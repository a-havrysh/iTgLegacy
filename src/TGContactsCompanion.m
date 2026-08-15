#import "TGContactsCompanion.h"
#import "TGUserModel.h"
#import "TGClient.h"
#import "TGClient+Contacts.h"
#import "TGClient+UserStatus.h"
#import "TGImageDecode.h"

static const CGFloat kTGContactsAvatarSide = 40.0f;
static const NSUInteger kTGContactsAvatarCount = 80;
static const NSUInteger kTGContactsAvatarBytes = 2 * 1024 * 1024;
static const NSTimeInterval kTGContactsCoalesce = 0.15;
static const NSTimeInterval kTGContactsSearchDelay = 0.35;
static const NSInteger kTGContactsServerSearchLimit = 30;

static NSUInteger TGContactsAvatarCost(UIImage *image) {
	CGImageRef bitmap = image.CGImage;
	if (!bitmap)
		return (NSUInteger)(image.size.width * image.size.height * 4);
	return (NSUInteger)(CGImageGetWidth(bitmap) * CGImageGetHeight(bitmap) * 4);
}

static NSString *TGContactsSortKey(TGUserModel *user) {
	if (user.lastName.length)
		return user.lastName;
	if (user.firstName.length)
		return user.firstName;
	return user.displayName ?: @"";
}

static NSString *TGContactsLetter(TGUserModel *user) {
	NSString *key = TGContactsSortKey(user);
	if (!key.length)
		return @"#";
	NSString *letter = [key substringToIndex:1].capitalizedString;
	if (![letter rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].length)
		return @"#";
	return letter;
}

static BOOL TGContactsMatches(TGUserModel *user, NSString *query) {
	if ([user.displayName rangeOfString:query options:NSCaseInsensitiveSearch].length)
		return YES;
	if ([user.username rangeOfString:query options:NSCaseInsensitiveSearch].length)
		return YES;
	if ([user.phoneNumber rangeOfString:query options:NSCaseInsensitiveSearch].length)
		return YES;
	return NO;
}

@interface TGContactsCompanion ()
@property (nonatomic, assign) TGContactsState state;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, assign) NSInteger importedContactCount;
@end

@implementation TGContactsCompanion {
	NSArray *_contacts;
	NSArray *_sections;
	NSArray *_sectionTitles;
	NSArray *_filtered;
	NSArray *_serverResults;
	NSString *_serverQuery;
	NSMutableSet *_closeFriendIds;
	NSMutableDictionary *_badges;
	NSMutableSet *_badgesRequested;
	NSCache *_avatars;
	NSMutableSet *_avatarsRequested;
	NSMutableDictionary *_pendingStatusPaths;
	BOOL _loading;
	BOOL _observing;
	BOOL _avatarNotifyScheduled;
}

- (id)init {
	self = [super init];
	if (!self)
		return nil;
	_state = TGContactsStateIdle;
	_importedContactCount = -1;
	_contacts = @[];
	_sections = @[];
	_sectionTitles = @[];
	_closeFriendIds = [NSMutableSet set];
	_badges = [NSMutableDictionary dictionary];
	_badgesRequested = [NSMutableSet set];
	_avatarsRequested = [NSMutableSet set];
	_pendingStatusPaths = [NSMutableDictionary dictionary];
	_avatars = [[NSCache alloc] init];
	_avatars.countLimit = kTGContactsAvatarCount;
	_avatars.totalCostLimit = kTGContactsAvatarBytes;
	return self;
}

- (void)dealloc {
	[self stopObserving];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

#pragma mark - observing

- (void)startObserving {
	if (_observing)
		return;
	_observing = YES;
	NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];
	[centre addObserver:self
			   selector:@selector(handleUserStatusNotification:)
				   name:TGUserStatusDidChangeNotification
				 object:nil];
	[centre addObserver:self
			   selector:@selector(handleMemoryWarning:)
				   name:UIApplicationDidReceiveMemoryWarningNotification
				 object:nil];
}

- (void)stopObserving {
	if (!_observing)
		return;
	_observing = NO;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleMemoryWarning:(NSNotification *)note {
	[self clearAvatarCache];
}

#pragma mark - state

- (void)setStateAndTell:(TGContactsState)state {
	if (_state == state)
		return;
	_state = state;
	if ([self.delegate respondsToSelector:@selector(contactsCompanionDidChangeState:)])
		[self.delegate contactsCompanionDidChangeState:self];
}

#pragma mark - loading

- (void)reload {
	if (_loading)
		return;
	_loading = YES;
	if (!self.loaded)
		[self setStateAndTell:TGContactsStateLoading];

	__weak TGContactsCompanion *weakSelf = self;
	[[TGClient shared] contactsWithCompletion:^(NSArray *users){
		TGContactsCompanion *me = weakSelf;
		if (!me)
			return;
		[me handleContactsResponse:users];
	}];

	if (!self.pickerMode){
		[[TGClient shared] contactCloseFriendsWithCompletion:^(NSArray *users){
			TGContactsCompanion *me = weakSelf;
			if (!me)
				return;
			[me handleCloseFriendsResponse:users];
		}];
		[[TGClient shared] importedContactCountWithCompletion:^(NSInteger count){
			TGContactsCompanion *me = weakSelf;
			if (!me)
				return;
			me.importedContactCount = count;
		}];
	}
}

- (void)handleContactsResponse:(NSArray *)users {
	_loading = NO;
	self.loaded = YES;

	if (![users isKindOfClass:NSArray.class]){
		if (_contacts.count == 0)
			[self setStateAndTell:TGContactsStateFailed];
		return;
	}

	NSArray *oldTitles = _sectionTitles;
	NSArray *oldSections = _sections;
	BOOL wasSearching = (_filtered != nil);

	_contacts = [self sorted:[TGUserModel arrayFromDictionaries:users]];
	[self applyFilter];
	[self rebuildSections];

	[self setStateAndTell:_contacts.count ? TGContactsStateLoaded : TGContactsStateEmpty];

	if (wasSearching || _filtered){
		[self tellReload];
		return;
	}
	if (![oldTitles isEqualToArray:_sectionTitles] || oldSections.count == 0){
		[self tellReload];
		return;
	}
	[self tellDiffAgainstSections:oldSections];
}

- (void)handleCloseFriendsResponse:(NSArray *)users {
	NSMutableSet *ids = [NSMutableSet set];
	if ([users isKindOfClass:NSArray.class]){
		for (id entry in users){
			TGUserModel *user = [TGUserModel fromDictionary:entry];
			if (user)
				[ids addObject:@(user.userId)];
		}
	}
	if ([ids isEqualToSet:_closeFriendIds])
		return;
	NSMutableSet *union_ = [NSMutableSet setWithSet:ids];
	[union_ unionSet:_closeFriendIds];
	NSMutableSet *both = [NSMutableSet setWithSet:ids];
	[both intersectSet:_closeFriendIds];
	NSMutableSet *changed = union_;
	[changed minusSet:both];
	_closeFriendIds = ids;
	[self tellUpdatedUserIds:changed];
}

#pragma mark - sorting and sectioning

- (NSArray *)sorted:(NSArray *)users {
	return [users sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
		TGUserModel *left = a;
		TGUserModel *right = b;
		NSComparisonResult result = [TGContactsSortKey(left)
				caseInsensitiveCompare:TGContactsSortKey(right)];
		if (result != NSOrderedSame)
			return result;
		if (!left.firstName.length || !right.firstName.length)
			return NSOrderedSame;
		return [left.firstName caseInsensitiveCompare:right.firstName];
	}];
}

- (void)applyFilter {
	NSString *query = [self.searchQuery
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!query.length){
		_filtered = nil;
		return;
	}
	NSMutableArray *out = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	for (TGUserModel *user in _contacts){
		if (!TGContactsMatches(user, query))
			continue;
		[out addObject:user];
		[seen addObject:@(user.userId)];
	}
	if ([_serverQuery isEqualToString:query]){
		for (TGUserModel *user in _serverResults){
			NSNumber *key = @(user.userId);
			if (user.userId == 0 || [seen containsObject:key])
				continue;
			[seen addObject:key];
			[out addObject:user];
		}
	}
	_filtered = out;
}

- (void)rebuildSections {
	if (_filtered){
		_sections = @[_filtered];
		_sectionTitles = @[[NSNull null]];
		return;
	}
	NSMutableArray *titles = [NSMutableArray array];
	NSMutableArray *groups = [NSMutableArray array];
	for (TGUserModel *user in _contacts){
		NSString *letter = TGContactsLetter(user);
		if (![titles.lastObject isEqual:letter]){
			[titles addObject:letter];
			[groups addObject:[NSMutableArray array]];
		}
		[groups.lastObject addObject:user];
	}
	_sectionTitles = titles;
	_sections = groups;
}

#pragma mark - delegate traffic

- (void)tellReload {
	if ([self.delegate respondsToSelector:@selector(contactsCompanionDidReloadContacts:)])
		[self.delegate contactsCompanionDidReloadContacts:self];
}

- (void)tellDiffAgainstSections:(NSArray *)oldSections {
	if (![self.delegate respondsToSelector:
			@selector(contactsCompanion:didInsertRowsAtPaths:removeRowsAtPaths:)]){
		[self tellReload];
		return;
	}
	NSMutableArray *inserted = [NSMutableArray array];
	NSMutableArray *removed = [NSMutableArray array];
	for (NSUInteger s = 0; s < _sections.count && s < oldSections.count; s++){
		NSArray *before = oldSections[s];
		NSArray *after = _sections[s];
		NSMutableSet *afterIds = [NSMutableSet set];
		for (TGUserModel *user in after)
			[afterIds addObject:@(user.userId)];
		NSMutableSet *beforeIds = [NSMutableSet set];
		for (TGUserModel *user in before)
			[beforeIds addObject:@(user.userId)];
		for (NSUInteger r = 0; r < before.count; r++){
			TGUserModel *user = before[r];
			if (![afterIds containsObject:@(user.userId)])
				[removed addObject:[NSIndexPath indexPathForRow:(NSInteger)r
													  inSection:(NSInteger)s]];
		}
		for (NSUInteger r = 0; r < after.count; r++){
			TGUserModel *user = after[r];
			if (![beforeIds containsObject:@(user.userId)])
				[inserted addObject:[NSIndexPath indexPathForRow:(NSInteger)r
													   inSection:(NSInteger)s]];
		}
	}
	if (!inserted.count && !removed.count)
		return;
	[self.delegate contactsCompanion:self
				didInsertRowsAtPaths:inserted
				   removeRowsAtPaths:removed];
}

- (void)tellUpdatedUserIds:(NSSet *)userIds {
	if (!userIds.count)
		return;
	if (![self.delegate respondsToSelector:@selector(contactsCompanion:didUpdateRowsAtPaths:)])
		return;
	NSMutableArray *paths = [NSMutableArray array];
	for (NSNumber *userId in userIds){
		NSIndexPath *path = [self indexPathForUserId:userId.longLongValue];
		if (path)
			[paths addObject:path];
	}
	if (paths.count)
		[self.delegate contactsCompanion:self didUpdateRowsAtPaths:paths];
}

- (void)scheduleUpdateForUserId:(int64_t)userId {
	_pendingStatusPaths[@(userId)] = @(YES);
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(flushPendingUpdates)
											   object:nil];
	[self performSelector:@selector(flushPendingUpdates)
			   withObject:nil
			   afterDelay:kTGContactsCoalesce];
}

- (void)flushPendingUpdates {
	NSSet *ids = [NSSet setWithArray:_pendingStatusPaths.allKeys];
	[_pendingStatusPaths removeAllObjects];
	[self tellUpdatedUserIds:ids];
}

#pragma mark - status subscription

- (void)handleUserStatusNotification:(NSNotification *)note {
	int64_t userId = [note.userInfo[@"userId"] longLongValue];
	NSDictionary *status = note.userInfo[@"status"];
	if (userId == 0 || ![status isKindOfClass:NSDictionary.class])
		return;

	NSUInteger index = NSNotFound;
	for (NSUInteger i = 0; i < _contacts.count; i++){
		TGUserModel *candidate = _contacts[i];
		if (candidate.userId == userId){
			index = i;
			break;
		}
	}
	if (index == NSNotFound)
		return;

	TGUserModel *replacement = [self userModelFrom:_contacts[index] status:status];
	if (!replacement)
		return;
	NSMutableArray *next = [_contacts mutableCopy];
	next[index] = replacement;
	_contacts = next;
	[self applyFilter];
	[self rebuildSections];
	[self scheduleUpdateForUserId:userId];
}

- (TGUserModel *)userModelFrom:(TGUserModel *)user status:(NSDictionary *)status {
	NSMutableDictionary *flat = [NSMutableDictionary dictionaryWithCapacity:9];
	flat[@"id"] = @(user.userId);
	if (user.firstName.length)
		flat[@"first_name"] = user.firstName;
	if (user.lastName.length)
		flat[@"last_name"] = user.lastName;
	if (user.phoneNumber.length)
		flat[@"phone"] = user.phoneNumber;
	if (user.username.length)
		flat[@"username"] = user.username;
	if (user.photoFileId)
		flat[@"photoFileId"] = user.photoFileId;
	if (user.photoUniqueId.length)
		flat[@"photoUniqueId"] = user.photoUniqueId;
	flat[@"isOnline"] = status[@"isOnline"] ?: @(NO);
	flat[@"statusText"] = status[@"text"] ?: @"";
	flat[@"statusRank"] = status[@"rank"] ?: @(0);
	return [TGUserModel fromDictionary:flat];
}

#pragma mark - rows

- (NSInteger)numberOfSections {
	return (NSInteger)_sections.count;
}

- (NSInteger)numberOfRowsInSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)_sections.count)
		return 0;
	return (NSInteger)[_sections[(NSUInteger)section] count];
}

- (NSString *)titleForSection:(NSInteger)section {
	if (_filtered)
		return nil;
	if (section <= 0 || section >= (NSInteger)_sectionTitles.count)
		return nil;
	id title = _sectionTitles[(NSUInteger)section];
	return [title isKindOfClass:NSString.class] ? title : nil;
}

- (NSArray *)sectionIndexTitles {
	if (_filtered)
		return nil;
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:_sectionTitles.count];
	for (id title in _sectionTitles)
		[out addObject:[title isKindOfClass:NSString.class] ? title : @""];
	return out;
}

- (TGUserModel *)userAtIndexPath:(NSIndexPath *)indexPath {
	if (!indexPath || indexPath.section < 0
			|| indexPath.section >= (NSInteger)_sections.count)
		return nil;
	NSArray *rows = _sections[(NSUInteger)indexPath.section];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count)
		return nil;
	return rows[(NSUInteger)indexPath.row];
}

- (NSIndexPath *)indexPathForUserId:(int64_t)userId {
	for (NSUInteger s = 0; s < _sections.count; s++){
		NSArray *rows = _sections[s];
		for (NSUInteger r = 0; r < rows.count; r++){
			TGUserModel *candidate = rows[r];
			if (candidate.userId == userId)
				return [NSIndexPath indexPathForRow:(NSInteger)r inSection:(NSInteger)s];
		}
	}
	return nil;
}

- (NSArray *)allContacts {
	return _contacts;
}

#pragma mark - search

- (void)setSearchQuery:(NSString *)query {
	NSString *trimmed = [query
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!trimmed.length)
		trimmed = nil;
	if (trimmed == _searchQuery || [trimmed isEqualToString:_searchQuery])
		return;
	_searchQuery = [trimmed copy];
	[self applyFilter];
	[self rebuildSections];
	[self tellReload];

	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runServerSearch)
											   object:nil];
	if (self.pickerMode || _searchQuery.length < 2)
		return;
	[self performSelector:@selector(runServerSearch)
			   withObject:nil
			   afterDelay:kTGContactsSearchDelay];
}

- (void)runServerSearch {
	NSString *query = self.searchQuery;
	if (query.length < 2)
		return;
	__weak TGContactsCompanion *weakSelf = self;
	[[TGClient shared] searchContacts:query
								limit:kTGContactsServerSearchLimit
						   completion:^(NSArray *users){
		TGContactsCompanion *me = weakSelf;
		if (!me)
			return;
		[me handleServerSearchResults:users forQuery:query];
	}];
}

- (void)handleServerSearchResults:(NSArray *)users forQuery:(NSString *)query {
	if (![query isEqualToString:self.searchQuery])
		return;
	_serverQuery = [query copy];
	_serverResults = [users isKindOfClass:NSArray.class]
			? [TGUserModel arrayFromDictionaries:users] : @[];
	[self applyFilter];
	[self rebuildSections];
	[self tellReload];
}

#pragma mark - per-user extras

- (BOOL)isCloseFriendUserId:(int64_t)userId {
	return [_closeFriendIds containsObject:@(userId)];
}

- (NSDictionary *)badgesForUserId:(int64_t)userId {
	NSNumber *key = @(userId);
	NSDictionary *cached = _badges[key];
	if (cached)
		return cached;
	if ([_badgesRequested containsObject:key])
		return nil;
	[_badgesRequested addObject:key];

	__weak TGContactsCompanion *weakSelf = self;
	[[TGClient shared] badgesForUser:userId completion:^(NSDictionary *badges){
		TGContactsCompanion *me = weakSelf;
		if (!me)
			return;
		[me storeBadges:badges forUserId:userId];
	}];
	return nil;
}

- (void)storeBadges:(NSDictionary *)badges forUserId:(int64_t)userId {
	_badges[@(userId)] = [badges isKindOfClass:NSDictionary.class] ? badges : @{};
	[self scheduleUpdateForUserId:userId];
}

- (BOOL)badgeFlag:(NSString *)name forUserId:(int64_t)userId {
	NSDictionary *badges = [self badgesForUserId:userId];
	id value = badges[name];
	return [value isKindOfClass:NSNumber.class] ? [value boolValue] : NO;
}

- (BOOL)isVerifiedUserId:(int64_t)userId {
	return [self badgeFlag:@"isVerified" forUserId:userId];
}

- (BOOL)isPremiumUserId:(int64_t)userId {
	return [self badgeFlag:@"isPremium" forUserId:userId];
}

- (BOOL)isScamUserId:(int64_t)userId {
	return [self badgeFlag:@"isScam" forUserId:userId];
}

- (BOOL)isFakeUserId:(int64_t)userId {
	return [self badgeFlag:@"isFake" forUserId:userId];
}

#pragma mark - avatars

- (NSString *)thumbDirectory {
	NSString *dir = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, NSUserDomainMask, YES).firstObject
					stringByAppendingPathComponent:@"ContactCompanionThumbs"];
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:dir])
		[fm createDirectoryAtPath:dir
	  withIntermediateDirectories:YES
					   attributes:nil
							error:nil];
	return dir;
}

- (NSString *)thumbPathForUser:(TGUserModel *)user {
	NSString *stem = user.photoUniqueId.length
			? user.photoUniqueId
			: [NSString stringWithFormat:@"f%@", user.photoFileId];
	stem = [stem stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
	return [[self thumbDirectory] stringByAppendingPathComponent:
			[stem stringByAppendingPathExtension:@"png"]];
}

- (UIImage *)avatarForUser:(TGUserModel *)user {
	NSNumber *fileId = user.photoFileId;
	if (!fileId)
		return nil;
	UIImage *cached = [_avatars objectForKey:fileId];
	if (cached)
		return cached;

	NSString *path = [self thumbPathForUser:user];
	UIImage *fromDisk = [UIImage imageWithContentsOfFile:path];
	if (fromDisk){
		[_avatars setObject:fromDisk forKey:fileId cost:TGContactsAvatarCost(fromDisk)];
		return fromDisk;
	}
	[self requestAvatarForFileId:fileId path:path];
	return nil;
}

- (void)requestAvatarForFileId:(NSNumber *)fileId path:(NSString *)path {
	if (!fileId || !path.length || [_avatarsRequested containsObject:fileId])
		return;
	[_avatarsRequested addObject:fileId];

	__weak TGContactsCompanion *weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *filePath){
		TGContactsCompanion *me = weakSelf;
		if (!me)
			return;
		if (!filePath.length){
			[me forgetAvatarRequest:fileId];
			return;
		}
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			@autoreleasepool {
				UIImage *thumb = TGDecodeSquareThumbnail(filePath, kTGContactsAvatarSide);
				if (thumb)
					[UIImagePNGRepresentation(thumb) writeToFile:path atomically:YES];
				dispatch_async(dispatch_get_main_queue(), ^{
					TGContactsCompanion *inner = weakSelf;
					if (!inner)
						return;
					[inner storeAvatar:thumb forFileId:fileId];
				});
			}
		});
	}];
}

- (void)forgetAvatarRequest:(NSNumber *)fileId {
	[_avatarsRequested removeObject:fileId];
}

- (void)storeAvatar:(UIImage *)image forFileId:(NSNumber *)fileId {
	if (!image){
		[self forgetAvatarRequest:fileId];
		return;
	}
	[_avatars setObject:image forKey:fileId cost:TGContactsAvatarCost(image)];
	if (_avatarNotifyScheduled)
		return;
	_avatarNotifyScheduled = YES;
	[self performSelector:@selector(flushAvatarNotification)
			   withObject:nil
			   afterDelay:kTGContactsCoalesce];
}

- (void)flushAvatarNotification {
	_avatarNotifyScheduled = NO;
	if ([self.delegate respondsToSelector:@selector(contactsCompanionDidUpdateAvatars:)])
		[self.delegate contactsCompanionDidUpdateAvatars:self];
}

- (void)clearAvatarCache {
	[_avatars removeAllObjects];
}

@end

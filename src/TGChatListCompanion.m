#import "TGChatListCompanion.h"

#import "TGChatModel.h"
#import "TGFolderModel.h"
#import "TGClient.h"

#import <UIKit/UIKit.h>

static const NSInteger TGChatListCompanionPageSize = 60;
static const NSTimeInterval TGChatListCompanionFolderSweepInterval = 5.0;

static BOOL TGChatListCompanionRowsEqual(TGChatModel *a, TGChatModel *b) {
	if (a == b)
		return YES;
	if (!a || !b)
		return NO;
	if (a.chatId != b.chatId)
		return NO;
	if (a.date != b.date || a.order != b.order || a.archiveOrder != b.archiveOrder)
		return NO;
	if (a.unreadCount != b.unreadCount)
		return NO;
	if (a.photoFileId != b.photoFileId)
		return NO;
	if (a.markedUnread != b.markedUnread || a.pinned != b.pinned || a.muted != b.muted)
		return NO;
	if (a.online != b.online || a.outgoing != b.outgoing || a.outgoingRead != b.outgoingRead)
		return NO;
	if (a.title != b.title && ![a.title isEqualToString:b.title])
		return NO;
	if (a.previewText != b.previewText && ![a.previewText isEqualToString:b.previewText])
		return NO;
	if (a.draftText != b.draftText && ![a.draftText isEqualToString:b.draftText])
		return NO;
	if (a.actionText != b.actionText && ![a.actionText isEqualToString:b.actionText])
		return NO;
	return YES;
}

@interface TGChatListCompanion ()
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, strong) NSArray *folders;
@property (nonatomic, assign) TGChatListCompanionState state;
@property (nonatomic, copy) NSString *lastErrorText;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) NSInteger folderLimit;
@property (nonatomic, assign) NSUInteger fetchToken;
@property (nonatomic, strong) NSMutableDictionary *listUnread;
@property (nonatomic, assign) NSTimeInterval lastFolderSweep;
@end

@implementation TGChatListCompanion

- (id)init {
	self = [super init];
	if (self){
		_chats = @[];
		_folders = @[];
		_listId = TGChatListMain;
		_state = TGChatListCompanionStateIdle;
		_folderLimit = TGChatListCompanionPageSize;
		_listUnread = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc {
	[self stop];
}

#pragma mark - configuration

- (void)setListId:(TGChatListId)listId {
	if (_listId == listId)
		return;
	_listId = listId;
	_folderLimit = TGChatListCompanionPageSize;
	_loadingMore = NO;
	self.chats = @[];
	[self notifyReplace];
	if (self.running){
		[self setState:TGChatListCompanionStateLoading];
		[self fetchReplacing:YES];
	}
}

- (void)setShowsArchive:(BOOL)showsArchive {
	self.listId = showsArchive ? TGChatListArchive : TGChatListMain;
}

- (BOOL)showsArchive {
	return self.listId == TGChatListArchive;
}

- (void)setFolderId:(NSInteger)folderId {
	self.listId = folderId != 0 ? (TGChatListId)folderId : TGChatListMain;
}

- (NSInteger)folderId {
	return (self.listId > 0) ? (NSInteger)self.listId : 0;
}

- (NSString *)listTitle {
	if (self.listId == TGChatListArchive)
		return @"Archived";
	TGFolderModel *folder = [self currentFolder];
	if (folder.title.length)
		return folder.title;
	return @"Messages";
}

#pragma mark - lifecycle

- (void)start {
	if (self.running)
		return;
	self.running = YES;

	__weak TGChatListCompanion *weakSelf = self;
	[TGClient shared].onChatsChanged = ^{
		[weakSelf clientChatsChanged];
	};
	[TGClient shared].onArchiveChanged = ^{
		[weakSelf clientArchiveChanged];
	};
	[[TGClient shared] beginObservingFolderChanges];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(clientFoldersChanged)
												 name:TGChatFoldersDidChangeNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(purgeCaches)
												 name:UIApplicationDidReceiveMemoryWarningNotification
											   object:nil];

	[self reloadFolders];
	[self setState:TGChatListCompanionStateLoading];
	[self fetchReplacing:YES];
}

- (void)stop {
	if (!self.running)
		return;
	self.running = NO;
	self.fetchToken++;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[TGClient shared].onChatsChanged = nil;
	[TGClient shared].onArchiveChanged = nil;
}

- (void)refresh {
	[self reloadFolders];
	[self fetchReplacing:NO];
}

- (void)loadMore {
	if (self.loadingMore || !self.running)
		return;
	if (self.listId > 0){
		if ((NSInteger)self.chats.count < self.folderLimit)
			return;
		self.loadingMore = YES;
		self.folderLimit += TGChatListCompanionPageSize;
		[[TGClient shared] loadMoreChatsInList:self.listId limit:TGChatListCompanionPageSize];
		[self fetchReplacing:NO];
		return;
	}

	self.loadingMore = YES;
	[[TGClient shared] loadMoreChatsInList:self.listId limit:TGChatListCompanionPageSize];
	__weak TGChatListCompanion *weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		weakSelf.loadingMore = NO;
	});
}

- (void)purgeCaches {
	[self.listUnread removeAllObjects];
	self.lastFolderSweep = 0;
	[self notifyUnread];
}

#pragma mark - fetching

- (void)fetchReplacing:(BOOL)replacing {
	if (self.listId == TGChatListArchive){
		[self applyRows:[TGChatModel arrayFromDictionaries:[TGClient shared].archivedChats]
			  replacing:replacing];
		self.loadingMore = NO;
		[self refreshUnreadCounters];
		return;
	}

	if (self.listId > 0){
		self.fetchToken++;
		NSUInteger token = self.fetchToken;
		__weak TGChatListCompanion *weakSelf = self;
		[[TGClient shared] chatsInList:self.listId limit:self.folderLimit
							completion:^(NSArray *reply){
			TGChatListCompanion *me = weakSelf;
			if (!me || me.fetchToken != token)
				return;
			me.loadingMore = NO;
			[me applyRows:[TGChatModel arrayFromDictionaries:reply] replacing:replacing];
			[me refreshUnreadCounters];
		}];
		return;
	}

	[self applyRows:[TGChatModel arrayFromDictionaries:[TGClient shared].chats]
		  replacing:replacing];
	self.loadingMore = NO;
	[self refreshUnreadCounters];
}

- (void)applyRows:(NSArray *)rows replacing:(BOOL)replacing {
	NSArray *next = rows ?: @[];
	NSArray *previous = self.chats;

	if (replacing || previous.count == 0 || next.count == 0){
		BOOL identical = (previous.count == next.count);
		if (identical){
			for (NSUInteger i = 0; i < next.count; i++){
				if (!TGChatListCompanionRowsEqual(previous[i], next[i])){
					identical = NO;
					break;
				}
			}
		}
		self.chats = next;
		if (!identical)
			[self notifyReplace];
		[self settleStateAfterFetch];
		return;
	}

	NSMutableDictionary *previousIndexById =
			[NSMutableDictionary dictionaryWithCapacity:previous.count];
	for (NSUInteger i = 0; i < previous.count; i++){
		TGChatModel *row = previous[i];
		previousIndexById[@(row.chatId)] = @(i);
	}
	NSMutableSet *nextIds = [NSMutableSet setWithCapacity:next.count];
	for (TGChatModel *row in next)
		[nextIds addObject:@(row.chatId)];

	NSMutableIndexSet *removed = [NSMutableIndexSet indexSet];
	NSMutableArray *survivingOldIds = [NSMutableArray array];
	for (NSUInteger i = 0; i < previous.count; i++){
		TGChatModel *row = previous[i];
		if ([nextIds containsObject:@(row.chatId)])
			[survivingOldIds addObject:@(row.chatId)];
		else
			[removed addIndex:i];
	}

	NSMutableIndexSet *inserted = [NSMutableIndexSet indexSet];
	NSMutableIndexSet *reloaded = [NSMutableIndexSet indexSet];
	NSMutableArray *survivingNewIds = [NSMutableArray array];
	for (NSUInteger i = 0; i < next.count; i++){
		TGChatModel *row = next[i];
		NSNumber *oldIndex = previousIndexById[@(row.chatId)];
		if (!oldIndex){
			[inserted addIndex:i];
			continue;
		}
		[survivingNewIds addObject:@(row.chatId)];
		if (!TGChatListCompanionRowsEqual(previous[[oldIndex unsignedIntegerValue]], row))
			[reloaded addIndex:i];
	}

	self.chats = next;

	if (![survivingOldIds isEqualToArray:survivingNewIds]){
		[self notifyReplace];
		[self settleStateAfterFetch];
		return;
	}

	if (inserted.count || removed.count || reloaded.count){
		id<TGChatListCompanionDelegate> delegate = self.delegate;
		if ([delegate respondsToSelector:@selector(chatListCompanion:didUpdateChatsInsert:remove:reload:)])
			[delegate chatListCompanion:self
				   didUpdateChatsInsert:inserted
								 remove:removed
								 reload:reloaded];
	}
	[self settleStateAfterFetch];
}

- (void)settleStateAfterFetch {
	if (self.chats.count)
		[self setState:TGChatListCompanionStateLoaded];
	else
		[self setState:TGChatListCompanionStateEmpty];
}

- (void)setState:(TGChatListCompanionState)state {
	if (_state == state)
		return;
	_state = state;
	if (state != TGChatListCompanionStateFailed)
		self.lastErrorText = nil;
	id<TGChatListCompanionDelegate> delegate = self.delegate;
	if ([delegate respondsToSelector:@selector(chatListCompanionDidChangeState:)])
		[delegate chatListCompanionDidChangeState:self];
}

- (void)notifyReplace {
	id<TGChatListCompanionDelegate> delegate = self.delegate;
	if ([delegate respondsToSelector:@selector(chatListCompanionDidReplaceChats:)])
		[delegate chatListCompanionDidReplaceChats:self];
}

- (void)notifyUnread {
	id<TGChatListCompanionDelegate> delegate = self.delegate;
	if ([delegate respondsToSelector:@selector(chatListCompanionDidChangeUnreadCounts:)])
		[delegate chatListCompanionDidChangeUnreadCounts:self];
}

#pragma mark - client callbacks

- (void)clientChatsChanged {
	if (!self.running)
		return;
	if (self.listId == TGChatListArchive){
		[self refreshUnreadCounters];
		return;
	}
	[self fetchReplacing:NO];
}

- (void)clientArchiveChanged {
	if (!self.running)
		return;
	if (self.listId == TGChatListArchive)
		[self fetchReplacing:NO];
	else
		[self refreshUnreadCounters];
}

- (void)clientFoldersChanged {
	if (!self.running)
		return;
	[self reloadFolders];
	id<TGChatListCompanionDelegate> delegate = self.delegate;
	if ([delegate respondsToSelector:@selector(chatListCompanionDidChangeFolders:)])
		[delegate chatListCompanionDidChangeFolders:self];
	if (self.listId > 0 && ![self currentFolder]){
		self.listId = TGChatListMain;
		return;
	}
	if (self.listId > 0)
		[self fetchReplacing:NO];
}

- (void)reloadFolders {
	self.folders = [TGFolderModel arrayFromDictionaries:[TGClient shared].folders] ?: @[];
}

#pragma mark - rows

- (TGChatModel *)chatAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.chats.count)
		return nil;
	return [self.chats objectAtIndex:(NSUInteger)index];
}

- (NSInteger)indexOfChatId:(int64_t)chatId {
	NSUInteger count = self.chats.count;
	for (NSUInteger i = 0; i < count; i++){
		TGChatModel *row = [self.chats objectAtIndex:i];
		if (row.chatId == chatId)
			return (NSInteger)i;
	}
	return NSNotFound;
}

- (TGChatModel *)chatWithId:(int64_t)chatId {
	NSInteger index = [self indexOfChatId:chatId];
	return index == NSNotFound ? nil : [self chatAtIndex:index];
}

#pragma mark - folders

- (TGFolderModel *)currentFolder {
	if (self.listId <= 0)
		return nil;
	for (TGFolderModel *folder in self.folders){
		if (folder.folderId == (int64_t)self.listId)
			return folder;
	}
	return nil;
}

#pragma mark - unread

- (void)refreshUnreadCounters {
	TGClient *client = [TGClient shared];
	NSInteger before = [self totalUnreadSignature];

	NSDictionary *main = [client unreadSummaryForList:TGChatListMain];
	if ([main isKindOfClass:[NSDictionary class]] &&
		[main[@"messages"] isKindOfClass:[NSNumber class]])
		self.listUnread[@(TGChatListMain)] = main[@"messages"];

	NSDictionary *archive = [client unreadSummaryForList:TGChatListArchive];
	if ([archive isKindOfClass:[NSDictionary class]] &&
		[archive[@"messages"] isKindOfClass:[NSNumber class]])
		self.listUnread[@(TGChatListArchive)] = archive[@"messages"];

	if ([self totalUnreadSignature] != before)
		[self notifyUnread];

	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - self.lastFolderSweep < TGChatListCompanionFolderSweepInterval)
		return;
	self.lastFolderSweep = now;

	__weak TGChatListCompanion *weakSelf = self;
	for (TGFolderModel *folder in self.folders){
		NSInteger listId = (NSInteger)folder.folderId;
		if (listId <= 0)
			continue;
		[client chatsInList:(TGChatListId)listId limit:100 completion:^(NSArray *reply){
			TGChatListCompanion *me = weakSelf;
			if (!me)
				return;
			NSInteger total = 0;
			for (TGChatModel *row in [TGChatModel arrayFromDictionaries:reply])
				total += row.unreadCount;
			NSNumber *key = @(listId);
			if ([me.listUnread[key] integerValue] == total)
				return;
			me.listUnread[key] = @(total);
			[me notifyUnread];
		}];
	}
}

- (NSInteger)totalUnreadSignature {
	NSInteger sum = 0;
	for (NSNumber *value in [self.listUnread allValues])
		sum += [value integerValue] + 1;
	return sum;
}

- (NSInteger)unreadCountForList:(TGChatListId)list {
	return [self.listUnread[@(list)] integerValue];
}

- (NSInteger)unreadCount {
	return [self unreadCountForList:self.listId];
}

- (NSInteger)archivedChatCount {
	NSArray *archived = [TGClient shared].archivedChats;
	return [archived isKindOfClass:[NSArray class]] ? (NSInteger)archived.count : 0;
}

- (NSInteger)archiveUnreadCount {
	return [self unreadCountForList:TGChatListArchive];
}

- (void)markCurrentListAsRead {
	[[TGClient shared] markListAsRead:self.listId];
	[self refresh];
}

@end

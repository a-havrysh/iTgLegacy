#import "TGProfileCompanion.h"

#import <UIKit/UIKit.h>

#import "TGClient.h"
#import "TGClient+Channels.h"
#import "TGClient+ChatList.h"
#import "TGClient+ChatManagement.h"
#import "TGClient+Contacts.h"
#import "TGClient+Groups.h"
#import "TGClient+UserStatus.h"

#import "TGChatModel.h"
#import "TGMemberModel.h"
#import "TGUserModel.h"

static NSString *TGProfileCompanionText(id value) {
	if (![value isKindOfClass:[NSString class]])
		return nil;
	NSString *text = (NSString *)value;
	return [text length] ? text : nil;
}

static BOOL TGProfileCompanionBool(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value boolValue];
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value boolValue];
	return NO;
}

static NSInteger TGProfileCompanionInteger(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value integerValue];
	if ([value isKindOfClass:[NSString class]])
		return (NSInteger)[(NSString *)value longLongValue];
	return 0;
}

static int64_t TGProfileCompanionIdentifier(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value longLongValue];
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value longLongValue];
	return 0;
}

@interface TGProfileCompanion () {
@private
	int64_t _userId;
	int64_t _chatId;
	BOOL _cancelled;

	TGProfileLoadState _identityState;
	TGProfileLoadState _detailsState;
	TGProfileLoadState _mediaState;
	TGProfileLoadState _membersState;
	TGProfileLoadState _managementState;
	TGProfileLoadState _commonGroupsState;

	TGProfileLoadState _photoState;
	TGProfileLoadState _fileState;

	TGUserModel *_user;
	NSString *_displayName;
	NSInteger _photoFileId;
	BOOL _muted;

	NSString *_bio;
	NSString *_birthdayText;
	NSString *_note;
	BOOL _noteLoaded;
	NSString *_phoneNumber;
	NSString *_username;
	NSString *_contactRelation;
	BOOL _isContact;
	BOOL _isBlocked;
	BOOL _blockedKnown;

	NSArray *_commonGroups;
	NSInteger _commonGroupCount;
	NSInteger _reportedCommonGroupCount;
	NSArray *_gifts;

	NSInteger _photoCount;
	NSInteger _fileCount;

	NSString *_title;
	NSString *_chatDescription;
	NSString *_primaryInviteLink;
	NSInteger _primaryLinkJoinCount;

	NSArray *_members;

	NSInteger _memberCount;
	NSInteger _adminCount;
	NSInteger _inviteLinkCount;
	NSInteger _pendingJoinRequests;
	NSInteger _onlineCount;

	BOOL _managementLoaded;
	BOOL _managementFlagsLoaded;
	BOOL _isChannel;
	BOOL _isSupergroup;
	BOOL _isForum;
	BOOL _isAdmin;
	BOOL _canEditChat;
	BOOL _canListMembers;
	BOOL _canGetStatistics;

	NSInteger _slowModeDelay;
	BOOL _historyAvailable;
	BOOL _hiddenMembers;
	BOOL _canHideMembers;
	BOOL _antiSpam;
	BOOL _canToggleAntiSpam;
	BOOL _protectedContent;

	BOOL _signaturesLoaded;
	BOOL _signMessages;
	BOOL _showAuthorProfiles;

	BOOL _discussionLoaded;
	int64_t _discussionChatId;
	NSString *_discussionTitle;

	BOOL _boostsLoaded;
	NSInteger _boostLevel;
}
@end

@implementation TGProfileCompanion

@synthesize delegate = _delegate;
@synthesize userId = _userId;
@synthesize chatId = _chatId;
@synthesize user = _user;
@synthesize displayName = _displayName;
@synthesize photoFileId = _photoFileId;
@synthesize muted = _muted;
@synthesize bio = _bio;
@synthesize birthdayText = _birthdayText;
@synthesize note = _note;
@synthesize noteLoaded = _noteLoaded;
@synthesize phoneNumber = _phoneNumber;
@synthesize username = _username;
@synthesize contactRelation = _contactRelation;
@synthesize isContact = _isContact;
@synthesize isBlocked = _isBlocked;
@synthesize blockedKnown = _blockedKnown;
@synthesize commonGroups = _commonGroups;
@synthesize gifts = _gifts;
@synthesize photoCount = _photoCount;
@synthesize fileCount = _fileCount;
@synthesize title = _title;
@synthesize chatDescription = _chatDescription;
@synthesize primaryInviteLink = _primaryInviteLink;
@synthesize primaryLinkJoinCount = _primaryLinkJoinCount;
@synthesize members = _members;
@synthesize memberCount = _memberCount;
@synthesize adminCount = _adminCount;
@synthesize inviteLinkCount = _inviteLinkCount;
@synthesize pendingJoinRequests = _pendingJoinRequests;
@synthesize onlineCount = _onlineCount;
@synthesize managementLoaded = _managementLoaded;
@synthesize managementFlagsLoaded = _managementFlagsLoaded;
@synthesize isChannel = _isChannel;
@synthesize isSupergroup = _isSupergroup;
@synthesize isForum = _isForum;
@synthesize isAdmin = _isAdmin;
@synthesize canEditChat = _canEditChat;
@synthesize canListMembers = _canListMembers;
@synthesize canGetStatistics = _canGetStatistics;
@synthesize slowModeDelay = _slowModeDelay;
@synthesize historyAvailable = _historyAvailable;
@synthesize hiddenMembers = _hiddenMembers;
@synthesize canHideMembers = _canHideMembers;
@synthesize antiSpam = _antiSpam;
@synthesize canToggleAntiSpam = _canToggleAntiSpam;
@synthesize protectedContent = _protectedContent;
@synthesize signaturesLoaded = _signaturesLoaded;
@synthesize signMessages = _signMessages;
@synthesize showAuthorProfiles = _showAuthorProfiles;
@synthesize discussionLoaded = _discussionLoaded;
@synthesize discussionChatId = _discussionChatId;
@synthesize discussionTitle = _discussionTitle;
@synthesize boostsLoaded = _boostsLoaded;
@synthesize boostLevel = _boostLevel;

#pragma mark - lifecycle

- (id)initWithUserId:(int64_t)userId chatId:(int64_t)chatId {
	self = [super init];
	if (!self)
		return nil;
	_userId = userId;
	_chatId = chatId;
	[self commonInit];
	return self;
}

- (id)initWithChatId:(int64_t)chatId {
	self = [super init];
	if (!self)
		return nil;
	_userId = 0;
	_chatId = chatId;
	[self commonInit];
	return self;
}

- (id)init {
	return [self initWithChatId:0];
}

- (void)commonInit {
	_members = [NSArray array];
	_commonGroups = [NSArray array];
	_gifts = [NSArray array];
	_identityState = TGProfileLoadStateIdle;
	_detailsState = TGProfileLoadStateIdle;
	_mediaState = TGProfileLoadStateIdle;
	_membersState = TGProfileLoadStateIdle;
	_managementState = TGProfileLoadStateIdle;
	_commonGroupsState = TGProfileLoadStateIdle;
	_photoState = TGProfileLoadStateIdle;
	_fileState = TGProfileLoadStateIdle;
	[[NSNotificationCenter defaultCenter]
			addObserver:self
			   selector:@selector(handleMemoryWarning)
				   name:UIApplicationDidReceiveMemoryWarningNotification
				 object:nil];
	[[NSNotificationCenter defaultCenter]
			addObserver:self
			   selector:@selector(handleUserStatusChanged)
				   name:TGUserStatusDidChangeNotification
				 object:nil];
}

- (void)dealloc {
	_cancelled = YES;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)cancel {
	_cancelled = YES;
	_delegate = nil;
}

- (BOOL)isUserProfile {
	return _userId != 0;
}

#pragma mark - delegate plumbing

- (BOOL)alive {
	return !_cancelled;
}

- (void)notifySection:(TGProfileSection)section {
	if (_cancelled)
		return;
	if ([_delegate respondsToSelector:@selector(profileCompanion:didUpdateSection:)])
		[_delegate profileCompanion:self didUpdateSection:section];
}

- (void)notifyFailure:(TGProfileSection)section message:(NSString *)message {
	if (_cancelled)
		return;
	if ([_delegate respondsToSelector:@selector(profileCompanion:didFailSection:message:)])
		[_delegate profileCompanion:self didFailSection:section message:message];
	[self notifySection:section];
}

- (TGProfileLoadState)state {
	return _identityState;
}

- (TGProfileLoadState)stateForSection:(TGProfileSection)section {
	switch (section){
		case TGProfileSectionIdentity: return _identityState;
		case TGProfileSectionDetails: return _detailsState;
		case TGProfileSectionMedia: return _mediaState;
		case TGProfileSectionMembers: return _membersState;
		case TGProfileSectionManagement: return _managementState;
		case TGProfileSectionCommonGroups: return _commonGroupsState;
	}
	return TGProfileLoadStateIdle;
}

#pragma mark - loading

- (void)reload {
	if (_cancelled)
		return;
	if (_chatId)
		_muted = [[TGClient shared] isChatMuted:_chatId];

	[self loadPhotoFileId];
	[self loadSharedMediaCounts];

	if (_userId){
		[self loadUser];
		[self loadUserFullProfile];
		[self loadNote];
		[self loadCommonGroups];
		[self loadContactFlags];
		[self loadBlockedState];
		[self loadGifts];
		return;
	}

	[self loadChatProfile];
	[self loadMembers];
	[self loadManagement];
}

- (void)refreshVolatile {
	if (_cancelled)
		return;
	if (_chatId){
		BOOL muted = [[TGClient shared] isChatMuted:_chatId];
		if (muted != _muted){
			_muted = muted;
			[self notifySection:TGProfileSectionIdentity];
		}
	}
	if (_userId){
		[self loadUser];
		return;
	}
	[self loadManagement];
	[self loadOnlineSummary];
}

- (void)loadPhotoFileId {
	NSNumber *fileId = _userId
			? [[TGClient shared] photoFileIdForUserId:_userId]
			: [[TGClient shared] photoFileIdForChat:_chatId];
	if ([fileId isKindOfClass:[NSNumber class]])
		_photoFileId = [fileId integerValue];
}

- (void)loadUser {
	if (!_userId)
		return;
	if (_identityState != TGProfileLoadStateLoaded)
		_identityState = TGProfileLoadStateLoading;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] userInfo:_userId completion:^(NSDictionary *dict){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyUserDictionary:dict];
	}];
}

- (void)applyUserDictionary:(NSDictionary *)dict {
	TGUserModel *model = [TGUserModel fromDictionary:dict];
	if (!model){
		if (_identityState != TGProfileLoadStateLoaded)
			_identityState = TGProfileLoadStateFailed;
		[self notifyFailure:TGProfileSectionIdentity message:@"Could not load profile"];
		return;
	}
	_user = model;
	_displayName = [model.displayName copy];
	_phoneNumber = [model.phoneNumber copy];
	_username = [model.username copy];
	_isContact = model.isContact || model.isMutualContact;
	if (model.photoFileId)
		_photoFileId = [model.photoFileId integerValue];
	_identityState = TGProfileLoadStateLoaded;
	if (_detailsState == TGProfileLoadStateIdle)
		_detailsState = TGProfileLoadStateLoading;
	[self notifySection:TGProfileSectionIdentity];
	[self notifySection:TGProfileSectionDetails];
}

- (void)loadUserFullProfile {
	if (!_userId)
		return;
	if (_detailsState != TGProfileLoadStateLoaded)
		_detailsState = TGProfileLoadStateLoading;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] userProfile:_userId completion:^(NSDictionary *info){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyUserFullProfile:info];
	}];
}

- (void)applyUserFullProfile:(NSDictionary *)info {
	if (![info isKindOfClass:[NSDictionary class]]){
		if (_detailsState != TGProfileLoadStateLoaded)
			_detailsState = TGProfileLoadStateFailed;
		[self notifyFailure:TGProfileSectionDetails message:nil];
		return;
	}
	_bio = [TGProfileCompanionText([info objectForKey:@"bio"]) copy];
	_birthdayText = [TGProfileCompanionText([info objectForKey:@"birthday"]) copy];
	_reportedCommonGroupCount =
			TGProfileCompanionInteger([info objectForKey:@"commonGroups"]);
	_detailsState = TGProfileLoadStateLoaded;
	[self notifySection:TGProfileSectionDetails];
	if (_commonGroupsState != TGProfileLoadStateLoaded)
		[self notifySection:TGProfileSectionCommonGroups];
}

- (void)loadNote {
	if (!_userId)
		return;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] noteForUser:_userId completion:^(NSString *note){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyNote:note];
	}];
}

- (void)applyNote:(NSString *)note {
	_noteLoaded = YES;
	_note = [TGProfileCompanionText(note) copy];
	[self notifySection:TGProfileSectionDetails];
}

- (void)loadContactFlags {
	if (!_userId)
		return;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] contactFlagsForUser:_userId completion:^(NSDictionary *flags){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyContactFlags:flags];
	}];
}

- (void)applyContactFlags:(NSDictionary *)flags {
	if (![flags isKindOfClass:[NSDictionary class]])
		return;
	BOOL mutual = TGProfileCompanionBool([flags objectForKey:@"isMutualContact"]);
	_isContact = TGProfileCompanionBool([flags objectForKey:@"isContact"]) || mutual;
	if (TGProfileCompanionBool([flags objectForKey:@"isCloseFriend"]))
		_contactRelation = @"Close friend";
	else if (mutual)
		_contactRelation = @"Mutual contact";
	else if (TGProfileCompanionBool([flags objectForKey:@"isSupport"]))
		_contactRelation = @"Telegram support";
	else
		_contactRelation = nil;
	[self notifySection:TGProfileSectionDetails];
}

- (void)loadBlockedState {
	if (!_userId)
		return;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] isUserBlocked:_userId completion:^(BOOL blocked){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyBlocked:blocked];
	}];
}

- (void)applyBlocked:(BOOL)blocked {
	_blockedKnown = YES;
	if (blocked == _isBlocked)
		return;
	_isBlocked = blocked;
	[self notifySection:TGProfileSectionDetails];
}

- (void)loadCommonGroups {
	if (!_userId)
		return;
	_commonGroupsState = TGProfileLoadStateLoading;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] groupsInCommonWithUser:_userId completion:^(NSArray *chats){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyCommonGroups:chats];
	}];
}

- (void)applyCommonGroups:(NSArray *)chats {
	if (![chats isKindOfClass:[NSArray class]]){
		_commonGroupsState = TGProfileLoadStateFailed;
		[self notifyFailure:TGProfileSectionCommonGroups message:nil];
		return;
	}
	_commonGroups = [TGChatModel arrayFromDictionaries:chats];
	_commonGroupsState = [_commonGroups count]
			? TGProfileLoadStateLoaded : TGProfileLoadStateEmpty;
	[self notifySection:TGProfileSectionCommonGroups];
	[self notifySection:TGProfileSectionDetails];
}

- (NSInteger)commonGroupCount {
	if (_commonGroupsState == TGProfileLoadStateLoaded
			|| _commonGroupsState == TGProfileLoadStateEmpty)
		return (NSInteger)[_commonGroups count];
	return _reportedCommonGroupCount;
}

- (void)loadGifts {
	if (!_userId)
		return;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] giftsForUser:_userId completion:^(NSArray *gifts){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyGifts:gifts];
	}];
}

- (void)applyGifts:(NSArray *)gifts {
	_gifts = [gifts isKindOfClass:[NSArray class]] ? [gifts copy] : [NSArray array];
	[self notifySection:TGProfileSectionMedia];
}

#pragma mark - shared media

- (void)loadSharedMediaCounts {
	if (!_chatId){
		_mediaState = TGProfileLoadStateEmpty;
		return;
	}
	_mediaState = TGProfileLoadStateLoading;
	_photoState = TGProfileLoadStateLoading;
	_fileState = TGProfileLoadStateLoading;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] mediaInChat:_chatId
							filter:@"searchMessagesFilterPhotoAndVideo"
						completion:^(NSArray *messages){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyPhotoMessages:messages];
	}];
	[[TGClient shared] mediaInChat:_chatId
							filter:@"searchMessagesFilterDocument"
						completion:^(NSArray *messages){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyFileMessages:messages];
	}];
}

- (void)applyPhotoMessages:(NSArray *)messages {
	BOOL ok = [messages isKindOfClass:[NSArray class]];
	_photoCount = ok ? (NSInteger)[messages count] : 0;
	_photoState = ok
			? (_photoCount ? TGProfileLoadStateLoaded : TGProfileLoadStateEmpty)
			: TGProfileLoadStateFailed;
	[self settleMediaState];
}

- (void)applyFileMessages:(NSArray *)messages {
	BOOL ok = [messages isKindOfClass:[NSArray class]];
	_fileCount = ok ? (NSInteger)[messages count] : 0;
	_fileState = ok
			? (_fileCount ? TGProfileLoadStateLoaded : TGProfileLoadStateEmpty)
			: TGProfileLoadStateFailed;
	[self settleMediaState];
}

- (void)settleMediaState {
	if (_photoState == TGProfileLoadStateLoading
			|| _fileState == TGProfileLoadStateLoading)
		return;
	if (_photoState == TGProfileLoadStateFailed
			&& _fileState == TGProfileLoadStateFailed)
		_mediaState = TGProfileLoadStateFailed;
	else if (_photoCount + _fileCount == 0)
		_mediaState = TGProfileLoadStateEmpty;
	else
		_mediaState = TGProfileLoadStateLoaded;
	[self notifySection:TGProfileSectionMedia];
}

#pragma mark - group profile

- (void)loadChatProfile {
	if (!_chatId)
		return;
	if (_detailsState != TGProfileLoadStateLoaded)
		_detailsState = TGProfileLoadStateLoading;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] chatProfile:_chatId completion:^(NSDictionary *info){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyChatProfile:info];
	}];
}

- (void)applyChatProfile:(NSDictionary *)info {
	if (![info isKindOfClass:[NSDictionary class]]){
		if (_detailsState != TGProfileLoadStateLoaded)
			_detailsState = TGProfileLoadStateFailed;
		[self notifyFailure:TGProfileSectionDetails message:nil];
		return;
	}
	_chatDescription = [TGProfileCompanionText([info objectForKey:@"description"]) copy];
	NSInteger members = TGProfileCompanionInteger([info objectForKey:@"members"]);
	if (members > 0)
		_memberCount = members;
	NSInteger admins = TGProfileCompanionInteger([info objectForKey:@"admins"]);
	if (admins > 0)
		_adminCount = admins;
	NSString *link = TGProfileCompanionText([info objectForKey:@"inviteLink"]);
	if (link)
		_primaryInviteLink = [link copy];
	_detailsState = TGProfileLoadStateLoaded;
	_identityState = TGProfileLoadStateLoaded;
	[self notifySection:TGProfileSectionDetails];
	[self notifySection:TGProfileSectionManagement];
}

#pragma mark - members

- (void)loadMembers {
	if (!_chatId || _userId)
		return;
	if (_membersState != TGProfileLoadStateLoaded)
		_membersState = TGProfileLoadStateLoading;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] membersOfChat:_chatId completion:^(NSArray *members){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyMembers:members];
	}];
}

- (void)applyMembers:(NSArray *)raw {
	if (![raw isKindOfClass:[NSArray class]]){
		if (_membersState != TGProfileLoadStateLoaded)
			_membersState = TGProfileLoadStateFailed;
		[self notifyFailure:TGProfileSectionMembers message:nil];
		return;
	}
	NSArray *fresh = [TGMemberModel arrayFromDictionaries:raw];
	NSArray *previous = _members ?: [NSArray array];
	_members = fresh;
	_membersState = [fresh count]
			? TGProfileLoadStateLoaded : TGProfileLoadStateEmpty;
	if ((NSInteger)[fresh count] > _memberCount)
		_memberCount = (NSInteger)[fresh count];

	if (_cancelled)
		return;
	if (![_delegate respondsToSelector:
			@selector(profileCompanion:didInsertMemberRows:removeMemberRows:)]){
		[self notifySection:TGProfileSectionMembers];
		return;
	}
	NSMutableSet *freshIds = [NSMutableSet setWithCapacity:[fresh count]];
	for (TGMemberModel *member in fresh)
		[freshIds addObject:[NSNumber numberWithLongLong:member.userId]];
	NSMutableSet *previousIds = [NSMutableSet setWithCapacity:[previous count]];
	for (TGMemberModel *member in previous)
		[previousIds addObject:[NSNumber numberWithLongLong:member.userId]];

	NSMutableArray *inserted = [NSMutableArray array];
	NSUInteger index = 0;
	for (TGMemberModel *member in fresh){
		NSNumber *key = [NSNumber numberWithLongLong:member.userId];
		if (![previousIds containsObject:key])
			[inserted addObject:[NSNumber numberWithUnsignedInteger:index]];
		index++;
	}
	NSMutableArray *removed = [NSMutableArray array];
	index = 0;
	for (TGMemberModel *member in previous){
		NSNumber *key = [NSNumber numberWithLongLong:member.userId];
		if (![freshIds containsObject:key])
			[removed addObject:[NSNumber numberWithUnsignedInteger:index]];
		index++;
	}
	if (![inserted count] && ![removed count]
			&& [fresh count] == [previous count])
		return;
	[_delegate profileCompanion:self
			didInsertMemberRows:inserted
			   removeMemberRows:removed];
}

- (void)loadOnlineSummary {
	if (!_chatId || _userId)
		return;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] groupOnlineSummaryForChat:_chatId
									  completion:^(NSString *text,
												   NSInteger members,
												   NSInteger online){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyOnlineMembers:members online:online];
	}];
}

- (void)applyOnlineMembers:(NSInteger)members online:(NSInteger)online {
	BOOL changed = NO;
	if (members > _memberCount){
		_memberCount = members;
		changed = YES;
	}
	if (online != _onlineCount){
		_onlineCount = online;
		changed = YES;
	}
	if (changed)
		[self notifySection:TGProfileSectionIdentity];
}

#pragma mark - management

- (void)loadManagement {
	if (_userId || !_chatId)
		return;
	if (_managementState != TGProfileLoadStateLoaded)
		_managementState = TGProfileLoadStateLoading;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] groupInfoForChat:_chatId completion:^(NSDictionary *info){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyGroupInfo:info];
	}];
}

- (void)applyGroupInfo:(NSDictionary *)info {
	if (![info isKindOfClass:[NSDictionary class]]){
		_managementLoaded = YES;
		_canListMembers = YES;
		_managementState = TGProfileLoadStateEmpty;
		[self notifySection:TGProfileSectionManagement];
		return;
	}
	NSString *status = TGProfileCompanionText([info objectForKey:@"myStatus"]) ?: @"";
	BOOL admin = [status isEqualToString:@"creator"]
			|| [status isEqualToString:@"administrator"];
	_isAdmin = admin;
	_canEditChat = TGProfileCompanionBool([info objectForKey:@"canBeEdited"]) || admin;
	_isChannel = TGProfileCompanionBool([info objectForKey:@"isChannel"]);
	_isSupergroup = TGProfileCompanionBool([info objectForKey:@"isSupergroup"]);
	_isForum = TGProfileCompanionBool([info objectForKey:@"isForum"]);
	_slowModeDelay = TGProfileCompanionInteger([info objectForKey:@"slowModeDelay"]);
	_historyAvailable =
			TGProfileCompanionBool([info objectForKey:@"isAllHistoryAvailable"]);
	_hiddenMembers = TGProfileCompanionBool([info objectForKey:@"hasHiddenMembers"]);
	_canHideMembers = TGProfileCompanionBool([info objectForKey:@"canHideMembers"]);
	_antiSpam = TGProfileCompanionBool([info objectForKey:@"hasAggressiveAntiSpam"]);
	_canToggleAntiSpam =
			TGProfileCompanionBool([info objectForKey:@"canToggleAggressiveAntiSpam"]);
	_pendingJoinRequests =
			TGProfileCompanionInteger([info objectForKey:@"pendingJoinRequests"]);
	_title = [(TGProfileCompanionText([info objectForKey:@"title"]) ?: @"") copy];
	if (!_displayName)
		_displayName = [_title copy];
	_canListMembers = TGProfileCompanionBool([info objectForKey:@"canGetMembers"])
			|| admin || !_isChannel;
	_managementLoaded = YES;
	_managementState = TGProfileLoadStateLoaded;
	_identityState = TGProfileLoadStateLoaded;
	[self notifySection:TGProfileSectionIdentity];
	[self notifySection:TGProfileSectionManagement];
	[self loadManagementExtras];
}

- (void)loadManagementExtras {
	__weak TGProfileCompanion *weakSelf = self;

	[[TGClient shared] groupMemberCount:_chatId completion:^(NSInteger count){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyMemberCount:count];
	}];

	[[TGClient shared] canGetStatisticsForChat:_chatId completion:^(BOOL canGet){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive] || !canGet)
			return;
		[strongSelf applyCanGetStatistics];
	}];

	[self loadOnlineSummary];

	if (_isAdmin){
		[self loadManagementFlags];
		[self loadAdministrationSummary];
	}

	if (!_isChannel && !_isSupergroup)
		return;

	[self loadBoostSummary];

	if (!_isChannel)
		return;

	[self loadChannelSignatures];
	[self loadDiscussionGroup];
}

- (void)applyMemberCount:(NSInteger)count {
	if (count <= 0 || count == _memberCount)
		return;
	_memberCount = count;
	[self notifySection:TGProfileSectionManagement];
}

- (void)applyCanGetStatistics {
	if (_canGetStatistics)
		return;
	_canGetStatistics = YES;
	[self notifySection:TGProfileSectionManagement];
}

- (void)loadManagementFlags {
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] managementInfoForChat:_chatId
								  completion:^(NSDictionary *info){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyManagementFlags:info];
	}];
}

- (void)applyManagementFlags:(NSDictionary *)info {
	if (![info isKindOfClass:[NSDictionary class]])
		return;
	_protectedContent =
			TGProfileCompanionBool([info objectForKey:@"hasProtectedContent"]);
	_historyAvailable =
			TGProfileCompanionBool([info objectForKey:@"isAllHistoryAvailable"]);
	_hiddenMembers = TGProfileCompanionBool([info objectForKey:@"hasHiddenMembers"]);
	_canHideMembers = TGProfileCompanionBool([info objectForKey:@"canHideMembers"]);
	_antiSpam = TGProfileCompanionBool([info objectForKey:@"hasAntiSpam"]);
	_canToggleAntiSpam =
			TGProfileCompanionBool([info objectForKey:@"canToggleAntiSpam"]);
	id pending = [info objectForKey:@"pendingJoinRequests"];
	if ([pending isKindOfClass:[NSNumber class]])
		_pendingJoinRequests = [pending integerValue];
	_managementFlagsLoaded = YES;
	[self notifySection:TGProfileSectionManagement];
}

- (void)loadAdministrationSummary {
	__weak TGProfileCompanion *weakSelf = self;

	[[TGClient shared] administratorsInGroup:_chatId completion:^(NSArray *admins){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive]
				|| ![admins isKindOfClass:[NSArray class]])
			return;
		[strongSelf applyAdminCount:(NSInteger)[admins count]];
	}];

	[[TGClient shared] inviteLinkCountsInGroup:_chatId completion:^(NSArray *counts){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive]
				|| ![counts isKindOfClass:[NSArray class]])
			return;
		[strongSelf applyInviteLinkCounts:counts];
	}];

	[[TGClient shared] pendingJoinRequestCountForChat:_chatId
										   completion:^(NSInteger count){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyPendingJoinRequests:count];
	}];

	[[TGClient shared] membersJoinedViaPrimaryInviteLinkInChat:_chatId
														 limit:1
													completion:^(NSArray *members,
																 NSInteger total){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyPrimaryLinkJoinCount:total];
	}];

	if ([_primaryInviteLink length])
		return;
	[[TGClient shared] primaryInviteLinkForGroup:_chatId
									  completion:^(NSDictionary *link){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyPrimaryInviteLink:link];
	}];
}

- (void)applyAdminCount:(NSInteger)count {
	if (count == _adminCount)
		return;
	_adminCount = count;
	[self notifySection:TGProfileSectionManagement];
}

- (void)applyInviteLinkCounts:(NSArray *)counts {
	NSInteger total = 0;
	for (id entry in counts){
		if (![entry isKindOfClass:[NSDictionary class]])
			continue;
		total += TGProfileCompanionInteger([(NSDictionary *)entry
				objectForKey:@"linkCount"]);
	}
	if (total == _inviteLinkCount)
		return;
	_inviteLinkCount = total;
	[self notifySection:TGProfileSectionManagement];
}

- (void)applyPendingJoinRequests:(NSInteger)count {
	if (count == _pendingJoinRequests)
		return;
	_pendingJoinRequests = count;
	[self notifySection:TGProfileSectionManagement];
}

- (void)applyPrimaryLinkJoinCount:(NSInteger)total {
	_primaryLinkJoinCount = total;
}

- (void)applyPrimaryInviteLink:(NSDictionary *)link {
	NSString *text = [link isKindOfClass:[NSDictionary class]]
			? TGProfileCompanionText([link objectForKey:@"link"]) : nil;
	if (!text)
		return;
	_primaryInviteLink = [text copy];
	[self notifySection:TGProfileSectionDetails];
	[self notifySection:TGProfileSectionManagement];
}

- (void)loadBoostSummary {
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] boostStatusForChat:_chatId completion:^(NSDictionary *status){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive]
				|| ![status isKindOfClass:[NSDictionary class]])
			return;
		[strongSelf applyBoostStatus:status];
	}];
}

- (void)applyBoostStatus:(NSDictionary *)status {
	_boostsLoaded = YES;
	_boostLevel = TGProfileCompanionInteger([status objectForKey:@"level"]);
	[self notifySection:TGProfileSectionManagement];
}

- (void)loadChannelSignatures {
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] channelSignaturesForChat:_chatId
									 completion:^(NSDictionary *info){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive]
				|| ![info isKindOfClass:[NSDictionary class]])
			return;
		[strongSelf applyChannelSignatures:info];
	}];
}

- (void)applyChannelSignatures:(NSDictionary *)info {
	_signaturesLoaded = YES;
	_signMessages = TGProfileCompanionBool([info objectForKey:@"sign_messages"]);
	_showAuthorProfiles =
			TGProfileCompanionBool([info objectForKey:@"show_message_sender"]);
	[self notifySection:TGProfileSectionManagement];
}

- (void)loadDiscussionGroup {
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] discussionGroupForChannel:_chatId
									  completion:^(NSNumber *linkedChatId){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyDiscussionChatId:TGProfileCompanionIdentifier(linkedChatId)];
	}];
}

- (void)applyDiscussionChatId:(int64_t)chatId {
	_discussionLoaded = YES;
	_discussionChatId = chatId;
	[self notifySection:TGProfileSectionManagement];
	if (!chatId)
		return;
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] titleForChatId:chatId completion:^(NSString *title){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyDiscussionTitle:title];
	}];
}

- (void)applyDiscussionTitle:(NSString *)title {
	_discussionTitle = [TGProfileCompanionText(title) copy];
	[self notifySection:TGProfileSectionManagement];
}

#pragma mark - writes

- (void)setMuted:(BOOL)muted {
	if (!_chatId || muted == _muted)
		return;
	_muted = muted;
	[[TGClient shared] setChat:_chatId muted:muted];
	[self notifySection:TGProfileSectionIdentity];
}

- (void)setBlocked:(BOOL)blocked {
	if (!_userId)
		return;
	_isBlocked = blocked;
	_blockedKnown = YES;
	[[TGClient shared] setUser:_userId blocked:blocked];
	[self notifySection:TGProfileSectionDetails];
	__weak TGProfileCompanion *weakSelf = self;
	[[TGClient shared] isUserBlocked:_userId completion:^(BOOL actual){
		TGProfileCompanion *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf alive])
			return;
		[strongSelf applyBlocked:actual];
	}];
}

- (void)setNoteText:(NSString *)text {
	if (!_userId)
		return;
	NSString *note = TGProfileCompanionText(text);
	_note = [note copy];
	_noteLoaded = YES;
	[self notifySection:TGProfileSectionDetails];
	[[TGClient shared] setNote:(note ?: @"") forUser:_userId completion:nil];
}

#pragma mark - notifications

- (void)handleUserStatusChanged {
	if (_cancelled)
		return;
	if (_userId){
		[self loadUser];
		return;
	}
	[self loadOnlineSummary];
}

- (void)handleMemoryWarning {
	[self purgeCaches];
}

- (void)purgeCaches {
	_members = [NSArray array];
	_commonGroups = [NSArray array];
	_gifts = [NSArray array];
	if (_membersState == TGProfileLoadStateLoaded
			|| _membersState == TGProfileLoadStateEmpty)
		_membersState = TGProfileLoadStateIdle;
	if (_commonGroupsState == TGProfileLoadStateLoaded
			|| _commonGroupsState == TGProfileLoadStateEmpty)
		_commonGroupsState = TGProfileLoadStateIdle;
	[self notifySection:TGProfileSectionMembers];
	[self notifySection:TGProfileSectionCommonGroups];
}

@end

#import "TGNotificationManager.h"
#import "TGClient.h"
#import "TGClient+Notifications.h"

static const NSInteger TGNotificationGroupCountMax = 5;
static const NSInteger TGNotificationGroupSizeMax = 10;
static const NSTimeInterval TGNotificationMinimumInterval = 1.0;
static const NSTimeInterval TGNotificationMinimumSoundInterval = 3.0;
static const NSTimeInterval TGNotificationBudgetWindow = 10.0;
static const NSUInteger TGNotificationBudgetPerWindow = 5;
static const NSUInteger TGNotificationAggregateThreshold = 5;
static const NSUInteger TGNotificationMaxBodyLength = 160;
static const NSUInteger TGNotificationRecentKeyLimit = 256;

static NSString *TGNotificationSafeText(NSString *text) {
	if (![text isKindOfClass:[NSString class]] || !text.length)
		return nil;

	NSMutableString *out = [NSMutableString stringWithCapacity:
			MIN(text.length, TGNotificationMaxBodyLength)];
	BOOL previousWasSpace = NO;
	BOOL truncated = NO;

	for (NSUInteger i = 0; i < text.length; i++){
		unichar ch = [text characterAtIndex:i];

		if (ch >= 0xd800 && ch <= 0xdbff){
			if (i + 1 >= text.length)
				continue;
			unichar low = [text characterAtIndex:i + 1];
			if (low < 0xdc00 || low > 0xdfff)
				continue;
			if (out.length + 2 > TGNotificationMaxBodyLength - 1){
				truncated = YES;
				break;
			}
			[out appendFormat:@"%C%C", ch, low];
			i++;
			previousWasSpace = NO;
			continue;
		}
		if (ch >= 0xdc00 && ch <= 0xdfff)
			continue;

		BOOL isWhitespace = ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
		BOOL isControl = ch < 0x20 || (ch >= 0x7f && ch <= 0x9f);
		BOOL isDirectional = (ch >= 0x200b && ch <= 0x200f) ||
				(ch >= 0x202a && ch <= 0x202e) || (ch >= 0x2060 && ch <= 0x206f);
		BOOL isInvalid = ch == 0xfffc || ch == 0xfffe || ch == 0xffff || ch == 0xfeff;

		if (isWhitespace){
			if (!previousWasSpace && out.length)
				[out appendString:@" "];
			previousWasSpace = YES;
			continue;
		}
		if (isControl || isDirectional || isInvalid)
			continue;
		if (out.length + 1 > TGNotificationMaxBodyLength - 1){
			truncated = YES;
			break;
		}
		[out appendFormat:@"%C", ch];
		previousWasSpace = NO;
	}

	NSString *clean = [out stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length)
		return nil;
	if (truncated || text.length > TGNotificationMaxBodyLength)
		clean = [clean stringByAppendingString:@"…"];
	return clean;
}

static NSString *TGNotificationAggregateText(NSUInteger count) {
	return [NSString stringWithFormat:@"%lu new messages", (unsigned long)count];
}

static NSString *TGNotificationSoundName(long long soundId) {
	if (soundId == 0)
		return nil;

	NSString *stem = [NSString stringWithFormat:@"%lld", soundId];
	NSArray *extensions = @[@"caf", @"aiff", @"wav", @"m4a"];
	for (NSString *extension in extensions){
		if ([[NSBundle mainBundle] pathForResource:stem ofType:extension])
			return [stem stringByAppendingFormat:@".%@", extension];
	}
	if ([[NSBundle mainBundle] pathForResource:@"notification" ofType:@"caf"])
		return @"notification.caf";
	return UILocalNotificationDefaultSoundName;
}

@interface TGNotificationManager ()

@property (nonatomic, strong) NSMutableDictionary *chatIdByGroup;
@property (nonatomic, strong) NSMutableDictionary *unreadByList;
@property (nonatomic, strong) NSMutableArray *recentKeys;
@property (nonatomic, strong) NSMutableSet *recentKeySet;
@property (nonatomic, assign) NSTimeInterval lastPresented;
@property (nonatomic, assign) NSTimeInterval lastSound;
@property (nonatomic, assign) NSTimeInterval budgetWindowStart;
@property (nonatomic, assign) NSUInteger budgetUsed;
@property (nonatomic, assign) NSInteger unmutedUnread;
@property (nonatomic, assign) BOOL haveUnreadCount;
@property (nonatomic, assign) BOOL started;

@end

@implementation TGNotificationManager

+ (instancetype)shared {
	static TGNotificationManager *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [[TGNotificationManager alloc] init]; });
	return shared;
}

- (id)init {
	self = [super init];
	if (!self)
		return nil;
	_chatIdByGroup = [NSMutableDictionary dictionary];
	_unreadByList = [NSMutableDictionary dictionary];
	_recentKeys = [NSMutableArray array];
	_recentKeySet = [NSMutableSet set];
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - lifecycle

- (void)start {
	if (self.started)
		return;
	self.started = YES;

	[self requestAlertPermission];

	TGClient *tg = [TGClient shared];
	[tg send:@{
		@"@type" : @"setOption",
		@"name"  : @"notification_group_count_max",
		@"value" : @{@"@type" : @"optionValueInteger",
					 @"value" : @(TGNotificationGroupCountMax)},
	}];
	[tg send:@{
		@"@type" : @"setOption",
		@"name"  : @"notification_group_size_max",
		@"value" : @{@"@type" : @"optionValueInteger",
					 @"value" : @(TGNotificationGroupSizeMax)},
	}];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(handleClientUpdate:)
												 name:TGNotificationUpdateNotification
											   object:nil];
}

- (void)requestAlertPermission {
	UIApplication *app = [UIApplication sharedApplication];
	SEL registerSelector = NSSelectorFromString(@"registerUserNotificationSettings:");
	if (![app respondsToSelector:registerSelector])
		return;

	Class settingsClass = NSClassFromString(@"UIUserNotificationSettings");
	SEL buildSelector = NSSelectorFromString(@"settingsForTypes:categories:");
	if (!settingsClass || ![settingsClass respondsToSelector:buildSelector])
		return;

	NSMethodSignature *signature = [settingsClass methodSignatureForSelector:buildSelector];
	if (!signature)
		return;
	NSInvocation *build = [NSInvocation invocationWithMethodSignature:signature];
	build.selector = buildSelector;
	build.target = settingsClass;
	NSUInteger types = (1 << 0) | (1 << 1) | (1 << 2);
	id categories = nil;
	[build setArgument:&types atIndex:2];
	[build setArgument:&categories atIndex:3];
	[build invoke];

	void *raw = NULL;
	[build getReturnValue:&raw];
	id settings = (__bridge id)raw;
	if (!settings)
		return;

	NSMethodSignature *registerSignature = [app methodSignatureForSelector:registerSelector];
	if (!registerSignature)
		return;
	NSInvocation *registration = [NSInvocation invocationWithMethodSignature:registerSignature];
	registration.selector = registerSelector;
	registration.target = app;
	[registration setArgument:&settings atIndex:2];
	[registration invoke];
}

- (void)applicationDidBecomeActive {
	[self flushDeliveredNotifications];
	if (self.haveUnreadCount)
		[self setBadge:self.unmutedUnread];
}

- (void)applicationDidEnterBackground {
	if (self.haveUnreadCount)
		[self setBadge:self.unmutedUnread];
}

#pragma mark - updates

- (void)handleClientUpdate:(NSNotification *)note {
	NSDictionary *update = note.object;
	if (![update isKindOfClass:[NSDictionary class]])
		return;
	NSString *type = update[@"@type"];
	if (![type isKindOfClass:[NSString class]])
		return;

	if ([type isEqualToString:@"updateNotificationGroup"])
		[self applyNotificationGroup:update];
	else if ([type isEqualToString:@"updateActiveNotifications"])
		[self applyActiveNotifications:update[@"groups"]];
	else if ([type isEqualToString:@"updateChatReadInbox"])
		[self applyReadInbox:update];
	else if ([type isEqualToString:@"updateChatNotificationSettings"])
		[self applyChatNotificationSettings:update];
	else if ([type isEqualToString:@"updateUnreadMessageCount"])
		[self applyUnreadMessageCount:update];
}

- (void)applyActiveNotifications:(NSArray *)groups {
	if (![groups isKindOfClass:[NSArray class]])
		return;
	for (NSDictionary *group in groups){
		if (![group isKindOfClass:[NSDictionary class]])
			continue;
		int64_t chatId = [group[@"chat_id"] longLongValue];
		if (!chatId)
			continue;
		self.chatIdByGroup[@([group[@"id"] integerValue])] = @(chatId);
	}
}

- (void)applyNotificationGroup:(NSDictionary *)update {
	NSInteger groupId = [update[@"notification_group_id"] integerValue];
	int64_t chatId = [update[@"chat_id"] longLongValue];
	int64_t settingsChatId = [update[@"notification_settings_chat_id"] longLongValue];
	if (!settingsChatId)
		settingsChatId = chatId;
	long long soundId = [update[@"notification_sound_id"] longLongValue];

	if (chatId)
		self.chatIdByGroup[@(groupId)] = @(chatId);

	NSArray *removed = update[@"removed_notification_ids"];
	if ([removed isKindOfClass:[NSArray class]] && removed.count)
		[self cancelPendingLocalNotificationsForChat:chatId];

	NSArray *added = update[@"added_notifications"];
	if (![added isKindOfClass:[NSArray class]] || !added.count)
		return;

	if ([[TGClient shared] isChatMuted:settingsChatId]){
		[[TGClient shared] removeNotificationGroup:groupId
								upToNotificationId:NSIntegerMax];
		return;
	}

	for (NSDictionary *notification in added)
		[self presentNotification:notification
							group:groupId
							 chat:chatId
						  soundId:soundId
							batch:added.count];
}

- (void)applyReadInbox:(NSDictionary *)update {
	if ([update[@"unread_count"] integerValue] != 0)
		return;
	[self clearNotificationsForChat:[update[@"chat_id"] longLongValue]];
}

- (void)applyChatNotificationSettings:(NSDictionary *)update {
	NSDictionary *settings = update[@"notification_settings"];
	if (![settings isKindOfClass:[NSDictionary class]])
		return;
	if ([settings[@"mute_for"] integerValue] <= 0)
		return;
	[self clearNotificationsForChat:[update[@"chat_id"] longLongValue]];
}

- (void)applyUnreadMessageCount:(NSDictionary *)update {
	NSDictionary *list = update[@"chat_list"];
	NSString *listType = [list isKindOfClass:[NSDictionary class]] ? list[@"@type"] : nil;
	if (![listType isEqualToString:@"chatListMain"] &&
			![listType isEqualToString:@"chatListArchive"])
		return;

	self.unreadByList[listType] = @([update[@"unread_unmuted_count"] integerValue]);

	NSInteger total = 0;
	for (NSNumber *count in [self.unreadByList allValues])
		total += [count integerValue];
	self.unmutedUnread = total < 0 ? 0 : total;
	self.haveUnreadCount = YES;

	if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive)
		[self setBadge:self.unmutedUnread];
}

#pragma mark - presentation

- (void)presentNotification:(NSDictionary *)notification
                      group:(NSInteger)groupId
                       chat:(int64_t)chatId
                    soundId:(long long)soundId
                      batch:(NSUInteger)batchCount {
	if (![notification isKindOfClass:[NSDictionary class]])
		return;

	UIApplication *app = [UIApplication sharedApplication];
	if (app.applicationState == UIApplicationStateActive)
		return;

	NSInteger notificationId = [notification[@"id"] integerValue];
	NSString *key = [NSString stringWithFormat:@"%d:%d", (int)groupId, (int)notificationId];
	if ([self.recentKeySet containsObject:key])
		return;
	[self rememberKey:key];

	if (![self consumeBudget])
		return;

	NSString *chatName = [[TGClient shared] titleForChatId:chatId];
	NSDictionary *alert = [[TGClient shared] alertForNotification:notification
														 chatName:chatName];
	if (!alert)
		return;

	NSDictionary *type = notification[@"type"];
	BOOL previewHidden = [type isKindOfClass:[NSDictionary class]] &&
			[type[@"@type"] isEqualToString:@"notificationTypeNewMessage"] &&
			![type[@"show_preview"] boolValue];

	NSString *title = alert[@"title"];
	NSString *body = alert[@"body"];
	if (batchCount >= TGNotificationAggregateThreshold)
		body = TGNotificationAggregateText(batchCount);
	else if (!previewHidden && title.length && ![body hasPrefix:title])
		body = [NSString stringWithFormat:@"%@: %@", title, body];

	NSString *safe = TGNotificationSafeText(body);
	if (!safe.length)
		return;

	NSTimeInterval now = CFAbsoluteTimeGetCurrent();
	if (self.lastPresented != 0.0 && now - self.lastPresented < TGNotificationMinimumInterval)
		return;
	self.lastPresented = now;

	UILocalNotification *local = [[UILocalNotification alloc] init];
	if (!local)
		return;
	local.alertBody = safe;
	local.alertAction = @"View";
	local.userInfo = @{
		@"chatId"         : @(chatId),
		@"groupId"        : @(groupId),
		@"notificationId" : @(notificationId),
	};

	NSString *sound = [notification[@"is_silent"] boolValue]
			? nil : TGNotificationSoundName(soundId);
	if (sound){
		if (self.lastSound != 0.0 && now - self.lastSound < TGNotificationMinimumSoundInterval)
			sound = nil;
		else
			self.lastSound = now;
	}
	local.soundName = sound;

	if (title.length && [local respondsToSelector:NSSelectorFromString(@"setAlertTitle:")])
		[local setValue:title forKey:@"alertTitle"];

	dispatch_async(dispatch_get_main_queue(), ^{
		if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive)
			[[UIApplication sharedApplication] presentLocalNotificationNow:local];
	});
}

- (BOOL)consumeBudget {
	NSTimeInterval now = CFAbsoluteTimeGetCurrent();
	if (self.budgetWindowStart == 0.0 || now - self.budgetWindowStart >= TGNotificationBudgetWindow){
		self.budgetWindowStart = now;
		self.budgetUsed = 0;
	}
	if (self.budgetUsed >= TGNotificationBudgetPerWindow)
		return NO;
	self.budgetUsed++;
	return YES;
}

- (void)rememberKey:(NSString *)key {
	[self.recentKeySet addObject:key];
	[self.recentKeys addObject:key];
	while (self.recentKeys.count > TGNotificationRecentKeyLimit){
		NSString *oldest = [self.recentKeys objectAtIndex:0];
		[self.recentKeySet removeObject:oldest];
		[self.recentKeys removeObjectAtIndex:0];
	}
}

#pragma mark - clearing

- (void)clearNotificationsForChat:(int64_t)chatId {
	if (!chatId)
		return;

	NSMutableArray *groups = [NSMutableArray array];
	for (NSNumber *group in [self.chatIdByGroup allKeys])
		if ([self.chatIdByGroup[group] longLongValue] == chatId)
			[groups addObject:group];

	for (NSNumber *group in groups){
		[[TGClient shared] removeNotificationGroup:[group integerValue]
								upToNotificationId:NSIntegerMax];
		[self.chatIdByGroup removeObjectForKey:group];
	}

	[self cancelPendingLocalNotificationsForChat:chatId];

	if (!self.unmutedUnread)
		[self flushDeliveredNotifications];
}

- (void)cancelPendingLocalNotificationsForChat:(int64_t)chatId {
	if (!chatId)
		return;
	UIApplication *app = [UIApplication sharedApplication];
	for (UILocalNotification *scheduled in [app scheduledLocalNotifications]){
		if ([scheduled.userInfo[@"chatId"] longLongValue] == chatId)
			[app cancelLocalNotification:scheduled];
	}
}

- (void)flushDeliveredNotifications {
	UIApplication *app = [UIApplication sharedApplication];
	if (![UIApplication instancesRespondToSelector:@selector(setApplicationIconBadgeNumber:)])
		return;
	NSArray *scheduled = [app scheduledLocalNotifications];
	app.applicationIconBadgeNumber = 1;
	app.applicationIconBadgeNumber = 0;
	if (scheduled.count)
		[app setScheduledLocalNotifications:scheduled];
}

- (void)setBadge:(NSInteger)count {
	if (![UIApplication instancesRespondToSelector:@selector(setApplicationIconBadgeNumber:)])
		return;
	[UIApplication sharedApplication].applicationIconBadgeNumber = count < 0 ? 0 : count;
}

#pragma mark - taps

- (int64_t)chatIdForLocalNotification:(UILocalNotification *)notification {
	NSDictionary *info = notification.userInfo;
	if (![info isKindOfClass:[NSDictionary class]])
		return 0;
	return [info[@"chatId"] longLongValue];
}

@end

// vim:ft=objc

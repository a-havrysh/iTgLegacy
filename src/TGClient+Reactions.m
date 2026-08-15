#import "TGClient+Private.h"
#import "TGClient+Reactions.h"

@interface TGClient (ReactionsWatchInternal)
- (void)tgStartReactionWatchTimer;
- (void)tgReactionWatchTick:(NSTimer *)timer;
@end

static NSString *const TGReactionPlaceholder = @"\U00002B50";
static NSString *TGQuickReaction = nil;

static NSDictionary *TGReactionTypeEmoji(NSString *emoji) {
	return @{@"@type" : @"reactionTypeEmoji", @"emoji" : emoji ?: @""};
}

static NSDictionary *TGReactionSender(int64_t senderId) {
	if (senderId < 0)
		return @{@"@type" : @"messageSenderChat", @"chat_id" : @(senderId)};
	return @{@"@type" : @"messageSenderUser", @"user_id" : @(senderId)};
}

static int64_t TGReactionSenderId(NSDictionary *sender) {
	if (![sender isKindOfClass:NSDictionary.class])
		return 0;
	if ([sender[@"@type"] isEqualToString:@"messageSenderChat"])
		return [sender[@"chat_id"] longLongValue];
	return [sender[@"user_id"] longLongValue];
}

static NSString *TGReactionEmoji(NSDictionary *type) {
	if (![type isKindOfClass:NSDictionary.class])
		return TGReactionPlaceholder;
	NSString *emoji = type[@"emoji"];
	if ([emoji isKindOfClass:NSString.class] && emoji.length)
		return emoji;
	return TGReactionPlaceholder;
}

static BOOL TGReactionIsCustom(NSDictionary *type) {
	if (![type isKindOfClass:NSDictionary.class])
		return NO;
	NSString *t = type[@"@type"];
	return [t isEqualToString:@"reactionTypeCustomEmoji"] ||
	       [t isEqualToString:@"reactionTypePaid"];
}

static NSString *TGReactionUnavailability(NSDictionary *reason) {
	if (![reason isKindOfClass:NSDictionary.class])
		return @"";
	NSString *t = reason[@"@type"];
	if ([t isEqualToString:@"reactionUnavailabilityReasonAnonymousAdministrator"])
		return @"Anonymous admins cannot react";
	if ([t isEqualToString:@"reactionUnavailabilityReasonGuest"])
		return @"Join the chat to react";
	if ([t isEqualToString:@"reactionUnavailabilityReasonRestricted"])
		return @"Reacting is restricted here";
	return @"";
}

static void TGAppendReactionEmoji(NSArray *list, NSMutableArray *out) {
	if (![list isKindOfClass:NSArray.class])
		return;
	for (NSDictionary *r in list){
		if (![r isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *type = r[@"type"];
		if (TGReactionIsCustom(type))
			continue;
		NSString *emoji = TGReactionEmoji(type);
		if (emoji.length && ![emoji isEqualToString:TGReactionPlaceholder])
			[out addObject:emoji];
	}
}

static NSMutableDictionary *TGReactionIconPaths = nil;
static NSMutableDictionary *TGReactionWatches = nil;
static NSTimer *TGReactionWatchTimer = nil;
static NSTimeInterval TGReactionWatchInterval = 5.0;

static NSString *TGReactionWatchKey(int64_t chatId, int64_t messageId) {
	return [NSString stringWithFormat:@"%lld:%lld", chatId, messageId];
}

static NSString *TGReactionChipSignature(NSArray *chips) {
	if (![chips isKindOfClass:NSArray.class])
		return @"";
	NSMutableString *sig = [NSMutableString string];
	for (NSDictionary *chip in chips){
		if (![chip isKindOfClass:NSDictionary.class])
			continue;
		NSString *emoji = chip[@"emoji"];
		if (![emoji isKindOfClass:NSString.class])
			emoji = @"";
		[sig appendFormat:@"%@|%d|%d;", emoji,
		                  (int)[chip[@"count"] integerValue],
		                  [chip[@"chosen"] boolValue] ? 1 : 0];
	}
	return sig;
}

static NSString *TGReactionSenderName(TGClient *client, int64_t senderId) {
	if (!client || senderId == 0)
		return @"";
	if (senderId > 0)
		return [client nameForUserId:senderId] ?: @"";
	for (NSDictionary *c in client.chats){
		if ([c[@"id"] longLongValue] == senderId)
			return c[@"title"] ?: @"";
	}
	for (NSDictionary *c in client.archivedChats){
		if ([c[@"id"] longLongValue] == senderId)
			return c[@"title"] ?: @"";
	}
	return @"";
}

@implementation TGClient (Reactions)

#pragma mark - sending

- (void)addReaction:(NSString *)emoji
          toMessage:(int64_t)messageId
             inChat:(int64_t)chatId
                big:(BOOL)big {
	if (!emoji.length)
		return;
	[self send:@{
		@"@type"                   : @"addMessageReaction",
		@"chat_id"                 : @(chatId),
		@"message_id"              : @(messageId),
		@"reaction_type"           : TGReactionTypeEmoji(emoji),
		@"is_big"                  : @(big),
		@"update_recent_reactions" : @YES,
	}];
}

- (void)removeReaction:(NSString *)emoji
           fromMessage:(int64_t)messageId
                inChat:(int64_t)chatId {
	if (!emoji.length)
		return;
	[self send:@{
		@"@type"         : @"removeMessageReaction",
		@"chat_id"       : @(chatId),
		@"message_id"    : @(messageId),
		@"reaction_type" : TGReactionTypeEmoji(emoji),
	}];
}

- (void)toggleReaction:(NSString *)emoji
             onMessage:(int64_t)messageId
                inChat:(int64_t)chatId
                   big:(BOOL)big
            completion:(void (^)(BOOL nowChosen))completion {
	if (!emoji.length){
		if (completion)
			completion(NO);
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self reactionChipsForMessage:messageId inChat:chatId
	                   completion:^(NSArray *chips){
		TGClient *me = weakSelf;
		if (!me){
			if (completion)
				completion(NO);
			return;
		}
		BOOL chosen = NO;
		for (NSDictionary *chip in chips){
			if ([chip[@"emoji"] isEqualToString:emoji] &&
			    [chip[@"chosen"] boolValue]){
				chosen = YES;
				break;
			}
		}
		if (chosen)
			[me removeReaction:emoji fromMessage:messageId inChat:chatId];
		else
			[me addReaction:emoji toMessage:messageId inChat:chatId big:big];
		if (completion)
			completion(!chosen);
	}];
}

- (void)setReactions:(NSArray *)emojis
           onMessage:(int64_t)messageId
              inChat:(int64_t)chatId
                 big:(BOOL)big {
	NSMutableArray *types = [NSMutableArray array];
	for (NSString *emoji in emojis){
		if ([emoji isKindOfClass:NSString.class] && emoji.length)
			[types addObject:TGReactionTypeEmoji(emoji)];
	}
	[self send:@{
		@"@type"          : @"setMessageReactions",
		@"chat_id"        : @(chatId),
		@"message_id"     : @(messageId),
		@"reaction_types" : types,
		@"is_big"         : @(big),
	}];
}

- (NSString *)quickReactionEmoji {
	return TGQuickReaction.length ? TGQuickReaction : @"\U0001F44D";
}

- (void)setQuickReactionEmoji:(NSString *)emoji {
	if (!emoji.length)
		return;
	TGQuickReaction = [emoji copy];
	[self send:@{
		@"@type"         : @"setDefaultReactionType",
		@"reaction_type" : TGReactionTypeEmoji(emoji),
	}];
}

- (void)clearRecentReactions {
	[self send:@{@"@type" : @"clearRecentReactions"}];
}

#pragma mark - reading

+ (NSArray *)reactionChipsFromMessage:(NSDictionary *)message {
	if (![message isKindOfClass:NSDictionary.class])
		return @[];
	NSDictionary *info = message[@"interaction_info"];
	if (![info isKindOfClass:NSDictionary.class])
		return @[];
	NSDictionary *box = info[@"reactions"];
	if (![box isKindOfClass:NSDictionary.class])
		return @[];
	NSArray *reactions = box[@"reactions"];
	if (![reactions isKindOfClass:NSArray.class])
		return @[];

	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *r in reactions){
		if (![r isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *type = r[@"type"];
		[out addObject:@{
			@"emoji"  : TGReactionEmoji(type),
			@"count"  : r[@"total_count"] ?: @(0),
			@"chosen" : @([r[@"is_chosen"] boolValue]),
			@"custom" : @(TGReactionIsCustom(type)),
		}];
	}
	return out;
}

- (void)reactionChipsForMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSArray *chips))completion {
	[self request:@{
		@"@type"      : @"getMessage",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result isKindOfClass:NSDictionary.class] ||
		    [result[@"@type"] isEqualToString:@"error"]){
			completion(@[]);
			return;
		}
		completion([TGClient reactionChipsFromMessage:result]);
	}];
}

- (void)availableReactionsForMessage:(int64_t)messageId
                              inChat:(int64_t)chatId
                          completion:(void (^)(NSDictionary *info))completion {
	[self request:@{
		@"@type"      : @"getMessageAvailableReactions",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"row_size"   : @(7),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result isKindOfClass:NSDictionary.class] ||
		    [result[@"@type"] isEqualToString:@"error"]){
			completion(nil);
			return;
		}
		NSMutableArray *top = [NSMutableArray array];
		NSMutableArray *recent = [NSMutableArray array];
		NSMutableArray *popular = [NSMutableArray array];
		TGAppendReactionEmoji(result[@"top_reactions"], top);
		TGAppendReactionEmoji(result[@"recent_reactions"], recent);
		TGAppendReactionEmoji(result[@"popular_reactions"], popular);

		NSMutableArray *all = [NSMutableArray array];
		for (NSArray *list in [NSArray arrayWithObjects:top, recent, popular, nil]){
			for (NSString *emoji in list){
				if (![all containsObject:emoji])
					[all addObject:emoji];
			}
		}
		completion(@{
			@"top"      : top,
			@"recent"   : recent,
			@"popular"  : popular,
			@"allEmoji" : all,
			@"reason"   : TGReactionUnavailability(result[@"unavailability_reason"]),
		});
	}];
}

- (void)addedReactionsForMessage:(int64_t)messageId
                          inChat:(int64_t)chatId
                           emoji:(NSString *)emoji
                          offset:(NSString *)offset
                           limit:(NSInteger)limit
                      completion:(void (^)(NSArray *reactors,
                                           NSString *nextOffset,
                                           NSInteger totalCount))completion {
	NSMutableDictionary *req = [NSMutableDictionary dictionaryWithDictionary:@{
		@"@type"      : @"getMessageAddedReactions",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"offset"     : offset.length ? offset : @"",
		@"limit"      : @(limit > 0 ? limit : 50),
	}];
	if (emoji.length)
		[req setObject:TGReactionTypeEmoji(emoji) forKey:@"reaction_type"];

	__weak typeof(self) weakSelf = self;
	[self request:req completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *me = weakSelf;
		if (!me || ![result isKindOfClass:NSDictionary.class] ||
		    [result[@"@type"] isEqualToString:@"error"]){
			completion(@[], @"", 0);
			return;
		}
		NSArray *added = result[@"reactions"];
		NSMutableArray *out = [NSMutableArray array];
		if ([added isKindOfClass:NSArray.class]){
			for (NSDictionary *r in added){
				if (![r isKindOfClass:NSDictionary.class])
					continue;
				int64_t senderId = TGReactionSenderId(r[@"sender_id"]);
				[out addObject:@{
					@"senderId" : @(senderId),
					@"name"     : TGReactionSenderName(me, senderId),
					@"emoji"    : TGReactionEmoji(r[@"type"]),
					@"date"     : r[@"date"] ?: @(0),
				}];
			}
		}
		NSString *next = result[@"next_offset"];
		if (![next isKindOfClass:NSString.class])
			next = @"";
		completion(out, next, [result[@"total_count"] integerValue]);
	}];
}

- (void)emojiReactionInfo:(NSString *)emoji
               completion:(void (^)(NSDictionary *info))completion {
	if (!emoji.length){
		if (completion)
			completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getEmojiReaction", @"emoji" : emoji}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result isKindOfClass:NSDictionary.class] ||
		    [result[@"@type"] isEqualToString:@"error"]){
			completion(nil);
			return;
		}
		NSDictionary *icon = result[@"static_icon"];
		NSNumber *fileId = nil;
		if ([icon isKindOfClass:NSDictionary.class]){
			NSDictionary *file = icon[@"sticker"];
			if ([file isKindOfClass:NSDictionary.class] &&
			    [file[@"id"] isKindOfClass:NSNumber.class])
				fileId = file[@"id"];
		}
		completion(@{
			@"emoji"      : result[@"emoji"] ?: emoji,
			@"title"      : result[@"title"] ?: @"",
			@"isActive"   : @([result[@"is_active"] boolValue]),
			@"iconFileId" : fileId ?: [NSNull null],
		});
	}];
}

+ (NSArray *)paidReactorsFromMessage:(NSDictionary *)message {
	if (![message isKindOfClass:NSDictionary.class])
		return @[];
	NSDictionary *info = message[@"interaction_info"];
	if (![info isKindOfClass:NSDictionary.class])
		return @[];
	NSDictionary *box = info[@"reactions"];
	if (![box isKindOfClass:NSDictionary.class])
		return @[];
	NSArray *reactors = box[@"paid_reactors"];
	if (![reactors isKindOfClass:NSArray.class])
		return @[];

	TGClient *client = [TGClient shared];
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *r in reactors){
		if (![r isKindOfClass:NSDictionary.class])
			continue;
		int64_t senderId = TGReactionSenderId(r[@"sender_id"]);
		BOOL anonymous = [r[@"is_anonymous"] boolValue];
		[out addObject:@{
			@"senderId"    : @(anonymous ? 0 : senderId),
			@"name"        : anonymous ? @"Anonymous"
			                           : TGReactionSenderName(client, senderId),
			@"stars"       : r[@"star_count"] ?: @(0),
			@"isTop"       : @([r[@"is_top"] boolValue]),
			@"isAnonymous" : @(anonymous),
		}];
	}
	return out;
}

- (void)reactionUsageForMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSArray *chosenEmoji,
                                          NSInteger usedCount,
                                          NSInteger maxCount,
                                          BOOL canAddMore))completion {
	if (!completion)
		return;
	__weak typeof(self) weakSelf = self;
	[self reactionChipsForMessage:messageId inChat:chatId completion:^(NSArray *chips){
		TGClient *me = weakSelf;
		if (!me){
			completion(@[], 0, 1, YES);
			return;
		}
		NSMutableArray *chosen = [NSMutableArray array];
		for (NSDictionary *chip in chips){
			if (![chip isKindOfClass:NSDictionary.class])
				continue;
			if (![chip[@"chosen"] boolValue])
				continue;
			NSString *emoji = chip[@"emoji"];
			if ([emoji isKindOfClass:NSString.class] && emoji.length)
				[chosen addObject:emoji];
		}
		[me availableReactionsInChat:chatId
		                  completion:^(NSArray *emojis, BOOL allowsAll, NSInteger maxCount){
			NSInteger max = maxCount > 0 ? maxCount : 1;
			NSInteger used = (NSInteger)chosen.count;
			completion(chosen, used, max, used < max);
		}];
	}];
}

- (void)reactionIconPathForEmoji:(NSString *)emoji
                      completion:(void (^)(NSString *path))completion {
	if (!completion)
		return;
	if (!emoji.length){
		completion(nil);
		return;
	}
	if (!TGReactionIconPaths)
		TGReactionIconPaths = [[NSMutableDictionary alloc] init];
	NSString *cached = TGReactionIconPaths[emoji];
	if ([cached isKindOfClass:NSString.class] && cached.length){
		completion(cached);
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self emojiReactionInfo:emoji completion:^(NSDictionary *info){
		TGClient *me = weakSelf;
		NSNumber *fileId = nil;
		if ([info isKindOfClass:NSDictionary.class] &&
		    [info[@"iconFileId"] isKindOfClass:NSNumber.class])
			fileId = info[@"iconFileId"];
		if (!me || !fileId){
			completion(nil);
			return;
		}
		[me downloadFile:[fileId integerValue] completion:^(NSString *path){
			if ([path isKindOfClass:NSString.class] && path.length)
				[TGReactionIconPaths setObject:path forKey:emoji];
			completion([path isKindOfClass:NSString.class] && path.length ? path : nil);
		}];
	}];
}

#pragma mark - live chip updates

- (void)watchReactionsForMessage:(int64_t)messageId
                          inChat:(int64_t)chatId
                        onChange:(void (^)(NSArray *chips))onChange {
	if (!onChange)
		return;
	if (!TGReactionWatches)
		TGReactionWatches = [[NSMutableDictionary alloc] init];

	NSString *key = TGReactionWatchKey(chatId, messageId);
	NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
	                              @(chatId), @"chatId",
	                              @(messageId), @"messageId",
	                              [onChange copy], @"block",
	                              @"", @"signature", nil];
	[TGReactionWatches setObject:entry forKey:key];

	[self reactionChipsForMessage:messageId inChat:chatId completion:^(NSArray *chips){
		NSMutableDictionary *live = [TGReactionWatches objectForKey:key];
		if ([live isKindOfClass:NSDictionary.class])
			[live setObject:TGReactionChipSignature(chips) forKey:@"signature"];
	}];

	[self tgStartReactionWatchTimer];
}

- (void)unwatchReactionsForMessage:(int64_t)messageId inChat:(int64_t)chatId {
	if (!TGReactionWatches)
		return;
	[TGReactionWatches removeObjectForKey:TGReactionWatchKey(chatId, messageId)];
	if (TGReactionWatches.count == 0)
		[self unwatchAllReactions];
}

- (void)unwatchAllReactions {
	[TGReactionWatches removeAllObjects];
	[TGReactionWatchTimer invalidate];
	TGReactionWatchTimer = nil;
}

- (void)setReactionWatchInterval:(NSTimeInterval)seconds {
	TGReactionWatchInterval = seconds < 2.0 ? 2.0 : seconds;
}

- (void)tgStartReactionWatchTimer {
	if (TGReactionWatchTimer)
		return;
	TGReactionWatchTimer = [NSTimer scheduledTimerWithTimeInterval:TGReactionWatchInterval
	                                                        target:self
	                                                      selector:@selector(tgReactionWatchTick:)
	                                                      userInfo:nil
	                                                       repeats:YES];
}

- (void)tgReactionWatchTick:(NSTimer *)timer {
	if (TGReactionWatches.count == 0){
		[self unwatchAllReactions];
		return;
	}
	for (NSString *key in [TGReactionWatches allKeys]){
		NSMutableDictionary *entry = [TGReactionWatches objectForKey:key];
		if (![entry isKindOfClass:NSDictionary.class])
			continue;
		int64_t chatId = [entry[@"chatId"] longLongValue];
		int64_t messageId = [entry[@"messageId"] longLongValue];
		[self reactionChipsForMessage:messageId inChat:chatId completion:^(NSArray *chips){
			NSMutableDictionary *live = [TGReactionWatches objectForKey:key];
			if (![live isKindOfClass:NSDictionary.class])
				return;
			NSString *signature = TGReactionChipSignature(chips);
			NSString *previous = live[@"signature"];
			if ([previous isKindOfClass:NSString.class] &&
			    [previous isEqualToString:signature])
				return;
			[live setObject:signature forKey:@"signature"];
			void (^block)(NSArray *) = live[@"block"];
			if (block)
				block(chips);
		}];
	}
}

#pragma mark - unread reactions

- (void)unreadReactionsInChat:(int64_t)chatId
                fromMessageId:(int64_t)fromMessageId
                        limit:(NSInteger)limit
                   completion:(void (^)(NSArray *messageIds))completion {
	[self request:@{
		@"@type"           : @"searchChatMessages",
		@"chat_id"         : @(chatId),
		@"query"           : @"",
		@"from_message_id" : @(fromMessageId),
		@"offset"          : @(0),
		@"limit"           : @(limit > 0 ? limit : 50),
		@"filter"          : @{@"@type" : @"searchMessagesFilterUnreadReaction"},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result isKindOfClass:NSDictionary.class]){
			completion(@[]);
			return;
		}
		NSArray *messages = result[@"messages"];
		if (![messages isKindOfClass:NSArray.class]){
			completion(@[]);
			return;
		}
		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *m in messages){
			if ([m isKindOfClass:NSDictionary.class] && m[@"id"])
				[ids addObject:m[@"id"]];
		}
		completion([[ids reverseObjectEnumerator] allObjects]);
	}];
}

- (void)markReactionsReadInChat:(int64_t)chatId {
	[self send:@{@"@type" : @"readAllChatReactions", @"chat_id" : @(chatId)}];
}

- (void)markReactionsReadInChat:(int64_t)chatId forumTopicId:(int64_t)topicId {
	if (topicId == 0){
		[self markReactionsReadInChat:chatId];
		return;
	}
	[self send:@{
		@"@type"          : @"readAllForumTopicReactions",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
	}];
}

#pragma mark - moderation

- (void)reactionPermissionsForMessage:(int64_t)messageId
                               inChat:(int64_t)chatId
                           completion:(void (^)(BOOL canDelete,
                                                BOOL canReport))completion {
	[self request:@{
		@"@type"      : @"getMessageProperties",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result isKindOfClass:NSDictionary.class] ||
		    [result[@"@type"] isEqualToString:@"error"]){
			completion(NO, NO);
			return;
		}
		completion([result[@"can_delete_reactions"] boolValue],
		           [result[@"can_report_reactions"] boolValue]);
	}];
}

- (void)deleteReactionsFromSender:(int64_t)senderId
                        onMessage:(int64_t)messageId
                           inChat:(int64_t)chatId {
	if (senderId == 0)
		return;
	[self send:@{
		@"@type"      : @"deleteMessageReactionsFromSender",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"sender_id"  : TGReactionSender(senderId),
	}];
}

- (void)deleteAllRecentReactionsFromSender:(int64_t)senderId
                                    inChat:(int64_t)chatId {
	if (senderId == 0)
		return;
	[self send:@{
		@"@type"     : @"deleteAllRecentMessageReactionsFromSender",
		@"chat_id"   : @(chatId),
		@"sender_id" : TGReactionSender(senderId),
	}];
}

- (void)reportReactionsFromSender:(int64_t)senderId
                        onMessage:(int64_t)messageId
                           inChat:(int64_t)chatId {
	if (senderId == 0)
		return;
	[self send:@{
		@"@type"      : @"reportMessageReactions",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"sender_id"  : TGReactionSender(senderId),
	}];
}

#pragma mark - chat settings

- (void)availableReactionsInChat:(int64_t)chatId
                      completion:(void (^)(NSArray *emojis,
                                           BOOL allowsAll,
                                           NSInteger maxCount))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (!completion)
			return;
		if (![chat isKindOfClass:NSDictionary.class]){
			completion(@[], NO, 1);
			return;
		}
		NSDictionary *available = chat[@"available_reactions"];
		if (![available isKindOfClass:NSDictionary.class]){
			completion(@[], NO, 1);
			return;
		}
		NSInteger maxCount = [available[@"max_reaction_count"] integerValue];
		if (maxCount < 1)
			maxCount = 1;
		if ([available[@"@type"] isEqualToString:@"chatAvailableReactionsAll"]){
			completion(@[], YES, maxCount);
			return;
		}
		NSMutableArray *emojis = [NSMutableArray array];
		NSArray *types = available[@"reactions"];
		if ([types isKindOfClass:NSArray.class]){
			for (NSDictionary *type in types){
				if (TGReactionIsCustom(type))
					continue;
				NSString *emoji = TGReactionEmoji(type);
				if (emoji.length && ![emoji isEqualToString:TGReactionPlaceholder])
					[emojis addObject:emoji];
			}
		}
		completion(emojis, NO, maxCount);
	}];
}

- (void)setAvailableReactionsInChat:(int64_t)chatId
                             emojis:(NSArray *)emojis
                           maxCount:(NSInteger)maxCount {
	if (maxCount < 1)
		maxCount = 1;
	NSDictionary *available = nil;
	if (!emojis){
		available = @{
			@"@type"              : @"chatAvailableReactionsAll",
			@"max_reaction_count" : @(maxCount),
		};
	}
	else {
		NSMutableArray *types = [NSMutableArray array];
		for (NSString *emoji in emojis){
			if ([emoji isKindOfClass:NSString.class] && emoji.length)
				[types addObject:TGReactionTypeEmoji(emoji)];
		}
		available = @{
			@"@type"              : @"chatAvailableReactionsSome",
			@"reactions"          : types,
			@"max_reaction_count" : @(maxCount),
		};
	}
	[self send:@{
		@"@type"               : @"setChatAvailableReactions",
		@"chat_id"             : @(chatId),
		@"available_reactions" : available,
	}];
}

#pragma mark - notification settings

- (void)setReactionNotificationSource:(NSString *)source
                          showPreview:(BOOL)showPreview
                              soundId:(int64_t)soundId {
	NSString *type = @"reactionNotificationSourceAll";
	if ([source isEqualToString:@"none"])
		type = @"reactionNotificationSourceNone";
	else if ([source isEqualToString:@"contacts"])
		type = @"reactionNotificationSourceContacts";

	NSDictionary *value = @{@"@type" : type};
	[self send:@{
		@"@type" : @"setReactionNotificationSettings",
		@"notification_settings" : @{
			@"@type"                  : @"reactionNotificationSettings",
			@"message_reaction_source": value,
			@"story_reaction_source"  : value,
			@"poll_vote_source"       : value,
			@"sound_id"               : @(soundId),
			@"show_preview"           : @(showPreview),
		},
	}];
}

@end

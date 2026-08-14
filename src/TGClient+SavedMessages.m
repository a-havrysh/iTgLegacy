#import "TGClient+SavedMessages.h"
#import "TGClient+Private.h"
#import <objc/runtime.h>

static NSMutableDictionary *TGSavedTopics(void){
	static NSMutableDictionary *topics = nil;
	if (!topics)
		topics = [[NSMutableDictionary alloc] init];
	return topics;
}

static NSInteger TGSavedTopicCount = 0;
static void (^TGSavedTopicsChanged)(void) = nil;
static void (^TGSavedTagsChanged)(int64_t) = nil;

static NSString *TGSavedPreview(NSDictionary *message){
	if (![message isKindOfClass:NSDictionary.class])
		return @"";
	NSDictionary *content = message[@"content"];
	if (![content isKindOfClass:NSDictionary.class])
		return @"";
	NSDictionary *text = content[@"text"];
	if ([text isKindOfClass:NSDictionary.class]){
		NSString *body = text[@"text"];
		if ([body isKindOfClass:NSString.class] && body.length)
			return body;
	}
	NSDictionary *caption = content[@"caption"];
	if ([caption isKindOfClass:NSDictionary.class]){
		NSString *body = caption[@"text"];
		if ([body isKindOfClass:NSString.class] && body.length)
			return body;
	}
	NSString *type = content[@"@type"];
	if (![type isKindOfClass:NSString.class])
		return @"";
	if ([type isEqualToString:@"messagePhoto"])     return @"Photo";
	if ([type isEqualToString:@"messageVideo"])     return @"Video";
	if ([type isEqualToString:@"messageVideoNote"]) return @"Video message";
	if ([type isEqualToString:@"messageVoiceNote"]) return @"Voice message";
	if ([type isEqualToString:@"messageAudio"])     return @"Audio";
	if ([type isEqualToString:@"messageDocument"])  return @"Document";
	if ([type isEqualToString:@"messageSticker"])   return @"Sticker";
	if ([type isEqualToString:@"messageAnimation"]) return @"GIF";
	if ([type isEqualToString:@"messageLocation"])  return @"Location";
	if ([type isEqualToString:@"messageVenue"])     return @"Location";
	if ([type isEqualToString:@"messageContact"])   return @"Contact";
	if ([type isEqualToString:@"messagePoll"])      return @"Poll";
	return @"";
}

static NSArray *TGSavedMessageTags(NSDictionary *message){
	NSDictionary *info = message[@"interaction_info"];
	if (![info isKindOfClass:NSDictionary.class])
		return [NSArray array];
	NSDictionary *reactions = info[@"reactions"];
	if (![reactions isKindOfClass:NSDictionary.class])
		return [NSArray array];
	NSArray *list = reactions[@"reactions"];
	if (![list isKindOfClass:NSArray.class])
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *reaction in list){
		if (![reaction isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *type = reaction[@"type"];
		if (![type isKindOfClass:NSDictionary.class])
			continue;
		NSString *emoji = type[@"emoji"];
		if ([emoji isKindOfClass:NSString.class] && emoji.length)
			[out addObject:emoji];
	}
	return out;
}

static NSDictionary *TGSavedFlattenMessage(NSDictionary *m){
	if (![m isKindOfClass:NSDictionary.class])
		return nil;
	NSDictionary *sender = m[@"sender_id"];
	if (![sender isKindOfClass:NSDictionary.class])
		sender = [NSDictionary dictionary];

	NSNumber *messageId = m[@"id"];
	if (![messageId isKindOfClass:NSNumber.class])
		messageId = @(0);

	return [NSDictionary dictionaryWithObjectsAndKeys:
			messageId,                              @"id",
			TGSavedPreview(m) ?: @"",               @"text",
			m[@"date"] ?: @(0),                     @"date",
			@([m[@"is_outgoing"] boolValue]),       @"outgoing",
			sender[@"user_id"] ?: @(0),             @"senderId",
			sender[@"chat_id"] ?: @(0),             @"senderChatId",
			@([m[@"is_pinned"] boolValue]),         @"isPinned",
			TGSavedMessageTags(m),                  @"tags",
			nil];
}

static NSDictionary *TGSavedFlattenTopic(NSDictionary *topic){
	if (![topic isKindOfClass:NSDictionary.class])
		return nil;
	NSNumber *topicId = topic[@"id"];
	if (![topicId isKindOfClass:NSNumber.class])
		return nil;

	NSDictionary *type = topic[@"type"];
	if (![type isKindOfClass:NSDictionary.class])
		type = [NSDictionary dictionary];
	NSString *typeName = type[@"@type"];
	if (![typeName isKindOfClass:NSString.class])
		typeName = @"";

	NSString *kind = @"fromChat";
	NSString *title = @"";
	int64_t originChatId = 0;

	if ([typeName isEqualToString:@"savedMessagesTopicTypeMyNotes"]){
		kind = @"myNotes";
		title = @"My Notes";
	} else if ([typeName isEqualToString:@"savedMessagesTopicTypeAuthorHidden"]){
		kind = @"authorHidden";
		title = @"Hidden Author";
	} else {
		NSNumber *chatId = type[@"chat_id"];
		if ([chatId isKindOfClass:NSNumber.class])
			originChatId = [chatId longLongValue];
		NSString *known = [[TGClient shared] nameForUserId:originChatId];
		if ([known isKindOfClass:NSString.class] && known.length)
			title = known;
	}

	NSDictionary *last = topic[@"last_message"];
	if (![last isKindOfClass:NSDictionary.class])
		last = [NSDictionary dictionary];

	NSString *draftText = @"";
	NSDictionary *draft = topic[@"draft_message"];
	if ([draft isKindOfClass:NSDictionary.class]){
		NSDictionary *content = draft[@"content"];
		if ([content isKindOfClass:NSDictionary.class]){
			NSDictionary *text = content[@"text"];
			if ([text isKindOfClass:NSDictionary.class] &&
				[text[@"text"] isKindOfClass:NSString.class])
				draftText = text[@"text"];
		}
	}

	return [NSDictionary dictionaryWithObjectsAndKeys:
			topicId,                                 @"id",
			kind,                                    @"kind",
			@(originChatId),                         @"chatId",
			title,                                   @"title",
			TGSavedPreview(last) ?: @"",             @"text",
			last[@"date"] ?: @(0),                   @"date",
			last[@"id"] ?: @(0),                     @"messageId",
			@([last[@"is_outgoing"] boolValue]),     @"outgoing",
			@([topic[@"is_pinned"] boolValue]),      @"isPinned",
			topic[@"order"] ?: @(0),                 @"order",
			draftText,                               @"draft",
			nil];
}

static NSDictionary *TGSavedReactionType(NSString *emoji){
	return [NSDictionary dictionaryWithObjectsAndKeys:
			@"reactionTypeEmoji", @"@type",
			emoji ?: @"",         @"emoji",
			nil];
}

@interface TGClient (SavedMessagesSwizzle)
- (void)handleUpdate:(NSDictionary *)obj;
- (void)tgsm_handleUpdate:(NSDictionary *)obj;
@end

@implementation TGClient (SavedMessages)

+ (void)load {
	Method original = class_getInstanceMethod(self, @selector(handleUpdate:));
	Method replacement = class_getInstanceMethod(self, @selector(tgsm_handleUpdate:));
	if (original && replacement)
		method_exchangeImplementations(original, replacement);
}

- (void)tgsm_handleUpdate:(NSDictionary *)obj {
	if ([obj isKindOfClass:NSDictionary.class] && ![obj[@"@extra"] isKindOfClass:NSString.class]){
		NSString *type = obj[@"@type"];

		if ([type isEqualToString:@"updateSavedMessagesTopic"]){
			NSDictionary *flat = TGSavedFlattenTopic(obj[@"topic"]);
			if (flat){
				[TGSavedTopics() setObject:flat forKey:flat[@"id"]];
				if (TGSavedTopicsChanged)
					TGSavedTopicsChanged();
			}
		} else if ([type isEqualToString:@"updateSavedMessagesTopicCount"]){
			NSNumber *count = obj[@"topic_count"];
			if ([count isKindOfClass:NSNumber.class])
				TGSavedTopicCount = [count integerValue];
			if (TGSavedTopicsChanged)
				TGSavedTopicsChanged();
		} else if ([type isEqualToString:@"updateSavedMessagesTags"]){
			if (TGSavedTagsChanged){
				NSNumber *topicId = obj[@"saved_messages_topic_id"];
				TGSavedTagsChanged([topicId isKindOfClass:NSNumber.class]
						? [topicId longLongValue] : 0);
			}
		}
	}
	[self tgsm_handleUpdate:obj];
}

- (void)runSavedOk:(NSDictionary *)request completion:(void (^)(BOOL))completion {
	[self request:request completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"TGClient: %@ failed: %@", request[@"@type"], result[@"message"]);
		if (completion)
			completion(ok);
	}];
}

#pragma mark - topics list

- (NSArray *)cachedSavedMessagesTopics {
	NSArray *all = [TGSavedTopics() allValues];
	return [all sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
		BOOL pinnedA = [a[@"isPinned"] boolValue];
		BOOL pinnedB = [b[@"isPinned"] boolValue];
		if (pinnedA != pinnedB)
			return pinnedA ? NSOrderedAscending : NSOrderedDescending;
		long long orderA = [a[@"order"] longLongValue];
		long long orderB = [b[@"order"] longLongValue];
		if (orderA == orderB)
			return NSOrderedSame;
		return orderA > orderB ? NSOrderedAscending : NSOrderedDescending;
	}];
}

- (NSDictionary *)cachedSavedMessagesTopic:(int64_t)topicId {
	return [TGSavedTopics() objectForKey:@(topicId)];
}

- (NSInteger)savedMessagesTopicCount {
	return TGSavedTopicCount;
}

- (void)setSavedMessagesTopicsChangedHandler:(void (^)(void))handler {
	TGSavedTopicsChanged = [handler copy];
}

- (void)resetSavedMessagesTopicsCache {
	[TGSavedTopics() removeAllObjects];
	TGSavedTopicCount = 0;
}

- (void)loadSavedMessagesTopicsWithLimit:(NSInteger)limit
                              completion:(void (^)(NSArray *))completion {
	if (limit <= 0)
		limit = 100;
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type" : @"loadSavedMessagesTopics",
		@"limit" : @(limit),
	} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"])
			NSLog(@"TGClient: loadSavedMessagesTopics -> %@", result[@"message"]);
		if (!completion)
			return;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
			TGClient *me = weakSelf;
			completion(me ? [me cachedSavedMessagesTopics] : [NSArray array]);
		});
	}];
}

#pragma mark - topic history

- (void)savedMessagesTopicHistory:(int64_t)topicId
                      fromMessage:(int64_t)fromMessageId
                            limit:(NSInteger)limit
                       completion:(void (^)(NSArray *))completion {
	if (limit <= 0)
		limit = 50;
	[self request:@{
		@"@type"                  : @"getSavedMessagesTopicHistory",
		@"saved_messages_topic_id" : @(topicId),
		@"from_message_id"        : @(fromMessageId),
		@"offset"                 : @(0),
		@"limit"                  : @(limit),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *messages = result[@"messages"];
		if (![messages isKindOfClass:NSArray.class]){
			NSLog(@"TGClient: getSavedMessagesTopicHistory -> %@", result[@"message"]);
			completion([NSArray array]);
			return;
		}
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:messages.count];
		for (NSDictionary *m in [[messages reverseObjectEnumerator] allObjects]){
			NSDictionary *flat = TGSavedFlattenMessage(m);
			if (flat)
				[out addObject:flat];
		}
		completion(out);
	}];
}

- (void)savedMessagesTopic:(int64_t)topicId
             messageAtDate:(NSInteger)date
                completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"                   : @"getSavedMessagesTopicMessageByDate",
		@"saved_messages_topic_id" : @(topicId),
		@"date"                    : @(date),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"message"]){
			completion(nil);
			return;
		}
		completion(TGSavedFlattenMessage(result));
	}];
}

- (void)savedMessagesSparsePositionsForTopic:(int64_t)topicId
                                 fromMessage:(int64_t)fromMessageId
                                       limit:(NSInteger)limit
                                  completion:(void (^)(NSArray *, NSInteger))completion {
	if (limit <= 0)
		limit = 100;
	int64_t chatId = [self savedMessagesChatId];
	[self request:@{
		@"@type"                   : @"getChatSparseMessagePositions",
		@"chat_id"                 : @(chatId),
		@"filter"                  : @{ @"@type" : @"searchMessagesFilterEmpty" },
		@"from_message_id"         : @(fromMessageId),
		@"limit"                   : @(limit),
		@"saved_messages_topic_id" : @(topicId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *positions = result[@"positions"];
		if (![positions isKindOfClass:NSArray.class]){
			NSLog(@"TGClient: getChatSparseMessagePositions -> %@", result[@"message"]);
			completion([NSArray array], 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:positions.count];
		for (NSDictionary *p in positions){
			if (![p isKindOfClass:NSDictionary.class])
				continue;
			[out addObject:@{
				@"position"  : p[@"position"] ?: @(0),
				@"messageId" : p[@"message_id"] ?: @(0),
				@"date"      : p[@"date"] ?: @(0),
			}];
		}
		completion(out, [result[@"total_count"] integerValue]);
	}];
}

#pragma mark - pinning topics

- (void)setSavedMessagesTopic:(int64_t)topicId
                       pinned:(BOOL)pinned
                   completion:(void (^)(BOOL))completion {
	[self runSavedOk:@{
		@"@type"                   : @"toggleSavedMessagesTopicIsPinned",
		@"saved_messages_topic_id" : @(topicId),
		@"is_pinned"               : @(pinned),
	} completion:completion];
}

- (void)setPinnedSavedMessagesTopics:(NSArray *)topicIds
                          completion:(void (^)(BOOL))completion {
	NSMutableArray *ids = [NSMutableArray array];
	for (id value in topicIds){
		if ([value isKindOfClass:NSNumber.class])
			[ids addObject:value];
	}
	[self runSavedOk:@{
		@"@type"                    : @"setPinnedSavedMessagesTopics",
		@"saved_messages_topic_ids" : ids,
	} completion:completion];
}

#pragma mark - deleting

- (void)deleteSavedMessagesTopic:(int64_t)topicId
                      completion:(void (^)(BOOL))completion {
	[self runSavedOk:@{
		@"@type"                   : @"deleteSavedMessagesTopicHistory",
		@"saved_messages_topic_id" : @(topicId),
	} completion:^(BOOL ok){
		if (ok)
			[TGSavedTopics() removeObjectForKey:@(topicId)];
		if (completion)
			completion(ok);
	}];
}

- (void)deleteSavedMessagesTopic:(int64_t)topicId
                    messagesFrom:(NSInteger)minDate
                              to:(NSInteger)maxDate
                      completion:(void (^)(BOOL))completion {
	[self runSavedOk:@{
		@"@type"                   : @"deleteSavedMessagesTopicMessagesByDate",
		@"saved_messages_topic_id" : @(topicId),
		@"min_date"                : @(minDate),
		@"max_date"                : @(maxDate),
	} completion:completion];
}

#pragma mark - tags

- (void)setSavedMessagesTagLabel:(NSString *)label
                        forEmoji:(NSString *)emoji
                      completion:(void (^)(BOOL))completion {
	[self runSavedOk:@{
		@"@type" : @"setSavedMessagesTagLabel",
		@"tag"   : TGSavedReactionType(emoji),
		@"label" : label ?: @"",
	} completion:completion];
}

- (void)setSavedMessagesTagsChangedHandler:(void (^)(int64_t))handler {
	TGSavedTagsChanged = [handler copy];
}

#pragma mark - pinned message inside Saved Messages

- (void)pinSavedMessage:(int64_t)messageId completion:(void (^)(BOOL))completion {
	[self runSavedOk:@{
		@"@type"                : @"pinChatMessage",
		@"chat_id"              : @([self savedMessagesChatId]),
		@"message_id"           : @(messageId),
		@"disable_notification" : @YES,
		@"only_for_self"        : @NO,
	} completion:completion];
}

- (void)unpinSavedMessage:(int64_t)messageId completion:(void (^)(BOOL))completion {
	[self runSavedOk:@{
		@"@type"      : @"unpinChatMessage",
		@"chat_id"    : @([self savedMessagesChatId]),
		@"message_id" : @(messageId),
	} completion:completion];
}

- (void)unpinAllSavedMessagesWithCompletion:(void (^)(BOOL))completion {
	[self runSavedOk:@{
		@"@type"   : @"unpinAllChatMessages",
		@"chat_id" : @([self savedMessagesChatId]),
	} completion:completion];
}

- (void)savedMessagesPinnedMessageWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"   : @"getChatPinnedMessage",
		@"chat_id" : @([self savedMessagesChatId]),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"message"]){
			completion(nil);
			return;
		}
		completion(TGSavedFlattenMessage(result));
	}];
}

#pragma mark - per-topic drafts

- (void)setSavedMessagesTopic:(int64_t)topicId
                    draftText:(NSString *)text
                   completion:(void (^)(BOOL))completion {
	NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:@{
		@"@type"    : @"setChatDraftMessage",
		@"chat_id"  : @([self savedMessagesChatId]),
		@"topic_id" : @{
			@"@type"                   : @"messageTopicSavedMessages",
			@"saved_messages_topic_id" : @(topicId),
		},
	}];
	if (text.length){
		[request setObject:@{
			@"@type"   : @"draftMessage",
			@"date"    : @((NSInteger)[[NSDate date] timeIntervalSince1970]),
			@"content" : @{
				@"@type" : @"draftMessageContentText",
				@"text"  : @{ @"@type" : @"formattedText", @"text" : text, @"entities" : @[] },
			},
		} forKey:@"draft_message"];
	}
	[self runSavedOk:request completion:completion];
}

#pragma mark - links

- (void)linkOpensSavedMessages:(NSString *)link
                    completion:(void (^)(BOOL))completion {
	if (!link.length){
		if (completion)
			completion(NO);
		return;
	}
	[self request:@{
		@"@type" : @"getInternalLinkType",
		@"link"  : link,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion([result[@"@type"] isEqualToString:@"internalLinkTypeSavedMessages"]);
	}];
}

@end

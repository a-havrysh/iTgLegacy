#import "TGClient+Forums.h"
#import "TGClient+Private.h"

static NSString *TGForumsMessagePreview(NSDictionary *message){
	if (![message isKindOfClass:NSDictionary.class])
		return @"";
	NSDictionary *content = message[@"content"];
	if (![content isKindOfClass:NSDictionary.class])
		return @"";
	NSString *type = content[@"@type"];
	if (![type isKindOfClass:NSString.class])
		return @"";
	NSDictionary *text = content[@"text"];
	if ([text isKindOfClass:NSDictionary.class]){
		NSString *body = text[@"text"];
		if ([body isKindOfClass:NSString.class])
			return body;
	}
	NSDictionary *caption = content[@"caption"];
	if ([caption isKindOfClass:NSDictionary.class]){
		NSString *body = caption[@"text"];
		if ([body isKindOfClass:NSString.class] && body.length)
			return body;
	}
	if ([type isEqualToString:@"messagePhoto"])       return @"Photo";
	if ([type isEqualToString:@"messageVideo"])       return @"Video";
	if ([type isEqualToString:@"messageVideoNote"])   return @"Video message";
	if ([type isEqualToString:@"messageVoiceNote"])   return @"Voice message";
	if ([type isEqualToString:@"messageAudio"])       return @"Audio";
	if ([type isEqualToString:@"messageDocument"])    return @"Document";
	if ([type isEqualToString:@"messageSticker"])     return @"Sticker";
	if ([type isEqualToString:@"messageAnimation"])   return @"GIF";
	if ([type isEqualToString:@"messageLocation"])    return @"Location";
	if ([type isEqualToString:@"messageContact"])     return @"Contact";
	if ([type isEqualToString:@"messagePoll"])        return @"Poll";
	if ([type isEqualToString:@"messageForumTopicCreated"]) return @"Topic created";
	if ([type isEqualToString:@"messageForumTopicEdited"])  return @"Topic edited";
	return @"";
}

static NSDictionary *TGForumsFlattenTopic(NSDictionary *topic, int64_t chatId){
	if (![topic isKindOfClass:NSDictionary.class])
		return nil;
	NSDictionary *info = topic[@"info"];
	if (![info isKindOfClass:NSDictionary.class])
		return nil;
	NSDictionary *icon = info[@"icon"];
	if (![icon isKindOfClass:NSDictionary.class])
		icon = [NSDictionary dictionary];
	NSDictionary *last = topic[@"last_message"];
	if (![last isKindOfClass:NSDictionary.class])
		last = nil;
	NSDictionary *creator = info[@"creator_id"];
	if (![creator isKindOfClass:NSDictionary.class])
		creator = [NSDictionary dictionary];
	NSDictionary *settings = topic[@"notification_settings"];
	if (![settings isKindOfClass:NSDictionary.class])
		settings = [NSDictionary dictionary];

	NSNumber *topicId = info[@"forum_topic_id"];
	if (![topicId isKindOfClass:NSNumber.class])
		topicId = @(0);
	NSNumber *ownerId = info[@"chat_id"];
	if (![ownerId isKindOfClass:NSNumber.class])
		ownerId = @(chatId);
	NSString *name = info[@"name"];
	if (![name isKindOfClass:NSString.class])
		name = @"";

	return [NSDictionary dictionaryWithObjectsAndKeys:
			topicId,                                     @"topicId",
			topicId,                                     @"threadId",
			ownerId,                                     @"chatId",
			name,                                        @"name",
			TGForumsMessagePreview(last) ?: @"",          @"text",
			last[@"date"] ?: @(0),                       @"date",
			topic[@"unread_count"] ?: @(0),              @"unread",
			topic[@"unread_mention_count"] ?: @(0),      @"unreadMentions",
			topic[@"unread_reaction_count"] ?: @(0),     @"unreadReactions",
			@([info[@"is_general"] boolValue]),          @"isGeneral",
			@([info[@"is_closed"] boolValue]),           @"isClosed",
			@([info[@"is_hidden"] boolValue]),           @"isHidden",
			@([topic[@"is_pinned"] boolValue]),          @"isPinned",
			@([info[@"is_outgoing"] boolValue]),         @"isOutgoing",
			icon[@"color"] ?: @(0),                      @"iconColor",
			icon[@"custom_emoji_id"] ?: @(0),            @"iconEmojiId",
			settings[@"mute_for"] ?: @(0),               @"muteFor",
			info[@"creation_date"] ?: @(0),              @"creationDate",
			creator[@"user_id"] ?: @(0),                 @"creatorId",
			topic[@"order"] ?: @(0),                     @"order",
			nil];
}

@implementation TGClient (Forums)

- (void)runForumOk:(NSDictionary *)request completion:(void (^)(BOOL))completion {
	[self request:request completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"TGClient: %@ failed: %@", request[@"@type"], result[@"message"]);
		if (completion)
			completion(ok);
	}];
}

#pragma mark - listing

- (void)forumTopicsForChat:(int64_t)chatId
                     query:(NSString *)query
                offsetDate:(NSInteger)offsetDate
           offsetMessageId:(int64_t)offsetMessageId
             offsetTopicId:(int32_t)offsetTopicId
                     limit:(NSInteger)limit
                completion:(void (^)(NSArray *, NSDictionary *, NSInteger))completion {
	if (limit <= 0)
		limit = 100;
	[self request:@{
		@"@type"                  : @"getForumTopics",
		@"chat_id"                : @(chatId),
		@"query"                  : query ?: @"",
		@"offset_date"            : @(offsetDate),
		@"offset_message_id"      : @(offsetMessageId),
		@"offset_forum_topic_id"  : @(offsetTopicId),
		@"limit"                  : @(limit),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *topics = result[@"topics"];
		if (![topics isKindOfClass:NSArray.class]){
			NSLog(@"TGClient: getForumTopics -> %@", result[@"@type"]);
			completion(@[], nil, 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:topics.count];
		for (NSDictionary *topic in topics){
			NSDictionary *flat = TGForumsFlattenTopic(topic, chatId);
			if (flat)
				[out addObject:flat];
		}
		NSDictionary *next = nil;
		if (out.count)
			next = @{
				@"date"      : result[@"next_offset_date"] ?: @(0),
				@"messageId" : result[@"next_offset_message_id"] ?: @(0),
				@"topicId"   : result[@"next_offset_forum_topic_id"] ?: @(0),
			};
		NSInteger total = [result[@"total_count"] integerValue];
		NSLog(@"TGClient: %lu forum topics of %ld",
				(unsigned long)out.count, (long)total);
		completion(out, next, total);
	}];
}

- (void)forumTopicRowsForChat:(int64_t)chatId
                   completion:(void (^)(NSArray *))completion {
	[self forumTopicsForChat:chatId query:nil offsetDate:0 offsetMessageId:0
			   offsetTopicId:0 limit:100
				  completion:^(NSArray *topics, NSDictionary *next, NSInteger total){
		if (completion)
			completion(topics);
	}];
}

- (void)searchForumTopicsInChat:(int64_t)chatId
                          query:(NSString *)query
                     completion:(void (^)(NSArray *))completion {
	[self forumTopicsForChat:chatId query:query offsetDate:0 offsetMessageId:0
			   offsetTopicId:0 limit:100
				  completion:^(NSArray *topics, NSDictionary *next, NSInteger total){
		if (completion)
			completion(topics);
	}];
}

- (void)forumTopic:(int32_t)topicId
            inChat:(int64_t)chatId
        completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"          : @"getForumTopic",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"error"]){
			NSLog(@"TGClient: getForumTopic -> %@", result[@"message"]);
			completion(nil);
			return;
		}
		completion(TGForumsFlattenTopic(result, chatId));
	}];
}

- (void)forumTopicHistoryForChat:(int64_t)chatId
                           topic:(int32_t)topicId
                     fromMessage:(int64_t)fromMessageId
                           limit:(NSInteger)limit
                      completion:(void (^)(NSArray *))completion {
	if (limit <= 0)
		limit = 50;
	[self request:@{
		@"@type"           : @"getForumTopicHistory",
		@"chat_id"         : @(chatId),
		@"forum_topic_id"  : @(topicId),
		@"from_message_id" : @(fromMessageId),
		@"offset"          : @(0),
		@"limit"           : @(limit),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *messages = result[@"messages"];
		if (![messages isKindOfClass:NSArray.class]){
			NSLog(@"TGClient: getForumTopicHistory -> %@", result[@"@type"]);
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:messages.count];
		for (NSDictionary *m in [[messages reverseObjectEnumerator] allObjects]){
			if (![m isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *sender = m[@"sender_id"];
			if (![sender isKindOfClass:NSDictionary.class])
				sender = [NSDictionary dictionary];
			[out addObject:@{
				@"id"       : m[@"id"] ?: @(0),
				@"text"     : TGForumsMessagePreview(m) ?: @"",
				@"date"     : m[@"date"] ?: @(0),
				@"outgoing" : @([m[@"is_outgoing"] boolValue]),
				@"senderId" : sender[@"user_id"] ?: @(0),
			}];
		}
		completion(out);
	}];
}

#pragma mark - create and edit

- (NSArray *)forumTopicIconColors {
	return @[@(0x6FB9F0), @(0xFFD67E), @(0xCB86DB),
			 @(0x8EEE98), @(0xFF93B2), @(0xFB6F5F)];
}

- (void)createForumTopicInChat:(int64_t)chatId
                          name:(NSString *)name
                     iconColor:(NSInteger)iconColor
                   iconEmojiId:(int64_t)iconEmojiId
                    completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"            : @"createForumTopic",
		@"chat_id"          : @(chatId),
		@"name"             : name ?: @"",
		@"is_name_implicit" : @NO,
		@"icon"             : @{
			@"@type"           : @"forumTopicIcon",
			@"color"           : @(iconColor),
			@"custom_emoji_id" : @(iconEmojiId),
		},
	} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"])
			NSLog(@"TGClient: createForumTopic -> %@", result[@"message"]);
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"error"]){
			completion(nil);
			return;
		}
		completion(TGForumsFlattenTopic(@{@"info" : result ?: @{}}, chatId));
	}];
}

- (void)editForumTopicInChat:(int64_t)chatId
                       topic:(int32_t)topicId
                        name:(NSString *)name
                  changeIcon:(BOOL)changeIcon
                 iconEmojiId:(int64_t)iconEmojiId
                  completion:(void (^)(BOOL))completion {
	[self runForumOk:@{
		@"@type"                  : @"editForumTopic",
		@"chat_id"                : @(chatId),
		@"forum_topic_id"         : @(topicId),
		@"name"                   : name ?: @"",
		@"edit_icon_custom_emoji" : @(changeIcon),
		@"icon_custom_emoji_id"   : @(changeIcon ? iconEmojiId : 0),
	} completion:completion];
}

- (void)setForumTopicInChat:(int64_t)chatId
                      topic:(int32_t)topicId
                     closed:(BOOL)closed
                 completion:(void (^)(BOOL))completion {
	[self runForumOk:@{
		@"@type"          : @"toggleForumTopicIsClosed",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
		@"is_closed"      : @(closed),
	} completion:completion];
}

- (void)setGeneralForumTopicInChat:(int64_t)chatId
                            hidden:(BOOL)hidden
                        completion:(void (^)(BOOL))completion {
	[self runForumOk:@{
		@"@type"     : @"toggleGeneralForumTopicIsHidden",
		@"chat_id"   : @(chatId),
		@"is_hidden" : @(hidden),
	} completion:completion];
}

- (void)setForumTopicInChat:(int64_t)chatId
                      topic:(int32_t)topicId
                     pinned:(BOOL)pinned
                 completion:(void (^)(BOOL))completion {
	[self runForumOk:@{
		@"@type"          : @"toggleForumTopicIsPinned",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
		@"is_pinned"      : @(pinned),
	} completion:completion];
}

- (void)setPinnedForumTopicsInChat:(int64_t)chatId
                          topicIds:(NSArray *)topicIds
                        completion:(void (^)(BOOL))completion {
	NSMutableArray *ids = [NSMutableArray array];
	if ([topicIds isKindOfClass:NSArray.class]){
		for (id one in topicIds){
			if ([one isKindOfClass:NSNumber.class])
				[ids addObject:@([one intValue])];
		}
	}
	[self runForumOk:@{
		@"@type"           : @"setPinnedForumTopics",
		@"chat_id"         : @(chatId),
		@"forum_topic_ids" : ids,
	} completion:completion];
}

- (void)deleteForumTopicInChat:(int64_t)chatId
                         topic:(int32_t)topicId
                    completion:(void (^)(BOOL))completion {
	[self runForumOk:@{
		@"@type"          : @"deleteForumTopic",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
	} completion:completion];
}

#pragma mark - per-topic housekeeping

- (void)setForumTopicInChat:(int64_t)chatId
                      topic:(int32_t)topicId
                   mutedFor:(NSInteger)seconds
                 completion:(void (^)(BOOL))completion {
	BOOL useDefault = seconds < 0;
	[self runForumOk:@{
		@"@type"                 : @"setForumTopicNotificationSettings",
		@"chat_id"               : @(chatId),
		@"forum_topic_id"        : @(topicId),
		@"notification_settings" : @{
			@"@type"                : @"chatNotificationSettings",
			@"use_default_mute_for" : @(useDefault),
			@"mute_for"             : @(useDefault ? 0 : seconds),
			@"use_default_sound"                                : @YES,
			@"use_default_show_preview"                         : @YES,
			@"use_default_mute_stories"                         : @YES,
			@"use_default_story_sound"                          : @YES,
			@"use_default_show_story_poster"                    : @YES,
			@"use_default_disable_pinned_message_notifications" : @YES,
			@"use_default_disable_mention_notifications"        : @YES,
		},
	} completion:completion];
}

- (void)markForumTopicReadInChat:(int64_t)chatId
                           topic:(int32_t)topicId
                      completion:(void (^)(BOOL))completion {
	[self send:@{
		@"@type"          : @"readAllForumTopicMentions",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
	}];
	[self send:@{
		@"@type"          : @"readAllForumTopicReactions",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
	}];
	[self runForumOk:@{
		@"@type"          : @"readAllForumTopicPollVotes",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
	} completion:completion];
}

- (void)unpinAllMessagesInForumTopicInChat:(int64_t)chatId
                                     topic:(int32_t)topicId
                                completion:(void (^)(BOOL))completion {
	[self runForumOk:@{
		@"@type"          : @"unpinAllForumTopicMessages",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
	} completion:completion];
}

- (void)forumTopicLinkInChat:(int64_t)chatId
                       topic:(int32_t)topicId
                  completion:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"          : @"getForumTopicLink",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *link = result[@"link"];
		if (![link isKindOfClass:NSString.class] || !link.length){
			NSLog(@"TGClient: getForumTopicLink -> %@", result[@"@type"]);
			completion(nil);
			return;
		}
		completion(link);
	}];
}

#pragma mark - icons

- (void)forumTopicDefaultIconsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getForumTopicDefaultIcons"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *stickers = result[@"stickers"];
		if (![stickers isKindOfClass:NSArray.class]){
			NSLog(@"TGClient: getForumTopicDefaultIcons -> %@", result[@"@type"]);
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:stickers.count];
		for (NSDictionary *sticker in stickers){
			if (![sticker isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *fullType = sticker[@"full_type"];
			if (![fullType isKindOfClass:NSDictionary.class])
				fullType = [NSDictionary dictionary];
			NSDictionary *thumb = sticker[@"thumbnail"];
			if (![thumb isKindOfClass:NSDictionary.class])
				thumb = [NSDictionary dictionary];
			NSDictionary *thumbFile = thumb[@"file"];
			if (![thumbFile isKindOfClass:NSDictionary.class])
				thumbFile = [NSDictionary dictionary];
			NSDictionary *file = sticker[@"sticker"];
			if (![file isKindOfClass:NSDictionary.class])
				file = [NSDictionary dictionary];
			NSString *emoji = sticker[@"emoji"];
			if (![emoji isKindOfClass:NSString.class])
				emoji = @"";
			[out addObject:@{
				@"emojiId"     : fullType[@"custom_emoji_id"] ?: @(0),
				@"emoji"       : emoji,
				@"thumbFileId" : thumbFile[@"id"] ?: @(0),
				@"fileId"      : file[@"id"] ?: @(0),
			}];
		}
		completion(out);
	}];
}

#pragma mark - forum mode

- (void)setSupergroup:(int64_t)supergroupId
              isForum:(BOOL)isForum
              hasTabs:(BOOL)hasTabs
           completion:(void (^)(BOOL))completion {
	[self runForumOk:@{
		@"@type"          : @"toggleSupergroupIsForum",
		@"supergroup_id"  : @(supergroupId),
		@"is_forum"       : @(isForum),
		@"has_forum_tabs" : @(hasTabs),
	} completion:completion];
}

- (void)setChat:(int64_t)chatId
   viewAsTopics:(BOOL)viewAsTopics
     completion:(void (^)(BOOL))completion {
	[self runForumOk:@{
		@"@type"          : @"toggleChatViewAsTopics",
		@"chat_id"        : @(chatId),
		@"view_as_topics" : @(viewAsTopics),
	} completion:completion];
}

@end

// vim:ft=objc

#import "TGClient+Messages.h"
#import "TGClient+Private.h"

static BOOL TGMsgIsError(NSDictionary *result) {
	return ![result isKindOfClass:NSDictionary.class] ||
			[result[@"@type"] isEqualToString:@"error"];
}

static NSDictionary *TGMsgFormattedText(NSString *text) {
	return @{@"@type" : @"formattedText", @"text" : text ?: @""};
}

static NSDictionary *TGMsgTopic(int64_t threadId) {
	if (threadId == 0)
		return nil;
	return @{@"@type" : @"messageTopicForum", @"forum_topic_id" : @((int32_t)threadId)};
}

static NSDictionary *TGMsgTextContent(NSString *text, BOOL clearDraft) {
	return @{
		@"@type"       : @"inputMessageText",
		@"text"        : TGMsgFormattedText(text),
		@"clear_draft" : @(clearDraft),
	};
}

static NSDictionary *TGMsgSendOptions(NSDictionary *options) {
	NSMutableDictionary *out = [@{
		@"@type"               : @"messageSendOptions",
		@"disable_notification": @([options[@"silent"] boolValue]),
		@"protect_content"     : @([options[@"protect"] boolValue]),
		@"from_background"     : @NO,
	} mutableCopy];

	NSTimeInterval sendDate = [options[@"sendDate"] doubleValue];
	if (sendDate > 0)
		out[@"scheduling_state"] = @{@"@type" : @"messageSchedulingStateSendAtDate",
									 @"send_date" : @((int32_t)sendDate)};
	else if ([options[@"whenOnline"] boolValue])
		out[@"scheduling_state"] = @{@"@type" : @"messageSchedulingStateSendWhenOnline"};

	return out;
}

static NSString *TGMsgSenderName(int64_t userId) {
	NSString *name = [[TGClient shared] nameForUserId:userId];
	return name.length ? name : @"";
}

static NSDictionary *TGMsgBrief(NSDictionary *m) {
	if (![m isKindOfClass:NSDictionary.class])
		return nil;

	NSDictionary *content = [m[@"content"] isKindOfClass:NSDictionary.class]
			? m[@"content"] : @{};
	NSString *ctype = [content[@"@type"] isKindOfClass:NSString.class]
			? content[@"@type"] : @"";

	NSString *text = @"";
	NSDictionary *body = [content[@"text"] isKindOfClass:NSDictionary.class]
			? content[@"text"]
			: ([content[@"caption"] isKindOfClass:NSDictionary.class]
				? content[@"caption"] : nil);
	if ([body[@"text"] isKindOfClass:NSString.class])
		text = body[@"text"];

	NSNumber *senderId = @0;
	NSDictionary *sender = [m[@"sender_id"] isKindOfClass:NSDictionary.class]
			? m[@"sender_id"] : nil;
	if ([sender[@"user_id"] isKindOfClass:NSNumber.class])
		senderId = sender[@"user_id"];

	return @{
		@"id"       : m[@"id"] ?: @0,
		@"text"     : text,
		@"kind"     : ctype,
		@"date"     : m[@"date"] ?: @0,
		@"outgoing" : m[@"is_outgoing"] ?: @NO,
		@"senderId" : senderId,
	};
}

static NSArray *TGMsgBriefList(NSDictionary *result) {
	NSMutableArray *out = [NSMutableArray array];
	NSArray *messages = result[@"messages"];
	if (![messages isKindOfClass:NSArray.class])
		return out;
	for (NSDictionary *m in messages){
		NSDictionary *flat = TGMsgBrief(m);
		if (flat)
			[out addObject:flat];
	}
	return out;
}

@implementation TGClient (Messages)

#pragma mark - sending

- (void)sendText:(NSString *)text
          toChat:(int64_t)chatId
          thread:(int64_t)threadId
         replyTo:(int64_t)replyToId
         options:(NSDictionary *)options
      completion:(void (^)(NSDictionary *))completion {
	BOOL clearDraft = options[@"clearDraft"] ? [options[@"clearDraft"] boolValue] : YES;

	NSMutableDictionary *request = [@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"options"              : TGMsgSendOptions(options),
		@"input_message_content": TGMsgTextContent(text, clearDraft),
	} mutableCopy];

	NSDictionary *topic = TGMsgTopic(threadId);
	if (topic)
		request[@"topic_id"] = topic;
	if (replyToId != 0)
		request[@"reply_to"] = @{@"@type" : @"inputMessageReplyToMessage",
								 @"message_id" : @(replyToId)};

	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMsgIsError(result) ? nil : TGMsgBrief(result));
	}];
}

- (void)sendText:(NSString *)text
          toChat:(int64_t)chatId
          thread:(int64_t)threadId
         replyTo:(int64_t)replyToId
       quoteText:(NSString *)quoteText
   quotePosition:(NSInteger)quotePosition
      completion:(void (^)(NSDictionary *))completion {
	if (replyToId == 0 || !quoteText.length){
		[self sendText:text toChat:chatId thread:threadId replyTo:replyToId
			   options:nil completion:completion];
		return;
	}

	NSMutableDictionary *request = [@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"options"              : TGMsgSendOptions(nil),
		@"input_message_content": TGMsgTextContent(text, YES),
		@"reply_to"             : @{
			@"@type"      : @"inputMessageReplyToMessage",
			@"message_id" : @(replyToId),
			@"quote"      : @{@"@type" : @"inputTextQuote",
							  @"text"  : TGMsgFormattedText(quoteText),
							  @"position" : @((int32_t)quotePosition)},
		},
	} mutableCopy];

	NSDictionary *topic = TGMsgTopic(threadId);
	if (topic)
		request[@"topic_id"] = topic;

	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMsgIsError(result) ? nil : TGMsgBrief(result));
	}];
}

- (void)sendText:(NSString *)text
          toChat:(int64_t)chatId
  replyToMessage:(int64_t)messageId
        fromChat:(int64_t)sourceChatId
      completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"options"              : TGMsgSendOptions(nil),
		@"input_message_content": TGMsgTextContent(text, YES),
		@"reply_to"             : @{
			@"@type"      : @"inputMessageReplyToExternalMessage",
			@"chat_id"    : @(sourceChatId),
			@"message_id" : @(messageId),
		},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMsgIsError(result) ? nil : TGMsgBrief(result));
	}];
}

- (void)sendPhotoAlbumAtPaths:(NSArray *)paths
                       toChat:(int64_t)chatId
                      caption:(NSString *)caption
                   completion:(void (^)(NSArray *))completion {
	NSMutableArray *contents = [NSMutableArray array];
	for (NSString *path in paths){
		if (![path isKindOfClass:NSString.class] || !path.length)
			continue;
		NSMutableDictionary *item = [@{
			@"@type" : @"inputMessagePhoto",
			@"photo" : @{@"@type" : @"inputPhoto",
						 @"photo" : @{@"@type" : @"inputFileLocal", @"path" : path}},
		} mutableCopy];
		if (contents.count == 0 && caption.length)
			item[@"caption"] = TGMsgFormattedText(caption);
		[contents addObject:item];
	}

	if (!contents.count){
		if (completion)
			completion(@[]);
		return;
	}

	[self request:@{
		@"@type"                 : @"sendMessageAlbum",
		@"chat_id"               : @(chatId),
		@"options"               : TGMsgSendOptions(nil),
		@"input_message_contents": contents,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMsgIsError(result) ? @[] : TGMsgBriefList(result));
	}];
}

- (void)addLocalTextMessage:(NSString *)text
                     toChat:(int64_t)chatId
               senderUserId:(int64_t)senderUserId
                    replyTo:(int64_t)replyToId
                 completion:(void (^)(NSDictionary *))completion {
	int64_t sender = senderUserId;
	if (sender == 0)
		sender = [self.me[@"id"] longLongValue];

	NSMutableDictionary *request = [@{
		@"@type"                : @"addLocalMessage",
		@"chat_id"              : @(chatId),
		@"sender_id"            : @{@"@type" : @"messageSenderUser",
									@"user_id" : @(sender)},
		@"disable_notification" : @YES,
		@"input_message_content": TGMsgTextContent(text, NO),
	} mutableCopy];

	if (replyToId != 0)
		request[@"reply_to"] = @{@"@type" : @"inputMessageReplyToMessage",
								 @"message_id" : @(replyToId)};

	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMsgIsError(result) ? nil : TGMsgBrief(result));
	}];
}

- (void)resendMessages:(NSArray *)messageIds
                inChat:(int64_t)chatId
            completion:(void (^)(NSArray *))completion {
	if (!messageIds.count){
		if (completion)
			completion(@[]);
		return;
	}

	[self request:@{
		@"@type"       : @"resendMessages",
		@"chat_id"     : @(chatId),
		@"message_ids" : messageIds,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMsgIsError(result) ? @[] : TGMsgBriefList(result));
	}];
}

- (void)sendingStateOfMessage:(int64_t)messageId
                       inChat:(int64_t)chatId
                   completion:(void (^)(NSString *, BOOL))completion {
	[self request:@{@"@type" : @"getMessage",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(@"failed", NO);
			return;
		}

		NSDictionary *state = [result[@"sending_state"] isKindOfClass:NSDictionary.class]
				? result[@"sending_state"] : nil;
		NSString *type = [state[@"@type"] isKindOfClass:NSString.class]
				? state[@"@type"] : nil;

		if (!type){
			completion(@"sent", NO);
			return;
		}
		if ([type isEqualToString:@"messageSendingStateFailed"]){
			completion(@"failed", [state[@"can_retry"] boolValue]);
			return;
		}
		completion(@"pending", NO);
	}];
}

#pragma mark - editing

- (void)replaceMediaInMessage:(int64_t)messageId
                       inChat:(int64_t)chatId
                      content:(NSDictionary *)content
                   completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"                : @"editMessageMedia",
		@"chat_id"              : @(chatId),
		@"message_id"           : @(messageId),
		@"input_message_content": content,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGMsgIsError(result));
	}];
}

- (void)replacePhotoInMessage:(int64_t)messageId
                       inChat:(int64_t)chatId
                         path:(NSString *)path
                      caption:(NSString *)caption
                   completion:(void (^)(BOOL))completion {
	if (!path.length){
		if (completion)
			completion(NO);
		return;
	}

	[self replaceMediaInMessage:messageId inChat:chatId content:@{
		@"@type"   : @"inputMessagePhoto",
		@"photo"   : @{@"@type" : @"inputPhoto",
					   @"photo" : @{@"@type" : @"inputFileLocal", @"path" : path}},
		@"caption" : TGMsgFormattedText(caption),
	} completion:completion];
}

- (void)replaceVideoInMessage:(int64_t)messageId
                       inChat:(int64_t)chatId
                         path:(NSString *)path
                      caption:(NSString *)caption
                   completion:(void (^)(BOOL))completion {
	if (!path.length){
		if (completion)
			completion(NO);
		return;
	}

	[self replaceMediaInMessage:messageId inChat:chatId content:@{
		@"@type"   : @"inputMessageVideo",
		@"video"   : @{@"@type" : @"inputVideo",
					   @"video" : @{@"@type" : @"inputFileLocal", @"path" : path},
					   @"supports_streaming" : @NO},
		@"caption" : TGMsgFormattedText(caption),
	} completion:completion];
}

- (void)propertiesOfMessage:(int64_t)messageId
                     inChat:(int64_t)chatId
                 completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getMessageProperties",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(@{});
			return;
		}

		NSMutableDictionary *out = [@{
			@"canEdit"                : result[@"can_be_edited"] ?: @NO,
			@"canEditMedia"           : result[@"can_edit_media"] ?: @NO,
			@"canDeleteForMe"         : result[@"can_be_deleted_only_for_self"] ?: @NO,
			@"canDeleteForEveryone"   : result[@"can_be_deleted_for_all_users"] ?: @NO,
			@"canForward"             : result[@"can_be_forwarded"] ?: @NO,
			@"canCopy"                : result[@"can_be_copied"] ?: @NO,
			@"canPin"                 : result[@"can_be_pinned"] ?: @NO,
			@"canReply"               : result[@"can_be_replied"] ?: @NO,
			@"canReplyInAnotherChat"  : result[@"can_be_replied_in_another_chat"] ?: @NO,
			@"canGetLink"             : result[@"can_get_link"] ?: @NO,
			@"canGetEmbeddingCode"    : result[@"can_get_embedding_code"] ?: @NO,
			@"canGetViewers"          : result[@"can_get_viewers"] ?: @NO,
			@"canGetReadDate"         : result[@"can_get_read_date"] ?: @NO,
			@"canGetThread"           : result[@"can_get_message_thread"] ?: @NO,
			@"canEditSchedulingState" : result[@"can_edit_scheduling_state"] ?: @NO,
			@"canReport"              : result[@"can_report_chat"] ?: @NO,
			@"canSave"                : result[@"can_be_saved"] ?: @NO,
			@"canDeleteReactions"     : result[@"can_delete_reactions"] ?: @NO,
			@"canReportReactions"     : result[@"can_report_reactions"] ?: @NO,
			@"canReportSpam"          : result[@"can_report_supergroup_spam"] ?: @NO,
			@"canRecognizeSpeech"     : result[@"can_recognize_speech"] ?: @NO,
			@"canGetStatistics"       : result[@"can_get_statistics"] ?: @NO,
		} mutableCopy];

		BOOL canSelect = [result[@"can_be_copied"] boolValue] ||
						 [result[@"can_be_forwarded"] boolValue] ||
						 [result[@"can_be_deleted_only_for_self"] boolValue] ||
						 [result[@"can_be_deleted_for_all_users"] boolValue];
		out[@"canSelect"] = @(canSelect);

		[self request:@{@"@type" : @"getMessage",
						@"chat_id" : @(chatId),
						@"message_id" : @(messageId)}
		   completion:^(NSDictionary *message){
			NSDictionary *flat = TGMsgIsError(message) ? nil : TGMsgBrief(message);
			NSString *text = [flat[@"text"] isKindOfClass:NSString.class]
					? flat[@"text"] : @"";
			out[@"canTranslate"] = @(text.length > 0);
			completion(out);
		}];
	}];
}

#pragma mark - pinning a message

- (void)pinMessage:(int64_t)messageId
            inChat:(int64_t)chatId
          silently:(BOOL)silently
         onlyForMe:(BOOL)onlyForMe
        completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"                : @"pinChatMessage",
		@"chat_id"              : @(chatId),
		@"message_id"           : @(messageId),
		@"disable_notification" : @(silently),
		@"only_for_self"        : @(onlyForMe),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGMsgIsError(result));
	}];
}

- (void)unpinMessage:(int64_t)messageId
              inChat:(int64_t)chatId
          completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"      : @"unpinChatMessage",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGMsgIsError(result));
	}];
}

- (void)unpinAllMessagesInChat:(int64_t)chatId
                    completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"unpinAllChatMessages", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGMsgIsError(result));
	}];
}

- (void)pinnedMessageIdInChat:(int64_t)chatId
                   completion:(void (^)(int64_t))completion {
	if (!completion)
		return;

	[self request:@{@"@type" : @"getChatPinnedMessage", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (TGMsgIsError(result) || ![result[@"id"] isKindOfClass:NSNumber.class]){
			completion(0);
			return;
		}
		completion([result[@"id"] longLongValue]);
	}];
}

- (void)isMessagePinned:(int64_t)messageId
                 inChat:(int64_t)chatId
             completion:(void (^)(BOOL))completion {
	if (!completion)
		return;

	[self pinnedMessageIdInChat:chatId completion:^(int64_t pinnedId){
		completion(pinnedId != 0 && pinnedId == messageId);
	}];
}

#pragma mark - deleting

- (void)deleteMessages:(NSArray *)messageIds
                inChat:(int64_t)chatId
           forEveryone:(BOOL)forEveryone
            completion:(void (^)(BOOL))completion {
	if (!messageIds.count){
		if (completion)
			completion(NO);
		return;
	}

	[self request:@{
		@"@type"       : @"deleteMessages",
		@"chat_id"     : @(chatId),
		@"message_ids" : messageIds,
		@"revoke"      : @(forEveryone),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGMsgIsError(result));
	}];
}

- (void)deleteMessagesFromUser:(int64_t)userId
                        inChat:(int64_t)chatId
                    completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"     : @"deleteChatMessagesBySender",
		@"chat_id"   : @(chatId),
		@"sender_id" : @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGMsgIsError(result));
	}];
}

- (void)deleteMessagesInChat:(int64_t)chatId
                    fromDate:(NSTimeInterval)minDate
                      toDate:(NSTimeInterval)maxDate
                 forEveryone:(BOOL)forEveryone
                  completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"    : @"deleteChatMessagesByDate",
		@"chat_id"  : @(chatId),
		@"min_date" : @((int32_t)minDate),
		@"max_date" : @((int32_t)maxDate),
		@"revoke"   : @(forEveryone),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGMsgIsError(result));
	}];
}

#pragma mark - forwarding

- (void)forwardMessages:(NSArray *)messageIds
               fromChat:(int64_t)fromChatId
                 toChat:(int64_t)toChatId
                 thread:(int64_t)threadId
                 asCopy:(BOOL)asCopy
         removeCaptions:(BOOL)removeCaptions
                 silent:(BOOL)silent
             completion:(void (^)(NSArray *))completion {
	if (!messageIds.count){
		if (completion)
			completion(@[]);
		return;
	}

	NSMutableDictionary *request = [@{
		@"@type"          : @"forwardMessages",
		@"chat_id"        : @(toChatId),
		@"from_chat_id"   : @(fromChatId),
		@"message_ids"    : messageIds,
		@"options"        : TGMsgSendOptions(@{@"silent" : @(silent)}),
		@"send_copy"      : @(asCopy),
		@"remove_caption" : @(removeCaptions),
	} mutableCopy];

	NSDictionary *topic = TGMsgTopic(threadId);
	if (topic)
		request[@"topic_id"] = topic;

	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMsgIsError(result) ? @[] : TGMsgBriefList(result));
	}];
}

#pragma mark - drafts

- (void)setDraftText:(NSString *)text
             replyTo:(int64_t)replyToId
              inChat:(int64_t)chatId
              thread:(int64_t)threadId {
	if (!text.length){
		[self clearDraftInChat:chatId thread:threadId];
		return;
	}

	NSMutableDictionary *draft = [@{
		@"@type"   : @"draftMessage",
		@"date"    : @((int32_t)[[NSDate date] timeIntervalSince1970]),
		@"content" : @{@"@type" : @"draftMessageContentText",
					   @"text"  : TGMsgFormattedText(text)},
	} mutableCopy];

	if (replyToId != 0)
		draft[@"reply_to"] = @{@"@type" : @"inputMessageReplyToMessage",
							   @"message_id" : @(replyToId)};

	NSMutableDictionary *request = [@{
		@"@type"        : @"setChatDraftMessage",
		@"chat_id"      : @(chatId),
		@"draft_message": draft,
	} mutableCopy];

	NSDictionary *topic = TGMsgTopic(threadId);
	if (topic)
		request[@"topic_id"] = topic;

	[self send:request];
}

- (void)clearDraftInChat:(int64_t)chatId thread:(int64_t)threadId {
	NSMutableDictionary *request = [@{
		@"@type"   : @"setChatDraftMessage",
		@"chat_id" : @(chatId),
	} mutableCopy];

	NSDictionary *topic = TGMsgTopic(threadId);
	if (topic)
		request[@"topic_id"] = topic;

	[self send:request];
}

- (void)draftForChat:(int64_t)chatId
          completion:(void (^)(NSString *, int64_t))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(@"", 0);
			return;
		}

		NSDictionary *draft = [result[@"draft_message"] isKindOfClass:NSDictionary.class]
				? result[@"draft_message"] : nil;
		NSDictionary *content = [draft[@"content"] isKindOfClass:NSDictionary.class]
				? draft[@"content"] : nil;
		NSDictionary *body = [content[@"text"] isKindOfClass:NSDictionary.class]
				? content[@"text"] : nil;
		NSString *text = [body[@"text"] isKindOfClass:NSString.class] ? body[@"text"] : @"";

		NSDictionary *replyTo = [draft[@"reply_to"] isKindOfClass:NSDictionary.class]
				? draft[@"reply_to"] : nil;
		int64_t replyToId = [replyTo[@"message_id"] longLongValue];

		completion(text, replyToId);
	}];
}

#pragma mark - scheduling

- (void)scheduledMessagesInChat:(int64_t)chatId
                     completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getChatScheduledMessages", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(@[]);
			return;
		}

		NSArray *messages = [result[@"messages"] isKindOfClass:NSArray.class]
				? result[@"messages"] : @[];
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *m in messages){
			NSDictionary *flat = TGMsgBrief(m);
			if (!flat)
				continue;

			NSDictionary *state = [m[@"scheduling_state"] isKindOfClass:NSDictionary.class]
					? m[@"scheduling_state"] : nil;
			BOOL whenOnline = [state[@"@type"]
					isEqualToString:@"messageSchedulingStateSendWhenOnline"];

			NSMutableDictionary *entry = [flat mutableCopy];
			entry[@"sendDate"]   = state[@"send_date"] ?: @0;
			entry[@"whenOnline"] = @(whenOnline);
			[out addObject:entry];
		}
		completion(out);
	}];
}

- (void)rescheduleMessage:(int64_t)messageId
                   inChat:(int64_t)chatId
                 sendDate:(NSTimeInterval)sendDate
               whenOnline:(BOOL)whenOnline
               completion:(void (^)(BOOL))completion {
	NSDictionary *state = whenOnline && sendDate <= 0
		? @{@"@type" : @"messageSchedulingStateSendWhenOnline"}
		: @{@"@type" : @"messageSchedulingStateSendAtDate",
			@"send_date" : @((int32_t)sendDate)};

	[self request:@{
		@"@type"            : @"editMessageSchedulingState",
		@"chat_id"          : @(chatId),
		@"message_id"       : @(messageId),
		@"scheduling_state" : state,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGMsgIsError(result));
	}];
}

- (void)sendScheduledMessageNow:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"      : @"editMessageSchedulingState",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGMsgIsError(result));
	}];
}

#pragma mark - read state

- (void)markRead:(NSArray *)messageIds
          inChat:(int64_t)chatId
          source:(NSString *)source {
	if (!messageIds.count)
		return;

	NSString *type = @"messageSourceChatHistory";
	if ([source isEqualToString:@"thread"])
		type = @"messageSourceMessageThreadHistory";
	else if ([source isEqualToString:@"search"])
		type = @"messageSourceSearch";
	else if ([source isEqualToString:@"notification"])
		type = @"messageSourceNotification";

	[self send:@{
		@"@type"       : @"viewMessages",
		@"chat_id"     : @(chatId),
		@"message_ids" : messageIds,
		@"source"      : @{@"@type" : type},
		@"force_read"  : @YES,
	}];
}

- (void)readAllMentionsInChat:(int64_t)chatId {
	[self send:@{@"@type" : @"readAllChatMentions", @"chat_id" : @(chatId)}];
}

- (void)readAllReactionsInChat:(int64_t)chatId {
	[self send:@{@"@type" : @"readAllChatReactions", @"chat_id" : @(chatId)}];
}

- (void)readDateOfMessage:(int64_t)messageId
                   inChat:(int64_t)chatId
               completion:(void (^)(NSString *, NSTimeInterval))completion {
	[self request:@{@"@type" : @"getMessageReadDate",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(@"unread", 0);
			return;
		}

		NSString *type = [result[@"@type"] isKindOfClass:NSString.class]
				? result[@"@type"] : @"";
		if ([type isEqualToString:@"messageReadDateRead"]){
			completion(@"read", [result[@"read_date"] doubleValue]);
			return;
		}
		if ([type isEqualToString:@"messageReadDateTooOld"]){
			completion(@"tooOld", 0);
			return;
		}
		if ([type isEqualToString:@"messageReadDateUserPrivacyRestricted"]){
			completion(@"theirPrivacy", 0);
			return;
		}
		if ([type isEqualToString:@"messageReadDateMyPrivacyRestricted"]){
			completion(@"myPrivacy", 0);
			return;
		}
		completion(@"unread", 0);
	}];
}

- (void)viewersOfMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
              completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getMessageViewers",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(@[]);
			return;
		}

		NSArray *viewers = [result[@"viewers"] isKindOfClass:NSArray.class]
				? result[@"viewers"] : @[];
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *viewer in viewers){
			if (![viewer isKindOfClass:NSDictionary.class])
				continue;
			int64_t userId = [viewer[@"user_id"] longLongValue];
			[out addObject:@{
				@"id"   : @(userId),
				@"name" : TGMsgSenderName(userId),
				@"date" : viewer[@"view_date"] ?: @0,
			}];
		}
		completion(out);
	}];
}

#pragma mark - typing indicator

- (void)sendChatAction:(NSString *)action toChat:(int64_t)chatId thread:(int64_t)threadId {
	NSDictionary *names = @{
		@"typing"            : @"chatActionTyping",
		@"recordingVoice"    : @"chatActionRecordingVoiceNote",
		@"uploadingVoice"    : @"chatActionUploadingVoiceNote",
		@"recordingVideo"    : @"chatActionRecordingVideo",
		@"uploadingVideo"    : @"chatActionUploadingVideo",
		@"uploadingPhoto"    : @"chatActionUploadingPhoto",
		@"uploadingDocument" : @"chatActionUploadingDocument",
		@"choosingSticker"   : @"chatActionChoosingSticker",
		@"choosingLocation"  : @"chatActionChoosingLocation",
		@"choosingContact"   : @"chatActionChoosingContact",
		@"cancel"            : @"chatActionCancel",
	};

	NSString *type = names[action ?: @""];
	if (!type)
		return;

	NSMutableDictionary *request = [@{
		@"@type"   : @"sendChatAction",
		@"chat_id" : @(chatId),
		@"action"  : @{@"@type" : type},
	} mutableCopy];

	NSDictionary *topic = TGMsgTopic(threadId);
	if (topic)
		request[@"topic_id"] = topic;

	[self send:request];
}

#pragma mark - links

- (void)linkForMessage:(int64_t)messageId
                inChat:(int64_t)chatId
              inThread:(BOOL)inThread
            completion:(void (^)(NSString *, BOOL))completion {
	[self request:@{
		@"@type"             : @"getMessageLink",
		@"chat_id"           : @(chatId),
		@"message_id"        : @(messageId),
		@"media_timestamp"   : @0,
		@"for_album"         : @NO,
		@"in_message_thread" : @(inThread),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(nil, NO);
			return;
		}

		NSString *link = [result[@"link"] isKindOfClass:NSString.class]
				? result[@"link"] : nil;
		completion(link.length ? link : nil, [result[@"is_public"] boolValue]);
	}];
}

- (void)messageLinkInfoForUrl:(NSString *)url
                   completion:(void (^)(int64_t, int64_t, NSDictionary *))completion {
	if (!url.length){
		if (completion)
			completion(0, 0, nil);
		return;
	}

	[self request:@{@"@type" : @"getMessageLinkInfo", @"url" : url}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(0, 0, nil);
			return;
		}

		NSDictionary *message = [result[@"message"] isKindOfClass:NSDictionary.class]
				? result[@"message"] : nil;
		completion([result[@"chat_id"] longLongValue],
				   [message[@"id"] longLongValue],
				   message ? TGMsgBrief(message) : nil);
	}];
}

- (void)embeddingCodeForMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSString *))completion {
	[self request:@{@"@type" : @"getMessageEmbeddingCode",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId),
					@"for_album" : @NO}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(nil);
			return;
		}
		NSString *text = [result[@"text"] isKindOfClass:NSString.class]
				? result[@"text"] : nil;
		completion(text.length ? text : nil);
	}];
}

#pragma mark - threads

- (void)threadForMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
              completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getMessageThread",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(nil);
			return;
		}

		NSDictionary *info = [result[@"reply_info"] isKindOfClass:NSDictionary.class]
				? result[@"reply_info"] : @{};
		completion(@{
			@"chatId"   : result[@"chat_id"] ?: @0,
			@"threadId" : result[@"message_thread_id"] ?: @0,
			@"replies"  : info[@"reply_count"] ?: @0,
			@"unread"   : result[@"unread_message_count"] ?: @0,
		});
	}];
}

#pragma mark - translation

- (void)translateText:(NSString *)text
           toLanguage:(NSString *)languageCode
           completion:(void (^)(NSString *))completion {
	if (!text.length){
		if (completion)
			completion(nil);
		return;
	}

	[self request:@{@"@type" : @"translateText",
					@"text" : TGMsgFormattedText(text),
					@"to_language_code" : languageCode ?: @"en"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(nil);
			return;
		}
		NSString *out = [result[@"text"] isKindOfClass:NSString.class]
				? result[@"text"] : nil;
		completion(out.length ? out : nil);
	}];
}

#pragma mark - bot buttons

- (void)pressInlineButtonWithData:(NSString *)data
                        onMessage:(int64_t)messageId
                           inChat:(int64_t)chatId
                       completion:(void (^)(NSString *, BOOL, NSString *))completion {
	[self request:@{
		@"@type"      : @"getCallbackQueryAnswer",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"payload"    : @{@"@type" : @"callbackQueryPayloadData",
						  @"data"  : data ?: @""},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(nil, NO, nil);
			return;
		}

		NSString *text = [result[@"text"] isKindOfClass:NSString.class]
				? result[@"text"] : nil;
		NSString *url = [result[@"url"] isKindOfClass:NSString.class]
				? result[@"url"] : nil;
		completion(text.length ? text : nil,
				   [result[@"show_alert"] boolValue],
				   url.length ? url : nil);
	}];
}

#pragma mark - reporting

- (void)reportMessages:(NSArray *)messageIds
                inChat:(int64_t)chatId
              optionId:(NSString *)optionId
                  text:(NSString *)text
            completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"       : @"reportChat",
		@"chat_id"     : @(chatId),
		@"option_id"   : optionId ?: @"",
		@"message_ids" : messageIds ?: @[],
		@"text"        : text ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMsgIsError(result)){
			completion(@{@"status" : @"error"});
			return;
		}

		NSString *type = [result[@"@type"] isKindOfClass:NSString.class]
				? result[@"@type"] : @"";

		if ([type isEqualToString:@"reportChatResultOptionRequired"]){
			NSArray *options = [result[@"options"] isKindOfClass:NSArray.class]
					? result[@"options"] : @[];
			NSMutableArray *rows = [NSMutableArray array];
			for (NSDictionary *option in options){
				if (![option isKindOfClass:NSDictionary.class])
					continue;
				[rows addObject:@{@"id"   : option[@"id"] ?: @"",
								  @"text" : option[@"text"] ?: @""}];
			}
			completion(@{@"status"  : @"chooseOption",
						 @"title"   : result[@"title"] ?: @"",
						 @"options" : rows});
			return;
		}

		if ([type isEqualToString:@"reportChatResultTextRequired"]){
			completion(@{@"status"   : @"needText",
						 @"optionId" : result[@"option_id"] ?: @"",
						 @"optional" : result[@"is_optional"] ?: @NO});
			return;
		}

		completion(@{@"status" : [type isEqualToString:@"reportChatResultOk"]
				? @"ok" : @"error"});
	}];
}

#pragma mark - quick replies

- (void)addQuickReplyShortcutNamed:(NSString *)name
                              text:(NSString *)text
                        completion:(void (^)(BOOL))completion {
	if (!name.length || !text.length){
		if (completion)
			completion(NO);
		return;
	}

	[self request:@{
		@"@type"                : @"addQuickReplyShortcutMessage",
		@"shortcut_name"        : name,
		@"reply_to_message_id"  : @0,
		@"input_message_content": TGMsgTextContent(text, NO),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGMsgIsError(result));
	}];
}

- (void)sendQuickReplyShortcut:(NSInteger)shortcutId
                        toChat:(int64_t)chatId
                    completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"       : @"sendQuickReplyShortcutMessages",
		@"chat_id"     : @(chatId),
		@"shortcut_id" : @(shortcutId),
		@"sending_id"  : @0,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMsgIsError(result) ? @[] : TGMsgBriefList(result));
	}];
}

@end

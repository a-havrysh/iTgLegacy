#import "TGClient+Bots.h"
#import "TGClient+Private.h"

static NSDictionary *TGBDict(id value){
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *TGBArray(id value){
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSString *TGBString(id value){
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSNumber *TGBNumber(id value){
	return [value isKindOfClass:NSNumber.class] ? value : @0;
}

static NSNumber *TGBInt64(id value){
	if ([value isKindOfClass:NSNumber.class])
		return value;
	if ([value isKindOfClass:NSString.class])
		return @([value longLongValue]);
	return @0;
}

static BOOL TGBIsError(NSDictionary *result){
	return !TGBDict(result) || [TGBString(result[@"@type"]) isEqualToString:@"error"];
}

static NSDictionary *TGBMarkup(NSDictionary *message){
	NSDictionary *m = TGBDict(message);
	if (!m)
		return nil;
	NSDictionary *markup = TGBDict(m[@"reply_markup"]);
	if (!markup)
		markup = TGBDict(m[@"replyMarkup"]);
	return markup;
}

static NSNumber *TGBFileIdOfPhoto(NSDictionary *photo){
	NSArray *sizes = TGBArray(TGBDict(photo)[@"sizes"]);
	NSDictionary *chosen = nil;
	for (id entry in sizes){
		NSDictionary *size = TGBDict(entry);
		if (size)
			chosen = size;
	}
	NSNumber *fileId = TGBDict(chosen[@"photo"])[@"id"];
	return [fileId isKindOfClass:NSNumber.class] ? fileId : nil;
}

static NSNumber *TGBFileIdOfThumbnail(NSDictionary *owner){
	NSDictionary *thumb = TGBDict(TGBDict(owner)[@"thumbnail"]);
	NSNumber *fileId = TGBDict(thumb[@"file"])[@"id"];
	return [fileId isKindOfClass:NSNumber.class] ? fileId : nil;
}

static NSNumber *TGBFileIdOfDocument(NSDictionary *owner, NSString *key){
	NSNumber *fileId = TGBDict(TGBDict(owner)[key])[@"id"];
	return [fileId isKindOfClass:NSNumber.class] ? fileId : nil;
}

@implementation TGClient (Bots)

#pragma mark - keyboards

- (NSDictionary *)tgb_inlineButton:(NSDictionary *)raw {
	NSDictionary *button = TGBDict(raw);
	if (!button)
		return nil;

	NSDictionary *type = TGBDict(button[@"type"]);
	NSString *kindName = TGBString(type[@"@type"]);
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	out[@"text"] = TGBString(button[@"text"]);
	out[@"kind"] = @"unsupported";

	if ([kindName isEqualToString:@"inlineKeyboardButtonTypeUrl"]){
		out[@"kind"] = @"url";
		out[@"url"] = TGBString(type[@"url"]);
	} else if ([kindName isEqualToString:@"inlineKeyboardButtonTypeLoginUrl"]){
		out[@"kind"] = @"loginUrl";
		out[@"url"] = TGBString(type[@"url"]);
	} else if ([kindName isEqualToString:@"inlineKeyboardButtonTypeWebApp"]){
		out[@"kind"] = @"webApp";
		out[@"url"] = TGBString(type[@"url"]);
	} else if ([kindName isEqualToString:@"inlineKeyboardButtonTypeCallback"]){
		out[@"kind"] = @"callback";
		out[@"data"] = TGBString(type[@"data"]);
	} else if ([kindName isEqualToString:@"inlineKeyboardButtonTypeCallbackWithPassword"]){
		out[@"kind"] = @"callbackWithPassword";
		out[@"data"] = TGBString(type[@"data"]);
	} else if ([kindName isEqualToString:@"inlineKeyboardButtonTypeCallbackGame"]){
		out[@"kind"] = @"callbackGame";
	} else if ([kindName isEqualToString:@"inlineKeyboardButtonTypeSwitchInline"]){
		NSString *target = TGBString(TGBDict(type[@"target_chat"])[@"@type"]);
		out[@"kind"] = @"switchInline";
		out[@"query"] = TGBString(type[@"query"]);
		if ([target isEqualToString:@"targetChatCurrent"])
			out[@"target"] = @"current";
		else if ([target isEqualToString:@"targetChatInternalLink"])
			out[@"target"] = @"link";
		else
			out[@"target"] = @"chosen";
	} else if ([kindName isEqualToString:@"inlineKeyboardButtonTypeUser"]){
		out[@"kind"] = @"user";
		out[@"userId"] = TGBNumber(type[@"user_id"]);
	} else if ([kindName isEqualToString:@"inlineKeyboardButtonTypeCopyText"]){
		out[@"kind"] = @"copyText";
		out[@"copyText"] = TGBString(type[@"text"]);
	} else if ([kindName isEqualToString:@"inlineKeyboardButtonTypeBuy"]){
		out[@"kind"] = @"buy";
	}

	return out;
}

- (NSArray *)inlineKeyboardRowsForMessage:(NSDictionary *)message {
	NSDictionary *markup = TGBMarkup(message);
	if (![TGBString(markup[@"@type"]) isEqualToString:@"replyMarkupInlineKeyboard"])
		return nil;

	NSMutableArray *rows = [NSMutableArray array];
	for (id rawRow in TGBArray(markup[@"rows"])){
		NSMutableArray *row = [NSMutableArray array];
		for (id rawButton in TGBArray(rawRow)){
			NSDictionary *button = [self tgb_inlineButton:rawButton];
			if (button)
				[row addObject:button];
		}
		if (row.count > 0)
			[rows addObject:row];
	}
	return rows.count > 0 ? rows : nil;
}

- (NSDictionary *)tgb_replyButton:(NSDictionary *)raw {
	NSDictionary *button = TGBDict(raw);
	if (!button)
		return nil;

	NSDictionary *type = TGBDict(button[@"type"]);
	NSString *kindName = TGBString(type[@"@type"]);
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	out[@"text"] = TGBString(button[@"text"]);
	out[@"kind"] = @"unsupported";

	if ([kindName isEqualToString:@"keyboardButtonTypeText"]){
		out[@"kind"] = @"text";
	} else if ([kindName isEqualToString:@"keyboardButtonTypeRequestPhoneNumber"]){
		out[@"kind"] = @"requestPhoneNumber";
	} else if ([kindName isEqualToString:@"keyboardButtonTypeRequestLocation"]){
		out[@"kind"] = @"requestLocation";
	} else if ([kindName isEqualToString:@"keyboardButtonTypeRequestPoll"]){
		out[@"kind"] = @"requestPoll";
		out[@"forceQuiz"] = TGBNumber(type[@"force_quiz"]);
		out[@"forceRegular"] = TGBNumber(type[@"force_regular"]);
	} else if ([kindName isEqualToString:@"keyboardButtonTypeRequestUsers"]){
		out[@"kind"] = @"requestUsers";
		out[@"buttonId"] = TGBNumber(type[@"id"]);
		out[@"maxQuantity"] = TGBNumber(type[@"max_quantity"]);
		out[@"userIsBot"] = [TGBNumber(type[@"restrict_user_is_bot"]) boolValue]
				? TGBNumber(type[@"user_is_bot"]) : @NO;
		out[@"userIsPremium"] = [TGBNumber(type[@"restrict_user_is_premium"]) boolValue]
				? TGBNumber(type[@"user_is_premium"]) : @NO;
	} else if ([kindName isEqualToString:@"keyboardButtonTypeRequestChat"]){
		out[@"kind"] = @"requestChat";
		out[@"buttonId"] = TGBNumber(type[@"id"]);
		out[@"chatIsChannel"] = TGBNumber(type[@"chat_is_channel"]);
	} else if ([kindName isEqualToString:@"keyboardButtonTypeWebApp"]){
		out[@"kind"] = @"webApp";
		out[@"url"] = TGBString(type[@"url"]);
	}

	return out;
}

- (NSDictionary *)replyKeyboardForMessage:(NSDictionary *)message {
	NSDictionary *markup = TGBMarkup(message);
	NSString *kind = TGBString(markup[@"@type"]);

	if ([kind isEqualToString:@"replyMarkupRemoveKeyboard"])
		return @{ @"mode" : @"remove", @"rows" : @[], @"resize" : @NO,
				  @"oneTime" : @NO, @"persistent" : @NO, @"placeholder" : @"" };

	if ([kind isEqualToString:@"replyMarkupForceReply"])
		return @{ @"mode" : @"forceReply", @"rows" : @[], @"resize" : @NO,
				  @"oneTime" : @NO, @"persistent" : @NO,
				  @"placeholder" : TGBString(markup[@"input_field_placeholder"]) };

	if (![kind isEqualToString:@"replyMarkupShowKeyboard"])
		return nil;

	NSMutableArray *rows = [NSMutableArray array];
	for (id rawRow in TGBArray(markup[@"rows"])){
		NSMutableArray *row = [NSMutableArray array];
		for (id rawButton in TGBArray(rawRow)){
			NSDictionary *button = [self tgb_replyButton:rawButton];
			if (button)
				[row addObject:button];
		}
		if (row.count > 0)
			[rows addObject:row];
	}

	return @{
		@"mode"        : @"show",
		@"rows"        : rows,
		@"resize"      : TGBNumber(markup[@"resize_keyboard"]),
		@"oneTime"     : TGBNumber(markup[@"one_time"]),
		@"persistent"  : TGBNumber(markup[@"is_persistent"]),
		@"placeholder" : TGBString(markup[@"input_field_placeholder"]),
	};
}

- (void)shareUsers:(NSArray *)userIds
    withBotButton:(NSInteger)buttonId
           inChat:(int64_t)chatId
          message:(int64_t)messageId {
	[self send:@{
		@"@type"           : @"shareUsersWithBot",
		@"source"          : @{ @"@type" : @"keyboardButtonSourceMessage",
								@"chat_id" : @(chatId),
								@"message_id" : @(messageId) },
		@"button_id"       : @(buttonId),
		@"shared_user_ids" : userIds ?: @[],
		@"only_check"      : @NO,
	}];
}

- (void)shareChat:(int64_t)sharedChatId
    withBotButton:(NSInteger)buttonId
           inChat:(int64_t)chatId
          message:(int64_t)messageId {
	[self send:@{
		@"@type"          : @"shareChatWithBot",
		@"source"         : @{ @"@type" : @"keyboardButtonSourceMessage",
							   @"chat_id" : @(chatId),
							   @"message_id" : @(messageId) },
		@"button_id"      : @(buttonId),
		@"shared_chat_id" : @(sharedChatId),
		@"only_check"     : @NO,
	}];
}

#pragma mark - callback buttons

- (void)tgb_callbackWithPayload:(NSDictionary *)payload
                         inChat:(int64_t)chatId
                        message:(int64_t)messageId
                     completion:(void (^)(NSDictionary *))completion {
	if (!payload){
		if (completion)
			completion(nil);
		return;
	}

	[self request:@{
		@"@type"      : @"getCallbackQueryAnswer",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"payload"    : payload,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGBIsError(result)){
			completion(nil);
			return;
		}
		completion(@{
			@"text"      : TGBString(result[@"text"]),
			@"showAlert" : TGBNumber(result[@"show_alert"]),
			@"url"       : TGBString(result[@"url"]),
		});
	}];
}

- (NSDictionary *)tgb_payloadForButton:(NSDictionary *)button password:(NSString *)password {
	NSDictionary *b = TGBDict(button);
	NSString *kind = TGBString(b[@"kind"]);

	if ([kind isEqualToString:@"callbackGame"])
		return nil;

	NSString *data = TGBString(b[@"data"]);
	if (data.length == 0)
		return nil;

	if (password.length > 0)
		return @{ @"@type" : @"callbackQueryPayloadDataWithPassword",
				  @"password" : password, @"data" : data };

	return @{ @"@type" : @"callbackQueryPayloadData", @"data" : data };
}

- (void)pressCallbackButton:(NSDictionary *)button
                     inChat:(int64_t)chatId
                    message:(int64_t)messageId
                 completion:(void (^)(NSDictionary *))completion {
	[self pressCallbackButton:button inChat:chatId message:messageId
					 password:nil completion:completion];
}

- (void)pressCallbackButton:(NSDictionary *)button
                     inChat:(int64_t)chatId
                    message:(int64_t)messageId
                   password:(NSString *)password
                 completion:(void (^)(NSDictionary *))completion {
	[self tgb_callbackWithPayload:[self tgb_payloadForButton:button password:password]
						   inChat:chatId
						  message:messageId
					   completion:completion];
}

#pragma mark - bot profile and commands

- (NSArray *)tgb_commandsFromBotInfo:(NSDictionary *)botInfo {
	NSMutableArray *out = [NSMutableArray array];
	for (id entry in TGBArray(TGBDict(botInfo)[@"commands"])){
		NSDictionary *command = TGBDict(entry);
		if (!command)
			continue;
		[out addObject:@{
			@"command"     : TGBString(command[@"command"]),
			@"description" : TGBString(command[@"description"]),
		}];
	}
	return out;
}

- (void)botInfoForUser:(int64_t)userId completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getUserFullInfo", @"user_id" : @(userId)}
	   completion:^(NSDictionary *full){
		if (!completion)
			return;
		NSDictionary *botInfo = TGBDict(TGBDict(full)[@"bot_info"]);
		if (!botInfo){
			completion(nil);
			return;
		}
		NSDictionary *menu = TGBDict(botInfo[@"menu_button"]);
		completion(@{
			@"description"      : TGBString(botInfo[@"description"]),
			@"shortDescription" : TGBString(botInfo[@"short_description"]),
			@"commands"         : [self tgb_commandsFromBotInfo:botInfo],
			@"menuButtonText"   : TGBString(menu[@"text"]),
			@"menuButtonUrl"    : TGBString(menu[@"url"]),
		});
	}];
}

- (void)botCommandsForUser:(int64_t)userId completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getUserFullInfo", @"user_id" : @(userId)}
	   completion:^(NSDictionary *full){
		if (completion)
			completion([self tgb_commandsFromBotInfo:TGBDict(TGBDict(full)[@"bot_info"])]);
	}];
}

- (void)botCommandsForUser:(int64_t)userId
            matchingPrefix:(NSString *)prefix
                completion:(void (^)(NSArray *))completion {
	NSString *needle = prefix ?: @"";
	if ([needle hasPrefix:@"/"])
		needle = [needle substringFromIndex:1];
	needle = [needle lowercaseString];

	[self botCommandsForUser:userId completion:^(NSArray *commands){
		if (!completion)
			return;
		if (needle.length == 0){
			completion(commands);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *command in commands){
			if ([[TGBString(command[@"command"]) lowercaseString] hasPrefix:needle])
				[out addObject:command];
		}
		completion(out);
	}];
}

- (void)menuButtonForBot:(int64_t)userId completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getMenuButton", @"user_id" : @(userId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGBIsError(result)){
			completion(nil);
			return;
		}
		completion(@{ @"text" : TGBString(result[@"text"]),
					  @"url"  : TGBString(result[@"url"]) });
	}];
}

#pragma mark - starting a bot

- (void)startBot:(int64_t)botUserId inChat:(int64_t)chatId parameter:(NSString *)parameter {
	[self send:@{
		@"@type"       : @"sendBotStartMessage",
		@"bot_user_id" : @(botUserId),
		@"chat_id"     : @(chatId),
		@"parameter"   : parameter ?: @"",
	}];
}

- (void)botStartLinkInfo:(NSString *)link completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getInternalLinkType", @"link" : link ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *kind = TGBString(TGBDict(result)[@"@type"]);
		BOOL inGroup = [kind isEqualToString:@"internalLinkTypeBotStartInGroup"];
		if (!inGroup && ![kind isEqualToString:@"internalLinkTypeBotStart"]){
			completion(nil);
			return;
		}
		completion(@{
			@"username"  : TGBString(result[@"bot_username"]),
			@"parameter" : TGBString(result[@"start_parameter"]),
			@"inGroup"   : inGroup ? @YES : @NO,
		});
	}];
}

- (void)openBotStartLink:(NSString *)link completion:(void (^)(int64_t))completion {
	[self botStartLinkInfo:link completion:^(NSDictionary *info){
		if (!info){
			if (completion)
				completion(0);
			return;
		}
		NSString *parameter = TGBString(info[@"parameter"]);
		[self request:@{@"@type" : @"searchPublicChat",
						@"username" : TGBString(info[@"username"])}
		   completion:^(NSDictionary *chat){
			if (TGBIsError(chat)){
				if (completion)
					completion(0);
				return;
			}
			int64_t chatId = [TGBNumber(chat[@"id"]) longLongValue];
			int64_t botUserId = [TGBNumber(TGBDict(chat[@"type"])[@"user_id"]) longLongValue];
			if (chatId != 0 && botUserId != 0)
				[self startBot:botUserId inChat:chatId parameter:parameter];
			if (completion)
				completion(chatId);
		}];
	}];
}

#pragma mark - write access

- (void)canBotSendMessages:(int64_t)botUserId completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"canBotSendMessages", @"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGBIsError(result));
	}];
}

- (void)allowBotToSendMessages:(int64_t)botUserId completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"allowBotToSendMessages", @"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGBIsError(result));
	}];
}

#pragma mark - inline queries

- (NSDictionary *)tgb_inlineResult:(NSDictionary *)raw {
	NSDictionary *result = TGBDict(raw);
	if (!result)
		return nil;

	NSString *type = TGBString(result[@"@type"]);
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	out[@"id"] = TGBString(result[@"id"]);
	out[@"title"] = TGBString(result[@"title"]);
	out[@"description"] = TGBString(result[@"description"]);
	out[@"kind"] = @"article";

	NSNumber *thumbId = TGBFileIdOfThumbnail(result);
	NSNumber *fileId = nil;

	if ([type isEqualToString:@"inlineQueryResultArticle"]){
		out[@"url"] = TGBString(result[@"url"]);
	} else if ([type isEqualToString:@"inlineQueryResultPhoto"]){
		out[@"kind"] = @"photo";
		NSDictionary *photo = TGBDict(result[@"photo"]);
		fileId = TGBFileIdOfPhoto(photo);
		if (!thumbId)
			thumbId = fileId;
	} else if ([type isEqualToString:@"inlineQueryResultSticker"]){
		out[@"kind"] = @"sticker";
		NSDictionary *sticker = TGBDict(result[@"sticker"]);
		fileId = TGBFileIdOfDocument(sticker, @"sticker");
		thumbId = TGBFileIdOfThumbnail(sticker) ?: fileId;
		out[@"title"] = TGBString(sticker[@"emoji"]);
	} else if ([type isEqualToString:@"inlineQueryResultAnimation"]){
		out[@"kind"] = @"animation";
		NSDictionary *animation = TGBDict(result[@"animation"]);
		fileId = TGBFileIdOfDocument(animation, @"animation");
		thumbId = TGBFileIdOfThumbnail(animation);
	} else if ([type isEqualToString:@"inlineQueryResultVideo"]){
		out[@"kind"] = @"video";
		NSDictionary *video = TGBDict(result[@"video"]);
		fileId = TGBFileIdOfDocument(video, @"video");
		thumbId = TGBFileIdOfThumbnail(video);
	} else if ([type isEqualToString:@"inlineQueryResultAudio"]){
		out[@"kind"] = @"audio";
		NSDictionary *audio = TGBDict(result[@"audio"]);
		fileId = TGBFileIdOfDocument(audio, @"audio");
		out[@"title"] = TGBString(audio[@"title"]);
		out[@"description"] = TGBString(audio[@"performer"]);
	} else if ([type isEqualToString:@"inlineQueryResultVoiceNote"]){
		out[@"kind"] = @"voiceNote";
		fileId = TGBFileIdOfDocument(TGBDict(result[@"voice_note"]), @"voice");
	} else if ([type isEqualToString:@"inlineQueryResultDocument"]){
		out[@"kind"] = @"document";
		NSDictionary *document = TGBDict(result[@"document"]);
		fileId = TGBFileIdOfDocument(document, @"document");
		thumbId = TGBFileIdOfThumbnail(document);
	} else if ([type isEqualToString:@"inlineQueryResultLocation"]){
		out[@"kind"] = @"location";
	} else if ([type isEqualToString:@"inlineQueryResultVenue"]){
		out[@"kind"] = @"venue";
		NSDictionary *venue = TGBDict(result[@"venue"]);
		out[@"title"] = TGBString(venue[@"title"]);
		out[@"description"] = TGBString(venue[@"address"]);
	} else if ([type isEqualToString:@"inlineQueryResultContact"]){
		out[@"kind"] = @"contact";
		NSDictionary *contact = TGBDict(result[@"contact"]);
		out[@"title"] = [NSString stringWithFormat:@"%@ %@",
				TGBString(contact[@"first_name"]), TGBString(contact[@"last_name"])];
		out[@"description"] = TGBString(contact[@"phone_number"]);
	} else if ([type isEqualToString:@"inlineQueryResultGame"]){
		out[@"kind"] = @"game";
		NSDictionary *game = TGBDict(result[@"game"]);
		out[@"title"] = TGBString(game[@"title"]);
		out[@"description"] = TGBString(game[@"description"]);
		thumbId = TGBFileIdOfPhoto(TGBDict(game[@"photo"]));
	}

	if (thumbId)
		out[@"thumbId"] = thumbId;
	if (fileId)
		out[@"fileId"] = fileId;
	return out;
}

- (void)inlineQueryToBot:(int64_t)botUserId
                  inChat:(int64_t)chatId
                   query:(NSString *)query
                  offset:(NSString *)offset
              completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"       : @"getInlineQueryResults",
		@"bot_user_id" : @(botUserId),
		@"chat_id"     : @(chatId),
		@"query"       : query ?: @"",
		@"offset"      : offset ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGBIsError(result)){
			completion(nil);
			return;
		}
		NSMutableArray *results = [NSMutableArray array];
		for (id entry in TGBArray(result[@"results"])){
			NSDictionary *flat = [self tgb_inlineResult:entry];
			if (flat)
				[results addObject:flat];
		}
		NSDictionary *button = TGBDict(result[@"button"]);
		NSDictionary *buttonType = TGBDict(button[@"type"]);
		BOOL startBot = [TGBString(buttonType[@"@type"])
				isEqualToString:@"inlineQueryResultsButtonTypeStartBot"];
		completion(@{
			@"queryId"         : TGBInt64(result[@"inline_query_id"]),
			@"nextOffset"      : TGBString(result[@"next_offset"]),
			@"buttonText"      : startBot ? TGBString(button[@"text"]) : @"",
			@"buttonParameter" : startBot ? TGBString(buttonType[@"parameter"]) : @"",
			@"results"         : results,
		});
	}];
}

- (void)sendInlineResult:(NSString *)resultId
                 queryId:(NSNumber *)queryId
                  toChat:(int64_t)chatId
                 replyTo:(int64_t)replyToId
                 hideVia:(BOOL)hideVia {
	NSMutableDictionary *request = [@{
		@"@type"        : @"sendInlineQueryResultMessage",
		@"chat_id"      : @(chatId),
		@"query_id"     : queryId ?: @0,
		@"result_id"    : resultId ?: @"",
		@"hide_via_bot" : hideVia ? @YES : @NO,
	} mutableCopy];

	if (replyToId != 0)
		request[@"reply_to"] = @{@"@type" : @"inputMessageReplyToMessage",
								 @"message_id" : @(replyToId)};

	[self send:request];
}

#pragma mark - users

- (void)tgb_usersForIds:(NSArray *)userIds completion:(void (^)(NSArray *))completion {
	NSArray *ids = TGBArray(userIds) ?: @[];
	if (ids.count == 0){
		if (completion)
			completion(@[]);
		return;
	}

	NSMutableArray *out = [NSMutableArray array];
	for (NSUInteger i = 0; i < ids.count; i++)
		[out addObject:[NSNull null]];

	__block NSUInteger remaining = ids.count;
	for (NSUInteger i = 0; i < ids.count; i++){
		NSUInteger index = i;
		[self request:@{@"@type" : @"getUser", @"user_id" : ids[i]}
		   completion:^(NSDictionary *user){
			if (!TGBIsError(user)){
				NSString *username = TGBString(
						[TGBArray(TGBDict(user[@"usernames"])[@"active_usernames"]) firstObject]);
				NSString *name = [NSString stringWithFormat:@"%@ %@",
						TGBString(user[@"first_name"]), TGBString(user[@"last_name"])];
				out[index] = @{
					@"id"       : TGBNumber(user[@"id"]),
					@"name"     : [name stringByTrimmingCharactersInSet:
							[NSCharacterSet whitespaceCharacterSet]],
					@"username" : username,
				};
			}
			if (--remaining > 0)
				return;
			NSMutableArray *clean = [NSMutableArray array];
			for (id entry in out){
				if ([entry isKindOfClass:NSDictionary.class])
					[clean addObject:entry];
			}
			if (completion)
				completion(clean);
		}];
	}
}

- (void)recentInlineBotsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getRecentInlineBots"}
	   completion:^(NSDictionary *result){
		if (TGBIsError(result)){
			if (completion)
				completion(@[]);
			return;
		}
		[self tgb_usersForIds:result[@"user_ids"] completion:completion];
	}];
}

- (void)similarBotsFor:(int64_t)botUserId
            completion:(void (^)(NSArray *, NSInteger))completion {
	[self request:@{@"@type" : @"getBotSimilarBots", @"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		if (TGBIsError(result)){
			if (completion)
				completion(@[], 0);
			return;
		}
		NSInteger total = [TGBNumber(result[@"total_count"]) integerValue];
		[self tgb_usersForIds:result[@"user_ids"] completion:^(NSArray *bots){
			if (completion)
				completion(bots, total > 0 ? total : (NSInteger)bots.count);
		}];
	}];
}

#pragma mark - message decoration

- (void)viaBotForMessage:(NSDictionary *)message completion:(void (^)(NSString *))completion {
	NSDictionary *m = TGBDict(message);
	NSNumber *botId = [m[@"via_bot_user_id"] isKindOfClass:NSNumber.class]
			? m[@"via_bot_user_id"] : m[@"viaBotId"];
	if (![botId isKindOfClass:NSNumber.class] || [botId longLongValue] == 0){
		if (completion)
			completion(nil);
		return;
	}

	[self request:@{@"@type" : @"getUser", @"user_id" : botId}
	   completion:^(NSDictionary *user){
		if (!completion)
			return;
		NSString *username = TGBString(
				[TGBArray(TGBDict(user[@"usernames"])[@"active_usernames"]) firstObject]);
		completion(username.length > 0 ? username : nil);
	}];
}

- (NSString *)botServiceTextForMessage:(NSDictionary *)message {
	NSDictionary *m = TGBDict(message);
	NSDictionary *content = TGBDict(m[@"content"]) ?: m;
	NSString *type = TGBString(content[@"@type"]);

	if ([type isEqualToString:@"messageBotWriteAccessAllowed"]){
		NSString *reason = TGBString(TGBDict(content[@"reason"])[@"@type"]);
		if ([reason isEqualToString:@"botWriteAccessAllowReasonAcceptedRequest"])
			return @"You allowed this bot to message you";
		if ([reason isEqualToString:@"botWriteAccessAllowReasonLaunchedWebApp"])
			return @"You allowed this bot to message you by opening its app";
		return @"You allowed this bot to message you";
	}

	if ([type isEqualToString:@"messageUsersShared"]){
		NSUInteger count = TGBArray(content[@"users"]).count;
		if (count == 1)
			return @"You shared a user with the bot";
		return [NSString stringWithFormat:@"You shared %lu users with the bot",
				(unsigned long)count];
	}

	if ([type isEqualToString:@"messageChatShared"])
		return @"You shared a chat with the bot";

	if ([type isEqualToString:@"messageWebAppDataSent"] ||
		[type isEqualToString:@"messageWebAppDataReceived"])
		return @"Data was sent to the bot";

	return nil;
}

@end

//
// TGClient+MessageContent - see TGClient+MessageContent.h.
//
#import "TGClient+Private.h"
#import "TGClient+MessageContent.h"

static NSDictionary *TGMCDict(id value) {
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSArray *TGMCArray(id value) {
	return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static NSString *TGMCString(id value) {
	return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSNumber *TGMCNumber(id value) {
	return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

static BOOL TGMCIsError(NSDictionary *result) {
	return !TGMCDict(result) || [TGMCString(result[@"@type"]) isEqualToString:@"error"];
}

static NSDictionary *TGMCFormattedText(NSString *text) {
	return @{@"@type" : @"formattedText", @"text" : text ?: @"", @"entities" : @[]};
}

static NSDictionary *TGMCLocalFile(NSString *path) {
	return @{@"@type" : @"inputFileLocal", @"path" : path ?: @""};
}

static NSDictionary *TGMCSelfDestruct(NSInteger seconds) {
	if (seconds <= 0)
		return nil;
	return @{@"@type" : @"messageSelfDestructTypeTimer",
			 @"self_destruct_time" : @(seconds)};
}

static NSString *TGMCEntityKind(NSString *typeName) {
	if ([typeName hasPrefix:@"textEntityType"])
		return [typeName substringFromIndex:14];
	return typeName ?: @"";
}

static NSArray *TGMCFlattenEntities(id rawEntities) {
	NSArray *entities = TGMCArray(rawEntities);
	NSMutableArray *out = [NSMutableArray array];
	for (id item in entities){
		NSDictionary *entity = TGMCDict(item);
		NSDictionary *type = TGMCDict(entity[@"type"]);
		if (!entity || !type)
			continue;
		[out addObject:@{
			@"offset"    : TGMCNumber(entity[@"offset"]),
			@"length"    : TGMCNumber(entity[@"length"]),
			@"kind"      : TGMCEntityKind(TGMCString(type[@"@type"])),
			@"url"       : TGMCString(type[@"url"]),
			@"userId"    : TGMCNumber(type[@"user_id"]),
			@"language"  : TGMCString(type[@"language"]),
			@"timestamp" : TGMCNumber(type[@"media_timestamp"]),
		}];
	}
	return out;
}

/// TDLib ships `bytes` fields as base64 text. iOS 6 has no public decoder
/// (-initWithBase64EncodedString:options: arrived in iOS 7), so decode by hand.
static NSData *TGMCBase64(id value) {
	NSString *encoded = TGMCString(value);
	if (!encoded.length)
		return [NSData data];

	static signed char table[256];
	static BOOL ready = NO;
	if (!ready){
		static const char *alphabet =
				"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		for (int i = 0; i < 256; i++)
			table[i] = -1;
		for (int i = 0; i < 64; i++)
			table[(unsigned char)alphabet[i]] = (signed char)i;
		table[(unsigned char)'-'] = 62;
		table[(unsigned char)'_'] = 63;
		ready = YES;
	}

	NSMutableData *out = nil;
	@autoreleasepool {
		NSData *ascii = [encoded dataUsingEncoding:NSASCIIStringEncoding];
		const unsigned char *src = ascii.bytes;
		NSUInteger length = ascii.length;
		out = [[NSMutableData alloc] initWithCapacity:(length / 4) * 3 + 3];
		unsigned char chunk[3072];
		NSUInteger filled = 0;
		unsigned int accumulator = 0;
		int bits = 0;
		for (NSUInteger i = 0; i < length; i++){
			signed char decoded = table[src[i]];
			if (decoded < 0)
				continue;
			accumulator = (accumulator << 6) | (unsigned int)decoded;
			bits += 6;
			if (bits >= 8){
				bits -= 8;
				chunk[filled++] = (unsigned char)((accumulator >> bits) & 0xFF);
				if (filled == sizeof(chunk)){
					[out appendBytes:chunk length:filled];
					filled = 0;
				}
			}
		}
		if (filled)
			[out appendBytes:chunk length:filled];
	}
	return out;
}

static NSNumber *TGMCFileId(id file) {
	NSDictionary *dict = TGMCDict(file);
	return dict ? TGMCNumber(dict[@"id"]) : @0;
}

static NSNumber *TGMCThumbId(id owner) {
	NSDictionary *dict = TGMCDict(owner);
	NSDictionary *thumbnail = TGMCDict(dict[@"thumbnail"]);
	return TGMCFileId(thumbnail[@"file"]);
}

static NSDictionary *TGMCMediaInfo(NSDictionary *message) {
	NSDictionary *content = TGMCDict(message[@"content"]);
	NSString *kind = TGMCString(content[@"@type"]);
	if (!content.count)
		return nil;

	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	info[@"kind"]       = kind;
	info[@"fileId"]     = @0;
	info[@"thumbId"]    = @0;
	info[@"fileName"]   = @"";
	info[@"mimeType"]   = @"";
	info[@"size"]       = @0;
	info[@"width"]      = @0;
	info[@"height"]     = @0;
	info[@"duration"]   = @0;
	info[@"title"]      = @"";
	info[@"performer"]  = @"";
	info[@"waveform"]   = [NSData data];
	info[@"minithumb"]  = [NSData data];
	info[@"hasSpoiler"] = @([content[@"has_spoiler"] boolValue]);
	info[@"isSecret"]   = @([content[@"is_secret"] boolValue]);
	info[@"isViewed"]   = @([content[@"is_viewed"] boolValue] ||
							[content[@"is_listened"] boolValue]);
	info[@"caption"]    = TGMCString(TGMCDict(content[@"caption"])[@"text"]);

	NSDictionary *media = nil;
	NSDictionary *mainFile = nil;

	if ([kind isEqualToString:@"messagePhoto"]){
		NSArray *sizes = TGMCArray(TGMCDict(content[@"photo"])[@"sizes"]);
		NSDictionary *largest = TGMCDict([sizes lastObject]);
		mainFile = TGMCDict(largest[@"photo"]);
		info[@"width"]  = TGMCNumber(largest[@"width"]);
		info[@"height"] = TGMCNumber(largest[@"height"]);
		NSDictionary *smallest = TGMCDict([sizes firstObject]);
		info[@"thumbId"] = TGMCFileId(smallest[@"photo"]);
		media = TGMCDict(content[@"photo"]);

	} else if ([kind isEqualToString:@"messageVideo"]){
		media = TGMCDict(content[@"video"]);
		mainFile = TGMCDict(media[@"video"]);

	} else if ([kind isEqualToString:@"messageAnimation"]){
		media = TGMCDict(content[@"animation"]);
		mainFile = TGMCDict(media[@"animation"]);

	} else if ([kind isEqualToString:@"messageDocument"]){
		media = TGMCDict(content[@"document"]);
		mainFile = TGMCDict(media[@"document"]);

	} else if ([kind isEqualToString:@"messageAudio"]){
		media = TGMCDict(content[@"audio"]);
		mainFile = TGMCDict(media[@"audio"]);
		info[@"title"]     = TGMCString(media[@"title"]);
		info[@"performer"] = TGMCString(media[@"performer"]);
		NSDictionary *cover = TGMCDict(media[@"album_cover_thumbnail"]);
		info[@"thumbId"] = TGMCFileId(cover[@"file"]);

	} else if ([kind isEqualToString:@"messageVoiceNote"]){
		media = TGMCDict(content[@"voice_note"]);
		mainFile = TGMCDict(media[@"voice"]);
		info[@"waveform"] = TGMCBase64(media[@"waveform"]);

	} else if ([kind isEqualToString:@"messageVideoNote"]){
		media = TGMCDict(content[@"video_note"]);
		mainFile = TGMCDict(media[@"video"]);
		info[@"width"]  = TGMCNumber(media[@"length"]);
		info[@"height"] = TGMCNumber(media[@"length"]);

	} else if ([kind isEqualToString:@"messageSticker"] ||
			   [kind isEqualToString:@"messageAnimatedEmoji"]){
		media = [kind isEqualToString:@"messageSticker"]
			? TGMCDict(content[@"sticker"])
			: TGMCDict(TGMCDict(content[@"animated_emoji"])[@"sticker"]);
		mainFile = TGMCDict(media[@"sticker"]);
		info[@"title"] = TGMCString(media[@"emoji"]);

	} else {
		return nil;
	}

	if (media){
		if ([TGMCNumber(info[@"width"]) integerValue] == 0)
			info[@"width"] = TGMCNumber(media[@"width"]);
		if ([TGMCNumber(info[@"height"]) integerValue] == 0)
			info[@"height"] = TGMCNumber(media[@"height"]);
		info[@"duration"] = TGMCNumber(media[@"duration"]);
		info[@"fileName"] = TGMCString(media[@"file_name"]);
		info[@"mimeType"] = TGMCString(media[@"mime_type"]);
		if ([TGMCNumber(info[@"thumbId"]) integerValue] == 0)
			info[@"thumbId"] = TGMCThumbId(media);
		NSDictionary *mini = TGMCDict(media[@"minithumbnail"]);
		if (mini)
			info[@"minithumb"] = TGMCBase64(mini[@"data"]);
	}

	if (mainFile){
		info[@"fileId"] = TGMCNumber(mainFile[@"id"]);
		info[@"size"]   = TGMCNumber(mainFile[@"size"]);
	}

	return info;
}

@implementation TGClient (MessageContent)

- (NSDictionary *)mc_sendRequestForChat:(int64_t)chatId
								 thread:(int64_t)threadId
								content:(NSDictionary *)content
								replyTo:(int64_t)replyToId {
	NSMutableDictionary *request = [@{
		@"@type"                 : @"sendMessage",
		@"chat_id"               : @(chatId),
		@"input_message_content" : content ?: @{},
	} mutableCopy];

	if (threadId != 0){
		request[@"topic_id"] = @{@"@type" : @"messageTopicForum",
								 @"forum_topic_id" : @((int32_t)threadId)};
	}
	if (replyToId != 0)
		request[@"reply_to"] = @{@"@type" : @"inputMessageReplyToMessage",
								 @"message_id" : @(replyToId)};
	return request;
}

- (void)mc_send:(NSDictionary *)content
		 toChat:(int64_t)chatId
		 thread:(int64_t)threadId
	 completion:(void (^)(int64_t messageId))completion {
	NSDictionary *request = [self mc_sendRequestForChat:chatId
												 thread:threadId
												content:content
												replyTo:0];
	[self request:request completion:^(NSDictionary *result){
		if (TGMCIsError(result))
			NSLog(@"TGClient: send rejected: %@ %@", result[@"code"], result[@"message"]);
		if (completion)
			completion(TGMCIsError(result) ? 0 : [TGMCNumber(result[@"id"]) longLongValue]);
	}];
}

- (void)mc_parse:(NSString *)text completion:(void (^)(NSDictionary *formatted))completion {
	if (!text.length){
		if (completion) completion(TGMCFormattedText(@""));
		return;
	}
	[self request:@{
		@"@type"      : @"parseTextEntities",
		@"text"       : text,
		@"parse_mode" : @{@"@type" : @"textParseModeMarkdown", @"version" : @2},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMCIsError(result) || !TGMCString(result[@"text"]).length){
			completion(TGMCFormattedText(text));
			return;
		}
		completion(@{@"@type"    : @"formattedText",
					 @"text"     : TGMCString(result[@"text"]),
					 @"entities" : TGMCArray(result[@"entities"]) ?: @[]});
	}];
}

#pragma mark - text entities

- (void)parseMarkdown:(NSString *)text
		   completion:(void (^)(NSString *, NSArray *))completion {
	[self mc_parse:text completion:^(NSDictionary *formatted){
		if (completion)
			completion(TGMCString(formatted[@"text"]),
					   TGMCFlattenEntities(formatted[@"entities"]));
	}];
}

- (void)entitiesInText:(NSString *)text completion:(void (^)(NSArray *))completion {
	if (!text.length){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type" : @"getTextEntities", @"text" : text}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMCIsError(result) ? @[] : TGMCFlattenEntities(result[@"entities"]));
	}];
}

- (void)sendMarkdown:(NSString *)text
			  toChat:(int64_t)chatId
			  thread:(int64_t)threadId
			 replyTo:(int64_t)replyToId {
	if (!text.length)
		return;
	__weak TGClient *weakSelf = self;
	[self mc_parse:text completion:^(NSDictionary *formatted){
		TGClient *strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSDictionary *content = @{@"@type" : @"inputMessageText", @"text" : formatted};
		[strongSelf send:[strongSelf mc_sendRequestForChat:chatId
													thread:threadId
												   content:content
												   replyTo:replyToId]];
	}];
}

- (void)formattedTextForMessage:(int64_t)messageId
						 inChat:(int64_t)chatId
					 completion:(void (^)(NSString *, NSArray *))completion {
	[self request:@{@"@type" : @"getMessage",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSDictionary *content = TGMCDict(result[@"content"]);
		NSDictionary *formatted = TGMCDict(content[@"text"]) ?: TGMCDict(content[@"caption"]);
		if (TGMCIsError(result) || !formatted){
			completion(@"", @[]);
			return;
		}
		completion(TGMCString(formatted[@"text"]),
				   TGMCFlattenEntities(formatted[@"entities"]));
	}];
}

- (void)editCaptionOfMessage:(int64_t)messageId
					  inChat:(int64_t)chatId
					 caption:(NSString *)caption
				  completion:(void (^)(BOOL))completion {
	__weak TGClient *weakSelf = self;
	[self mc_parse:caption completion:^(NSDictionary *formatted){
		TGClient *strongSelf = weakSelf;
		if (!strongSelf){
			if (completion) completion(NO);
			return;
		}
		[strongSelf request:@{
			@"@type"      : @"editMessageCaption",
			@"chat_id"    : @(chatId),
			@"message_id" : @(messageId),
			@"caption"    : formatted,
		} completion:^(NSDictionary *result){
			if (completion) completion(!TGMCIsError(result));
		}];
	}];
}

#pragma mark - inspecting media

- (void)mediaInfoForMessage:(int64_t)messageId
					 inChat:(int64_t)chatId
				 completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getMessage",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMCIsError(result) ? nil : TGMCMediaInfo(result));
	}];
}

- (void)openContentOfMessage:(int64_t)messageId inChat:(int64_t)chatId {
	[self send:@{@"@type" : @"openMessageContent",
				 @"chat_id" : @(chatId),
				 @"message_id" : @(messageId)}];
}

- (NSString *)placeholderTextForContentKind:(NSString *)kind {
	if ([kind isEqualToString:@"messageExpiredPhoto"])
		return @"Photo has expired";
	if ([kind isEqualToString:@"messageExpiredVideo"])
		return @"Video has expired";
	if ([kind isEqualToString:@"messageExpiredVoiceNote"])
		return @"Voice message has expired";
	if ([kind isEqualToString:@"messageExpiredVideoNote"])
		return @"Video message has expired";
	if ([kind isEqualToString:@"messageUnsupported"])
		return @"This message is not supported on this device";
	return nil;
}

#pragma mark - sending media

- (void)sendPhotoAtPath:(NSString *)path
				 toChat:(int64_t)chatId
				 thread:(int64_t)threadId
				caption:(NSString *)caption
				spoiler:(BOOL)spoiler
	 selfDestructSeconds:(NSInteger)selfDestructSeconds {
	if (!path.length)
		return;
	__weak TGClient *weakSelf = self;
	[self mc_parse:caption completion:^(NSDictionary *formatted){
		TGClient *strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSMutableDictionary *content = [@{
			@"@type"       : @"inputMessagePhoto",
			@"photo"       : @{@"@type" : @"inputPhoto",
							   @"photo" : TGMCLocalFile(path)},
			@"caption"     : formatted,
			@"has_spoiler" : @(spoiler),
		} mutableCopy];
		NSDictionary *destruct = TGMCSelfDestruct(selfDestructSeconds);
		if (destruct)
			content[@"self_destruct_type"] = destruct;
		[strongSelf mc_send:content toChat:chatId thread:threadId completion:nil];
	}];
}

- (void)sendVideoAtPath:(NSString *)path
				 toChat:(int64_t)chatId
				 thread:(int64_t)threadId
				caption:(NSString *)caption
			   duration:(NSInteger)duration
				  width:(NSInteger)width
				 height:(NSInteger)height
				spoiler:(BOOL)spoiler
	 selfDestructSeconds:(NSInteger)selfDestructSeconds {
	if (!path.length)
		return;
	__weak TGClient *weakSelf = self;
	[self mc_parse:caption completion:^(NSDictionary *formatted){
		TGClient *strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSMutableDictionary *content = [@{
			@"@type"       : @"inputMessageVideo",
			@"video"       : @{@"@type"    : @"inputVideo",
							   @"video"    : TGMCLocalFile(path),
							   @"duration" : @(duration),
							   @"width"    : @(width),
							   @"height"   : @(height)},
			@"caption"     : formatted,
			@"has_spoiler" : @(spoiler),
		} mutableCopy];
		NSDictionary *destruct = TGMCSelfDestruct(selfDestructSeconds);
		if (destruct)
			content[@"self_destruct_type"] = destruct;
		[strongSelf mc_send:content toChat:chatId thread:threadId completion:nil];
	}];
}

- (void)sendAnimationAtPath:(NSString *)path
					 toChat:(int64_t)chatId
					 thread:(int64_t)threadId
					caption:(NSString *)caption {
	if (!path.length)
		return;
	__weak TGClient *weakSelf = self;
	[self mc_parse:caption completion:^(NSDictionary *formatted){
		TGClient *strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf mc_send:@{
			@"@type"     : @"inputMessageAnimation",
			@"animation" : @{@"@type" : @"inputAnimation",
							 @"animation" : TGMCLocalFile(path)},
			@"caption"   : formatted,
		} toChat:chatId thread:threadId completion:nil];
	}];
}

- (void)sendAudioAtPath:(NSString *)path
				 toChat:(int64_t)chatId
				 thread:(int64_t)threadId
				  title:(NSString *)title
			  performer:(NSString *)performer
			   duration:(NSInteger)duration
				caption:(NSString *)caption {
	if (!path.length)
		return;
	__weak TGClient *weakSelf = self;
	[self mc_parse:caption completion:^(NSDictionary *formatted){
		TGClient *strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf mc_send:@{
			@"@type"   : @"inputMessageAudio",
			@"audio"   : @{@"@type"     : @"inputAudio",
						   @"audio"     : TGMCLocalFile(path),
						   @"duration"  : @(duration),
						   @"title"     : title ?: @"",
						   @"performer" : performer ?: @""},
			@"caption" : formatted,
		} toChat:chatId thread:threadId completion:nil];
	}];
}

- (void)sendDocumentAtPath:(NSString *)path
					toChat:(int64_t)chatId
					thread:(int64_t)threadId
				   caption:(NSString *)caption {
	if (!path.length)
		return;
	__weak TGClient *weakSelf = self;
	[self mc_parse:caption completion:^(NSDictionary *formatted){
		TGClient *strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf mc_send:@{
			@"@type"    : @"inputMessageDocument",
			@"document" : @{@"@type"    : @"inputDocument",
							@"document" : TGMCLocalFile(path),
							@"disable_content_type_detection" : @NO},
			@"caption"  : formatted,
		} toChat:chatId thread:threadId completion:nil];
	}];
}

- (void)sendPhotoAlbumAtPaths:(NSArray *)paths
					   toChat:(int64_t)chatId
					   thread:(int64_t)threadId
					  caption:(NSString *)caption
				   completion:(void (^)(NSInteger))completion {
	NSArray *safePaths = TGMCArray(paths);
	if (!safePaths.count){
		if (completion) completion(0);
		return;
	}
	__weak TGClient *weakSelf = self;
	[self mc_parse:caption completion:^(NSDictionary *formatted){
		TGClient *strongSelf = weakSelf;
		if (!strongSelf){
			if (completion) completion(0);
			return;
		}
		NSMutableArray *contents = [NSMutableArray array];
		for (id item in safePaths){
			NSString *path = [item isKindOfClass:[NSString class]] ? item : nil;
			if (!path.length)
				continue;
			[contents addObject:@{
				@"@type"   : @"inputMessagePhoto",
				@"photo"   : @{@"@type" : @"inputPhoto",
							   @"photo" : TGMCLocalFile(path)},
				@"caption" : (contents.count == 0 ? formatted : TGMCFormattedText(@"")),
			}];
		}
		if (!contents.count){
			if (completion) completion(0);
			return;
		}
		NSMutableDictionary *request = [@{
			@"@type"                  : @"sendMessageAlbum",
			@"chat_id"                : @(chatId),
			@"input_message_contents" : contents,
		} mutableCopy];
		if (threadId != 0){
			request[@"topic_id"] = @{@"@type" : @"messageTopicForum",
									 @"forum_topic_id" : @((int32_t)threadId)};
		}
		[strongSelf request:request completion:^(NSDictionary *result){
			if (!completion)
				return;
			NSArray *messages = TGMCArray(result[@"messages"]);
			completion(TGMCIsError(result) ? 0 : (NSInteger)messages.count);
		}];
	}];
}

- (void)sendVenueWithTitle:(NSString *)title
				   address:(NSString *)address
				  latitude:(double)latitude
				 longitude:(double)longitude
					toChat:(int64_t)chatId {
	[self mc_send:@{
		@"@type" : @"inputMessageVenue",
		@"venue" : @{
			@"@type"    : @"venue",
			@"location" : @{@"@type" : @"location",
							@"latitude" : @(latitude),
							@"longitude" : @(longitude)},
			@"title"    : title ?: @"",
			@"address"  : address ?: @"",
			@"provider" : @"foursquare",
			@"id"       : @"",
			@"type"     : @"",
		},
	} toChat:chatId thread:0 completion:nil];
}

- (void)sendLiveLocationWithLatitude:(double)latitude
						   longitude:(double)longitude
							  period:(NSInteger)period
							  toChat:(int64_t)chatId
						  completion:(void (^)(int64_t))completion {
	NSInteger safePeriod = period;
	if (safePeriod < 60)
		safePeriod = 60;
	if (safePeriod > 86400)
		safePeriod = 86400;
	[self mc_send:@{
		@"@type"    : @"inputMessageLiveLocation",
		@"location" : @{
			@"@type"       : @"liveLocation",
			@"location"    : @{@"@type" : @"location",
							   @"latitude" : @(latitude),
							   @"longitude" : @(longitude)},
			@"live_period" : @(safePeriod),
			@"heading"     : @0,
			@"proximity_alert_radius" : @0,
		},
	} toChat:chatId thread:0 completion:completion];
}

- (void)updateLiveLocation:(int64_t)messageId
					inChat:(int64_t)chatId
				  latitude:(double)latitude
				 longitude:(double)longitude {
	[self send:@{
		@"@type"      : @"editMessageLiveLocation",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"location"   : @{
			@"@type"    : @"liveLocation",
			@"location" : @{@"@type" : @"location",
							@"latitude" : @(latitude),
							@"longitude" : @(longitude)},
			@"heading"  : @0,
			@"proximity_alert_radius" : @0,
		},
	}];
}

- (void)stopLiveLocation:(int64_t)messageId inChat:(int64_t)chatId {
	[self send:@{
		@"@type"      : @"editMessageLiveLocation",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"location"   : [NSNull null],
	}];
}

- (void)sendDice:(NSString *)emoji toChat:(int64_t)chatId thread:(int64_t)threadId {
	[self mc_send:@{
		@"@type"       : @"inputMessageDice",
		@"emoji"       : emoji.length ? emoji : @"\U0001F3B2",
		@"clear_draft" : @NO,
	} toChat:chatId thread:threadId completion:nil];
}

#pragma mark - polls

- (void)sendPollWithQuestion:(NSString *)question
					 options:(NSArray *)options
				   anonymous:(BOOL)anonymous
			 multipleAnswers:(BOOL)multipleAnswers
		   quizCorrectOption:(NSInteger)quizCorrectOption
			 quizExplanation:(NSString *)quizExplanation
					  toChat:(int64_t)chatId
					  thread:(int64_t)threadId
				  completion:(void (^)(int64_t))completion {
	NSArray *safeOptions = TGMCArray(options);
	if (!question.length || safeOptions.count < 2){
		if (completion) completion(0);
		return;
	}

	NSMutableArray *pollOptions = [NSMutableArray array];
	for (id item in safeOptions){
		NSString *option = [item isKindOfClass:[NSString class]] ? item : nil;
		if (!option.length)
			continue;
		[pollOptions addObject:@{@"@type" : @"inputPollOption",
								 @"text"  : TGMCFormattedText(option)}];
	}
	if (pollOptions.count < 2){
		if (completion) completion(0);
		return;
	}

	BOOL isQuiz = quizCorrectOption >= 0 &&
				  quizCorrectOption < (NSInteger)pollOptions.count;
	NSString *explanation = [quizExplanation isKindOfClass:[NSString class]]
			? quizExplanation : @"";
	if (explanation.length > 200)
		explanation = [explanation substringToIndex:200];
	NSDictionary *type = isQuiz
		? @{@"@type" : @"inputPollTypeQuiz",
			@"correct_option_ids" : @[@(quizCorrectOption)],
			@"explanation" : TGMCFormattedText(explanation)}
		: @{@"@type" : @"inputPollTypeRegular", @"allow_adding_options" : @NO};

	[self mc_send:@{
		@"@type"                  : @"inputMessagePoll",
		@"question"               : TGMCFormattedText(question),
		@"options"                : pollOptions,
		@"is_anonymous"           : @(anonymous),
		@"allows_multiple_answers": @(!isQuiz && multipleAnswers),
		@"type"                   : type,
		@"open_period"            : @0,
		@"close_date"             : @0,
		@"is_closed"              : @NO,
	} toChat:chatId thread:threadId completion:completion];
}

- (void)stopPoll:(int64_t)messageId inChat:(int64_t)chatId {
	[self send:@{@"@type" : @"stopPoll",
				 @"chat_id" : @(chatId),
				 @"message_id" : @(messageId)}];
}

- (void)votersForPollOption:(NSInteger)optionIndex
				  ofMessage:(int64_t)messageId
					 inChat:(int64_t)chatId
					  limit:(NSInteger)limit
				 completion:(void (^)(NSArray *, NSInteger))completion {
	__weak TGClient *weakSelf = self;
	[self request:@{
		@"@type"      : @"getPollVoters",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"option_id"  : @(optionIndex),
		@"offset"     : @0,
		@"limit"      : @(limit > 0 ? limit : 50),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMCIsError(result)){
			completion(@[], 0);
			return;
		}
		TGClient *strongSelf = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (id item in TGMCArray(result[@"voters"])){
			NSDictionary *voter = TGMCDict(item);
			NSDictionary *sender = TGMCDict(voter[@"voter_id"]);
			NSNumber *userId = TGMCNumber(sender[@"user_id"]);
			if (!userId.longLongValue)
				continue;
			NSString *name = [strongSelf nameForUserId:userId.longLongValue];
			[out addObject:@{@"id" : userId, @"name" : name ?: @""}];
		}
		completion(out, [TGMCNumber(result[@"total_count"]) integerValue]);
	}];
}

#pragma mark - links

- (void)linkForMessage:(int64_t)messageId
				inChat:(int64_t)chatId
		mediaTimestamp:(NSInteger)mediaTimestamp
			  forAlbum:(BOOL)forAlbum
			completion:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"             : @"getMessageLink",
		@"chat_id"           : @(chatId),
		@"message_id"        : @(messageId),
		@"media_timestamp"   : @(mediaTimestamp > 0 ? mediaTimestamp : 0),
		@"for_album"         : @(forAlbum),
		@"in_message_thread" : @NO,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *link = TGMCString(result[@"link"]);
		completion((TGMCIsError(result) || !link.length) ? nil : link);
	}];
}

- (void)resolveMessageLink:(NSString *)url
				completion:(void (^)(NSDictionary *))completion {
	if (!url.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getMessageLinkInfo", @"url" : url}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMCIsError(result)){
			completion(nil);
			return;
		}
		NSDictionary *message = TGMCDict(result[@"message"]);
		completion(@{
			@"chatId"         : TGMCNumber(result[@"chat_id"]),
			@"messageId"      : TGMCNumber(message[@"id"]),
			@"mediaTimestamp" : TGMCNumber(result[@"media_timestamp"]),
		});
	}];
}

- (void)linkPreviewForText:(NSString *)text
				completion:(void (^)(NSDictionary *))completion {
	if (!text.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type" : @"getLinkPreview",
		@"text"  : TGMCFormattedText(text),
		@"link_preview_options" : @{@"@type" : @"linkPreviewOptions",
									@"is_disabled" : @NO},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMCIsError(result)){
			completion(nil);
			return;
		}
		NSDictionary *type = TGMCDict(result[@"type"]);
		NSNumber *photoId = @0;
		NSDictionary *photo = TGMCDict(type[@"photo"]);
		NSArray *sizes = TGMCArray(photo[@"sizes"]);
		if (sizes.count)
			photoId = TGMCFileId(TGMCDict([sizes lastObject])[@"photo"]);
		completion(@{
			@"url"         : TGMCString(result[@"url"]),
			@"siteName"    : TGMCString(result[@"site_name"]),
			@"title"       : TGMCString(result[@"title"]),
			@"description" : TGMCString(TGMCDict(result[@"description"])[@"text"]),
			@"kind"        : TGMCString(type[@"@type"]),
			@"photoId"     : photoId,
		});
	}];
}

#pragma mark - odds and ends

- (void)translateMessage:(int64_t)messageId
				  inChat:(int64_t)chatId
			  toLanguage:(NSString *)languageCode
			  completion:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"            : @"translateMessageText",
		@"chat_id"          : @(chatId),
		@"message_id"       : @(messageId),
		@"to_language_code" : languageCode.length ? languageCode : @"en",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *text = TGMCString(result[@"text"]);
		completion((TGMCIsError(result) || !text.length) ? nil : text);
	}];
}

- (void)mapThumbnailForLatitude:(double)latitude
					  longitude:(double)longitude
						   zoom:(NSInteger)zoom
						  width:(NSInteger)width
						 height:(NSInteger)height
						  scale:(NSInteger)scale
						 inChat:(int64_t)chatId
					 completion:(void (^)(NSInteger))completion {
	[self request:@{
		@"@type"    : @"getMapThumbnailFile",
		@"location" : @{@"@type" : @"location",
						@"latitude" : @(latitude),
						@"longitude" : @(longitude)},
		@"zoom"     : @(zoom > 0 ? zoom : 16),
		@"width"    : @(width > 0 ? width : 320),
		@"height"   : @(height > 0 ? height : 160),
		@"scale"    : @(scale > 0 ? scale : 1),
		@"chat_id"  : @(chatId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGMCIsError(result) ? 0 : [TGMCNumber(result[@"id"]) integerValue]);
	}];
}

- (void)clickAnimatedEmojiInMessage:(int64_t)messageId
							 inChat:(int64_t)chatId
						 completion:(void (^)(NSInteger))completion {
	[self request:@{@"@type" : @"clickAnimatedEmojiMessage",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGMCIsError(result)){
			completion(0);
			return;
		}
		completion([TGMCFileId(result[@"sticker"]) integerValue]);
	}];
}

- (void)storyForMessage:(int64_t)messageId
				 inChat:(int64_t)chatId
			 completion:(void (^)(NSDictionary *))completion {
	__weak TGClient *weakSelf = self;
	[self request:@{@"@type" : @"getMessage",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *message){
		TGClient *strongSelf = weakSelf;
		NSDictionary *content = TGMCDict(message[@"content"]);
		if (!strongSelf || TGMCIsError(message) ||
			![TGMCString(content[@"@type"]) isEqualToString:@"messageStory"]){
			if (completion) completion(nil);
			return;
		}
		[strongSelf request:@{
			@"@type"                : @"getStory",
			@"story_poster_chat_id" : TGMCNumber(content[@"story_poster_chat_id"]),
			@"story_id"             : TGMCNumber(content[@"story_id"]),
			@"only_local"           : @NO,
		} completion:^(NSDictionary *story){
			if (!completion)
				return;
			if (TGMCIsError(story)){
				completion(nil);
				return;
			}
			NSDictionary *storyContent = TGMCDict(story[@"content"]);
			NSString *kind = TGMCString(storyContent[@"@type"]);
			BOOL isVideo = [kind isEqualToString:@"storyContentVideo"];
			NSNumber *fileId = @0;
			NSNumber *thumbId = @0;
			if (isVideo){
				NSDictionary *video = TGMCDict(storyContent[@"video"]);
				fileId  = TGMCFileId(video[@"video"]);
				thumbId = TGMCThumbId(video);
			} else {
				NSArray *sizes = TGMCArray(TGMCDict(storyContent[@"photo"])[@"sizes"]);
				if (sizes.count){
					fileId  = TGMCFileId(TGMCDict([sizes lastObject])[@"photo"]);
					thumbId = TGMCFileId(TGMCDict([sizes firstObject])[@"photo"]);
				}
			}
			completion(@{
				@"caption" : TGMCString(TGMCDict(story[@"caption"])[@"text"]),
				@"date"    : TGMCNumber(story[@"date"]),
				@"isVideo" : @(isVideo),
				@"fileId"  : fileId,
				@"thumbId" : thumbId,
			});
		}];
	}];
}

@end

// vim:ft=objc

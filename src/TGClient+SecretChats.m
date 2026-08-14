#import "TGClient+Private.h"
#import "TGClient+SecretChats.h"

static NSMutableDictionary *TGSecretChatIds(void){
	static NSMutableDictionary *map = nil;
	if (!map)
		map = [[NSMutableDictionary alloc] init];
	return map;
}

static BOOL TGScIsError(NSDictionary *result){
	return ![result isKindOfClass:NSDictionary.class] ||
	       [result[@"@type"] isEqualToString:@"error"];
}

static NSDictionary *TGScDict(id value){
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSString *TGScString(id value){
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSNumber *TGScNumber(id value){
	return [value isKindOfClass:NSNumber.class] ? value : @(0);
}

static NSString *TGScStateName(NSDictionary *secretChat){
	NSString *type = TGScString(TGScDict(secretChat[@"state"])[@"@type"]);
	if ([type isEqualToString:@"secretChatStateReady"])
		return @"ready";
	if ([type isEqualToString:@"secretChatStateClosed"])
		return @"closed";
	return @"pending";
}

static NSData *TGScBase64Decode(NSString *string){
	if (![string isKindOfClass:NSString.class] || string.length == 0)
		return nil;

	static signed char table[128];
	static BOOL ready = NO;
	if (!ready){
		for (int i = 0; i < 128; i++)
			table[i] = -1;
		const char *alphabet =
			"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		for (int i = 0; i < 64; i++)
			table[(int)alphabet[i]] = (signed char)i;
		table[(int)'-'] = 62;
		table[(int)'_'] = 63;
		ready = YES;
	}

	const char *chars = [string UTF8String];
	if (!chars)
		return nil;

	NSMutableData *out = [NSMutableData dataWithCapacity:string.length];
	uint32_t bits = 0;
	int have = 0;
	for (const char *p = chars; *p; p++){
		unsigned char c = (unsigned char)*p;
		if (c >= 128 || table[c] < 0)
			continue;
		bits = (bits << 6) | (uint32_t)table[c];
		have += 6;
		if (have >= 8){
			have -= 8;
			unsigned char byte = (unsigned char)((bits >> have) & 0xFF);
			[out appendBytes:&byte length:1];
		}
	}
	return out.length ? out : nil;
}

@implementation TGClient (SecretChats)

#pragma mark - internals

- (void)tgSecretRemember:(NSDictionary *)chat {
	NSDictionary *type = TGScDict(chat[@"type"]);
	NSNumber *chatId = TGScNumber(chat[@"id"]);
	if (!type || chatId.longLongValue == 0)
		return;
	if (![TGScString(type[@"@type"]) isEqualToString:@"chatTypeSecret"]){
		TGSecretChatIds()[chatId] = @(0);
		return;
	}
	TGSecretChatIds()[chatId] = TGScNumber(type[@"secret_chat_id"]);
}

- (void)tgSecretFetchChat:(int64_t)chatId completion:(void (^)(NSDictionary *chat))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (TGScIsError(chat)){
			if (completion) completion(nil);
			return;
		}
		[weakSelf tgSecretRemember:chat];
		if (completion) completion(chat);
	}];
}

- (NSDictionary *)tgSecretInfoFrom:(NSDictionary *)secretChat chatId:(int64_t)chatId {
	if (!TGScDict(secretChat))
		return nil;
	int64_t userId = [TGScNumber(secretChat[@"user_id"]) longLongValue];
	NSString *name = [self nameForUserId:userId] ?: @"";
	return @{
		@"secretChatId" : TGScNumber(secretChat[@"id"]),
		@"chatId"       : @(chatId),
		@"userId"       : @(userId),
		@"name"         : name,
		@"state"        : TGScStateName(secretChat),
		@"isOutbound"   : @([secretChat[@"is_outbound"] boolValue]),
		@"layer"        : TGScNumber(secretChat[@"layer"]),
		@"keyHash"      : TGScString(secretChat[@"key_hash"]),
	};
}

#pragma mark - lifecycle

- (void)createSecretChatWithUser:(int64_t)userId
                      completion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"createNewSecretChat", @"user_id" : @(userId)}
	   completion:^(NSDictionary *chat){
		if (TGScIsError(chat)){
			if (completion) completion(nil);
			return;
		}
		TGClient *me = weakSelf;
		[me tgSecretRemember:chat];
		int64_t chatId = [TGScNumber(chat[@"id"]) longLongValue];
		int secretId = (int)[TGScNumber(TGScDict(chat[@"type"])[@"secret_chat_id"]) intValue];
		if (!completion)
			return;
		if (secretId == 0){
			completion(nil);
			return;
		}
		[me request:@{@"@type" : @"getSecretChat", @"secret_chat_id" : @(secretId)}
		 completion:^(NSDictionary *secret){
			if (TGScIsError(secret)){
				completion(@{
					@"secretChatId" : @(secretId),
					@"chatId"       : @(chatId),
					@"userId"       : @(userId),
					@"name"         : [me nameForUserId:userId] ?: @"",
					@"state"        : @"pending",
					@"isOutbound"   : @YES,
					@"layer"        : @(0),
					@"keyHash"      : @"",
				});
				return;
			}
			completion([me tgSecretInfoFrom:secret chatId:chatId]);
		}];
	}];
}

- (void)openSecretChatId:(int)secretChatId
              completion:(void (^)(int64_t))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"createSecretChat", @"secret_chat_id" : @(secretChatId)}
	   completion:^(NSDictionary *chat){
		if (TGScIsError(chat)){
			if (completion) completion(0);
			return;
		}
		[weakSelf tgSecretRemember:chat];
		if (completion) completion([TGScNumber(chat[@"id"]) longLongValue]);
	}];
}

- (void)closeSecretChatId:(int)secretChatId {
	if (secretChatId == 0)
		return;
	[self send:@{@"@type" : @"closeSecretChat", @"secret_chat_id" : @(secretChatId)}];
}

- (void)closeSecretChatForChat:(int64_t)chatId deleteHistory:(BOOL)deleteHistory {
	__weak typeof(self) weakSelf = self;
	void (^finish)(int) = ^(int secretId){
		TGClient *me = weakSelf;
		if (!me)
			return;
		[me closeSecretChatId:secretId];
		if (!deleteHistory)
			return;
		[me send:@{
			@"@type"                 : @"deleteChatHistory",
			@"chat_id"               : @(chatId),
			@"remove_from_chat_list" : @YES,
			@"revoke"                : @NO,
		}];
	};

	int known = [self secretChatIdForChat:chatId];
	if (known != 0){
		finish(known);
		return;
	}
	[self tgSecretFetchChat:chatId completion:^(NSDictionary *chat){
		finish((int)[TGScNumber(TGScDict(chat[@"type"])[@"secret_chat_id"]) intValue]);
	}];
}

#pragma mark - state

- (int)secretChatIdForChat:(int64_t)chatId {
	NSNumber *known = TGSecretChatIds()[@(chatId)];
	if (known)
		return [known intValue];
	[self tgSecretFetchChat:chatId completion:nil];
	return 0;
}

- (BOOL)isSecretChat:(int64_t)chatId {
	return [self secretChatIdForChat:chatId] != 0;
}

- (void)secretChatInfo:(int)secretChatId
            completion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getSecretChat", @"secret_chat_id" : @(secretChatId)}
	   completion:^(NSDictionary *secret){
		if (!completion)
			return;
		if (TGScIsError(secret)){
			completion(nil);
			return;
		}
		completion([weakSelf tgSecretInfoFrom:secret chatId:0]);
	}];
}

- (void)secretChatInfoForChat:(int64_t)chatId
                   completion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	void (^withSecretId)(int) = ^(int secretId){
		TGClient *me = weakSelf;
		if (secretId == 0 || !me){
			if (completion) completion(nil);
			return;
		}
		[me request:@{@"@type" : @"getSecretChat", @"secret_chat_id" : @(secretId)}
		 completion:^(NSDictionary *secret){
			if (!completion)
				return;
			if (TGScIsError(secret)){
				completion(nil);
				return;
			}
			completion([me tgSecretInfoFrom:secret chatId:chatId]);
		}];
	};

	NSNumber *known = TGSecretChatIds()[@(chatId)];
	if (known){
		withSecretId([known intValue]);
		return;
	}
	[self tgSecretFetchChat:chatId completion:^(NSDictionary *chat){
		withSecretId((int)[TGScNumber(TGScDict(chat[@"type"])[@"secret_chat_id"]) intValue]);
	}];
}

- (void)secretChatStatusForChat:(int64_t)chatId
                     completion:(void (^)(NSString *))completion {
	[self secretChatInfoForChat:chatId completion:^(NSDictionary *info){
		if (!completion)
			return;
		if (!info){
			completion(nil);
			return;
		}
		NSString *state = info[@"state"];
		if ([state isEqualToString:@"ready"]){
			completion(nil);
			return;
		}
		if ([state isEqualToString:@"closed"]){
			completion(@"secret chat cancelled");
			return;
		}
		NSString *name = [info[@"name"] length] ? info[@"name"] : @"the other party";
		if ([info[@"isOutbound"] boolValue])
			completion([NSString stringWithFormat:@"waiting for %@ to come online", name]);
		else
			completion(@"exchanging encryption keys");
	}];
}

- (void)canSendInSecretChat:(int64_t)chatId
                 completion:(void (^)(BOOL, NSString *))completion {
	[self secretChatInfoForChat:chatId completion:^(NSDictionary *info){
		if (!completion)
			return;
		if (!info){
			completion(YES, @"");
			return;
		}
		NSString *state = info[@"state"];
		completion([state isEqualToString:@"ready"], state);
	}];
}

#pragma mark - encryption key

- (void)encryptionKeyGridForChat:(int64_t)chatId
                      completion:(void (^)(NSArray *))completion {
	[self encryptionKeyHashForChat:chatId completion:^(NSString *base64){
		if (!completion)
			return;
		NSData *hash = TGScBase64Decode(base64);
		if (hash.length < 36){
			completion(nil);
			return;
		}
		const unsigned char *bytes = hash.bytes;
		NSMutableArray *cells = [NSMutableArray arrayWithCapacity:144];
		for (NSUInteger i = 0; i < 36; i++){
			unsigned char byte = bytes[i];
			[cells addObject:@((byte >> 6) & 0x03)];
			[cells addObject:@((byte >> 4) & 0x03)];
			[cells addObject:@((byte >> 2) & 0x03)];
			[cells addObject:@(byte & 0x03)];
		}
		completion(cells);
	}];
}

- (void)encryptionKeyHashForChat:(int64_t)chatId
                      completion:(void (^)(NSString *))completion {
	[self secretChatInfoForChat:chatId completion:^(NSDictionary *info){
		if (!completion)
			return;
		completion(info[@"keyHash"] ?: @"");
	}];
}

#pragma mark - capability gating

- (void)secretChat:(int64_t)chatId
   supportsFeature:(NSString *)feature
        completion:(void (^)(BOOL))completion {
	[self secretChatInfoForChat:chatId completion:^(NSDictionary *info){
		if (!completion)
			return;
		if (!info){
			completion(NO);
			return;
		}
		NSInteger layer = [info[@"layer"] integerValue];
		NSInteger needed = 46;
		if ([feature isEqualToString:@"video_note"])
			needed = 66;
		else if ([feature isEqualToString:@"delete_for_both"])
			needed = 17;
		else if ([feature isEqualToString:@"sticker"])
			needed = 45;
		completion(layer >= needed && [info[@"state"] isEqualToString:@"ready"]);
	}];
}

- (BOOL)secretChat:(int64_t)chatId allowsInputMessage:(NSString *)kind {
	if (![self isSecretChat:chatId])
		return YES;
	if (![kind isKindOfClass:NSString.class])
		return YES;

	static NSSet *forbidden = nil;
	if (!forbidden){
		forbidden = [[NSSet alloc] initWithObjects:
					 @"inputMessagePoll",
					 @"inputMessageChecklist",
					 @"inputMessageForwarded",
					 @"inputMessageStory",
					 @"inputMessageReplyToExternalMessage",
					 @"inputMessageInvoice",
					 @"inputMessageGame",
					 nil];
	}
	return ![forbidden containsObject:kind];
}

- (BOOL)chatAllowsMessageEditing:(int64_t)chatId {
	return ![self isSecretChat:chatId];
}

#pragma mark - self-destruct timer

- (void)autoDeleteTimeForChat:(int64_t)chatId
                   completion:(void (^)(NSInteger))completion {
	[self tgSecretFetchChat:chatId completion:^(NSDictionary *chat){
		if (completion)
			completion([TGScNumber(chat[@"message_auto_delete_time"]) integerValue]);
	}];
}

+ (NSArray *)autoDeleteLadder {
	NSArray *values = @[@(0), @(1), @(2), @(5), @(10), @(30),
						@(60), @(3600), @(86400), @(604800)];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:values.count];
	for (NSNumber *value in values){
		[out addObject:@{
			@"seconds" : value,
			@"title"   : [self autoDeleteTitleForSeconds:[value integerValue]],
		}];
	}
	return out;
}

+ (NSString *)autoDeleteTitleForSeconds:(NSInteger)seconds {
	if (seconds <= 0)
		return @"Off";
	if (seconds < 60)
		return [NSString stringWithFormat:@"%d second%s", (int)seconds,
				seconds == 1 ? "" : "s"];
	if (seconds < 3600){
		NSInteger minutes = seconds / 60;
		return [NSString stringWithFormat:@"%d minute%s", (int)minutes,
				minutes == 1 ? "" : "s"];
	}
	if (seconds < 86400){
		NSInteger hours = seconds / 3600;
		return [NSString stringWithFormat:@"%d hour%s", (int)hours,
				hours == 1 ? "" : "s"];
	}
	if (seconds < 604800){
		NSInteger days = seconds / 86400;
		return [NSString stringWithFormat:@"%d day%s", (int)days,
				days == 1 ? "" : "s"];
	}
	NSInteger weeks = seconds / 604800;
	return [NSString stringWithFormat:@"%d week%s", (int)weeks,
			weeks == 1 ? "" : "s"];
}

- (void)defaultAutoDeleteTimeWithCompletion:(void (^)(NSInteger))completion {
	[self request:@{@"@type" : @"getDefaultMessageAutoDeleteTime"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGScIsError(result)){
			completion(0);
			return;
		}
		completion([TGScNumber(result[@"time"]) integerValue]);
	}];
}

- (void)setDefaultAutoDeleteTime:(NSInteger)seconds {
	[self send:@{
		@"@type" : @"setDefaultMessageAutoDeleteTime",
		@"message_auto_delete_time" : @{
			@"@type" : @"messageAutoDeleteTime",
			@"time"  : @(seconds < 0 ? 0 : seconds),
		},
	}];
}

#pragma mark - self-destructing content

- (NSDictionary *)selfDestructInfoForMessage:(NSDictionary *)message {
	NSDictionary *msg = TGScDict(message);
	if (!msg)
		return nil;

	NSDictionary *content = TGScDict(msg[@"content"]);
	NSString *kind = TGScString(content[@"@type"]);

	NSString *expiredText = nil;
	if ([kind isEqualToString:@"messageExpiredPhoto"])
		expiredText = @"Photo has expired";
	else if ([kind isEqualToString:@"messageExpiredVideo"])
		expiredText = @"Video has expired";
	else if ([kind isEqualToString:@"messageExpiredVideoNote"])
		expiredText = @"Video message has expired";
	else if ([kind isEqualToString:@"messageExpiredVoiceNote"])
		expiredText = @"Voice message has expired";

	BOOL isSecret = [content[@"is_secret"] boolValue];

	NSDictionary *destruct = TGScDict(msg[@"self_destruct_type"]);
	NSString *destructType = TGScString(destruct[@"@type"]);
	BOOL immediate = [destructType isEqualToString:@"messageSelfDestructTypeImmediately"];
	NSInteger ttl = 0;
	if ([destructType isEqualToString:@"messageSelfDestructTypeTimer"])
		ttl = [TGScNumber(destruct[@"self_destruct_time"]) integerValue];

	if (!expiredText && !isSecret && !destruct)
		return nil;

	NSInteger remaining = (NSInteger)[TGScNumber(msg[@"self_destruct_in"]) doubleValue];
	if (remaining < 0)
		remaining = 0;

	return @{
		@"isSecret"    : @(isSecret),
		@"isExpired"   : @(expiredText != nil),
		@"expiredText" : expiredText ?: @"",
		@"ttl"         : @(ttl),
		@"immediate"   : @(immediate),
		@"remaining"   : @(remaining),
	};
}

- (NSDictionary *)selfDestructOptionForChat:(int64_t)chatId seconds:(NSInteger)seconds {
	if (![self isSecretChat:chatId])
		return nil;
	if (seconds <= 0)
		return @{@"self_destruct_type" : @{@"@type" : @"messageSelfDestructTypeImmediately"}};
	if (seconds > 60)
		seconds = 60;
	return @{@"self_destruct_type" : @{
		@"@type"             : @"messageSelfDestructTypeTimer",
		@"self_destruct_time": @(seconds),
	}};
}

#pragma mark - sessions

- (void)setSession:(int64_t)sessionId canAcceptSecretChats:(BOOL)canAccept {
	[self send:@{
		@"@type"      : @"toggleSessionCanAcceptSecretChats",
		@"session_id" : @(sessionId),
		@"can_accept_secret_chats" : @(canAccept),
	}];
}

#pragma mark - service messages

- (NSString *)secretServiceTextForMessage:(NSDictionary *)message {
	NSDictionary *msg = TGScDict(message);
	NSDictionary *content = TGScDict(msg[@"content"]);
	NSString *kind = TGScString(content[@"@type"]);

	int64_t senderId = 0;
	NSDictionary *sender = TGScDict(msg[@"sender_id"]);
	if ([TGScString(sender[@"@type"]) isEqualToString:@"messageSenderUser"])
		senderId = [TGScNumber(sender[@"user_id"]) longLongValue];

	if ([kind isEqualToString:@"messageScreenshotTaken"]){
		NSString *who = [self nameForUserId:senderId];
		if ([msg[@"is_outgoing"] boolValue])
			return @"You took a screenshot!";
		return [NSString stringWithFormat:@"%@ took a screenshot!", who.length ? who : @"Someone"];
	}

	if ([kind isEqualToString:@"messageChatSetMessageAutoDeleteTime"]){
		NSInteger seconds = [TGScNumber(content[@"message_auto_delete_time"]) integerValue];
		int64_t fromUser = [TGScNumber(content[@"from_user_id"]) longLongValue];
		NSString *who = [self nameForUserId:fromUser ?: senderId];
		if ([msg[@"is_outgoing"] boolValue])
			who = @"You";
		else if (!who.length)
			who = @"Someone";
		if (seconds <= 0)
			return [NSString stringWithFormat:@"%@ disabled the self-destruct timer", who];
		return [NSString stringWithFormat:@"%@ set the self-destruct timer to %@", who,
				[[self class] autoDeleteTitleForSeconds:seconds]];
	}

	return nil;
}

- (NSString *)textForSecretChatNotification:(NSDictionary *)notification {
	NSDictionary *note = TGScDict(notification);
	NSDictionary *type = TGScDict(note[@"type"]);
	if (![TGScString(type[@"@type"]) isEqualToString:@"notificationTypeNewSecretChat"])
		return nil;
	return @"You have a new secret chat request";
}

@end

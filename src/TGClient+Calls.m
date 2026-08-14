#import "TGClient+Calls.h"
#import "TGClient+Private.h"

static BOOL TGCallsIsError(id result){
	return ![result isKindOfClass:NSDictionary.class] ||
		   [((NSDictionary *)result)[@"@type"] isEqualToString:@"error"];
}

static NSDictionary *TGCallsDict(id value){
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *TGCallsArray(id value){
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSString *TGCallsString(id value){
	return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSNumber *TGCallsNumber(id value){
	return [value isKindOfClass:NSNumber.class] ? value : @(0);
}

static NSString *TGCallsProblemType(NSString *name){
	static NSDictionary *map = nil;
	if (!map){
		map = [[NSDictionary alloc] initWithObjectsAndKeys:
			@"callProblemEcho",            @"echo",
			@"callProblemNoise",           @"noise",
			@"callProblemInterruptions",   @"interruptions",
			@"callProblemDistortedSpeech", @"distortedSpeech",
			@"callProblemSilentLocal",     @"silentLocal",
			@"callProblemSilentRemote",    @"silentRemote",
			@"callProblemDropped",         @"dropped",
			@"callProblemDistortedVideo",  @"distortedVideo",
			@"callProblemPixelatedVideo",  @"pixelatedVideo",
			nil];
	}
	if (![name isKindOfClass:NSString.class])
		return nil;
	return map[name];
}

static NSString *TGCallsDuration(NSInteger seconds){
	if (seconds >= 3600)
		return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(seconds / 3600),
				(long)((seconds % 3600) / 60), (long)(seconds % 60)];
	return [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}

@implementation TGClient (Calls)

#pragma mark - after a call: rating and debug

- (void)tgcalls_rate:(NSDictionary *)inputCall
              rating:(NSInteger)rating
             comment:(NSString *)comment
            problems:(NSArray *)problems
          completion:(void (^)(BOOL))completion {
	NSMutableArray *encoded = [NSMutableArray array];
	for (id name in TGCallsArray(problems)){
		NSString *type = TGCallsProblemType(name);
		if (type)
			[encoded addObject:@{@"@type" : type}];
	}
	NSInteger clamped = rating < 1 ? 1 : (rating > 5 ? 5 : rating);

	[self request:@{
		@"@type"    : @"sendCallRating",
		@"call_id"  : inputCall,
		@"rating"   : @((int)clamped),
		@"comment"  : TGCallsString(comment) ?: @"",
		@"problems" : encoded,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGCallsIsError(result));
	}];
}

- (void)rateCallId:(int32_t)callId
            rating:(NSInteger)rating
           comment:(NSString *)comment
          problems:(NSArray *)problems
        completion:(void (^)(BOOL))completion {
	[self tgcalls_rate:@{@"@type" : @"inputCallDiscarded", @"call_id" : @(callId)}
				rating:rating
			   comment:comment
			  problems:problems
			completion:completion];
}

- (void)rateCallInChat:(int64_t)chatId
             messageId:(int64_t)messageId
                rating:(NSInteger)rating
               comment:(NSString *)comment
              problems:(NSArray *)problems
            completion:(void (^)(BOOL))completion {
	[self tgcalls_rate:@{@"@type"      : @"inputCallFromMessage",
						 @"chat_id"    : @(chatId),
						 @"message_id" : @(messageId)}
				rating:rating
			   comment:comment
			  problems:problems
			completion:completion];
}

- (void)sendDebugInformationForCallId:(int32_t)callId
                          information:(NSString *)information {
	NSString *text = TGCallsString(information);
	if (text.length == 0)
		return;
	[self send:@{
		@"@type"             : @"sendCallDebugInformation",
		@"call_id"           : @{@"@type" : @"inputCallDiscarded", @"call_id" : @(callId)},
		@"debug_information" : text,
	}];
}

- (void)sendLogForCallId:(int32_t)callId filePath:(NSString *)path {
	NSString *file = TGCallsString(path);
	if (file.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:file])
		return;
	[self send:@{
		@"@type"    : @"sendCallLog",
		@"call_id"  : @{@"@type" : @"inputCallDiscarded", @"call_id" : @(callId)},
		@"log_file" : @{@"@type" : @"inputFileLocal", @"path" : file},
	}];
}

#pragma mark - call log

- (NSDictionary *)tgcalls_rowForMessage:(NSDictionary *)message {
	NSDictionary *m = TGCallsDict(message);
	NSDictionary *content = TGCallsDict(m[@"content"]);
	if (!content || ![content[@"@type"] isEqualToString:@"messageCall"])
		return nil;

	NSString *reason = TGCallsString(TGCallsDict(content[@"discard_reason"])[@"@type"]) ?: @"";
	BOOL missed = [reason isEqualToString:@"callDiscardReasonMissed"] ||
				  [reason isEqualToString:@"callDiscardReasonDeclined"];
	BOOL outgoing = [TGCallsNumber(m[@"is_outgoing"]) boolValue];
	NSInteger duration = [TGCallsNumber(content[@"duration"]) integerValue];

	NSNumber *chatId = TGCallsNumber(m[@"chat_id"]);
	NSNumber *userId = TGCallsNumber(TGCallsDict(m[@"sender_id"])[@"user_id"]);
	if (userId.longLongValue == 0 && chatId.longLongValue > 0)
		userId = chatId;

	NSString *text = missed
		? (outgoing ? @"Cancelled" : @"Missed")
		: (outgoing ? @"Outgoing" : @"Incoming");
	if (!missed && duration > 0)
		text = [NSString stringWithFormat:@"%@, %@", text, TGCallsDuration(duration)];

	return @{
		@"chatId"    : chatId,
		@"messageId" : TGCallsNumber(m[@"id"]),
		@"userId"    : userId,
		@"name"      : [self nameForUserId:userId.longLongValue] ?: @"",
		@"date"      : TGCallsNumber(m[@"date"]),
		@"outgoing"  : @(outgoing),
		@"missed"    : @(missed),
		@"video"     : @([TGCallsNumber(content[@"is_video"]) boolValue]),
		@"duration"  : @(duration),
		@"text"      : text,
	};
}

- (void)callLogWithOffset:(NSString *)offset
               onlyMissed:(BOOL)onlyMissed
                    limit:(NSInteger)limit
               completion:(void (^)(NSArray *, NSString *))completion {
	NSInteger count = limit > 0 ? limit : 50;
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"       : @"searchCallMessages",
		@"offset"      : TGCallsString(offset) ?: @"",
		@"limit"       : @((int)count),
		@"only_missed" : @(onlyMissed),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCallsIsError(result)){
			completion(@[], nil);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id message in TGCallsArray(result[@"messages"])){
			NSDictionary *row = [weakSelf tgcalls_rowForMessage:message];
			if (row)
				[out addObject:row];
		}
		NSString *next = TGCallsString(result[@"next_offset"]);
		completion(out, next.length > 0 ? next : nil);
	}];
}

- (void)clearCallLogRevoke:(BOOL)revoke completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"deleteAllCallMessages", @"revoke" : @(revoke)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGCallsIsError(result));
	}];
}

- (void)frequentlyCalledContactsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"    : @"getTopChats",
		@"category" : @{@"@type" : @"topChatCategoryCalls"},
		@"limit"    : @(10),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCallsIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id item in TGCallsArray(result[@"chat_ids"])){
			if (![item isKindOfClass:NSNumber.class])
				continue;
			NSNumber *chatId = item;
			NSString *name = [weakSelf nameForUserId:chatId.longLongValue];
			[out addObject:@{
				@"chatId" : chatId,
				@"userId" : chatId,
				@"name"   : name ?: @"",
			}];
		}
		completion(out);
	}];
}

- (void)removeFrequentlyCalledChat:(int64_t)chatId {
	[self send:@{
		@"@type"    : @"removeTopChat",
		@"category" : @{@"@type" : @"topChatCategoryCalls"},
		@"chat_id"  : @(chatId),
	}];
}

#pragma mark - settings

- (void)setSessionId:(int64_t)sessionId
      canAcceptCalls:(BOOL)canAccept
          completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"            : @"toggleSessionCanAcceptCalls",
		@"session_id"       : @(sessionId),
		@"can_accept_calls" : @(canAccept),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGCallsIsError(result));
	}];
}

- (void)callNetworkUsageWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getNetworkStatistics", @"only_current" : @NO}
	   completion:^(NSDictionary *stats){
		if (!completion)
			return;
		long long sent = 0;
		long long received = 0;
		double duration = 0;
		if (!TGCallsIsError(stats)){
			for (id item in TGCallsArray(stats[@"entries"])){
				NSDictionary *entry = TGCallsDict(item);
				if (![entry[@"@type"] isEqualToString:@"networkStatisticsEntryCall"])
					continue;
				sent += [TGCallsNumber(entry[@"sent_bytes"]) longLongValue];
				received += [TGCallsNumber(entry[@"received_bytes"]) longLongValue];
				duration += [TGCallsNumber(entry[@"duration"]) doubleValue];
			}
		}
		completion(@{
			@"sent"      : @(sent),
			@"received"  : @(received),
			@"duration"  : @((long long)duration),
			@"sinceDate" : TGCallsIsError(stats) ? @(0) : TGCallsNumber(stats[@"since_date"]),
		});
	}];
}

- (void)resetNetworkUsageWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"resetNetworkStatistics"} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGCallsIsError(result));
	}];
}

#pragma mark - group calls (video chats), read-only

- (NSString *)groupCallServiceTextForContent:(NSDictionary *)content {
	NSDictionary *c = TGCallsDict(content);
	NSString *type = TGCallsString(c[@"@type"]);
	if (!type)
		return nil;

	if ([type isEqualToString:@"messageVideoChatStarted"])
		return @"Video chat started";

	if ([type isEqualToString:@"messageVideoChatEnded"]){
		NSInteger duration = [TGCallsNumber(c[@"duration"]) integerValue];
		if (duration <= 0)
			return @"Video chat ended";
		return [NSString stringWithFormat:@"Video chat ended (%@)", TGCallsDuration(duration)];
	}

	if ([type isEqualToString:@"messageVideoChatScheduled"]){
		NSInteger start = [TGCallsNumber(c[@"start_date"]) integerValue];
		if (start <= 0)
			return @"Video chat scheduled";
		NSDate *date = [NSDate dateWithTimeIntervalSince1970:start];
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterShortStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
		return [NSString stringWithFormat:@"Video chat scheduled for %@",
				[formatter stringFromDate:date]];
	}

	if ([type isEqualToString:@"messageInviteVideoChatParticipants"]){
		NSMutableArray *names = [NSMutableArray array];
		for (id item in TGCallsArray(c[@"user_ids"])){
			if (![item isKindOfClass:NSNumber.class])
				continue;
			NSString *name = [self nameForUserId:[item longLongValue]];
			if (name.length > 0)
				[names addObject:name];
		}
		if (names.count == 0)
			return @"Invited participants to the video chat";
		return [NSString stringWithFormat:@"Invited %@ to the video chat",
				[names componentsJoinedByString:@", "]];
	}

	if ([type isEqualToString:@"messageGroupCall"]){
		BOOL active = [TGCallsNumber(c[@"is_active"]) boolValue];
		BOOL missed = [TGCallsNumber(c[@"was_missed"]) boolValue];
		BOOL video = [TGCallsNumber(c[@"is_video"]) boolValue];
		NSString *kind = video ? @"Video chat" : @"Group call";
		if (active)
			return [NSString stringWithFormat:@"%@ in progress", kind];
		if (missed)
			return [NSString stringWithFormat:@"Missed %@", [kind lowercaseString]];
		NSInteger duration = [TGCallsNumber(c[@"duration"]) integerValue];
		if (duration > 0)
			return [NSString stringWithFormat:@"%@ (%@)", kind, TGCallsDuration(duration)];
		return kind;
	}

	return nil;
}

- (void)declineGroupCallInvitationInChat:(int64_t)chatId
                               messageId:(int64_t)messageId
                              completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"      : @"declineGroupCallInvitation",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGCallsIsError(result));
	}];
}

- (void)isGroupCallLink:(NSString *)url completion:(void (^)(BOOL))completion {
	NSString *link = TGCallsString(url);
	if (link.length == 0){
		if (completion)
			completion(NO);
		return;
	}
	[self request:@{@"@type" : @"getInternalLinkType", @"link" : link}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCallsIsError(result)){
			completion(NO);
			return;
		}
		NSString *type = TGCallsString(result[@"@type"]) ?: @"";
		completion([type isEqualToString:@"internalLinkTypeGroupCall"] ||
				   [type isEqualToString:@"internalLinkTypeVideoChat"]);
	}];
}

@end

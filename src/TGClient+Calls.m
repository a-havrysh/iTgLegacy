#import "TGClient+Calls.h"
#import "TGClient+Private.h"

static BOOL TGCallsIsError(id result){
	return ![result isKindOfClass:NSDictionary.class] ||
		   [((NSDictionary *)result)[@"@type"] isEqualToString:@"error"];
}

static NSArray *TGCallsArray(id value){
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSString *TGCallsString(id value){
	return [value isKindOfClass:NSString.class] ? value : nil;
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

@implementation TGClient (Calls)

#pragma mark - after a call: rating

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

@end

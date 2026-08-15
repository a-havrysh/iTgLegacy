#import "TGCallModel.h"

@interface TGCallModel ()
@property (nonatomic, assign) int32_t callId;
@property (nonatomic, assign) int64_t peerUserId;
@property (nonatomic, assign) BOOL outgoing;
@property (nonatomic, assign) BOOL video;
@property (nonatomic, assign) TGCallModelState state;
@property (nonatomic, assign) TGCallModelDiscardReason discardReason;
@property (nonatomic, copy) NSString *discardReasonName;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, copy) NSArray *emojiKey;
@property (nonatomic, copy) NSString *errorMessage;
@end

static NSDictionary *TGCallModelDict(id value) {
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSString *TGCallModelString(id value) {
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value length] ? value : nil;
	return nil;
}

static int64_t TGCallModelInt64(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value longLongValue];
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value longLongValue];
	return 0;
}

static BOOL TGCallModelBool(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value boolValue];
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value boolValue];
	return NO;
}

static TGCallModelState TGCallModelStateFromName(NSString *name) {
	if (!name)
		return TGCallModelStateUnknown;
	if ([name isEqualToString:@"callStatePending"])
		return TGCallModelStatePending;
	if ([name isEqualToString:@"callStateExchangingKeys"])
		return TGCallModelStateExchangingKeys;
	if ([name isEqualToString:@"callStateReady"])
		return TGCallModelStateReady;
	if ([name isEqualToString:@"callStateHangingUp"])
		return TGCallModelStateHangingUp;
	if ([name isEqualToString:@"callStateDiscarded"])
		return TGCallModelStateDiscarded;
	if ([name isEqualToString:@"callStateError"])
		return TGCallModelStateError;
	return TGCallModelStateUnknown;
}

static TGCallModelDiscardReason TGCallModelReasonFromName(NSString *name) {
	if (!name)
		return TGCallModelDiscardReasonEmpty;
	if ([name isEqualToString:@"callDiscardReasonMissed"])
		return TGCallModelDiscardReasonMissed;
	if ([name isEqualToString:@"callDiscardReasonDeclined"])
		return TGCallModelDiscardReasonDeclined;
	if ([name isEqualToString:@"callDiscardReasonDisconnected"])
		return TGCallModelDiscardReasonDisconnected;
	if ([name isEqualToString:@"callDiscardReasonHungUp"])
		return TGCallModelDiscardReasonHungUp;
	if ([name isEqualToString:@"callDiscardReasonUpgradeToGroupCall"])
		return TGCallModelDiscardReasonUpgradeToGroupCall;
	return TGCallModelDiscardReasonEmpty;
}

static NSArray *TGCallModelEmoji(id value) {
	if (![value isKindOfClass:[NSArray class]])
		return nil;

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
	for (id entry in (NSArray *)value){
		NSString *emoji = TGCallModelString(entry);
		if (emoji)
			[out addObject:emoji];
	}
	return [out count] ? [NSArray arrayWithArray:out] : nil;
}

@implementation TGCallModel

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;

	int64_t callId = TGCallModelInt64([dict objectForKey:@"id"]);

	NSDictionary *state = TGCallModelDict([dict objectForKey:@"state"]);
	NSString *stateName = state ? TGCallModelString([state objectForKey:@"@type"]) : nil;

	NSDictionary *reason = TGCallModelDict([dict objectForKey:@"discard_reason"]);
	if (!reason && state)
		reason = TGCallModelDict([state objectForKey:@"reason"]);
	NSString *reasonName = reason ? TGCallModelString([reason objectForKey:@"@type"]) : nil;

	NSString *flatState = TGCallModelString([dict objectForKey:@"callState"]);

	int64_t duration = TGCallModelInt64([dict objectForKey:@"duration"]);
	if (duration < 0)
		duration = 0;

	if (callId == 0 && !stateName && !reasonName && !flatState && duration == 0)
		return nil;

	TGCallModel *model = [[TGCallModel alloc] init];
	model.callId = (int32_t)callId;
	model.peerUserId = TGCallModelInt64([dict objectForKey:@"user_id"]);
	model.video = TGCallModelBool([dict objectForKey:@"is_video"]);
	model.duration = (NSInteger)duration;
	model.state = TGCallModelStateFromName(stateName);
	model.discardReasonName = reasonName;
	model.discardReason = TGCallModelReasonFromName(reasonName);

	id outgoing = [dict objectForKey:@"is_outgoing"];
	if (!outgoing)
		outgoing = [dict objectForKey:@"outgoing"];
	model.outgoing = TGCallModelBool(outgoing);

	if (state){
		model.emojiKey = TGCallModelEmoji([state objectForKey:@"emojis"]);
		NSDictionary *error = TGCallModelDict([state objectForKey:@"error"]);
		if (error)
			model.errorMessage = TGCallModelString([error objectForKey:@"message"]);
	}

	if (model.discardReason == TGCallModelDiscardReasonEmpty && flatState){
		if ([flatState isEqualToString:@"missed"])
			model.discardReason = TGCallModelDiscardReasonMissed;
		else if ([flatState isEqualToString:@"answered"])
			model.discardReason = TGCallModelDiscardReasonHungUp;
	}

	if (model.state == TGCallModelStateUnknown &&
		model.discardReason != TGCallModelDiscardReasonEmpty)
		model.state = TGCallModelStateDiscarded;

	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	if (![dicts isKindOfClass:[NSArray class]])
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:[dicts count]];
	for (id entry in dicts){
		TGCallModel *model = [self fromDictionary:entry];
		if (model)
			[out addObject:model];
	}
	return out;
}

- (BOOL)missed {
	return self.discardReason == TGCallModelDiscardReasonMissed ||
		   self.discardReason == TGCallModelDiscardReasonDeclined;
}

- (BOOL)ended {
	return self.state == TGCallModelStateDiscarded ||
		   self.state == TGCallModelStateError;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"<TGCallModel %d %@ %lds reason=%@>",
			self.callId, self.outgoing ? @"out" : @"in",
			(long)self.duration, self.discardReasonName ?: @"(none)"];
}

@end

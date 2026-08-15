#import "TGMessageModel.h"

static NSDictionary *TGMMDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *TGMMArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSString *TGMMString(id value) {
	if ([value isKindOfClass:NSString.class])
		return [(NSString *)value length] ? value : nil;
	if ([value isKindOfClass:NSNumber.class])
		return [value stringValue];
	return nil;
}

static int64_t TGMMId(id value) {
	if ([value isKindOfClass:NSNumber.class])
		return [value longLongValue];
	if ([value isKindOfClass:NSString.class])
		return [value longLongValue];
	return 0;
}

static NSInteger TGMMInteger(id value) {
	if ([value isKindOfClass:NSNumber.class])
		return [value integerValue];
	if ([value isKindOfClass:NSString.class])
		return [value integerValue];
	return 0;
}

static double TGMMDouble(id value) {
	if ([value isKindOfClass:NSNumber.class])
		return [value doubleValue];
	if ([value isKindOfClass:NSString.class])
		return [value doubleValue];
	return 0.0;
}

static BOOL TGMMBool(id value, BOOL fallback) {
	if ([value isKindOfClass:NSNumber.class])
		return [value boolValue];
	if ([value isKindOfClass:NSString.class])
		return [value boolValue];
	return fallback;
}

static NSData *TGMMData(id value) {
	if (![value isKindOfClass:NSData.class])
		return nil;
	return [(NSData *)value length] ? value : nil;
}

static TGMessageContentKind TGMMKindFromTypeName(NSString *name) {
	if (!name.length)
		return TGMessageContentKindUnknown;
	if ([name isEqualToString:@"messageText"])          return TGMessageContentKindText;
	if ([name isEqualToString:@"messagePhoto"])         return TGMessageContentKindPhoto;
	if ([name isEqualToString:@"messageVideo"])         return TGMessageContentKindVideo;
	if ([name isEqualToString:@"messageVideoNote"])     return TGMessageContentKindVideoNote;
	if ([name isEqualToString:@"messageAnimation"])     return TGMessageContentKindAnimation;
	if ([name isEqualToString:@"messageSticker"])       return TGMessageContentKindSticker;
	if ([name isEqualToString:@"messageAnimatedEmoji"]) return TGMessageContentKindAnimatedEmoji;
	if ([name isEqualToString:@"messageDocument"])      return TGMessageContentKindDocument;
	if ([name isEqualToString:@"messageVoiceNote"])     return TGMessageContentKindVoiceNote;
	if ([name isEqualToString:@"messageAudio"])         return TGMessageContentKindAudio;
	if ([name isEqualToString:@"messageContact"])       return TGMessageContentKindContact;
	if ([name isEqualToString:@"messageLocation"])      return TGMessageContentKindLocation;
	if ([name isEqualToString:@"messageLiveLocation"])  return TGMessageContentKindLiveLocation;
	if ([name isEqualToString:@"messageVenue"])         return TGMessageContentKindVenue;
	if ([name isEqualToString:@"messagePoll"])          return TGMessageContentKindPoll;
	if ([name isEqualToString:@"messageChecklist"])     return TGMessageContentKindChecklist;
	if ([name isEqualToString:@"messageCall"])          return TGMessageContentKindCall;
	if ([name isEqualToString:@"messageDice"])          return TGMessageContentKindDice;
	if ([name isEqualToString:@"messageGame"])          return TGMessageContentKindGame;
	if ([name isEqualToString:@"messageInvoice"])       return TGMessageContentKindInvoice;
	if ([name isEqualToString:@"messageStory"])         return TGMessageContentKindStory;
	if ([name isEqualToString:@"messagePaidMedia"])     return TGMessageContentKindPaidMedia;
	if ([name isEqualToString:@"messageUnsupported"])   return TGMessageContentKindUnsupported;
	if ([name hasPrefix:@"messageExpired"])             return TGMessageContentKindExpiredMedia;
	return TGMessageContentKindUnknown;
}

@interface TGMessagePollOption ()
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) NSInteger votePercentage;
@property (nonatomic, assign) BOOL isChosen;
@end

@implementation TGMessagePollOption

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:NSDictionary.class])
		return nil;

	id rawText = dict[@"text"];
	NSDictionary *nested = TGMMDict(rawText);
	NSString *text = nested ? TGMMString(nested[@"text"]) : TGMMString(rawText);
	if (!text)
		return nil;

	TGMessagePollOption *option = [[TGMessagePollOption alloc] init];
	option.text = text;

	NSInteger percentage = TGMMInteger(dict[@"vote_percentage"]);
	if (percentage == 0)
		percentage = TGMMInteger(dict[@"votePercentage"]);
	if (percentage < 0)   percentage = 0;
	if (percentage > 100) percentage = 100;
	option.votePercentage = percentage;

	option.isChosen = TGMMBool(dict[@"is_chosen"], TGMMBool(dict[@"isChosen"], NO));
	return option;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	NSArray *source = TGMMArray(dicts);
	if (!source.count)
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:source.count];
	for (id entry in source){
		TGMessagePollOption *option = [self fromDictionary:entry];
		if (option)
			[out addObject:option];
	}
	return [out copy];
}

@end

@interface TGMessageModel ()
@property (nonatomic, assign) int64_t messageId;
@property (nonatomic, assign) int64_t senderId;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *chatTitle;
@property (nonatomic, assign) NSTimeInterval date;
@property (nonatomic, assign) BOOL isOutgoing;
@property (nonatomic, assign) TGMessageContentKind kind;
@property (nonatomic, copy) NSString *kindTypeName;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) BOOL isService;
@property (nonatomic, copy) NSString *albumId;
@property (nonatomic, assign) NSInteger photoFileId;
@property (nonatomic, assign) NSInteger documentFileId;
@property (nonatomic, copy) NSString *documentName;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, copy) NSData *waveform;
@property (nonatomic, assign) double latitude;
@property (nonatomic, assign) double longitude;
@property (nonatomic, assign) BOOL hasLocation;
@property (nonatomic, assign) TGMessageCallState callState;
@property (nonatomic, copy) NSString *pollQuestion;
@property (nonatomic, copy) NSArray *pollOptions;
@property (nonatomic, assign) NSInteger pollTotalVoterCount;
@property (nonatomic, assign) BOOL pollIsClosed;
@property (nonatomic, assign) BOOL pollIsAnonymous;
@property (nonatomic, assign) int64_t replyToMessageId;
@property (nonatomic, copy) NSString *replyText;
@property (nonatomic, copy) NSString *forwardFrom;
@property (nonatomic, assign) BOOL isEdited;
@property (nonatomic, copy) NSString *reactionsSummary;
@property (nonatomic, assign) TGMessageSendState sendState;
@property (nonatomic, assign) BOOL canRetry;
@property (nonatomic, assign) NSTimeInterval scheduledSendDate;
@property (nonatomic, assign) BOOL sendWhenOnline;
@end

@implementation TGMessageModel

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:NSDictionary.class])
		return nil;

	int64_t messageId = TGMMId(dict[@"id"]);
	if (messageId == 0)
		messageId = TGMMId(dict[@"messageId"]);
	if (messageId == 0)
		return nil;

	TGMessageModel *model = [[TGMessageModel alloc] init];
	model.messageId = messageId;

	id sender = dict[@"senderId"];
	if (!sender)
		sender = TGMMDict(dict[@"sender_id"])[@"user_id"];
	model.senderId = TGMMId(sender);

	model.chatId = TGMMId(dict[@"chatId"] ?: dict[@"chat_id"]);
	model.chatTitle = TGMMString(dict[@"chatTitle"]);
	model.date = (NSTimeInterval)TGMMDouble(dict[@"date"]);
	model.isOutgoing = TGMMBool(dict[@"outgoing"], TGMMBool(dict[@"is_outgoing"], NO));

	NSString *typeName = TGMMString(dict[@"kind"]);
	model.kindTypeName = typeName ?: @"";
	TGMessageContentKind kind = TGMMKindFromTypeName(typeName);
	model.isService = TGMMBool(dict[@"service"], NO);

	NSString *text = TGMMString(dict[@"text"]);
	model.text = text ?: @"";

	model.albumId = TGMMString(dict[@"albumId"]);

	model.photoFileId = TGMMInteger(dict[@"photoId"]);
	model.documentFileId = TGMMInteger(dict[@"docId"]);
	if (model.photoFileId < 0)    model.photoFileId = 0;
	if (model.documentFileId < 0) model.documentFileId = 0;
	model.documentName = TGMMString(dict[@"docName"]);
	model.duration = TGMMInteger(dict[@"duration"]);
	if (model.duration < 0)
		model.duration = 0;
	model.waveform = TGMMData(dict[@"waveform"]);

	id latitude = dict[@"lat"];
	id longitude = dict[@"lon"];
	BOOL hasLatitude = [latitude isKindOfClass:NSNumber.class];
	BOOL hasLongitude = [longitude isKindOfClass:NSNumber.class];
	if (hasLatitude || hasLongitude){
		model.latitude = TGMMDouble(latitude);
		model.longitude = TGMMDouble(longitude);
		model.hasLocation = YES;
	}

	NSString *callState = TGMMString(dict[@"callState"]);
	if ([callState isEqualToString:@"missed"])
		model.callState = TGMessageCallStateMissed;
	else if ([callState isEqualToString:@"answered"])
		model.callState = TGMessageCallStateAnswered;
	if (model.callState != TGMessageCallStateNone)
		kind = TGMessageContentKindCall;

	NSString *question = TGMMString(dict[@"pollQuestion"]);
	NSArray *options = [TGMessagePollOption arrayFromDictionaries:dict[@"pollOptions"]];
	model.pollOptions = options;
	if (question || options.count){
		model.pollQuestion = question;
		model.pollTotalVoterCount = TGMMInteger(dict[@"pollTotal"]);
		if (model.pollTotalVoterCount < 0)
			model.pollTotalVoterCount = 0;
		model.pollIsClosed = TGMMBool(dict[@"pollClosed"], NO);
		model.pollIsAnonymous = TGMMBool(dict[@"pollAnonymous"], YES);
		kind = TGMessageContentKindPoll;
	} else {
		model.pollIsAnonymous = YES;
	}

	model.replyToMessageId = TGMMId(dict[@"replyId"]);
	model.replyText = TGMMString(dict[@"replyText"]);
	model.forwardFrom = TGMMString(dict[@"forward"]);
	model.isEdited = TGMMBool(dict[@"edited"], NO);
	model.reactionsSummary = TGMMString(dict[@"reactions"]);

	NSString *state = TGMMString(dict[@"sendState"]);
	if (!state){
		NSString *raw = TGMMDict(dict[@"sending_state"])[@"@type"];
		if ([raw isKindOfClass:NSString.class]){
			if ([raw isEqualToString:@"messageSendingStatePending"])
				state = @"pending";
			else if ([raw isEqualToString:@"messageSendingStateFailed"])
				state = @"failed";
		}
	}
	if ([state isEqualToString:@"pending"])
		model.sendState = TGMessageSendStatePending;
	else if ([state isEqualToString:@"failed"])
		model.sendState = TGMessageSendStateFailed;
	if (model.sendState == TGMessageSendStateFailed){
		id retry = dict[@"canRetry"];
		if (!retry)
			retry = TGMMDict(dict[@"sending_state"])[@"can_retry"];
		model.canRetry = TGMMBool(retry, NO);
	}

	model.scheduledSendDate = (NSTimeInterval)TGMMDouble(dict[@"sendDate"]);
	if (model.scheduledSendDate < 0)
		model.scheduledSendDate = 0;
	model.sendWhenOnline = TGMMBool(dict[@"whenOnline"], NO);

	if (kind == TGMessageContentKindUnknown){
		if (model.isService)
			kind = TGMessageContentKindService;
		else if (model.hasLocation)
			kind = TGMessageContentKindLocation;
		else if (model.photoFileId != 0 || model.documentFileId != 0)
			kind = TGMessageContentKindDocument;
		else if (model.text.length)
			kind = TGMessageContentKindText;
	}
	model.kind = kind;

	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	NSArray *source = TGMMArray(dicts);
	if (!source.count)
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:source.count];
	for (id entry in source){
		TGMessageModel *model = [self fromDictionary:entry];
		if (model)
			[out addObject:model];
	}
	return [out copy];
}

- (BOOL)hasPhoto {
	return self.photoFileId != 0;
}

- (BOOL)hasDocument {
	return self.documentFileId != 0;
}

- (BOOL)isPoll {
	return self.kind == TGMessageContentKindPoll;
}

- (BOOL)isReply {
	return self.replyToMessageId != 0;
}

- (BOOL)isForwarded {
	return self.forwardFrom != nil;
}

- (BOOL)hasReactions {
	return self.reactionsSummary != nil;
}

- (BOOL)isScheduled {
	return self.scheduledSendDate > 0 || self.sendWhenOnline;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"<TGMessageModel %lld %@ %@>",
			self.messageId, self.kindTypeName,
			self.isOutgoing ? @"out" : @"in"];
}

@end

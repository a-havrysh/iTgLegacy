#import "TGStoryModel.h"

static NSDictionary *TGStoryModelDict(id value)
{
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSArray *TGStoryModelArray(id value)
{
	return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static NSString *TGStoryModelString(id value)
{
	if (![value isKindOfClass:[NSString class]])
		return nil;
	return [value length] ? [value copy] : nil;
}

static NSNumber *TGStoryModelNumber(id value)
{
	if ([value isKindOfClass:[NSNumber class]])
		return value;
	if ([value isKindOfClass:[NSString class]])
		return [NSNumber numberWithLongLong:[value longLongValue]];
	return nil;
}

static int64_t TGStoryModelId(id value)
{
	return [TGStoryModelNumber(value) longLongValue];
}

static NSInteger TGStoryModelInt(id value)
{
	int64_t v = TGStoryModelId(value);
	if (v > 2147483647LL)
		v = 2147483647LL;
	if (v < -2147483648LL)
		v = -2147483648LL;
	return (NSInteger)v;
}

static double TGStoryModelDouble(id value)
{
	return [TGStoryModelNumber(value) doubleValue];
}

static BOOL TGStoryModelBool(id value)
{
	if ([value isKindOfClass:[NSNumber class]])
		return [value boolValue];
	if ([value isKindOfClass:[NSString class]])
		return [value boolValue];
	return NO;
}

static TGStoryKind TGStoryModelKindFromName(NSString *name)
{
	if ([name isEqualToString:@"photo"])
		return TGStoryKindPhoto;
	if ([name isEqualToString:@"video"])
		return TGStoryKindVideo;
	if ([name isEqualToString:@"live"])
		return TGStoryKindLive;
	return TGStoryKindUnsupported;
}

static TGStoryPrivacy TGStoryModelPrivacyFromName(NSString *name)
{
	if ([name isEqualToString:@"everyone"])
		return TGStoryPrivacyEveryone;
	if ([name isEqualToString:@"contacts"])
		return TGStoryPrivacyContacts;
	if ([name isEqualToString:@"closeFriends"])
		return TGStoryPrivacyCloseFriends;
	if ([name isEqualToString:@"selected"])
		return TGStoryPrivacySelected;
	return TGStoryPrivacyUnknown;
}

static TGStoryAreaKind TGStoryModelAreaKindFromName(NSString *name)
{
	if ([name isEqualToString:@"location"])
		return TGStoryAreaKindLocation;
	if ([name isEqualToString:@"venue"])
		return TGStoryAreaKindVenue;
	if ([name isEqualToString:@"reaction"])
		return TGStoryAreaKindReaction;
	if ([name isEqualToString:@"message"])
		return TGStoryAreaKindMessage;
	if ([name isEqualToString:@"link"])
		return TGStoryAreaKindLink;
	if ([name isEqualToString:@"weather"])
		return TGStoryAreaKindWeather;
	if ([name isEqualToString:@"gift"])
		return TGStoryAreaKindGift;
	return TGStoryAreaKindUnsupported;
}

@interface TGStoryAreaModel ()
@property (nonatomic, assign) TGStoryAreaKind kind;
@property (nonatomic, copy) NSString *kindName;
@property (nonatomic, assign) double x;
@property (nonatomic, assign) double y;
@property (nonatomic, assign) double width;
@property (nonatomic, assign) double height;
@property (nonatomic, assign) double rotation;
@property (nonatomic, assign) double cornerRadius;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *emoji;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) double latitude;
@property (nonatomic, assign) double longitude;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;
@end

@implementation TGStoryAreaModel

+ (instancetype)fromDictionary:(NSDictionary *)dict
{
	NSDictionary *d = TGStoryModelDict(dict);
	if (!d)
		return nil;

	TGStoryAreaModel *area = [[TGStoryAreaModel alloc] init];
	NSString *kindName = TGStoryModelString(d[@"kind"]);
	area.kindName = kindName ?: @"unsupported";
	area.kind = TGStoryModelAreaKindFromName(kindName);
	area.x = TGStoryModelDouble(d[@"x"]);
	area.y = TGStoryModelDouble(d[@"y"]);
	area.width = TGStoryModelDouble(d[@"width"]);
	area.height = TGStoryModelDouble(d[@"height"]);
	area.rotation = TGStoryModelDouble(d[@"rotation"]);
	area.cornerRadius = TGStoryModelDouble(d[@"cornerRadius"]);
	area.url = TGStoryModelString(d[@"url"]);
	area.emoji = TGStoryModelString(d[@"emoji"]);
	area.title = TGStoryModelString(d[@"title"]);
	area.latitude = TGStoryModelDouble(d[@"latitude"]);
	area.longitude = TGStoryModelDouble(d[@"longitude"]);
	area.chatId = TGStoryModelId(d[@"chatId"]);
	area.messageId = TGStoryModelId(d[@"messageId"]);
	return area;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts
{
	NSArray *list = TGStoryModelArray(dicts);
	if (!list.count)
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:list.count];
	for (id one in list){
		TGStoryAreaModel *area = [TGStoryAreaModel fromDictionary:TGStoryModelDict(one)];
		if (area)
			[out addObject:area];
	}
	return out;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<TGStoryAreaModel %@ %.1f,%.1f>",
			self.kindName, self.x, self.y];
}

@end

@interface TGStoryModel ()
@property (nonatomic, assign) int64_t storyId;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t senderId;
@property (nonatomic, assign) NSTimeInterval date;
@property (nonatomic, assign) NSTimeInterval expireDate;
@property (nonatomic, assign) TGStoryKind kind;
@property (nonatomic, copy) NSString *kindName;
@property (nonatomic, copy) NSString *caption;
@property (nonatomic, assign) int64_t photoId;
@property (nonatomic, assign) int64_t videoId;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, copy) NSString *repostFrom;
@property (nonatomic, assign) TGStoryPrivacy privacy;
@property (nonatomic, copy) NSString *privacyName;
@property (nonatomic, assign) NSInteger viewCount;
@property (nonatomic, assign) NSInteger forwardCount;
@property (nonatomic, assign) NSInteger reactionCount;
@property (nonatomic, copy) NSString *myReaction;
@property (nonatomic, assign) BOOL isEdited;
@property (nonatomic, assign) BOOL isBeingPosted;
@property (nonatomic, assign) BOOL isBeingEdited;
@property (nonatomic, assign) BOOL isOnProfile;
@property (nonatomic, assign) BOOL canDelete;
@property (nonatomic, assign) BOOL canEdit;
@property (nonatomic, assign) BOOL canForward;
@property (nonatomic, assign) BOOL canReply;
@property (nonatomic, assign) BOOL canSetPrivacy;
@property (nonatomic, assign) BOOL canToggleProfile;
@property (nonatomic, assign) BOOL canGetViewers;
@property (nonatomic, assign) BOOL hasExpiredViewers;
@property (nonatomic, copy) NSArray *albumIds;
@property (nonatomic, copy) NSArray *areas;
@end

@implementation TGStoryModel

+ (instancetype)fromDictionary:(NSDictionary *)dict
{
	NSDictionary *d = TGStoryModelDict(dict);
	if (!d)
		return nil;

	int64_t storyId = TGStoryModelId(d[@"id"]);
	if (storyId == 0)
		return nil;

	TGStoryModel *story = [[TGStoryModel alloc] init];
	story.storyId = storyId;
	story.chatId = TGStoryModelId(d[@"chatId"]);
	story.senderId = TGStoryModelId(d[@"senderId"]);
	story.date = (NSTimeInterval)TGStoryModelId(d[@"date"]);

	id expiry = d[@"expireDate"] ?: d[@"expire_date"];
	story.expireDate = (NSTimeInterval)TGStoryModelId(expiry);

	NSString *kindName = TGStoryModelString(d[@"kind"]);
	story.kindName = kindName ?: @"unsupported";
	story.kind = TGStoryModelKindFromName(kindName);
	story.caption = TGStoryModelString(d[@"caption"]);
	story.photoId = TGStoryModelId(d[@"photoId"]);
	story.videoId = TGStoryModelId(d[@"videoId"]);
	story.duration = TGStoryModelInt(d[@"duration"]);
	story.width = TGStoryModelInt(d[@"width"]);
	story.height = TGStoryModelInt(d[@"height"]);
	story.repostFrom = TGStoryModelString(d[@"repostFrom"]);

	NSString *privacyName = TGStoryModelString(d[@"privacy"]);
	story.privacyName = privacyName;
	story.privacy = TGStoryModelPrivacyFromName(privacyName);

	story.viewCount = TGStoryModelInt(d[@"views"]);
	story.forwardCount = TGStoryModelInt(d[@"forwards"]);
	story.reactionCount = TGStoryModelInt(d[@"reactions"]);
	story.myReaction = TGStoryModelString(d[@"myReaction"]);

	story.isEdited = TGStoryModelBool(d[@"isEdited"]);
	story.isBeingPosted = TGStoryModelBool(d[@"isBeingPosted"]);
	story.isBeingEdited = TGStoryModelBool(d[@"isBeingEdited"]);
	story.isOnProfile = TGStoryModelBool(d[@"onProfile"]);
	story.canDelete = TGStoryModelBool(d[@"canDelete"]);
	story.canEdit = TGStoryModelBool(d[@"canEdit"]);
	story.canForward = TGStoryModelBool(d[@"canForward"]);
	story.canReply = TGStoryModelBool(d[@"canReply"]);
	story.canSetPrivacy = TGStoryModelBool(d[@"canSetPrivacy"]);
	story.canToggleProfile = TGStoryModelBool(d[@"canToggleProfile"]);
	story.canGetViewers = TGStoryModelBool(d[@"canGetViewers"]);
	story.hasExpiredViewers = TGStoryModelBool(d[@"expiredViewers"]);

	NSArray *rawAlbums = TGStoryModelArray(d[@"albumIds"]);
	if (rawAlbums.count){
		NSMutableArray *albums = [NSMutableArray arrayWithCapacity:rawAlbums.count];
		for (id one in rawAlbums){
			NSNumber *n = TGStoryModelNumber(one);
			if (n)
				[albums addObject:n];
		}
		story.albumIds = albums;
	} else {
		story.albumIds = [NSArray array];
	}

	story.areas = [TGStoryAreaModel arrayFromDictionaries:d[@"areas"]];
	return story;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts
{
	NSArray *list = TGStoryModelArray(dicts);
	if (!list.count)
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:list.count];
	for (id one in list){
		@autoreleasepool {
			TGStoryModel *story = [TGStoryModel fromDictionary:TGStoryModelDict(one)];
			if (story)
				[out addObject:story];
		}
	}
	return out;
}

- (BOOL)isRepost
{
	return self.repostFrom != nil;
}

- (BOOL)hasMyReaction
{
	return self.myReaction != nil;
}

- (BOOL)isExpiredAt:(NSTimeInterval)now
{
	if (self.expireDate <= 0.0)
		return NO;
	return self.expireDate <= now;
}

- (NSTimeInterval)secondsUntilExpiryAt:(NSTimeInterval)now
{
	if (self.expireDate <= 0.0)
		return 0.0;
	NSTimeInterval left = self.expireDate - now;
	return left > 0.0 ? left : 0.0;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<TGStoryModel %lld in %lld %@ views:%d>",
			self.storyId, self.chatId, self.kindName, (int)self.viewCount];
}

@end

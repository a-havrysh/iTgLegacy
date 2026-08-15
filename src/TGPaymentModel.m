//
// TGPaymentModel - see TGPaymentModel.h.
//
#import "TGPaymentModel.h"

static NSDictionary *TGPMDict(id value)
{
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSString *TGPMString(id value)
{
	if (![value isKindOfClass:[NSString class]])
		return nil;
	return [value length] ? [[NSString alloc] initWithString:value] : nil;
}

static long long TGPMLongLong(id value)
{
	return [value isKindOfClass:[NSNumber class]] ? [value longLongValue] : 0;
}

static NSInteger TGPMInteger(id value)
{
	return (NSInteger)TGPMLongLong(value);
}

static BOOL TGPMBool(id value)
{
	return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

static NSNumber *TGPMNumber(id value)
{
	return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static NSArray *TGPMMap(Class modelClass, NSArray *dicts)
{
	if (![dicts isKindOfClass:[NSArray class]])
		return [NSArray array];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:[dicts count]];
	for (id entry in dicts){
		id model = [modelClass fromDictionary:TGPMDict(entry)];
		if (model)
			[out addObject:model];
	}
	return out;
}

#pragma mark - star balance

@interface TGStarBalanceModel ()
@property (nonatomic, readwrite) long long stars;
@property (nonatomic, readwrite) long long requiredStars;
@property (nonatomic, readwrite, copy) NSString *nextOffset;
@end

@implementation TGStarBalanceModel

+ (instancetype)fromDictionary:(NSDictionary *)dict
{
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;
	TGStarBalanceModel *model = [[TGStarBalanceModel alloc] init];
	model.stars = TGPMLongLong([dict objectForKey:@"balance"]);
	model.requiredStars = TGPMLongLong([dict objectForKey:@"requiredStars"]);
	model.nextOffset = TGPMString([dict objectForKey:@"nextOffset"]);
	return model;
}

+ (instancetype)balanceWithStars:(long long)stars
{
	TGStarBalanceModel *model = [[TGStarBalanceModel alloc] init];
	model.stars = stars;
	return model;
}

@end

#pragma mark - star transaction

@interface TGStarTransactionModel ()
@property (nonatomic, readwrite, copy) NSString *transactionId;
@property (nonatomic, readwrite) int64_t date;
@property (nonatomic, readwrite) long long stars;
@property (nonatomic, readwrite) BOOL isRefund;
@property (nonatomic, readwrite, copy) NSString *type;
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readwrite, copy) NSString *transactionDescription;
@property (nonatomic, readwrite) int64_t userId;
@property (nonatomic, readwrite) int64_t chatId;
@property (nonatomic, readwrite, strong) NSNumber *photoFileId;
@end

@implementation TGStarTransactionModel

+ (instancetype)fromDictionary:(NSDictionary *)dict
{
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;
	NSString *transactionId = TGPMString([dict objectForKey:@"id"]);
	if (!transactionId)
		return nil;

	TGStarTransactionModel *model = [[TGStarTransactionModel alloc] init];
	model.transactionId = transactionId;
	model.date = TGPMLongLong([dict objectForKey:@"date"]);
	model.stars = TGPMLongLong([dict objectForKey:@"stars"]);
	model.isRefund = TGPMBool([dict objectForKey:@"isRefund"])
			|| TGPMBool([dict objectForKey:@"refund"]);
	model.type = TGPMString([dict objectForKey:@"type"]);
	model.title = TGPMString([dict objectForKey:@"title"]);
	model.transactionDescription = TGPMString([dict objectForKey:@"description"]);
	model.userId = TGPMLongLong([dict objectForKey:@"userId"]);
	model.chatId = TGPMLongLong([dict objectForKey:@"chatId"]);
	model.photoFileId = TGPMNumber([dict objectForKey:@"photoFileId"]);
	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts
{
	return TGPMMap([TGStarTransactionModel class], dicts);
}

- (BOOL)isOutgoing
{
	return self.stars < 0;
}

@end

#pragma mark - star subscription

@interface TGStarSubscriptionModel ()
@property (nonatomic, readwrite, copy) NSString *subscriptionId;
@property (nonatomic, readwrite) int64_t chatId;
@property (nonatomic, readwrite) int64_t expirationDate;
@property (nonatomic, readwrite) BOOL isCanceled;
@property (nonatomic, readwrite) BOOL isExpiring;
@property (nonatomic, readwrite) BOOL canReuse;
@property (nonatomic, readwrite) int64_t period;
@property (nonatomic, readwrite) long long stars;
@property (nonatomic, readwrite, copy) NSString *kind;
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readwrite, copy) NSString *inviteLink;
@end

@implementation TGStarSubscriptionModel

+ (instancetype)fromDictionary:(NSDictionary *)dict
{
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;
	NSString *subscriptionId = TGPMString([dict objectForKey:@"id"]);
	if (!subscriptionId)
		return nil;

	TGStarSubscriptionModel *model = [[TGStarSubscriptionModel alloc] init];
	model.subscriptionId = subscriptionId;
	model.chatId = TGPMLongLong([dict objectForKey:@"chatId"]);
	model.expirationDate = TGPMLongLong([dict objectForKey:@"expirationDate"]);
	model.isCanceled = TGPMBool([dict objectForKey:@"isCanceled"]);
	model.isExpiring = TGPMBool([dict objectForKey:@"isExpiring"]);
	model.canReuse = TGPMBool([dict objectForKey:@"canReuse"]);
	model.period = TGPMLongLong([dict objectForKey:@"period"]);
	model.stars = TGPMLongLong([dict objectForKey:@"stars"]);
	model.kind = TGPMString([dict objectForKey:@"kind"]) ?: @"channel";
	model.title = TGPMString([dict objectForKey:@"title"]);
	model.inviteLink = TGPMString([dict objectForKey:@"inviteLink"]);
	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts
{
	return TGPMMap([TGStarSubscriptionModel class], dicts);
}

+ (NSArray *)arrayFromPage:(NSDictionary *)page
{
	NSDictionary *dict = TGPMDict(page);
	return [self arrayFromDictionaries:[dict objectForKey:@"subscriptions"]];
}

- (BOOL)isBot
{
	return [self.kind isEqualToString:@"bot"];
}

@end

#pragma mark - gift

@interface TGGiftModel ()
@property (nonatomic, readwrite, copy) NSString *giftId;
@property (nonatomic, readwrite) int64_t catalogueGiftId;
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readwrite) long long starCount;
@property (nonatomic, readwrite) long long upgradeStarCount;
@property (nonatomic, readwrite) long long sellStarCount;
@property (nonatomic, readwrite) long long transferStarCount;
@property (nonatomic, readwrite) long long resaleStarCount;
@property (nonatomic, readwrite) long long minResaleStarCount;
@property (nonatomic, readwrite) NSInteger resaleCount;
@property (nonatomic, readwrite) BOOL isPremium;
@property (nonatomic, readwrite) BOOL isForBirthday;
@property (nonatomic, readwrite) BOOL isUnique;
@property (nonatomic, readwrite) BOOL isSaved;
@property (nonatomic, readwrite) BOOL isPinned;
@property (nonatomic, readwrite) BOOL isPrivate;
@property (nonatomic, readwrite) BOOL canUpgrade;
@property (nonatomic, readwrite) BOOL canTransfer;
@property (nonatomic, readwrite) BOOL isChannelGift;
@property (nonatomic, readwrite) int64_t senderId;
@property (nonatomic, readwrite) BOOL senderIsChat;
@property (nonatomic, readwrite, copy) NSString *senderName;
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite) int64_t date;
@property (nonatomic, readwrite, copy) NSString *uniqueName;
@property (nonatomic, readwrite) NSInteger uniqueNumber;
@property (nonatomic, readwrite, copy) NSString *emoji;
@property (nonatomic, readwrite, strong) NSNumber *stickerFileId;
@end

@implementation TGGiftModel

+ (instancetype)fromDictionary:(NSDictionary *)dict
{
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;
	NSString *giftId = TGPMString([dict objectForKey:@"giftId"]);
	int64_t catalogueGiftId = TGPMLongLong([dict objectForKey:@"id"]);
	if (!giftId && catalogueGiftId == 0)
		return nil;

	TGGiftModel *model = [[TGGiftModel alloc] init];
	model.giftId = giftId;
	model.catalogueGiftId = catalogueGiftId;
	model.title = TGPMString([dict objectForKey:@"title"]);
	model.starCount = TGPMLongLong([dict objectForKey:@"starCount"]);
	model.upgradeStarCount = TGPMLongLong([dict objectForKey:@"upgradeStarCount"]);
	model.sellStarCount = TGPMLongLong([dict objectForKey:@"sellStarCount"]);
	model.transferStarCount = TGPMLongLong([dict objectForKey:@"transferStarCount"]);
	model.resaleStarCount = TGPMLongLong([dict objectForKey:@"resaleStarCount"]);
	model.minResaleStarCount = TGPMLongLong([dict objectForKey:@"minResaleStarCount"]);
	model.resaleCount = TGPMInteger([dict objectForKey:@"resaleCount"]);
	model.isPremium = TGPMBool([dict objectForKey:@"isPremium"]);
	model.isForBirthday = TGPMBool([dict objectForKey:@"isForBirthday"]);
	model.isUnique = TGPMBool([dict objectForKey:@"isUnique"]);
	model.isSaved = TGPMBool([dict objectForKey:@"isSaved"]);
	model.isPinned = TGPMBool([dict objectForKey:@"isPinned"]);
	model.isPrivate = TGPMBool([dict objectForKey:@"isPrivate"]);
	model.canUpgrade = TGPMBool([dict objectForKey:@"canUpgrade"]);
	model.canTransfer = TGPMBool([dict objectForKey:@"canTransfer"]);
	model.isChannelGift = TGPMBool([dict objectForKey:@"tgChannelGift"]);
	model.senderId = TGPMLongLong([dict objectForKey:@"senderId"]);
	model.senderIsChat = TGPMBool([dict objectForKey:@"senderIsChat"]);
	model.senderName = TGPMString([dict objectForKey:@"senderName"]);
	model.text = TGPMString([dict objectForKey:@"text"]);
	model.date = TGPMLongLong([dict objectForKey:@"date"]);
	model.uniqueName = TGPMString([dict objectForKey:@"name"]);
	model.uniqueNumber = TGPMInteger([dict objectForKey:@"number"]);
	model.emoji = TGPMString([dict objectForKey:@"emoji"]);
	model.stickerFileId = TGPMNumber([dict objectForKey:@"stickerFileId"]);
	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts
{
	return TGPMMap([TGGiftModel class], dicts);
}

- (BOOL)isReceived
{
	return self.giftId != nil;
}

@end

#pragma mark - star payment option

@interface TGStarPaymentOptionModel ()
@property (nonatomic, readwrite) long long stars;
@property (nonatomic, readwrite) long long amount;
@property (nonatomic, readwrite, copy) NSString *currency;
@property (nonatomic, readwrite, copy) NSString *storeProductId;
@property (nonatomic, readwrite) BOOL isAdditional;
@end

@implementation TGStarPaymentOptionModel

+ (instancetype)fromDictionary:(NSDictionary *)dict
{
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;
	long long stars = TGPMLongLong([dict objectForKey:@"stars"]);
	if (stars == 0)
		return nil;

	TGStarPaymentOptionModel *model = [[TGStarPaymentOptionModel alloc] init];
	model.stars = stars;
	model.amount = TGPMLongLong([dict objectForKey:@"amount"]);
	model.currency = TGPMString([dict objectForKey:@"currency"]);
	model.storeProductId = TGPMString([dict objectForKey:@"storeProductId"]);
	model.isAdditional = TGPMBool([dict objectForKey:@"isAdditional"]);
	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts
{
	return TGPMMap([TGStarPaymentOptionModel class], dicts);
}

@end

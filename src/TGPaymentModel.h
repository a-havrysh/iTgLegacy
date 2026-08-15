//
// TGPaymentModel - typed value objects for the Telegram Stars area.
//
// These wrap what TGClient+Payments vends, so a screen reads a property
// instead of subscripting a TDLib-shaped dictionary. Every guard lives in
// +fromDictionary:; after it, no caller needs isKindOfClass anywhere.
//
// All models are immutable, hold no reference to the dictionary they were
// built from, and know nothing about a screen. Ids are int64_t because
// NSInteger is 32 bits on armv7. Star amounts are whole stars.
//
// Optional fields are NSString/NSNumber and are nil when absent - never an
// empty string that a screen would mistake for real data.
//
#import <Foundation/Foundation.h>

#pragma mark - star balance

/// This account's star balance, plus the two numbers that ride along with the
/// subscriptions page. Build it from -starSubscriptionsOnlyExpiring:'s `page`
/// dictionary, or with +balanceWithStars: from
/// -starBalanceWithCompletion: / -cachedStarBalance.
@interface TGStarBalanceModel : NSObject

/// Whole stars owned. 0 is a legitimate value, not a failure marker.
@property (nonatomic, readonly) long long stars;

/// Stars still needed to keep every expiring subscription alive. 0 when
/// nothing is expiring, and always 0 for a balance built with +balanceWithStars:.
@property (nonatomic, readonly) long long requiredStars;

/// Paging cursor for the next subscriptions page. Optional: nil at the end of
/// the list, and always nil for a balance built with +balanceWithStars:.
@property (nonatomic, readonly, copy) NSString *nextOffset;

/// Reads "balance", "requiredStars" and "nextOffset". Returns nil for a
/// non-dictionary; any missing key simply defaults.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// A balance from the plain long long the client's balance calls answer.
+ (instancetype)balanceWithStars:(long long)stars;

@end

#pragma mark - star transaction

/// One row of the star transaction history.
@interface TGStarTransactionModel : NSObject

/// Server transaction id. Never nil - a model without one does not build.
@property (nonatomic, readonly, copy) NSString *transactionId;

/// Unix time of the transaction, 0 when the server omitted it.
@property (nonatomic, readonly) int64_t date;

/// Signed: negative when stars were spent, positive when earned.
@property (nonatomic, readonly) long long stars;

/// YES when this row reverses an earlier payment.
@property (nonatomic, readonly) BOOL isRefund;

/// TDLib's StarTransactionType without the "starTransactionType" prefix,
/// e.g. "GiftPurchase". Never nil, but may be empty-sourced and therefore nil
/// if TDLib sent no type at all - check before grouping on it.
@property (nonatomic, readonly, copy) NSString *type;

/// Short human label. The client already falls back to a prettified type
/// name, so this is effectively always present.
@property (nonatomic, readonly, copy) NSString *title;

/// Longer product description. Optional: nil for transactions that carry no
/// product info. Named to avoid clashing with NSObject's -description.
@property (nonatomic, readonly, copy) NSString *transactionDescription;

/// Counterparty user, 0 when the transaction has none (e.g. a top-up).
@property (nonatomic, readonly) int64_t userId;

/// Counterparty chat, 0 when the transaction has none.
@property (nonatomic, readonly) int64_t chatId;

/// File id of the product photo or gift sticker. Optional: nil when the
/// transaction has no image.
@property (nonatomic, readonly, strong) NSNumber *photoFileId;

/// Convenience for a screen that only wants to know the direction.
@property (nonatomic, readonly) BOOL isOutgoing;

/// Needs a non-empty "id"; returns nil otherwise. Tolerates both "isRefund"
/// and the legacy "refund" spelling.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array of transaction dictionaries, dropping entries that fail to
/// build. Never returns nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

#pragma mark - star subscription

/// A recurring star subscription to a channel or a bot.
@interface TGStarSubscriptionModel : NSObject

/// Server subscription id, the handle every edit call takes. Never nil.
@property (nonatomic, readonly, copy) NSString *subscriptionId;

/// Chat the subscription belongs to, 0 when the server omitted it.
@property (nonatomic, readonly) int64_t chatId;

/// Unix time of the next charge, or of the end when canceled. 0 if unknown.
@property (nonatomic, readonly) int64_t expirationDate;

@property (nonatomic, readonly) BOOL isCanceled;

/// About to renew without enough balance.
@property (nonatomic, readonly) BOOL isExpiring;

/// The channel is still paid for but was left, so it can be rejoined.
@property (nonatomic, readonly) BOOL canReuse;

/// Billing period in seconds, 0 if unknown.
@property (nonatomic, readonly) int64_t period;

/// Stars charged per period.
@property (nonatomic, readonly) long long stars;

/// @"channel" or @"bot", as the client reports it. Never nil.
@property (nonatomic, readonly, copy) NSString *kind;

/// YES when kind is @"bot".
@property (nonatomic, readonly) BOOL isBot;

/// Subscription title. Optional: nil for a channel subscription, where the
/// chat's own title is what the row should show.
@property (nonatomic, readonly, copy) NSString *title;

/// Invite link of the subscribed channel. Optional: nil when there is none.
@property (nonatomic, readonly, copy) NSString *inviteLink;

/// Needs a non-empty "id"; returns nil otherwise.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array, dropping entries that fail to build. Never returns nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

/// The "subscriptions" array of a -starSubscriptionsOnlyExpiring: page.
+ (NSArray *)arrayFromPage:(NSDictionary *)page;

@end

#pragma mark - gift

/// A gift, in either of the two shapes the client vends:
///
///  - a catalogue gift from -availableGiftsWithCompletion:, identified by
///    `catalogueGiftId` (what sendGift takes), with `giftId` nil;
///  - a received gift from -receivedGiftsFor... / -giftsForResaleWithGiftId:,
///    identified by `giftId` (the received_gift_id every gift action takes),
///    with `catalogueGiftId` 0.
///
/// `isReceived` says which one you have. Fields that only one shape carries
/// are documented as optional below.
@interface TGGiftModel : NSObject

/// Received-gift handle. Optional: nil for a catalogue gift.
@property (nonatomic, readonly, copy) NSString *giftId;

/// Catalogue gift id for sendGift. 0 for a received gift.
@property (nonatomic, readonly) int64_t catalogueGiftId;

/// YES when this came from a received-gift list rather than the catalogue.
@property (nonatomic, readonly) BOOL isReceived;

/// Display title. The client substitutes @"Gift" when the server sends none,
/// so this is effectively always present.
@property (nonatomic, readonly, copy) NSString *title;

/// Price of the gift in stars.
@property (nonatomic, readonly) long long starCount;

/// Price of upgrading it to a unique gift, 0 when it cannot be upgraded.
@property (nonatomic, readonly) long long upgradeStarCount;

/// Stars returned by converting a received gift back, 0 when too late.
/// Received gifts only.
@property (nonatomic, readonly) long long sellStarCount;

/// Price of transferring a unique gift, 0 when free. Received gifts only.
@property (nonatomic, readonly) long long transferStarCount;

/// Asking price of a resale listing. 0 when this gift is not a listing.
@property (nonatomic, readonly) long long resaleStarCount;

/// Cheapest resale listing for this catalogue gift, 0 when none.
@property (nonatomic, readonly) long long minResaleStarCount;

/// How many resale listings exist for this catalogue gift.
@property (nonatomic, readonly) NSInteger resaleCount;

/// Catalogue flags.
@property (nonatomic, readonly) BOOL isPremium;
@property (nonatomic, readonly) BOOL isForBirthday;

/// An upgraded (NFT) gift.
@property (nonatomic, readonly) BOOL isUnique;

/// Received-gift flags.
@property (nonatomic, readonly) BOOL isSaved;
@property (nonatomic, readonly) BOOL isPinned;
@property (nonatomic, readonly) BOOL isPrivate;
@property (nonatomic, readonly) BOOL canUpgrade;
@property (nonatomic, readonly) BOOL canTransfer;

/// Set by the gifts screen on a channel's shelf, so a row knows the gift
/// belongs to a chat rather than to the signed-in user. Read from the
/// "tgChannelGift" key; NO when absent.
@property (nonatomic, readonly) BOOL isChannelGift;

/// Who sent a received gift. 0 when anonymous or for a catalogue gift.
@property (nonatomic, readonly) int64_t senderId;

/// YES when `senderId` is a chat id rather than a user id.
@property (nonatomic, readonly) BOOL senderIsChat;

/// Resolved sender name. Optional: nil when anonymous or not yet known.
@property (nonatomic, readonly, copy) NSString *senderName;

/// The note sent with the gift. Optional: nil when there is none.
@property (nonatomic, readonly, copy) NSString *text;

/// Unix time the gift was received, 0 for a catalogue gift.
@property (nonatomic, readonly) int64_t date;

/// t.me/nft slug of a unique gift. Optional: nil unless `isUnique`.
@property (nonatomic, readonly, copy) NSString *uniqueName;

/// Edition number of a unique gift, 0 when not unique.
@property (nonatomic, readonly) NSInteger uniqueNumber;

/// Emoji of the gift's sticker. Optional: catalogue gifts only.
@property (nonatomic, readonly, copy) NSString *emoji;

/// File id of the gift sticker (the model sticker for a unique gift).
/// Optional: nil when the server sent none.
@property (nonatomic, readonly, strong) NSNumber *stickerFileId;

/// Needs either a non-empty "giftId" or a non-zero "id"; returns nil
/// otherwise, so a stray dictionary can never become a blank gift row.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array, dropping entries that fail to build. Never returns nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

#pragma mark - star payment option

/// One buyable star pack from -starPaymentOptionsWithCompletion:.
@interface TGStarPaymentOptionModel : NSObject

/// Stars this pack grants.
@property (nonatomic, readonly) long long stars;

/// Price in the currency's smallest unit.
@property (nonatomic, readonly) long long amount;

/// ISO currency code. Optional: nil when the server omitted it.
@property (nonatomic, readonly, copy) NSString *currency;

/// App Store product id. Optional: nil when the pack has none.
@property (nonatomic, readonly, copy) NSString *storeProductId;

/// A pack the UI hides behind a "show more" row.
@property (nonatomic, readonly) BOOL isAdditional;

/// Needs a non-zero "stars"; returns nil otherwise.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array, dropping entries that fail to build. Never returns nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

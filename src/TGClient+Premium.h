//
// TGClient+Premium - Telegram Premium: limits, the feature catalogue, the
// subscription state, gift codes, gifting Premium, giveaways, channel boosts,
// the star balance and star subscriptions.
//
// Everything returned here is plain Foundation. TDLib enum objects are
// flattened into short NSString tags (the "@type" with its family prefix
// stripped, e.g. "pinnedChatCount", "chatBoostSourceGiveaway" -> "giveaway")
// plus a human readable title, so the UI never has to know the schema.
//
// Not covered, deliberately: anything that ends in a payment. Buying Premium,
// buying stars, creating a giveaway and star withdrawal all require Telegram's
// own App Store product ids or a card form, neither of which is reachable from
// this bundle on iOS 6.
//
#import "TGClient.h"

@interface TGClient (Premium)

#pragma mark - account state

/// YES when the signed-in account has Premium, read from the cached "me" user.
/// Cheap and synchronous; safe to call while drawing a cell.
- (BOOL)isPremiumAccount;

/// YES when this user object (any raw TDLib user dictionary, e.g. from an
/// update or from -userWithId:) is a Premium user. Use it to decide whether to
/// draw the star badge next to a name.
+ (BOOL)isPremiumUser:(NSDictionary *)user;

/// The Premium subscription block for the settings header. `completion` runs
/// on the main queue with a dictionary, or nil on failure:
///   "active"      NSNumber BOOL, whether this account has Premium now
///   "text"        NSString, the server's plain-text description of the state
///   "expires"     NSNumber, unix date, 0 when unknown
///   "expiresText" NSString, "Until 3 Mar 2026", "Active" or "" when inactive
///   "options"     NSArray of dictionaries, one per purchasable plan:
///                 "currency" NSString, "amount" NSNumber (in the currency's
///                 smallest unit), "months" NSNumber, "discount" NSNumber
///                 (percent), "current" NSNumber BOOL, "upgrade" NSNumber BOOL,
///                 "storeProductId" NSString, "link" NSString (an https
///                 checkout url, empty when the option is not a link).
/// The options are informational only - this client cannot transact them.
- (void)premiumSubscriptionWithCompletion:(void (^)(NSDictionary *info))completion;

/// The premium related values from TDLib's option store, in one call.
/// `completion` receives a dictionary with NSNumber values:
///   "isPremium", "isPremiumAvailable" (BOOL),
///   "uploadSpeedup", "downloadSpeedup" (integer multipliers),
///   "maxUploadFileSize" (bytes, the cap that applies to this account),
///   "starCount" (owned stars).
/// Never nil; missing options come back as zero.
- (void)premiumOptionsWithCompletion:(void (^)(NSDictionary *options))completion;

#pragma mark - limits

/// One limit, by its short tag ("pinnedChatCount", "captionLength",
/// "bioLength", "chatFolderCount", "supergroupCount", "savedAnimationCount",
/// "favoriteStickerCount", "messageTextLength", ... - the PremiumLimitType
/// name with the "premiumLimitType" prefix removed, first letter lowercase).
/// `completion` receives "type", "title", "default" and "premium" (NSNumbers),
/// or nil on failure.
- (void)premiumLimit:(NSString *)limitType
          completion:(void (^)(NSDictionary *limit))completion;

/// The whole limits table for the Premium screen: the limits that mean
/// something on this client, each in the shape above, in display order.
/// `completion` receives an array, empty on failure.
- (void)premiumLimitsWithCompletion:(void (^)(NSArray *limits))completion;

/// The value of one limit that actually applies to this account right now -
/// the premium value when the account has Premium, otherwise the default.
/// Use it to set the max length on a bio or caption editor, or the pinned chat
/// cap. `completion` receives 0 when the limit could not be fetched, in which
/// case keep whatever fallback the editor already has.
- (void)effectivePremiumLimit:(NSString *)limitType
                   completion:(void (^)(NSInteger value))completion;

#pragma mark - feature catalogue

/// The Premium promo feature list. `completion` receives an array of
/// dictionaries in server order:
///   "type"      NSString short tag ("increasedLimits", "voiceRecognition", ...)
///   "title"     NSString, a short user-facing name
///   "subtitle"  NSString, one explanatory line, may be empty
///   "supported" NSNumber BOOL, NO for features this client cannot show at all
///               (custom emoji, animated profile photos, app icons ...), so the
///               row can be dimmed instead of promising something untrue.
/// Empty array on failure.
- (void)premiumFeaturesWithCompletion:(void (^)(NSArray *features))completion;

/// The Telegram Business feature list, same shape as -premiumFeaturesWithCompletion:.
- (void)businessFeaturesWithCompletion:(void (^)(NSArray *features))completion;

/// Tell the server a promo feature row was opened. Fire and forget; pass the
/// short tag from -premiumFeaturesWithCompletion:.
- (void)viewPremiumFeature:(NSString *)featureType;

/// Tell the server the subscribe button was tapped. Fire and forget.
- (void)clickPremiumSubscriptionButton;

/// The header sticker for a gift or promo screen. `monthCount` is 1, 3, 6, 12
/// or 0 for the generic one. `completion` receives a dictionary with "fileId"
/// and "thumbnailFileId" (NSNumbers, feed either to -downloadFile:completion:),
/// "emoji", "width" and "height", or nil on failure. The sticker is animated on
/// the server side; download the thumbnail and show it as a still.
- (void)premiumInfoStickerForMonths:(NSInteger)monthCount
                         completion:(void (^)(NSDictionary *sticker))completion;

#pragma mark - gift codes

/// Look up a t.me/giftcode code without consuming it. `completion` receives:
///   "code"        NSString, echoed back
///   "creatorId"   NSNumber, the user or chat id that created it, 0 if unknown
///   "creatorIsChat" NSNumber BOOL
///   "creationDate" NSNumber unix date
///   "fromGiveaway" NSNumber BOOL
///   "giveawayMessageId" NSNumber
///   "months"      NSNumber, the length of the subscription it grants
///   "days"        NSNumber
///   "userId"      NSNumber, who redeemed it, 0 when still unused
///   "useDate"     NSNumber unix date, 0 when still unused
///   "used"        NSNumber BOOL
/// nil when the code is invalid or the lookup failed.
- (void)checkGiftCode:(NSString *)code
           completion:(void (^)(NSDictionary *info))completion;

/// Redeem a gift code on this account. `completion` receives YES on success,
/// or NO with a short server error message suitable for an alert.
- (void)applyGiftCode:(NSString *)code
           completion:(void (^)(BOOL ok, NSString *error))completion;

/// Check then apply in one step, for the "Redeem code" field and the deep-link
/// action sheet. `completion` receives YES plus the same info dictionary
/// -checkGiftCode:completion: returns, or NO plus a message to show. A code
/// that is already used fails here without a server round trip.
- (void)redeemGiftCode:(NSString *)code
            completion:(void (^)(BOOL ok, NSDictionary *info, NSString *error))completion;

#pragma mark - gifting premium

/// The durations Premium can be gifted for live in TGClient+Payments as
/// -premiumGiftOptionsWithCompletion:; use that one, its rows carry the same
/// month/star pairs this method needs.

/// Gift Premium to a user, paid from this account's star balance. `stars` and
/// `months` must be a pair taken from -premiumGiftOptionsWithCompletion:.
/// `message` is an optional plain-text note shown with the gift, may be nil.
/// `completion` receives YES, or NO with a server message - most commonly a
/// "not enough stars" error.
- (void)giftPremiumToUser:(int64_t)userId
                   months:(NSInteger)months
                    stars:(long long)stars
                  message:(NSString *)message
               completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - giveaways

/// The "How it works" sheet behind a giveaway message. `completion` receives:
///   "ongoing"       NSNumber BOOL, NO when the giveaway is finished
///   "creationDate"  NSNumber unix date
///   "ended"         NSNumber BOOL (ongoing giveaways whose winners are being picked)
///   "status"        NSString short tag: "eligible", "participating",
///                   "alreadyWasMember", "administrator", "disallowedCountry"
///                   or "" for a finished giveaway
///   "statusText"    NSString, one ready-to-show sentence for the sheet
///   "joinedDate"    NSNumber, for "alreadyWasMember"
///   "adminChatId"   NSNumber, for "administrator"
///   "countryCode"   NSString, for "disallowedCountry"
/// and for finished giveaways additionally
///   "winnersDate", "winnerCount", "activationCount" (NSNumbers),
///   "winner", "refunded" (NSNumber BOOL), "giftCode" (NSString, non-empty
///   only when this account won), "wonStars" (NSNumber).
/// nil on failure.
- (void)giveawayInfoForMessage:(int64_t)messageId
                        inChat:(int64_t)chatId
                    completion:(void (^)(NSDictionary *info))completion;

/// Start a giveaway a channel has already paid for, listed in the "prepaid"
/// entries of -chatBoostStatusForChat:completion:. `winnersDate` is a unix
/// date, `countryCodes` an array of two-letter NSString codes (may be nil for
/// no restriction), `prizeDescription` may be nil. `stars` is 0 for a Premium
/// prize giveaway and the prepaid star amount for a star giveaway.
/// `completion` receives YES, or NO with a server message.
- (void)launchPrepaidGiveaway:(long long)giveawayId
                       inChat:(int64_t)chatId
                  winnerCount:(NSInteger)winnerCount
                 winnersDate:(NSTimeInterval)winnersDate
               onlyNewMembers:(BOOL)onlyNewMembers
             hasPublicWinners:(BOOL)hasPublicWinners
                 countryCodes:(NSArray *)countryCodes
             prizeDescription:(NSString *)prizeDescription
                        stars:(long long)stars
                   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Every gift code this account has received, newest first, scraped from the
/// service chat with Telegram (user 777000) where gift-code and giveaway-prize
/// notifications are delivered. `limit` is the number of service messages to
/// scan, 0 for the default of 100. `completion` receives an array of:
///   "code"        NSString, the gift code, "" for a star prize
///   "months"      NSNumber, subscription length
///   "days"        NSNumber
///   "stars"       NSNumber, non-zero for a star giveaway prize
///   "fromGiveaway" NSNumber BOOL
///   "unclaimed"   NSNumber BOOL, YES while the code has not been redeemed
///   "creatorId"   NSNumber, the user or chat that sent it
///   "creatorIsChat" NSNumber BOOL
///   "creatorName" NSString, "" when unknown
///   "chatId"      NSNumber, the chat the notification lives in
///   "messageId"   NSNumber, the notification message
///   "boostedChatId" NSNumber, the channel a star prize boosted, 0 otherwise
///   "giveawayMessageId" NSNumber, 0 when not from a giveaway
///   "date"        NSNumber unix date
///   "text"        NSString, the plain caption Telegram sent, may be ""
/// The array is empty when nothing was found. Feed "code" to
/// -checkGiftCode:completion: for the redeemed/unredeemed detail.
- (void)accountGiftCodesWithLimit:(NSInteger)limit
                       completion:(void (^)(NSArray *codes))completion;

/// The giveaways this account has taken part in, found by scanning the recent
/// history of every channel this account currently boosts (a boost is how a
/// giveaway is entered) for giveaway messages and asking the server for this
/// account's status in each. `limit` caps the number of giveaways returned,
/// 0 for the default of 20. Costs one request per boosted chat plus one per
/// giveaway found, so call it once per screen and cache the result.
/// `completion` receives an array, newest first, of:
///   "chatId"      NSNumber, the channel that runs the giveaway
///   "chatTitle"   NSString, "" when unknown
///   "messageId"   NSNumber, the giveaway message
///   "date"        NSNumber unix date of the giveaway message
///   "winnerCount" NSNumber
///   "months"      NSNumber, Premium months at stake, 0 for a star giveaway
///   "stars"       NSNumber, star prize, 0 for a Premium giveaway
///   "winnersDate" NSNumber unix date the winners are picked
///   plus every key of -giveawayInfoForMessage:inChat:completion: merged in
///   ("ongoing", "status", "statusText", "winner", "giftCode", ...).
- (void)enteredGiveawaysWithLimit:(NSInteger)limit
                       completion:(void (^)(NSArray *giveaways))completion;

#pragma mark - channel boosts

/// The boost block for a channel profile. `completion` receives:
///   "level", "boostCount", "giftCodeBoostCount",
///   "currentLevelBoostCount", "nextLevelBoostCount",
///   "premiumMemberCount" (NSNumbers),
///   "premiumMemberPercentage" (NSNumber double),
///   "progress" (NSNumber double 0..1 through the current level - already
///   clamped, so a progress bar can use it directly),
///   "boostUrl" (NSString), "appliedSlotIds" (NSArray of NSNumber, the slots
///   this account has already spent on the chat),
///   "boosted" (NSNumber BOOL, whether this account boosts the chat),
///   "prepaidGiveaways" (NSArray of dictionaries: "id" NSNumber, "winnerCount",
///   "boostCount", "paymentDate", "prizeMonths", "prizeStars").
/// nil on failure.
- (void)chatBoostStatusForChat:(int64_t)chatId
                    completion:(void (^)(NSDictionary *status))completion;

/// The shareable boost link for a chat. `completion` receives the url and
/// whether the chat is public; url is nil on failure.
- (void)chatBoostLinkForChat:(int64_t)chatId
                  completion:(void (^)(NSString *url, BOOL isPublic))completion;

/// Resolve a t.me boost url back to a chat. `completion` receives the chat id
/// (0 on failure) and whether the chat is public.
- (void)chatBoostLinkInfo:(NSString *)url
               completion:(void (^)(int64_t chatId, BOOL isPublic))completion;

/// This account's boost slots. `completion` receives an array of dictionaries:
///   "slotId" NSNumber, "chatId" NSNumber (0 when the slot is free),
///   "startDate", "expirationDate", "cooldownUntil" (NSNumbers),
///   "free" NSNumber BOOL (slot is unused),
///   "reassignable" NSNumber BOOL (in use, but past its cooldown so it can be
///   moved to another chat).
/// Empty array for a non-Premium account or on failure.
- (void)availableBoostSlotsWithCompletion:(void (^)(NSArray *slots))completion;

/// Spend specific slots on a chat. `slotIds` is an array of NSNumber taken
/// from -availableBoostSlotsWithCompletion:. `completion` receives YES plus
/// the refreshed slot list, or NO with a server message.
- (void)boostChat:(int64_t)chatId
        withSlots:(NSArray *)slotIds
       completion:(void (^)(BOOL ok, NSArray *slots, NSString *error))completion;

/// The one-tap "Boost this channel" path: fetch the slots, spend every free
/// one on the chat and report the result. `completion` receives YES with the
/// refreshed slots when at least one slot was applied. When nothing was free
/// it receives NO, the full slot list (so the caller can put up a
/// reassignment sheet) and a short explanatory message.
- (void)boostChat:(int64_t)chatId
       completion:(void (^)(BOOL ok, NSArray *slots, NSString *error))completion;

/// Who boosted a chat, paginated. Pass an empty or nil `offset` for the first
/// page and the returned "nextOffset" for the following ones. `completion`
/// receives a dictionary with "totalCount" (NSNumber), "nextOffset" (NSString,
/// empty at the end) and "boosts", an array of:
///   "id" NSString, "count" NSNumber (how many boosts this entry is worth),
///   "startDate", "expirationDate" (NSNumbers), "userId" (NSNumber, 0 for an
///   unclaimed giveaway prize), "name" (NSString, the cached display name or
///   ""), "source" NSString ("premium", "giftCode" or "giveaway"),
///   "giftCode" NSString, "giveawayMessageId" NSNumber,
///   "unclaimed" NSNumber BOOL.
/// nil on failure.
- (void)boostersInChat:(int64_t)chatId
        onlyGiftCodes:(BOOL)onlyGiftCodes
                offset:(NSString *)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSDictionary *page))completion;

/// The "what boosts unlock" table. `completion` receives an array of
/// dictionaries, one per level, sorted by level: "level" (NSNumber) and
/// "features", an array of NSString lines already written for display
/// ("8 custom reactions", "Custom chat background", ...). Empty on failure.
- (void)boostFeaturesForChannel:(BOOL)isChannel
                     completion:(void (^)(NSArray *levels))completion;

#pragma mark - stars

/// The star balance lives in TGClient+Payments as
/// -starBalanceWithCompletion:; there is no second copy here.

/// The star transaction history for this account, paginated. `completion`
/// receives a dictionary with "balance" (NSNumber), "nextOffset" (NSString,
/// empty at the end) and "transactions", an array of:
///   "id" NSString, "stars" NSNumber (signed - negative when spent),
///   "refund" NSNumber BOOL, "date" NSNumber unix date,
///   "type" NSString short tag, "title" NSString (a readable label derived
///   from the type, safe to show as the row title).
/// nil on failure.
- (void)starTransactionsWithOffset:(NSString *)offset
                             limit:(NSInteger)limit
                        completion:(void (^)(NSDictionary *page))completion;

/// Star subscriptions - listing them, cancelling one and rejoining a chat -
/// live in TGClient+Payments (-starSubscriptionsOnlyExpiring:offset:completion:,
/// -setStarSubscription:canceled:completion:, -reuseStarSubscription:completion:).
/// They are not duplicated here.

#pragma mark - voice recognition

/// Ask the server to transcribe a voice or video note. The transcript is not
/// returned here: it arrives as an updated message, so the bubble must re-read
/// it with +speechRecognitionFromMessage:. `completion` receives YES when the
/// request was accepted, or NO with a server message (a non-Premium account
/// gets a limit error once its free quota is used).
- (void)recognizeSpeechInMessage:(int64_t)messageId
                          inChat:(int64_t)chatId
                      completion:(void (^)(BOOL ok, NSString *error))completion;

/// Read the transcription state off a raw TDLib message dictionary holding a
/// voice or video note. Returns a dictionary with "state" ("none", "pending",
/// "text" or "error") and "text" (the transcript, the partial text while
/// pending, or the error message). Never nil.
+ (NSDictionary *)speechRecognitionFromMessage:(NSDictionary *)message;

@end

// vim:ft=objc

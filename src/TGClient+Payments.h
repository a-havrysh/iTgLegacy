//
// TGClient+Payments - Telegram Stars, invoices, payment forms and gifts.
//
// Everything here answers with plain Foundation objects on the main queue.
// Star amounts are whole stars as long long; TDLib's nanostar remainder is
// dropped because nothing in this client can spend a fraction of a star.
//
// Money that is not stars (bot invoices priced in a real currency) is
// reported in the currency's smallest unit, exactly as TDLib sends it, plus
// the currency code, so the caller formats it once and we never guess an
// exponent.
//
#import "TGClient.h"

@interface TGClient (Payments)

#pragma mark - star balance

/// This account's star balance. TDLib has no dedicated balance call: the
/// balance rides along on the first page of the transaction history, so this
/// asks for a single transaction and reports the balance it comes with.
/// `stars` is 0 on failure. The answer is also kept in a file-static cache
/// (categories cannot add ivars) readable synchronously with
/// -cachedStarBalance, so a screen can paint a number before the round trip
/// finishes. Re-call this after anything that spends or earns stars.
- (void)starBalanceWithCompletion:(void (^)(long long stars))completion;

/// The last balance -starBalanceWithCompletion: saw, or 0 if it has never
/// answered in this process. Synchronous, never hits the network.
- (long long)cachedStarBalance;

/// The star packs this account may buy, cheapest first. Each option:
/// "stars" (NSNumber), "currency" (NSString, ISO code), "amount" (NSNumber,
/// the price in the currency's smallest unit), "storeProductId" (NSString,
/// may be empty) and "isAdditional" (NSNumber BOOL - a pack the UI hides
/// behind a "show more" row). Buying itself needs the App Store, which this
/// client has no route to, so the list is informational.
- (void)starPaymentOptionsWithCompletion:(void (^)(NSArray *options))completion;

/// The same list, but for buying stars as a gift for `userId`. Same shape.
- (void)starGiftPaymentOptionsForUser:(int64_t)userId
                           completion:(void (^)(NSArray *options))completion;

#pragma mark - star subscriptions

/// The recurring star subscriptions of this account. Pass YES for
/// `onlyExpiring` to get just the ones about to renew without enough balance.
/// `offset` is @"" for the first page, otherwise the previous page's
/// "nextOffset".
///
/// `page` is nil on failure, otherwise: "balance" (NSNumber, the star
/// balance the server reported alongside), "requiredStars" (NSNumber, stars
/// still needed to keep every expiring subscription alive), "nextOffset"
/// (NSString, empty at the end) and "subscriptions", an array of:
///   "id" NSString, "chatId" NSNumber, "expirationDate" NSNumber unix date,
///   "isCanceled" / "isExpiring" / "canReuse" NSNumber BOOL,
///   "period" NSNumber seconds, "stars" NSNumber per period,
///   "kind" NSString (@"channel" or @"bot"), "title" NSString (empty for a
///   channel - use the chat title), "inviteLink" NSString (may be empty).
- (void)starSubscriptionsOnlyExpiring:(BOOL)onlyExpiring
                               offset:(NSString *)offset
                           completion:(void (^)(NSDictionary *page))completion;

/// Cancel (or un-cancel) a star subscription by its "id".
- (void)setStarSubscription:(NSString *)subscriptionId
                   canceled:(BOOL)canceled
                 completion:(void (^)(BOOL ok))completion;

/// Rejoin the channel of a subscription that is still paid for but was left.
/// Only valid when the subscription reported "canReuse".
- (void)reuseStarSubscription:(NSString *)subscriptionId
                   completion:(void (^)(BOOL ok))completion;

#pragma mark - star transactions

/// Star transaction history, newest first. `direction` is @"incoming",
/// @"outgoing" or nil for both. `offset` is @"" for the first page, otherwise
/// the `nextOffset` of the previous page; `nextOffset` is empty at the end.
///
/// Each transaction: "id" (NSString), "date" (NSNumber unix time), "stars"
/// (NSNumber, signed - negative when spent), "isRefund" (NSNumber BOOL),
/// "type" (NSString, the TDLib StarTransactionType name without the
/// "starTransactionType" prefix), "title" (NSString, a short human label),
/// "description" (NSString, may be empty), "userId" / "chatId" (NSNumber, 0
/// when the transaction has no counterparty) and "photoFileId" (NSNumber file
/// id of the product photo or gift sticker, or absent).
- (void)starTransactionsWithDirection:(NSString *)direction
                               offset:(NSString *)offset
                                limit:(NSInteger)limit
                           completion:(void (^)(NSArray *transactions, NSString *nextOffset))completion;

/// Refund a star payment a bot of ours received. `chargeId` is the
/// "telegram_payment_charge_id" a receipt carries. `ok` is NO on failure.
- (void)refundStarPaymentWithChargeId:(NSString *)chargeId
                             toUserId:(int64_t)userId
                           completion:(void (^)(BOOL ok))completion;

#pragma mark - payment forms

/// Payment form for an invoice sent as a message (bot invoice bubble, or a
/// paid-media bubble). The form must be paid with one of the -pay... methods
/// below, and it expires, so do not cache it across screens.
///
/// The form: "formId" (NSNumber int64), "isStars" (NSNumber BOOL),
/// "starCount" (NSNumber, stars-priced forms only), "sellerBotUserId"
/// (NSNumber), "title", "description", "photoFileId" (NSNumber or absent),
/// "currency" (NSString, regular forms only), "totalAmount" (NSNumber, in the
/// currency's smallest unit), "priceParts" (NSArray of {"label", "amount"}),
/// "needsName" / "needsPhone" / "needsEmail" / "needsShippingAddress" /
/// "isFlexible" / "canSaveCredentials" / "needsPassword" (NSNumber BOOL),
/// "savedCredentials" (NSArray of {"id", "title"}), "savedOrderInfo"
/// (NSDictionary or absent), "maxTipAmount" (NSNumber), "suggestedTips"
/// (NSArray of NSNumber) and "invoice" - an opaque dictionary that must be
/// handed straight back to the pay methods.
- (void)paymentFormForMessage:(int64_t)messageId
                       inChat:(int64_t)chatId
                   completion:(void (^)(NSDictionary *form))completion;

/// The same, for an invoice reached by its t.me/invoice name (the deep link
/// slug), rather than by a message.
- (void)paymentFormForInvoiceName:(NSString *)name
                       completion:(void (^)(NSDictionary *form))completion;

/// Pay a stars-priced form. `form` is what -paymentFormFor... answered.
/// `ok` is YES when Telegram accepted the payment; the message updates itself
/// afterwards, so the caller only has to dismiss its sheet.
- (void)payStarsPaymentForm:(NSDictionary *)form
                 completion:(void (^)(BOOL ok))completion;

/// Unlock paid media in a message: fetches the form and pays it with stars in
/// one step. `ok` is NO when the balance is short or the call failed.
- (void)unlockPaidMediaInMessage:(int64_t)messageId
                          inChat:(int64_t)chatId
                      completion:(void (^)(BOOL ok))completion;

/// Validate the shipping/contact details of a regular (card) form before
/// paying. `orderInfo` takes "name", "phone", "email" and, when the form
/// needs an address, "countryCode", "state", "city", "street1", "street2" and
/// "postalCode". `save` asks Telegram to remember it for next time.
/// `orderInfoId` is what -payCardPaymentForm... wants; `shippingOptions` is
/// an array of {"id", "title", "amount"} and is empty for a non-flexible
/// invoice.
- (void)validateOrderInfo:(NSDictionary *)orderInfo
              forPaymentForm:(NSDictionary *)form
                        save:(BOOL)save
                  completion:(void (^)(NSString *orderInfoId, NSArray *shippingOptions))completion;

/// Pay a regular (card) form. Exactly one of `savedCredentialsId` and
/// `newCredentialsData` must be set: the id of a row from the form's
/// "savedCredentials", or a provider payment token JSON string obtained from
/// the card entry screen. `orderInfoId` and `shippingOptionId` may be nil
/// when the invoice does not need them. `tipAmount` is in the currency's
/// smallest unit, 0 for none. `verificationUrl` is non-nil when the bank
/// wants a 3-D Secure page opened before the payment completes.
- (void)payCardPaymentForm:(NSDictionary *)form
        savedCredentialsId:(NSString *)savedCredentialsId
        newCredentialsData:(NSString *)newCredentialsData
             allowSaveCard:(BOOL)allowSave
               orderInfoId:(NSString *)orderInfoId
          shippingOptionId:(NSString *)shippingOptionId
                 tipAmount:(long long)tipAmount
                completion:(void (^)(BOOL ok, NSString *verificationUrl))completion;

/// Receipt of a completed payment, reached from the "payment successful"
/// service message. Keys: "date" (NSNumber), "title", "description",
/// "photoFileId" (NSNumber or absent), "sellerBotUserId" (NSNumber),
/// "isStars" (NSNumber BOOL), "starCount" (NSNumber, stars receipts),
/// "transactionId" (NSString, stars receipts), "currency", "totalAmount",
/// "tipAmount", "priceParts", "credentialsTitle" and "shippingOption"
/// (regular receipts).
- (void)paymentReceiptForMessage:(int64_t)messageId
                          inChat:(int64_t)chatId
                      completion:(void (^)(NSDictionary *receipt))completion;

/// Forget the saved card and the saved shipping details. This is the
/// destructive "Clear saved payment info" row in Privacy settings.
- (void)clearSavedPaymentInfoWithCompletion:(void (^)(BOOL ok))completion;

#pragma mark - gift catalogue

/// Gifts that can be bought and sent right now. Each entry: "id" (NSNumber
/// int64 - the gift id sendGift wants), "title", "starCount" (NSNumber),
/// "upgradeStarCount" (NSNumber, 0 when it cannot be upgraded), "stickerFileId"
/// (NSNumber or absent), "emoji", "isPremium" and "isForBirthday" (NSNumber
/// BOOL), "resaleCount" (NSNumber) and "minResaleStarCount" (NSNumber).
- (void)availableGiftsWithCompletion:(void (^)(NSArray *gifts))completion;

/// Buy `giftId` from the catalogue and send it to a user. `text` is the
/// optional note shown with the gift, `isPrivate` hides the sender from other
/// profile visitors, `payForUpgrade` pre-pays the recipient's upgrade.
- (void)sendGiftWithId:(long long)giftId
                toUser:(int64_t)userId
                  text:(NSString *)text
             isPrivate:(BOOL)isPrivate
         payForUpgrade:(BOOL)payForUpgrade
            completion:(void (^)(BOOL ok))completion;

/// The same, for a channel that accepts gifts.
- (void)sendGiftWithId:(long long)giftId
                toChat:(int64_t)chatId
                  text:(NSString *)text
             isPrivate:(BOOL)isPrivate
         payForUpgrade:(BOOL)payForUpgrade
            completion:(void (^)(BOOL ok))completion;

#pragma mark - received gifts

/// Gifts on a user's profile, paged. `offset` is @"" for the first page.
/// `collectionId` is 0 for all of them. Each entry: "giftId" (NSString - the
/// received_gift_id every gift action below takes), "title", "starCount",
/// "sellStarCount", "transferStarCount", "upgradeStarCount", "senderId"
/// (NSNumber, 0 when anonymous), "senderName", "text", "date", "isSaved",
/// "isPinned", "isPrivate", "isUnique" (NSNumber BOOL - an upgraded gift),
/// "canUpgrade", "canTransfer" (NSNumber BOOL), "stickerFileId" (NSNumber or
/// absent) and, for unique gifts, "name" (NSString, the t.me/nft slug) and
/// "number" (NSNumber).
///
/// TGClient's own -giftsForUser:completion: is the short form of this and
/// stays as it is; use this one when the row needs more than a title.
- (void)receivedGiftsForUser:(int64_t)userId
                collectionId:(int32_t)collectionId
                      offset:(NSString *)offset
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *gifts, NSString *nextOffset, NSInteger total))completion;

/// The same for a channel's gift shelf.
- (void)receivedGiftsForChat:(int64_t)chatId
                collectionId:(int32_t)collectionId
                      offset:(NSString *)offset
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *gifts, NSString *nextOffset, NSInteger total))completion;

/// One received gift by its id, same shape as a list entry.
- (void)receivedGiftWithId:(NSString *)giftId
                completion:(void (^)(NSDictionary *gift))completion;

/// Show or hide a received gift on the profile.
- (void)setReceivedGift:(NSString *)giftId saved:(BOOL)saved;

/// Convert a received gift back into stars. `ok` is NO when it is too late.
- (void)sellReceivedGift:(NSString *)giftId completion:(void (^)(BOOL ok))completion;

/// Replace the pinned set on the signed-in user's own profile, in order.
- (void)setPinnedGiftIds:(NSArray *)giftIds;

/// Whether a channel's admins are told about new gifts.
- (void)setChat:(int64_t)chatId giftNotificationsEnabled:(BOOL)enabled;

/// Who may send the signed-in user gifts, and whether the profile shows a
/// Gift button. All flags are BOOL. Reads the current values first, so a
/// screen may set only what its switches changed by passing the dictionary
/// it got from -giftSettingsWithCompletion: with one key replaced.
/// Keys: "showGiftButton", "unlimited", "limited", "upgraded",
/// "fromChannels", "premiumSubscription".
- (void)giftSettingsWithCompletion:(void (^)(NSDictionary *settings))completion;
- (void)setGiftSettings:(NSDictionary *)settings;

#pragma mark - unique gifts

/// What a gift would look like upgraded: "models", "symbols" and "backdrops",
/// each an array of {"name", "rarity" (NSNumber per-mille), "stickerFileId"},
/// and "starCount" (NSNumber, the current upgrade price).
- (void)giftUpgradePreviewForGiftId:(long long)giftId
                         completion:(void (^)(NSDictionary *preview))completion;

/// Upgrade a received gift into a unique one. `starCount` is the price the
/// gift reported ("upgradeStarCount"), or 0 when the upgrade was pre-paid.
/// `gift` is the resulting unique gift, same shape as a received gift entry,
/// or nil on failure.
- (void)upgradeReceivedGift:(NSString *)giftId
        keepOriginalDetails:(BOOL)keepOriginalDetails
                  starCount:(long long)starCount
                 completion:(void (^)(NSDictionary *gift))completion;

/// Give a unique gift to somebody else. `starCount` is the gift's
/// "transferStarCount"; 0 when the transfer is free.
- (void)transferReceivedGift:(NSString *)giftId
                      toUser:(int64_t)userId
                   starCount:(long long)starCount
                  completion:(void (^)(BOOL ok))completion;

/// Erase the "originally sent by" line from a unique gift, for a price.
- (void)dropOriginalDetailsOfGift:(NSString *)giftId
                        starCount:(long long)starCount
                       completion:(void (^)(BOOL ok))completion;

#pragma mark - resale

/// Unique gifts of one gift kind offered for resale, cheapest first.
/// Each entry adds "resaleStarCount" (NSNumber) to the unique-gift shape.
- (void)giftsForResaleWithGiftId:(long long)giftId
                          offset:(NSString *)offset
                           limit:(NSInteger)limit
                      completion:(void (^)(NSArray *gifts, NSString *nextOffset, NSInteger total))completion;

/// Put a unique gift we own up for sale, or take it down with 0 stars.
- (void)setResalePrice:(long long)starCount
      forReceivedGift:(NSString *)giftId
            completion:(void (^)(BOOL ok))completion;

/// Buy a resold unique gift by its name (the t.me/nft slug) for the signed-in
/// user, at the price the listing showed.
- (void)buyResoldGiftNamed:(NSString *)name
              forStarCount:(long long)starCount
                completion:(void (^)(BOOL ok))completion;

#pragma mark - gift collections

/// The signed-in user's gift collections: "id" (NSNumber int32), "name",
/// "giftCount" (NSNumber) and "stickerFileId" (NSNumber or absent).
- (void)giftCollectionsWithCompletion:(void (^)(NSArray *collections))completion;

/// Create a collection holding the given received gift ids. `collection` is
/// the new collection, or nil on failure.
- (void)createGiftCollectionNamed:(NSString *)name
                          giftIds:(NSArray *)giftIds
                       completion:(void (^)(NSDictionary *collection))completion;

- (void)deleteGiftCollection:(int32_t)collectionId;
- (void)renameGiftCollection:(int32_t)collectionId
                          to:(NSString *)name
                  completion:(void (^)(NSDictionary *collection))completion;
- (void)addGiftIds:(NSArray *)giftIds toCollection:(int32_t)collectionId
        completion:(void (^)(NSDictionary *collection))completion;
- (void)removeGiftIds:(NSArray *)giftIds fromCollection:(int32_t)collectionId
           completion:(void (^)(NSDictionary *collection))completion;
/// Reorder the tab strip. `collectionIds` is every collection, in the wanted
/// order, as NSNumber int32.
- (void)reorderGiftCollections:(NSArray *)collectionIds;

#pragma mark - paid messages

/// Charge strangers this many stars per message they send us; 0 turns it off.
/// `chatId` is the signed-in user's own chat for the global setting, or a
/// channel's chat for a paid channel.
- (void)setChat:(int64_t)chatId paidMessageStarCount:(long long)starCount;

/// Stars a given user has already paid us for messages.
- (void)paidMessageRevenueFromUser:(int64_t)userId
                        completion:(void (^)(long long stars))completion;

/// Let a user write to us for free from now on. `refund` also returns the
/// stars they have already paid.
- (void)allowUnpaidMessagesFromUser:(int64_t)userId refundPayments:(BOOL)refund;

#pragma mark - paid (star) reactions

/// Add star reactions to a channel post. They are pending until committed,
/// which is what the undo banner's window is for: commit when it ends,
/// -cancelPaidReactionsOnMessage:inChat: when the user taps Undo.
- (void)addPaidReactionToMessage:(int64_t)messageId
                          inChat:(int64_t)chatId
                       starCount:(long long)starCount
                       anonymous:(BOOL)anonymous;
- (void)commitPaidReactionsOnMessage:(int64_t)messageId inChat:(int64_t)chatId;
- (void)cancelPaidReactionsOnMessage:(int64_t)messageId inChat:(int64_t)chatId;

/// Change how an already-sent paid reaction is attributed.
- (void)setPaidReactionAnonymous:(BOOL)anonymous
                       onMessage:(int64_t)messageId
                          inChat:(int64_t)chatId;

/// Senders a paid reaction in this chat may be attributed to: "id"
/// (NSNumber - negative for a chat), "name" and "isChat" (NSNumber BOOL).
- (void)paidReactionSendersInChat:(int64_t)chatId
                       completion:(void (^)(NSArray *senders))completion;

#pragma mark - premium gifts and codes

/// Look up a t.me/giftcode link before applying it. `info` carries
/// "creatorId" (NSNumber), "creationDate", "monthCount", "dayCount",
/// "isFromGiveaway" (NSNumber BOOL), "userId" (NSNumber, who used it, 0 when
/// unused) and "useDate" (NSNumber, 0 when unused). Nil when the code is not
/// valid, which is what the alert should say.
- (void)checkPremiumGiftCode:(NSString *)code
                  completion:(void (^)(NSDictionary *info))completion;

/// Redeem a gift code on the signed-in account.
- (void)applyPremiumGiftCode:(NSString *)code completion:(void (^)(BOOL ok))completion;

/// Gift Premium to a user, paid for with stars. `starCount` and `months` come
/// from one row of -premiumGiftOptionsWithCompletion: (TGClient+Premium.h).
- (void)giftPremiumWithStarsToUser:(int64_t)userId
                         starCount:(long long)starCount
                            months:(NSInteger)months
                              text:(NSString *)text
                        completion:(void (^)(BOOL ok))completion;

@end

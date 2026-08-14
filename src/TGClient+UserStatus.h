//
// TGClient+UserStatus - presence, last seen, status privacy, emoji status and
// peer accent colours.
//
// Everything here returns plain Foundation objects. Colours are returned as
// NSNumber packed 0xRRGGBB so this header stays free of UIKit; the UI layer
// makes its own UIColor from them.
//
#import "TGClient.h"

@interface TGClient (UserStatus)

#pragma mark - chat lifecycle

/// Tell TDLib the chat is on screen. Precise user statuses and online member
/// counts are only pushed for open chats, so call this from viewWillAppear:
/// and pair it with -closeChat:.
- (void)openChat:(int64_t)chatId;

/// Tell TDLib the chat left the screen. Call from viewWillDisappear:.
- (void)closeChat:(int64_t)chatId;

#pragma mark - last seen

/// Format a raw TDLib UserStatus object (the "status" field of a user, or the
/// "status" of an updateUserStatus) into what a subtitle shows.
/// Keys: "text" (NSString, e.g. "online", "last seen yesterday at 21:04"),
/// "isOnline" (NSNumber BOOL), "rank" (NSNumber, higher sorts first in a
/// contacts list), "wasOnline" (NSNumber unix time, 0 when unknown),
/// "isApproximate" (NSNumber BOOL - recently/week/month, no exact time), and
/// "hiddenByMyPrivacy" (NSNumber BOOL - the exact time is withheld because the
/// signed-in user hides their own last seen).
/// Never nil, so a malformed status still yields a drawable subtitle.
+ (NSDictionary *)statusInfoForUserStatus:(NSDictionary *)status;

/// The same dictionary for one user, fetched from TDLib's local cache when it
/// has one. `completion` also gets "userId". Never nil.
- (void)statusInfoForUser:(int64_t)userId
               completion:(void (^)(NSDictionary *info))completion;

/// Explanatory line for tapping an approximate status, or nil when the status
/// is exact and there is nothing to explain. Says that the precise time is
/// hidden because the signed-in user hides their own, when that is the reason.
+ (NSString *)hiddenStatusHintForStatusInfo:(NSDictionary *)info;

/// Publish or withdraw our own presence to peers. Call with YES from
/// applicationDidBecomeActive: and NO from applicationDidEnterBackground:;
/// without this our account looks permanently offline to everyone else.
- (void)setSelfOnline:(BOOL)online;

/// "N members, M online" for a group or supergroup, ready for the navigation
/// bar subtitle. `online` is 0 for anything that is not a group.
/// The count is sampled from the members TDLib has cached (up to 50 recent
/// ones in a supergroup), so it is exact for small groups and a lower bound
/// for large ones. Call -openChat: first for TDLib to keep statuses fresh.
- (void)groupOnlineSummaryForChat:(int64_t)chatId
                       completion:(void (^)(NSString *text, NSInteger members, NSInteger online))completion;

#pragma mark - status privacy

/// Full picture of one privacy setting, beyond the everybody/contacts/nobody
/// scalar -privacyRule:completion: returns. `setting` is the TDLib name
/// without the "userPrivacySetting" prefix: "ShowStatus", "ShowProfilePhoto",
/// "ShowPhoneNumber", "ShowBio", "AllowCalls", "AllowChatInvites",
/// "AllowFindingByPhoneNumber", "ShowLinkInForwardedMessages".
/// Keys: "value" ("everybody" / "contacts" / "nobody"), "allowedUserIds",
/// "restrictedUserIds", "allowedChatIds", "restrictedChatIds" (NSArray of
/// NSNumber, possibly empty). Nil on failure.
- (void)privacyRuleDetail:(NSString *)setting
               completion:(void (^)(NSDictionary *detail))completion;

/// Write a privacy setting with its Always/Never exception lists.
/// `value` is "everybody", "contacts" or "nobody"; the two id arrays are
/// NSNumber user ids and may be nil or empty. The exceptions are sent ahead of
/// the base rule, which is the order TDLib evaluates them in.
/// `completion` gets YES when the server accepted the rules.
- (void)setPrivacyRule:(NSString *)setting
                    to:(NSString *)value
            allowUsers:(NSArray *)allowedUserIds
         restrictUsers:(NSArray *)restrictedUserIds
            completion:(void (^)(BOOL ok))completion;

#pragma mark - emoji status

/// Emoji status badge shown after a user's name, or nil when they have none.
/// Keys: "customEmojiId" (NSNumber, the id to draw), "thumbFileId" (NSNumber
/// file id of a static thumbnail, or absent), "stickerFileId" (NSNumber),
/// "emoji" (NSString fallback character), "isAnimated" (NSNumber BOOL - drop
/// the animation on this hardware and use the thumbnail), "expires"
/// (NSNumber unix time, 0 when it does not expire), "isGift" (NSNumber BOOL)
/// and "giftTitle" (NSString, empty unless it is a collectible gift status).
- (void)emojiStatusForUser:(int64_t)userId
                completion:(void (^)(NSDictionary *status))completion;

/// The same badge for a channel or supergroup, or nil.
- (void)emojiStatusForChat:(int64_t)chatId
                completion:(void (^)(NSDictionary *status))completion;

/// Resolve custom emoji ids to drawable icons in one call, for a list screen
/// that needs several badges at once. `ids` are NSNumber custom emoji ids.
/// `completion` gets a dictionary keyed by the id as an NSString, each value
/// shaped like -emojiStatusForUser:. Missing ids are simply absent.
- (void)customEmojiIconsForIds:(NSArray *)ids
                    completion:(void (^)(NSDictionary *iconsById))completion;

#pragma mark - badges

/// The small marks drawn after a name. Keys, all NSNumber BOOL: "isPremium",
/// "isVerified", "isScam", "isFake", "isSupport", "isBot". Never nil.
- (void)badgesForUser:(int64_t)userId
           completion:(void (^)(NSDictionary *badges))completion;

/// The same for a chat; channels and supergroups carry their own verification
/// mark. Keys "isVerified", "isScam", "isFake" (NSNumber BOOL). Never nil.
- (void)badgesForChat:(int64_t)chatId
           completion:(void (^)(NSDictionary *badges))completion;

#pragma mark - accent colours

/// Colour a peer's name and reply bar are drawn in.
/// Keys: "colorId" (NSNumber), "rgb" (NSNumber 0xRRGGBB), "profileColorId"
/// (NSNumber, -1 when the peer has no profile colour), "profileColors"
/// (NSArray of two NSNumber 0xRRGGBB gradient stops, absent when there is no
/// profile colour), "backgroundCustomEmojiId" and
/// "profileBackgroundCustomEmojiId" (NSNumber, 0 when unset). Never nil.
- (void)accentColorsForUser:(int64_t)userId
                 completion:(void (^)(NSDictionary *colors))completion;

/// The same for any chat, including groups and channels.
- (void)accentColorsForChat:(int64_t)chatId
                 completion:(void (^)(NSDictionary *colors))completion;

/// Name colour for a built-in accent colour id, as 0xRRGGBB. Ids outside the
/// seven built-in colours are folded back into them, so this always answers.
/// Use it to colour a name synchronously once an id is known.
+ (NSNumber *)rgbForAccentColorId:(NSInteger)colorId;

/// Two gradient stops (0xRRGGBB NSNumbers, top then bottom) for a profile
/// accent colour id, or nil when `colorId` is negative, which means the peer
/// uses the plain profile header.
+ (NSArray *)profileGradientForColorId:(NSInteger)colorId;

@end

// vim:ft=objc

//
// TGClient+Channels - channel signatures, discussion groups, statistics and boosts.
//
// Everything here returns plain Foundation objects on the main queue. A nil
// argument in a completion means the call failed or the reply was malformed;
// callers never see raw TDLib wrapper objects.
//
#import "TGClient.h"

@interface TGClient (Channels)

#pragma mark - Signatures

/// Signature settings of a channel. `info` is nil on failure, otherwise:
/// "supergroup_id" (NSNumber), "is_channel", "sign_messages",
/// "show_message_sender", "has_linked_chat", "boost_level" - all NSNumber.
- (void)channelSignaturesForChat:(int64_t)chatId
                      completion:(void (^)(NSDictionary *info))completion;

/// Sets the "Sign Messages" / "Show Author Profiles" pair on a channel.
/// `showAuthorProfiles` is only meaningful when `sign` is YES.
/// `completion` receives YES when TDLib accepted the change.
- (void)setChannelSignaturesForChat:(int64_t)chatId
                       signMessages:(BOOL)sign
                 showAuthorProfiles:(BOOL)showAuthorProfiles
                         completion:(void (^)(BOOL ok))completion;

#pragma mark - Discussion group

/// Chat id of the discussion group linked to a channel, or nil when there is
/// none. Also works the other way round: for a discussion group it gives the
/// channel it is linked to.
- (void)discussionGroupForChannel:(int64_t)chatId
                       completion:(void (^)(NSNumber *linkedChatId))completion;

/// Groups the user may link to a channel as its discussion group.
/// `chats` is an array of {"id", "title"}; the first entry may be a group that
/// still has to be created by the caller. Nil on failure.
- (void)suitableDiscussionChatsWithCompletion:(void (^)(NSArray *chats))completion;

/// Links `discussionChatId` to the channel `chatId`. Pass 0 to unlink.
/// `completion` receives YES when TDLib accepted the change.
- (void)setDiscussionGroup:(int64_t)discussionChatId
                forChannel:(int64_t)chatId
                completion:(void (^)(BOOL ok))completion;

/// Whether new subscribers of a linked discussion group see the old history.
- (void)isAllHistoryAvailableForChat:(int64_t)chatId
                          completion:(void (^)(BOOL available))completion;

/// Toggles history visibility for new members of a discussion group.
- (void)setAllHistoryAvailable:(BOOL)available
                       forChat:(int64_t)chatId
                    completion:(void (^)(BOOL ok))completion;

#pragma mark - Statistics

/// YES when the "Statistics" row should be shown for this chat.
- (void)canGetStatisticsForChat:(int64_t)chatId
                     completion:(void (^)(BOOL canGet))completion;

/// Channel or supergroup statistics, flattened for a grouped table.
/// `stats` is nil on failure, otherwise:
///   "kind"    - "channel" or "supergroup"
///   "period"  - {"start_date", "end_date"} NSNumbers
///   "values"  - ordered array of {"key", "title", "value", "previous",
///               "growth"} where value/previous/growth are NSNumber doubles
///   "graphs"  - ordered array of {"key", "title", "json", "zoom_token"} for
///               ready graphs, or {"key", "title", "token"} for async ones
///               that must be fetched with -statisticalGraphForChat:...
///   "top_senders"        - supergroup only: {"user_id", "name",
///                          "sent_message_count", "average_character_count"}
///   "top_administrators" - supergroup only: {"user_id", "name",
///                          "deleted_message_count", "banned_user_count",
///                          "restricted_user_count"}
///   "top_inviters"       - supergroup only: {"user_id", "name",
///                          "added_member_count"}
///   "recent_interactions"- channel only: {"message_id", "story_id",
///                          "view_count", "forward_count", "reaction_count"}
- (void)statisticsForChat:(int64_t)chatId
                   isDark:(BOOL)isDark
               completion:(void (^)(NSDictionary *stats))completion;

/// Loads an async or zoomed graph. `token` is the "token" of an async graph or
/// the "zoom_token" of a loaded one; pass 0 for `x` when not zooming.
/// `graph` is nil on failure, otherwise {"json", "zoom_token"}.
- (void)statisticalGraphForChat:(int64_t)chatId
                          token:(NSString *)token
                        zoomAtX:(int64_t)x
                     completion:(void (^)(NSDictionary *graph))completion;

/// Per-post statistics. `graphs` has the same shape as the "graphs" entry of
/// -statisticsForChat:isDark:completion:, with keys "message_interaction" and
/// "message_reaction". Nil on failure.
- (void)statisticsForMessage:(int64_t)messageId
                      inChat:(int64_t)chatId
                      isDark:(BOOL)isDark
                  completion:(void (^)(NSArray *graphs))completion;

/// Public channels that reposted a message, for the per-post statistics screen.
/// Each entry is {"chat_id", "message_id", "title", "view_count"} for a
/// message repost, or {"story_id", "sender_chat_id", "title"} for a story.
/// Pass @"" as `offset` for the first page. `nextOffset` is empty at the end.
- (void)publicForwardsOfMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                         offset:(NSString *)offset
                          limit:(NSInteger)limit
                     completion:(void (^)(NSArray *forwards, NSString *nextOffset, NSInteger totalCount))completion;

#pragma mark - Boosts

/// Boost state of a channel or supergroup. `status` is nil on failure,
/// otherwise: "boost_url", "level", "boost_count", "gift_code_boost_count",
/// "current_level_boost_count", "next_level_boost_count",
/// "premium_member_count", "premium_member_percentage",
/// "applied_slot_ids" (array of NSNumber, non-empty when already boosted),
/// "is_boosted" (NSNumber BOOL).
- (void)boostStatusForChat:(int64_t)chatId
                completion:(void (^)(NSDictionary *status))completion;

/// Boost slots the signed-in Premium user owns. Each entry is
/// {"slot_id", "currently_boosted_chat_id", "start_date", "expiration_date",
/// "cooldown_until_date", "is_available"} - "is_available" is YES when the
/// slot is free or out of cooldown. Nil on failure.
/// Named apart from TGClient+Premium's -availableBoostSlotsWithCompletion:,
/// which returns a different dictionary shape for the same TDLib call.
- (void)channelBoostSlotsWithCompletion:(void (^)(NSArray *slots))completion;

/// Applies the given slots (array of NSNumber slot ids) to a chat.
/// `slots` in the completion is the updated slot list, same shape as
/// -channelBoostSlotsWithCompletion:, or nil when the boost was rejected.
- (void)boostChat:(int64_t)chatId
      withSlotIds:(NSArray *)slotIds
       completion:(void (^)(NSArray *slots))completion;

/// Shareable boost link for a chat. `link` is nil on failure; `isPublic` says
/// whether the link works for users who are not members.
- (void)boostLinkForChat:(int64_t)chatId
              completion:(void (^)(NSString *link, BOOL isPublic))completion;

/// Resolves a t.me boost URL into a chat to open the boost sheet for.
/// `chatId` is nil when the link cannot be resolved.
- (void)resolveBoostLink:(NSString *)url
              completion:(void (^)(NSNumber *chatId, BOOL isPublic))completion;

/// Paginated list of boosters, admin only. Each entry is
/// {"id", "count", "source", "user_id", "gift_code", "star_count",
/// "giveaway_message_id", "is_unclaimed", "start_date", "expiration_date",
/// "name"} where "source" is "premium", "gift_code" or "giveaway".
/// Pass @"" as `offset` for the first page.
- (void)boostsForChat:(int64_t)chatId
        onlyGiftCodes:(BOOL)onlyGiftCodes
               offset:(NSString *)offset
                limit:(NSInteger)limit
           completion:(void (^)(NSArray *boosts, NSString *nextOffset, NSInteger totalCount))completion;

/// Boosts one specific user applied to a chat, same entry shape as
/// -boostsForChat:onlyGiftCodes:offset:limit:completion:.
- (void)boostsByUser:(int64_t)userId
              inChat:(int64_t)chatId
          completion:(void (^)(NSArray *boosts))completion;

/// Feature checklist for a single boost level. `features` is nil on failure,
/// otherwise the flattened chatBoostLevelFeatures fields ("level",
/// "story_per_day_count", "custom_emoji_reaction_count", "title_color_count",
/// "profile_accent_color_count", "accent_color_count", "chat_theme_background_count",
/// "can_set_profile_background_custom_emoji", "can_set_background_custom_emoji",
/// "can_set_emoji_status", "can_set_custom_background",
/// "can_set_custom_emoji_sticker_set", "can_enable_automatic_translation",
/// "can_recognize_speech", "can_disable_sponsored_messages").
- (void)boostLevelFeaturesForChannel:(BOOL)isChannel
                               level:(NSInteger)level
                          completion:(void (^)(NSDictionary *features))completion;

/// Full per-level feature table for the boost explainer. `levels` is an array
/// of the same dictionaries as -boostLevelFeaturesForChannel:level:completion:,
/// `minimums` maps each "min_*_boost_level" key to an NSNumber. Both nil on failure.
/// Named apart from TGClient+Premium's -boostFeaturesForChannel:completion:,
/// which wraps the same TDLib call with a one-argument completion.
- (void)boostLevelFeatureTableForChannel:(BOOL)isChannel
                              completion:(void (^)(NSArray *levels, NSDictionary *minimums))completion;

@end

// vim:ft=objc

//
// TGClient+Reactions - message reactions: adding, removing, listing who
// reacted, the emoji a message allows, the quick reaction and unread
// reaction bookkeeping.
//
// Everything here returns plain Foundation objects. Emoji are passed and
// returned as NSString; custom emoji and paid (star) reactions cannot be
// sent from this client and are reported with a placeholder character so a
// chip can still be drawn for them.
//
#import "TGClient.h"

@interface TGClient (Reactions)

#pragma mark - sending

/// Add one emoji reaction to a message. `big` asks other clients to play the
/// large animation; we cannot play it ourselves but the flag is honoured
/// remotely. Fire and forget - the chip row updates through the message.
- (void)addReaction:(NSString *)emoji
          toMessage:(int64_t)messageId
             inChat:(int64_t)chatId
                big:(BOOL)big;

/// Remove one emoji reaction the signed-in user has previously added.
- (void)removeReaction:(NSString *)emoji
           fromMessage:(int64_t)messageId
                inChat:(int64_t)chatId;

/// Add the reaction if the user has not chosen it, remove it if they have.
/// This is the tap-a-chip and double-tap-to-react path. `completion` runs on
/// the main queue with YES when the reaction is now set, NO when it was
/// removed or the message could not be read.
- (void)toggleReaction:(NSString *)emoji
             onMessage:(int64_t)messageId
                inChat:(int64_t)chatId
                   big:(BOOL)big
            completion:(void (^)(BOOL nowChosen))completion;

/// Replace the user's whole reaction set on a message in one call. `emojis`
/// is an array of NSString; pass an empty array to clear all of them. Respect
/// the max count from -availableReactionsInChat:completion: before calling.
- (void)setReactions:(NSArray *)emojis
           onMessage:(int64_t)messageId
              inChat:(int64_t)chatId
                 big:(BOOL)big;

/// The signed-in user's quick reaction, used by the double-tap gesture.
/// TDLib only reports the current value through an update this client does
/// not yet route, so the value is cached here from the last set and defaults
/// to a thumbs up until the user changes it.
- (NSString *)quickReactionEmoji;

/// Set the global default (quick) reaction. Also updates -quickReactionEmoji.
- (void)setQuickReactionEmoji:(NSString *)emoji;

/// Forget the recently used reactions the emoji picker suggests.
- (void)clearRecentReactions;

#pragma mark - reading

/// Reaction chips for one message: an array of dictionaries with
/// "emoji" (NSString, a star for custom/paid reactions we cannot draw),
/// "count" (NSNumber), "chosen" (NSNumber BOOL, YES when the signed-in user
/// picked it) and "custom" (NSNumber BOOL). Empty array when there are none.
/// Pass the raw TDLib message dictionary, e.g. from an update.
+ (NSArray *)reactionChipsFromMessage:(NSDictionary *)message;

/// Same chips, fetched fresh for one message. `completion` runs on the main
/// queue with an array in the shape above, empty on failure.
- (void)reactionChipsForMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSArray *chips))completion;

/// Which reactions this message accepts, for the picker strip. `completion`
/// receives a dictionary with "top", "recent" and "popular" (arrays of emoji
/// NSString, custom-emoji entries dropped), "allEmoji" (the three lists
/// merged, duplicates removed, in picker order) and "reason" (NSString, empty
/// when reacting is allowed, otherwise a short user-facing sentence such as
/// "Only channel members can react here"). Nil on failure.
- (void)availableReactionsForMessage:(int64_t)messageId
                              inChat:(int64_t)chatId
                          completion:(void (^)(NSDictionary *info))completion;

/// One page of the "who reacted" list. `emoji` filters to a single reaction,
/// pass nil for all of them. `offset` is nil for the first page and then the
/// nextOffset handed back by the previous call. `completion` receives an
/// array of dictionaries with "senderId" (NSNumber, negative for a chat),
/// "name" (NSString, may be empty until the sender is known), "emoji" and
/// "date" (NSNumber, unix time), plus the offset to use for the following
/// page (empty NSString when the list is exhausted) and the total count.
- (void)addedReactionsForMessage:(int64_t)messageId
                          inChat:(int64_t)chatId
                           emoji:(NSString *)emoji
                          offset:(NSString *)offset
                           limit:(NSInteger)limit
                      completion:(void (^)(NSArray *reactors,
                                           NSString *nextOffset,
                                           NSInteger totalCount))completion;

/// Static metadata for one emoji reaction, for the picker grid. `completion`
/// receives "emoji", "title", "isActive" (NSNumber BOOL) and "iconFileId"
/// (NSNumber, the static_icon sticker file - download it with the usual file
/// path API; the animated variants are deliberately not exposed). Nil on
/// failure.
- (void)emojiReactionInfo:(NSString *)emoji
               completion:(void (^)(NSDictionary *info))completion;

/// Top paid (star) reactors on a channel post, read-only - we cannot send
/// paid reactions. Array of dictionaries with "senderId" (NSNumber, 0 when
/// anonymous), "name", "stars" (NSNumber), "isTop" and "isAnonymous"
/// (NSNumber BOOL). Empty when the post has none.
+ (NSArray *)paidReactorsFromMessage:(NSDictionary *)message;

/// How much of a message's reaction budget the signed-in user has spent, so
/// the picker can grey out the strip once the limit is reached. `completion`
/// runs on the main queue with the emoji the user has already chosen on this
/// message (array of NSString), how many that is, the chat's maximum per
/// message and whether one more may still be added. On failure: empty array,
/// 0 used, 1 max, canAddMore YES.
- (void)reactionUsageForMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSArray *chosenEmoji,
                                          NSInteger usedCount,
                                          NSInteger maxCount,
                                          BOOL canAddMore))completion;

/// Local file path of the official static artwork for one reaction emoji,
/// downloading it if needed. This is the `static_icon` sticker of
/// getEmojiReaction - a WEBP that UIImage on iOS 6 cannot decode directly, so
/// callers that cannot decode it should keep drawing the plain character.
/// `completion` runs on the main queue with the path, or nil when the
/// reaction has no icon or the download failed. Resolved paths are cached in
/// a file-static dictionary for the process lifetime (categories cannot add
/// ivars), so repeat calls for the same emoji are free.
- (void)reactionIconPathForEmoji:(NSString *)emoji
                      completion:(void (^)(NSString *path))completion;

#pragma mark - live chip updates

/// Watch one message's reaction chips and get a callback whenever they
/// change - somebody else reacting, or our own toggle landing on the server.
/// TDLib delivers this as updateMessageInteractionInfo, which this client
/// does not route yet, so the watcher polls -reactionChipsForMessage: on a
/// shared timer (one request per watched message every few seconds) and only
/// invokes `onChange` when the emoji, counts or chosen flags actually differ
/// from the previous read. `onChange` runs on the main queue with the chips
/// in the -reactionChipsForMessage: shape.
///
/// The watch table and its timer are file statics inside the category, since
/// a category cannot add ivars. Registering the same message twice replaces
/// the previous block. ALWAYS unwatch in -viewWillDisappear or -dealloc: the
/// block is retained until then, and so is anything it captures.
- (void)watchReactionsForMessage:(int64_t)messageId
                          inChat:(int64_t)chatId
                        onChange:(void (^)(NSArray *chips))onChange;

/// Stop watching one message. Safe to call for a message never watched.
- (void)unwatchReactionsForMessage:(int64_t)messageId inChat:(int64_t)chatId;

/// Stop every reaction watch and shut the shared timer down.
- (void)unwatchAllReactions;

/// Poll interval of the shared watch timer, in seconds. Defaults to 5, which
/// is what the 4S can carry with a couple of visible messages watched. Values
/// below 2 are clamped to 2. Applies from the next timer restart.
- (void)setReactionWatchInterval:(NSTimeInterval)seconds;

#pragma mark - unread reactions

/// Messages in a chat that carry a reaction the user has not seen yet, oldest
/// first, for the jump-to-next-reaction badge. `fromMessageId` is 0 to start
/// from the newest. `completion` receives an array of NSNumber message ids.
- (void)unreadReactionsInChat:(int64_t)chatId
                fromMessageId:(int64_t)fromMessageId
                        limit:(NSInteger)limit
                   completion:(void (^)(NSArray *messageIds))completion;

/// Mark every unread reaction in a chat as read, clearing the badge.
- (void)markReactionsReadInChat:(int64_t)chatId;

/// Mark every unread reaction inside one forum topic as read. Only meaningful
/// for a forum supergroup.
- (void)markReactionsReadInChat:(int64_t)chatId forumTopicId:(int64_t)topicId;

#pragma mark - moderation

/// Whether the signed-in user may moderate reactions on a message.
/// `completion` receives both flags; NO/NO on failure.
- (void)reactionPermissionsForMessage:(int64_t)messageId
                               inChat:(int64_t)chatId
                           completion:(void (^)(BOOL canDelete,
                                                BOOL canReport))completion;

/// Remove all reactions one sender left on one message. `senderId` is a user
/// id when positive and a chat id when negative, matching the "senderId" the
/// reaction list hands back. Gated on canDelete above.
- (void)deleteReactionsFromSender:(int64_t)senderId
                        onMessage:(int64_t)messageId
                           inChat:(int64_t)chatId;

/// Remove every recent reaction one sender left anywhere in a chat.
- (void)deleteAllRecentReactionsFromSender:(int64_t)senderId
                                    inChat:(int64_t)chatId;

/// Report a sender's reactions on a message as spam. Gated on canReport.
- (void)reportReactionsFromSender:(int64_t)senderId
                        onMessage:(int64_t)messageId
                           inChat:(int64_t)chatId;

#pragma mark - chat settings

/// Which reactions a chat allows, for the admin screen and for filtering the
/// picker. `completion` receives the allowed emoji (empty when all are
/// allowed or when reactions are off), whether every reaction is allowed, and
/// the maximum number of reactions one message may carry.
- (void)availableReactionsInChat:(int64_t)chatId
                      completion:(void (^)(NSArray *emojis,
                                           BOOL allowsAll,
                                           NSInteger maxCount))completion;

/// Admin: set the reactions a chat allows. Pass nil for `emojis` to allow all
/// of them, an empty array to switch reactions off entirely, or a list to
/// allow exactly those. `maxCount` below 1 falls back to 1.
- (void)setAvailableReactionsInChat:(int64_t)chatId
                             emojis:(NSArray *)emojis
                           maxCount:(NSInteger)maxCount;

#pragma mark - notification settings

/// Who may trigger a reaction notification. Pass one of "none", "contacts" or
/// "all"; anything else is treated as "all". The same source is applied to
/// message reactions, story reactions and poll votes, which is what a single
/// settings row can express. `soundId` of 0 means the default sound.
/// TDLib reports the current values only through an update this client does
/// not route yet, so the settings screen must hold its own state.
- (void)setReactionNotificationSource:(NSString *)source
                          showPreview:(BOOL)showPreview
                              soundId:(int64_t)soundId;

@end

// vim:ft=objc

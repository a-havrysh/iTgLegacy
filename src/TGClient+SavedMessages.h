/**
 * TGClient+SavedMessages - the Saved Messages chat: its topics, per-topic
 * history, tag reactions, search, pinning and per-topic drafts.
 *
 * Saved Messages is the signed-in user's own chat; its id is
 * -[TGClient savedMessagesChatId]. Inside it, forwarded messages are grouped
 * into "topics", one per original author, identified by an int53
 * saved_messages_topic_id. A topic id is NOT a chat id and NOT a forum topic
 * id - only pass values handed back by the methods here.
 *
 * TDLib never returns the topic list from a request: -loadSavedMessagesTopics
 * only asks the server for more, and the topics themselves arrive as
 * updateSavedMessagesTopic updates. This category keeps a live cache of them,
 * so the UI reads -cachedSavedMessagesTopics and redraws from the change
 * handler instead of re-requesting.
 *
 * Every completion runs on the main queue and may be nil.
 */
#import "TGClient.h"

@interface TGClient (SavedMessages)

#pragma mark - topics list

/**
 * Asks the server for up to `limit` more topics (0 means 100) and calls back
 * with the full cache once the resulting updates have been absorbed.
 *
 * `topics` is an array of dictionaries, pinned first then newest activity
 * first:
 *   "id"        NSNumber int53, the saved_messages_topic_id
 *   "kind"      NSString: "myNotes", "authorHidden" or "fromChat"
 *   "chatId"    NSNumber int64 of the original author's chat, 0 unless
 *               "kind" is "fromChat" - feed it to -nameForUserId: /
 *               -photoFileIdForChat: to draw the row
 *   "title"     NSString ready to show: "My Notes", "Hidden Author", or the
 *               known chat title, falling back to "" when the chat is not
 *               cached yet
 *   "text"      NSString preview of the last message ("" if none)
 *   "date"      NSNumber unix date of the last message, 0 if none
 *   "messageId" NSNumber int53 of the last message, 0 if none
 *   "outgoing"  NSNumber BOOL, last message was sent by us
 *   "isPinned"  NSNumber BOOL
 *   "order"     NSNumber int64 sort order, descending
 *   "draft"     NSString draft text for the topic, "" when there is none
 *
 * Call it again with the last topic already shown to page further; TDLib
 * answers with an error once every topic has been loaded, and the completion
 * then simply gets the unchanged cache.
 */
- (void)loadSavedMessagesTopicsWithLimit:(NSInteger)limit
                              completion:(void (^)(NSArray *topics))completion;

/// The topics received so far, same shape and order as above. Never nil.
- (NSArray *)cachedSavedMessagesTopics;

/// One cached topic by id, or nil when it has not been received yet.
- (NSDictionary *)cachedSavedMessagesTopic:(int64_t)topicId;

/// Total number of topics the server reports, or 0 before it says so.
- (NSInteger)savedMessagesTopicCount;

/// Called on the main queue whenever a topic was added, changed or removed,
/// or the total count changed. Read -cachedSavedMessagesTopics and reload the
/// table. Pass nil to stop.
- (void)setSavedMessagesTopicsChangedHandler:(void (^)(void))handler;

/// Drops the cached topics, e.g. when leaving the topics screen for good.
- (void)resetSavedMessagesTopicsCache;

#pragma mark - topic history

/**
 * One page of a topic's messages, oldest first, the order a chat view wants.
 *
 * Pass 0 for `fromMessageId` to start at the newest message; for the next
 * (older) page pass the "id" of the oldest message of the previous page.
 * `limit` 0 means 50.
 *
 * Each message dictionary carries:
 *   "id" NSNumber int53, "text" NSString preview/body, "date" NSNumber,
 *   "outgoing" NSNumber BOOL, "senderId" NSNumber user id (0 when the sender
 *   is a chat), "senderChatId" NSNumber, "isPinned" NSNumber BOOL,
 *   "tags" NSArray of tag emoji NSStrings attached to the message.
 * On error the array is empty.
 */
- (void)savedMessagesTopicHistory:(int64_t)topicId
                      fromMessage:(int64_t)fromMessageId
                            limit:(NSInteger)limit
                       completion:(void (^)(NSArray *messages))completion;

/// The first message of a topic sent on or after `date` (unix time), in the
/// same flattened shape as the history rows. Use it to jump to a date.
/// Completion gets nil when there is none.
- (void)savedMessagesTopic:(int64_t)topicId
             messageAtDate:(NSInteger)date
                completion:(void (^)(NSDictionary *message))completion;

/**
 * Sparse scroll positions across Saved Messages, for a fast-scroll date
 * bubble. Pass a topic id to restrict to one topic, or 0 for the whole chat.
 * `fromMessageId` 0 starts at the newest message; `limit` 0 means 100.
 *
 * `positions` is an array of dictionaries with "position" (index from the
 * newest message), "messageId" and "date". `totalCount` is the total number
 * of messages the positions are spread over. Empty array on error.
 */
- (void)savedMessagesSparsePositionsForTopic:(int64_t)topicId
                                 fromMessage:(int64_t)fromMessageId
                                       limit:(NSInteger)limit
                                  completion:(void (^)(NSArray *positions, NSInteger totalCount))completion;

#pragma mark - pinning topics

/// Pins or unpins a topic. `ok` is NO when the server refused, which for
/// pinning usually means the pinned-topic limit was reached (raising it needs
/// Premium) - show the message from onError.
- (void)setSavedMessagesTopic:(int64_t)topicId
                       pinned:(BOOL)pinned
                   completion:(void (^)(BOOL ok))completion;

/// Replaces the whole pinned set, in the order given. `topicIds` is an array
/// of NSNumber topic ids; pass an empty array to unpin everything. Use this
/// after a table edit-mode reorder.
- (void)setPinnedSavedMessagesTopics:(NSArray *)topicIds
                          completion:(void (^)(BOOL ok))completion;

#pragma mark - deleting

/// Deletes every message of a topic, which removes the topic itself.
/// Destructive: confirm first.
- (void)deleteSavedMessagesTopic:(int64_t)topicId
                      completion:(void (^)(BOOL ok))completion;

/// Deletes the messages of a topic sent between the two unix dates,
/// inclusive.
- (void)deleteSavedMessagesTopic:(int64_t)topicId
                    messagesFrom:(NSInteger)minDate
                              to:(NSInteger)maxDate
                      completion:(void (^)(BOOL ok))completion;

#pragma mark - tags

/// The tag list itself lives in TGClient+Search.h as
/// -savedMessagesTagsForTopic:completion:, and searching Saved Messages by
/// query and/or tag is -searchSavedMessagesWithQuery:tagEmoji:topicId:
/// fromMessageId:limit:completion: there. Use those; only the pieces below
/// are owned here.

/// Renames a tag, i.e. sets the label shown on its chip. Pass an empty
/// `label` to clear the name and fall back to the bare emoji.
- (void)setSavedMessagesTagLabel:(NSString *)label
                        forEmoji:(NSString *)emoji
                      completion:(void (^)(BOOL ok))completion;

/// Called on the main queue when the tag set changed (a tag was added,
/// removed or renamed anywhere). Re-request the tags and redraw the strip.
/// The argument is the topic whose tags changed, or 0 for the whole chat.
/// Pass nil to stop.
- (void)setSavedMessagesTagsChangedHandler:(void (^)(int64_t topicId))handler;

#pragma mark - pinned message inside Saved Messages

/// Pins a message inside the Saved Messages chat. Pinning is per chat, not
/// per topic, so the banner is the same in every topic.
- (void)pinSavedMessage:(int64_t)messageId completion:(void (^)(BOOL ok))completion;

/// Unpins one message of the Saved Messages chat.
- (void)unpinSavedMessage:(int64_t)messageId completion:(void (^)(BOOL ok))completion;

/// Unpins every message of the Saved Messages chat.
- (void)unpinAllSavedMessagesWithCompletion:(void (^)(BOOL ok))completion;

/// The currently pinned message of Saved Messages for the banner, flattened
/// like a history row, or nil when nothing is pinned.
- (void)savedMessagesPinnedMessageWithCompletion:(void (^)(NSDictionary *message))completion;

#pragma mark - per-topic drafts

/// Stores the composer text as the draft of a Saved Messages topic. Pass an
/// empty or nil `text` to clear it. The draft comes back on the topic row as
/// "draft" and can be restored when the topic is reopened.
- (void)setSavedMessagesTopic:(int64_t)topicId
                    draftText:(NSString *)text
                   completion:(void (^)(BOOL ok))completion;

#pragma mark - links

/// YES when `link` is a tg://saved style link, i.e. the URL handler should
/// open Saved Messages. Completion gets NO for anything else, including
/// errors.
- (void)linkOpensSavedMessages:(NSString *)link
                    completion:(void (^)(BOOL isSavedMessages))completion;

@end

// vim:ft=objc

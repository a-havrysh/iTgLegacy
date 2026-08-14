/**
 * TGClient+Forums - forum topics: listing, creating, editing, pinning,
 * closing, hiding General, deleting, per-topic notifications and icons.
 *
 * A forum supergroup keeps several independent threads ("topics") in one chat.
 * In the current TDLib schema a topic is identified by `forum_topic_id`, an
 * int32 that is NOT the same thing as the legacy message_thread_id used by
 * -historyForChat:thread:limit:completion: in TGClient.h. Always pass the
 * "topicId" value handed back by the methods here.
 *
 * Every completion runs on the main queue and may be nil.
 */
#import "TGClient.h"

@interface TGClient (Forums)

#pragma mark - listing

/**
 * One page of topics of a forum chat.
 *
 * `query` filters by topic name server-side; pass nil or @"" for all topics.
 * Pass 0 for all three offsets to get the first page; for the next page pass
 * the values out of the `nextOffset` dictionary of the previous call.
 *
 * `topics` is an array of dictionaries, newest activity first:
 *   "topicId"        NSNumber int32, the forum_topic_id - use this everywhere
 *   "threadId"       same value, kept so existing row code keeps compiling
 *   "chatId"         NSNumber int64
 *   "name"           NSString
 *   "text"           NSString, short preview of the last message ("" if none)
 *   "date"           NSNumber, unix date of the last message (0 if none)
 *   "unread"         NSNumber, unread message count
 *   "unreadMentions" NSNumber
 *   "unreadReactions" NSNumber
 *   "isGeneral"      NSNumber BOOL
 *   "isClosed"       NSNumber BOOL - hide the composer when YES
 *   "isHidden"       NSNumber BOOL - General only
 *   "isPinned"       NSNumber BOOL
 *   "isOutgoing"     NSNumber BOOL - the current user created the topic
 *   "iconColor"      NSNumber, 0xRRGGBB for the fallback circle
 *   "iconEmojiId"    NSNumber int64 custom emoji id, 0 when there is none
 *   "muteFor"        NSNumber seconds of remaining mute, 0 when unmuted
 *   "creatorId"      NSNumber user id, 0 when the sender was a chat
 *   "order"          NSNumber int64 sort order
 *
 * `nextOffset` has "date", "messageId" and "topicId" for the next page, or is
 * nil when the page was empty. `totalCount` is the server's total.
 * On error: topics is an empty array, nextOffset nil, totalCount 0.
 */
- (void)forumTopicsForChat:(int64_t)chatId
                     query:(NSString *)query
                offsetDate:(NSInteger)offsetDate
           offsetMessageId:(int64_t)offsetMessageId
             offsetTopicId:(int32_t)offsetTopicId
                     limit:(NSInteger)limit
                completion:(void (^)(NSArray *topics, NSDictionary *nextOffset, NSInteger totalCount))completion;

/// First page of topics (up to 100), same dictionary shape as above.
/// Convenience over the paging method; named differently from the older
/// -forumTopicsForChat:completion: in TGClient.h, which returns fewer fields.
- (void)forumTopicRowsForChat:(int64_t)chatId
                   completion:(void (^)(NSArray *topics))completion;

/// Server-side search of topic names in a forum. Same dictionary shape.
- (void)searchForumTopicsInChat:(int64_t)chatId
                          query:(NSString *)query
                     completion:(void (^)(NSArray *topics))completion;

/// One topic, freshly fetched. Completion receives the same dictionary shape
/// as a row of the list, or nil on error.
- (void)forumTopic:(int32_t)topicId
            inChat:(int64_t)chatId
        completion:(void (^)(NSDictionary *topic))completion;

/// Messages of one topic, oldest first. Pass 0 for `fromMessageId` to start at
/// the newest message. Each entry has "id", "text", "date", "outgoing" and
/// "senderId"; this is a reduced flattening, richer message fields still come
/// from the chat-level history calls in TGClient.h.
- (void)forumTopicHistoryForChat:(int64_t)chatId
                           topic:(int32_t)topicId
                     fromMessage:(int64_t)fromMessageId
                           limit:(NSInteger)limit
                      completion:(void (^)(NSArray *messages))completion;

#pragma mark - create and edit

/// The six topic icon colors TDLib accepts, as NSNumbers of 0xRRGGBB.
/// Anything else is rejected by the server.
- (NSArray *)forumTopicIconColors;

/// Create a topic. `iconColor` must be one of -forumTopicIconColors.
/// `iconEmojiId` is a custom emoji id or 0 for none (non-zero needs Premium).
/// Completion receives the new topic's dictionary, or nil on error.
- (void)createForumTopicInChat:(int64_t)chatId
                          name:(NSString *)name
                     iconColor:(NSInteger)iconColor
                   iconEmojiId:(int64_t)iconEmojiId
                    completion:(void (^)(NSDictionary *topic))completion;

/// Rename a topic and optionally change its custom-emoji icon.
/// Pass changeIcon NO to keep the current icon and ignore `iconEmojiId`;
/// pass changeIcon YES with iconEmojiId 0 to fall back to the color circle.
/// Requires can_manage_topics, or being the topic's creator for an open topic.
- (void)editForumTopicInChat:(int64_t)chatId
                       topic:(int32_t)topicId
                        name:(NSString *)name
                  changeIcon:(BOOL)changeIcon
                 iconEmojiId:(int64_t)iconEmojiId
                  completion:(void (^)(BOOL success))completion;

/// Close or reopen a topic. A closed topic accepts no new messages.
- (void)setForumTopicInChat:(int64_t)chatId
                      topic:(int32_t)topicId
                     closed:(BOOL)closed
                 completion:(void (^)(BOOL success))completion;

/// Hide or unhide the General topic of a forum. Only valid on the topic whose
/// "isGeneral" is YES, and requires can_manage_topics.
- (void)setGeneralForumTopicInChat:(int64_t)chatId
                            hidden:(BOOL)hidden
                        completion:(void (^)(BOOL success))completion;

/// Pin or unpin a topic at the top of the list.
- (void)setForumTopicInChat:(int64_t)chatId
                      topic:(int32_t)topicId
                     pinned:(BOOL)pinned
                 completion:(void (^)(BOOL success))completion;

/// Replace the whole pinned set, in the order given. `topicIds` is an array of
/// NSNumbers of topic ids.
- (void)setPinnedForumTopicsInChat:(int64_t)chatId
                          topicIds:(NSArray *)topicIds
                        completion:(void (^)(BOOL success))completion;

/// Delete a topic and all of its messages. Requires can_delete_messages.
- (void)deleteForumTopicInChat:(int64_t)chatId
                         topic:(int32_t)topicId
                    completion:(void (^)(BOOL success))completion;

#pragma mark - per-topic housekeeping

/// Mute a topic for `seconds` (use a large value such as 2^31-1 for forever),
/// 0 to unmute, or a negative value to go back to the chat's default.
- (void)setForumTopicInChat:(int64_t)chatId
                      topic:(int32_t)topicId
                   mutedFor:(NSInteger)seconds
                 completion:(void (^)(BOOL success))completion;

/// Clear a topic's unread mentions, reactions and poll votes in one go.
/// Call it when the topic is opened, and from a "Mark as read" action.
- (void)markForumTopicReadInChat:(int64_t)chatId
                           topic:(int32_t)topicId
                      completion:(void (^)(BOOL success))completion;

/// Unpin every pinned message inside a topic.
- (void)unpinAllMessagesInForumTopicInChat:(int64_t)chatId
                                     topic:(int32_t)topicId
                                completion:(void (^)(BOOL success))completion;

/// A t.me link to a topic, for the pasteboard. Completion receives the link
/// string, or nil on error.
- (void)forumTopicLinkInChat:(int64_t)chatId
                       topic:(int32_t)topicId
                  completion:(void (^)(NSString *link))completion;

#pragma mark - icons

/// The default custom-emoji icons a non-Premium user may pick for a topic.
/// Each entry: "emojiId" (NSNumber int64 custom emoji id), "emoji" (NSString),
/// "thumbFileId" (NSNumber file id of a static thumbnail, 0 if none),
/// "fileId" (NSNumber file id of the sticker itself). Feed "thumbFileId" to
/// the existing file download plumbing to draw a real glyph; fall back to the
/// color circle when it is 0 or the download fails.
- (void)forumTopicDefaultIconsWithCompletion:(void (^)(NSArray *icons))completion;

#pragma mark - forum mode

/// Turn a supergroup into a forum, or back. Requires owner rights.
/// `hasTabs` is passed straight through and should be NO for this client.
- (void)setSupergroup:(int64_t)supergroupId
              isForum:(BOOL)isForum
              hasTabs:(BOOL)hasTabs
           completion:(void (^)(BOOL success))completion;

/// Whether opening the chat shows the topic list or a flat message list.
- (void)setChat:(int64_t)chatId
   viewAsTopics:(BOOL)viewAsTopics
     completion:(void (^)(BOOL success))completion;

@end

// vim:ft=objc

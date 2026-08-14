/**
 * TGClient+Search - searching messages, chats, hashtags and tags.
 *
 * Every completion runs on the main queue and may be nil. Results are plain
 * Foundation objects: message rows are flattened dictionaries with the keys
 *
 *   "id"         NSNumber, message id
 *   "chatId"     NSNumber, chat the message lives in
 *   "chatTitle"  NSString, chat title if the client already knows it, else ""
 *   "text"       NSString, caption or text or a short description of the media
 *   "date"       NSNumber, unix time
 *   "outgoing"   NSNumber BOOL
 *   "senderId"   NSNumber, user id of the sender, 0 for a channel post
 *   "senderName" NSString, "" when unknown
 *   "photoId"    NSNumber file id of a picture to show, or NSNull
 *   "kind"       NSString, the TDLib content type name ("messagePhoto", ...)
 *
 * `filter` arguments are TDLib SearchMessagesFilter type names, e.g.
 * "searchMessagesFilterPhotoAndVideo", "searchMessagesFilterDocument",
 * "searchMessagesFilterVoiceNote", "searchMessagesFilterUrl",
 * "searchMessagesFilterAudio". Pass nil for no filter.
 */
#import "TGClient.h"

@interface TGClient (Search)

#pragma mark - global message search

/// Full global message search with every knob TDLib offers.
/// `filter` is a SearchMessagesFilter type name or nil.
/// `chatType` is "private", "group" or "channel", or nil for all of them.
/// `minDate`/`maxDate` are unix times; 0 means unbounded.
/// `offset` is @"" for the first page, or the `nextOffset` handed back by the
/// previous call; an empty `nextOffset` means there is nothing more to load.
/// `completion` gets flattened message rows and the offset for the next page.
- (void)searchMessagesWithQuery:(NSString *)query
                         filter:(NSString *)filter
                       chatType:(NSString *)chatType
                        minDate:(NSInteger)minDate
                        maxDate:(NSInteger)maxDate
                         offset:(NSString *)offset
                          limit:(NSInteger)limit
                     completion:(void (^)(NSArray *messages, NSString *nextOffset))completion;

/// Short form of the above: query, optional filter, one page from `offset`.
- (void)searchMessagesWithQuery:(NSString *)query
                         filter:(NSString *)filter
                         offset:(NSString *)offset
                     completion:(void (^)(NSArray *messages, NSString *nextOffset))completion;

#pragma mark - in-chat message search

/// Search inside one chat, newest first.
/// `senderUserId` limits results to one sender; pass 0 for anyone.
/// `filter` is a SearchMessagesFilter type name or nil.
/// `fromMessageId` is 0 for the newest page, or the `nextFromMessageId` of the
/// previous call; a `nextFromMessageId` of 0 means the end was reached.
- (void)searchMessagesInChat:(int64_t)chatId
                       query:(NSString *)query
                senderUserId:(int64_t)senderUserId
                      filter:(NSString *)filter
               fromMessageId:(int64_t)fromMessageId
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *messages, int64_t nextFromMessageId, NSInteger totalCount))completion;

/// Live location messages currently being shared in a chat.
- (void)recentLocationMessagesInChat:(int64_t)chatId
                               limit:(NSInteger)limit
                          completion:(void (^)(NSArray *messages))completion;

#pragma mark - special message searches

/// Call messages across all chats, for a recent-calls list.
/// `onlyMissed` restricts it to calls that were never answered.
/// Paged the same way as the global search.
- (void)searchCallMessagesOnlyMissed:(BOOL)onlyMissed
                              offset:(NSString *)offset
                               limit:(NSInteger)limit
                          completion:(void (^)(NSArray *messages, NSString *nextOffset))completion;

/// Documents the signed-in user has sent, for re-sharing a file.
- (void)searchOutgoingDocumentsWithQuery:(NSString *)query
                                   limit:(NSInteger)limit
                              completion:(void (^)(NSArray *messages))completion;

/// Public posts carrying a #hashtag or $cashtag. `tag` may be given with or
/// without its leading # - it is passed through as typed.
- (void)searchPublicMessagesWithTag:(NSString *)tag
                             offset:(NSString *)offset
                              limit:(NSInteger)limit
                         completion:(void (^)(NSArray *messages, NSString *nextOffset))completion;

#pragma mark - hashtags

/// Hashtag autocomplete for what the user has typed so far. `prefix` is given
/// without the '#'. `completion` gets an NSArray of NSString tags, also
/// without the '#'.
- (void)searchHashtagsWithPrefix:(NSString *)prefix
                           limit:(NSInteger)limit
                      completion:(void (^)(NSArray *hashtags))completion;

/// Tags the user has searched for before, for the empty hashtag-search state.
/// `prefix` may be @"" for the whole list. Same NSString array shape.
- (void)searchedForTagsWithPrefix:(NSString *)prefix
                            limit:(NSInteger)limit
                       completion:(void (^)(NSArray *hashtags))completion;

/// Forget one remembered tag. `tag` must include its leading '#' or '$'.
- (void)removeSearchedForTag:(NSString *)tag;

/// Forget all remembered hashtags, or all remembered cashtags.
- (void)clearSearchedForTagsIncludingCashtags:(BOOL)cashtags;

// Saved Messages search and reaction tags live in TGClient+SavedMessages.h:
// -searchSavedMessagesWithQuery:tagEmoji:topic:fromMessage:limit:completion:,
// -savedMessagesTagsForTopic:completion: and
// -setSavedMessagesTagLabel:forEmoji:completion:.

#pragma mark - recents

/// Chats the user picked out of search results before, newest first. Pass
/// @"" as the query for the whole list. Each entry: "id" (NSNumber),
/// "title" (NSString), "photoFileId" (NSNumber or NSNull).
/// TDLib has no separate getRecentlyFoundChats; this is the same list.
- (void)recentlyFoundChatsWithQuery:(NSString *)query
                              limit:(NSInteger)limit
                         completion:(void (^)(NSArray *chats))completion;

#pragma mark - jumping around a history

/// Newest message sent at or before `date` in a chat, so the history can jump
/// to a day. `completion` gets 0 when the chat has nothing that old.
- (void)messageInChat:(int64_t)chatId
        closestToDate:(NSInteger)date
           completion:(void (^)(int64_t messageId))completion;

/// Per-day message counts for a calendar view, newest day first. Each entry:
/// "date" (NSNumber unix time of the day's first message), "count" (NSNumber)
/// and "messageId" (NSNumber, the message to jump to for that day).
/// `filter` narrows it to one media type, or nil for everything.
- (void)messageCalendarForChat:(int64_t)chatId
                        filter:(NSString *)filter
                 fromMessageId:(int64_t)fromMessageId
                    completion:(void (^)(NSArray *days, NSInteger totalCount))completion;

/// Sparse positions of messages in a chat, for a fast-scroll date indicator on
/// a shared-media grid. Each entry: "position" (NSNumber, index from the
/// newest message), "messageId" (NSNumber) and "date" (NSNumber).
- (void)sparseMessagePositionsInChat:(int64_t)chatId
                              filter:(NSString *)filter
                       fromMessageId:(int64_t)fromMessageId
                               limit:(NSInteger)limit
                          completion:(void (^)(NSArray *positions, NSInteger totalCount))completion;

#pragma mark - text helpers

/// Which of `strings` start with `query`, for filtering a local list such as
/// the country picker. `completion` gets an NSArray of NSNumber indexes into
/// the array that was passed in.
- (void)indexesOfStrings:(NSArray *)strings
           matchingPrefix:(NSString *)query
                    limit:(NSInteger)limit
               completion:(void (^)(NSArray *indexes))completion;

/// Character offset of `quote` inside `text`, for highlighting a quoted
/// fragment. `completion` gets -1 when the quote is not in the text.
- (void)positionOfQuote:(NSString *)quote
                 inText:(NSString *)text
             completion:(void (^)(NSInteger position))completion;

@end

// vim:ft=objc

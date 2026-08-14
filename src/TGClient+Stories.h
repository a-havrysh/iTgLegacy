/**
 * TGClient+Stories - posting, viewing, listing and moderating stories.
 *
 * Story ids are int32 and always belong to a poster chat, so nearly every call
 * takes the pair (storyId, posterChatId). Everything handed back is plain
 * Foundation data; nothing here returns a raw TDLib object.
 *
 * A flattened story dictionary, as produced by -storyWithId:inChat:completion:
 * and by every list call, has:
 *   "id"           NSNumber, story id (int32)
 *   "chatId"       NSNumber, poster chat id
 *   "senderId"     NSNumber, poster user id (0 for a channel post)
 *   "date"         NSNumber, unix time
 *   "caption"      NSString, plain text of the caption (never nil)
 *   "kind"         NSString, "photo", "video", "live" or "unsupported"
 *   "photoId"      NSNumber file id of the largest still image, or nil
 *   "videoId"      NSNumber file id of the LOW quality alternative video, or
 *                  nil. The full-quality video is deliberately not exposed:
 *                  a 4S must never be asked to fetch or decode it.
 *   "duration"     NSNumber seconds, video stories only
 *   "width"/"height" NSNumber, video stories only
 *   "views"        NSNumber, "forwards" NSNumber, "reactions" NSNumber
 *   "myReaction"   NSString emoji the user reacted with, or "" if none
 *   "privacy"      NSString, one of the privacy values below, or ""
 *   "isEdited", "isBeingPosted", "isBeingEdited", "onProfile",
 *   "canDelete", "canEdit", "canForward", "canReply", "canSetPrivacy",
 *   "canToggleProfile", "canGetViewers", "expiredViewers"
 *                  NSNumber BOOL each
 *   "repostFrom"   NSString name of the original poster for a repost, or ""
 *   "albumIds"     NSArray of NSNumber
 *   "areas"        NSArray of interactive areas, see below
 *
 * An area dictionary:
 *   "kind"   NSString: "location", "venue", "reaction", "message", "link",
 *            "weather", "gift" or "unsupported"
 *   "x", "y", "width", "height", "rotation", "cornerRadius"
 *            NSNumber percentages 0..100 of the story frame, as TDLib gives
 *            them, so hit testing is frame.size * value / 100
 *   "url"    NSString for a link area, "" otherwise
 *   "emoji"  NSString for a reaction or weather area, "" otherwise
 *   "title"  NSString, a short human label for venue/weather/gift areas
 *   "latitude"/"longitude" NSNumber for location and venue areas
 *   "chatId"/"messageId"   NSNumber for a message area
 *
 * Privacy values used by this category, matching the four rows every client
 * offers: "everyone", "contacts", "closeFriends", "selected".
 */
#import "TGClient.h"

@interface TGClient (Stories)

#pragma mark - active stories (the tray)

/// Ask TDLib to fill in the active story list. Answers are delivered as
/// updateChatActiveStories, so call this once at startup and then read the
/// per-chat state with -activeStoriesForChat:completion:.
/// `archived` picks the Archive list instead of the Main one.
- (void)loadActiveStoriesArchived:(BOOL)archived;

/// Active (unexpired) stories of one chat, or nil when it has none. Keys:
/// "chatId", "order" (NSNumber, higher sorts first in the tray),
/// "canBeArchived" (NSNumber BOOL), "maxReadStoryId" (NSNumber),
/// "unread" (NSNumber BOOL - at least one story newer than maxReadStoryId),
/// "archived" (NSNumber BOOL - it is in the Archive list),
/// "stories" (NSArray of {"id", "date", "closeFriends", "isLive"}).
- (void)activeStoriesForChat:(int64_t)chatId
                  completion:(void (^)(NSDictionary *active))completion;

/// Move a poster between the main tray and the archived tray.
- (void)setChat:(int64_t)chatId storiesArchived:(BOOL)archived;

#pragma mark - viewing

/// One story, flattened as described at the top of this header. `completion`
/// gets nil when the story is gone or not visible to us.
- (void)storyWithId:(NSInteger)storyId
             inChat:(int64_t)chatId
         completion:(void (^)(NSDictionary *story))completion;

/// Tell TDLib a story is on screen. This is what marks it read and what keeps
/// the unread ring accurate, so the viewer must call it on every page turn.
- (void)openStory:(NSInteger)storyId inChat:(int64_t)chatId;
/// The matching close. Call it when the story scrolls away or the viewer exits.
- (void)closeStory:(NSInteger)storyId inChat:(int64_t)chatId;

/// Mark a story read without showing it - open immediately followed by close.
- (void)markStoryRead:(NSInteger)storyId inChat:(int64_t)chatId;

#pragma mark - interactions

/// Emoji the reaction strip should offer, most useful first, capped at `limit`.
- (void)storyReactionsWithLimit:(NSInteger)limit
                     completion:(void (^)(NSArray *emoji))completion;

/// React to a story. Pass nil or an empty string to take the reaction back.
- (void)reactToStory:(NSInteger)storyId
              inChat:(int64_t)chatId
               emoji:(NSString *)emoji;

/// Who viewed one of OUR stories. Each entry: "id" (user id), "name",
/// "date", "emoji" (their reaction or ""), "kind" ("view", "forward" or
/// "repost"), "blocked" (NSNumber BOOL - they are on a block list).
/// `offset` is nil for the first page, then the "nextOffset" of the previous
/// answer; `nextOffset` is empty when the list is exhausted.
- (void)viewersOfStory:(NSInteger)storyId
                offset:(NSString *)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *viewers, NSString *nextOffset, NSInteger total))completion;

/// The same list for a story posted by a chat we administer.
- (void)viewersOfStory:(NSInteger)storyId
                inChat:(int64_t)chatId
                offset:(NSString *)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *viewers, NSString *nextOffset, NSInteger total))completion;

/// Send a text reply to a story. It lands in the poster's private chat with a
/// reply-to-story header, which is what the official client does from the
/// viewer's composer.
- (void)replyToStory:(NSInteger)storyId
              inChat:(int64_t)chatId
                text:(NSString *)text;

/// Public reposts and forwards of a story. Each entry: "chatId", "title",
/// "date", "isStory" (NSNumber BOOL), "storyId" when it is a repost.
- (void)publicForwardsOfStory:(NSInteger)storyId
                       inChat:(int64_t)chatId
                       offset:(NSString *)offset
                        limit:(NSInteger)limit
                   completion:(void (^)(NSArray *forwards, NSString *nextOffset))completion;

#pragma mark - posting

/// Whether a story may be posted as `chatId` right now. `reason` is nil when
/// it can, and a ready-to-show alert message otherwise.
- (void)canPostStoryAsChat:(int64_t)chatId
                completion:(void (^)(BOOL canPost, NSString *reason))completion;

/// Chats the user may post a story as - their own account first, then any
/// channel with the right. Each entry: "id", "title".
- (void)chatsToPostStoriesWithCompletion:(void (^)(NSArray *chats))completion;

/// Post a photo story from a local file. `privacy` is one of the four privacy
/// values; `userIds` is the exception list for "everyone"/"contacts" and the
/// allow list for "selected", and may be nil. The expiry is fixed at 24h
/// because anything else is Premium-only. `completion` gets the flattened
/// story TDLib created, or nil if the call was refused.
- (void)postPhotoStoryAtPath:(NSString *)path
                      asChat:(int64_t)chatId
                     caption:(NSString *)caption
                     privacy:(NSString *)privacy
                     userIds:(NSArray *)userIds
                   toProfile:(BOOL)toProfile
                  completion:(void (^)(NSDictionary *story))completion;

/// Repost someone else's story as our own, optionally with a new caption.
- (void)repostStory:(NSInteger)storyId
           fromChat:(int64_t)fromChatId
             asChat:(int64_t)chatId
            caption:(NSString *)caption
            privacy:(NSString *)privacy
         completion:(void (^)(NSDictionary *story))completion;

/// Change the caption of a story we posted, leaving its content alone.
- (void)editStory:(NSInteger)storyId
           inChat:(int64_t)chatId
          caption:(NSString *)caption;

/// Replace the content of a story with another local photo.
- (void)editStory:(NSInteger)storyId
           inChat:(int64_t)chatId
        photoPath:(NSString *)path
          caption:(NSString *)caption;

/// Delete one of our stories.
- (void)deleteStory:(NSInteger)storyId inChat:(int64_t)chatId;

#pragma mark - privacy

/// Change who can see an already posted story. Same `privacy`/`userIds`
/// meaning as -postPhotoStoryAtPath:.
- (void)setStory:(NSInteger)storyId
         privacy:(NSString *)privacy
         userIds:(NSArray *)userIds;

/// The close friends list: "id", "name", "username".
- (void)closeFriendsWithCompletion:(void (^)(NSArray *users))completion;
/// Replace the close friends list wholesale with these user ids.
- (void)setCloseFriends:(NSArray *)userIds;

/// People whose stories are hidden from the tray: "id", "name".
- (void)hiddenStoryPostersWithCompletion:(void (^)(NSArray *users))completion;
/// Hide or unhide a poster's stories. This is the stories block list, which is
/// separate from blocking the user outright.
- (void)setUser:(int64_t)userId storiesHidden:(BOOL)hidden;

#pragma mark - archive and profile

/// Our expired stories, newest first. `fromStoryId` is 0 for the first page,
/// then the id of the oldest story already shown.
- (void)archivedStoriesInChat:(int64_t)chatId
                  fromStoryId:(NSInteger)fromStoryId
                        limit:(NSInteger)limit
                   completion:(void (^)(NSArray *stories, NSInteger total))completion;

/// Stories a chat keeps on its profile page. `pinnedIds` are the subset shown
/// at the top.
- (void)profileStoriesInChat:(int64_t)chatId
                 fromStoryId:(NSInteger)fromStoryId
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *stories, NSArray *pinnedIds, NSInteger total))completion;

/// Keep a story on the profile page after it expires, or take it off again.
- (void)setStory:(NSInteger)storyId inChat:(int64_t)chatId onProfile:(BOOL)onProfile;

/// Replace the pinned story ids of a profile.
- (void)setPinnedStories:(NSArray *)storyIds inChat:(int64_t)chatId;

#pragma mark - albums

/// Story albums of a chat: "id", "name".
- (void)storyAlbumsInChat:(int64_t)chatId completion:(void (^)(NSArray *albums))completion;
- (void)createStoryAlbumInChat:(int64_t)chatId
                          name:(NSString *)name
                      storyIds:(NSArray *)storyIds
                    completion:(void (^)(NSDictionary *album))completion;
- (void)renameStoryAlbum:(NSInteger)albumId
                  inChat:(int64_t)chatId
                    name:(NSString *)name
              completion:(void (^)(NSDictionary *album))completion;
- (void)deleteStoryAlbum:(NSInteger)albumId inChat:(int64_t)chatId;
/// Album ids in the order they should appear.
- (void)reorderStoryAlbums:(NSArray *)albumIds inChat:(int64_t)chatId;

/// Contents of one album, flattened stories.
- (void)storiesInAlbum:(NSInteger)albumId
                inChat:(int64_t)chatId
                offset:(NSInteger)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *stories, NSInteger total))completion;
/// Add, remove or reorder album members. `completion` gets the updated album.
- (void)addStories:(NSArray *)storyIds
           toAlbum:(NSInteger)albumId
            inChat:(int64_t)chatId
        completion:(void (^)(NSDictionary *album))completion;
- (void)removeStories:(NSArray *)storyIds
            fromAlbum:(NSInteger)albumId
               inChat:(int64_t)chatId
           completion:(void (^)(NSDictionary *album))completion;
- (void)reorderStories:(NSArray *)storyIds
               inAlbum:(NSInteger)albumId
                inChat:(int64_t)chatId
            completion:(void (^)(NSDictionary *album))completion;

#pragma mark - search and links

/// Public stories carrying a hashtag. Pass 0 for `posterChatId` to search
/// everywhere. `offset` is nil for the first page.
- (void)searchStoriesWithTag:(NSString *)tag
                posterChatId:(int64_t)posterChatId
                      offset:(NSString *)offset
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *stories, NSString *nextOffset, NSInteger total))completion;

/// Public stories posted at a venue, as an interactive venue area links to.
- (void)searchStoriesAtVenueProvider:(NSString *)provider
                             venueId:(NSString *)venueId
                              offset:(NSString *)offset
                               limit:(NSInteger)limit
                          completion:(void (^)(NSArray *stories, NSString *nextOffset, NSInteger total))completion;

/// Resolve a t.me story link into something the viewer can open. `completion`
/// gets the poster chat id and story id, or (0, 0) when the link is not a
/// story link or the username does not resolve.
- (void)resolveStoryLink:(NSString *)link
              completion:(void (^)(int64_t chatId, NSInteger storyId))completion;

#pragma mark - reporting and notifications

/// Report a story. The flow is the same multi-step one messages use:
/// `completion` gets a dictionary with "status" of
///   "ok"     - accepted, nothing more to do
///   "option" - show "title" and pick one of "options" ({"id", "text"}),
///              then call again with that id
///   "text"   - ask for free text, "optional" (NSNumber BOOL) says whether it
///              may be empty, then call again with the same "optionId"
///   "error"  - the call failed
/// `optionId` and `text` are nil on the first call.
- (void)reportStory:(NSInteger)storyId
             inChat:(int64_t)chatId
           optionId:(NSString *)optionId
               text:(NSString *)text
         completion:(void (^)(NSDictionary *result))completion;

/// Mute or unmute one chat's stories, leaving its message notifications as
/// they are.
- (void)setChat:(int64_t)chatId storiesMuted:(BOOL)muted;

/// Chats with a story notification setting of their own: "id", "title".
- (void)storyNotificationExceptionsWithCompletion:(void (^)(NSArray *chats))completion;

/// Who may trigger a notification when they react to our story. `source` is
/// "all", "contacts" or "none". Note this rewrites the whole reaction
/// notification record, so message-reaction and poll sources follow it.
- (void)setStoryReactionNotificationSource:(NSString *)source;

/// Whether stories are fetched ahead of time on the given network. Off is the
/// right default on this hardware. `type` is "mobile" or "wifi".
- (void)setStoryPreloading:(BOOL)preload onNetwork:(NSString *)type;

@end

// vim:ft=objc

//
// TGClient+Stickers - sticker sets, stickers, emoji suggestions, custom emoji.
//
// Everything here returns plain Foundation objects on the main queue.
//
// Two shapes are used throughout:
//
//   sticker  = { "fileId"       : NSNumber, file id of the sticker file
//                "setId"        : NSNumber, int64 id of the owning set
//                "emoji"        : NSString, may be empty
//                "width"        : NSNumber
//                "height"       : NSNumber
//                "isAnimated"   : NSNumber BOOL, YES for .tgs and .webm
//                "isVideo"      : NSNumber BOOL, YES for .webm (undrawable here)
//                "thumbId"      : NSNumber, thumbnail file id or 0
//                "customEmojiId": NSNumber, 0 unless this is a custom emoji }
//
//   set      = { "id"        : NSNumber, int64 set id
//                "title"     : NSString
//                "name"      : NSString, short name used in t.me/addstickers links
//                "count"     : NSNumber, number of stickers in the set
//                "installed" : NSNumber BOOL
//                "archived"  : NSNumber BOOL
//                "official"  : NSNumber BOOL
//                "viewed"    : NSNumber BOOL, NO means "new" in the trending list
//                "isEmoji"   : NSNumber BOOL, custom-emoji set rather than stickers
//                "thumbId"   : NSNumber, set thumbnail file id or 0
//                "covers"    : NSArray of sticker, may be empty
//                "stickers"  : NSArray of sticker, only filled by the
//                              stickerSetWithId:/WithName: calls }
//
// Set ids are int64. TDLib sends them over JSON as strings; every method here
// takes and returns them as int64_t / NSNumber, so callers never see that.
//
#import "TGClient.h"

@interface TGClient (Stickers)

/// Installed regular sticker sets, in the user's own order. Completion gets an
/// array of set dictionaries (no "stickers"), or nil on error.
- (void)installedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;

/// Installed custom-emoji sets. Same shape as installedStickerSetsWithCompletion:.
- (void)installedEmojiStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;

/// Archived (installed once, then archived) sticker sets. Pass 0 for
/// `offsetSetId` for the first page. Completion gets (sets, totalCount).
- (void)archivedStickerSetsFromSetId:(int64_t)offsetSetId
                               limit:(NSInteger)limit
                          completion:(void (^)(NSArray *sets, NSInteger totalCount))completion;

/// Trending / featured sticker sets. Completion gets (sets, totalCount); a set
/// whose "viewed" is NO should be badged as new.
- (void)trendingStickerSetsWithOffset:(NSInteger)offset
                                limit:(NSInteger)limit
                           completion:(void (^)(NSArray *sets, NSInteger totalCount))completion;

/// Tell the server the given trending sets were shown, which clears their
/// unread badge. `setIds` is an array of NSNumber int64 set ids.
- (void)markTrendingStickerSetsViewed:(NSArray *)setIds;

/// One full set with all of its stickers in "stickers". Completion gets the set
/// dictionary or nil.
- (void)stickerSetWithId:(int64_t)setId completion:(void (^)(NSDictionary *set))completion;

/// Same, looked up by short name - what a t.me/addstickers/<name> link carries.
- (void)stickerSetWithName:(NSString *)name completion:(void (^)(NSDictionary *set))completion;

/// Install a set (also un-archives it). Completion gets YES on success.
- (void)installStickerSet:(int64_t)setId completion:(void (^)(BOOL ok))completion;

/// Remove a set from the installed list entirely.
- (void)uninstallStickerSet:(int64_t)setId completion:(void (^)(BOOL ok))completion;

/// Move an installed set to the archive; it stays restorable.
- (void)archiveStickerSet:(int64_t)setId completion:(void (^)(BOOL ok))completion;

/// New order of the installed regular sets, as an array of NSNumber set ids.
/// Must list every installed set.
- (void)reorderInstalledStickerSets:(NSArray *)setIds;

/// Search the installed sets by title. Completion gets an array of sets.
- (void)searchInstalledStickerSets:(NSString *)query
                             limit:(NSInteger)limit
                        completion:(void (^)(NSArray *sets))completion;

/// Search all public sticker sets on the server by title or short name.
- (void)searchStickerSets:(NSString *)query completion:(void (^)(NSArray *sets))completion;

/// Favourite stickers, most recent first. Completion gets an array of stickers.
- (void)favoriteStickersWithCompletion:(void (^)(NSArray *stickers))completion;

/// Add a sticker to favourites, by its sticker file id.
- (void)addFavoriteStickerWithFileId:(NSInteger)fileId;

/// Remove a sticker from favourites.
- (void)removeFavoriteStickerWithFileId:(NSInteger)fileId;

/// Push a sticker to the front of the recently used strip.
- (void)addRecentStickerWithFileId:(NSInteger)fileId;

/// Drop one sticker from the recently used strip.
- (void)removeRecentStickerWithFileId:(NSInteger)fileId;

/// Empty the recently used strip.
- (void)clearRecentStickers;

/// Stickers matching one or more emoji, server side, including sets the user
/// has not installed. `query` may be nil. Completion gets an array of stickers.
- (void)searchStickersByEmoji:(NSString *)emoji
                        query:(NSString *)query
                        limit:(NSInteger)limit
                   completion:(void (^)(NSArray *stickers))completion;

/// Stickers from the user's installed sets that match `query` (an emoji or a
/// word). This is the local lookup used for the suggestion strip above the
/// input when the composed text is a single emoji.
- (void)installedStickersMatching:(NSString *)query
                            limit:(NSInteger)limit
                       completion:(void (^)(NSArray *stickers))completion;

/// YES when the server wants us to offer sticker suggestions for a lone typed
/// emoji. Read once and cache; it does not change often.
- (void)stickerSuggestionEnabledWithCompletion:(void (^)(BOOL enabled))completion;

/// Every emoji that has a sticker in the installed sets, for the emoji tab
/// strip of the sticker panel. Completion gets an array of NSString.
- (void)allStickerEmojisForQuery:(NSString *)query
                      completion:(void (^)(NSArray *emojis))completion;

/// Emoji whose keyword starts with the typed text, for the ":smile" suggestion
/// bar. Completion gets an array of { "emoji" : NSString, "keyword" : NSString }.
- (void)emojiSuggestionsForText:(NSString *)text
                     completion:(void (^)(NSArray *suggestions))completion;

/// Emoji for an exact keyword, no fuzzy matching. Array of NSString.
- (void)keywordEmojisForText:(NSString *)text
                  completion:(void (^)(NSArray *emojis))completion;

/// Emoji keyboard categories (Smileys, Animals, ...). Completion gets an array
/// of { "name" : NSString, "isGreeting" : NSNumber BOOL,
///      "icon" : sticker, "emojis" : NSArray of NSString }.
/// Pass NO for `forStickers` to get the emoji categories, YES for the category
/// row of the sticker panel.
- (void)emojiCategoriesForStickers:(BOOL)forStickers
                        completion:(void (^)(NSArray *categories))completion;

/// Stickers Telegram suggests for greeting someone in an empty chat.
- (void)greetingStickersWithCompletion:(void (^)(NSArray *stickers))completion;

/// Resolve custom emoji ids found in message text entities into stickers so
/// they can be drawn inline. `customEmojiIds` is an array of NSNumber int64.
- (void)customEmojiStickersWithIds:(NSArray *)customEmojiIds
                        completion:(void (^)(NSArray *stickers))completion;

/// Sticker sets attached to a photo or video file, for the media viewer's
/// "Stickers" button. Completion gets an array of sets.
- (void)attachedStickerSetsForFileId:(NSInteger)fileId
                          completion:(void (^)(NSArray *sets))completion;

/// Set (or clear, with 0) the group sticker pack of a supergroup.
- (void)setStickerSet:(int64_t)setId
       forSupergroup:(int64_t)supergroupId
          completion:(void (^)(BOOL ok))completion;

/// Set (or clear, with 0) the group custom-emoji pack of a supergroup.
- (void)setCustomEmojiStickerSet:(int64_t)setId
                   forSupergroup:(int64_t)supergroupId
                      completion:(void (^)(BOOL ok))completion;

/// Vector silhouette of a sticker, to draw while its file downloads.
/// Completion gets an array of closed paths; each path is an array of
/// { "type" : @"line" | @"curve", "x", "y" } and, for curves,
/// "c1x", "c1y", "c2x", "c2y". All coordinates are NSNumber doubles in the
/// sticker's own width/height space.
- (void)stickerOutlineForFileId:(NSInteger)fileId
                     completion:(void (^)(NSArray *paths))completion;

@end

// vim:ft=objc

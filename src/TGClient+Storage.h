//
// TGClient+Storage - storage statistics, cache management, downloads,
// network usage and auto-download settings.
//
// Every completion runs on the main queue and is safe to pass as nil.
// Sizes are bytes; a "no limit" argument is -1 as TDLib expects.
//
#import "TGClient.h"

/// File-type category names this category accepts wherever `kinds` or
/// `category` appears. They are plain TDLib FileType type names, e.g.
/// @"fileTypePhoto", @"fileTypeVideo", @"fileTypeDocument", @"fileTypeAudio",
/// @"fileTypeVoiceNote", @"fileTypeVideoNote", @"fileTypeAnimation",
/// @"fileTypeSticker", @"fileTypeProfilePhoto", @"fileTypeThumbnail",
/// @"fileTypeWallpaper".

@interface TGClient (Storage)

#pragma mark - statistics

/// Fast storage overview, the whole of storageStatisticsFast rather than just
/// the two fields -storageStatsWithCompletion: returns. Keys: "files" (bytes,
/// NSNumber), "fileCount" (NSNumber), "database" (bytes), "languagePack"
/// (bytes), "log" (bytes), "total" (bytes, everything above added up).
/// Nil on failure.
- (void)storageOverviewWithCompletion:(void (^)(NSDictionary *overview))completion;

/// Exact cache usage per file-type category. Walks every cached file, so it
/// takes seconds on a 4S - show a spinner. `sizes` maps a FileType name
/// (@"fileTypePhoto" and friends) to an NSDictionary with "size" (bytes) and
/// "count". `totalBytes` is the sum over every category.
/// Empty dictionary and 0 on failure.
- (void)storageUsageByFileTypeWithCompletion:
        (void (^)(NSDictionary *sizes, long long totalBytes))completion;

/// Cache usage per chat, biggest first, for a "top offenders" list. Each entry
/// is a dictionary with "chatId" (NSNumber, 0 for files not tied to a chat),
/// "title" (NSString, empty when the chat is unknown to us), "size" (bytes,
/// NSNumber) and "count" (NSNumber). `limit` caps how many chats TDLib reports
/// on; pass 0 for no per-chat breakdown at all and 32 for a usable screen.
/// This is the slow call - same warning as above.
- (void)storageUsageByChatWithLimit:(NSInteger)limit
                         completion:(void (^)(NSArray *chats))completion;

/// Cache used by exactly one chat, for a "Clear cache (N MB)" row in a chat
/// profile. `bytes` is 0 when that chat has nothing cached.
- (void)storageUsageForChat:(int64_t)chatId
                 completion:(void (^)(long long bytes, NSInteger files))completion;

/// TDLib's internal database statistics as one preformatted, multi-line
/// string, for a debug text view. Nil on failure.
- (void)databaseStatisticsWithCompletion:(void (^)(NSString *text))completion;

#pragma mark - clearing

/// Clear cached files of the given categories across every chat. `kinds` are
/// FileType names; pass nil or an empty array to clear every category this
/// client considers user media (this deliberately does not touch profile
/// photos or thumbnails, which would make the whole UI reload its avatars).
/// `freed` is the number of bytes actually deleted.
- (void)clearCacheCategories:(NSArray *)kinds
                  completion:(void (^)(long long freed))completion;

/// Clear everything TDLib is willing to delete, including stickers, wallpapers
/// and thumbnails. This is the destructive "Clear everything" row.
- (void)clearAllCacheWithCompletion:(void (^)(long long freed))completion;

/// Clear the cached files of one chat only.
- (void)clearCacheForChat:(int64_t)chatId
               completion:(void (^)(long long freed))completion;

/// The generic form, if a screen needs the full optimizeStorage control.
/// `maxBytes` is the cache size to shrink to, `ttlSeconds` the age above which
/// a file may go, `immunityDelaySeconds` how long a just-used file is spared -
/// pass -1 for "no limit of that sort" on any of the three, and 0 for the
/// immunity delay to spare nothing. `kinds` may be nil for all categories,
/// `excludedChatIds` an array of NSNumber chat ids never to touch.
- (void)optimizeStorageToSize:(long long)maxBytes
                   ttlSeconds:(NSInteger)ttlSeconds
         immunityDelaySeconds:(NSInteger)immunityDelaySeconds
                    fileTypes:(NSArray *)kinds
              excludedChatIds:(NSArray *)excludedChatIds
                   completion:(void (^)(long long freed))completion;

/// Apply the user's persisted "keep media for" and "maximum cache size"
/// choices in one call, which is what the launch-time and low-disk trim hook
/// wants. `maxBytes` and `ttlSeconds` are -1 for "no limit". `excludedChatIds`
/// is the persisted never-clear list, or nil.
- (void)applyCachePolicyMaxBytes:(long long)maxBytes
                      ttlSeconds:(NSInteger)ttlSeconds
                 excludedChatIds:(NSArray *)excludedChatIds
                      completion:(void (^)(long long freed))completion;

/// Drop one cached file from disk. The file stays available for re-download.
- (void)deleteCachedFile:(NSInteger)fileId;

#pragma mark - downloads

/// Stop a download in progress. `onlyIfPending` cancels only a download that
/// has not started transferring yet.
- (void)cancelDownloadFile:(NSInteger)fileId onlyIfPending:(BOOL)onlyIfPending;

/// Put a file on the account's download list ("Save to downloads" in a message
/// action sheet). `chatId`/`messageId` identify the message it came from.
- (void)addFileToDownloads:(NSInteger)fileId
                    inChat:(int64_t)chatId
                   message:(int64_t)messageId
                completion:(void (^)(BOOL ok))completion;

/// Empty the download list. Pass onlyActive or onlyCompleted to limit it; both
/// NO means everything.
- (void)clearDownloadsOnlyActive:(BOOL)onlyActive
                   onlyCompleted:(BOOL)onlyCompleted
                 deleteFromCache:(BOOL)deleteFromCache;

/// Pause or resume a single download.
- (void)setDownloadPaused:(BOOL)paused forFile:(NSInteger)fileId;

/// One page of the download list, for a Downloads screen. `query` may be nil
/// or empty for everything; `offset` is nil for the first page and otherwise
/// the "nextOffset" of the previous page.
/// Each entry: "fileId" (NSNumber), "chatId" (NSNumber), "messageId"
/// (NSNumber), "name" (NSString, best-effort file name, may be empty),
/// "size" (bytes, NSNumber - 0 when TDLib did not include the file object),
/// "downloaded" (bytes, NSNumber, same caveat), "isPaused"
/// (NSNumber BOOL), "isComplete" (NSNumber BOOL), "date" (NSNumber, unix time
/// it was added).
/// `counts` has "active", "paused" and "completed" (NSNumber). `nextOffset` is
/// an empty string when there is no further page.
- (void)downloadsWithQuery:(NSString *)query
                onlyActive:(BOOL)onlyActive
             onlyCompleted:(BOOL)onlyCompleted
                    offset:(NSString *)offset
                     limit:(NSInteger)limit
                completion:(void (^)(NSArray *files, NSDictionary *counts,
                                     NSString *nextOffset))completion;

#pragma mark - network usage

/// NOTE: telling TDLib which connection we are on is TGClient+Files's
/// -setNetworkType:; call it from the reachability observer or the figures
/// below are attributed to the wrong bucket.

/// Network usage since the counters were last reset. `entries` groups the
/// heterogeneous TDLib vector into readable rows, each with "kind" (a FileType
/// name, or @"calls"), "network" (@"wifi", @"mobile", @"roaming", @"other" or
/// @"none"), "sent" (bytes, NSNumber), "received" (bytes, NSNumber) and
/// "duration" (seconds, NSNumber, calls only - 0 otherwise).
/// `sinceDate` is the unix time the counters started. Pass onlyCurrent to get
/// usage of this launch only.
- (void)networkStatsOnlyCurrent:(BOOL)onlyCurrent
                     completion:(void (^)(NSArray *entries, NSInteger sinceDate))completion;

/// Sent/received totals for a network-usage screen header, already summed.
/// `byNetwork` maps @"wifi"/@"mobile"/@"roaming"/@"other"/@"none" to a
/// dictionary with "sent" and "received" in bytes.
- (void)networkTotalsOnlyCurrent:(BOOL)onlyCurrent
                      completion:(void (^)(long long sent, long long received,
                                           NSDictionary *byNetwork))completion;

/// Zero the network counters.
- (void)resetNetworkStats;

#pragma mark - auto-download

/// NOTE: the three suggested presets are TGClient+Files's
/// -autoDownloadPresetsWithCompletion:.

/// Apply auto-download settings for one network type. `settings` keys are
/// "enabled" (NSNumber BOOL), "maxPhoto", "maxVideo", "maxOther" (bytes,
/// NSNumber), "videoUploadBitrate" (NSNumber, 0 for server choice),
/// "preloadLargeVideos", "preloadNextAudio", "useLessDataForCalls" (NSNumber
/// BOOL); any key left out falls back to a safe default.
/// `type` is @"wifi", @"mobile", @"roaming", @"other" or @"none".
/// NOTE: TDLib has no getter for the settings currently in force, so the UI
/// has to mirror whatever it last set in NSUserDefaults.
- (void)setAutoDownloadSettings:(NSDictionary *)settings forNetworkType:(NSString *)type;

#pragma mark - autosave

/// Autosave-to-camera-roll settings. Each of `privateChats`, `groups` and
/// `channels` is a dictionary with "photos" (NSNumber BOOL), "videos"
/// (NSNumber BOOL) and "maxVideoBytes" (NSNumber).
- (void)autosaveSettingsWithCompletion:
        (void (^)(NSDictionary *privateChats, NSDictionary *groups,
                  NSDictionary *channels))completion;

/// Change autosave for one scope: @"private", @"groups" or @"channels".
- (void)setAutosavePhotos:(BOOL)photos
                   videos:(BOOL)videos
            maxVideoBytes:(long long)maxVideoBytes
                 forScope:(NSString *)scope;

/// Forget every per-chat autosave override.
- (void)clearAutosaveExceptions;

#pragma mark - file name helpers

/// The file name TDLib suggests when exporting a file into `directory`, or nil.
- (void)suggestedFileNameForFile:(NSInteger)fileId
                     inDirectory:(NSString *)directory
                      completion:(void (^)(NSString *name))completion;

/// NOTE: -mimeTypeForFileName:completion: and -cleanFileName:completion: are
/// TGClient+Files's.

@end

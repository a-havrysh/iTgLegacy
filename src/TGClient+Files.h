//
// TGClient+Files - file download and upload, the downloads list, byte-range
// streaming, thumbnails, auto-download settings and network/storage stats.
//
// Everything here returns plain Foundation objects on the main queue, and every
// completion may be nil.
//
// TDLib file ids are int32 and are NOT stable across sessions. Persist
// "remoteId" (the remote file id string) instead and turn it back into a local
// file id with resolveRemoteFileId:type:completion:.
//
// One shape is used throughout:
//
//   file = { "id"             : NSNumber, local int32 file id
//            "size"           : NSNumber, bytes on the server, 0 if unknown
//            "expectedSize"   : NSNumber, best guess while downloading
//            "path"           : NSString, local path, "" until something is on disk
//            "downloadedSize" : NSNumber, bytes on disk
//            "prefixSize"     : NSNumber, contiguous bytes from "downloadOffset"
//            "downloadOffset" : NSNumber
//            "canBeDownloaded": NSNumber BOOL
//            "canBeDeleted"   : NSNumber BOOL
//            "isDownloading"  : NSNumber BOOL, a download is running now
//            "isDownloaded"   : NSNumber BOOL, the whole file is on disk
//            "isUploading"    : NSNumber BOOL
//            "isUploaded"     : NSNumber BOOL
//            "uploadedSize"   : NSNumber
//            "remoteId"       : NSString, persistent remote file id
//            "uniqueId"       : NSString, persistent id shared by all sizes }
//
// Progress of any active transfer keeps arriving through TGClient's existing
// onFileProgress block; nothing here replaces it.
//
#import <CoreGraphics/CoreGraphics.h>
#import "TGClient.h"

/// FileType type names accepted by resolveRemoteFileId:type: and
/// uploadFileAtPath:type:priority:completion:.
extern NSString *const TGFileTypePhoto;
extern NSString *const TGFileTypeVideo;
extern NSString *const TGFileTypeDocument;
extern NSString *const TGFileTypeSticker;
extern NSString *const TGFileTypeAudio;
extern NSString *const TGFileTypeVoiceNote;
extern NSString *const TGFileTypeAnimation;
extern NSString *const TGFileTypeThumbnail;

/// NetworkType type names accepted by setNetworkType: and the auto-download
/// setters.
extern NSString *const TGNetworkTypeWiFi;
extern NSString *const TGNetworkTypeMobile;
extern NSString *const TGNetworkTypeMobileRoaming;
extern NSString *const TGNetworkTypeOther;
extern NSString *const TGNetworkTypeNone;

@interface TGClient (Files)

#pragma mark - file state

/// Current state of a file without starting a download. Completion gets a file
/// dictionary, or nil on error.
- (void)fileInfo:(NSInteger)fileId completion:(void (^)(NSDictionary *file))completion;

/// Turn a persisted remote file id back into a live local file id. `type` is
/// one of the TGFileType* constants. Completion gets a file dictionary, or nil.
- (void)resolveRemoteFileId:(NSString *)remoteId
					   type:(NSString *)type
				 completion:(void (^)(NSDictionary *file))completion;

#pragma mark - downloading

/// Start (or bump the priority of) a download without waiting for it to end.
/// Progress arrives on onFileProgress; `completion` fires as soon as TDLib has
/// accepted the request and gets the file's state at that moment.
/// `priority` is 1..32, 32 being the most urgent; pass 0 for the default of 1.
- (void)startDownloadingFile:(NSInteger)fileId
					priority:(NSInteger)priority
				  completion:(void (^)(NSDictionary *file))completion;

/// Stop a running download. Pass YES for `onlyIfPending` to cancel only if it
/// has not started transferring yet.
- (void)cancelDownloadOfFile:(NSInteger)fileId onlyIfPending:(BOOL)onlyIfPending;

/// Pause or resume one download that is in the downloads list.
- (void)setDownloadOfFile:(NSInteger)fileId paused:(BOOL)paused;

/// Delete the local copy of a file, keeping the remote id usable. The bubble
/// falls back to its thumbnail afterwards. Completion gets YES on success.
- (void)deleteCachedFile:(NSInteger)fileId completion:(void (^)(BOOL ok))completion;

/// File name a Save/Export flow should offer for this file. Completion gets
/// the name, or nil.
- (void)suggestedFileNameForFile:(NSInteger)fileId
					  completion:(void (^)(NSString *name))completion;

#pragma mark - downloads list

/// Add a message's file to the downloads list, which is what "Save to
/// Downloads" does. Completion gets the file dictionary, or nil on error.
- (void)addFileToDownloads:(NSInteger)fileId
					inChat:(int64_t)chatId
				 messageId:(int64_t)messageId
				  priority:(NSInteger)priority
				completion:(void (^)(NSDictionary *file))completion;

/// One page of the downloads list. `query` may be nil or empty for everything.
/// `offset` is nil for the first page, otherwise the "nextOffset" of the page
/// before. Completion gets, or nil on error:
///   { "downloads"      : NSArray of
///                        { "fileId"       : NSNumber
///                          "chatId"       : NSNumber
///                          "messageId"    : NSNumber
///                          "addDate"      : NSNumber unix seconds
///                          "completeDate" : NSNumber, 0 while incomplete
///                          "isPaused"     : NSNumber BOOL
///                          "fileName"     : NSString, may be empty
///                          "file"         : file dictionary as above }
///     "nextOffset"     : NSString, empty when this was the last page
///     "activeCount"    : NSNumber
///     "pausedCount"    : NSNumber
///     "completedCount" : NSNumber }
- (void)searchDownloadsWithQuery:(NSString *)query
					  onlyActive:(BOOL)onlyActive
				   onlyCompleted:(BOOL)onlyCompleted
						  offset:(NSString *)offset
						   limit:(NSInteger)limit
					  completion:(void (^)(NSDictionary *page))completion;

/// Clear the downloads list. Pass onlyActive or onlyCompleted to limit what
/// goes; both NO clears everything.
- (void)removeAllDownloadsOnlyActive:(BOOL)onlyActive
					   onlyCompleted:(BOOL)onlyCompleted
					 deleteFromCache:(BOOL)deleteFromCache;

#pragma mark - streaming and partial reads

/// Bytes already on disk in one run starting at `offset`. This is what an
/// AVAssetResourceLoader needs to know before it asks for a range.
/// Completion gets the count, 0 if nothing is there.
- (void)downloadedPrefixSizeForFile:(NSInteger)fileId
							 offset:(long long)offset
						 completion:(void (^)(long long size))completion;

/// Download exactly one byte range and wait for it. `limit` of 0 means "to the
/// end of the file". Completion gets the file dictionary once that range is on
/// disk, or nil on error. Use it as the fetch half of a streaming player.
- (void)downloadFile:(NSInteger)fileId
			  offset:(long long)offset
			   limit:(long long)limit
		  completion:(void (^)(NSDictionary *file))completion;

/// Read bytes out of a file through TDLib rather than off the filesystem, for
/// files whose path our sandbox cannot open. Completion gets the data, or nil.
- (void)readFile:(NSInteger)fileId
		  offset:(long long)offset
		   count:(long long)count
	  completion:(void (^)(NSData *data))completion;

/// Download a byte range if needed and hand the bytes back: the one call a
/// resource-loader delegate makes per requested range. Completion gets exactly
/// `count` bytes when possible, fewer at the end of the file, or nil on error.
- (void)streamFile:(NSInteger)fileId
			offset:(long long)offset
			 count:(long long)count
		completion:(void (^)(NSData *data))completion;

#pragma mark - thumbnails

/// Pick the smallest entry of a TDLib photo's "sizes" vector that still covers
/// `width` points at `scale`, falling back to the largest one available.
/// `sizes` is the raw vector out of a photo object. Returns, or nil:
///   { "fileId" : NSNumber, "width" : NSNumber, "height" : NSNumber,
///     "type"   : NSString, "path" : NSString (empty until downloaded),
///     "isDownloaded" : NSNumber BOOL }
- (NSDictionary *)bestPhotoSizeIn:(NSArray *)sizes
						 forWidth:(CGFloat)width
							scale:(CGFloat)scale;

/// Same shape as bestPhotoSizeIn:, for a TDLib "thumbnail" object as carried by
/// videos, documents, animations and stickers. Returns nil for formats this
/// device cannot decode (tgs, webm, webp, gif, mpeg4), so the caller can fall
/// back to the minithumbnail.
- (NSDictionary *)decodableThumbnail:(NSDictionary *)thumbnail;

/// Pick the right size out of a photo and download it. Completion gets the
/// local path, or nil. This is the whole "show a photo bubble" fetch.
- (void)downloadPhotoSizes:(NSArray *)sizes
				  forWidth:(CGFloat)width
					 scale:(CGFloat)scale
				completion:(void (^)(NSString *path, NSDictionary *size))completion;

/// Bytes of a TDLib "minithumbnail" object, ready for UIImage imageWithData:.
/// It is a tiny stripped JPEG that decodes instantly and is meant as the
/// blurred placeholder behind a bubble. Returns nil if there is none.
- (NSData *)minithumbnailData:(NSDictionary *)minithumbnail;

#pragma mark - uploading

/// Upload a local file ahead of sending a message with it, so the send is
/// instant. `type` is one of the TGFileType* constants. Completion gets the
/// file dictionary; watch onFileProgress for the upload bar.
- (void)uploadFileAtPath:(NSString *)path
					type:(NSString *)type
				priority:(NSInteger)priority
			  completion:(void (^)(NSDictionary *file))completion;

/// Cancel an upload started by uploadFileAtPath:. This does NOT cancel media
/// already attached to a message being sent; for that, delete the pending
/// message instead.
- (void)cancelUploadOfFile:(NSInteger)fileId;

#pragma mark - auto-download settings

/// Store auto-download settings for one network type. `settings` keys are
/// "enabled", "maxPhotoSize", "maxVideoSize", "maxOtherSize",
/// "videoUploadBitrate", "preloadLargeVideos", "preloadNextAudio",
/// "preloadStories", "lessDataForCalls"; missing keys take sensible defaults.
/// Read the presets with TGClient+Network's autoDownloadPresetsWithCompletion:.
/// `networkType` is one of the TGNetworkType* constants.
- (void)setAutoDownloadSettings:(NSDictionary *)settings
					forNetwork:(NSString *)networkType
					 completion:(void (^)(BOOL ok))completion;

#pragma mark - statistics

/// Zero the network counters.
- (void)resetNetworkStatistics;

/// Full storage breakdown per chat. Slow on old hardware because it walks every
/// cached file, so show a spinner and keep `chatLimit` small (20 is plenty).
/// Completion gets, or nil:
///   { "size"  : NSNumber total bytes
///     "count" : NSNumber total files
///     "chats" : NSArray, largest first, of
///               { "chatId" : NSNumber, 0 for files owned by no chat
///                 "title"  : NSString, empty if the chat is unknown
///                 "size"   : NSNumber
///                 "count"  : NSNumber
///                 "byType" : NSArray of { "type" : NSString TDLib FileType
///                                         name, "size", "count" } } }
- (void)storageStatisticsWithChatLimit:(NSInteger)chatLimit
							completion:(void (^)(NSDictionary *stats))completion;

#pragma mark - small helpers

/// File extension guessed from a MIME type, for the document row's icon and
/// label. Completion gets the extension without a dot, or nil.
- (void)fileExtensionForMimeType:(NSString *)mimeType
					  completion:(void (^)(NSString *extension))completion;

@end

// vim:ft=objc

//
// TGStickerThumbnailCache - scaled sticker thumbnails that outlive the panel.
//
// The sticker keyboard used to keep decoded thumbnails in an instance-owned
// dictionary, so closing the panel threw every decode away and a relaunch threw
// away the whole session. This cache is process wide and two tiered: an NSCache
// in front of TGDiskCache, keyed on the sticker's persistent remote unique id
// rather than the TDLib file id, which TGClient+Files.h says is not stable
// across sessions.
//
// Nothing decodes on the main thread. WebP is decoded straight to the wanted
// pixel size through libwebp's rescaler, so a 512x512 sticker never becomes a
// one megabyte bitmap on the way to a 64pt tile.
//
#import <UIKit/UIKit.h>

@interface TGStickerThumbnailCache : NSObject

/// Memory hit only, safe and immediate on the main thread. Nil when the
/// thumbnail is not decoded yet.
+ (UIImage *)cachedThumbnailForUniqueId:(NSString *)uniqueId side:(CGFloat)side;

/// Fetch a thumbnail scaled to fit `side` points. `uniqueId` may be empty, in
/// which case the result is memory cached but never written to disk, because
/// there would be no key that survives a relaunch. Completion runs on the main
/// queue, possibly before this returns when the image is already in memory.
///
/// Returns a token for cancelRequest:, or nil when nothing was started.
+ (id)thumbnailForFileId:(NSInteger)fileId
				uniqueId:(NSString *)uniqueId
					side:(CGFloat)side
			  completion:(void (^)(UIImage *image))completion;

/// Drop a caller's interest. When the last caller for a key goes away the
/// download is cancelled and any decode still queued is skipped.
+ (void)cancelRequest:(id)token;

+ (void)purgeMemory;

/// Where the thumbnails served since the last reset came from, for the PERF
/// line the panel logs when it finishes filling a screen.
+ (void)resetStatistics;
+ (NSString *)statisticsSummary;

@end

// vim:ft=objc

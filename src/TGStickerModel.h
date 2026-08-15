//
// TGStickerModel / TGStickerSetModel - typed, immutable value objects for one
// sticker and one sticker set.
//
// These replace the dictionaries documented at the top of TGClient+Stickers.h.
// +fromDictionary: accepts either of the two shapes a screen can be handed:
//
//   * the flattened shape TGClient+Stickers vends
//     ("fileId"/"setId"/"isAnimated"/"thumbId", "id"/"installed"/"isEmoji"/...)
//   * the raw TDLib object ("sticker"/"set_id"/"format"/"thumbnail",
//     "is_installed"/"sticker_type"/"size"/...)
//
// so a caller never needs to know which one it has, and never needs an
// isKindOfClass check of its own.
//
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface TGStickerModel : NSObject

/// File id of the sticker image. Non-zero for every model that exists; this is
/// what makes a sticker meaningful, so +fromDictionary: returns nil without it.
@property (nonatomic, readonly) NSInteger fileId;

/// Id of the owning set. 0 when the sticker arrived outside a set
/// (greeting stickers, some search results).
@property (nonatomic, readonly) int64_t setId;

/// The emoji this sticker stands for. Optional - nil when the producer sent an
/// empty string or nothing at all.
@property (nonatomic, readonly, copy) NSString *emoji;

/// Intrinsic size in points. 0 when the producer did not report it.
@property (nonatomic, readonly) CGFloat width;
@property (nonatomic, readonly) CGFloat height;

/// YES for anything that is not a plain .webp, i.e. .tgs and .webm.
@property (nonatomic, readonly) BOOL animated;

/// YES for .webm specifically, which this client cannot draw.
@property (nonatomic, readonly) BOOL video;

/// File id of the small thumbnail, or 0 when the sticker has none.
@property (nonatomic, readonly) NSInteger thumbId;

/// Custom-emoji id, or 0 when this sticker is not a custom emoji.
@property (nonatomic, readonly) int64_t customEmojiId;

/// YES when this sticker is a custom emoji (customEmojiId != 0).
@property (nonatomic, readonly) BOOL customEmoji;

/// Builds one sticker. Returns nil for anything that is not a dictionary or
/// carries no usable file id. Never returns a half-built object.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array of dictionaries, dropping entries that fail to build.
/// Returns an empty array for a nil or non-array input, never nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end


@interface TGStickerSetModel : NSObject

/// Id of the set. Non-zero for every model that exists.
@property (nonatomic, readonly) int64_t setId;

/// Display title. Optional - nil when the producer sent nothing.
@property (nonatomic, readonly, copy) NSString *title;

/// Short name used in t.me/addstickers/<name> links. Optional.
@property (nonatomic, readonly, copy) NSString *name;

/// Number of stickers in the whole set, which may exceed stickers.count when
/// only covers were sent. 0 when unknown and nothing was sent to count.
@property (nonatomic, readonly) NSInteger count;

/// The set is in the user's installed list.
@property (nonatomic, readonly) BOOL installed;

/// The set was installed once and then archived; it stays restorable.
@property (nonatomic, readonly) BOOL archived;

/// The set is an official Telegram pack.
@property (nonatomic, readonly) BOOL official;

/// The trending list has already shown this set. NO means "badge it as new".
@property (nonatomic, readonly) BOOL viewed;

/// The set holds custom emoji rather than stickers.
@property (nonatomic, readonly) BOOL emojiSet;

/// File id of the set thumbnail, or 0 when it has none. Fall back to the first
/// cover's thumbId when this is 0.
@property (nonatomic, readonly) NSInteger thumbId;

/// The few stickers to preview the set with. Never nil; empty when the producer
/// sent neither covers nor stickers.
@property (nonatomic, readonly, copy) NSArray *covers;

/// Every sticker in the set, but only for sets fetched whole
/// (stickerSetWithId:/stickerSetWithName:). Never nil; empty for list results.
@property (nonatomic, readonly, copy) NSArray *stickers;

/// First cover, or nil when the set has no preview stickers.
@property (nonatomic, readonly) TGStickerModel *firstCover;

/// Builds one set. Returns nil for anything that is not a dictionary or carries
/// no usable set id.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array of dictionaries, dropping entries that fail to build.
/// Returns an empty array for a nil or non-array input, never nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

// vim:ft=objc

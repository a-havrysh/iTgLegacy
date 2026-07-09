//
// TGIcons - the icon set, drawn rather than shipped as artwork.
//
// Drawing them means they follow TGTheme: line art with flat, and shaded
// glyphs with a highlight when skeuomorphic. It also means one source for
// every scale instead of a folder of PNGs per size.
//
#import <UIKit/UIKit.h>

@interface TGIcons : NSObject

+ (UIImage *)chats;        ///< tab bar
+ (UIImage *)contacts;
+ (UIImage *)settings;

+ (UIImage *)compose;      ///< new message
+ (UIImage *)send;
+ (UIImage *)attach;
+ (UIImage *)play;         ///< over video thumbnails
+ (UIImage *)document;
+ (UIImage *)pin;
+ (UIImage *)microphone;
+ (UIImage *)sticker;          ///< map marker

/// Delivery ticks, drawn the way Telegram draws them: two checks overlapping
/// into one mark, not two separate glyphs side by side.
+ (UIImage *)ticksWhite:(BOOL)white;

/// Circular avatar with initials, for chats and contacts without a photo.
+ (UIImage *)avatarWithInitials:(NSString *)initials
                           size:(CGFloat)size
                       colourId:(int64_t)colourId;

/// Drop the cache after a theme change.
+ (void)flush;

@end

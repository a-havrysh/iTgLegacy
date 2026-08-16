#import <UIKit/UIKit.h>

@interface TGLaunchSnapshot : NSObject

+ (BOOL)enabled;
+ (void)setEnabled:(BOOL)enabled;

+ (void)noteColdLaunchOffsetFromWindow:(UIWindow *)window;

+ (void)captureFromWindow:(UIWindow *)window;

+ (void)restoreShippedImage:(NSString *)reason;

+ (NSString *)describe;

@end

// vim:ft=objc

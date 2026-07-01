//
// TGTheme - skeuomorphic or flat, chosen by the user.
//
// The default follows the system it runs on: iOS 6 shipped skeuomorphic, iOS 7
// went flat, and an app that ignores that looks foreign on both. Either can be
// picked explicitly in Settings, because the point of running a modern client
// on old hardware is often that you prefer how the old one looked.
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGThemeStyle) {
    TGThemeStyleSkeuomorphic = 0,
    TGThemeStyleFlat         = 1
};

@interface TGTheme : NSObject

+ (instancetype)shared;

/// Persisted; defaults to skeuomorphic below iOS 7 and flat from iOS 7 on.
@property (nonatomic, assign) TGThemeStyle style;
@property (nonatomic, readonly) BOOL isFlat;

/// Posted when the style changes so open screens can restyle themselves.
extern NSString *const TGThemeChangedNotification;

#pragma mark - palette

- (UIColor *)barColour;             ///< navigation bar background
- (UIColor *)barTitleColour;
- (UIColor *)accentColour;          ///< buttons, links, unread badges
- (UIColor *)chatBackgroundColour;
- (UIColor *)bubbleMineColour;
- (UIColor *)bubbleTheirsColour;
- (UIColor *)bubbleBorderColour;    ///< clear when flat
- (UIColor *)listBackgroundColour;
- (UIColor *)primaryTextColour;
- (UIColor *)secondaryTextColour;

- (CGFloat)bubbleCornerRadius;
- (CGFloat)bubbleBorderWidth;       ///< 0 when flat

/// Apply the bar styling to a navigation bar.
- (void)styleNavigationBar:(UINavigationBar *)bar;

@end

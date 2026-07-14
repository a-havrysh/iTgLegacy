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

#pragma mark - imported themes

/// Name of the imported theme in use, or nil for the built-in styles.
@property (nonatomic, readonly) NSString *importedName;
/// YES when the imported theme calls itself dark.
@property (nonatomic, readonly) BOOL isDark;

/// Adopt a theme file made for an official client (.tgios-theme, .attheme).
/// Returns NO if the file cannot be read. Persists across launches.
- (BOOL)importThemeAtPath:(NSString *)path;

/// Drop the imported theme and go back to the built-in style.
- (void)clearImportedTheme;

/// Theme files the app can see: everything in Documents, plus anything
/// received in a chat and saved there. Paths.
+ (NSArray *)availableThemeFiles;

/// Message text size in points. Persisted; 15 is the default.
@property (nonatomic, assign) CGFloat messageFontSize;

#pragma mark - wallpaper

/// The chat wallpaper, or nil for a plain background. Either a picture the
/// user chose or one carried by an imported theme.
- (UIImage *)wallpaper;

/// Adopt a picture as the wallpaper; nil clears it. Persisted.
- (void)setWallpaperImage:(UIImage *)image;

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
- (UIColor *)inputBarColour;        ///< the composer strip at the bottom

- (CGFloat)bubbleCornerRadius;
- (CGFloat)bubbleBorderWidth;       ///< 0 when flat

/// Style a table cell so an imported theme reaches the settings screens too;
/// grouped tables draw white cells otherwise.
- (void)styleCell:(UITableViewCell *)cell;

/// Apply the bar styling to a navigation bar.
- (void)styleNavigationBar:(UINavigationBar *)bar;
/// Same for the tab bar, which an imported theme should not leave behind.
- (void)styleTabBar:(UITabBar *)bar;

@end

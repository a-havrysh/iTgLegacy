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
    TGThemeStyleFlat         = 1,
    TGThemeStyleDark         = 2
};

@interface TGTheme : NSObject

+ (instancetype)shared;

/// Persisted; defaults to skeuomorphic below iOS 7 and flat from iOS 7 on.
@property (nonatomic, assign) TGThemeStyle style;
/// YES for the flat style and for dark, which is flat drawn on dark surfaces.
@property (nonatomic, readonly) BOOL isFlat;

/// Posted when the style changes so open screens can restyle themselves.
extern NSString *const TGThemeChangedNotification;

#pragma mark - imported themes

/// Name of the imported theme in use, or nil for the built-in styles.
@property (nonatomic, readonly) NSString *importedName;
/// YES for the built-in dark style, and when an imported theme calls itself dark.
@property (nonatomic, readonly) BOOL isDark;
/// YES only for the built-in dark style: an imported theme brings its own
/// colours and must not be second-guessed by the dark defaults.
@property (nonatomic, readonly) BOOL isDarkStyle;

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
- (UIColor *)inputBarColour;
- (UIColor *)timeColour;            ///< the stamp in the corner of a bubble
- (UIColor *)cellDetailColour;      ///< the value on the right of a settings row
- (UIColor *)sectionHeaderColour;   ///< the caption above a group of rows
- (UIColor *)profileHeaderColour;   ///< the block behind a profile picture

#pragma mark - media and file blocks

- (UIColor *)fileTileColour;        ///< the square behind a file glyph
- (UIColor *)mediaCircleColour;     ///< the disc under a file glyph or play arrow
- (UIColor *)fileNameColour;        ///< the file name in a document block
- (UIColor *)fileMetaColour;        ///< "6.5 KB PNG" under it
- (UIColor *)mediaStampColour;      ///< the plate carrying the time over a picture

#pragma mark - chat list

- (UIColor *)badgeColour;           ///< unread count
- (UIColor *)mutedBadgeColour;      ///< the same count in a muted chat
- (UIColor *)typingColour;          ///< "typing..." in place of the preview
- (UIColor *)onlineColour;          ///< the dot on an avatar
- (UIColor *)separatorColour;       ///< hairlines between rows and around bars

#pragma mark - service messages

- (UIColor *)serviceBubbleColour;   ///< the plate behind "X joined the group"
- (UIColor *)serviceTextColour;

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

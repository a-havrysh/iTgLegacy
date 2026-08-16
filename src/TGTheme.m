#import "TGTheme.h"
#import "TGThemeFile.h"

NSString *const TGThemeChangedNotification = @"TGThemeChanged";

static NSString *const kStyleKey  = @"themeStyle";
static NSString *const kImportKey = @"themeImportPath";
static NSString *const kFontKey   = @"messageFontSize";

@implementation TGTheme {
	NSDictionary *_imported;
	UIImage *_wallpaper;
}

+ (instancetype)shared {
	static TGTheme *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[TGTheme alloc] init]; });
	return s;
}

- (id)init {
	self = [super init];
	if (!self)
		return nil;

	_style = TGThemeStyleSkeuomorphic;
	NSString *imported = [NSUserDefaults.standardUserDefaults stringForKey:kImportKey];
	if (imported.length)
		[self loadImportedTheme:[TGTheme pathInDocuments:imported]];
	return self;
}

- (CGFloat)messageFontSize {
	CGFloat stored = [NSUserDefaults.standardUserDefaults floatForKey:kFontKey];
	return stored > 0 ? MIN(60.0f, stored) : 16.0f;
}

- (void)setMessageFontSize:(CGFloat)size {
	[NSUserDefaults.standardUserDefaults setFloat:size forKey:kFontKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
}

#pragma mark - imported themes

- (BOOL)importThemeAtPath:(NSString *)path {
	if (![self loadImportedTheme:path])
		return NO;
	// Only the file name: the container path changes on every reinstall, and
	// an absolute path stored across one points at a directory that is gone.
	[NSUserDefaults.standardUserDefaults setObject:path.lastPathComponent
											forKey:kImportKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
	return YES;
}

+ (NSString *)pathInDocuments:(NSString *)name {
	NSString *documents = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	return [documents stringByAppendingPathComponent:name.lastPathComponent];
}

- (BOOL)loadImportedTheme:(NSString *)path {
	NSString *name = nil;
	NSDictionary *palette = [TGThemeFile paletteFromFile:path name:&name];
	if (!palette)
		return NO;
	_imported = palette;
	_importedName = name;
	return YES;
}

- (void)clearImportedTheme {
	_imported = nil;
	_importedName = nil;
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kImportKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
}

- (BOOL)isDark {
	if (_imported)
		return [_imported[@"isDark"] boolValue];
	return _style == TGThemeStyleDark;
}

+ (NSArray *)availableThemeFiles {
	NSString *documents = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	NSMutableArray *found = [NSMutableArray array];
	for (NSString *entry in [[NSFileManager defaultManager]
			contentsOfDirectoryAtPath:documents error:nil]){
		NSString *path = [documents stringByAppendingPathComponent:entry];
		if ([TGThemeFile handlesFile:path])
			[found addObject:path];
	}
	return found;
}

/// An imported colour wins over the built-in style; anything the file did not
/// define falls through, so a partial theme still works.
- (UIColor *)importedColour:(NSString *)key {
	return _imported[key];
}

#pragma mark - style state

- (void)setStyle:(TGThemeStyle)style {
	if (_style == style)
		return;
	_style = style;
	[NSUserDefaults.standardUserDefaults setInteger:style forKey:kStyleKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
}

/// Dark is flat drawn on dark surfaces, so everything that asks "flat?" to
/// decide whether to draw a bevel gets the same answer for both.
- (BOOL)isFlat {
	return _style == TGThemeStyleFlat || _style == TGThemeStyleDark;
}

/// The built-in dark style, which an imported theme overrides colour by colour.
- (BOOL)isDarkStyle {
	return _style == TGThemeStyleDark && _imported == nil;
}

#pragma mark - wallpaper

- (NSString *)wallpaperPath {
	NSString *documents = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	return [documents stringByAppendingPathComponent:@"wallpaper.jpg"];
}

- (UIImage *)wallpaper {
	if (!_wallpaper)
		_wallpaper = [UIImage imageWithContentsOfFile:[self wallpaperPath]];
	return _wallpaper;
}

// Scaled down first: a full camera frame behind every chat is megabytes of
// memory on a device that has 512.
static UIImage *TGThemeScaledWallpaper(UIImage *image) {
	CGFloat maxSide = 640;
	CGFloat scale = MIN(1.0f, maxSide / MAX(image.size.width, image.size.height));
	if (scale >= 1.0f)
		return image;
	CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
	UIGraphicsBeginImageContextWithOptions(size, YES, 1);
	[image drawInRect:CGRectMake(0, 0, size.width, size.height)];
	UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return scaled;
}

- (void)setWallpaperImage:(UIImage *)image {
	NSString *path = [self wallpaperPath];
	if (image){
		image = TGThemeScaledWallpaper(image);
		[UIImageJPEGRepresentation(image, 0.8f) writeToFile:path atomically:YES];
	} else {
		[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	}
	_wallpaper = image;
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
}

#pragma mark - palette

static UIColor *rgb(int r, int g, int b) {
	return [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:1.0f];
}

#define TG_BAR_BLUE       rgb(0x54, 0x7A, 0xA1)
#define TG_ACTION_BLUE    rgb(0x07, 0x79, 0xD0)
#define TG_BADGE_STEEL    rgb(0x92, 0x9F, 0xB0)
#define TG_BUBBLE_OUT     rgb(0xD3, 0xFB, 0xB1)
#define TG_BUBBLE_IN      rgb(0xFB, 0xFB, 0xFB)
#define TG_LINEN          rgb(0xDB, 0xE4, 0xED)
#define TG_SETTINGS_GROUND rgb(0xC9, 0xD1, 0xDB)
#define TG_INPUT_PANEL    rgb(0xE7, 0xEB, 0xF0)
#define TG_MUTE_GREY      rgb(0xBA, 0xBA, 0xBA)
#define TG_PRESENCE_TEXT  rgb(0x77, 0x86, 0x98)
#define TG_GRAY_LIGHT3    rgb(0xF7, 0xF7, 0xF7)
#define TG_STEEL_LIGHT1   rgb(0xED, 0xEE, 0xF0)
#define TG_HAIRLINE       rgb(0xE5, 0xE5, 0xE5)
#define TG_TEXT_PRIMARY   rgb(0x11, 0x11, 0x11)
#define TG_TEXT_SECONDARY rgb(0x88, 0x88, 0x88)
#define TG_MESSAGE_DATE   rgb(0x23, 0x2D, 0x37)
#define TG_SETTINGS_VALUE rgb(0x35, 0x65, 0x96)
#define TG_FOOTER_CAPTION rgb(0x69, 0x74, 0x87)
#define TG_ACTION_TEXT    rgb(0x53, 0x6C, 0x8C)
#define TG_ATTACH_TITLE   rgb(0x62, 0x76, 0x8A)
#define TG_ATTACH_META    rgb(0x72, 0x87, 0x9B)

#define TG_DARK_BAR       rgb(0x19, 0x19, 0x19)
#define TG_DARK_LIST      rgb(0x1F, 0x1F, 0x1F)
#define TG_DARK_LINEN     rgb(0x53, 0x58, 0x62)
#define TG_DARK_EDGE      rgb(0x0C, 0x0C, 0x0C)
#define TG_DARK_SECONDARY rgb(0x99, 0x99, 0x99)
#define TG_DARK_STAMP     rgb(0xC9, 0xDC, 0xF2)
#define TG_DARK_BUBBLE_OUT rgb(0x16, 0x96, 0x00)

- (UIColor *)barColour {
	UIColor *imported = [self importedColour:@"bar"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_DARK_BAR;
	return self.isFlat ? TG_GRAY_LIGHT3 : TG_BAR_BLUE;
}

- (UIColor *)barTitleColour {
	UIColor *imported = [self importedColour:@"barTitle"];
	if (imported) return imported;
	if (self.isDarkStyle) return [UIColor whiteColor];
	return self.isFlat ? TG_TEXT_PRIMARY : [UIColor whiteColor];
}

- (UIColor *)accentColour {
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;
	return TG_ACTION_BLUE;
}

- (UIColor *)chatBackgroundColour {
	UIColor *imported = [self importedColour:@"chatBackground"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_DARK_LINEN;
	if (self.isFlat) return TG_STEEL_LIGHT1;
	static UIColor *linen = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		UIImage *tile = [UIImage imageNamed:@"Linen.png"];
		if (tile)
			linen = [UIColor colorWithPatternImage:tile];
	});
	return linen ?: TG_LINEN;
}

- (UIColor *)bubbleMineColour {
	UIColor *imported = [self importedColour:@"bubbleMine"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_DARK_BUBBLE_OUT;
	return TG_BUBBLE_OUT;
}

- (UIColor *)bubbleTheirsColour {
	UIColor *imported = [self importedColour:@"bubbleTheirs"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_DARK_LIST;
	return TG_BUBBLE_IN;
}

- (UIColor *)bubbleBorderColour {
	if (self.isDark)
		return [UIColor colorWithWhite:1.0f alpha:52.0f / 255.0f];
	return [UIColor colorWithRed:0x01 / 255.0f green:0x29 / 255.0f
							blue:0x68 / 255.0f alpha:52.0f / 255.0f];
}

- (UIColor *)listBackgroundColour {
	UIColor *imported = [self importedColour:@"listBackground"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_DARK_LIST;
	return [UIColor whiteColor];
}

- (UIColor *)primaryTextColour {
	UIColor *imported = [self importedColour:@"primaryText"];
	if (imported) return imported;
	if (self.isDarkStyle) return [UIColor whiteColor];
	return TG_TEXT_PRIMARY;
}

- (UIColor *)secondaryTextColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_DARK_SECONDARY;
	return TG_TEXT_SECONDARY;
}

- (UIColor *)timeColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_DARK_STAMP : TG_MESSAGE_DATE;
}

- (UIColor *)cellDetailColour {
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_SETTINGS_VALUE;
}

- (UIColor *)sectionHeaderColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	return imported ?: TG_FOOTER_CAPTION;
}

- (UIColor *)profileHeaderColour {
	UIColor *imported = [self importedColour:@"bar"];
	if (imported)
		return imported;
	if (self.isDark)
		return TG_DARK_LIST;
	static UIColor *lines = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		UIImage *tile = [UIImage imageNamed:@"SettingsBackground.png"];
		if (tile)
			lines = [UIColor colorWithPatternImage:tile];
	});
	return lines ?: TG_SETTINGS_GROUND;
}

- (UIColor *)inputBarColour {
	if (_imported)
		return [self barColour];
	if (self.isDarkStyle)
		return TG_DARK_BAR;
	return self.isFlat ? TG_GRAY_LIGHT3 : TG_INPUT_PANEL;
}

#pragma mark - media and file blocks

- (UIColor *)fileTileColour {
	return self.isDark ? TG_DARK_LIST : [UIColor whiteColor];
}

- (UIColor *)mediaCircleColour {
	return [UIColor colorWithRed:0x60 / 255.0f green:0x78 / 255.0f
							blue:0x99 / 255.0f alpha:140.0f / 255.0f];
}

- (UIColor *)fileNameColour {
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_ATTACH_TITLE;
}

- (UIColor *)fileMetaColour {
	return self.isDark ? TG_DARK_SECONDARY : TG_ATTACH_META;
}

/// The stamp over a picture has to read against whatever the picture is, so it
/// gets a plate rather than a colour.
- (UIColor *)mediaStampColour {
	return [UIColor colorWithWhite:0.0f alpha:0.35f];
}

#pragma mark - chat list

- (UIColor *)badgeColour {
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_BADGE_STEEL;
}

- (UIColor *)mutedBadgeColour {
	return TG_MUTE_GREY;
}

- (UIColor *)typingColour {
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_ACTION_TEXT;
}

- (UIColor *)onlineColour {
	return TG_PRESENCE_TEXT;
}

- (UIColor *)separatorColour {
	if (_imported)
		return [self bubbleBorderColour];
	return self.isDark ? TG_DARK_EDGE : TG_HAIRLINE;
}

#pragma mark - service messages

- (UIColor *)serviceBubbleColour {
	return self.isDark ? [UIColor colorWithWhite:1.0f alpha:0.29f]
							: [UIColor colorWithWhite:0.0f alpha:0.29f];
}

- (UIColor *)serviceTextColour {
	return self.isDark ? [UIColor colorWithWhite:1.0f alpha:0.85f]
							: [UIColor whiteColor];
}

#pragma mark - bubble metrics

- (CGFloat)bubbleCornerRadius {
	return self.isFlat ? 12.0f : 10.0f;
}

- (CGFloat)bubbleBorderWidth {
	return 1.0f;
}

#pragma mark - styling views

- (void)styleCell:(UITableViewCell *)cell {
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.textColor = [self cellDetailColour];

	if (!_imported && !self.isDarkStyle){
		cell.textLabel.textColor = [UIColor blackColor];
		return;
	}
	cell.backgroundColor = [self listBackgroundColour];
	cell.textLabel.textColor = [self primaryTextColour];
	// A selection flash of white would be worse than none.
	UIView *selected = [[UIView alloc] init];
	selected.backgroundColor = (!_imported && self.isDarkStyle)
			? TG_DARK_EDGE : [self bubbleTheirsColour];
	cell.selectedBackgroundView = selected;
}

- (void)styleTabBar:(UITabBar *)bar {
	if (!bar || (!_imported && !self.isDarkStyle))
		return;
	if ([bar respondsToSelector:@selector(setBarTintColor:)]){
		bar.translucent = NO;
		bar.barTintColor = [self barColour];
		bar.tintColor = [self accentColour];
	} else {
		bar.tintColor = [self barColour];
	}
}

- (void)styleNavigationBar:(UINavigationBar *)bar {
	if (!bar)
		return;

	// barTintColor is iOS 7; on iOS 6 the bar colour is tintColor itself.
	// A dark bar needs light status-bar glyphs, which is what barStyle decides.
	bar.barStyle = self.isDark ? UIBarStyleBlack : UIBarStyleDefault;

	if ([bar respondsToSelector:@selector(setBarTintColor:)]){
		// A translucent bar blends with whatever is behind it, which turns a
		// dark bar pale. Anything dark gets an opaque bar.
		bar.translucent = (_imported == nil && !self.isDarkStyle);
		bar.barTintColor = [self barColour];
		bar.tintColor = self.isFlat ? [self accentColour] : [UIColor whiteColor];
		bar.titleTextAttributes = @{ NSForegroundColorAttributeName : [self barTitleColour] };
	} else {
		bar.tintColor = self.isFlat ? [self accentColour] : [UIColor whiteColor];
		bar.titleTextAttributes = @{ UITextAttributeTextColor : [self barTitleColour] };
	}

	if (!self.isFlat && _imported == nil)
		[self applyCarvedBarBackground:bar];

	[self styleBackButton];
}

- (void)applyCarvedBarBackground:(UINavigationBar *)bar {
	UIImage *background = [UIImage imageNamed:@"NavBarBackground"];
	if ([background respondsToSelector:@selector(resizableImageWithCapInsets:)])
		background = [background resizableImageWithCapInsets:UIEdgeInsetsMake(0, 8, 0, 8)];
	if (background && [bar respondsToSelector:@selector(setBackgroundImage:forBarMetrics:)])
		[bar setBackgroundImage:background forBarMetrics:UIBarMetricsDefault];
}

/// The back button is created by UINavigationController itself, so it can only
/// be reached through the appearance proxy rather than per screen.
- (void)styleBackButton {
	// The appearance proxy forwards selectors instead of implementing them, so
	// respondsToSelector: answers NO for every one of them and must not gate
	// these calls. They have all existed since iOS 5.
	UIBarButtonItem *proxy = [UIBarButtonItem appearance];

	if (self.isFlat || _imported != nil){
		[proxy setBackButtonBackgroundImage:nil forState:UIControlStateNormal
								 barMetrics:UIBarMetricsDefault];
		[proxy setBackButtonBackgroundImage:nil forState:UIControlStateHighlighted
								 barMetrics:UIBarMetricsDefault];
		return;
	}

	UIImage *normal = [[UIImage imageNamed:@"BackButton"]
			stretchableImageWithLeftCapWidth:15 topCapHeight:0];
	UIImage *pressed = [[UIImage imageNamed:@"BackButton_Pressed"]
			stretchableImageWithLeftCapWidth:15 topCapHeight:0];
	if (normal)
		[proxy setBackButtonBackgroundImage:normal forState:UIControlStateNormal
								 barMetrics:UIBarMetricsDefault];
	if (pressed)
		[proxy setBackButtonBackgroundImage:pressed forState:UIControlStateHighlighted
								 barMetrics:UIBarMetricsDefault];

	NSDictionary *titleAttributes = nil;
	if (NSFoundationVersionNumber > 993.00)
		titleAttributes = @{ NSForegroundColorAttributeName : [UIColor whiteColor] };
	else
		titleAttributes = @{ UITextAttributeTextColor : [UIColor whiteColor] };
	[proxy setTitleTextAttributes:titleAttributes forState:UIControlStateNormal];
}

@end

// vim:ft=objc

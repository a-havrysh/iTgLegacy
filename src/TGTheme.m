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

	NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:kStyleKey];
	if (stored){
		_style = (TGThemeStyle)stored.integerValue;
	} else {
		// NSFoundationVersionNumber_iOS_6_1 is 993.00; anything above is iOS 7+
		_style = (NSFoundationVersionNumber > 993.00)
			? TGThemeStyleFlat : TGThemeStyleSkeuomorphic;
	}
	NSString *imported = [NSUserDefaults.standardUserDefaults stringForKey:kImportKey];
	if (imported.length)
		[self loadImportedTheme:[TGTheme pathInDocuments:imported]];
	return self;
}

- (CGFloat)messageFontSize {
	CGFloat stored = [NSUserDefaults.standardUserDefaults floatForKey:kFontKey];
	return stored > 0 ? stored : 15.0f;
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
	return [_imported[@"isDark"] boolValue];
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

- (void)setStyle:(TGThemeStyle)style {
	if (_style == style)
		return;
	_style = style;
	[NSUserDefaults.standardUserDefaults setInteger:style forKey:kStyleKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
}

- (BOOL)isFlat {
	return _style == TGThemeStyleFlat;
}

- (void)styleCell:(UITableViewCell *)cell {
	if (!_imported)
		return;
	cell.backgroundColor = [self listBackgroundColour];
	cell.textLabel.textColor = [self primaryTextColour];
	cell.detailTextLabel.textColor = [self secondaryTextColour];
	// A selection flash of white would be worse than none.
	UIView *selected = [[UIView alloc] init];
	selected.backgroundColor = [self bubbleTheirsColour];
	cell.selectedBackgroundView = selected;
}

- (void)styleTabBar:(UITabBar *)bar {
	if (!bar || !_imported)
		return;
	if ([bar respondsToSelector:@selector(setBarTintColor:)]){
		bar.translucent = NO;
		bar.barTintColor = [self barColour];
		bar.tintColor = [self accentColour];
	} else {
		bar.tintColor = [self barColour];
	}
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

- (void)setWallpaperImage:(UIImage *)image {
	NSString *path = [self wallpaperPath];
	if (image){
		// Scaled down first: a full camera frame behind every chat is megabytes
		// of memory on a device that has 512.
		CGFloat maxSide = 640;
		CGFloat scale = MIN(1.0f, maxSide / MAX(image.size.width, image.size.height));
		if (scale < 1.0f){
			CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
			UIGraphicsBeginImageContextWithOptions(size, YES, 1);
			[image drawInRect:CGRectMake(0, 0, size.width, size.height)];
			image = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
		}
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

- (UIColor *)barColour {
	UIColor *imported = [self importedColour:@"bar"];
	if (imported) return imported;

	return self.isFlat ? rgb(247, 247, 247) : rgb(64, 122, 173);
}

- (UIColor *)barTitleColour {
	UIColor *imported = [self importedColour:@"barTitle"];
	if (imported) return imported;

	return self.isFlat ? rgb(20, 20, 20) : [UIColor whiteColor];
}

- (UIColor *)accentColour {
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;

	return self.isFlat ? rgb(0, 122, 255) : rgb(38, 92, 140);
}

- (UIColor *)chatBackgroundColour {
	UIColor *imported = [self importedColour:@"chatBackground"];
	if (imported) return imported;

	return self.isFlat ? rgb(255, 255, 255) : rgb(217, 222, 212);
}

- (UIColor *)bubbleMineColour {
	UIColor *imported = [self importedColour:@"bubbleMine"];
	if (imported) return imported;

	return self.isFlat ? rgb(0, 122, 255) : rgb(217, 245, 194);
}

- (UIColor *)bubbleTheirsColour {
	UIColor *imported = [self importedColour:@"bubbleTheirs"];
	if (imported) return imported;

	return self.isFlat ? rgb(233, 233, 235) : [UIColor whiteColor];
}

- (UIColor *)bubbleBorderColour {
	// A drawn edge is what makes a skeuomorphic bubble sit on the surface;
	// flat bubbles have none at all.
	return self.isFlat ? [UIColor clearColor] : [UIColor colorWithWhite:0.0f alpha:0.12f];
}

- (UIColor *)listBackgroundColour {
	UIColor *imported = [self importedColour:@"listBackground"];
	if (imported) return imported;

	return [UIColor whiteColor];
}

- (UIColor *)primaryTextColour {
	UIColor *imported = [self importedColour:@"primaryText"];
	if (imported) return imported;

	return rgb(20, 20, 20);
}

- (UIColor *)secondaryTextColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;

	return rgb(120, 120, 125);
}

/// An imported theme rarely names the composer separately, so it takes the
/// bar colour - which is what the official clients do with it anyway.
- (UIColor *)inputBarColour {
	if (_imported)
		return [self barColour];
	return [UIColor colorWithWhite:0.93f alpha:1.0f];
}

- (CGFloat)bubbleCornerRadius {
	return self.isFlat ? 18.0f : 14.0f;
}

- (CGFloat)bubbleBorderWidth {
	return self.isFlat ? 0.0f : 1.0f;
}

- (void)styleNavigationBar:(UINavigationBar *)bar {
	if (!bar)
		return;

	// barTintColor is iOS 7; on iOS 6 the bar colour is tintColor itself.
	if ([bar respondsToSelector:@selector(setBarTintColor:)]){
		// A translucent bar blends with whatever is behind it, which turns an
		// imported dark bar pale. Imported themes get an opaque bar.
		bar.translucent = (_imported == nil);
		bar.barTintColor = [self barColour];
		bar.tintColor = _imported ? [self accentColour]
								  : (self.isFlat ? [self accentColour] : [UIColor whiteColor]);
		bar.titleTextAttributes = @{ NSForegroundColorAttributeName : [self barTitleColour] };
	} else {
		bar.tintColor = [self barColour];
		bar.titleTextAttributes = @{ UITextAttributeTextColor : [self barTitleColour] };
	}
}

@end

// vim:ft=objc

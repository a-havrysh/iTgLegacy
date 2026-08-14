#import "TGThemeFile.h"

@interface TGThemeFile ()
+ (NSDictionary *)paletteFromIOSTheme:(NSData *)data name:(NSString **)name;
+ (NSDictionary *)paletteFromAndroidTheme:(NSData *)data;
@end

@implementation TGThemeFile

+ (BOOL)handlesFile:(NSString *)path {
	if (![path isKindOfClass:NSString.class] || !path.length)
		return NO;
	BOOL directory = NO;
	if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && directory)
		return NO;
	NSString *ext = path.pathExtension.lowercaseString;
	return [ext isEqualToString:@"tgios-theme"] || [ext isEqualToString:@"attheme"] ||
		   [ext isEqualToString:@"theme"];
}

+ (NSDictionary *)paletteFromFile:(NSString *)path name:(NSString **)name {
	if (![path isKindOfClass:NSString.class] || !path.length)
		return nil;

	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data.length)
		return nil;

	if (name)
		*name = [path.lastPathComponent stringByDeletingPathExtension];

	// A wallpaper-carrying export is a zip, which this does not unpack.
	const unsigned char *bytes = data.bytes;
	if (data.length > 4 && bytes[0] == 'P' && bytes[1] == 'K'){
		NSLog(@"TGThemeFile: %@ is a zipped theme, not supported",
				path.lastPathComponent);
		return nil;
	}

	NSUInteger probe = 0;
	while (probe < data.length && (bytes[probe] == ' ' || bytes[probe] == '\t' ||
			bytes[probe] == '\r' || bytes[probe] == '\n' || bytes[probe] == 0xEF ||
			bytes[probe] == 0xBB || bytes[probe] == 0xBF))
		probe++;
	BOOL looksLikeJSON = (probe < data.length && (bytes[probe] == '{' || bytes[probe] == '['));

	NSDictionary *palette = looksLikeJSON ? [self paletteFromIOSTheme:data name:name]
										  : [self paletteFromAndroidTheme:data];
	if (!palette)
		palette = looksLikeJSON ? [self paletteFromAndroidTheme:data]
								: [self paletteFromIOSTheme:data name:name];
	if (!palette)
		NSLog(@"TGThemeFile: %@ has no colours this app can use",
				path.lastPathComponent);
	return palette;
}

#pragma mark - Telegram for iOS (.tgios-theme)

/// "ffffff", "#ffffff", "ffffffcc" with alpha, or a gradient "aabbcc-ddeeff",
/// of which the first stop is taken - nothing here paints gradients.
static UIColor *TGColourFromHex(id value) {
	if ([value isKindOfClass:NSNumber.class]){
		uint32_t packed = (uint32_t)[(NSNumber *)value longLongValue];
		CGFloat alpha = ((packed >> 24) & 0xFF) / 255.0f;
		return [UIColor colorWithRed:((packed >> 16) & 0xFF) / 255.0f
							   green:((packed >> 8) & 0xFF) / 255.0f
								blue:(packed & 0xFF) / 255.0f
							   alpha:(alpha == 0 ? 1.0f : alpha)];
	}
	if (![value isKindOfClass:NSString.class])
		return nil;

	NSString *hex = [[(NSString *)value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]]
			stringByReplacingOccurrencesOfString:@"#" withString:@""];
	NSRange dash = [hex rangeOfString:@"-"];
	if (dash.location != NSNotFound)
		hex = [hex substringToIndex:dash.location];
	if (hex.length == 3){
		NSMutableString *expanded = [NSMutableString stringWithCapacity:6];
		for (NSUInteger i = 0; i < 3; i++){
			NSString *digit = [hex substringWithRange:NSMakeRange(i, 1)];
			[expanded appendString:digit];
			[expanded appendString:digit];
		}
		hex = expanded;
	}
	if (hex.length != 6 && hex.length != 8)
		return nil;

	NSScanner *scanner = [NSScanner scannerWithString:[hex substringToIndex:6]];
	unsigned int rgb = 0;
	if (![scanner scanHexInt:&rgb] || ![scanner isAtEnd])
		return nil;

	CGFloat alpha = 1.0f;
	if (hex.length == 8){
		unsigned int a = 255;
		[[NSScanner scannerWithString:[hex substringFromIndex:6]] scanHexInt:&a];
		alpha = a / 255.0f;
	}
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0f
						   green:((rgb >> 8) & 0xFF) / 255.0f
							blue:(rgb & 0xFF) / 255.0f
						   alpha:alpha];
}

static BOOL TGPaletteLooksDark(NSDictionary *palette) {
	NSArray *order = [NSArray arrayWithObjects:@"listBackground", @"chatBackground",
			@"bar", nil];
	for (NSString *key in order){
		UIColor *colour = [palette objectForKey:key];
		if (![colour isKindOfClass:UIColor.class])
			continue;
		CGFloat r = 0, g = 0, b = 0, a = 0;
		if ([colour respondsToSelector:@selector(getRed:green:blue:alpha:)] &&
				[colour getRed:&r green:&g blue:&b alpha:&a])
			return (0.299f * r + 0.587f * g + 0.114f * b) < 0.5f;
		CGFloat white = 0;
		if ([colour getWhite:&white alpha:&a])
			return white < 0.5f;
	}
	return NO;
}

/// Follow a dotted key path, tolerating a missing branch.
static id TGDig(NSDictionary *root, NSString *path) {
	id node = root;
	for (NSString *key in [path componentsSeparatedByString:@"."]){
		if (![node isKindOfClass:NSDictionary.class])
			return nil;
		node = node[key];
	}
	return node;
}

+ (NSDictionary *)paletteFromIOSTheme:(NSData *)data name:(NSString **)name {
	NSError *err = nil;
	id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
	if (![json isKindOfClass:NSDictionary.class]){
		NSLog(@"TGThemeFile: not JSON (%@)", err.localizedDescription);
		return nil;
	}
	NSDictionary *root = json;
	if (name && [root[@"name"] isKindOfClass:NSString.class])
		*name = root[@"name"];

	// The bubble sits under a wallpaper in the official client; without
	// wallpapers here, withoutWp is the closer match, with withWp as fallback.
	NSMutableDictionary *palette = [NSMutableDictionary dictionary];
	struct { NSString *key; NSString *paths; } map[] = {
		{@"bar",           @"root.navBar.background"},
		{@"barTitle",      @"root.navBar.primaryText"},
		{@"accent",        @"root.navBar.accentText|list.accent|chatList.unreadBadgeActiveBg"},
		{@"chatBackground",@"chat.message.freeform.withoutWp.bg|list.plainBg"},
		{@"bubbleMine",    @"chat.message.outgoing.bubble.withoutWp.bg|chat.message.outgoing.bubble.withWp.bg"},
		{@"bubbleTheirs",  @"chat.message.incoming.bubble.withoutWp.bg|chat.message.incoming.bubble.withWp.bg"},
		{@"listBackground",@"chatList.bg|list.plainBg"},
		{@"primaryText",   @"chatList.title|list.primaryText"},
		{@"secondaryText", @"chatList.messageText|list.secondaryText"},
	};

	for (unsigned i = 0; i < sizeof(map) / sizeof(map[0]); i++){
		for (NSString *path in [map[i].paths componentsSeparatedByString:@"|"]){
			UIColor *colour = TGColourFromHex(TGDig(root, path));
			if (colour){
				palette[map[i].key] = colour;
				break;
			}
		}
	}

	if (palette.count < 2)
		return nil;

	if ([root[@"dark"] respondsToSelector:@selector(boolValue)])
		palette[@"isDark"] = @([root[@"dark"] boolValue]);
	else
		palette[@"isDark"] = @(TGPaletteLooksDark(palette));
	return palette;
}

#pragma mark - Telegram for Android (.attheme)

/// Android writes signed decimal ARGB, so -14606047 is a colour.
static UIColor *TGColourFromSignedARGB(NSString *value) {
	value = [value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!value.length)
		return nil;

	if ([value hasPrefix:@"#"])
		return TGColourFromHex(value);

	NSScanner *scanner = [NSScanner scannerWithString:value];
	long long v = 0;
	if (![scanner scanLongLong:&v] || ![scanner isAtEnd])
		return nil;

	uint32_t argb = (uint32_t)v;
	CGFloat alpha = ((argb >> 24) & 0xFF) / 255.0f;
	return [UIColor colorWithRed:((argb >> 16) & 0xFF) / 255.0f
						   green:((argb >> 8) & 0xFF) / 255.0f
							blue:(argb & 0xFF) / 255.0f
						   alpha:(alpha == 0 ? 1.0f : alpha)];
}

+ (NSDictionary *)paletteFromAndroidTheme:(NSData *)data {
	NSData *marker = [@"WPS" dataUsingEncoding:NSUTF8StringEncoding];
	NSRange wallpaper = [data rangeOfData:marker
								  options:0
									range:NSMakeRange(0, data.length)];
	if (wallpaper.location != NSNotFound)
		data = [data subdataWithRange:NSMakeRange(0, wallpaper.location)];
	if (!data.length)
		return nil;

	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!text.length)
		text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
	if (!text.length)
		return nil;

	text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
	text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

	NSMutableDictionary *raw = [NSMutableDictionary dictionary];
	for (NSString *line in [text componentsSeparatedByString:@"\n"]){
		NSRange eq = [line rangeOfString:@"="];
		if (eq.location == NSNotFound)
			continue;
		NSString *key = [[line substringToIndex:eq.location]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *value = [[line substringFromIndex:eq.location + 1]
				stringByTrimmingCharactersInSet:
						[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (key.length && value.length)
			raw[key] = value;
	}
	if (!raw.count)
		return nil;

	NSMutableDictionary *palette = [NSMutableDictionary dictionary];
	struct { NSString *key; NSString *names; } map[] = {
		{@"bar",           @"actionBarDefault|actionBarActionModeDefault"},
		{@"barTitle",      @"actionBarDefaultTitle"},
		{@"accent",        @"windowBackgroundWhiteBlueText|windowBackgroundWhiteBlueHeader|actionBarDefaultSubtitle"},
		{@"chatBackground",@"chat_wallpaper|windowBackgroundGray|windowBackgroundWhite"},
		{@"bubbleMine",    @"chat_outBubble"},
		{@"bubbleTheirs",  @"chat_inBubble"},
		{@"listBackground",@"windowBackgroundWhite"},
		{@"primaryText",   @"windowBackgroundWhiteBlackText"},
		{@"secondaryText", @"windowBackgroundWhiteGrayText|windowBackgroundWhiteGrayText2"},
	};

	for (unsigned i = 0; i < sizeof(map) / sizeof(map[0]); i++){
		for (NSString *candidate in [map[i].names componentsSeparatedByString:@"|"]){
			UIColor *colour = TGColourFromSignedARGB(raw[candidate]);
			if (colour){
				palette[map[i].key] = colour;
				break;
			}
		}
	}
	if (palette.count < 2)
		return nil;

	palette[@"isDark"] = @(TGPaletteLooksDark(palette));
	return palette;
}

@end

// vim:ft=objc

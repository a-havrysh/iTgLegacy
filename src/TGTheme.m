#import "TGTheme.h"

NSString *const TGThemeChangedNotification = @"TGThemeChanged";

static NSString *const kStyleKey = @"themeStyle";

@implementation TGTheme

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
	return self;
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

#pragma mark - palette

static UIColor *rgb(int r, int g, int b) {
	return [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:1.0f];
}

- (UIColor *)barColour {
	return self.isFlat ? rgb(247, 247, 247) : rgb(64, 122, 173);
}

- (UIColor *)barTitleColour {
	return self.isFlat ? rgb(20, 20, 20) : [UIColor whiteColor];
}

- (UIColor *)accentColour {
	return self.isFlat ? rgb(0, 122, 255) : rgb(38, 92, 140);
}

- (UIColor *)chatBackgroundColour {
	return self.isFlat ? rgb(255, 255, 255) : rgb(217, 222, 212);
}

- (UIColor *)bubbleMineColour {
	return self.isFlat ? rgb(0, 122, 255) : rgb(217, 245, 194);
}

- (UIColor *)bubbleTheirsColour {
	return self.isFlat ? rgb(233, 233, 235) : [UIColor whiteColor];
}

- (UIColor *)bubbleBorderColour {
	// A drawn edge is what makes a skeuomorphic bubble sit on the surface;
	// flat bubbles have none at all.
	return self.isFlat ? [UIColor clearColor] : [UIColor colorWithWhite:0.0f alpha:0.12f];
}

- (UIColor *)listBackgroundColour {
	return [UIColor whiteColor];
}

- (UIColor *)primaryTextColour {
	return rgb(20, 20, 20);
}

- (UIColor *)secondaryTextColour {
	return rgb(120, 120, 125);
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
		bar.barTintColor = [self barColour];
		bar.tintColor = self.isFlat ? [self accentColour] : [UIColor whiteColor];
		bar.titleTextAttributes = @{ NSForegroundColorAttributeName : [self barTitleColour] };
	} else {
		bar.tintColor = [self barColour];
		bar.titleTextAttributes = @{ UITextAttributeTextColor : [self barTitleColour] };
	}
}

@end

// vim:ft=objc

#import "TGIcons.h"
#import "TGTheme.h"

@interface TGHeaderButton : UIButton
@end

@implementation TGHeaderButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
	return CGRectContainsPoint(CGRectInset(self.bounds, -8, -8), point);
}

@end

static NSMutableDictionary *sCache = nil;
static NSCache *sAvatarCache = nil;

static CGFloat TGAvatarCornerRadius(CGFloat side) {
	if (fabs(side - 70) < 0.5f) return 9;
	if (fabs(side - 56) < 0.5f) return 5;
	if (fabs(side - 40) < 0.5f) return 4;
	if (fabs(side - 30) < 0.5f) return 3;
	return roundf(side * 0.09f);
}

static UIImage *TGArtwork(NSString *name) {
	return [UIImage imageNamed:name];
}

static UIImage *TGArtworkTemplate(NSString *name) {
	UIImage *image = [UIImage imageNamed:name];
	if (image && [image respondsToSelector:@selector(imageWithRenderingMode:)])
		image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	return image;
}

static UIImage *TGArtworkMasked(NSString *name, UIColor *colour, CGSize target) {
	UIImage *src = [UIImage imageNamed:name];
	if (!src || src.size.width < 1 || src.size.height < 1)
		return nil;

	CGSize size = target.width > 0 && target.height > 0 ? target : src.size;
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGRect rect = CGRectMake(0, 0, size.width, size.height);

	CGContextTranslateCTM(ctx, 0, size.height);
	CGContextScaleCTM(ctx, 1, -1);
	CGContextClipToMask(ctx, rect, src.CGImage);
	[colour set];
	CGContextFillRect(ctx, rect);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

static BOOL TGInitialsAreName(NSString *initials) {
	if (initials.length == 0)
		return YES;
	NSCharacterSet *letters = [NSCharacterSet alphanumericCharacterSet];
	for (NSUInteger i = 0; i < initials.length; i++){
		if ([letters characterIsMember:[initials characterAtIndex:i]])
			return YES;
	}
	return NO;
}

static NSUInteger TGImageByteCost(UIImage *image) {
	CGFloat scale = image.scale > 0 ? image.scale : 1.0f;
	CGFloat w = image.size.width * scale;
	CGFloat h = image.size.height * scale;
	if (w < 1) w = 1;
	if (h < 1) h = 1;
	return (NSUInteger)(w * h * 4.0f);
}

static NSCache *TGAvatarCache(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		sAvatarCache = [[NSCache alloc] init];
		sAvatarCache.countLimit = 64;
		sAvatarCache.totalCostLimit = 1536 * 1024;
	});
	return sAvatarCache;
}

@implementation TGIcons

+ (void)load {
	@autoreleasepool {
		[[NSNotificationCenter defaultCenter]
				addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
							object:nil
							 queue:[NSOperationQueue mainQueue]
						usingBlock:^(NSNotification *note){
			[TGIcons flush];
		}];
	}
}

+ (void)flush {
	[sCache removeAllObjects];
	[TGAvatarCache() removeAllObjects];
}

+ (void)styleHeaderButton:(UIButton *)button {
	[self styleHeaderButton:button done:NO];
}

+ (void)styleHeaderButton:(UIButton *)button done:(BOOL)done {
	static UIImage *bg = nil;
	static UIImage *bgPressed = nil;
	static UIImage *bgDone = nil;
	static UIImage *bgDonePressed = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		bg = [[UIImage imageNamed:@"HeaderButton"] stretchableImageWithLeftCapWidth:6 topCapHeight:0];
		bgPressed = [[UIImage imageNamed:@"HeaderButton_Pressed"] stretchableImageWithLeftCapWidth:6 topCapHeight:0];

		UIImage *rawDone = [UIImage imageNamed:@"HeaderButton_Login_Blue"];
		UIImage *rawDonePressed = [UIImage imageNamed:@"HeaderButton_Login_Blue_Pressed"];
		bgDone = [rawDone stretchableImageWithLeftCapWidth:(int)(rawDone.size.width / 2) topCapHeight:0];
		bgDonePressed = [rawDonePressed stretchableImageWithLeftCapWidth:(int)(rawDonePressed.size.width / 2) topCapHeight:0];
	});

	UIImage *normal = (done && bgDone) ? bgDone : bg;
	UIImage *pressed = (done && bgDonePressed) ? bgDonePressed : bgPressed;
	[button setBackgroundImage:normal forState:UIControlStateNormal];
	[button setBackgroundImage:pressed forState:UIControlStateHighlighted];
}

+ (UIButton *)headerButtonWithTitle:(NSString *)title bold:(BOOL)bold
							  target:(id)target action:(SEL)action {
	UIButton *button = [[TGHeaderButton alloc] initWithFrame:CGRectZero];
	button.exclusiveTouch = YES;
	button.adjustsImageWhenDisabled = NO;
	button.adjustsImageWhenHighlighted = NO;
	[self styleHeaderButton:button done:bold];
	[button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];

	UIFont *font = [UIFont boldSystemFontOfSize:12];
	CGSize size = [title sizeWithFont:font];
	button.frame = CGRectMake(0, 0, size.width + 14, 30);

	CGFloat retinaPixel = [UIScreen mainScreen].scale > 1.5f ? 0.5f : 0.0f;
	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectOffset(button.bounds, 0, -2 * retinaPixel)];
	label.text = title;
	label.textColor = [UIColor whiteColor];
	label.shadowColor = bold
			? [UIColor colorWithRed:0x04 / 255.0f green:0x26 / 255.0f blue:0x51 / 255.0f alpha:0.3f]
			: [UIColor colorWithRed:0x0e / 255.0f green:0x28 / 255.0f blue:0x4d / 255.0f alpha:0.4f];
	label.shadowOffset = CGSizeMake(0, -1);
	label.textAlignment = NSTextAlignmentCenter;
	label.backgroundColor = [UIColor clearColor];
	label.font = font;
	label.userInteractionEnabled = NO;
	[button addSubview:label];

	return button;
}

/// Every icon goes through here: same size, same cache, same styling rules.
+ (UIImage *)iconNamed:(NSString *)name draw:(void (^)(CGContextRef ctx, CGFloat s))draw {
	if (!sCache)
		sCache = [NSMutableDictionary dictionary];

	BOOL flat = [TGTheme shared].isFlat;
	BOOL dark = [TGTheme shared].isDark;
	NSString *key = [NSString stringWithFormat:@"%@-%d-%d", name, (int)flat, (int)dark];
	UIImage *cached = sCache[key];
	if (cached)
		return cached;

	CGFloat side = 28;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	if (!flat && !dark){
		// Skeuomorphic glyphs sit on the surface: a soft shadow under, a white
		// highlight one pixel up. Flat ones are the shape and nothing else.
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, 0, 1);
		CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.55f);
		CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.55f);
		draw(ctx, side);
		CGContextRestoreGState(ctx);
	}

	CGFloat ink = dark ? 1.0f : 0.0f;
	CGContextSetRGBFillColor(ctx, ink, ink, ink, 1);
	CGContextSetRGBStrokeColor(ctx, ink, ink, ink, 1);
	draw(ctx, side);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	// Template rendering lets the tab bar and buttons tint it themselves.
	if ([image respondsToSelector:@selector(imageWithRenderingMode:)])
		image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	sCache[key] = image;
	return image;
}

#pragma mark - tab bar

+ (UIImage *)chats {
	UIImage *art = TGArtworkTemplate(@"TabIconMessages");
	if (art)
		return art;
	return [self iconNamed:@"chats" draw:^(CGContextRef ctx, CGFloat s){
		// a speech bubble with a tail, sized to match the other tab glyphs
		CGRect body = CGRectMake(2, 3, s - 4, s - 9);
		UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:6];
		[p moveToPoint:CGPointMake(8, CGRectGetMaxY(body) - 2)];
		[p addLineToPoint:CGPointMake(7, CGRectGetMaxY(body) + 6)];
		[p addLineToPoint:CGPointMake(15, CGRectGetMaxY(body) - 2)];
		[p closePath];
		CGContextAddPath(ctx, p.CGPath);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)contacts {
	UIImage *art = TGArtworkTemplate(@"TabIconContacts");
	if (art)
		return art;
	return [self iconNamed:@"contacts" draw:^(CGContextRef ctx, CGFloat s){
		// head and shoulders
		CGContextFillEllipseInRect(ctx, CGRectMake(s/2 - 5, 4, 10, 10));
		CGRect shoulders = CGRectMake(s/2 - 9, 16, 18, 12);
		UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:shoulders cornerRadius:9];
		CGContextAddPath(ctx, p.CGPath);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)settings {
	UIImage *art = TGArtworkTemplate(@"TabIconSettings");
	if (art)
		return art;
	return [self iconNamed:@"settings" draw:^(CGContextRef ctx, CGFloat s){
		CGPoint center = CGPointMake(s / 2, s / 2);
		CGFloat outerRadius = s * 0.46f;
		CGFloat innerRadius = s * 0.30f;
		CGFloat toothDepth = s * 0.12f;
		NSInteger toothCount = 8;

		UIBezierPath *gear = [UIBezierPath bezierPath];
		for (NSInteger i = 0; i < toothCount * 2; i++){
			CGFloat angle = (CGFloat)i / (toothCount * 2) * 2 * M_PI;
			CGFloat radius = (i % 2 == 0) ? outerRadius + toothDepth : outerRadius;
			CGPoint p = CGPointMake(center.x + radius * cosf(angle),
									 center.y + radius * sinf(angle));
			if (i == 0) [gear moveToPoint:p];
			else [gear addLineToPoint:p];
		}
		[gear closePath];

		UIBezierPath *hole = [UIBezierPath bezierPathWithArcCenter:center
				radius:innerRadius startAngle:0 endAngle:2 * M_PI clockwise:YES];
		[gear appendPath:hole];
		gear.usesEvenOddFillRule = YES;

		CGContextAddPath(ctx, gear.CGPath);
		CGContextEOFillPath(ctx);
	}];
}

#pragma mark - actions

/// A pencil laid across the open corner of a sheet - their compose glyph. The
/// previous one drew the sheet as two bare strokes meeting at a right angle,
/// which read as a stray corner rather than paper.
+ (UIImage *)compose {
	UIImage *art = TGArtworkTemplate(@"ComposeMessageIcon");
	if (art)
		return art;
	return [self iconNamed:@"compose" draw:^(CGContextRef ctx, CGFloat s){
		// The sheet: three sides, left open where the pencil crosses it.
		CGContextSetLineWidth(ctx, 1.8f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);
		CGContextMoveToPoint(ctx, s - 9, 5);
		CGContextAddLineToPoint(ctx, 5, 5);
		CGContextAddLineToPoint(ctx, 5, s - 5);
		CGContextAddLineToPoint(ctx, s - 5, s - 5);
		CGContextAddLineToPoint(ctx, s - 5, 10);
		CGContextStrokePath(ctx);

		// The pencil: a shaft with a nib, pointing down and left.
		CGFloat tipX = 11, tipY = s - 10;
		CGContextMoveToPoint(ctx, tipX, tipY);
		CGContextAddLineToPoint(ctx, tipX + 2, tipY + 3.5f);
		CGContextAddLineToPoint(ctx, tipX + 5.5f, tipY + 1.5f);
		CGContextAddLineToPoint(ctx, s - 5, 6.5f);
		CGContextAddLineToPoint(ctx, s - 8.5f, 3);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)send {
	UIImage *art = TGArtwork(@"Send");
	if (art)
		return art;
	return [self iconNamed:@"send" draw:^(CGContextRef ctx, CGFloat s){
		// paper plane
		CGContextMoveToPoint(ctx, 3, s/2);
		CGContextAddLineToPoint(ctx, s - 3, 4);
		CGContextAddLineToPoint(ctx, s - 8, s - 4);
		CGContextAddLineToPoint(ctx, s/2 - 1, s/2 + 3);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)attach {
	UIImage *art = TGArtwork(@"AttachBtn");
	if (art)
		return art;
	return [self iconNamed:@"attach" draw:^(CGContextRef ctx, CGFloat s){
		// plus
		CGContextSetLineWidth(ctx, 3);
		CGContextMoveToPoint(ctx, s/2, 6);
		CGContextAddLineToPoint(ctx, s/2, s - 6);
		CGContextMoveToPoint(ctx, 6, s/2);
		CGContextAddLineToPoint(ctx, s - 6, s/2);
		CGContextStrokePath(ctx);
	}];
}

+ (UIImage *)play {
	return [self iconNamed:@"play" draw:^(CGContextRef ctx, CGFloat s){
		CGContextMoveToPoint(ctx, 8, 5);
		CGContextAddLineToPoint(ctx, s - 6, s/2);
		CGContextAddLineToPoint(ctx, 8, s - 5);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)pause {
	return [self iconNamed:@"pause" draw:^(CGContextRef ctx, CGFloat s){
		CGContextFillRect(ctx, CGRectMake(s * 0.32f, 5, s * 0.13f, s - 10));
		CGContextFillRect(ctx, CGRectMake(s * 0.55f, 5, s * 0.13f, s - 10));
	}];
}

+ (UIImage *)document {
	return [self iconNamed:@"document" draw:^(CGContextRef ctx, CGFloat s){
		// sheet with a folded corner
		CGContextMoveToPoint(ctx, 6, 3);
		CGContextAddLineToPoint(ctx, s - 10, 3);
		CGContextAddLineToPoint(ctx, s - 5, 8);
		CGContextAddLineToPoint(ctx, s - 5, s - 3);
		CGContextAddLineToPoint(ctx, 6, s - 3);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)pin {
	return [self iconNamed:@"pin" draw:^(CGContextRef ctx, CGFloat s){
		CGContextFillEllipseInRect(ctx, CGRectMake(s/2 - 6, 4, 12, 12));
		CGContextMoveToPoint(ctx, s/2 - 4, 14);
		CGContextAddLineToPoint(ctx, s/2 + 4, 14);
		CGContextAddLineToPoint(ctx, s/2, s - 4);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)microphone {
	return [self iconNamed:@"microphone" draw:^(CGContextRef ctx, CGFloat s){
		// capsule head, stand, base
		UIBezierPath *head = [UIBezierPath bezierPathWithRoundedRect:
				CGRectMake(s/2 - 4, 3, 8, 13) cornerRadius:4];
		CGContextAddPath(ctx, head.CGPath);
		CGContextFillPath(ctx);

		CGContextSetLineWidth(ctx, 2);
		CGContextAddArc(ctx, s/2, 14, 7, 0, M_PI, 0);
		CGContextStrokePath(ctx);

		CGContextMoveToPoint(ctx, s/2, 21);
		CGContextAddLineToPoint(ctx, s/2, s - 4);
		CGContextStrokePath(ctx);
	}];
}

/// A smiling face. U+1F642 would be the obvious glyph, but it arrived in
/// Unicode 7.0 and iOS 7 draws it as an empty box.
+ (UIImage *)sticker {
	return [self iconNamed:@"sticker" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, 2);
		CGContextStrokeEllipseInRect(ctx, CGRectMake(3, 3, s - 6, s - 6));
		CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.33f, s * 0.34f, 2.5f, 3.5f));
		CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.60f, s * 0.34f, 2.5f, 3.5f));
		CGContextAddArc(ctx, s / 2, s * 0.52f, s * 0.22f, 0.5f, M_PI - 0.5f, 0);
		CGContextStrokePath(ctx);
	}];
}

+ (UIImage *)callArrowOutgoing:(BOOL)outgoing missed:(BOOL)missed {
	CGFloat s = 14;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	// green_bright1 answered, red_3 missed - their two call colours.
	if (missed)
		CGContextSetRGBStrokeColor(ctx, 0.871f, 0.227f, 0.227f, 1.0f);
	else
		CGContextSetRGBStrokeColor(ctx, 0.353f, 0.804f, 0.188f, 1.0f);
	CGContextSetLineWidth(ctx, 1.6f);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);

	// The shaft runs corner to corner; the head sits on the end it points at.
	CGFloat lo = 2.5f, hi = s - 2.5f;
	if (outgoing){
		CGContextMoveToPoint(ctx, lo, hi);
		CGContextAddLineToPoint(ctx, hi, lo);
		CGContextStrokePath(ctx);
		CGContextMoveToPoint(ctx, hi - 5, lo);
		CGContextAddLineToPoint(ctx, hi, lo);
		CGContextAddLineToPoint(ctx, hi, lo + 5);
	} else {
		CGContextMoveToPoint(ctx, hi, lo);
		CGContextAddLineToPoint(ctx, lo, hi);
		CGContextStrokePath(ctx);
		CGContextMoveToPoint(ctx, lo + 5, hi);
		CGContextAddLineToPoint(ctx, lo, hi);
		CGContextAddLineToPoint(ctx, lo, hi - 5);
	}
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

#pragma mark - menu glyphs

/// The line art beside each row of their pop-up menu. Drawn as strokes at a
/// single weight so the set reads as one family, which is what their 27x27
/// outline icons do.
static void TGMenuDrawReply(CGContextRef ctx, CGFloat s, CGFloat m) {
	// an arrow turning back on itself
	CGContextMoveToPoint(ctx, m + 5, s * 0.30f);
	CGContextAddLineToPoint(ctx, m, s * 0.45f);
	CGContextAddLineToPoint(ctx, m + 5, s * 0.60f);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, m, s * 0.45f);
	CGContextAddLineToPoint(ctx, s - m - 5, s * 0.45f);
	CGContextAddArc(ctx, s - m - 5, s * 0.62f, s * 0.17f, -M_PI_2, 0, 0);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawForward(CGContextRef ctx, CGFloat s, CGFloat m) {
	// the same arrow mirrored
	CGContextMoveToPoint(ctx, s - m - 5, s * 0.30f);
	CGContextAddLineToPoint(ctx, s - m, s * 0.45f);
	CGContextAddLineToPoint(ctx, s - m - 5, s * 0.60f);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, s - m, s * 0.45f);
	CGContextAddLineToPoint(ctx, m + 5, s * 0.45f);
	CGContextAddArc(ctx, m + 5, s * 0.62f, s * 0.17f, -M_PI_2, M_PI, 1);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawCopy(CGContextRef ctx, CGFloat s, CGFloat m) {
	// two sheets, one behind the other
	CGContextStrokeRect(ctx, CGRectMake(m, m, s * 0.46f, s * 0.46f));
	CGContextStrokeRect(ctx, CGRectMake(s * 0.34f, s * 0.34f, s * 0.46f, s * 0.46f));
}

static void TGMenuDrawEdit(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a pencil on its diagonal
	CGContextMoveToPoint(ctx, m, s - m);
	CGContextAddLineToPoint(ctx, m + s * 0.10f, s - m - s * 0.16f);
	CGContextAddLineToPoint(ctx, s - m - s * 0.06f, m + s * 0.06f);
	CGContextAddLineToPoint(ctx, s - m, m + s * 0.16f);
	CGContextAddLineToPoint(ctx, m + s * 0.20f, s - m - s * 0.06f);
	CGContextClosePath(ctx);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawDelete(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a bin: lid, body, two ribs
	CGContextMoveToPoint(ctx, m, s * 0.30f);
	CGContextAddLineToPoint(ctx, s - m, s * 0.30f);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, s * 0.40f, s * 0.30f);
	CGContextAddLineToPoint(ctx, s * 0.40f, s * 0.22f);
	CGContextAddLineToPoint(ctx, s * 0.60f, s * 0.22f);
	CGContextAddLineToPoint(ctx, s * 0.60f, s * 0.30f);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, m + 2, s * 0.30f);
	CGContextAddLineToPoint(ctx, m + 4, s - m);
	CGContextAddLineToPoint(ctx, s - m - 4, s - m);
	CGContextAddLineToPoint(ctx, s - m - 2, s * 0.30f);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawPin(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a drawing pin seen from the side
	CGContextMoveToPoint(ctx, s * 0.34f, m);
	CGContextAddLineToPoint(ctx, s * 0.66f, m);
	CGContextAddLineToPoint(ctx, s * 0.58f, s * 0.46f);
	CGContextAddLineToPoint(ctx, s * 0.76f, s * 0.60f);
	CGContextAddLineToPoint(ctx, s * 0.24f, s * 0.60f);
	CGContextAddLineToPoint(ctx, s * 0.42f, s * 0.46f);
	CGContextClosePath(ctx);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, s / 2, s * 0.60f);
	CGContextAddLineToPoint(ctx, s / 2, s - m);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawSpeaker(CGContextRef ctx, CGFloat s, CGFloat m, BOOL crossed) {
	// a speaker cone
	CGContextMoveToPoint(ctx, m, s * 0.38f);
	CGContextAddLineToPoint(ctx, s * 0.34f, s * 0.38f);
	CGContextAddLineToPoint(ctx, s * 0.54f, s * 0.20f);
	CGContextAddLineToPoint(ctx, s * 0.54f, s * 0.80f);
	CGContextAddLineToPoint(ctx, s * 0.34f, s * 0.62f);
	CGContextAddLineToPoint(ctx, m, s * 0.62f);
	CGContextClosePath(ctx);
	CGContextStrokePath(ctx);
	if (crossed){
		CGContextMoveToPoint(ctx, s * 0.66f, s * 0.38f);
		CGContextAddLineToPoint(ctx, s * 0.86f, s * 0.62f);
		CGContextMoveToPoint(ctx, s * 0.86f, s * 0.38f);
		CGContextAddLineToPoint(ctx, s * 0.66f, s * 0.62f);
		CGContextStrokePath(ctx);
	}
}

static void TGMenuDrawArchive(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a box with a lid and a handle slot
	CGContextStrokeRect(ctx, CGRectMake(m, m, s - 2 * m, s * 0.18f));
	CGContextMoveToPoint(ctx, m + 2, m + s * 0.18f);
	CGContextAddLineToPoint(ctx, m + 2, s - m);
	CGContextAddLineToPoint(ctx, s - m - 2, s - m);
	CGContextAddLineToPoint(ctx, s - m - 2, m + s * 0.18f);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, s * 0.40f, s * 0.58f);
	CGContextAddLineToPoint(ctx, s * 0.60f, s * 0.58f);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawReact(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a heart
	CGContextMoveToPoint(ctx, s / 2, s - m - 2);
	CGContextAddCurveToPoint(ctx, m, s * 0.60f, m, s * 0.22f, s / 2, s * 0.38f);
	CGContextAddCurveToPoint(ctx, s - m, s * 0.22f, s - m, s * 0.60f, s / 2, s - m - 2);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawCall(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a handset on its diagonal
	CGContextSetLineWidth(ctx, 2.0f);
	CGContextMoveToPoint(ctx, m + 1, m + 4);
	CGContextAddCurveToPoint(ctx, m + 1, s * 0.70f, s * 0.70f, s - m - 1,
							 s - m - 4, s - m - 1);
	CGContextAddLineToPoint(ctx, s - m, s * 0.68f);
	CGContextAddLineToPoint(ctx, s * 0.62f, s * 0.58f);
	CGContextAddLineToPoint(ctx, s * 0.50f, s * 0.68f);
	CGContextAddCurveToPoint(ctx, s * 0.40f, s * 0.60f, s * 0.40f, s * 0.60f,
							 s * 0.32f, s * 0.50f);
	CGContextAddLineToPoint(ctx, s * 0.42f, s * 0.38f);
	CGContextAddLineToPoint(ctx, s * 0.32f, m);
	CGContextClosePath(ctx);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawVideo(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a camera: body and the lens sticking out of it
	CGContextAddPath(ctx, [UIBezierPath bezierPathWithRoundedRect:
			CGRectMake(m, s * 0.32f, s * 0.44f, s * 0.36f)
													 cornerRadius:3].CGPath);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, m + s * 0.46f, s * 0.44f);
	CGContextAddLineToPoint(ctx, s - m, s * 0.34f);
	CGContextAddLineToPoint(ctx, s - m, s * 0.66f);
	CGContextAddLineToPoint(ctx, m + s * 0.46f, s * 0.56f);
	CGContextClosePath(ctx);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawSearch(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a magnifier
	CGContextStrokeEllipseInRect(ctx, CGRectMake(m, m, s * 0.50f, s * 0.50f));
	CGContextMoveToPoint(ctx, m + s * 0.46f, m + s * 0.46f);
	CGContextAddLineToPoint(ctx, s - m, s - m);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawMore(CGContextRef ctx, CGFloat s, CGFloat m) {
	// three dots across
	for (int i = 0; i < 3; i++)
		CGContextFillEllipseInRect(ctx, CGRectMake(
				s * 0.24f + i * s * 0.20f - 1.5f, s / 2 - 1.5f, 3, 3));
}

static void TGMenuDrawNotifications(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a bell
	CGContextAddArc(ctx, s / 2, s * 0.46f, s * 0.26f, M_PI, 0, 0);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, s * 0.24f, s * 0.46f);
	CGContextAddLineToPoint(ctx, s * 0.24f, s * 0.66f);
	CGContextAddLineToPoint(ctx, s * 0.76f, s * 0.66f);
	CGContextAddLineToPoint(ctx, s * 0.76f, s * 0.46f);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, s * 0.42f, s * 0.74f);
	CGContextAddLineToPoint(ctx, s * 0.58f, s * 0.74f);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawPrivacy(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a padlock: shackle over a body
	CGContextAddArc(ctx, s / 2, s * 0.42f, s * 0.16f, M_PI, 0, 0);
	CGContextStrokePath(ctx);
	CGContextStrokeRect(ctx, CGRectMake(s * 0.26f, s * 0.44f,
										s * 0.48f, s * 0.34f));
}

static void TGMenuDrawData(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a pie with one slice drawn in
	CGContextStrokeEllipseInRect(ctx, CGRectInset(
			CGRectMake(0, 0, s, s), m, m));
	CGContextMoveToPoint(ctx, s / 2, s / 2);
	CGContextAddLineToPoint(ctx, s / 2, m);
	CGContextMoveToPoint(ctx, s / 2, s / 2);
	CGContextAddLineToPoint(ctx, s - m, s / 2);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawChat(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a speech bubble with a tail
	CGRect body = CGRectMake(m, m, s - 2 * m, s * 0.50f);
	CGContextAddPath(ctx, [UIBezierPath bezierPathWithRoundedRect:body
													 cornerRadius:s * 0.14f].CGPath);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, s * 0.30f, CGRectGetMaxY(body));
	CGContextAddLineToPoint(ctx, s * 0.30f, s - m);
	CGContextAddLineToPoint(ctx, s * 0.48f, CGRectGetMaxY(body));
	CGContextStrokePath(ctx);
}

static void TGMenuDrawFolder(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a tab along the top left, then the body
	CGContextMoveToPoint(ctx, m, s * 0.74f);
	CGContextAddLineToPoint(ctx, m, s * 0.28f);
	CGContextAddLineToPoint(ctx, s * 0.42f, s * 0.28f);
	CGContextAddLineToPoint(ctx, s * 0.50f, s * 0.38f);
	CGContextAddLineToPoint(ctx, s - m, s * 0.38f);
	CGContextAddLineToPoint(ctx, s - m, s * 0.74f);
	CGContextClosePath(ctx);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawDevices(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a laptop: screen and the bar it stands on
	CGContextStrokeRect(ctx, CGRectMake(s * 0.20f, s * 0.28f,
										s * 0.60f, s * 0.36f));
	CGContextMoveToPoint(ctx, m, s * 0.72f);
	CGContextAddLineToPoint(ctx, s - m, s * 0.72f);
	CGContextStrokePath(ctx);
}

static void TGMenuDrawLanguage(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a globe: circle, equator, meridian
	CGRect ball = CGRectInset(CGRectMake(0, 0, s, s), m, m);
	CGContextStrokeEllipseInRect(ctx, ball);
	CGContextMoveToPoint(ctx, m, s / 2);
	CGContextAddLineToPoint(ctx, s - m, s / 2);
	CGContextStrokePath(ctx);
	CGContextSaveGState(ctx);
	CGContextTranslateCTM(ctx, s / 2, s / 2);
	CGContextScaleCTM(ctx, 0.5f, 1.0f);
	CGContextTranslateCTM(ctx, -s / 2, -s / 2);
	CGContextStrokeEllipseInRect(ctx, ball);
	CGContextRestoreGState(ctx);
}

static void TGMenuDrawFaq(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a question mark in a circle
	CGContextStrokeEllipseInRect(ctx, CGRectInset(
			CGRectMake(0, 0, s, s), m, m));
	CGContextAddArc(ctx, s / 2, s * 0.40f, s * 0.11f, M_PI, M_PI_2, 1);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, s / 2, s * 0.51f);
	CGContextAddLineToPoint(ctx, s / 2, s * 0.60f);
	CGContextStrokePath(ctx);
	CGContextFillEllipseInRect(ctx, CGRectMake(s / 2 - 1, s * 0.68f, 2, 2));
}

static void TGMenuDrawPolicy(CGContextRef ctx, CGFloat s, CGFloat m) {
	// a shield with a tick in it
	CGContextMoveToPoint(ctx, s / 2, m);
	CGContextAddLineToPoint(ctx, s - m, s * 0.30f);
	CGContextAddLineToPoint(ctx, s - m, s * 0.56f);
	CGContextAddCurveToPoint(ctx, s - m, s * 0.76f, s * 0.70f, s - m,
							 s / 2, s - m);
	CGContextAddCurveToPoint(ctx, s * 0.30f, s - m, m, s * 0.76f,
							 m, s * 0.56f);
	CGContextAddLineToPoint(ctx, m, s * 0.30f);
	CGContextClosePath(ctx);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, s * 0.36f, s * 0.50f);
	CGContextAddLineToPoint(ctx, s * 0.46f, s * 0.60f);
	CGContextAddLineToPoint(ctx, s * 0.66f, s * 0.38f);
	CGContextStrokePath(ctx);
}

static NSSet *TGKnownMenuGlyphNames(void) {
	static NSSet *known = nil;
	if (!known)
		known = [NSSet setWithObjects:@"reply", @"undo", @"forward", @"copy",
				@"edit", @"delete", @"pin", @"unpin", @"mute", @"unmute",
				@"archive", @"unarchive", @"react",
				// the settings list
				@"notifications", @"privacy", @"data", @"chat", @"folder",
				@"devices", @"language", @"faq", @"policy",
				// the profile's action tiles
				@"call", @"video", @"search", @"more", nil];
	return known;
}

+ (UIImage *)menuGlyphNamed:(NSString *)name {
	// An unknown name has to answer nil, not a blank square: a row with no
	// glyph is better than a row with a hole where one should be.
	if (![TGKnownMenuGlyphNames() containsObject:name])
		return nil;

	if ([name isEqualToString:@"search"]){
		UIImage *art = TGArtworkTemplate(@"SearchBarIcon");
		if (art)
			return art;
	}

	NSString *key = [@"menu-" stringByAppendingString:name];
	return [self iconNamed:key draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, 1.8f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);
		CGFloat m = s * 0.18f;              // margin, so every glyph shares a box

		if ([name isEqualToString:@"reply"] || [name isEqualToString:@"undo"]){
			TGMenuDrawReply(ctx, s, m);

		} else if ([name isEqualToString:@"forward"]){
			TGMenuDrawForward(ctx, s, m);

		} else if ([name isEqualToString:@"copy"]){
			TGMenuDrawCopy(ctx, s, m);

		} else if ([name isEqualToString:@"edit"]){
			TGMenuDrawEdit(ctx, s, m);

		} else if ([name isEqualToString:@"delete"]){
			TGMenuDrawDelete(ctx, s, m);

		} else if ([name isEqualToString:@"pin"] || [name isEqualToString:@"unpin"]){
			TGMenuDrawPin(ctx, s, m);

		} else if ([name isEqualToString:@"mute"] || [name isEqualToString:@"unmute"]){
			TGMenuDrawSpeaker(ctx, s, m, [name isEqualToString:@"mute"]);

		} else if ([name isEqualToString:@"archive"] || [name isEqualToString:@"unarchive"]){
			TGMenuDrawArchive(ctx, s, m);

		} else if ([name isEqualToString:@"react"]){
			TGMenuDrawReact(ctx, s, m);

		} else if ([name isEqualToString:@"call"]){
			TGMenuDrawCall(ctx, s, m);

		} else if ([name isEqualToString:@"video"]){
			TGMenuDrawVideo(ctx, s, m);

		} else if ([name isEqualToString:@"search"]){
			TGMenuDrawSearch(ctx, s, m);

		} else if ([name isEqualToString:@"more"]){
			TGMenuDrawMore(ctx, s, m);

		} else if ([name isEqualToString:@"notifications"]){
			TGMenuDrawNotifications(ctx, s, m);

		} else if ([name isEqualToString:@"privacy"]){
			TGMenuDrawPrivacy(ctx, s, m);

		} else if ([name isEqualToString:@"data"]){
			TGMenuDrawData(ctx, s, m);

		} else if ([name isEqualToString:@"chat"]){
			TGMenuDrawChat(ctx, s, m);

		} else if ([name isEqualToString:@"folder"]){
			TGMenuDrawFolder(ctx, s, m);

		} else if ([name isEqualToString:@"devices"]){
			TGMenuDrawDevices(ctx, s, m);

		} else if ([name isEqualToString:@"language"]){
			TGMenuDrawLanguage(ctx, s, m);

		} else if ([name isEqualToString:@"faq"]){
			TGMenuDrawFaq(ctx, s, m);

		} else if ([name isEqualToString:@"policy"]){
			TGMenuDrawPolicy(ctx, s, m);

		} else {
			return;   // an unknown name draws nothing rather than a wrong glyph
		}
	}];
}

+ (UIImage *)mediaDiscOfSide:(CGFloat)side playing:(BOOL)playing {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetRGBFillColor(ctx, 0x0f / 255.0f, 0x94 / 255.0f, 0xed / 255.0f, 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, side, side));

	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	if (playing){
		CGFloat w = side * 0.10f, h = side * 0.30f, gap = side * 0.10f;
		CGContextFillRect(ctx, CGRectMake(side/2 - gap/2 - w, (side - h)/2, w, h));
		CGContextFillRect(ctx, CGRectMake(side/2 + gap/2,     (side - h)/2, w, h));
	} else {
		// A triangle, nudged right so it looks centred inside the disc.
		CGContextMoveToPoint(ctx, side * 0.40f, side * 0.32f);
		CGContextAddLineToPoint(ctx, side * 0.68f, side * 0.50f);
		CGContextAddLineToPoint(ctx, side * 0.40f, side * 0.68f);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

+ (UIImage *)fileDiscOfSide:(CGFloat)side {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetRGBFillColor(ctx, 0x0f / 255.0f, 0x94 / 255.0f, 0xed / 255.0f, 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, side, side));

	// A sheet with the top right corner turned down, drawn as one path so the
	// fold reads as a notch rather than a separate shape.
	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	CGFloat l = side * 0.34f, r = side * 0.66f, t = side * 0.28f, b = side * 0.72f;
	CGFloat fold = side * 0.12f;
	CGContextMoveToPoint(ctx, l, t);
	CGContextAddLineToPoint(ctx, r - fold, t);
	CGContextAddLineToPoint(ctx, r, t + fold);
	CGContextAddLineToPoint(ctx, r, b);
	CGContextAddLineToPoint(ctx, l, b);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);

	// The fold itself, punched back out in the disc's blue.
	CGContextSetRGBFillColor(ctx, 0x0f / 255.0f, 0x94 / 255.0f, 0xed / 255.0f, 1.0f);
	CGContextMoveToPoint(ctx, r - fold, t);
	CGContextAddLineToPoint(ctx, r, t + fold);
	CGContextAddLineToPoint(ctx, r - fold, t + fold);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

+ (UIImage *)microphoneOfSide:(CGFloat)side colour:(UIColor *)colour {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	[colour set];

	// capsule head, the arc under it, the stand and the foot
	UIBezierPath *head = [UIBezierPath bezierPathWithRoundedRect:
			CGRectMake(side * 0.40f, side * 0.18f, side * 0.20f, side * 0.38f)
												   cornerRadius:side * 0.10f];
	[head fill];

	CGContextSetLineWidth(ctx, MAX(1.5f, side * 0.055f));
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextAddArc(ctx, side / 2, side * 0.50f, side * 0.20f, 0, M_PI, 0);
	CGContextStrokePath(ctx);

	CGContextMoveToPoint(ctx, side / 2, side * 0.70f);
	CGContextAddLineToPoint(ctx, side / 2, side * 0.80f);
	CGContextStrokePath(ctx);

	CGContextMoveToPoint(ctx, side * 0.38f, side * 0.80f);
	CGContextAddLineToPoint(ctx, side * 0.62f, side * 0.80f);
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

+ (UIImage *)waveform:(NSData *)waveform size:(CGSize)size
               played:(CGFloat)played colour:(UIColor *)colour {
	CGFloat barW = 2, gap = 1;
	if (size.width <= 0 || size.height <= 0)
		return nil;
	NSUInteger bars = (NSUInteger)(size.width / (barW + gap));
	if (bars == 0)
		return nil;

	UIGraphicsBeginImageContextWithOptions(size, NO, 0);

	const uint8_t *bytes = (const uint8_t *)waveform.bytes;
	NSUInteger bits = waveform.length * 8 / 5;      // five bits per sample

	for (NSUInteger i = 0; i < bars; i++){
		CGFloat value = 0.35f;                       // a flat line when there
		if (bits > 0){                               // is no waveform at all
			NSUInteger index = i * bits / bars;
			NSUInteger bit = index * 5;
			NSUInteger byte = bit / 8;
			if (byte + 1 < waveform.length){
				uint16_t window = (uint16_t)((bytes[byte] | (bytes[byte + 1] << 8)) >> (bit % 8));
				value = (window & 0x1F) / 31.0f;
			}
		}

		CGFloat height = MAX(2.0f, value * size.height);
		CGFloat x = i * (barW + gap);
		CGRect bar = CGRectMake(x, (size.height - height) / 2, barW, height);

		// The part already heard is solid; the rest is faded, which is how
		// Telegram shows progress through a message. The gap between the two
		// has to be wide enough to read at a glance on a 3.5" screen.
		CGFloat alpha = (i < bars * played) ? 1.0f : 0.32f;
		[[colour colorWithAlphaComponent:alpha] set];
		UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:bar cornerRadius:1];
		[rounded fill];
	}

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

+ (UIImage *)bubbleTailForColour:(UIColor *)colour outgoing:(BOOL)outgoing {
	CGSize size = CGSizeMake(6, 10);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	[colour set];

	// A curl off the bottom corner, mirrored for an incoming bubble.
	if (outgoing){
		CGContextMoveToPoint(ctx, 0, 0);
		CGContextAddLineToPoint(ctx, 0, 10);
		CGContextAddCurveToPoint(ctx, 3, 9, 5, 7, 6, 4);
		CGContextAddLineToPoint(ctx, 0, 4);
	} else {
		CGContextMoveToPoint(ctx, 6, 0);
		CGContextAddLineToPoint(ctx, 6, 10);
		CGContextAddCurveToPoint(ctx, 3, 9, 1, 7, 0, 4);
		CGContextAddLineToPoint(ctx, 6, 4);
	}
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

+ (UIImage *)messageChecksRead:(BOOL)read white:(BOOL)white {
	NSString *name = read ? @"MessageCheckFull" : @"MessageCheckHalf";
	if (!white)
		return TGArtwork(name);
	return TGArtworkMasked(name, [UIColor whiteColor], CGSizeZero);
}

+ (UIImage *)messageTimestampPlateOutgoing:(BOOL)outgoing {
	UIImage *art = TGArtwork(outgoing ? @"MessageTimestampBackground"
									  : @"MessageTimestampBackgroundIncoming");
	if (!art || art.size.width < 2)
		return nil;
	return [art stretchableImageWithLeftCapWidth:(int)(art.size.width / 2) topCapHeight:0];
}

+ (UIImage *)ticksWhite:(BOOL)white {
	static UIImage *green = nil;
	static UIImage *pale = nil;
	static dispatch_once_t ticksOnce;
	dispatch_once(&ticksOnce, ^{
		green = TGArtwork(@"DialogListRead");
		pale = TGArtworkMasked(@"DialogListRead", [UIColor whiteColor], CGSizeZero);
	});
	if (white && pale)
		return pale;
	if (!white && green)
		return green;

	CGSize size = CGSizeMake(16, 10);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	if (white)
		CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1);
	else
		CGContextSetRGBStrokeColor(ctx, 0.051f, 0.710f, 0.051f, 1);

	CGContextSetLineWidth(ctx, 1.2f);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);

	for (int i = 0; i < 2; i++){
		CGFloat dx = i * 4.0f;
		CGContextMoveToPoint(ctx, dx + 0.6f, 5.4f);
		CGContextAddLineToPoint(ctx, dx + 3.4f, 8.4f);
		CGContextAddLineToPoint(ctx, dx + 11.4f, 1.6f);
		CGContextStrokePath(ctx);
	}

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

#pragma mark - avatars

/// The system rows sit on the flat identity blue their placeholder art uses,
/// with a white glyph on top.
static UIImage *TGGlyphAvatar(CGFloat side, void (^draw)(CGContextRef ctx, CGFloat s)) {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side)
													  cornerRadius:TGAvatarCornerRadius(side)];
	CGContextSetRGBFillColor(ctx, 0x0f / 255.0f, 0x94 / 255.0f, 0xed / 255.0f, 1.0f);
	CGContextAddPath(ctx, shape.CGPath);
	CGContextFillPath(ctx);

	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1);
	draw(ctx, side);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

+ (UIImage *)archiveAvatarOfSide:(CGFloat)side {
	return TGGlyphAvatar(side, ^(CGContextRef ctx, CGFloat s){
		// A box: a lid across the top, the body under it, a slot for a hand.
		CGFloat w = s * 0.46f, x = (s - w) / 2;
		CGContextFillRect(ctx, CGRectMake(x, s * 0.32f, w, s * 0.10f));
		CGContextFillRect(ctx, CGRectMake(x + s * 0.03f, s * 0.44f,
										  w - s * 0.06f, s * 0.24f));
		CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.25f);
		CGContextFillRect(ctx, CGRectMake(s * 0.44f, s * 0.50f, s * 0.12f, s * 0.05f));
	});
}

+ (UIImage *)savedMessagesAvatarOfSide:(CGFloat)side {
	return TGGlyphAvatar(side, ^(CGContextRef ctx, CGFloat s){
		// A bookmark: a rectangle with a notch cut out of the bottom edge.
		CGContextMoveToPoint(ctx, s * 0.36f, s * 0.30f);
		CGContextAddLineToPoint(ctx, s * 0.64f, s * 0.30f);
		CGContextAddLineToPoint(ctx, s * 0.64f, s * 0.70f);
		CGContextAddLineToPoint(ctx, s * 0.50f, s * 0.58f);
		CGContextAddLineToPoint(ctx, s * 0.36f, s * 0.70f);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	});
}

+ (UIImage *)inviteFriendsAvatarOfSide:(CGFloat)side {
	return TGGlyphAvatar(side, ^(CGContextRef ctx, CGFloat s){
		UIImage *art = [UIImage imageNamed:@"ListIconInvite"];
		if (art && art.size.width > 0 && art.size.height > 0){
			CGFloat w = roundf(s * 0.56f);
			CGFloat h = roundf(w * art.size.height / art.size.width);
			CGRect box = CGRectMake(roundf((s - w) / 2), roundf((s - h) / 2), w, h);
			UIImage *mark = TGArtworkMasked(@"ListIconInvite", [UIColor whiteColor], box.size);
			if (mark){
				[mark drawInRect:box];
				return;
			}
		}

		CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.357f, s * 0.170f, s * 0.268f, s * 0.339f));
		CGRect shoulders = CGRectMake(s * 0.143f, s * 0.595f, s * 0.714f, s * 0.40f);
		CGContextSaveGState(ctx);
		CGContextClipToRect(ctx, CGRectMake(0, 0, s, s * 0.795f));
		CGContextFillEllipseInRect(ctx, shoulders);
		CGContextRestoreGState(ctx);
	});
}

static void TGDrawAvatarSilhouette(CGContextRef ctx, CGFloat size, uint32_t ink) {
	CGContextSetRGBFillColor(ctx,
			((ink >> 16) & 0xff) / 255.0f,
			((ink >> 8) & 0xff) / 255.0f,
			(ink & 0xff) / 255.0f, 1.0f);

	CGContextSaveGState(ctx);
	CGContextClipToRect(ctx, CGRectMake(0, 0, size, size * 0.795f));
	CGContextFillEllipseInRect(ctx, CGRectMake(size * 0.357f, size * 0.170f,
											   size * 0.268f, size * 0.339f));
	CGContextFillEllipseInRect(ctx, CGRectMake(size * 0.143f, size * 0.595f,
											   size * 0.714f, size * 0.400f));
	CGContextRestoreGState(ctx);
}

static void TGDrawAvatarInitials(NSString *text, CGFloat size) {
	UIFont *font = [UIFont boldSystemFontOfSize:size * 0.4f];
	CGSize textSize = [text sizeWithFont:font];
	[[UIColor whiteColor] set];
	[text drawAtPoint:CGPointMake((size - textSize.width) / 2,
								  (size - textSize.height) / 2)
			 withFont:font];
}

+ (UIImage *)avatarWithInitials:(NSString *)initials
                           size:(CGFloat)size
                       colourId:(int64_t)colourId
{
	static const uint32_t plate[8] = {
		0xed650b, 0x4abc0d, 0xffc600, 0x2f92e9,
		0xa054fe, 0xfb2e6a, 0x06a6c8, 0xde3f12
	};
	static const uint32_t ink[8] = {
		0xaf3600, 0x088202, 0xe36008, 0x0854b7,
		0x6915b7, 0xad0055, 0x006785, 0x8a1e00
	};
	NSUInteger slot = (NSUInteger)(llabs(colourId) % 8);
	uint32_t fill = plate[slot];

	NSString *cacheKey = [NSString stringWithFormat:@"%@-%d-%u-%d",
			TGInitialsAreName(initials) ? @"*" : initials, (int)(size * 100),
			(unsigned)slot, (int)[TGTheme shared].isFlat];
	UIImage *cachedAvatar = [TGAvatarCache() objectForKey:cacheKey];
	if (cachedAvatar)
		return cachedAvatar;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size)
													  cornerRadius:TGAvatarCornerRadius(size)];
	CGContextSetRGBFillColor(ctx, ((fill >> 16) & 0xff) / 255.0f,
								  ((fill >> 8) & 0xff) / 255.0f,
								  (fill & 0xff) / 255.0f, 1.0f);
	CGContextAddPath(ctx, shape.CGPath);
	CGContextFillPath(ctx);

	CGContextSaveGState(ctx);
	CGContextAddPath(ctx, shape.CGPath);
	CGContextClip(ctx);

	if (TGInitialsAreName(initials))
		TGDrawAvatarSilhouette(ctx, size, ink[slot]);
	else
		TGDrawAvatarInitials(initials, size);
	CGContextRestoreGState(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (image)
		[TGAvatarCache() setObject:image forKey:cacheKey cost:TGImageByteCost(image)];
	return image;
}

@end

// vim:ft=objc

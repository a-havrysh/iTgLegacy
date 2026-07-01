#import "TGIcons.h"
#import "TGTheme.h"

static NSMutableDictionary *sCache = nil;

@implementation TGIcons

+ (void)flush {
	[sCache removeAllObjects];
}

/// Every icon goes through here: same size, same cache, same styling rules.
+ (UIImage *)iconNamed:(NSString *)name draw:(void (^)(CGContextRef ctx, CGFloat s))draw {
	if (!sCache)
		sCache = [NSMutableDictionary dictionary];

	BOOL flat = [TGTheme shared].isFlat;
	NSString *key = [NSString stringWithFormat:@"%@-%d", name, (int)flat];
	UIImage *cached = sCache[key];
	if (cached)
		return cached;

	CGFloat side = 28;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	if (!flat){
		// Skeuomorphic glyphs sit on the surface: a soft shadow under, a white
		// highlight one pixel up. Flat ones are the shape and nothing else.
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, 0, 1);
		CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.55f);
		CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.55f);
		draw(ctx, side);
		CGContextRestoreGState(ctx);
	}

	CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
	CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 1);
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
	return [self iconNamed:@"chats" draw:^(CGContextRef ctx, CGFloat s){
		// a speech bubble with a tail
		CGRect body = CGRectMake(3, 5, s - 6, s - 13);
		UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:5];
		[p moveToPoint:CGPointMake(8, CGRectGetMaxY(body) - 1)];
		[p addLineToPoint:CGPointMake(8, CGRectGetMaxY(body) + 5)];
		[p addLineToPoint:CGPointMake(14, CGRectGetMaxY(body) - 1)];
		CGContextAddPath(ctx, p.CGPath);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)contacts {
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
	return [self iconNamed:@"settings" draw:^(CGContextRef ctx, CGFloat s){
		// three sliders
		CGContextSetLineWidth(ctx, 2);
		for (int i = 0; i < 3; i++){
			CGFloat y = 8 + i * 6;
			CGContextMoveToPoint(ctx, 4, y);
			CGContextAddLineToPoint(ctx, s - 4, y);
			CGContextStrokePath(ctx);
			CGContextFillEllipseInRect(ctx,
					CGRectMake(6 + (i == 1 ? 12 : (i == 0 ? 4 : 8)), y - 3, 6, 6));
		}
	}];
}

#pragma mark - actions

+ (UIImage *)compose {
	return [self iconNamed:@"compose" draw:^(CGContextRef ctx, CGFloat s){
		// pencil over a sheet
		CGContextSetLineWidth(ctx, 2);
		CGContextMoveToPoint(ctx, 5, s - 6);
		CGContextAddLineToPoint(ctx, 5, 8);
		CGContextAddLineToPoint(ctx, 15, 8);
		CGContextStrokePath(ctx);

		CGContextMoveToPoint(ctx, 10, s - 8);
		CGContextAddLineToPoint(ctx, s - 6, 5);
		CGContextAddLineToPoint(ctx, s - 3, 8);
		CGContextAddLineToPoint(ctx, 13, s - 5);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)send {
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

+ (UIImage *)ticksWhite:(BOOL)white {
	CGSize size = CGSizeMake(15, 9);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	if (white)
		CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1);
	else
		CGContextSetRGBStrokeColor(ctx, 0.35f, 0.72f, 0.42f, 1);

	CGContextSetLineWidth(ctx, 1.2f);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);

	// back tick, then the front one shifted right - they overlap, which is
	// what makes it read as one mark rather than two symbols.
	CGContextMoveToPoint(ctx, 0.5f, 5.0f);
	CGContextAddLineToPoint(ctx, 3.0f, 7.6f);
	CGContextAddLineToPoint(ctx, 8.4f, 1.4f);
	CGContextStrokePath(ctx);

	CGContextMoveToPoint(ctx, 6.0f, 5.0f);
	CGContextAddLineToPoint(ctx, 8.5f, 7.6f);
	CGContextAddLineToPoint(ctx, 14.0f, 1.4f);
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

#pragma mark - avatars

+ (UIImage *)avatarWithInitials:(NSString *)initials
                           size:(CGFloat)size
                       colourId:(int64_t)colourId
{
	// A blank grey circle tells you nothing; initials on a stable colour let
	// you recognise a row before reading it.
	static NSArray *palette = nil;
	if (!palette)
		palette = @[@[@0.85f, @0.35f, @0.35f], @[@0.30f, @0.60f, @0.85f],
					@[@0.35f, @0.68f, @0.45f], @[@0.85f, @0.60f, @0.25f],
					@[@0.60f, @0.45f, @0.80f], @[@0.30f, @0.65f, @0.68f]];
	NSArray *c = palette[(NSUInteger)llabs(colourId) % palette.count];

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetRGBFillColor(ctx, [c[0] floatValue], [c[1] floatValue],
								  [c[2] floatValue], 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, size, size));

	if (![TGTheme shared].isFlat){
		// a glassy highlight across the top half
		CGContextSaveGState(ctx);
		CGContextAddEllipseInRect(ctx, CGRectMake(0, 0, size, size));
		CGContextClip(ctx);
		CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.20f);
		CGContextFillEllipseInRect(ctx,
				CGRectMake(-size * 0.2f, -size * 0.55f, size * 1.4f, size * 0.95f));
		CGContextRestoreGState(ctx);
	}

	NSString *text = initials.length ? initials : @"?";
	UIFont *font = [UIFont boldSystemFontOfSize:size * 0.4f];
	CGSize textSize = [text sizeWithFont:font];
	[[UIColor whiteColor] set];
	[text drawAtPoint:CGPointMake((size - textSize.width) / 2,
								  (size - textSize.height) / 2)
			 withFont:font];

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

@end

// vim:ft=objc

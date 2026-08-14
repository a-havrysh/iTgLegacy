#import "TGLottieView.h"
#include <zlib.h>

#pragma mark - gunzip

/// .tgs is gzip, and NSData has no unzip on iOS 7, so inflate with zlib.
static NSData *TGGunzip(NSData *input) {
	if (!input.length)
		return nil;

	z_stream stream;
	memset(&stream, 0, sizeof(stream));
	stream.next_in = (Bytef *)input.bytes;
	stream.avail_in = (uInt)input.length;

	// 15 + 32 lets zlib detect gzip or zlib wrapping on its own
	if (inflateInit2(&stream, 15 + 32) != Z_OK)
		return nil;

	NSMutableData *out = [NSMutableData dataWithLength:input.length * 8];
	int status;
	do {
		if (stream.total_out >= out.length)
			[out increaseLengthBy:input.length * 4];
		stream.next_out = (Bytef *)out.mutableBytes + stream.total_out;
		stream.avail_out = (uInt)(out.length - stream.total_out);
		status = inflate(&stream, Z_SYNC_FLUSH);
	} while (status == Z_OK);

	inflateEnd(&stream);
	if (status != Z_STREAM_END)
		return nil;

	[out setLength:stream.total_out];
	return out;
}

#pragma mark - keyframed values

/// Lottie writes a property either as a plain value ("k" is a number or array)
/// or as a list of keyframes. Both collapse to "value at frame f".

static NSArray *TGNumbers(id v) {
	if ([v isKindOfClass:NSArray.class])
		return v;
	if ([v isKindOfClass:NSNumber.class])
		return @[v];
	return nil;
}

/// Interpolate a keyframed property at `frame`. Returns an array of numbers.
static NSArray *TGValueAt(NSDictionary *prop, double frame) {
	if (![prop isKindOfClass:NSDictionary.class])
		return nil;

	id k = prop[@"k"];
	if (!k)
		return nil;

	// static value
	if (![k isKindOfClass:NSArray.class] ||
		![[k firstObject] isKindOfClass:NSDictionary.class])
		return TGNumbers(k);

	NSArray *keys = k;
	NSDictionary *before = nil, *after = nil;

	for (NSDictionary *kf in keys){
		if (![kf isKindOfClass:NSDictionary.class])
			continue;
		double t = [kf[@"t"] doubleValue];
		if (t <= frame)
			before = kf;
		else { after = kf; break; }
	}
	if (!before)
		return TGNumbers([[keys firstObject] objectForKey:@"s"]);
	if (!after)
		return TGNumbers(before[@"s"] ?: before[@"e"]);

	NSArray *from = TGNumbers(before[@"s"]);
	NSArray *to   = TGNumbers(before[@"e"] ?: after[@"s"]);
	if (!from || !to)
		return from ?: to;

	double t0 = [before[@"t"] doubleValue];
	double t1 = [after[@"t"] doubleValue];
	double p = (t1 > t0) ? (frame - t0) / (t1 - t0) : 0.0;
	if (p < 0) p = 0;
	if (p > 1) p = 1;

	// Linear only. Telegram's easing is cubic, so fast-in/out looks slightly
	// more even than intended - visible only in side-by-side comparison.
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:from.count];
	for (NSUInteger i = 0; i < from.count; i++){
		double a = [from[i] doubleValue];
		double b = (i < to.count) ? [to[i] doubleValue] : a;
		[out addObject:@(a + (b - a) * p)];
	}
	return out;
}

static double TGScalarAt(NSDictionary *prop, double frame, double fallback) {
	NSArray *v = TGValueAt(prop, frame);
	return v.count ? [v[0] doubleValue] : fallback;
}

#pragma mark - view

@interface TGLottieView (TGLottieTick)
- (void)tick;
@end

@interface TGLottieTimerProxy : NSObject
@property (nonatomic, weak) TGLottieView *target;
@end

@implementation TGLottieTimerProxy
- (void)tick:(NSTimer *)timer {
	TGLottieView *t = self.target;
	if (t)
		[t tick];
	else
		[timer invalidate];
}
@end

@interface TGLottieView ()
@property (nonatomic, strong) NSDictionary *animation;
@property (nonatomic, strong) NSArray *layers;
@property (nonatomic, assign) double inPoint;
@property (nonatomic, assign) double outPoint;
@property (nonatomic, assign) double frameRate;
@property (nonatomic, assign) CGSize canvas;
@property (nonatomic, assign) double currentFrame;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL wantsPlayback;
@property (nonatomic, strong) NSDictionary *layersByIndex;
@end

@implementation TGLottieView {
	double _cumulativeAlpha;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self){
		self.backgroundColor = [UIColor clearColor];
		self.opaque = NO;
	}
	return self;
}

- (void)dealloc {
	[_timer invalidate];
}

- (BOOL)loadTGSFile:(NSString *)path {
	[self stop];
	self.wantsPlayback = NO;
	self.loaded = NO;
	self.animation = nil;
	self.layers = nil;
	self.layersByIndex = nil;

	if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]){
		[self setNeedsDisplay];
		return NO;
	}

	NSData *raw = [NSData dataWithContentsOfFile:path];
	if (!raw.length){
		[self setNeedsDisplay];
		return NO;
	}

	NSData *json = TGGunzip(raw);
	if (!json.length)
		json = raw;

	NSError *err = nil;
	id parsed = [NSJSONSerialization JSONObjectWithData:json options:0 error:&err];
	if (![parsed isKindOfClass:NSDictionary.class]){
		NSLog(@"TGLottie: bad JSON: %@", err);
		[self setNeedsDisplay];
		return NO;
	}
	NSDictionary *anim = parsed;

	NSArray *layers = anim[@"layers"];
	if (![layers isKindOfClass:NSArray.class])
		layers = nil;

	double ip = [anim[@"ip"] doubleValue];
	double op = [anim[@"op"] doubleValue];
	double fr = [anim[@"fr"] doubleValue];
	CGSize canvas = CGSizeMake([anim[@"w"] doubleValue], [anim[@"h"] doubleValue]);

	if (layers.count == 0 || canvas.width <= 0 || canvas.height <= 0){
		[self setNeedsDisplay];
		return NO;
	}

	NSMutableDictionary *byIndex = [NSMutableDictionary dictionary];
	for (NSDictionary *layer in layers){
		if (![layer isKindOfClass:NSDictionary.class])
			continue;
		id ind = layer[@"ind"];
		if ([ind isKindOfClass:NSNumber.class])
			byIndex[ind] = layer;
	}

	self.animation = anim;
	self.layers    = layers;
	self.layersByIndex = byIndex;
	self.inPoint   = ip;
	self.outPoint  = (op > ip) ? op : (ip + 1.0);
	self.frameRate = (fr > 0.0) ? fr : 60.0;
	self.canvas    = canvas;
	self.currentFrame = ip;
	self.loaded = YES;

	[self setNeedsDisplay];
	return YES;
}

- (void)play {
	self.wantsPlayback = YES;
	[self updatePlaybackState];
}

- (void)stop {
	self.wantsPlayback = NO;
	[self.timer invalidate];
	self.timer = nil;
}

- (void)updatePlaybackState {
	BOOL shouldPlay = self.wantsPlayback && self.loaded && self.window != nil &&
					  !self.hidden && self.alpha > 0.01;

	if (shouldPlay && !self.timer){
		TGLottieTimerProxy *proxy = [[TGLottieTimerProxy alloc] init];
		proxy.target = self;
		// An A5 will not hold 60fps on a vector sticker; 20 is smooth enough and
		// leaves the main thread usable.
		self.timer = [NSTimer timerWithTimeInterval:1.0 / 20.0
											 target:proxy
										   selector:@selector(tick:)
										   userInfo:nil
											repeats:YES];
		[[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
	} else if (!shouldPlay && self.timer){
		[self.timer invalidate];
		self.timer = nil;
	}
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	[self updatePlaybackState];
}

- (void)setHidden:(BOOL)hidden {
	[super setHidden:hidden];
	[self updatePlaybackState];
}

- (void)tick {
	if (!self.loaded)
		return;
	double step = self.frameRate / 20.0;
	if (step <= 0.0)
		step = 1.0;
	self.currentFrame += step;
	if (self.currentFrame >= self.outPoint)
		self.currentFrame = self.inPoint;   // stickers loop
	[self setNeedsDisplay];
}

#pragma mark - drawing

- (void)drawRect:(CGRect)rect {
	if (!self.loaded)
		return;

	CGContextRef ctx = UIGraphicsGetCurrentContext();
	if (!ctx)
		return;
	if (self.canvas.width <= 0 || self.canvas.height <= 0 ||
		self.bounds.size.width <= 0 || self.bounds.size.height <= 0)
		return;

	CGContextSaveGState(ctx);
	_cumulativeAlpha = 1.0;

	// Lottie's origin is top-left in canvas units; scale to fit the view.
	CGFloat scale = MIN(self.bounds.size.width / self.canvas.width,
						self.bounds.size.height / self.canvas.height);
	CGContextTranslateCTM(ctx,
			(self.bounds.size.width - self.canvas.width * scale) / 2,
			(self.bounds.size.height - self.canvas.height * scale) / 2);
	CGContextScaleCTM(ctx, scale, scale);

	// Lottie paints the last layer first.
	for (NSDictionary *layer in [[self.layers reverseObjectEnumerator] allObjects])
		[self drawLottieLayer:layer inContext:ctx];

	CGContextRestoreGState(ctx);
}

// NOT drawLayer:inContext: - that is UIView's CALayerDelegate method, and
// CoreAnimation calls it with a real CALayer when the view renders.
- (void)drawLottieLayer:(NSDictionary *)layer inContext:(CGContextRef)ctx {
	if (![layer isKindOfClass:NSDictionary.class])
		return;

	// type 4 is a shape layer; nothing else is drawable here
	if ([layer[@"ty"] intValue] != 4)
		return;

	if ([layer[@"hd"] boolValue] || [layer[@"td"] intValue] != 0)
		return;

	double frame = self.currentFrame;
	double ip = [layer[@"ip"] doubleValue];
	double op = [layer[@"op"] doubleValue];
	if (frame < ip || frame > op)
		return;

	NSArray *shapes = layer[@"shapes"];
	if (![shapes isKindOfClass:NSArray.class] || shapes.count == 0)
		return;

	double savedAlpha = _cumulativeAlpha;
	CGContextSaveGState(ctx);
	NSArray *chain = [self transformChainForLayer:layer];
	for (NSDictionary *ancestor in chain)
		[self applyTransform:ancestor[@"ks"] atFrame:frame inContext:ctx];
	[self applyTransform:layer[@"ks"] atFrame:frame inContext:ctx];
	[self drawShapes:shapes atFrame:frame inContext:ctx];
	CGContextRestoreGState(ctx);
	_cumulativeAlpha = savedAlpha;
}

- (NSArray *)transformChainForLayer:(NSDictionary *)layer {
	if (self.layersByIndex.count == 0)
		return nil;

	NSMutableArray *chain = nil;
	NSMutableSet *seen = nil;
	id parent = layer[@"parent"];
	int depth = 0;

	while ([parent isKindOfClass:NSNumber.class] && depth < 16){
		NSDictionary *p = self.layersByIndex[parent];
		if (![p isKindOfClass:NSDictionary.class])
			break;
		if (!seen)
			seen = [NSMutableSet set];
		if ([seen containsObject:parent])
			break;
		[seen addObject:parent];

		if (!chain)
			chain = [NSMutableArray array];
		[chain insertObject:p atIndex:0];

		parent = p[@"parent"];
		depth++;
	}

	return chain;
}

- (void)applyTransform:(NSDictionary *)ks atFrame:(double)frame inContext:(CGContextRef)ctx {
	if (![ks isKindOfClass:NSDictionary.class])
		return;

	NSArray *pos    = TGValueAt(ks[@"p"], frame);
	NSArray *anchor = TGValueAt(ks[@"a"], frame);
	NSArray *scale  = TGValueAt(ks[@"s"], frame);
	double rotation = TGScalarAt(ks[@"r"], frame, 0);
	double opacity  = TGScalarAt(ks[@"o"], frame, 100);

	if (pos.count >= 2)
		CGContextTranslateCTM(ctx, [pos[0] doubleValue], [pos[1] doubleValue]);
	if (rotation != 0)
		CGContextRotateCTM(ctx, rotation * M_PI / 180.0);
	if (scale.count >= 2){
		double sx = [scale[0] doubleValue] / 100.0;
		double sy = [scale[1] doubleValue] / 100.0;
		if (sx != 0.0 && sy != 0.0)
			CGContextScaleCTM(ctx, sx, sy);
	}
	if (anchor.count >= 2)
		CGContextTranslateCTM(ctx, -[anchor[0] doubleValue], -[anchor[1] doubleValue]);

	if (opacity < 0) opacity = 0;
	if (opacity > 100) opacity = 100;
	_cumulativeAlpha *= opacity / 100.0;
	CGContextSetAlpha(ctx, _cumulativeAlpha);
}

/// A shape group is a list where paths accumulate and a fill/stroke paints
/// whatever came before it - so build the path first, then look for paint.
- (void)drawShapes:(NSArray *)shapes atFrame:(double)frame inContext:(CGContextRef)ctx {
	if (![shapes isKindOfClass:NSArray.class])
		return;

	CGMutablePathRef path = CGPathCreateMutable();

	for (NSDictionary *shape in shapes){
		if (![shape isKindOfClass:NSDictionary.class] || [shape[@"hd"] boolValue])
			continue;

		NSString *ty = shape[@"ty"];
		if (![ty isKindOfClass:NSString.class])
			continue;

		if ([ty isEqualToString:@"gr"]){
			NSArray *items = shape[@"it"];
			if (![items isKindOfClass:NSArray.class])
				continue;
			double savedAlpha = _cumulativeAlpha;
			CGContextSaveGState(ctx);
			// a group carries its own transform, as the last item
			for (NSDictionary *item in items)
				if ([item isKindOfClass:NSDictionary.class] &&
					[item[@"ty"] isEqualToString:@"tr"])
					[self applyTransform:item atFrame:frame inContext:ctx];
			[self drawShapes:items atFrame:frame inContext:ctx];
			CGContextRestoreGState(ctx);
			_cumulativeAlpha = savedAlpha;

		} else if ([ty isEqualToString:@"sh"]){
			[self appendBezier:shape[@"ks"] atFrame:frame toPath:path];

		} else if ([ty isEqualToString:@"el"]){
			NSArray *p = TGValueAt(shape[@"p"], frame);
			NSArray *s = TGValueAt(shape[@"s"], frame);
			if (p.count >= 2 && s.count >= 2){
				CGRect r = CGRectMake([p[0] doubleValue] - [s[0] doubleValue] / 2,
									  [p[1] doubleValue] - [s[1] doubleValue] / 2,
									  [s[0] doubleValue], [s[1] doubleValue]);
				CGPathAddEllipseInRect(path, NULL, r);
			}

		} else if ([ty isEqualToString:@"rc"]){
			NSArray *p = TGValueAt(shape[@"p"], frame);
			NSArray *s = TGValueAt(shape[@"s"], frame);
			double radius = TGScalarAt(shape[@"r"], frame, 0);
			if (p.count >= 2 && s.count >= 2){
				CGRect r = CGRectMake([p[0] doubleValue] - [s[0] doubleValue] / 2,
									  [p[1] doubleValue] - [s[1] doubleValue] / 2,
									  [s[0] doubleValue], [s[1] doubleValue]);
				if (radius > 0){
					UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:r
																	  cornerRadius:radius];
					CGPathAddPath(path, NULL, rounded.CGPath);
				} else {
					CGPathAddRect(path, NULL, r);
				}
			}

		} else if ([ty isEqualToString:@"fl"]){
			[self fillPath:path withShape:shape atFrame:frame inContext:ctx];

		} else if ([ty isEqualToString:@"st"]){
			[self strokePath:path withShape:shape atFrame:frame inContext:ctx];
		}
	}

	CGPathRelease(path);
}

/// Lottie bezier: "v" vertices, "i"/"o" tangents relative to their vertex.
- (void)appendBezier:(NSDictionary *)ks atFrame:(double)frame toPath:(CGMutablePathRef)path {
	if (![ks isKindOfClass:NSDictionary.class])
		return;

	NSArray *value = nil;
	id k = ks[@"k"];

	if ([k isKindOfClass:NSDictionary.class]){
		value = @[k];
	} else if ([k isKindOfClass:NSArray.class] &&
			   [[k firstObject] isKindOfClass:NSDictionary.class] &&
			   [[k firstObject] objectForKey:@"t"]){
		// keyframed shape: take the last keyframe whose time has passed
		NSDictionary *chosen = [k firstObject];
		for (NSDictionary *kf in k)
			if ([kf isKindOfClass:NSDictionary.class] &&
				[kf[@"t"] doubleValue] <= frame)
				chosen = kf;
		id s = chosen[@"s"];
		value = [s isKindOfClass:NSArray.class] ? s : (s ? @[s] : nil);
	} else if ([k isKindOfClass:NSArray.class]){
		value = k;
	}

	for (NSDictionary *shape in value){
		if (![shape isKindOfClass:NSDictionary.class])
			continue;

		NSArray *v = shape[@"v"], *in = shape[@"i"], *out = shape[@"o"];
		if (![v isKindOfClass:NSArray.class] || v.count < 2 ||
			![in isKindOfClass:NSArray.class] || in.count < v.count ||
			![out isKindOfClass:NSArray.class] || out.count < v.count)
			continue;

		BOOL malformed = NO;
		for (NSUInteger i = 0; i < v.count; i++){
			NSArray *vi = v[i], *ii = in[i], *oi = out[i];
			if (![vi isKindOfClass:NSArray.class] || vi.count < 2 ||
				![ii isKindOfClass:NSArray.class] || ii.count < 2 ||
				![oi isKindOfClass:NSArray.class] || oi.count < 2){
				malformed = YES;
				break;
			}
		}
		if (malformed)
			continue;

		CGPathMoveToPoint(path, NULL, [v[0][0] doubleValue], [v[0][1] doubleValue]);
		for (NSUInteger i = 1; i < v.count; i++){
			NSUInteger p = i - 1;
			CGPathAddCurveToPoint(path, NULL,
				[v[p][0] doubleValue] + [out[p][0] doubleValue],
				[v[p][1] doubleValue] + [out[p][1] doubleValue],
				[v[i][0] doubleValue] + [in[i][0] doubleValue],
				[v[i][1] doubleValue] + [in[i][1] doubleValue],
				[v[i][0] doubleValue], [v[i][1] doubleValue]);
		}

		if ([shape[@"c"] boolValue]){
			NSUInteger last = v.count - 1;
			CGPathAddCurveToPoint(path, NULL,
				[v[last][0] doubleValue] + [out[last][0] doubleValue],
				[v[last][1] doubleValue] + [out[last][1] doubleValue],
				[v[0][0] doubleValue] + [in[0][0] doubleValue],
				[v[0][1] doubleValue] + [in[0][1] doubleValue],
				[v[0][0] doubleValue], [v[0][1] doubleValue]);
			CGPathCloseSubpath(path);
		}
	}
}

- (void)fillPath:(CGPathRef)path withShape:(NSDictionary *)shape
		 atFrame:(double)frame inContext:(CGContextRef)ctx {
	NSArray *c = TGValueAt(shape[@"c"], frame);
	if (c.count < 3 || CGPathIsEmpty(path))
		return;

	double alpha = TGScalarAt(shape[@"o"], frame, 100) / 100.0;
	if (alpha <= 0.0)
		return;
	if (alpha > 1.0)
		alpha = 1.0;

	CGContextSetRGBFillColor(ctx, [c[0] doubleValue], [c[1] doubleValue],
								  [c[2] doubleValue], alpha);
	CGContextAddPath(ctx, path);

	// Lottie fills use even-odd, which is what makes holes work.
	if ([shape[@"r"] intValue] == 1)
		CGContextFillPath(ctx);
	else
		CGContextEOFillPath(ctx);
}

- (void)strokePath:(CGPathRef)path withShape:(NSDictionary *)shape
		   atFrame:(double)frame inContext:(CGContextRef)ctx {
	NSArray *c = TGValueAt(shape[@"c"], frame);
	if (c.count < 3 || CGPathIsEmpty(path))
		return;

	double alpha = TGScalarAt(shape[@"o"], frame, 100) / 100.0;
	double width = TGScalarAt(shape[@"w"], frame, 1);
	if (alpha <= 0.0 || width <= 0.0)
		return;
	if (alpha > 1.0)
		alpha = 1.0;

	CGContextSetRGBStrokeColor(ctx, [c[0] doubleValue], [c[1] doubleValue],
									[c[2] doubleValue], alpha);
	CGContextSetLineWidth(ctx, width);

	switch ([shape[@"lc"] intValue]){
		case 2:  CGContextSetLineCap(ctx, kCGLineCapRound);  break;
		case 3:  CGContextSetLineCap(ctx, kCGLineCapSquare); break;
		default: CGContextSetLineCap(ctx, kCGLineCapButt);   break;
	}
	switch ([shape[@"lj"] intValue]){
		case 2:  CGContextSetLineJoin(ctx, kCGLineJoinRound); break;
		case 3:  CGContextSetLineJoin(ctx, kCGLineJoinBevel); break;
		default: CGContextSetLineJoin(ctx, kCGLineJoinMiter); break;
	}
	double miter = TGScalarAt(shape[@"ml"], frame, 0);
	if (miter > 0)
		CGContextSetMiterLimit(ctx, miter);
	CGContextAddPath(ctx, path);
	CGContextStrokePath(ctx);
}

@end

// vim:ft=objc

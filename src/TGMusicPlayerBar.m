#import "TGMusicPlayerBar.h"
#import "TGMusicPlayer.h"
#import "TGTheme.h"

static const CGFloat kBarHeight  = 37.0f;
static const CGFloat kLineHeight = 2.0f;
static const CGFloat kGlyphSide  = 24.0f;

static TGMusicPlayerBar *sBar = nil;

#pragma mark - glyphs

static NSMutableDictionary *sGlyphs = nil;

static UIImage *TGMusicGlyph(NSString *name, UIColor *colour) {
	if (!sGlyphs)
		sGlyphs = [NSMutableDictionary dictionary];
	NSString *key = [NSString stringWithFormat:@"%@-%@", name, colour];
	UIImage *cached = sGlyphs[key];
	if (cached)
		return cached;

	const CGFloat s = kGlyphSide;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(ctx, colour.CGColor);
	CGContextSetStrokeColorWithColor(ctx, colour.CGColor);

	if ([name isEqualToString:@"play"]){
		CGContextMoveToPoint(ctx, 7, 4);
		CGContextAddLineToPoint(ctx, s - 6, s / 2);
		CGContextAddLineToPoint(ctx, 7, s - 4);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	} else if ([name isEqualToString:@"pause"]){
		CGContextFillRect(ctx, CGRectMake(7, 4, 3.5f, s - 8));
		CGContextFillRect(ctx, CGRectMake(s - 10.5f, 4, 3.5f, s - 8));
	} else if ([name isEqualToString:@"previous"] || [name isEqualToString:@"next"]){
		BOOL back = [name isEqualToString:@"previous"];
		CGContextSaveGState(ctx);
		if (back){
			CGContextTranslateCTM(ctx, s, 0);
			CGContextScaleCTM(ctx, -1, 1);
		}
		for (int i = 0; i < 2; i++){
			CGFloat x = 4 + i * 7.0f;
			CGContextMoveToPoint(ctx, x, 5);
			CGContextAddLineToPoint(ctx, x + 6.5f, s / 2);
			CGContextAddLineToPoint(ctx, x, s - 5);
			CGContextClosePath(ctx);
		}
		CGContextFillPath(ctx);
		CGContextFillRect(ctx, CGRectMake(s - 6, 5, 2.5f, s - 10));
		CGContextRestoreGState(ctx);
	} else if ([name isEqualToString:@"close"]){
		CGContextSetLineWidth(ctx, 1.5f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextMoveToPoint(ctx, 7, 7);
		CGContextAddLineToPoint(ctx, s - 7, s - 7);
		CGContextMoveToPoint(ctx, s - 7, 7);
		CGContextAddLineToPoint(ctx, 7, s - 7);
		CGContextStrokePath(ctx);
	}

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	sGlyphs[key] = image;
	return image;
}

#pragma mark - hierarchy probes

static CGFloat TGNavigationBarBottom(UIView *host, UIView *view, int depth) {
	if (depth > 8 || view.hidden || view.alpha < 0.05f)
		return 0;
	if ([view isKindOfClass:UINavigationBar.class]){
		CGRect frame = [view convertRect:view.bounds toView:host];
		return CGRectGetMaxY(frame);
	}
	CGFloat best = 0;
	for (UIView *child in view.subviews){
		CGFloat bottom = TGNavigationBarBottom(host, child, depth + 1);
		if (bottom > best)
			best = bottom;
	}
	return best;
}

static UIScrollView *TGFrontmostScrollView(UIView *view, int depth) {
	if (depth > 7 || view.hidden || view.alpha < 0.05f || view.window == nil)
		return nil;
	if ([view isKindOfClass:UIScrollView.class] && view.bounds.size.height > 120)
		return (UIScrollView *)view;
	for (UIView *child in [view.subviews reverseObjectEnumerator]){
		UIScrollView *found = TGFrontmostScrollView(child, depth + 1);
		if (found)
			return found;
	}
	return nil;
}

#pragma mark -

@implementation TGMusicPlayerBar {
	UIButton *_previous;
	UIButton *_toggle;
	UIButton *_next;
	UIButton *_close;
	UILabel  *_title;
	UILabel  *_performer;
	UIView   *_track;
	UIView   *_progress;
	UIView   *_hairline;
	NSTimer  *_anchorTimer;
	__weak UIScrollView *_insetView;
	BOOL      _insetApplied;
	BOOL      _scrubbing;
	CGFloat   _scrubFraction;
}

+ (CGFloat)barHeight {
	return kBarHeight;
}

+ (void)activate {
	if (sBar)
		return;
	sBar = [[TGMusicPlayerBar alloc] initWithFrame:
			CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, kBarHeight)];
	[sBar sync];
}

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame]))
		return nil;

	self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.clipsToBounds = YES;

	_previous = [self buttonWithGlyph:@"previous" action:@selector(previousTapped)];
	_toggle   = [self buttonWithGlyph:@"pause"    action:@selector(toggleTapped)];
	_next     = [self buttonWithGlyph:@"next"     action:@selector(nextTapped)];
	_close    = [self buttonWithGlyph:@"close"    action:@selector(closeTapped)];

	_title = [[UILabel alloc] initWithFrame:CGRectZero];
	_title.backgroundColor = [UIColor clearColor];
	_title.font = [UIFont boldSystemFontOfSize:13];
	[self addSubview:_title];

	_performer = [[UILabel alloc] initWithFrame:CGRectZero];
	_performer.backgroundColor = [UIColor clearColor];
	_performer.font = [UIFont systemFontOfSize:11];
	[self addSubview:_performer];

	_track = [[UIView alloc] initWithFrame:CGRectZero];
	[self addSubview:_track];

	_progress = [[UIView alloc] initWithFrame:CGRectZero];
	[self addSubview:_progress];

	_hairline = [[UIView alloc] initWithFrame:CGRectZero];
	[self addSubview:_hairline];

	UIPanGestureRecognizer *scrub = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(scrubbed:)];
	[self addGestureRecognizer:scrub];

	NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];
	[centre addObserver:self selector:@selector(playerNotified:)
				   name:TGMusicPlayerStateChangedNotification object:nil];
	[centre addObserver:self selector:@selector(progressNotified:)
				   name:TGMusicPlayerProgressNotification object:nil];
	[centre addObserver:self selector:@selector(themeNotified:)
				   name:TGThemeChangedNotification object:nil];
	[centre addObserver:self selector:@selector(backgroundNotified:)
				   name:UIApplicationDidEnterBackgroundNotification object:nil];
	[centre addObserver:self selector:@selector(rotationNotified:)
				   name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
	[centre addObserver:self selector:@selector(playerNotified:)
				   name:UIApplicationWillEnterForegroundNotification object:nil];

	[self restyle];
	return self;
}

- (void)dealloc {
	[_anchorTimer invalidate];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIButton *)buttonWithGlyph:(NSString *)glyph action:(SEL)action {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.showsTouchWhenHighlighted = NO;
	button.adjustsImageWhenHighlighted = YES;
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	button.accessibilityLabel = glyph;
	[self addSubview:button];
	return button;
}

#pragma mark - notifications

- (void)playerNotified:(NSNotification *)note     { [self sync]; }
- (void)progressNotified:(NSNotification *)note   { [self progressed]; }
- (void)themeNotified:(NSNotification *)note      { [self restyle]; }
- (void)backgroundNotified:(NSNotification *)note { [self suspendAnchoring]; }
- (void)rotationNotified:(NSNotification *)note   { if (self.superview) [self reanchor]; }

#pragma mark - appearance

- (void)restyle {
	[sGlyphs removeAllObjects];
	TGTheme *theme = [TGTheme shared];
	self.backgroundColor = [theme inputBarColour];
	_title.textColor = [theme primaryTextColour];
	_performer.textColor = [theme secondaryTextColour];
	_track.backgroundColor = [theme separatorColour];
	_progress.backgroundColor = [theme accentColour];
	_hairline.backgroundColor = [theme separatorColour];

	UIColor *ink = [theme accentColour];
	[_previous setImage:TGMusicGlyph(@"previous", ink) forState:UIControlStateNormal];
	[_next setImage:TGMusicGlyph(@"next", ink) forState:UIControlStateNormal];
	[_close setImage:TGMusicGlyph(@"close", [theme secondaryTextColour])
			forState:UIControlStateNormal];
	[self syncToggleGlyph];
}

- (void)syncToggleGlyph {
	UIColor *ink = [[TGTheme shared] accentColour];
	[_toggle setImage:TGMusicGlyph([TGMusicPlayer shared].isPlaying ? @"pause" : @"play", ink)
			 forState:UIControlStateNormal];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.bounds.size.width;
	CGFloat row = kBarHeight - kLineHeight;

	_previous.frame = CGRectMake(2, 0, 32, row);
	_toggle.frame   = CGRectMake(34, 0, 34, row);
	_next.frame     = CGRectMake(68, 0, 32, row);
	_close.frame    = CGRectMake(w - 34, 0, 32, row);

	CGFloat left  = 106;
	CGFloat width = MAX((CGFloat)40, w - left - 40);
	BOOL twoLines = _performer.text.length > 0;
	if (twoLines){
		_title.frame     = CGRectMake(left, 2, width, 16);
		_performer.frame = CGRectMake(left, 18, width, 14);
	} else {
		_title.frame     = CGRectMake(left, (row - 17) / 2, width, 17);
		_performer.frame = CGRectZero;
	}
	_performer.hidden = !twoLines;

	_track.frame    = CGRectMake(0, row, w, kLineHeight);
	_hairline.frame = CGRectMake(0, kBarHeight - 0.5f, w, 0.5f);
	[self layoutProgress];
}

- (void)layoutProgress {
	CGFloat fraction = _scrubbing ? _scrubFraction : [TGMusicPlayer shared].playedFraction;
	fraction = MAX((CGFloat)0, MIN((CGFloat)1, fraction));
	_progress.frame = CGRectMake(0, kBarHeight - kLineHeight,
								 self.bounds.size.width * fraction, kLineHeight);
}

#pragma mark - placement

- (UIView *)host {
	UIWindow *window = [UIApplication sharedApplication].keyWindow;
	if (!window)
		window = [[UIApplication sharedApplication].windows count]
				? [UIApplication sharedApplication].windows[0] : nil;
	return window.rootViewController.view;
}

- (void)reanchor {
	UIView *host = [self host];
	if (!host){
		[self detach];
		return;
	}
	if (self.superview != host){
		[self dropInset];
		[host addSubview:self];
	} else {
		[host bringSubviewToFront:self];
	}

	CGFloat top = TGNavigationBarBottom(host, host, 0);
	if (top <= 0){
		BOOL pad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
		BOOL landscape = UIInterfaceOrientationIsLandscape(
				[UIApplication sharedApplication].statusBarOrientation);
		top = (!pad && landscape) ? 32 : 44;
	}
	self.frame = CGRectMake(0, top, host.bounds.size.width, kBarHeight);
	[self applyInset];
}

- (void)applyInset {
	UIView *host = [self host];
	UIScrollView *wanted = host ? TGFrontmostScrollView(host, 0) : nil;
	if (wanted == self.superview)
		wanted = nil;
	if (wanted == _insetView)
		return;
	[self dropInset];
	if (!wanted)
		return;
	UIEdgeInsets insets = wanted.contentInset;
	insets.top += kBarHeight;
	wanted.contentInset = insets;
	wanted.scrollIndicatorInsets = insets;
	_insetView = wanted;
	_insetApplied = YES;
}

- (void)dropInset {
	UIScrollView *previous = _insetView;
	if (previous && _insetApplied){
		UIEdgeInsets insets = previous.contentInset;
		insets.top -= kBarHeight;
		previous.contentInset = insets;
		previous.scrollIndicatorInsets = insets;
	}
	_insetView = nil;
	_insetApplied = NO;
}

- (void)detach {
	[self suspendAnchoring];
	[self dropInset];
	[self removeFromSuperview];
}

- (void)suspendAnchoring {
	[_anchorTimer invalidate];
	_anchorTimer = nil;
}

#pragma mark - state

- (void)sync {
	TGMusicPlayer *player = [TGMusicPlayer shared];
	NSDictionary *track = player.currentTrack;
	if (!track){
		[self detach];
		return;
	}

	NSString *title = track[TGMusicTrackTitle];
	NSString *performer = track[TGMusicTrackPerformer];
	_title.text = title.length ? title : @"Audio";
	_performer.text = player.isLoading ? @"Loading…" : (performer.length ? performer : @"");

	BOOL alone = (player.playlist.count < 2);
	_previous.enabled = !alone;
	_next.enabled = !alone;
	_previous.alpha = alone ? 0.35f : 1.0f;
	_next.alpha = alone ? 0.35f : 1.0f;
	[self syncToggleGlyph];

	[self reanchor];
	[self setNeedsLayout];

	if (!_anchorTimer){
		_anchorTimer = [NSTimer scheduledTimerWithTimeInterval:0.8
														target:self
													  selector:@selector(reanchor)
													  userInfo:nil
													   repeats:YES];
	}
}

- (void)progressed {
	if (_scrubbing)
		return;
	[self layoutProgress];
}

#pragma mark - controls

- (void)toggleTapped   { [[TGMusicPlayer shared] toggle]; }
- (void)nextTapped     { [[TGMusicPlayer shared] playNext]; }
- (void)previousTapped { [[TGMusicPlayer shared] playPrevious]; }
- (void)closeTapped    { [[TGMusicPlayer shared] stop]; }

- (void)scrubbed:(UIPanGestureRecognizer *)pan {
	CGFloat width = self.bounds.size.width;
	if (width <= 0)
		return;
	CGFloat x = [pan locationInView:self].x;
	_scrubFraction = MAX((CGFloat)0, MIN((CGFloat)1, x / width));

	if (pan.state == UIGestureRecognizerStateBegan ||
		pan.state == UIGestureRecognizerStateChanged){
		_scrubbing = YES;
		[self layoutProgress];
		return;
	}
	if (pan.state != UIGestureRecognizerStateEnded &&
		pan.state != UIGestureRecognizerStateCancelled &&
		pan.state != UIGestureRecognizerStateFailed)
		return;

	_scrubbing = NO;
	if (pan.state == UIGestureRecognizerStateEnded)
		[[TGMusicPlayer shared] seekToFraction:_scrubFraction];
	[self layoutProgress];
}

@end

#import "TGSnackbar.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "UIView+SafeTint.h"

// Their snackbar at 360dp: a 48 tall plate inset 8, a 24 countdown ring at 16
// from the left, the wording at 15, UNDO on the right in blue.
static const CGFloat kBarHeight = 53.0f;
static const CGFloat kBarInset  = 0.0f;
static const CGFloat kRingSide  = 22.0f;
static const CGFloat kButtonWidth  = 96.0f;
static const CGFloat kButtonHeight = 32.0f;

static TGSnackbar *sOpenBar = nil;

@interface TGSnackbar () <UIGestureRecognizerDelegate>
@end

@implementation TGSnackbar {
	NSTimer *_tick;
	CGFloat _left;
	CGFloat _total;
	NSInteger _shown;
	void (^_commit)(void);
	UILabel *_count;
	CAShapeLayer *_ring;
	UIButton *_undo;
	BOOL _finished;
	BOOL _wasInWindow;
	CGFloat _dragOffset;
}

+ (void)commitNow {
	TGSnackbar *bar = sOpenBar;
	if (!bar)
		return;
	[bar finishCommitting:YES animated:YES];
}

- (void)finishCommitting:(BOOL)runCommit animated:(BOOL)animated {
	if (_finished)
		return;
	_finished = YES;
	if (sOpenBar == self)
		sOpenBar = nil;
	[_tick invalidate];
	_tick = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	self.userInteractionEnabled = NO;
	void (^commit)(void) = _commit;
	_commit = nil;

	if (animated && self.superview) {
		UIView *me = self;
		[UIView animateWithDuration:0.2
						 animations:^{ me.alpha = 0.0f; }
						 completion:^(BOOL done){ [me removeFromSuperview]; }];
	} else {
		[self removeFromSuperview];
	}

	if (runCommit && commit)
		commit();
}

+ (void)showInView:(UIView *)host
              text:(NSString *)text
           seconds:(NSInteger)seconds
          onCommit:(void (^)(void))commit
{
	if (!host)
		return;
	// Whatever was waiting has now really happened; only one can be pending.
	[self commitNow];

	CGRect b = host.bounds;
	TGSnackbar *bar = [[TGSnackbar alloc] initWithFrame:CGRectMake(
			kBarInset, b.size.height - kBarHeight - kBarInset,
			b.size.width - 2 * kBarInset, kBarHeight)];
	bar->_total = (CGFloat)MAX((NSInteger)1, seconds);
	bar->_left = bar->_total;
	bar->_shown = (NSInteger)bar->_total;
	bar->_commit = [commit copy];
	bar.autoresizingMask = UIViewAutoresizingFlexibleWidth |
						   UIViewAutoresizingFlexibleTopMargin;
	[bar buildWithText:text];
	[host addSubview:bar];
	sOpenBar = bar;

	// Up from below the edge, the way it arrives in their design.
	CGRect resting = bar.frame;
	bar.frame = CGRectOffset(resting, 0, kBarHeight + kBarInset);
	[UIView animateWithDuration:0.2 animations:^{ bar.frame = resting; }];

	bar->_tick = [NSTimer timerWithTimeInterval:0.5
										 target:bar
									   selector:@selector(second)
									   userInfo:nil
										repeats:YES];
	[[NSRunLoop mainRunLoop] addTimer:bar->_tick forMode:NSRunLoopCommonModes];

	[[NSNotificationCenter defaultCenter] addObserver:bar
											 selector:@selector(appLeaving)
												 name:UIApplicationDidEnterBackgroundNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:bar
											 selector:@selector(appLeaving)
												 name:UIApplicationWillTerminateNotification
											   object:nil];
}

- (void)appLeaving {
	[self finishCommitting:YES animated:NO];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window)
		_wasInWindow = YES;
}

- (void)willMoveToWindow:(UIWindow *)window {
	[super willMoveToWindow:window];
	if (!window && _wasInWindow && !_finished)
		[self finishCommitting:YES animated:NO];
}

- (void)dealloc {
	[_tick invalidate];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildWithText:(NSString *)text {
	// steel-gray_dark, which is what their plate is - it has to read over both
	// a light and a dark chat.
	self.backgroundColor = [UIColor colorWithRed:0.20f green:0.22f blue:0.24f alpha:1.0f];
	self.clipsToBounds = YES;

	UIImage *plate = [UIImage imageNamed:@"ConversationActionBar.png"];
	if (plate) {
		UIImageView *plateView = [[UIImageView alloc] initWithFrame:self.bounds];
		plateView.image = [plate stretchableImageWithLeftCapWidth:(int)(plate.size.width / 2)
													topCapHeight:0];
		plateView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
									 UIViewAutoresizingFlexibleHeight;
		[self addSubview:plateView];
	}

	CGRect ring = CGRectMake(12, (kBarHeight - kRingSide) / 2, kRingSide, kRingSide);
	_ring = [CAShapeLayer layer];
	_ring.frame = ring;
	_ring.path = [UIBezierPath bezierPathWithOvalInRect:
			CGRectInset(CGRectMake(0, 0, kRingSide, kRingSide), 1, 1)].CGPath;
	_ring.fillColor = [UIColor clearColor].CGColor;
	_ring.strokeColor = [UIColor whiteColor].CGColor;
	_ring.lineWidth = 1.5f;
	// Wound from the top and unwinding as the seconds go, so the plate says how
	// long is left without anyone having to read the number.
	_ring.strokeEnd = 1.0f;
	_ring.transform = CATransform3DMakeRotation(-M_PI_2, 0, 0, 1);
	[self.layer addSublayer:_ring];

	_count = [[UILabel alloc] initWithFrame:ring];
	_count.textAlignment = NSTextAlignmentCenter;
	_count.font = [UIFont boldSystemFontOfSize:12];
	_count.textColor = [UIColor whiteColor];
	_count.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.4f];
	_count.shadowOffset = CGSizeMake(0, -1);
	_count.backgroundColor = [UIColor clearColor];
	_count.text = [NSString stringWithFormat:@"%ld", (long)_shown];
	[self addSubview:_count];

	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
			42, 0, self.bounds.size.width - 42 - kButtonWidth - 16, kBarHeight)];
	label.text = ([text isKindOfClass:[NSString class]] && text.length > 0) ? text : @"Done";
	label.numberOfLines = 1;
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	label.font = [UIFont systemFontOfSize:13];
	label.textColor = [UIColor whiteColor];
	label.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.4f];
	label.shadowOffset = CGSizeMake(0, -1);
	label.backgroundColor = [UIColor clearColor];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self addSubview:label];

	UIButton *undo = [UIButton buttonWithType:UIButtonTypeCustom];
	undo.frame = CGRectMake(self.bounds.size.width - kButtonWidth - 8,
			(int)((kBarHeight - kButtonHeight) / 2), kButtonWidth, kButtonHeight);
	undo.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	undo.exclusiveTouch = YES;
	undo.adjustsImageWhenHighlighted = NO;
	undo.adjustsImageWhenDisabled = NO;

	UIImage *normal = [UIImage imageNamed:@"ActionForward_Button.png"];
	UIImage *pressed = [UIImage imageNamed:@"ActionForward_Button_Pressed.png"];
	if (normal)
		[undo setBackgroundImage:[normal stretchableImageWithLeftCapWidth:(int)(normal.size.width / 2)
															topCapHeight:0]
						forState:UIControlStateNormal];
	if (pressed)
		[undo setBackgroundImage:[pressed stretchableImageWithLeftCapWidth:(int)(pressed.size.width / 2)
															 topCapHeight:0]
						forState:UIControlStateHighlighted];

	[undo setTitle:@"Undo" forState:UIControlStateNormal];
	[undo setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	undo.titleLabel.font = [UIFont boldSystemFontOfSize:13];
	undo.titleLabel.shadowColor = [UIColor colorWithRed:0x3c / 255.0f
												  green:0x66 / 255.0f
												   blue:0x96 / 255.0f
												  alpha:0.5f];
	undo.titleLabel.shadowOffset = CGSizeMake(0, -1);
	[undo addTarget:self action:@selector(undoTapped)
   forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:undo];
	_undo = undo;

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(plateTapped)];
	tap.delegate = self;
	[self addGestureRecognizer:tap];

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(plateDragged:)];
	[self addGestureRecognizer:pan];
}

- (void)second {
	if (_finished)
		return;
	_left -= 0.5f;
	if (_left <= 0.0f) {
		[self finishCommitting:YES animated:YES];
		return;
	}
	NSInteger whole = (NSInteger)ceilf(_left);
	if (whole != _shown) {
		_shown = whole;
		_count.text = [NSString stringWithFormat:@"%ld", (long)_shown];
	}
	_ring.strokeEnd = MAX(0.02f, _left / _total);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
	   shouldReceiveTouch:(UITouch *)touch
{
	if (_undo && touch.view && [touch.view isDescendantOfView:_undo])
		return NO;
	return YES;
}

- (void)plateTapped {
	[self finishCommitting:YES animated:YES];
}

- (void)plateDragged:(UIPanGestureRecognizer *)pan {
	if (_finished)
		return;
	CGPoint t = [pan translationInView:self];
	if (pan.state == UIGestureRecognizerStateChanged) {
		CGFloat dy = MAX(0.0f, t.y);
		self.transform = CGAffineTransformMakeTranslation(0.0f, dy);
		_dragOffset = dy;
	} else if (pan.state == UIGestureRecognizerStateEnded ||
			   pan.state == UIGestureRecognizerStateCancelled) {
		CGFloat v = [pan velocityInView:self].y;
		if (_dragOffset > kBarHeight / 3.0f || v > 300.0f) {
			[self finishCommitting:YES animated:YES];
		} else {
			_dragOffset = 0.0f;
			UIView *me = self;
			[UIView animateWithDuration:0.15
							 animations:^{ me.transform = CGAffineTransformIdentity; }];
		}
	}
}

- (void)undoTapped {
	if (_finished)
		return;
	_undo.enabled = NO;
	[self finishCommitting:NO animated:YES];
}

@end

// vim:ft=objc

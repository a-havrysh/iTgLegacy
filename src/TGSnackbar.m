#import "TGSnackbar.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "UIView+SafeTint.h"

static const CGFloat kBarHeight = 55.0f;
static const CGFloat kBarInset  = 0.0f;
static const CGFloat kBadgeHeight = 21.0f;
static const CGFloat kBadgeMinWidth = 27.0f;
static const CGFloat kBadgeLeft = 9.0f;
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
	UIImageView *_badge;
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
	CGFloat retinaPixel = ([UIScreen mainScreen].scale > 1.0f) ? 0.5f : 0.0f;
	self.backgroundColor = [UIColor clearColor];
	self.clipsToBounds = YES;

	UIImage *plate = [UIImage imageNamed:@"ConversationActionBar.png"];
	if (plate) {
		UIImageView *plateView = [[UIImageView alloc] initWithFrame:self.bounds];
		plateView.image = [plate stretchableImageWithLeftCapWidth:(int)(plate.size.width / 2)
													topCapHeight:0];
		plateView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
									 UIViewAutoresizingFlexibleHeight;
		[self addSubview:plateView];
	} else {
		self.backgroundColor = [UIColor colorWithRed:0.20f green:0.22f blue:0.24f alpha:1.0f];
	}

	UIImage *badgeImage = [UIImage imageNamed:@"DialogListUnreadBadge.png"];
	if (badgeImage) {
		_badge = [[UIImageView alloc] initWithImage:
				[badgeImage stretchableImageWithLeftCapWidth:(int)(badgeImage.size.width / 2)
											   topCapHeight:(int)(badgeImage.size.height / 2)]];
		[self addSubview:_badge];
	}

	_count = [[UILabel alloc] initWithFrame:CGRectZero];
	_count.textAlignment = NSTextAlignmentCenter;
	_count.font = [UIFont boldSystemFontOfSize:14];
	_count.textColor = [UIColor whiteColor];
	_count.shadowColor = [UIColor colorWithRed:0x80 / 255.0f
										 green:0x91 / 255.0f
										  blue:0xa6 / 255.0f
										 alpha:1.0f];
	_count.shadowOffset = CGSizeMake(0, -1);
	_count.backgroundColor = [UIColor clearColor];
	_count.text = [NSString stringWithFormat:@"%ld", (long)_shown];
	[self addSubview:_count];
	[self layoutCountdown];

	CGFloat textLeft = kBadgeLeft + kBadgeMinWidth + 8.0f;
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
			textLeft, 0, self.bounds.size.width - textLeft - kButtonWidth - 16, kBarHeight)];
	label.text = ([text isKindOfClass:[NSString class]] && text.length > 0) ? text : @"Done";
	label.numberOfLines = 1;
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	label.font = [UIFont boldSystemFontOfSize:13];
	label.textColor = [UIColor whiteColor];
	label.shadowColor = [UIColor colorWithRed:0x0e / 255.0f
										green:0x28 / 255.0f
										 blue:0x4d / 255.0f
										alpha:0.4f];
	label.shadowOffset = CGSizeMake(0, -1);
	label.backgroundColor = [UIColor clearColor];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self addSubview:label];

	UIButton *undo = [UIButton buttonWithType:UIButtonTypeCustom];
	undo.frame = CGRectMake(self.bounds.size.width - kButtonWidth - 9,
			(int)((kBarHeight - kButtonHeight) / 2) + retinaPixel,
			kButtonWidth, kButtonHeight);
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

- (void)layoutCountdown {
	CGSize size = [_count.text sizeWithFont:_count.font];
	CGFloat width = MAX(kBadgeMinWidth, size.width + 10.0f);
	CGRect frame = CGRectMake(kBadgeLeft, (int)((kBarHeight - kBadgeHeight) / 2),
			width, kBadgeHeight);
	_badge.frame = frame;
	_count.frame = frame;
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
		[self layoutCountdown];
	}
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

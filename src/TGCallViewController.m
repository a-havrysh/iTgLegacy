#import "TGCallViewController.h"
#import "TGCall.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"

@interface TGCallViewController ()
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSString *peerName;
@property (nonatomic, assign) BOOL outgoing;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UIButton *endButton;
@property (nonatomic, strong) UIButton *acceptButton;
@property (nonatomic, strong) NSTimer *ticker;
@property (nonatomic, assign) BOOL dismissing;
@property (nonatomic, assign) BOOL proximityWasEnabled;
@property (nonatomic, assign) BOOL idleTimerWasDisabled;
@end

@implementation TGCallViewController

+ (void)presentForUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing {
	UIWindow *window = [UIApplication sharedApplication].keyWindow;
	if (window == nil)
		window = [[UIApplication sharedApplication].windows count] ? [[UIApplication sharedApplication].windows objectAtIndex:0] : nil;
	UIViewController *top = window.rootViewController;
	if (top == nil)
		return;
	while (top.presentedViewController)
		top = top.presentedViewController;

	if ([top isKindOfClass:[TGCallViewController class]])
		return;
	if ([top isBeingPresented] || [top isBeingDismissed])
		return;

	TGCallViewController *screen = [[TGCallViewController alloc]
			initWithUserId:userId name:name outgoing:outgoing];
	screen.modalPresentationStyle = UIModalPresentationFullScreen;
	[top presentViewController:screen animated:YES completion:nil];
}

- (instancetype)initWithUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing {
	if ((self = [super init])){
		_userId = userId;
		_peerName = [(name ?: @"") stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		_outgoing = outgoing;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// A call screen is its own thing in every client: dark, centred, and with
	// nothing on it but who and how long.
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];

	CGRect b = self.view.bounds;
	CGFloat side = 96;
	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake((b.size.width - side) / 2, 70, side, side)];
	self.avatarView.layer.cornerRadius = side * 0.12f;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.image = [TGIcons avatarWithInitials:[self initials]
												   size:side colourId:self.userId];
	[self.view addSubview:self.avatarView];

	self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(9, 180, b.size.width - 18, 24)];
	self.nameLabel.text = self.peerName.length ? self.peerName : @"Unknown";
	self.nameLabel.adjustsFontSizeToFitWidth = YES;
	if ([self.nameLabel respondsToSelector:@selector(setMinimumScaleFactor:)])
		self.nameLabel.minimumScaleFactor = 0.7f;
	self.nameLabel.font = [UIFont boldSystemFontOfSize:19];
	self.nameLabel.textColor = [UIColor colorWithRed:0x22 / 255.0f green:0x29 / 255.0f blue:0x32 / 255.0f alpha:1.0f];
	self.nameLabel.shadowColor = [UIColor colorWithRed:0xed / 255.0f green:0xf0 / 255.0f blue:0xf5 / 255.0f alpha:0.28f];
	self.nameLabel.shadowOffset = CGSizeMake(0, 1);
	self.nameLabel.textAlignment = NSTextAlignmentCenter;
	self.nameLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.nameLabel];

	self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(9, 208, b.size.width - 18, 24)];
	self.statusLabel.font = [UIFont systemFontOfSize:14];
	self.statusLabel.textColor = [UIColor colorWithRed:0x6d / 255.0f green:0x7d / 255.0f blue:0x90 / 255.0f alpha:1.0f];
	self.statusLabel.shadowColor = [UIColor colorWithRed:0xed / 255.0f green:0xf0 / 255.0f blue:0xf5 / 255.0f alpha:0.28f];
	self.statusLabel.shadowOffset = CGSizeMake(0, 1);
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.statusLabel];

	CGFloat buttonHeight = 43;
	CGFloat buttonWidth = (CGFloat)(int)((b.size.width - 9 * 2 - 8) / 2);
	CGFloat buttonY = b.size.height - 20 - buttonHeight;
	CGRect leftFrame = CGRectMake(9, buttonY, buttonWidth, buttonHeight);
	CGRect rightFrame = CGRectMake(b.size.width - 9 - buttonWidth, buttonY, buttonWidth, buttonHeight);

	self.muteButton = [self buttonWithTitle:@"Mute"
									  asset:@"GroupedActionButton"
									  frame:leftFrame
									 action:@selector(toggleMute)];
	self.endButton = [self buttonWithTitle:@"End"
									 asset:@"MenuRedButton"
									 frame:rightFrame
									action:@selector(end)];

	// An incoming call needs an answer button where mute would be.
	if (!self.outgoing){
		self.acceptButton = [self buttonWithTitle:@"Answer"
											asset:@"GroupedActionButtonGreen"
											frame:leftFrame
										   action:@selector(answer)];
		self.muteButton.hidden = YES;
	}

	self.idleTimerWasDisabled = [UIApplication sharedApplication].idleTimerDisabled;
	[UIApplication sharedApplication].idleTimerDisabled = YES;

	__weak typeof(self) weakSelf = self;
	[TGCall shared].onStateChanged = ^(TGCallState state){
		TGCallViewController *strongSelf = weakSelf;
		if (strongSelf == nil || strongSelf.dismissing)
			return;
		[strongSelf applyState:state];
	};

	TGCallState current = [TGCall shared].state;
	if (self.outgoing && current != TGCallStatePending
			&& current != TGCallStateExchangingKeys
			&& current != TGCallStateConnecting
			&& current != TGCallStateEstablished)
		[[TGCall shared] callUser:self.userId];
	[self applyState:[TGCall shared].state];

	self.ticker = [NSTimer scheduledTimerWithTimeInterval:1.0
												   target:self
												 selector:@selector(tick)
												 userInfo:nil
												  repeats:YES];
}

- (NSString *)initials {
	if (self.peerName.length == 0)
		return @"?";
	NSRange first = [self.peerName rangeOfComposedCharacterSequenceAtIndex:0];
	return [[self.peerName substringWithRange:first] uppercaseString];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self teardown];
}

- (void)teardown {
	[self.ticker invalidate];
	self.ticker = nil;
	[self setProximityEnabled:NO];
	[UIApplication sharedApplication].idleTimerDisabled = self.idleTimerWasDisabled;
	if ([TGCall shared].onStateChanged != nil)
		[TGCall shared].onStateChanged = nil;
}

- (void)setProximityEnabled:(BOOL)enabled {
	UIDevice *device = [UIDevice currentDevice];
	if (![device respondsToSelector:@selector(setProximityMonitoringEnabled:)])
		return;
	if (enabled && !self.proximityWasEnabled){
		device.proximityMonitoringEnabled = YES;
		self.proximityWasEnabled = YES;
	} else if (!enabled && self.proximityWasEnabled){
		device.proximityMonitoringEnabled = NO;
		self.proximityWasEnabled = NO;
	}
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[self teardown];
}

- (UIButton *)buttonWithTitle:(NSString *)title asset:(NSString *)asset
						frame:(CGRect)frame action:(SEL)action {
	UIImage *raw = [UIImage imageNamed:[asset stringByAppendingString:@".png"]];
	UIImage *rawHighlighted = [UIImage imageNamed:
			[asset stringByAppendingString:@"_Highlighted.png"]];

	BOOL centreStretch = [asset isEqualToString:@"MenuRedButton"];
	NSInteger topCap = centreStretch ? (NSInteger)(raw.size.height / 2) : 0;
	NSInteger topCapHighlighted = centreStretch ? (NSInteger)(rawHighlighted.size.height / 2) : 0;

	UIImage *background = [raw stretchableImageWithLeftCapWidth:(NSInteger)(raw.size.width / 2)
												   topCapHeight:topCap];
	UIImage *backgroundHighlighted = [rawHighlighted
			stretchableImageWithLeftCapWidth:(NSInteger)(rawHighlighted.size.width / 2)
								topCapHeight:topCapHighlighted];

	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = frame;
	button.exclusiveTouch = YES;
	button.adjustsImageWhenDisabled = NO;
	[button setBackgroundImage:background forState:UIControlStateNormal];
	[button setBackgroundImage:backgroundHighlighted forState:UIControlStateHighlighted];
	[button setTitle:title forState:UIControlStateNormal];

	if ([asset isEqualToString:@"GroupedActionButton"]){
		[button setTitleColor:[UIColor colorWithRed:0x4a / 255.0f green:0x65 / 255.0f
											   blue:0x87 / 255.0f alpha:1.0f]
					 forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithWhite:1.0f alpha:0.45f]
						   forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleShadowColor:[UIColor clearColor] forState:UIControlStateHighlighted];
		button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		button.titleLabel.shadowOffset = CGSizeMake(0, 1);
	} else {
		UIColor *shadow = [asset isEqualToString:@"GroupedActionButtonGreen"]
				? [UIColor colorWithRed:0x12 / 255.0f green:0x46 / 255.0f blue:0x06 / 255.0f alpha:0.3f]
				: [UIColor colorWithWhite:0.0f alpha:0.3f];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleShadowColor:shadow forState:UIControlStateNormal];
		[button setTitleShadowColor:shadow forState:UIControlStateHighlighted];
		button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	}

	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:button];
	return button;
}

- (void)applyState:(TGCallState)state {
	if (self.dismissing)
		return;

	switch (state){
		case TGCallStateNone:
			self.statusLabel.text = self.outgoing ? @"Calling..." : @"Incoming call";
			break;
		case TGCallStatePending:
			self.statusLabel.text = self.outgoing ? @"Calling..." : @"Incoming call";
			self.acceptButton.hidden = self.outgoing;
			self.muteButton.hidden = !self.outgoing;
			break;
		case TGCallStateExchangingKeys:
			self.statusLabel.text = @"Exchanging keys...";
			self.acceptButton.hidden = YES;
			self.muteButton.hidden = NO;
			break;
		case TGCallStateConnecting:
			self.statusLabel.text = @"Connecting...";
			self.acceptButton.hidden = YES;
			self.muteButton.hidden = NO;
			break;
		case TGCallStateEstablished:
			self.acceptButton.hidden = YES;
			self.muteButton.hidden = NO;
			[self setProximityEnabled:YES];
			[self tick];
			break;
		case TGCallStateFailed:
			self.statusLabel.text = [self endText:@"Call failed"];
			[self finish];
			break;
		case TGCallStateEnded:
			self.statusLabel.text = [self endText:@"Call ended"];
			[self finish];
			break;
		default:
			break;
	}

	if (state != TGCallStateEnded && state != TGCallStateFailed)
		[self syncMuteTitle];
}

- (NSString *)endText:(NSString *)fallback {
	NSString *reason = [TGCall shared].endReason;
	if ([reason isKindOfClass:[NSString class]] && reason.length)
		return reason;
	return fallback;
}

- (void)syncMuteTitle {
	BOOL muted = [TGCall shared].muted;
	[self.muteButton setTitle:(muted ? @"Unmute" : @"Mute") forState:UIControlStateNormal];
}

- (void)tick {
	if (self.dismissing)
		return;
	if ([TGCall shared].state != TGCallStateEstablished)
		return;
	NSTimeInterval elapsed = [[TGCall shared] duration];
	if (elapsed < 0)
		elapsed = 0;
	NSInteger seconds = (NSInteger)elapsed;
	if (seconds >= 3600)
		self.statusLabel.text = [NSString stringWithFormat:@"%ld:%02ld:%02ld",
				(long)(seconds / 3600), (long)((seconds % 3600) / 60), (long)(seconds % 60)];
	else
		self.statusLabel.text = [NSString stringWithFormat:@"%ld:%02ld",
				(long)(seconds / 60), (long)(seconds % 60)];
}

- (void)toggleMute {
	if (self.dismissing)
		return;
	[[TGCall shared] setMuted:![TGCall shared].muted];
	[self syncMuteTitle];
}

- (void)answer {
	if (self.dismissing)
		return;
	self.acceptButton.hidden = YES;
	self.muteButton.hidden = NO;
	self.statusLabel.text = @"Connecting...";
	[[TGCall shared] accept];
}

- (void)end {
	if (self.dismissing)
		return;
	[[TGCall shared] hangUp];
	self.statusLabel.text = [self endText:@"Call ended"];
	[self finish];
}

- (void)finish {
	if (self.dismissing)
		return;
	self.dismissing = YES;
	self.muteButton.enabled = NO;
	self.acceptButton.enabled = NO;
	self.endButton.enabled = NO;
	[self.ticker invalidate];
	self.ticker = nil;
	[self setProximityEnabled:NO];
	[TGCall shared].onStateChanged = nil;
	[self performSelector:@selector(dismissNow) withObject:nil afterDelay:1.0];
}

- (void)dismissNow {
	[UIApplication sharedApplication].idleTimerDisabled = self.idleTimerWasDisabled;
	if (self.presentingViewController != nil)
		[self dismissViewControllerAnimated:YES completion:nil];
}

@end

// vim:ft=objc

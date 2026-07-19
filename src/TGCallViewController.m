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
@end

@implementation TGCallViewController

+ (void)presentForUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing {
	UIWindow *window = [UIApplication sharedApplication].keyWindow;
	UIViewController *top = window.rootViewController;
	while (top.presentedViewController)
		top = top.presentedViewController;

	TGCallViewController *screen = [[TGCallViewController alloc]
			initWithUserId:userId name:name outgoing:outgoing];
	[top presentViewController:screen animated:YES completion:nil];
}

- (instancetype)initWithUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing {
	if ((self = [super init])){
		_userId = userId;
		_peerName = name ?: @"";
		_outgoing = outgoing;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// A call screen is its own thing in every client: dark, centred, and with
	// nothing on it but who and how long.
	self.view.backgroundColor = [UIColor colorWithWhite:0.09f alpha:1.0f];

	CGRect b = self.view.bounds;
	CGFloat side = 96;
	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake((b.size.width - side) / 2, 70, side, side)];
	self.avatarView.layer.cornerRadius = side / 2;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.image = [TGIcons avatarWithInitials:
			(self.peerName.length ? [self.peerName substringToIndex:1].uppercaseString : @"?")
												   size:side colourId:self.userId];
	[self.view addSubview:self.avatarView];

	self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 180, b.size.width - 20, 26)];
	self.nameLabel.text = self.peerName;
	self.nameLabel.font = [UIFont boldSystemFontOfSize:22];
	self.nameLabel.textColor = [UIColor whiteColor];
	self.nameLabel.textAlignment = NSTextAlignmentCenter;
	self.nameLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.nameLabel];

	self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 210, b.size.width - 20, 20)];
	self.statusLabel.font = [UIFont systemFontOfSize:15];
	self.statusLabel.textColor = [UIColor colorWithWhite:0.7f alpha:1];
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.statusLabel];

	CGFloat buttonY = b.size.height - 110;
	self.muteButton = [self buttonWithTitle:@"Mute"
									 colour:[UIColor colorWithWhite:0.25f alpha:1]
									  frame:CGRectMake(30, buttonY, 100, 46)
									 action:@selector(toggleMute)];
	self.endButton = [self buttonWithTitle:@"End"
									colour:[UIColor colorWithRed:0.82f green:0.18f blue:0.18f alpha:1]
									 frame:CGRectMake(b.size.width - 130, buttonY, 100, 46)
									action:@selector(end)];

	// An incoming call needs an answer button where mute would be.
	if (!self.outgoing){
		self.acceptButton = [self buttonWithTitle:@"Answer"
										   colour:[UIColor colorWithRed:0.20f green:0.68f blue:0.30f alpha:1]
											frame:CGRectMake(30, buttonY, 100, 46)
										   action:@selector(answer)];
		self.muteButton.hidden = YES;
	}

	__weak typeof(self) weakSelf = self;
	[TGCall shared].onStateChanged = ^(TGCallState state){
		[weakSelf applyState:state];
	};

	if (self.outgoing)
		[[TGCall shared] callUser:self.userId];
	[self applyState:[TGCall shared].state];

	self.ticker = [NSTimer scheduledTimerWithTimeInterval:1.0
												   target:self
												 selector:@selector(tick)
												 userInfo:nil
												  repeats:YES];
}

- (UIButton *)buttonWithTitle:(NSString *)title colour:(UIColor *)colour
						frame:(CGRect)frame action:(SEL)action {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = frame;
	button.backgroundColor = colour;
	button.layer.cornerRadius = 23;
	[button setTitle:title forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:button];
	return button;
}

- (void)applyState:(TGCallState)state {
	switch (state){
		case TGCallStatePending:
			self.statusLabel.text = self.outgoing ? @"Calling..." : @"Incoming call";
			break;
		case TGCallStateExchangingKeys:
			self.statusLabel.text = @"Exchanging keys...";
			break;
		case TGCallStateConnecting:
			self.statusLabel.text = @"Connecting...";
			self.acceptButton.hidden = YES;
			self.muteButton.hidden = NO;
			break;
		case TGCallStateEstablished:
			self.acceptButton.hidden = YES;
			self.muteButton.hidden = NO;
			break;
		case TGCallStateFailed:
			self.statusLabel.text = [TGCall shared].endReason ?: @"Call failed";
			[self dismissShortly];
			break;
		case TGCallStateEnded:
			self.statusLabel.text = [TGCall shared].endReason ?: @"Call ended";
			[self dismissShortly];
			break;
		default:
			break;
	}
}

- (void)tick {
	if ([TGCall shared].state != TGCallStateEstablished)
		return;
	NSInteger seconds = (NSInteger)[[TGCall shared] duration];
	self.statusLabel.text = [NSString stringWithFormat:@"%ld:%02ld",
			(long)(seconds / 60), (long)(seconds % 60)];
}

- (void)toggleMute {
	BOOL muted = ![TGCall shared].muted;
	[[TGCall shared] setMuted:muted];
	[self.muteButton setTitle:(muted ? @"Unmute" : @"Mute") forState:UIControlStateNormal];
}

- (void)answer {
	[[TGCall shared] accept];
}

- (void)end {
	[[TGCall shared] hangUp];
	[self dismissShortly];
}

- (void)dismissShortly {
	[self.ticker invalidate];
	self.ticker = nil;
	[self performSelector:@selector(dismissNow) withObject:nil afterDelay:1.0];
}

- (void)dismissNow {
	[TGCall shared].onStateChanged = nil;
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end

// vim:ft=objc

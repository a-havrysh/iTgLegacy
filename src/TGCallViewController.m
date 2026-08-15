#import "TGCallViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "TGCall.h"
#import "TGClient.h"
#import "TGClient+Calls.h"
#import "TGTheme.h"
#import "TGIcons.h"

@interface TGCallViewController () <UITextFieldDelegate>
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSString *peerName;
@property (nonatomic, assign) BOOL outgoing;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UIButton *speakerButton;
@property (nonatomic, assign) BOOL speakerOn;
@property (nonatomic, strong) AVAudioPlayer *tonePlayer;
@property (nonatomic, strong) NSTimer *vibrateTimer;
@property (nonatomic, assign) BOOL tonesFinished;
@property (nonatomic, strong) UIButton *endButton;
@property (nonatomic, strong) UIButton *acceptButton;
@property (nonatomic, strong) NSTimer *ticker;
@property (nonatomic, assign) BOOL dismissing;
@property (nonatomic, assign) BOOL proximityWasEnabled;
@property (nonatomic, assign) BOOL idleTimerWasDisabled;
@property (nonatomic, assign) int32_t lastCallId;
@property (nonatomic, assign) BOOL wasEstablished;
@property (nonatomic, assign) NSInteger lastDuration;
@property (nonatomic, assign) BOOL rating;
@property (nonatomic, assign) NSInteger stars;
@property (nonatomic, strong) UIView *ratingPanel;
@property (nonatomic, strong) NSMutableArray *starButtons;
@property (nonatomic, strong) NSMutableArray *problemButtons;
@property (nonatomic, strong) NSArray *problemKeys;
@property (nonatomic, strong) UITextField *commentField;
@property (nonatomic, strong) UILabel *ratingTitleLabel;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *laterButton;
@property (nonatomic, assign) CGFloat keyboardShift;
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

	CGFloat retinaPixel = ([UIScreen mainScreen].scale > 1.0f) ? 0.5f : 0.0f;

	UIImage *linen = [UIImage imageNamed:@"DarkLinen.png"];
	if (linen != nil)
		self.view.backgroundColor = [UIColor colorWithPatternImage:linen];
	else
		self.view.backgroundColor = [UIColor colorWithRed:0x2f / 255.0f green:0x39 / 255.0f
													 blue:0x48 / 255.0f alpha:1.0f];

	CGRect b = self.view.bounds;
	CGFloat side = 90;
	CGFloat avatarY = (CGFloat)(int)(b.size.height * 0.16f);
	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake((CGFloat)(int)((b.size.width - side) / 2), avatarY, side, side)];
	self.avatarView.layer.cornerRadius = (CGFloat)(int)(side / 11.0f + 0.5f);
	self.avatarView.clipsToBounds = YES;
	self.avatarView.image = [TGIcons avatarWithInitials:[self initials]
												   size:side colourId:self.userId];
	[self.view addSubview:self.avatarView];

	UIColor *chromeShadow = [UIColor colorWithRed:0x0e / 255.0f green:0x28 / 255.0f
											 blue:0x4d / 255.0f alpha:0.4f];

	self.nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(9, avatarY + side + 18 + retinaPixel, b.size.width - 18, 24)];
	self.nameLabel.text = self.peerName.length ? self.peerName : @"Unknown";
	self.nameLabel.adjustsFontSizeToFitWidth = YES;
	if ([self.nameLabel respondsToSelector:@selector(setMinimumScaleFactor:)])
		self.nameLabel.minimumScaleFactor = 0.7f;
	self.nameLabel.font = [UIFont boldSystemFontOfSize:19];
	self.nameLabel.textColor = [UIColor whiteColor];
	self.nameLabel.shadowColor = chromeShadow;
	self.nameLabel.shadowOffset = CGSizeMake(0, -1);
	self.nameLabel.textAlignment = NSTextAlignmentCenter;
	self.nameLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.nameLabel];

	self.statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(9, CGRectGetMaxY(self.nameLabel.frame) + 4, b.size.width - 18, 24)];
	self.statusLabel.font = [UIFont systemFontOfSize:14];
	self.statusLabel.textColor = [UIColor colorWithWhite:1.0f alpha:0.65f];
	self.statusLabel.shadowColor = chromeShadow;
	self.statusLabel.shadowOffset = CGSizeMake(0, -1);
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.statusLabel];

	CGFloat buttonWidth = (CGFloat)(int)((b.size.width - 9 * 2 - 8) / 2);
	CGFloat baseline = b.size.height - 20;
	CGRect leftFrame = CGRectMake(9, baseline - 43, buttonWidth, 43);
	CGRect rightFrame = CGRectMake(b.size.width - 9 - buttonWidth, baseline - 45, buttonWidth, 45);
	CGRect speakerFrame = CGRectMake(9, baseline - 43 - 51, b.size.width - 18, 43);

	self.speakerButton = [self buttonWithTitle:@"Speaker"
										 asset:@"GroupedActionButton"
										 frame:speakerFrame
										action:@selector(toggleSpeaker)];
	self.speakerButton.hidden = YES;
	self.muteButton = [self buttonWithTitle:@"Mute"
									  asset:@"GroupedActionButton"
									  frame:leftFrame
									 action:@selector(toggleMute)];
	self.endButton = [self buttonWithTitle:@"End"
									 asset:@"MenuRedButton"
									 frame:rightFrame
									action:@selector(end)];

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
	[self stopTone];
	if (self.speakerOn){
		self.speakerOn = NO;
		[[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone
														   error:nil];
	}
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

#pragma mark - call tones

static void TGCallToneAppend(NSMutableData *samples, double freqA, double freqB,
		double seconds, double rate) {
	NSUInteger count = (NSUInteger)(seconds * rate);
	int16_t *buffer = (int16_t *)malloc(count * sizeof(int16_t));
	if (buffer == NULL)
		return;
	for (NSUInteger i = 0; i < count; i++){
		double t = (double)i / rate;
		double value = 0.0;
		if (freqA > 0.0)
			value += sin(2.0 * M_PI * freqA * t);
		if (freqB > 0.0)
			value += sin(2.0 * M_PI * freqB * t);
		if (freqA > 0.0 && freqB > 0.0)
			value *= 0.5;
		double fade = 1.0;
		double fadeSamples = rate * 0.005;
		if (i < fadeSamples)
			fade = (double)i / fadeSamples;
		else if (count > (NSUInteger)fadeSamples && i > count - (NSUInteger)fadeSamples)
			fade = (double)(count - i) / fadeSamples;
		buffer[i] = (int16_t)(value * fade * 9000.0);
	}
	[samples appendBytes:buffer length:count * sizeof(int16_t)];
	free(buffer);
}

static void TGCallToneAppendSilence(NSMutableData *samples, double seconds, double rate) {
	NSUInteger count = (NSUInteger)(seconds * rate);
	NSUInteger bytes = count * sizeof(int16_t);
	[samples increaseLengthBy:bytes];
}

static NSData *TGCallToneWrap(NSData *samples, double rate) {
	uint32_t sampleRate = (uint32_t)rate;
	uint32_t dataSize = (uint32_t)[samples length];
	uint32_t byteRate = sampleRate * 2;
	NSMutableData *wav = [NSMutableData dataWithCapacity:dataSize + 44];
	uint32_t chunkSize = dataSize + 36;
	uint32_t sixteen = 16;
	uint16_t one = 1;
	uint16_t bits = 16;
	uint16_t align = 2;
	[wav appendBytes:"RIFF" length:4];
	[wav appendBytes:&chunkSize length:4];
	[wav appendBytes:"WAVEfmt " length:8];
	[wav appendBytes:&sixteen length:4];
	[wav appendBytes:&one length:2];
	[wav appendBytes:&one length:2];
	[wav appendBytes:&sampleRate length:4];
	[wav appendBytes:&byteRate length:4];
	[wav appendBytes:&align length:2];
	[wav appendBytes:&bits length:2];
	[wav appendBytes:"data" length:4];
	[wav appendBytes:&dataSize length:4];
	[wav appendData:samples];
	return wav;
}

- (void)playToneData:(NSData *)data loop:(BOOL)loop volume:(float)volume {
	[self stopTone];
	if (data == nil)
		return;
	AVAudioSession *session = [AVAudioSession sharedInstance];
	if ([TGCall shared].state != TGCallStateEstablished){
		[session setCategory:AVAudioSessionCategoryPlayback error:nil];
		[session setActive:YES error:nil];
	}
	NSError *error = nil;
	AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:data error:&error];
	if (player == nil)
		return;
	player.numberOfLoops = loop ? -1 : 0;
	player.volume = volume;
	[player prepareToPlay];
	[player play];
	self.tonePlayer = player;
}

- (void)startRingingTone {
	if (self.tonePlayer != nil || self.tonesFinished || self.dismissing)
		return;

	double rate = 8000.0;
	NSMutableData *samples = [NSMutableData data];
	if (self.outgoing){
		TGCallToneAppend(samples, 425.0, 0.0, 1.0, rate);
		TGCallToneAppendSilence(samples, 3.0, rate);
	} else {
		TGCallToneAppend(samples, 440.0, 480.0, 1.2, rate);
		TGCallToneAppendSilence(samples, 2.4, rate);
	}
	[self playToneData:TGCallToneWrap(samples, rate) loop:YES volume:self.outgoing ? 0.5f : 1.0f];

	if (!self.outgoing && self.vibrateTimer == nil){
		AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
		self.vibrateTimer = [NSTimer scheduledTimerWithTimeInterval:3.6
															 target:self
														   selector:@selector(vibrate)
														   userInfo:nil
															repeats:YES];
	}
}

- (void)vibrate {
	if (self.dismissing || self.tonePlayer == nil)
		return;
	AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)playEndTone {
	if (self.tonesFinished)
		return;
	[self stopTone];
	self.tonesFinished = YES;
	double rate = 8000.0;
	NSMutableData *samples = [NSMutableData data];
	for (NSInteger i = 0; i < 3; i++){
		TGCallToneAppend(samples, 425.0, 0.0, 0.2, rate);
		TGCallToneAppendSilence(samples, 0.2, rate);
	}
	[self playToneData:TGCallToneWrap(samples, rate) loop:NO volume:0.6f];
}

- (void)stopTone {
	[self.vibrateTimer invalidate];
	self.vibrateTimer = nil;
	if (self.tonePlayer != nil){
		[self.tonePlayer stop];
		self.tonePlayer = nil;
	}
}

- (void)applyState:(TGCallState)state {
	if (self.dismissing)
		return;

	if ([TGCall shared].callId != 0)
		self.lastCallId = [TGCall shared].callId;

	switch (state){
		case TGCallStateNone:
			self.statusLabel.text = self.outgoing ? @"Waiting..." : @"Incoming call";
			[self startRingingTone];
			break;
		case TGCallStatePending:
			self.statusLabel.text = self.outgoing ? @"Calling..." : @"Incoming call";
			[self startRingingTone];
			self.acceptButton.hidden = self.outgoing;
			self.muteButton.hidden = !self.outgoing;
			break;
		case TGCallStateExchangingKeys:
			self.statusLabel.text = @"Exchanging keys...";
			self.acceptButton.hidden = YES;
			self.muteButton.hidden = NO;
			[self stopTone];
			break;
		case TGCallStateConnecting:
			self.statusLabel.text = @"Connecting...";
			self.acceptButton.hidden = YES;
			self.muteButton.hidden = NO;
			[self stopTone];
			break;
		case TGCallStateEstablished:
			self.acceptButton.hidden = YES;
			self.muteButton.hidden = NO;
			self.wasEstablished = YES;
			[self stopTone];
			[self setProximityEnabled:!self.speakerOn];
			[self tick];
			break;
		case TGCallStateFailed:
			self.statusLabel.text = [self endText:@"Call failed"];
			[self playEndTone];
			[self finish];
			break;
		case TGCallStateEnded:
			self.statusLabel.text = [self endText:@"Call ended"];
			[self playEndTone];
			[self finish];
			break;
		default:
			break;
	}

	if (state != TGCallStateEnded && state != TGCallStateFailed){
		[self syncMuteTitle];
		self.speakerButton.hidden = self.muteButton.hidden;
	} else {
		self.speakerButton.hidden = YES;
	}
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
	self.lastDuration = seconds;
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

- (void)toggleSpeaker {
	if (self.dismissing)
		return;
	self.speakerOn = !self.speakerOn;
	[self applySpeakerRoute];
}

- (void)applySpeakerRoute {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session overrideOutputAudioPort:(self.speakerOn
			? AVAudioSessionPortOverrideSpeaker
			: AVAudioSessionPortOverrideNone) error:nil];
	[self.speakerButton setTitle:(self.speakerOn ? @"Earpiece" : @"Speaker")
						forState:UIControlStateNormal];
	if ([TGCall shared].state == TGCallStateEstablished)
		[self setProximityEnabled:!self.speakerOn];
	else
		[self setProximityEnabled:NO];
}

- (void)answer {
	if (self.dismissing)
		return;
	[self stopTone];
	self.acceptButton.hidden = YES;
	self.muteButton.hidden = NO;
	self.speakerButton.hidden = NO;
	self.statusLabel.text = @"Connecting...";
	[[TGCall shared] accept];
}

- (void)end {
	if (self.dismissing)
		return;
	[[TGCall shared] hangUp];
	self.statusLabel.text = [self endText:@"Call ended"];
	[self playEndTone];
	[self finish];
}

- (void)finish {
	if (self.dismissing)
		return;
	self.dismissing = YES;
	self.speakerButton.hidden = YES;
	self.muteButton.enabled = NO;
	self.acceptButton.enabled = NO;
	self.endButton.enabled = NO;
	[self.ticker invalidate];
	self.ticker = nil;
	[self setProximityEnabled:NO];
	[TGCall shared].onStateChanged = nil;

	if (self.wasEstablished && self.lastDuration > 0 && self.lastCallId != 0){
		[self presentRating];
		return;
	}
	[self performSelector:@selector(dismissNow) withObject:nil afterDelay:1.0];
}

#pragma mark - post-call rating

- (void)presentRating {
	self.rating = YES;
	self.muteButton.hidden = YES;
	self.acceptButton.hidden = YES;
	self.endButton.hidden = YES;

	CGRect b = self.view.bounds;
	self.problemKeys = [NSArray arrayWithObjects:@"echo", @"noise", @"interruptions",
			@"distortedSpeech", @"silentRemote", @"dropped", nil];

	CGRect nameFrame = self.nameLabel.frame;
	nameFrame.origin.y = 26;
	CGRect statusFrame = self.statusLabel.frame;
	statusFrame.origin.y = CGRectGetMaxY(nameFrame) + 2;
	[UIView animateWithDuration:0.2 animations:^{
		self.avatarView.alpha = 0.0f;
		self.nameLabel.frame = nameFrame;
		self.statusLabel.frame = statusFrame;
	}];

	CGFloat top = CGRectGetMaxY(statusFrame) + 12;
	self.ratingPanel = [[UIView alloc] initWithFrame:
			CGRectMake(0, top, b.size.width, b.size.height - top)];
	self.ratingPanel.backgroundColor = [UIColor clearColor];
	self.ratingPanel.alpha = 0.0f;
	[self.view addSubview:self.ratingPanel];

	UIColor *chromeShadow = [UIColor colorWithRed:0x0e / 255.0f green:0x28 / 255.0f
											 blue:0x4d / 255.0f alpha:0.4f];

	self.ratingTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(9, 0, b.size.width - 18, 22)];
	self.ratingTitleLabel.text = @"Rate this call";
	self.ratingTitleLabel.font = [UIFont boldSystemFontOfSize:17];
	self.ratingTitleLabel.textColor = [UIColor whiteColor];
	self.ratingTitleLabel.shadowColor = chromeShadow;
	self.ratingTitleLabel.shadowOffset = CGSizeMake(0, -1);
	self.ratingTitleLabel.textAlignment = NSTextAlignmentCenter;
	self.ratingTitleLabel.backgroundColor = [UIColor clearColor];
	[self.ratingPanel addSubview:self.ratingTitleLabel];

	self.starButtons = [NSMutableArray array];
	CGFloat starSide = 44;
	CGFloat starsWidth = starSide * 5;
	CGFloat starsX = (CGFloat)(int)((b.size.width - starsWidth) / 2);
	for (NSInteger i = 0; i < 5; i++){
		UIButton *star = [UIButton buttonWithType:UIButtonTypeCustom];
		star.frame = CGRectMake(starsX + starSide * i, 26, starSide, starSide);
		star.tag = i + 1;
		star.exclusiveTouch = YES;
		star.backgroundColor = [UIColor clearColor];
		star.titleLabel.font = [UIFont systemFontOfSize:30];
		[star setTitle:@"☆" forState:UIControlStateNormal];
		[star setTitleColor:[UIColor colorWithWhite:1.0f alpha:0.6f] forState:UIControlStateNormal];
		[star addTarget:self action:@selector(starPressed:)
				forControlEvents:UIControlEventTouchUpInside];
		[self.ratingPanel addSubview:star];
		[self.starButtons addObject:star];
	}

	CGFloat y = 26 + starSide + 8;
	self.problemButtons = [NSMutableArray array];
	NSArray *titles = [NSArray arrayWithObjects:@"Echo", @"Noise", @"Interruptions",
			@"Distorted speech", @"Silent remote", @"Dropped", nil];
	CGFloat cellWidth = (CGFloat)(int)((b.size.width - 9 * 2 - 8) / 2);
	for (NSUInteger i = 0; i < [titles count]; i++){
		CGFloat px = (i % 2 == 0) ? 9 : (b.size.width - 9 - cellWidth);
		CGFloat py = y + (CGFloat)(int)(i / 2) * 34;
		UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
		chip.frame = CGRectMake(px, py, cellWidth, 30);
		chip.tag = (NSInteger)i;
		chip.exclusiveTouch = YES;
		chip.titleLabel.font = [UIFont boldSystemFontOfSize:13];
		chip.titleLabel.shadowOffset = CGSizeMake(0, -1);
		chip.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
		chip.layer.cornerRadius = 4;
		chip.layer.borderWidth = 1;
		chip.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.25f].CGColor;
		[chip setTitle:[titles objectAtIndex:i] forState:UIControlStateNormal];
		[chip setTitleColor:[UIColor colorWithWhite:1.0f alpha:0.75f]
				   forState:UIControlStateNormal];
		[chip setTitleShadowColor:chromeShadow forState:UIControlStateNormal];
		[chip addTarget:self action:@selector(problemPressed:)
				forControlEvents:UIControlEventTouchUpInside];
		chip.hidden = YES;
		[self.ratingPanel addSubview:chip];
		[self.problemButtons addObject:chip];
	}

	self.commentField = [[UITextField alloc] initWithFrame:
			CGRectMake(9, y + 3 * 34 + 4, b.size.width - 18, 31)];
	self.commentField.borderStyle = UITextBorderStyleRoundedRect;
	self.commentField.font = [UIFont systemFontOfSize:14];
	self.commentField.placeholder = @"Comment (optional)";
	self.commentField.returnKeyType = UIReturnKeyDone;
	self.commentField.autocorrectionType = UITextAutocorrectionTypeDefault;
	self.commentField.clearButtonMode = UITextFieldViewModeWhileEditing;
	self.commentField.delegate = self;
	self.commentField.hidden = YES;
	[self.ratingPanel addSubview:self.commentField];

	CGFloat baseline = b.size.height - 20 - self.ratingPanel.frame.origin.y;
	CGFloat buttonWidth = (CGFloat)(int)((b.size.width - 9 * 2 - 8) / 2);
	self.laterButton = [self ratingButtonWithTitle:@"Not Now"
											 asset:@"GroupedActionButton"
											 frame:CGRectMake(9, baseline - 43, buttonWidth, 43)
											action:@selector(skipRating)];
	self.sendButton = [self ratingButtonWithTitle:@"Send"
											asset:@"GroupedActionButtonGreen"
											frame:CGRectMake(b.size.width - 9 - buttonWidth,
													baseline - 45, buttonWidth, 45)
										   action:@selector(submitRating)];
	self.sendButton.enabled = NO;
	self.sendButton.alpha = 0.5f;

	[UIView animateWithDuration:0.2 animations:^{
		self.ratingPanel.alpha = 1.0f;
	}];
}

- (UIButton *)ratingButtonWithTitle:(NSString *)title asset:(NSString *)asset
							  frame:(CGRect)frame action:(SEL)action {
	UIButton *button = [self buttonWithTitle:title asset:asset frame:frame action:action];
	[button removeFromSuperview];
	[self.ratingPanel addSubview:button];
	return button;
}

- (void)starPressed:(UIButton *)sender {
	self.stars = sender.tag;
	for (UIButton *star in self.starButtons){
		BOOL on = star.tag <= self.stars;
		[star setTitle:(on ? @"★" : @"☆") forState:UIControlStateNormal];
		[star setTitleColor:(on ? [UIColor whiteColor] : [UIColor colorWithWhite:1.0f alpha:0.6f])
				   forState:UIControlStateNormal];
	}

	BOOL detail = (self.stars > 0 && self.stars < 5);
	if (!detail){
		[self.commentField resignFirstResponder];
		for (UIButton *chip in self.problemButtons)
			[self setChip:chip selected:NO];
	}
	for (UIButton *chip in self.problemButtons)
		chip.hidden = !detail;
	self.commentField.hidden = !detail;

	self.sendButton.enabled = (self.stars > 0);
	self.sendButton.alpha = (self.stars > 0) ? 1.0f : 0.5f;
}

- (void)setChip:(UIButton *)chip selected:(BOOL)selected {
	chip.selected = selected;
	chip.backgroundColor = selected
			? [UIColor colorWithRed:0x36 / 255.0f green:0x8a / 255.0f blue:0x2e / 255.0f alpha:0.9f]
			: [UIColor colorWithWhite:1.0f alpha:0.12f];
	[chip setTitleColor:(selected ? [UIColor whiteColor] : [UIColor colorWithWhite:1.0f alpha:0.75f])
			   forState:UIControlStateNormal];
}

- (void)problemPressed:(UIButton *)sender {
	[self setChip:sender selected:!sender.selected];
}

- (NSArray *)selectedProblems {
	NSMutableArray *problems = [NSMutableArray array];
	for (UIButton *chip in self.problemButtons){
		if (chip.selected && (NSUInteger)chip.tag < [self.problemKeys count])
			[problems addObject:[self.problemKeys objectAtIndex:(NSUInteger)chip.tag]];
	}
	return problems;
}

- (void)submitRating {
	if (self.stars <= 0)
		return;
	[self.commentField resignFirstResponder];

	NSString *comment = [self.commentField.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	self.sendButton.enabled = NO;
	self.laterButton.enabled = NO;
	self.statusLabel.text = @"Sending...";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] rateCallId:self.lastCallId
						   rating:self.stars
						  comment:(comment.length ? comment : nil)
						 problems:[self selectedProblems]
					   completion:^(BOOL ok){
		TGCallViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf.statusLabel.text = ok ? @"Thank you" : @"Could not send rating";
		[strongSelf closeRating];
	}];
}

- (void)skipRating {
	[self.commentField resignFirstResponder];
	[self closeRating];
}

- (void)closeRating {
	if (!self.rating)
		return;
	self.rating = NO;
	[UIView animateWithDuration:0.2 animations:^{
		self.ratingPanel.alpha = 0.0f;
	} completion:^(BOOL finished){
		[self.ratingPanel removeFromSuperview];
		self.ratingPanel = nil;
	}];
	[self performSelector:@selector(dismissNow) withObject:nil afterDelay:0.8];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
	if (self.keyboardShift > 0)
		return;
	CGFloat needed = CGRectGetMaxY(self.view.bounds) - 216
			- (self.ratingPanel.frame.origin.y + CGRectGetMaxY(self.commentField.frame) + 8);
	if (needed >= 0)
		return;
	self.keyboardShift = -needed;
	CGRect frame = self.view.frame;
	frame.origin.y -= self.keyboardShift;
	[UIView animateWithDuration:0.25 animations:^{
		self.view.frame = frame;
	}];
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
	if (self.keyboardShift <= 0)
		return;
	CGRect frame = self.view.frame;
	frame.origin.y += self.keyboardShift;
	self.keyboardShift = 0;
	[UIView animateWithDuration:0.25 animations:^{
		self.view.frame = frame;
	}];
}

- (void)dismissNow {
	[UIApplication sharedApplication].idleTimerDisabled = self.idleTimerWasDisabled;
	if (self.presentingViewController != nil)
		[self dismissViewControllerAnimated:YES completion:nil];
}

@end

// vim:ft=objc

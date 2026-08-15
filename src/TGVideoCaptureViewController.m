#import "TGVideoCaptureViewController.h"
#import "TGVideoRecorder.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

static const CGFloat TGVideoCaptureShutterSide = 68.0f;
static const CGFloat TGVideoCaptureRoundSide = 240.0f;
static const NSTimeInterval TGVideoCaptureMinimum = 0.6;

static UIImage *TGVideoCaptureShutterImage(BOOL recording, BOOL pressed) {
	CGFloat side = TGVideoCaptureShutterSide;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0.0f);
	CGContextRef context = UIGraphicsGetCurrentContext();

	CGContextSetShadowWithColor(context, CGSizeMake(0, 1), 2.0f,
			[UIColor colorWithWhite:0 alpha:0.4f].CGColor);
	CGContextSetStrokeColorWithColor(context,
			[UIColor colorWithWhite:1 alpha:pressed ? 0.7f : 1.0f].CGColor);
	CGContextSetLineWidth(context, 4.0f);
	CGContextStrokeEllipseInRect(context, CGRectMake(4, 4, side - 8, side - 8));
	CGContextSetShadowWithColor(context, CGSizeZero, 0, NULL);

	CGContextSetFillColorWithColor(context,
			[UIColor colorWithRed:0.85f green:0.16f blue:0.14f
							alpha:pressed ? 0.7f : 1.0f].CGColor);
	if (recording){
		CGFloat inner = 26.0f;
		CGRect square = CGRectMake((side - inner) / 2, (side - inner) / 2, inner, inner);
		CGContextAddPath(context,
				[UIBezierPath bezierPathWithRoundedRect:square cornerRadius:4].CGPath);
		CGContextFillPath(context);
	} else {
		CGFloat inner = side - 20;
		CGContextFillEllipseInRect(context,
				CGRectMake((side - inner) / 2, (side - inner) / 2, inner, inner));
	}

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

@interface TGVideoCaptureViewController () <TGVideoRecorderDelegate>

@property (nonatomic, assign) BOOL roundVideoNote;
@property (nonatomic, assign) BOOL reviewing;
@property (nonatomic, assign) BOOL prepared;

@property (nonatomic, strong) TGVideoRecorder *recorder;

@property (nonatomic, strong) UIView *stage;
@property (nonatomic, strong) CAShapeLayer *progressRing;

@property (nonatomic, strong) UIView *topPanel;
@property (nonatomic, strong) UIView *bottomPanel;

@property (nonatomic, strong) UIButton *shutter;
@property (nonatomic, strong) UIButton *flip;
@property (nonatomic, strong) UIButton *cancel;
@property (nonatomic, strong) UIView *timeBadge;
@property (nonatomic, strong) UIView *timeDot;
@property (nonatomic, strong) UILabel *timeLabel;

@property (nonatomic, strong) UIButton *retake;
@property (nonatomic, strong) UIButton *send;

@property (nonatomic, strong) NSString *resultPath;
@property (nonatomic, assign) NSTimeInterval resultDuration;
@property (nonatomic, assign) CGSize resultDimensions;

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;

@end

@implementation TGVideoCaptureViewController

- (id)initWithRoundVideoNote:(BOOL)round {
	self = [super initWithNibName:nil bundle:nil];
	if (self){
		_roundVideoNote = round;
		_recorder = [[TGVideoRecorder alloc] initWithMode:round ? TGVideoRecorderModeNote
														 : TGVideoRecorderModeVideo];
		_recorder.delegate = self;
		_maximumDuration = _recorder.maximumDuration;
		_minimumDuration = TGVideoCaptureMinimum;
		self.wantsFullScreenLayout = YES;
	}
	return self;
}

- (id)initWithNibName:(NSString *)name bundle:(NSBundle *)bundle {
	return [self initWithRoundVideoNote:NO];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_player pause];
	_recorder.delegate = nil;
	[_recorder teardown];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [UIColor colorWithRed:0x22 / 255.0f green:0x22 / 255.0f
												 blue:0x22 / 255.0f alpha:1.0f];
	[self.navigationController setNavigationBarHidden:YES animated:NO];

	[self buildStage];
	[self buildTopPanel];
	[self buildBottomPanel];
	[self updateChrome];
}

- (CGFloat)topPanelHeight {
	return self.view.bounds.size.height > 440.0f ? 112.0f : 68.0f;
}

- (CGFloat)bottomPanelHeight {
	return self.view.bounds.size.height > 440.0f ? 136.0f : 92.0f;
}

- (void)buildStage {
	CGRect bounds = self.view.bounds;
	CGRect frame = bounds;
	if (self.roundVideoNote){
		CGFloat side = TGVideoCaptureRoundSide;
		CGFloat area = bounds.size.height - [self bottomPanelHeight];
		frame = CGRectMake((int)((bounds.size.width - side) / 2),
						   (int)((area - side) / 2) + [self topPanelHeight] / 2,
						   side, side);
	}

	self.stage = [[UIView alloc] initWithFrame:frame];
	self.stage.backgroundColor = [UIColor blackColor];
	self.stage.clipsToBounds = YES;
	if (self.roundVideoNote){
		self.stage.layer.cornerRadius = frame.size.width / 2;
		self.stage.layer.masksToBounds = YES;
	}
	[self.view addSubview:self.stage];

	if (self.roundVideoNote){
		CGFloat side = frame.size.width;
		self.progressRing = [CAShapeLayer layer];
		self.progressRing.frame = CGRectMake(frame.origin.x - 2, frame.origin.y - 2,
											 side + 4, side + 4);
		self.progressRing.path = [UIBezierPath bezierPathWithOvalInRect:
				CGRectMake(2, 2, side, side)].CGPath;
		self.progressRing.fillColor = [UIColor clearColor].CGColor;
		self.progressRing.strokeColor = [UIColor colorWithRed:0.85f green:0.16f blue:0.14f
														alpha:1.0f].CGColor;
		self.progressRing.lineWidth = 3.0f;
		self.progressRing.lineCap = kCALineCapRound;
		self.progressRing.strokeEnd = 0.0f;
		self.progressRing.transform = CATransform3DMakeRotation(-M_PI_2, 0, 0, 1);
		[self.view.layer addSublayer:self.progressRing];
	}
}

- (void)attachPreviewLayer {
	CALayer *preview = self.recorder.previewLayer;
	if (preview == nil || self.stage == nil)
		return;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	preview.frame = self.stage.bounds;
	[CATransaction commit];
	if (preview.superlayer != self.stage.layer)
		[self.stage.layer insertSublayer:preview atIndex:0];
	preview.hidden = self.reviewing;
}

- (UIButton *)panelTextButtonWithTitle:(NSString *)title {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.exclusiveTouch = YES;
	button.showsTouchWhenHighlighted = YES;
	button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
	button.titleLabel.shadowOffset = CGSizeMake(0, 1);
	[button setTitle:title forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[button setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.3f]
					   forState:UIControlStateNormal];
	return button;
}

- (UIButton *)plateButtonWithTitle:(NSString *)title green:(BOOL)green {
	NSString *normal = green ? @"GroupedActionButtonGreen.png" : @"GroupedActionButton.png";
	NSString *pressed = green ? @"GroupedActionButtonGreen_Highlighted.png"
							  : @"GroupedActionButton_Highlighted.png";
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.exclusiveTouch = YES;
	button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	[button setBackgroundImage:[[UIImage imageNamed:normal]
			stretchableImageWithLeftCapWidth:24 topCapHeight:0]
					  forState:UIControlStateNormal];
	[button setBackgroundImage:[[UIImage imageNamed:pressed]
			stretchableImageWithLeftCapWidth:24 topCapHeight:0]
					  forState:UIControlStateHighlighted];
	[button setTitle:title forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[button setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.3f]
					   forState:UIControlStateNormal];
	return button;
}

- (void)buildTopPanel {
	CGRect bounds = self.view.bounds;
	CGFloat height = [self topPanelHeight];

	self.topPanel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, height)];
	self.topPanel.backgroundColor = [UIColor clearColor];
	UIImageView *background = [[UIImageView alloc] initWithFrame:self.topPanel.bounds];
	background.image = [[UIImage imageNamed:@"CameraStripeTop.png"]
			stretchableImageWithLeftCapWidth:6 topCapHeight:20];
	background.userInteractionEnabled = NO;
	[self.topPanel addSubview:background];
	[self.view addSubview:self.topPanel];

	CGFloat row = height - 40.0f;

	self.timeBadge = [[UIView alloc] initWithFrame:CGRectMake(12, row, 92, 26)];
	self.timeBadge.backgroundColor = [UIColor clearColor];
	self.timeBadge.hidden = YES;
	[self.topPanel addSubview:self.timeBadge];

	self.timeDot = [[UIView alloc] initWithFrame:CGRectMake(0, 9, 8, 8)];
	self.timeDot.backgroundColor = [UIColor colorWithRed:0.85f green:0.16f blue:0.14f alpha:1.0f];
	self.timeDot.layer.cornerRadius = 4.0f;
	[self.timeBadge addSubview:self.timeDot];

	self.timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 3, 78, 20)];
	self.timeLabel.backgroundColor = [UIColor clearColor];
	self.timeLabel.textColor = [UIColor whiteColor];
	self.timeLabel.font = [UIFont boldSystemFontOfSize:15];
	self.timeLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.4f];
	self.timeLabel.shadowOffset = CGSizeMake(0, 1);
	self.timeLabel.text = @"0:00";
	[self.timeBadge addSubview:self.timeLabel];

	self.flip = [self panelTextButtonWithTitle:@"Flip"];
	self.flip.frame = CGRectMake((int)((bounds.size.width - 80) / 2), row, 80, 26);
	[self.flip addTarget:self action:@selector(flipPressed)
		forControlEvents:UIControlEventTouchUpInside];
	[self.topPanel addSubview:self.flip];

	self.cancel = [self panelTextButtonWithTitle:@"Cancel"];
	self.cancel.frame = CGRectMake(bounds.size.width - 88, row, 76, 26);
	[self.cancel addTarget:self action:@selector(cancelPressed)
		  forControlEvents:UIControlEventTouchUpInside];
	[self.topPanel addSubview:self.cancel];
}

- (void)buildBottomPanel {
	CGRect bounds = self.view.bounds;
	CGFloat height = [self bottomPanelHeight];

	self.bottomPanel = [[UIView alloc] initWithFrame:CGRectMake(
			0, bounds.size.height - height, bounds.size.width, height)];
	self.bottomPanel.backgroundColor = [UIColor clearColor];
	UIImageView *background = [[UIImageView alloc] initWithFrame:self.bottomPanel.bounds];
	background.image = [[UIImage imageNamed:@"CameraStripeBottom.png"]
			stretchableImageWithLeftCapWidth:6 topCapHeight:0];
	background.userInteractionEnabled = NO;
	[self.bottomPanel addSubview:background];
	[self.view addSubview:self.bottomPanel];

	CGFloat side = TGVideoCaptureShutterSide;
	self.shutter = [UIButton buttonWithType:UIButtonTypeCustom];
	self.shutter.exclusiveTouch = YES;
	self.shutter.frame = CGRectMake((int)((bounds.size.width - side) / 2),
									(int)(height - side - 14), side, side);
	[self.shutter setBackgroundImage:TGVideoCaptureShutterImage(NO, NO)
							forState:UIControlStateNormal];
	[self.shutter setBackgroundImage:TGVideoCaptureShutterImage(NO, YES)
							forState:UIControlStateHighlighted];
	[self.shutter addTarget:self action:@selector(shutterPressed)
		   forControlEvents:UIControlEventTouchUpInside];
	[self.bottomPanel addSubview:self.shutter];

	self.retake = [self plateButtonWithTitle:@"Retake" green:NO];
	self.retake.frame = CGRectMake(12, (int)(height - 43 - 20), 130, 43);
	self.retake.hidden = YES;
	[self.retake addTarget:self action:@selector(retakePressed)
		  forControlEvents:UIControlEventTouchUpInside];
	[self.bottomPanel addSubview:self.retake];

	self.send = [self plateButtonWithTitle:@"Send" green:YES];
	self.send.frame = CGRectMake(bounds.size.width - 142, (int)(height - 43 - 20), 130, 43);
	self.send.hidden = YES;
	[self.send addTarget:self action:@selector(sendPressed)
		forControlEvents:UIControlEventTouchUpInside];
	[self.bottomPanel addSubview:self.send];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.navigationController setNavigationBarHidden:YES animated:animated];
	if (!self.reviewing)
		[self startSession];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.player pause];
	[self stopSession];
}

- (BOOL)shouldAutorotate {
	return NO;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation == UIInterfaceOrientationPortrait;
}

- (NSUInteger)supportedInterfaceOrientations {
	return UIInterfaceOrientationMaskPortrait;
}

- (void)startSession {
	if (!self.prepared){
		self.prepared = YES;
		[self.recorder prepare];
	}
	[self attachPreviewLayer];
	self.shutter.enabled = self.recorder.ready;
	[self updateChrome];
}

- (void)stopSession {
	if (!self.prepared)
		return;
	self.prepared = NO;
	[self.recorder teardown];
}

- (void)shutterPressed {
	if (self.recorder.recording)
		[self.recorder stopRecording];
	else
		[self beginRecording];
}

- (void)beginRecording {
	if (!self.prepared)
		[self startSession];
	[self.recorder startRecording];
}

- (void)showRecordingChrome {
	[self.shutter setBackgroundImage:TGVideoCaptureShutterImage(YES, NO)
							forState:UIControlStateNormal];
	[self.shutter setBackgroundImage:TGVideoCaptureShutterImage(YES, YES)
							forState:UIControlStateHighlighted];
	self.timeBadge.hidden = NO;
	self.timeDot.hidden = NO;
	self.timeDot.alpha = 1.0f;
	self.timeLabel.text = @"0:00";
	self.cancel.hidden = YES;
	self.flip.hidden = YES;
}

- (void)setElapsedText:(NSTimeInterval)elapsed {
	NSInteger seconds = (NSInteger)elapsed;
	if (seconds < 0)
		seconds = 0;
	self.timeLabel.text = [NSString stringWithFormat:@"%d:%02d",
			(int)(seconds / 60), (int)(seconds % 60)];
}

- (void)videoRecorderDidBecomeReady:(TGVideoRecorder *)recorder {
	[self attachPreviewLayer];
	self.shutter.enabled = YES;
	[self updateChrome];
}

- (void)videoRecorderDidStartRecording:(TGVideoRecorder *)recorder {
	[self showRecordingChrome];
}

- (void)videoRecorder:(TGVideoRecorder *)recorder
	didUpdateDuration:(NSTimeInterval)duration
			 progress:(float)progress {
	[self setElapsedText:duration];
	self.timeDot.alpha = ((NSInteger)(duration * 2)) % 2 == 0 ? 1.0f : 0.2f;

	if (self.progressRing != nil){
		CGFloat fraction = progress;
		if (fraction < 0.0f)
			fraction = 0.0f;
		if (fraction > 1.0f)
			fraction = 1.0f;
		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		self.progressRing.strokeEnd = fraction;
		[CATransaction commit];
	}
}

- (void)videoRecorder:(TGVideoRecorder *)recorder
	didFinishRecordingToPath:(NSString *)path
					duration:(NSTimeInterval)duration
				  dimensions:(CGSize)dimensions {
	self.timeDot.alpha = 1.0f;
	if (path.length == 0 || duration < self.minimumDuration){
		if (path.length)
			[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
		[self resetToCamera];
		return;
	}
	self.resultPath = path;
	self.resultDuration = duration;
	self.resultDimensions = dimensions;
	[self enterReview];
}

- (void)videoRecorder:(TGVideoRecorder *)recorder didFailWithError:(NSError *)error {
	[self resetToCamera];
}

- (void)enterReview {
	self.reviewing = YES;
	[self stopSession];

	self.timeBadge.hidden = YES;
	self.cancel.hidden = NO;
	self.flip.hidden = YES;
	self.shutter.hidden = YES;
	self.retake.hidden = NO;
	self.send.hidden = NO;

	[self setElapsedText:self.resultDuration + 0.5];
	self.timeDot.hidden = YES;
	self.timeBadge.hidden = NO;

	self.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:self.resultPath]];
	self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
	self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
	self.playerLayer.frame = self.stage.bounds;
	[self.stage.layer addSublayer:self.playerLayer];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(playbackReachedEnd:)
												 name:AVPlayerItemDidPlayToEndTimeNotification
											   object:self.player.currentItem];
	[self.player play];
	[self updateChrome];
}

- (void)playbackReachedEnd:(NSNotification *)notification {
	[self.player seekToTime:kCMTimeZero];
	[self.player play];
}

- (void)resetToCamera {
	[[NSNotificationCenter defaultCenter]
			removeObserver:self
					  name:AVPlayerItemDidPlayToEndTimeNotification
					object:nil];
	[self.player pause];
	self.player = nil;
	[self.playerLayer removeFromSuperlayer];
	self.playerLayer = nil;

	self.reviewing = NO;
	self.resultPath = nil;
	self.resultDuration = 0;
	self.resultDimensions = CGSizeZero;

	self.timeBadge.hidden = YES;
	self.timeDot.hidden = NO;
	self.timeDot.alpha = 1.0f;
	self.timeLabel.text = @"0:00";
	self.progressRing.strokeEnd = 0.0f;
	self.shutter.hidden = NO;
	self.shutter.enabled = YES;
	self.retake.hidden = YES;
	self.send.hidden = YES;
	self.cancel.hidden = NO;

	[self.shutter setBackgroundImage:TGVideoCaptureShutterImage(NO, NO)
							forState:UIControlStateNormal];
	[self.shutter setBackgroundImage:TGVideoCaptureShutterImage(NO, YES)
							forState:UIControlStateHighlighted];

	if (self.view.window != nil)
		[self startSession];
	[self updateChrome];
}

- (void)updateChrome {
	self.flip.hidden = self.reviewing || self.recorder.recording || !self.recorder.canSwitchCamera;
	self.progressRing.hidden = self.reviewing;
	self.recorder.previewLayer.hidden = self.reviewing;
}

- (void)flipPressed {
	if (self.recorder.recording || !self.recorder.canSwitchCamera)
		return;

	UIView *snapshot = [[UIView alloc] initWithFrame:self.stage.bounds];
	snapshot.backgroundColor = [UIColor blackColor];
	snapshot.alpha = 0.0f;
	[self.stage addSubview:snapshot];

	__weak TGVideoCaptureViewController *weakSelf = self;
	[UIView animateWithDuration:0.12 animations:^{
		snapshot.alpha = 1.0f;
	} completion:^(BOOL finished){
		TGVideoCaptureViewController *me = weakSelf;
		[me.recorder switchCamera];
		[UIView animateWithDuration:0.18 animations:^{
			snapshot.alpha = 0.0f;
		} completion:^(BOOL done){
			[snapshot removeFromSuperview];
		}];
	}];
}

- (void)retakePressed {
	NSString *path = self.resultPath;
	[self resetToCamera];
	if (path.length)
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (void)sendPressed {
	NSString *path = self.resultPath;
	NSTimeInterval duration = self.resultDuration;
	CGSize dimensions = self.resultDimensions;
	if (path.length == 0)
		return;

	[self.player pause];
	[self stopSession];

	if (self.onFinish)
		self.onFinish(path, duration, dimensions);
	if ([self.delegate respondsToSelector:
			@selector(videoCaptureController:didFinishWithPath:duration:dimensions:round:)])
		[self.delegate videoCaptureController:self
							didFinishWithPath:path
									 duration:duration
								   dimensions:dimensions
										round:self.roundVideoNote];
	[self dismiss];
}

- (void)cancelPressed {
	if (self.recorder.recording){
		[self.recorder cancel];
		[self resetToCamera];
		return;
	}
	if (self.reviewing){
		NSString *path = self.resultPath;
		[self resetToCamera];
		if (path.length)
			[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	}

	[self stopSession];
	if (self.onCancel)
		self.onCancel();
	if ([self.delegate respondsToSelector:@selector(videoCaptureControllerDidCancel:)])
		[self.delegate videoCaptureControllerDidCancel:self];
	[self dismiss];
}

- (void)dismiss {
	if (self.navigationController != nil && self.navigationController.viewControllers.count > 1)
		[self.navigationController popViewControllerAnimated:YES];
	else if (self.presentingViewController != nil)
		[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	if (!self.reviewing && !self.view.window)
		[self stopSession];
}

@end

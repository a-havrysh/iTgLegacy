#import "TGVideoRecorder.h"
#import <CoreMedia/CoreMedia.h>

NSString *const TGVideoRecorderErrorDomain = @"TGVideoRecorderErrorDomain";

static const NSTimeInterval TGVideoRecorderVideoMaxDuration = 600.0;
static const NSTimeInterval TGVideoRecorderNoteMaxDuration  = 60.0;
static const NSTimeInterval TGVideoRecorderMinDuration      = 0.4;
static const NSTimeInterval TGVideoRecorderTick             = 0.1;

static const long long TGVideoRecorderVideoMaxFileSize = 64ll * 1024ll * 1024ll;
static const long long TGVideoRecorderNoteMaxFileSize  = 12ll * 1024ll * 1024ll;
static const long long TGVideoRecorderVideoDiskFloor   = 40ll * 1024ll * 1024ll;
static const long long TGVideoRecorderNoteDiskFloor    = 12ll * 1024ll * 1024ll;

@interface TGVideoRecorder () <AVCaptureFileOutputRecordingDelegate>

@property (nonatomic, assign) TGVideoRecorderMode mode;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioInput;
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSString *outputPath;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, assign) NSTimeInterval lastDuration;
@property (nonatomic, assign) AVCaptureDevicePosition cameraPosition;
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, assign) BOOL recording;
@property (nonatomic, assign) BOOL discarding;
@property (nonatomic, assign) BOOL observing;
@property (nonatomic, assign) BOOL sessionWasRunning;
@property (nonatomic, strong) NSError *pendingError;

@end

@implementation TGVideoRecorder

+ (BOOL)isAvailable {
	return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] != nil;
}

- (instancetype)initWithMode:(TGVideoRecorderMode)mode {
	self = [super init];
	if (self){
		_mode = mode;
		_cameraPosition = (mode == TGVideoRecorderModeNote)
				? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
	}
	return self;
}

- (void)dealloc {
	[self teardown];
}

- (NSTimeInterval)maximumDuration {
	return self.mode == TGVideoRecorderModeNote
			? TGVideoRecorderNoteMaxDuration : TGVideoRecorderVideoMaxDuration;
}

- (long long)maximumFileSize {
	return self.mode == TGVideoRecorderModeNote
			? TGVideoRecorderNoteMaxFileSize : TGVideoRecorderVideoMaxFileSize;
}

- (long long)diskFloor {
	return self.mode == TGVideoRecorderModeNote
			? TGVideoRecorderNoteDiskFloor : TGVideoRecorderVideoDiskFloor;
}

- (NSTimeInterval)duration {
	if (!self.recording)
		return self.lastDuration;
	AVCaptureMovieFileOutput *output = self.movieOutput;
	if (output){
		CMTime recorded = output.recordedDuration;
		if (CMTIME_IS_NUMERIC(recorded)){
			Float64 seconds = CMTimeGetSeconds(recorded);
			if (seconds > 0)
				return seconds;
		}
	}
	if (self.startedAt)
		return -[self.startedAt timeIntervalSinceNow];
	return 0;
}

- (BOOL)canSwitchCamera {
	return [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count > 1;
}

#pragma mark - errors

- (NSError *)errorWithCode:(TGVideoRecorderErrorCode)code {
	return [NSError errorWithDomain:TGVideoRecorderErrorDomain code:code userInfo:nil];
}

- (void)failWithCode:(TGVideoRecorderErrorCode)code {
	NSError *error = [self errorWithCode:code];
	id<TGVideoRecorderDelegate> delegate = self.delegate;
	if ([delegate respondsToSelector:@selector(videoRecorder:didFailWithError:)])
		[delegate videoRecorder:self didFailWithError:error];
}

#pragma mark - disk

- (long long)freeDiskSpace {
	NSDictionary *attrs = [[NSFileManager defaultManager]
			attributesOfFileSystemForPath:NSTemporaryDirectory() error:nil];
	NSNumber *free = attrs[NSFileSystemFreeSize];
	return free ? [free longLongValue] : LLONG_MAX;
}

- (NSString *)temporaryPath {
	NSString *name = [NSString stringWithFormat:@"video-%.0f-%u.mp4",
			[[NSDate date] timeIntervalSince1970] * 1000.0, arc4random() % 100000];
	return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

#pragma mark - permissions

- (BOOL)cameraAccessAllowedRequestingIfNeeded {
	if (![AVCaptureDevice respondsToSelector:@selector(authorizationStatusForMediaType:)])
		return YES;

	AVAuthorizationStatus status =
			[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
	if (status == AVAuthorizationStatusAuthorized)
		return YES;

	if (status == AVAuthorizationStatusNotDetermined){
		__weak typeof(self) weakSelf = self;
		[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
								 completionHandler:^(BOOL granted){
			dispatch_async(dispatch_get_main_queue(), ^{
				TGVideoRecorder *me = weakSelf;
				if (!me)
					return;
				if (granted)
					[me prepare];
				else
					[me failWithCode:TGVideoRecorderErrorCameraAccessDenied];
			});
		}];
		return NO;
	}

	[self failWithCode:TGVideoRecorderErrorCameraAccessDenied];
	return NO;
}

- (void)requestMicrophoneAccess {
	AVAudioSession *audio = [AVAudioSession sharedInstance];
	if (![audio respondsToSelector:@selector(requestRecordPermission:)])
		return;
	__weak typeof(self) weakSelf = self;
	[audio requestRecordPermission:^(BOOL granted){
		if (granted)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			TGVideoRecorder *me = weakSelf;
			if (!me)
				return;
			if (me.recording)
				[me cancel];
			[me failWithCode:TGVideoRecorderErrorMicrophoneAccessDenied];
		});
	}];
}

#pragma mark - setup

- (AVCaptureDevice *)cameraAtPosition:(AVCaptureDevicePosition)position {
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	for (AVCaptureDevice *device in devices){
		if (device.position == position)
			return device;
	}
	return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
}

- (NSString *)preferredPresetForSession:(AVCaptureSession *)session {
	NSArray *candidates = (self.mode == TGVideoRecorderModeNote)
			? @[AVCaptureSessionPreset640x480, AVCaptureSessionPresetMedium, AVCaptureSessionPresetLow]
			: @[AVCaptureSessionPreset1280x720, AVCaptureSessionPreset640x480, AVCaptureSessionPresetMedium];
	for (NSString *preset in candidates){
		if ([session canSetSessionPreset:preset])
			return preset;
	}
	return AVCaptureSessionPresetMedium;
}

- (void)configureDevice:(AVCaptureDevice *)device {
	NSError *error = nil;
	if (![device lockForConfiguration:&error])
		return;
	if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
		device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
	if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
		device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
	if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
		device.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
	if (device.isTorchActive && [device isTorchModeSupported:AVCaptureTorchModeOff])
		device.torchMode = AVCaptureTorchModeOff;
	[device unlockForConfiguration];
}

- (void)applyConnectionSettings {
	AVCaptureConnection *video = [self.movieOutput connectionWithMediaType:AVMediaTypeVideo];
	if (!video)
		return;
	if (video.isVideoOrientationSupported)
		video.videoOrientation = AVCaptureVideoOrientationPortrait;
	if (video.isVideoMirroringSupported)
		video.videoMirrored = (self.cameraPosition == AVCaptureDevicePositionFront);
}

- (void)prepare {
	if (self.session)
		return;

	if (![self cameraAccessAllowedRequestingIfNeeded])
		return;

	AVCaptureDevice *camera = [self cameraAtPosition:self.cameraPosition];
	if (!camera){
		[self failWithCode:TGVideoRecorderErrorNoCamera];
		return;
	}
	self.cameraPosition = camera.position;

	NSError *error = nil;
	AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:camera
																			error:&error];
	if (!videoInput){
		NSLog(@"TGVideoRecorder: video input: %@", error);
		[self failWithCode:TGVideoRecorderErrorNoCamera];
		return;
	}

	AVAudioSession *audio = [AVAudioSession sharedInstance];
	NSError *audioError = nil;
	[audio setCategory:AVAudioSessionCategoryPlayAndRecord error:&audioError];
	[audio setActive:YES error:&audioError];

	AVCaptureDevice *microphone = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
	AVCaptureDeviceInput *audioInput = microphone
			? [AVCaptureDeviceInput deviceInputWithDevice:microphone error:nil] : nil;

	AVCaptureSession *session = [[AVCaptureSession alloc] init];
	[session beginConfiguration];
	session.sessionPreset = [self preferredPresetForSession:session];

	if ([session canAddInput:videoInput])
		[session addInput:videoInput];
	else {
		[session commitConfiguration];
		[self failWithCode:TGVideoRecorderErrorNoCamera];
		return;
	}
	if (audioInput && [session canAddInput:audioInput])
		[session addInput:audioInput];
	else
		audioInput = nil;

	AVCaptureMovieFileOutput *output = [[AVCaptureMovieFileOutput alloc] init];
	output.maxRecordedDuration = CMTimeMakeWithSeconds(self.maximumDuration, 30);
	output.maxRecordedFileSize = [self maximumFileSize];
	output.minFreeDiskSpaceLimit = [self diskFloor] / 2;
	if ([session canAddOutput:output])
		[session addOutput:output];
	else {
		[session commitConfiguration];
		[self failWithCode:TGVideoRecorderErrorRecordingFailed];
		return;
	}
	[session commitConfiguration];

	self.session = session;
	self.videoInput = videoInput;
	self.audioInput = audioInput;
	self.movieOutput = output;

	[self configureDevice:camera];
	[self applyConnectionSettings];

	AVCaptureVideoPreviewLayer *preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
	preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
	self.previewLayer = preview;

	[self startObserving];
	[session startRunning];
	self.ready = YES;

	[self requestMicrophoneAccess];

	id<TGVideoRecorderDelegate> delegate = self.delegate;
	if ([delegate respondsToSelector:@selector(videoRecorderDidBecomeReady:)])
		[delegate videoRecorderDidBecomeReady:self];
}

- (void)switchCamera {
	if (!self.session || self.recording || !self.canSwitchCamera)
		return;

	AVCaptureDevicePosition next = (self.cameraPosition == AVCaptureDevicePositionBack)
			? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
	AVCaptureDevice *camera = [self cameraAtPosition:next];
	if (!camera || camera.position == self.cameraPosition)
		return;

	AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:nil];
	if (!input)
		return;

	[self.session beginConfiguration];
	if (self.videoInput)
		[self.session removeInput:self.videoInput];
	if ([self.session canAddInput:input]){
		[self.session addInput:input];
		self.videoInput = input;
		self.cameraPosition = camera.position;
	} else if (self.videoInput){
		[self.session addInput:self.videoInput];
	}
	self.session.sessionPreset = [self preferredPresetForSession:self.session];
	[self.session commitConfiguration];

	[self configureDevice:camera];
	[self applyConnectionSettings];
}

#pragma mark - recording

- (void)startRecording {
	if (self.recording)
		return;
	if (!self.session){
		[self prepare];
		if (!self.session)
			return;
	}
	if (!self.session.isRunning)
		[self.session startRunning];

	if ([self freeDiskSpace] < [self diskFloor]){
		[self failWithCode:TGVideoRecorderErrorNotEnoughDiskSpace];
		return;
	}

	[self applyConnectionSettings];

	NSString *path = [self temporaryPath];
	[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	self.outputPath = path;
	self.discarding = NO;
	self.pendingError = nil;
	self.lastDuration = 0;
	self.startedAt = [NSDate date];
	self.recording = YES;

	[self.movieOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:path]
								  recordingDelegate:self];

	[self startTimer];

	id<TGVideoRecorderDelegate> delegate = self.delegate;
	if ([delegate respondsToSelector:@selector(videoRecorderDidStartRecording:)])
		[delegate videoRecorderDidStartRecording:self];
}

- (void)stopRecording {
	if (!self.recording)
		return;
	self.lastDuration = self.duration;
	[self stopTimer];
	if (self.movieOutput.isRecording)
		[self.movieOutput stopRecording];
	else
		self.recording = NO;
}

- (void)cancel {
	if (!self.recording){
		[self discardOutputFile];
		return;
	}
	self.discarding = YES;
	[self stopRecording];
}

- (void)discardOutputFile {
	if (self.outputPath)
		[[NSFileManager defaultManager] removeItemAtPath:self.outputPath error:nil];
	self.outputPath = nil;
	self.lastDuration = 0;
}

#pragma mark - timer

- (void)startTimer {
	[self stopTimer];
	self.timer = [NSTimer scheduledTimerWithTimeInterval:TGVideoRecorderTick
												  target:self
												selector:@selector(tick)
												userInfo:nil
												 repeats:YES];
}

- (void)stopTimer {
	[self.timer invalidate];
	self.timer = nil;
}

- (void)tick {
	if (!self.recording){
		[self stopTimer];
		return;
	}

	NSTimeInterval seconds = self.duration;
	NSTimeInterval maximum = self.maximumDuration;
	float progress = maximum > 0 ? (float)(seconds / maximum) : 0.0f;
	if (progress > 1.0f)
		progress = 1.0f;

	id<TGVideoRecorderDelegate> delegate = self.delegate;
	if ([delegate respondsToSelector:@selector(videoRecorder:didUpdateDuration:progress:)])
		[delegate videoRecorder:self didUpdateDuration:seconds progress:progress];

	if ([self freeDiskSpace] < [self diskFloor] / 2){
		self.pendingError = [self errorWithCode:TGVideoRecorderErrorNotEnoughDiskSpace];
		[self stopRecording];
		return;
	}

	if (seconds >= maximum)
		[self stopRecording];
}

#pragma mark - notifications

- (void)startObserving {
	if (self.observing)
		return;
	self.observing = YES;
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self
			   selector:@selector(sessionRuntimeError:)
				   name:AVCaptureSessionRuntimeErrorNotification
				 object:self.session];
	[center addObserver:self
			   selector:@selector(sessionWasInterrupted:)
				   name:AVCaptureSessionWasInterruptedNotification
				 object:self.session];
	[center addObserver:self
			   selector:@selector(sessionInterruptionEnded:)
				   name:AVCaptureSessionInterruptionEndedNotification
				 object:self.session];
	[center addObserver:self
			   selector:@selector(applicationDidEnterBackground:)
				   name:UIApplicationDidEnterBackgroundNotification
				 object:nil];
	[center addObserver:self
			   selector:@selector(applicationWillEnterForeground:)
				   name:UIApplicationWillEnterForegroundNotification
				 object:nil];
}

- (void)stopObserving {
	if (!self.observing)
		return;
	self.observing = NO;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)sessionRuntimeError:(NSNotification *)notification {
	NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
	NSLog(@"TGVideoRecorder: runtime error %@", error);
	if (self.recording){
		self.pendingError = [self errorWithCode:TGVideoRecorderErrorRecordingFailed];
		[self stopRecording];
	}
}

- (void)sessionWasInterrupted:(NSNotification *)notification {
	if (self.recording){
		self.pendingError = [self errorWithCode:TGVideoRecorderErrorInterrupted];
		[self stopRecording];
	}
}

- (void)sessionInterruptionEnded:(NSNotification *)notification {
	if (self.session && !self.session.isRunning
			&& [UIApplication sharedApplication].applicationState != UIApplicationStateBackground)
		[self.session startRunning];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
	self.sessionWasRunning = self.session.isRunning;
	if (self.recording){
		self.pendingError = [self errorWithCode:TGVideoRecorderErrorEnteredBackground];
		[self stopRecording];
	}
	[self stopTimer];
	if (self.session.isRunning)
		[self.session stopRunning];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
	if (self.session && self.sessionWasRunning && !self.session.isRunning)
		[self.session startRunning];
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)output
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
	  fromConnections:(NSArray *)connections
				error:(NSError *)error {
	if (![NSThread isMainThread]){
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			TGVideoRecorder *me = weakSelf;
			if (!me)
				return;
			[me captureOutput:output
					didFinishRecordingToOutputFileAtURL:outputFileURL
					fromConnections:connections
					error:error];
		});
		return;
	}

	self.recording = NO;
	[self stopTimer];

	BOOL usable = (error == nil);
	if (error){
		NSNumber *finished = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey];
		usable = finished ? [finished boolValue] : NO;
		if (!usable)
			NSLog(@"TGVideoRecorder: recording error %@", error);
	}

	NSString *path = outputFileURL.path ?: self.outputPath;
	self.outputPath = path;

	if (self.discarding){
		self.discarding = NO;
		self.pendingError = nil;
		[self discardOutputFile];
		return;
	}

	NSError *pending = self.pendingError;
	self.pendingError = nil;

	if (!usable){
		[self discardOutputFile];
		TGVideoRecorderErrorCode code = pending
				? (TGVideoRecorderErrorCode)pending.code : TGVideoRecorderErrorRecordingFailed;
		[self failWithCode:code];
		return;
	}

	[self deliverFileAtPath:path];
}

- (void)deliverFileAtPath:(NSString *)path {
	if (!path){
		[self failWithCode:TGVideoRecorderErrorRecordingFailed];
		return;
	}

	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
		NSTimeInterval seconds = 0;
		CMTime assetDuration = asset.duration;
		if (CMTIME_IS_NUMERIC(assetDuration))
			seconds = CMTimeGetSeconds(assetDuration);

		CGSize dimensions = CGSizeZero;
		NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
		if (tracks.count > 0){
			AVAssetTrack *track = tracks[0];
			CGSize natural = CGSizeApplyAffineTransform(track.naturalSize,
														track.preferredTransform);
			dimensions = CGSizeMake(fabs(natural.width), fabs(natural.height));
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			TGVideoRecorder *me = weakSelf;
			if (!me)
				return;

			if (seconds < TGVideoRecorderMinDuration){
				[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
				me.outputPath = nil;
				me.lastDuration = 0;
				[me failWithCode:TGVideoRecorderErrorTooShort];
				return;
			}

			CGSize reported = dimensions;
			if (me.mode == TGVideoRecorderModeNote){
				CGFloat side = MIN(dimensions.width, dimensions.height);
				if (side > 0)
					reported = CGSizeMake(side, side);
			}

			me.lastDuration = seconds;
			me.outputPath = nil;

			id<TGVideoRecorderDelegate> delegate = me.delegate;
			if ([delegate respondsToSelector:
					@selector(videoRecorder:didFinishRecordingToPath:duration:dimensions:)])
				[delegate videoRecorder:me
					didFinishRecordingToPath:path
									duration:seconds
								  dimensions:reported];
		});
	});
}

#pragma mark - teardown

- (void)teardown {
	[self stopTimer];
	[self stopObserving];

	if (self.movieOutput.isRecording){
		self.discarding = YES;
		[self.movieOutput stopRecording];
	}
	self.recording = NO;
	self.ready = NO;

	AVCaptureSession *session = self.session;
	if (session.isRunning)
		[session stopRunning];
	if (session){
		[session beginConfiguration];
		for (AVCaptureInput *input in [session.inputs copy])
			[session removeInput:input];
		for (AVCaptureOutput *output in [session.outputs copy])
			[session removeOutput:output];
		[session commitConfiguration];
	}

	[self.previewLayer removeFromSuperlayer];
	self.previewLayer = nil;
	self.movieOutput = nil;
	self.videoInput = nil;
	self.audioInput = nil;
	self.session = nil;
	self.startedAt = nil;

	AVAudioSession *audio = [AVAudioSession sharedInstance];
	NSError *audioError = nil;
	[audio setCategory:AVAudioSessionCategoryPlayback error:&audioError];
	[audio setActive:YES error:&audioError];
}

@end

// vim:ft=objc

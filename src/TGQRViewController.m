#import "TGQRViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface TGQRViewController () <AVCaptureMetadataOutputObjectsDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property (nonatomic, strong) AVCaptureMetadataOutput *output;
@property (nonatomic, strong) AVCaptureDevice *camera;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UIButton *torch;
@property (nonatomic, strong) UIView *wash;
@property (nonatomic, strong) UIView *outline;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *failureLabel;
@property (nonatomic, strong) NSString *failure;
@property (nonatomic, strong) NSString *pendingLink;
@property (nonatomic, assign) CGRect window;
@property (nonatomic, assign) BOOL handled;
@end

@implementation TGQRViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.title = @"Scan QR Code";
	self.view.backgroundColor = [UIColor colorWithRed:0x22 / 255.0f green:0x22 / 255.0f
												 blue:0x22 / 255.0f alpha:1.0f];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	[self buildFrame];
	[self startCamera];
	if (self.failure.length)
		[self showFailure:self.failure];
}

- (void)startCamera {
	if ([[UIDevice currentDevice].systemVersion floatValue] < 7.0){
		self.failure = @"QR scanning needs iOS 7 or later.";
		return;
	}

	if ([AVCaptureDevice respondsToSelector:@selector(authorizationStatusForMediaType:)]){
		AVAuthorizationStatus status =
				[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
		if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted){
			self.failure = @"Telegram does not have access to the camera. "
					@"You can allow it in Settings > Privacy > Camera.";
			return;
		}
		if (status == AVAuthorizationStatusNotDetermined){
			__weak typeof(self) weakSelf = self;
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
									 completionHandler:^(BOOL granted){
				dispatch_async(dispatch_get_main_queue(), ^{
					TGQRViewController *me = weakSelf;
					if (!me || !me.isViewLoaded)
						return;
					if (granted){
						[me startCamera];
						[me applyScanWindow];
					} else {
						[me showFailure:@"Telegram does not have access to the camera. "
								@"You can allow it in Settings > Privacy > Camera."];
					}
				});
			}];
			return;
		}
	}

	AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	NSError *error = nil;
	AVCaptureDeviceInput *input = camera
			? [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error] : nil;
	if (!input){
		self.failure = @"This device has no camera to scan with.";
		return;
	}
	self.camera = camera;

	self.session = [[AVCaptureSession alloc] init];
	[self.session addInput:input];

	AVCaptureMetadataOutput *codes = [[AVCaptureMetadataOutput alloc] init];
	[self.session addOutput:codes];
	if (![codes.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]){
		self.failure = @"This device cannot recognise QR codes.";
		self.session = nil;
		return;
	}
	[codes setMetadataObjectTypes:@[AVMetadataObjectTypeQRCode]];
	[codes setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
	self.output = codes;

	self.preview = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
	self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
	self.preview.frame = self.view.bounds;
	[self.view.layer insertSublayer:self.preview atIndex:0];

	self.failure = nil;
	[self hideFailure];
	[self.session startRunning];
	[self applyScanWindow];
	[self updateTorchButton];
}

- (void)applyScanWindow {
	if (!self.preview || CGRectIsEmpty(self.window))
		return;
	if (![self.preview respondsToSelector:@selector(metadataOutputRectOfInterestForRect:)])
		return;
	CGRect interest = [self.preview metadataOutputRectOfInterestForRect:self.window];
	if (interest.size.width > 0 && interest.size.height > 0
			&& [self.output respondsToSelector:@selector(setRectOfInterest:)])
		self.output.rectOfInterest = interest;
}

- (BOOL)torchAvailable {
	return self.camera && [self.camera respondsToSelector:@selector(hasTorch)]
			&& self.camera.hasTorch && [self.camera isTorchModeSupported:AVCaptureTorchModeOn];
}

- (void)updateTorchButton {
	if (!self.torch)
		return;
	self.torch.hidden = ![self torchAvailable] || self.failureLabel != nil;
	BOOL on = self.camera.torchMode == AVCaptureTorchModeOn;
	[self.torch setTitle:on ? @"Light Off" : @"Light On" forState:UIControlStateNormal];
}

- (void)toggleTorch {
	if (![self torchAvailable])
		return;
	NSError *error = nil;
	if (![self.camera lockForConfiguration:&error])
		return;
	self.camera.torchMode = self.camera.torchMode == AVCaptureTorchModeOn
			? AVCaptureTorchModeOff : AVCaptureTorchModeOn;
	[self.camera unlockForConfiguration];
	[self updateTorchButton];
}

- (void)buildFrame {
	CGRect b = self.view.bounds;
	CGFloat panelHeight = b.size.height > 440.0f ? 136.0f : 92.0f;
	CGRect area = CGRectMake(0, 0, b.size.width, b.size.height - panelHeight);
	CGFloat side = (int)(MIN(area.size.width, area.size.height) * 0.66f);
	CGRect window = CGRectMake((int)((area.size.width - side) / 2),
							   (int)((area.size.height - side) / 2), side, side);

	self.wash = [[UIView alloc] initWithFrame:b];
	self.wash.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5f];
	self.wash.userInteractionEnabled = NO;

	CAShapeLayer *mask = [CAShapeLayer layer];
	UIBezierPath *path = [UIBezierPath bezierPathWithRect:b];
	[path appendPath:[UIBezierPath bezierPathWithRoundedRect:window cornerRadius:8]];
	mask.path = path.CGPath;
	mask.fillRule = kCAFillRuleEvenOdd;
	self.wash.layer.mask = mask;
	[self.view addSubview:self.wash];

	self.outline = [[UIView alloc] initWithFrame:window];
	self.outline.layer.borderColor = [UIColor whiteColor].CGColor;
	self.outline.layer.borderWidth = 2;
	self.outline.layer.cornerRadius = 8;
	self.outline.userInteractionEnabled = NO;
	[self.view addSubview:self.outline];

	self.panel = [[UIView alloc] initWithFrame:CGRectMake(
			0, b.size.height - panelHeight, b.size.width, panelHeight)];
	self.panel.backgroundColor = [UIColor clearColor];
	UIImageView *panelBackground = [[UIImageView alloc] initWithFrame:self.panel.bounds];
	panelBackground.image = [[UIImage imageNamed:@"CameraStripeBottom.png"]
			stretchableImageWithLeftCapWidth:6 topCapHeight:0];
	panelBackground.userInteractionEnabled = NO;
	[self.panel addSubview:panelBackground];
	[self.view addSubview:self.panel];

	self.hint = [[UILabel alloc] initWithFrame:CGRectMake(
			20, 8, b.size.width - 40, 32)];
	self.hint.text = @"Point the camera at a QR code";
	self.hint.numberOfLines = 2;
	self.hint.textAlignment = UITextAlignmentCenter;
	self.hint.font = [UIFont boldSystemFontOfSize:14];
	self.hint.textColor = [UIColor whiteColor];
	self.hint.shadowColor = [UIColor colorWithWhite:0 alpha:0.5f];
	self.hint.shadowOffset = CGSizeMake(0, -1);
	self.hint.backgroundColor = [UIColor clearColor];
	self.hint.userInteractionEnabled = NO;
	[self.panel addSubview:self.hint];

	self.window = window;
	[self applyScanWindow];

	UIImage *plate = [[UIImage imageNamed:@"GroupedActionButton.png"]
			stretchableImageWithLeftCapWidth:24 topCapHeight:0];
	UIImage *platePressed = [[UIImage imageNamed:@"GroupedActionButton_Highlighted.png"]
			stretchableImageWithLeftCapWidth:24 topCapHeight:0];
	self.torch = [UIButton buttonWithType:UIButtonTypeCustom];
	self.torch.frame = CGRectMake((int)((b.size.width - 132) / 2),
			(int)(panelHeight - 43 - 8), 132, 43);
	self.torch.titleLabel.font = [UIFont boldSystemFontOfSize:14];
	self.torch.titleLabel.shadowOffset = CGSizeMake(0, -1);
	[self.torch setBackgroundImage:plate forState:UIControlStateNormal];
	[self.torch setBackgroundImage:platePressed forState:UIControlStateHighlighted];
	[self.torch setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[self.torch setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5f]
						   forState:UIControlStateNormal];
	[self.torch addTarget:self action:@selector(toggleTorch)
		 forControlEvents:UIControlEventTouchUpInside];
	self.torch.hidden = YES;
	[self.panel addSubview:self.torch];
	[self updateTorchButton];
}

- (void)hideFailure {
	[self.failureLabel removeFromSuperview];
	self.failureLabel = nil;
	self.wash.hidden = NO;
	self.outline.hidden = NO;
	self.hint.hidden = NO;
	[self updateTorchButton];
}

- (void)showFailure:(NSString *)message {
	self.failure = message;
	self.wash.hidden = YES;
	self.outline.hidden = YES;
	self.hint.hidden = YES;

	if (!self.failureLabel){
		self.failureLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		self.failureLabel.numberOfLines = 0;
		self.failureLabel.textAlignment = UITextAlignmentCenter;
		self.failureLabel.font = [UIFont boldSystemFontOfSize:14];
		self.failureLabel.textColor = [UIColor whiteColor];
		self.failureLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.5f];
		self.failureLabel.shadowOffset = CGSizeMake(0, -1);
		self.failureLabel.backgroundColor = [UIColor clearColor];
	}
	self.failureLabel.text = message;

	CGRect b = self.view.bounds;
	CGFloat width = b.size.width - 48;
	CGFloat panelHeight = self.panel ? self.panel.frame.size.height : 0;
	CGSize fit = [message sizeWithFont:self.failureLabel.font
					 constrainedToSize:CGSizeMake(width, b.size.height)
						 lineBreakMode:UILineBreakModeWordWrap];
	self.failureLabel.frame = CGRectMake(24,
			(int)((b.size.height - panelHeight - fit.height) / 2), width, fit.height);
	[self.view addSubview:self.failureLabel];
	[self.view bringSubviewToFront:self.failureLabel];
	[self updateTorchButton];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.handled = NO;
	if (self.session && !self.session.isRunning)
		[self.session startRunning];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.camera && self.camera.torchMode == AVCaptureTorchModeOn
			&& [self.camera lockForConfiguration:NULL]){
		self.camera.torchMode = AVCaptureTorchModeOff;
		[self.camera unlockForConfiguration];
		[self updateTorchButton];
	}
	[self.session stopRunning];
}

- (void)dealloc {
	[self.session stopRunning];
}

#pragma mark - reading

- (void)captureOutput:(AVCaptureOutput *)output
		didOutputMetadataObjects:(NSArray *)objects
				  fromConnection:(AVCaptureConnection *)connection
{
	if (self.handled)
		return;
	for (AVMetadataMachineReadableCodeObject *code in objects){
		if (![code.type isEqualToString:AVMetadataObjectTypeQRCode] || !code.stringValue.length)
			continue;
		self.handled = YES;
		[self.session stopRunning];
		NSLog(@"qr: %@", code.stringValue);
		[self actOn:code.stringValue];
		return;
	}
}

- (NSString *)usernameIn:(NSString *)text {
	NSString *candidate = nil;
	NSRange marker = [text rangeOfString:@"t.me/"];
	if (marker.location != NSNotFound){
		NSString *rest = [text substringFromIndex:NSMaxRange(marker)];
		NSRange stop = [rest rangeOfCharacterFromSet:
				[NSCharacterSet characterSetWithCharactersInString:@"/?#"]];
		candidate = stop.location == NSNotFound ? rest : [rest substringToIndex:stop.location];
	}
	if (!candidate){
		marker = [text rangeOfString:@"domain="];
		if (marker.location != NSNotFound){
			NSString *rest = [text substringFromIndex:NSMaxRange(marker)];
			NSRange stop = [rest rangeOfCharacterFromSet:
					[NSCharacterSet characterSetWithCharactersInString:@"&#"]];
			candidate = stop.location == NSNotFound ? rest : [rest substringToIndex:stop.location];
		}
	}
	if (!candidate && [text hasPrefix:@"@"] && ![text rangeOfString:@" "].length)
		candidate = [text substringFromIndex:1];
	if (!candidate)
		return nil;

	candidate = [candidate stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([candidate hasPrefix:@"@"])
		candidate = [candidate substringFromIndex:1];
	if (!candidate.length || [candidate hasPrefix:@"+"]
			|| [candidate isEqualToString:@"joinchat"] || [candidate isEqualToString:@"login"])
		return nil;

	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
			@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
	if ([candidate rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound)
		return nil;
	return candidate;
}

- (void)actOn:(NSString *)text {
	text = [text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length){
		self.handled = NO;
		[self.session startRunning];
		return;
	}

	NSString *username = [self usernameIn:text];
	if (!username.length){
		self.hint.text = text;
		BOOL isLink = [text hasPrefix:@"http://"] || [text hasPrefix:@"https://"]
				|| [text hasPrefix:@"mailto:"] || [text hasPrefix:@"tel:"];
		self.pendingLink = isLink ? text : nil;
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"QR Code"
				message:text delegate:self
				cancelButtonTitle:isLink ? @"Cancel" : @"OK"
				otherButtonTitles:isLink ? @"Open" : nil];
		[alert show];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatWithUsername:username completion:^(int64_t chatId,
															 NSString *title){
		TGQRViewController *me = weakSelf;
		if (!me)
			return;
		if (!chatId){
			me.hint.text = [NSString stringWithFormat:@"No such account: @%@", username];
			me.handled = NO;
			[me.session startRunning];
			return;
		}
		me.hint.text = @"Point the camera at a QR code";
		TGChatViewController *chat = [[TGChatViewController alloc] init];
		chat.chatId = chatId;
		chat.chatTitle = title ?: username;
		if (me.navigationController)
			[me.navigationController pushViewController:chat animated:YES];
		else
			[me presentModalViewController:
					[[UINavigationController alloc] initWithRootViewController:chat]
								  animated:YES];
	}];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	NSString *link = self.pendingLink;
	self.pendingLink = nil;
	if (link.length && buttonIndex != alertView.cancelButtonIndex){
		NSURL *url = [NSURL URLWithString:link];
		if (url && [[UIApplication sharedApplication] canOpenURL:url]){
			[[UIApplication sharedApplication] openURL:url];
			return;
		}
	}
	self.hint.text = @"Point the camera at a QR code";
	self.handled = NO;
	if (self.session && !self.session.isRunning)
		[self.session startRunning];
}

@end

// vim:ft=objc

#import "TGChatViewController.h"
#import "TGClient.h"
#import <QuartzCore/QuartzCore.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MapKit/MapKit.h>
#import <AVFoundation/AVFoundation.h>
#import "TGVoiceDecoder.h"
#import "UIImage+WebP.h"
#import "TGLottieView.h"

static const CGFloat kInputHeight = 44.0f;
static const CGFloat kBubbleMaxW  = 240.0f;
static const CGFloat kPadH        = 10.0f;
static const CGFloat kPadV        = 7.0f;
static const CGFloat kImageMax    = 200.0f;

#pragma mark - bubble cell

@interface TGBubbleCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *body;
@property (nonatomic, strong) UIImageView *picture;
@property (nonatomic, strong) UILabel *time;
@property (nonatomic, strong) TGLottieView *lottie;
@property (nonatomic, strong) UILabel *icon;        // file glyph / contact initials
@property (nonatomic, strong) UILabel *subtitle;    // size / phone number
@end

@implementation TGBubbleCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.backgroundColor = [UIColor clearColor];
	self.contentView.backgroundColor = [UIColor clearColor];
	self.selectionStyle = UITableViewCellSelectionStyleNone;

	self.bubble = [[UIView alloc] init];
	self.bubble.layer.cornerRadius = 14;
	self.bubble.layer.borderWidth = 1.0f;
	self.bubble.clipsToBounds = YES;
	[self.contentView addSubview:self.bubble];

	self.picture = [[UIImageView alloc] init];
	self.picture.contentMode = UIViewContentModeScaleAspectFill;
	self.picture.clipsToBounds = YES;
	[self.bubble addSubview:self.picture];

	self.body = [[UILabel alloc] init];
	self.body.numberOfLines = 0;
	self.body.font = [UIFont systemFontOfSize:15];
	self.body.backgroundColor = [UIColor clearColor];
	[self.bubble addSubview:self.body];

	self.icon = [[UILabel alloc] init];
	self.icon.textAlignment = NSTextAlignmentCenter;
	self.icon.textColor = [UIColor whiteColor];
	self.icon.font = [UIFont boldSystemFontOfSize:17];
	self.icon.clipsToBounds = YES;
	self.icon.hidden = YES;
	[self.bubble addSubview:self.icon];

	self.subtitle = [[UILabel alloc] init];
	self.subtitle.font = [UIFont systemFontOfSize:13];
	self.subtitle.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
	self.subtitle.backgroundColor = [UIColor clearColor];
	self.subtitle.hidden = YES;
	[self.bubble addSubview:self.subtitle];

	self.lottie = [[TGLottieView alloc] initWithFrame:CGRectZero];
	self.lottie.hidden = YES;
	[self.bubble addSubview:self.lottie];

	self.time = [[UILabel alloc] init];
	self.time.font = [UIFont systemFontOfSize:11];
	self.time.backgroundColor = [UIColor clearColor];
	self.time.textAlignment = NSTextAlignmentRight;
	[self.bubble addSubview:self.time];

	return self;
}

@end

#pragma mark - controller

@interface TGChatViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) NSArray *messages;          // flattened TDLib dicts
@property (nonatomic, strong) NSMutableDictionary *images; // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *imagesRequested;
@property (nonatomic, strong) AVAudioPlayer *voicePlayer;
@property (nonatomic, assign) BOOL anchorToBottom;
@property (nonatomic, strong) NSMutableDictionary *lottiePaths;   // fileId -> path
@property (nonatomic, strong) NSMutableDictionary *maps;          // messageId -> UIImage
@property (nonatomic, strong) NSMutableSet *mapsRequested;
@end

@implementation TGChatViewController

#pragma mark - layout

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = self.chatTitle ?: @"Chat";
	self.messages = @[];
	self.images = [NSMutableDictionary dictionary];
	self.imagesRequested = [NSMutableSet set];
	self.lottiePaths = [NSMutableDictionary dictionary];
	self.maps = [NSMutableDictionary dictionary];
	self.mapsRequested = [NSMutableSet set];
	self.view.backgroundColor = [UIColor colorWithRed:0.85f green:0.87f blue:0.83f alpha:1.0f];

	CGRect b = self.view.bounds;

	self.table = [[UITableView alloc] initWithFrame:
			CGRectMake(0, 0, b.size.width, b.size.height - kInputHeight)];
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.table.backgroundColor = [UIColor clearColor];
	self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.table];

	[self buildInputBar:b];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
			name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
			name:UIKeyboardWillHideNotification object:nil];

	// Live updates: append instead of waiting for the screen to be reopened.
	__weak typeof(self) weakSelf = self;
	[TGClient shared].onMessage = ^(int64_t chatId, NSDictionary *message, int64_t deletedId){
		TGChatViewController *me = weakSelf;
		if (!me || chatId != me.chatId)
			return;

		if (message){
			NSMutableArray *next = [me.messages mutableCopy];
			[next addObject:message];
			me.messages = next;
			[me.table reloadData];
			[me scrollToBottomAnimated:YES];
			[me fetchMissingImages];
			[[TGClient shared] markRead:@[message[@"id"]] inChat:chatId];
			return;
		}
		// deleted or edited - cheapest correct answer is to re-read
		[me reload];
	};

	[self reload];
}

- (void)buildInputBar:(CGRect)b {
	self.inputBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, b.size.height - kInputHeight, b.size.width, kInputHeight)];
	self.inputBar.backgroundColor = [UIColor colorWithWhite:0.93f alpha:1.0f];
	self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

	UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 1)];
	hair.backgroundColor = [UIColor colorWithWhite:0.75f alpha:1.0f];
	hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.inputBar addSubview:hair];

	UIButton *attach = [UIButton buttonWithType:UIButtonTypeCustom];
	attach.frame = CGRectMake(4, 6, 34, kInputHeight - 12);
	[attach setTitle:@"+" forState:UIControlStateNormal];
	[attach setTitleColor:[UIColor colorWithRed:0.24f green:0.50f blue:0.85f alpha:1.0f]
				 forState:UIControlStateNormal];
	attach.titleLabel.font = [UIFont boldSystemFontOfSize:26];
	[attach addTarget:self action:@selector(attachTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:attach];

	self.input = [[UITextField alloc] initWithFrame:
			CGRectMake(38, 7, b.size.width - 106, kInputHeight - 14)];
	self.input.borderStyle = UITextBorderStyleRoundedRect;
	self.input.placeholder = @"Message";
	self.input.font = [UIFont systemFontOfSize:15];
	self.input.returnKeyType = UIReturnKeySend;
	self.input.delegate = self;
	self.input.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.inputBar addSubview:self.input];

	// UIButtonTypeSystem is iOS 7; RoundedRect is its iOS 6 equivalent and is
	// merely deprecated later, not absent.
	UIButtonType sendType = UIButtonTypeRoundedRect;
	if (NSFoundationVersionNumber > 993.00 /* NSFoundationVersionNumber_iOS_6_1 */)
		sendType = UIButtonTypeSystem;
	self.sendButton = [UIButton buttonWithType:sendType];
	self.sendButton.frame = CGRectMake(b.size.width - 64, 6, 58, kInputHeight - 12);
	[self.sendButton setTitle:@"Send" forState:UIControlStateNormal];
	self.sendButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.sendButton addTarget:self action:@selector(sendTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:self.sendButton];

	[self.view addSubview:self.inputBar];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - data

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] historyForChat:self.chatId limit:60 completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		me.messages = messages;
		// hold the bottom until the media has settled
		me.anchorToBottom = YES;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ me.anchorToBottom = NO; });
		// kinds only - the content is the user's, the log is read remotely
		NSMutableArray *kinds = [NSMutableArray array];
		for (NSDictionary *m in messages)
			[kinds addObject:m[@"kind"] ?: @"?"];
		NSLog(@"TDLIB HISTORY: %lu msgs: %@",
				(unsigned long)messages.count, [kinds componentsJoinedByString:@", "]);
		[me.table reloadData];
		[me scrollToBottomAnimated:NO];
		[me fetchMissingImages];

		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *m in messages)
			[ids addObject:m[@"id"]];
		[[TGClient shared] markRead:ids inChat:me.chatId];
	}];
}

/// A location gets a drawn card, not a real map: MKMapSnapshotter fires no
/// completion at all on iOS 7 because Apple's tile servers stopped answering
/// clients this old. So this is a stylised plan view with a pin - honest about
/// being a placeholder, and it works with no network.
- (UIImage *)mapCardForLatitude:(double)lat longitude:(double)lon {
	CGSize size = CGSizeMake(220, 130);
	UIGraphicsBeginImageContextWithOptions(size, YES, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	// paper
	CGContextSetRGBFillColor(ctx, 0.90f, 0.91f, 0.87f, 1.0f);
	CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));

	// a few roads, placed from the coordinates so different places differ
	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
	CGContextSetLineWidth(ctx, 6);
	double seed = fabs(lat * 1000 + lon * 1000);
	for (int i = 0; i < 3; i++){
		double y = 20 + fmod(seed * (i + 3), 90);
		CGContextMoveToPoint(ctx, 0, y);
		CGContextAddLineToPoint(ctx, size.width, y - 12 + fmod(seed * (i + 1), 24));
		CGContextStrokePath(ctx);

		double x = 20 + fmod(seed * (i + 5), 180);
		CGContextMoveToPoint(ctx, x, 0);
		CGContextAddLineToPoint(ctx, x - 10 + fmod(seed * (i + 2), 20), size.height);
		CGContextStrokePath(ctx);
	}

	// greenery
	CGContextSetRGBFillColor(ctx, 0.78f, 0.86f, 0.74f, 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(fmod(seed, 120), fmod(seed, 60), 70, 44));

	// the pin, centred
	CGPoint p = CGPointMake(size.width / 2, size.height / 2);
	CGContextSetRGBFillColor(ctx, 0.0f, 0.0f, 0.0f, 0.25f);
	CGContextFillEllipseInRect(ctx, CGRectMake(p.x - 7, p.y + 6, 14, 5));
	CGContextSetRGBFillColor(ctx, 0.85f, 0.15f, 0.15f, 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(p.x - 8, p.y - 16, 16, 16));
	CGContextMoveToPoint(ctx, p.x - 5, p.y - 4);
	CGContextAddLineToPoint(ctx, p.x + 5, p.y - 4);
	CGContextAddLineToPoint(ctx, p.x, p.y + 8);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);
	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	CGContextFillEllipseInRect(ctx, CGRectMake(p.x - 3, p.y - 11, 6, 6));

	// coordinates, so the card still carries the real information
	NSString *coords = [NSString stringWithFormat:@"%.4f, %.4f", lat, lon];
	CGContextSetRGBFillColor(ctx, 0.25f, 0.27f, 0.24f, 1.0f);
	[coords drawAtPoint:CGPointMake(8, size.height - 18)
			   withFont:[UIFont systemFontOfSize:12]];

	UIImage *card = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return card;
}

- (void)fetchMissingMaps {
	for (NSDictionary *m in self.messages){
		NSNumber *lat = m[@"lat"], *lon = m[@"lon"];
		if (![lat isKindOfClass:NSNumber.class] || ![lon isKindOfClass:NSNumber.class])
			continue;
		NSNumber *key = m[@"id"];
		if (self.maps[key])
			continue;
		self.maps[key] = [self mapCardForLatitude:lat.doubleValue
										longitude:lon.doubleValue];
	}
}

- (void)fetchMissingImages {
	__weak typeof(self) weakSelf = self;
	[self fetchMissingMaps];

	// Animated stickers need the .tgs itself, not the still thumbnail.
	for (NSDictionary *m in self.messages){
		if (![m[@"docName"] isEqualToString:@"tgs"])
			continue;
		NSNumber *docId = m[@"docId"];
		if (![docId isKindOfClass:NSNumber.class] || self.lottiePaths[docId])
			continue;
		if ([self.imagesRequested containsObject:docId])
			continue;
		[self.imagesRequested addObject:docId];

		[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
			TGChatViewController *me = weakSelf;
			if (!me || !path)
				return;
			me.lottiePaths[docId] = path;
			[me.table reloadData];
			if (me.anchorToBottom)
				[me scrollToBottomAnimated:NO];
		}];
	}

	for (NSDictionary *m in self.messages){
		NSNumber *fileId = m[@"photoId"];
		if (![fileId isKindOfClass:NSNumber.class])
			continue;
		if (self.images[fileId] || [self.imagesRequested containsObject:fileId])
			continue;
		[self.imagesRequested addObject:fileId];

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			TGChatViewController *me = weakSelf;
			if (!me || !path)
				return;
			// Stickers arrive as WebP, which UIImage does not know on iOS 7.
			UIImage *img = [UIImage imageWithContentsOfFile:path];
			if (!img && [path.pathExtension.lowercaseString isEqualToString:@"webp"])
				img = [UIImage convertFromWebP:path compressedData:nil error:nil];
			if (!img){
				NSLog(@"image: cannot decode %@", path.lastPathComponent);
				return;
			}
			NSLog(@"image: %@ -> %.0fx%.0f", path.lastPathComponent,
					img.size.width, img.size.height);
			me.images[fileId] = img;
			[me.table reloadData];
			// Rows grow when an image arrives, pushing the newest messages
			// below the fold, so re-anchor to the bottom while first showing.
			if (me.anchorToBottom)
				[me scrollToBottomAnimated:NO];
		}];
	}
}

- (void)scrollToBottomAnimated:(BOOL)animated {
	if (!self.messages.count)
		return;
	NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
	[self.table scrollToRowAtIndexPath:last
					  atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

#pragma mark - sending

- (void)sendTapped {
	NSString *text = [self.input.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length)
		return;

	[[TGClient shared] sendText:text toChat:self.chatId];
	self.input.text = @"";

	// TDLib echoes the message back as an update; refresh shortly after.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		[self reload];
	});
}

#pragma mark - attachments

- (void)attachTapped {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary])
		return;

	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info
{
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (!image)
		return;

	// TDLib wants a path, so write the pick to a temporary file first.
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"outgoing.jpg"];
	if (![UIImageJPEGRepresentation(image, 0.85f) writeToFile:path atomically:YES]){
		NSLog(@"cannot stage the picked image");
		return;
	}
	[[TGClient shared] sendPhotoAtPath:path toChat:self.chatId];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - taps

- (void)simulateTapOnRow:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.messages.count){
		NSLog(@"tap: row %ld out of range (%lu)",
				(long)row, (unsigned long)self.messages.count);
		return;
	}
	NSLog(@"tap: row %ld, kind %@", (long)row, self.messages[row][@"kind"]);
	[self tableView:self.table
			didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:NO];
	NSDictionary *m = self.messages[indexPath.row];
	NSString *kind = m[@"kind"];

	// Video and video notes play; a photo opens full screen.
	if ([kind isEqualToString:@"messageVideo"] ||
		[kind isEqualToString:@"messageVideoNote"]){
		NSNumber *docId = m[@"docId"];
		if (![docId isKindOfClass:NSNumber.class])
			return;
		[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
			if (!path)
				return;
			MPMoviePlayerViewController *player = [[MPMoviePlayerViewController alloc]
					initWithContentURL:[NSURL fileURLWithPath:path]];
			[self presentMoviePlayerViewControllerAnimated:player];
		}];
		return;
	}

	// Voice notes are Opus, which iOS 7 cannot decode - convert, then play.
	if ([kind isEqualToString:@"messageVoiceNote"] ||
		[kind isEqualToString:@"messageAudio"]){
		NSNumber *docId = m[@"docId"];
		if (![docId isKindOfClass:NSNumber.class])
			return;
		[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
			if (!path)
				return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				NSString *wav = [TGVoiceDecoder wavFromOpusFile:path];
				dispatch_async(dispatch_get_main_queue(), ^{
					if (!wav){
						[self showPlaybackFailure];
						return;
					}
					NSError *err = nil;
					[[AVAudioSession sharedInstance]
							setCategory:AVAudioSessionCategoryPlayback error:nil];
					[[AVAudioSession sharedInstance] setActive:YES error:nil];
					self.voicePlayer = [[AVAudioPlayer alloc]
							initWithContentsOfURL:[NSURL fileURLWithPath:wav] error:&err];
					if (err){
						NSLog(@"voice playback: %@", err);
						[self showPlaybackFailure];
						return;
					}
					[self.voicePlayer play];
				});
			});
		}];
		return;
	}

	if ([kind isEqualToString:@"messagePhoto"]){
		NSNumber *fileId = m[@"photoId"];
		UIImage *img = [fileId isKindOfClass:NSNumber.class] ? self.images[fileId] : nil;
		if (img)
			[self showFullScreenImage:img];
	}
}

- (void)showPlaybackFailure {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
													message:@"Cannot play this audio"
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

/// Simple full-screen viewer: black backdrop, tap anywhere to dismiss.
- (void)showFullScreenImage:(UIImage *)image {
	UIWindow *window = [UIApplication sharedApplication].keyWindow;

	UIView *backdrop = [[UIView alloc] initWithFrame:window.bounds];
	backdrop.backgroundColor = [UIColor blackColor];
	backdrop.tag = 0xF117;

	UIImageView *view = [[UIImageView alloc] initWithFrame:backdrop.bounds];
	view.contentMode = UIViewContentModeScaleAspectFit;
	view.image = image;
	[backdrop addSubview:view];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(dismissFullScreen:)];
	[backdrop addGestureRecognizer:tap];

	backdrop.alpha = 0;
	[window addSubview:backdrop];
	[UIView animateWithDuration:0.2 animations:^{ backdrop.alpha = 1; }];
}

- (void)dismissFullScreen:(UITapGestureRecognizer *)tap {
	UIView *backdrop = tap.view;
	[UIView animateWithDuration:0.2 animations:^{ backdrop.alpha = 0; }
					 completion:^(BOOL done){ [backdrop removeFromSuperview]; }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[self sendTapped];
	return NO;
}

#pragma mark - geometry

/// Size of the text inside a bubble, and of the bubble itself.
- (CGSize)bodySizeFor:(NSDictionary *)m {
	NSString *text = m[@"text"] ?: @"";
	if (!text.length)
		return CGSizeZero;
	return [text sizeWithFont:[UIFont systemFontOfSize:15]
			constrainedToSize:CGSizeMake(kBubbleMaxW - 2 * kPadH, 10000)
				lineBreakMode:NSLineBreakByWordWrapping];
}

- (UIImage *)imageFor:(NSDictionary *)m {
	UIImage *map = self.maps[m[@"id"]];
	if (map)
		return map;
	NSNumber *fileId = m[@"photoId"];
	return [fileId isKindOfClass:NSNumber.class] ? self.images[fileId] : nil;
}

- (CGSize)imageSizeFor:(NSDictionary *)m {
	UIImage *img = [self imageFor:m];
	if (!img)
		return CGSizeZero;

	CGFloat scale = MIN(kImageMax / img.size.width, kImageMax / img.size.height);
	scale = MIN(scale, 1.0f);
	return CGSizeMake(floorf(img.size.width * scale), floorf(img.size.height * scale));
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *m = self.messages[indexPath.row];
	CGSize body = [self bodySizeFor:m];
	CGSize pic  = [self imageSizeFor:m];

	if ([m[@"kind"] isEqualToString:@"messageVideoNote"] && pic.height > 0)
		return MIN(pic.width, pic.height) + 20;

	if ([m[@"docName"] isEqualToString:@"tgs"] && self.lottiePaths[m[@"docId"]])
		return 148;

	if ([m[@"kind"] isEqualToString:@"messageDocument"] ||
		[m[@"kind"] isEqualToString:@"messageContact"])
		return 64;

	CGFloat h = kPadV * 2 + 14;                 // padding + time line
	if (pic.height > 0) h += pic.height + 4;
	if (body.height > 0) h += body.height;
	return MAX(h + 6, 40);
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGBubbleCell";
	TGBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];

	NSDictionary *m = self.messages[indexPath.row];
	BOOL mine = [m[@"outgoing"] boolValue];
	NSString *kind = m[@"kind"];

	// Stickers never sit in a bubble - they are drawn straight on the wallpaper.
	BOOL isSticker = [kind isEqualToString:@"messageSticker"] ||
					 [kind isEqualToString:@"messageAnimatedEmoji"];

	cell.icon.hidden = YES;
	cell.subtitle.hidden = YES;
	cell.lottie.hidden = YES;
	[cell.lottie stop];

	// Documents and contacts get their own layout: a round glyph on the left,
	// a bold first line and a grey second one. Rendering them as plain text
	// made them indistinguishable from a message that merely mentions a file.
	if ([kind isEqualToString:@"messageDocument"] ||
		[kind isEqualToString:@"messageContact"]){
		BOOL isDoc = [kind isEqualToString:@"messageDocument"];
		NSArray *lines = [m[@"text"] componentsSeparatedByString:@"\n"];
		NSString *first = lines.count ? lines[0] : @"";
		NSString *second = lines.count > 1 ? lines[1] : @"";

		CGFloat width = 250;
		CGFloat height = 58;
		CGFloat x = mine ? (tableView.bounds.size.width - width - 8) : 8;
		cell.bubble.frame = CGRectMake(x, 3, width, height);
		cell.bubble.backgroundColor = mine
			? [UIColor colorWithRed:0.85f green:0.96f blue:0.76f alpha:1.0f]
			: [UIColor whiteColor];
		cell.bubble.layer.borderWidth = 1.0f;
		cell.bubble.layer.borderColor = [UIColor colorWithWhite:0.0f alpha:0.12f].CGColor;

		cell.icon.hidden = NO;
		cell.icon.frame = CGRectMake(kPadH, 11, 36, 36);
		cell.icon.layer.cornerRadius = 18;
		if (isDoc){
			cell.icon.text = @"\u25a4";              // a sheet of paper
			cell.icon.backgroundColor = [UIColor colorWithRed:0.24f green:0.60f blue:0.92f alpha:1.0f];
		} else {
			// initials read better than a generic person glyph
			NSString *initials = first.length ? [first substringToIndex:1] : @"?";
			NSArray *words = [first componentsSeparatedByString:@" "];
			if (words.count > 1 && [words[1] length])
				initials = [initials stringByAppendingString:[words[1] substringToIndex:1]];
			cell.icon.text = initials.uppercaseString;
			cell.icon.backgroundColor = [UIColor colorWithRed:0.36f green:0.72f blue:0.45f alpha:1.0f];
		}

		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont boldSystemFontOfSize:15];
		cell.body.textColor = [UIColor colorWithWhite:0.08f alpha:1.0f];
		cell.body.text = first;
		cell.body.frame = CGRectMake(56, 10, width - 66, 20);

		cell.subtitle.hidden = NO;
		cell.subtitle.text = second;
		cell.subtitle.frame = CGRectMake(56, 30, width - 66, 18);

		static NSDateFormatter *hmd = nil;
		if (!hmd){ hmd = [[NSDateFormatter alloc] init]; [hmd setDateFormat:@"HH:mm"]; }
		cell.time.text = [hmd stringFromDate:
				[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
		cell.time.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
		cell.time.frame = CGRectMake(width - 50, height - 16, 44, 12);
		cell.picture.hidden = YES;
		return cell;
	}

	CGSize body = [self bodySizeFor:m];
	CGSize pic  = [self imageSizeFor:m];

	CGFloat contentW = MAX(body.width, pic.width);
	CGFloat bubbleW  = MAX(contentW + 2 * kPadH, 56);
	CGFloat bubbleH  = kPadV * 2 + 14 + (pic.height ? pic.height + 4 : 0) + body.height;

	CGFloat x = mine ? (tableView.bounds.size.width - bubbleW - 8) : 8;
	cell.bubble.frame = CGRectMake(x, 3, bubbleW, bubbleH);

	// Outgoing green, incoming white - the convention every client uses.
	// A sticker gets neither: no fill, no border.
	cell.bubble.backgroundColor = isSticker ? [UIColor clearColor] : (mine
		? [UIColor colorWithRed:0.85f green:0.96f blue:0.76f alpha:1.0f]
		: [UIColor whiteColor]);
	cell.bubble.layer.borderWidth = isSticker ? 0.0f : 1.0f;
	cell.bubble.layer.borderColor = [UIColor colorWithWhite:0.0f alpha:0.12f].CGColor;

	// A video note is a circle, with no bubble around it - that is how every
	// client draws them.
	BOOL isRound = [m[@"kind"] isEqualToString:@"messageVideoNote"];
	if (isRound && pic.height > 0){
		CGFloat side = MIN(pic.width, pic.height);
		cell.bubble.backgroundColor = [UIColor clearColor];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.frame = CGRectMake(mine ? (tableView.bounds.size.width - side - 8) : 8,
				3, side, side + 14);
		cell.picture.hidden = NO;
		cell.picture.image = [self imageFor:m];
		cell.picture.frame = CGRectMake(0, 0, side, side);
		cell.picture.layer.cornerRadius = side / 2;
		cell.body.hidden = YES;

		static NSDateFormatter *hmr = nil;
		if (!hmr){ hmr = [[NSDateFormatter alloc] init]; [hmr setDateFormat:@"HH:mm"]; }
		cell.time.text = [hmr stringFromDate:
				[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
		cell.time.textColor = [UIColor colorWithWhite:0.35f alpha:1.0f];
		cell.time.frame = CGRectMake(side - 44, side, 44, 12);
		return cell;
	}

	// An animated sticker plays in place of the still image.
	NSString *tgsPath = [m[@"docName"] isEqualToString:@"tgs"]
			? self.lottiePaths[m[@"docId"]] : nil;
	if (tgsPath){
		CGFloat side = 128;
		cell.bubble.backgroundColor = [UIColor clearColor];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.frame = CGRectMake(mine ? (tableView.bounds.size.width - side - 8) : 8,
				3, side, side + 14);
		cell.picture.hidden = YES;
		cell.body.hidden = YES;
		cell.lottie.hidden = NO;
		cell.lottie.frame = CGRectMake(0, 0, side, side);
		[cell.lottie loadTGSFile:tgsPath];
		[cell.lottie play];

		static NSDateFormatter *hmt = nil;
		if (!hmt){ hmt = [[NSDateFormatter alloc] init]; [hmt setDateFormat:@"HH:mm"]; }
		cell.time.text = [hmt stringFromDate:
				[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
		cell.time.textColor = [UIColor colorWithWhite:0.35f alpha:1.0f];
		cell.time.frame = CGRectMake(side - 44, side, 44, 12);
		return cell;
	}
	CGFloat y = kPadV;
	if (pic.height > 0){
		cell.picture.hidden = NO;
		cell.picture.image = [self imageFor:m];
		cell.picture.frame = CGRectMake(kPadH, y, pic.width, pic.height);
		cell.picture.layer.cornerRadius = 8;
		y += pic.height + 4;
	} else {
		cell.picture.hidden = YES;
		cell.picture.image = nil;
	}

	cell.body.hidden = (body.height == 0);
	cell.body.numberOfLines = 0;
	cell.body.font = [UIFont systemFontOfSize:15];
	cell.body.text = m[@"text"];
	cell.body.textColor = [UIColor colorWithWhite:0.08f alpha:1.0f];
	cell.body.frame = CGRectMake(kPadH, y, body.width, body.height);

	static NSDateFormatter *hm = nil;
	if (!hm){ hm = [[NSDateFormatter alloc] init]; [hm setDateFormat:@"HH:mm"]; }
	cell.time.text = [hm stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
	cell.time.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
	cell.time.frame = CGRectMake(bubbleW - 44 - kPadH + 6, bubbleH - kPadV - 12, 44, 12);

	return cell;
}

#pragma mark - keyboard

- (void)keyboardWillShow:(NSNotification *)note {
	CGRect kb = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	[self shiftForKeyboardHeight:kb.size.height];
}

- (void)keyboardWillHide:(NSNotification *)note {
	[self shiftForKeyboardHeight:0];
}

- (void)shiftForKeyboardHeight:(CGFloat)height {
	CGRect b = self.view.bounds;
	[UIView animateWithDuration:0.25 animations:^{
		self.inputBar.frame = CGRectMake(0, b.size.height - kInputHeight - height,
				b.size.width, kInputHeight);
		self.table.frame = CGRectMake(0, 0, b.size.width,
				b.size.height - kInputHeight - height);
	} completion:^(BOOL done){
		[self scrollToBottomAnimated:NO];
	}];
}

@end

// vim:ft=objc

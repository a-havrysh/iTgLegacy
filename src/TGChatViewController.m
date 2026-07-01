#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGForwardPicker.h"
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
@property (nonatomic, strong) UILabel *sender;     // who wrote it, groups only
@property (nonatomic, strong) UIView  *quoteBar;   // the stripe beside a quote
@property (nonatomic, strong) UILabel *quote;      // what is being replied to
@property (nonatomic, strong) UIImageView *ticks;  // delivery marks
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

	self.sender = [[UILabel alloc] init];
	self.sender.font = [UIFont boldSystemFontOfSize:12];
	self.sender.backgroundColor = [UIColor clearColor];
	self.sender.hidden = YES;
	[self.contentView addSubview:self.sender];

	self.ticks = [[UIImageView alloc] init];
	self.ticks.hidden = YES;
	[self.bubble addSubview:self.ticks];

	self.quoteBar = [[UIView alloc] init];
	self.quoteBar.hidden = YES;
	[self.bubble addSubview:self.quoteBar];

	self.quote = [[UILabel alloc] init];
	self.quote.font = [UIFont systemFontOfSize:13];
	self.quote.numberOfLines = 2;
	self.quote.backgroundColor = [UIColor clearColor];
	self.quote.hidden = YES;
	[self.bubble addSubview:self.quote];

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
@property (nonatomic, strong) NSMutableDictionary *quotes;       // messageId -> flattened
@property (nonatomic, strong) NSMutableSet *quotesRequested;
@property (nonatomic, strong) NSDictionary *actionMessage;   // long-pressed
@property (nonatomic, assign) int64_t replyToId;             // composing a reply
@property (nonatomic, assign) int64_t editingId;             // editing instead
@property (nonatomic, strong) UIView *composeBanner;         // "Reply to ..."

- (void)clearComposeState;
- (void)showComposeBanner:(NSString *)text;
@end

@implementation TGChatViewController

#pragma mark - layout

- (void)viewDidLoad {
	[super viewDidLoad];

	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self buildTitleView];
	self.messages = @[];
	self.images = [NSMutableDictionary dictionary];
	self.imagesRequested = [NSMutableSet set];
	self.lottiePaths = [NSMutableDictionary dictionary];
	self.maps = [NSMutableDictionary dictionary];
	self.mapsRequested = [NSMutableSet set];
	self.quotes = [NSMutableDictionary dictionary];
	self.quotesRequested = [NSMutableSet set];
	self.view.backgroundColor = [[TGTheme shared] chatBackgroundColour];

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

/// A two-line header: the chat name with member count or status beneath it,
/// which is what tells you where you are in a group.
- (void)buildTitleView {
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 40)];

	UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(0, 1, 200, 20)];
	name.text = self.chatTitle ?: @"Chat";
	name.font = [UIFont boldSystemFontOfSize:17];
	name.textColor = [[TGTheme shared] barTitleColour];
	name.backgroundColor = [UIColor clearColor];
	name.textAlignment = NSTextAlignmentCenter;
	if (![TGTheme shared].isFlat){
		name.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.4f];
		name.shadowOffset = CGSizeMake(0, -1);
	}
	[header addSubview:name];

	UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(0, 21, 200, 14)];
	subtitle.font = [UIFont systemFontOfSize:12];
	subtitle.textColor = [TGTheme shared].isFlat
			? [[TGTheme shared] secondaryTextColour]
			: [UIColor colorWithWhite:1.0f alpha:0.75f];
	subtitle.backgroundColor = [UIColor clearColor];
	subtitle.textAlignment = NSTextAlignmentCenter;
	[header addSubview:subtitle];

	self.navigationItem.titleView = header;

	if (!self.isGroup)
		return;

	[[TGClient shared] memberCountForChat:self.chatId completion:^(NSInteger count){
		if (count > 0)
			subtitle.text = [NSString stringWithFormat:@"%ld members", (long)count];
	}];
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
	[attach setImage:[TGIcons attach] forState:UIControlStateNormal];
	attach.tintColor = [[TGTheme shared] accentColour];
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
	[[TGClient shared] historyForChat:self.chatId thread:self.threadId limit:60 completion:^(NSArray *messages){
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
		[me resolveUnknownSenders];
		[me fetchMissingQuotes];

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

/// Group messages need a name over the bubble, and TDLib only volunteers
/// users it happens to have sent already - the rest have to be asked for.
- (void)resolveUnknownSenders {
	__weak typeof(self) weakSelf = self;
	NSMutableSet *wanted = [NSMutableSet set];
	for (NSDictionary *m in self.messages){
		int64_t sender = [m[@"senderId"] longLongValue];
		if (sender != 0 && ![[TGClient shared] nameForUserId:sender])
			[wanted addObject:@(sender)];
	}

	for (NSNumber *uid in wanted){
		[[TGClient shared] ensureUserName:uid.longLongValue completion:^{
			[weakSelf.table reloadData];
		}];
	}
}

/// A reply shows what it answers. TDLib only inlines the quote sometimes, so
/// the original is fetched when it does not.
- (void)fetchMissingQuotes {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *m in self.messages){
		NSNumber *replyId = m[@"replyId"];
		if (![replyId isKindOfClass:NSNumber.class])
			continue;
		if ([m[@"replyText"] length] || self.quotes[replyId] ||
			[self.quotesRequested containsObject:replyId])
			continue;
		[self.quotesRequested addObject:replyId];

		[[TGClient shared] messageWithId:replyId.longLongValue
								  inChat:self.chatId
							  completion:^(NSDictionary *original){
			TGChatViewController *me = weakSelf;
			if (!me || !original)
				return;
			me.quotes[replyId] = original;
			[me.table reloadData];
		}];
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

	if (self.editingId != 0)
		[[TGClient shared] editMessage:self.editingId inChat:self.chatId text:text];
	else
		[[TGClient shared] sendText:text toChat:self.chatId
							 thread:self.threadId replyTo:self.replyToId];

	[self clearComposeState];

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
/// The quote block a reply carries, and the "forwarded from" line above it.
- (NSString *)quoteTextFor:(NSDictionary *)m {
	NSNumber *replyId = m[@"replyId"];
	if (![replyId isKindOfClass:NSNumber.class])
		return nil;
	NSString *inline_ = m[@"replyText"];
	if (inline_.length)
		return inline_;
	NSDictionary *fetched = self.quotes[replyId];
	return fetched[@"text"] ?: @"...";
}

- (CGFloat)decorationHeightFor:(NSDictionary *)m {
	CGFloat h = 0;
	if ([m[@"forward"] length])
		h += 16;
	if ([self quoteTextFor:m])
		h += 32;
	return h;
}

/// "12:29" for incoming, "12:29 ✓✓" for outgoing, "edited" in front when it
/// applies - the same line Telegram tucks into the corner of the bubble.
- (NSString *)stampFor:(NSDictionary *)m {
	static NSDateFormatter *hm = nil;
	if (!hm){ hm = [[NSDateFormatter alloc] init]; [hm setDateFormat:@"HH:mm"]; }

	NSString *stamp = [hm stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
	if ([m[@"edited"] boolValue])
		stamp = [NSString stringWithFormat:@"edited %@", stamp];
	return stamp;   // the ticks are drawn beside it, not spelled out
}

- (CGFloat)timeWidthFor:(NSDictionary *)m {
	CGFloat w = [[self stampFor:m] sizeWithFont:[UIFont systemFontOfSize:11]].width + 2;
	if ([m[@"outgoing"] boolValue])
		w += 18;   // room for the ticks
	return w;
}

/// Telegram puts the stamp at the end of the last line when it fits there,
/// and only drops it to its own line when it does not. Anything else leaves a
/// gap under short messages, which is what looked wrong.
- (BOOL)stampFitsInlineFor:(NSDictionary *)m {
	NSString *text = m[@"text"] ?: @"";
	if (!text.length || [text rangeOfString:@"\n"].location != NSNotFound)
		return NO;

	CGFloat oneLine = [text sizeWithFont:[UIFont systemFontOfSize:15]].width;
	if (oneLine > kBubbleMaxW - 2 * kPadH)
		return NO;   // it wraps, so there is no short last line to share

	return (oneLine + 6 + [self timeWidthFor:m]) <= (kBubbleMaxW - 2 * kPadH);
}

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

	if ([m[@"service"] boolValue])
		return 30;

	if ([m[@"kind"] isEqualToString:@"messageDocument"] ||
		[m[@"kind"] isEqualToString:@"messageContact"])
		return 64;

	CGFloat h = kPadV * 2 + [self decorationHeightFor:m] +
			([self stampFitsInlineFor:m] ? 0 : 14);
	if (self.isGroup && ![m[@"outgoing"] boolValue] &&
		[[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]])
		h += 15;                                // room for the sender line
	if (pic.height > 0) h += pic.height + 4;
	if (body.height > 0) h += body.height;
	return MAX(h + 6, 40);
}

/// Clients colour each participant's name; the same person keeps the same
/// colour because it is derived from their id.
static UIColor *TGSenderColour(int64_t userId) {
	static NSArray *palette = nil;
	if (!palette)
		palette = @[[UIColor colorWithRed:0.85f green:0.27f blue:0.27f alpha:1],
					[UIColor colorWithRed:0.20f green:0.55f blue:0.85f alpha:1],
					[UIColor colorWithRed:0.25f green:0.62f blue:0.35f alpha:1],
					[UIColor colorWithRed:0.75f green:0.45f blue:0.15f alpha:1],
					[UIColor colorWithRed:0.55f green:0.35f blue:0.75f alpha:1],
					[UIColor colorWithRed:0.20f green:0.60f blue:0.62f alpha:1]];
	return palette[(NSUInteger)llabs(userId) % palette.count];
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
	cell.sender.hidden = YES;

	// Service messages sit centred on the wallpaper, not in a bubble - joins,
	// renames, pins. Groups are full of them.
	if ([m[@"service"] boolValue]){
		CGFloat width = tableView.bounds.size.width - 40;
		cell.bubble.frame = CGRectMake(20, 4, width, 22);
		cell.bubble.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.10f];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.layer.cornerRadius = 11;
		cell.picture.hidden = YES;
		cell.time.text = @"";
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont systemFontOfSize:12];
		cell.body.textAlignment = NSTextAlignmentCenter;
		cell.body.textColor = [UIColor colorWithWhite:0.30f alpha:1.0f];
		// "joined the group" reads oddly with nobody attached to it.
		NSString *who = [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
		cell.body.text = who.length
				? [NSString stringWithFormat:@"%@ %@", who, m[@"text"]]
				: m[@"text"];
		cell.body.frame = CGRectMake(0, 3, width, 16);
		return cell;
	}
	cell.body.textAlignment = NSTextAlignmentLeft;
	cell.bubble.layer.cornerRadius = 14;
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

	// The bubble has to fit whichever is widest: the text, a picture, the
	// quoted message, or the timestamp. Sizing it on the text alone squeezed
	// quotes down to an ellipsis.
	BOOL inlineStamp = [self stampFitsInlineFor:m];
	CGFloat timeW = [self timeWidthFor:m];
	CGFloat contentW = MAX(body.width, pic.width);
	if ([self quoteTextFor:m] || [m[@"forward"] length])
		contentW = MAX(contentW, 170);
	if (inlineStamp)
		contentW = MAX(contentW, body.width + 6 + timeW);   // they share the last line

	CGFloat bubbleW = MAX(contentW + 2 * kPadH, timeW + 2 * kPadH + 8);
	bubbleW = MIN(bubbleW, kBubbleMaxW + 2 * kPadH);
	CGFloat bubbleH  = kPadV * 2 + (inlineStamp ? 0 : 14) + [self decorationHeightFor:m] +
			(pic.height ? pic.height + 4 : 0) + body.height;

	CGFloat x = mine ? (tableView.bounds.size.width - bubbleW - 8) : 8;
	CGFloat top = 3;

	// In a group you need to know who is speaking.
	NSString *senderName = (self.isGroup && !mine)
			? [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]] : nil;
	if (senderName.length){
		cell.sender.hidden = NO;
		cell.sender.text = senderName;
		cell.sender.textColor = TGSenderColour([m[@"senderId"] longLongValue]);
		cell.sender.frame = CGRectMake(x + kPadH, 2, tableView.bounds.size.width - x - 20, 14);
		top = 18;
	}

	cell.bubble.frame = CGRectMake(x, top, bubbleW, bubbleH);

	// Outgoing green, incoming white - the convention every client uses.
	// A sticker gets neither: no fill, no border.
	TGTheme *theme = [TGTheme shared];
	cell.bubble.backgroundColor = isSticker ? [UIColor clearColor] : (mine
		? [theme bubbleMineColour] : [theme bubbleTheirsColour]);
	cell.bubble.layer.borderWidth = isSticker ? 0.0f : [theme bubbleBorderWidth];
	cell.bubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
	cell.bubble.layer.cornerRadius = [theme bubbleCornerRadius];
	// A flat outgoing bubble is a solid accent colour, so its text inverts.
	cell.body.textColor = (mine && theme.isFlat)
		? [UIColor whiteColor] : [theme primaryTextColour];

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

	// "Forwarded from X", then the quote block, then the message itself.
	cell.quoteBar.hidden = YES;
	cell.quote.hidden = YES;

	NSString *forwarded = m[@"forward"];
	if ([forwarded length]){
		cell.quote.hidden = NO;
		cell.quote.numberOfLines = 1;
		cell.quote.font = [UIFont italicSystemFontOfSize:12];
		cell.quote.textColor = [theme accentColour];
		cell.quote.text = [NSString stringWithFormat:@"Forwarded from %@", forwarded];
		cell.quote.frame = CGRectMake(kPadH, y, bubbleW - 2 * kPadH, 14);
		y += 16;
	}

	NSString *quoted = [self quoteTextFor:m];
	if (quoted){
		cell.quoteBar.hidden = NO;
		cell.quoteBar.backgroundColor = [theme accentColour];
		cell.quoteBar.frame = CGRectMake(kPadH, y, 2, 28);

		// the forward line above reuses the same label, so build a second one
		UILabel *q = cell.quote.hidden ? cell.quote : nil;
		if (!q){
			q = [[UILabel alloc] init];
			q.tag = 0x9001;
			q.font = [UIFont systemFontOfSize:13];
			q.numberOfLines = 2;
			q.backgroundColor = [UIColor clearColor];
			UILabel *existing = (UILabel *)[cell.bubble viewWithTag:0x9001];
			if (existing) q = existing; else [cell.bubble addSubview:q];
		}
		q.hidden = NO;
		q.numberOfLines = 2;
		q.font = [UIFont systemFontOfSize:13];
		q.textColor = [theme secondaryTextColour];
		q.text = quoted;
		q.frame = CGRectMake(kPadH + 8, y, bubbleW - 2 * kPadH - 10, 28);
		y += 32;
	} else {
		UILabel *existing = (UILabel *)[cell.bubble viewWithTag:0x9001];
		existing.hidden = YES;
	}

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
	cell.body.frame = CGRectMake(kPadH, y, body.width, body.height);

	cell.time.text = [self stampFor:m];
	cell.time.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
	CGFloat tickW = mine ? 18 : 0;
	CGFloat stampY = inlineStamp ? (y + body.height - 14) : (bubbleH - kPadV - 13);
	cell.time.frame = CGRectMake(bubbleW - timeW - kPadH, stampY, timeW - tickW, 12);

	cell.ticks.hidden = !mine;
	if (mine){
		cell.ticks.image = [TGIcons ticksWhite:theme.isFlat];
		cell.ticks.frame = CGRectMake(bubbleW - kPadH - 15, stampY + 2, 15, 9);
	}

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

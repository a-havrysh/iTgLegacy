#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGForwardPicker.h"
#import "TGVoiceRecorder.h"
#import "TGProfileViewController.h"
#import "TGThemeFile.h"
#import "TGCapabilities.h"
#import <AddressBookUI/AddressBookUI.h>
#import <CoreLocation/CoreLocation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <QuartzCore/QuartzCore.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MapKit/MapKit.h>
#import <AVFoundation/AVFoundation.h>
#import "TGVoiceDecoder.h"
#import "UIImage+WebP.h"
#import "TGLottieView.h"
#import "UIView+SafeTint.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGSnackbar.h"

// Their design system is drawn for Android at 360dp; a 4S is 320pt, so
// everything taken from it is scaled by 0.889 and rounded to a whole point.
static const CGFloat kInputHeight = 43.0f;
// Msg_In.png / Msg_Out.png carry the tail inside the artwork: their body
// padding is 15+1 on the tail side against 9+1 on the other, so the picture
// hangs 6pt past the content box.
static const CGFloat kBubbleTailOverhang = 6.0f;
static const CGFloat kBubbleMinW = 40.0f;
static const CGFloat kBubbleMinH = 31.0f;
static const CGFloat kBubbleMaxW  = 240.0f;
static const CGFloat kPadH        = 10.0f;
static const CGFloat kAvatarSide  = 28.0f;   // sender avatar in groups
static const CGFloat kPadV        = 7.0f;
static const CGFloat kImageMax    = 200.0f;
// Their file block: an 80dp tile carrying a 42dp disc, 71 and 37 here.
static const CGFloat kFileTile    = 71.0f;
static const CGFloat kFileDisc    = 37.0f;
// A picture in a bubble is clipped to the same radius their media uses.
static const CGFloat kMediaRadius = 6.0f;
// One option of a poll: a 16 circle, the text, the share, and the bar under it.
static const CGFloat kPollRow     = 30.0f;

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
@property (nonatomic, strong) UIImageView *senderAvatar;  // groups only
@property (nonatomic, strong) UIImageView *tail;         // the curl off the corner
@property (nonatomic, strong) UIImageView *disc;        // play button on media
@property (nonatomic, strong) UIImageView *wave;        // voice message bars
@property (nonatomic, strong) UILabel *mediaStamp;      // the time over a picture
/// Kept so playback can repaint this one row's bars without a table reload.
@property (nonatomic, assign) int64_t voiceMessageId;
@property (nonatomic, strong) NSData *waveformData;
/// Which poll this cell is drawing, so an option knows what it is voting in.
@property (nonatomic, assign) int64_t pollMessageId;
/// "Forwarded from X" above the content, whatever the content turns out to be.
@property (nonatomic, strong) UILabel *forwardLabel;
/// Msg_In.png / Msg_Out.png stretched behind the content box.
@property (nonatomic, strong) UIImageView *bubbleBg;
@end

@implementation TGBubbleCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.backgroundColor = [UIColor clearColor];
	self.contentView.backgroundColor = [UIColor clearColor];
	self.selectionStyle = UITableViewCellSelectionStyleNone;

	self.bubbleBg = [[UIImageView alloc] init];
	self.bubbleBg.hidden = YES;
	[self.contentView addSubview:self.bubbleBg];

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
	self.body.font = [UIFont systemFontOfSize:[TGTheme shared].messageFontSize];
	self.body.backgroundColor = [UIColor clearColor];
	[self.bubble addSubview:self.body];

	self.sender = [[UILabel alloc] init];
	self.sender.font = [UIFont boldSystemFontOfSize:12];
	self.sender.backgroundColor = [UIColor clearColor];
	self.sender.hidden = YES;
	[self.contentView addSubview:self.sender];

	self.disc = [[UIImageView alloc] init];
	self.disc.hidden = YES;
	[self.bubble addSubview:self.disc];

	self.wave = [[UIImageView alloc] init];
	self.wave.hidden = YES;
	[self.bubble addSubview:self.wave];

	self.tail = [[UIImageView alloc] init];
	self.tail.hidden = YES;
	[self.contentView addSubview:self.tail];

	self.senderAvatar = [[UIImageView alloc] init];
	self.senderAvatar.layer.cornerRadius = kAvatarSide * 0.12f;
	self.senderAvatar.clipsToBounds = YES;
	self.senderAvatar.hidden = YES;
	[self.contentView addSubview:self.senderAvatar];

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

	self.forwardLabel = [[UILabel alloc] init];
	self.forwardLabel.font = [UIFont systemFontOfSize:12];
	self.forwardLabel.backgroundColor = [UIColor clearColor];
	self.forwardLabel.hidden = YES;
	[self.bubble addSubview:self.forwardLabel];

	// A stamp on a picture cannot be grey on nothing - it needs its own plate,
	// which is what their mediaDateAndStatusBg is.
	self.mediaStamp = [[UILabel alloc] init];
	self.mediaStamp.font = [UIFont systemFontOfSize:11];
	self.mediaStamp.textColor = [UIColor whiteColor];
	self.mediaStamp.textAlignment = NSTextAlignmentCenter;
	self.mediaStamp.layer.cornerRadius = 8;
	self.mediaStamp.clipsToBounds = YES;
	self.mediaStamp.hidden = YES;
	[self.bubble addSubview:self.mediaStamp];

	self.time = [[UILabel alloc] init];
	self.time.font = [UIFont systemFontOfSize:11];
	self.time.backgroundColor = [UIColor clearColor];
	self.time.textAlignment = NSTextAlignmentRight;
	[self.bubble addSubview:self.time];

	return self;
}

@end

#pragma mark - controller

@interface TGChatViewController () <UISearchBarDelegate, CLLocationManagerDelegate,
		UIScrollViewDelegate, AVAudioPlayerDelegate,
		ABPeoplePickerNavigationControllerDelegate>
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
@property (nonatomic, strong) UIButton *micButton;
@property (nonatomic, strong) UISearchBar *chatSearchBar;
@property (nonatomic, strong) NSArray *messagesBeforeSearch;
@property (nonatomic, strong) NSTimer *recordTimer;
@property (nonatomic, strong) UIView *recordPanel;      // shown while holding
@property (nonatomic, strong) UILabel *recordClock;
@property (nonatomic, strong) UIView *recordDot;
@property (nonatomic, assign) int64_t playingMessageId;
@property (nonatomic, strong) NSTimer *playbackTimer;
@property (nonatomic, strong) MPMoviePlayerController *videoNotePlayer;
@property (nonatomic, strong) UIView *playerBar;        // the strip under the header
@property (nonatomic, strong) UIView *playerProgress;   // its line
@property (nonatomic, strong) UIButton *playerToggle;
@property (nonatomic, strong) UILabel *playerLabel;
@property (nonatomic, strong) NSMutableDictionary *senderAvatars;   // userId -> UIImage
@property (nonatomic, strong) NSMutableSet *senderAvatarsRequested;
@property (nonatomic, strong) UILabel *downloadHUD;
@property (nonatomic, assign) NSInteger downloadingFileId;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) UIImage *fullScreenImage;
@property (nonatomic, strong) UIImageView *wallpaperView;
@property (nonatomic, strong) UIButton *stickerButton;
@property (nonatomic, strong) UIScrollView *stickerPanel;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIButton *scrollDownButton;
@property (nonatomic, strong) NSDate *lastTypingSent;
@property (nonatomic, assign) BOOL postingBlocked;

- (void)clearComposeState;
- (void)showComposeBanner:(NSString *)text;
- (void)installMessageHandler;
- (void)updateEmptyState;
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
	self.senderAvatars = [NSMutableDictionary dictionary];
	self.senderAvatarsRequested = [NSMutableSet set];
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
	// The wallpaper goes behind the table, which is transparent over it.
	self.wallpaperView = [[UIImageView alloc] initWithFrame:self.view.bounds];
	self.wallpaperView.contentMode = UIViewContentModeScaleAspectFill;
	self.wallpaperView.clipsToBounds = YES;
	self.wallpaperView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
										  UIViewAutoresizingFlexibleHeight;
	if ([TGCapabilities canShowWallpaper])
		self.wallpaperView.image = [[TGTheme shared] wallpaper];
	[self.view addSubview:self.wallpaperView];

	// Hold a message for the things a chat needs and a tap cannot carry.
	[self.table addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(messageHeld:)]];

	[self.view addSubview:self.table];

	[self buildInputBar:b];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
			name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
			name:UIKeyboardWillHideNotification object:nil];

	[self installMessageHandler];

	[self reload];
}

/// Another screen pushed on top of this one - the forward picker, a profile -
/// may install a handler of its own on the shared client. Coming back has to
/// take it over again or the chat stops updating live.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self installMessageHandler];
}

- (void)installMessageHandler {
	__weak typeof(self) weakSelf = self;
	[TGClient shared].onMessage = ^(int64_t chatId, NSDictionary *message, int64_t deletedId){
		TGChatViewController *me = weakSelf;
		if (!me || chatId != me.chatId)
			return;

		// While a search is on screen the table is showing results, not the
		// conversation; appending to it would corrupt what gets restored.
		if (me.chatSearchBar){
			if (!message)
				return;
			NSMutableArray *behind = [(me.messagesBeforeSearch ?: @[]) mutableCopy];
			[behind addObject:message];
			me.messagesBeforeSearch = behind;
			return;
		}

		if (message){
			NSNumber *newId = [message[@"id"] isKindOfClass:NSNumber.class] ? message[@"id"] : nil;
			// TDLib echoes a message it has already delivered when the sending
			// state settles; the same row twice is worse than a late refresh.
			if (newId){
				for (NSDictionary *existing in me.messages){
					if ([existing[@"id"] isEqual:newId]){
						[me reload];
						return;
					}
				}
			}
			NSMutableArray *next = [me.messages mutableCopy];
			[next addObject:message];
			me.messages = next;
			[me.table reloadData];
			[me updateEmptyState];
			[me scrollToBottomAnimated:YES];
			[me fetchMissingImages];
			[me fetchMissingQuotes];
			if (newId)
				[[TGClient shared] markRead:@[newId] inChat:chatId];
			return;
		}
		// deleted or edited - cheapest correct answer is to re-read
		[me reload];
	};
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

	header.userInteractionEnabled = YES;
	[header addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(openProfile)]];
	self.navigationItem.titleView = header;
	[self buildAvatarButton];

	// "typing..." takes the subtitle over while it lasts, then hands it back.
	__weak typeof(self) weakSelf = self;
	__block NSString *restingSubtitle = @"";
	[TGClient shared].onChatAction = ^(int64_t chatId, NSString *action){
		if (chatId != weakSelf.chatId)
			return;
		subtitle.text = action ?: restingSubtitle;
	};

	// An imported theme can arrive while a chat is open - repaint rather than
	// wait for the screen to be pushed again.
	__weak typeof(self) weakChat = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[TGIcons flush];
		TGChatViewController *me = weakChat;
		me.view.backgroundColor = [[TGTheme shared] chatBackgroundColour];
		me.table.backgroundColor = [UIColor clearColor];
		me.inputBar.backgroundColor = [[TGTheme shared] inputBarColour];
		me.input.textColor = [[TGTheme shared] primaryTextColour];
		me.wallpaperView.image = [[TGTheme shared] wallpaper];
		[[TGTheme shared] styleNavigationBar:me.navigationController.navigationBar];
		[me.table reloadData];
	}];

	[self loadPinnedMessage];
	[self applyPostingRights];

	// Saved Messages is a chat with yourself only in TDLib's bookkeeping; your
	// own presence under your own notes is meaningless.
	if (self.chatId == [[TGClient shared] savedMessagesChatId]){
		subtitle.hidden = YES;
		return;
	}

	if (!self.isGroup){
		// A private chat shows presence where a group shows its size.
		[[TGClient shared] statusForUser:self.chatId completion:^(NSString *status){
			if (!status.length)
				return;
			restingSubtitle = status;
			if (!subtitle.text.length)
				subtitle.text = status;
		}];
		return;
	}

	[[TGClient shared] memberCountForChat:self.chatId completion:^(NSInteger count){
		if (count > 0){
			restingSubtitle = [NSString stringWithFormat:@"%ld members", (long)count];
			subtitle.text = restingSubtitle;
		}
	}];
}

- (void)buildInputBar:(CGRect)b {
	self.inputBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, b.size.height - kInputHeight, b.size.width, kInputHeight)];
	self.inputBar.backgroundColor = [[TGTheme shared] inputBarColour];
	self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	self.inputBar.clipsToBounds = NO;

	// Their panel is three pieces of artwork: a tiled strip, a shadow that sits
	// above it, and the field frame stretched across the whole width. There is
	// no hairline and no drawn box anywhere in it.
	UIImage *strip = [UIImage imageNamed:@"ConversationInputPanel_Background"];
	if (strip){
		UIImageView *stripView = [[UIImageView alloc] initWithFrame:
				CGRectMake(0, 0, b.size.width, kInputHeight)];
		stripView.image = [strip stretchableImageWithLeftCapWidth:0 topCapHeight:0];
		stripView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
									 UIViewAutoresizingFlexibleHeight;
		[self.inputBar addSubview:stripView];
	}

	UIImage *shadow = [UIImage imageNamed:@"ChatInputContainer_Shadow"];
	if (shadow){
		UIImageView *shadowView = [[UIImageView alloc] initWithFrame:
				CGRectMake(0, -shadow.size.height, b.size.width, shadow.size.height)];
		shadowView.image = [shadow stretchableImageWithLeftCapWidth:0 topCapHeight:0];
		shadowView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
									  UIViewAutoresizingFlexibleBottomMargin;
		shadowView.userInteractionEnabled = NO;
		[self.inputBar addSubview:shadowView];
	} else {
		UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 1)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.inputBar addSubview:hair];
	}

	// The field frame is drawn on top of a white plate; the caret sits inside it.
	UIImage *fieldArt = [UIImage imageNamed:@"ConversationInputPanel"];
	if (fieldArt){
		UIView *plate = [[UIView alloc] initWithFrame:
				CGRectMake(40, 4, b.size.width - 106, 36)];
		plate.backgroundColor = [UIColor whiteColor];
		plate.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.inputBar addSubview:plate];

		UIImageView *frameView = [[UIImageView alloc] initWithFrame:
				CGRectMake(0, 0, b.size.width, kInputHeight)];
		frameView.image = [fieldArt stretchableImageWithLeftCapWidth:55 topCapHeight:21];
		frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
									 UIViewAutoresizingFlexibleHeight;
		frameView.userInteractionEnabled = NO;
		[self.inputBar addSubview:frameView];
	}

	CGFloat sendY = 7;

	UIButton *attach = [UIButton buttonWithType:UIButtonTypeCustom];
	attach.frame = CGRectMake(6, 7, 29, 30);
	UIImage *attachImage = [UIImage imageNamed:@"AttachBtn"];
	if (attachImage){
		[attach setImage:attachImage forState:UIControlStateNormal];
		[attach setImage:[UIImage imageNamed:@"AttachBtn_Pressed"] forState:UIControlStateHighlighted];
		attach.adjustsImageWhenHighlighted = NO;
	} else {
		[attach setImage:[TGIcons attach] forState:UIControlStateNormal];
		[attach tg_setTintColor:[[TGTheme shared] accentColour]];
	}
	[attach addTarget:self action:@selector(attachTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:attach];

	// Their placeholder starts at 49 and the field runs to 113 from the right;
	// the sticker button takes 30 of that off the end.
	self.input = [[UITextField alloc] initWithFrame:
			CGRectMake(49, 5, b.size.width - 113 - 30, 34)];
	self.input.borderStyle = UITextBorderStyleNone;
	self.input.background = nil;
	self.input.backgroundColor = [UIColor clearColor];
	self.input.placeholder = @"Message";
	self.input.textColor = [[TGTheme shared] primaryTextColour];
	self.input.font = [UIFont systemFontOfSize:16];
	self.input.returnKeyType = UIReturnKeySend;
	self.input.keyboardAppearance = [TGTheme shared].isDark
			? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
	self.input.delegate = self;
	self.input.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	if ([self.input respondsToSelector:@selector(setAttributedPlaceholder:)]){
		self.input.attributedPlaceholder = [[NSAttributedString alloc]
				initWithString:@"Message"
					attributes:@{NSForegroundColorAttributeName :
							[UIColor colorWithRed:0.616f green:0.655f blue:0.702f alpha:1.0f]}];
	}
	[self.inputBar addSubview:self.input];

	// Their send button: 62x29 of SendButton.png stretched from its middle, the
	// word in bold 14.5 with a one-point shadow above it.
	CGFloat sendWidth = 62;
	self.sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.sendButton.frame = CGRectMake(b.size.width - sendWidth - 5, sendY,
									   sendWidth, 29);
	UIImage *sendImage = [UIImage imageNamed:@"SendButton"];
	if (sendImage){
		[self.sendButton setBackgroundImage:
				[sendImage stretchableImageWithLeftCapWidth:(int)(sendImage.size.width / 2)
											   topCapHeight:0]
									forState:UIControlStateNormal];
		UIImage *sendPressed = [UIImage imageNamed:@"SendButton_Pressed"];
		if (sendPressed)
			[self.sendButton setBackgroundImage:
					[sendPressed stretchableImageWithLeftCapWidth:(int)(sendPressed.size.width / 2)
													topCapHeight:0]
										forState:UIControlStateHighlighted];
	} else {
		self.sendButton.backgroundColor = [[TGTheme shared] accentColour];
		self.sendButton.layer.cornerRadius = 4;
	}
	[self.sendButton setTitle:@"Send" forState:UIControlStateNormal];
	[self.sendButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[self.sendButton setTitleShadowColor:[UIColor colorWithRed:0.047f green:0.722f
														  blue:0.890f alpha:0.3f]
								forState:UIControlStateNormal];
	self.sendButton.titleLabel.font = [UIFont boldSystemFontOfSize:14.5f];
	self.sendButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
	self.sendButton.titleEdgeInsets = UIEdgeInsetsMake(1.5f, 0, 2, 0);
	self.sendButton.adjustsImageWhenHighlighted = NO;
	self.sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.sendButton addTarget:self action:@selector(sendTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:self.sendButton];

	// A sticker button beside the composer, as clients place it.
	self.stickerButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.stickerButton.frame = CGRectMake(b.size.width - 97, sendY, 30, 29);
	[self.stickerButton setImage:[TGIcons sticker] forState:UIControlStateNormal];
	[self.stickerButton tg_setTintColor:[[TGTheme shared] secondaryTextColour]];
	self.stickerButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.stickerButton addTarget:self action:@selector(toggleStickerPanel)
				 forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:self.stickerButton];

	// Hold to record, release to send - the gesture every client uses. It sits
	// where Send is and swaps with it depending on whether anything is typed.
	self.micButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.micButton.frame = self.sendButton.frame;
	[self.micButton setImage:[TGIcons microphone] forState:UIControlStateNormal];
	[self.micButton tg_setTintColor:[[TGTheme shared] secondaryTextColour]];
	self.micButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.micButton addTarget:self action:@selector(recordStart)
			 forControlEvents:UIControlEventTouchDown];
	[self.micButton addTarget:self action:@selector(recordFinish)
			 forControlEvents:UIControlEventTouchUpInside];
	[self.micButton addTarget:self action:@selector(recordCancel)
			 forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
	[self.inputBar addSubview:self.micButton];

	[self.input addTarget:self action:@selector(inputChanged)
		 forControlEvents:UIControlEventEditingChanged];
	[self inputChanged];

	[self.view addSubview:self.inputBar];
}

/// A voice note going on playing after you have left the chat is the one thing
/// nobody expects, and the timer would outlive the screen it repaints.
- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.voicePlayer)
		[self stopPlayback];
	[self stopVideoNote];
	// A pending delete must not be lost with the screen, and a menu must not
	// outlive the messages it was opened over.
	[TGSnackbar commitNow];
	[TGPopupMenu dismiss];
}

- (void)dealloc {
	[self.playbackTimer invalidate];
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
		[me updateEmptyState];
		[me scrollToBottomAnimated:NO];
		[me fetchMissingImages];
		[me resolveUnknownSenders];
		[me fetchMissingQuotes];

		// A message with no id would put NSNull, or nothing, into the array and
		// take the app down inside markRead.
		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *m in messages)
			if ([m[@"id"] isKindOfClass:NSNumber.class])
				[ids addObject:m[@"id"]];
		if (ids.count)
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
	[self updateScrollDownButton];
}

/// An empty conversation is otherwise a blank wallpaper with no explanation,
/// which reads as a screen that failed to load.
- (void)updateEmptyState {
	if (!self.emptyLabel){
		CGRect b = self.view.bounds;
		self.emptyLabel = [[UILabel alloc] initWithFrame:
				CGRectMake(20, (b.size.height - kInputHeight) / 2 - 20,
						   b.size.width - 40, 40)];
		self.emptyLabel.numberOfLines = 2;
		self.emptyLabel.textAlignment = NSTextAlignmentCenter;
		self.emptyLabel.font = [UIFont systemFontOfSize:14];
		self.emptyLabel.backgroundColor = [UIColor clearColor];
		self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
										   UIViewAutoresizingFlexibleTopMargin |
										   UIViewAutoresizingFlexibleBottomMargin;
		self.emptyLabel.userInteractionEnabled = NO;
		[self.view insertSubview:self.emptyLabel aboveSubview:self.wallpaperView];
	}
	self.emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.emptyLabel.text = self.chatSearchBar
			? @"No messages found"
			: @"No messages here yet.\nWrite something to start.";
	self.emptyLabel.hidden = (self.messages.count > 0);
}

/// Every client puts a way back to the newest message once you have scrolled
/// away from it; without one a long history is a one-way trip.
- (void)updateScrollDownButton {
	CGFloat fromBottom = self.table.contentSize.height -
			(self.table.contentOffset.y + self.table.bounds.size.height);
	BOOL wanted = (self.messages.count > 0) && (fromBottom > 220);

	if (!wanted){
		self.scrollDownButton.hidden = YES;
		return;
	}

	if (!self.scrollDownButton){
		self.scrollDownButton = [UIButton buttonWithType:UIButtonTypeCustom];
		self.scrollDownButton.frame = CGRectMake(0, 0, 34, 34);
		self.scrollDownButton.layer.cornerRadius = 17;
		self.scrollDownButton.clipsToBounds = YES;
		self.scrollDownButton.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.9f];
		self.scrollDownButton.layer.borderWidth = 1.0f;
		self.scrollDownButton.layer.borderColor =
				[[TGTheme shared] separatorColour].CGColor;
		[self.scrollDownButton setTitle:@"▼" forState:UIControlStateNormal];
		self.scrollDownButton.titleLabel.font = [UIFont systemFontOfSize:13];
		[self.scrollDownButton setTitleColor:[[TGTheme shared] accentColour]
									forState:UIControlStateNormal];
		self.scrollDownButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
												 UIViewAutoresizingFlexibleTopMargin;
		[self.scrollDownButton addTarget:self action:@selector(scrollDownTapped)
					   forControlEvents:UIControlEventTouchUpInside];
		[self.view addSubview:self.scrollDownButton];
	}
	self.scrollDownButton.hidden = NO;
	self.scrollDownButton.frame = CGRectMake(self.view.bounds.size.width - 44,
			CGRectGetMinY(self.inputBar.frame) - 44, 34, 34);
	[self.view bringSubviewToFront:self.scrollDownButton];
}

- (void)scrollDownTapped {
	[self scrollToBottomAnimated:YES];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView == self.table)
		[self updateScrollDownButton];
}

#pragma mark - sending

- (void)sendTapped {
	NSString *text = [self.input.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length)
		return;
	// A channel you only follow has no composer; a stale keyboard must not be
	// able to post into it anyway.
	if (self.postingBlocked)
		return;

	// The field has to empty on send, or the next tap sends the same line again.
	self.input.text = @"";
	if (self.stickerPanel)
		[self toggleStickerPanel];

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

/// Telegram puts the chat's picture top right, and it opens the profile.
- (void)buildAvatarButton {
	// 42dp in their header, which is 37 here and still clears a 44pt bar.
	CGFloat side = 37;
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(0, 0, side, side);
	button.layer.cornerRadius = side / 2;
	button.clipsToBounds = YES;
	[button addTarget:self action:@selector(openProfile)
	 forControlEvents:UIControlEventTouchUpInside];

	NSString *title = self.chatTitle ?: @"";
	BOOL isSaved = (self.chatId == [[TGClient shared] savedMessagesChatId]);
	[button setImage:(isSaved
			? [TGIcons savedMessagesAvatarOfSide:side]
			: [TGIcons avatarWithInitials:
					(title.length ? [title substringToIndex:1].uppercaseString : @"?")
									 size:side colourId:self.chatId])
			forState:UIControlStateNormal];

	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:button];

	// Your own photo is not what Saved Messages is known by; the bookmark set
	// above stays.
	if (isSaved)
		return;

	NSNumber *fileId = [[TGClient shared] photoFileIdForChat:self.chatId];
	if (!fileId)
		return;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		UIImage *photo = path ? [UIImage imageWithContentsOfFile:path] : nil;
		if (photo) [button setImage:photo forState:UIControlStateNormal];
	}];
}

- (void)openProfile {
	// A private chat id is the user id, which is what the profile needs to
	// look up a photo and a phone number; a group has no single user.
	int64_t userId = self.isGroup ? 0 : self.chatId;
	TGProfileViewController *profile = [[TGProfileViewController alloc]
			initWithChatId:self.chatId userId:userId title:self.chatTitle];
	__weak typeof(self) weakSelf = self;
	profile.onSearchTapped = ^{
		[weakSelf.navigationController popViewControllerAnimated:YES];
		[weakSelf toggleChatSearch];
	};
	[self.navigationController pushViewController:profile animated:YES];
}

/// A channel you only follow has no composer; it gets a mute switch instead,
/// which is what the bottom of a channel offers in every client.
- (void)applyPostingRights {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] canSendInChat:self.chatId completion:^(BOOL canSend, BOOL isChannel){
		TGChatViewController *me = weakSelf;
		if (!me || canSend)
			return;
		// The answer can arrive before the composer has been built, and it can
		// arrive twice; either way there must be exactly one bar at the bottom.
		if (me.postingBlocked)
			return;
		me.postingBlocked = YES;

		me.inputBar.hidden = YES;
		[me.input resignFirstResponder];

		CGRect b = me.view.bounds;
		UIButton *mute = [UIButton buttonWithType:UIButtonTypeCustom];
		mute.frame = CGRectMake(0, b.size.height - kInputHeight,
								b.size.width, kInputHeight);
		mute.backgroundColor = [[TGTheme shared] inputBarColour];
		mute.autoresizingMask = UIViewAutoresizingFlexibleWidth |
								UIViewAutoresizingFlexibleTopMargin;
		[mute setTitleColor:[[TGTheme shared] accentColour] forState:UIControlStateNormal];
		mute.titleLabel.font = [UIFont systemFontOfSize:15];
		[mute setTitle:(isChannel ? @"Mute channel" : @"Mute chat")
			  forState:UIControlStateNormal];
		[mute addTarget:me action:@selector(muteFromChat:)
	   forControlEvents:UIControlEventTouchUpInside];
		[me.view addSubview:mute];
		(void)b;
	}];
}

- (void)muteFromChat:(UIButton *)button {
	BOOL muting = [button.currentTitle hasPrefix:@"Mute"];
	[[TGClient shared] setChat:self.chatId muted:muting];
	[button setTitle:(muting ? @"Unmute" : @"Mute channel") forState:UIControlStateNormal];
}

/// YES when this message continues the album the one before it started.
- (BOOL)continuesAlbumAtRow:(NSInteger)row {
	NSString *album = self.messages[row][@"albumId"];
	if (!album.length || [album isEqualToString:@"0"] || row == 0)
		return NO;
	return [self.messages[row - 1][@"albumId"] isEqualToString:album];
}

/// YES when the next message belongs to the same album, so this one should not
/// carry the timestamp - only the last of a block does.
- (BOOL)albumContinuesAfterRow:(NSInteger)row {
	NSString *album = self.messages[row][@"albumId"];
	if (!album.length || [album isEqualToString:@"0"] ||
		row + 1 >= (NSInteger)self.messages.count)
		return NO;
	return [self.messages[row + 1][@"albumId"] isEqualToString:album];
}

/// Copy the received file into Documents first: TDLib owns its cache and can
/// delete it, and a theme has to survive the next launch.
- (void)applyThemeFromMessage:(NSDictionary *)m {
	NSNumber *docId = m[@"docId"];
	if (![docId isKindOfClass:NSNumber.class])
		return;

	NSString *name = m[@"docName"] ?: @"theme.tgios-theme";
	[self beginDownloadHUDForFile:[docId integerValue]];
	[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
		[self endDownloadHUD];
		if (!path)
			return;

		NSString *documents = [NSSearchPathForDirectoriesInDomains(
				NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
		NSString *saved = [documents stringByAppendingPathComponent:name];
		[[NSFileManager defaultManager] removeItemAtPath:saved error:nil];
		[[NSFileManager defaultManager] copyItemAtPath:path toPath:saved error:nil];

		BOOL applied = [[TGTheme shared] importThemeAtPath:saved];
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Theme"
				message:(applied ? [NSString stringWithFormat:@"%@ applied.",
						[TGTheme shared].importedName ?: name]
								 : @"This file could not be read as a Telegram theme.")
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}];
}

/// Scroll to a message already loaded, and flash it so the eye finds it.
/// NO when the message is not in the loaded window.
- (BOOL)scrollToMessageId:(int64_t)messageId {
	for (NSInteger row = 0; row < (NSInteger)self.messages.count; row++){
		if ([self.messages[row][@"id"] longLongValue] != messageId)
			continue;

		NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
		[self.table scrollToRowAtIndexPath:path
						  atScrollPosition:UITableViewScrollPositionMiddle
								  animated:YES];
		UITableViewCell *cell = [self.table cellForRowAtIndexPath:path];
		cell.contentView.alpha = 0.3f;
		[UIView animateWithDuration:0.6 animations:^{ cell.contentView.alpha = 1.0f; }];
		return YES;
	}
	return NO;
}

/// The option that was tapped votes for itself. Which poll it belongs to comes
/// from the cell it sits in, because a button knows nothing about messages.
- (void)pollOptionTapped:(UIButton *)option {
	UIView *view = option;
	while (view && ![view isKindOfClass:TGBubbleCell.class])
		view = view.superview;
	TGBubbleCell *cell = (TGBubbleCell *)view;
	if (!cell || !cell.pollMessageId)
		return;

	NSInteger index = option.tag - 0x9100;
	[[TGClient shared] votePoll:cell.pollMessageId
						 inChat:self.chatId
						options:@[@(index)]];

	// TDLib answers with an updated message; re-read so the shares move.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [self reload]; });
}

#pragma mark - download progress

/// A video or a document is megabytes over a 4S connection; without this the
/// tap looks like it did nothing.
- (void)beginDownloadHUDForFile:(NSInteger)fileId {
	self.downloadingFileId = fileId;

	if (!self.downloadHUD){
		self.downloadHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 110, 40)];
		self.downloadHUD.center = CGPointMake(self.view.bounds.size.width / 2,
											  self.view.bounds.size.height / 2);
		self.downloadHUD.textAlignment = NSTextAlignmentCenter;
		self.downloadHUD.font = [UIFont boldSystemFontOfSize:15];
		self.downloadHUD.textColor = [UIColor whiteColor];
		self.downloadHUD.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7f];
		self.downloadHUD.layer.cornerRadius = 8;
		self.downloadHUD.clipsToBounds = YES;
	}
	self.downloadHUD.text = @"0%";
	self.downloadHUD.hidden = NO;
	[self.view addSubview:self.downloadHUD];

	__weak typeof(self) weakSelf = self;
	[TGClient shared].onFileProgress = ^(NSInteger updatedId, float progress){
		TGChatViewController *me = weakSelf;
		if (!me || updatedId != me.downloadingFileId)
			return;
		me.downloadHUD.text = [NSString stringWithFormat:@"%d%%", (int)(progress * 100)];
	};
}

- (void)endDownloadHUD {
	self.downloadingFileId = 0;
	self.downloadHUD.hidden = YES;
	[self.downloadHUD removeFromSuperview];
}

#pragma mark - pinned message

/// A strip under the navigation bar, the way clients surface what is pinned.
- (void)loadPinnedMessage {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] pinnedMessageForChat:self.chatId completion:^(NSDictionary *m){
		NSString *text = m[@"text"];
		if (!text.length)
			return;
		[weakSelf showPinnedBanner:text];
	}];
}

- (void)showPinnedBanner:(NSString *)text {
	CGRect b = self.view.bounds;
	UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 34)];
	banner.backgroundColor = [UIColor colorWithWhite:0.97f alpha:0.97f];
	banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;

	UIView *stripe = [[UIView alloc] initWithFrame:CGRectMake(8, 5, 2, 24)];
	stripe.backgroundColor = [[TGTheme shared] accentColour];
	[banner addSubview:stripe];

	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 2, b.size.width - 24, 14)];
	label.text = @"Pinned message";
	label.font = [UIFont boldSystemFontOfSize:11];
	label.textColor = [[TGTheme shared] accentColour];
	label.backgroundColor = [UIColor clearColor];
	[banner addSubview:label];

	UILabel *body = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, b.size.width - 24, 16)];
	body.text = text;
	body.font = [UIFont systemFontOfSize:13];
	body.textColor = [[TGTheme shared] primaryTextColour];
	body.backgroundColor = [UIColor clearColor];
	body.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[banner addSubview:body];

	UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 33, b.size.width, 1)];
	hair.backgroundColor = [UIColor colorWithWhite:0.8f alpha:1];
	hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[banner addSubview:hair];

	[self.view addSubview:banner];

	// Push the message list down so the banner does not cover the first row.
	UIEdgeInsets insets = self.table.contentInset;
	insets.top += 34;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
}

#pragma mark - search

/// The table already knows how to draw a list of flattened messages, so search
/// just swaps the list underneath it rather than building a second screen.
- (void)toggleChatSearch {
	if (self.chatSearchBar){
		[self endChatSearch];
		return;
	}

	CGRect b = self.view.bounds;
	self.chatSearchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 44)];
	self.chatSearchBar.delegate = self;
	self.chatSearchBar.placeholder = @"Search in chat";
	self.chatSearchBar.showsCancelButton = YES;
	self.chatSearchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:self.chatSearchBar];
	[self.chatSearchBar becomeFirstResponder];

	self.messagesBeforeSearch = self.messages;
}

- (void)endChatSearch {
	[self.chatSearchBar resignFirstResponder];
	[self.chatSearchBar removeFromSuperview];
	self.chatSearchBar = nil;

	if (self.messagesBeforeSearch){
		self.messages = self.messagesBeforeSearch;
		self.messagesBeforeSearch = nil;
		[self.table reloadData];
		[self scrollToBottomAnimated:NO];
	}
	[self updateEmptyState];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	[self endChatSearch];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
	if (!query.length){
		self.messages = self.messagesBeforeSearch ?: @[];
		[self.table reloadData];
		[self updateEmptyState];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchInChat:self.chatId query:query completion:^(NSArray *found){
		TGChatViewController *me = weakSelf;
		if (!me || ![me.chatSearchBar.text isEqualToString:query])
			return;   // a stale answer must not replace a newer query
		// searchChatMessages answers newest first; the table reads oldest first.
		me.messages = [[found reverseObjectEnumerator] allObjects];
		[me.table reloadData];
		[me updateEmptyState];
	}];
}

/// Cached initials until the real photo arrives; drawing it every row would
/// re-download and re-decode on every scroll.
- (UIImage *)avatarForUser:(int64_t)userId name:(NSString *)name {
	NSNumber *key = @(userId);
	UIImage *cached = self.senderAvatars[key];
	if (cached)
		return cached;

	NSString *initials = name.length ? [name substringToIndex:1] : @"?";
	UIImage *placeholder = [TGIcons avatarWithInitials:initials.uppercaseString
												  size:kAvatarSide
											  colourId:userId];
	self.senderAvatars[key] = placeholder;

	if ([self.senderAvatarsRequested containsObject:key])
		return placeholder;
	[self.senderAvatarsRequested addObject:key];

	__weak typeof(self) weakSelf = self;
	void (^fetch)(NSNumber *) = ^(NSNumber *fileId){
		if (!fileId)
			return;
		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			UIImage *photo = path ? [UIImage imageWithContentsOfFile:path] : nil;
			if (!photo) return;
			weakSelf.senderAvatars[key] = photo;
			[weakSelf.table reloadData];
		}];
	};

	NSNumber *cachedFile = [[TGClient shared] photoFileIdForUserId:userId];
	if (cachedFile){
		fetch(cachedFile);
		return placeholder;
	}

	// TDLib only volunteers updateUser for people it has reason to send; the
	// rest of a group's members have to be asked for.
	[[TGClient shared] userInfo:userId completion:^(NSDictionary *user){
		fetch(user[@"profile_photo"][@"small"][@"id"]);
	}];
	return placeholder;
}

#pragma mark - compose banner

/// Back to composing a plain message: no reply, no edit, no banner. Also
/// missing, and reached from the recorder and from the banner's own cancel.
- (void)clearComposeState {
	// Cancelling an edit has to take the text it prefilled with it, otherwise
	// the draft of a message already sent is left sitting in the composer.
	if (self.editingId != 0)
		self.input.text = @"";
	self.replyToId = 0;
	self.editingId = 0;
	self.composeBanner.hidden = YES;
	[self inputChanged];
}

/// A strip above the composer saying what the next message will be: a reply,
/// an edit, or a recording in progress. Declared and used from three places
/// but never written, so holding the microphone brought the app down.
- (void)showComposeBanner:(NSString *)text {
	if (!self.composeBanner){
		CGRect b = self.view.bounds;
		self.composeBanner = [[UIView alloc] initWithFrame:
				CGRectMake(0, CGRectGetMinY(self.inputBar.frame) - 28, b.size.width, 28)];
		self.composeBanner.backgroundColor = [[TGTheme shared] inputBarColour];
		self.composeBanner.autoresizingMask = UIViewAutoresizingFlexibleWidth |
											  UIViewAutoresizingFlexibleTopMargin;

		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(10, 4, b.size.width - 50, 20)];
		label.font = [UIFont systemFontOfSize:13];
		label.textColor = [[TGTheme shared] accentColour];
		label.backgroundColor = [UIColor clearColor];
		label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.composeBanner addSubview:label];

		UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
		cancel.frame = CGRectMake(b.size.width - 40, 0, 40, 28);
		cancel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[cancel setTitle:@"\u00d7" forState:UIControlStateNormal];
		[cancel setTitleColor:[[TGTheme shared] secondaryTextColour]
					 forState:UIControlStateNormal];
		cancel.titleLabel.font = [UIFont systemFontOfSize:22];
		[cancel addTarget:self action:@selector(clearComposeState)
		 forControlEvents:UIControlEventTouchUpInside];
		[self.composeBanner addSubview:cancel];

		[self.view addSubview:self.composeBanner];
	}

	UILabel *label = (UILabel *)[self.composeBanner.subviews firstObject];
	if ([label isKindOfClass:UILabel.class])
		label.text = text;
	self.composeBanner.hidden = NO;
}

#pragma mark - stickers

/// A strip of the stickers used lately. A full sticker-set browser is a screen
/// of its own; the recents are what a chat reaches for.
- (void)toggleStickerPanel {
	if (self.stickerPanel){
		[self.stickerPanel removeFromSuperview];
		self.stickerPanel = nil;
		return;
	}

	CGRect b = self.view.bounds;
	CGFloat height = 96;
	UIScrollView *panel = [[UIScrollView alloc] initWithFrame:
			CGRectMake(0, CGRectGetMinY(self.inputBar.frame) - height, b.size.width, height)];
	panel.backgroundColor = [[TGTheme shared] inputBarColour];
	panel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
							 UIViewAutoresizingFlexibleTopMargin;
	[self.view addSubview:panel];
	self.stickerPanel = panel;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] recentStickersWithCompletion:^(NSArray *stickers){
		TGChatViewController *me = weakSelf;
		if (!me || me.stickerPanel != panel)
			return;
		[me fillStickerPanel:panel with:stickers];
	}];
}

- (void)fillStickerPanel:(UIScrollView *)panel with:(NSArray *)stickers {
	CGFloat side = 72, gap = 6, x = gap;
	for (NSDictionary *sticker in stickers){
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = CGRectMake(x, 12, side, side);
		button.tag = [sticker[@"fileId"] integerValue];
		[button addTarget:self action:@selector(stickerTapped:)
		 forControlEvents:UIControlEventTouchUpInside];
		// Until the picture is decoded the emoji stands in, so the strip is
		// usable immediately rather than a row of blanks.
		[button setTitle:sticker[@"emoji"] forState:UIControlStateNormal];
		button.titleLabel.font = [UIFont systemFontOfSize:34];
		[panel addSubview:button];
		x += side + gap;

		if ([sticker[@"isAnimated"] boolValue])
			continue;
		[[TGClient shared] downloadFile:[sticker[@"fileId"] integerValue]
							 completion:^(NSString *path){
			UIImage *image = path ? [UIImage convertFromWebP:path
											  compressedData:nil error:nil] : nil;
			if (!image)
				return;
			[button setTitle:@"" forState:UIControlStateNormal];
			[button setImage:image forState:UIControlStateNormal];
			button.imageView.contentMode = UIViewContentModeScaleAspectFit;
		}];
	}
	panel.contentSize = CGSizeMake(x, panel.bounds.size.height);
}

- (void)stickerTapped:(UIButton *)button {
	[[TGClient shared] sendStickerWithFileId:button.tag
									  toChat:self.chatId
									  thread:self.threadId];
	[self toggleStickerPanel];
}

#pragma mark - voice

/// Send is for typed text, the microphone for everything else - showing both
/// at once would leave one of them dead.
- (void)inputChanged {
	BOOL hasText = self.input.text.length > 0;
	self.sendButton.hidden = !hasText;
	self.micButton.hidden = hasText;
	if (hasText)
		[self sendTypingAction];
}

/// The other side sees "typing..." only if we say so. TDLib expects the action
/// to be repeated while it lasts; it lapses on its own after a few seconds, so
/// one call every four is enough and does not flood a 4S connection.
- (void)sendTypingAction {
	if (self.postingBlocked || self.editingId != 0)
		return;
	NSDate *now = [NSDate date];
	if (self.lastTypingSent &&
		[now timeIntervalSinceDate:self.lastTypingSent] < 4.0)
		return;
	self.lastTypingSent = now;

	NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:@{
			@"@type" : @"sendChatAction",
			@"chat_id" : @(self.chatId),
			@"action" : @{@"@type" : @"chatActionTyping"}}];
	if (self.threadId)
		request[@"message_thread_id"] = @(self.threadId);
	[[TGClient shared] send:request];
}

/// Their recording panel: a red dot, the running time, "Slide to cancel", and
/// the microphone grown into a disc with a halo around it. It takes over the
/// composer for as long as the finger is down.
- (void)showRecordPanel {
	CGRect bar = self.inputBar.frame;
	if (!self.recordPanel){
		self.recordPanel = [[UIView alloc] initWithFrame:bar];
		self.recordPanel.backgroundColor = [[TGTheme shared] listBackgroundColour];
		self.recordPanel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
											UIViewAutoresizingFlexibleTopMargin;

		UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, bar.size.width, 1)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.recordPanel addSubview:hair];

		// 10dp in their panel, and it blinks the way a recorder's does.
		self.recordDot = [[UIView alloc] initWithFrame:
				CGRectMake(14, (kInputHeight - 9) / 2, 9, 9)];
		self.recordDot.backgroundColor = [UIColor colorWithRed:0.878f green:0.329f
														 blue:0.341f alpha:1.0f];
		self.recordDot.layer.cornerRadius = 4.5f;
		[self.recordPanel addSubview:self.recordDot];

		self.recordClock = [[UILabel alloc] initWithFrame:
				CGRectMake(32, (kInputHeight - 20) / 2, 62, 20)];
		self.recordClock.font = [UIFont systemFontOfSize:16];
		self.recordClock.textColor = [UIColor colorWithRed:0.557f green:0.584f
													  blue:0.608f alpha:1.0f];
		self.recordClock.backgroundColor = [UIColor clearColor];
		[self.recordPanel addSubview:self.recordClock];

		UILabel *cancel = [[UILabel alloc] initWithFrame:
				CGRectMake(100, (kInputHeight - 20) / 2, bar.size.width - 180, 20)];
		cancel.text = @"‹ Slide to cancel";
		cancel.font = [UIFont systemFontOfSize:15];
		cancel.textColor = [UIColor colorWithRed:0.565f green:0.592f
											blue:0.616f alpha:1.0f];
		cancel.backgroundColor = [UIColor clearColor];
		cancel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.recordPanel addSubview:cancel];

		// 89dp with the button itself at 63 inside it; scaled to fit the strip.
		CGFloat halo = kInputHeight + 12, disc = 44;
		UIView *ring = [[UIView alloc] initWithFrame:
				CGRectMake(bar.size.width - halo + 4, (kInputHeight - halo) / 2, halo, halo)];
		ring.backgroundColor = [[TGTheme shared] accentColour];
		ring.alpha = 0.25f;
		ring.layer.cornerRadius = halo / 2;
		ring.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.recordPanel addSubview:ring];

		UIImageView *button = [[UIImageView alloc] initWithFrame:CGRectMake(
				CGRectGetMidX(ring.frame) - disc / 2, (kInputHeight - disc) / 2, disc, disc)];
		button.backgroundColor = [UIColor colorWithRed:0.369f green:0.655f
												  blue:0.871f alpha:1.0f];   // #5EA7DE
		button.layer.cornerRadius = disc / 2;
		button.image = [TGIcons microphoneOfSide:disc colour:[UIColor whiteColor]];
		button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.recordPanel addSubview:button];
	}

	self.recordPanel.frame = bar;
	self.recordClock.text = @"0:00,0";
	self.recordDot.alpha = 1.0f;
	[self.view addSubview:self.recordPanel];
}

- (void)hideRecordPanel {
	[self.recordPanel removeFromSuperview];
}

- (void)recordStart {
	if (![[TGVoiceRecorder shared] start]){
		[self showPlaybackFailure];
		return;
	}
	[self showRecordPanel];
	self.recordTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
													   target:self
													 selector:@selector(recordTick)
													 userInfo:nil
													  repeats:YES];
}

- (void)recordTick {
	NSTimeInterval d = [TGVoiceRecorder shared].duration;
	// Their panel shows tenths, which is what makes it read as running.
	self.recordClock.text = [NSString stringWithFormat:@"%ld:%02ld,%ld",
			(long)(d / 60), (long)((NSInteger)d % 60), (long)((NSInteger)(d * 10) % 10)];
	self.recordDot.alpha = (self.recordDot.alpha < 1.0f) ? 1.0f : 0.25f;
}

- (void)recordFinish {
	[self.recordTimer invalidate];
	self.recordTimer = nil;
	[self hideRecordPanel];

	__weak typeof(self) weakSelf = self;
	[[TGVoiceRecorder shared] stopWithCompletion:^(NSString *path, NSTimeInterval seconds){
		TGChatViewController *me = weakSelf;
		[me clearComposeState];
		if (!me || !path || seconds < 0.5)
			return;   // a stray tap is not a voice message
		[[TGClient shared] sendVoiceAtPath:path
								  duration:(NSInteger)seconds
									toChat:me.chatId
									thread:me.threadId];
	}];
}

- (void)recordCancel {
	[self.recordTimer invalidate];
	self.recordTimer = nil;
	[self hideRecordPanel];
	[[TGVoiceRecorder shared] cancel];
	[self clearComposeState];
}

#pragma mark - video notes

/// Plays a round note over the circle it belongs to, clipped to the same shape.
/// MPMoviePlayerController is the only decoder iOS 7 offers, but it does not
/// have to own the screen: its view goes in a mask of our own.
- (void)playVideoNoteAtPath:(NSString *)path row:(NSInteger)row {
	[self stopVideoNote];

	CGRect rect = [self.table rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	CGRect inView = [self.table convertRect:rect toView:self.view];
	// The circle is the row minus the strip its timestamp sits in.
	CGFloat side = MIN(inView.size.height - 20, inView.size.width);
	NSDictionary *m = self.messages[row];
	CGFloat x = [m[@"outgoing"] boolValue]
			? CGRectGetMaxX(inView) - side - 8 : 8;

	UIView *circle = [[UIView alloc] initWithFrame:
			CGRectMake(x, CGRectGetMinY(inView) + 3, side, side)];
	circle.layer.cornerRadius = side / 2;
	circle.clipsToBounds = YES;
	circle.backgroundColor = [UIColor blackColor];
	circle.tag = 0xF119;

	MPMoviePlayerController *player = [[MPMoviePlayerController alloc]
			initWithContentURL:[NSURL fileURLWithPath:path]];
	player.controlStyle = MPMovieControlStyleNone;
	player.scalingMode = MPMovieScalingModeAspectFill;
	player.view.frame = circle.bounds;
	player.shouldAutoplay = YES;
	[circle addSubview:player.view];
	[self.view addSubview:circle];
	self.videoNotePlayer = player;

	[circle addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(stopVideoNote)]];

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(stopVideoNote)
				name:MPMoviePlayerPlaybackDidFinishNotification
			  object:player];
	[player prepareToPlay];
	[player play];
}

- (void)stopVideoNote {
	if (!self.videoNotePlayer)
		return;
	[[NSNotificationCenter defaultCenter] removeObserver:self
			name:MPMoviePlayerPlaybackDidFinishNotification
		  object:self.videoNotePlayer];
	[self.videoNotePlayer stop];
	[[self.view viewWithTag:0xF119] removeFromSuperview];
	self.videoNotePlayer = nil;
}

#pragma mark - playback

/// Their player strip: an arrow, what is playing, a way out, and a line along
/// the bottom that fills as it goes. It sits under the header, which is where
/// a client puts it so the chat stays readable while something plays.
- (void)showPlayerBar {
	CGRect b = self.view.bounds;
	if (!self.playerBar){
		self.playerBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 36)];
		self.playerBar.backgroundColor = [[TGTheme shared] listBackgroundColour];
		self.playerBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;

		self.playerToggle = [UIButton buttonWithType:UIButtonTypeCustom];
		self.playerToggle.frame = CGRectMake(8, 4, 28, 28);
		[self.playerToggle tg_setTintColor:[[TGTheme shared] accentColour]];
		[self.playerToggle addTarget:self action:@selector(togglePlayback)
					forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:self.playerToggle];

		self.playerLabel = [[UILabel alloc] initWithFrame:
				CGRectMake(40, 8, b.size.width - 80, 20)];
		self.playerLabel.font = [UIFont systemFontOfSize:14];
		self.playerLabel.backgroundColor = [UIColor clearColor];
		self.playerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.playerBar addSubview:self.playerLabel];

		UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
		close.frame = CGRectMake(b.size.width - 38, 4, 34, 28);
		[close setTitle:@"×" forState:UIControlStateNormal];
		close.titleLabel.font = [UIFont systemFontOfSize:24];
		close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[close addTarget:self action:@selector(stopPlayback)
		forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:close];
		[close setTitleColor:[[TGTheme shared] secondaryTextColour]
					forState:UIControlStateNormal];

		UIView *track = [[UIView alloc] initWithFrame:CGRectMake(0, 34, b.size.width, 2)];
		track.backgroundColor = [[TGTheme shared] separatorColour];
		track.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.playerBar addSubview:track];

		self.playerProgress = [[UIView alloc] initWithFrame:CGRectMake(0, 34, 0, 2)];
		self.playerProgress.backgroundColor = [[TGTheme shared] accentColour];
		[self.playerBar addSubview:self.playerProgress];
	}

	self.playerLabel.textColor = [[TGTheme shared] primaryTextColour];
	self.playerLabel.text = @"Voice message";
	self.playerProgress.frame = CGRectMake(0, 34, 0, 2);
	[self.playerToggle setImage:[TGIcons pause] forState:UIControlStateNormal];
	[self.view addSubview:self.playerBar];

	// Push the messages down so the strip does not cover the newest one.
	UIEdgeInsets insets = self.table.contentInset;
	insets.top += 36;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
}

- (void)hidePlayerBar {
	if (!self.playerBar.superview)
		return;
	[self.playerBar removeFromSuperview];
	UIEdgeInsets insets = self.table.contentInset;
	insets.top -= 36;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
}

/// Five ticks a second is enough for the eye and cheap enough for a 4S: the
/// waveform is redrawn each tick, and redrawing it sixty times would not be.
- (void)startPlaybackTimer {
	[self.playbackTimer invalidate];
	self.playbackTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
														 target:self
													   selector:@selector(playbackTick)
													   userInfo:nil
														repeats:YES];
}

- (CGFloat)playedFraction {
	if (!self.voicePlayer || self.voicePlayer.duration <= 0)
		return 0;
	return (CGFloat)(self.voicePlayer.currentTime / self.voicePlayer.duration);
}

- (void)playbackTick {
	CGFloat played = [self playedFraction];
	self.playerProgress.frame = CGRectMake(0, 34,
			self.playerBar.bounds.size.width * played, 2);

	// Only the row being played changes, and reloading the whole table five
	// times a second on this hardware is visible as a stutter.
	for (UITableViewCell *cell in self.table.visibleCells){
		if (![cell isKindOfClass:TGBubbleCell.class])
			continue;
		TGBubbleCell *bubble = (TGBubbleCell *)cell;
		if (bubble.voiceMessageId != self.playingMessageId || bubble.wave.hidden)
			continue;
		bubble.wave.image = [TGIcons waveform:bubble.waveformData
										 size:bubble.wave.bounds.size
									   played:played
									   colour:[[TGTheme shared] accentColour]];
	}
}

- (void)togglePlayback {
	if (!self.voicePlayer)
		return;
	if (self.voicePlayer.playing){
		[self.voicePlayer pause];
		[self.playbackTimer invalidate];
		self.playbackTimer = nil;
		[self.playerToggle setImage:[TGIcons play] forState:UIControlStateNormal];
	} else {
		[self.voicePlayer play];
		[self startPlaybackTimer];
		[self.playerToggle setImage:[TGIcons pause] forState:UIControlStateNormal];
	}
	[self.table reloadData];
}

- (void)stopPlayback {
	[self.voicePlayer stop];
	self.voicePlayer = nil;
	[self.playbackTimer invalidate];
	self.playbackTimer = nil;
	self.playingMessageId = 0;
	[self hidePlayerBar];
	[self.table reloadData];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
	[self stopPlayback];
}

#pragma mark - attachments

static const NSInteger kAttachSheetTag  = 41;
static const NSInteger kMessageSheetTag = 42;

- (void)attachTapped {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:@"Photo or Video",
														   @"Location",
														   @"Contact", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kAttachSheetTag;
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == kMessageSheetTag){
		[self runMessageAction:[sheet buttonTitleAtIndex:index]];
		return;
	}
	if (sheet.tag != kAttachSheetTag)
		return;
	if (index == 0)      [self pickMedia];
	else if (index == 1) [self sendCurrentLocation];
	else                 [self pickContact];
}

#pragma mark - message actions

- (void)messageHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;

	NSIndexPath *path = [self.table indexPathForRowAtPoint:[hold locationInView:self.table]];
	if (path)
		[self showActionsForRow:path.row];
}

/// The flattened message stores an absent value as NSNull, which answers no
/// string selector - asking one for its length is an unrecognized selector and
/// takes the app down.
- (NSString *)textOf:(NSDictionary *)m {
	NSString *text = m[@"text"];
	return [text isKindOfClass:NSString.class] ? text : nil;
}

/// Split out from the gesture so itglegacy://holdrow/N can reach it: a long
/// press cannot be delivered through a URL.
- (void)showActionsForRow:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.messages.count)
		return;

	NSDictionary *m = self.messages[row];
	if ([m[@"service"] boolValue])
		return;
	self.actionMessage = m;

	BOOL mine = [m[@"outgoing"] boolValue];
	NSMutableArray *items = [NSMutableArray arrayWithObjects:
			@{@"title" : @"Reply",   @"icon" : @"reply"},
			@{@"title" : @"Forward", @"icon" : @"forward"},
			@{@"title" : @"React",   @"icon" : @"react"}, nil];
	NSString *bodyText = [self textOf:m];
	if (bodyText.length)
		[items addObject:@{@"title" : @"Copy", @"icon" : @"copy"}];
	if (mine && bodyText.length)
		[items addObject:@{@"title" : @"Edit", @"icon" : @"edit"}];
	if (mine)
		[items addObject:@{@"title" : @"Delete", @"icon" : @"delete",
						   @"destructive" : @YES}];

	// Beside the message rather than over the whole screen, which is what
	// makes it read as belonging to that bubble.
	CGRect rect = [self.table rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	CGPoint where = [self.table convertPoint:
			CGPointMake(mine ? CGRectGetMaxX(rect) - 60 : 60, CGRectGetMaxY(rect) - 8)
									  toView:self.view];

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.view
				  onChoice:^(NSInteger index, NSString *title){
		[weakSelf runMessageAction:title];
	}];
}

- (void)runMessageAction:(NSString *)action {
	NSDictionary *m = self.actionMessage;
	if (![m[@"id"] isKindOfClass:NSNumber.class])
		return;
	int64_t messageId = [m[@"id"] longLongValue];
	if (!messageId)
		return;
	NSString *bodyText = [self textOf:m];

	if ([action isEqualToString:@"Reply"]){
		self.replyToId = messageId;
		self.editingId = 0;
		[self showComposeBanner:[NSString stringWithFormat:@"Reply to: %@",
				bodyText.length ? bodyText : (m[@"kind"] ?: @"message")]];
		[self.input becomeFirstResponder];

	} else if ([action isEqualToString:@"Forward"]){
		TGForwardPicker *picker = [[TGForwardPicker alloc] init];
		__weak typeof(self) weakSelf = self;
		picker.onPicked = ^(int64_t targetChatId){
			[[TGClient shared] forwardMessages:@[@(messageId)]
									  fromChat:weakSelf.chatId
										toChat:targetChatId];
		};
		[self.navigationController pushViewController:picker animated:YES];

	} else if ([action hasPrefix:@"React"]){
		[[TGClient shared] reactTo:messageId inChat:self.chatId emoji:@"\U0001F44D"];

	} else if ([action isEqualToString:@"Copy"]){
		if (bodyText.length)
			[UIPasteboard generalPasteboard].string = bodyText;

	} else if ([action isEqualToString:@"Edit"]){
		self.editingId = messageId;
		self.replyToId = 0;
		self.input.text = bodyText ?: @"";
		// Setting the text in code fires no editing-changed event, so Send has
		// to be swapped in by hand or the field looks unsendable.
		[self inputChanged];
		[self showComposeBanner:@"Editing"];
		[self.input becomeFirstResponder];

	} else if ([action isEqualToString:@"Delete"]){
		// The message goes off the screen at once and off the server when the
		// count runs out, so taking it back costs one tap and no dialog.
		int64_t chatId = self.chatId;
		NSMutableArray *without = [self.messages mutableCopy];
		[without removeObject:m];
		self.messages = without;
		[self.table reloadData];
		[self updateEmptyState];

		__weak typeof(self) weakSelf = self;
		[TGSnackbar showInView:self.view text:@"Message deleted" seconds:5
					  onCommit:^{
			[[TGClient shared] deleteMessage:messageId inChat:chatId];
		}];
		// Undo has no callback of its own: whatever the answer, re-reading the
		// history afterwards puts the row back or leaves it gone, correctly.
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ [weakSelf reload]; });
	}
	self.actionMessage = nil;
}

- (void)pickMedia {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary])
		return;

	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	// Without this the library shows photos only, and video cannot be sent.
	picker.mediaTypes = @[(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

/// One fix, then stop - a chat wants a pin, not a running trace.
- (void)sendCurrentLocation {
	if (!self.locationManager){
		self.locationManager = [[CLLocationManager alloc] init];
		self.locationManager.delegate = self;
		self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
	}
	[self.locationManager startUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager
	 didUpdateLocations:(NSArray *)locations {
	CLLocation *fix = [locations lastObject];
	[manager stopUpdatingLocation];
	if (!fix)
		return;
	[[TGClient shared] sendLocation:fix.coordinate.latitude
						  longitude:fix.coordinate.longitude
							 toChat:self.chatId];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
	[manager stopUpdatingLocation];
	NSLog(@"location: %@", error);
}

- (void)pickContact {
	ABPeoplePickerNavigationController *picker =
			[[ABPeoplePickerNavigationController alloc] init];
	picker.peoplePickerDelegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)picker
      shouldContinueAfterSelectingPerson:(ABRecordRef)person {
	NSString *name = (__bridge_transfer NSString *)
			ABRecordCopyCompositeName(person);
	ABMultiValueRef phones = ABRecordCopyValue(person, kABPersonPhoneProperty);
	NSString *phone = ABMultiValueGetCount(phones) > 0
			? (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex(phones, 0)
			: nil;
	if (phones) CFRelease(phones);

	[picker dismissViewControllerAnimated:YES completion:nil];
	if (phone.length)
		[[TGClient shared] sendContactNamed:name phone:phone toChat:self.chatId];
	return NO;
}

- (void)peoplePickerNavigationControllerDidCancel:(ABPeoplePickerNavigationController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info
{
	[picker dismissViewControllerAnimated:YES completion:nil];

	NSURL *movie = info[UIImagePickerControllerMediaURL];
	if (movie){
		[[TGClient shared] sendVideoAtPath:movie.path toChat:self.chatId];
		return;
	}

	UIImage *image = info[UIImagePickerControllerOriginalImage];
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

	// A call log entry calls back, which is the only thing anyone wants from
	// one - and a missed call is otherwise a dead end.
	if ([kind isEqualToString:@"messageCall"] && !self.isGroup){
		[TGCallViewController presentForUserId:self.chatId
										  name:self.chatTitle
									  outgoing:YES];
		return;
	}

	// A poll is voted in by tapping an option, which is a button of its own.
	if ([kind isEqualToString:@"messagePoll"])
		return;

	// A reply is unreadable if you cannot get to what it answers.
	// The flattened message stores absent values as NSNull, which answers no
	// number selector - asking it for a long long is what brought the app
	// down on the first tap on a voice note.
	NSNumber *replyTo = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	if (replyTo && [self scrollToMessageId:replyTo.longLongValue])
		return;

	// A theme file is the one document worth opening in place: tapping it
	// applies the theme, the way the official clients do.
	if ([kind isEqualToString:@"messageDocument"] &&
		[TGThemeFile handlesFile:(m[@"docName"] ?: @"")]){
		[self applyThemeFromMessage:m];
		return;
	}

	// Any other document: fetch it and keep a copy where it survives TDLib's
	// cache being pruned. Doing nothing at all was the previous answer.
	if ([kind isEqualToString:@"messageDocument"]){
		NSNumber *docId = [m[@"docId"] isKindOfClass:NSNumber.class] ? m[@"docId"] : nil;
		if (!docId)
			return;
		NSString *name = [m[@"docName"] length] ? m[@"docName"] : @"file";
		[self beginDownloadHUDForFile:[docId integerValue]];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			[me endDownloadHUD];
			if (!path){
				[me showAlertTitle:@"" message:@"This file could not be downloaded"];
				return;
			}
			NSString *documents = [NSSearchPathForDirectoriesInDomains(
					NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
			NSString *saved = [documents stringByAppendingPathComponent:
					name.lastPathComponent];
			[[NSFileManager defaultManager] removeItemAtPath:saved error:nil];
			NSError *copyError = nil;
			[[NSFileManager defaultManager] copyItemAtPath:path toPath:saved
													 error:&copyError];
			[me showAlertTitle:name
					   message:(copyError ? @"Downloaded, but it could not be saved."
										  : @"Saved to Documents.")];
		}];
		return;
	}

	// A video note plays where it sits, in its own circle - handing it to the
	// full-screen player turns a two-second glance into a modal screen.
	if ([kind isEqualToString:@"messageVideoNote"]){
		NSNumber *docId = m[@"docId"];
		if (![docId isKindOfClass:NSNumber.class])
			return;
		[self beginDownloadHUDForFile:[docId integerValue]];
		[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
			[self endDownloadHUD];
			if (path)
				[self playVideoNoteAtPath:path row:indexPath.row];
		}];
		return;
	}

	if ([kind isEqualToString:@"messageVideo"]){
		NSNumber *docId = m[@"docId"];
		if (![docId isKindOfClass:NSNumber.class])
			return;
		[self beginDownloadHUDForFile:[docId integerValue]];
		[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
			[self endDownloadHUD];
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

		// Tapping the one already playing is how you stop it; without this the
		// only way out was to leave the chat.
		if (self.playingMessageId == [m[@"id"] longLongValue] && self.voicePlayer){
			[self togglePlayback];
			return;
		}
		if (self.voicePlayer)
			[self stopPlayback];
		[self beginDownloadHUDForFile:[docId integerValue]];
		[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
			[self endDownloadHUD];
			NSLog(@"voice: file %@", path.lastPathComponent ?: @"(not downloaded)");
			if (!path)
				return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				NSString *wav = [TGVoiceDecoder wavFromOpusFile:path];
				NSLog(@"voice: decoded to %@ (%llu bytes)", wav.lastPathComponent ?: @"nothing",
						[[[NSFileManager defaultManager] attributesOfItemAtPath:wav ?: @""
																		  error:nil] fileSize]);
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
					NSLog(@"voice: playing %.1f s", self.voicePlayer.duration);
					self.voicePlayer.delegate = self;
					self.playingMessageId = [m[@"id"] longLongValue];
					[self.voicePlayer play];
					[self showPlayerBar];
					[self startPlaybackTimer];
					[self.table reloadData];
				});
			});
		}];
		return;
	}

	if ([kind isEqualToString:@"messagePhoto"]){
		NSNumber *fileId = [m[@"photoId"] isKindOfClass:NSNumber.class] ? m[@"photoId"] : nil;
		UIImage *img = fileId ? self.images[fileId] : nil;
		if (img){
			[self showFullScreenImage:img];
			return;
		}
		// Tapping a picture that has not come down yet used to do nothing at
		// all, which reads as a dead row; fetch it and then open it.
		if (!fileId)
			return;
		[self beginDownloadHUDForFile:[fileId integerValue]];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			[me endDownloadHUD];
			if (!path)
				return;
			UIImage *loaded = [UIImage imageWithContentsOfFile:path];
			if (!loaded && [path.pathExtension.lowercaseString isEqualToString:@"webp"])
				loaded = [UIImage convertFromWebP:path compressedData:nil error:nil];
			if (!loaded)
				return;
			me.images[fileId] = loaded;
			[me.table reloadData];
			[me showFullScreenImage:loaded];
		}];
		return;
	}
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
	return [scrollView viewWithTag:0xF118];
}

- (void)saveFullScreenImage:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan || !self.fullScreenImage)
		return;
	UIImageWriteToSavedPhotosAlbum(self.fullScreenImage, self,
			@selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error
  contextInfo:(void *)contextInfo {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
			message:(error ? @"Could not save" : @"Saved to Camera Roll")
		   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

/// UIAlertController does not exist on this target; UIAlertView is what the
/// rest of the file already uses.
- (void)showAlertTitle:(NSString *)title message:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:(title ?: @"")
													message:(message ?: @"")
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
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

	// A scroll view is all zooming needs; a 4S has no room for a custom one.
	UIScrollView *zoom = [[UIScrollView alloc] initWithFrame:backdrop.bounds];
	zoom.minimumZoomScale = 1.0f;
	zoom.maximumZoomScale = 4.0f;
	zoom.delegate = self;
	zoom.showsHorizontalScrollIndicator = NO;
	zoom.showsVerticalScrollIndicator = NO;
	[backdrop addSubview:zoom];

	UIImageView *view = [[UIImageView alloc] initWithFrame:backdrop.bounds];
	view.contentMode = UIViewContentModeScaleAspectFit;
	view.image = image;
	view.tag = 0xF118;
	[zoom addSubview:view];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(dismissFullScreen:)];
	[backdrop addGestureRecognizer:tap];

	// Hold the picture to keep it - the only way out of the app for an image.
	self.fullScreenImage = image;
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(saveFullScreenImage:)];
	[backdrop addGestureRecognizer:hold];

	UILabel *hint = [[UILabel alloc] initWithFrame:
			CGRectMake(0, backdrop.bounds.size.height - 34, backdrop.bounds.size.width, 20)];
	hint.text = @"Hold to save";
	hint.font = [UIFont systemFontOfSize:12];
	hint.textAlignment = NSTextAlignmentCenter;
	hint.textColor = [UIColor colorWithWhite:1 alpha:0.6f];
	hint.backgroundColor = [UIColor clearColor];
	[backdrop addSubview:hint];

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

/// Who wrote the message being answered. Only known once the original has been
/// fetched; TDLib's inline quote carries the text but not the author.
- (NSString *)quoteAuthorFor:(NSDictionary *)m {
	NSNumber *replyId = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	if (!replyId)
		return nil;
	NSDictionary *original = self.quotes[replyId];
	if (!original)
		return nil;
	if ([original[@"outgoing"] boolValue])
		return @"You";
	return [[TGClient shared] nameForUserId:[original[@"senderId"] longLongValue]];
}

- (CGFloat)decorationHeightFor:(NSDictionary *)m {
	CGFloat h = 0;
	if ([m[@"forward"] length])
		h += 18;
	// Their reply block is two lines beside a stripe: the author, then what
	// they said.
	if ([self quoteTextFor:m])
		h += 38;
	if ([m[@"reactions"] length])
		h += 18;
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

	CGFloat oneLine = [text sizeWithFont:
			[UIFont systemFontOfSize:[TGTheme shared].messageFontSize]].width;
	if (oneLine > kBubbleMaxW - 2 * kPadH)
		return NO;   // it wraps, so there is no short last line to share

	return (oneLine + 6 + [self timeWidthFor:m]) <= (kBubbleMaxW - 2 * kPadH);
}

/// Their forwarded line: "Forwarded from" in grey with the name after it in
/// the accent colour. Returns the height it took, so every kind of bubble can
/// carry it by shifting its own content down - a forwarded file used to look
/// exactly like one you had been sent directly.
- (CGFloat)layoutForwardIn:(TGBubbleCell *)cell
				   message:(NSDictionary *)m
					 width:(CGFloat)width
{
	NSString *from = m[@"forward"];
	if (![from length]){
		cell.forwardLabel.hidden = YES;
		return 0;
	}

	TGTheme *theme = [TGTheme shared];
	cell.forwardLabel.hidden = NO;
	cell.forwardLabel.frame = CGRectMake(kPadH, kPadV, width - 2 * kPadH, 16);

	NSString *line = [NSString stringWithFormat:@"Forwarded from %@", from];
	if ([cell.forwardLabel respondsToSelector:@selector(setAttributedText:)]){
		NSMutableAttributedString *styled =
				[[NSMutableAttributedString alloc] initWithString:line];
		[styled addAttribute:NSForegroundColorAttributeName
					   value:[theme secondaryTextColour]
					   range:NSMakeRange(0, line.length)];
		[styled addAttribute:NSForegroundColorAttributeName
					   value:[theme accentColour]
					   range:NSMakeRange(15, from.length)];
		[styled addAttribute:NSFontAttributeName
					   value:[UIFont boldSystemFontOfSize:12]
					   range:NSMakeRange(15, from.length)];
		cell.forwardLabel.attributedText = styled;
	} else {
		cell.forwardLabel.textColor = [theme accentColour];
		cell.forwardLabel.text = line;
	}
	return 18;
}

/// Question, the "N voted" line, one row per option, and the stamp.
- (CGFloat)pollHeightFor:(NSDictionary *)m {
	NSString *question = m[@"pollQuestion"] ?: @"Poll";
	CGSize qs = [question sizeWithFont:[UIFont boldSystemFontOfSize:15]
					 constrainedToSize:CGSizeMake(kBubbleMaxW - 2 * kPadH, 200)
						 lineBreakMode:NSLineBreakByWordWrapping];
	NSArray *options = m[@"pollOptions"];
	return kPadV + qs.height + 22 + kPollRow * options.count + 18;
}

/// A picture with no caption carries its own stamp on a plate, so the bubble
/// does not need a strip of empty space under it for one.
- (BOOL)stampSitsOnPictureFor:(NSDictionary *)m {
	return [self imageSizeFor:m].height > 0 && [self bodySizeFor:m].height == 0 &&
		   ![m[@"kind"] isEqualToString:@"messageVideoNote"] &&
		   ![m[@"kind"] isEqualToString:@"messageSticker"] &&
		   ![m[@"kind"] isEqualToString:@"messageAnimatedEmoji"];
}

- (CGSize)bodySizeFor:(NSDictionary *)m {
	NSString *text = m[@"text"] ?: @"";
	if (!text.length)
		return CGSizeZero;
	return [text sizeWithFont:[UIFont systemFontOfSize:[TGTheme shared].messageFontSize]
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
	// A voice message is a fixed block rather than a run of text: the disc,
	// the bars and the duration, sized the way their media components are.
	BOOL isVoice = [m[@"kind"] isEqualToString:@"messageVoiceNote"];

	CGSize body = [self bodySizeFor:m];
	CGSize pic  = [self imageSizeFor:m];
	// A forwarded anything carries a line saying where it came from.
	CGFloat forwarded = [m[@"forward"] length] ? 18 : 0;

	if ([m[@"kind"] isEqualToString:@"messageVideoNote"] && pic.height > 0)
		return MIN(MIN(pic.width, pic.height), 178) + 20;

	if ([m[@"docName"] isEqualToString:@"tgs"] && self.lottiePaths[m[@"docId"]])
		return 148;

	if ([m[@"service"] boolValue])
		return 30;

	// Their media block is 80dp tall; a voice message needs only the disc and
	// the bars, which comes to 54 on this screen.
	if ([m[@"kind"] isEqualToString:@"messageVoiceNote"])
		return 62 + forwarded;

	if ([m[@"kind"] isEqualToString:@"messagePoll"])
		return [self pollHeightFor:m] + 6;

	if ([m[@"kind"] isEqualToString:@"messageCall"])
		return 50 + forwarded;

	if ([m[@"kind"] isEqualToString:@"messageDocument"] ||
		[m[@"kind"] isEqualToString:@"messageContact"])
		return kFileTile + 2 * kPadV + 6 + forwarded;

	CGFloat h = kPadV * 2 + [self decorationHeightFor:m] +
			([self stampFitsInlineFor:m] || [self stampSitsOnPictureFor:m] ? 0 : 14);
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

/// The 2014 client never drew a bubble: it stretched Msg_In.png / Msg_Out.png,
/// tail and shading included, with caps 20/15 incoming and 15/15 outgoing, and
/// a body padding of 15+1 on the tail side against 9+1 on the other. So the
/// artwork sits behind the content box and hangs 6pt past it on the tail side.
- (BOOL)applyBubbleArtworkTo:(TGBubbleCell *)cell outgoing:(BOOL)mine {
	UIImage *art = [UIImage imageNamed:(mine ? @"Msg_Out" : @"Msg_In")];
	if (!art){
		cell.bubbleBg.hidden = YES;
		return NO;
	}

	cell.bubbleBg.hidden = NO;
	cell.bubbleBg.image = [art stretchableImageWithLeftCapWidth:(mine ? 15 : 20)
												  topCapHeight:15];

	CGRect box = cell.bubble.frame;
	CGFloat w = MAX(box.size.width + kBubbleTailOverhang, kBubbleMinW);
	CGFloat h = MAX(box.size.height, kBubbleMinH);
	cell.bubbleBg.frame = CGRectMake(
			mine ? box.origin.x : box.origin.x - kBubbleTailOverhang,
			box.origin.y, w, h);

	cell.bubble.backgroundColor = [UIColor clearColor];
	cell.bubble.layer.borderWidth = 0.0f;
	cell.bubble.layer.cornerRadius = 0.0f;
	cell.tail.hidden = YES;
	return YES;
}

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
	cell.bubbleBg.hidden = YES;
	cell.subtitle.hidden = YES;
	cell.sender.hidden = YES;
	cell.senderAvatar.hidden = YES;
	cell.tail.hidden = YES;
	cell.disc.hidden = YES;
	cell.wave.hidden = YES;

	// Service messages sit centred on the wallpaper, not in a bubble - joins,
	// renames, pins. Groups are full of them.
	if ([m[@"service"] boolValue]){
		TGTheme *serviceTheme = [TGTheme shared];
		// "joined the group" reads oddly with nobody attached to it.
		NSString *who = [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
		NSString *line = who.length
				? [NSString stringWithFormat:@"%@ %@", who, m[@"text"]]
				: (m[@"text"] ?: @"");

		// Their service message is a plate the width of its own text, centred -
		// not a bar across the chat. It sits over the wallpaper, so it is a
		// wash with white text rather than grey on grey.
		UIFont *font = [UIFont systemFontOfSize:12];
		CGFloat full = tableView.bounds.size.width;
		CGFloat textW = MIN([line sizeWithFont:font].width, full - 60);
		CGFloat plateW = textW + 20;

		cell.bubble.frame = CGRectMake((full - plateW) / 2, 4, plateW, 21);
		cell.bubble.backgroundColor = [serviceTheme serviceBubbleColour];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.layer.cornerRadius = 10.5f;
		cell.picture.hidden = YES;
		cell.time.text = @"";
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = font;
		cell.body.textAlignment = NSTextAlignmentCenter;
		cell.body.textColor = [serviceTheme serviceTextColour];
		cell.body.text = line;
		cell.body.frame = CGRectMake(0, 2, plateW, 17);
		return cell;
	}
	cell.body.textAlignment = NSTextAlignmentLeft;
	cell.bubble.layer.cornerRadius = 14;
	cell.lottie.hidden = YES;
	[cell.lottie stop];

	// Documents and contacts get their own layout: a round glyph on the left,
	// a bold first line and a grey second one. Rendering them as plain text
	// made them indistinguishable from a message that merely mentions a file.
	// A poll is a question with its options stacked under it, each a circle,
	// a line of text and its share of the vote - which is unreadable as the
	// run of text it used to be, and unvotable in a group without it.
	if ([kind isEqualToString:@"messagePoll"]){
		TGTheme *pollTheme = [TGTheme shared];
		NSArray *options = m[@"pollOptions"];
		NSString *question = m[@"pollQuestion"] ?: @"Poll";
		BOOL closed = [m[@"pollClosed"] boolValue];

		CGFloat width = kBubbleMaxW;
		CGFloat x = mine ? (tableView.bounds.size.width - width - 8) : 8;
		CGFloat height = [self pollHeightFor:m];
		cell.bubble.frame = CGRectMake(x, 3, width, height);
		cell.bubble.backgroundColor = mine ? [pollTheme bubbleMineColour]
										   : [pollTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [pollTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [pollTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [pollTheme bubbleCornerRadius];
		[self applyBubbleArtworkTo:cell outgoing:mine];

		cell.body.hidden = NO;
		cell.body.numberOfLines = 0;
		cell.body.font = [UIFont boldSystemFontOfSize:15];
		cell.body.textColor = [pollTheme primaryTextColour];
		cell.body.text = question;
		CGSize qs = [question sizeWithFont:cell.body.font
						 constrainedToSize:CGSizeMake(width - 2 * kPadH, 200)
							 lineBreakMode:NSLineBreakByWordWrapping];
		cell.body.frame = CGRectMake(kPadH, kPadV, width - 2 * kPadH, qs.height);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:12];
		cell.subtitle.textColor = [pollTheme secondaryTextColour];
		cell.subtitle.text = closed ? @"Final results"
			: [NSString stringWithFormat:@"%@ voted",
					[m[@"pollTotal"] integerValue] == 0 ? @"Nobody" : m[@"pollTotal"]];
		cell.subtitle.frame = CGRectMake(kPadH, kPadV + qs.height + 2,
										 width - 2 * kPadH, 16);

		// The option rows are rebuilt rather than reused: a cell that came back
		// from another poll would keep the wrong number of them.
		for (UIView *old in [cell.bubble.subviews copy])
			if (old.tag >= 0x9100 && old.tag < 0x9200)
				[old removeFromSuperview];
		cell.pollMessageId = [m[@"id"] longLongValue];

		CGFloat y = kPadV + qs.height + 22;
		for (NSUInteger i = 0; i < options.count; i++){
			NSDictionary *option = options[i];
			BOOL chosen = [option[@"is_chosen"] boolValue];
			NSInteger share = [option[@"vote_percentage"] integerValue];

			// The option itself is the button: a poll you vote in by choosing
			// from a list of the same options is a menu about a menu.
			// The option itself is the button: a poll you vote in by choosing
			// from a list of the same options is a menu about a menu. The tag
			// carries which option it is, and the cell carries which poll.
			UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
			row.frame = CGRectMake(kPadH, y, width - 2 * kPadH, kPollRow);
			row.tag = 0x9100 + (NSInteger)i;
			row.enabled = !closed;
			[row addTarget:self action:@selector(pollOptionTapped:)
			  forControlEvents:UIControlEventTouchUpInside];
			[cell.bubble addSubview:row];

			UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 4, 16, 16)];
			dot.layer.cornerRadius = 8;
			dot.layer.borderWidth = 1.5f;
			dot.layer.borderColor = [pollTheme accentColour].CGColor;
			dot.backgroundColor = chosen ? [pollTheme accentColour] : [UIColor clearColor];
			[row addSubview:dot];

			UILabel *label = [[UILabel alloc] initWithFrame:
					CGRectMake(24, 2, row.bounds.size.width - 66, 20)];
			label.text = option[@"text"][@"text"] ?: option[@"text"] ?: @"";
			label.font = [UIFont systemFontOfSize:14];
			label.textColor = [pollTheme primaryTextColour];
			label.backgroundColor = [UIColor clearColor];
			[row addSubview:label];

			UILabel *percent = [[UILabel alloc] initWithFrame:
					CGRectMake(row.bounds.size.width - 40, 2, 40, 20)];
			percent.text = [NSString stringWithFormat:@"%ld%%", (long)share];
			percent.font = [UIFont systemFontOfSize:13];
			percent.textAlignment = NSTextAlignmentRight;
			percent.textColor = [pollTheme secondaryTextColour];
			percent.backgroundColor = [UIColor clearColor];
			[row addSubview:percent];

			// The bar under each option is the only way the result reads at a
			// glance; the number alone makes you compare digits.
			UIView *track = [[UIView alloc] initWithFrame:
					CGRectMake(24, kPollRow - 6, row.bounds.size.width - 24, 2)];
			track.backgroundColor = [pollTheme separatorColour];
			[row addSubview:track];

			UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(24, kPollRow - 6,
					(row.bounds.size.width - 24) * share / 100.0f, 2)];
			fill.backgroundColor = [pollTheme accentColour];
			[row addSubview:fill];

			y += kPollRow;
		}

		cell.picture.hidden = YES;
		cell.disc.hidden = YES;
		cell.time.text = [self stampFor:m];
		cell.time.textColor = [pollTheme timeColour];
		CGFloat pollTimeW = [self timeWidthFor:m];
		cell.time.frame = CGRectMake(width - pollTimeW - kPadH, height - 17,
									 pollTimeW - (mine ? 18 : 0), 12);
		cell.ticks.hidden = !mine;
		if (mine){
			cell.ticks.image = [TGIcons ticksWhite:NO];
			cell.ticks.frame = CGRectMake(width - kPadH - 15, height - 15, 15, 9);
		}
		return cell;
	}

	// A call reads as a small bubble with an arrow saying which way it went and
	// whether it was answered. Tapping it calls back.
	if ([kind isEqualToString:@"messageCall"]){
		TGTheme *callTheme = [TGTheme shared];
		BOOL missed = [m[@"callState"] isEqualToString:@"missed"];
		NSString *line = m[@"text"] ?: @"Call";

		CGFloat width = MIN(kBubbleMaxW,
				[line sizeWithFont:[UIFont systemFontOfSize:15]].width + 76);
		CGFloat fwd = [self layoutForwardIn:cell message:m width:width];
		CGFloat height = 44 + fwd;
		CGFloat x = mine ? (tableView.bounds.size.width - width - 8) : 8;
		cell.bubble.frame = CGRectMake(x, 3, width, height);
		cell.bubble.backgroundColor = mine ? [callTheme bubbleMineColour]
										   : [callTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [callTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [callTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [callTheme bubbleCornerRadius];
		[self applyBubbleArtworkTo:cell outgoing:mine];

		cell.disc.hidden = NO;
		cell.disc.image = [TGIcons callArrowOutgoing:mine missed:missed];
		cell.disc.frame = CGRectMake(kPadH, fwd + (height - fwd - 14) / 2, 14, 14);

		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont systemFontOfSize:15];
		cell.body.textColor = [callTheme primaryTextColour];
		cell.body.text = line;
		cell.body.frame = CGRectMake(kPadH + 20, fwd + 6, width - kPadH - 26, 20);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:12];
		cell.subtitle.textColor = [callTheme timeColour];
		cell.subtitle.text = [self stampFor:m];
		cell.subtitle.frame = CGRectMake(kPadH + 20, fwd + 24, width - kPadH - 26, 14);

		cell.picture.hidden = YES;
		cell.time.text = @"";
		cell.ticks.hidden = YES;
		return cell;
	}

	if ([kind isEqualToString:@"messageDocument"] ||
		[kind isEqualToString:@"messageContact"]){
		BOOL isDoc = [kind isEqualToString:@"messageDocument"];
		NSArray *lines = [m[@"text"] componentsSeparatedByString:@"\n"];
		NSString *first = lines.count ? lines[0] : @"";
		NSString *second = lines.count > 1 ? lines[1] : @"";

		TGTheme *cardTheme = [TGTheme shared];
		// Their file block is 253x87 at 360dp: an 80dp tile on the left, the
		// name and the size stacked beside it.
		CGFloat width = 225;
		CGFloat fwd = [self layoutForwardIn:cell message:m width:width];
		CGFloat height = kFileTile + 2 * kPadV + fwd;
		CGFloat x = mine ? (tableView.bounds.size.width - width - 8) : 8;
		cell.bubble.frame = CGRectMake(x, 3, width, height);
		cell.bubble.backgroundColor = mine ? [cardTheme bubbleMineColour]
										   : [cardTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [cardTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [cardTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [cardTheme bubbleCornerRadius];
		[self applyBubbleArtworkTo:cell outgoing:mine];

		// A document gets the tile; a contact keeps its initials, because a
		// sheet of paper says nothing about a person.
		cell.icon.hidden = NO;
		// A document gets the square tile at their size; a contact gets a round
		// avatar, which is smaller and sits centred beside the name.
		CGFloat side = isDoc ? kFileTile : 48;
		cell.icon.frame = CGRectMake(kPadH, fwd + kPadV + (kFileTile - side) / 2, side, side);
		if (isDoc){
			cell.icon.text = @"";
			cell.icon.layer.cornerRadius = 3;
			cell.icon.backgroundColor = [cardTheme fileTileColour];

			cell.disc.hidden = NO;
			cell.disc.image = [TGIcons fileDiscOfSide:kFileDisc];
			cell.disc.frame = CGRectMake(kPadH + (kFileTile - kFileDisc) / 2,
										 fwd + kPadV + (kFileTile - kFileDisc) / 2,
										 kFileDisc, kFileDisc);
			// The tile was added to the bubble after the disc was, so without
			// this it covers the glyph it is supposed to carry.
			[cell.bubble bringSubviewToFront:cell.disc];
		} else {
			NSString *initials = first.length ? [first substringToIndex:1] : @"?";
			NSArray *words = [first componentsSeparatedByString:@" "];
			if (words.count > 1 && [words[1] length])
				initials = [initials stringByAppendingString:[words[1] substringToIndex:1]];
			cell.icon.text = initials.uppercaseString;
			cell.icon.font = [UIFont boldSystemFontOfSize:18];
			cell.icon.layer.cornerRadius = side / 2;
			cell.icon.backgroundColor = [cardTheme mediaCircleColour];
		}

		CGFloat textX = kPadH + side + 10;
		cell.body.hidden = NO;
		cell.body.numberOfLines = 2;
		cell.body.font = [UIFont systemFontOfSize:15];
		cell.body.textColor = isDoc ? [cardTheme fileNameColour]
									: [cardTheme primaryTextColour];
		cell.body.text = first;
		cell.body.frame = CGRectMake(textX, fwd + kPadV + 8, width - textX - kPadH, 38);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:13];
		cell.subtitle.textColor = [cardTheme fileMetaColour];
		cell.subtitle.text = second;
		cell.subtitle.frame = CGRectMake(textX, fwd + kPadV + 46, width - textX - kPadH, 17);

		cell.time.text = [self stampFor:m];
		cell.time.textColor = [cardTheme timeColour];
		CGFloat fileTimeW = [self timeWidthFor:m];
		CGFloat fileTicks = mine ? 18 : 0;
		cell.time.frame = CGRectMake(width - fileTimeW - kPadH, height - 17,
									 fileTimeW - fileTicks, 12);
		cell.ticks.hidden = !mine;
		if (mine){
			cell.ticks.image = [TGIcons ticksWhite:NO];
			cell.ticks.frame = CGRectMake(width - kPadH - 15, height - 15, 15, 9);
		}
		cell.picture.hidden = YES;
		return cell;
	}

	// A voice message is a fixed block rather than a run of text: the disc,
	// the bars and the duration, sized the way their media components are.
	BOOL isVoice = [m[@"kind"] isEqualToString:@"messageVoiceNote"];

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

	if (isVoice)
		contentW = 190;
	CGFloat bubbleW = MAX(contentW + 2 * kPadH, timeW + 2 * kPadH + 8);
	bubbleW = MIN(bubbleW, kBubbleMaxW + 2 * kPadH);
	BOOL stampOnPicture = [self stampSitsOnPictureFor:m];
	CGFloat bubbleH  = kPadV * 2 + (inlineStamp || stampOnPicture ? 0 : 14) +
			[self decorationHeightFor:m] +
			(pic.height ? pic.height + 4 : 0) + body.height;
	// The voice block has its own size: a 40pt disc with the bars beside it.
	if (isVoice)
		bubbleH = 56 + ([m[@"forward"] length] ? 18 : 0);

	CGFloat x = mine ? (tableView.bounds.size.width - bubbleW - 8) : 8;
	// Photos of one album sit flush against each other, so the block reads as
	// a single post rather than a run of separate messages.
	CGFloat top = [self continuesAlbumAtRow:indexPath.row] ? 0 : 3;

	// In a group you need to know who is speaking.
	int64_t senderId = [m[@"senderId"] longLongValue];
	NSString *senderName = (self.isGroup && !mine)
			? [[TGClient shared] nameForUserId:senderId] : nil;
	if (senderName.length){
		// The bubble shifts right to make room for the avatar beside it.
		x += kAvatarSide + 4;
		cell.senderAvatar.hidden = NO;
		cell.senderAvatar.image = [self avatarForUser:senderId name:senderName];

		cell.sender.hidden = NO;
		cell.sender.text = senderName;
		cell.sender.textColor = TGSenderColour(senderId);
		cell.sender.frame = CGRectMake(x + kPadH, 2, tableView.bounds.size.width - x - 20, 14);
		top = 18;
	}

	cell.bubble.frame = CGRectMake(x, top, bubbleW, bubbleH);

	if (!cell.senderAvatar.hidden)
		cell.senderAvatar.frame = CGRectMake(8, top + bubbleH - kAvatarSide,
											 kAvatarSide, kAvatarSide);

	// Outgoing green, incoming white - the convention every client uses.
	// A sticker gets neither: no fill, no border.
	TGTheme *theme = [TGTheme shared];
	UIColor *fill = mine ? [theme bubbleMineColour] : [theme bubbleTheirsColour];
	cell.bubble.backgroundColor = isSticker ? [UIColor clearColor] : fill;

	// The tail hangs off the bottom corner on the side the message came from.
	// It has to be drawn from `fill` rather than from the bubble's own colour,
	// which on a freshly dequeued cell has not been set yet and reads as black.
	cell.tail.hidden = isSticker;
	if (!cell.tail.hidden){
		cell.tail.image = [TGIcons bubbleTailForColour:fill outgoing:mine];
		cell.tail.frame = mine
				? CGRectMake(x + bubbleW - 1, top + bubbleH - 10, 6, 10)
				: CGRectMake(x - 5, top + bubbleH - 10, 6, 10);
	}
	cell.bubble.layer.borderWidth = isSticker ? 0.0f : [theme bubbleBorderWidth];
	cell.bubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
	cell.bubble.layer.cornerRadius = [theme bubbleCornerRadius];
	if (!isSticker)
		[self applyBubbleArtworkTo:cell outgoing:mine];
	// A flat outgoing bubble is a solid accent colour, so its text inverts.
	cell.body.textColor = [theme primaryTextColour];

	// A video note is a circle, with no bubble around it - that is how every
	// client draws them.
	BOOL isRound = [m[@"kind"] isEqualToString:@"messageVideoNote"];
	if (isRound && pic.height > 0){
		// Their video note is 200dp across; taking the thumbnail's own size
		// filled almost the whole width of a 320pt screen.
		CGFloat side = MIN(MIN(pic.width, pic.height), 178);
		cell.bubbleBg.hidden = YES;
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
		cell.bubbleBg.hidden = YES;
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

	y += [self layoutForwardIn:cell message:m width:bubbleW];

	NSString *quoted = [self quoteTextFor:m];
	UILabel *quoteAuthor = (UILabel *)[cell.bubble viewWithTag:0x9003];
	if (quoted){
		// A 2pt stripe the height of the block, then the author's name and the
		// line being answered - which is how their reply reads at a glance.
		cell.quoteBar.hidden = NO;
		cell.quoteBar.backgroundColor = [theme accentColour];
		cell.quoteBar.frame = CGRectMake(kPadH, y, 2, 34);

		if (!quoteAuthor){
			quoteAuthor = [[UILabel alloc] init];
			quoteAuthor.tag = 0x9003;
			quoteAuthor.backgroundColor = [UIColor clearColor];
			[cell.bubble addSubview:quoteAuthor];
		}
		quoteAuthor.hidden = NO;
		quoteAuthor.font = [UIFont boldSystemFontOfSize:13];
		quoteAuthor.textColor = [theme accentColour];
		quoteAuthor.text = [self quoteAuthorFor:m] ?: @"Reply";
		quoteAuthor.frame = CGRectMake(kPadH + 8, y, bubbleW - 2 * kPadH - 10, 16);

		// The forwarded line has a label of its own now, so the quote can use
		// this one rather than a second one built at runtime.
		cell.quote.hidden = NO;
		cell.quote.numberOfLines = 1;
		cell.quote.font = [UIFont systemFontOfSize:13];
		cell.quote.textColor = [theme primaryTextColour];
		cell.quote.text = quoted;
		cell.quote.frame = CGRectMake(kPadH + 8, y + 17, bubbleW - 2 * kPadH - 10, 17);
		y += 38;
	} else {
		quoteAuthor.hidden = YES;
	}

	cell.mediaStamp.hidden = YES;
	if (pic.height > 0){
		cell.picture.hidden = NO;
		cell.picture.image = [self imageFor:m];
		cell.picture.frame = CGRectMake(kPadH, y, pic.width, pic.height);
		cell.picture.layer.cornerRadius = kMediaRadius;

		// A video says so with a play button in the middle of the frame.
		cell.disc.hidden = ![kind isEqualToString:@"messageVideo"] &&
						   ![kind isEqualToString:@"messageAnimation"];
		if (!cell.disc.hidden){
			CGFloat disc = 42;
			cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:NO];
			cell.disc.frame = CGRectMake(kPadH + (pic.width - disc) / 2,
										 y + (pic.height - disc) / 2, disc, disc);
		}

		// With no caption under it the stamp has nowhere grey to sit, so it
		// goes on the picture itself, on a plate.
		if (!body.height){
			NSString *stamp = [self stampFor:m];
			CGFloat plateW = [stamp sizeWithFont:cell.mediaStamp.font].width +
					(mine ? 30 : 14);
			cell.mediaStamp.hidden = NO;
			cell.mediaStamp.backgroundColor = [theme mediaStampColour];
			cell.mediaStamp.text = stamp;
			cell.mediaStamp.frame = CGRectMake(
					kPadH + pic.width - plateW - 5, y + pic.height - 21, plateW, 16);
			// The ticks were added to the bubble before the plate was, so
			// without this they end up behind it.
			[cell.bubble bringSubviewToFront:cell.ticks];
		}
		y += pic.height + 4;
	} else {
		cell.picture.hidden = YES;
		cell.picture.image = nil;
	}

	if (isVoice){
		TGTheme *voiceTheme = [TGTheme shared];
		CGFloat disc = 36;
		CGFloat left = kPadH + disc + 8;
		BOOL isPlaying = (self.playingMessageId == [m[@"id"] longLongValue]);

		cell.voiceMessageId = [m[@"id"] longLongValue];
		cell.waveformData = m[@"waveform"];

		CGFloat fwd = [self layoutForwardIn:cell message:m width:bubbleW];

		cell.disc.hidden = NO;
		cell.disc.image = [TGIcons mediaDiscOfSide:disc
										   playing:(isPlaying && self.voicePlayer.playing)];
		cell.disc.frame = CGRectMake(kPadH, fwd + (bubbleH - fwd - disc) / 2, disc, disc);

		// The bars take the width left over once the stamp has its corner, and
		// the part already heard is drawn solid.
		cell.wave.hidden = NO;
		CGSize waveSize = CGSizeMake(bubbleW - left - kPadH, 18);
		cell.wave.image = [TGIcons waveform:m[@"waveform"]
									   size:waveSize
									 played:(isPlaying ? [self playedFraction] : 0)
									 colour:[voiceTheme accentColour]];
		cell.wave.frame = CGRectMake(left, fwd + 10, waveSize.width, waveSize.height);

		NSInteger seconds = [m[@"duration"] integerValue];
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont systemFontOfSize:12];
		cell.body.textColor = [voiceTheme secondaryTextColour];
		cell.body.text = [NSString stringWithFormat:@"%ld:%02ld",
				(long)(seconds / 60), (long)(seconds % 60)];
		cell.body.frame = CGRectMake(left, bubbleH - 20, 44, 14);

		cell.picture.hidden = YES;
		cell.time.text = [self stampFor:m];
		cell.time.textColor = [voiceTheme timeColour];
		CGFloat tickRoom = mine ? 18 : 0;
		cell.time.frame = CGRectMake(bubbleW - timeW - kPadH, bubbleH - 20,
									 timeW - tickRoom, 12);
		cell.ticks.hidden = !mine;
		if (mine){
			cell.ticks.image = [TGIcons ticksWhite:NO];
			cell.ticks.frame = CGRectMake(bubbleW - kPadH - 15, bubbleH - 18, 15, 9);
		}
		return cell;
	}

	cell.body.hidden = (body.height == 0);
	cell.body.numberOfLines = 0;
	cell.body.font = [UIFont systemFontOfSize:[TGTheme shared].messageFontSize];
	cell.body.text = m[@"text"];
	cell.body.frame = CGRectMake(kPadH, y, body.width, body.height);

	// Reactions sit under the message, as they do everywhere else.
	UILabel *reactions = (UILabel *)[cell.bubble viewWithTag:0x9002];
	NSString *reactionText = m[@"reactions"];
	if ([reactionText length]){
		if (!reactions){
			reactions = [[UILabel alloc] init];
			reactions.tag = 0x9002;
			reactions.backgroundColor = [UIColor clearColor];
			reactions.font = [UIFont systemFontOfSize:13];
			[cell.bubble addSubview:reactions];
		}
		reactions.hidden = NO;
		reactions.text = reactionText;
		reactions.textColor = [theme secondaryTextColour];
		reactions.frame = CGRectMake(kPadH, y + body.height + 2, bubbleW - 2 * kPadH, 16);
	} else {
		reactions.hidden = YES;
	}

	// A stamp already on the picture must not be repeated under it.
	BOOL onPicture = !cell.mediaStamp.hidden;
	cell.time.text = (onPicture || [self albumContinuesAfterRow:indexPath.row])
			? @"" : [self stampFor:m];
	cell.time.textColor = [theme timeColour];
	CGFloat tickW = mine ? 18 : 0;
	CGFloat stampY = inlineStamp ? (y + body.height - 14) : (bubbleH - kPadV - 13);
	cell.time.frame = CGRectMake(bubbleW - timeW - kPadH, stampY, timeW - tickW, 12);

	cell.ticks.hidden = !mine;
	if (mine && onPicture){
		// Inside the plate the ticks need white; green would vanish into it.
		cell.ticks.image = [TGIcons ticksWhite:YES];
		cell.ticks.frame = CGRectMake(CGRectGetMaxX(cell.mediaStamp.frame) - 20,
									  CGRectGetMidY(cell.mediaStamp.frame) - 4, 15, 9);
	} else if (mine){
		// Checks sit on a pale bubble now, so they are drawn in their green
		// rather than white.
		cell.ticks.image = [TGIcons ticksWhite:NO];
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
		// These three sit above the composer and are positioned from it, so
		// they stayed behind the keyboard until they were moved as well.
		CGFloat top = CGRectGetMinY(self.inputBar.frame);
		if (self.composeBanner && !self.composeBanner.hidden){
			CGRect banner = self.composeBanner.frame;
			banner.origin.y = top - banner.size.height;
			self.composeBanner.frame = banner;
		}
		if (self.stickerPanel){
			CGRect panel = self.stickerPanel.frame;
			panel.origin.y = top - panel.size.height;
			self.stickerPanel.frame = panel;
		}
		if (self.scrollDownButton && !self.scrollDownButton.hidden)
			self.scrollDownButton.frame = CGRectMake(b.size.width - 44, top - 44, 34, 34);
	} completion:^(BOOL done){
		[self scrollToBottomAnimated:NO];
	}];
}

@end

// vim:ft=objc

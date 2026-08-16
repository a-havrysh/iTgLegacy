#import "TGChatViewController.h"
#import "TGClient.h"
#import "AppDelegate.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGForwardPicker.h"
#import "TGVoiceRecorder.h"
#import "TGProfileViewController.h"
#import "TGPollComposerViewController.h"
#import "TGThemeFile.h"
#import "TGCapabilities.h"
#import "TGMosaicLayout.h"
#import "TGEmoji.h"
#import <AddressBookUI/AddressBookUI.h>
#import <CoreLocation/CoreLocation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <QuartzCore/QuartzCore.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MapKit/MapKit.h>
#import <AVFoundation/AVFoundation.h>
#import "TGVoiceDecoder.h"
#import "TGMusicPlayer.h"
#import "UIImage+WebP.h"
#import "TGLottieView.h"
#import "UIView+SafeTint.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGSnackbar.h"
#import "TGReactionPickerView.h"
#import "TGMessageActionsSheet.h"
#import "TGStickerPanelView.h"
#import "TGClient+Messages.h"
#import "TGClient+MessageContent.h"
#import "TGClient+Reactions.h"
#import "TGClient+Bots.h"
#import "TGClient+Translation.h"
#import "TGClient+Search.h"
#import "TGClient+WebLinks.h"
#import "TGClient+Notifications.h"
#import "TGVideoCaptureViewController.h"
#import "TGAssetPicker.h"
#import <ImageIO/ImageIO.h>
#import "TGClient+Groups.h"
#import "TGClient+SecretChats.h"
#import "TGClient+ChatManagement.h"
#import "TGClient+Stickers.h"
#import "TGClient+Files.h"
#import "TGClient+ChatList.h"
#import "TGMediaViewController.h"
#import "TGImageDecode.h"
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "TGAlertView.h"

@interface NSObject (TGReadingList)
+ (id)defaultReadingList;
- (BOOL)addReadingListItemWithURL:(NSURL *)url
							title:(NSString *)title
					  previewText:(NSString *)previewText
							error:(NSError **)error;
@end

// Their design system is drawn for Android at 360dp; a 4S is 320pt, so
// everything taken from it is scaled by 0.889 and rounded to a whole point.
static const CGFloat kInputHeight = 43.0f;
static const CGFloat kInputSwipeDismissDistance = 18.0f;
static const CGFloat kInputSwipeDismissVelocity = 260.0f;
static const CGFloat kFloatingButtonSide = 36.0f;
static const CGFloat kFloatingButtonGap  = 7.0f;
static const CGFloat kComposeBannerHeight = 28.0f;
static const NSInteger kPinnedBannerHighlightTag = 991;
// Msg_In.png / Msg_Out.png carry the tail inside the artwork: their body
// padding is 15+1 on the tail side against 9+1 on the other, so the picture
// hangs 6pt past the content box.
static const CGFloat kBubbleTailOverhang = 6.0f;
static const CGFloat kRetinaPixel = 0.5f;
static const CGFloat kBubbleMinW = 40.0f;
static const CGFloat kBubbleMinH = 31.0f;
static const CGFloat kBubbleMaxW  = 244.0f;
static const CGFloat kBubbleReferenceWidth = 320.0f;
static const CGFloat kBubbleBudgetAtReference = 250.0f;
static const CGFloat kBubbleOutgoingTrim = 12.0f;
static const CGFloat kBubbleAvatarTrim   = 40.0f;
static const CGFloat kPadH        = 10.0f;
static const CGFloat kAvatarSide  = 38.0f;
static const CGFloat kPadV        = 5.0f;
static const CGFloat kForwardJumpSide = 22.0f;

static BOOL TGChatIsPad(void) {
	static BOOL pad = NO;
	static BOOL known = NO;
	if (!known){
		known = YES;
		pad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
	}
	return pad;
}

static CGFloat TGMessageBaseFontSize(void) {
	CGFloat size = [TGTheme shared].messageFontSize;
	return size > 0 ? size : 16.0f;
}

static UIColor *TGMessageBodyColour(void) {
	static UIColor *colour = nil;
	if (!colour)
		colour = [UIColor colorWithRed:20 / 255.0f green:22 / 255.0f
								  blue:23 / 255.0f alpha:1.0f];
	return colour;
}
static const CGFloat kImageMax    = 200.0f;
static const NSUInteger kPictureMemoryBudget = 5 * 1024 * 1024;
static const NSUInteger kMaxLivePictures = 12;
static const CGFloat kDayRowHeight    = 27.0f;
static const CGFloat kUnreadRowHeight = 34.0f;
static const CGFloat kSystemPlateHeight = 21.0f;

static UIColor *TGSystemPlateColour(void) {
	static UIColor *colour = nil;
	if (!colour)
		colour = [UIColor colorWithRed:70 / 255.0f green:99 / 255.0f
								  blue:126 / 255.0f alpha:0.4f];
	return colour;
}

static UIImage *TGUnreadDividerImage(void) {
	static UIImage *image = nil;
	static BOOL looked = NO;
	if (!looked){
		looked = YES;
		UIImage *raw = [UIImage imageNamed:@"ConversationNewMessagesDivider"];
		if (raw)
			image = [raw stretchableImageWithLeftCapWidth:1 topCapHeight:0];
	}
	return image;
}

static UIImage *TGUnreadArrowImage(void) {
	static UIImage *image = nil;
	if (image)
		return image;
	CGSize size = CGSizeMake(11, 8);
	if (UIGraphicsBeginImageContextWithOptions != NULL)
		UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
	else
		UIGraphicsBeginImageContext(size);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetLineWidth(ctx, 2.0f);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);
	CGContextSetRGBStrokeColor(ctx, 140 / 255.0f, 162 / 255.0f, 182 / 255.0f, 1.0f);
	CGContextMoveToPoint(ctx, 1.5f, 1.5f);
	CGContextAddLineToPoint(ctx, 5.5f, 6.0f);
	CGContextAddLineToPoint(ctx, 9.5f, 1.5f);
	CGContextStrokePath(ctx);
	image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}
// Their file block: an 80dp tile carrying a 42dp disc, 71 and 37 here.
static const CGFloat kFileTile    = 71.0f;
static const CGFloat kFileDisc    = 37.0f;
// A picture in a bubble is clipped to the same radius their media uses.
static const CGFloat kMediaRadius = 6.0f;
static const CGFloat kAlbumGap    = 2.0f;
static const CGFloat kMosaicMinTileSide = 68.0f;
// One option of a poll: a 16 circle, the text, the share, and the bar under it.
static const CGFloat kPollRow     = 30.0f;
static const CGFloat kChipsRowTopGap    = 4.0f;
static const CGFloat kChipsRowBottomGap = 3.0f;
static const CGFloat kSignatureHeight   = 14.0f;
static const CGFloat kSignatureTopGap   = 2.0f;
static const CGFloat kBareChipsTopGap   = 6.0f;
static const NSUInteger kLargeEmojiTextLimit = 64;
static const CGFloat kPreviewBar   = 2.0f;
static const CGFloat kPreviewGap   = 8.0f;
static const CGFloat kPreviewThumb = 52.0f;
static const CGFloat kPreviewLargeMax = 160.0f;
static const CGFloat kInstantHeight   = 33.0f;

static const CGFloat kMapCardW = 220.0f;
static const CGFloat kMapCardH = 130.0f;

static CGSize TGDrawnSizeForImageSize(CGSize source) {
	if (source.width < 1 || source.height < 1)
		return CGSizeZero;
	CGFloat scale = MIN(kImageMax / source.width, kImageMax / source.height);
	scale = MIN(scale, 1.0f);
	return CGSizeMake(floorf(source.width * scale), floorf(source.height * scale));
}

static UIImage *TGImageDrawnAtPointSize(UIImage *source, CGSize points) {
	if (!source || points.width < 1 || points.height < 1)
		return source;
	CGFloat screen = [UIScreen mainScreen].scale;
	if (source.size.width * source.scale <= points.width * screen &&
		source.size.height * source.scale <= points.height * screen)
		return source;
	UIGraphicsBeginImageContextWithOptions(points, NO, 0.0f);
	[source drawInRect:CGRectMake(0, 0, points.width, points.height)];
	UIImage *smaller = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return smaller ?: source;
}

static UIColor *TGChatHexColour(unsigned int rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0f
						   green:((rgb >> 8) & 0xFF) / 255.0f
							blue:(rgb & 0xFF) / 255.0f
						   alpha:1.0f];
}

static BOOL TGTextIsRightToLeft(NSString *text) {
	NSUInteger length = text.length;
	for (NSUInteger i = 0; i < length; i++){
		unichar c = [text characterAtIndex:i];
		if (c >= 0xD800 && c <= 0xDBFF){
			i++;
			continue;
		}
		if ((c >= 0x0590 && c <= 0x08FF) ||
			(c >= 0xFB1D && c <= 0xFDFF) ||
			(c >= 0xFE70 && c <= 0xFEFF))
			return YES;
		if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
			(c >= 0x00C0 && c <= 0x058F) ||
			(c >= 0x0900 && c <= 0x1FFF) ||
			(c >= 0x2C00 && c <= 0xD7FF) ||
			(c >= 0xF900 && c <= 0xFB17))
			return NO;
	}
	return NO;
}

#pragma mark - link preview block

@interface TGLinkPreviewView : UIView
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) void (^onOpen)(NSString *url);
@property (nonatomic, copy) void (^onInstantView)(NSString *url);
+ (CGSize)sizeForPreview:(NSDictionary *)preview
				   image:(UIImage *)image
				maxWidth:(CGFloat)maxWidth;
- (void)configureWithPreview:(NSDictionary *)preview
					   image:(UIImage *)image
					outgoing:(BOOL)outgoing
					maxWidth:(CGFloat)maxWidth;
@end

@implementation TGLinkPreviewView {
	UIView *_bar;
	UILabel *_site;
	UILabel *_title;
	UILabel *_text;
	UIImageView *_thumb;
	UIButton *_instant;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	self.backgroundColor = [UIColor clearColor];

	_bar = [[UIView alloc] init];
	[self addSubview:_bar];

	_site = [[UILabel alloc] init];
	_site.font = [UIFont boldSystemFontOfSize:14];
	_site.backgroundColor = [UIColor clearColor];
	[self addSubview:_site];

	_title = [[UILabel alloc] init];
	_title.font = [UIFont boldSystemFontOfSize:14];
	_title.numberOfLines = 2;
	_title.backgroundColor = [UIColor clearColor];
	_title.textColor = TGChatHexColour(0x141617);
	[self addSubview:_title];

	_text = [[UILabel alloc] init];
	_text.font = [UIFont systemFontOfSize:14];
	_text.numberOfLines = 2;
	_text.backgroundColor = [UIColor clearColor];
	_text.textColor = TGChatHexColour(0x62768A);
	[self addSubview:_text];

	_thumb = [[UIImageView alloc] init];
	_thumb.contentMode = UIViewContentModeScaleAspectFill;
	_thumb.clipsToBounds = YES;
	[self addSubview:_thumb];

	_instant = [UIButton buttonWithType:UIButtonTypeCustom];
	_instant.titleLabel.font = [UIFont boldSystemFontOfSize:13];
	[_instant setTitleColor:TGChatHexColour(0x506E8D) forState:UIControlStateNormal];
	[_instant setTitleShadowColor:[UIColor colorWithWhite:1.0f alpha:0.7f]
						 forState:UIControlStateNormal];
	_instant.titleLabel.shadowOffset = CGSizeMake(0, 1);
	[_instant setTitle:@"INSTANT VIEW" forState:UIControlStateNormal];
	[_instant addTarget:self action:@selector(instantTapped)
	   forControlEvents:UIControlEventTouchUpInside];
	_instant.hidden = YES;
	[self addSubview:_instant];

	[self addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(blockTapped)]];
	return self;
}

+ (BOOL)preview:(NSDictionary *)preview showsLargeMediaWithImage:(UIImage *)image {
	if (!image)
		return NO;
	return [preview[@"hasLargeMedia"] boolValue] && [preview[@"showLargeMedia"] boolValue];
}

+ (CGSize)largeImageSizeForImage:(UIImage *)image width:(CGFloat)width {
	if (!image || image.size.width < 1)
		return CGSizeZero;
	CGFloat height = image.size.height * (width / image.size.width);
	return CGSizeMake(width, MIN(height, kPreviewLargeMax));
}

+ (CGSize)sizeForPreview:(NSDictionary *)preview
				   image:(UIImage *)image
				maxWidth:(CGFloat)maxWidth
{
	if (![preview[@"url"] length])
		return CGSizeZero;

	CGFloat columnX = kPreviewBar + kPreviewGap;
	CGFloat columnW = maxWidth - columnX;
	BOOL large = [self preview:preview showsLargeMediaWithImage:image];
	BOOL smallThumb = (image != nil && !large);
	CGFloat textW = smallThumb ? columnW - kPreviewThumb - 6 : columnW;
	if (textW < 40)
		textW = columnW;

	CGFloat textH = 0;
	if ([preview[@"siteName"] length])
		textH += 17;
	NSString *title = preview[@"title"];
	if ([title length]){
		CGSize s = [title sizeWithFont:[UIFont boldSystemFontOfSize:14]
					 constrainedToSize:CGSizeMake(textW, 32)
						 lineBreakMode:NSLineBreakByWordWrapping];
		textH += MIN(s.height, 32);
	}
	NSString *body = preview[@"description"];
	if ([body length]){
		CGSize s = [body sizeWithFont:[UIFont systemFontOfSize:14]
					constrainedToSize:CGSizeMake(textW, 32)
						lineBreakMode:NSLineBreakByWordWrapping];
		textH += MIN(s.height, 32);
	}

	CGFloat height = textH;
	if (smallThumb)
		height = MAX(height, kPreviewThumb);
	if (large)
		height += [self largeImageSizeForImage:image width:columnW].height + 5;
	if (height < 1)
		return CGSizeZero;
	if ([preview[@"hasInstantView"] boolValue])
		height += 8 + kInstantHeight;

	CGFloat width = (large || smallThumb) ? maxWidth : columnX + textW;
	return CGSizeMake(width, ceilf(height));
}

- (void)configureWithPreview:(NSDictionary *)preview
					   image:(UIImage *)image
					outgoing:(BOOL)outgoing
					maxWidth:(CGFloat)maxWidth
{
	self.url = preview[@"url"];

	UIColor *accent = outgoing ? TGChatHexColour(0x3A8E26) : TGChatHexColour(0x0E7ACD);
	CGFloat columnX = kPreviewBar + kPreviewGap;
	CGFloat columnW = maxWidth - columnX;
	BOOL large = [TGLinkPreviewView preview:preview showsLargeMediaWithImage:image];
	BOOL smallThumb = (image != nil && !large);
	BOOL mediaAbove = large && [preview[@"showMediaAboveDescription"] boolValue];
	CGFloat textW = smallThumb ? columnW - kPreviewThumb - 6 : columnW;
	if (textW < 40)
		textW = columnW;

	CGFloat y = 0;
	CGSize largeSize = large
			? [TGLinkPreviewView largeImageSizeForImage:image width:columnW]
			: CGSizeZero;

	_thumb.image = image;
	_thumb.hidden = (image == nil);
	if (smallThumb){
		_thumb.frame = CGRectMake(maxWidth - kPreviewThumb, 0, kPreviewThumb, kPreviewThumb);
		_thumb.layer.cornerRadius = 4;
	} else if (large){
		_thumb.layer.cornerRadius = kMediaRadius;
		if (mediaAbove){
			_thumb.frame = CGRectMake(columnX, y, largeSize.width, largeSize.height);
			y += largeSize.height + 5;
		}
	}

	NSString *site = preview[@"siteName"];
	_site.hidden = ![site length];
	if (!_site.hidden){
		_site.text = site;
		_site.textColor = accent;
		_site.frame = CGRectMake(columnX, y, textW, 17);
		y += 17;
	}

	NSString *title = preview[@"title"];
	_title.hidden = ![title length];
	if (!_title.hidden){
		CGSize s = [title sizeWithFont:[UIFont boldSystemFontOfSize:14]
					 constrainedToSize:CGSizeMake(textW, 32)
						 lineBreakMode:NSLineBreakByWordWrapping];
		_title.text = title;
		_title.frame = CGRectMake(columnX, y, textW, MIN(s.height, 32));
		y += MIN(s.height, 32);
	}

	NSString *body = preview[@"description"];
	_text.hidden = ![body length];
	if (!_text.hidden){
		CGSize s = [body sizeWithFont:[UIFont systemFontOfSize:14]
					constrainedToSize:CGSizeMake(textW, 32)
						lineBreakMode:NSLineBreakByWordWrapping];
		_text.text = body;
		_text.frame = CGRectMake(columnX, y, textW, MIN(s.height, 32));
		y += MIN(s.height, 32);
	}

	if (large && !mediaAbove){
		_thumb.frame = CGRectMake(columnX, y, largeSize.width, largeSize.height);
		y += largeSize.height + 5;
	}
	if (smallThumb)
		y = MAX(y, kPreviewThumb);

	_instant.hidden = ![preview[@"hasInstantView"] boolValue];
	if (!_instant.hidden){
		UIImage *plate = [UIImage imageNamed:@"GroupedActionButton.png"];
		UIImage *pressed = [UIImage imageNamed:@"GroupedActionButton_Highlighted.png"];
		if (plate)
			[_instant setBackgroundImage:[plate stretchableImageWithLeftCapWidth:24 topCapHeight:0]
								forState:UIControlStateNormal];
		if (pressed)
			[_instant setBackgroundImage:[pressed stretchableImageWithLeftCapWidth:24 topCapHeight:0]
								forState:UIControlStateHighlighted];
		_instant.frame = CGRectMake(kPreviewBar, y + 8, maxWidth - kPreviewBar, kInstantHeight);
		y += 8 + kInstantHeight;
	}

	_bar.backgroundColor = accent;
	CGFloat barBottom = _instant.hidden ? y : (y - 8 - kInstantHeight);
	_bar.frame = CGRectMake(0, 0, kPreviewBar, MAX(0, barBottom));
}

- (void)blockTapped {
	if (self.onOpen && self.url.length)
		self.onOpen(self.url);
}

- (void)instantTapped {
	if (self.onInstantView && self.url.length)
		self.onInstantView(self.url);
}

@end

#pragma mark - instant view reader

@interface TGInstantViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *url;
@end

@implementation TGInstantViewController {
	UITableView *_table;
	NSArray *_blocks;
	NSMutableArray *_heights;
	NSMutableDictionary *_images;
	NSMutableSet *_imagesRequested;
	UILabel *_placeholder;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor whiteColor];
	_images = [NSMutableDictionary dictionary];
	_imagesRequested = [NSMutableSet set];
	_blocks = @[];
	_heights = [NSMutableArray array];

	NSString *host = [[NSURL URLWithString:(self.url ?: @"")] host] ?: @"Instant View";
	self.title = host;

	_table = [[UITableView alloc] initWithFrame:self.view.bounds
										  style:UITableViewStylePlain];
	_table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_table.separatorStyle = UITableViewCellSeparatorStyleNone;
	_table.backgroundColor = [UIColor whiteColor];
	_table.dataSource = self;
	_table.delegate = self;
	[self.view addSubview:_table];

	_placeholder = [[UILabel alloc] initWithFrame:CGRectMake(0, 120, self.view.bounds.size.width, 20)];
	_placeholder.textAlignment = NSTextAlignmentCenter;
	_placeholder.backgroundColor = [UIColor clearColor];
	_placeholder.textColor = TGChatHexColour(0x999999);
	_placeholder.text = @"Loading...";
	[self.view addSubview:_placeholder];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] instantViewForUrl:self.url completion:^(NSDictionary *view){
		TGInstantViewController *me = weakSelf;
		if (!me)
			return;
		NSArray *blocks = view[@"blocks"];
		if (!blocks.count){
			me->_placeholder.text = @"This article has no Instant View.";
			return;
		}
		[me adoptBlocks:blocks];
	}];
}

- (void)adoptBlocks:(NSArray *)blocks {
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSMutableArray *heights = [NSMutableArray array];
		for (NSDictionary *block in blocks)
			[heights addObject:@([TGInstantViewController heightForBlock:block])];
		dispatch_async(dispatch_get_main_queue(), ^{
			TGInstantViewController *me = weakSelf;
			if (!me)
				return;
			me->_blocks = blocks;
			me->_heights = heights;
			me->_placeholder.hidden = YES;
			[me->_table reloadData];
		});
	});
}

+ (UIFont *)fontForKind:(NSString *)kind {
	if ([kind isEqualToString:@"title"])          return [UIFont boldSystemFontOfSize:19];
	if ([kind isEqualToString:@"subtitle"])       return [UIFont systemFontOfSize:15];
	if ([kind isEqualToString:@"authorDate"])     return [UIFont systemFontOfSize:13];
	if ([kind isEqualToString:@"kicker"])         return [UIFont boldSystemFontOfSize:12];
	if ([kind isEqualToString:@"header"])         return [UIFont boldSystemFontOfSize:17];
	if ([kind isEqualToString:@"sectionHeading"]) return [UIFont boldSystemFontOfSize:17];
	if ([kind isEqualToString:@"subheader"])      return [UIFont boldSystemFontOfSize:15];
	if ([kind isEqualToString:@"preformatted"])   return [UIFont fontWithName:@"Courier" size:13];
	if ([kind isEqualToString:@"blockQuote"] || [kind isEqualToString:@"pullQuote"])
		return [UIFont italicSystemFontOfSize:15];
	if ([kind isEqualToString:@"footer"])         return [UIFont systemFontOfSize:13];
	return [UIFont systemFontOfSize:15];
}

+ (UIColor *)colourForKind:(NSString *)kind {
	if ([kind isEqualToString:@"kicker"])     return TGChatHexColour(0x0E7ACD);
	if ([kind isEqualToString:@"subtitle"])   return TGChatHexColour(0x62768A);
	if ([kind isEqualToString:@"authorDate"]) return TGChatHexColour(0x999999);
	if ([kind isEqualToString:@"footer"])     return TGChatHexColour(0x697487);
	return TGChatHexColour(0x141617);
}

+ (BOOL)kindIsText:(NSString *)kind {
	static NSSet *known = nil;
	if (!known)
		known = [NSSet setWithObjects:@"title", @"subtitle", @"authorDate", @"kicker",
				@"header", @"subheader", @"sectionHeading", @"paragraph", @"preformatted",
				@"footer", @"blockQuote", @"pullQuote", @"list", nil];
	return [known containsObject:(kind ?: @"")];
}

+ (NSString *)textOfBlock:(NSDictionary *)block {
	NSString *kind = block[@"kind"];
	if ([kind isEqualToString:@"list"]){
		NSMutableString *lines = [NSMutableString string];
		for (NSDictionary *item in block[@"items"]){
			NSString *label = item[@"label"] ?: @"•";
			NSMutableString *body = [NSMutableString string];
			for (NSDictionary *nested in item[@"blocks"]){
				NSString *text = nested[@"text"];
				if (text.length)
					[body appendFormat:@"%@ ", text];
			}
			[lines appendFormat:@"%@  %@\n", label, [body stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
		}
		return [lines stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}
	if ([kind isEqualToString:@"blockQuote"] || [kind isEqualToString:@"pullQuote"]){
		NSString *own = block[@"text"];
		if (own.length)
			return own;
		NSMutableString *body = [NSMutableString string];
		for (NSDictionary *nested in block[@"blocks"]){
			NSString *text = nested[@"text"];
			if (text.length)
				[body appendFormat:@"%@\n", text];
		}
		return [body stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}
	return block[@"text"] ?: @"";
}

+ (CGFloat)textWidthForKind:(NSString *)kind {
	CGFloat inset = 15;
	if ([kind isEqualToString:@"blockQuote"] || [kind isEqualToString:@"pullQuote"])
		inset += 10;
	if ([kind isEqualToString:@"list"])
		inset += 20;
	return 320 - inset - 15;
}

+ (CGFloat)heightForBlock:(NSDictionary *)block {
	NSString *kind = block[@"kind"] ?: @"unsupported";

	if ([kind isEqualToString:@"divider"])
		return 17;
	if ([kind isEqualToString:@"anchor"])
		return 0;
	if ([kind isEqualToString:@"photo"] || [kind isEqualToString:@"cover"] ||
		[kind isEqualToString:@"animation"] || [kind isEqualToString:@"video"]){
		CGFloat w = [block[@"width"] floatValue], h = [block[@"height"] floatValue];
		CGFloat picture = (w > 1 && h > 1) ? MIN(320 * (h / w), 320) : 180;
		NSString *caption = block[@"captionText"];
		CGFloat captionH = 0;
		if (caption.length){
			CGSize s = [caption sizeWithFont:[UIFont systemFontOfSize:13]
						   constrainedToSize:CGSizeMake(290, 200)
							   lineBreakMode:NSLineBreakByWordWrapping];
			captionH = s.height + 6;
		}
		return ceilf(picture) + captionH + 11;
	}
	if (![self kindIsText:kind])
		return 66;

	NSString *text = [self textOfBlock:block];
	if (!text.length)
		return 0;
	CGSize s = [text sizeWithFont:[self fontForKind:kind]
				constrainedToSize:CGSizeMake([self textWidthForKind:kind], 20000)
					lineBreakMode:NSLineBreakByWordWrapping];
	CGFloat top = [kind isEqualToString:@"sectionHeading"] ? 8 : 0;
	return ceilf(s.height) + 11 + top;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return _blocks.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= (NSInteger)_heights.count)
		return 0;
	return [_heights[indexPath.row] floatValue];
}

- (void)fetchImageForBlock:(NSDictionary *)block {
	NSNumber *fileId = block[@"photoFileId"];
	if (![fileId isKindOfClass:NSNumber.class] || fileId.integerValue == 0)
		return;
	if (_images[fileId] || [_imagesRequested containsObject:fileId])
		return;
	[_imagesRequested addObject:fileId];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		TGInstantViewController *me = weakSelf;
		if (!me || !path)
			return;
		UIImage *image = nil;
		CGImageSourceRef source = CGImageSourceCreateWithURL(
				(__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
		if (source){
			NSDictionary *options = @{
				(id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
				(id)kCGImageSourceThumbnailMaxPixelSize : @640,
			};
			CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(source, 0,
					(__bridge CFDictionaryRef)options);
			if (thumb){
				image = [UIImage imageWithCGImage:thumb];
				CGImageRelease(thumb);
			}
			CFRelease(source);
		}
		if (!image)
			image = [UIImage imageWithContentsOfFile:path];
		if (!image)
			return;
		me->_images[fileId] = image;
		[me->_table reloadData];
	}];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGInstantBlock";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:reuse];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.backgroundColor = [UIColor whiteColor];

		UILabel *body = [[UILabel alloc] init];
		body.tag = 0x8001;
		body.numberOfLines = 0;
		body.backgroundColor = [UIColor clearColor];
		[cell.contentView addSubview:body];

		UIView *bar = [[UIView alloc] init];
		bar.tag = 0x8002;
		bar.backgroundColor = TGChatHexColour(0x0E7ACD);
		bar.hidden = YES;
		[cell.contentView addSubview:bar];

		UIImageView *picture = [[UIImageView alloc] init];
		picture.tag = 0x8003;
		picture.contentMode = UIViewContentModeScaleAspectFill;
		picture.clipsToBounds = YES;
		picture.hidden = YES;
		[cell.contentView addSubview:picture];

		UILabel *caption = [[UILabel alloc] init];
		caption.tag = 0x8004;
		caption.numberOfLines = 0;
		caption.font = [UIFont systemFontOfSize:13];
		caption.textColor = TGChatHexColour(0x697487);
		caption.backgroundColor = [UIColor clearColor];
		caption.hidden = YES;
		[cell.contentView addSubview:caption];
	}

	UILabel *body = (UILabel *)[cell.contentView viewWithTag:0x8001];
	UIView *bar = [cell.contentView viewWithTag:0x8002];
	UIImageView *picture = (UIImageView *)[cell.contentView viewWithTag:0x8003];
	UILabel *caption = (UILabel *)[cell.contentView viewWithTag:0x8004];
	body.hidden = YES;
	bar.hidden = YES;
	picture.hidden = YES;
	caption.hidden = YES;
	cell.backgroundColor = [UIColor whiteColor];

	if (indexPath.row >= (NSInteger)_blocks.count)
		return cell;
	NSDictionary *block = _blocks[indexPath.row];
	NSString *kind = block[@"kind"] ?: @"unsupported";
	CGFloat height = [_heights[indexPath.row] floatValue];

	if ([kind isEqualToString:@"divider"]){
		bar.hidden = NO;
		bar.backgroundColor = [[TGTheme shared] separatorColour];
		bar.frame = CGRectMake(15, 8, 290, 1);
		return cell;
	}

	if ([kind isEqualToString:@"photo"] || [kind isEqualToString:@"cover"] ||
		[kind isEqualToString:@"animation"] || [kind isEqualToString:@"video"]){
		[self fetchImageForBlock:block];
		NSNumber *fileId = block[@"photoFileId"];
		UIImage *image = [fileId isKindOfClass:NSNumber.class] ? _images[fileId] : nil;
		NSString *text = block[@"captionText"];
		CGFloat captionH = 0;
		if (text.length){
			CGSize s = [text sizeWithFont:[UIFont systemFontOfSize:13]
						constrainedToSize:CGSizeMake(290, 200)
							lineBreakMode:NSLineBreakByWordWrapping];
			captionH = s.height + 6;
		}
		CGFloat pictureH = MAX(0, height - captionH - 11);
		picture.hidden = NO;
		picture.image = image;
		picture.backgroundColor = image ? [UIColor clearColor] : TGChatHexColour(0xEEF1F4);
		picture.frame = CGRectMake(0, 5, 320, pictureH);
		if (text.length){
			caption.hidden = NO;
			caption.text = text;
			caption.frame = CGRectMake(15, 5 + pictureH + 6, 290, captionH - 6);
		}
		return cell;
	}

	if (![TGInstantViewController kindIsText:kind]){
		body.hidden = NO;
		body.font = [UIFont systemFontOfSize:15];
		body.textColor = TGChatHexColour(0x141617);
		NSString *title = block[@"text"];
		body.text = title.length
				? [NSString stringWithFormat:@"%@\nTap to open in Safari", title]
				: @"Tap to open in Safari";
		body.frame = CGRectMake(15, 8, 290, 50);
		cell.backgroundColor = TGChatHexColour(0xEEF1F4);
		return cell;
	}

	NSString *text = [TGInstantViewController textOfBlock:block];
	CGFloat inset = 15;
	if ([kind isEqualToString:@"blockQuote"] || [kind isEqualToString:@"pullQuote"]){
		inset += 10;
		bar.hidden = NO;
		bar.backgroundColor = TGChatHexColour(0x0E7ACD);
		bar.frame = CGRectMake(15, 4, kPreviewBar, MAX(0, height - 11));
	}
	if ([kind isEqualToString:@"list"])
		inset += 20;

	CGFloat top = [kind isEqualToString:@"sectionHeading"] ? 12 : 4;
	body.hidden = NO;
	body.font = [TGInstantViewController fontForKind:kind];
	body.textColor = [TGInstantViewController colourForKind:kind];
	body.text = [kind isEqualToString:@"kicker"] ? text.uppercaseString : text;
	body.backgroundColor = [kind isEqualToString:@"preformatted"]
			? TGChatHexColour(0xEEF1F4) : [UIColor clearColor];
	body.frame = CGRectMake(inset, top, [TGInstantViewController textWidthForKind:kind],
							MAX(0, height - 11 - (top - 4)));
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= (NSInteger)_blocks.count)
		return;
	NSDictionary *block = _blocks[indexPath.row];
	if ([TGInstantViewController kindIsText:block[@"kind"]])
		return;
	NSString *link = block[@"url"] ?: self.url;
	if (link.length)
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:link]];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	[_images removeAllObjects];
	[_imagesRequested removeAllObjects];
	[_table reloadData];
}

@end

#pragma mark - bubble cell

@interface TGMosaicTileView : UIImageView
@property (nonatomic, assign) NSInteger tileIndex;
@property (nonatomic, strong) UIImageView *disc;
@end

@implementation TGMosaicTileView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	self.contentMode = UIViewContentModeScaleAspectFill;
	self.clipsToBounds = YES;
	self.userInteractionEnabled = YES;
	_disc = [[UIImageView alloc] initWithFrame:CGRectZero];
	_disc.hidden = YES;
	_disc.userInteractionEnabled = NO;
	[self addSubview:_disc];
	return self;
}

@end

static const CGFloat kReplySwipeIconSize = 33.0f;
static const CGFloat kReplySwipeIncomingTrigger = 45.0f;
static const CGFloat kReplySwipeOutgoingTrigger = 60.0f;
static const CGFloat kReplySwipeIncomingInset = -24.0f;
static const CGFloat kReplySwipeOutgoingInset = 10.0f;
static const CGFloat kReplySwipeBandRange = 100.0f;
static const CGFloat kReplySwipeBandCoefficient = 0.4f;
static const CGFloat kReplySwipeMaxOffset = 180.0f;
static const CGFloat kReplySwipeDirectionSlop = 2.0f;

static CGFloat TGReplySwipeBandedOffset(CGFloat offset, CGFloat bandingStart) {
	if (offset < bandingStart)
		return offset;
	CGFloat banded = offset - bandingStart;
	CGFloat eased = 1.0f - (1.0f /
			((banded * kReplySwipeBandCoefficient / kReplySwipeBandRange) + 1.0f));
	return bandingStart + eased * kReplySwipeBandRange;
}

static UIImage *TGReplySwipeArrowImage(void) {
	static UIImage *image = nil;
	if (image)
		return image;
	const CGFloat s = 28.0f;
	const CGFloat m = s * 0.18f;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetLineWidth(ctx, 1.8f);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);
	CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1);
	CGContextMoveToPoint(ctx, m + 5, s * 0.30f);
	CGContextAddLineToPoint(ctx, m, s * 0.45f);
	CGContextAddLineToPoint(ctx, m + 5, s * 0.60f);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, m, s * 0.45f);
	CGContextAddLineToPoint(ctx, s - m - 5, s * 0.45f);
	CGContextAddArc(ctx, s - m - 5, s * 0.62f, s * 0.17f, -M_PI_2, 0, 0);
	CGContextStrokePath(ctx);
	image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

@interface TGReplySwipeRecognizer : UIPanGestureRecognizer
@property (nonatomic, copy) BOOL (^shouldBegin)(void);
@end

@implementation TGReplySwipeRecognizer {
	BOOL _validated;
	CGPoint _firstTouch;
}

- (id)initWithTarget:(id)target action:(SEL)action {
	self = [super initWithTarget:target action:action];
	if (!self)
		return nil;
	self.maximumNumberOfTouches = 1;
	return self;
}

- (void)reset {
	[super reset];
	_validated = NO;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	[super touchesBegan:touches withEvent:event];
	if (self.shouldBegin && !self.shouldBegin()){
		self.state = UIGestureRecognizerStateFailed;
		return;
	}
	_firstTouch = [[touches anyObject] locationInView:self.view];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	CGPoint here = [[touches anyObject] locationInView:self.view];
	CGFloat dx = here.x - _firstTouch.x;
	CGFloat dy = here.y - _firstTouch.y;

	if (!_validated){
		if (dx > kReplySwipeDirectionSlop)
			self.state = UIGestureRecognizerStateFailed;
		else if (fabs(dy) > kReplySwipeDirectionSlop && fabs(dy) > fabs(dx) * 2.0f)
			self.state = UIGestureRecognizerStateFailed;
		else if (fabs(dx) > kReplySwipeDirectionSlop && fabs(dy) * 2.0f < fabs(dx))
			_validated = YES;
	}

	if (_validated)
		[super touchesMoved:touches withEvent:event];
}

@end

@interface TGBubbleCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIView *album;
@property (nonatomic, strong) NSMutableArray *albumTiles;
@property (nonatomic, strong) TGEmojiLabel *body;
@property (nonatomic, strong) UIImageView *picture;
@property (nonatomic, strong) UILabel *time;
@property (nonatomic, strong) TGLottieView *lottie;
@property (nonatomic, strong) TGEmojiLabel *icon;   // file glyph / contact initials
@property (nonatomic, strong) UILabel *subtitle;    // size / phone number
@property (nonatomic, strong) TGEmojiLabel *sender; // who wrote it, groups only
@property (nonatomic, strong) UIView  *quoteBar;   // the stripe beside a quote
@property (nonatomic, strong) TGEmojiLabel *quote;      // what is being replied to
@property (nonatomic, strong) UIImageView *ticks;  // delivery marks
@property (nonatomic, strong) UIImageView *senderAvatar;  // groups only
@property (nonatomic, assign) int64_t avatarUserId;
@property (nonatomic, strong) UIImageView *tail;         // the curl off the corner
@property (nonatomic, strong) UIImageView *disc;        // play button on media
@property (nonatomic, strong) UIImageView *wave;        // voice message bars
@property (nonatomic, strong) UILabel *mediaStamp;      // the time over a picture
@property (nonatomic, strong) UILabel *mediaBadge;      // "GIF" or a duration
/// Kept so playback can repaint this one row's bars without a table reload.
@property (nonatomic, assign) int64_t voiceMessageId;
@property (nonatomic, strong) NSData *waveformData;
/// Which poll this cell is drawing, so an option knows what it is voting in.
@property (nonatomic, assign) int64_t pollMessageId;
/// "Forwarded from X" above the content, whatever the content turns out to be.
@property (nonatomic, strong) TGEmojiLabel *forwardLabel;
@property (nonatomic, strong) UIButton *forwardJump;
@property (nonatomic, assign) int64_t forwardChatId;
@property (nonatomic, assign) int64_t forwardMessageId;
@property (nonatomic, assign) int64_t forwardUserId;
@property (nonatomic, copy)   NSString *forwardTitle;
/// Msg_In.png / Msg_Out.png stretched behind the content box.
@property (nonatomic, strong) UIImageView *bubbleBg;
@property (nonatomic, strong) UIImageView *checkView;
@property (nonatomic, strong) UIView *dateBadge;
@property (nonatomic, assign) CGFloat headerHeight;
@property (nonatomic, strong) UIView *dayPlate;
@property (nonatomic, strong) UILabel *dayLabel;
@property (nonatomic, strong) UIView *unreadStrip;
@property (nonatomic, strong) UIView *unreadTopLine;
@property (nonatomic, strong) UIView *unreadBottomLine;
@property (nonatomic, strong) UILabel *unreadLabel;
@property (nonatomic, strong) UIImageView *unreadArrow;
@property (nonatomic, strong) TGReplySwipeRecognizer *replySwipe;
@property (nonatomic, strong) UIView *replyArrow;
@property (nonatomic, strong) UIView *replyArrowPlate;
@end

@implementation TGBubbleCell

- (void)buildCellChrome {
	self.backgroundColor = [UIColor clearColor];
	self.contentView.backgroundColor = [UIColor clearColor];
	self.selectionStyle = UITableViewCellSelectionStyleNone;
}

- (void)buildBubbleViews {
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

	self.album = [[UIView alloc] init];
	self.album.clipsToBounds = YES;
	self.album.hidden = YES;
	self.album.backgroundColor = [UIColor clearColor];
	self.album.layer.cornerRadius = kMediaRadius;
	self.albumTiles = [NSMutableArray array];
	[self.bubble addSubview:self.album];

	self.body = [[TGEmojiLabel alloc] init];
	self.body.numberOfLines = 0;
	self.body.lineBreakMode = NSLineBreakByWordWrapping;
	self.body.font = [UIFont systemFontOfSize:TGMessageBaseFontSize()];
	self.body.backgroundColor = [UIColor clearColor];
	[self.bubble addSubview:self.body];

	self.sender = [[TGEmojiLabel alloc] init];
	self.sender.font = [UIFont boldSystemFontOfSize:13];
	self.sender.backgroundColor = [UIColor clearColor];
	self.sender.hidden = YES;
	[self.bubble addSubview:self.sender];

	self.disc = [[UIImageView alloc] init];
	self.disc.hidden = YES;
	[self.bubble addSubview:self.disc];

	self.wave = [[UIImageView alloc] init];
	self.wave.hidden = YES;
	[self.bubble addSubview:self.wave];
}

- (void)buildContentOverlays {
	self.tail = [[UIImageView alloc] init];
	self.tail.hidden = YES;
	[self.contentView addSubview:self.tail];

	self.senderAvatar = [[UIImageView alloc] init];
	self.senderAvatar.layer.cornerRadius = kAvatarSide * 0.12f;
	self.senderAvatar.clipsToBounds = YES;
	self.senderAvatar.hidden = YES;
	[self.contentView addSubview:self.senderAvatar];

	self.dateBadge = [[UIView alloc] init];
	self.dateBadge.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.55f];
	self.dateBadge.layer.cornerRadius = 10.5f;
	self.dateBadge.hidden = YES;
	[self.contentView addSubview:self.dateBadge];

	self.ticks = [[UIImageView alloc] init];
	self.ticks.hidden = YES;
	[self.contentView addSubview:self.ticks];
}

- (void)buildBubbleDecorations {
	self.quoteBar = [[UIView alloc] init];
	self.quoteBar.hidden = YES;
	[self.bubble addSubview:self.quoteBar];

	self.quote = [[TGEmojiLabel alloc] init];
	self.quote.font = [UIFont systemFontOfSize:13];
	self.quote.numberOfLines = 2;
	self.quote.backgroundColor = [UIColor clearColor];
	self.quote.hidden = YES;
	[self.bubble addSubview:self.quote];

	self.icon = [[TGEmojiLabel alloc] init];
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

	self.forwardLabel = [[TGEmojiLabel alloc] init];
	self.forwardLabel.font = [UIFont systemFontOfSize:13];
	self.forwardLabel.backgroundColor = [UIColor clearColor];
	self.forwardLabel.hidden = YES;
	[self.bubble addSubview:self.forwardLabel];

	self.forwardJump = [UIButton buttonWithType:UIButtonTypeCustom];
	self.forwardJump.backgroundColor = [UIColor clearColor];
	self.forwardJump.adjustsImageWhenHighlighted = YES;
	self.forwardJump.hidden = YES;
	[self.bubble addSubview:self.forwardJump];

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

	self.mediaBadge = [[UILabel alloc] init];
	self.mediaBadge.font = [UIFont boldSystemFontOfSize:11];
	self.mediaBadge.textColor = [UIColor whiteColor];
	self.mediaBadge.textAlignment = NSTextAlignmentCenter;
	self.mediaBadge.layer.cornerRadius = 8;
	self.mediaBadge.clipsToBounds = YES;
	self.mediaBadge.hidden = YES;
	[self.bubble addSubview:self.mediaBadge];
}

- (void)buildTimeViews {
	self.time = [[UILabel alloc] init];
	self.time.font = [UIFont systemFontOfSize:11];
	self.time.backgroundColor = [UIColor clearColor];
	self.time.textAlignment = NSTextAlignmentRight;
	[self.contentView addSubview:self.time];

	self.checkView = [[UIImageView alloc] initWithFrame:CGRectMake(2, 0, 26, 26)];
	self.checkView.hidden = YES;
	[self addSubview:self.checkView];
}

- (void)buildDayPlateViews {
	self.dayPlate = [[UIView alloc] init];
	self.dayPlate.backgroundColor = TGSystemPlateColour();
	self.dayPlate.layer.cornerRadius = kSystemPlateHeight / 2;
	self.dayPlate.userInteractionEnabled = NO;
	self.dayPlate.hidden = YES;
	[self addSubview:self.dayPlate];

	self.dayLabel = [[UILabel alloc] init];
	self.dayLabel.font = [UIFont boldSystemFontOfSize:13];
	self.dayLabel.textColor = [UIColor whiteColor];
	self.dayLabel.textAlignment = NSTextAlignmentCenter;
	self.dayLabel.backgroundColor = [UIColor clearColor];
	self.dayLabel.userInteractionEnabled = NO;
	self.dayLabel.hidden = YES;
	[self addSubview:self.dayLabel];
}

- (void)buildUnreadViews {
	UIImage *dividerArt = TGUnreadDividerImage();
	if (dividerArt){
		UIImageView *plate = [[UIImageView alloc] initWithImage:dividerArt];
		plate.userInteractionEnabled = NO;
		plate.hidden = YES;
		[self addSubview:plate];
		self.unreadStrip = plate;
	} else {
		self.unreadStrip = [[UIView alloc] init];
		self.unreadStrip.userInteractionEnabled = NO;
		self.unreadStrip.hidden = YES;
		self.unreadStrip.clipsToBounds = YES;
		[self addSubview:self.unreadStrip];

		CAGradientLayer *strip = [CAGradientLayer layer];
		strip.colors = [NSArray arrayWithObjects:
				(id)[UIColor colorWithRed:250 / 255.0f green:253 / 255.0f
									 blue:255 / 255.0f alpha:1.0f].CGColor,
				(id)[UIColor colorWithRed:229 / 255.0f green:236 / 255.0f
									 blue:243 / 255.0f alpha:1.0f].CGColor, nil];
		[self.unreadStrip.layer insertSublayer:strip atIndex:0];

		self.unreadTopLine = [[UIView alloc] init];
		self.unreadTopLine.backgroundColor = [UIColor colorWithRed:0 green:35 / 255.0f
															  blue:70 / 255.0f alpha:0.13f];
		[self.unreadStrip addSubview:self.unreadTopLine];

		self.unreadBottomLine = [[UIView alloc] init];
		self.unreadBottomLine.backgroundColor = [UIColor colorWithRed:0 green:43 / 255.0f
																 blue:86 / 255.0f alpha:0.26f];
		[self.unreadStrip addSubview:self.unreadBottomLine];
	}

	self.unreadLabel = [[UILabel alloc] init];
	self.unreadLabel.font = [UIFont boldSystemFontOfSize:13];
	self.unreadLabel.textColor = [UIColor colorWithRed:0x50 / 255.0f green:0x6e / 255.0f
												  blue:0x8d / 255.0f alpha:1.0f];
	self.unreadLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.6f];
	self.unreadLabel.shadowOffset = CGSizeMake(0, 1);
	self.unreadLabel.textAlignment = NSTextAlignmentCenter;
	self.unreadLabel.backgroundColor = [UIColor clearColor];
	self.unreadLabel.userInteractionEnabled = NO;
	self.unreadLabel.hidden = YES;
	[self addSubview:self.unreadLabel];

	self.unreadArrow = [[UIImageView alloc] initWithImage:TGUnreadArrowImage()];
	self.unreadArrow.hidden = YES;
	[self addSubview:self.unreadArrow];
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	[self buildCellChrome];
	[self buildBubbleViews];
	[self buildContentOverlays];
	[self buildBubbleDecorations];
	[self buildTimeViews];
	[self buildDayPlateViews];
	[self buildUnreadViews];

	return self;
}

- (void)setHeaderHeight:(CGFloat)headerHeight {
	if (_headerHeight == headerHeight)
		return;
	_headerHeight = headerHeight;
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGRect content = self.contentView.bounds;
	if (content.origin.y != -_headerHeight){
		content.origin.y = -_headerHeight;
		self.contentView.bounds = content;
	}

	CGFloat width = self.bounds.size.width;

	if (!self.dayLabel.hidden){
		[self.dayLabel sizeToFit];
		CGRect label = self.dayLabel.frame;
		label.origin = CGPointMake(floorf((width - label.size.width) / 2),
								   floorf((kDayRowHeight - label.size.height) / 2) - 1);
		self.dayLabel.frame = label;
		self.dayPlate.frame = CGRectMake(label.origin.x - 10,
										 label.origin.y - 2,
										 label.size.width + 20, kSystemPlateHeight);
		[self bringSubviewToFront:self.dayPlate];
		[self bringSubviewToFront:self.dayLabel];
	}

	if (!self.unreadStrip.hidden){
		CGFloat top = _headerHeight - kUnreadRowHeight;
		CGFloat stripH = TGUnreadDividerImage()
				? TGUnreadDividerImage().size.height : 27.0f;
		self.unreadStrip.frame = CGRectMake(0, top + 3, width, stripH);
		if (self.unreadTopLine){
			CALayer *strip = [self.unreadStrip.layer.sublayers count]
					? [self.unreadStrip.layer.sublayers objectAtIndex:0] : nil;
			strip.frame = self.unreadStrip.bounds;
			self.unreadTopLine.frame = CGRectMake(0, 0, width, kRetinaPixel);
			self.unreadBottomLine.frame =
					CGRectMake(0, stripH - kRetinaPixel, width, kRetinaPixel);
		}

		[self.unreadLabel sizeToFit];
		CGRect label = self.unreadLabel.frame;
		label.origin = CGPointMake(floorf((width - label.size.width) / 2),
								   top + floorf((kUnreadRowHeight - label.size.height) / 2) - 1);
		self.unreadLabel.frame = label;

		CGRect arrow = self.unreadArrow.frame;
		arrow.origin = CGPointMake(width - arrow.size.width - 7, top + 13 + kRetinaPixel);
		self.unreadArrow.frame = arrow;

		[self bringSubviewToFront:self.unreadStrip];
		[self bringSubviewToFront:self.unreadLabel];
		[self bringSubviewToFront:self.unreadArrow];
	}
}

@end

#pragma mark - controller

#pragma mark - message info

@interface TGMessageInfoViewController : UITableViewController <UIAlertViewDelegate,
		UIActionSheetDelegate, UIImagePickerControllerDelegate,
		UINavigationControllerDelegate>
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;
@property (nonatomic, strong) NSDictionary *message;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, assign) BOOL canResend;
@property (nonatomic, copy) void (^onOpenChat)(int64_t chatId, NSString *title);
@property (nonatomic, copy) NSString *formattedBody;
@property (nonatomic, assign) int64_t threadChatId;
@property (nonatomic, copy) NSString *replaceKind;
@end

static const NSInteger kInfoCaptionAlertTag = 71;

@implementation TGMessageInfoViewController {
	NSMutableArray *_order;
	NSMutableDictionary *_rows;
	NSMutableArray *_visible;
}

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Message Info";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	_order = [NSMutableArray arrayWithObjects:@"Details", @"Text", @"Seen By",
			@"Voice", @"Poll", @"Story", @"Actions", nil];
	_rows = [NSMutableDictionary dictionary];
	_visible = [NSMutableArray array];
	for (NSString *name in _order)
		_rows[name] = [NSMutableArray array];

	[self loadEverything];
}

- (void)addRow:(NSString *)title
		detail:(NSString *)detail
		action:(NSString *)action
			to:(NSString *)section {
	NSMutableArray *list = _rows[section];
	if (!list)
		return;
	NSMutableDictionary *row = [NSMutableDictionary dictionary];
	row[@"title"] = title.length ? title : @" ";
	if (detail.length)
		row[@"detail"] = detail;
	if (action.length)
		row[@"action"] = action;
	[list addObject:row];
	[self refresh];
}

- (void)clearSection:(NSString *)section {
	[_rows[section] removeAllObjects];
}

- (void)refresh {
	[_visible removeAllObjects];
	for (NSString *name in _order)
		if ([_rows[name] count])
			[_visible addObject:name];
	[self.tableView reloadData];
}

- (NSString *)sizeText:(long long)bytes {
	if (bytes <= 0)
		return nil;
	if (bytes < 1024)
		return [NSString stringWithFormat:@"%lld B", bytes];
	if (bytes < 1024 * 1024)
		return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
	return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
}

- (NSString *)stringOf:(id)value {
	return [value isKindOfClass:NSString.class] ? value : nil;
}

- (NSTimeInterval)messageDate {
	id date = self.message[@"date"];
	return [date isKindOfClass:NSNumber.class] ? [date doubleValue] : 0;
}

- (void)loadEverything {
	int64_t messageId = self.messageId;
	int64_t chatId = self.chatId;
	NSString *kind = [self stringOf:self.message[@"kind"]] ?: @"message";
	BOOL outgoing = [self.message[@"outgoing"] boolValue];
	__weak typeof(self) weakSelf = self;

	[self addRow:@"Type" detail:kind action:nil to:@"Details"];

	NSTimeInterval date = [self messageDate];
	if (date > 0)
		[self addRow:@"Sent"
			  detail:[NSDateFormatter localizedStringFromDate:
					  [NSDate dateWithTimeIntervalSince1970:date]
										  dateStyle:NSDateFormatterShortStyle
										  timeStyle:NSDateFormatterShortStyle]
			  action:nil to:@"Details"];

	[[TGClient shared] mediaInfoForMessage:messageId inChat:chatId
								completion:^(NSDictionary *info){
		TGMessageInfoViewController *me = weakSelf;
		if (!me || ![info isKindOfClass:NSDictionary.class])
			return;
		NSString *name = [me stringOf:info[@"fileName"]];
		if (name.length)
			[me addRow:@"File" detail:name action:nil to:@"Details"];
		NSString *size = [me sizeText:[info[@"size"] longLongValue]];
		if (size)
			[me addRow:@"Size" detail:size action:nil to:@"Details"];
		NSInteger seconds = [info[@"duration"] integerValue];
		if (seconds > 0)
			[me addRow:@"Length"
				detail:[NSString stringWithFormat:@"%ld:%02ld",
						(long)(seconds / 60), (long)(seconds % 60)]
				action:nil to:@"Details"];
		NSInteger width = [info[@"width"] integerValue];
		NSInteger height = [info[@"height"] integerValue];
		if (width > 0 && height > 0)
			[me addRow:@"Dimensions"
				detail:[NSString stringWithFormat:@"%ld x %ld", (long)width, (long)height]
				action:nil to:@"Details"];
		NSString *caption = [me stringOf:info[@"caption"]];
		if (caption.length)
			[me addRow:@"Caption" detail:caption action:nil to:@"Details"];
		if ([info[@"isSecret"] boolValue])
			[me addRow:@"Self-destructing" detail:@"Yes" action:nil to:@"Details"];

		if (!outgoing)
			return;
		[me addRow:@"Edit Caption" detail:nil action:@"editCaption" to:@"Actions"];
		NSString *contentKind = [me stringOf:info[@"kind"]] ?: kind;
		if ([contentKind isEqualToString:@"messagePhoto"])
			[me addRow:@"Replace Photo" detail:nil action:@"replacePhoto" to:@"Actions"];
		else if ([contentKind isEqualToString:@"messageVideo"])
			[me addRow:@"Replace Video" detail:nil action:@"replaceVideo" to:@"Actions"];
	}];

	[[TGClient shared] formattedTextForMessage:messageId inChat:chatId
									completion:^(NSString *text, NSArray *entities){
		TGMessageInfoViewController *me = weakSelf;
		if (!me || !text.length)
			return;
		me.formattedBody = text;
		[me addRow:@"Copy Text"
			detail:[NSString stringWithFormat:@"%lu formatted run%@",
					(unsigned long)entities.count, (entities.count == 1 ? @"" : @"s")]
			action:@"copyText" to:@"Text"];
	}];

	if (outgoing && !self.isGroup)
		[[TGClient shared] readDateOfMessage:messageId inChat:chatId
								  completion:^(NSString *status, NSTimeInterval when){
			TGMessageInfoViewController *me = weakSelf;
			if (!me)
				return;
			NSString *detail = @"Not read yet";
			if ([status isEqualToString:@"read"] && when > 0)
				detail = [NSDateFormatter localizedStringFromDate:
						[NSDate dateWithTimeIntervalSince1970:when]
											   dateStyle:NSDateFormatterShortStyle
											   timeStyle:NSDateFormatterShortStyle];
			else if ([status isEqualToString:@"tooOld"])
				detail = @"Too old to tell";
			else if ([status isEqualToString:@"theirPrivacy"] ||
					 [status isEqualToString:@"myPrivacy"])
				detail = @"Hidden by privacy";
			[me addRow:@"Read" detail:detail action:nil to:@"Details"];
		}];

	if (self.isGroup)
		[[TGClient shared] viewersOfMessage:messageId inChat:chatId
								 completion:^(NSArray *viewers){
			TGMessageInfoViewController *me = weakSelf;
			if (!me || !viewers.count)
				return;
			NSUInteger shown = 0;
			for (NSDictionary *viewer in viewers){
				if (shown++ >= 25)
					break;
				NSTimeInterval seen = [viewer[@"date"] doubleValue];
				NSString *when = (seen > 0)
						? [NSDateFormatter localizedStringFromDate:
								[NSDate dateWithTimeIntervalSince1970:seen]
												   dateStyle:NSDateFormatterNoStyle
												   timeStyle:NSDateFormatterShortStyle]
						: nil;
				[me addRow:([me stringOf:viewer[@"name"]] ?: @"Someone")
					detail:when action:nil to:@"Seen By"];
			}
		}];

	[[TGClient shared] threadForMessage:messageId inChat:chatId
							 completion:^(NSDictionary *thread){
		TGMessageInfoViewController *me = weakSelf;
		if (!me || ![thread isKindOfClass:NSDictionary.class])
			return;
		me.threadChatId = [thread[@"chatId"] longLongValue];
		[me addRow:@"Comments"
			detail:[NSString stringWithFormat:@"%ld, %ld unread",
					(long)[thread[@"replies"] integerValue],
					(long)[thread[@"unread"] integerValue]]
			action:(me.threadChatId ? @"openThread" : nil) to:@"Details"];
	}];

	if ([kind isEqualToString:@"messageVoiceNote"] ||
		[kind isEqualToString:@"messageVideoNote"])
		[self loadTranscript];

	NSArray *options = [self.message[@"pollOptions"] isKindOfClass:NSArray.class]
			? self.message[@"pollOptions"] : nil;
	for (NSUInteger i = 0; i < options.count; i++){
		NSDictionary *option = options[i];
		id text = option[@"text"];
		NSString *label = [text isKindOfClass:NSDictionary.class]
				? [self stringOf:text[@"text"]] : [self stringOf:text];
		[self addRow:(label ?: @"Option")
			  detail:[NSString stringWithFormat:@"%ld%%",
					  (long)[option[@"vote_percentage"] integerValue]]
			  action:[NSString stringWithFormat:@"voters:%lu", (unsigned long)i]
				  to:@"Poll"];
	}
	if (options.count && outgoing && ![self.message[@"pollClosed"] boolValue])
		[self addRow:@"Stop Poll" detail:nil action:@"stopPoll" to:@"Poll"];

	if ([kind isEqualToString:@"messageStory"])
		[[TGClient shared] storyForMessage:messageId inChat:chatId
								completion:^(NSDictionary *story){
			TGMessageInfoViewController *me = weakSelf;
			if (!me)
				return;
			if (![story isKindOfClass:NSDictionary.class]){
				[me addRow:@"Story" detail:@"No longer available" action:nil to:@"Story"];
				return;
			}
			[me addRow:@"Kind"
				detail:([story[@"isVideo"] boolValue] ? @"Video" : @"Photo")
				action:nil to:@"Story"];
			NSTimeInterval posted = [story[@"date"] doubleValue];
			if (posted > 0)
				[me addRow:@"Posted"
					detail:[NSDateFormatter localizedStringFromDate:
							[NSDate dateWithTimeIntervalSince1970:posted]
											   dateStyle:NSDateFormatterShortStyle
											   timeStyle:NSDateFormatterShortStyle]
					action:nil to:@"Story"];
			NSString *caption = [me stringOf:story[@"caption"]];
			if (caption.length)
				[me addRow:@"Caption" detail:caption action:nil to:@"Story"];
		}];

	if (self.canResend)
		[self addRow:@"Try Again" detail:nil action:@"resend" to:@"Actions"];
	[self addRow:@"Copy Embed Code" detail:nil action:@"embed" to:@"Actions"];
	[self addRow:@"Delete This Day For Me" detail:nil action:@"deleteDay" to:@"Actions"];
}

- (void)loadTranscript {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] speechTranscriptForMessage:self.messageId inChat:self.chatId
									   completion:^(NSDictionary *transcript){
		TGMessageInfoViewController *me = weakSelf;
		if (!me)
			return;
		[me clearSection:@"Voice"];
		if (![transcript isKindOfClass:NSDictionary.class]){
			[me addRow:@"Transcript" detail:@"None yet" action:nil to:@"Voice"];
			return;
		}
		NSString *state = [me stringOf:transcript[@"state"]] ?: @"";
		NSString *text = [me stringOf:transcript[@"text"]] ?: @"";
		if ([state isEqualToString:@"error"]){
			[me addRow:@"Transcript"
				detail:([me stringOf:transcript[@"error"]] ?: @"Failed")
				action:nil to:@"Voice"];
			return;
		}
		if ([state isEqualToString:@"pending"]){
			[me addRow:@"Transcript" detail:@"In progress" action:@"reloadTranscript"
					to:@"Voice"];
			return;
		}
		[me addRow:(text.length ? text : @"Empty") detail:nil action:nil to:@"Voice"];
		if (!text.length)
			return;
		[me addRow:@"Transcript Is Good" detail:nil action:@"rateGood" to:@"Voice"];
		[me addRow:@"Transcript Is Bad" detail:nil action:@"rateBad" to:@"Voice"];
	}];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)_visible.count;
}

- (NSString *)tableView:(UITableView *)tableView
titleForHeaderInSection:(NSInteger)section {
	return _visible[section];
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[_rows[_visible[section]] count];
}

- (NSDictionary *)rowAt:(NSIndexPath *)path {
	NSArray *list = _rows[_visible[path.section]];
	return (path.row < (NSInteger)list.count) ? list[path.row] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"info";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:identifier];
	NSDictionary *row = [self rowAt:indexPath];
	cell.textLabel.text = row[@"title"];
	cell.detailTextLabel.text = row[@"detail"];
	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.textLabel.numberOfLines = 0;
	NSString *action = row[@"action"];
	cell.selectionStyle = action.length ? UITableViewCellSelectionStyleBlue
										: UITableViewCellSelectionStyleNone;
	cell.accessoryType = [action isEqualToString:@"openThread"]
			? UITableViewCellAccessoryDisclosureIndicator
			: UITableViewCellAccessoryNone;
	cell.textLabel.textColor = [action isEqualToString:@"deleteDay"]
			? [UIColor colorWithRed:0.78f green:0.16f blue:0.13f alpha:1.0f]
			: [UIColor blackColor];
	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView
heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *row = [self rowAt:indexPath];
	if (row[@"detail"])
		return 44;
	CGSize size = [(row[@"title"] ?: @"") sizeWithFont:[UIFont systemFontOfSize:15]
									 constrainedToSize:CGSizeMake(280, 400)
										 lineBreakMode:NSLineBreakByWordWrapping];
	return MAX(44, size.height + 20);
}

- (void)tableView:(UITableView *)tableView
		didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString *action = [self rowAt:indexPath][@"action"];
	if (!action.length)
		return;

	if ([action isEqualToString:@"copyText"]){
		[UIPasteboard generalPasteboard].string = self.formattedBody ?: @"";
		[self say:@"Copied" message:@"The text is on the clipboard."];
		return;
	}
	if ([action isEqualToString:@"openThread"]){
		if (self.onOpenChat && self.threadChatId)
			self.onOpenChat(self.threadChatId, @"Comments");
		return;
	}
	if ([action isEqualToString:@"reloadTranscript"]){
		[self loadTranscript];
		return;
	}
	if ([action isEqualToString:@"rateGood"] || [action isEqualToString:@"rateBad"]){
		[[TGClient shared] rateSpeechRecognitionForMessage:self.messageId
													inChat:self.chatId
													  good:[action isEqualToString:@"rateGood"]];
		[self say:@"" message:@"Thank you for the feedback."];
		return;
	}
	if ([action hasPrefix:@"voters:"]){
		[self showVotersForOption:[[action substringFromIndex:7] integerValue]];
		return;
	}
	if ([action isEqualToString:@"stopPoll"]){
		[[TGClient shared] stopPoll:self.messageId inChat:self.chatId];
		[self say:@"" message:@"The poll takes no more votes."];
		return;
	}
	if ([action isEqualToString:@"editCaption"]){
		UIAlertView *ask = [[TGAlertView alloc] initWithTitle:@"Caption"
													  message:nil
													 delegate:self
											cancelButtonTitle:@"Cancel"
											otherButtonTitles:@"Save", nil];
		if ([ask respondsToSelector:@selector(setAlertViewStyle:)])
			ask.alertViewStyle = UIAlertViewStylePlainTextInput;
		ask.tag = kInfoCaptionAlertTag;
		[ask show];
		return;
	}
	if ([action isEqualToString:@"replacePhoto"] || [action isEqualToString:@"replaceVideo"]){
		[self pickReplacementFor:action];
		return;
	}
	if ([action isEqualToString:@"resend"]){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] resendMessages:@[@(self.messageId)] inChat:self.chatId
							   completion:^(NSArray *messages){
			[weakSelf say:@"" message:(messages.count ? @"Sending again."
													  : @"This message could not be sent again.")];
		}];
		return;
	}
	if ([action isEqualToString:@"embed"]){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] embeddingCodeForMessage:self.messageId inChat:self.chatId
										  forAlbum:NO completion:^(NSString *code){
			TGMessageInfoViewController *me = weakSelf;
			if (!me)
				return;
			if (!code.length){
				[me say:@"" message:@"This message cannot be embedded."];
				return;
			}
			[UIPasteboard generalPasteboard].string = code;
			[me say:@"Copied" message:@"The embed code is on the clipboard."];
		}];
		return;
	}
	if ([action isEqualToString:@"deleteDay"]){
		UIActionSheet *sheet = [[UIActionSheet alloc]
				initWithTitle:@"Delete every message of this day from this device?"
					 delegate:self
			cancelButtonTitle:@"Cancel"
	   destructiveButtonTitle:@"Delete"
			otherButtonTitles:nil];
		[sheet showInView:self.view];
	}
}

- (void)showVotersForOption:(NSInteger)index {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] votersForPollOption:index ofMessage:self.messageId
									inChat:self.chatId limit:20
								completion:^(NSArray *voters, NSInteger total){
		TGMessageInfoViewController *me = weakSelf;
		if (!me)
			return;
		if (!voters.count){
			[me say:@"" message:(total > 0 ? @"This poll does not reveal its voters."
										   : @"Nobody picked this option.")];
			return;
		}
		NSMutableArray *names = [NSMutableArray array];
		for (NSDictionary *voter in voters)
			[names addObject:([me stringOf:voter[@"name"]] ?: @"Someone")];
		[me say:[NSString stringWithFormat:@"%ld votes", (long)total]
		  message:[names componentsJoinedByString:@"\n"]];
	}];
}

- (void)pickReplacementFor:(NSString *)action {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary]){
		[self say:@"" message:@"There is no photo library on this device."];
		return;
	}
	self.replaceKind = action;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.mediaTypes = [action isEqualToString:@"replaceVideo"]
			? @[(NSString *)kUTTypeMovie] : @[(NSString *)kUTTypeImage];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	NSString *action = self.replaceKind;
	self.replaceKind = nil;
	__weak typeof(self) weakSelf = self;

	if ([action isEqualToString:@"replaceVideo"]){
		NSURL *movie = info[UIImagePickerControllerMediaURL];
		if (!movie.path.length)
			return;
		[[TGClient shared] replaceVideoInMessage:self.messageId inChat:self.chatId
											path:movie.path caption:nil
									  completion:^(BOOL ok){
			[weakSelf say:@"" message:(ok ? @"The video has been replaced."
										  : @"The video could not be replaced.")];
		}];
		return;
	}

	UIImage *image = info[UIImagePickerControllerOriginalImage];
	NSData *jpeg = image ? UIImageJPEGRepresentation(image, 0.85f) : nil;
	if (!jpeg.length)
		return;
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"replace-%.0f.jpg",
					[[NSDate date] timeIntervalSince1970] * 1000]];
	if (![jpeg writeToFile:path atomically:YES])
		return;
	[[TGClient shared] replacePhotoInMessage:self.messageId inChat:self.chatId
										path:path caption:nil
								  completion:^(BOOL ok){
		[weakSelf say:@"" message:(ok ? @"The photo has been replaced."
									  : @"The photo could not be replaced.")];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	self.replaceKind = nil;
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (alertView.tag != kInfoCaptionAlertTag || buttonIndex == alertView.cancelButtonIndex)
		return;
	NSString *caption = @"";
	if ([alertView respondsToSelector:@selector(textFieldAtIndex:)])
		caption = [alertView textFieldAtIndex:0].text ?: @"";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] editCaptionOfMessage:self.messageId inChat:self.chatId
									caption:caption completion:^(BOOL ok){
		[weakSelf say:@"" message:(ok ? @"The caption has been changed."
									  : @"The caption could not be changed.")];
	}];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index != sheet.destructiveButtonIndex)
		return;
	NSTimeInterval date = [self messageDate];
	if (date <= 0){
		[self say:@"" message:@"This message has no date to work from."];
		return;
	}
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *parts = [calendar components:
			(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit)
										  fromDate:[NSDate dateWithTimeIntervalSince1970:date]];
	NSTimeInterval start = [[calendar dateFromComponents:parts] timeIntervalSince1970];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] deleteMessagesInChat:self.chatId
								   fromDate:start
									 toDate:start + 86399
								forEveryone:NO
								 completion:^(BOOL ok){
		TGMessageInfoViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[me say:@"" message:@"These messages could not be deleted."];
			return;
		}
		[me.navigationController popViewControllerAnimated:YES];
	}];
}

- (void)say:(NSString *)title message:(NSString *)message {
	[[[UIAlertView alloc] initWithTitle:(title ?: @"")
								message:message
							   delegate:nil
					  cancelButtonTitle:@"OK"
					  otherButtonTitles:nil] show];
}

@end

#pragma mark - reactions detail

static const NSInteger kReactorSheetTag      = 81;
static const NSInteger kQuickReactionSheetTag = 82;
static const NSInteger kChatReactionsSheetTag = 83;
static const NSInteger kClearMineAlertTag    = 84;
static const NSInteger kClearRecentAlertTag  = 85;

@interface TGMessageReactionsViewController : UITableViewController <UIActionSheetDelegate,
		UIAlertViewDelegate>
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;
@property (nonatomic, strong) NSDictionary *message;
@end

@implementation TGMessageReactionsViewController {
	NSMutableArray *_sections;
	NSArray *_chips;
	NSMutableArray *_reactors;
	NSString *_reactorsOffset;
	NSInteger _reactorsTotal;
	NSArray *_paidReactors;
	NSMutableDictionary *_reactionTitles;
	NSMutableDictionary *_reactionIcons;
	NSArray *_chosenEmoji;
	NSInteger _usedCount;
	NSInteger _maxCount;
	BOOL _canAddMore;
	NSString *_allowedReason;
	NSArray *_allowedEmoji;
	NSArray *_chatEmoji;
	BOOL _chatAllowsAll;
	NSInteger _chatMax;
	BOOL _canDelete;
	BOOL _canReport;
	int64_t _actionSenderId;
	NSString *_actionSenderName;
}

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Reactions";
	_sections = [NSMutableArray array];
	_reactors = [NSMutableArray array];
	_reactionTitles = [NSMutableDictionary dictionary];
	_reactionIcons = [NSMutableDictionary dictionary];
	_maxCount = 1;
	_canAddMore = YES;
	_paidReactors = self.message
			? [TGClient paidReactorsFromMessage:self.message] : @[];
	[self loadEverything];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setReactionWatchInterval:5];
	[[TGClient shared] watchReactionsForMessage:self.messageId
										 inChat:self.chatId
									   onChange:^(NSArray *chips){
		[weakSelf adoptChips:chips];
	}];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[[TGClient shared] unwatchReactionsForMessage:self.messageId inChat:self.chatId];
}

- (void)dealloc {
	[[TGClient shared] unwatchReactionsForMessage:self.messageId inChat:self.chatId];
}

- (void)adoptChips:(NSArray *)chips {
	_chips = chips ?: @[];
	[self fetchReactionDecoration];
	[self rebuild];
}

- (void)loadEverything {
	__weak typeof(self) weakSelf = self;

	[[TGClient shared] reactionChipsForMessage:self.messageId
										inChat:self.chatId
									completion:^(NSArray *chips){
		[weakSelf adoptChips:chips];
	}];

	[[TGClient shared] reactionUsageForMessage:self.messageId
										inChat:self.chatId
									completion:^(NSArray *chosenEmoji,
												 NSInteger usedCount,
												 NSInteger maxCount,
												 BOOL canAddMore){
		TGMessageReactionsViewController *me = weakSelf;
		if (!me)
			return;
		me->_chosenEmoji = chosenEmoji ?: @[];
		me->_usedCount = usedCount;
		me->_maxCount = maxCount;
		me->_canAddMore = canAddMore;
		[me rebuild];
	}];

	[[TGClient shared] availableReactionsForMessage:self.messageId
											 inChat:self.chatId
										 completion:^(NSDictionary *info){
		TGMessageReactionsViewController *me = weakSelf;
		if (!me)
			return;
		me->_allowedEmoji = info[@"allEmoji"];
		me->_allowedReason = info[@"reason"];
		[me rebuild];
	}];

	[[TGClient shared] availableReactionsInChat:self.chatId
									 completion:^(NSArray *emojis,
												  BOOL allowsAll,
												  NSInteger maxCount){
		TGMessageReactionsViewController *me = weakSelf;
		if (!me)
			return;
		me->_chatEmoji = emojis ?: @[];
		me->_chatAllowsAll = allowsAll;
		me->_chatMax = maxCount;
		[me rebuild];
	}];

	[[TGClient shared] reactionPermissionsForMessage:self.messageId
											  inChat:self.chatId
										  completion:^(BOOL canDelete, BOOL canReport){
		TGMessageReactionsViewController *me = weakSelf;
		if (!me)
			return;
		me->_canDelete = canDelete;
		me->_canReport = canReport;
		[me rebuild];
	}];

	[self loadReactorsFromOffset:nil];
}

- (void)loadReactorsFromOffset:(NSString *)offset {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] addedReactionsForMessage:self.messageId
										 inChat:self.chatId
										  emoji:nil
										 offset:offset
										  limit:40
									 completion:^(NSArray *reactors,
												  NSString *nextOffset,
												  NSInteger totalCount){
		TGMessageReactionsViewController *me = weakSelf;
		if (!me)
			return;
		if (!offset.length)
			[me->_reactors removeAllObjects];
		[me->_reactors addObjectsFromArray:(reactors ?: @[])];
		me->_reactorsOffset = nextOffset;
		me->_reactorsTotal = totalCount;
		[me rebuild];
	}];
}

- (void)fetchReactionDecoration {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *chip in _chips){
		NSString *emoji = chip[@"emoji"];
		if (![emoji isKindOfClass:NSString.class] || !emoji.length)
			continue;
		if (_reactionTitles[emoji])
			continue;
		_reactionTitles[emoji] = emoji;

		[[TGClient shared] emojiReactionInfo:emoji completion:^(NSDictionary *info){
			TGMessageReactionsViewController *me = weakSelf;
			if (!me || !info)
				return;
			NSString *title = info[@"title"];
			if ([title isKindOfClass:NSString.class] && title.length)
				me->_reactionTitles[emoji] = title;
			[me rebuild];
		}];

		[[TGClient shared] reactionIconPathForEmoji:emoji completion:^(NSString *path){
			if (!path.length)
				return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
				UIImage *raw = [UIImage convertFromWebP:path compressedData:NULL error:NULL];
				if (!raw)
					return;
				CGFloat side = 29.0f;
				CGFloat scale = MIN(side / MAX(raw.size.width, 1.0f),
									side / MAX(raw.size.height, 1.0f));
				CGSize target = CGSizeMake(floorf(raw.size.width * scale),
										   floorf(raw.size.height * scale));
				if (target.width < 1 || target.height < 1)
					return;
				UIGraphicsBeginImageContextWithOptions(target, NO, 0.0f);
				[raw drawInRect:CGRectMake(0, 0, target.width, target.height)];
				UIImage *icon = UIGraphicsGetImageFromCurrentImageContext();
				UIGraphicsEndImageContext();
				raw = nil;
				if (!icon)
					return;
				dispatch_async(dispatch_get_main_queue(), ^{
					TGMessageReactionsViewController *me = weakSelf;
					if (!me)
						return;
					me->_reactionIcons[emoji] = icon;
					[me rebuild];
				});
			});
		}];
	}
}

- (NSDictionary *)row:(NSString *)title
			   detail:(NSString *)detail
			   action:(NSString *)action
				emoji:(NSString *)emoji {
	NSMutableDictionary *row = [NSMutableDictionary dictionary];
	row[@"title"] = title ?: @"";
	if (detail.length)
		row[@"detail"] = detail;
	if (action.length)
		row[@"action"] = action;
	if (emoji.length)
		row[@"emoji"] = emoji;
	return row;
}

- (void)addSection:(NSString *)title rows:(NSArray *)rows {
	if (!rows.count)
		return;
	[_sections addObject:@{ @"title" : (title ?: @""), @"rows" : rows }];
}

- (void)rebuild {
	[_sections removeAllObjects];

	NSMutableArray *chipRows = [NSMutableArray array];
	for (NSDictionary *chip in _chips){
		NSString *emoji = chip[@"emoji"];
		if (![emoji isKindOfClass:NSString.class] || !emoji.length)
			continue;
		NSString *name = _reactionTitles[emoji] ?: emoji;
		NSString *detail = [NSString stringWithFormat:@"%@%ld",
				([chip[@"chosen"] boolValue] ? @"✓ " : @""),
				(long)[chip[@"count"] integerValue]];
		[chipRows addObject:[self row:[NSString stringWithFormat:@"%@  %@", emoji, name]
							   detail:detail
							   action:([chip[@"custom"] boolValue] ? nil : @"toggle")
								emoji:emoji]];
	}
	[self addSection:@"ON THIS MESSAGE" rows:chipRows];

	NSMutableArray *mine = [NSMutableArray array];
	[mine addObject:[self row:@"Your Reactions"
					   detail:[NSString stringWithFormat:@"%ld of %ld",
							   (long)_usedCount, (long)MAX(1, _maxCount)]
					   action:nil
						emoji:nil]];
	[mine addObject:[self row:@"Reacting Here"
					   detail:(_allowedReason.length ? _allowedReason
							   : (_canAddMore ? @"Allowed" : @"Limit reached"))
					   action:nil
						emoji:nil]];
	if (_chosenEmoji.count)
		[mine addObject:[self row:@"Clear My Reactions" detail:nil
						   action:@"clearMine" emoji:nil]];
	[self addSection:@"YOU" rows:mine];

	NSMutableArray *paid = [NSMutableArray array];
	for (NSDictionary *reactor in _paidReactors){
		NSString *name = reactor[@"name"];
		if (![name isKindOfClass:NSString.class] || !name.length)
			name = [reactor[@"isAnonymous"] boolValue] ? @"Anonymous" : @"Someone";
		[paid addObject:[self row:name
						   detail:[NSString stringWithFormat:@"%ld",
								   (long)[reactor[@"stars"] integerValue]]
						   action:nil
							emoji:nil]];
	}
	[self addSection:@"STARS" rows:paid];

	NSMutableArray *who = [NSMutableArray array];
	for (NSDictionary *reactor in _reactors){
		NSString *name = reactor[@"name"];
		if (![name isKindOfClass:NSString.class] || !name.length)
			name = [[TGClient shared] nameForUserId:
					[reactor[@"senderId"] longLongValue]] ?: @"Someone";
		NSMutableDictionary *entry = [[self row:name
										 detail:(reactor[@"emoji"] ?: @"")
										 action:@"reactor"
										  emoji:nil] mutableCopy];
		entry[@"senderId"] = reactor[@"senderId"] ?: @0;
		[who addObject:entry];
	}
	if (_reactorsOffset.length)
		[who addObject:[self row:@"Show More" detail:nil action:@"moreReactors" emoji:nil]];
	[self addSection:(_reactorsTotal > 0
			? [NSString stringWithFormat:@"WHO REACTED (%ld)", (long)_reactorsTotal]
			: @"WHO REACTED") rows:who];

	NSMutableArray *chat = [NSMutableArray array];
	NSString *chatDetail = _chatAllowsAll
			? @"All"
			: (_chatEmoji.count
					? [NSString stringWithFormat:@"%lu allowed", (unsigned long)_chatEmoji.count]
					: @"Off");
	[chat addObject:[self row:@"Allowed in This Chat" detail:chatDetail action:nil emoji:nil]];
	if (_canDelete)
		[chat addObject:[self row:@"Change What Is Allowed" detail:nil
						   action:@"chatReactions" emoji:nil]];
	[chat addObject:[self row:@"Quick Reaction"
					   detail:[[TGClient shared] quickReactionEmoji]
					   action:@"quick" emoji:nil]];
	[chat addObject:[self row:@"Clear Recently Used" detail:nil
					   action:@"clearRecent" emoji:nil]];
	[self addSection:@"REACTIONS" rows:chat];

	[self.tableView reloadData];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)_sections.count;
}

- (NSString *)tableView:(UITableView *)tableView
		titleForHeaderInSection:(NSInteger)section {
	return _sections[section][@"title"];
}

- (NSInteger)tableView:(UITableView *)tableView
		numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[_sections[section][@"rows"] count];
}

- (NSDictionary *)rowAt:(NSIndexPath *)path {
	if (path.section >= (NSInteger)_sections.count)
		return nil;
	NSArray *rows = _sections[path.section][@"rows"];
	return (path.row < (NSInteger)rows.count) ? rows[path.row] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"reaction"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"reaction"];
	NSDictionary *row = [self rowAt:indexPath];
	cell.textLabel.text = row[@"title"];
	cell.detailTextLabel.text = row[@"detail"] ?: @"";
	cell.imageView.image = row[@"emoji"] ? _reactionIcons[row[@"emoji"]] : nil;
	NSString *action = row[@"action"];
	cell.selectionStyle = action.length ? UITableViewCellSelectionStyleBlue
										: UITableViewCellSelectionStyleNone;
	cell.textLabel.textColor = [action isEqualToString:@"clearMine"]
			? [UIColor colorWithRed:0.78f green:0.13f blue:0.13f alpha:1.0f]
			: [UIColor blackColor];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *row = [self rowAt:indexPath];
	NSString *action = row[@"action"];
	if (!action.length)
		return;

	if ([action isEqualToString:@"toggle"]){
		NSString *emoji = row[@"emoji"];
		BOOL chosen = [row[@"detail"] hasPrefix:@"✓"];
		if (chosen){
			[[TGClient shared] removeReaction:emoji fromMessage:self.messageId inChat:self.chatId];
		} else if (!_canAddMore){
			[self say:@"" message:@"You have used every reaction this chat allows on one message."];
			return;
		} else {
			[[TGClient shared] addReaction:emoji toMessage:self.messageId
									inChat:self.chatId big:YES];
		}
		[self refreshSoon];
		return;
	}

	if ([action isEqualToString:@"clearMine"]){
		UIAlertView *ask = [[UIAlertView alloc] initWithTitle:@""
													  message:@"Remove all of your reactions from this message?"
													 delegate:self
											cancelButtonTitle:@"Cancel"
											otherButtonTitles:@"Remove", nil];
		ask.tag = kClearMineAlertTag;
		[ask show];
		return;
	}

	if ([action isEqualToString:@"moreReactors"]){
		[self loadReactorsFromOffset:_reactorsOffset];
		return;
	}

	if ([action isEqualToString:@"reactor"]){
		if (!_canDelete && !_canReport){
			[self say:@"" message:@"You cannot moderate reactions in this chat."];
			return;
		}
		_actionSenderId = [row[@"senderId"] longLongValue];
		_actionSenderName = row[@"title"];
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:_actionSenderName
														   delegate:self
												  cancelButtonTitle:nil
											 destructiveButtonTitle:nil
												  otherButtonTitles:nil];
		if (_canDelete){
			[sheet addButtonWithTitle:@"Remove From This Message"];
			[sheet addButtonWithTitle:@"Remove Everywhere Here"];
		}
		if (_canReport)
			[sheet addButtonWithTitle:@"Report as Spam"];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = kReactorSheetTag;
		[sheet showInView:self.view];
		return;
	}

	if ([action isEqualToString:@"quick"]){
		NSArray *choices = _allowedEmoji.count ? _allowedEmoji : _chatEmoji;
		if (!choices.count){
			[self say:@"" message:@"No reactions are available here."];
			return;
		}
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Quick Reaction"
														   delegate:self
												  cancelButtonTitle:nil
											 destructiveButtonTitle:nil
												  otherButtonTitles:nil];
		NSUInteger shown = MIN((NSUInteger)8, choices.count);
		for (NSUInteger i = 0; i < shown; i++)
			[sheet addButtonWithTitle:choices[i]];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = kQuickReactionSheetTag;
		[sheet showInView:self.view];
		return;
	}

	if ([action isEqualToString:@"chatReactions"]){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Reactions in This Chat"
														   delegate:self
												  cancelButtonTitle:nil
											 destructiveButtonTitle:nil
												  otherButtonTitles:@"Allow All",
																	@"Allow Only What Is Used",
																	@"Turn Reactions Off", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = kChatReactionsSheetTag;
		[sheet showInView:self.view];
		return;
	}

	if ([action isEqualToString:@"clearRecent"]){
		UIAlertView *ask = [[UIAlertView alloc] initWithTitle:@""
													  message:@"Forget the reactions the picker suggests?"
													 delegate:self
											cancelButtonTitle:@"Cancel"
											otherButtonTitles:@"Clear", nil];
		ask.tag = kClearRecentAlertTag;
		[ask show];
	}
}

- (void)refreshSoon {
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [weakSelf loadEverything]; });
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;
	NSString *chosen = [sheet buttonTitleAtIndex:index];

	if (sheet.tag == kReactorSheetTag){
		if ([chosen isEqualToString:@"Remove From This Message"])
			[[TGClient shared] deleteReactionsFromSender:_actionSenderId
											   onMessage:self.messageId
												  inChat:self.chatId];
		else if ([chosen isEqualToString:@"Remove Everywhere Here"])
			[[TGClient shared] deleteAllRecentReactionsFromSender:_actionSenderId
														   inChat:self.chatId];
		else if ([chosen isEqualToString:@"Report as Spam"])
			[[TGClient shared] reportReactionsFromSender:_actionSenderId
											   onMessage:self.messageId
												  inChat:self.chatId];
		[self refreshSoon];
		return;
	}

	if (sheet.tag == kQuickReactionSheetTag){
		[[TGClient shared] setQuickReactionEmoji:chosen];
		[self rebuild];
		return;
	}

	if (sheet.tag == kChatReactionsSheetTag){
		NSInteger maxCount = MAX(1, _chatMax);
		if ([chosen isEqualToString:@"Allow All"])
			[[TGClient shared] setAvailableReactionsInChat:self.chatId emojis:nil
												  maxCount:maxCount];
		else if ([chosen isEqualToString:@"Turn Reactions Off"])
			[[TGClient shared] setAvailableReactionsInChat:self.chatId emojis:@[]
												  maxCount:maxCount];
		else {
			NSMutableArray *used = [NSMutableArray array];
			for (NSDictionary *chip in _chips){
				NSString *emoji = chip[@"emoji"];
				if ([emoji isKindOfClass:NSString.class] && emoji.length &&
					![chip[@"custom"] boolValue])
					[used addObject:emoji];
			}
			if (!used.count){
				[self say:@"" message:@"Nobody has reacted here yet, so there is nothing to keep."];
				return;
			}
			[[TGClient shared] setAvailableReactionsInChat:self.chatId emojis:used
												  maxCount:maxCount];
		}
		[self refreshSoon];
	}
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	if (alertView.tag == kClearMineAlertTag){
		[[TGClient shared] setReactions:@[] onMessage:self.messageId
								 inChat:self.chatId big:NO];
		[self refreshSoon];
		return;
	}
	if (alertView.tag == kClearRecentAlertTag){
		[[TGClient shared] clearRecentReactions];
		[self say:@"" message:@"The suggested reactions have been cleared."];
	}
}

- (void)say:(NSString *)title message:(NSString *)message {
	[[[UIAlertView alloc] initWithTitle:(title ?: @"")
								message:message
							   delegate:nil
					  cancelButtonTitle:@"OK"
					  otherButtonTitles:nil] show];
}

@end

static UIColor *TGChatInputPlaceholderColour(void) {
	return [UIColor colorWithRed:0.616f green:0.655f blue:0.702f alpha:1.0f];
}

@interface TGChatInputTextField : UITextField
@end

@implementation TGChatInputTextField

- (CGRect)placeholderRectForBounds:(CGRect)bounds {
	return [self textRectForBounds:bounds];
}

- (void)drawPlaceholderInRect:(CGRect)rect {
	NSString *text = self.placeholder;
	if (!text.length)
		return;
	UIFont *font = self.font ?: [UIFont systemFontOfSize:16];
	[TGChatInputPlaceholderColour() set];
	CGFloat lineHeight = [@"Ag" sizeWithFont:font].height;
	CGRect line = CGRectMake(rect.origin.x,
			rect.origin.y + floorf((rect.size.height - lineHeight) / 2),
			rect.size.width, lineHeight);
	[text drawInRect:line withFont:font lineBreakMode:UILineBreakModeTailTruncation];
}

@end

typedef NS_ENUM(NSInteger, TGComposeMode) {
	TGComposeModeNew = 0,
	TGComposeModeReply,
	TGComposeModeEdit
};

@interface TGChatViewController () <UISearchBarDelegate, CLLocationManagerDelegate,
		UIScrollViewDelegate, UIAlertViewDelegate,
		ABPeoplePickerNavigationControllerDelegate, MPMediaPickerControllerDelegate,
		UIGestureRecognizerDelegate, UISplitViewControllerDelegate>
- (CGFloat)bubbleWidthBudget;
- (BOOL)scrollToMessageId:(int64_t)messageId;
- (void)loadDeeperHistoryAndScrollTo:(int64_t)messageId;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, assign) CGFloat laidOutWidth;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) NSArray *messages;          // flattened TDLib dicts
@property (nonatomic, strong) NSArray *displayRows;
@property (nonatomic, strong) NSDictionary *albumsByRow;
@property (nonatomic, strong) NSDictionary *rowByMessageId;
@property (nonatomic, strong) NSMutableDictionary *mosaics;
@property (nonatomic, strong) NSMutableDictionary *tileSizes;
@property (nonatomic, strong) NSMutableDictionary *tileBitmaps;
@property (nonatomic, strong) NSMutableSet *tileBitmapsRequested;
@property (nonatomic, strong) NSMutableDictionary *images; // fileId -> UIImage
@property (nonatomic, strong) NSMutableArray *imageOrder;  // fileId, oldest first
@property (nonatomic, assign) BOOL tableReloadPending;
@property (nonatomic, assign) BOOL fetchImagesPending;
@property (nonatomic, assign) BOOL pendingReloadAnchors;
@property (nonatomic, strong) NSMutableSet *imagesRequested;
@property (nonatomic, strong) NSMutableSet *photoFilesInFlight;
@property (nonatomic, strong) NSMutableSet *photoFilesCancelled;
@property (nonatomic, strong) NSMutableSet *photoFilesFailed;
@property (nonatomic, strong) NSMutableDictionary *minithumbnails;
@property (nonatomic, assign) NSRange photoWindow;
@property (nonatomic, assign) BOOL anchorToBottom;
@property (nonatomic, strong) NSMutableDictionary *lottiePaths;   // fileId -> path
@property (nonatomic, strong) NSMutableDictionary *maps;          // messageId -> UIImage
@property (nonatomic, strong) NSMutableSet *mapsRequested;
@property (nonatomic, strong) NSMutableDictionary *quotes;       // messageId -> flattened
@property (nonatomic, strong) NSMutableSet *quotesRequested;
@property (nonatomic, strong) NSMutableSet *quotesMissing;   // replied-to message is gone
@property (nonatomic, strong) NSDictionary *actionMessage;   // long-pressed
@property (nonatomic, assign) int64_t replyToId;             // composing a reply
@property (nonatomic, assign) int64_t editingId;             // editing instead
@property (nonatomic, readonly) TGComposeMode composeMode;
@property (nonatomic, strong) UIView *composeBanner;         // "Reply to ..."
@property (nonatomic, strong) UIButton *micButton;
@property (nonatomic, assign) BOOL videoNoteMode;
@property (nonatomic, assign) BOOL micDidRecord;
@property (nonatomic, strong) UILongPressGestureRecognizer *micHold;
@property (nonatomic, strong) UIView *titleHeader;
@property (nonatomic, strong) UILabel *titleNameLabel;
@property (nonatomic, strong) UILabel *titleStatusLabel;
@property (nonatomic, strong) UISearchBar *chatSearchBar;
@property (nonatomic, strong) NSArray *messagesBeforeSearch;
@property (nonatomic, strong) NSTimer *recordTimer;
@property (nonatomic, strong) UIView *recordPanel;      // shown while holding
@property (nonatomic, strong) UILabel *recordClock;
@property (nonatomic, strong) UIView *recordDot;
@property (nonatomic, strong) MPMoviePlayerController *videoNotePlayer;
@property (nonatomic, strong) NSMutableDictionary *senderAvatars;   // userId -> UIImage
@property (nonatomic, strong) NSMutableSet *senderAvatarsRequested;
@property (nonatomic, strong) UIView *downloadHUD;
@property (nonatomic, strong) UIActivityIndicatorView *downloadSpinner;
@property (nonatomic, strong) UILabel *downloadPercent;
@property (nonatomic, assign) NSInteger downloadingFileId;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) UIImageView *wallpaperView;
@property (nonatomic, strong) UIButton *stickerButton;
@property (nonatomic, strong) UIView *stickerPanel;
@property (nonatomic, strong) NSMutableDictionary *reactionChips;   // messageId -> chips
@property (nonatomic, strong) NSMutableSet *reactionChipsRequested;
@property (nonatomic, strong) NSMutableDictionary *chipsRowWidths;
@property (nonatomic, strong) NSMutableDictionary *linkPreviews;
@property (nonatomic, strong) NSMutableSet *linkPreviewsRequested;
@property (nonatomic, copy) NSString *pendingLinkURL;
@property (nonatomic, strong) TGMessageActionsSheet *actionsSheet;
@property (nonatomic, assign) int64_t forwardMessageId;
@property (nonatomic, strong) NSArray *reportOptions;
@property (nonatomic, assign) int64_t reportMessageId;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIView *emptyPlate;
@property (nonatomic, strong) UIImageView *emptyGlyph;
@property (nonatomic, assign) NSInteger unreadOnOpen;
@property (nonatomic, assign) BOOL unreadOnOpenKnown;
@property (nonatomic, assign) NSInteger cachedUnreadRow;
@property (nonatomic, strong) NSArray *cachedUnreadKey;
@property (nonatomic, strong) UIButton *scrollDownButton;
@property (nonatomic, strong) NSDate *lastTypingSent;
@property (nonatomic, assign) BOOL postingBlocked;
@property (nonatomic, assign) int64_t pinnedMessageId;
@property (nonatomic, strong) NSDictionary *pinnedMessage;
@property (nonatomic, strong) UIView *pinnedBanner;
@property (nonatomic, assign) CGFloat pinnedBannerInset;
@property (nonatomic, assign) CGFloat shortContentInset;
@property (nonatomic, assign) BOOL deeperHistoryPending;
@property (nonatomic, assign) BOOL localHistoryShown;
@property (nonatomic, assign) BOOL networkHistoryShown;
@property (nonatomic, strong) UIButton *channelActionButton;
@property (nonatomic, assign) BOOL channelMuted;
@property (nonatomic, assign) BOOL selecting;
@property (nonatomic, strong) NSMutableArray *selectedIds;
@property (nonatomic, strong) UIView *selectionPanel;
@property (nonatomic, strong) UIBarButtonItem *rightItemBeforeSelection;
@property (nonatomic, strong) UIView *titleViewBeforeSelection;
@property (nonatomic, assign) BOOL drawingSelectedRow;
@property (nonatomic, assign) BOOL sendSilently;
@property (nonatomic, assign) BOOL protectContent;
@property (nonatomic, assign) NSTimeInterval scheduledSendDate;
@property (nonatomic, assign) BOOL scheduleWhenOnline;
@property (nonatomic, strong) NSArray *scheduledMessages;
@property (nonatomic, strong) NSMutableDictionary *sendStates;
@property (nonatomic, strong) NSMutableSet *sendStatesRequested;
@property (nonatomic, strong) NSMutableSet *readMessageIds;
@property (nonatomic, strong) NSMutableArray *mentionIds;
@property (nonatomic, strong) UIButton *mentionButton;
@property (nonatomic, assign) BOOL draftRestored;
@property (nonatomic, copy) NSString *reportTextOptionId;
@property (nonatomic, strong) UIView *datePickerPanel;
@property (nonatomic, strong) UIDatePicker *schedulePicker;
@property (nonatomic, strong) UIImage *pendingPastedImage;
@property (nonatomic, strong) UILongPressGestureRecognizer *messageHold;
@property (nonatomic, strong) UITapGestureRecognizer *backgroundTap;
@property (nonatomic, strong) UIPanGestureRecognizer *inputBarDismissSwipe;
@property (nonatomic, assign) NSInteger swipingRow;
@property (nonatomic, weak) TGBubbleCell *swipingCell;
@property (nonatomic, assign) CGFloat swipeOffset;
@property (nonatomic, assign) BOOL swipeArmed;
@property (nonatomic, assign) NSInteger pressedRow;
@property (nonatomic, assign) int64_t peerMenuUserId;
@property (nonatomic, copy) NSString *peerMenuName;
@property (nonatomic, copy) NSString *heldLinkURL;
@property (nonatomic, assign) int64_t failedMessageId;
@property (nonatomic, strong) NSMutableDictionary *translations;
@property (nonatomic, copy) NSString *pendingInviteLink;
@property (nonatomic, assign) int64_t moderationUserId;
@property (nonatomic, copy) NSString *moderationName;
@property (nonatomic, strong) NSArray *moderationMessageIds;
@property (nonatomic, copy) NSString *attachMode;
@property (nonatomic, copy) NSString *locationMode;
@property (nonatomic, assign) int64_t liveLocationMessageId;
@property (nonatomic, copy) NSString *venueTitle;
@property (nonatomic, copy) NSString *venueAddress;
@property (nonatomic, assign) BOOL markdownComposing;
@property (nonatomic, assign) int64_t reschedulingMessageId;
@property (nonatomic, assign) NSInteger scheduledItemIndex;
@property (nonatomic, strong) NSMutableSet *mapTilesRequested;
@property (nonatomic, strong) NSArray *botButtons;
@property (nonatomic, assign) int64_t botButtonsMessageId;
@property (nonatomic, assign) NSInteger botButtonsRow;
@property (nonatomic, strong) NSDictionary *pendingCallbackButton;
@property (nonatomic, strong) NSArray *botCommandList;
@property (nonatomic, strong) NSArray *similarBotList;
@property (nonatomic, strong) NSArray *recentInlineBotList;
@property (nonatomic, strong) NSDictionary *inlineResults;
@property (nonatomic, copy) NSString *inlineQueryText;
@property (nonatomic, assign) int64_t inlineBotId;
@property (nonatomic, copy) NSString *pendingBotStartLink;
@property (nonatomic, copy) NSString *sharePickerKind;
@property (nonatomic, assign) NSInteger sharePickerButtonId;
@property (nonatomic, assign) int64_t sharePickerMessageId;
@property (nonatomic, assign) int64_t chipsSheetMessageId;
@property (nonatomic, strong) NSMutableArray *reactionMessageIds;
@property (nonatomic, strong) UIButton *reactionButton;
@property (nonatomic, assign) BOOL chatIsWithBot;
@property (nonatomic, copy) NSString *pendingStickerSetLink;
@property (nonatomic, strong) NSArray *tappedLinkTargets;
@property (nonatomic, strong) UIBarButtonItem *masterRevealItem;
@property (nonatomic, strong) UIPopoverController *masterPopover;
@property (nonatomic, strong) UIBarButtonItem *leftItemBeforeSplit;
@property (nonatomic, assign) BOOL leftItemBeforeSplitKnown;
@property (nonatomic, assign) CGFloat composeBannerInset;
@property (nonatomic, strong) UIActivityIndicatorView *historySpinner;
@property (nonatomic, assign) NSTimeInterval keyboardDuration;
@property (nonatomic, assign) UIViewAnimationCurve keyboardCurve;

- (void)clearComposeState;
- (void)layoutFloatingButtons;
- (void)centreEmptyPlate;
- (BOOL)historyIsAtBottom;
- (void)setComposeMode:(TGComposeMode)mode messageId:(int64_t)messageId;
- (void)showComposeBanner:(NSString *)text;
- (void)installMessageHandler;
- (void)updateEmptyState;
- (void)layoutTitleView;
- (void)applyMicButtonGlyph;
- (void)captureVideoRound:(BOOL)round;
- (Class)videoCaptureClass;
- (void)pickPhotoAlbum;
- (void)sendPickedPhotos:(NSArray *)paths;
- (void)sendAlbumBatch:(NSArray *)paths caption:(NSString *)caption;
@end

@implementation TGChatViewController

#pragma mark - layout

- (void)viewDidLoad {
	[super viewDidLoad];

	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	if (!self.unreadOnOpenKnown){
		self.unreadOnOpenKnown = YES;
		self.cachedUnreadRow = NSNotFound;
		for (NSDictionary *chat in [[TGClient shared] chats]){
			if ([chat[@"id"] longLongValue] == self.chatId){
				self.unreadOnOpen = [chat[@"unread"] integerValue];
				break;
			}
		}
	}

	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self buildTitleView];
	self.mosaics = [NSMutableDictionary dictionary];
	self.tileSizes = [NSMutableDictionary dictionary];
	self.tileBitmaps = [NSMutableDictionary dictionary];
	self.tileBitmapsRequested = [NSMutableSet set];
	self.messages = @[];
	self.senderAvatars = [NSMutableDictionary dictionary];
	self.senderAvatarsRequested = [NSMutableSet set];
	self.images = [NSMutableDictionary dictionary];
	self.imageOrder = [NSMutableArray array];
	self.imagesRequested = [NSMutableSet set];
	self.photoFilesInFlight = [NSMutableSet set];
	self.photoFilesCancelled = [NSMutableSet set];
	self.photoFilesFailed = [NSMutableSet set];
	self.minithumbnails = [NSMutableDictionary dictionary];
	self.photoWindow = NSMakeRange(NSNotFound, 0);
	self.lottiePaths = [NSMutableDictionary dictionary];
	self.maps = [NSMutableDictionary dictionary];
	self.mapsRequested = [NSMutableSet set];
	self.quotes = [NSMutableDictionary dictionary];
	self.quotesRequested = [NSMutableSet set];
	self.quotesMissing = [NSMutableSet set];
	self.reactionChips = [NSMutableDictionary dictionary];
	self.reactionChipsRequested = [NSMutableSet set];
	self.chipsRowWidths = [NSMutableDictionary dictionary];
	self.linkPreviews = [NSMutableDictionary dictionary];
	self.linkPreviewsRequested = [NSMutableSet set];
	self.selectedIds = [NSMutableArray array];
	self.translations = [NSMutableDictionary dictionary];
	self.sendStates = [NSMutableDictionary dictionary];
	self.sendStatesRequested = [NSMutableSet set];
	self.readMessageIds = [NSMutableSet set];
	self.mentionIds = [NSMutableArray array];
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
	self.messageHold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(messageHeld:)];
	self.messageHold.minimumPressDuration = 0.3;
	self.messageHold.allowableMovement = 10.0f;
	self.messageHold.cancelsTouchesInView = YES;
	self.messageHold.delegate = self;
	[self.table addGestureRecognizer:self.messageHold];

	UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(messageDoubleTapped:)];
	doubleTap.numberOfTapsRequired = 2;
	[self.table addGestureRecognizer:doubleTap];

	self.backgroundTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(messageBackgroundTapped:)];
	self.backgroundTap.cancelsTouchesInView = NO;
	self.backgroundTap.delaysTouchesBegan = NO;
	self.backgroundTap.delaysTouchesEnded = NO;
	self.backgroundTap.delegate = self;
	[self.table addGestureRecognizer:self.backgroundTap];

	self.swipingRow = -1;
	self.pressedRow = -1;

	[self.view addSubview:self.table];

	[self buildInputBar:b];

	self.inputBarDismissSwipe = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(inputBarSwiped:)];
	self.inputBarDismissSwipe.cancelsTouchesInView = NO;
	self.inputBarDismissSwipe.delaysTouchesBegan = NO;
	self.inputBarDismissSwipe.delaysTouchesEnded = NO;
	self.inputBarDismissSwipe.delegate = self;
	[self.inputBar addGestureRecognizer:self.inputBarDismissSwipe];

	UILongPressGestureRecognizer *sendHold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(sendHeld:)];
	[self.sendButton addGestureRecognizer:sendHold];

	[self restoreDraft];
	[self loadUnreadMentions];
	[self loadUnreadReactions];
	[self detectBotChat];
	[self loadScheduledMessages];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
			name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
			name:UIKeyboardWillHideNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(flushDraftOnAppState:)
			name:UIApplicationDidEnterBackgroundNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(flushDraftOnAppState:)
			name:UIApplicationWillTerminateNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(musicPlayerStateChanged)
			name:TGMusicPlayerStateChangedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(musicPlayerProgressed)
			name:TGMusicPlayerProgressNotification object:nil];

	[self installMessageHandler];

	TGBeginOpenTiming();
	[self reload];
}

/// Another screen pushed on top of this one - the forward picker, a profile -
/// may install a handler of its own on the shared client. Coming back has to
/// take it over again or the chat stops updating live.
- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGRect frame = self.table.frame;
	if (fabsf(frame.size.width - self.view.bounds.size.width) > 0.5f){
		frame.size.width = self.view.bounds.size.width;
		self.table.frame = frame;
	}
	[self centreEmptyPlate];
	[self layoutFloatingButtons];
	CGFloat width = self.table.bounds.size.width;
	if (width < 1 || fabsf(width - self.laidOutWidth) < 0.5f){
		[self updateShortContentInset];
		return;
	}
	self.laidOutWidth = width;
	[self.table reloadData];
	[self updateShortContentInset];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self installMessageHandler];
	[[TGMusicPlayer shared] chatOpened:self.chatId];
	if (TGChatIsPad() && self.masterRevealItem &&
		self.navigationItem.leftBarButtonItem != self.masterRevealItem)
		self.navigationItem.leftBarButtonItem = self.masterRevealItem;
	if (self.liveLocationMessageId && [self.locationMode isEqualToString:@"tracking"])
		[self.locationManager startUpdatingLocation];
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
			if (deletedId && newId){
				[me.sendStates removeObjectForKey:@(deletedId)];
				[me.sendStatesRequested removeObject:@(deletedId)];
				[me.sendStates removeObjectForKey:newId];
				[me.sendStatesRequested removeObject:newId];
				NSMutableArray *swapped = [me.messages mutableCopy];
				BOOL found = NO;
				for (NSUInteger i = 0; i < swapped.count; i++){
					if ([swapped[i][@"id"] longLongValue] != deletedId)
						continue;
					[swapped replaceObjectAtIndex:i withObject:message];
					found = YES;
					break;
				}
				if (found){
					me.messages = swapped;
					[me.table reloadData];
					return;
				}
			}
			NSArray *liveChips = [TGClient reactionChipsFromMessage:message];
			if (newId && liveChips.count){
				me.reactionChips[newId] = liveChips;
				[me.chipsRowWidths removeObjectForKey:newId];
				[me.reactionChipsRequested addObject:newId];
			}
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
			BOOL follow = [message[@"outgoing"] boolValue] || [me historyIsAtBottom];
			NSMutableArray *next = [me.messages mutableCopy];
			[next addObject:message];
			me.messages = next;
			[me warmMinithumbnailsFor:@[message]];
			[me.table reloadData];
			[me updateEmptyState];
			if (follow)
				[me scrollToBottomAnimated:YES];
			else
				[me updateScrollDownButton];
			[me fetchMissingImages];
			[me fetchMissingQuotes];
			if (newId)
				[[TGClient shared] markRead:@[newId] inChat:chatId];
			return;
		}
		if (deletedId){
			NSMutableArray *left = [NSMutableArray arrayWithCapacity:me.messages.count];
			for (NSDictionary *existing in me.messages)
				if ([existing[@"id"] longLongValue] != deletedId)
					[left addObject:existing];
			if (left.count == me.messages.count)
				return;
			me.messages = left;
			[me.table reloadData];
			[me updateEmptyState];
			return;
		}
		[me reload];
	};
}

/// A two-line header: the chat name with member count or status beneath it,
/// which is what tells you where you are in a group.
- (void)buildTitleView {
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 36)];

	TGEmojiLabel *name = [[TGEmojiLabel alloc] initWithFrame:CGRectMake(0, 1, 200, 20)];
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
	self.titleHeader = header;
	self.titleNameLabel = name;
	self.titleStatusLabel = subtitle;
	[self buildAvatarButton];
	self.navigationItem.titleView = header;
	[self layoutTitleView];

	// "typing..." takes the subtitle over while it lasts, then hands it back.
	__weak typeof(self) weakSelf = self;
	__block NSString *restingSubtitle = @"";
	[TGClient shared].onChatAction = ^(int64_t chatId, NSString *action){
		if (chatId != weakSelf.chatId)
			return;
		NSString *next = action ?: restingSubtitle;
		if ([next isEqualToString:subtitle.text ?: @""])
			return;
		CATransition *fade = [CATransition animation];
		fade.duration = 0.2;
		fade.type = kCATransitionFade;
		[subtitle.layer addAnimation:fade forKey:@"tgStatusFade"];
		subtitle.text = next;
		[weakSelf layoutTitleView];
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
			[weakSelf layoutTitleView];
		}];
		return;
	}

	[[TGClient shared] memberCountForChat:self.chatId completion:^(NSInteger count){
		if (count > 0){
			restingSubtitle = [NSString stringWithFormat:@"%ld members", (long)count];
			subtitle.text = restingSubtitle;
			[weakSelf layoutTitleView];
		}
	}];
}

- (void)layoutTitleView {
	if (!self.titleHeader)
		return;

	CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
	CGFloat barWidth = self.navigationController.navigationBar.bounds.size.width;
	if (TGChatIsPad() && barWidth > 1)
		screenWidth = barWidth;
	UIView *leftView = self.navigationItem.leftBarButtonItem.customView;
	UIView *rightView = self.navigationItem.rightBarButtonItem.customView;
	CGFloat leftWidth = (leftView ? leftView.frame.size.width : 54.0f) + 13.0f;
	CGFloat rightWidth = (rightView ? rightView.frame.size.width : 37.0f) + 13.0f;
	CGFloat maxWidth = screenWidth - 2 * MAX(leftWidth, rightWidth);
	if (maxWidth < 80.0f)
		maxWidth = 80.0f;

	NSString *nameText = self.titleNameLabel.text.length ? self.titleNameLabel.text : @" ";
	NSString *statusText = self.titleStatusLabel.hidden || !self.titleStatusLabel.text.length
			? @"" : self.titleStatusLabel.text;

	CGFloat nameWidth = TGEmojiTextSize(nameText, self.titleNameLabel.font,
			CGSizeMake(10000, 40), NSLineBreakByWordWrapping, 1).width;
	CGFloat statusWidth = statusText.length
			? [statusText sizeWithFont:self.titleStatusLabel.font].width : 0.0f;
	CGFloat width = ceilf(MAX(nameWidth, statusWidth));
	if (width > maxWidth)
		width = maxWidth;
	if (((int)width) % 2 != 0)
		width += 1;

	CGFloat height = statusText.length ? 36.0f : 22.0f;
	const CGFloat retinaPixel = ([UIScreen mainScreen].scale > 1.0f) ? 0.5f : 0.0f;

	self.titleHeader.frame = CGRectMake(0, 0, width, height);
	self.titleNameLabel.frame = CGRectMake(0, statusText.length ? 0 : 1, width, 21);
	self.titleStatusLabel.frame = CGRectMake(0, height - 15 - 3 + retinaPixel, width, 15);

	[self.titleHeader.superview setNeedsLayout];
	[self.navigationController.navigationBar setNeedsLayout];
}

- (void)buildInputBarContainer:(CGRect)b {
	self.inputBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, b.size.height - kInputHeight, b.size.width, kInputHeight)];
	self.inputBar.backgroundColor = [[TGTheme shared] inputBarColour];
	self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	self.inputBar.clipsToBounds = NO;
}

- (void)buildInputBarBackground:(CGRect)b retinaPixel:(CGFloat)retinaPixel {
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
				CGRectMake(40, 4 - retinaPixel, b.size.width - 106, 36)];
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
}

- (void)buildInputBarAttachButton:(CGRect)b retinaPixel:(CGFloat)retinaPixel {
	(void)retinaPixel;
	UIButton *attach = [UIButton buttonWithType:UIButtonTypeCustom];
	attach.frame = CGRectMake(0, 0, 41, kInputHeight);
	attach.imageEdgeInsets = UIEdgeInsetsMake(1, 0, 0, 0);
	attach.exclusiveTouch = YES;
	attach.autoresizingMask = UIViewAutoresizingFlexibleRightMargin |
							  UIViewAutoresizingFlexibleTopMargin;
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
}

- (void)buildInputBarTextField:(CGRect)b retinaPixel:(CGFloat)retinaPixel {
	self.input = [[TGChatInputTextField alloc] initWithFrame:
			CGRectMake(49, 5 - retinaPixel, b.size.width - 158, 34)];
	self.input.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
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
	[self.inputBar addSubview:self.input];
}

- (UIImage *)buildInputBarSendButton:(CGRect)b topY:(CGFloat)sendY {
	CGFloat sendWidth = 62;
	self.sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.sendButton.frame = CGRectMake(b.size.width - sendWidth - 5, sendY,
									   sendWidth, 29);
	self.sendButton.exclusiveTouch = YES;
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
	[self.sendButton setTitleColor:[UIColor colorWithRed:0.808f green:1.0f
													blue:0.690f alpha:1.0f]
						  forState:UIControlStateDisabled];
	self.sendButton.adjustsImageWhenHighlighted = NO;
	self.sendButton.adjustsImageWhenDisabled = NO;
	self.sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
									   UIViewAutoresizingFlexibleTopMargin;
	[self.sendButton addTarget:self action:@selector(sendTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:self.sendButton];
	return sendImage;
}

static UIImage *TGChatStickerGlyph(UIColor *colour) {
	const CGFloat box = 24.0f;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(box, box), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetLineWidth(ctx, 1.5f);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);
	[colour setStroke];

	CGPoint centre = CGPointMake(box / 2, box / 2);
	CGFloat radius = 9.5f;
	CGPoint top = CGPointMake(centre.x, centre.y - radius);
	CGPoint right = CGPointMake(centre.x + radius, centre.y);
	CGFloat reach = radius * 1.3f * 0.70710678f;
	CGPoint tip = CGPointMake(centre.x + reach, centre.y - reach);

	UIBezierPath *body = [UIBezierPath bezierPath];
	[body addArcWithCenter:centre radius:radius startAngle:0.0f
				  endAngle:(CGFloat)(3.0 * M_PI / 2.0) clockwise:YES];
	[body addLineToPoint:tip];
	[body addLineToPoint:right];
	CGContextAddPath(ctx, body.CGPath);
	CGContextStrokePath(ctx);

	CGFloat foldRadius = sqrtf((tip.x - top.x) * (tip.x - top.x) +
							   (tip.y - top.y) * (tip.y - top.y));
	UIBezierPath *fold = [UIBezierPath bezierPath];
	[fold addArcWithCenter:tip radius:foldRadius
				startAngle:atan2f(top.y - tip.y, top.x - tip.x)
				  endAngle:atan2f(right.y - tip.y, right.x - tip.x)
				 clockwise:NO];
	CGContextAddPath(ctx, fold.CGPath);
	CGContextStrokePath(ctx);

	UIImage *glyph = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return glyph;
}

- (void)buildInputBarStickerButton:(CGRect)b retinaPixel:(CGFloat)retinaPixel {
	(void)retinaPixel;
	self.stickerButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.stickerButton.frame = CGRectMake(b.size.width - 109, 0, 39, kInputHeight);
	self.stickerButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 2);
	self.stickerButton.exclusiveTouch = YES;
	UIColor *stickerInk = [UIColor colorWithRed:0.616f green:0.655f blue:0.702f alpha:1.0f];
	[self.stickerButton setImage:TGChatStickerGlyph(stickerInk)
						forState:UIControlStateNormal];
	[self.stickerButton setImage:TGChatStickerGlyph([[TGTheme shared] accentColour])
						forState:UIControlStateHighlighted];
	self.stickerButton.adjustsImageWhenHighlighted = NO;
	self.stickerButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
										  UIViewAutoresizingFlexibleTopMargin;
	[self.stickerButton addTarget:self action:@selector(toggleStickerPanel)
				 forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:self.stickerButton];
}

- (void)buildInputBarMicButton:(UIImage *)sendImage {
	self.micButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.micButton.frame = self.sendButton.frame;
	self.micButton.exclusiveTouch = YES;
	if (sendImage){
		[self.micButton setBackgroundImage:
				[sendImage stretchableImageWithLeftCapWidth:(int)(sendImage.size.width / 2)
											   topCapHeight:0]
								  forState:UIControlStateNormal];
		UIImage *micPressed = [UIImage imageNamed:@"SendButton_Pressed"];
		if (micPressed)
			[self.micButton setBackgroundImage:
					[micPressed stretchableImageWithLeftCapWidth:(int)(micPressed.size.width / 2)
													topCapHeight:0]
									  forState:UIControlStateHighlighted];
		self.micButton.adjustsImageWhenHighlighted = NO;
	}
	self.micButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
									  UIViewAutoresizingFlexibleTopMargin;
	[self applyMicButtonGlyph];

	[self.micButton addTarget:self action:@selector(micTapped)
			 forControlEvents:UIControlEventTouchUpInside];

	self.micHold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(micHeld:)];
	self.micHold.minimumPressDuration = 0.18;
	self.micHold.allowableMovement = CGFLOAT_MAX;
	[self.micButton addGestureRecognizer:self.micHold];

	[self.inputBar addSubview:self.micButton];
}

static UIImage *TGChatVideoNoteGlyph(UIColor *colour, CGFloat side) {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	[colour setFill];

	CGFloat bodyWidth = side * 0.66f;
	CGFloat bodyHeight = side * 0.58f;
	CGRect body = CGRectMake(side * 0.06f, (side - bodyHeight) / 2, bodyWidth, bodyHeight);
	UIBezierPath *shell = [UIBezierPath bezierPathWithRoundedRect:body
													cornerRadius:side * 0.14f];
	CGContextAddPath(ctx, shell.CGPath);
	CGContextFillPath(ctx);

	UIBezierPath *lens = [UIBezierPath bezierPath];
	[lens moveToPoint:CGPointMake(CGRectGetMaxX(body) + side * 0.04f, side / 2)];
	[lens addLineToPoint:CGPointMake(side * 0.94f, side * 0.25f)];
	[lens addLineToPoint:CGPointMake(side * 0.94f, side * 0.75f)];
	[lens closePath];
	CGContextAddPath(ctx, lens.CGPath);
	CGContextFillPath(ctx);

	UIImage *glyph = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return glyph;
}

- (void)applyMicButtonGlyph {
	BOOL onPlate = ([self.micButton backgroundImageForState:UIControlStateNormal] != nil);
	UIColor *ink = onPlate ? [UIColor whiteColor] : [[TGTheme shared] secondaryTextColour];
	UIImage *glyph = self.videoNoteMode
			? TGChatVideoNoteGlyph(ink, 20)
			: [TGIcons microphoneOfSide:20 colour:ink];
	[self.micButton setImage:glyph forState:UIControlStateNormal];
}

- (void)micTapped {
	if (self.micDidRecord){
		self.micDidRecord = NO;
		return;
	}
	if (self.videoNoteMode)
		self.videoNoteMode = NO;
	else
		self.videoNoteMode = ([self videoCaptureClass] != Nil);
	[self applyMicButtonGlyph];
}

- (void)micHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state == UIGestureRecognizerStateBegan){
		self.micDidRecord = YES;
		if (self.videoNoteMode)
			[self captureVideoRound:YES];
		else
			[self recordStart];
		return;
	}

	if (self.videoNoteMode){
		if (hold.state != UIGestureRecognizerStateChanged)
			self.micDidRecord = NO;
		return;
	}

	if (hold.state == UIGestureRecognizerStateEnded){
		CGPoint where = [hold locationInView:self.micButton];
		if (CGRectContainsPoint(CGRectInset(self.micButton.bounds, -20, -20), where))
			[self recordFinish];
		else
			[self recordCancel];
		self.micDidRecord = NO;
	} else if (hold.state == UIGestureRecognizerStateCancelled ||
			   hold.state == UIGestureRecognizerStateFailed){
		[self recordCancel];
		self.micDidRecord = NO;
	}
}

- (void)buildInputBar:(CGRect)b {
	const CGFloat retinaPixel = ([UIScreen mainScreen].scale > 1.0f) ? 0.5f : 0.0f;

	[self buildInputBarContainer:b];
	[self buildInputBarBackground:b retinaPixel:retinaPixel];

	CGFloat sendY = 7 + retinaPixel;

	[self buildInputBarAttachButton:b retinaPixel:retinaPixel];
	[self buildInputBarTextField:b retinaPixel:retinaPixel];

	UIImage *sendImage = [self buildInputBarSendButton:b topY:sendY];

	[self buildInputBarStickerButton:b retinaPixel:retinaPixel];
	[self buildInputBarMicButton:sendImage];

	[self.input addTarget:self action:@selector(inputChanged)
		 forControlEvents:UIControlEventEditingChanged];
	self.sendButton.hidden = YES;
	self.micButton.hidden = NO;
	[self inputChanged];

	[self.view addSubview:self.inputBar];
}

#pragma mark - split layout

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
								duration:(NSTimeInterval)duration {
	[super willRotateToInterfaceOrientation:orientation duration:duration];
	if (!TGChatIsPad())
		return;
	[self.masterPopover dismissPopoverAnimated:NO];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
	[super didRotateFromInterfaceOrientation:orientation];
	if (!TGChatIsPad())
		return;
	[self relayoutForPaneWidth];
}

- (void)relayoutForPaneWidth {
	[self.chipsRowWidths removeAllObjects];
	[self.mosaics removeAllObjects];
	[self.tileSizes removeAllObjects];
	[self.tileBitmaps removeAllObjects];
	[self.tileBitmapsRequested removeAllObjects];

	NSArray *visible = [self.table indexPathsForVisibleRows];
	NSIndexPath *anchor = visible.count ? visible.lastObject : nil;
	[self.table reloadData];
	if (anchor && anchor.row < [self displayRowCount])
		[self.table scrollToRowAtIndexPath:anchor
						  atScrollPosition:UITableViewScrollPositionBottom
								  animated:NO];

	[self layoutTitleView];
}

- (void)splitViewController:(UISplitViewController *)splitController
	 willHideViewController:(UIViewController *)master
		  withBarButtonItem:(UIBarButtonItem *)barButtonItem
	   forPopoverController:(UIPopoverController *)popover {
	if (!TGChatIsPad())
		return;

	barButtonItem.title = barButtonItem.title.length ? barButtonItem.title : @"Chats";
	self.masterRevealItem = barButtonItem;
	self.masterPopover = popover;

	if (!self.leftItemBeforeSplitKnown){
		self.leftItemBeforeSplitKnown = YES;
		self.leftItemBeforeSplit = self.navigationItem.leftBarButtonItem;
	}
	self.navigationItem.leftBarButtonItem = barButtonItem;
	[self layoutTitleView];
}

- (void)splitViewController:(UISplitViewController *)splitController
	 willShowViewController:(UIViewController *)master
  invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem {
	if (!TGChatIsPad())
		return;

	if (self.navigationItem.leftBarButtonItem == barButtonItem ||
		self.navigationItem.leftBarButtonItem == self.masterRevealItem)
		self.navigationItem.leftBarButtonItem = self.leftItemBeforeSplit;

	self.masterRevealItem = nil;
	self.masterPopover = nil;
	[self layoutTitleView];
}

- (void)splitViewController:(UISplitViewController *)splitController
		  popoverController:(UIPopoverController *)popover
  willPresentViewController:(UIViewController *)master {
	[self.input resignFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self saveDraft];
	[self stopVideoNote];
	// A pending delete must not be lost with the screen, and a menu must not
	// outlive the messages it was opened over.
	[TGSnackbar commitNow];
	[TGPopupMenu dismiss];
	[TGReactionPickerView dismiss];
	[[TGClient shared] unwatchAllReactions];
	[self.actionsSheet dismiss];
	self.actionsSheet = nil;
	if (self.locationManager)
		[self.locationManager stopUpdatingLocation];
	if (!self.navigationController || self.isMovingFromParentViewController)
		[[TGMusicPlayer shared] chatClosed:self.chatId];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];

	NSMutableSet *keep = [NSMutableSet set];
	NSMutableSet *keepFiles = [NSMutableSet set];
	for (NSIndexPath *path in [self.table indexPathsForVisibleRows]){
		for (NSDictionary *m in [self messagesAtRow:path.row]){
			if ([m[@"id"] isKindOfClass:NSNumber.class])
				[keep addObject:m[@"id"]];
			NSNumber *fileId = [self pictureFileIdFor:m];
			if (fileId)
				[keepFiles addObject:fileId];
		}
	}
	[self.tileBitmaps removeAllObjects];
	[self.tileBitmapsRequested removeAllObjects];
	for (NSNumber *key in [self.maps allKeys])
		if (![keep containsObject:key])
			[self.maps removeObjectForKey:key];
	for (NSNumber *key in [self.minithumbnails allKeys])
		if (![keep containsObject:key])
			[self.minithumbnails removeObjectForKey:key];

	for (NSNumber *fileId in [self.images allKeys]){
		if ([keepFiles containsObject:fileId])
			continue;
		[self.images removeObjectForKey:fileId];
		[self.imagesRequested removeObject:fileId];
		[self.imageOrder removeObject:fileId];
	}
	self.photoWindow = NSMakeRange(NSNotFound, 0);
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - data

- (void)showHistorySpinnerAfterGrace {
	if (self.historySpinner)
		return;
	self.historySpinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	self.historySpinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
										   UIViewAutoresizingFlexibleRightMargin |
										   UIViewAutoresizingFlexibleTopMargin |
										   UIViewAutoresizingFlexibleBottomMargin;
	self.historySpinner.hidesWhenStopped = YES;
	[self.view insertSubview:self.historySpinner aboveSubview:self.table];

	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		TGChatViewController *me = weakSelf;
		if (!me || !me.historySpinner || me.messages.count)
			return;
		CGRect history = me.table.frame;
		me.historySpinner.center = CGPointMake(
				floorf(CGRectGetMidX(history)),
				floorf(CGRectGetMidY(history) + me.pinnedBannerInset / 2));
		[me.historySpinner startAnimating];
	});
}

- (void)hideHistorySpinner {
	[self.historySpinner stopAnimating];
	[self.historySpinner removeFromSuperview];
	self.historySpinner = nil;
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	self.localHistoryShown = NO;
	self.networkHistoryShown = NO;
	if (self.messages.count != 0){
		[self reloadFromNetwork];
		return;
	}

	[self showHistorySpinnerAfterGrace];

	void (^partial)(NSArray *) = ^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me || !messages.count || me.networkHistoryShown ||
			messages.count <= me.messages.count)
			return;
		me.localHistoryShown = YES;
		TGMarkOpenStage([NSString stringWithFormat:@"%lu of the cached messages drawn",
				(unsigned long)messages.count]);
		[me applyHistory:messages final:NO partial:YES];
	};

	[[TGClient shared] historyForChat:self.chatId thread:self.threadId limit:60
							onlyLocal:YES progress:partial completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (messages.count && !me.networkHistoryShown){
			me.localHistoryShown = YES;
			TGMarkOpenStage([NSString stringWithFormat:@"%lu cached messages drawn",
					(unsigned long)messages.count]);
			[me applyHistory:messages final:NO partial:NO];
		}
		[me reloadFromNetwork];
	}];
}

- (void)reloadFromNetwork {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] historyForChat:self.chatId thread:self.threadId limit:60
							onlyLocal:NO completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (me.localHistoryShown && messages.count < me.messages.count)
			return;
		me.networkHistoryShown = YES;
		TGMarkOpenStage([NSString stringWithFormat:@"%lu messages from TDLib",
				(unsigned long)messages.count]);
		[me applyHistory:messages final:YES partial:NO];
	}];
}

- (void)applyHistory:(NSArray *)messages final:(BOOL)final partial:(BOOL)partial {
	if (messages.count)
		[self hideHistorySpinner];
	self.messages = messages;
	[self warmMinithumbnailsFor:messages];
	[self.reactionChipsRequested removeAllObjects];
	[self.reactionChips removeAllObjects];
	[self.chipsRowWidths removeAllObjects];
	for (NSNumber *key in [self.sendStates allKeys]){
		if ([self.sendStates[key] isEqualToString:@"sent"])
			continue;
		[self.sendStates removeObjectForKey:key];
		[self.sendStatesRequested removeObject:key];
	}
	self.anchorToBottom = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ weakSelf.anchorToBottom = NO; });
	NSMutableArray *kinds = [NSMutableArray array];
	for (NSDictionary *m in messages)
		[kinds addObject:m[@"kind"] ?: @"?"];
	NSLog(@"TDLIB HISTORY%@: %lu msgs: %@", final ? @"" : @" (cached)",
			(unsigned long)messages.count, [kinds componentsJoinedByString:@", "]);
	[self.table reloadData];
	[self updateShortContentInset];
	if (messages.count){
		TGMarkOpenFrame([NSString stringWithFormat:@"FIRST FRAME with %lu messages",
				(unsigned long)messages.count]);
		if (!partial)
			TGMarkOpenSettledFrame([NSString stringWithFormat:
					@"SETTLED FRAME with %lu messages", (unsigned long)messages.count]);
	}
	[self updateEmptyState];
	[self scrollToBottomAnimated:NO];
	[self fetchMissingImages];
	[self resolveUnknownSenders];
	[self fetchMissingQuotes];

	if (self.focusMessageId && final){
		int64_t wanted = self.focusMessageId;
		self.focusMessageId = 0;
		self.anchorToBottom = NO;
		if (![self scrollToMessageId:wanted])
			[self loadDeeperHistoryAndScrollTo:wanted];
	}

	if (!final)
		return;

	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *m in messages)
		if ([m[@"id"] isKindOfClass:NSNumber.class])
			[ids addObject:m[@"id"]];
	if (ids.count)
		[[TGClient shared] markRead:ids inChat:self.chatId];
}

/// A location gets a drawn card, not a real map: MKMapSnapshotter fires no
/// completion at all on iOS 7 because Apple's tile servers stopped answering
/// clients this old. So this is a stylised plan view with a pin - honest about
/// being a placeholder, and it works with no network.
- (UIImage *)mapCardForLatitude:(double)lat longitude:(double)lon {
	CGSize size = CGSizeMake(kMapCardW, kMapCardH);
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

- (BOOL)messageCarriesMapCard:(NSDictionary *)m {
	return [m[@"lat"] isKindOfClass:NSNumber.class] &&
		   [m[@"lon"] isKindOfClass:NSNumber.class];
}

- (UIImage *)mapCardFor:(NSDictionary *)m {
	if (![self messageCarriesMapCard:m])
		return nil;
	NSNumber *key = [m[@"id"] isKindOfClass:NSNumber.class] ? m[@"id"] : nil;
	UIImage *card = key ? self.maps[key] : nil;
	if (card)
		return card;
	card = [self mapCardForLatitude:[m[@"lat"] doubleValue]
						  longitude:[m[@"lon"] doubleValue]];
	if (key && card)
		self.maps[key] = card;
	if (key)
		[self fetchMapTileFor:m key:key];
	return card;
}

/// The drawn card is only a stand-in: TDLib renders a real tile for the point,
/// and the bubble swaps to it once it has arrived.
- (void)fetchMapTileFor:(NSDictionary *)m key:(NSNumber *)key {
	if (!self.mapTilesRequested)
		self.mapTilesRequested = [NSMutableSet set];
	if ([self.mapTilesRequested containsObject:key])
		return;
	[self.mapTilesRequested addObject:key];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] mapThumbnailForLatitude:[m[@"lat"] doubleValue]
									 longitude:[m[@"lon"] doubleValue]
										  zoom:16
										 width:(NSInteger)kMapCardW
										height:(NSInteger)kMapCardH
										 scale:1
										inChat:self.chatId
									completion:^(NSInteger fileId){
		TGChatViewController *me = weakSelf;
		if (!me || fileId <= 0)
			return;
		[[TGClient shared] downloadFile:fileId completion:^(NSString *path){
			if (!path.length)
				return;
			CGFloat cardPixels = MAX(kMapCardW, kMapCardH) * [UIScreen mainScreen].scale;
			dispatch_async(TGImageDecodeQueue(), ^{
				UIImage *tile = TGDecodeThumbnail(path, cardPixels);
				if (!tile)
					return;
				UIImage *card = TGImageDrawnAtPointSize(tile,
						CGSizeMake(kMapCardW, kMapCardH));
				dispatch_async(dispatch_get_main_queue(), ^{
					TGChatViewController *inner = weakSelf;
					if (!inner)
						return;
					inner.maps[key] = card;
					[inner setNeedsTableReload];
				});
			});
		}];
	}];
}

- (void)setNeedsTableReload {
	if (self.tableReloadPending)
		return;
	self.tableReloadPending = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		me.tableReloadPending = NO;
		BOOL anchor = me.pendingReloadAnchors;
		me.pendingReloadAnchors = NO;
		[me.table reloadData];
		if (anchor && me.anchorToBottom)
			[me scrollToBottomAnimated:NO];
	});
}

- (void)setNeedsTableReloadKeepingBottom {
	self.pendingReloadAnchors = YES;
	[self setNeedsTableReload];
}

- (void)setNeedsFetchMissingImages {
	if (self.fetchImagesPending)
		return;
	self.fetchImagesPending = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		me.fetchImagesPending = NO;
		[me fetchMissingImages];
	});
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
			[weakSelf setNeedsTableReload];
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
			if (!me)
				return;
			if (!original){
				[me.quotesMissing addObject:replyId];
				[me.table reloadData];
				return;
			}
			me.quotes[replyId] = original;
			[me setNeedsTableReload];
			[me setNeedsFetchMissingImages];
		}];
	}
}

/// The flattened message only carries the reactions as a run of text; the chip
/// row needs counts and which one is ours, which is a separate read.
- (void)fetchMissingReactionChips {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *m in self.messages){
		NSNumber *messageId = [m[@"id"] isKindOfClass:NSNumber.class] ? m[@"id"] : nil;
		if (!messageId || ![m[@"reactions"] length])
			continue;
		if (self.reactionChips[messageId] ||
			[self.reactionChipsRequested containsObject:messageId])
			continue;
		[self.reactionChipsRequested addObject:messageId];

		[[TGClient shared] reactionChipsForMessage:messageId.longLongValue
											inChat:self.chatId
										completion:^(NSArray *chips){
			TGChatViewController *me = weakSelf;
			if (!me || !chips.count)
				return;
			me.reactionChips[messageId] = chips;
			[me.chipsRowWidths removeObjectForKey:messageId];
			[me setNeedsTableReload];
		}];
	}
}

- (void)fetchMissingLinkPreviews {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *m in self.messages){
		NSNumber *messageId = [m[@"id"] isKindOfClass:NSNumber.class] ? m[@"id"] : nil;
		if (!messageId || [m[@"service"] boolValue])
			continue;
		if (![m[@"kind"] isEqualToString:@"messageText"])
			continue;
		NSString *text = m[@"text"];
		if (!text.length)
			continue;
		if ([text rangeOfString:@"http" options:NSCaseInsensitiveSearch].location == NSNotFound &&
			[text rangeOfString:@"t.me/" options:NSCaseInsensitiveSearch].location == NSNotFound)
			continue;
		if (self.linkPreviews[messageId] ||
			[self.linkPreviewsRequested containsObject:messageId])
			continue;
		[self.linkPreviewsRequested addObject:messageId];

		[[TGClient shared] linkPreviewForText:text withOptions:nil
								   completion:^(NSDictionary *preview){
			TGChatViewController *me = weakSelf;
			if (!me || ![preview[@"url"] length])
				return;
			me.linkPreviews[messageId] = preview;
			NSNumber *photo = preview[@"photoFileId"];
			if ([photo isKindOfClass:NSNumber.class] && photo.integerValue != 0 &&
				!me.images[photo] && ![me.imagesRequested containsObject:photo]){
				[me.imagesRequested addObject:photo];
				CGFloat limit = [me pictureDecodeLimit];
				[[TGClient shared] downloadFile:photo.integerValue completion:^(NSString *path){
					if (!path.length)
						return;
					dispatch_async(TGImageDecodeQueue(), ^{
						UIImage *image = TGDecodeThumbnail(path, limit);
						if (!image)
							return;
						dispatch_async(dispatch_get_main_queue(), ^{
							TGChatViewController *inner = weakSelf;
							if (!inner)
								return;
							inner.images[photo] = image;
							[inner setNeedsTableReload];
						});
					});
				}];
			}
			[me setNeedsTableReload];
		}];
	}
}

- (NSDictionary *)previewFor:(NSDictionary *)m {
	NSNumber *messageId = [m[@"id"] isKindOfClass:NSNumber.class] ? m[@"id"] : nil;
	return messageId ? self.linkPreviews[messageId] : nil;
}

- (UIImage *)previewImageFor:(NSDictionary *)preview {
	NSNumber *photo = preview[@"photoFileId"];
	return [photo isKindOfClass:NSNumber.class] ? self.images[photo] : nil;
}

- (CGSize)previewSizeFor:(NSDictionary *)m {
	NSDictionary *preview = [self previewFor:m];
	if (!preview)
		return CGSizeZero;
	return [TGLinkPreviewView sizeForPreview:preview
									   image:[self previewImageFor:preview]
									maxWidth:[self bubbleWidthBudget] - 2 * kPadH];
}

/// Chips already known for a message, or nil.
- (NSArray *)chipsFor:(NSDictionary *)m {
	NSNumber *messageId = [m[@"id"] isKindOfClass:NSNumber.class] ? m[@"id"] : nil;
	return messageId ? self.reactionChips[messageId] : nil;
}

- (CGFloat)chipsRowWidthFor:(NSDictionary *)m {
	NSArray *chips = [self chipsFor:m];
	if (!chips.count)
		return 0;

	CGFloat maxW = [self maxBubbleWidthFor:m] - 2 * kPadH;
	CGFloat floorW = [TGReactionChipsView rowHeight] * 2;
	if (maxW < floorW)
		maxW = floorW;

	NSNumber *messageId = [m[@"id"] isKindOfClass:NSNumber.class] ? m[@"id"] : nil;
	NSNumber *cached = messageId ? self.chipsRowWidths[messageId] : nil;
	if (cached)
		return MIN([cached floatValue], maxW);

	CGFloat width = [TGReactionChipsView sizeForChips:chips width:maxW].width;
	if (width < 1)
		return 0;
	if (messageId)
		self.chipsRowWidths[messageId] = @(width);
	return width;
}

- (void)fetchMissingImages {
	__weak typeof(self) weakSelf = self;
	[self fetchMissingReactionChips];
	[self fetchMissingLinkPreviews];

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
			[me setNeedsTableReloadKeepingBottom];
		}];
	}

	self.photoWindow = NSMakeRange(NSNotFound, 0);
	[self fetchVisiblePictures];
}

- (NSRange)visiblePictureWindow {
	NSInteger count = [self displayRowCount];
	if (count <= 0)
		return NSMakeRange(0, 0);

	NSInteger first = NSNotFound;
	NSInteger last = NSNotFound;
	for (NSIndexPath *path in [self.table indexPathsForVisibleRows]){
		if (path.row < 0 || path.row >= count)
			continue;
		if (first == NSNotFound || path.row < first)
			first = path.row;
		if (last == NSNotFound || path.row > last)
			last = path.row;
	}
	if (first == NSNotFound){
		first = MAX(0, count - 12);
		last = count - 1;
	}
	first = MAX(0, first - 3);
	last = MIN(count - 1, last + 3);
	if (last < first)
		return NSMakeRange(0, 0);
	return NSMakeRange((NSUInteger)first, (NSUInteger)(last - first + 1));
}

- (void)fetchVisiblePictures {
	if (![self displayRowCount])
		return;
	NSRange window = [self visiblePictureWindow];
	if (window.location == self.photoWindow.location &&
		window.length == self.photoWindow.length)
		return;
	self.photoWindow = window;

	NSMutableSet *wanted = [NSMutableSet set];
	NSMutableArray *byProximity = [NSMutableArray array];
	NSUInteger centre = window.location + window.length / 2;
	for (NSInteger step = (NSInteger)window.length; step >= 0; step--){
		for (NSInteger side = 0; side < 2; side++){
			NSInteger row = (NSInteger)centre + (side ? step : -step);
			if (row < (NSInteger)window.location ||
				row >= (NSInteger)(window.location + window.length))
				continue;
			for (NSDictionary *m in [self messagesAtRow:row]){
				NSNumber *fileId = [self pictureFileIdFor:m];
				if (!fileId || [wanted containsObject:fileId])
					continue;
				[wanted addObject:fileId];
				[byProximity addObject:fileId];
			}
			if (!step)
				break;
		}
	}
	for (NSDictionary *quoted in [self.quotes allValues]){
		NSNumber *fileId = [self pictureFileIdFor:quoted];
		if (fileId && ![wanted containsObject:fileId]){
			[wanted addObject:fileId];
			[byProximity insertObject:fileId atIndex:0];
		}
	}

	if (byProximity.count > kMaxLivePictures){
		NSRange far = NSMakeRange(0, byProximity.count - kMaxLivePictures);
		[wanted minusSet:[NSSet setWithArray:[byProximity subarrayWithRange:far]]];
		[byProximity removeObjectsInRange:far];
	}

	for (NSNumber *fileId in [self.photoFilesInFlight allObjects]){
		if ([wanted containsObject:fileId])
			continue;
		if ([fileId integerValue] == self.downloadingFileId)
			continue;
		[[TGClient shared] cancelDownloadOfFile:[fileId integerValue] onlyIfPending:NO];
		[self.photoFilesInFlight removeObject:fileId];
		[self.photoFilesCancelled addObject:fileId];
		[self.imagesRequested removeObject:fileId];
	}

	for (NSNumber *fileId in wanted){
		if (self.images[fileId])
			continue;
		if ([self.photoFilesFailed containsObject:fileId])
			continue;
		if ([self.imagesRequested containsObject:fileId])
			continue;
		[self startPictureDownload:fileId];
	}

	[self prunePicturesInUseOrder:byProximity];
}

- (void)prunePicturesInUseOrder:(NSArray *)nearestLast {
	for (NSNumber *fileId in nearestLast){
		[self.imageOrder removeObject:fileId];
		[self.imageOrder addObject:fileId];
	}

	NSUInteger budget = 0;
	NSMutableSet *keep = [NSMutableSet set];
	for (NSNumber *fileId in [self.imageOrder reverseObjectEnumerator]){
		UIImage *image = self.images[fileId];
		if (!image)
			continue;
		NSUInteger cost = TGImageBitmapBytes(image);
		if (keep.count && budget + cost > kPictureMemoryBudget)
			continue;
		budget += cost;
		[keep addObject:fileId];
	}

	for (NSNumber *fileId in [self.images allKeys]){
		if ([keep containsObject:fileId])
			continue;
		[self.images removeObjectForKey:fileId];
		[self.imagesRequested removeObject:fileId];
		[self.imageOrder removeObject:fileId];
	}
	[self dropTileBitmapsOutside:keep];

	if (!TGPerfLogging())
		return;
	NSUInteger tiles = 0;
	for (UIImage *image in [self.tileBitmaps allValues])
		tiles += TGImageBitmapBytes(image);
	NSUInteger thumbs = 0;
	for (id image in [self.minithumbnails allValues])
		if ([image isKindOfClass:[UIImage class]])
			thumbs += TGImageBitmapBytes(image);
	NSUInteger avatars = 0;
	for (UIImage *image in [self.senderAvatars allValues])
		avatars += TGImageBitmapBytes(image);
	NSLog(@"PERF chatmem pictures=%u/%.2f MB tiles=%u/%.2f MB thumbs=%u/%.2f MB avatars=%.2f MB",
			(unsigned)self.images.count, budget / 1048576.0,
			(unsigned)self.tileBitmaps.count, tiles / 1048576.0,
			(unsigned)self.minithumbnails.count, thumbs / 1048576.0,
			avatars / 1048576.0);
}

- (void)dropTileBitmapsOutside:(NSSet *)keep {
	if (!self.tileBitmaps.count)
		return;
	NSMutableSet *live = [NSMutableSet set];
	for (NSNumber *fileId in keep)
		[live addObject:[fileId stringValue]];
	for (NSString *key in [self.tileBitmaps allKeys]){
		NSRange at = [key rangeOfString:@"@"];
		if (at.location == NSNotFound)
			continue;
		if (![live containsObject:[key substringToIndex:at.location]])
			[self.tileBitmaps removeObjectForKey:key];
	}
}

- (CGFloat)pictureDecodeLimit {
	CGFloat scale = [UIScreen mainScreen].scale;
	if (scale < 1.0f)
		scale = 1.0f;
	return MAX(kImageMax, [self bubbleWidthBudget]) * scale;
}

- (void)pictureFailed:(NSNumber *)fileId {
	[self.imagesRequested removeObject:fileId];
	[self.photoFilesFailed addObject:fileId];
	[self refreshRowsShowingFile:fileId withImage:nil];
}

- (void)startPictureDownload:(NSNumber *)fileId {
	if (!fileId)
		return;
	[self.imagesRequested addObject:fileId];
	[self.photoFilesInFlight addObject:fileId];
	[self.photoFilesCancelled removeObject:fileId];

	CGFloat limit = [self pictureDecodeLimit];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[me.photoFilesInFlight removeObject:fileId];
		if ([me.photoFilesCancelled containsObject:fileId]){
			[me.photoFilesCancelled removeObject:fileId];
			[me.imagesRequested removeObject:fileId];
			return;
		}
		if (!path.length){
			[me pictureFailed:fileId];
			return;
		}

		dispatch_async(TGImageDecodeQueue(), ^{
			UIImage *img = nil;
			@autoreleasepool {
				img = TGDecodeThumbnail(path, limit);
				if (!img && [path.pathExtension.lowercaseString isEqualToString:@"webp"])
					img = TGImageWithinPixelLimit(
							[UIImage convertFromWebP:path compressedData:nil error:nil], limit);
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				TGChatViewController *inner = weakSelf;
				if (!inner)
					return;
				if ([inner.photoFilesCancelled containsObject:fileId]){
					[inner.photoFilesCancelled removeObject:fileId];
					[inner.imagesRequested removeObject:fileId];
					return;
				}
				if (!img){
					[inner pictureFailed:fileId];
					return;
				}
				[inner.photoFilesFailed removeObject:fileId];
				inner.images[fileId] = img;
				[inner applyArrivedImage:img forFile:fileId];
			});
		});
	}];
}

- (BOOL)heightDependsOnBitmapForFile:(NSNumber *)fileId {
	for (NSDictionary *m in self.messages){
		NSNumber *pictureId = [self pictureFileIdFor:m];
		if (!pictureId || ![pictureId isEqualToNumber:fileId])
			continue;
		CGSize declared = [self declaredPixelSizeFor:m];
		if (declared.width < 1 || declared.height < 1)
			return YES;
	}
	return NO;
}

- (void)applyArrivedImage:(UIImage *)img forFile:(NSNumber *)fileId {
	if ([self heightDependsOnBitmapForFile:fileId]){
		[self setNeedsTableReloadKeepingBottom];
		return;
	}
	[self refreshRowsShowingFile:fileId withImage:img];
}

- (void)refreshRowsShowingFile:(NSNumber *)fileId withImage:(UIImage *)img {
	NSMutableArray *stale = [NSMutableArray array];
	for (NSIndexPath *path in [self.table indexPathsForVisibleRows]){
		if ([self albumAtRow:path.row]){
			for (NSDictionary *member in [self messagesAtRow:path.row]){
				NSNumber *tileId = [self pictureFileIdFor:member];
				if (tileId && [tileId isEqualToNumber:fileId]){
					[stale addObject:path];
					break;
				}
			}
			continue;
		}
		NSDictionary *m = [self messageAtRow:path.row];
		NSNumber *pictureId = m ? [self pictureFileIdFor:m] : nil;
		if (!pictureId || ![pictureId isEqualToNumber:fileId])
			continue;
		UITableViewCell *raw = [self.table cellForRowAtIndexPath:path];
		if (![raw isKindOfClass:[TGBubbleCell class]] || !img){
			[stale addObject:path];
			continue;
		}
		TGBubbleCell *cell = (TGBubbleCell *)raw;
		CATransition *fade = [CATransition animation];
		fade.duration = 0.2;
		fade.type = kCATransitionFade;
		[cell.picture.layer addAnimation:fade forKey:@"tgPictureFade"];
		cell.picture.image = img;
		cell.picture.backgroundColor = [UIColor clearColor];
	}
	if (stale.count)
		[self.table reloadRowsAtIndexPaths:stale
						  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)updateShortContentInset {
	if (!self.table)
		return;
	UIEdgeInsets insets = self.table.contentInset;
	CGFloat fixed = insets.top - self.shortContentInset;
	CGFloat room = self.table.bounds.size.height - fixed - insets.bottom;
	NSInteger rows = [self displayRowCount];
	if (self.shortContentInset <= 0 && rows * kSystemPlateHeight > room)
		return;
	CGFloat pad = rows ? room - self.table.contentSize.height : 0;
	if (pad < 0)
		pad = 0;
	if (fabsf(pad - self.shortContentInset) < 0.5f)
		return;
	insets.top = fixed + pad;
	self.shortContentInset = pad;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
}

- (void)scrollToBottomAnimated:(BOOL)animated {
	if (![self displayRowCount])
		return;
	NSIndexPath *last = [NSIndexPath indexPathForRow:[self displayRowCount] - 1
										   inSection:0];
	[self.table scrollToRowAtIndexPath:last
					  atScrollPosition:UITableViewScrollPositionBottom animated:animated];
	[self updateScrollDownButton];
}

static const CGFloat kEmptyPlateWidth  = 122.0f;
static const CGFloat kEmptyPlateHeight = 116.0f;

- (void)centreEmptyPlate {
	if (!self.emptyPlate)
		return;
	CGRect history = self.table.frame;
	if (history.size.height < 1)
		return;
	self.emptyPlate.frame = CGRectMake(
			floorf((history.size.width - kEmptyPlateWidth) / 2),
			CGRectGetMinY(history) + self.pinnedBannerInset +
					floorf((history.size.height - self.pinnedBannerInset -
							kEmptyPlateHeight) / 2),
			kEmptyPlateWidth, kEmptyPlateHeight);
}

/// An empty conversation is otherwise a blank wallpaper with no explanation,
/// which reads as a screen that failed to load.
- (void)updateEmptyState {
	BOOL wanted = (self.messages.count == 0);
	if (!wanted && !self.emptyPlate)
		return;

	if (!self.emptyPlate){
		self.emptyPlate = [[UIView alloc] initWithFrame:
				CGRectMake(0, 0, kEmptyPlateWidth, kEmptyPlateHeight)];
		self.emptyPlate.backgroundColor = TGSystemPlateColour();
		self.emptyPlate.layer.cornerRadius = 10;
		self.emptyPlate.userInteractionEnabled = NO;
		self.emptyPlate.alpha = 0.0f;
		self.emptyPlate.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
										   UIViewAutoresizingFlexibleRightMargin |
										   UIViewAutoresizingFlexibleTopMargin |
										   UIViewAutoresizingFlexibleBottomMargin;
		[self.view insertSubview:self.emptyPlate aboveSubview:self.wallpaperView];

		UIImage *glyph = [UIImage imageNamed:@"ConversationIconPlain.png"];
		if (!glyph)
			glyph = [self plainConversationGlyph];
		self.emptyGlyph = [[UIImageView alloc] initWithImage:glyph];
		self.emptyGlyph.frame = CGRectMake(
				floorf((kEmptyPlateWidth - glyph.size.width) / 2), 23,
				glyph.size.width, glyph.size.height);
		[self.emptyPlate addSubview:self.emptyGlyph];

		self.emptyLabel = [[UILabel alloc] init];
		self.emptyLabel.numberOfLines = 0;
		self.emptyLabel.lineBreakMode = NSLineBreakByWordWrapping;
		self.emptyLabel.textAlignment = NSTextAlignmentCenter;
		self.emptyLabel.font = [UIFont boldSystemFontOfSize:13];
		self.emptyLabel.textColor = [UIColor whiteColor];
		self.emptyLabel.backgroundColor = [UIColor clearColor];
		self.emptyLabel.userInteractionEnabled = NO;
		[self.emptyPlate addSubview:self.emptyLabel];
	}

	self.emptyLabel.text = self.chatSearchBar
			? @"No messages found"
			: @"No messages here yet...";
	CGSize fits = [self.emptyLabel sizeThatFits:CGSizeMake(110, 1000)];
	self.emptyLabel.frame = CGRectMake(floorf((kEmptyPlateWidth - fits.width) / 2),
									   kEmptyPlateHeight - fits.height - 8,
									   fits.width, fits.height);
	[self centreEmptyPlate];

	BOOL shown = (!self.emptyPlate.hidden && self.emptyPlate.alpha > 0.01f);
	if (wanted == shown)
		return;
	if (wanted){
		self.emptyPlate.hidden = NO;
		[UIView animateWithDuration:0.3 delay:0.0
							options:UIViewAnimationOptionBeginFromCurrentState
						 animations:^{ self.emptyPlate.alpha = 1.0f; } completion:nil];
		return;
	}
	[UIView animateWithDuration:0.3 delay:0.0
						options:UIViewAnimationOptionBeginFromCurrentState
					 animations:^{ self.emptyPlate.alpha = 0.0f; }
					 completion:^(BOOL finished){
		if (finished && self.emptyPlate.alpha < 0.01f)
			self.emptyPlate.hidden = YES;
	}];
}

- (UIImage *)plainConversationGlyph {
	CGSize size = CGSizeMake(47, 39);
	if (UIGraphicsBeginImageContextWithOptions != NULL)
		UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
	else
		UIGraphicsBeginImageContext(size);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
	CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
	CGContextSetLineWidth(ctx, 1.5f);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);

	CGRect body = CGRectMake(1, 1, 45, 30);
	CGFloat radius = 6;
	CGContextBeginPath(ctx);
	CGContextMoveToPoint(ctx, CGRectGetMinX(body) + radius, CGRectGetMinY(body));
	CGContextAddArcToPoint(ctx, CGRectGetMaxX(body), CGRectGetMinY(body),
						   CGRectGetMaxX(body), CGRectGetMaxY(body), radius);
	CGContextAddArcToPoint(ctx, CGRectGetMaxX(body), CGRectGetMaxY(body),
						   CGRectGetMinX(body), CGRectGetMaxY(body), radius);
	CGContextAddArcToPoint(ctx, CGRectGetMinX(body), CGRectGetMaxY(body),
						   CGRectGetMinX(body), CGRectGetMinY(body), radius);
	CGContextAddArcToPoint(ctx, CGRectGetMinX(body), CGRectGetMinY(body),
						   CGRectGetMaxX(body), CGRectGetMinY(body), radius);
	CGContextClosePath(ctx);
	CGContextStrokePath(ctx);

	CGContextBeginPath(ctx);
	CGContextMoveToPoint(ctx, 11, 30.5f);
	CGContextAddLineToPoint(ctx, 23, 30.5f);
	CGContextAddLineToPoint(ctx, 12, 38.5f);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

- (void)setFloatingButton:(UIButton *)button shown:(BOOL)shown {
	if (!button)
		return;
	BOOL onScreen = (!button.hidden && button.alpha > 0.01f);
	if (onScreen == shown)
		return;
	if (shown){
		button.alpha = 0.0f;
		button.hidden = NO;
		[UIView animateWithDuration:0.3 delay:0.0
							options:UIViewAnimationOptionBeginFromCurrentState
						 animations:^{ button.alpha = 1.0f; } completion:nil];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[UIView animateWithDuration:0.2 delay:0.0
						options:UIViewAnimationOptionBeginFromCurrentState
					 animations:^{ button.alpha = 0.0f; }
					 completion:^(BOOL finished){
		if (!finished || button.alpha > 0.01f)
			return;
		button.hidden = YES;
		[weakSelf layoutFloatingButtons];
	}];
}

- (void)layoutFloatingButtons {
	CGFloat right = self.view.bounds.size.width - kFloatingButtonSide - kFloatingButtonGap;
	CGFloat bottom = CGRectGetMinY(self.inputBar.frame) - self.composeBannerInset -
			kFloatingButtonGap;
	NSArray *column = @[self.scrollDownButton ?: (id)[NSNull null],
						self.mentionButton ?: (id)[NSNull null],
						self.reactionButton ?: (id)[NSNull null]];
	for (id entry in column){
		if (![entry isKindOfClass:UIButton.class])
			continue;
		UIButton *button = entry;
		if (button.hidden && button.alpha < 0.01f)
			continue;
		bottom -= kFloatingButtonSide;
		button.frame = CGRectMake(right, bottom,
								  kFloatingButtonSide, kFloatingButtonSide);
		bottom -= kFloatingButtonGap;
		[self.view bringSubviewToFront:button];
	}
}

/// Every client puts a way back to the newest message once you have scrolled
/// away from it; without one a long history is a one-way trip.
- (void)updateScrollDownButton {
	BOOL wanted = (self.messages.count > 0) && ![self historyIsAtBottom];

	if (!wanted && !self.scrollDownButton)
		return;

	if (!self.scrollDownButton){
		self.scrollDownButton = [UIButton buttonWithType:UIButtonTypeCustom];
		self.scrollDownButton.frame = CGRectMake(0, 0, kFloatingButtonSide,
												 kFloatingButtonSide);
		[self.scrollDownButton setBackgroundImage:
				[UIImage imageNamed:@"ConversationScrollDown.png"]
										 forState:UIControlStateNormal];
		[self.scrollDownButton setBackgroundImage:
				[UIImage imageNamed:@"ConversationScrollDown_Highlighted.png"]
										 forState:UIControlStateHighlighted];
		self.scrollDownButton.showsTouchWhenHighlighted = NO;
		self.scrollDownButton.adjustsImageWhenHighlighted = NO;
		self.scrollDownButton.layer.shadowColor = [UIColor blackColor].CGColor;
		self.scrollDownButton.layer.shadowOffset = CGSizeMake(0, 1);
		self.scrollDownButton.layer.shadowRadius = 1.0f;
		self.scrollDownButton.layer.shadowOpacity = 0.25f;
		self.scrollDownButton.layer.shadowPath =
				[UIBezierPath bezierPathWithRoundedRect:
						CGRectMake(0, 0, kFloatingButtonSide, kFloatingButtonSide)
										   cornerRadius:5.0f].CGPath;
		self.scrollDownButton.hidden = YES;
		self.scrollDownButton.alpha = 0.0f;
		self.scrollDownButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
												 UIViewAutoresizingFlexibleTopMargin;
		[self.scrollDownButton addTarget:self action:@selector(scrollDownTapped)
					   forControlEvents:UIControlEventTouchUpInside];
		[self.view addSubview:self.scrollDownButton];
	}
	[self setFloatingButton:self.scrollDownButton shown:wanted];
	[self layoutFloatingButtons];
}

- (BOOL)historyIsAtBottom {
	CGFloat fromBottom = self.table.contentSize.height -
			(self.table.contentOffset.y + self.table.bounds.size.height);
	return (fromBottom <= 220);
}

- (void)scrollDownTapped {
	[self scrollToBottomAnimated:YES];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != self.table)
		return;
	[self updateScrollDownButton];
	[self markVisibleMessagesRead];
	[self fetchVisiblePictures];
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

	if (self.editingId != 0){
		[[TGClient shared] editMessage:self.editingId inChat:self.chatId text:text];
	} else {
		NSDictionary *options = [self sendOptionsDictionary];
		if (self.markdownComposing && !options){
			[[TGClient shared] sendMarkdown:text toChat:self.chatId
									 thread:self.threadId replyTo:self.replyToId];
		} else if (self.markdownComposing && options){
			[TGSnackbar showInView:self.view
							  text:@"Sent as plain text: formatting needs a plain send"
						   seconds:3 onCommit:nil];
			[[TGClient shared] sendText:text toChat:self.chatId
								 thread:self.threadId replyTo:self.replyToId
								options:options completion:nil];
		} else if (options)
			[[TGClient shared] sendText:text toChat:self.chatId
								 thread:self.threadId replyTo:self.replyToId
								options:options completion:nil];
		else
			[[TGClient shared] sendText:text toChat:self.chatId
								 thread:self.threadId replyTo:self.replyToId];
	}

	if (self.scheduledSendDate != 0 || self.scheduleWhenOnline){
		self.scheduledSendDate = 0;
		self.scheduleWhenOnline = NO;
		[self loadScheduledMessages];
	}

	[[TGClient shared] clearDraftInChat:self.chatId thread:self.threadId];
	[self clearComposeState];

	// TDLib echoes the message back as an update; refresh shortly after.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		[self reload];
	});
}

/// Telegram puts the chat's picture top right, and it opens the profile.
- (void)buildAvatarButton {
	CGFloat side = 35;
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(0, 0, side, side);
	button.layer.cornerRadius = 4.0f;
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
	CGFloat avatarPixels = side * [UIScreen mainScreen].scale;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		if (!path.length)
			return;
		dispatch_async(TGImageDecodeQueue(), ^{
			UIImage *photo = TGDecodeThumbnail(path, avatarPixels);
			if (!photo)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				[button setImage:photo forState:UIControlStateNormal];
			});
		});
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
		[me buildChannelActionBar];
		(void)isChannel;
	}];
}

- (void)buildChannelActionBar {
	CGRect b = self.view.bounds;
	UIView *bar = [[UIView alloc] initWithFrame:
			CGRectMake(0, b.size.height - kInputHeight, b.size.width, kInputHeight)];
	bar.backgroundColor = [[TGTheme shared] inputBarColour];
	bar.autoresizingMask = UIViewAutoresizingFlexibleWidth |
						   UIViewAutoresizingFlexibleTopMargin;
	bar.clipsToBounds = NO;

	UIImage *strip = [UIImage imageNamed:@"ConversationInputPanel_Background"];
	if (strip){
		UIImageView *stripView = [[UIImageView alloc] initWithFrame:
				CGRectMake(0, 0, b.size.width, kInputHeight)];
		stripView.image = [strip stretchableImageWithLeftCapWidth:0 topCapHeight:0];
		stripView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
									 UIViewAutoresizingFlexibleHeight;
		stripView.userInteractionEnabled = NO;
		[bar addSubview:stripView];
	}

	UIImage *shadow = [UIImage imageNamed:@"ChatInputContainer_Shadow"];
	if (shadow){
		UIImageView *shadowView = [[UIImageView alloc] initWithFrame:
				CGRectMake(0, -shadow.size.height, b.size.width, shadow.size.height)];
		shadowView.image = [shadow stretchableImageWithLeftCapWidth:0 topCapHeight:0];
		shadowView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
									  UIViewAutoresizingFlexibleBottomMargin;
		shadowView.userInteractionEnabled = NO;
		[bar addSubview:shadowView];
	} else {
		UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 1)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		hair.userInteractionEnabled = NO;
		[bar addSubview:hair];
	}

	UIButton *action = [UIButton buttonWithType:UIButtonTypeCustom];
	action.frame = CGRectMake(0, 0, b.size.width, kInputHeight);
	action.autoresizingMask = UIViewAutoresizingFlexibleWidth |
							  UIViewAutoresizingFlexibleHeight;
	action.backgroundColor = [UIColor clearColor];
	action.titleLabel.font = [UIFont systemFontOfSize:17];
	UIColor *accent = [[TGTheme shared] accentColour];
	[action setTitleColor:accent forState:UIControlStateNormal];
	[action setTitleColor:[accent colorWithAlphaComponent:0.4f]
				 forState:UIControlStateHighlighted];
	[action addTarget:self action:@selector(muteFromChat:)
	 forControlEvents:UIControlEventTouchUpInside];
	[bar addSubview:action];

	self.channelActionButton = action;
	self.channelMuted = [[TGClient shared] isChatMuted:self.chatId];
	[self updateChannelActionTitle];

	[self.view addSubview:bar];
}

- (void)updateChannelActionTitle {
	[self.channelActionButton setTitle:(self.channelMuted ? @"Unmute" : @"Mute")
							  forState:UIControlStateNormal];
}

- (void)muteFromChat:(UIButton *)button {
	(void)button;
	self.channelMuted = !self.channelMuted;
	[[TGClient shared] setChat:self.chatId
				muteForSeconds:(self.channelMuted ? TGNotificationMuteForever : 0)];
	[self updateChannelActionTitle];
}

#pragma mark - photo albums

- (BOOL)messageCanTile:(NSDictionary *)m {
	if ([m[@"service"] boolValue])
		return NO;
	NSString *album = m[@"albumId"];
	if (![album isKindOfClass:NSString.class] || !album.length ||
		[album isEqualToString:@"0"])
		return NO;
	if (![m[@"id"] isKindOfClass:NSNumber.class])
		return NO;
	NSString *kind = m[@"kind"];
	return [kind isEqualToString:@"messagePhoto"] ||
		   [kind isEqualToString:@"messageVideo"] ||
		   [kind isEqualToString:@"messageAnimation"];
}

- (void)setMessages:(NSArray *)messages {
	_messages = messages;
	[self.mosaics removeAllObjects];
	[self.tileSizes removeAllObjects];

	NSMutableArray *rows = [NSMutableArray arrayWithCapacity:messages.count];
	NSMutableDictionary *albums = [NSMutableDictionary dictionary];
	NSMutableDictionary *rowById = [NSMutableDictionary dictionary];

	NSUInteger index = 0;
	while (index < messages.count){
		NSDictionary *head = messages[index];
		NSUInteger run = 1;
		if ([self messageCanTile:head]){
			NSString *album = head[@"albumId"];
			while (index + run < messages.count && run < TGMosaicMaxItems){
				NSDictionary *next = messages[index + run];
				if (![self messageCanTile:next] ||
					![next[@"albumId"] isEqualToString:album] ||
					[next[@"outgoing"] boolValue] != [head[@"outgoing"] boolValue])
					break;
				run++;
			}
		}

		NSNumber *row = @(rows.count);
		[rows addObject:@(index)];
		if (run > 1){
			NSArray *members = [messages subarrayWithRange:NSMakeRange(index, run)];
			albums[row] = members;
			for (NSDictionary *member in members)
				if ([member[@"id"] isKindOfClass:NSNumber.class])
					rowById[member[@"id"]] = row;
		} else if ([head[@"id"] isKindOfClass:NSNumber.class]){
			rowById[head[@"id"]] = row;
		}
		index += run;
	}

	self.displayRows = rows;
	self.albumsByRow = albums;
	self.rowByMessageId = rowById;
}

- (NSInteger)displayRowCount {
	return (NSInteger)self.displayRows.count;
}

- (NSDictionary *)messageAtRow:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.displayRows.count)
		return nil;
	NSUInteger index = [self.displayRows[row] unsignedIntegerValue];
	return index < self.messages.count ? self.messages[index] : nil;
}

- (NSArray *)messagesAtRow:(NSInteger)row {
	NSArray *album = [self albumAtRow:row];
	if (album)
		return album;
	NSDictionary *m = [self messageAtRow:row];
	return m ? @[m] : @[];
}

- (NSArray *)albumAtRow:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.displayRows.count)
		return nil;
	return self.albumsByRow[@(row)];
}

- (NSInteger)rowForMessageId:(int64_t)messageId {
	NSNumber *row = self.rowByMessageId[@(messageId)];
	return row ? [row integerValue] : NSNotFound;
}

- (CGSize)mosaicBoundsFor:(NSDictionary *)m {
	CGSize maxDimensions = TGChatIsPad() ? CGSizeMake(440, 440)
										 : CGSizeMake(300, 380);
	CGFloat budget = [self maxBubbleWidthFor:m] - 2 * kPadH;
	if (budget < kMosaicMinTileSide)
		budget = kMosaicMinTileSide;
	CGFloat scale = MIN(1.0f, budget / MAX(1.0f, maxDimensions.width));
	return CGSizeMake(floorf(maxDimensions.width * scale),
					  floorf(maxDimensions.height * scale));
}

- (NSDictionary *)mosaicForRow:(NSInteger)row {
	NSArray *album = [self albumAtRow:row];
	if (album.count < 2)
		return nil;

	NSNumber *key = album[0][@"id"];
	if (![key isKindOfClass:NSNumber.class])
		return nil;
	NSDictionary *cached = self.mosaics[key];
	if (cached)
		return cached;

	CGSize sizes[TGMosaicMaxItems];
	NSUInteger count = MIN(album.count, (NSUInteger)TGMosaicMaxItems);
	for (NSUInteger i = 0; i < count; i++){
		CGSize declared = [self declaredPixelSizeFor:album[i]];
		if (declared.width < 1 || declared.height < 1)
			declared = CGSizeMake(256, 256);
		sizes[i] = declared;
	}

	TGMosaicTile tiles[TGMosaicMaxItems];
	CGSize total = CGSizeZero;
	NSUInteger laid = TGMosaicLayoutTiles(sizes, count,
										  [self mosaicBoundsFor:album[0]],
										  kAlbumGap, NO,
										  tiles, TGMosaicMaxItems, &total);
	if (laid < 2)
		return nil;

	NSMutableArray *frames = [NSMutableArray arrayWithCapacity:laid];
	for (NSUInteger i = 0; i < laid; i++){
		[frames addObject:[NSValue valueWithCGRect:tiles[i].frame]];
		NSNumber *memberId = album[i][@"id"];
		if ([memberId isKindOfClass:NSNumber.class])
			self.tileSizes[memberId] = [NSValue valueWithCGSize:tiles[i].frame.size];
	}

	NSDictionary *mosaic = @{@"size"   : [NSValue valueWithCGSize:total],
							 @"frames" : frames};
	self.mosaics[key] = mosaic;
	return mosaic;
}

- (CGSize)tileSizeForMessage:(NSDictionary *)m {
	NSNumber *messageId = [m[@"id"] isKindOfClass:NSNumber.class] ? m[@"id"] : nil;
	if (!messageId)
		return CGSizeZero;
	NSValue *known = self.tileSizes[messageId];
	if (known)
		return [known CGSizeValue];
	NSNumber *row = self.rowByMessageId[messageId];
	if (!row || !self.albumsByRow[row])
		return CGSizeZero;
	[self mosaicForRow:[row integerValue]];
	known = self.tileSizes[messageId];
	return known ? [known CGSizeValue] : CGSizeZero;
}

- (CGFloat)mosaicHeightForRow:(NSInteger)row {
	NSDictionary *mosaic = [self mosaicForRow:row];
	return mosaic ? [mosaic[@"size"] CGSizeValue].height : 0;
}

- (CGSize)imageSizeForRow:(NSInteger)row {
	NSDictionary *m = [self messageAtRow:row];
	return m ? [self imageSizeFor:m] : CGSizeZero;
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
		[self endDownloadHUDForFile:[docId integerValue]];
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
	NSInteger row = [self rowForMessageId:messageId];
	if (row == NSNotFound)
		return NO;

	NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
	[self.table scrollToRowAtIndexPath:path
					  atScrollPosition:UITableViewScrollPositionMiddle
							  animated:YES];
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		TGChatViewController *me = weakSelf;
		if (!me || me.actionsSheet)
			return;
		[me setPressedRow:row];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
			TGChatViewController *later = weakSelf;
			if (later && later.pressedRow == row)
				[later setPressedRow:-1];
		});
	});
	return YES;
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
		const CGFloat side = 100.0f;
		self.downloadHUD = [[UIView alloc] initWithFrame:CGRectMake(0, 0, side, side)];
		self.downloadHUD.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7f];
		self.downloadHUD.layer.cornerRadius = 12;
		self.downloadHUD.userInteractionEnabled = NO;
		self.downloadHUD.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
											UIViewAutoresizingFlexibleRightMargin |
											UIViewAutoresizingFlexibleTopMargin |
											UIViewAutoresizingFlexibleBottomMargin;

		self.downloadSpinner = [[UIActivityIndicatorView alloc]
				initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
		self.downloadSpinner.center = CGPointMake(side / 2, side / 2 - 8);
		[self.downloadHUD addSubview:self.downloadSpinner];

		self.downloadPercent = [[UILabel alloc] initWithFrame:
				CGRectMake(0, side - 30, side, 20)];
		self.downloadPercent.textAlignment = NSTextAlignmentCenter;
		self.downloadPercent.font = [UIFont boldSystemFontOfSize:15];
		self.downloadPercent.textColor = [UIColor whiteColor];
		self.downloadPercent.backgroundColor = [UIColor clearColor];
		[self.downloadHUD addSubview:self.downloadPercent];
	}
	self.downloadPercent.text = @"0%";
	self.downloadHUD.center = CGPointMake(floorf(self.view.bounds.size.width / 2),
										  floorf(self.view.bounds.size.height / 2));
	self.downloadHUD.alpha = 0.0f;
	self.downloadHUD.hidden = NO;
	[self.downloadSpinner startAnimating];
	[self.view addSubview:self.downloadHUD];
	[UIView animateWithDuration:0.3 delay:0.0
						options:UIViewAnimationOptionBeginFromCurrentState
					 animations:^{ self.downloadHUD.alpha = 1.0f; } completion:nil];

	__weak typeof(self) weakSelf = self;
	[TGClient shared].onFileProgress = ^(NSInteger updatedId, float progress){
		TGChatViewController *me = weakSelf;
		if (!me || updatedId != me.downloadingFileId)
			return;
		me.downloadPercent.text = [NSString stringWithFormat:@"%d%%",
				(int)(progress * 100)];
	};
}

- (void)endDownloadHUDForFile:(NSInteger)fileId {
	if (fileId != self.downloadingFileId)
		return;
	[self endDownloadHUD];
}

- (void)endDownloadHUD {
	self.downloadingFileId = 0;
	[TGClient shared].onFileProgress = nil;
	if (!self.downloadHUD || self.downloadHUD.hidden)
		return;
	UIView *hud = self.downloadHUD;
	UIActivityIndicatorView *spinner = self.downloadSpinner;
	[UIView animateWithDuration:0.3 delay:0.0
						options:UIViewAnimationOptionBeginFromCurrentState
					 animations:^{ hud.alpha = 0.0f; }
					 completion:^(BOOL finished){
		if (!finished || hud.alpha > 0.01f)
			return;
		[spinner stopAnimating];
		hud.hidden = YES;
		[hud removeFromSuperview];
	}];
}

#pragma mark - pinned message

static UIImage *TGPinnedBadgeImage(void) {
	static UIImage *badge = nil;
	if (!badge){
		UIImage *raw = [UIImage imageNamed:@"DialogListUnreadBadge.png"];
		badge = [raw stretchableImageWithLeftCapWidth:(int)(raw.size.width / 2)
										 topCapHeight:(int)(raw.size.height / 2)];
	}
	return badge;
}

static UIImage *TGPinnedBadgeGlyph(void) {
	static UIImage *glyph = nil;
	if (glyph)
		return glyph;

	CGSize size = CGSizeMake(11, 13);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	CGContextFillEllipseInRect(ctx, CGRectMake(1.5f, 0, 8, 8));
	CGContextMoveToPoint(ctx, 3.5f, 7);
	CGContextAddLineToPoint(ctx, 7.5f, 7);
	CGContextAddLineToPoint(ctx, 5.5f, 13);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);
	glyph = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return glyph;
}

/// A strip under the navigation bar, the way clients surface what is pinned.
- (void)loadPinnedMessage {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] pinnedMessageForChat:self.chatId completion:^(NSDictionary *m){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSString *text = [m[@"text"] isKindOfClass:NSString.class] ? m[@"text"] : nil;
		NSNumber *messageId = m[@"id"];
		me.pinnedMessageId = [messageId isKindOfClass:NSNumber.class]
				? messageId.longLongValue : 0;
		me.pinnedMessage = [m isKindOfClass:NSDictionary.class] ? m : nil;
		if (!text.length && me.pinnedMessageId == 0){
			[me hidePinnedBanner];
			return;
		}
		[me showPinnedBanner:(text.length ? text : (m[@"kind"] ?: @"Message"))];
	}];
}

- (void)hidePinnedBanner {
	if (!self.pinnedBanner)
		return;
	[self.pinnedBanner removeFromSuperview];
	self.pinnedBanner = nil;
	UIEdgeInsets insets = self.table.contentInset;
	insets.top -= self.pinnedBannerInset;
	self.pinnedBannerInset = 0;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
	[self centreEmptyPlate];
	[self updateShortContentInset];
}

- (void)showPinnedBanner:(NSString *)text {
	[self hidePinnedBanner];
	CGRect b = self.view.bounds;
	const CGFloat height = 39;
	UIControl *banner = [[UIControl alloc] initWithFrame:
			CGRectMake(0, 0, b.size.width, height)];
	banner.backgroundColor = [[TGTheme shared] inputBarColour];
	banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[banner addTarget:self action:@selector(pinnedBannerTapped)
	 forControlEvents:UIControlEventTouchUpInside];
	[banner addTarget:self action:@selector(pinnedBannerPressed:)
	 forControlEvents:UIControlEventTouchDown];
	[banner addTarget:self action:@selector(pinnedBannerReleased:)
	 forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
					  UIControlEventTouchCancel];
	[banner addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(pinnedBannerHeld:)]];

	const CGFloat badgeWidth = 27;
	const CGFloat badgeHeight = 21;
	UIImageView *badge = [[UIImageView alloc] initWithImage:TGPinnedBadgeImage()];
	badge.frame = CGRectMake(9, (height - 1 - badgeHeight) / 2, badgeWidth, badgeHeight);
	[banner addSubview:badge];

	UIImageView *glyph = [[UIImageView alloc] initWithImage:TGPinnedBadgeGlyph()];
	glyph.frame = CGRectMake((badgeWidth - glyph.image.size.width) / 2,
							 (badgeHeight - glyph.image.size.height) / 2 - 1,
							 glyph.image.size.width, glyph.image.size.height);
	[badge addSubview:glyph];

	const CGFloat textLeft = 9 + badgeWidth + 8;
	UILabel *caption = [[UILabel alloc] initWithFrame:
			CGRectMake(textLeft, 3, b.size.width - textLeft - 10, 16)];
	caption.text = @"Pinned message";
	caption.font = [UIFont boldSystemFontOfSize:13];
	caption.textColor = [UIColor colorWithRed:0.302f green:0.408f blue:0.549f alpha:1.0f];
	caption.backgroundColor = [UIColor clearColor];
	caption.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[banner addSubview:caption];

	UILabel *body = [[UILabel alloc] initWithFrame:
			CGRectMake(textLeft, 19, b.size.width - textLeft - 10, 17)];
	body.text = text;
	body.font = [UIFont systemFontOfSize:13];
	body.textColor = [UIColor colorWithWhite:0.533f alpha:1.0f];
	body.backgroundColor = [UIColor clearColor];
	body.numberOfLines = 1;
	body.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[banner addSubview:body];

	UIView *hair = [[UIView alloc] initWithFrame:
			CGRectMake(0, height - 1, b.size.width, 1)];
	hair.backgroundColor = [UIColor colorWithRed:0.835f green:0.871f blue:0.898f alpha:1.0f];
	hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[banner addSubview:hair];

	UIView *litPlate = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, b.size.width, height - 1)];
	litPlate.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.08f];
	litPlate.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	litPlate.userInteractionEnabled = NO;
	litPlate.alpha = 0.0f;
	litPlate.tag = kPinnedBannerHighlightTag;
	[banner addSubview:litPlate];

	[self.view addSubview:banner];
	self.pinnedBanner = banner;
	self.pinnedBannerInset = height;

	// Push the message list down so the banner does not cover the first row.
	UIEdgeInsets insets = self.table.contentInset;
	insets.top += height;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
	[self centreEmptyPlate];
	[self updateShortContentInset];
}

- (void)pinnedBannerPressed:(UIControl *)banner {
	[banner viewWithTag:kPinnedBannerHighlightTag].alpha = 1.0f;
}

- (void)pinnedBannerReleased:(UIControl *)banner {
	UIView *lit = [banner viewWithTag:kPinnedBannerHighlightTag];
	[UIView animateWithDuration:0.2 delay:0.0
						options:UIViewAnimationOptionBeginFromCurrentState
					 animations:^{ lit.alpha = 0.0f; } completion:nil];
}

- (void)pinnedBannerTapped {
	if (self.pinnedMessageId == 0)
		return;
	if ([self scrollToMessageId:self.pinnedMessageId])
		return;

	if ([self insertPinnedMessagePlaceholder]){
		[self.table reloadData];
		[self scrollToMessageId:self.pinnedMessageId];
	}
	[self loadDeeperHistoryAndScrollTo:self.pinnedMessageId];
}

- (BOOL)insertPinnedMessagePlaceholder {
	NSDictionary *pinned = self.pinnedMessage;
	if (![pinned[@"id"] isKindOfClass:NSNumber.class])
		return NO;

	NSMutableArray *merged = [self.messages mutableCopy] ?: [NSMutableArray array];
	NSInteger index = 0;
	while (index < (NSInteger)merged.count &&
		   [merged[index][@"id"] longLongValue] < self.pinnedMessageId)
		index++;
	[merged insertObject:pinned atIndex:index];
	self.messages = merged;
	self.anchorToBottom = NO;
	return YES;
}

- (void)loadDeeperHistoryAndScrollTo:(int64_t)messageId {
	if (self.deeperHistoryPending)
		return;
	self.deeperHistoryPending = YES;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] historyForChat:self.chatId
							   thread:self.threadId
								limit:400
						   completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		me.deeperHistoryPending = NO;
		if (messages.count > me.messages.count){
			me.messages = [me messagesMerging:messages];
			me.anchorToBottom = NO;
			[me.table reloadData];
			[me fetchMissingImages];
			[me resolveUnknownSenders];
			[me fetchMissingQuotes];
		}
		[me scrollToMessageId:messageId];
	}];
}

- (NSArray *)messagesMerging:(NSArray *)incoming {
	NSMutableDictionary *byId = [NSMutableDictionary dictionary];
	NSMutableArray *unkeyed = [NSMutableArray array];
	for (NSArray *source in @[self.messages ?: @[], incoming ?: @[]]){
		for (NSDictionary *m in source){
			if ([m[@"id"] isKindOfClass:NSNumber.class] && [m[@"id"] longLongValue] != 0)
				byId[m[@"id"]] = m;
			else
				[unkeyed addObject:m];
		}
	}
	NSArray *keys = [[byId allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b){
		int64_t left = a.longLongValue, right = b.longLongValue;
		if (left == right) return NSOrderedSame;
		return left < right ? NSOrderedAscending : NSOrderedDescending;
	}];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:byId.count + unkeyed.count];
	for (NSNumber *key in keys)
		[out addObject:byId[key]];
	[out addObjectsFromArray:unkeyed];
	return out;
}

/// Holding the banner is where "Unpin all" lives, behind the red button of a
/// confirmation - it is not something a stray tap may do.
- (void)pinnedBannerHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Pinned messages"
													   delegate:self
											  cancelButtonTitle:@"Cancel"
										 destructiveButtonTitle:@"Unpin All Messages"
											  otherButtonTitles:nil];
	sheet.tag = kPinnedSheetTag;
	[sheet showInView:self.view];
}

- (void)unpinEverything {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] unpinAllMessagesInChat:self.chatId completion:^(BOOL ok){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[me showAlertTitle:@"" message:@"The pinned messages could not be cleared."];
			return;
		}
		me.pinnedMessageId = 0;
		[me hidePinnedBanner];
		[me reload];
	}];
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

- (void)searchChatForTag:(NSString *)tag {
	if (!tag.length)
		return;
	if (!self.chatSearchBar)
		[self toggleChatSearch];
	if (!self.chatSearchBar)
		return;
	self.chatSearchBar.text = tag;
	[self searchBar:self.chatSearchBar textDidChange:tag];
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
- (void)refreshAvatarForUser:(NSNumber *)key {
	UIImage *avatar = self.senderAvatars[key];
	if (!avatar)
		return;
	for (NSIndexPath *path in [self.table indexPathsForVisibleRows]){
		NSDictionary *m = [self messageAtRow:path.row];
		if (!m || [m[@"senderId"] longLongValue] != [key longLongValue])
			continue;
		UITableViewCell *raw = [self.table cellForRowAtIndexPath:path];
		if (![raw isKindOfClass:[TGBubbleCell class]])
			continue;
		TGBubbleCell *cell = (TGBubbleCell *)raw;
		if (cell.senderAvatar.hidden)
			continue;
		CATransition *fade = [CATransition animation];
		fade.duration = 0.2;
		fade.type = kCATransitionFade;
		[cell.senderAvatar.layer addAnimation:fade forKey:@"tgAvatarFade"];
		cell.senderAvatar.image = avatar;
	}
}

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
		CGFloat sidePixels = kAvatarSide * [UIScreen mainScreen].scale;
		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			if (!path.length)
				return;
			dispatch_async(TGImageDecodeQueue(), ^{
				UIImage *photo = TGDecodeThumbnail(path, sidePixels);
				if (!photo)
					return;
				UIImage *sized = TGImageDrawnAtPointSize(photo,
						CGSizeMake(kAvatarSide, kAvatarSide));
				dispatch_async(dispatch_get_main_queue(), ^{
					TGChatViewController *me = weakSelf;
					if (!me)
						return;
					me.senderAvatars[key] = sized;
					[me refreshAvatarForUser:key];
				});
			});
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

- (TGComposeMode)composeMode {
	if (self.editingId != 0)
		return TGComposeModeEdit;
	if (self.replyToId != 0)
		return TGComposeModeReply;
	return TGComposeModeNew;
}

- (void)setComposeMode:(TGComposeMode)mode messageId:(int64_t)messageId {
	self.replyToId = (mode == TGComposeModeReply) ? messageId : 0;
	self.editingId = (mode == TGComposeModeEdit) ? messageId : 0;
}

/// Back to composing a plain message: no reply, no edit, no banner. Also
/// missing, and reached from the recorder and from the banner's own cancel.
- (void)clearComposeState {
	// Cancelling an edit has to take the text it prefilled with it, otherwise
	// the draft of a message already sent is left sitting in the composer.
	if (self.composeMode == TGComposeModeEdit)
		self.input.text = @"";
	[self setComposeMode:TGComposeModeNew messageId:0];
	self.scheduledSendDate = 0;
	self.scheduleWhenOnline = NO;
	[self.sendButton setTitle:@"Send" forState:UIControlStateNormal];
	[self setComposeBannerShown:NO];
	[self inputChanged];
}

- (void)setComposeBannerShown:(BOOL)shown {
	if (!self.composeBanner)
		return;
	BOOL onScreen = (!self.composeBanner.hidden && self.composeBanner.alpha > 0.01f);
	if (onScreen == shown)
		return;

	UIEdgeInsets insets = self.table.contentInset;
	insets.bottom += shown ? kComposeBannerHeight : -self.composeBannerInset;
	self.composeBannerInset = shown ? kComposeBannerHeight : 0.0f;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;

	if (shown){
		self.composeBanner.frame = CGRectMake(0,
				CGRectGetMinY(self.inputBar.frame) - kComposeBannerHeight,
				self.view.bounds.size.width, kComposeBannerHeight);
		self.composeBanner.alpha = 0.0f;
		self.composeBanner.hidden = NO;
		[self.view bringSubviewToFront:self.composeBanner];
	}
	[self layoutFloatingButtons];

	[UIView animateWithDuration:0.2 delay:0.0
						options:UIViewAnimationOptionBeginFromCurrentState
					 animations:^{ self.composeBanner.alpha = shown ? 1.0f : 0.0f; }
					 completion:^(BOOL finished){
		if (finished && self.composeBanner.alpha < 0.01f)
			self.composeBanner.hidden = YES;
	}];
}

/// A strip above the composer saying what the next message will be: a reply,
/// an edit, or a recording in progress. Declared and used from three places
/// but never written, so holding the microphone brought the app down.
- (void)showComposeBanner:(NSString *)text {
	if (!self.composeBanner){
		CGRect b = self.view.bounds;
		self.composeBanner = [[UIView alloc] initWithFrame:
				CGRectMake(0, CGRectGetMinY(self.inputBar.frame) - kComposeBannerHeight,
						   b.size.width, kComposeBannerHeight)];
		self.composeBanner.backgroundColor = [[TGTheme shared] inputBarColour];
		self.composeBanner.alpha = 0.0f;
		self.composeBanner.hidden = YES;
		self.composeBanner.autoresizingMask = UIViewAutoresizingFlexibleWidth |
											  UIViewAutoresizingFlexibleTopMargin;

		UILabel *label = [[TGEmojiLabel alloc] initWithFrame:
				CGRectMake(10, 4, b.size.width - 56, 20)];
		label.font = [UIFont systemFontOfSize:13];
		label.textColor = [[TGTheme shared] accentColour];
		label.backgroundColor = [UIColor clearColor];
		label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.composeBanner addSubview:label];

		UIView *hair = [[UIView alloc] initWithFrame:
				CGRectMake(0, 0, b.size.width, kRetinaPixel)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		hair.userInteractionEnabled = NO;
		[self.composeBanner addSubview:hair];

		UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
		cancel.frame = CGRectMake(b.size.width - 44, 0, 44, kComposeBannerHeight);
		cancel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[cancel setTitle:@"\u00d7" forState:UIControlStateNormal];
		[cancel setTitleColor:[[TGTheme shared] secondaryTextColour]
					 forState:UIControlStateNormal];
		[cancel setTitleColor:[[TGTheme shared] accentColour]
					 forState:UIControlStateHighlighted];
		cancel.titleLabel.font = [UIFont systemFontOfSize:22];
		cancel.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 0);
		[cancel addTarget:self action:@selector(clearComposeState)
		 forControlEvents:UIControlEventTouchUpInside];
		[self.composeBanner addSubview:cancel];

		[self.view addSubview:self.composeBanner];
	}

	UILabel *label = (UILabel *)[self.composeBanner.subviews firstObject];
	if ([label isKindOfClass:UILabel.class])
		label.text = text;
	[self setComposeBannerShown:YES];
}

#pragma mark - stickers

/// The full sticker keyboard: recents, favourites and every installed set,
/// over the composer where the system keyboard would be.
- (void)toggleStickerPanel {
	if (self.stickerPanel){
		[self.stickerPanel removeFromSuperview];
		self.stickerPanel = nil;
		[self shiftForKeyboardHeight:0];
		return;
	}

	[self.input resignFirstResponder];

	CGRect b = self.view.bounds;
	BOOL landscape = b.size.width > b.size.height;
	CGFloat height = [TGStickerPanelView preferredHeightForLandscape:landscape];
	TGStickerPanelView *panel = [[TGStickerPanelView alloc] initWithFrame:
			CGRectMake(0, b.size.height - height, b.size.width, height)];
	panel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
							 UIViewAutoresizingFlexibleTopMargin;

	__weak typeof(self) weakSelf = self;
	panel.onStickerPicked = ^(NSDictionary *sticker){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSNumber *fileId = sticker[@"fileId"];
		if (![fileId isKindOfClass:NSNumber.class])
			return;
		[[TGClient shared] sendStickerWithFileId:fileId.integerValue
										  toChat:me.chatId
										  thread:me.threadId];
		[me toggleStickerPanel];
	};
	panel.onCloseRequested = ^{
		TGChatViewController *me = weakSelf;
		if (me.stickerPanel)
			[me toggleStickerPanel];
	};

	[self.view addSubview:panel];
	self.stickerPanel = panel;
	[self shiftForKeyboardHeight:height];
}

#pragma mark - voice

/// Send is for typed text, the microphone for everything else - showing both
/// at once would leave one of them dead.
- (void)inputChanged {
	BOOL hasText = self.input.text.length > 0;
	if (self.sendButton.hidden == hasText){
		UIButton *arriving = hasText ? self.sendButton : self.micButton;
		UIButton *leaving  = hasText ? self.micButton : self.sendButton;
		arriving.alpha = 0.0f;
		arriving.hidden = NO;
		[UIView animateWithDuration:0.15 delay:0.0
							options:UIViewAnimationOptionBeginFromCurrentState
						 animations:^{
			arriving.alpha = 1.0f;
			leaving.alpha = 0.0f;
		} completion:^(BOOL finished){
			if (!finished)
				return;
			leaving.hidden = YES;
			leaving.alpha = 1.0f;
		}];
	}
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
	[[TGClient shared] sendChatAction:@"typing" toChat:self.chatId thread:self.threadId];
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
	[[TGClient shared] sendChatAction:@"recordingVoice" toChat:self.chatId
							   thread:self.threadId];
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
	NSDate *now = [NSDate date];
	if (self.lastTypingSent &&
		[now timeIntervalSinceDate:self.lastTypingSent] < 4.0)
		return;
	self.lastTypingSent = now;
	[[TGClient shared] sendChatAction:@"recordingVoice" toChat:self.chatId
							   thread:self.threadId];
}

- (void)recordFinish {
	[self.recordTimer invalidate];
	self.recordTimer = nil;
	[self hideRecordPanel];
	self.lastTypingSent = nil;
	[[TGClient shared] sendChatAction:@"uploadingVoice" toChat:self.chatId
							   thread:self.threadId];

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
	self.lastTypingSent = nil;
	[[TGClient shared] sendChatAction:@"cancel" toChat:self.chatId thread:self.threadId];
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
	NSDictionary *m = [self messageAtRow:row];
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

- (int64_t)playingMessageId {
	TGMusicPlayer *player = [TGMusicPlayer shared];
	return (player.currentChatId == self.chatId) ? player.currentMessageId : 0;
}

- (CGFloat)playedFraction {
	return [self playingMessageId] ? [TGMusicPlayer shared].playedFraction : 0;
}

- (void)musicPlayerStateChanged {
	if (!self.isViewLoaded || !self.view.window)
		return;
	[self.table reloadData];
}

- (void)musicPlayerProgressed {
	int64_t playing = [self playingMessageId];
	if (!playing)
		return;
	CGFloat played = [self playedFraction];
	for (UITableViewCell *cell in self.table.visibleCells){
		if (![cell isKindOfClass:TGBubbleCell.class])
			continue;
		TGBubbleCell *bubble = (TGBubbleCell *)cell;
		if (bubble.voiceMessageId != playing || bubble.wave.hidden)
			continue;
		bubble.wave.image = [TGIcons waveform:bubble.waveformData
										 size:bubble.wave.bounds.size
									   played:played
									   colour:[[TGTheme shared] accentColour]];
	}
}

#pragma mark - attachments

static const NSInteger kAttachSheetTag  = 41;
static const NSInteger kMessageSheetTag = 42;
static const NSInteger kForwardSheetTag = 43;
static const NSInteger kReportSheetTag  = 44;
static const NSInteger kSendOptionsSheetTag = 45;
static const NSInteger kScheduleSheetTag    = 46;
static const NSInteger kScheduledListSheetTag = 47;
static const NSInteger kSelectionDeleteSheetTag = 48;
static const NSInteger kLinkSheetTag        = 49;
static const NSInteger kReportTextAlertTag  = 61;
static const NSInteger kPastePhotoAlertTag  = 62;
static const NSInteger kJoinLinkAlertTag    = 63;
static const NSInteger kModerationSheetTag  = 50;
static const NSInteger kAttachMoreSheetTag  = 51;
static const NSInteger kLocationSheetTag    = 52;
static const NSInteger kDiceSheetTag        = 53;
static const NSInteger kTextToolsSheetTag   = 54;
static const NSInteger kPinnedSheetTag      = 55;
static const NSInteger kScheduledItemSheetTag = 56;
static const NSInteger kSelectionMoreSheetTag = 57;
static const NSInteger kVenueTitleAlertTag  = 64;
static const NSInteger kVenueAddressAlertTag = 65;
static const NSInteger kQuickReplyAlertTag  = 68;
static const NSInteger kAlbumSelectionLimit = 30;
static const NSInteger kAlbumBatchLimit     = 10;
static const NSInteger kBotMenuSheetTag     = 90;
static const NSInteger kBotButtonsSheetTag  = 91;
static const NSInteger kBotCommandsSheetTag = 92;
static const NSInteger kInlineResultsSheetTag = 93;
static const NSInteger kSimilarBotsSheetTag = 94;
static const NSInteger kRecentBotsSheetTag  = 95;
static const NSInteger kChipsSheetTag       = 96;
static const NSInteger kBotPasswordAlertTag = 97;
static const NSInteger kInlineQueryAlertTag = 98;
static const NSInteger kBotStartAlertTag    = 99;
static const NSInteger kAllowBotAlertTag    = 100;
static const NSInteger kTextLinksSheetTag   = 101;
static const NSInteger kStickerLinkAlertTag = 102;
static const NSInteger kPeerMenuSheetTag    = 103;
static const NSInteger kHeldLinkSheetTag    = 104;
static const NSInteger kFailedMessageSheetTag = 105;

- (Class)videoCaptureClass {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypeCamera])
		return Nil;
	return NSClassFromString(@"TGVideoCaptureViewController");
}

- (BOOL)cameraAvailable {
	return [UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypeCamera];
}

- (UIImage *)pasteboardImage {
	UIPasteboard *board = [UIPasteboard generalPasteboard];
	UIImage *image = board.image;
	if (image)
		return image;
	id first = [board.images firstObject];
	return [first isKindOfClass:UIImage.class] ? first : nil;
}

- (void)attachTapped {
	NSMutableArray *titles = [NSMutableArray array];
	if ([self cameraAvailable])
		[titles addObject:@"Take Photo"];
	[titles addObject:@"Photo or Video"];
	if ([TGAssetPicker available])
		[titles addObject:@"Photo Album"];
	if ([self videoCaptureClass]){
		[titles addObject:@"Video"];
		[titles addObject:@"Video Message"];
	}
	if ([self pasteboardImage])
		[titles addObject:@"Paste Photo"];
	[titles addObject:@"Music"];
	[titles addObject:@"Location"];
	[titles addObject:@"Contact"];
	[titles addObject:@"More"];

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:nil];
	for (NSString *title in titles)
		[sheet addButtonWithTitle:title];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kAttachSheetTag;
	[sheet showInView:self.view];
}

- (void)captureVideoRound:(BOOL)round {
	Class shooterClass = [self videoCaptureClass];
	if (!shooterClass)
		return;

	TGVideoCaptureViewController *shooter =
			[[shooterClass alloc] initWithRoundVideoNote:round];
	if (!shooter)
		return;

	__weak typeof(self) weakSelf = self;
	shooter.onFinish = ^(NSString *path, NSTimeInterval duration, CGSize dimensions){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[me sendCapturedVideoAtPath:path duration:duration
							   size:dimensions round:round];
	};

	[self presentViewController:shooter animated:YES completion:nil];
}

- (void)sendCapturedVideoAtPath:(NSString *)path
					   duration:(NSTimeInterval)duration
						   size:(CGSize)dimensions
						  round:(BOOL)round
{
	if (!path.length || self.postingBlocked)
		return;

	if (!round){
		[[TGClient shared] sendVideoAtPath:path
									toChat:self.chatId
									thread:self.threadId
								   caption:@""
								  duration:(NSInteger)duration
									 width:(NSInteger)dimensions.width
									height:(NSInteger)dimensions.height
								   spoiler:NO
					   selfDestructSeconds:0];
		[self clearComposeState];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ [self reload]; });
		return;
	}

	NSInteger side = (NSInteger)MIN(dimensions.width, dimensions.height);
	if (side <= 0)
		side = 240;

	NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:@{
			@"@type"   : @"sendMessage",
			@"chat_id" : @(self.chatId),
			@"input_message_content" : @{
					@"@type"      : @"inputMessageVideoNote",
					@"video_note" : @{@"@type" : @"inputFileLocal", @"path" : path},
					@"duration"   : @((NSInteger)duration),
					@"length"     : @(side)}}];
	if (self.threadId)
		request[@"message_thread_id"] = @(self.threadId);
	if (self.replyToId)
		request[@"reply_to"] = @{@"@type" : @"inputMessageReplyToMessage",
								 @"message_id" : @(self.replyToId)};
	[[TGClient shared] send:request];

	[self clearComposeState];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [self reload]; });
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex){
		if (sheet.tag == kPeerMenuSheetTag){
			self.peerMenuUserId = 0;
			self.peerMenuName = nil;
		} else if (sheet.tag == kHeldLinkSheetTag){
			self.heldLinkURL = nil;
		} else if (sheet.tag == kFailedMessageSheetTag){
			self.failedMessageId = 0;
		}
		return;
	}

	if (sheet.tag == kTextLinksSheetTag){
		if (index >= 0 && index < (NSInteger)self.tappedLinkTargets.count)
			[self followTextTarget:[self.tappedLinkTargets objectAtIndex:index]];
		self.tappedLinkTargets = nil;
		return;
	}
	if (sheet.tag == kPeerMenuSheetTag){
		[self runPeerMenuOption:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kHeldLinkSheetTag){
		[self runHeldLinkOption:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kFailedMessageSheetTag){
		[self runFailedMessageOption:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kMessageSheetTag){
		[self runMessageAction:[sheet buttonTitleAtIndex:index]];
		return;
	}
	if (sheet.tag == kForwardSheetTag){
		[self forwardWithCopy:(index >= 1) removeCaptions:(index == 2)];
		return;
	}
	if (sheet.tag == kReportSheetTag){
		if (index < (NSInteger)self.reportOptions.count)
			[self reportMessage:self.reportMessageId
					   optionId:self.reportOptions[index][@"id"]];
		return;
	}
	if (sheet.tag == kSendOptionsSheetTag){
		[self runSendOption:[sheet buttonTitleAtIndex:index]];
		return;
	}
	if (sheet.tag == kScheduleSheetTag){
		[self runScheduleOption:[sheet buttonTitleAtIndex:index]];
		return;
	}
	if (sheet.tag == kScheduledListSheetTag){
		if (index < (NSInteger)self.scheduledMessages.count)
			[self showScheduledItemOptions:index];
		return;
	}
	if (sheet.tag == kScheduledItemSheetTag){
		NSString *chosen = [sheet buttonTitleAtIndex:index] ?: @"";
		if ([chosen isEqualToString:@"Send Now"])
			[self sendScheduledMessageAtIndex:self.scheduledItemIndex];
		else if ([chosen isEqualToString:@"Reschedule"])
			[self beginReschedulingItem:self.scheduledItemIndex];
		return;
	}
	if (sheet.tag == kAttachMoreSheetTag){
		[self runAttachMore:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kBotMenuSheetTag){
		[self runBotMenu:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kBotButtonsSheetTag){
		[self runBotButtonAtIndex:index];
		return;
	}
	if (sheet.tag == kBotCommandsSheetTag){
		if (index < (NSInteger)self.botCommandList.count){
			NSString *command = self.botCommandList[index][@"command"];
			if (command.length){
				self.input.text = [NSString stringWithFormat:@"/%@", command];
				[self inputChanged];
				[self sendTapped];
			}
		}
		return;
	}
	if (sheet.tag == kSimilarBotsSheetTag){
		if (index < (NSInteger)self.similarBotList.count)
			[self openBotFromEntry:self.similarBotList[index]];
		return;
	}
	if (sheet.tag == kRecentBotsSheetTag){
		if (index < (NSInteger)self.recentInlineBotList.count)
			[self runInlineQueryForBot:[self.recentInlineBotList[index][@"id"] longLongValue]
								 query:@""
								offset:nil];
		return;
	}
	if (sheet.tag == kInlineResultsSheetTag){
		[self runInlineResultAtIndex:index];
		return;
	}
	if (sheet.tag == kChipsSheetTag){
		[self runChipsOption:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kDiceSheetTag){
		[self runDiceOption:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kLocationSheetTag){
		[self runLocationOption:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kTextToolsSheetTag){
		[self runTextTool:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kPinnedSheetTag){
		[self unpinEverything];
		return;
	}
	if (sheet.tag == kSelectionMoreSheetTag){
		[self runSelectionMore:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kLinkSheetTag){
		NSString *link = self.pendingLinkURL;
		self.pendingLinkURL = nil;
		if (!link.length)
			return;
		if (index == 0)
			[self openExternalLink:link];
		else
			[UIPasteboard generalPasteboard].string = link;
		return;
	}
	if (sheet.tag == kModerationSheetTag){
		[self runModerationAction:([sheet buttonTitleAtIndex:index] ?: @"")];
		return;
	}
	if (sheet.tag == kSelectionDeleteSheetTag){
		[self deleteSelectedForEveryone:(index == sheet.destructiveButtonIndex)];
		return;
	}
	if (sheet.tag != kAttachSheetTag)
		return;

	NSString *chosen = [sheet buttonTitleAtIndex:index] ?: @"";
	if ([chosen isEqualToString:@"Take Photo"])
		[self takePhoto];
	else if ([chosen isEqualToString:@"Paste Photo"])
		[self pastePhoto];
	else if ([chosen isEqualToString:@"Music"])
		[self pickMusic];
	else if ([chosen isEqualToString:@"Photo or Video"])
		[self pickMedia];
	else if ([chosen isEqualToString:@"Photo Album"])
		[self pickPhotoAlbum];
	else if ([chosen isEqualToString:@"Video"])
		[self captureVideoRound:NO];
	else if ([chosen isEqualToString:@"Video Message"])
		[self captureVideoRound:YES];
	else if ([chosen isEqualToString:@"Location"])
		[self showLocationOptions];
	else if ([chosen isEqualToString:@"Contact"])
		[self pickContact];
	else if ([chosen isEqualToString:@"More"])
		[self showAttachMore];
}

/// The second page of the attach menu: the things a chat sends rarely enough
/// that they do not deserve a row of their own on the first one.
- (void)showAttachMore {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:@"Send as File",
															   @"GIF",
															   @"Poll",
															   @"Dice", nil];
	[sheet addButtonWithTitle:@"Inline Bot"];
	if (self.chatIsWithBot)
		[sheet addButtonWithTitle:@"Bot"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kAttachMoreSheetTag;
	[sheet showInView:self.view];
}

- (void)runAttachMore:(NSString *)chosen {
	if (self.postingBlocked)
		return;
	if ([chosen isEqualToString:@"Inline Bot"]){
		[self askInlineBotQuery];
		return;
	}
	if ([chosen isEqualToString:@"Bot"]){
		[self showBotMenu];
		return;
	}
	if ([chosen isEqualToString:@"Send as File"]){
		self.attachMode = @"document";
		[self pickMedia];
		return;
	}
	if ([chosen isEqualToString:@"GIF"]){
		self.attachMode = @"animation";
		[self pickMedia];
		return;
	}
	if ([chosen isEqualToString:@"Poll"]){
		[self showPollComposer];
		return;
	}
	if ([chosen isEqualToString:@"Dice"]){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Roll"
														   delegate:self
												  cancelButtonTitle:nil
											 destructiveButtonTitle:nil
												  otherButtonTitles:@"Dice",
																   @"Darts",
																   @"Basketball",
																   @"Slot Machine", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = kDiceSheetTag;
		[sheet showInView:self.view];
	}
}

- (void)runDiceOption:(NSString *)chosen {
	NSString *face = nil;
	if ([chosen isEqualToString:@"Darts"])
		face = @"\U0001F3AF";
	else if ([chosen isEqualToString:@"Basketball"])
		face = @"\U0001F3C0";
	else if ([chosen isEqualToString:@"Slot Machine"])
		face = @"\U0001F3B0";
	[[TGClient shared] sendDice:face toChat:self.chatId thread:self.threadId];
	[self clearComposeState];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [self reload]; });
}

#pragma mark - polls

- (void)showPollComposer {
	TGPollComposerViewController *composer = [[TGPollComposerViewController alloc] init];
	__weak typeof(self) weakSelf = self;
	composer.onSend = ^(NSString *question, NSArray *options, BOOL anonymous,
						BOOL multipleAnswers, NSInteger correctOption,
						NSString *explanation){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[me sendComposedPollQuestion:question
							 options:options
						   anonymous:anonymous
					 multipleAnswers:multipleAnswers
				   quizCorrectOption:correctOption
					 quizExplanation:explanation];
	};
	UINavigationController *nav =
			[[UINavigationController alloc] initWithRootViewController:composer];
	if (TGChatIsPad())
		nav.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentModalViewController:nav animated:YES];
}

- (void)sendComposedPollQuestion:(NSString *)question
						 options:(NSArray *)options
					   anonymous:(BOOL)anonymous
				 multipleAnswers:(BOOL)multipleAnswers
			   quizCorrectOption:(NSInteger)quizCorrectOption
				 quizExplanation:(NSString *)quizExplanation {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sendPollWithQuestion:question
									options:options
								  anonymous:anonymous
							multipleAnswers:multipleAnswers
						  quizCorrectOption:quizCorrectOption
							quizExplanation:quizExplanation
									 toChat:self.chatId
									 thread:self.threadId
								 completion:^(int64_t messageId){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!messageId){
			[me showAlertTitle:@"" message:@"This poll was refused."];
			return;
		}
		[me clearComposeState];
		[me reload];
	}];
}

#pragma mark - location

- (void)showLocationOptions {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Location"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"Send My Location"];
	if (self.liveLocationMessageId)
		[sheet addButtonWithTitle:@"Stop Sharing"];
	else
		[sheet addButtonWithTitle:@"Share For 1 Hour"];
	[sheet addButtonWithTitle:@"Send a Place"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kLocationSheetTag;
	[sheet showInView:self.view];
}

- (void)runLocationOption:(NSString *)chosen {
	if ([chosen isEqualToString:@"Send My Location"]){
		self.locationMode = @"point";
		[self sendCurrentLocation];
		return;
	}
	if ([chosen isEqualToString:@"Share For 1 Hour"]){
		self.locationMode = @"live";
		[self sendCurrentLocation];
		return;
	}
	if ([chosen isEqualToString:@"Stop Sharing"]){
		[self stopSharingLiveLocation];
		return;
	}
	if ([chosen isEqualToString:@"Send a Place"]){
		UIAlertView *ask = [[TGAlertView alloc] initWithTitle:@"Place"
													  message:@"Its name"
													 delegate:self
											cancelButtonTitle:@"Cancel"
											otherButtonTitles:@"Next", nil];
		if ([ask respondsToSelector:@selector(setAlertViewStyle:)])
			ask.alertViewStyle = UIAlertViewStylePlainTextInput;
		ask.tag = kVenueTitleAlertTag;
		[ask show];
	}
}

- (void)stopSharingLiveLocation {
	if (!self.liveLocationMessageId)
		return;
	[[TGClient shared] stopLiveLocation:self.liveLocationMessageId inChat:self.chatId];
	self.liveLocationMessageId = 0;
	self.locationMode = nil;
	[self.locationManager stopUpdatingLocation];
	[TGSnackbar showInView:self.view text:@"Live location stopped" seconds:3 onCommit:nil];
	[self reload];
}

#pragma mark - text tools

- (void)showTextTools {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Text"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	[sheet addButtonWithTitle:(self.markdownComposing ? @"Send as Plain Text"
													  : @"Send as Markdown")];
	[sheet addButtonWithTitle:@"Preview Formatting"];
	[sheet addButtonWithTitle:@"Preview Link"];
	[sheet addButtonWithTitle:@"Translate Draft"];
	[sheet addButtonWithTitle:@"Save as Quick Reply"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kTextToolsSheetTag;
	[sheet showInView:self.view];
}

- (NSString *)composerText {
	return [self.input.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)runTextTool:(NSString *)chosen {
	if ([chosen isEqualToString:@"Send as Markdown"] ||
		[chosen isEqualToString:@"Send as Plain Text"]){
		self.markdownComposing = !self.markdownComposing;
		[TGSnackbar showInView:self.view
						  text:(self.markdownComposing
								? @"*bold*, _italic_ and `code` will be applied"
								: @"Text will be sent exactly as typed")
					   seconds:3 onCommit:nil];
		return;
	}

	NSString *text = [self composerText];
	if (!text.length){
		[self showAlertTitle:@"" message:@"There is nothing in the message field."];
		return;
	}

	__weak typeof(self) weakSelf = self;
	if ([chosen isEqualToString:@"Preview Formatting"]){
		[[TGClient shared] parseMarkdown:text completion:^(NSString *plainText, NSArray *entities){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			[me showFormattingPreview:(plainText ?: text) markup:entities];
		}];
		return;
	}

	if ([chosen isEqualToString:@"Preview Link"]){
		NSDictionary *options = [TGClient linkPreviewOptionsDisabled:NO
																 url:@""
													 forceSmallMedia:NO
													 forceLargeMedia:YES
													   showAboveText:NO];
		[[TGClient shared] linkPreviewForText:text withOptions:options
								   completion:^(NSDictionary *preview){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (![preview[@"url"] length]){
				[me showAlertTitle:@""
						   message:@"There is no link in the message field."];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSString *key in @[@"siteName", @"title", @"description", @"displayUrl"]){
				NSString *value = [preview[key] isKindOfClass:NSString.class]
						? preview[key] : nil;
				if (value.length)
					[lines addObject:value];
			}
			if ([preview[@"hasInstantView"] boolValue])
				[lines addObject:@"Instant View available"];
			[me showAlertTitle:(preview[@"url"] ?: @"Link")
					   message:(lines.count ? [lines componentsJoinedByString:@"\n"]
											: @"Nothing is known about this link yet.")];
		}];
		return;
	}

	if ([chosen isEqualToString:@"Translate Draft"]){
		NSString *preferred = [[NSLocale preferredLanguages] firstObject];
		NSString *language = (preferred.length >= 2) ? [preferred substringToIndex:2] : @"en";
		[[TGClient shared] translateText:text toLanguage:language tone:nil
							  completion:^(NSString *translated){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!translated.length){
				[me showAlertTitle:@"" message:@"This text could not be translated."];
				return;
			}
			me.input.text = translated;
			[me inputChanged];
			[TGSnackbar showInView:me.view text:@"Draft translated" seconds:3 onCommit:nil];
		}];
		return;
	}

	if ([chosen isEqualToString:@"Save as Quick Reply"]){
		UIAlertView *ask = [[TGAlertView alloc] initWithTitle:@"Quick Reply"
													  message:@"A short name for it"
													 delegate:self
											cancelButtonTitle:@"Cancel"
											otherButtonTitles:@"Save", nil];
		if ([ask respondsToSelector:@selector(setAlertViewStyle:)])
			ask.alertViewStyle = UIAlertViewStylePlainTextInput;
		ask.tag = kQuickReplyAlertTag;
		[ask show];
	}
}

/// What the composer would actually send: the markers gone, and every run
/// TDLib found in it - the ones the user typed and the ones it detects itself.
- (void)showFormattingPreview:(NSString *)plainText markup:(NSArray *)markup {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] entitiesInText:plainText completion:^(NSArray *detected){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *lines = [NSMutableArray array];
		for (NSDictionary *entity in markup)
			[lines addObject:[NSString stringWithFormat:@"%@ %@",
					(entity[@"kind"] ?: @"text"),
					[me fragmentOf:plainText entity:entity]]];
		for (NSDictionary *entity in detected)
			[lines addObject:[NSString stringWithFormat:@"%@ %@",
					(entity[@"kind"] ?: @"text"),
					[me fragmentOf:plainText entity:entity]]];
		[me showAlertTitle:plainText
				   message:(lines.count ? [lines componentsJoinedByString:@"\n"]
										: @"No formatting in this text.")];
	}];
}

- (NSString *)fragmentOf:(NSString *)text entity:(NSDictionary *)entity {
	NSUInteger offset = (NSUInteger)[entity[@"offset"] integerValue];
	NSUInteger length = (NSUInteger)[entity[@"length"] integerValue];
	if (offset + length > text.length || length == 0)
		return @"";
	return [text substringWithRange:NSMakeRange(offset, length)];
}

#pragma mark - links

- (void)openLink:(NSString *)url {
	if (!url.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] botStartLinkInfo:url completion:^(NSDictionary *info){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSString *username = info[@"username"];
		if (!username.length){
			[me resolveAndOpenLink:url];
			return;
		}
		me.pendingBotStartLink = url;
		UIAlertView *ask = [[UIAlertView alloc] initWithTitle:
				[NSString stringWithFormat:@"@%@", username]
													  message:([info[@"inGroup"] boolValue]
															   ? @"Start this bot?"
															   : @"Start a chat with this bot?")
													 delegate:me
											cancelButtonTitle:@"Cancel"
											otherButtonTitles:@"Start", nil];
		ask.tag = kBotStartAlertTag;
		[ask show];
	}];
}

- (void)touchedMessageBackground {
	if ([self.input isFirstResponder])
		[self.input resignFirstResponder];
	else if ([self.chatSearchBar isFirstResponder])
		[self.chatSearchBar resignFirstResponder];
	else if (self.stickerPanel)
		[self toggleStickerPanel];
}

- (void)openLinkInMessage:(NSDictionary *)m {
	NSString *text = [self originalTextOf:m];
	if (!text.length){
		[self touchedMessageBackground];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] entitiesInText:text completion:^(NSArray *entities){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *targets = [NSMutableArray array];
		for (NSDictionary *entity in entities){
			if (![entity isKindOfClass:NSDictionary.class])
				continue;
			NSString *kind = [([entity[@"kind"] isKindOfClass:NSString.class]
					? entity[@"kind"] : @"") lowercaseString];
			NSString *fragment = [me fragmentOf:text entity:entity];
			if (!fragment.length)
				continue;
			if ([kind isEqualToString:@"url"]){
				[targets addObject:@{ @"label" : fragment, @"url" : fragment }];
			} else if ([kind isEqualToString:@"texturl"]){
				NSString *href = [entity[@"url"] isKindOfClass:NSString.class]
						? entity[@"url"] : nil;
				if (href.length)
					[targets addObject:@{ @"label" : fragment, @"url" : href }];
			} else if ([kind isEqualToString:@"mention"] && fragment.length > 1){
				[targets addObject:@{ @"label" : fragment,
									  @"mention" : [fragment substringFromIndex:1] }];
			} else if ([kind isEqualToString:@"mentionname"]){
				int64_t mentioned = [entity[@"userId"] longLongValue];
				if (mentioned > 0)
					[targets addObject:@{ @"label" : fragment,
										  @"userId" : @(mentioned) }];
			} else if (([kind isEqualToString:@"hashtag"] ||
						[kind isEqualToString:@"cashtag"]) && fragment.length > 1){
				[targets addObject:@{ @"label" : fragment, @"hashtag" : fragment }];
			} else if ([kind isEqualToString:@"botcommand"] && fragment.length > 1){
				[targets addObject:@{ @"label" : fragment, @"command" : fragment }];
			} else if ([kind isEqualToString:@"phonenumber"]){
				[targets addObject:@{ @"label" : fragment,
									  @"url" : [@"tel:" stringByAppendingString:fragment] }];
			} else if ([kind isEqualToString:@"emailaddress"]){
				[targets addObject:@{ @"label" : fragment,
									  @"url" : [@"mailto:" stringByAppendingString:fragment] }];
			}
		}
		if (!targets.count){
			[me tapFellThroughOnMessage:m];
			return;
		}
		if (targets.count == 1){
			[me followTextTarget:[targets objectAtIndex:0]];
			return;
		}
		me.tappedLinkTargets = targets;
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Links"
														   delegate:me
												  cancelButtonTitle:nil
											 destructiveButtonTitle:nil
												  otherButtonTitles:nil];
		NSUInteger shown = MIN((NSUInteger)8, targets.count);
		for (NSUInteger i = 0; i < shown; i++)
			[sheet addButtonWithTitle:[targets objectAtIndex:i][@"label"]];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = kTextLinksSheetTag;
		[sheet showInView:me.view];
	}];
}

- (void)followTextTarget:(NSDictionary *)target {
	NSString *url = target[@"url"];
	if ([url isKindOfClass:NSString.class] && url.length){
		[self openLink:url];
		return;
	}
	NSString *hashtag = target[@"hashtag"];
	if ([hashtag isKindOfClass:NSString.class] && hashtag.length){
		[self searchChatForTag:hashtag];
		return;
	}
	NSString *command = target[@"command"];
	if ([command isKindOfClass:NSString.class] && command.length){
		[[TGClient shared] sendText:command toChat:self.chatId
							 thread:self.threadId];
		return;
	}
	NSNumber *userId = target[@"userId"];
	if ([userId isKindOfClass:NSNumber.class] && [userId longLongValue] > 0){
		[self openProfileForUserId:[userId longLongValue]];
		return;
	}
	NSString *mention = target[@"mention"];
	if (![mention isKindOfClass:NSString.class] || !mention.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] publicLinkForUsername:mention completion:^(NSString *link){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!link.length){
			[me showAlertTitle:@""
					   message:[NSString stringWithFormat:@"There is no @%@.", mention]];
			return;
		}
		[me openLink:link];
	}];
}

- (void)resolveAndOpenLink:(NSString *)url {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] resolveLink:url completion:^(NSDictionary *link){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSString *kind = link[@"kind"];
		if ([kind isEqualToString:@"message"]){
			[[TGClient shared] resolveMessageLink:url completion:^(NSDictionary *info){
				TGChatViewController *inner = weakSelf;
				if (!inner)
					return;
				int64_t messageId = [info[@"messageId"] longLongValue];
				if (messageId && [info[@"chatId"] longLongValue] == inner.chatId &&
					[inner scrollToMessageId:messageId])
					return;
				[inner confirmExternalLink:url];
			}];
			return;
		}
		if ([me routeInternalLink:link])
			return;
		if (link && ![link[@"supported"] boolValue]){
			[me explainUnsupportedLink:url];
			return;
		}
		[me confirmExternalLink:url];
	}];
}

- (BOOL)routeInternalLink:(NSDictionary *)link {
	NSString *kind = link[@"kind"];
	if (!kind.length)
		return NO;

	if ([kind isEqualToString:@"publicChat"] || [kind isEqualToString:@"publicChatUsername"]){
		NSString *username = link[@"username"];
		if (!username.length)
			return NO;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] publicChatWithUsername:username completion:^(NSDictionary *chat){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			int64_t target = [chat[@"id"] longLongValue];
			if (!target)
				target = [chat[@"chatId"] longLongValue];
			if (!target){
				[me showAlertTitle:@"" message:@"There is no such public chat."];
				return;
			}
			[me openChatId:target
					 title:(chat[@"title"] ?: [NSString stringWithFormat:@"@%@", username])
				   isGroup:[chat[@"isGroup"] boolValue]];
		}];
		return YES;
	}

	if ([kind isEqualToString:@"chatInvite"]){
		NSString *invite = link[@"inviteLink"] ?: link[@"link"];
		if (!invite.length)
			return NO;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] previewInviteLink:invite completion:^(NSDictionary *info){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!info){
				[me showAlertTitle:@"" message:@"This invite link has expired."];
				return;
			}
			int64_t known = [info[@"chatId"] longLongValue];
			if (known){
				[me openChatId:known title:(info[@"title"] ?: @"Chat")
					   isGroup:YES];
				return;
			}
			me.pendingInviteLink = invite;
			UIAlertView *ask = [[UIAlertView alloc] initWithTitle:(info[@"title"] ?: @"Join")
														  message:([info[@"requiresApproval"] boolValue]
																  ? @"Your request to join will be sent to the admins."
																  : @"Join this chat?")
														 delegate:me
												cancelButtonTitle:@"Cancel"
												otherButtonTitles:@"Join", nil];
			ask.tag = kJoinLinkAlertTag;
			[ask show];
		}];
		return YES;
	}

	if ([kind isEqualToString:@"stickerSet"]){
		NSString *name = link[@"stickerSetName"];
		if (!name.length)
			return NO;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] stickerSetWithName:name completion:^(NSDictionary *set){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!set){
				[me showAlertTitle:@"" message:@"This sticker set no longer exists."];
				return;
			}
			int64_t setId = [set[@"id"] longLongValue];
			if ([set[@"installed"] boolValue] || !setId){
				[me offerStickerSetLink:name
								  title:(set[@"title"] ?: @"Stickers")
								message:@"This set is already in your stickers."];
				return;
			}
			[[TGClient shared] installStickerSet:setId completion:^(BOOL ok){
				TGChatViewController *inner = weakSelf;
				if (!inner)
					return;
				if (!ok){
					[inner showAlertTitle:(set[@"title"] ?: @"Stickers")
								  message:@"This set could not be added."];
					return;
				}
				[inner offerStickerSetLink:name
									 title:(set[@"title"] ?: @"Stickers")
								   message:@"Added to your stickers."];
			}];
		}];
		return YES;
	}

	return NO;
}

- (void)offerStickerSetLink:(NSString *)name
					  title:(NSString *)title
					message:(NSString *)message {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] publicLinkForStickerSetName:name completion:^(NSString *url){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!url.length){
			[me showAlertTitle:title message:message];
			return;
		}
		me.pendingStickerSetLink = url;
		UIAlertView *ask = [[UIAlertView alloc] initWithTitle:title
													  message:[NSString stringWithFormat:
															   @"%@\n%@", message, url]
													 delegate:me
											cancelButtonTitle:@"Done"
											otherButtonTitles:@"Copy Link", nil];
		ask.tag = kStickerLinkAlertTag;
		[ask show];
	}];
}

- (void)explainUnsupportedLink:(NSString *)url {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] deepLinkInfoForUrl:url completion:^(NSString *text, BOOL needsUpdate){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		(void)needsUpdate;
		[me showAlertTitle:@""
				   message:(text.length ? text : @"This link cannot be opened.")];
	}];
}

- (void)openChatId:(int64_t)targetChatId title:(NSString *)title isGroup:(BOOL)isGroup {
	[self openChatId:targetChatId title:title isGroup:isGroup focusMessage:0];
}

- (void)openChatId:(int64_t)targetChatId
			 title:(NSString *)title
		   isGroup:(BOOL)isGroup
	  focusMessage:(int64_t)messageId
{
	if (targetChatId == self.chatId){
		if (messageId && ![self scrollToMessageId:messageId])
			[self loadDeeperHistoryAndScrollTo:messageId];
		return;
	}
	for (UIViewController *existing in self.navigationController.viewControllers){
		if (![existing isKindOfClass:TGChatViewController.class])
			continue;
		TGChatViewController *open = (TGChatViewController *)existing;
		if (open.chatId != targetChatId)
			continue;
		open.focusMessageId = messageId;
		[self.navigationController popToViewController:existing animated:YES];
		if (messageId && ![open scrollToMessageId:messageId])
			[open loadDeeperHistoryAndScrollTo:messageId];
		return;
	}
	TGChatViewController *controller = [[TGChatViewController alloc] init];
	controller.chatId = targetChatId;
	controller.chatTitle = title.length ? title : @"Chat";
	controller.isGroup = isGroup;
	controller.focusMessageId = messageId;
	[self.navigationController pushViewController:controller animated:YES];
}

- (void)confirmExternalLink:(NSString *)url {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] externalLinkInfoForUrl:url completion:^(NSDictionary *info){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSString *target = info[@"url"] ?: url;
		if (info && ![info[@"needsConfirmation"] boolValue]){
			[me openExternalLink:target];
			return;
		}
		NSString *domain = info[@"domain"];
		if (!domain.length)
			domain = [[NSURL URLWithString:url] host] ?: url;

		me.pendingLinkURL = target;
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:domain
														  delegate:me
												 cancelButtonTitle:nil
											destructiveButtonTitle:nil
												 otherButtonTitles:@"Open in Safari",
																   @"Copy Link", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = kLinkSheetTag;
		[sheet showInView:me.view];
	}];
}

- (void)openExternalLink:(NSString *)url {
	[[TGClient shared] externalLinkForUrl:url allowWriteAccess:NO
							   completion:^(NSString *opened){
		NSURL *target = [NSURL URLWithString:(opened.length ? opened : url)];
		if (target)
			[[UIApplication sharedApplication] openURL:target];
	}];
}

- (void)openInstantView:(NSString *)url {
	if (!url.length)
		return;
	TGInstantViewController *reader = [[TGInstantViewController alloc] init];
	reader.url = url;
	[self.navigationController pushViewController:reader animated:YES];
}

#pragma mark - message actions

- (void)messageHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;

	CGPoint point = [hold locationInView:self.table];
	for (UIView *view = [self.table hitTest:point withEvent:nil]; view; view = view.superview)
		if ([view isKindOfClass:TGReactionChipsView.class])
			return;

	NSIndexPath *path = [self.table indexPathForRowAtPoint:point];
	if (!path)
		return;

	[self.table deselectRowAtIndexPath:path animated:NO];

	UITableViewCell *cell = [self.table cellForRowAtIndexPath:path];
	if ([cell isKindOfClass:TGBubbleCell.class] && !self.selecting){
		TGBubbleCell *bubbleCell = (TGBubbleCell *)cell;
		NSString *held = [self urlInLabel:bubbleCell.body
								  atPoint:[hold locationInView:bubbleCell.body]];
		if (held.length){
			[self showHeldLinkSheetFor:held];
			return;
		}
	}

	[self showActionsForRow:path.row];
}

#pragma mark - a link under the finger

- (NSArray *)lineRangesOfText:(NSString *)text font:(UIFont *)font width:(CGFloat)width {
	NSMutableArray *lines = [NSMutableArray array];
	if (!text.length || !font || width < 1)
		return lines;

	NSUInteger length = text.length;
	NSUInteger lineStart = 0;
	NSUInteger cursor = 0;
	NSUInteger lastBreak = NSNotFound;
	NSCharacterSet *spaces = [NSCharacterSet whitespaceCharacterSet];

	while (cursor < length){
		unichar c = [text characterAtIndex:cursor];
		if (c == '\n'){
			[lines addObject:[NSValue valueWithRange:
					NSMakeRange(lineStart, cursor - lineStart)]];
			cursor++;
			lineStart = cursor;
			lastBreak = NSNotFound;
			continue;
		}
		if ([spaces characterIsMember:c])
			lastBreak = cursor;

		NSRange sofar = NSMakeRange(lineStart, cursor - lineStart + 1);
		CGFloat used = [[text substringWithRange:sofar] sizeWithFont:font].width;
		if (used > width && cursor > lineStart){
			NSUInteger breakAt = (lastBreak != NSNotFound && lastBreak > lineStart)
					? lastBreak : cursor;
			[lines addObject:[NSValue valueWithRange:
					NSMakeRange(lineStart, breakAt - lineStart)]];
			lineStart = (breakAt == lastBreak) ? breakAt + 1 : breakAt;
			cursor = lineStart;
			lastBreak = NSNotFound;
			continue;
		}
		cursor++;
	}
	if (lineStart <= length)
		[lines addObject:[NSValue valueWithRange:
				NSMakeRange(lineStart, length - lineStart)]];
	return lines;
}

- (NSInteger)characterIndexInLabel:(UILabel *)label atPoint:(CGPoint)point {
	NSString *text = label.text;
	if (!text.length || label.hidden)
		return -1;
	if (!CGRectContainsPoint(CGRectInset(label.bounds, -4, -2), point))
		return -1;

	UIFont *font = label.font;
	CGFloat lineHeight = [@"Ag" sizeWithFont:font].height;
	if (lineHeight < 1)
		return -1;

	NSArray *lines = [self lineRangesOfText:text font:font
									  width:label.bounds.size.width];
	if (!lines.count)
		return -1;
	NSInteger index = (NSInteger)floorf(MAX(0.0f, point.y) / lineHeight);
	if (index < 0 || index >= (NSInteger)lines.count)
		return -1;

	NSRange line = [[lines objectAtIndex:index] rangeValue];
	CGFloat x = 0;
	if (label.textAlignment != NSTextAlignmentLeft){
		CGFloat lineW = [[text substringWithRange:line] sizeWithFont:font].width;
		CGFloat slack = MAX(0.0f, label.bounds.size.width - lineW);
		x = (label.textAlignment == NSTextAlignmentCenter) ? slack / 2 : slack;
	}
	CGFloat start = x;
	for (NSUInteger i = 0; i < line.length; i++){
		NSString *prefix = [text substringWithRange:
				NSMakeRange(line.location, i + 1)];
		CGFloat next = start + [prefix sizeWithFont:font].width;
		if (point.x >= x && point.x < next)
			return (NSInteger)(line.location + i);
		x = next;
	}
	return -1;
}

- (NSString *)urlInLabel:(UILabel *)label atPoint:(CGPoint)point {
	NSString *text = label.text;
	if (!text.length || label.hidden)
		return nil;
	if (TGEmojiTextNeedsSubstitution(text))
		return nil;
	if (text.length > 600)
		return nil;

	NSError *error = nil;
	NSDataDetector *detector = [NSDataDetector
			dataDetectorWithTypes:NSTextCheckingTypeLink error:&error];
	if (!detector)
		return nil;
	NSArray *matches = [detector matchesInString:text options:0
										   range:NSMakeRange(0, text.length)];
	if (!matches.count)
		return nil;

	NSInteger index = [self characterIndexInLabel:label atPoint:point];
	if (index < 0)
		return nil;
	for (NSTextCheckingResult *match in matches){
		if (!NSLocationInRange((NSUInteger)index, match.range))
			continue;
		NSURL *found = match.URL;
		if (found)
			return found.absoluteString;
		return [text substringWithRange:match.range];
	}
	return nil;
}

- (void)showHeldLinkSheetFor:(NSString *)url {
	self.heldLinkURL = url;
	NSString *title = url;
	if (title.length > 60)
		title = [[title substringToIndex:57] stringByAppendingString:@"..."];
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"Open"];
	[sheet addButtonWithTitle:@"Copy Link"];
	if ([self readingListClass])
		[sheet addButtonWithTitle:@"Add to Reading List"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kHeldLinkSheetTag;
	[sheet showInView:self.view];
}

- (Class)readingListClass {
	return NSClassFromString(@"SSReadingList");
}

- (void)runHeldLinkOption:(NSString *)chosen {
	NSString *url = self.heldLinkURL;
	self.heldLinkURL = nil;
	if (!url.length)
		return;
	if ([chosen isEqualToString:@"Open"]){
		[self openLink:url];
		return;
	}
	if ([chosen isEqualToString:@"Copy Link"]){
		[UIPasteboard generalPasteboard].string = url;
		return;
	}
	if (![chosen isEqualToString:@"Add to Reading List"])
		return;
	Class readingList = [self readingListClass];
	NSURL *target = [NSURL URLWithString:url];
	if (!readingList || !target)
		return;
	id list = [readingList defaultReadingList];
	if (![list respondsToSelector:
			@selector(addReadingListItemWithURL:title:previewText:error:)])
		return;
	[list addReadingListItemWithURL:target title:nil previewText:nil error:NULL];
}

#pragma mark - the sender beside a message

- (void)showPeerMenuForUserId:(int64_t)userId {
	if (userId <= 0 || self.selecting)
		return;
	self.peerMenuUserId = userId;
	self.peerMenuName = [[TGClient shared] nameForUserId:userId] ?: @"";
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:
			(self.peerMenuName.length ? self.peerMenuName : nil)
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"Open Profile"];
	[sheet addButtonWithTitle:@"Send Message"];
	if (!self.postingBlocked)
		[sheet addButtonWithTitle:@"Mention"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kPeerMenuSheetTag;
	[sheet showInView:self.view];
}

- (void)runPeerMenuOption:(NSString *)chosen {
	int64_t userId = self.peerMenuUserId;
	NSString *name = self.peerMenuName;
	self.peerMenuUserId = 0;
	self.peerMenuName = nil;
	if (userId <= 0)
		return;

	if ([chosen isEqualToString:@"Open Profile"]){
		[self openProfileForUserId:userId];
		return;
	}
	if ([chosen isEqualToString:@"Send Message"]){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
			TGChatViewController *me = weakSelf;
			if (!me || !chatId)
				return;
			[me openChatId:chatId title:(name.length ? name : @"Chat") isGroup:NO];
		}];
		return;
	}
	if ([chosen isEqualToString:@"Mention"])
		[self insertMentionOfUser:userId name:name];
}

- (void)insertMentionOfUser:(int64_t)userId name:(NSString *)name {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userInfo:userId completion:^(NSDictionary *user){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSString *username = [me publicUsernameIn:user];
		NSString *insert = username.length
				? [NSString stringWithFormat:@"@%@ ", username]
				: [NSString stringWithFormat:@"%@ ", (name.length ? name : @"")];
		if (insert.length < 2)
			return;
		NSString *current = me.input.text ?: @"";
		if (current.length && ![current hasSuffix:@" "])
			current = [current stringByAppendingString:@" "];
		me.input.text = [current stringByAppendingString:insert];
		[me inputChanged];
		[me.input becomeFirstResponder];
	}];
}

- (NSString *)publicUsernameIn:(NSDictionary *)user {
	if (![user isKindOfClass:NSDictionary.class])
		return nil;
	NSString *plain = user[@"username"];
	if ([plain isKindOfClass:NSString.class] && plain.length)
		return plain;
	NSDictionary *usernames = user[@"usernames"];
	if (![usernames isKindOfClass:NSDictionary.class])
		return nil;
	NSString *editable = usernames[@"editable_username"];
	if ([editable isKindOfClass:NSString.class] && editable.length)
		return editable;
	NSArray *active = usernames[@"active_usernames"];
	if (![active isKindOfClass:NSArray.class])
		return nil;
	NSString *first = [active firstObject];
	return [first isKindOfClass:NSString.class] ? first : nil;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
	if (recognizer == self.inputBarDismissSwipe){
		if (![self hasDismissableInput])
			return NO;
		CGPoint moved = [self.inputBarDismissSwipe translationInView:self.inputBar];
		return (moved.y > 0 && moved.y > fabs(moved.x));
	}
	return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
		shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
	if ((recognizer == self.backgroundTap && other == self.messageHold) ||
		(recognizer == self.messageHold && other == self.backgroundTap))
		return NO;
	return (recognizer == self.backgroundTap || other == self.backgroundTap ||
			recognizer == self.inputBarDismissSwipe || other == self.inputBarDismissSwipe);
}

- (BOOL)hasDismissableInput {
	return ([self.input isFirstResponder] || [self.chatSearchBar isFirstResponder] ||
			self.stickerPanel != nil);
}

- (void)messageBackgroundTapped:(UITapGestureRecognizer *)tap {
	if (tap.state != UIGestureRecognizerStateEnded)
		return;
	if (!self.selecting)
		[self touchedMessageBackground];
}

- (void)inputBarSwiped:(UIPanGestureRecognizer *)pan {
	if (pan.state != UIGestureRecognizerStateChanged &&
		pan.state != UIGestureRecognizerStateEnded)
		return;

	CGPoint moved = [pan translationInView:self.inputBar];
	if (moved.y <= 0 || moved.y <= fabs(moved.x))
		return;

	BOOL farEnough = (moved.y >= kInputSwipeDismissDistance);
	BOOL flicked = (pan.state == UIGestureRecognizerStateEnded &&
					[pan velocityInView:self.inputBar].y >= kInputSwipeDismissVelocity);
	if (!farEnough && !flicked)
		return;

	if (pan.state == UIGestureRecognizerStateChanged){
		pan.enabled = NO;
		pan.enabled = YES;
	}
	[self touchedMessageBackground];
}

- (BOOL)canReplyToRow:(NSInteger)row {
	NSDictionary *m = [self messageAtRow:row];
	if (!m)
		return NO;
	if ([m[@"service"] boolValue] || ![m[@"id"] isKindOfClass:NSNumber.class])
		return NO;
	return ([m[@"id"] longLongValue] != 0);
}

- (void)attachReplySwipeTo:(TGBubbleCell *)cell {
	__weak TGChatViewController *weakSelf = self;
	__weak TGBubbleCell *weakCell = cell;
	TGReplySwipeRecognizer *pan = [[TGReplySwipeRecognizer alloc]
			initWithTarget:self action:@selector(replySwiped:)];
	pan.shouldBegin = ^BOOL {
		TGChatViewController *me = weakSelf;
		return me ? [me canBeginReplySwipeOnCell:weakCell] : NO;
	};
	cell.replySwipe = pan;
	cell.contentView.clipsToBounds = NO;
	[cell addGestureRecognizer:pan];
}

- (BOOL)canBeginReplySwipeOnCell:(TGBubbleCell *)cell {
	if (!cell || self.selecting || self.postingBlocked)
		return NO;
	NSIndexPath *path = [self.table indexPathForCell:cell];
	return (path != nil && [self canReplyToRow:path.row]);
}

- (void)stopReplySwipeAnimationsInCell:(TGBubbleCell *)cell {
	if (cell.contentView.layer.animationKeys.count)
		[cell.contentView.layer removeAllAnimations];
	if (cell.replyArrow.layer.animationKeys.count)
		[cell.replyArrow.layer removeAllAnimations];
	if (cell.replyArrowPlate.layer.animationKeys.count)
		[cell.replyArrowPlate.layer removeAllAnimations];
}

- (void)applyReplySwipeOffset:(CGFloat)offset toCell:(TGBubbleCell *)cell {
	CGRect box = cell.contentView.bounds;
	if (box.origin.x == offset)
		return;
	box.origin.x = offset;
	cell.contentView.bounds = box;
}

- (void)resetReplySwipeOnCell:(TGBubbleCell *)cell {
	[self stopReplySwipeAnimationsInCell:cell];
	[self applyReplySwipeOffset:0.0f toCell:cell];
	cell.replyArrow.hidden = YES;
	cell.replyArrowPlate.alpha = 0.0f;
}

- (CGFloat)replySwipeTriggerForRow:(NSInteger)row {
	NSDictionary *m = [self messageAtRow:row];
	return [m[@"outgoing"] boolValue] ? kReplySwipeOutgoingTrigger
									  : kReplySwipeIncomingTrigger;
}

- (CGFloat)replySwipeArrowInsetForRow:(NSInteger)row {
	NSDictionary *m = [self messageAtRow:row];
	return [m[@"outgoing"] boolValue] ? kReplySwipeOutgoingInset
									  : kReplySwipeIncomingInset;
}

- (void)placeReplyArrowInCell:(TGBubbleCell *)cell forRow:(NSInteger)row {
	if (!cell.replyArrow){
		UIView *carrier = [[UIView alloc] initWithFrame:
				CGRectMake(0, 0, kReplySwipeIconSize, kReplySwipeIconSize)];
		carrier.backgroundColor = [UIColor clearColor];
		carrier.userInteractionEnabled = NO;

		UIView *plate = [[UIView alloc] initWithFrame:carrier.bounds];
		plate.backgroundColor = TGSystemPlateColour();
		plate.layer.cornerRadius = kReplySwipeIconSize / 2.0f;
		plate.userInteractionEnabled = NO;

		UIImageView *glyph = [[UIImageView alloc] initWithFrame:plate.bounds];
		glyph.contentMode = UIViewContentModeCenter;
		glyph.image = TGReplySwipeArrowImage();
		[plate addSubview:glyph];
		[carrier addSubview:plate];

		cell.replyArrow = carrier;
		cell.replyArrowPlate = plate;
		[cell.contentView addSubview:carrier];
	}

	[self stopReplySwipeAnimationsInCell:cell];

	CGRect box = cell.contentView.bounds;
	cell.replyArrow.transform = CGAffineTransformIdentity;
	cell.replyArrow.center = CGPointMake(
			box.size.width + [self replySwipeArrowInsetForRow:row] +
					kReplySwipeIconSize / 2.0f,
			(box.size.height + box.origin.y) / 2.0f);
	cell.replyArrowPlate.transform = CGAffineTransformMakeScale(0.65f, 0.65f);
	cell.replyArrowPlate.alpha = 0.0f;
	cell.replyArrow.hidden = NO;
	[cell.contentView bringSubviewToFront:cell.replyArrow];
}

- (void)updateReplyArrowInCell:(TGBubbleCell *)cell progress:(CGFloat)progress {
	UIView *plate = cell.replyArrowPlate;
	if (!plate)
		return;
	progress = MAX(0.0f, MIN(1.0f, progress));
	CGFloat shown = MIN(1.0f, progress * 1.2f);
	CGFloat scale = 0.65f + shown * 0.35f;
	plate.alpha = shown;
	plate.transform = CGAffineTransformMakeScale(scale, scale);

	if (progress < 1.0f || self.swipeArmed)
		return;
	self.swipeArmed = YES;
	[self popReplyArrowInCell:cell];
}

- (void)popReplyArrowInCell:(TGBubbleCell *)cell {
	UIView *carrier = cell.replyArrow;
	if (!carrier)
		return;
	[UIView animateWithDuration:0.2 delay:0.0
						options:UIViewAnimationOptionCurveEaseOut |
								UIViewAnimationOptionBeginFromCurrentState
					 animations:^{
		carrier.transform = CGAffineTransformMakeScale(1.1f, 1.1f);
	} completion:^(BOOL finished){
		if (!finished)
			return;
		[UIView animateWithDuration:0.15 delay:0.0
							options:UIViewAnimationOptionCurveEaseInOut |
									UIViewAnimationOptionBeginFromCurrentState
						 animations:^{
			carrier.transform = CGAffineTransformIdentity;
		} completion:nil];
	}];
}

- (void)springReplySwipeBackInCell:(TGBubbleCell *)cell from:(CGFloat)offset {
	UIView *carrier = cell.replyArrow;
	UIView *plate = cell.replyArrowPlate;
	CGFloat overshoot = MIN(5.0f, offset * 0.12f);
	__weak TGChatViewController *weakSelf = self;

	[UIView animateWithDuration:0.19 delay:0.0
						options:UIViewAnimationOptionCurveEaseOut |
								UIViewAnimationOptionBeginFromCurrentState
					 animations:^{
		CGRect box = cell.contentView.bounds;
		box.origin.x = -overshoot;
		cell.contentView.bounds = box;
		plate.alpha = 0.0f;
		plate.transform = CGAffineTransformMakeScale(0.2f, 0.2f);
	} completion:^(BOOL finished){
		TGChatViewController *me = weakSelf;
		if (!me || cell == me.swipingCell)
			return;
		carrier.hidden = YES;
		[UIView animateWithDuration:0.13 delay:0.0
							options:UIViewAnimationOptionCurveEaseInOut |
									UIViewAnimationOptionBeginFromCurrentState
						 animations:^{
			CGRect box = cell.contentView.bounds;
			box.origin.x = 0.0f;
			cell.contentView.bounds = box;
		} completion:nil];
	}];
}

- (void)replySwiped:(TGReplySwipeRecognizer *)pan {
	if (![pan.view isKindOfClass:TGBubbleCell.class])
		return;
	TGBubbleCell *cell = (TGBubbleCell *)pan.view;

	if (pan.state == UIGestureRecognizerStateBegan){
		NSIndexPath *path = [self.table indexPathForCell:cell];
		self.swipingRow = (path && [self canReplyToRow:path.row]) ? path.row : -1;
		if (self.swipingRow < 0)
			return;
		self.swipingCell = cell;
		self.swipeArmed = NO;
		self.swipeOffset = 0.0f;
		[self applyReplySwipeOffset:0.0f toCell:cell];
		[self placeReplyArrowInCell:cell forRow:self.swipingRow];
		return;
	}

	if (self.swipingRow < 0 || cell != self.swipingCell)
		return;

	CGFloat trigger = [self replySwipeTriggerForRow:self.swipingRow];
	CGFloat dragged = MAX(0.0f, -[pan translationInView:cell].x);

	if (pan.state == UIGestureRecognizerStateChanged){
		CGFloat offset = MIN(kReplySwipeMaxOffset,
				TGReplySwipeBandedOffset(dragged, trigger));
		self.swipeOffset = offset;
		[self applyReplySwipeOffset:offset toCell:cell];
		[self updateReplyArrowInCell:cell progress:offset / trigger];
		return;
	}

	if (pan.state == UIGestureRecognizerStateEnded ||
		pan.state == UIGestureRecognizerStateCancelled ||
		pan.state == UIGestureRecognizerStateFailed){
		NSInteger row = self.swipingRow;
		CGFloat travelled = self.swipeOffset;
		BOOL fired = (pan.state == UIGestureRecognizerStateEnded && dragged > trigger);

		self.swipingRow = -1;
		self.swipingCell = nil;
		self.swipeArmed = NO;
		self.swipeOffset = 0.0f;

		[self springReplySwipeBackInCell:cell from:travelled];
		if (fired)
			[self beginReplyToRow:row];
	}
}

- (void)beginReplyToRow:(NSInteger)row {
	if (![self canReplyToRow:row])
		return;
	NSDictionary *m = [self messageAtRow:row];
	[self setComposeMode:TGComposeModeReply messageId:[m[@"id"] longLongValue]];
	[self.sendButton setTitle:@"Send" forState:UIControlStateNormal];
	NSString *bodyText = [self textOf:m];
	[self showComposeBanner:[NSString stringWithFormat:@"Reply to: %@",
			bodyText.length ? bodyText : (m[@"kind"] ?: @"message")]];
	[self.input becomeFirstResponder];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] viaBotForMessage:m completion:^(NSString *username){
		TGChatViewController *me = weakSelf;
		if (!me || !username.length || me.replyToId != [m[@"id"] longLongValue])
			return;
		[me showComposeBanner:[NSString stringWithFormat:@"Reply to @%@: %@",
				username, bodyText.length ? bodyText : (m[@"kind"] ?: @"message")]];
	}];
}

- (void)chipsHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	TGReactionChipsView *chips = (TGReactionChipsView *)hold.view;
	if (![chips isKindOfClass:TGReactionChipsView.class] || !chips.messageId)
		return;
	self.chipsSheetMessageId = chips.messageId;
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:@"React",
																@"Who Reacted", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kChipsSheetTag;
	[sheet showInView:self.view];
}

- (void)runChipsOption:(NSString *)chosen {
	int64_t messageId = self.chipsSheetMessageId;
	if (!messageId)
		return;
	if ([chosen isEqualToString:@"React"]){
		UIView *source = self.table;
		for (NSIndexPath *path in [self.table indexPathsForVisibleRows]){
			NSDictionary *m = [self messageAtRow:path.row];
			if (m && [m[@"id"] isKindOfClass:NSNumber.class] &&
				[m[@"id"] longLongValue] == messageId){
				UITableViewCell *cell = [self.table cellForRowAtIndexPath:path];
				if ([cell isKindOfClass:TGBubbleCell.class])
					source = ((TGBubbleCell *)cell).bubble;
			}
		}
		[self showReactionPickerForMessage:messageId fromView:source];
		return;
	}
	if ([chosen isEqualToString:@"Who Reacted"])
		[self openReactionDetailForMessage:messageId];
}

- (void)showReactionPickerForMessage:(int64_t)messageId fromView:(UIView *)source {
	CGRect rect = [source convertRect:source.bounds toView:self.view];
	__weak typeof(self) weakSelf = self;
	[TGReactionPickerView showForMessage:messageId
								  inChat:self.chatId
								fromRect:rect
								  inView:self.view
								  picked:^(NSString *emoji, BOOL nowChosen){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[me.reactionChipsRequested removeObject:@(messageId)];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ [me reload]; });
	}];
}

/// The flattened message stores an absent value as NSNull, which answers no
/// string selector - asking one for its length is an unrecognized selector and
/// takes the app down.
- (NSString *)textOf:(NSDictionary *)m {
	if ([m[@"id"] isKindOfClass:NSNumber.class]){
		NSString *translated = self.translations[m[@"id"]];
		if ([translated isKindOfClass:NSString.class] && translated.length)
			return translated;
	}
	return [self originalTextOf:m];
}

- (NSString *)originalTextOf:(NSDictionary *)m {
	NSString *text = m[@"text"];
	if ([text isKindOfClass:NSString.class] && text.length)
		return text;
	NSString *kind = [m[@"kind"] isKindOfClass:NSString.class] ? m[@"kind"] : nil;
	NSString *placeholder = kind.length
			? [[TGClient shared] placeholderTextForContentKind:kind] : nil;
	if (placeholder.length)
		return placeholder;
	return [text isKindOfClass:NSString.class] ? text : nil;
}

/// Split out from the gesture so itglegacy://holdrow/N can reach it: a long
/// press cannot be delivered through a URL.
- (void)showActionsForRow:(NSInteger)row {
	NSDictionary *m = [self messageAtRow:row];
	if (!m)
		return;
	if ([m[@"service"] boolValue])
		return;
	if (![m[@"id"] isKindOfClass:NSNumber.class])
		return;
	self.actionMessage = m;

	if ([self offerBotButtonsForRow:row message:m])
		return;
	[self showActionsSheetForRow:row];
}

- (void)showActionsSheetForRow:(NSInteger)row {
	NSDictionary *m = [self messageAtRow:row];
	if (![m[@"id"] isKindOfClass:NSNumber.class])
		return;
	self.actionMessage = m;

	BOOL mine = [m[@"outgoing"] boolValue];
	int64_t messageId = [m[@"id"] longLongValue];

	// Beside the message rather than over the whole screen, which is what
	// makes it read as belonging to that bubble.
	CGRect rect = [self.table rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	CGPoint where = [self.table convertPoint:
			CGPointMake(mine ? CGRectGetMaxX(rect) - 60 : 60, CGRectGetMaxY(rect) - 8)
									  toView:self.view];

	[self.actionsSheet dismiss];
	TGMessageActionsSheet *sheet = [TGMessageActionsSheet sheetForMessage:messageId
																   inChat:self.chatId];
	sheet.messageText = [self textOf:m];
	sheet.pinned = (self.pinnedMessageId == messageId);
	sheet.allowsSelection = YES;
	self.actionsSheet = sheet;
	[self setPressedRow:row];

	__weak typeof(self) weakSelf = self;
	[sheet presentAtPoint:where inView:self.view completion:^(NSString *action){
		[weakSelf setPressedRow:-1];
		if (action)
			[weakSelf performMessageAction:action];
	}];
}

- (void)setPressedRow:(NSInteger)row {
	if (_pressedRow == row)
		return;
	NSInteger before = _pressedRow;
	_pressedRow = row;
	if (before >= 0)
		[self repaintBubbleArtworkOnRow:before];
	if (row >= 0)
		[self repaintBubbleArtworkOnRow:row];
}

- (void)repaintBubbleArtworkOnRow:(NSInteger)row {
	if (row < 0 || row >= [self displayRowCount])
		return;
	NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
	UITableViewCell *cell = [self.table cellForRowAtIndexPath:path];
	if (![cell isKindOfClass:TGBubbleCell.class])
		return;
	TGBubbleCell *bubbleCell = (TGBubbleCell *)cell;
	if (bubbleCell.bubbleBg.hidden)
		return;
	NSDictionary *m = [self messageAtRow:row];
	if (!m)
		return;

	BOOL mine = [m[@"outgoing"] boolValue];
	BOOL lit = (row == _pressedRow);
	NSString *name = mine ? @"Msg_Out" : @"Msg_In";
	if (lit)
		name = [name stringByAppendingString:@"_Selected"];
	UIImage *art = [UIImage imageNamed:name];
	if (!art)
		art = [UIImage imageNamed:(mine ? @"Msg_Out" : @"Msg_In")];
	if (!art)
		return;
	if (!lit){
		CATransition *fade = [CATransition animation];
		fade.duration = 0.25;
		fade.type = kCATransitionFade;
		[bubbleCell.bubbleBg.layer addAnimation:fade forKey:@"tgBubbleFade"];
	}
	bubbleCell.bubbleBg.image = [art stretchableImageWithLeftCapWidth:(mine ? 15 : 20)
														 topCapHeight:15];
}

- (void)messageDoubleTapped:(UITapGestureRecognizer *)tap {
	NSIndexPath *path = [self.table indexPathForRowAtPoint:[tap locationInView:self.table]];
	NSDictionary *m = path ? [self messageAtRow:path.row] : nil;
	if (!m)
		return;
	if ([m[@"service"] boolValue] || ![m[@"id"] isKindOfClass:NSNumber.class])
		return;
	[self sendQuickReactionToMessage:[m[@"id"] longLongValue]];
}

- (void)sendQuickReactionToMessage:(int64_t)messageId {
	if (!messageId || self.selecting)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] availableReactionsForMessage:messageId inChat:self.chatId
										 completion:^(NSDictionary *info){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSString *reason = [info[@"reason"] isKindOfClass:NSString.class]
				? info[@"reason"] : @"";
		if (reason.length){
			[me showAlertTitle:@"" message:reason];
			return;
		}
		NSArray *allowed = [info[@"allEmoji"] isKindOfClass:NSArray.class]
				? info[@"allEmoji"] : nil;
		NSString *emoji = [[TGClient shared] quickReactionEmoji];
		if (allowed.count && ![allowed containsObject:emoji])
			emoji = [allowed objectAtIndex:0];
		if (!emoji.length)
			return;
		[[TGClient shared] toggleReaction:emoji onMessage:messageId
								   inChat:me.chatId big:NO
							   completion:^(BOOL nowChosen){
			TGChatViewController *inner = weakSelf;
			if (!inner)
				return;
			[inner.reactionChipsRequested removeObject:@(messageId)];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
					dispatch_get_main_queue(), ^{ [inner reload]; });
		}];
	}];
}

/// The rows TGMessageActionsSheet reports back, each wired to the category
/// that owns it. Nothing here builds a TDLib request of its own.
- (void)performMessageAction:(NSString *)action {
	NSDictionary *m = self.actionMessage;
	if (![m[@"id"] isKindOfClass:NSNumber.class])
		return;
	int64_t messageId = [m[@"id"] longLongValue];
	NSString *bodyText = [self originalTextOf:m];
	__weak typeof(self) weakSelf = self;

	if ([action isEqualToString:TGMessageActionReply]){
		[self setComposeMode:TGComposeModeReply messageId:messageId];
		[self.sendButton setTitle:@"Send" forState:UIControlStateNormal];
		[self showComposeBanner:[NSString stringWithFormat:@"Reply to: %@",
				bodyText.length ? bodyText : (m[@"kind"] ?: @"message")]];
		[self.input becomeFirstResponder];

	} else if ([action isEqualToString:TGMessageActionEdit]){
		[self setComposeMode:TGComposeModeEdit messageId:messageId];
		self.input.text = bodyText ?: @"";
		[self inputChanged];
		[self.sendButton setTitle:@"Save" forState:UIControlStateNormal];
		[self showComposeBanner:@"Edit message"];
		[self.input becomeFirstResponder];

	} else if ([action isEqualToString:TGMessageActionCopy]){
		if (bodyText.length)
			[UIPasteboard generalPasteboard].string = bodyText;

	} else if ([action isEqualToString:TGMessageActionCopyLink]){
		[[TGClient shared] linkForMessage:messageId inChat:self.chatId inThread:NO
							   completion:^(NSString *link, BOOL isPublic){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!link.length){
				[me showAlertTitle:@"" message:@"This message has no public link."];
				return;
			}
			[UIPasteboard generalPasteboard].string = link;
			[me showAlertTitle:@"Link copied" message:link];
		}];

	} else if ([action isEqualToString:TGMessageActionForward]){
		self.forwardMessageId = messageId;
		[self showForwardOptions];

	} else if ([action isEqualToString:TGMessageActionTranslate]){
		[self translateMessage:messageId];

	} else if ([action isEqualToString:TGMessageActionPin]){
		[[TGClient shared] pinMessage:messageId inChat:self.chatId
							 silently:NO onlyForMe:NO completion:^(BOOL ok){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!ok){
				[me showAlertTitle:@"" message:@"This message could not be pinned."];
				return;
			}
			me.pinnedMessageId = messageId;
			[me loadPinnedMessage];
		}];

	} else if ([action isEqualToString:TGMessageActionUnpin]){
		[[TGClient shared] unpinMessage:messageId inChat:self.chatId
							 completion:^(BOOL ok){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!ok){
				[me showAlertTitle:@"" message:@"This message could not be unpinned."];
				return;
			}
			if (me.pinnedMessageId == messageId){
				me.pinnedMessageId = 0;
				[me hidePinnedBanner];
			}
			[me loadPinnedMessage];
		}];

	} else if ([action isEqualToString:TGMessageActionSelect]){
		[self beginSelectionWithMessage:messageId];

	} else if ([action isEqualToString:TGMessageActionReport]){
		self.reportMessageId = messageId;
		[self reportMessage:messageId optionId:nil];

	} else if ([action isEqualToString:TGMessageActionDeleteForMe]){
		[self deleteMessage:m forEveryone:[[TGClient shared] isSecretChat:self.chatId]];

	} else if ([action isEqualToString:TGMessageActionDeleteForEveryone]){
		[self deleteMessage:m forEveryone:YES];
	}
	self.actionMessage = nil;
}

/// The row goes off the screen at once and off the server when the undo runs
/// out, which is what the chat already did for its one Delete row.
- (void)deleteMessage:(NSDictionary *)m forEveryone:(BOOL)forEveryone {
	int64_t messageId = [m[@"id"] longLongValue];
	int64_t chatId = self.chatId;

	NSMutableArray *without = [self.messages mutableCopy];
	[without removeObject:m];
	self.messages = without;
	[self.table reloadData];
	[self updateEmptyState];

	__weak typeof(self) weakSelf = self;
	[TGSnackbar showInView:self.view
					  text:(forEveryone ? @"Deleted for everyone" : @"Deleted for you")
				   seconds:5
				  onCommit:^{
		[[TGClient shared] deleteMessages:@[@(messageId)] inChat:chatId
							  forEveryone:forEveryone completion:nil];
	}];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [weakSelf reload]; });

	[self offerModerationForMessage:m];
}

- (void)offerModerationForMessage:(NSDictionary *)m {
	if (!self.isGroup || [m[@"outgoing"] boolValue])
		return;
	int64_t senderId = [m[@"senderId"] longLongValue];
	if (senderId <= 0)
		return;
	if (!self.view.window)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] myAdministratorRightsInGroup:self.chatId
										 completion:^(NSDictionary *rights, NSString *status){
		TGChatViewController *me = weakSelf;
		if (!me || !rights || !me.view.window)
			return;
		BOOL canRestrict = [rights[@"can_restrict_members"] boolValue] ||
						   [status isEqualToString:@"creator"];
		if (!canRestrict)
			return;

		NSString *name = [[TGClient shared] nameForUserId:senderId];
		if (!name.length)
			name = @"this user";
		me.moderationUserId = senderId;
		me.moderationName = name;
		me.moderationMessageIds = ([m[@"id"] isKindOfClass:NSNumber.class]
				? @[m[@"id"]] : @[]);

		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:name
														   delegate:me
												  cancelButtonTitle:nil
											 destructiveButtonTitle:nil
												  otherButtonTitles:
						@"Delete All From This User",
						@"Ban From The Group",
						@"Report Spam", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Done"];
		sheet.tag = kModerationSheetTag;
		[sheet showInView:me.view];
	}];
}

- (void)runModerationAction:(NSString *)action {
	int64_t userId = self.moderationUserId;
	if (!userId)
		return;

	if ([action isEqualToString:@"Delete All From This User"]){
		__weak typeof(self) weakSelf = self;
		NSString *name = self.moderationName ?: @"this user";
		[[TGClient shared] deleteMessagesFromUser:userId inChat:self.chatId
									   completion:^(BOOL ok){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!ok){
				[me showAlertTitle:@""
						   message:[NSString stringWithFormat:
									@"The messages from %@ could not be deleted.", name]];
				return;
			}
			[me reload];
		}];
		return;
	}
	if ([action isEqualToString:@"Ban From The Group"]){
		__weak typeof(self) weakSelf = self;
		NSString *name = self.moderationName ?: @"";
		[[TGClient shared] banMember:userId
							 inGroup:self.chatId
						   untilDate:0
					  revokeMessages:NO
						  completion:^(BOOL ok){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			[me showAlertTitle:@""
					   message:(ok ? [NSString stringWithFormat:@"%@ can no longer post here.", name]
								   : @"This user could not be banned.")];
		}];
		return;
	}
	if ([action isEqualToString:@"Report Spam"] && self.moderationMessageIds.count){
		[[TGClient shared] reportSpamMessages:self.moderationMessageIds inGroup:self.chatId];
		[self showAlertTitle:@"" message:@"Thank you. This has been reported as spam."];
	}
}

/// Forwarding is three choices, not one: with the sender's name, without it,
/// and without the captions the media carries.
- (void)showForwardOptions {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Forward message"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:@"Forward",
														   @"Hide sender name",
														   @"Without caption", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kForwardSheetTag;
	[sheet showInView:self.view];
}

- (void)forwardWithCopy:(BOOL)asCopy removeCaptions:(BOOL)removeCaptions {
	int64_t messageId = self.forwardMessageId;
	if (!messageId)
		return;

	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	__weak typeof(self) weakSelf = self;
	picker.onPicked = ^(int64_t targetChatId){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] forwardMessages:@[@(messageId)]
								  fromChat:me.chatId
									toChat:targetChatId
									thread:0
									asCopy:asCopy
							removeCaptions:removeCaptions
									silent:NO
								completion:nil];
	};
	[self.navigationController pushViewController:picker animated:YES];
}

/// Translate into whatever the phone is set to, which is the only target a
/// screen with no language picker can honestly offer.
- (void)translateMessage:(int64_t)messageId {
	if (self.translations[@(messageId)]){
		[self.translations removeObjectForKey:@(messageId)];
		[self.table reloadData];
		return;
	}

	NSString *preferred = [[NSLocale preferredLanguages] firstObject];
	NSString *language = (preferred.length >= 2)
			? [preferred substringToIndex:2] : @"en";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] translateMessage:messageId
								 inChat:self.chatId
							 toLanguage:language
								   tone:nil
							 completion:^(NSString *text){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!text.length){
			[me showAlertTitle:@"" message:@"This message could not be translated."];
			return;
		}
		me.translations[@(messageId)] = text;
		[me.table reloadData];
	}];
}

/// TDLib asks for a reason before it accepts a report, and it asks in steps.
- (void)reportMessage:(int64_t)messageId optionId:(NSString *)optionId {
	[self reportMessage:messageId optionId:optionId text:@""];
}

- (void)reportMessage:(int64_t)messageId optionId:(NSString *)optionId text:(NSString *)text {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] reportMessages:@[@(messageId)]
							   inChat:self.chatId
							 optionId:optionId
								 text:(text ?: @"")
						   completion:^(NSDictionary *result){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSString *status = result[@"status"];
		if ([status isEqualToString:@"chooseOption"] && [result[@"options"] count]){
			me.reportOptions = result[@"options"];
			UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:
					(result[@"title"] ?: @"Report") delegate:me
										cancelButtonTitle:nil
								   destructiveButtonTitle:nil
										otherButtonTitles:nil];
			for (NSDictionary *option in me.reportOptions)
				[sheet addButtonWithTitle:(option[@"text"] ?: @"")];
			sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
			sheet.tag = kReportSheetTag;
			[sheet showInView:me.view];
			return;
		}
		if ([status isEqualToString:@"needText"]){
			me.reportMessageId = messageId;
			me.reportTextOptionId = result[@"optionId"] ?: optionId;
			UIAlertView *ask = [[TGAlertView alloc] initWithTitle:@"Report"
														  message:@"Add a comment"
														 delegate:me
												cancelButtonTitle:@"Cancel"
												otherButtonTitles:@"Send", nil];
			if ([ask respondsToSelector:@selector(setAlertViewStyle:)])
				ask.alertViewStyle = UIAlertViewStylePlainTextInput;
			ask.tag = kReportTextAlertTag;
			[ask show];
			return;
		}
		[me showAlertTitle:@""
				   message:([status isEqualToString:@"ok"]
						   ? @"Thank you. The message has been reported."
						   : @"This message could not be reported.")];
	}];
}

- (void)runMessageAction:(NSString *)action {
	NSDictionary *m = self.actionMessage;
	if (![m[@"id"] isKindOfClass:NSNumber.class])
		return;
	int64_t messageId = [m[@"id"] longLongValue];
	if (!messageId)
		return;
	NSString *bodyText = [self originalTextOf:m];

	if ([action isEqualToString:@"Reply"]){
		[self setComposeMode:TGComposeModeReply messageId:messageId];
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
		[self setComposeMode:TGComposeModeEdit messageId:messageId];
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

- (void)takePhoto {
	if (![self cameraAvailable] || self.postingBlocked)
		return;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypeCamera;
	picker.mediaTypes = @[(NSString *)kUTTypeImage];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (NSString *)stageImageForSending:(UIImage *)image {
	if (!image)
		return nil;
	NSData *jpeg = UIImageJPEGRepresentation(image, 0.85f);
	if (!jpeg.length)
		return nil;
	NSString *name = [NSString stringWithFormat:@"outgoing-%.0f.jpg",
			[[NSDate date] timeIntervalSince1970] * 1000];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	if (![jpeg writeToFile:path atomically:YES])
		return nil;
	return path;
}

- (void)pastePhoto {
	if (self.postingBlocked)
		return;
	UIImage *image = [self pasteboardImage];
	if (!image)
		return;
	self.pendingPastedImage = image;
	UIAlertView *ask = [[UIAlertView alloc] initWithTitle:@"Send Photo"
												  message:@"Send the image from the clipboard?"
												 delegate:self
										cancelButtonTitle:@"Cancel"
										otherButtonTitles:@"Send", nil];
	ask.tag = kPastePhotoAlertTag;
	[ask show];
}

- (void)sendPendingPastedImage {
	UIImage *image = self.pendingPastedImage;
	self.pendingPastedImage = nil;
	NSString *path = [self stageImageForSending:image];
	if (!path)
		return;
	[[TGClient shared] sendPhotoAtPath:path
								toChat:self.chatId
								thread:self.threadId
							   caption:@""
							   spoiler:NO
				   selfDestructSeconds:0];
	[self clearComposeState];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [self reload]; });
}

- (void)pickMusic {
	if (self.postingBlocked)
		return;
	MPMediaPickerController *picker = [[MPMediaPickerController alloc]
			initWithMediaTypes:MPMediaTypeMusic];
	picker.delegate = self;
	picker.allowsPickingMultipleItems = NO;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)mediaPicker:(MPMediaPickerController *)mediaPicker
		didPickMediaItems:(MPMediaItemCollection *)collection
{
	[mediaPicker dismissViewControllerAnimated:YES completion:nil];

	MPMediaItem *item = [collection.items firstObject];
	NSURL *asset = [item valueForProperty:MPMediaItemPropertyAssetURL];
	if (!asset){
		[self showAlertTitle:@"" message:@"This track cannot be sent."];
		return;
	}

	NSString *title = [item valueForProperty:MPMediaItemPropertyTitle];
	NSString *performer = [item valueForProperty:MPMediaItemPropertyArtist];
	NSNumber *seconds = [item valueForProperty:MPMediaItemPropertyPlaybackDuration];

	AVURLAsset *source = [AVURLAsset URLAssetWithURL:asset options:nil];
	AVAssetExportSession *export = [[AVAssetExportSession alloc]
			initWithAsset:source presetName:AVAssetExportPresetAppleM4A];
	if (!export){
		[self showAlertTitle:@"" message:@"This track cannot be sent."];
		return;
	}

	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"music-%.0f.m4a",
					[[NSDate date] timeIntervalSince1970] * 1000]];
	export.outputURL = [NSURL fileURLWithPath:path];
	export.outputFileType = AVFileTypeAppleM4A;

	__weak typeof(self) weakSelf = self;
	[export exportAsynchronouslyWithCompletionHandler:^{
		AVAssetExportSessionStatus status = export.status;
		dispatch_async(dispatch_get_main_queue(), ^{
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (status != AVAssetExportSessionStatusCompleted){
				[me showAlertTitle:@"" message:@"This track cannot be sent."];
				return;
			}
			[[TGClient shared] sendAudioAtPath:path
										toChat:me.chatId
										thread:me.threadId
										 title:title
									 performer:performer
									  duration:(NSInteger)[seconds doubleValue]
									   caption:@""];
			[me clearComposeState];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
					dispatch_get_main_queue(), ^{ [me reload]; });
		});
	}];
}

- (void)mediaPickerDidCancel:(MPMediaPickerController *)mediaPicker {
	[mediaPicker dismissViewControllerAnimated:YES completion:nil];
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
	NSString *mode = self.locationMode ?: @"point";

	if ([mode isEqualToString:@"tracking"]){
		if (fix && self.liveLocationMessageId)
			[[TGClient shared] updateLiveLocation:self.liveLocationMessageId
										   inChat:self.chatId
										 latitude:fix.coordinate.latitude
										longitude:fix.coordinate.longitude];
		return;
	}

	[manager stopUpdatingLocation];
	if (!fix)
		return;

	if ([mode isEqualToString:@"live"]){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] sendLiveLocationWithLatitude:fix.coordinate.latitude
											  longitude:fix.coordinate.longitude
												 period:3600
												 toChat:self.chatId
											 completion:^(int64_t messageId){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!messageId){
				me.locationMode = nil;
				[me showAlertTitle:@"" message:@"Live location could not be started."];
				return;
			}
			me.liveLocationMessageId = messageId;
			me.locationMode = @"tracking";
			me.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
			me.locationManager.distanceFilter = 50;
			[me.locationManager startUpdatingLocation];
			[TGSnackbar showInView:me.view text:@"Sharing your location for an hour"
						   seconds:3 onCommit:nil];
			[me reload];
		}];
		return;
	}

	if ([mode isEqualToString:@"venue"]){
		NSString *title = self.venueTitle ?: @"Place";
		[[TGClient shared] sendVenueWithTitle:title
									  address:(self.venueAddress ?: @"")
									 latitude:fix.coordinate.latitude
									longitude:fix.coordinate.longitude
									   toChat:self.chatId];
		self.venueTitle = nil;
		self.venueAddress = nil;
		self.locationMode = nil;
		[self clearComposeState];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ [self reload]; });
		return;
	}

	self.locationMode = nil;
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
	if (self.attachMode.length){
		[self handleAttachPickOfMovie:movie.path
								image:info[UIImagePickerControllerOriginalImage]];
		return;
	}
	if (movie){
		[[TGClient shared] sendVideoAtPath:movie.path toChat:self.chatId];
		return;
	}

	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (!image)
		return;

	// TDLib wants a path, so write the pick to a temporary file first.
	NSString *path = [self stageImageForSending:image];
	if (!path){
		NSLog(@"cannot stage the picked image");
		return;
	}
	[[TGClient shared] sendPhotoAtPath:path
								toChat:self.chatId
								thread:self.threadId
							   caption:@""
							   spoiler:NO
				   selfDestructSeconds:0];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [self reload]; });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	self.attachMode = nil;
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleAttachPickOfMovie:(NSString *)moviePath image:(UIImage *)image {
	NSString *mode = self.attachMode;
	self.attachMode = nil;
	if (self.postingBlocked)
		return;

	if ([mode isEqualToString:@"animation"]){
		if (!moviePath.length){
			[self showAlertTitle:@"" message:@"A GIF is made from a video."];
			return;
		}
		[[TGClient shared] sendAnimationAtPath:moviePath toChat:self.chatId
										thread:self.threadId caption:@""];
		[self clearComposeState];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ [self reload]; });
		return;
	}

	if ([mode isEqualToString:@"document"]){
		NSString *path = moviePath.length ? moviePath : [self stageImageForSending:image];
		if (!path.length){
			[self showAlertTitle:@"" message:@"This file could not be prepared."];
			return;
		}
		[[TGClient shared] sendDocumentAtPath:path toChat:self.chatId
									   thread:self.threadId caption:@""];
		[self clearComposeState];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ [self reload]; });
		return;
	}
}

- (void)pickPhotoAlbum {
	if (self.postingBlocked)
		return;
	if (![TGAssetPicker available]){
		[self showAlertTitle:@""
					 message:@"Telegram has no access to your photos. "
							 @"Turn Photos on in Settings, Privacy."];
		return;
	}

	TGAssetPicker *picker = [[TGAssetPicker alloc] init];
	picker.selectionLimit = kAlbumSelectionLimit;
	__weak typeof(self) weakSelf = self;
	picker.onCancelled = ^{
		TGChatViewController *me = weakSelf;
		[me dismissViewControllerAnimated:YES completion:nil];
	};
	picker.onPicked = ^(NSArray *paths){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[me dismissViewControllerAnimated:YES completion:nil];
		[me sendPickedPhotos:paths];
	};
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)sendPickedPhotos:(NSArray *)paths {
	if (self.postingBlocked)
		return;
	if (!paths.count){
		[self showAlertTitle:@"" message:@"Those photos could not be prepared."];
		return;
	}

	NSString *caption = @"";
	if (self.composeMode != TGComposeModeEdit){
		NSString *typed = [self.input.text stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (typed.length){
			caption = typed;
			self.input.text = @"";
		}
	}
	[self clearComposeState];

	if (paths.count == 1){
		[[TGClient shared] sendPhotoAtPath:[paths objectAtIndex:0]
									toChat:self.chatId
									thread:self.threadId
								   caption:caption
								   spoiler:NO
					   selfDestructSeconds:0];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ [self reload]; });
		return;
	}

	[self sendAlbumBatch:paths caption:caption];
}

- (void)sendAlbumBatch:(NSArray *)paths caption:(NSString *)caption {
	if (!paths.count)
		return;

	NSUInteger take = MIN((NSUInteger)kAlbumBatchLimit, paths.count);
	NSArray *batch = [paths subarrayWithRange:NSMakeRange(0, take)];
	NSArray *rest = [paths subarrayWithRange:NSMakeRange(take, paths.count - take)];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sendPhotoAlbumAtPaths:batch
									  toChat:self.chatId
									  thread:self.threadId
									 caption:(caption ?: @"")
								  completion:^(NSInteger sent){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!sent){
			[me showAlertTitle:@"" message:@"This album could not be sent."];
			return;
		}
		if (rest.count){
			[me sendAlbumBatch:rest caption:@""];
			return;
		}
		[me reload];
	}];
}

#pragma mark - taps

- (void)simulateTapOnRow:(NSInteger)row {
	NSDictionary *tapped = [self messageAtRow:row];
	if (!tapped){
		NSLog(@"tap: row %ld out of range (%ld)",
				(long)row, (long)[self displayRowCount]);
		return;
	}
	NSLog(@"tap: row %ld, kind %@", (long)row, tapped[@"kind"]);
	[self tableView:self.table
			didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
}


- (void)openPhotoMessage:(NSDictionary *)m {
	NSNumber *fileId = [m[@"photoId"] isKindOfClass:NSNumber.class] ? m[@"photoId"] : nil;
	if (!fileId)
		return;
	[self.photoFilesFailed removeObject:fileId];
	[self.photoFilesCancelled removeObject:fileId];
	[self showGalleryForMessage:m];
}

- (void)playMovieMessage:(NSDictionary *)m {
	NSNumber *docId = m[@"docId"];
	if (![docId isKindOfClass:NSNumber.class])
		return;
	[self beginDownloadHUDForFile:[docId integerValue]];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[me endDownloadHUDForFile:[docId integerValue]];
		if (!path)
			return;
		MPMoviePlayerViewController *player = [[MPMoviePlayerViewController alloc]
				initWithContentURL:[NSURL fileURLWithPath:path]];
		[me presentMoviePlayerViewControllerAnimated:player];
	}];
}

- (void)albumTileTapped:(UITapGestureRecognizer *)tap {
	if (![tap.view isKindOfClass:TGMosaicTileView.class])
		return;
	TGMosaicTileView *tile = (TGMosaicTileView *)tap.view;

	UIView *walk = tile;
	while (walk && ![walk isKindOfClass:TGBubbleCell.class])
		walk = walk.superview;
	NSIndexPath *path = walk
			? [self.table indexPathForCell:(UITableViewCell *)walk] : nil;
	if (!path)
		return;

	if (self.selecting){
		[self toggleSelectionOfRow:path.row];
		return;
	}

	NSArray *album = [self messagesAtRow:path.row];
	if (tile.tileIndex < 0 || tile.tileIndex >= (NSInteger)album.count)
		return;
	NSDictionary *m = album[tile.tileIndex];
	if ([m[@"id"] isKindOfClass:NSNumber.class])
		[[TGClient shared] openContentOfMessage:[m[@"id"] longLongValue]
										 inChat:self.chatId];

	NSString *kind = m[@"kind"];
	if ([kind isEqualToString:@"messageVideo"] ||
		[kind isEqualToString:@"messageAnimation"])
		[self playMovieMessage:m];
	else
		[self openPhotoMessage:m];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:NO];
	NSDictionary *m = [self messageAtRow:indexPath.row];
	if (!m)
		return;
	NSString *kind = m[@"kind"];

	if (self.selecting){
		[self toggleSelectionOfRow:indexPath.row];
		return;
	}

	if ([m[@"outgoing"] boolValue] &&
		[[self sendStateForMessage:m] isEqualToString:@"failed"] &&
		[m[@"id"] isKindOfClass:NSNumber.class]){
		[self offerResendOfMessage:[m[@"id"] longLongValue]];
		return;
	}

	if ([kind isEqualToString:@"messagePinMessage"]){
		[self jumpToPinnedMessageBehind:m];
		return;
	}

	NSTimeInterval offset = [self mediaTimestampInMessage:m];
	if (offset >= 0 && [self openMediaTimestamp:offset forRow:indexPath.row])
		return;

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

	if ([kind isEqualToString:@"messageVoiceNote"] || [kind isEqualToString:@"messageAudio"] ||
		[kind isEqualToString:@"messageVideoNote"] || [kind isEqualToString:@"messageVideo"] ||
		[kind isEqualToString:@"messagePhoto"]){
		if ([m[@"id"] isKindOfClass:NSNumber.class])
			[[TGClient shared] openContentOfMessage:[m[@"id"] longLongValue]
											 inChat:self.chatId];
	}

	if ([m[@"id"] isKindOfClass:NSNumber.class] && [self largeEmojiCountFor:m] > 0){
		[self playAnimatedEmojiEffectFor:[m[@"id"] longLongValue]];
		return;
	}

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
			[me endDownloadHUDForFile:[docId integerValue]];
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
			[self endDownloadHUDForFile:[docId integerValue]];
			if (path)
				[self playVideoNoteAtPath:path row:indexPath.row];
		}];
		return;
	}

	if ([kind isEqualToString:@"messageVideo"] ||
		[kind isEqualToString:@"messageAnimation"]){
		[self playMovieMessage:m];
		return;
	}

	// Voice notes are Opus, which iOS 7 cannot decode - convert, then play.
	if ([kind isEqualToString:@"messageVoiceNote"] ||
		[kind isEqualToString:@"messageAudio"]){
		[self playAudioMessage:m fromSeconds:0];
		return;
	}

	if ([kind isEqualToString:@"messageText"]){
		[self openLinkInMessage:m];
		return;
	}

	if ([kind isEqualToString:@"messagePhoto"]){
		[self openPhotoMessage:m];
		return;
	}

	[self tapFellThroughOnMessage:m];
}

- (void)tapFellThroughOnMessage:(NSDictionary *)m {
	NSNumber *replyTo = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	if (replyTo && [self scrollToMessageId:replyTo.longLongValue])
		return;
	[self touchedMessageBackground];
}

- (void)jumpToPinnedMessageBehind:(NSDictionary *)m {
	NSNumber *replyTo = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	if (replyTo && [self scrollToMessageId:replyTo.longLongValue])
		return;
	if (![m[@"id"] isKindOfClass:NSNumber.class]){
		[self touchedMessageBackground];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] request:@{@"@type"      : @"getRepliedMessage",
								 @"chat_id"    : @(self.chatId),
								 @"message_id" : m[@"id"]}
					completion:^(NSDictionary *result){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		int64_t pinned = [result[@"id"] longLongValue];
		if (!pinned || ![me scrollToMessageId:pinned])
			[me showAlertTitle:@"" message:@"That message is not in the loaded history."];
	}];
}

- (void)offerResendOfMessage:(int64_t)messageId {
	self.failedMessageId = messageId;
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"This message was not sent"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:@"Send Again", nil];
	[sheet addButtonWithTitle:@"Delete"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kFailedMessageSheetTag;
	[sheet showInView:self.view];
}

- (void)runFailedMessageOption:(NSString *)chosen {
	int64_t messageId = self.failedMessageId;
	self.failedMessageId = 0;
	if (!messageId)
		return;

	if ([chosen isEqualToString:@"Delete"]){
		NSInteger row = [self rowForMessageId:messageId];
		NSDictionary *found = (row != NSNotFound) ? [self messageAtRow:row] : nil;
		if (found)
			[self deleteMessage:found forEveryone:NO];
		return;
	}
	if (![chosen isEqualToString:@"Send Again"])
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] resendMessages:@[@(messageId)] inChat:self.chatId
						   completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[me.sendStates removeObjectForKey:@(messageId)];
		[me.sendStatesRequested removeObject:@(messageId)];
		if (!messages.count){
			[me showAlertTitle:@"" message:@"This could not be sent again."];
			return;
		}
		[me reload];
	}];
}

/// The effect is a sticker TDLib names for us: fetch it, show it over the
/// chat for a moment, and let it go again - nothing is kept.
- (void)playAnimatedEmojiEffectFor:(int64_t)messageId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] clickAnimatedEmojiInMessage:messageId inChat:self.chatId
										completion:^(NSInteger stickerFileId){
		TGChatViewController *me = weakSelf;
		if (!me || stickerFileId <= 0)
			return;
		[[TGClient shared] downloadFile:stickerFileId completion:^(NSString *path){
			TGChatViewController *inner = weakSelf;
			if (!inner || !path.length)
				return;
			UIImage *sticker = [UIImage imageWithContentsOfFile:path];
			if (!sticker && [path.pathExtension.lowercaseString isEqualToString:@"webp"])
				sticker = [UIImage convertFromWebP:path compressedData:nil error:nil];
			if (!sticker)
				return;
			UIImageView *effect = [[UIImageView alloc] initWithImage:
					TGImageDrawnAtPointSize(sticker, CGSizeMake(140, 140))];
			effect.frame = CGRectMake(0, 0, 140, 140);
			effect.center = CGPointMake(CGRectGetMidX(inner.view.bounds),
										CGRectGetMidY(inner.view.bounds));
			effect.userInteractionEnabled = NO;
			[inner.view addSubview:effect];
			[UIView animateWithDuration:0.9 animations:^{
				effect.alpha = 0.0f;
			} completion:^(BOOL finished){
				[effect removeFromSuperview];
			}];
		}];
	}];
}

- (void)playAudioMessage:(NSDictionary *)m fromSeconds:(NSTimeInterval)seconds {
	[[TGMusicPlayer shared] playMessage:m
								 inChat:self.chatId
							  chatTitle:self.chatTitle
							fromSeconds:seconds];
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

- (NSDictionary *)galleryItemForMessage:(NSDictionary *)m {
	NSString *kind = [m[@"kind"] isKindOfClass:NSString.class] ? m[@"kind"] : @"";
	BOOL isVideo = [kind isEqualToString:@"messageVideo"];
	if (!isVideo && ![kind isEqualToString:@"messagePhoto"])
		return nil;

	NSNumber *pictureId = [m[@"photoId"] isKindOfClass:NSNumber.class] ? m[@"photoId"] : nil;
	NSNumber *movieId = [m[@"docId"] isKindOfClass:NSNumber.class] ? m[@"docId"] : nil;
	NSNumber *fullId = isVideo ? movieId : pictureId;
	if (!fullId || [fullId integerValue] <= 0)
		return nil;

	NSNumber *thumbId = [self pictureFileIdFor:m] ?: (pictureId ?: fullId);
	NSString *caption = [m[@"text"] isKindOfClass:NSString.class] ? m[@"text"] : @"";
	NSString *author = [m[@"outgoing"] boolValue]
			? @"" : ([[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]] ?: @"");

	NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:@{
		@"fullId"    : fullId,
		@"thumbId"   : thumbId,
		@"caption"   : caption,
		@"author"    : author,
		@"date"      : m[@"date"] ?: @(0),
		@"messageId" : m[@"id"] ?: @(0),
		@"duration"  : m[@"duration"] ?: @(0),
		@"isVideo"   : @(isVideo),
	}];
	NSDictionary *minithumb = m[@"minithumbnail"];
	if ([minithumb isKindOfClass:NSDictionary.class])
		item[@"minithumb"] = minithumb;
	return item;
}

- (NSArray *)galleryItemsForMessageId:(int64_t)messageId index:(NSInteger *)index {
	NSMutableArray *items = [NSMutableArray array];
	if (index)
		*index = 0;

	for (NSDictionary *m in self.messages){
		NSDictionary *item = [self galleryItemForMessage:m];
		if (!item)
			continue;
		if (index && messageId != 0 && [m[@"id"] longLongValue] == messageId)
			*index = (NSInteger)items.count;
		[items addObject:item];
	}
	return items;
}

- (void)showGalleryForMessage:(NSDictionary *)m {
	NSInteger index = 0;
	NSArray *items = [self galleryItemsForMessageId:[m[@"id"] longLongValue] index:&index];

	if (items.count == 0){
		NSDictionary *only = [self galleryItemForMessage:m];
		if (!only)
			return;
		items = @[only];
		index = 0;
	}

	TGMediaFullscreenController *viewer = [[TGMediaFullscreenController alloc]
			initWithItems:items index:index];
	viewer.chatId = self.chatId;

	__weak typeof(self) weakSelf = self;
	viewer.onMessageDeleted = ^(int64_t deletedId){
		[weakSelf dropMessageWithId:deletedId];
	};

	[self presentViewController:viewer animated:YES completion:nil];
}

- (void)dropMessageWithId:(int64_t)messageId {
	NSMutableArray *left = [NSMutableArray arrayWithCapacity:self.messages.count];
	for (NSDictionary *m in self.messages){
		if ([m[@"id"] longLongValue] == messageId)
			continue;
		[left addObject:m];
	}
	if (left.count == self.messages.count)
		return;
	self.messages = left;
	[self.table reloadData];
	[self updateEmptyState];
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
	if ([self.quotesMissing containsObject:replyId])
		return nil;
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

- (NSString *)quoteKindLabelFor:(NSDictionary *)original {
	NSString *kind = original[@"kind"];
	if ([kind isEqualToString:@"messagePhoto"])        return @"Photo";
	if ([kind isEqualToString:@"messageVideo"])        return @"Video";
	if ([kind isEqualToString:@"messageAnimation"])    return @"GIF";
	if ([kind isEqualToString:@"messageVoiceNote"])    return @"Voice message";
	if ([kind isEqualToString:@"messageVideoNote"])    return @"Video message";
	if ([kind isEqualToString:@"messageAudio"])        return @"Music";
	if ([kind isEqualToString:@"messageDocument"])     return @"File";
	if ([kind isEqualToString:@"messageContact"])      return @"Contact";
	if ([kind isEqualToString:@"messagePoll"])         return @"Poll";
	if ([kind isEqualToString:@"messageLocation"])     return @"Location";
	if ([kind isEqualToString:@"messageLiveLocation"]) return @"Live location";
	if ([kind isEqualToString:@"messageSticker"] ||
		[kind isEqualToString:@"messageAnimatedEmoji"]){
		NSString *text = original[@"text"];
		return [text isKindOfClass:NSString.class] && text.length
				? [NSString stringWithFormat:@"Sticker %@", text] : @"Sticker";
	}
	return nil;
}

/// The line under the author in a reply bar: what was said, or what kind of
/// thing it was when there is nothing to quote.
- (NSString *)quoteDisplayTextFor:(NSDictionary *)m {
	NSString *text = [self quoteTextFor:m];
	if (text.length && ![text isEqualToString:@"..."])
		return text;
	NSNumber *replyId = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	NSDictionary *original = replyId ? self.quotes[replyId] : nil;
	NSString *label = original ? [self quoteKindLabelFor:original] : nil;
	return label ?: text;
}

/// The little rounded picture of the thing being answered, once its thumbnail
/// has come down.
- (UIImage *)quoteThumbnailFor:(NSDictionary *)m {
	NSNumber *replyId = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	if (!replyId)
		return nil;
	NSDictionary *original = self.quotes[replyId];
	NSNumber *fileId = original[@"photoId"];
	return [fileId isKindOfClass:NSNumber.class] ? self.images[fileId] : nil;
}

- (CGFloat)chipsRowHeightFor:(NSDictionary *)m {
	NSArray *chips = [self chipsFor:m];
	if (chips.count)
		return [TGReactionChipsView heightForChips:chips
											 width:[self chipsRowWidthFor:m]];
	return [m[@"reactions"] length] ? [TGReactionChipsView rowHeight] : 0;
}

- (CGFloat)reactionsBlockHeightFor:(NSDictionary *)m {
	CGFloat row = [self chipsRowHeightFor:m];
	return row > 0 ? row + kChipsRowTopGap + kChipsRowBottomGap : 0;
}

static NSString *TGCompactCount(long long count) {
	if (count >= 1000000){
		long long remainder = (count % 1000000) / 100000;
		return remainder
				? [NSString stringWithFormat:@"%lld.%lldM", count / 1000000, remainder]
				: [NSString stringWithFormat:@"%lldM", count / 1000000];
	}
	if (count >= 1000){
		long long remainder = (count % 1000) / 100;
		return remainder
				? [NSString stringWithFormat:@"%lld.%lldK", count / 1000, remainder]
				: [NSString stringWithFormat:@"%lldK", count / 1000];
	}
	return [NSString stringWithFormat:@"%lld", count];
}

- (NSString *)signatureLineFor:(NSDictionary *)m {
	NSString *signature = [m[@"signature"] isKindOfClass:NSString.class]
			? m[@"signature"] : nil;
	long long views = [m[@"views"] longLongValue];
	if (!signature.length && views <= 0)
		return nil;

	if (!signature.length)
		return TGCompactCount(views);
	if (views <= 0)
		return signature;
	return [NSString stringWithFormat:@"%@   %@", TGCompactCount(views), signature];
}

- (BOOL)showsViewCountFor:(NSDictionary *)m {
	return [m[@"views"] longLongValue] > 0 && [self signatureLineFor:m] != nil;
}

static UIImage *TGViewsEyeImage(UIColor *tint) {
	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [NSMutableDictionary dictionary];

	const CGFloat w = 12.0f;
	const CGFloat h = 8.0f;
	CGFloat r = 0, g = 0, b = 0, a = 0;
	if (![tint respondsToSelector:@selector(getRed:green:blue:alpha:)] ||
		![tint getRed:&r green:&g blue:&b alpha:&a]){
		r = g = b = 0.5f; a = 1.0f;
	}
	NSString *key = [NSString stringWithFormat:@"%.3f-%.3f-%.3f-%.3f", r, g, b, a];
	UIImage *cached = cache[key];
	if (cached)
		return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(w, h), NO, 0.0f);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetRGBStrokeColor(ctx, r, g, b, a);
	CGContextSetRGBFillColor(ctx, r, g, b, a);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextSetLineCap(ctx, kCGLineCapRound);

	CGContextMoveToPoint(ctx, 0.5f, h / 2);
	CGContextAddCurveToPoint(ctx, w * 0.3f, 0.5f, w * 0.7f, 0.5f, w - 0.5f, h / 2);
	CGContextAddCurveToPoint(ctx, w * 0.7f, h - 0.5f, w * 0.3f, h - 0.5f, 0.5f, h / 2);
	CGContextStrokePath(ctx);
	CGContextFillEllipseInRect(ctx, CGRectMake(w / 2 - 1.5f, h / 2 - 1.5f, 3, 3));

	UIImage *eye = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (eye)
		cache[key] = eye;
	return eye;
}

static const CGFloat kViewsEyeWidth = 12.0f;
static const CGFloat kViewsEyeGap   = 3.0f;

- (CGFloat)gapUnderMediaFor:(NSDictionary *)m {
	return [self bodySizeFor:m].height > 0 ? 4 : 0;
}

- (CGFloat)signatureBlockHeightFor:(NSDictionary *)m {
	return [self signatureLineFor:m] ? kSignatureHeight + kSignatureTopGap : 0;
}

- (CGFloat)signatureWidthFor:(NSDictionary *)m {
	NSString *line = [self signatureLineFor:m];
	if (!line)
		return 0;
	CGFloat w = ceilf([line sizeWithFont:[UIFont systemFontOfSize:11]].width);
	if ([self showsViewCountFor:m])
		w += kViewsEyeWidth + kViewsEyeGap;
	return w;
}

- (CGFloat)bareReactionsHeightFor:(NSDictionary *)m {
	CGFloat row = [self chipsRowHeightFor:m];
	return row > 0 ? row + kBareChipsTopGap : 0;
}

- (CGFloat)headDecorationHeightFor:(NSDictionary *)m {
	CGFloat h = 0;
	if ([m[@"forward"] length])
		h += 18;
	// Their reply block is two lines beside a stripe: the author, then what
	// they said.
	if ([self quoteTextFor:m])
		h += 38;
	return h;
}

- (CGFloat)footDecorationHeightFor:(NSDictionary *)m {
	CGFloat h = 0;
	CGFloat previewH = [self previewSizeFor:m].height;
	if (previewH > 0)
		h += previewH + 6;
	h += [self signatureBlockHeightFor:m];
	h += [self reactionsBlockHeightFor:m];
	return h;
}

- (CGFloat)decorationHeightFor:(NSDictionary *)m {
	return [self headDecorationHeightFor:m] + [self footDecorationHeightFor:m];
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

- (CGFloat)bubbleWidthBudget {
	if (!TGChatIsPad())
		return kBubbleMaxW;

	CGFloat width = self.table ? self.table.bounds.size.width : 0;
	if (width < 1)
		width = self.view.bounds.size.width;
	if (width <= kBubbleReferenceWidth)
		return kBubbleMaxW;

	return floorf(width * (kBubbleBudgetAtReference / kBubbleReferenceWidth))
			- kBubbleTailOverhang;
}

- (CGFloat)maxBubbleWidthFor:(NSDictionary *)m {
	CGFloat w = [self bubbleWidthBudget];
	if ([m[@"outgoing"] boolValue])
		w -= kBubbleOutgoingTrim;
	else if (self.isGroup &&
			 [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]])
		w -= kBubbleAvatarTrim;
	return w;
}

/// Their forwarded line: "Forwarded from" in grey with the name after it in
/// the accent colour. Returns the height it took, so every kind of bubble can
/// carry it by shifting its own content down - a forwarded file used to look
/// exactly like one you had been sent directly.
- (CGFloat)layoutForwardIn:(TGBubbleCell *)cell
				   message:(NSDictionary *)m
					   atY:(CGFloat)y
					 width:(CGFloat)width
{
	NSString *from = m[@"forward"];
	if (![from length]){
		cell.forwardLabel.hidden = YES;
		cell.forwardLabel.userInteractionEnabled = NO;
		cell.forwardJump.hidden = YES;
		cell.forwardChatId = 0;
		cell.forwardMessageId = 0;
		cell.forwardUserId = 0;
		cell.forwardTitle = nil;
		return 0;
	}

	int64_t originChat = [m[@"forwardChatId"] longLongValue];
	NSString *originTitle = originChat
			? [[TGClient shared] cachedTitleForChatId:originChat] : nil;
	if (originTitle.length)
		from = originTitle;

	cell.forwardChatId    = originChat;
	cell.forwardMessageId = [m[@"forwardMessageId"] longLongValue];
	cell.forwardUserId    = [m[@"forwardUserId"] longLongValue];
	cell.forwardTitle     = from;
	cell.forwardLabel.userInteractionEnabled =
			(cell.forwardChatId != 0 || cell.forwardUserId != 0);
	[self attachForwardTapTo:cell.forwardLabel];

	BOOL mine = [m[@"outgoing"] boolValue];
	UIColor *titleColour = mine ? TGChatHexColour(0x3a8e26)
								: TGChatHexColour(0x0e7acd);
	UIColor *nameColour  = mine ? TGChatHexColour(0x169600)
								: TGChatHexColour(0x0e7acd);
	BOOL canJump = [m[@"forwardIsChannel"] boolValue] &&
			cell.forwardChatId != 0 && cell.forwardMessageId != 0;
	CGFloat labelW = width - 2 * kPadH - (canJump ? kForwardJumpSide + 6 : 0);

	cell.forwardLabel.hidden = NO;
	cell.forwardLabel.frame = CGRectMake(kPadH, y, MAX(labelW, 20), 16);
	[self layoutForwardJumpIn:cell atY:y width:width wanted:canJump];

	NSString *line = [NSString stringWithFormat:@"Forwarded from %@", from];
	if ([cell.forwardLabel respondsToSelector:@selector(setAttributedText:)]){
		NSMutableAttributedString *styled =
				[[NSMutableAttributedString alloc] initWithString:line];
		[styled addAttribute:NSForegroundColorAttributeName
					   value:titleColour
					   range:NSMakeRange(0, line.length)];
		[styled addAttribute:NSForegroundColorAttributeName
					   value:nameColour
					   range:NSMakeRange(15, from.length)];
		[styled addAttribute:NSFontAttributeName
					   value:[UIFont boldSystemFontOfSize:13]
					   range:NSMakeRange(15, from.length)];
		cell.forwardLabel.attributedText = styled;
	} else {
		cell.forwardLabel.textColor = nameColour;
		cell.forwardLabel.text = line;
	}
	return 18;
}

static UIImage *TGForwardJumpImage(BOOL pressed) {
	static UIImage *plain = nil;
	static UIImage *held = nil;
	UIImage *cached = pressed ? held : plain;
	if (cached)
		return cached;

	UIImage *source = [UIImage imageNamed:
			(pressed ? @"ConversationScrollDown_Highlighted.png"
					 : @"ConversationScrollDown.png")];
	if (!source)
		return nil;

	CGSize size = CGSizeMake(kForwardJumpSide, kForwardJumpSide);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextTranslateCTM(ctx, size.width / 2, size.height / 2);
	CGContextRotateCTM(ctx, -M_PI_2);
	[source drawInRect:CGRectMake(-size.width / 2, -size.height / 2,
								  size.width, size.height)];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	if (pressed)
		held = image;
	else
		plain = image;
	return image;
}

static const NSInteger kForwardJumpTag = 0x9201;

- (void)layoutForwardJumpIn:(TGBubbleCell *)cell
						atY:(CGFloat)y
					  width:(CGFloat)width
					 wanted:(BOOL)wanted
{
	cell.forwardJump.hidden = !wanted;
	if (!wanted)
		return;

	if (cell.forwardJump.tag != kForwardJumpTag){
		[cell.forwardJump addTarget:self
							 action:@selector(forwardJumpTapped:)
				   forControlEvents:UIControlEventTouchUpInside];
		[cell.forwardJump setImage:TGForwardJumpImage(NO)
						  forState:UIControlStateNormal];
		[cell.forwardJump setImage:TGForwardJumpImage(YES)
						  forState:UIControlStateHighlighted];
		cell.forwardJump.tag = kForwardJumpTag;
		[cell.bubble bringSubviewToFront:cell.forwardJump];
	}
	cell.forwardJump.userInteractionEnabled = !self.selecting;

	CGFloat lineMiddle = y + 8;
	CGFloat top = lineMiddle - 13;
	if (top < 0)
		top = 0;
	cell.forwardJump.frame = CGRectMake(width - kPadH - kForwardJumpSide - 6,
										top, kForwardJumpSide + 12, 26);
}

- (void)forwardJumpTapped:(UIButton *)button {
	UIView *view = button;
	while (view && ![view isKindOfClass:TGBubbleCell.class])
		view = view.superview;
	TGBubbleCell *cell = (TGBubbleCell *)view;
	if (!cell || !cell.forwardChatId)
		return;
	[self openForwardOriginChat:cell.forwardChatId
						  title:cell.forwardTitle
						message:cell.forwardMessageId];
}

static const NSInteger kForwardTapTag = 0x9200;

- (void)attachForwardTapTo:(UILabel *)label {
	if (label.tag == kForwardTapTag)
		return;
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(forwardHeaderTapped:)];
	[label addGestureRecognizer:tap];
	label.tag = kForwardTapTag;
}

- (void)forwardHeaderTapped:(UITapGestureRecognizer *)tap {
	UIView *view = tap.view;
	while (view && ![view isKindOfClass:TGBubbleCell.class])
		view = view.superview;
	TGBubbleCell *cell = (TGBubbleCell *)view;
	if (!cell)
		return;

	if (cell.forwardChatId){
		[self openForwardOriginChat:cell.forwardChatId
							  title:cell.forwardTitle
							message:cell.forwardMessageId];
		return;
	}
	if (cell.forwardUserId)
		[self openForwardOriginUser:cell.forwardUserId title:cell.forwardTitle];
}

static const NSInteger kAvatarTapTag = 0x9300;
static const NSInteger kSenderTapTag = 0x9301;

- (void)attachAvatarTapIn:(TGBubbleCell *)cell sender:(int64_t)senderId {
	cell.avatarUserId = senderId;
	BOOL live = (senderId > 0 && !self.selecting);
	cell.senderAvatar.userInteractionEnabled = live;
	cell.sender.userInteractionEnabled = live;

	if (cell.senderAvatar.tag != kAvatarTapTag){
		[cell.senderAvatar addGestureRecognizer:[[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(senderAvatarTapped:)]];
		[cell.senderAvatar addGestureRecognizer:[self senderHoldRecognizer]];
		cell.senderAvatar.tag = kAvatarTapTag;
	}
	if (cell.sender.tag != kSenderTapTag){
		[cell.sender addGestureRecognizer:[[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(senderAvatarTapped:)]];
		[cell.sender addGestureRecognizer:[self senderHoldRecognizer]];
		cell.sender.tag = kSenderTapTag;
	}
}

- (UILongPressGestureRecognizer *)senderHoldRecognizer {
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(senderHeld:)];
	hold.minimumPressDuration = 0.24;
	hold.allowableMovement = 10.0f;
	return hold;
}

- (int64_t)senderOfGestureView:(UIView *)view {
	while (view && ![view isKindOfClass:TGBubbleCell.class])
		view = view.superview;
	TGBubbleCell *cell = (TGBubbleCell *)view;
	if (!cell || self.selecting)
		return 0;
	return cell.avatarUserId;
}

- (void)senderAvatarTapped:(UITapGestureRecognizer *)tap {
	if (tap.state != UIGestureRecognizerStateRecognized)
		return;
	[self openProfileForUserId:[self senderOfGestureView:tap.view]];
}

- (void)senderHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	[self showPeerMenuForUserId:[self senderOfGestureView:hold.view]];
}

- (void)openProfileForUserId:(int64_t)userId {
	if (userId <= 0)
		return;
	UINavigationController *navigation = self.navigationController;
	if (!navigation)
		return;
	NSString *name = [[TGClient shared] nameForUserId:userId] ?: @"";
	[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
		if (!chatId)
			return;
		TGProfileViewController *profile = [[TGProfileViewController alloc]
				initWithChatId:chatId userId:userId title:name];
		[navigation pushViewController:profile animated:YES];
	}];
}

- (void)openForwardOriginUser:(int64_t)userId title:(NSString *)title {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
		TGChatViewController *me = weakSelf;
		if (!me || !chatId)
			return;
		[me openChatId:chatId
				 title:(title.length ? title : @"Chat")
			   isGroup:NO
		   focusMessage:0];
	}];
}

- (void)openForwardOriginChat:(int64_t)chatId
						title:(NSString *)title
					  message:(int64_t)messageId
{
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] titleForChatId:chatId completion:^(NSString *name){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!name.length && !title.length){
			[me showAlertTitle:@""
					   message:@"The original chat is not available."];
			return;
		}
		[me openChatId:chatId
				 title:(name.length ? name : title)
			   isGroup:YES
		   focusMessage:messageId];
	}];
}

/// Question, the "N voted" line, one row per option, and the stamp.
- (CGFloat)pollHeightFor:(NSDictionary *)m {
	NSString *question = m[@"pollQuestion"] ?: @"Poll";
	CGSize qs = [question sizeWithFont:[UIFont boldSystemFontOfSize:15]
					 constrainedToSize:CGSizeMake([self bubbleWidthBudget] - 2 * kPadH, 200)
						 lineBreakMode:NSLineBreakByWordWrapping];
	NSArray *options = m[@"pollOptions"];
	CGFloat retract = [self pollCanRetractFor:m] ? 24 : 0;
	return kPadV + qs.height + 22 + kPollRow * options.count + retract + 18;
}

/// You have voted and the poll is still open, so the vote can be taken back -
/// which is the one poll action every client offers.
- (BOOL)pollCanRetractFor:(NSDictionary *)m {
	if ([m[@"pollClosed"] boolValue])
		return NO;
	for (NSDictionary *option in m[@"pollOptions"])
		if ([option[@"is_chosen"] boolValue])
			return YES;
	return NO;
}

- (NSString *)pollSubtitleFor:(NSDictionary *)m {
	BOOL closed = [m[@"pollClosed"] boolValue];
	NSInteger total = [m[@"pollTotal"] integerValue];
	NSString *count = total == 0
			? (closed ? @"No votes" : @"No votes yet")
			: [NSString stringWithFormat:@"%ld voted", (long)total];
	if (closed)
		return [NSString stringWithFormat:@"Final results  ·  %@", count];
	NSString *kind = [m[@"pollAnonymous"] boolValue] ? @"Anonymous Poll" : @"Public Poll";
	return [NSString stringWithFormat:@"%@  ·  %@", kind, count];
}

- (void)pollRetractTapped:(UIButton *)button {
	UIView *view = button;
	while (view && ![view isKindOfClass:TGBubbleCell.class])
		view = view.superview;
	TGBubbleCell *cell = (TGBubbleCell *)view;
	if (!cell || !cell.pollMessageId)
		return;

	[[TGClient shared] votePoll:cell.pollMessageId inChat:self.chatId options:@[]];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [self reload]; });
}

/// A picture with no caption carries its own stamp on a plate, so the bubble
/// does not need a strip of empty space under it for one.
- (BOOL)stampSitsOnPictureFor:(NSDictionary *)m {
	return [self imageSizeFor:m].height > 0 && [self bodySizeFor:m].height == 0 &&
		   ![m[@"kind"] isEqualToString:@"messageVideoNote"] &&
		   ![m[@"kind"] isEqualToString:@"messageSticker"] &&
		   ![m[@"kind"] isEqualToString:@"messageAnimatedEmoji"];
}

static BOOL TGIsEmojiPiece(NSString *piece) {
	if (!piece.length)
		return NO;
	unichar high = [piece characterAtIndex:0];
	UTF32Char code = high;
	if (high >= 0xD800 && high <= 0xDBFF && piece.length > 1){
		unichar low = [piece characterAtIndex:1];
		code = ((high - 0xD800) * 0x400) + (low - 0xDC00) + 0x10000;
	}
	if (code >= 0x1F000 && code <= 0x1FAFF) return YES;
	if (code >= 0x2600  && code <= 0x27BF)  return YES;
	if (code >= 0x2B00  && code <= 0x2BFF)  return YES;
	if (code >= 0x2190  && code <= 0x21FF)  return YES;
	if (code >= 0xFE00  && code <= 0xFE0F)  return YES;
	if (code == 0x200D || code == 0x203C || code == 0x2049) return YES;
	if (code == 0x00A9 || code == 0x00AE)   return YES;
	if (code >= 0x2122 && code <= 0x2199)   return YES;
	return NO;
}

- (NSInteger)largeEmojiCountFor:(NSDictionary *)m {
	if (![m[@"kind"] isEqualToString:@"messageText"])
		return 0;
	if ([m[@"service"] boolValue])
		return 0;
	NSString *text = [([self textOf:m] ?: @"")
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length || text.length > kLargeEmojiTextLimit)
		return 0;

	__block NSInteger count = 0;
	__block BOOL onlyEmoji = YES;
	[text enumerateSubstringsInRange:NSMakeRange(0, text.length)
							 options:NSStringEnumerationByComposedCharacterSequences
						  usingBlock:^(NSString *piece, NSRange range,
									   NSRange enclosing, BOOL *stop){
		if (!TGIsEmojiPiece(piece)){
			onlyEmoji = NO;
			*stop = YES;
			return;
		}
		count++;
	}];
	if (!onlyEmoji || count == 0)
		return 0;

	if ([self quoteTextFor:m] || [m[@"forward"] length])
		return 0;
	if ([self previewSizeFor:m].height > 0)
		return 0;
	return count;
}

static CGFloat TGLargeEmojiFontSize(NSInteger count) {
	static const CGFloat multipliers[] = {
		1.0f, 0.84f, 0.69f, 0.53f, 0.46f, 0.38f, 0.32f, 0.27f, 0.24f
	};
	const NSInteger known = (NSInteger)(sizeof(multipliers) / sizeof(multipliers[0]));
	CGFloat multiplier = (count >= 1 && count <= known)
			? multipliers[count - 1] : 0.21f;
	return floorf(94.0f * multiplier);
}

- (UIFont *)bodyFontFor:(NSDictionary *)m {
	NSInteger emoji = [self largeEmojiCountFor:m];
	if (emoji > 0)
		return [UIFont systemFontOfSize:TGLargeEmojiFontSize(emoji)];
	return [UIFont systemFontOfSize:TGMessageBaseFontSize()];
}

- (NSString *)bubbleTextFor:(NSDictionary *)m {
	if ([self messageIsSticker:m])
		return nil;
	return [self textOf:m];
}

- (CGSize)bodySizeFor:(NSDictionary *)m {
	NSString *text = [self bubbleTextFor:m] ?: @"";
	if (!text.length)
		return CGSizeZero;
	CGFloat maxW = [self maxBubbleWidthFor:m] - 2 * kPadH;
	return TGEmojiTextSize(text, [self bodyFontFor:m], CGSizeMake(maxW, 10000),
						   NSLineBreakByWordWrapping, 0);
}

- (UIImage *)imageFor:(NSDictionary *)m {
	if ([self messageCarriesMapCard:m])
		return [self mapCardFor:m];
	NSNumber *fileId = [self pictureFileIdFor:m];
	return fileId ? self.images[fileId] : nil;
}

- (NSString *)pictureKindOf:(NSDictionary *)m {
	return [m[@"kind"] isKindOfClass:NSString.class] ? m[@"kind"] : @"";
}

- (NSNumber *)pictureFileIdFor:(NSDictionary *)m {
	NSNumber *fileId = m[@"photoId"];
	if (![fileId isKindOfClass:NSNumber.class] || [fileId integerValue] == 0)
		return nil;

	NSArray *sizes = m[@"photoSizes"];
	if (![sizes isKindOfClass:NSArray.class] || sizes.count < 2)
		return fileId;

	CGSize tile = [self tileSizeForMessage:m];
	if (tile.width < 1 || tile.height < 1)
		return fileId;

	CGFloat screen = [UIScreen mainScreen].scale;
	CGFloat needW = tile.width * screen;
	CGFloat needH = tile.height * screen;
	for (NSDictionary *size in sizes){
		if ([size[@"w"] floatValue] >= needW && [size[@"h"] floatValue] >= needH)
			return size[@"id"];
	}
	return fileId;
}

- (BOOL)messageCarriesPicture:(NSDictionary *)m {
	if (![self pictureFileIdFor:m])
		return NO;
	NSString *kind = [self pictureKindOf:m];
	return [kind isEqualToString:@"messagePhoto"] ||
		   [kind isEqualToString:@"messageVideo"] ||
		   [kind isEqualToString:@"messageAnimation"] ||
		   [kind isEqualToString:@"messageVideoNote"] ||
		   [kind isEqualToString:@"messageSticker"] ||
		   [kind isEqualToString:@"messageAnimatedEmoji"];
}

- (CGSize)declaredPixelSizeFor:(NSDictionary *)m {
	NSNumber *w = m[@"photoWidth"];
	NSNumber *h = m[@"photoHeight"];
	if (![w isKindOfClass:NSNumber.class] || ![h isKindOfClass:NSNumber.class])
		return CGSizeZero;
	if ([w floatValue] < 1 || [h floatValue] < 1)
		return CGSizeZero;
	return CGSizeMake([w floatValue], [h floatValue]);
}

- (NSString *)mediaBadgeTextFor:(NSDictionary *)m {
	NSString *kind = m[@"kind"];
	if ([kind isEqualToString:@"messageAnimation"])
		return @"GIF";
	if (![kind isEqualToString:@"messageVideo"])
		return nil;
	NSInteger seconds = [m[@"duration"] integerValue];
	if (seconds < 1)
		return nil;
	return [NSString stringWithFormat:@"%ld:%02ld",
			(long)(seconds / 60), (long)(seconds % 60)];
}

- (BOOL)messageIsSticker:(NSDictionary *)m {
	NSString *kind = [self pictureKindOf:m];
	return [kind isEqualToString:@"messageSticker"] ||
		   [kind isEqualToString:@"messageAnimatedEmoji"];
}

static CGSize TGStickerFittedSize(CGSize source, BOOL animated) {
	CGFloat side = animated ? 180.0f : 184.0f;
	if (source.width < 1 || source.height < 1)
		return CGSizeMake(side, side);
	CGFloat scale = MIN(side / source.width, side / source.height);
	return CGSizeMake(floorf(source.width * scale),
					  floorf(source.height * scale));
}

- (CGSize)reservedPictureSizeFor:(NSDictionary *)m {
	NSString *kind = [self pictureKindOf:m];
	if ([kind isEqualToString:@"messageVideoNote"])
		return CGSizeMake(178, 178);
	if ([self messageIsSticker:m])
		return TGStickerFittedSize(CGSizeZero, NO);
	return TGDrawnSizeForImageSize(CGSizeMake(800, 600));
}

- (CGSize)imageSizeFor:(NSDictionary *)m {
	if ([self messageCarriesMapCard:m])
		return TGDrawnSizeForImageSize(CGSizeMake(kMapCardW, kMapCardH));

	CGSize declared = [self declaredPixelSizeFor:m];
	if ([self messageIsSticker:m]){
		if (declared.width < 1 || declared.height < 1)
			declared = [self imageFor:m].size;
		return TGStickerFittedSize(declared, NO);
	}
	if (declared.width >= 1 && declared.height >= 1)
		return TGDrawnSizeForImageSize(declared);

	UIImage *img = [self imageFor:m];
	if (img)
		return TGDrawnSizeForImageSize(img.size);
	if ([self messageCarriesPicture:m])
		return [self reservedPictureSizeFor:m];
	return CGSizeZero;
}

- (UIImage *)minithumbnailImageFor:(NSDictionary *)m {
	NSNumber *key = [m[@"id"] isKindOfClass:NSNumber.class] ? m[@"id"] : nil;
	if (!key)
		return nil;
	id cached = self.minithumbnails[key];
	return [cached isKindOfClass:[UIImage class]] ? cached : nil;
}

- (void)warmMinithumbnailsFor:(NSArray *)messages {
	NSMutableArray *pending = [NSMutableArray array];
	for (NSDictionary *m in messages){
		NSNumber *key = [m[@"id"] isKindOfClass:NSNumber.class] ? m[@"id"] : nil;
		id raw = m[@"minithumbnail"];
		if (!key || !raw || raw == [NSNull null] || self.minithumbnails[key])
			continue;
		self.minithumbnails[key] = [NSNull null];
		[pending addObject:@[key, raw]];
	}
	if (!pending.count)
		return;

	if (pending.count <= 4){
		for (NSArray *entry in pending){
			id raw = entry[1];
			NSData *data = [raw isKindOfClass:NSData.class]
					? raw : [[TGClient shared] minithumbnailData:raw];
			UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
			if (image)
				self.minithumbnails[entry[0]] = image;
		}
		return;
	}

	__weak typeof(self) weakSelf = self;
	dispatch_async(TGImageDecodeQueue(), ^{
		NSMutableDictionary *decoded = [NSMutableDictionary dictionary];
		@autoreleasepool {
			for (NSArray *entry in pending){
				id raw = entry[1];
				NSData *data = [raw isKindOfClass:NSData.class]
						? raw : [[TGClient shared] minithumbnailData:raw];
				UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
				if (image)
					decoded[entry[0]] = image;
			}
		}
		if (!decoded.count)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			[me.minithumbnails addEntriesFromDictionary:decoded];
			[me setNeedsTableReload];
		});
	});
}

- (BOOL)pictureFailedFor:(NSDictionary *)m {
	NSNumber *fileId = [self pictureFileIdFor:m];
	return fileId && [self.photoFilesFailed containsObject:fileId];
}

- (UIImage *)retryGlyphOfSide:(CGFloat)side {
	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [NSMutableDictionary dictionary];
	NSNumber *key = @(side);
	UIImage *cached = cache[key];
	if (cached)
		return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0.0f);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0 alpha:0.45f].CGColor);
	CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, side, side));
	CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
	CGContextSetLineWidth(ctx, 2.0f);
	CGFloat inset = side * 0.28f;
	CGRect arc = CGRectMake(inset, inset, side - 2 * inset, side - 2 * inset);
	CGContextAddArc(ctx, CGRectGetMidX(arc), CGRectGetMidY(arc),
					arc.size.width / 2, (CGFloat)(-M_PI_2), (CGFloat)(M_PI), 0);
	CGContextStrokePath(ctx);
	CGFloat tip = CGRectGetMidX(arc);
	CGFloat top = CGRectGetMinY(arc);
	CGContextMoveToPoint(ctx, tip - 4, top);
	CGContextAddLineToPoint(ctx, tip + 4, top);
	CGContextAddLineToPoint(ctx, tip, top + 5);
	CGContextClosePath(ctx);
	CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
	CGContextFillPath(ctx);
	UIImage *glyph = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (glyph)
		cache[key] = glyph;
	return glyph;
}

- (UIColor *)picturePlaceholderColour {
	return [UIColor colorWithWhite:0 alpha:0.10f];
}

- (UIImage *)picture:(UIImage *)image forMessage:(NSDictionary *)m
			  atSize:(CGSize)points {
	if (!image || points.width < 1 || points.height < 1)
		return image;

	CGFloat screen = [UIScreen mainScreen].scale;
	CGFloat sourceW = image.size.width * image.scale;
	CGFloat sourceH = image.size.height * image.scale;
	if (sourceW < 1 || sourceH < 1)
		return image;

	CGFloat cover = MAX(points.width * screen / sourceW,
						points.height * screen / sourceH);
	if (cover >= 1.0f)
		return image;
	CGSize target = CGSizeMake(MAX(1.0f, floorf(sourceW * cover / screen)),
							   MAX(1.0f, floorf(sourceH * cover / screen)));

	NSNumber *fileId = [self pictureFileIdFor:m];
	if (!fileId)
		return TGImageDrawnAtPointSize(image, target);

	NSString *key = [NSString stringWithFormat:@"%@@%dx%d", fileId,
			(int)roundf(points.width), (int)roundf(points.height)];
	UIImage *cached = self.tileBitmaps[key];
	if (cached)
		return cached;

	if (![self.tileBitmapsRequested containsObject:key]){
		[self.tileBitmapsRequested addObject:key];
		__weak typeof(self) weakSelf = self;
		dispatch_async(TGImageDecodeQueue(), ^{
			UIImage *drawn = nil;
			@autoreleasepool {
				drawn = TGImageDrawnAtPointSize(image, target);
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				TGChatViewController *me = weakSelf;
				if (!me)
					return;
				[me.tileBitmapsRequested removeObject:key];
				if (!drawn)
					return;
				if (me.tileBitmaps.count > 80){
					[me.tileBitmaps removeAllObjects];
					[me.tileBitmapsRequested removeAllObjects];
				}
				me.tileBitmaps[key] = drawn;
			});
		});
	}
	return image;
}

- (void)applyPictureTo:(UIImageView *)view message:(NSDictionary *)m {
	[self applyPictureTo:view message:m atSize:CGSizeZero];
}

- (void)applyPictureTo:(UIImageView *)view
			   message:(NSDictionary *)m
				atSize:(CGSize)points {
	UIImage *shown = [self imageFor:m];
	if (shown && points.width >= 1 && points.height >= 1)
		shown = [self picture:shown forMessage:m atSize:points];
	if (!shown)
		shown = [self minithumbnailImageFor:m];
	view.image = shown;
	view.backgroundColor = shown ? [UIColor clearColor] : [self picturePlaceholderColour];
}

- (long)dayOrdinalForMessage:(NSDictionary *)m {
	time_t stamp = (time_t)[m[@"date"] doubleValue];
	struct tm parts;
	localtime_r(&stamp, &parts);
	return (long)parts.tm_year * 512 + parts.tm_yday;
}

- (NSString *)dayStringForMessage:(NSDictionary *)m {
	static NSDateFormatter *thisYear = nil;
	static NSDateFormatter *otherYear = nil;
	if (!thisYear){
		thisYear  = [[NSDateFormatter alloc] init];
		otherYear = [[NSDateFormatter alloc] init];
		NSString *shortFormat = nil, *longFormat = nil;
		if ([NSDateFormatter respondsToSelector:@selector(dateFormatFromTemplate:options:locale:)]){
			shortFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMd" options:0
														   locale:[NSLocale currentLocale]];
			longFormat  = [NSDateFormatter dateFormatFromTemplate:@"MMMdyyyy" options:0
														   locale:[NSLocale currentLocale]];
		}
		[thisYear  setDateFormat:shortFormat.length ? shortFormat : @"MMM d"];
		[otherYear setDateFormat:longFormat.length  ? longFormat  : @"MMM d, yyyy"];
	}

	time_t now = time(NULL);
	struct tm nowParts;
	localtime_r(&now, &nowParts);
	time_t stamp = (time_t)[m[@"date"] doubleValue];
	struct tm parts;
	localtime_r(&stamp, &parts);

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]];
	if (parts.tm_year != nowParts.tm_year)
		return [otherYear stringFromDate:date];
	if (parts.tm_yday == nowParts.tm_yday)
		return @"Today";
	return [thisYear stringFromDate:date];
}

- (BOOL)rowOpensNewDay:(NSInteger)row {
	NSDictionary *m = [self messageAtRow:row];
	if (!m || ![m[@"date"] doubleValue])
		return NO;
	if (row == 0)
		return YES;
	NSDictionary *prev = [self messageAtRow:row - 1];
	if (![prev[@"date"] doubleValue])
		return NO;
	return [self dayOrdinalForMessage:prev] != [self dayOrdinalForMessage:m];
}

- (NSInteger)unreadDividerRow {
	if (self.chatSearchBar || self.unreadOnOpen <= 0)
		return NSNotFound;
	if (self.messages && self.cachedUnreadKey == self.messages)
		return self.cachedUnreadRow;
	NSInteger remaining = self.unreadOnOpen;
	NSInteger row = NSNotFound;
	for (NSInteger i = [self displayRowCount] - 1; i >= 0; i--){
		NSDictionary *m = [self messageAtRow:i];
		if ([m[@"outgoing"] boolValue] || [m[@"service"] boolValue])
			continue;
		row = i;
		remaining -= (NSInteger)[self messagesAtRow:i].count;
		if (remaining <= 0)
			break;
	}
	if (row == NSNotFound || row == 0)
		row = NSNotFound;
	self.cachedUnreadKey = self.messages;
	self.cachedUnreadRow = row;
	return row;
}

- (CGFloat)headerHeightForRow:(NSInteger)row {
	CGFloat h = 0;
	if ([self rowOpensNewDay:row])
		h += kDayRowHeight;
	if (row == [self unreadDividerRow])
		h += kUnreadRowHeight;
	return h;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return [self headerHeightForRow:indexPath.row] +
			[self messageHeightForRowAtIndexPath:indexPath];
}

- (CGFloat)messageHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *m = [self messageAtRow:indexPath.row];
	if (!m)
		return 0;

	if ([self albumAtRow:indexPath.row])
		return [self albumRowHeight:indexPath.row];

	CGSize body = [self bodySizeFor:m];
	CGSize pic  = [self imageSizeForRow:indexPath.row];
	// A forwarded anything carries a line saying where it came from.
	CGFloat forwarded = [m[@"forward"] length] ? 18 : 0;

	if ([m[@"kind"] isEqualToString:@"messageVideoNote"] && pic.height > 0)
		return MIN(MIN(pic.width, pic.height), 178) + 17 +
				[self bareReactionsHeightFor:m];

	if ([m[@"docName"] isEqualToString:@"tgs"] && self.lottiePaths[m[@"docId"]])
		return 145 + [self bareReactionsHeightFor:m];

	if ([m[@"service"] boolValue]){
		CGFloat full = self.table ? self.table.bounds.size.width
								  : self.view.bounds.size.width;
		return kDayRowHeight + [self serviceOverflowFor:m inWidth:full];
	}

	// Their media block is 80dp tall; a voice message needs only the disc and
	// the bars, which comes to 54 on this screen.
	if ([m[@"kind"] isEqualToString:@"messageVoiceNote"])
		return 59 + forwarded + [self reactionsBlockHeightFor:m];

	if ([m[@"kind"] isEqualToString:@"messagePoll"])
		return [self pollHeightFor:m] + 3;

	if ([m[@"kind"] isEqualToString:@"messageCall"])
		return 47 + forwarded;

	if ([m[@"kind"] isEqualToString:@"messageDocument"] ||
		[m[@"kind"] isEqualToString:@"messageContact"])
		return kFileTile + 2 * kPadV + 3 + forwarded;

	CGFloat senderH = (self.isGroup && ![m[@"outgoing"] boolValue] &&
					   [[TGClient shared] nameForUserId:
							[m[@"senderId"] longLongValue]]) ? 17 : 0;
	CGFloat topPad = (pic.height > 0 && senderH < 0.5f &&
					  [self headDecorationHeightFor:m] < 0.5f) ? kPadH : kPadV;
	CGFloat bottomPad = (pic.height > 0 && body.height < 0.5f &&
						 [self footDecorationHeightFor:m] < 0.5f) ? kPadH : kPadV;
	CGFloat h = bottomPad + topPad + [self decorationHeightFor:m] + senderH;
	if (pic.height > 0) h += pic.height + [self gapUnderMediaFor:m];
	if (body.height > 0) h += body.height;
	h = MAX(h, kBubbleMinH);
	return h + 3;
}

- (NSDictionary *)albumCaptionMessageAtRow:(NSInteger)row {
	for (NSDictionary *member in [self albumAtRow:row])
		if ([[self textOf:member] length])
			return member;
	return nil;
}

- (CGFloat)albumInsetForRow:(NSInteger)row {
	(void)row;
	return kPadH;
}

- (CGFloat)albumRowHeight:(NSInteger)row {
	CGFloat mosaic = [self mosaicHeightForRow:row];
	if (mosaic < 1)
		return 0;

	NSDictionary *head = [self messageAtRow:row];
	NSDictionary *caption = [self albumCaptionMessageAtRow:row];
	CGSize body = caption ? [self bodySizeFor:caption] : CGSizeZero;
	CGFloat inset = [self albumInsetForRow:row];

	CGFloat senderH = (self.isGroup && ![head[@"outgoing"] boolValue] &&
					   [[TGClient shared] nameForUserId:
							[head[@"senderId"] longLongValue]]) ? 17 : 0;
	CGFloat topPad = (senderH < 0.5f &&
					  [self headDecorationHeightFor:head] < 0.5f) ? kPadH : kPadV;
	CGFloat bottomPad = (body.height < 0.5f &&
						 [self footDecorationHeightFor:head] < 0.5f) ? kPadH : kPadV;
	CGFloat h = bottomPad + topPad + [self decorationHeightFor:head] + mosaic +
			(body.height > 0 ? 4 : 0) + senderH;
	if ([head[@"forward"] length])
		h += 2;
	h += body.height;
	return MAX(h, kBubbleMinH) + 3;
}

/// Clients colour each participant's name; the same person keeps the same
/// colour because it is derived from their id.
static UIColor *TGMessageDateColour(void) {
	static UIColor *colour = nil;
	if (!colour)
		colour = [UIColor colorWithRed:0x23 / 255.0f
								 green:0x2d / 255.0f
								  blue:0x37 / 255.0f alpha:1.0f];
	return colour;
}

static UIColor *TGSenderColour(int64_t userId) {
	static NSArray *palette = nil;
	if (!palette){
		static const NSUInteger hexes[8] = {
			0xee4928, 0x41a903, 0xe09602, 0x0f94ed,
			0x8f3bf7, 0xfc4380, 0x00a1c4, 0xeb7002
		};
		NSMutableArray *built = [NSMutableArray arrayWithCapacity:8];
		for (NSUInteger i = 0; i < 8; i++){
			NSUInteger hex = hexes[i];
			[built addObject:[UIColor colorWithRed:((hex >> 16) & 0xff) / 255.0f
											 green:((hex >> 8) & 0xff) / 255.0f
											  blue:(hex & 0xff) / 255.0f
											 alpha:1.0f]];
		}
		palette = built;
	}
	return palette[(NSUInteger)llabs(userId) % palette.count];
}

/// Their conversation cell never put the stamp inside the bubble: the date
/// label, its translucent plate and the delivery marks live on the cell beside
/// the bubble - to its right when the message came in, to its left when it
/// went out.
- (void)placeDateBesideBubbleFor:(TGBubbleCell *)cell
						 message:(NSDictionary *)m
						outgoing:(BOOL)mine
					  tableWidth:(CGFloat)tableWidth
{
	[self placeDateBesideBox:cell.bubble.frame inCell:cell message:m
					outgoing:mine tableWidth:tableWidth];
}

- (void)placeDateBesideBox:(CGRect)box
					inCell:(TGBubbleCell *)cell
				   message:(NSDictionary *)m
				  outgoing:(BOOL)mine
				tableWidth:(CGFloat)tableWidth
{
	if (![cell.time.text length]){
		cell.dateBadge.hidden = YES;
		cell.time.hidden = YES;
		return;
	}

	cell.time.hidden = NO;
	CGFloat dateW = ceilf([cell.time.text sizeWithFont:cell.time.font].width) + 1;
	CGFloat dateX = mine ? (CGRectGetMinX(box) - 26 - kRetinaPixel - dateW)
						 : (CGRectGetMaxX(box) + 12);
	CGFloat dateY = CGRectGetMaxY(box) - 22;

	CGRect badge = mine
			? CGRectMake(dateX - 5, dateY - 3 - kRetinaPixel, dateW + 29, 21)
			: CGRectMake(dateX - 10, dateY - 3 - kRetinaPixel, dateW + 16, 21);

	CGFloat over = CGRectGetMaxX(badge) - (tableWidth - 2);
	if (over > 0){ badge.origin.x -= over; dateX -= over; }
	if (badge.origin.x < 2){ CGFloat back = 2 - badge.origin.x;
		badge.origin.x += back; dateX += back; }

	cell.dateBadge.hidden = NO;
	cell.dateBadge.frame = badge;
	cell.time.textAlignment = NSTextAlignmentLeft;
	cell.time.textColor = TGMessageDateColour();
	cell.time.frame = CGRectMake(dateX, dateY, dateW, 14);

	if (mine){
		cell.ticks.hidden = NO;
		cell.ticks.image = [self statusGlyphForMessage:m white:NO];
		cell.ticks.frame = CGRectMake(dateX + dateW + 4,
									  CGRectGetMidY(badge) - 5, 15, 9);
	} else {
		cell.ticks.hidden = YES;
	}

	[cell.contentView bringSubviewToFront:cell.dateBadge];
	[cell.contentView bringSubviewToFront:cell.time];
	[cell.contentView bringSubviewToFront:cell.ticks];
}

#pragma mark - table

/// The 2014 client never drew a bubble: it stretched Msg_In.png / Msg_Out.png,
/// tail and shading included, with caps 20/15 incoming and 15/15 outgoing, and
/// a body padding of 15+1 on the tail side against 9+1 on the other. So the
/// artwork sits behind the content box and hangs 6pt past it on the tail side.
- (BOOL)applyBubbleArtworkTo:(TGBubbleCell *)cell outgoing:(BOOL)mine {
	NSString *name = mine ? @"Msg_Out" : @"Msg_In";
	if (self.drawingSelectedRow)
		name = [name stringByAppendingString:@"_Selected"];
	UIImage *art = [UIImage imageNamed:name];
	if (!art && self.drawingSelectedRow)
		art = [UIImage imageNamed:(mine ? @"Msg_Out" : @"Msg_In")];
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
	return [self displayRowCount];
}

- (UIFont *)serviceFont {
	return [UIFont boldSystemFontOfSize:13];
}

- (NSString *)serviceLineFor:(NSDictionary *)m {
	NSString *who = [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
	NSString *botLine = [[TGClient shared] botServiceTextForMessage:m];
	NSString *body = botLine.length ? botLine : ([self textOf:m] ?: @"");
	BOOL alreadyNamed = botLine.length || [m[@"serviceNamesAuthor"] boolValue];
	return (who.length && !alreadyNamed)
			? [NSString stringWithFormat:@"%@ %@", who, body]
			: body;
}

- (CGSize)serviceTextSizeFor:(NSDictionary *)m inWidth:(CGFloat)full {
	NSString *line = [self serviceLineFor:m];
	if (!line.length)
		return CGSizeZero;
	CGFloat limit = MAX(full - 60, 60);
	return TGEmojiTextSize(line, [self serviceFont], CGSizeMake(limit, 10000),
						   NSLineBreakByWordWrapping, 0);
}

- (CGFloat)serviceOverflowFor:(NSDictionary *)m inWidth:(CGFloat)full {
	CGFloat oneLine = [self serviceFont].lineHeight;
	if (oneLine < 1)
		return 0;
	CGFloat textH = [self serviceTextSizeFor:m inWidth:full].height;
	NSInteger lines = (NSInteger)floorf(textH / oneLine + 0.5f);
	return lines > 1 ? ceilf((lines - 1) * oneLine) : 0;
}

- (void)configureServiceCell:(TGBubbleCell *)cell
					 message:(NSDictionary *)m
					 inTable:(UITableView *)tableView {
	TGTheme *serviceTheme = [TGTheme shared];
	NSString *line = [self serviceLineFor:m];

	// Their service message is a plate the width of its own text, centred -
	// not a bar across the chat. It sits over the wallpaper, so it is a
	// wash with white text rather than grey on grey.
	CGFloat full = tableView.bounds.size.width;
	CGSize text = [self serviceTextSizeFor:m inWidth:full];
	CGFloat plateW = MIN(text.width, full - 60) + 20;
	CGFloat grown = [self serviceOverflowFor:m inWidth:full];
	CGFloat plateH = kSystemPlateHeight + grown;

	cell.bubble.frame = CGRectMake(floorf((full - plateW) / 2),
								   floorf((kDayRowHeight - kSystemPlateHeight) / 2),
								   plateW, plateH);
	cell.bubble.backgroundColor = TGSystemPlateColour();
	cell.bubble.layer.borderWidth = 0;
	cell.bubble.layer.cornerRadius = kSystemPlateHeight / 2;
	cell.picture.hidden = YES;
	cell.time.text = @"";
	cell.body.hidden = NO;
	cell.body.numberOfLines = 0;
	cell.body.font = [self serviceFont];
	cell.body.textAlignment = NSTextAlignmentCenter;
	cell.body.textColor = [serviceTheme serviceTextColour];
	cell.body.text = line;
	cell.body.frame = CGRectMake(0, 1, plateW, plateH - 2);
}

- (void)configurePollCell:(TGBubbleCell *)cell
				  message:(NSDictionary *)m
				  inTable:(UITableView *)tableView {
	BOOL mine = [m[@"outgoing"] boolValue];
	TGTheme *pollTheme = [TGTheme shared];
	NSArray *options = m[@"pollOptions"];
	NSString *question = m[@"pollQuestion"] ?: @"Poll";
	BOOL closed = [m[@"pollClosed"] boolValue];

	CGFloat width = [self bubbleWidthBudget];
	CGFloat x = mine ? (tableView.bounds.size.width - width - 8) : 8;
	CGFloat height = [self pollHeightFor:m];
	cell.bubble.frame = CGRectMake(x, 0, width, height);
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
	cell.subtitle.text = [self pollSubtitleFor:m];
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
		id optionText = option[@"text"];
		if ([optionText isKindOfClass:NSDictionary.class])
			optionText = optionText[@"text"];
		label.text = [optionText isKindOfClass:NSString.class] ? optionText : @"";
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

	if ([self pollCanRetractFor:m]){
		UIButton *retract = [UIButton buttonWithType:UIButtonTypeCustom];
		retract.frame = CGRectMake(kPadH, y, width - 2 * kPadH, 22);
		retract.tag = 0x91F0;
		retract.titleLabel.font = [UIFont systemFontOfSize:14];
		[retract setTitle:@"Retract Vote" forState:UIControlStateNormal];
		[retract setTitleColor:[pollTheme accentColour] forState:UIControlStateNormal];
		[retract addTarget:self action:@selector(pollRetractTapped:)
		  forControlEvents:UIControlEventTouchUpInside];
		[cell.bubble addSubview:retract];
	}

	cell.picture.hidden = YES;
	cell.disc.hidden = YES;
	cell.time.text = [self stampFor:m];
	[self placeDateBesideBubbleFor:cell message:m outgoing:mine
						tableWidth:tableView.bounds.size.width];
}

- (void)configureCallCell:(TGBubbleCell *)cell
				  message:(NSDictionary *)m
				  inTable:(UITableView *)tableView {
	BOOL mine = [m[@"outgoing"] boolValue];
	TGTheme *callTheme = [TGTheme shared];
	BOOL missed = [m[@"callState"] isEqualToString:@"missed"];
	NSString *line = [self textOf:m] ?: @"Call";

	CGFloat width = MIN([self bubbleWidthBudget],
			[line sizeWithFont:[UIFont systemFontOfSize:15]].width + 76);
	CGFloat fwd = [self layoutForwardIn:cell message:m atY:kPadV width:width];
	CGFloat height = 44 + fwd;
	CGFloat x = mine ? (tableView.bounds.size.width - width - 8) : 8;
	cell.bubble.frame = CGRectMake(x, 0, width, height);
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
}

- (void)configureFileCell:(TGBubbleCell *)cell
				  message:(NSDictionary *)m
				  inTable:(UITableView *)tableView {
	BOOL mine = [m[@"outgoing"] boolValue];
	NSString *kind = m[@"kind"];
	BOOL isDoc = [kind isEqualToString:@"messageDocument"];
	NSArray *lines = [([self textOf:m] ?: @"") componentsSeparatedByString:@"\n"];
	NSString *first = lines.count ? lines[0] : @"";
	NSString *second = lines.count > 1 ? lines[1] : @"";

	TGTheme *cardTheme = [TGTheme shared];
	// Their file block is 253x87 at 360dp: an 80dp tile on the left, the
	// name and the size stacked beside it.
	CGFloat width = 225;
	CGFloat fwd = [self layoutForwardIn:cell message:m atY:kPadV width:width];
	CGFloat height = kFileTile + 2 * kPadV + fwd;
	CGFloat x = mine ? (tableView.bounds.size.width - width - 8) : 8;
	cell.bubble.frame = CGRectMake(x, 0, width, height);
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
	[self placeDateBesideBubbleFor:cell message:m outgoing:mine
						tableWidth:tableView.bounds.size.width];
	cell.picture.hidden = YES;
}

- (void)configureAnimatedStickerCell:(TGBubbleCell *)cell
							 message:(NSDictionary *)m
								path:(NSString *)tgsPath
							 inTable:(UITableView *)tableView {
	BOOL mine = [m[@"outgoing"] boolValue];
	CGFloat side = 128;
	CGFloat chipsBlock = [self bareReactionsHeightFor:m];
	CGFloat boxW = MAX(side, chipsBlock > 0 ? [self chipsRowWidthFor:m] : 0);
	CGFloat boxX = mine ? (tableView.bounds.size.width - boxW - 8) : 8;
	CGFloat artX = mine ? (boxW - side) : 0;

	cell.bubbleBg.hidden = YES;
	cell.bubble.backgroundColor = [UIColor clearColor];
	cell.bubble.layer.borderWidth = 0;
	cell.bubble.frame = CGRectMake(boxX, 0, boxW, side + 14 + chipsBlock);
	cell.picture.hidden = YES;
	cell.body.hidden = YES;
	cell.lottie.hidden = NO;
	cell.lottie.frame = CGRectMake(artX, 0, side, side);
	[cell.lottie loadTGSFile:tgsPath];
	[cell.lottie play];

	[self layoutReactionsIn:cell message:m atY:side + kBareChipsTopGap
				bubbleWidth:boxW inset:0 rightAligned:mine];

	static NSDateFormatter *hmt = nil;
	if (!hmt){ hmt = [[NSDateFormatter alloc] init]; [hmt setDateFormat:@"HH:mm"]; }
	cell.time.text = [hmt stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
	[self placeDateBesideBox:CGRectMake(boxX + artX, 0, side, side + 14)
					  inCell:cell message:m outgoing:mine
				  tableWidth:tableView.bounds.size.width];
}

- (void)configureVideoNoteCell:(TGBubbleCell *)cell
					   message:(NSDictionary *)m
				   pictureSize:(CGSize)pic
					   inTable:(UITableView *)tableView {
	BOOL mine = [m[@"outgoing"] boolValue];
	// Their video note is 200dp across; taking the thumbnail's own size
	// filled almost the whole width of a 320pt screen.
	CGFloat side = MIN(MIN(pic.width, pic.height), 178);
	CGFloat chipsBlock = [self bareReactionsHeightFor:m];
	CGFloat boxW = MAX(side, chipsBlock > 0 ? [self chipsRowWidthFor:m] : 0);
	CGFloat boxH = side + 14 + chipsBlock;
	CGFloat boxX = mine ? (tableView.bounds.size.width - boxW - 8) : 8;
	CGFloat circleX = mine ? (boxW - side) : 0;

	cell.bubbleBg.hidden = YES;
	cell.bubble.backgroundColor = [UIColor clearColor];
	cell.bubble.layer.borderWidth = 0;
	cell.bubble.frame = CGRectMake(boxX, 0, boxW, boxH);
	cell.picture.hidden = NO;
	[self applyPictureTo:cell.picture message:m];
	cell.picture.frame = CGRectMake(circleX, 0, side, side);
	cell.picture.layer.cornerRadius = side / 2;
	cell.body.hidden = YES;

	[self layoutReactionsIn:cell message:m atY:side + kBareChipsTopGap
				bubbleWidth:boxW inset:0 rightAligned:mine];

	static NSDateFormatter *hmr = nil;
	if (!hmr){ hmr = [[NSDateFormatter alloc] init]; [hmr setDateFormat:@"HH:mm"]; }
	cell.time.text = [hmr stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
	[self placeDateBesideBox:CGRectMake(boxX + circleX, 0, side, side + 14)
					  inCell:cell message:m outgoing:mine
				  tableWidth:tableView.bounds.size.width];
}

static const NSInteger kQuoteTapTag = 0x9009;

- (CGFloat)layoutQuoteIn:(TGBubbleCell *)cell
				 message:(NSDictionary *)m
					 atY:(CGFloat)y
			 bubbleWidth:(CGFloat)bubbleW {
	TGTheme *theme = [TGTheme shared];
	NSString *quoted = [self quoteTextFor:m];
	UILabel *quoteAuthor = (UILabel *)[cell.bubble viewWithTag:0x9003];
	UIImageView *quoteThumb = (UIImageView *)[cell.bubble viewWithTag:0x9008];
	if (quoted){
		// A 2pt stripe the height of the block, then the author's name and the
		// line being answered - which is how their reply reads at a glance.
		cell.quoteBar.hidden = NO;
		cell.quoteBar.backgroundColor = [theme accentColour];
		cell.quoteBar.frame = CGRectMake(kPadH, y, 2, 34);

		if (!quoteAuthor){
			quoteAuthor = [[TGEmojiLabel alloc] init];
			quoteAuthor.tag = 0x9003;
			quoteAuthor.backgroundColor = [UIColor clearColor];
			[cell.bubble addSubview:quoteAuthor];
		}
		// A reply to a picture shows the picture, small and rounded, the way
		// every client draws it - the words alone lose what was answered.
		UIImage *thumb = [self quoteThumbnailFor:m];
		CGFloat textX = kPadH + 8;
		if (thumb){
			if (!quoteThumb){
				quoteThumb = [[UIImageView alloc] initWithFrame:CGRectZero];
				quoteThumb.tag = 0x9008;
				quoteThumb.contentMode = UIViewContentModeScaleAspectFill;
				quoteThumb.clipsToBounds = YES;
				quoteThumb.layer.cornerRadius = 3;
				[cell.bubble addSubview:quoteThumb];
			}
			quoteThumb.hidden = NO;
			quoteThumb.image = thumb;
			quoteThumb.frame = CGRectMake(kPadH + 7, y + 1, 32, 32);
			textX = kPadH + 45;
		} else {
			quoteThumb.hidden = YES;
		}

		CGFloat quoteW = MAX(bubbleW - textX - kPadH, 40);
		quoteAuthor.hidden = NO;
		quoteAuthor.font = [UIFont boldSystemFontOfSize:13];
		quoteAuthor.textColor = [theme accentColour];
		quoteAuthor.text = [self quoteAuthorFor:m] ?: @"Reply";
		quoteAuthor.frame = CGRectMake(textX, y, quoteW, 16);

		// The forwarded line has a label of its own now, so the quote can use
		// this one rather than a second one built at runtime.
		cell.quote.hidden = NO;
		cell.quote.numberOfLines = 1;
		cell.quote.font = [UIFont systemFontOfSize:13];
		cell.quote.textColor = [theme primaryTextColour];
		cell.quote.text = [self quoteDisplayTextFor:m];
		cell.quote.frame = CGRectMake(textX, y + 17, quoteW, 17);
		[self placeQuoteTapTargetIn:cell
							  frame:CGRectMake(kPadH, y, bubbleW - 2 * kPadH, 38)];
		y += 38;
	} else {
		cell.quoteBar.hidden = YES;
		cell.quote.hidden = YES;
		quoteAuthor.hidden = YES;
		quoteThumb.hidden = YES;
		[cell.bubble viewWithTag:kQuoteTapTag].hidden = YES;
	}
	return y;
}

- (void)alignBodyNaturallyIn:(TGBubbleCell *)cell
						text:(NSString *)text
						left:(CGFloat)left
				  innerWidth:(CGFloat)innerW {
	if (!TGTextIsRightToLeft(text)){
		cell.body.textAlignment = NSTextAlignmentLeft;
		return;
	}
	cell.body.textAlignment = NSTextAlignmentRight;
	CGRect box = cell.body.frame;
	box.origin.x = left;
	box.size.width = MAX(innerW, box.size.width);
	cell.body.frame = box;
}

- (void)placeQuoteTapTargetIn:(TGBubbleCell *)cell frame:(CGRect)frame {
	UIView *target = [cell.bubble viewWithTag:kQuoteTapTag];
	if (!target){
		target = [[UIView alloc] initWithFrame:frame];
		target.tag = kQuoteTapTag;
		target.backgroundColor = [UIColor clearColor];
		[target addGestureRecognizer:[[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(quoteHeaderTapped:)]];
		[cell.bubble addSubview:target];
	}
	target.hidden = NO;
	target.userInteractionEnabled = !self.selecting;
	target.frame = frame;
	[cell.bubble bringSubviewToFront:target];
}

- (void)quoteHeaderTapped:(UITapGestureRecognizer *)tap {
	if (tap.state != UIGestureRecognizerStateRecognized || self.selecting)
		return;
	UIView *view = tap.view;
	while (view && ![view isKindOfClass:TGBubbleCell.class])
		view = view.superview;
	NSIndexPath *path = view ? [self.table indexPathForCell:(TGBubbleCell *)view] : nil;
	NSDictionary *m = path ? [self messageAtRow:path.row] : nil;
	NSNumber *replyTo = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	if (!replyTo)
		return;
	if (![self scrollToMessageId:replyTo.longLongValue])
		[self showAlertTitle:@"" message:@"That message is not in the loaded history."];
}

- (void)configureVoiceCell:(TGBubbleCell *)cell
				   message:(NSDictionary *)m
				bubbleSize:(CGSize)bubbleSize
				   inTable:(UITableView *)tableView {
	BOOL mine = [m[@"outgoing"] boolValue];
	CGFloat bubbleW = bubbleSize.width;
	CGFloat chipsBlock = [self reactionsBlockHeightFor:m];
	CGFloat bubbleH = bubbleSize.height - chipsBlock;
	TGTheme *voiceTheme = [TGTheme shared];
	CGFloat disc = 36;
	CGFloat left = kPadH + disc + 8;
	BOOL isPlaying = (self.playingMessageId == [m[@"id"] longLongValue]);

	cell.voiceMessageId = [m[@"id"] longLongValue];
	cell.waveformData = m[@"waveform"];

	CGFloat fwd = [self layoutForwardIn:cell message:m atY:kPadV width:bubbleW];

	cell.disc.hidden = NO;
	cell.disc.image = [TGIcons mediaDiscOfSide:disc
									   playing:(isPlaying && [TGMusicPlayer shared].isPlaying)];
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
	[self layoutReactionsIn:cell message:m atY:bubbleH bubbleWidth:bubbleW];
	cell.time.text = [self stampFor:m];
	CGRect box = cell.bubble.frame;
	box.size.height -= chipsBlock;
	[self placeDateBesideBox:box inCell:cell message:m outgoing:mine
				  tableWidth:tableView.bounds.size.width];
}

- (void)layoutReactionsIn:(TGBubbleCell *)cell
				 message:(NSDictionary *)m
					 atY:(CGFloat)afterBody
			 bubbleWidth:(CGFloat)bubbleW {
	[self layoutReactionsIn:cell message:m atY:afterBody + kChipsRowTopGap
				bubbleWidth:bubbleW inset:kPadH rightAligned:NO];
}

- (CGFloat)layoutSignatureIn:(TGBubbleCell *)cell
					 message:(NSDictionary *)m
						 atY:(CGFloat)afterBody
				 bubbleWidth:(CGFloat)bubbleW {
	UILabel *line = (UILabel *)[cell.bubble viewWithTag:0x900A];
	UIImageView *eye = (UIImageView *)[cell.bubble viewWithTag:0x900B];
	NSString *text = [self signatureLineFor:m];

	if (!text){
		line.hidden = YES;
		eye.hidden = YES;
		return 0;
	}

	if (!line){
		line = [[UILabel alloc] initWithFrame:CGRectZero];
		line.tag = 0x900A;
		line.backgroundColor = [UIColor clearColor];
		line.font = [UIFont systemFontOfSize:11];
		line.numberOfLines = 1;
		line.lineBreakMode = NSLineBreakByTruncatingTail;
		[cell.bubble addSubview:line];
	}
	if (!eye){
		eye = [[UIImageView alloc] initWithFrame:CGRectZero];
		eye.tag = 0x900B;
		[cell.bubble addSubview:eye];
	}

	UIColor *tint = [[TGTheme shared] secondaryTextColour];
	line.hidden = NO;
	line.text = text;
	line.textColor = tint;
	line.textAlignment = NSTextAlignmentRight;

	CGFloat top = afterBody + kSignatureTopGap;
	CGFloat available = MAX(bubbleW - 2 * kPadH, 20);
	CGFloat textW = MIN(ceilf([text sizeWithFont:line.font].width), available);

	BOOL withEye = [self showsViewCountFor:m];
	eye.hidden = !withEye;
	if (withEye){
		textW = MIN(textW, MAX(available - kViewsEyeWidth - kViewsEyeGap, 20));
		eye.image = TGViewsEyeImage(tint);
		eye.frame = CGRectMake(bubbleW - kPadH - textW - kViewsEyeGap - kViewsEyeWidth,
							   top + floorf((kSignatureHeight - 8) / 2),
							   kViewsEyeWidth, 8);
	}

	line.frame = CGRectMake(bubbleW - kPadH - textW, top, textW, kSignatureHeight);
	return kSignatureTopGap + kSignatureHeight;
}

- (void)layoutReactionsIn:(TGBubbleCell *)cell
				 message:(NSDictionary *)m
					 atY:(CGFloat)rowTop
			 bubbleWidth:(CGFloat)bubbleW
				   inset:(CGFloat)inset
			rightAligned:(BOOL)rightAligned {
	TGTheme *theme = [TGTheme shared];
	BOOL mine = [m[@"outgoing"] boolValue];
	UILabel *reactions = (UILabel *)[cell.bubble viewWithTag:0x9002];
	TGReactionChipsView *chipsView = (TGReactionChipsView *)[cell.bubble viewWithTag:0x9005];
	NSString *reactionText = m[@"reactions"];
	NSArray *chips = [self chipsFor:m];
	int64_t rowMessageId = [m[@"id"] isKindOfClass:NSNumber.class]
			? [m[@"id"] longLongValue] : 0;

	if (chips.count && rowMessageId){
		reactions.hidden = YES;
		if (!chipsView){
			chipsView = [[TGReactionChipsView alloc] initWithFrame:CGRectZero];
			chipsView.tag = 0x9005;
			[chipsView addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
					initWithTarget:self action:@selector(chipsHeld:)]];
			[cell.bubble addSubview:chipsView];
		}
		chipsView.hidden = NO;
		chipsView.outgoing = mine;
		chipsView.chatId = self.chatId;
		chipsView.messageId = rowMessageId;
		chipsView.chips = chips;
		CGFloat chipsW = [self chipsRowWidthFor:m];
		chipsW = MIN(chipsW, MAX(bubbleW - 2 * inset,
								 [TGReactionChipsView rowHeight] * 2));
		CGFloat chipsH = [TGReactionChipsView heightForChips:chips width:chipsW];
		chipsView.frame = CGRectMake(
				rightAligned ? (bubbleW - inset - chipsW) : inset,
				rowTop, chipsW, chipsH);
		__weak typeof(self) weakSelf = self;
		chipsView.onChipTapped = ^(NSString *emoji, BOOL wasChosen){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			[me.reactionChipsRequested removeObject:@(rowMessageId)];
			[me.chipsRowWidths removeObjectForKey:@(rowMessageId)];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
					dispatch_get_main_queue(), ^{ [me reload]; });
		};
	} else if ([reactionText length]){
		chipsView.hidden = YES;
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
		CGFloat textW = MAX(bubbleW - 2 * inset, 40);
		reactions.frame = CGRectMake(inset, rowTop, textW,
									 [TGReactionChipsView rowHeight]);
		reactions.textAlignment = rightAligned ? NSTextAlignmentRight
											   : NSTextAlignmentLeft;
	} else {
		reactions.hidden = YES;
		chipsView.hidden = YES;
	}
}

- (void)configureRowChromeIn:(TGBubbleCell *)cell
					 message:(NSDictionary *)m
				  atIndexPath:(NSIndexPath *)indexPath {
	BOOL opensDay = [self rowOpensNewDay:indexPath.row];
	NSInteger dividerRow = [self unreadDividerRow];
	CGFloat headerH = [self headerHeightForRow:indexPath.row];
	cell.headerHeight = headerH;

	[cell.bubble viewWithTag:0x900A].hidden = YES;
	[cell.bubble viewWithTag:0x900B].hidden = YES;

	cell.dayPlate.hidden = !opensDay;
	cell.dayLabel.hidden = !opensDay;
	if (opensDay)
		cell.dayLabel.text = [self dayStringForMessage:m];

	BOOL divides = (indexPath.row == dividerRow);
	cell.unreadStrip.hidden = !divides;
	cell.unreadLabel.hidden = !divides;
	cell.unreadArrow.hidden = !divides;
	if (divides)
		cell.unreadLabel.text = [NSString stringWithFormat:@"%d unread message%@",
				(int)self.unreadOnOpen, self.unreadOnOpen == 1 ? @"" : @"s"];
	[cell setNeedsLayout];

	BOOL picked = self.selecting && [m[@"id"] isKindOfClass:NSNumber.class] &&
			[self.selectedIds containsObject:m[@"id"]];
	self.drawingSelectedRow = picked || (indexPath.row == self.pressedRow);
	cell.checkView.hidden = !self.selecting || [m[@"service"] boolValue];
	if (!cell.checkView.hidden){
		cell.checkView.image = [self selectionGlyphChecked:picked];
		cell.checkView.frame = CGRectMake(2,
				headerH + ([self messageHeightForRowAtIndexPath:indexPath] - 26) / 2,
				26, 26);
		[cell bringSubviewToFront:cell.checkView];
	}
}

- (TGMosaicTileView *)albumTile:(NSUInteger)index inCell:(TGBubbleCell *)cell {
	while (cell.albumTiles.count <= index){
		TGMosaicTileView *made = [[TGMosaicTileView alloc] initWithFrame:CGRectZero];
		made.tileIndex = (NSInteger)cell.albumTiles.count;
		[made addGestureRecognizer:[[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(albumTileTapped:)]];
		[cell.album addSubview:made];
		[cell.albumTiles addObject:made];
	}
	return cell.albumTiles[index];
}

- (void)configureAlbumCell:(TGBubbleCell *)cell
			   atIndexPath:(NSIndexPath *)indexPath
				   inTable:(UITableView *)tableView {
	NSDictionary *head = [self messageAtRow:indexPath.row];
	NSDictionary *mosaic = [self mosaicForRow:indexPath.row];
	NSArray *album = [self messagesAtRow:indexPath.row];
	if (!head || !mosaic)
		return;

	NSArray *frames = mosaic[@"frames"];
	CGSize groupSize = [mosaic[@"size"] CGSizeValue];
	BOOL mine = [head[@"outgoing"] boolValue];
	TGTheme *theme = [TGTheme shared];

	NSDictionary *caption = [self albumCaptionMessageAtRow:indexPath.row];
	CGSize body = caption ? [self bodySizeFor:caption] : CGSizeZero;

	int64_t senderId = [head[@"senderId"] longLongValue];
	NSString *senderName = (self.isGroup && !mine)
			? [[TGClient shared] nameForUserId:senderId] : nil;

	cell.picture.hidden = YES;
	cell.picture.image = nil;
	cell.picture.backgroundColor = [UIColor clearColor];
	cell.disc.hidden = YES;
	cell.wave.hidden = YES;
	cell.icon.hidden = YES;
	cell.subtitle.hidden = YES;
	cell.lottie.hidden = YES;
	[cell.lottie stop];
	[cell.bubble viewWithTag:0x9006].hidden = YES;
	cell.album.hidden = NO;
	cell.album.clipsToBounds = YES;

	CGFloat senderH = senderName.length ? 17 : 0;
	CGFloat albumContentW = MAX(groupSize.width, body.width);
	if ([[self chipsFor:head] count])
		albumContentW = MAX(albumContentW, [self chipsRowWidthFor:head]);
	albumContentW = MAX(albumContentW, [self signatureWidthFor:head]);
	CGFloat inset = [self albumInsetForRow:indexPath.row];
	CGFloat bubbleW = albumContentW + 2 * inset;
	CGFloat x = mine ? (tableView.bounds.size.width - bubbleW - 8) : 8;
	CGFloat avatarX = x - kBubbleTailOverhang + 4;
	if (senderName.length)
		x += kAvatarSide + 4;
	CGFloat top = 0;
	CGFloat bubbleH = [self albumRowHeight:indexPath.row] - 3;

	cell.bubble.frame = CGRectMake(x, top, bubbleW, bubbleH);

	UIColor *fill = mine ? [theme bubbleMineColour] : [theme bubbleTheirsColour];
	cell.bubble.backgroundColor = fill;
	cell.bubble.layer.borderWidth = [theme bubbleBorderWidth];
	cell.bubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
	cell.bubble.layer.cornerRadius = [theme bubbleCornerRadius];
	cell.tail.hidden = NO;
	cell.tail.image = [TGIcons bubbleTailForColour:fill outgoing:mine];
	cell.tail.frame = mine
			? CGRectMake(x + bubbleW - 1, top + bubbleH - 10, 6, 10)
			: CGRectMake(x - 5, top + bubbleH - 10, 6, 10);
	[self applyBubbleArtworkTo:cell outgoing:mine];

	CGFloat topPad = (senderH < 0.5f &&
					  [self headDecorationHeightFor:head] < 0.5f) ? kPadH : kPadV;

	cell.sender.hidden = !senderName.length;
	if (senderName.length){
		cell.sender.text = senderName;
		cell.sender.textColor = TGSenderColour(senderId);
		cell.sender.frame = CGRectMake(kPadH, topPad,
									   bubbleW - 2 * kPadH, senderH - 1);
	}

	CGFloat y = topPad + senderH;
	CGFloat forwardHeight = [self layoutForwardIn:cell message:head atY:y width:bubbleW];
	y += forwardHeight;
	if (forwardHeight > 0.5f)
		y += 2;
	y = [self layoutQuoteIn:cell message:head atY:y bubbleWidth:bubbleW];
	cell.album.frame = CGRectMake(inset, y, groupSize.width, groupSize.height);
	CGFloat innerRadius = [theme bubbleCornerRadius] - inset;
	cell.album.layer.cornerRadius = MAX(kMediaRadius, innerRadius);

	for (NSUInteger i = 0; i < album.count && i < frames.count; i++){
		NSDictionary *member = album[i];
		CGRect tileFrame = [frames[i] CGRectValue];
		TGMosaicTileView *tile = [self albumTile:i inCell:cell];
		tile.hidden = NO;
		tile.frame = tileFrame;
		[self applyPictureTo:tile message:member atSize:tileFrame.size];

		BOOL failed = [self pictureFailedFor:member] && ![self imageFor:member];
		BOOL playable = [member[@"kind"] isEqualToString:@"messageVideo"] ||
						[member[@"kind"] isEqualToString:@"messageAnimation"];
		tile.disc.hidden = !playable && !failed;
		if (!tile.disc.hidden){
			CGFloat side = MIN(42.0f, floorf(MIN(tileFrame.size.width,
												 tileFrame.size.height) * 0.5f));
			tile.disc.image = failed ? [self retryGlyphOfSide:side]
									 : [TGIcons mediaDiscOfSide:side playing:NO];
			tile.disc.frame = CGRectMake(floorf((tileFrame.size.width - side) / 2),
										 floorf((tileFrame.size.height - side) / 2),
										 side, side);
		}
	}
	for (NSUInteger i = album.count; i < cell.albumTiles.count; i++)
		((UIView *)cell.albumTiles[i]).hidden = YES;

	cell.senderAvatar.hidden = !senderName.length;
	if (!cell.senderAvatar.hidden){
		cell.senderAvatar.image = [self avatarForUser:senderId name:senderName];
		[self attachAvatarTapIn:cell sender:senderId];
		cell.senderAvatar.frame = CGRectMake(avatarX,
											 top + bubbleH - kAvatarSide - 1,
											 kAvatarSide, kAvatarSide);
	}

	cell.ticks.hidden = YES;
	cell.mediaStamp.hidden = YES;
	cell.mediaBadge.hidden = YES;
	CGFloat afterAlbum = CGRectGetMaxY(cell.album.frame) +
			(body.height > 0 ? 4 : 0);
	cell.body.hidden = (body.height == 0);
	if (body.height > 0){
		cell.body.numberOfLines = 0;
		cell.body.textAlignment = NSTextAlignmentLeft;
		cell.body.font = [self bodyFontFor:caption];
		cell.body.textColor = [theme isDark] ? [theme primaryTextColour]
											 : TGMessageBodyColour();
		cell.body.text = [self textOf:caption] ?: @"";
		[self highlightTimestampInLabel:cell.body];
		cell.body.frame = CGRectMake(inset, afterAlbum, body.width, body.height);
		[self alignBodyNaturallyIn:cell text:[self textOf:caption]
							  left:inset innerWidth:bubbleW - 2 * inset];
		afterAlbum += body.height;
	}

	afterAlbum += [self layoutSignatureIn:cell message:head atY:afterAlbum
							  bubbleWidth:bubbleW];

	[self layoutReactionsIn:cell message:head atY:afterAlbum bubbleWidth:bubbleW];
	cell.time.text = [self stampFor:head];
	[self placeDateBesideBubbleFor:cell message:head outgoing:mine
						tableWidth:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGBubbleCell";
	TGBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell){
		cell = [[TGBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
		[self attachReplySwipeTo:cell];
	}

	if (cell != self.swipingCell)
		[self resetReplySwipeOnCell:cell];

	NSDictionary *m = [self messageAtRow:indexPath.row];
	if (!m)
		return cell;
	BOOL mine = [m[@"outgoing"] boolValue];
	NSString *kind = m[@"kind"];

	[self configureRowChromeIn:cell message:m atIndexPath:indexPath];
	cell.album.hidden = YES;

	// Stickers never sit in a bubble - they are drawn straight on the wallpaper.
	BOOL isSticker = [kind isEqualToString:@"messageSticker"] ||
					 [kind isEqualToString:@"messageAnimatedEmoji"] ||
					 [self largeEmojiCountFor:m] > 0;

	cell.icon.hidden = YES;
	cell.bubbleBg.hidden = YES;
	cell.subtitle.hidden = YES;
	cell.sender.hidden = YES;
	cell.senderAvatar.hidden = YES;
	cell.dateBadge.hidden = YES;
	cell.ticks.hidden = YES;
	cell.time.hidden = YES;
	cell.time.text = @"";
	cell.tail.hidden = YES;
	cell.disc.hidden = YES;
	cell.wave.hidden = YES;
	cell.mediaBadge.hidden = YES;
	cell.forwardLabel.hidden = YES;
	cell.forwardJump.hidden = YES;
	[cell.bubble viewWithTag:kQuoteTapTag].hidden = YES;
	[cell.bubble viewWithTag:0x9005].hidden = YES;
	[cell.bubble viewWithTag:0x9002].hidden = YES;

	if ([self albumAtRow:indexPath.row]){
		[self configureAlbumCell:cell atIndexPath:indexPath inTable:tableView];
		return cell;
	}

	// Service messages sit centred on the wallpaper, not in a bubble - joins,
	// renames, pins. Groups are full of them.
	if ([m[@"service"] boolValue]){
		[self configureServiceCell:cell message:m inTable:tableView];
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
		[self configurePollCell:cell message:m inTable:tableView];
		return cell;
	}

	// A call reads as a small bubble with an arrow saying which way it went and
	// whether it was answered. Tapping it calls back.
	if ([kind isEqualToString:@"messageCall"]){
		[self configureCallCell:cell message:m inTable:tableView];
		return cell;
	}

	if ([kind isEqualToString:@"messageDocument"] ||
		[kind isEqualToString:@"messageContact"]){
		[self configureFileCell:cell message:m inTable:tableView];
		return cell;
	}

	// A voice message is a fixed block rather than a run of text: the disc,
	// the bars and the duration, sized the way their media components are.
	BOOL isVoice = [m[@"kind"] isEqualToString:@"messageVoiceNote"];

	CGSize body = [self bodySizeFor:m];
	CGSize pic  = [self imageSizeForRow:indexPath.row];

	// The bubble has to fit whichever is widest: the text, a picture, the
	// quoted message, or the timestamp. Sizing it on the text alone squeezed
	// quotes down to an ellipsis.
	CGFloat contentW = MAX(body.width, pic.width);
	if ([self quoteTextFor:m] || [m[@"forward"] length])
		contentW = MAX(contentW, [self quoteThumbnailFor:m] ? 200 : 170);
	if ([[self chipsFor:m] count])
		contentW = MAX(contentW, [self chipsRowWidthFor:m]);
	CGSize previewSize = [self previewSizeFor:m];
	if (previewSize.height > 0)
		contentW = MAX(contentW, previewSize.width);
	contentW = MAX(contentW, [self signatureWidthFor:m]);

	if (isVoice)
		contentW = MAX(190, [[self chipsFor:m] count] ? [self chipsRowWidthFor:m] : 0);

	// In a group you need to know who is speaking. Their layout puts the name
	// inside the bubble as its first line and hangs the avatar beside it.
	int64_t senderId = [m[@"senderId"] longLongValue];
	NSString *senderName = (self.isGroup && !mine)
			? [[TGClient shared] nameForUserId:senderId] : nil;
	CGFloat senderH = 0;
	CGFloat nameW = 0;
	if (senderName.length){
		senderH = 17;
		nameW = ceilf([senderName sizeWithFont:cell.sender.font].width) + 4;
		contentW = MAX(contentW, nameW);
	}

	CGFloat maxBubbleW = [self maxBubbleWidthFor:m];
	CGFloat bubbleW = MAX(contentW + 2 * kPadH, kBubbleMinW - kBubbleTailOverhang);
	bubbleW = MIN(bubbleW, maxBubbleW);
	BOOL mediaOnly = pic.height > 0 && body.height < 0.5f &&
			[self footDecorationHeightFor:m] < 0.5f;
	CGFloat mediaTopPad = (pic.height > 0 && senderH < 0.5f &&
						   [self headDecorationHeightFor:m] < 0.5f)
			? kPadH : kPadV;
	CGFloat mediaBottomPad = mediaOnly ? kPadH : kPadV;
	CGFloat bubbleH  = senderH + mediaTopPad + mediaBottomPad +
			[self decorationHeightFor:m] +
			(pic.height ? pic.height + [self gapUnderMediaFor:m] : 0) + body.height;
	bubbleH = MAX(bubbleH, kBubbleMinH);
	if (isVoice)
		bubbleH = 56 + ([m[@"forward"] length] ? 18 : 0) +
				[self reactionsBlockHeightFor:m];

	CGFloat x = mine ? (tableView.bounds.size.width - bubbleW - 8) : 8;
	CGFloat top = 0;

	CGFloat avatarX = x - kBubbleTailOverhang + 4;
	if (senderName.length){
		// The bubble shifts right to make room for the avatar beside it.
		x += kAvatarSide + 4;
		cell.senderAvatar.hidden = NO;
		cell.senderAvatar.image = [self avatarForUser:senderId name:senderName];
		[self attachAvatarTapIn:cell sender:senderId];

		cell.sender.hidden = NO;
		cell.sender.text = senderName;
		cell.sender.textColor = TGSenderColour(senderId);
		cell.sender.frame = CGRectMake(kPadH, mediaTopPad,
									   bubbleW - 2 * kPadH, senderH - 1);
	}

	cell.bubble.frame = CGRectMake(x, top, bubbleW, bubbleH);

	if (!cell.senderAvatar.hidden)
		cell.senderAvatar.frame = CGRectMake(avatarX,
											 top + bubbleH - kAvatarSide - 1,
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
	BOOL bareMedia = [self stampSitsOnPictureFor:m] &&
			[self decorationHeightFor:m] < 0.5f;
	if (!isSticker && ![self applyBubbleArtworkTo:cell outgoing:mine] && bareMedia){
		cell.bubble.backgroundColor = [UIColor clearColor];
		cell.bubble.layer.borderWidth = 0.0f;
		cell.bubble.layer.cornerRadius = 0.0f;
		cell.tail.hidden = YES;
	}
	cell.body.textColor = [theme isDark] ? [theme primaryTextColour]
										 : TGMessageBodyColour();

	// A video note is a circle, with no bubble around it - that is how every
	// client draws them.
	BOOL isRound = [m[@"kind"] isEqualToString:@"messageVideoNote"];
	if (isRound && pic.height > 0){
		[self configureVideoNoteCell:cell message:m pictureSize:pic inTable:tableView];
		return cell;
	}

	// An animated sticker plays in place of the still image.
	NSString *tgsPath = [m[@"docName"] isEqualToString:@"tgs"]
			? self.lottiePaths[m[@"docId"]] : nil;
	if (tgsPath){
		[self configureAnimatedStickerCell:cell message:m path:tgsPath inTable:tableView];
		return cell;
	}
	CGFloat y = mediaTopPad + senderH;

	// "Forwarded from X", then the quote block, then the message itself.
	cell.quoteBar.hidden = YES;
	cell.quote.hidden = YES;

	y += [self layoutForwardIn:cell message:m atY:y width:bubbleW];

	y = [self layoutQuoteIn:cell message:m atY:y bubbleWidth:bubbleW];

	cell.mediaStamp.hidden = YES;
	cell.mediaBadge.hidden = YES;
	if (pic.height > 0){
		cell.picture.hidden = NO;
		[self applyPictureTo:cell.picture message:m];
		cell.picture.frame = CGRectMake(kPadH, y, pic.width, pic.height);
		cell.picture.layer.cornerRadius = kMediaRadius;

		// A video says so with a play button in the middle of the frame.
		BOOL failedPicture = [self pictureFailedFor:m] && ![self imageFor:m];
		BOOL playable = [kind isEqualToString:@"messageVideo"] ||
						[kind isEqualToString:@"messageAnimation"];
		cell.disc.hidden = !playable && !failedPicture;
		if (!cell.disc.hidden){
			CGFloat disc = 42;
			cell.disc.image = failedPicture ? [self retryGlyphOfSide:disc]
											: [TGIcons mediaDiscOfSide:disc playing:NO];
			cell.disc.frame = CGRectMake(kPadH + (pic.width - disc) / 2,
										 y + (pic.height - disc) / 2, disc, disc);
		}

		NSString *badge = [self mediaBadgeTextFor:m];
		if (badge.length){
			CGFloat badgeW = ceilf([badge sizeWithFont:cell.mediaBadge.font].width) + 12;
			cell.mediaBadge.hidden = NO;
			cell.mediaBadge.backgroundColor = [theme mediaStampColour];
			cell.mediaBadge.text = badge;
			cell.mediaBadge.frame = CGRectMake(kPadH + 6, y + 6, badgeW, 16);
			[cell.bubble bringSubviewToFront:cell.mediaBadge];
		}

		if (!body.height && !bareMedia && !isSticker){
			NSString *stamp = [self stampFor:m];
			CGFloat plateW = [stamp sizeWithFont:cell.mediaStamp.font].width +
					(mine ? 30 : 14);
			cell.mediaStamp.hidden = NO;
			cell.mediaStamp.backgroundColor = [theme mediaStampColour];
			cell.mediaStamp.text = stamp;
			cell.mediaStamp.frame = CGRectMake(
					kPadH + pic.width - plateW - 6, y + pic.height - 22, plateW, 16);
		}
		y += pic.height + [self gapUnderMediaFor:m];
	} else {
		cell.picture.hidden = YES;
		cell.picture.image = nil;
		cell.picture.backgroundColor = [UIColor clearColor];
	}

	if (isVoice){
		[self configureVoiceCell:cell message:m
					 bubbleSize:CGSizeMake(bubbleW, bubbleH) inTable:tableView];
		return cell;
	}

	cell.body.hidden = (body.height == 0);
	cell.body.numberOfLines = 0;
	cell.body.font = [self bodyFontFor:m];
	cell.body.text = [self bubbleTextFor:m] ?: @"";
	[self highlightTimestampInLabel:cell.body];
	cell.body.frame = CGRectMake(kPadH, y, body.width, body.height);
	[self alignBodyNaturallyIn:cell text:[self bubbleTextFor:m]
						  left:kPadH innerWidth:bubbleW - 2 * kPadH];

	CGFloat afterBody = y + body.height;
	TGLinkPreviewView *previewView = (TGLinkPreviewView *)[cell.bubble viewWithTag:0x9006];
	NSDictionary *preview = [self previewFor:m];
	if (preview && previewSize.height > 0){
		if (!previewView){
			previewView = [[TGLinkPreviewView alloc] initWithFrame:CGRectZero];
			previewView.tag = 0x9006;
			[cell.bubble addSubview:previewView];
		}
		previewView.hidden = NO;
		CGFloat previewW = bubbleW - 2 * kPadH;
		[previewView configureWithPreview:preview
									image:[self previewImageFor:preview]
								 outgoing:mine
								 maxWidth:previewW];
		previewView.frame = CGRectMake(kPadH, afterBody + 6, previewW, previewSize.height);

		__weak typeof(self) weakSelf = self;
		previewView.onOpen = ^(NSString *url){ [weakSelf openLink:url]; };
		previewView.onInstantView = ^(NSString *url){ [weakSelf openInstantView:url]; };
		afterBody += previewSize.height + 6;
	} else {
		previewView.hidden = YES;
	}

	afterBody += [self layoutSignatureIn:cell message:m atY:afterBody
							 bubbleWidth:bubbleW];

	[self layoutReactionsIn:cell message:m atY:afterBody + kChipsRowTopGap
				bubbleWidth:bubbleW inset:kPadH rightAligned:(isSticker && mine)];

	// A stamp already on the picture must not be repeated under it.
	BOOL onPicture = !cell.mediaStamp.hidden;
	cell.time.text = onPicture ? @"" : [self stampFor:m];
	CGRect stampBox = cell.bubble.frame;
	if (isSticker)
		stampBox.size.height -= [self reactionsBlockHeightFor:m];
	[self placeDateBesideBox:stampBox inCell:cell message:m outgoing:mine
				  tableWidth:tableView.bounds.size.width];

	if (mine && onPicture){
		// The stamp on a picture keeps its own plate inside the bubble, so its
		// ticks stay there too - white, because green vanishes into the plate.
		cell.ticks.hidden = NO;
		cell.ticks.image = [self statusGlyphForMessage:m white:YES];
		cell.ticks.frame = CGRectMake(
				x + CGRectGetMaxX(cell.mediaStamp.frame) - 20,
				top + CGRectGetMidY(cell.mediaStamp.frame) - 4, 15, 9);
	}

	return cell;
}

#pragma mark - drafts

- (void)restoreDraft {
	if (self.draftRestored)
		return;
	self.draftRestored = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] draftForChat:self.chatId
						 completion:^(NSString *text, int64_t replyToId){
		TGChatViewController *me = weakSelf;
		if (!me || !text.length || me.input.text.length)
			return;
		me.input.text = text;
		[me inputChanged];
		if (replyToId != 0){
			me.replyToId = replyToId;
			[me showComposeBanner:@"Reply to message"];
		}
	}];
}

- (void)flushDraftOnAppState:(NSNotification *)note {
	[self saveDraft];
}

- (void)saveDraft {
	if (self.editingId != 0)
		return;
	NSString *text = self.input.text ?: @"";
	[[TGClient shared] setDraftText:text
							replyTo:self.replyToId
							 inChat:self.chatId
							 thread:self.threadId];
}

#pragma mark - send options

- (void)sendHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan || self.postingBlocked)
		return;
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Send options"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:nil];
	[sheet addButtonWithTitle:(self.sendSilently ? @"Send With Sound"
												 : @"Send Without Sound")];
	[sheet addButtonWithTitle:(self.protectContent ? @"Allow Forwarding"
												   : @"Protect Content")];
	[sheet addButtonWithTitle:@"Text Tools"];
	BOOL reminders = [self isRemindersChat];
	[sheet addButtonWithTitle:(reminders ? @"Set a Reminder" : @"Schedule Message")];
	if (self.scheduledMessages.count)
		[sheet addButtonWithTitle:(reminders ? @"Reminders" : @"Scheduled Messages")];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kSendOptionsSheetTag;
	[sheet showInView:self.view];
}

- (void)runSendOption:(NSString *)title {
	if ([title isEqualToString:@"Send Without Sound"] ||
		[title isEqualToString:@"Send With Sound"]){
		self.sendSilently = !self.sendSilently;
		[TGSnackbar showInView:self.view
						  text:(self.sendSilently ? @"Messages will be sent silently"
												  : @"Messages will make a sound")
					   seconds:3 onCommit:nil];
		return;
	}
	if ([title isEqualToString:@"Protect Content"] ||
		[title isEqualToString:@"Allow Forwarding"]){
		self.protectContent = !self.protectContent;
		[TGSnackbar showInView:self.view
						  text:(self.protectContent
								? @"New messages cannot be forwarded or saved"
								: @"New messages can be forwarded")
					   seconds:3 onCommit:nil];
		return;
	}
	if ([title isEqualToString:@"Text Tools"]){
		[self showTextTools];
		return;
	}
	if ([title isEqualToString:@"Schedule Message"] ||
		[title isEqualToString:@"Set a Reminder"]){
		UIActionSheet *sheet = [[UIActionSheet alloc]
				initWithTitle:([self isRemindersChat] ? @"Remind me" : @"Send later")
					 delegate:self
			cancelButtonTitle:nil
	   destructiveButtonTitle:nil
			otherButtonTitles:@"In 1 Hour",
							  @"In 8 Hours",
							  @"Tomorrow Morning", nil];
		if (!self.isGroup && ![self isRemindersChat])
			[sheet addButtonWithTitle:@"When Online"];
		[sheet addButtonWithTitle:@"Choose Date"];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = kScheduleSheetTag;
		[sheet showInView:self.view];
		return;
	}
	if ([title isEqualToString:@"Scheduled Messages"] ||
		[title isEqualToString:@"Reminders"])
		[self showScheduledMessages];
}

- (BOOL)isRemindersChat {
	return (self.chatId == [[TGClient shared] savedMessagesChatId]);
}

- (void)showSchedulePicker {
	if (self.datePickerPanel)
		return;

	CGRect b = self.view.bounds;
	CGFloat panelHeight = 260;
	UIView *panel = [[UIView alloc] initWithFrame:
			CGRectMake(0, b.size.height, b.size.width, panelHeight)];
	panel.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
	panel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
							 UIViewAutoresizingFlexibleTopMargin;

	UIToolbar *bar = [[UIToolbar alloc] initWithFrame:
			CGRectMake(0, 0, b.size.width, 44)];
	bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	UIBarButtonItem *cancel = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
								 target:self
								 action:@selector(dismissSchedulePicker)];
	UIBarButtonItem *space = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
								 target:nil action:nil];
	UIBarButtonItem *done = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemDone
								 target:self
								 action:@selector(commitSchedulePicker)];
	bar.items = @[cancel, space, done];
	[panel addSubview:bar];

	UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:
			CGRectMake(0, 44, b.size.width, panelHeight - 44)];
	picker.datePickerMode = UIDatePickerModeDateAndTime;
	picker.minuteInterval = 5;
	picker.minimumDate = [NSDate dateWithTimeIntervalSinceNow:60];
	picker.date = [NSDate dateWithTimeIntervalSinceNow:3600];
	picker.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[panel addSubview:picker];

	self.schedulePicker = picker;
	self.datePickerPanel = panel;

	[self.input resignFirstResponder];
	[self.view addSubview:panel];
	[UIView animateWithDuration:0.25 animations:^{
		panel.frame = CGRectMake(0, b.size.height - panelHeight,
								 b.size.width, panelHeight);
	}];
}

- (void)dismissSchedulePicker {
	UIView *panel = self.datePickerPanel;
	self.reschedulingMessageId = 0;
	if (!panel)
		return;
	self.datePickerPanel = nil;
	self.schedulePicker = nil;
	CGRect gone = panel.frame;
	gone.origin.y = self.view.bounds.size.height;
	[UIView animateWithDuration:0.25 animations:^{
		panel.frame = gone;
	} completion:^(BOOL finished){
		[panel removeFromSuperview];
	}];
}

- (void)commitSchedulePicker {
	NSDate *when = self.schedulePicker.date;
	int64_t moving = self.reschedulingMessageId;
	[self dismissSchedulePicker];
	if (!when)
		return;
	NSTimeInterval stamp = [when timeIntervalSince1970];
	if (stamp <= [[NSDate date] timeIntervalSince1970])
		return;
	if (moving){
		self.reschedulingMessageId = moving;
		[self rescheduleTo:stamp];
		return;
	}
	self.scheduleWhenOnline = NO;
	self.scheduledSendDate = stamp;
	[self showComposeBanner:[NSString stringWithFormat:
			([self isRemindersChat] ? @"Reminder for %@" : @"Scheduled for %@"),
			[NSDateFormatter localizedStringFromDate:when
										   dateStyle:NSDateFormatterShortStyle
										   timeStyle:NSDateFormatterShortStyle]]];
	[self.input becomeFirstResponder];
}

- (void)runScheduleOption:(NSString *)title {
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	self.scheduleWhenOnline = NO;
	self.scheduledSendDate = 0;

	if ([title isEqualToString:@"In 1 Hour"]){
		self.scheduledSendDate = now + 3600;
	} else if ([title isEqualToString:@"In 8 Hours"]){
		self.scheduledSendDate = now + 8 * 3600;
	} else if ([title isEqualToString:@"Tomorrow Morning"]){
		NSCalendar *calendar = [NSCalendar currentCalendar];
		NSDateComponents *parts = [calendar components:
				(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit)
											  fromDate:[NSDate dateWithTimeIntervalSinceNow:86400]];
		parts.hour = 9;
		parts.minute = 0;
		self.scheduledSendDate = [[calendar dateFromComponents:parts] timeIntervalSince1970];
	} else if ([title isEqualToString:@"When Online"]){
		self.scheduleWhenOnline = YES;
	} else if ([title isEqualToString:@"Choose Date"]){
		[self showSchedulePicker];
		return;
	} else {
		return;
	}

	[self showComposeBanner:(self.scheduleWhenOnline
			? @"Will be sent when online"
			: [NSString stringWithFormat:
					([self isRemindersChat] ? @"Reminder for %@" : @"Scheduled for %@"),
					[NSDateFormatter localizedStringFromDate:
							[NSDate dateWithTimeIntervalSince1970:self.scheduledSendDate]
												   dateStyle:NSDateFormatterShortStyle
												   timeStyle:NSDateFormatterShortStyle]])];
	[self.input becomeFirstResponder];
}

- (NSDictionary *)sendOptionsDictionary {
	if (!self.sendSilently && !self.protectContent &&
		self.scheduledSendDate == 0 && !self.scheduleWhenOnline)
		return nil;
	NSMutableDictionary *options = [NSMutableDictionary dictionary];
	if (self.sendSilently)
		options[@"silent"] = @YES;
	if (self.protectContent)
		options[@"protect"] = @YES;
	if (self.scheduledSendDate != 0)
		options[@"sendDate"] = @(self.scheduledSendDate);
	if (self.scheduleWhenOnline)
		options[@"whenOnline"] = @YES;
	return options;
}

- (void)loadScheduledMessages {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] scheduledMessagesInChat:self.chatId
									completion:^(NSArray *messages){
		weakSelf.scheduledMessages = messages ?: @[];
	}];
}

- (void)showScheduledMessages {
	if (!self.scheduledMessages.count){
		[self showAlertTitle:@"" message:@"Nothing is scheduled in this chat."];
		return;
	}
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Scheduled messages"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:nil];
	for (NSDictionary *m in self.scheduledMessages){
		NSString *body = [self textOf:m];
		NSString *kind = [m[@"kind"] isKindOfClass:NSString.class] ? m[@"kind"] : @"message";
		NSTimeInterval when = [m[@"sendDate"] isKindOfClass:NSNumber.class]
				? [m[@"sendDate"] doubleValue] : 0;
		NSString *stamp = (when > 0)
				? [NSDateFormatter localizedStringFromDate:
						[NSDate dateWithTimeIntervalSince1970:when]
										   dateStyle:NSDateFormatterNoStyle
										   timeStyle:NSDateFormatterShortStyle]
				: @"When online";
		[sheet addButtonWithTitle:[NSString stringWithFormat:@"%@  %@", stamp,
				(body.length ? body : kind)]];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kScheduledListSheetTag;
	[sheet showInView:self.view];
}

/// A scheduled message is worth two things, not one: sending it now, and
/// moving it to another moment.
- (void)showScheduledItemOptions:(NSInteger)index {
	self.scheduledItemIndex = index;
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:@"Send Now",
															   @"Reschedule", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kScheduledItemSheetTag;
	[sheet showInView:self.view];
}

- (void)beginReschedulingItem:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.scheduledMessages.count)
		return;
	NSDictionary *m = self.scheduledMessages[index];
	if (![m[@"id"] isKindOfClass:NSNumber.class])
		return;
	self.reschedulingMessageId = [m[@"id"] longLongValue];
	[self showSchedulePicker];
}

- (void)rescheduleTo:(NSTimeInterval)stamp {
	int64_t messageId = self.reschedulingMessageId;
	self.reschedulingMessageId = 0;
	if (!messageId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] rescheduleMessage:messageId
								  inChat:self.chatId
								sendDate:stamp
							  whenOnline:NO
							  completion:^(BOOL ok){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[me showAlertTitle:@"" message:@"This message could not be moved."];
			return;
		}
		[me loadScheduledMessages];
		[TGSnackbar showInView:me.view text:@"Moved to another time" seconds:3 onCommit:nil];
	}];
}

- (void)sendScheduledMessageAtIndex:(NSInteger)index {
	NSDictionary *m = self.scheduledMessages[index];
	if (![m[@"id"] isKindOfClass:NSNumber.class])
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sendScheduledMessageNow:[m[@"id"] longLongValue]
										inChat:self.chatId
									completion:^(BOOL ok){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[me showAlertTitle:@"" message:@"This message could not be sent."];
			return;
		}
		[me loadScheduledMessages];
		[me reload];
	}];
}

#pragma mark - selection

- (void)beginSelectionWithMessage:(int64_t)messageId {
	if (!self.selecting){
		self.selecting = YES;
		self.rightItemBeforeSelection = self.navigationItem.rightBarButtonItem;
		self.titleViewBeforeSelection = self.navigationItem.titleView;
		self.navigationItem.titleView = nil;
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
				initWithTitle:@"Cancel"
						style:UIBarButtonItemStyleBordered
					   target:self
					   action:@selector(endSelection)];
		[self buildSelectionPanel];
	}
	if (messageId != 0 && ![self.selectedIds containsObject:@(messageId)])
		[self.selectedIds addObject:@(messageId)];
	[self updateSelectionChrome];
	[self.table reloadData];
}

- (void)endSelection {
	self.selecting = NO;
	[self.selectedIds removeAllObjects];
	self.navigationItem.rightBarButtonItem = self.rightItemBeforeSelection;
	self.rightItemBeforeSelection = nil;
	UIView *panel = self.selectionPanel;
	self.selectionPanel = nil;
	[UIView animateWithDuration:0.2 delay:0.0
						options:UIViewAnimationOptionBeginFromCurrentState
					 animations:^{ panel.alpha = 0.0f; }
					 completion:^(BOOL finished){ [panel removeFromSuperview]; }];
	self.navigationItem.title = nil;
	if (self.titleViewBeforeSelection){
		self.navigationItem.titleView = self.titleViewBeforeSelection;
		self.titleViewBeforeSelection = nil;
	}
	[self.table reloadData];
}

- (void)toggleSelectionOfRow:(NSInteger)row {
	NSDictionary *m = [self messageAtRow:row];
	if (!m || [m[@"service"] boolValue] || ![m[@"id"] isKindOfClass:NSNumber.class])
		return;
	BOOL picked = [self.selectedIds containsObject:m[@"id"]];
	for (NSDictionary *member in [self messagesAtRow:row]){
		NSNumber *messageId = member[@"id"];
		if (![messageId isKindOfClass:NSNumber.class])
			continue;
		if (picked)
			[self.selectedIds removeObject:messageId];
		else if (![self.selectedIds containsObject:messageId])
			[self.selectedIds addObject:messageId];
	}

	if (!self.selectedIds.count){
		[self endSelection];
		return;
	}
	[self updateSelectionChrome];
	[self.table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
					  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)updateSelectionChrome {
	self.navigationItem.title = self.selecting
			? [NSString stringWithFormat:@"%lu selected",
					(unsigned long)self.selectedIds.count]
			: nil;
}

- (void)buildSelectionPanel {
	CGRect b = self.view.bounds;
	const CGFloat height = kInputHeight;
	UIView *panel = [[UIView alloc] initWithFrame:
			CGRectMake(0, CGRectGetMinY(self.inputBar.frame), b.size.width, height)];
	panel.backgroundColor = [[TGTheme shared] inputBarColour];
	panel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
							 UIViewAutoresizingFlexibleTopMargin;

	UIImage *bar = [UIImage imageNamed:@"ConversationActionBar"];
	if (bar){
		UIImageView *plate = [[UIImageView alloc] initWithFrame:
				CGRectMake(0, 0, b.size.width, height)];
		plate.image = [bar stretchableImageWithLeftCapWidth:0 topCapHeight:0];
		plate.autoresizingMask = UIViewAutoresizingFlexibleWidth |
								 UIViewAutoresizingFlexibleHeight;
		[panel addSubview:plate];
	}

	NSArray *titles = [[TGClient shared] isSecretChat:self.chatId]
			? @[@"More", @"Delete"]
			: @[@"Forward", @"Copy", @"Save", @"More", @"Delete"];
	CGFloat slice = b.size.width / titles.count;
	for (NSUInteger i = 0; i < titles.count; i++){
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = CGRectMake(floorf(slice * i), 0,
								  floorf(slice * (i + 1)) - floorf(slice * i), height);
		button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		button.tag = (NSInteger)i;
		[button setTitle:titles[i] forState:UIControlStateNormal];
		UIColor *ink = [titles[i] isEqualToString:@"Delete"]
				? [UIColor colorWithRed:0.78f green:0.16f blue:0.13f alpha:1.0f]
				: [[TGTheme shared] accentColour];
		[button setTitleColor:ink forState:UIControlStateNormal];
		[button setTitleColor:[ink colorWithAlphaComponent:0.4f]
					 forState:UIControlStateHighlighted];
		[button setTitleColor:[ink colorWithAlphaComponent:0.3f]
					 forState:UIControlStateDisabled];
		[button addTarget:self action:@selector(selectionButtonTapped:)
		 forControlEvents:UIControlEventTouchUpInside];
		[panel addSubview:button];

		if (i > 0){
			UIView *rule = [[UIView alloc] initWithFrame:
					CGRectMake(floorf(slice * i), 7, kRetinaPixel, height - 14)];
			rule.backgroundColor = [[TGTheme shared] separatorColour];
			[panel addSubview:rule];
		}
	}

	panel.alpha = 0.0f;
	[self.view addSubview:panel];
	self.selectionPanel = panel;
	[UIView animateWithDuration:0.2 delay:0.0
						options:UIViewAnimationOptionBeginFromCurrentState
					 animations:^{ panel.alpha = 1.0f; } completion:nil];
}

- (void)selectionButtonTapped:(UIButton *)button {
	if (!self.selectedIds.count)
		return;
	NSString *title = button.currentTitle ?: @"";
	if ([title isEqualToString:@"Forward"])
		[self forwardSelected];
	else if ([title isEqualToString:@"Copy"])
		[self copySelected];
	else if ([title isEqualToString:@"Save"])
		[self saveSelectedToCameraRoll];
	else if ([title isEqualToString:@"More"])
		[self showSelectionMore];
	else
		[self confirmDeleteSelected];
}

/// One message selected opens everything the chat knows about it; several
/// share only the one action that makes sense in bulk.
- (void)showSelectionMore {
	if (self.selectedIds.count == 1){
		[self openInfoForMessageId:[[self.selectedIds firstObject] longLongValue]];
		return;
	}
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:@"Try Again", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kSelectionMoreSheetTag;
	[sheet showInView:self.view];
}

- (void)runSelectionMore:(NSString *)chosen {
	if (![chosen isEqualToString:@"Try Again"] || !self.selectedIds.count)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] resendMessages:[self.selectedIds copy] inChat:self.chatId
						   completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[me endSelection];
		if (!messages.count){
			[me showAlertTitle:@"" message:@"None of these could be sent again."];
			return;
		}
		[me reload];
	}];
}

- (void)openInfoForMessageId:(int64_t)messageId {
	NSDictionary *found = nil;
	for (NSDictionary *m in self.messages){
		if ([m[@"id"] isKindOfClass:NSNumber.class] &&
			[m[@"id"] longLongValue] == messageId){
			found = m;
			break;
		}
	}
	if (!found)
		return;

	TGMessageInfoViewController *info = [[TGMessageInfoViewController alloc] init];
	info.chatId = self.chatId;
	info.messageId = messageId;
	info.message = found;
	info.isGroup = self.isGroup;
	info.canResend = [[self sendStateForMessage:found] isEqualToString:@"failed"];
	__weak typeof(self) weakSelf = self;
	info.onOpenChat = ^(int64_t targetChatId, NSString *title){
		[weakSelf openChatId:targetChatId title:title isGroup:YES];
	};
	[self endSelection];
	[self.navigationController pushViewController:info animated:YES];
}

- (void)forwardSelected {
	NSArray *ids = [self.selectedIds copy];
	int64_t fromChat = self.chatId;
	BOOL silent = self.sendSilently;
	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	__weak typeof(self) weakSelf = self;
	picker.onPicked = ^(int64_t targetChatId){
		[[TGClient shared] forwardMessages:ids
								  fromChat:fromChat
									toChat:targetChatId
									thread:0
									asCopy:NO
							removeCaptions:NO
									silent:silent
								completion:nil];
		[weakSelf endSelection];
	};
	[self.navigationController pushViewController:picker animated:YES];
}

- (void)copySelected {
	NSMutableArray *lines = [NSMutableArray array];
	for (NSDictionary *m in self.messages){
		if (![m[@"id"] isKindOfClass:NSNumber.class] ||
			![self.selectedIds containsObject:m[@"id"]])
			continue;
		NSString *body = [self originalTextOf:m];
		if (body.length)
			[lines addObject:body];
	}
	if (!lines.count){
		[self showAlertTitle:@"" message:@"Nothing here can be copied."];
		return;
	}
	[UIPasteboard generalPasteboard].string = [lines componentsJoinedByString:@"\n"];
	[self endSelection];
}

- (void)saveSelectedToCameraRoll {
	NSMutableArray *wanted = [NSMutableArray array];
	for (NSDictionary *m in self.messages)
		if ([m[@"id"] isKindOfClass:NSNumber.class] &&
			[self.selectedIds containsObject:m[@"id"]])
			[wanted addObject:m];

	NSInteger started = 0;
	for (NSDictionary *m in wanted){
		NSString *kind = [m[@"kind"] isKindOfClass:NSString.class] ? m[@"kind"] : @"";
		if ([kind isEqualToString:@"messagePhoto"]){
			NSNumber *fileId = [m[@"photoId"] isKindOfClass:NSNumber.class]
					? m[@"photoId"] : nil;
			if (!fileId)
				continue;
			started++;
			__weak typeof(self) weakForPhoto = self;
			[[TGClient shared] downloadFile:[fileId integerValue]
								 completion:^(NSString *path){
				if (!path.length)
					return;
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					UIImage *loaded = [UIImage imageWithContentsOfFile:path];
					if (!loaded && [path.pathExtension.lowercaseString isEqualToString:@"webp"])
						loaded = [UIImage convertFromWebP:path compressedData:nil error:nil];
					if (!loaded)
						return;
					dispatch_async(dispatch_get_main_queue(), ^{
						TGChatViewController *me = weakForPhoto;
						if (!me)
							return;
						UIImageWriteToSavedPhotosAlbum(loaded, me,
								@selector(image:didFinishSavingWithError:contextInfo:), NULL);
					});
				});
			}];
			continue;
		}
		if ([kind isEqualToString:@"messageVideo"] ||
			[kind isEqualToString:@"messageVideoNote"]){
			NSNumber *docId = [m[@"docId"] isKindOfClass:NSNumber.class] ? m[@"docId"] : nil;
			if (!docId)
				continue;
			started++;
			__weak typeof(self) weakSelf = self;
			[[TGClient shared] downloadFile:[docId integerValue]
								 completion:^(NSString *path){
				TGChatViewController *me = weakSelf;
				if (!me || !path)
					return;
				if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path)){
					[me showAlertTitle:@"" message:@"This video cannot be saved."];
					return;
				}
				UISaveVideoAtPathToSavedPhotosAlbum(path, me,
						@selector(video:didFinishSavingWithError:contextInfo:), NULL);
			}];
		}
	}

	if (!started){
		[self showAlertTitle:@"" message:@"Nothing here can be saved."];
		return;
	}
	[self endSelection];
}

- (void)video:(NSString *)path didFinishSavingWithError:(NSError *)error
  contextInfo:(void *)contextInfo {
	[self showAlertTitle:@""
				 message:(error ? @"Could not save" : @"Saved to Camera Roll")];
}

- (void)confirmDeleteSelected {
	BOOL secret = [[TGClient shared] isSecretChat:self.chatId];
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:
			[NSString stringWithFormat:@"Delete %lu messages?",
					(unsigned long)self.selectedIds.count]
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:(secret ? @"Delete"
																	   : @"Delete for Everyone")
											 otherButtonTitles:nil];
	if (!secret)
		[sheet addButtonWithTitle:@"Delete for Me"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kSelectionDeleteSheetTag;
	[sheet showInView:self.view];
}

- (void)deleteSelectedForEveryone:(BOOL)forEveryone {
	NSArray *ids = [self.selectedIds copy];
	if (!ids.count)
		return;
	int64_t chatId = self.chatId;

	NSMutableArray *left = [NSMutableArray array];
	for (NSDictionary *m in self.messages)
		if (![m[@"id"] isKindOfClass:NSNumber.class] || ![ids containsObject:m[@"id"]])
			[left addObject:m];
	self.messages = left;
	[self endSelection];
	[self updateEmptyState];

	__weak typeof(self) weakSelf = self;
	[TGSnackbar showInView:self.view
					  text:(forEveryone ? @"Deleted for everyone" : @"Deleted for you")
				   seconds:5
				  onCommit:^{
		[[TGClient shared] deleteMessages:ids inChat:chatId
							  forEveryone:forEveryone completion:nil];
	}];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [weakSelf reload]; });
}

- (UIImage *)selectionGlyphChecked:(BOOL)checked {
	CGSize size = CGSizeMake(26, 26);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGRect ring = CGRectMake(1.5f, 1.5f, size.width - 3, size.height - 3);

	if (checked){
		CGContextSetFillColorWithColor(ctx, [[TGTheme shared] accentColour].CGColor);
		CGContextFillEllipseInRect(ctx, ring);
		CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
		CGContextSetLineWidth(ctx, 2.0f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextMoveToPoint(ctx, 7.5f, 13.5f);
		CGContextAddLineToPoint(ctx, 11.5f, 17.5f);
		CGContextAddLineToPoint(ctx, 18.5f, 9.0f);
		CGContextStrokePath(ctx);
	} else {
		CGContextSetFillColorWithColor(ctx,
				[UIColor colorWithWhite:1.0f alpha:0.85f].CGColor);
		CGContextFillEllipseInRect(ctx, ring);
		CGContextSetStrokeColorWithColor(ctx,
				[UIColor colorWithWhite:0.62f alpha:1.0f].CGColor);
		CGContextSetLineWidth(ctx, 1.0f);
		CGContextStrokeEllipseInRect(ctx, ring);
	}

	UIImage *glyph = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return glyph;
}

#pragma mark - mentions

- (void)loadUnreadMentions {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchMessagesInChat:self.chatId
									  query:@""
							   senderUserId:0
									 filter:@"searchMessagesFilterUnreadMention"
							  fromMessageId:0
									  limit:30
								 completion:^(NSArray *messages, int64_t next, NSInteger total){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *m in messages)
			if ([m[@"id"] isKindOfClass:NSNumber.class])
				[ids addObject:m[@"id"]];
		me.mentionIds = ids;
		[me updateMentionButton];
	}];
}

static UIImage *TGFloatingBadgeDisc(UIColor *fill, UIColor *border) {
	CGSize size = CGSizeMake(kFloatingButtonSide, kFloatingButtonSide);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGRect disc = CGRectInset(CGRectMake(0, 0, size.width, size.height), 0.5f, 0.5f);
	[fill setFill];
	CGContextFillEllipseInRect(ctx, disc);
	[border setStroke];
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextStrokeEllipseInRect(ctx, disc);
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

- (UIButton *)buildFloatingBadgeWithAction:(SEL)action font:(UIFont *)font {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(0, 0, kFloatingButtonSide, kFloatingButtonSide);
	UIColor *border = [[TGTheme shared] separatorColour];
	[button setBackgroundImage:
			TGFloatingBadgeDisc([UIColor colorWithWhite:1.0f alpha:0.9f], border)
					  forState:UIControlStateNormal];
	[button setBackgroundImage:
			TGFloatingBadgeDisc([UIColor colorWithWhite:0.85f alpha:0.95f], border)
					  forState:UIControlStateHighlighted];
	button.adjustsImageWhenHighlighted = NO;
	button.titleLabel.font = font;
	[button setTitleColor:[[TGTheme shared] accentColour] forState:UIControlStateNormal];
	button.layer.shadowColor = [UIColor blackColor].CGColor;
	button.layer.shadowOffset = CGSizeMake(0, 1);
	button.layer.shadowRadius = 1.0f;
	button.layer.shadowOpacity = 0.25f;
	button.hidden = YES;
	button.alpha = 0.0f;
	button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
							  UIViewAutoresizingFlexibleTopMargin;
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:button];
	return button;
}

- (void)updateMentionButton {
	BOOL wanted = (self.mentionIds.count > 0);
	if (!wanted && !self.mentionButton)
		return;
	if (!self.mentionButton)
		self.mentionButton = [self buildFloatingBadgeWithAction:@selector(mentionTapped)
														   font:[UIFont boldSystemFontOfSize:15]];
	if (wanted)
		[self.mentionButton setTitle:[NSString stringWithFormat:@"@%lu",
				(unsigned long)self.mentionIds.count] forState:UIControlStateNormal];
	[self setFloatingButton:self.mentionButton shown:wanted];
	[self layoutFloatingButtons];
}

- (void)mentionTapped {
	NSNumber *next = [self.mentionIds lastObject];
	if (!next){
		[self updateMentionButton];
		return;
	}
	[self.mentionIds removeLastObject];
	[[TGClient shared] markRead:@[next] inChat:self.chatId source:@"history"];
	if (![self scrollToMessageId:next.longLongValue])
		[self showAlertTitle:@"" message:@"That mention is not in the loaded history."];
	if (!self.mentionIds.count)
		[[TGClient shared] readAllMentionsInChat:self.chatId];
	[self updateMentionButton];
}

#pragma mark - unread reactions

- (void)loadUnreadReactions {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] unreadReactionsInChat:self.chatId
							   fromMessageId:0
									   limit:30
								  completion:^(NSArray *messageIds){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		me.reactionMessageIds = [(messageIds ?: @[]) mutableCopy];
		[me updateReactionButton];
	}];
}

- (void)updateReactionButton {
	BOOL wanted = (self.reactionMessageIds.count > 0);
	if (!wanted && !self.reactionButton)
		return;
	if (!self.reactionButton)
		self.reactionButton = [self buildFloatingBadgeWithAction:@selector(reactionBadgeTapped)
															font:[UIFont boldSystemFontOfSize:13]];
	if (wanted)
		[self.reactionButton setTitle:[NSString stringWithFormat:@"♥%lu",
				(unsigned long)self.reactionMessageIds.count] forState:UIControlStateNormal];
	[self setFloatingButton:self.reactionButton shown:wanted];
	[self layoutFloatingButtons];
}

- (void)reactionBadgeTapped {
	NSNumber *next = [self.reactionMessageIds firstObject];
	if (!next){
		[self updateReactionButton];
		return;
	}
	[self.reactionMessageIds removeObjectAtIndex:0];
	if (![self scrollToMessageId:next.longLongValue])
		[self showAlertTitle:@"" message:@"That reaction is not in the loaded history."];
	if (!self.reactionMessageIds.count)
		[[TGClient shared] markReactionsReadInChat:self.chatId];
	[self updateReactionButton];
}

- (void)openReactionDetailForMessage:(int64_t)messageId {
	NSDictionary *found = nil;
	for (NSDictionary *m in self.messages)
		if ([m[@"id"] isKindOfClass:NSNumber.class] &&
			[m[@"id"] longLongValue] == messageId)
			found = m;
	TGMessageReactionsViewController *screen =
			[[TGMessageReactionsViewController alloc] init];
	screen.chatId = self.chatId;
	screen.messageId = messageId;
	screen.message = found;
	[self.navigationController pushViewController:screen animated:YES];
}

#pragma mark - bots

- (int64_t)botChatUserId {
	return (!self.isGroup && self.chatId > 0 &&
			self.chatId != [[TGClient shared] savedMessagesChatId]) ? self.chatId : 0;
}

- (void)detectBotChat {
	int64_t botId = [self botChatUserId];
	if (!botId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] botInfoForUser:botId completion:^(NSDictionary *info){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		me.chatIsWithBot = (info != nil);
	}];
}

- (void)showBotMenu {
	int64_t botId = [self botChatUserId];
	if (!botId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] canBotSendMessages:botId completion:^(BOOL allowed){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Bot"
														   delegate:me
												  cancelButtonTitle:nil
											 destructiveButtonTitle:nil
												  otherButtonTitles:@"Commands",
																	@"About This Bot",
																	@"Menu Button",
																	@"Start Bot",
																	@"Similar Bots", nil];
		if (!allowed)
			[sheet addButtonWithTitle:@"Allow Messages From This Bot"];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = kBotMenuSheetTag;
		[sheet showInView:me.view];
	}];
}

- (void)runBotMenu:(NSString *)chosen {
	int64_t botId = [self botChatUserId];
	if (!botId)
		return;
	__weak typeof(self) weakSelf = self;

	if ([chosen isEqualToString:@"Commands"]){
		NSString *typed = [self composerText];
		void (^show)(NSArray *) = ^(NSArray *commands){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!commands.count){
				[me showAlertTitle:@"" message:@"This bot publishes no commands."];
				return;
			}
			me.botCommandList = commands;
			UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Commands"
															   delegate:me
													  cancelButtonTitle:nil
												 destructiveButtonTitle:nil
													  otherButtonTitles:nil];
			NSUInteger shown = MIN((NSUInteger)8, commands.count);
			for (NSUInteger i = 0; i < shown; i++){
				NSDictionary *entry = commands[i];
				NSString *description = entry[@"description"];
				[sheet addButtonWithTitle:(description.length
						? [NSString stringWithFormat:@"/%@ - %@", entry[@"command"], description]
						: [NSString stringWithFormat:@"/%@", entry[@"command"]])];
			}
			sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
			sheet.tag = kBotCommandsSheetTag;
			[sheet showInView:me.view];
		};
		if ([typed hasPrefix:@"/"] && typed.length > 1)
			[[TGClient shared] botCommandsForUser:botId matchingPrefix:typed
									   completion:show];
		else
			[[TGClient shared] botCommandsForUser:botId completion:show];
		return;
	}

	if ([chosen isEqualToString:@"About This Bot"]){
		[[TGClient shared] botInfoForUser:botId completion:^(NSDictionary *info){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!info){
				[me showAlertTitle:@"" message:@"This chat is not with a bot."];
				return;
			}
			NSString *description = info[@"description"];
			if (!description.length)
				description = info[@"shortDescription"];
			NSInteger commandCount = [info[@"commands"] count];
			NSMutableString *body = [NSMutableString string];
			[body appendString:(description.length ? description : @"No description.")];
			if (commandCount)
				[body appendFormat:@"\n\n%ld commands", (long)commandCount];
			[me showAlertTitle:(me.chatTitle ?: @"Bot") message:body];
		}];
		return;
	}

	if ([chosen isEqualToString:@"Menu Button"]){
		[[TGClient shared] menuButtonForBot:botId completion:^(NSDictionary *button){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			NSString *url = button[@"url"];
			if (!url.length){
				[me showAlertTitle:@"" message:@"This bot has no menu button."];
				return;
			}
			[me openLink:url];
		}];
		return;
	}

	if ([chosen isEqualToString:@"Start Bot"]){
		[[TGClient shared] startBot:botId inChat:self.chatId parameter:nil];
		[TGSnackbar showInView:self.view text:@"Bot started" seconds:3 onCommit:nil];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ [weakSelf reload]; });
		return;
	}

	if ([chosen isEqualToString:@"Similar Bots"]){
		[[TGClient shared] similarBotsFor:botId completion:^(NSArray *bots, NSInteger total){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!bots.count){
				[me showAlertTitle:@"" message:@"No similar bots were found."];
				return;
			}
			me.similarBotList = bots;
			UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:
					[NSString stringWithFormat:@"Similar Bots (%ld)", (long)total]
															   delegate:me
													  cancelButtonTitle:nil
												 destructiveButtonTitle:nil
													  otherButtonTitles:nil];
			NSUInteger shown = MIN((NSUInteger)8, bots.count);
			for (NSUInteger i = 0; i < shown; i++)
				[sheet addButtonWithTitle:(bots[i][@"name"] ?: bots[i][@"username"] ?: @"Bot")];
			sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
			sheet.tag = kSimilarBotsSheetTag;
			[sheet showInView:me.view];
		}];
		return;
	}

	if ([chosen isEqualToString:@"Allow Messages From This Bot"]){
		UIAlertView *ask = [[UIAlertView alloc] initWithTitle:(self.chatTitle ?: @"Bot")
													  message:@"Let this bot message you without being started?"
													 delegate:self
											cancelButtonTitle:@"Cancel"
											otherButtonTitles:@"Allow", nil];
		ask.tag = kAllowBotAlertTag;
		[ask show];
	}
}

- (void)openBotFromEntry:(NSDictionary *)entry {
	int64_t userId = [entry[@"id"] longLongValue];
	if (!userId)
		return;
	NSString *name = entry[@"name"] ?: entry[@"username"] ?: @"Bot";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] privateChatWithUser:userId completion:^(int64_t openedChatId){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!openedChatId){
			[me showAlertTitle:@"" message:@"That bot could not be opened."];
			return;
		}
		[me openChatId:openedChatId title:name isGroup:NO];
	}];
}

#pragma mark - bot keyboards

- (NSArray *)botButtonsForMessage:(NSDictionary *)m {
	NSMutableArray *flat = [NSMutableArray array];
	for (NSArray *row in [[TGClient shared] inlineKeyboardRowsForMessage:m])
		for (NSDictionary *button in row)
			if ([button isKindOfClass:NSDictionary.class])
				[flat addObject:button];

	NSDictionary *replyKeyboard = [[TGClient shared] replyKeyboardForMessage:m];
	for (NSArray *row in replyKeyboard[@"rows"]){
		for (NSDictionary *button in row){
			if (![button isKindOfClass:NSDictionary.class])
				continue;
			NSMutableDictionary *copy = [button mutableCopy];
			copy[@"replyKeyboard"] = @YES;
			[flat addObject:copy];
		}
	}
	return flat;
}

- (BOOL)offerBotButtonsForRow:(NSInteger)row message:(NSDictionary *)m {
	NSArray *buttons = [self botButtonsForMessage:m];
	if (!buttons.count)
		return NO;

	self.botButtons = buttons;
	self.botButtonsMessageId = [m[@"id"] longLongValue];
	self.botButtonsRow = row;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Bot Buttons"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	NSUInteger shown = MIN((NSUInteger)8, buttons.count);
	for (NSUInteger i = 0; i < shown; i++){
		NSString *text = buttons[i][@"text"];
		[sheet addButtonWithTitle:(text.length ? text : @"Button")];
	}
	[sheet addButtonWithTitle:@"Message Actions"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kBotButtonsSheetTag;
	[sheet showInView:self.view];
	return YES;
}

- (void)runBotButtonAtIndex:(NSInteger)index {
	NSUInteger shown = MIN((NSUInteger)8, self.botButtons.count);
	if (index < 0 || index >= (NSInteger)shown){
		[self showActionsSheetForRow:self.botButtonsRow];
		return;
	}
	NSDictionary *button = self.botButtons[index];
	NSString *kind = button[@"kind"];
	int64_t messageId = self.botButtonsMessageId;
	__weak typeof(self) weakSelf = self;

	if ([button[@"replyKeyboard"] boolValue]){
		[self runReplyKeyboardButton:button messageId:messageId];
		return;
	}

	if ([kind isEqualToString:@"url"] || [kind isEqualToString:@"loginUrl"] ||
		[kind isEqualToString:@"webApp"]){
		[self openLink:button[@"url"]];
		return;
	}

	if ([kind isEqualToString:@"copyText"]){
		NSString *text = button[@"copyText"] ?: button[@"text"];
		if (!text.length){
			[self showAlertTitle:@"" message:@"This button has nothing to copy."];
			return;
		}
		[UIPasteboard generalPasteboard].string = text;
		[TGSnackbar showInView:self.view text:@"Copied" seconds:3 onCommit:nil];
		return;
	}

	if ([kind isEqualToString:@"switchInline"]){
		NSString *query = button[@"query"] ?: @"";
		self.input.text = query;
		[self inputChanged];
		[self.input becomeFirstResponder];
		[TGSnackbar showInView:self.view
						  text:([button[@"target"] isEqualToString:@"current"]
								? @"Query placed in the message field"
								: @"Query placed in the message field for this chat")
					   seconds:3 onCommit:nil];
		return;
	}

	if ([kind isEqualToString:@"user"]){
		int64_t userId = [button[@"userId"] longLongValue];
		if (!userId){
			[self showAlertTitle:@"" message:@"This button points at nobody."];
			return;
		}
		[self openBotFromEntry:@{ @"id" : @(userId),
								  @"name" : ([[TGClient shared] nameForUserId:userId]
											 ?: (button[@"text"] ?: @"Chat")) }];
		return;
	}

	if ([kind isEqualToString:@"callbackWithPassword"]){
		self.pendingCallbackButton = button;
		UIAlertView *ask = [[TGAlertView alloc] initWithTitle:(button[@"text"] ?: @"Password")
													  message:@"Your two-step verification password"
													 delegate:self
											cancelButtonTitle:@"Cancel"
											otherButtonTitles:@"Send", nil];
		if ([ask respondsToSelector:@selector(setAlertViewStyle:)])
			ask.alertViewStyle = UIAlertViewStyleSecureTextInput;
		ask.tag = kBotPasswordAlertTag;
		[ask show];
		return;
	}

	if ([kind isEqualToString:@"callback"] || [kind isEqualToString:@"callbackGame"]){
		[[TGClient shared] pressCallbackButton:button
										inChat:self.chatId
									   message:messageId
									completion:^(NSDictionary *answer){
			[weakSelf showCallbackAnswer:answer];
		}];
		return;
	}

	[self showAlertTitle:@"" message:@"This button cannot be used here."];
}

- (void)showCallbackAnswer:(NSDictionary *)answer {
	if (!answer){
		[self showAlertTitle:@"" message:@"The bot did not answer."];
		return;
	}
	NSString *url = answer[@"url"];
	if (url.length){
		[self openLink:url];
		return;
	}
	NSString *text = answer[@"text"];
	if (!text.length){
		[TGSnackbar showInView:self.view text:@"Done" seconds:2 onCommit:nil];
		return;
	}
	if ([answer[@"showAlert"] boolValue])
		[self showAlertTitle:@"" message:text];
	else
		[TGSnackbar showInView:self.view text:text seconds:3 onCommit:nil];
}

- (void)runReplyKeyboardButton:(NSDictionary *)button messageId:(int64_t)messageId {
	NSString *kind = button[@"kind"];

	if (!kind.length || [kind isEqualToString:@"text"]){
		NSString *text = button[@"text"];
		if (!text.length)
			return;
		self.input.text = text;
		[self inputChanged];
		[self sendTapped];
		return;
	}

	if ([kind isEqualToString:@"requestLocation"]){
		[self sendCurrentLocation];
		return;
	}

	if ([kind isEqualToString:@"requestPoll"]){
		[self showPollComposer];
		return;
	}

	if ([kind isEqualToString:@"webApp"]){
		[self openLink:button[@"url"]];
		return;
	}

	if ([kind isEqualToString:@"requestUsers"] || [kind isEqualToString:@"requestChat"]){
		self.sharePickerKind = kind;
		self.sharePickerButtonId = [button[@"buttonId"] integerValue];
		self.sharePickerMessageId = messageId;
		TGForwardPicker *picker = [[TGForwardPicker alloc] init];
		__weak typeof(self) weakSelf = self;
		picker.onPicked = ^(int64_t pickedChatId){
			[weakSelf completeShareWithChatId:pickedChatId];
		};
		[self.navigationController pushViewController:picker animated:YES];
		return;
	}

	[self showAlertTitle:@"" message:@"This button cannot be used here."];
}

- (void)completeShareWithChatId:(int64_t)pickedChatId {
	if (!pickedChatId || !self.sharePickerKind.length)
		return;

	if ([self.sharePickerKind isEqualToString:@"requestUsers"]){
		if (pickedChatId <= 0){
			[self showAlertTitle:@"" message:@"The bot asked for a person, not a group."];
			return;
		}
		[[TGClient shared] shareUsers:@[@(pickedChatId)]
						withBotButton:self.sharePickerButtonId
							   inChat:self.chatId
							  message:self.sharePickerMessageId];
	} else {
		[[TGClient shared] shareChat:pickedChatId
					   withBotButton:self.sharePickerButtonId
							  inChat:self.chatId
							 message:self.sharePickerMessageId];
	}
	self.sharePickerKind = nil;
	[TGSnackbar showInView:self.view text:@"Sent to the bot" seconds:3 onCommit:nil];
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [weakSelf reload]; });
}

#pragma mark - inline bots

- (void)askInlineBotQuery {
	NSString *typed = [self composerText];
	UIAlertView *ask = [[TGAlertView alloc] initWithTitle:@"Inline Bot"
												  message:@"Bot username and what to look for"
												 delegate:self
										cancelButtonTitle:@"Cancel"
										otherButtonTitles:@"Search", nil];
	if ([ask respondsToSelector:@selector(setAlertViewStyle:)]){
		ask.alertViewStyle = UIAlertViewStylePlainTextInput;
		[ask textFieldAtIndex:0].text = [typed hasPrefix:@"@"] ? typed : @"@";
	}
	ask.tag = kInlineQueryAlertTag;
	[ask show];
}

- (void)runInlineBotEntry:(NSString *)entry {
	NSString *trimmed = [entry stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed hasPrefix:@"@"])
		trimmed = [trimmed substringFromIndex:1];

	NSRange space = [trimmed rangeOfString:@" "];
	NSString *username = (space.location == NSNotFound)
			? trimmed : [trimmed substringToIndex:space.location];
	NSString *query = (space.location == NSNotFound)
			? @"" : [trimmed substringFromIndex:space.location + 1];

	if (!username.length){
		[self showRecentInlineBots];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] publicChatWithUsername:username completion:^(NSDictionary *chat){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		int64_t botId = [chat[@"id"] longLongValue];
		if (!botId)
			botId = [chat[@"chatId"] longLongValue];
		if (botId <= 0){
			[me showAlertTitle:@"" message:@"There is no such bot."];
			return;
		}
		[me runInlineQueryForBot:botId query:query offset:nil];
	}];
}

- (void)showRecentInlineBots {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] recentInlineBotsWithCompletion:^(NSArray *bots){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!bots.count){
			[me showAlertTitle:@"" message:@"You have not used an inline bot yet."];
			return;
		}
		me.recentInlineBotList = bots;
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Recent Inline Bots"
														   delegate:me
												  cancelButtonTitle:nil
											 destructiveButtonTitle:nil
												  otherButtonTitles:nil];
		NSUInteger shown = MIN((NSUInteger)8, bots.count);
		for (NSUInteger i = 0; i < shown; i++)
			[sheet addButtonWithTitle:[NSString stringWithFormat:@"@%@",
					(bots[i][@"username"] ?: bots[i][@"name"] ?: @"bot")]];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = kRecentBotsSheetTag;
		[sheet showInView:me.view];
	}];
}

- (void)runInlineQueryForBot:(int64_t)botId query:(NSString *)query offset:(NSString *)offset {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inlineQueryToBot:botId
								 inChat:self.chatId
								  query:(query ?: @"")
								 offset:offset
							 completion:^(NSDictionary *results){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!results){
			[me showAlertTitle:@"" message:@"That bot did not answer an inline query."];
			return;
		}
		me.inlineResults = results;
		me.inlineBotId = botId;
		me.inlineQueryText = query;
		[me showInlineResults];
	}];
}

- (void)showInlineResults {
	NSArray *results = self.inlineResults[@"results"];
	NSString *buttonText = self.inlineResults[@"buttonText"];
	if (!results.count && !buttonText.length){
		[self showAlertTitle:@"" message:@"Nothing was found."];
		return;
	}
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Results"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	NSUInteger shown = MIN((NSUInteger)7, results.count);
	for (NSUInteger i = 0; i < shown; i++){
		NSDictionary *result = results[i];
		NSString *title = result[@"title"];
		if (!title.length)
			title = result[@"description"];
		if (!title.length)
			title = result[@"kind"] ?: @"Result";
		[sheet addButtonWithTitle:title];
	}
	if ([self.inlineResults[@"nextOffset"] length])
		[sheet addButtonWithTitle:@"More Results"];
	if (buttonText.length)
		[sheet addButtonWithTitle:buttonText];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kInlineResultsSheetTag;
	[sheet showInView:self.view];
}

- (void)runInlineResultAtIndex:(NSInteger)index {
	NSArray *results = self.inlineResults[@"results"];
	NSUInteger shown = MIN((NSUInteger)7, results.count);
	NSString *nextOffset = self.inlineResults[@"nextOffset"];
	NSString *buttonText = self.inlineResults[@"buttonText"];

	if (index >= 0 && index < (NSInteger)shown){
		NSDictionary *result = results[index];
		[[TGClient shared] sendInlineResult:result[@"id"]
									queryId:self.inlineResults[@"queryId"]
									 toChat:self.chatId
									replyTo:self.replyToId
									hideVia:NO];
		[self clearComposeState];
		self.input.text = @"";
		[self inputChanged];
		__weak typeof(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ [weakSelf reload]; });
		return;
	}

	NSInteger cursor = (NSInteger)shown;
	if (nextOffset.length){
		if (index == cursor){
			[self runInlineQueryForBot:self.inlineBotId
								 query:self.inlineQueryText
								offset:nextOffset];
			return;
		}
		cursor++;
	}
	if (buttonText.length && index == cursor){
		[[TGClient shared] startBot:self.inlineBotId
							 inChat:self.chatId
						  parameter:self.inlineResults[@"buttonParameter"]];
		[TGSnackbar showInView:self.view text:@"Bot started" seconds:3 onCommit:nil];
	}
}

#pragma mark - read state

- (void)markVisibleMessagesRead {
	NSArray *visible = [self.table indexPathsForVisibleRows];
	if (!visible.count)
		return;
	NSMutableArray *fresh = [NSMutableArray array];
	for (NSIndexPath *path in visible){
		for (NSDictionary *m in [self messagesAtRow:path.row]){
			if (![m[@"id"] isKindOfClass:NSNumber.class] || [m[@"outgoing"] boolValue])
				continue;
			if ([self.readMessageIds containsObject:m[@"id"]])
				continue;
			[self.readMessageIds addObject:m[@"id"]];
			[fresh addObject:m[@"id"]];
		}
	}
	if (fresh.count)
		[[TGClient shared] markRead:fresh inChat:self.chatId source:@"history"];
}

#pragma mark - media timestamps

- (NSTimeInterval)mediaTimestampInMessage:(NSDictionary *)m {
	NSString *text = [self textOf:m];
	if (!text.length)
		return -1;

	NSScanner *scanner = [NSScanner scannerWithString:text];
	NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
	while (![scanner isAtEnd]){
		[scanner scanUpToCharactersFromSet:digits intoString:NULL];
		NSInteger first = 0;
		NSUInteger mark = scanner.scanLocation;
		if (![scanner scanInteger:&first])
			break;
		if (scanner.scanLocation >= text.length ||
			[text characterAtIndex:scanner.scanLocation] != ':'){
			if (scanner.scanLocation == mark)
				scanner.scanLocation = mark + 1;
			continue;
		}
		scanner.scanLocation += 1;
		NSInteger second = 0;
		if (![scanner scanInteger:&second])
			continue;
		if (scanner.scanLocation < text.length &&
			[text characterAtIndex:scanner.scanLocation] == ':'){
			scanner.scanLocation += 1;
			NSInteger third = 0;
			if ([scanner scanInteger:&third])
				return first * 3600 + second * 60 + third;
			continue;
		}
		return first * 60 + second;
	}
	return -1;
}

- (void)highlightTimestampInLabel:(UILabel *)label {
	NSString *text = [label.text isKindOfClass:NSString.class] ? label.text : nil;
	if (!text.length || ![label respondsToSelector:@selector(setAttributedText:)])
		return;
	NSRange found = [text rangeOfString:@":"];
	if (found.location == NSNotFound || found.location == 0)
		return;

	NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
	NSUInteger start = found.location;
	while (start > 0 &&
		   [digits characterIsMember:[text characterAtIndex:start - 1]])
		start--;
	NSUInteger end = found.location + 1;
	while (end < text.length &&
		   ([digits characterIsMember:[text characterAtIndex:end]] ||
			[text characterAtIndex:end] == ':'))
		end++;
	if (start == found.location || end == found.location + 1)
		return;

	NSMutableAttributedString *shown = [[NSMutableAttributedString alloc]
			initWithString:text
				attributes:@{NSFontAttributeName : label.font,
							 NSForegroundColorAttributeName : label.textColor}];
	[shown addAttribute:NSForegroundColorAttributeName
				  value:[[TGTheme shared] accentColour]
				  range:NSMakeRange(start, end - start)];
	label.attributedText = shown;
}

- (BOOL)openMediaTimestamp:(NSTimeInterval)seconds forRow:(NSInteger)row {
	NSDictionary *m = [self messageAtRow:row];
	NSDictionary *target = nil;

	NSNumber *replyTo = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	if (replyTo){
		for (NSDictionary *candidate in self.messages)
			if ([candidate[@"id"] isEqual:replyTo])
				target = candidate;
	}
	if (!target)
		return NO;

	NSString *kind = target[@"kind"];
	if (![@"messageVoiceNote" isEqualToString:kind] &&
		![@"messageAudio" isEqualToString:kind])
		return NO;

	[self playAudioMessage:target fromSeconds:seconds];
	return YES;
}

#pragma mark - send state

- (UIImage *)statusGlyphForMessage:(NSDictionary *)m white:(BOOL)white {
	NSString *state = [self sendStateForMessage:m];
	if ([state isEqualToString:@"pending"])
		return [self clockGlyphWhite:white];
	if ([state isEqualToString:@"failed"])
		return [self failedGlyph];
	return [TGIcons ticksWhite:white];
}

- (NSString *)sendStateForMessage:(NSDictionary *)m {
	if (![m[@"id"] isKindOfClass:NSNumber.class] || ![m[@"outgoing"] boolValue])
		return @"sent";
	NSNumber *messageId = m[@"id"];
	NSString *known = self.sendStates[messageId];
	if (known)
		return known;
	if ([self.sendStatesRequested containsObject:messageId])
		return @"sent";

	[self.sendStatesRequested addObject:messageId];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sendingStateOfMessage:[messageId longLongValue]
									  inChat:self.chatId
								  completion:^(NSString *state, BOOL canRetry){
		TGChatViewController *me = weakSelf;
		if (!me || !state.length)
			return;
		NSString *before = me.sendStates[messageId];
		me.sendStates[messageId] = state;
		if (!before && ![state isEqualToString:@"sent"])
			[me.table reloadData];
	}];
	return @"sent";
}

- (UIImage *)clockGlyphWhite:(BOOL)white {
	CGSize size = CGSizeMake(15, 9);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	UIColor *ink = white ? [UIColor whiteColor] : [[TGTheme shared] timeColour];
	CGContextSetStrokeColorWithColor(ctx, ink.CGColor);
	CGContextSetLineWidth(ctx, 1.0f);
	CGRect face = CGRectMake(5.5f, 0.5f, 8, 8);
	CGContextStrokeEllipseInRect(ctx, face);
	CGContextMoveToPoint(ctx, 9.5f, 4.5f);
	CGContextAddLineToPoint(ctx, 9.5f, 2.0f);
	CGContextMoveToPoint(ctx, 9.5f, 4.5f);
	CGContextAddLineToPoint(ctx, 11.5f, 5.5f);
	CGContextStrokePath(ctx);
	UIImage *glyph = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return glyph;
}

- (UIImage *)failedGlyph {
	CGSize size = CGSizeMake(15, 9);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	UIColor *red = [UIColor colorWithRed:0.78f green:0.16f blue:0.13f alpha:1.0f];
	CGContextSetFillColorWithColor(ctx, red.CGColor);
	CGContextFillEllipseInRect(ctx, CGRectMake(5.5f, 0.5f, 8, 8));
	CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
	CGContextFillRect(ctx, CGRectMake(9.0f, 2.0f, 1, 3.5f));
	CGContextFillRect(ctx, CGRectMake(9.0f, 6.5f, 1, 1));
	UIImage *glyph = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return glyph;
}

#pragma mark - alerts

- (NSString *)textInAlert:(UIAlertView *)alertView {
	if (![alertView respondsToSelector:@selector(textFieldAtIndex:)])
		return @"";
	return [[alertView textFieldAtIndex:0].text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (void)handlePastePhotoAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex){
		self.pendingPastedImage = nil;
		return;
	}
	[self sendPendingPastedImage];
}

- (void)handleStickerLinkAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	NSString *link = self.pendingStickerSetLink;
	self.pendingStickerSetLink = nil;
	if (buttonIndex == alertView.cancelButtonIndex || !link.length)
		return;
	[UIPasteboard generalPasteboard].string = link;
	[TGSnackbar showInView:self.view text:@"Link copied" seconds:3 onCommit:nil];
}

- (void)handleBotPasswordAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	NSDictionary *button = self.pendingCallbackButton;
	self.pendingCallbackButton = nil;
	if (buttonIndex == alertView.cancelButtonIndex || !button)
		return;
	NSString *password = [alertView respondsToSelector:@selector(textFieldAtIndex:)]
			? [alertView textFieldAtIndex:0].text : @"";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] pressCallbackButton:button
									inChat:self.chatId
								   message:self.botButtonsMessageId
								  password:(password ?: @"")
								completion:^(NSDictionary *answer){
		[weakSelf showCallbackAnswer:answer];
	}];
}

- (void)handleInlineQueryAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	NSString *entry = [alertView respondsToSelector:@selector(textFieldAtIndex:)]
			? [alertView textFieldAtIndex:0].text : @"";
	[self runInlineBotEntry:(entry ?: @"")];
}

- (void)handleAllowBotAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] allowBotToSendMessages:[self botChatUserId]
								   completion:^(BOOL ok){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[me showAlertTitle:@""
				   message:(ok ? @"This bot may now message you."
							   : @"That permission could not be granted.")];
	}];
}

- (void)handleBotStartAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	NSString *link = self.pendingBotStartLink;
	self.pendingBotStartLink = nil;
	if (buttonIndex == alertView.cancelButtonIndex || !link.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] openBotStartLink:link completion:^(int64_t openedChatId){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!openedChatId){
			[me showAlertTitle:@"" message:@"That bot link could not be used."];
			return;
		}
		[me openChatId:openedChatId title:@"Bot" isGroup:NO];
	}];
}

- (void)handleJoinLinkAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	NSString *invite = self.pendingInviteLink;
	self.pendingInviteLink = nil;
	if (buttonIndex == alertView.cancelButtonIndex || !invite.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] joinChatByInviteLink:invite
								 completion:^(int64_t joinedChatId, BOOL requestSent){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (joinedChatId){
			[me openChatId:joinedChatId title:@"Chat" isGroup:YES];
			return;
		}
		[me showAlertTitle:@""
				   message:(requestSent ? @"Your request to join has been sent."
									    : @"This invite link was refused.")];
	}];
}

- (void)handleVenueTitleAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	self.venueTitle = [self textInAlert:alertView];
	if (!self.venueTitle.length){
		[self showAlertTitle:@"" message:@"A place needs a name."];
		return;
	}
	UIAlertView *ask = [[TGAlertView alloc] initWithTitle:@"Place"
												  message:@"Its address"
												 delegate:self
										cancelButtonTitle:@"Cancel"
										otherButtonTitles:@"Send", nil];
	if ([ask respondsToSelector:@selector(setAlertViewStyle:)])
		ask.alertViewStyle = UIAlertViewStylePlainTextInput;
	ask.tag = kVenueAddressAlertTag;
	[ask show];
}

- (void)handleVenueAddressAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex){
		self.venueTitle = nil;
		return;
	}
	self.venueAddress = [self textInAlert:alertView];
	self.locationMode = @"venue";
	[self sendCurrentLocation];
}

- (void)handleQuickReplyAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	NSString *name = [self textInAlert:alertView];
	NSString *body = [self composerText];
	if (!name.length || !body.length){
		[self showAlertTitle:@"" message:@"A quick reply needs a name and some text."];
		return;
	}
	__weak TGChatViewController *weakSelf = self;
	[[TGClient shared] addQuickReplyShortcutNamed:name text:body
									   completion:^(BOOL ok){
		[weakSelf showAlertTitle:@""
					 message:(ok ? @"Saved as a quick reply."
								 : @"That name was refused.")];
	}];
}

- (void)handleReportTextAlert:(UIAlertView *)alertView buttonIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	NSString *text = @"";
	if ([alertView respondsToSelector:@selector(textFieldAtIndex:)])
		text = [alertView textFieldAtIndex:0].text ?: @"";
	[self reportMessage:self.reportMessageId
			   optionId:self.reportTextOptionId
				   text:text];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (alertView.tag == kPastePhotoAlertTag){
		[self handlePastePhotoAlert:alertView buttonIndex:buttonIndex];
		return;
	}
	if (alertView.tag == kStickerLinkAlertTag){
		[self handleStickerLinkAlert:alertView buttonIndex:buttonIndex];
		return;
	}
	if (alertView.tag == kBotPasswordAlertTag){
		[self handleBotPasswordAlert:alertView buttonIndex:buttonIndex];
		return;
	}
	if (alertView.tag == kInlineQueryAlertTag){
		[self handleInlineQueryAlert:alertView buttonIndex:buttonIndex];
		return;
	}
	if (alertView.tag == kAllowBotAlertTag){
		[self handleAllowBotAlert:alertView buttonIndex:buttonIndex];
		return;
	}
	if (alertView.tag == kBotStartAlertTag){
		[self handleBotStartAlert:alertView buttonIndex:buttonIndex];
		return;
	}
	if (alertView.tag == kJoinLinkAlertTag){
		[self handleJoinLinkAlert:alertView buttonIndex:buttonIndex];
		return;
	}
	if (alertView.tag == kVenueTitleAlertTag){
		[self handleVenueTitleAlert:alertView buttonIndex:buttonIndex];
		return;
	}
	if (alertView.tag == kVenueAddressAlertTag){
		[self handleVenueAddressAlert:alertView buttonIndex:buttonIndex];
		return;
	}
	if (alertView.tag == kQuickReplyAlertTag){
		[self handleQuickReplyAlert:alertView buttonIndex:buttonIndex];
		return;
	}
	if (alertView.tag != kReportTextAlertTag)
		return;
	[self handleReportTextAlert:alertView buttonIndex:buttonIndex];
}

#pragma mark - keyboard

- (void)adoptKeyboardTiming:(NSNotification *)note {
	NSNumber *duration = note.userInfo[UIKeyboardAnimationDurationUserInfoKey];
	NSNumber *curve = note.userInfo[UIKeyboardAnimationCurveUserInfoKey];
	self.keyboardDuration = duration ? duration.doubleValue : 0.25;
	self.keyboardCurve = curve ? (UIViewAnimationCurve)curve.integerValue
							   : UIViewAnimationCurveEaseInOut;
}

- (void)keyboardWillShow:(NSNotification *)note {
	CGRect kb = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	if (self.stickerPanel){
		[self.stickerPanel removeFromSuperview];
		self.stickerPanel = nil;
	}
	[self adoptKeyboardTiming:note];
	[self shiftForKeyboardHeight:kb.size.height];
}

- (void)keyboardWillHide:(NSNotification *)note {
	[self adoptKeyboardTiming:note];
	[self shiftForKeyboardHeight:0];
}

- (void)shiftForKeyboardHeight:(CGFloat)height {
	CGRect b = self.view.bounds;
	NSTimeInterval duration = (self.keyboardDuration > 0) ? self.keyboardDuration : 0.25;
	UIViewAnimationOptions curve =
			(UIViewAnimationOptions)(self.keyboardCurve << 16) |
			UIViewAnimationOptionBeginFromCurrentState;
	BOOL wasAtBottom = [self historyIsAtBottom];

	[UIView animateWithDuration:duration delay:0.0 options:curve animations:^{
		self.inputBar.frame = CGRectMake(0, b.size.height - kInputHeight - height,
				b.size.width, kInputHeight);
		self.table.frame = CGRectMake(0, 0, b.size.width,
				b.size.height - kInputHeight - height);
		CGFloat top = CGRectGetMinY(self.inputBar.frame);
		if (self.composeBanner && !self.composeBanner.hidden){
			CGRect banner = self.composeBanner.frame;
			banner.origin.y = top - banner.size.height;
			self.composeBanner.frame = banner;
		}
		if (self.stickerPanel){
			CGRect panel = self.stickerPanel.frame;
			panel.origin.y = top + kInputHeight;
			self.stickerPanel.frame = panel;
		}
		[self layoutFloatingButtons];
		[self centreEmptyPlate];
		if (self.selectionPanel){
			CGRect panel = self.selectionPanel.frame;
			panel.origin.y = top;
			self.selectionPanel.frame = panel;
		}
	} completion:^(BOOL done){
		if (wasAtBottom)
			[self scrollToBottomAnimated:NO];
		[self updateScrollDownButton];
	}];
}

@end

// vim:ft=objc











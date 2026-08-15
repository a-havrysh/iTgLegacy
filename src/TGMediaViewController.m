#import "TGMediaViewController.h"

#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

#import "TGClient.h"
#import "TGClient+Files.h"
#import "TGClient+Messages.h"
#import "TGClient+Search.h"
#import "TGForwardPicker.h"
#import "TGIcons.h"
#import "TGImageDecode.h"
#import "TGRemoteImageView.h"
#import "TGTheme.h"
#import "TGViewRecycler.h"

static const CGFloat TGMediaTileSide    = 75.0f;
static const CGFloat TGMediaTileSpacing = 4.0f;
static const CGFloat TGMediaRowHeight   = 79.0f;
static const CGFloat TGMediaBannerHeight = 44.0f;
static const NSInteger TGMediaPageSize  = 50;
static const CGFloat TGMediaPageGap     = 40.0f;
static const CGFloat TGMediaScopeHeight = 36.0f;
static const CGFloat TGMediaListRowHeight = 56.0f;

enum {
	TGMediaScopeMedia = 0,
	TGMediaScopeFiles = 1,
	TGMediaScopeLinks = 2,
	TGMediaScopeMusic = 3,
};

static NSString *const TGMediaTileIdentifier = @"TGMediaTile";

static NSString *TGMediaFormatDuration(NSInteger seconds) {
	if (seconds < 0)
		seconds = 0;
	return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

static NSString *TGMediaFormatBytes(long long bytes) {
	if (bytes < 1024)
		return [NSString stringWithFormat:@"%lld B", bytes];
	double kb = bytes / 1024.0;
	if (kb < 1024.0)
		return [NSString stringWithFormat:@"%.0f KB", kb];
	double mb = kb / 1024.0;
	if (mb < 1024.0)
		return [NSString stringWithFormat:@"%.1f MB", mb];
	return [NSString stringWithFormat:@"%.2f GB", mb / 1024.0];
}

static UIImage *TGMediaTilePlaceholder(void) {
	static UIImage *placeholder = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		placeholder = [UIImage imageNamed:@"FlatImagePlaceholder.png"];
		if (placeholder)
			return;
		CGSize size = CGSizeMake(TGMediaTileSide, TGMediaTileSide);
		UIGraphicsBeginImageContextWithOptions(size, YES, 0.0f);
		[[UIColor colorWithWhite:0.87f alpha:1.0f] setFill];
		UIRectFill(CGRectMake(0, 0, size.width, size.height));
		placeholder = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	});
	return placeholder;
}

static NSDictionary *TGMediaItemFromMessage(NSDictionary *message) {
	if (![message isKindOfClass:NSDictionary.class])
		return nil;

	NSDictionary *content = message[@"content"];
	NSString *kind = content[@"@type"];
	if (![kind isKindOfClass:NSString.class])
		return nil;

	CGFloat scale = [UIScreen mainScreen].scale;
	TGClient *client = [TGClient shared];

	NSNumber *thumbId = nil;
	NSNumber *fullId = nil;
	NSInteger duration = 0;
	BOOL isVideo = NO;

	if ([kind isEqualToString:@"messagePhoto"]){
		NSArray *sizes = content[@"photo"][@"sizes"];
		if (![sizes isKindOfClass:NSArray.class] || sizes.count == 0)
			return nil;
		NSDictionary *small = [client bestPhotoSizeIn:sizes forWidth:TGMediaTileSide scale:scale];
		NSDictionary *large = [client bestPhotoSizeIn:sizes forWidth:320.0f scale:scale];
		thumbId = small[@"fileId"];
		fullId = large[@"fileId"] ?: [sizes lastObject][@"photo"][@"id"];

	} else if ([kind isEqualToString:@"messageVideo"]){
		NSDictionary *thumb = [client decodableThumbnail:content[@"video"][@"thumbnail"]];
		thumbId = thumb[@"fileId"];
		fullId = content[@"video"][@"video"][@"id"];
		duration = [content[@"video"][@"duration"] integerValue];
		isVideo = YES;

	} else if ([kind isEqualToString:@"messageAnimation"]){
		NSDictionary *thumb = [client decodableThumbnail:content[@"animation"][@"thumbnail"]];
		thumbId = thumb[@"fileId"];
		fullId = content[@"animation"][@"animation"][@"id"];
		duration = [content[@"animation"][@"duration"] integerValue];
		isVideo = YES;

	} else {
		return nil;
	}

	if (![thumbId isKindOfClass:NSNumber.class] && ![fullId isKindOfClass:NSNumber.class])
		return nil;

	NSString *caption = content[@"caption"][@"text"];
	if (![caption isKindOfClass:NSString.class])
		caption = @"";

	return @{
		@"messageId" : message[@"id"] ?: @(0),
		@"thumbId"   : [thumbId isKindOfClass:NSNumber.class] ? thumbId : (fullId ?: @(0)),
		@"fullId"    : [fullId isKindOfClass:NSNumber.class] ? fullId : (thumbId ?: @(0)),
		@"duration"  : @(duration),
		@"isVideo"   : @(isVideo),
		@"caption"   : caption,
		@"date"      : message[@"date"] ?: @(0),
	};
}

static NSArray *TGMediaScopeTitles(void) {
	static NSArray *titles = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		titles = @[@"Media", @"Files", @"Links", @"Music"];
	});
	return titles;
}

static NSString *TGMediaFilterForScope(NSInteger scope) {
	switch (scope){
		case TGMediaScopeFiles: return @"searchMessagesFilterDocument";
		case TGMediaScopeLinks: return @"searchMessagesFilterUrl";
		case TGMediaScopeMusic: return @"searchMessagesFilterAudio";
		default: return @"searchMessagesFilterPhotoAndVideo";
	}
}

static BOOL TGMediaScopeIsGrid(NSInteger scope) {
	return scope == TGMediaScopeMedia;
}

static NSString *TGMediaEmptyTextForScope(NSInteger scope) {
	switch (scope){
		case TGMediaScopeFiles: return @"No shared files";
		case TGMediaScopeLinks: return @"No shared links";
		case TGMediaScopeMusic: return @"No shared music";
		default: return @"No Photos in this Conversation";
	}
}

static NSString *TGMediaMonthForDate(NSInteger date) {
	if (date <= 0)
		return @"";
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		[formatter setDateFormat:@"LLLL yyyy"];
	}
	return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:date]];
}

static NSString *TGMediaDayForDate(NSInteger date) {
	if (date <= 0)
		return @"";
	return [NSDateFormatter localizedStringFromDate:
			[NSDate dateWithTimeIntervalSince1970:date]
										  dateStyle:NSDateFormatterMediumStyle
										  timeStyle:NSDateFormatterShortStyle];
}

static NSString *TGMediaFirstUrlInText(NSString *text, NSDictionary *content) {
	NSString *pageUrl = content[@"web_page"][@"url"];
	if ([pageUrl isKindOfClass:NSString.class] && pageUrl.length)
		return pageUrl;

	if (![text isKindOfClass:NSString.class] || text.length == 0)
		return nil;

	static NSDataDetector *detector = nil;
	if (!detector){
		detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL];
	}
	NSTextCheckingResult *match = [detector firstMatchInString:text
													   options:0
														 range:NSMakeRange(0, text.length)];
	if (match && match.URL)
		return [match.URL absoluteString];
	return nil;
}

static NSDictionary *TGMediaListItemFromMessage(NSDictionary *message, NSInteger scope) {
	if (![message isKindOfClass:NSDictionary.class])
		return nil;

	NSDictionary *content = message[@"content"];
	NSString *kind = content[@"@type"];
	if (![kind isKindOfClass:NSString.class])
		return nil;

	NSString *title = @"";
	NSString *detail = @"";
	NSString *url = @"";
	NSNumber *fileId = nil;
	long long size = 0;
	NSInteger duration = 0;

	if (scope == TGMediaScopeFiles){
		if (![kind isEqualToString:@"messageDocument"])
			return nil;
		NSDictionary *document = content[@"document"];
		NSString *name = document[@"file_name"];
		title = [name isKindOfClass:NSString.class] && name.length ? name : @"File";
		NSDictionary *file = document[@"document"];
		fileId = file[@"id"];
		size = [file[@"size"] longLongValue];
		if (size <= 0)
			size = [file[@"expected_size"] longLongValue];
		detail = TGMediaFormatBytes(size);

	} else if (scope == TGMediaScopeMusic){
		if (![kind isEqualToString:@"messageAudio"])
			return nil;
		NSDictionary *audio = content[@"audio"];
		NSString *name = audio[@"title"];
		if (![name isKindOfClass:NSString.class] || name.length == 0)
			name = audio[@"file_name"];
		title = [name isKindOfClass:NSString.class] && name.length ? name : @"Audio";
		NSString *performer = audio[@"performer"];
		duration = [audio[@"duration"] integerValue];
		NSDictionary *file = audio[@"audio"];
		fileId = file[@"id"];
		size = [file[@"size"] longLongValue];
		if (size <= 0)
			size = [file[@"expected_size"] longLongValue];
		detail = [performer isKindOfClass:NSString.class] && performer.length
				? [NSString stringWithFormat:@"%@ · %@", performer,
						TGMediaFormatDuration(duration)]
				: TGMediaFormatDuration(duration);

	} else {
		NSString *body = content[@"text"][@"text"];
		if (![body isKindOfClass:NSString.class])
			body = content[@"caption"][@"text"];
		NSString *found = TGMediaFirstUrlInText(body, content);
		if (!found.length)
			return nil;
		url = found;
		NSString *pageTitle = content[@"web_page"][@"title"];
		title = [pageTitle isKindOfClass:NSString.class] && pageTitle.length ? pageTitle : found;
		detail = found;
	}

	if (scope != TGMediaScopeLinks && ![fileId isKindOfClass:NSNumber.class])
		return nil;

	return @{
		@"messageId" : message[@"id"] ?: @(0),
		@"title"     : title,
		@"detail"    : detail,
		@"url"       : url,
		@"fileId"    : [fileId isKindOfClass:NSNumber.class] ? fileId : @(0),
		@"size"      : @(size),
		@"duration"  : @(duration),
		@"date"      : message[@"date"] ?: @(0),
		@"list"      : @(YES),
	};
}

#pragma mark - tile

@interface TGMediaTileView : TGRemoteImageView

@property (nonatomic, strong) UIView *badgeBar;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UIImageView *playView;
@property (nonatomic, strong) UIImageView *shadowView;

- (void)showVideoBadge:(NSString *)text;
- (void)hideVideoBadge;

@end

@implementation TGMediaTileView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self){
		self.reuseIdentifier = TGMediaTileIdentifier;
		self.clipsToBounds = YES;
		self.contentMode = UIViewContentModeScaleAspectFill;
		self.userInteractionEnabled = NO;
		self.fadeTransition = true;
		self.backgroundColor = [UIColor colorWithWhite:0.87f alpha:1.0f];

		UIImage *shadow = [UIImage imageNamed:@"MediaGridImageShadow.png"];
		if (shadow){
			_shadowView = [[UIImageView alloc] initWithImage:
					[shadow stretchableImageWithLeftCapWidth:(int)(shadow.size.width / 2)
												topCapHeight:(int)(shadow.size.height / 2)]];
			_shadowView.frame = CGRectMake(0, 0, TGMediaTileSide, TGMediaTileSide);
			_shadowView.userInteractionEnabled = NO;
			[self addSubview:_shadowView];
		}
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (_shadowView)
		_shadowView.frame = self.bounds;
}

- (void)buildBadge {
	if (_badgeBar)
		return;

	_badgeBar = [[UIView alloc] initWithFrame:CGRectMake(0, TGMediaTileSide - 19,
														 TGMediaTileSide, 19)];
	_badgeBar.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_badgeBar.userInteractionEnabled = NO;

	UIImage *play = [UIImage imageNamed:@"MessageInlineVideoIcon.png"];
	if (play){
		_playView = [[UIImageView alloc] initWithImage:play];
		_playView.frame = CGRectOffset(_playView.frame, 4, 5);
	} else {
		play = [TGIcons play];
		_playView = [[UIImageView alloc] initWithImage:play];
		_playView.frame = CGRectMake(4, (int)((19 - MIN(11.0f, play.size.height)) / 2),
									 MIN(11.0f, play.size.width), MIN(11.0f, play.size.height));
		_playView.contentMode = UIViewContentModeScaleAspectFit;
	}
	[_badgeBar addSubview:_playView];

	_badgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(TGMediaTileSide - 56 - 3, 0, 56, 19)];
	_badgeLabel.backgroundColor = [UIColor clearColor];
	_badgeLabel.textColor = [UIColor whiteColor];
	_badgeLabel.font = [UIFont boldSystemFontOfSize:10];
	_badgeLabel.textAlignment = NSTextAlignmentRight;
	[_badgeBar addSubview:_badgeLabel];

	[self addSubview:_badgeBar];
}

- (void)showVideoBadge:(NSString *)text {
	[self buildBadge];
	_badgeLabel.text = text;
	_badgeBar.hidden = NO;
	_badgeBar.frame = CGRectMake(0, self.bounds.size.height - 19, self.bounds.size.width, 19);
	_badgeLabel.frame = CGRectMake(self.bounds.size.width - 56 - 3, 0, 56, 19);
}

- (void)hideVideoBadge {
	_badgeBar.hidden = YES;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self hideVideoBadge];
	self.image = TGMediaTilePlaceholder();
}

- (void)prepareForRecycle:(TGViewRecycler *)recycler {
	[super prepareForRecycle:recycler];
	[self hideVideoBadge];
	self.image = nil;
	self.fileId = nil;
}

@end

#pragma mark - grid row

@class TGMediaGridCell;

@protocol TGMediaGridCellDelegate <NSObject>
- (void)gridCell:(TGMediaGridCell *)cell tappedItemAtIndex:(NSInteger)index;
@end

@interface TGMediaGridCell : UITableViewCell

@property (nonatomic, weak) TGViewRecycler *recycler;
@property (nonatomic, weak) id<TGMediaGridCellDelegate> gridDelegate;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, assign) NSInteger baseIndex;
@property (nonatomic, strong) NSMutableArray *tiles;

- (void)configureWithItems:(NSArray *)items baseIndex:(NSInteger)baseIndex;
- (void)releaseTiles;

@end

@implementation TGMediaGridCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self){
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.backgroundColor = [UIColor clearColor];
		self.contentView.backgroundColor = [UIColor clearColor];
		_tiles = [[NSMutableArray alloc] init];

		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(handleTap:)];
		[self.contentView addGestureRecognizer:tap];
	}
	return self;
}

- (TGMediaTileView *)takeTile {
	TGMediaTileView *tile = nil;
	TGViewRecycler *recycler = self.recycler;
	if (recycler){
		UIView<TGReusableView> *view = [recycler dequeueReusableViewWithIdentifier:TGMediaTileIdentifier];
		if ([view isKindOfClass:[TGMediaTileView class]])
			tile = (TGMediaTileView *)view;
	}
	if (!tile){
		tile = [[TGMediaTileView alloc] initWithFrame:CGRectZero];
		tile.image = TGMediaTilePlaceholder();
	}
	return tile;
}

- (void)releaseTiles {
	TGViewRecycler *recycler = self.recycler;
	for (TGMediaTileView *tile in _tiles){
		if (recycler)
			[recycler recycleView:tile];
		else {
			[tile cancelLoading];
			[tile removeFromSuperview];
		}
	}
	[_tiles removeAllObjects];
	self.items = nil;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self releaseTiles];
}

- (void)configureWithItems:(NSArray *)items baseIndex:(NSInteger)baseIndex {
	self.baseIndex = baseIndex;
	self.items = items;

	while (_tiles.count > items.count){
		TGMediaTileView *tile = [_tiles lastObject];
		[_tiles removeLastObject];
		TGViewRecycler *recycler = self.recycler;
		if (recycler)
			[recycler recycleView:tile];
		else {
			[tile cancelLoading];
			[tile removeFromSuperview];
		}
	}

	while (_tiles.count < items.count){
		TGMediaTileView *tile = [self takeTile];
		[self.contentView addSubview:tile];
		[_tiles addObject:tile];
	}

	CGFloat scale = [UIScreen mainScreen].scale;
	for (NSInteger i = 0; i < (NSInteger)items.count; i++){
		TGMediaTileView *tile = _tiles[i];
		NSDictionary *item = items[i];

		if (tile.superview != self.contentView)
			[self.contentView addSubview:tile];

		NSNumber *thumbId = item[@"thumbId"];
		[tile loadWithFileId:[thumbId isKindOfClass:NSNumber.class] ? thumbId : nil
					  square:TGMediaTileSide * scale
				 placeholder:TGMediaTilePlaceholder()
				   forceFade:false];

		if ([item[@"isVideo"] boolValue])
			[tile showVideoBadge:TGMediaFormatDuration([item[@"duration"] integerValue])];
		else
			[tile hideVideoBadge];
	}

	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	NSInteger count = (NSInteger)_tiles.count;
	if (count == 0)
		return;

	CGFloat width = self.contentView.bounds.size.width;
	NSInteger perRow = (NSInteger)(width / (TGMediaTileSide + TGMediaTileSpacing));
	if (perRow < 1)
		perRow = 1;
	CGFloat used = perRow * TGMediaTileSide + (perRow - 1) * TGMediaTileSpacing;
	CGFloat x = (CGFloat)(int)((width - used) / 2.0f);

	for (NSInteger i = 0; i < count; i++){
		TGMediaTileView *tile = _tiles[i];
		tile.frame = CGRectMake(x, TGMediaTileSpacing, TGMediaTileSide, TGMediaTileSide);
		if (tile.badgeBar && !tile.badgeBar.hidden)
			tile.badgeBar.frame = CGRectMake(0, TGMediaTileSide - 19, TGMediaTileSide, 19);
		x += TGMediaTileSide + TGMediaTileSpacing;
	}
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateRecognized)
		return;

	CGPoint point = [recognizer locationInView:self.contentView];
	for (NSInteger i = 0; i < (NSInteger)_tiles.count; i++){
		TGMediaTileView *tile = _tiles[i];
		if (CGRectContainsPoint(CGRectInset(tile.frame, -2, -2), point)){
			UIImage *loaded = [tile currentImage];
			if (loaded == nil || loaded == TGMediaTilePlaceholder())
				return;
			[self.gridDelegate gridCell:self tappedItemAtIndex:self.baseIndex + i];
			return;
		}
	}
}

@end

#pragma mark - fullscreen page

@interface TGMediaPageView : UIScrollView <UIScrollViewDelegate>

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, strong) NSNumber *loadingFileId;

- (void)setPageImage:(UIImage *)image;
- (void)resetZoom;
- (void)layoutImage;

@end

@implementation TGMediaPageView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self){
		self.backgroundColor = [UIColor clearColor];
		self.showsHorizontalScrollIndicator = NO;
		self.showsVerticalScrollIndicator = NO;
		self.scrollsToTop = NO;
		self.bouncesZoom = YES;
		self.minimumZoomScale = 1.0f;
		self.maximumZoomScale = 2.0f;
		self.delegate = self;
		self.pageIndex = -1;

		_imageView = [[UIImageView alloc] initWithFrame:self.bounds];
		_imageView.contentMode = UIViewContentModeScaleAspectFit;
		[self addSubview:_imageView];
	}
	return self;
}

- (void)setPageImage:(UIImage *)image {
	_imageView.image = image;
	[self resetZoom];
}

- (void)resetZoom {
	self.zoomScale = 1.0f;
	[self layoutImage];
}

- (void)layoutImage {
	self.contentSize = self.bounds.size;
	_imageView.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
	return _imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
	CGSize bounds = self.bounds.size;
	CGRect frame = _imageView.frame;
	frame.origin.x = frame.size.width < bounds.width
			? (CGFloat)(int)((bounds.width - frame.size.width) / 2.0f) : 0.0f;
	frame.origin.y = frame.size.height < bounds.height
			? (CGFloat)(int)((bounds.height - frame.size.height) / 2.0f) : 0.0f;
	_imageView.frame = frame;
}

@end

#pragma mark - fullscreen viewer

@interface TGMediaFullscreenController : UIViewController
		<UIScrollViewDelegate, UIGestureRecognizerDelegate, UIActionSheetDelegate>

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) void (^onMessageDeleted)(int64_t messageId);
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, assign) NSInteger startIndex;
@property (nonatomic, assign) NSInteger currentIndex;

@property (nonatomic, strong) UIScrollView *pagingView;
@property (nonatomic, strong) NSMutableDictionary *visiblePages;
@property (nonatomic, strong) NSMutableArray *pagePool;
@property (nonatomic, strong) NSMutableDictionary *imageCache;

@property (nonatomic, strong) UIImageView *topBar;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *bottomBar;
@property (nonatomic, strong) UIView *controlsContainer;
@property (nonatomic, strong) UIView *progressContainer;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UIActivityIndicatorView *progressSpinner;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSMutableSet *failedPages;
@property (nonatomic, strong) NSMutableSet *prefetchedFiles;
@property (nonatomic, strong) NSArray *sheetActions;

@property (nonatomic, assign) BOOL chromeHidden;
@property (nonatomic, assign) BOOL dismissing;
@property (nonatomic, assign) BOOL statusBarWasHidden;

- (instancetype)initWithItems:(NSArray *)items index:(NSInteger)index;

@end

@implementation TGMediaFullscreenController

- (instancetype)initWithItems:(NSArray *)items index:(NSInteger)index {
	self = [super init];
	if (self){
		_items = [NSMutableArray arrayWithArray:items ?: @[]];
		_startIndex = index;
		_currentIndex = index;
		_visiblePages = [[NSMutableDictionary alloc] init];
		_pagePool = [[NSMutableArray alloc] init];
		_imageCache = [[NSMutableDictionary alloc] init];
		_failedPages = [[NSMutableSet alloc] init];
		_prefetchedFiles = [[NSMutableSet alloc] init];
		self.modalPresentationStyle = UIModalPresentationFullScreen;
	}
	return self;
}

- (void)loadView {
	[super loadView];
	self.view.backgroundColor = [UIColor blackColor];
	self.view.clipsToBounds = YES;

	CGRect bounds = self.view.bounds;

	_pagingView = [[UIScrollView alloc] initWithFrame:
			CGRectMake(-TGMediaPageGap / 2.0f, 0,
					   bounds.size.width + TGMediaPageGap, bounds.size.height)];
	_pagingView.pagingEnabled = YES;
	_pagingView.alwaysBounceHorizontal = YES;
	_pagingView.alwaysBounceVertical = NO;
	_pagingView.showsHorizontalScrollIndicator = NO;
	_pagingView.showsVerticalScrollIndicator = NO;
	_pagingView.scrollsToTop = NO;
	_pagingView.delaysContentTouches = NO;
	_pagingView.backgroundColor = [UIColor clearColor];
	_pagingView.delegate = self;
	[self.view addSubview:_pagingView];

	UIImage *topPanelImage = [UIImage imageNamed:@"GalleryTopPanel.png"];
	CGFloat topPanelHeight = topPanelImage ? topPanelImage.size.height : 44.0f;
	_topBar = [[UIImageView alloc] initWithFrame:
			CGRectMake(0, 20, bounds.size.width, topPanelHeight)];
	_topBar.image = topPanelImage;
	if (!topPanelImage)
		_topBar.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_topBar.userInteractionEnabled = YES;
	_topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:_topBar];

	UIImage *cornersImage = [UIImage imageNamed:@"NavigationBar_Corners.png"];
	if (cornersImage){
		UIImageView *corners = [[UIImageView alloc] initWithImage:
				[cornersImage stretchableImageWithLeftCapWidth:(int)(cornersImage.size.width / 2)
												  topCapHeight:0]];
		corners.frame = CGRectMake(0, -20, bounds.size.width, cornersImage.size.height);
		corners.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[_topBar addSubview:corners];
	}

	UIImage *closePlate = [UIImage imageNamed:@"GalleryDoneButton.png"];
	UIImage *closePlateHighlighted = [UIImage imageNamed:@"GalleryDoneButton_Highlighted.png"];
	UIButton *done = [UIButton buttonWithType:UIButtonTypeCustom];
	done.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	[done setTitle:@"Close" forState:UIControlStateNormal];
	[done setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[done setTitleShadowColor:[UIColor colorWithWhite:0.0f alpha:0.5f]
					 forState:UIControlStateNormal];
	done.titleLabel.shadowOffset = CGSizeMake(0, -1);
	if (closePlate){
		[done setBackgroundImage:[closePlate stretchableImageWithLeftCapWidth:11 topCapHeight:0]
						forState:UIControlStateNormal];
		if (closePlateHighlighted)
			[done setBackgroundImage:[closePlateHighlighted
					stretchableImageWithLeftCapWidth:11 topCapHeight:0]
							forState:UIControlStateHighlighted];
	}
	CGSize closeTitleSize = [@"Close" sizeWithFont:done.titleLabel.font];
	CGFloat closeWidth = closeTitleSize.width + 22.0f;
	if (closeWidth < 55.0f)
		closeWidth = 55.0f;
	done.frame = CGRectMake(5, 7, closeWidth, 30);
	[done addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
	[_topBar addSubview:done];

	_counterLabel = [[UILabel alloc] initWithFrame:
			CGRectMake((CGFloat)(int)((bounds.size.width - 140) / 2), 11, 140, 20)];
	_counterLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	_counterLabel.backgroundColor = [UIColor clearColor];
	_counterLabel.textColor = [UIColor whiteColor];
	_counterLabel.font = [UIFont boldSystemFontOfSize:20];
	_counterLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
	_counterLabel.shadowOffset = CGSizeMake(0, -1);
	_counterLabel.textAlignment = NSTextAlignmentCenter;
	[_topBar addSubview:_counterLabel];

	UIImage *bottomPanelImage = [UIImage imageNamed:@"GalleryBottomPanel.png"];
	CGFloat bottomPanelHeight = bottomPanelImage ? bottomPanelImage.size.height : 44.0f;
	_bottomBar = [[UIImageView alloc] initWithFrame:
			CGRectMake(0, bounds.size.height - bottomPanelHeight,
					   bounds.size.width, bottomPanelHeight)];
	if (bottomPanelImage)
		_bottomBar.image = [bottomPanelImage
				stretchableImageWithLeftCapWidth:(int)(bottomPanelImage.size.width / 2)
									topCapHeight:0];
	else
		_bottomBar.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_bottomBar.userInteractionEnabled = YES;
	_bottomBar.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleTopMargin;
	[self.view addSubview:_bottomBar];

	_controlsContainer = [[UIView alloc] initWithFrame:_bottomBar.bounds];
	_controlsContainer.backgroundColor = [UIColor clearColor];
	_controlsContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleHeight;
	[_bottomBar addSubview:_controlsContainer];

	_authorLabel = [[UILabel alloc] initWithFrame:
			CGRectMake((CGFloat)(int)((bounds.size.width - 220) / 2), 4, 220, 20)];
	_authorLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	_authorLabel.backgroundColor = [UIColor clearColor];
	_authorLabel.textColor = [UIColor whiteColor];
	_authorLabel.font = [UIFont boldSystemFontOfSize:14];
	_authorLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
	_authorLabel.shadowOffset = CGSizeMake(0, -1);
	_authorLabel.textAlignment = NSTextAlignmentCenter;
	[_controlsContainer addSubview:_authorLabel];

	_dateLabel = [[UILabel alloc] initWithFrame:
			CGRectMake((CGFloat)(int)((bounds.size.width - 140) / 2), 23, 140, 20)];
	_dateLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	_dateLabel.backgroundColor = [UIColor clearColor];
	_dateLabel.textColor = [UIColor whiteColor];
	_dateLabel.font = [UIFont systemFontOfSize:13];
	_dateLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
	_dateLabel.shadowOffset = CGSizeMake(0, -1);
	_dateLabel.textAlignment = NSTextAlignmentCenter;
	[_controlsContainer addSubview:_dateLabel];

	UIImage *playImage = [UIImage imageNamed:@"VideoPanelPlay.png"];
	_playButton = [UIButton buttonWithType:UIButtonTypeCustom];
	if (playImage){
		_playButton.frame = CGRectMake(
				(CGFloat)(int)((bounds.size.width - playImage.size.width) / 2),
				(CGFloat)(int)((bottomPanelHeight - playImage.size.height) / 2),
				playImage.size.width, playImage.size.height);
		[_playButton setBackgroundImage:playImage forState:UIControlStateNormal];
	} else {
		_playButton.frame = CGRectMake((CGFloat)(int)((bounds.size.width - 60) / 2),
									   (CGFloat)(int)((bottomPanelHeight - 30) / 2), 60, 30);
		_playButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		[_playButton setTitle:@"Play" forState:UIControlStateNormal];
		[_playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	}
	_playButton.showsTouchWhenHighlighted = YES;
	_playButton.exclusiveTouch = YES;
	_playButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	[_playButton addTarget:self action:@selector(playTapped)
		  forControlEvents:UIControlEventTouchUpInside];
	[_controlsContainer addSubview:_playButton];

	_progressContainer = [[UIView alloc] initWithFrame:_bottomBar.bounds];
	_progressContainer.backgroundColor = [UIColor clearColor];
	_progressContainer.userInteractionEnabled = NO;
	_progressContainer.alpha = 0.0f;
	_progressContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleHeight;
	[_bottomBar addSubview:_progressContainer];

	_progressLabel = [[UILabel alloc] initWithFrame:
			CGRectMake((CGFloat)(int)((bounds.size.width - 220) / 2), 12, 220, 20)];
	_progressLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	_progressLabel.backgroundColor = [UIColor clearColor];
	_progressLabel.textColor = [UIColor whiteColor];
	_progressLabel.font = [UIFont systemFontOfSize:13];
	_progressLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
	_progressLabel.shadowOffset = CGSizeMake(0, -1);
	_progressLabel.textAlignment = NSTextAlignmentCenter;
	_progressLabel.clipsToBounds = NO;
	[_progressContainer addSubview:_progressLabel];

	_progressSpinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
	_progressSpinner.frame = CGRectMake(0, 3, 15, 15);
	_progressSpinner.hidesWhenStopped = YES;
	[_progressContainer addSubview:_progressSpinner];

	UIImage *actionIcon = [UIImage imageNamed:@"GalleryActionIcon.png"];
	_actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_actionButton.frame = CGRectMake(6, 2, 40, 40);
	_actionButton.exclusiveTouch = YES;
	_actionButton.showsTouchWhenHighlighted = YES;
	if (actionIcon)
		[_actionButton setBackgroundImage:actionIcon forState:UIControlStateNormal];
	else {
		_actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		[_actionButton setTitle:@"…" forState:UIControlStateNormal];
		[_actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	}
	_actionButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
	[_actionButton addTarget:self action:@selector(actionsTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[_bottomBar addSubview:_actionButton];

	UIImage *trashIcon = [UIImage imageNamed:@"GalleryTrashIcon.png"];
	_deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_deleteButton.frame = CGRectMake(bounds.size.width - 40 - 6, 2, 40, 40);
	_deleteButton.exclusiveTouch = YES;
	_deleteButton.showsTouchWhenHighlighted = YES;
	if (trashIcon)
		[_deleteButton setBackgroundImage:trashIcon forState:UIControlStateNormal];
	else {
		_deleteButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		[_deleteButton setTitle:@"Delete" forState:UIControlStateNormal];
		[_deleteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	}
	_deleteButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[_deleteButton addTarget:self action:@selector(deleteTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[_bottomBar addSubview:_deleteButton];

	_spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
	_spinner.center = CGPointMake(bounds.size.width / 2, bounds.size.height / 2);
	_spinner.hidesWhenStopped = YES;
	[self.view addSubview:_spinner];

	UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(handleDoubleTap:)];
	doubleTap.numberOfTapsRequired = 2;
	[self.view addGestureRecognizer:doubleTap];

	UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(handleSingleTap:)];
	[singleTap requireGestureRecognizerToFail:doubleTap];
	[self.view addGestureRecognizer:singleTap];

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(handlePan:)];
	pan.delegate = self;
	[self.view addGestureRecognizer:pan];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self layoutPagesPreservingIndex:_startIndex];
	[self updateChromeForCurrentItem];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	_statusBarWasHidden = [UIApplication sharedApplication].statusBarHidden;
	if (_statusBarWasHidden)
		[[UIApplication sharedApplication] setStatusBarHidden:NO
												withAnimation:UIStatusBarAnimationFade];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[[UIApplication sharedApplication] setStatusBarHidden:_statusBarWasHidden
											withAnimation:UIStatusBarAnimationFade];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutPagesPreservingIndex:_currentIndex];
}

- (BOOL)shouldAutorotate {
	return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
	return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation != UIInterfaceOrientationPortraitUpsideDown;
}

#pragma mark - paging

- (CGFloat)pageWidth {
	return self.view.bounds.size.width + TGMediaPageGap;
}

- (void)layoutPagesPreservingIndex:(NSInteger)index {
	CGRect bounds = self.view.bounds;
	if (bounds.size.width < 1)
		return;

	_pagingView.frame = CGRectMake(-TGMediaPageGap / 2.0f, 0,
								   bounds.size.width + TGMediaPageGap, bounds.size.height);
	_pagingView.contentSize = CGSizeMake([self pageWidth] * _items.count, bounds.size.height);

	CGFloat wanted = index * [self pageWidth];
	if (!_pagingView.isDragging && !_pagingView.isDecelerating &&
		fabs(_pagingView.contentOffset.x - wanted) > 0.5f)
		_pagingView.contentOffset = CGPointMake(wanted, 0);

	for (NSNumber *key in _visiblePages.allKeys){
		TGMediaPageView *page = _visiblePages[key];
		page.frame = CGRectMake([key integerValue] * [self pageWidth] + TGMediaPageGap / 2.0f, 0,
								bounds.size.width, bounds.size.height);
		[page layoutImage];
	}

	[self updateVisiblePages];
}

- (TGMediaPageView *)takePage {
	TGMediaPageView *page = [_pagePool lastObject];
	if (page){
		[_pagePool removeLastObject];
		return page;
	}
	return [[TGMediaPageView alloc] initWithFrame:self.view.bounds];
}

- (void)updateVisiblePages {
	if (_items.count == 0)
		return;

	NSInteger first = _currentIndex - 1;
	NSInteger last = _currentIndex + 1;
	if (first < 0)
		first = 0;
	if (last > (NSInteger)_items.count - 1)
		last = (NSInteger)_items.count - 1;

	for (NSNumber *key in _visiblePages.allKeys){
		NSInteger index = [key integerValue];
		if (index < first || index > last){
			TGMediaPageView *page = _visiblePages[key];
			[page setPageImage:nil];
			page.loadingFileId = nil;
			page.pageIndex = -1;
			[page removeFromSuperview];
			[_visiblePages removeObjectForKey:key];
			if (_pagePool.count < 3)
				[_pagePool addObject:page];
			[_imageCache removeObjectForKey:key];
			[_failedPages removeObject:key];
		}
	}

	for (NSInteger index = first; index <= last; index++){
		NSNumber *key = @(index);
		TGMediaPageView *page = _visiblePages[key];
		if (page)
			continue;

		page = [self takePage];
		page.pageIndex = index;
		page.frame = CGRectMake(index * [self pageWidth] + TGMediaPageGap / 2.0f, 0,
								self.view.bounds.size.width, self.view.bounds.size.height);
		[page resetZoom];
		[_pagingView addSubview:page];
		_visiblePages[key] = page;

		UIImage *cached = _imageCache[key];
		if (cached)
			[page setPageImage:cached];
		else
			[self loadImageForPageAtIndex:index];
	}
}

- (void)loadImageForPageAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_items.count)
		return;

	NSDictionary *item = _items[index];
	NSNumber *fileId = [item[@"isVideo"] boolValue] ? item[@"thumbId"] : item[@"fullId"];
	if (![fileId isKindOfClass:NSNumber.class])
		fileId = item[@"thumbId"];
	if (![fileId isKindOfClass:NSNumber.class])
		return;

	NSNumber *key = @(index);
	TGMediaPageView *page = _visiblePages[key];
	if (!page)
		return;
	if ([page.loadingFileId isEqual:fileId])
		return;
	page.loadingFileId = fileId;
	[_failedPages removeObject:key];
	[self updateLoadingChrome];

	NSNumber *thumbId = item[@"thumbId"];
	if ([thumbId isKindOfClass:NSNumber.class] && ![thumbId isEqual:fileId] &&
		!page.imageView.image)
		[self loadThumbnailForPageAtIndex:index fileId:thumbId];

	CGFloat maxSide = MAX(self.view.bounds.size.width, self.view.bounds.size.height)
			* [UIScreen mainScreen].scale;
	if (maxSide > 960.0f)
		maxSide = 960.0f;

	[[TGClient shared] startDownloadingFile:[fileId integerValue]
								   priority:(index == _currentIndex ? 32 : 8)
								 completion:nil];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
		typeof(self) me = weakSelf;
		if (!me)
			return;
		if (path.length == 0){
			TGMediaPageView *failedPage = me.visiblePages[key];
			if (failedPage && [failedPage.loadingFileId isEqual:fileId]){
				failedPage.loadingFileId = nil;
				[me.failedPages addObject:key];
				[me updateLoadingChrome];
			}
			return;
		}
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			UIImage *image = TGDecodeThumbnail(path, maxSide);
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongMe = weakSelf;
				if (!strongMe)
					return;
				TGMediaPageView *target = strongMe.visiblePages[key];
				if (!target || ![target.loadingFileId isEqual:fileId])
					return;
				if (!image){
					target.loadingFileId = nil;
					[strongMe.failedPages addObject:key];
					[strongMe updateLoadingChrome];
					return;
				}
				strongMe.imageCache[key] = image;
				[target setPageImage:image];
				[strongMe updateLoadingChrome];
			});
		});
	}];

	[self prefetchNeighboursOfIndex:index];
}

- (void)loadThumbnailForPageAtIndex:(NSInteger)index fileId:(NSNumber *)thumbId {
	NSNumber *key = @(index);
	CGFloat side = TGMediaTileSide * 4.0f;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[thumbId integerValue] completion:^(NSString *path){
		if (path.length == 0)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			UIImage *image = TGDecodeThumbnail(path, side);
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) me = weakSelf;
				if (!me)
					return;
				TGMediaPageView *target = me.visiblePages[key];
				if (!target || target.imageView.image || me.imageCache[key])
					return;
				[target setPageImage:image];
			});
		});
	}];
}

- (void)prefetchNeighboursOfIndex:(NSInteger)index {
	NSInteger neighbours[2] = {index - 1, index + 1};
	for (NSInteger i = 0; i < 2; i++){
		NSInteger at = neighbours[i];
		if (at < 0 || at >= (NSInteger)_items.count)
			continue;

		NSDictionary *item = _items[at];
		if ([item[@"isVideo"] boolValue])
			continue;

		NSNumber *fileId = item[@"fullId"];
		if (![fileId isKindOfClass:NSNumber.class] || [fileId integerValue] <= 0)
			continue;
		if ([_prefetchedFiles containsObject:fileId])
			continue;

		[_prefetchedFiles addObject:fileId];
		[[TGClient shared] startDownloadingFile:[fileId integerValue]
									   priority:1
									 completion:nil];
	}
}

- (void)updateLoadingChrome {
	if (!_playButton.enabled)
		return;

	NSNumber *key = @(_currentIndex);
	TGMediaPageView *page = _visiblePages[key];

	BOOL loading = page && !_imageCache[key] && page.loadingFileId
			&& ![_failedPages containsObject:key];

	if (loading){
		NSDictionary *item = [self currentItem];
		_progressLabel.text = [item[@"isVideo"] boolValue]
				? @"loading video..." : @"loading full image...";
		CGSize textSize = [_progressLabel.text sizeWithFont:_progressLabel.font];
		CGFloat textLeft = _progressLabel.frame.origin.x
				+ (_progressLabel.frame.size.width - textSize.width) / 2.0f;
		_progressSpinner.frame = CGRectMake((CGFloat)(int)(textLeft - 19.0f),
											_progressLabel.frame.origin.y + 3.0f, 15, 15);
		[_progressSpinner startAnimating];
	} else {
		[_progressSpinner stopAnimating];
	}

	[UIView animateWithDuration:0.2 animations:^{
		self.progressContainer.alpha = loading ? 1.0f : 0.0f;
		self.controlsContainer.alpha = loading ? 0.0f : 1.0f;
	}];
}

- (void)retryTapped {
	NSNumber *key = @(_currentIndex);
	[_failedPages removeObject:key];
	TGMediaPageView *page = _visiblePages[key];
	page.loadingFileId = nil;
	[self loadImageForPageAtIndex:_currentIndex];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != _pagingView || _dismissing)
		return;

	CGFloat width = [self pageWidth];
	if (width < 1)
		return;

	NSInteger index = (NSInteger)((scrollView.contentOffset.x + width / 2.0f) / width);
	if (index < 0)
		index = 0;
	if (index > (NSInteger)_items.count - 1)
		index = (NSInteger)_items.count - 1;

	if (index != _currentIndex){
		_currentIndex = index;
		[self updateVisiblePages];
		[self updateChromeForCurrentItem];
	}
}

#pragma mark - chrome

- (void)updateChromeForCurrentItem {
	if (_items.count == 0)
		return;

	_counterLabel.text = [NSString stringWithFormat:@"%ld of %lu",
			(long)(_currentIndex + 1), (unsigned long)_items.count];

	NSDictionary *item = _items[_currentIndex];
	NSString *caption = item[@"caption"];
	_authorLabel.text = [caption isKindOfClass:NSString.class] ? caption : @"";
	_dateLabel.text = TGMediaDayForDate([item[@"date"] integerValue]);

	BOOL isVideo = [item[@"isVideo"] boolValue];
	_playButton.hidden = !isVideo;
	_authorLabel.alpha = isVideo ? 0.0f : 1.0f;
	_dateLabel.alpha = isVideo ? 0.0f : 1.0f;
	_deleteButton.hidden = (self.chatId == 0 || [item[@"messageId"] longLongValue] == 0);

	[self updateLoadingChrome];
}

- (void)setChromeHidden:(BOOL)hidden animated:(BOOL)animated {
	_chromeHidden = hidden;
	CGFloat alpha = hidden ? 0.0f : 1.0f;
	[[UIApplication sharedApplication] setStatusBarHidden:hidden
											withAnimation:UIStatusBarAnimationFade];
	if (animated){
		[UIView animateWithDuration:(hidden ? 0.3 : 0.15) animations:^{
			self.topBar.alpha = alpha;
			self.bottomBar.alpha = alpha;
		}];
	} else {
		_topBar.alpha = alpha;
		_bottomBar.alpha = alpha;
	}
}

- (void)handleSingleTap:(UITapGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateRecognized)
		return;
	if ([_failedPages containsObject:@(_currentIndex)]){
		[self retryTapped];
		return;
	}
	[self setChromeHidden:!_chromeHidden animated:YES];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateRecognized)
		return;

	TGMediaPageView *page = _visiblePages[@(_currentIndex)];
	if (!page)
		return;

	if (page.zoomScale > page.minimumZoomScale + 0.01f){
		[page setZoomScale:page.minimumZoomScale animated:YES];
		return;
	}

	CGPoint point = [recognizer locationInView:page.imageView];
	CGFloat scale = page.maximumZoomScale;
	CGSize size = page.bounds.size;
	CGRect target = CGRectMake(point.x - (size.width / scale) / 2.0f,
							   point.y - (size.height / scale) / 2.0f,
							   size.width / scale, size.height / scale);
	[page zoomToRect:target animated:YES];
}

#pragma mark - drag to dismiss

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
	if (![recognizer isKindOfClass:[UIPanGestureRecognizer class]])
		return YES;

	TGMediaPageView *page = _visiblePages[@(_currentIndex)];
	if (page && page.zoomScale > 1.01f)
		return NO;
	if (_pagingView.isDragging || _pagingView.isDecelerating)
		return NO;

	CGPoint translation = [(UIPanGestureRecognizer *)recognizer translationInView:self.view];
	return fabs(translation.y) > fabs(translation.x);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
		shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
	return NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
	CGPoint translation = [recognizer translationInView:self.view];

	if (recognizer.state == UIGestureRecognizerStateBegan){
		_dismissing = YES;
		[self setChromeHidden:YES animated:YES];
		return;
	}

	if (recognizer.state == UIGestureRecognizerStateChanged){
		_pagingView.transform = CGAffineTransformMakeTranslation(0, translation.y);
		CGFloat progress = MIN(1.0f, fabs(translation.y) / 200.0f);
		self.view.backgroundColor = [UIColor colorWithWhite:0.0f alpha:1.0f - progress * 0.8f];
		return;
	}

	if (recognizer.state == UIGestureRecognizerStateEnded ||
		recognizer.state == UIGestureRecognizerStateCancelled){
		CGPoint velocity = [recognizer velocityInView:self.view];
		BOOL shouldClose = fabs(translation.y) > 100.0f || fabs(velocity.y) > 700.0f;

		if (shouldClose){
			CGFloat target = translation.y < 0 ? -self.view.bounds.size.height
											   : self.view.bounds.size.height;
			[UIView animateWithDuration:0.2 animations:^{
				self.pagingView.transform = CGAffineTransformMakeTranslation(0, target);
				self.view.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.0f];
			} completion:^(BOOL finished){
				[self closeTapped];
			}];
			return;
		}

		[UIView animateWithDuration:0.25 animations:^{
			self.pagingView.transform = CGAffineTransformIdentity;
			self.view.backgroundColor = [UIColor blackColor];
		} completion:^(BOOL finished){
			self.dismissing = NO;
			[self setChromeHidden:NO animated:YES];
		}];
	}
}

#pragma mark - actions

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showMessage:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
													message:message
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

- (NSDictionary *)currentItem {
	if (_currentIndex < 0 || _currentIndex >= (NSInteger)_items.count)
		return nil;
	return _items[_currentIndex];
}

- (void)actionsTapped {
	NSDictionary *item = [self currentItem];
	if (!item)
		return;

	NSMutableArray *actions = [NSMutableArray array];
	if (self.chatId != 0 && [item[@"messageId"] longLongValue] != 0)
		[actions addObject:@"forward"];
	[actions addObject:@"save"];
	self.sheetActions = actions;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
	for (NSString *action in actions){
		if ([action isEqualToString:@"save"])
			[sheet addButtonWithTitle:@"Save to Camera Roll"];
		else
			[sheet addButtonWithTitle:@"Forward via Telegram"];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)deleteTapped {
	NSDictionary *item = [self currentItem];
	if (!item)
		return;
	if (self.chatId == 0 || [item[@"messageId"] longLongValue] == 0)
		return;

	self.sheetActions = @[@"delete"];

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
	sheet.destructiveButtonIndex = [sheet addButtonWithTitle:[item[@"isVideo"] boolValue]
			? @"Delete Video" : @"Delete Photo"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.sheetActions.count)
		return;

	NSString *action = self.sheetActions[index];
	if ([action isEqualToString:@"save"])
		[self saveCurrentItem];
	else if ([action isEqualToString:@"forward"])
		[self forwardCurrentItem];
	else if ([action isEqualToString:@"delete"])
		[self deleteCurrentItem];
}

- (void)saveCurrentItem {
	NSDictionary *item = [self currentItem];
	NSNumber *fileId = item[@"fullId"];
	if (![fileId isKindOfClass:NSNumber.class] || [fileId integerValue] <= 0)
		return;

	BOOL isVideo = [item[@"isVideo"] boolValue];
	[_spinner startAnimating];
	_playButton.enabled = NO;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
		typeof(self) me = weakSelf;
		if (!me)
			return;
		[me.spinner stopAnimating];
		me.playButton.enabled = YES;
		if (path.length == 0){
			[me showMessage:@"Could not save"];
			return;
		}
		if (isVideo){
			if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path)){
				[me showMessage:@"This video cannot be saved."];
				return;
			}
			UISaveVideoAtPathToSavedPhotosAlbum(path, me,
					@selector(media:didFinishSavingWithError:contextInfo:), NULL);
			return;
		}
		UIImage *image = [UIImage imageWithContentsOfFile:path];
		if (!image){
			[me showMessage:@"Could not save"];
			return;
		}
		UIImageWriteToSavedPhotosAlbum(image, me,
				@selector(media:didFinishSavingWithError:contextInfo:), NULL);
	}];
}

- (void)media:(id)item didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
	[self showMessage:error ? @"Could not save" : @"Saved to Camera Roll"];
}

- (void)forwardCurrentItem {
	NSDictionary *item = [self currentItem];
	NSNumber *messageId = item[@"messageId"];
	if (![messageId isKindOfClass:NSNumber.class] || [messageId longLongValue] == 0)
		return;

	int64_t fromChat = self.chatId;
	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	picker.onPicked = ^(int64_t targetChatId){
		[[TGClient shared] forwardMessages:@[messageId]
								  fromChat:fromChat
									toChat:targetChatId
									thread:0
									asCopy:NO
							removeCaptions:NO
									silent:NO
								completion:nil];
	};

	UINavigationController *wrapper = [[UINavigationController alloc]
			initWithRootViewController:picker];
	[self presentViewController:wrapper animated:YES completion:nil];
}

- (void)deleteCurrentItem {
	NSDictionary *item = [self currentItem];
	NSNumber *messageId = item[@"messageId"];
	if (![messageId isKindOfClass:NSNumber.class] || [messageId longLongValue] == 0)
		return;

	int64_t identifier = [messageId longLongValue];
	NSInteger index = _currentIndex;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] deleteMessages:@[messageId]
							   inChat:self.chatId
						  forEveryone:NO
						   completion:^(BOOL ok){
		typeof(self) me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[me showMessage:@"Could not delete"];
			return;
		}
		if (me.onMessageDeleted)
			me.onMessageDeleted(identifier);
		[me removeItemAtIndex:index];
	}];
}

- (void)removeItemAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_items.count)
		return;

	[_items removeObjectAtIndex:index];
	if (_items.count == 0){
		[self closeTapped];
		return;
	}

	for (NSNumber *key in _visiblePages.allKeys){
		TGMediaPageView *page = _visiblePages[key];
		[page setPageImage:nil];
		page.loadingFileId = nil;
		page.pageIndex = -1;
		[page removeFromSuperview];
		[_visiblePages removeObjectForKey:key];
		if (_pagePool.count < 3)
			[_pagePool addObject:page];
	}
	[_imageCache removeAllObjects];
	[_failedPages removeAllObjects];

	if (_currentIndex > (NSInteger)_items.count - 1)
		_currentIndex = (NSInteger)_items.count - 1;

	[self layoutPagesPreservingIndex:_currentIndex];
	[self updateChromeForCurrentItem];
}

- (void)playTapped {
	if (_currentIndex < 0 || _currentIndex >= (NSInteger)_items.count)
		return;

	NSDictionary *item = _items[_currentIndex];
	NSNumber *fileId = item[@"fullId"];
	if (![fileId isKindOfClass:NSNumber.class])
		return;

	[_spinner startAnimating];
	_playButton.enabled = NO;
	[[TGClient shared] startDownloadingFile:[fileId integerValue]
								   priority:32
								 completion:nil];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
		typeof(self) me = weakSelf;
		if (!me)
			return;
		[me.spinner stopAnimating];
		me.playButton.enabled = YES;
		if (path.length == 0){
			[me showMessage:@"Could not download"];
			return;
		}
		MPMoviePlayerViewController *player = [[MPMoviePlayerViewController alloc]
				initWithContentURL:[NSURL fileURLWithPath:path]];
		[me presentMoviePlayerViewControllerAnimated:player];
	}];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	for (NSNumber *key in _imageCache.allKeys){
		if ([key integerValue] != _currentIndex)
			[_imageCache removeObjectForKey:key];
	}
}

- (void)dealloc {
	_pagingView.delegate = nil;
	for (NSNumber *key in _visiblePages.allKeys)
		[(TGMediaPageView *)_visiblePages[key] setDelegate:nil];
	for (TGMediaPageView *page in _pagePool)
		page.delegate = nil;
}

@end

#pragma mark - shared media

@interface TGMediaViewController ()
		<TGMediaGridCellDelegate, UIDocumentInteractionControllerDelegate>

@property (nonatomic, assign) NSInteger scope;
@property (nonatomic, assign) NSInteger loadToken;
@property (nonatomic, strong) UIView *scopeBar;
@property (nonatomic, strong) NSMutableArray *scopeButtons;
@property (nonatomic, strong) UILabel *dateIndicator;
@property (nonatomic, strong) UIDocumentInteractionController *documentController;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) TGViewRecycler *recycler;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, assign) NSInteger itemsPerRow;
@property (nonatomic, assign) int64_t lastMessageId;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL canLoadMore;
@property (nonatomic, assign) BOOL loadedOnce;

@property (nonatomic, strong) UIControl *banner;
@property (nonatomic, strong) UILabel *bannerTitle;
@property (nonatomic, strong) UILabel *bannerDetail;
@property (nonatomic, assign) BOOL bannerVisible;

@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIImageView *emptyImageView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) BOOL emptyVisible;

@end

@implementation TGMediaViewController

- (instancetype)initWithChatId:(int64_t)chatId {
	self = [super init];
	if (self){
		_chatId = chatId;
	}
	return self;
}

- (UIColor *)backgroundColourForScope:(NSInteger)scope {
	return TGMediaScopeIsGrid(scope)
			? [UIColor whiteColor]
			: [[TGTheme shared] listBackgroundColour];
}

- (void)loadView {
	[super loadView];

	self.title = @"Media";
	self.view.backgroundColor = [self backgroundColourForScope:_scope];

	_items = [[NSMutableArray alloc] init];
	_recycler = [[TGViewRecycler alloc] init];
	_canLoadMore = YES;
	_itemsPerRow = [self itemsPerRowForWidth:self.view.bounds.size.width];

	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds
											  style:UITableViewStylePlain];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	_tableView.backgroundColor = [self backgroundColourForScope:_scope];
	_tableView.contentInset = UIEdgeInsetsMake(0, 0, 4, 0);
	_tableView.scrollIndicatorInsets = UIEdgeInsetsZero;
	_tableView.rowHeight = TGMediaRowHeight;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	[self.view addSubview:_tableView];

	_scopeBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, TGMediaScopeHeight)];
	_scopeBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_scopeBar.clipsToBounds = YES;
	_scopeBar.backgroundColor = [TGTheme shared].isFlat
			? [[TGTheme shared] listBackgroundColour]
			: [UIColor colorWithRed:0xc3 / 255.0f green:0xcb / 255.0f
								blue:0xd4 / 255.0f alpha:1.0f];
	[self.view addSubview:_scopeBar];

	_scopeButtons = [NSMutableArray array];
	NSArray *scopeTitles = TGMediaScopeTitles();
	for (NSUInteger i = 0; i < scopeTitles.count; i++){
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.tag = (NSInteger)i;
		button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
		[button setTitle:scopeTitles[i] forState:UIControlStateNormal];
		[self styleScopeButton:button selected:(i == 0)];
		[button addTarget:self action:@selector(scopeTapped:)
		 forControlEvents:UIControlEventTouchDown];
		[_scopeBar addSubview:button];
		[_scopeButtons addObject:button];
	}

	UIView *scopeLine = [[UIView alloc] initWithFrame:
			CGRectMake(0, TGMediaScopeHeight - 1, self.view.bounds.size.width, 1)];
	scopeLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	scopeLine.backgroundColor = [[TGTheme shared] separatorColour];
	[_scopeBar addSubview:scopeLine];

	_banner = [[UIControl alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, TGMediaBannerHeight)];
	_banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_banner.backgroundColor = [[TGTheme shared] barColour];
	_banner.hidden = YES;
	[_banner addTarget:self action:@selector(bannerTapped)
	  forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_banner];

	_bannerTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, 4, 200, 20)];
	_bannerTitle.backgroundColor = [UIColor clearColor];
	_bannerTitle.font = [UIFont boldSystemFontOfSize:14];
	_bannerTitle.textColor = [[TGTheme shared] primaryTextColour];
	_bannerTitle.text = @"Downloads";
	[_banner addSubview:_bannerTitle];

	_bannerDetail = [[UILabel alloc] initWithFrame:CGRectMake(12, 22, 260, 18)];
	_bannerDetail.backgroundColor = [UIColor clearColor];
	_bannerDetail.font = [UIFont systemFontOfSize:12];
	_bannerDetail.textColor = [[TGTheme shared] secondaryTextColour];
	[_banner addSubview:_bannerDetail];

	UIView *bannerLine = [[UIView alloc] initWithFrame:
			CGRectMake(0, TGMediaBannerHeight - 1, self.view.bounds.size.width, 1)];
	bannerLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	bannerLine.backgroundColor = [[TGTheme shared] separatorColour];
	[_banner addSubview:bannerLine];

	_spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	_spinner.center = CGPointMake(self.view.bounds.size.width / 2,
								  self.view.bounds.size.height / 2 - 40);
	_spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin
			| UIViewAutoresizingFlexibleBottomMargin;
	_spinner.hidesWhenStopped = YES;
	[self.view addSubview:_spinner];

	UIImage *blank = [UIImage imageNamed:@"PhotosBlankPlaceholder.png"];
	_emptyImageView = [[UIImageView alloc] initWithImage:blank];

	_emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_emptyLabel.backgroundColor = [UIColor clearColor];
	_emptyLabel.textAlignment = NSTextAlignmentCenter;
	_emptyLabel.font = [UIFont boldSystemFontOfSize:17];
	_emptyLabel.textColor = [UIColor colorWithRed:0x80 / 255.0f green:0x88 / 255.0f
											 blue:0x95 / 255.0f alpha:1.0f];
	_emptyLabel.text = TGMediaEmptyTextForScope(_scope);
	[_emptyLabel sizeToFit];

	_emptyView = [[UIView alloc] initWithFrame:CGRectZero];
	_emptyView.backgroundColor = [UIColor clearColor];
	_emptyView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin
			| UIViewAutoresizingFlexibleBottomMargin;
	[_emptyView addSubview:_emptyImageView];
	[_emptyView addSubview:_emptyLabel];
	_emptyImageView.hidden = !TGMediaScopeIsGrid(_scope);
	_emptyView.alpha = 0.0f;
	[self.view insertSubview:_emptyView belowSubview:_tableView];
	[self layoutEmptyView];

	_dateIndicator = [[UILabel alloc] initWithFrame:
			CGRectMake(self.view.bounds.size.width - 140, TGMediaScopeHeight + 8, 128, 22)];
	_dateIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	_dateIndicator.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.62f];
	_dateIndicator.textColor = [UIColor whiteColor];
	_dateIndicator.font = [UIFont boldSystemFontOfSize:12];
	_dateIndicator.textAlignment = NSTextAlignmentCenter;
	_dateIndicator.layer.cornerRadius = 4.0f;
	_dateIndicator.clipsToBounds = YES;
	_dateIndicator.alpha = 0.0f;
	[self.view addSubview:_dateIndicator];
}

- (void)layoutEmptyView {
	CGRect bounds = self.view.bounds;
	UIImage *blank = _emptyImageView.hidden ? nil : _emptyImageView.image;
	CGFloat imageHeight = blank ? blank.size.height : 0.0f;
	CGFloat imageWidth = blank ? blank.size.width : 0.0f;
	CGFloat gap = imageHeight > 0.0f ? 12.0f : 0.0f;
	CGFloat width = MAX(imageWidth, _emptyLabel.frame.size.width);
	CGFloat height = imageHeight + gap + _emptyLabel.frame.size.height;

	_emptyView.frame = CGRectIntegral(CGRectMake((bounds.size.width - width) / 2.0f,
												 (bounds.size.height - height) / 2.0f - 18.0f,
												 width, height));
	_emptyImageView.frame = CGRectIntegral(CGRectMake((width - imageWidth) / 2.0f, 0,
													  imageWidth, imageHeight));
	_emptyLabel.frame = CGRectIntegral(CGRectMake(
			(width - _emptyLabel.frame.size.width) / 2.0f, imageHeight + gap,
			_emptyLabel.frame.size.width, _emptyLabel.frame.size.height));
}

- (void)setEmptyVisible:(BOOL)visible animated:(BOOL)animated {
	if (_emptyVisible == visible)
		return;
	_emptyVisible = visible;
	[self layoutEmptyView];

	void (^apply)(void) = ^{
		self.emptyView.alpha = visible ? 1.0f : 0.0f;
		self.tableView.alpha = visible ? 0.0f : 1.0f;
	};
	if (animated)
		[UIView animateWithDuration:0.2 animations:apply];
	else
		apply();
}

- (void)styleScopeButton:(UIButton *)button selected:(BOOL)selected {
	UIImage *plate = [UIImage imageNamed:selected
			? @"SearchBarScopeButton_Highlighted.png" : @"SearchBarScopeButton.png"];
	if (plate){
		plate = [plate stretchableImageWithLeftCapWidth:(int)(plate.size.width / 2)
										   topCapHeight:0];
		[button setBackgroundImage:plate forState:UIControlStateNormal];
		button.backgroundColor = [UIColor clearColor];
	} else {
		button.backgroundColor = selected
				? [[TGTheme shared] accentColour]
				: [UIColor clearColor];
	}

	if (selected){
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	} else {
		[button setTitleColor:([TGTheme shared].isFlat
				? [[TGTheme shared] secondaryTextColour]
				: [UIColor colorWithRed:0x5c / 255.0f green:0x70 / 255.0f
									blue:0x8b / 255.0f alpha:1.0f])
					 forState:UIControlStateNormal];
	}
}

- (void)layoutScopeButtons {
	CGFloat width = self.view.bounds.size.width;
	NSUInteger count = _scopeButtons.count;
	if (width < 1 || count == 0)
		return;

	CGFloat available = width - 12;
	CGFloat each = (CGFloat)(int)(available / count);
	for (NSUInteger i = 0; i < count; i++){
		UIButton *button = _scopeButtons[i];
		CGFloat buttonWidth = (i == count - 1) ? (available - each * (count - 1)) : each;
		button.frame = CGRectMake(6 + each * i, 3, buttonWidth, 30);
	}
}

- (void)scopeTapped:(UIButton *)button {
	if (button.tag == _scope)
		return;

	_scope = button.tag;
	_loadToken++;
	for (UIButton *other in _scopeButtons)
		[self styleScopeButton:other selected:(other.tag == _scope)];

	[_items removeAllObjects];
	_lastMessageId = 0;
	_canLoadMore = YES;
	_loadedOnce = NO;
	_loading = NO;
	[self setEmptyVisible:NO animated:NO];
	_emptyLabel.text = TGMediaEmptyTextForScope(_scope);
	[_emptyLabel sizeToFit];
	_emptyImageView.hidden = !TGMediaScopeIsGrid(_scope);
	[self layoutEmptyView];
	self.view.backgroundColor = [self backgroundColourForScope:_scope];
	_tableView.backgroundColor = [self backgroundColourForScope:_scope];
	_dateIndicator.alpha = 0.0f;
	[_recycler removeAllViews];
	_tableView.rowHeight = TGMediaScopeIsGrid(_scope)
			? TGMediaRowHeight : TGMediaListRowHeight;
	_tableView.separatorStyle = TGMediaScopeIsGrid(_scope)
			? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
	_tableView.separatorColor = [[TGTheme shared] separatorColour];
	[_tableView reloadData];
	[_tableView setContentOffset:CGPointZero animated:NO];
	[self loadNextPage];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	[self loadNextPage];
	[self refreshDownloadsBanner];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.backgroundColor = [self backgroundColourForScope:_scope];
	[self refreshDownloadsBanner];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGFloat top = _bannerVisible ? TGMediaBannerHeight : 0.0f;
	CGRect bounds = self.view.bounds;
	_banner.frame = CGRectMake(0, 0, bounds.size.width, TGMediaBannerHeight);
	_scopeBar.frame = CGRectMake(0, top, bounds.size.width, TGMediaScopeHeight);
	[self layoutScopeButtons];
	top += TGMediaScopeHeight;
	_tableView.frame = CGRectMake(0, top, bounds.size.width, bounds.size.height - top);
	[self layoutEmptyView];
	_dateIndicator.frame = CGRectMake(bounds.size.width - 140, top + 8, 128, 22);

	NSInteger perRow = [self itemsPerRowForWidth:bounds.size.width];
	if (perRow != _itemsPerRow){
		_itemsPerRow = perRow;
		[_tableView reloadData];
	}
}

- (NSInteger)itemsPerRowForWidth:(CGFloat)width {
	NSInteger perRow = (NSInteger)(width / (TGMediaTileSide + TGMediaTileSpacing));
	return perRow < 1 ? 1 : perRow;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation != UIInterfaceOrientationPortraitUpsideDown;
}

#pragma mark - loading

- (void)loadNextPage {
	if (_loading || !_canLoadMore || self.chatId == 0)
		return;

	_loading = YES;
	if (!_loadedOnce)
		[_spinner startAnimating];

	NSInteger token = _loadToken;
	NSInteger scope = _scope;

	__weak typeof(self) weakSelf = self;
	NSDictionary *request = @{
		@"@type"           : @"searchChatMessages",
		@"chat_id"         : @(self.chatId),
		@"query"           : @"",
		@"from_message_id" : @(_lastMessageId),
		@"offset"          : @(0),
		@"limit"           : @(TGMediaPageSize),
		@"filter"          : @{@"@type" : TGMediaFilterForScope(scope)},
	};

	[[TGClient shared] request:request completion:^(NSDictionary *result){
		typeof(self) me = weakSelf;
		if (!me || me.loadToken != token)
			return;

		me.loading = NO;
		me.loadedOnce = YES;
		[me.spinner stopAnimating];

		NSArray *messages = result[@"messages"];
		if (![messages isKindOfClass:NSArray.class] || messages.count == 0){
			me.canLoadMore = NO;
			[me setEmptyVisible:(me.items.count == 0) animated:YES];
			[me.tableView reloadData];
			return;
		}

		NSInteger added = 0;
		for (NSDictionary *message in messages){
			if (![message isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *item = TGMediaScopeIsGrid(scope)
					? TGMediaItemFromMessage(message)
					: TGMediaListItemFromMessage(message, scope);
			if (item){
				[me.items addObject:item];
				added++;
			}
			int64_t identifier = [message[@"id"] longLongValue];
			if (identifier != 0)
				me.lastMessageId = identifier;
		}

		if (messages.count < (NSUInteger)TGMediaPageSize)
			me.canLoadMore = NO;

		[me setEmptyVisible:(me.items.count == 0 && !me.canLoadMore) animated:YES];
		[me.tableView reloadData];

		if (added == 0 && me.canLoadMore)
			[me loadNextPage];
	}];
}

#pragma mark - downloads banner

- (void)refreshDownloadsBanner {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchDownloadsWithQuery:@""
									 onlyActive:NO
								  onlyCompleted:NO
										 offset:nil
										  limit:1
									 completion:^(NSDictionary *page){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;

		NSInteger active = [page[@"activeCount"] integerValue];
		NSInteger paused = [page[@"pausedCount"] integerValue];
		NSInteger completed = [page[@"completedCount"] integerValue];
		NSInteger total = active + paused + completed;

		if (total == 0){
			me.bannerVisible = NO;
			me.banner.hidden = YES;
			[me.view setNeedsLayout];
			return;
		}

		NSMutableArray *parts = [NSMutableArray array];
		if (active > 0)
			[parts addObject:[NSString stringWithFormat:@"%ld downloading", (long)active]];
		if (paused > 0)
			[parts addObject:[NSString stringWithFormat:@"%ld paused", (long)paused]];
		if (completed > 0)
			[parts addObject:[NSString stringWithFormat:@"%ld ready", (long)completed]];

		me.bannerDetail.text = [parts componentsJoinedByString:@", "];
		me.bannerVisible = YES;
		me.banner.hidden = NO;
		[me.view setNeedsLayout];
	}];
}

- (void)bannerTapped {
	TGDownloadsViewController *downloads = [[TGDownloadsViewController alloc] init];
	if (self.navigationController)
		[self.navigationController pushViewController:downloads animated:YES];
}

#pragma mark - table

- (NSInteger)numberOfRowsForItems {
	if (!TGMediaScopeIsGrid(_scope))
		return (NSInteger)_items.count;
	NSInteger perRow = _itemsPerRow < 1 ? 1 : _itemsPerRow;
	return ((NSInteger)_items.count + perRow - 1) / perRow;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSInteger rows = [self numberOfRowsForItems];
	return _canLoadMore ? rows + 1 : rows;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= [self numberOfRowsForItems])
		return 50.0f;
	return TGMediaScopeIsGrid(_scope) ? TGMediaRowHeight : TGMediaListRowHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= [self numberOfRowsForItems]){
		static NSString *loadingIdentifier = @"TGMediaLoading";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:loadingIdentifier];
		if (!cell){
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:loadingIdentifier];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.backgroundColor = [UIColor clearColor];
			UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
					initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
			spinner.tag = 401;
			spinner.frame = CGRectMake(
					(CGFloat)(int)((tableView.bounds.size.width
							- spinner.frame.size.width) / 2), 14,
					spinner.frame.size.width, spinner.frame.size.height);
			spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
					| UIViewAutoresizingFlexibleRightMargin;
			[cell.contentView addSubview:spinner];
		}
		UIActivityIndicatorView *spinner = (UIActivityIndicatorView *)[cell.contentView viewWithTag:401];
		[spinner startAnimating];
		return cell;
	}

	if (!TGMediaScopeIsGrid(_scope)){
		static NSString *listIdentifier = @"TGMediaList";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:listIdentifier];
		if (!cell){
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
										  reuseIdentifier:listIdentifier];
			cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
			cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
		}
		[[TGTheme shared] styleCell:cell];
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		cell.accessoryType = UITableViewCellAccessoryNone;

		if (indexPath.row < (NSInteger)_items.count){
			NSDictionary *item = _items[indexPath.row];
			cell.textLabel.text = item[@"title"];
			cell.detailTextLabel.text = item[@"detail"];
		}
		return cell;
	}

	static NSString *gridIdentifier = @"TGMediaGrid";
	TGMediaGridCell *cell = (TGMediaGridCell *)[tableView dequeueReusableCellWithIdentifier:gridIdentifier];
	if (!cell){
		cell = [[TGMediaGridCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:gridIdentifier];
	}
	cell.recycler = _recycler;
	cell.gridDelegate = self;

	NSInteger perRow = _itemsPerRow < 1 ? 1 : _itemsPerRow;
	NSInteger base = indexPath.row * perRow;
	NSInteger end = MIN(base + perRow, (NSInteger)_items.count);
	NSArray *slice = base < end
			? [_items subarrayWithRange:NSMakeRange(base, end - base)] : @[];

	[cell configureWithItems:slice baseIndex:base];
	return cell;
}

- (void)tableView:(UITableView *)tableView
	willDisplayCell:(UITableViewCell *)cell
  forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (!_canLoadMore || _loading)
		return;
	if (indexPath.row + 4 >= [self numberOfRowsForItems])
		[self loadNextPage];
}

- (void)tableView:(UITableView *)tableView
	didEndDisplayingCell:(UITableViewCell *)cell
	   forRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([cell isKindOfClass:[TGMediaGridCell class]])
		[(TGMediaGridCell *)cell releaseTiles];
}

- (void)gridCell:(TGMediaGridCell *)cell tappedItemAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_items.count)
		return;

	TGMediaFullscreenController *viewer = [[TGMediaFullscreenController alloc]
			initWithItems:[_items copy] index:index];
	viewer.chatId = self.chatId;

	__weak typeof(self) weakSelf = self;
	viewer.onMessageDeleted = ^(int64_t messageId){
		[weakSelf removeItemWithMessageId:messageId];
	};

	[self presentViewController:viewer animated:YES completion:nil];
}

- (void)removeItemWithMessageId:(int64_t)messageId {
	for (NSInteger i = 0; i < (NSInteger)_items.count; i++){
		if ([_items[i][@"messageId"] longLongValue] != messageId)
			continue;
		[_items removeObjectAtIndex:i];
		[_tableView reloadData];
		[self setEmptyVisible:(_items.count == 0 && !_canLoadMore) animated:YES];
		return;
	}
}

#pragma mark - list rows

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (TGMediaScopeIsGrid(_scope) || indexPath.row >= (NSInteger)_items.count)
		return;

	NSDictionary *item = _items[indexPath.row];

	if (_scope == TGMediaScopeLinks){
		NSString *url = item[@"url"];
		if (![url isKindOfClass:NSString.class] || url.length == 0)
			return;
		NSURL *target = [NSURL URLWithString:url];
		if (!target.scheme.length)
			target = [NSURL URLWithString:[@"http://" stringByAppendingString:url]];
		if (target)
			[[UIApplication sharedApplication] openURL:target];
		return;
	}

	NSInteger fileId = [item[@"fileId"] integerValue];
	if (fileId <= 0)
		return;

	[_spinner startAnimating];
	[[TGClient shared] startDownloadingFile:fileId priority:32 completion:nil];

	BOOL isMusic = (_scope == TGMediaScopeMusic);
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId completion:^(NSString *path){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;
		[me.spinner stopAnimating];
		if (path.length == 0){
			[me showAlertMessage:@"Could not download"];
			return;
		}
		if (isMusic){
			MPMoviePlayerViewController *player = [[MPMoviePlayerViewController alloc]
					initWithContentURL:[NSURL fileURLWithPath:path]];
			[me presentMoviePlayerViewControllerAnimated:player];
			return;
		}
		[me previewFileAtPath:path];
	}];
}

- (void)showAlertMessage:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
													message:message
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

- (void)previewFileAtPath:(NSString *)path {
	self.documentController = [UIDocumentInteractionController
			interactionControllerWithURL:[NSURL fileURLWithPath:path]];
	self.documentController.delegate = self;
	if ([self.documentController presentPreviewAnimated:YES])
		return;
	[self.documentController presentOpenInMenuFromRect:self.view.bounds
												inView:self.view
											  animated:YES];
}

- (UIViewController *)documentInteractionControllerViewControllerForPreview:
		(UIDocumentInteractionController *)controller {
	return self;
}

#pragma mark - fast scroll date

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != _tableView || _items.count == 0)
		return;
	if (!scrollView.isDragging && !scrollView.isDecelerating)
		return;

	NSArray *visible = [_tableView indexPathsForVisibleRows];
	if (visible.count == 0)
		return;

	NSIndexPath *top = visible[0];
	NSInteger perRow = TGMediaScopeIsGrid(_scope)
			? (_itemsPerRow < 1 ? 1 : _itemsPerRow) : 1;
	NSInteger index = top.row * perRow;
	if (index >= (NSInteger)_items.count)
		index = (NSInteger)_items.count - 1;

	NSString *month = TGMediaMonthForDate([_items[index][@"date"] integerValue]);
	if (month.length == 0)
		return;

	_dateIndicator.text = month;
	if (_dateIndicator.alpha < 1.0f){
		[UIView animateWithDuration:0.15 animations:^{
			self.dateIndicator.alpha = 1.0f;
		}];
	}
}

- (void)hideDateIndicator {
	if (_dateIndicator.alpha == 0.0f)
		return;
	[UIView animateWithDuration:0.25 animations:^{
		self.dateIndicator.alpha = 0.0f;
	}];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	[self hideDateIndicator];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	if (!decelerate)
		[self hideDateIndicator];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	[_recycler removeAllViews];
}

- (void)dealloc {
	_tableView.delegate = nil;
	_tableView.dataSource = nil;
	[_recycler removeAllViews];
}

@end

#pragma mark - downloads

@interface TGDownloadsRowCell : UITableViewCell

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIProgressView *progressView;

@end

@implementation TGDownloadsRowCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self){
		_nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_nameLabel.backgroundColor = [UIColor clearColor];
		_nameLabel.font = [UIFont boldSystemFontOfSize:15];
		_nameLabel.textColor = [[TGTheme shared] primaryTextColour];
		[self.contentView addSubview:_nameLabel];

		_detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_detailLabel.backgroundColor = [UIColor clearColor];
		_detailLabel.font = [UIFont systemFontOfSize:12];
		_detailLabel.textColor = [[TGTheme shared] secondaryTextColour];
		[self.contentView addSubview:_detailLabel];

		_progressView = [[UIProgressView alloc]
				initWithProgressViewStyle:UIProgressViewStyleDefault];
		_progressView.progressTintColor = [[TGTheme shared] accentColour];
		[self.contentView addSubview:_progressView];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat width = self.contentView.bounds.size.width;
	_nameLabel.frame = CGRectMake(12, 6, width - 24, 19);
	_progressView.frame = CGRectMake(12, 30, width - 24, 9);
	_detailLabel.frame = CGRectMake(12, 40, width - 24, 16);
}

@end

@interface TGDownloadsViewController ()

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *active;
@property (nonatomic, strong) NSMutableArray *completed;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) void (^savedProgressBlock)(NSInteger fileId, float progress);
@property (nonatomic, assign) BOOL progressHooked;
@property (nonatomic, strong) NSTimer *refreshTimer;

@end

@implementation TGDownloadsViewController

- (void)loadView {
	[super loadView];

	self.title = @"Downloads";
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	_active = [[NSMutableArray alloc] init];
	_completed = [[NSMutableArray alloc] init];

	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds
											  style:UITableViewStylePlain];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	_tableView.separatorColor = [[TGTheme shared] separatorColour];
	_tableView.rowHeight = 62.0f;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	[self.view addSubview:_tableView];

	_emptyLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, self.view.bounds.size.height / 2 - 60,
					   self.view.bounds.size.width, 20)];
	_emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_emptyLabel.backgroundColor = [UIColor clearColor];
	_emptyLabel.textAlignment = NSTextAlignmentCenter;
	_emptyLabel.font = [UIFont systemFontOfSize:15];
	_emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
	_emptyLabel.text = @"Nothing downloading";
	_emptyLabel.hidden = YES;
	[self.view addSubview:_emptyLabel];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Clear"
					style:UIBarButtonItemStylePlain
				   target:self
				   action:@selector(clearTapped)];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self reload];
	[self installProgressHook];

	self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
														 target:self
													   selector:@selector(reload)
													   userInfo:nil
														repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;
	[self removeProgressHook];
}

#pragma mark - progress

- (void)installProgressHook {
	if (self.progressHooked)
		return;

	TGClient *client = [TGClient shared];
	void (^previous)(NSInteger, float) = client.onFileProgress;
	self.savedProgressBlock = previous;
	self.progressHooked = YES;

	__weak typeof(self) weakSelf = self;
	client.onFileProgress = ^(NSInteger fileId, float progress){
		if (previous)
			previous(fileId, progress);
		[weakSelf applyProgress:progress toFile:fileId];
	};
}

- (void)removeProgressHook {
	if (!self.progressHooked)
		return;
	[TGClient shared].onFileProgress = self.savedProgressBlock;
	self.savedProgressBlock = nil;
	self.progressHooked = NO;
}

- (void)applyProgress:(float)progress toFile:(NSInteger)fileId {
	if (!self.isViewLoaded)
		return;

	for (NSInteger row = 0; row < (NSInteger)_active.count; row++){
		NSDictionary *entry = _active[row];
		if ([entry[@"fileId"] integerValue] != fileId)
			continue;

		NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
		TGDownloadsRowCell *cell = (TGDownloadsRowCell *)[_tableView cellForRowAtIndexPath:path];
		if ([cell isKindOfClass:[TGDownloadsRowCell class]]){
			[cell.progressView setProgress:progress animated:YES];
			long long total = [entry[@"file"][@"size"] longLongValue];
			if (total <= 0)
				total = [entry[@"file"][@"expectedSize"] longLongValue];
			cell.detailLabel.text = total > 0
					? [NSString stringWithFormat:@"%@ of %@",
							TGMediaFormatBytes((long long)(total * progress)),
							TGMediaFormatBytes(total)]
					: [NSString stringWithFormat:@"%d%%", (int)(progress * 100)];
		}
		return;
	}
}

#pragma mark - data

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchDownloadsWithQuery:@""
									 onlyActive:NO
								  onlyCompleted:NO
										 offset:nil
										  limit:100
									 completion:^(NSDictionary *page){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;

		NSArray *downloads = page[@"downloads"];
		if (![downloads isKindOfClass:NSArray.class])
			downloads = @[];

		[me.active removeAllObjects];
		[me.completed removeAllObjects];

		for (NSDictionary *entry in downloads){
			if ([entry[@"completeDate"] longLongValue] > 0 ||
				[entry[@"file"][@"isDownloaded"] boolValue])
				[me.completed addObject:entry];
			else
				[me.active addObject:entry];
		}

		me.emptyLabel.hidden = downloads.count != 0;
		[me.tableView reloadData];
	}];
}

- (void)clearTapped {
	[[TGClient shared] removeAllDownloadsOnlyActive:NO onlyCompleted:NO deleteFromCache:NO];
	[_active removeAllObjects];
	[_completed removeAllObjects];
	_emptyLabel.hidden = NO;
	[_tableView reloadData];
}

#pragma mark - table

- (NSArray *)entriesForSection:(NSInteger)section {
	return section == 0 ? _active : _completed;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[self entriesForSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if ([self entriesForSection:section].count == 0)
		return nil;
	return section == 0 ? @"Downloading" : @"Downloaded";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"TGDownloadRow";
	TGDownloadsRowCell *cell = (TGDownloadsRowCell *)
			[tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell){
		cell = [[TGDownloadsRowCell alloc] initWithStyle:UITableViewCellStyleDefault
										 reuseIdentifier:identifier];
	}
	[[TGTheme shared] styleCell:cell];

	NSArray *entries = [self entriesForSection:indexPath.section];
	if (indexPath.row >= (NSInteger)entries.count)
		return cell;

	NSDictionary *entry = entries[indexPath.row];
	NSDictionary *file = entry[@"file"];

	NSString *name = entry[@"fileName"];
	if (![name isKindOfClass:NSString.class] || name.length == 0)
		name = [NSString stringWithFormat:@"File %@", entry[@"fileId"] ?: @0];
	cell.nameLabel.text = name;

	long long total = [file[@"size"] longLongValue];
	if (total <= 0)
		total = [file[@"expectedSize"] longLongValue];
	long long got = [file[@"downloadedSize"] longLongValue];

	if (indexPath.section == 0){
		cell.progressView.hidden = NO;
		cell.progressView.progress = total > 0 ? (float)((double)got / (double)total) : 0.0f;
		BOOL paused = [entry[@"isPaused"] boolValue];
		cell.detailLabel.text = paused
				? [NSString stringWithFormat:@"Paused, %@ of %@",
						TGMediaFormatBytes(got), TGMediaFormatBytes(total)]
				: [NSString stringWithFormat:@"%@ of %@",
						TGMediaFormatBytes(got), TGMediaFormatBytes(total)];
	} else {
		cell.progressView.hidden = YES;
		cell.detailLabel.text = TGMediaFormatBytes(total > 0 ? total : got);
	}

	cell.selectionStyle = indexPath.section == 0
			? UITableViewCellSelectionStyleBlue : UITableViewCellSelectionStyleNone;
	[cell setNeedsLayout];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 0)
		return;

	NSArray *entries = [self entriesForSection:indexPath.section];
	if (indexPath.row >= (NSInteger)entries.count)
		return;

	NSDictionary *entry = entries[indexPath.row];
	NSInteger fileId = [entry[@"fileId"] integerValue];
	BOOL paused = [entry[@"isPaused"] boolValue];
	[[TGClient shared] setDownloadOfFile:fileId paused:!paused];
	[self reload];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;

	NSMutableArray *entries = indexPath.section == 0 ? _active : _completed;
	if (indexPath.row >= (NSInteger)entries.count)
		return;

	NSDictionary *entry = entries[indexPath.row];
	if (indexPath.section == 0)
		[[TGClient shared] cancelDownloadOfFile:[entry[@"fileId"] integerValue] onlyIfPending:NO];

	[entries removeObjectAtIndex:indexPath.row];
	[tableView deleteRowsAtIndexPaths:@[indexPath]
					 withRowAnimation:UITableViewRowAnimationFade];
	_emptyLabel.hidden = (_active.count + _completed.count) != 0;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation != UIInterfaceOrientationPortraitUpsideDown;
}

- (void)dealloc {
	[_refreshTimer invalidate];
	_tableView.delegate = nil;
	_tableView.dataSource = nil;
}

@end

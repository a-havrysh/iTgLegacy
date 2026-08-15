#import "TGMediaViewController.h"

#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

#import "TGClient.h"
#import "TGClient+Files.h"
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
static const CGFloat TGMediaPageGap     = 20.0f;

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

#pragma mark - tile

@interface TGMediaTileView : TGRemoteImageView

@property (nonatomic, strong) UIView *badgeBar;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UIImageView *playView;

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
	}
	return self;
}

- (void)buildBadge {
	if (_badgeBar)
		return;

	_badgeBar = [[UIView alloc] initWithFrame:CGRectMake(0, TGMediaTileSide - 19,
														 TGMediaTileSide, 19)];
	_badgeBar.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_badgeBar.userInteractionEnabled = NO;

	UIImage *play = [TGIcons play];
	_playView = [[UIImageView alloc] initWithImage:play];
	_playView.frame = CGRectMake(4, (int)((19 - MIN(11.0f, play.size.height)) / 2),
								 MIN(11.0f, play.size.width), MIN(11.0f, play.size.height));
	_playView.contentMode = UIViewContentModeScaleAspectFit;
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
		self.maximumZoomScale = 3.0f;
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
		<UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) NSArray *items;
@property (nonatomic, assign) NSInteger startIndex;
@property (nonatomic, assign) NSInteger currentIndex;

@property (nonatomic, strong) UIScrollView *pagingView;
@property (nonatomic, strong) NSMutableDictionary *visiblePages;
@property (nonatomic, strong) NSMutableArray *pagePool;
@property (nonatomic, strong) NSMutableDictionary *imageCache;

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, assign) BOOL chromeHidden;
@property (nonatomic, assign) BOOL dismissing;
@property (nonatomic, assign) BOOL statusBarWasHidden;

- (instancetype)initWithItems:(NSArray *)items index:(NSInteger)index;

@end

@implementation TGMediaFullscreenController

- (instancetype)initWithItems:(NSArray *)items index:(NSInteger)index {
	self = [super init];
	if (self){
		_items = items ?: @[];
		_startIndex = index;
		_currentIndex = index;
		_visiblePages = [[NSMutableDictionary alloc] init];
		_pagePool = [[NSMutableArray alloc] init];
		_imageCache = [[NSMutableDictionary alloc] init];
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
			CGRectMake(0, 0, bounds.size.width + TGMediaPageGap, bounds.size.height)];
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

	_topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, 44)];
	_topBar.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:_topBar];

	UIButton *done = [UIButton buttonWithType:UIButtonTypeCustom];
	done.frame = CGRectMake(bounds.size.width - 70, 0, 66, 44);
	done.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	done.titleLabel.font = [UIFont boldSystemFontOfSize:15];
	[done setTitle:@"Done" forState:UIControlStateNormal];
	[done setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[done addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
	[_topBar addSubview:done];

	_counterLabel = [[UILabel alloc] initWithFrame:CGRectMake(70, 0, bounds.size.width - 140, 44)];
	_counterLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_counterLabel.backgroundColor = [UIColor clearColor];
	_counterLabel.textColor = [UIColor whiteColor];
	_counterLabel.font = [UIFont boldSystemFontOfSize:15];
	_counterLabel.textAlignment = NSTextAlignmentCenter;
	[_topBar addSubview:_counterLabel];

	_bottomBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, bounds.size.height - 60, bounds.size.width, 60)];
	_bottomBar.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_bottomBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	[self.view addSubview:_bottomBar];

	_captionLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, bounds.size.width - 100, 60)];
	_captionLabel.backgroundColor = [UIColor clearColor];
	_captionLabel.textColor = [UIColor whiteColor];
	_captionLabel.font = [UIFont systemFontOfSize:13];
	_captionLabel.numberOfLines = 3;
	[_bottomBar addSubview:_captionLabel];

	_playButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_playButton.frame = CGRectMake(bounds.size.width - 80, 10, 70, 40);
	_playButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	_playButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
	[_playButton setTitle:@"Play" forState:UIControlStateNormal];
	[_playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[_playButton addTarget:self action:@selector(playTapped)
		  forControlEvents:UIControlEventTouchUpInside];
	[_bottomBar addSubview:_playButton];

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
	[[UIApplication sharedApplication] setStatusBarHidden:YES
											withAnimation:UIStatusBarAnimationFade];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (!_statusBarWasHidden)
		[[UIApplication sharedApplication] setStatusBarHidden:NO
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

	_pagingView.frame = CGRectMake(0, 0, bounds.size.width + TGMediaPageGap, bounds.size.height);
	_pagingView.contentSize = CGSizeMake([self pageWidth] * _items.count, bounds.size.height);

	CGFloat wanted = index * [self pageWidth];
	if (!_pagingView.isDragging && !_pagingView.isDecelerating &&
		fabs(_pagingView.contentOffset.x - wanted) > 0.5f)
		_pagingView.contentOffset = CGPointMake(wanted, 0);

	for (NSNumber *key in _visiblePages.allKeys){
		TGMediaPageView *page = _visiblePages[key];
		page.frame = CGRectMake([key integerValue] * [self pageWidth], 0,
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
		}
	}

	for (NSInteger index = first; index <= last; index++){
		NSNumber *key = @(index);
		TGMediaPageView *page = _visiblePages[key];
		if (page)
			continue;

		page = [self takePage];
		page.pageIndex = index;
		page.frame = CGRectMake(index * [self pageWidth], 0,
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

	CGFloat maxSide = MAX(self.view.bounds.size.width, self.view.bounds.size.height)
			* [UIScreen mainScreen].scale;
	if (maxSide > 960.0f)
		maxSide = 960.0f;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
		typeof(self) me = weakSelf;
		if (!me || path.length == 0)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			UIImage *image = TGDecodeThumbnail(path, maxSide);
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongMe = weakSelf;
				if (!strongMe)
					return;
				TGMediaPageView *target = strongMe.visiblePages[key];
				if (!target || ![target.loadingFileId isEqual:fileId])
					return;
				strongMe.imageCache[key] = image;
				[target setPageImage:image];
			});
		});
	}];
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
	_captionLabel.text = [caption isKindOfClass:NSString.class] ? caption : @"";

	BOOL isVideo = [item[@"isVideo"] boolValue];
	_playButton.hidden = !isVideo;
	if (isVideo)
		[_playButton setTitle:[NSString stringWithFormat:@"▶ %@",
				TGMediaFormatDuration([item[@"duration"] integerValue])]
					 forState:UIControlStateNormal];
}

- (void)setChromeHidden:(BOOL)hidden animated:(BOOL)animated {
	_chromeHidden = hidden;
	CGFloat alpha = hidden ? 0.0f : 1.0f;
	if (animated){
		[UIView animateWithDuration:0.2 animations:^{
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
	[self setChromeHidden:!_chromeHidden animated:YES];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateRecognized)
		return;

	TGMediaPageView *page = _visiblePages[@(_currentIndex)];
	if (!page)
		return;

	if (page.zoomScale > 1.01f){
		[page setZoomScale:1.0f animated:YES];
		return;
	}

	CGPoint point = [recognizer locationInView:page.imageView];
	CGFloat scale = 2.5f;
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

- (void)playTapped {
	if (_currentIndex < 0 || _currentIndex >= (NSInteger)_items.count)
		return;

	NSDictionary *item = _items[_currentIndex];
	NSNumber *fileId = item[@"fullId"];
	if (![fileId isKindOfClass:NSNumber.class])
		return;

	[_spinner startAnimating];
	_playButton.enabled = NO;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
		typeof(self) me = weakSelf;
		if (!me)
			return;
		[me.spinner stopAnimating];
		me.playButton.enabled = YES;
		if (path.length == 0)
			return;
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

@interface TGMediaViewController () <TGMediaGridCellDelegate>

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
@property (nonatomic, strong) UILabel *emptyLabel;

@end

@implementation TGMediaViewController

- (instancetype)initWithChatId:(int64_t)chatId {
	self = [super init];
	if (self){
		_chatId = chatId;
	}
	return self;
}

- (void)loadView {
	[super loadView];

	self.title = @"Shared Media";
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];

	_items = [[NSMutableArray alloc] init];
	_recycler = [[TGViewRecycler alloc] init];
	_canLoadMore = YES;
	_itemsPerRow = [self itemsPerRowForWidth:self.view.bounds.size.width];

	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds
											  style:UITableViewStylePlain];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	_tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	_tableView.rowHeight = TGMediaRowHeight;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	[self.view addSubview:_tableView];

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

	_emptyLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, self.view.bounds.size.height / 2 - 50,
					   self.view.bounds.size.width, 20)];
	_emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_emptyLabel.backgroundColor = [UIColor clearColor];
	_emptyLabel.textAlignment = NSTextAlignmentCenter;
	_emptyLabel.font = [UIFont systemFontOfSize:15];
	_emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
	_emptyLabel.text = @"No shared media";
	_emptyLabel.hidden = YES;
	[self.view addSubview:_emptyLabel];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	if (self.chatTitle.length)
		self.title = self.chatTitle;

	[self loadNextPage];
	[self refreshDownloadsBanner];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[self refreshDownloadsBanner];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGFloat top = _bannerVisible ? TGMediaBannerHeight : 0.0f;
	CGRect bounds = self.view.bounds;
	_banner.frame = CGRectMake(0, 0, bounds.size.width, TGMediaBannerHeight);
	_tableView.frame = CGRectMake(0, top, bounds.size.width, bounds.size.height - top);

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

	__weak typeof(self) weakSelf = self;
	NSDictionary *request = @{
		@"@type"           : @"searchChatMessages",
		@"chat_id"         : @(self.chatId),
		@"query"           : @"",
		@"from_message_id" : @(_lastMessageId),
		@"offset"          : @(0),
		@"limit"           : @(TGMediaPageSize),
		@"filter"          : @{@"@type" : @"searchMessagesFilterPhotoAndVideo"},
	};

	[[TGClient shared] request:request completion:^(NSDictionary *result){
		typeof(self) me = weakSelf;
		if (!me)
			return;

		me.loading = NO;
		me.loadedOnce = YES;
		[me.spinner stopAnimating];

		NSArray *messages = result[@"messages"];
		if (![messages isKindOfClass:NSArray.class] || messages.count == 0){
			me.canLoadMore = NO;
			me.emptyLabel.hidden = me.items.count != 0;
			[me.tableView reloadData];
			return;
		}

		NSInteger added = 0;
		for (NSDictionary *message in messages){
			NSDictionary *item = TGMediaItemFromMessage(message);
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

		me.emptyLabel.hidden = me.items.count != 0;
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
	NSInteger perRow = _itemsPerRow < 1 ? 1 : _itemsPerRow;
	return ((NSInteger)_items.count + perRow - 1) / perRow;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSInteger rows = [self numberOfRowsForItems];
	return _canLoadMore ? rows + 1 : rows;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.row < [self numberOfRowsForItems] ? TGMediaRowHeight : 50.0f;
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
			spinner.center = CGPointMake(tableView.bounds.size.width / 2, 25);
			spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
					| UIViewAutoresizingFlexibleRightMargin;
			[cell.contentView addSubview:spinner];
		}
		UIActivityIndicatorView *spinner = (UIActivityIndicatorView *)[cell.contentView viewWithTag:401];
		[spinner startAnimating];
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
	[self presentViewController:viewer animated:YES completion:nil];
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

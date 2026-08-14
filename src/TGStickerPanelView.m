#import "TGStickerPanelView.h"

#import "TGClient.h"
#import "TGClient+Stickers.h"
#import "TGTheme.h"
#import "TGViewRecycler.h"
#import "TGReusableView.h"
#import "UIImage+WebP.h"

static const CGFloat TGStickerPanelTabHeight = 30.0f;
static const CGFloat TGStickerPanelHeaderHeight = 25.0f;
static const CGFloat TGStickerPanelTileSide = 64.0f;
static const NSInteger TGStickerPanelImageCacheLimit = 180;

static const NSInteger TGStickerSectionRecent = 0;
static const NSInteger TGStickerSectionFavourite = 1;
static const NSInteger TGStickerSectionSet = 2;

@interface TGStickerTile : UIControl <TGReusableView>

@property (nonatomic, strong) NSString *reuseIdentifier;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *emojiLabel;
@property (nonatomic, strong) NSDictionary *sticker;
@property (nonatomic, assign) NSInteger sectionIndex;
@property (nonatomic, assign) NSInteger itemIndex;

@end

@implementation TGStickerTile

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self != nil){
		self.reuseIdentifier = @"stickerTile";
		self.opaque = NO;
		self.backgroundColor = [UIColor clearColor];
		self.exclusiveTouch = YES;

		_emojiLabel = [[UILabel alloc] initWithFrame:self.bounds];
		_emojiLabel.backgroundColor = [UIColor clearColor];
		_emojiLabel.textAlignment = UITextAlignmentCenter;
		_emojiLabel.font = [UIFont systemFontOfSize:32];
		_emojiLabel.userInteractionEnabled = NO;
		[self addSubview:_emojiLabel];

		_imageView = [[UIImageView alloc] initWithFrame:self.bounds];
		_imageView.contentMode = UIViewContentModeScaleAspectFit;
		_imageView.userInteractionEnabled = NO;
		[self addSubview:_imageView];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	_emojiLabel.frame = self.bounds;
	_imageView.frame = self.bounds;
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	self.alpha = highlighted ? 0.6f : 1.0f;
}

- (void)prepareForReuse {
	self.alpha = 1.0f;
	self.sticker = nil;
	self.imageView.image = nil;
	self.emojiLabel.text = @"";
}

- (void)prepareForRecycle:(TGViewRecycler *)recycler {
	self.sticker = nil;
	self.imageView.image = nil;
	self.emojiLabel.text = @"";
	[self removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	for (UIGestureRecognizer *recogniser in [self.gestureRecognizers copy])
		[self removeGestureRecognizer:recogniser];
}

@end

@interface TGStickerPanelView () <UIScrollViewDelegate>

@property (nonatomic, strong) UIScrollView *tabStrip;
@property (nonatomic, strong) UIScrollView *grid;
@property (nonatomic, strong) UIView *topSeparator;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *retryButton;

@property (nonatomic, strong) TGViewRecycler *recycler;
@property (nonatomic, strong) NSMutableArray *sections;
@property (nonatomic, strong) NSMutableDictionary *visibleTiles;
@property (nonatomic, strong) NSMutableArray *headerViews;
@property (nonatomic, strong) NSMutableArray *tabButtons;
@property (nonatomic, strong) NSMutableDictionary *imageCache;
@property (nonatomic, strong) NSMutableSet *pendingImages;
@property (nonatomic, strong) dispatch_queue_t decodeQueue;

@property (nonatomic, assign) NSInteger columns;
@property (nonatomic, assign) CGFloat gutter;
@property (nonatomic, assign) NSInteger selectedSection;
@property (nonatomic, assign) CGFloat laidOutWidth;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) NSInteger generation;

@end

@implementation TGStickerPanelView

+ (CGFloat)preferredHeightForLandscape:(BOOL)landscape {
	return landscape ? 194.0f : 216.0f;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self != nil){
		self.backgroundColor = [[TGTheme shared] listBackgroundColour];
		self.clipsToBounds = YES;

		_recycler = [[TGViewRecycler alloc] init];
		_sections = [[NSMutableArray alloc] init];
		_visibleTiles = [[NSMutableDictionary alloc] init];
		_headerViews = [[NSMutableArray alloc] init];
		_tabButtons = [[NSMutableArray alloc] init];
		_imageCache = [[NSMutableDictionary alloc] init];
		_pendingImages = [[NSMutableSet alloc] init];
		_decodeQueue = dispatch_queue_create("tg.stickerpanel.decode", NULL);
		_columns = 4;
		_gutter = 12.0f;
		_selectedSection = -1;

		_grid = [[UIScrollView alloc] initWithFrame:CGRectZero];
		_grid.delegate = self;
		_grid.showsVerticalScrollIndicator = YES;
		_grid.alwaysBounceVertical = YES;
		_grid.backgroundColor = [UIColor clearColor];
		[self addSubview:_grid];

		_tabStrip = [[UIScrollView alloc] initWithFrame:CGRectZero];
		_tabStrip.showsHorizontalScrollIndicator = NO;
		_tabStrip.backgroundColor = [UIColor clearColor];
		[self addSubview:_tabStrip];

		_topSeparator = [[UIView alloc] initWithFrame:CGRectZero];
		_topSeparator.backgroundColor = [[TGTheme shared] separatorColour];
		[self addSubview:_topSeparator];

		_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
				UIActivityIndicatorViewStyleGray];
		_spinner.hidesWhenStopped = YES;
		[self addSubview:_spinner];

		_statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_statusLabel.backgroundColor = [UIColor clearColor];
		_statusLabel.textAlignment = UITextAlignmentCenter;
		_statusLabel.font = [UIFont systemFontOfSize:14];
		_statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
		_statusLabel.numberOfLines = 2;
		_statusLabel.hidden = YES;
		[self addSubview:_statusLabel];

		_retryButton = [UIButton buttonWithType:UIButtonTypeCustom];
		UIImage *plate = [UIImage imageNamed:@"GroupedActionButton.png"];
		UIImage *platePressed = [UIImage imageNamed:@"GroupedActionButton_Highlighted.png"];
		[_retryButton setBackgroundImage:[plate stretchableImageWithLeftCapWidth:24 topCapHeight:0]
								forState:UIControlStateNormal];
		[_retryButton setBackgroundImage:[platePressed stretchableImageWithLeftCapWidth:24 topCapHeight:0]
								forState:UIControlStateHighlighted];
		[_retryButton setTitle:@"Try Again" forState:UIControlStateNormal];
		[_retryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		_retryButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		_retryButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
		[_retryButton setTitleShadowColor:[UIColor colorWithRed:0x0e / 255.0f green:0x28 / 255.0f
														   blue:0x4d / 255.0f alpha:0.4f]
								 forState:UIControlStateNormal];
		_retryButton.hidden = YES;
		[_retryButton addTarget:self action:@selector(reload)
			   forControlEvents:UIControlEventTouchUpInside];
		[self addSubview:_retryButton];

		[[NSNotificationCenter defaultCenter] addObserver:self
				selector:@selector(handleMemoryWarning)
					name:UIApplicationDidReceiveMemoryWarningNotification object:nil];

		[self reload];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	_grid.delegate = nil;
}

- (void)handleMemoryWarning {
	[self.imageCache removeAllObjects];
	[self.recycler removeAllViews];
}

#pragma mark - loading

- (void)reload {
	self.generation += 1;
	NSInteger generation = self.generation;

	[self.imageCache removeAllObjects];
	[self.pendingImages removeAllObjects];
	[self clearTiles];
	[self.sections removeAllObjects];
	self.selectedSection = -1;
	self.loading = YES;
	self.failed = NO;
	[self updateStatus];
	[self rebuildTabs];

	__block BOOL anyFailure = NO;
	__block NSInteger outstanding = 3;
	__block NSArray *recent = nil;
	__block NSArray *favourites = nil;
	__block NSArray *sets = nil;

	__weak TGStickerPanelView *weakSelf = self;
	void (^finish)(void) = ^{
		TGStickerPanelView *me = weakSelf;
		if (me == nil || me.generation != generation)
			return;
		outstanding -= 1;
		if (outstanding > 0)
			return;
		[me buildSectionsWithRecent:recent favourites:favourites sets:sets failed:anyFailure];
	};

	[[TGClient shared] recentStickersWithCompletion:^(NSArray *stickers){
		recent = stickers;
		if (stickers == nil)
			anyFailure = YES;
		finish();
	}];
	[[TGClient shared] favoriteStickersWithCompletion:^(NSArray *stickers){
		favourites = stickers;
		if (stickers == nil)
			anyFailure = YES;
		finish();
	}];
	[[TGClient shared] installedStickerSetsWithCompletion:^(NSArray *installed){
		sets = installed;
		if (installed == nil)
			anyFailure = YES;
		finish();
	}];
}

- (void)buildSectionsWithRecent:(NSArray *)recent
					 favourites:(NSArray *)favourites
						   sets:(NSArray *)sets
						 failed:(BOOL)failed {
	self.loading = NO;

	if (recent.count > 0){
		[self.sections addObject:[[NSMutableDictionary alloc] initWithObjectsAndKeys:
				@(TGStickerSectionRecent), @"kind",
				@"Recent", @"title",
				@"Recent", @"tabTitle",
				recent, @"stickers",
				@(recent.count), @"count", nil]];
	}
	if (favourites.count > 0){
		[self.sections addObject:[[NSMutableDictionary alloc] initWithObjectsAndKeys:
				@(TGStickerSectionFavourite), @"kind",
				@"Favourites", @"title",
				@"Fav", @"tabTitle",
				favourites, @"stickers",
				@(favourites.count), @"count", nil]];
	}

	for (NSDictionary *set in sets){
		if ([set[@"isEmoji"] boolValue])
			continue;
		NSInteger count = [set[@"count"] integerValue];
		if (count <= 0)
			continue;

		NSString *title = set[@"title"];
		if (title.length == 0)
			title = @"Stickers";

		NSMutableDictionary *section = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
				@(TGStickerSectionSet), @"kind",
				title, @"title",
				title, @"tabTitle",
				set[@"id"], @"setId",
				@(count), @"count", nil];

		NSInteger thumbId = [set[@"thumbId"] integerValue];
		if (thumbId == 0){
			NSArray *covers = set[@"covers"];
			NSDictionary *cover = covers.count > 0 ? covers[0] : nil;
			if (cover != nil){
				thumbId = [cover[@"thumbId"] integerValue];
				if (thumbId == 0 && ![cover[@"isVideo"] boolValue] && ![cover[@"isAnimated"] boolValue])
					thumbId = [cover[@"fileId"] integerValue];
			}
		}
		if (thumbId != 0)
			section[@"tabThumbId"] = @(thumbId);

		[self.sections addObject:section];
	}

	self.failed = (self.sections.count == 0 && failed);
	[self rebuildTabs];
	[self relayoutSections];
	[self updateStatus];

	if (self.sections.count > 0)
		[self setSelectedSection:0 scrollGrid:NO];
}

- (void)loadSectionAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.sections.count)
		return;

	NSMutableDictionary *section = self.sections[index];
	if (section[@"stickers"] != nil || [section[@"loading"] boolValue])
		return;
	if ([section[@"kind"] integerValue] != TGStickerSectionSet)
		return;

	section[@"loading"] = @YES;
	NSInteger generation = self.generation;
	int64_t setId = [section[@"setId"] longLongValue];

	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] stickerSetWithId:setId completion:^(NSDictionary *full){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || me.generation != generation)
			return;
		if (index >= (NSInteger)me.sections.count)
			return;

		NSMutableDictionary *target = me.sections[index];
		[target removeObjectForKey:@"loading"];
		NSArray *stickers = full[@"stickers"];
		target[@"stickers"] = stickers != nil ? stickers : [NSArray array];
		if (stickers != nil && stickers.count != [target[@"count"] unsignedIntegerValue]){
			target[@"count"] = @(stickers.count);
			[me relayoutSections];
		}
		[me updateVisibleTiles];
	}];
}

#pragma mark - geometry

- (void)layoutSubviews {
	[super layoutSubviews];

	CGRect bounds = self.bounds;
	CGFloat separator = 1.0f / [UIScreen mainScreen].scale;

	self.topSeparator.frame = CGRectMake(0, 0, bounds.size.width, separator);
	self.tabStrip.frame = CGRectMake(0, separator, bounds.size.width, TGStickerPanelTabHeight);
	self.grid.frame = CGRectMake(0, separator + TGStickerPanelTabHeight, bounds.size.width,
			bounds.size.height - separator - TGStickerPanelTabHeight);

	CGFloat centreY = floorf(self.grid.frame.origin.y + self.grid.frame.size.height / 2.0f);
	self.spinner.frame = CGRectMake(floorf((bounds.size.width - 20) / 2.0f), centreY - 10, 20, 20);
	self.statusLabel.frame = CGRectMake(20, centreY - 34, bounds.size.width - 40, 40);
	self.retryButton.frame = CGRectMake(floorf((bounds.size.width - 120) / 2.0f), centreY + 12, 120, 43);

	NSInteger columns = (NSInteger)floorf((bounds.size.width - 12.0f) / (TGStickerPanelTileSide + 12.0f));
	if (columns < 4)
		columns = 4;
	CGFloat gutter = floorf((bounds.size.width - columns * TGStickerPanelTileSide) / (columns + 1));
	if (gutter < 4.0f)
		gutter = 4.0f;

	BOOL metricsChanged = (columns != self.columns || fabsf(gutter - self.gutter) > 0.01f);
	BOOL widthChanged = fabsf(bounds.size.width - self.laidOutWidth) > 0.01f;
	self.columns = columns;
	self.gutter = gutter;
	self.laidOutWidth = bounds.size.width;
	if (metricsChanged || widthChanged || (self.sections.count > 0 && self.grid.contentSize.height < 1.0f))
		[self relayoutSections];
	[self layoutTabs];
	[self updateVisibleTiles];
}

- (void)relayoutSections {
	for (UIView *header in self.headerViews)
		[header removeFromSuperview];
	[self.headerViews removeAllObjects];

	CGFloat y = 0;
	CGFloat width = self.grid.bounds.size.width;
	if (width < 1.0f)
		return;

	NSInteger index = 0;
	for (NSMutableDictionary *section in self.sections){
		NSInteger count = [section[@"count"] integerValue];
		NSInteger rows = (count + self.columns - 1) / self.columns;
		if (rows < 1)
			rows = 1;

		section[@"y"] = @(y);

		UIImage *plate = [UIImage imageNamed:index == 0 ? @"CategoryDividerFirst.png" : @"CategoryDivider.png"];
		UIImageView *header = [[UIImageView alloc] initWithFrame:
				CGRectMake(0, y, width, TGStickerPanelHeaderHeight)];
		if (plate != nil)
			header.image = [plate stretchableImageWithLeftCapWidth:1 topCapHeight:0];
		else
			header.backgroundColor = [[TGTheme shared] listBackgroundColour];

		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(self.gutter, 0, width - self.gutter * 2, TGStickerPanelHeaderHeight)];
		label.backgroundColor = [UIColor clearColor];
		label.font = [UIFont boldSystemFontOfSize:13];
		label.textColor = [UIColor colorWithRed:0x69 / 255.0f green:0x74 / 255.0f
										   blue:0x87 / 255.0f alpha:1.0f];
		label.text = section[@"title"];
		[header addSubview:label];
		[self.grid addSubview:header];
		[self.headerViews addObject:header];

		CGFloat body = self.gutter + rows * (TGStickerPanelTileSide + self.gutter);
		section[@"height"] = @(TGStickerPanelHeaderHeight + body);
		y += TGStickerPanelHeaderHeight + body;
		index += 1;
	}

	self.grid.contentSize = CGSizeMake(width, y);
	[self clearTiles];
	[self updateVisibleTiles];
}

- (CGRect)frameForItem:(NSInteger)item inSection:(NSInteger)sectionIndex {
	NSDictionary *section = self.sections[sectionIndex];
	CGFloat sectionY = [section[@"y"] floatValue];
	NSInteger row = item / self.columns;
	NSInteger column = item % self.columns;
	CGFloat x = self.gutter + column * (TGStickerPanelTileSide + self.gutter);
	CGFloat y = sectionY + TGStickerPanelHeaderHeight + self.gutter +
			row * (TGStickerPanelTileSide + self.gutter);
	return CGRectMake(floorf(x), floorf(y), TGStickerPanelTileSide, TGStickerPanelTileSide);
}

#pragma mark - tiles

- (void)clearTiles {
	for (NSString *key in [self.visibleTiles allKeys]){
		TGStickerTile *tile = self.visibleTiles[key];
		[self.recycler recycleView:tile];
	}
	[self.visibleTiles removeAllObjects];
}

- (void)updateVisibleTiles {
	if (self.sections.count == 0)
		return;

	CGRect visible = CGRectMake(0, self.grid.contentOffset.y - TGStickerPanelTileSide,
			self.grid.bounds.size.width, self.grid.bounds.size.height + TGStickerPanelTileSide * 2);

	NSMutableSet *wanted = [[NSMutableSet alloc] init];

	for (NSInteger s = 0; s < (NSInteger)self.sections.count; s++){
		NSDictionary *section = self.sections[s];
		CGFloat sectionY = [section[@"y"] floatValue];
		CGFloat sectionHeight = [section[@"height"] floatValue];
		if (sectionY + sectionHeight < CGRectGetMinY(visible) || sectionY > CGRectGetMaxY(visible))
			continue;

		[self loadSectionAtIndex:s];

		NSArray *stickers = section[@"stickers"];
		NSInteger count = [section[@"count"] integerValue];
		if (stickers != nil)
			count = (NSInteger)stickers.count;

		for (NSInteger i = 0; i < count; i++){
			CGRect frame = [self frameForItem:i inSection:s];
			if (CGRectGetMaxY(frame) < CGRectGetMinY(visible) || frame.origin.y > CGRectGetMaxY(visible))
				continue;

			NSString *key = [NSString stringWithFormat:@"%d.%d", (int)s, (int)i];
			[wanted addObject:key];

			TGStickerTile *tile = self.visibleTiles[key];
			if (tile == nil){
				tile = (TGStickerTile *)[self.recycler dequeueReusableViewWithIdentifier:@"stickerTile"];
				if (tile == nil)
					tile = [[TGStickerTile alloc] initWithFrame:frame];
				[tile addTarget:self action:@selector(tileTapped:)
					   forControlEvents:UIControlEventTouchUpInside];
				UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
						initWithTarget:self action:@selector(tileLongPressed:)];
				press.minimumPressDuration = 0.5;
				[tile addGestureRecognizer:press];
				[self.grid addSubview:tile];
				self.visibleTiles[key] = tile;
			}
			tile.frame = frame;
			tile.sectionIndex = s;
			tile.itemIndex = i;

			NSDictionary *sticker = (stickers != nil && i < (NSInteger)stickers.count) ? stickers[i] : nil;
			[self configureTile:tile withSticker:sticker];
		}
	}

	for (NSString *key in [self.visibleTiles allKeys]){
		if ([wanted containsObject:key])
			continue;
		[self.recycler recycleView:self.visibleTiles[key]];
		[self.visibleTiles removeObjectForKey:key];
	}
}

- (void)configureTile:(TGStickerTile *)tile withSticker:(NSDictionary *)sticker {
	tile.sticker = sticker;
	if (sticker == nil){
		tile.emojiLabel.text = @"";
		tile.imageView.image = nil;
		return;
	}

	NSString *emoji = sticker[@"emoji"];
	tile.emojiLabel.text = emoji.length > 0 ? emoji : @"";

	NSInteger fileId = [self drawableFileIdForSticker:sticker];
	if (fileId == 0){
		tile.imageView.image = nil;
		return;
	}

	UIImage *cached = [self cachedImageForFileId:fileId side:TGStickerPanelTileSide];
	if (cached != nil){
		tile.imageView.image = cached;
		tile.emojiLabel.text = @"";
		return;
	}

	tile.imageView.image = nil;
	NSDictionary *requested = sticker;
	__weak TGStickerPanelView *weakSelf = self;
	__weak TGStickerTile *weakTile = tile;
	[self imageForFileId:fileId side:TGStickerPanelTileSide completion:^(UIImage *image){
		TGStickerPanelView *me = weakSelf;
		TGStickerTile *target = weakTile;
		if (me == nil || target == nil || image == nil)
			return;
		if (target.sticker != requested)
			return;
		target.imageView.image = image;
		target.emojiLabel.text = @"";
	}];
}

- (NSInteger)drawableFileIdForSticker:(NSDictionary *)sticker {
	BOOL drawable = ![sticker[@"isVideo"] boolValue] && ![sticker[@"isAnimated"] boolValue];
	NSInteger thumbId = [sticker[@"thumbId"] integerValue];
	if (thumbId != 0)
		return thumbId;
	return drawable ? [sticker[@"fileId"] integerValue] : 0;
}

#pragma mark - images

- (NSString *)cacheKeyForFileId:(NSInteger)fileId side:(CGFloat)side {
	return [NSString stringWithFormat:@"%d@%d", (int)fileId, (int)side];
}

- (UIImage *)cachedImageForFileId:(NSInteger)fileId side:(CGFloat)side {
	return self.imageCache[[self cacheKeyForFileId:fileId side:side]];
}

- (void)imageForFileId:(NSInteger)fileId side:(CGFloat)side completion:(void (^)(UIImage *))completion {
	NSString *key = [self cacheKeyForFileId:fileId side:side];
	UIImage *cached = self.imageCache[key];
	if (cached != nil){
		if (completion)
			completion(cached);
		return;
	}
	if ([self.pendingImages containsObject:key])
		return;
	[self.pendingImages addObject:key];

	NSInteger generation = self.generation;
	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] downloadFile:fileId completion:^(NSString *path){
		TGStickerPanelView *me = weakSelf;
		if (me == nil)
			return;
		if (path.length == 0){
			[me.pendingImages removeObject:key];
			return;
		}
		dispatch_async(me.decodeQueue, ^{
			UIImage *decoded = [UIImage convertFromWebP:path compressedData:nil error:nil];
			if (decoded == nil)
				decoded = [UIImage imageWithContentsOfFile:path];
			UIImage *scaled = [TGStickerPanelView imageFrom:decoded fittingSide:side];
			dispatch_async(dispatch_get_main_queue(), ^{
				TGStickerPanelView *inner = weakSelf;
				if (inner == nil)
					return;
				[inner.pendingImages removeObject:key];
				if (scaled == nil || inner.generation != generation)
					return;
				if (inner.imageCache.count > TGStickerPanelImageCacheLimit)
					[inner.imageCache removeAllObjects];
				inner.imageCache[key] = scaled;
				if (completion)
					completion(scaled);
			});
		});
	}];
}

+ (UIImage *)imageFrom:(UIImage *)image fittingSide:(CGFloat)side {
	if (image == nil)
		return nil;
	CGSize size = image.size;
	if (size.width < 1.0f || size.height < 1.0f)
		return nil;

	CGFloat scale = MIN(side / size.width, side / size.height);
	CGSize target = CGSizeMake(floorf(size.width * scale), floorf(size.height * scale));
	if (target.width < 1.0f || target.height < 1.0f)
		return nil;

	UIGraphicsBeginImageContextWithOptions(target, NO, 0.0f);
	[image drawInRect:CGRectMake(0, 0, target.width, target.height)];
	UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return result;
}

#pragma mark - tabs

- (void)rebuildTabs {
	for (UIView *view in [self.tabStrip.subviews copy])
		[view removeFromSuperview];
	[self.tabButtons removeAllObjects];

	NSInteger total = (NSInteger)self.sections.count + 1;
	NSInteger index = 0;

	for (NSMutableDictionary *section in self.sections){
		UIButton *button = [self tabButtonAtIndex:index total:total];
		button.tag = index;
		[button addTarget:self action:@selector(tabTapped:)
		 forControlEvents:UIControlEventTouchUpInside];

		NSNumber *thumbId = section[@"tabThumbId"];
		if (thumbId != nil){
			UIImage *cached = [self cachedImageForFileId:[thumbId integerValue] side:24.0f];
			if (cached != nil){
				[button setImage:cached forState:UIControlStateNormal];
			}
			else {
				[button setTitle:[self shortTabTitle:section[@"tabTitle"]] forState:UIControlStateNormal];
				__weak UIButton *weakButton = button;
				[self imageForFileId:[thumbId integerValue] side:24.0f completion:^(UIImage *image){
					UIButton *target = weakButton;
					if (target == nil || image == nil)
						return;
					[target setTitle:@"" forState:UIControlStateNormal];
					[target setImage:image forState:UIControlStateNormal];
				}];
			}
		}
		else {
			[button setTitle:[self shortTabTitle:section[@"tabTitle"]] forState:UIControlStateNormal];
		}

		[self.tabStrip addSubview:button];
		[self.tabButtons addObject:button];
		index += 1;
	}

	UIButton *hide = [self tabButtonAtIndex:index total:total];
	hide.tag = -1;
	[hide setTitle:@"Hide" forState:UIControlStateNormal];
	[hide addTarget:self action:@selector(hideTapped)
   forControlEvents:UIControlEventTouchUpInside];
	[self.tabStrip addSubview:hide];
	[self.tabButtons addObject:hide];

	[self layoutTabs];
	[self updateTabSelection];
}

- (NSString *)shortTabTitle:(NSString *)title {
	if (title.length <= 3)
		return title;
	return [[title substringToIndex:3] uppercaseString];
}

- (UIButton *)tabButtonAtIndex:(NSInteger)index total:(NSInteger)total {
	NSString *name = @"ButtonGroupCenter.png";
	NSString *highlighted = @"ButtonGroupCenter_Highlighted.png";
	NSInteger cap = 1;
	if (index == 0){
		name = @"ButtonGroupLeft.png";
		highlighted = @"ButtonGroupLeft_Highlighted.png";
		cap = 8;
	}
	else if (index == total - 1){
		name = @"ButtonGroupRight.png";
		highlighted = @"ButtonGroupRight_Highlighted.png";
		cap = 1;
	}

	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	UIImage *plate = [UIImage imageNamed:name];
	UIImage *platePressed = [UIImage imageNamed:highlighted];
	if (plate != nil)
		[button setBackgroundImage:[plate stretchableImageWithLeftCapWidth:cap topCapHeight:0]
						  forState:UIControlStateNormal];
	if (platePressed != nil){
		UIImage *stretched = [platePressed stretchableImageWithLeftCapWidth:cap topCapHeight:0];
		[button setBackgroundImage:stretched forState:UIControlStateHighlighted];
		[button setBackgroundImage:stretched forState:UIControlStateSelected];
		[button setBackgroundImage:stretched
						  forState:UIControlStateSelected | UIControlStateHighlighted];
	}
	button.adjustsImageWhenHighlighted = NO;
	button.adjustsImageWhenDisabled = NO;
	button.exclusiveTouch = YES;
	button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[button setTitleShadowColor:[UIColor colorWithRed:0x0e / 255.0f green:0x28 / 255.0f
												 blue:0x4d / 255.0f alpha:0.4f]
					   forState:UIControlStateNormal];
	button.imageView.contentMode = UIViewContentModeScaleAspectFit;
	return button;
}

- (void)layoutTabs {
	for (UIView *view in [self.tabStrip.subviews copy]){
		if (view.tag == 9901)
			[view removeFromSuperview];
	}

	CGFloat x = 0;
	for (UIButton *button in self.tabButtons){
		CGFloat width = 44.0f;
		NSString *title = [button titleForState:UIControlStateNormal];
		if (title.length > 0){
			CGSize size = [title sizeWithFont:button.titleLabel.font];
			width = MAX(44.0f, floorf(size.width) + 14.0f);
		}
		button.frame = CGRectMake(floorf(x), 0, width, TGStickerPanelTabHeight);
		x += width;

		if (button != [self.tabButtons lastObject]){
			UIImage *divider = [UIImage imageNamed:@"ButtonGroupDivider.png"];
			if (divider != nil){
				UIImageView *view = [[UIImageView alloc] initWithFrame:
						CGRectMake(floorf(x) - 1, 0, 2, TGStickerPanelTabHeight)];
				view.image = [divider stretchableImageWithLeftCapWidth:6 topCapHeight:0];
				view.tag = 9901;
				[self.tabStrip insertSubview:view atIndex:0];
			}
		}
	}
	self.tabStrip.contentSize = CGSizeMake(x, TGStickerPanelTabHeight);
}

- (void)updateTabSelection {
	NSInteger index = 0;
	for (UIButton *button in self.tabButtons){
		button.selected = (button.tag >= 0 && index == self.selectedSection);
		index += 1;
	}
}

- (void)setSelectedSection:(NSInteger)index scrollGrid:(BOOL)scrollGrid {
	if (index < 0 || index >= (NSInteger)self.sections.count)
		return;
	_selectedSection = index;
	[self updateTabSelection];

	if (index < (NSInteger)self.tabButtons.count){
		UIButton *button = self.tabButtons[index];
		[self.tabStrip scrollRectToVisible:CGRectInset(button.frame, -20, 0) animated:YES];
	}

	if (!scrollGrid)
		return;

	CGFloat y = [self.sections[index][@"y"] floatValue];
	CGFloat maxOffset = MAX(0.0f, self.grid.contentSize.height - self.grid.bounds.size.height);
	[self.grid setContentOffset:CGPointMake(0, MIN(y, maxOffset)) animated:YES];
}

- (void)tabTapped:(UIButton *)button {
	[self setSelectedSection:button.tag scrollGrid:YES];
}

- (void)hideTapped {
	if (self.onCloseRequested)
		self.onCloseRequested();
}

#pragma mark - status

- (void)updateStatus {
	BOOL empty = (!self.loading && self.sections.count == 0);

	if (self.loading)
		[self.spinner startAnimating];
	else
		[self.spinner stopAnimating];

	self.statusLabel.hidden = !empty;
	self.retryButton.hidden = !(empty && self.failed);
	self.grid.hidden = empty;

	if (!empty)
		return;

	self.statusLabel.text = self.failed ? @"Stickers could not be loaded."
										: @"No sticker sets installed yet.";
}

#pragma mark - interaction

- (void)tileTapped:(TGStickerTile *)tile {
	NSDictionary *sticker = tile.sticker;
	if (sticker == nil)
		return;

	NSInteger fileId = [sticker[@"fileId"] integerValue];
	if (fileId != 0)
		[[TGClient shared] addRecentStickerWithFileId:fileId];

	if (self.onStickerPicked)
		self.onStickerPicked(sticker);
}

- (void)tileLongPressed:(UILongPressGestureRecognizer *)recogniser {
	if (recogniser.state != UIGestureRecognizerStateBegan)
		return;
	if (![recogniser.view isKindOfClass:[TGStickerTile class]])
		return;

	TGStickerTile *tile = (TGStickerTile *)recogniser.view;
	NSDictionary *sticker = tile.sticker;
	NSInteger fileId = [sticker[@"fileId"] integerValue];
	if (fileId == 0)
		return;

	BOOL isFavourite = NO;
	if (tile.sectionIndex < (NSInteger)self.sections.count){
		NSDictionary *section = self.sections[tile.sectionIndex];
		isFavourite = ([section[@"kind"] integerValue] == TGStickerSectionFavourite);
	}

	if (isFavourite)
		[[TGClient shared] removeFavoriteStickerWithFileId:fileId];
	else
		[[TGClient shared] addFavoriteStickerWithFileId:fileId];

	[self refreshFavourites];
}

- (void)refreshFavourites {
	NSInteger generation = self.generation;
	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] favoriteStickersWithCompletion:^(NSArray *stickers){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || me.generation != generation || stickers == nil)
			return;

		NSInteger index = -1;
		for (NSInteger i = 0; i < (NSInteger)me.sections.count; i++){
			if ([me.sections[i][@"kind"] integerValue] == TGStickerSectionFavourite){
				index = i;
				break;
			}
		}

		if (index < 0){
			if (stickers.count == 0)
				return;
			[me reload];
			return;
		}

		if (stickers.count == 0){
			[me reload];
			return;
		}

		NSMutableDictionary *section = me.sections[index];
		section[@"stickers"] = stickers;
		section[@"count"] = @(stickers.count);
		[me relayoutSections];
	}];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != self.grid)
		return;

	[self updateVisibleTiles];

	CGFloat offset = scrollView.contentOffset.y + 1.0f;
	NSInteger current = 0;
	for (NSInteger i = 0; i < (NSInteger)self.sections.count; i++){
		if ([self.sections[i][@"y"] floatValue] <= offset)
			current = i;
		else
			break;
	}
	if (current != self.selectedSection){
		_selectedSection = current;
		[self updateTabSelection];
		if (current < (NSInteger)self.tabButtons.count){
			UIButton *button = self.tabButtons[current];
			[self.tabStrip scrollRectToVisible:CGRectInset(button.frame, -20, 0) animated:YES];
		}
	}
}

@end

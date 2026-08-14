#import "TGStickersViewController.h"
#import "TGClient.h"
#import "TGClient+Stickers.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGActionSheet.h"
#import "UIImage+WebP.h"

#define TGStickersRGB(rgb) [UIColor colorWithRed:(((rgb) >> 16) & 0xff) / 255.0f \
										   green:(((rgb) >> 8) & 0xff) / 255.0f \
											blue:((rgb) & 0xff) / 255.0f alpha:1.0f]

static const CGFloat kSetRowHeight = 51.0f;
static const CGFloat kPlainRowHeight = 44.0f;
static const CGFloat kCoverSide = 40.0f;
static const CGFloat kTileSide = 64.0f;
static const NSInteger kArchivedPageSize = 20;
static const NSInteger kTrendingPageSize = 20;

static CGFloat TGStickersRetinaPixel(void) {
	return [UIScreen mainScreen].scale > 1.0f ? 0.5f : 0.0f;
}

@interface TGStickersViewController () <UITableViewDataSource, UITableViewDelegate,
		UIScrollViewDelegate>

@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIScrollView *grid;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIView *placeholder;
@property (nonatomic, strong) UILabel *placeholderTitle;
@property (nonatomic, strong) UILabel *placeholderBody;

@property (nonatomic, strong) NSMutableArray *sets;
@property (nonatomic, strong) NSArray *stickers;
@property (nonatomic, strong) NSMutableDictionary *covers;
@property (nonatomic, strong) NSMutableSet *coversInFlight;
@property (nonatomic, strong) NSMutableArray *tiles;

@property (nonatomic, assign) NSInteger favouriteCount;
@property (nonatomic, assign) NSInteger archivedCount;
@property (nonatomic, assign) NSInteger trendingNewCount;
@property (nonatomic, assign) NSInteger totalRemote;

@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL exhausted;
@property (nonatomic, assign) BOOL reordering;
@property (nonatomic, assign) BOOL installedHere;

@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, strong) NSDictionary *actionSheetSet;
@property (nonatomic, strong) NSDictionary *actionSheetSticker;
@end

@implementation TGStickersViewController

- (instancetype)init {
	self = [super initWithNibName:nil bundle:nil];
	if (self){
		_page = TGStickersPageRoot;
		_sets = [NSMutableArray array];
		_covers = [NSMutableDictionary dictionary];
		_coversInFlight = [NSMutableSet set];
		_tiles = [NSMutableArray array];
	}
	return self;
}

- (BOOL)isGridPage {
	return self.page == TGStickersPageFavourites || self.page == TGStickersPageSet;
}

- (NSString *)pageTitle {
	switch (self.page){
		case TGStickersPageTrending:   return @"Trending Stickers";
		case TGStickersPageArchived:   return @"Archived Stickers";
		case TGStickersPageFavourites: return @"Favourite Stickers";
		case TGStickersPageSet: {
			NSString *title = self.set[@"title"];
			return title.length ? title : @"Stickers";
		}
		default: return @"Stickers";
	}
}

#pragma mark - lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = [self pageTitle];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];

	if ([self isGridPage])
		[self buildGrid];
	else
		[self buildTable];

	[self buildPlaceholder];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
			UIActivityIndicatorViewStyleGray];
	self.spinner.hidesWhenStopped = YES;
	[self.view addSubview:self.spinner];

	if (self.page == TGStickersPageRoot)
		[self installEditButton];
	if (self.page == TGStickersPageSet)
		[self refreshSetBarButton];

	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	if (self.page == TGStickersPageRoot && self.loaded && !self.reordering)
		[self reload];
	[self.table deselectRowAtIndexPath:[self.table indexPathForSelectedRow] animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.currentActionSheet){
		[self.currentActionSheet dismissWithClickedButtonIndex:
				self.currentActionSheet.cancelButtonIndex animated:NO];
		self.currentActionSheet = nil;
	}
	if (self.reordering)
		[self commitOrder];
}

- (void)viewDidLayoutSubviews {
	if ([super respondsToSelector:@selector(viewDidLayoutSubviews)])
		[super viewDidLayoutSubviews];
	[self layoutChrome];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	if (![self isGridPage])
		return;
	[self.covers removeAllObjects];
	for (UIButton *tile in self.tiles){
		if (tile.superview && CGRectIntersectsRect(tile.frame, [self visibleGridRect]))
			continue;
		[tile setImage:nil forState:UIControlStateNormal];
		[tile setTitle:tile.accessibilityLabel forState:UIControlStateNormal];
	}
}

#pragma mark - chrome

- (void)buildTable {
	self.table = [[UITableView alloc] initWithFrame:self.view.bounds
											  style:UITableViewStyleGrouped];
	self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.rowHeight = kPlainRowHeight;
	self.table.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.table.separatorColor = [[TGTheme shared] separatorColour];
	if ([[TGTheme shared] isDark])
		self.table.backgroundView = nil;
	[self.view addSubview:self.table];
}

- (void)buildGrid {
	self.grid = [[UIScrollView alloc] initWithFrame:self.view.bounds];
	self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	self.grid.delegate = self;
	self.grid.alwaysBounceVertical = YES;
	self.grid.backgroundColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] listBackgroundColour] : [UIColor whiteColor];
	[self.view addSubview:self.grid];
}

- (void)buildPlaceholder {
	self.placeholder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 250, 0)];
	self.placeholder.backgroundColor = [UIColor clearColor];
	self.placeholder.hidden = YES;

	self.placeholderTitle = [[UILabel alloc] initWithFrame:CGRectZero];
	self.placeholderTitle.backgroundColor = [UIColor clearColor];
	self.placeholderTitle.font = [UIFont boldSystemFontOfSize:15];
	self.placeholderTitle.textColor = TGStickersRGB(0x8b97a5);
	self.placeholderTitle.textAlignment = NSTextAlignmentCenter;
	[self.placeholder addSubview:self.placeholderTitle];

	self.placeholderBody = [[UILabel alloc] initWithFrame:CGRectZero];
	self.placeholderBody.backgroundColor = [UIColor clearColor];
	self.placeholderBody.font = [UIFont systemFontOfSize:14];
	self.placeholderBody.textColor = TGStickersRGB(0x8b97a5);
	self.placeholderBody.textAlignment = NSTextAlignmentCenter;
	self.placeholderBody.lineBreakMode = NSLineBreakByWordWrapping;
	self.placeholderBody.numberOfLines = 0;
	[self.placeholder addSubview:self.placeholderBody];

	[self.view addSubview:self.placeholder];
}

- (void)installEditButton {
	NSString *title = self.reordering ? @"Done" : @"Edit";
	UIButton *button = [TGIcons headerButtonWithTitle:title bold:self.reordering
											   target:self action:@selector(editTapped)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:button];
	self.navigationItem.rightBarButtonItem.customView.hidden = (self.sets.count == 0);
}

- (void)refreshSetBarButton {
	BOOL installed = [self.set[@"installed"] boolValue] || self.installedHere;
	UIButton *button = [TGIcons headerButtonWithTitle:(installed ? @"Remove" : @"Add")
												 bold:!installed
											   target:self
											   action:@selector(toggleCurrentSet)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:button];
}

- (void)layoutChrome {
	CGFloat width = self.view.bounds.size.width;
	CGFloat height = self.view.bounds.size.height;

	self.spinner.center = CGPointMake(floorf(width / 2), floorf(height / 2));

	if (!self.placeholder.hidden){
		CGFloat containerWidth = 250;
		CGSize titleSize = [self.placeholderTitle.text
				sizeWithFont:self.placeholderTitle.font];
		CGSize bodySize = [self.placeholderBody.text
				sizeWithFont:self.placeholderBody.font
		   constrainedToSize:CGSizeMake(232, 1000)
			   lineBreakMode:NSLineBreakByWordWrapping];

		self.placeholderTitle.frame = CGRectMake(0, 0, containerWidth, titleSize.height);
		self.placeholderBody.frame = CGRectMake(floorf((containerWidth - 232) / 2),
				titleSize.height + 8, 232, bodySize.height);
		CGFloat containerHeight = titleSize.height + 8 + bodySize.height;
		self.placeholder.frame = CGRectMake(floorf((width - containerWidth) / 2),
				floorf((height - containerHeight) / 2), containerWidth, containerHeight);
	}

	if ([self isGridPage])
		[self layoutTiles];
}

#pragma mark - state

- (void)showLoading {
	self.placeholder.hidden = YES;
	self.table.hidden = (self.sets.count == 0 && self.page != TGStickersPageRoot);
	self.grid.hidden = (self.tiles.count == 0);
	[self.spinner startAnimating];
	[self layoutChrome];
}

- (void)showTitle:(NSString *)title body:(NSString *)body {
	[self.spinner stopAnimating];
	self.placeholderTitle.text = title;
	self.placeholderBody.text = body;
	self.placeholder.hidden = NO;
	self.table.hidden = YES;
	self.grid.hidden = YES;
	[self layoutChrome];
}

- (void)showContent {
	[self.spinner stopAnimating];
	self.placeholder.hidden = YES;
	self.table.hidden = NO;
	self.grid.hidden = NO;
	[self layoutChrome];
}

- (void)showFailure {
	[self showTitle:@"No Stickers"
			   body:@"The sticker list could not be loaded. Check the connection and try again."];
}

#pragma mark - loading

- (void)reload {
	switch (self.page){
		case TGStickersPageTrending:   [self reloadTrending]; break;
		case TGStickersPageArchived:   [self reloadArchived]; break;
		case TGStickersPageFavourites: [self reloadFavourites]; break;
		case TGStickersPageSet:        [self reloadSet]; break;
		default:                       [self reloadRoot]; break;
	}
}

- (void)reloadRoot {
	if (!self.loaded)
		[self showLoading];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] installedStickerSetsWithCompletion:^(NSArray *sets){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		strongSelf.failed = (sets == nil);
		if (sets)
			strongSelf.sets = [NSMutableArray arrayWithArray:sets];
		if (strongSelf.failed && strongSelf.sets.count == 0){
			[strongSelf showFailure];
			return;
		}
		[strongSelf showContent];
		[strongSelf.table reloadData];
		[strongSelf installEditButton];
	}];

	[[TGClient shared] favoriteStickersWithCompletion:^(NSArray *stickers){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.favouriteCount = (NSInteger)stickers.count;
		[strongSelf reloadFirstSection];
	}];

	[[TGClient shared] archivedStickerSetsFromSetId:0 limit:1
										 completion:^(NSArray *sets, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.archivedCount = total > 0 ? total : (NSInteger)sets.count;
		[strongSelf reloadFirstSection];
	}];

	[[TGClient shared] trendingStickerSetsWithOffset:0 limit:kTrendingPageSize
										  completion:^(NSArray *sets, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSInteger unseen = 0;
		for (NSDictionary *set in sets)
			if (![set[@"viewed"] boolValue])
				unseen++;
		strongSelf.trendingNewCount = unseen;
		[strongSelf reloadFirstSection];
	}];
}

- (void)reloadFirstSection {
	if (self.table.hidden || !self.loaded)
		return;
	[self.table reloadSections:[NSIndexSet indexSetWithIndex:0]
			  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)reloadTrending {
	[self showLoading];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] trendingStickerSetsWithOffset:0 limit:kTrendingPageSize
										  completion:^(NSArray *sets, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		strongSelf.totalRemote = total;
		if (!sets){
			[strongSelf showFailure];
			return;
		}
		strongSelf.sets = [NSMutableArray arrayWithArray:sets];
		strongSelf.exhausted = (sets.count == 0 || (NSInteger)sets.count >= total);
		if (strongSelf.sets.count == 0){
			[strongSelf showTitle:@"No Trending Stickers"
							 body:@"There is nothing featured right now. Come back later."];
			return;
		}
		[strongSelf showContent];
		[strongSelf.table reloadData];
		[strongSelf markShownSetsViewed];
	}];
}

- (void)markShownSetsViewed {
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *set in self.sets)
		if (![set[@"viewed"] boolValue] && set[@"id"])
			[ids addObject:set[@"id"]];
	if (ids.count)
		[[TGClient shared] markTrendingStickerSetsViewed:ids];
}

- (void)reloadArchived {
	[self showLoading];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] archivedStickerSetsFromSetId:0 limit:kArchivedPageSize
										 completion:^(NSArray *sets, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		strongSelf.totalRemote = total;
		if (!sets){
			[strongSelf showFailure];
			return;
		}
		strongSelf.sets = [NSMutableArray arrayWithArray:sets];
		strongSelf.exhausted = ((NSInteger)sets.count < kArchivedPageSize);
		if (strongSelf.sets.count == 0){
			[strongSelf showTitle:@"No Archived Stickers"
							 body:@"Sticker sets you archive are kept here, ready to be put back."];
			return;
		}
		[strongSelf showContent];
		[strongSelf.table reloadData];
	}];
}

- (void)loadMoreArchived {
	if (self.loadingMore || self.exhausted || self.sets.count == 0)
		return;
	self.loadingMore = YES;
	int64_t last = [[self.sets lastObject][@"id"] longLongValue];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] archivedStickerSetsFromSetId:last limit:kArchivedPageSize
										 completion:^(NSArray *sets, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loadingMore = NO;
		strongSelf.totalRemote = total;
		if (sets.count == 0){
			strongSelf.exhausted = YES;
			[strongSelf.table reloadData];
			return;
		}
		strongSelf.exhausted = ((NSInteger)sets.count < kArchivedPageSize);
		[strongSelf.sets addObjectsFromArray:sets];
		[strongSelf.table reloadData];
	}];
}

- (void)reloadFavourites {
	[self showLoading];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] favoriteStickersWithCompletion:^(NSArray *stickers){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		if (!stickers){
			[strongSelf showFailure];
			return;
		}
		strongSelf.stickers = stickers;
		if (stickers.count == 0){
			[strongSelf showTitle:@"No Favourites"
							 body:@"Hold a sticker in a chat and add it to favourites to keep it here."];
			return;
		}
		[strongSelf showContent];
		[strongSelf rebuildTiles];
	}];
}

- (void)reloadSet {
	[self showLoading];
	int64_t identifier = self.setId ?: [self.set[@"id"] longLongValue];
	if (identifier == 0){
		[self showFailure];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] stickerSetWithId:identifier completion:^(NSDictionary *set){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		if (!set){
			[strongSelf showFailure];
			return;
		}
		strongSelf.set = set;
		strongSelf.title = [strongSelf pageTitle];
		strongSelf.stickers = set[@"stickers"];
		[strongSelf refreshSetBarButton];
		if (strongSelf.stickers.count == 0){
			[strongSelf showTitle:@"Empty Set" body:@"This sticker set has no stickers in it."];
			return;
		}
		[strongSelf showContent];
		[strongSelf rebuildTiles];
	}];
}

#pragma mark - covers

- (UIImage *)scale:(UIImage *)image toSide:(CGFloat)side {
	if (!image)
		return nil;
	CGFloat scale = [UIScreen mainScreen].scale;
	CGFloat width = image.size.width;
	CGFloat height = image.size.height;
	if (width <= 0 || height <= 0)
		return nil;
	CGFloat factor = MIN(side / width, side / height);
	CGSize target = CGSizeMake(floorf(width * factor), floorf(height * factor));
	if (target.width < 1 || target.height < 1)
		return nil;

	UIGraphicsBeginImageContextWithOptions(target, NO, scale);
	[image drawInRect:CGRectMake(0, 0, target.width, target.height)];
	UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return result;
}

- (NSInteger)coverFileIdForSet:(NSDictionary *)set {
	NSArray *covers = set[@"covers"];
	for (NSDictionary *sticker in covers){
		if ([sticker[@"isAnimated"] boolValue] || [sticker[@"isVideo"] boolValue])
			continue;
		return [sticker[@"fileId"] integerValue];
	}
	return 0;
}

- (UIImage *)coverForSet:(NSDictionary *)set atIndexPath:(NSIndexPath *)indexPath {
	NSNumber *key = set[@"id"];
	if (!key)
		return nil;
	UIImage *cached = self.covers[key];
	if (cached)
		return cached;
	if ([self.coversInFlight containsObject:key])
		return nil;

	NSInteger fileId = [self coverFileIdForSet:set];
	if (fileId == 0)
		return nil;
	[self.coversInFlight addObject:key];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId completion:^(NSString *path){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf.coversInFlight removeObject:key];
		if (!path)
			return;
		UIImage *decoded = [UIImage convertFromWebP:path compressedData:nil error:nil];
		UIImage *small = [strongSelf scale:decoded toSide:kCoverSide];
		if (!small)
			return;
		strongSelf.covers[key] = small;
		if (indexPath.row < [strongSelf.table numberOfRowsInSection:indexPath.section])
			[strongSelf.table reloadRowsAtIndexPaths:@[indexPath]
									withRowAnimation:UITableViewRowAnimationNone];
	}];
	return nil;
}

#pragma mark - grid

- (CGRect)visibleGridRect {
	return CGRectMake(0, self.grid.contentOffset.y - kTileSide,
			self.grid.bounds.size.width, self.grid.bounds.size.height + kTileSide * 2);
}

- (void)rebuildTiles {
	for (UIView *tile in self.tiles)
		[tile removeFromSuperview];
	[self.tiles removeAllObjects];

	NSInteger index = 0;
	for (NSDictionary *sticker in self.stickers){
		UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
		tile.tag = index;
		tile.backgroundColor = [UIColor clearColor];
		tile.titleLabel.font = [UIFont systemFontOfSize:34];
		tile.imageView.contentMode = UIViewContentModeScaleAspectFit;
		tile.accessibilityLabel = sticker[@"emoji"];
		[tile setTitle:sticker[@"emoji"] forState:UIControlStateNormal];
		[tile addTarget:self action:@selector(tileTapped:)
	   forControlEvents:UIControlEventTouchUpInside];
		[self.grid addSubview:tile];
		[self.tiles addObject:tile];
		index++;
	}
	[self layoutTiles];
}

- (void)layoutTiles {
	if (!self.grid || self.tiles.count == 0)
		return;
	CGFloat width = self.grid.bounds.size.width;
	NSInteger columns = (NSInteger)floorf(width / (kTileSide + 8));
	if (columns < 3)
		columns = 3;
	CGFloat gutter = floorf((width - columns * kTileSide) / (columns + 1));
	if (gutter < 1)
		gutter = 1;

	NSInteger index = 0;
	for (UIButton *tile in self.tiles){
		NSInteger column = index % columns;
		NSInteger row = index / columns;
		tile.frame = CGRectMake(gutter + column * (kTileSide + gutter),
				gutter + row * (kTileSide + gutter), kTileSide, kTileSide);
		index++;
	}
	NSInteger rows = (self.tiles.count + columns - 1) / columns;
	self.grid.contentSize = CGSizeMake(width, gutter + rows * (kTileSide + gutter));
	[self loadVisibleTiles];
}

- (void)loadVisibleTiles {
	CGRect visible = [self visibleGridRect];
	for (UIButton *tile in self.tiles){
		if (!CGRectIntersectsRect(tile.frame, visible))
			continue;
		if (tile.imageView.image)
			continue;
		NSInteger index = tile.tag;
		if (index >= (NSInteger)self.stickers.count)
			continue;
		NSDictionary *sticker = self.stickers[index];
		if ([sticker[@"isAnimated"] boolValue] || [sticker[@"isVideo"] boolValue])
			continue;

		NSNumber *key = sticker[@"fileId"];
		if (!key || [key integerValue] == 0)
			continue;
		UIImage *cached = self.covers[key];
		if (cached){
			[tile setTitle:@"" forState:UIControlStateNormal];
			[tile setImage:cached forState:UIControlStateNormal];
			continue;
		}
		if ([self.coversInFlight containsObject:key])
			continue;
		[self.coversInFlight addObject:key];

		__weak typeof(self) weakSelf = self;
		__weak UIButton *weakTile = tile;
		[[TGClient shared] downloadFile:[key integerValue] completion:^(NSString *path){
			__strong typeof(weakSelf) strongSelf = weakSelf;
			__strong UIButton *strongTile = weakTile;
			if (!strongSelf)
				return;
			[strongSelf.coversInFlight removeObject:key];
			if (!path)
				return;
			UIImage *decoded = [UIImage convertFromWebP:path compressedData:nil error:nil];
			UIImage *small = [strongSelf scale:decoded toSide:kTileSide];
			if (!small)
				return;
			strongSelf.covers[key] = small;
			if (!strongTile)
				return;
			[strongTile setTitle:@"" forState:UIControlStateNormal];
			[strongTile setImage:small forState:UIControlStateNormal];
		}];
	}
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView == self.grid)
		[self loadVisibleTiles];
}

- (void)tileTapped:(UIButton *)tile {
	if (self.page != TGStickersPageFavourites)
		return;
	NSInteger index = tile.tag;
	if (index >= (NSInteger)self.stickers.count)
		return;
	self.actionSheetSticker = self.stickers[index];

	NSArray *actions = @[
		[[TGActionSheetAction alloc] initWithTitle:@"Remove from Favourites"
											action:@"removeFavourite"
											  type:TGActionSheetActionTypeDestructive],
		[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
											  type:TGActionSheetActionTypeCancel]
	];
	[self presentSheetWithTitle:nil actions:actions];
}

#pragma mark - action sheets

- (void)presentSheetWithTitle:(NSString *)title actions:(NSArray *)actions {
	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:title actions:actions
													  actionBlock:^(__unused id target, NSString *action){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.currentActionSheet = nil;
		[strongSelf performAction:action];
	} target:self];

	UIView *host = self.navigationController.view ?: self.view;
	[self.currentActionSheet showInView:host];
}

- (void)performAction:(NSString *)action {
	NSDictionary *set = self.actionSheetSet;
	self.actionSheetSet = nil;

	if ([action isEqualToString:@"archiveSet"] && set)
		[self archiveSet:set];
	else if ([action isEqualToString:@"removeSet"] && set)
		[self uninstallSet:set];
	else if ([action isEqualToString:@"clearRecent"])
		[self clearRecent];
	else if ([action isEqualToString:@"removeFavourite"])
		[self removeCurrentFavourite];
}

#pragma mark - acts

- (void)archiveSet:(NSDictionary *)set {
	NSInteger index = [self.sets indexOfObject:set];
	if (index == NSNotFound)
		return;
	[self.sets removeObjectAtIndex:index];
	[self.table reloadData];
	[self installEditButton];
	[[TGClient shared] archiveStickerSet:[set[@"id"] longLongValue] completion:^(BOOL ok){
		if (!ok)
			return;
	}];
	self.archivedCount++;
	[self reloadFirstSection];
}

- (void)uninstallSet:(NSDictionary *)set {
	NSInteger index = [self.sets indexOfObject:set];
	if (index == NSNotFound)
		return;
	[self.sets removeObjectAtIndex:index];
	[self.table reloadData];
	[self installEditButton];
	[[TGClient shared] uninstallStickerSet:[set[@"id"] longLongValue] completion:^(BOOL ok){
		if (!ok)
			return;
	}];
}

- (void)installSet:(NSDictionary *)set fromRow:(NSInteger)row {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] installStickerSet:[set[@"id"] longLongValue] completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || !ok)
			return;
		if (row >= (NSInteger)strongSelf.sets.count)
			return;
		NSMutableDictionary *updated = [NSMutableDictionary
				dictionaryWithDictionary:strongSelf.sets[row]];
		updated[@"installed"] = @YES;
		updated[@"archived"] = @NO;
		strongSelf.sets[row] = updated;
		[strongSelf.table reloadData];
	}];
}

- (void)toggleCurrentSet {
	int64_t identifier = self.setId ?: [self.set[@"id"] longLongValue];
	if (identifier == 0)
		return;
	BOOL installed = [self.set[@"installed"] boolValue] || self.installedHere;
	self.installedHere = !installed;

	NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:self.set];
	updated[@"installed"] = installed ? @NO : @YES;
	self.set = updated;
	[self refreshSetBarButton];

	if (installed)
		[[TGClient shared] uninstallStickerSet:identifier completion:^(__unused BOOL ok){}];
	else
		[[TGClient shared] installStickerSet:identifier completion:^(__unused BOOL ok){}];
}

- (void)clearRecent {
	[[TGClient shared] clearRecentStickers];
}

- (void)removeCurrentFavourite {
	NSDictionary *sticker = self.actionSheetSticker;
	self.actionSheetSticker = nil;
	if (!sticker)
		return;
	[[TGClient shared] removeFavoriteStickerWithFileId:[sticker[@"fileId"] integerValue]];

	NSMutableArray *remaining = [NSMutableArray arrayWithArray:self.stickers];
	[remaining removeObject:sticker];
	self.stickers = remaining;
	self.favouriteCount = (NSInteger)remaining.count;
	if (remaining.count == 0){
		[self showTitle:@"No Favourites"
				   body:@"Hold a sticker in a chat and add it to favourites to keep it here."];
		return;
	}
	[self rebuildTiles];
}

#pragma mark - reordering

- (void)editTapped {
	if (self.reordering){
		[self commitOrder];
		self.reordering = NO;
		[self.table setEditing:NO animated:YES];
	} else {
		self.reordering = YES;
		[self.table setEditing:YES animated:YES];
	}
	[self installEditButton];
}

- (void)commitOrder {
	self.reordering = NO;
	if (self.sets.count == 0)
		return;
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *set in self.sets)
		if (set[@"id"])
			[ids addObject:set[@"id"]];
	if (ids.count)
		[[TGClient shared] reorderInstalledStickerSets:ids];
}

#pragma mark - navigation

- (void)openPage:(TGStickersPage)page {
	TGStickersViewController *next = [[TGStickersViewController alloc] init];
	next.page = page;
	[self.navigationController pushViewController:next animated:YES];
}

- (void)openSet:(NSDictionary *)set {
	TGStickersViewController *next = [[TGStickersViewController alloc] init];
	next.page = TGStickersPageSet;
	next.set = set;
	next.setId = [set[@"id"] longLongValue];
	[self.navigationController pushViewController:next animated:YES];
}

#pragma mark - captions

- (UILabel *)captionLabel {
	UILabel *label = [[UILabel alloc] init];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont systemFontOfSize:14];
	label.textColor = [[TGTheme shared] isDark] ? [[TGTheme shared] sectionHeaderColour]
												: TGStickersRGB(0x697487);
	if (![[TGTheme shared] isFlat] && ![[TGTheme shared] isDark]){
		label.shadowColor = TGStickersRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	label.numberOfLines = 0;
	return label;
}

- (CGFloat)captionHeightFor:(NSString *)text width:(CGFloat)width {
	return [text sizeWithFont:[UIFont systemFontOfSize:14]
			constrainedToSize:CGSizeMake(width, 1000)
				lineBreakMode:NSLineBreakByWordWrapping].height;
}

- (NSString *)headerTitleForSection:(NSInteger)section {
	if (self.page == TGStickersPageRoot && section == 1 && self.sets.count)
		return @"Sticker Sets";
	return nil;
}

- (NSString *)footerTitleForSection:(NSInteger)section {
	if (self.page == TGStickersPageRoot){
		if (section != 1)
			return nil;
		if (self.sets.count == 0)
			return self.loaded ? @"You have no sticker sets yet. Trending sets are a good place to start."
							   : @"Loading...";
		return @"Tap a set to see its stickers. Swipe one away to archive or remove it, or press Edit to reorder.";
	}
	if (self.page == TGStickersPageArchived && section == 0 && self.sets.count)
		return @"Archived sets are kept out of the panel until you add them back.";
	if (self.page == TGStickersPageTrending && section == 0 && self.sets.count)
		return @"Sets other people are using right now.";
	return nil;
}

#pragma mark - table data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.page == TGStickersPageRoot ? 3 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (self.page != TGStickersPageRoot)
		return (NSInteger)self.sets.count;
	if (section == 0)
		return 3;
	if (section == 1)
		return (NSInteger)self.sets.count;
	return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.page != TGStickersPageRoot)
		return kSetRowHeight;
	return indexPath.section == 1 ? kSetRowHeight : kPlainRowHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return 12;
	return [self captionHeightFor:title width:tableView.bounds.size.width - 42] + 18;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return nil;
	CGFloat width = tableView.bounds.size.width - 42;
	CGFloat height = [self captionHeightFor:title width:width];
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, height + 18)];
	container.backgroundColor = [UIColor clearColor];
	UILabel *label = [self captionLabel];
	label.text = title;
	label.frame = CGRectMake(21, 6 + TGStickersRetinaPixel(), width, height);
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return 1;
	return [self captionHeightFor:title width:tableView.bounds.size.width - 42] + 14;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return nil;
	CGFloat width = tableView.bounds.size.width - 42;
	CGFloat height = [self captionHeightFor:title width:width];
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, height + 14)];
	container.backgroundColor = [UIColor clearColor];
	UILabel *label = [self captionLabel];
	label.text = title;
	label.frame = CGRectMake(21, 7 + TGStickersRetinaPixel(), width, height);
	[container addSubview:label];
	return container;
}

- (NSDictionary *)setAtIndexPath:(NSIndexPath *)indexPath {
	if (self.page == TGStickersPageRoot && indexPath.section != 1)
		return nil;
	if (indexPath.row >= (NSInteger)self.sets.count)
		return nil;
	return self.sets[indexPath.row];
}

- (NSString *)countTextForSet:(NSDictionary *)set {
	NSInteger count = [set[@"count"] integerValue];
	if (count == 0)
		count = (NSInteger)[set[@"stickers"] count];
	return count == 1 ? @"1 sticker" : [NSString stringWithFormat:@"%d stickers", (int)count];
}

- (UIButton *)addButton {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(0, 0, 54, 30);
	button.titleLabel.font = [UIFont boldSystemFontOfSize:13];
	[button setTitle:@"Add" forState:UIControlStateNormal];
	[button setTitleColor:[[TGTheme shared] accentColour] forState:UIControlStateNormal];
	[button setTitleColor:TGStickersRGB(0x8b97a5) forState:UIControlStateDisabled];
	[button addTarget:self action:@selector(addButtonTapped:)
	 forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (void)addButtonTapped:(UIButton *)button {
	NSInteger row = button.tag;
	if (row >= (NSInteger)self.sets.count)
		return;
	button.enabled = NO;
	[button setTitle:@"Added" forState:UIControlStateDisabled];
	[self installSet:self.sets[row] fromRow:row];
}

- (UITableViewCell *)plainCellForTable:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"plain"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"plain"];
	[[TGTheme shared] styleCell:cell];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	cell.imageView.image = nil;
	return cell;
}

- (UITableViewCell *)setCellForTable:(UITableView *)tableView
						 indexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"set"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"set"];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	}
	[[TGTheme shared] styleCell:cell];
	cell.shouldIndentWhileEditing = NO;
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.textColor = TGStickersRGB(0x888888);

	NSDictionary *set = [self setAtIndexPath:indexPath];
	cell.textLabel.text = set[@"title"];
	cell.detailTextLabel.text = [self countTextForSet:set];

	UIImage *cover = [self coverForSet:set atIndexPath:indexPath];
	if (cover){
		cell.imageView.image = cover;
	} else {
		NSString *title = set[@"title"];
		NSString *initials = title.length ? [[title substringToIndex:1] uppercaseString] : @"?";
		cell.imageView.image = [TGIcons avatarWithInitials:initials
													  size:kCoverSide
												  colourId:[set[@"id"] longLongValue]];
	}
	cell.imageView.contentMode = UIViewContentModeScaleAspectFit;

	if (self.page == TGStickersPageRoot){
		cell.accessoryView = nil;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else {
		BOOL installed = [set[@"installed"] boolValue];
		UIButton *add = [self addButton];
		add.tag = indexPath.row;
		add.enabled = !installed;
		if (installed)
			[add setTitle:@"Added" forState:UIControlStateDisabled];
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.accessoryView = add;
	}
	return cell;
}

- (UITableViewCell *)clearRecentCellForTable:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"clear"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"clear"];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
	}
	[[TGTheme shared] styleCell:cell];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.imageView.image = nil;
	cell.textLabel.text = @"Clear Recent Stickers";
	cell.textLabel.textColor = TGStickersRGB(0xd0021b);
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.page != TGStickersPageRoot)
		return [self setCellForTable:tableView indexPath:indexPath];

	if (indexPath.section == 1)
		return [self setCellForTable:tableView indexPath:indexPath];
	if (indexPath.section == 2)
		return [self clearRecentCellForTable:tableView];

	UITableViewCell *cell = [self plainCellForTable:tableView];
	if (indexPath.row == 0){
		cell.textLabel.text = @"Favourite Stickers";
		cell.detailTextLabel.text = self.favouriteCount
				? [NSString stringWithFormat:@"%d", (int)self.favouriteCount] : @"";
	} else if (indexPath.row == 1){
		cell.textLabel.text = @"Trending Stickers";
		cell.detailTextLabel.text = self.trendingNewCount
				? [NSString stringWithFormat:@"%d new", (int)self.trendingNewCount] : @"";
	} else {
		cell.textLabel.text = @"Archived Stickers";
		cell.detailTextLabel.text = self.archivedCount
				? [NSString stringWithFormat:@"%d", (int)self.archivedCount] : @"";
	}
	return cell;
}

#pragma mark - table delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (self.page != TGStickersPageRoot){
		NSDictionary *set = [self setAtIndexPath:indexPath];
		if (set)
			[self openSet:set];
		return;
	}

	if (indexPath.section == 0){
		if (indexPath.row == 0)
			[self openPage:TGStickersPageFavourites];
		else if (indexPath.row == 1)
			[self openPage:TGStickersPageTrending];
		else
			[self openPage:TGStickersPageArchived];
		return;
	}
	if (indexPath.section == 1){
		NSDictionary *set = [self setAtIndexPath:indexPath];
		if (set)
			[self openSet:set];
		return;
	}

	NSArray *actions = @[
		[[TGActionSheetAction alloc] initWithTitle:@"Clear Recent Stickers"
											action:@"clearRecent"
											  type:TGActionSheetActionTypeDestructive],
		[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
											  type:TGActionSheetActionTypeCancel]
	];
	[self presentSheetWithTitle:nil actions:actions];
}

- (void)tableView:(UITableView *)tableView
		willDisplayCell:(UITableViewCell *)cell
	  forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.page != TGStickersPageArchived)
		return;
	if (indexPath.row >= (NSInteger)self.sets.count - 3)
		[self loadMoreArchived];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return self.page == TGStickersPageRoot && indexPath.section == 1;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return self.page == TGStickersPageRoot && indexPath.section == 1;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
		   editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.reordering)
		return UITableViewCellEditingStyleNone;
	if (self.page == TGStickersPageRoot && indexPath.section == 1)
		return UITableViewCellEditingStyleDelete;
	return UITableViewCellEditingStyleNone;
}

- (NSString *)tableView:(UITableView *)tableView
		titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	return @"Remove";
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;
	NSDictionary *set = [self setAtIndexPath:indexPath];
	if (!set)
		return;
	self.actionSheetSet = set;

	NSArray *actions = @[
		[[TGActionSheetAction alloc] initWithTitle:@"Archive" action:@"archiveSet"],
		[[TGActionSheetAction alloc] initWithTitle:@"Remove" action:@"removeSet"
											  type:TGActionSheetActionTypeDestructive],
		[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
											  type:TGActionSheetActionTypeCancel]
	];
	[self presentSheetWithTitle:set[@"title"] actions:actions];
}

- (NSIndexPath *)tableView:(UITableView *)tableView
		targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
							 toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
	if (proposedDestinationIndexPath.section == 1)
		return proposedDestinationIndexPath;
	if (proposedDestinationIndexPath.section < 1)
		return [NSIndexPath indexPathForRow:0 inSection:1];
	return [NSIndexPath indexPathForRow:(NSInteger)self.sets.count - 1 inSection:1];
}

- (void)tableView:(UITableView *)tableView
		moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
			   toIndexPath:(NSIndexPath *)destinationIndexPath {
	if (sourceIndexPath.row >= (NSInteger)self.sets.count)
		return;
	NSDictionary *moved = self.sets[sourceIndexPath.row];
	[self.sets removeObjectAtIndex:sourceIndexPath.row];
	NSInteger target = destinationIndexPath.row;
	if (target > (NSInteger)self.sets.count)
		target = (NSInteger)self.sets.count;
	[self.sets insertObject:moved atIndex:target];
}

@end

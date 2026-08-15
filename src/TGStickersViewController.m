#import "TGStickersViewController.h"
#import "TGClient.h"
#import "TGClient+Stickers.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGActionSheet.h"
#import "TGAlertView.h"
#import "UIImage+WebP.h"

#define TGStickersRGB(rgb) [UIColor colorWithRed:(((rgb) >> 16) & 0xff) / 255.0f \
										   green:(((rgb) >> 8) & 0xff) / 255.0f \
											blue:((rgb) & 0xff) / 255.0f alpha:1.0f]

static const CGFloat kSetRowHeight = 51.0f;
static const CGFloat kPlainRowHeight = 44.0f;
static const CGFloat kCoverSide = 40.0f;

static const CGFloat kTileSide = 72.0f;
static const CGFloat kTileGap = 4.0f;
static const CGFloat kTileInset = 2.0f;
static const CGFloat kGridRowHeight = 78.0f;

static const CGFloat kTrendRowHeight = 78.0f;
static const CGFloat kTrendCoverSide = 34.0f;
static const NSInteger kTrendCoverCount = 5;

static const NSInteger kArchivedPageSize = 20;
static const NSInteger kTrendingPageSize = 20;

static const CGFloat kBottomBarHeight = 45.0f;
static const NSUInteger kCoverCacheLimit = 220;
static const NSUInteger kCoverCacheByteLimit = 8 * 1024 * 1024;

static const NSInteger TGStickersPageMasks = 5;
static const NSInteger TGStickersPageEmoji = 6;
static const NSInteger TGStickersPageEmojiTrending = 7;
static const NSInteger TGStickersPageEmojiArchived = 8;
static const NSInteger TGStickersPageMasksArchived = 9;
static const NSInteger TGStickersPageRecent = 10;
static const NSInteger TGStickersPagePremium = 11;

static const NSInteger kSearchLimit = 40;
static const NSInteger kPremiumLimit = 40;
static const CGFloat kSearchBarHeight = 44.0f;

static const NSInteger kRootSectionSettings = 0;
static const NSInteger kRootSectionPages = 1;
static const NSInteger kRootSectionSets = 2;
static const NSInteger kRootSectionRecent = 3;

static NSString *const TGStickerSuggestModeKey = @"TGStickerSuggestMode";
static NSString *const TGStickerLoopAnimatedKey = @"TGStickerLoopAnimated";

typedef NS_ENUM(NSInteger, TGStickerSuggestMode) {
	TGStickerSuggestModeAll = 0,
	TGStickerSuggestModeInstalled = 1,
	TGStickerSuggestModeNone = 2
};

static TGStickerSuggestMode TGStickersSuggestMode(void) {
	NSNumber *stored = [[NSUserDefaults standardUserDefaults]
			objectForKey:TGStickerSuggestModeKey];
	if (!stored)
		return TGStickerSuggestModeAll;
	NSInteger value = [stored integerValue];
	if (value < TGStickerSuggestModeAll || value > TGStickerSuggestModeNone)
		return TGStickerSuggestModeAll;
	return (TGStickerSuggestMode)value;
}

static NSString *TGStickersSuggestModeName(TGStickerSuggestMode mode) {
	switch (mode){
		case TGStickerSuggestModeInstalled: return @"My Sets";
		case TGStickerSuggestModeNone:      return @"None";
		default:                            return @"All Sets";
	}
}

static UIImage *TGStickersStretch(NSString *name, int leftCap) {
	UIImage *raw = [UIImage imageNamed:name];
	if (!raw)
		return nil;
	return [raw stretchableImageWithLeftCapWidth:leftCap topCapHeight:0];
}

static CGFloat TGStickersRetinaPixel(void) {
	return [UIScreen mainScreen].scale > 1.0f ? 0.5f : 0.0f;
}

static NSString *TGStickersCacheKey(NSInteger fileId, CGFloat side) {
	return [NSString stringWithFormat:@"%d-%d", (int)fileId, (int)side];
}

@interface TGStickerTilesCell : UITableViewCell

@property (nonatomic, strong) NSMutableArray *tiles;

- (UIButton *)tileAtIndex:(NSInteger)index;
- (void)hideTilesFromIndex:(NSInteger)index;

@end

@implementation TGStickerTilesCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.selectionStyle = UITableViewCellSelectionStyleNone;
	self.tiles = [NSMutableArray array];

	if (![[TGTheme shared] isFlat]){
		UIImage *plate = TGStickersStretch(@"Cell102.png", 1);
		if (plate)
			self.backgroundView = [[UIImageView alloc] initWithImage:plate];
	}
	self.backgroundColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] listBackgroundColour] : [UIColor whiteColor];
	return self;
}

- (UIButton *)tileAtIndex:(NSInteger)index {
	while ((NSInteger)self.tiles.count <= index){
		UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
		tile.backgroundColor = [UIColor clearColor];
		tile.titleLabel.font = [UIFont systemFontOfSize:34];
		tile.imageView.contentMode = UIViewContentModeScaleAspectFit;
		[self.contentView addSubview:tile];
		[self.tiles addObject:tile];
	}
	UIButton *tile = self.tiles[index];
	tile.hidden = NO;
	return tile;
}

- (void)hideTilesFromIndex:(NSInteger)index {
	for (NSInteger i = index; i < (NSInteger)self.tiles.count; i++){
		UIButton *tile = self.tiles[i];
		tile.hidden = YES;
		[tile setImage:nil forState:UIControlStateNormal];
		[tile setTitle:@"" forState:UIControlStateNormal];
	}
}

@end

@interface TGStickerTrendCell : UITableViewCell

@property (nonatomic, strong) UILabel *packTitleLabel;
@property (nonatomic, strong) UILabel *packCountLabel;
@property (nonatomic, strong) NSMutableArray *coverViews;
@property (nonatomic, strong) UIButton *addButton;

@end

@implementation TGStickerTrendCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.packTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.packTitleLabel.backgroundColor = [UIColor clearColor];
	self.packTitleLabel.font = [UIFont boldSystemFontOfSize:15];
	[self.contentView addSubview:self.packTitleLabel];

	self.packCountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.packCountLabel.backgroundColor = [UIColor clearColor];
	self.packCountLabel.font = [UIFont systemFontOfSize:13 + TGStickersRetinaPixel()];
	self.packCountLabel.textColor = TGStickersRGB(0x888888);
	[self.contentView addSubview:self.packCountLabel];

	self.coverViews = [NSMutableArray array];
	for (NSInteger i = 0; i < kTrendCoverCount; i++){
		UIImageView *cover = [[UIImageView alloc] initWithFrame:CGRectZero];
		cover.contentMode = UIViewContentModeScaleAspectFit;
		[self.contentView addSubview:cover];
		[self.coverViews addObject:cover];
	}

	self.addButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.addButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
	self.addButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
	[self.addButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[self.addButton setTitleColor:TGStickersRGB(0x8b97a5) forState:UIControlStateDisabled];
	[self.addButton setTitleShadowColor:
			[UIColor colorWithRed:0.05f green:0.15f blue:0.30f alpha:0.4f]
						 forState:UIControlStateNormal];
	[self.addButton setBackgroundImage:TGStickersStretch(@"GroupedActionButtonGreen.png", 33)
							  forState:UIControlStateNormal];
	[self.addButton setBackgroundImage:
			TGStickersStretch(@"GroupedActionButtonGreen_Highlighted.png", 33)
							  forState:UIControlStateHighlighted];
	[self.contentView addSubview:self.addButton];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat width = self.contentView.bounds.size.width;

	self.addButton.frame = CGRectMake(width - 80, 7, 70, 30);
	self.packTitleLabel.frame = CGRectMake(10, 6, width - 100, 20);
	self.packCountLabel.frame = CGRectMake(10, 24, width - 100, 16);

	NSInteger index = 0;
	for (UIImageView *cover in self.coverViews){
		cover.frame = CGRectMake(10 + index * (kTrendCoverSide + 14), 40,
				kTrendCoverSide, kTrendCoverSide);
		index++;
	}
}

@end

@interface TGStickersViewController () <UITableViewDataSource, UITableViewDelegate,
		UISearchBarDelegate>

@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIView *placeholder;
@property (nonatomic, strong) UILabel *placeholderTitle;
@property (nonatomic, strong) UILabel *placeholderBody;

@property (nonatomic, strong) NSMutableArray *sets;
@property (nonatomic, strong) NSArray *stickers;
@property (nonatomic, strong) NSMutableDictionary *covers;
@property (nonatomic, strong) NSMutableArray *coverOrder;
@property (nonatomic, assign) NSUInteger coverBytes;
@property (nonatomic, strong) NSMutableSet *coversInFlight;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIView *bottomBarLine;
@property (nonatomic, strong) UIButton *bottomButton;
@property (nonatomic, strong) NSArray *orderBeforeEdit;
@property (nonatomic, copy) void (^setStateChanged)(BOOL installed);

@property (nonatomic, assign) NSInteger favouriteCount;
@property (nonatomic, assign) NSInteger archivedCount;
@property (nonatomic, assign) NSInteger trendingNewCount;
@property (nonatomic, assign) NSInteger totalRemote;
@property (nonatomic, assign) NSInteger trendingOffset;
@property (nonatomic, assign) NSInteger maskCount;
@property (nonatomic, strong) NSSet *archivedIdsBeforeInstall;

@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL exhausted;
@property (nonatomic, assign) BOOL reordering;
@property (nonatomic, assign) BOOL installedHere;

@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, strong) NSDictionary *actionSheetSet;
@property (nonatomic, strong) NSDictionary *actionSheetSticker;

@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSMutableArray *setsBeforeSearch;
@property (nonatomic, assign) BOOL searching;
@property (nonatomic, assign) NSInteger recentCount;
@property (nonatomic, assign) NSInteger emojiSetCount;
@property (nonatomic, assign) NSInteger subpageTrendingCount;
@end

@implementation TGStickersViewController

- (instancetype)init {
	self = [super initWithNibName:nil bundle:nil];
	if (self){
		_page = TGStickersPageRoot;
		_sets = [NSMutableArray array];
		_covers = [NSMutableDictionary dictionary];
		_coverOrder = [NSMutableArray array];
		_coversInFlight = [NSMutableSet set];
	}
	return self;
}

- (BOOL)isGridPage {
	return self.page == TGStickersPageFavourites || self.page == TGStickersPageSet ||
			(NSInteger)self.page == TGStickersPageRecent ||
			(NSInteger)self.page == TGStickersPagePremium;
}

- (BOOL)isMaskPage {
	return (NSInteger)self.page == TGStickersPageMasks;
}

- (BOOL)isEmojiListPage {
	return (NSInteger)self.page == TGStickersPageEmoji;
}

- (BOOL)isTwoSectionListPage {
	return [self isMaskPage] || [self isEmojiListPage];
}

- (BOOL)isTrendingPage {
	return self.page == TGStickersPageTrending ||
			(NSInteger)self.page == TGStickersPageEmojiTrending;
}

- (BOOL)isArchivePage {
	return self.page == TGStickersPageArchived ||
			(NSInteger)self.page == TGStickersPageEmojiArchived ||
			(NSInteger)self.page == TGStickersPageMasksArchived;
}

- (BOOL)isReorderPage {
	return self.page == TGStickersPageRoot || [self isTwoSectionListPage];
}

- (BOOL)showsSearchBar {
	return [self isMaskPage] || (NSInteger)self.page == TGStickersPageEmojiTrending;
}

- (NSInteger)setsSection {
	if (self.page == TGStickersPageRoot)
		return kRootSectionSets;
	if ([self isTwoSectionListPage])
		return 1;
	return 0;
}

- (NSString *)pageTitle {
	if ([self isMaskPage])
		return @"Masks";
	if ([self isEmojiListPage])
		return @"Custom Emoji";
	if ((NSInteger)self.page == TGStickersPageEmojiTrending)
		return @"Trending Emoji";
	if ((NSInteger)self.page == TGStickersPageEmojiArchived)
		return @"Archived Emoji";
	if ((NSInteger)self.page == TGStickersPageMasksArchived)
		return @"Archived Masks";
	if ((NSInteger)self.page == TGStickersPageRecent)
		return @"Recently Used";
	if ((NSInteger)self.page == TGStickersPagePremium)
		return @"Premium Stickers";
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

	[self buildTable];

	if ([self showsSearchBar])
		[self buildSearchBar];

	if ([self showsBottomBar])
		[self buildBottomBar];

	[self buildPlaceholder];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
			UIActivityIndicatorViewStyleGray];
	self.spinner.hidesWhenStopped = YES;
	[self.view addSubview:self.spinner];

	if ([self isReorderPage])
		[self installEditButton];
	if (self.page == TGStickersPageSet){
		[self refreshSetBarButton];
		[self refreshBottomBar];
	}

	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self reload];

	if (self.page == TGStickersPageTrending || self.page == TGStickersPageSet)
		[self captureArchivedSnapshot];
}

- (void)buildSearchBar {
	self.searchBar = [[UISearchBar alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, kSearchBarHeight)];
	self.searchBar.delegate = self;
	self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.searchBar.placeholder = [self isMaskPage] ? @"Search Masks" : @"Search Emoji Sets";
	self.table.tableHeaderView = self.searchBar;
}

- (void)captureArchivedSnapshot {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] archivedStickerSetsFromSetId:0 limit:kArchivedPageSize
										 completion:^(NSArray *sets, __unused NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || !sets)
			return;
		NSMutableSet *ids = [NSMutableSet set];
		for (NSDictionary *set in sets)
			if (set[@"id"])
				[ids addObject:set[@"id"]];
		strongSelf.archivedIdsBeforeInstall = ids;
	}];
}

- (void)checkAutoArchivedSets {
	NSSet *before = self.archivedIdsBeforeInstall;
	if (!before)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] archivedStickerSetsFromSetId:0 limit:kArchivedPageSize
										 completion:^(NSArray *sets, __unused NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || !sets)
			return;

		NSMutableSet *ids = [NSMutableSet set];
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *set in sets){
			if (!set[@"id"])
				continue;
			[ids addObject:set[@"id"]];
			if (![before containsObject:set[@"id"]] && [set[@"title"] length])
				[titles addObject:set[@"title"]];
		}
		strongSelf.archivedIdsBeforeInstall = ids;
		if (titles.count == 0)
			return;

		NSString *names;
		if (titles.count == 1)
			names = titles[0];
		else if (titles.count == 2)
			names = [NSString stringWithFormat:@"%@ and %@", titles[0], titles[1]];
		else
			names = [NSString stringWithFormat:@"%@, %@ and %d more", titles[0], titles[1],
					(int)(titles.count - 2)];

		NSString *title = [NSString stringWithFormat:
				@"There was no room for another set, so %@ moved to the archive.", names];
		NSArray *actions = @[
			[[TGActionSheetAction alloc] initWithTitle:@"Show Archive" action:@"openArchive"],
			[[TGActionSheetAction alloc] initWithTitle:@"OK" action:@"cancel"
												  type:TGActionSheetActionTypeCancel]
		];
		[strongSelf presentSheetWithTitle:title actions:actions];
	}];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	if ([self isReorderPage] && self.loaded && !self.reordering && !self.searching)
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
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runSearch) object:nil];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutChrome];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	[self flushCovers];
	[self.table reloadData];
}

#pragma mark - chrome

- (void)buildTable {
	UITableViewStyle style = [self isGridPage] ? UITableViewStylePlain
											  : UITableViewStyleGrouped;
	self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:style];
	self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.rowHeight = [self isGridPage] ? kGridRowHeight : kPlainRowHeight;
	self.table.separatorColor = [[TGTheme shared] separatorColour];

	if ([self isGridPage]){
		self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
		self.table.backgroundColor = [[TGTheme shared] isDark]
				? [[TGTheme shared] listBackgroundColour] : [UIColor whiteColor];
		self.table.tableFooterView = [self gridFooterView];
	} else {
		self.table.backgroundColor = [[TGTheme shared] listBackgroundColour];
	}
	if ([[TGTheme shared] isDark])
		self.table.backgroundView = nil;
	[self.view addSubview:self.table];
}

- (UIView *)gridFooterView {
	UIImage *plate = TGStickersStretch(@"Footer.png", 1);
	if (!plate || [[TGTheme shared] isFlat])
		return [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 1)];
	UIImageView *footer = [[UIImageView alloc] initWithImage:plate];
	footer.frame = CGRectMake(0, 0, self.view.bounds.size.width, plate.size.height);
	footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	return footer;
}

- (BOOL)showsBottomBar {
	return self.page == TGStickersPageSet;
}

- (BOOL)currentSetInstalled {
	return [self.set[@"installed"] boolValue];
}

- (void)buildBottomBar {
	self.bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
	self.bottomBar.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleTopMargin;

	UIImage *plate = TGStickersStretch(@"Footer.png", 1);
	if (plate && ![[TGTheme shared] isFlat] && ![[TGTheme shared] isDark])
		self.bottomBar.backgroundColor = [UIColor colorWithPatternImage:plate];
	else
		self.bottomBar.backgroundColor = [[TGTheme shared] isDark]
				? [[TGTheme shared] listBackgroundColour] : TGStickersRGB(0xf7f7f7);

	self.bottomBarLine = [[UIView alloc] initWithFrame:CGRectZero];
	self.bottomBarLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.bottomBarLine.backgroundColor = [[TGTheme shared] separatorColour];
	[self.bottomBar addSubview:self.bottomBarLine];

	self.bottomButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.bottomButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.bottomButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
	self.bottomButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
	[self.bottomButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[self.bottomButton addTarget:self action:@selector(bottomButtonTapped)
				forControlEvents:UIControlEventTouchUpInside];
	[self.bottomBar addSubview:self.bottomButton];

	self.bottomBar.hidden = YES;
	[self.view addSubview:self.bottomBar];
}

- (void)refreshBottomBar {
	if (!self.bottomBar)
		return;

	BOOL installed = [self currentSetInstalled];
	NSString *asset = installed ? @"MenuRedButton" : @"GroupedActionButtonGreen";
	int cap = installed ? 12 : 33;
	[self.bottomButton setBackgroundImage:
			TGStickersStretch([asset stringByAppendingString:@".png"], cap)
								 forState:UIControlStateNormal];
	[self.bottomButton setBackgroundImage:
			TGStickersStretch([asset stringByAppendingString:@"_Highlighted.png"], cap)
								 forState:UIControlStateHighlighted];
	UIColor *shadow = installed
			? [UIColor colorWithRed:0.64f green:0.06f blue:0.04f alpha:0.2f]
			: [UIColor colorWithRed:0.05f green:0.15f blue:0.30f alpha:0.4f];
	[self.bottomButton setTitleShadowColor:shadow forState:UIControlStateNormal];

	NSInteger count = (NSInteger)self.stickers.count;
	if (count == 0)
		count = [self.set[@"count"] integerValue];
	NSString *noun = count == 1 ? @"Sticker" : @"Stickers";
	NSString *title;
	if (count > 0)
		title = [NSString stringWithFormat:@"%@ %d %@", installed ? @"Remove" : @"Add",
				(int)count, noun];
	else
		title = installed ? @"Remove Stickers" : @"Add Stickers";
	[self.bottomButton setTitle:title forState:UIControlStateNormal];

	self.bottomBar.hidden = !self.loaded || self.table.hidden;
	[self layoutChrome];
}

- (void)bottomButtonTapped {
	[self toggleCurrentSet];
}

- (void)layoutBottomBar {
	if (!self.bottomBar)
		return;
	CGFloat width = self.view.bounds.size.width;
	CGFloat height = self.view.bounds.size.height;
	self.bottomBar.frame = CGRectMake(0, height - kBottomBarHeight, width, kBottomBarHeight);
	self.bottomBarLine.frame = CGRectMake(0, 0, width, 1.0f / [UIScreen mainScreen].scale);

	CGFloat buttonHeight = [self currentSetInstalled] ? 45 : 43;
	CGFloat buttonWidth = width - 20;
	self.bottomButton.frame = CGRectMake(10,
			floorf((kBottomBarHeight - buttonHeight) / 2), buttonWidth, buttonHeight);

	UIEdgeInsets insets = self.table.contentInset;
	insets.bottom = self.bottomBar.hidden ? 0 : kBottomBarHeight;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
}

- (void)buildPlaceholder {
	self.placeholder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 260, 70)];
	self.placeholder.backgroundColor = [UIColor clearColor];
	self.placeholder.hidden = YES;

	BOOL plain = ![[TGTheme shared] isFlat] && ![[TGTheme shared] isDark];
	UIColor *colour = [[TGTheme shared] isDark] ? [[TGTheme shared] sectionHeaderColour]
												: TGStickersRGB(0x8694a4);

	self.placeholderTitle = [[UILabel alloc] initWithFrame:CGRectZero];
	self.placeholderTitle.backgroundColor = [UIColor clearColor];
	self.placeholderTitle.font = [UIFont boldSystemFontOfSize:14];
	self.placeholderTitle.textColor = colour;
	self.placeholderTitle.textAlignment = NSTextAlignmentCenter;
	if (plain){
		self.placeholderTitle.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.5f];
		self.placeholderTitle.shadowOffset = CGSizeMake(0, 1);
	}
	[self.placeholder addSubview:self.placeholderTitle];

	self.placeholderBody = [[UILabel alloc] initWithFrame:CGRectZero];
	self.placeholderBody.backgroundColor = [UIColor clearColor];
	self.placeholderBody.font = [UIFont systemFontOfSize:14];
	self.placeholderBody.textColor = colour;
	self.placeholderBody.textAlignment = NSTextAlignmentCenter;
	self.placeholderBody.lineBreakMode = NSLineBreakByWordWrapping;
	self.placeholderBody.numberOfLines = 0;
	if (plain){
		self.placeholderBody.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.5f];
		self.placeholderBody.shadowOffset = CGSizeMake(0, 1);
	}
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
	BOOL installed = [self currentSetInstalled];
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
		CGFloat containerWidth = 260;
		CGSize titleSize = [self.placeholderTitle.text
				sizeWithFont:self.placeholderTitle.font];
		CGSize bodySize = [self.placeholderBody.text
				sizeWithFont:self.placeholderBody.font
		   constrainedToSize:CGSizeMake(containerWidth, 1000)
			   lineBreakMode:NSLineBreakByWordWrapping];

		self.placeholderTitle.frame = CGRectMake(0, 0, containerWidth, titleSize.height);
		self.placeholderBody.frame = CGRectMake(0, 26, containerWidth, bodySize.height);
		CGFloat containerHeight = 26 + bodySize.height;
		self.placeholder.frame = CGRectMake(floorf((width - containerWidth) / 2),
				floorf((height - containerHeight) / 2), containerWidth, containerHeight);
	}

	[self layoutBottomBar];
}

#pragma mark - state

- (void)showLoading {
	self.placeholder.hidden = YES;
	self.table.hidden = (self.sets.count == 0 && self.stickers.count == 0 &&
			self.page != TGStickersPageRoot);
	[self.spinner startAnimating];
	[self layoutChrome];
}

- (void)showTitle:(NSString *)title body:(NSString *)body {
	[self.spinner stopAnimating];
	self.placeholderTitle.text = title;
	self.placeholderBody.text = body;
	self.placeholder.hidden = NO;
	self.table.hidden = YES;
	self.bottomBar.hidden = YES;
	[self layoutChrome];
}

- (void)showContent {
	[self.spinner stopAnimating];
	self.placeholder.hidden = YES;
	self.table.hidden = NO;
	self.bottomBar.hidden = ![self showsBottomBar];
	[self layoutChrome];
}

- (void)showFailure {
	[self showTitle:@"No Stickers"
			   body:@"The sticker list could not be loaded. Check the connection and try again."];
}

#pragma mark - loading

- (void)reload {
	if (self.searching)
		return;
	if ([self isMaskPage]){
		[self reloadMasks];
		return;
	}
	if ([self isEmojiListPage]){
		[self reloadEmojiSets];
		return;
	}
	if ([self isTrendingPage]){
		[self reloadTrending];
		return;
	}
	if ([self isArchivePage]){
		[self reloadArchived];
		return;
	}
	if ((NSInteger)self.page == TGStickersPageRecent){
		[self reloadRecent];
		return;
	}
	if ((NSInteger)self.page == TGStickersPagePremium){
		[self reloadPremium];
		return;
	}
	switch (self.page){
		case TGStickersPageFavourites: [self reloadFavourites]; break;
		case TGStickersPageSet:        [self reloadSet]; break;
		default:                       [self reloadRoot]; break;
	}
}

- (void)fetchArchivedFromSetId:(int64_t)offsetSetId
					completion:(void (^)(NSArray *sets, NSInteger totalCount))completion {
	if ((NSInteger)self.page == TGStickersPageEmojiArchived)
		[[TGClient shared] archivedEmojiStickerSetsFromSetId:offsetSetId
													   limit:kArchivedPageSize
												  completion:completion];
	else if ((NSInteger)self.page == TGStickersPageMasksArchived)
		[[TGClient shared] archivedMaskStickerSetsFromSetId:offsetSetId
													  limit:kArchivedPageSize
												 completion:completion];
	else
		[[TGClient shared] archivedStickerSetsFromSetId:offsetSetId limit:kArchivedPageSize
											 completion:completion];
}

- (void)fetchTrendingFromOffset:(NSInteger)offset
					 completion:(void (^)(NSArray *sets, NSInteger totalCount))completion {
	if ((NSInteger)self.page == TGStickersPageEmojiTrending)
		[[TGClient shared] trendingEmojiStickerSetsWithOffset:offset limit:kTrendingPageSize
												   completion:completion];
	else
		[[TGClient shared] trendingStickerSetsWithOffset:offset limit:kTrendingPageSize
											  completion:completion];
}

- (void)reloadEmojiSets {
	if (!self.loaded)
		[self showLoading];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] installedEmojiStickerSetsWithCompletion:^(NSArray *sets){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		if (!sets && strongSelf.sets.count == 0){
			[strongSelf showFailure];
			return;
		}
		if (sets)
			strongSelf.sets = [NSMutableArray arrayWithArray:sets];
		strongSelf.emojiSetCount = (NSInteger)strongSelf.sets.count;
		[strongSelf showContent];
		[strongSelf.table reloadData];
		[strongSelf installEditButton];
	}];

	[[TGClient shared] archivedEmojiStickerSetsFromSetId:0 limit:1
											  completion:^(NSArray *sets, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.archivedCount = total > 0 ? total : (NSInteger)sets.count;
		[strongSelf reloadSubpageSection];
	}];

	[[TGClient shared] trendingEmojiStickerSetsWithOffset:0 limit:kTrendingPageSize
											   completion:^(NSArray *sets, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.subpageTrendingCount = total > 0 ? total : (NSInteger)sets.count;
		[strongSelf reloadSubpageSection];
	}];
}

- (void)reloadSubpageSection {
	if (![self isTwoSectionListPage] || self.table.hidden || !self.loaded)
		return;
	if ([self.table numberOfSections] < 2)
		return;
	[self.table reloadSections:[NSIndexSet indexSetWithIndex:0]
			  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)reloadRecent {
	[self showLoading];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] recentStickersAttached:NO completion:^(NSArray *stickers){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		if (!stickers){
			[strongSelf showFailure];
			return;
		}
		strongSelf.stickers = stickers;
		strongSelf.recentCount = (NSInteger)stickers.count;
		if (stickers.count == 0){
			[strongSelf showTitle:@"No Recent Stickers"
							 body:@"Stickers you send show up here, ready to be sent again."];
			return;
		}
		[strongSelf showContent];
		[strongSelf.table reloadData];
	}];
}

- (void)reloadPremium {
	[self showLoading];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] premiumStickersWithLimit:kPremiumLimit completion:^(NSArray *stickers){
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
			[strongSelf showTitle:@"No Premium Stickers"
							 body:@"There are no premium stickers in the sets you have installed."];
			return;
		}
		[strongSelf showContent];
		[strongSelf.table reloadData];
	}];
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

	[[TGClient shared] installedMaskStickerSetsWithCompletion:^(NSArray *sets){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSInteger count = (NSInteger)sets.count;
		if (count == strongSelf.maskCount)
			return;
		strongSelf.maskCount = count;
		if (strongSelf.table.hidden || !strongSelf.loaded || strongSelf.reordering)
			return;
		[strongSelf.table reloadData];
	}];

	[[TGClient shared] recentStickersAttached:NO completion:^(NSArray *stickers){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.recentCount = (NSInteger)stickers.count;
		[strongSelf reloadFirstSection];
	}];

	[[TGClient shared] installedEmojiStickerSetsWithCompletion:^(NSArray *sets){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.emojiSetCount = (NSInteger)sets.count;
		[strongSelf reloadFirstSection];
	}];

	if (![[NSUserDefaults standardUserDefaults] objectForKey:TGStickerSuggestModeKey]){
		[[TGClient shared] stickerSuggestionEnabledWithCompletion:^(BOOL enabled){
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf)
				return;
			if ([[NSUserDefaults standardUserDefaults] objectForKey:TGStickerSuggestModeKey])
				return;
			[[NSUserDefaults standardUserDefaults]
					setInteger:(enabled ? TGStickerSuggestModeAll : TGStickerSuggestModeNone)
						forKey:TGStickerSuggestModeKey];
			[[NSUserDefaults standardUserDefaults] synchronize];
			[strongSelf reloadSettingsSection];
		}];
	}
}

- (void)reloadSettingsSection {
	if (self.page != TGStickersPageRoot || self.table.hidden || !self.loaded)
		return;
	[self.table reloadSections:[NSIndexSet indexSetWithIndex:kRootSectionSettings]
			  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)reloadMasks {
	if (!self.loaded)
		[self showLoading];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] installedMaskStickerSetsWithCompletion:^(NSArray *sets){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		if (!sets && strongSelf.sets.count == 0){
			[strongSelf showFailure];
			return;
		}
		if (sets)
			strongSelf.sets = [NSMutableArray arrayWithArray:sets];
		strongSelf.maskCount = (NSInteger)strongSelf.sets.count;
		[strongSelf showContent];
		[strongSelf.table reloadData];
		[strongSelf installEditButton];
	}];

	[[TGClient shared] archivedMaskStickerSetsFromSetId:0 limit:1
											 completion:^(NSArray *sets, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.archivedCount = total > 0 ? total : (NSInteger)sets.count;
		[strongSelf reloadSubpageSection];
	}];
}

- (void)reloadFirstSection {
	if (self.page != TGStickersPageRoot || self.table.hidden || !self.loaded)
		return;
	[self.table reloadSections:[NSIndexSet indexSetWithIndex:kRootSectionPages]
			  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)reloadTrending {
	[self showLoading];
	__weak typeof(self) weakSelf = self;
	[self fetchTrendingFromOffset:0 completion:^(NSArray *sets, NSInteger total){
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
		strongSelf.trendingOffset = (NSInteger)sets.count;
		strongSelf.exhausted = ((NSInteger)sets.count < kTrendingPageSize ||
				(total > 0 && strongSelf.trendingOffset >= total));
		if (strongSelf.sets.count == 0 && ![strongSelf showsSearchBar]){
			[strongSelf showTitle:@"No Trending Stickers"
							 body:@"There is nothing featured right now. Come back later."];
			return;
		}
		[strongSelf showContent];
		[strongSelf.table reloadData];
		[strongSelf markShownSetsViewed];
	}];
}

- (void)loadMoreTrending {
	if (self.searching)
		return;
	if (self.loadingMore || self.exhausted || self.sets.count == 0)
		return;
	self.loadingMore = YES;

	__weak typeof(self) weakSelf = self;
	[self fetchTrendingFromOffset:self.trendingOffset
					   completion:^(NSArray *sets, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loadingMore = NO;
		if (total > 0)
			strongSelf.totalRemote = total;
		if (sets.count == 0){
			strongSelf.exhausted = YES;
			return;
		}

		NSMutableSet *known = [NSMutableSet set];
		for (NSDictionary *existing in strongSelf.sets)
			if (existing[@"id"])
				[known addObject:existing[@"id"]];
		NSMutableArray *fresh = [NSMutableArray array];
		for (NSDictionary *set in sets)
			if (!set[@"id"] || ![known containsObject:set[@"id"]])
				[fresh addObject:set];

		strongSelf.trendingOffset += (NSInteger)sets.count;
		strongSelf.exhausted = ((NSInteger)sets.count < kTrendingPageSize ||
				(total > 0 && strongSelf.trendingOffset >= total));
		if (fresh.count == 0){
			[strongSelf loadMoreTrending];
			return;
		}
		[strongSelf.sets addObjectsFromArray:fresh];
		[strongSelf.table reloadData];
		[strongSelf markSetsViewed:fresh];
	}];
}

- (void)markShownSetsViewed {
	[self markSetsViewed:self.sets];
}

- (void)markSetsViewed:(NSArray *)sets {
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *set in sets)
		if (![set[@"viewed"] boolValue] && set[@"id"])
			[ids addObject:set[@"id"]];
	if (ids.count)
		[[TGClient shared] markTrendingStickerSetsViewed:ids];
}

- (NSString *)emptyArchiveTitle {
	if ((NSInteger)self.page == TGStickersPageEmojiArchived)
		return @"No Archived Emoji";
	if ((NSInteger)self.page == TGStickersPageMasksArchived)
		return @"No Archived Masks";
	return @"No Archived Stickers";
}

- (NSString *)emptyArchiveBody {
	if ((NSInteger)self.page == TGStickersPageEmojiArchived)
		return @"Custom emoji sets you archive are kept here, ready to be put back.";
	if ((NSInteger)self.page == TGStickersPageMasksArchived)
		return @"Mask sets you archive are kept here, ready to be put back.";
	return @"Sticker sets you archive are kept here, ready to be put back.";
}

- (void)reloadArchived {
	[self showLoading];
	__weak typeof(self) weakSelf = self;
	[self fetchArchivedFromSetId:0 completion:^(NSArray *sets, NSInteger total){
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
			[strongSelf showTitle:[strongSelf emptyArchiveTitle]
							 body:[strongSelf emptyArchiveBody]];
			return;
		}
		[strongSelf showContent];
		[strongSelf.table reloadData];
	}];
}

- (void)loadMoreArchived {
	if (self.searching)
		return;
	if (self.loadingMore || self.exhausted || self.sets.count == 0)
		return;
	self.loadingMore = YES;
	int64_t last = [[self.sets lastObject][@"id"] longLongValue];

	__weak typeof(self) weakSelf = self;
	[self fetchArchivedFromSetId:last completion:^(NSArray *sets, NSInteger total){
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
		[strongSelf.table reloadData];
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
		NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:set];
		if (strongSelf.installedHere)
			merged[@"installed"] = @YES;
		strongSelf.set = merged;
		strongSelf.title = [strongSelf pageTitle];
		strongSelf.stickers = set[@"stickers"];
		[strongSelf refreshSetBarButton];
		if (strongSelf.stickers.count == 0){
			[strongSelf showTitle:@"Empty Set" body:@"This sticker set has no stickers in it."];
			[strongSelf refreshBottomBar];
			return;
		}
		[strongSelf showContent];
		[strongSelf.table reloadData];
		[strongSelf refreshBottomBar];
	}];
}

#pragma mark - images

- (void)flushCovers {
	[self.covers removeAllObjects];
	[self.coverOrder removeAllObjects];
	self.coverBytes = 0;
}

- (NSUInteger)byteCostOfImage:(UIImage *)image {
	CGImageRef bitmap = image.CGImage;
	if (!bitmap)
		return 4096;
	return CGImageGetWidth(bitmap) * CGImageGetHeight(bitmap) * 4;
}

- (void)storeCover:(UIImage *)image forKey:(NSString *)key {
	if (!image || !key)
		return;

	UIImage *existing = self.covers[key];
	if (existing){
		self.coverBytes -= MIN(self.coverBytes, [self byteCostOfImage:existing]);
		[self.coverOrder removeObject:key];
	}

	self.covers[key] = image;
	[self.coverOrder addObject:key];
	self.coverBytes += [self byteCostOfImage:image];

	while (self.coverOrder.count > 1 &&
		   (self.coverBytes > kCoverCacheByteLimit ||
			self.covers.count > kCoverCacheLimit)){
		NSString *oldest = self.coverOrder[0];
		UIImage *evicted = self.covers[oldest];
		self.coverBytes -= MIN(self.coverBytes, [self byteCostOfImage:evicted]);
		[self.covers removeObjectForKey:oldest];
		[self.coverOrder removeObjectAtIndex:0];
	}
}

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

- (BOOL)stickerIsStill:(NSDictionary *)sticker {
	return !([sticker[@"isAnimated"] boolValue] || [sticker[@"isVideo"] boolValue]);
}

- (UIImage *)imageForFileId:(NSInteger)fileId side:(CGFloat)side
				  indexPath:(NSIndexPath *)indexPath {
	if (fileId == 0)
		return nil;
	NSString *key = TGStickersCacheKey(fileId, side);
	UIImage *cached = self.covers[key];
	if (cached)
		return cached;
	if ([self.coversInFlight containsObject:key])
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
		UIImage *small = nil;
		@autoreleasepool {
			UIImage *decoded = [UIImage convertFromWebP:path compressedData:nil error:nil];
			small = [strongSelf scale:decoded toSide:side];
		}
		if (!small)
			return;
		[strongSelf storeCover:small forKey:key];
		if (!indexPath)
			return;
		if (indexPath.section >= [strongSelf.table numberOfSections])
			return;
		if (indexPath.row >= [strongSelf.table numberOfRowsInSection:indexPath.section])
			return;
		if (![strongSelf.table cellForRowAtIndexPath:indexPath])
			return;
		[strongSelf.table reloadRowsAtIndexPaths:@[indexPath]
								withRowAnimation:UITableViewRowAnimationNone];
	}];
	return nil;
}

- (NSInteger)coverFileIdForSet:(NSDictionary *)set {
	NSArray *covers = set[@"covers"];
	for (NSDictionary *sticker in covers){
		if (![self stickerIsStill:sticker])
			continue;
		return [sticker[@"fileId"] integerValue];
	}
	return 0;
}

- (UIImage *)coverForSet:(NSDictionary *)set atIndexPath:(NSIndexPath *)indexPath {
	return [self imageForFileId:[self coverFileIdForSet:set] side:kCoverSide
					  indexPath:indexPath];
}

#pragma mark - grid

- (NSInteger)gridColumns {
	CGFloat width = self.table.bounds.size.width;
	if (width <= 0)
		width = self.view.bounds.size.width;
	NSInteger columns = (NSInteger)floorf((width - kTileInset * 2 + kTileGap) /
			(kTileSide + kTileGap));
	if (columns < 3)
		columns = 3;
	return columns;
}

- (NSInteger)gridRowCount {
	NSInteger columns = [self gridColumns];
	return ((NSInteger)self.stickers.count + columns - 1) / columns;
}

- (UITableViewCell *)tilesCellForTable:(UITableView *)tableView
							 indexPath:(NSIndexPath *)indexPath {
	TGStickerTilesCell *cell = (TGStickerTilesCell *)
			[tableView dequeueReusableCellWithIdentifier:@"tiles"];
	if (!cell)
		cell = [[TGStickerTilesCell alloc] initWithStyle:UITableViewCellStyleDefault
										 reuseIdentifier:@"tiles"];

	NSInteger columns = [self gridColumns];
	NSInteger first = indexPath.row * columns;
	NSInteger placed = 0;

	for (NSInteger column = 0; column < columns; column++){
		NSInteger index = first + column;
		if (index >= (NSInteger)self.stickers.count)
			break;
		NSDictionary *sticker = self.stickers[index];

		UIButton *tile = [cell tileAtIndex:column];
		tile.frame = CGRectMake(kTileInset + column * (kTileSide + kTileGap), 3,
				kTileSide, kTileSide);
		tile.tag = index;
		[tile removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
		[tile addTarget:self action:@selector(tileTapped:)
	   forControlEvents:UIControlEventTouchUpInside];

		UIImage *image = nil;
		if ([self stickerIsStill:sticker])
			image = [self imageForFileId:[sticker[@"fileId"] integerValue] side:kTileSide
							   indexPath:indexPath];
		if (image){
			[tile setTitle:@"" forState:UIControlStateNormal];
			[tile setImage:image forState:UIControlStateNormal];
		} else {
			[tile setImage:nil forState:UIControlStateNormal];
			[tile setTitle:sticker[@"emoji"] forState:UIControlStateNormal];
		}
		placed++;
	}
	[cell hideTilesFromIndex:placed];
	return cell;
}

- (void)tileTapped:(UIButton *)tile {
	if (![self isGridPage])
		return;
	NSInteger index = tile.tag;
	if (index >= (NSInteger)self.stickers.count)
		return;
	NSDictionary *sticker = self.stickers[index];
	self.actionSheetSticker = sticker;

	if (self.page == TGStickersPageFavourites){
		NSArray *actions = @[
			[[TGActionSheetAction alloc] initWithTitle:@"Remove from Favourites"
												action:@"removeFavourite"
												  type:TGActionSheetActionTypeDestructive],
			[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
												  type:TGActionSheetActionTypeCancel]
		];
		[self presentSheetWithTitle:nil actions:actions];
		return;
	}

	NSInteger fileId = [sticker[@"fileId"] integerValue];
	if (fileId == 0)
		return;
	BOOL recent = ((NSInteger)self.page == TGStickersPageRecent);

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] isStickerFavoriteWithFileId:fileId completion:^(BOOL favourite){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || strongSelf.actionSheetSticker != sticker)
			return;
		NSMutableArray *actions = [NSMutableArray array];
		if (favourite)
			[actions addObject:[[TGActionSheetAction alloc]
					initWithTitle:@"Remove from Favourites" action:@"unfavouriteSticker"]];
		else
			[actions addObject:[[TGActionSheetAction alloc]
					initWithTitle:@"Add to Favourites" action:@"favouriteSticker"]];
		if (recent)
			[actions addObject:[[TGActionSheetAction alloc]
					initWithTitle:@"Remove from Recent" action:@"removeRecent"
							 type:TGActionSheetActionTypeDestructive]];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
																 type:TGActionSheetActionTypeCancel]];
		[strongSelf presentSheetWithTitle:sticker[@"emoji"] actions:actions];
	}];
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
	else if ([action isEqualToString:@"restoreSet"] && set)
		[self restoreArchivedSet:set];
	else if ([action isEqualToString:@"removeSet"] && set)
		[self uninstallSet:set];
	else if ([action isEqualToString:@"clearRecent"])
		[self clearRecent];
	else if ([action isEqualToString:@"removeFavourite"])
		[self removeCurrentFavourite];
	else if ([action isEqualToString:@"openArchive"])
		[self openPage:TGStickersPageArchived];
	else if ([action isEqualToString:@"suggestAll"])
		[self applySuggestMode:TGStickerSuggestModeAll];
	else if ([action isEqualToString:@"suggestInstalled"])
		[self applySuggestMode:TGStickerSuggestModeInstalled];
	else if ([action isEqualToString:@"suggestNone"])
		[self applySuggestMode:TGStickerSuggestModeNone];
	else if ([action isEqualToString:@"copyLink"] && set)
		[self copyLinkForSet:set];
	else if ([action isEqualToString:@"favouriteSticker"])
		[self setCurrentStickerFavourite:YES];
	else if ([action isEqualToString:@"unfavouriteSticker"])
		[self setCurrentStickerFavourite:NO];
	else if ([action isEqualToString:@"removeRecent"])
		[self removeCurrentRecent];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:title message:message
										  cancelButtonTitle:@"OK" okButtonTitle:nil
											completionBlock:nil];
	[alert show];
}

- (void)copyLinkForSet:(NSDictionary *)set {
	int64_t identifier = [set[@"id"] longLongValue];
	if (identifier == 0)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] stickerSetNameForId:identifier completion:^(NSString *name){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (!name.length){
			[strongSelf showAlertWithTitle:@"Sticker Set"
								   message:@"The link for this set could not be fetched."];
			return;
		}
		NSString *link = [NSString stringWithFormat:@"https://telegram.me/addstickers/%@", name];
		[UIPasteboard generalPasteboard].string = link;
		[strongSelf showAlertWithTitle:@"Link Copied" message:link];
	}];
}

- (void)setCurrentStickerFavourite:(BOOL)favourite {
	NSDictionary *sticker = self.actionSheetSticker;
	self.actionSheetSticker = nil;
	NSInteger fileId = [sticker[@"fileId"] integerValue];
	if (fileId == 0)
		return;

	if (favourite)
		[[TGClient shared] addFavoriteStickerWithFileId:fileId];
	else
		[[TGClient shared] removeFavoriteStickerWithFileId:fileId];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] isStickerFavoriteWithFileId:fileId completion:^(BOOL isFavourite){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (isFavourite != favourite){
			[strongSelf showAlertWithTitle:@"Favourites"
								   message:@"The favourites list could not be updated."];
			return;
		}
		[strongSelf showAlertWithTitle:@"Favourites"
							   message:favourite ? @"Sticker added to favourites."
												 : @"Sticker removed from favourites."];
	}];
}

- (void)removeCurrentRecent {
	NSDictionary *sticker = self.actionSheetSticker;
	self.actionSheetSticker = nil;
	if (!sticker)
		return;
	[[TGClient shared] removeRecentStickerWithFileId:[sticker[@"fileId"] integerValue]];

	NSMutableArray *remaining = [NSMutableArray arrayWithArray:self.stickers];
	[remaining removeObject:sticker];
	self.stickers = remaining;
	self.recentCount = (NSInteger)remaining.count;
	if (remaining.count == 0){
		[self showTitle:@"No Recent Stickers"
				   body:@"Stickers you send show up here, ready to be sent again."];
		return;
	}
	[self.table reloadData];
}

- (void)applySuggestMode:(TGStickerSuggestMode)mode {
	[[NSUserDefaults standardUserDefaults] setInteger:mode forKey:TGStickerSuggestModeKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[self reloadSettingsSection];
}

- (void)presentSuggestModeSheet {
	NSArray *actions = @[
		[[TGActionSheetAction alloc] initWithTitle:@"All Sets" action:@"suggestAll"],
		[[TGActionSheetAction alloc] initWithTitle:@"My Sets" action:@"suggestInstalled"],
		[[TGActionSheetAction alloc] initWithTitle:@"None" action:@"suggestNone"],
		[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
											  type:TGActionSheetActionTypeCancel]
	];
	[self presentSheetWithTitle:@"Suggest Stickers by Emoji" actions:actions];
}

- (void)loopAnimatedToggled:(UISwitch *)toggle {
	[[NSUserDefaults standardUserDefaults] setBool:toggle.on forKey:TGStickerLoopAnimatedKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
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
	NSUInteger index = [self.sets indexOfObject:set];
	if (index == NSNotFound)
		return;
	if ([self isArchivePage]){
		[self removeArchivedRow:(NSInteger)index];
	} else {
		[self.sets removeObjectAtIndex:index];
		[self.table reloadData];
		[self installEditButton];
	}
	[[TGClient shared] uninstallStickerSet:[set[@"id"] longLongValue] completion:^(BOOL ok){
		if (!ok)
			return;
	}];
}

- (void)installSet:(NSDictionary *)set fromRow:(NSInteger)row button:(UIButton *)button {
	__weak typeof(self) weakSelf = self;
	__weak UIButton *weakButton = button;
	[[TGClient shared] installStickerSet:[set[@"id"] longLongValue] completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		__strong UIButton *strongButton = weakButton;
		if (!strongSelf)
			return;
		if (!ok){
			strongButton.enabled = YES;
			[strongButton setTitle:[strongSelf addButtonTitle] forState:UIControlStateNormal];
			return;
		}
		[strongSelf checkAutoArchivedSets];
		if (row >= (NSInteger)strongSelf.sets.count)
			return;
		if ([strongSelf isArchivePage]){
			[strongSelf removeArchivedRow:row];
			return;
		}
		NSMutableDictionary *updated = [NSMutableDictionary
				dictionaryWithDictionary:strongSelf.sets[row]];
		updated[@"installed"] = @YES;
		updated[@"archived"] = @NO;
		strongSelf.sets[row] = updated;
		[strongSelf.table reloadData];
	}];
}

- (void)removeArchivedRow:(NSInteger)row {
	if (row >= (NSInteger)self.sets.count)
		return;
	[self.sets removeObjectAtIndex:row];
	if (self.archivedCount > 0)
		self.archivedCount--;
	if (self.sets.count == 0){
		[self.table reloadData];
		[self showTitle:[self emptyArchiveTitle] body:[self emptyArchiveBody]];
		return;
	}
	[self.table reloadData];
}

- (void)restoreArchivedSet:(NSDictionary *)set {
	NSUInteger row = [self.sets indexOfObject:set];
	if (row == NSNotFound)
		return;
	[self installSet:set fromRow:(NSInteger)row button:nil];
}

- (void)applyCurrentSetInstalled:(BOOL)installed {
	self.installedHere = installed;
	NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:self.set];
	updated[@"installed"] = installed ? @YES : @NO;
	if (installed)
		updated[@"archived"] = @NO;
	self.set = updated;
	[self refreshSetBarButton];
	[self refreshBottomBar];
	if (self.setStateChanged)
		self.setStateChanged(installed);
}

- (void)toggleCurrentSet {
	int64_t identifier = self.setId ?: [self.set[@"id"] longLongValue];
	if (identifier == 0)
		return;
	BOOL installed = [self currentSetInstalled];
	[self applyCurrentSetInstalled:!installed];
	self.bottomButton.enabled = NO;

	__weak typeof(self) weakSelf = self;
	void (^done)(BOOL) = ^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.bottomButton.enabled = YES;
		if (!ok){
			[strongSelf applyCurrentSetInstalled:installed];
			return;
		}
		if (!installed)
			[strongSelf checkAutoArchivedSets];
	};

	if (installed)
		[[TGClient shared] uninstallStickerSet:identifier completion:done];
	else
		[[TGClient shared] installStickerSet:identifier completion:done];
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
	[self.table reloadData];
}

#pragma mark - reordering

- (void)editTapped {
	if (self.reordering){
		[self commitOrder];
		self.reordering = NO;
		[self.table setEditing:NO animated:YES];
	} else {
		self.reordering = YES;
		self.orderBeforeEdit = [NSArray arrayWithArray:self.sets];
		[self.table setEditing:YES animated:YES];
	}
	[self installEditButton];
}

- (void)commitOrder {
	self.reordering = NO;
	NSArray *previous = self.orderBeforeEdit;
	self.orderBeforeEdit = nil;
	if (self.sets.count == 0)
		return;
	if (previous && [previous isEqualToArray:self.sets])
		return;

	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *set in self.sets)
		if (set[@"id"])
			[ids addObject:set[@"id"]];
	if (ids.count == 0)
		return;

	__weak typeof(self) weakSelf = self;
	void (^done)(BOOL) = ^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || ok || !previous)
			return;
		strongSelf.sets = [NSMutableArray arrayWithArray:previous];
		[strongSelf.table reloadData];
	};
	if ([self isMaskPage])
		[[TGClient shared] reorderInstalledMaskStickerSets:ids completion:done];
	else if ([self isEmojiListPage])
		[[TGClient shared] reorderInstalledEmojiStickerSets:ids completion:done];
	else
		[[TGClient shared] reorderInstalledStickerSets:ids completion:done];
}

#pragma mark - search

- (NSString *)trimmedQuery {
	return [self.searchBar.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)endSearch {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runSearch) object:nil];
	if (!self.searching)
		return;
	self.searching = NO;
	if (self.setsBeforeSearch)
		self.sets = self.setsBeforeSearch;
	self.setsBeforeSearch = nil;
	[self.table reloadData];
	[self reload];
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
	if (self.reordering)
		[self editTapped];
	[searchBar setShowsCancelButton:YES animated:YES];
	return YES;
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	[searchBar resignFirstResponder];
	[self endSearch];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runSearch) object:nil];
	if ([self trimmedQuery].length == 0){
		[self endSearch];
		return;
	}
	[self performSelector:@selector(runSearch) withObject:nil afterDelay:0.3];
}

- (void)runSearch {
	NSString *query = [self trimmedQuery];
	if (query.length == 0){
		[self endSearch];
		return;
	}
	if (!self.searching){
		self.searching = YES;
		self.setsBeforeSearch = self.sets;
	}

	__weak typeof(self) weakSelf = self;
	void (^done)(NSArray *) = ^(NSArray *sets){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.searching)
			return;
		if (![[strongSelf trimmedQuery] isEqualToString:query])
			return;
		strongSelf.sets = [NSMutableArray arrayWithArray:(sets ?: @[])];
		[strongSelf showContent];
		[strongSelf.table reloadData];
	};

	if ([self isMaskPage])
		[[TGClient shared] searchInstalledMaskStickerSets:query limit:kSearchLimit
											   completion:done];
	else
		[[TGClient shared] searchEmojiStickerSets:query completion:done];
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

	if ([self isTrendingPage] || [self isArchivePage]){
		__weak typeof(self) weakSelf = self;
		next.setStateChanged = ^(BOOL installed){
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf)
				return;
			[strongSelf previewedSet:set becameInstalled:installed];
		};
	}
	[self.navigationController pushViewController:next animated:YES];
}

- (void)previewedSet:(NSDictionary *)set becameInstalled:(BOOL)installed {
	NSUInteger index = [self.sets indexOfObject:set];
	if (index == NSNotFound)
		return;
	if ([self isArchivePage]){
		if (installed)
			[self removeArchivedRow:(NSInteger)index];
		return;
	}
	NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:set];
	updated[@"installed"] = installed ? @YES : @NO;
	updated[@"archived"] = @NO;
	self.sets[index] = updated;
	[self.table reloadData];
}

#pragma mark - captions

- (UILabel *)commentLabel {
	UILabel *label = [[UILabel alloc] init];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont systemFontOfSize:14];
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [[TGTheme shared] isDark] ? [[TGTheme shared] sectionHeaderColour]
												: TGStickersRGB(0x697487);
	if (![[TGTheme shared] isFlat] && ![[TGTheme shared] isDark]){
		label.shadowColor = TGStickersRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	label.numberOfLines = 0;
	return label;
}

- (CGFloat)commentHeightFor:(NSString *)text width:(CGFloat)width {
	return [text sizeWithFont:[UIFont systemFontOfSize:14]
			constrainedToSize:CGSizeMake(width, 1000)
				lineBreakMode:NSLineBreakByWordWrapping].height;
}

- (NSString *)headerTitleForSection:(NSInteger)section {
	if (self.page == TGStickersPageRoot && section == kRootSectionSets && self.sets.count)
		return @"Sticker Sets";
	return nil;
}

- (NSString *)footerTitleForSection:(NSInteger)section {
	if ([self isTwoSectionListPage]){
		if (section != 1)
			return nil;
		if (self.searching)
			return self.sets.count ? nil : @"No sets match that name.";
		if (self.sets.count == 0)
			return [self isMaskPage]
					? @"Mask sets you install show up here, ready to be reordered or removed."
					: @"Custom emoji sets you install show up here, ready to be reordered or removed.";
		return [self isMaskPage]
				? @"The mask sets you have installed. Hold Edit to reorder, swipe to remove."
				: @"The custom emoji sets you have installed. Hold Edit to reorder, swipe to remove.";
	}
	if (self.page == TGStickersPageRoot){
		if (section == kRootSectionSettings)
			return @"Type a single emoji and matching stickers are offered above the input.";
		if (section != kRootSectionSets)
			return nil;
		if (self.sets.count == 0)
			return self.loaded ? @"You have no sticker sets yet. Trending sets are a good place to start."
							   : @"Loading...";
		return @"Tap a set to see its stickers, hold Edit to reorder. Sets are managed through @stickers.";
	}
	if ([self isArchivePage] && section == 0 && self.sets.count)
		return @"Archived sets are kept out of the panel until you add them back.";
	if ([self isTrendingPage] && section == 0){
		if (self.searching)
			return self.sets.count ? nil : @"No public emoji sets match that name.";
		if (self.sets.count)
			return @"Sets other people are using right now. Tap one to see its stickers before you add it.";
	}
	return nil;
}

#pragma mark - table data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	if (self.page == TGStickersPageRoot)
		return 4;
	return [self isTwoSectionListPage] ? 2 : 1;
}

- (NSArray *)rootPageRows {
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:@{@"title": @"Trending Stickers",
					  @"detail": self.trendingNewCount
							? [NSString stringWithFormat:@"%d new", (int)self.trendingNewCount] : @"",
					  @"page": @(TGStickersPageTrending)}];
	[rows addObject:@{@"title": @"Archived Stickers",
					  @"detail": self.archivedCount
							? [NSString stringWithFormat:@"%d", (int)self.archivedCount] : @"",
					  @"page": @(TGStickersPageArchived)}];
	[rows addObject:@{@"title": @"Favourite Stickers",
					  @"detail": self.favouriteCount
							? [NSString stringWithFormat:@"%d", (int)self.favouriteCount] : @"",
					  @"page": @(TGStickersPageFavourites)}];
	[rows addObject:@{@"title": @"Recently Used",
					  @"detail": self.recentCount
							? [NSString stringWithFormat:@"%d", (int)self.recentCount] : @"",
					  @"page": @(TGStickersPageRecent)}];
	[rows addObject:@{@"title": @"Custom Emoji",
					  @"detail": self.emojiSetCount
							? [NSString stringWithFormat:@"%d", (int)self.emojiSetCount] : @"",
					  @"page": @(TGStickersPageEmoji)}];
	if (self.maskCount > 0)
		[rows addObject:@{@"title": @"Masks",
						  @"detail": [NSString stringWithFormat:@"%d", (int)self.maskCount],
						  @"page": @(TGStickersPageMasks)}];
	[rows addObject:@{@"title": @"Premium Stickers", @"detail": @"",
					  @"page": @(TGStickersPagePremium)}];
	return rows;
}

- (NSArray *)subpageRows {
	if ([self isEmojiListPage]){
		return @[@{@"title": @"Trending Emoji",
				   @"detail": self.subpageTrendingCount
						? [NSString stringWithFormat:@"%d", (int)self.subpageTrendingCount] : @"",
				   @"page": @(TGStickersPageEmojiTrending)},
				 @{@"title": @"Archived Emoji",
				   @"detail": self.archivedCount
						? [NSString stringWithFormat:@"%d", (int)self.archivedCount] : @"",
				   @"page": @(TGStickersPageEmojiArchived)}];
	}
	return @[@{@"title": @"Archived Masks",
			   @"detail": self.archivedCount
					? [NSString stringWithFormat:@"%d", (int)self.archivedCount] : @"",
			   @"page": @(TGStickersPageMasksArchived)}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if ([self isGridPage])
		return [self gridRowCount];
	if ([self isTwoSectionListPage])
		return section == 0 ? (NSInteger)[self subpageRows].count : (NSInteger)self.sets.count;
	if (self.page != TGStickersPageRoot)
		return (NSInteger)self.sets.count;
	if (section == kRootSectionSettings)
		return 2;
	if (section == kRootSectionPages)
		return (NSInteger)[self rootPageRows].count;
	if (section == kRootSectionSets)
		return (NSInteger)self.sets.count;
	return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isGridPage])
		return kGridRowHeight;
	if ([self isTrendingPage])
		return kTrendRowHeight;
	if ([self isTwoSectionListPage])
		return indexPath.section == 0 ? kPlainRowHeight : kSetRowHeight;
	if (self.page != TGStickersPageRoot)
		return kSetRowHeight;
	return indexPath.section == kRootSectionSets ? kSetRowHeight : kPlainRowHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if ([self isGridPage])
		return 0;
	return [self headerTitleForSection:section] ? 46 : 14;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return nil;
	UILabel *label = [[UILabel alloc] init];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont boldSystemFontOfSize:17];
	label.text = title;
	label.textColor = [[TGTheme shared] isDark] ? [[TGTheme shared] sectionHeaderColour]
												: TGStickersRGB(0x697487);
	if (![[TGTheme shared] isFlat] && ![[TGTheme shared] isDark]){
		label.shadowColor = TGStickersRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[label sizeToFit];
	label.frame = CGRectMake(21, 16, label.frame.size.width, label.frame.size.height);

	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, 46)];
	container.backgroundColor = [UIColor clearColor];
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if ([self isGridPage])
		return 0;
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return 1;
	return [self commentHeightFor:title width:tableView.bounds.size.width - 20] + 14;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return nil;
	CGFloat width = tableView.bounds.size.width - 20;
	CGFloat height = [self commentHeightFor:title width:width];
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, height + 14)];
	container.backgroundColor = [UIColor clearColor];
	UILabel *label = [self commentLabel];
	label.text = title;
	label.frame = CGRectMake(10, 7 + TGStickersRetinaPixel(), width, height);
	[container addSubview:label];
	return container;
}

- (NSDictionary *)setAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isGridPage])
		return nil;
	if (self.page == TGStickersPageRoot && indexPath.section != kRootSectionSets)
		return nil;
	if ([self isTwoSectionListPage] && indexPath.section != 1)
		return nil;
	if (indexPath.row >= (NSInteger)self.sets.count)
		return nil;
	return self.sets[indexPath.row];
}

- (NSInteger)stickerCountForSet:(NSDictionary *)set {
	NSInteger count = [set[@"count"] integerValue];
	if (count == 0)
		count = (NSInteger)[set[@"stickers"] count];
	return count;
}

- (NSString *)countTextForSet:(NSDictionary *)set {
	NSInteger count = [self stickerCountForSet:set];
	return count == 1 ? @"1 sticker" : [NSString stringWithFormat:@"%d stickers", (int)count];
}

- (NSString *)addButtonTitle {
	return [self isArchivePage] ? @"ADD BACK" : @"ADD";
}

- (UIButton *)addButton {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(0, 0,
			[self isArchivePage] ? 86 : 70, 30);
	button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
	button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	[button setTitle:[self addButtonTitle] forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[button setTitleColor:TGStickersRGB(0x8b97a5) forState:UIControlStateDisabled];
	[button setTitleShadowColor:[UIColor colorWithRed:0.05f green:0.15f blue:0.30f alpha:0.4f]
					   forState:UIControlStateNormal];
	[button setBackgroundImage:TGStickersStretch(@"GroupedActionButtonGreen.png", 33)
					  forState:UIControlStateNormal];
	[button setBackgroundImage:TGStickersStretch(@"GroupedActionButtonGreen_Highlighted.png", 33)
					  forState:UIControlStateHighlighted];
	[button addTarget:self action:@selector(addButtonTapped:)
	 forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (void)configureAddButton:(UIButton *)button forRow:(NSInteger)row installed:(BOOL)installed {
	button.tag = row;
	button.enabled = !installed;
	if (installed){
		[button setBackgroundImage:nil forState:UIControlStateNormal];
		[button setTitle:@"ADDED" forState:UIControlStateDisabled];
	} else {
		[button setBackgroundImage:TGStickersStretch(@"GroupedActionButtonGreen.png", 33)
						  forState:UIControlStateNormal];
		[button setTitle:[self addButtonTitle] forState:UIControlStateNormal];
	}
}

- (void)addButtonTapped:(UIButton *)button {
	NSInteger row = button.tag;
	if (row >= (NSInteger)self.sets.count)
		return;
	button.enabled = NO;
	[button setBackgroundImage:nil forState:UIControlStateDisabled];
	[button setTitle:@"ADDED" forState:UIControlStateDisabled];
	[self installSet:self.sets[row] fromRow:row button:button];
}

- (UITableViewCell *)plainCellForTable:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"plain"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"plain"];
	[[TGTheme shared] styleCell:cell];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.textLabel.font = [UIFont systemFontOfSize:19];
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
		cell.textLabel.font = [UIFont systemFontOfSize:19];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:13 + TGStickersRetinaPixel()];
	}
	[[TGTheme shared] styleCell:cell];
	cell.shouldIndentWhileEditing = NO;
	cell.textLabel.font = [UIFont systemFontOfSize:19];
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

	if ([self isReorderPage]){
		cell.accessoryView = nil;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else {
		UIButton *add = [self addButton];
		[self configureAddButton:add forRow:indexPath.row
					   installed:[set[@"installed"] boolValue]];
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.accessoryView = add;
	}
	return cell;
}

- (UITableViewCell *)trendCellForTable:(UITableView *)tableView
							 indexPath:(NSIndexPath *)indexPath {
	TGStickerTrendCell *cell = (TGStickerTrendCell *)
			[tableView dequeueReusableCellWithIdentifier:@"trend"];
	if (!cell){
		cell = [[TGStickerTrendCell alloc] initWithStyle:UITableViewCellStyleDefault
										 reuseIdentifier:@"trend"];
		[cell.addButton addTarget:self action:@selector(addButtonTapped:)
				 forControlEvents:UIControlEventTouchUpInside];
	}
	[[TGTheme shared] styleCell:cell];

	NSDictionary *set = [self setAtIndexPath:indexPath];
	cell.packTitleLabel.text = set[@"title"];
	cell.packTitleLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.packCountLabel.text = [self countTextForSet:set];
	[self configureAddButton:cell.addButton forRow:indexPath.row
				   installed:[set[@"installed"] boolValue]];

	NSArray *covers = set[@"covers"];
	NSInteger index = 0;
	for (UIImageView *view in cell.coverViews){
		UIImage *image = nil;
		if (index < (NSInteger)covers.count){
			NSDictionary *sticker = covers[index];
			if ([self stickerIsStill:sticker])
				image = [self imageForFileId:[sticker[@"fileId"] integerValue]
										side:kTrendCoverSide indexPath:indexPath];
		}
		view.image = image;
		index++;
	}
	return cell;
}

- (UITableViewCell *)clearRecentCellForTable:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"clear"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"clear"];
		cell.textLabel.font = [UIFont systemFontOfSize:19];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
	}
	[[TGTheme shared] styleCell:cell];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.imageView.image = nil;
	cell.textLabel.font = [UIFont systemFontOfSize:19];
	cell.textLabel.text = @"Clear Recent Stickers";
	cell.textLabel.textColor = TGStickersRGB(0xd0021b);
	return cell;
}

- (UITableViewCell *)settingsCellForTable:(UITableView *)tableView row:(NSInteger)row {
	UITableViewCell *cell = [self plainCellForTable:tableView];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];

	if (row == 0){
		cell.textLabel.text = @"Suggest by Emoji";
		cell.detailTextLabel.text = TGStickersSuggestModeName(TGStickersSuggestMode());
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	cell.textLabel.text = @"Loop Animated Stickers";
	cell.detailTextLabel.text = @"";
	cell.accessoryType = UITableViewCellAccessoryNone;
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:TGStickerLoopAnimatedKey];
	[toggle addTarget:self action:@selector(loopAnimatedToggled:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isGridPage])
		return [self tilesCellForTable:tableView indexPath:indexPath];
	if ([self isTrendingPage])
		return [self trendCellForTable:tableView indexPath:indexPath];
	if ([self isTwoSectionListPage]){
		if (indexPath.section == 0){
			NSArray *rows = [self subpageRows];
			if (indexPath.row >= (NSInteger)rows.count)
				return [self plainCellForTable:tableView];
			return [self subpageCellForTable:tableView rowInfo:rows[indexPath.row]];
		}
		return [self setCellForTable:tableView indexPath:indexPath];
	}
	if (self.page != TGStickersPageRoot)
		return [self setCellForTable:tableView indexPath:indexPath];

	if (indexPath.section == kRootSectionSets)
		return [self setCellForTable:tableView indexPath:indexPath];
	if (indexPath.section == kRootSectionRecent)
		return [self clearRecentCellForTable:tableView];

	if (indexPath.section == kRootSectionSettings)
		return [self settingsCellForTable:tableView row:indexPath.row];

	NSArray *rows = [self rootPageRows];
	if (indexPath.row >= (NSInteger)rows.count)
		return [self plainCellForTable:tableView];
	return [self subpageCellForTable:tableView rowInfo:rows[indexPath.row]];
}

- (UITableViewCell *)subpageCellForTable:(UITableView *)tableView
								 rowInfo:(NSDictionary *)rowInfo {
	UITableViewCell *cell = [self plainCellForTable:tableView];
	cell.textLabel.text = rowInfo[@"title"];
	cell.detailTextLabel.text = rowInfo[@"detail"];
	return cell;
}

#pragma mark - table delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if ([self isGridPage])
		return;

	if ([self isTwoSectionListPage]){
		if (indexPath.section == 0){
			NSArray *rows = [self subpageRows];
			if (indexPath.row < (NSInteger)rows.count)
				[self openPage:(TGStickersPage)[rows[indexPath.row][@"page"] integerValue]];
			return;
		}
		NSDictionary *set = [self setAtIndexPath:indexPath];
		if (set)
			[self openSet:set];
		return;
	}

	if (self.page != TGStickersPageRoot){
		NSDictionary *set = [self setAtIndexPath:indexPath];
		if (set)
			[self openSet:set];
		return;
	}

	if (indexPath.section == kRootSectionSettings){
		if (indexPath.row == 0)
			[self presentSuggestModeSheet];
		return;
	}
	if (indexPath.section == kRootSectionPages){
		NSArray *rows = [self rootPageRows];
		if (indexPath.row < (NSInteger)rows.count)
			[self openPage:(TGStickersPage)[rows[indexPath.row][@"page"] integerValue]];
		return;
	}
	if (indexPath.section == kRootSectionSets){
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
	if (![self isArchivePage] && ![self isTrendingPage])
		return;
	if (indexPath.row < (NSInteger)self.sets.count - 3)
		return;
	if ([self isArchivePage])
		[self loadMoreArchived];
	else
		[self loadMoreTrending];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isGridPage] || self.searching)
		return NO;
	if ([self isArchivePage])
		return YES;
	if ([self isTwoSectionListPage])
		return indexPath.section == 1;
	return self.page == TGStickersPageRoot && indexPath.section == kRootSectionSets;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.searching)
		return NO;
	if ([self isTwoSectionListPage])
		return indexPath.section == 1;
	return self.page == TGStickersPageRoot && indexPath.section == kRootSectionSets;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
		   editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.reordering || self.searching)
		return UITableViewCellEditingStyleNone;
	if ([self isArchivePage])
		return UITableViewCellEditingStyleDelete;
	if ([self isTwoSectionListPage])
		return indexPath.section == 1 ? UITableViewCellEditingStyleDelete
									  : UITableViewCellEditingStyleNone;
	if (self.page == TGStickersPageRoot && indexPath.section == kRootSectionSets)
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

	if ([self isArchivePage]){
		NSArray *archivedActions = @[
			[[TGActionSheetAction alloc] initWithTitle:@"Add Back" action:@"restoreSet"],
			[[TGActionSheetAction alloc] initWithTitle:@"Copy Link" action:@"copyLink"],
			[[TGActionSheetAction alloc] initWithTitle:@"Delete" action:@"removeSet"
												  type:TGActionSheetActionTypeDestructive],
			[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
												  type:TGActionSheetActionTypeCancel]
		];
		[self presentSheetWithTitle:set[@"title"] actions:archivedActions];
		return;
	}

	NSArray *actions = @[
		[[TGActionSheetAction alloc] initWithTitle:@"Archive" action:@"archiveSet"],
		[[TGActionSheetAction alloc] initWithTitle:@"Copy Link" action:@"copyLink"],
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
	NSInteger section = [self setsSection];
	if (proposedDestinationIndexPath.section == section)
		return proposedDestinationIndexPath;
	if (proposedDestinationIndexPath.section < section)
		return [NSIndexPath indexPathForRow:0 inSection:section];
	return [NSIndexPath indexPathForRow:(NSInteger)self.sets.count - 1 inSection:section];
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

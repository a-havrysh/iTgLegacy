#import "TGStickerPanelView.h"

#import "TGClient.h"
#import "TGClient+Stickers.h"
#import "TGClient+Files.h"
#import "TGActionSheet.h"
#import "TGStickerThumbnailCache.h"
#import "TGTheme.h"
#import "TGViewRecycler.h"
#import "TGReusableView.h"
#import "UIView+SafeTint.h"

/// The tab plates are 30pt tall and the divider between them is 2pt wide; both
/// come straight off the button-group art the rest of the app uses.
static const CGFloat TGStickerPanelTabHeight = 30.0f;
static const CGFloat TGStickerPanelTabHeightLandscape = 25.0f;
static const CGFloat TGStickerPanelTabDividerWidth = 2.0f;
static const CGFloat TGStickerPanelTabMinWidth = 44.0f;
/// CategoryDivider.png is 26pt tall; a 25pt header stretched it by a pixel.
static const CGFloat TGStickerPanelHeaderHeight = 26.0f;
static const CGFloat TGStickerPanelTileSide = 64.0f;
static const CGFloat TGStickerPanelTileMinSpacing = 9.0f;
static const NSInteger TGStickerPanelMinColumns = 4;
static const CGFloat TGStickerPanelTileCornerRadius = 8.0f;
static const CGFloat TGStickerPanelPreviewSide = 180.0f;
static const CGFloat TGStickerPanelSearchHeight = 44.0f;
static const CGFloat TGStickerPanelTabThumbSide = 24.0f;
static const CGFloat TGStickerPanelPurgeDistance = 900.0f;
static const NSInteger TGStickerPanelPageSize = 40;

static const NSInteger TGStickerSectionRecent = 0;
static const NSInteger TGStickerSectionFavourite = 1;
static const NSInteger TGStickerSectionSet = 2;
static const NSInteger TGStickerSectionEmojiSet = 3;
static const NSInteger TGStickerSectionTrending = 4;
static const NSInteger TGStickerSectionPublicSet = 5;
static const NSInteger TGStickerSectionSearch = 6;

static const NSInteger TGStickerPanelTrendingLimit = 6;
static const NSInteger TGStickerPanelAddButtonTag = 9902;

static BOOL TGStickerSectionIsSet(NSInteger kind) {
	return kind == TGStickerSectionSet || kind == TGStickerSectionEmojiSet ||
			kind == TGStickerSectionTrending || kind == TGStickerSectionPublicSet;
}

@interface TGStickerTile : UIControl <TGReusableView>

@property (nonatomic, strong) NSString *reuseIdentifier;
@property (nonatomic, strong) UIView *pressPlate;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *emojiLabel;
@property (nonatomic, strong) NSDictionary *sticker;
@property (nonatomic, assign) NSInteger sectionIndex;
@property (nonatomic, assign) NSInteger itemIndex;
@property (nonatomic, strong) NSString *imageKey;
@property (nonatomic, strong) id imageToken;

@end

@implementation TGStickerTile

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self != nil){
		self.reuseIdentifier = @"stickerTile";
		self.opaque = NO;
		self.backgroundColor = [UIColor clearColor];
		self.exclusiveTouch = YES;

		_pressPlate = [[UIView alloc] initWithFrame:self.bounds];
		_pressPlate.backgroundColor = [[TGTheme shared] separatorColour];
		_pressPlate.layer.cornerRadius = TGStickerPanelTileCornerRadius;
		_pressPlate.userInteractionEnabled = NO;
		_pressPlate.hidden = YES;
		[self addSubview:_pressPlate];

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
	_pressPlate.frame = self.bounds;
	_emojiLabel.frame = self.bounds;
	_imageView.frame = self.bounds;
}

/// Telegram highlights a sticker with a rounded plate behind it rather than by
/// fading the sticker out; a translucent sticker over a fading tile reads as a
/// loading failure.
- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	_pressPlate.hidden = !highlighted;
}

- (void)reset {
	self.pressPlate.hidden = YES;
	self.alpha = 1.0f;
	self.sticker = nil;
	self.imageKey = nil;
	self.imageView.image = nil;
	self.imageView.alpha = 1.0f;
	self.emojiLabel.text = @"";
}

- (void)prepareForReuse {
	[self reset];
}

- (void)prepareForRecycle:(TGViewRecycler *)recycler {
	[self reset];
	[self removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	for (UIGestureRecognizer *recogniser in [self.gestureRecognizers copy])
		[self removeGestureRecognizer:recogniser];
}

@end

@interface TGStickerPanelView () <UIScrollViewDelegate, UISearchBarDelegate>

@property (nonatomic, strong) UIScrollView *tabStrip;
@property (nonatomic, strong) UIScrollView *grid;
@property (nonatomic, strong) UIView *topSeparator;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UISearchBar *searchBar;

@property (nonatomic, strong) TGViewRecycler *recycler;
@property (nonatomic, strong) NSMutableArray *allSections;
@property (nonatomic, strong) NSMutableArray *sections;
@property (nonatomic, strong) NSMutableArray *searchSections;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, strong) NSDictionary *menuSticker;
@property (nonatomic, assign) NSInteger menuSectionIndex;
@property (nonatomic, assign) BOOL menuStickerFavourite;
@property (nonatomic, strong) NSMutableDictionary *visibleTiles;
@property (nonatomic, strong) NSMutableArray *headerViews;
@property (nonatomic, strong) NSMutableArray *tabButtons;
@property (nonatomic, strong) NSMutableArray *tabDividers;
@property (nonatomic, strong) NSMutableArray *tabImageTokens;
@property (nonatomic, strong) UIView *previewOverlay;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UILabel *previewEmojiLabel;
@property (nonatomic, strong) id previewToken;

@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, assign) BOOL searchVisible;
@property (nonatomic, assign) NSInteger columns;
@property (nonatomic, assign) CGFloat tileSide;
@property (nonatomic, assign) CGFloat tileSpacing;
@property (nonatomic, assign) CGFloat sideInset;
@property (nonatomic, assign) CGFloat tabHeight;
@property (nonatomic, assign) NSInteger selectedSection;
@property (nonatomic, assign) CGFloat laidOutWidth;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) NSInteger generation;
@property (nonatomic, assign) NSInteger searchGeneration;
@property (nonatomic, assign) NSTimeInterval openedAt;
@property (nonatomic, assign) BOOL openTimingReported;
@property (nonatomic, assign) BOOL restoredFromSnapshot;

@end

/// The panel view itself is thrown away every time the keyboard is dismissed
/// (TGChatViewController -toggleStickerPanel), so the section list has to live
/// outside it or the second open of a session pays for the whole load again.
static NSMutableArray *TGStickerPanelSectionSnapshot = nil;
static NSTimeInterval TGStickerPanelSnapshotTaken = 0;
static const NSTimeInterval TGStickerPanelSnapshotLifetime = 600.0;

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
		_allSections = [[NSMutableArray alloc] init];
		_sections = [[NSMutableArray alloc] init];
		_searchSections = [[NSMutableArray alloc] init];
		_menuSectionIndex = -1;
		_visibleTiles = [[NSMutableDictionary alloc] init];
		_headerViews = [[NSMutableArray alloc] init];
		_tabButtons = [[NSMutableArray alloc] init];
		_tabDividers = [[NSMutableArray alloc] init];
		_tabImageTokens = [[NSMutableArray alloc] init];
		_columns = TGStickerPanelMinColumns;
		_tileSide = TGStickerPanelTileSide;
		_tileSpacing = TGStickerPanelTileMinSpacing;
		_sideInset = TGStickerPanelTileMinSpacing;
		_tabHeight = TGStickerPanelTabHeight;
		_selectedSection = -1;
		_searchQuery = @"";

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

		_searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
		_searchBar.delegate = self;
		_searchBar.placeholder = @"Search Stickers";
		_searchBar.showsCancelButton = YES;
		_searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
		_searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
		_searchBar.barStyle = [[TGTheme shared] isDark] ? UIBarStyleBlack : UIBarStyleDefault;
		[_searchBar tg_setTintColor:[[TGTheme shared] accentColour]];
		_searchBar.hidden = YES;
		[self addSubview:_searchBar];

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

		_openedAt = [NSDate timeIntervalSinceReferenceDate];
		[TGStickerThumbnailCache resetStatistics];

		// Reopening the panel inside one session draws the packs it already
		// knows straight away and refreshes them underneath, instead of
		// spinning through five TDLib round trips again.
		_restoredFromSnapshot = [self restoreSectionSnapshot];
		if (_restoredFromSnapshot)
			[self reloadShowingSpinner:NO];
		else
			[self reload];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[self cancelAllPendingImageLoads];
	[_previewOverlay removeFromSuperview];
	_grid.delegate = nil;
	_searchBar.delegate = nil;
}

/// A tile that scrolls out of the window drops its interest at once, so the
/// download is cancelled and any decode still sitting in the queue is skipped
/// instead of finishing for a tile nobody can see.
- (void)releaseImageForTile:(TGStickerTile *)tile {
	if (tile.imageToken != nil)
		[TGStickerThumbnailCache cancelRequest:tile.imageToken];
	tile.imageToken = nil;
	tile.imageKey = nil;
}

- (void)cancelTabImageLoads {
	for (id token in self.tabImageTokens)
		[TGStickerThumbnailCache cancelRequest:token];
	[self.tabImageTokens removeAllObjects];
}

- (void)cancelAllPendingImageLoads {
	for (NSString *key in [self.visibleTiles allKeys])
		[self releaseImageForTile:self.visibleTiles[key]];
	[self cancelTabImageLoads];
	[self cancelPreviewLoad];
}

- (void)handleMemoryWarning {
	[TGStickerThumbnailCache purgeMemory];
	[self.recycler removeAllViews];
	[self purgeDistantSectionsAggressively:YES];
	TGStickerPanelSectionSnapshot = nil;
}

#pragma mark - loading

/// Everything the snapshot carries stays valid only while the TDLib session
/// that minted its file ids is alive, so it is a process-lifetime cache and
/// never touches disk. The thumbnails behind it do survive a relaunch: those
/// live in TGStickerThumbnailCache, keyed on the remote unique id.
- (void)takeSectionSnapshot {
	if (self.searchQuery.length > 0 || self.allSections.count == 0)
		return;
	TGStickerPanelSectionSnapshot = [self.allSections mutableCopy];
	TGStickerPanelSnapshotTaken = [NSDate timeIntervalSinceReferenceDate];
}

- (BOOL)restoreSectionSnapshot {
	if (TGStickerPanelSectionSnapshot.count == 0)
		return NO;
	if ([NSDate timeIntervalSinceReferenceDate] - TGStickerPanelSnapshotTaken >
			TGStickerPanelSnapshotLifetime){
		TGStickerPanelSectionSnapshot = nil;
		return NO;
	}

	[self.allSections setArray:TGStickerPanelSectionSnapshot];
	self.loading = NO;
	self.failed = NO;
	[self applyFilter];
	[self updateStatus];
	return YES;
}

- (void)reload {
	[self reloadShowingSpinner:YES];
}

- (void)reloadShowingSpinner:(BOOL)showSpinner {
	self.generation += 1;
	NSInteger generation = self.generation;

	[self clearTiles];
	[self cancelAllPendingImageLoads];
	if (showSpinner){
		[self.allSections removeAllObjects];
		[self.sections removeAllObjects];
		[self.searchSections removeAllObjects];
		self.selectedSection = -1;
		self.loading = YES;
		self.failed = NO;
		[self updateStatus];
		[self rebuildTabs];
	}

	__block BOOL anyFailure = NO;
	__block NSInteger outstanding = 5;
	__block NSArray *recent = nil;
	__block NSArray *favourites = nil;
	__block NSArray *sets = nil;
	__block NSArray *emojiSets = nil;
	__block NSArray *trending = nil;

	__weak TGStickerPanelView *weakSelf = self;
	void (^finish)(void) = ^{
		TGStickerPanelView *me = weakSelf;
		if (me == nil || me.generation != generation)
			return;
		outstanding -= 1;
		if (outstanding > 0)
			return;
		[me buildSectionsWithRecent:recent favourites:favourites sets:sets
						  emojiSets:emojiSets trending:trending failed:anyFailure];
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
	[[TGClient shared] installedEmojiStickerSetsWithCompletion:^(NSArray *installed){
		emojiSets = installed;
		finish();
	}];
	[[TGClient shared] trendingStickerSetsWithOffset:0 limit:TGStickerPanelTrendingLimit
										  completion:^(NSArray *featured, __unused NSInteger totalCount){
		trending = featured;
		finish();
	}];
}

- (NSMutableDictionary *)sectionForSet:(NSDictionary *)set kind:(NSInteger)kind {
	NSInteger count = [set[@"count"] integerValue];
	if (count <= 0)
		return nil;

	NSString *title = set[@"title"];
	if (title.length == 0)
		title = (kind == TGStickerSectionEmojiSet) ? @"Emoji" : @"Stickers";

	NSMutableDictionary *section = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
			@(kind), @"kind",
			title, @"title",
			title, @"tabTitle",
			set[@"id"], @"setId",
			@(count), @"count", nil];

	NSString *name = set[@"name"];
	if (name.length > 0)
		section[@"name"] = name;

	if ((kind == TGStickerSectionTrending || kind == TGStickerSectionPublicSet) &&
		![set[@"installed"] boolValue])
		section[@"canInstall"] = @YES;

	NSInteger thumbId = [set[@"thumbId"] integerValue];
	NSString *thumbUniqueId = set[@"thumbUniqueId"];
	if (thumbId == 0){
		NSArray *covers = set[@"covers"];
		NSDictionary *cover = covers.count > 0 ? covers[0] : nil;
		if (cover != nil){
			thumbId = [self drawableFileIdForSticker:cover];
			thumbUniqueId = [self drawableUniqueIdForSticker:cover];
		}
	}
	if (thumbId != 0)
		section[@"tabThumbId"] = @(thumbId);
	if ([thumbUniqueId isKindOfClass:[NSString class]] && thumbUniqueId.length > 0)
		section[@"tabThumbUniqueId"] = thumbUniqueId;

	return section;
}

- (void)buildSectionsWithRecent:(NSArray *)recent
					 favourites:(NSArray *)favourites
						   sets:(NSArray *)sets
					  emojiSets:(NSArray *)emojiSets
					   trending:(NSArray *)trending
						 failed:(BOOL)failed {
	self.loading = NO;
	BOOL hadSections = (self.allSections.count > 0);
	NSInteger keptSelection = self.selectedSection;
	CGFloat keptOffset = self.grid.contentOffset.y;
	[self.allSections removeAllObjects];

	if (recent.count > 0){
		[self.allSections addObject:[[NSMutableDictionary alloc] initWithObjectsAndKeys:
				@(TGStickerSectionRecent), @"kind",
				@"Recent", @"title",
				@"Recent", @"tabTitle",
				[recent mutableCopy], @"stickers",
				@(recent.count), @"loadedCount",
				@YES, @"complete",
				@(recent.count), @"count", nil]];
	}
	if (favourites.count > 0){
		[self.allSections addObject:[[NSMutableDictionary alloc] initWithObjectsAndKeys:
				@(TGStickerSectionFavourite), @"kind",
				@"Favourites", @"title",
				@"Fav", @"tabTitle",
				[favourites mutableCopy], @"stickers",
				@(favourites.count), @"loadedCount",
				@YES, @"complete",
				@(favourites.count), @"count", nil]];
	}

	for (NSDictionary *set in sets){
		if ([set[@"isEmoji"] boolValue])
			continue;
		NSMutableDictionary *section = [self sectionForSet:set kind:TGStickerSectionSet];
		if (section != nil)
			[self.allSections addObject:section];
	}

	for (NSDictionary *set in emojiSets){
		NSMutableDictionary *section = [self sectionForSet:set kind:TGStickerSectionEmojiSet];
		if (section != nil)
			[self.allSections addObject:section];
	}

	NSMutableSet *knownIds = [[NSMutableSet alloc] init];
	for (NSMutableDictionary *section in self.allSections){
		NSNumber *setId = section[@"setId"];
		if (setId != nil)
			[knownIds addObject:setId];
	}

	for (NSDictionary *set in trending){
		NSNumber *setId = set[@"id"];
		if (setId == nil || [knownIds containsObject:setId])
			continue;
		if ([set[@"installed"] boolValue] || [set[@"isEmoji"] boolValue])
			continue;
		NSMutableDictionary *section = [self sectionForSet:set kind:TGStickerSectionTrending];
		if (section == nil)
			continue;
		[knownIds addObject:setId];
		[self.allSections addObject:section];
	}

	self.failed = (self.allSections.count == 0 && failed);
	[self takeSectionSnapshot];
	[self applyFilter];
	[self updateStatus];

	if (self.sections.count == 0)
		return;

	// A silent refresh behind a restored snapshot must not throw the user back
	// to the top of the first pack.
	if (hadSections && keptSelection >= 0 && keptSelection < (NSInteger)self.sections.count){
		CGFloat maxOffset = MAX(0.0f, self.grid.contentSize.height - self.grid.bounds.size.height);
		self.grid.contentOffset = CGPointMake(0, MAX(0.0f, MIN(keptOffset, maxOffset)));
		[self setSelectedSection:keptSelection scrollGrid:NO];
		return;
	}
	[self setSelectedSection:0 scrollGrid:NO];
}

- (void)ensureSection:(NSInteger)index loadedUpToItem:(NSInteger)item {
	if (index < 0 || index >= (NSInteger)self.sections.count)
		return;

	NSMutableDictionary *section = self.sections[index];
	NSInteger kind = [section[@"kind"] integerValue];
	if (!TGStickerSectionIsSet(kind))
		return;
	if ([section[@"loading"] boolValue] || [section[@"complete"] boolValue])
		return;

	NSInteger loaded = [section[@"loadedCount"] integerValue];
	if (loaded > item)
		return;

	NSInteger limit = MAX((NSInteger)TGStickerPanelPageSize, item - loaded + 1);
	section[@"loading"] = @YES;

	NSInteger generation = self.generation;
	int64_t setId = [section[@"setId"] longLongValue];
	NSMutableDictionary *target = section;

	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] stickersFromSetId:setId offset:loaded limit:limit
							  completion:^(NSArray *stickers, NSInteger totalCount){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || me.generation != generation)
			return;

		[target removeObjectForKey:@"loading"];
		if (stickers == nil){
			target[@"complete"] = @YES;
			return;
		}

		NSMutableArray *store = target[@"stickers"];
		if (store == nil){
			store = [[NSMutableArray alloc] init];
			target[@"stickers"] = store;
		}
		[store addObjectsFromArray:stickers];
		target[@"loadedCount"] = @(store.count);
		if (stickers.count < (NSUInteger)limit)
			target[@"complete"] = @YES;

		BOOL geometryChanged = NO;
		if (totalCount > 0 && totalCount != [target[@"count"] integerValue]){
			target[@"count"] = @(totalCount);
			geometryChanged = YES;
		}
		else if (totalCount <= 0 && [target[@"complete"] boolValue] &&
				 (NSInteger)store.count != [target[@"count"] integerValue]){
			target[@"count"] = @(store.count);
			geometryChanged = YES;
		}

		if (geometryChanged)
			[me relayoutSections];
		[me updateVisibleTiles];
	}];
}

#pragma mark - search

- (void)toggleSearch {
	[self setSearchVisible:!self.searchVisible];
}

- (void)setSearchVisible:(BOOL)visible {
	if (_searchVisible == visible)
		return;
	_searchVisible = visible;
	self.searchBar.hidden = !visible;

	if (visible){
		[self setNeedsLayout];
		[self layoutIfNeeded];
		[self.searchBar becomeFirstResponder];
		return;
	}

	[self.searchBar resignFirstResponder];
	self.searchBar.text = @"";
	if (self.searchQuery.length > 0){
		self.searchQuery = @"";
		self.searchGeneration += 1;
		[self.searchSections removeAllObjects];
		[self applyFilter];
		[self updateStatus];
	}
	[self setNeedsLayout];
}

- (void)applyFilter {
	NSString *query = self.searchQuery;
	NSMutableArray *filtered = [[NSMutableArray alloc] init];

	if (query.length == 0){
		[filtered addObjectsFromArray:self.allSections];
	}
	else {
		[filtered addObjectsFromArray:self.searchSections];
		for (NSMutableDictionary *section in self.allSections){
			NSString *title = section[@"title"];
			NSString *name = section[@"name"];
			BOOL matched = ([title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) ||
					(name.length > 0 && [name rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound);
			if (!matched && section[@"serverMatch"] != nil)
				matched = [section[@"serverMatch"] isEqualToString:query];
			if (matched)
				[filtered addObject:section];
		}
	}

	[self.sections setArray:filtered];
	if (query.length > 0)
		[self purgeDistantSectionsAggressively:NO];
	self.selectedSection = -1;
	[self rebuildTabs];
	[self relayoutSections];
	if (self.sections.count > 0)
		[self setSelectedSection:0 scrollGrid:NO];
}

- (BOOL)searchStillCurrent:(NSString *)query
				generation:(NSInteger)generation
		  searchGeneration:(NSInteger)searchGeneration {
	if (self.generation != generation || self.searchGeneration != searchGeneration)
		return NO;
	return [self.searchQuery isEqualToString:query];
}

- (BOOL)knowsSetId:(NSNumber *)setId {
	if (setId == nil)
		return YES;
	for (NSMutableDictionary *section in self.allSections){
		if ([setId isEqualToNumber:section[@"setId"] ?: @(0)])
			return YES;
	}
	for (NSMutableDictionary *section in self.searchSections){
		if ([setId isEqualToNumber:section[@"setId"] ?: @(0)])
			return YES;
	}
	return NO;
}

- (void)insertSearchSection:(NSMutableDictionary *)section order:(NSInteger)order {
	section[@"order"] = @(order);
	NSInteger insertAt = (NSInteger)self.searchSections.count;
	for (NSInteger i = 0; i < (NSInteger)self.searchSections.count; i++){
		if ([self.searchSections[i][@"order"] integerValue] > order){
			insertAt = i;
			break;
		}
	}
	[self.searchSections insertObject:section atIndex:insertAt];
}

- (void)addSearchSection:(NSMutableDictionary *)section order:(NSInteger)order {
	[self insertSearchSection:section order:order];
	[self applyFilter];
	[self updateStatus];
}

- (NSMutableDictionary *)searchResultSectionForStickers:(NSArray *)stickers {
	if (stickers.count == 0)
		return nil;

	NSMutableDictionary *section = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
			@(TGStickerSectionSearch), @"kind",
			@"Search Results", @"title",
			@"Found", @"tabTitle",
			[stickers mutableCopy], @"stickers",
			@(stickers.count), @"loadedCount",
			@YES, @"complete",
			@(stickers.count), @"count", nil];

	NSInteger thumbId = [self drawableFileIdForSticker:stickers[0]];
	NSString *thumbUniqueId = [self drawableUniqueIdForSticker:stickers[0]];
	if (thumbId != 0)
		section[@"tabThumbId"] = @(thumbId);
	if (thumbUniqueId.length > 0)
		section[@"tabThumbUniqueId"] = thumbUniqueId;
	return section;
}

- (void)searchStickersByEmoji:(NSString *)emoji
					 forQuery:(NSString *)query
				   generation:(NSInteger)generation
			 searchGeneration:(NSInteger)searchGeneration {
	NSString *typed = query.length > 0 ? query : emoji;
	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] searchStickersByEmoji:emoji query:query limit:40
								  completion:^(NSArray *stickers){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || ![me searchStillCurrent:typed generation:generation
								searchGeneration:searchGeneration])
			return;
		NSMutableDictionary *section = [me searchResultSectionForStickers:stickers];
		if (section != nil)
			[me addSearchSection:section order:0];
	}];
}

- (void)runStickerSearchForQuery:(NSString *)query
					  generation:(NSInteger)generation
				searchGeneration:(NSInteger)searchGeneration {
	if ([query canBeConvertedToEncoding:NSASCIIStringEncoding]){
		__weak TGStickerPanelView *weakSelf = self;
		[[TGClient shared] allStickerEmojisForQuery:query completion:^(NSArray *emojis){
			TGStickerPanelView *me = weakSelf;
			if (me == nil || ![me searchStillCurrent:query generation:generation
									searchGeneration:searchGeneration])
				return;

			if (emojis.count > 0){
				NSArray *head = emojis.count > 5 ? [emojis subarrayWithRange:NSMakeRange(0, 5)] : emojis;
				[me searchStickersByEmoji:[head componentsJoinedByString:@""] forQuery:query
							   generation:generation searchGeneration:searchGeneration];
				return;
			}

			[[TGClient shared] installedStickersMatching:query limit:40
											  completion:^(NSArray *stickers){
				TGStickerPanelView *inner = weakSelf;
				if (inner == nil || ![inner searchStillCurrent:query generation:generation
											  searchGeneration:searchGeneration])
					return;
				NSMutableDictionary *section = [inner searchResultSectionForStickers:stickers];
				if (section != nil)
					[inner addSearchSection:section order:0];
			}];
		}];
		return;
	}

	[self searchStickersByEmoji:query forQuery:nil generation:generation
			   searchGeneration:searchGeneration];
}

- (void)runPublicSetSearchForQuery:(NSString *)query
						generation:(NSInteger)generation
				  searchGeneration:(NSInteger)searchGeneration {
	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] searchStickerSets:query completion:^(NSArray *sets){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || ![me searchStillCurrent:query generation:generation
								searchGeneration:searchGeneration])
			return;

		NSInteger added = 0;
		for (NSDictionary *set in sets){
			if (added >= 6)
				break;
			NSNumber *setId = set[@"id"];
			if ([me knowsSetId:setId])
				continue;
			NSMutableDictionary *section = [me sectionForSet:set kind:TGStickerSectionPublicSet];
			if (section == nil)
				continue;
			section[@"serverMatch"] = query;
			[me insertSearchSection:section order:1];
			added += 1;
		}

		if (added > 0){
			[me applyFilter];
			[me updateStatus];
		}
	}];
}

- (void)runServerSearch {
	NSString *query = self.searchQuery;
	if (query.length == 0)
		return;

	self.searchGeneration += 1;
	NSInteger searchGeneration = self.searchGeneration;
	NSInteger generation = self.generation;

	[self runStickerSearchForQuery:query generation:generation searchGeneration:searchGeneration];
	[self runPublicSetSearchForQuery:query generation:generation searchGeneration:searchGeneration];

	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] searchInstalledStickerSets:query limit:40 completion:^(NSArray *sets){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || me.generation != generation || me.searchGeneration != searchGeneration)
			return;
		if (sets.count == 0 || ![me.searchQuery isEqualToString:query])
			return;

		NSMutableSet *ids = [[NSMutableSet alloc] init];
		for (NSDictionary *set in sets){
			NSNumber *setId = set[@"id"];
			if (setId != nil)
				[ids addObject:setId];
		}

		BOOL changed = NO;
		for (NSMutableDictionary *section in me.allSections){
			NSNumber *setId = section[@"setId"];
			if (setId != nil && [ids containsObject:setId] &&
				![section[@"serverMatch"] isEqualToString:query]){
				section[@"serverMatch"] = query;
				changed = YES;
			}
		}
		if (changed){
			[me applyFilter];
			[me updateStatus];
		}
	}];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
	NSString *query = [text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([query isEqualToString:self.searchQuery])
		return;

	self.searchQuery = query;
	self.searchGeneration += 1;
	[self.searchSections removeAllObjects];
	[self applyFilter];
	[self updateStatus];

	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runServerSearch) object:nil];
	if (query.length > 0)
		[self performSelector:@selector(runServerSearch) withObject:nil afterDelay:0.3];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	[self setSearchVisible:NO];
}

#pragma mark - geometry

- (void)layoutSubviews {
	[super layoutSubviews];

	CGRect bounds = self.bounds;
	CGFloat separator = 1.0f / [UIScreen mainScreen].scale;
	CGFloat searchHeight = self.searchVisible ? TGStickerPanelSearchHeight : 0.0f;
	BOOL landscape = bounds.size.width > bounds.size.height;
	CGFloat tabHeight = landscape ? TGStickerPanelTabHeightLandscape : TGStickerPanelTabHeight;
	self.tabHeight = tabHeight;

	self.topSeparator.frame = CGRectMake(0, 0, bounds.size.width, separator);
	self.searchBar.frame = CGRectMake(0, separator, bounds.size.width, TGStickerPanelSearchHeight);
	self.tabStrip.frame = CGRectMake(0, separator + searchHeight, bounds.size.width, tabHeight);
	CGFloat gridTop = separator + searchHeight + tabHeight;
	self.grid.frame = CGRectMake(0, gridTop, bounds.size.width,
			MAX(0.0f, bounds.size.height - gridTop));

	CGFloat centreY = floorf(self.grid.frame.origin.y + self.grid.frame.size.height / 2.0f);
	self.spinner.frame = CGRectMake(floorf((bounds.size.width - 20) / 2.0f), centreY - 10, 20, 20);
	self.statusLabel.frame = CGRectMake(20, centreY - 34, bounds.size.width - 40, 40);
	self.retryButton.frame = CGRectMake(floorf((bounds.size.width - 120) / 2.0f), centreY + 12, 120, 43);

	// Columns come from a minimum gap, the tile shrinks only when it has to,
	// the leftover width becomes the gap between tiles, and the whole block is
	// centred - so the outer margin is never confused with the inner spacing.
	CGFloat pixel = 1.0f / [UIScreen mainScreen].scale;
	CGFloat available = bounds.size.width - TGStickerPanelTileMinSpacing * 2.0f;
	NSInteger columns = (NSInteger)floorf((available + TGStickerPanelTileMinSpacing) /
			(TGStickerPanelTileSide + TGStickerPanelTileMinSpacing));
	if (columns < TGStickerPanelMinColumns)
		columns = TGStickerPanelMinColumns;

	CGFloat proposed = floorf((available - TGStickerPanelTileMinSpacing * (columns - 1)) / columns);
	CGFloat tileSide = MIN(proposed, TGStickerPanelTileSide);
	if (tileSide < 1.0f)
		tileSide = TGStickerPanelTileSide;
	CGFloat spacing = (columns > 1)
			? floorf((available - tileSide * columns) / (columns - 1) / pixel) * pixel
			: 0.0f;
	if (spacing < TGStickerPanelTileMinSpacing)
		spacing = TGStickerPanelTileMinSpacing;
	CGFloat contentWidth = tileSide * columns + spacing * (columns - 1);
	CGFloat sideInset = floorf((bounds.size.width - contentWidth) / 2.0f);
	if (sideInset < 0.0f)
		sideInset = 0.0f;

	BOOL metricsChanged = (columns != self.columns ||
			fabsf(tileSide - self.tileSide) > 0.01f ||
			fabsf(spacing - self.tileSpacing) > 0.01f);
	BOOL widthChanged = fabsf(bounds.size.width - self.laidOutWidth) > 0.01f;
	self.columns = columns;
	self.tileSide = tileSide;
	self.tileSpacing = spacing;
	self.sideInset = sideInset;
	self.laidOutWidth = bounds.size.width;
	if (metricsChanged || widthChanged || (self.sections.count > 0 && self.grid.contentSize.height < 1.0f))
		[self relayoutSections];
	[self layoutTabs];
	[self layoutPreview];
	[self updateVisibleTiles];
}

- (void)relayoutSections {
	CGFloat previousOffset = self.grid.contentOffset.y;
	NSInteger anchorIndex = -1;
	CGFloat anchorDelta = 0.0f;
	for (NSInteger i = 0; i < (NSInteger)self.sections.count; i++){
		NSNumber *y = self.sections[i][@"y"];
		if (y == nil)
			continue;
		if ([y floatValue] <= previousOffset){
			anchorIndex = i;
			anchorDelta = previousOffset - [y floatValue];
		}
		else
			break;
	}

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
		header.userInteractionEnabled = [section[@"canInstall"] boolValue];
		if (plate != nil)
			header.image = [plate stretchableImageWithLeftCapWidth:1 topCapHeight:0];
		else
			header.backgroundColor = [[TGTheme shared] listBackgroundColour];

		// The same plate carries the same 15pt bold caption everywhere else in
		// the app that uses CategoryDivider.
		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(self.sideInset, 0, width - self.sideInset * 2, TGStickerPanelHeaderHeight)];
		label.backgroundColor = [UIColor clearColor];
		label.font = [UIFont boldSystemFontOfSize:15];
		label.textColor = [UIColor colorWithRed:0x69 / 255.0f green:0x74 / 255.0f
										   blue:0x87 / 255.0f alpha:1.0f];
		label.text = section[@"title"];
		[header addSubview:label];

		if ([section[@"canInstall"] boolValue]){
			UIButton *add = [self addButtonForSectionIndex:index];
			CGFloat addWidth = 52.0f;
			add.frame = CGRectMake(width - self.sideInset - addWidth,
					floorf((TGStickerPanelHeaderHeight - 20.0f) / 2.0f), addWidth, 20.0f);
			label.frame = CGRectMake(self.sideInset, 0,
					MAX(20.0f, width - self.sideInset * 2 - addWidth - 6.0f), TGStickerPanelHeaderHeight);
			[header addSubview:add];
		}
		[self.grid addSubview:header];
		[self.headerViews addObject:header];

		CGFloat body = self.tileSpacing * 2.0f + rows * self.tileSide +
				(rows - 1) * self.tileSpacing;
		section[@"height"] = @(TGStickerPanelHeaderHeight + body);
		y += TGStickerPanelHeaderHeight + body;
		index += 1;
	}

	self.grid.contentSize = CGSizeMake(width, y);

	if (anchorIndex >= 0 && anchorIndex < (NSInteger)self.sections.count){
		CGFloat restored = [self.sections[anchorIndex][@"y"] floatValue] + anchorDelta;
		CGFloat maxOffset = MAX(0.0f, self.grid.contentSize.height - self.grid.bounds.size.height);
		restored = MAX(0.0f, MIN(restored, maxOffset));
		if (fabsf(restored - previousOffset) > 0.5f)
			self.grid.contentOffset = CGPointMake(0, restored);
	}

	[self clearTiles];
	[self updateVisibleTiles];
}

- (UIButton *)addButtonForSectionIndex:(NSInteger)index {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.tag = TGStickerPanelAddButtonTag + index;
	UIImage *plate = [UIImage imageNamed:@"GroupedActionButton.png"];
	UIImage *platePressed = [UIImage imageNamed:@"GroupedActionButton_Highlighted.png"];
	if (plate != nil)
		[button setBackgroundImage:[plate stretchableImageWithLeftCapWidth:24 topCapHeight:0]
						  forState:UIControlStateNormal];
	if (platePressed != nil)
		[button setBackgroundImage:[platePressed stretchableImageWithLeftCapWidth:24 topCapHeight:0]
						  forState:UIControlStateHighlighted];
	[button setTitle:@"ADD" forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont boldSystemFontOfSize:11];
	button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	button.exclusiveTouch = YES;
	[button addTarget:self action:@selector(addSetTapped:)
	 forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (void)addSetTapped:(UIButton *)button {
	NSInteger index = button.tag - TGStickerPanelAddButtonTag;
	if (index < 0 || index >= (NSInteger)self.sections.count)
		return;

	NSMutableDictionary *section = self.sections[index];
	int64_t setId = [section[@"setId"] longLongValue];
	if (setId == 0)
		return;

	button.enabled = NO;
	NSInteger generation = self.generation;
	NSMutableDictionary *target = section;

	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] installStickerSet:setId completion:^(BOOL ok){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || me.generation != generation)
			return;
		if (!ok){
			button.enabled = YES;
			return;
		}
		[target removeObjectForKey:@"canInstall"];
		[me relayoutSections];
		[me checkArchivedAfterInstall];
	}];
}

- (void)checkArchivedAfterInstall {
	NSInteger generation = self.generation;
	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] installedStickerSetsWithCompletion:^(NSArray *installed){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || me.generation != generation || installed == nil)
			return;

		NSMutableSet *installedIds = [[NSMutableSet alloc] init];
		for (NSDictionary *set in installed){
			NSNumber *setId = set[@"id"];
			if (setId != nil)
				[installedIds addObject:setId];
		}

		NSMutableArray *lost = [[NSMutableArray alloc] init];
		for (NSMutableDictionary *section in me.allSections){
			if ([section[@"kind"] integerValue] != TGStickerSectionSet)
				continue;
			NSNumber *setId = section[@"setId"];
			if (setId != nil && ![installedIds containsObject:setId] && section[@"title"] != nil)
				[lost addObject:section[@"title"]];
		}

		if (lost.count > 0)
			[me showArchivedNoticeForTitles:lost];
	}];
}

- (void)showArchivedNoticeForTitles:(NSArray *)titles {
	if (self.currentActionSheet != nil)
		return;

	NSString *names = [titles componentsJoinedByString:@", "];
	NSString *message = [NSString stringWithFormat:
			@"You have too many sticker packs. These were moved to the archive:\n%@", names];

	NSMutableArray *actions = [[NSMutableArray alloc] init];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Refresh Packs" action:@"refresh"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"OK" action:@"cancel"
															 type:TGActionSheetActionTypeCancel]];

	__weak TGStickerPanelView *weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:message actions:actions
													   actionBlock:^(__unused id target, NSString *action){
		TGStickerPanelView *me = weakSelf;
		if (me == nil)
			return;
		me.currentActionSheet = nil;
		if ([action isEqualToString:@"refresh"])
			[me reload];
	} target:self];
	[self.currentActionSheet showInView:self.window ?: self];
}

- (CGRect)frameForItem:(NSInteger)item inSection:(NSInteger)sectionIndex {
	NSDictionary *section = self.sections[sectionIndex];
	CGFloat sectionY = [section[@"y"] floatValue];
	NSInteger row = item / self.columns;
	NSInteger column = item % self.columns;
	CGFloat x = self.sideInset + column * (self.tileSide + self.tileSpacing);
	CGFloat y = sectionY + TGStickerPanelHeaderHeight + self.tileSpacing +
			row * (self.tileSide + self.tileSpacing);
	return CGRectMake(floorf(x), floorf(y), self.tileSide, self.tileSide);
}

#pragma mark - tiles

- (void)clearTiles {
	for (NSString *key in [self.visibleTiles allKeys]){
		TGStickerTile *tile = self.visibleTiles[key];
		[self releaseImageForTile:tile];
		[self.recycler recycleView:tile];
	}
	[self.visibleTiles removeAllObjects];
}

- (void)updateVisibleTiles {
	if (self.sections.count == 0)
		return;

	// One row of headroom either side, the same window Telegram's own pager
	// allocates item layers for. Anything past it is recycled and its download
	// and decode are cancelled.
	CGFloat row = self.tileSide + self.tileSpacing;
	CGRect visible = CGRectMake(0, self.grid.contentOffset.y - row,
			self.grid.bounds.size.width, self.grid.bounds.size.height + row * 2.0f);

	NSMutableSet *wanted = [[NSMutableSet alloc] init];
	NSMutableArray *nowViewed = nil;

	for (NSInteger s = 0; s < (NSInteger)self.sections.count; s++){
		NSMutableDictionary *section = self.sections[s];
		CGFloat sectionY = [section[@"y"] floatValue];
		CGFloat sectionHeight = [section[@"height"] floatValue];
		if (sectionY + sectionHeight < CGRectGetMinY(visible) || sectionY > CGRectGetMaxY(visible))
			continue;

		if ([section[@"kind"] integerValue] == TGStickerSectionTrending &&
			section[@"viewedSent"] == nil && section[@"setId"] != nil){
			section[@"viewedSent"] = @YES;
			if (nowViewed == nil)
				nowViewed = [[NSMutableArray alloc] init];
			[nowViewed addObject:section[@"setId"]];
		}

		NSArray *stickers = section[@"stickers"];
		NSInteger count = [section[@"count"] integerValue];
		NSInteger highestWanted = -1;

		for (NSInteger i = 0; i < count; i++){
			CGRect frame = [self frameForItem:i inSection:s];
			if (CGRectGetMaxY(frame) < CGRectGetMinY(visible))
				continue;
			if (frame.origin.y > CGRectGetMaxY(visible))
				break;

			highestWanted = i;
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
				press.minimumPressDuration = 0.2;
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

		[self ensureSection:s loadedUpToItem:MAX(highestWanted, 0)];
	}

	for (NSString *key in [self.visibleTiles allKeys]){
		if ([wanted containsObject:key])
			continue;
		[self releaseImageForTile:self.visibleTiles[key]];
		[self.recycler recycleView:self.visibleTiles[key]];
		[self.visibleTiles removeObjectForKey:key];
	}

	if (nowViewed.count > 0)
		[[TGClient shared] markTrendingStickerSetsViewed:nowViewed];

	[self reportOpenTiming];
	[self purgeDistantSectionsAggressively:NO];
}

/// One line per panel open, once the first screenful has stopped waiting on
/// anything. "restored" means the pack list came from the in-process snapshot
/// rather than from five TDLib round trips.
- (void)reportOpenTiming {
	if (self.openTimingReported || self.visibleTiles.count == 0)
		return;
	for (NSString *key in self.visibleTiles){
		TGStickerTile *tile = self.visibleTiles[key];
		// A tile with no sticker yet is a section still being fetched, and a
		// tile still holding a token is a thumbnail still in flight.
		if (tile.sticker == nil || tile.imageToken != nil)
			return;
	}

	self.openTimingReported = YES;
	NSLog(@"PERF stickers open +%.0f ms: %lu tiles, %@, %@",
			([NSDate timeIntervalSinceReferenceDate] - self.openedAt) * 1000.0,
			(unsigned long)self.visibleTiles.count,
			self.restoredFromSnapshot ? @"restored" : @"cold",
			[TGStickerThumbnailCache statisticsSummary]);
}

- (void)purgeDistantSectionsAggressively:(BOOL)aggressive {
	CGFloat offset = self.grid.contentOffset.y;
	CGFloat height = self.grid.bounds.size.height;

	NSMutableArray *candidates = [[NSMutableArray alloc] initWithArray:self.allSections];
	for (NSMutableDictionary *section in self.searchSections){
		if ([candidates indexOfObjectIdenticalTo:section] == NSNotFound)
			[candidates addObject:section];
	}

	for (NSMutableDictionary *section in candidates){
		NSInteger kind = [section[@"kind"] integerValue];
		if (!TGStickerSectionIsSet(kind))
			continue;
		if (section[@"stickers"] == nil || [section[@"loading"] boolValue])
			continue;

		BOOL displayed = ([self.sections indexOfObjectIdenticalTo:section] != NSNotFound);
		BOOL purge = !displayed;
		if (displayed){
			NSNumber *y = section[@"y"];
			if (y == nil)
				purge = YES;
			else {
				CGFloat top = [y floatValue];
				CGFloat bottom = top + [section[@"height"] floatValue];
				CGFloat distance = 0.0f;
				if (bottom < offset)
					distance = offset - bottom;
				else if (top > offset + height)
					distance = top - (offset + height);
				purge = (distance > (aggressive ? 0.0f : TGStickerPanelPurgeDistance));
			}
		}

		if (!purge)
			continue;

		[section removeObjectForKey:@"stickers"];
		[section removeObjectForKey:@"loadedCount"];
		[section removeObjectForKey:@"complete"];
	}
}

- (void)configureTile:(TGStickerTile *)tile withSticker:(NSDictionary *)sticker {
	if (sticker == nil){
		[self releaseImageForTile:tile];
		tile.sticker = nil;
		tile.emojiLabel.text = @"";
		tile.imageView.image = nil;
		tile.imageView.alpha = 1.0f;
		return;
	}

	NSString *emoji = sticker[@"emoji"];
	NSInteger fileId = [self drawableFileIdForSticker:sticker];
	NSString *uniqueId = [self drawableUniqueIdForSticker:sticker];

	if (fileId == 0 && uniqueId.length == 0){
		[self releaseImageForTile:tile];
		tile.sticker = sticker;
		tile.emojiLabel.text = emoji.length > 0 ? emoji : @"";
		tile.imageView.image = nil;
		tile.imageView.alpha = 1.0f;
		return;
	}

	CGFloat side = self.tileSide;
	NSString *key = [NSString stringWithFormat:@"%@|%d@%d", uniqueId, (int)fileId, (int)side];
	UIImage *cached = [TGStickerThumbnailCache cachedThumbnailForUniqueId:uniqueId side:side];
	if (cached != nil){
		[self releaseImageForTile:tile];
		tile.sticker = sticker;
		tile.emojiLabel.text = @"";
		tile.imageView.image = cached;
		tile.imageView.alpha = 1.0f;
		return;
	}

	// Already waiting on exactly this image for exactly this sticker: leave the
	// request alone rather than cancelling and restarting it on every scroll.
	if (tile.sticker == sticker && [tile.imageKey isEqualToString:key])
		return;

	[self releaseImageForTile:tile];
	tile.sticker = sticker;
	tile.emojiLabel.text = emoji.length > 0 ? emoji : @"";
	tile.imageView.image = nil;
	tile.imageView.alpha = 1.0f;
	tile.imageKey = key;

	NSDictionary *requested = sticker;
	__weak TGStickerTile *weakTile = tile;
	tile.imageToken = [TGStickerThumbnailCache thumbnailForFileId:fileId uniqueId:uniqueId
															 side:side
													   completion:^(UIImage *image){
		TGStickerTile *target = weakTile;
		if (target == nil)
			return;
		if (target.sticker != requested || ![target.imageKey isEqualToString:key])
			return;
		target.imageToken = nil;
		if (image == nil)
			return;
		target.imageKey = nil;
		target.imageView.image = image;
		target.emojiLabel.text = @"";
		target.imageView.alpha = 0.0f;
		[UIView animateWithDuration:0.15 animations:^{
			target.imageView.alpha = 1.0f;
		}];
	}];
}

- (NSInteger)drawableFileIdForSticker:(NSDictionary *)sticker {
	BOOL drawable = ![sticker[@"isVideo"] boolValue] && ![sticker[@"isAnimated"] boolValue];
	NSInteger thumbId = [sticker[@"thumbId"] integerValue];
	if (thumbId != 0)
		return thumbId;
	return drawable ? [sticker[@"fileId"] integerValue] : 0;
}

/// The disk cache has to be keyed on something that outlives the session, and
/// TGClient+Files.h is explicit that the file id is not that. Pick the unique
/// id of whichever file drawableFileIdForSticker: settled on.
- (NSString *)drawableUniqueIdForSticker:(NSDictionary *)sticker {
	BOOL drawable = ![sticker[@"isVideo"] boolValue] && ![sticker[@"isAnimated"] boolValue];
	NSString *thumbUniqueId = sticker[@"thumbUniqueId"];
	if ([sticker[@"thumbId"] integerValue] != 0)
		return [thumbUniqueId isKindOfClass:[NSString class]] ? thumbUniqueId : @"";
	if (!drawable)
		return @"";
	NSString *uniqueId = sticker[@"uniqueId"];
	return [uniqueId isKindOfClass:[NSString class]] ? uniqueId : @"";
}

#pragma mark - tabs

- (void)rebuildTabs {
	[self cancelTabImageLoads];
	for (UIView *view in [self.tabStrip.subviews copy])
		[view removeFromSuperview];
	[self.tabButtons removeAllObjects];
	[self.tabDividers removeAllObjects];

	NSInteger total = (NSInteger)self.sections.count + 2;
	NSInteger index = 0;

	for (NSMutableDictionary *section in self.sections){
		UIButton *button = [self tabButtonAtIndex:index total:total];
		button.tag = index;
		[button addTarget:self action:@selector(tabTapped:)
		 forControlEvents:UIControlEventTouchUpInside];

		NSNumber *thumbId = section[@"tabThumbId"];
		NSString *thumbUniqueId = section[@"tabThumbUniqueId"];
		if (![thumbUniqueId isKindOfClass:[NSString class]])
			thumbUniqueId = @"";

		if (thumbId != nil || thumbUniqueId.length > 0){
			UIImage *cached = [TGStickerThumbnailCache
					cachedThumbnailForUniqueId:thumbUniqueId side:TGStickerPanelTabThumbSide];
			if (cached != nil){
				[button setImage:cached forState:UIControlStateNormal];
			}
			else {
				[button setTitle:[self shortTabTitle:section[@"tabTitle"]] forState:UIControlStateNormal];
				__weak UIButton *weakButton = button;
				id token = [TGStickerThumbnailCache thumbnailForFileId:[thumbId integerValue]
															  uniqueId:thumbUniqueId
																  side:TGStickerPanelTabThumbSide
															completion:^(UIImage *image){
					UIButton *target = weakButton;
					if (target == nil || image == nil)
						return;
					[target setTitle:@"" forState:UIControlStateNormal];
					[target setImage:image forState:UIControlStateNormal];
				}];
				if (token != nil)
					[self.tabImageTokens addObject:token];
			}
		}
		else {
			[button setTitle:[self shortTabTitle:section[@"tabTitle"]] forState:UIControlStateNormal];
		}

		[self.tabStrip addSubview:button];
		[self.tabButtons addObject:button];
		index += 1;
	}

	UIButton *search = [self tabButtonAtIndex:index total:total];
	search.tag = -2;
	[search setTitle:@"Find" forState:UIControlStateNormal];
	search.selected = self.searchVisible;
	[search addTarget:self action:@selector(toggleSearch)
	 forControlEvents:UIControlEventTouchUpInside];
	[self.tabStrip addSubview:search];
	[self.tabButtons addObject:search];
	index += 1;

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

/// A group-button strip carries a real 2pt divider between neighbours, and the
/// divider next to the pressed plate is a different piece of art on each side.
/// Overlapping one plain divider over the seam is what made the strip look
/// stuck on rather than part of the bar.
- (UIImageView *)tabDividerView {
	UIImageView *view = [[UIImageView alloc] initWithFrame:CGRectZero];
	UIImage *plain = [UIImage imageNamed:@"ButtonGroupDivider.png"];
	if (plain != nil)
		view.image = [plain stretchableImageWithLeftCapWidth:6 topCapHeight:0];
	view.contentMode = UIViewContentModeScaleToFill;
	return view;
}

- (void)layoutTabs {
	for (UIView *view in self.tabDividers)
		[view removeFromSuperview];
	[self.tabDividers removeAllObjects];

	CGFloat height = self.tabHeight;
	CGFloat x = 0;
	NSInteger index = 0;
	NSInteger last = (NSInteger)self.tabButtons.count - 1;

	for (UIButton *button in self.tabButtons){
		CGFloat width = TGStickerPanelTabMinWidth;
		NSString *title = [button titleForState:UIControlStateNormal];
		if (title.length > 0){
			CGSize size = [title sizeWithFont:button.titleLabel.font];
			width = MAX(TGStickerPanelTabMinWidth, floorf(size.width) + 14.0f);
		}
		button.frame = CGRectMake(floorf(x), 0, width, height);
		x += width;

		if (index < last){
			UIImageView *divider = [self tabDividerView];
			divider.frame = CGRectMake(floorf(x), 0, TGStickerPanelTabDividerWidth, height);
			[self.tabStrip addSubview:divider];
			[self.tabDividers addObject:divider];
			x += TGStickerPanelTabDividerWidth;
		}
		index += 1;
	}
	self.tabStrip.contentSize = CGSizeMake(x, height);
	[self updateTabDividers];
}

- (void)updateTabDividers {
	NSInteger selected = -1;
	NSInteger index = 0;
	for (UIButton *button in self.tabButtons){
		if (button.selected){
			selected = index;
			break;
		}
		index += 1;
	}

	UIImage *plain = [UIImage imageNamed:@"ButtonGroupDivider.png"];
	UIImage *leftLit = [UIImage imageNamed:@"ButtonGroupDivider_LeftHighlighted.png"];
	UIImage *rightLit = [UIImage imageNamed:@"ButtonGroupDivider_RightHighlighted.png"];

	for (NSInteger i = 0; i < (NSInteger)self.tabDividers.count; i++){
		UIImageView *divider = self.tabDividers[i];
		UIImage *wanted = plain;
		if (selected == i)
			wanted = leftLit ?: plain;
		else if (selected == i + 1)
			wanted = rightLit ?: plain;
		if (wanted == nil)
			continue;
		divider.image = [wanted stretchableImageWithLeftCapWidth:6 topCapHeight:0];
	}
}

- (void)updateTabSelection {
	NSInteger index = 0;
	for (UIButton *button in self.tabButtons){
		if (button.tag == -2)
			button.selected = self.searchVisible;
		else
			button.selected = (button.tag >= 0 && index == self.selectedSection);
		index += 1;
	}
	[self updateTabDividers];
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
	if (self.searchVisible)
		[self.searchBar resignFirstResponder];
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
	self.retryButton.hidden = !(empty && self.failed && self.searchQuery.length == 0);
	self.grid.hidden = empty;

	if (!empty)
		return;

	if (self.searchQuery.length > 0)
		self.statusLabel.text = @"No sticker sets found.";
	else
		self.statusLabel.text = self.failed ? @"Stickers could not be loaded."
											: @"No sticker sets installed yet.";
}

#pragma mark - interaction

- (void)tileTapped:(TGStickerTile *)tile {
	NSDictionary *sticker = tile.sticker;
	if (sticker == nil)
		return;

	if (self.searchVisible)
		[self.searchBar resignFirstResponder];

	NSInteger fileId = [sticker[@"fileId"] integerValue];
	if (fileId != 0)
		[[TGClient shared] addRecentStickerWithFileId:fileId];

	if (self.onStickerPicked)
		self.onStickerPicked(sticker);
}

#pragma mark - preview

/// Holding a sticker shows it big before anything else happens, the way the
/// current client peeks one: a 180pt bounding box with the sticker's emoji
/// above it. Letting go brings up the actions.
- (void)cancelPreviewLoad {
	if (self.previewToken != nil)
		[TGStickerThumbnailCache cancelRequest:self.previewToken];
	self.previewToken = nil;
}

/// The panel is only as tall as a keyboard, so the peek goes over the window
/// the way the action sheet does; inside the panel the emoji above the sticker
/// would be clipped away.
- (void)layoutPreview {
	if (self.previewOverlay == nil || self.previewOverlay.hidden)
		return;
	UIView *host = self.previewOverlay.superview;
	if (host == nil)
		return;

	CGRect bounds = host.bounds;
	self.previewOverlay.frame = bounds;

	CGFloat side = MIN(TGStickerPanelPreviewSide,
			MIN(bounds.size.width - 24.0f, bounds.size.height - 96.0f));
	if (side < 1.0f)
		side = 1.0f;
	CGFloat centreX = floorf(bounds.size.width / 2.0f);
	CGFloat centreY = floorf(bounds.size.height / 2.0f);
	self.previewImageView.frame = CGRectMake(floorf(centreX - side / 2.0f),
			floorf(centreY - side / 2.0f), side, side);
	// 32pt emoji, 10pt clear of the sticker, exactly as the current client
	// stacks a peeked sticker.
	self.previewEmojiLabel.frame = CGRectMake(0,
			CGRectGetMinY(self.previewImageView.frame) - 48.0f, bounds.size.width, 38.0f);
}

- (void)showPreviewForSticker:(NSDictionary *)sticker {
	if (self.previewOverlay == nil){
		_previewOverlay = [[UIView alloc] initWithFrame:CGRectZero];
		_previewOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45f];
		_previewOverlay.userInteractionEnabled = NO;

		_previewEmojiLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_previewEmojiLabel.backgroundColor = [UIColor clearColor];
		_previewEmojiLabel.textAlignment = UITextAlignmentCenter;
		_previewEmojiLabel.font = [UIFont systemFontOfSize:32];
		[_previewOverlay addSubview:_previewEmojiLabel];

		_previewImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_previewImageView.contentMode = UIViewContentModeScaleAspectFit;
		[_previewOverlay addSubview:_previewImageView];
	}

	UIView *host = self.window ?: self;
	if (self.previewOverlay.superview != host)
		[host addSubview:self.previewOverlay];

	NSString *emoji = sticker[@"emoji"];
	self.previewEmojiLabel.text = [emoji isKindOfClass:[NSString class]] ? emoji : @"";
	self.previewOverlay.hidden = NO;
	[host bringSubviewToFront:self.previewOverlay];
	[self layoutPreview];

	CGFloat side = self.previewImageView.frame.size.width;
	NSInteger fileId = [self drawableFileIdForSticker:sticker];
	NSString *uniqueId = [self drawableUniqueIdForSticker:sticker];

	UIImage *cached = [TGStickerThumbnailCache cachedThumbnailForUniqueId:uniqueId side:side];
	self.previewImageView.image = cached;
	if (cached != nil)
		return;

	// Something to look at while the big one decodes.
	self.previewImageView.image =
			[TGStickerThumbnailCache cachedThumbnailForUniqueId:uniqueId side:self.tileSide];

	[self cancelPreviewLoad];
	__weak TGStickerPanelView *weakSelf = self;
	self.previewToken = [TGStickerThumbnailCache thumbnailForFileId:fileId uniqueId:uniqueId
															   side:side
														 completion:^(UIImage *image){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || image == nil)
			return;
		me.previewToken = nil;
		if (me.previewOverlay.hidden)
			return;
		me.previewImageView.image = image;
	}];
}

- (void)hidePreview {
	[self cancelPreviewLoad];
	if (self.previewOverlay == nil)
		return;
	self.previewOverlay.hidden = YES;
	self.previewImageView.image = nil;
	[self.previewOverlay removeFromSuperview];
}

- (void)tileLongPressed:(UILongPressGestureRecognizer *)recogniser {
	if (![recogniser.view isKindOfClass:[TGStickerTile class]])
		return;

	TGStickerTile *tile = (TGStickerTile *)recogniser.view;
	NSDictionary *sticker = tile.sticker;
	NSInteger fileId = [sticker[@"fileId"] integerValue];

	if (recogniser.state == UIGestureRecognizerStateBegan){
		if (fileId == 0 || self.currentActionSheet != nil)
			return;
		[self showPreviewForSticker:sticker];
		return;
	}

	if (recogniser.state != UIGestureRecognizerStateEnded &&
		recogniser.state != UIGestureRecognizerStateCancelled &&
		recogniser.state != UIGestureRecognizerStateFailed)
		return;

	BOOL wasPreviewing = (self.previewOverlay != nil && !self.previewOverlay.hidden);
	[self hidePreview];

	if (!wasPreviewing || recogniser.state != UIGestureRecognizerStateEnded)
		return;
	if (fileId == 0 || self.currentActionSheet != nil)
		return;

	NSInteger sectionIndex = tile.sectionIndex;
	NSInteger generation = self.generation;
	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] isStickerFavoriteWithFileId:fileId completion:^(BOOL favourite){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || me.generation != generation)
			return;
		[me presentMenuForSticker:sticker sectionIndex:sectionIndex favourite:favourite];
	}];
}

- (NSInteger)sectionIndexForSetId:(NSNumber *)setId {
	if (setId == nil || [setId longLongValue] == 0)
		return -1;
	for (NSInteger i = 0; i < (NSInteger)self.sections.count; i++){
		NSNumber *candidate = self.sections[i][@"setId"];
		if (candidate != nil && [candidate isEqualToNumber:setId])
			return i;
	}
	return -1;
}

- (void)presentMenuForSticker:(NSDictionary *)sticker
				 sectionIndex:(NSInteger)sectionIndex
					favourite:(BOOL)favourite {
	if (self.currentActionSheet != nil)
		return;
	if (sectionIndex < 0 || sectionIndex >= (NSInteger)self.sections.count)
		return;

	NSMutableDictionary *section = self.sections[sectionIndex];
	NSInteger kind = [section[@"kind"] integerValue];

	self.menuSticker = sticker;
	self.menuSectionIndex = sectionIndex;
	self.menuStickerFavourite = favourite;

	NSMutableArray *actions = [[NSMutableArray alloc] init];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Send Sticker" action:@"send"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:
			favourite ? @"Remove from Favourites" : @"Add to Favourites" action:@"favourite"]];

	NSNumber *setId = sticker[@"setId"];
	if (setId == nil || [setId longLongValue] == 0)
		setId = section[@"setId"];
	if (TGStickerSectionIsSet(kind) == NO && [self sectionIndexForSetId:setId] >= 0)
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"View Pack" action:@"pack"]];

	if (kind == TGStickerSectionRecent)
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Remove from Recent"
															   action:@"unrecent"
																 type:TGActionSheetActionTypeDestructive]];

	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
															 type:TGActionSheetActionTypeCancel]];

	NSString *title = sticker[@"emoji"];
	if (title.length == 0)
		title = section[@"title"];

	__weak TGStickerPanelView *weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:title actions:actions
													   actionBlock:^(__unused id target, NSString *action){
		TGStickerPanelView *me = weakSelf;
		if (me == nil)
			return;
		me.currentActionSheet = nil;
		[me performStickerMenuAction:action];
	} target:self];
	[self.currentActionSheet showInView:self.window ?: self];
}

- (void)performStickerMenuAction:(NSString *)action {
	NSDictionary *sticker = self.menuSticker;
	NSInteger sectionIndex = self.menuSectionIndex;
	BOOL favourite = self.menuStickerFavourite;
	self.menuSticker = nil;
	self.menuSectionIndex = -1;

	NSInteger fileId = [sticker[@"fileId"] integerValue];
	if (sticker == nil || fileId == 0)
		return;

	if ([action isEqualToString:@"send"]){
		[[TGClient shared] addRecentStickerWithFileId:fileId];
		if (self.onStickerPicked)
			self.onStickerPicked(sticker);
		return;
	}

	if ([action isEqualToString:@"favourite"]){
		if (favourite)
			[[TGClient shared] removeFavoriteStickerWithFileId:fileId];
		else
			[[TGClient shared] addFavoriteStickerWithFileId:fileId];
		[self refreshFavourites];
		return;
	}

	if ([action isEqualToString:@"unrecent"]){
		[[TGClient shared] removeRecentStickerWithFileId:fileId];
		[self removeRecentSticker:sticker];
		return;
	}

	if ([action isEqualToString:@"pack"]){
		NSNumber *setId = sticker[@"setId"];
		if ((setId == nil || [setId longLongValue] == 0) &&
			sectionIndex >= 0 && sectionIndex < (NSInteger)self.sections.count)
			setId = self.sections[sectionIndex][@"setId"];
		NSInteger target = [self sectionIndexForSetId:setId];
		if (target >= 0)
			[self setSelectedSection:target scrollGrid:YES];
	}
}

- (void)removeRecentSticker:(NSDictionary *)sticker {
	NSMutableDictionary *section = nil;
	for (NSMutableDictionary *candidate in self.allSections){
		if ([candidate[@"kind"] integerValue] == TGStickerSectionRecent){
			section = candidate;
			break;
		}
	}
	if (section == nil)
		return;

	NSMutableArray *stickers = section[@"stickers"];
	NSInteger index = (NSInteger)[stickers indexOfObjectIdenticalTo:sticker];
	if (stickers == nil || index == (NSInteger)NSNotFound)
		return;

	[stickers removeObjectAtIndex:index];
	if (stickers.count == 0){
		[self reload];
		return;
	}

	section[@"loadedCount"] = @(stickers.count);
	section[@"count"] = @(stickers.count);
	[self takeSectionSnapshot];
	[self relayoutSections];
}

- (void)refreshFavourites {
	NSInteger generation = self.generation;
	__weak TGStickerPanelView *weakSelf = self;
	[[TGClient shared] favoriteStickersWithCompletion:^(NSArray *stickers){
		TGStickerPanelView *me = weakSelf;
		if (me == nil || me.generation != generation || stickers == nil)
			return;

		NSInteger index = -1;
		for (NSInteger i = 0; i < (NSInteger)me.allSections.count; i++){
			if ([me.allSections[i][@"kind"] integerValue] == TGStickerSectionFavourite){
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

		NSMutableDictionary *section = me.allSections[index];
		section[@"stickers"] = [stickers mutableCopy];
		section[@"loadedCount"] = @(stickers.count);
		section[@"complete"] = @YES;
		section[@"count"] = @(stickers.count);
		[me takeSectionSnapshot];
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

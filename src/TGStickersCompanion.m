#import "TGStickersCompanion.h"
#import "TGStickerModel.h"
#import "TGClient.h"
#import "TGClient+Stickers.h"
#import <UIKit/UIKit.h>

static const NSInteger TGStickersArchivedPageSize = 24;
static const NSInteger TGStickersTrendingPageSize = 20;
static const NSInteger TGStickersSearchLimit = 40;
static const NSInteger TGStickersSectionCount = 7;

@interface TGStickersCompanion () {
	TGStickerKind _kind;

	NSMutableArray *_installedSets;
	NSMutableArray *_archivedSets;
	NSMutableArray *_trendingSets;
	NSMutableArray *_favouriteStickers;
	NSMutableArray *_recentStickers;
	NSMutableArray *_setStickers;
	NSMutableArray *_searchResults;

	TGStickerSetModel *_openSet;

	TGStickersLoadState _states[7];
	NSInteger _archivedTotal;
	NSInteger _trendingTotal;

	BOOL _archivedLoading;
	BOOL _trendingLoading;
	BOOL _archivedAtEnd;
	BOOL _trendingAtEnd;

	NSInteger _searchGeneration;
	NSInteger _setGeneration;
	NSMutableSet *_favouriteFileIds;
}
@end

@implementation TGStickersCompanion

@synthesize delegate = _delegate;

- (id)init {
	return [self initWithKind:TGStickerKindRegular];
}

- (id)initWithKind:(TGStickerKind)kind {
	self = [super init];
	if (self != nil) {
		_kind = kind;
		_installedSets = [[NSMutableArray alloc] init];
		_archivedSets = [[NSMutableArray alloc] init];
		_trendingSets = [[NSMutableArray alloc] init];
		_favouriteStickers = [[NSMutableArray alloc] init];
		_recentStickers = [[NSMutableArray alloc] init];
		_setStickers = [[NSMutableArray alloc] init];
		_searchResults = [[NSMutableArray alloc] init];
		_favouriteFileIds = [[NSMutableSet alloc] init];
		for (NSInteger i = 0; i < TGStickersSectionCount; i++) {
			_states[i] = TGStickersLoadStateIdle;
		}
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(handleMemoryWarning)
		                                             name:UIApplicationDidReceiveMemoryWarningNotification
		                                           object:nil];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (TGStickerKind)kind {
	return _kind;
}

- (NSArray *)installedSets { return _installedSets; }
- (NSArray *)archivedSets { return _archivedSets; }
- (NSArray *)trendingSets { return _trendingSets; }
- (NSArray *)favouriteStickers { return _favouriteStickers; }
- (NSArray *)recentStickers { return _recentStickers; }
- (NSArray *)setStickers { return _setStickers; }
- (NSArray *)searchResults { return _searchResults; }
- (TGStickerSetModel *)openSet { return _openSet; }

#pragma mark - state

- (TGStickersLoadState)stateForSection:(TGStickersSection)section {
	if (section < 0 || section >= TGStickersSectionCount) {
		return TGStickersLoadStateIdle;
	}
	return _states[section];
}

- (void)setState:(TGStickersLoadState)state forSection:(TGStickersSection)section {
	if (section < 0 || section >= TGStickersSectionCount) {
		return;
	}
	if (_states[section] == state) {
		return;
	}
	_states[section] = state;
	if ([_delegate respondsToSelector:@selector(stickersCompanion:section:didChangeState:)]) {
		[_delegate stickersCompanion:self section:section didChangeState:state];
	}
}

- (void)setLoadedState:(TGStickersSection)section empty:(BOOL)empty {
	[self setState:(empty ? TGStickersLoadStateEmpty : TGStickersLoadStateLoaded) forSection:section];
}

- (NSInteger)totalCountForSection:(TGStickersSection)section {
	if (section == TGStickersSectionArchived) {
		return _archivedTotal;
	}
	if (section == TGStickersSectionTrending) {
		return _trendingTotal;
	}
	return 0;
}

- (void)notifyReload:(TGStickersSection)section {
	if ([_delegate respondsToSelector:@selector(stickersCompanion:didReloadSection:)]) {
		[_delegate stickersCompanion:self didReloadSection:section];
	}
}

- (void)notifySection:(TGStickersSection)section inserted:(NSArray *)inserted removed:(NSArray *)removed {
	if ([inserted count] == 0 && [removed count] == 0) {
		return;
	}
	if ([_delegate respondsToSelector:@selector(stickersCompanion:section:didInsertRows:removedRows:)]) {
		[_delegate stickersCompanion:self
		                     section:section
		               didInsertRows:(inserted != nil ? inserted : [NSArray array])
		                 removedRows:(removed != nil ? removed : [NSArray array])];
	}
}

- (void)notifySection:(TGStickersSection)section updated:(NSArray *)rows {
	if ([rows count] == 0) {
		return;
	}
	if ([_delegate respondsToSelector:@selector(stickersCompanion:section:didUpdateRows:)]) {
		[_delegate stickersCompanion:self section:section didUpdateRows:rows];
	}
}

- (void)failSection:(TGStickersSection)section message:(NSString *)message {
	[self setState:TGStickersLoadStateFailed forSection:section];
	if ([_delegate respondsToSelector:@selector(stickersCompanion:didFailWithMessage:section:)]) {
		[_delegate stickersCompanion:self didFailWithMessage:message section:section];
	}
}

- (NSArray *)rangeRowsFrom:(NSInteger)start count:(NSInteger)count {
	NSMutableArray *rows = [NSMutableArray arrayWithCapacity:(count > 0 ? count : 1)];
	for (NSInteger i = 0; i < count; i++) {
		[rows addObject:[NSNumber numberWithInteger:start + i]];
	}
	return rows;
}

#pragma mark - reading helpers

- (TGStickerSetModel *)setWithId:(int64_t)setId {
	NSArray *lists = [NSArray arrayWithObjects:_installedSets, _trendingSets, _archivedSets, _searchResults, nil];
	for (NSArray *list in lists) {
		for (TGStickerSetModel *set in list) {
			if (set.setId == setId) {
				return set;
			}
		}
	}
	if (_openSet != nil && _openSet.setId == setId) {
		return _openSet;
	}
	return nil;
}

- (NSInteger)indexOfSetId:(int64_t)setId inList:(NSArray *)list {
	NSInteger count = (NSInteger)[list count];
	for (NSInteger i = 0; i < count; i++) {
		TGStickerSetModel *set = [list objectAtIndex:i];
		if (set.setId == setId) {
			return i;
		}
	}
	return NSNotFound;
}

- (BOOL)isFavouriteFileId:(NSInteger)fileId {
	return [_favouriteFileIds containsObject:[NSNumber numberWithInteger:fileId]];
}

- (void)rebuildFavouriteIndex {
	[_favouriteFileIds removeAllObjects];
	for (TGStickerModel *sticker in _favouriteStickers) {
		[_favouriteFileIds addObject:[NSNumber numberWithInteger:sticker.fileId]];
	}
}

#pragma mark - loading

- (void)reload {
	[self reloadSection:TGStickersSectionInstalled];
	[self reloadSection:TGStickersSectionFavourites];
	[self reloadSection:TGStickersSectionRecents];
	[self reloadSection:TGStickersSectionTrending];
	[self reloadSection:TGStickersSectionArchived];
}

- (void)reloadSection:(TGStickersSection)section {
	switch (section) {
		case TGStickersSectionInstalled:
			[self loadInstalled];
			break;
		case TGStickersSectionFavourites:
			[self loadFavourites];
			break;
		case TGStickersSectionRecents:
			[self loadRecents];
			break;
		case TGStickersSectionTrending:
			_trendingAtEnd = NO;
			[_trendingSets removeAllObjects];
			[self notifyReload:TGStickersSectionTrending];
			[self loadMoreTrending];
			break;
		case TGStickersSectionArchived:
			_archivedAtEnd = NO;
			[_archivedSets removeAllObjects];
			[self notifyReload:TGStickersSectionArchived];
			[self loadMoreArchived];
			break;
		default:
			break;
	}
}

- (void)loadInstalled {
	[self setState:TGStickersLoadStateLoading forSection:TGStickersSectionInstalled];
	__weak TGStickersCompanion *weakSelf = self;
	void (^done)(NSArray *) = ^(NSArray *sets) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		[strongSelf handleInstalled:sets];
	};
	if (_kind == TGStickerKindEmoji) {
		[[TGClient shared] installedEmojiStickerSetsWithCompletion:done];
	} else if (_kind == TGStickerKindMask) {
		[[TGClient shared] installedMaskStickerSetsWithCompletion:done];
	} else {
		[[TGClient shared] installedStickerSetsWithCompletion:done];
	}
}

- (void)handleInstalled:(NSArray *)sets {
	if (sets == nil) {
		[self failSection:TGStickersSectionInstalled message:@"Could not load your sticker sets."];
		return;
	}
	NSArray *models = [TGStickerSetModel arrayFromDictionaries:sets];
	NSInteger oldCount = (NSInteger)[_installedSets count];
	[_installedSets setArray:models];
	if (oldCount == 0) {
		[self notifySection:TGStickersSectionInstalled
		           inserted:[self rangeRowsFrom:0 count:(NSInteger)[models count]]
		            removed:nil];
	} else {
		[self notifyReload:TGStickersSectionInstalled];
	}
	[self setLoadedState:TGStickersSectionInstalled empty:([models count] == 0)];
}

- (void)loadFavourites {
	[self setState:TGStickersLoadStateLoading forSection:TGStickersSectionFavourites];
	__weak TGStickersCompanion *weakSelf = self;
	[[TGClient shared] favoriteStickersWithCompletion:^(NSArray *stickers) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		[strongSelf handleFavourites:stickers];
	}];
}

- (void)handleFavourites:(NSArray *)stickers {
	if (stickers == nil) {
		[self failSection:TGStickersSectionFavourites message:@"Could not load your favourite stickers."];
		return;
	}
	NSArray *models = [TGStickerModel arrayFromDictionaries:stickers];
	[_favouriteStickers setArray:models];
	[self rebuildFavouriteIndex];
	[self notifyReload:TGStickersSectionFavourites];
	[self setLoadedState:TGStickersSectionFavourites empty:([models count] == 0)];
}

- (void)loadRecents {
	[self setState:TGStickersLoadStateLoading forSection:TGStickersSectionRecents];
	__weak TGStickersCompanion *weakSelf = self;
	[[TGClient shared] recentStickersAttached:NO completion:^(NSArray *stickers) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		[strongSelf handleRecents:stickers];
	}];
}

- (void)handleRecents:(NSArray *)stickers {
	if (stickers == nil) {
		[self failSection:TGStickersSectionRecents message:@"Could not load recent stickers."];
		return;
	}
	NSArray *models = [TGStickerModel arrayFromDictionaries:stickers];
	[_recentStickers setArray:models];
	[self notifyReload:TGStickersSectionRecents];
	[self setLoadedState:TGStickersSectionRecents empty:([models count] == 0)];
}

- (BOOL)canLoadMoreInSection:(TGStickersSection)section {
	if (section == TGStickersSectionArchived) {
		return !_archivedAtEnd && !_archivedLoading;
	}
	if (section == TGStickersSectionTrending) {
		return !_trendingAtEnd && !_trendingLoading;
	}
	return NO;
}

- (void)loadMoreArchived {
	if (_archivedLoading || _archivedAtEnd) {
		return;
	}
	_archivedLoading = YES;
	if ([_archivedSets count] == 0) {
		[self setState:TGStickersLoadStateLoading forSection:TGStickersSectionArchived];
	}
	int64_t offsetSetId = 0;
	if ([_archivedSets count] > 0) {
		TGStickerSetModel *last = [_archivedSets lastObject];
		offsetSetId = last.setId;
	}
	__weak TGStickersCompanion *weakSelf = self;
	void (^done)(NSArray *, NSInteger) = ^(NSArray *sets, NSInteger total) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		[strongSelf handleArchivedPage:sets total:total];
	};
	if (_kind == TGStickerKindEmoji) {
		[[TGClient shared] archivedEmojiStickerSetsFromSetId:offsetSetId
		                                               limit:TGStickersArchivedPageSize
		                                          completion:done];
	} else if (_kind == TGStickerKindMask) {
		[[TGClient shared] archivedMaskStickerSetsFromSetId:offsetSetId
		                                              limit:TGStickersArchivedPageSize
		                                         completion:done];
	} else {
		[[TGClient shared] archivedStickerSetsFromSetId:offsetSetId
		                                          limit:TGStickersArchivedPageSize
		                                     completion:done];
	}
}

- (void)handleArchivedPage:(NSArray *)sets total:(NSInteger)total {
	_archivedLoading = NO;
	if (sets == nil) {
		[self failSection:TGStickersSectionArchived message:@"Could not load archived sets."];
		return;
	}
	_archivedTotal = total;
	NSArray *models = [TGStickerSetModel arrayFromDictionaries:sets];
	if ([models count] < TGStickersArchivedPageSize) {
		_archivedAtEnd = YES;
	}
	NSInteger start = (NSInteger)[_archivedSets count];
	NSMutableArray *added = [NSMutableArray array];
	for (TGStickerSetModel *set in models) {
		if ([self indexOfSetId:set.setId inList:_archivedSets] == NSNotFound) {
			[_archivedSets addObject:set];
			[added addObject:set];
		}
	}
	[self notifySection:TGStickersSectionArchived
	           inserted:[self rangeRowsFrom:start count:(NSInteger)[added count]]
	            removed:nil];
	[self setLoadedState:TGStickersSectionArchived empty:([_archivedSets count] == 0)];
}

- (void)loadMoreTrending {
	if (_trendingLoading || _trendingAtEnd) {
		return;
	}
	_trendingLoading = YES;
	if ([_trendingSets count] == 0) {
		[self setState:TGStickersLoadStateLoading forSection:TGStickersSectionTrending];
	}
	NSInteger offset = (NSInteger)[_trendingSets count];
	__weak TGStickersCompanion *weakSelf = self;
	void (^done)(NSArray *, NSInteger) = ^(NSArray *sets, NSInteger total) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		[strongSelf handleTrendingPage:sets total:total];
	};
	if (_kind == TGStickerKindEmoji) {
		[[TGClient shared] trendingEmojiStickerSetsWithOffset:offset
		                                                limit:TGStickersTrendingPageSize
		                                           completion:done];
	} else {
		[[TGClient shared] trendingStickerSetsWithOffset:offset
		                                           limit:TGStickersTrendingPageSize
		                                      completion:done];
	}
}

- (void)handleTrendingPage:(NSArray *)sets total:(NSInteger)total {
	_trendingLoading = NO;
	if (sets == nil) {
		[self failSection:TGStickersSectionTrending message:@"Could not load trending sets."];
		return;
	}
	_trendingTotal = total;
	NSArray *models = [TGStickerSetModel arrayFromDictionaries:sets];
	if ([models count] < TGStickersTrendingPageSize) {
		_trendingAtEnd = YES;
	}
	NSInteger start = (NSInteger)[_trendingSets count];
	NSInteger added = 0;
	for (TGStickerSetModel *set in models) {
		if ([self indexOfSetId:set.setId inList:_trendingSets] == NSNotFound) {
			[_trendingSets addObject:set];
			added++;
		}
	}
	[self notifySection:TGStickersSectionTrending
	           inserted:[self rangeRowsFrom:start count:added]
	            removed:nil];
	[self setLoadedState:TGStickersSectionTrending empty:([_trendingSets count] == 0)];
}

- (void)loadSetWithId:(int64_t)setId {
	_setGeneration++;
	NSInteger generation = _setGeneration;
	[self setState:TGStickersLoadStateLoading forSection:TGStickersSectionSetContents];
	__weak TGStickersCompanion *weakSelf = self;
	[[TGClient shared] stickerSetWithId:setId completion:^(NSDictionary *set) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		[strongSelf handleOpenedSet:set generation:generation];
	}];
}

- (void)loadSetWithName:(NSString *)name {
	if ([name length] == 0) {
		return;
	}
	_setGeneration++;
	NSInteger generation = _setGeneration;
	[self setState:TGStickersLoadStateLoading forSection:TGStickersSectionSetContents];
	__weak TGStickersCompanion *weakSelf = self;
	[[TGClient shared] stickerSetWithName:name completion:^(NSDictionary *set) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		[strongSelf handleOpenedSet:set generation:generation];
	}];
}

- (void)handleOpenedSet:(NSDictionary *)set generation:(NSInteger)generation {
	if (generation != _setGeneration) {
		return;
	}
	TGStickerSetModel *model = [TGStickerSetModel fromDictionary:set];
	if (model == nil) {
		[self failSection:TGStickersSectionSetContents message:@"Could not load this sticker set."];
		return;
	}
	_openSet = model;
	[_setStickers setArray:model.stickers];
	[self notifyReload:TGStickersSectionSetContents];
	[self setLoadedState:TGStickersSectionSetContents empty:([_setStickers count] == 0)];
}

- (void)search:(NSString *)query installedOnly:(BOOL)installedOnly {
	_searchGeneration++;
	NSInteger generation = _searchGeneration;
	NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed length] == 0) {
		[_searchResults removeAllObjects];
		[self notifyReload:TGStickersSectionSearch];
		[self setState:TGStickersLoadStateIdle forSection:TGStickersSectionSearch];
		return;
	}
	[self setState:TGStickersLoadStateLoading forSection:TGStickersSectionSearch];
	__weak TGStickersCompanion *weakSelf = self;
	void (^done)(NSArray *) = ^(NSArray *sets) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		[strongSelf handleSearchResults:sets generation:generation];
	};
	if (installedOnly) {
		if (_kind == TGStickerKindMask) {
			[[TGClient shared] searchInstalledMaskStickerSets:trimmed limit:TGStickersSearchLimit completion:done];
		} else {
			[[TGClient shared] searchInstalledStickerSets:trimmed limit:TGStickersSearchLimit completion:done];
		}
	} else {
		if (_kind == TGStickerKindEmoji) {
			[[TGClient shared] searchEmojiStickerSets:trimmed completion:done];
		} else {
			[[TGClient shared] searchStickerSets:trimmed completion:done];
		}
	}
}

- (void)handleSearchResults:(NSArray *)sets generation:(NSInteger)generation {
	if (generation != _searchGeneration) {
		return;
	}
	if (sets == nil) {
		[self failSection:TGStickersSectionSearch message:@"Could not search sticker sets."];
		return;
	}
	NSArray *models = [TGStickerSetModel arrayFromDictionaries:sets];
	[_searchResults setArray:models];
	[self notifyReload:TGStickersSectionSearch];
	[self setLoadedState:TGStickersSectionSearch empty:([models count] == 0)];
}

#pragma mark - writing

- (void)installSetWithId:(int64_t)setId {
	TGStickerSetModel *set = [self setWithId:setId];
	NSInteger archivedIndex = [self indexOfSetId:setId inList:_archivedSets];
	if (archivedIndex != NSNotFound) {
		[_archivedSets removeObjectAtIndex:archivedIndex];
		[self notifySection:TGStickersSectionArchived
		           inserted:nil
		            removed:[NSArray arrayWithObject:[NSNumber numberWithInteger:archivedIndex]]];
		[self setLoadedState:TGStickersSectionArchived empty:([_archivedSets count] == 0)];
	}
	if (set != nil && [self indexOfSetId:setId inList:_installedSets] == NSNotFound) {
		[_installedSets insertObject:set atIndex:0];
		[self notifySection:TGStickersSectionInstalled
		           inserted:[NSArray arrayWithObject:[NSNumber numberWithInteger:0]]
		            removed:nil];
		[self setLoadedState:TGStickersSectionInstalled empty:NO];
	}
	NSInteger trendingIndex = [self indexOfSetId:setId inList:_trendingSets];
	if (trendingIndex != NSNotFound) {
		[self notifySection:TGStickersSectionTrending
		            updated:[NSArray arrayWithObject:[NSNumber numberWithInteger:trendingIndex]]];
	}
	__weak TGStickersCompanion *weakSelf = self;
	[[TGClient shared] installStickerSet:setId completion:^(BOOL ok) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		if (!ok) {
			[strongSelf revertInstalledChangeWithMessage:@"Could not add this sticker set."];
		}
	}];
}

- (void)uninstallSetWithId:(int64_t)setId {
	NSInteger index = [self indexOfSetId:setId inList:_installedSets];
	if (index != NSNotFound) {
		[_installedSets removeObjectAtIndex:index];
		[self notifySection:TGStickersSectionInstalled
		           inserted:nil
		            removed:[NSArray arrayWithObject:[NSNumber numberWithInteger:index]]];
		[self setLoadedState:TGStickersSectionInstalled empty:([_installedSets count] == 0)];
	}
	__weak TGStickersCompanion *weakSelf = self;
	[[TGClient shared] uninstallStickerSet:setId completion:^(BOOL ok) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		if (!ok) {
			[strongSelf revertInstalledChangeWithMessage:@"Could not remove this sticker set."];
		}
	}];
}

- (void)archiveSetWithId:(int64_t)setId {
	NSInteger index = [self indexOfSetId:setId inList:_installedSets];
	if (index != NSNotFound) {
		[_installedSets removeObjectAtIndex:index];
		[self notifySection:TGStickersSectionInstalled
		           inserted:nil
		            removed:[NSArray arrayWithObject:[NSNumber numberWithInteger:index]]];
		[self setLoadedState:TGStickersSectionInstalled empty:([_installedSets count] == 0)];
	}
	__weak TGStickersCompanion *weakSelf = self;
	[[TGClient shared] archiveStickerSet:setId completion:^(BOOL ok) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		if (ok) {
			[strongSelf reloadSection:TGStickersSectionArchived];
		} else {
			[strongSelf revertInstalledChangeWithMessage:@"Could not archive this sticker set."];
		}
	}];
}

- (void)revertInstalledChangeWithMessage:(NSString *)message {
	if ([_delegate respondsToSelector:@selector(stickersCompanion:didFailWithMessage:section:)]) {
		[_delegate stickersCompanion:self didFailWithMessage:message section:TGStickersSectionInstalled];
	}
	[self loadInstalled];
}

- (void)moveInstalledSetFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex {
	NSInteger count = (NSInteger)[_installedSets count];
	if (fromIndex < 0 || fromIndex >= count || toIndex < 0 || toIndex >= count || fromIndex == toIndex) {
		return;
	}
	TGStickerSetModel *set = [_installedSets objectAtIndex:fromIndex];
	[_installedSets removeObjectAtIndex:fromIndex];
	[_installedSets insertObject:set atIndex:toIndex];

	NSMutableArray *ids = [NSMutableArray arrayWithCapacity:count];
	for (TGStickerSetModel *each in _installedSets) {
		[ids addObject:[NSNumber numberWithLongLong:each.setId]];
	}
	__weak TGStickersCompanion *weakSelf = self;
	void (^done)(BOOL) = ^(BOOL ok) {
		TGStickersCompanion *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		if (!ok) {
			[strongSelf revertInstalledChangeWithMessage:@"Could not save the new order."];
		}
	};
	if (_kind == TGStickerKindEmoji) {
		[[TGClient shared] reorderInstalledEmojiStickerSets:ids completion:done];
	} else if (_kind == TGStickerKindMask) {
		[[TGClient shared] reorderInstalledMaskStickerSets:ids completion:done];
	} else {
		[[TGClient shared] reorderInstalledStickerSets:ids completion:done];
	}
}

- (void)markTrendingSetsViewed {
	NSMutableArray *ids = [NSMutableArray array];
	NSMutableArray *rows = [NSMutableArray array];
	NSInteger count = (NSInteger)[_trendingSets count];
	for (NSInteger i = 0; i < count; i++) {
		TGStickerSetModel *set = [_trendingSets objectAtIndex:i];
		if (!set.viewed) {
			[ids addObject:[NSNumber numberWithLongLong:set.setId]];
			[rows addObject:[NSNumber numberWithInteger:i]];
		}
	}
	if ([ids count] == 0) {
		return;
	}
	[[TGClient shared] markTrendingStickerSetsViewed:ids];
	[self notifySection:TGStickersSectionTrending updated:rows];
}

- (void)setFileId:(NSInteger)fileId favourite:(BOOL)favourite {
	NSNumber *key = [NSNumber numberWithInteger:fileId];
	if (favourite) {
		if (![_favouriteFileIds containsObject:key]) {
			[_favouriteFileIds addObject:key];
		}
		[[TGClient shared] addFavoriteStickerWithFileId:fileId];
	} else {
		NSInteger index = NSNotFound;
		NSInteger count = (NSInteger)[_favouriteStickers count];
		for (NSInteger i = 0; i < count; i++) {
			TGStickerModel *sticker = [_favouriteStickers objectAtIndex:i];
			if (sticker.fileId == fileId) {
				index = i;
				break;
			}
		}
		[_favouriteFileIds removeObject:key];
		if (index != NSNotFound) {
			[_favouriteStickers removeObjectAtIndex:index];
			[self notifySection:TGStickersSectionFavourites
			           inserted:nil
			            removed:[NSArray arrayWithObject:[NSNumber numberWithInteger:index]]];
			[self setLoadedState:TGStickersSectionFavourites empty:([_favouriteStickers count] == 0)];
		}
		[[TGClient shared] removeFavoriteStickerWithFileId:fileId];
	}
	if (favourite) {
		[self loadFavourites];
	}
}

- (void)useStickerWithFileId:(NSInteger)fileId {
	[[TGClient shared] addRecentStickerWithFileId:fileId];
	[self loadRecents];
}

- (void)removeRecentFileId:(NSInteger)fileId {
	NSInteger index = NSNotFound;
	NSInteger count = (NSInteger)[_recentStickers count];
	for (NSInteger i = 0; i < count; i++) {
		TGStickerModel *sticker = [_recentStickers objectAtIndex:i];
		if (sticker.fileId == fileId) {
			index = i;
			break;
		}
	}
	if (index != NSNotFound) {
		[_recentStickers removeObjectAtIndex:index];
		[self notifySection:TGStickersSectionRecents
		           inserted:nil
		            removed:[NSArray arrayWithObject:[NSNumber numberWithInteger:index]]];
		[self setLoadedState:TGStickersSectionRecents empty:([_recentStickers count] == 0)];
	}
	[[TGClient shared] removeRecentStickerWithFileId:fileId];
}

- (void)clearRecents {
	[[TGClient shared] clearRecentStickers];
	if ([_recentStickers count] > 0) {
		[_recentStickers removeAllObjects];
		[self notifyReload:TGStickersSectionRecents];
	}
	[self setState:TGStickersLoadStateEmpty forSection:TGStickersSectionRecents];
}

#pragma mark - memory

- (void)handleMemoryWarning {
	[self purgeCaches];
}

- (void)purgeCaches {
	if ([_searchResults count] > 0) {
		[_searchResults removeAllObjects];
		[self notifyReload:TGStickersSectionSearch];
		[self setState:TGStickersLoadStateIdle forSection:TGStickersSectionSearch];
	}
	if ([_setStickers count] > 0 && _states[TGStickersSectionSetContents] != TGStickersLoadStateLoading) {
		[_setStickers removeAllObjects];
		_openSet = nil;
		[self notifyReload:TGStickersSectionSetContents];
		[self setState:TGStickersLoadStateIdle forSection:TGStickersSectionSetContents];
	}
	if ([_archivedSets count] > TGStickersArchivedPageSize) {
		NSRange tail = NSMakeRange(TGStickersArchivedPageSize,
		                           [_archivedSets count] - TGStickersArchivedPageSize);
		[_archivedSets removeObjectsInRange:tail];
		_archivedAtEnd = NO;
		[self notifyReload:TGStickersSectionArchived];
	}
	if ([_trendingSets count] > TGStickersTrendingPageSize) {
		NSRange tail = NSMakeRange(TGStickersTrendingPageSize,
		                           [_trendingSets count] - TGStickersTrendingPageSize);
		[_trendingSets removeObjectsInRange:tail];
		_trendingAtEnd = NO;
		[self notifyReload:TGStickersSectionTrending];
	}
}

@end

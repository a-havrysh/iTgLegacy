//
// TGStickersCompanion - owns the sticker data for one sticker screen.
//
// The screen (TGStickersViewController, TGStickerPanelView) creates one of
// these, sets itself as the delegate, calls -reload, and from then on reads
// only typed models: TGStickerSetModel and TGStickerModel. It never calls
// TGClient and never subscripts a dictionary.
//
// One companion instance serves one screen instance. It is not a singleton:
// two sticker screens on the stack own two companions with independent state.
//
//   TGStickersCompanion *c = [[TGStickersCompanion alloc] initWithKind:TGStickerKindRegular];
//   c.delegate = self;
//   [c reload];
//
// Every method is main-queue only, and every delegate callback arrives on the
// main queue.
//
#import <Foundation/Foundation.h>

@class TGStickerModel;
@class TGStickerSetModel;
@class TGStickersCompanion;

/// Which family of sets this companion works with. Chosen once at init: the
/// installed / archived / trending / reorder calls all follow it.
typedef NS_ENUM(NSInteger, TGStickerKind) {
	TGStickerKindRegular = 0,
	TGStickerKindEmoji = 1,
	TGStickerKindMask = 2
};

/// The four states a screen must be able to draw, per section. A screen reads
/// these instead of guessing from an empty array - "empty" and "not loaded
/// yet" look identical in an array and must not look identical on screen.
typedef NS_ENUM(NSInteger, TGStickersLoadState) {
	TGStickersLoadStateIdle = 0,
	TGStickersLoadStateLoading,
	TGStickersLoadStateLoaded,
	TGStickersLoadStateEmpty,
	TGStickersLoadStateFailed
};

/// The lists this companion owns. Used by the delegate to say which one moved
/// and by the screen to ask for a state.
typedef NS_ENUM(NSInteger, TGStickersSection) {
	TGStickersSectionInstalled = 0,
	TGStickersSectionArchived,
	TGStickersSectionTrending,
	TGStickersSectionFavourites,
	TGStickersSectionRecents,
	TGStickersSectionSetContents,
	TGStickersSectionSearch
};

@protocol TGStickersCompanionDelegate <NSObject>
@optional

/// A section changed state: started loading, finished, came back empty, failed.
/// Draw the spinner / the empty label / the retry row from here.
- (void)stickersCompanion:(TGStickersCompanion *)companion
      section:(TGStickersSection)section
      didChangeState:(TGStickersLoadState)state;

/// Rows arrived or left in a section. `inserted` and `removed` are arrays of
/// NSNumber row indexes in the section's own array, either of which may be
/// empty. Removals are expressed against the array as it was before the change,
/// insertions against the array as it is now - the same contract UITableView
/// wants inside beginUpdates/endUpdates.
/// Prefer this over a reloadData: on this hardware a full reload of the
/// installed list costs several frames.
- (void)stickersCompanion:(TGStickersCompanion *)companion
      section:(TGStickersSection)section
      didInsertRows:(NSArray *)inserted
      removedRows:(NSArray *)removed;

/// One row's content changed in place (a set became installed, a trending set
/// lost its "new" badge). `rows` is an array of NSNumber row indexes.
- (void)stickersCompanion:(TGStickersCompanion *)companion
      section:(TGStickersSection)section
      didUpdateRows:(NSArray *)rows;

/// The section changed so much that row maths is not worth it (a search
/// result set replaced wholesale, a reorder rolled back). Reload it.
- (void)stickersCompanion:(TGStickersCompanion *)companion
      didReloadSection:(TGStickersSection)section;

/// A write failed and the companion has already rolled its own state back.
/// Show the message; do not undo anything yourself.
- (void)stickersCompanion:(TGStickersCompanion *)companion
      didFailWithMessage:(NSString *)message
      section:(TGStickersSection)section;

@end


@interface TGStickersCompanion : NSObject

/// The screen. Weak - the screen owns the companion, never the other way round.
@property (nonatomic, assign) id<TGStickersCompanionDelegate> delegate;

/// Which family of sets this instance works with.
@property (nonatomic, readonly) TGStickerKind kind;

/// Designated initialiser. -init is the same as TGStickerKindRegular.
- (id)initWithKind:(TGStickerKind)kind;


// ---- reading ------------------------------------------------------------

/// Installed sets in the user's own order, as TGStickerSetModel. Never nil.
@property (nonatomic, readonly) NSArray *installedSets;

/// Archived sets, oldest page first as they were paged in. Never nil.
@property (nonatomic, readonly) NSArray *archivedSets;

/// Trending sets in server order. A set whose `viewed` is NO is badged new.
@property (nonatomic, readonly) NSArray *trendingSets;

/// Favourite stickers, most recent first, as TGStickerModel. Never nil.
@property (nonatomic, readonly) NSArray *favouriteStickers;

/// Recently used stickers, most recent first. Never nil.
@property (nonatomic, readonly) NSArray *recentStickers;

/// Stickers of the set opened with -loadSetWithId:/-loadSetWithName:.
@property (nonatomic, readonly) NSArray *setStickers;

/// The set opened with -loadSetWithId:/-loadSetWithName:, or nil.
@property (nonatomic, readonly) TGStickerSetModel *openSet;

/// Latest result of -search:, as TGStickerSetModel. Never nil.
@property (nonatomic, readonly) NSArray *searchResults;

/// Total the server reports for a paged section, which can exceed what has
/// been paged in. 0 for sections that are not paged.
- (NSInteger)totalCountForSection:(TGStickersSection)section;

/// Current state of one section.
- (TGStickersLoadState)stateForSection:(TGStickersSection)section;

/// The set with this id from whichever list already holds it, or nil. Cheap:
/// it reads the companion's own caches and never asks the network.
- (TGStickerSetModel *)setWithId:(int64_t)setId;

/// YES when the sticker file id is in the favourites list. Answered from the
/// cached favourites, so it is safe to call once per cell.
- (BOOL)isFavouriteFileId:(NSInteger)fileId;


// ---- loading ------------------------------------------------------------

/// Loads everything the root page needs: installed, favourites, recents, the
/// first page of trending, and whether the archive is non-empty. Call it in
/// viewDidLoad, and again on pull-to-refresh.
- (void)reload;

/// Loads one section on its own, for screens that show only one.
- (void)reloadSection:(TGStickersSection)section;

/// Next page of archived sets. Does nothing while a page is in flight or once
/// the end has been reached.
- (void)loadMoreArchived;

/// Next page of trending sets. Same guards.
- (void)loadMoreTrending;

/// YES while there is another page to fetch for that section.
- (BOOL)canLoadMoreInSection:(TGStickersSection)section;

/// Opens one set and fills `setStickers` / `openSet`.
- (void)loadSetWithId:(int64_t)setId;

/// Same by short name - what a t.me/addstickers/<name> link carries.
- (void)loadSetWithName:(NSString *)name;

/// Searches sets. `installedOnly` restricts to the user's own sets. An empty
/// or nil query clears `searchResults` without hitting the network. Calls
/// after this one supersede earlier ones: a stale answer is dropped.
- (void)search:(NSString *)query installedOnly:(BOOL)installedOnly;


// ---- writing ------------------------------------------------------------
//
// Every write below updates the companion's arrays first, tells the delegate,
// then asks the server. If the server refuses, the companion puts its arrays
// back and sends -stickersCompanion:didFailWithMessage:section:. The screen
// never has to sequence this itself.

/// Install a set; also un-archives it. Moves it into `installedSets`.
- (void)installSetWithId:(int64_t)setId;

/// Remove a set from the installed list entirely.
- (void)uninstallSetWithId:(int64_t)setId;

/// Move an installed set to the archive; it stays restorable.
- (void)archiveSetWithId:(int64_t)setId;

/// Commit a drag in the installed list. Indexes are into `installedSets` as it
/// stands now. Rolls back and reloads the section if the server refuses.
- (void)moveInstalledSetFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;

/// Tell the server every currently loaded trending set has been seen, which
/// clears the new badges. Safe to call repeatedly; only unviewed ids are sent.
- (void)markTrendingSetsViewed;

/// Favourite / unfavourite a sticker. Updates `favouriteStickers` immediately.
- (void)setFileId:(NSInteger)fileId favourite:(BOOL)favourite;

/// Push a sticker to the front of the recents strip - call it when one is sent.
- (void)useStickerWithFileId:(NSInteger)fileId;

/// Drop one sticker from the recents strip.
- (void)removeRecentFileId:(NSInteger)fileId;

/// Empty the recents strip.
- (void)clearRecents;


// ---- memory -------------------------------------------------------------

/// Drops everything that can be fetched again: paged archived and trending
/// pages past the first, search results and any opened set's stickers. The
/// installed list, favourites and recents survive, because they are what the
/// visible screen is made of. Call it from didReceiveMemoryWarning; the
/// companion also listens for the warning itself, so this is only for screens
/// that want to drop more, sooner.
- (void)purgeCaches;

@end

// vim:ft=objc

//
// TGStickerPanelView - the sticker keyboard that sits over the chat input.
//
// A tab strip of recents, favourites and every installed set, drawn as a group
// button bar with the same plates and three-state dividers the rest of the app
// uses, over a hand-tiled grid of sticker thumbnails. No UICollectionView: the
// grid is a UIScrollView whose tiles are recycled through TGViewRecycler as
// they leave the visible rect, so a hundred sets cost the same as one.
//
// Sets load lazily: the geometry comes from the set's "count" and the stickers
// themselves are fetched only when their section scrolls into view. Only the
// visible rows plus one row either side hold a tile; anything past that has its
// download and its decode cancelled on the way out.
//
// Thumbnails do not live here. They live in TGStickerThumbnailCache, which is
// process wide and disk backed, so closing the panel or restarting the app does
// not throw the decodes away. The panel keeps its section list in a
// process-lifetime snapshot for the same reason - the chat screen destroys this
// view every time the keyboard goes down.
//
#import <UIKit/UIKit.h>

@interface TGStickerPanelView : UIView

/// Called with the sticker dictionary from TGClient+Stickers when one is
/// tapped. The panel has already pushed it onto the recent strip; sending it
/// is the chat screen's job.
@property (nonatomic, copy) void (^onStickerPicked)(NSDictionary *sticker);

/// Called when the "Hide" tab at the end of the strip is tapped.
@property (nonatomic, copy) void (^onCloseRequested)(void);

/// The height a panel should be given, matching the system keyboard.
+ (CGFloat)preferredHeightForLandscape:(BOOL)landscape;

/// Reload tabs and sets from the server, discarding what is on screen. Called
/// on init when nothing is cached; call it again after the user installs or
/// removes a set.
- (void)reload;

@end

// vim:ft=objc

//
// TGStickerPanelView - the sticker keyboard that sits over the chat input.
//
// A tab strip of recents, favourites and every installed set, drawn as a group
// button bar, over a hand-tiled grid of sticker thumbnails. No
// UICollectionView: the grid is a UIScrollView whose 64pt tiles are recycled
// through TGViewRecycler as they leave the visible rect, so a hundred sets cost
// the same as one.
//
// Sets load lazily: the geometry comes from the set's "count" and the stickers
// themselves are fetched only when their section scrolls into view.
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

/// Reload tabs and sets from the server. Called once on init; call it again
/// after the user installs or removes a set.
- (void)reload;

@end

// vim:ft=objc

//
// TGStickerPanelView - the sticker keyboard that sits over the chat input.
//
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

/// Called when the panel wants to go away: the backspace key with nothing left
/// to delete, or a search cancel.
@property (nonatomic, copy) void (^onCloseRequested)(void);

/// The backspace key at the bottom right, where the system keyboard keeps its
/// own. Return YES if a character was deleted; returning NO closes the panel.
@property (nonatomic, copy) BOOL (^onBackspace)(void);

/// The height a panel should be given, matching the system keyboard.
+ (CGFloat)preferredHeightForLandscape:(BOOL)landscape;

/// Record the system keyboard's measured height so the panel can be exactly as
/// tall as it. Call from the keyboard-will-show notification.
+ (void)noteSystemKeyboardHeight:(CGFloat)height landscape:(BOOL)landscape;

/// Reload tabs and sets from the server, discarding what is on screen. Called
/// on init when nothing is cached; call it again after the user installs or
/// removes a set.
- (void)reload;

@end

// vim:ft=objc

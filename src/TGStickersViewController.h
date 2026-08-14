//
// TGStickersViewController - sticker settings.
//
// One class, several pages, chosen with `page` before the screen is pushed:
//
//   Root        the grouped table: favourites, trending, archived, then the
//               installed sets in the user's own order. Reorderable behind the
//               Edit button, swipe a set for Archive / Remove.
//   Trending    featured sets, each with an Add button; being shown here marks
//               them viewed, which clears the "new" badge.
//   Archived    sets the user put away, paged in as the list is scrolled.
//   Favourites  the favourite stickers as a grid.
//   Set         one set's stickers as a grid, with Add or Remove in the bar.
//
// Push it, never present it: it is a settings page and belongs on the settings
// navigation stack.
//
//   TGStickersViewController *stickers = [[TGStickersViewController alloc] init];
//   [self.navigationController pushViewController:stickers animated:YES];
//
// For TGStickersPageSet set either `setId` or `set` (a set dictionary as
// TGClient+Stickers documents it) before pushing; every other page needs
// nothing but `page`, and Root is the default.
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGStickersPage) {
	TGStickersPageRoot = 0,
	TGStickersPageTrending = 1,
	TGStickersPageArchived = 2,
	TGStickersPageFavourites = 3,
	TGStickersPageSet = 4
};

@interface TGStickersViewController : UIViewController

/// Which of the pages above this instance is. Defaults to Root.
@property (nonatomic, assign) TGStickersPage page;

/// The set to open on TGStickersPageSet, when only its id is known.
@property (nonatomic, assign) int64_t setId;

/// The set to open on TGStickersPageSet, when the caller already holds the
/// dictionary. Its title fills the bar before the stickers arrive.
@property (nonatomic, strong) NSDictionary *set;

@end

// vim:ft=objc

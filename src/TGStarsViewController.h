//
// TGStarsViewController - the Telegram Stars page.
//
// Informational only: the current star balance, the star transaction history
// (amount, counterparty and date, paged with a "Show more" row) and the gifts
// this account has received. Nothing here buys stars - that needs Telegram's
// own App Store products, which this bundle cannot reach.
//
// Push it from a settings row; it needs no context beyond the signed-in
// account, so a plain -init is enough.
//
#import <UIKit/UIKit.h>

@interface TGStarsViewController : UITableViewController

@end

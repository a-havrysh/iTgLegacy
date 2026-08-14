//
// TGPremiumViewController - the Premium status page.
//
// Informational only: whether this account has Premium, what the free and the
// Premium limit is for every capped thing, the promo feature list, the boost
// slots this account owns and a field for redeeming a gift code. Nothing here
// can be bought - a purchase needs Telegram's own App Store products, which
// this bundle cannot reach.
//
// Push it from a settings row; it needs no context beyond the signed-in
// account, so a plain -init is enough.
//
#import <UIKit/UIKit.h>

@interface TGPremiumViewController : UITableViewController

@end

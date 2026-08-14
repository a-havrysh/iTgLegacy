//
// TGProxyViewController - the proxy settings screen: every proxy configured on
// this device with its type and ping, the one in use marked with a check, a
// form for adding or editing an MTProto or SOCKS5 proxy, and a status line
// saying what the connection is doing right now.
//
// Push it onto a navigation controller; it needs no context of any kind.
//
#import <UIKit/UIKit.h>

@interface TGProxyViewController : UITableViewController

/// Ready to push as it stands.
- (instancetype)init;

@end

// vim:ft=objc

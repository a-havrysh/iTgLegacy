//
// TGInviteLinksViewController - the invite links of a group or channel.
//
// Shows the primary link with copy and share, the additional links the user
// made with their usage counts and expiry, the pending join requests with
// approve and decline, and the revoked links.
//
// Push it onto a navigation controller after setting `chatId`; nothing else
// is required, the screen loads everything itself.
//
#import <UIKit/UIKit.h>

@interface TGInviteLinksViewController : UITableViewController

/// The group or channel whose links are shown. Set before the view loads.
@property (nonatomic, assign) int64_t chatId;

/// Convenience initialiser: -init plus the chat.
- (instancetype)initWithChatId:(int64_t)chatId;

@end

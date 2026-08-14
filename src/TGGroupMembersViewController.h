//
// TGGroupMembersViewController - who is in a group or channel, and what may be
// done about them.
//
// One list with four modes across the top - members, administrators, banned,
// restricted - drawn as the 2013 button group, not a UISegmentedControl. A row
// is the 49pt member row: 40pt avatar, name, and a status line that says what
// the person is rather than when they were last seen. Holding a row opens the
// popup menu with promote, restrict, ban and remove, filtered down to what the
// server says we may actually do to that member.
//
// Present it by pushing onto a navigation controller. `chatId` must be set
// before the view loads; nothing else is required.
//
//   TGGroupMembersViewController *vc = [[TGGroupMembersViewController alloc] init];
//   vc.chatId = chatId;
//   [self.navigationController pushViewController:vc animated:YES];
//
#import <UIKit/UIKit.h>

@interface TGGroupMembersViewController : UIViewController

/// The chat id of the group or channel. Required.
@property (nonatomic, assign) int64_t chatId;

/// Which mode the list opens in: 0 members, 1 administrators, 2 banned,
/// 3 restricted. Defaults to 0.
@property (nonatomic, assign) NSInteger initialMode;

@end

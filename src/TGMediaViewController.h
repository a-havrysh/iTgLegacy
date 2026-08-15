//
// TGMediaViewController - the shared media of one chat, drawn the way the 2014
// client drew it: a plain UITableView whose rows each carry a line of square
// thumbnails, newest last, paged as you reach the bottom.
//
// A 44pt banner over the grid carries the state of the downloads queue and
// pushes TGDownloadsViewController, which is the same list on its own screen.
//
#import <UIKit/UIKit.h>

@interface TGMediaViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

/// The chat whose media is shown. Must be set before the view loads;
/// -initWithChatId: is the usual way in.
@property (nonatomic, assign) int64_t chatId;

/// Shown under the title when set. Optional.
@property (nonatomic, copy) NSString *chatTitle;

- (instancetype)initWithChatId:(int64_t)chatId;

@end

@interface TGDownloadsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

// vim:ft=objc

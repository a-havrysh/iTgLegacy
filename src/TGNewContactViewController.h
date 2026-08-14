#import <UIKit/UIKit.h>

@interface TGNewContactViewController : UITableViewController
@property (nonatomic, copy) void (^onDone)(void);
@end

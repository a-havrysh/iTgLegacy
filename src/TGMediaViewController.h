#import <UIKit/UIKit.h>

@interface TGMediaViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *chatTitle;

- (instancetype)initWithChatId:(int64_t)chatId;

@end

@interface TGDownloadsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

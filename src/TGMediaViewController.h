#import <UIKit/UIKit.h>

@interface TGMediaViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *chatTitle;

- (instancetype)initWithChatId:(int64_t)chatId;

@end

@interface TGDownloadsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

@interface TGMediaFullscreenController : UIViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) void (^onMessageDeleted)(int64_t messageId);

- (instancetype)initWithItems:(NSArray *)items index:(NSInteger)index;

@end

//
// TGChatEventsViewController - the admin log ("Recent Actions") of a group or
// channel: moderation events newest first, with a filter form.
//
#import <UIKit/UIKit.h>

@interface TGChatEventsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

/// The group or supergroup/channel whose log is shown. Must be set before the
/// view loads; -initWithChatId: is the usual way in.
@property (nonatomic, assign) int64_t chatId;

/// Shown under the title when set. Optional.
@property (nonatomic, copy) NSString *chatTitle;

- (instancetype)initWithChatId:(int64_t)chatId;

@end

// vim:ft=objc

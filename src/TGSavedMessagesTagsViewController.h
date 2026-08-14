//
// TGSavedMessagesTagsViewController - the tags used inside Saved Messages,
// each with the number of messages carrying it. A tag can be renamed and
// tapping one lists the Saved Messages that carry it.
//
#import <UIKit/UIKit.h>

@interface TGSavedMessagesTagsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate>

/// Restricts the tags to one Saved Messages topic. 0, the default, gathers the
/// tags of the whole Saved Messages chat. Set before the view loads; a topic
/// id is only ever a value handed back by TGClient+SavedMessages.
@property (nonatomic, assign) int64_t topicId;

/// Shown as the screen title when set, otherwise "Tags".
@property (nonatomic, copy) NSString *topicTitle;

- (instancetype)initWithTopicId:(int64_t)topicId;

@end

// vim:ft=objc

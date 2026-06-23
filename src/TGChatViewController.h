//
// TGChatViewController - a chat, driven purely by TDLib.
//
// Written from scratch rather than reusing ChatViewController: that one is
// built around libtg's tg_message_t and NSBubbleData, and carries the whole
// old media pipeline with it.
//
#import <UIKit/UIKit.h>

@interface TGChatViewController : UIViewController
    <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy)   NSString *chatTitle;

@end

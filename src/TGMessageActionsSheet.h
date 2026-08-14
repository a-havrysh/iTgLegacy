//
// TGMessageActionsSheet - the long-press menu of a message bubble.
//
// The rows are not a fixed list: TGClient+Messages is asked what this
// particular message allows and only the permitted rows are drawn. The card
// itself is TGPopupMenu, the destructive confirmation is a UIActionSheet with
// one red button, exactly as the 2013 client did it.
//
#import <UIKit/UIKit.h>

/// Action ids handed back through the completion block.
extern NSString *const TGMessageActionReply;
extern NSString *const TGMessageActionEdit;
extern NSString *const TGMessageActionCopy;
extern NSString *const TGMessageActionCopyLink;
extern NSString *const TGMessageActionForward;
extern NSString *const TGMessageActionPin;
extern NSString *const TGMessageActionUnpin;
extern NSString *const TGMessageActionTranslate;
extern NSString *const TGMessageActionSelect;
extern NSString *const TGMessageActionDeleteForMe;
extern NSString *const TGMessageActionDeleteForEveryone;
extern NSString *const TGMessageActionReport;

@interface TGMessageActionsSheet : NSObject

/// The message the menu acts on. Both must be set before presenting.
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;

/// The bubble's text, when it has any. Drives Copy and Translate, which the
/// permission query cannot decide on its own.
@property (nonatomic, copy) NSString *messageText;

/// YES when the message is already the chat's pinned one, so the row reads
/// Unpin instead of Pin.
@property (nonatomic, assign) BOOL pinned;

/// NO removes the Select row, for a screen with no selection mode.
@property (nonatomic, assign) BOOL allowsSelection;

/// Convenience: chatId and messageId set, allowsSelection YES.
+ (instancetype)sheetForMessage:(int64_t)messageId inChat:(int64_t)chatId;

/// Ask TDLib what the message allows, then open the card beside `point`
/// (in `host`'s coordinates). `completion` fires with one of the action
/// constants above, or nil when the user dismissed without choosing or the
/// message turned out to be gone. Delete is confirmed before it is reported.
- (void)presentAtPoint:(CGPoint)point
                inView:(UIView *)host
            completion:(void (^)(NSString *action))completion;

/// Close the card and any confirmation still on screen. Call from
/// viewWillDisappear of whatever presented it.
- (void)dismiss;

@end

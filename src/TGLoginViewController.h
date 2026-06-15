#import <UIKit/UIKit.h>

@interface TGLoginViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic, copy) void (^onPhoneSubmitted)(NSString *phoneNumber);
@property (nonatomic, copy) void (^onCodeSubmitted)(NSString *code);
@property (nonatomic, copy) void (^onPasswordSubmitted)(NSString *password);

- (void)showCodeStepWithPhoneNumber:(NSString *)phoneNumber;
- (void)showPasswordStep;

/* Spinner + disabled button while a request is in flight, so a tap on Next
 * is visibly doing something instead of looking dead. */
- (void)setBusy:(BOOL)busy;

@end

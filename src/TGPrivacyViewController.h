//
// TGPrivacyViewController - Privacy and Security, and the screens under it.
//
// The privacy rules, the local passcode lock and two-step verification, each
// as a pushed grouped table. Multi-step work is a chain of one-question
// screens, the way the original asked for a phone number and then a code.
//
#import <UIKit/UIKit.h>

/// Privacy and Security: the privacy rules, then a security group carrying
/// the passcode lock, two-step verification and the device list.
@interface TGPrivacyViewController : UITableViewController
@end

/// One privacy rule: Everybody / My Contacts / Nobody, with the exception
/// lists another client may have set shown but left alone.
@interface TGPrivacyRuleViewController : UITableViewController
- (instancetype)initWithSetting:(NSString *)setting;
@end

/// The local passcode: on/off, change, and the auto-lock interval.
@interface TGPasscodeViewController : UITableViewController

/// Whether a passcode is set, what it is measured against, and how long the
/// app may stay in the background before it locks. The lock window itself is
/// not owned here.
+ (BOOL)passcodeIsSet;
+ (BOOL)passcodeMatches:(NSString *)passcode;
+ (NSInteger)autoLockSeconds;

@end

/// Two-step verification: state, then set / change / disable as a chain.
@interface TGTwoStepViewController : UITableViewController
@end

// vim:ft=objc

#import "TGLoginViewController.h"
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, TGLoginStep) {
    TGLoginStepPhone,
    TGLoginStepCode,
    TGLoginStepPassword
};

@interface TGLoginViewController ()

@property (nonatomic, assign) TGLoginStep currentStep;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *inputContainer;
@property (nonatomic, strong) UITextField *phonePrefixField;
@property (nonatomic, strong) UIView *prefixSeparator;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIBarButtonItem *nextItem;
@property (nonatomic, copy) NSString *savedPhoneNumber;

@end

@implementation TGLoginViewController

/* ---- skeuomorphic helpers -------------------------------------------- */

static UIColor *tgRGB(int r, int g, int b) {
    return [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:1.0f];
}

/* Vertical gloss gradient, the iOS 6 era look. */
static CAGradientLayer *tgGloss(CGRect frame, UIColor *top, UIColor *bottom) {
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = frame;
    g.colors = @[(id)top.CGColor, (id)bottom.CGColor];
    return g;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Your Phone";

    self.nextItem = [[UIBarButtonItem alloc] initWithTitle:@"Next"
                                                     style:UIBarButtonItemStyleDone
                                                    target:self
                                                    action:@selector(actionButtonTapped)];
    self.navigationItem.rightBarButtonItem = self.nextItem;

    /* Brushed-metal-ish bar rather than iOS 7 flat white. */
    self.navigationController.navigationBar.tintColor = tgRGB(38, 92, 140);
    if ([self.navigationController.navigationBar respondsToSelector:@selector(setBarTintColor:)])
        self.navigationController.navigationBar.barTintColor = tgRGB(64, 122, 173);
    self.navigationController.navigationBar.titleTextAttributes = @{
        NSForegroundColorAttributeName : [UIColor whiteColor]
    };

    [self setupUI];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;

    /* Paper-ish backdrop with a soft vertical shade. */
    self.view.backgroundColor = tgRGB(203, 209, 216);
    CAGradientLayer *bg = tgGloss(self.view.bounds, tgRGB(222, 226, 232), tgRGB(186, 193, 203));
    [self.view.layer insertSublayer:bg atIndex:0];

    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    /* Embossed title: dark text with a white highlight underneath. */
    self.headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 22, width - 40, 36)];
    self.headerLabel.text = @"Telegram";
    self.headerLabel.backgroundColor = [UIColor clearColor];
    self.headerLabel.textColor = tgRGB(52, 74, 96);
    self.headerLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.8f];
    self.headerLabel.shadowOffset = CGSizeMake(0, 1);
    self.headerLabel.font = [UIFont boldSystemFontOfSize:28];
    self.headerLabel.textAlignment = NSTextAlignmentCenter;
    [self.scrollView addSubview:self.headerLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 62, width - 40, 40)];
    self.subtitleLabel.text = @"Please confirm your country code\nand enter your phone number.";
    self.subtitleLabel.backgroundColor = [UIColor clearColor];
    self.subtitleLabel.textColor = tgRGB(90, 103, 117);
    self.subtitleLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.7f];
    self.subtitleLabel.shadowOffset = CGSizeMake(0, 1);
    self.subtitleLabel.font = [UIFont systemFontOfSize:14];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 2;
    [self.scrollView addSubview:self.subtitleLabel];

    /* Recessed input well: bevelled border plus an inner top shadow. */
    self.inputContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 112, width - 30, 50)];
    self.inputContainer.backgroundColor = [UIColor whiteColor];
    self.inputContainer.layer.cornerRadius = 10.0f;
    self.inputContainer.layer.borderWidth = 1.0f;
    self.inputContainer.layer.borderColor = tgRGB(140, 149, 160).CGColor;
    self.inputContainer.clipsToBounds = YES;
    [self.scrollView addSubview:self.inputContainer];

    UIView *inner = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width - 30, 3)];
    inner.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.10f];
    [self.inputContainer addSubview:inner];

    /* Country code prefix - Ukraine by default. */
    self.phonePrefixField = [[UITextField alloc] initWithFrame:CGRectMake(12, 1, 62, 48)];
    self.phonePrefixField.text = @"+380";
    self.phonePrefixField.font = [UIFont boldSystemFontOfSize:17];
    self.phonePrefixField.keyboardType = UIKeyboardTypePhonePad;
    self.phonePrefixField.returnKeyType = UIReturnKeyNext;
    self.phonePrefixField.textColor = tgRGB(38, 92, 140);
    [self.inputContainer addSubview:self.phonePrefixField];

    self.prefixSeparator = [[UIView alloc] initWithFrame:CGRectMake(78, 9, 1, 32)];
    self.prefixSeparator.backgroundColor = tgRGB(190, 196, 204);
    [self.inputContainer addSubview:self.prefixSeparator];

    self.inputField = [[UITextField alloc] initWithFrame:CGRectMake(90, 1, width - 132, 48)];
    self.inputField.placeholder = @"Phone number";
    self.inputField.font = [UIFont systemFontOfSize:17];
    self.inputField.textColor = tgRGB(40, 46, 54);
    self.inputField.keyboardType = UIKeyboardTypePhonePad;
    self.inputField.returnKeyType = UIReturnKeyGo;
    self.inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.inputField.delegate = self;
    [self.inputContainer addSubview:self.inputField];

    /* Glossy raised button: gradient body, dark rim, highlight on the top half. */
    self.actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.actionButton.frame = CGRectMake(15, 176, width - 30, 46);
    self.actionButton.layer.cornerRadius = 9.0f;
    self.actionButton.layer.borderWidth = 1.0f;
    self.actionButton.layer.borderColor = tgRGB(26, 66, 102).CGColor;
    self.actionButton.clipsToBounds = YES;
    self.actionButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.actionButton.layer.shadowOffset = CGSizeMake(0, 1);
    self.actionButton.layer.shadowOpacity = 0.35f;
    self.actionButton.layer.shadowRadius = 1.0f;

    CAGradientLayer *btn = tgGloss(CGRectMake(0, 0, width - 30, 46),
                                   tgRGB(92, 156, 210), tgRGB(38, 92, 148));
    [self.actionButton.layer insertSublayer:btn atIndex:0];

    UIView *shine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width - 30, 22)];
    shine.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.18f];
    shine.userInteractionEnabled = NO;
    [self.actionButton addSubview:shine];

    [self.actionButton setTitle:@"Next" forState:UIControlStateNormal];
    [self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.actionButton setTitleColor:[UIColor colorWithWhite:1.0f alpha:0.5f] forState:UIControlStateDisabled];
    self.actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.actionButton.titleLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.4f];
    self.actionButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [self.actionButton addTarget:self action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.actionButton];

    self.spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.center = CGPointMake((width - 30) / 2, 23);
    self.spinner.hidesWhenStopped = YES;
    [self.actionButton addSubview:self.spinner];

    self.scrollView.contentSize = CGSizeMake(width, 250);
    self.currentStep = TGLoginStepPhone;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.inputField becomeFirstResponder];
    });
}

/* Code and password steps have no country prefix, so the prefix field AND the
 * separator have to go - otherwise the divider line stays sitting in the
 * middle of the field. The field then takes the whole well, centred. */
- (void)useSingleFieldLayout {
    CGFloat width = self.view.bounds.size.width;
    self.phonePrefixField.hidden = YES;
    self.prefixSeparator.hidden = YES;
    self.inputField.frame = CGRectMake(14, 1, width - 58, 48);
    self.inputField.textAlignment = NSTextAlignmentCenter;
    self.inputField.font = [UIFont boldSystemFontOfSize:20];
    self.inputField.text = @"";
    self.inputField.returnKeyType = UIReturnKeyGo;
}

- (void)setBusy:(BOOL)busy {
    self.actionButton.enabled = !busy;
    self.nextItem.enabled = !busy;
    if (busy) {
        self.actionButton.titleLabel.alpha = 0.0f;
        [self.spinner startAnimating];
    } else {
        self.actionButton.titleLabel.alpha = 1.0f;
        [self.spinner stopAnimating];
    }
}

- (void)actionButtonTapped {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        return;
    }

    [self setBusy:YES];

    if (self.currentStep == TGLoginStepPhone) {
        NSString *fullPhone = [NSString stringWithFormat:@"%@%@", self.phonePrefixField.text, text];
        self.savedPhoneNumber = fullPhone;
        if (self.onPhoneSubmitted) {
            self.onPhoneSubmitted(fullPhone);
        }
    } else if (self.currentStep == TGLoginStepCode) {
        if (self.onCodeSubmitted) {
            self.onCodeSubmitted(text);
        }
    } else if (self.currentStep == TGLoginStepPassword) {
        if (self.onPasswordSubmitted) {
            self.onPasswordSubmitted(text);
        }
    }
}

- (void)showCodeStepWithPhoneNumber:(NSString *)phoneNumber {
    [self setBusy:NO];
    self.currentStep = TGLoginStepCode;
    self.title = @"Enter Code";
    self.headerLabel.text = @"Enter Code";
    self.subtitleLabel.text = [NSString stringWithFormat:@"We've sent an SMS with an activation code to your phone\n%@", phoneNumber ?: @""];

    [self useSingleFieldLayout];
    self.inputField.placeholder = @"Code";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;
    [self.actionButton setTitle:@"Submit Code" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";
    [self.inputField becomeFirstResponder];
}

- (void)showPasswordStep {
    [self setBusy:NO];
    self.currentStep = TGLoginStepPassword;
    self.title = @"Password";
    self.headerLabel.text = @"Two-Step Verification";
    self.subtitleLabel.text = @"Your account is protected with a password.\nEnter your password below.";

    [self useSingleFieldLayout];
    self.inputField.placeholder = @"Password";
    self.inputField.secureTextEntry = YES;
    self.inputField.keyboardType = UIKeyboardTypeDefault;
    [self.actionButton setTitle:@"Submit Password" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";
    [self.inputField becomeFirstResponder];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self actionButtonTapped];
    return YES;
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    CGRect kbFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat kbHeight = kbFrame.size.height;

    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0, 0, kbHeight + 20, 0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

@end

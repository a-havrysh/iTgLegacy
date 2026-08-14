#import "TGLoginViewController.h"
#import "TGTheme.h"
#import "TGClient.h"
#import "TGCountryPickerViewController.h"
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, TGLoginStep) {
    TGLoginStepPhone,
    TGLoginStepCode,
    TGLoginStepPassword
};

@interface TGLoginViewController ()

@property (nonatomic, assign) TGLoginStep currentStep;
@property (nonatomic, strong) UILabel *noticeLabel;
@property (nonatomic, strong) UIButton *countryButton;
@property (nonatomic, strong) UIImageView *inputBackgroundView;
@property (nonatomic, strong) UIImageView *inputDivider;
@property (nonatomic, strong) UITextField *countryCodeField;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *resendButton;
@property (nonatomic, strong) UILabel *timeoutLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSString *savedPhoneNumber;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, strong) NSTimer *resendTimer;
@property (nonatomic, assign) NSInteger resendSeconds;

@end

@implementation TGLoginViewController

static UIColor *tgRGB(int rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
                           green:((rgb >> 8) & 0xff) / 255.0f
                            blue:(rgb & 0xff) / 255.0f
                           alpha:1.0f];
}

static UIColor *tgRGBA(int rgb, CGFloat alpha) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
                           green:((rgb >> 8) & 0xff) / 255.0f
                            blue:(rgb & 0xff) / 255.0f
                           alpha:alpha];
}

static NSDictionary *tgDialCodes(void) {
    static NSDictionary *codes = nil;
    if (codes == nil) {
        codes = @{ @"US" : @"+1", @"CA" : @"+1", @"GB" : @"+44", @"UA" : @"+380",
                   @"PL" : @"+48", @"DE" : @"+49", @"FR" : @"+33", @"IT" : @"+39",
                   @"ES" : @"+34", @"NL" : @"+31", @"BE" : @"+32", @"CH" : @"+41",
                   @"AT" : @"+43", @"SE" : @"+46", @"NO" : @"+47", @"DK" : @"+45",
                   @"FI" : @"+358", @"PT" : @"+351", @"GR" : @"+30", @"IE" : @"+353",
                   @"CZ" : @"+420", @"SK" : @"+421", @"HU" : @"+36", @"RO" : @"+40",
                   @"BG" : @"+359", @"RS" : @"+381", @"HR" : @"+385", @"SI" : @"+386",
                   @"LT" : @"+370", @"LV" : @"+371", @"EE" : @"+372", @"MD" : @"+373",
                   @"RU" : @"+7", @"KZ" : @"+7", @"BY" : @"+375", @"GE" : @"+995",
                   @"AM" : @"+374", @"AZ" : @"+994", @"TR" : @"+90", @"IL" : @"+972",
                   @"AE" : @"+971", @"SA" : @"+966", @"EG" : @"+20", @"ZA" : @"+27",
                   @"NG" : @"+234", @"KE" : @"+254", @"IN" : @"+91", @"PK" : @"+92",
                   @"BD" : @"+880", @"CN" : @"+86", @"JP" : @"+81", @"KR" : @"+82",
                   @"HK" : @"+852", @"SG" : @"+65", @"MY" : @"+60", @"TH" : @"+66",
                   @"VN" : @"+84", @"ID" : @"+62", @"PH" : @"+63", @"AU" : @"+61",
                   @"NZ" : @"+64", @"BR" : @"+55", @"AR" : @"+54", @"CL" : @"+56",
                   @"CO" : @"+57", @"PE" : @"+51", @"MX" : @"+52", @"VE" : @"+58" };
    }
    return codes;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Your Phone";

    [self setupNavigationBar];
    [self setupUI];
}

- (UIButton *)loginToolbarButtonWithTitle:(NSString *)title
                                    plate:(NSString *)plateName
                                  pressed:(NSString *)pressedName
                                 leftCapHalf:(BOOL)leftCapHalf
                                  leftCap:(int)leftCap
                              shadowColour:(UIColor *)shadowColour
                              paddingLeft:(CGFloat)paddingLeft
                             paddingRight:(CGFloat)paddingRight
                                 minWidth:(CGFloat)minWidth
                                    isBack:(BOOL)isBack {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.exclusiveTouch = YES;
    button.adjustsImageWhenDisabled = NO;
    button.adjustsImageWhenHighlighted = NO;

    UIImage *raw = [UIImage imageNamed:plateName];
    UIImage *rawPressed = [UIImage imageNamed:pressedName];
    if (raw != nil) {
        int cap = leftCapHalf ? (int)(raw.size.width / 2) : leftCap;
        [button setBackgroundImage:[raw stretchableImageWithLeftCapWidth:cap topCapHeight:0] forState:UIControlStateNormal];
    }
    if (rawPressed != nil) {
        int cap = leftCapHalf ? (int)(rawPressed.size.width / 2) : leftCap;
        UIImage *stretched = [rawPressed stretchableImageWithLeftCapWidth:cap topCapHeight:0];
        [button setBackgroundImage:stretched forState:UIControlStateHighlighted];
        [button setBackgroundImage:stretched forState:UIControlStateSelected];
        [button setBackgroundImage:stretched forState:UIControlStateHighlighted | UIControlStateSelected];
    }

    button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    button.titleLabel.shadowOffset = CGSizeMake(0, -1);
    button.titleLabel.backgroundColor = [UIColor clearColor];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleShadowColor:shadowColour forState:UIControlStateNormal];

    CGFloat lift = isBack ? 0.5f : 1.0f;
    button.titleEdgeInsets = UIEdgeInsetsMake(-lift, paddingLeft, lift, paddingRight);
    [button setTitle:title forState:UIControlStateNormal];

    [self sizeLoginToolbarButton:button
                    paddingLeft:paddingLeft
                   paddingRight:paddingRight
                       minWidth:minWidth];

    return button;
}

- (void)sizeLoginToolbarButton:(UIButton *)button
                   paddingLeft:(CGFloat)paddingLeft
                  paddingRight:(CGFloat)paddingRight
                      minWidth:(CGFloat)minWidth {
    NSString *title = [button titleForState:UIControlStateNormal];
    CGSize textSize = title.length > 0 ? [title sizeWithFont:button.titleLabel.font] : CGSizeZero;
    CGFloat width = paddingLeft + paddingRight + ceilf(textSize.width);
    if (width < minWidth)
        width = minWidth;
    button.frame = CGRectMake(button.frame.origin.x, button.frame.origin.y, width, 30);
}

- (void)setupNavigationBar {
    UINavigationBar *bar = self.navigationController.navigationBar;
    if (bar == nil)
        return;

    bar.barStyle = UIBarStyleBlackOpaque;

    UIImage *header = [UIImage imageNamed:@"LoginHeader.png"];
    if (header != nil && [bar respondsToSelector:@selector(setBackgroundImage:forBarMetrics:)])
        [bar setBackgroundImage:header forBarMetrics:UIBarMetricsDefault];

    if ([bar respondsToSelector:@selector(setTitleTextAttributes:)]) {
        if ([bar respondsToSelector:@selector(setBarTintColor:)])
            bar.titleTextAttributes = @{ NSForegroundColorAttributeName : [UIColor whiteColor] };
        else
            bar.titleTextAttributes = @{ UITextAttributeTextColor : [UIColor whiteColor],
                                         UITextAttributeTextShadowColor : tgRGB(0x25272b),
                                         UITextAttributeTextShadowOffset : [NSValue valueWithUIOffset:UIOffsetMake(0, 1)] };
    }

    self.nextButton = [self loginToolbarButtonWithTitle:@"Next"
                                                  plate:@"HeaderButton_Login_Blue.png"
                                                pressed:@"HeaderButton_Login_Blue_Pressed.png"
                                            leftCapHalf:YES
                                                leftCap:0
                                           shadowColour:tgRGBA(0x042651, 0.3f)
                                            paddingLeft:7
                                           paddingRight:7
                                               minWidth:52
                                                 isBack:NO];
    [self.nextButton addTarget:self action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.frame = CGRectMake(floorf((self.nextButton.frame.size.width - self.spinner.frame.size.width) / 2),
                                    floorf((self.nextButton.frame.size.height - self.spinner.frame.size.height) / 2),
                                    self.spinner.frame.size.width, self.spinner.frame.size.height);
    self.spinner.hidesWhenStopped = YES;
    [self.nextButton addSubview:self.spinner];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.nextButton];
}

- (void)setupUI {
    UIImage *linen = [UIImage imageNamed:@"DarkLinen.png"];
    if (linen != nil)
        self.view.backgroundColor = [UIColor colorWithPatternImage:linen];
    else
        self.view.backgroundColor = tgRGB(0x1c1e22);

    UIImage *shadow = [UIImage imageNamed:@"LoginShadow.png"];
    if (shadow != nil) {
        UIImageView *shadowView = [[UIImageView alloc] initWithFrame:self.view.bounds];
        shadowView.image = shadow;
        shadowView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:shadowView];
    }

    UIImage *headerShadow = [UIImage imageNamed:@"HeaderLoginShadow.png"];
    if (headerShadow != nil) {
        UIImageView *headerShadowView = [[UIImageView alloc] initWithImage:[headerShadow stretchableImageWithLeftCapWidth:0 topCapHeight:0]];
        headerShadowView.frame = CGRectMake(0, 0, self.view.bounds.size.width, headerShadow.size.height);
        headerShadowView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self.view addSubview:headerShadowView];
    }

    self.noticeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.noticeLabel.font = [UIFont systemFontOfSize:14];
    self.noticeLabel.textColor = tgRGB(0xc0c5cc);
    self.noticeLabel.shadowColor = tgRGB(0x323c4a);
    self.noticeLabel.shadowOffset = CGSizeMake(0, 1);
    self.noticeLabel.backgroundColor = [UIColor clearColor];
    self.noticeLabel.textAlignment = NSTextAlignmentCenter;
    self.noticeLabel.contentMode = UIViewContentModeCenter;
    self.noticeLabel.numberOfLines = 0;
    self.noticeLabel.text = @"Please confirm your country code and enter your phone number.";
    [self.view addSubview:self.noticeLabel];

    UIImage *rawCountryImage = [UIImage imageNamed:@"LoginCountry.png"];
    UIImage *rawCountryImageHighlighted = [UIImage imageNamed:@"LoginCountry_Highlighted.png"];

    CGFloat countryHeight = rawCountryImage != nil ? rawCountryImage.size.height : 55;
    self.countryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.countryButton.frame = CGRectMake(0, 0, 290, countryHeight);
    self.countryButton.exclusiveTouch = YES;
    if (rawCountryImage != nil)
        [self.countryButton setBackgroundImage:[rawCountryImage stretchableImageWithLeftCapWidth:(int)(rawCountryImage.size.width - 16) topCapHeight:0] forState:UIControlStateNormal];
    if (rawCountryImageHighlighted != nil)
        [self.countryButton setBackgroundImage:[rawCountryImageHighlighted stretchableImageWithLeftCapWidth:(int)(rawCountryImageHighlighted.size.width - 16) topCapHeight:0] forState:UIControlStateHighlighted];
    self.countryButton.titleLabel.font = [UIFont boldSystemFontOfSize:16.5f];
    self.countryButton.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.countryButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [self.countryButton setTitleColor:tgRGB(0xf0f0f0) forState:UIControlStateNormal];
    [self.countryButton setTitleShadowColor:tgRGB(0x17191d) forState:UIControlStateNormal];
    [self.countryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    [self.countryButton setTitleShadowColor:[UIColor clearColor] forState:UIControlStateHighlighted];
    self.countryButton.titleLabel.shadowOffset = CGSizeMake(0, 1);
    self.countryButton.titleEdgeInsets = UIEdgeInsetsMake(0, 14, 9, 14);
    [self.countryButton setTitle:[self currentCountryName] forState:UIControlStateNormal];
    [self.countryButton addTarget:self action:@selector(countryButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    UIImage *arrowImage = [UIImage imageNamed:@"LoginCountryArrow.png"];
    if (arrowImage != nil) {
        UIImageView *arrowView = [[UIImageView alloc] initWithImage:arrowImage highlightedImage:[UIImage imageNamed:@"LoginCountryArrow_Highlighted.png"]];
        arrowView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        arrowView.frame = CGRectMake(290 - arrowImage.size.width - 15, 16, arrowImage.size.width, arrowImage.size.height);
        [self.countryButton addSubview:arrowView];
    }
    [self.view addSubview:self.countryButton];

    UIImage *rawInputImage = [UIImage imageNamed:@"LoginInput.png"];
    self.inputBackgroundView = [[UIImageView alloc] initWithFrame:CGRectZero];
    if (rawInputImage != nil)
        self.inputBackgroundView.image = [rawInputImage stretchableImageWithLeftCapWidth:(int)(rawInputImage.size.width / 2) topCapHeight:(int)(rawInputImage.size.height / 2)];
    [self.view addSubview:self.inputBackgroundView];

    UIImage *rawDivider = [UIImage imageNamed:@"LoginInputDivider.png"];
    self.inputDivider = [[UIImageView alloc] initWithFrame:CGRectMake(60, 1, 1, 48)];
    if (rawDivider != nil)
        self.inputDivider.image = [rawDivider stretchableImageWithLeftCapWidth:0 topCapHeight:4];
    [self.inputBackgroundView addSubview:self.inputDivider];

    self.inputBackgroundView.userInteractionEnabled = YES;
    [self.inputBackgroundView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(inputBackgroundTapped)]];

    self.countryCodeField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.countryCodeField.font = [UIFont boldSystemFontOfSize:18];
    self.countryCodeField.backgroundColor = tgRGB(0xf5f5f5);
    self.countryCodeField.text = [self defaultDialCode];
    self.countryCodeField.textAlignment = NSTextAlignmentCenter;
    self.countryCodeField.keyboardType = UIKeyboardTypeNumberPad;
    self.countryCodeField.delegate = self;
    [self.countryCodeField addTarget:self action:@selector(countryCodeChanged) forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:self.countryCodeField];

    self.inputField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.inputField.font = [UIFont boldSystemFontOfSize:18];
    self.inputField.backgroundColor = tgRGB(0xf5f5f5);
    self.inputField.placeholder = @"Phone number";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;
    self.inputField.delegate = self;
    self.inputField.returnKeyType = UIReturnKeyDone;
    self.inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.inputField addTarget:self action:@selector(inputChanged) forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:self.inputField];

    self.timeoutLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.timeoutLabel.font = [UIFont systemFontOfSize:14];
    self.timeoutLabel.textColor = tgRGB(0xc4c9d2);
    self.timeoutLabel.shadowColor = tgRGB(0x25272b);
    self.timeoutLabel.shadowOffset = CGSizeMake(0, 1);
    self.timeoutLabel.textAlignment = NSTextAlignmentCenter;
    self.timeoutLabel.contentMode = UIViewContentModeCenter;
    self.timeoutLabel.numberOfLines = 0;
    self.timeoutLabel.backgroundColor = [UIColor clearColor];
    self.timeoutLabel.hidden = YES;
    [self.view addSubview:self.timeoutLabel];

    self.resendButton = [self loginToolbarButtonWithTitle:@"Send the code again"
                                                    plate:@"HeaderButton_Login.png"
                                                  pressed:@"HeaderButton_Login_Pressed.png"
                                              leftCapHalf:NO
                                                  leftCap:11
                                             shadowColour:tgRGBA(0x07080a, 0.35f)
                                              paddingLeft:7
                                             paddingRight:7
                                                 minWidth:0
                                                   isBack:NO];
    [self.resendButton addTarget:self action:@selector(resendTapped) forControlEvents:UIControlEventTouchUpInside];
    self.resendButton.hidden = YES;
    [self.view addSubview:self.resendButton];

    self.currentStep = TGLoginStepPhone;
    [self updateCountryNameForDialCode];
    [self layoutInterface];
    [self updateNextEnabled];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.inputField becomeFirstResponder];
    });
}

- (NSString *)currentCountryId {
    NSString *countryId = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    return countryId != nil ? [countryId uppercaseString] : nil;
}

- (NSString *)countryNameForId:(NSString *)countryId {
    if (countryId.length == 0)
        return @"Country";
    NSString *name = [[NSLocale currentLocale] displayNameForKey:NSLocaleCountryCode value:countryId];
    return name.length > 0 ? name : countryId;
}

- (NSString *)currentCountryName {
    return [self countryNameForId:[self currentCountryId]];
}

- (NSString *)defaultDialCode {
    NSString *countryId = [self currentCountryId];
    NSString *dial = countryId != nil ? [tgDialCodes() objectForKey:countryId] : nil;
    return dial != nil ? dial : @"+1";
}

- (void)updateCountryNameForDialCode {
    NSString *dial = self.countryCodeField.text;
    if (dial.length < 2) {
        [self.countryButton setTitle:@"Country" forState:UIControlStateNormal];
        return;
    }

    NSString *currentId = [self currentCountryId];
    if (currentId != nil && [[tgDialCodes() objectForKey:currentId] isEqualToString:dial]) {
        [self.countryButton setTitle:[self countryNameForId:currentId] forState:UIControlStateNormal];
        return;
    }

    NSDictionary *codes = tgDialCodes();
    for (NSString *countryId in codes) {
        if ([[codes objectForKey:countryId] isEqualToString:dial]) {
            [self.countryButton setTitle:[self countryNameForId:countryId] forState:UIControlStateNormal];
            return;
        }
    }
    [self.countryButton setTitle:@"Country" forState:UIControlStateNormal];
}

- (void)countryButtonTapped {
    if (self.currentStep != TGLoginStepPhone)
        return;

    TGCountryPickerViewController *picker = [[TGCountryPickerViewController alloc] init];
    picker.title = @"Country";
    __weak TGLoginViewController *weakSelf = self;
    picker.onPick = ^(NSString *name, NSString *flag, NSString *dialCode) {
        TGLoginViewController *me = weakSelf;
        if (me == nil)
            return;
        if (name.length > 0)
            [me.countryButton setTitle:name forState:UIControlStateNormal];
        if (dialCode.length > 0)
            me.countryCodeField.text = dialCode;
        [me updateNextEnabled];
    };

    if (self.navigationController != nil)
        [self.navigationController pushViewController:picker animated:YES];
}

- (void)layoutInterface {
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGSize viewSize = CGSizeMake(screenSize.width, screenSize.height - 20 - 44 - 216);

    if (self.currentStep == TGLoginStepPhone) {
        CGFloat width = 290;
        self.countryButton.hidden = NO;
        self.countryCodeField.hidden = NO;
        self.inputDivider.hidden = NO;

        self.countryButton.frame = CGRectMake((int)((viewSize.width - width) / 2),
                                              (int)((viewSize.height - 68) / 2) + 4.5f,
                                              width, self.countryButton.frame.size.height);
        self.inputBackgroundView.frame = CGRectIntegral(CGRectMake((viewSize.width - width) / 2,
                                                                   self.countryButton.frame.origin.y + self.countryButton.frame.size.height + 7.5f,
                                                                   width, 47));
        self.inputDivider.frame = CGRectMake(60, 1, 1, self.inputBackgroundView.frame.size.height + 1);
        self.countryCodeField.frame = CGRectMake(self.inputBackgroundView.frame.origin.x + 4, self.inputBackgroundView.frame.origin.y + 12, 54, 22);
        self.inputField.frame = CGRectMake(self.inputBackgroundView.frame.origin.x + 74, self.inputBackgroundView.frame.origin.y + 2,
                                           self.inputBackgroundView.frame.size.width - 74 - 14, 32);
        self.inputField.textAlignment = NSTextAlignmentLeft;
    } else {
        CGFloat width = self.currentStep == TGLoginStepCode ? 80 : 200;
        self.countryButton.hidden = YES;
        self.countryCodeField.hidden = YES;
        self.inputDivider.hidden = YES;

        self.inputBackgroundView.frame = CGRectIntegral(CGRectMake((viewSize.width - width) / 2,
                                                                   (viewSize.height - 26) / 2,
                                                                   width, 43));
        self.inputField.frame = CGRectMake(self.inputBackgroundView.frame.origin.x + 9,
                                           self.inputBackgroundView.frame.origin.y + 10,
                                           self.inputBackgroundView.frame.size.width - 20, 22);
        self.inputField.textAlignment = NSTextAlignmentCenter;
    }

    CGSize noticeSize = [self.noticeLabel sizeThatFits:CGSizeMake(self.currentStep == TGLoginStepPhone ? 270 : 300, 1024)];
    CGFloat anchorY = self.currentStep == TGLoginStepPhone ? self.countryButton.frame.origin.y : self.inputBackgroundView.frame.origin.y;
    CGFloat spacing = self.currentStep == TGLoginStepPhone ? 16 : 14;
    self.noticeLabel.frame = CGRectIntegral(CGRectMake((viewSize.width - noticeSize.width) / 2,
                                                       anchorY - spacing - noticeSize.height,
                                                       noticeSize.width, noticeSize.height));
    self.noticeLabel.alpha = self.noticeLabel.frame.origin.y < 0 ? 0.0f : 1.0f;

    CGFloat resendY = self.inputBackgroundView.frame.origin.y + self.inputBackgroundView.frame.size.height + 14;

    CGSize timeoutSize = [self.timeoutLabel sizeThatFits:CGSizeMake(300, 1024)];
    self.timeoutLabel.frame = CGRectIntegral(CGRectMake((viewSize.width - timeoutSize.width) / 2, resendY, timeoutSize.width, timeoutSize.height));

    self.resendButton.frame = CGRectMake((int)((viewSize.width - self.resendButton.frame.size.width) / 2), resendY,
                                         self.resendButton.frame.size.width, self.resendButton.frame.size.height);

    BOOL onCodeStep = self.currentStep == TGLoginStepCode;
    self.timeoutLabel.hidden = !onCodeStep || self.resendSeconds <= 0;
    self.resendButton.hidden = !onCodeStep || self.resendSeconds > 0;
}

- (void)inputBackgroundTapped {
    [self.inputField becomeFirstResponder];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    [self updateNextEnabled];
    if (busy)
        [self.spinner startAnimating];
    else
        [self.spinner stopAnimating];
}

- (NSString *)trimmedInput {
    return [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)digitsOnly:(NSString *)string {
    if (string.length == 0)
        return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:string.length];
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c >= '0' && c <= '9')
            [result appendFormat:@"%C", c];
    }
    return result;
}

- (BOOL)hasSubmittableInput {
    NSString *text = [self trimmedInput];
    if (self.currentStep == TGLoginStepPhone)
        return [self digitsOnly:text].length >= 4 && [self digitsOnly:self.countryCodeField.text].length >= 1;
    if (self.currentStep == TGLoginStepCode)
        return [self digitsOnly:text].length >= 4;
    return text.length > 0;
}

- (void)updateNextEnabled {
    BOOL enabled = !self.busy && [self hasSubmittableInput];
    self.nextButton.enabled = enabled;
    self.nextButton.titleLabel.alpha = self.busy ? 0.0f : (enabled ? 1.0f : 0.6f);
}

- (void)inputChanged {
    [self updateNextEnabled];

    if (self.currentStep == TGLoginStepCode && !self.busy) {
        if ([self digitsOnly:[self trimmedInput]].length >= 5)
            [self actionButtonTapped];
    }
}

- (void)countryCodeChanged {
    NSString *digits = [self digitsOnly:self.countryCodeField.text];
    if (digits.length > 4)
        digits = [digits substringToIndex:4];
    self.countryCodeField.text = [@"+" stringByAppendingString:digits];
    [self updateCountryNameForDialCode];
    [self updateNextEnabled];
}

- (void)actionButtonTapped {
    if (self.busy)
        return;

    NSString *text = [self trimmedInput];
    if (![self hasSubmittableInput]) {
        [self.inputField becomeFirstResponder];
        return;
    }

    [self setBusy:YES];

    if (self.currentStep == TGLoginStepPhone) {
        NSString *code = [self digitsOnly:self.countryCodeField.text];
        NSString *fullPhone = [NSString stringWithFormat:@"+%@%@", code, [self digitsOnly:text]];
        self.savedPhoneNumber = fullPhone;
        if (self.onPhoneSubmitted) {
            self.onPhoneSubmitted(fullPhone);
        }
    } else if (self.currentStep == TGLoginStepCode) {
        if (self.onCodeSubmitted) {
            self.onCodeSubmitted([self digitsOnly:text]);
        }
    } else if (self.currentStep == TGLoginStepPassword) {
        if (self.onPasswordSubmitted) {
            self.onPasswordSubmitted(text);
        }
    }
}

- (void)showCodeStepWithPhoneNumber:(NSString *)phoneNumber {
    (void)self.view;
    [self setBusy:NO];
    self.currentStep = TGLoginStepCode;
    self.title = phoneNumber.length > 0 ? phoneNumber : (self.savedPhoneNumber.length > 0 ? self.savedPhoneNumber : @"Enter Code");
    self.noticeLabel.text = @"We have sent you an SMS with the code";

    self.inputField.text = @"";
    self.inputField.secureTextEntry = NO;
    self.inputField.placeholder = @"Code";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;

    [self installBackButton];
    [self startResendCountdown];
    [self layoutInterface];
    [self updateNextEnabled];
    [self.inputField becomeFirstResponder];
}

- (void)showPasswordStep {
    (void)self.view;
    [self setBusy:NO];
    self.currentStep = TGLoginStepPassword;
    self.title = @"Password";
    self.noticeLabel.text = @"Your account is protected with a password. Please enter it below.";

    self.inputField.text = @"";
    self.inputField.placeholder = @"Password";
    self.inputField.secureTextEntry = YES;
    self.inputField.keyboardType = UIKeyboardTypeDefault;

    [self stopResendCountdown];
    [self installBackButton];
    [self layoutInterface];
    [self updateNextEnabled];
    [self.inputField becomeFirstResponder];
}

- (void)showPhoneStep {
    (void)self.view;
    [self setBusy:NO];
    self.currentStep = TGLoginStepPhone;
    self.title = @"Your Phone";
    self.noticeLabel.text = @"Please confirm your country code and enter your phone number.";

    self.inputField.text = @"";
    self.inputField.secureTextEntry = NO;
    self.inputField.placeholder = @"Phone number";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;

    [self stopResendCountdown];
    self.navigationItem.leftBarButtonItem = nil;
    [self layoutInterface];
    [self updateNextEnabled];
    [self.inputField becomeFirstResponder];
}

- (void)installBackButton {
    if (self.navigationItem.leftBarButtonItem != nil)
        return;

    UIButton *backButton = [self loginToolbarButtonWithTitle:@"Back"
                                                      plate:@"BackButton_Login.png"
                                                    pressed:@"BackButton_Login_Pressed.png"
                                                leftCapHalf:NO
                                                    leftCap:15
                                               shadowColour:tgRGBA(0x050608, 0.4f)
                                                paddingLeft:15
                                               paddingRight:9
                                                   minWidth:0
                                                     isBack:YES];
    [backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:backButton];
}

- (void)backTapped {
    if (self.busy)
        return;

    [[TGClient shared] logOut];
    [self showPhoneStep];
}

- (void)startResendCountdown {
    [self stopResendCountdown];
    self.resendSeconds = 60;
    [self updateResendTitle];
    self.resendTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                        target:self
                                                      selector:@selector(resendTick)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)stopResendCountdown {
    [self.resendTimer invalidate];
    self.resendTimer = nil;
    self.resendSeconds = 0;
}

- (void)resendTick {
    if (self.resendSeconds > 0)
        self.resendSeconds--;
    [self updateResendTitle];
    if (self.resendSeconds <= 0) {
        [self.resendTimer invalidate];
        self.resendTimer = nil;
    }
}

- (void)updateResendTitle {
    if (self.resendSeconds > 0) {
        self.timeoutLabel.text = [NSString stringWithFormat:@"You can request the code again in %d:%02d",
                                  (int)self.resendSeconds / 60, (int)self.resendSeconds % 60];
        self.resendButton.enabled = NO;
    } else {
        self.resendButton.enabled = YES;
    }
    [self layoutInterface];
}

- (void)resendTapped {
    if (self.busy || self.resendSeconds > 0 || self.currentStep != TGLoginStepCode)
        return;

    [[TGClient shared] send:@{ @"@type" : @"resendAuthenticationCode" }];
    [self startResendCountdown];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (textField == self.countryCodeField) {
        NSString *result = [textField.text stringByReplacingCharactersInRange:range withString:string];
        return [self digitsOnly:result].length <= 4;
    }

    if (self.currentStep == TGLoginStepCode) {
        NSString *result = [textField.text stringByReplacingCharactersInRange:range withString:string];
        return [self digitsOnly:result].length <= 8 && [[self digitsOnly:string] length] == string.length;
    }

    if (self.currentStep == TGLoginStepPhone) {
        NSString *result = [textField.text stringByReplacingCharactersInRange:range withString:string];
        return [self digitsOnly:result].length <= 15;
    }

    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.countryCodeField) {
        [self.inputField becomeFirstResponder];
        return NO;
    }
    [self actionButtonTapped];
    return YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.busy && ![self.inputField isFirstResponder] && ![self.countryCodeField isFirstResponder])
        [self.inputField becomeFirstResponder];
}

- (void)dealloc {
    [_resendTimer invalidate];
    _resendTimer = nil;
    _inputField.delegate = nil;
    _countryCodeField.delegate = nil;
}

@end

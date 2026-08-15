#import "TGLoginViewController.h"
#import "TGTheme.h"
#import "TGClient.h"
#import "TGCountryPickerViewController.h"
#import "TGClient+Account.h"
#import "TGClient+Privacy.h"
#import "TGActionSheet.h"
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, TGLoginStep) {
    TGLoginStepPhone,
    TGLoginStepCode,
    TGLoginStepPassword,
    TGLoginStepEmail,
    TGLoginStepEmailCode,
    TGLoginStepRecoveryCode,
    TGLoginStepNewPassword,
    TGLoginStepQrCode,
    TGLoginStepRegistration
};

static const NSInteger TGLoginAlertTerms = 101;
static const NSInteger TGLoginAlertDeleteAccount = 102;

@protocol TGBackspaceTextFieldDelegate <NSObject>
- (void)textFieldDidHitLastBackspace;
@end

@interface TGBackspaceTextField : UITextField
@property (nonatomic, weak) id<TGBackspaceTextFieldDelegate> backspaceDelegate;
@end

@implementation TGBackspaceTextField

- (void)deleteBackward {
    BOOL wasEmpty = self.text.length == 0;
    [super deleteBackward];
    if (wasEmpty)
        [self.backspaceDelegate textFieldDidHitLastBackspace];
}

@end

@interface TGLoginViewController () <UIAlertViewDelegate, TGBackspaceTextFieldDelegate>

@property (nonatomic, assign) TGLoginStep currentStep;
@property (nonatomic, strong) UILabel *noticeLabel;
@property (nonatomic, strong) UIButton *countryButton;
@property (nonatomic, strong) UIImageView *inputBackgroundView;
@property (nonatomic, strong) UIImageView *inputDivider;
@property (nonatomic, strong) UITextField *countryCodeField;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *resendButton;
@property (nonatomic, strong) UIButton *extraButton;
@property (nonatomic, strong) UIButton *optionsButton;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *timeoutLabel;
@property (nonatomic, strong) UILabel *requestingCallLabel;
@property (nonatomic, strong) UILabel *callSentLabel;
@property (nonatomic, assign) NSInteger callRequestState;
@property (nonatomic, strong) UIView *shadeView;
@property (nonatomic, strong) UIButton *addPhotoButton;
@property (nonatomic, strong) UIImage *plateImage;
@property (nonatomic, strong) UIImage *plateTopImage;
@property (nonatomic, strong) UIImage *plateBottomImage;
@property (nonatomic, strong) UILabel *qrLinkLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSString *savedPhoneNumber;
@property (nonatomic, copy) NSString *emailPattern;
@property (nonatomic, copy) NSString *verifiedRecoveryCode;
@property (nonatomic, copy) NSString *nextCodeTypeTitle;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, strong) NSTimer *resendTimer;
@property (nonatomic, assign) NSInteger resendSeconds;
@property (nonatomic, strong) NSTimer *qrTimer;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, assign) BOOL suppressResendButton;
@property (nonatomic, strong) UITextField *lastNameField;
@property (nonatomic, strong) UIImageView *lastNameBackgroundView;
@property (nonatomic, assign) BOOL codeIsText;
@property (nonatomic, assign) BOOL codeIsPhrase;
@property (nonatomic, copy) NSString *termsText;
@property (nonatomic, assign) NSInteger termsMinUserAge;
@property (nonatomic, strong) NSTimer *authPollTimer;
@property (nonatomic, assign) BOOL passwordResetPending;
@property (nonatomic, copy) NSString *lastQueriedPhonePrefix;
@property (nonatomic, assign) BOOL countryCodeEdited;
@property (nonatomic, assign) BOOL didPrefillGuessedCountry;

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

static void tgStylePlaceholder(UITextField *field, UIFont *font, UIColor *colour) {
    NSString *text = field.placeholder;
    if (text.length == 0)
        return;
    if (![field respondsToSelector:@selector(setAttributedPlaceholder:)])
        return;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (colour != nil)
        [attributes setObject:colour forKey:NSForegroundColorAttributeName];
    if (font != nil)
        [attributes setObject:font forKey:NSFontAttributeName];
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:text attributes:attributes];
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

static NSString *tgGroupDigits(NSString *digits, const int *groups, int groupCount, NSString *separator, BOOL parenthesiseFirst) {
    NSMutableString *result = [NSMutableString string];
    NSUInteger position = 0;
    for (int i = 0; i < groupCount && position < digits.length; i++) {
        NSUInteger length = (NSUInteger)groups[i];
        if (position + length > digits.length)
            length = digits.length - position;
        NSString *chunk = [digits substringWithRange:NSMakeRange(position, length)];
        if (i == 0 && parenthesiseFirst) {
            [result appendFormat:@"(%@", chunk];
            if (position + length < digits.length || length == (NSUInteger)groups[0])
                [result appendString:@")"];
        } else {
            if (result.length > 0)
                [result appendString:i == 1 ? @" " : separator];
            [result appendString:chunk];
        }
        position += length;
    }
    if (position < digits.length)
        [result appendFormat:@"%@%@", separator, [digits substringFromIndex:position]];
    return result;
}

static NSString *tgFormatNationalNumber(NSString *dialDigits, NSString *nationalDigits) {
    if (nationalDigits.length == 0)
        return @"";
    if ([dialDigits isEqualToString:@"1"]) {
        static const int groups[] = { 3, 3, 4 };
        NSMutableString *out = [NSMutableString string];
        NSUInteger position = 0;
        for (int i = 0; i < 3 && position < nationalDigits.length; i++) {
            NSUInteger length = (NSUInteger)groups[i];
            if (position + length > nationalDigits.length)
                length = nationalDigits.length - position;
            NSString *chunk = [nationalDigits substringWithRange:NSMakeRange(position, length)];
            if (i == 0) {
                [out appendFormat:@"(%@", chunk];
                if (length == 3)
                    [out appendString:@")"];
            } else if (i == 1) {
                [out appendFormat:@" %@", chunk];
            } else {
                [out appendFormat:@"-%@", chunk];
            }
            position += length;
        }
        if (position < nationalDigits.length)
            [out appendFormat:@"-%@", [nationalDigits substringFromIndex:position]];
        return out;
    }
    if ([dialDigits isEqualToString:@"7"]) {
        static const int groups[] = { 3, 3, 2, 2 };
        return tgGroupDigits(nationalDigits, groups, 4, @"-", NO);
    }
    return nationalDigits;
}

- (NSString *)formattedPhoneForDigits:(NSString *)nationalDigits {
    return tgFormatNationalNumber([self digitsOnly:self.countryCodeField.text], nationalDigits);
}

- (void)updateTitleText {
    NSString *nationalDigits = [self digitsOnly:self.inputField.text];
    NSString *dialDigits = [self digitsOnly:self.countryCodeField.text];
    if (nationalDigits.length == 0 || dialDigits.length == 0) {
        self.title = @"Your Phone";
        return;
    }
    self.title = [NSString stringWithFormat:@"+%@ %@", dialDigits, tgFormatNationalNumber(dialDigits, nationalDigits)];
}

- (void)reformatPhoneField {
    if (self.currentStep != TGLoginStepPhone)
        return;
    self.inputField.text = [self formattedPhoneForDigits:[self digitsOnly:self.inputField.text]];
    [self updateTitleText];
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

    [self installOptionsButton];
}

- (UIButton *)neutralLoginButtonWithTitle:(NSString *)title {
    return [self loginToolbarButtonWithTitle:title
                                       plate:@"HeaderButton_Login.png"
                                     pressed:@"HeaderButton_Login_Pressed.png"
                                 leftCapHalf:NO
                                     leftCap:11
                                shadowColour:tgRGBA(0x07080a, 0.35f)
                                 paddingLeft:7
                                paddingRight:7
                                    minWidth:0
                                      isBack:NO];
}

- (void)setLoginButton:(UIButton *)button title:(NSString *)title {
    [button setTitle:title forState:UIControlStateNormal];
    [self sizeLoginToolbarButton:button paddingLeft:7 paddingRight:7 minWidth:0];
}

- (void)installOptionsButton {
    if (self.optionsButton == nil) {
        self.optionsButton = [self neutralLoginButtonWithTitle:@"Options"];
        [self.optionsButton addTarget:self action:@selector(optionsTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.optionsButton];
}

- (UILabel *)countdownStateLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = [UIFont systemFontOfSize:14];
    label.textColor = tgRGB(0xc4c9d2);
    label.shadowColor = tgRGB(0x25272b);
    label.shadowOffset = CGSizeMake(0, 1);
    label.textAlignment = NSTextAlignmentCenter;
    label.contentMode = UIViewContentModeCenter;
    label.numberOfLines = 0;
    label.backgroundColor = [UIColor clearColor];
    label.text = text;
    label.hidden = YES;
    return label;
}

- (void)setupUI {
    [self buildBackgroundLayers];
    [self buildNoticeLabel];
    [self buildCountryButton];
    [self buildPlateImages];
    [self buildInputPlate];
    [self buildPhoneFields];
    [self buildLastNameRow];
    [self buildCountdownLabels];
    [self buildResendAndExtraButtons];
    [self buildQrLinkLabel];
    [self buildShadeView];

    self.currentStep = TGLoginStepPhone;
    [self updateCountryNameForDialCode];
    [self layoutInterface];
    [self updateNextEnabled];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.inputField becomeFirstResponder];
    });

    [self prefillGuessedCountry];
}

- (void)buildBackgroundLayers {
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
}

- (void)buildNoticeLabel {
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
}

- (void)buildCountryButton {
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
}

- (void)buildPlateImages {
    UIImage *rawInputImage = [UIImage imageNamed:@"LoginInput.png"];
    if (rawInputImage != nil)
        self.plateImage = [rawInputImage stretchableImageWithLeftCapWidth:(int)(rawInputImage.size.width / 2) topCapHeight:(int)(rawInputImage.size.height / 2)];

    UIImage *rawTopImage = [UIImage imageNamed:@"LoginInput_Top.png"];
    self.plateTopImage = rawTopImage != nil
        ? [rawTopImage stretchableImageWithLeftCapWidth:(int)(rawTopImage.size.width / 2) topCapHeight:0]
        : self.plateImage;

    UIImage *rawBottomImage = [UIImage imageNamed:@"LoginInput_Bottom.png"];
    self.plateBottomImage = rawBottomImage != nil
        ? [rawBottomImage stretchableImageWithLeftCapWidth:(int)(rawBottomImage.size.width / 2) topCapHeight:0]
        : self.plateImage;
}

- (void)buildInputPlate {
    self.inputBackgroundView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.inputBackgroundView.image = self.plateImage;
    [self.view addSubview:self.inputBackgroundView];

    UIImage *rawDivider = [UIImage imageNamed:@"LoginInputDivider.png"];
    self.inputDivider = [[UIImageView alloc] initWithFrame:CGRectMake(60, 1, 1, 48)];
    if (rawDivider != nil)
        self.inputDivider.image = [rawDivider stretchableImageWithLeftCapWidth:0 topCapHeight:4];
    [self.inputBackgroundView addSubview:self.inputDivider];

    self.inputBackgroundView.userInteractionEnabled = YES;
    [self.inputBackgroundView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(inputBackgroundTapped:)]];
}

- (void)buildPhoneFields {
    self.countryCodeField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.countryCodeField.font = [UIFont boldSystemFontOfSize:18];
    self.countryCodeField.backgroundColor = tgRGB(0xf5f5f5);
    self.countryCodeField.text = [self defaultDialCode];
    self.countryCodeField.textAlignment = NSTextAlignmentCenter;
    self.countryCodeField.keyboardType = UIKeyboardTypeNumberPad;
    self.countryCodeField.delegate = self;
    [self.countryCodeField addTarget:self action:@selector(countryCodeChanged) forControlEvents:UIControlEventEditingChanged];
    [self.countryCodeField addTarget:self action:@selector(phoneFieldsDidEndEditing) forControlEvents:UIControlEventEditingDidEnd];
    [self.view addSubview:self.countryCodeField];

    TGBackspaceTextField *phoneField = [[TGBackspaceTextField alloc] initWithFrame:CGRectZero];
    phoneField.backspaceDelegate = self;
    self.inputField = phoneField;
    self.inputField.font = [UIFont boldSystemFontOfSize:18];
    self.inputField.backgroundColor = tgRGB(0xf5f5f5);
    self.inputField.placeholder = @"Your phone number";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;
    self.inputField.delegate = self;
    self.inputField.returnKeyType = UIReturnKeyDone;
    self.inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.inputField addTarget:self action:@selector(inputChanged) forControlEvents:UIControlEventEditingChanged];
    [self.inputField addTarget:self action:@selector(phoneFieldsDidEndEditing) forControlEvents:UIControlEventEditingDidEnd];
    [self.view addSubview:self.inputField];
}

- (void)buildLastNameRow {
    self.lastNameBackgroundView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.lastNameBackgroundView.image = self.plateBottomImage;
    self.lastNameBackgroundView.userInteractionEnabled = YES;
    self.lastNameBackgroundView.hidden = YES;
    [self.lastNameBackgroundView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(lastNameBackgroundTapped)]];
    [self.view addSubview:self.lastNameBackgroundView];

    self.lastNameField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.lastNameField.font = [UIFont boldSystemFontOfSize:15.0f];
    self.lastNameField.backgroundColor = tgRGB(0xf5f5f5);
    self.lastNameField.placeholder = @"Last name";
    self.lastNameField.keyboardType = UIKeyboardTypeDefault;
    self.lastNameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.lastNameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.lastNameField.returnKeyType = UIReturnKeyDone;
    self.lastNameField.delegate = self;
    self.lastNameField.hidden = YES;
    [self.lastNameField addTarget:self action:@selector(inputChanged) forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:self.lastNameField];
}

- (void)buildCountdownLabels {
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

    self.requestingCallLabel = [self countdownStateLabelWithText:@"Requesting a call from Telegram..."];
    [self.view addSubview:self.requestingCallLabel];

    self.callSentLabel = [self countdownStateLabelWithText:@"Telegram dialed your number"];
    [self.view addSubview:self.callSentLabel];
}

- (void)buildResendAndExtraButtons {
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

    self.extraButton = [self neutralLoginButtonWithTitle:@"Didn't get the code?"];
    [self.extraButton addTarget:self action:@selector(extraTapped) forControlEvents:UIControlEventTouchUpInside];
    self.extraButton.hidden = YES;
    [self.view addSubview:self.extraButton];
}

- (void)buildQrLinkLabel {
    self.qrLinkLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.qrLinkLabel.font = [UIFont boldSystemFontOfSize:13];
    self.qrLinkLabel.textColor = tgRGB(0xf0f0f0);
    self.qrLinkLabel.shadowColor = tgRGB(0x25272b);
    self.qrLinkLabel.shadowOffset = CGSizeMake(0, 1);
    self.qrLinkLabel.textAlignment = NSTextAlignmentCenter;
    self.qrLinkLabel.lineBreakMode = NSLineBreakByCharWrapping;
    self.qrLinkLabel.numberOfLines = 0;
    self.qrLinkLabel.backgroundColor = [UIColor clearColor];
    self.qrLinkLabel.hidden = YES;
    [self.view addSubview:self.qrLinkLabel];
}

- (void)buildShadeView {
    self.shadeView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.shadeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.shadeView.backgroundColor = [UIColor clearColor];
    self.shadeView.hidden = YES;
    [self.view addSubview:self.shadeView];
}

- (void)prefillGuessedCountry {
    if (self.didPrefillGuessedCountry || self.countryCodeEdited)
        return;
    self.didPrefillGuessedCountry = YES;

    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] guessedCountryCodeWithCompletion:^(NSString *countryCode) {
        TGLoginViewController *me = weakSelf;
        if (me == nil)
            return;
        if (countryCode.length == 0) {
            me.didPrefillGuessedCountry = NO;
            return;
        }
        if (me.currentStep != TGLoginStepPhone || me.countryCodeEdited)
            return;
        if ([me digitsOnly:me.inputField.text].length > 0)
            return;

        NSString *dial = [tgDialCodes() objectForKey:[countryCode uppercaseString]];
        if (dial.length == 0)
            return;

        me.countryCodeField.text = dial;
        [me setMatchedCountryTitle:[me countryNameForId:[countryCode uppercaseString]]];
        [me updateNextEnabled];
    }];
}

- (void)phoneFieldsDidEndEditing {
    if (self.currentStep != TGLoginStepPhone)
        return;

    NSString *dialDigits = [self digitsOnly:self.countryCodeField.text];
    if (dialDigits.length == 0)
        return;

    NSString *prefix = [NSString stringWithFormat:@"+%@%@", dialDigits, [self digitsOnly:self.inputField.text]];
    if ([prefix isEqualToString:self.lastQueriedPhonePrefix])
        return;
    self.lastQueriedPhonePrefix = prefix;

    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] phoneNumberInfo:prefix completion:^(NSDictionary *info) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || me.currentStep != TGLoginStepPhone)
            return;
        if (![prefix isEqualToString:me.lastQueriedPhonePrefix])
            return;

        NSString *callingCode = [info objectForKey:@"callingCode"];
        if ([callingCode isKindOfClass:[NSString class]] && callingCode.length > 0
                && ![callingCode isEqualToString:[me digitsOnly:me.countryCodeField.text]])
            return;

        NSString *countryName = [info objectForKey:@"countryName"];
        if ([countryName isKindOfClass:[NSString class]] && countryName.length > 0)
            [me setMatchedCountryTitle:countryName];
        else
            [me updateCountryNameForDialCode];
    }];
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

- (void)setMatchedCountryTitle:(NSString *)title {
    [self.countryButton setTitleColor:tgRGB(0xf0f0f0) forState:UIControlStateNormal];
    [self.countryButton setTitle:title forState:UIControlStateNormal];
}

- (void)setUnmatchedCountryTitle {
    [self.countryButton setTitleColor:tgRGBA(0xf0f0f0, 0.7f) forState:UIControlStateNormal];
    [self.countryButton setTitle:self.countryCodeField.text.length <= 1 ? @"Country Code" : @"Invalid Country Code"
                        forState:UIControlStateNormal];
}

- (void)updateCountryNameForDialCode {
    NSString *dial = self.countryCodeField.text;
    if (dial.length < 2) {
        [self setUnmatchedCountryTitle];
        return;
    }

    NSString *currentId = [self currentCountryId];
    if (currentId != nil && [[tgDialCodes() objectForKey:currentId] isEqualToString:dial]) {
        [self setMatchedCountryTitle:[self countryNameForId:currentId]];
        return;
    }

    NSDictionary *codes = tgDialCodes();
    for (NSString *countryId in codes) {
        if ([[codes objectForKey:countryId] isEqualToString:dial]) {
            [self setMatchedCountryTitle:[self countryNameForId:countryId]];
            return;
        }
    }
    [self setUnmatchedCountryTitle];
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
            [me setMatchedCountryTitle:name];
        if (dialCode.length > 0) {
            me.countryCodeField.text = dialCode;
            me.countryCodeEdited = YES;
            me.lastQueriedPhonePrefix = nil;
        }
        [me reformatPhoneField];
        [me updateNextEnabled];
        [me dismissViewControllerAnimated:YES completion:nil];
    };

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:picker];
    UINavigationBar *bar = navigationController.navigationBar;
    bar.barStyle = UIBarStyleBlackOpaque;
    UIImage *header = [UIImage imageNamed:@"LoginHeader.png"];
    if (header != nil && [bar respondsToSelector:@selector(setBackgroundImage:forBarMetrics:)])
        [bar setBackgroundImage:header forBarMetrics:UIBarMetricsDefault];
    if ([bar respondsToSelector:@selector(setTitleTextAttributes:)])
        bar.titleTextAttributes = @{ UITextAttributeTextColor : [UIColor whiteColor],
                                     UITextAttributeTextShadowColor : tgRGB(0x25272b),
                                     UITextAttributeTextShadowOffset : [NSValue valueWithUIOffset:UIOffsetMake(0, 1)] };

    picker.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                               style:UIBarButtonItemStyleBordered
                                                                              target:self
                                                                              action:@selector(dismissCountryPicker)];

    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)dismissCountryPicker {
    [self dismissViewControllerAnimated:YES completion:^{
        [self.inputField becomeFirstResponder];
    }];
}

- (CGFloat)plateWidthForCurrentStep {
    switch (self.currentStep) {
        case TGLoginStepCode:
            return self.codeIsText ? 240 : 80;
        case TGLoginStepEmailCode:
        case TGLoginStepRecoveryCode:
            return 80;
        default:
            return 200;
    }
}

- (void)restylePlaceholders {
    UIFont *fieldFont = [UIFont boldSystemFontOfSize:self.currentStep == TGLoginStepRegistration ? 15.0f : 18.0f];
    if (![self.inputField.font isEqual:fieldFont])
        self.inputField.font = fieldFont;

    if (self.currentStep == TGLoginStepPhone) {
        tgStylePlaceholder(self.inputField, [UIFont systemFontOfSize:17], tgRGB(0x999999));
    } else if (self.currentStep == TGLoginStepRegistration) {
        tgStylePlaceholder(self.inputField, self.inputField.font, tgRGB(0x999da4));
        tgStylePlaceholder(self.lastNameField, self.lastNameField.font, tgRGB(0x999da4));
    } else {
        tgStylePlaceholder(self.inputField, [UIFont systemFontOfSize:18], tgRGB(0xadb0b6));
    }
}

- (void)setNextButtonTitle:(NSString *)title {
    if ([[self.nextButton titleForState:UIControlStateNormal] isEqualToString:title])
        return;
    [self.nextButton setTitle:title forState:UIControlStateNormal];
    [self sizeLoginToolbarButton:self.nextButton
                     paddingLeft:7
                    paddingRight:7
                        minWidth:self.currentStep == TGLoginStepRegistration ? 51 : 52];
    self.spinner.frame = CGRectMake(floorf((self.nextButton.frame.size.width - self.spinner.frame.size.width) / 2),
                                    floorf((self.nextButton.frame.size.height - self.spinner.frame.size.height) / 2),
                                    self.spinner.frame.size.width, self.spinner.frame.size.height);
}

- (void)layoutInterface {
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    BOOL keyboardUp = self.currentStep != TGLoginStepQrCode;
    CGSize viewSize = CGSizeMake(screenSize.width, screenSize.height - 20 - 44 - (keyboardUp ? 216 : 0));

    [self setNextButtonTitle:self.currentStep == TGLoginStepRegistration ? @"Done" : @"Next"];
    [self restylePlaceholders];

    self.noticeLabel.hidden = self.currentStep == TGLoginStepRegistration;
    if (self.currentStep != TGLoginStepRegistration)
        self.inputBackgroundView.image = self.plateImage;

    if (self.currentStep != TGLoginStepRegistration) {
        self.lastNameBackgroundView.hidden = YES;
        self.lastNameField.hidden = YES;
    }

    if (self.currentStep == TGLoginStepRegistration) {
        [self layoutRegistrationStepForViewSize:viewSize];
        return;
    }

    if (self.currentStep == TGLoginStepQrCode) {
        [self layoutQrStepForViewSize:viewSize];
        return;
    }

    self.inputBackgroundView.hidden = NO;
    self.inputField.hidden = NO;
    self.qrLinkLabel.hidden = YES;

    if (self.currentStep == TGLoginStepPhone)
        [self layoutPhoneRowForViewSize:viewSize];
    else
        [self layoutCentredPlateForViewSize:viewSize];

    [self layoutNoticeLabelForViewSize:viewSize];
    [self layoutCountdownRowForViewSize:viewSize];
}

- (void)layoutRegistrationStepForViewSize:(CGSize)viewSize {
    CGFloat width = 288;
    self.countryButton.hidden = YES;
    self.countryCodeField.hidden = YES;
    self.inputDivider.hidden = YES;
    self.qrLinkLabel.hidden = YES;
    self.inputBackgroundView.hidden = NO;
    self.inputField.hidden = NO;
    self.lastNameBackgroundView.hidden = NO;
    self.lastNameField.hidden = NO;

    self.inputBackgroundView.image = self.plateTopImage;
    self.lastNameBackgroundView.image = self.plateBottomImage;

    CGFloat retinaOffset = [UIScreen mainScreen].scale > 1.0f ? 0.5f : 0.0f;
    CGFloat top = (int)((viewSize.height - 68) / 2) - 7;
    self.inputBackgroundView.frame = CGRectMake((int)((viewSize.width - width) / 2), top, width, 43);
    self.inputField.frame = CGRectMake(self.inputBackgroundView.frame.origin.x + 15,
                                       self.inputBackgroundView.frame.origin.y + 11.0f + retinaOffset,
                                       width - 20, 22);
    self.inputField.textAlignment = NSTextAlignmentLeft;

    self.lastNameBackgroundView.frame = CGRectIntegral(CGRectMake(self.inputBackgroundView.frame.origin.x,
                                                                  self.inputBackgroundView.frame.origin.y + 43,
                                                                  width, 43));
    self.lastNameField.frame = CGRectMake(self.lastNameBackgroundView.frame.origin.x + 15,
                                          self.lastNameBackgroundView.frame.origin.y + 10.0f + retinaOffset,
                                          width - 20, 22);

    self.noticeLabel.hidden = YES;

    self.timeoutLabel.hidden = YES;
    self.requestingCallLabel.hidden = YES;
    self.callSentLabel.hidden = YES;
    self.resendButton.hidden = YES;
    self.extraButton.hidden = YES;
}

- (void)layoutQrStepForViewSize:(CGSize)viewSize {
    self.countryButton.hidden = YES;
    self.countryCodeField.hidden = YES;
    self.inputDivider.hidden = YES;
    self.inputBackgroundView.hidden = YES;
    self.inputField.hidden = YES;
    self.qrLinkLabel.hidden = NO;

    CGSize noticeSize = [self.noticeLabel sizeThatFits:CGSizeMake(280, 1024)];
    self.noticeLabel.frame = CGRectIntegral(CGRectMake((viewSize.width - noticeSize.width) / 2, 40, noticeSize.width, noticeSize.height));
    self.noticeLabel.alpha = 1.0f;

    CGSize linkSize = [self.qrLinkLabel sizeThatFits:CGSizeMake(280, 1024)];
    self.qrLinkLabel.frame = CGRectIntegral(CGRectMake((viewSize.width - linkSize.width) / 2,
                                                       self.noticeLabel.frame.origin.y + self.noticeLabel.frame.size.height + 24,
                                                       linkSize.width, linkSize.height));

    self.timeoutLabel.hidden = YES;
    self.requestingCallLabel.hidden = YES;
    self.callSentLabel.hidden = YES;
    self.resendButton.hidden = YES;
    self.extraButton.hidden = NO;
    self.extraButton.frame = CGRectMake((int)((viewSize.width - self.extraButton.frame.size.width) / 2),
                                        viewSize.height - self.extraButton.frame.size.height - 20,
                                        self.extraButton.frame.size.width, self.extraButton.frame.size.height);
}

- (void)layoutPhoneRowForViewSize:(CGSize)viewSize {
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
}

- (void)layoutCentredPlateForViewSize:(CGSize)viewSize {
    CGFloat width = [self plateWidthForCurrentStep];
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

- (void)layoutNoticeLabelForViewSize:(CGSize)viewSize {
    CGSize noticeSize = [self.noticeLabel sizeThatFits:CGSizeMake(self.currentStep == TGLoginStepPhone ? 270 : 300, 1024)];
    CGFloat anchorY = self.currentStep == TGLoginStepPhone ? self.countryButton.frame.origin.y : self.inputBackgroundView.frame.origin.y;
    CGFloat spacing = self.currentStep == TGLoginStepPhone ? 16 : 14;
    self.noticeLabel.frame = CGRectIntegral(CGRectMake((viewSize.width - noticeSize.width) / 2,
                                                       anchorY - spacing - noticeSize.height,
                                                       noticeSize.width, noticeSize.height));
    self.noticeLabel.alpha = self.noticeLabel.frame.origin.y < 0 ? 0.0f : 1.0f;
}

- (void)layoutCountdownRowForViewSize:(CGSize)viewSize {
    CGFloat resendY = self.inputBackgroundView.frame.origin.y + self.inputBackgroundView.frame.size.height + 14;

    CGSize timeoutSize = [self.timeoutLabel sizeThatFits:CGSizeMake(300, 1024)];
    self.timeoutLabel.frame = CGRectIntegral(CGRectMake((viewSize.width - timeoutSize.width) / 2, resendY, timeoutSize.width, timeoutSize.height));

    CGSize requestingSize = [self.requestingCallLabel sizeThatFits:CGSizeMake(300, 1024)];
    self.requestingCallLabel.frame = CGRectIntegral(CGRectMake((viewSize.width - requestingSize.width) / 2, resendY, requestingSize.width, requestingSize.height));

    CGSize callSentSize = [self.callSentLabel sizeThatFits:CGSizeMake(300, 1024)];
    self.callSentLabel.frame = CGRectIntegral(CGRectMake((viewSize.width - callSentSize.width) / 2, resendY, callSentSize.width, callSentSize.height));

    self.resendButton.frame = CGRectMake((int)((viewSize.width - self.resendButton.frame.size.width) / 2), resendY,
                                         self.resendButton.frame.size.width, self.resendButton.frame.size.height);

    BOOL resetRow = self.currentStep == TGLoginStepPassword && self.passwordResetPending;
    BOOL countdownStep = self.currentStep == TGLoginStepCode || self.currentStep == TGLoginStepEmailCode;

    BOOL callStateVisible = self.currentStep == TGLoginStepCode && self.callRequestState > 0 && self.resendSeconds <= 0;
    self.requestingCallLabel.hidden = !(callStateVisible && self.callRequestState == 1);
    self.callSentLabel.hidden = !(callStateVisible && self.callRequestState == 2);

    if (resetRow) {
        self.timeoutLabel.hidden = NO;
        self.resendButton.hidden = NO;
        self.resendButton.frame = CGRectMake((int)((viewSize.width - self.resendButton.frame.size.width) / 2),
                                             resendY + timeoutSize.height + 8,
                                             self.resendButton.frame.size.width, self.resendButton.frame.size.height);
    } else {
        self.timeoutLabel.hidden = !countdownStep || (self.resendSeconds <= 0 && self.callRequestState == 0);
        self.resendButton.hidden = !countdownStep || self.resendSeconds > 0 || self.suppressResendButton;
    }

    BOOL hasExtra = self.currentStep == TGLoginStepCode || self.currentStep == TGLoginStepPassword;
    self.extraButton.hidden = !hasExtra;
    CGFloat extraY = resendY;
    if (self.currentStep == TGLoginStepCode)
        extraY += 38;
    else if (resetRow)
        extraY += timeoutSize.height + 8 + self.resendButton.frame.size.height + 8;
    self.extraButton.frame = CGRectMake((int)((viewSize.width - self.extraButton.frame.size.width) / 2), extraY,
                                        self.extraButton.frame.size.width, self.extraButton.frame.size.height);
}

- (void)inputBackgroundTapped:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateRecognized)
        return;

    if (!self.countryCodeField.hidden) {
        CGPoint location = [recognizer locationInView:self.inputBackgroundView];
        CGFloat countryRight = self.countryCodeField.frame.origin.x + self.countryCodeField.frame.size.width
            - self.inputBackgroundView.frame.origin.x;
        if (location.x < countryRight) {
            [self.countryCodeField becomeFirstResponder];
            return;
        }
    }

    [self.inputField becomeFirstResponder];
}

- (void)textFieldDidHitLastBackspace {
    if (self.currentStep == TGLoginStepPhone)
        [self.countryCodeField becomeFirstResponder];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.shadeView.hidden = !busy;
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
        return self.codeIsText ? text.length >= 2 : [self digitsOnly:text].length >= 4;
    if (self.currentStep == TGLoginStepRegistration)
        return text.length > 0;
    if (self.currentStep == TGLoginStepEmail)
        return [text rangeOfString:@"@"].location != NSNotFound && text.length >= 5;
    if (self.currentStep == TGLoginStepEmailCode)
        return text.length >= 4;
    if (self.currentStep == TGLoginStepRecoveryCode)
        return text.length >= 4;
    if (self.currentStep == TGLoginStepQrCode)
        return NO;
    return text.length > 0;
}

- (void)updateNextEnabled {
    BOOL enabled = !self.busy && self.currentStep != TGLoginStepQrCode;
    self.nextButton.enabled = enabled;
    self.nextButton.titleLabel.alpha = self.busy ? 0.0f : (enabled ? 1.0f : 0.6f);
}

- (void)shakeView:(UIView *)view {
    if (view == nil || view.hidden)
        return;

    CGRect originalFrame = view.frame;
    CGRect right = originalFrame;
    right.origin.x = originalFrame.origin.x + 4;
    CGRect left = originalFrame;
    left.origin.x = originalFrame.origin.x - 4;

    [UIView animateWithDuration:0.05 delay:0.0 options:UIViewAnimationOptionAutoreverse animations:^{
        view.frame = right;
    } completion:^(BOOL finished) {
        if (!finished) {
            view.frame = originalFrame;
            return;
        }
        [UIView animateWithDuration:0.05
                              delay:0.0
                            options:(UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse)
                         animations:^{
            [UIView setAnimationRepeatCount:3];
            view.frame = left;
        } completion:^(__unused BOOL innerFinished) {
            view.frame = originalFrame;
        }];
    }];
}

- (void)shakeInputRow {
    [self shakeView:self.inputField];
    [self shakeView:self.inputBackgroundView];
    if (!self.countryCodeField.hidden)
        [self shakeView:self.countryCodeField];
    if (self.currentStep == TGLoginStepRegistration) {
        [self shakeView:self.lastNameField];
        [self shakeView:self.lastNameBackgroundView];
    }
}

- (void)inputChanged {
    [self updateNextEnabled];

    if (self.currentStep == TGLoginStepCode && !self.codeIsText && !self.busy) {
        if ([self digitsOnly:[self trimmedInput]].length >= 5)
            [self actionButtonTapped];
    }
}

- (void)countryCodeChanged {
    NSString *digits = [self digitsOnly:self.countryCodeField.text];
    if (digits.length > 4)
        digits = [digits substringToIndex:4];
    self.countryCodeField.text = [@"+" stringByAppendingString:digits];
    self.countryCodeEdited = YES;
    self.lastQueriedPhonePrefix = nil;
    [self updateCountryNameForDialCode];
    [self reformatPhoneField];
    [self updateNextEnabled];
}

- (void)actionButtonTapped {
    if (self.busy)
        return;

    if (self.currentStep == TGLoginStepQrCode)
        return;

    NSString *text = [self trimmedInput];
    if (![self hasSubmittableInput]) {
        [self shakeInputRow];
        if (self.currentStep == TGLoginStepPhone && [self digitsOnly:self.countryCodeField.text].length < 1)
            [self.countryCodeField becomeFirstResponder];
        else
            [self.inputField becomeFirstResponder];
        return;
    }

    [self setBusy:YES];

    if (self.currentStep == TGLoginStepPhone) {
        [self submitPhoneNumber:text];
    } else if (self.currentStep == TGLoginStepCode) {
        [self submitCode:text];
    } else if (self.currentStep == TGLoginStepRegistration) {
        [self submitRegistrationFirstName:text];
    } else if (self.currentStep == TGLoginStepPassword) {
        [self submitPassword:text];
    } else if (self.currentStep == TGLoginStepEmail) {
        [self submitEmailAddress:text];
    } else if (self.currentStep == TGLoginStepEmailCode) {
        [self submitEmailCode:text];
    } else if (self.currentStep == TGLoginStepRecoveryCode) {
        [self submitRecoveryCode:text];
    } else if (self.currentStep == TGLoginStepNewPassword) {
        [self submitNewPassword:text];
    }
}

- (void)submitPhoneNumber:(NSString *)text {
    NSString *code = [self digitsOnly:self.countryCodeField.text];
    NSString *fullPhone = [NSString stringWithFormat:@"+%@%@", code, [self digitsOnly:text]];
    self.savedPhoneNumber = fullPhone;
    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] startLoginWithPhoneNumber:fullPhone
                                 isCurrentNumber:NO
                                      completion:^(BOOL ok) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || ok)
            return;
        if (me.currentStep != TGLoginStepPhone)
            return;
        [me setBusy:NO];
        [me shakeInputRow];
        [me showLoginAlert:@"This phone number was not accepted. Please check it and try again."];
        [me.inputField becomeFirstResponder];
    }];
}

- (void)submitCode:(NSString *)text {
    if (self.onCodeSubmitted) {
        self.onCodeSubmitted(self.codeIsText ? text : [self digitsOnly:text]);
    }
}

- (void)submitRegistrationFirstName:(NSString *)text {
    NSString *lastName = [self.lastNameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] registerWithFirstName:text lastName:lastName.length > 0 ? lastName : nil completion:^(BOOL ok) {
        TGLoginViewController *me = weakSelf;
        if (me == nil)
            return;
        [me setBusy:NO];
        if (!ok)
            [me showLoginAlert:@"This name was not accepted. Please try again."];
    }];
}

- (void)submitPassword:(NSString *)text {
    if (self.onPasswordSubmitted) {
        self.onPasswordSubmitted(text);
    }
}

- (void)submitEmailAddress:(NSString *)text {
    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] setAuthenticationEmailAddress:text completion:^(NSString *pattern, NSInteger codeLength) {
        TGLoginViewController *me = weakSelf;
        if (me == nil)
            return;
        [me setBusy:NO];
        if (pattern.length == 0) {
            [me showLoginAlert:@"This email address was not accepted."];
            return;
        }
        [me showEmailCodeStepWithPattern:pattern];
    }];
}

- (void)submitEmailCode:(NSString *)text {
    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] checkAuthenticationEmailCode:text completion:^(BOOL ok) {
        TGLoginViewController *me = weakSelf;
        if (me == nil)
            return;
        [me setBusy:NO];
        if (!ok) {
            me.inputField.text = @"";
            [me updateNextEnabled];
            [me showLoginAlert:@"Invalid code. Please try again."];
        }
    }];
}

- (void)submitRecoveryCode:(NSString *)text {
    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] checkAuthenticationPasswordRecoveryCode:text completion:^(BOOL ok) {
        TGLoginViewController *me = weakSelf;
        if (me == nil)
            return;
        [me setBusy:NO];
        if (!ok) {
            me.inputField.text = @"";
            [me updateNextEnabled];
            [me showLoginAlert:@"Invalid recovery code. Please try again."];
            return;
        }
        me.verifiedRecoveryCode = text;
        [me showNewPasswordStep];
    }];
}

- (void)submitNewPassword:(NSString *)text {
    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] recoverAuthenticationPasswordWithCode:self.verifiedRecoveryCode
                                                 newPassword:text
                                                     newHint:nil
                                                  completion:^(BOOL ok) {
        TGLoginViewController *me = weakSelf;
        if (me == nil)
            return;
        [me setBusy:NO];
        if (!ok)
            [me showLoginAlert:@"The password could not be changed. Please try again."];
    }];
}

- (void)showLoginAlert:(NSString *)message {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)enterStep:(TGLoginStep)step title:(NSString *)title notice:(NSString *)notice {
    self.currentStep = step;
    self.title = title;
    self.noticeLabel.text = notice;
}

- (void)finishStepTransition {
    [self layoutInterface];
    [self updateNextEnabled];
}

- (void)finishStepTransitionFocusingInput {
    [self finishStepTransition];
    [self.inputField becomeFirstResponder];
}

- (void)showCodeStepWithPhoneNumber:(NSString *)phoneNumber {
    (void)self.view;
    [self setBusy:NO];
    [self stopQrRefresh];
    self.suppressResendButton = NO;
    self.codeIsText = NO;
    self.codeIsPhrase = NO;
    [self enterStep:TGLoginStepCode
              title:phoneNumber.length > 0 ? phoneNumber : (self.savedPhoneNumber.length > 0 ? self.savedPhoneNumber : @"Enter Code")
             notice:@"We've sent an SMS with an activation code to your phone. Please enter the code below."];

    self.inputField.text = @"";
    self.inputField.secureTextEntry = NO;
    self.inputField.placeholder = @"Code";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;

    [self startAuthPoll];

    [self setLoginButton:self.resendButton title:@"Send the code again"];
    [self setLoginButton:self.extraButton title:@"Didn't get the code?"];
    self.nextCodeTypeTitle = nil;

    [self installBackButton];
    [self startResendCountdown];
    [self finishStepTransitionFocusingInput];

    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] authenticationCodeInfoWithCompletion:^(NSDictionary *info) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || me.currentStep != TGLoginStepCode || info == nil)
            return;
        [me applyCodeInfo:info];
    }];
}

- (void)applyTextCodeType:(BOOL)isPhrase {
    self.codeIsText = YES;
    self.codeIsPhrase = isPhrase;

    self.inputField.keyboardType = UIKeyboardTypeDefault;
    self.inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.inputField.placeholder = isPhrase ? @"Phrase" : @"Word";
    if ([self.inputField isFirstResponder])
        [self.inputField reloadInputViews];

    self.noticeLabel.text = isPhrase
        ? @"We have sent you an SMS with a secret phrase. Please enter it below."
        : @"We have sent you an SMS with a secret word. Please enter it below.";
}

- (void)applyCodeInfo:(NSDictionary *)info {
    NSString *type = [info objectForKey:@"type"];
    BOOL isWordCode = [type isKindOfClass:[NSString class]] && [type isEqualToString:@"authenticationCodeTypeSmsWord"];
    BOOL isPhraseCode = [type isKindOfClass:[NSString class]] && [type isEqualToString:@"authenticationCodeTypeSmsPhrase"];

    if (isWordCode || isPhraseCode) {
        [self applyTextCodeType:isPhraseCode];
    } else if (self.codeIsText) {
        self.codeIsText = NO;
        self.codeIsPhrase = NO;
        self.inputField.placeholder = @"Code";
        self.inputField.keyboardType = UIKeyboardTypeNumberPad;
        if ([self.inputField isFirstResponder])
            [self.inputField reloadInputViews];
    }

    NSString *description = [info objectForKey:@"description"];
    if (!self.codeIsText && [description isKindOfClass:[NSString class]] && description.length > 0)
        self.noticeLabel.text = description;

    NSString *nextDescription = [info objectForKey:@"nextDescription"];
    if ([nextDescription isKindOfClass:[NSString class]] && nextDescription.length > 0) {
        self.nextCodeTypeTitle = nextDescription;
        [self setLoginButton:self.resendButton title:nextDescription];
    }

    NSNumber *timeout = [info objectForKey:@"timeout"];
    if ([timeout isKindOfClass:[NSNumber class]] && [timeout intValue] > 0) {
        [self stopResendCountdown];
        self.resendSeconds = [timeout integerValue];
        self.callRequestState = 0;
        self.timeoutLabel.alpha = 1.0f;
        [self startResendTimer];
    }

    [self updateResendTitle];
    [self layoutInterface];
}

- (void)startAuthPoll {
    [self stopAuthPoll];
    self.authPollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(authPollTick)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)stopAuthPoll {
    [self.authPollTimer invalidate];
    self.authPollTimer = nil;
}

- (void)authPollTick {
    if (self.currentStep != TGLoginStepCode) {
        [self stopAuthPoll];
        return;
    }
    if ([TGClient shared].authState == TGAuthStateWaitRegistration) {
        [self stopAuthPoll];
        [self showRegistrationStep];
    }
}

- (void)showRegistrationStep {
    (void)self.view;
    [self setBusy:NO];
    [self stopAuthPoll];
    [self stopResendCountdown];
    [self stopQrRefresh];
    [self enterStep:TGLoginStepRegistration
              title:@"Your Info"
             notice:@"Enter your name so your friends know who is writing to them."];

    self.inputField.text = @"";
    self.inputField.secureTextEntry = NO;
    self.inputField.font = [UIFont boldSystemFontOfSize:15.0f];
    self.inputField.placeholder = @"First name";
    self.inputField.keyboardType = UIKeyboardTypeDefault;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.inputField.returnKeyType = UIReturnKeyNext;
    self.lastNameField.text = @"";

    [self installBackButton];
    [self finishStepTransitionFocusingInput];

    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] registrationTermsWithCompletion:^(NSDictionary *terms) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || me.currentStep != TGLoginStepRegistration || terms == nil)
            return;
        [me applyRegistrationTerms:terms];
    }];
}

- (void)applyRegistrationTerms:(NSDictionary *)terms {
    NSString *text = [terms objectForKey:@"text"];
    if (![text isKindOfClass:[NSString class]])
        text = @"";
    self.termsText = text;

    NSNumber *minAge = [terms objectForKey:@"minUserAge"];
    self.termsMinUserAge = [minAge isKindOfClass:[NSNumber class]] ? [minAge integerValue] : 0;

    NSNumber *showPopup = [terms objectForKey:@"showPopup"];
    if (![showPopup isKindOfClass:[NSNumber class]] || ![showPopup boolValue])
        return;

    NSMutableString *message = [NSMutableString string];
    if (text.length > 0)
        [message appendString:text];
    if (self.termsMinUserAge > 0) {
        if (message.length > 0)
            [message appendString:@"\n\n"];
        [message appendFormat:@"You must be at least %d years old to use Telegram.", (int)self.termsMinUserAge];
    }
    if (message.length == 0)
        return;

    [self.inputField resignFirstResponder];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Terms of Service"
                                                    message:message
                                                   delegate:self
                                          cancelButtonTitle:@"Decline"
                                          otherButtonTitles:@"Accept", nil];
    alert.tag = TGLoginAlertTerms;
    [alert show];
}

- (void)lastNameBackgroundTapped {
    [self.lastNameField becomeFirstResponder];
}

- (void)showPasswordStep {
    (void)self.view;
    [self setBusy:NO];
    [self stopQrRefresh];
    [self stopAuthPoll];
    [self enterStep:TGLoginStepPassword
              title:@"Password"
             notice:@"Your account is protected with a password. Please enter it below."];
    [self setLoginButton:self.extraButton title:@"Forgot password?"];

    self.inputField.text = @"";
    self.inputField.placeholder = @"Password";
    self.inputField.secureTextEntry = YES;
    self.inputField.keyboardType = UIKeyboardTypeDefault;
    self.inputField.returnKeyType = UIReturnKeyDone;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;

    self.passwordResetPending = NO;
    [self stopResendCountdown];
    [self installBackButton];
    [self finishStepTransitionFocusingInput];
}

- (void)showPhoneStep {
    (void)self.view;
    [self setBusy:NO];
    [self enterStep:TGLoginStepPhone
              title:@"Your Phone"
             notice:@"Please confirm your country code and enter your phone number."];

    self.inputField.text = @"";
    self.inputField.secureTextEntry = NO;
    self.inputField.font = [UIFont boldSystemFontOfSize:18];
    self.inputField.placeholder = @"Your phone number";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;
    self.inputField.returnKeyType = UIReturnKeyDone;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.codeIsText = NO;
    self.codeIsPhrase = NO;
    self.passwordResetPending = NO;
    self.lastQueriedPhonePrefix = nil;

    [self stopResendCountdown];
    [self stopQrRefresh];
    [self stopAuthPoll];
    [self installOptionsButton];
    [self finishStepTransitionFocusingInput];
    [self prefillGuessedCountry];
}

- (void)optionsTapped {
    if (self.busy || self.currentStep != TGLoginStepPhone)
        return;

    [self.inputField resignFirstResponder];
    [self.countryCodeField resignFirstResponder];

    NSArray *actions = @[ [[TGActionSheetAction alloc] initWithTitle:@"Log in by QR Code" action:@"qr"],
                          [[TGActionSheetAction alloc] initWithTitle:@"Log in with Email" action:@"email"],
                          [[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel" type:TGActionSheetActionTypeCancel] ];

    __weak TGLoginViewController *weakSelf = self;
    TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:nil
                                                        actions:actions
                                                    actionBlock:^(__unused id target, NSString *action) {
        TGLoginViewController *me = weakSelf;
        if (me == nil)
            return;
        if ([action isEqualToString:@"qr"])
            [me showQrCodeStep];
        else if ([action isEqualToString:@"email"])
            [me showEmailStep];
        else
            [me.inputField becomeFirstResponder];
    } target:self];
    self.currentActionSheet = sheet;
    [sheet showInView:self.view];
}

- (void)showEmailStep {
    (void)self.view;
    [self setBusy:NO];
    [self stopResendCountdown];
    [self stopQrRefresh];
    [self enterStep:TGLoginStepEmail
              title:@"Email"
             notice:@"Enter the email address connected to your Telegram account."];

    self.inputField.text = @"";
    self.inputField.secureTextEntry = NO;
    self.inputField.placeholder = @"Email";
    self.inputField.keyboardType = UIKeyboardTypeEmailAddress;

    [self installBackButton];
    [self finishStepTransitionFocusingInput];
}

- (void)showEmailCodeStepWithPattern:(NSString *)pattern {
    (void)self.view;
    [self setBusy:NO];
    [self stopQrRefresh];
    self.suppressResendButton = NO;
    self.emailPattern = pattern;
    [self enterStep:TGLoginStepEmailCode
              title:@"Email Code"
             notice:[NSString stringWithFormat:@"We have sent a code to %@", pattern]];

    self.inputField.text = @"";
    self.inputField.secureTextEntry = NO;
    self.inputField.placeholder = @"Code";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;

    [self setLoginButton:self.resendButton title:@"Reset email address"];
    [self installBackButton];
    [self finishStepTransitionFocusingInput];

    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] authenticationEmailStateWithCompletion:^(NSDictionary *info) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || me.currentStep != TGLoginStepEmailCode || info == nil)
            return;
        [me applyEmailState:info];
    }];
}

- (void)applyEmailState:(NSDictionary *)info {
    NSString *resetState = [info objectForKey:@"resetState"];
    if (![resetState isKindOfClass:[NSString class]])
        resetState = @"";

    if ([resetState isEqualToString:@"pending"]) {
        NSNumber *resetIn = [info objectForKey:@"resetIn"];
        [self stopResendCountdown];
        self.resendSeconds = [resetIn isKindOfClass:[NSNumber class]] ? [resetIn integerValue] : 0;
        if (self.resendSeconds > 0)
            [self startResendTimer];
    } else if ([resetState isEqualToString:@"available"]) {
        [self stopResendCountdown];
    } else {
        [self stopResendCountdown];
        self.suppressResendButton = YES;
    }

    [self updateResendTitle];
    [self layoutInterface];
}

- (void)showRecoveryCodeStep {
    (void)self.view;
    [self setBusy:NO];
    [self stopResendCountdown];
    [self stopQrRefresh];
    [self enterStep:TGLoginStepRecoveryCode
              title:@"Recovery"
             notice:@"We have sent a recovery code to the email address you provided when setting up your password."];

    self.inputField.text = @"";
    self.inputField.secureTextEntry = NO;
    self.inputField.placeholder = @"Code";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;

    [self installBackButton];
    [self finishStepTransitionFocusingInput];
}

- (void)showNewPasswordStep {
    (void)self.view;
    [self setBusy:NO];
    [self stopResendCountdown];
    [self stopQrRefresh];
    [self enterStep:TGLoginStepNewPassword
              title:@"New Password"
             notice:@"Please enter a new password for your account."];

    self.inputField.text = @"";
    self.inputField.secureTextEntry = YES;
    self.inputField.placeholder = @"New password";
    self.inputField.keyboardType = UIKeyboardTypeDefault;

    [self installBackButton];
    [self finishStepTransitionFocusingInput];
}

- (void)showQrCodeStep {
    (void)self.view;
    [self setBusy:YES];
    [self stopResendCountdown];
    [self enterStep:TGLoginStepQrCode
              title:@"Log in by QR Code"
             notice:@"1. Open Telegram on your other phone\n2. Go to Settings → Devices\n3. Add this device with the link below"];
    self.qrLinkLabel.text = @"Requesting a link…";

    [self.inputField resignFirstResponder];
    [self.countryCodeField resignFirstResponder];

    [self setLoginButton:self.extraButton title:@"Log in with phone number"];
    [self installBackButton];
    [self finishStepTransition];

    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] requestQrCodeLoginWithCompletion:^(NSString *link) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || me.currentStep != TGLoginStepQrCode)
            return;
        [me setBusy:NO];
        if (link.length == 0) {
            me.qrLinkLabel.text = @"This account cannot be logged in by QR code.";
            [me layoutInterface];
            return;
        }
        [me applyQrLink:link];
        [me startQrRefresh];
    }];
}

- (void)applyQrLink:(NSString *)link {
    self.qrLinkLabel.text = link;
    [self layoutInterface];
}

- (void)startQrRefresh {
    [self stopQrRefresh];
    self.qrTimer = [NSTimer scheduledTimerWithTimeInterval:20.0
                                                    target:self
                                                  selector:@selector(refreshQrLink)
                                                  userInfo:nil
                                                   repeats:YES];
}

- (void)stopQrRefresh {
    [self.qrTimer invalidate];
    self.qrTimer = nil;
}

- (void)refreshQrLink {
    if (self.currentStep != TGLoginStepQrCode) {
        [self stopQrRefresh];
        return;
    }

    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] qrCodeLoginLinkWithCompletion:^(NSString *link) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || me.currentStep != TGLoginStepQrCode)
            return;
        if (link.length > 0)
            [me applyQrLink:link];
    }];
}

- (void)extraTapped {
    if (self.busy)
        return;

    __weak TGLoginViewController *weakSelf = self;

    if (self.currentStep == TGLoginStepQrCode) {
        [self stopQrRefresh];
        [self showPhoneStep];
        return;
    }

    if (self.currentStep == TGLoginStepCode) {
        [[TGClient shared] reportAuthenticationCodeMissing:nil completion:^(BOOL ok) {
            TGLoginViewController *me = weakSelf;
            if (me == nil)
                return;
            [me showLoginAlert:ok ? @"Telegram has been told the code did not arrive. Please wait a little longer."
                                  : @"Could not report the missing code."];
        }];
        return;
    }

    if (self.currentStep == TGLoginStepPassword) {
        [self setBusy:YES];
        [[TGClient shared] requestAuthenticationPasswordRecoveryWithCompletion:^(BOOL ok) {
            TGLoginViewController *me = weakSelf;
            if (me == nil)
                return;
            [me setBusy:NO];
            if (!ok) {
                [me showPasswordResetOptions];
                return;
            }
            [me showRecoveryCodeStep];
        }];
    }
}

- (void)showPasswordResetOptions {
    [self.inputField resignFirstResponder];

    NSArray *actions = @[ [[TGActionSheetAction alloc] initWithTitle:@"Reset Password" action:@"reset" type:TGActionSheetActionTypeDestructive],
                          [[TGActionSheetAction alloc] initWithTitle:@"Delete Account" action:@"delete" type:TGActionSheetActionTypeDestructive],
                          [[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel" type:TGActionSheetActionTypeCancel] ];

    __weak TGLoginViewController *weakSelf = self;
    TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:@"No recovery email is attached to this password. You can reset the password after a waiting period, or delete the account."
                                                        actions:actions
                                                    actionBlock:^(__unused id target, NSString *action) {
        TGLoginViewController *me = weakSelf;
        if (me == nil)
            return;
        if ([action isEqualToString:@"reset"])
            [me requestPasswordReset];
        else if ([action isEqualToString:@"delete"])
            [me confirmAccountDeletion];
        else
            [me.inputField becomeFirstResponder];
    } target:self];
    self.currentActionSheet = sheet;
    [sheet showInView:self.view];
}

- (void)requestPasswordReset {
    if (self.busy)
        return;

    [self setBusy:YES];
    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] resetPasswordWithCompletion:^(NSString *result, NSInteger date) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || me.currentStep != TGLoginStepPassword)
            return;
        [me setBusy:NO];
        [me applyPasswordResetResult:result date:date];
    }];
}

- (void)applyPasswordResetResult:(NSString *)result date:(NSInteger)date {
    if ([result isEqualToString:@"ok"]) {
        self.passwordResetPending = NO;
        [self stopResendCountdown];
        [self layoutInterface];
        [self showLoginAlert:@"Your password has been reset."];
        return;
    }

    if ([result isEqualToString:@"pending"] || [result isEqualToString:@"declined"]) {
        NSTimeInterval remaining = (NSTimeInterval)date - [[NSDate date] timeIntervalSince1970];
        if (remaining < 0)
            remaining = 0;
        self.passwordResetPending = [result isEqualToString:@"pending"];
        [self stopResendCountdown];
        self.resendSeconds = (NSInteger)remaining;
        if (self.resendSeconds > 0)
            [self startResendTimer];
        if (self.passwordResetPending) {
            [self setLoginButton:self.resendButton title:@"Cancel reset"];
            [self updateResendTitle];
            [self layoutInterface];
        } else {
            [self layoutInterface];
            [self showLoginAlert:@"Telegram has declined this reset. Please try again later."];
        }
        return;
    }

    [self showLoginAlert:@"The password could not be reset. Please try again later."];
}

- (void)confirmAccountDeletion {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Delete Account"
                                                    message:@"All your chats, messages and contacts on Telegram will be lost. This cannot be undone."
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Delete", nil];
    alert.tag = TGLoginAlertDeleteAccount;
    [alert show];
}

- (void)deleteAccountNow {
    [self setBusy:YES];
    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] deleteAccountWithReason:@"Forgot password" password:nil completion:^(BOOL ok) {
        TGLoginViewController *me = weakSelf;
        if (me == nil)
            return;
        [me setBusy:NO];
        if (ok)
            [me showPhoneStep];
        else
            [me showLoginAlert:@"The account could not be deleted. Please try again later."];
    }];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == TGLoginAlertTerms) {
        if (buttonIndex == alertView.cancelButtonIndex) {
            [self logOutAndReturnToPhoneStep];
            return;
        }
        if (self.currentStep == TGLoginStepRegistration)
            [self.inputField becomeFirstResponder];
        return;
    }

    if (alertView.tag == TGLoginAlertDeleteAccount) {
        if (buttonIndex != alertView.cancelButtonIndex)
            [self deleteAccountNow];
        else
            [self.inputField becomeFirstResponder];
    }
}

- (void)installBackButton {
    if (self.backButton != nil) {
        [self.backButton setTitleShadowColor:self.currentStep == TGLoginStepRegistration ? tgRGBA(0x07080a, 0.35f) : tgRGBA(0x050608, 0.4f)
                                    forState:UIControlStateNormal];
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.backButton];
        return;
    }

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
    if (self.currentStep == TGLoginStepRegistration)
        [backButton setTitleShadowColor:tgRGBA(0x07080a, 0.35f) forState:UIControlStateNormal];
    self.backButton = backButton;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:backButton];
}

- (void)backTapped {
    if (self.busy)
        return;

    if (self.currentStep == TGLoginStepEmailCode) {
        [self showEmailStep];
        return;
    }

    if (self.currentStep == TGLoginStepNewPassword) {
        [self showRecoveryCodeStep];
        return;
    }

    if (self.currentStep == TGLoginStepRecoveryCode) {
        [self showPasswordStep];
        return;
    }

    if (self.currentStep == TGLoginStepEmail || self.currentStep == TGLoginStepQrCode) {
        [self showPhoneStep];
        return;
    }

    [self logOutAndReturnToPhoneStep];
}

- (void)logOutAndReturnToPhoneStep {
    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] logOutWithCompletion:^(BOOL ok) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || ok)
            return;
        [me showLoginAlert:@"Could not start over. Please try again."];
    }];
    [self showPhoneStep];
}

- (void)startResendCountdown {
    [self stopResendCountdown];
    self.resendSeconds = 60;
    self.callRequestState = 0;
    self.timeoutLabel.alpha = 1.0f;
    self.requestingCallLabel.alpha = 0.0f;
    self.callSentLabel.alpha = 0.0f;
    [self updateResendTitle];
    [self startResendTimer];
}

- (void)beginCallRequest {
    self.callRequestState = 1;
    self.requestingCallLabel.hidden = NO;
    self.requestingCallLabel.alpha = 0.0f;

    [UIView animateWithDuration:0.2 animations:^{
        self.timeoutLabel.alpha = 0.0f;
    }];
    [UIView animateWithDuration:0.2 delay:0.1 options:0 animations:^{
        self.requestingCallLabel.alpha = 1.0f;
    } completion:nil];

    __weak TGLoginViewController *weakSelf = self;
    [[TGClient shared] resendAuthenticationCodeWithFailureMessage:nil completion:^(NSDictionary *info) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || me.currentStep != TGLoginStepCode)
            return;
        if (info != nil)
            [me applyCodeInfo:info];
        [me finishCallRequest];
    }];
}

- (void)finishCallRequest {
    if (self.currentStep != TGLoginStepCode || self.callRequestState != 1)
        return;

    self.callRequestState = 2;
    self.callSentLabel.hidden = NO;
    self.callSentLabel.alpha = 0.0f;

    [UIView animateWithDuration:0.2 animations:^{
        self.requestingCallLabel.alpha = 0.0f;
    }];
    [UIView animateWithDuration:0.2 delay:0.1 options:0 animations:^{
        self.callSentLabel.alpha = 1.0f;
    } completion:nil];

    [self layoutInterface];
}

- (void)startResendTimer {
    [self.resendTimer invalidate];
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
        if (self.currentStep == TGLoginStepCode && self.callRequestState == 0 && !self.suppressResendButton)
            [self beginCallRequest];
    }
}

- (NSString *)longDurationString:(NSInteger)seconds {
    NSInteger days = seconds / 86400;
    NSInteger hours = (seconds % 86400) / 3600;
    NSInteger minutes = (seconds % 3600) / 60;
    if (days > 0)
        return [NSString stringWithFormat:@"%d days %d hours", (int)days, (int)hours];
    if (hours > 0)
        return [NSString stringWithFormat:@"%d hours %d minutes", (int)hours, (int)minutes];
    return [NSString stringWithFormat:@"%d:%02d", (int)minutes, (int)(seconds % 60)];
}

- (void)updateResendTitle {
    if (self.currentStep == TGLoginStepPassword && self.passwordResetPending) {
        self.timeoutLabel.text = self.resendSeconds > 0
            ? [NSString stringWithFormat:@"You will be able to reset your password in %@", [self longDurationString:self.resendSeconds]]
            : @"You can reset your password now.";
        self.resendButton.enabled = YES;
        [self layoutInterface];
        return;
    }

    if (self.resendSeconds > 0) {
        NSString *format = self.currentStep == TGLoginStepEmailCode
            ? @"You will be able to reset your email address in %d:%02d"
            : @"Telegram will call you in %d:%.2d";
        self.timeoutLabel.text = [NSString stringWithFormat:format,
                                  (int)self.resendSeconds / 60, (int)self.resendSeconds % 60];
        self.resendButton.enabled = NO;
    } else {
        self.resendButton.enabled = YES;
    }
    [self layoutInterface];
}

- (void)resendTapped {
    if (self.busy)
        return;

    __weak TGLoginViewController *weakSelf = self;

    if (self.currentStep == TGLoginStepPassword && self.passwordResetPending) {
        [self setBusy:YES];
        [[TGClient shared] cancelPasswordResetWithCompletion:^(BOOL ok) {
            TGLoginViewController *me = weakSelf;
            if (me == nil)
                return;
            [me setBusy:NO];
            if (!ok) {
                [me showLoginAlert:@"The reset could not be cancelled."];
                return;
            }
            me.passwordResetPending = NO;
            [me stopResendCountdown];
            [me layoutInterface];
            [me.inputField becomeFirstResponder];
        }];
        return;
    }

    if (self.resendSeconds > 0)
        return;

    if (self.currentStep == TGLoginStepEmailCode) {
        [self setBusy:YES];
        [[TGClient shared] resetAuthenticationEmailAddressWithCompletion:^(BOOL ok) {
            TGLoginViewController *me = weakSelf;
            if (me == nil)
                return;
            [me setBusy:NO];
            if (ok)
                [me showEmailStep];
            else
                [me showLoginAlert:@"The email address could not be reset."];
        }];
        return;
    }

    if (self.currentStep != TGLoginStepCode)
        return;

    [[TGClient shared] resendAuthenticationCodeWithFailureMessage:nil completion:^(NSDictionary *info) {
        TGLoginViewController *me = weakSelf;
        if (me == nil || me.currentStep != TGLoginStepCode)
            return;
        if (info != nil)
            [me applyCodeInfo:info];
    }];
    [self startResendCountdown];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (textField == self.countryCodeField) {
        NSString *result = [textField.text stringByReplacingCharactersInRange:range withString:string];
        return [self digitsOnly:result].length <= 4;
    }

    if (self.currentStep == TGLoginStepRegistration) {
        NSString *result = [textField.text stringByReplacingCharactersInRange:range withString:string];
        return result.length <= 30;
    }

    if (self.currentStep == TGLoginStepCode) {
        NSString *result = [textField.text stringByReplacingCharactersInRange:range withString:string];
        if (self.codeIsText)
            return result.length <= 64;
        return [self digitsOnly:result].length <= 5 && [[self digitsOnly:string] length] == string.length;
    }

    if (self.currentStep == TGLoginStepEmailCode || self.currentStep == TGLoginStepRecoveryCode) {
        NSString *result = [textField.text stringByReplacingCharactersInRange:range withString:string];
        return result.length <= 12;
    }

    if (self.currentStep == TGLoginStepPhone) {
        [self applyPhoneFormattingInField:textField range:range replacement:string];
        return NO;
    }

    return YES;
}

- (void)applyPhoneFormattingInField:(UITextField *)textField range:(NSRange)range replacement:(NSString *)string {
    NSString *result = [textField.text stringByReplacingCharactersInRange:range withString:string];
    NSString *digits = [self digitsOnly:result];
    if (digits.length > 15)
        return;

    NSString *prefix = [textField.text substringToIndex:range.location];
    NSUInteger digitsBeforeCaret = [self digitsOnly:prefix].length + [self digitsOnly:string].length;

    NSString *formatted = [self formattedPhoneForDigits:digits];
    textField.text = formatted;

    NSUInteger caret = formatted.length;
    NSUInteger seen = 0;
    for (NSUInteger i = 0; i < formatted.length; i++) {
        if (seen == digitsBeforeCaret) {
            caret = i;
            break;
        }
        unichar c = [formatted characterAtIndex:i];
        if (c >= '0' && c <= '9')
            seen++;
    }
    if (seen == digitsBeforeCaret && caret == formatted.length)
        caret = formatted.length;

    UITextPosition *position = [textField positionFromPosition:textField.beginningOfDocument offset:(NSInteger)caret];
    if (position != nil)
        textField.selectedTextRange = [textField textRangeFromPosition:position toPosition:position];

    [self updateTitleText];
    [self inputChanged];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.countryCodeField) {
        [self.inputField becomeFirstResponder];
        return NO;
    }
    if (self.currentStep == TGLoginStepRegistration && textField == self.inputField) {
        [self.lastNameField becomeFirstResponder];
        return NO;
    }
    [self actionButtonTapped];
    return YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.currentStep == TGLoginStepQrCode)
        return;
    if (!self.busy && ![self.inputField isFirstResponder] && ![self.countryCodeField isFirstResponder])
        [self.inputField becomeFirstResponder];
}

- (void)dealloc {
    [_resendTimer invalidate];
    _resendTimer = nil;
    [_qrTimer invalidate];
    _qrTimer = nil;
    [_authPollTimer invalidate];
    _authPollTimer = nil;
    _currentActionSheet.delegate = nil;
    _lastNameField.delegate = nil;
    _inputField.delegate = nil;
    _countryCodeField.delegate = nil;
}

@end

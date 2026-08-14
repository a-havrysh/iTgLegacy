#import "TGNewContactViewController.h"
#import "TGCountryPickerViewController.h"
#import "TGQRViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <AddressBook/AddressBook.h>

@interface TGNewContactFieldCell : UITableViewCell
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UILabel *prefixLabel;
@property (nonatomic, strong) UIView *verticalSeparator;
@end

@implementation TGNewContactFieldCell

- (id)initWithReuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;
	self.selectionStyle = UITableViewCellSelectionStyleNone;
	self.prefixLabel = [[UILabel alloc] init];
	self.prefixLabel.font = [UIFont boldSystemFontOfSize:13];
	self.prefixLabel.textAlignment = NSTextAlignmentRight;
	self.prefixLabel.textColor = [UIColor colorWithRed:0x5d / 255.0f green:0x70 / 255.0f blue:0x8f / 255.0f alpha:1.0f];
	self.prefixLabel.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:self.prefixLabel];
	self.verticalSeparator = [[UIView alloc] initWithFrame:CGRectZero];
	self.verticalSeparator.backgroundColor = [[TGTheme shared] separatorColour];
	self.verticalSeparator.hidden = YES;
	[self.contentView addSubview:self.verticalSeparator];
	return self;
}

- (void)setField:(UITextField *)field {
	if (_field == field)
		return;
	if (_field.superview == self.contentView)
		[_field removeFromSuperview];
	_field = field;
	if (field)
		[self.contentView addSubview:field];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.prefixLabel.text = nil;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect bounds = self.contentView.bounds;
	if (self.prefixLabel.text.length){
		self.prefixLabel.hidden = NO;
		self.verticalSeparator.hidden = NO;
		self.prefixLabel.frame = CGRectMake(4, 13, 62, 16);
		self.verticalSeparator.frame = CGRectMake(72, 0, 1.0f, bounds.size.height);
		self.field.font = [UIFont boldSystemFontOfSize:15];
		self.field.frame = CGRectMake(78, 11, bounds.size.width - 80, 20);
	} else {
		self.prefixLabel.hidden = YES;
		self.verticalSeparator.hidden = YES;
		self.field.font = [UIFont boldSystemFontOfSize:16];
		self.field.frame = CGRectMake(15, 12, bounds.size.width - 20, 22);
	}
}

@end

@interface TGNewContactViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *firstNameField;
@property (nonatomic, strong) UITextField *lastNameField;
@property (nonatomic, strong) UITextField *phoneField;
@property (nonatomic, strong) NSString *countryName;
@property (nonatomic, strong) NSString *countryFlag;
@property (nonatomic, strong) NSString *countryDialCode;
@property (nonatomic, strong) UISwitch *syncSwitch;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, assign) BOOL saving;
@end

@implementation TGNewContactViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (!self)
		return nil;
	self.countryName = @"United States";
	self.countryFlag = @"🇺🇸";
	self.countryDialCode = @"+1";
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.title = @"New Contact";
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.rowHeight = 44.0f;

	UIButton *cancel = [TGIcons headerButtonWithTitle:@"Cancel" bold:NO
												target:self action:@selector(cancelTapped)];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:cancel];

	self.doneButton = [TGIcons headerButtonWithTitle:@"Done" bold:YES
											  target:self action:@selector(doneTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.doneButton];

	self.firstNameField = [self makeFieldWithPlaceholder:@"First" font:[UIFont boldSystemFontOfSize:16]];
	self.firstNameField.returnKeyType = UIReturnKeyNext;
	self.lastNameField  = [self makeFieldWithPlaceholder:@"Last" font:[UIFont boldSystemFontOfSize:16]];
	self.lastNameField.returnKeyType = UIReturnKeyNext;
	self.phoneField = [self makeFieldWithPlaceholder:@"Phone" font:[UIFont boldSystemFontOfSize:15]];
	self.phoneField.keyboardType = UIKeyboardTypePhonePad;

	self.syncSwitch = [[UISwitch alloc] init];
	self.syncSwitch.on = YES;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textChanged:)
												 name:UITextFieldTextDidChangeNotification object:nil];
	[self updateDoneEnabled];

	[self.firstNameField becomeFirstResponder];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	self.firstNameField.delegate = nil;
	self.lastNameField.delegate = nil;
	self.phoneField.delegate = nil;
}

- (void)textChanged:(NSNotification *)note {
	id object = note.object;
	if (object == self.firstNameField || object == self.lastNameField || object == self.phoneField)
		[self updateDoneEnabled];
}

- (NSString *)trimmed:(NSString *)text {
	if (!text.length)
		return @"";
	return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)digitsOf:(NSString *)text {
	if (!text.length)
		return @"";
	NSMutableString *digits = [NSMutableString stringWithCapacity:text.length];
	for (NSUInteger i = 0; i < text.length; i++){
		unichar c = [text characterAtIndex:i];
		if (c >= '0' && c <= '9')
			[digits appendFormat:@"%C", c];
	}
	return digits;
}

- (NSString *)composedPhone {
	NSString *typed = [self digitsOf:self.phoneField.text];
	if (!typed.length)
		return @"";
	NSString *dial = [self digitsOf:self.countryDialCode];
	NSString *raw = [self trimmed:self.phoneField.text];
	if ([raw hasPrefix:@"+"])
		return typed;
	if (dial.length && [typed hasPrefix:@"00"])
		return [typed substringFromIndex:2];
	if (dial.length && [typed hasPrefix:dial] && typed.length > dial.length + 4)
		return typed;
	return [dial stringByAppendingString:typed];
}

- (BOOL)isFormValid {
	if (![self trimmed:self.firstNameField.text].length)
		return NO;
	return [self composedPhone].length >= 5;
}

- (void)updateDoneEnabled {
	BOOL enabled = !self.saving && [self isFormValid];
	self.doneButton.enabled = enabled;
	self.doneButton.alpha = enabled ? 1.0f : 0.5f;
}

- (void)showAlertWithMessage:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New Contact"
													message:message
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

- (UITextField *)makeFieldWithPlaceholder:(NSString *)placeholder font:(UIFont *)font {
	UITextField *field = [[UITextField alloc] init];
	field.placeholder = placeholder;
	field.font = font;
	if ([field respondsToSelector:@selector(setAttributedPlaceholder:)]){
		UIColor *placeholderColour = [UIColor colorWithRed:0xb3 / 255.0f green:0xb3 / 255.0f blue:0xb3 / 255.0f alpha:1.0f];
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
									placeholderColour, NSForegroundColorAttributeName,
									font, NSFontAttributeName, nil];
		field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:attributes];
	}
	field.textColor = [[TGTheme shared] primaryTextColour];
	field.backgroundColor = [UIColor clearColor];
	field.contentMode = UIViewContentModeLeft;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.delegate = self;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	return field;
}

- (void)closeSelf {
	[self.view endEditing:YES];
	if (self.navigationController.viewControllers.count > 1)
		[self.navigationController popViewControllerAnimated:YES];
	else
		[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancelTapped {
	[self closeSelf];
}

- (void)doneTapped {
	if (self.saving)
		return;

	NSString *first = [self trimmed:self.firstNameField.text];
	NSString *last  = [self trimmed:self.lastNameField.text];
	NSString *fullPhone = [self composedPhone];

	if (!first.length){
		[self.firstNameField becomeFirstResponder];
		[self showAlertWithMessage:@"Please enter a first name."];
		return;
	}
	if (fullPhone.length < 5){
		[self.phoneField becomeFirstResponder];
		[self showAlertWithMessage:@"Please enter a valid phone number."];
		return;
	}

	BOOL sync = self.syncSwitch.on;
	self.saving = YES;
	[self updateDoneEnabled];
	[self.view endEditing:YES];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] addContactWithPhone:fullPhone firstName:first lastName:last
								 completion:^(BOOL ok){
		dispatch_block_t finish = ^{
		TGNewContactViewController *me = weakSelf;
		if (!me)
			return;
		me.saving = NO;
		[me updateDoneEnabled];
		if (!ok){
			[me showAlertWithMessage:@"The contact could not be added. Please check the phone number and your connection."];
			return;
		}
		if (sync)
			[me saveToAddressBookFirst:first last:last phone:fullPhone];
		if (me.onDone)
			me.onDone();
		[me closeSelf];
		};
		if ([NSThread isMainThread])
			finish();
		else
			dispatch_async(dispatch_get_main_queue(), finish);
	}];
}

- (void)saveToAddressBookFirst:(NSString *)first last:(NSString *)last phone:(NSString *)phone {
	ABAddressBookRef book = ABAddressBookCreateWithOptions(NULL, NULL);
	if (!book)
		return;
	ABAddressBookRequestAccessWithCompletion(book, ^(bool granted, CFErrorRef error){
		if (!granted){
			CFRelease(book);
			return;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			ABRecordRef person = ABPersonCreate();
			ABRecordSetValue(person, kABPersonFirstNameProperty, (__bridge CFStringRef)first, NULL);
			if (last.length)
				ABRecordSetValue(person, kABPersonLastNameProperty, (__bridge CFStringRef)last, NULL);

			ABMutableMultiValueRef phones = ABMultiValueCreateMutable(kABMultiStringPropertyType);
			ABMultiValueAddValueAndLabel(phones, (__bridge CFStringRef)phone, kABPersonPhoneMobileLabel, NULL);
			ABRecordSetValue(person, kABPersonPhoneProperty, phones, NULL);
			CFRelease(phones);

			ABAddressBookAddRecord(book, person, NULL);
			ABAddressBookSave(book, NULL);
			CFRelease(person);
			CFRelease(book);
		});
	});
}

- (void)countryTapped {
	[self.view endEditing:YES];
	TGCountryPickerViewController *picker = [[TGCountryPickerViewController alloc] init];
	__weak typeof(self) weakSelf = self;
	picker.onPick = ^(NSString *name, NSString *flag, NSString *dialCode){
		TGNewContactViewController *me = weakSelf;
		if (!me)
			return;
		if (name.length)
			me.countryName = name;
		me.countryFlag = flag.length ? flag : @"";
		if (dialCode.length)
			me.countryDialCode = dialCode;
		[me.tableView reloadData];
		[me updateDoneEnabled];
		[me.phoneField becomeFirstResponder];
	};
	[self.navigationController pushViewController:picker animated:YES];
}

- (void)qrTapped {
	[self.view endEditing:YES];
	TGQRViewController *scanner = [[TGQRViewController alloc] init];
	[self.navigationController pushViewController:scanner animated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	if (textField == self.firstNameField)
		[self.lastNameField becomeFirstResponder];
	else if (textField == self.lastNameField)
		[self.phoneField becomeFirstResponder];
	else {
		[textField resignFirstResponder];
		if ([self isFormValid])
			[self doneTapped];
	}
	return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
	if (textField != self.phoneField || !string.length)
		return YES;
	for (NSUInteger i = 0; i < string.length; i++){
		unichar c = [string characterAtIndex:i];
		if (!(c >= '0' && c <= '9') && c != '+' && c != ' ' && c != '-' && c != '(' && c != ')')
			return NO;
	}
	return YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return 2;
	if (section == 1)
		return 2;
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 1)
		return @"The contact's country and phone number.";
	if (section == 2)
		return @"Adds this contact to your phone's address book too.";
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0){
		NSString *reuse = (indexPath.row == 0) ? @"TGNewContactFirst" : @"TGNewContactLast";
		TGNewContactFieldCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
		if (!cell)
			cell = [[TGNewContactFieldCell alloc] initWithReuseIdentifier:reuse];
		cell.prefixLabel.text = nil;
		cell.field = (indexPath.row == 0) ? self.firstNameField : self.lastNameField;
		[[TGTheme shared] styleCell:cell];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		[cell setNeedsLayout];
		[cell layoutIfNeeded];
		return cell;
	}

	if (indexPath.section == 1 && indexPath.row == 0){
		static NSString *reuse = @"TGCountryRow";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuse];
		cell.textLabel.text = @"Country";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", self.countryFlag, self.countryName];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		[[TGTheme shared] styleCell:cell];
		return cell;
	}

	if (indexPath.section == 1 && indexPath.row == 1){
		static NSString *reuse = @"TGNewContactPhone";
		TGNewContactFieldCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
		if (!cell)
			cell = [[TGNewContactFieldCell alloc] initWithReuseIdentifier:reuse];
		cell.prefixLabel.text = self.countryDialCode.length ? self.countryDialCode : @"+";
		cell.field = self.phoneField;
		[[TGTheme shared] styleCell:cell];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		[cell setNeedsLayout];
		[cell layoutIfNeeded];
		return cell;
	}

	if (indexPath.section == 2){
		static NSString *reuse = @"TGSyncRow";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
		cell.textLabel.text = @"Sync Contact to Phone";
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.accessoryView = self.syncSwitch;
		[[TGTheme shared] styleCell:cell];
		return cell;
	}

	static NSString *reuse = @"TGQRRow";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
	cell.textLabel.text = @"Add via QR Code";
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.textLabel.textColor = [[TGTheme shared] accentColour];
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	[[TGTheme shared] styleCell:cell];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 1 && indexPath.row == 0)
		[self countryTapped];
	else if (indexPath.section == 3)
		[self qrTapped];
}

@end

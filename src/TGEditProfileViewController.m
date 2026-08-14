#import "TGEditProfileViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"

static inline UIColor *TGEditProfileRGB(int rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:1.0f];
}

@interface TGEditProfileViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *firstField;
@property (nonatomic, strong) UITextField *lastField;
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UITextField *bioField;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, copy) NSString *loadedBio;
@property (nonatomic, assign) BOOL saving;
@end

@implementation TGEditProfileViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Edit Profile";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.rowHeight = 44;

	self.saveButton = [TGIcons headerButtonWithTitle:@"Save" bold:YES
											  target:self action:@selector(save)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:self.saveButton];

	NSDictionary *me = [TGClient shared].me;
	if (![me isKindOfClass:NSDictionary.class]) me = @{};

	self.firstField    = [self fieldWithPlaceholder:@"First name" text:me[@"first_name"]];
	self.firstField.returnKeyType = UIReturnKeyNext;
	self.lastField     = [self fieldWithPlaceholder:@"Last name"  text:me[@"last_name"]];
	self.lastField.returnKeyType = UIReturnKeyNext;
	self.usernameField = [self fieldWithPlaceholder:@"username"   text:me[@"username"]];
	self.usernameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.usernameField.autocorrectionType = UITextAutocorrectionTypeNo;
	self.usernameField.returnKeyType = UIReturnKeyNext;
	self.bioField      = [self fieldWithPlaceholder:@"A few words about you" text:nil];
	self.loadedBio     = @"";

	[self updateSaveEnabled];

	// getUserFullInfo carries the bio; `me` does not.
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] request:@{
		@"@type"   : @"getUserFullInfo",
		@"user_id" : me[@"id"] ?: @0,
	} completion:^(NSDictionary *full){
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			NSString *bio = [strongSelf stringFromBio:[full isKindOfClass:NSDictionary.class]
					? full[@"bio"] : nil];
			strongSelf.loadedBio = bio;
			if (!strongSelf.bioField.isFirstResponder)
				strongSelf.bioField.text = bio;
		});
	}];
}

- (NSString *)stringFromBio:(id)bio {
	if ([bio isKindOfClass:NSString.class]) return bio;
	if ([bio isKindOfClass:NSDictionary.class]){
		id text = ((NSDictionary *)bio)[@"text"];
		if ([text isKindOfClass:NSString.class]) return text;
	}
	return @"";
}

- (NSString *)trimmed:(NSString *)text {
	if (![text isKindOfClass:NSString.class]) return @"";
	return [text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)updateSaveEnabled {
	BOOL enabled = !self.saving && [self trimmed:self.firstField.text].length > 0;
	self.saveButton.enabled = enabled;
	self.saveButton.alpha = enabled ? 1.0f : 0.5f;
}

- (void)fieldChanged {
	[self updateSaveEnabled];
}

- (NSString *)problemWithUsername:(NSString *)username {
	if (username.length < 5) return @"A username must be at least 5 characters long.";
	if (username.length > 32) return @"A username must be at most 32 characters long.";
	unichar first = [username characterAtIndex:0];
	if (!((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z')))
		return @"A username must begin with a letter.";
	for (NSUInteger i = 0; i < username.length; i++){
		unichar c = [username characterAtIndex:i];
		BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
				|| (c >= '0' && c <= '9') || c == '_';
		if (!ok) return @"A username may only contain letters, digits and underscores.";
	}
	return nil;
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
			message:message delegate:nil
	  cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text {
	UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(15, 12, 290, 22)];
	field.placeholder = placeholder;
	field.text = [text isKindOfClass:NSString.class] ? text : @"";
	field.font = [UIFont boldSystemFontOfSize:16];
	field.contentMode = UIViewContentModeLeft;
	field.backgroundColor = [UIColor clearColor];
	field.keyboardType = UIKeyboardTypeDefault;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	field.delegate = self;
	field.returnKeyType = UIReturnKeyDone;
	field.textColor = [[TGTheme shared] primaryTextColour];
	[field addTarget:self action:@selector(fieldChanged)
	 forControlEvents:UIControlEventEditingChanged];
	return field;
}

- (void)save {
	if (self.saving) return;
	[self.view endEditing:YES];

	NSString *first = [self trimmed:self.firstField.text];
	NSString *last  = [self trimmed:self.lastField.text];
	if (first.length == 0){
		[self showMessage:@"Please enter your first name." title:@"Name"];
		[self.firstField becomeFirstResponder];
		return;
	}

	NSString *username = [[self trimmed:self.usernameField.text]
			stringByReplacingOccurrencesOfString:@"@" withString:@""];
	NSDictionary *me = [TGClient shared].me;
	if (![me isKindOfClass:NSDictionary.class]) me = @{};
	NSString *currentFirst = [self trimmed:me[@"first_name"]];
	NSString *currentLast  = [self trimmed:me[@"last_name"]];
	NSString *currentUsername = [me[@"username"] isKindOfClass:NSString.class]
			? me[@"username"] : @"";
	BOOL usernameChanged = ![username isEqualToString:currentUsername];

	if (usernameChanged && username.length > 0){
		NSString *problem = [self problemWithUsername:username];
		if (problem){
			[self showMessage:problem title:@"Username"];
			[self.usernameField becomeFirstResponder];
			return;
		}
	}

	if (![first isEqualToString:currentFirst] || ![last isEqualToString:currentLast])
		[[TGClient shared] setName:first last:last];

	NSString *bio = [self trimmed:self.bioField.text];
	if (![bio isEqualToString:self.loadedBio ?: @""]){
		[[TGClient shared] setBio:bio];
		self.loadedBio = bio;
	}

	if (!usernameChanged){
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}

	// A username can be taken, which is the one failure worth reporting.
	self.saving = YES;
	[self updateSaveEnabled];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setUsername:username completion:^(BOOL ok){
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.saving = NO;
			[strongSelf updateSaveEnabled];
			if (ok){
				[strongSelf.navigationController popViewControllerAnimated:YES];
			} else {
				[strongSelf showMessage:@"That username is not available."
								  title:@"Username"];
				[strongSelf.usernameField becomeFirstResponder];
			}
		});
	}];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
	if (field == self.firstField){
		[self.lastField becomeFirstResponder];
		return NO;
	}
	if (field == self.lastField){
		[self.usernameField becomeFirstResponder];
		return NO;
	}
	if (field == self.usernameField){
		[self.bioField becomeFirstResponder];
		return NO;
	}
	[field resignFirstResponder];
	return NO;
}

- (BOOL)textField:(UITextField *)field
		shouldChangeCharactersInRange:(NSRange)range
					replacementString:(NSString *)string {
	NSUInteger limit = 64;
	if (field == self.usernameField) limit = 32;
	else if (field == self.bioField) limit = 70;

	NSString *current = field.text ?: @"";
	if (range.location > current.length) return NO;
	if (NSMaxRange(range) > current.length) return NO;
	NSUInteger length = current.length - range.length + string.length;
	if (length > limit && string.length > 0) return NO;

	if (field == self.usernameField && string.length > 0){
		for (NSUInteger i = 0; i < string.length; i++){
			unichar c = [string characterAtIndex:i];
			BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
					|| (c >= '0' && c <= '9') || c == '_';
			if (!ok) return NO;
		}
	}
	return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)field {
	[self updateSaveEnabled];
}

/// Settings has its own navigation controller, and nothing was styling
/// its bar - an imported theme stopped at the top of the screen.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return 12;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	UIView *spacer = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, 12)];
	spacer.backgroundColor = [UIColor clearColor];
	return spacer;
}

- (NSString *)footerTextForSection:(NSInteger)section {
	if (section == 1)
		return @"You can choose a username on Telegram. Other people will be able to "
				"find you by this username and contact you without knowing your phone "
				"number.\n\nYou can use a-z, 0-9 and underscores. Minimum length is 5 "
				"characters.";
	if (section == 2)
		return @"Any details such as age, occupation or city.";
	return nil;
}

- (CGFloat)footerTextHeightForSection:(NSInteger)section width:(CGFloat)width {
	NSString *text = [self footerTextForSection:section];
	if (text.length == 0)
		return 0;
	CGSize bounded = [text sizeWithFont:[UIFont systemFontOfSize:14]
					 constrainedToSize:CGSizeMake(width - 20, 400)
						 lineBreakMode:NSLineBreakByWordWrapping];
	return ceilf(bounded.height);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	CGFloat height = [self footerTextHeightForSection:section
											   width:tableView.bounds.size.width];
	if (height <= 0)
		return 12;
	return height + 14 + 12;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	NSString *text = [self footerTextForSection:section];
	if (text.length == 0)
		return nil;
	CGFloat width = tableView.bounds.size.width;
	CGFloat height = [self footerTextHeightForSection:section width:width];
	BOOL dark = [[TGTheme shared] isDark];

	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, height + 14 + 12)];
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(10, 7, width - 20, height)];
	label.text = text;
	label.font = [UIFont systemFontOfSize:14];
	label.textAlignment = NSTextAlignmentCenter;
	label.lineBreakMode = NSLineBreakByWordWrapping;
	label.numberOfLines = 0;
	label.backgroundColor = [UIColor clearColor];
	label.textColor = dark ? [[TGTheme shared] secondaryTextColour]
						   : TGEditProfileRGB(0x697487);
	if (!dark){
		label.shadowColor = TGEditProfileRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[container addSubview:label];
	return container;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 2 : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
												  reuseIdentifier:nil];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UITextField *field = nil;
	if (indexPath.section == 0)      field = indexPath.row == 0 ? self.firstField : self.lastField;
	else if (indexPath.section == 1) field = self.usernameField;
	else                             field = self.bioField;

	CGFloat contentWidth = tableView.bounds.size.width - 20;
	field.frame = CGRectMake(15, 12, contentWidth - 20, 22);
	[cell.contentView addSubview:field];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:NO];
	if (indexPath.section == 0)
		[(indexPath.row == 0 ? self.firstField : self.lastField) becomeFirstResponder];
	else if (indexPath.section == 1)
		[self.usernameField becomeFirstResponder];
	else
		[self.bioField becomeFirstResponder];
}

@end

// vim:ft=objc

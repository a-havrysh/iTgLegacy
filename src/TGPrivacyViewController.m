#import "TGPrivacyViewController.h"
#import "TGClient.h"
#import "TGClient+Privacy.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGSessionsViewController.h"
#import <CommonCrypto/CommonDigest.h>

#define TGPrivacyRGB(rgb) [UIColor colorWithRed:(((rgb) >> 16) & 0xff) / 255.0f \
									      green:(((rgb) >> 8) & 0xff) / 255.0f \
										   blue:((rgb) & 0xff) / 255.0f alpha:1.0f]

static NSString *const TGPasscodeDigestKey = @"TGPasscodeDigest";
static NSString *const TGPasscodeAutoLockKey = @"TGPasscodeAutoLockSeconds";

static UIColor *TGPrivacyRowTitleColour(void) {
	if ([[TGTheme shared] isDark])
		return [[TGTheme shared] primaryTextColour];
	return TGPrivacyRGB(0x516691);
}

static UIColor *TGPrivacyActionColour(void) {
	if ([[TGTheme shared] isFlat])
		return [[TGTheme shared] accentColour];
	return TGPrivacyRGB(0x0779d0);
}

static UIColor *TGPrivacyDestructiveColour(void) {
	return TGPrivacyRGB(0xc4362f);
}

static void TGPrivacyComplain(NSString *message) {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:message
												   delegate:nil cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

@class TGSecurityStepViewController;

typedef void (^TGSecurityStepBlock)(TGSecurityStepViewController *step, NSString *text);

@interface TGSecurityStepViewController : UITableViewController <UITextFieldDelegate>
@property (nonatomic, strong) NSString *stepTitle;
@property (nonatomic, strong) NSString *stepCaption;
@property (nonatomic, strong) NSString *footerText;
@property (nonatomic, strong) NSString *placeholder;
@property (nonatomic, strong) NSString *actionTitle;
@property (nonatomic, strong) NSString *skipTitle;
@property (nonatomic, assign) BOOL secure;
@property (nonatomic, assign) BOOL numeric;
@property (nonatomic, assign) BOOL email;
@property (nonatomic, copy) TGSecurityStepBlock onSubmit;
@property (nonatomic, copy) dispatch_block_t onSkip;
- (NSString *)text;
- (void)setBusy:(BOOL)busy;
- (void)refuseWithMessage:(NSString *)message;
@end

@interface TGSecurityStepViewController ()
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, assign) BOOL busy;
@end

@implementation TGSecurityStepViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		_actionTitle = @"Next";
		_secure = YES;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.stepTitle;
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.rowHeight = 44;
	self.tableView.scrollEnabled = NO;

	self.field = [[UITextField alloc] initWithFrame:CGRectMake(15, 11, 290, 22)];
	self.field.placeholder = self.placeholder;
	self.field.font = [UIFont boldSystemFontOfSize:16];
	self.field.backgroundColor = [UIColor clearColor];
	self.field.textColor = [[TGTheme shared] primaryTextColour];
	self.field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.field.secureTextEntry = self.secure;
	self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.field.autocorrectionType = UITextAutocorrectionTypeNo;
	self.field.returnKeyType = UIReturnKeyDone;
	self.field.delegate = self;
	if (self.numeric)
		self.field.keyboardType = UIKeyboardTypeNumberPad;
	else if (self.email)
		self.field.keyboardType = UIKeyboardTypeEmailAddress;

	[self installActionButton];
}

- (void)installActionButton {
	UIButton *button = [TGIcons headerButtonWithTitle:self.actionTitle bold:YES
											   target:self action:@selector(submit)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:button];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self.field becomeFirstResponder];
}

- (NSString *)text {
	NSString *text = self.field.text ?: @"";
	if (self.secure)
		return text;
	return [text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)setBusy:(BOOL)busy {
	_busy = busy;
	if (busy){
		UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
				initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
		[spinner startAnimating];
		self.navigationItem.rightBarButtonItem =
				[[UIBarButtonItem alloc] initWithCustomView:spinner];
		[self.field resignFirstResponder];
		self.field.enabled = NO;
	} else {
		[self installActionButton];
		self.field.enabled = YES;
		[self.field becomeFirstResponder];
	}
}

- (void)refuseWithMessage:(NSString *)message {
	[self setBusy:NO];
	TGPrivacyComplain(message);
}

- (void)submit {
	if (self.busy)
		return;
	if (self.onSubmit)
		self.onSubmit(self, [self text]);
}

- (void)skip {
	if (self.busy)
		return;
	if (self.onSkip)
		self.onSkip();
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
	[self submit];
	return NO;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.skipTitle.length ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0)
		return self.stepCaption;
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0)
		return self.footerText;
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 1){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"skip"];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:@"skip"];
		[[TGTheme shared] styleCell:cell];
		cell.textLabel.text = self.skipTitle;
		cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.textLabel.textColor = TGPrivacyActionColour();
		cell.textLabel.highlightedTextColor = [UIColor whiteColor];
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"field"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"field"];
		[cell.contentView addSubview:self.field];
	}
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	self.field.frame = CGRectMake(15, 11, tableView.bounds.size.width - 50, 22);
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 1)
		[self skip];
}

@end

#pragma mark - two-step verification

@interface TGTwoStepViewController ()
@property (nonatomic, strong) NSDictionary *state;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, strong, getter=pendingPassword) NSString *newPassword;
@property (nonatomic, strong) NSString *pendingHint;
@property (nonatomic, strong) NSString *pendingOldPassword;
@end

@implementation TGTwoStepViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Two-Step Verification";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.rowHeight = 44;
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] passwordStateWithCompletion:^(NSDictionary *state){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		if ([state isKindOfClass:[NSDictionary class]])
			strongSelf.state = state;
		[strongSelf.tableView reloadData];
	}];
}

- (BOOL)hasPassword {
	return [self.state[@"hasPassword"] boolValue];
}

- (NSString *)hint {
	id hint = self.state[@"hint"];
	return [hint isKindOfClass:[NSString class]] ? hint : @"";
}

- (NSString *)pendingEmailPattern {
	id pattern = self.state[@"recoveryEmailPattern"];
	if ([pattern isKindOfClass:[NSString class]] && [pattern length])
		return pattern;
	return nil;
}

- (BOOL)hasRecoveryEmail {
	return [self.state[@"hasRecoveryEmail"] boolValue];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	if (!self.loaded)
		return 1;
	return [self hasPassword] ? 3 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (!self.loaded)
		return 0;
	if (![self hasPassword])
		return 1;
	if (section == 0)
		return [self hint].length ? 2 : 1;
	if (section == 1)
		return 2;
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (!self.loaded)
		return @"Loading...";
	if (![self hasPassword])
		return @"You can set a password that will be required when you log in "
			   @"on a new device, on top of the code you get by text message.";
	if (section == 0){
		NSString *pending = [self pendingEmailPattern];
		if (pending)
			return [NSString stringWithFormat:
					@"Please check your e-mail at %@ and enter the code we sent you.",
					pending];
		if (![self hasRecoveryEmail])
			return @"Without a recovery e-mail address there is no way back into "
				   @"this account if you forget the password.";
		return nil;
	}
	if (section == 2)
		return @"Turning the password off leaves only the text message code "
			   @"protecting this account.";
	return nil;
}

- (UITableViewCell *)plainCellFor:(UITableView *)tableView identifier:(NSString *)identifier {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:identifier];
	[[TGTheme shared] styleCell:cell];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = TGPrivacyRowTitleColour();
	cell.detailTextLabel.text = @"";
	cell.detailTextLabel.font = [UIFont systemFontOfSize:17];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [self plainCellFor:tableView identifier:@"row"];

	if (![self hasPassword]){
		cell.textLabel.text = @"Set Additional Password";
		cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.textLabel.textColor = TGPrivacyActionColour();
		cell.textLabel.highlightedTextColor = [UIColor whiteColor];
		return cell;
	}

	if (indexPath.section == 0){
		if (indexPath.row == 0){
			cell.textLabel.text = @"Password";
			NSString *pending = [self pendingEmailPattern];
			if (pending){
				cell.detailTextLabel.text = @"e-mail unconfirmed";
				cell.detailTextLabel.textColor = TGPrivacyDestructiveColour();
			} else {
				cell.detailTextLabel.text = @"On";
			}
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			return cell;
		}
		cell.textLabel.text = @"Hint";
		cell.detailTextLabel.text = [self hint];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	if (indexPath.section == 1){
		if (indexPath.row == 0){
			cell.textLabel.text = @"Change Password";
		} else {
			NSString *pending = [self pendingEmailPattern];
			if (pending)
				cell.textLabel.text = @"Enter E-Mail Code";
			else
				cell.textLabel.text = [self hasRecoveryEmail]
						? @"Change Recovery E-Mail" : @"Set Recovery E-Mail";
		}
		cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.textLabel.textColor = TGPrivacyActionColour();
		cell.textLabel.highlightedTextColor = [UIColor whiteColor];
		return cell;
	}

	cell.textLabel.text = @"Turn Password Off";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.textLabel.textColor = TGPrivacyDestructiveColour();
	cell.textLabel.highlightedTextColor = [UIColor whiteColor];
	return cell;
}

- (TGSecurityStepViewController *)stepWithTitle:(NSString *)title
										caption:(NSString *)caption
									placeholder:(NSString *)placeholder
										 footer:(NSString *)footer {
	TGSecurityStepViewController *step = [[TGSecurityStepViewController alloc] init];
	step.stepTitle = title;
	step.stepCaption = caption;
	step.placeholder = placeholder;
	step.footerText = footer;
	return step;
}

- (void)popToSelfAnimated:(BOOL)animated {
	[self.navigationController popToViewController:self animated:animated];
	[self reload];
}

#pragma mark - setting a password

- (void)startSetPassword {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self stepWithTitle:@"Password"
													 caption:@"Step 1 of 4"
												 placeholder:@"Password"
													  footer:@"Enter a password you will be "
							@"asked for whenever you log in on a new device."];
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (!text.length){
			[sender refuseWithMessage:@"Please enter a password."];
			return;
		}
		[weakSelf askReenterOfPassword:text oldPassword:nil];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)askReenterOfPassword:(NSString *)password oldPassword:(NSString *)oldPassword {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self stepWithTitle:@"Re-enter"
													 caption:@"Step 2 of 4"
												 placeholder:@"Password"
													  footer:@"Type the same password once "
							@"more, so a typing mistake cannot lock you out."];
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (![text isEqualToString:password]){
			[sender refuseWithMessage:@"The two passwords are different."];
			return;
		}
		[weakSelf askHintForPassword:password oldPassword:oldPassword];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)askHintForPassword:(NSString *)password oldPassword:(NSString *)oldPassword {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self stepWithTitle:@"Hint"
													 caption:@"Step 3 of 4"
												 placeholder:@"Hint"
													  footer:@"A short reminder shown when the "
							@"password is asked for. Anyone who sees your log-in screen sees "
							@"the hint, so keep it vague."];
	step.secure = NO;
	step.skipTitle = @"Skip This Step";
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if ([text isEqualToString:password]){
			[sender refuseWithMessage:@"The hint cannot be the password itself."];
			return;
		}
		[weakSelf askEmailForPassword:password hint:text oldPassword:oldPassword];
	};
	step.onSkip = ^{
		[weakSelf askEmailForPassword:password hint:nil oldPassword:oldPassword];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)askEmailForPassword:(NSString *)password hint:(NSString *)hint
				oldPassword:(NSString *)oldPassword {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self stepWithTitle:@"Recovery"
													 caption:@"Step 4 of 4"
												 placeholder:@"E-Mail"
													  footer:@"This is the only way back into "
							@"the account if you forget the password. Telegram sends a code "
							@"to this address to confirm it."];
	step.secure = NO;
	step.email = YES;
	step.skipTitle = @"Skip This Step";
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if ([text rangeOfString:@"@"].location == NSNotFound || text.length < 5){
			[sender refuseWithMessage:@"That is not an e-mail address."];
			return;
		}
		[weakSelf commitPassword:password hint:hint email:text
					 oldPassword:oldPassword fromStep:sender];
	};
	step.onSkip = ^{
		[weakSelf confirmSkippingRecoveryForPassword:password hint:hint
										 oldPassword:oldPassword];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)confirmSkippingRecoveryForPassword:(NSString *)password hint:(NSString *)hint
							   oldPassword:(NSString *)oldPassword {
	self.newPassword = password;
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil
			message:@"Without a recovery e-mail address you will lose the account if you "
					@"forget the password. Continue anyway?"
			delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Continue", nil];
	alert.tag = (NSInteger)(hint.length ? 1 : 2);
	objc_setAssociatedObject_placeholder: ;
	[self performSelector:@selector(noop)];
	[alert show];
	self.pendingHint = hint;
	self.pendingOldPassword = oldPassword;
}

- (void)noop {
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	[self commitPassword:self.newPassword hint:self.pendingHint email:nil
			 oldPassword:self.pendingOldPassword fromStep:nil];
}

- (void)commitPassword:(NSString *)password hint:(NSString *)hint email:(NSString *)email
		   oldPassword:(NSString *)oldPassword
			  fromStep:(TGSecurityStepViewController *)step {
	[step setBusy:YES];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPasswordWithOldPassword:oldPassword
									  newPassword:password
											 hint:hint
									recoveryEmail:email
									   completion:^(NSDictionary *state){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (![state isKindOfClass:[NSDictionary class]]){
			if (step)
				[step refuseWithMessage:oldPassword.length
						? @"That password is wrong." : @"The password could not be set."];
			else
				TGPrivacyComplain(@"The password could not be set.");
			return;
		}
		strongSelf.state = state;
		strongSelf.loaded = YES;
		id pattern = state[@"recoveryEmailPattern"];
		if ([pattern isKindOfClass:[NSString class]] && [pattern length]){
			[step setBusy:NO];
			[strongSelf askRecoveryCodeForPattern:pattern replacingStep:step];
			return;
		}
		[strongSelf popToSelfAnimated:YES];
	}];
}

- (void)askRecoveryCodeForPattern:(NSString *)pattern
					replacingStep:(TGSecurityStepViewController *)step {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *code = [self stepWithTitle:@"Code"
													 caption:@"Confirm your e-mail"
												 placeholder:@"Code"
													  footer:[NSString stringWithFormat:
							@"We have sent a code to %@. Enter it here to switch the "
							@"password on.", pattern]];
	code.secure = NO;
	code.numeric = YES;
	code.actionTitle = @"Done";
	code.skipTitle = @"Send The Code Again";
	code.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (!text.length){
			[sender refuseWithMessage:@"Please enter the code."];
			return;
		}
		[sender setBusy:YES];
		[[TGClient shared] checkRecoveryEmailCode:text completion:^(NSDictionary *state){
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf)
				return;
			if (![state isKindOfClass:[NSDictionary class]]){
				[sender refuseWithMessage:@"That code is wrong."];
				return;
			}
			strongSelf.state = state;
			[strongSelf popToSelfAnimated:YES];
		}];
	};
	code.onSkip = ^{
		[[TGClient shared] resendRecoveryEmailCodeWithCompletion:^(NSDictionary *state){
			TGPrivacyComplain(state ? @"The code has been sent again."
									: @"The code could not be sent again.");
		}];
	};
	[self.navigationController pushViewController:code animated:YES];
}

#pragma mark - changing, disabling, recovery e-mail

- (void)startChangePassword {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self stepWithTitle:@"Password"
													 caption:@"Your current password"
												 placeholder:@"Password"
													  footer:[self hint].length
							? [NSString stringWithFormat:@"Hint: %@", [self hint]]
							: @"Enter the password you are using now."];
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (!text.length){
			[sender refuseWithMessage:@"Please enter your password."];
			return;
		}
		[weakSelf askNewPasswordWithOldPassword:text];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)askNewPasswordWithOldPassword:(NSString *)oldPassword {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self stepWithTitle:@"New Password"
													 caption:@"Step 1 of 4"
												 placeholder:@"Password"
													  footer:@"Enter the new password."];
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (!text.length){
			[sender refuseWithMessage:@"Please enter a password."];
			return;
		}
		[weakSelf askReenterOfPassword:text oldPassword:oldPassword];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)startDisablePassword {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self stepWithTitle:@"Password"
													 caption:@"Your current password"
												 placeholder:@"Password"
													  footer:@"Enter your password to turn "
							@"two-step verification off."];
	step.actionTitle = @"Done";
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (!text.length){
			[sender refuseWithMessage:@"Please enter your password."];
			return;
		}
		[sender setBusy:YES];
		[[TGClient shared] disablePasswordWithOldPassword:text completion:^(BOOL ok){
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf)
				return;
			if (!ok){
				[sender refuseWithMessage:@"That password is wrong."];
				return;
			}
			[strongSelf popToSelfAnimated:YES];
		}];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)startSetRecoveryEmail {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self stepWithTitle:@"Password"
													 caption:@"Your current password"
												 placeholder:@"Password"
													  footer:@"Enter your password to change "
							@"the recovery e-mail address."];
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (!text.length){
			[sender refuseWithMessage:@"Please enter your password."];
			return;
		}
		[weakSelf askRecoveryEmailWithPassword:text];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)askRecoveryEmailWithPassword:(NSString *)password {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self stepWithTitle:@"Recovery"
													 caption:@"Recovery e-mail"
												 placeholder:@"E-Mail"
													  footer:@"Telegram sends a code to this "
							@"address to confirm it."];
	step.secure = NO;
	step.email = YES;
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if ([text rangeOfString:@"@"].location == NSNotFound || text.length < 5){
			[sender refuseWithMessage:@"That is not an e-mail address."];
			return;
		}
		[sender setBusy:YES];
		[[TGClient shared] setRecoveryEmail:text password:password
								 completion:^(NSDictionary *state){
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf)
				return;
			if (![state isKindOfClass:[NSDictionary class]]){
				[sender refuseWithMessage:@"The address could not be saved."];
				return;
			}
			strongSelf.state = state;
			id pattern = state[@"recoveryEmailPattern"];
			if ([pattern isKindOfClass:[NSString class]] && [pattern length]){
				[sender setBusy:NO];
				[strongSelf askRecoveryCodeForPattern:pattern replacingStep:sender];
				return;
			}
			[strongSelf popToSelfAnimated:YES];
		}];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (!self.loaded)
		return;

	if (![self hasPassword]){
		[self startSetPassword];
		return;
	}
	if (indexPath.section == 1){
		if (indexPath.row == 0){
			[self startChangePassword];
			return;
		}
		NSString *pending = [self pendingEmailPattern];
		if (pending)
			[self askRecoveryCodeForPattern:pending replacingStep:nil];
		else
			[self startSetRecoveryEmail];
		return;
	}
	if (indexPath.section == 2)
		[self startDisablePassword];
}

@end

#pragma mark - passcode

@interface TGPasscodeViewController () <UIActionSheetDelegate>
@property (nonatomic, assign) BOOL locked;
@end

@implementation TGPasscodeViewController

+ (NSString *)digestOf:(NSString *)passcode {
	NSData *data = [[NSString stringWithFormat:@"tg.passcode.%@", passcode ?: @""]
			dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char out[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(data.bytes, (CC_LONG)data.length, out);
	NSMutableString *hex = [NSMutableString string];
	for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
		[hex appendFormat:@"%02x", out[i]];
	return hex;
}

+ (BOOL)passcodeIsSet {
	id stored = [[NSUserDefaults standardUserDefaults] objectForKey:TGPasscodeDigestKey];
	return [stored isKindOfClass:[NSString class]] && [stored length] > 0;
}

+ (BOOL)passcodeMatches:(NSString *)passcode {
	id stored = [[NSUserDefaults standardUserDefaults] objectForKey:TGPasscodeDigestKey];
	if (![stored isKindOfClass:[NSString class]] || ![stored length])
		return YES;
	return [stored isEqualToString:[self digestOf:passcode]];
}

+ (NSInteger)autoLockSeconds {
	return [[NSUserDefaults standardUserDefaults] integerForKey:TGPasscodeAutoLockKey];
}

+ (void)storePasscode:(NSString *)passcode {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if (passcode.length)
		[defaults setObject:[self digestOf:passcode] forKey:TGPasscodeDigestKey];
	else
		[defaults removeObjectForKey:TGPasscodeDigestKey];
	[defaults synchronize];
}

+ (void)storeAutoLockSeconds:(NSInteger)seconds {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setInteger:seconds forKey:TGPasscodeAutoLockKey];
	[defaults synchronize];
}

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Passcode Lock";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.rowHeight = 44;
	self.locked = [TGPasscodeViewController passcodeIsSet];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.locked = [TGPasscodeViewController passcodeIsSet];
	[self.tableView reloadData];
}

- (NSArray *)autoLockOptions {
	return [NSArray arrayWithObjects:
			[NSNumber numberWithInteger:0],
			[NSNumber numberWithInteger:60],
			[NSNumber numberWithInteger:5 * 60],
			[NSNumber numberWithInteger:60 * 60],
			[NSNumber numberWithInteger:5 * 60 * 60], nil];
}

- (NSString *)autoLockTitleForSeconds:(NSInteger)seconds {
	if (seconds <= 0) return @"Disabled";
	if (seconds < 60 * 60)
		return [NSString stringWithFormat:@"in %d minutes", (int)(seconds / 60)];
	if (seconds == 60 * 60) return @"in 1 hour";
	return [NSString stringWithFormat:@"in %d hours", (int)(seconds / 3600)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.locked ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return 1;
	return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0)
		return @"When the passcode is on, Telegram asks for it before showing "
			   @"your chats again.";
	if (section == 1)
		return @"Auto-Lock is how long Telegram may stay open in the background "
			   @"before it asks again.";
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"toggle"];
		if (!cell){
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:@"toggle"];
			UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
			[toggle addTarget:self action:@selector(toggleChanged:)
			 forControlEvents:UIControlEventValueChanged];
			cell.accessoryView = toggle;
		}
		[[TGTheme shared] styleCell:cell];
		cell.textLabel.text = @"Passcode Lock";
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.textLabel.textAlignment = NSTextAlignmentLeft;
		cell.textLabel.textColor = TGPrivacyRowTitleColour();
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		[(UISwitch *)cell.accessoryView setOn:self.locked animated:NO];
		return cell;
	}

	if (indexPath.row == 0){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"autolock"];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
										  reuseIdentifier:@"autolock"];
		[[TGTheme shared] styleCell:cell];
		cell.textLabel.text = @"Auto-Lock";
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.textLabel.textAlignment = NSTextAlignmentLeft;
		cell.textLabel.textColor = TGPrivacyRowTitleColour();
		cell.detailTextLabel.text = [self autoLockTitleForSeconds:
				[TGPasscodeViewController autoLockSeconds]];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:17];
		cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"change"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"change"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = @"Change Passcode";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.textLabel.textColor = TGPrivacyActionColour();
	cell.textLabel.highlightedTextColor = [UIColor whiteColor];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (TGSecurityStepViewController *)passcodeStepWithTitle:(NSString *)title
												caption:(NSString *)caption
												 footer:(NSString *)footer {
	TGSecurityStepViewController *step = [[TGSecurityStepViewController alloc] init];
	step.stepTitle = title;
	step.stepCaption = caption;
	step.placeholder = @"Passcode";
	step.footerText = footer;
	step.secure = YES;
	step.numeric = YES;
	return step;
}

- (void)toggleChanged:(UISwitch *)sender {
	if (sender.on){
		[self startSetPasscode];
		[sender setOn:NO animated:NO];
		return;
	}
	[sender setOn:YES animated:NO];
	[self startVerifyThen:^{
		[TGPasscodeViewController storePasscode:nil];
	}];
}

- (void)startVerifyThen:(dispatch_block_t)done {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self passcodeStepWithTitle:@"Passcode"
															 caption:@"Your current passcode"
															  footer:@"Enter the passcode you "
							@"are using now."];
	step.actionTitle = @"Done";
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (![TGPasscodeViewController passcodeMatches:text]){
			[sender refuseWithMessage:@"That passcode is wrong."];
			return;
		}
		if (done)
			done();
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.locked = [TGPasscodeViewController passcodeIsSet];
		[strongSelf.navigationController popToViewController:strongSelf animated:YES];
		[strongSelf.tableView reloadData];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)startSetPasscode {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self passcodeStepWithTitle:@"Passcode"
															 caption:@"Step 1 of 2"
															  footer:@"Enter a passcode of at "
							@"least four digits."];
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (text.length < 4){
			[sender refuseWithMessage:@"Please enter at least four digits."];
			return;
		}
		[weakSelf askPasscodeAgain:text];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)askPasscodeAgain:(NSString *)passcode {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self passcodeStepWithTitle:@"Re-enter"
															 caption:@"Step 2 of 2"
															  footer:@"Type the same passcode "
							@"once more."];
	step.actionTitle = @"Done";
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (![text isEqualToString:passcode]){
			[sender refuseWithMessage:@"The two passcodes are different."];
			return;
		}
		[TGPasscodeViewController storePasscode:passcode];
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.locked = YES;
		[strongSelf.navigationController popToViewController:strongSelf animated:YES];
		[strongSelf.tableView reloadData];
	};
	[self.navigationController pushViewController:step animated:YES];
}

- (void)showAutoLockPicker {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Auto-Lock"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	NSInteger current = [TGPasscodeViewController autoLockSeconds];
	for (NSNumber *option in [self autoLockOptions]){
		NSString *title = [self autoLockTitleForSeconds:[option integerValue]];
		if ([option integerValue] == current)
			title = [title stringByAppendingString:@" ✓"];
		[sheet addButtonWithTitle:title];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 90;
	[sheet showInView:self.navigationController.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (sheet.tag != 90 || index == sheet.cancelButtonIndex)
		return;
	NSArray *options = [self autoLockOptions];
	if (index < 0 || index >= (NSInteger)options.count)
		return;
	[TGPasscodeViewController storeAutoLockSeconds:
			[[options objectAtIndex:index] integerValue]];
	[self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1)
		return;
	if (indexPath.row == 0){
		[self showAutoLockPicker];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self startVerifyThenChange:^{
		[weakSelf startSetPasscode];
	}];
}

- (void)startVerifyThenChange:(dispatch_block_t)next {
	__weak typeof(self) weakSelf = self;
	TGSecurityStepViewController *step = [self passcodeStepWithTitle:@"Passcode"
															 caption:@"Your current passcode"
															  footer:@"Enter the passcode you "
							@"are using now."];
	step.onSubmit = ^(TGSecurityStepViewController *sender, NSString *text){
		if (![TGPasscodeViewController passcodeMatches:text]){
			[sender refuseWithMessage:@"That passcode is wrong."];
			return;
		}
		__strong typeof(weakSelf) strongSelf = weakSelf;
		[strongSelf.navigationController popToViewController:strongSelf animated:NO];
		if (next)
			next();
	};
	[self.navigationController pushViewController:step animated:YES];
}

@end

#pragma mark - privacy rule

@interface TGPrivacyRuleViewController ()
@property (nonatomic, strong) NSString *setting;
@property (nonatomic, strong) NSString *value;
@property (nonatomic, strong) NSArray *allowedUsers;
@property (nonatomic, strong) NSArray *restrictedUsers;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation TGPrivacyRuleViewController

- (instancetype)initWithSetting:(NSString *)setting {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self)
		_setting = setting;
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = [TGClient titleForPrivacySetting:self.setting];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.rowHeight = 44;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] privacyRuleDetailed:self.setting completion:^(NSDictionary *info){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		if ([info isKindOfClass:[NSDictionary class]]){
			id value = info[@"value"];
			strongSelf.value = [value isKindOfClass:[NSString class]] ? value : @"everybody";
			id allowed = info[@"allowedUserIds"];
			id restricted = info[@"restrictedUserIds"];
			strongSelf.allowedUsers = [allowed isKindOfClass:[NSArray class]] ? allowed : nil;
			strongSelf.restrictedUsers =
					[restricted isKindOfClass:[NSArray class]] ? restricted : nil;
		}
		[strongSelf.tableView reloadData];
	}];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (NSArray *)values {
	return [NSArray arrayWithObjects:@"everybody", @"contacts", @"nobody", nil];
}

- (NSString *)titleForValue:(NSString *)value {
	if ([value isEqualToString:@"contacts"])
		return @"My Contacts";
	if ([value isEqualToString:@"nobody"])
		return @"Nobody";
	return @"Everybody";
}

- (BOOL)showsExceptions {
	return self.allowedUsers.count > 0 || self.restrictedUsers.count > 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [self showsExceptions] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return self.loaded ? 3 : 0;
	NSInteger rows = 0;
	if (self.allowedUsers.count)
		rows++;
	if (self.restrictedUsers.count)
		rows++;
	return rows;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0)
		return @"Who can see this";
	return @"Exceptions";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0)
		return self.loaded ? nil : @"Loading...";
	return @"Exceptions set on another device are kept as they are.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"value"];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:@"value"];
		[[TGTheme shared] styleCell:cell];
		NSString *value = [self values][indexPath.row];
		cell.textLabel.text = [self titleForValue:value];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.textLabel.textAlignment = NSTextAlignmentLeft;
		cell.textLabel.textColor = TGPrivacyRowTitleColour();
		cell.accessoryType = [value isEqualToString:self.value]
				? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"exception"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"exception"];
	[[TGTheme shared] styleCell:cell];
	BOOL allowedRow = self.allowedUsers.count && indexPath.row == 0;
	NSArray *list = allowedRow ? self.allowedUsers : self.restrictedUsers;
	cell.textLabel.text = allowedRow ? @"Always Share With" : @"Never Share With";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.textColor = TGPrivacyRowTitleColour();
	cell.detailTextLabel.text = list.count == 1
			? @"1 user" : [NSString stringWithFormat:@"%d users", (int)list.count];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:17];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 0 || !self.loaded)
		return;

	NSString *picked = [self values][indexPath.row];
	if ([picked isEqualToString:self.value])
		return;

	NSString *previous = self.value;
	self.value = picked;
	[tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPrivacyRule:self.setting
								   to:picked
						 allowedUsers:self.allowedUsers
					  restrictedUsers:self.restrictedUsers
						   completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (ok || !strongSelf)
			return;
		strongSelf.value = previous;
		[strongSelf.tableView reloadData];
		TGPrivacyComplain(@"That setting could not be changed.");
	}];
}

@end

#pragma mark - the hub

@interface TGPrivacyViewController ()
@property (nonatomic, strong) NSMutableDictionary *ruleValues;
@property (nonatomic, assign) BOOL passwordOn;
@property (nonatomic, assign) BOOL passwordLoaded;
@end

@implementation TGPrivacyViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self)
		_ruleValues = [NSMutableDictionary dictionary];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Privacy and Security";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.rowHeight = 44;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self.tableView reloadData];
	[self reload];
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	for (NSString *setting in [TGClient privacySettingNames]){
		[[TGClient shared] privacyRuleDetailed:setting completion:^(NSDictionary *info){
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf || ![info isKindOfClass:[NSDictionary class]])
				return;
			id value = info[@"value"];
			if ([value isKindOfClass:[NSString class]])
				strongSelf.ruleValues[setting] = value;
			[strongSelf.tableView reloadData];
		}];
	}

	[[TGClient shared] passwordStateWithCompletion:^(NSDictionary *state){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.passwordLoaded = [state isKindOfClass:[NSDictionary class]];
		strongSelf.passwordOn = [state[@"hasPassword"] boolValue];
		[strongSelf.tableView reloadData];
	}];
}

- (NSArray *)settings {
	return [TGClient privacySettingNames] ?: [NSArray array];
}

- (NSString *)shortTitleForValue:(NSString *)value {
	if (!value.length)
		return @"...";
	if ([value isEqualToString:@"contacts"])
		return @"My Contacts";
	if ([value isEqualToString:@"nobody"])
		return @"Nobody";
	return @"Everybody";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return (NSInteger)[self settings].count;
	return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0)
		return @"Privacy";
	return @"Security";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0)
		return @"These settings decide who may see what about you, and who may "
			   @"reach you.";
	return @"Two-step verification asks for a password of your own when you log "
		   @"in on a new device. The passcode only guards this phone.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.textColor = TGPrivacyRowTitleColour();
	cell.detailTextLabel.font = [UIFont systemFontOfSize:17];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;

	if (indexPath.section == 0){
		NSString *setting = [self settings][indexPath.row];
		cell.textLabel.text = [TGClient titleForPrivacySetting:setting];
		cell.detailTextLabel.text = [self shortTitleForValue:self.ruleValues[setting]];
		return cell;
	}

	if (indexPath.row == 0){
		cell.textLabel.text = @"Passcode Lock";
		cell.detailTextLabel.text = [TGPasscodeViewController passcodeIsSet] ? @"On" : @"Off";
		return cell;
	}
	if (indexPath.row == 1){
		cell.textLabel.text = @"Two-Step Verification";
		cell.detailTextLabel.text = self.passwordLoaded
				? (self.passwordOn ? @"On" : @"Off") : @"...";
		return cell;
	}
	cell.textLabel.text = @"Active Sessions";
	cell.detailTextLabel.text = @"";
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 0){
		NSArray *settings = [self settings];
		if ((NSUInteger)indexPath.row >= settings.count)
			return;
		TGPrivacyRuleViewController *rule = [[TGPrivacyRuleViewController alloc]
				initWithSetting:settings[indexPath.row]];
		[self.navigationController pushViewController:rule animated:YES];
		return;
	}

	if (indexPath.row == 0){
		[self.navigationController pushViewController:
				[[TGPasscodeViewController alloc] init] animated:YES];
		return;
	}
	if (indexPath.row == 1){
		[self.navigationController pushViewController:
				[[TGTwoStepViewController alloc] init] animated:YES];
		return;
	}
	[self.navigationController pushViewController:
			[[TGSessionsViewController alloc] init] animated:YES];
}

@end

// vim:ft=objc

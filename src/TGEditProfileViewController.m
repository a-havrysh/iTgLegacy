#import "TGEditProfileViewController.h"
#import "TGClient.h"
#import "TGTheme.h"

@interface TGEditProfileViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *firstField;
@property (nonatomic, strong) UITextField *lastField;
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UITextField *bioField;
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
	self.tableView.separatorColor = [[TGTheme shared] bubbleBorderColour];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Save" style:UIBarButtonItemStyleDone
				   target:self action:@selector(save)];

	NSDictionary *me = [TGClient shared].me;
	self.firstField    = [self fieldWithPlaceholder:@"First name" text:me[@"first_name"]];
	self.lastField     = [self fieldWithPlaceholder:@"Last name"  text:me[@"last_name"]];
	self.usernameField = [self fieldWithPlaceholder:@"username"   text:me[@"username"]];
	self.usernameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.bioField      = [self fieldWithPlaceholder:@"A few words about you" text:nil];

	// getUserFullInfo carries the bio; `me` does not.
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] request:@{
		@"@type"   : @"getUserFullInfo",
		@"user_id" : me[@"id"] ?: @0,
	} completion:^(NSDictionary *full){
		weakSelf.bioField.text = full[@"bio"][@"text"] ?: full[@"bio"] ?: @"";
	}];
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text {
	UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(15, 0, 290, 44)];
	field.placeholder = placeholder;
	field.text = [text isKindOfClass:NSString.class] ? text : @"";
	field.font = [UIFont systemFontOfSize:16];
	field.delegate = self;
	field.returnKeyType = UIReturnKeyDone;
	field.textColor = [[TGTheme shared] primaryTextColour];
	return field;
}

- (void)save {
	[[TGClient shared] setName:self.firstField.text last:self.lastField.text];
	[[TGClient shared] setBio:self.bioField.text];

	NSString *username = [self.usernameField.text
			stringByReplacingOccurrencesOfString:@"@" withString:@""];
	NSDictionary *me = [TGClient shared].me;
	if (![username isEqualToString:me[@"username"] ?: @""]){
		// A username can be taken, which is the one failure worth reporting.
		[[TGClient shared] setUsername:username completion:^(BOOL ok){
			if (!ok){
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Username"
						message:@"That username is not available."
					   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
				[alert show];
			}
		}];
	}
	[self.navigationController popViewControllerAnimated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
	[field resignFirstResponder];
	return NO;
}

/// Settings has its own navigation controller, and nothing was styling
/// its bar - an imported theme stopped at the top of the screen.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"Name";
	if (section == 1) return @"Username";
	return @"Bio";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 2 : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
												  reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UITextField *field = nil;
	if (indexPath.section == 0)      field = indexPath.row == 0 ? self.firstField : self.lastField;
	else if (indexPath.section == 1) field = self.usernameField;
	else                             field = self.bioField;

	field.frame = CGRectMake(15, 0, tableView.bounds.size.width - 30, 44);
	[cell.contentView addSubview:field];
	return cell;
}

@end

// vim:ft=objc

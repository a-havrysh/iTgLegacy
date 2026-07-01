#import "TGSettingsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"

@implementation TGSettingsViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Settings";
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"Account";
	if (section == 1) return @"Appearance";
	return @"Storage";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section != 1)
		return nil;
	return (NSFoundationVersionNumber > 993.00)
		? @"This system shipped flat, so that is the default here."
		: @"This system shipped skeuomorphic, so that is the default here.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 1;
	if (section == 1) return 2;   // skeuomorphic / flat
	return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGSettingsCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.textColor = [UIColor blackColor];

	if (indexPath.section == 0){
		NSDictionary *me = [TGClient shared].me;
		if (me){
			cell.textLabel.text = [me[@"username"] length]
				? [NSString stringWithFormat:@"@%@", me[@"username"]]
				: me[@"first_name"];
			cell.detailTextLabel.text = [NSString stringWithFormat:@"+%@", me[@"phone"]];
			cell.accessoryType = UITableViewCellAccessoryCheckmark;
		} else {
			cell.textLabel.text = @"Not signed in";
			cell.detailTextLabel.text = @"";
		}
		return cell;
	}

	if (indexPath.section == 1){
		BOOL flat = [TGTheme shared].isFlat;
		cell.textLabel.text = (indexPath.row == 0) ? @"Skeuomorphic" : @"Flat";
		cell.detailTextLabel.text = @"";
		cell.accessoryType = ((indexPath.row == 1) == flat)
			? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		return cell;
	}

	cell.detailTextLabel.text = @"";
	if (indexPath.row == 0){
		cell.textLabel.text = @"Clear local cache";
	} else {
		cell.textLabel.text = @"Log out";
		cell.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1.0f];
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 1){
		[TGTheme shared].style = (indexPath.row == 0)
			? TGThemeStyleSkeuomorphic : TGThemeStyleFlat;
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
		[tableView reloadData];
		return;
	}

	if (indexPath.section != 2)
		return;

	if (indexPath.row == 0){
		[[TGClient shared] clearLocalDatabase];
		return;
	}

	// Logging out drops the session, so make it deliberate.
	UIAlertView *confirm = [[UIAlertView alloc]
			initWithTitle:@"Log out"
				  message:@"Sign out of this account on this device?"
				 delegate:self
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@"Log out", nil];
	[confirm show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == 1)
		[[TGClient shared] logOut];
}

@end

// vim:ft=objc

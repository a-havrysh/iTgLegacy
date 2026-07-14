#import "TGDeviceViewController.h"
#import "TGDevice.h"
#import "TGCapabilities.h"
#import "TGTheme.h"

@interface TGDeviceViewController ()
@property (nonatomic, strong) NSArray *capabilities;
@end

@implementation TGDeviceViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Device";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] bubbleBorderColour];
	self.capabilities = [TGCapabilities all];
}

/// Settings has its own navigation controller, and nothing was styling
/// its bar - an imported theme stopped at the top of the screen.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? @"Hardware" : @"Features";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0)
		return @"Vintage: iPhone 3GS and 4. Legacy: 4S, 5 and 5c. "
			   @"Modern: 5s and 6. Full: 6s and later.";
	return @"Features off here are not missing from the app - this device "
		   @"cannot run them.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 4 : self.capabilities.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
	[[TGTheme shared] styleCell:cell];

	if (indexPath.section == 0){
		switch (indexPath.row){
			case 0:
				cell.textLabel.text = @"Model";
				cell.detailTextLabel.text = [TGDevice modelName];
				break;
			case 1:
				cell.textLabel.text = @"Chip and memory";
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, %lu MB",
						[TGDevice chip] ?: @"?", (unsigned long)[TGDevice memoryMB]];
				break;
			case 2:
				cell.textLabel.text = @"iOS";
				cell.detailTextLabel.text = [UIDevice currentDevice].systemVersion;
				break;
			default:
				cell.textLabel.text = @"Tier";
				cell.detailTextLabel.text = [TGDevice tierName];
				break;
		}
		return cell;
	}

	TGCapability *capability = self.capabilities[indexPath.row];
	cell.textLabel.text = capability.name;
	cell.detailTextLabel.text = capability.available ? @"on" : capability.requirement;
	cell.detailTextLabel.textColor = capability.available
			? [UIColor colorWithRed:0.20f green:0.60f blue:0.30f alpha:1]
			: [[TGTheme shared] secondaryTextColour];
	cell.textLabel.textColor = capability.available
			? [[TGTheme shared] primaryTextColour]
			: [[TGTheme shared] secondaryTextColour];
	return cell;
}

@end

// vim:ft=objc

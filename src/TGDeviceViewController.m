#import "TGDeviceViewController.h"
#import "TGDevice.h"
#import "TGCapabilities.h"
#import "TGTheme.h"

@interface TGDeviceViewController ()
@property (nonatomic, strong) NSArray *capabilities;
@property (nonatomic, strong) NSIndexPath *copiedIndexPath;
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
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.rowHeight = 44;
	self.capabilities = [TGCapabilities all] ?: @[];
}

- (NSString *)freeSpaceText {
	NSString *path = NSHomeDirectory();
	if (!path)
		return @"?";
	NSError *error = nil;
	NSDictionary *attributes = [[NSFileManager defaultManager]
			attributesOfFileSystemForPath:path error:&error];
	NSNumber *free = attributes[NSFileSystemFreeSize];
	if (!free)
		return @"?";
	double megabytes = [free doubleValue] / (1024.0 * 1024.0);
	if (megabytes >= 1024.0)
		return [NSString stringWithFormat:@"%.1f GB", megabytes / 1024.0];
	return [NSString stringWithFormat:@"%.0f MB", megabytes];
}

- (NSString *)screenText {
	CGRect bounds = [UIScreen mainScreen].bounds;
	CGFloat scale = 1;
	if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
		scale = [UIScreen mainScreen].scale;
	return [NSString stringWithFormat:@"%.0f x %.0f @%.0fx",
			bounds.size.width * scale, bounds.size.height * scale, scale];
}

- (NSString *)titleForHardwareRow:(NSInteger)row {
	switch (row){
		case 0: return @"Model";
		case 1: return @"Identifier";
		case 2: return @"Chip and memory";
		case 3: return @"Screen";
		case 4: return @"iOS";
		case 5: return @"Free space";
		default: return @"Tier";
	}
}

- (NSString *)valueForHardwareRow:(NSInteger)row {
	switch (row){
		case 0: return [TGDevice modelName] ?: @"Unknown";
		case 1: return [TGDevice machine] ?: @"?";
		case 2: return [NSString stringWithFormat:@"%@, %lu MB",
				[TGDevice chip] ?: @"?", (unsigned long)[TGDevice memoryMB]];
		case 3: return [self screenText];
		case 4: return [UIDevice currentDevice].systemVersion ?: @"?";
		case 5: return [self freeSpaceText];
		default: return [TGDevice tierName] ?: @"?";
	}
}

/// Settings has its own navigation controller, and nothing was styling
/// its bar - an imported theme stopped at the top of the screen.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.capabilities = [TGCapabilities all] ?: @[];
	self.copiedIndexPath = nil;
	[self.tableView reloadData];
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
			   @"Modern: 5s and 6. Full: 6s and later. Tap a row to copy it.";
	if (self.capabilities.count == 0)
		return @"Nothing to report for this device.";
	return @"Features off here are not missing from the app - this device "
		   @"cannot run them.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 7 : (NSInteger)self.capabilities.count;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 0)
		return;
	NSString *line = [NSString stringWithFormat:@"%@: %@",
			[self titleForHardwareRow:indexPath.row],
			[self valueForHardwareRow:indexPath.row]];
	[[UIPasteboard generalPasteboard] setString:line];
	self.copiedIndexPath = indexPath;
	[tableView reloadRowsAtIndexPaths:@[indexPath]
					 withRowAnimation:UITableViewRowAnimationNone];
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.copiedIndexPath)
			return;
		NSIndexPath *path = strongSelf.copiedIndexPath;
		strongSelf.copiedIndexPath = nil;
		if (path.row < [strongSelf.tableView numberOfRowsInSection:0])
			[strongSelf.tableView reloadRowsAtIndexPaths:@[path]
										withRowAnimation:UITableViewRowAnimationNone];
	});
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"row"];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];

	if (indexPath.section == 0){
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		cell.textLabel.text = [self titleForHardwareRow:indexPath.row];
		if (self.copiedIndexPath && self.copiedIndexPath.row == indexPath.row)
			cell.detailTextLabel.text = @"copied";
		else
			cell.detailTextLabel.text = [self valueForHardwareRow:indexPath.row];
		return cell;
	}

	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	if (indexPath.row >= (NSInteger)self.capabilities.count){
		cell.textLabel.text = @"";
		cell.detailTextLabel.text = @"";
		return cell;
	}
	TGCapability *capability = self.capabilities[indexPath.row];
	cell.textLabel.text = capability.name ?: @"";
	cell.detailTextLabel.text = capability.available
			? @"on"
			: (capability.requirement ?: @"off");
	cell.detailTextLabel.textColor = capability.available
			? [[TGTheme shared] cellDetailColour]
			: [[TGTheme shared] secondaryTextColour];
	cell.textLabel.textColor = capability.available
			? [[TGTheme shared] primaryTextColour]
			: [[TGTheme shared] secondaryTextColour];
	return cell;
}

@end

// vim:ft=objc

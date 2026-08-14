#import "TGDeviceViewController.h"
#import "TGDevice.h"
#import "TGCapabilities.h"
#import "TGTheme.h"

static UIColor *TGDeviceRGB(int rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:1.0f];
}

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

- (NSString *)headerTitleForSection:(NSInteger)section {
	return section == 0 ? @"Hardware" : @"Features";
}

- (NSString *)footerTextForSection:(NSInteger)section {
	if (section == 0)
		return @"Vintage: iPhone 3GS and 4. Legacy: 4S, 5 and 5c. "
			   @"Modern: 5s and 6. Full: 6s and later. Tap a row to copy it.";
	if (self.capabilities.count == 0)
		return @"Nothing to report for this device.";
	return @"Features off here are not missing from the app - this device "
		   @"cannot run them.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return 46;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	BOOL dark = [[TGTheme shared] isDark];
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, 46)];
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [[UILabel alloc] init];
	label.text = [self headerTitleForSection:section];
	label.font = [UIFont boldSystemFontOfSize:17];
	label.backgroundColor = [UIColor clearColor];
	label.textColor = dark ? [[TGTheme shared] sectionHeaderColour]
						   : TGDeviceRGB(0x697487);
	if (!dark){
		label.shadowColor = TGDeviceRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[label sizeToFit];
	label.frame = CGRectIntegral(CGRectOffset(label.frame, 21, 16));
	[container addSubview:label];
	return container;
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
						   : TGDeviceRGB(0x697487);
	if (!dark){
		label.shadowColor = TGDeviceRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[container addSubview:label];
	return container;
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

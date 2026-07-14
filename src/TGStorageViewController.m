#import "TGStorageViewController.h"
#import "TGClient.h"
#import "TGTheme.h"

@interface TGStorageViewController () <UIActionSheetDelegate>
@property (nonatomic, assign) long long bytes;
@property (nonatomic, assign) NSInteger files;
@property (nonatomic, assign) BOOL working;
@end

@implementation TGStorageViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Storage";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] bubbleBorderColour];
	[self refresh];
}

- (void)refresh {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storageStatsWithCompletion:^(long long bytes, NSInteger files){
		weakSelf.bytes = bytes;
		weakSelf.files = files;
		[weakSelf.tableView reloadData];
	}];
}

static NSString *TGHumanSize(long long bytes) {
	if (bytes < 1024)
		return [NSString stringWithFormat:@"%lld B", bytes];
	if (bytes < 1024 * 1024)
		return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
	if (bytes < 1024LL * 1024 * 1024)
		return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024)];
	return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024 * 1024)];
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
	return section == 0 ? @"Cache" : @"Clear";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section != 1)
		return nil;
	return @"Cleared media is downloaded again when you open the message. "
		   @"Nothing is deleted from Telegram.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 2 : 4;   // photos, videos, files, everything
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];

	if (indexPath.section == 0){
		cell.textLabel.text = indexPath.row == 0 ? @"Size on disk" : @"Files";
		cell.detailTextLabel.text = indexPath.row == 0
				? (self.working ? @"..." : TGHumanSize(self.bytes))
				: [NSString stringWithFormat:@"%ld", (long)self.files];
		return cell;
	}

	static NSArray *labels = nil;
	if (!labels)
		labels = @[@"Clear photos", @"Clear videos", @"Clear other files", @"Clear everything"];
	cell.textLabel.text = labels[indexPath.row];
	cell.detailTextLabel.text = @"";
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	if (indexPath.row == 3)
		cell.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1 || self.working)
		return;

	// TDLib names each kind; "everything" is the empty list, which means no
	// restriction by type rather than nothing at all.
	NSArray *kinds = nil;
	switch (indexPath.row){
		case 0: kinds = @[@"fileTypePhoto", @"fileTypeProfilePhoto", @"fileTypeThumbnail"]; break;
		case 1: kinds = @[@"fileTypeVideo", @"fileTypeVideoNote", @"fileTypeAnimation"]; break;
		case 2: kinds = @[@"fileTypeDocument", @"fileTypeAudio", @"fileTypeVoiceNote"]; break;
		default: kinds = @[]; break;
	}

	self.working = YES;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] clearCacheOfTypes:kinds completion:^(long long freed){
		weakSelf.working = NO;
		[weakSelf refresh];
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Storage"
				message:[NSString stringWithFormat:@"Freed %@.", TGHumanSize(freed)]
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}];
}

@end

// vim:ft=objc

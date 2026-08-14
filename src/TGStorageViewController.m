#import "TGStorageViewController.h"
#import "TGClient.h"
#import "TGTheme.h"

@interface TGStorageViewController () <UIActionSheetDelegate>
@property (nonatomic, assign) long long bytes;
@property (nonatomic, assign) NSInteger files;
@property (nonatomic, assign) BOOL working;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL refreshing;
@property (nonatomic, strong) NSArray *pendingKinds;
@property (nonatomic, copy) NSString *pendingTitle;
@end

static UIColor *TGStorageRGB(int rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:1.0f];
}

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
	if (self.refreshing)
		return;
	self.refreshing = YES;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storageStatsWithCompletion:^(long long bytes, NSInteger files){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.refreshing)
			return;
		[NSObject cancelPreviousPerformRequestsWithTarget:strongSelf
												 selector:@selector(statsTimedOut)
												   object:nil];
		strongSelf.refreshing = NO;
		strongSelf.loaded = YES;
		strongSelf.bytes = bytes < 0 ? 0 : bytes;
		strongSelf.files = files < 0 ? 0 : files;
		[strongSelf.tableView reloadData];
	}];

	[self performSelector:@selector(statsTimedOut) withObject:nil afterDelay:20.0];
}

- (void)statsTimedOut {
	if (!self.refreshing)
		return;
	self.refreshing = NO;
	self.working = NO;
	[self.tableView reloadData];
}

- (BOOL)cacheIsEmpty {
	return self.loaded && self.bytes <= 0 && self.files <= 0;
}

- (BOOL)canClear {
	return self.loaded && !self.working && ![self cacheIsEmpty];
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
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
	if (self.loaded && !self.working)
		[self refresh];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
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
	label.text = section == 0 ? @"Cache" : @"Clear";
	label.font = [UIFont boldSystemFontOfSize:17];
	label.backgroundColor = [UIColor clearColor];
	label.textColor = dark ? [[TGTheme shared] sectionHeaderColour]
						   : TGStorageRGB(0x697487);
	if (!dark){
		label.shadowColor = TGStorageRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 21, 16);
	[container addSubview:label];
	return container;
}

- (NSString *)footerText {
	return @"Cleared media is downloaded again when you open the message. "
		   @"Nothing is deleted from Telegram.";
}

- (CGFloat)footerHeightForWidth:(CGFloat)width {
	CGSize size = [[self footerText] sizeWithFont:[UIFont systemFontOfSize:14]
								constrainedToSize:CGSizeMake(width - 12 * 2, 1000)
									lineBreakMode:NSLineBreakByWordWrapping];
	return size.height + 7 * 2;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	return section == 1 ? [self footerHeightForWidth:tableView.bounds.size.width] : 1;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (section != 1)
		return nil;
	BOOL dark = [[TGTheme shared] isDark];
	CGFloat width = tableView.bounds.size.width;
	CGFloat height = [self footerHeightForWidth:width];

	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	container.backgroundColor = [UIColor clearColor];
	container.opaque = NO;

	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(1, 7, width - 2, height - 14)];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	label.text = [self footerText];
	label.font = [UIFont systemFontOfSize:14];
	label.contentMode = UIViewContentModeCenter;
	label.textAlignment = NSTextAlignmentCenter;
	label.lineBreakMode = NSLineBreakByWordWrapping;
	label.numberOfLines = 0;
	label.backgroundColor = [UIColor clearColor];
	label.textColor = dark ? [[TGTheme shared] secondaryTextColour]
						   : TGStorageRGB(0x697487);
	if (!dark){
		label.shadowColor = TGStorageRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 1 && indexPath.row == 3)
		return 45;
	return 44;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 2 : 4;   // photos, videos, files, everything
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 1 && indexPath.row == 3)
		return [self clearEverythingCellInTable:tableView];

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	[[TGTheme shared] styleCell:cell];
	BOOL dark = [[TGTheme shared] isDark];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = dark ? [[TGTheme shared] primaryTextColour]
									: [UIColor blackColor];
	cell.textLabel.highlightedTextColor = [UIColor whiteColor];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.textColor = dark ? [[TGTheme shared] cellDetailColour]
										  : TGStorageRGB(0x356596);
	cell.detailTextLabel.highlightedTextColor = [UIColor whiteColor];

	cell.accessoryView = nil;

	if (indexPath.section == 0){
		BOOL busy = self.working || !self.loaded;
		cell.textLabel.text = indexPath.row == 0 ? @"Size on disk" : @"Files";
		if (busy){
			cell.detailTextLabel.text = @"";
			cell.accessoryView = [self spinner];
		}
		else if (indexPath.row == 0)
			cell.detailTextLabel.text = [self cacheIsEmpty] ? @"Empty" : TGHumanSize(self.bytes);
		else
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)self.files];
		return cell;
	}

	static NSArray *labels = nil;
	if (!labels)
		labels = @[@"Clear photos", @"Clear videos", @"Clear other files"];
	cell.textLabel.text = labels[indexPath.row];
	cell.detailTextLabel.text = @"";
	if ([self canClear]){
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	} else {
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.textLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
										: TGStorageRGB(0x888888);
		if (self.working)
			cell.accessoryView = [self spinner];
	}
	return cell;
}

- (UIView *)spinner {
	UIActivityIndicatorViewStyle style = [[TGTheme shared] isDark]
			? UIActivityIndicatorViewStyleWhite
			: UIActivityIndicatorViewStyleGray;
	UIActivityIndicatorView *view = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:style];
	[view startAnimating];
	return view;
}

- (UITableViewCell *)clearEverythingCellInTable:(UITableView *)tableView {
	static NSString *reuse = @"TGStorageClearAllCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:reuse];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.backgroundColor = [UIColor clearColor];
		cell.backgroundView = [[UIView alloc] initWithFrame:CGRectZero];
		cell.backgroundView.backgroundColor = [UIColor clearColor];
		cell.contentView.backgroundColor = [UIColor clearColor];
		cell.opaque = NO;

		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.tag = 772;
		button.frame = CGRectMake(9, 0, cell.contentView.bounds.size.width - 18, 45);
		button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		button.adjustsImageWhenDisabled = NO;
		button.exclusiveTouch = YES;
		button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		[button setTitle:@"Clear everything" forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleShadowColor:[UIColor colorWithRed:0xa1 / 255.0f green:0x06 / 255.0f
													 blue:0x03 / 255.0f alpha:0.5f]
						   forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithRed:0xa1 / 255.0f green:0x06 / 255.0f
													 blue:0x03 / 255.0f alpha:0.5f]
						   forState:UIControlStateHighlighted];

		UIImage *raw = [UIImage imageNamed:@"MenuRedButton.png"];
		UIImage *rawHighlighted = [UIImage imageNamed:@"MenuRedButton_Highlighted.png"];
		if (raw)
			[button setBackgroundImage:[raw stretchableImageWithLeftCapWidth:
					(int)(raw.size.width / 2) topCapHeight:(int)(raw.size.height / 2)]
							  forState:UIControlStateNormal];
		if (rawHighlighted)
			[button setBackgroundImage:[rawHighlighted stretchableImageWithLeftCapWidth:
					(int)(rawHighlighted.size.width / 2)
					topCapHeight:(int)(rawHighlighted.size.height / 2)]
							  forState:UIControlStateHighlighted];
		if (!raw)
			button.backgroundColor = TGStorageRGB(0xc4362f);
		[button addTarget:self action:@selector(clearEverythingPressed)
		 forControlEvents:UIControlEventTouchUpInside];
		[cell.contentView addSubview:button];
	}
	UIButton *button = (UIButton *)[cell.contentView viewWithTag:772];
	button.frame = CGRectMake(9, 0, cell.contentView.bounds.size.width - 18, 45);
	button.enabled = [self canClear];
	button.alpha = [self canClear] ? 1.0f : 0.7f;
	return cell;
}

- (void)clearEverythingPressed {
	[self confirmClearKinds:@[] title:@"Clear everything"];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1 || indexPath.row == 3 || ![self canClear])
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
	[self confirmClearKinds:kinds title:[[tableView cellForRowAtIndexPath:indexPath] textLabel].text];
}

- (void)confirmClearKinds:(NSArray *)kinds title:(NSString *)title {
	if (![self canClear])
		return;
	self.pendingKinds = kinds ? kinds : @[];
	self.pendingTitle = title.length ? title : @"Clear";

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:nil];
	[sheet addButtonWithTitle:self.pendingTitle];
	sheet.destructiveButtonIndex = 0;
	[sheet addButtonWithTitle:@"Cancel"];
	sheet.cancelButtonIndex = 1;
	if (self.tabBarController.tabBar)
		[sheet showFromTabBar:self.tabBarController.tabBar];
	else
		[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet
		clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex != actionSheet.destructiveButtonIndex)
		return;
	NSArray *kinds = self.pendingKinds;
	self.pendingKinds = nil;
	self.pendingTitle = nil;
	[self clearKinds:kinds];
}

- (void)clearKinds:(NSArray *)kinds {
	if (self.working || !kinds)
		return;

	self.working = YES;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] clearCacheOfTypes:kinds completion:^(long long freed){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.working)
			return;
		[NSObject cancelPreviousPerformRequestsWithTarget:strongSelf
												 selector:@selector(clearTimedOut)
												   object:nil];
		strongSelf.working = NO;
		[strongSelf refresh];
		[strongSelf.tableView reloadData];

		NSString *message = freed > 0
				? [NSString stringWithFormat:@"Freed %@.", TGHumanSize(freed)]
				: @"There was nothing to clear.";
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Storage"
				message:message
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}];

	[self performSelector:@selector(clearTimedOut) withObject:nil afterDelay:60.0];
}

- (void)clearTimedOut {
	if (!self.working)
		return;
	self.working = NO;
	[self.tableView reloadData];
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Storage"
			message:@"Clearing the cache is taking too long. Please try again."
		   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

@end

// vim:ft=objc

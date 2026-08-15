#import "TGSessionsViewController.h"
#import "TGClient.h"
#import "TGClient+Privacy.h"
#import "TGClient+Account.h"
#import "TGTheme.h"
#import "TGActionSheet.h"

@class TGSessionDetailViewController;

@protocol TGSessionDetailDelegate <NSObject>
- (void)sessionDetailDidChangeSessions:(TGSessionDetailViewController *)controller;
@end

@interface TGSessionDetailViewController : UITableViewController
@property (nonatomic, weak) id<TGSessionDetailDelegate> detailDelegate;
- (instancetype)initWithSession:(NSDictionary *)session;
@end

#define TGSessionsRGB(rgb) [UIColor colorWithRed:(((rgb) >> 16) & 0xff) / 255.0f \
									   green:(((rgb) >> 8) & 0xff) / 255.0f \
										blue:((rgb) & 0xff) / 255.0f alpha:1.0f]

static const NSInteger TGSessionsHairlineTag = 7701;

static CGFloat TGSessionsRetinaPixel(void) {
	return [UIScreen mainScreen].scale > 1.0f ? 0.5f : 0.0f;
}

static UIColor *TGSessionsListBackground(void) {
	TGTheme *theme = [TGTheme shared];
	if (theme.isFlat || theme.isDark || theme.importedName)
		return [theme listBackgroundColour];
	UIImage *pattern = [UIImage imageNamed:@"SettingsBackground.png"];
	if (pattern)
		return [UIColor colorWithPatternImage:pattern];
	return [theme listBackgroundColour];
}

static void TGSessionsApplyBackground(UITableView *tableView) {
	tableView.backgroundView = nil;
	tableView.opaque = NO;
	tableView.backgroundColor = TGSessionsListBackground();
}

static UIView *TGSessionsHeaderView(NSString *title, CGFloat width) {
	TGTheme *theme = [TGTheme shared];
	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 46)];
	container.backgroundColor = [UIColor clearColor];
	container.opaque = NO;

	UILabel *label = [[UILabel alloc] init];
	label.text = title;
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont boldSystemFontOfSize:17];
	label.textColor = theme.isDark ? [theme sectionHeaderColour]
								   : TGSessionsRGB(0x697487);
	if (!theme.isDark && !theme.isFlat){
		label.shadowColor = TGSessionsRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 21, 16);
	[container addSubview:label];
	return container;
}

static CGFloat TGSessionsCommentHeight(NSString *text, CGFloat width) {
	CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:14]
				   constrainedToSize:CGSizeMake(width - 12 * 2, 1000)
					   lineBreakMode:NSLineBreakByWordWrapping];
	return size.height + 7 * 2;
}

static UIView *TGSessionsCommentView(NSString *text, CGFloat width) {
	TGTheme *theme = [TGTheme shared];
	CGFloat height = TGSessionsCommentHeight(text, width);

	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	container.backgroundColor = [UIColor clearColor];
	container.opaque = NO;

	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(1, 7, width - 2, height - 14)];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleHeight;
	label.text = text;
	label.font = [UIFont systemFontOfSize:14];
	label.backgroundColor = [UIColor clearColor];
	label.contentMode = UIViewContentModeCenter;
	label.textAlignment = NSTextAlignmentCenter;
	label.lineBreakMode = NSLineBreakByWordWrapping;
	label.numberOfLines = 0;
	label.textColor = theme.isDark ? [theme sectionHeaderColour]
								   : TGSessionsRGB(0x697487);
	if (!theme.isDark && !theme.isFlat){
		label.shadowColor = TGSessionsRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[container addSubview:label];
	return container;
}

static UIView *TGSessionsDisclosureView(void) {
	UIImage *image = [UIImage imageNamed:@"MenuDisclosureIndicator.png"];
	if (!image)
		return nil;
	UIImage *highlighted = [UIImage imageNamed:@"MenuDisclosureIndicator_Highlighted.png"];
	UIImageView *view = [[UIImageView alloc] initWithImage:image
										  highlightedImage:highlighted];
	view.frame = CGRectMake(0, 0, image.size.width, image.size.height);
	return view;
}

@interface TGSessionsViewController () <TGSessionDetailDelegate>
@property (nonatomic, strong) NSArray *sessions;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, assign) long long pendingTermination;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL refreshing;
@property (nonatomic, assign) NSInteger ttlDays;
@end

@implementation TGSessionsViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Devices";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	TGSessionsApplyBackground(self.tableView);
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

	[self refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.currentActionSheet){
		[self.currentActionSheet dismissWithClickedButtonIndex:
				self.currentActionSheet.cancelButtonIndex animated:NO];
		self.currentActionSheet = nil;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(refresh) object:nil];
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)refresh {
	if (self.refreshing)
		return;
	self.refreshing = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] activeSessionsWithCompletion:^(NSArray *sessions, NSInteger inactiveTtlDays){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.refreshing = NO;
		strongSelf.loaded = YES;
		strongSelf.ttlDays = inactiveTtlDays;
		strongSelf.sessions = sessions ?: [NSArray array];
		[strongSelf.tableView reloadData];
	}];
}

- (NSString *)stringIn:(NSDictionary *)session forKey:(NSString *)key {
	id value = session[key];
	if (![value isKindOfClass:[NSString class]])
		return @"";
	return [value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceCharacterSet]];
}

- (NSString *)titleForSession:(NSDictionary *)session {
	NSString *app = [self stringIn:session forKey:@"appName"];
	if (!app.length)
		app = [self stringIn:session forKey:@"name"];
	if (!app.length)
		app = @"Unknown application";
	NSString *version = [self stringIn:session forKey:@"appVersion"];
	if (version.length)
		return [NSString stringWithFormat:@"%@ %@", app, version];
	return app;
}

- (NSString *)subtitleForSession:(NSDictionary *)session {
	NSString *device = [self stringIn:session forKey:@"deviceModel"];
	NSString *platform = [self stringIn:session forKey:@"platform"];
	NSString *ip = [self stringIn:session forKey:@"ip"];
	NSString *location = [self stringIn:session forKey:@"location"];

	NSMutableArray *first = [NSMutableArray array];
	if (device.length)
		[first addObject:device];
	if (platform.length)
		[first addObject:platform];

	NSMutableArray *second = [NSMutableArray array];
	if (ip.length)
		[second addObject:ip];
	if (location.length)
		[second addObject:location];

	if ([session[@"isCurrent"] boolValue]){
		[second addObject:@"online"];
	} else {
		NSString *seen = [self lastActiveTextForSession:session];
		if (seen.length)
			[second addObject:seen];
	}

	NSMutableArray *lines = [NSMutableArray array];
	if (first.count)
		[lines addObject:[first componentsJoinedByString:@", "]];
	if (second.count)
		[lines addObject:[second componentsJoinedByString:@" - "]];
	return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)lastActiveTextForSession:(NSDictionary *)session {
	long long stamp = [session[@"lastActive"] longLongValue];
	if (stamp <= 0)
		return nil;

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)stamp];
	NSTimeInterval age = -[date timeIntervalSinceNow];
	if (age < 0)
		age = 0;

	if (age < 60)
		return @"just now";

	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	if (age < 60 * 60 * 12){
		formatter.dateStyle = NSDateFormatterNoStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
	} else {
		formatter.dateStyle = NSDateFormatterShortStyle;
		formatter.timeStyle = NSDateFormatterNoStyle;
	}
	return [formatter stringFromDate:date];
}

- (NSArray *)othersOnly {
	NSMutableArray *others = [NSMutableArray array];
	for (NSDictionary *session in self.sessions)
		if (![session[@"isCurrent"] boolValue])
			[others addObject:session];
	return others;
}

- (NSDictionary *)currentSession {
	for (NSDictionary *session in self.sessions)
		if ([session[@"isCurrent"] boolValue])
			return session;
	return nil;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	NSIndexPath *selected = [self.tableView indexPathForSelectedRow];
	if (selected)
		[self.tableView deselectRowAtIndexPath:selected animated:YES];
	if (self.loaded)
		[self refresh];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 4;
}

- (NSString *)headerTitleForSection:(NSInteger)section {
	if (section == 0) return [self currentSession] ? @"This device" : nil;
	if (section == 1) return [self othersOnly].count ? @"Active sessions" : nil;
	if (section == 3) return self.loaded ? @"Automatically terminate old sessions" : nil;
	return nil;
}

- (NSString *)footerTitleForSection:(NSInteger)section {
	if (section == 3){
		if (!self.loaded)
			return nil;
		return @"If you do not log in from another device for this "
			   @"period of time, that session ends by itself.";
	}
	if (section != 1)
		return nil;
	if (!self.loaded)
		return @"Loading...";
	if ([self othersOnly].count)
		return @"Tap a session to see its details, or swipe it away to terminate it.";
	return @"You have no other active sessions.";
}

- (NSArray *)ttlOptions {
	return [NSArray arrayWithObjects:
			[NSNumber numberWithInteger:7],
			[NSNumber numberWithInteger:30],
			[NSNumber numberWithInteger:90],
			[NSNumber numberWithInteger:180], nil];
}

- (NSString *)ttlTitleForDays:(NSInteger)days {
	if (days <= 0) return @"Never";
	if (days <= 7) return @"1 week";
	if (days <= 30) return @"1 month";
	if (days <= 90) return @"3 months";
	return @"6 months";
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return 14;
	return 46;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return nil;
	return TGSessionsHeaderView(title, tableView.bounds.size.width);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return 1;
	return TGSessionsCommentHeight(title, tableView.bounds.size.width);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return nil;
	return TGSessionsCommentView(title, tableView.bounds.size.width);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2)
		return 45;
	if (indexPath.section == 3)
		return 44;
	return 58;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return [self currentSession] ? 1 : 0;
	if (section == 1)
		return [self othersOnly].count;
	if (section == 3)
		return self.loaded ? 1 : 0;
	return [self othersOnly].count ? 1 : 0;
}

- (NSDictionary *)sessionAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0)
		return [self currentSession];
	NSArray *others = [self othersOnly];
	if (indexPath.section == 1 && indexPath.row < (NSInteger)others.count)
		return others[indexPath.row];
	return nil;
}

- (UIImage *)redPlateHighlighted:(BOOL)highlighted {
	UIImage *image = [UIImage imageNamed:highlighted ? @"MenuRedButton_Highlighted.png"
													 : @"MenuRedButton.png"];
	if (!image)
		return nil;
	return [image stretchableImageWithLeftCapWidth:(int)(image.size.width / 2)
									  topCapHeight:(int)(image.size.height / 2)];
}

- (UITableViewCell *)terminateAllCellForTable:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"action"];
		cell.backgroundColor = [UIColor clearColor];
		cell.backgroundView = [[UIView alloc] init];
		cell.backgroundView.backgroundColor = [UIColor clearColor];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.tag = TGSessionsHairlineTag + 1;
		button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		UIImage *plate = [self redPlateHighlighted:NO];
		UIImage *platePressed = [self redPlateHighlighted:YES];
		if (plate)
			[button setBackgroundImage:plate forState:UIControlStateNormal];
		else
			button.backgroundColor = TGSessionsRGB(0xc4362f);
		if (platePressed)
			[button setBackgroundImage:platePressed forState:UIControlStateHighlighted];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleShadowColor:[UIColor colorWithRed:0xa1 / 255.0f
													green:0x06 / 255.0f
													 blue:0x03 / 255.0f alpha:0.5f]
						   forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithRed:0xa1 / 255.0f
													green:0x06 / 255.0f
													 blue:0x03 / 255.0f alpha:0.5f]
						   forState:UIControlStateHighlighted];
		button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		[button setTitle:@"Terminate All Other Sessions" forState:UIControlStateNormal];
		[button addTarget:self action:@selector(confirmTerminateAll)
		 forControlEvents:UIControlEventTouchUpInside];
		[cell.contentView addSubview:button];
	}
	return cell;
}

- (UITableViewCell *)ttlCellForTable:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ttl"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"ttl"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = @"If inactive for";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
	cell.textLabel.highlightedTextColor = [UIColor whiteColor];
	cell.detailTextLabel.text = [self ttlTitleForDays:self.ttlDays];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] cellDetailColour] : TGSessionsRGB(0x356596);
	cell.detailTextLabel.highlightedTextColor = [UIColor whiteColor];
	UIView *disclosure = TGSessionsDisclosureView();
	if (disclosure){
		cell.accessoryView = disclosure;
		cell.accessoryType = UITableViewCellAccessoryNone;
	} else {
		cell.accessoryView = nil;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2)
		return [self terminateAllCellForTable:tableView];
	if (indexPath.section == 3)
		return [self ttlCellForTable:tableView];

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
		UIView *hairline = [[UIView alloc] initWithFrame:CGRectZero];
		hairline.tag = TGSessionsHairlineTag;
		hairline.autoresizingMask = UIViewAutoresizingFlexibleWidth
				| UIViewAutoresizingFlexibleTopMargin;
		[cell.contentView addSubview:hairline];
	}

	BOOL dark = [[TGTheme shared] isDark];
	NSDictionary *session = [self sessionAtIndexPath:indexPath];
	NSString *name = session ? [self titleForSession:session] : @"Unknown application";

	[[TGTheme shared] styleCell:cell];

	cell.textLabel.text = name;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.textColor = dark ? [[TGTheme shared] primaryTextColour]
									: [UIColor blackColor];
	cell.textLabel.highlightedTextColor = [UIColor whiteColor];
	cell.detailTextLabel.text = session ? [self subtitleForSession:session] : @"";
	cell.detailTextLabel.numberOfLines = 2;
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13 + TGSessionsRetinaPixel()];
	cell.detailTextLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
										  : TGSessionsRGB(0x888888);
	cell.selectionStyle = indexPath.section == 0
			? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
	UIView *disclosure = indexPath.section == 1 ? TGSessionsDisclosureView() : nil;
	cell.accessoryView = disclosure;
	cell.accessoryType = (indexPath.section == 1 && !disclosure)
			? UITableViewCellAccessoryDisclosureIndicator
			: UITableViewCellAccessoryNone;

	UIView *hairline = [cell.contentView viewWithTag:TGSessionsHairlineTag];
	NSInteger rows = [self tableView:tableView numberOfRowsInSection:indexPath.section];
	hairline.backgroundColor = [[TGTheme shared] separatorColour];
	hairline.hidden = indexPath.row + 1 >= rows;
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	CGRect bounds = cell.contentView.bounds;
	if (indexPath.section == 2){
		UIView *button = [cell.contentView viewWithTag:TGSessionsHairlineTag + 1];
		button.frame = CGRectMake(9, 0, bounds.size.width - 18, 45);
		return;
	}
	UIView *hairline = [cell.contentView viewWithTag:TGSessionsHairlineTag];
	CGFloat thickness = 1.0f / [UIScreen mainScreen].scale;
	hairline.frame = CGRectMake(10, bounds.size.height - thickness,
			bounds.size.width - 10, thickness);
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 1;
}

- (NSString *)tableView:(UITableView *)tableView
		titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	return @"Terminate";
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;
	NSDictionary *session = [self sessionAtIndexPath:indexPath];
	if (!session)
		return;
	[self terminateSessions:[NSArray arrayWithObject:session]];
}

- (void)terminateSessions:(NSArray *)targets {
	if (!targets.count)
		return;

	NSMutableArray *remaining = [NSMutableArray arrayWithArray:self.sessions ?: [NSArray array]];
	for (NSDictionary *session in targets){
		long long sessionId = [session[@"id"] longLongValue];
		if (!sessionId)
			continue;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] terminateSession:sessionId completion:^(BOOL ok){
			if (!ok)
				[weakSelf refresh];
		}];
		[remaining removeObject:session];
	}
	self.sessions = remaining;
	[self.tableView reloadData];

	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(refresh) object:nil];
	[self performSelector:@selector(refresh) withObject:nil afterDelay:1.0];
}

#pragma mark - destructive confirmation

- (UIView *)sheetHostView {
	if (self.navigationController.view)
		return self.navigationController.view;
	return self.view;
}

- (void)performTerminateAll {
	NSDictionary *current = [self currentSession];
	self.sessions = current ? [NSArray arrayWithObject:current] : [NSArray array];
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] terminateAllOtherSessionsWithCompletion:^(__unused BOOL ok){
		[weakSelf refresh];
	}];
}

- (void)confirmTerminateAll {
	if (![self othersOnly].count)
		return;
	self.pendingTermination = 0;

	NSArray *actions = [NSArray arrayWithObjects:
			[[TGActionSheetAction alloc] initWithTitle:@"Terminate All Other Sessions"
												action:@"terminateAll"
												  type:TGActionSheetActionTypeDestructive],
			[[TGActionSheetAction alloc] initWithTitle:@"Cancel"
												action:@"cancel"
												  type:TGActionSheetActionTypeCancel],
			nil];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:nil actions:actions
			actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				if ([action isEqualToString:@"terminateAll"])
					[strongSelf performTerminateAll];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

- (void)showTtlPicker {
	NSMutableArray *actions = [NSMutableArray array];
	for (NSNumber *option in [self ttlOptions]){
		NSInteger days = [option integerValue];
		NSString *title = [self ttlTitleForDays:days];
		if (days == self.ttlDays)
			title = [NSString stringWithFormat:@"%@ ✓", title];
		[actions addObject:[[TGActionSheetAction alloc]
				initWithTitle:title
					   action:[NSString stringWithFormat:@"ttl%d", (int)days]]];
	}
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Cancel"
														  action:@"cancel"
															type:TGActionSheetActionTypeCancel]];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc]
			initWithTitle:@"Terminate sessions inactive for"
				  actions:actions
			  actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				if (![action hasPrefix:@"ttl"])
					return;
				NSInteger days = [[action substringFromIndex:3] integerValue];
				if (days <= 0 || days == strongSelf.ttlDays)
					return;
				NSInteger previous = strongSelf.ttlDays;
				strongSelf.ttlDays = days;
				[strongSelf.tableView reloadData];
				[[TGClient shared] setInactiveSessionTtlDays:days completion:^(BOOL ok){
					__strong typeof(weakSelf) inner = weakSelf;
					if (ok || !inner)
						return;
					inner.ttlDays = previous;
					[inner.tableView reloadData];
				}];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 3){
		[self showTtlPicker];
		return;
	}
	if (indexPath.section != 1)
		return;

	NSDictionary *session = [self sessionAtIndexPath:indexPath];
	if (!session)
		return;
	if (![session[@"id"] longLongValue])
		return;

	TGSessionDetailViewController *detail =
			[[TGSessionDetailViewController alloc] initWithSession:session];
	detail.detailDelegate = self;
	[self.navigationController pushViewController:detail animated:YES];
}

- (void)sessionDetailDidChangeSessions:(__unused TGSessionDetailViewController *)controller {
	[self refresh];
}

@end

@interface TGSessionDetailViewController ()
@property (nonatomic, strong) NSDictionary *session;
@property (nonatomic, strong) NSArray *infoRows;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, assign) BOOL acceptsCalls;
@property (nonatomic, assign) BOOL acceptsSecrets;
@property (nonatomic, assign) BOOL isCurrent;
@property (nonatomic, assign) BOOL unconfirmed;
@property (nonatomic, assign) long long sessionId;
@end

@implementation TGSessionDetailViewController

- (instancetype)initWithSession:(NSDictionary *)session {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		_session = session ?: [NSDictionary dictionary];
		_sessionId = [_session[@"id"] longLongValue];
		[self adoptSession:_session];
	}
	return self;
}

- (NSString *)stringIn:(NSDictionary *)session forKey:(NSString *)key {
	id value = session[key];
	if (![value isKindOfClass:[NSString class]])
		return @"";
	return [value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceCharacterSet]];
}

- (NSString *)firstStringIn:(NSDictionary *)session keys:(NSArray *)keys {
	for (NSString *key in keys){
		NSString *value = [self stringIn:session forKey:key];
		if (value.length)
			return value;
	}
	return @"";
}

- (NSString *)dateTextIn:(NSDictionary *)session keys:(NSArray *)keys {
	long long stamp = 0;
	for (NSString *key in keys){
		stamp = [session[key] longLongValue];
		if (stamp > 0)
			break;
	}
	if (stamp <= 0)
		return @"";
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)stamp];
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateStyle = NSDateFormatterMediumStyle;
	formatter.timeStyle = NSDateFormatterShortStyle;
	return [formatter stringFromDate:date];
}

- (void)adoptSession:(NSDictionary *)session {
	if (!session.count)
		return;
	self.session = session;
	self.acceptsCalls = [session[@"canAcceptCalls"] boolValue];
	self.acceptsSecrets = [session[@"canAcceptSecretChats"] boolValue];
	self.isCurrent = [session[@"isCurrent"] boolValue];
	self.unconfirmed = [session[@"isUnconfirmed"] boolValue];

	NSMutableArray *rows = [NSMutableArray array];
	NSString *app = [self firstStringIn:session keys:
			[NSArray arrayWithObjects:@"appName", @"name", nil]];
	NSString *version = [self stringIn:session forKey:@"appVersion"];
	if (app.length && version.length)
		app = [NSString stringWithFormat:@"%@ %@", app, version];
	if (app.length)
		[rows addObject:[NSArray arrayWithObjects:@"Application", app, nil]];

	NSString *device = [self stringIn:session forKey:@"deviceModel"];
	if (device.length)
		[rows addObject:[NSArray arrayWithObjects:@"Device", device, nil]];

	NSString *platform = [self firstStringIn:session keys:
			[NSArray arrayWithObjects:@"platform", @"systemVersion", nil]];
	if (platform.length)
		[rows addObject:[NSArray arrayWithObjects:@"System", platform, nil]];

	NSString *ip = [self firstStringIn:session keys:
			[NSArray arrayWithObjects:@"ipAddress", @"ip", nil]];
	if (ip.length)
		[rows addObject:[NSArray arrayWithObjects:@"IP", ip, nil]];

	NSString *location = [self stringIn:session forKey:@"location"];
	if (location.length)
		[rows addObject:[NSArray arrayWithObjects:@"Location", location, nil]];

	NSString *login = [self dateTextIn:session keys:
			[NSArray arrayWithObjects:@"loginDate", nil]];
	if (login.length)
		[rows addObject:[NSArray arrayWithObjects:@"Logged in", login, nil]];

	if (!self.isCurrent){
		NSString *seen = [self dateTextIn:session keys:
				[NSArray arrayWithObjects:@"lastActiveDate", @"lastActive", nil]];
		if (seen.length)
			[rows addObject:[NSArray arrayWithObjects:@"Last active", seen, nil]];
	}
	self.infoRows = rows;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Session";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	TGSessionsApplyBackground(self.tableView);
	self.tableView.rowHeight = 44;

	UISwipeGestureRecognizer *back = [[UISwipeGestureRecognizer alloc]
			initWithTarget:self action:@selector(performSwipeBack)];
	back.direction = UISwipeGestureRecognizerDirectionRight;
	[self.tableView addGestureRecognizer:back];

	[self reload];
}

- (void)performSwipeBack {
	if (self.navigationController.viewControllers.count > 1)
		[self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	NSIndexPath *selected = [self.tableView indexPathForSelectedRow];
	if (selected)
		[self.tableView deselectRowAtIndexPath:selected animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.currentActionSheet){
		[self.currentActionSheet dismissWithClickedButtonIndex:
				self.currentActionSheet.cancelButtonIndex animated:NO];
		self.currentActionSheet = nil;
	}
}

- (void)reload {
	if (!self.sessionId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sessionInfoForId:self.sessionId
							 completion:^(NSDictionary *session){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || !session.count)
			return;
		[strongSelf adoptSession:session];
		[strongSelf.tableView reloadData];
	}];
}

- (UIView *)sheetHostView {
	if (self.navigationController.view)
		return self.navigationController.view;
	return self.view;
}

- (BOOL)showsSwitches {
	return !self.isCurrent;
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return (NSInteger)self.infoRows.count;
	if (section == 1)
		return [self showsSwitches] ? 2 : 0;
	if (self.isCurrent)
		return 0;
	return self.unconfirmed ? 2 : 1;
}

- (NSString *)headerTitleForSection:(NSInteger)section {
	if (section == 1 && [self showsSwitches])
		return @"Accepts from this session";
	return nil;
}

- (NSString *)footerTitleForSection:(NSInteger)section {
	if (section == 1 && [self showsSwitches])
		return @"Calls and secret chats can be turned off for this session "
			   @"without ending it.";
	if (section == 2 && self.unconfirmed)
		return @"You have not confirmed this login yet.";
	return nil;
}

- (CGFloat)tableView:(__unused UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return [self headerTitleForSection:section] ? 46 : 14;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return nil;
	return TGSessionsHeaderView(title, tableView.bounds.size.width);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return 1;
	return TGSessionsCommentHeight(title, tableView.bounds.size.width);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return nil;
	return TGSessionsCommentView(title, tableView.bounds.size.width);
}

- (UITableViewCell *)infoCellForTable:(UITableView *)tableView
								  row:(NSInteger)row {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"info"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"info"];
	}
	[[TGTheme shared] styleCell:cell];
	NSArray *pair = self.infoRows[row];
	cell.textLabel.text = pair[0];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
	cell.detailTextLabel.text = pair[1];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] cellDetailColour] : TGSessionsRGB(0x356596);
	cell.detailTextLabel.highlightedTextColor = [UIColor whiteColor];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)switchCellForTable:(UITableView *)tableView
									row:(NSInteger)row {
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
	cell.textLabel.text = row == 0 ? @"Calls" : @"Secret Chats";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UISwitch *toggle = (UISwitch *)cell.accessoryView;
	toggle.tag = row;
	[toggle setOn:(row == 0 ? self.acceptsCalls : self.acceptsSecrets) animated:NO];
	return cell;
}

- (UITableViewCell *)actionCellForTable:(UITableView *)tableView
								   row:(NSInteger)row {
	BOOL confirmRow = self.unconfirmed && row == 0;
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"action"];
	}
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = confirmRow ? @"Confirm Session" : @"Terminate Session";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.textLabel.textColor = confirmRow ? TGSessionsRGB(0x0779d0)
										  : TGSessionsRGB(0xc4362f);
	cell.textLabel.highlightedTextColor = [UIColor whiteColor];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0)
		return [self infoCellForTable:tableView row:indexPath.row];
	if (indexPath.section == 1)
		return [self switchCellForTable:tableView row:indexPath.row];
	return [self actionCellForTable:tableView row:indexPath.row];
}

- (void)toggleChanged:(UISwitch *)sender {
	BOOL calls = self.acceptsCalls;
	BOOL secrets = self.acceptsSecrets;
	if (sender.tag == 0)
		calls = sender.on;
	else
		secrets = sender.on;

	BOOL previousCalls = self.acceptsCalls;
	BOOL previousSecrets = self.acceptsSecrets;
	self.acceptsCalls = calls;
	self.acceptsSecrets = secrets;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setSession:self.sessionId
				   canAcceptCalls:calls
				 canAcceptSecrets:secrets
					   completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (ok || !strongSelf)
			return;
		strongSelf.acceptsCalls = previousCalls;
		strongSelf.acceptsSecrets = previousSecrets;
		[strongSelf.tableView reloadData];
	}];
}

- (void)confirmSession {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] confirmSession:self.sessionId completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (ok){
			strongSelf.unconfirmed = NO;
			[strongSelf.tableView reloadData];
			[strongSelf.detailDelegate sessionDetailDidChangeSessions:strongSelf];
		}
	}];
}

- (void)performTerminate {
	__weak typeof(self) weakSelf = self;
	id<TGSessionDetailDelegate> delegate = self.detailDelegate;
	[[TGClient shared] terminateSession:self.sessionId completion:^(__unused BOOL ok){
		[delegate sessionDetailDidChangeSessions:weakSelf];
	}];
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)confirmTerminate {
	NSArray *actions = [NSArray arrayWithObjects:
			[[TGActionSheetAction alloc] initWithTitle:@"Terminate Session"
												action:@"terminate"
												  type:TGActionSheetActionTypeDestructive],
			[[TGActionSheetAction alloc] initWithTitle:@"Cancel"
												action:@"cancel"
												  type:TGActionSheetActionTypeCancel],
			nil];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:nil actions:actions
			actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				if ([action isEqualToString:@"terminate"])
					[strongSelf performTerminate];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 2 || !self.sessionId)
		return;
	if (self.unconfirmed && indexPath.row == 0){
		[self confirmSession];
		return;
	}
	[self confirmTerminate];
}

@end

// vim:ft=objc

#import "TGSessionsViewController.h"
#import "TGClient.h"
#import "TGClient+Privacy.h"
#import "TGTheme.h"
#import "TGActionSheet.h"

#define TGSessionsRGB(rgb) [UIColor colorWithRed:(((rgb) >> 16) & 0xff) / 255.0f \
									   green:(((rgb) >> 8) & 0xff) / 255.0f \
										blue:((rgb) & 0xff) / 255.0f alpha:1.0f]

static const NSInteger TGSessionsHairlineTag = 7701;

static CGFloat TGSessionsRetinaPixel(void) {
	return [UIScreen mainScreen].scale > 1.0f ? 0.5f : 0.0f;
}

@interface TGSessionsViewController ()
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
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

	if ([self respondsToSelector:@selector(setRefreshControl:)]){
		UIRefreshControl *control = [[UIRefreshControl alloc] init];
		[control addTarget:self action:@selector(refresh)
		  forControlEvents:UIControlEventValueChanged];
		self.refreshControl = control;
	}
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
		if ([strongSelf respondsToSelector:@selector(refreshControl)])
			[strongSelf.refreshControl endRefreshing];
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

	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	if (age < 60)
		return @"just now";
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
}

#pragma mark - captions

- (UIColor *)captionColour {
	return [[TGTheme shared] isDark] ? [[TGTheme shared] sectionHeaderColour]
									 : TGSessionsRGB(0x697487);
}

- (UILabel *)captionLabel {
	UILabel *label = [[UILabel alloc] init];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont systemFontOfSize:14];
	label.textColor = [self captionColour];
	if (![[TGTheme shared] isFlat] && ![[TGTheme shared] isDark]){
		label.shadowColor = TGSessionsRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	return label;
}

- (CGFloat)captionHeightFor:(NSString *)text width:(CGFloat)width {
	CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:14]
				   constrainedToSize:CGSizeMake(width, 1000)
					   lineBreakMode:NSLineBreakByWordWrapping];
	return size.height;
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
		return @"Tap a session to terminate it, or swipe it away.";
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
	if (days <= 7) return @"1 week";
	if (days <= 30) return @"1 month";
	if (days <= 90) return @"3 months";
	return @"6 months";
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return 12;
	return [self captionHeightFor:title width:tableView.bounds.size.width - 42] + 18;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return nil;

	CGFloat width = tableView.bounds.size.width - 42;
	CGFloat height = [self captionHeightFor:title width:width];

	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, height + 18)];
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [self captionLabel];
	label.numberOfLines = 0;
	label.text = title;
	label.frame = CGRectMake(21, 6 + TGSessionsRetinaPixel(), width, height);
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return 1;
	return [self captionHeightFor:title width:tableView.bounds.size.width - 42] + 14;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return nil;

	CGFloat width = tableView.bounds.size.width - 42;
	CGFloat height = [self captionHeightFor:title width:width];

	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, height + 14)];
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [self captionLabel];
	label.numberOfLines = 0;
	label.text = title;
	label.frame = CGRectMake(21, 7 + TGSessionsRetinaPixel(), width, height);
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2)
		return 46;
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
			? [[TGTheme shared] primaryTextColour] : TGSessionsRGB(0x516691);
	cell.detailTextLabel.text = [self ttlTitleForDays:self.ttlDays];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:17];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
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
									: TGSessionsRGB(0x516691);
	cell.detailTextLabel.text = session ? [self subtitleForSession:session] : @"";
	cell.detailTextLabel.numberOfLines = 2;
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13 + TGSessionsRetinaPixel()];
	cell.detailTextLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
										  : TGSessionsRGB(0x888888);
	cell.selectionStyle = indexPath.section == 0
			? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;

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
		button.frame = CGRectMake(0, 0.5f, bounds.size.width, 45);
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
	long long sessionId = [session[@"id"] longLongValue];
	if (!sessionId)
		return;
	self.pendingTermination = sessionId;

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
				if (![action isEqualToString:@"terminate"])
					return;
				long long pending = strongSelf.pendingTermination;
				strongSelf.pendingTermination = 0;
				for (NSDictionary *candidate in [strongSelf othersOnly]){
					if ([candidate[@"id"] longLongValue] == pending){
						[strongSelf terminateSessions:
								[NSArray arrayWithObject:candidate]];
						return;
					}
				}
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

@end

// vim:ft=objc

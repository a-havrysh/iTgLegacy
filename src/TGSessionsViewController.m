#import "TGSessionsViewController.h"
#import "TGClient.h"
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
	[[TGClient shared] sessionsWithCompletion:^(NSArray *sessions){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.refreshing = NO;
		strongSelf.loaded = YES;
		strongSelf.sessions = sessions ?: [NSArray array];
		[strongSelf.tableView reloadData];
		if ([strongSelf respondsToSelector:@selector(refreshControl)])
			[strongSelf.refreshControl endRefreshing];
	}];
}

- (NSString *)subtitleForSession:(NSDictionary *)session {
	NSString *platform = session[@"platform"];
	if (![platform isKindOfClass:[NSString class]])
		platform = @"";
	platform = [platform stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceCharacterSet]];

	NSString *ip = session[@"ip"];
	if (![ip isKindOfClass:[NSString class]])
		ip = @"";

	NSMutableArray *parts = [NSMutableArray array];
	if (platform.length)
		[parts addObject:platform];
	if (ip.length)
		[parts addObject:ip];

	if ([session[@"isCurrent"] boolValue]){
		if (!parts.count)
			return @"online";
		[parts addObject:@"online"];
	} else {
		NSString *seen = [self lastActiveTextForSession:session];
		if (seen.length)
			[parts addObject:seen];
	}
	return [parts componentsJoinedByString:@" - "];
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
	return 3;
}

- (NSString *)headerTitleForSection:(NSInteger)section {
	if (section == 0) return [self currentSession] ? @"This device" : nil;
	if (section == 1) return [self othersOnly].count ? @"Active sessions" : nil;
	return nil;
}

- (NSString *)footerTitleForSection:(NSInteger)section {
	if (section != 1)
		return nil;
	if (!self.loaded)
		return @"Loading...";
	if ([self othersOnly].count)
		return @"Tap a session to terminate it, or swipe it away.";
	return @"You have no other active sessions.";
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
	return indexPath.section == 2 ? 46 : 44;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return [self currentSession] ? 1 : 0;
	if (section == 1)
		return [self othersOnly].count;
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2)
		return [self terminateAllCellForTable:tableView];

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
	NSString *name = session[@"name"];
	if (![name isKindOfClass:[NSString class]] || !name.length)
		name = @"Unknown application";

	[[TGTheme shared] styleCell:cell];

	cell.textLabel.text = name;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.textColor = dark ? [[TGTheme shared] primaryTextColour]
									: TGSessionsRGB(0x516691);
	cell.detailTextLabel.text = session ? [self subtitleForSession:session] : @"";
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
		[[TGClient shared] terminateSession:sessionId];
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
					[strongSelf terminateSessions:[strongSelf othersOnly]];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

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

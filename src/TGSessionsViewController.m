#import "TGSessionsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"

#define TGSessionsRGB(rgb) [UIColor colorWithRed:(((rgb) >> 16) & 0xff) / 255.0f \
									   green:(((rgb) >> 8) & 0xff) / 255.0f \
										blue:((rgb) & 0xff) / 255.0f alpha:1.0f]

@interface TGSessionsViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *sessions;
@property (nonatomic, assign) long long pendingTermination;
@property (nonatomic, assign) BOOL terminatingAll;
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
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

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

/// Current session first, the way every client orders this list.
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

/// Settings has its own navigation controller, and nothing was styling
/// its bar - an imported theme stopped at the top of the screen.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
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
		return @"Tap a session to sign that device out, or swipe it away.";
	return @"You have no other active sessions.";
}

- (UILabel *)captionLabel {
	UILabel *label = [[UILabel alloc] init];
	label.backgroundColor = [UIColor clearColor];
	label.textColor = [[TGTheme shared] sectionHeaderColour];
	if (![[TGTheme shared] isFlat]){
		label.shadowColor = TGSessionsRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	return label;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return [self headerTitleForSection:section] ? 46 : 14;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return nil;

	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, 46)];
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [self captionLabel];
	label.font = [UIFont boldSystemFontOfSize:17];
	label.text = title;
	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 21, 16);
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return 1;

	CGSize size = [title sizeWithFont:[UIFont systemFontOfSize:14]
				   constrainedToSize:CGSizeMake(tableView.bounds.size.width - 42, 1000)
					   lineBreakMode:NSLineBreakByWordWrapping];
	return size.height + 14;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return nil;

	CGFloat width = tableView.bounds.size.width - 42;
	CGSize size = [title sizeWithFont:[UIFont systemFontOfSize:14]
				   constrainedToSize:CGSizeMake(width, 1000)
					   lineBreakMode:NSLineBreakByWordWrapping];

	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, size.height + 14)];
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [self captionLabel];
	label.font = [UIFont systemFontOfSize:14];
	label.numberOfLines = 0;
	label.text = title;
	label.frame = CGRectMake(21, 7, width, size.height);
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 44;
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:@"action"];
		[[TGTheme shared] styleCell:cell];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.textLabel.textColor = TGSessionsRGB(0xd12b2b);
		cell.textLabel.text = @"Terminate all other sessions";
		cell.detailTextLabel.text = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];

	NSDictionary *session = [self sessionAtIndexPath:indexPath];
	NSString *name = session[@"name"];
	if (![name isKindOfClass:[NSString class]] || !name.length)
		name = @"Unknown application";
	cell.textLabel.text = name;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	[[TGTheme shared] styleCell:cell];
	cell.detailTextLabel.text = session ? [self subtitleForSession:session] : @"";
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.selectionStyle = indexPath.section == 0
			? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 1;
}

- (NSString *)tableView:(UITableView *)tableView
		titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	return @"Sign out";
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 2){
		if (![self othersOnly].count)
			return;
		self.terminatingAll = YES;
		self.pendingTermination = 0;
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Terminate sessions"
				message:@"Sign out of all devices except this one?"
			   delegate:self cancelButtonTitle:@"Cancel"
			  otherButtonTitles:@"Terminate", nil];
		[alert show];
		return;
	}

	if (indexPath.section != 1)
		return;

	NSDictionary *session = [self sessionAtIndexPath:indexPath];
	if (!session)
		return;
	self.terminatingAll = NO;
	self.pendingTermination = [session[@"id"] longLongValue];
	if (!self.pendingTermination)
		return;

	NSString *name = session[@"name"];
	if (![name isKindOfClass:[NSString class]] || !name.length)
		name = @"this session";

	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Sign out"
			message:[NSString stringWithFormat:@"Sign %@ out of this account?", name]
		   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Sign out", nil];
	[alert show];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
	BOOL all = self.terminatingAll;
	long long sessionId = self.pendingTermination;
	self.terminatingAll = NO;
	self.pendingTermination = 0;

	if (index == alert.cancelButtonIndex)
		return;

	if (all){
		[self terminateSessions:[self othersOnly]];
		return;
	}
	if (!sessionId)
		return;
	for (NSDictionary *session in [self othersOnly]){
		if ([session[@"id"] longLongValue] == sessionId){
			[self terminateSessions:[NSArray arrayWithObject:session]];
			return;
		}
	}
}

@end

// vim:ft=objc

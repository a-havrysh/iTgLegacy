#import "TGSessionsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"

@interface TGSessionsViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *sessions;
@property (nonatomic, assign) long long pendingTermination;
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
	self.tableView.separatorColor = [[TGTheme shared] bubbleBorderColour];
	[self refresh];
}

- (void)refresh {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sessionsWithCompletion:^(NSArray *sessions){
		weakSelf.sessions = sessions;
		[weakSelf.tableView reloadData];
	}];
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
	return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"This device";
	return [self othersOnly].count ? @"Active sessions" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return section == 1 && [self othersOnly].count
			? @"Tap a session to sign that device out." : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? ([self currentSession] ? 1 : 0) : [self othersOnly].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];

	NSDictionary *session = indexPath.section == 0
			? [self currentSession] : [self othersOnly][indexPath.row];
	cell.textLabel.text = session[@"name"];
	[[TGTheme shared] styleCell:cell];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@",
			session[@"platform"], session[@"ip"]];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.selectionStyle = indexPath.section == 0
			? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1)
		return;

	NSDictionary *session = [self othersOnly][indexPath.row];
	self.pendingTermination = [session[@"id"] longLongValue];

	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Sign out"
			message:[NSString stringWithFormat:@"Sign %@ out of this account?",
					session[@"name"]]
		   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Sign out", nil];
	[alert show];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
	if (index == alert.cancelButtonIndex || !self.pendingTermination)
		return;
	[[TGClient shared] terminateSession:self.pendingTermination];
	self.pendingTermination = 0;
	// The server needs a moment before the list reflects it.
	[self performSelector:@selector(refresh) withObject:nil afterDelay:1.0];
}

@end

// vim:ft=objc

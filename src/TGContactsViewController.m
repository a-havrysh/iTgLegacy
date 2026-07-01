#import "TGContactsViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"

@interface TGContactsViewController ()
@property (nonatomic, strong) NSArray *users;
@end

@implementation TGContactsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Contacts";
	self.users = @[];
	self.tableView.rowHeight = 52;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] contactsWithCompletion:^(NSArray *users){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		// Alphabetical, the way a contact list is expected to read.
		me.users = [users sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
			return [a[@"first_name"] localizedCaseInsensitiveCompare:b[@"first_name"]];
		}];
		[me.tableView reloadData];
		NSLog(@"TDLIB CONTACTS: %lu", (unsigned long)me.users.count);
	}];
}

static NSString *TGContactName(NSDictionary *u) {
	NSString *first = u[@"first_name"] ?: @"";
	NSString *last  = u[@"last_name"] ?: @"";
	NSString *name  = [[NSString stringWithFormat:@"%@ %@", first, last]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (name.length)
		return name;
	if ([u[@"username"] length])
		return [NSString stringWithFormat:@"@%@", u[@"username"]];
	return u[@"phone"] ?: @"";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.users.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGContactCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	NSDictionary *u = self.users[indexPath.row];
	cell.textLabel.text = TGContactName(u);
	cell.detailTextLabel.text = [u[@"phone"] length]
		? [NSString stringWithFormat:@"+%@", u[@"phone"]] : @"";
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSDictionary *u = self.users[indexPath.row];
	NSString *name = TGContactName(u);
	__weak typeof(self) weakSelf = self;

	[[TGClient shared] privateChatWithUser:[u[@"id"] longLongValue]
								completion:^(int64_t chatId){
		TGContactsViewController *me = weakSelf;
		if (!me || chatId == 0)
			return;
		TGChatViewController *vc = [[TGChatViewController alloc] init];
		vc.chatId = chatId;
		vc.chatTitle = name;
		vc.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:vc animated:YES];
	}];
}

@end

// vim:ft=objc

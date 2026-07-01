#import "TGTopicsViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"

@interface TGTopicsViewController ()
@property (nonatomic, strong) NSArray *topics;
@end

@implementation TGTopicsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = self.chatTitle ?: @"Topics";
	self.topics = @[];
	self.tableView.rowHeight = 56;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] forumTopicsForChat:self.chatId completion:^(NSArray *topics){
		TGTopicsViewController *me = weakSelf;
		if (!me)
			return;
		me.topics = topics;
		[me.tableView reloadData];
		NSLog(@"TDLIB TOPICS: %lu", (unsigned long)topics.count);
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.topics.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGTopicCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	NSDictionary *t = self.topics[indexPath.row];
	NSInteger unread = [t[@"unread"] integerValue];

	cell.textLabel.text = unread > 0
		? [NSString stringWithFormat:@"%@  (%ld)", t[@"name"], (long)unread]
		: t[@"name"];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	cell.detailTextLabel.text = t[@"text"];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSDictionary *t = self.topics[indexPath.row];
	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = self.chatId;
	vc.threadId = [t[@"threadId"] longLongValue];
	vc.chatTitle = t[@"name"];
	vc.isGroup = YES;
	[self.navigationController pushViewController:vc animated:YES];
}

@end

// vim:ft=objc

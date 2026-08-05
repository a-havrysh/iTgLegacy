#import "TGSearchViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kSearchAvatar = 36.0f;

@interface TGSearchViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *bar;
@property (nonatomic, strong) NSArray *chatHits;      // chats whose title matches
@property (nonatomic, strong) NSArray *messageHits;   // messages from the server
@property (nonatomic, strong) NSMutableDictionary *avatars;
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@end

@implementation TGSearchViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.chatHits = @[];
	self.messageHits = @[];
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];
	self.tableView.rowHeight = 56;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	// The one thing the pinned bar could not do: get out of the way. iOS 7 has
	// this, and it is the whole reason search moved to a page.
	if ([self.tableView respondsToSelector:@selector(setKeyboardDismissMode:)])
		self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

	self.bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 240, 44)];
	self.bar.delegate = self;
	self.bar.placeholder = @"Search";
	self.bar.barStyle = [TGTheme shared].isDark ? UIBarStyleBlack : UIBarStyleDefault;
	self.bar.tintColor = [[TGTheme shared] accentColour];
	self.navigationItem.titleView = self.bar;
	self.navigationItem.hidesBackButton = YES;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain
				   target:self action:@selector(cancel)];

	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self.bar becomeFirstResponder];
}

- (void)cancel {
	[self.bar resignFirstResponder];
	[self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - searching

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
	if (!query.length){
		self.chatHits = @[];
		self.messageHits = @[];
		[self.tableView reloadData];
		return;
	}

	// Titles match here and now; the server answers about message bodies when
	// it gets round to it. Showing the first without waiting for the second is
	// what makes typing feel like it is doing something.
	NSMutableArray *titles = [NSMutableArray array];
	for (NSDictionary *c in [TGClient shared].chats)
		if ([c[@"title"] rangeOfString:query
							   options:NSCaseInsensitiveSearch].location != NSNotFound)
			[titles addObject:c];
	self.chatHits = titles;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchMessages:query completion:^(NSArray *messages){
		TGSearchViewController *me = weakSelf;
		// A slower answer to an older query must not replace a newer one.
		if (!me || ![me.bar.text isEqualToString:query])
			return;
		me.messageHits = messages ?: @[];
		[me.tableView reloadData];
	}];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? self.chatHits.count : self.messageHits.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0)
		return self.chatHits.count ? @"Chats" : nil;
	return self.messageHits.count ? @"Messages" : nil;
}

- (UIImage *)avatarForChat:(int64_t)chatId
					 title:(NSString *)title
					fileId:(NSNumber *)fileId
{
	UIImage *cached = [fileId isKindOfClass:NSNumber.class] ? self.avatars[fileId] : nil;
	if (cached)
		return cached;

	if ([fileId isKindOfClass:NSNumber.class] &&
		![self.avatarsRequested containsObject:fileId]){
		[self.avatarsRequested addObject:fileId];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			TGSearchViewController *me = weakSelf;
			UIImage *photo = path ? [UIImage imageWithContentsOfFile:path] : nil;
			if (!me || !photo)
				return;
			UIGraphicsBeginImageContextWithOptions(
					CGSizeMake(kSearchAvatar, kSearchAvatar), NO, 0);
			[photo drawInRect:CGRectMake(0, 0, kSearchAvatar, kSearchAvatar)];
			me.avatars[fileId] = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
			[me.tableView reloadData];
		}];
	}

	return [TGIcons avatarWithInitials:
				(title.length ? [title substringToIndex:1].uppercaseString : @"?")
								  size:kSearchAvatar
							  colourId:chatId];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	static NSString *reuse = @"TGSearchCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	cell.backgroundColor = [theme listBackgroundColour];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	if (indexPath.section == 0){
		NSDictionary *c = self.chatHits[indexPath.row];
		cell.textLabel.text = c[@"title"];
		cell.detailTextLabel.text = c[@"text"];
		cell.imageView.image = [self avatarForChat:[c[@"id"] longLongValue]
											 title:c[@"title"]
											fileId:c[@"photoFileId"]];
	} else {
		NSDictionary *m = self.messageHits[indexPath.row];
		cell.textLabel.text = m[@"chatTitle"];
		cell.detailTextLabel.text = m[@"text"];
		cell.imageView.image = [self avatarForChat:[m[@"chatId"] longLongValue]
											 title:m[@"chatTitle"]
											fileId:nil];
	}

	cell.imageView.layer.cornerRadius = kSearchAvatar / 2;
	cell.imageView.clipsToBounds = YES;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self.bar resignFirstResponder];

	NSDictionary *row = indexPath.section == 0
			? self.chatHits[indexPath.row] : self.messageHits[indexPath.row];
	int64_t chatId = [(indexPath.section == 0 ? row[@"id"] : row[@"chatId"]) longLongValue];
	if (!chatId)
		return;

	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = chatId;
	chat.chatTitle = indexPath.section == 0 ? row[@"title"] : row[@"chatTitle"];
	chat.isGroup = [row[@"isGroup"] boolValue];
	chat.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chat animated:YES];
}

@end

// vim:ft=objc

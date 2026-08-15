/**
 * RootViewController - the tab bar. Three screens, all on TDLib.
 */
#import "RootViewController.h"
#import "TGChatListViewController.h"
#import "TGContactsViewController.h"
#import "TGSettingsViewController.h"
#import "TGTabBar.h"
#import "TGClient.h"
#import "TGHacks.h"
#import "TGTabsContainerViewDelegate.h"
#import "UIView+SafeTint.h"

@interface RootViewController () <TGTabBarDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) TGTabBar *customTabBar;
@property (nonatomic, strong) id layoutDelegate;
@end

@implementation RootViewController

- (void)loadView {
	[super loadView];
	self.layoutDelegate = [[TGTabsContainerViewDelegate alloc] init];
	[TGHacks setLayoutDelegateForContainerView:self.view layoutDelegate:self.layoutDelegate];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	TGChatListViewController *chats = [[TGChatListViewController alloc] init];
	UINavigationController *chatsNC =
		[[UINavigationController alloc] initWithRootViewController:chats];

	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	UINavigationController *contactsNC =
		[[UINavigationController alloc] initWithRootViewController:contacts];

	TGSettingsViewController *settings = [[TGSettingsViewController alloc] init];
	UINavigationController *settingsNC =
		[[UINavigationController alloc] initWithRootViewController:settings];

	[self setViewControllers:@[contactsNC, chatsNC, settingsNC] animated:NO];
	[self setSelectedIndex:1];

	self.customTabBar = [[TGTabBar alloc] initWithFrame:
			CGRectMake(0, self.view.frame.size.height - 49, self.view.frame.size.width, 49)];
	self.customTabBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	self.customTabBar.tabDelegate = self;
	self.customTabBar.selectedIndex = 1;
	[self.view insertSubview:self.customTabBar aboveSubview:self.tabBar];

	self.tabBar.hidden = true;

	for (UINavigationController *nc in @[contactsNC, chatsNC, settingsNC]){
		nc.delegate = self;
		if ([nc.topViewController isKindOfClass:[UITableViewController class]]){
			UITableView *tableView = ((UITableViewController *)nc.topViewController).tableView;
			tableView.contentInset = UIEdgeInsetsMake(tableView.contentInset.top, 0, 49, 0);
			tableView.scrollIndicatorInsets = tableView.contentInset;
		}
	}
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self updateUnreadBadge];
}

- (void)navigationController:(UINavigationController *)navigationController
		willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
	self.customTabBar.hidden = viewController != navigationController.viewControllers.firstObject;
}

- (void)tabBarSelectedItem:(int)index {
	if ((int)self.selectedIndex != index)
		[self setSelectedIndex:index];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
	if (selectedIndex >= self.viewControllers.count)
		return;
	[super setSelectedIndex:selectedIndex];
	[self.customTabBar setSelectedIndex:(int)selectedIndex];
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController {
	[super setSelectedViewController:selectedViewController];
	NSUInteger index = [self.viewControllers indexOfObject:selectedViewController];
	if (index != NSNotFound)
		[self.customTabBar setSelectedIndex:(int)index];
}

- (int)unreadInChats:(NSArray *)chats {
	int total = 0;
	for (id entry in chats) {
		if (![entry isKindOfClass:[NSDictionary class]])
			continue;
		NSDictionary *c = (NSDictionary *)entry;
		if ([c[@"isMuted"] boolValue])
			continue;
		total += [c[@"unread"] intValue];
	}
	return total;
}

- (void)updateUnreadBadge {
	if (!self.customTabBar)
		return;
	int total = [self unreadInChats:[TGClient shared].chats];
	total += [self unreadInChats:[TGClient shared].archivedChats];
	if (total < 0)
		total = 0;
	[self.customTabBar setUnreadCount:total];
	if ([UIApplication instancesRespondToSelector:@selector(setApplicationIconBadgeNumber:)])
		[UIApplication sharedApplication].applicationIconBadgeNumber = total;
}

@end

// vim:ft=objc

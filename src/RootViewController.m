/**
 * File              : RootViewController.m
 * Author            : Igor V. Sementsov <ig.kuzm@gmail.com>
 * Date              : 22.08.2023
 * Last Modified Date: 22.08.2023
 * Last Modified By  : Igor V. Sementsov <ig.kuzm@gmail.com>
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

static const CGFloat TGTabBarHeight = 49.0f;

@interface TGDetailPlaceholderViewController : UIViewController
@end

@implementation TGDetailPlaceholderViewController

- (void)loadView {
	[super loadView];
	self.view.backgroundColor = [UIColor colorWithRed:0.84f green:0.85f blue:0.87f alpha:1.0f];

	UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	label.backgroundColor = [UIColor clearColor];
	label.textAlignment = NSTextAlignmentCenter;
	label.numberOfLines = 0;
	label.font = [UIFont systemFontOfSize:22];
	label.textColor = [UIColor colorWithWhite:0.55f alpha:1.0f];
	label.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.7f];
	label.shadowOffset = CGSizeMake(0, 1);
	label.text = @"No Conversation Selected";
	[self.view addSubview:label];
}

@end

@interface RootViewController () <TGTabBarDelegate, UINavigationControllerDelegate,
		UISplitViewControllerDelegate, UIPopoverControllerDelegate>
@property (nonatomic, strong) TGTabBar *customTabBar;
@property (nonatomic, strong) id layoutDelegate;
@property (nonatomic, strong) NSMutableIndexSet *insetTabs;
@property (nonatomic, assign) BOOL isSplitMaster;
@property (nonatomic, strong) UISplitViewController *splitController;
@property (nonatomic, strong) RootViewController *splitMaster;
@property (nonatomic, strong) UINavigationController *detailNav;
@property (nonatomic, strong) UIPopoverController *masterPopover;
@property (nonatomic, strong) UIBarButtonItem *masterBarButtonItem;
@end

static __weak RootViewController *gSplitRoot = nil;

@implementation RootViewController

+ (BOOL)isPadIdiom {
	return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
}

- (void)loadView {
	[super loadView];
	self.layoutDelegate = [[TGTabsContainerViewDelegate alloc] init];
	[TGHacks setLayoutDelegateForContainerView:self.view layoutDelegate:self.layoutDelegate];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([RootViewController isPadIdiom] && !self.isSplitMaster){
		[self buildSplitLayout];
		return;
	}

	[self buildTabs];
}

- (void)buildTabs {
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
			CGRectMake(0, self.view.bounds.size.height - TGTabBarHeight,
					   self.view.bounds.size.width, TGTabBarHeight)];
	self.customTabBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	self.customTabBar.tabDelegate = self;
	self.customTabBar.selectedIndex = 1;
	[self.view insertSubview:self.customTabBar aboveSubview:self.tabBar];

	self.tabBar.hidden = true;

	for (UINavigationController *nc in @[contactsNC, chatsNC, settingsNC])
		nc.delegate = self;

	[self applyTabBarInsetForIndex:self.selectedIndex];
}

#pragma mark - split layout (iPad only)

- (void)buildSplitLayout {
	gSplitRoot = self;

	RootViewController *master = [[RootViewController alloc] init];
	master.isSplitMaster = YES;
	self.splitMaster = master;

	self.detailNav = [[UINavigationController alloc]
			initWithRootViewController:[[TGDetailPlaceholderViewController alloc] init]];

	self.splitController = [[UISplitViewController alloc] init];
	self.splitController.delegate = self;
	self.splitController.viewControllers = @[master, self.detailNav];

	[self addChildViewController:self.splitController];
	self.splitController.view.frame = self.view.bounds;
	self.splitController.view.autoresizingMask =
			UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.splitController.view];
	if ([self.splitController respondsToSelector:@selector(didMoveToParentViewController:)])
		[self.splitController didMoveToParentViewController:self];

	self.tabBar.hidden = true;
}

- (BOOL)isSplitLayoutActive {
	if (self.isSplitMaster)
		return [[RootViewController splitRootController] splitController] != nil;
	return self.splitController != nil;
}

+ (RootViewController *)splitRootController {
	return gSplitRoot;
}

+ (BOOL)isSplitLayoutActive {
	RootViewController *root = gSplitRoot;
	return root != nil && root.splitController != nil;
}

- (UINavigationController *)detailNavigationController {
	if (self.isSplitMaster)
		return [[RootViewController splitRootController] detailNavigationController];
	return self.detailNav;
}

+ (UINavigationController *)detailNavigationController {
	return [gSplitRoot detailNavigationController];
}

- (void)dismissMasterPopover {
	if (self.masterPopover.popoverVisible)
		[self.masterPopover dismissPopoverAnimated:YES];
}

- (void)applyMasterBarButtonTo:(UIViewController *)controller {
	if (!controller)
		return;
	if (self.masterBarButtonItem)
		controller.navigationItem.leftBarButtonItem = self.masterBarButtonItem;
	else if (controller.navigationItem.leftBarButtonItem == self.masterBarButtonItem)
		controller.navigationItem.leftBarButtonItem = nil;
}

- (BOOL)presentInDetail:(UIViewController *)controller {
	if (self.isSplitMaster)
		return [[RootViewController splitRootController] presentInDetail:controller];
	if (!self.splitController || !controller)
		return NO;
	[self dismissMasterPopover];
	[self applyMasterBarButtonTo:controller];
	[self.detailNav setViewControllers:@[controller] animated:NO];
	return YES;
}

+ (BOOL)presentInDetail:(UIViewController *)controller {
	return [gSplitRoot presentInDetail:controller];
}

- (BOOL)pushInDetail:(UIViewController *)controller {
	if (self.isSplitMaster)
		return [[RootViewController splitRootController] pushInDetail:controller];
	if (!self.splitController || !controller)
		return NO;
	[self dismissMasterPopover];
	UIViewController *root = [self.detailNav.viewControllers firstObject];
	if ([root isKindOfClass:[TGDetailPlaceholderViewController class]])
		return [self presentInDetail:controller];
	[self.detailNav pushViewController:controller animated:YES];
	return YES;
}

+ (BOOL)pushInDetail:(UIViewController *)controller {
	return [gSplitRoot pushInDetail:controller];
}

- (void)showDetailEmptyState {
	if (self.isSplitMaster){
		[[RootViewController splitRootController] showDetailEmptyState];
		return;
	}
	if (!self.splitController)
		return;
	[self presentInDetail:[[TGDetailPlaceholderViewController alloc] init]];
}

+ (void)showDetailEmptyState {
	[gSplitRoot showDetailEmptyState];
}

#pragma mark - UISplitViewControllerDelegate

- (BOOL)splitViewController:(UISplitViewController *)svc
		shouldHideViewController:(UIViewController *)vc
			   inOrientation:(UIInterfaceOrientation)orientation {
	return UIInterfaceOrientationIsPortrait(orientation);
}

- (void)splitViewController:(UISplitViewController *)svc
	 willHideViewController:(UIViewController *)aViewController
		  withBarButtonItem:(UIBarButtonItem *)barButtonItem
	   forPopoverController:(UIPopoverController *)pc {
	barButtonItem.title = @"Chats";
	self.masterBarButtonItem = barButtonItem;
	self.masterPopover = pc;
	pc.delegate = self;
	[self applyMasterBarButtonTo:self.detailNav.topViewController];
}

- (void)splitViewController:(UISplitViewController *)svc
	 willShowViewController:(UIViewController *)aViewController
  invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem {
	UIViewController *top = self.detailNav.topViewController;
	if (top.navigationItem.leftBarButtonItem == barButtonItem)
		top.navigationItem.leftBarButtonItem = nil;
	self.masterBarButtonItem = nil;
	self.masterPopover = nil;
}

- (void)splitViewController:(UISplitViewController *)svc
		  popoverController:(UIPopoverController *)pc
  willPresentViewController:(UIViewController *)aViewController {
	self.masterPopover = pc;
}

#pragma mark - rotation

- (BOOL)shouldAutorotate {
	if ([RootViewController isPadIdiom])
		return YES;
	return [super shouldAutorotate];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
	if ([RootViewController isPadIdiom])
		return UIInterfaceOrientationMaskAll;
	return [super supportedInterfaceOrientations];
}

#pragma mark - tabs

- (void)applyTabBarInsetForIndex:(NSUInteger)index {
	if (index >= self.viewControllers.count)
		return;
	if (!self.insetTabs)
		self.insetTabs = [NSMutableIndexSet indexSet];
	if ([self.insetTabs containsIndex:index])
		return;
	id controller = self.viewControllers[index];
	if (![controller isKindOfClass:[UINavigationController class]])
		return;
	UIViewController *top = [[(UINavigationController *)controller viewControllers] firstObject];
	if (![top isKindOfClass:[UITableViewController class]])
		return;
	[self.insetTabs addIndex:index];
	UITableView *tableView = ((UITableViewController *)top).tableView;
	tableView.contentInset = UIEdgeInsetsMake(tableView.contentInset.top, 0, TGTabBarHeight, 0);
	tableView.scrollIndicatorInsets = tableView.contentInset;
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self applyTabBarInsetForIndex:self.selectedIndex];
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

- (NSArray *)viewControllers {
	if (self.splitMaster)
		return self.splitMaster.viewControllers;
	return [super viewControllers];
}

- (NSUInteger)selectedIndex {
	if (self.splitMaster)
		return self.splitMaster.selectedIndex;
	return [super selectedIndex];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
	if (self.splitMaster){
		[self.splitMaster setSelectedIndex:selectedIndex];
		return;
	}
	if (selectedIndex >= [super viewControllers].count)
		return;
	[self applyTabBarInsetForIndex:selectedIndex];
	[super setSelectedIndex:selectedIndex];
	[self.customTabBar setSelectedIndex:(int)selectedIndex];
}

- (UIViewController *)selectedViewController {
	if (self.splitMaster)
		return self.splitMaster.selectedViewController;
	return [super selectedViewController];
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController {
	if (self.splitMaster){
		[self.splitMaster setSelectedViewController:selectedViewController];
		return;
	}
	NSUInteger index = [[super viewControllers] indexOfObject:selectedViewController];
	if (index != NSNotFound)
		[self applyTabBarInsetForIndex:index];
	[super setSelectedViewController:selectedViewController];
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
	if (self.splitMaster){
		[self.splitMaster updateUnreadBadge];
		return;
	}
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

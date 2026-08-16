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
@property (nonatomic, strong) NSMutableIndexSet *builtTabs;
@property (nonatomic, assign) BOOL isSplitMaster;
@property (nonatomic, strong) UISplitViewController *splitController;
@property (nonatomic, strong) RootViewController *splitMaster;
@property (nonatomic, strong) UINavigationController *detailNav;
@property (nonatomic, strong) UIPopoverController *masterPopover;
@property (nonatomic, strong) UIBarButtonItem *masterBarButtonItem;
@property (nonatomic, assign) NSInteger pendingIconBadge;
@property (nonatomic, assign) NSInteger pushedIconBadge;
@property (nonatomic, assign) BOOL iconBadgeScheduled;
@property (nonatomic, assign) BOOL iconBadgePushed;
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

	if (gSplitRoot != nil && gSplitRoot != self)
		self.isSplitMaster = YES;

	if ([RootViewController isPadIdiom] && !self.isSplitMaster){
		[self buildSplitLayout];
		return;
	}

	[self buildTabs];
}

- (UINavigationController *)placeholderTab {
	UIViewController *blank = [[UIViewController alloc] init];
	blank.view.backgroundColor = [UIColor colorWithRed:0.84f green:0.85f blue:0.87f alpha:1.0f];
	return [[UINavigationController alloc] initWithRootViewController:blank];
}

- (void)materialiseTab:(NSUInteger)index {
	if (index == 1 || [self.builtTabs containsIndex:index])
		return;
	NSMutableArray *tabs = [[super viewControllers] mutableCopy];
	if (index >= tabs.count)
		return;
	UIViewController *root = index == 0
			? (UIViewController *)[[TGContactsViewController alloc] init]
			: (UIViewController *)[[TGSettingsViewController alloc] init];
	UINavigationController *nc =
			[[UINavigationController alloc] initWithRootViewController:root];
	nc.delegate = self;
	tabs[index] = nc;
	[self.builtTabs addIndex:index];
	NSUInteger selected = [super selectedIndex];
	[super setViewControllers:tabs animated:NO];
	[super setSelectedIndex:selected];
	[self.insetTabs removeIndex:index];
	[self applyTabBarInsetForIndex:index];
}

- (void)buildTabs {
	self.builtTabs = [NSMutableIndexSet indexSet];

	TGChatListViewController *chats = [[TGChatListViewController alloc] init];
	UINavigationController *chatsNC =
		[[UINavigationController alloc] initWithRootViewController:chats];

	UINavigationController *contactsNC = [self placeholderTab];
	UINavigationController *settingsNC = [self placeholderTab];

	[self setViewControllers:@[contactsNC, chatsNC, settingsNC] animated:NO];
	[self setSelectedIndex:1];
	if ([RootViewController isPadIdiom]){
		__weak RootViewController *weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			RootViewController *me = weakSelf;
			[me setSelectedIndex:1];
			me.customTabBar.selectedIndex = 1;
		});
	}

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

	self.tabBar.hidden = true;

	UISplitViewController *split = self.splitController;
	dispatch_async(dispatch_get_main_queue(), ^{
		UIWindow *window = [UIApplication sharedApplication].keyWindow;
		if (window.rootViewController == self)
			window.rootViewController = split;
	});
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
	return NO;
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

- (CGFloat)tabBarInsetForController:(UIViewController *)controller {
	if (!self.customTabBar || !controller)
		return 0;
	UINavigationController *nav = controller.navigationController;
	if (!nav || [nav.viewControllers firstObject] != controller)
		return 0;
	if (![[super viewControllers] containsObject:nav])
		return 0;
	return TGTabBarHeight;
}

- (void)applyTabBarInsetForIndex:(NSUInteger)index {
	if (self.splitMaster){
		[self.splitMaster applyTabBarInsetForIndex:index];
		return;
	}
	if (index >= self.viewControllers.count)
		return;
	id controller = self.viewControllers[index];
	if (![controller isKindOfClass:[UINavigationController class]])
		return;
	UIViewController *top = [[(UINavigationController *)controller viewControllers] firstObject];
	if (![top isKindOfClass:[UITableViewController class]])
		return;
	UITableView *tableView = ((UITableViewController *)top).tableView;
	CGFloat bottom = [self tabBarInsetForController:top];
	UIEdgeInsets insets = tableView.contentInset;
	if (insets.bottom == bottom && tableView.scrollIndicatorInsets.bottom == bottom)
		return;
	insets.bottom = bottom;
	tableView.contentInset = insets;
	tableView.scrollIndicatorInsets = insets;
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	for (NSUInteger i = 0; i < self.viewControllers.count; i++)
		[self applyTabBarInsetForIndex:i];
	[self updateUnreadBadge];
}

- (void)navigationController:(UINavigationController *)navigationController
		willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
	self.customTabBar.hidden = viewController != navigationController.viewControllers.firstObject;
	if (!self.customTabBar.hidden)
		[self applyTabBarInsetForIndex:[[self viewControllers] indexOfObject:navigationController]];
}

- (void)tabBarSelectedItem:(int)index {
	if (index >= 0)
		[self materialiseTab:(NSUInteger)index];
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

- (void)pushIconBadge {
	if (![UIApplication instancesRespondToSelector:@selector(setApplicationIconBadgeNumber:)])
		return;
	if (self.iconBadgePushed && self.pendingIconBadge == self.pushedIconBadge)
		return;
	self.iconBadgePushed = YES;
	self.pushedIconBadge = self.pendingIconBadge;
	[UIApplication sharedApplication].applicationIconBadgeNumber = self.pendingIconBadge;
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

	if (self.iconBadgeScheduled && total == self.pendingIconBadge)
		return;
	self.iconBadgeScheduled = YES;
	self.pendingIconBadge = total;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(pushIconBadge)
											   object:nil];
	[self performSelector:@selector(pushIconBadge) withObject:nil afterDelay:1.5];
}

@end

// vim:ft=objc

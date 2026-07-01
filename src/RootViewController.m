/**
 * RootViewController - the tab bar. Three screens, all on TDLib.
 */
#import "RootViewController.h"
#import "TGChatListViewController.h"
#import "TGContactsViewController.h"
#import "TGSettingsViewController.h"
#import "TGIcons.h"
#import "TGTheme.h"

@implementation RootViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	TGChatListViewController *chats = [[TGChatListViewController alloc] init];
	UINavigationController *chatsNC =
		[[UINavigationController alloc] initWithRootViewController:chats];
	chatsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Chats"
														image:[TGIcons chats] tag:0];

	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	UINavigationController *contactsNC =
		[[UINavigationController alloc] initWithRootViewController:contacts];
	contactsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Contacts"
														   image:[TGIcons contacts] tag:1];

	TGSettingsViewController *settings = [[TGSettingsViewController alloc] init];
	UINavigationController *settingsNC =
		[[UINavigationController alloc] initWithRootViewController:settings];
	settingsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
														   image:[TGIcons settings] tag:2];

	// On iOS 7 the bar background is barTintColor; tintColor only colours the
	// selected item. Setting the latter alone painted the whole bar.
	TGTheme *theme = [TGTheme shared];
	if ([self.tabBar respondsToSelector:@selector(setBarTintColor:)]){
		self.tabBar.barTintColor = [theme barColour];
		self.tabBar.tintColor = [theme accentColour];
	}

	[self setViewControllers:@[chatsNC, contactsNC, settingsNC] animated:NO];
	[self setSelectedIndex:0];
}

@end

// vim:ft=objc

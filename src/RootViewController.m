/**
 * RootViewController - the tab bar. Three screens, all on TDLib.
 */
#import "RootViewController.h"
#import "TGChatListViewController.h"
#import "TGContactsViewController.h"
#import "TGSettingsViewController.h"

@implementation RootViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	TGChatListViewController *chats = [[TGChatListViewController alloc] init];
	UINavigationController *chatsNC =
		[[UINavigationController alloc] initWithRootViewController:chats];
	chatsNC.tabBarItem = [[UITabBarItem alloc]
		initWithTabBarSystemItem:UITabBarSystemItemRecents tag:0];
	chatsNC.tabBarItem.title = @"Chats";

	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	UINavigationController *contactsNC =
		[[UINavigationController alloc] initWithRootViewController:contacts];
	contactsNC.tabBarItem = [[UITabBarItem alloc]
		initWithTabBarSystemItem:UITabBarSystemItemContacts tag:1];

	TGSettingsViewController *settings = [[TGSettingsViewController alloc] init];
	UINavigationController *settingsNC =
		[[UINavigationController alloc] initWithRootViewController:settings];
	settingsNC.tabBarItem = [[UITabBarItem alloc]
		initWithTabBarSystemItem:UITabBarSystemItemMore tag:2];

	[self setViewControllers:@[chatsNC, contactsNC, settingsNC] animated:NO];
	[self setSelectedIndex:0];
}

@end

// vim:ft=objc

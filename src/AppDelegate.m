/**
 * AppDelegate - TDLib only.
 *
 * Everything libtg used to own (session, dialogs, history, media, contacts)
 * now goes through TGClient. The old C library, its 60-second queue transport
 * and the view controllers built on its structs are gone.
 */
#import "AppDelegate.h"
#import "RootViewController.h"
#import "TGClient.h"
#import "TGChatViewController.h"
#import "TGTopicsViewController.h"
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
		didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	NSString *cache = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];

	// stderr into a file so TDLib's own diagnostics survive a crash and can be
	// read off the device; scripts/devrun.sh pulls it.
	NSString *log = [cache stringByAppendingPathComponent:@"log.txt"];
	// Keep the previous run: an uncaught exception prints its reason to stderr
	// and the process dies, so without this copy the one message that explains
	// a crash is deleted by the next launch.
	NSString *lastlog = [cache stringByAppendingPathComponent:@"lastlog.txt"];
	[[NSFileManager defaultManager] removeItemAtPath:lastlog error:nil];
	[[NSFileManager defaultManager] copyItemAtPath:log toPath:lastlog error:nil];
	[[NSFileManager defaultManager] removeItemAtPath:log error:nil];
	self.log = freopen(log.UTF8String, "a+", stderr);

	NSLog(@"start...");

	self.syncData = [[NSOperationQueue alloc] init];
	self.syncData.maxConcurrentOperationCount = 2;
	application.applicationIconBadgeNumber = 0;

	for (NSString *name in @[@"s", @"peer", @"images", @"files", @"docThumbs"]){
		NSString *path = [cache stringByAppendingPathComponent:name];
		[NSFileManager.defaultManager createDirectoryAtPath:path attributes:nil];
		if ([name isEqualToString:@"s"])           self.smallPhotoCache = path;
		else if ([name isEqualToString:@"peer"])   self.peerPhotoCache = path;
		else if ([name isEqualToString:@"images"]) self.imagesCache = path;
		else if ([name isEqualToString:@"files"])  self.filesCache = path;
		else                                       self.thumbDocCache = path;
	}

	self.showNotifications = [NSUserDefaults.standardUserDefaults
			boolForKey:@"showNotifications"];

	[[NSFileManager defaultManager] changeCurrentDirectoryPath:
			[[NSBundle mainBundle] bundlePath]];

	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	// Only TDLib knows whether this session is signed in, and it takes a second
	// to say so. Showing the login form meanwhile means an already-signed-in
	// user is asked for their phone number on every launch, so show a neutral
	// screen until the state actually arrives.
	[self showLoadingUI];
	[self.window makeKeyAndVisible];

	[self startTDLib];

	return YES;
}

#pragma mark - TDLib

- (void)startTDLib {
	TGClient *tg = [TGClient shared];
	__weak typeof(self) weakSelf = self;

	tg.onAuthState = ^(TGAuthState state){
		AppDelegate *me = weakSelf;
		if (!me)
			return;
		NSLog(@"TDLIB AUTH: state %d", (int)state);

		switch (state){
			case TGAuthStateWaitPhoneNumber:
				[me showLoginUI];
				[me.loginVC setBusy:NO];
				break;
			case TGAuthStateWaitCode:
				[me.loginVC showCodeStepWithPhoneNumber:me.currentPhoneNumber];
				break;
			case TGAuthStateWaitPassword:
				[me.loginVC showPasswordStep];
				break;
			case TGAuthStateReady:
				NSLog(@"TDLIB AUTH: READY");
				[me.loginVC setBusy:NO];
				[me showMainUI];
				break;
			case TGAuthStateClosed:
			case TGAuthStateLoggingOut:
				[me showLoginUI];
				break;
			default:
				break;
		}
	};

	tg.onError = ^(NSString *msg){
		AppDelegate *me = weakSelf;
		[me.loginVC setBusy:NO];
		[me showMessage:msg];
	};

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		if (![tg start])
			NSLog(@"TDLib unavailable - libtdjson.dylib missing or unloadable");
	});
}

#pragma mark - screens

- (void)showLoadingUI {
	UIViewController *vc = [[UIViewController alloc] init];
	vc.view.backgroundColor = [UIColor colorWithRed:0.87f green:0.89f blue:0.92f alpha:1.0f];

	UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	spinner.center = CGPointMake(vc.view.bounds.size.width / 2,
								 vc.view.bounds.size.height / 2);
	spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
			UIViewAutoresizingFlexibleRightMargin |
			UIViewAutoresizingFlexibleTopMargin |
			UIViewAutoresizingFlexibleBottomMargin;
	[spinner startAnimating];
	[vc.view addSubview:spinner];

	[self.window setRootViewController:vc];
}

- (void)showMainUI {
	if (!self.rootViewController)
		self.rootViewController = [[RootViewController alloc] init];
	if (self.window.rootViewController != self.rootViewController){
		self.loginVC = nil;
		[self.window setRootViewController:self.rootViewController];
	}
}

- (void)showLoginUI {
	if (self.loginVC)
		return;

	TGLoginViewController *loginVC = [[TGLoginViewController alloc] init];
	self.loginVC = loginVC;

	__weak typeof(self) weakSelf = self;
	loginVC.onPhoneSubmitted = ^(NSString *phoneNumber) {
		weakSelf.currentPhoneNumber = phoneNumber;
		[[TGClient shared] sendPhoneNumber:phoneNumber];
	};
	loginVC.onCodeSubmitted = ^(NSString *code) {
		[[TGClient shared] sendCode:code];
	};
	loginVC.onPasswordSubmitted = ^(NSString *password) {
		[[TGClient shared] sendPassword:password];
	};

	UINavigationController *nav =
		[[UINavigationController alloc] initWithRootViewController:loginVC];
	[self.window setRootViewController:nav];
	self.rootViewController = nil;
}

- (void)showMessage:(NSString *)msg {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
													message:msg
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

#pragma mark - remote control by URL

/**
 * Nobody can tap this device remotely, so the app is driven by its own URL
 * scheme instead. scripts/devrun.sh uses these.
 *
 *   itglegacy://                 just launch
 *   itglegacy://screenshot       write Caches/screen.png
 *   itglegacy://tab/N            select a tab
 *   itglegacy://chatindex/N      open the Nth chat in the list
 *   itglegacy://profile          open the profile of the chat on screen
 *   itglegacy://phone/+NNN       hand a phone number to TDLib
 *   itglegacy://code/NNNNN       hand the login code to TDLib
 *   itglegacy://password/...     hand the 2FA password to TDLib
 *
 * The last two exist so the account owner can run them from their own
 * terminal; the values are never written to the log.
 */
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
	NSString *host = url.host;
	NSString *arg = [url.path stringByReplacingOccurrencesOfString:@"/" withString:@""];
	NSLog(@"handleOpenURL: %@", host ?: @"(launch)");

	if ([host isEqualToString:@"phone"] && arg.length){
		self.currentPhoneNumber = arg;
		[[TGClient shared] sendPhoneNumber:arg];
		return YES;
	}

	if ([host isEqualToString:@"code"] && arg.length){
		NSLog(@"code received (%lu chars)", (unsigned long)arg.length);
		[[TGClient shared] sendCode:arg];
		return YES;
	}

	if ([host isEqualToString:@"password"] && arg.length){
		NSLog(@"password received (%lu chars)", (unsigned long)arg.length);
		[[TGClient shared] sendPassword:arg];
		return YES;
	}

	if ([host isEqualToString:@"tab"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			NSInteger idx = [arg integerValue];
			if ([tabs isKindOfClass:UITabBarController.class] &&
				idx >= 0 && idx < (NSInteger)tabs.viewControllers.count)
				tabs.selectedIndex = idx;
		});
		return YES;
	}

	if ([host isEqualToString:@"chatindex"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSArray *chats = [TGClient shared].chats;
			NSInteger idx = [arg integerValue];
			if (idx < 0 || idx >= (NSInteger)chats.count){
				NSLog(@"chatindex %ld out of range (%lu)",
						(long)idx, (unsigned long)chats.count);
				return;
			}
			NSDictionary *c = chats[idx];

			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			tabs.selectedIndex = 0;
			UINavigationController *nc = tabs.viewControllers[0];
			[nc popToRootViewControllerAnimated:NO];

			if ([c[@"isForum"] boolValue]){
				TGTopicsViewController *topics = [[TGTopicsViewController alloc] init];
				topics.chatId = [c[@"id"] longLongValue];
				topics.chatTitle = c[@"title"];
				topics.hidesBottomBarWhenPushed = YES;
				[nc pushViewController:topics animated:NO];
				NSLog(@"open forum index %ld", (long)idx);
				return;
			}

			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = [c[@"id"] longLongValue];
			vc.chatTitle = c[@"title"];
			vc.isGroup = [c[@"isGroup"] boolValue];   // same as the list does
			vc.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:vc animated:NO];
			NSLog(@"open chat index %ld", (long)idx);
		});
		return YES;
	}

	// itglegacy://profile - open the profile of the chat already on screen.
	if ([host isEqualToString:@"profile"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if ([top respondsToSelector:@selector(openProfile)])
				[top performSelector:@selector(openProfile)];
			else
				NSLog(@"profile: no chat on screen");
		});
		return YES;
	}

	// itglegacy://tap/N - run the tap handler for a row of the open chat.
	// itglegacy://send/<text> - send into the open chat, for testing the path
	// end to end without a keyboard.
	if ([host isEqualToString:@"send"] && arg.length){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if (![top isKindOfClass:[TGChatViewController class]]){
				NSLog(@"send: no chat open");
				return;
			}
			int64_t chatId = [(TGChatViewController *)top chatId];
			NSString *text = [arg stringByReplacingPercentEscapesUsingEncoding:
					NSUTF8StringEncoding] ?: arg;
			NSLog(@"send: %lu chars to chat %lld", (unsigned long)text.length, chatId);
			[[TGClient shared] sendText:text toChat:chatId];
		});
		return YES;
	}

	if ([host isEqualToString:@"tap"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if ([top isKindOfClass:[TGChatViewController class]])
				[(TGChatViewController *)top simulateTapOnRow:[arg integerValue]];
			else
				NSLog(@"tap: no chat open");
		});
		return YES;
	}

	if ([host isEqualToString:@"screenshot"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UIWindow *w = self.window;
			// Opaque: with an alpha channel, white text over a solid bubble
			// composited wrongly and came out orange in the capture - a
			// screenshot artifact that looked exactly like a colour bug.
			UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0.0f);
			[w.layer renderInContext:UIGraphicsGetCurrentContext()];
			UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();

			NSString *dir = [NSSearchPathForDirectoriesInDomains(
					NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
			NSString *path = [dir stringByAppendingPathComponent:@"screen.png"];
			BOOL ok = [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
			NSLog(@"screenshot %@", ok ? @"saved" : @"FAILED");
		});
		return YES;
	}

	return YES;
}

@end

// vim:ft=objc

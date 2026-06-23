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
	// Which screen to show is TDLib's authorization state to decide, so start
	// on the login form and swap to the tabs when the session turns out ready.
	[self showLoginUI];
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

- (void)showMainUI {
	if (!self.rootViewController)
		self.rootViewController = [[RootViewController alloc] init];
	if (self.window.rootViewController != self.rootViewController){
		self.loginVC = nil;
		[self.window setRootViewController:self.rootViewController];
	}
}

- (void)showLoginUI {
	if (self.loginVC && self.window.rootViewController)
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

			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = [c[@"id"] longLongValue];
			vc.chatTitle = c[@"title"];
			vc.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:vc animated:NO];
			NSLog(@"open chat index %ld", (long)idx);
		});
		return YES;
	}

	if ([host isEqualToString:@"screenshot"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UIWindow *w = self.window;
			UIGraphicsBeginImageContextWithOptions(w.bounds.size, NO, 0.0f);
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

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
#import "TGTheme.h"
#import "TGSnackbar.h"
#import "TGSearchViewController.h"
#import "TGDeviceViewController.h"
#import "TGCall.h"
#import "TGCallViewController.h"
#import "TGChatViewController.h"
#import "TGTopicsViewController.h"
#import "TGHacks.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

@protocol TGTabBarHitTesting <NSObject>
- (int)indexForLocation:(CGPoint)location;
@end

@implementation AppDelegate

/// An incoming call is the one thing that takes over the screen on its own.
static void TGWatchForIncomingCalls(void) {
	[TGCall shared].onStateChanged = ^(TGCallState state){
		if (state != TGCallStatePending || [TGCall shared].outgoing)
			return;
		int64_t userId = [TGCall shared].peerUserId;
		[TGCallViewController presentForUserId:userId
										  name:[[TGClient shared] nameForUserId:userId]
									  outgoing:NO];
	};
}

- (BOOL)application:(UIApplication *)application
		didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	[TGHacks hackSetAnimationDuration];

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
	TGWatchForIncomingCalls();

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

#pragma mark - memory

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
	NSLog(@"memory warning: dropping discardable caches");
	[TGIcons flush];
	[[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
	[TGIcons flush];
	[[NSURLCache sharedURLCache] removeAllCachedResponses];
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
				[me showLoginUI];
				[me.loginVC showCodeStepWithPhoneNumber:me.currentPhoneNumber];
				break;
			case TGAuthStateWaitPassword:
				[me showLoginUI];
				[me.loginVC showPasswordStep];
				break;
			case TGAuthStateWaitRegistration:
				[me showLoginUI];
				[me.loginVC setBusy:NO];
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
	UIViewController *wanted = self.rootViewController;
	if ([RootViewController isSplitLayoutActive])
		wanted = [self.window.rootViewController isKindOfClass:[UISplitViewController class]]
				? self.window.rootViewController : wanted;
	if (self.window.rootViewController != wanted){
		self.loginVC = nil;
		[self.window setRootViewController:wanted];
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

/// The view currently taking keystrokes, wherever it is in the tree.
- (UIView *)firstResponderUnder:(UIView *)view {
	if (view.isFirstResponder)
		return view;
	for (UIView *sub in view.subviews){
		UIView *found = [self firstResponderUnder:sub];
		if (found)
			return found;
	}
	return nil;
}

/**
 * Nobody can tap this device remotely, so the app is driven by its own URL
 * scheme instead. scripts/devrun.sh uses these.
 *
 *   itglegacy://                 just launch
 *   itglegacy://screenshot       write Caches/screen.png
 *   itglegacy://chatindex/N      open the Nth chat in the list
 *   itglegacy://profile          open the profile of the chat on screen
 *   itglegacy://holdrow/N        hold the Nth row, for the menus behind it
 *   itglegacy://theme/NAME       apply a theme file from Documents ("none" clears,
 *                                "skeuomorphic"/"flat"/"dark" pick a built-in)
 *   itglegacy://stickers         open the sticker strip in the chat on screen
 *   itglegacy://tab/N            switch to tab N (0 contacts, 1 chats, 2 settings)
 *   itglegacy://device           open the Device screen
 *   itglegacy://call/USERID      place a call, for testing without a tap
 *   itglegacy://callindex/N      call the other side of the Nth chat
 *   itglegacy://scroll/N         scroll the visible table N points down
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
			if (![tabs isKindOfClass:UITabBarController.class] ||
				idx < 0 || idx >= (NSInteger)tabs.viewControllers.count)
				return;
			tabs.selectedIndex = idx;
			// Back to the top of that tab as well: picking a tab that stayed
			// three screens deep looks like the URL did nothing, and every
			// tap/ and holdrow/ after it lands on the wrong screen.
			UIViewController *chosen = tabs.viewControllers[idx];
			if ([chosen isKindOfClass:UINavigationController.class])
				[(UINavigationController *)chosen popToRootViewControllerAnimated:NO];
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
			if (![chats[idx] isKindOfClass:[NSDictionary class]])
				return;
			NSDictionary *c = (NSDictionary *)chats[idx];

			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			tabs.selectedIndex = 1;
			UINavigationController *nc = tabs.viewControllers[1];
			[nc popToRootViewControllerAnimated:NO];

			if ([c[@"isForum"] boolValue]){
				TGTopicsViewController *topics = [[TGTopicsViewController alloc] init];
				topics.chatId = [c[@"id"] longLongValue];
				topics.chatTitle = c[@"title"];
				[nc pushViewController:topics animated:NO];
				NSLog(@"open forum index %ld", (long)idx);
				return;
			}

			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = [c[@"id"] longLongValue];
			vc.chatTitle = c[@"title"];
			vc.isGroup = [c[@"isGroup"] boolValue];   // same as the list does
			if (![RootViewController presentInDetail:vc])
				[nc pushViewController:vc animated:NO];
			NSLog(@"open chat index %ld", (long)idx);
		});
		return YES;
	}

	// itglegacy://touch/X/Y and itglegacy://hold/X/Y/MS - a finger, for the
	// things a URL cannot express: holding the microphone, tapping a sticker,
	// answering a call. Only reaches this app, which is all that is needed.
	if ([host isEqualToString:@"touch"] || [host isEqualToString:@"hold"]){
		BOOL holding = [host isEqualToString:@"hold"];
		// `arg` has had every slash stripped out of it, so the path is read
		// straight from the URL here.
		NSMutableArray *parts = [NSMutableArray array];
		for (NSString *component in url.pathComponents)
			if (![component isEqualToString:@"/"] && component.length)
				[parts addObject:component];
		if (parts.count < 2){
			NSLog(@"touch: expected x and y, got %@", url.path);
			return YES;
		}

		CGPoint point = CGPointMake([parts[0] floatValue], [parts[1] floatValue]);
		NSTimeInterval seconds = (holding && parts.count > 2)
				? [parts[2] doubleValue] / 1000.0 : 0;

		dispatch_async(dispatch_get_main_queue(), ^{
			UIWindow *window = [UIApplication sharedApplication].keyWindow;
			UIView *hit = [window hitTest:point withEvent:nil];
			NSLog(@"touch at %.0f,%.0f hit %@", point.x, point.y, [hit class]);

			// A control is driven through its actions; a plain view gets its
			// gesture recognisers fired instead.
			UIControl *control = nil;
			for (UIView *view = hit; view; view = view.superview)
				if ([view isKindOfClass:UIControl.class]){
					control = (UIControl *)view;
					break;
				}

			// TGTabBar reads raw touches itself rather than being a UIControl,
			// so touch/ needs to drive it directly rather than through actions.
			Class tabBarClass = NSClassFromString(@"TGTabBar");
			for (UIView *view = hit; view; view = view.superview){
				if (tabBarClass && [view isKindOfClass:tabBarClass]){
					int index = [(id<TGTabBarHitTesting>)view
							indexForLocation:[view convertPoint:point fromView:nil]];
					if (index < 0)
						return;
					if ([view respondsToSelector:@selector(setSelectedIndex:)])
						[view setValue:@(index) forKey:@"selectedIndex"];
					id delegate = [view valueForKey:@"tabDelegate"];
					SEL selector = @selector(tabBarSelectedItem:);
					if ([delegate respondsToSelector:selector]){
						NSMethodSignature *sig = [delegate methodSignatureForSelector:selector];
						NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
						invocation.selector = selector;
						[invocation setArgument:&index atIndex:2];
						[invocation invokeWithTarget:delegate];
					}
					NSLog(@"touch: TGTabBar -> index %d", index);
					return;
				}
			}

			// A switch changes its value from its own gesture handling, not
			// from TouchUpInside, so sending that alone leaves it where it was
			// and the screen looks like it ignored the tap.
			if ([control isKindOfClass:UISwitch.class]){
				UISwitch *toggle = (UISwitch *)control;
				[toggle setOn:!toggle.on animated:YES];
				[toggle sendActionsForControlEvents:UIControlEventValueChanged];
				NSLog(@"touch: switch -> %@", toggle.on ? @"on" : @"off");
				return;
			}

			if (control){
				[control sendActionsForControlEvents:UIControlEventTouchDown];
				if (seconds > 0){
					dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
							(int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
						[control sendActionsForControlEvents:UIControlEventTouchUpInside];
						NSLog(@"released after %.0f ms", seconds * 1000);
					});
				} else {
					[control sendActionsForControlEvents:UIControlEventTouchUpInside];
				}
				return;
			}

			// Rows are reachable through itglegacy://tap/N, so anything that is
			// not a control is left alone rather than guessed at.
			NSLog(@"touch: nothing actionable at that point");
		});
		return YES;
	}

	// itglegacy://answer - the 4S is not in reach of a finger during a test.
	if ([host isEqualToString:@"answer"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"answering call %d", [TGCall shared].callId);
			[[TGCall shared] accept];
		});
		return YES;
	}

	// itglegacy://hangup - end whatever call is up.
	if ([host isEqualToString:@"hangup"]){
		dispatch_async(dispatch_get_main_queue(), ^{ [[TGCall shared] hangUp]; });
		return YES;
	}

	// itglegacy://callindex/N - the private chat id is the user id, and this
	// saves having to find one by hand.
	if ([host isEqualToString:@"callindex"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSArray *chats = [TGClient shared].chats;
			NSInteger idx = [arg integerValue];
			if (idx < 0 || idx >= (NSInteger)chats.count){
				NSLog(@"callindex %ld out of range", (long)idx);
				return;
			}
			NSDictionary *c = chats[idx];
			if ([c[@"isGroup"] boolValue]){
				NSLog(@"callindex %ld is a group", (long)idx);
				return;
			}
			int64_t userId = [c[@"id"] longLongValue];
			NSLog(@"calling %@ (%lld)", c[@"title"], userId);
			[TGCallViewController presentForUserId:userId name:c[@"title"] outgoing:YES];
		});
		return YES;
	}

	// itglegacy://call/<user id> - placing a call needs a tap otherwise.
	if ([host isEqualToString:@"call"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			int64_t userId = [arg longLongValue];
			[TGCallViewController presentForUserId:userId
											  name:[[TGClient shared] nameForUserId:userId]
										  outgoing:YES];
		});
		return YES;
	}

	// itglegacy://type/TEXT - put text into whatever is being typed into, and
	// tell its delegate, which is what a keyboard would have done. Keyboard
	// keys are not controls, so touch/ cannot reach them.
	if ([host isEqualToString:@"type"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSString *text = [arg stringByReplacingPercentEscapesUsingEncoding:
					NSUTF8StringEncoding] ?: arg;
			UIView *responder = [self firstResponderUnder:self.window];
			if ([responder isKindOfClass:UITextField.class]){
				UITextField *field = (UITextField *)responder;
				field.text = text;
				[field sendActionsForControlEvents:UIControlEventEditingChanged];
			}

			// A search bar owns a text field but may be the responder itself,
			// and either way its delegate is what wants to hear about this.
			UIView *bar = responder;
			while (bar && ![bar isKindOfClass:UISearchBar.class])
				bar = bar.superview;
			if (bar){
				[(UISearchBar *)bar setText:text];
				id<UISearchBarDelegate> delegate = [(UISearchBar *)bar delegate];
				if ([delegate respondsToSelector:@selector(searchBar:textDidChange:)])
					[delegate searchBar:(UISearchBar *)bar textDidChange:text];
			}
			NSLog(@"type: %@ into %@", text, responder ? [responder class] : (id)@"nothing");
		});
		return YES;
	}

	// itglegacy://search - open the search page. Tapping the bar in the header
	// cannot be delivered through touch/, which drives controls rather than
	// first responders.
	if ([host isEqualToString:@"search"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			[nc pushViewController:[[TGSearchViewController alloc] init] animated:YES];
		});
		return YES;
	}

	// itglegacy://snackbar - show the undo plate over whatever is on screen,
	// committing nothing. The real one sits behind a delete, and checking how
	// it looks is not worth destroying a chat to find out.
	if ([host isEqualToString:@"snackbar"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			[TGSnackbar showInView:self.window.rootViewController.view
							  text:@"Chat deleted"
						   seconds:5
						  onCommit:^{ NSLog(@"snackbar: committed (test, no-op)"); }];
		});
		return YES;
	}

	// itglegacy://holdrow/N - hold the Nth row. A long press cannot be sent
	// through touch/, which only drives controls, and the menus behind it are
	// the ones most worth looking at.
	if ([host isEqualToString:@"holdrow"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UIViewController *top = [tabs.viewControllers[tabs.selectedIndex] topViewController];
			if (![top respondsToSelector:@selector(showActionsForRow:)]){
				NSLog(@"holdrow: %@ has no row menu", [top class]);
				return;
			}
			NSLog(@"holdrow: %ld on %@", (long)[arg integerValue], [top class]);
			NSInteger row = [arg integerValue];
			NSMethodSignature *sig = [top methodSignatureForSelector:
					@selector(showActionsForRow:)];
			NSInvocation *call = [NSInvocation invocationWithMethodSignature:sig];
			call.selector = @selector(showActionsForRow:);
			call.target = top;
			[call setArgument:&row atIndex:2];
			[call invoke];
		});
		return YES;
	}

	// itglegacy://scroll/N - a screenshot only shows the top of a screen.
	if ([host isEqualToString:@"scroll"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UIViewController *top = [tabs.viewControllers[tabs.selectedIndex] topViewController];
			UIView *view = top.view;
			UIScrollView *scroll = [view isKindOfClass:UIScrollView.class]
					? (UIScrollView *)view : nil;
			for (UIView *sub in view.subviews)
				if (!scroll && [sub isKindOfClass:UIScrollView.class])
					scroll = (UIScrollView *)sub;
			[scroll setContentOffset:CGPointMake(0, [arg floatValue]) animated:NO];
		});
		return YES;
	}

	// itglegacy://device - the Device screen, which is three taps in otherwise.
	if ([host isEqualToString:@"device"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			tabs.selectedIndex = tabs.viewControllers.count - 1;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			[nc popToRootViewControllerAnimated:NO];
			[nc pushViewController:[[TGDeviceViewController alloc] init] animated:NO];
		});
		return YES;
	}

	// itglegacy://stickers - open the sticker strip, which needs a real tap.
	if ([host isEqualToString:@"stickers"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UIViewController *top = [tabs.viewControllers[tabs.selectedIndex] topViewController];
			if ([top respondsToSelector:@selector(toggleStickerPanel)])
				[top performSelector:@selector(toggleStickerPanel)];
		});
		return YES;
	}

	// itglegacy://theme/<file> - apply a theme file sitting in Documents.
	// The three built-in styles answer to their own names, because reaching a
	// settings row from a URL is not possible and checking a theme on the
	// device otherwise means a finger.
	if ([host isEqualToString:@"theme"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSArray *builtIn = @[@"skeuomorphic", @"flat", @"dark"];
			NSUInteger style = [builtIn indexOfObject:arg.lowercaseString];
			if (style != NSNotFound){
				[[TGTheme shared] clearImportedTheme];
				[TGTheme shared].style = (TGThemeStyle)style;
				NSLog(@"theme: built-in %@", arg);
				return;
			}
			if ([arg isEqualToString:@"none"]){
				[[TGTheme shared] clearImportedTheme];
				NSLog(@"theme: cleared");
				return;
			}
			NSString *documents = [NSSearchPathForDirectoriesInDomains(
					NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
			NSString *path = [documents stringByAppendingPathComponent:arg];
			NSLog(@"theme: %@ -> %@", arg,
					[[TGTheme shared] importThemeAtPath:path] ? @"applied" : @"rejected");
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
			// A modally-presented screen (like New Contact) sits outside the tab
			// bar's own navigation stack, so its rows would otherwise be
			// unreachable from a script.
			UIViewController *presented = self.rootViewController.presentedViewController;
			while (presented.presentedViewController)
				presented = presented.presentedViewController;
			UIViewController *top;
			if ([presented isKindOfClass:UINavigationController.class])
				top = ((UINavigationController *)presented).topViewController;
			else if (presented)
				top = presented;
			else {
				UITabBarController *tabs = (UITabBarController *)self.rootViewController;
				if (![tabs isKindOfClass:UITabBarController.class])
					return;
				UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
				top = nc.topViewController;
			}
			// Any table screen can answer this, not only a chat: rows are not
			// controls, so touch/ cannot reach them and every list would
			// otherwise be unreachable without a finger.
			UITableView *table = [top isKindOfClass:UITableViewController.class]
					? [(UITableViewController *)top tableView] : nil;
			if ([top isKindOfClass:[TGChatViewController class]]){
				[(TGChatViewController *)top simulateTapOnRow:[arg integerValue]];
			} else if (table){
				// tap/N is row N of section 0; tap/S/R reaches a grouped table,
				// where everything past the first group is otherwise unreachable.
				NSMutableArray *parts = [NSMutableArray array];
				for (NSString *component in url.pathComponents)
					if (![component isEqualToString:@"/"] && component.length)
						[parts addObject:component];
				NSIndexPath *path = (parts.count > 1)
						? [NSIndexPath indexPathForRow:[parts[1] integerValue]
											 inSection:[parts[0] integerValue]]
						: [NSIndexPath indexPathForRow:[arg integerValue] inSection:0];
				// A row that is not there must not take the app down with it:
				// this is driven from a script, and a stale index is normal.
				NSInteger rows = [table numberOfRowsInSection:path.section];
				if (path.section >= [table numberOfSections] || path.row >= rows){
					NSLog(@"tap: %ld.%ld is out of range (%ld rows)",
							(long)path.section, (long)path.row, (long)rows);
					return;
				}
				NSLog(@"tap: %ld.%ld on %@", (long)path.section, (long)path.row, [top class]);
				[table.delegate tableView:table didSelectRowAtIndexPath:path];
			} else {
				NSLog(@"tap: %@ has no rows", [top class]);
			}
		});
		return YES;
	}

	if ([host isEqualToString:@"screenshot"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			@autoreleasepool {
			// Opaque: with an alpha channel, white text over a solid bubble
			// composited wrongly and came out orange in the capture - a
			// screenshot artifact that looked exactly like a colour bug.
			UIGraphicsBeginImageContextWithOptions(self.window.bounds.size, YES, 0.0f);
			CGContextRef ctx = UIGraphicsGetCurrentContext();
			// An action sheet, an alert and the keyboard each live in a window
			// of their own, so rendering only ours photographed the screen
			// underneath them and made a menu that was open look like one that
			// had never opened.
			for (UIWindow *w in [UIApplication sharedApplication].windows){
				if (w.hidden || w.alpha <= 0.01f)
					continue;
				CGContextSaveGState(ctx);
				CGContextTranslateCTM(ctx, w.frame.origin.x, w.frame.origin.y);
				[w.layer renderInContext:ctx];
				CGContextRestoreGState(ctx);
			}
			UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();

			NSString *dir = [NSSearchPathForDirectoriesInDomains(
					NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
			NSString *path = [dir stringByAppendingPathComponent:@"screen.png"];
			BOOL ok = [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
			NSLog(@"screenshot %@", ok ? @"saved" : @"FAILED");
			}
		});
		return YES;
	}

	return YES;
}

@end

// vim:ft=objc

/**
 * File              : AppDelegate.m
 * Author            : Igor V. Sementsov <ig.kuzm@gmail.com>
 * Date              : 09.08.2023
 * Last Modified Date: 31.08.2023
 * Last Modified By  : Igor V. Sementsov <ig.kuzm@gmail.com>
 */

#import "AppDelegate.h"
#include "AVFoundation/AVFoundation.h"
#include <stdlib.h>
#include <dlfcn.h>
#include "TGDialog.h"
#include "DialogsViewController.h"
#include "ChatViewController.h"
#include "AudioToolbox/AudioToolbox.h"
#include <string.h>
#include <stdio.h>
#import <UIKit/UIResponder.h>
#include "Foundation/Foundation.h"
#include "UIKit/UIKit.h"
#include "RootViewController.h"
#include "../libtg/libtg.h"
#include "../libtg/tg/dialogs.h"
#include "../libtg/api_id.h"
#include "../libtg/tg/user.h"
#include "../libtg/tg/peer.h"
#include "AVFoundation/AVAudioSession.h"
#import "TGClient.h"
#import <QuartzCore/QuartzCore.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

	// lock crush
	//UIApplication.sharedApplication.idleTimerDisabled = YES;
	
	self.unread = [NSMutableArray array];
	NSArray *unread = 
		[NSUserDefaults.standardUserDefaults objectForKey:@"unread"];
	if (unread){
		[self.unread addObjectsFromArray:unread];
	}

	// colorset
	self.colorset = [NSUserDefaults.standardUserDefaults 
			objectForKey:@"colorset"];
	if (!self.colorset)
		self.colorset = [NSArray array];

	// create cache
	NSString *cache = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, 
			NSUserDomainMask,
		 	YES) objectAtIndex:0]; 
	
	// logging
	//NSString *log = 
		//[NSTemporaryDirectory() stringByAppendingPathComponent:@"log.txt"];
	NSString *log = 
		[cache stringByAppendingPathComponent:@"log.txt"];
	NSString *lastlog = 
		[NSTemporaryDirectory() stringByAppendingPathComponent:@"lastlog.txt"];
	FILE *logp = fopen(log.UTF8String, "r");
	FILE *lastlogp = fopen(lastlog.UTF8String, "w");
	if (logp && lastlogp){
		fseek(logp, -BUFSIZ, SEEK_END);
		char buf[BUFSIZ];
		fread(buf, BUFSIZ, 1, logp);
		fwrite(buf, BUFSIZ, 1, lastlogp);
		fclose(logp);
		fclose(lastlogp);
	}

	// setup update interwal
	NSInteger sec = [NSUserDefaults.standardUserDefaults 
			integerForKey:@"chatUpdateInterval"];
	if (sec == 0)
		[NSUserDefaults.standardUserDefaults setInteger:30 forKey:@"chatUpdateInterval"];

	// remove log file
	[[NSFileManager defaultManager] removeItemAtPath:log error:nil];
	self.log = freopen([log UTF8String], "a+", stderr);

	NSLog(@"start...");

	self.syncData = [[NSOperationQueue alloc]init];
	// libtg drives a single socket and one answer queue - running 4 operations
	// against it in parallel races the auth-key handshake against the queries
	// that need it.
	self.syncData.maxConcurrentOperationCount = 1;
	
	// set badge number
	application.applicationIconBadgeNumber = 0;

		self.smallPhotoCache = [cache 
			stringByAppendingPathComponent:@"s"];
	[NSFileManager.defaultManager 
		createDirectoryAtPath:self.smallPhotoCache attributes:nil];
		
	self.peerPhotoCache = [cache 
			stringByAppendingPathComponent:@"peer"];
	[NSFileManager.defaultManager 
		createDirectoryAtPath:self.peerPhotoCache attributes:nil];
	
	self.imagesCache = [cache 
			stringByAppendingPathComponent:@"images"];
	[NSFileManager.defaultManager 
		createDirectoryAtPath:self.imagesCache attributes:nil];
	
	self.filesCache = [cache 
			stringByAppendingPathComponent:@"files"];
	[NSFileManager.defaultManager 
		createDirectoryAtPath:self.filesCache attributes:nil];
	
	self.thumbDocCache = [cache 
			stringByAppendingPathComponent:@"docThumbs"];
	[NSFileManager.defaultManager 
		createDirectoryAtPath:self.thumbDocCache attributes:nil];
	
  //[[NSNotificationCenter defaultCenter] addObserver:@"" selector:@selector(callMyWebService) name:nil object:nil];

	// Override point for customization after application launch.
	[application beginReceivingRemoteControlEvents];
	[application registerForRemoteNotificationTypes:
		(UIRemoteNotificationTypeBadge|UIRemoteNotificationTypeSound|UIRemoteNotificationTypeAlert)];

	// show notifications in dialogs
	self.showNotifications = [NSUserDefaults.standardUserDefaults 
			boolForKey:@"showNotifications"];
	
	// start reachability
	// Route-based check, not a name-based one. reachabilityWithHostname makes
	// every "is there network?" test depend on resolving one specific foreign
	// host - if that name does not resolve, the whole app reports "no network"
	// while Telegram itself is perfectly reachable.
	self.reach = [Reachability reachabilityForInternetConnection];
	// Set the blocks
	self.reach.reachableBlock = ^(Reachability*reach)
	{
			// keep in mind this is called on a background thread
			// and if you are updating the UI it needs to happen
			// on the main thread, like this:

			dispatch_async(dispatch_get_main_queue(), ^{
					if (self.reachabilityDelegate)
						[self.reachabilityDelegate isOnLine];
					NSLog(@"REACHABLE!");
			});
	};

	self.reach.unreachableBlock = ^(Reachability*reach)
	{
			dispatch_async(dispatch_get_main_queue(), ^{
					if (self.reachabilityDelegate)
						[self.reachabilityDelegate isOffLine];
			});

			NSLog(@"UNREACHABLE!");
	};

	// Start the notifier, which will cause the reachability object to retain itself!
	[self.reach startNotifier];

	// change current directory path to bundle
	[[NSFileManager defaultManager]changeCurrentDirectoryPath:
		[[NSBundle mainBundle] bundlePath]];

	// start window
	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

	// With no stored session, the login screen IS the root: building the tab UI
	// first only makes launch slower and flashes an interface the user cannot
	// use yet. The tab UI is built in showMainUI once we are authorized.
	if ([NSUserDefaults.standardUserDefaults objectForKey:@"userId"])
		[self showMainUI];
	else
		[self showLoginUI];

	[self.window makeKeyAndVisible];

	[self startTDLibAuth];
	[self authorize];
	
	return true;
}

- (void)showAlarm:(NSString *)text {
  UIAlertView *alertView = [[UIAlertView alloc] 
		initWithTitle:@"Alarm"
		message:text 
		delegate:nil
		cancelButtonTitle:@"OK"
		otherButtonTitles:nil];
	[alertView show];
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
	//if (event.type == UIEventTypeRemoteControl) {
		//switch (event.subtype) {
			//case UIEventSubtypeRemoteControlTogglePlayPause:
					//// Pause or play action
					//if (self.player.currentPlaybackRate != 0)
						//[self.player pause];
					//else
						//[self.player play];
					//break;
			//case UIEventSubtypeRemoteControlNextTrack:
					//// Next track action
					//[self.player next];
					//break;
			//case UIEventSubtypeRemoteControlPreviousTrack:
					//// Previous track action
					//[self.player prev];
					//break;
			//case UIEventSubtypeRemoteControlStop:
					//// Stop action
					//[self.player stop];
					//break;
			//case UIEventSubtypeRemoteControlPlay:
					//// Stop action
					//[self.player play];
					//break;
			//case UIEventSubtypeRemoteControlPause:
					//// Stop action
					//[self.player pause];
					//break;

			//default:
					//// catch all action
					//break;
		//}
	//}
}

-(void)showMessage:(NSString *)msg {
	UIAlertView *alert = 
			[[UIAlertView alloc]initWithTitle:@"" 
			message:msg 
			delegate:nil 
			cancelButtonTitle:@"Закрыть" 
			otherButtonTitles:nil];

		[alert show];
}

-(void)askInput:(NSString *)msg onDone:(void (^)(NSString *text))onDone{
	self.askInput_onDone = onDone;
	self.allertType = ALLERT_TYPE_ASK_INPUT;
	UIAlertView *alert = 
			[[UIAlertView alloc]initWithTitle:@"" 
			message:msg 
			delegate:self 
			cancelButtonTitle:@"OK" 
			otherButtonTitles:nil];

	[alert setAlertViewStyle:UIAlertViewStylePlainTextInput]; 
	[alert show];
}

-(void)askYesNo:(NSString *)msg onYes:(void (^)())onYes{
	self.allertType = ALLERT_TYPE_YES_NO;
	self.askYesNo_onYes = onYes;
	UIAlertView *alert = 
			[[UIAlertView alloc]initWithTitle:@"" 
			message:msg 
			delegate:self 
			cancelButtonTitle:@"cancel" 
			otherButtonTitles:@"OK", nil];

	[alert show];
}

-(void)alertView:(UIAlertView *)alertView 
	clickedButtonAtIndex:(NSInteger)buttonIndex
{	
	switch (self.allertType) {
		case ALLERT_TYPE_ASK_INPUT:
			{
				UITextField *textField = [alertView textFieldAtIndex:0];
				if (self.askInput_onDone)
					self.askInput_onDone(textField.text);
			}
			break;
		case ALLERT_TYPE_YES_NO:
			{
				if (buttonIndex == 1){
					if (self.askYesNo_onYes)
						self.askYesNo_onYes();
				}
			}
			break;
	
		default:
			break;
	}
	
}

#pragma mark <NOTIFICATIONS FUNCTIONS>
-(void)openDislogForNotification:(NSDictionary *)userInfo{
	if ([userInfo valueForKey:@"from_id"]){
		NSNumber *n = [userInfo valueForKey:@"from_id"];
		uint64_t from_id = [n longLongValue]; 
		tg_user_t *user = tg_user_get(self.tg, from_id);
		if (user){
			UINavigationController *nc =
					[((RootViewController *)self.rootViewController).viewControllers objectAtIndex:1]; 
			if (nc){
				[((RootViewController *)self.rootViewController) setSelectedViewController:nc];
				[nc popToRootViewControllerAnimated:NO];

				TGDialog *dialog = [[TGDialog alloc] init];
				dialog.peerType = TG_PEER_TYPE_USER;
				dialog.peerId = from_id;
				dialog.accessHash = user->access_hash_;
				dialog.photoId = user->photo_id;
				if (user->first_name_)
					dialog.title = [NSString stringWithUTF8String:user->first_name_];

				DialogsViewController *dc = 
					(DialogsViewController *)[nc visibleViewController];
				
				ChatViewController *vc = [[ChatViewController alloc]init];
				vc.hidesBottomBarWhenPushed = YES;
				vc.dialog = dialog;
				vc.spinner = dc.spinner;
				[nc pushViewController:vc animated:TRUE];
			}
		}
	}
}

-(void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo{
	NSLog(@"%@", userInfo);
	//[self showMessage:[NSString stringWithFormat:@"%@", userInfo]];
	NSNumber *from_id = [userInfo valueForKey:@"from_id"];
	NSNumber *msg_id = [userInfo valueForKey:@"msg_id"];
	if (from_id && msg_id){
		[self.unread addObject:from_id];
		UIApplication.sharedApplication.applicationIconBadgeNumber = 
			self.unread.count;

		[NSUserDefaults.standardUserDefaults setObject:self.unread 
																						 forKey:@"unread"];
	}

	NSDictionary *aps = [userInfo valueForKey:@"aps"];
	//NSString *badge = [aps valueForKey:@"badge"];

	if(application.applicationState == UIApplicationStateInactive) 
	{
     NSLog(@"Inactive - the user has tapped in the notification when app was closed or in background");
     //do some tasks
    //[self manageRemoteNotification:userInfo];
     //completionHandler(UIBackgroundFetchResultNewData);
		 [self openDislogForNotification:userInfo];
 } else if (application.applicationState == UIApplicationStateBackground) {

     NSLog(@"application Background - notification has arrived when app was in background");
     NSString* contentAvailable = [NSString stringWithFormat:@"%@", [[userInfo valueForKey:@"aps"] valueForKey:@"content-available"]];

     if([contentAvailable isEqualToString:@"1"]) {
         // do tasks
         //[self manageRemoteNotification:userInfo];
         NSLog(@"content-available is equal to 1");
         //completionHandler(UIBackgroundFetchResultNewData);
     }
		 [self openDislogForNotification:userInfo];
 } else {
     NSLog(@"application Active - notication has arrived while app was opened");
      //play sound
			NSURL *url = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"2.m4a"];
			SystemSoundID soundID;
			AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &soundID);
			AudioServicesPlaySystemSound(soundID);
			AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
			// add bange to tabBarItem
			UINavigationController *nc =
				[((RootViewController *)self.rootViewController).viewControllers objectAtIndex:1]; 
			if (nc){
				//int badge = nc.tabBarItem.badgeValue.intValue;
				//badge++;
				nc.tabBarItem.badgeValue = 
					[NSString stringWithFormat:@"%ld", self.unread.count];
			}

			// reload data
			if (self.reachabilityDelegate)
				[self.reachabilityDelegate isOnLine];
			//if (self.dialogsViewController){
				//[(DialogsViewController *)self.dialogsViewController getDialogsFrom:[NSDate date]];
			//}

			// show allert
			NSDictionary *alert = [aps valueForKey:@"alert"];
			NSString *title = [alert valueForKey:@"title"];
			NSString *body = [alert valueForKey:@"body"];
			if (self.showNotifications){
				UIAlertView *alertView = 
					[[UIAlertView alloc] 
						initWithTitle:title
						message:body delegate:nil
						cancelButtonTitle:@"OK"
						otherButtonTitles:nil];
				[alertView show];
			}

			NSNumber *from_id = [userInfo valueForKey:@"from_id"];
			NSNumber *msg_id = [userInfo valueForKey:@"msg_id"];
			if (from_id && msg_id){
				tg_dialog_set_top_message(
						self.tg, 
						from_id.longLongValue, 
						msg_id.intValue,
						body?body.UTF8String:"");
			}
  }
}


-(void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
	self.tokenAlreadyRequested = YES;
	NSLog(@"TOKEN: %@", deviceToken);
	NSString *token = [[deviceToken description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
  token = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
  NSLog(@"Device token: %@", token);
	self.token = token;
}

-(void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
	NSLog(@"FAILD TO GET TOKEN: %@", error);
} 

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    [self showAlarm:notification.alertBody];
    //application.applicationIconBadgeNumber = 0;
    NSLog(@"AppDelegate didReceiveLocalNotification %@", notification.userInfo);
}

#pragma <LibTg FUNCTIONS>

-(void)loadTgLib{
	// ponytail: syncData runs 4 ops in parallel, so authorize/sendCode can race here
	@synchronized(self){
	if (self.tg)
		return;

	// connect to libtg
	NSString *databasePath = [[NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) 
						objectAtIndex:0] 
			stringByAppendingPathComponent:@"tgdata.db"];
	
	int SETUP_API_ID(apiId)
	char * SETUP_API_HASH(apiHash)
	
	self.tg = tg_new(
			[databasePath UTF8String],
			0,
			apiId, 
			apiHash,
			"pub.pkcs");
	if (!self.tg){
		[self showMessage:@"can't init LibTg"];
	} else {
			NSLog(@"LibTg inited");
			if (self.authorizationDelegate)
				[self.authorizationDelegate tgLibLoaded];
	}
	tg_set_on_error(self.tg, (__bridge void *)self, on_err);
	if ([NSUserDefaults.standardUserDefaults  boolForKey:@"debug"])
		tg_set_on_log(self.tg, (__bridge void *)self, on_log);
	} // @synchronized
}

static void on_err(void *d, const char *err)
{
	AppDelegate *self = (__bridge AppDelegate *)d;
	NSLog(@"%s", err);
	//dispatch_sync(dispatch_get_main_queue(), ^{
		//[self showMessage: 
				//[NSString stringWithFormat:@"%s", err]];	
	//});	
}

static void on_log(void *d, const char *msg)
{
	AppDelegate *self = (__bridge AppDelegate *)d;
	NSLog(@"%s", msg);
}

-(void)afteLoginUser:(tl_user_t *)user {
	self.authorizedUser = user;
	NSLog(@"AUTHORIZED! as: %s", user->username_.data);
	NSNumber *userId = [NSNumber numberWithLongLong:user->id_];
	[NSUserDefaults.standardUserDefaults 
		setValue:userId forKey:@"userId"];

	dispatch_async(dispatch_get_main_queue(), ^{
		self.loginVC = nil;
		// Swap the login screen out for the tab UI. showMainUI builds it, which
		// is what registers DialogsViewController as authorizationDelegate, so
		// it has to run before we notify the delegate below.
		[self showMainUI];

		if (self.authorizationDelegate)
			[self.authorizationDelegate authorizedAs:user];
		self.authorizationDelegate = nil;
	});
	if (self.token){
		[self.syncData addOperationWithBlock:^{
			if (tg_account_register_ios(self.tg, self.token.UTF8String, true) == 0)	
				NSLog(@"Register device with token: %@", self.token);
			else
				NSLog(@"Can't register device with token: %@", self.token);
		}];
	}
	// get colors
	[self getPeerColorset];
}

-(void)chechPassword:(NSString *)password 
{
	[self.syncData addOperationWithBlock:^{
		tl_user_t *user = tg_auth_check_password(
				self.tg, 
				[password UTF8String]);

		dispatch_async(dispatch_get_main_queue(), ^{
			if (user){
				[self afteLoginUser:user];
			} else {
				[self.loginVC setBusy:NO];
				[self showMessage:@"Password is incorrect!"];
			}
		});
	}];
}

-(void)signIn:(NSString *)phone_number 
				 code:(NSString *)code 
		 sentCode:(tl_auth_sentCode_t *)sentCode
{
	// set first launch
	[[NSUserDefaults standardUserDefaults] setBool:NO 
																					forKey:@"isNotFirstLaunch"];

	[self.syncData addOperationWithBlock:^{
		tl_user_t *user = tg_auth_signIn(
				self.tg, 
				sentCode, 
				[phone_number UTF8String], 
				[code UTF8String]);

		dispatch_async(dispatch_get_main_queue(), ^{
			if (user){
				[self afteLoginUser:user];
			} else {
				if (self.loginVC) {
					[self.loginVC showPasswordStep];
				} else {
					[self askInput:@"enter password" 
										onDone:^(NSString *text){
											[self chechPassword:text];
										}];
				}
			}
		});
	}];
}

-(void)sendCode:(NSString *)phone_number
{
	self.currentPhoneNumber = phone_number;
	[self.syncData addOperationWithBlock:^{
		[self loadTgLib];	// may still be initialising - the login form is shown early
		tl_auth_sentCode_t *sentCode =
			tg_auth_sendCode(
					self.tg,
					[phone_number UTF8String]);
					
		dispatch_async(dispatch_get_main_queue(), ^{
			if (sentCode){
				self.currentSentCode = sentCode;
				if (self.loginVC) {
					[self.loginVC showCodeStepWithPhoneNumber:phone_number];
				} else {
					[self askInput:@"enter phone_code" 
									onDone:^(NSString *text){
										[self signIn:phone_number 
														code:text sentCode:sentCode];
									}];
				}
			} else {
				[self.loginVC setBusy:NO];
				[self showMessage:@"Failed to send authorization code. Please check number."];
			}
		});
	}];
}

// TDLib drives authorization now. libtg still owns the chat UI, so both run
// until the rest of the migration lands.
-(void)startTDLibAuth{
	TGClient *tg = [TGClient shared];

	__weak typeof(self) weakSelf = self;
	tg.onAuthState = ^(TGAuthState state){
		NSLog(@"TDLIB AUTH: state %d", (int)state);
		AppDelegate *me = weakSelf;
		if (!me) return;

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
			NSLog(@"TDLIB AUTH: unavailable, falling back to libtg");
	});
}

-(void)showMainUI{
	if (!self.rootViewController)
		self.rootViewController = [[RootViewController alloc]init];
	if (self.window.rootViewController != self.rootViewController)
		[self.window setRootViewController:self.rootViewController];
}

-(void)showLoginUI{
	if (self.loginVC)
		return;

	TGLoginViewController *loginVC = [[TGLoginViewController alloc] init];
	self.loginVC = loginVC;

	// Route through TDLib when it loaded; libtg is the fallback.
	__weak typeof(self) weakSelf = self;
	loginVC.onPhoneSubmitted = ^(NSString *phoneNumber) {
		weakSelf.currentPhoneNumber = phoneNumber;
		if ([TGClient shared].available)
			[[TGClient shared] sendPhoneNumber:phoneNumber];
		else
			[weakSelf sendCode:phoneNumber];
	};
	loginVC.onCodeSubmitted = ^(NSString *code) {
		if ([TGClient shared].available)
			[[TGClient shared] sendCode:code];
		else
			[weakSelf signIn:weakSelf.currentPhoneNumber code:code sentCode:weakSelf.currentSentCode];
	};
	loginVC.onPasswordSubmitted = ^(NSString *password) {
		if ([TGClient shared].available)
			[[TGClient shared] sendPassword:password];
		else
			[weakSelf chechPassword:password];
	};

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:loginVC];
	[self.window setRootViewController:nav];
}

-(void)authorize{
	// do in background
	[self.syncData addOperationWithBlock:^{
		[self loadTgLib];

		if (!self.tg)
			return;

		// check authorized
		tl_user_t *user = tg_is_authorized(self.tg);

		// authorize if needed
		dispatch_async(dispatch_get_main_queue(), ^{
			if (user)
				[self afteLoginUser:user];
			else
				[self showLoginUI];
		});

		// No auth key yet? Build it now, while the user is still typing the
		// phone number. It is a full RSA2048 + DH handshake - the bulk of the
		// wait on an A5 - and tg_auth_sendCode would otherwise pay for it only
		// after the Next tap.
		if (!user && !tg_has_auth_key(self.tg)){
			NSLog(@"prewarming auth key...");
			tg_new_auth_key(self.tg);
			NSLog(@"auth key ready");
		}
	}];
}

- (void)applicationWillResignActive:(UIApplication *)application {
	//if (self.appActivityDelegate)
		//[self.appActivityDelegate willResignActive];
	//[self.syncData cancelAllOperations];
}

static int getPeerColorsetCb(void *d, uint32_t color_id, tg_colors_t *colors, tg_colors_t *dark_colors)
{
	NSMutableArray *array = (__bridge NSMutableArray *)d;
	NSDictionary *c = @{
		@"color_id":[NSNumber numberWithInt:color_id],
		@"rgb0":[NSNumber numberWithInt:colors->rgb0],
		@"rgb1":[NSNumber numberWithInt:colors->rgb1],
		@"rgb2":[NSNumber numberWithInt:colors->rgb2],
		@"darkRgb0":[NSNumber numberWithInt:dark_colors->rgb0],
		@"darkRgb1":[NSNumber numberWithInt:dark_colors->rgb1],
		@"darkRgb2":[NSNumber numberWithInt:dark_colors->rgb2],
	};

	[array addObject:c];
	return 0;
}

- (void) getPeerColorset{
	NSMutableArray *array = [NSMutableArray array];
	[self.syncData addOperationWithBlock:^{
		NSInteger hash = 
			[NSUserDefaults.standardUserDefaults integerForKey:@"colorsetHash"];
		
		hash = tg_get_peer_colors(
				self.tg, 
				hash, 
				(__bridge void *)array, getPeerColorsetCb);

		//dispatch_sync(dispatch_get_main_queue(), ^{
			//NSString *str = 
				//[NSString stringWithFormat:@"%@", array];
			//[self showMessage:str];
		//});

		[NSUserDefaults.standardUserDefaults 
			setInteger:hash forKey:@"colorsetHash"];

		[NSUserDefaults.standardUserDefaults 
			setObject:array forKey:@"colorset"];
		self.colorset = array;
	}];
}

-(Boolean)isOnLineAndAuthorized{
	Boolean hasTg    = self.tg != NULL;
	Boolean hasUser  = self.authorizedUser != nil;
	Boolean isOnline = self.reach.isReachable;

	if (!(hasTg && hasUser && isOnline))
		NSLog(@"isOnLineAndAuthorized NO: tg=%d user=%d reachable=%d",
				hasTg, hasUser, isOnline);

	return hasTg && hasUser && isOnline;
}

-(void)setDebug:(Boolean)debug {
	if (!self.tg)
		return;
	NSLog(@"Set debugging %s", debug?"ON":"OFF");
	if (debug)
		tg_set_on_log(self.tg, (__bridge void *)self, on_log);
	else 
		tg_set_on_log(self.tg, NULL, NULL);

}
-(void)toggleShowNotifications:(Boolean)showNotifications
{
	NSLog(@"Set showNotifications %s", 
			showNotifications?"ON":"OFF");
	[NSUserDefaults.standardUserDefaults 
			setBool:showNotifications forKey:@"showNotifications"];
	self.showNotifications = showNotifications;
}

- (BOOL)application:(UIApplication *)application 
			handleOpenURL:(NSURL *)url 
{
	// Was an alert on every URL open, which blocks scripted launches
	// (scripts/devrun.sh starts the app with `uiopen itglegacy://`).
	NSLog(@"handleOpenURL: %@", url);

	// itglegacy://screenshot - the app photographs itself into Caches, which
	// devrun.sh then pulls over SSH. There is no screenshot binary on this
	// device and iOS 7 + 30-pin cannot be mirrored to a Mac, so this is the
	// only way to actually see the UI without someone holding the phone.
	// itglegacy://phone/+380XXXXXXXXX - hand a phone number to TDLib without
	// touching the screen and without the number ever entering the repository.
	if ([url.host isEqualToString:@"phone"]){
		NSString *number = [url.path stringByReplacingOccurrencesOfString:@"/" withString:@""];
		if (number.length){
			NSLog(@"phone from URL: %lu digits", (unsigned long)number.length);
			self.currentPhoneNumber = number;
			[[TGClient shared] sendPhoneNumber:number];
		}
		return true;
	}

	// itglegacy://code/12345 and itglegacy://password/... - the account owner
	// runs these from their own terminal so the secret never passes through
	// anyone else. Same mechanism as phone, different TDLib call.
	if ([url.host isEqualToString:@"code"] || [url.host isEqualToString:@"password"]){
		NSString *value = [url.path stringByReplacingOccurrencesOfString:@"/" withString:@""];
		if (value.length){
			// deliberately never logged
			NSLog(@"%@ received from URL (%lu chars)", url.host, (unsigned long)value.length);
			if ([url.host isEqualToString:@"code"])
				[[TGClient shared] sendCode:value];
			else
				[[TGClient shared] sendPassword:value];
		}
		return true;
	}

	if ([url.host isEqualToString:@"screenshot"]){
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
			NSLog(@"screenshot %@ -> %@", ok ? @"saved" : @"FAILED", path);
		});
	}
	//if ([url.host isEqualToString:@"authorize"]){

		//NSString *fragment = url.fragment;
		//NSArray *array = [fragment componentsSeparatedByString:@"&"];
		//for (NSString *item in array) {
			//NSArray *pair = [item componentsSeparatedByString:@"="];
			//NSString *key = [pair objectAtIndex:0];
			//NSString *value = [pair objectAtIndex:1];
			//[[NSUserDefaults standardUserDefaults]setValue:value forKey:key];
		//}
		//UIAlertView *alert = 
					//[[UIAlertView alloc]initWithTitle:@"response" 
					//message:fragment
					//delegate:nil 
					//cancelButtonTitle:@"Закрыть" 
					//otherButtonTitles:nil];
		//[alert show];
	//}
	return true;
}

-(void)removeUnredId:(uint64_t)fromId{
	for (NSNumber *n in self.unread){
		if (n.longLongValue == fromId){
			[self.unread removeObject:n];
			[NSUserDefaults.standardUserDefaults setObject:self.unread 
																						 forKey:@"unread"];
			UIApplication.sharedApplication.applicationIconBadgeNumber = 
				self.unread.count;
			UINavigationController *nc =
				[((RootViewController *)self.rootViewController).viewControllers objectAtIndex:1]; 
			if (nc){
				nc.tabBarItem.badgeValue = 
					[NSString stringWithFormat:@"%ld", self.unread.count];
			}
			return;
		}
	}
}

- (void)setupPlayAndRecordAudioSession
{
	AVAudioSession *audioSession = [AVAudioSession sharedInstance];
	//if (audioSession.category != AVAudioSessionCategoryPlayback) {
	if (audioSession.category != AVAudioSessionCategoryPlayAndRecord) {
		UIDevice *device = [UIDevice currentDevice];
		if ([device respondsToSelector:@selector(isMultitaskingSupported)]) {
			if (device.multitaskingSupported) {										                
				
				NSError *setCategoryError = nil;
				//[audioSession setCategory:AVAudioSessionCategoryPlayback
				[audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
											withOptions: 
					AVAudioSessionCategoryOptionAllowBluetooth|
					AVAudioSessionCategoryOptionDefaultToSpeaker|
					AVAudioSessionCategoryOptionDuckOthers 
											error:&setCategoryError];
				if (setCategoryError)
					NSLog(@"%@", setCategoryError.description);
				
				NSError *activationError = nil;
				[audioSession setActive:YES error:&activationError];
				if (activationError)
					NSLog(@"%@", activationError.description);
			}
		}									    
	}				
}
- (void)setupSoloAmbientAudioSession
{
	AVAudioSession *audioSession = [AVAudioSession sharedInstance];
	//if (audioSession.category != AVAudioSessionCategoryPlayback) {
	if (audioSession.category != AVAudioSessionCategorySoloAmbient) {
		UIDevice *device = [UIDevice currentDevice];
		if ([device respondsToSelector:@selector(isMultitaskingSupported)]) {
			if (device.multitaskingSupported) {										                
				
				NSError *setCategoryError = nil;
				//[audioSession setCategory:AVAudioSessionCategoryPlayback
				[audioSession setCategory:AVAudioSessionCategorySoloAmbient
											withOptions:0 
											error:&setCategoryError];
				if (setCategoryError)
					NSLog(@"%@", setCategoryError.description);
				
				NSError *activationError = nil;
				[audioSession setActive:YES error:&activationError];
				if (activationError)
					NSLog(@"%@", activationError.description);
			}
		}									    
	}				
}
@end

// vim:ft=objc

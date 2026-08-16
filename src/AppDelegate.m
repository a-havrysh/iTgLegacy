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
#import "TGNotificationManager.h"
#import "TGMusicPlayer.h"
#import "TGHacks.h"
#import "TGIcons.h"
#import "TGDiskCache.h"
#import "TGAlertView.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <malloc/malloc.h>

@protocol TGTabBarHitTesting <NSObject>
- (int)indexForLocation:(CGPoint)location;
@end

static NSTimeInterval TGLaunchStarted = 0;
static NSTimeInterval TGOpenStarted = 0;
static BOOL TGOpenFrameSeen = NO;
static BOOL TGOpenSettledSeen = NO;
static unsigned long long TGResidentPeak = 0;
static volatile double TGMainPingAt = 0;

unsigned long long TGResidentBytes(void) {
	struct task_basic_info info;
	mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
	if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS)
		return 0;
	unsigned long long rss = (unsigned long long)info.resident_size;
	if (rss > TGResidentPeak)
		TGResidentPeak = rss;
	return rss;
}

static double TGProcessCPUSeconds(void) {
	double total = 0;
	struct task_basic_info basic;
	mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
	if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&basic, &count) == KERN_SUCCESS){
		total += basic.user_time.seconds + basic.user_time.microseconds / 1e6;
		total += basic.system_time.seconds + basic.system_time.microseconds / 1e6;
	}
	struct task_thread_times_info times;
	count = TASK_THREAD_TIMES_INFO_COUNT;
	if (task_info(mach_task_self(), TASK_THREAD_TIMES_INFO, (task_info_t)&times, &count) == KERN_SUCCESS){
		total += times.user_time.seconds + times.user_time.microseconds / 1e6;
		total += times.system_time.seconds + times.system_time.microseconds / 1e6;
	}
	return total;
}

static volatile BOOL TGPerfLoggingOn = NO;

/// The running commentary - a resident-size line four times a second, one line
/// per image decoded - costs real time on this hardware, so it stays off until
/// itglegacy://perflog/on asks for it.
BOOL TGPerfLogging(void) {
	return TGPerfLoggingOn;
}

static thread_t TGMainThreadPort = MACH_PORT_NULL;
static volatile BOOL TGStackSamplingOn = NO;

static BOOL TGPeek(const void *address, void *into, size_t length) {
	vm_size_t got = 0;
	if (vm_read_overwrite(mach_task_self(), (vm_address_t)address, length,
			(vm_address_t)into, &got) != KERN_SUCCESS)
		return NO;
	return got == length;
}

static int TGCaptureMainStack(void **frames, int maximum) {
	if (TGMainThreadPort == MACH_PORT_NULL)
		return 0;
	if (thread_suspend(TGMainThreadPort) != KERN_SUCCESS)
		return 0;
	int found = 0;
#if defined(__arm__)
	_STRUCT_ARM_THREAD_STATE state;
	mach_msg_type_number_t count = ARM_THREAD_STATE_COUNT;
	if (thread_get_state(TGMainThreadPort, ARM_THREAD_STATE,
			(thread_state_t)&state, &count) == KERN_SUCCESS){
		frames[found++] = (void *)state.__pc;
		if (state.__lr && found < maximum)
			frames[found++] = (void *)state.__lr;
		const void **link = (const void **)state.__r[7];
		while (found < maximum && link && ((uintptr_t)link & 3) == 0){
			const void *next = NULL;
			const void *returnAddress = NULL;
			if (!TGPeek(link, &next, sizeof(next)))
				break;
			if (!TGPeek(link + 1, &returnAddress, sizeof(returnAddress)))
				break;
			if (!returnAddress)
				break;
			frames[found++] = (void *)returnAddress;
			if ((const void **)next <= link)
				break;
			link = (const void **)next;
		}
	}
#endif
	thread_resume(TGMainThreadPort);
	return found;
}

static void TGLogMainStack(void) {
	void *frames[48];
	int found = TGCaptureMainStack(frames, 48);
	if (found <= 0)
		return;
	char line[4000];
	size_t used = 0;
	for (int i = 0; i < found && used < sizeof(line) - 90; i++){
		Dl_info info;
		memset(&info, 0, sizeof(info));
		const char *symbol = "?";
		const char *image = "?";
		if (dladdr(frames[i], &info)){
			if (info.dli_sname)
				symbol = info.dli_sname;
			if (info.dli_fname){
				const char *slash = strrchr(info.dli_fname, '/');
				image = slash ? slash + 1 : info.dli_fname;
			}
		}
		used += snprintf(line + used, sizeof(line) - used, "%s%s`%s",
				i ? " < " : "", image, symbol);
	}
	line[sizeof(line) - 1] = 0;
	NSLog(@"PERF stack | %s", line);
}

/// RSS split by what asked the kernel for the pages. malloc statistics only
/// see the heap, and on this app the heap is a fifth of the resident size, so
/// the answer to "what is resident" is only ever visible here.
static void TGRegionReport(NSString *tag) {
	vm_address_t address = 0;
	unsigned long long byTag[256];
	unsigned long long dirtyByTag[256];
	memset(byTag, 0, sizeof(byTag));
	memset(dirtyByTag, 0, sizeof(dirtyByTag));

	while (1){
		vm_size_t size = 0;
		uint32_t depth = 1;
		struct vm_region_submap_info_64 info;
		mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
		if (vm_region_recurse_64(mach_task_self(), &address, &size, &depth,
				(vm_region_recurse_info_t)&info, &count) != KERN_SUCCESS)
			break;
		if (info.is_submap){
			depth++;
			continue;
		}
		unsigned int slot = info.user_tag & 0xFF;
		byTag[slot] += (unsigned long long)info.pages_resident * vm_page_size;
		dirtyByTag[slot] += (unsigned long long)info.pages_dirtied * vm_page_size;
		address += size;
	}

	for (unsigned int i = 0; i < 256; i++){
		if (byTag[i] < 1048576)
			continue;
		NSLog(@"PERF region %@ tag=%u resident=%.2f MB dirty=%.2f MB",
				tag, i, byTag[i] / 1048576.0, dirtyByTag[i] / 1048576.0);
	}
}

void TGMemMark(NSString *tag) {
	vm_address_t *zones = NULL;
	unsigned int count = 0;
	unsigned long long inUse = 0;
	if (malloc_get_all_zones(mach_task_self(), NULL, &zones, &count) == KERN_SUCCESS){
		for (unsigned int i = 0; i < count; i++){
			malloc_zone_t *zone = (malloc_zone_t *)zones[i];
			if (!zone || !zone->introspect)
				continue;
			malloc_statistics_t stats;
			memset(&stats, 0, sizeof(stats));
			malloc_zone_statistics(zone, &stats);
			inUse += stats.size_in_use;
		}
	}
	NSLog(@"PERF mem %@ rss=%.2f MB peak=%.2f MB heap=%.2f MB cpu=%.2f s",
			tag, TGResidentBytes() / 1048576.0, TGResidentPeak / 1048576.0,
			inUse / 1048576.0, TGProcessCPUSeconds());
}

/// The stage marks below used to start counting at didFinishLaunching, which
/// hides everything dyld does first. A tap starts the process, so the honest
/// zero is the exec time the kernel recorded for this pid.
static NSTimeInterval TGProcessStarted(void) {
	static NSTimeInterval started = -1;
	if (started >= 0)
		return started;
	int name[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
	struct kinfo_proc info;
	size_t length = sizeof(info);
	memset(&info, 0, sizeof(info));
	if (sysctl(name, 4, &info, &length, NULL, 0) != 0 || length == 0){
		started = 0;
		return started;
	}
	NSTimeInterval unix = info.kp_proc.p_starttime.tv_sec +
			info.kp_proc.p_starttime.tv_usec / 1e6;
	started = unix - NSTimeIntervalSince1970;
	return started;
}

static double TGSinceTap(void) {
	NSTimeInterval started = TGProcessStarted();
	if (started <= 0)
		return -1;
	return ([NSDate timeIntervalSinceReferenceDate] - started) * 1000.0;
}

/// stderr into a file so TDLib's own diagnostics survive a crash and can be
/// read off the device; scripts/devrun.sh pulls it. This runs from main, not
/// from didFinishLaunching, because everything UIKit does in between - and
/// every stage mark taken there - is otherwise written to a stderr nobody
/// reads. The previous run is kept: an uncaught exception prints its reason to
/// stderr and the process dies, so without the rotation the one message that
/// explains a crash is deleted by the next launch.
void TGRedirectLogToFile(void) {
	NSString *cache = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *log = [cache stringByAppendingPathComponent:@"log.txt"];
	NSString *lastlog = [cache stringByAppendingPathComponent:@"lastlog.txt"];
	[[NSFileManager defaultManager] removeItemAtPath:lastlog error:nil];
	[[NSFileManager defaultManager] moveItemAtPath:log toPath:lastlog error:nil];
	freopen(log.UTF8String, "a+", stderr);
}

void TGNoteImageReady(NSTimeInterval when) {
	if (when <= 0)
		return;
	NSTimeInterval started = TGProcessStarted();
	if (started <= 0)
		return;
	NSLog(@"PERF launch (tap +%.0f ms): image ready, dyld and the kernel done",
			(when - started) * 1000.0);
}

void TGMarkLaunchStage(NSString *stage) {
	if (TGLaunchStarted <= 0)
		TGLaunchStarted = [NSDate timeIntervalSinceReferenceDate];
	NSLog(@"PERF launch +%.0f ms (tap +%.0f ms): %@ rss=%.2f MB cpu=%.2f s",
			([NSDate timeIntervalSinceReferenceDate] - TGLaunchStarted) * 1000.0,
			TGSinceTap(), stage,
			TGResidentBytes() / 1048576.0, TGProcessCPUSeconds());
}

/// A stage mark says when the app handed a layer tree to Core Animation, not
/// when the pixels appeared. The completion block of the transaction that
/// carries those layers is the last point this process can observe, so the
/// frame marks below hang off it.
/// A frame mark is a number; the screenshot is the evidence behind it. The
/// capture costs 100 ms of its own, so it happens only when a measuring run
/// has asked for it and always after the timestamp has been taken.
static void TGCaptureFrame(NSString *name) {
	if (![[NSUserDefaults standardUserDefaults] boolForKey:@"tgCaptureFrames"])
		return;
	UIWindow *window = [[UIApplication sharedApplication] keyWindow];
	if (!window)
		return;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, scale);
	[window.layer renderInContext:UIGraphicsGetCurrentContext()];
	UIImage *shot = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	NSString *cache = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	[UIImagePNGRepresentation(shot)
			writeToFile:[cache stringByAppendingPathComponent:name] atomically:YES];
	NSLog(@"PERF captured %@", name);
}

void TGMarkFirstFrame(NSString *stage) {
	[CATransaction begin];
	[CATransaction setCompletionBlock:^{
		TGMarkLaunchStage(stage);
		TGCaptureFrame(@"firstframe.png");
	}];
	[CATransaction commit];
}

static dispatch_semaphore_t TGTextWarmGate(void) {
	static dispatch_semaphore_t gate = NULL;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		gate = dispatch_semaphore_create(0);
	});
	return gate;
}

void TGWaitForTextWarm(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		dispatch_semaphore_wait(TGTextWarmGate(),
				dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
	});
}

/// The clock for opening a conversation starts at the tap, not at viewDidLoad -
/// pushing the controller is itself part of what the finger waits through.
void TGBeginOpenTimingFromTap(void) {
	TGOpenStarted = [NSDate timeIntervalSinceReferenceDate];
	TGOpenFrameSeen = NO;
	TGOpenSettledSeen = NO;
}

void TGBeginOpenTiming(void) {
	if (TGOpenStarted > 0)
		return;
	TGOpenStarted = [NSDate timeIntervalSinceReferenceDate];
	TGOpenFrameSeen = NO;
	TGOpenSettledSeen = NO;
}

void TGMarkOpenStage(NSString *stage) {
	if (TGOpenStarted <= 0)
		return;
	NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - TGOpenStarted;
	if (elapsed > 20.0){
		TGOpenStarted = 0;
		return;
	}
	NSLog(@"PERF open +%.0f ms: %@", elapsed * 1000.0, stage);
}

/// The one that matters: the first frame in which the conversation is
/// readable, and later the frame that holds the whole history. Each is
/// reported once, and the second closes the open timing so the next tap starts
/// from zero.
void TGMarkOpenFrame(NSString *stage) {
	if (TGOpenStarted <= 0 || TGOpenFrameSeen)
		return;
	TGOpenFrameSeen = YES;
	[CATransaction begin];
	[CATransaction setCompletionBlock:^{
		TGMarkOpenStage(stage);
		TGCaptureFrame(@"openframe.png");
	}];
	[CATransaction commit];
}

void TGMarkOpenSettledFrame(NSString *stage) {
	if (TGOpenStarted <= 0 || TGOpenSettledSeen)
		return;
	TGOpenSettledSeen = YES;
	[CATransaction begin];
	[CATransaction setCompletionBlock:^{
		TGMarkOpenStage(stage);
		TGOpenStarted = 0;
		TGCaptureFrame(@"settledframe.png");
	}];
	[CATransaction commit];
}

@implementation AppDelegate

+ (void)tgPingMainThread {
	TGMainPingAt = [NSDate timeIntervalSinceReferenceDate];
}

+ (void)tgStackSamplerLoop {
	while (1){
		if (TGStackSamplingOn){
			@autoreleasepool {
				TGLogMainStack();
			}
		}
		usleep(25000);
	}
}

+ (void)tgMemorySamplerLoop {
	NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
	double worstStall = 0;
	while (1){
		@autoreleasepool {
			if (!TGPerfLoggingOn){
				usleep(250000);
				continue;
			}
			NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
			double stall = TGMainPingAt > 0 ? (now - TGMainPingAt) : 0;
			if (stall > worstStall)
				worstStall = stall;
			NSLog(@"PERF sample +%.0f ms rss=%.2f MB peak=%.2f MB cpu=%.2f s stall=%.0f worst=%.0f",
					(now - started) * 1000.0,
					TGResidentBytes() / 1048576.0,
					TGResidentPeak / 1048576.0,
					TGProcessCPUSeconds(),
					stall * 1000.0, worstStall * 1000.0);
		}
		usleep(250000);
	}
}

static void TGStartMemorySampler(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// A launch is over before a URL can turn sampling on, so the switch
		// for it has to survive the previous run.
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"tgStacksAtLaunch"])
			TGStackSamplingOn = YES;
		TGMainThreadPort = mach_thread_self();
		TGMainPingAt = [NSDate timeIntervalSinceReferenceDate];
		dispatch_async(dispatch_get_main_queue(), ^{
			[NSTimer scheduledTimerWithTimeInterval:0.05
											 target:[AppDelegate class]
										   selector:@selector(tgPingMainThread)
										   userInfo:nil
											repeats:YES];
		});
		[NSThread detachNewThreadSelector:@selector(tgMemorySamplerLoop)
								 toTarget:[AppDelegate class]
							   withObject:nil];
		[NSThread detachNewThreadSelector:@selector(tgStackSamplerLoop)
								 toTarget:[AppDelegate class]
							   withObject:nil];
	});
}

+ (void)tgWarmEmojiFont {
	@autoreleasepool {
		unichar units[2] = {0x2764, 0xFE0F};
		CTFontRef font = CTFontCreateWithName(CFSTR("AppleColorEmoji"), 14.0f, NULL);
		if (!font){
			dispatch_semaphore_signal(TGTextWarmGate());
			return;
		}
		NSDictionary *attributes = [NSDictionary dictionaryWithObject:(__bridge id)font
				forKey:(__bridge NSString *)kCTFontAttributeName];
		NSAttributedString *string = [[NSAttributedString alloc]
				initWithString:[NSString stringWithCharacters:units length:2]
					attributes:attributes];
		CTLineRef line = CTLineCreateWithAttributedString(
				(__bridge CFAttributedStringRef)string);
		if (line){
			CGFloat ascent = 0, descent = 0, leading = 0;
			CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
			CFRelease(line);
		}
		CFRelease(font);

		NSString *probe = [NSString stringWithCharacters:units length:2];
		NSArray *fonts = @[[UIFont boldSystemFontOfSize:16.0f],
						   [UIFont systemFontOfSize:14.0f],
						   [UIFont systemFontOfSize:13.0f]];
		for (UIFont *warm in fonts)
			[probe sizeWithFont:warm
			  constrainedToSize:CGSizeMake(1000, 40)
				  lineBreakMode:NSLineBreakByWordWrapping];
		dispatch_semaphore_signal(TGTextWarmGate());
	}
}

static UIBackgroundTaskIdentifier TGBackgroundTask;
static BOOL TGBackgroundTaskActive = NO;
static int64_t TGPendingNotificationChatId = 0;

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
	TGMarkLaunchStage(@"didFinishLaunching");
	TGStartMemorySampler();
	[NSThread detachNewThreadSelector:@selector(tgWarmEmojiFont)
							 toTarget:[AppDelegate class]
						   withObject:nil];
	[TGHacks hackSetAnimationDuration];

	NSString *cache = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];

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

	NSString *databaseDirectory = [TGDiskCache databaseDirectory];

	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	if ([NSUserDefaults.standardUserDefaults boolForKey:@"tgWasSignedIn"]){
		[[TGClient shared] loadCachedChats];
		TGMarkLaunchStage(@"snapshot loaded");
		[self showMainUI];
	} else {
		[self showLoadingUI];
	}
	TGMarkLaunchStage(@"before makeKeyAndVisible");
	[self.window makeKeyAndVisible];
	TGMarkLaunchStage(@"window on screen");
	TGMarkFirstFrame(@"FIRST FRAME");

	[self startTDLib];
	[TGDiskCache sweep];
	[TGDiskCache protectTreeAtPath:databaseDirectory];

	UILocalNotification *launchNotification =
			launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
	if ([launchNotification isKindOfClass:[UILocalNotification class]])
		TGPendingNotificationChatId =
				[[TGNotificationManager shared] chatIdForLocalNotification:launchNotification];

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
	[[TGClient shared] saveCachedChats];
	[[NSURLCache sharedURLCache] removeAllCachedResponses];
	[[TGNotificationManager shared] applicationDidEnterBackground];

	if (![application respondsToSelector:@selector(beginBackgroundTaskWithExpirationHandler:)])
		return;
	if (TGBackgroundTaskActive)
		return;
	TGBackgroundTaskActive = YES;
	TGBackgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
		if (!TGBackgroundTaskActive)
			return;
		TGBackgroundTaskActive = NO;
		[[UIApplication sharedApplication] endBackgroundTask:TGBackgroundTask];
	}];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
	if (!TGBackgroundTaskActive)
		return;
	TGBackgroundTaskActive = NO;
	[application endBackgroundTask:TGBackgroundTask];
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
	[[TGMusicPlayer shared] handleRemoteControlEvent:event];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	[[TGNotificationManager shared] applicationDidBecomeActive];
	if (!TGPendingNotificationChatId)
		return;
	int64_t chatId = TGPendingNotificationChatId;
	TGPendingNotificationChatId = 0;
	[self openChatFromNotification:chatId];
}

- (void)application:(UIApplication *)application
		didReceiveLocalNotification:(UILocalNotification *)notification {
	int64_t chatId = [[TGNotificationManager shared]
			chatIdForLocalNotification:notification];
	if (!chatId)
		return;
	if (application.applicationState == UIApplicationStateActive){
		[[TGNotificationManager shared] clearNotificationsForChat:chatId];
		return;
	}
	TGPendingNotificationChatId = chatId;
}

- (void)openChatFromNotification:(int64_t)chatId {
	if (!chatId)
		return;
	dispatch_async(dispatch_get_main_queue(), ^{
		UITabBarController *tabs = (UITabBarController *)self.rootViewController;
		if (![tabs isKindOfClass:UITabBarController.class] || tabs.viewControllers.count < 2){
			TGPendingNotificationChatId = chatId;
			return;
		}

		NSDictionary *found = nil;
		for (id entry in [TGClient shared].chats){
			if ([entry isKindOfClass:[NSDictionary class]] &&
				[entry[@"id"] longLongValue] == chatId){
				found = entry;
				break;
			}
		}

		tabs.selectedIndex = 1;
		UINavigationController *nc = tabs.viewControllers[1];
		[nc popToRootViewControllerAnimated:NO];

		if ([found[@"isForum"] boolValue]){
			TGTopicsViewController *topics = [[TGTopicsViewController alloc] init];
			topics.chatId = chatId;
			topics.chatTitle = found[@"title"];
			[nc pushViewController:topics animated:NO];
		} else {
			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = chatId;
			vc.chatTitle = found[@"title"] ?: @"Chat";
			vc.isGroup = [found[@"isGroup"] boolValue];
			if (![RootViewController presentInDetail:vc])
				[nc pushViewController:vc animated:NO];
		}

		[[TGNotificationManager shared] clearNotificationsForChat:chatId];
	});
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
				[[TGNotificationManager shared] start];
				if (TGPendingNotificationChatId){
					int64_t pending = TGPendingNotificationChatId;
					TGPendingNotificationChatId = 0;
					[me openChatFromNotification:pending];
				}
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

- (UIViewController *)topControllerOnScreen {
	UINavigationController *detail = [RootViewController detailNavigationController];
	if (detail != nil && ![detail.topViewController isKindOfClass:
			NSClassFromString(@"TGDetailPlaceholderViewController")])
		return detail.topViewController;
	UITabBarController *tabs = (UITabBarController *)self.rootViewController;
	if (![tabs isKindOfClass:UITabBarController.class])
		return nil;
	id nc = tabs.viewControllers[tabs.selectedIndex];
	return [nc isKindOfClass:UINavigationController.class]
			? [(UINavigationController *)nc topViewController] : nc;
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

	if ([host isEqualToString:@"mem"]){
		TGMemMark(arg.length ? arg : @"probe");
		return YES;
	}

	if ([host isEqualToString:@"regions"]){
		TGMemMark(arg.length ? arg : @"regions");
		TGRegionReport(arg.length ? arg : @"regions");
		return YES;
	}

	if ([host isEqualToString:@"captureframes"]){
		[[NSUserDefaults standardUserDefaults] setBool:[arg isEqualToString:@"on"]
												forKey:@"tgCaptureFrames"];
		[[NSUserDefaults standardUserDefaults] synchronize];
		NSLog(@"PERF captureframes %@", arg);
		return YES;
	}

	if ([host isEqualToString:@"perflog"]){
		TGPerfLoggingOn = [arg isEqualToString:@"on"];
		NSLog(@"PERF perflog %@", TGPerfLoggingOn ? @"on" : @"off");
		return YES;
	}

	if ([host isEqualToString:@"stacks"]){
		TGStackSamplingOn = [arg isEqualToString:@"on"];
		NSLog(@"PERF stacks %@", TGStackSamplingOn ? @"on" : @"off");
		return YES;
	}

	if ([host isEqualToString:@"stacksatlaunch"]){
		[[NSUserDefaults standardUserDefaults] setBool:[arg isEqualToString:@"on"]
												forKey:@"tgStacksAtLaunch"];
		[[NSUserDefaults standardUserDefaults] synchronize];
		NSLog(@"PERF stacksatlaunch %@", arg);
		return YES;
	}

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
			TGBeginOpenTimingFromTap();
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

	if ([host isEqualToString:@"alerttest"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSInteger which = [arg integerValue];
			NSString *longTitle = @"A Very Long Prompt Title That Has To Wrap Onto Several Lines";
			TGAlertView *alert = nil;
			if (which == 1)
				alert = [[TGAlertView alloc] initWithTitle:@"Confirmation Code"
						message:@"Type the code you received."
						delegate:nil cancelButtonTitle:@"Cancel" otherButtonTitles:nil];
			else if (which == 2)
				alert = [[TGAlertView alloc] initWithTitle:@"New Poll"
						message:@"The question"
						delegate:nil cancelButtonTitle:@"Cancel" otherButtonTitles:@"Next", nil];
			else if (which == 3)
				alert = [[TGAlertView alloc] initWithTitle:@"New Poll"
						message:@"Option 1"
						delegate:nil cancelButtonTitle:@"Cancel" otherButtonTitles:@"Add", @"Send", nil];
			else if (which == 4)
				alert = [[TGAlertView alloc] initWithTitle:longTitle
						message:@"Option 1"
						delegate:nil cancelButtonTitle:@"Cancel" otherButtonTitles:@"Add", @"Send", nil];
			else if (which == 5)
				alert = [[TGAlertView alloc] initWithTitle:longTitle
						message:nil
						delegate:nil cancelButtonTitle:@"Cancel" otherButtonTitles:@"Save", nil];
			else
				alert = [[TGAlertView alloc] initWithTitle:@"Reply"
						message:nil
						delegate:nil cancelButtonTitle:@"Cancel" otherButtonTitles:@"Send", nil];
			alert.alertViewStyle = UIAlertViewStylePlainTextInput;
			if (which == 9){
				NSString *info = [NSString stringWithFormat:@"%@ tg=%d n=%d own=%d",
						NSStringFromClass([alert class]),
						(int)[alert isKindOfClass:[TGAlertView class]],
						(int)alert.numberOfButtons,
						(int)[alert respondsToSelector:NSSelectorFromString(@"usesOwnLayout")]];
				UIAlertView *probe = [[UIAlertView alloc] initWithTitle:info
						message:@"probe" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
				[probe show];
				return;
			}
			[alert show];
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
			UIViewController *top = [self topControllerOnScreen];
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
			UIViewController *top = [self topControllerOnScreen];
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
			UIViewController *top = [self topControllerOnScreen];
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
			UIViewController *top = [self topControllerOnScreen];
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
			UIViewController *top = [self topControllerOnScreen];
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
				top = [self topControllerOnScreen];
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

#import "TGLaunchSnapshot.h"
#import <QuartzCore/QuartzCore.h>
#include <sys/stat.h>

static NSString *const TGLaunchSnapshotEnabledKey = @"tgLaunchSnapshot";
static NSString *const TGLaunchSnapshotInstalledKey = @"tgLaunchSnapshotInstalled";
static NSString *const TGLaunchSnapshotOffsetKey = @"tgLaunchSnapshotListOffset";

static NSString *TGLaunchLastNote = @"nothing yet";

static void TGLaunchNote(NSString *format, ...) {
	va_list args;
	va_start(args, format);
	NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	TGLaunchLastNote = line;
	NSLog(@"PERF launchimage %@", line);
}

static NSArray *TGLaunchImageNames(void) {
	UIScreen *screen = [UIScreen mainScreen];
	CGSize size = screen.bounds.size;
	CGFloat scale = [screen respondsToSelector:@selector(scale)] ? screen.scale : 1.0f;
	CGFloat height = MAX(size.width, size.height);

	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
		return scale > 1.0f
				? @[@"Default-Portrait@2x~ipad.png", @"LaunchImage-Portrait@2x~ipad.png"]
				: @[@"Default-Portrait~ipad.png", @"LaunchImage-Portrait~ipad.png"];

	if (height >= 568.0f)
		return @[@"Default-568h@2x.png", @"LaunchImage-568h@2x.png"];

	return scale > 1.0f
			? @[@"Default@2x.png", @"LaunchImage@2x.png"]
			: @[@"Default.png", @"LaunchImage.png"];
}

static NSString *TGBundleImagePath(NSString *name) {
	return [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:name];
}

static NSArray *TGLaunchImageTargets(void) {
	NSFileManager *files = [NSFileManager defaultManager];
	NSMutableArray *targets = [NSMutableArray array];
	for (NSString *name in TGLaunchImageNames())
		if ([files fileExistsAtPath:TGBundleImagePath(name)])
			[targets addObject:name];
	return targets;
}

static NSString *TGShippedImagePath(NSString *name) {
	NSString *support = [NSSearchPathForDirectoriesInDomains(
			NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *directory = [support stringByAppendingPathComponent:@"launchimage"];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory
							 withIntermediateDirectories:YES
											  attributes:nil
												   error:NULL];
	return [directory stringByAppendingPathComponent:name];
}

@implementation TGLaunchSnapshot

+ (BOOL)enabled {
	NSNumber *value = [[NSUserDefaults standardUserDefaults]
			objectForKey:TGLaunchSnapshotEnabledKey];
	return value ? value.boolValue : YES;
}

+ (void)setEnabled:(BOOL)enabled {
	[[NSUserDefaults standardUserDefaults] setBool:enabled
											forKey:TGLaunchSnapshotEnabledKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	if (!enabled)
		[self restoreShippedImage:@"switched off"];
}

+ (BOOL)installed {
	return [[NSUserDefaults standardUserDefaults] boolForKey:TGLaunchSnapshotInstalledKey];
}

+ (void)setInstalled:(BOOL)installed {
	[[NSUserDefaults standardUserDefaults] setBool:installed
											forKey:TGLaunchSnapshotInstalledKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)preserveShippedImages {
	if ([self installed])
		return;
	NSFileManager *files = [NSFileManager defaultManager];
	for (NSString *name in TGLaunchImageTargets()){
		NSString *shipped = TGShippedImagePath(name);
		if ([files fileExistsAtPath:shipped])
			continue;
		[files copyItemAtPath:TGBundleImagePath(name) toPath:shipped error:NULL];
	}
}

+ (UITableView *)chatListTableInWindow:(UIWindow *)window reason:(NSString **)reason {
	UIViewController *root = window.rootViewController;
	if (!root){
		*reason = @"no root view controller";
		return nil;
	}
	if (root.presentedViewController){
		*reason = @"something is presented over the app";
		return nil;
	}
	if (![root isKindOfClass:[UITabBarController class]]){
		*reason = @"not on the tabbed UI (login or loading)";
		return nil;
	}

	UITabBarController *tabs = (UITabBarController *)root;
	if (tabs.selectedIndex != 1){
		*reason = [NSString stringWithFormat:@"tab %lu is selected, not Messages",
				(unsigned long)tabs.selectedIndex];
		return nil;
	}

	if (tabs.selectedIndex >= tabs.viewControllers.count){
		*reason = @"selected tab has no controller";
		return nil;
	}
	id selected = tabs.viewControllers[tabs.selectedIndex];
	if (![selected isKindOfClass:[UINavigationController class]]){
		*reason = @"chat list tab is not a navigation controller";
		return nil;
	}

	UINavigationController *nav = (UINavigationController *)selected;
	if (nav.viewControllers.count != 1){
		*reason = @"a chat is pushed over the list";
		return nil;
	}
	UIViewController *top = nav.topViewController;
	if (top.presentedViewController){
		*reason = @"something is presented over the list";
		return nil;
	}
	if (![top isKindOfClass:NSClassFromString(@"TGChatListViewController")]){
		*reason = @"top of the list tab is not the chat list";
		return nil;
	}
	if (![top isKindOfClass:[UITableViewController class]]){
		*reason = @"chat list is not a table controller";
		return nil;
	}

	UITableView *table = [(UITableViewController *)top tableView];
	if (table.isEditing){
		*reason = @"the list is in editing mode";
		return nil;
	}
	if ([top respondsToSelector:@selector(searchBar)]){
		UISearchBar *search = [top valueForKey:@"searchBar"];
		if ([search isKindOfClass:[UISearchBar class]] && search.isFirstResponder){
			*reason = @"a search is on screen";
			return nil;
		}
	}
	return table;
}

+ (void)noteColdLaunchOffsetFromWindow:(UIWindow *)window {
	NSString *reason = nil;
	UITableView *table = [self chatListTableInWindow:window reason:&reason];
	if (!table)
		return;
	[[NSUserDefaults standardUserDefaults]
			setDouble:table.contentOffset.y + table.contentInset.top
			   forKey:TGLaunchSnapshotOffsetKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)hasColdLaunchOffset {
	return [[NSUserDefaults standardUserDefaults]
			objectForKey:TGLaunchSnapshotOffsetKey] != nil;
}

+ (CGFloat)coldLaunchOffset {
	return (CGFloat)[[NSUserDefaults standardUserDefaults]
			doubleForKey:TGLaunchSnapshotOffsetKey];
}

+ (void)captureFromWindow:(UIWindow *)window {
	if (![self enabled]){
		TGLaunchNote(@"skipped: switched off");
		return;
	}
	if (![[NSUserDefaults standardUserDefaults] boolForKey:@"tgWasSignedIn"]){
		[self restoreShippedImage:@"signed out"];
		return;
	}
	if (!window){
		TGLaunchNote(@"skipped: no window");
		return;
	}
	if (UIInterfaceOrientationIsLandscape(
			[UIApplication sharedApplication].statusBarOrientation)){
		TGLaunchNote(@"kept the previous image: the screen is in landscape");
		return;
	}

	NSString *reason = @"unknown";
	UITableView *table = [self chatListTableInWindow:window reason:&reason];
	if (!table){
		TGLaunchNote(@"kept the previous image: %@", reason);
		return;
	}

	CGPoint saved = table.contentOffset;
	BOOL moved = NO;
	if ([self hasColdLaunchOffset]){
		CGFloat target = [self coldLaunchOffset] - table.contentInset.top;
		if (fabs(saved.y - target) > 0.5f){
			table.contentOffset = CGPointMake(0, target);
			moved = YES;
		}
	} else if (saved.y + table.contentInset.top > 44.0f){
		TGLaunchNote(@"kept the previous image: list is scrolled and no launch offset is known");
		return;
	}

	NSTimeInterval began = [NSDate timeIntervalSinceReferenceDate];
	[window layoutIfNeeded];
	UIImage *shot = [self renderWindow:window];
	if (moved)
		table.contentOffset = saved;
	if (!shot){
		TGLaunchNote(@"render produced nothing");
		return;
	}
	NSTimeInterval rendered = [NSDate timeIntervalSinceReferenceDate];

	NSData *png = UIImagePNGRepresentation(shot);
	if (!png.length){
		TGLaunchNote(@"PNG encode failed");
		return;
	}
	NSTimeInterval encoded = [NSDate timeIntervalSinceReferenceDate];

	[self preserveShippedImages];

	NSUInteger written = 0;
	for (NSString *name in TGLaunchImageTargets())
		if ([self writeData:png toPath:TGBundleImagePath(name)])
			written++;

	if (!written){
		TGLaunchNote(@"could not write the launch image (bundle not writable)");
		return;
	}
	[self setInstalled:YES];
	TGLaunchNote(@"wrote %lu file(s), %lu KB, render %.0f ms encode %.0f ms write %.0f ms",
			(unsigned long)written, (unsigned long)(png.length / 1024),
			(rendered - began) * 1000.0,
			(encoded - rendered) * 1000.0,
			([NSDate timeIntervalSinceReferenceDate] - encoded) * 1000.0);
}

+ (UIImage *)renderWindow:(UIWindow *)window {
	CGSize size = window.bounds.size;
	if (size.width < 1 || size.height < 1)
		return nil;
	UIScreen *screen = [UIScreen mainScreen];
	CGFloat scale = [screen respondsToSelector:@selector(scale)] ? screen.scale : 1.0f;

	UIGraphicsBeginImageContextWithOptions(size, YES, scale);
	CGContextRef context = UIGraphicsGetCurrentContext();
	if (!context){
		UIGraphicsEndImageContext();
		return nil;
	}
	CGContextSetGrayFillColor(context, 0.0f, 1.0f);
	CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
	[window.layer renderInContext:context];
	UIImage *shot = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return shot;
}

+ (BOOL)writeData:(NSData *)data toPath:(NSString *)path {
	if (![data writeToFile:path atomically:YES])
		return NO;
	chmod(path.fileSystemRepresentation, S_IRUSR | S_IWUSR);
	return YES;
}

+ (NSData *)blankImageData {
	UIScreen *screen = [UIScreen mainScreen];
	CGSize size = screen.bounds.size;
	CGFloat scale = [screen respondsToSelector:@selector(scale)] ? screen.scale : 1.0f;
	UIGraphicsBeginImageContextWithOptions(size, YES, scale);
	CGContextRef context = UIGraphicsGetCurrentContext();
	if (!context){
		UIGraphicsEndImageContext();
		return nil;
	}
	CGContextSetRGBFillColor(context, 0.84f, 0.85f, 0.87f, 1.0f);
	CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
	CGContextSetGrayFillColor(context, 0.0f, 1.0f);
	CGContextFillRect(context, CGRectMake(0, 0, size.width, 20.0f));
	UIImage *plain = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return UIImagePNGRepresentation(plain);
}

+ (void)restoreShippedImage:(NSString *)reason {
	if (![self installed])
		return;
	NSFileManager *files = [NSFileManager defaultManager];
	NSUInteger restored = 0;
	NSData *blank = nil;
	for (NSString *name in TGLaunchImageTargets()){
		NSString *shipped = TGShippedImagePath(name);
		NSData *data = [files fileExistsAtPath:shipped]
				? [NSData dataWithContentsOfFile:shipped] : nil;
		if (!data.length){
			if (!blank)
				blank = [self blankImageData];
			data = blank;
		}
		if (!data.length)
			continue;
		NSString *bundled = TGBundleImagePath(name);
		if (![data writeToFile:bundled atomically:YES])
			continue;
		chmod(bundled.fileSystemRepresentation, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
		restored++;
	}
	[self setInstalled:NO];
	TGLaunchNote(@"restored the shipped artwork (%lu file(s)): %@",
			(unsigned long)restored, reason);
}

+ (NSString *)describe {
	NSMutableString *out = [NSMutableString string];
	[out appendFormat:@"enabled=%@ installed=%@ offset=%@ last=\"%@\"",
			[self enabled] ? @"yes" : @"no",
			[self installed] ? @"yes" : @"no",
			[self hasColdLaunchOffset]
					? [NSString stringWithFormat:@"%.1f", [self coldLaunchOffset]] : @"unknown",
			TGLaunchLastNote];
	for (NSString *name in TGLaunchImageNames()){
		NSDictionary *attributes = [[NSFileManager defaultManager]
				attributesOfItemAtPath:TGBundleImagePath(name) error:NULL];
		[out appendFormat:@" %@=%@", name,
				attributes ? [NSString stringWithFormat:@"%lluB mode%o",
						[attributes fileSize],
						(unsigned)[attributes filePosixPermissions]] : @"missing"];
	}
	return out;
}

@end

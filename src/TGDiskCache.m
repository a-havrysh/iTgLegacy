#import "TGDiskCache.h"

static const unsigned long long TGDiskCacheImageCap = 24ULL * 1024 * 1024;
static const unsigned long long TGDiskCacheImageFloor = 18ULL * 1024 * 1024;
static const NSTimeInterval TGDiskCacheTouchInterval = 3600.0;
static const NSTimeInterval TGDiskCacheSweepInterval = 120.0;

static NSString *TGDiskCacheProtection(void) {
	return NSFileProtectionCompleteUntilFirstUserAuthentication;
}

static dispatch_queue_t TGDiskCacheQueue(void) {
	static dispatch_queue_t queue = NULL;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("TGDiskCache", NULL);
	});
	return queue;
}

static NSString *TGDiskCacheLibrarySubdirectory(NSSearchPathDirectory which, NSString *name) {
	NSString *root = [NSSearchPathForDirectoriesInDomains(which, NSUserDomainMask, YES)
			objectAtIndex:0];
	NSString *path = [root stringByAppendingPathComponent:name];
	[[NSFileManager defaultManager] createDirectoryAtPath:path
							  withIntermediateDirectories:YES
											   attributes:@{NSFileProtectionKey : TGDiskCacheProtection()}
													error:NULL];
	return path;
}

static NSString *TGDiskCacheImageDirectory(void) {
	static NSString *dir = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		dir = TGDiskCacheLibrarySubdirectory(NSCachesDirectory, @"TGImageCache");
	});
	return dir;
}

static NSString *TGDiskCacheStateDirectory(void) {
	static NSString *dir = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		dir = TGDiskCacheLibrarySubdirectory(NSCachesDirectory, @"TGState");
	});
	return dir;
}

static NSString *TGDiskCacheSafeName(NSString *key) {
	NSMutableString *out = [NSMutableString stringWithCapacity:key.length];
	for (NSUInteger i = 0; i < key.length; i++){
		unichar c = [key characterAtIndex:i];
		BOOL plain = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
					 (c >= '0' && c <= '9') || c == '_' || c == '-';
		if (plain)
			[out appendFormat:@"%C", c];
		else
			[out appendFormat:@"%%%04X", (unsigned int)c];
	}
	return out;
}

static NSString *TGDiskCacheImagePath(NSString *key) {
	return [TGDiskCacheImageDirectory() stringByAppendingPathComponent:
			[TGDiskCacheSafeName(key) stringByAppendingPathExtension:@"png"]];
}

@interface TGDiskCache ()
+ (void)sweepIfDue;
+ (void)sweepNow;
+ (void)discardStrayTemporariesIn:(NSString *)directory;
+ (void)discardLegacyCaches;
@end

@implementation TGDiskCache

+ (NSString *)databaseDirectory {
	static NSString *dir = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *support = TGDiskCacheLibrarySubdirectory(NSApplicationSupportDirectory, @"tdlib");
		NSString *legacy = [[NSSearchPathForDirectoriesInDomains(
				NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0]
						stringByAppendingPathComponent:@"tdlib"];

		BOOL legacyIsDirectory = NO;
		BOOL hasLegacy = [fm fileExistsAtPath:legacy isDirectory:&legacyIsDirectory] && legacyIsDirectory;
		BOOL supportIsEmpty = [fm contentsOfDirectoryAtPath:support error:NULL].count == 0;
		if (hasLegacy && supportIsEmpty){
			[fm removeItemAtPath:support error:NULL];
			NSError *moveError = nil;
			if ([fm moveItemAtPath:legacy toPath:support error:&moveError])
				NSLog(@"TGDiskCache: moved the database out of Documents");
			else
				NSLog(@"TGDiskCache: database move failed: %@", moveError);
			[fm createDirectoryAtPath:support
		  withIntermediateDirectories:YES
						   attributes:@{NSFileProtectionKey : TGDiskCacheProtection()}
								error:NULL];
		}

		[self protectPath:support];
		NSURL *url = [NSURL fileURLWithPath:support];
		[url setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
		dir = support;
	});
	return dir;
}

+ (NSString *)snapshotPathForName:(NSString *)name {
	return [TGDiskCacheStateDirectory() stringByAppendingPathComponent:
			[TGDiskCacheSafeName(name) stringByAppendingPathExtension:@"plist"]];
}

+ (void)protectPath:(NSString *)path {
	if (!path.length)
		return;
	[[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey : TGDiskCacheProtection()}
									 ofItemAtPath:path
											error:NULL];
}

+ (void)protectTreeAtPath:(NSString *)path {
	if (!path.length)
		return;
	NSString *done = [@"TGDiskCacheProtected-" stringByAppendingString:
			TGDiskCacheSafeName(path)];
	if ([NSUserDefaults.standardUserDefaults boolForKey:done])
		return;
	dispatch_time_t after = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC));
	dispatch_after(after, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		@autoreleasepool {
			NSFileManager *fm = [NSFileManager defaultManager];
			[self protectPath:path];
			NSDirectoryEnumerator *walk = [fm enumeratorAtPath:path];
			NSString *relative = nil;
			NSUInteger touched = 0;
			while ((relative = [walk nextObject]) != nil){
				@autoreleasepool {
					[self protectPath:[path stringByAppendingPathComponent:relative]];
					touched++;
				}
			}
			NSLog(@"TGDiskCache: protection applied to %lu items", (unsigned long)touched);
			[NSUserDefaults.standardUserDefaults setBool:YES forKey:done];
		}
	});
}

+ (BOOL)writeData:(NSData *)data toProtectedPath:(NSString *)path {
	if (!data || !path.length)
		return NO;
	BOOL ok = [data writeToFile:path atomically:YES];
	if (ok)
		[self protectPath:path];
	return ok;
}

+ (UIImage *)imageForKey:(NSString *)key scale:(CGFloat)scale {
	if (!key.length)
		return nil;
	NSString *path = TGDiskCacheImagePath(key);
	NSData *data = [NSData dataWithContentsOfFile:path
										  options:NSDataReadingMappedIfSafe
											error:NULL];
	if (!data.length)
		return nil;

	UIImage *image = [UIImage imageWithData:data scale:(scale > 0 ? scale : 1.0f)];
	if (!image){
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
		return nil;
	}

	dispatch_async(TGDiskCacheQueue(), ^{
		NSFileManager *fm = [NSFileManager defaultManager];
		NSDate *modified = [[fm attributesOfItemAtPath:path error:NULL] fileModificationDate];
		if (modified && [[NSDate date] timeIntervalSinceDate:modified] < TGDiskCacheTouchInterval)
			return;
		[fm setAttributes:@{NSFileModificationDate : [NSDate date]} ofItemAtPath:path error:NULL];
	});
	return image;
}

+ (void)storeImage:(UIImage *)image forKey:(NSString *)key {
	if (!image || !key.length)
		return;
	NSString *path = TGDiskCacheImagePath(key);
	dispatch_async(TGDiskCacheQueue(), ^{
		@autoreleasepool {
			NSData *data = UIImagePNGRepresentation(image);
			if (!data.length)
				return;
			[self writeData:data toProtectedPath:path];
		}
		[self sweepIfDue];
	});
}

+ (void)removeImageForKey:(NSString *)key {
	if (!key.length)
		return;
	NSString *path = TGDiskCacheImagePath(key);
	dispatch_async(TGDiskCacheQueue(), ^{
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	});
}

+ (void)sweepIfDue {
	static NSTimeInterval last = 0;
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - last < TGDiskCacheSweepInterval)
		return;
	last = now;
	[self sweepNow];
}

+ (void)sweep {
	dispatch_async(TGDiskCacheQueue(), ^{
		[self discardLegacyCaches];
		[self discardStrayTemporariesIn:TGDiskCacheStateDirectory()];
		[self discardStrayTemporariesIn:TGDiskCacheImageDirectory()];
		[self sweepNow];
	});
}

+ (void)discardLegacyCaches {
	NSString *caches = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *legacy = [caches stringByAppendingPathComponent:@"RemoteImageCache"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:legacy])
		return;
	if ([[NSFileManager defaultManager] removeItemAtPath:legacy error:NULL])
		NSLog(@"TGDiskCache: removed the unprotected RemoteImageCache folder");
}

+ (void)discardStrayTemporariesIn:(NSString *)directory {
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *name in [fm contentsOfDirectoryAtPath:directory error:NULL]){
		if (![name hasPrefix:@"."])
			continue;
		[fm removeItemAtPath:[directory stringByAppendingPathComponent:name] error:NULL];
	}
}

+ (void)sweepNow {
	@autoreleasepool {
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *dir = TGDiskCacheImageDirectory();
		NSArray *names = [fm contentsOfDirectoryAtPath:dir error:NULL];
		if (!names.count)
			return;

		NSMutableArray *entries = [NSMutableArray arrayWithCapacity:names.count];
		unsigned long long total = 0;
		for (NSString *name in names){
			NSString *path = [dir stringByAppendingPathComponent:name];
			NSDictionary *attributes = [fm attributesOfItemAtPath:path error:NULL];
			if (!attributes)
				continue;
			unsigned long long size = [attributes fileSize];
			total += size;
			[entries addObject:@{@"path" : path,
								 @"size" : @(size),
								 @"date" : [attributes fileModificationDate] ?: [NSDate distantPast]}];
		}
		if (total <= TGDiskCacheImageCap)
			return;

		[entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
			return [a[@"date"] compare:b[@"date"]];
		}];

		NSUInteger removed = 0;
		for (NSDictionary *entry in entries){
			if (total <= TGDiskCacheImageFloor)
				break;
			if (![fm removeItemAtPath:entry[@"path"] error:NULL])
				continue;
			total -= [entry[@"size"] unsignedLongLongValue];
			removed++;
		}
		NSLog(@"TGDiskCache: evicted %lu images, %llu KB left",
				(unsigned long)removed, total / 1024);
	}
}

+ (unsigned long long)imageBytesOnDisk {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *dir = TGDiskCacheImageDirectory();
	unsigned long long total = 0;
	for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL])
		total += [[fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:name]
									   error:NULL] fileSize];
	return total;
}

@end


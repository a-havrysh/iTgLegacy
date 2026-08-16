#import <UIKit/UIKit.h>

@interface TGDiskCache : NSObject

+ (NSString *)databaseDirectory;
+ (NSString *)snapshotPathForName:(NSString *)name;

+ (UIImage *)imageForKey:(NSString *)key scale:(CGFloat)scale;
+ (void)storeImage:(UIImage *)image forKey:(NSString *)key;
+ (void)removeImageForKey:(NSString *)key;
+ (void)clearImages;

+ (void)protectPath:(NSString *)path;
+ (void)protectTreeAtPath:(NSString *)path;
+ (BOOL)writeData:(NSData *)data toProtectedPath:(NSString *)path;

+ (void)sweep;
+ (unsigned long long)imageBytesOnDisk;

@end


#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface TGBackgroundSession : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL launchedIntoBackground;
@property (nonatomic, readonly) BOOL voipSocketMarked;
@property (nonatomic, readonly) int primarySocketDescriptor;

- (void)attachToTDLibHandle:(void *)handle;

- (void)noteDataReceived;
- (void)noteConnectionReady;

- (void)applicationDidFinishLaunching:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;
- (void)applicationWillEnterForeground:(UIApplication *)application;

- (NSString *)statusLine;
- (void)runDiagnosticProbe;

@end

// vim:ft=objc

/**
 * AppDelegate - TDLib only. libtg is gone, along with its C structs, its
 * queue/socket transport and everything that depended on them.
 */
#import <UIKit/UIKit.h>
#import "TGLoginViewController.h"

void TGMarkLaunchStage(NSString *stage);
void TGWaitForTextWarm(void);
void TGMarkOpenStage(NSString *stage);
void TGBeginOpenTiming(void);
void TGBeginOpenTimingFromTap(void);
void TGMarkFirstFrame(NSString *stage);
void TGRedirectLogToFile(void);
void TGNoteImageReady(NSTimeInterval when);
void TGMarkOpenFrame(NSString *stage);
void TGMarkOpenSettledFrame(NSString *stage);

unsigned long long TGResidentBytes(void);
void TGMemMark(NSString *tag);
BOOL TGPerfLogging(void);

@interface AppDelegate : UIResponder <UIApplicationDelegate, UIAlertViewDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) UIViewController *rootViewController;
@property (strong, nonatomic) TGLoginViewController *loginVC;

@property (strong) NSOperationQueue *syncData;

/// Caches used by the image loaders.
@property (strong) NSString *smallPhotoCache;
@property (strong) NSString *peerPhotoCache;
@property (strong) NSString *imagesCache;
@property (strong) NSString *filesCache;
@property (strong) NSString *thumbDocCache;

@property (copy) NSString *currentPhoneNumber;
@property (strong) NSString *token;
@property Boolean showNotifications;
@property FILE *log;

-(void)showMessage:(NSString *)msg;
-(void)showMainUI;
-(void)showLoginUI;

@end

// vim:ft=objc

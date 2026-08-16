// TGQRViewController - reads a QR code with the camera.
#import <UIKit/UIKit.h>

@interface TGQRViewController : UIViewController
@property (nonatomic, copy) BOOL (^onCode)(NSString *payload);
@end

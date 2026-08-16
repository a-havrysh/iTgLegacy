//
// TGQRCodeViewController - shows a link as a QR code for another phone to read.
//
// The other half of TGQRViewController: one screen photographs a code, this one
// puts one on the glass. Used for a profile's t.me link, and by anything else
// that has a short link and wants it handed over without typing.
//
#import <UIKit/UIKit.h>

@interface TGQRCodeViewController : UIViewController
- (id)initWithLink:(NSString *)link caption:(NSString *)caption;
@end

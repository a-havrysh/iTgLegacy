//
// TGQRImage - draws a link as a QR code.
//
// The image comes back at whole-pixel module size and native screen scale, so
// it is drawn crisply rather than resampled: a QR code that another phone has
// to photograph off this screen cannot afford soft edges. Its own size is the
// largest that fits the limit, which is usually a little under it - place it by
// its -size, do not stretch it into a frame.
//
#import <UIKit/UIKit.h>

UIImage *TGQRCodeImage(NSString *text, CGFloat maximumSide);

@interface TGQRCodeView : UIView
@property (nonatomic, copy) NSString *text;
@end

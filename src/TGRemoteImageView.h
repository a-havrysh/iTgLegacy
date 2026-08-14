#import <UIKit/UIKit.h>
#import "TGReusableView.h"

@interface TGRemoteImageView : UIImageView <TGReusableView>

@property (nonatomic, strong) NSString *reuseIdentifier;
@property (nonatomic, strong) NSNumber *fileId;
@property (nonatomic) bool fadeTransition;
@property (nonatomic) NSTimeInterval fadeTransitionDuration;
@property (nonatomic, strong) NSString *currentUrl;

- (UIImage *)currentImage;
- (void)tryFillCache:(NSMutableDictionary *)dict;

- (void)loadImage:(NSString *)url filter:(NSString *)filter placeholder:(UIImage *)placeholder;
- (void)loadImage:(NSString *)url filter:(NSString *)filter placeholder:(UIImage *)placeholder forceFade:(bool)forceFade;
- (void)loadWithFileId:(NSNumber *)fileId square:(CGFloat)side placeholder:(UIImage *)placeholder forceFade:(bool)forceFade;
- (void)cancelLoading;

@end

#import <UIKit/UIKit.h>

#import "TGReusableView.h"

@interface TGViewRecycler : NSObject

- (UIView<TGReusableView> *)dequeueReusableViewWithIdentifier:(NSString *)reuseIdentifier;
- (void)recycleView:(UIView<TGReusableView> *)view;
- (int)recycledCount:(NSString *)identifier;
- (void)removeAllViews;

@end

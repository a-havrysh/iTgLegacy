//
// UIView+SafeTint - tintColor exists on every UIView only from iOS 7.0.
// Below that (UIImageView, UITableViewCell.imageView, etc.) the setter is
// simply absent and calling it throws unrecognized-selector. Bars
// (UINavigationBar/UITabBar/UISearchBar) had their own tintColor earlier and
// are unaffected, but this guard is harmless for them too.
//
#import <UIKit/UIKit.h>

@interface UIView (SafeTint)
- (void)tg_setTintColor:(UIColor *)color;
@end

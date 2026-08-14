#import <UIKit/UIKit.h>

@protocol TGTabBarDelegate <NSObject>
- (void)tabBarSelectedItem:(int)index;
@end

@interface TGTabBar : UIView

@property (nonatomic, weak) id<TGTabBarDelegate> tabDelegate;
@property (nonatomic) int selectedIndex;

- (void)setUnreadCount:(int)unreadCount;

@end

/**
 * File              : RootViewController.h
 * Author            : Igor V. Sementsov <ig.kuzm@gmail.com>
 * Date              : 22.08.2023
 * Last Modified Date: 22.08.2023
 * Last Modified By  : Igor V. Sementsov <ig.kuzm@gmail.com>
 */

#include <UIKit/UIKit.h>
#include "UIKit/UIKit.h"
@interface RootViewController : UITabBarController

- (void)updateUnreadBadge;

- (CGFloat)tabBarInsetForController:(UIViewController *)controller;

+ (BOOL)isPadIdiom;

+ (RootViewController *)splitRootController;

+ (BOOL)isSplitLayoutActive;
- (BOOL)isSplitLayoutActive;

+ (UINavigationController *)detailNavigationController;
- (UINavigationController *)detailNavigationController;

+ (BOOL)presentInDetail:(UIViewController *)controller;
- (BOOL)presentInDetail:(UIViewController *)controller;

+ (BOOL)pushInDetail:(UIViewController *)controller;
- (BOOL)pushInDetail:(UIViewController *)controller;

+ (void)showDetailEmptyState;
- (void)showDetailEmptyState;

@end


// vim:ft=objc

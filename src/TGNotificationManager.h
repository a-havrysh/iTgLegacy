#import <UIKit/UIKit.h>

@interface TGNotificationManager : NSObject

+ (instancetype)shared;

- (void)start;

- (void)clearNotificationsForChat:(int64_t)chatId;

- (void)applicationDidBecomeActive;
- (void)applicationDidEnterBackground;

- (int64_t)chatIdForLocalNotification:(UILocalNotification *)notification;

@end

// vim:ft=objc

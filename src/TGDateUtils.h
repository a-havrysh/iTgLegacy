#import <Foundation/Foundation.h>

@interface TGDateUtils : NSObject

+ (NSString *)stringForShortTime:(int)time;
+ (NSString *)stringForDialogTime:(int)time;
+ (NSString *)stringForDayOfMonth:(int)date dayOfMonth:(int *)dayOfMonth;
+ (NSString *)stringForDayOfWeek:(int)date;
+ (NSString *)stringForMessageListDate:(int)date;
+ (NSString *)stringForLastSeen:(int)date;
+ (NSString *)stringForLastSeenShort:(int)date;
+ (NSString *)stringForRelativeLastSeen:(int)date;
+ (NSString *)stringForUntil:(int)date;

@end

#ifdef __cplusplus
extern "C" {
#endif

bool TGUse12hDateFormat(void);

#ifdef __cplusplus
}
#endif

#import <UIKit/UIKit.h>

@interface TGAssetPicker : UIViewController

@property (nonatomic, assign) NSUInteger selectionLimit;
@property (nonatomic, copy) void (^onPicked)(NSArray *paths);
@property (nonatomic, copy) void (^onCancelled)(void);

+ (BOOL)available;

@end

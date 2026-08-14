#import <UIKit/UIKit.h>

@protocol TGAdvancedHighlightable <NSObject>

- (void)advancedSetHighlighted:(bool)highlighted;

@end

@protocol TGHighlightable <NSObject>

@required

- (void)setHighlighted:(BOOL)highlighted;
- (void)setOpaque:(BOOL)opaque;

@end

@interface TGHighlightTriggerLabel : UILabel

@property (nonatomic, strong) NSArray *targetViews;
@property (nonatomic) bool advanced;

@end

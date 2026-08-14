#import "TGHighlightTriggerLabel.h"

@implementation TGHighlightTriggerLabel

- (void)setHighlighted:(BOOL)highlighted {
	if (self.targetViews != nil){
		for (id<TGHighlightable> target in self.targetViews){
			if (self.advanced)
				[(id<TGAdvancedHighlightable>)target advancedSetHighlighted:highlighted];
			else
				[target setHighlighted:highlighted];
		}
	}
}

@end

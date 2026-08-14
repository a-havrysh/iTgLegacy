#import "TGHighlightImageView.h"

@implementation TGHighlightImageView

- (void)setHidden:(BOOL)hidden {
	if (self.targetView != nil)
		[self.targetView setHidden:hidden];
	[super setHidden:hidden];
}

- (void)setAlpha:(CGFloat)alpha {
	if (self.targetView != nil)
		[self.targetView setAlpha:alpha];
	[super setAlpha:alpha];
}

@end

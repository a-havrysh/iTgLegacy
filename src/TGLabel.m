#import "TGLabel.h"

@implementation TGLabel

- (void)prepareForReuse {
	self.text = nil;
	self.highlighted = NO;
	self.customDrawingOffset = CGPointZero;
	self.customDrawingSize = CGSizeZero;
}

- (void)prepareForRecycle:(TGViewRecycler *)__unused recycler {
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	if (self.highlightedShadowColor != nil && self.normalShadowColor != nil)
		self.shadowColor = highlighted ? self.highlightedShadowColor : self.normalShadowColor;
}

- (void)setLandscape:(bool)landscape {
	if (self.landscapeFont != nil && self.portraitFont != nil)
		self.font = landscape ? self.landscapeFont : self.portraitFont;
}

- (void)setOpaque:(BOOL)opaque {
	[super setOpaque:opaque];
	if (opaque && self.persistentBackgroundColor != nil)
		[super setBackgroundColor:self.persistentBackgroundColor];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
	if (self.opaque && self.persistentBackgroundColor != nil)
		[super setBackgroundColor:self.persistentBackgroundColor];
	else
		[super setBackgroundColor:backgroundColor];
}

- (void)setPersistentBackgroundColor:(UIColor *)persistentBackgroundColor {
	_persistentBackgroundColor = persistentBackgroundColor;
	if (self.opaque && persistentBackgroundColor != nil)
		self.backgroundColor = persistentBackgroundColor;
}

- (void)setCustomDrawingOffset:(CGPoint)customDrawingOffset {
	if (!CGPointEqualToPoint(customDrawingOffset, _customDrawingOffset)){
		_customDrawingOffset = customDrawingOffset;
		[self setNeedsDisplay];
	}
}

- (void)setCustomDrawingSize:(CGSize)customDrawingSize {
	if (!CGSizeEqualToSize(customDrawingSize, _customDrawingSize)){
		_customDrawingSize = customDrawingSize;
		[self setNeedsDisplay];
	}
}

- (CGRect)textRectForBounds:(CGRect)bounds limitedToNumberOfLines:(NSInteger)numberOfLines {
	if (_customDrawingSize.height != 0){
		bounds.size.height = _customDrawingSize.height;
		if (_customDrawingSize.width > 0)
			bounds.size.width = _customDrawingSize.width;
	}
	if (self.verticalAlignment == TGLabelVericalAlignmentCenter){
		CGRect textRect = [super textRectForBounds:bounds limitedToNumberOfLines:numberOfLines];
		textRect.origin.y = bounds.origin.y + (int)((bounds.size.height - textRect.size.height) / 2);
		return CGRectOffset(textRect, 0, (int)(self.verticalOffset + self.verticalOffsetMultiplier * textRect.size.height));
	} else if (self.verticalAlignment == TGLabelVericalAlignmentTop){
		CGRect textRect = [super textRectForBounds:bounds limitedToNumberOfLines:numberOfLines];
		textRect.origin.y = bounds.origin.y;
		return CGRectOffset(textRect, 0, (int)(self.verticalOffset + self.verticalOffsetMultiplier * textRect.size.height));
	}
	return CGRectOffset([super textRectForBounds:bounds limitedToNumberOfLines:numberOfLines], 0, self.verticalOffset);
}

- (void)drawTextInRect:(CGRect)requestedRect {
	if (self.text.length == 0)
		return;
	if (_customDrawingSize.height != 0){
		CGFloat maxWidth = _customDrawingSize.width > 0 ? _customDrawingSize.width : requestedRect.size.width;
		if (requestedRect.size.width > maxWidth)
			requestedRect.size.width = maxWidth;
		CGRect actualRect = [self textRectForBounds:requestedRect limitedToNumberOfLines:self.numberOfLines];
		if (self.verticalAlignment != TGLabelVericalAlignmentCenter)
			actualRect.origin.y = requestedRect.origin.y;
		[super drawTextInRect:CGRectMake(requestedRect.origin.x + _customDrawingOffset.x,
										  actualRect.origin.y + _customDrawingOffset.y,
										  MIN(actualRect.size.width, maxWidth),
										  MIN(actualRect.size.height, _customDrawingSize.height))];
	} else {
		CGRect actualRect = [self textRectForBounds:requestedRect limitedToNumberOfLines:self.numberOfLines];
		[super drawTextInRect:actualRect];
	}
}

- (void)drawRect:(CGRect)__unused rect {
	[self drawTextInRect:self.bounds];
}

@end

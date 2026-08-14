#import "TGDateLabel.h"
#import "TGDateUtils.h"

typedef enum {
	TGDateLabelFormatModeNone = 0,
	TGDateLabelFormatModeAm = 1,
	TGDateLabelFormatModePm = 2
} TGDateLabelFormatMode;

@interface TGDateLabel () {
	CGSize _measuredTextSize;
	bool _measuredTextSizeIsValid;
}

@property (nonatomic) TGDateLabelFormatMode formatMode;

@end

@implementation TGDateLabel

- (void)setText:(NSString *)text {
	_measuredTextSizeIsValid = false;
	_dateText = nil;
	_rawDateText = nil;
	[self setDateText:text];
}

- (void)setDateText:(NSString *)dateText {
	if (dateText != _dateText && ![dateText isEqualToString:_rawDateText]){
		_measuredTextSizeIsValid = false;
		_rawDateText = dateText;

		if (dateText.length == 0){
			_dateText = @"";
			self.formatMode = TGDateLabelFormatModeNone;
			[self setNeedsDisplay];
			return;
		}

		if (TGUse12hDateFormat()){
			NSString *suffix = dateText.length >= 3 ? [[dateText substringFromIndex:dateText.length - 3] uppercaseString] : nil;
			bool isAm = [suffix isEqualToString:@" AM"];
			if (isAm || [suffix isEqualToString:@" PM"]){
				_dateText = [dateText substringToIndex:dateText.length - 3];
				self.formatMode = isAm ? TGDateLabelFormatModeAm : TGDateLabelFormatModePm;
			} else {
				_dateText = dateText;
				self.formatMode = TGDateLabelFormatModeNone;
			}
		} else {
			_dateText = dateText;
			self.formatMode = TGDateLabelFormatModeNone;
		}

		[self setNeedsDisplay];
	}
}

- (UIFont *)effectiveTextFont {
	UIFont *font = self.formatMode != TGDateLabelFormatModeNone ? self.dateTextFont : self.dateFont;
	if (font == nil)
		font = self.font;
	if (font == nil)
		font = [UIFont systemFontOfSize:13.0f];
	return font;
}

- (UIFont *)effectiveSuffixFont {
	UIFont *font = self.dateLabelFont;
	if (font == nil)
		font = [self effectiveTextFont];
	return font;
}

- (CGSize)measureTextSize {
	if (_measuredTextSizeIsValid)
		return _measuredTextSize;

	if (_dateText.length == 0){
		_measuredTextSize = CGSizeZero;
		_measuredTextSizeIsValid = true;
		return _measuredTextSize;
	}

	CGSize textSize = [_dateText sizeWithFont:[self effectiveTextFont]];
	if (self.formatMode == TGDateLabelFormatModeAm){
		float width = self.amWidth;
		if (width < 0.001f)
			width = [@"AM" sizeWithFont:[self effectiveSuffixFont]].width;
		textSize.width += width;
	} else if (self.formatMode == TGDateLabelFormatModePm){
		float width = self.pmWidth;
		if (width < 0.001f)
			width = [@"PM" sizeWithFont:[self effectiveSuffixFont]].width;
		textSize.width += width;
	}

	_measuredTextSize = textSize;
	_measuredTextSizeIsValid = true;
	return textSize;
}

- (void)drawTextInRect:(CGRect)__unused rect {
	CGContextRef context = UIGraphicsGetCurrentContext();
	if (context == NULL || _dateText.length == 0)
		return;

	[self measureTextSize];

	if (self.textAlignment == NSTextAlignmentCenter)
		CGContextTranslateCTM(context, floorf((self.frame.size.width - _measuredTextSize.width) / 2), 0);

	if (self.shadowColor != nil)
		CGContextSetShadowWithColor(context, self.shadowOffset, 0.0f, self.shadowColor.CGColor);

	if (self.isDisabled){
		UIColor *disabledColor = self.disabledColor ?: [UIColor colorWithRed:0xae / 255.0f green:0xae / 255.0f blue:0xae / 255.0f alpha:1.0f];
		CGContextSetFillColorWithColor(context, disabledColor.CGColor);
	} else {
		UIColor *color = self.highlighted ? self.highlightedTextColor : self.textColor;
		if (color == nil)
			color = self.textColor ?: [UIColor blackColor];
		CGContextSetFillColorWithColor(context, color.CGColor);
	}

	[_dateText drawAtPoint:CGPointMake(0, 0) withFont:[self effectiveTextFont]];

	if (self.formatMode != TGDateLabelFormatModeNone)
		[self.formatMode == TGDateLabelFormatModeAm ? @"AM" : @"PM"
				drawInRect:CGRectMake(0, self.dstOffset, _measuredTextSize.width, self.bounds.size.height)
				withFont:[self effectiveSuffixFont] lineBreakMode:NSLineBreakByClipping alignment:NSTextAlignmentRight];
}

- (void)drawRect:(CGRect)__unused rect {
	[self drawTextInRect:self.bounds];
}

@end

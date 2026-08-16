#import <UIKit/UIKit.h>

BOOL TGEmojiTextNeedsSubstitution(NSString *text);

CGSize TGEmojiTextSize(NSString *text, UIFont *font, CGSize limit,
					   NSLineBreakMode mode, NSInteger maxLines);

void TGEmojiTextDraw(NSString *text, UIFont *font, UIColor *colour, CGRect rect,
					 NSTextAlignment alignment, NSInteger maxLines);

@interface TGEmojiLabel : UILabel
@end

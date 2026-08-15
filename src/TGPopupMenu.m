#import "TGPopupMenu.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kMenuHeight = 41.0f;
static const CGFloat kMenuTitlePadding = 34.0f;
static const CGFloat kMenuLineInset = 10.0f;
static const NSTimeInterval kMenuReopenSuppression = 0.4;

static TGPopupMenu *sOpenMenu = nil;
static NSTimeInterval sLastHideTime = 0;

@protocol TGPopupMenuButtonDelegate <NSObject>

- (void)menuButtonHighlightChanged;

@end

@interface TGPopupMenuButton : UIButton

@property (nonatomic, weak) id<TGPopupMenuButtonDelegate> delegate;

@property (nonatomic, strong) UIImageView *leftView;
@property (nonatomic, strong) UIImageView *centerView;
@property (nonatomic, strong) UIImageView *rightView;

@property (nonatomic, strong) UIImageView *topLeftView;
@property (nonatomic, strong) UIImageView *topRightView;
@property (nonatomic, strong) UIImageView *bottomLeftView;
@property (nonatomic, strong) UIImageView *bottomRightView;

@end

@implementation TGPopupMenuButton

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self != nil){
		_leftView = [[UIImageView alloc] init];
		[self addSubview:_leftView];
		_centerView = [[UIImageView alloc] init];
		[self addSubview:_centerView];
		_rightView = [[UIImageView alloc] init];
		[self addSubview:_rightView];

		UIImage *topImage = [UIImage imageNamed:@"MenuButtonTopLine.png"];
		UIImage *topHighlightedImage = [UIImage imageNamed:@"MenuButtonTopLine_Highlighted.png"];
		UIImage *bottomImage = [UIImage imageNamed:@"MenuButtonBottomLine.png"];
		UIImage *bottomHighlightedImage = [UIImage imageNamed:@"MenuButtonBottomLine_Highlighted.png"];

		_topLeftView = [[UIImageView alloc] initWithImage:topImage highlightedImage:topHighlightedImage];
		[self addSubview:_topLeftView];
		_topRightView = [[UIImageView alloc] initWithImage:topImage highlightedImage:topHighlightedImage];
		[self addSubview:_topRightView];

		_bottomLeftView = [[UIImageView alloc] initWithImage:bottomImage highlightedImage:bottomHighlightedImage];
		[self addSubview:_bottomLeftView];
		_bottomRightView = [[UIImageView alloc] initWithImage:bottomImage highlightedImage:bottomHighlightedImage];
		[self addSubview:_bottomRightView];
	}
	return self;
}

- (void)applyHighlight:(BOOL)highlighted {
	_leftView.highlighted = highlighted;
	_centerView.highlighted = highlighted;
	_rightView.highlighted = highlighted;
	_topLeftView.highlighted = highlighted;
	_topRightView.highlighted = highlighted;
	_bottomLeftView.highlighted = highlighted;
	_bottomRightView.highlighted = highlighted;
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	[self applyHighlight:highlighted || self.selected];
	id<TGPopupMenuButtonDelegate> delegate = _delegate;
	[delegate menuButtonHighlightChanged];
}

- (void)setSelected:(BOOL)selected {
	[super setSelected:selected];
	[self applyHighlight:selected || self.highlighted];
	id<TGPopupMenuButtonDelegate> delegate = _delegate;
	[delegate menuButtonHighlightChanged];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGSize viewSize = self.frame.size;
	CGFloat leftWidth = _leftView.image.size.width;
	CGFloat rightWidth = _rightView.image.size.width;

	_leftView.frame = CGRectMake(0, 0, leftWidth, viewSize.height);
	_rightView.frame = CGRectMake(viewSize.width - rightWidth, 0, rightWidth, viewSize.height);
	_centerView.frame = CGRectMake(leftWidth, 0, viewSize.width - leftWidth - rightWidth, viewSize.height);

	[self bringSubviewToFront:_topLeftView];
	[self bringSubviewToFront:_topRightView];
	[self bringSubviewToFront:_bottomLeftView];
	[self bringSubviewToFront:_bottomRightView];
	[self bringSubviewToFront:self.titleLabel];
}

@end

@interface TGPopupMenu () <TGPopupMenuButtonDelegate>
@end

@implementation TGPopupMenu {
	UIView *_card;
	NSArray *_items;
	NSMutableArray *_buttons;
	NSMutableArray *_separators;
	UIImageView *_arrowTopView;
	UIImageView *_arrowBottomView;
	CGFloat _arrowLocation;
	BOOL _arrowOnTop;
	CGSize _hostSize;
	BOOL _dismissed;
	void (^_choice)(NSInteger, NSString *);
}

+ (void)dismiss {
	TGPopupMenu *menu = sOpenMenu;
	sOpenMenu = nil;
	[menu teardownAnimated:YES];
}

+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
         onChoice:(void (^)(NSInteger, NSString *))choice
{
	if (![items isKindOfClass:[NSArray class]] || !host)
		return;

	NSMutableArray *normalized = [[NSMutableArray alloc] init];
	for (id raw in items){
		if (![raw isKindOfClass:[NSDictionary class]])
			continue;
		id title = [(NSDictionary *)raw objectForKey:@"title"];
		if ([title isKindOfClass:[NSNumber class]])
			title = [title description];
		if (![title isKindOfClass:[NSString class]] || [(NSString *)title length] == 0)
			continue;
		NSMutableDictionary *item = [[NSMutableDictionary alloc] initWithDictionary:(NSDictionary *)raw];
		[item setObject:title forKey:@"title"];
		[normalized addObject:item];
	}
	if (!normalized.count)
		return;

	if ([NSDate timeIntervalSinceReferenceDate] < sLastHideTime + kMenuReopenSuppression)
		return;

	[self dismiss];

	CGRect hostBounds = host.bounds;
	if (hostBounds.size.width < 20 || hostBounds.size.height < 20)
		return;

	TGPopupMenu *menu = [[TGPopupMenu alloc] initWithFrame:hostBounds];
	[menu buildWithItems:normalized atPoint:point];
	menu->_choice = [choice copy];
	menu->_hostSize = hostBounds.size;
	[host addSubview:menu];
	sOpenMenu = menu;

	[[NSNotificationCenter defaultCenter] addObserver:menu
											 selector:@selector(externalDismiss)
												 name:UIApplicationDidEnterBackgroundNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:menu
											 selector:@selector(externalDismiss)
												 name:UIApplicationWillChangeStatusBarOrientationNotification
											   object:nil];

	[menu present];
}

- (void)externalDismiss {
	if (sOpenMenu == self)
		sOpenMenu = nil;
	[self teardownAnimated:YES];
}

- (void)teardownAnimated:(BOOL)animated {
	if (_dismissed)
		return;
	_dismissed = YES;
	_choice = nil;
	sLastHideTime = [NSDate timeIntervalSinceReferenceDate];
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	self.userInteractionEnabled = NO;

	if (!animated){
		[self removeFromSuperview];
		return;
	}

	UIView *card = _card;
	[UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
					 animations:^{
		card.alpha = 0.0f;
	} completion:^(BOOL finished){
		card.transform = CGAffineTransformMakeScale(0.1f, 0.1f);
		[self removeFromSuperview];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (_dismissed)
		return;
	CGSize size = self.bounds.size;
	if (_hostSize.width > 0 &&
		(fabs(size.width - _hostSize.width) > 0.5f || fabs(size.height - _hostSize.height) > 0.5f)){
		if (sOpenMenu == self)
			sOpenMenu = nil;
		[self teardownAnimated:NO];
	}
}

- (void)buildWithItems:(NSArray *)items atPoint:(CGPoint)point {
	_items = items;
	_buttons = [[NSMutableArray alloc] init];
	_separators = [[NSMutableArray alloc] init];
	_arrowLocation = 50;

	self.backgroundColor = [UIColor clearColor];
	self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

	_card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, kMenuHeight)];
	_card.backgroundColor = [UIColor clearColor];
	[self addSubview:_card];

	_arrowTopView = [[UIImageView alloc]
			initWithImage:[UIImage imageNamed:@"MenuArrowTop.png"]
		 highlightedImage:[UIImage imageNamed:@"MenuArrowTop_Highlighted.png"]];
	[_card addSubview:_arrowTopView];

	_arrowBottomView = [[UIImageView alloc]
			initWithImage:[UIImage imageNamed:@"MenuArrowBottom.png"]
		 highlightedImage:[UIImage imageNamed:@"MenuArrowBottom_Highlighted.png"]];
	[_card addSubview:_arrowBottomView];

	UIImage *rawLeftImage = [UIImage imageNamed:@"MenuButtonLeft.png"];
	UIImage *leftImage = [rawLeftImage stretchableImageWithLeftCapWidth:(int)(rawLeftImage.size.width - 1) topCapHeight:0];
	UIImage *rightImage = [[UIImage imageNamed:@"MenuButtonRight.png"] stretchableImageWithLeftCapWidth:0 topCapHeight:0];
	UIImage *rawCenterImage = [UIImage imageNamed:@"MenuButtonCenter.png"];
	UIImage *centerImage = [rawCenterImage stretchableImageWithLeftCapWidth:(int)(rawCenterImage.size.width / 2) topCapHeight:0];

	UIImage *rawLeftHighlightedImage = [UIImage imageNamed:@"MenuButtonLeft_Highlighted.png"];
	UIImage *leftHighlightedImage = [rawLeftHighlightedImage stretchableImageWithLeftCapWidth:(int)(rawLeftHighlightedImage.size.width - 1) topCapHeight:0];
	UIImage *rightHighlightedImage = [[UIImage imageNamed:@"MenuButtonRight_Highlighted.png"] stretchableImageWithLeftCapWidth:0 topCapHeight:0];
	UIImage *rawCenterHighlightedImage = [UIImage imageNamed:@"MenuButtonCenter_Highlighted.png"];
	UIImage *centerHighlightedImage = [rawCenterHighlightedImage stretchableImageWithLeftCapWidth:(int)(rawCenterHighlightedImage.size.width / 2) topCapHeight:0];

	UIImage *separatorImage = [UIImage imageNamed:@"MenuButtonSeparator.png"];

	UIFont *titleFont = [UIFont boldSystemFontOfSize:14];
	CGFloat maximumWidth = MAX(60.0f, self.bounds.size.width - 8.0f);

	NSMutableArray *widths = [[NSMutableArray alloc] init];
	CGFloat naturalWidth = 0;
	for (NSUInteger i = 0; i < items.count; i++){
		NSString *title = [items[i] objectForKey:@"title"];
		CGFloat width = [title sizeWithFont:titleFont].width + kMenuTitlePadding;
		if (i == 0 || i == items.count - 1)
			width += 1;
		width = floorf(width);
		naturalWidth += width;
		[widths addObject:[NSNumber numberWithFloat:width]];
	}

	if (naturalWidth > maximumWidth){
		CGFloat scale = maximumWidth / naturalWidth;
		CGFloat used = 0;
		for (NSUInteger i = 0; i < widths.count; i++){
			CGFloat width = floorf([[widths objectAtIndex:i] floatValue] * scale);
			if (width < 24)
				width = 24;
			if (i == widths.count - 1 && used + width < maximumWidth)
				width = floorf(maximumWidth - used);
			used += width;
			[widths replaceObjectAtIndex:i withObject:[NSNumber numberWithFloat:width]];
		}
	}

	UIColor *shadowNormal = [UIColor colorWithWhite:0.0f alpha:0.8f];
	UIColor *shadowHighlighted = [UIColor colorWithRed:0x18 / 255.0f
												 green:0x6b / 255.0f
												  blue:0xcb / 255.0f
												 alpha:0.6f];

	CGFloat totalWidth = 0;

	for (NSUInteger i = 0; i < items.count; i++){
		NSDictionary *item = items[i];
		NSString *title = item[@"title"];

		TGPopupMenuButton *button = [[TGPopupMenuButton alloc] initWithFrame:CGRectZero];
		button.tag = (NSInteger)i;
		button.delegate = self;
		button.titleLabel.font = titleFont;
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		button.exclusiveTouch = YES;
		[button setTitle:title forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor colorWithWhite:1.0f alpha:0.5f] forState:UIControlStateDisabled];
		[button setTitleShadowColor:shadowNormal forState:UIControlStateNormal];
		[button setTitleShadowColor:shadowHighlighted forState:UIControlStateHighlighted];
		[button setTitleShadowColor:shadowHighlighted forState:UIControlStateSelected];
		[button setTitleShadowColor:shadowHighlighted forState:UIControlStateHighlighted | UIControlStateSelected];
		[button addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];

		button.centerView.image = centerImage;
		button.centerView.highlightedImage = centerHighlightedImage;
		button.leftView.image = centerImage;
		button.leftView.highlightedImage = centerHighlightedImage;
		button.rightView.image = centerImage;
		button.rightView.highlightedImage = centerHighlightedImage;

		UIEdgeInsets titleInset = UIEdgeInsetsMake(0, 0, 0, 0);

		if (i == 0){
			button.leftView.image = leftImage;
			button.leftView.highlightedImage = leftHighlightedImage;
			titleInset.left += 2;
		}
		if (i == items.count - 1){
			button.rightView.image = rightImage;
			button.rightView.highlightedImage = rightHighlightedImage;
			titleInset.right += 2;
		}
		button.titleEdgeInsets = titleInset;

		id enabled = [item objectForKey:@"enabled"];
		if ([enabled respondsToSelector:@selector(boolValue)] && ![enabled boolValue])
			button.enabled = NO;

		CGFloat width = [[widths objectAtIndex:i] floatValue];

		button.frame = CGRectMake(totalWidth, 0, width, kMenuHeight);
		totalWidth += width;

		[_card addSubview:button];
		[_buttons addObject:button];

		if (i > 0){
			UIImageView *separator = [[UIImageView alloc] initWithImage:separatorImage];
			[_card addSubview:separator];
			[_separators addObject:separator];
		}
	}

	CGRect cardFrame = _card.frame;
	cardFrame.size.width = totalWidth;
	_card.frame = cardFrame;

	[_card bringSubviewToFront:_arrowTopView];
	[_card bringSubviewToFront:_arrowBottomView];

	[self positionCardFromRect:CGRectMake(point.x, point.y, 0, 0)];
	[self layoutCard];
}

- (void)positionCardFromRect:(CGRect)rect {
	CGRect frame = _card.frame;

	frame.origin.x = floorf(rect.origin.x + rect.size.width / 2 - frame.size.width / 2);
	if (frame.origin.x < 4)
		frame.origin.x = 4;
	if (frame.origin.x + frame.size.width > self.bounds.size.width - 4)
		frame.origin.x = self.bounds.size.width - 4 - frame.size.width;

	frame.origin.y = rect.origin.y - frame.size.height - 14;
	if (frame.origin.y < 2){
		frame.origin.y = rect.origin.y + rect.size.height + 17;
		if (frame.origin.y + frame.size.height > self.bounds.size.height - 14){
			frame.origin.y = floorf((self.bounds.size.height - frame.size.height) / 2);
			_arrowOnTop = NO;
		}
		else
			_arrowOnTop = YES;
	}
	else
		_arrowOnTop = NO;

	_arrowLocation = floorf(rect.origin.x + rect.size.width / 2) - frame.origin.x;

	_card.layer.anchorPoint = CGPointMake(MAX(0.0f, MIN(1.0f, _arrowLocation / frame.size.width)),
										  _arrowOnTop ? -0.2f : 1.2f);
	_card.frame = frame;
}

- (BOOL)buttonContainsArrow:(TGPopupMenuButton *)button atIndex:(NSUInteger)index {
	BOOL containsArrow = _arrowLocation >= button.frame.origin.x &&
						 _arrowLocation < button.frame.origin.x + button.frame.size.width;
	if (index == 0 && _arrowLocation < button.frame.size.width)
		containsArrow = YES;
	if (index == _buttons.count - 1 && _arrowLocation >= button.frame.origin.x)
		containsArrow = YES;
	return containsArrow;
}

- (void)menuButtonHighlightChanged {
	BOOL arrowHighlighted = NO;

	for (NSUInteger index = 0; index < _buttons.count; index++){
		TGPopupMenuButton *button = _buttons[index];
		if (button.highlighted || button.selected){
			arrowHighlighted = [self buttonContainsArrow:button atIndex:index];
			break;
		}
	}

	_arrowTopView.highlighted = arrowHighlighted;
	_arrowBottomView.highlighted = arrowHighlighted;
}

- (void)layoutCard {
	NSUInteger count = _buttons.count;

	for (NSUInteger index = 0; index < count; index++){
		TGPopupMenuButton *button = _buttons[index];
		[button layoutSubviews];

		CGFloat linePosition = 0.0f;
		CGFloat lineWidth = button.frame.size.width;

		if (index > 0){
			UIImageView *separator = _separators[index - 1];
			separator.frame = CGRectMake(button.frame.origin.x - 1, 2, separator.image.size.width, 36);
		}

		BOOL containsArrow = [self buttonContainsArrow:button atIndex:index];

		if (index == 0){
			linePosition += kMenuLineInset;
			lineWidth -= kMenuLineInset;
		}
		if (index == count - 1)
			lineWidth -= kMenuLineInset;

		CGFloat arrowWidth = _arrowTopView.image.size.width;

		if (containsArrow){
			CGFloat minArrowX = button.frame.origin.x + (index == 0 ? kMenuLineInset : 0);
			CGFloat maxArrowX = button.frame.origin.x + button.frame.size.width - arrowWidth +
								(index == count - 1 ? (-kMenuLineInset) : 0);
			CGFloat arrowX = floorf(_arrowLocation - arrowWidth / 2);
			arrowX = MIN(MAX(minArrowX, arrowX), maxArrowX);

			_arrowTopView.frame = CGRectMake(arrowX, -9, arrowWidth, _arrowTopView.image.size.height);
			_arrowBottomView.frame = CGRectMake(arrowX, kMenuHeight - 4, _arrowBottomView.image.size.width,
												_arrowBottomView.image.size.height);
		}

		CGFloat topLineHeight = button.topLeftView.image.size.height;
		CGFloat bottomLineHeight = button.bottomLeftView.image.size.height;

		if (!_arrowOnTop || !containsArrow){
			button.topLeftView.frame = CGRectMake(linePosition, 0, lineWidth, topLineHeight);
			button.topRightView.frame = CGRectMake(linePosition, 0, 0, topLineHeight);
		}
		else {
			CGFloat firstWidth = MAX(0.0f, _arrowTopView.frame.origin.x - button.frame.origin.x - linePosition);
			button.topLeftView.frame = CGRectMake(linePosition, 0, firstWidth, topLineHeight);

			CGFloat secondLinePosition = MIN(linePosition + lineWidth, linePosition + firstWidth + arrowWidth);
			button.topRightView.frame = CGRectMake(secondLinePosition, 0,
												   MAX(0.0f, linePosition + lineWidth - secondLinePosition),
												   topLineHeight);
		}

		if (_arrowOnTop || !containsArrow){
			button.bottomLeftView.frame = CGRectMake(linePosition, kMenuHeight - 4, lineWidth, bottomLineHeight);
			button.bottomRightView.frame = CGRectMake(linePosition, kMenuHeight - 4, 0, bottomLineHeight);
		}
		else {
			CGFloat firstWidth = MAX(0.0f, _arrowBottomView.frame.origin.x - button.frame.origin.x - linePosition);
			button.bottomLeftView.frame = CGRectMake(linePosition, kMenuHeight - 4, firstWidth, bottomLineHeight);

			CGFloat secondLinePosition = MIN(linePosition + lineWidth, linePosition + firstWidth + arrowWidth);
			button.bottomRightView.frame = CGRectMake(secondLinePosition, kMenuHeight - 4,
													  MAX(0.0f, linePosition + lineWidth - secondLinePosition),
													  bottomLineHeight);
		}
	}

	_arrowTopView.hidden = !_arrowOnTop;
	_arrowBottomView.hidden = _arrowOnTop;
}

- (void)present {
	_card.alpha = 1.0f;
	_card.transform = CGAffineTransformMakeScale(0.1f, 0.1f);

	if ([_card.layer respondsToSelector:@selector(setRasterizationScale:)])
		_card.layer.rasterizationScale = [[UIScreen mainScreen] scale];
	_card.layer.shouldRasterize = YES;

	UIView *card = _card;
	[UIView animateWithDuration:0.142 delay:0
						options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
					 animations:^{
		card.transform = CGAffineTransformMakeScale(1.07f, 1.07f);
	} completion:^(BOOL finished){
		if (!finished)
			return;
		[UIView animateWithDuration:0.08 delay:0
							options:UIViewAnimationOptionBeginFromCurrentState
						 animations:^{
			card.transform = CGAffineTransformMakeScale(0.967f, 0.967f);
		} completion:^(BOOL finished2){
			if (!finished2)
				return;
			[UIView animateWithDuration:0.06 delay:0
								options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
							 animations:^{
				card.transform = CGAffineTransformIdentity;
			} completion:^(BOOL finished3){
				if (finished3)
					card.layer.shouldRasterize = NO;
			}];
		}];
	}];
}

- (void)rowTapped:(TGPopupMenuButton *)row {
	if (_dismissed)
		return;
	NSInteger index = row.tag;
	if (index < 0 || (NSUInteger)index >= _items.count)
		return;
	row.selected = YES;
	NSString *title = [[_items objectAtIndex:(NSUInteger)index] objectForKey:@"title"];
	void (^choice)(NSInteger, NSString *) = _choice;
	[self externalDismiss];
	if (choice)
		choice(index, title);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	UIView *result = [super hitTest:point withEvent:event];
	if (result == self || result == nil){
		if (!_dismissed)
			[self externalDismiss];
		return nil;
	}
	return result;
}

@end

// vim:ft=objc

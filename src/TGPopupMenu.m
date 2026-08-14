#import "TGPopupMenu.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kMenuHeight = 41.0f;
static const CGFloat kMenuTitlePadding = 34.0f;

static TGPopupMenu *sOpenMenu = nil;

@interface TGPopupMenuButton : UIButton

@property (nonatomic, strong) UIImageView *leftView;
@property (nonatomic, strong) UIImageView *centerView;
@property (nonatomic, strong) UIImageView *rightView;
@property (nonatomic, strong) UIImageView *topLineView;
@property (nonatomic, strong) UIImageView *bottomLineView;

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

		_topLineView = [[UIImageView alloc]
				initWithImage:[UIImage imageNamed:@"MenuButtonTopLine.png"]
			 highlightedImage:[UIImage imageNamed:@"MenuButtonTopLine_Highlighted.png"]];
		[self addSubview:_topLineView];

		_bottomLineView = [[UIImageView alloc]
				initWithImage:[UIImage imageNamed:@"MenuButtonBottomLine.png"]
			 highlightedImage:[UIImage imageNamed:@"MenuButtonBottomLine_Highlighted.png"]];
		[self addSubview:_bottomLineView];
	}
	return self;
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	_leftView.highlighted = highlighted;
	_centerView.highlighted = highlighted;
	_rightView.highlighted = highlighted;
	_topLineView.highlighted = highlighted;
	_bottomLineView.highlighted = highlighted;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGSize viewSize = self.frame.size;
	CGFloat leftWidth = _leftView.image.size.width;
	CGFloat rightWidth = _rightView.image.size.width;

	_leftView.frame = CGRectMake(0, 0, leftWidth, viewSize.height);
	_rightView.frame = CGRectMake(viewSize.width - rightWidth, 0, rightWidth, viewSize.height);
	_centerView.frame = CGRectMake(leftWidth, 0, viewSize.width - leftWidth - rightWidth, viewSize.height);

	[self bringSubviewToFront:_topLineView];
	[self bringSubviewToFront:_bottomLineView];
	[self bringSubviewToFront:self.titleLabel];
}

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
	[menu teardown];
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
	[self teardown];
}

- (void)teardown {
	if (_dismissed)
		return;
	_dismissed = YES;
	_choice = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self removeFromSuperview];
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
		(fabs(size.width - _hostSize.width) > 0.5f || fabs(size.height - _hostSize.height) > 0.5f))
		[self externalDismiss];
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

	CGFloat totalWidth = 0;

	for (NSUInteger i = 0; i < items.count; i++){
		NSDictionary *item = items[i];
		NSString *title = item[@"title"];

		TGPopupMenuButton *button = [[TGPopupMenuButton alloc] initWithFrame:CGRectZero];
		button.tag = (NSInteger)i;
		button.titleLabel.font = titleFont;
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		button.exclusiveTouch = YES;
		[button setTitle:title forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor colorWithWhite:1.0f alpha:0.5f] forState:UIControlStateDisabled];
		[button setTitleShadowColor:[UIColor colorWithWhite:0.0f alpha:0.8f] forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithRed:0x18 / 255.0f green:0x6b / 255.0f blue:0xcb / 255.0f alpha:0.6f] forState:UIControlStateHighlighted];
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
	if (frame.origin.x < 4)
		frame.origin.x = 4;

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

		BOOL containsArrow = _arrowLocation >= button.frame.origin.x &&
							 _arrowLocation < button.frame.origin.x + button.frame.size.width;

		if (index == 0){
			linePosition += 10;
			lineWidth -= 10;
			if (_arrowLocation < button.frame.size.width)
				containsArrow = YES;
		}
		if (index == count - 1){
			lineWidth -= 10;
			if (_arrowLocation >= button.frame.origin.x)
				containsArrow = YES;
		}

		if (containsArrow){
			CGFloat arrowWidth = _arrowTopView.image.size.width;
			CGFloat minArrowX = button.frame.origin.x + (index == 0 ? 10 : 0);
			CGFloat maxArrowX = button.frame.origin.x + button.frame.size.width - arrowWidth +
								(index == count - 1 ? (-10) : 0);
			CGFloat arrowX = floorf(_arrowLocation - arrowWidth / 2);
			arrowX = MIN(MAX(minArrowX, arrowX), maxArrowX);

			_arrowTopView.frame = CGRectMake(arrowX, -9, arrowWidth, _arrowTopView.image.size.height);
			_arrowBottomView.frame = CGRectMake(arrowX, 37, _arrowBottomView.image.size.width,
												_arrowBottomView.image.size.height);
		}

		CGFloat topLineHeight = button.topLineView.image.size.height;
		CGFloat bottomLineHeight = button.bottomLineView.image.size.height;

		button.topLineView.frame = CGRectMake(linePosition, 0, lineWidth, topLineHeight);
		button.bottomLineView.frame = CGRectMake(linePosition, kMenuHeight - 4, lineWidth, bottomLineHeight);
		button.topLineView.hidden = _arrowOnTop && containsArrow;
		button.bottomLineView.hidden = !_arrowOnTop && containsArrow;
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

- (void)rowTapped:(UIButton *)row {
	if (_dismissed)
		return;
	NSInteger index = row.tag;
	if (index < 0 || (NSUInteger)index >= _items.count)
		return;
	NSString *title = [[_items objectAtIndex:(NSUInteger)index] objectForKey:@"title"];
	void (^choice)(NSInteger, NSString *) = _choice;
	[self externalDismiss];
	if (choice)
		choice(index, title);
}

/// Anything outside the card closes the menu and chooses nothing.
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];
	if (!touch || _dismissed)
		return;
	CGPoint where = [touch locationInView:self];
	if (!CGRectContainsPoint(CGRectInset(_card.frame, -4, -12), where))
		[self externalDismiss];
}

@end

// vim:ft=objc

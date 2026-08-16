#import "TGTabBar.h"

@interface TGTabBar ()

@property (nonatomic, strong) UIImageView *backgroundView;
@property (nonatomic, strong) UIImageView *selectedView;

@property (nonatomic, strong) NSMutableArray *buttonViews;
@property (nonatomic, strong) NSMutableArray *labelViews;

@property (nonatomic, strong) UIView *unreadBadgeContainer;
@property (nonatomic, strong) UIImageView *unreadBadgeBackground;
@property (nonatomic, strong) UILabel *unreadBadgeLabel;

@end

static const CGFloat TGTabBarPadHeight = 56.0f;
static const CGFloat TGTabBarPadItemWidth = 128.0f;
static const CGFloat TGTabBarPadIconHeight = 36.0f;
static const CGFloat TGTabBarPadLabelFontSize = 13.0f;

@implementation TGTabBar {
	int _unreadCount;
}

- (BOOL)isPadLayout {
	return NO;
}

- (CGFloat)barHeight {
	return [self isPadLayout] ? TGTabBarPadHeight : 49.0f;
}

- (CGFloat)itemWidth {
	NSUInteger count = self.buttonViews.count;
	CGFloat width = self.frame.size.width;
	if (count == 0 || width < 1)
		return 0;

	if ([self isPadLayout])
		return MIN(TGTabBarPadItemWidth, floorf(width / count));

	float indicatorWidth = floorf(width / count);
	if (((int)indicatorWidth) % 2 != 0)
		indicatorWidth -= 1;
	return indicatorWidth;
}

- (CGFloat)groupLeft {
	NSUInteger count = self.buttonViews.count;
	return floorf((self.frame.size.width - [self itemWidth] * count) / 2);
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self != nil){
		self.multipleTouchEnabled = false;
		self.exclusiveTouch = true;
		UIImage *rawBackgroundImage = [UIImage imageNamed:@"TabBarBackground"];
		if ([self isPadLayout] && rawBackgroundImage.size.width > 2)
			rawBackgroundImage = [rawBackgroundImage
					stretchableImageWithLeftCapWidth:(int)(rawBackgroundImage.size.width / 2) topCapHeight:0];
		self.backgroundView = [[UIImageView alloc] initWithImage:rawBackgroundImage];
		self.backgroundView.frame = self.bounds;
		[self addSubview:self.backgroundView];

		UIImage *rawSelectedImage = [UIImage imageNamed:@"TabBarSelected"];
		self.selectedView = [[UIImageView alloc] initWithImage:
				[rawSelectedImage stretchableImageWithLeftCapWidth:(int)(rawSelectedImage.size.width / 2) topCapHeight:0]];
		[self addSubview:self.selectedView];

		self.buttonViews = [NSMutableArray array];
		self.labelViews = [NSMutableArray array];

		NSArray *names = @[@"Contacts", @"Messages", @"Settings"];
		NSArray *icons = @[@"TabIconContacts", @"TabIconMessages", @"TabIconSettings"];

		for (NSUInteger i = 0; i < names.count; i++){
			UIImageView *icon = [[UIImageView alloc]
					initWithImage:[UIImage imageNamed:icons[i]]
					highlightedImage:[UIImage imageNamed:[icons[i] stringByAppendingString:@"_Highlighted"]]];
			[self addSubview:icon];
			[self.buttonViews addObject:icon];

			UILabel *label = [[UILabel alloc] init];
			label.backgroundColor = [UIColor clearColor];
			label.textColor = [UIColor colorWithRed:0x99 / 255.0f green:0x99 / 255.0f blue:0x99 / 255.0f alpha:1.0f];
			label.highlightedTextColor = [UIColor whiteColor];
			label.font = [UIFont boldSystemFontOfSize:
					[self isPadLayout] ? TGTabBarPadLabelFontSize : 10.0f];
			label.text = names[i];
			[label sizeToFit];
			label.isAccessibilityElement = true;
			label.accessibilityLabel = names[i];
			label.accessibilityTraits = UIAccessibilityTraitButton;
			[self addSubview:label];
			[self.labelViews addObject:label];
		}

		_unreadCount = 0;
		[self updateAccessibility];
	}
	return self;
}

- (void)updateAccessibility {
	for (NSUInteger i = 0; i < self.labelViews.count; i++){
		UILabel *label = self.labelViews[i];
		NSMutableString *value = [NSMutableString string];
		if ((int)i == _selectedIndex)
			[value appendString:@"selected"];
		if (i == 1 && _unreadCount > 0){
			if (value.length != 0)
				[value appendString:@", "];
			[value appendFormat:@"%d unread", _unreadCount];
		}
		label.accessibilityValue = value.length != 0 ? value : nil;
	}
}

- (void)setFrame:(CGRect)frame {
	if ([self isPadLayout]){
		CGFloat height = [self barHeight];
		frame.origin.y += frame.size.height - height;
		frame.size.height = height;
	}
	[super setFrame:frame];
}

- (void)layoutSelectedView {
	NSUInteger count = self.buttonViews.count;
	CGFloat width = self.frame.size.width;
	if (count == 0 || width < 1)
		return;

	float indicatorWidth = [self itemWidth];
	float paddingLeft = [self groupLeft];

	if ([self isPadLayout]){
		self.selectedView.frame = CGRectMake(paddingLeft + indicatorWidth * _selectedIndex,
											  0, indicatorWidth, [self barHeight]);
		return;
	}

	float additionalWidth = 0;
	float additionalOffset = 0;
	if (_selectedIndex == 0 || _selectedIndex == (int)count - 1)
		additionalWidth += paddingLeft + 1;
	if (_selectedIndex == 0)
		additionalOffset += -paddingLeft - 1;

	self.selectedView.frame = CGRectMake(paddingLeft + indicatorWidth * _selectedIndex + additionalOffset,
										  0, indicatorWidth + additionalWidth, 49);
}

- (int)indexForLocation:(CGPoint)location {
	NSUInteger count = self.buttonViews.count;
	if (count == 0)
		return -1;

	if ([self isPadLayout]){
		CGFloat itemWidth = [self itemWidth];
		if (itemWidth < 1)
			return -1;
		CGFloat offset = location.x - [self groupLeft];
		if (offset < 0 || offset >= itemWidth * count)
			return -1;
		return (int)(offset / itemWidth);
	}

	return MAX(0, MIN((int)count - 1, (int)(location.x / (self.frame.size.width / count))));
}

- (void)setSelectedIndex:(int)selectedIndex {
	if (self.buttonViews.count != 0)
		selectedIndex = MAX(0, MIN((int)self.buttonViews.count - 1, selectedIndex));

	if (_selectedIndex >= 0 && _selectedIndex < (int)self.buttonViews.count){
		((UIImageView *)self.buttonViews[_selectedIndex]).highlighted = false;
		((UILabel *)self.labelViews[_selectedIndex]).highlighted = false;
	}

	_selectedIndex = selectedIndex;
	[self layoutSelectedView];
	[self setNeedsLayout];

	if (_selectedIndex >= 0 && _selectedIndex < (int)self.buttonViews.count){
		((UIImageView *)self.buttonViews[_selectedIndex]).highlighted = true;
		((UILabel *)self.labelViews[_selectedIndex]).highlighted = true;
	}

	[self updateAccessibility];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	[super touchesBegan:touches withEvent:event];

	UITouch *touch = [touches anyObject];
	if (touch == nil || self.buttonViews.count == 0)
		return;

	int index = [self indexForLocation:[touch locationInView:self]];
	if (index < 0)
		return;

	self.selectedIndex = index;

	if ([self.tabDelegate respondsToSelector:@selector(tabBarSelectedItem:)])
		[self.tabDelegate tabBarSelectedItem:index];
}

- (void)loadUnreadBadgeView {
	if (self.unreadBadgeContainer != nil)
		return;

	self.unreadBadgeContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
	self.unreadBadgeContainer.hidden = true;
	self.unreadBadgeContainer.userInteractionEnabled = false;
	self.unreadBadgeContainer.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self addSubview:self.unreadBadgeContainer];

	UIImage *badgeBackground = [UIImage imageNamed:@"TabBarBadge"];
	self.unreadBadgeBackground = [[UIImageView alloc] initWithImage:
			[badgeBackground stretchableImageWithLeftCapWidth:10 topCapHeight:0]];
	[self.unreadBadgeContainer addSubview:self.unreadBadgeBackground];

	CGFloat retinaPixel = [UIScreen mainScreen].scale > 1 ? 0.5f : 0.0f;

	self.unreadBadgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(9, 4 + retinaPixel, 28 + retinaPixel, 10)];
	self.unreadBadgeLabel.backgroundColor = [UIColor clearColor];
	self.unreadBadgeLabel.textColor = [UIColor whiteColor];
	self.unreadBadgeLabel.font = [UIFont boldSystemFontOfSize:11];
	[self.unreadBadgeContainer addSubview:self.unreadBadgeLabel];

	[self setNeedsLayout];
}

- (void)setUnreadCount:(int)unreadCount {
	if (unreadCount < 0)
		unreadCount = 0;

	_unreadCount = unreadCount;
	[self updateAccessibility];

	if (unreadCount <= 0 && self.unreadBadgeLabel == nil)
		return;

	[self loadUnreadBadgeView];

	if (unreadCount <= 0){
		self.unreadBadgeLabel.text = nil;
		self.unreadBadgeContainer.hidden = true;
		return;
	}

	NSString *text;
	if (unreadCount < 1000)
		text = [NSString stringWithFormat:@"%d", unreadCount];
	else if (unreadCount < 1000000)
		text = [NSString stringWithFormat:@"%dK", unreadCount / 1000];
	else
		text = [NSString stringWithFormat:@"%dM", unreadCount / 1000000];

	CGFloat retinaPixel = [UIScreen mainScreen].scale > 1 ? 0.5f : 0.0f;

	self.unreadBadgeLabel.text = text;
	self.unreadBadgeContainer.hidden = false;

	CGRect frame = self.unreadBadgeBackground.frame;
	int textWidth = (int)[text sizeWithFont:self.unreadBadgeLabel.font
						constrainedToSize:self.unreadBadgeLabel.bounds.size
							lineBreakMode:NSLineBreakByTruncatingTail].width;
	frame.size.width = MAX(20, textWidth + 12 + retinaPixel * 2);
	frame.origin.x = self.unreadBadgeBackground.superview.frame.size.width - frame.size.width;
	self.unreadBadgeBackground.frame = frame;

	CGRect labelFrame = self.unreadBadgeLabel.frame;
	labelFrame.origin.x = 6 + retinaPixel + frame.origin.x;
	self.unreadBadgeLabel.frame = labelFrame;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGSize viewSize = self.frame.size;
	self.backgroundView.frame = CGRectMake(0, 0, viewSize.width, viewSize.height);

	NSUInteger count = self.buttonViews.count;
	if (count == 0 || viewSize.width < 1)
		return;

	float indicatorWidth = [self itemWidth];
	float paddingLeft = [self groupLeft];
	BOOL pad = [self isPadLayout];
	[self layoutSelectedView];

	int index = -1;
	for (UIImageView *iconView in self.buttonViews){
		index++;

		CGRect frame = iconView.frame;
		if (pad){
			CGSize imageSize = iconView.image.size;
			if (imageSize.height > 0){
				CGFloat scale = TGTabBarPadIconHeight / imageSize.height;
				frame.size = CGSizeMake(floorf(imageSize.width * scale), floorf(imageSize.height * scale));
			}
		}
		frame.origin.x = paddingLeft + index * indicatorWidth + floorf((indicatorWidth - frame.size.width) / 2);
		frame.origin.y = pad ? 1 : 4;
		iconView.frame = frame;

		if (index == 1 && self.unreadBadgeContainer != nil){
			CGRect unreadBadgeContainerFrame = self.unreadBadgeContainer.frame;
			unreadBadgeContainerFrame.origin.x = frame.origin.x + frame.size.width - 9;
			unreadBadgeContainerFrame.origin.y = pad ? 0 : 2;
			self.unreadBadgeContainer.frame = unreadBadgeContainerFrame;
		}

		UILabel *labelView = self.labelViews[index];
		CGRect labelFrame = labelView.frame;
		labelFrame.origin.x = paddingLeft + index * indicatorWidth + floorf((indicatorWidth - labelFrame.size.width) / 2);
		labelFrame.origin.y = pad ? floorf(viewSize.height - labelFrame.size.height - 2) : 35;
		labelView.frame = labelFrame;
	}
}

@end

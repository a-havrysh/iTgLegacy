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

@implementation TGTabBar {
	BOOL _tracking;
	int _touchStartIndex;
	int _pendingIndex;
	int _unreadCount;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self != nil){
		self.multipleTouchEnabled = false;
		self.exclusiveTouch = true;
		self.backgroundView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"TabBarBackground"]];
		self.backgroundView.frame = self.bounds;
		self.backgroundView.opaque = NO;
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
			label.font = [UIFont boldSystemFontOfSize:10];
			label.text = names[i];
			[label sizeToFit];
			label.isAccessibilityElement = true;
			label.accessibilityLabel = names[i];
			label.accessibilityTraits = UIAccessibilityTraitButton;
			[self addSubview:label];
			[self.labelViews addObject:label];
		}

		_tracking = false;
		_touchStartIndex = 0;
		_pendingIndex = -1;
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

- (int)indexForLocation:(CGPoint)location {
	NSUInteger count = self.buttonViews.count;
	if (count == 0)
		return -1;
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

	_tracking = true;
	_touchStartIndex = _selectedIndex;
	_pendingIndex = index;
	self.selectedIndex = index;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	[super touchesMoved:touches withEvent:event];

	if (!_tracking)
		return;

	UITouch *touch = [touches anyObject];
	if (touch == nil)
		return;

	CGPoint location = [touch locationInView:self];
	if (!CGRectContainsPoint(CGRectInset(self.bounds, 0, -16), location)){
		if (_pendingIndex >= 0){
			_pendingIndex = -1;
			self.selectedIndex = _touchStartIndex;
		}
		return;
	}

	int index = [self indexForLocation:location];
	if (index >= 0 && index != _pendingIndex){
		_pendingIndex = index;
		self.selectedIndex = index;
	}
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	[super touchesEnded:touches withEvent:event];

	BOOL wasTracking = _tracking;
	int index = _pendingIndex;
	_tracking = false;
	_pendingIndex = -1;

	if (!wasTracking || index < 0 || index >= (int)self.buttonViews.count)
		return;

	self.selectedIndex = index;

	if ([self.tabDelegate respondsToSelector:@selector(tabBarSelectedItem:)])
		[self.tabDelegate tabBarSelectedItem:index];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
	[super touchesCancelled:touches withEvent:event];

	if (!_tracking)
		return;

	_tracking = false;
	_pendingIndex = -1;
	self.selectedIndex = _touchStartIndex;
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

	float indicatorWidth = floorf(viewSize.width / count);
	if (((int)indicatorWidth) % 2 != 0)
		indicatorWidth -= 1;

	float paddingLeft = floorf((viewSize.width - indicatorWidth * count) / 2);
	float additionalWidth = 0;
	float additionalOffset = 0;
	if (self.selectedIndex == 0 || self.selectedIndex == (int)count - 1)
		additionalWidth += paddingLeft + 1;
	if (self.selectedIndex == 0)
		additionalOffset += -paddingLeft - 1;

	self.selectedView.frame = CGRectMake(paddingLeft + indicatorWidth * self.selectedIndex + additionalOffset,
										  0, indicatorWidth + additionalWidth, 49);

	int index = -1;
	for (UIView *iconView in self.buttonViews){
		index++;

		CGRect frame = iconView.frame;
		frame.origin.x = paddingLeft + index * indicatorWidth + floorf((indicatorWidth - frame.size.width) / 2);
		frame.origin.y = 4;
		iconView.frame = frame;

		if (index == 1 && self.unreadBadgeContainer != nil){
			CGRect unreadBadgeContainerFrame = self.unreadBadgeContainer.frame;
			unreadBadgeContainerFrame.origin.x = frame.origin.x + frame.size.width - 9;
			unreadBadgeContainerFrame.origin.y = 2;
			self.unreadBadgeContainer.frame = unreadBadgeContainerFrame;
		}

		UILabel *labelView = self.labelViews[index];
		CGRect labelFrame = labelView.frame;
		labelFrame.origin.x = paddingLeft + index * indicatorWidth + floorf((indicatorWidth - labelFrame.size.width) / 2);
		labelFrame.origin.y = 35;
		labelView.frame = labelFrame;
	}
}

@end

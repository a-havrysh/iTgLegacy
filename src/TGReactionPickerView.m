#import "TGReactionPickerView.h"
#import "TGClient.h"
#import "TGClient+Reactions.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kStripHeight = 41.0f;
static const CGFloat kStripButtonWidth = 44.0f;
static const CGFloat kStripVisibleButtons = 6.0f;
static const CGFloat kStripEmojiFontSize = 24.0f;
static const NSTimeInterval kStripReopenSuppression = 0.4;

static const CGFloat kChipHeight = 20.0f;
static const CGFloat kChipPadding = 7.0f;
static const CGFloat kChipGap = 4.0f;
static const CGFloat kChipRowGap = 3.0f;
static const CGFloat kChipEmojiFontSize = 13.0f;
static const CGFloat kChipCountFontSize = 11.0f;
static const CGFloat kChipCountGap = 3.0f;

static TGReactionPickerView *sOpenPicker = nil;
static NSTimeInterval sLastHideTime = 0;

static UIImage *TGReactionStretch(NSString *name, int cap) {
	UIImage *image = [UIImage imageNamed:name];
	if (image == nil)
		return nil;
	if (cap == -1)
		cap = (int)(image.size.width / 2);
	else if (cap < -1)
		cap = (int)(image.size.width - 1);
	if (cap > (int)image.size.width - 1)
		cap = MAX(0, (int)image.size.width - 1);
	return [image stretchableImageWithLeftCapWidth:cap topCapHeight:0];
}

#pragma mark - one emoji button

@interface TGReactionStripButton : UIButton

@property (nonatomic, strong) UIImageView *leftView;
@property (nonatomic, strong) UIImageView *centerView;
@property (nonatomic, strong) UIImageView *rightView;
@property (nonatomic, strong) UILabel *emojiLabel;
@property (nonatomic, copy) NSString *emoji;

@end

@implementation TGReactionStripButton

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self != nil){
		_leftView = [[UIImageView alloc] init];
		[self addSubview:_leftView];
		_centerView = [[UIImageView alloc] init];
		[self addSubview:_centerView];
		_rightView = [[UIImageView alloc] init];
		[self addSubview:_rightView];

		_emojiLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_emojiLabel.backgroundColor = [UIColor clearColor];
		_emojiLabel.textAlignment = NSTextAlignmentCenter;
		_emojiLabel.font = [UIFont systemFontOfSize:kStripEmojiFontSize];
		_emojiLabel.textColor = [UIColor whiteColor];
		[self addSubview:_emojiLabel];

		self.exclusiveTouch = YES;
		self.adjustsImageWhenHighlighted = NO;
		self.adjustsImageWhenDisabled = NO;
	}
	return self;
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	_leftView.highlighted = highlighted;
	_centerView.highlighted = highlighted;
	_rightView.highlighted = highlighted;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGSize size = self.bounds.size;
	CGFloat leftWidth = _leftView.image.size.width;
	CGFloat rightWidth = _rightView.image.size.width;

	_leftView.frame = CGRectMake(0, 0, leftWidth, size.height);
	_rightView.frame = CGRectMake(size.width - rightWidth, 0, rightWidth, size.height);
	_centerView.frame = CGRectMake(leftWidth, 0, MAX(0.0f, size.width - leftWidth - rightWidth), size.height);

	_emojiLabel.frame = CGRectMake(0, 4, size.width, size.height - 8);
	[self bringSubviewToFront:_emojiLabel];
}

@end

#pragma mark - the strip

@implementation TGReactionPickerView {
	UIView *_card;
	UIScrollView *_scrollView;
	UIImageView *_arrowTopView;
	UIImageView *_arrowBottomView;
	UIImageView *_topLineView;
	UIImageView *_bottomLineView;
	UIActivityIndicatorView *_spinner;
	UILabel *_noticeLabel;
	NSMutableArray *_buttons;
	NSMutableArray *_separators;
	CGRect _anchorRect;
	CGFloat _arrowLocation;
	BOOL _arrowOnTop;
	BOOL _dismissed;
	BOOL _loading;
	CGSize _hostSize;
}

+ (void)dismiss {
	TGReactionPickerView *picker = sOpenPicker;
	sOpenPicker = nil;
	[picker teardownAnimated:YES];
}

+ (instancetype)showForMessage:(int64_t)messageId
                        inChat:(int64_t)chatId
                      fromRect:(CGRect)rect
                        inView:(UIView *)host
                        picked:(TGReactionPickedBlock)picked
{
	if (host == nil)
		return nil;

	CGRect hostBounds = host.bounds;
	if (hostBounds.size.width < 40 || hostBounds.size.height < 40)
		return nil;

	BOOL wasOpen = (sOpenPicker != nil);
	[self dismiss];
	if (!wasOpen && [NSDate timeIntervalSinceReferenceDate] - sLastHideTime < kStripReopenSuppression)
		return nil;

	TGReactionPickerView *picker = [[TGReactionPickerView alloc] initWithFrame:hostBounds];
	picker.chatId = chatId;
	picker.messageId = messageId;
	picker.onReactionPicked = picked;
	picker->_anchorRect = rect;
	picker->_hostSize = hostBounds.size;
	[host addSubview:picker];
	sOpenPicker = picker;

	[[NSNotificationCenter defaultCenter] addObserver:picker
	                                         selector:@selector(externalDismiss)
	                                             name:UIApplicationDidEnterBackgroundNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:picker
	                                         selector:@selector(externalDismiss)
	                                             name:UIApplicationWillChangeStatusBarOrientationNotification
	                                           object:nil];

	[picker showSpinner];
	[picker present];
	[picker loadReactions];

	return picker;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self != nil){
		self.backgroundColor = [UIColor clearColor];
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

		_buttons = [[NSMutableArray alloc] init];
		_separators = [[NSMutableArray alloc] init];
		_arrowLocation = 50;
		_anchorRect = CGRectMake(frame.size.width / 2, frame.size.height / 2, 0, 0);

		_card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, kStripHeight)];
		_card.backgroundColor = [UIColor clearColor];
		_card.clipsToBounds = NO;
		[self addSubview:_card];

		_scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 0, kStripHeight)];
		_scrollView.backgroundColor = [UIColor clearColor];
		_scrollView.showsHorizontalScrollIndicator = NO;
		_scrollView.showsVerticalScrollIndicator = NO;
		_scrollView.alwaysBounceHorizontal = NO;
		_scrollView.clipsToBounds = YES;
		[_card addSubview:_scrollView];

		_topLineView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"MenuButtonTopLine.png"]];
		[_card addSubview:_topLineView];
		_bottomLineView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"MenuButtonBottomLine.png"]];
		[_card addSubview:_bottomLineView];

		_arrowTopView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"MenuArrowTop.png"]];
		[_card addSubview:_arrowTopView];
		_arrowBottomView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"MenuArrowBottom.png"]];
		[_card addSubview:_arrowBottomView];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark loading

- (void)loadReactions {
	if (_dismissed)
		return;
	if (_chatId == 0 || _messageId == 0){
		[self setEmoji:nil reason:@"Reactions are not available here"];
		return;
	}

	_loading = YES;
	__weak TGReactionPickerView *weakSelf = self;
	[[TGClient shared] availableReactionsForMessage:_messageId
	                                         inChat:_chatId
	                                     completion:^(NSDictionary *info)
	{
		TGReactionPickerView *strongSelf = weakSelf;
		if (strongSelf == nil || strongSelf->_dismissed)
			return;
		strongSelf->_loading = NO;

		if (![info isKindOfClass:[NSDictionary class]]){
			[strongSelf setEmoji:nil reason:@"Could not load reactions"];
			return;
		}

		NSString *reason = [info objectForKey:@"reason"];
		if (![reason isKindOfClass:[NSString class]])
			reason = @"";

		NSArray *emoji = [info objectForKey:@"allEmoji"];
		if (![emoji isKindOfClass:[NSArray class]])
			emoji = nil;

		if (reason.length == 0 && emoji.count == 0)
			reason = @"No reactions are allowed here";

		[strongSelf setEmoji:emoji reason:reason];
	}];
}

- (void)showSpinner {
	[self clearContent];
	_loading = YES;

	_spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
	[_scrollView addSubview:_spinner];
	[_spinner startAnimating];

	[self buildPlainCardOfWidth:64.0f];
	_spinner.center = CGPointMake(32.0f, kStripHeight / 2);
}

- (void)setEmoji:(NSArray *)emoji reason:(NSString *)reason {
	if (_dismissed)
		return;

	_loading = NO;
	[self clearContent];

	if ([reason isKindOfClass:[NSString class]] && reason.length > 0){
		[self buildNoticeWithText:reason];
		return;
	}

	NSMutableArray *usable = [[NSMutableArray alloc] init];
	for (id raw in emoji){
		if ([raw isKindOfClass:[NSString class]] && [(NSString *)raw length] > 0)
			[usable addObject:raw];
	}
	if (usable.count == 0){
		[self buildNoticeWithText:@"No reactions are allowed here"];
		return;
	}

	NSString *quick = [[TGClient shared] quickReactionEmoji];

	UIImage *leftImage = TGReactionStretch(@"MenuButtonLeft.png", -2);
	UIImage *rightImage = TGReactionStretch(@"MenuButtonRight.png", 0);
	UIImage *centerImage = TGReactionStretch(@"MenuButtonCenter.png", -1);
	UIImage *leftHighlighted = TGReactionStretch(@"MenuButtonLeft_Highlighted.png", -2);
	UIImage *rightHighlighted = TGReactionStretch(@"MenuButtonRight_Highlighted.png", 0);
	UIImage *centerHighlighted = TGReactionStretch(@"MenuButtonCenter_Highlighted.png", -1);
	UIImage *separatorImage = [UIImage imageNamed:@"MenuButtonSeparator.png"];

	CGFloat x = 0;
	for (NSUInteger i = 0; i < usable.count; i++){
		NSString *value = [usable objectAtIndex:i];

		TGReactionStripButton *button = [[TGReactionStripButton alloc] initWithFrame:
				CGRectMake(x, 0, kStripButtonWidth, kStripHeight)];
		button.emoji = value;
		button.emojiLabel.text = value;
		button.tag = (NSInteger)i;

		button.centerView.image = centerImage;
		button.centerView.highlightedImage = centerHighlighted;
		button.leftView.image = centerImage;
		button.leftView.highlightedImage = centerHighlighted;
		button.rightView.image = centerImage;
		button.rightView.highlightedImage = centerHighlighted;

		if (i == 0){
			button.leftView.image = leftImage;
			button.leftView.highlightedImage = leftHighlighted;
		}
		if (i == usable.count - 1){
			button.rightView.image = rightImage;
			button.rightView.highlightedImage = rightHighlighted;
		}

		if ([value isEqualToString:quick])
			button.emojiLabel.font = [UIFont systemFontOfSize:kStripEmojiFontSize + 2];

		[button addTarget:self action:@selector(emojiTapped:) forControlEvents:UIControlEventTouchUpInside];
		[_scrollView addSubview:button];
		[_buttons addObject:button];

		if (i > 0 && separatorImage != nil){
			UIImageView *separator = [[UIImageView alloc] initWithImage:separatorImage];
			separator.frame = CGRectMake(x - 1, 2, separatorImage.size.width, 36);
			[_scrollView addSubview:separator];
			[_separators addObject:separator];
		}

		x += kStripButtonWidth;
	}

	CGFloat visible = MIN(x, kStripVisibleButtons * kStripButtonWidth);
	_scrollView.contentSize = CGSizeMake(x, kStripHeight);
	_scrollView.scrollEnabled = (x > visible + 0.5f);

	[self buildPlainCardOfWidth:visible];
}

- (void)buildNoticeWithText:(NSString *)text {
	UIFont *font = [UIFont boldSystemFontOfSize:14];
	CGFloat maximumWidth = MAX(80.0f, self.bounds.size.width - 8.0f);
	CGFloat width = MIN(maximumWidth, [text sizeWithFont:font].width + 34.0f);

	_noticeLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, width - 20, kStripHeight)];
	_noticeLabel.backgroundColor = [UIColor clearColor];
	_noticeLabel.font = font;
	_noticeLabel.textColor = [UIColor whiteColor];
	_noticeLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.8f];
	_noticeLabel.shadowOffset = CGSizeMake(0, -1);
	_noticeLabel.textAlignment = NSTextAlignmentCenter;
	_noticeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	_noticeLabel.text = text;

	UIImage *centerImage = TGReactionStretch(@"MenuButtonCenter.png", -1);
	UIImageView *plate = [[UIImageView alloc] initWithImage:centerImage];
	plate.frame = CGRectMake(0, 0, width, kStripHeight);
	[_scrollView addSubview:plate];
	[_scrollView addSubview:_noticeLabel];

	_scrollView.contentSize = CGSizeMake(width, kStripHeight);
	_scrollView.scrollEnabled = NO;

	[self buildPlainCardOfWidth:width];
}

- (void)buildPlainCardOfWidth:(CGFloat)width {
	CGFloat maximumWidth = MAX(60.0f, self.bounds.size.width - 8.0f);
	width = MIN(width, maximumWidth);
	if (width < 40.0f)
		width = 40.0f;

	CGRect cardFrame = _card.frame;
	cardFrame.size = CGSizeMake(width, kStripHeight);
	_card.frame = cardFrame;
	_scrollView.frame = CGRectMake(0, 0, width, kStripHeight);

	[self positionCard];
	[self layoutCard];
}

- (void)clearContent {
	for (UIView *view in _buttons)
		[view removeFromSuperview];
	for (UIView *view in _separators)
		[view removeFromSuperview];
	[_buttons removeAllObjects];
	[_separators removeAllObjects];

	for (UIView *view in [_scrollView.subviews copy])
		[view removeFromSuperview];

	_spinner = nil;
	_noticeLabel = nil;
	_scrollView.contentOffset = CGPointZero;
}

#pragma mark placement

- (void)positionCard {
	CGRect frame = _card.frame;
	CGRect rect = _anchorRect;

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

	_card.layer.anchorPoint = CGPointMake(MAX(0.0f, MIN(1.0f, _arrowLocation / MAX(1.0f, frame.size.width))),
	                                      _arrowOnTop ? -0.2f : 1.2f);
	_card.frame = frame;
}

- (void)layoutCard {
	CGFloat width = _card.bounds.size.width;

	CGFloat topHeight = _topLineView.image.size.height;
	CGFloat bottomHeight = _bottomLineView.image.size.height;
	_topLineView.frame = CGRectMake(10, 0, MAX(0.0f, width - 20), topHeight);
	_bottomLineView.frame = CGRectMake(10, kStripHeight - 4, MAX(0.0f, width - 20), bottomHeight);

	CGFloat arrowWidth = _arrowTopView.image.size.width;
	CGFloat arrowX = floorf(_arrowLocation - arrowWidth / 2);
	arrowX = MIN(MAX(10.0f, arrowX), MAX(10.0f, width - arrowWidth - 10.0f));

	_arrowTopView.frame = CGRectMake(arrowX, -9, arrowWidth, _arrowTopView.image.size.height);
	_arrowBottomView.frame = CGRectMake(arrowX, kStripHeight - 4, _arrowBottomView.image.size.width,
	                                    _arrowBottomView.image.size.height);

	_arrowTopView.hidden = !_arrowOnTop;
	_arrowBottomView.hidden = _arrowOnTop;

	[_card bringSubviewToFront:_arrowTopView];
	[_card bringSubviewToFront:_arrowBottomView];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (_dismissed)
		return;
	CGSize size = self.bounds.size;
	if (_hostSize.width > 0 &&
		(fabs(size.width - _hostSize.width) > 0.5f || fabs(size.height - _hostSize.height) > 0.5f)){
		if (sOpenPicker == self)
			sOpenPicker = nil;
		[self teardownAnimated:NO];
	}
}

#pragma mark interaction

- (void)emojiTapped:(TGReactionStripButton *)button {
	if (_dismissed)
		return;

	NSString *emoji = button.emoji;
	if (emoji.length == 0)
		return;

	TGReactionPickedBlock picked = self.onReactionPicked;

	if (sOpenPicker == self)
		sOpenPicker = nil;
	[self teardownAnimated:YES];

	if (_chatId == 0 || _messageId == 0){
		if (picked != nil)
			picked(emoji, YES);
		return;
	}

	[[TGClient shared] toggleReaction:emoji
	                        onMessage:_messageId
	                           inChat:_chatId
	                              big:NO
	                       completion:^(BOOL nowChosen)
	{
		if (picked != nil)
			picked(emoji, nowChosen);
	}];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	[super touchesEnded:touches withEvent:event];
	CGPoint point = [[touches anyObject] locationInView:self];
	if (!CGRectContainsPoint(_card.frame, point)){
		if (sOpenPicker == self)
			sOpenPicker = nil;
		[self teardownAnimated:YES];
	}
}

- (void)externalDismiss {
	if (sOpenPicker == self)
		sOpenPicker = nil;
	[self teardownAnimated:YES];
}

- (void)teardownAnimated:(BOOL)animated {
	if (_dismissed)
		return;
	_dismissed = YES;
	self.onReactionPicked = nil;
	sLastHideTime = [NSDate timeIntervalSinceReferenceDate];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_spinner stopAnimating];

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
		[UIView animateWithDuration:0.08 delay:0
		                    options:UIViewAnimationOptionBeginFromCurrentState
		                 animations:^{
			card.transform = CGAffineTransformMakeScale(0.967f, 0.967f);
		} completion:^(BOOL finished2){
			[UIView animateWithDuration:0.06 delay:0
			                    options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
			                 animations:^{
				card.transform = CGAffineTransformIdentity;
			} completion:^(BOOL finished3){
				card.layer.shouldRasterize = NO;
			}];
		}];
	}];
}

@end

#pragma mark - one chip

@interface TGReactionChipView : UIControl

@property (nonatomic, strong) UIImageView *plateView;
@property (nonatomic, strong) UILabel *emojiLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, copy) NSString *emoji;
@property (nonatomic, assign) BOOL chosen;

@end

@implementation TGReactionChipView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self != nil){
		_plateView = [[UIImageView alloc] initWithFrame:CGRectZero];
		[self addSubview:_plateView];

		_emojiLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_emojiLabel.backgroundColor = [UIColor clearColor];
		_emojiLabel.font = [UIFont systemFontOfSize:kChipEmojiFontSize];
		[self addSubview:_emojiLabel];

		_countLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_countLabel.backgroundColor = [UIColor clearColor];
		_countLabel.font = [UIFont boldSystemFontOfSize:kChipCountFontSize];
		[self addSubview:_countLabel];

		self.exclusiveTouch = YES;
	}
	return self;
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	self.alpha = highlighted ? 0.6f : 1.0f;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGSize size = self.bounds.size;
	_plateView.frame = CGRectMake(0, 0, size.width, size.height);

	CGFloat emojiWidth = [_emojiLabel.text sizeWithFont:_emojiLabel.font].width;
	_emojiLabel.frame = CGRectMake(kChipPadding, 0, emojiWidth, size.height);

	CGFloat countX = kChipPadding + emojiWidth + kChipCountGap;
	_countLabel.frame = CGRectMake(countX, 0, MAX(0.0f, size.width - countX - kChipPadding), size.height);
}

@end

#pragma mark - the chip row

@interface TGReactionChipsView ()

+ (CGFloat)chipWidthForEmoji:(NSString *)emoji count:(NSInteger)count;

@end

@implementation TGReactionChipsView {
	NSMutableArray *_chipViews;
}

+ (CGFloat)chipWidthForEmoji:(NSString *)emoji count:(NSInteger)count {
	CGFloat emojiWidth = [emoji sizeWithFont:[UIFont systemFontOfSize:kChipEmojiFontSize]].width;
	NSString *countText = [NSString stringWithFormat:@"%d", (int)MAX(1, count)];
	CGFloat countWidth = [countText sizeWithFont:[UIFont boldSystemFontOfSize:kChipCountFontSize]].width;
	return floorf(kChipPadding * 2 + emojiWidth + kChipCountGap + countWidth);
}

+ (CGFloat)heightForChips:(NSArray *)chips width:(CGFloat)width {
	if (![chips isKindOfClass:[NSArray class]] || chips.count == 0)
		return 0.0f;
	if (width < 40.0f)
		width = 40.0f;

	CGFloat x = 0;
	NSInteger rows = 1;
	for (id raw in chips){
		if (![raw isKindOfClass:[NSDictionary class]])
			continue;
		NSString *emoji = [(NSDictionary *)raw objectForKey:@"emoji"];
		if (![emoji isKindOfClass:[NSString class]] || emoji.length == 0)
			continue;
		NSInteger count = [[(NSDictionary *)raw objectForKey:@"count"] integerValue];
		CGFloat chipWidth = [self chipWidthForEmoji:emoji count:count];
		if (x > 0 && x + chipWidth > width){
			rows++;
			x = 0;
		}
		x += chipWidth + kChipGap;
	}
	if (x == 0 && rows == 1)
		return 0.0f;
	return rows * kChipHeight + (rows - 1) * kChipRowGap;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self != nil){
		self.backgroundColor = [UIColor clearColor];
		self.clipsToBounds = NO;
		_chipViews = [[NSMutableArray alloc] init];
		self.hidden = YES;
	}
	return self;
}

- (UIImage *)plateChosen:(BOOL)chosen {
	NSString *name = nil;
	if (_outgoing)
		name = chosen ? @"Msg_Out_High_Selected.png" : @"Msg_Out_Selected.png";
	else
		name = chosen ? @"Msg_In_High_Selected.png" : @"Msg_In_Selected.png";

	UIImage *image = [UIImage imageNamed:name];
	if (image == nil)
		return nil;
	int cap = (int)MIN(18.0f, MAX(1.0f, image.size.width / 2 - 1));
	return [image stretchableImageWithLeftCapWidth:cap topCapHeight:0];
}

- (void)setChips:(NSArray *)chips {
	[self setChips:chips animated:NO];
}

- (void)setChips:(NSArray *)chips animated:(BOOL)animated {
	NSMutableArray *usable = [[NSMutableArray alloc] init];
	for (id raw in chips){
		if (![raw isKindOfClass:[NSDictionary class]])
			continue;
		NSString *emoji = [(NSDictionary *)raw objectForKey:@"emoji"];
		if (![emoji isKindOfClass:[NSString class]] || emoji.length == 0)
			continue;
		[usable addObject:raw];
	}

	_chips = [usable copy];

	for (UIView *view in _chipViews)
		[view removeFromSuperview];
	[_chipViews removeAllObjects];

	if (usable.count == 0){
		self.hidden = YES;
		return;
	}

	UIColor *textColour = [[TGTheme shared] primaryTextColour];

	for (NSDictionary *chip in usable){
		NSString *emoji = [chip objectForKey:@"emoji"];
		NSInteger count = [[chip objectForKey:@"count"] integerValue];
		BOOL chosen = [[chip objectForKey:@"chosen"] boolValue];

		TGReactionChipView *view = [[TGReactionChipView alloc] initWithFrame:CGRectZero];
		view.emoji = emoji;
		view.chosen = chosen;
		view.plateView.image = [self plateChosen:chosen];
		view.emojiLabel.text = emoji;
		view.emojiLabel.textColor = textColour;
		view.countLabel.text = [NSString stringWithFormat:@"%d", (int)MAX(1, count)];
		view.countLabel.textColor = textColour;
		[view addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];

		[self addSubview:view];
		[_chipViews addObject:view];
	}

	self.hidden = NO;
	[self setNeedsLayout];
	[self layoutIfNeeded];

	if (animated){
		self.alpha = 0.0f;
		[UIView animateWithDuration:0.15 animations:^{
			self.alpha = 1.0f;
		}];
	}
	else
		self.alpha = 1.0f;
}

- (void)setOutgoing:(BOOL)outgoing {
	if (_outgoing == outgoing)
		return;
	_outgoing = outgoing;
	for (TGReactionChipView *view in _chipViews)
		view.plateView.image = [self plateChosen:view.chosen];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGFloat width = self.bounds.size.width;
	if (width < 40.0f)
		width = 40.0f;

	CGFloat x = 0;
	CGFloat y = 0;
	for (TGReactionChipView *view in _chipViews){
		NSInteger count = [view.countLabel.text integerValue];
		CGFloat chipWidth = [[self class] chipWidthForEmoji:view.emoji count:count];
		if (x > 0 && x + chipWidth > width){
			x = 0;
			y += kChipHeight + kChipRowGap;
		}
		view.frame = CGRectMake(x, y, chipWidth, kChipHeight);
		x += chipWidth + kChipGap;
	}
}

- (CGSize)sizeThatFits:(CGSize)size {
	CGFloat width = size.width > 40.0f ? size.width : self.bounds.size.width;
	return CGSizeMake(width, [[self class] heightForChips:_chips width:width]);
}

- (void)reloadChips {
	if (_chatId == 0 || _messageId == 0)
		return;

	__weak TGReactionChipsView *weakSelf = self;
	[[TGClient shared] reactionChipsForMessage:_messageId
	                                    inChat:_chatId
	                                completion:^(NSArray *chips)
	{
		TGReactionChipsView *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		[strongSelf setChips:chips animated:YES];
	}];
}

- (void)chipTapped:(TGReactionChipView *)view {
	NSString *emoji = view.emoji;
	if (emoji.length == 0)
		return;

	BOOL wasChosen = view.chosen;
	TGReactionChipTappedBlock tapped = self.onChipTapped;

	if (_chatId == 0 || _messageId == 0){
		if (tapped != nil)
			tapped(emoji, wasChosen);
		return;
	}

	__weak TGReactionChipsView *weakSelf = self;
	[[TGClient shared] toggleReaction:emoji
	                        onMessage:_messageId
	                           inChat:_chatId
	                              big:NO
	                       completion:^(BOOL nowChosen)
	{
		TGReactionChipsView *strongSelf = weakSelf;
		if (strongSelf != nil)
			[strongSelf reloadChips];
		if (tapped != nil)
			tapped(emoji, wasChosen);
	}];
}

@end

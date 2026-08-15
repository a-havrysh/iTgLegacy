#import "TGReactionPickerView.h"
#import "TGClient.h"
#import "TGClient+Reactions.h"
#import "TGClient+ChatList.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGImageDecode.h"
#import "TGActionSheet.h"
#import "UIImage+WebP.h"
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

static const CGFloat kReactionIconSide = 28.0f;

static const CGFloat kListRowHeight = 51.0f;
static const CGFloat kListAvatarSide = 40.0f;
static const CGFloat kListBarHeight = 44.0f;
static const CGFloat kListGroupHeight = 30.0f;
static const CGFloat kListGroupInset = 8.0f;
static const CGFloat kListSeparatorWidth = 2.0f;
static const NSInteger kListPageSize = 50;

static TGReactionPickerView *sOpenPicker = nil;
static NSTimeInterval sLastHideTime = 0;
static NSMutableDictionary *sReactionIcons = nil;

static UIImage *TGReactionScaledIcon(UIImage *image, CGFloat side) {
	if (image == nil || side < 1.0f)
		return nil;
	CGSize source = image.size;
	if (source.width < 1.0f || source.height < 1.0f)
		return nil;

	CGFloat factor = MIN(side / source.width, side / source.height);
	CGSize target = CGSizeMake(floorf(source.width * factor), floorf(source.height * factor));
	if (target.width < 1.0f || target.height < 1.0f)
		return nil;

	CGFloat scale = 1.0f;
	if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
		scale = [[UIScreen mainScreen] scale];

	UIGraphicsBeginImageContextWithOptions(target, NO, scale);
	[image drawInRect:CGRectMake(0, 0, target.width, target.height)];
	UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return result;
}

static void TGReactionIconForEmoji(NSString *emoji, CGFloat side, void (^completion)(UIImage *icon)) {
	if (completion == nil)
		return;
	if (emoji.length == 0){
		completion(nil);
		return;
	}
	if (sReactionIcons == nil)
		sReactionIcons = [[NSMutableDictionary alloc] init];

	id cached = [sReactionIcons objectForKey:emoji];
	if (cached != nil){
		completion([cached isKindOfClass:[UIImage class]] ? cached : nil);
		return;
	}

	[[TGClient shared] reactionIconPathForEmoji:emoji completion:^(NSString *path){
		if (path.length == 0){
			[sReactionIcons setObject:[NSNull null] forKey:emoji];
			completion(nil);
			return;
		}
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			UIImage *raw = TGDecodeThumbnail(path, side * 2.0f);
			if (raw == nil)
				raw = [UIImage convertFromWebP:path compressedData:NULL error:NULL];
			UIImage *scaled = TGReactionScaledIcon(raw, side);
			raw = nil;
			dispatch_async(dispatch_get_main_queue(), ^{
				[sReactionIcons setObject:(scaled != nil ? (id)scaled : (id)[NSNull null])
				                   forKey:emoji];
				completion(scaled);
			});
		});
	}];
}

static UIViewController *TGReactionOwningController(UIView *view) {
	UIResponder *responder = view;
	while (responder != nil){
		if ([responder isKindOfClass:[UIViewController class]])
			return (UIViewController *)responder;
		responder = [responder nextResponder];
	}
	return nil;
}

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
@property (nonatomic, strong) UIImageView *iconView;
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

		_iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_iconView.contentMode = UIViewContentModeScaleAspectFit;
		_iconView.hidden = YES;
		[self addSubview:_iconView];

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
	CGFloat iconSide = MIN(kStripEmojiFontSize + 4.0f, size.height - 10.0f);
	_iconView.frame = CGRectMake(floorf((size.width - iconSide) / 2),
	                             floorf((size.height - iconSide) / 2), iconSide, iconSide);
	[self bringSubviewToFront:_emojiLabel];
	[self bringSubviewToFront:_iconView];
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
	NSSet *_chosenEmoji;
	BOOL _canAddMore;
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

		if (reason.length > 0){
			[strongSelf setEmoji:nil reason:reason];
			return;
		}
		if (emoji.count == 0){
			[strongSelf setEmoji:nil reason:@"No reactions are allowed here"];
			return;
		}

		[strongSelf applyChatRestrictionsTo:emoji];
	}];
}

- (void)applyChatRestrictionsTo:(NSArray *)emoji {
	__weak TGReactionPickerView *weakSelf = self;
	[[TGClient shared] availableReactionsInChat:_chatId
	                                 completion:^(NSArray *emojis, BOOL allowsAll, NSInteger maxCount)
	{
		TGReactionPickerView *strongSelf = weakSelf;
		if (strongSelf == nil || strongSelf->_dismissed)
			return;

		NSArray *allowed = emoji;
		if (!allowsAll){
			NSMutableSet *permitted = [[NSMutableSet alloc] init];
			for (id raw in emojis){
				if ([raw isKindOfClass:[NSString class]] && [(NSString *)raw length] > 0)
					[permitted addObject:raw];
			}
			if (permitted.count == 0){
				[strongSelf setEmoji:nil reason:@"Reactions are switched off in this chat"];
				return;
			}
			NSMutableArray *filtered = [[NSMutableArray alloc] init];
			for (id raw in emoji){
				if ([permitted containsObject:raw])
					[filtered addObject:raw];
			}
			if (filtered.count == 0){
				[strongSelf setEmoji:nil reason:@"No reactions are allowed here"];
				return;
			}
			allowed = filtered;
		}

		[strongSelf applyUsageTo:allowed maxCount:maxCount];
	}];
}

- (void)applyUsageTo:(NSArray *)emoji maxCount:(NSInteger)maxCount {
	__weak TGReactionPickerView *weakSelf = self;
	[[TGClient shared] reactionUsageForMessage:_messageId
	                                    inChat:_chatId
	                                completion:^(NSArray *chosenEmoji,
	                                             NSInteger usedCount,
	                                             NSInteger limit,
	                                             BOOL canAddMore)
	{
		TGReactionPickerView *strongSelf = weakSelf;
		if (strongSelf == nil || strongSelf->_dismissed)
			return;

		NSInteger effective = maxCount > 0 ? maxCount : limit;
		BOOL room = canAddMore;
		if (effective > 0 && usedCount >= effective)
			room = NO;

		[strongSelf setEmoji:emoji reason:nil chosen:chosenEmoji canAddMore:room];
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
	[self setEmoji:emoji reason:reason chosen:nil canAddMore:YES];
}

- (void)setEmoji:(NSArray *)emoji
          reason:(NSString *)reason
          chosen:(NSArray *)chosen
      canAddMore:(BOOL)canAddMore
{
	if (_dismissed)
		return;

	NSMutableSet *chosenSet = [[NSMutableSet alloc] init];
	for (id raw in chosen){
		if ([raw isKindOfClass:[NSString class]] && [(NSString *)raw length] > 0)
			[chosenSet addObject:raw];
	}
	_chosenEmoji = chosenSet;
	_canAddMore = canAddMore;

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

		BOOL isChosen = [_chosenEmoji containsObject:value];
		if (isChosen){
			button.centerView.image = centerHighlighted;
			button.leftView.image = (i == 0) ? leftHighlighted : centerHighlighted;
			button.rightView.image = (i == usable.count - 1) ? rightHighlighted : centerHighlighted;
		}
		else if (!_canAddMore){
			button.enabled = NO;
			button.alpha = 0.45f;
		}

		__weak TGReactionStripButton *weakButton = button;
		TGReactionIconForEmoji(value, kReactionIconSide, ^(UIImage *icon){
			TGReactionStripButton *strongButton = weakButton;
			if (strongButton == nil || icon == nil)
				return;
			strongButton.iconView.image = icon;
			strongButton.iconView.hidden = NO;
			strongButton.emojiLabel.hidden = YES;
			[strongButton setNeedsLayout];
		});

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

#pragma mark - who reacted

@interface TGReactionListCell : UITableViewCell

@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *emojiLabel;

@end

@implementation TGReactionListCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (self == nil)
		return nil;

	BOOL flat = [[TGTheme shared] isFlat];
	if (!flat){
		UIImage *plate = TGReactionStretch(@"Cell102.png", 1);
		UIImage *platePressed = TGReactionStretch(@"CellHighlighted102.png", 1);
		if (plate != nil)
			self.backgroundView = [[UIImageView alloc] initWithImage:plate];
		if (platePressed != nil)
			self.selectedBackgroundView = [[UIImageView alloc] initWithImage:platePressed];
	}
	self.backgroundColor = [[TGTheme shared] listBackgroundColour];

	_avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(5, 5, kListAvatarSide, kListAvatarSide)];
	_avatarView.contentMode = UIViewContentModeScaleAspectFill;
	_avatarView.clipsToBounds = YES;
	_avatarView.layer.cornerRadius = 4.0f;
	[self.contentView addSubview:_avatarView];

	_nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_nameLabel.backgroundColor = [UIColor clearColor];
	_nameLabel.font = [UIFont systemFontOfSize:19];
	_nameLabel.textColor = flat ? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
	_nameLabel.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:_nameLabel];

	_emojiLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_emojiLabel.backgroundColor = [UIColor clearColor];
	_emojiLabel.font = [UIFont systemFontOfSize:20];
	_emojiLabel.textAlignment = NSTextAlignmentRight;
	[self.contentView addSubview:_emojiLabel];

	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGSize size = self.contentView.bounds.size;
	_avatarView.frame = CGRectMake(5, floorf((size.height - kListAvatarSide) / 2),
	                               kListAvatarSide, kListAvatarSide);
	_emojiLabel.frame = CGRectMake(size.width - 40, 0, 30, size.height);

	CGFloat nameWidth = MAX(10.0f, size.width - 54 - 46);
	CGFloat nameHeight = _nameLabel.font.lineHeight;
	_nameLabel.frame = CGRectMake(54, floorf((size.height - nameHeight) / 2) - 1, nameWidth, nameHeight);
}

@end

@interface TGReactionListViewController : UIViewController
		<UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate> {
	int64_t _chatId;
	int64_t _messageId;
	NSArray *_filters;
	NSMutableArray *_rows;
	NSMutableDictionary *_photos;
	NSMutableSet *_photosRequested;
	NSMutableArray *_groupButtons;
	NSMutableArray *_groupSeparators;
	NSString *_nextOffset;
	NSInteger _totalCount;
	NSInteger _selectedFilter;
	NSInteger _generation;
	BOOL _loading;
	BOOL _exhausted;
	BOOL _canDelete;
	BOOL _canReport;
	int64_t _actionSenderId;
	NSString *_actionName;
	UIView *_filterBar;
	UITableView *_tableView;
	UILabel *_statusLabel;
	UIActivityIndicatorView *_spinner;
}

- (id)initWithMessage:(int64_t)messageId chatId:(int64_t)chatId chips:(NSArray *)chips;

@end

@implementation TGReactionListViewController

- (id)initWithMessage:(int64_t)messageId chatId:(int64_t)chatId chips:(NSArray *)chips {
	self = [super init];
	if (self == nil)
		return nil;

	_messageId = messageId;
	_chatId = chatId;
	_rows = [[NSMutableArray alloc] init];
	_photos = [[NSMutableDictionary alloc] init];
	_photosRequested = [[NSMutableSet alloc] init];
	_nextOffset = nil;
	_selectedFilter = 0;

	NSMutableArray *filters = [[NSMutableArray alloc] init];
	[filters addObject:@""];
	for (id raw in chips){
		if (![raw isKindOfClass:[NSDictionary class]])
			continue;
		if ([[(NSDictionary *)raw objectForKey:@"custom"] boolValue])
			continue;
		NSString *emoji = [(NSDictionary *)raw objectForKey:@"emoji"];
		if ([emoji isKindOfClass:[NSString class]] && emoji.length > 0 &&
			![filters containsObject:emoji])
			[filters addObject:emoji];
	}
	_filters = filters;

	return self;
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Reactions";
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	UIButton *done = [TGIcons headerButtonWithTitle:@"Done" bold:YES
	                                         target:self action:@selector(closePressed)];
	if (done != nil)
		self.navigationItem.rightBarButtonItem =
				[[UIBarButtonItem alloc] initWithCustomView:done];
	else
		self.navigationItem.rightBarButtonItem =
				[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
				                                              target:self
				                                              action:@selector(closePressed)];

	CGRect bounds = self.view.bounds;
	CGFloat top = 0;

	if (_filters.count > 2){
		_filterBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, kListBarHeight)];
		_filterBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		UIImage *plate = TGReactionStretch(@"Footer.png", 1);
		if (plate != nil && ![[TGTheme shared] isFlat])
			_filterBar.backgroundColor = [UIColor colorWithPatternImage:plate];
		else
			_filterBar.backgroundColor = [[TGTheme shared] inputBarColour];
		[self.view addSubview:_filterBar];

		UIView *hairline = [[UIView alloc] initWithFrame:
				CGRectMake(0, kListBarHeight - 1, bounds.size.width, 1)];
		hairline.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		hairline.backgroundColor = [[TGTheme shared] separatorColour];
		[_filterBar addSubview:hairline];

		[self buildFilterButtons];
		top = kListBarHeight;
	}

	_tableView = [[UITableView alloc] initWithFrame:
			CGRectMake(0, top, bounds.size.width, bounds.size.height - top)
	                                          style:UITableViewStylePlain];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	_tableView.rowHeight = kListRowHeight;
	_tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	_tableView.separatorColor = [[TGTheme shared] separatorColour];
	_tableView.separatorStyle = [[TGTheme shared] isFlat]
			? UITableViewCellSeparatorStyleSingleLine
			: UITableViewCellSeparatorStyleNone;
	[self.view addSubview:_tableView];

	UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(longPressed:)];
	longPress.minimumPressDuration = 0.4;
	[_tableView addGestureRecognizer:longPress];

	_statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, top + 60, bounds.size.width, 20)];
	_statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_statusLabel.backgroundColor = [UIColor clearColor];
	_statusLabel.textAlignment = NSTextAlignmentCenter;
	_statusLabel.font = [UIFont systemFontOfSize:14];
	_statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	_statusLabel.hidden = YES;
	[self.view addSubview:_statusLabel];

	_spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	_spinner.center = CGPointMake(bounds.size.width / 2, top + 60);
	_spinner.autoresizingMask =
			UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	[self.view addSubview:_spinner];

	[self loadPermissions];
	[self reload];
}

- (void)closePressed {
	if ([self respondsToSelector:@selector(dismissViewControllerAnimated:completion:)])
		[self dismissViewControllerAnimated:YES completion:nil];
	else
		[self dismissModalViewControllerAnimated:YES];
}

#pragma mark filters

- (NSString *)currentFilter {
	if (_selectedFilter <= 0 || _selectedFilter >= (NSInteger)_filters.count)
		return nil;
	NSString *emoji = [_filters objectAtIndex:(NSUInteger)_selectedFilter];
	return emoji.length > 0 ? emoji : nil;
}

- (void)buildFilterButtons {
	_groupButtons = [[NSMutableArray alloc] init];
	_groupSeparators = [[NSMutableArray alloc] init];

	CGFloat width = self.view.bounds.size.width - kListGroupInset * 2;
	CGFloat originY = floorf((kListBarHeight - kListGroupHeight) / 2);

	UIView *group = [[UIView alloc] initWithFrame:
			CGRectMake(kListGroupInset, originY, width, kListGroupHeight)];
	group.autoresizingMask = UIViewAutoresizingFlexibleWidth;

	NSInteger count = (NSInteger)_filters.count;
	CGFloat usable = width - kListSeparatorWidth * (count - 1);
	CGFloat buttonWidth = floorf(usable / MAX(1, count));

	UIColor *shadowColour = [UIColor colorWithRed:0x0e / 255.0f green:0x28 / 255.0f
	                                         blue:0x4d / 255.0f alpha:0.4f];

	CGFloat currentX = 0;
	for (NSInteger i = 0; i < count; i++){
		CGFloat thisWidth = (i == count - 1) ? (width - currentX) : buttonWidth;
		NSString *value = [_filters objectAtIndex:(NSUInteger)i];

		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.exclusiveTouch = YES;
		button.frame = CGRectMake(currentX, 0, thisWidth, kListGroupHeight);
		button.tag = i;
		[button setTitle:(value.length > 0 ? value : @"All") forState:UIControlStateNormal];
		button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleShadowColor:shadowColour forState:UIControlStateNormal];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		button.adjustsImageWhenHighlighted = NO;
		button.adjustsImageWhenDisabled = NO;
		[button addTarget:self action:@selector(filterPressed:)
		 forControlEvents:UIControlEventTouchDown];
		[group addSubview:button];
		[_groupButtons addObject:button];

		currentX += thisWidth;

		if (i + 1 < count){
			UIView *separator = [[UIView alloc] initWithFrame:
					CGRectMake(currentX, 0, kListSeparatorWidth, kListGroupHeight)];
			UIImage *art = TGReactionStretch(@"ButtonGroupDivider.png", 6);
			if (art != nil){
				UIImageView *layer = [[UIImageView alloc] initWithImage:art];
				layer.frame = separator.bounds;
				[separator addSubview:layer];
			}
			[group addSubview:separator];
			[_groupSeparators addObject:separator];
			currentX += kListSeparatorWidth;
		}
	}

	[_filterBar addSubview:group];
	[self updateFilterButtons];
}

- (void)updateFilterButtons {
	NSUInteger count = _groupButtons.count;
	for (NSUInteger i = 0; i < count; i++){
		UIButton *button = [_groupButtons objectAtIndex:i];
		NSString *normalName = @"ButtonGroupCenter.png";
		NSString *highlightedName = @"ButtonGroupCenter_Highlighted.png";
		int leftCap = 1;
		if (i == 0){
			normalName = @"ButtonGroupLeft.png";
			highlightedName = @"ButtonGroupLeft_Highlighted.png";
			leftCap = 8;
		}
		else if (i == count - 1){
			normalName = @"ButtonGroupRight.png";
			highlightedName = @"ButtonGroupRight_Highlighted.png";
		}

		UIImage *normal = TGReactionStretch(normalName, leftCap);
		UIImage *highlighted = TGReactionStretch(highlightedName, leftCap);
		UIImage *shown = ((NSInteger)i == _selectedFilter) ? highlighted : normal;
		[button setBackgroundImage:shown forState:UIControlStateNormal];
		[button setBackgroundImage:shown forState:UIControlStateHighlighted];
		if (normal == nil)
			button.backgroundColor = ((NSInteger)i == _selectedFilter)
					? [[TGTheme shared] accentColour]
					: [UIColor colorWithWhite:0.62f alpha:1.0f];
	}
}

- (void)filterPressed:(UIButton *)button {
	if (button.tag == _selectedFilter)
		return;
	_selectedFilter = button.tag;
	[self updateFilterButtons];
	[self reload];
}

#pragma mark loading

- (void)loadPermissions {
	__weak TGReactionListViewController *weakSelf = self;
	[[TGClient shared] reactionPermissionsForMessage:_messageId
	                                          inChat:_chatId
	                                      completion:^(BOOL canDelete, BOOL canReport)
	{
		TGReactionListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_canDelete = canDelete;
		strongSelf->_canReport = canReport;
	}];
}

- (void)reload {
	_generation++;
	[_rows removeAllObjects];
	_nextOffset = nil;
	_exhausted = NO;
	_totalCount = 0;
	[_tableView reloadData];
	[self loadMore];
}

- (void)loadMore {
	if (_loading || _exhausted)
		return;
	_loading = YES;

	if (_rows.count == 0){
		_statusLabel.hidden = YES;
		[_spinner startAnimating];
	}

	NSInteger generation = _generation;
	__weak TGReactionListViewController *weakSelf = self;
	[[TGClient shared] addedReactionsForMessage:_messageId
	                                     inChat:_chatId
	                                      emoji:[self currentFilter]
	                                     offset:_nextOffset
	                                      limit:kListPageSize
	                                 completion:^(NSArray *reactors,
	                                              NSString *nextOffset,
	                                              NSInteger totalCount)
	{
		TGReactionListViewController *strongSelf = weakSelf;
		if (strongSelf == nil || strongSelf->_generation != generation)
			return;

		strongSelf->_loading = NO;
		[strongSelf->_spinner stopAnimating];

		for (id raw in reactors){
			if ([raw isKindOfClass:[NSDictionary class]])
				[strongSelf->_rows addObject:raw];
		}
		if (totalCount > 0)
			strongSelf->_totalCount = totalCount;

		strongSelf->_nextOffset = [nextOffset isKindOfClass:[NSString class]] ? nextOffset : nil;
		if (strongSelf->_nextOffset.length == 0 || reactors.count == 0)
			strongSelf->_exhausted = YES;

		[strongSelf updateTitle];
		[strongSelf->_tableView reloadData];
		[strongSelf updateStatus];
		[strongSelf fetchPhotos];
	}];
}

- (void)updateTitle {
	NSInteger shown = _totalCount > 0 ? _totalCount : (NSInteger)_rows.count;
	if (shown <= 0)
		self.title = @"Reactions";
	else if (shown == 1)
		self.title = @"1 Reaction";
	else
		self.title = [NSString stringWithFormat:@"%d Reactions", (int)shown];
}

- (void)updateStatus {
	if (_rows.count > 0){
		_statusLabel.hidden = YES;
		return;
	}
	_statusLabel.text = @"Nobody has reacted yet";
	_statusLabel.hidden = NO;
}

- (void)fetchPhotos {
	__weak TGReactionListViewController *weakSelf = self;
	for (NSDictionary *row in [_rows copy]){
		int64_t senderId = [[row objectForKey:@"senderId"] longLongValue];
		if (senderId == 0)
			continue;
		NSNumber *key = [NSNumber numberWithLongLong:senderId];
		if ([_photos objectForKey:key] != nil || [_photosRequested containsObject:key])
			continue;

		NSNumber *fileId = senderId > 0
				? [[TGClient shared] photoFileIdForUserId:senderId]
				: [[TGClient shared] photoFileIdForChat:senderId];
		if (![fileId isKindOfClass:[NSNumber class]])
			continue;
		[_photosRequested addObject:key];

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			if (path.length == 0){
				TGReactionListViewController *me = weakSelf;
				if (me != nil)
					[me->_photosRequested removeObject:key];
				return;
			}
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
				UIImage *thumb = TGDecodeSquareThumbnail(path, kListAvatarSide);
				dispatch_async(dispatch_get_main_queue(), ^{
					TGReactionListViewController *me = weakSelf;
					if (me == nil || thumb == nil)
						return;
					[me->_photos setObject:thumb forKey:key];
					[me reloadSoon];
				});
			});
		}];
	}
}

- (void)reloadSoon {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
	                                         selector:@selector(reloadNow)
	                                           object:nil];
	[self performSelector:@selector(reloadNow) withObject:nil afterDelay:0.15f];
}

- (void)reloadNow {
	[_tableView reloadData];
}

#pragma mark table

- (NSDictionary *)rowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)_rows.count)
		return nil;
	return [_rows objectAtIndex:(NSUInteger)indexPath.row];
}

- (NSString *)nameForRow:(NSDictionary *)row {
	NSString *name = [row objectForKey:@"name"];
	if ([name isKindOfClass:[NSString class]] && name.length > 0)
		return name;

	int64_t senderId = [[row objectForKey:@"senderId"] longLongValue];
	if (senderId > 0){
		NSString *known = [[TGClient shared] nameForUserId:senderId];
		if (known.length > 0)
			return known;
	}
	return @"Unknown";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)_rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	static NSString *identifier = @"TGReactionListCell";
	TGReactionListCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (cell == nil)
		cell = [[TGReactionListCell alloc] initWithStyle:UITableViewCellStyleDefault
		                                 reuseIdentifier:identifier];

	NSDictionary *row = [self rowAtIndexPath:indexPath];
	NSString *name = [self nameForRow:row];
	cell.nameLabel.text = name;

	NSString *emoji = [row objectForKey:@"emoji"];
	cell.emojiLabel.text = [emoji isKindOfClass:[NSString class]] ? emoji : @"";

	int64_t senderId = [[row objectForKey:@"senderId"] longLongValue];
	NSNumber *key = [NSNumber numberWithLongLong:senderId];
	UIImage *photo = [_photos objectForKey:key];
	if (photo == nil)
		photo = [TGIcons avatarWithInitials:[[name substringToIndex:1] uppercaseString]
		                               size:kListAvatarSide
		                           colourId:senderId];
	cell.avatarView.image = photo;
	[cell setNeedsLayout];

	if (indexPath.row + 5 >= (NSInteger)_rows.count)
		[self loadMore];

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)longPressed:(UILongPressGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateBegan)
		return;
	if (!_canDelete && !_canReport)
		return;

	CGPoint point = [recognizer locationInView:_tableView];
	NSIndexPath *indexPath = [_tableView indexPathForRowAtPoint:point];
	NSDictionary *row = [self rowAtIndexPath:indexPath];
	if (row == nil)
		return;

	int64_t senderId = [[row objectForKey:@"senderId"] longLongValue];
	if (senderId == 0)
		return;

	_actionSenderId = senderId;
	_actionName = [self nameForRow:row];

	NSMutableArray *actions = [[NSMutableArray alloc] init];
	if (_canDelete){
		[actions addObject:[[TGActionSheetAction alloc]
				initWithTitle:@"Delete Reactions" action:@"delete"
				         type:TGActionSheetActionTypeDestructive]];
		[actions addObject:[[TGActionSheetAction alloc]
				initWithTitle:@"Delete All From This User" action:@"deleteAll"
				         type:TGActionSheetActionTypeDestructive]];
	}
	if (_canReport){
		[actions addObject:[[TGActionSheetAction alloc]
				initWithTitle:@"Report" action:@"report"]];
	}
	[actions addObject:[[TGActionSheetAction alloc]
			initWithTitle:@"Cancel" action:@"cancel" type:TGActionSheetActionTypeCancel]];

	__weak TGReactionListViewController *weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:_actionName
	                                                   actions:actions
	                                               actionBlock:^(id target, NSString *action)
	{
		TGReactionListViewController *strongSelf = weakSelf;
		if (strongSelf != nil)
			[strongSelf performModerationAction:action];
	} target:self];
	[sheet showInView:self.view];
}

- (void)performModerationAction:(NSString *)action {
	int64_t senderId = _actionSenderId;
	if (senderId == 0)
		return;

	if ([action isEqualToString:@"delete"]){
		[[TGClient shared] deleteReactionsFromSender:senderId
		                                   onMessage:_messageId
		                                      inChat:_chatId];
		[self removeRowsFromSender:senderId];
	}
	else if ([action isEqualToString:@"deleteAll"]){
		[[TGClient shared] deleteAllRecentReactionsFromSender:senderId inChat:_chatId];
		[self removeRowsFromSender:senderId];
	}
	else if ([action isEqualToString:@"report"]){
		[[TGClient shared] reportReactionsFromSender:senderId
		                                   onMessage:_messageId
		                                      inChat:_chatId];
		[self removeRowsFromSender:senderId];
	}
}

- (void)removeRowsFromSender:(int64_t)senderId {
	NSMutableArray *kept = [[NSMutableArray alloc] init];
	for (NSDictionary *row in _rows){
		if ([[row objectForKey:@"senderId"] longLongValue] != senderId)
			[kept addObject:row];
	}
	NSInteger removed = (NSInteger)_rows.count - (NSInteger)kept.count;
	[_rows setArray:kept];
	if (_totalCount >= removed)
		_totalCount -= removed;
	[self updateTitle];
	[_tableView reloadData];
	[self updateStatus];
}

@end

#pragma mark - one chip

@interface TGReactionChipView : UIControl

@property (nonatomic, strong) UIImageView *plateView;
@property (nonatomic, strong) UILabel *emojiLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, copy) NSString *emoji;
@property (nonatomic, assign) BOOL chosen;
@property (nonatomic, assign) BOOL custom;

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

		_iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_iconView.contentMode = UIViewContentModeScaleAspectFit;
		_iconView.hidden = YES;
		[self addSubview:_iconView];

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
	CGFloat iconSide = MIN(emojiWidth, size.height - 4.0f);
	_iconView.frame = CGRectMake(kChipPadding + floorf((emojiWidth - iconSide) / 2),
	                             floorf((size.height - iconSide) / 2), iconSide, iconSide);

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
	BOOL _watching;
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
		BOOL custom = [[chip objectForKey:@"custom"] boolValue];

		TGReactionChipView *view = [[TGReactionChipView alloc] initWithFrame:CGRectZero];
		view.emoji = emoji;
		view.chosen = chosen;
		view.custom = custom;
		view.plateView.image = [self plateChosen:chosen];
		view.emojiLabel.text = emoji;
		view.emojiLabel.textColor = textColour;
		view.countLabel.text = [NSString stringWithFormat:@"%d", (int)MAX(1, count)];
		view.countLabel.textColor = textColour;
		[view addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];

		if (!custom){
			__weak TGReactionChipView *weakChip = view;
			TGReactionIconForEmoji(emoji, kReactionIconSide, ^(UIImage *icon){
				TGReactionChipView *strongChip = weakChip;
				if (strongChip == nil || icon == nil)
					return;
				strongChip.iconView.image = icon;
				strongChip.iconView.hidden = NO;
				strongChip.emojiLabel.hidden = YES;
				[strongChip setNeedsLayout];
			});
		}

		UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
				initWithTarget:self action:@selector(chipLongPressed:)];
		longPress.minimumPressDuration = 0.4;
		[view addGestureRecognizer:longPress];

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

- (void)chipLongPressed:(UILongPressGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateBegan)
		return;
	[self showReactionList];
}

- (void)showReactionList {
	if (_chatId == 0 || _messageId == 0)
		return;

	UIViewController *owner = TGReactionOwningController(self);
	if (owner == nil)
		return;

	TGReactionListViewController *list = [[TGReactionListViewController alloc]
			initWithMessage:_messageId chatId:_chatId chips:_chips];
	UINavigationController *navigation =
			[[UINavigationController alloc] initWithRootViewController:list];
	[[TGTheme shared] styleNavigationBar:navigation.navigationBar];

	if ([owner respondsToSelector:@selector(presentViewController:animated:completion:)])
		[owner presentViewController:navigation animated:YES completion:nil];
	else
		[owner presentModalViewController:navigation animated:YES];
}

- (void)startWatching {
	if (_watching || _chatId == 0 || _messageId == 0 || self.window == nil)
		return;
	_watching = YES;

	__weak TGReactionChipsView *weakSelf = self;
	[[TGClient shared] watchReactionsForMessage:_messageId
	                                     inChat:_chatId
	                                   onChange:^(NSArray *chips)
	{
		TGReactionChipsView *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		[strongSelf setChips:chips animated:YES];
	}];
}

- (void)stopWatching {
	if (!_watching)
		return;
	_watching = NO;
	[[TGClient shared] unwatchReactionsForMessage:_messageId inChat:_chatId];
}

- (void)setChatId:(int64_t)chatId {
	if (_chatId == chatId)
		return;
	[self stopWatching];
	_chatId = chatId;
	[self startWatching];
}

- (void)setMessageId:(int64_t)messageId {
	if (_messageId == messageId)
		return;
	[self stopWatching];
	_messageId = messageId;
	[self startWatching];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window == nil)
		[self stopWatching];
	else
		[self startWatching];
}

- (void)dealloc {
	[self stopWatching];
}

- (void)chipTapped:(TGReactionChipView *)view {
	NSString *emoji = view.emoji;
	if (emoji.length == 0)
		return;

	if (view.custom){
		[self showReactionList];
		return;
	}

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

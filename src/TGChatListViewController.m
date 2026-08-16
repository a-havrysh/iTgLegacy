#import "TGChatListViewController.h"
#import "RootViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGClient+ChatList.h"
#import "TGClient+Notifications.h"
#import "TGClient+Messages.h"
#import "TGClient+Stories.h"
#import "TGClient+Files.h"
#import "TGClient+SecretChats.h"
#import "TGClient+Privacy.h"
#import "TGFoldersViewController.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGContactsViewController.h"
#import "TGTopicsViewController.h"
#import "TGPopupMenu.h"
#import "TGSnackbar.h"
#import "TGSearchViewController.h"
#import "TGSwipeGestureRecognizer.h"
#import "TGEmoji.h"
#import "TGActionsMenu.h"
#import "TGStoriesViewController.h"
#import "UIView+SafeTint.h"
#import "TGDiskCache.h"
#import "AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import "TGAlertView.h"

static const CGFloat kRowHeight = 73.0f;
static const CGFloat kAvatar = 56.0f;
static const CGFloat kAvatarLeft = 8.0f;
static const CGFloat kTextLeft = 73.0f;

static const CGFloat kSwipeButtonHeight = 31.0f;
static const CGFloat kSwipeButtonMinWidth = 61.0f;
static const CGFloat kSwipeEdgeDistance = 6.0f;
static const CGFloat kSwipeButtonTop = 20.0f;
static const CGFloat kSwipeButtonGap = 6.0f;

static UIColor *TGChatListTitleColour(void) {
	static UIColor *colour = nil;
	if (!colour)
		colour = [UIColor colorWithRed:0x11 / 255.0f green:0x11 / 255.0f
								  blue:0x11 / 255.0f alpha:1.0f];
	return colour;
}

static UIColor *TGChatListMessageColour(void) {
	static UIColor *colour = nil;
	if (!colour)
		colour = [UIColor colorWithRed:0x88 / 255.0f green:0x88 / 255.0f
								  blue:0x88 / 255.0f alpha:1.0f];
	return colour;
}

static UIColor *TGChatListActionColour(void) {
	static UIColor *colour = nil;
	if (!colour)
		colour = [UIColor colorWithRed:0x53 / 255.0f green:0x6c / 255.0f
								  blue:0x8c / 255.0f alpha:1.0f];
	return colour;
}

static UIColor *TGChatListAuthorColour(void) {
	static UIColor *colour = nil;
	if (!colour)
		colour = [UIColor colorWithRed:0x34 / 255.0f green:0x5f / 255.0f
								  blue:0x8f / 255.0f alpha:1.0f];
	return colour;
}

static NSDictionary *TGReplyDictionary(id value) {
	return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : nil;
}

static NSArray *TGReplyArray(id value) {
	return [value isKindOfClass:[NSArray class]] ? (NSArray *)value : nil;
}

static NSString *TGReplyString(id value) {
	return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

static NSArray *TGChatRows(id value) {
	NSArray *raw = TGReplyArray(value);
	if (!raw.count)
		return @[];
	NSMutableArray *rows = [NSMutableArray arrayWithCapacity:raw.count];
	for (id entry in raw){
		NSDictionary *chat = TGReplyDictionary(entry);
		if (chat && [chat[@"id"] longLongValue])
			[rows addObject:chat];
	}
	return rows;
}

static UIImage *TGDialogListBadgeImage(BOOL highlighted) {
	static UIImage *normal = nil, *bright = nil;
	if (!normal){
		UIImage *raw = [UIImage imageNamed:@"DialogListUnreadBadge.png"];
		normal = [raw stretchableImageWithLeftCapWidth:(int)(raw.size.width / 2)
										  topCapHeight:(int)(raw.size.height / 2)];
		UIImage *rawHigh = [UIImage imageNamed:@"DialogListUnreadBadge_Highlighted.png"];
		bright = [rawHigh stretchableImageWithLeftCapWidth:(int)(rawHigh.size.width / 2)
											  topCapHeight:(int)(rawHigh.size.height / 2)];
	}
	return highlighted ? bright : normal;
}

#pragma mark - chat id picker

@interface TGChatIdPickerViewController : UITableViewController
@property (nonatomic, strong) NSArray *chatIds;
@property (nonatomic, strong) NSDictionary *titles;
@property (nonatomic, copy) NSString *prompt;
@property (nonatomic, copy) NSString *confirmTitle;
@property (nonatomic, copy) void (^onConfirm)(NSArray *chatIds);
@end

@implementation TGChatIdPickerViewController {
	NSMutableSet *_selected;
}

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	_selected = [NSMutableSet setWithArray:(self.chatIds ?: @[])];

	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	UIButton *done = [TGIcons headerButtonWithTitle:(self.confirmTitle.length ? self.confirmTitle : @"Add")
											   bold:YES target:self action:@selector(confirmTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:done];

	if (!self.titles.count && self.chatIds.count){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] titlesForChatIds:self.chatIds completion:^(NSDictionary *reply){
			TGChatIdPickerViewController *me = weakSelf;
			if (!me)
				return;
			me.titles = TGReplyDictionary(reply) ?: @{};
			[me.tableView reloadData];
		}];
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.prompt.length ? self.prompt : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.chatIds.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGChatIdPickerCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:reuse];

	NSNumber *key = self.chatIds[indexPath.row];
	NSString *title = TGReplyString(self.titles[key]);
	if (!title.length)
		title = [[TGClient shared] cachedTitleForChatId:[key longLongValue]];
	cell.textLabel.text = title.length ? title : @"Chat";
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.accessoryType = [_selected containsObject:key]
			? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSNumber *key = self.chatIds[indexPath.row];
	if ([_selected containsObject:key])
		[_selected removeObject:key];
	else
		[_selected addObject:key];
	[tableView reloadRowsAtIndexPaths:@[indexPath]
					 withRowAnimation:UITableViewRowAnimationNone];
}

- (void)confirmTapped {
	NSMutableArray *picked = [NSMutableArray array];
	for (NSNumber *key in (self.chatIds ?: @[]))
		if ([_selected containsObject:key])
			[picked addObject:key];
	void (^confirm)(NSArray *) = self.onConfirm;
	[self.navigationController popViewControllerAnimated:YES];
	if (confirm)
		confirm(picked);
}

@end

#pragma mark - cell

@interface TGChatCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) TGEmojiLabel *titleLabel;
@property (nonatomic, strong) TGEmojiLabel *previewLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *draftLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *badgeBackground;
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, strong) UIView *onlineDot;
@property (nonatomic, strong) UIImageView *tick;   // your own last message
@property (nonatomic, strong) UIImageView *pin;   // pinned to the top
@property (nonatomic, strong) UIImageView *arrow;
@property (nonatomic, strong) UIImageView *muteIcon;
@property (nonatomic, strong) UIImageView *groupIcon;

@property (nonatomic, assign) long long chatId;

@property (nonatomic, strong) NSArray *swipeActions;
@property (nonatomic, copy) void (^onSwipeOpen)(void);
@property (nonatomic, copy) void (^onSwipeAction)(NSString *kind);
@property (nonatomic, readonly) BOOL swipeActionsVisible;

- (void)setSwipeActionsVisible:(BOOL)visible animated:(BOOL)animated;
- (void)setDateText:(NSString *)text suffix:(NSString *)suffix bold:(BOOL)bold;
@end

@implementation TGChatCell {
	NSMutableArray *_swipeButtons;
	BOOL _swipeActionsVisible;
	CGFloat _dateWidth;
	NSString *_dateMain;
	NSString *_dateSuffix;
	BOOL _dateBold;
}

static UIImage *TGSwipePlateImage(BOOL destructive, BOOL highlighted) {
	static UIImage *cache[4] = {nil, nil, nil, nil};
	NSInteger slot = (destructive ? 2 : 0) + (highlighted ? 1 : 0);
	if (cache[slot])
		return cache[slot];

	NSString *name = destructive ? @"MenuRedButton" : @"GroupedActionButton";
	if (highlighted)
		name = [name stringByAppendingString:@"_Highlighted"];
	UIImage *raw = [UIImage imageNamed:[name stringByAppendingString:@".png"]];
	if (!raw)
		return nil;
	cache[slot] = [raw stretchableImageWithLeftCapWidth:(int)(raw.size.width / 2)
										   topCapHeight:(int)(raw.size.height / 2)];
	return cache[slot];
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	[self buildAvatar];
	[self buildTextLabels];
	[self buildBadge];
	[self buildRowIcons];
	[self buildPlates];

	_swipeButtons = [NSMutableArray array];
	TGSwipeGestureRecognizer *swipe = [[TGSwipeGestureRecognizer alloc]
			initWithTarget:self action:@selector(swipeRecognised:)];
	[self addGestureRecognizer:swipe];

	return self;
}

- (void)buildAvatar {
	self.avatar = [[UIImageView alloc] initWithFrame:CGRectMake(kAvatarLeft, 8, kAvatar, kAvatar)];
	self.avatar.layer.cornerRadius = 5.0f;
	self.avatar.clipsToBounds = YES;
	self.avatar.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
	self.avatar.contentMode = UIViewContentModeScaleAspectFill;
	[self.contentView addSubview:self.avatar];
}

- (void)buildTextLabels {
	self.titleLabel = [[TGEmojiLabel alloc] init];
	self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.titleLabel.textColor = TGChatListTitleColour();
	self.titleLabel.highlightedTextColor = [UIColor whiteColor];
	// A long name has to stop at the date rather than slide under it.
	self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.titleLabel];

	self.previewLabel = [[TGEmojiLabel alloc] init];
	self.previewLabel.font = [UIFont systemFontOfSize:14];
	self.previewLabel.textColor = TGChatListMessageColour();
	self.previewLabel.highlightedTextColor = [UIColor whiteColor];
	self.previewLabel.numberOfLines = 2;
	self.previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.previewLabel];

	self.authorLabel = [[UILabel alloc] init];
	self.authorLabel.font = [UIFont boldSystemFontOfSize:14];
	self.authorLabel.backgroundColor = [UIColor clearColor];
	self.authorLabel.textColor = TGChatListAuthorColour();
	self.authorLabel.highlightedTextColor = [UIColor whiteColor];
	self.authorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	self.authorLabel.hidden = YES;
	[self.contentView addSubview:self.authorLabel];

	self.draftLabel = [[UILabel alloc] init];
	self.draftLabel.font = [UIFont systemFontOfSize:14];
	self.draftLabel.backgroundColor = [UIColor clearColor];
	self.draftLabel.textColor = [UIColor colorWithRed:0xC4 / 255.0f green:0x2B / 255.0f
												 blue:0x1E / 255.0f alpha:1.0f];
	self.draftLabel.text = @"Draft:";
	self.draftLabel.hidden = YES;
	[self.contentView addSubview:self.draftLabel];

	self.dateLabel = [[UILabel alloc] init];
	self.dateLabel.font = [UIFont systemFontOfSize:13];
	self.dateLabel.textColor = [UIColor colorWithRed:0x33 / 255.0f green:0x7a / 255.0f blue:0xcc / 255.0f alpha:1.0f];
	self.dateLabel.textAlignment = NSTextAlignmentRight;
	self.dateLabel.backgroundColor = [UIColor clearColor];
	self.dateLabel.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:self.dateLabel];
}

- (void)buildBadge {
	self.badgeBackground = [[UIImageView alloc] initWithImage:TGDialogListBadgeImage(NO)
											 highlightedImage:TGDialogListBadgeImage(YES)];
	self.badgeBackground.hidden = YES;
	[self.contentView addSubview:self.badgeBackground];

	self.badge = [[UILabel alloc] init];
	self.badge.font = [UIFont boldSystemFontOfSize:14];
	self.badge.textColor = [UIColor whiteColor];
	self.badge.backgroundColor = [UIColor clearColor];
	self.badge.shadowColor = [UIColor colorWithRed:0x80 / 255.0f green:0x91 / 255.0f blue:0xa6 / 255.0f alpha:1.0f];
	self.badge.shadowOffset = CGSizeMake(0, -1);
	self.badge.highlightedTextColor = [UIColor colorWithRed:0x23 / 255.0f green:0x71 / 255.0f
													   blue:0xc2 / 255.0f alpha:1.0f];
	self.badge.textAlignment = NSTextAlignmentCenter;
	self.badge.hidden = YES;
	[self.contentView addSubview:self.badge];
}

/// The dot sits half off the avatar, so it needs a ring of the row's own
/// colour to stay legible against a photo.
- (void)buildRowIcons {
	self.onlineDot = [[UIView alloc] initWithFrame:
			CGRectMake(kAvatarLeft + kAvatar - 14, 8 + kAvatar - 14, 14, 14)];
	self.onlineDot.backgroundColor = [[TGTheme shared] onlineColour];
	self.onlineDot.layer.cornerRadius = 7;
	self.onlineDot.layer.borderWidth = 2;
	self.onlineDot.hidden = YES;
	[self.contentView addSubview:self.onlineDot];

	self.tick = [[UIImageView alloc] init];
	self.tick.hidden = YES;
	[self.contentView addSubview:self.tick];

	// A pinned chat says so where the unread count would be, and gives the
	// place up as soon as there is a count to show.
	self.pin = [[UIImageView alloc] init];
	self.pin.contentMode = UIViewContentModeScaleAspectFit;
	self.pin.hidden = YES;
	[self.contentView addSubview:self.pin];

	self.muteIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"DialogList_Muted.png"]];
	self.muteIcon.hidden = YES;
	[self.contentView addSubview:self.muteIcon];

	self.groupIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"DialogListGroupChatIcon.png"]];
	self.groupIcon.hidden = YES;
	[self.contentView addSubview:self.groupIcon];

	self.arrow = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"DialogListArrow.png"]
								   highlightedImage:[UIImage imageNamed:@"DialogListArrow_Highlighted.png"]];
	[self.contentView addSubview:self.arrow];
}

- (void)buildPlates {
	UIImage *plate = [[UIImage imageNamed:@"DialogListCell.png"]
			stretchableImageWithLeftCapWidth:1 topCapHeight:0];
	UIImage *platePressed = [[UIImage imageNamed:@"DialogListCellHighlighted.png"]
			stretchableImageWithLeftCapWidth:1 topCapHeight:0];
	self.backgroundView = [[UIImageView alloc] initWithImage:plate];
	self.selectedBackgroundView = [[UIImageView alloc] initWithImage:platePressed];

	self.accessoryType = UITableViewCellAccessoryNone;
	self.selectionStyle = UITableViewCellSelectionStyleBlue;
}

#pragma mark - swipe actions

- (BOOL)swipeActionsVisible {
	return _swipeActionsVisible;
}

- (void)swipeRecognised:(TGSwipeGestureRecognizer *)recogniser {
	if (recogniser.state != UIGestureRecognizerStateRecognized || self.editing)
		return;
	if (!self.swipeActions.count || _swipeActionsVisible)
		return;

	[self setSelected:NO];
	[self setHighlighted:NO];
	if (self.onSwipeOpen)
		self.onSwipeOpen();
	[self setSwipeActionsVisible:YES animated:YES];
}

- (void)buildSwipeButtons {
	for (UIButton *button in _swipeButtons)
		[button removeFromSuperview];
	[_swipeButtons removeAllObjects];

	UIFont *font = [UIFont boldSystemFontOfSize:13];
	for (NSUInteger i = 0; i < self.swipeActions.count; i++){
		NSDictionary *action = self.swipeActions[i];
		BOOL destructive = [action[@"destructive"] boolValue];
		NSString *title = action[@"title"] ?: @"";

		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.exclusiveTouch = YES;
		button.adjustsImageWhenHighlighted = NO;
		button.titleLabel.font = font;
		[button setTitle:title forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];

		UIImage *plate = TGSwipePlateImage(destructive, NO);
		UIImage *pressed = TGSwipePlateImage(destructive, YES);
		if (plate){
			[button setBackgroundImage:plate forState:UIControlStateNormal];
			[button setBackgroundImage:(pressed ?: plate) forState:UIControlStateHighlighted];
			if (!destructive){
				[button setTitleColor:[UIColor colorWithRed:0x4a / 255.0f green:0x65 / 255.0f
													   blue:0x87 / 255.0f alpha:1.0f]
							 forState:UIControlStateNormal];
				[button setTitleShadowColor:[UIColor colorWithWhite:1.0f alpha:0.45f]
								   forState:UIControlStateNormal];
				button.titleLabel.shadowOffset = CGSizeMake(0, 1);
			} else {
				[button setTitleShadowColor:[UIColor colorWithRed:0xa3 / 255.0f
															green:0x0f / 255.0f
															 blue:0x0a / 255.0f alpha:0.2f]
								   forState:UIControlStateNormal];
				button.titleLabel.shadowOffset = CGSizeMake(0, -1);
			}
		} else {
			button.backgroundColor = destructive
					? [UIColor colorWithRed:0xC4 / 255.0f green:0x2B / 255.0f
									   blue:0x1E / 255.0f alpha:1.0f]
					: [UIColor colorWithRed:0x8E / 255.0f green:0x9C / 255.0f
									   blue:0xAE / 255.0f alpha:1.0f];
			button.layer.cornerRadius = 4;
		}

		button.tag = (NSInteger)i;
		[button addTarget:self action:@selector(swipeButtonPressed:)
		 forControlEvents:UIControlEventTouchUpInside];
		[self.contentView addSubview:button];
		[_swipeButtons addObject:button];
	}
}

- (CGFloat)swipeButtonWidthForIndex:(NSUInteger)index {
	if (index >= _swipeButtons.count)
		return kSwipeButtonMinWidth;
	UIButton *button = _swipeButtons[index];
	NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
	CGFloat text = [title sizeWithFont:button.titleLabel.font].width;
	return MAX(kSwipeButtonMinWidth, (int)text + 22);
}

- (void)layoutSwipeButtonsCollapsed:(BOOL)collapsed {
	CGFloat width = self.contentView.bounds.size.width;
	CGFloat top = kSwipeButtonTop;
	CGFloat right = width - kSwipeEdgeDistance;
	for (NSUInteger i = _swipeButtons.count; i > 0; i--){
		UIButton *button = _swipeButtons[i - 1];
		CGFloat buttonWidth = [self swipeButtonWidthForIndex:i - 1];
		if (collapsed)
			button.frame = CGRectMake(width - kSwipeEdgeDistance - 2, top, 2, kSwipeButtonHeight);
		else
			button.frame = CGRectMake(right - buttonWidth, top, buttonWidth, kSwipeButtonHeight);
		right -= buttonWidth + kSwipeButtonGap;
	}
}

- (void)setCoveredContentAlpha:(CGFloat)alpha {
	self.dateLabel.alpha = alpha;
	self.tick.alpha = alpha;
	self.badge.alpha = alpha;
	self.badgeBackground.alpha = alpha;
	self.pin.alpha = alpha;
	self.arrow.alpha = alpha;
	self.previewLabel.alpha = alpha;
	self.authorLabel.alpha = alpha;
	self.draftLabel.alpha = alpha;
}

- (void)setSwipeActionsVisible:(BOOL)visible animated:(BOOL)animated {
	if (visible && !self.swipeActions.count)
		return;
	if (visible == _swipeActionsVisible && (!visible || _swipeButtons.count))
		return;
	_swipeActionsVisible = visible;

	if (visible){
		[self buildSwipeButtons];
		[self layoutSwipeButtonsCollapsed:YES];
		for (UIButton *button in _swipeButtons)
			button.alpha = 0.0f;

		__weak typeof(self) weakSelf = self;
		NSArray *coming = [_swipeButtons copy];
		void (^reveal)(void) = ^{
			[weakSelf layoutSwipeButtonsCollapsed:NO];
			for (UIButton *button in coming)
				button.alpha = 1.0f;
			[weakSelf setCoveredContentAlpha:0.0f];
		};
		if (animated)
			[UIView animateWithDuration:0.25 delay:0
								options:UIViewAnimationOptionBeginFromCurrentState
							 animations:reveal completion:nil];
		else
			reveal();
		return;
	}

	__weak typeof(self) weakSelf = self;
	NSArray *going = [_swipeButtons copy];
	CGFloat collapsedX = self.contentView.bounds.size.width - kSwipeEdgeDistance - 2;
	CGFloat collapsedY = kSwipeButtonTop;
	[_swipeButtons removeAllObjects];
	void (^conceal)(void) = ^{
		for (UIButton *button in going){
			button.alpha = 0.0f;
			button.frame = CGRectMake(collapsedX, collapsedY, 2, kSwipeButtonHeight);
		}
		[weakSelf setCoveredContentAlpha:1.0f];
	};
	void (^drop)(BOOL) = ^(BOOL finished){
		for (UIButton *button in going)
			[button removeFromSuperview];
	};
	if (animated)
		[UIView animateWithDuration:0.25 delay:0
							options:UIViewAnimationOptionBeginFromCurrentState
						 animations:conceal completion:drop];
	else {
		conceal();
		drop(YES);
	}
}

- (void)swipeButtonPressed:(UIButton *)button {
	NSInteger index = button.tag;
	if (index < 0 || index >= (NSInteger)self.swipeActions.count)
		return;
	NSString *kind = self.swipeActions[index][@"kind"];
	if (self.onSwipeAction && kind.length)
		self.onSwipeAction(kind);
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self setSwipeActionsVisible:NO animated:NO];
	[self setCoveredContentAlpha:1.0f];
	self.chatId = 0;
	self.swipeActions = nil;
	self.onSwipeOpen = nil;
	self.onSwipeAction = nil;
}

- (void)applyBadgeShadowForHighlight:(BOOL)highlighted {
	self.badge.shadowColor = highlighted
			? [UIColor clearColor]
			: [UIColor colorWithRed:0x80 / 255.0f green:0x91 / 255.0f
							   blue:0xa6 / 255.0f alpha:1.0f];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
	[super setHighlighted:highlighted animated:animated];
	[self applyBadgeShadowForHighlight:highlighted];
	if (_dateSuffix.length)
		[self applyDateAppearance];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
	[super setSelected:selected animated:animated];
	[self applyBadgeShadowForHighlight:selected || self.highlighted];
	if (_dateSuffix.length)
		[self applyDateAppearance];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
	if (editing && _swipeActionsVisible)
		[self setSwipeActionsVisible:NO animated:animated];
	[super setEditing:editing animated:animated];
}

- (void)applyDateAppearance {
	UIFont *main = _dateBold ? [UIFont boldSystemFontOfSize:13] : [UIFont systemFontOfSize:13];
	self.dateLabel.font = main;
	NSString *text = _dateMain ?: @"";
	UIColor *ink = (self.highlighted || self.selected) && self.dateLabel.highlightedTextColor
			? self.dateLabel.highlightedTextColor : self.dateLabel.textColor;

	if (!_dateSuffix.length || ![self.dateLabel respondsToSelector:@selector(setAttributedText:)]){
		self.dateLabel.text = text;
		_dateWidth = (int)[text sizeWithFont:main].width;
		return;
	}

	NSString *whole = [text stringByAppendingString:_dateSuffix];
	NSMutableAttributedString *line = [[NSMutableAttributedString alloc] initWithString:whole];
	[line addAttribute:NSFontAttributeName value:main range:NSMakeRange(0, text.length)];
	[line addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11]
				 range:NSMakeRange(text.length, _dateSuffix.length)];
	if (ink)
		[line addAttribute:NSForegroundColorAttributeName value:ink
					 range:NSMakeRange(0, whole.length)];
	self.dateLabel.attributedText = line;
	_dateWidth = (int)ceilf([line size].width);
}

- (void)setDateText:(NSString *)text suffix:(NSString *)suffix bold:(BOOL)bold {
	_dateMain = [text copy];
	_dateSuffix = [suffix copy];
	_dateBold = bold;
	[self applyDateAppearance];
}

- (CGFloat)layoutBadgeInWidth:(CGFloat)w {
	CGFloat countWidth = (int)[self.badge.text sizeWithFont:self.badge.font].width;
	CGFloat badgeWidth = MAX(27, countWidth + 10);
	CGRect badgeFrame = CGRectMake(w - 28 - badgeWidth, 29, badgeWidth, 21);
	self.badgeBackground.frame = badgeFrame;
	self.badge.frame = CGRectMake(badgeFrame.origin.x, badgeFrame.origin.y, badgeWidth, 20);
	return self.badge.hidden ? 0 : badgeWidth + 7;
}

- (CGFloat)layoutDraftLabelAtLeft:(CGFloat)left {
	if (self.draftLabel.hidden)
		return 0;
	CGFloat draftWidth = (int)[self.draftLabel.text sizeWithFont:self.draftLabel.font].width;
	self.draftLabel.frame = CGRectMake(left, 29, draftWidth, 18);
	return draftWidth + 4;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.contentView.bounds.size.width;
	CGFloat left = kTextLeft;
	CGFloat retinaPixel = ([UIScreen mainScreen].scale > 1.5f) ? 0.5f : 0.0f;
	CGFloat rightPadding = 16;

	rightPadding += [self layoutBadgeInWidth:w];

	CGFloat dateWidth = _dateWidth;
	CGFloat dateX = w - dateWidth - 9;
	self.dateLabel.frame = CGRectMake(dateX - (75 - dateWidth), 9, 75, 15);

	CGFloat titleX = left;
	CGFloat iconWidth = 0;
	if (!self.groupIcon.hidden){
		iconWidth = 21;
		self.groupIcon.frame = CGRectMake(left, 10,
				self.groupIcon.image.size.width, self.groupIcon.image.size.height);
		titleX += iconWidth;
	}

	CGFloat titleWidth = (int)(dateX - 4 - left - 18) - iconWidth;
	if (!self.muteIcon.hidden)
		titleWidth -= 12;
	titleWidth = MIN(titleWidth, TGEmojiTextSize(self.titleLabel.text, self.titleLabel.font,
			CGSizeMake(10000, 40), NSLineBreakByWordWrapping, 1).width);
	if (titleWidth < 0)
		titleWidth = 0;
	self.titleLabel.frame = CGRectMake(titleX, 6, titleWidth, 20);

	if (!self.muteIcon.hidden)
		self.muteIcon.frame = CGRectMake(titleX + titleWidth + 3, 12,
				self.muteIcon.image.size.width, self.muteIcon.image.size.height);

	CGFloat previewLeft = left + [self layoutDraftLabelAtLeft:left];
	CGRect previewFrame = CGRectMake(previewLeft, 29,
			w - previewLeft - 10 - rightPadding, 40);
	if (!self.authorLabel.hidden){
		self.authorLabel.frame = CGRectMake(left, 29, w - left - 10 - rightPadding, 20);
		previewFrame.origin.y += 9;
		previewFrame.size.height -= 12;
		CGSize fits = TGEmojiTextSize(self.previewLabel.text, self.previewLabel.font,
				previewFrame.size, NSLineBreakByTruncatingTail, 2);
		if (fits.height < 20)
			previewFrame.origin.y += 9;
		CGFloat textBottom = kRowHeight - 9;
		if (CGRectGetMaxY(previewFrame) > textBottom)
			previewFrame.size.height = textBottom - previewFrame.origin.y;
	}
	self.previewLabel.frame = previewFrame;

	// Your own last message is marked, the way it is in their chat item.
	if (!self.tick.hidden){
		CGSize tickSize = self.tick.image ? self.tick.image.size : CGSizeMake(13, 11);
		self.tick.frame = CGRectMake(dateX - tickSize.width - 2, 11 + retinaPixel,
				tickSize.width, tickSize.height);
	}

	if (!self.pin.hidden)
		self.pin.frame = CGRectMake(w - 28 - 16, 32, 16, 16);

	self.arrow.frame = CGRectMake(w - self.arrow.image.size.width - 6, 33,
			self.arrow.image.size.width, self.arrow.image.size.height);

	if (_swipeActionsVisible && _swipeButtons.count)
		[self layoutSwipeButtonsCollapsed:NO];
}

@end

#pragma mark - settings

static NSString *const TGChatListStoriesTrayKey = @"TGShowStoriesTray";
static NSString *const TGChatListFolderStyleKey = @"TGChatListFolderStyle";
static NSString *const TGChatListArchiveHiddenKey = @"TGArchiveHiddenByDefault";

static const NSInteger TGChatListFolderStyleChooser = 0;
static const NSInteger TGChatListFolderStyleStrip = 1;

static const CGFloat kStoryTrayHeight = 82.0f;
static const CGFloat kStoryCellWidth = 68.0f;
static const CGFloat kStoryAvatar = 56.0f;
static const CGFloat kSearchBarHeight = 44.0f;
static const CGFloat kFolderStripHeight = 44.0f;
static const CGFloat kLoginBannerHeight = 76.0f;
static const CGFloat kFolderBannerHeight = 62.0f;
static const NSUInteger kRowDetailCacheLimit = 200;
static const NSInteger kAvatarPrefetchRows = 4;
static const CGFloat kArchivePullThreshold = 40.0f;

static BOOL TGStoriesTrayEnabled(void) {
	id stored = [[NSUserDefaults standardUserDefaults] objectForKey:TGChatListStoriesTrayKey];
	return stored ? [stored boolValue] : YES;
}

static NSInteger TGChatListFolderStyle(void) {
	id stored = [[NSUserDefaults standardUserDefaults] objectForKey:TGChatListFolderStyleKey];
	return stored ? [stored integerValue] : TGChatListFolderStyleStrip;
}

static BOOL TGArchiveHiddenByDefault(void) {
	id stored = [[NSUserDefaults standardUserDefaults] objectForKey:TGChatListArchiveHiddenKey];
	return stored ? [stored boolValue] : YES;
}

static void TGSetArchiveHiddenByDefault(BOOL hidden) {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:hidden forKey:TGChatListArchiveHiddenKey];
	[defaults synchronize];
}

static UIImage *TGScopeBarBackgroundImage(void) {
	static UIImage *plate = nil;
	static BOOL looked = NO;
	if (!looked){
		looked = YES;
		UIImage *raw = [UIImage imageNamed:@"SearchBarScopeBarBackground.png"];
		if (raw)
			plate = [raw stretchableImageWithLeftCapWidth:1 topCapHeight:0];
	}
	return plate;
}

static UIImage *TGTitleCaretImage(void) {
	static UIImage *caret = nil;
	if (caret)
		return caret;
	CGSize size = CGSizeMake(10, 6);
	if (UIGraphicsBeginImageContextWithOptions != NULL)
		UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
	else
		UIGraphicsBeginImageContext(size);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
	CGContextMoveToPoint(ctx, 0, 0);
	CGContextAddLineToPoint(ctx, size.width, 0);
	CGContextAddLineToPoint(ctx, size.width / 2, size.height);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);
	caret = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return caret;
}

static UIImage *TGStoryScaledImage(UIImage *source, CGSize bounds) {
	if (!source || bounds.width < 1 || bounds.height < 1)
		return source;
	CGFloat scale = MIN(bounds.width / source.size.width, bounds.height / source.size.height);
	if (scale >= 1.0f)
		return source;
	CGSize target = CGSizeMake((int)(source.size.width * scale), (int)(source.size.height * scale));
	if (UIGraphicsBeginImageContextWithOptions != NULL)
		UIGraphicsBeginImageContextWithOptions(target, YES, 1.0f);
	else
		UIGraphicsBeginImageContext(target);
	[source drawInRect:CGRectMake(0, 0, target.width, target.height)];
	UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return scaled ?: source;
}

#pragma mark - story viewer

@interface TGStoryViewController : UIViewController <UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *posters;
@property (nonatomic, assign) NSInteger posterIndex;
@property (nonatomic, assign) NSInteger storyIndex;
@property (nonatomic, strong) UIView *bars;
@property (nonatomic, strong) UIImageView *photo;
@property (nonatomic, strong) UIView *captionPlate;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *titleLine;
@property (nonatomic, strong) UILabel *subtitleLine;
@property (nonatomic, strong) UIButton *replyButton;
@property (nonatomic, strong) UIButton *reactButton;
@property (nonatomic, strong) NSDictionary *current;
@property (nonatomic, assign) NSInteger openedStoryId;
@property (nonatomic, assign) int64_t openedChatId;
@property (nonatomic, assign) NSInteger loadingPhotoFileId;
@property (nonatomic, strong) NSArray *sheetItems;
@end

@implementation TGStoryViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor blackColor];

	UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 180, 40)];
	self.titleLine = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, 180, 18)];
	self.titleLine.backgroundColor = [UIColor clearColor];
	self.titleLine.font = [UIFont boldSystemFontOfSize:16];
	self.titleLine.textColor = [UIColor whiteColor];
	self.titleLine.textAlignment = NSTextAlignmentCenter;
	[titleView addSubview:self.titleLine];

	self.subtitleLine = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, 180, 15)];
	self.subtitleLine.backgroundColor = [UIColor clearColor];
	self.subtitleLine.font = [UIFont systemFontOfSize:13];
	self.subtitleLine.textColor = [UIColor colorWithRed:0xE0 / 255.0f green:0xEE / 255.0f
												   blue:0xFD / 255.0f alpha:1.0f];
	self.subtitleLine.textAlignment = NSTextAlignmentCenter;
	[titleView addSubview:self.subtitleLine];
	self.navigationItem.titleView = titleView;

	UIButton *more = [TGIcons headerButtonWithTitle:@"More" bold:NO
											 target:self action:@selector(moreTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:more];

	self.bars = [[UIView alloc] initWithFrame:CGRectZero];
	self.bars.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.bars];

	self.photo = [[UIImageView alloc] initWithFrame:CGRectZero];
	self.photo.contentMode = UIViewContentModeScaleAspectFit;
	self.photo.backgroundColor = [UIColor blackColor];
	[self.view addSubview:self.photo];

	self.captionPlate = [[UIView alloc] initWithFrame:CGRectZero];
	self.captionPlate.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45f];
	self.captionPlate.hidden = YES;
	[self.view addSubview:self.captionPlate];

	self.captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.captionLabel.backgroundColor = [UIColor clearColor];
	self.captionLabel.font = [UIFont systemFontOfSize:15];
	self.captionLabel.textColor = [UIColor whiteColor];
	self.captionLabel.numberOfLines = 2;
	self.captionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.view addSubview:self.captionLabel];

	self.replyButton = [self footerButtonWithTitle:@"Reply" action:@selector(replyTapped)];
	self.reactButton = [self footerButtonWithTitle:@"♥" action:@selector(reactTapped)];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(viewTapped:)];
	[self.view addGestureRecognizer:tap];

	[self showCurrentStory];
}

- (UIButton *)footerButtonWithTitle:(NSString *)title action:(SEL)action {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	[button setTitle:title forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	button.titleLabel.shadowColor = [UIColor colorWithRed:0x0e / 255.0f green:0x28 / 255.0f
													 blue:0x4d / 255.0f alpha:0.4f];
	button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	button.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.15f];
	button.layer.cornerRadius = 4;
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:button];
	return button;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGRect bounds = self.view.bounds;
	CGFloat w = bounds.size.width;
	CGFloat h = bounds.size.height;

	self.bars.frame = CGRectMake(0, 6, w, 3);
	[self layoutBars];

	CGFloat footerTop = h - 40;
	self.photo.frame = CGRectMake(0, 15, w, footerTop - 20);
	self.replyButton.frame = CGRectMake(10, footerTop, 145, 30);
	self.reactButton.frame = CGRectMake(165, footerTop, 145, 30);

	CGRect plate = CGRectMake(0, CGRectGetMaxY(self.photo.frame) - 50, w, 50);
	self.captionPlate.frame = plate;
	self.captionLabel.frame = CGRectInset(plate, 10, 6);
}

- (void)layoutBars {
	for (UIView *bar in [self.bars.subviews copy])
		[bar removeFromSuperview];

	NSArray *stories = TGReplyArray([self currentPoster][@"stories"]);
	NSInteger count = (NSInteger)stories.count;
	if (count <= 0)
		return;
	CGFloat width = self.bars.bounds.size.width - 8;
	CGFloat gap = 2;
	CGFloat each = (width - gap * (count - 1)) / count;
	for (NSInteger i = 0; i < count; i++){
		UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(4 + i * (each + gap), 0, each, 3)];
		bar.backgroundColor = [UIColor colorWithWhite:1.0f
												alpha:(i <= self.storyIndex ? 1.0f : 0.3f)];
		[self.bars addSubview:bar];
	}
}

- (NSDictionary *)currentPoster {
	if (self.posterIndex < 0 || self.posterIndex >= (NSInteger)self.posters.count)
		return nil;
	return self.posters[self.posterIndex];
}

- (void)closeOpenStory {
	if (self.loadingPhotoFileId){
		[[TGClient shared] cancelDownloadOfFile:self.loadingPhotoFileId onlyIfPending:NO];
		self.loadingPhotoFileId = 0;
	}
	if (!self.openedStoryId)
		return;
	[[TGClient shared] closeStory:self.openedStoryId inChat:self.openedChatId];
	self.openedStoryId = 0;
	self.openedChatId = 0;
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self closeOpenStory];
}

- (void)showCurrentStory {
	NSDictionary *poster = [self currentPoster];
	if (!poster){
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}

	NSArray *stories = TGReplyArray(poster[@"stories"]);
	if (self.storyIndex >= (NSInteger)stories.count)
		self.storyIndex = (NSInteger)stories.count - 1;
	if (self.storyIndex < 0)
		self.storyIndex = 0;
	if (!stories.count)
		return;

	int64_t chatId = [poster[@"chatId"] longLongValue];
	NSDictionary *entry = TGReplyDictionary(stories[self.storyIndex]);
	NSInteger storyId = [entry[@"id"] integerValue];
	if (!storyId)
		return;

	[self closeOpenStory];
	[[TGClient shared] openStory:storyId inChat:chatId];
	self.openedStoryId = storyId;
	self.openedChatId = chatId;

	self.titleLine.text = TGReplyString(poster[@"title"]) ?: @"";
	self.subtitleLine.text = [NSString stringWithFormat:@"%ld of %lu",
			(long)(self.storyIndex + 1), (unsigned long)stories.count];
	[self layoutBars];
	self.photo.image = nil;
	self.captionLabel.text = @"";
	self.captionPlate.hidden = YES;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storyWithId:storyId inChat:chatId completion:^(NSDictionary *reply){
		TGStoryViewController *me = weakSelf;
		NSDictionary *story = TGReplyDictionary(reply);
		if (!me || !story)
			return;
		if (me.openedStoryId != storyId)
			return;
		[me applyStory:story forStoryId:storyId];
	}];
}

- (void)applyStory:(NSDictionary *)story forStoryId:(NSInteger)storyId {
	self.current = story;
	NSString *caption = TGReplyString(story[@"caption"]);
	self.captionLabel.text = caption ?: @"";
	self.captionPlate.hidden = (caption.length == 0);
	NSInteger reactions = [story[@"reactions"] integerValue];
	[self.reactButton setTitle:(reactions > 0
			? [NSString stringWithFormat:@"♥ %ld", (long)reactions] : @"♥")
					  forState:UIControlStateNormal];

	id photoId = story[@"photoId"];
	if (![photoId isKindOfClass:[NSNumber class]])
		return;
	NSInteger photoFileId = [photoId integerValue];
	self.loadingPhotoFileId = photoFileId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:photoFileId completion:^(NSString *reply){
		TGStoryViewController *inner = weakSelf;
		if (!inner || inner.openedStoryId != storyId)
			return;
		if (inner.loadingPhotoFileId == photoFileId)
			inner.loadingPhotoFileId = 0;
		NSString *path = TGReplyString(reply);
		if (!path.length)
			return;
		UIImage *raw = [UIImage imageWithContentsOfFile:path];
		if (!raw)
			return;
		inner.photo.image = TGStoryScaledImage(raw, inner.photo.bounds.size);
	}];
}

- (void)viewTapped:(UITapGestureRecognizer *)tap {
	CGFloat x = [tap locationInView:self.view].x;
	CGFloat w = self.view.bounds.size.width;
	if (x < w * 0.4f)
		[self stepBy:-1];
	else if (x > w * 0.6f)
		[self stepBy:1];
}

- (void)stepBy:(NSInteger)delta {
	NSArray *stories = TGReplyArray([self currentPoster][@"stories"]);
	NSInteger next = self.storyIndex + delta;
	if (next < 0){
		if (self.posterIndex == 0)
			return;
		self.posterIndex -= 1;
		self.storyIndex = (NSInteger)TGReplyArray([self currentPoster][@"stories"]).count - 1;
	} else if (next >= (NSInteger)stories.count){
		if (self.posterIndex + 1 >= (NSInteger)self.posters.count){
			[self closeOpenStory];
			[self.navigationController popViewControllerAnimated:YES];
			return;
		}
		self.posterIndex += 1;
		self.storyIndex = 0;
	} else {
		self.storyIndex = next;
	}
	[self showCurrentStory];
}

- (void)replyTapped {
	UIAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Reply"
													message:nil
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Send", nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	alert.tag = 1;
	[alert show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
	if (alertView.tag != 1 || buttonIndex == alertView.cancelButtonIndex)
		return;
	NSString *text = [alertView textFieldAtIndex:0].text;
	if (!text.length)
		return;
	[[TGClient shared] replyToStory:self.openedStoryId inChat:self.openedChatId text:text];
}

- (void)reactTapped {
	NSString *mine = TGReplyString(self.current[@"myReaction"]);
	NSString *next = mine.length ? nil : @"❤";
	[[TGClient shared] reactToStory:self.openedStoryId inChat:self.openedChatId emoji:next];
	NSMutableDictionary *updated = [(self.current ?: @{}) mutableCopy];
	NSInteger reactions = [updated[@"reactions"] integerValue] + (next ? 1 : -1);
	if (reactions < 0)
		reactions = 0;
	updated[@"reactions"] = @(reactions);
	updated[@"myReaction"] = next ?: @"";
	self.current = updated;
	[self.reactButton setTitle:(reactions > 0
			? [NSString stringWithFormat:@"♥ %ld", (long)reactions] : @"♥")
					  forState:UIControlStateNormal];
}

- (void)moreTapped {
	NSMutableArray *items = [NSMutableArray array];
	NSString *name = TGReplyString([self currentPoster][@"title"]) ?: @"this person";
	[items addObject:@{@"kind" : @"hide",
					   @"title" : [NSString stringWithFormat:@"Hide Stories from %@", name]}];
	[items addObject:@{@"kind" : @"report", @"title" : @"Report"}];
	if ([self.current[@"canDelete"] boolValue])
		[items addObject:@{@"kind" : @"delete", @"title" : @"Delete Story"}];
	self.sheetItems = items;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:nil];
	for (NSDictionary *item in items)
		[sheet addButtonWithTitle:item[@"title"]];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex || index < 0 || index >= (NSInteger)self.sheetItems.count)
		return;
	NSString *kind = self.sheetItems[index][@"kind"];
	int64_t chatId = self.openedChatId;
	NSInteger storyId = self.openedStoryId;

	if ([kind isEqualToString:@"hide"]){
		[[TGClient shared] setUser:chatId storiesHidden:YES];
		[self closeOpenStory];
		[self.navigationController popViewControllerAnimated:YES];
	} else if ([kind isEqualToString:@"delete"]){
		[[TGClient shared] deleteStory:storyId inChat:chatId];
		[self closeOpenStory];
		[self.navigationController popViewControllerAnimated:YES];
	} else if ([kind isEqualToString:@"report"]){
		[[TGClient shared] reportStory:storyId inChat:chatId optionId:nil text:nil
							completion:^(NSDictionary *reply){
			NSString *status = TGReplyString(TGReplyDictionary(reply)[@"status"]);
			NSString *message = [status isEqualToString:@"ok"]
					? @"Thank you. The story has been reported."
					: @"The report was not accepted.";
			UIAlertView *done = [[UIAlertView alloc] initWithTitle:@"Report"
														   message:message
														  delegate:nil
												 cancelButtonTitle:@"OK"
												 otherButtonTitles:nil];
			[done show];
		}];
	}
}

@end

#pragma mark - controller

@interface TGChatListViewController () <UISearchBarDelegate, UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, assign) BOOL showsArchive;      // this IS the archive screen
@property (nonatomic, assign) NSInteger folderId;     // 0 = no folder
@property (nonatomic, strong) NSMutableDictionary *avatars;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@property (nonatomic, strong) NSMutableSet *avatarsInFlight;
@property (nonatomic, strong) NSMutableSet *avatarsFailedOnce;
@property (nonatomic, assign) NSTimeInterval lastAvatarSweep;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *searchResults;   // nil = not searching
@property (nonatomic, strong) NSDictionary *actionChat; // long-pressed row
@property (nonatomic, assign) int64_t chatPendingDeletion;
@property (nonatomic, assign) CGFloat headerHeight;
@property (nonatomic, copy) NSString *headerSignature;
@property (nonatomic, assign) CGFloat scrollAnchor;
@property (nonatomic, assign) BOOL archiveAvailable;
@property (nonatomic, assign) BOOL archiveRevealed;
@property (nonatomic, assign) CGFloat archiveRowTop;
@property (nonatomic, weak) TGChatCell *archiveRowView;
@property (nonatomic, assign) BOOL initialScrollApplied;
@property (nonatomic, strong) UIView *emptyContainer;
@property (nonatomic, strong) UIImageView *emptyIcon;
@property (nonatomic, strong) UILabel *emptyTitleLabel;
@property (nonatomic, strong) UILabel *emptyTextLabel;
@property (nonatomic, strong) id themeObserver;
@property (nonatomic, strong) id storyObserver;
@property (nonatomic, strong) NSArray *sheetItems;
@property (nonatomic, strong) NSDictionary *archiveSettings;
@property (nonatomic, assign) CGPoint menuPoint;
@property (nonatomic, strong) NSMutableDictionary *listUnread;
@property (nonatomic, assign) NSInteger folderLimit;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, strong) NSMutableSet *sponsoredSeen;
@property (nonatomic, strong) NSArray *storyPosters;
@property (nonatomic, strong) NSMutableDictionary *storyPostersById;
@property (nonatomic, assign) NSInteger storyProbesPending;
@property (nonatomic, assign) NSTimeInterval lastStorySweep;
@property (nonatomic, strong) UILabel *titleLabelView;
@property (nonatomic, strong) UIView *titleStatusContainer;
@property (nonatomic, strong) UILabel *titleStatusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *titleStatusIndicator;
@property (nonatomic, copy) NSString *connectionText;
@property (nonatomic, weak) TGChatCell *openSwipeCell;
@property (nonatomic, strong) NSMutableDictionary *secretStatuses;
@property (nonatomic, strong) NSMutableSet *secretStatusesRequested;
@property (nonatomic, strong) NSMutableDictionary *muteRemaining;
@property (nonatomic, strong) NSDictionary *unconfirmedSession;
@property (nonatomic, strong) NSArray *folderSheetItems;
@property (nonatomic, strong) NSArray *rowActionKinds;
@property (nonatomic, assign) int64_t chatPendingCustomMute;
@property (nonatomic, strong) NSArray *folderNewChats;
@property (nonatomic, assign) NSInteger folderNewChatsFolderId;
@property (nonatomic, strong) NSMutableDictionary *rowDetails;
@property (nonatomic, strong) NSMutableSet *rowDetailsRequested;
@property (nonatomic, strong) NSArray *listsToAddIds;
@property (nonatomic, assign) BOOL actionChatUnread;
@end

@implementation TGChatListViewController

- (void)buildRowCaches {
	self.chats = @[];
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];
	self.avatarsInFlight = [NSMutableSet set];
	self.avatarsFailedOnce = [NSMutableSet set];
	self.listUnread = [NSMutableDictionary dictionary];
	self.sponsoredSeen = [NSMutableSet set];
	self.storyPostersById = [NSMutableDictionary dictionary];
	self.secretStatuses = [NSMutableDictionary dictionary];
	self.secretStatusesRequested = [NSMutableSet set];
	self.muteRemaining = [NSMutableDictionary dictionary];
	self.rowDetails = [NSMutableDictionary dictionary];
	self.rowDetailsRequested = [NSMutableSet set];
	self.folderLimit = 60;
}

/// Search sits above the list, the way every client puts it - pull down or
/// just start typing.
- (void)buildSearchBar {
	CGFloat searchWidth = self.view.bounds.size.width;
	if (searchWidth < 1)
		searchWidth = self.tableView.bounds.size.width;
	if (searchWidth < 1)
		searchWidth = [UIScreen mainScreen].applicationFrame.size.width;
	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, searchWidth, 44)];
	self.searchBar.delegate = self;
	self.searchBar.placeholder = @"Search";
	[self styleSearchBar];
	[self rebuildTableHeader];
}

- (void)styleListTable {
	self.tableView.rowHeight = kRowHeight;
	[self applySeparatorStyle];
	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.tableView.backgroundView = nil;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.view.layer.backgroundColor = [[TGTheme shared] listBackgroundColour].CGColor;
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[[TGTheme shared] styleTabBar:self.tabBarController.tabBar];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = [self defaultTitle];
	[self buildRowCaches];
	if (!self.showsArchive && TGStoriesTrayEnabled())
		[[TGClient shared] loadActiveStoriesArchived:NO];

	[self installComposeButton];
	[self updateEditingChrome];

	[self buildSearchBar];

	// Hold a row for the two things clients put there: pin and mute.
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(rowHeld:)];
	[self.tableView addGestureRecognizer:hold];

	[self styleListTable];

	[self installThemeObserver];
	[self installStoryObserver];

	if ([self.tabBarController isKindOfClass:[RootViewController class]])
		[(RootViewController *)self.tabBarController updateUnreadBadge];

	[self buildEmptyContainer];

	[self applyTitleView];
	[self installClientHandlers];
	[self reload];
}

/// Without this there is no way to start a conversation at all - you can only
/// reply to chats that already exist.
- (void)installComposeButton {
	UIButton *compose = [UIButton buttonWithType:UIButtonTypeCustom];
	[TGIcons styleHeaderButton:compose];
	[compose setImage:[UIImage imageNamed:@"ComposeMessageIcon"] forState:UIControlStateNormal];
	compose.frame = CGRectMake(0, 0, 30, 30);
	[compose addTarget:self action:@selector(composeTapped) forControlEvents:UIControlEventTouchUpInside];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:compose];
}

/// Restyle in place when the setting changes, rather than needing a restart.
- (void)installThemeObserver {
	__weak typeof(self) weakSelf = self;
	self.themeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		usingBlock:^(NSNotification *note){
		[TGIcons flush];
		[[TGTheme shared] styleNavigationBar:weakSelf.navigationController.navigationBar];
		weakSelf.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
		weakSelf.view.layer.backgroundColor = [[TGTheme shared] listBackgroundColour].CGColor;
		weakSelf.tableView.separatorColor = [[TGTheme shared] separatorColour];
		[weakSelf applySeparatorStyle];
		[[TGTheme shared] styleTabBar:weakSelf.tabBarController.tabBar];
		[weakSelf styleSearchBar];
		[weakSelf applyTitleView];
		[weakSelf updateEditingChrome];
		[weakSelf rebuildTableHeader];
		[weakSelf.tableView reloadData];
	}];
}

- (void)installStoryObserver {
	__weak typeof(self) weakSelf = self;
	self.storyObserver = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGStoryUpdateNotification
						object:nil
						 queue:[NSOperationQueue mainQueue]
					usingBlock:^(NSNotification *note){
		[weakSelf handleStoryUpdate:note.object];
	}];
}

- (void)handleStoryUpdate:(id)update {
	if (self.showsArchive || !TGStoriesTrayEnabled())
		return;

	NSDictionary *object = TGReplyDictionary(update);
	NSString *type = TGReplyString(object[@"@type"]);
	int64_t chatId = 0;
	if ([type isEqualToString:@"updateChatActiveStories"])
		chatId = [TGReplyDictionary(object[@"active_stories"])[@"chat_id"] longLongValue];
	else if ([type isEqualToString:@"updateStoryPostSucceeded"] ||
			 [type isEqualToString:@"updateStory"])
		chatId = [TGReplyDictionary(object[@"story"])[@"poster_chat_id"] longLongValue];
	else if ([type isEqualToString:@"updateStoryDeleted"])
		chatId = [object[@"story_poster_chat_id"] longLongValue];
	if (chatId == 0)
		return;

	[self mergeStoryPosterForChat:chatId attempt:0];
}

- (NSString *)storyTitleForChat:(int64_t)chatId {
	for (NSDictionary *chat in self.chats){
		if ([chat[@"id"] longLongValue] == chatId)
			return TGReplyString(chat[@"title"]) ?: @"";
	}
	NSString *name = chatId > 0 ? [[TGClient shared] nameForUserId:chatId] : nil;
	return name.length ? name : @"Story";
}

- (NSNumber *)storyPhotoFileIdForChat:(int64_t)chatId {
	for (NSDictionary *chat in self.chats){
		if ([chat[@"id"] longLongValue] != chatId)
			continue;
		id fileId = chat[@"photoFileId"];
		return [fileId isKindOfClass:[NSNumber class]] ? fileId : nil;
	}
	return nil;
}

- (void)mergeStoryPosterForChat:(int64_t)chatId attempt:(NSInteger)attempt {
	if (self.storyProbesPending > 0){
		if (attempt >= 5)
			return;
		__weak typeof(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
			[weakSelf mergeStoryPosterForChat:chatId attempt:(attempt + 1)];
		});
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] activeStoriesForChat:chatId completion:^(NSDictionary *reply){
		TGChatListViewController *me = weakSelf;
		if (!me || me.showsArchive || !TGStoriesTrayEnabled() || me.storyProbesPending > 0)
			return;
		if (!me.storyPostersById)
			me.storyPostersById = [NSMutableDictionary dictionary];

		NSDictionary *active = TGReplyDictionary(reply);
		NSArray *stories = TGReplyArray(active[@"stories"]);
		NSNumber *key = @(chatId);

		if (!stories.count || [active[@"archived"] boolValue]){
			if (!me.storyPostersById[key])
				return;
			[me.storyPostersById removeObjectForKey:key];
			[me commitStoryPosters];
			return;
		}

		NSMutableDictionary *poster = [NSMutableDictionary dictionary];
		poster[@"chatId"] = key;
		poster[@"title"] = [me storyTitleForChat:chatId];
		poster[@"stories"] = stories;
		poster[@"order"] = active[@"order"] ?: @0;
		poster[@"unread"] = active[@"unread"] ?: @NO;
		NSNumber *fileId = [me storyPhotoFileIdForChat:chatId];
		if (fileId)
			poster[@"photoFileId"] = fileId;

		if ([me.storyPostersById[key] isEqual:poster])
			return;
		me.storyPostersById[key] = poster;
		[me commitStoryPosters];
	}];
}

- (void)updateEditingChrome {
	BOOL editing = self.tableView.editing;
	UIButton *button = [TGIcons headerButtonWithTitle:(editing ? @"Done" : @"Edit")
												 bold:editing
											   target:self action:@selector(editTapped)];
	[button addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(editHeld:)]];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
	self.navigationItem.rightBarButtonItem.customView.alpha = editing ? 0.0f : 1.0f;
}

- (void)editTapped {
	[self closeOpenSwipeCellAnimated:NO];
	[self.tableView setEditing:!self.tableView.editing animated:YES];
	[self updateEditingChrome];
}

- (void)editHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	[self actionsTapped];
}

- (void)installClientHandlers {
	__weak typeof(self) weakSelf = self;
	[TGClient shared].onChatsChanged = ^{
		[weakSelf reload];
		TGChatListViewController *me = weakSelf;
		if ([me.tabBarController isKindOfClass:[RootViewController class]])
			[(RootViewController *)me.tabBarController updateUnreadBadge];
	};
	[TGClient shared].onArchiveChanged = ^{
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		if (me.showsArchive)
			[me reload];
		else
			[me rebuildTableHeader];
		[me.tableView reloadData];
	};
	[TGClient shared].onConnectionState = ^(TGConnectionState state, NSString *text){
		TGChatListViewController *me = weakSelf;
		NSString *line = TGReplyString(text);
		me.connectionText = line.length ? line : nil;
		[me applyTitleView];
		[me updateEmptyState];
	};
}

- (NSString *)defaultTitle {
	if (self.showsArchive)
		return @"Archived";
	if (self.folderId != 0){
		for (id entry in [self folderList]){
			NSDictionary *f = TGReplyDictionary(entry);
			if ([f[@"id"] integerValue] == self.folderId)
				return TGReplyString(f[@"title"]) ?: @"Messages";
		}
	}
	return @"Messages";
}

- (NSArray *)folderList {
	return TGReplyArray([TGClient shared].folders) ?: @[];
}

- (BOOL)hasFolders {
	return [self folderList].count > 0;
}

- (BOOL)usesFolderStrip {
	return !self.showsArchive && [self hasFolders] &&
		   TGChatListFolderStyle() == TGChatListFolderStyleStrip;
}

- (BOOL)usesFolderChooser {
	return !self.showsArchive && [self hasFolders] &&
		   TGChatListFolderStyle() == TGChatListFolderStyleChooser;
}

- (UIView *)titleStatusView {
	if (!self.titleStatusContainer){
		self.titleStatusContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 30)];
		self.titleStatusContainer.clipsToBounds = NO;

		self.titleStatusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		self.titleStatusLabel.backgroundColor = [UIColor clearColor];
		self.titleStatusLabel.font = [UIFont boldSystemFontOfSize:15];
		self.titleStatusLabel.textColor = [UIColor whiteColor];
		self.titleStatusLabel.shadowColor = [UIColor colorWithRed:0x41 / 255.0f
															green:0x5a / 255.0f
															 blue:0x7e / 255.0f alpha:1.0f];
		self.titleStatusLabel.shadowOffset = CGSizeMake(0, -1);
		[self.titleStatusContainer addSubview:self.titleStatusLabel];

		self.titleStatusIndicator = [[UIActivityIndicatorView alloc]
				initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
		[self.titleStatusContainer addSubview:self.titleStatusIndicator];
	}

	self.titleStatusLabel.text = self.connectionText ?: @"";
	[self.titleStatusLabel sizeToFit];
	CGRect holder = self.titleStatusContainer.bounds;
	CGRect label = self.titleStatusLabel.frame;
	CGRect spinner = self.titleStatusIndicator.frame;
	label.origin = CGPointMake((int)((holder.size.width - label.size.width
					+ spinner.size.width + 5) / 2),
			(int)((holder.size.height - label.size.height) / 2) - 1);
	self.titleStatusLabel.frame = label;
	self.titleStatusIndicator.frame = CGRectMake(label.origin.x - spinner.size.width - 5,
			label.origin.y + 3, spinner.size.width, spinner.size.height);
	[self.titleStatusIndicator startAnimating];
	return self.titleStatusContainer;
}

- (void)applyTitleView {
	self.title = [self defaultTitle];
	if (self.connectionText.length){
		self.navigationItem.titleView = [self titleStatusView];
		return;
	}
	if (self.titleStatusIndicator)
		[self.titleStatusIndicator stopAnimating];
	if (![self usesFolderChooser]){
		self.navigationItem.titleView = nil;
		self.titleLabelView = nil;
		return;
	}

	NSString *text = [self defaultTitle];
	UIFont *font = [UIFont boldSystemFontOfSize:20];
	CGFloat textWidth = MIN(180, (int)[text sizeWithFont:font].width);
	UIImage *caret = TGTitleCaretImage();
	CGFloat width = textWidth + 6 + caret.size.width;

	UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 40)];
	self.titleLabelView = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, textWidth, 40)];
	self.titleLabelView.backgroundColor = [UIColor clearColor];
	self.titleLabelView.font = font;
	self.titleLabelView.textColor = [UIColor whiteColor];
	self.titleLabelView.shadowColor = [UIColor colorWithWhite:0 alpha:0.4f];
	self.titleLabelView.shadowOffset = CGSizeMake(0, -1);
	self.titleLabelView.textAlignment = NSTextAlignmentCenter;
	self.titleLabelView.text = text;
	[holder addSubview:self.titleLabelView];

	UIImageView *arrow = [[UIImageView alloc] initWithImage:caret];
	arrow.frame = CGRectMake(textWidth + 6, 22, caret.size.width, caret.size.height);
	[holder addSubview:arrow];

	holder.userInteractionEnabled = YES;
	[holder addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(foldersTapped)]];
	self.navigationItem.titleView = holder;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self installClientHandlers];
	[self applyTitleView];
	[self applyBottomBarInset];
	[self rebuildTableHeader];
	NSIndexPath *selected = [self.tableView indexPathForSelectedRow];
	if (selected && ![self splitLayoutActive])
		[self.tableView deselectRowAtIndexPath:selected animated:animated];
	if ([self.tabBarController isKindOfClass:[RootViewController class]])
		[(RootViewController *)self.tabBarController updateUnreadBadge];
	[self reload];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	[self closeOpenSwipeCellAnimated:YES];
	self.scrollAnchor = scrollView.contentOffset.y + scrollView.contentInset.top;
}

- (void)snapSearchBar:(UIScrollView *)scrollView {
	CGFloat top = scrollView.contentInset.top;
	CGFloat shown = scrollView.contentOffset.y + top;
	if (shown <= 0 || shown >= kSearchBarHeight)
		return;

	CGFloat target = shown < kSearchBarHeight / 2 ? 0 : kSearchBarHeight;

	[scrollView setContentOffset:CGPointMake(0, target - top) animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self closeOpenSwipeCellAnimated:NO];
	[TGPopupMenu dismiss];
	[TGActionsMenu dismiss];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (self.emptyContainer && !self.emptyContainer.hidden)
		[self updateEmptyState];
	[self revealArchiveIfPulled:scrollView];
	[self loadMoreIfNeeded];
	[self fetchMissingAvatarsThrottled];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	if (!decelerate){
		[self collapseArchiveIfScrolledPast];
		[self snapSearchBar:scrollView];
		[self fetchMissingAvatars];
		self.scrollAnchor = scrollView.contentOffset.y + scrollView.contentInset.top;
	}
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	[self collapseArchiveIfScrolledPast];
	[self snapSearchBar:scrollView];
	[self fetchMissingAvatars];
	self.scrollAnchor = scrollView.contentOffset.y + scrollView.contentInset.top;
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
	[self collapseArchiveIfScrolledPast];
	[self fetchMissingAvatars];
	self.scrollAnchor = scrollView.contentOffset.y + scrollView.contentInset.top;
}

- (BOOL)archiveBannerAllowed {
	return !self.showsArchive && self.folderId == 0 && self.searchResults == nil &&
			!self.tableView.editing;
}

- (void)revealArchiveIfPulled:(UIScrollView *)scrollView {
	if (self.archiveRevealed || !self.archiveAvailable || !TGArchiveHiddenByDefault())
		return;
	if (![self archiveBannerAllowed] || !scrollView.dragging)
		return;
	if (self.scrollAnchor > 0.5f)
		return;
	if (scrollView.contentOffset.y + scrollView.contentInset.top > -kArchivePullThreshold)
		return;

	CGPoint offset = scrollView.contentOffset;
	self.archiveRevealed = YES;
	[self rebuildTableHeader];
	if (!CGPointEqualToPoint(scrollView.contentOffset, offset))
		scrollView.contentOffset = offset;

	UIView *row = self.archiveRowView;
	if (row){
		row.alpha = 0;
		[UIView animateWithDuration:0.25 animations:^{
			row.alpha = 1;
		}];
	}
}

- (void)collapseArchiveIfScrolledPast {
	if (!self.archiveRevealed || !TGArchiveHiddenByDefault() || ![self archiveBannerAllowed])
		return;
	UITableView *table = self.tableView;
	if (table.contentOffset.y + table.contentInset.top < self.archiveRowTop + kRowHeight)
		return;

	CGPoint offset = table.contentOffset;
	self.archiveRevealed = NO;
	[self rebuildTableHeader];
	offset.y -= kRowHeight;
	table.contentOffset = offset;
}

- (void)toggleArchiveHiddenByDefaultFromCell:(TGChatCell *)cell {
	if (cell){
		[cell setSwipeActionsVisible:NO animated:YES];
		if (self.openSwipeCell == cell)
			self.openSwipeCell = nil;
	}

	BOOL hidden = !TGArchiveHiddenByDefault();
	TGSetArchiveHiddenByDefault(hidden);
	self.archiveRevealed = NO;
	[self rebuildTableHeader];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self applyBottomBarInset];
	UIView *header = self.tableView.tableHeaderView;
	CGFloat width = self.tableView.bounds.size.width;
	if (header && width >= 1 && header.frame.size.width != width)
		[self rebuildTableHeader];
	[self updateEmptyState];
}

- (void)applyBottomBarInset {
	CGFloat bottom = 0;
	id tabs = self.tabBarController;
	if ([tabs isKindOfClass:[RootViewController class]])
		bottom = [(RootViewController *)tabs tabBarInsetForController:self];

	UIEdgeInsets insets = self.tableView.contentInset;
	if (insets.bottom == bottom &&
			self.tableView.scrollIndicatorInsets.bottom == bottom)
		return;
	insets.bottom = bottom;
	self.tableView.contentInset = insets;
	self.tableView.scrollIndicatorInsets = insets;
}

- (void)buildEmptyContainer {
	UIColor *ink = [UIColor colorWithRed:0x8b / 255.0f green:0x97 / 255.0f
									blue:0xa5 / 255.0f alpha:1.0f];

	self.emptyContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 250, 0)];
	self.emptyContainer.backgroundColor = [UIColor clearColor];
	self.emptyContainer.userInteractionEnabled = NO;
	self.emptyContainer.hidden = YES;

	self.emptyIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"NoMessages.png"]];
	[self.emptyContainer addSubview:self.emptyIcon];

	self.emptyTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.emptyTitleLabel.backgroundColor = [UIColor clearColor];
	self.emptyTitleLabel.textColor = ink;
	self.emptyTitleLabel.font = [UIFont boldSystemFontOfSize:15];
	[self.emptyContainer addSubview:self.emptyTitleLabel];

	self.emptyTextLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.emptyTextLabel.backgroundColor = [UIColor clearColor];
	self.emptyTextLabel.textColor = ink;
	self.emptyTextLabel.font = [UIFont systemFontOfSize:14];
	self.emptyTextLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
	self.emptyTextLabel.numberOfLines = 0;
	[self.emptyContainer addSubview:self.emptyTextLabel];

	[self.tableView addSubview:self.emptyContainer];
}

- (void)updateEmptyState {
	if (!self.emptyContainer)
		return;

	NSInteger rows = [self visibleChats].count + [self headerRows].count;
	if (rows > 0){
		self.emptyContainer.hidden = YES;
		return;
	}

	NSArray *wording = [self emptyStateWording];
	NSString *title = wording[0];
	NSString *text = wording[1];

	self.emptyTitleLabel.text = title;
	self.emptyTextLabel.text = text;

	[self layoutEmptyContentWithText:text];
}

- (NSArray *)emptyStateWording {
	NSString *title = @"You have no conversations yet";
	NSString *text = @"Start messaging by pressing the pencil button in the "
					  "top right corner or go to the Contacts section.";
	if (self.searchResults){
		title = @"No results";
		text = @"";
	} else if (self.showsArchive){
		title = @"You have no archived conversations";
		text = @"";
	} else if (self.folderId != 0){
		title = @"This folder has no conversations";
		text = @"";
	}
	return @[title, text];
}

- (void)layoutEmptyContentWithText:(NSString *)text {
	CGFloat width = 250;
	CGFloat top = 0;
	self.emptyIcon.hidden = (self.emptyIcon.image == nil);
	if (!self.emptyIcon.hidden){
		CGSize icon = self.emptyIcon.image.size;
		self.emptyIcon.frame = CGRectMake((int)((width - icon.width) / 2), 0,
				icon.width, icon.height);
		top = icon.height;
	}

	[self.emptyTitleLabel sizeToFit];
	CGRect titleFrame = self.emptyTitleLabel.frame;
	titleFrame.origin = CGPointMake((int)((width - titleFrame.size.width) / 2),
			top + (top > 0 ? 21 : 0));
	self.emptyTitleLabel.frame = titleFrame;
	CGFloat height = CGRectGetMaxY(titleFrame);

	if (text.length){
		CGSize fits = [self.emptyTextLabel sizeThatFits:CGSizeMake(232, 1000)];
		self.emptyTextLabel.frame = CGRectMake((int)((width - fits.width) / 2),
				CGRectGetMaxY(titleFrame) + 8, fits.width, fits.height);
		height = CGRectGetMaxY(self.emptyTextLabel.frame);
		self.emptyTextLabel.hidden = NO;
	} else {
		self.emptyTextLabel.hidden = YES;
	}

	CGRect bounds = self.tableView.bounds;
	self.emptyContainer.frame = CGRectMake((int)((bounds.size.width - width) / 2),
			bounds.origin.y + (int)((bounds.size.height - height) / 2), width, height);
	self.emptyContainer.hidden = NO;
	[self.tableView bringSubviewToFront:self.emptyContainer];
}

- (void)dealloc {
	if (self.themeObserver)
		[[NSNotificationCenter defaultCenter] removeObserver:self.themeObserver];
	if (self.storyObserver)
		[[NSNotificationCenter defaultCenter] removeObserver:self.storyObserver];
}

- (void)applySeparatorStyle {
	TGTheme *theme = [TGTheme shared];
	BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
	self.tableView.separatorStyle = plainPlate
			? UITableViewCellSeparatorStyleNone
			: UITableViewCellSeparatorStyleSingleLine;
}

- (void)rebuildTableHeader {
	CGFloat width = self.tableView.bounds.size.width;
	if (width < 1)
		width = self.view.bounds.size.width;
	if (width < 1)
		width = [UIScreen mainScreen].applicationFrame.size.width;
	NSUInteger archivedCount = TGReplyArray([TGClient shared].archivedChats).count;
	BOOL hasArchive = !self.showsArchive && self.folderId == 0 && archivedCount > 0;
	if (!hasArchive)
		self.archiveRevealed = NO;
	BOOL archiveHidden = TGArchiveHiddenByDefault();
	BOOL showArchive = hasArchive && (!archiveHidden || self.archiveRevealed);
	BOOL showTray = !self.showsArchive && TGStoriesTrayEnabled() &&
			TGReplyArray(self.storyPosters).count > 0;
	BOOL showStrip = [self usesFolderStrip];
	BOOL showLogin = !self.showsArchive && self.unconfirmedSession != nil;
	BOOL showFolderBanner = !self.showsArchive && self.folderId != 0 &&
			self.folderNewChatsFolderId == self.folderId && self.folderNewChats.count > 0;
	CGFloat loginHeight = showLogin ? kLoginBannerHeight : 0;
	CGFloat folderBannerHeight = showFolderBanner ? kFolderBannerHeight : 0;
	CGFloat trayHeight = showTray ? kStoryTrayHeight : 0;
	CGFloat stripHeight = showStrip ? kFolderStripHeight : 0;
	CGFloat rowsTop = kSearchBarHeight + loginHeight + folderBannerHeight + trayHeight
			+ stripHeight;
	CGFloat height = rowsTop + (showArchive ? kRowHeight : 0);

	TGTheme *theme = [TGTheme shared];
	NSMutableString *signature = [NSMutableString stringWithFormat:
			@"%.1f|%lu|%d%d%d%d%d%d|%ld|%d|%@",
			width, (unsigned long)archivedCount,
			hasArchive, showArchive, showTray, showStrip, showLogin, showFolderBanner,
			(long)[self.listUnread[@(TGChatListArchive)] integerValue],
			theme.isDark, theme.importedName ?: @"-"];
	if (showTray)
		[signature appendFormat:@"|tray:%@", TGReplyArray(self.storyPosters)];
	if (showStrip)
		[signature appendFormat:@"|strip:%@", [self folderStripEntries]];
	if (showLogin)
		[signature appendFormat:@"|login:%@", self.unconfirmedSession];
	if (showFolderBanner)
		[signature appendFormat:@"|banner:%@", self.folderNewChats];

	if (self.tableView.tableHeaderView != nil &&
		[signature isEqualToString:self.headerSignature])
		return;
	self.headerSignature = signature;

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	header.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.searchBar.frame = CGRectMake(0, 0, width, kSearchBarHeight);
	[header addSubview:self.searchBar];

	if (showLogin)
		[header addSubview:[self loginBannerWithWidth:width top:kSearchBarHeight]];
	if (showFolderBanner)
		[header addSubview:[self folderInviteBannerWithWidth:width
														top:kSearchBarHeight + loginHeight]];
	if (showTray)
		[header addSubview:[self storyTrayWithWidth:width
												top:kSearchBarHeight + loginHeight
													+ folderBannerHeight]];
	if (showStrip)
		[header addSubview:[self folderStripWithWidth:width
												  top:kSearchBarHeight + loginHeight
													  + folderBannerHeight + trayHeight]];

	if (showArchive){
		TGChatCell *row = [self archiveHeaderRowWithWidth:width top:rowsTop
													count:archivedCount];
		[header addSubview:row];
		self.archiveRowView = row;

		UIView *hair = [[UIView alloc] initWithFrame:
				CGRectMake(0, height - 0.5f, width, 0.5f)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		[header addSubview:hair];
	} else {
		self.archiveRowView = nil;
	}

	self.tableView.tableHeaderView = header;
	self.headerHeight = height;
	self.archiveAvailable = hasArchive;
	self.archiveRowTop = rowsTop;
	[self pinHeaderIfSearchBarClipped];
	[self applyInitialScrollOffset];
}

- (void)pinHeaderIfSearchBarClipped {
	UITableView *table = self.tableView;
	if (table.dragging || table.decelerating || table.tracking)
		return;
	CGFloat shown = table.contentOffset.y + table.contentInset.top;
	if (shown <= 0 || shown >= kSearchBarHeight)
		return;
	CGFloat target = shown < kSearchBarHeight / 2 ? 0 : kSearchBarHeight;
	table.contentOffset = CGPointMake(0, target - table.contentInset.top);
}

- (void)applyInitialScrollOffset {
	if (self.initialScrollApplied || self.searchResults)
		return;
	UITableView *table = self.tableView;
	if (table.dragging || table.tracking || table.decelerating)
		return;
	if (table.bounds.size.height < 1)
		return;
	if (table.contentOffset.y + table.contentInset.top != 0)
		return;
	CGFloat reachable = table.contentSize.height - table.bounds.size.height
			+ table.contentInset.top + table.contentInset.bottom;
	if (reachable < kSearchBarHeight)
		return;
	self.initialScrollApplied = YES;
	table.contentOffset = CGPointMake(0, kSearchBarHeight - table.contentInset.top);
}

- (TGChatCell *)archiveHeaderRowWithWidth:(CGFloat)width top:(CGFloat)top count:(NSUInteger)archivedCount {
	TGChatCell *row = [[TGChatCell alloc] initWithStyle:UITableViewCellStyleDefault
										reuseIdentifier:nil];
	row.frame = CGRectMake(0, top, width, kRowHeight);
	row.titleLabel.text = @"Archived Chats";
	row.titleLabel.textColor = [[TGTheme shared] primaryTextColour];
	row.previewLabel.text = [NSString stringWithFormat:@"%lu chats",
			(unsigned long)archivedCount];
	row.previewLabel.textColor = [[TGTheme shared] secondaryTextColour];
	NSInteger archiveUnread = [self.listUnread[@(TGChatListArchive)] integerValue];
	if (archiveUnread > 0){
		row.badge.text = archiveUnread < 1000
				? [NSString stringWithFormat:@"%ld", (long)archiveUnread]
				: [NSString stringWithFormat:@"%ldK", (long)(archiveUnread / 1000)];
		row.badge.hidden = NO;
		row.badgeBackground.hidden = NO;
	}
	row.avatar.image = [TGIcons archiveAvatarOfSide:kAvatar];
	row.avatar.backgroundColor = [UIColor clearColor];
	row.backgroundColor = [[TGTheme shared] listBackgroundColour];
	row.userInteractionEnabled = YES;

	row.swipeActions = @[@{@"kind"  : @"archiveVisibility",
						   @"title" : (TGArchiveHiddenByDefault() ? @"Unhide" : @"Hide")}];
	__weak typeof(self) weakSelf = self;
	__weak TGChatCell *weakRow = row;
	row.onSwipeOpen = ^{
		[weakSelf closeOpenSwipeCellAnimated:YES];
		weakSelf.openSwipeCell = weakRow;
	};
	row.onSwipeAction = ^(NSString *__unused kind){
		[weakSelf toggleArchiveHiddenByDefaultFromCell:weakRow];
	};

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(archiveRowTapped)];
	tap.cancelsTouchesInView = NO;
	[row addGestureRecognizer:tap];
	[row setNeedsLayout];
	[row layoutIfNeeded];
	return row;
}

- (void)archiveRowTapped {
	if (self.openSwipeCell){
		[self closeOpenSwipeCellAnimated:YES];
		return;
	}
	[self openArchive];
}

- (UIView *)loginBannerWithWidth:(CGFloat)width top:(CGFloat)top {
	NSDictionary *session = self.unconfirmedSession;
	UIView *banner = [[UIView alloc] initWithFrame:
			CGRectMake(0, top, width, kLoginBannerHeight)];
	banner.backgroundColor = [UIColor colorWithRed:0xFF / 255.0f green:0xF9 / 255.0f
											  blue:0xD8 / 255.0f alpha:1.0f];

	NSString *device = TGReplyString(session[@"deviceModel"]);
	if (!device.length)
		device = TGReplyString(session[@"appName"]) ?: @"a new device";

	UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 7, width - 20, 18)];
	title.backgroundColor = [UIColor clearColor];
	title.font = [UIFont boldSystemFontOfSize:15];
	title.textColor = [UIColor colorWithRed:0x33 / 255.0f green:0x2C / 255.0f
									   blue:0x0A / 255.0f alpha:1.0f];
	title.lineBreakMode = NSLineBreakByTruncatingTail;
	title.text = [NSString stringWithFormat:@"New login from %@", device];
	[banner addSubview:title];

	NSMutableArray *detail = [NSMutableArray array];
	NSString *location = TGReplyString(session[@"location"]);
	NSString *ip = TGReplyString(session[@"ip"]);
	if (location.length)
		[detail addObject:location];
	if (ip.length)
		[detail addObject:ip];

	UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(10, 25, width - 20, 15)];
	subtitle.backgroundColor = [UIColor clearColor];
	subtitle.font = [UIFont systemFontOfSize:12];
	subtitle.textColor = [UIColor colorWithRed:0x6B / 255.0f green:0x62 / 255.0f
										  blue:0x35 / 255.0f alpha:1.0f];
	subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
	subtitle.text = detail.count ? [detail componentsJoinedByString:@" · "]
								 : @"Was this you?";
	[banner addSubview:subtitle];

	CGFloat buttonWidth = (int)((width - 30) / 2);
	UIButton *mine = [self bannerButtonWithTitle:@"It's Me"
										   frame:CGRectMake(10, 44, buttonWidth, 26)
										  action:@selector(confirmNewLogin)
									 destructive:NO];
	[banner addSubview:mine];
	UIButton *not = [self bannerButtonWithTitle:@"Not Me"
										  frame:CGRectMake(width - 10 - buttonWidth, 44,
														   buttonWidth, 26)
										 action:@selector(terminateNewLogin)
									destructive:YES];
	[banner addSubview:not];

	UIView *hair = [[UIView alloc] initWithFrame:
			CGRectMake(0, kLoginBannerHeight - 0.5f, width, 0.5f)];
	hair.backgroundColor = [[TGTheme shared] separatorColour];
	[banner addSubview:hair];
	return banner;
}

- (UIButton *)bannerButtonWithTitle:(NSString *)title
							  frame:(CGRect)frame
							 action:(SEL)action
						destructive:(BOOL)destructive {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = frame;
	button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
	[button setTitle:title forState:UIControlStateNormal];
	UIImage *plate = TGSwipePlateImage(destructive, NO);
	UIImage *pressed = TGSwipePlateImage(destructive, YES);
	if (plate){
		[button setBackgroundImage:plate forState:UIControlStateNormal];
		[button setBackgroundImage:(pressed ?: plate) forState:UIControlStateHighlighted];
	} else {
		button.backgroundColor = destructive
				? [UIColor colorWithRed:0xC4 / 255.0f green:0x2B / 255.0f
								   blue:0x1E / 255.0f alpha:1.0f]
				: [UIColor colorWithRed:0x8E / 255.0f green:0x9C / 255.0f
								   blue:0xAE / 255.0f alpha:1.0f];
		button.layer.cornerRadius = 4;
	}
	[button setTitleColor:(destructive ? [UIColor whiteColor]
									   : [UIColor colorWithRed:0x4a / 255.0f green:0x65 / 255.0f
														  blue:0x87 / 255.0f alpha:1.0f])
				 forState:UIControlStateNormal];
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (void)refreshUnconfirmedSession {
	if (self.showsArchive)
		return;
	static NSTimeInterval lastSweep = 0;
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - lastSweep < 30.0)
		return;
	lastSweep = now;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] unconfirmedSessionsWithCompletion:^(NSArray *sessions){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		NSDictionary *first = nil;
		for (id entry in (TGReplyArray(sessions) ?: @[])){
			NSDictionary *session = TGReplyDictionary(entry);
			if ([session[@"id"] longLongValue]){
				first = session;
				break;
			}
		}
		NSNumber *wasId = me.unconfirmedSession[@"id"];
		NSNumber *nowId = first[@"id"];
		BOOL changed = (wasId == nil) != (nowId == nil) ||
					   (nowId != nil && ![nowId isEqualToNumber:wasId]);
		me.unconfirmedSession = first;
		if (changed)
			[me rebuildTableHeader];
	}];
}

- (void)confirmNewLogin {
	long long sessionId = [self.unconfirmedSession[@"id"] longLongValue];
	self.unconfirmedSession = nil;
	[self rebuildTableHeader];
	if (sessionId)
		[[TGClient shared] confirmSession:sessionId completion:nil];
}

- (void)terminateNewLogin {
	long long sessionId = [self.unconfirmedSession[@"id"] longLongValue];
	self.unconfirmedSession = nil;
	[self rebuildTableHeader];
	if (!sessionId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] terminateSession:sessionId completion:^(BOOL ok){
		if (ok || !weakSelf)
			return;
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New Login"
														message:@"Could not end that session."
													   delegate:nil
											  cancelButtonTitle:@"OK"
											  otherButtonTitles:nil];
		[alert show];
	}];
}

- (void)refreshFolderNewChats {
	if (self.showsArchive || self.folderId == 0){
		if (self.folderNewChats.count){
			self.folderNewChats = nil;
			self.folderNewChatsFolderId = 0;
			[self rebuildTableHeader];
		}
		return;
	}

	NSInteger folderId = self.folderId;
	static NSTimeInterval lastSweep = 0;
	static NSInteger lastFolder = 0;
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (folderId == lastFolder && now - lastSweep < 30.0)
		return;
	lastSweep = now;
	lastFolder = folderId;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] newChatsInFolder:folderId completion:^(NSArray *reply){
		TGChatListViewController *me = weakSelf;
		if (!me || me.folderId != folderId)
			return;
		NSArray *rows = TGChatRows(reply);
		BOOL had = me.folderNewChats.count > 0 && me.folderNewChatsFolderId == folderId;
		me.folderNewChats = rows;
		me.folderNewChatsFolderId = folderId;
		if (had || rows.count)
			[me rebuildTableHeader];
	}];
}

- (UIView *)folderInviteBannerWithWidth:(CGFloat)width top:(CGFloat)top {
	NSUInteger count = self.folderNewChats.count;
	UIView *banner = [[UIView alloc] initWithFrame:
			CGRectMake(0, top, width, kFolderBannerHeight)];
	banner.backgroundColor = [UIColor colorWithRed:0xE8 / 255.0f green:0xF2 / 255.0f
											  blue:0xFD / 255.0f alpha:1.0f];

	UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, width - 20, 18)];
	title.backgroundColor = [UIColor clearColor];
	title.font = [UIFont boldSystemFontOfSize:15];
	title.textColor = [UIColor colorWithRed:0x14 / 255.0f green:0x2C / 255.0f
									   blue:0x4B / 255.0f alpha:1.0f];
	title.lineBreakMode = NSLineBreakByTruncatingTail;
	title.text = (count == 1)
			? @"This folder has 1 new chat"
			: [NSString stringWithFormat:@"This folder has %lu new chats", (unsigned long)count];
	[banner addSubview:title];

	CGFloat buttonWidth = (int)((width - 30) / 2);
	UIButton *add = [self bannerButtonWithTitle:@"Add Chats"
										  frame:CGRectMake(10, 28, buttonWidth, 26)
										 action:@selector(addNewFolderChats)
									destructive:NO];
	[banner addSubview:add];
	UIButton *skip = [self bannerButtonWithTitle:@"Dismiss"
										   frame:CGRectMake(width - 10 - buttonWidth, 28,
															buttonWidth, 26)
										  action:@selector(dismissNewFolderChats)
									 destructive:NO];
	[banner addSubview:skip];

	UIView *hair = [[UIView alloc] initWithFrame:
			CGRectMake(0, kFolderBannerHeight - 0.5f, width, 0.5f)];
	hair.backgroundColor = [[TGTheme shared] separatorColour];
	[banner addSubview:hair];
	return banner;
}

- (void)addNewFolderChats {
	NSInteger folderId = self.folderNewChatsFolderId;
	NSArray *rows = self.folderNewChats;
	if (!folderId || !rows.count)
		return;

	NSMutableArray *ids = [NSMutableArray array];
	NSMutableDictionary *titles = [NSMutableDictionary dictionary];
	for (NSDictionary *chat in rows){
		NSNumber *key = chat[@"id"];
		if (![key isKindOfClass:[NSNumber class]])
			continue;
		[ids addObject:key];
		NSString *name = TGReplyString(chat[@"title"]);
		if (name.length)
			titles[key] = name;
	}
	if (!ids.count)
		return;

	TGChatIdPickerViewController *picker = [[TGChatIdPickerViewController alloc] init];
	picker.title = @"New Chats";
	picker.prompt = @"Chats the folder's owner has added";
	picker.confirmTitle = @"Join";
	picker.chatIds = ids;
	picker.titles = titles;
	__weak typeof(self) weakSelf = self;
	picker.onConfirm = ^(NSArray *picked){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] addNewChats:(picked.count ? picked : nil) toFolder:folderId];
		me.folderNewChats = nil;
		[me rebuildTableHeader];
		[me reload];
	};
	[self.navigationController pushViewController:picker animated:YES];
}

- (void)dismissNewFolderChats {
	NSInteger folderId = self.folderNewChatsFolderId;
	self.folderNewChats = nil;
	[self rebuildTableHeader];
	if (folderId)
		[[TGClient shared] addNewChats:nil toFolder:folderId];
}

#pragma mark - folder invite links

- (void)askFolderInviteLink {
	UIAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Add Folder"
													message:@"Paste a folder invite link"
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Check", nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	UITextField *field = [alert textFieldAtIndex:0];
	field.keyboardType = UIKeyboardTypeURL;
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	alert.tag = 21;
	[alert show];
}

- (void)checkFolderInviteLink:(NSString *)link {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] checkFolderInviteLink:link completion:^(NSDictionary *reply){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		NSDictionary *info = TGReplyDictionary(reply);
		if (!info){
			UIAlertView *bad = [[UIAlertView alloc] initWithTitle:@"Add Folder"
														  message:@"That link is not valid any more."
														 delegate:nil
												cancelButtonTitle:@"OK"
												otherButtonTitles:nil];
			[bad show];
			return;
		}

		NSString *name = TGReplyString(info[@"title"]) ?: @"Folder";
		NSArray *missing = TGReplyArray(info[@"missingChatIds"]) ?: @[];
		if (!missing.count){
			[[TGClient shared] joinFolderByInviteLink:link chatIds:nil completion:^(BOOL ok){
				[me reportFolderJoin:ok name:name];
			}];
			return;
		}

		TGChatIdPickerViewController *picker = [[TGChatIdPickerViewController alloc] init];
		picker.title = name;
		picker.prompt = @"Chats to join with this folder";
		picker.confirmTitle = @"Join";
		picker.chatIds = missing;
		picker.onConfirm = ^(NSArray *picked){
			[[TGClient shared] joinFolderByInviteLink:link chatIds:picked completion:^(BOOL ok){
				[weakSelf reportFolderJoin:ok name:name];
			}];
		};
		[me.navigationController pushViewController:picker animated:YES];
	}];
}

- (void)reportFolderJoin:(BOOL)ok name:(NSString *)name {
	if (ok){
		[self reload];
		[self applyTitleView];
		[self rebuildTableHeader];
		return;
	}
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Add Folder"
													message:[NSString stringWithFormat:
															@"Telegram would not add \"%@\".", name ?: @""]
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

/// The strip of folders under the search bar, drawn with the search bar's own
/// scope-button artwork and the exact text attributes the original dialog list
/// gave its scope buttons.
- (UIView *)folderStripWithWidth:(CGFloat)width top:(CGFloat)top {
	UIView *strip = [[UIView alloc] initWithFrame:CGRectMake(0, top, width, kFolderStripHeight)];
	UIImage *background = TGScopeBarBackgroundImage();
	if (background){
		UIImageView *plate = [[UIImageView alloc] initWithImage:background];
		plate.frame = strip.bounds;
		[strip addSubview:plate];
	} else {
		strip.backgroundColor = [[TGTheme shared] listBackgroundColour];
	}

	UIScrollView *scroller = [[UIScrollView alloc] initWithFrame:strip.bounds];
	scroller.backgroundColor = [UIColor clearColor];
	scroller.showsHorizontalScrollIndicator = NO;
	[strip addSubview:scroller];

	UIImage *normalPlate = [[UIImage imageNamed:@"SearchBarScopeButton.png"]
			stretchableImageWithLeftCapWidth:6 topCapHeight:0];
	UIImage *selectedPlate = [[UIImage imageNamed:@"SearchBarScopeButton_Highlighted.png"]
			stretchableImageWithLeftCapWidth:6 topCapHeight:0];

	NSArray *entries = [self folderStripEntries];

	UIFont *font = [UIFont boldSystemFontOfSize:12];
	CGFloat x = 4;
	for (NSUInteger i = 0; i < entries.count; i++){
		UIButton *button = [self folderStripButtonForEntry:entries[i]
													  font:font
													  left:x
											   normalPlate:normalPlate
											 selectedPlate:selectedPlate];
		[scroller addSubview:button];
		x += button.frame.size.width + 4;
	}

	scroller.contentSize = CGSizeMake(x, kFolderStripHeight);

	if (!background){
		UIView *hair = [[UIView alloc] initWithFrame:
				CGRectMake(0, kFolderStripHeight - 0.5f, width, 0.5f)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		[strip addSubview:hair];
	}
	return strip;
}

- (NSArray *)folderStripEntries {
	NSMutableArray *entries = [NSMutableArray array];
	[entries addObject:@{@"title" : @"All Chats", @"folder" : @0}];
	for (id entry in [self folderList]){
		NSDictionary *folder = TGReplyDictionary(entry);
		[entries addObject:@{@"title" : (TGReplyString(folder[@"title"]) ?: @"Folder"),
							 @"folder" : ([folder[@"id"] isKindOfClass:[NSNumber class]]
									 ? folder[@"id"] : @0)}];
	}
	return entries;
}

- (UIButton *)folderStripButtonForEntry:(NSDictionary *)entry
								   font:(UIFont *)font
								   left:(CGFloat)left
							normalPlate:(UIImage *)normalPlate
						  selectedPlate:(UIImage *)selectedPlate {
	NSInteger listId = [entry[@"folder"] integerValue];
	NSString *caption = [entry[@"title"] stringByAppendingString:
			[self unreadSuffixForList:(TGChatListId)(listId ?: TGChatListMain)]];
	BOOL selected = (listId == self.folderId);

	CGFloat buttonWidth = (int)[caption sizeWithFont:font].width + 24;
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(left, (int)((kFolderStripHeight - 30) / 2), buttonWidth, 30);
	[button setBackgroundImage:(selected ? selectedPlate : normalPlate)
					  forState:UIControlStateNormal];
	[button setTitle:caption forState:UIControlStateNormal];
	button.titleLabel.font = font;
	[self styleFolderStripButton:button selected:selected];
	button.tag = listId;
	[button addTarget:self action:@selector(folderButtonTapped:)
	 forControlEvents:UIControlEventTouchUpInside];
	[button addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(folderButtonHeld:)]];
	return button;
}

- (void)styleFolderStripButton:(UIButton *)button selected:(BOOL)selected {
	if (selected){
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		button.titleLabel.shadowColor = [UIColor colorWithRed:0x11 / 255.0f
														green:0x2e / 255.0f
														 blue:0x5c / 255.0f alpha:0.2f];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	} else {
		[button setTitleColor:[UIColor colorWithRed:0x5c / 255.0f green:0x70 / 255.0f
											   blue:0x8b / 255.0f alpha:1.0f]
					 forState:UIControlStateNormal];
		button.titleLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.25f];
		button.titleLabel.shadowOffset = CGSizeMake(0, 1);
	}
}

- (void)folderButtonHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	UIView *button = hold.view;
	if (!button)
		return;
	NSInteger listId = button.tag;

	UIView *host = self.navigationController.view ?: self.view;
	CGPoint where = [button.superview convertPoint:
			CGPointMake(CGRectGetMidX(button.frame), CGRectGetMaxY(button.frame)) toView:host];

	NSArray *items = @[
		@{@"title" : @"Mark All as Read", @"icon" : @"chat"},
		@{@"title" : @"Add Folder from Link…", @"icon" : @"folder"},
		@{@"title" : @"Edit Folders", @"icon" : @"folder"},
	];
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:host
				  onChoice:^(NSInteger choice, NSString *title){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		if (choice == 0){
			[[TGClient shared] markListAsRead:(TGChatListId)(listId ?: TGChatListMain)];
			[me reload];
		} else if (choice == 1){
			[me askFolderInviteLink];
		} else if (choice == 2){
			[me openFolderManagement];
		}
	}];
}

- (void)folderButtonTapped:(UIButton *)button {
	if (self.folderId == button.tag)
		return;
	self.folderId = button.tag;
	self.folderLimit = 60;
	[self applyTitleView];
	[self reload];
}

- (UIView *)storyTrayWithWidth:(CGFloat)width top:(CGFloat)top {
	TGTheme *theme = [TGTheme shared];
	UIView *band = [[UIView alloc] initWithFrame:CGRectMake(0, top, width, kStoryTrayHeight)];
	UIImage *plateImage = theme.isDark ? nil : TGScopeBarBackgroundImage();
	if (plateImage){
		UIImageView *plate = [[UIImageView alloc] initWithImage:plateImage];
		plate.frame = band.bounds;
		[band addSubview:plate];
	} else {
		band.backgroundColor = theme.isDark
				? [UIColor colorWithWhite:0.11f alpha:1.0f]
				: [UIColor colorWithRed:0xE4 / 255.0f green:0xE9 / 255.0f
								   blue:0xF0 / 255.0f alpha:1.0f];
	}

	UIScrollView *tray = [[UIScrollView alloc] initWithFrame:band.bounds];
	tray.backgroundColor = [UIColor clearColor];
	tray.showsHorizontalScrollIndicator = NO;
	[band addSubview:tray];

	CGFloat x = 8;
	for (NSUInteger i = 0; i < self.storyPosters.count; i++){
		UIView *cell = [self storyTrayCellForPoster:self.storyPosters[i] index:i left:x];
		[tray addSubview:cell];
		x += kStoryCellWidth;
	}
	tray.contentSize = CGSizeMake(x + 8, kStoryTrayHeight);

	if (!plateImage){
		UIView *hair = [[UIView alloc] initWithFrame:
				CGRectMake(0, kStoryTrayHeight - 0.5f, width, 0.5f)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		[band addSubview:hair];
	}
	return band;
}

- (UIView *)storyTrayCellForPoster:(NSDictionary *)poster index:(NSUInteger)index left:(CGFloat)x {
	TGTheme *theme = [TGTheme shared];
	BOOL unread = [poster[@"unread"] boolValue];

	UIView *cell = [[UIView alloc] initWithFrame:CGRectMake(x, 0, kStoryCellWidth, kStoryTrayHeight)];
	cell.backgroundColor = [UIColor clearColor];
	cell.tag = (NSInteger)index;

	UIView *ring = [[UIView alloc] initWithFrame:CGRectMake(4, 4, kStoryAvatar + 4, kStoryAvatar + 4)];
	ring.backgroundColor = [UIColor clearColor];
	ring.layer.cornerRadius = 7;
	ring.layer.borderWidth = 2;
	ring.layer.borderColor = unread
			? [theme accentColour].CGColor
			: [UIColor colorWithRed:0xC3 / 255.0f green:0xCB / 255.0f
							   blue:0xD6 / 255.0f alpha:1.0f].CGColor;
	[cell addSubview:ring];

	UIImageView *avatar = [[UIImageView alloc] initWithFrame:
			CGRectMake(6, 6, kStoryAvatar, kStoryAvatar)];
	avatar.layer.cornerRadius = 5;
	avatar.clipsToBounds = YES;
	avatar.contentMode = UIViewContentModeScaleAspectFill;
	NSNumber *fileId = poster[@"photoFileId"];
	UIImage *photo = fileId ? self.avatars[fileId] : nil;
	if (!photo){
		NSString *title = TGReplyString(poster[@"title"]) ?: @"";
		photo = [TGIcons avatarWithInitials:(title.length
				? [title substringToIndex:1].uppercaseString : @"?")
									   size:kStoryAvatar
								   colourId:[poster[@"chatId"] longLongValue]];
	}
	avatar.image = photo;
	[cell addSubview:avatar];

	UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(0, 64, kStoryCellWidth, 13)];
	name.backgroundColor = [UIColor clearColor];
	name.font = [UIFont systemFontOfSize:11];
	name.textAlignment = NSTextAlignmentCenter;
	name.lineBreakMode = NSLineBreakByTruncatingTail;
	name.textColor = unread ? [theme primaryTextColour] : [theme secondaryTextColour];
	name.text = TGReplyString(poster[@"title"]) ?: @"";
	[cell addSubview:name];

	[cell addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(storyCellTapped:)]];
	return cell;
}

- (void)storyCellTapped:(UITapGestureRecognizer *)tap {
	NSInteger index = tap.view.tag;
	if (index < 0 || index >= (NSInteger)self.storyPosters.count)
		return;

	TGStoryViewController *viewer = [[TGStoryViewController alloc] init];
	viewer.posters = self.storyPosters;
	viewer.posterIndex = index;
	viewer.storyIndex = 0;
	[self.navigationController pushViewController:viewer animated:YES];
}

/// TDLib has no "who has stories" list of its own, so the tray is built by
/// asking each chat near the top of the list whether it has active stories -
/// the same shape as the unread sweep above.
- (void)refreshStoryPosters {
	if (self.showsArchive || !TGStoriesTrayEnabled()){
		if (self.storyPosters.count){
			self.storyPosters = nil;
			[self rebuildTableHeader];
		}
		return;
	}

	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - self.lastStorySweep < 20.0 &&
		(self.storyPosters || self.storyProbesPending > 0))
		return;
	self.lastStorySweep = now;

	NSArray *candidates = self.chats;
	if (candidates.count > 40)
		candidates = [candidates subarrayWithRange:NSMakeRange(0, 40)];

	NSMutableSet *probed = [NSMutableSet set];
	for (NSDictionary *chat in candidates)
		[probed addObject:@([chat[@"id"] longLongValue])];
	NSMutableDictionary *kept = [NSMutableDictionary dictionary];
	for (NSNumber *known in self.storyPostersById){
		if (![probed containsObject:known])
			kept[known] = self.storyPostersById[known];
	}

	self.storyPostersById = kept;
	self.storyProbesPending = (NSInteger)candidates.count;
	if (!candidates.count){
		[self commitStoryPosters];
		return;
	}

	__weak typeof(self) weakSelf = self;
	for (NSDictionary *chat in candidates){
		int64_t chatId = [chat[@"id"] longLongValue];
		NSString *title = TGReplyString(chat[@"title"]) ?: @"";
		id fileId = [chat[@"photoFileId"] isKindOfClass:[NSNumber class]] ? chat[@"photoFileId"] : nil;
		[[TGClient shared] activeStoriesForChat:chatId completion:^(NSDictionary *reply){
			TGChatListViewController *me = weakSelf;
			if (!me)
				return;
			NSDictionary *active = TGReplyDictionary(reply);
			NSArray *stories = TGReplyArray(active[@"stories"]);
			if (stories.count && ![active[@"archived"] boolValue]){
				NSMutableDictionary *poster = [NSMutableDictionary dictionary];
				poster[@"chatId"] = @(chatId);
				poster[@"title"] = title;
				poster[@"stories"] = stories;
				poster[@"order"] = active[@"order"] ?: @0;
				poster[@"unread"] = active[@"unread"] ?: @NO;
				if (fileId)
					poster[@"photoFileId"] = fileId;
				me.storyPostersById[@(chatId)] = poster;
			}
			me.storyProbesPending -= 1;
			if (me.storyProbesPending <= 0)
				[me commitStoryPosters];
		}];
	}
}

- (void)commitStoryPosters {
	NSArray *sorted = [self.storyPostersById.allValues sortedArrayUsingComparator:
			^NSComparisonResult(NSDictionary *a, NSDictionary *b){
		BOOL unreadA = [a[@"unread"] boolValue];
		BOOL unreadB = [b[@"unread"] boolValue];
		if (unreadA != unreadB)
			return unreadA ? NSOrderedAscending : NSOrderedDescending;
		long long orderA = [a[@"order"] longLongValue];
		long long orderB = [b[@"order"] longLongValue];
		if (orderA == orderB)
			return NSOrderedSame;
		return orderA > orderB ? NSOrderedAscending : NSOrderedDescending;
	}];

	BOOL had = self.storyPosters.count > 0;
	self.storyPosters = sorted;
	if (had || sorted.count)
		[self rebuildTableHeader];
}

/// The bar in the header is a way in, not a place to type: touching it hands
/// over to the search page, which has room for the results and the keyboard.
- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
	TGSearchViewController *search = [[TGSearchViewController alloc] init];
	[self.navigationController pushViewController:search animated:YES];
	return NO;
}

/// barTintColor paints the bar around the field but leaves the field itself
/// white, which on a dark list is a slab of light at the top. barStyle is what
/// turns the field over too.
- (void)styleSearchBar {
	TGTheme *theme = [TGTheme shared];
	self.searchBar.barStyle = theme.isDark ? UIBarStyleBlack : UIBarStyleDefault;
	if ([self.searchBar respondsToSelector:@selector(setBackgroundImage:)]){
		BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
		[self.searchBar setBackgroundImage:(plainPlate
				? [UIImage imageNamed:@"SearchBarBackground.png"] : nil)];
	}
	if ([self.searchBar respondsToSelector:@selector(setBarTintColor:)]){
		self.searchBar.barTintColor = [theme listBackgroundColour];
		[self.searchBar tg_setTintColor:[theme accentColour]];
	} else {
		[self.searchBar tg_setTintColor:[UIColor colorWithWhite:0.68f alpha:1.0f]];
	}
}

- (BOOL)splitLayoutActive {
	return [RootViewController isSplitLayoutActive];
}

- (void)presentChatController:(UIViewController *)controller {
	if (![self splitLayoutActive]){
		[self.navigationController pushViewController:controller animated:YES];
		return;
	}
	if (![RootViewController presentInDetail:controller])
		[self.navigationController pushViewController:controller animated:YES];
}

/// Saved Messages is your own chat; it is not always in the list, and every
/// client keeps a way in regardless.
- (void)openSavedMessages {
	int64_t chatId = [[TGClient shared] savedMessagesChatId];
	if (!chatId)
		return;
	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = chatId;
	vc.chatTitle = @"Saved Messages";
	[self presentChatController:vc];
}

- (void)composeTapped {
	[self closeOpenSwipeCellAnimated:NO];
	self.sheetItems = @[
		@{@"kind" : @"newMessage", @"title" : @"New Message"},
		@{@"kind" : @"addStory",   @"title" : @"Add Story"},
	];
	[self presentSheetForItemsWithTitle:@"Compose" cancelTitle:@"Cancel"];
}

- (void)startNewMessage {
	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	contacts.title = @"New Message";
	contacts.isPickerMode = YES;
	[self.navigationController pushViewController:contacts animated:YES];
}

- (void)reload {
	self.openSwipeCell = nil;
	[self reportFirstRows];
	[self refreshUnconfirmedSession];
	if (self.showsArchive){
		self.chats = TGChatRows([TGClient shared].archivedChats);
		[self.tableView reloadData];
		[self applyInitialScrollOffset];
		[self fetchMissingAvatars];
		[self refreshUnreadCounters];
		return;
	}

	if (self.folderId != 0){
		__weak typeof(self) weakSelf = self;
		NSInteger requested = self.folderId;
		[[TGClient shared] chatsInList:(TGChatListId)self.folderId limit:self.folderLimit
							completion:^(NSArray *reply){
			TGChatListViewController *me = weakSelf;
			if (!me || me.folderId != requested)
				return;
			me.loadingMore = NO;
			me.chats = TGChatRows(reply);
			[me.tableView reloadData];
			[me refreshUnreadCounters];
			[me rebuildTableHeader];
			[me fetchMissingAvatars];
			[me refreshStoryPosters];
			[me refreshFolderNewChats];
		}];
		return;
	}

	self.chats = TGChatRows([TGClient shared].chats);
	self.loadingMore = NO;
	[self.tableView reloadData];
	[self refreshUnreadCounters];
	[self rebuildTableHeader];
	[self fetchMissingAvatars];
	[self refreshStoryPosters];
	[self refreshFolderNewChats];
}

- (void)refreshUnreadCounters {
	TGClient *client = [TGClient shared];
	NSDictionary *main = TGReplyDictionary([client unreadSummaryForList:TGChatListMain]);
	if ([main[@"messages"] isKindOfClass:[NSNumber class]])
		self.listUnread[@(TGChatListMain)] = main[@"messages"];
	NSDictionary *archive = TGReplyDictionary([client unreadSummaryForList:TGChatListArchive]);
	if ([archive[@"messages"] isKindOfClass:[NSNumber class]])
		self.listUnread[@(TGChatListArchive)] = archive[@"messages"];

	static NSTimeInterval lastFolderSweep = 0;
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - lastFolderSweep < 5.0)
		return;
	lastFolderSweep = now;

	__weak typeof(self) weakSelf = self;
	for (id entry in (TGReplyArray(client.folders) ?: @[])){
		NSDictionary *folder = TGReplyDictionary(entry);
		NSInteger listId = [folder[@"id"] integerValue];
		if (listId == 0)
			continue;
		[client chatsInList:(TGChatListId)listId limit:100 completion:^(NSArray *reply){
			TGChatListViewController *me = weakSelf;
			if (!me)
				return;
			NSInteger total = 0;
			for (id item in (TGReplyArray(reply) ?: @[]))
				total += [TGReplyDictionary(item)[@"unread"] integerValue];
			me.listUnread[@(listId)] = @(total);
		}];
	}
}

- (NSString *)unreadSuffixForList:(TGChatListId)list {
	NSInteger count = [self.listUnread[@(list)] integerValue];
	if (count <= 0)
		return @"";
	return [NSString stringWithFormat:@"  (%ld)", (long)count];
}

- (void)loadMoreIfNeeded {
	if (self.searchResults || self.loadingMore)
		return;
	UITableView *table = self.tableView;
	CGFloat bottom = table.contentOffset.y + table.bounds.size.height;
	if (table.contentSize.height <= 0 || bottom < table.contentSize.height - kRowHeight * 2)
		return;

	self.loadingMore = YES;
	if (self.folderId != 0){
		if ((NSInteger)self.chats.count < self.folderLimit){
			self.loadingMore = NO;
			return;
		}
		self.folderLimit += 60;
		[[TGClient shared] loadMoreChatsInList:(TGChatListId)self.folderId limit:60];
		[self reload];
		return;
	}
	[[TGClient shared] loadMoreChatsInList:[self currentListId] limit:60];
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		weakSelf.loadingMore = NO;
	});
}

/// Nothing sits above the chats any more. The archive lives in the table's
/// header, hidden above the top of the list until you pull down for it - which
/// is where Telegram keeps it - and Saved Messages is simply a chat, because
/// pinning your own notes to the top of the list is not something it does.
- (NSArray *)headerRows {
	return @[];
}

- (BOOL)hasArchiveRow {
	return NO;
}

- (void)openArchive {
	TGChatListViewController *archive = [[TGChatListViewController alloc] init];
	archive.showsArchive = YES;
	[self.navigationController pushViewController:archive animated:YES];
}

/// Which chat list this screen is showing, in the terms TGClient+ChatList uses.
- (TGChatListId)currentListId {
	if (self.showsArchive)
		return TGChatListArchive;
	if (self.folderId != 0)
		return (TGChatListId)self.folderId;
	return TGChatListMain;
}

- (void)presentSheet:(UIActionSheet *)sheet {
	UITabBar *tabBar = [self.tabBarController isKindOfClass:UITabBarController.class]
			? self.tabBarController.tabBar : nil;
	if (tabBar)
		[sheet showFromTabBar:tabBar];
	else
		[sheet showInView:self.view];
}

- (void)presentSheetForItemsWithTitle:(NSString *)title cancelTitle:(NSString *)cancelTitle {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	sheet.tag = 1;
	for (NSDictionary *item in self.sheetItems)
		[sheet addButtonWithTitle:item[@"title"]];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:cancelTitle];
	[self presentSheet:sheet];
}

/// Folders are a filter over the same chats, offered as a choice, with the way
/// into managing them at the end of the same list.
- (void)foldersTapped {
	NSArray *folders = [self folderList];

	NSMutableArray *items = [NSMutableArray array];
	[items addObject:@{@"kind"   : @"list",
					   @"title"  : [NSString stringWithFormat:@"%@All Chats%@",
										   (self.folderId == 0 ? @"✓ " : @""),
										   [self unreadSuffixForList:TGChatListMain]],
					   @"folder" : @0}];
	for (id entry in folders){
		NSDictionary *f = TGReplyDictionary(entry);
		NSInteger listId = [f[@"id"] integerValue];
		if (!listId)
			continue;
		NSString *name = TGReplyString(f[@"title"]) ?: @"Folder";
		[items addObject:@{@"kind"   : @"list",
						   @"title"  : [NSString stringWithFormat:@"%@%@%@",
											   (self.folderId == listId ? @"✓ " : @""), name,
											   [self unreadSuffixForList:(TGChatListId)listId]],
						   @"folder" : @(listId)}];
	}
	[items addObject:@{@"kind" : @"folderLink", @"title" : @"Add Folder from Link…"}];
	self.sheetItems = items;

	[self presentSheetForItemsWithTitle:(folders.count ? @"Show"
													  : @"This account has no chat folders yet")
							cancelTitle:@"Cancel"];
}

- (void)listOptionsTapped {
	self.sheetItems = @[
		@{@"kind" : @"markAllRead", @"title" : @"Mark All as Read"},
	];

	[self presentSheetForItemsWithTitle:[self defaultTitle] cancelTitle:@"Cancel"];
}

- (void)actionsTapped {
	[self closeOpenSwipeCellAnimated:NO];
	if (self.showsArchive){
		[self archiveOptionsTapped];
		return;
	}
	[self listOptionsTapped];
}

- (void)selectChatListWithFolderId:(NSInteger)folderId {
	if (self.folderId == folderId)
		return;
	self.folderId = folderId;
	self.folderLimit = 60;
	[self applyTitleView];
	[self reload];
}

- (void)addStory {
	__weak typeof(self) weakSelf = self;
	[TGStoryComposer presentFrom:self completion:^(BOOL posted){
		TGChatListViewController *me = weakSelf;
		if (!me || !posted)
			return;
		me.lastStorySweep = 0;
		[[TGClient shared] loadActiveStoriesArchived:NO];
		[me refreshStoryPosters];
	}];
}

- (void)openFolderManagement {
	TGFoldersViewController *folders = [[TGFoldersViewController alloc] init];
	folders.page = TGFoldersPageList;
	[self.navigationController pushViewController:folders animated:YES];
}

- (void)markCurrentListAsRead {
	[[TGClient shared] markListAsRead:[self currentListId]];
	[self reload];
}

/// The archive's own actions: read it all at once, and the three settings that
/// decide what lands in here on its own.
- (void)archiveOptionsTapped {
	self.sheetItems = @[
		@{@"kind" : @"markAllRead", @"title" : @"Mark All as Read"},
		@{@"kind" : @"archiveSettings", @"title" : @"Archive Settings"},
	];
	[self presentSheetForItemsWithTitle:@"Archived Chats" cancelTitle:@"Cancel"];
}

- (void)showArchiveSettings {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] archiveSettingsWithCompletion:^(NSDictionary *reply){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		me.archiveSettings = TGReplyDictionary(reply) ?: @{};

		NSArray *keys = @[@"archiveUnknownSenders", @"keepUnmutedArchived", @"keepFoldersArchived"];
		NSArray *names = @[@"Archive new chats from unknown senders",
						   @"Keep unmuted chats archived",
						   @"Keep chats from folders archived"];
		NSMutableArray *items = [NSMutableArray array];
		for (NSUInteger i = 0; i < keys.count; i++){
			BOOL on = [me.archiveSettings[keys[i]] boolValue];
			[items addObject:@{@"kind"  : @"toggleArchive",
							   @"key"   : keys[i],
							   @"title" : [NSString stringWithFormat:@"%@%@",
											   (on ? @"✓ " : @""), names[i]]}];
		}
		me.sheetItems = items;

		[me presentSheetForItemsWithTitle:@"Archive Settings" cancelTitle:@"Done"];
	}];
}

- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;
	if (index < 0 || index >= (NSInteger)self.sheetItems.count)
		return;

	NSDictionary *item = self.sheetItems[index];
	NSString *kind = item[@"kind"];

	if ([kind isEqualToString:@"list"]){
		[self showFolderFromSheetItem:item];
	} else if ([kind isEqualToString:@"markAllRead"]){
		[self markCurrentListAsRead];
	} else if ([kind isEqualToString:@"editFolders"]){
		[self openFolderManagement];
	} else if ([kind isEqualToString:@"newMessage"]){
		[self startNewMessage];
	} else if ([kind isEqualToString:@"addStory"]){
		[self addStory];
	} else if ([kind isEqualToString:@"folderLink"]){
		[self askFolderInviteLink];
	} else if ([kind isEqualToString:@"archiveSettings"]){
		[self showArchiveSettings];
	} else if ([kind isEqualToString:@"toggleArchive"]){
		[self toggleArchiveSettingWithKey:item[@"key"]];
	}
}

- (void)showFolderFromSheetItem:(NSDictionary *)item {
	self.folderId = [item[@"folder"] integerValue];
	self.folderLimit = 60;
	[self applyTitleView];
	[self reload];
}

- (void)toggleArchiveSettingWithKey:(NSString *)key {
	NSMutableDictionary *next = [(self.archiveSettings ?: @{}) mutableCopy];
	next[key] = @(![next[key] boolValue]);
	[[TGClient shared] setArchiveSettings:next];
	self.archiveSettings = next;
	[self showArchiveSettings];
}

static UIImage *TGAvatarThumbnail(UIImage *source, CGFloat sidePoints) {
	if (!source || sidePoints < 1)
		return source;
	CGSize points = source.size;
	if (points.width < 1 || points.height < 1)
		return source;
	CGFloat screenScale = [UIScreen mainScreen].scale;
	if (screenScale < 1.0f)
		screenScale = 1.0f;
	CGFloat shortSidePixels = MIN(points.width, points.height) * source.scale;
	if (shortSidePixels <= sidePoints * screenScale + 0.5f)
		return source;

	CGFloat factor = MAX(sidePoints / points.width, sidePoints / points.height);
	CGSize target = CGSizeMake(points.width * factor, points.height * factor);
	if (UIGraphicsBeginImageContextWithOptions != NULL)
		UIGraphicsBeginImageContextWithOptions(target, NO, 0.0f);
	else
		UIGraphicsBeginImageContext(target);
	[source drawInRect:CGRectMake(0, 0, target.width, target.height)];
	UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return scaled ?: source;
}

- (NSSet *)avatarFileIdsInUse {
	NSMutableSet *keep = [NSMutableSet set];
	NSArray *rows = [self visibleChats];
	NSInteger headerCount = (NSInteger)[self headerRows].count;
	for (NSIndexPath *path in ([self.tableView indexPathsForVisibleRows] ?: @[])){
		NSInteger index = path.row - headerCount;
		if (index < 0 || index >= (NSInteger)rows.count)
			continue;
		id fileId = rows[index][@"photoFileId"];
		if ([fileId isKindOfClass:[NSNumber class]])
			[keep addObject:fileId];
	}
	for (NSDictionary *poster in (self.storyPosters ?: @[])){
		id fileId = poster[@"photoFileId"];
		if ([fileId isKindOfClass:[NSNumber class]])
			[keep addObject:fileId];
	}
	return keep;
}

- (void)dropAvatar:(id)fileId {
	[self.avatars removeObjectForKey:fileId];
	[self.avatarsRequested removeObject:fileId];
	[self.avatarsFailedOnce removeObject:fileId];
	if ([self.avatarsInFlight containsObject:fileId]){
		[self.avatarsInFlight removeObject:fileId];
		[[TGClient shared] cancelDownloadOfFile:[fileId integerValue] onlyIfPending:NO];
	}
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	[self pruneRowDetails];
	NSSet *keep = [self avatarFileIdsInUse];
	for (id fileId in [self.avatars.allKeys copy]){
		if ([keep containsObject:fileId])
			continue;
		[self dropAvatar:fileId];
	}
}

- (NSSet *)avatarFileIdsWanted {
	NSMutableSet *wanted = [NSMutableSet set];
	NSArray *rows = [self visibleChats];
	NSInteger headerCount = (NSInteger)[self headerRows].count;

	NSInteger first = NSIntegerMax;
	NSInteger last = -1;
	for (NSIndexPath *path in ([self.tableView indexPathsForVisibleRows] ?: @[])){
		first = MIN(first, path.row);
		last = MAX(last, path.row);
	}
	if (last < 0){
		first = headerCount;
		last = headerCount + kAvatarPrefetchRows;
	} else {
		first -= kAvatarPrefetchRows;
		last += kAvatarPrefetchRows;
	}

	for (NSInteger row = first; row <= last; row++){
		NSInteger index = row - headerCount;
		if (index < 0 || index >= (NSInteger)rows.count)
			continue;
		id fileId = rows[index][@"photoFileId"];
		if ([fileId isKindOfClass:[NSNumber class]])
			[wanted addObject:fileId];
	}
	for (NSDictionary *poster in (self.storyPosters ?: @[])){
		id fileId = poster[@"photoFileId"];
		if ([fileId isKindOfClass:[NSNumber class]])
			[wanted addObject:fileId];
	}
	return wanted;
}

- (BOOL)storyPostersUseAvatarFileId:(NSNumber *)fileId {
	for (NSDictionary *poster in (self.storyPosters ?: @[]))
		if ([fileId isEqual:poster[@"photoFileId"]])
			return YES;
	return NO;
}

- (NSDictionary *)chatShownByCell:(TGChatCell *)cell {
	long long chatId = cell.chatId;
	if (!chatId)
		return nil;
	for (NSDictionary *c in [self visibleChats]){
		if ([c[@"id"] longLongValue] == chatId)
			return c;
	}
	return nil;
}

- (TGChatCell *)cellShowingChatId:(long long)chatId {
	if (!chatId)
		return nil;
	for (UITableViewCell *raw in ([self.tableView visibleCells] ?: @[])){
		if (![raw isKindOfClass:[TGChatCell class]])
			continue;
		if (((TGChatCell *)raw).chatId == chatId)
			return (TGChatCell *)raw;
	}
	return nil;
}

- (void)applyArrivedAvatar:(UIImage *)image forFileId:(NSNumber *)fileId {
	NSMutableSet *owners = [NSMutableSet set];
	for (NSDictionary *c in [self visibleChats]){
		if ([fileId isEqual:c[@"photoFileId"]] && ![c[@"isSaved"] boolValue])
			[owners addObject:@([c[@"id"] longLongValue])];
	}
	if (!owners.count){
		if ([self storyPostersUseAvatarFileId:fileId])
			[self rebuildTableHeader];
		return;
	}

	for (UITableViewCell *raw in ([self.tableView visibleCells] ?: @[])){
		if (![raw isKindOfClass:[TGChatCell class]])
			continue;
		TGChatCell *cell = (TGChatCell *)raw;
		if (!cell.chatId || ![owners containsObject:@(cell.chatId)])
			continue;
		if (cell.avatar.image == image)
			continue;
		UIImageView *target = cell.avatar;
		[UIView transitionWithView:target
						  duration:0.2
						   options:UIViewAnimationOptionTransitionCrossDissolve
						animations:^{ target.image = image; }
						completion:nil];
	}
	if ([self storyPostersUseAvatarFileId:fileId])
		[self rebuildTableHeader];
}

- (void)reportFirstRows {
	static NSUInteger lastCount = 0;
	static NSTimeInterval firstSeen = 0;
	if (self.showsArchive)
		return;
	NSUInteger count = [TGClient shared].chats.count;
	if (!count || count == lastCount)
		return;
	if (firstSeen <= 0)
		firstSeen = [NSDate timeIntervalSinceReferenceDate];
	if ([NSDate timeIntervalSinceReferenceDate] - firstSeen > 20.0)
		return;
	lastCount = count;
	TGMarkLaunchStage([NSString stringWithFormat:@"chat list has %lu rows",
			(unsigned long)count]);
}

static NSString *TGAvatarDiskKey(NSNumber *fileId, long long ownerChatId) {
	if (!ownerChatId)
		return nil;
	return [NSString stringWithFormat:@"chatavatar_%lld_%@_%d",
			ownerChatId, fileId, (int)kAvatar];
}

static CGFloat TGAvatarScale(void) {
	CGFloat scale = [UIScreen mainScreen].scale;
	return scale < 1.0f ? 1.0f : scale;
}

- (long long)avatarOwnerChatIdForFileId:(NSNumber *)fileId {
	for (NSDictionary *c in [self visibleChats]){
		if ([fileId isEqual:c[@"photoFileId"]])
			return [c[@"id"] longLongValue];
	}
	for (NSDictionary *poster in (self.storyPosters ?: @[])){
		if ([fileId isEqual:poster[@"photoFileId"]])
			return [poster[@"chatId"] longLongValue];
	}
	return 0;
}

- (void)startAvatarDownload:(NSNumber *)fileId {
	[self.avatarsRequested addObject:fileId];
	[self.avatarsInFlight addObject:fileId];

	NSString *key = TGAvatarDiskKey(fileId, [self avatarOwnerChatIdForFileId:fileId]);
	if (!key){
		[self downloadAvatar:fileId key:nil];
		return;
	}

	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		UIImage *cached = [TGDiskCache imageForKey:key scale:TGAvatarScale()];
		dispatch_async(dispatch_get_main_queue(), ^{
			TGChatListViewController *me = weakSelf;
			if (!me || ![me.avatarsRequested containsObject:fileId])
				return;
			if (!cached){
				[me downloadAvatar:fileId key:key];
				return;
			}
			[me.avatarsInFlight removeObject:fileId];
			[me.avatarsFailedOnce removeObject:fileId];
			me.avatars[fileId] = cached;
			[me applyArrivedAvatar:cached forFileId:fileId];
		});
	});
}

- (void)downloadAvatar:(NSNumber *)fileId key:(NSString *)key {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *reply){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		[me.avatarsInFlight removeObject:fileId];

		NSString *path = TGReplyString(reply);
		if (!path.length){
			[me avatarFailed:fileId];
			return;
		}

		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			UIImage *img = nil;
			@autoreleasepool {
				img = TGAvatarThumbnail([UIImage imageWithContentsOfFile:path], kAvatar);
			}
			if (img && key.length)
				[TGDiskCache storeImage:img forKey:key];
			dispatch_async(dispatch_get_main_queue(), ^{
				TGChatListViewController *inner = weakSelf;
				if (!inner)
					return;
				if (!img){
					[inner avatarFailed:fileId];
					return;
				}
				[inner.avatarsFailedOnce removeObject:fileId];
				inner.avatars[fileId] = img;
				[inner applyArrivedAvatar:img forFileId:fileId];
			});
		});
	}];
}

- (void)avatarFailed:(NSNumber *)fileId {
	if (![self.avatarsRequested containsObject:fileId])
		return;
	if ([self.avatarsFailedOnce containsObject:fileId])
		return;
	[self.avatarsFailedOnce addObject:fileId];
	[self.avatarsRequested removeObject:fileId];
}

- (void)fetchMissingAvatars {
	self.lastAvatarSweep = [NSDate timeIntervalSinceReferenceDate];
	NSSet *wanted = [self avatarFileIdsWanted];

	for (NSNumber *fileId in [self.avatarsInFlight allObjects]){
		if ([wanted containsObject:fileId])
			continue;
		[self.avatarsInFlight removeObject:fileId];
		[self.avatarsRequested removeObject:fileId];
		[[TGClient shared] cancelDownloadOfFile:[fileId integerValue] onlyIfPending:NO];
	}

	for (NSNumber *fileId in wanted){
		if (self.avatars[fileId] || [self.avatarsRequested containsObject:fileId])
			continue;
		[self startAvatarDownload:fileId];
	}
}

- (void)fetchMissingAvatarsThrottled {
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - self.lastAvatarSweep < 0.15)
		return;
	[self fetchMissingAvatars];
}

- (void)describeCell:(TGChatCell *)cell unread:(NSInteger)unread muted:(BOOL)muted {
	NSMutableArray *parts = [NSMutableArray array];
	if (cell.titleLabel.text.length)
		[parts addObject:cell.titleLabel.text];
	if (!cell.draftLabel.hidden)
		[parts addObject:@"draft"];
	if (cell.previewLabel.text.length)
		[parts addObject:cell.previewLabel.text];
	if (cell.dateLabel.text.length)
		[parts addObject:cell.dateLabel.text];
	if (unread == 1)
		[parts addObject:@"1 unread message"];
	else if (unread > 1)
		[parts addObject:[NSString stringWithFormat:@"%ld unread messages", (long)unread]];
	if (muted)
		[parts addObject:@"muted"];

	cell.isAccessibilityElement = YES;
	cell.accessibilityLabel = [parts componentsJoinedByString:@", "];
	cell.accessibilityTraits = UIAccessibilityTraitButton;
}

static UIColor *TGSecretChatColour(void) {
	static UIColor *colour = nil;
	if (!colour)
		colour = [UIColor colorWithRed:0x22 / 255.0f green:0x9a / 255.0f
								  blue:0x0a / 255.0f alpha:1.0f];
	return colour;
}

- (NSString *)secretHandshakeTextForChat:(NSDictionary *)chat {
	if (self.searchResults)
		return nil;
	int64_t chatId = [chat[@"id"] longLongValue];
	if (!chatId || [[TGClient shared] secretChatIdForChat:chatId] == 0)
		return nil;

	NSNumber *key = @(chatId);
	NSString *cached = self.secretStatuses[key];
	if (cached)
		return cached.length ? cached : nil;
	if ([self.secretStatusesRequested containsObject:key])
		return nil;
	[self.secretStatusesRequested addObject:key];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] secretChatStatusForChat:chatId completion:^(NSString *status){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		NSString *line = TGReplyString(status) ?: @"";
		me.secretStatuses[key] = line;
		if (line.length)
			[me.tableView reloadData];
	}];
	return nil;
}

static BOOL TGChatDateUses12Hour(void) {
	static BOOL twelve = NO;
	static BOOL asked = NO;
	if (!asked){
		asked = YES;
		NSString *shape = [NSDateFormatter dateFormatFromTemplate:@"j"
														  options:0
														   locale:[NSLocale currentLocale]];
		twelve = ([shape rangeOfString:@"a"].location != NSNotFound);
	}
	return twelve;
}

static NSString *TGChatDateParts(NSTimeInterval unix, NSString **suffix, BOOL *bold) {
	if (suffix)
		*suffix = nil;
	if (bold)
		*bold = NO;
	if (unix <= 0)
		return @"";

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:unix];
	NSTimeInterval age = -[date timeIntervalSinceNow];

	static NSDateFormatter *time = nil, *hour12 = nil, *marker = nil;
	static NSDateFormatter *weekday = nil, *full = nil;
	if (!time){
		NSLocale *fixed = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		time = [[NSDateFormatter alloc] init];    [time setLocale:fixed];    [time setDateFormat:@"HH:mm"];
		hour12 = [[NSDateFormatter alloc] init];  [hour12 setLocale:fixed];  [hour12 setDateFormat:@"h:mm"];
		marker = [[NSDateFormatter alloc] init];  [marker setLocale:fixed];  [marker setDateFormat:@"a"];
		weekday = [[NSDateFormatter alloc] init]; [weekday setLocale:fixed]; [weekday setDateFormat:@"EEE"];
		full = [[NSDateFormatter alloc] init];    [full setLocale:fixed];    [full setDateFormat:@"dd.MM.yy"];
	}

	if (age < 24 * 3600){
		if (!TGChatDateUses12Hour())
			return [time stringFromDate:date];
		if (suffix)
			*suffix = [@" " stringByAppendingString:[marker stringFromDate:date]];
		return [hour12 stringFromDate:date];
	}
	if (age < 7 * 24 * 3600){
		if (bold)
			*bold = YES;
		return [weekday stringFromDate:date];
	}
	return [full stringFromDate:date];
}

#pragma mark - table

static const NSInteger kChatActionsTag = 77;

- (void)rowHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;

	[self closeOpenSwipeCellAnimated:YES];
	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:[hold locationInView:self.tableView]];
	if (path)
		[self showActionsForRow:path.row];
}

/// Split out from the gesture so itglegacy://holdrow/N can reach it: a long
/// press cannot be delivered through a URL, and this menu needs checking.
- (void)showActionsForRow:(NSInteger)row {
	if (self.searchResults)
		return;

	NSDictionary *chat = [self chatForRow:row];
	if (!chat)
		return;
	int64_t chatId = [chat[@"id"] longLongValue];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatMarkedAsUnread:chatId completion:^(BOOL marked){
		[weakSelf presentActionsForRow:row chat:chatId markedUnread:marked];
	}];
}

- (void)presentActionsForRow:(NSInteger)row chat:(int64_t)expected markedUnread:(BOOL)markedUnread {
	NSDictionary *held = [self chatForRow:row];
	if (!held || [held[@"id"] longLongValue] != expected)
		return;
	self.actionChat = held;

	BOOL pinned = [self.actionChat[@"isPinned"] boolValue];
	BOOL muted  = [self.actionChat[@"isMuted"] boolValue];
	BOOL unread = markedUnread || [self chatIsUnread:self.actionChat];
	self.actionChatUnread = unread;
	int64_t heldChatId = [self.actionChat[@"id"] longLongValue];
	if (muted)
		[self refreshMuteRemainingForChat:heldChatId];

	BOOL hasFolders = ([self folderList].count > 0);
	NSArray *items = [self rowActionItemsForChat:heldChatId
										  pinned:pinned
										   muted:muted
										  unread:unread
									  hasFolders:hasFolders];
	self.rowActionKinds = [self rowActionKindsWithFolders:hasFolders];

	CGRect rect = [self.tableView rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	CGPoint where = [self.tableView convertPoint:
			CGPointMake(120, CGRectGetMaxY(rect) - 10) toView:self.navigationController.view];

	self.menuPoint = where;
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		[weakSelf runChatAction:choice];
	}];
}

- (NSArray *)rowActionItemsForChat:(int64_t)chatId
							pinned:(BOOL)pinned
							 muted:(BOOL)muted
							unread:(BOOL)unread
						hasFolders:(BOOL)hasFolders {
	NSMutableArray *items = [NSMutableArray array];
	[items addObject:@{@"title" : (pinned ? @"Unpin" : @"Pin"),
					   @"icon"  : (pinned ? @"unpin" : @"pin")}];
	[items addObject:@{@"title" : (unread ? @"Mark as Read" : @"Mark as Unread"),
					   @"icon"  : @"chat"}];
	[items addObject:@{@"title" : (muted ? [self unmuteTitleForChat:chatId] : @"Mute"),
					   @"icon"  : (muted ? @"unmute" : @"mute")}];
	[items addObject:@{@"title" : @"Notifications…", @"icon" : @"mute"}];
	[items addObject:@{@"title" : (self.showsArchive ? @"Unarchive" : @"Archive"),
					   @"icon"  : (self.showsArchive ? @"unarchive" : @"archive")}];
	if (hasFolders)
		[items addObject:@{@"title" : @"Add to Folder", @"icon" : @"folder"}];
	[items addObject:@{@"title" : @"Delete and Leave", @"icon" : @"delete",
					   @"destructive" : @YES}];
	return items;
}

- (NSArray *)rowActionKindsWithFolders:(BOOL)hasFolders {
	NSMutableArray *kinds = [NSMutableArray arrayWithObjects:
			@"pin", @"read", @"mute", @"notify", @"archive", nil];
	if (hasFolders)
		[kinds addObject:@"folder"];
	[kinds addObject:@"delete"];
	return kinds;
}

- (void)runChatAction:(NSInteger)choice {
	NSDictionary *chat = self.actionChat;
	int64_t chatId = [chat[@"id"] longLongValue];
	BOOL unread = self.actionChatUnread;
	if (choice < 0 || choice >= (NSInteger)self.rowActionKinds.count)
		return;
	NSString *kind = self.rowActionKinds[choice];

	if ([kind isEqualToString:@"pin"]){
		[[TGClient shared] setChat:chatId
							pinned:![chat[@"isPinned"] boolValue]
							inList:[self currentListId]];
	} else if ([kind isEqualToString:@"read"]){
		[self setChat:chatId read:unread];
	} else if ([kind isEqualToString:@"mute"]){
		if ([chat[@"isMuted"] boolValue]){
			[[TGClient shared] setChat:chatId muteForSeconds:0];
			[self.muteRemaining removeObjectForKey:@(chatId)];
		} else {
			[self showMuteDurationsForChat:chatId];
			return;
		}
	} else if ([kind isEqualToString:@"notify"]){
		[self showNotificationOptionsForChat:chatId];
		return;
	} else if ([kind isEqualToString:@"archive"]){
		[self setChat:chatId archived:!self.showsArchive];
	} else if ([kind isEqualToString:@"folder"]){
		[self showFoldersForChat:chatId];
		return;
	} else {
		[self confirmDeleteChat:chatId];
	}
	self.actionChat = nil;
}

- (void)showFoldersForChat:(int64_t)chatId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] listsToAddChat:chatId completion:^(NSArray *reply){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *items = [NSMutableArray array];
		NSMutableArray *ids = [NSMutableArray array];
		for (id entry in (TGReplyArray(reply) ?: @[])){
			NSDictionary *list = TGReplyDictionary(entry);
			if (![list[@"list"] isKindOfClass:[NSNumber class]])
				continue;
			NSInteger listId = [list[@"list"] integerValue];
			if (listId == TGChatListMain || listId == TGChatListArchive)
				continue;
			[items addObject:@{@"title" : (TGReplyString(list[@"title"]) ?: @"Folder"),
							   @"icon"  : @"folder"}];
			[ids addObject:@(listId)];
		}
		if (!items.count){
			[me showAllFoldersForChat:chatId];
			return;
		}
		me.listsToAddIds = ids;

		[TGPopupMenu showItems:items atPoint:me.menuPoint inView:me.navigationController.view
					  onChoice:^(NSInteger choice, NSString *title){
			TGChatListViewController *inner = weakSelf;
			if (!inner || choice < 0 || choice >= (NSInteger)inner.listsToAddIds.count)
				return;
			NSInteger listId = [inner.listsToAddIds[choice] integerValue];
			[[TGClient shared] addChat:chatId toList:(TGChatListId)listId completion:^(BOOL ok){
				TGChatListViewController *tail = weakSelf;
				if (!tail)
					return;
				tail.actionChat = nil;
				if (!ok){
					UIAlertView *alert = [[UIAlertView alloc]
							initWithTitle:@"Add to Folder"
								  message:@"Telegram would not add this chat to that folder."
								 delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
					[alert show];
					return;
				}
				[tail reload];
			}];
		}];
	}];
}

- (void)showAllFoldersForChat:(int64_t)chatId {
	NSArray *folders = [self folderList];
	if (!folders.count){
		[self openFolderManagement];
		return;
	}

	NSMutableArray *items = [NSMutableArray array];
	NSMutableArray *ids = [NSMutableArray array];
	for (id entry in folders){
		NSDictionary *folder = TGReplyDictionary(entry);
		NSInteger listId = [folder[@"id"] integerValue];
		if (!listId)
			continue;
		[items addObject:@{@"title" : (TGReplyString(folder[@"title"]) ?: @"Folder"),
						   @"icon"  : @"folder"}];
		[ids addObject:@(listId)];
	}
	if (!items.count){
		[self openFolderManagement];
		return;
	}
	self.folderSheetItems = ids;

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:self.menuPoint inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		TGChatListViewController *me = weakSelf;
		if (!me || choice < 0 || choice >= (NSInteger)me.folderSheetItems.count)
			return;
		[me toggleChat:chatId inFolder:[me.folderSheetItems[choice] integerValue]];
	}];
}

- (void)toggleChat:(int64_t)chatId inFolder:(NSInteger)folderId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] folderWithId:folderId completion:^(NSDictionary *reply){
		TGChatListViewController *me = weakSelf;
		NSDictionary *folder = TGReplyDictionary(reply);
		if (!me || !folder)
			return;

		NSMutableDictionary *edited = [folder mutableCopy];
		NSMutableArray *included = [(TGReplyArray(folder[@"includedChatIds"]) ?: @[]) mutableCopy];
		NSMutableArray *excluded = [(TGReplyArray(folder[@"excludedChatIds"]) ?: @[]) mutableCopy];
		NSNumber *key = @(chatId);

		BOOL wasIn = NO;
		for (NSNumber *entry in [included copy]){
			if ([entry longLongValue] == chatId){
				wasIn = YES;
				[included removeObject:entry];
			}
		}
		for (NSNumber *entry in [excluded copy]){
			if ([entry longLongValue] == chatId)
				[excluded removeObject:entry];
		}
		if (!wasIn)
			[included addObject:key];

		edited[@"includedChatIds"] = included;
		edited[@"excludedChatIds"] = excluded;
		[[TGClient shared] saveFolder:edited completion:^(NSInteger saved){
			TGChatListViewController *inner = weakSelf;
			if (!inner)
				return;
			if (!saved)
				return;
			[inner reload];
		}];
	}];
	self.actionChat = nil;
}

- (void)setChat:(int64_t)chatId read:(BOOL)read {
	[self.rowDetails removeObjectForKey:@(chatId)];
	[self.rowDetailsRequested removeObject:@(chatId)];
	__weak typeof(self) weakSelf = self;
	if (!read){
		[[TGClient shared] setChat:chatId markedAsUnread:YES];
		[self reload];
		return;
	}
	[[TGClient shared] readAllMentionsInChat:chatId];
	[[TGClient shared] readAllReactionsInChat:chatId];
	[[TGClient shared] markChatAsRead:chatId completion:^(BOOL ok){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		[me reload];
		if ([me.tabBarController isKindOfClass:[RootViewController class]])
			[(RootViewController *)me.tabBarController updateUnreadBadge];
	}];
}

- (BOOL)chatIsUnread:(NSDictionary *)chat {
	if ([chat[@"unread"] integerValue] > 0)
		return YES;
	if ([chat[@"markedUnread"] boolValue])
		return YES;
	if ([chat[@"id"] isKindOfClass:[NSNumber class]] &&
		[TGReplyDictionary(self.rowDetails[chat[@"id"]])[@"markedUnread"] boolValue])
		return YES;
	return [[TGClient shared] isChatMarkedAsUnread:[chat[@"id"] longLongValue]];
}

- (void)showNotificationsAlertWithMessage:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Notifications"
													message:message
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

- (NSArray *)notificationMenuKindsForChatMuted:(BOOL)muted usesDefault:(BOOL)usesDefault {
	NSMutableArray *kinds = [NSMutableArray array];
	[kinds addObject:(muted ? @"unmute" : @"mute")];
	[kinds addObject:@"preview"];
	if (!usesDefault)
		[kinds addObject:@"default"];
	return kinds;
}

- (NSArray *)notificationMenuItemsForChat:(int64_t)chatId
									muted:(BOOL)muted
								  preview:(BOOL)preview
							  usesDefault:(BOOL)usesDefault {
	NSMutableArray *items = [NSMutableArray array];
	[items addObject:@{@"title" : (muted ? [self unmuteTitleForChat:chatId] : @"Mute…"),
					   @"icon"  : (muted ? @"unmute" : @"mute")}];
	[items addObject:@{@"title" : (preview ? @"Hide Message Text" : @"Show Message Text"),
					   @"icon"  : @"chat"}];
	if (!usesDefault)
		[items addObject:@{@"title" : @"Use Default Settings", @"icon" : @"chat"}];
	return items;
}

- (void)togglePreviewForChat:(int64_t)chatId currentlyOn:(BOOL)preview {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] updateChat:chatId
						   values:@{@"showPreview" : @(!preview),
									@"useDefaultShowPreview" : @NO}
					   completion:^(BOOL ok){
		TGChatListViewController *tail = weakSelf;
		if (!tail)
			return;
		tail.actionChat = nil;
		if (!ok){
			[tail showNotificationsAlertWithMessage:@"Telegram would not change that setting."];
			return;
		}
		[tail reload];
	}];
}

- (void)applyNotificationMenuKind:(NSString *)kind
						  forChat:(int64_t)chatId
					   previewOn:(BOOL)preview {
	if ([kind isEqualToString:@"mute"]){
		[self showMuteDurationsForChat:chatId];
		return;
	}
	if ([kind isEqualToString:@"unmute"]){
		[[TGClient shared] setChat:chatId muteForSeconds:0];
		[self.muteRemaining removeObjectForKey:@(chatId)];
		self.actionChat = nil;
		[self reload];
		return;
	}
	if ([kind isEqualToString:@"default"]){
		[[TGClient shared] resetNotificationSettingsForChat:chatId];
		[self.muteRemaining removeObjectForKey:@(chatId)];
		self.actionChat = nil;
		[self reload];
		return;
	}
	[self togglePreviewForChat:chatId currentlyOn:preview];
}

- (void)showNotificationOptionsForChat:(int64_t)chatId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] notificationSettingsForChat:chatId completion:^(NSDictionary *reply){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		NSDictionary *settings = TGReplyDictionary(reply);
		if (!settings){
			[me showNotificationsAlertWithMessage:@"Telegram would not answer for this chat."];
			return;
		}

		BOOL muted = [settings[@"muted"] boolValue];
		BOOL preview = [settings[@"showPreview"] boolValue];
		BOOL usesDefault = [settings[@"useDefaultMuteFor"] boolValue] &&
						   [settings[@"useDefaultShowPreview"] boolValue];
		me.muteRemaining[@(chatId)] = @([settings[@"muteFor"] integerValue]);

		NSArray *items = [me notificationMenuItemsForChat:chatId
													muted:muted
												  preview:preview
											  usesDefault:usesDefault];
		NSArray *kinds = [me notificationMenuKindsForChatMuted:muted usesDefault:usesDefault];

		[TGPopupMenu showItems:items atPoint:me.menuPoint inView:me.navigationController.view
					  onChoice:^(NSInteger choice, NSString *title){
			TGChatListViewController *inner = weakSelf;
			if (!inner || choice < 0 || choice >= (NSInteger)kinds.count)
				return;
			[inner applyNotificationMenuKind:kinds[choice] forChat:chatId previewOn:preview];
		}];
	}];
}

/// Muting is a choice of how long, the way every client asks it, rather than
/// an on/off that always means forever.
- (void)showMuteDurationsForChat:(int64_t)chatId {
	NSArray *items = @[
		@{@"title" : @"Mute for 1 hour",  @"icon" : @"mute"},
		@{@"title" : @"Mute for 8 hours", @"icon" : @"mute"},
		@{@"title" : @"Mute for 2 days",  @"icon" : @"mute"},
		@{@"title" : @"Mute for 1 week",  @"icon" : @"mute"},
		@{@"title" : @"Mute for…",        @"icon" : @"mute"},
		@{@"title" : @"Mute forever",     @"icon" : @"mute"},
	];
	NSArray *seconds = @[@(3600), @(8 * 3600), @(2 * 24 * 3600), @(7 * 24 * 3600),
						 @(-1), @(TGNotificationMuteForever)];

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:self.menuPoint inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		TGChatListViewController *me = weakSelf;
		if (!me || choice < 0 || choice >= (NSInteger)seconds.count)
			return;
		NSInteger value = [seconds[choice] integerValue];
		if (value < 0){
			[me askCustomMuteForChat:chatId];
			return;
		}
		[[TGClient shared] setChat:chatId muteForSeconds:value];
		me.muteRemaining[@(chatId)] = @(value);
		me.actionChat = nil;
		[me reload];
	}];
}

- (void)askCustomMuteForChat:(int64_t)chatId {
	self.chatPendingCustomMute = chatId;
	UIAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Mute for"
													message:@"Hours"
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Mute", nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	UITextField *field = [alert textFieldAtIndex:0];
	field.keyboardType = UIKeyboardTypeNumberPad;
	field.text = @"12";
	alert.tag = 20;
	[alert show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	if (alertView.tag == 21){
		NSString *link = [[alertView textFieldAtIndex:0].text
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (link.length)
			[self checkFolderInviteLink:link];
		return;
	}
	if (alertView.tag != 20)
		return;
	int64_t chatId = self.chatPendingCustomMute;
	self.chatPendingCustomMute = 0;
	if (!chatId)
		return;

	NSInteger hours = [[alertView textFieldAtIndex:0].text integerValue];
	if (hours <= 0)
		return;
	if (hours > 24 * 365)
		hours = 24 * 365;
	NSInteger value = hours * 3600;
	[[TGClient shared] setChat:chatId muteForSeconds:value];
	self.muteRemaining[@(chatId)] = @(value);
	self.actionChat = nil;
	[self reload];
}

- (void)refreshMuteRemainingForChat:(int64_t)chatId {
	if (!chatId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] notificationSettingsForChat:chatId completion:^(NSDictionary *settings){
		TGChatListViewController *me = weakSelf;
		NSDictionary *values = TGReplyDictionary(settings);
		if (!me || !values)
			return;
		me.muteRemaining[@(chatId)] = @([values[@"muteFor"] integerValue]);
	}];
}

- (NSString *)unmuteTitleForChat:(int64_t)chatId {
	NSInteger left = [self.muteRemaining[@(chatId)] integerValue];
	if (left <= 0 || left >= TGNotificationMuteForever)
		return @"Unmute";
	if (left < 3600)
		return [NSString stringWithFormat:@"Unmute (%ldm left)", (long)(left / 60)];
	if (left < 24 * 3600)
		return [NSString stringWithFormat:@"Unmute (%ldh left)", (long)(left / 3600)];
	return [NSString stringWithFormat:@"Unmute (%ldd left)", (long)(left / (24 * 3600))];
}

/// Archiving is a move between two chat lists, which is what TDLib calls it.
- (void)setChat:(int64_t)chatId archived:(BOOL)archived {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] addChat:chatId
						toList:(archived ? TGChatListArchive : TGChatListMain)
					completion:^(BOOL ok){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			UIAlertView *alert = [[UIAlertView alloc]
					initWithTitle:(archived ? @"Archive" : @"Unarchive")
						  message:@"Telegram would not move this chat."
						 delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
			return;
		}
		[me reload];
		[me rebuildTableHeader];
	}];
}

/// Leaving cannot be taken back once it has happened, so it does not happen at
/// once: the row goes, and the count on the plate is the window to change your
/// mind. Their design answers this with a snackbar rather than a dialog.
- (void)confirmDeleteChat:(int64_t)chatId {
	self.chatPendingDeletion = chatId;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[TGSnackbar showInView:self.navigationController.view
					  text:@"Chat deleted"
				   seconds:5
				  onCommit:^{
		[[TGClient shared] deleteChat:chatId];
		TGChatListViewController *me = weakSelf;
		me.chatPendingDeletion = 0;
		[me reload];
	}];

	// UNDO simply never commits; the row has to come back when it does not.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		TGChatListViewController *me = weakSelf;
		if (me.chatPendingDeletion == chatId){
			me.chatPendingDeletion = 0;
			[me.tableView reloadData];
		}
	});
}

#pragma mark - search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
	if (!query.length){
		self.searchResults = nil;
		[self.tableView reloadData];
		return;
	}

	// Chat titles match locally and instantly; messages need the server. Both
	// land in one list, chats first, which is what the query usually means.
	NSMutableArray *results = [NSMutableArray array];
	for (NSDictionary *c in TGChatRows([TGClient shared].chats)){
		NSString *title = TGReplyString(c[@"title"]);
		if (title && [title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound)
			[results addObject:c];
	}
	self.searchResults = results;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchMessages:query completion:^(NSArray *reply){
		TGChatListViewController *me = weakSelf;
		// A slower answer to an older query must not replace a newer one.
		if (!me || ![me.searchBar.text isEqualToString:query])
			return;
		NSMutableArray *combined = [results mutableCopy];
		for (id item in (TGReplyArray(reply) ?: @[])){
			NSDictionary *m = TGReplyDictionary(item);
			if (![m[@"chatId"] longLongValue])
				continue;
			[combined addObject:@{
				@"id"    : m[@"chatId"],
				@"title" : (TGReplyString(m[@"chatTitle"]) ?: @""),
				@"text"  : (TGReplyString(m[@"text"]) ?: @""),
				@"date"  : ([m[@"date"] isKindOfClass:[NSNumber class]] ? m[@"date"] : @0),
			}];
		}
		me.searchResults = combined;
		[me.tableView reloadData];
		[me appendSponsoredChatsForQuery:query onto:combined];
	}];
	[self appendSponsoredChatsForQuery:query onto:results];
}

- (void)appendSponsoredChatsForQuery:(NSString *)query onto:(NSArray *)base {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sponsoredChatsForQuery:query completion:^(NSArray *reply){
		TGChatListViewController *me = weakSelf;
		NSArray *sponsored = TGReplyArray(reply);
		if (!me || !sponsored.count || ![me.searchBar.text isEqualToString:query])
			return;
		NSMutableArray *combined = [NSMutableArray array];
		for (NSDictionary *existing in (me.searchResults ?: base))
			if (![existing[@"sponsored"] boolValue])
				[combined addObject:existing];
		for (id item in sponsored){
			NSDictionary *s = TGReplyDictionary(item);
			if (![s[@"id"] longLongValue])
				continue;
			NSString *info = TGReplyString(s[@"sponsorInfo"]) ?: TGReplyString(s[@"additionalInfo"]);
			[combined addObject:@{
				@"id"        : s[@"id"],
				@"title"     : (TGReplyString(s[@"title"]) ?: @""),
				@"text"      : (info ?: @"Sponsored"),
				@"date"      : @0,
				@"sponsored" : @YES,
				@"uniqueId"  : ([s[@"uniqueId"] isKindOfClass:[NSNumber class]] ? s[@"uniqueId"] : @0),
			}];
		}
		me.searchResults = combined;
		[me.tableView reloadData];
	}];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	self.searchResults = nil;
	[searchBar resignFirstResponder];
	[self.tableView reloadData];
}

/// Saved Messages has a row of its own above the list, so leaving it among the
/// chats as well would show it twice.
- (NSArray *)visibleChats {
	if (self.searchResults)
		return self.searchResults;

	BOOL hideSaved = [[self headerRows] containsObject:@"saved"];
	int64_t saved = hideSaved ? [[TGClient shared] savedMessagesChatId] : 0;
	if (!hideSaved && !self.chatPendingDeletion)
		return self.chats;

	NSMutableArray *rest = [NSMutableArray array];
	for (NSDictionary *c in self.chats){
		int64_t chatId = [c[@"id"] longLongValue];
		// A chat waiting on the undo plate is already off the list; putting it
		// back is what UNDO does.
		if (chatId == saved || chatId == self.chatPendingDeletion)
			continue;
		[rest addObject:c];
	}
	return rest;
}

- (NSDictionary *)chatForRow:(NSInteger)row {
	NSArray *rows = [self visibleChats];
	NSInteger index = row - (NSInteger)[self headerRows].count;
	if (index < 0 || index >= (NSInteger)rows.count)
		return nil;
	return rows[index];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	[self updateEmptyState];
	if (self.searchResults)
		return self.searchResults.count;
	return [self visibleChats].count + [self headerRows].count;
}

- (void)resetCell:(TGChatCell *)cell plain:(BOOL)plainPlate {
	TGTheme *theme = [TGTheme shared];
	cell.chatId = 0;
	cell.backgroundColor = [theme listBackgroundColour];
	cell.backgroundView.hidden = !plainPlate;
	cell.titleLabel.textColor = plainPlate ? TGChatListTitleColour() : [theme primaryTextColour];
	cell.previewLabel.textColor = plainPlate ? TGChatListMessageColour()
											 : [theme secondaryTextColour];
	cell.dateLabel.textColor = [theme accentColour];
	cell.authorLabel.hidden = YES;
	cell.onlineDot.hidden = YES;
	cell.tick.hidden = YES;
	cell.muteIcon.hidden = YES;
	cell.groupIcon.hidden = YES;
	cell.pin.hidden = YES;
	cell.draftLabel.hidden = YES;
	cell.badge.hidden = YES;
	cell.badgeBackground.hidden = YES;
	cell.badge.text = @"";
	[cell setDateText:@"" suffix:nil bold:NO];
	cell.previewLabel.text = @"";
	cell.titleLabel.text = @"";
	cell.authorLabel.text = @"";
	cell.tick.image = nil;
	cell.tick.highlightedImage = nil;
	cell.pin.image = nil;
	cell.onlineDot.layer.borderColor = [theme listBackgroundColour].CGColor;
}

- (void)configureHeaderCell:(TGChatCell *)cell kind:(NSString *)kind {
	BOOL isArchive = [kind isEqualToString:@"archive"];
	cell.titleLabel.text = isArchive ? @"Archived Chats" : @"Saved Messages";
	cell.previewLabel.text = isArchive
			? [NSString stringWithFormat:@"%lu chats",
					(unsigned long)TGReplyArray([TGClient shared].archivedChats).count]
			: @"Your own notes and forwards";
	[cell setDateText:@"" suffix:nil bold:NO];
	cell.badge.hidden = YES;
	cell.badgeBackground.hidden = YES;
	cell.avatar.image = isArchive
			? [TGIcons archiveAvatarOfSide:kAvatar]
			: [TGIcons savedMessagesAvatarOfSide:kAvatar];
	cell.avatar.backgroundColor = [UIColor clearColor];
	[self describeCell:cell unread:0 muted:NO];
}

/// Someone typing takes the preview over for as long as it lasts, in their
/// blurple rather than the grey the preview uses.
- (void)configurePreviewInCell:(TGChatCell *)cell chat:(NSDictionary *)c plain:(BOOL)plainPlate {
	TGTheme *theme = [TGTheme shared];
	NSDictionary *detail = [c[@"id"] isKindOfClass:[NSNumber class]]
			? TGReplyDictionary(self.rowDetails[c[@"id"]]) : nil;
	NSString *action = TGReplyString(c[@"action"]);
	NSString *draft = TGReplyString(c[@"draft"]);
	if (!draft.length)
		draft = TGReplyString(detail[@"draft"]);
	NSString *handshake = [self secretHandshakeTextForChat:c];
	if (action.length){
		cell.previewLabel.text = action;
		cell.previewLabel.textColor = plainPlate ? TGChatListActionColour()
												 : [theme typingColour];
	} else if (handshake.length){
		cell.previewLabel.text = handshake;
		cell.previewLabel.textColor = plainPlate ? TGChatListActionColour()
												 : [theme typingColour];
	} else if (draft.length && !self.searchResults){
		cell.draftLabel.hidden = NO;
		cell.previewLabel.text = draft;
	} else if ([TGReplyString(detail[@"source"]) isEqualToString:@"psa"]){
		NSString *note = TGReplyString(detail[@"sourceText"]);
		cell.authorLabel.text = note.length ? note : @"Public Service Announcement";
		cell.authorLabel.hidden = NO;
		cell.previewLabel.text = TGReplyString(c[@"text"]) ?: @"";
	} else {
		NSString *preview = TGReplyString(c[@"text"]) ?: @"";
		NSRange split = [c[@"isGroup"] boolValue] && !self.searchResults
				? [preview rangeOfString:@": "] : NSMakeRange(NSNotFound, 0);
		if (split.location != NSNotFound && split.location > 0 && split.location <= 40){
			cell.authorLabel.text = [preview substringToIndex:split.location];
			cell.authorLabel.hidden = NO;
			preview = [preview substringFromIndex:split.location + split.length];
		}
		cell.previewLabel.text = preview;
	}
}

- (void)configureBadgeInCell:(TGChatCell *)cell chat:(NSDictionary *)c unread:(NSInteger)unread {
	BOOL markedUnread = (unread <= 0) && ![c[@"sponsored"] boolValue] && [self chatIsUnread:c];
	cell.badge.hidden = (unread <= 0 && !markedUnread);
	cell.badgeBackground.hidden = cell.badge.hidden;
	cell.pin.hidden = !([c[@"isPinned"] boolValue] && unread <= 0 && !markedUnread);
	if (!cell.pin.hidden){
		cell.pin.image = [TGIcons menuGlyphNamed:@"pin"];
		[cell.pin tg_setTintColor:[[TGTheme shared] secondaryTextColour]];
	}
	cell.badge.text = unread > 0
			? (unread < 1000 ? [NSString stringWithFormat:@"%ld", (long)unread]
							 : [NSString stringWithFormat:@"%ldK", (long)(unread / 1000)])
			: @"";
}

- (void)configureAvatarInCell:(TGChatCell *)cell chat:(NSDictionary *)c {
	NSNumber *fileId = c[@"photoFileId"];
	UIImage *photo = fileId ? self.avatars[fileId] : nil;
	if ([c[@"isSaved"] boolValue])
		photo = [TGIcons savedMessagesAvatarOfSide:kAvatar];
	if (!photo){
		NSString *title = TGReplyString(c[@"title"]) ?: @"";
		NSString *initials = title.length ? [title substringToIndex:1] : @"?";
		photo = [TGIcons avatarWithInitials:initials.uppercaseString
									   size:kAvatar
								   colourId:[c[@"id"] longLongValue]];
	}
	cell.avatar.image = photo;
	cell.avatar.backgroundColor = [UIColor clearColor];
}

- (void)configureStatusIconsInCell:(TGChatCell *)cell chat:(NSDictionary *)c {
	cell.onlineDot.hidden = ![c[@"isOnline"] boolValue];
	cell.tick.hidden = ![c[@"outgoing"] boolValue] || !cell.draftLabel.hidden ||
			[c[@"sponsored"] boolValue];
	if (!cell.tick.hidden){
		NSString *art = [c[@"outgoingRead"] boolValue] ? @"DialogListRead" : @"DialogListSent";
		cell.tick.image = [UIImage imageNamed:[art stringByAppendingString:@".png"]];
		cell.tick.highlightedImage = [UIImage imageNamed:
				[art stringByAppendingString:@"_Highlighted.png"]];
	}

	cell.muteIcon.hidden = ![c[@"isMuted"] boolValue];
	cell.groupIcon.hidden = ![c[@"isGroup"] boolValue];
}

- (void)attachSwipeHandlersToCell:(TGChatCell *)cell chat:(NSDictionary *)c {
	cell.swipeActions = [self swipeActionsForChat:c];
	__weak typeof(self) weakSelf = self;
	__weak TGChatCell *weakCell = cell;
	cell.onSwipeOpen = ^{
		[weakSelf closeOpenSwipeCellAnimated:YES];
		weakSelf.openSwipeCell = weakCell;
	};
	cell.onSwipeAction = ^(NSString *kind){
		[weakSelf runSwipeAction:kind forCell:weakCell];
	};
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

	static NSString *reuse = @"TGChatCell";
	TGChatCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
	if (cell == self.openSwipeCell)
		self.openSwipeCell = nil;

	TGTheme *theme = [TGTheme shared];
	BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
	[self resetCell:cell plain:plainPlate];

	NSArray *header = [self headerRows];
	NSArray *rows = [self visibleChats];
	if (indexPath.row >= (NSInteger)(header.count + rows.count))
		return cell;
	if (indexPath.row < (NSInteger)header.count){
		[self configureHeaderCell:cell kind:header[indexPath.row]];
		[cell setNeedsLayout];
		return cell;
	}

	NSDictionary *c = rows[indexPath.row - header.count];
	cell.chatId = [c[@"id"] longLongValue];
	cell.titleLabel.text = TGReplyString(c[@"title"]) ?: @"";
	if (!self.searchResults && [c[@"id"] longLongValue] &&
		[[TGClient shared] secretChatIdForChat:[c[@"id"] longLongValue]] != 0)
		cell.titleLabel.textColor = TGSecretChatColour();
	cell.dateLabel.textColor = [c[@"sponsored"] boolValue]
			? [theme secondaryTextColour] : [theme accentColour];
	if ([c[@"sponsored"] boolValue]){
		[cell setDateText:@"Sponsored" suffix:nil bold:NO];
	} else {
		NSString *marker = nil;
		BOOL bold = NO;
		NSString *stamp = TGChatDateParts([c[@"date"] doubleValue], &marker, &bold);
		[cell setDateText:stamp suffix:marker bold:bold];
	}

	[self configurePreviewInCell:cell chat:c plain:plainPlate];

	[self configureStatusIconsInCell:cell chat:c];

	NSInteger unread = [c[@"unread"] integerValue];
	[self configureBadgeInCell:cell chat:c unread:unread];
	[self configureAvatarInCell:cell chat:c];
	[self attachSwipeHandlersToCell:cell chat:c];

	[self describeCell:cell unread:unread muted:[c[@"isMuted"] boolValue]];
	[cell setNeedsLayout];
	return cell;
}

- (void)fetchRowDetailForChat:(NSDictionary *)chat {
	if (self.searchResults || [chat[@"sponsored"] boolValue])
		return;
	NSNumber *key = chat[@"id"];
	if (![key isKindOfClass:[NSNumber class]] || ![key longLongValue])
		return;
	if (self.rowDetails[key] || [self.rowDetailsRequested containsObject:key])
		return;
	if (self.rowDetails.count >= kRowDetailCacheLimit)
		[self pruneRowDetails];
	[self.rowDetailsRequested addObject:key];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] rowDetailForChat:[key longLongValue] completion:^(NSDictionary *reply){
		TGChatListViewController *me = weakSelf;
		NSDictionary *detail = TGReplyDictionary(reply);
		if (!me)
			return;
		if (!detail){
			[me.rowDetailsRequested removeObject:key];
			return;
		}
		me.rowDetails[key] = detail;

		TGChatCell *cell = [me cellShowingChatId:[key longLongValue]];
		NSIndexPath *path = cell ? [me.tableView indexPathForCell:cell] : nil;
		if (path && [[me chatForRow:path.row][@"id"] isEqual:key])
			[me.tableView reloadRowsAtIndexPaths:@[path]
								withRowAnimation:UITableViewRowAnimationNone];
	}];
}

- (void)pruneRowDetails {
	NSMutableSet *keep = [NSMutableSet set];
	for (UITableViewCell *raw in ([self.tableView visibleCells] ?: @[])){
		if (![raw isKindOfClass:[TGChatCell class]])
			continue;
		long long chatId = ((TGChatCell *)raw).chatId;
		if (chatId)
			[keep addObject:@(chatId)];
	}
	for (id key in [self.rowDetails.allKeys copy]){
		if ([keep containsObject:key])
			continue;
		[self.rowDetails removeObjectForKey:key];
		[self.rowDetailsRequested removeObject:key];
	}
}

- (NSArray *)swipeActionsForChat:(NSDictionary *)chat {
	if (self.searchResults || [chat[@"sponsored"] boolValue])
		return nil;
	if (![chat[@"id"] longLongValue])
		return nil;

	BOOL muted = [chat[@"isMuted"] boolValue];
	return @[
		@{@"kind"  : (muted ? @"unmute" : @"mute"),
		  @"title" : (muted ? @"Unmute" : @"Mute")},
		@{@"kind"  : (self.showsArchive ? @"unarchive" : @"archive"),
		  @"title" : (self.showsArchive ? @"Unarchive" : @"Archive")},
		@{@"kind"        : @"delete",
		  @"title"       : ([chat[@"isGroup"] boolValue] ? @"Leave" : @"Delete"),
		  @"destructive" : @YES},
	];
}

- (void)closeOpenSwipeCellAnimated:(BOOL)animated {
	TGChatCell *open = self.openSwipeCell;
	self.openSwipeCell = nil;
	[open setSwipeActionsVisible:NO animated:animated];
}

- (void)runSwipeAction:(NSString *)kind forCell:(TGChatCell *)cell {
	if (!cell)
		return;
	NSIndexPath *path = [self.tableView indexPathForCell:cell];
	if (!path)
		return;
	NSDictionary *chat = [self chatShownByCell:cell];
	if (!chat)
		return;

	int64_t chatId = [chat[@"id"] longLongValue];
	if (!chatId)
		return;

	[cell setSwipeActionsVisible:NO animated:YES];
	if (self.openSwipeCell == cell)
		self.openSwipeCell = nil;

	if ([kind isEqualToString:@"unmute"]){
		[[TGClient shared] setChat:chatId muteForSeconds:0];
		[self reload];
	} else if ([kind isEqualToString:@"mute"]){
		self.actionChat = chat;
		CGRect rect = [self.tableView rectForRowAtIndexPath:path];
		self.menuPoint = [self.tableView convertPoint:
				CGPointMake(120, CGRectGetMaxY(rect) - 10) toView:self.navigationController.view];
		[self showMuteDurationsForChat:chatId];
	} else if ([kind isEqualToString:@"archive"]){
		[self setChat:chatId archived:YES];
	} else if ([kind isEqualToString:@"unarchive"]){
		[self setChat:chatId archived:NO];
	} else if ([kind isEqualToString:@"delete"]){
		[self confirmDeleteChat:chatId];
	}
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *c = [self chatForRow:indexPath.row];
	if (!c)
		return;
	[self fetchRowDetailForChat:c];
	NSNumber *avatarFileId = c[@"photoFileId"];
	if ([avatarFileId isKindOfClass:[NSNumber class]] && !self.avatars[avatarFileId] &&
		![self.avatarsRequested containsObject:avatarFileId])
		[self startAvatarDownload:avatarFileId];
	if (![c[@"sponsored"] boolValue])
		return;
	NSNumber *uniqueId = c[@"uniqueId"];
	if (!uniqueId || [self.sponsoredSeen containsObject:uniqueId])
		return;
	[self.sponsoredSeen addObject:uniqueId];
	[[TGClient shared] viewSponsoredChat:[uniqueId longLongValue]];
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (!self.avatarsInFlight.count)
		return;
	NSSet *wanted = [self avatarFileIdsWanted];
	for (NSNumber *fileId in [self.avatarsInFlight allObjects]){
		if ([wanted containsObject:fileId])
			continue;
		[self.avatarsInFlight removeObject:fileId];
		[self.avatarsRequested removeObject:fileId];
		[[TGClient shared] cancelDownloadOfFile:[fileId integerValue] onlyIfPending:NO];
	}
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.searchResults)
		return NO;
	NSArray *header = [self headerRows];
	return indexPath.row >= (NSInteger)header.count;
}

- (NSInteger)pinnedRowCount {
	if (self.searchResults)
		return 0;
	NSArray *rows = [self visibleChats];
	NSInteger count = 0;
	for (NSDictionary *chat in rows){
		if (![chat[@"isPinned"] boolValue])
			break;
		count++;
	}
	return count;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.searchResults || [self visibleChats].count != self.chats.count)
		return NO;
	NSInteger pinned = [self pinnedRowCount];
	if (pinned < 2)
		return NO;
	NSInteger index = indexPath.row - (NSInteger)[self headerRows].count;
	return index >= 0 && index < pinned;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
		targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
							 toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
	NSInteger header = (NSInteger)[self headerRows].count;
	NSInteger pinned = [self pinnedRowCount];
	NSInteger row = proposedDestinationIndexPath.row;
	if (row < header)
		row = header;
	if (row > header + pinned - 1)
		row = header + pinned - 1;
	return [NSIndexPath indexPathForRow:row inSection:0];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
	  toIndexPath:(NSIndexPath *)destinationIndexPath {
	NSInteger header = (NSInteger)[self headerRows].count;
	NSInteger pinned = [self pinnedRowCount];
	NSInteger from = sourceIndexPath.row - header;
	NSInteger to = destinationIndexPath.row - header;
	if (from < 0 || to < 0 || from >= pinned || to >= pinned || from == to)
		return;

	NSMutableArray *reordered = [self.chats mutableCopy];
	if (from >= (NSInteger)reordered.count || to >= (NSInteger)reordered.count)
		return;
	id moved = reordered[from];
	[reordered removeObjectAtIndex:from];
	[reordered insertObject:moved atIndex:to];
	self.chats = reordered;
	[self reloadRowsFrom:MIN(from, to) to:MAX(from, to)];

	NSMutableArray *ids = [NSMutableArray array];
	for (NSInteger i = 0; i < pinned; i++){
		NSNumber *key = reordered[i][@"id"];
		if ([key isKindOfClass:[NSNumber class]])
			[ids addObject:key];
	}
	if (!ids.count)
		return;
	[[TGClient shared] setPinnedChats:ids inList:[self currentListId]];
}

- (void)reloadRowsFrom:(NSInteger)first to:(NSInteger)last {
	NSInteger header = (NSInteger)[self headerRows].count;
	NSInteger rows = (NSInteger)[self visibleChats].count;
	NSMutableArray *paths = [NSMutableArray array];
	for (NSInteger i = MAX(first, 0); i <= last && i < rows; i++)
		[paths addObject:[NSIndexPath indexPathForRow:i + header inSection:0]];
	if (!paths.count)
		return;

	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		TGChatListViewController *me = weakSelf;
		if ((NSInteger)[me visibleChats].count != rows)
			return;
		[me.tableView reloadRowsAtIndexPaths:paths
							withRowAnimation:UITableViewRowAnimationNone];
	});
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
		editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (![self tableView:tableView canEditRowAtIndexPath:indexPath])
		return UITableViewCellEditingStyleNone;
	return tableView.editing ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (NSString *)tableView:(UITableView *)tableView
		titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([[self chatForRow:indexPath.row][@"isGroup"] boolValue])
		return @"Leave";
	return @"Delete";
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (style != UITableViewCellEditingStyleDelete)
		return;
	NSDictionary *chat = [self chatForRow:indexPath.row];
	if (!chat)
		return;
	int64_t chatId = [chat[@"id"] longLongValue];
	[self confirmDeleteChat:chatId];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (![self splitLayoutActive])
		[tableView deselectRowAtIndexPath:indexPath animated:YES];

	BOOL split = [self splitLayoutActive];

	if (self.openSwipeCell){
		if (split)
			[tableView deselectRowAtIndexPath:indexPath animated:YES];
		[self closeOpenSwipeCellAnimated:YES];
		return;
	}

	NSArray *header = [self headerRows];
	NSArray *rows = [self visibleChats];
	if (indexPath.row >= (NSInteger)(header.count + rows.count)){
		if (split)
			[tableView deselectRowAtIndexPath:indexPath animated:YES];
		return;
	}
	if (indexPath.row < (NSInteger)header.count){
		if ([header[indexPath.row] isEqualToString:@"archive"]){
			if (split)
				[tableView deselectRowAtIndexPath:indexPath animated:YES];
			[self openArchive];
		} else {
			[self openSavedMessages];
		}
		return;
	}

	NSDictionary *c = rows[indexPath.row - header.count];
	int64_t chatId = [c[@"id"] longLongValue];
	if (!chatId){
		if (split)
			[tableView deselectRowAtIndexPath:indexPath animated:YES];
		return;
	}
	if ([c[@"sponsored"] boolValue] && [c[@"uniqueId"] longLongValue])
		[[TGClient shared] openSponsoredChat:[c[@"uniqueId"] longLongValue]];
	NSLog(@"open chat: group=%@ forum=%@", c[@"isGroup"], c[@"isForum"] ?: @"(absent)");

	if ([c[@"isForum"] boolValue]){
		if (split)
			[tableView deselectRowAtIndexPath:indexPath animated:YES];
		TGTopicsViewController *topics = [[TGTopicsViewController alloc] init];
		topics.chatId = chatId;
		topics.chatTitle = TGReplyString(c[@"title"]);
		[self.navigationController pushViewController:topics animated:YES];
		return;
	}

	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = chatId;
	vc.chatTitle = TGReplyString(c[@"title"]);
	vc.isGroup = [c[@"isGroup"] boolValue];
	[self presentChatController:vc];
}

@end

// vim:ft=objc

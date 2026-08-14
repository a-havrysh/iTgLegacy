#import "TGTopicsViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGClient+Forums.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGActionSheet.h"
#import "TGPopupMenu.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kTopicRowHeight = 73.0f;
static const CGFloat kTopicAvatar = 56.0f;
static const CGFloat kTopicAvatarLeft = 8.0f;
static const CGFloat kTopicTextLeft = 73.0f;

static UIImage *TGTopicBadgeImage(void) {
	static UIImage *normal = nil;
	if (!normal){
		UIImage *raw = [UIImage imageNamed:@"DialogListUnreadBadge.png"];
		normal = [raw stretchableImageWithLeftCapWidth:(int)(raw.size.width / 2)
										  topCapHeight:(int)(raw.size.height / 2)];
	}
	return normal;
}

static NSString *TGTopicDate(NSTimeInterval unix) {
	if (unix <= 0)
		return @"";

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:unix];
	NSTimeInterval age = -[date timeIntervalSinceNow];

	static NSDateFormatter *time = nil, *weekday = nil, *full = nil;
	if (!time){
		time = [[NSDateFormatter alloc] init];    [time setDateFormat:@"HH:mm"];
		weekday = [[NSDateFormatter alloc] init]; [weekday setDateFormat:@"EEE"];
		full = [[NSDateFormatter alloc] init];    [full setDateFormat:@"dd.MM.yy"];
	}

	if (age < 24 * 3600)     return [time stringFromDate:date];
	if (age < 7 * 24 * 3600) return [weekday stringFromDate:date];
	return [full stringFromDate:date];
}

@interface TGTopicCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *badgeBackground;
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, strong) UIImageView *arrow;
@property (nonatomic, strong) UIImageView *pinIcon;
@end

@implementation TGTopicCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.avatar = [[UIImageView alloc] initWithFrame:
			CGRectMake(kTopicAvatarLeft, 8, kTopicAvatar, kTopicAvatar)];
	self.avatar.layer.cornerRadius = 5.0f;
	self.avatar.clipsToBounds = YES;
	self.avatar.backgroundColor = [UIColor clearColor];
	self.avatar.contentMode = UIViewContentModeScaleAspectFill;
	[self.contentView addSubview:self.avatar];

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.titleLabel.textColor = [UIColor colorWithRed:0x11 / 255.0f green:0x11 / 255.0f blue:0x11 / 255.0f alpha:1.0f];
	self.titleLabel.backgroundColor = [UIColor clearColor];
	self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.titleLabel];

	self.previewLabel = [[UILabel alloc] init];
	self.previewLabel.font = [UIFont systemFontOfSize:14];
	self.previewLabel.textColor = [UIColor colorWithRed:0x88 / 255.0f green:0x88 / 255.0f blue:0x88 / 255.0f alpha:1.0f];
	self.previewLabel.backgroundColor = [UIColor clearColor];
	self.previewLabel.numberOfLines = 2;
	self.previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.previewLabel];

	self.dateLabel = [[UILabel alloc] init];
	self.dateLabel.font = [UIFont systemFontOfSize:13];
	self.dateLabel.textColor = [UIColor colorWithRed:0x33 / 255.0f green:0x7a / 255.0f blue:0xcc / 255.0f alpha:1.0f];
	self.dateLabel.textAlignment = NSTextAlignmentRight;
	self.dateLabel.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:self.dateLabel];

	self.badgeBackground = [[UIImageView alloc] initWithImage:TGTopicBadgeImage()];
	self.badgeBackground.hidden = YES;
	[self.contentView addSubview:self.badgeBackground];

	self.badge = [[UILabel alloc] init];
	self.badge.font = [UIFont boldSystemFontOfSize:14];
	self.badge.textColor = [UIColor whiteColor];
	self.badge.backgroundColor = [UIColor clearColor];
	self.badge.shadowColor = [UIColor colorWithRed:0x80 / 255.0f green:0x91 / 255.0f blue:0xa6 / 255.0f alpha:1.0f];
	self.badge.shadowOffset = CGSizeMake(0, -1);
	self.badge.textAlignment = NSTextAlignmentCenter;
	self.badge.hidden = YES;
	[self.contentView addSubview:self.badge];

	self.arrow = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"DialogListArrow.png"]];
	[self.contentView addSubview:self.arrow];

	self.pinIcon = [[UIImageView alloc] initWithImage:[TGIcons menuGlyphNamed:@"pin"]];
	self.pinIcon.hidden = YES;
	[self.contentView addSubview:self.pinIcon];

	UIImage *plate = [[UIImage imageNamed:@"DialogListCell.png"]
			stretchableImageWithLeftCapWidth:1 topCapHeight:0];
	UIImage *platePressed = [[UIImage imageNamed:@"DialogListCellHighlighted.png"]
			stretchableImageWithLeftCapWidth:1 topCapHeight:0];
	self.backgroundView = [[UIImageView alloc] initWithImage:plate];
	self.selectedBackgroundView = [[UIImageView alloc] initWithImage:platePressed];

	self.accessoryType = UITableViewCellAccessoryNone;
	self.selectionStyle = UITableViewCellSelectionStyleBlue;
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.contentView.bounds.size.width;
	CGFloat left = kTopicTextLeft;
	CGFloat rightPadding = 16;

	self.avatar.frame = CGRectMake(kTopicAvatarLeft, 8, kTopicAvatar, kTopicAvatar);

	CGFloat countWidth = (int)[self.badge.text sizeWithFont:self.badge.font].width;
	CGFloat badgeWidth = MAX(27, countWidth + 10);
	CGRect badgeFrame = CGRectMake(w - 28 - badgeWidth, 29, badgeWidth, 21);
	self.badgeBackground.frame = badgeFrame;
	self.badge.frame = badgeFrame;
	if (!self.badge.hidden)
		rightPadding += badgeWidth + 7;

	CGFloat dateWidth = (int)[self.dateLabel.text sizeWithFont:self.dateLabel.font].width;
	CGFloat dateX = w - dateWidth - 9;
	self.dateLabel.frame = CGRectMake(dateX - (75 - dateWidth), 9, 75, 15);

	CGSize pinSize = self.pinIcon.image ? self.pinIcon.image.size : CGSizeZero;
	if (!self.pinIcon.hidden && pinSize.width > 0){
		self.pinIcon.frame = CGRectMake(dateX - pinSize.width - 5,
				9 + (15 - pinSize.height) / 2.0f, pinSize.width, pinSize.height);
		dateX -= pinSize.width + 5;
	}

	CGFloat titleWidth = (int)(dateX - 4 - left - 18);
	titleWidth = MIN(titleWidth, [self.titleLabel.text sizeWithFont:self.titleLabel.font].width);
	if (titleWidth < 0)
		titleWidth = 0;
	self.titleLabel.frame = CGRectMake(left, 6, titleWidth, 20);

	self.previewLabel.frame = CGRectMake(left, 29, w - left - 10 - rightPadding, 40);

	self.arrow.frame = CGRectMake(w - self.arrow.image.size.width - 6, 33,
			self.arrow.image.size.width, self.arrow.image.size.height);
}

@end

static const NSInteger kTopicNameAlertCreate = 91;
static const NSInteger kTopicNameAlertEdit = 92;

@interface TGTopicsViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *topics;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL loadedOnce;
@property (nonatomic, strong) NSArray *iconChoices;
@property (nonatomic, strong) NSDictionary *actionTopic;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@end

@implementation TGTopicsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = self.chatTitle ?: @"Topics";
	self.topics = @[];
	self.tableView.rowHeight = kTopicRowHeight;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	TGTheme *theme = [TGTheme shared];
	BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
	self.tableView.separatorStyle = plainPlate
			? UITableViewCellSeparatorStyleNone
			: UITableViewCellSeparatorStyleSingleLine;

	UIView *background = [[UIView alloc] initWithFrame:self.tableView.bounds];
	background.backgroundColor = [[TGTheme shared] listBackgroundColour];
	background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

	self.emptyLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 120, background.bounds.size.width, 22)];
	self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.emptyLabel.backgroundColor = [UIColor clearColor];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.emptyLabel.hidden = YES;
	[background addSubview:self.emptyLabel];

	self.spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	self.spinner.center = CGPointMake(background.bounds.size.width / 2.0f, 120);
	self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	self.spinner.hidesWhenStopped = YES;
	[background addSubview:self.spinner];

	self.tableView.backgroundView = background;

	if ([self respondsToSelector:@selector(setRefreshControl:)]
			&& NSClassFromString(@"UIRefreshControl")){
		UIRefreshControl *refresh = [[NSClassFromString(@"UIRefreshControl") alloc] init];
		[refresh addTarget:self action:@selector(reloadTopics)
		  forControlEvents:UIControlEventValueChanged];
		self.refreshControl = refresh;
	}

	UIButton *create = [TGIcons headerButtonWithTitle:@"New" bold:NO
											   target:self action:@selector(newTopicPressed)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:create];

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(topicHeld:)];
	[self.tableView addGestureRecognizer:hold];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] forumTopicDefaultIconsWithCompletion:^(NSArray *icons){
		weakSelf.iconChoices = [icons isKindOfClass:NSArray.class] ? icons : @[];
	}];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(themeChanged)
												 name:TGThemeChangedNotification
											   object:nil];

	[self reloadTopics];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.loadedOnce)
		[self reloadTopics];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.currentActionSheet dismissWithClickedButtonIndex:self.currentActionSheet.cancelButtonIndex
												  animated:NO];
	self.currentActionSheet = nil;
	[TGPopupMenu dismiss];
}

- (void)themeChanged {
	TGTheme *theme = [TGTheme shared];
	[theme styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	self.tableView.backgroundView.backgroundColor = [theme listBackgroundColour];
	self.emptyLabel.textColor = [theme secondaryTextColour];
	BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
	self.tableView.separatorStyle = plainPlate
			? UITableViewCellSeparatorStyleNone
			: UITableViewCellSeparatorStyleSingleLine;
	[self.tableView reloadData];
}

- (void)reloadTopics {
	if (self.loading)
		return;
	self.loading = YES;

	if (!self.loadedOnce){
		self.emptyLabel.hidden = YES;
		[self.spinner startAnimating];
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] forumTopicRowsForChat:self.chatId completion:^(NSArray *topics){
		TGTopicsViewController *me = weakSelf;
		if (!me)
			return;
		me.loading = NO;
		me.loadedOnce = YES;
		[me.spinner stopAnimating];
		if ([me respondsToSelector:@selector(refreshControl)])
			[me.refreshControl endRefreshing];

		NSMutableArray *clean = [NSMutableArray array];
		if ([topics isKindOfClass:NSArray.class]){
			for (id topic in topics){
				if ([topic isKindOfClass:NSDictionary.class])
					[clean addObject:topic];
			}
		}
		me.topics = clean;

		me.emptyLabel.text = @"No topics";
		me.emptyLabel.hidden = (clean.count > 0);

		[me.tableView reloadData];
		NSLog(@"TDLIB TOPICS: %lu", (unsigned long)clean.count);
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.topics.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGTopicCell";
	TGTopicCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGTopicCell alloc] initWithStyle:UITableViewCellStyleDefault
								  reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
	cell.backgroundColor = [theme listBackgroundColour];
	cell.backgroundView.hidden = !plainPlate;
	cell.titleLabel.textColor = [theme primaryTextColour];
	cell.previewLabel.textColor = [theme secondaryTextColour];
	cell.dateLabel.textColor = [theme accentColour];
	cell.dateLabel.text = @"";
	cell.previewLabel.text = @"";
	cell.badge.text = @"";
	cell.badge.hidden = YES;
	cell.badgeBackground.hidden = YES;
	cell.pinIcon.hidden = YES;

	if (indexPath.row >= (NSInteger)self.topics.count)
		return cell;

	NSDictionary *t = self.topics[indexPath.row];
	NSInteger unread = [t[@"unread"] respondsToSelector:@selector(integerValue)]
			? [t[@"unread"] integerValue] : 0;

	NSString *name = [t[@"name"] isKindOfClass:NSString.class] ? t[@"name"] : @"";
	NSString *preview = [t[@"text"] isKindOfClass:NSString.class] ? t[@"text"] : @"";
	NSString *title = name.length ? name : @"Topic";
	BOOL closed = [t[@"isClosed"] boolValue];
	BOOL hidden = [t[@"isHidden"] boolValue];

	cell.titleLabel.text = title;
	if (closed)
		cell.previewLabel.text = preview.length
				? [NSString stringWithFormat:@"Closed · %@", preview]
				: @"Closed";
	else if (hidden)
		cell.previewLabel.text = preview.length
				? [NSString stringWithFormat:@"Hidden · %@", preview]
				: @"Hidden";
	else
		cell.previewLabel.text = preview;
	cell.dateLabel.text = TGTopicDate([t[@"date"] doubleValue]);
	cell.pinIcon.hidden = ![t[@"isPinned"] boolValue];

	long long colourId = [self topicIdOf:t];
	if ([t[@"iconColor"] respondsToSelector:@selector(longLongValue)])
		colourId = [t[@"iconColor"] longLongValue];
	cell.avatar.image = [TGIcons avatarWithInitials:[title substringToIndex:1].uppercaseString
											   size:kTopicAvatar
										   colourId:colourId];

	if (unread > 0){
		cell.badge.text = unread < 1000
				? [NSString stringWithFormat:@"%ld", (long)unread]
				: [NSString stringWithFormat:@"%ldK", (long)(unread / 1000)];
		cell.badge.hidden = NO;
		cell.badgeBackground.hidden = NO;
	}

	[cell setNeedsLayout];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.row >= (NSInteger)self.topics.count)
		return;

	NSDictionary *t = self.topics[indexPath.row];
	long long threadId = [t[@"threadId"] respondsToSelector:@selector(longLongValue)]
			? [t[@"threadId"] longLongValue] : 0;
	if (threadId == 0)
		return;

	NSString *name = [t[@"name"] isKindOfClass:NSString.class] ? t[@"name"] : @"";
	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = self.chatId;
	vc.threadId = threadId;
	vc.chatTitle = name.length ? name : @"Topic";
	vc.isGroup = YES;
	[self.navigationController pushViewController:vc animated:YES];

	int32_t topicId = [self topicIdOf:t];
	if (topicId != 0 && [t[@"unread"] integerValue] > 0)
		[[TGClient shared] markForumTopicReadInChat:self.chatId topic:topicId completion:nil];
}

#pragma mark - topic actions

- (int32_t)topicIdOf:(NSDictionary *)topic {
	id value = topic[@"topicId"];
	if (![value respondsToSelector:@selector(intValue)])
		value = topic[@"threadId"];
	return [value respondsToSelector:@selector(intValue)] ? (int32_t)[value intValue] : 0;
}

- (void)showError:(NSString *)message {
	[[[UIAlertView alloc] initWithTitle:nil message:message delegate:nil
					  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (void)topicHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;

	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:
			[hold locationInView:self.tableView]];
	if (!path || path.row >= (NSInteger)self.topics.count)
		return;

	NSDictionary *t = self.topics[path.row];
	self.actionTopic = t;

	BOOL general = [t[@"isGeneral"] boolValue];
	BOOL closed = [t[@"isClosed"] boolValue];
	BOOL pinned = [t[@"isPinned"] boolValue];
	BOOL hidden = [t[@"isHidden"] boolValue];

	NSMutableArray *items = [NSMutableArray array];
	NSMutableArray *keys = [NSMutableArray array];

	if (!general){
		[items addObject:@{@"title" : @"Edit", @"icon" : @"edit"}];
		[keys addObject:@"edit"];
	}
	[items addObject:@{@"title" : (pinned ? @"Unpin" : @"Pin"),
					   @"icon"  : (pinned ? @"unpin" : @"pin")}];
	[keys addObject:@"pin"];

	if (!general){
		[items addObject:@{@"title" : (closed ? @"Reopen" : @"Close"),
						   @"icon"  : (closed ? @"unmute" : @"mute")}];
		[keys addObject:@"close"];
	}
	if (general){
		[items addObject:@{@"title" : (hidden ? @"Show" : @"Hide"),
						   @"icon"  : (hidden ? @"unmute" : @"mute")}];
		[keys addObject:@"hide"];
	}

	CGRect rect = [self.tableView rectForRowAtIndexPath:path];
	CGPoint where = [self.tableView convertPoint:
			CGPointMake(120, CGRectGetMaxY(rect) - 10) toView:self.navigationController.view];

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		if (choice < 0 || choice >= (NSInteger)keys.count)
			return;
		[weakSelf runTopicAction:keys[choice]];
	}];
}

- (void)runTopicAction:(NSString *)key {
	NSDictionary *t = self.actionTopic;
	if (!t)
		return;

	int32_t topicId = [self topicIdOf:t];
	__weak typeof(self) weakSelf = self;

	if ([key isEqualToString:@"edit"]){
		[self askTopicNameForEdit:t];
		return;
	}

	if ([key isEqualToString:@"pin"]){
		BOOL pin = ![t[@"isPinned"] boolValue];
		[[TGClient shared] setForumTopicInChat:self.chatId topic:topicId pinned:pin
									completion:^(BOOL success){
			if (!success)
				[weakSelf showError:pin ? @"Could not pin the topic."
									   : @"Could not unpin the topic."];
			[weakSelf reloadTopics];
		}];
	} else if ([key isEqualToString:@"close"]){
		BOOL close = ![t[@"isClosed"] boolValue];
		[[TGClient shared] setForumTopicInChat:self.chatId topic:topicId closed:close
									completion:^(BOOL success){
			if (!success)
				[weakSelf showError:close ? @"Could not close the topic."
										 : @"Could not reopen the topic."];
			[weakSelf reloadTopics];
		}];
	} else if ([key isEqualToString:@"hide"]){
		BOOL hide = ![t[@"isHidden"] boolValue];
		[[TGClient shared] setGeneralForumTopicInChat:self.chatId hidden:hide
										   completion:^(BOOL success){
			if (!success)
				[weakSelf showError:hide ? @"Could not hide the General topic."
										: @"Could not show the General topic."];
			[weakSelf reloadTopics];
		}];
	}

	self.actionTopic = nil;
}

#pragma mark - create and rename

- (void)newTopicPressed {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New Topic"
													message:@"Name the topic."
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Create", nil];
	alert.tag = kTopicNameAlertCreate;
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	[alert show];
}

- (void)askTopicNameForEdit:(NSDictionary *)topic {
	self.actionTopic = topic;
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Edit Topic"
													message:@"Name the topic."
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Save", nil];
	alert.tag = kTopicNameAlertEdit;
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)]){
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
		NSString *name = [topic[@"name"] isKindOfClass:NSString.class] ? topic[@"name"] : @"";
		[alert textFieldAtIndex:0].text = name;
	}
	[alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	if (![alertView respondsToSelector:@selector(textFieldAtIndex:)])
		return;

	NSString *name = [[alertView textFieldAtIndex:0].text
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (name.length == 0){
		[self showError:@"The topic needs a name."];
		return;
	}

	if (alertView.tag == kTopicNameAlertCreate)
		[self chooseIconForName:name editing:NO];
	else if (alertView.tag == kTopicNameAlertEdit)
		[self chooseIconForName:name editing:YES];
}

- (NSArray *)availableIconChoices {
	NSMutableArray *clean = [NSMutableArray array];
	for (id icon in self.iconChoices){
		if (![icon isKindOfClass:NSDictionary.class])
			continue;
		NSString *emoji = [icon[@"emoji"] isKindOfClass:NSString.class] ? icon[@"emoji"] : nil;
		if (!emoji.length)
			continue;
		[clean addObject:icon];
		if (clean.count >= 8)
			break;
	}
	return clean;
}

- (void)chooseIconForName:(NSString *)name editing:(BOOL)editing {
	NSArray *icons = [self availableIconChoices];
	NSMutableArray *actions = [NSMutableArray array];

	[actions addObject:[[TGActionSheetAction alloc]
			initWithTitle:(editing ? @"Keep Icon" : @"No Icon") action:@"none"]];

	for (NSUInteger i = 0; i < icons.count; i++){
		NSDictionary *icon = icons[i];
		[actions addObject:[[TGActionSheetAction alloc]
				initWithTitle:icon[@"emoji"]
					   action:[NSString stringWithFormat:@"icon%lu", (unsigned long)i]]];
	}

	if (editing)
		[actions addObject:[[TGActionSheetAction alloc]
				initWithTitle:@"Colour Only" action:@"clear"]];

	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
															type:TGActionSheetActionTypeCancel]];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:nil actions:actions
													  actionBlock:^(id target, NSString *action){
		TGTopicsViewController *me = weakSelf;
		me.currentActionSheet = nil;
		if (!me || [action isEqualToString:@"cancel"])
			return;

		int64_t emojiId = 0;
		BOOL changeIcon = YES;
		if ([action isEqualToString:@"none"])
			changeIcon = !editing;
		else if (![action isEqualToString:@"clear"]){
			NSInteger index = [[action substringFromIndex:4] integerValue];
			if (index >= 0 && index < (NSInteger)icons.count)
				emojiId = [icons[(NSUInteger)index][@"emojiId"] longLongValue];
		}

		if (editing)
			[me commitEditWithName:name changeIcon:changeIcon iconEmojiId:emojiId];
		else
			[me commitCreateWithName:name iconEmojiId:emojiId];
	} target:self];

	[self.currentActionSheet showInView:self.navigationController.view];
}

- (NSInteger)iconColourForName:(NSString *)name {
	NSArray *colours = [[TGClient shared] forumTopicIconColors];
	if (colours.count == 0)
		return 0;
	NSUInteger index = (NSUInteger)labs((long)name.hash) % colours.count;
	return [colours[index] integerValue];
}

- (void)commitCreateWithName:(NSString *)name iconEmojiId:(int64_t)emojiId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] createForumTopicInChat:self.chatId
										 name:name
									iconColor:[self iconColourForName:name]
								  iconEmojiId:emojiId
								   completion:^(NSDictionary *topic){
		if (!topic)
			[weakSelf showError:@"Could not create the topic."];
		[weakSelf reloadTopics];
	}];
}

- (void)commitEditWithName:(NSString *)name changeIcon:(BOOL)changeIcon iconEmojiId:(int64_t)emojiId {
	NSDictionary *t = self.actionTopic;
	if (!t)
		return;

	int32_t topicId = [self topicIdOf:t];
	self.actionTopic = nil;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] editForumTopicInChat:self.chatId
									  topic:topicId
									   name:name
								 changeIcon:changeIcon
								iconEmojiId:emojiId
								 completion:^(BOOL success){
		if (!success)
			[weakSelf showError:@"Could not edit the topic."];
		[weakSelf reloadTopics];
	}];
}

@end

// vim:ft=objc

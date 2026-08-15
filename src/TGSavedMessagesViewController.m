#import "TGSavedMessagesViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGClient+SavedMessages.h"
#import "TGClient+Files.h"
#import "TGClient+Messages.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGPopupMenu.h"
#import <QuartzCore/QuartzCore.h>

static NSString *const TGSavedShowsTopicsKey = @"TGSavedMessagesShowsTopics";

static const CGFloat kSavedRowHeight = 73.0f;
static const CGFloat kSavedAvatar = 56.0f;
static const CGFloat kSavedAvatarLeft = 8.0f;
static const CGFloat kSavedTextLeft = 73.0f;
static const CGFloat kSavedMessageRowHeight = 51.0f;
static const NSInteger kSavedTopicPage = 40;
static const NSInteger kSavedHistoryPage = 40;

static const NSInteger kSavedDeleteAlertTag = 71;
static const NSInteger kSavedRangeAlertTag = 72;
static const NSInteger kSavedReminderAlertTag = 73;
static const NSInteger kSavedRangeSheetTag = 74;
static const NSInteger kSavedReminderSheetTag = 75;
static const NSInteger kSavedPinnedSheetTag = 76;
static const NSInteger kSavedJumpSheetTag = 77;
static const NSInteger kSavedUnpinAllAlertTag = 78;
static const NSInteger kSavedJumpStops = 6;
static const CGFloat kSavedBannerHeight = 42.0f;

static NSString *TGSavedDate(NSTimeInterval unix) {
	if (unix <= 0)
		return @"";

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:unix];
	NSTimeInterval age = -[date timeIntervalSinceNow];

	static NSDateFormatter *time = nil, *weekday = nil, *full = nil;
	if (!time){
		NSLocale *fixed = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		time = [[NSDateFormatter alloc] init];    [time setLocale:fixed];    [time setDateFormat:@"HH:mm"];
		weekday = [[NSDateFormatter alloc] init]; [weekday setLocale:fixed]; [weekday setDateFormat:@"EEE"];
		full = [[NSDateFormatter alloc] init];    [full setLocale:fixed];    [full setDateFormat:@"dd.MM.yy"];
	}

	if (age < 24 * 3600)     return [time stringFromDate:date];
	if (age < 7 * 24 * 3600) return [weekday stringFromDate:date];
	return [full stringFromDate:date];
}

static NSString *TGSavedDayStamp(NSTimeInterval unix) {
	if (unix <= 0)
		return @"";

	static NSDateFormatter *day = nil;
	if (!day){
		day = [[NSDateFormatter alloc] init];
		[day setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
		[day setDateFormat:@"d MMM yyyy"];
	}
	return [day stringFromDate:[NSDate dateWithTimeIntervalSince1970:unix]];
}

static NSString *TGSavedShortText(NSDictionary *message, NSUInteger limit) {
	NSString *text = message[@"text"];
	if (![text isKindOfClass:NSString.class] || !text.length)
		text = @"Media";
	if (text.length > limit)
		text = [[text substringToIndex:limit] stringByAppendingString:@"…"];
	return text;
}

static NSString *TGSavedTopicKind(NSDictionary *topic) {
	NSString *kind = topic[@"kind"];
	return [kind isKindOfClass:NSString.class] ? kind : @"";
}

static NSString *TGSavedTopicTitle(NSDictionary *topic) {
	NSString *title = topic[@"title"];
	if ([title isKindOfClass:NSString.class] && title.length)
		return title;

	NSString *kind = TGSavedTopicKind(topic);
	if ([kind isEqualToString:@"myNotes"])
		return @"My Notes";
	if ([kind isEqualToString:@"authorHidden"])
		return @"Hidden Author";

	int64_t chatId = [topic[@"chatId"] longLongValue];
	NSString *name = chatId ? [[TGClient shared] nameForUserId:chatId] : nil;
	return name.length ? name : @"Saved Messages";
}

#pragma mark - the messages of one topic

@interface TGSavedTopicController : UITableViewController <UIActionSheetDelegate, UIAlertViewDelegate>

@property (nonatomic, assign) int64_t topicId;
@property (nonatomic, copy)   NSString *topicTitle;
@property (nonatomic, strong) NSMutableArray *messages;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL exhausted;
@property (nonatomic, strong) NSDictionary *pinnedMessage;
@property (nonatomic, strong) UIButton *pinnedBanner;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) NSArray *jumpDates;
@property (nonatomic, assign) NSInteger totalCount;
@property (nonatomic, assign) int64_t menuMessageId;
@property (nonatomic, assign) BOOL menuMessagePinned;

@end

@implementation TGSavedTopicController

- (void)viewDidLoad {
	[super viewDidLoad];

	TGTheme *theme = [TGTheme shared];
	[theme styleNavigationBar:self.navigationController.navigationBar];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = self.topicTitle.length ? self.topicTitle : @"Saved Messages";
	self.messages = [NSMutableArray array];

	[self buildTableBackground];

	UIButton *chat = [TGIcons headerButtonWithTitle:@"More" bold:NO
											 target:self action:@selector(showTopicMenu)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:chat];

	[self buildPinnedBanner];
	[self buildCountFooter];

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(messageHeld:)];
	[self.tableView addGestureRecognizer:hold];

	[self loadOlder];
	[self reloadPinnedBanner];
	[self reloadPositions];
}

- (void)buildTableBackground {
	TGTheme *theme = [TGTheme shared];

	self.tableView.rowHeight = kSavedMessageRowHeight;
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];

	UIView *background = [[UIView alloc] initWithFrame:self.tableView.bounds];
	background.backgroundColor = [theme listBackgroundColour];
	background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

	self.emptyLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 120, background.bounds.size.width, 22)];
	self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.emptyLabel.backgroundColor = [UIColor clearColor];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.textColor = [theme secondaryTextColour];
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
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	NSDictionary *topic = [[TGClient shared] cachedSavedMessagesTopic:self.topicId];
	if (topic){
		NSString *title = TGSavedTopicTitle(topic);
		if (title.length){
			self.topicTitle = title;
			self.title = title;
		}
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[TGPopupMenu dismiss];
}

#pragma mark - the pinned message of Saved Messages

- (void)buildPinnedBanner {
	TGTheme *theme = [TGTheme shared];

	UIButton *banner = [UIButton buttonWithType:UIButtonTypeCustom];
	banner.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, kSavedBannerHeight);
	banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	banner.backgroundColor = [theme listBackgroundColour];
	banner.titleLabel.font = [UIFont systemFontOfSize:14];
	banner.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
	banner.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
	[banner setTitleColor:[theme accentColour] forState:UIControlStateNormal];
	[banner addTarget:self action:@selector(showPinnedSheet)
	 forControlEvents:UIControlEventTouchUpInside];

	UIView *line = [[UIView alloc] initWithFrame:
			CGRectMake(0, kSavedBannerHeight - 1, banner.bounds.size.width, 1)];
	line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	line.backgroundColor = [theme separatorColour];
	[banner addSubview:line];

	self.pinnedBanner = banner;
}

- (void)buildCountFooter {
	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 0, self.tableView.bounds.size.width, 34)];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	label.backgroundColor = [UIColor clearColor];
	label.textAlignment = NSTextAlignmentCenter;
	label.font = [UIFont systemFontOfSize:13];
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.text = @"";
	self.countLabel = label;
}

- (void)reloadPinnedBanner {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] savedMessagesPinnedMessageWithCompletion:^(NSDictionary *message){
		TGSavedTopicController *me = weakSelf;
		if (!me)
			return;
		me.pinnedMessage = [message isKindOfClass:NSDictionary.class] ? message : nil;
		[me updatePinnedBanner];
	}];
}

- (void)updatePinnedBanner {
	if (!self.pinnedMessage){
		self.tableView.tableHeaderView = nil;
		return;
	}

	[self.pinnedBanner setTitle:[NSString stringWithFormat:@"Pinned: %@",
			TGSavedShortText(self.pinnedMessage, 30)] forState:UIControlStateNormal];
	if (self.tableView.tableHeaderView != self.pinnedBanner)
		self.tableView.tableHeaderView = self.pinnedBanner;
}

- (void)showPinnedSheet {
	if (!self.pinnedMessage)
		return;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:
			TGSavedShortText(self.pinnedMessage, 60)
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"Unpin"];
	[sheet addButtonWithTitle:@"Unpin All"];
	[sheet addButtonWithTitle:@"Cancel"];
	sheet.cancelButtonIndex = 2;
	sheet.tag = kSavedPinnedSheetTag;
	[sheet showInView:self.navigationController.view];
}

- (void)unpinPinnedMessage {
	int64_t messageId = [self.pinnedMessage[@"id"] longLongValue];
	if (!messageId)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] unpinSavedMessage:messageId completion:^(BOOL ok){
		TGSavedTopicController *me = weakSelf;
		if (!me)
			return;
		if (!ok)
			[me showError:@"Could not unpin that message."];
		[me reloadPinnedBanner];
	}];
}

- (void)confirmUnpinAll {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Unpin All"
													message:@"Unpin every message in Saved Messages?"
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Unpin All", nil];
	alert.tag = kSavedUnpinAllAlertTag;
	[alert show];
}

- (void)showError:(NSString *)message {
	[[[UIAlertView alloc] initWithTitle:nil message:message delegate:nil
					  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

#pragma mark - positions and jumping to a date

- (void)reloadPositions {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] savedMessagesSparsePositionsForTopic:self.topicId
												fromMessage:0
													  limit:0
												 completion:^(NSArray *positions, NSInteger totalCount){
		TGSavedTopicController *me = weakSelf;
		if (!me)
			return;
		me.totalCount = totalCount;

		NSMutableArray *dates = [NSMutableArray array];
		if ([positions isKindOfClass:NSArray.class] && positions.count){
			NSInteger step = ((NSInteger)positions.count + kSavedJumpStops - 1) / kSavedJumpStops;
			if (step < 1)
				step = 1;
			for (NSInteger i = 0; i < (NSInteger)positions.count; i += step){
				id entry = positions[(NSUInteger)i];
				if (![entry isKindOfClass:NSDictionary.class])
					continue;
				NSInteger date = [entry[@"date"] integerValue];
				if (date > 0 && ![dates containsObject:@(date)])
					[dates addObject:@(date)];
			}
		}
		me.jumpDates = dates;

		if (totalCount > 0){
			me.countLabel.text = (totalCount == 1)
					? @"1 message"
					: [NSString stringWithFormat:@"%d messages", (int)totalCount];
			me.tableView.tableFooterView = me.countLabel;
		}
	}];
}

- (void)showJumpSheet {
	if (self.jumpDates.count == 0){
		[self showError:@"No dates to jump to yet."];
		return;
	}

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Jump to Date"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	for (NSNumber *date in self.jumpDates)
		[sheet addButtonWithTitle:TGSavedDayStamp([date doubleValue])];

	[sheet addButtonWithTitle:@"Cancel"];
	sheet.cancelButtonIndex = (NSInteger)self.jumpDates.count;
	sheet.tag = kSavedJumpSheetTag;
	[sheet showInView:self.navigationController.view];
}

- (void)jumpToDate:(NSInteger)date {
	[self.spinner startAnimating];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] savedMessagesTopic:self.topicId
							messageAtDate:date
							   completion:^(NSDictionary *message){
		TGSavedTopicController *me = weakSelf;
		if (!me)
			return;
		[me.spinner stopAnimating];

		if (![message isKindOfClass:NSDictionary.class] || ![message[@"id"] longLongValue]){
			[me showError:@"No message on that date."];
			return;
		}

		me.messages = [NSMutableArray arrayWithObject:message];
		me.exhausted = NO;
		me.loading = NO;
		me.emptyLabel.hidden = YES;
		[me.tableView reloadData];
		[me.tableView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];
		[me loadOlder];
	}];
}

#pragma mark - menus

- (void)showTopicMenu {
	NSMutableArray *items = [NSMutableArray array];
	NSMutableArray *keys = [NSMutableArray array];

	[items addObject:@{@"title" : @"Open Chat", @"icon" : @"chat"}];
	[keys addObject:@"chat"];

	[items addObject:@{@"title" : @"Jump to Date", @"icon" : @"search"}];
	[keys addObject:@"jump"];

	if (self.pinnedMessage){
		[items addObject:@{@"title" : @"Pinned Message", @"icon" : @"pin"}];
		[keys addObject:@"pinned"];
	}

	CGPoint where = CGPointMake(self.navigationController.view.bounds.size.width - 30, 44);

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		TGSavedTopicController *me = weakSelf;
		if (!me || choice < 0 || choice >= (NSInteger)keys.count)
			return;
		NSString *key = keys[choice];
		if ([key isEqualToString:@"chat"])
			[me openChat];
		else if ([key isEqualToString:@"jump"])
			[me showJumpSheet];
		else if ([key isEqualToString:@"pinned"])
			[me showPinnedSheet];
	}];
}

- (void)messageHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;

	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:
			[hold locationInView:self.tableView]];
	if (!path || path.row >= (NSInteger)self.messages.count)
		return;

	NSDictionary *message = self.messages[path.row];
	int64_t messageId = [message[@"id"] longLongValue];
	if (!messageId)
		return;

	self.menuMessageId = messageId;
	self.menuMessagePinned = [message[@"isPinned"] boolValue];

	NSArray *items = @[@{@"title" : (self.menuMessagePinned ? @"Unpin" : @"Pin"),
						 @"icon"  : (self.menuMessagePinned ? @"unpin" : @"pin")}];

	CGRect rect = [self.tableView rectForRowAtIndexPath:path];
	CGPoint where = [self.tableView convertPoint:
			CGPointMake(120, CGRectGetMaxY(rect) - 10) toView:self.navigationController.view];

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		if (choice == 0)
			[weakSelf togglePinOfMenuMessage];
	}];
}

- (void)togglePinOfMenuMessage {
	int64_t messageId = self.menuMessageId;
	if (!messageId)
		return;
	BOOL pinned = self.menuMessagePinned;
	self.menuMessageId = 0;

	__weak typeof(self) weakSelf = self;
	void (^done)(BOOL) = ^(BOOL ok){
		TGSavedTopicController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[me showError:pinned ? @"Could not unpin that message."
								 : @"Could not pin that message."];
			return;
		}
		[me markMessage:messageId pinned:!pinned];
		[me reloadPinnedBanner];
	};

	if (pinned)
		[[TGClient shared] unpinSavedMessage:messageId completion:done];
	else
		[[TGClient shared] pinSavedMessage:messageId completion:done];
}

- (void)markMessage:(int64_t)messageId pinned:(BOOL)pinned {
	for (NSUInteger i = 0; i < self.messages.count; i++){
		NSDictionary *message = self.messages[i];
		if ([message[@"id"] longLongValue] != messageId)
			continue;
		NSMutableDictionary *updated = [message mutableCopy];
		updated[@"isPinned"] = @(pinned);
		self.messages[i] = updated;
		[self.tableView reloadData];
		return;
	}
}

#pragma mark - sheets and alerts

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == kSavedPinnedSheetTag){
		if (index == 0)
			[self unpinPinnedMessage];
		else if (index == 1)
			[self confirmUnpinAll];
		return;
	}

	if (sheet.tag == kSavedJumpSheetTag){
		if (index < 0 || index >= (NSInteger)self.jumpDates.count)
			return;
		[self jumpToDate:[self.jumpDates[index] integerValue]];
	}
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (alertView.tag != kSavedUnpinAllAlertTag || buttonIndex == alertView.cancelButtonIndex)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] unpinAllSavedMessagesWithCompletion:^(BOOL ok){
		TGSavedTopicController *me = weakSelf;
		if (!me)
			return;
		if (!ok)
			[me showError:@"Could not unpin the messages."];
		[me reloadPinnedBanner];
	}];
}

- (void)openChat {
	int64_t chatId = [[TGClient shared] savedMessagesChatId];
	if (!chatId)
		return;
	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = chatId;
	vc.chatTitle = @"Saved Messages";
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)loadOlder {
	if (self.loading || self.exhausted)
		return;
	self.loading = YES;

	if (self.messages.count == 0){
		self.emptyLabel.hidden = YES;
		[self.spinner startAnimating];
	}

	int64_t from = 0;
	if (self.messages.count){
		NSDictionary *oldest = [self.messages lastObject];
		from = [oldest[@"id"] longLongValue];
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] savedMessagesTopicHistory:self.topicId
									 fromMessage:from
										   limit:kSavedHistoryPage
									  completion:^(NSArray *messages){
		TGSavedTopicController *me = weakSelf;
		if (!me)
			return;
		me.loading = NO;
		[me.spinner stopAnimating];

		NSMutableArray *clean = [NSMutableArray array];
		if ([messages isKindOfClass:NSArray.class]){
			for (id message in messages){
				if ([message isKindOfClass:NSDictionary.class])
					[clean addObject:message];
			}
		}
		if (clean.count == 0)
			me.exhausted = YES;

		for (NSInteger i = (NSInteger)clean.count - 1; i >= 0; i--)
			[me.messages addObject:clean[(NSUInteger)i]];

		me.emptyLabel.text = @"No messages";
		me.emptyLabel.hidden = (me.messages.count > 0);
		[me.tableView reloadData];
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGSavedMessageCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	[theme styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.text = @"";
	cell.detailTextLabel.text = @"";

	if (indexPath.row >= (NSInteger)self.messages.count)
		return cell;

	NSDictionary *message = self.messages[indexPath.row];
	NSString *text = message[@"text"];
	if (![text isKindOfClass:NSString.class] || !text.length)
		text = @"Media";

	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.textLabel.numberOfLines = 1;
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.textLabel.text = text;

	NSArray *tags = message[@"tags"];
	NSString *tagLine = @"";
	if ([tags isKindOfClass:NSArray.class] && tags.count)
		tagLine = [NSString stringWithFormat:@"%@  ", [tags componentsJoinedByString:@" "]];

	int date = [message[@"date"] intValue];
	NSString *pinMark = [message[@"isPinned"] boolValue] ? @"Pinned  " : @"";
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@%@",
			pinMark, tagLine, date ? TGSavedDate(date) : @""];
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= (NSInteger)self.messages.count - 3)
		[self loadOlder];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self openChat];
}

@end

#pragma mark - the topic row

@interface TGSavedTopicCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *pinIcon;
@property (nonatomic, strong) UIImageView *arrow;
@end

@implementation TGSavedTopicCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.avatar = [[UIImageView alloc] initWithFrame:
			CGRectMake(kSavedAvatarLeft, 8, kSavedAvatar, kSavedAvatar)];
	self.avatar.layer.cornerRadius = 5.0f;
	self.avatar.clipsToBounds = YES;
	self.avatar.backgroundColor = [UIColor clearColor];
	self.avatar.contentMode = UIViewContentModeScaleAspectFill;
	[self.contentView addSubview:self.avatar];

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.titleLabel.backgroundColor = [UIColor clearColor];
	self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.titleLabel];

	self.previewLabel = [[UILabel alloc] init];
	self.previewLabel.font = [UIFont systemFontOfSize:14];
	self.previewLabel.backgroundColor = [UIColor clearColor];
	self.previewLabel.numberOfLines = 2;
	self.previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.previewLabel];

	self.dateLabel = [[UILabel alloc] init];
	self.dateLabel.font = [UIFont systemFontOfSize:13];
	self.dateLabel.textAlignment = NSTextAlignmentRight;
	self.dateLabel.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:self.dateLabel];

	self.pinIcon = [[UIImageView alloc] initWithImage:[TGIcons menuGlyphNamed:@"pin"]];
	self.pinIcon.hidden = YES;
	[self.contentView addSubview:self.pinIcon];

	self.arrow = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"DialogListArrow.png"]];
	[self.contentView addSubview:self.arrow];

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
	CGFloat left = kSavedTextLeft;

	self.avatar.frame = CGRectMake(kSavedAvatarLeft, 8, kSavedAvatar, kSavedAvatar);

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

	self.previewLabel.frame = CGRectMake(left, 29, w - left - 26, 40);

	CGSize arrowSize = self.arrow.image ? self.arrow.image.size : CGSizeZero;
	self.arrow.frame = CGRectMake(w - arrowSize.width - 6, 33, arrowSize.width, arrowSize.height);
}

@end

#pragma mark - the topics list

@interface TGSavedMessagesViewController () <UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) NSArray *topics;
@property (nonatomic, strong) NSArray *reminders;
@property (nonatomic, strong) UIButton *reminderBanner;
@property (nonatomic, strong) NSDictionary *pendingReminder;
@property (nonatomic, assign) int64_t rangeTopicId;
@property (nonatomic, copy)   NSString *rangeTopicTitle;
@property (nonatomic, assign) NSInteger rangeMinDate;
@property (nonatomic, assign) NSInteger rangeMaxDate;
@property (nonatomic, strong) NSMutableDictionary *avatars;
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@property (nonatomic, strong) UIView *emptyContainer;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL loadedOnce;
@property (nonatomic, assign) BOOL reordering;
@property (nonatomic, assign) BOOL orderDirty;
@property (nonatomic, strong) NSDictionary *actionTopic;
@property (nonatomic, assign) CGPoint menuPoint;
@end

@implementation TGSavedMessagesViewController

+ (BOOL)showsTopics {
	return [[NSUserDefaults standardUserDefaults] boolForKey:TGSavedShowsTopicsKey];
}

+ (void)setShowsTopics:(BOOL)showsTopics {
	[[NSUserDefaults standardUserDefaults] setBool:showsTopics forKey:TGSavedShowsTopicsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	TGTheme *theme = [TGTheme shared];
	[theme styleNavigationBar:self.navigationController.navigationBar];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Saved Messages";
	self.topics = @[];
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];

	[self buildTableBackground];

	[self showListButtons];

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(topicHeld:)];
	[self.tableView addGestureRecognizer:hold];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(themeChanged)
												 name:TGThemeChangedNotification
											   object:nil];

	[self buildReminderBanner];

	[TGSavedMessagesViewController setShowsTopics:YES];
	[self reloadTopics];
}

- (void)buildTableBackground {
	TGTheme *theme = [TGTheme shared];

	self.tableView.rowHeight = kSavedRowHeight;
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];

	BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
	self.tableView.separatorStyle = plainPlate
			? UITableViewCellSeparatorStyleNone
			: UITableViewCellSeparatorStyleSingleLine;

	UIView *background = [[UIView alloc] initWithFrame:self.tableView.bounds];
	background.backgroundColor = [theme listBackgroundColour];
	background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self buildEmptyContainerInside:background];

	self.spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	self.spinner.center = CGPointMake(background.bounds.size.width / 2.0f, 120);
	self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	self.spinner.hidesWhenStopped = YES;
	[background addSubview:self.spinner];

	self.tableView.backgroundView = background;
}

- (void)buildReminderBanner {
	TGTheme *theme = [TGTheme shared];

	UIButton *banner = [UIButton buttonWithType:UIButtonTypeCustom];
	banner.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, kSavedBannerHeight);
	banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	banner.backgroundColor = [theme listBackgroundColour];
	banner.titleLabel.font = [UIFont boldSystemFontOfSize:15];
	banner.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
	banner.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
	[banner setTitleColor:[theme accentColour] forState:UIControlStateNormal];
	[banner addTarget:self action:@selector(showReminders)
	 forControlEvents:UIControlEventTouchUpInside];

	UIView *line = [[UIView alloc] initWithFrame:
			CGRectMake(0, kSavedBannerHeight - 1, banner.bounds.size.width, 1)];
	line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	line.backgroundColor = [theme separatorColour];
	[banner addSubview:line];

	self.reminderBanner = banner;
	self.reminders = @[];
}

#pragma mark - reminders

- (void)reloadReminders {
	int64_t chatId = [[TGClient shared] savedMessagesChatId];
	if (!chatId)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] scheduledMessagesInChat:chatId completion:^(NSArray *messages){
		TGSavedMessagesViewController *me = weakSelf;
		if (!me)
			return;

		NSMutableArray *clean = [NSMutableArray array];
		if ([messages isKindOfClass:NSArray.class]){
			for (id message in messages){
				if ([message isKindOfClass:NSDictionary.class])
					[clean addObject:message];
			}
		}
		me.reminders = clean;
		[me updateReminderBanner];
	}];
}

- (void)updateReminderBanner {
	if (self.reminders.count == 0){
		self.tableView.tableHeaderView = nil;
		return;
	}

	NSString *title = (self.reminders.count == 1)
			? @"1 Reminder"
			: [NSString stringWithFormat:@"%d Reminders", (int)self.reminders.count];
	[self.reminderBanner setTitle:title forState:UIControlStateNormal];
	self.reminderBanner.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[self.reminderBanner setTitleColor:[[TGTheme shared] accentColour]
							  forState:UIControlStateNormal];

	if (self.tableView.tableHeaderView != self.reminderBanner)
		self.tableView.tableHeaderView = self.reminderBanner;
}

- (NSString *)titleForReminder:(NSDictionary *)reminder {
	NSString *text = TGSavedShortText(reminder, 24);

	NSTimeInterval when = [reminder[@"sendDate"] doubleValue];
	if (when <= 0)
		return text;

	static NSDateFormatter *stamp = nil;
	if (!stamp){
		stamp = [[NSDateFormatter alloc] init];
		[stamp setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
		[stamp setDateFormat:@"dd.MM HH:mm"];
	}
	return [NSString stringWithFormat:@"%@  %@",
			[stamp stringFromDate:[NSDate dateWithTimeIntervalSince1970:when]], text];
}

- (void)showReminders {
	if (self.reminders.count == 0)
		return;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Reminders"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	NSInteger shown = MIN((NSInteger)self.reminders.count, 6);
	for (NSInteger i = 0; i < shown; i++)
		[sheet addButtonWithTitle:[self titleForReminder:self.reminders[i]]];

	[sheet addButtonWithTitle:@"Cancel"];
	sheet.cancelButtonIndex = shown;
	sheet.tag = kSavedReminderSheetTag;
	[sheet showInView:self.navigationController.view];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[TGClient shared] setSavedMessagesTopicsChangedHandler:nil];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setSavedMessagesTopicsChangedHandler:^{
		[weakSelf applyCachedTopics];
	}];

	if (self.loadedOnce)
		[self applyCachedTopics];

	[self reloadReminders];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[[TGClient shared] setSavedMessagesTopicsChangedHandler:nil];
	[TGPopupMenu dismiss];
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];

	UINavigationController *nav = self.navigationController;
	if (nav && [nav.viewControllers containsObject:self])
		return;

	[self.avatars removeAllObjects];
	[self.avatarsRequested removeAllObjects];
	[[TGClient shared] resetSavedMessagesTopicsCache];
}

- (void)themeChanged {
	TGTheme *theme = [TGTheme shared];
	[theme styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	self.tableView.backgroundView.backgroundColor = [theme listBackgroundColour];
	[self updateReminderBanner];

	BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
	self.tableView.separatorStyle = plainPlate
			? UITableViewCellSeparatorStyleNone
			: UITableViewCellSeparatorStyleSingleLine;

	for (UIView *view in self.emptyContainer.subviews){
		if ([view isKindOfClass:UILabel.class])
			[(UILabel *)view setTextColor:[theme secondaryTextColour]];
	}
	[self.tableView reloadData];
}

#pragma mark - the empty state

- (void)buildEmptyContainerInside:(UIView *)background {
	TGTheme *theme = [TGTheme shared];

	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 250, 0)];
	container.backgroundColor = [UIColor clearColor];
	container.hidden = YES;

	UIImageView *iconView = [[UIImageView alloc]
			initWithImage:[TGIcons savedMessagesAvatarOfSide:66]];
	iconView.frame = CGRectMake(floorf((250 - 66) / 2.0f), 0, 66, 66);
	[container addSubview:iconView];

	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.backgroundColor = [UIColor clearColor];
	titleLabel.textColor = [theme secondaryTextColour];
	titleLabel.font = [UIFont boldSystemFontOfSize:15];
	titleLabel.text = @"No Saved Messages";
	[titleLabel sizeToFit];
	titleLabel.frame = CGRectMake(floorf((250 - titleLabel.frame.size.width) / 2.0f),
			CGRectGetMaxY(iconView.frame) + 21,
			titleLabel.frame.size.width, titleLabel.frame.size.height);
	[container addSubview:titleLabel];

	UILabel *textLabel = [[UILabel alloc] init];
	textLabel.textAlignment = NSTextAlignmentCenter;
	textLabel.lineBreakMode = NSLineBreakByWordWrapping;
	textLabel.numberOfLines = 0;
	textLabel.backgroundColor = [UIColor clearColor];
	textLabel.textColor = [theme secondaryTextColour];
	textLabel.font = [UIFont systemFontOfSize:14];
	textLabel.text = @"Forward messages here to keep them. They are grouped by who sent them.";
	CGSize textSize = [textLabel sizeThatFits:CGSizeMake(232, 1000)];
	textLabel.frame = CGRectMake(floorf((250 - textSize.width) / 2.0f),
			CGRectGetMaxY(titleLabel.frame) + 8, textSize.width, textSize.height);
	[container addSubview:textLabel];

	CGFloat height = CGRectGetMaxY(textLabel.frame);
	container.frame = CGRectMake(floorf((background.bounds.size.width - 250) / 2.0f),
			floorf((background.bounds.size.height - height) / 2.0f), 250, height);
	container.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin
			| UIViewAutoresizingFlexibleTopMargin
			| UIViewAutoresizingFlexibleBottomMargin;

	self.emptyContainer = container;
	[background addSubview:container];
}

- (void)updateEmptyContainer {
	BOOL empty = (self.topics.count == 0) && self.loadedOnce;
	self.emptyContainer.hidden = !empty;
}

#pragma mark - loading

- (void)reloadTopics {
	if (self.loading)
		return;
	self.loading = YES;

	if (!self.loadedOnce)
		[self.spinner startAnimating];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] loadSavedMessagesTopicsWithLimit:kSavedTopicPage
											 completion:^(NSArray *topics){
		TGSavedMessagesViewController *me = weakSelf;
		if (!me)
			return;
		me.loading = NO;
		me.loadedOnce = YES;
		[me.spinner stopAnimating];
		[me applyTopics:topics];
	}];
}

- (void)applyCachedTopics {
	[self applyTopics:[[TGClient shared] cachedSavedMessagesTopics]];
}

- (void)applyTopics:(NSArray *)topics {
	if (self.reordering)
		return;

	NSMutableArray *clean = [NSMutableArray array];
	if ([topics isKindOfClass:NSArray.class]){
		for (id topic in topics){
			if ([topic isKindOfClass:NSDictionary.class])
				[clean addObject:topic];
		}
	}

	NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:clean.count];
	for (NSDictionary *topic in clean){
		if ([topic[@"isPinned"] boolValue])
			[ordered addObject:topic];
	}
	for (NSDictionary *topic in clean){
		if (![topic[@"isPinned"] boolValue])
			[ordered addObject:topic];
	}

	self.topics = ordered;
	[self fetchMissingAvatars];
	[self.tableView reloadData];
	[self updateEmptyContainer];
}

- (void)fetchMissingAvatars {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *topic in self.topics){
		if (![TGSavedTopicKind(topic) isEqualToString:@"fromChat"])
			continue;
		int64_t chatId = [topic[@"chatId"] longLongValue];
		if (!chatId)
			continue;
		NSNumber *fileId = [[TGClient shared] photoFileIdForChat:chatId];
		if (!fileId || self.avatars[fileId] || [self.avatarsRequested containsObject:fileId])
			continue;
		[self.avatarsRequested addObject:fileId];

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			TGSavedMessagesViewController *me = weakSelf;
			if (!me || !path)
				return;
			UIImage *image = [UIImage imageWithContentsOfFile:path];
			if (!image)
				return;
			me.avatars[fileId] = image;
			[me.tableView reloadData];
		}];
	}
}

- (UIImage *)avatarForTopic:(NSDictionary *)topic {
	NSString *kind = TGSavedTopicKind(topic);
	if ([kind isEqualToString:@"myNotes"])
		return [TGIcons savedMessagesAvatarOfSide:kSavedAvatar];

	int64_t chatId = [topic[@"chatId"] longLongValue];
	if ([kind isEqualToString:@"fromChat"] && chatId){
		NSNumber *fileId = [[TGClient shared] photoFileIdForChat:chatId];
		UIImage *photo = fileId ? self.avatars[fileId] : nil;
		if (photo)
			return photo;
	}

	NSString *title = TGSavedTopicTitle(topic);
	NSString *initials = [kind isEqualToString:@"authorHidden"]
			? @"?"
			: (title.length ? [title substringToIndex:1].uppercaseString : @"?");
	return [TGIcons avatarWithInitials:initials size:kSavedAvatar colourId:chatId];
}

#pragma mark - the plain chat

- (void)showListButtons {
	UIButton *chat = [TGIcons headerButtonWithTitle:@"Chat" bold:NO
											 target:self action:@selector(openPlainChat)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:chat];
}

- (void)openPlainChat {
	int64_t chatId = [[TGClient shared] savedMessagesChatId];
	if (!chatId)
		return;

	[TGSavedMessagesViewController setShowsTopics:NO];

	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = chatId;
	vc.chatTitle = @"Saved Messages";
	[self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.topics.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGSavedTopicCell";
	TGSavedTopicCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGSavedTopicCell alloc] initWithStyle:UITableViewCellStyleDefault
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
	cell.titleLabel.text = @"";
	cell.avatar.image = nil;
	cell.pinIcon.hidden = YES;

	if (indexPath.row >= (NSInteger)self.topics.count)
		return cell;

	NSDictionary *topic = self.topics[indexPath.row];
	cell.titleLabel.text = TGSavedTopicTitle(topic);

	NSString *draft = topic[@"draft"];
	NSString *text = topic[@"text"];
	if ([draft isKindOfClass:NSString.class] && draft.length){
		cell.previewLabel.text = [NSString stringWithFormat:@"Draft: %@", draft];
	} else if ([text isKindOfClass:NSString.class] && text.length){
		cell.previewLabel.text = [topic[@"outgoing"] boolValue]
				? [NSString stringWithFormat:@"You: %@", text]
				: text;
	}

	cell.dateLabel.text = TGSavedDate([topic[@"date"] doubleValue]);
	cell.pinIcon.hidden = ![topic[@"isPinned"] boolValue];
	if (!cell.pinIcon.hidden)
		cell.pinIcon.image = [TGIcons menuGlyphNamed:@"pin"];
	cell.avatar.image = [self avatarForTopic:topic];

	[cell setNeedsLayout];
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.reordering || self.loading)
		return;
	if (indexPath.row < (NSInteger)self.topics.count - 1)
		return;
	if ((NSInteger)self.topics.count >= [[TGClient shared] savedMessagesTopicCount])
		return;
	[self reloadTopics];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (self.reordering || indexPath.row >= (NSInteger)self.topics.count)
		return;

	NSDictionary *topic = self.topics[indexPath.row];
	int64_t topicId = [topic[@"id"] longLongValue];
	if (!topicId)
		return;

	TGSavedTopicController *vc = [[TGSavedTopicController alloc] initWithStyle:UITableViewStylePlain];
	vc.topicId = topicId;
	vc.topicTitle = TGSavedTopicTitle(topic);
	[self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - topic actions

- (void)showError:(NSString *)message {
	[[[UIAlertView alloc] initWithTitle:nil message:message delegate:nil
					  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (NSInteger)pinnedCount {
	NSInteger count = 0;
	for (NSDictionary *topic in self.topics){
		if ([topic[@"isPinned"] boolValue])
			count++;
		else
			break;
	}
	return count;
}

- (void)topicHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan || self.reordering)
		return;

	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:
			[hold locationInView:self.tableView]];
	if (!path || path.row >= (NSInteger)self.topics.count)
		return;

	NSDictionary *topic = self.topics[path.row];
	self.actionTopic = topic;

	BOOL pinned = [topic[@"isPinned"] boolValue];

	NSMutableArray *items = [NSMutableArray array];
	NSMutableArray *keys = [NSMutableArray array];

	[items addObject:@{@"title" : (pinned ? @"Unpin" : @"Pin"),
					   @"icon"  : (pinned ? @"unpin" : @"pin")}];
	[keys addObject:@"pin"];

	if (pinned && [self pinnedCount] > 1){
		[items addObject:@{@"title" : @"Reorder Pins", @"icon" : @"pin"}];
		[keys addObject:@"reorder"];
	}

	[items addObject:@{@"title" : @"Clear by Date", @"icon" : @"delete"}];
	[keys addObject:@"range"];

	[items addObject:@{@"title"       : @"Delete",
					   @"icon"        : @"delete",
					   @"destructive" : @YES}];
	[keys addObject:@"delete"];

	CGRect rect = [self.tableView rectForRowAtIndexPath:path];
	CGPoint where = [self.tableView convertPoint:
			CGPointMake(120, CGRectGetMaxY(rect) - 10) toView:self.navigationController.view];
	self.menuPoint = where;

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		if (choice < 0 || choice >= (NSInteger)keys.count)
			return;
		[weakSelf runTopicAction:keys[choice]];
	}];
}

- (void)runTopicAction:(NSString *)key {
	NSDictionary *topic = self.actionTopic;
	if (!topic)
		return;

	int64_t topicId = [topic[@"id"] longLongValue];
	__weak typeof(self) weakSelf = self;

	if ([key isEqualToString:@"pin"]){
		BOOL pin = ![topic[@"isPinned"] boolValue];
		self.actionTopic = nil;
		[[TGClient shared] setSavedMessagesTopic:topicId pinned:pin completion:^(BOOL ok){
			if (!ok)
				[weakSelf showError:pin ? @"Could not pin the topic."
										: @"Could not unpin the topic."];
			[weakSelf applyCachedTopics];
		}];
		return;
	}

	if ([key isEqualToString:@"reorder"]){
		self.actionTopic = nil;
		[self beginReordering];
		return;
	}

	if ([key isEqualToString:@"range"]){
		self.actionTopic = nil;
		self.rangeTopicId = topicId;
		self.rangeTopicTitle = TGSavedTopicTitle(topic);
		[self showRangeSheet];
		return;
	}

	if ([key isEqualToString:@"delete"]){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Delete Topic"
														message:[NSString stringWithFormat:
																@"Delete every saved message from %@?",
																TGSavedTopicTitle(topic)]
													   delegate:self
											  cancelButtonTitle:@"Cancel"
											  otherButtonTitles:@"Delete", nil];
		alert.tag = kSavedDeleteAlertTag;
		[alert show];
	}
}

#pragma mark - clearing a date range

- (void)showRangeSheet {
	if (!self.rangeTopicId)
		return;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Clear Messages"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"Last 24 Hours"];
	[sheet addButtonWithTitle:@"Last 7 Days"];
	[sheet addButtonWithTitle:@"Last 30 Days"];
	[sheet addButtonWithTitle:@"Older Than 30 Days"];
	[sheet addButtonWithTitle:@"Cancel"];
	sheet.cancelButtonIndex = 4;
	sheet.tag = kSavedRangeSheetTag;
	[sheet showInView:self.navigationController.view];
}

- (void)confirmRangeAtIndex:(NSInteger)index {
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	NSTimeInterval day = 24 * 3600;
	NSString *what = nil;

	if (index == 0){
		self.rangeMinDate = (NSInteger)(now - day);
		self.rangeMaxDate = (NSInteger)now;
		what = @"from the last 24 hours";
	} else if (index == 1){
		self.rangeMinDate = (NSInteger)(now - 7 * day);
		self.rangeMaxDate = (NSInteger)now;
		what = @"from the last 7 days";
	} else if (index == 2){
		self.rangeMinDate = (NSInteger)(now - 30 * day);
		self.rangeMaxDate = (NSInteger)now;
		what = @"from the last 30 days";
	} else if (index == 3){
		self.rangeMinDate = 0;
		self.rangeMaxDate = (NSInteger)(now - 30 * day);
		what = @"older than 30 days";
	} else {
		return;
	}

	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Clear Messages"
													message:[NSString stringWithFormat:
															@"Delete the saved messages %@ in %@?",
															what,
															self.rangeTopicTitle.length
																	? self.rangeTopicTitle
																	: @"this topic"]
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Delete", nil];
	alert.tag = kSavedRangeAlertTag;
	[alert show];
}

- (void)clearConfirmedRange {
	int64_t topicId = self.rangeTopicId;
	self.rangeTopicId = 0;
	if (!topicId)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] deleteSavedMessagesTopic:topicId
								   messagesFrom:self.rangeMinDate
											 to:self.rangeMaxDate
									 completion:^(BOOL ok){
		if (!ok)
			[weakSelf showError:@"Could not clear those messages."];
		[weakSelf applyCachedTopics];
	}];
}

#pragma mark - sheets and alerts

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == kSavedRangeSheetTag){
		[self confirmRangeAtIndex:index];
		return;
	}

	if (sheet.tag == kSavedReminderSheetTag){
		if (index < 0 || index >= (NSInteger)self.reminders.count)
			return;
		self.pendingReminder = self.reminders[index];
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Reminder"
														message:@"Send this reminder now?"
													   delegate:self
											  cancelButtonTitle:@"Cancel"
											  otherButtonTitles:@"Send Now", nil];
		alert.tag = kSavedReminderAlertTag;
		[alert show];
	}
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (alertView.tag == kSavedRangeAlertTag){
		if (buttonIndex != alertView.cancelButtonIndex)
			[self clearConfirmedRange];
		else
			self.rangeTopicId = 0;
		return;
	}

	if (alertView.tag == kSavedReminderAlertTag){
		NSDictionary *reminder = self.pendingReminder;
		self.pendingReminder = nil;
		if (buttonIndex == alertView.cancelButtonIndex || !reminder)
			return;

		int64_t messageId = [reminder[@"id"] longLongValue];
		int64_t chatId = [[TGClient shared] savedMessagesChatId];
		if (!messageId || !chatId)
			return;

		__weak typeof(self) weakSelf = self;
		[[TGClient shared] sendScheduledMessageNow:messageId inChat:chatId
										completion:^(BOOL ok){
			if (!ok)
				[weakSelf showError:@"Could not send the reminder."];
			[weakSelf reloadReminders];
		}];
		return;
	}

	NSDictionary *topic = self.actionTopic;
	self.actionTopic = nil;

	if (alertView.tag != kSavedDeleteAlertTag || buttonIndex == alertView.cancelButtonIndex)
		return;

	int64_t topicId = [topic[@"id"] longLongValue];
	if (!topicId)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] deleteSavedMessagesTopic:topicId completion:^(BOOL ok){
		if (!ok)
			[weakSelf showError:@"Could not delete the topic."];
		[weakSelf applyCachedTopics];
	}];
}

#pragma mark - reordering pinned topics

- (void)beginReordering {
	if ([self pinnedCount] < 2)
		return;

	self.reordering = YES;
	self.orderDirty = NO;
	[self.tableView setEditing:YES animated:YES];

	UIButton *done = [TGIcons headerButtonWithTitle:@"Done" bold:YES
											 target:self action:@selector(finishReordering)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:done];
}

- (void)finishReordering {
	self.reordering = NO;
	[self.tableView setEditing:NO animated:YES];
	[self showListButtons];

	if (!self.orderDirty){
		[self applyCachedTopics];
		return;
	}
	self.orderDirty = NO;

	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *topic in self.topics){
		if (![topic[@"isPinned"] boolValue])
			break;
		int64_t topicId = [topic[@"id"] longLongValue];
		if (topicId)
			[ids addObject:@(topicId)];
	}
	if (ids.count < 2){
		[self applyCachedTopics];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPinnedSavedMessagesTopics:ids completion:^(BOOL ok){
		if (!ok)
			[weakSelf showError:@"Could not save the order of the pinned topics."];
		[weakSelf applyCachedTopics];
	}];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return self.reordering && indexPath.row < [self pinnedCount];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return self.reordering;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
		   editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView
		shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
	return NO;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from
	   toProposedIndexPath:(NSIndexPath *)proposed {
	NSInteger last = [self pinnedCount] - 1;
	if (last < 0)
		return from;
	if (proposed.row > last)
		return [NSIndexPath indexPathForRow:last inSection:0];
	return proposed;
}

- (void)tableView:(UITableView *)tableView
		moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
	NSInteger pinned = [self pinnedCount];
	if (from.row >= pinned || from.row >= (NSInteger)self.topics.count)
		return;

	NSMutableArray *ordered = [self.topics mutableCopy];
	NSDictionary *topic = ordered[from.row];
	[ordered removeObjectAtIndex:from.row];
	NSInteger target = MIN(MAX(to.row, 0), pinned - 1);
	[ordered insertObject:topic atIndex:target];
	self.topics = ordered;
	self.orderDirty = YES;
}

@end

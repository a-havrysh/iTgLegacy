#import "TGSavedMessagesTagsViewController.h"
#import "TGClient.h"
#import "TGClient+SavedMessages.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGDateUtils.h"
#import "TGActionSheet.h"
#import "TGAlertView.h"

#define TGTagsRGB(rgb) [UIColor colorWithRed:(((rgb) >> 16) & 0xff) / 255.0f \
									   green:(((rgb) >> 8) & 0xff) / 255.0f \
										blue:((rgb) & 0xff) / 255.0f alpha:1.0f]

static const CGFloat TGTagsRowHeight = 51.0f;
static const CGFloat TGTagsGlyphSide = 40.0f;
static const CGFloat TGTagsTextOrigin = 49.0f;
static const CGFloat TGTagsRightInset = 9.0f;
static const CGFloat TGTagsBadgeHeight = 21.0f;
static const NSInteger TGTagsPageSize = 50;
static const NSInteger TGTagsMaxTopics = 12;
static const NSInteger TGTagsMaxMessagesPerTag = 200;

static CGFloat TGTagsRetinaPixel(void) {
	return [UIScreen mainScreen].scale > 1.0f ? 0.5f : 0.0f;
}

static NSString *TGTagsCountString(NSInteger count) {
	if (count < 1000)
		return [NSString stringWithFormat:@"%d", (int)count];
	if (count < 1000000)
		return [NSString stringWithFormat:@"%dK", (int)(count / 1000)];
	return [NSString stringWithFormat:@"%dM", (int)(count / 1000000)];
}

static UIImage *TGTagsBadgeImage(void) {
	UIImage *image = [UIImage imageNamed:@"DialogListUnreadBadge.png"];
	if (!image)
		return nil;
	return [image stretchableImageWithLeftCapWidth:13 topCapHeight:10];
}

#pragma mark - the messages of one tag

@interface TGSavedMessagesTagFilterController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) NSArray *messages;
@property (nonatomic, copy) NSString *tagTitle;
@property (nonatomic, strong) UITableView *tableView;

- (instancetype)initWithMessages:(NSArray *)messages title:(NSString *)title;

@end

@implementation TGSavedMessagesTagFilterController

- (instancetype)initWithMessages:(NSArray *)messages title:(NSString *)title {
	self = [super initWithNibName:nil bundle:nil];
	if (self){
		_messages = messages ? messages : [NSArray array];
		_tagTitle = [title copy];
	}
	return self;
}

- (void)dealloc {
	_tableView.delegate = nil;
	_tableView.dataSource = nil;
}

- (void)loadView {
	[super loadView];

	self.view.backgroundColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] listBackgroundColour] : [UIColor whiteColor];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
												  style:UITableViewStylePlain];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleHeight;
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.tableView.rowHeight = TGTagsRowHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	[self.view addSubview:self.tableView];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.tagTitle.length ? self.tagTitle : @"Tag";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"tagMessage"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"tagMessage"];

	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;

	NSDictionary *message = nil;
	if (indexPath.row < (NSInteger)self.messages.count)
		message = self.messages[indexPath.row];

	NSString *text = message[@"text"];
	if (![text isKindOfClass:[NSString class]] || !text.length)
		text = @"Media";

	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.textLabel.numberOfLines = 1;
	cell.textLabel.text = text;

	int date = [message[@"date"] intValue];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = TGTagsRGB(0x888888);
	cell.detailTextLabel.text = date ? [TGDateUtils stringForMessageListDate:date] : @"";
	return cell;
}

@end

#pragma mark - the tag row

@interface TGSavedMessagesTagCell : UITableViewCell

@property (nonatomic, strong) UILabel *glyphLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *badgeView;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UIView *hairline;

@end

@implementation TGSavedMessagesTagCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self){
		self.selectionStyle = UITableViewCellSelectionStyleBlue;

		_glyphLabel = [[UILabel alloc] initWithFrame:
				CGRectMake(5, 5, TGTagsGlyphSide, TGTagsGlyphSide)];
		_glyphLabel.backgroundColor = [UIColor clearColor];
		_glyphLabel.font = [UIFont systemFontOfSize:28];
		_glyphLabel.textAlignment = NSTextAlignmentCenter;
		[self.contentView addSubview:_glyphLabel];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.backgroundColor = [UIColor clearColor];
		_titleLabel.font = [UIFont systemFontOfSize:19];
		[self.contentView addSubview:_titleLabel];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		_subtitleLabel.font = [UIFont systemFontOfSize:13 + TGTagsRetinaPixel()];
		_subtitleLabel.textColor = TGTagsRGB(0x888888);
		[self.contentView addSubview:_subtitleLabel];

		_badgeView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_badgeView.image = TGTagsBadgeImage();
		[self.contentView addSubview:_badgeView];

		_badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_badgeLabel.backgroundColor = [UIColor clearColor];
		_badgeLabel.font = [UIFont boldSystemFontOfSize:14];
		_badgeLabel.textColor = [UIColor whiteColor];
		_badgeLabel.textAlignment = NSTextAlignmentCenter;
		_badgeLabel.shadowColor = TGTagsRGB(0x8091a6);
		_badgeLabel.shadowOffset = CGSizeMake(0, -1);
		[self.contentView addSubview:_badgeLabel];

		_hairline = [[UIView alloc] initWithFrame:CGRectZero];
		_hairline.backgroundColor = [[TGTheme shared] separatorColour];
		[self.contentView addSubview:_hairline];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGRect bounds = self.contentView.bounds;
	CGFloat width = bounds.size.width;

	self.glyphLabel.frame = CGRectMake(5, 5, TGTagsGlyphSide, TGTagsGlyphSide);

	CGFloat badgeWidth = 0;
	if (self.badgeLabel.text.length){
		CGSize size = [self.badgeLabel.text sizeWithFont:self.badgeLabel.font];
		badgeWidth = floorf(size.width) + 10;
		if (badgeWidth < 27)
			badgeWidth = 27;
		CGFloat badgeY = floorf((bounds.size.height - TGTagsBadgeHeight) / 2);
		CGRect badgeFrame = CGRectMake(width - TGTagsRightInset - badgeWidth, badgeY,
				badgeWidth, TGTagsBadgeHeight);
		self.badgeView.frame = badgeFrame;
		self.badgeLabel.frame = CGRectMake(badgeFrame.origin.x,
				badgeY + 2 + TGTagsRetinaPixel(), badgeWidth, 17);
		self.badgeView.hidden = self.badgeView.image == nil;
		self.badgeLabel.hidden = NO;
		badgeWidth += TGTagsRightInset + 6;
	} else {
		self.badgeView.hidden = YES;
		self.badgeLabel.hidden = YES;
	}

	CGFloat textWidth = width - TGTagsTextOrigin - TGTagsRightInset - badgeWidth;
	if (textWidth < 40)
		textWidth = 40;

	if (self.subtitleLabel.text.length){
		self.titleLabel.frame = CGRectMake(TGTagsTextOrigin, 5, textWidth, 24);
		self.subtitleLabel.frame = CGRectMake(TGTagsTextOrigin + 1,
				28 + TGTagsRetinaPixel(), textWidth, 18);
	} else {
		self.titleLabel.frame = CGRectMake(TGTagsTextOrigin,
				floorf((bounds.size.height - 24) / 2), textWidth, 24);
		self.subtitleLabel.frame = CGRectZero;
	}

	CGFloat thickness = 1.0f / [UIScreen mainScreen].scale;
	self.hairline.frame = CGRectMake(TGTagsTextOrigin, bounds.size.height - thickness,
			width - TGTagsTextOrigin, thickness);
}

@end

#pragma mark - the screen

@interface TGSavedMessagesTagsViewController ()

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIView *messageView;
@property (nonatomic, strong) UIImageView *messageIconView;
@property (nonatomic, strong) UILabel *messageTitleLabel;
@property (nonatomic, strong) UILabel *messageBodyLabel;

@property (nonatomic, strong) NSMutableArray *tags;
@property (nonatomic, strong) NSMutableDictionary *counts;
@property (nonatomic, strong) NSMutableDictionary *messagesByTag;
@property (nonatomic, strong) NSMutableDictionary *labels;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, copy) NSString *pendingRenameEmoji;

@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) NSInteger scannedMessages;

@end

@implementation TGSavedMessagesTagsViewController

- (instancetype)initWithTopicId:(int64_t)topicId {
	self = [super initWithNibName:nil bundle:nil];
	if (self){
		_topicId = topicId;
		[self commonSetup];
	}
	return self;
}

- (instancetype)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
	self = [super initWithNibName:nibName bundle:bundle];
	if (self)
		[self commonSetup];
	return self;
}

- (void)commonSetup {
	_tags = [NSMutableArray array];
	_counts = [NSMutableDictionary dictionary];
	_messagesByTag = [NSMutableDictionary dictionary];
	_labels = [NSMutableDictionary dictionary];
}

- (void)dealloc {
	_tableView.delegate = nil;
	_tableView.dataSource = nil;
	[[TGClient shared] setSavedMessagesTagsChangedHandler:nil];
}

#pragma mark - view

- (void)loadView {
	[super loadView];

	self.view.backgroundColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] listBackgroundColour] : [UIColor whiteColor];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
												  style:UITableViewStylePlain];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleHeight;
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.tableView.rowHeight = TGTagsRowHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	[self.view addSubview:self.tableView];

	self.messageView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 250, 60)];
	self.messageView.backgroundColor = [UIColor clearColor];
	self.messageView.hidden = YES;

	self.messageIconView = [[UIImageView alloc] initWithImage:
			[TGIcons savedMessagesAvatarOfSide:70]];
	[self.messageView addSubview:self.messageIconView];

	self.messageTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.messageTitleLabel.backgroundColor = [UIColor clearColor];
	self.messageTitleLabel.font = [UIFont boldSystemFontOfSize:15];
	self.messageTitleLabel.textColor = TGTagsRGB(0x8b97a5);
	self.messageTitleLabel.textAlignment = NSTextAlignmentCenter;
	[self.messageView addSubview:self.messageTitleLabel];

	self.messageBodyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.messageBodyLabel.backgroundColor = [UIColor clearColor];
	self.messageBodyLabel.font = [UIFont systemFontOfSize:14];
	self.messageBodyLabel.textColor = TGTagsRGB(0x8b97a5);
	self.messageBodyLabel.textAlignment = NSTextAlignmentCenter;
	self.messageBodyLabel.numberOfLines = 0;
	self.messageBodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
	[self.messageView addSubview:self.messageBodyLabel];

	[self.view insertSubview:self.messageView belowSubview:self.tableView];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
			UIActivityIndicatorViewStyleGray];
	self.spinner.hidesWhenStopped = YES;
	[self.view addSubview:self.spinner];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = self.topicTitle.length ? self.topicTitle : @"Tags";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	UIButton *reloadButton = [TGIcons headerButtonWithTitle:@"Reload" bold:NO
													 target:self action:@selector(reloadPressed)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:reloadButton];

	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setSavedMessagesTagsChangedHandler:^(int64_t changedTopicId){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (changedTopicId != 0 && strongSelf.topicId != 0
				&& changedTopicId != strongSelf.topicId)
			return;
		[strongSelf reload];
	}];

	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.currentActionSheet){
		[self.currentActionSheet dismissWithClickedButtonIndex:
				self.currentActionSheet.cancelButtonIndex animated:NO];
		self.currentActionSheet = nil;
	}
}

- (void)viewDidLayoutSubviews {
	if ([[UIViewController class] instancesRespondToSelector:@selector(viewDidLayoutSubviews)])
		[super viewDidLayoutSubviews];
	[self layoutOverlays];
}

- (void)viewWillLayoutSubviews {
	if ([[UIViewController class] instancesRespondToSelector:@selector(viewWillLayoutSubviews)])
		[super viewWillLayoutSubviews];
	[self layoutOverlays];
}

- (void)layoutOverlays {
	CGRect bounds = self.view.bounds;
	self.spinner.center = CGPointMake(floorf(bounds.size.width / 2),
			floorf(bounds.size.height / 2));

	if (self.messageView.hidden)
		return;

	CGFloat width = 250;
	CGFloat iconBottom = 0;
	if (self.messageIconView.image){
		CGSize iconSize = self.messageIconView.image.size;
		self.messageIconView.frame = CGRectMake(floorf((width - iconSize.width) / 2), 0,
				iconSize.width, iconSize.height);
		iconBottom = CGRectGetMaxY(self.messageIconView.frame) + 21;
	}

	[self.messageTitleLabel sizeToFit];
	CGRect titleFrame = self.messageTitleLabel.frame;
	titleFrame.origin = CGPointMake(floorf((width - titleFrame.size.width) / 2), iconBottom);
	self.messageTitleLabel.frame = titleFrame;

	CGSize bodySize = [self.messageBodyLabel.text.length ? self.messageBodyLabel.text : @" "
			sizeWithFont:self.messageBodyLabel.font
	   constrainedToSize:CGSizeMake(232, 1000)
		   lineBreakMode:NSLineBreakByWordWrapping];
	self.messageBodyLabel.frame = CGRectMake(9, CGRectGetMaxY(titleFrame) + 8, 232,
			floorf(bodySize.height));

	CGFloat height = CGRectGetMaxY(self.messageBodyLabel.frame);
	self.messageView.frame = CGRectMake(floorf((bounds.size.width - width) / 2),
			floorf((bounds.size.height - height) / 2), width, height);
}

#pragma mark - loading

- (void)reloadPressed {
	[self reload];
}

- (void)reload {
	if (self.loading)
		return;

	self.loaded = NO;
	self.failed = NO;
	self.scannedMessages = 0;
	[self.tags removeAllObjects];
	[self.counts removeAllObjects];
	[self.messagesByTag removeAllObjects];
	[self.tableView reloadData];
	[self showLoading];

	self.loading = YES;
	if (self.topicId != 0){
		[self scanTopics:[NSArray arrayWithObject:@(self.topicId)] atIndex:0];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] loadSavedMessagesTopicsWithLimit:100 completion:^(NSArray *topics){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *topic in topics){
			if (![topic isKindOfClass:[NSDictionary class]])
				continue;
			NSNumber *identifier = topic[@"id"];
			if (![identifier isKindOfClass:[NSNumber class]])
				continue;
			[ids addObject:identifier];
			if ((NSInteger)ids.count >= TGTagsMaxTopics)
				break;
		}
		if (!ids.count){
			strongSelf.loading = NO;
			strongSelf.loaded = YES;
			strongSelf.failed = NO;
			[strongSelf finishScan];
			return;
		}
		[strongSelf scanTopics:ids atIndex:0];
	}];
}

- (void)scanTopics:(NSArray *)topicIds atIndex:(NSInteger)index {
	if (index >= (NSInteger)topicIds.count){
		self.loading = NO;
		self.loaded = YES;
		self.failed = self.scannedMessages == 0 && self.tags.count == 0;
		[self finishScan];
		return;
	}

	int64_t topicId = [topicIds[index] longLongValue];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] savedMessagesTopicHistory:topicId
									 fromMessage:0
										   limit:TGTagsPageSize
									  completion:^(NSArray *messages){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf absorbMessages:messages];
		[strongSelf scanTopics:topicIds atIndex:index + 1];
	}];
}

- (void)absorbMessages:(NSArray *)messages {
	if (![messages isKindOfClass:[NSArray class]])
		return;

	for (NSDictionary *message in messages){
		if (![message isKindOfClass:[NSDictionary class]])
			continue;
		self.scannedMessages += 1;

		NSArray *tags = message[@"tags"];
		if (![tags isKindOfClass:[NSArray class]])
			continue;

		for (NSString *emoji in tags){
			if (![emoji isKindOfClass:[NSString class]] || !emoji.length)
				continue;

			NSNumber *count = self.counts[emoji];
			self.counts[emoji] = @([count integerValue] + 1);
			if (!count)
				[self.tags addObject:emoji];

			NSMutableArray *bucket = self.messagesByTag[emoji];
			if (!bucket){
				bucket = [NSMutableArray array];
				self.messagesByTag[emoji] = bucket;
			}
			if ((NSInteger)bucket.count < TGTagsMaxMessagesPerTag)
				[bucket addObject:message];
		}
	}
}

- (void)finishScan {
	NSMutableDictionary *counts = self.counts;
	[self.tags sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b){
		NSInteger countA = [counts[a] integerValue];
		NSInteger countB = [counts[b] integerValue];
		if (countA == countB)
			return [a compare:b];
		return countA > countB ? NSOrderedAscending : NSOrderedDescending;
	}];
	[self.tableView reloadData];
	[self updateStates];
}

- (void)showLoading {
	self.messageView.hidden = YES;
	self.tableView.hidden = YES;
	[self.spinner startAnimating];
	[self layoutOverlays];
}

- (void)updateStates {
	[self.spinner stopAnimating];

	if (self.tags.count){
		self.messageView.hidden = YES;
		self.tableView.hidden = NO;
		return;
	}

	self.tableView.hidden = YES;
	self.messageView.hidden = NO;
	if (self.failed){
		self.messageTitleLabel.text = @"Cannot load";
		self.messageBodyLabel.text = @"The tags of Saved Messages could not be loaded. "
				@"Check the connection and tap Reload.";
	} else {
		self.messageTitleLabel.text = @"No tags";
		self.messageBodyLabel.text = @"Tag a saved message with a reaction and the tag "
				@"shows up here, with the number of messages that carry it.";
	}
	[self layoutOverlays];
}

#pragma mark - model helpers

- (NSString *)emojiAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.tags.count)
		return nil;
	return self.tags[index];
}

- (NSString *)titleForEmoji:(NSString *)emoji {
	NSString *label = self.labels[emoji];
	if ([label isKindOfClass:[NSString class]] && label.length)
		return label;
	return emoji;
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.tags.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	TGSavedMessagesTagCell *cell = [tableView dequeueReusableCellWithIdentifier:@"tag"];
	if (!cell)
		cell = [[TGSavedMessagesTagCell alloc] initWithStyle:UITableViewCellStyleDefault
											 reuseIdentifier:@"tag"];

	[[TGTheme shared] styleCell:cell];

	NSString *emoji = [self emojiAtIndex:indexPath.row];
	NSInteger count = [self.counts[emoji] integerValue];

	cell.glyphLabel.text = emoji ? emoji : @"";
	cell.titleLabel.text = [self titleForEmoji:emoji];
	cell.titleLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.subtitleLabel.text = count == 1 ? @"1 message"
			: [NSString stringWithFormat:@"%d messages", (int)count];
	cell.badgeLabel.text = TGTagsCountString(count);
	[cell setNeedsLayout];
	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return TGTagsRowHeight;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSString *emoji = [self emojiAtIndex:indexPath.row];
	if (!emoji)
		return;

	NSArray *actions = [NSArray arrayWithObjects:
			[[TGActionSheetAction alloc] initWithTitle:@"Show Messages" action:@"show"],
			[[TGActionSheetAction alloc] initWithTitle:@"Rename Tag" action:@"rename"],
			[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
												  type:TGActionSheetActionTypeCancel],
			nil];

	__weak typeof(self) weakSelf = self;
	NSString *chosen = emoji;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:nil
														  actions:actions
													  actionBlock:^(id target, NSString *action){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.currentActionSheet = nil;
		if ([action isEqualToString:@"show"])
			[strongSelf showMessagesForEmoji:chosen];
		else if ([action isEqualToString:@"rename"])
			[strongSelf askRenameForEmoji:chosen];
	} target:self];

	UIView *host = self.navigationController.view ? self.navigationController.view : self.view;
	[self.currentActionSheet showInView:host];
}

#pragma mark - actions

- (void)showMessagesForEmoji:(NSString *)emoji {
	NSArray *messages = self.messagesByTag[emoji];
	NSString *title = [self titleForEmoji:emoji];
	TGSavedMessagesTagFilterController *controller =
			[[TGSavedMessagesTagFilterController alloc] initWithMessages:messages title:title];
	[self.navigationController pushViewController:controller animated:YES];
}

- (void)askRenameForEmoji:(NSString *)emoji {
	self.pendingRenameEmoji = emoji;

	UIAlertView *alert = [[TGAlertView alloc] initWithTitle:nil
												   message:@"Name for this tag"
												  delegate:self
										 cancelButtonTitle:@"Cancel"
										 otherButtonTitles:@"Done", nil];
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)]){
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
		UITextField *field = [alert textFieldAtIndex:0];
		field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
		NSString *label = self.labels[emoji];
		if ([label isKindOfClass:[NSString class]])
			field.text = label;
	}
	[alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex){
		self.pendingRenameEmoji = nil;
		return;
	}

	NSString *emoji = self.pendingRenameEmoji;
	self.pendingRenameEmoji = nil;
	if (!emoji.length)
		return;

	NSString *label = @"";
	if ([alertView respondsToSelector:@selector(textFieldAtIndex:)]){
		UITextField *field = [alertView textFieldAtIndex:0];
		if (field.text)
			label = [field.text stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}

	__weak typeof(self) weakSelf = self;
	NSString *chosen = emoji;
	NSString *newLabel = label;
	[[TGClient shared] setSavedMessagesTagLabel:newLabel forEmoji:chosen completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (!ok){
			[[[TGAlertView alloc] initWithTitle:nil
										message:@"The tag could not be renamed."
							  cancelButtonTitle:@"OK"
								  okButtonTitle:nil
								completionBlock:nil] show];
			return;
		}
		if (newLabel.length)
			strongSelf.labels[chosen] = newLabel;
		else
			[strongSelf.labels removeObjectForKey:chosen];
		[strongSelf.tableView reloadData];
	}];
}

@end

// vim:ft=objc

#import "TGChatEventsViewController.h"
#import "TGClient.h"
#import "TGClient+ChatManagement.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGDateUtils.h"

#define TGEventsRGB(rgb) [UIColor colorWithRed:(((rgb) >> 16) & 0xff) / 255.0f \
									 green:(((rgb) >> 8) & 0xff) / 255.0f \
									  blue:((rgb) & 0xff) / 255.0f alpha:1.0f]

static const CGFloat TGEventsAvatarSide = 40.0f;
static const CGFloat TGEventsTextOrigin = 49.0f;
static const CGFloat TGEventsRightInset = 10.0f;
static const CGFloat TGEventsMinRowHeight = 51.0f;
static const CGFloat TGEventsHeaderHeight = 26.0f;
static const NSInteger TGEventsPageSize = 50;

static CGFloat TGEventsRetinaPixel(void) {
	return [UIScreen mainScreen].scale > 1.0f ? 0.5f : 0.0f;
}

static NSArray *TGEventsAllFilters(void) {
	return [NSArray arrayWithObjects:
			@"messageEdits", @"messageDeletions", @"messagePins",
			@"memberJoins", @"memberLeaves", @"memberInvites",
			@"memberPromotions", @"memberRestrictions",
			@"infoChanges", @"settingChanges", @"inviteLinkChanges",
			@"videoChatChanges", @"forumChanges", nil];
}

static NSString *TGEventsFilterTitle(NSString *filter) {
	if ([filter isEqualToString:@"messageEdits"]) return @"Edited Messages";
	if ([filter isEqualToString:@"messageDeletions"]) return @"Deleted Messages";
	if ([filter isEqualToString:@"messagePins"]) return @"Pinned Messages";
	if ([filter isEqualToString:@"memberJoins"]) return @"New Members";
	if ([filter isEqualToString:@"memberLeaves"]) return @"Members Left";
	if ([filter isEqualToString:@"memberInvites"]) return @"Invited Members";
	if ([filter isEqualToString:@"memberPromotions"]) return @"Admin Rights";
	if ([filter isEqualToString:@"memberRestrictions"]) return @"Restrictions";
	if ([filter isEqualToString:@"infoChanges"]) return @"Group Info";
	if ([filter isEqualToString:@"settingChanges"]) return @"Settings";
	if ([filter isEqualToString:@"inviteLinkChanges"]) return @"Invite Links";
	if ([filter isEqualToString:@"videoChatChanges"]) return @"Video Chats";
	if ([filter isEqualToString:@"forumChanges"]) return @"Topics";
	return filter;
}

static NSString *TGEventsInitials(NSString *name) {
	if (![name isKindOfClass:[NSString class]] || !name.length)
		return @"?";
	NSMutableString *initials = [NSMutableString string];
	NSArray *words = [name componentsSeparatedByString:@" "];
	for (NSString *word in words){
		if (!word.length)
			continue;
		[initials appendString:[[word substringToIndex:1] uppercaseString]];
		if (initials.length >= 2)
			break;
	}
	return initials.length ? initials : @"?";
}

#pragma mark - the filter form

@interface TGChatEventsFilterController : UITableViewController

@property (nonatomic, strong) NSMutableArray *selection;
@property (nonatomic, copy) void (^completion)(NSArray *filters);

- (instancetype)initWithFilters:(NSArray *)filters;

@end

@implementation TGChatEventsFilterController

- (instancetype)initWithFilters:(NSArray *)filters {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		_selection = filters.count ? [NSMutableArray arrayWithArray:filters]
								   : [NSMutableArray arrayWithArray:TGEventsAllFilters()];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Filter";
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.tableView.rowHeight = 44;

	UIButton *cancel = [TGIcons headerButtonWithTitle:@"Cancel" bold:NO
											   target:self action:@selector(cancelPressed)];
	UIButton *done = [TGIcons headerButtonWithTitle:@"Done" bold:YES
											target:self action:@selector(donePressed)];
	self.navigationItem.leftBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:cancel];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:done];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)cancelPressed {
	[self dismissModalViewControllerAnimated:YES];
}

- (void)donePressed {
	NSArray *result = nil;
	if (self.selection.count && self.selection.count < TGEventsAllFilters().count)
		result = [NSArray arrayWithArray:self.selection];
	if (self.completion)
		self.completion(result);
	[self dismissModalViewControllerAnimated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 1 : (NSInteger)TGEventsAllFilters().count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section != 1)
		return nil;
	return @"Only the selected kinds of action are listed.";
}

- (UIImage *)checkImage {
	return [UIImage imageNamed:@"ListCheck.png"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"filter"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"filter"];

	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.font = [UIFont systemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] primaryTextColour] : TGEventsRGB(0x516691);

	BOOL selected;
	if (indexPath.section == 0){
		cell.textLabel.text = @"All Actions";
		selected = self.selection.count == TGEventsAllFilters().count;
	} else {
		NSString *filter = TGEventsAllFilters()[indexPath.row];
		cell.textLabel.text = TGEventsFilterTitle(filter);
		selected = [self.selection containsObject:filter];
	}

	UIImage *check = [self checkImage];
	if (selected && check){
		UIImageView *view = [[UIImageView alloc] initWithImage:check];
		cell.accessoryView = view;
	} else if (selected){
		UILabel *mark = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 14, 20)];
		mark.backgroundColor = [UIColor clearColor];
		mark.font = [UIFont boldSystemFontOfSize:16];
		mark.textColor = TGEventsRGB(0x0779d0);
		mark.text = @"✓";
		cell.accessoryView = mark;
	} else {
		cell.accessoryView = nil;
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 0){
		if (self.selection.count == TGEventsAllFilters().count)
			[self.selection removeAllObjects];
		else
			[self.selection setArray:TGEventsAllFilters()];
		[tableView reloadData];
		return;
	}

	NSString *filter = TGEventsAllFilters()[indexPath.row];
	if ([self.selection containsObject:filter])
		[self.selection removeObject:filter];
	else
		[self.selection addObject:filter];
	[tableView reloadData];
}

@end

#pragma mark - the row

@interface TGChatEventCell : UITableViewCell

@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIView *hairline;

+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width;

@end

@implementation TGChatEventCell

+ (UIFont *)bodyFont {
	return [UIFont systemFontOfSize:14];
}

+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width {
	CGFloat textWidth = width - TGEventsTextOrigin - TGEventsRightInset;
	if (textWidth < 40)
		textWidth = 40;
	CGSize size = [(text.length ? text : @" ") sizeWithFont:[self bodyFont]
										  constrainedToSize:CGSizeMake(textWidth, 1000)
											  lineBreakMode:NSLineBreakByWordWrapping];
	CGFloat height = 28 + size.height + 8;
	return height < TGEventsMinRowHeight ? TGEventsMinRowHeight : floorf(height);
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self){
		self.selectionStyle = UITableViewCellSelectionStyleNone;

		_avatarView = [[UIImageView alloc] initWithFrame:
				CGRectMake(5, 5, TGEventsAvatarSide, TGEventsAvatarSide)];
		[self.contentView addSubview:_avatarView];

		_nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_nameLabel.backgroundColor = [UIColor clearColor];
		_nameLabel.font = [UIFont boldSystemFontOfSize:16];
		[self.contentView addSubview:_nameLabel];

		_dateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_dateLabel.backgroundColor = [UIColor clearColor];
		_dateLabel.font = [UIFont systemFontOfSize:13];
		_dateLabel.textAlignment = NSTextAlignmentRight;
		[self.contentView addSubview:_dateLabel];

		_bodyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_bodyLabel.backgroundColor = [UIColor clearColor];
		_bodyLabel.font = [TGChatEventCell bodyFont];
		_bodyLabel.numberOfLines = 0;
		_bodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
		[self.contentView addSubview:_bodyLabel];

		_hairline = [[UIView alloc] initWithFrame:CGRectZero];
		[self.contentView addSubview:_hairline];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGRect bounds = self.contentView.bounds;
	CGFloat width = bounds.size.width;

	self.avatarView.frame = CGRectMake(5, 5, TGEventsAvatarSide, TGEventsAvatarSide);

	CGSize dateSize = [self.dateLabel.text.length ? self.dateLabel.text : @" "
			sizeWithFont:self.dateLabel.font];
	CGFloat dateWidth = floorf(dateSize.width) + 2;
	self.dateLabel.frame = CGRectMake(width - dateWidth - 9, 7 + TGEventsRetinaPixel(),
			dateWidth, 15);

	CGFloat nameWidth = width - TGEventsTextOrigin - dateWidth - 9 - 6;
	if (nameWidth < 20)
		nameWidth = 20;
	self.nameLabel.frame = CGRectMake(TGEventsTextOrigin, 5, nameWidth, 20);

	CGFloat textWidth = width - TGEventsTextOrigin - TGEventsRightInset;
	if (textWidth < 40)
		textWidth = 40;
	CGSize bodySize = [self.bodyLabel.text.length ? self.bodyLabel.text : @" "
			sizeWithFont:self.bodyLabel.font
	   constrainedToSize:CGSizeMake(textWidth, 1000)
		   lineBreakMode:NSLineBreakByWordWrapping];
	self.bodyLabel.frame = CGRectMake(TGEventsTextOrigin, 26 + TGEventsRetinaPixel(),
			textWidth, floorf(bodySize.height));

	CGFloat thickness = 1.0f / [UIScreen mainScreen].scale;
	self.hairline.frame = CGRectMake(TGEventsTextOrigin, bounds.size.height - thickness,
			width - TGEventsTextOrigin, thickness);
}

@end

#pragma mark - the screen

@interface TGChatEventsViewController ()

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIView *messageView;
@property (nonatomic, strong) UILabel *messageTitleLabel;
@property (nonatomic, strong) UILabel *messageBodyLabel;
@property (nonatomic, strong) NSMutableArray *events;
@property (nonatomic, strong) NSMutableArray *sections;
@property (nonatomic, strong) NSArray *filters;
@property (nonatomic, assign) long long oldestEventId;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) BOOL exhausted;

@end

@implementation TGChatEventsViewController

- (instancetype)initWithChatId:(int64_t)chatId {
	self = [super initWithNibName:nil bundle:nil];
	if (self){
		_chatId = chatId;
		_events = [NSMutableArray array];
		_sections = [NSMutableArray array];
	}
	return self;
}

- (instancetype)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
	self = [super initWithNibName:nibName bundle:bundle];
	if (self){
		_events = [NSMutableArray array];
		_sections = [NSMutableArray array];
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
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	[self.view addSubview:self.tableView];

	self.messageView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 250, 60)];
	self.messageView.backgroundColor = [UIColor clearColor];
	self.messageView.hidden = YES;

	self.messageTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.messageTitleLabel.backgroundColor = [UIColor clearColor];
	self.messageTitleLabel.font = [UIFont boldSystemFontOfSize:15];
	self.messageTitleLabel.textColor = TGEventsRGB(0x8b97a5);
	self.messageTitleLabel.textAlignment = NSTextAlignmentCenter;
	[self.messageView addSubview:self.messageTitleLabel];

	self.messageBodyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.messageBodyLabel.backgroundColor = [UIColor clearColor];
	self.messageBodyLabel.font = [UIFont systemFontOfSize:14];
	self.messageBodyLabel.textColor = TGEventsRGB(0x8b97a5);
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

	self.title = @"Recent Actions";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	UIButton *filterButton = [TGIcons headerButtonWithTitle:@"Filter" bold:NO
													 target:self action:@selector(filterPressed)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:filterButton];

	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
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
	[self.messageTitleLabel sizeToFit];
	CGRect titleFrame = self.messageTitleLabel.frame;
	titleFrame.origin = CGPointMake(floorf((width - titleFrame.size.width) / 2), 0);
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

- (void)reload {
	self.loaded = NO;
	self.failed = NO;
	self.exhausted = NO;
	self.oldestEventId = 0;
	[self.events removeAllObjects];
	[self rebuildSections];
	[self.tableView reloadData];
	[self showLoading];
	[self loadNextPage];
}

- (void)loadNextPage {
	if (self.loading || self.exhausted)
		return;
	if (self.chatId == 0){
		self.loaded = YES;
		self.failed = YES;
		[self updateStates];
		return;
	}

	self.loading = YES;
	long long from = self.oldestEventId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] eventLogForChat:self.chatId
								 query:nil
						   fromEventId:from
								 limit:TGEventsPageSize
							   filters:self.filters
							   userIds:nil
							completion:^(NSArray *events){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf handlePage:events fromEventId:from];
	}];
}

- (void)handlePage:(NSArray *)events fromEventId:(long long)from {
	self.loading = NO;
	self.loaded = YES;

	if (![events isKindOfClass:[NSArray class]]){
		self.failed = self.events.count == 0;
		self.exhausted = YES;
		[self updateStates];
		return;
	}

	self.failed = NO;
	if (events.count == 0){
		self.exhausted = YES;
	} else {
		for (NSDictionary *event in events){
			if (![event isKindOfClass:[NSDictionary class]])
				continue;
			[self.events addObject:event];
			long long eventId = [event[@"eventId"] longLongValue];
			if (eventId != 0)
				self.oldestEventId = eventId;
		}
		if ((NSInteger)events.count < TGEventsPageSize)
			self.exhausted = YES;
		if (self.oldestEventId == from)
			self.exhausted = YES;
	}

	[self rebuildSections];
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

	if (self.events.count){
		self.messageView.hidden = YES;
		self.tableView.hidden = NO;
		return;
	}

	self.tableView.hidden = YES;
	self.messageView.hidden = NO;
	if (self.failed){
		self.messageTitleLabel.text = @"Cannot load";
		self.messageBodyLabel.text = @"The recent actions of this chat could not be "
				@"loaded. Check the connection and open this screen again.";
	} else if (self.filters.count){
		self.messageTitleLabel.text = @"No actions";
		self.messageBodyLabel.text = @"No recent action matches the filter. "
				@"Admin actions are kept for 48 hours.";
	} else {
		self.messageTitleLabel.text = @"No actions yet";
		self.messageBodyLabel.text = @"Actions taken by the admins of this chat over "
				@"the last 48 hours are listed here.";
	}
	[self layoutOverlays];
}

#pragma mark - grouping

- (NSString *)dayTitleForDate:(int)date {
	time_t stamp = (time_t)date;
	struct tm parts;
	localtime_r(&stamp, &parts);
	time_t now = time(0);
	struct tm nowParts;
	localtime_r(&now, &nowParts);

	if (parts.tm_year == nowParts.tm_year && parts.tm_yday == nowParts.tm_yday)
		return @"Today";
	if (parts.tm_year == nowParts.tm_year && parts.tm_yday == nowParts.tm_yday - 1)
		return @"Yesterday";

	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateStyle = NSDateFormatterMediumStyle;
	formatter.timeStyle = NSDateFormatterNoStyle;
	return [formatter stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)date]];
}

- (void)rebuildSections {
	[self.sections removeAllObjects];

	NSString *currentTitle = nil;
	NSMutableArray *currentRows = nil;
	for (NSDictionary *event in self.events){
		NSString *title = [self dayTitleForDate:[event[@"date"] intValue]];
		if (!currentTitle || ![title isEqualToString:currentTitle]){
			currentTitle = title;
			currentRows = [NSMutableArray array];
			[self.sections addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
					title, @"title", currentRows, @"rows", nil]];
		}
		[currentRows addObject:event];
	}
}

- (NSDictionary *)eventAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.sections.count)
		return nil;
	NSArray *rows = self.sections[indexPath.section][@"rows"];
	if (indexPath.row >= (NSInteger)rows.count)
		return nil;
	return rows[indexPath.row];
}

- (NSString *)summaryForEvent:(NSDictionary *)event {
	NSString *text = event[@"text"];
	if ([text isKindOfClass:[NSString class]] && text.length)
		return text;
	NSString *action = event[@"action"];
	if ([action isKindOfClass:[NSString class]] && action.length)
		return action;
	return @"Unknown action";
}

#pragma mark - filter

- (void)filterPressed {
	TGChatEventsFilterController *controller =
			[[TGChatEventsFilterController alloc] initWithFilters:self.filters];
	__weak typeof(self) weakSelf = self;
	controller.completion = ^(NSArray *filters){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.filters = filters;
		[strongSelf reload];
	};

	UINavigationController *navigation =
			[[UINavigationController alloc] initWithRootViewController:controller];
	[[TGTheme shared] styleNavigationBar:navigation.navigationBar];
	if ([self respondsToSelector:@selector(presentViewController:animated:completion:)])
		[self presentViewController:navigation animated:YES completion:nil];
	else
		[self presentModalViewController:navigation animated:YES];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section >= (NSInteger)self.sections.count)
		return 0;
	return (NSInteger)[self.sections[section][@"rows"] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return TGEventsHeaderHeight;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (section >= (NSInteger)self.sections.count)
		return nil;

	CGFloat width = tableView.bounds.size.width;
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, TGEventsHeaderHeight)];
	container.backgroundColor = TGEventsRGB(0xe4e9f0);

	NSString *name = section == 0 ? @"CategoryDividerFirst.png" : @"CategoryDivider.png";
	UIImage *art = [UIImage imageNamed:name];
	if (art){
		UIImage *stretched = [art stretchableImageWithLeftCapWidth:0 topCapHeight:0];
		UIImageView *background = [[UIImageView alloc] initWithImage:stretched];
		background.frame = CGRectMake(0, 0, width, TGEventsHeaderHeight);
		background.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[container addSubview:background];
	}

	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(10, 4 + TGEventsRetinaPixel(), width - 20, 18)];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont boldSystemFontOfSize:13];
	label.text = self.sections[section][@"title"];
	if ([[TGTheme shared] isDark]){
		label.textColor = [[TGTheme shared] sectionHeaderColour];
	} else {
		label.textColor = TGEventsRGB(0x697487);
		label.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.3f];
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *event = [self eventAtIndexPath:indexPath];
	if (!event)
		return TGEventsMinRowHeight;
	return [TGChatEventCell heightForText:[self summaryForEvent:event]
									width:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	TGChatEventCell *cell = (TGChatEventCell *)
			[tableView dequeueReusableCellWithIdentifier:@"event"];
	if (!cell)
		cell = [[TGChatEventCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"event"];

	NSDictionary *event = [self eventAtIndexPath:indexPath];
	BOOL dark = [[TGTheme shared] isDark];

	NSString *name = event[@"name"];
	if (![name isKindOfClass:[NSString class]] || !name.length)
		name = @"Someone";

	cell.backgroundColor = dark ? [[TGTheme shared] listBackgroundColour]
								: [UIColor whiteColor];
	cell.contentView.backgroundColor = cell.backgroundColor;

	cell.nameLabel.text = name;
	cell.nameLabel.textColor = dark ? [[TGTheme shared] primaryTextColour]
									: TGEventsRGB(0x345f8f);

	cell.bodyLabel.text = [self summaryForEvent:event];
	cell.bodyLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
									: TGEventsRGB(0x536c8c);

	cell.dateLabel.text = [TGDateUtils stringForShortTime:[event[@"date"] intValue]];
	cell.dateLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
									: TGEventsRGB(0x337acc);

	cell.hairline.backgroundColor = [[TGTheme shared] separatorColour];

	int64_t userId = [event[@"userId"] longLongValue];
	cell.avatarView.image = [TGIcons avatarWithInitials:TGEventsInitials(name)
												   size:TGEventsAvatarSide
											   colourId:userId];
	[cell setNeedsLayout];
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.exhausted || self.loading || !self.loaded)
		return;
	if (indexPath.section + 1 < (NSInteger)self.sections.count)
		return;
	NSInteger rows = [self tableView:tableView numberOfRowsInSection:indexPath.section];
	if (indexPath.row + 5 < rows)
		return;
	[self loadNextPage];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end

// vim:ft=objc

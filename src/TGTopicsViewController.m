#import "TGTopicsViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGClient+Forums.h"
#import "TGClient+Notifications.h"
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

static BOOL TGTopicFlag(NSDictionary *topic, NSString *key) {
	id value = [topic isKindOfClass:[NSDictionary class]] ? topic[key] : nil;
	return [value isKindOfClass:[NSNumber class]] && [value boolValue];
}

static NSInteger TGTopicInteger(NSDictionary *topic, NSString *key) {
	id value = [topic isKindOfClass:[NSDictionary class]] ? topic[key] : nil;
	return [value isKindOfClass:[NSNumber class]] ? [value integerValue] : 0;
}

static long long TGTopicLongLong(NSDictionary *topic, NSString *key) {
	id value = [topic isKindOfClass:[NSDictionary class]] ? topic[key] : nil;
	return [value isKindOfClass:[NSNumber class]] ? [value longLongValue] : 0;
}

static double TGTopicDouble(NSDictionary *topic, NSString *key) {
	id value = [topic isKindOfClass:[NSDictionary class]] ? topic[key] : nil;
	return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : 0;
}

static NSString *TGTopicString(NSDictionary *topic, NSString *key) {
	id value = [topic isKindOfClass:[NSDictionary class]] ? topic[key] : nil;
	return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSString *TGTopicInitial(NSString *name) {
	if (!name.length)
		return @"?";
	NSRange first = [name rangeOfComposedCharacterSequenceAtIndex:0];
	return [[name substringWithRange:first] uppercaseString];
}

static UIImage *TGTopicPlateImage(void) {
	static UIImage *plate = nil;
	if (!plate)
		plate = [[UIImage imageNamed:@"DialogListCell.png"] stretchableImageWithLeftCapWidth:1 topCapHeight:0];
	return plate;
}

static UIColor *TGTopicRGB(NSInteger rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:1.0f];
}

static UIImage *TGTopicDrawAvatar(NSString *initials, CGFloat size, NSInteger rgb) {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size)
													cornerRadius:size * 0.12f];
	CGContextSetRGBFillColor(ctx,
			((rgb >> 16) & 0xff) / 255.0f,
			((rgb >> 8) & 0xff) / 255.0f,
			(rgb & 0xff) / 255.0f, 1.0f);
	CGContextAddPath(ctx, shape.CGPath);
	CGContextFillPath(ctx);

	if (![TGTheme shared].isFlat){
		CGContextSaveGState(ctx);
		CGContextAddPath(ctx, shape.CGPath);
		CGContextClip(ctx);
		CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.20f);
		CGContextFillEllipseInRect(ctx,
				CGRectMake(-size * 0.2f, -size * 0.55f, size * 1.4f, size * 0.95f));
		CGContextRestoreGState(ctx);
	}

	NSString *text = initials.length ? initials : @"?";
	UIFont *font = [UIFont boldSystemFontOfSize:size * 0.4f];
	CGSize textSize = [text sizeWithFont:font];
	[[UIColor whiteColor] set];
	[text drawAtPoint:CGPointMake((size - textSize.width) / 2,
								  (size - textSize.height) / 2)
			 withFont:font];

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

static NSMutableDictionary *TGTopicAvatarCache = nil;

static void TGTopicFlushAvatarCache(void) {
	[TGTopicAvatarCache removeAllObjects];
}

static UIImage *TGTopicAvatarImage(NSString *initials, CGFloat size, NSInteger rgb) {
	if (!TGTopicAvatarCache)
		TGTopicAvatarCache = [[NSMutableDictionary alloc] init];

	NSString *letter = initials.length ? initials : @"?";
	NSString *key = [NSString stringWithFormat:@"%ld.%@.%d", (long)rgb, letter, (int)size];
	UIImage *cached = [TGTopicAvatarCache objectForKey:key];
	if (cached)
		return cached;

	UIImage *image = TGTopicDrawAvatar(initials, size, rgb);
	if (image){
		if (TGTopicAvatarCache.count > 48)
			[TGTopicAvatarCache removeAllObjects];
		[TGTopicAvatarCache setObject:image forKey:key];
	}
	return image;
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
@property (nonatomic, strong) UIImageView *muteIcon;
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

	self.muteIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"DialogList_Muted.png"]];
	self.muteIcon.hidden = YES;
	[self.contentView addSubview:self.muteIcon];

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

	CGSize muteSize = (!self.muteIcon.hidden && self.muteIcon.image)
			? self.muteIcon.image.size : CGSizeZero;

	CGFloat titleWidth = (int)(dateX - 4 - left - 18 - (muteSize.width ? muteSize.width + 3 : 0));
	titleWidth = MIN(titleWidth, [self.titleLabel.text sizeWithFont:self.titleLabel.font].width);
	if (titleWidth < 0)
		titleWidth = 0;
	self.titleLabel.frame = CGRectMake(left, 6, titleWidth, 20);

	if (muteSize.width > 0)
		self.muteIcon.frame = CGRectMake(left + titleWidth + 3, 12,
				muteSize.width, muteSize.height);

	self.previewLabel.frame = CGRectMake(left, 29, w - left - 10 - rightPadding, 40);

	self.arrow.frame = CGRectMake(w - self.arrow.image.size.width - 6, 33,
			self.arrow.image.size.width, self.arrow.image.size.height);
}

@end

static const NSInteger kTopicNameAlertCreate = 91;
static const NSInteger kTopicNameAlertEdit = 92;
static const NSInteger kTopicDeleteAlert = 93;

@interface TGTopicsViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *topics;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UILabel *emptyText;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) NSDictionary *nextOffset;
@property (nonatomic, assign) NSInteger totalCount;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL reachedEnd;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL loadedOnce;
@property (nonatomic, strong) NSArray *iconChoices;
@property (nonatomic, strong) NSDictionary *actionTopic;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, assign) CGPoint menuPoint;
@property (nonatomic, assign) BOOL reordering;
@property (nonatomic, assign) BOOL orderDirty;
@end

@implementation TGTopicsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Topics";
	[self buildTitleView];
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
			CGRectMake(0, 150, background.bounds.size.width, 20)];
	self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.emptyLabel.backgroundColor = [UIColor clearColor];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.font = [UIFont boldSystemFontOfSize:15];
	self.emptyLabel.textColor = TGTopicRGB(0x8b97a5);
	self.emptyLabel.text = @"No Topics Yet";
	self.emptyLabel.hidden = YES;
	[background addSubview:self.emptyLabel];

	self.emptyText = [[UILabel alloc] initWithFrame:
			CGRectMake(35, 178, background.bounds.size.width - 70, 40)];
	self.emptyText.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.emptyText.backgroundColor = [UIColor clearColor];
	self.emptyText.textAlignment = NSTextAlignmentCenter;
	self.emptyText.numberOfLines = 0;
	self.emptyText.lineBreakMode = NSLineBreakByWordWrapping;
	self.emptyText.font = [UIFont systemFontOfSize:14];
	self.emptyText.textColor = TGTopicRGB(0x8b97a5);
	self.emptyText.text = @"Topics keep separate conversations in one group.";
	self.emptyText.hidden = YES;
	[background addSubview:self.emptyText];

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

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	TGTopicFlushAvatarCache();
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

- (void)buildTitleView {
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 40)];

	UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(0, 1, 200, 20)];
	name.text = self.chatTitle.length ? self.chatTitle : @"Topics";
	name.font = [UIFont boldSystemFontOfSize:17];
	name.textColor = [[TGTheme shared] barTitleColour];
	name.backgroundColor = [UIColor clearColor];
	name.textAlignment = NSTextAlignmentCenter;
	if (![TGTheme shared].isFlat){
		name.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.4f];
		name.shadowOffset = CGSizeMake(0, -1);
	}
	[header addSubview:name];

	self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 21, 200, 14)];
	self.subtitleLabel.font = [UIFont systemFontOfSize:12];
	self.subtitleLabel.textColor = [TGTheme shared].isFlat
			? [[TGTheme shared] secondaryTextColour]
			: [UIColor colorWithWhite:1.0f alpha:0.75f];
	self.subtitleLabel.backgroundColor = [UIColor clearColor];
	self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
	[header addSubview:self.subtitleLabel];

	self.navigationItem.titleView = header;
}

- (void)updateSubtitle {
	NSInteger count = MAX(self.totalCount, (NSInteger)self.topics.count);
	if (count <= 0)
		self.subtitleLabel.text = @"";
	else if (count == 1)
		self.subtitleLabel.text = @"1 topic";
	else
		self.subtitleLabel.text = [NSString stringWithFormat:@"%ld topics", (long)count];
}

- (void)themeChanged {
	TGTheme *theme = [TGTheme shared];
	TGTopicFlushAvatarCache();
	[theme styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	self.tableView.backgroundView.backgroundColor = [theme listBackgroundColour];
	[self buildTitleView];
	[self updateSubtitle];
	BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
	self.tableView.separatorStyle = plainPlate
			? UITableViewCellSeparatorStyleNone
			: UITableViewCellSeparatorStyleSingleLine;
	[self.tableView reloadData];
}

- (void)reloadTopics {
	if (self.loading || self.reordering)
		return;
	self.loading = YES;

	if (!self.loadedOnce){
		self.emptyLabel.hidden = YES;
		self.emptyText.hidden = YES;
		[self.spinner startAnimating];
	}

	self.nextOffset = nil;
	self.reachedEnd = NO;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] forumTopicsForChat:self.chatId
									query:nil
							   offsetDate:0
						  offsetMessageId:0
							offsetTopicId:0
									limit:40
							   completion:^(NSArray *topics, NSDictionary *nextOffset, NSInteger totalCount){
		TGTopicsViewController *me = weakSelf;
		if (!me)
			return;
		me.loading = NO;
		me.loadedOnce = YES;
		[me.spinner stopAnimating];
		if ([me respondsToSelector:@selector(refreshControl)])
			[me.refreshControl endRefreshing];

		me.totalCount = totalCount;
		me.nextOffset = nextOffset;
		NSArray *clean = [me cleanedTopics:topics];
		me.reachedEnd = (clean.count == 0 || nextOffset == nil);
		me.topics = [me orderedTopics:clean];

		[me updateEmptyState];
		[me updateSubtitle];
		[me.tableView reloadData];
	}];
}

- (NSArray *)cleanedTopics:(NSArray *)topics {
	NSMutableArray *clean = [NSMutableArray array];
	if ([topics isKindOfClass:NSArray.class]){
		for (id topic in topics){
			if ([topic isKindOfClass:NSDictionary.class])
				[clean addObject:topic];
		}
	}
	return clean;
}

- (NSArray *)orderedTopics:(NSArray *)topics {
	NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:topics.count];
	for (NSDictionary *topic in topics){
		if (TGTopicFlag(topic, @"isPinned"))
			[ordered addObject:topic];
	}
	for (NSDictionary *topic in topics){
		if (!TGTopicFlag(topic, @"isPinned"))
			[ordered addObject:topic];
	}
	return ordered;
}

- (void)updateEmptyState {
	BOOL empty = (self.topics.count == 0 && self.loadedOnce);
	self.emptyLabel.hidden = !empty;
	self.emptyText.hidden = !empty;
}

- (void)loadMoreTopics {
	if (self.loading || self.loadingMore || self.reordering || self.reachedEnd)
		return;
	NSDictionary *offset = self.nextOffset;
	if (![offset isKindOfClass:NSDictionary.class]){
		self.reachedEnd = YES;
		return;
	}

	self.loadingMore = YES;
	NSInteger offsetDate = TGTopicInteger(offset, @"date");
	int64_t offsetMessageId = TGTopicLongLong(offset, @"messageId");
	int32_t offsetTopicId = (int32_t)TGTopicInteger(offset, @"topicId");

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] forumTopicsForChat:self.chatId
									query:nil
							   offsetDate:offsetDate
						  offsetMessageId:offsetMessageId
							offsetTopicId:offsetTopicId
									limit:40
							   completion:^(NSArray *topics, NSDictionary *nextOffset, NSInteger totalCount){
		TGTopicsViewController *me = weakSelf;
		if (!me)
			return;
		me.loadingMore = NO;

		NSArray *page = [me cleanedTopics:topics];
		if (page.count == 0 || nextOffset == nil)
			me.reachedEnd = YES;
		if (page.count == 0)
			return;

		if (totalCount > 0)
			me.totalCount = totalCount;
		me.nextOffset = nextOffset;

		NSMutableSet *known = [NSMutableSet set];
		for (NSDictionary *topic in me.topics)
			[known addObject:@([me topicIdOf:topic])];

		NSMutableArray *combined = [me.topics mutableCopy];
		for (NSDictionary *topic in page){
			NSNumber *identifier = @([me topicIdOf:topic]);
			if ([known containsObject:identifier])
				continue;
			[known addObject:identifier];
			[combined addObject:topic];
		}
		me.topics = [me orderedTopics:combined];

		[me updateEmptyState];
		[me updateSubtitle];
		[me.tableView reloadData];
	}];
}

- (void)tableView:(UITableView *)tableView
		willDisplayCell:(UITableViewCell *)cell
	  forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= (NSInteger)self.topics.count - 3)
		[self loadMoreTopics];
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
	cell.muteIcon.hidden = YES;

	if (indexPath.row >= (NSInteger)self.topics.count)
		return cell;

	NSDictionary *t = self.topics[indexPath.row];
	NSInteger unread = TGTopicInteger(t, @"unread");

	NSString *name = TGTopicString(t, @"name");
	NSString *preview = TGTopicString(t, @"text");
	NSString *title = name.length ? name : @"Topic";
	BOOL closed = TGTopicFlag(t, @"isClosed");
	BOOL hidden = TGTopicFlag(t, @"isHidden");

	cell.titleLabel.text = title;
	if (closed){
		cell.previewLabel.text = @"Topic closed";
		if (plainPlate)
			cell.previewLabel.textColor = TGTopicRGB(0x536c8c);
	} else if (hidden){
		cell.previewLabel.text = preview.length
				? [NSString stringWithFormat:@"Hidden · %@", preview]
				: @"Hidden";
	} else {
		cell.previewLabel.text = preview;
	}
	cell.dateLabel.text = TGTopicDate(TGTopicDouble(t, @"date"));
	cell.pinIcon.hidden = !TGTopicFlag(t, @"isPinned");

	if (plainPlate){
		UIImageView *plate = (UIImageView *)cell.backgroundView;
		if (unread > 0){
			plate.image = nil;
			plate.backgroundColor = TGTopicRGB(0xebf0f5);
			if (!closed)
				cell.previewLabel.textColor = TGTopicRGB(0x5b646e);
		} else {
			plate.image = TGTopicPlateImage();
			plate.backgroundColor = [UIColor clearColor];
		}
	}

	NSString *initials = TGTopicInitial(title);
	NSInteger rgb = TGTopicInteger(t, @"iconColor");
	cell.avatar.image = (rgb > 0)
			? TGTopicAvatarImage(initials, kTopicAvatar, rgb)
			: [TGIcons avatarWithInitials:initials size:kTopicAvatar
								 colourId:[self topicIdOf:t]];

	cell.muteIcon.hidden = ![self topicIsMuted:t];

	NSInteger mentions = TGTopicInteger(t, @"unreadMentions");
	if (unread > 0){
		cell.badge.text = unread < 1000
				? [NSString stringWithFormat:@"%ld", (long)unread]
				: [NSString stringWithFormat:@"%ldK", (long)(unread / 1000)];
		cell.badge.hidden = NO;
		cell.badgeBackground.hidden = NO;
	} else if (mentions > 0){
		cell.badge.text = @"@";
		cell.badge.hidden = NO;
		cell.badgeBackground.hidden = NO;
	}

	[cell setNeedsLayout];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (self.reordering)
		return;

	if (indexPath.row >= (NSInteger)self.topics.count)
		return;

	NSDictionary *t = self.topics[indexPath.row];
	long long threadId = TGTopicLongLong(t, @"threadId");
	if (threadId == 0)
		return;

	NSString *name = TGTopicString(t, @"name");
	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = self.chatId;
	vc.threadId = threadId;
	vc.chatTitle = name.length ? name : @"Topic";
	vc.isGroup = YES;
	[self.navigationController pushViewController:vc animated:YES];

	int32_t topicId = [self topicIdOf:t];
	if (topicId != 0 && TGTopicInteger(t, @"unread") > 0)
		[[TGClient shared] markForumTopicReadInChat:self.chatId topic:topicId completion:nil];
}

#pragma mark - topic actions

- (int32_t)topicIdOf:(NSDictionary *)topic {
	int32_t topicId = (int32_t)TGTopicInteger(topic, @"topicId");
	if (topicId == 0)
		topicId = (int32_t)TGTopicLongLong(topic, @"threadId");
	return topicId;
}

- (void)showError:(NSString *)message {
	[[[UIAlertView alloc] initWithTitle:nil message:message delegate:nil
					  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (BOOL)topicIsMuted:(NSDictionary *)topic {
	return TGTopicInteger(topic, @"muteFor") > 0;
}

- (NSInteger)pinnedCount {
	NSInteger count = 0;
	for (NSDictionary *topic in self.topics){
		if (TGTopicFlag(topic, @"isPinned"))
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

	NSDictionary *t = self.topics[path.row];
	self.actionTopic = t;

	BOOL general = TGTopicFlag(t, @"isGeneral");
	BOOL closed = TGTopicFlag(t, @"isClosed");
	BOOL pinned = TGTopicFlag(t, @"isPinned");
	BOOL hidden = TGTopicFlag(t, @"isHidden");

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

	BOOL muted = [self topicIsMuted:t];
	[items addObject:@{@"title" : (muted ? @"Unmute" : @"Mute"),
					   @"icon"  : (muted ? @"unmute" : @"mute")}];
	[keys addObject:@"mute"];

	if (TGTopicInteger(t, @"unread") > 0 || TGTopicInteger(t, @"unreadMentions") > 0
			|| TGTopicInteger(t, @"unreadReactions") > 0){
		[items addObject:@{@"title" : @"Mark as Read", @"icon" : @"unmute"}];
		[keys addObject:@"read"];
	}

	[items addObject:@{@"title" : @"Copy Link", @"icon" : @"copy"}];
	[keys addObject:@"link"];

	if (pinned && [self pinnedCount] > 1){
		[items addObject:@{@"title" : @"Reorder Pins", @"icon" : @"pin"}];
		[keys addObject:@"reorder"];
	}

	if (!general){
		[items addObject:@{@"title"       : @"Delete",
						   @"icon"        : @"delete",
						   @"destructive" : @YES}];
		[keys addObject:@"delete"];
	}

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
		BOOL pin = !TGTopicFlag(t, @"isPinned");
		[[TGClient shared] setForumTopicInChat:self.chatId topic:topicId pinned:pin
									completion:^(BOOL success){
			if (!success)
				[weakSelf showError:pin ? @"Could not pin the topic."
									   : @"Could not unpin the topic."];
			[weakSelf reloadTopics];
		}];
	} else if ([key isEqualToString:@"close"]){
		BOOL close = !TGTopicFlag(t, @"isClosed");
		[[TGClient shared] setForumTopicInChat:self.chatId topic:topicId closed:close
									completion:^(BOOL success){
			if (!success)
				[weakSelf showError:close ? @"Could not close the topic."
										 : @"Could not reopen the topic."];
			[weakSelf reloadTopics];
		}];
	} else if ([key isEqualToString:@"mute"]){
		if ([self topicIsMuted:t]){
			[[TGClient shared] setForumTopicInChat:self.chatId topic:topicId mutedFor:0
										completion:^(BOOL success){
				if (!success)
					[weakSelf showError:@"Could not unmute the topic."];
				[weakSelf reloadTopics];
			}];
		} else {
			[self showMuteDurationsForTopic:topicId];
			return;
		}
	} else if ([key isEqualToString:@"read"]){
		[[TGClient shared] markForumTopicReadInChat:self.chatId topic:topicId
										 completion:^(BOOL success){
			if (!success)
				[weakSelf showError:@"Could not mark the topic as read."];
			[weakSelf reloadTopics];
		}];
	} else if ([key isEqualToString:@"link"]){
		[[TGClient shared] forumTopicLinkInChat:self.chatId topic:topicId
									 completion:^(NSString *link){
			if (link.length)
				[UIPasteboard generalPasteboard].string = link;
			else
				[weakSelf showError:@"Could not get a link to the topic."];
		}];
	} else if ([key isEqualToString:@"reorder"]){
		[self beginReordering];
		return;
	} else if ([key isEqualToString:@"delete"]){
		[self confirmDeleteTopic:t];
		return;
	} else if ([key isEqualToString:@"hide"]){
		BOOL hide = !TGTopicFlag(t, @"isHidden");
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

- (void)showMuteDurationsForTopic:(int32_t)topicId {
	NSArray *items = @[
		@{@"title" : @"Mute for 1 hour",  @"icon" : @"mute"},
		@{@"title" : @"Mute for 8 hours", @"icon" : @"mute"},
		@{@"title" : @"Mute for 2 days",  @"icon" : @"mute"},
		@{@"title" : @"Mute forever",     @"icon" : @"mute"},
	];
	NSArray *seconds = @[@(3600), @(8 * 3600), @(2 * 24 * 3600), @(TGNotificationMuteForever)];

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:self.menuPoint inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		TGTopicsViewController *me = weakSelf;
		if (!me || choice < 0 || choice >= (NSInteger)seconds.count)
			return;
		me.actionTopic = nil;
		[[TGClient shared] setForumTopicInChat:me.chatId topic:topicId
									  mutedFor:[seconds[choice] integerValue]
									completion:^(BOOL success){
			if (!success)
				[weakSelf showError:@"Could not mute the topic."];
			[weakSelf reloadTopics];
		}];
	}];
}

- (void)confirmDeleteTopic:(NSDictionary *)topic {
	self.actionTopic = topic;
	NSString *name = TGTopicString(topic, @"name");
	if (!name.length)
		name = @"this topic";
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Delete Topic"
													message:[NSString stringWithFormat:
															@"Delete %@ and all of its messages?", name]
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Delete", nil];
	alert.tag = kTopicDeleteAlert;
	[alert show];
}

#pragma mark - reordering pinned topics

- (void)beginReordering {
	if ([self pinnedCount] < 2)
		return;

	self.actionTopic = nil;
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

	UIButton *create = [TGIcons headerButtonWithTitle:@"New" bold:NO
											   target:self action:@selector(newTopicPressed)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:create];

	if (!self.orderDirty){
		[self reloadTopics];
		return;
	}
	self.orderDirty = NO;

	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *topic in self.topics){
		if (!TGTopicFlag(topic, @"isPinned"))
			break;
		int32_t topicId = [self topicIdOf:topic];
		if (topicId != 0)
			[ids addObject:@(topicId)];
	}
	if (ids.count < 2){
		[self reloadTopics];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPinnedForumTopicsInChat:self.chatId topicIds:ids
									   completion:^(BOOL success){
		if (!success)
			[weakSelf showError:@"Could not save the order of the pinned topics."];
		[weakSelf reloadTopics];
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
		[alert textFieldAtIndex:0].text = TGTopicString(topic, @"name");
	}
	[alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex){
		self.actionTopic = nil;
		return;
	}

	if (alertView.tag == kTopicDeleteAlert){
		NSDictionary *t = self.actionTopic;
		self.actionTopic = nil;
		int32_t topicId = [self topicIdOf:t];
		if (topicId == 0)
			return;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] deleteForumTopicInChat:self.chatId topic:topicId
									   completion:^(BOOL success){
			if (!success)
				[weakSelf showError:@"Could not delete the topic."];
			[weakSelf reloadTopics];
		}];
		return;
	}

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
		if (!me)
			return;
		if ([action isEqualToString:@"cancel"]){
			me.actionTopic = nil;
			return;
		}

		int64_t emojiId = 0;
		BOOL changeIcon = YES;
		if ([action isEqualToString:@"none"])
			changeIcon = !editing;
		else if (![action isEqualToString:@"clear"]){
			NSInteger index = [[action substringFromIndex:4] integerValue];
			if (index >= 0 && index < (NSInteger)icons.count)
				emojiId = TGTopicLongLong(icons[(NSUInteger)index], @"emojiId");
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
	if (![colours isKindOfClass:[NSArray class]] || colours.count == 0)
		return 0;
	NSUInteger index = (NSUInteger)labs((long)name.hash) % colours.count;
	id colour = colours[index];
	return [colour isKindOfClass:[NSNumber class]] ? [colour integerValue] : 0;
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

#import "TGTopicsViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kTopicRowHeight = 62.0f;
static const CGFloat kTopicTextLeft = 15.0f;

static UIImage *TGTopicBadgeImage(void) {
	static UIImage *normal = nil;
	if (!normal){
		UIImage *raw = [UIImage imageNamed:@"DialogListUnreadBadge.png"];
		normal = [raw stretchableImageWithLeftCapWidth:(int)(raw.size.width / 2)
										  topCapHeight:(int)(raw.size.height / 2)];
	}
	return normal;
}

@interface TGTopicCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UIImageView *badgeBackground;
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, strong) UIImageView *arrow;
@end

@implementation TGTopicCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

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
	self.previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.previewLabel];

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
	CGFloat rightPadding = 16;

	CGFloat countWidth = (int)[self.badge.text sizeWithFont:self.badge.font].width;
	CGFloat badgeWidth = MAX(27, countWidth + 10);
	CGRect badgeFrame = CGRectMake(w - 28 - badgeWidth, 21, badgeWidth, 21);
	self.badgeBackground.frame = badgeFrame;
	self.badge.frame = badgeFrame;
	if (!self.badge.hidden)
		rightPadding += badgeWidth + 7;

	self.titleLabel.frame = CGRectMake(kTopicTextLeft, 8,
			w - kTopicTextLeft - 10 - rightPadding, 20);
	self.previewLabel.frame = CGRectMake(kTopicTextLeft, 30,
			w - kTopicTextLeft - 10 - rightPadding, 20);

	self.arrow.frame = CGRectMake(w - self.arrow.image.size.width - 6, 27,
			self.arrow.image.size.width, self.arrow.image.size.height);
}

@end

@interface TGTopicsViewController ()
@property (nonatomic, strong) NSArray *topics;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL loadedOnce;
@end

@implementation TGTopicsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
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
	[[TGClient shared] forumTopicsForChat:self.chatId completion:^(NSArray *topics){
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

	if (indexPath.row >= (NSInteger)self.topics.count)
		return cell;

	NSDictionary *t = self.topics[indexPath.row];
	NSInteger unread = [t[@"unread"] respondsToSelector:@selector(integerValue)]
			? [t[@"unread"] integerValue] : 0;

	NSString *name = [t[@"name"] isKindOfClass:NSString.class] ? t[@"name"] : @"";
	NSString *preview = [t[@"text"] isKindOfClass:NSString.class] ? t[@"text"] : @"";
	cell.titleLabel.text = name.length ? name : @"Topic";
	cell.previewLabel.text = preview;

	if (unread > 0){
		cell.badge.text = [NSString stringWithFormat:@"%ld", (long)unread];
		cell.badge.hidden = NO;
		cell.badgeBackground.hidden = NO;
	} else {
		cell.badge.text = nil;
		cell.badge.hidden = YES;
		cell.badgeBackground.hidden = YES;
	}

	TGTheme *theme = [TGTheme shared];
	if (theme.isDark || theme.importedName != nil){
		cell.backgroundView = nil;
		cell.backgroundColor = [theme listBackgroundColour];
		cell.titleLabel.textColor = [theme primaryTextColour];
		cell.previewLabel.textColor = [theme secondaryTextColour];
	} else if (cell.backgroundView == nil){
		UIImage *plate = [[UIImage imageNamed:@"DialogListCell.png"]
				stretchableImageWithLeftCapWidth:1 topCapHeight:0];
		cell.backgroundView = [[UIImageView alloc] initWithImage:plate];
		cell.backgroundColor = [UIColor clearColor];
		cell.titleLabel.textColor = [UIColor colorWithRed:0x11 / 255.0f green:0x11 / 255.0f blue:0x11 / 255.0f alpha:1.0f];
		cell.previewLabel.textColor = [UIColor colorWithRed:0x88 / 255.0f green:0x88 / 255.0f blue:0x88 / 255.0f alpha:1.0f];
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
}

@end

// vim:ft=objc

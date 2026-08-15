#import "TGStarsViewController.h"
#import "TGClient.h"
#import "TGClient+Premium.h"
#import "TGClient+Payments.h"
#import "TGClient+ChatList.h"
#import "TGClient+Contacts.h"
#import "TGForwardPicker.h"
#import "TGAlertView.h"
#import "TGActionSheet.h"
#import "TGTheme.h"
#import "TGIcons.h"

static const NSInteger kStarsPageSize = 25;
static const NSInteger kStarsGiftPageSize = 20;

static inline UIColor *TGStarsRGB(unsigned int value) {
	return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0f
						   green:((value >> 8) & 0xff) / 255.0f
							blue:(value & 0xff) / 255.0f
						   alpha:1.0f];
}

static UIView *TGStarsSectionHeaderWithTitle(NSString *title) {
	if (!title.length)
		return nil;
	BOOL dark = [[TGTheme shared] isDark];
	UILabel *label = [[UILabel alloc] init];
	label.text = title;
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont boldSystemFontOfSize:17];
	label.textColor = dark ? [[TGTheme shared] sectionHeaderColour] : TGStarsRGB(0x697487);
	if (!dark){
		label.shadowColor = TGStarsRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 21, 16);
	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 46)];
	container.backgroundColor = [UIColor clearColor];
	[container addSubview:label];
	return container;
}

static NSDictionary *TGStarsAction(NSString *title,
								   NSString *value,
								   BOOL destructive,
								   void (^block)(void))
{
	NSMutableDictionary *action = [NSMutableDictionary dictionary];
	action[@"title"] = title ?: @"";
	if (value.length)
		action[@"value"] = value;
	if (destructive)
		action[@"destructive"] = @YES;
	if (block)
		action[@"block"] = [block copy];
	return action;
}

static UIFont *TGStarsCommentFont(void) {
	return [UIFont systemFontOfSize:14];
}

static CGFloat TGStarsCommentHeight(NSString *comment, CGFloat width) {
	if (!comment.length)
		return 8;
	CGSize size = [comment sizeWithFont:TGStarsCommentFont()
					  constrainedToSize:CGSizeMake(width - 24, 1000)
						  lineBreakMode:UILineBreakModeWordWrap];
	return size.height + 14;
}

static UIView *TGStarsCommentViewWithText(NSString *comment, CGFloat width) {
	if (!comment.length)
		return nil;
	BOOL dark = [[TGTheme shared] isDark];
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, TGStarsCommentHeight(comment, width))];
	container.backgroundColor = [UIColor clearColor];
	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(12, 7, width - 24, container.frame.size.height - 14)];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	label.text = comment;
	label.textAlignment = UITextAlignmentCenter;
	label.font = TGStarsCommentFont();
	label.backgroundColor = [UIColor clearColor];
	label.textColor = dark ? [[TGTheme shared] secondaryTextColour] : TGStarsRGB(0x697487);
	if (!dark){
		label.shadowColor = TGStarsRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	label.lineBreakMode = UILineBreakModeWordWrap;
	label.numberOfLines = 0;
	[container addSubview:label];
	return container;
}

static NSDictionary *TGStarsRow(NSString *title,
								NSString *subtitle,
								NSString *value,
								void (^block)(void))
{
	NSMutableDictionary *row = [NSMutableDictionary dictionary];
	row[@"title"] = title ?: @"";
	if (subtitle.length)
		row[@"subtitle"] = subtitle;
	if (value.length)
		row[@"value"] = value;
	if (block)
		row[@"block"] = [block copy];
	return row;
}

@interface TGStarsListViewController : UITableViewController

- (id)initWithTitle:(NSString *)title;

@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSString *comment;
@property (nonatomic, strong) NSString *emptyText;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL moreAvailable;
@property (nonatomic, copy) void (^loadMoreBlock)(void);

- (void)appendRow:(NSDictionary *)row;
- (void)finishLoadingWithMore:(BOOL)more;

@end

@implementation TGStarsListViewController

- (id)initWithTitle:(NSString *)title {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		self.title = title;
		self.rows = [NSMutableArray array];
		self.emptyText = @"Nothing Here";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	if (self.navigationController.navigationBar)
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if ([self.tableView indexPathForSelectedRow])
		[self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow]
									  animated:animated];
}

- (void)appendRow:(NSDictionary *)row {
	if (row)
		[self.rows addObject:row];
}

- (void)finishLoadingWithMore:(BOOL)more {
	self.loading = NO;
	self.moreAvailable = more;
	[self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (!self.rows.count)
		return 1;
	return (NSInteger)self.rows.count + (self.moreAvailable ? 1 : 0);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row < (NSInteger)self.rows.count && self.rows[indexPath.row][@"subtitle"])
		return 51;
	return 44;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return 8;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if (!self.comment.length)
		return 8;
	return TGStarsCommentHeight(self.comment, tableView.bounds.size.width ?: 320);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	return TGStarsCommentViewWithText(self.comment, tableView.bounds.size.width ?: 320);
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	BOOL dark = [[TGTheme shared] isDark];
	if (!self.rows.count || indexPath.row >= (NSInteger)self.rows.count){
		static NSString *statusId = @"TGStarsListStatus";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:statusId];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:statusId];
		BOOL isMore = self.rows.count > 0;
		cell.textLabel.textAlignment = isMore ? UITextAlignmentLeft : UITextAlignmentCenter;
		cell.textLabel.font = [UIFont boldSystemFontOfSize:isMore ? 17 : 14];
		if (self.loading){
			cell.textLabel.text = @"Loading...";
			cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		} else if (isMore){
			cell.textLabel.text = @"Show more";
			cell.textLabel.textColor = TGStarsRGB(0x0779d0);
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		} else {
			cell.textLabel.text = self.emptyText;
			cell.textLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
											: TGStarsRGB(0x8694a4);
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		cell.accessoryType = UITableViewCellAccessoryNone;
		[[TGTheme shared] styleCell:cell];
		return cell;
	}

	NSDictionary *row = self.rows[indexPath.row];
	NSString *subtitle = row[@"subtitle"];
	NSString *reuseId = subtitle.length ? @"TGStarsListSubtitle" : @"TGStarsListValue";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:subtitle.length
					? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1
									  reuseIdentifier:reuseId];
	cell.textLabel.text = row[@"title"];
	cell.textLabel.textAlignment = UITextAlignmentLeft;
	cell.textLabel.font = [UIFont systemFontOfSize:16];
	cell.textLabel.textColor = [row[@"destructive"] boolValue]
			? TGStarsRGB(0xd12b1f) : [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.text = subtitle.length ? subtitle : row[@"value"];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:subtitle.length ? 13 : 16];
	cell.detailTextLabel.textColor = subtitle.length
			? TGStarsRGB(0x888888)
			: (dark ? [[TGTheme shared] cellDetailColour] : TGStarsRGB(0x356596));
	BOOL tappable = row[@"block"] != nil;
	cell.accessoryType = (tappable && !subtitle.length && !row[@"value"])
			? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	cell.selectionStyle = tappable ? UITableViewCellSelectionStyleBlue
								   : UITableViewCellSelectionStyleNone;
	[[TGTheme shared] styleCell:cell];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (!self.rows.count)
		return;
	if (indexPath.row >= (NSInteger)self.rows.count){
		if (self.loading || !self.loadMoreBlock)
			return;
		self.loading = YES;
		[tableView reloadData];
		self.loadMoreBlock();
		return;
	}
	void (^block)(void) = self.rows[indexPath.row][@"block"];
	if (block)
		block();
}

@end

@interface TGStarsDetailViewController : UITableViewController

- (id)initWithTitle:(NSString *)title
			  pairs:(NSArray *)pairs
			comment:(NSString *)comment;

@property (nonatomic, strong) NSArray *pairs;
@property (nonatomic, strong) NSString *comment;
@property (nonatomic, strong) NSArray *actions;
@property (nonatomic, strong) NSString *actionsComment;
@property (nonatomic, assign) BOOL busy;

@end

@implementation TGStarsDetailViewController

- (id)initWithTitle:(NSString *)title
			  pairs:(NSArray *)pairs
			comment:(NSString *)comment
{
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		self.title = title;
		self.pairs = pairs;
		self.comment = comment;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	if (self.navigationController.navigationBar)
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.actions.count ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return (NSInteger)self.pairs.count;
	return (NSInteger)self.actions.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 44;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return 8;
}

- (NSString *)commentForSection:(NSInteger)section {
	if (section == 0)
		return self.comment;
	return self.actionsComment;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	NSString *comment = [self commentForSection:section];
	if (!comment.length)
		return (section == 0 && self.actions.count) ? 1 : 8;
	return TGStarsCommentHeight(comment, self.tableView.bounds.size.width ?: 320);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	return TGStarsCommentViewWithText([self commentForSection:section],
			self.tableView.bounds.size.width ?: 320);
}

- (UITableViewCell *)actionCellInTable:(UITableView *)tableView row:(NSInteger)row {
	static NSString *reuseId = @"TGStarsDetailAction";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:reuseId];
	NSDictionary *action = self.actions[row];
	cell.textLabel.text = action[@"title"];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textAlignment = UITextAlignmentLeft;
	cell.detailTextLabel.text = action[@"value"];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] cellDetailColour] : TGStarsRGB(0x356596);
	cell.accessoryType = UITableViewCellAccessoryNone;
	[[TGTheme shared] styleCell:cell];
	if (self.busy){
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	} else {
		cell.textLabel.textColor = [action[@"destructive"] boolValue]
				? TGStarsRGB(0xd12b1f) : TGStarsRGB(0x0779d0);
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1 || self.busy)
		return;
	if (indexPath.row >= (NSInteger)self.actions.count)
		return;
	void (^block)(void) = self.actions[indexPath.row][@"block"];
	if (block)
		block();
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.section == 1)
		return [self actionCellInTable:tableView row:indexPath.row];

	static NSString *reuseId = @"TGStarsDetailPair";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:reuseId];
	NSArray *pair = self.pairs[indexPath.row];
	cell.textLabel.text = pair[0];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.text = pair[1];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] cellDetailColour] : TGStarsRGB(0x356596);
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;
	[[TGTheme shared] styleCell:cell];
	return cell;
}

@end

enum {
	TGStarsSectionBalance = 0,
	TGStarsSectionTransactions,
	TGStarsSectionSubscriptions,
	TGStarsSectionGifts,
	TGStarsSectionGiftTools,
	TGStarsSectionMore,
	TGStarsSectionCount
};

enum {
	TGStarsGiftToolCatalogue = 0,
	TGStarsGiftToolCollections,
	TGStarsGiftToolSettings,
	TGStarsGiftToolChannel,
	TGStarsGiftToolCount
};

enum {
	TGStarsMoreStarPacks = 0,
	TGStarsMoreIncoming,
	TGStarsMoreOutgoing,
	TGStarsMoreInvoice,
	TGStarsMorePaidMessages,
	TGStarsMoreClearPaymentInfo,
	TGStarsMoreCount
};

@interface TGStarsViewController ()
@property (nonatomic, strong) NSMutableArray *subscriptions;
@property (nonatomic, assign) BOOL subscriptionsLoaded;
@property (nonatomic, assign) BOOL subscriptionsLoading;
@property (nonatomic, strong) NSMutableArray *transactions;
@property (nonatomic, strong) NSMutableArray *gifts;
@property (nonatomic, strong) NSString *transactionsOffset;
@property (nonatomic, strong) NSString *giftsOffset;
@property (nonatomic, assign) BOOL transactionsLoaded;
@property (nonatomic, assign) BOOL transactionsFailed;
@property (nonatomic, assign) BOOL transactionsLoading;
@property (nonatomic, assign) BOOL giftsLoaded;
@property (nonatomic, assign) BOOL giftsLoading;
@property (nonatomic, assign) BOOL balanceKnown;
@property (nonatomic, assign) long long balance;
@property (nonatomic, assign) NSInteger giftTotal;
@property (nonatomic, strong) NSArray *sectionHeaderViews;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@end

@implementation TGStarsViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Telegram Stars";
	self.transactions = [NSMutableArray array];
	self.gifts = [NSMutableArray array];
	self.subscriptions = [NSMutableArray array];
	self.transactionsOffset = @"";
	self.giftsOffset = @"";
	self.balance = [[TGClient shared] cachedStarBalance];
	self.balanceKnown = self.balance != 0;

	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	if (self.navigationController.navigationBar)
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	UIButton *reload = [TGIcons headerButtonWithTitle:@"Reload" bold:NO
											   target:self action:@selector(reloadTapped)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:reload];

	[self generateSectionHeaders];
	[self loadFirstPages];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if ([self.tableView indexPathForSelectedRow])
		[self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow]
									  animated:animated];
}

- (void)generateSectionHeaders {
	NSString *giftsTitle = self.giftTotal > 0
			? [NSString stringWithFormat:@"Gifts Received (%d)", (int)self.giftTotal]
			: @"Gifts Received";
	id subscriptionsHeader = self.subscriptions.count
			? TGStarsSectionHeaderWithTitle(@"Subscriptions") : (id)[NSNull null];
	self.sectionHeaderViews = [NSArray arrayWithObjects:
			[NSNull null],
			TGStarsSectionHeaderWithTitle(@"Transactions"),
			subscriptionsHeader,
			TGStarsSectionHeaderWithTitle(giftsTitle),
			TGStarsSectionHeaderWithTitle(@"Gifts"),
			TGStarsSectionHeaderWithTitle(@"More"), nil];
}

- (void)reloadTapped {
	[self.transactions removeAllObjects];
	[self.gifts removeAllObjects];
	[self.subscriptions removeAllObjects];
	self.subscriptionsLoaded = NO;
	self.subscriptionsLoading = NO;
	self.transactionsOffset = @"";
	self.giftsOffset = @"";
	self.transactionsLoaded = NO;
	self.transactionsFailed = NO;
	self.transactionsLoading = NO;
	self.giftsLoaded = NO;
	self.giftsLoading = NO;
	self.giftTotal = 0;
	[self generateSectionHeaders];
	[self.tableView reloadData];
	[self loadFirstPages];
}

#pragma mark - loading

- (void)loadFirstPages {
	[self loadMoreTransactions];
	[self loadMoreGifts];
	[self loadSubscriptions];
}

- (void)loadSubscriptions {
	if (self.subscriptionsLoading)
		return;
	self.subscriptionsLoading = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] starSubscriptionsOnlyExpiring:NO
											  offset:@""
										  completion:^(NSDictionary *page)
	{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.subscriptionsLoading = NO;
		strongSelf.subscriptionsLoaded = YES;
		[strongSelf.subscriptions removeAllObjects];
		if ([page isKindOfClass:[NSDictionary class]]){
			NSArray *rows = page[@"subscriptions"];
			if ([rows isKindOfClass:[NSArray class]]){
				for (id row in rows){
					if ([row isKindOfClass:[NSDictionary class]])
						[strongSelf.subscriptions addObject:row];
				}
			}
			NSNumber *balance = page[@"balance"];
			if ([balance isKindOfClass:[NSNumber class]] && [balance longLongValue]){
				strongSelf.balance = [balance longLongValue];
				strongSelf.balanceKnown = YES;
			}
		}
		[strongSelf generateSectionHeaders];
		[strongSelf.tableView reloadData];
	}];
}

- (void)loadMoreTransactions {
	if (self.transactionsLoading)
		return;
	self.transactionsLoading = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] starTransactionsWithOffset:self.transactionsOffset
										    limit:kStarsPageSize
									   completion:^(NSDictionary *page)
	{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.transactionsLoading = NO;
		strongSelf.transactionsLoaded = YES;
		if (![page isKindOfClass:[NSDictionary class]]){
			strongSelf.transactionsFailed = YES;
			[strongSelf.tableView reloadData];
			return;
		}
		strongSelf.transactionsFailed = NO;
		NSNumber *balance = page[@"balance"];
		if ([balance isKindOfClass:[NSNumber class]]){
			strongSelf.balance = [balance longLongValue];
			strongSelf.balanceKnown = YES;
		}
		NSArray *rows = page[@"transactions"];
		if ([rows isKindOfClass:[NSArray class]]){
			for (id row in rows){
				if ([row isKindOfClass:[NSDictionary class]])
					[strongSelf.transactions addObject:row];
			}
		}
		NSString *next = page[@"nextOffset"];
		strongSelf.transactionsOffset = [next isKindOfClass:[NSString class]] ? next : @"";
		[strongSelf.tableView reloadData];
	}];
}

- (void)loadMoreGifts {
	if (self.giftsLoading)
		return;
	int64_t userId = [[TGClient shared].me[@"id"] longLongValue];
	if (!userId){
		self.giftsLoaded = YES;
		[self.tableView reloadData];
		return;
	}
	self.giftsLoading = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] receivedGiftsForUser:userId
							   collectionId:0
									 offset:self.giftsOffset
									  limit:kStarsGiftPageSize
								 completion:^(NSArray *gifts, NSString *nextOffset, NSInteger total)
	{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.giftsLoading = NO;
		strongSelf.giftsLoaded = YES;
		if ([gifts isKindOfClass:[NSArray class]]){
			for (id gift in gifts){
				if ([gift isKindOfClass:[NSDictionary class]])
					[strongSelf.gifts addObject:gift];
			}
		}
		strongSelf.giftTotal = total;
		[strongSelf generateSectionHeaders];
		strongSelf.giftsOffset = [nextOffset isKindOfClass:[NSString class]] ? nextOffset : @"";
		[strongSelf.tableView reloadData];
	}];
}

- (BOOL)hasMoreTransactions {
	return self.transactions.count > 0 && self.transactionsOffset.length > 0;
}

- (BOOL)hasMoreGifts {
	return self.gifts.count > 0 && self.giftsOffset.length > 0;
}

#pragma mark - formatting

- (NSString *)formattedNumber:(NSNumber *)value {
	if (![value isKindOfClass:[NSNumber class]])
		return @"-";
	long long raw = [value longLongValue];
	if (raw >= 1000 || raw <= -1000){
		static NSNumberFormatter *formatter = nil;
		if (!formatter){
			formatter = [[NSNumberFormatter alloc] init];
			formatter.numberStyle = NSNumberFormatterDecimalStyle;
		}
		NSString *text = [formatter stringFromNumber:@(raw)];
		if (text.length)
			return text;
	}
	return [NSString stringWithFormat:@"%lld", raw];
}

- (NSString *)starsText:(long long)stars signed:(BOOL)withSign {
	return [NSString stringWithFormat:@"%@%@ ★",
			(withSign && stars > 0) ? @"+" : @"", [self formattedNumber:@(stars)]];
}

- (NSString *)dateTextFromValue:(NSNumber *)value {
	if (![value isKindOfClass:[NSNumber class]] || ![value doubleValue])
		return @"";
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterMediumStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
	}
	return [formatter stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[value doubleValue]]];
}

- (NSString *)counterpartyForTransaction:(NSDictionary *)transaction {
	NSString *title = transaction[@"title"];
	if ([title isKindOfClass:[NSString class]] && title.length)
		return title;
	NSString *type = transaction[@"type"];
	if ([type isKindOfClass:[NSString class]] && type.length)
		return type;
	return @"Telegram";
}

- (BOOL)transactionIsRefund:(NSDictionary *)transaction {
	return [transaction[@"refund"] boolValue] || [transaction[@"isRefund"] boolValue];
}

- (NSString *)subtitleForTransaction:(NSDictionary *)transaction {
	NSString *date = [self dateTextFromValue:transaction[@"date"]];
	if ([self transactionIsRefund:transaction]){
		if (date.length)
			return [NSString stringWithFormat:@"Refund · %@", date];
		return @"Refund";
	}
	return date;
}

- (NSString *)senderNameForGift:(NSDictionary *)gift {
	NSString *sender = gift[@"senderName"];
	if (![sender isKindOfClass:[NSString class]] || !sender.length){
		int64_t senderId = [gift[@"senderId"] longLongValue];
		sender = senderId ? [[TGClient shared] nameForUserId:senderId] : nil;
	}
	if (![sender isKindOfClass:[NSString class]] || !sender.length)
		return nil;
	return sender;
}

- (NSString *)initialsForName:(NSString *)name {
	if (!name.length)
		return @"★";
	return [[name substringToIndex:1] uppercaseString];
}

#pragma mark - shape

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return TGStarsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == TGStarsSectionBalance)
		return 1;
	if (section == TGStarsSectionTransactions){
		if (!self.transactions.count)
			return 1;
		return (NSInteger)self.transactions.count + ([self hasMoreTransactions] ? 1 : 0);
	}
	if (section == TGStarsSectionSubscriptions)
		return (NSInteger)self.subscriptions.count;
	if (section == TGStarsSectionGiftTools)
		return TGStarsGiftToolCount;
	if (section == TGStarsSectionMore)
		return TGStarsMoreCount;
	if (!self.gifts.count)
		return 1;
	return (NSInteger)self.gifts.count + ([self hasMoreGifts] ? 1 : 0);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	id header = self.sectionHeaderViews[section];
	return [header isKindOfClass:[UIView class]] ? 46 : 8;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	id header = self.sectionHeaderViews[section];
	return [header isKindOfClass:[UIView class]] ? header : nil;
}

- (NSString *)commentForSection:(NSInteger)section {
	if (section == TGStarsSectionBalance)
		return @"Stars are earned and spent inside Telegram. They cannot be bought here.";
	if (section == TGStarsSectionTransactions){
		if (self.transactionsFailed)
			return @"The history could not be loaded. Tap Reload to try again.";
		if (self.transactionsLoaded && !self.transactions.count)
			return @"Everything this account earns or spends will be listed here.";
		return nil;
	}
	if (section == TGStarsSectionSubscriptions){
		if (self.subscriptions.count)
			return @"Canceled subscriptions stay active until the paid period ends.";
		return nil;
	}
	if (section == TGStarsSectionGifts){
		if (self.giftsLoaded && !self.gifts.count)
			return @"Gifts friends send you appear here.";
		return nil;
	}
	if (section == TGStarsSectionGiftTools)
		return @"Sending a gift spends stars from the balance above.";
	if (section == TGStarsSectionMore)
		return @"Star packs are listed for reference. Stars are bought outside this client.";
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	NSString *comment = [self commentForSection:section];
	if (!comment.length)
		return section + 1 == TGStarsSectionCount ? 8 : 1;
	return TGStarsCommentHeight(comment, tableView.bounds.size.width ?: 320);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	return TGStarsCommentViewWithText([self commentForSection:section],
			tableView.bounds.size.width ?: 320);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == TGStarsSectionTransactions && self.transactions.count)
		return 51;
	if (indexPath.section == TGStarsSectionGifts && self.gifts.count)
		return 51;
	if (indexPath.section == TGStarsSectionSubscriptions)
		return 51;
	return 44;
}

#pragma mark - cells

- (UITableViewCell *)plainCellInTable:(UITableView *)tableView
								style:(UITableViewCellStyle)style
							  reuseId:(NSString *)reuseId
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:reuseId];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.imageView.image = nil;
	cell.detailTextLabel.text = @"";
	cell.textLabel.textAlignment = UITextAlignmentLeft;
	cell.textLabel.shadowColor = nil;
	cell.textLabel.shadowOffset = CGSizeZero;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.font = [UIFont systemFontOfSize:16];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = TGStarsRGB(0x888888);
	[[TGTheme shared] styleCell:cell];
	return cell;
}

- (UITableViewCell *)balanceCellInTable:(UITableView *)tableView {
	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleValue1
										   reuseId:@"TGStarsBalance"];
	cell.textLabel.text = @"Balance";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	if (self.balanceKnown){
		cell.detailTextLabel.text = [self starsText:self.balance signed:NO];
		cell.detailTextLabel.textColor = [[TGTheme shared] isDark]
				? [[TGTheme shared] cellDetailColour] : TGStarsRGB(0x356596);
	} else if (self.transactionsFailed){
		cell.detailTextLabel.text = @"unavailable";
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	} else {
		cell.detailTextLabel.text = @"checking...";
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	}
	return cell;
}

- (UITableViewCell *)statusCellInTable:(UITableView *)tableView text:(NSString *)text {
	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleDefault
										   reuseId:@"TGStarsStatus"];
	cell.textLabel.text = text;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
	cell.textLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] secondaryTextColour] : TGStarsRGB(0x8694a4);
	if (![[TGTheme shared] isDark]){
		cell.textLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.5f];
		cell.textLabel.shadowOffset = CGSizeMake(0, 1);
	}
	cell.textLabel.textAlignment = UITextAlignmentCenter;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)moreCellInTable:(UITableView *)tableView loading:(BOOL)loading {
	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleDefault
										   reuseId:@"TGStarsMore"];
	cell.textLabel.text = loading ? @"Loading..." : @"Show more";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = loading ? [[TGTheme shared] secondaryTextColour]
									   : TGStarsRGB(0x0779d0);
	cell.selectionStyle = loading ? UITableViewCellSelectionStyleNone
								  : UITableViewCellSelectionStyleBlue;
	return cell;
}

- (UILabel *)amountLabelWithStars:(long long)stars {
	NSString *text = [self starsText:stars signed:YES];
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 90, 20)];
	label.text = text;
	label.font = [UIFont boldSystemFontOfSize:16];
	label.backgroundColor = [UIColor clearColor];
	label.textAlignment = UITextAlignmentRight;
	label.textColor = stars < 0 ? TGStarsRGB(0xee4928) : TGStarsRGB(0x41a903);
	CGSize size = [text sizeWithFont:label.font];
	label.frame = CGRectMake(0, 0, ceilf(size.width) + 2, 20);
	return label;
}

- (UITableViewCell *)transactionCellInTable:(UITableView *)tableView
										row:(NSInteger)row
{
	NSDictionary *transaction = self.transactions[row];
	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleSubtitle
										   reuseId:@"TGStarsTransaction"];
	NSString *name = [self counterpartyForTransaction:transaction];
	cell.textLabel.text = name;
	cell.textLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.text = [self subtitleForTransaction:transaction];

	NSString *type = transaction[@"type"];
	int64_t colourId = [type isKindOfClass:[NSString class]] ? (int64_t)[type hash] : 0;
	if (colourId < 0)
		colourId = -colourId;
	cell.imageView.image = [TGIcons avatarWithInitials:[self initialsForName:name]
												  size:40
											  colourId:colourId];

	cell.accessoryView = [self amountLabelWithStars:
			[transaction[@"stars"] longLongValue]];
	return cell;
}

- (UITableViewCell *)giftCellInTable:(UITableView *)tableView row:(NSInteger)row {
	NSDictionary *gift = self.gifts[row];
	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleSubtitle
										   reuseId:@"TGStarsGift"];
	NSString *title = gift[@"title"];
	if (![title isKindOfClass:[NSString class]] || !title.length)
		title = @"Gift";
	cell.textLabel.text = title;
	cell.textLabel.font = [UIFont systemFontOfSize:16];

	NSString *sender = [self senderNameForGift:gift];
	if (!sender.length)
		sender = @"Anonymous";
	NSString *date = [self dateTextFromValue:gift[@"date"]];
	cell.detailTextLabel.text = date.length
			? [NSString stringWithFormat:@"from %@ · %@", sender, date]
			: [NSString stringWithFormat:@"from %@", sender];

	cell.imageView.image = [TGIcons avatarWithInitials:@"★"
												  size:40
											  colourId:[gift[@"isUnique"] boolValue] ? 4 : 2];

	long long stars = [gift[@"starCount"] longLongValue];
	if (stars > 0)
		cell.accessoryView = [self amountLabelWithStars:stars];
	return cell;
}

- (NSString *)periodTextForSeconds:(long long)seconds {
	if (seconds >= 31000000)
		return @"year";
	if (seconds >= 2500000)
		return @"month";
	if (seconds >= 600000)
		return @"week";
	if (seconds >= 86400)
		return [NSString stringWithFormat:@"%lld days", seconds / 86400];
	return @"period";
}

- (NSString *)titleForSubscription:(NSDictionary *)subscription {
	NSString *title = subscription[@"title"];
	if ([title isKindOfClass:[NSString class]] && title.length)
		return title;
	int64_t chatId = [subscription[@"chatId"] longLongValue];
	if (chatId){
		NSString *chatTitle = [[TGClient shared] cachedTitleForChatId:chatId];
		if (chatTitle.length)
			return chatTitle;
	}
	return @"Subscription";
}

- (NSString *)subtitleForSubscription:(NSDictionary *)subscription {
	NSString *date = [self dateTextFromValue:subscription[@"expirationDate"]];
	if ([subscription[@"isCanceled"] boolValue])
		return date.length ? [NSString stringWithFormat:@"Ends %@", date] : @"Canceled";
	if ([subscription[@"isExpiring"] boolValue])
		return date.length ? [NSString stringWithFormat:@"Expires %@", date] : @"Expiring";
	return date.length ? [NSString stringWithFormat:@"Renews %@", date] : @"Active";
}

- (UITableViewCell *)subscriptionCellInTable:(UITableView *)tableView row:(NSInteger)row {
	NSDictionary *subscription = self.subscriptions[row];
	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleSubtitle
										   reuseId:@"TGStarsSubscription"];
	NSString *title = [self titleForSubscription:subscription];
	cell.textLabel.text = title;
	cell.textLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.text = [self subtitleForSubscription:subscription];
	if ([subscription[@"isCanceled"] boolValue] || [subscription[@"isExpiring"] boolValue])
		cell.detailTextLabel.textColor = TGStarsRGB(0xee4928);

	int64_t chatId = [subscription[@"chatId"] longLongValue];
	if (chatId < 0)
		chatId = -chatId;
	cell.imageView.image = [TGIcons avatarWithInitials:[self initialsForName:title]
												  size:40
											  colourId:chatId];

	long long stars = [subscription[@"stars"] longLongValue];
	if (stars > 0){
		UILabel *label = [[UILabel alloc] init];
		label.text = [self starsText:stars signed:NO];
		label.font = [UIFont boldSystemFontOfSize:16];
		label.backgroundColor = [UIColor clearColor];
		label.textAlignment = UITextAlignmentRight;
		label.textColor = [[TGTheme shared] secondaryTextColour];
		CGSize size = [label.text sizeWithFont:label.font];
		label.frame = CGRectMake(0, 0, ceilf(size.width) + 2, 20);
		cell.accessoryView = label;
	}
	return cell;
}

- (NSString *)menuTitleAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == TGStarsSectionGiftTools){
		switch (indexPath.row){
			case TGStarsGiftToolCatalogue: return @"Gift Catalogue";
			case TGStarsGiftToolCollections: return @"My Collections";
			case TGStarsGiftToolSettings: return @"Who Can Gift Me";
			default: return @"Gifts on a Channel";
		}
	}
	switch (indexPath.row){
		case TGStarsMoreStarPacks: return @"Star Packs";
		case TGStarsMoreIncoming: return @"Incoming Payments";
		case TGStarsMoreOutgoing: return @"Outgoing Payments";
		case TGStarsMoreInvoice: return @"Open an Invoice";
		case TGStarsMorePaidMessages: return @"Charge for Messages";
		default: return @"Clear Saved Payment Info";
	}
}

- (UITableViewCell *)menuCellInTable:(UITableView *)tableView
						 atIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleValue1
										   reuseId:@"TGStarsMenu"];
	cell.textLabel.text = [self menuTitleAtIndexPath:indexPath];
	BOOL destructive = indexPath.section == TGStarsSectionMore &&
			indexPath.row == TGStarsMoreClearPaymentInfo;
	cell.textLabel.textColor = destructive ? TGStarsRGB(0xd12b1f)
										   : [[TGTheme shared] primaryTextColour];
	cell.accessoryType = destructive ? UITableViewCellAccessoryNone
									 : UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.section == TGStarsSectionSubscriptions)
		return [self subscriptionCellInTable:tableView row:indexPath.row];

	if (indexPath.section == TGStarsSectionBalance)
		return [self balanceCellInTable:tableView];

	if (indexPath.section == TGStarsSectionTransactions){
		if (!self.transactions.count){
			if (!self.transactionsLoaded)
				return [self statusCellInTable:tableView text:@"Loading transactions..."];
			if (self.transactionsFailed)
				return [self statusCellInTable:tableView text:@"History Unavailable"];
			return [self statusCellInTable:tableView text:@"No Transactions Yet"];
		}
		if (indexPath.row >= (NSInteger)self.transactions.count)
			return [self moreCellInTable:tableView loading:self.transactionsLoading];
		return [self transactionCellInTable:tableView row:indexPath.row];
	}

	if (indexPath.section == TGStarsSectionGiftTools ||
		indexPath.section == TGStarsSectionMore)
		return [self menuCellInTable:tableView atIndexPath:indexPath];

	if (!self.gifts.count){
		if (!self.giftsLoaded)
			return [self statusCellInTable:tableView text:@"Loading gifts..."];
		return [self statusCellInTable:tableView text:@"No Gifts Yet"];
	}
	if (indexPath.row >= (NSInteger)self.gifts.count)
		return [self moreCellInTable:tableView loading:self.giftsLoading];
	return [self giftCellInTable:tableView row:indexPath.row];
}

#pragma mark - taps

- (NSArray *)pairsForTransaction:(NSDictionary *)transaction {
	NSMutableArray *pairs = [NSMutableArray array];
	long long stars = [transaction[@"stars"] longLongValue];
	[pairs addObject:@[stars < 0 ? @"Spent" : @"Earned",
			[self starsText:stars < 0 ? -stars : stars signed:NO]]];

	NSString *date = [self dateTextFromValue:transaction[@"date"]];
	if (date.length)
		[pairs addObject:@[@"Date", date]];

	NSString *type = transaction[@"type"];
	if ([type isKindOfClass:[NSString class]] && type.length)
		[pairs addObject:@[@"Type", type]];

	if ([self transactionIsRefund:transaction])
		[pairs addObject:@[@"Refunded", @"Yes"]];

	NSString *transactionId = transaction[@"id"];
	if (![transactionId isKindOfClass:[NSString class]])
		transactionId = nil;
	if (transactionId.length)
		[pairs addObject:@[@"ID", transactionId]];

	return pairs;
}

- (NSDictionary *)refundActionForChargeId:(NSString *)transactionId
								partnerId:(int64_t)partnerId
									stars:(long long)stars
							   controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	NSString *partner = [[TGClient shared] nameForUserId:partnerId];
	NSString *amount = [self starsText:stars signed:NO];
	return TGStarsAction(@"Refund This Payment", nil, YES, ^{
			typeof(self) strongSelf = weakSelf;
			TGStarsDetailViewController *strongController = weakController;
			if (!strongSelf || !strongController)
				return;
			[strongSelf confirmWithTitle:@"Refund Payment"
								 message:[NSString stringWithFormat:@"Return %@ to %@?",
										 amount, partner.length ? partner : @"the payer"]
								  action:@"Refund"
								   block:^{
				typeof(self) innerSelf = weakSelf;
				if (!innerSelf)
					return;
				strongController.busy = YES;
				[strongController.tableView reloadData];
				[[TGClient shared] refundStarPaymentWithChargeId:transactionId
													    toUserId:partnerId
													  completion:^(BOOL ok)
				{
					typeof(self) doneSelf = weakSelf;
					if (doneSelf)
						[doneSelf finishAction:strongController
									   success:ok
									   failure:@"This payment could not be refunded."];
				}];
			}];
	});
}

- (void)pushTransactionDetails:(NSDictionary *)transaction {
	long long stars = [transaction[@"stars"] longLongValue];

	NSString *transactionId = transaction[@"id"];
	if (![transactionId isKindOfClass:[NSString class]])
		transactionId = nil;

	NSString *title = [self counterpartyForTransaction:transaction];
	NSString *comment = transaction[@"description"];
	if (![comment isKindOfClass:[NSString class]] || !comment.length)
		comment = nil;

	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:title
														 pairs:[self pairsForTransaction:transaction]
													   comment:comment];

	int64_t partnerId = [transaction[@"userId"] longLongValue];
	if (stars > 0 && partnerId && transactionId.length &&
		![self transactionIsRefund:transaction])
	{
		controller.actions = @[[self refundActionForChargeId:transactionId
												   partnerId:partnerId
													   stars:stars
												  controller:controller]];
		controller.actionsComment = @"Only a payment received by a bot of yours can be refunded.";
	}

	[self.navigationController pushViewController:controller animated:YES];
}

- (void)finishAction:(TGStarsDetailViewController *)controller
			 success:(BOOL)success
			 failure:(NSString *)failureMessage
{
	controller.busy = NO;
	if (!success){
		[controller.tableView reloadData];
		TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Telegram Stars"
														message:failureMessage
											  cancelButtonTitle:@"OK"
												  okButtonTitle:nil
												completionBlock:nil];
		[alert show];
		return;
	}
	if (controller.navigationController == self.navigationController)
		[self.navigationController popToViewController:self animated:YES];
	[self reloadTapped];
}

- (void)confirmWithTitle:(NSString *)title
				 message:(NSString *)message
				  action:(NSString *)actionTitle
				   block:(void (^)(void))block
{
	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:title
													message:message
										  cancelButtonTitle:@"Cancel"
											  okButtonTitle:actionTitle
											completionBlock:^(bool okButtonPressed)
	{
		if (okButtonPressed && block)
			block();
	}];
	[alert show];
}

- (NSDictionary *)giftVisibilityActionForGift:(NSDictionary *)gift
									   giftId:(NSString *)giftId
								   controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	BOOL saved = [gift[@"isSaved"] boolValue];
	return TGStarsAction(@"On My Profile", saved ? @"Shown" : @"Hidden", NO, ^{
		typeof(self) strongSelf = weakSelf;
		TGStarsDetailViewController *strongController = weakController;
		if (!strongSelf || !strongController)
			return;
		[[TGClient shared] setReceivedGift:giftId saved:!saved];
		[strongSelf refreshGiftDetail:strongController giftId:giftId fallback:gift];
	});
}

- (NSDictionary *)giftPinActionForGift:(NSDictionary *)gift
								giftId:(NSString *)giftId
							controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	BOOL pinned = [gift[@"isPinned"] boolValue];
	return TGStarsAction(@"Pinned on Profile", pinned ? @"Yes" : @"No", NO, ^{
		typeof(self) strongSelf = weakSelf;
		TGStarsDetailViewController *strongController = weakController;
		if (!strongSelf || !strongController)
			return;
		[[TGClient shared] setPinnedGiftIds:
				[strongSelf pinnedGiftIdsTogglingGift:giftId pinned:!pinned]];
		[strongSelf refreshGiftDetail:strongController giftId:giftId fallback:gift];
	});
}

- (NSDictionary *)giftCollectionActionForGiftId:(NSString *)giftId {
	__weak typeof(self) weakSelf = self;
	return TGStarsAction(@"Add to a Collection", nil, NO, ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf)
			[strongSelf pushCollectionPickerForGift:giftId];
	});
}

- (NSDictionary *)giftTransferActionForGiftId:(NSString *)giftId
										price:(long long)transferPrice
								   controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	return TGStarsAction(@"Transfer to a Contact",
			transferPrice > 0 ? [self starsText:transferPrice signed:NO] : @"Free", NO, ^{
			typeof(self) strongSelf = weakSelf;
			TGStarsDetailViewController *strongController = weakController;
			if (!strongSelf || !strongController)
				return;
			[strongSelf pickUserWithTitle:@"Transfer To"
								  handler:^(int64_t userId, NSString *name)
			{
				typeof(self) pickSelf = weakSelf;
				if (!pickSelf)
					return;
				[pickSelf confirmWithTitle:@"Transfer Gift"
								   message:transferPrice > 0
										   ? [NSString stringWithFormat:
												   @"Give this gift to %@ for %@?", name,
												   [pickSelf starsText:transferPrice signed:NO]]
										   : [NSString stringWithFormat:
												   @"Give this gift to %@?", name]
									action:@"Transfer"
									 block:^{
					typeof(self) sendSelf = weakSelf;
					if (!sendSelf)
						return;
					[[TGClient shared] transferReceivedGift:giftId
													 toUser:userId
												  starCount:transferPrice
												 completion:^(BOOL ok)
					{
						typeof(self) doneSelf = weakSelf;
						if (doneSelf)
							[doneSelf finishSimpleAction:ok
												 failure:@"The gift could not be transferred."];
					}];
				}];
			}];
	});
}

- (NSDictionary *)giftConvertActionForGiftId:(NSString *)giftId
									   price:(long long)sell
								  controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	NSString *value = [self starsText:sell signed:NO];
	return TGStarsAction(@"Convert to Stars", value, YES, ^{
			typeof(self) strongSelf = weakSelf;
			TGStarsDetailViewController *strongController = weakController;
			if (!strongSelf || !strongController)
				return;
			[strongSelf confirmWithTitle:@"Convert to Stars"
								 message:[NSString stringWithFormat:
										@"This gift will be removed and %@ added to your balance.",
										value]
								  action:@"Convert"
								   block:^{
				typeof(self) innerSelf = weakSelf;
				if (!innerSelf)
					return;
				strongController.busy = YES;
				[strongController.tableView reloadData];
				[[TGClient shared] sellReceivedGift:giftId completion:^(BOOL ok){
					typeof(self) doneSelf = weakSelf;
					if (!doneSelf)
						return;
					[doneSelf finishAction:strongController
								   success:ok
								   failure:@"This gift can no longer be converted."];
				}];
			}];
	});
}

- (NSDictionary *)giftUpgradeActionForGiftId:(NSString *)giftId
									   price:(long long)upgrade
								  controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	NSString *value = upgrade > 0 ? [self starsText:upgrade signed:NO] : @"Free";
	return TGStarsAction(@"Upgrade to Unique", value, NO, ^{
			typeof(self) strongSelf = weakSelf;
			TGStarsDetailViewController *strongController = weakController;
			if (!strongSelf || !strongController)
				return;
			[strongSelf confirmWithTitle:@"Upgrade Gift"
								 message:upgrade > 0
										? [NSString stringWithFormat:
												@"Turn this gift into a unique collectible for %@?", value]
										: @"Turn this gift into a unique collectible?"
								  action:@"Upgrade"
								   block:^{
				strongController.busy = YES;
				[strongController.tableView reloadData];
				[[TGClient shared] upgradeReceivedGift:giftId
								   keepOriginalDetails:YES
											 starCount:upgrade
											completion:^(NSDictionary *upgraded)
				{
					typeof(self) innerSelf = weakSelf;
					if (!innerSelf)
						return;
					[innerSelf finishAction:strongController
									success:[upgraded isKindOfClass:[NSDictionary class]]
									failure:@"The upgrade could not be completed."];
				}];
			}];
	});
}

- (NSDictionary *)giftResalePriceActionForGiftId:(NSString *)giftId
										   price:(long long)resale
									  controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	return TGStarsAction(resale > 0 ? @"Change Sale Price" : @"Sell This Gift",
			resale > 0 ? [self starsText:resale signed:NO] : nil, NO, ^{
		typeof(self) strongSelf = weakSelf;
		TGStarsDetailViewController *strongController = weakController;
		if (!strongSelf || !strongController)
			return;
		[strongSelf askResalePriceForGift:giftId controller:strongController];
	});
}

- (NSDictionary *)giftRemoveFromSaleActionForGiftId:(NSString *)giftId
										 controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	return TGStarsAction(@"Remove From Sale", nil, YES, ^{
				typeof(self) strongSelf = weakSelf;
				TGStarsDetailViewController *strongController = weakController;
				if (!strongSelf || !strongController)
					return;
				strongController.busy = YES;
				[strongController.tableView reloadData];
				[[TGClient shared] setResalePrice:0
								  forReceivedGift:giftId
									   completion:^(BOOL ok)
				{
					typeof(self) innerSelf = weakSelf;
					if (!innerSelf)
						return;
					[innerSelf finishAction:strongController
									success:ok
									failure:@"The listing could not be removed."];
				}];
	});
}

- (NSArray *)giftActionsFor:(NSDictionary *)gift
				 controller:(TGStarsDetailViewController *)controller
{
	NSString *giftId = gift[@"giftId"];
	if (![giftId isKindOfClass:[NSString class]] || !giftId.length)
		return nil;

	NSMutableArray *actions = [NSMutableArray array];

	if ([gift[@"tgChannelGift"] boolValue])
		return actions;

	[actions addObject:[self giftVisibilityActionForGift:gift
												  giftId:giftId
											  controller:controller]];
	[actions addObject:[self giftPinActionForGift:gift
										   giftId:giftId
									   controller:controller]];
	[actions addObject:[self giftCollectionActionForGiftId:giftId]];

	if ([gift[@"isUnique"] boolValue] && [gift[@"canTransfer"] boolValue]){
		[actions addObject:[self giftTransferActionForGiftId:giftId
													   price:[gift[@"transferStarCount"] longLongValue]
												  controller:controller]];
	}

	long long sell = [gift[@"sellStarCount"] longLongValue];
	if (sell > 0 && ![gift[@"isUnique"] boolValue]){
		[actions addObject:[self giftConvertActionForGiftId:giftId
													  price:sell
												 controller:controller]];
	}

	long long upgrade = [gift[@"upgradeStarCount"] longLongValue];
	if ([gift[@"canUpgrade"] boolValue] && ![gift[@"isUnique"] boolValue]){
		[actions addObject:[self giftUpgradeActionForGiftId:giftId
													  price:upgrade
												 controller:controller]];
	}

	if ([gift[@"isUnique"] boolValue]){
		long long resale = [gift[@"resaleStarCount"] longLongValue];
		[actions addObject:[self giftResalePriceActionForGiftId:giftId
														  price:resale
													 controller:controller]];
		if (resale > 0){
			[actions addObject:[self giftRemoveFromSaleActionForGiftId:giftId
															controller:controller]];
		}
	}

	return actions;
}

- (void)askResalePriceForGift:(NSString *)giftId
				   controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	__block TGAlertView *alert = nil;
	alert = [[TGAlertView alloc] initWithTitle:@"Sale Price"
									   message:@"How many stars should this gift cost?"
							 cancelButtonTitle:@"Cancel"
								 okButtonTitle:@"Set"
							   completionBlock:^(bool okButtonPressed)
	{
		typeof(self) strongSelf = weakSelf;
		TGStarsDetailViewController *strongController = weakController;
		TGAlertView *strongAlert = alert;
		alert = nil;
		if (!okButtonPressed || !strongSelf || !strongController || !strongAlert)
			return;
		NSString *text = [[strongAlert textFieldAtIndex:0] text];
		long long price = [text longLongValue];
		if (price <= 0)
			return;
		strongController.busy = YES;
		[strongController.tableView reloadData];
		[[TGClient shared] setResalePrice:price
						  forReceivedGift:giftId
							   completion:^(BOOL ok)
		{
			typeof(self) innerSelf = weakSelf;
			if (!innerSelf)
				return;
			[innerSelf finishAction:strongController
							success:ok
							failure:@"The price could not be set."];
		}];
	}];
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	UITextField *field = [alert textFieldAtIndex:0];
	field.keyboardType = UIKeyboardTypeNumberPad;
	field.placeholder = @"Stars";
	[alert show];
}

- (NSArray *)pairsForSubscription:(NSDictionary *)subscription {
	NSMutableArray *pairs = [NSMutableArray array];
	long long stars = [subscription[@"stars"] longLongValue];
	long long period = [subscription[@"period"] longLongValue];
	if (stars > 0){
		[pairs addObject:@[@"Price", [self starsText:stars signed:NO]]];
		if (period > 0)
			[pairs addObject:@[@"Billed", [NSString stringWithFormat:@"every %@",
					[self periodTextForSeconds:period]]]];
	}

	NSString *date = [self dateTextFromValue:subscription[@"expirationDate"]];
	if (date.length)
		[pairs addObject:@[[subscription[@"isCanceled"] boolValue] ? @"Ends" : @"Next Charge",
				date]];

	NSString *kind = subscription[@"kind"];
	if ([kind isKindOfClass:[NSString class]] && kind.length)
		[pairs addObject:@[@"Type", [kind isEqualToString:@"bot"] ? @"Bot" : @"Channel"]];

	[pairs addObject:@[@"Status", [subscription[@"isCanceled"] boolValue] ? @"Canceled"
			: ([subscription[@"isExpiring"] boolValue] ? @"Expiring" : @"Active")]];

	return pairs;
}

- (NSDictionary *)subscriptionRejoinActionForId:(NSString *)subscriptionId
									 controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	return TGStarsAction(@"Rejoin Channel", nil, NO, ^{
				typeof(self) strongSelf = weakSelf;
				TGStarsDetailViewController *strongController = weakController;
				if (!strongSelf || !strongController)
					return;
				strongController.busy = YES;
				[strongController.tableView reloadData];
				[[TGClient shared] reuseStarSubscription:subscriptionId
											  completion:^(BOOL ok)
				{
					typeof(self) innerSelf = weakSelf;
					if (!innerSelf)
						return;
					[innerSelf finishAction:strongController
									success:ok
									failure:@"The channel could not be rejoined."];
				}];
	});
}

- (NSDictionary *)subscriptionToggleActionForId:(NSString *)subscriptionId
									   canceled:(BOOL)canceled
									 controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	return TGStarsAction(
			canceled ? @"Renew Subscription" : @"Cancel Subscription",
			nil, !canceled, ^{
			typeof(self) strongSelf = weakSelf;
			TGStarsDetailViewController *strongController = weakController;
			if (!strongSelf || !strongController)
				return;
			void (^apply)(void) = ^{
				strongController.busy = YES;
				[strongController.tableView reloadData];
				[[TGClient shared] setStarSubscription:subscriptionId
											  canceled:!canceled
											completion:^(BOOL ok)
				{
					typeof(self) innerSelf = weakSelf;
					if (!innerSelf)
						return;
					[innerSelf finishAction:strongController
									success:ok
									failure:@"The subscription could not be changed."];
				}];
			};
			if (canceled){
				apply();
				return;
			}
			[strongSelf confirmWithTitle:@"Cancel Subscription"
								 message:@"Stars will stop being charged. Access stays until the paid period ends."
								  action:@"Cancel Subscription"
								   block:apply];
	});
}

- (void)pushSubscriptionDetails:(NSDictionary *)subscription {
	NSString *subscriptionId = subscription[@"id"];
	if (![subscriptionId isKindOfClass:[NSString class]])
		subscriptionId = nil;

	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:
					[self titleForSubscription:subscription]
														 pairs:[self pairsForSubscription:subscription]
													   comment:nil];

	if (subscriptionId.length){
		NSMutableArray *actions = [NSMutableArray array];

		if ([subscription[@"canReuse"] boolValue]){
			[actions addObject:[self subscriptionRejoinActionForId:subscriptionId
													   controller:controller]];
		}

		[actions addObject:[self subscriptionToggleActionForId:subscriptionId
													  canceled:[subscription[@"isCanceled"] boolValue]
													controller:controller]];

		controller.actions = actions;
	}

	[self.navigationController pushViewController:controller animated:YES];
}

- (void)configureGiftDetail:(TGStarsDetailViewController *)controller
				   withGift:(NSDictionary *)gift
{
	controller.actions = [self giftActionsFor:gift controller:controller];
	controller.actionsComment = controller.actions.count
			? @"Hidden gifts are visible only to you." : nil;
	[controller.tableView reloadData];
}

- (NSArray *)pinnedGiftIdsTogglingGift:(NSString *)giftId pinned:(BOOL)pinned {
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *gift in self.gifts){
		NSString *otherId = gift[@"giftId"];
		if (![otherId isKindOfClass:[NSString class]] || !otherId.length)
			continue;
		if ([otherId isEqualToString:giftId])
			continue;
		if ([gift[@"isPinned"] boolValue])
			[ids addObject:otherId];
	}
	if (pinned)
		[ids insertObject:giftId atIndex:0];
	return ids;
}

- (void)refreshGiftDetail:(TGStarsDetailViewController *)controller
				   giftId:(NSString *)giftId
				 fallback:(NSDictionary *)fallback
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	[[TGClient shared] receivedGiftWithId:giftId completion:^(NSDictionary *gift){
		typeof(self) strongSelf = weakSelf;
		TGStarsDetailViewController *strongController = weakController;
		if (!strongSelf || !strongController)
			return;
		[strongSelf configureGiftDetail:strongController
							   withGift:[gift isKindOfClass:[NSDictionary class]]
									   ? gift : fallback];
	}];
}

- (void)pushGiftDetails:(NSDictionary *)gift {
	NSMutableArray *pairs = [NSMutableArray array];

	long long stars = [gift[@"starCount"] longLongValue];
	if (stars > 0)
		[pairs addObject:@[@"Value", [self starsText:stars signed:NO]]];

	NSString *sender = [self senderNameForGift:gift];
	[pairs addObject:@[@"From", sender.length ? sender : @"Anonymous"]];

	NSString *date = [self dateTextFromValue:gift[@"date"]];
	if (date.length)
		[pairs addObject:@[@"Date", date]];

	if ([gift[@"isUnique"] boolValue]){
		NSString *name = gift[@"name"];
		if ([name isKindOfClass:[NSString class]] && name.length)
			[pairs addObject:@[@"Unique Gift", name]];
		else
			[pairs addObject:@[@"Unique Gift", @"Yes"]];
		NSNumber *number = gift[@"number"];
		if ([number isKindOfClass:[NSNumber class]] && [number longLongValue])
			[pairs addObject:@[@"Number", [NSString stringWithFormat:@"#%lld",
					[number longLongValue]]]];
	}

	NSString *comment = gift[@"text"];
	if ([comment isKindOfClass:[NSString class]] && comment.length)
		comment = [NSString stringWithFormat:@"“%@”", comment];
	else
		comment = nil;

	NSString *title = gift[@"title"];
	if (![title isKindOfClass:[NSString class]] || !title.length)
		title = @"Gift";

	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:title
														 pairs:pairs
													   comment:comment];
	controller.actions = [self giftActionsFor:gift controller:controller];
	controller.actionsComment = controller.actions.count
			? @"Hidden gifts are visible only to you." : nil;
	[self.navigationController pushViewController:controller animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == TGStarsSectionBalance)
		return;

	if (indexPath.section == TGStarsSectionTransactions){
		if (!self.transactions.count)
			return;
		if (indexPath.row >= (NSInteger)self.transactions.count){
			if (!self.transactionsLoading){
				[self loadMoreTransactions];
				[self.tableView reloadData];
			}
			return;
		}
		[self pushTransactionDetails:self.transactions[indexPath.row]];
		return;
	}

	if (indexPath.section == TGStarsSectionSubscriptions){
		if (indexPath.row < (NSInteger)self.subscriptions.count)
			[self pushSubscriptionDetails:self.subscriptions[indexPath.row]];
		return;
	}

	if (indexPath.section == TGStarsSectionGiftTools){
		switch (indexPath.row){
			case TGStarsGiftToolCatalogue: [self pushGiftCatalogue]; break;
			case TGStarsGiftToolCollections: [self pushGiftCollections]; break;
			case TGStarsGiftToolSettings: [self pushGiftSettings]; break;
			default: [self pushChannelGifts]; break;
		}
		return;
	}

	if (indexPath.section == TGStarsSectionMore){
		switch (indexPath.row){
			case TGStarsMoreStarPacks: [self pushStarPacks]; break;
			case TGStarsMoreIncoming:
				[self pushTransactionsWithDirection:@"incoming" title:@"Incoming Payments"];
				break;
			case TGStarsMoreOutgoing:
				[self pushTransactionsWithDirection:@"outgoing" title:@"Outgoing Payments"];
				break;
			case TGStarsMoreInvoice: [self openInvoiceByName]; break;
			case TGStarsMorePaidMessages: [self pushPaidMessages]; break;
			default: [self clearSavedPaymentInfo]; break;
		}
		return;
	}

	if (!self.gifts.count)
		return;
	if (indexPath.row >= (NSInteger)self.gifts.count){
		if (!self.giftsLoading){
			[self loadMoreGifts];
			[self.tableView reloadData];
		}
		return;
	}
	[self pushGiftDetails:self.gifts[indexPath.row]];
}

#pragma mark - shared helpers

- (UIView *)sheetHostView {
	if (self.navigationController.view)
		return self.navigationController.view;
	return self.view;
}

- (void)showMessage:(NSString *)message {
	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Telegram Stars"
													message:message
										  cancelButtonTitle:@"OK"
											  okButtonTitle:nil
											completionBlock:nil];
	[alert show];
}

- (void)finishSimpleAction:(BOOL)success failure:(NSString *)failureMessage {
	if (!success){
		[self showMessage:failureMessage];
		return;
	}
	[self.navigationController popToViewController:self animated:YES];
	[self reloadTapped];
}

- (void)promptWithTitle:(NSString *)title
				message:(NSString *)message
			placeholder:(NSString *)placeholder
				numeric:(BOOL)numeric
			actionTitle:(NSString *)actionTitle
				handler:(void (^)(NSString *text))handler
{
	__block TGAlertView *alert = nil;
	alert = [[TGAlertView alloc] initWithTitle:title
									   message:message
							 cancelButtonTitle:@"Cancel"
								 okButtonTitle:actionTitle
							   completionBlock:^(bool okButtonPressed)
	{
		TGAlertView *strongAlert = alert;
		alert = nil;
		if (!okButtonPressed || !strongAlert || !handler)
			return;
		NSString *text = [[strongAlert textFieldAtIndex:0] text];
		if (!text.length)
			return;
		handler(text);
	}];
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	UITextField *field = [alert textFieldAtIndex:0];
	if (numeric)
		field.keyboardType = UIKeyboardTypeNumberPad;
	field.placeholder = placeholder;
	[alert show];
}

- (NSString *)nameFromUser:(NSDictionary *)user {
	NSMutableString *name = [NSMutableString string];
	NSString *first = user[@"first_name"];
	NSString *last = user[@"last_name"];
	if ([first isKindOfClass:[NSString class]] && first.length)
		[name appendString:first];
	if ([last isKindOfClass:[NSString class]] && last.length){
		if (name.length)
			[name appendString:@" "];
		[name appendString:last];
	}
	if (name.length)
		return name;
	NSString *username = user[@"username"];
	if ([username isKindOfClass:[NSString class]] && username.length)
		return [NSString stringWithFormat:@"@%@", username];
	return @"User";
}

- (void)pickUserWithTitle:(NSString *)title
				  handler:(void (^)(int64_t userId, NSString *name))handler
{
	TGStarsListViewController *list =
			[[TGStarsListViewController alloc] initWithTitle:title];
	list.loading = YES;
	list.emptyText = @"No Contacts";
	__weak typeof(self) weakSelf = self;
	__weak TGStarsListViewController *weakList = list;
	[self.navigationController pushViewController:list animated:YES];
	[[TGClient shared] searchContacts:@""
								limit:200
						   completion:^(NSArray *users)
	{
		typeof(self) strongSelf = weakSelf;
		TGStarsListViewController *strongList = weakList;
		if (!strongSelf || !strongList)
			return;
		if ([users isKindOfClass:[NSArray class]]){
			for (NSDictionary *user in users){
				if (![user isKindOfClass:[NSDictionary class]])
					continue;
				int64_t userId = [user[@"id"] longLongValue];
				if (!userId)
					continue;
				NSString *name = [strongSelf nameFromUser:user];
				NSString *badge = [TGClient isPremiumUser:user] ? @"Premium" : nil;
				[strongList appendRow:TGStarsRow(name, badge, nil, ^{
					typeof(self) innerSelf = weakSelf;
					if (!innerSelf)
						return;
					[innerSelf.navigationController popViewControllerAnimated:YES];
					if (handler)
						handler(userId, name);
				})];
			}
		}
		[strongList finishLoadingWithMore:NO];
	}];
}

- (void)pickChatWithHandler:(void (^)(int64_t chatId))handler {
	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	__weak typeof(self) weakSelf = self;
	picker.onPicked = ^(int64_t chatId){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf.navigationController popViewControllerAnimated:NO];
		if (handler)
			handler(chatId);
	};
	[self.navigationController pushViewController:picker animated:YES];
}

#pragma mark - star packs

- (NSString *)priceTextForOption:(NSDictionary *)option {
	NSString *currency = option[@"currency"];
	if (![currency isKindOfClass:[NSString class]] || !currency.length)
		return @"";
	return [NSString stringWithFormat:@"%@ %@", currency,
			[self formattedNumber:option[@"amount"]]];
}

- (void)fillList:(TGStarsListViewController *)list withOptions:(NSArray *)options {
	if (![options isKindOfClass:[NSArray class]])
		return;
	for (NSDictionary *option in options){
		if (![option isKindOfClass:[NSDictionary class]])
			continue;
		NSString *title = [self starsText:[option[@"stars"] longLongValue] signed:NO];
		if ([option[@"isAdditional"] boolValue])
			title = [NSString stringWithFormat:@"%@ (extra)", title];
		[list appendRow:TGStarsRow(title, nil, [self priceTextForOption:option], nil)];
	}
}

- (void)pushStarPacksForUser:(int64_t)userId name:(NSString *)name {
	TGStarsListViewController *list = [[TGStarsListViewController alloc]
			initWithTitle:name.length ? name : @"Star Packs"];
	list.loading = YES;
	list.emptyText = @"No Packs Available";
	list.comment = @"These are the packs that may be bought as a gift for this contact.";
	__weak typeof(self) weakSelf = self;
	__weak TGStarsListViewController *weakList = list;
	[self.navigationController pushViewController:list animated:YES];
	[[TGClient shared] starGiftPaymentOptionsForUser:userId
										  completion:^(NSArray *options)
	{
		typeof(self) strongSelf = weakSelf;
		TGStarsListViewController *strongList = weakList;
		if (!strongSelf || !strongList)
			return;
		[strongSelf fillList:strongList withOptions:options];
		[strongList finishLoadingWithMore:NO];
	}];
}

- (void)pushStarPacks {
	TGStarsListViewController *list =
			[[TGStarsListViewController alloc] initWithTitle:@"Star Packs"];
	list.loading = YES;
	list.emptyText = @"No Packs Available";
	list.comment = @"Prices are shown in the smallest unit of each currency. Stars are bought outside this client.";
	__weak typeof(self) weakSelf = self;
	__weak TGStarsListViewController *weakList = list;
	[self.navigationController pushViewController:list animated:YES];
	[[TGClient shared] starPaymentOptionsWithCompletion:^(NSArray *options){
		typeof(self) strongSelf = weakSelf;
		TGStarsListViewController *strongList = weakList;
		if (!strongSelf || !strongList)
			return;
		[strongSelf fillList:strongList withOptions:options];
		[strongList appendRow:TGStarsRow(@"Packs for a Contact", nil, nil, ^{
			typeof(self) innerSelf = weakSelf;
			if (!innerSelf)
				return;
			[innerSelf pickUserWithTitle:@"Gift Stars To"
								 handler:^(int64_t userId, NSString *name)
			{
				typeof(self) pickSelf = weakSelf;
				if (pickSelf)
					[pickSelf pushStarPacksForUser:userId name:name];
			}];
		})];
		[strongList finishLoadingWithMore:NO];
	}];
}

#pragma mark - filtered transactions

- (void)loadTransactionsInto:(TGStarsListViewController *)list
				   direction:(NSString *)direction
					  offset:(NSString *)offset
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsListViewController *weakList = list;
	[[TGClient shared] starTransactionsWithDirection:direction
											  offset:offset
											   limit:kStarsPageSize
										  completion:^(NSArray *transactions, NSString *nextOffset)
	{
		typeof(self) strongSelf = weakSelf;
		TGStarsListViewController *strongList = weakList;
		if (!strongSelf || !strongList)
			return;
		if (![transactions isKindOfClass:[NSArray class]]){
			strongList.emptyText = @"History Unavailable";
			[strongList finishLoadingWithMore:NO];
			return;
		}
		for (NSDictionary *transaction in transactions){
			if (![transaction isKindOfClass:[NSDictionary class]])
				continue;
			NSString *date = [strongSelf subtitleForTransaction:transaction];
			NSString *amount = [strongSelf starsText:
					[transaction[@"stars"] longLongValue] signed:YES];
			NSString *subtitle = date.length
					? [NSString stringWithFormat:@"%@ · %@", amount, date] : amount;
			[strongList appendRow:TGStarsRow(
					[strongSelf counterpartyForTransaction:transaction],
					subtitle, nil, ^{
				typeof(self) innerSelf = weakSelf;
				if (innerSelf)
					[innerSelf pushTransactionDetails:transaction];
			})];
		}
		NSString *next = [nextOffset isKindOfClass:[NSString class]] ? nextOffset : @"";
		BOOL more = next.length > 0 && transactions.count > 0;
		if (more){
			strongList.loadMoreBlock = ^{
				typeof(self) innerSelf = weakSelf;
				TGStarsListViewController *innerList = weakList;
				if (innerSelf && innerList)
					[innerSelf loadTransactionsInto:innerList
										  direction:direction
											 offset:next];
			};
		} else {
			strongList.loadMoreBlock = nil;
		}
		[strongList finishLoadingWithMore:more];
	}];
}

- (void)pushTransactionsWithDirection:(NSString *)direction title:(NSString *)title {
	TGStarsListViewController *list =
			[[TGStarsListViewController alloc] initWithTitle:title];
	list.loading = YES;
	list.emptyText = @"No Payments";
	[self.navigationController pushViewController:list animated:YES];
	[self loadTransactionsInto:list direction:direction offset:@""];
}

#pragma mark - gift catalogue

- (void)pushUpgradePreviewForGiftId:(long long)giftId title:(NSString *)title {
	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:@"Upgrade Preview"
														 pairs:@[@[@"Loading", @"..."]]
													   comment:nil];
	__weak TGStarsDetailViewController *weakController = controller;
	__weak typeof(self) weakSelf = self;
	[self.navigationController pushViewController:controller animated:YES];
	[[TGClient shared] giftUpgradePreviewForGiftId:giftId
										completion:^(NSDictionary *preview)
	{
		typeof(self) strongSelf = weakSelf;
		TGStarsDetailViewController *strongController = weakController;
		if (!strongSelf || !strongController)
			return;
		if (![preview isKindOfClass:[NSDictionary class]]){
			strongController.pairs = @[@[@"Preview", @"Unavailable"]];
			[strongController.tableView reloadData];
			return;
		}
		NSMutableArray *pairs = [NSMutableArray array];
		[pairs addObject:@[@"Gift", title.length ? title : @"Gift"]];
		long long stars = [preview[@"starCount"] longLongValue];
		if (stars > 0)
			[pairs addObject:@[@"Upgrade Price", [strongSelf starsText:stars signed:NO]]];
		NSArray *keys = @[@"models", @"symbols", @"backdrops"];
		NSArray *labels = @[@"Models", @"Symbols", @"Backdrops"];
		for (NSUInteger index = 0; index < keys.count; index++){
			NSArray *values = preview[keys[index]];
			NSInteger count = [values isKindOfClass:[NSArray class]]
					? (NSInteger)values.count : 0;
			[pairs addObject:@[labels[index],
					[NSString stringWithFormat:@"%d", (int)count]]];
		}
		strongController.pairs = pairs;
		strongController.comment = @"An upgraded gift picks one model, symbol and backdrop at random.";
		[strongController.tableView reloadData];
	}];
}

- (void)pushResaleListingsForGiftId:(long long)giftId title:(NSString *)title {
	TGStarsListViewController *list =
			[[TGStarsListViewController alloc] initWithTitle:@"Resale"];
	list.loading = YES;
	list.emptyText = @"Nothing on Sale";
	list.comment = @"Buying spends stars from your balance immediately.";
	[self.navigationController pushViewController:list animated:YES];
	[self loadResaleListingsInto:list giftId:giftId offset:@""];
}

- (void)confirmBuyResoldGiftNamed:(NSString *)name price:(long long)price {
	__weak typeof(self) weakSelf = self;
	[self confirmWithTitle:@"Buy Gift"
				   message:[NSString stringWithFormat:
						   @"Buy this gift for %@?",
						   [self starsText:price signed:NO]]
					action:@"Buy"
					 block:^{
		typeof(self) buySelf = weakSelf;
		if (!buySelf)
			return;
		[[TGClient shared] buyResoldGiftNamed:name
								 forStarCount:price
								   completion:^(BOOL ok)
		{
			typeof(self) doneSelf = weakSelf;
			if (doneSelf)
				[doneSelf finishSimpleAction:ok
									 failure:@"This gift could not be bought."];
		}];
	}];
}

- (void)loadResaleListingsInto:(TGStarsListViewController *)list
						giftId:(long long)giftId
						offset:(NSString *)offset
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsListViewController *weakList = list;
	[[TGClient shared] giftsForResaleWithGiftId:giftId
										 offset:offset
										  limit:kStarsGiftPageSize
									 completion:^(NSArray *gifts, NSString *nextOffset, NSInteger total)
	{
		typeof(self) strongSelf = weakSelf;
		TGStarsListViewController *strongList = weakList;
		if (!strongSelf || !strongList)
			return;
		if ([gifts isKindOfClass:[NSArray class]]){
			for (NSDictionary *gift in gifts){
				if (![gift isKindOfClass:[NSDictionary class]])
					continue;
				NSString *name = gift[@"name"];
				if (![name isKindOfClass:[NSString class]] || !name.length)
					continue;
				long long price = [gift[@"resaleStarCount"] longLongValue];
				NSNumber *number = gift[@"number"];
				NSString *rowTitle = [number isKindOfClass:[NSNumber class]]
						? [NSString stringWithFormat:@"#%lld", [number longLongValue]]
						: name;
				[strongList appendRow:TGStarsRow(rowTitle, nil,
						[strongSelf starsText:price signed:NO], ^{
					typeof(self) innerSelf = weakSelf;
					if (!innerSelf)
						return;
					[innerSelf confirmBuyResoldGiftNamed:name price:price];
				})];
			}
		}
		NSString *next = [nextOffset isKindOfClass:[NSString class]] ? nextOffset : @"";
		BOOL more = next.length > 0 && strongList.rows.count < (NSUInteger)total;
		if (more){
			strongList.loadMoreBlock = ^{
				typeof(self) innerSelf = weakSelf;
				TGStarsListViewController *innerList = weakList;
				if (innerSelf && innerList)
					[innerSelf loadResaleListingsInto:innerList giftId:giftId offset:next];
			};
		} else {
			strongList.loadMoreBlock = nil;
		}
		[strongList finishLoadingWithMore:more];
	}];
}

- (void)sendCatalogueGift:(NSDictionary *)gift
				   toUser:(int64_t)userId
					 name:(NSString *)name
{
	long long giftId = [gift[@"id"] longLongValue];
	long long price = [gift[@"starCount"] longLongValue];
	NSString *title = gift[@"title"];
	__weak typeof(self) weakSelf = self;
	[self confirmWithTitle:@"Send Gift"
				   message:[NSString stringWithFormat:@"Send %@ to %@ for %@?",
						   [title isKindOfClass:[NSString class]] && title.length
								   ? title : @"this gift",
						   name.length ? name : @"this contact",
						   [self starsText:price signed:NO]]
					action:@"Send"
					 block:^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[[TGClient shared] sendGiftWithId:giftId
								   toUser:userId
									 text:@""
								isPrivate:NO
							payForUpgrade:NO
							   completion:^(BOOL ok)
		{
			typeof(self) doneSelf = weakSelf;
			if (doneSelf)
				[doneSelf finishSimpleAction:ok
									 failure:@"The gift could not be sent."];
		}];
	}];
}

- (void)sendCatalogueGift:(NSDictionary *)gift toChat:(int64_t)chatId {
	long long giftId = [gift[@"id"] longLongValue];
	long long price = [gift[@"starCount"] longLongValue];
	NSString *chatTitle = [[TGClient shared] cachedTitleForChatId:chatId];
	__weak typeof(self) weakSelf = self;
	[self confirmWithTitle:@"Send Gift"
				   message:[NSString stringWithFormat:@"Send this gift to %@ for %@?",
						   chatTitle.length ? chatTitle : @"this chat",
						   [self starsText:price signed:NO]]
					action:@"Send"
					 block:^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[[TGClient shared] sendGiftWithId:giftId
								   toChat:chatId
									 text:@""
								isPrivate:NO
							payForUpgrade:NO
							   completion:^(BOOL ok)
		{
			typeof(self) doneSelf = weakSelf;
			if (doneSelf)
				[doneSelf finishSimpleAction:ok
									 failure:@"The gift could not be sent."];
		}];
	}];
}

- (NSArray *)pairsForCatalogueGift:(NSDictionary *)gift {
	NSMutableArray *pairs = [NSMutableArray array];
	[pairs addObject:@[@"Price", [self starsText:
			[gift[@"starCount"] longLongValue] signed:NO]]];
	long long upgrade = [gift[@"upgradeStarCount"] longLongValue];
	if (upgrade > 0)
		[pairs addObject:@[@"Upgrade", [self starsText:upgrade signed:NO]]];
	if ([gift[@"isPremium"] boolValue])
		[pairs addObject:@[@"Limited", @"Yes"]];
	NSInteger resaleCount = [gift[@"resaleCount"] integerValue];
	if (resaleCount > 0){
		[pairs addObject:@[@"On Resale", [NSString stringWithFormat:@"%d", (int)resaleCount]]];
		long long minResale = [gift[@"minResaleStarCount"] longLongValue];
		if (minResale > 0)
			[pairs addObject:@[@"From", [self starsText:minResale signed:NO]]];
	}

	return pairs;
}

- (NSDictionary *)catalogueSendToContactActionForGift:(NSDictionary *)gift {
	__weak typeof(self) weakSelf = self;
	return TGStarsAction(@"Send to a Contact", nil, NO, ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf pickUserWithTitle:@"Send Gift To"
							  handler:^(int64_t userId, NSString *name)
		{
			typeof(self) innerSelf = weakSelf;
			if (innerSelf)
				[innerSelf sendCatalogueGift:gift toUser:userId name:name];
		}];
	});
}

- (NSDictionary *)catalogueSendToChannelActionForGift:(NSDictionary *)gift {
	__weak typeof(self) weakSelf = self;
	return TGStarsAction(@"Send to a Channel", nil, NO, ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf pickChatWithHandler:^(int64_t chatId){
			typeof(self) innerSelf = weakSelf;
			if (innerSelf)
				[innerSelf sendCatalogueGift:gift toChat:chatId];
		}];
	});
}

- (NSDictionary *)catalogueUpgradePreviewActionForGiftId:(long long)giftId
												   title:(NSString *)title
{
	__weak typeof(self) weakSelf = self;
	return TGStarsAction(@"Upgrade Preview", nil, NO, ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf)
			[strongSelf pushUpgradePreviewForGiftId:giftId title:title];
	});
}

- (NSDictionary *)catalogueResaleActionForGiftId:(long long)giftId
										   title:(NSString *)title
										   count:(NSInteger)resaleCount
{
	__weak typeof(self) weakSelf = self;
	return TGStarsAction(@"Buy From Resale",
			[NSString stringWithFormat:@"%d", (int)resaleCount], NO, ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf)
			[strongSelf pushResaleListingsForGiftId:giftId title:title];
	});
}

- (void)pushCatalogueGift:(NSDictionary *)gift {
	NSString *title = gift[@"title"];
	if (![title isKindOfClass:[NSString class]] || !title.length)
		title = @"Gift";
	long long giftId = [gift[@"id"] longLongValue];
	long long upgrade = [gift[@"upgradeStarCount"] longLongValue];
	NSInteger resaleCount = [gift[@"resaleCount"] integerValue];

	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:title
														 pairs:[self pairsForCatalogueGift:gift]
													   comment:nil];
	NSMutableArray *actions = [NSMutableArray array];

	[actions addObject:[self catalogueSendToContactActionForGift:gift]];
	[actions addObject:[self catalogueSendToChannelActionForGift:gift]];

	if (upgrade > 0)
		[actions addObject:[self catalogueUpgradePreviewActionForGiftId:giftId title:title]];

	if (resaleCount > 0){
		[actions addObject:[self catalogueResaleActionForGiftId:giftId
														  title:title
														  count:resaleCount]];
	}

	controller.actions = actions;
	[self.navigationController pushViewController:controller animated:YES];
}

- (void)pushGiftCatalogue {
	TGStarsListViewController *list =
			[[TGStarsListViewController alloc] initWithTitle:@"Gift Catalogue"];
	list.loading = YES;
	list.emptyText = @"No Gifts Available";
	__weak typeof(self) weakSelf = self;
	__weak TGStarsListViewController *weakList = list;
	[self.navigationController pushViewController:list animated:YES];
	[[TGClient shared] availableGiftsWithCompletion:^(NSArray *gifts){
		typeof(self) strongSelf = weakSelf;
		TGStarsListViewController *strongList = weakList;
		if (!strongSelf || !strongList)
			return;
		if ([gifts isKindOfClass:[NSArray class]]){
			for (NSDictionary *gift in gifts){
				if (![gift isKindOfClass:[NSDictionary class]])
					continue;
				NSString *title = gift[@"title"];
				if (![title isKindOfClass:[NSString class]] || !title.length)
					title = @"Gift";
				NSString *subtitle = [strongSelf starsText:
						[gift[@"starCount"] longLongValue] signed:NO];
				NSInteger resaleCount = [gift[@"resaleCount"] integerValue];
				if (resaleCount > 0)
					subtitle = [NSString stringWithFormat:@"%@ · %d on resale",
							subtitle, (int)resaleCount];
				[strongList appendRow:TGStarsRow(title, subtitle, nil, ^{
					typeof(self) innerSelf = weakSelf;
					if (innerSelf)
						[innerSelf pushCatalogueGift:gift];
				})];
			}
		}
		[strongList finishLoadingWithMore:NO];
	}];
}

#pragma mark - gift collections

- (void)pushGiftsOfCollection:(int32_t)collectionId name:(NSString *)name {
	TGStarsListViewController *list =
			[[TGStarsListViewController alloc] initWithTitle:name.length ? name : @"Collection"];
	list.loading = YES;
	list.emptyText = @"No Gifts";
	list.comment = @"Tap a gift to open it or take it out of this collection.";
	int64_t userId = [[TGClient shared].me[@"id"] longLongValue];
	__weak typeof(self) weakSelf = self;
	__weak TGStarsListViewController *weakList = list;
	[self.navigationController pushViewController:list animated:YES];
	[[TGClient shared] receivedGiftsForUser:userId
							   collectionId:collectionId
									 offset:@""
									  limit:kStarsGiftPageSize
								 completion:^(NSArray *gifts, NSString *nextOffset, NSInteger total)
	{
		typeof(self) strongSelf = weakSelf;
		TGStarsListViewController *strongList = weakList;
		if (!strongSelf || !strongList)
			return;
		if ([gifts isKindOfClass:[NSArray class]]){
			for (NSDictionary *gift in gifts){
				if (![gift isKindOfClass:[NSDictionary class]])
					continue;
				NSString *giftId = gift[@"giftId"];
				if (![giftId isKindOfClass:[NSString class]] || !giftId.length)
					continue;
				NSString *title = gift[@"title"];
				if (![title isKindOfClass:[NSString class]] || !title.length)
					title = @"Gift";
				[strongList appendRow:TGStarsRow(title,
						[strongSelf starsText:[gift[@"starCount"] longLongValue] signed:NO],
						nil, ^{
					typeof(self) innerSelf = weakSelf;
					if (innerSelf)
						[innerSelf showSheetForCollectionGift:gift
												 collectionId:collectionId];
				})];
			}
		}
		[strongList finishLoadingWithMore:NO];
	}];
}

- (void)showSheetForCollectionGift:(NSDictionary *)gift collectionId:(int32_t)collectionId {
	NSString *giftId = gift[@"giftId"];
	NSString *title = gift[@"title"];
	__weak typeof(self) weakSelf = self;
	NSArray *actions = @[
			[[TGActionSheetAction alloc] initWithTitle:@"Gift Details" action:@"details"],
			[[TGActionSheetAction alloc] initWithTitle:@"Remove From Collection"
												action:@"remove"
												  type:TGActionSheetActionTypeDestructive],
			[[TGActionSheetAction alloc] initWithTitle:@"Cancel"
												action:@"cancel"
												  type:TGActionSheetActionTypeCancel]];
	self.currentActionSheet = [[TGActionSheet alloc]
			initWithTitle:[title isKindOfClass:[NSString class]] ? title : nil
				  actions:actions
			  actionBlock:^(__unused id target, NSString *action)
	{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.currentActionSheet = nil;
		if ([action isEqualToString:@"details"]){
			[strongSelf pushGiftDetails:gift];
			return;
		}
		if (![action isEqualToString:@"remove"])
			return;
		[[TGClient shared] removeGiftIds:@[giftId]
						  fromCollection:collectionId
							  completion:^(NSDictionary *collection)
		{
			typeof(self) doneSelf = weakSelf;
			if (doneSelf)
				[doneSelf finishSimpleAction:[collection isKindOfClass:[NSDictionary class]]
									 failure:@"The gift could not be removed."];
		}];
	} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

- (void)pushGiftPickerForCollection:(int32_t)collectionId {
	TGStarsListViewController *list =
			[[TGStarsListViewController alloc] initWithTitle:@"Add a Gift"];
	list.emptyText = @"No Gifts Loaded";
	list.comment = @"Only the gifts already loaded on the Stars screen are listed.";
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *gift in self.gifts){
		NSString *giftId = gift[@"giftId"];
		if (![giftId isKindOfClass:[NSString class]] || !giftId.length)
			continue;
		NSString *title = gift[@"title"];
		if (![title isKindOfClass:[NSString class]] || !title.length)
			title = @"Gift";
		[list appendRow:TGStarsRow(title, nil, nil, ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf)
				return;
			[[TGClient shared] addGiftIds:@[giftId]
							 toCollection:collectionId
							   completion:^(NSDictionary *collection)
			{
				typeof(self) doneSelf = weakSelf;
				if (doneSelf)
					[doneSelf finishSimpleAction:[collection isKindOfClass:[NSDictionary class]]
										 failure:@"The gift could not be added."];
			}];
		})];
	}
	[self.navigationController pushViewController:list animated:YES];
}

- (NSDictionary *)collectionOpenActionForId:(int32_t)collectionId name:(NSString *)name {
	__weak typeof(self) weakSelf = self;
	return TGStarsAction(@"Gifts in Collection", nil, NO, ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf)
			[strongSelf pushGiftsOfCollection:collectionId name:name];
	});
}

- (NSDictionary *)collectionAddGiftActionForId:(int32_t)collectionId {
	__weak typeof(self) weakSelf = self;
	return TGStarsAction(@"Add a Gift", nil, NO, ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf)
			[strongSelf pushGiftPickerForCollection:collectionId];
	});
}

- (NSDictionary *)collectionRenameActionForId:(int32_t)collectionId
								   controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	return TGStarsAction(@"Rename", nil, NO, ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf promptWithTitle:@"Rename Collection"
							message:@"Choose a new name."
						placeholder:@"Name"
							numeric:NO
						actionTitle:@"Save"
							handler:^(NSString *text)
		{
			typeof(self) innerSelf = weakSelf;
			TGStarsDetailViewController *strongController = weakController;
			if (!innerSelf || !strongController)
				return;
			strongController.busy = YES;
			[strongController.tableView reloadData];
			[[TGClient shared] renameGiftCollection:collectionId
												 to:text
										 completion:^(NSDictionary *renamed)
			{
				typeof(self) doneSelf = weakSelf;
				if (doneSelf)
					[doneSelf finishAction:strongController
								   success:[renamed isKindOfClass:[NSDictionary class]]
								   failure:@"The collection could not be renamed."];
			}];
		}];
	});
}

- (NSDictionary *)collectionMoveToTopActionForId:(int32_t)collectionId
										     all:(NSArray *)allCollections
{
	__weak typeof(self) weakSelf = self;
	return TGStarsAction(@"Move to Top", nil, NO, ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf)
				return;
			NSMutableArray *ids = [NSMutableArray arrayWithObject:@(collectionId)];
			for (NSDictionary *other in allCollections){
				int32_t otherId = (int32_t)[other[@"id"] intValue];
				if (otherId != collectionId)
					[ids addObject:@(otherId)];
			}
			[[TGClient shared] reorderGiftCollections:ids];
			[strongSelf finishSimpleAction:YES failure:nil];
	});
}

- (NSDictionary *)collectionDeleteActionForId:(int32_t)collectionId {
	__weak typeof(self) weakSelf = self;
	return TGStarsAction(@"Delete Collection", nil, YES, ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf confirmWithTitle:@"Delete Collection"
							 message:@"The collection is removed. The gifts in it are kept."
							  action:@"Delete"
							   block:^{
			typeof(self) innerSelf = weakSelf;
			if (!innerSelf)
				return;
			[[TGClient shared] deleteGiftCollection:collectionId];
			[innerSelf finishSimpleAction:YES failure:nil];
		}];
	});
}

- (void)pushCollection:(NSDictionary *)collection all:(NSArray *)allCollections {
	int32_t collectionId = (int32_t)[collection[@"id"] intValue];
	NSString *name = collection[@"name"];
	if (![name isKindOfClass:[NSString class]] || !name.length)
		name = @"Collection";
	NSInteger count = [collection[@"giftCount"] integerValue];

	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:name
														 pairs:@[@[@"Gifts",
																 [NSString stringWithFormat:@"%d", (int)count]]]
													   comment:nil];
	NSMutableArray *actions = [NSMutableArray array];

	[actions addObject:[self collectionOpenActionForId:collectionId name:name]];
	[actions addObject:[self collectionAddGiftActionForId:collectionId]];
	[actions addObject:[self collectionRenameActionForId:collectionId controller:controller]];

	if (allCollections.count > 1 &&
		![[allCollections objectAtIndex:0] isEqual:collection])
	{
		[actions addObject:[self collectionMoveToTopActionForId:collectionId
															all:allCollections]];
	}

	[actions addObject:[self collectionDeleteActionForId:collectionId]];

	controller.actions = actions;
	[self.navigationController pushViewController:controller animated:YES];
}

- (void)fillCollectionsList:(TGStarsListViewController *)list {
	__weak typeof(self) weakSelf = self;
	__weak TGStarsListViewController *weakList = list;
	[[TGClient shared] giftCollectionsWithCompletion:^(NSArray *collections){
		typeof(self) strongSelf = weakSelf;
		TGStarsListViewController *strongList = weakList;
		if (!strongSelf || !strongList)
			return;
		[strongList.rows removeAllObjects];
		NSArray *all = [collections isKindOfClass:[NSArray class]] ? collections : @[];
		for (NSDictionary *collection in all){
			if (![collection isKindOfClass:[NSDictionary class]])
				continue;
			NSString *name = collection[@"name"];
			if (![name isKindOfClass:[NSString class]] || !name.length)
				name = @"Collection";
			[strongList appendRow:TGStarsRow(name, nil,
					[NSString stringWithFormat:@"%d",
							(int)[collection[@"giftCount"] integerValue]], ^{
				typeof(self) innerSelf = weakSelf;
				if (innerSelf)
					[innerSelf pushCollection:collection all:all];
			})];
		}
		[strongList appendRow:TGStarsRow(@"New Collection", nil, nil, ^{
			typeof(self) innerSelf = weakSelf;
			TGStarsListViewController *innerList = weakList;
			if (!innerSelf || !innerList)
				return;
			[innerSelf promptWithTitle:@"New Collection"
							   message:@"Name this collection."
						   placeholder:@"Name"
							   numeric:NO
						   actionTitle:@"Create"
							   handler:^(NSString *text)
			{
				typeof(self) createSelf = weakSelf;
				TGStarsListViewController *createList = weakList;
				if (!createSelf || !createList)
					return;
				createList.loading = YES;
				[createList.tableView reloadData];
				[[TGClient shared] createGiftCollectionNamed:text
													 giftIds:@[]
												  completion:^(NSDictionary *created)
				{
					typeof(self) doneSelf = weakSelf;
					TGStarsListViewController *doneList = weakList;
					if (!doneSelf || !doneList)
						return;
					if (![created isKindOfClass:[NSDictionary class]]){
						[doneList finishLoadingWithMore:NO];
						[doneSelf showMessage:@"The collection could not be created."];
						return;
					}
					[doneSelf fillCollectionsList:doneList];
				}];
			}];
		})];
		[strongList finishLoadingWithMore:NO];
	}];
}

- (void)pushGiftCollections {
	TGStarsListViewController *list =
			[[TGStarsListViewController alloc] initWithTitle:@"My Collections"];
	list.loading = YES;
	list.emptyText = @"No Collections";
	list.comment = @"Collections group the gifts shown on your profile.";
	[self.navigationController pushViewController:list animated:YES];
	[self fillCollectionsList:list];
}

- (void)pushCollectionPickerForGift:(NSString *)giftId {
	TGStarsListViewController *list =
			[[TGStarsListViewController alloc] initWithTitle:@"Add to Collection"];
	list.loading = YES;
	list.emptyText = @"No Collections";
	__weak typeof(self) weakSelf = self;
	__weak TGStarsListViewController *weakList = list;
	[self.navigationController pushViewController:list animated:YES];
	[[TGClient shared] giftCollectionsWithCompletion:^(NSArray *collections){
		typeof(self) strongSelf = weakSelf;
		TGStarsListViewController *strongList = weakList;
		if (!strongSelf || !strongList)
			return;
		if ([collections isKindOfClass:[NSArray class]]){
			for (NSDictionary *collection in collections){
				if (![collection isKindOfClass:[NSDictionary class]])
					continue;
				int32_t collectionId = (int32_t)[collection[@"id"] intValue];
				NSString *name = collection[@"name"];
				if (![name isKindOfClass:[NSString class]] || !name.length)
					name = @"Collection";
				[strongList appendRow:TGStarsRow(name, nil, nil, ^{
					typeof(self) innerSelf = weakSelf;
					if (!innerSelf)
						return;
					[[TGClient shared] addGiftIds:@[giftId]
									 toCollection:collectionId
									   completion:^(NSDictionary *updated)
					{
						typeof(self) doneSelf = weakSelf;
						if (doneSelf)
							[doneSelf finishSimpleAction:[updated isKindOfClass:[NSDictionary class]]
												 failure:@"The gift could not be added."];
					}];
				})];
			}
		}
		[strongList finishLoadingWithMore:NO];
	}];
}

#pragma mark - gift settings

- (void)configureGiftSettings:(TGStarsDetailViewController *)controller
					 settings:(NSDictionary *)settings
{
	if (![settings isKindOfClass:[NSDictionary class]]){
		controller.pairs = @[@[@"Settings", @"Unavailable"]];
		controller.actions = nil;
		[controller.tableView reloadData];
		return;
	}
	NSArray *keys = @[@"showGiftButton", @"unlimited", @"limited",
			@"upgraded", @"fromChannels", @"premiumSubscription"];
	NSArray *labels = @[@"Show Gift Button", @"Regular Gifts", @"Limited Gifts",
			@"Upgraded Gifts", @"Gifts From Channels", @"Premium Subscriptions"];
	NSMutableArray *actions = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	for (NSUInteger index = 0; index < keys.count; index++){
		NSString *key = keys[index];
		BOOL on = [settings[key] boolValue];
		[actions addObject:TGStarsAction(labels[index], on ? @"On" : @"Off", NO, ^{
			typeof(self) strongSelf = weakSelf;
			TGStarsDetailViewController *strongController = weakController;
			if (!strongSelf || !strongController)
				return;
			NSMutableDictionary *updated =
					[NSMutableDictionary dictionaryWithDictionary:settings];
			updated[key] = @(!on);
			[[TGClient shared] setGiftSettings:updated];
			[[TGClient shared] giftSettingsWithCompletion:^(NSDictionary *fresh){
				typeof(self) innerSelf = weakSelf;
				TGStarsDetailViewController *innerController = weakController;
				if (innerSelf && innerController)
					[innerSelf configureGiftSettings:innerController settings:fresh];
			}];
		})];
	}
	controller.pairs = @[];
	controller.actions = actions;
	controller.actionsComment = @"These choices decide who may send you gifts.";
	[controller.tableView reloadData];
}

- (void)pushGiftSettings {
	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:@"Who Can Gift Me"
														 pairs:@[@[@"Loading", @"..."]]
													   comment:nil];
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	[self.navigationController pushViewController:controller animated:YES];
	[[TGClient shared] giftSettingsWithCompletion:^(NSDictionary *settings){
		typeof(self) strongSelf = weakSelf;
		TGStarsDetailViewController *strongController = weakController;
		if (strongSelf && strongController)
			[strongSelf configureGiftSettings:strongController settings:settings];
	}];
}

#pragma mark - channel gifts

- (void)pushGiftsOfChat:(int64_t)chatId {
	NSString *chatTitle = [[TGClient shared] cachedTitleForChatId:chatId];
	TGStarsListViewController *list = [[TGStarsListViewController alloc]
			initWithTitle:chatTitle.length ? chatTitle : @"Channel Gifts"];
	list.loading = YES;
	list.emptyText = @"No Gifts";
	list.comment = @"Gift notifications reach every administrator of the channel.";
	__weak typeof(self) weakSelf = self;
	__weak TGStarsListViewController *weakList = list;
	[self.navigationController pushViewController:list animated:YES];
	[[TGClient shared] receivedGiftsForChat:chatId
							   collectionId:0
									 offset:@""
									  limit:kStarsGiftPageSize
								 completion:^(NSArray *gifts, NSString *nextOffset, NSInteger total)
	{
		typeof(self) strongSelf = weakSelf;
		TGStarsListViewController *strongList = weakList;
		if (!strongSelf || !strongList)
			return;
		if ([gifts isKindOfClass:[NSArray class]]){
			for (NSDictionary *gift in gifts){
				if (![gift isKindOfClass:[NSDictionary class]])
					continue;
				NSString *title = gift[@"title"];
				if (![title isKindOfClass:[NSString class]] || !title.length)
					title = @"Gift";
				NSString *sender = [strongSelf senderNameForGift:gift];
				NSMutableDictionary *marked =
						[NSMutableDictionary dictionaryWithDictionary:gift];
				marked[@"tgChannelGift"] = @YES;
				[strongList appendRow:TGStarsRow(title,
						sender.length ? [NSString stringWithFormat:@"from %@", sender]
									  : @"from Anonymous",
						nil, ^{
					typeof(self) innerSelf = weakSelf;
					if (innerSelf)
						[innerSelf pushGiftDetails:marked];
				})];
			}
		}
		[strongList appendRow:TGStarsRow(@"Notify Admins of New Gifts", nil, @"On", ^{
			typeof(self) innerSelf = weakSelf;
			if (!innerSelf)
				return;
			[[TGClient shared] setChat:chatId giftNotificationsEnabled:YES];
			[innerSelf showMessage:@"Administrators will be told about new gifts."];
		})];
		[strongList appendRow:TGStarsRow(@"Notify Admins of New Gifts", nil, @"Off", ^{
			typeof(self) innerSelf = weakSelf;
			if (!innerSelf)
				return;
			[[TGClient shared] setChat:chatId giftNotificationsEnabled:NO];
			[innerSelf showMessage:@"Administrators will not be told about new gifts."];
		})];
		[strongList finishLoadingWithMore:NO];
	}];
}

- (void)pushChannelGifts {
	__weak typeof(self) weakSelf = self;
	[self pickChatWithHandler:^(int64_t chatId){
		typeof(self) strongSelf = weakSelf;
		if (strongSelf)
			[strongSelf pushGiftsOfChat:chatId];
	}];
}

#pragma mark - invoices

- (NSArray *)pairsForPaymentForm:(NSDictionary *)form {
	BOOL isStars = [form[@"isStars"] boolValue];

	NSMutableArray *pairs = [NSMutableArray array];
	if (isStars){
		[pairs addObject:@[@"Price", [self starsText:
				[form[@"starCount"] longLongValue] signed:NO]]];
	} else {
		NSString *currency = form[@"currency"];
		if ([currency isKindOfClass:[NSString class]] && currency.length){
			[pairs addObject:@[@"Price", [NSString stringWithFormat:@"%@ %@", currency,
					[self formattedNumber:form[@"totalAmount"]]]]];
		}
	}
	NSArray *parts = form[@"priceParts"];
	if ([parts isKindOfClass:[NSArray class]]){
		for (NSDictionary *part in parts){
			if (![part isKindOfClass:[NSDictionary class]])
				continue;
			NSString *label = part[@"label"];
			if (![label isKindOfClass:[NSString class]] || !label.length)
				continue;
			[pairs addObject:@[label, [self formattedNumber:part[@"amount"]]]];
		}
	}
	int64_t sellerId = [form[@"sellerBotUserId"] longLongValue];
	if (sellerId){
		NSString *seller = [[TGClient shared] nameForUserId:sellerId];
		if (seller.length)
			[pairs addObject:@[@"Seller", seller]];
	}

	return pairs;
}

- (NSDictionary *)payWithStarsActionForForm:(NSDictionary *)form
									  price:(long long)price
								 controller:(TGStarsDetailViewController *)controller
{
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	return TGStarsAction(@"Pay With Stars",
			[self starsText:price signed:NO], NO, ^{
			typeof(self) strongSelf = weakSelf;
			TGStarsDetailViewController *strongController = weakController;
			if (!strongSelf || !strongController)
				return;
			[strongSelf confirmWithTitle:@"Pay With Stars"
								 message:[NSString stringWithFormat:
										 @"%@ will be taken from your balance.",
										 [strongSelf starsText:price signed:NO]]
								  action:@"Pay"
								   block:^{
				typeof(self) innerSelf = weakSelf;
				if (!innerSelf)
					return;
				strongController.busy = YES;
				[strongController.tableView reloadData];
				[[TGClient shared] payStarsPaymentForm:form completion:^(BOOL ok){
					typeof(self) doneSelf = weakSelf;
					if (doneSelf)
						[doneSelf finishAction:strongController
									   success:ok
									   failure:@"The payment was not accepted."];
				}];
			}];
	});
}

- (void)pushPaymentForm:(NSDictionary *)form {
	NSString *title = form[@"title"];
	if (![title isKindOfClass:[NSString class]] || !title.length)
		title = @"Invoice";
	BOOL isStars = [form[@"isStars"] boolValue];

	NSString *description = form[@"description"];
	if (![description isKindOfClass:[NSString class]] || !description.length)
		description = nil;

	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:title
														 pairs:[self pairsForPaymentForm:form]
													   comment:description];
	if (isStars){
		long long price = [form[@"starCount"] longLongValue];
		[controller setActions:@[[self payWithStarsActionForForm:form
														   price:price
													  controller:controller]]];
		controller.actionsComment = @"The invoice expires, so pay it soon after opening it.";
	} else {
		controller.actionsComment = nil;
		controller.comment = description.length
				? [NSString stringWithFormat:@"%@\n\nThis invoice is priced in a currency, and can only be paid where a card can be entered.", description]
				: @"This invoice is priced in a currency, and can only be paid where a card can be entered.";
	}
	[self.navigationController pushViewController:controller animated:YES];
}

- (void)openInvoiceByName {
	__weak typeof(self) weakSelf = self;
	[self promptWithTitle:@"Open an Invoice"
				  message:@"Enter the invoice name from its link."
			  placeholder:@"Invoice name"
				  numeric:NO
			  actionTitle:@"Open"
				  handler:^(NSString *text)
	{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[[TGClient shared] paymentFormForInvoiceName:text
										  completion:^(NSDictionary *form)
		{
			typeof(self) innerSelf = weakSelf;
			if (!innerSelf)
				return;
			if (![form isKindOfClass:[NSDictionary class]]){
				[innerSelf showMessage:@"No invoice was found under that name."];
				return;
			}
			[innerSelf pushPaymentForm:form];
		}];
	}];
}

#pragma mark - paid messages and saved details

- (void)editPaidMessagePrice {
	int64_t myId = [[TGClient shared].me[@"id"] longLongValue];
	if (!myId){
		[self showMessage:@"This account is not ready yet."];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self promptWithTitle:@"Charge for Messages"
				  message:@"Stars a stranger pays to send you one message. Enter 0 to charge nothing."
			  placeholder:@"Stars"
				  numeric:YES
			  actionTitle:@"Save"
				  handler:^(NSString *text)
	{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		long long stars = [text longLongValue];
		if (stars < 0)
			return;
		[[TGClient shared] setChat:myId paidMessageStarCount:stars];
		[strongSelf showMessage:stars > 0
				? [NSString stringWithFormat:@"Strangers now pay %@ per message.",
						[strongSelf starsText:stars signed:NO]]
				: @"Anybody may write to you for free."];
	}];
}

- (void)allowFreeMessagesFromUser:(int64_t)userId
							  name:(NSString *)name
							 refund:(BOOL)refund
{
	__weak typeof(self) weakSelf = self;
	[self confirmWithTitle:refund ? @"Free and Refund" : @"Write for Free"
				   message:refund
						   ? [NSString stringWithFormat:
								   @"%@ may write for free, and the stars already paid go back.",
								   name.length ? name : @"This contact"]
						   : [NSString stringWithFormat:@"%@ may write to you for free from now on.",
								   name.length ? name : @"This contact"]
					action:refund ? @"Refund" : @"Allow"
					 block:^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[[TGClient shared] allowUnpaidMessagesFromUser:userId refundPayments:refund];
		[strongSelf.navigationController popViewControllerAnimated:YES];
		[strongSelf showMessage:refund
				? @"The stars were returned and this contact writes for free."
				: @"This contact writes for free."];
	}];
}

- (void)pushPaidMessageDetailForUser:(int64_t)userId name:(NSString *)name {
	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:name.length ? name : @"Contact"
														 pairs:@[@[@"Paid So Far", @"..."]]
													   comment:nil];
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;
	[self.navigationController pushViewController:controller animated:YES];
	[[TGClient shared] paidMessageRevenueFromUser:userId completion:^(long long stars){
		typeof(self) strongSelf = weakSelf;
		TGStarsDetailViewController *strongController = weakController;
		if (!strongSelf || !strongController)
			return;
		strongController.pairs = @[@[@"Paid So Far",
				[strongSelf starsText:stars signed:NO]]];
		NSMutableArray *actions = [NSMutableArray array];
		[actions addObject:TGStarsAction(@"Let Them Write for Free", nil, NO, ^{
			typeof(self) innerSelf = weakSelf;
			if (innerSelf)
				[innerSelf allowFreeMessagesFromUser:userId name:name refund:NO];
		})];
		if (stars > 0){
			[actions addObject:TGStarsAction(@"Free and Refund Stars", nil, YES, ^{
				typeof(self) innerSelf = weakSelf;
				if (innerSelf)
					[innerSelf allowFreeMessagesFromUser:userId name:name refund:YES];
			})];
		}
		strongController.actions = actions;
		strongController.actionsComment =
				@"Allowing a contact cannot be undone from here.";
		[strongController.tableView reloadData];
	}];
}

- (void)pushPaidMessages {
	TGStarsListViewController *list =
			[[TGStarsListViewController alloc] initWithTitle:@"Charge for Messages"];
	list.comment = @"Strangers pay stars to write to you. A contact you allow always writes for free.";
	__weak typeof(self) weakSelf = self;
	[list appendRow:TGStarsRow(@"Price per Message", nil, nil, ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf)
			[strongSelf editPaidMessagePrice];
	})];
	[list appendRow:TGStarsRow(@"Free for a Contact", nil, nil, ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf pickUserWithTitle:@"Write for Free"
							  handler:^(int64_t userId, NSString *name)
		{
			typeof(self) innerSelf = weakSelf;
			if (innerSelf)
				[innerSelf pushPaidMessageDetailForUser:userId name:name];
		}];
	})];
	[self.navigationController pushViewController:list animated:YES];
}

- (void)clearSavedPaymentInfo {
	__weak typeof(self) weakSelf = self;
	[self confirmWithTitle:@"Clear Saved Payment Info"
				   message:@"The saved card and shipping details are forgotten."
					action:@"Clear"
					 block:^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[[TGClient shared] clearSavedPaymentInfoWithCompletion:^(BOOL ok){
			typeof(self) innerSelf = weakSelf;
			if (!innerSelf)
				return;
			[innerSelf showMessage:ok ? @"Saved payment details were cleared."
									  : @"The details could not be cleared."];
		}];
	}];
}

@end

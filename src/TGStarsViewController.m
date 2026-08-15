#import "TGStarsViewController.h"
#import "TGClient.h"
#import "TGClient+Premium.h"
#import "TGClient+Payments.h"
#import "TGClient+ChatList.h"
#import "TGAlertView.h"
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
	TGStarsSectionCount
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
			TGStarsSectionHeaderWithTitle(giftsTitle), nil];
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
	if (self.giftsLoaded && !self.gifts.count)
		return @"Gifts friends send you appear here.";
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

- (void)pushTransactionDetails:(NSDictionary *)transaction {
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
	if ([transactionId isKindOfClass:[NSString class]] && transactionId.length)
		[pairs addObject:@[@"ID", transactionId]];

	NSString *title = [self counterpartyForTransaction:transaction];
	NSString *comment = transaction[@"description"];
	if (![comment isKindOfClass:[NSString class]] || !comment.length)
		comment = nil;

	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:title
														 pairs:pairs
													   comment:comment];
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

- (NSArray *)giftActionsFor:(NSDictionary *)gift
				 controller:(TGStarsDetailViewController *)controller
{
	NSString *giftId = gift[@"giftId"];
	if (![giftId isKindOfClass:[NSString class]] || !giftId.length)
		return nil;

	NSMutableArray *actions = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;
	__weak TGStarsDetailViewController *weakController = controller;

	BOOL saved = [gift[@"isSaved"] boolValue];
	[actions addObject:TGStarsAction(@"On My Profile", saved ? @"Shown" : @"Hidden", NO, ^{
		typeof(self) strongSelf = weakSelf;
		TGStarsDetailViewController *strongController = weakController;
		if (!strongSelf || !strongController)
			return;
		[[TGClient shared] setReceivedGift:giftId saved:!saved];
		NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:gift];
		updated[@"isSaved"] = @(!saved);
		[strongSelf configureGiftDetail:strongController withGift:updated];
	})];

	long long sell = [gift[@"sellStarCount"] longLongValue];
	if (sell > 0 && ![gift[@"isUnique"] boolValue]){
		NSString *value = [self starsText:sell signed:NO];
		[actions addObject:TGStarsAction(@"Convert to Stars", value, YES, ^{
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
		})];
	}

	long long upgrade = [gift[@"upgradeStarCount"] longLongValue];
	if ([gift[@"canUpgrade"] boolValue] && ![gift[@"isUnique"] boolValue]){
		NSString *value = upgrade > 0 ? [self starsText:upgrade signed:NO] : @"Free";
		[actions addObject:TGStarsAction(@"Upgrade to Unique", value, NO, ^{
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
		})];
	}

	if ([gift[@"isUnique"] boolValue]){
		long long resale = [gift[@"resaleStarCount"] longLongValue];
		[actions addObject:TGStarsAction(resale > 0 ? @"Change Sale Price" : @"Sell This Gift",
				resale > 0 ? [self starsText:resale signed:NO] : nil, NO, ^{
			typeof(self) strongSelf = weakSelf;
			TGStarsDetailViewController *strongController = weakController;
			if (!strongSelf || !strongController)
				return;
			[strongSelf askResalePriceForGift:giftId controller:strongController];
		})];
		if (resale > 0){
			[actions addObject:TGStarsAction(@"Remove From Sale", nil, YES, ^{
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
			})];
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

- (void)pushSubscriptionDetails:(NSDictionary *)subscription {
	NSString *subscriptionId = subscription[@"id"];
	if (![subscriptionId isKindOfClass:[NSString class]])
		subscriptionId = nil;

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

	TGStarsDetailViewController *controller =
			[[TGStarsDetailViewController alloc] initWithTitle:
					[self titleForSubscription:subscription]
														 pairs:pairs
													   comment:nil];

	if (subscriptionId.length){
		NSMutableArray *actions = [NSMutableArray array];
		__weak typeof(self) weakSelf = self;
		__weak TGStarsDetailViewController *weakController = controller;

		if ([subscription[@"canReuse"] boolValue]){
			[actions addObject:TGStarsAction(@"Rejoin Channel", nil, NO, ^{
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
			})];
		}

		BOOL canceled = [subscription[@"isCanceled"] boolValue];
		[actions addObject:TGStarsAction(
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
		})];

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

@end

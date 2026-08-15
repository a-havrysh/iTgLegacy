#import "TGStarsViewController.h"
#import "TGClient.h"
#import "TGClient+Premium.h"
#import "TGClient+Payments.h"
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

@end

@interface TGStarsDetailViewController ()
@property (nonatomic, strong) NSArray *pairs;
@property (nonatomic, strong) NSString *comment;
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
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.pairs.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 44;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return 8;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	return TGStarsCommentHeight(self.comment, self.tableView.bounds.size.width ?: 320);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	return TGStarsCommentViewWithText(self.comment, self.tableView.bounds.size.width ?: 320);
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
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
	TGStarsSectionGifts,
	TGStarsSectionCount
};

@interface TGStarsViewController ()
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
	self.sectionHeaderViews = [NSArray arrayWithObjects:
			[NSNull null],
			TGStarsSectionHeaderWithTitle(@"Transactions"),
			TGStarsSectionHeaderWithTitle(giftsTitle), nil];
}

- (void)reloadTapped {
	[self.transactions removeAllObjects];
	[self.gifts removeAllObjects];
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

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
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

	long long sell = [gift[@"sellStarCount"] longLongValue];
	if (sell > 0)
		[pairs addObject:@[@"If Converted", [self starsText:sell signed:NO]]];

	[pairs addObject:@[@"On My Profile",
			[gift[@"isSaved"] boolValue] ? @"Shown" : @"Hidden"]];

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

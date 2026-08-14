#import "TGStarsViewController.h"
#import "TGClient.h"
#import "TGClient+Premium.h"
#import "TGClient+Payments.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGAlertView.h"

static const CGFloat kStarsHeaderHeight = 86.0f;
static const NSInteger kStarsPageSize = 25;
static const NSInteger kStarsGiftPageSize = 20;

static inline UIColor *TGStarsRGB(unsigned int value) {
	return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0f
						   green:((value >> 8) & 0xff) / 255.0f
							blue:(value & 0xff) / 255.0f
						   alpha:1.0f];
}

enum {
	TGStarsSectionTransactions = 0,
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
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerStatusLabel;
@property (nonatomic, strong) UIImageView *headerBadgeView;
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

	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	if (self.navigationController.navigationBar)
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	UIButton *reload = [TGIcons headerButtonWithTitle:@"Reload" bold:NO
											   target:self action:@selector(reloadTapped)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:reload];

	[self buildHeader];
	[self loadFirstPages];
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
	self.balanceKnown = NO;
	self.giftTotal = 0;
	[self.tableView reloadData];
	[self refreshHeader];
	[self loadFirstPages];
}

#pragma mark - header

- (void)buildHeader {
	CGFloat width = self.view.bounds.size.width ?: 320;
	UIView *header = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, kStarsHeaderHeight)];
	header.backgroundColor = [UIColor clearColor];
	header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

	BOOL dark = [[TGTheme shared] isDark];

	UIImageView *badge = [[UIImageView alloc] initWithFrame:CGRectMake(9, 14, 70, 70)];
	badge.image = [TGIcons avatarWithInitials:@"★" size:70 colourId:2];
	badge.layer.cornerRadius = 10.0f;
	badge.clipsToBounds = YES;
	[header addSubview:badge];
	self.headerBadgeView = badge;

	UILabel *title = [[UILabel alloc] initWithFrame:
			CGRectMake(94, 24, width - 94 - 9, 24)];
	title.text = @"—";
	title.font = [UIFont boldSystemFontOfSize:19];
	title.backgroundColor = [UIColor clearColor];
	title.textColor = dark ? [[TGTheme shared] primaryTextColour] : TGStarsRGB(0x222932);
	if (!dark){
		title.shadowColor = [UIColor colorWithRed:0xed / 255.0f green:0xf0 / 255.0f
											 blue:0xf5 / 255.0f alpha:0.28f];
		title.shadowOffset = CGSizeMake(0, 1);
	}
	title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:title];
	self.headerTitleLabel = title;

	UILabel *status = [[UILabel alloc] initWithFrame:
			CGRectMake(94, 52, width - 94 - 9, 24)];
	status.text = @"checking...";
	status.font = [UIFont systemFontOfSize:14];
	status.backgroundColor = [UIColor clearColor];
	status.textColor = dark ? [[TGTheme shared] secondaryTextColour] : TGStarsRGB(0x6d7d90);
	if (!dark){
		status.shadowColor = title.shadowColor;
		status.shadowOffset = CGSizeMake(0, 1);
	}
	status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:status];
	self.headerStatusLabel = status;

	self.tableView.tableHeaderView = header;
	[self refreshHeader];
}

- (void)refreshHeader {
	if (!self.headerTitleLabel)
		return;

	if (self.balanceKnown){
		self.headerTitleLabel.text = [NSString stringWithFormat:@"★ %@",
				[self formattedNumber:@(self.balance)]];
		self.headerStatusLabel.text = self.balance == 1 ? @"star on this account"
													   : @"stars on this account";
	} else if (self.transactionsFailed){
		self.headerTitleLabel.text = @"★ —";
		self.headerStatusLabel.text = @"balance unavailable";
	} else {
		self.headerTitleLabel.text = @"★ —";
		self.headerStatusLabel.text = @"checking...";
	}
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
			[strongSelf refreshHeader];
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
		[strongSelf refreshHeader];
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

- (NSString *)subtitleForTransaction:(NSDictionary *)transaction {
	NSString *date = [self dateTextFromValue:transaction[@"date"]];
	if ([transaction[@"refund"] boolValue]){
		if (date.length)
			return [NSString stringWithFormat:@"Refund · %@", date];
		return @"Refund";
	}
	return date;
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
	if (section == TGStarsSectionTransactions){
		if (!self.transactions.count)
			return 1;
		return (NSInteger)self.transactions.count + ([self hasMoreTransactions] ? 1 : 0);
	}
	if (!self.gifts.count)
		return 1;
	return (NSInteger)self.gifts.count + ([self hasMoreGifts] ? 1 : 0);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == TGStarsSectionTransactions)
		return @"Transactions";
	if (self.giftTotal > 0)
		return [NSString stringWithFormat:@"Gifts received (%d)", (int)self.giftTotal];
	return @"Gifts received";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == TGStarsSectionTransactions){
		if (self.transactionsFailed)
			return @"The history could not be loaded. Tap Reload to try again.";
		return @"Stars cannot be bought here. This page shows what the account "
				"has earned and spent.";
	}
	if (self.giftsLoaded && !self.gifts.count)
		return @"Gifts friends send you appear here.";
	return nil;
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
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.font = [UIFont systemFontOfSize:16];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = TGStarsRGB(0x888888);
	[[TGTheme shared] styleCell:cell];
	return cell;
}

- (UITableViewCell *)statusCellInTable:(UITableView *)tableView text:(NSString *)text {
	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleDefault
										   reuseId:@"TGStarsStatus"];
	cell.textLabel.text = text;
	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)moreCellInTable:(UITableView *)tableView loading:(BOOL)loading {
	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleDefault
										   reuseId:@"TGStarsMore"];
	cell.textLabel.text = loading ? @"Loading..." : @"Show more";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.textLabel.textColor = loading ? [[TGTheme shared] secondaryTextColour]
									   : TGStarsRGB(0x0779d0);
	cell.selectionStyle = loading ? UITableViewCellSelectionStyleNone
								  : UITableViewCellSelectionStyleBlue;
	return cell;
}

- (UILabel *)amountLabelWithStars:(long long)stars {
	NSString *text = [NSString stringWithFormat:@"%@%@ ★",
			stars > 0 ? @"+" : @"", [self formattedNumber:@(stars)]];
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 90, 20)];
	label.text = text;
	label.font = [UIFont boldSystemFontOfSize:16];
	label.backgroundColor = [UIColor clearColor];
	label.textAlignment = NSTextAlignmentRight;
	label.textColor = stars < 0 ? TGStarsRGB(0xcc1e2c) : TGStarsRGB(0x229a0a);
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

	NSString *sender = gift[@"senderName"];
	if (![sender isKindOfClass:[NSString class]] || !sender.length){
		int64_t senderId = [gift[@"senderId"] longLongValue];
		sender = senderId ? [[TGClient shared] nameForUserId:senderId] : nil;
	}
	if (![sender isKindOfClass:[NSString class]] || !sender.length)
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
	if (indexPath.section == TGStarsSectionTransactions){
		if (!self.transactions.count){
			if (!self.transactionsLoaded)
				return [self statusCellInTable:tableView text:@"Loading transactions..."];
			if (self.transactionsFailed)
				return [self statusCellInTable:tableView text:@"History unavailable"];
			return [self statusCellInTable:tableView text:@"No transactions yet"];
		}
		if (indexPath.row >= (NSInteger)self.transactions.count)
			return [self moreCellInTable:tableView loading:self.transactionsLoading];
		return [self transactionCellInTable:tableView row:indexPath.row];
	}

	if (!self.gifts.count){
		if (!self.giftsLoaded)
			return [self statusCellInTable:tableView text:@"Loading gifts..."];
		return [self statusCellInTable:tableView text:@"No gifts yet"];
	}
	if (indexPath.row >= (NSInteger)self.gifts.count)
		return [self moreCellInTable:tableView loading:self.giftsLoading];
	return [self giftCellInTable:tableView row:indexPath.row];
}

#pragma mark - taps

- (void)showTransactionDetails:(NSDictionary *)transaction {
	NSMutableString *message = [NSMutableString string];
	long long stars = [transaction[@"stars"] longLongValue];
	[message appendFormat:@"%@%@ stars\n", stars > 0 ? @"+" : @"",
			[self formattedNumber:@(stars)]];

	NSString *date = [self dateTextFromValue:transaction[@"date"]];
	if (date.length)
		[message appendFormat:@"%@\n", date];

	NSString *type = transaction[@"type"];
	if ([type isKindOfClass:[NSString class]] && type.length)
		[message appendFormat:@"Type: %@\n", type];

	if ([transaction[@"refund"] boolValue])
		[message appendString:@"Refunded\n"];

	NSString *transactionId = transaction[@"id"];
	if ([transactionId isKindOfClass:[NSString class]] && transactionId.length)
		[message appendFormat:@"ID %@", transactionId];

	NSString *title = transaction[@"title"];
	if (![title isKindOfClass:[NSString class]] || !title.length)
		title = @"Transaction";

	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:title
													message:message
										  cancelButtonTitle:@"Close"
											  okButtonTitle:nil
											completionBlock:nil];
	[alert show];
}

- (void)showGiftDetails:(NSDictionary *)gift {
	NSMutableString *message = [NSMutableString string];

	long long stars = [gift[@"starCount"] longLongValue];
	if (stars > 0)
		[message appendFormat:@"%@ stars\n", [self formattedNumber:@(stars)]];

	NSString *sender = gift[@"senderName"];
	if (![sender isKindOfClass:[NSString class]] || !sender.length){
		int64_t senderId = [gift[@"senderId"] longLongValue];
		if (senderId)
			sender = [[TGClient shared] nameForUserId:senderId];
	}
	if ([sender isKindOfClass:[NSString class]] && sender.length)
		[message appendFormat:@"From %@\n", sender];
	else
		[message appendString:@"From an anonymous sender\n"];

	NSString *date = [self dateTextFromValue:gift[@"date"]];
	if (date.length)
		[message appendFormat:@"%@\n", date];

	NSString *text = gift[@"text"];
	if ([text isKindOfClass:[NSString class]] && text.length)
		[message appendFormat:@"\"%@\"\n", text];

	if ([gift[@"isUnique"] boolValue]){
		NSString *name = gift[@"name"];
		NSNumber *number = gift[@"number"];
		if ([name isKindOfClass:[NSString class]] && name.length)
			[message appendFormat:@"Unique gift %@", name];
		else
			[message appendString:@"Unique gift"];
		if ([number isKindOfClass:[NSNumber class]] && [number longLongValue])
			[message appendFormat:@" #%lld", [number longLongValue]];
		[message appendString:@"\n"];
	}

	long long sell = [gift[@"sellStarCount"] longLongValue];
	if (sell > 0)
		[message appendFormat:@"Worth %@ stars if converted\n",
				[self formattedNumber:@(sell)]];

	[message appendString:[gift[@"isSaved"] boolValue]
			? @"Shown on your profile" : @"Hidden from your profile"];

	NSString *title = gift[@"title"];
	if (![title isKindOfClass:[NSString class]] || !title.length)
		title = @"Gift";

	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:title
													message:message
										  cancelButtonTitle:@"Close"
											  okButtonTitle:nil
											completionBlock:nil];
	[alert show];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

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
		[self showTransactionDetails:self.transactions[indexPath.row]];
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
	[self showGiftDetails:self.gifts[indexPath.row]];
}

@end

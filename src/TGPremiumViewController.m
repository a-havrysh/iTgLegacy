#import "TGPremiumViewController.h"
#import "TGClient.h"
#import "TGClient+Premium.h"
#import "TGClient+Network.h"
#import "TGClient+ChatList.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGAlertView.h"
#import "TGActionSheet.h"

static const CGFloat kPremiumHeaderHeight = 86.0f;
static const CGFloat kPremiumSectionHeaderHeight = 46.0f;

static inline UIColor *TGPremiumRGB(unsigned int value) {
	return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0f
						   green:((value >> 8) & 0xff) / 255.0f
							blue:(value & 0xff) / 255.0f
						   alpha:1.0f];
}

static NSString *TGPremiumDateText(id value) {
	if (![value isKindOfClass:[NSNumber class]] || [value doubleValue] <= 0)
		return @"";
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterMediumStyle;
		formatter.timeStyle = NSDateFormatterNoStyle;
	}
	return [formatter stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[value doubleValue]]];
}

enum {
	TGPremiumListGiftCodes = 0,
	TGPremiumListGiveaways,
	TGPremiumListBoostSlots,
	TGPremiumListBoostLevels,
	TGPremiumListBoosters,
	TGPremiumListBusiness
};

enum {
	TGPremiumRowPlain = 0,
	TGPremiumRowTappable,
	TGPremiumRowLevel,
	TGPremiumRowLoadMore
};

@interface TGPremiumListViewController : UITableViewController
@property (nonatomic, assign) NSInteger mode;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSString *nextOffset;
@property (nonatomic, strong) NSString *statusText;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) int64_t sheetChatId;
- (id)initWithMode:(NSInteger)mode chatId:(int64_t)chatId title:(NSString *)title;
@end

@implementation TGPremiumListViewController

- (id)initWithMode:(NSInteger)mode chatId:(int64_t)chatId title:(NSString *)title {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		_mode = mode;
		_chatId = chatId;
		_rows = [[NSMutableArray alloc] init];
		_nextOffset = @"";
		_statusText = @"Loading...";
		self.title = title;
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
	[self load];
}

- (void)addRowWithTitle:(NSString *)title
				 detail:(NSString *)detail
				   kind:(NSInteger)kind
				payload:(NSDictionary *)payload
{
	NSMutableDictionary *row = [NSMutableDictionary dictionaryWithCapacity:4];
	row[@"title"] = title.length ? title : @" ";
	row[@"detail"] = detail.length ? detail : @"";
	row[@"kind"] = @(kind);
	if (payload)
		row[@"payload"] = payload;
	[self.rows addObject:row];
}

- (void)finishedWithEmptyText:(NSString *)text {
	self.loading = NO;
	self.statusText = self.rows.count ? @"" : text;
	[self.tableView reloadData];
}

- (void)load {
	if (self.loading)
		return;
	self.loading = YES;
	switch (self.mode){
		case TGPremiumListGiftCodes:   [self loadGiftCodes]; break;
		case TGPremiumListGiveaways:   [self loadGiveaways]; break;
		case TGPremiumListBoostSlots:  [self loadBoostSlots]; break;
		case TGPremiumListBoostLevels: [self loadBoostLevels]; break;
		case TGPremiumListBoosters:    [self loadBoosters]; break;
		default:                       [self loadBusinessFeatures]; break;
	}
}

- (void)loadGiftCodes {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] accountGiftCodesWithLimit:0 completion:^(NSArray *codes){
		if (!weakSelf)
			return;
		[weakSelf.rows removeAllObjects];
		for (id raw in ([codes isKindOfClass:[NSArray class]] ? codes : @[])){
			if (![raw isKindOfClass:[NSDictionary class]])
				continue;
			NSDictionary *entry = raw;
			NSString *code = [entry[@"code"] isKindOfClass:[NSString class]]
					? entry[@"code"] : @"";
			long long stars = [entry[@"stars"] longLongValue];
			NSMutableString *detail = [NSMutableString string];
			if (stars > 0)
				[detail appendFormat:@"%lld Stars", stars];
			else if ([entry[@"months"] integerValue] > 0)
				[detail appendFormat:@"%d months", (int)[entry[@"months"] integerValue]];
			if ([entry[@"unclaimed"] boolValue])
				[detail appendString:detail.length ? @" · unclaimed" : @"unclaimed"];
			NSString *date = TGPremiumDateText(entry[@"date"]);
			if (date.length)
				[detail appendString:detail.length ?
						[NSString stringWithFormat:@" · %@", date] : date];
			NSString *title = code.length ? code : @"Star prize";
			[weakSelf addRowWithTitle:title
							   detail:detail
								 kind:code.length ? TGPremiumRowTappable : TGPremiumRowPlain
							  payload:entry];
		}
		[weakSelf finishedWithEmptyText:@"No gift codes have been sent to this account."];
	}];
}

- (void)loadGiveaways {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] enteredGiveawaysWithLimit:0 completion:^(NSArray *giveaways){
		if (!weakSelf)
			return;
		[weakSelf.rows removeAllObjects];
		for (id raw in ([giveaways isKindOfClass:[NSArray class]] ? giveaways : @[])){
			if (![raw isKindOfClass:[NSDictionary class]])
				continue;
			NSDictionary *entry = raw;
			NSString *title = [entry[@"chatTitle"] isKindOfClass:[NSString class]]
					&& [entry[@"chatTitle"] length] ? entry[@"chatTitle"] : @"Channel";
			NSString *status = [entry[@"statusText"] isKindOfClass:[NSString class]]
					? entry[@"statusText"] : @"";
			if (!status.length)
				status = [entry[@"ongoing"] boolValue] ? @"Ongoing" : @"Finished";
			[weakSelf addRowWithTitle:title
							   detail:status
								 kind:TGPremiumRowTappable
							  payload:entry];
		}
		[weakSelf finishedWithEmptyText:
				@"This account has not entered any giveaway in a channel it boosts."];
	}];
}

- (void)loadBoostSlots {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] availableBoostSlotsWithCompletion:^(NSArray *slots){
		if (!weakSelf)
			return;
		[weakSelf.rows removeAllObjects];
		for (id raw in ([slots isKindOfClass:[NSArray class]] ? slots : @[])){
			if (![raw isKindOfClass:[NSDictionary class]])
				continue;
			NSDictionary *slot = raw;
			int64_t slotChat = [slot[@"chatId"] longLongValue];
			NSString *title = [NSString stringWithFormat:@"Slot %d",
					(int)[slot[@"slotId"] integerValue]];
			if (slotChat == 0 || [slot[@"free"] boolValue]){
				[weakSelf addRowWithTitle:title detail:@"Free"
									 kind:TGPremiumRowPlain payload:slot];
				continue;
			}
			NSString *detail = [slot[@"reassignable"] boolValue]
					? @"In use · can be moved" : @"In use";
			[weakSelf addRowWithTitle:title detail:detail
								 kind:TGPremiumRowTappable payload:slot];
			NSUInteger index = weakSelf.rows.count - 1;
			[[TGClient shared] titleForChatId:slotChat completion:^(NSString *chatTitle){
				if (!weakSelf || index >= weakSelf.rows.count || !chatTitle.length)
					return;
				NSMutableDictionary *row = weakSelf.rows[index];
				row[@"title"] = chatTitle;
				[weakSelf.tableView reloadData];
			}];
		}
		[weakSelf finishedWithEmptyText:
				@"Boost slots come with a Premium subscription."];
	}];
}

- (void)loadBoostLevels {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] boostFeaturesForChannel:YES completion:^(NSArray *levels){
		if (!weakSelf)
			return;
		[weakSelf.rows removeAllObjects];
		for (id raw in ([levels isKindOfClass:[NSArray class]] ? levels : @[])){
			if (![raw isKindOfClass:[NSDictionary class]])
				continue;
			NSDictionary *level = raw;
			[weakSelf addRowWithTitle:[NSString stringWithFormat:@"Level %d",
							(int)[level[@"level"] integerValue]]
							   detail:@""
								 kind:TGPremiumRowLevel
							  payload:nil];
			id features = level[@"features"];
			if (![features isKindOfClass:[NSArray class]])
				continue;
			for (id line in features){
				if ([line isKindOfClass:[NSString class]])
					[weakSelf addRowWithTitle:line detail:@""
										 kind:TGPremiumRowPlain payload:nil];
			}
		}
		[weakSelf finishedWithEmptyText:@"The boost level table is unavailable."];
	}];
}

- (void)loadBoosters {
	__weak typeof(self) weakSelf = self;
	NSString *offset = self.nextOffset.length ? self.nextOffset : @"";
	[[TGClient shared] boostersInChat:self.chatId
						onlyGiftCodes:NO
							   offset:offset
								limit:20
						   completion:^(NSDictionary *page){
		if (!weakSelf)
			return;
		if (![page isKindOfClass:[NSDictionary class]]){
			[weakSelf finishedWithEmptyText:@"The booster list is unavailable."];
			return;
		}
		if (weakSelf.rows.count
				&& [weakSelf.rows.lastObject[@"kind"] integerValue] == TGPremiumRowLoadMore)
			[weakSelf.rows removeLastObject];
		id boosts = page[@"boosts"];
		for (id raw in ([boosts isKindOfClass:[NSArray class]] ? boosts : @[])){
			if (![raw isKindOfClass:[NSDictionary class]])
				continue;
			NSDictionary *boost = raw;
			NSString *name = [boost[@"name"] isKindOfClass:[NSString class]]
					? boost[@"name"] : @"";
			if (!name.length)
				name = [boost[@"unclaimed"] boolValue] ? @"Unclaimed prize" : @"Booster";
			NSString *source = [boost[@"source"] isKindOfClass:[NSString class]]
					? boost[@"source"] : @"";
			NSInteger count = [boost[@"count"] integerValue];
			NSMutableString *detail = [NSMutableString string];
			if (count > 1)
				[detail appendFormat:@"%d boosts", (int)count];
			if (source.length)
				[detail appendString:detail.length
						? [NSString stringWithFormat:@" · %@", source] : source];
			[weakSelf addRowWithTitle:name detail:detail
								 kind:TGPremiumRowPlain payload:boost];
		}
		NSString *next = [page[@"nextOffset"] isKindOfClass:[NSString class]]
				? page[@"nextOffset"] : @"";
		weakSelf.nextOffset = next;
		if (next.length && weakSelf.rows.count)
			[weakSelf addRowWithTitle:@"Show More" detail:@""
								 kind:TGPremiumRowLoadMore payload:nil];
		NSInteger total = [page[@"totalCount"] integerValue];
		if (total > 0)
			weakSelf.title = [NSString stringWithFormat:@"Boosters (%d)", (int)total];
		[weakSelf finishedWithEmptyText:@"Nobody has boosted this channel yet."];
	}];
}

- (void)loadBusinessFeatures {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] businessFeaturesWithCompletion:^(NSArray *features){
		if (!weakSelf)
			return;
		[weakSelf.rows removeAllObjects];
		for (id raw in ([features isKindOfClass:[NSArray class]] ? features : @[])){
			if (![raw isKindOfClass:[NSDictionary class]])
				continue;
			NSDictionary *feature = raw;
			NSString *title = [feature[@"title"] isKindOfClass:[NSString class]]
					&& [feature[@"title"] length] ? feature[@"title"] : feature[@"type"];
			NSString *subtitle = [feature[@"subtitle"] isKindOfClass:[NSString class]]
					? feature[@"subtitle"] : @"";
			[weakSelf addRowWithTitle:title
							   detail:subtitle
								 kind:subtitle.length ? TGPremiumRowTappable : TGPremiumRowPlain
							  payload:feature];
		}
		[weakSelf finishedWithEmptyText:@"The Business feature list is unavailable."];
	}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.rows.count ? (NSInteger)self.rows.count : 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (!self.rows.count)
		return 54;
	NSDictionary *row = self.rows[indexPath.row];
	if ([row[@"kind"] integerValue] == TGPremiumRowLevel)
		return 34;
	if ([row[@"detail"] length] > 34)
		return 58;
	return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (!self.rows.count){
		static NSString *emptyId = @"TGPremiumListEmpty";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:emptyId];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:emptyId];
		[[TGTheme shared] styleCell:cell];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.textLabel.numberOfLines = 0;
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.textLabel.font = [UIFont systemFontOfSize:15];
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.textLabel.text = self.loading ? @"Loading..." : self.statusText;
		return cell;
	}

	NSDictionary *row = self.rows[indexPath.row];
	NSInteger kind = [row[@"kind"] integerValue];
	NSString *reuseId = kind == TGPremiumRowLevel ? @"TGPremiumListLevel"
												  : @"TGPremiumListRow";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
	if (!cell)
		cell = [[UITableViewCell alloc]
				initWithStyle:kind == TGPremiumRowLevel ? UITableViewCellStyleDefault
													   : UITableViewCellStyleSubtitle
			  reuseIdentifier:reuseId];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.numberOfLines = 1;
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.text = row[@"title"];
	cell.detailTextLabel.numberOfLines = 2;
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.detailTextLabel.text = row[@"detail"];

	if (kind == TGPremiumRowLevel){
		cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	cell.textLabel.font = [UIFont systemFontOfSize:16];
	cell.textLabel.textColor = kind == TGPremiumRowLoadMore
			? [[TGTheme shared] accentColour]
			: [[TGTheme shared] primaryTextColour];
	cell.accessoryType = kind == TGPremiumRowTappable
			? UITableViewCellAccessoryDisclosureIndicator
			: UITableViewCellAccessoryNone;
	cell.selectionStyle = kind == TGPremiumRowPlain
			? UITableViewCellSelectionStyleNone
			: UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (!self.rows.count)
		return;
	NSDictionary *row = self.rows[indexPath.row];
	NSInteger kind = [row[@"kind"] integerValue];
	if (kind == TGPremiumRowLoadMore){
		[self load];
		return;
	}
	if (kind != TGPremiumRowTappable)
		return;

	NSDictionary *payload = row[@"payload"];
	switch (self.mode){
		case TGPremiumListGiftCodes:  [self showGiftCode:payload]; break;
		case TGPremiumListGiveaways:  [self showGiveaway:payload]; break;
		case TGPremiumListBoostSlots: [self showSlotActions:payload]; break;
		case TGPremiumListBusiness: {
			TGAlertView *alert = [[TGAlertView alloc] initWithTitle:row[@"title"]
															message:row[@"detail"]
												  cancelButtonTitle:@"OK"
													  okButtonTitle:nil
													completionBlock:nil];
			[alert show];
			break;
		}
		default: break;
	}
}

- (void)showGiftCode:(NSDictionary *)entry {
	NSString *code = [entry[@"code"] isKindOfClass:[NSString class]] ? entry[@"code"] : @"";
	if (!code.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] checkGiftCode:code completion:^(NSDictionary *info){
		if (![info isKindOfClass:[NSDictionary class]]){
			TGAlertView *fail = [[TGAlertView alloc] initWithTitle:@"Gift Code"
														   message:@"This code could not be checked."
												 cancelButtonTitle:@"OK"
													 okButtonTitle:nil
												   completionBlock:nil];
			[fail show];
			return;
		}
		NSMutableString *message = [NSMutableString stringWithString:code];
		NSInteger months = [info[@"months"] integerValue];
		if (months > 0)
			[message appendFormat:@"\n%d months of Premium", (int)months];
		if ([info[@"fromGiveaway"] boolValue])
			[message appendString:@"\nFrom a giveaway"];
		NSString *created = TGPremiumDateText(info[@"creationDate"]);
		if (created.length)
			[message appendFormat:@"\nCreated %@", created];
		BOOL used = [info[@"used"] boolValue];
		if (used){
			NSString *usedDate = TGPremiumDateText(info[@"useDate"]);
			[message appendFormat:@"\nAlready used%@",
					usedDate.length ? [NSString stringWithFormat:@" on %@", usedDate] : @""];
			TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Gift Code"
															message:message
												  cancelButtonTitle:@"OK"
													  okButtonTitle:nil
													completionBlock:nil];
			[alert show];
			return;
		}
		[message appendString:@"\nNot used yet"];
		TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Gift Code"
														message:message
											  cancelButtonTitle:@"Close"
												  okButtonTitle:@"Redeem"
												completionBlock:^(bool okPressed){
			if (!okPressed)
				return;
			[[TGClient shared] applyGiftCode:code completion:^(BOOL ok, NSString *error){
				TGAlertView *result = [[TGAlertView alloc]
						initWithTitle:ok ? @"Gift Code" : @"Gift Code Failed"
							  message:ok ? @"The code was applied to this account."
										 : (error.length ? error
														 : @"The code could not be redeemed.")
					cancelButtonTitle:@"OK"
						okButtonTitle:nil
					  completionBlock:nil];
				[result show];
				if (ok && weakSelf)
					[weakSelf load];
			}];
		}];
		[alert show];
	}];
}

- (void)showGiveaway:(NSDictionary *)entry {
	int64_t messageId = [entry[@"messageId"] longLongValue];
	int64_t chatId = [entry[@"chatId"] longLongValue];
	NSString *title = [entry[@"chatTitle"] isKindOfClass:[NSString class]]
			&& [entry[@"chatTitle"] length] ? entry[@"chatTitle"] : @"Giveaway";
	if (messageId == 0 || chatId == 0)
		return;
	[[TGClient shared] giveawayInfoForMessage:messageId
									   inChat:chatId
								   completion:^(NSDictionary *info){
		NSString *message = nil;
		if (![info isKindOfClass:[NSDictionary class]]){
			message = @"This giveaway could not be loaded.";
		} else {
			NSMutableString *text = [NSMutableString string];
			NSString *status = [info[@"statusText"] isKindOfClass:[NSString class]]
					? info[@"statusText"] : @"";
			if (status.length)
				[text appendString:status];
			BOOL ongoing = [info[@"ongoing"] boolValue];
			if (!ongoing){
				NSString *winners = TGPremiumDateText(info[@"winnersDate"]);
				if (winners.length)
					[text appendFormat:@"%@Winners picked %@",
							text.length ? @"\n" : @"", winners];
				NSInteger winnerCount = [info[@"winnerCount"] integerValue];
				if (winnerCount > 0)
					[text appendFormat:@"\n%d winners", (int)winnerCount];
				if ([info[@"refunded"] boolValue])
					[text appendString:@"\nThe giveaway was refunded."];
				NSString *code = [info[@"giftCode"] isKindOfClass:[NSString class]]
						? info[@"giftCode"] : @"";
				if ([info[@"winner"] boolValue])
					[text appendFormat:@"\nThis account won%@",
							code.length ? [NSString stringWithFormat:@": %@", code] : @""];
			} else {
				NSString *created = TGPremiumDateText(info[@"creationDate"]);
				if (created.length)
					[text appendFormat:@"%@Started %@", text.length ? @"\n" : @"", created];
			}
			message = text.length ? text : @"No details for this giveaway.";
		}
		TGAlertView *alert = [[TGAlertView alloc] initWithTitle:title
														message:message
											  cancelButtonTitle:@"OK"
												  okButtonTitle:nil
												completionBlock:nil];
		[alert show];
	}];
}

- (void)showSlotActions:(NSDictionary *)slot {
	int64_t slotChat = [slot[@"chatId"] longLongValue];
	if (slotChat == 0)
		return;
	self.sheetChatId = slotChat;

	NSArray *actions = @[
		[[TGActionSheetAction alloc] initWithTitle:@"Boost Status" action:@"status"],
		[[TGActionSheetAction alloc] initWithTitle:@"Who Boosted" action:@"boosters"],
		[[TGActionSheetAction alloc] initWithTitle:@"Copy Boost Link" action:@"link"],
		[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
											  type:TGActionSheetActionTypeCancel]
	];

	__weak typeof(self) weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc]
			initWithTitle:nil
				  actions:actions
			  actionBlock:^(id target, NSString *action){
		if (!weakSelf)
			return;
		if ([action isEqualToString:@"status"])
			[weakSelf showBoostStatusForChat:weakSelf.sheetChatId];
		else if ([action isEqualToString:@"boosters"])
			[weakSelf pushBoostersForChat:weakSelf.sheetChatId];
		else if ([action isEqualToString:@"link"])
			[weakSelf copyBoostLinkForChat:weakSelf.sheetChatId];
	}
				   target:self];
	[sheet showInView:self.view];
}

- (void)pushBoostersForChat:(int64_t)chatId {
	TGPremiumListViewController *list = [[TGPremiumListViewController alloc]
			initWithMode:TGPremiumListBoosters chatId:chatId title:@"Boosters"];
	[self.navigationController pushViewController:list animated:YES];
}

- (void)copyBoostLinkForChat:(int64_t)chatId {
	[[TGClient shared] chatBoostLinkForChat:chatId
								 completion:^(NSString *url, BOOL isPublic){
		NSString *message = nil;
		if (url.length){
			[[UIPasteboard generalPasteboard] setString:url];
			message = [NSString stringWithFormat:@"%@\n\nCopied to the clipboard.%@",
					url, isPublic ? @"" : @" This chat is private, so the link only "
									"works for people who can already see it."];
		} else {
			message = @"The boost link could not be fetched.";
		}
		TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Boost Link"
														message:message
											  cancelButtonTitle:@"OK"
												  okButtonTitle:nil
												completionBlock:nil];
		[alert show];
	}];
}

- (void)showBoostStatusForChat:(int64_t)chatId {
	[[TGClient shared] chatBoostStatusForChat:chatId
								   completion:^(NSDictionary *status){
		NSString *message = nil;
		if (![status isKindOfClass:[NSDictionary class]]){
			message = @"The boost status could not be fetched.";
		} else {
			NSMutableString *text = [NSMutableString string];
			[text appendFormat:@"Level %d", (int)[status[@"level"] integerValue]];
			[text appendFormat:@"\n%d boosts", (int)[status[@"boostCount"] integerValue]];
			NSInteger next = [status[@"nextLevelBoostCount"] integerValue];
			NSInteger current = [status[@"boostCount"] integerValue];
			if (next > current)
				[text appendFormat:@"\n%d more for the next level", (int)(next - current)];
			NSInteger gifted = [status[@"giftCodeBoostCount"] integerValue];
			if (gifted > 0)
				[text appendFormat:@"\n%d from gift codes", (int)gifted];
			NSInteger premiumMembers = [status[@"premiumMemberCount"] integerValue];
			if (premiumMembers > 0)
				[text appendFormat:@"\n%d Premium members (%.1f%%)", (int)premiumMembers,
						[status[@"premiumMemberPercentage"] doubleValue]];
			if ([status[@"boosted"] boolValue])
				[text appendString:@"\nThis account boosts this chat."];
			id prepaid = status[@"prepaidGiveaways"];
			if ([prepaid isKindOfClass:[NSArray class]] && [prepaid count])
				[text appendFormat:@"\n%d prepaid giveaways waiting to be launched.",
						(int)[prepaid count]];
			message = text;
		}
		TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Boosts"
														message:message
											  cancelButtonTitle:@"OK"
												  okButtonTitle:nil
												completionBlock:nil];
		[alert show];
	}];
}

@end

enum {
	TGPremiumPromptNone = 0,
	TGPremiumPromptRedeem,
	TGPremiumPromptCheck,
	TGPremiumPromptBoostLink
};

enum {
	TGPremiumSectionAccount = 0,
	TGPremiumSectionLimits,
	TGPremiumSectionFeatures,
	TGPremiumSectionBoosts,
	TGPremiumSectionGiftCode,
	TGPremiumSectionCount
};

@interface TGPremiumViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) NSDictionary *subscription;
@property (nonatomic, strong) NSDictionary *options;
@property (nonatomic, strong) NSArray *limits;
@property (nonatomic, strong) NSArray *features;
@property (nonatomic, strong) NSArray *slots;
@property (nonatomic, assign) BOOL subscriptionLoaded;
@property (nonatomic, assign) BOOL optionsLoaded;
@property (nonatomic, assign) BOOL limitsLoaded;
@property (nonatomic, assign) BOOL featuresLoaded;
@property (nonatomic, assign) BOOL slotsLoaded;
@property (nonatomic, assign) NSInteger trialRemaining;
@property (nonatomic, assign) NSInteger trialWeekly;
@property (nonatomic, assign) NSTimeInterval trialCooldownUntil;
@property (nonatomic, assign) NSInteger trialPending;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerStatusLabel;
@property (nonatomic, strong) UIImageView *headerBadgeView;
@property (nonatomic, assign) BOOL stickerShown;
@property (nonatomic, assign) NSInteger prompt;
@end

@implementation TGPremiumViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Telegram Premium";
	self.limits = @[];
	self.features = @[];
	self.slots = @[];
	self.trialRemaining = -1;

	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.sectionFooterHeight = 1;
	if (self.navigationController.navigationBar)
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	UIButton *reload = [TGIcons headerButtonWithTitle:@"Reload" bold:NO
											   target:self action:@selector(reloadTapped)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:reload];

	[self buildHeader];
	[self load];
}

- (void)reloadTapped {
	self.subscriptionLoaded = NO;
	self.optionsLoaded = NO;
	self.limitsLoaded = NO;
	self.featuresLoaded = NO;
	self.slotsLoaded = NO;
	self.trialPending = 0;
	self.trialRemaining = -1;
	self.trialWeekly = 0;
	self.trialCooldownUntil = 0;
	[self.tableView reloadData];
	[self load];
}

#pragma mark - header

- (void)buildHeader {
	CGFloat width = self.view.bounds.size.width ?: 320;
	UIView *header = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, kPremiumHeaderHeight)];
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
	title.text = @"Telegram Premium";
	title.font = [UIFont boldSystemFontOfSize:19];
	title.backgroundColor = [UIColor clearColor];
	title.textColor = dark ? [[TGTheme shared] primaryTextColour] : TGPremiumRGB(0x222932);
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
	status.textColor = dark ? [[TGTheme shared] secondaryTextColour] : TGPremiumRGB(0x6d7d90);
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
	if (!self.headerStatusLabel)
		return;

	BOOL active = [[TGClient shared] isPremiumAccount];
	NSString *line = nil;

	if (self.subscription){
		active = [self.subscription[@"active"] boolValue];
		NSString *expires = self.subscription[@"expiresText"];
		NSString *text = self.subscription[@"text"];
		if ([expires isKindOfClass:[NSString class]] && expires.length)
			line = expires;
		else if ([text isKindOfClass:[NSString class]] && text.length)
			line = text;
	} else if (!self.subscriptionLoaded){
		line = @"checking...";
	}

	if (!line.length)
		line = active ? @"Active on this account" : @"Not active on this account";
	self.headerStatusLabel.text = line;
	if (!self.stickerShown)
		self.headerBadgeView.image = [TGIcons avatarWithInitials:@"★" size:70
														colourId:active ? 2 : 6];
}

#pragma mark - loading

- (void)load {
	__weak typeof(self) weakSelf = self;

	[[TGClient shared] premiumSubscriptionWithCompletion:^(NSDictionary *info){
		weakSelf.subscription = [info isKindOfClass:[NSDictionary class]] ? info : nil;
		weakSelf.subscriptionLoaded = YES;
		[weakSelf refreshHeader];
		[weakSelf.tableView reloadData];
	}];

	[[TGClient shared] premiumOptionsWithCompletion:^(NSDictionary *options){
		weakSelf.options = [options isKindOfClass:[NSDictionary class]] ? options : nil;
		weakSelf.optionsLoaded = YES;
		[weakSelf.tableView reloadData];
	}];

	[[TGClient shared] premiumLimitsWithCompletion:^(NSArray *limits){
		weakSelf.limits = [limits isKindOfClass:[NSArray class]] ? limits : @[];
		weakSelf.limitsLoaded = YES;
		[weakSelf.tableView reloadData];
	}];

	[[TGClient shared] premiumFeaturesWithCompletion:^(NSArray *features){
		weakSelf.features = [features isKindOfClass:[NSArray class]] ? features : @[];
		weakSelf.featuresLoaded = YES;
		[weakSelf.tableView reloadData];
	}];

	if (!self.stickerShown)
		[self loadHeaderSticker];

	[self loadTranscriptionTrial];

	[[TGClient shared] availableBoostSlotsWithCompletion:^(NSArray *slots){
		weakSelf.slots = [slots isKindOfClass:[NSArray class]] ? slots : @[];
		weakSelf.slotsLoaded = YES;
		[weakSelf.tableView reloadData];
	}];
}

- (void)loadHeaderSticker {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] premiumInfoStickerForMonths:0 completion:^(NSDictionary *sticker){
		if (![sticker isKindOfClass:[NSDictionary class]])
			return;
		NSInteger fileId = [sticker[@"thumbnailFileId"] integerValue];
		if (fileId <= 0)
			fileId = [sticker[@"fileId"] integerValue];
		if (fileId <= 0)
			return;
		[[TGClient shared] downloadFile:fileId completion:^(NSString *path){
			if (!path.length || !weakSelf)
				return;
			UIImage *image = [UIImage imageWithContentsOfFile:path];
			if (!image)
				return;
			weakSelf.stickerShown = YES;
			weakSelf.headerBadgeView.contentMode = UIViewContentModeScaleAspectFit;
			weakSelf.headerBadgeView.image = image;
		}];
	}];
}

- (void)loadTranscriptionTrial {
	__weak typeof(self) weakSelf = self;
	self.trialPending = 3;

	[[TGClient shared] optionNamed:@"speech_recognition_trial_count"
						completion:^(id value){
		if ([value isKindOfClass:[NSNumber class]])
			weakSelf.trialRemaining = [value integerValue];
		[weakSelf trialPartArrived];
	}];

	[[TGClient shared] optionNamed:@"speech_recognition_trial_weekly_number"
						completion:^(id value){
		if ([value isKindOfClass:[NSNumber class]])
			weakSelf.trialWeekly = [value integerValue];
		[weakSelf trialPartArrived];
	}];

	[[TGClient shared] optionNamed:@"speech_recognition_trial_cooldown_until"
						completion:^(id value){
		if ([value isKindOfClass:[NSNumber class]])
			weakSelf.trialCooldownUntil = [value doubleValue];
		[weakSelf trialPartArrived];
	}];
}

- (void)trialPartArrived {
	if (self.trialPending > 0)
		self.trialPending--;
	if (self.trialPending == 0)
		[self.tableView reloadData];
}

- (BOOL)showsTranscriptionRow {
	return self.trialPending == 0 && (self.trialRemaining >= 0 || self.trialWeekly > 0);
}

- (NSString *)transcriptionTrialText {
	if ([[TGClient shared] isPremiumAccount] || [self.options[@"isPremium"] boolValue])
		return @"Unlimited";

	NSInteger left = self.trialRemaining < 0 ? 0 : self.trialRemaining;
	if (left > 0){
		if (self.trialWeekly > 0)
			return [NSString stringWithFormat:@"%d of %d left",
					(int)left, (int)self.trialWeekly];
		return [NSString stringWithFormat:@"%d left", (int)left];
	}

	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	if (self.trialCooldownUntil > now){
		static NSDateFormatter *formatter = nil;
		if (!formatter){
			formatter = [[NSDateFormatter alloc] init];
			formatter.dateStyle = NSDateFormatterShortStyle;
			formatter.timeStyle = NSDateFormatterShortStyle;
		}
		NSDate *date = [NSDate dateWithTimeIntervalSince1970:self.trialCooldownUntil];
		return [NSString stringWithFormat:@"Resets %@", [formatter stringFromDate:date]];
	}
	return @"None left";
}

#pragma mark - shape

- (NSString *)titleForSection:(NSInteger)section {
	switch (section){
		case TGPremiumSectionAccount:  return @"This account";
		case TGPremiumSectionLimits:   return @"Limits — now / with Premium";
		case TGPremiumSectionFeatures: return @"What Premium gives you";
		case TGPremiumSectionBoosts:   return @"Channel boosts";
		default:                       return @"Gift codes";
	}
}

- (NSString *)commentForSection:(NSInteger)section {
	if (section == TGPremiumSectionFeatures && self.features.count)
		return @"Dimmed rows are features this client cannot show.";
	if (section == TGPremiumSectionGiftCode)
		return @"Premium cannot be bought here. A gift code from a giveaway or a "
				"friend can still be redeemed on this account.";
	if (section == TGPremiumSectionBoosts && self.slotsLoaded && !self.slots.count)
		return @"Boost slots come with a Premium subscription.";
	return nil;
}

- (NSInteger)contentRowsInSection:(NSInteger)section {
	switch (section){
		case TGPremiumSectionAccount:
			if (!self.optionsLoaded)
				return 1;
			return [self showsTranscriptionRow] ? 5 : 4;
		case TGPremiumSectionLimits:
			return self.limits.count ? (NSInteger)self.limits.count : 1;
		case TGPremiumSectionFeatures:
			return self.features.count ? (NSInteger)self.features.count + 1 : 1;
		case TGPremiumSectionBoosts:
			return self.slotsLoaded ? 4 : 1;
		default:
			return 3;
	}
}

- (BOOL)isCommentRow:(NSIndexPath *)indexPath {
	return [self commentForSection:indexPath.section] != nil
			&& indexPath.row == [self contentRowsInSection:indexPath.section];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return TGPremiumSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [self contentRowsInSection:section] + ([self commentForSection:section] ? 1 : 0);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return kPremiumSectionHeaderHeight;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	BOOL dark = [[TGTheme shared] isDark];

	UILabel *label = [[UILabel alloc] init];
	label.text = [self titleForSection:section];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont boldSystemFontOfSize:17];
	label.textColor = dark ? [[TGTheme shared] secondaryTextColour] : TGPremiumRGB(0x697487);
	if (!dark){
		label.shadowColor = TGPremiumRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 21, 16);

	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, kPremiumSectionHeaderHeight)];
	container.backgroundColor = [UIColor clearColor];
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	return 1;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	UIView *spacer = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, 1)];
	spacer.backgroundColor = [UIColor clearColor];
	return spacer;
}

- (UIFont *)commentFont {
	return [UIFont systemFontOfSize:14];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isCommentRow:indexPath]){
		CGFloat width = tableView.bounds.size.width ?: 320;
		CGSize size = [[self commentForSection:indexPath.section]
				sizeWithFont:[self commentFont]
				constrainedToSize:CGSizeMake(width - 12 * 2, 1000)
				lineBreakMode:NSLineBreakByWordWrapping];
		return size.height + 7 * 2;
	}
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
	if ([cell.detailTextLabel respondsToSelector:@selector(setAttributedText:)])
		cell.detailTextLabel.attributedText = nil;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.font = [UIFont systemFontOfSize:16];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.textLabel.shadowColor = nil;
	cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	[[TGTheme shared] styleCell:cell];
	return cell;
}

- (UITableViewCell *)commentCellInTable:(UITableView *)tableView text:(NSString *)text {
	static NSString *reuseId = @"TGPremiumComment";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
	UILabel *label = nil;
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:reuseId];
		cell.backgroundColor = [UIColor clearColor];
		cell.backgroundView = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		label = [[UILabel alloc] initWithFrame:CGRectMake(12, 7,
				cell.contentView.bounds.size.width - 24, cell.contentView.bounds.size.height - 14)];
		label.tag = 4001;
		label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		label.textAlignment = NSTextAlignmentCenter;
		label.font = [self commentFont];
		label.backgroundColor = [UIColor clearColor];
		label.numberOfLines = 0;
		[cell.contentView addSubview:label];
	} else {
		label = (UILabel *)[cell.contentView viewWithTag:4001];
	}

	BOOL dark = [[TGTheme shared] isDark];
	label.textColor = dark ? [[TGTheme shared] secondaryTextColour] : TGPremiumRGB(0x697487);
	label.shadowColor = dark ? nil : TGPremiumRGB(0xdae0e8);
	label.shadowOffset = dark ? CGSizeZero : CGSizeMake(0, 1);
	label.text = text;
	return cell;
}

- (UITableViewCell *)statusCellInTable:(UITableView *)tableView text:(NSString *)text {
	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleDefault
										   reuseId:@"TGPremiumStatus"];
	cell.textLabel.text = text;
	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	return cell;
}

- (NSString *)formattedNumber:(NSNumber *)value {
	if (![value isKindOfClass:[NSNumber class]])
		return @"-";
	long long raw = [value longLongValue];
	if (raw >= 1000){
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

- (NSString *)formattedSize:(long long)bytes {
	if (bytes <= 0)
		return @"-";
	double mb = bytes / (1024.0 * 1024.0);
	if (mb >= 1024.0)
		return [NSString stringWithFormat:@"%.0f GB", mb / 1024.0];
	return [NSString stringWithFormat:@"%.0f MB", mb];
}

- (void)setComparisonOnCell:(UITableViewCell *)cell
					   free:(NSString *)freeValue
					premium:(NSString *)premiumValue
{
	NSString *plain = [NSString stringWithFormat:@"%@ → %@", freeValue, premiumValue];
	UIColor *freeColour = [[TGTheme shared] secondaryTextColour];
	UIColor *premiumColour = [[TGTheme shared] cellDetailColour];

	if (![cell.detailTextLabel respondsToSelector:@selector(setAttributedText:)]
			|| !NSClassFromString(@"NSMutableAttributedString")){
		cell.detailTextLabel.text = plain;
		cell.detailTextLabel.textColor = premiumColour;
		return;
	}

	NSMutableAttributedString *value =
			[[NSMutableAttributedString alloc] initWithString:plain];
	[value addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15]
				  range:NSMakeRange(0, plain.length)];
	[value addAttribute:NSForegroundColorAttributeName value:freeColour
				  range:NSMakeRange(0, freeValue.length + 3)];
	[value addAttribute:NSForegroundColorAttributeName value:premiumColour
				  range:NSMakeRange(freeValue.length + 3, plain.length - freeValue.length - 3)];
	cell.detailTextLabel.attributedText = value;
}

- (BOOL)featureIsSupported:(NSDictionary *)feature {
	id supported = feature[@"supported"];
	return ![supported isKindOfClass:[NSNumber class]] || [supported boolValue];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ([self isCommentRow:indexPath])
		return [self commentCellInTable:tableView
								   text:[self commentForSection:indexPath.section]];

	if (indexPath.section == TGPremiumSectionAccount){
		if (!self.optionsLoaded)
			return [self statusCellInTable:tableView text:@"Loading..."];
		UITableViewCell *cell = [self plainCellInTable:tableView
												 style:UITableViewCellStyleValue1
											   reuseId:@"TGPremiumOption"];
		switch (indexPath.row){
			case 0:
				cell.textLabel.text = @"Premium";
				cell.detailTextLabel.text = [self.options[@"isPremium"] boolValue]
						? @"Active" : @"Off";
				break;
			case 1:
				cell.textLabel.text = @"Download speed";
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%@x",
						[self formattedNumber:self.options[@"downloadSpeedup"]]];
				break;
			case 2:
				cell.textLabel.text = @"Max upload size";
				cell.detailTextLabel.text = [self formattedSize:
						[self.options[@"maxUploadFileSize"] longLongValue]];
				break;
			case 3:
				cell.textLabel.text = @"Stars";
				cell.detailTextLabel.text = [self formattedNumber:self.options[@"starCount"]];
				break;
			default:
				cell.textLabel.text = @"Voice transcription";
				cell.detailTextLabel.text = [self transcriptionTrialText];
				break;
		}
		return cell;
	}

	if (indexPath.section == TGPremiumSectionLimits){
		if (!self.limits.count)
			return [self statusCellInTable:tableView
									  text:self.limitsLoaded ? @"Limits unavailable"
															 : @"Loading limits..."];
		id rawLimit = self.limits[indexPath.row];
		if (![rawLimit isKindOfClass:[NSDictionary class]])
			return [self statusCellInTable:tableView text:@"-"];
		NSDictionary *limit = rawLimit;
		UITableViewCell *cell = [self plainCellInTable:tableView
												 style:UITableViewCellStyleValue1
											   reuseId:@"TGPremiumLimit"];
		NSString *title = limit[@"title"];
		cell.textLabel.text = [title isKindOfClass:[NSString class]] && title.length
				? title : limit[@"type"];
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		[self setComparisonOnCell:cell
							 free:[self formattedNumber:limit[@"default"]]
						  premium:[self formattedNumber:limit[@"premium"]]];
		return cell;
	}

	if (indexPath.section == TGPremiumSectionFeatures){
		if (!self.features.count)
			return [self statusCellInTable:tableView
									  text:self.featuresLoaded ? @"Feature list unavailable"
															   : @"Loading features..."];
		if (indexPath.row == (NSInteger)self.features.count){
			UITableViewCell *cell = [self plainCellInTable:tableView
													 style:UITableViewCellStyleValue1
												   reuseId:@"TGPremiumBusiness"];
			cell.textLabel.text = @"Telegram Business";
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
			return cell;
		}
		id rawFeature = self.features[indexPath.row];
		if (![rawFeature isKindOfClass:[NSDictionary class]])
			return [self statusCellInTable:tableView text:@"-"];
		NSDictionary *feature = rawFeature;
		UITableViewCell *cell = [self plainCellInTable:tableView
												 style:UITableViewCellStyleSubtitle
											   reuseId:@"TGPremiumFeature"];
		BOOL supported = [self featureIsSupported:feature];
		NSString *title = feature[@"title"];
		cell.textLabel.text = [title isKindOfClass:[NSString class]] && title.length
				? title : feature[@"type"];
		cell.textLabel.textColor = supported
				? [[TGTheme shared] primaryTextColour]
				: TGPremiumRGB(0xb0b0b0);
		NSString *subtitle = feature[@"subtitle"];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
		if (supported){
			cell.detailTextLabel.text = [subtitle isKindOfClass:[NSString class]] ? subtitle : @"";
			cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		} else {
			cell.detailTextLabel.text = @"Not available in this client";
			cell.detailTextLabel.textColor = TGPremiumRGB(0xb0b0b0);
		}
		return cell;
	}

	if (indexPath.section == TGPremiumSectionBoosts){
		if (!self.slotsLoaded)
			return [self statusCellInTable:tableView text:@"Loading boost slots..."];
		UITableViewCell *cell = [self plainCellInTable:tableView
												 style:UITableViewCellStyleValue1
											   reuseId:@"TGPremiumBoost"];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		switch (indexPath.row){
			case 0: {
				NSInteger free = 0;
				for (NSDictionary *slot in self.slots){
					if ([slot isKindOfClass:[NSDictionary class]]
							&& [slot[@"free"] boolValue])
						free++;
				}
				cell.textLabel.text = @"Boost slots";
				cell.detailTextLabel.text = self.slots.count
						? [NSString stringWithFormat:@"%d free of %d",
								(int)free, (int)self.slots.count]
						: @"None";
				break;
			}
			case 1:
				cell.textLabel.text = @"What Boosts Unlock";
				break;
			case 2:
				cell.textLabel.text = @"Giveaways I Entered";
				break;
			default:
				cell.textLabel.text = @"Open a Boost Link...";
				cell.accessoryType = UITableViewCellAccessoryNone;
				break;
		}
		return cell;
	}

	if (indexPath.row == 0){
		UITableViewCell *cell = [self plainCellInTable:tableView
												 style:UITableViewCellStyleValue1
											   reuseId:@"TGPremiumBoost"];
		cell.textLabel.text = @"Codes Sent to Me";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleDefault
										   reuseId:@"TGPremiumAction"];
	cell.textLabel.text = indexPath.row == 1 ? @"Check a Code..."
											 : @"Redeem a Gift Code...";
	cell.textLabel.font = indexPath.row == 1 ? [UIFont systemFontOfSize:16]
											 : [UIFont boldSystemFontOfSize:16];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.textLabel.textColor = [[TGTheme shared] accentColour];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

#pragma mark - taps

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if ([self isCommentRow:indexPath])
		return;

	if (indexPath.section == TGPremiumSectionLimits && self.limits.count){
		id rawLimit = self.limits[indexPath.row];
		if (![rawLimit isKindOfClass:[NSDictionary class]])
			return;
		[self showLimitDetail:rawLimit];
		return;
	}

	if (indexPath.section == TGPremiumSectionBoosts && self.slotsLoaded){
		switch (indexPath.row){
			case 0:
				[self pushListWithMode:TGPremiumListBoostSlots title:@"Boost Slots"];
				break;
			case 1:
				[self pushListWithMode:TGPremiumListBoostLevels title:@"Boost Levels"];
				break;
			case 2:
				[self pushListWithMode:TGPremiumListGiveaways title:@"Giveaways"];
				break;
			default:
				[self promptWithKind:TGPremiumPromptBoostLink
							   title:@"Boost Link"
							 message:@"Paste a t.me/boost link to see the channel's boosts."
								  ok:@"Open"];
				break;
		}
		return;
	}

	if (indexPath.section == TGPremiumSectionFeatures && self.features.count){
		if (indexPath.row == (NSInteger)self.features.count){
			[self pushListWithMode:TGPremiumListBusiness title:@"Telegram Business"];
			return;
		}
		id rawFeature = self.features[indexPath.row];
		if (![rawFeature isKindOfClass:[NSDictionary class]])
			return;
		NSDictionary *feature = rawFeature;
		if (![self featureIsSupported:feature])
			return;
		NSString *type = feature[@"type"];
		if ([type isKindOfClass:[NSString class]] && type.length)
			[[TGClient shared] viewPremiumFeature:type];
		NSString *subtitle = feature[@"subtitle"];
		if (![subtitle isKindOfClass:[NSString class]] || !subtitle.length)
			return;
		TGAlertView *alert = [[TGAlertView alloc] initWithTitle:feature[@"title"]
														message:subtitle
											  cancelButtonTitle:@"OK"
												  okButtonTitle:nil
												completionBlock:nil];
		[alert show];
		return;
	}

	if (indexPath.section != TGPremiumSectionGiftCode)
		return;

	if (indexPath.row == 0){
		[self pushListWithMode:TGPremiumListGiftCodes title:@"Gift Codes"];
		return;
	}
	if (indexPath.row == 1){
		[self promptWithKind:TGPremiumPromptCheck
					   title:@"Check a Code"
					 message:@"Enter a gift code to look it up without using it."
						  ok:@"Check"];
		return;
	}
	[self askForGiftCode];
}

- (void)pushListWithMode:(NSInteger)mode title:(NSString *)title {
	TGPremiumListViewController *list = [[TGPremiumListViewController alloc]
			initWithMode:mode chatId:0 title:title];
	[self.navigationController pushViewController:list animated:YES];
}

- (void)showLimitDetail:(NSDictionary *)limit {
	NSString *type = [limit[@"type"] isKindOfClass:[NSString class]] ? limit[@"type"] : @"";
	NSString *title = [limit[@"title"] isKindOfClass:[NSString class]]
			&& [limit[@"title"] length] ? limit[@"title"] : type;
	if (!type.length)
		return;
	BOOL premium = [[TGClient shared] isPremiumAccount];
	[[TGClient shared] premiumLimit:type completion:^(NSDictionary *fresh){
		NSDictionary *shown = [fresh isKindOfClass:[NSDictionary class]] ? fresh : limit;
		NSString *message = [NSString stringWithFormat:
				@"Without Premium: %d\nWith Premium: %d\n\nThis account: %d",
				(int)[shown[@"default"] integerValue],
				(int)[shown[@"premium"] integerValue],
				(int)[shown[premium ? @"premium" : @"default"] integerValue]];
		TGAlertView *alert = [[TGAlertView alloc] initWithTitle:title
														message:message
											  cancelButtonTitle:@"OK"
												  okButtonTitle:nil
												completionBlock:nil];
		[alert show];
	}];
}

- (void)promptWithKind:(NSInteger)kind
				 title:(NSString *)title
			   message:(NSString *)message
					ok:(NSString *)ok
{
	self.prompt = kind;
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
													message:message
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:ok, nil];
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	[alert show];
}

- (void)askForGiftCode {
	[self promptWithKind:TGPremiumPromptRedeem
				   title:@"Gift Code"
				 message:@"Enter the code from a t.me/giftcode link."
					  ok:@"Redeem"];
}

- (void)showBoostsForLink:(NSString *)url {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatBoostLinkInfo:url completion:^(int64_t chatId, BOOL isPublic){
		if (chatId == 0){
			TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Boost Link"
															message:@"That link could not be resolved."
												  cancelButtonTitle:@"OK"
													  okButtonTitle:nil
													completionBlock:nil];
			[alert show];
			return;
		}
		if (!weakSelf)
			return;
		TGPremiumListViewController *list = [[TGPremiumListViewController alloc]
				initWithMode:TGPremiumListBoosters chatId:chatId title:@"Boosters"];
		[weakSelf.navigationController pushViewController:list animated:YES];
	}];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	NSInteger kind = self.prompt;
	self.prompt = TGPremiumPromptNone;
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	if (![alertView respondsToSelector:@selector(textFieldAtIndex:)])
		return;

	NSString *entered = [[alertView textFieldAtIndex:0].text
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!entered.length)
		return;

	if (kind == TGPremiumPromptBoostLink){
		[self showBoostsForLink:entered];
		return;
	}

	NSString *code = entered;
	NSRange slash = [code rangeOfString:@"/" options:NSBackwardsSearch];
	if (slash.location != NSNotFound && slash.location + 1 < code.length)
		code = [code substringFromIndex:slash.location + 1];

	if (kind == TGPremiumPromptCheck){
		[self checkCode:code];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] redeemGiftCode:code
						   completion:^(BOOL ok, NSDictionary *info, NSString *error){
		NSString *message = nil;
		if (ok){
			NSInteger months = [info[@"months"] integerValue];
			message = months > 0
					? [NSString stringWithFormat:@"Premium is active for %d months.", (int)months]
					: @"The code was applied to this account.";
		} else {
			message = error.length ? error : @"The code could not be redeemed.";
		}
		TGAlertView *result = [[TGAlertView alloc] initWithTitle:ok ? @"Gift Code" : @"Gift Code Failed"
														message:message
											  cancelButtonTitle:@"OK"
												  okButtonTitle:nil
												completionBlock:nil];
		[result show];
		if (ok)
			[weakSelf reloadTapped];
	}];
}

- (void)checkCode:(NSString *)code {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] checkGiftCode:code completion:^(NSDictionary *info){
		if (![info isKindOfClass:[NSDictionary class]]){
			TGAlertView *fail = [[TGAlertView alloc] initWithTitle:@"Gift Code"
														   message:@"That code is not valid."
												 cancelButtonTitle:@"OK"
													 okButtonTitle:nil
												   completionBlock:nil];
			[fail show];
			return;
		}
		NSMutableString *message = [NSMutableString string];
		NSInteger months = [info[@"months"] integerValue];
		if (months > 0)
			[message appendFormat:@"%d months of Premium\n", (int)months];
		if ([info[@"fromGiveaway"] boolValue])
			[message appendString:@"From a giveaway\n"];
		NSString *created = TGPremiumDateText(info[@"creationDate"]);
		if (created.length)
			[message appendFormat:@"Created %@\n", created];

		if ([info[@"used"] boolValue]){
			NSString *usedDate = TGPremiumDateText(info[@"useDate"]);
			[message appendFormat:@"Already used%@",
					usedDate.length ? [NSString stringWithFormat:@" on %@", usedDate] : @""];
			TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Gift Code"
															message:message
												  cancelButtonTitle:@"OK"
													  okButtonTitle:nil
													completionBlock:nil];
			[alert show];
			return;
		}

		[message appendString:@"Not used yet"];
		TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Gift Code"
														message:message
											  cancelButtonTitle:@"Close"
												  okButtonTitle:@"Redeem"
												completionBlock:^(bool okPressed){
			if (!okPressed)
				return;
			[[TGClient shared] applyGiftCode:code completion:^(BOOL ok, NSString *error){
				TGAlertView *result = [[TGAlertView alloc]
						initWithTitle:ok ? @"Gift Code" : @"Gift Code Failed"
							  message:ok ? @"The code was applied to this account."
										 : (error.length ? error
														 : @"The code could not be redeemed.")
					cancelButtonTitle:@"OK"
						okButtonTitle:nil
					  completionBlock:nil];
				[result show];
				if (ok)
					[weakSelf reloadTapped];
			}];
		}];
		[alert show];
	}];
}

@end

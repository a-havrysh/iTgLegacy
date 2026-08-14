#import "TGPremiumViewController.h"
#import "TGClient.h"
#import "TGClient+Premium.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGAlertView.h"

static const CGFloat kPremiumHeaderHeight = 86.0f;

static inline UIColor *TGPremiumRGB(unsigned int value) {
	return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0f
						   green:((value >> 8) & 0xff) / 255.0f
							blue:(value & 0xff) / 255.0f
						   alpha:1.0f];
}

enum {
	TGPremiumSectionLimits = 0,
	TGPremiumSectionFeatures,
	TGPremiumSectionAccount,
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
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerStatusLabel;
@property (nonatomic, strong) UIImageView *headerBadgeView;
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

	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
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
	badge.layer.cornerRadius = 6.0f;
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
		line = active ? @"Active" : @"Not subscribed";
	self.headerStatusLabel.text = line;
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

	[[TGClient shared] availableBoostSlotsWithCompletion:^(NSArray *slots){
		weakSelf.slots = [slots isKindOfClass:[NSArray class]] ? slots : @[];
		weakSelf.slotsLoaded = YES;
		[weakSelf.tableView reloadData];
	}];
}

#pragma mark - shape

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return TGPremiumSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section){
		case TGPremiumSectionLimits:
			return self.limits.count ? (NSInteger)self.limits.count : 1;
		case TGPremiumSectionFeatures:
			return self.features.count ? (NSInteger)self.features.count : 1;
		case TGPremiumSectionAccount:
			return self.optionsLoaded ? 4 : 1;
		case TGPremiumSectionBoosts:
			return 1;
		default:
			return 1;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section){
		case TGPremiumSectionLimits:   return @"Limits (free / premium)";
		case TGPremiumSectionFeatures: return @"What Premium gives you";
		case TGPremiumSectionAccount:  return @"This account";
		case TGPremiumSectionBoosts:   return @"Channel boosts";
		default:                       return @"Gift codes";
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == TGPremiumSectionFeatures)
		return @"Dimmed rows are features this client cannot show.";
	if (section == TGPremiumSectionGiftCode)
		return @"Premium cannot be bought here. A gift code from a giveaway or a "
				"friend can still be redeemed on this account.";
	if (section == TGPremiumSectionBoosts && self.slotsLoaded && !self.slots.count)
		return @"Boost slots come with a Premium subscription.";
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
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
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [UIColor blackColor];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.textColor = TGPremiumRGB(0x356596);
	[[TGTheme shared] styleCell:cell];
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

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.section == TGPremiumSectionLimits){
		if (!self.limits.count)
			return [self statusCellInTable:tableView
									  text:self.limitsLoaded ? @"Limits unavailable"
															 : @"Loading limits..."];
		NSDictionary *limit = self.limits[indexPath.row];
		UITableViewCell *cell = [self plainCellInTable:tableView
												 style:UITableViewCellStyleValue1
											   reuseId:@"TGPremiumLimit"];
		NSString *title = limit[@"title"];
		cell.textLabel.text = [title isKindOfClass:[NSString class]] && title.length
				? title : limit[@"type"];
		cell.textLabel.font = [UIFont systemFontOfSize:16];
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ → %@",
				[self formattedNumber:limit[@"default"]],
				[self formattedNumber:limit[@"premium"]]];
		return cell;
	}

	if (indexPath.section == TGPremiumSectionFeatures){
		if (!self.features.count)
			return [self statusCellInTable:tableView
									  text:self.featuresLoaded ? @"Feature list unavailable"
															   : @"Loading features..."];
		NSDictionary *feature = self.features[indexPath.row];
		UITableViewCell *cell = [self plainCellInTable:tableView
												 style:UITableViewCellStyleSubtitle
											   reuseId:@"TGPremiumFeature"];
		BOOL supported = ![feature[@"supported"] isKindOfClass:[NSNumber class]]
				|| [feature[@"supported"] boolValue];
		NSString *title = feature[@"title"];
		cell.textLabel.text = [title isKindOfClass:[NSString class]] && title.length
				? title : feature[@"type"];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.textLabel.textColor = supported
				? [[TGTheme shared] primaryTextColour]
				: [UIColor colorWithWhite:0.0f alpha:0.35f];
		NSString *subtitle = feature[@"subtitle"];
		cell.detailTextLabel.text = [subtitle isKindOfClass:[NSString class]] ? subtitle : @"";
		cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
		cell.detailTextLabel.textColor = TGPremiumRGB(0x697487);
		cell.selectionStyle = supported ? UITableViewCellSelectionStyleBlue
										: UITableViewCellSelectionStyleNone;
		return cell;
	}

	if (indexPath.section == TGPremiumSectionAccount){
		if (!self.optionsLoaded)
			return [self statusCellInTable:tableView text:@"Loading..."];
		UITableViewCell *cell = [self plainCellInTable:tableView
												 style:UITableViewCellStyleValue1
											   reuseId:@"TGPremiumOption"];
		cell.textLabel.font = [UIFont systemFontOfSize:16];
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
				cell.textLabel.text = @"Upload limit";
				cell.detailTextLabel.text = [self formattedSize:
						[self.options[@"maxUploadFileSize"] longLongValue]];
				break;
			default:
				cell.textLabel.text = @"Stars";
				cell.detailTextLabel.text = [self formattedNumber:self.options[@"starCount"]];
				break;
		}
		return cell;
	}

	if (indexPath.section == TGPremiumSectionBoosts){
		if (!self.slotsLoaded)
			return [self statusCellInTable:tableView text:@"Loading boost slots..."];
		NSInteger free = 0;
		for (NSDictionary *slot in self.slots){
			if ([slot isKindOfClass:[NSDictionary class]] && [slot[@"free"] boolValue])
				free++;
		}
		UITableViewCell *cell = [self plainCellInTable:tableView
												 style:UITableViewCellStyleValue1
											   reuseId:@"TGPremiumBoost"];
		cell.textLabel.font = [UIFont systemFontOfSize:16];
		cell.textLabel.text = @"Boost slots";
		cell.detailTextLabel.text = self.slots.count
				? [NSString stringWithFormat:@"%d free of %d",
						(int)free, (int)self.slots.count]
				: @"None";
		return cell;
	}

	UITableViewCell *cell = [self plainCellInTable:tableView
											 style:UITableViewCellStyleDefault
										   reuseId:@"TGPremiumAction"];
	cell.textLabel.text = @"Redeem a Gift Code...";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.textLabel.textColor = TGPremiumRGB(0x0779d0);
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

#pragma mark - taps

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == TGPremiumSectionFeatures && self.features.count){
		NSDictionary *feature = self.features[indexPath.row];
		BOOL supported = ![feature[@"supported"] isKindOfClass:[NSNumber class]]
				|| [feature[@"supported"] boolValue];
		if (!supported)
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

	if (indexPath.section == TGPremiumSectionGiftCode)
		[self askForGiftCode];
}

- (void)askForGiftCode {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Gift Code"
													message:@"Enter the code from a t.me/giftcode link."
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Redeem", nil];
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	[alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	if (![alertView respondsToSelector:@selector(textFieldAtIndex:)])
		return;

	NSString *code = [[alertView textFieldAtIndex:0].text
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!code.length)
		return;

	NSRange slash = [code rangeOfString:@"/" options:NSBackwardsSearch];
	if (slash.location != NSNotFound && slash.location + 1 < code.length)
		code = [code substringFromIndex:slash.location + 1];

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

@end

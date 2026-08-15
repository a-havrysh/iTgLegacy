#import "TGPremiumViewController.h"
#import "TGClient.h"
#import "TGClient+Premium.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGAlertView.h"

static const CGFloat kPremiumHeaderHeight = 86.0f;
static const CGFloat kPremiumSectionHeaderHeight = 46.0f;

static inline UIColor *TGPremiumRGB(unsigned int value) {
	return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0f
						   green:((value >> 8) & 0xff) / 255.0f
							blue:(value & 0xff) / 255.0f
						   alpha:1.0f];
}

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
			return self.optionsLoaded ? 4 : 1;
		case TGPremiumSectionLimits:
			return self.limits.count ? (NSInteger)self.limits.count : 1;
		case TGPremiumSectionFeatures:
			return self.features.count ? (NSInteger)self.features.count : 1;
		default:
			return 1;
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
			default:
				cell.textLabel.text = @"Stars";
				cell.detailTextLabel.text = [self formattedNumber:self.options[@"starCount"]];
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
		NSInteger free = 0;
		for (NSDictionary *slot in self.slots){
			if ([slot isKindOfClass:[NSDictionary class]] && [slot[@"free"] boolValue])
				free++;
		}
		UITableViewCell *cell = [self plainCellInTable:tableView
												 style:UITableViewCellStyleValue1
											   reuseId:@"TGPremiumBoost"];
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
	cell.textLabel.textColor = [[TGTheme shared] accentColour];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

#pragma mark - taps

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if ([self isCommentRow:indexPath])
		return;

	if (indexPath.section == TGPremiumSectionFeatures && self.features.count){
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

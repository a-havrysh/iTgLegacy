#import "TGSettingsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGThemeFile.h"
#import "TGStorageViewController.h"
#import "TGSessionsViewController.h"
#import "TGDeviceViewController.h"
#import "TGDevice.h"
#import "TGEditProfileViewController.h"
#import "TGQRViewController.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "UIView+SafeTint.h"

// Their profile page: a 175dp coloured block with a 76dp picture on the left,
// the name beside it and the status under that. Scaled to a 320pt screen.
static const CGFloat kHeaderHeight = 86.0f;
static const CGFloat kHeaderAvatar = 70.0f;

static inline UIColor *TGSettingsRGB(unsigned int value) {
	return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0f
						   green:((value >> 8) & 0xff) / 255.0f
							blue:(value & 0xff) / 255.0f
						   alpha:1.0f];
}

// Declared here rather than in the header: nothing outside this file needs to
// know that the screen answers action sheets and the image picker.
@interface TGSettingsViewController () <UIActionSheetDelegate, UIAlertViewDelegate,
		UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) NSMutableDictionary *privacy;    // setting -> value
@property (nonatomic, strong) NSMutableDictionary *muted;      // scope -> NSNumber
@property (nonatomic, strong) NSArray *languages;
@property (nonatomic, strong) NSString *currentLanguage;
@property (nonatomic, strong) NSArray *blocked;
@property (nonatomic, assign) NSInteger accountTtl;
@property (nonatomic, assign) BOOL blockedLoaded;
@property (nonatomic, assign) BOOL languagesLoaded;
@property (nonatomic, strong) UILabel *headerNameLabel;
@property (nonatomic, strong) UILabel *headerStatusLabel;
+ (NSArray *)rootSettingsRows;
+ (NSArray *)helpRows;
+ (NSArray *)privacySettings;
+ (NSArray *)privacyTitles;
- (NSString *)displayName;
- (NSString *)initialsForName:(NSString *)name;
- (void)refreshHeader;
- (void)confirmClearDatabase;
- (UIImage *)wallpaperSizedImage:(UIImage *)image;
@end

@implementation TGSettingsViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];

	self.privacy = [NSMutableDictionary dictionary];
	self.muted = [NSMutableDictionary dictionary];

	switch (self.page){
		case TGSettingsPageAppearance:    self.title = @"Chat Settings"; break;
		case TGSettingsPageData:          self.title = @"Data and Storage"; break;
		case TGSettingsPageNotifications: self.title = @"Notifications"; break;
		case TGSettingsPagePrivacy:       self.title = @"Privacy and Security"; break;
		case TGSettingsPageLanguage:      self.title = @"Language"; break;
		case TGSettingsPageBlocked:       self.title = @"Blocked Users"; break;
		default:                          self.title = @"Settings"; break;
	}

	if (self.page == TGSettingsPageRoot)
		[self buildHeader];
	[self loadForPage];
}

- (void)applyTheme {
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.page == TGSettingsPageRoot)
		[self refreshHeader];
	[self.tableView reloadData];
}

- (void)openPage:(TGSettingsPage)page {
	TGSettingsViewController *next = [[TGSettingsViewController alloc] init];
	next.page = page;
	[self.navigationController pushViewController:next animated:YES];
}

#pragma mark - header

/// The coloured block their profile page opens with: picture on the left, name
/// beside it, status underneath. This is your own profile, so the name and the
/// number are the account's.
- (void)buildHeader {
	CGFloat width = self.view.bounds.size.width ?: 320;
	UIView *header = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, kHeaderHeight)];
	header.backgroundColor = [UIColor clearColor];
	header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

	BOOL dark = [[TGTheme shared] isDark];
	NSDictionary *me = [TGClient shared].me;
	NSString *name = [self displayName];

	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake(9, 14, kHeaderAvatar, kHeaderAvatar)];
	self.avatarView.layer.cornerRadius = 6.0f;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	self.avatarView.image = [TGIcons avatarWithInitials:[self initialsForName:name]
												   size:kHeaderAvatar
											   colourId:[me[@"id"] longLongValue]];
	[header addSubview:self.avatarView];

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(94, 24, width - 94 - 9, 24)];
	nameLabel.text = name;
	nameLabel.font = [UIFont boldSystemFontOfSize:19];
	nameLabel.textColor = dark ? [[TGTheme shared] primaryTextColour]
							   : TGSettingsRGB(0x222932);
	nameLabel.backgroundColor = [UIColor clearColor];
	if (!dark){
		nameLabel.shadowColor = [UIColor colorWithRed:0xed / 255.0f green:0xf0 / 255.0f
												 blue:0xf5 / 255.0f alpha:0.28f];
		nameLabel.shadowOffset = CGSizeMake(0, 1);
	}
	nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:nameLabel];
	self.headerNameLabel = nameLabel;

	UILabel *status = [[UILabel alloc] initWithFrame:
			CGRectMake(94, 52, width - 94 - 9, 24)];
	status.text = @"online";
	status.font = [UIFont systemFontOfSize:14];
	status.textColor = dark ? [[TGTheme shared] secondaryTextColour]
							: TGSettingsRGB(0x6d7d90);
	status.backgroundColor = [UIColor clearColor];
	if (!dark){
		status.shadowColor = nameLabel.shadowColor;
		status.shadowOffset = CGSizeMake(0, 1);
	}
	status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:status];
	self.headerStatusLabel = status;

	self.tableView.tableHeaderView = header;
	[self refreshHeader];
}

- (NSString *)displayName {
	NSDictionary *me = [TGClient shared].me;
	NSMutableString *name = [NSMutableString string];
	if ([me[@"first_name"] isKindOfClass:[NSString class]])
		[name appendString:me[@"first_name"]];
	if ([me[@"last_name"] isKindOfClass:[NSString class]]
			&& [me[@"last_name"] length]){
		if (name.length) [name appendString:@" "];
		[name appendString:me[@"last_name"]];
	}
	if (name.length)
		return name;
	if ([me[@"username"] isKindOfClass:[NSString class]] && [me[@"username"] length])
		return me[@"username"];
	return @"Telegram";
}

- (NSString *)initialsForName:(NSString *)name {
	if (!name.length)
		return @"T";
	return [[name substringToIndex:1] uppercaseString];
}

- (void)refreshHeader {
	if (!self.headerNameLabel)
		return;

	NSDictionary *me = [TGClient shared].me;
	int64_t userId = [me[@"id"] longLongValue];
	NSString *name = [self displayName];
	self.headerNameLabel.text = name;

	if (!userId){
		self.headerStatusLabel.text = @"connecting...";
	} else {
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] statusForUser:userId completion:^(NSString *text){
			if ([text isKindOfClass:[NSString class]] && text.length)
				weakSelf.headerStatusLabel.text = text;
		}];
	}

	NSNumber *fileId = [[TGClient shared] photoFileIdForUserId:userId];
	if (!fileId){
		self.avatarView.image = [TGIcons avatarWithInitials:[self initialsForName:name]
													  size:kHeaderAvatar
												  colourId:userId];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		UIImage *photo = path.length ? [UIImage imageWithContentsOfFile:path] : nil;
		if (photo) weakSelf.avatarView.image = photo;
	}];
}

/// The version, the way their page ends with one.
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (self.page != TGSettingsPageRoot || section != 3)
		return nil;
	NSDictionary *info = [NSBundle mainBundle].infoDictionary;
	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, 40)];
	label.text = [NSString stringWithFormat:@"iTgLegacy %@ (%@) armv7",
			info[@"CFBundleShortVersionString"] ?: @"", info[@"CFBundleVersion"] ?: @""];
	label.font = [UIFont systemFontOfSize:14];
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [[TGTheme shared] isDark] ? [[TGTheme shared] secondaryTextColour]
												: TGSettingsRGB(0x697487);
	label.backgroundColor = [UIColor clearColor];
	if (![[TGTheme shared] isDark]){
		label.shadowColor = TGSettingsRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	return label;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if (self.page == TGSettingsPageRoot && section == 3)
		return 44;
	return UITableViewAutomaticDimension;
}

#pragma mark - loading

- (void)loadForPage {
	__weak typeof(self) weakSelf = self;

	if (self.page == TGSettingsPageNotifications){
		for (NSString *scope in @[@"private", @"groups", @"channels"])
			[[TGClient shared] notificationsMutedForScope:scope
											   completion:^(BOOL muted){
				weakSelf.muted[scope] = @(muted);
				[weakSelf.tableView reloadData];
			}];
		return;
	}

	if (self.page == TGSettingsPagePrivacy){
		for (NSString *setting in [TGSettingsViewController privacySettings])
			[[TGClient shared] privacyRule:setting completion:^(NSString *value){
				weakSelf.privacy[setting] = value;
				[weakSelf.tableView reloadData];
			}];
		[[TGClient shared] accountTtlWithCompletion:^(NSInteger days){
			weakSelf.accountTtl = days;
			[weakSelf.tableView reloadData];
		}];
		return;
	}

	if (self.page == TGSettingsPageLanguage){
		[[TGClient shared] languagesWithCompletion:^(NSArray *languages,
													NSString *current){
			weakSelf.languages = [languages isKindOfClass:[NSArray class]]
					? languages : @[];
			weakSelf.currentLanguage = current;
			weakSelf.languagesLoaded = YES;
			[weakSelf.tableView reloadData];
		}];
		return;
	}

	if (self.page == TGSettingsPageBlocked){
		[[TGClient shared] blockedUsersWithCompletion:^(NSArray *users){
			weakSelf.blocked = [users isKindOfClass:[NSArray class]] ? users : @[];
			weakSelf.blockedLoaded = YES;
			[weakSelf.tableView reloadData];
		}];
	}
}

/// TDLib's names without the prefix, in the order every client lists them.
+ (NSArray *)privacySettings {
	static NSArray *settings = nil;
	if (!settings)
		settings = @[@"ShowStatus", @"ShowProfilePhoto", @"ShowPhoneNumber",
					 @"AllowCalls", @"AllowChatInvites",
					 @"ShowLinkInForwardedMessages"];
	return settings;
}

+ (NSArray *)privacyTitles {
	static NSArray *titles = nil;
	if (!titles)
		titles = @[@"Last seen", @"Profile photo", @"Phone number",
				   @"Calls", @"Group invites", @"Forwarded messages"];
	return titles;
}

#pragma mark - shape

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	switch (self.page){
		case TGSettingsPageAppearance:    return 3;
		case TGSettingsPageData:          return 1;
		case TGSettingsPageNotifications: return 1;
		case TGSettingsPagePrivacy:       return 3;
		case TGSettingsPageLanguage:      return 1;
		case TGSettingsPageBlocked:       return 1;
		default:                          return 4;
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (self.page){
		case TGSettingsPageAppearance:
			if (section == 0) return 3;                          // styles
			if (section == 1) return 2;                          // wallpaper, size
			return [TGTheme availableThemeFiles].count + 1;      // + "None"
		case TGSettingsPageData:          return 2;
		case TGSettingsPageNotifications: return 3;
		case TGSettingsPagePrivacy:
			if (section == 0) return [[TGSettingsViewController privacySettings] count];
			if (section == 1) return 1;                          // blocked users
			return 1;                                            // self-destruct
		case TGSettingsPageLanguage:
			return (NSInteger)MAX((NSUInteger)1, self.languages.count);
		case TGSettingsPageBlocked:
			return (NSInteger)MAX((NSUInteger)1, self.blocked.count);
		default: break;
	}

	if (section == 0) return 3;    // phone, username, bio
	if (section == 1) return (NSInteger)[TGSettingsViewController rootSettingsRows].count;
	if (section == 2) return (NSInteger)[TGSettingsViewController helpRows].count;
	return 1;                      // log out
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (self.page){
		case TGSettingsPageAppearance:
			if (section == 0) return @"Style";
			if (section == 2) return @"Telegram themes";
			return nil;
		case TGSettingsPagePrivacy:
			return section == 0 ? @"Who can see" : nil;
		case TGSettingsPageNotifications:
			return @"Show notifications for";
		default: break;
	}
	if (self.page != TGSettingsPageRoot)
		return nil;
	if (section == 0) return @"Account";
	if (section == 1) return @"Settings";
	if (section == 2) return @"Help";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (self.page == TGSettingsPageAppearance && section == 2)
		return @"Theme files made for the official clients - .tgios-theme and "
			   @".attheme - are read from the app's Documents folder, or from "
			   @"one received in a chat.";
	if (self.page == TGSettingsPageAppearance && section == 0)
		return (NSFoundationVersionNumber > 993.00)
			? @"This system shipped flat, so that is the default here."
			: @"This system shipped skeuomorphic, so that is the default here.";
	if (self.page == TGSettingsPagePrivacy && section == 2)
		return @"If you do not come online at least once within this period, "
			   @"the account is deleted along with everything in it.";
	if (self.page == TGSettingsPageLanguage)
		return @"This app's own text is English throughout. The language is "
			   @"what Telegram itself writes in, and it follows the account "
			   @"onto your other devices.";
	return nil;
}

#pragma mark - rows

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (self.page == TGSettingsPageRoot && indexPath.section == 0)
		return [self accountCellInTable:tableView at:indexPath];
	if (self.page == TGSettingsPageRoot && indexPath.section == 3)
		return [self logoutCellInTable:tableView];

	static NSString *reuse = @"TGSettingsCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.imageView.image = nil;
	cell.detailTextLabel.text = @"";
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.textColor = [UIColor blackColor];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
	[[TGTheme shared] styleCell:cell];

	switch (self.page){
		case TGSettingsPageAppearance:    return [self fillAppearanceCell:cell at:indexPath];
		case TGSettingsPageData:          return [self fillDataCell:cell at:indexPath];
		case TGSettingsPageNotifications: return [self fillNotificationCell:cell at:indexPath];
		case TGSettingsPagePrivacy:       return [self fillPrivacyCell:cell at:indexPath];
		case TGSettingsPageLanguage:      return [self fillLanguageCell:cell at:indexPath];
		case TGSettingsPageBlocked:       return [self fillBlockedCell:cell at:indexPath];
		default:                          return [self fillRootCell:cell at:indexPath];
	}
}

/// The settings list from their page, with the line icon each row carries.
+ (NSArray *)rootSettingsRows {
	static NSArray *rows = nil;
	if (!rows)
		rows = @[@[@"Notifications and Sounds", @"notifications"],
				 @[@"Privacy and Security",     @"privacy"],
				 @[@"Data and Storage",         @"data"],
				 @[@"Chat Settings",            @"chat"],
				 @[@"Folders",                  @"folder"],
				 @[@"Devices",                  @"devices"],
				 @[@"Language",                 @"language"]];
	return rows;
}

+ (NSArray *)helpRows {
	static NSArray *rows = nil;
	if (!rows)
		rows = @[@[@"Ask a Question", @"chat"],
				 @[@"Telegram FAQ",   @"faq"],
				 @[@"Privacy Policy", @"policy"]];
	return rows;
}

- (UITableViewCell *)fillRootCell:(UITableViewCell *)cell at:(NSIndexPath *)indexPath {
	TGTheme *theme = [TGTheme shared];

	if (indexPath.section == 1){
		NSArray *row = [TGSettingsViewController rootSettingsRows][indexPath.row];
		cell.textLabel.text = row[0];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.imageView.image = [TGIcons menuGlyphNamed:row[1]];
		[cell.imageView tg_setTintColor:[theme secondaryTextColour]];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (indexPath.section == 2){
		NSArray *help = [TGSettingsViewController helpRows];
		cell.textLabel.text = help[indexPath.row][0];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.imageView.image = [TGIcons menuGlyphNamed:help[indexPath.row][1]];
		[cell.imageView tg_setTintColor:[theme secondaryTextColour]];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	cell.textLabel.text = @"Log out";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1.0f];
	return cell;
}

- (UITableViewCell *)accountCellInTable:(UITableView *)tableView at:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGSettingsAccountCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue2
									  reuseIdentifier:reuse];
	[[TGTheme shared] styleCell:cell];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;

	NSDictionary *me = [TGClient shared].me;
	if (indexPath.row == 0){
		cell.textLabel.text = @"mobile";
		cell.detailTextLabel.text = [me[@"phone"] length]
				? [NSString stringWithFormat:@"+%@", me[@"phone"]] : @"Not signed in";
	} else if (indexPath.row == 1){
		cell.textLabel.text = @"username";
		cell.detailTextLabel.text = [me[@"username"] length]
				? [NSString stringWithFormat:@"@%@", me[@"username"]] : @"Not set";
	} else {
		cell.textLabel.text = @"bio";
		cell.detailTextLabel.text = [me[@"bio"] length] ? me[@"bio"] : @"Not set";
	}

	cell.textLabel.font = [UIFont boldSystemFontOfSize:13];
	cell.textLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] secondaryTextColour] : TGSettingsRGB(0x5d708f);
	cell.detailTextLabel.font = [UIFont boldSystemFontOfSize:15];
	cell.detailTextLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
	return cell;
}

- (UITableViewCell *)logoutCellInTable:(UITableView *)tableView {
	static NSString *reuse = @"TGSettingsLogoutCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:reuse];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.backgroundColor = [UIColor clearColor];
		cell.backgroundView = [[UIView alloc] initWithFrame:CGRectZero];
		cell.backgroundView.backgroundColor = [UIColor clearColor];
		cell.contentView.backgroundColor = [UIColor clearColor];

		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.tag = 771;
		button.frame = CGRectMake(9, 0, cell.contentView.bounds.size.width - 18, 45);
		button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		[button setTitle:@"Log out" forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleShadowColor:[UIColor colorWithRed:0xa1 / 255.0f green:0x06 / 255.0f
													 blue:0x03 / 255.0f alpha:0.5f]
						   forState:UIControlStateNormal];

		UIImage *raw = [UIImage imageNamed:@"MenuRedButton.png"];
		UIImage *rawHighlighted = [UIImage imageNamed:@"MenuRedButton_Highlighted.png"];
		if (raw)
			[button setBackgroundImage:[raw stretchableImageWithLeftCapWidth:
					(int)(raw.size.width / 2) topCapHeight:(int)(raw.size.height / 2)]
							  forState:UIControlStateNormal];
		if (rawHighlighted)
			[button setBackgroundImage:[rawHighlighted stretchableImageWithLeftCapWidth:
					(int)(rawHighlighted.size.width / 2)
					topCapHeight:(int)(rawHighlighted.size.height / 2)]
							  forState:UIControlStateHighlighted];
		if (!raw)
			button.backgroundColor = TGSettingsRGB(0xc4362f);
		[button addTarget:self action:@selector(confirmLogout)
		 forControlEvents:UIControlEventTouchUpInside];
		[cell.contentView addSubview:button];
	}
	UIView *button = [cell.contentView viewWithTag:771];
	button.frame = CGRectMake(9, 0, cell.contentView.bounds.size.width - 18, 45);
	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.page == TGSettingsPageRoot && indexPath.section == 3)
		return 45;
	return 44;
}

- (UITableViewCell *)fillNotificationCell:(UITableViewCell *)cell at:(NSIndexPath *)path {
	static NSArray *scopes = nil, *titles = nil;
	if (!scopes){
		scopes = @[@"private", @"groups", @"channels"];
		titles = @[@"Private chats", @"Groups", @"Channels"];
	}
	cell.textLabel.text = titles[path.row];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];

	UISwitch *toggle = [[UISwitch alloc] init];
	// The row says "show notifications", TDLib stores "muted": the same fact
	// the other way up.
	toggle.on = ![self.muted[scopes[path.row]] boolValue];
	toggle.tag = path.row;
	[toggle addTarget:self action:@selector(notificationToggled:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	return cell;
}

- (UITableViewCell *)fillPrivacyCell:(UITableViewCell *)cell at:(NSIndexPath *)path {
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	if (path.section == 0){
		NSString *setting = [TGSettingsViewController privacySettings][path.row];
		cell.textLabel.text = [TGSettingsViewController privacyTitles][path.row];
		cell.detailTextLabel.text = self.privacy[setting] ?: @"...";
		return cell;
	}
	if (path.section == 1){
		cell.textLabel.text = @"Blocked users";
		return cell;
	}
	cell.textLabel.text = @"Delete my account";
	cell.detailTextLabel.text = self.accountTtl > 0
			? [NSString stringWithFormat:@"if away for %ld months",
					(long)(self.accountTtl / 30)]
			: @"...";
	return cell;
}

- (UITableViewCell *)fillLanguageCell:(UITableViewCell *)cell at:(NSIndexPath *)path {
	if (!self.languages.count){
		cell.textLabel.text = self.languagesLoaded ? @"No languages available"
												   : @"Loading...";
		cell.textLabel.font = [UIFont systemFontOfSize:15];
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}
	NSDictionary *language = self.languages[path.row];
	if (![language isKindOfClass:[NSDictionary class]])
		return cell;
	NSString *languageName = [language[@"name"] isKindOfClass:[NSString class]]
			? language[@"name"] : nil;
	cell.textLabel.text = languageName.length ? languageName : @"Language";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.accessoryType = ([language[@"id"] isKindOfClass:[NSString class]]
			&& [language[@"id"] isEqualToString:self.currentLanguage])
			? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (UITableViewCell *)fillBlockedCell:(UITableViewCell *)cell at:(NSIndexPath *)path {
	if (!self.blocked.count){
		cell.textLabel.text = self.blockedLoaded ? @"Nobody is blocked" : @"Loading...";
		cell.textLabel.font = [UIFont systemFontOfSize:15];
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}
	NSDictionary *user = self.blocked[path.row];
	NSString *name = ([user isKindOfClass:[NSDictionary class]]
			&& [user[@"name"] isKindOfClass:[NSString class]]) ? user[@"name"] : nil;
	cell.textLabel.text = name.length ? name : @"Deleted Account";
	cell.detailTextLabel.text = @"Tap to unblock";
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	return cell;
}

- (UITableViewCell *)fillAppearanceCell:(UITableViewCell *)cell at:(NSIndexPath *)indexPath {
	if (indexPath.section == 0){
		static NSArray *styles = nil;
		if (!styles) styles = @[@"Skeuomorphic", @"Flat", @"Dark"];
		cell.textLabel.text = styles[indexPath.row];
		cell.accessoryType = (indexPath.row == [TGTheme shared].style)
			? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		return cell;
	}

	if (indexPath.section == 1){
		if (indexPath.row == 0){
			cell.textLabel.text = @"Chat wallpaper";
			cell.detailTextLabel.text = [TGTheme shared].wallpaper ? @"Set" : @"None";
		} else {
			cell.textLabel.text = @"Message text size";
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt",
					[TGTheme shared].messageFontSize];
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	NSArray *files = [TGTheme availableThemeFiles];
	NSString *current = [TGTheme shared].importedName;
	if (indexPath.row == 0){
		cell.textLabel.text = @"None";
		cell.accessoryType = current ? UITableViewCellAccessoryNone
									 : UITableViewCellAccessoryCheckmark;
		return cell;
	}
	if ((NSUInteger)(indexPath.row - 1) >= files.count)
		return cell;
	NSString *path = files[indexPath.row - 1];
	NSString *label = [path.lastPathComponent stringByDeletingPathExtension];
	cell.textLabel.text = label;
	cell.detailTextLabel.text = path.pathExtension;
	cell.accessoryType = [current isEqualToString:label]
			? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (UITableViewCell *)fillDataCell:(UITableViewCell *)cell at:(NSIndexPath *)indexPath {
	if (indexPath.row == 0){
		cell.textLabel.text = @"Storage and cache";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else {
		cell.textLabel.text = @"Clear local database";
		cell.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1.0f];
	}
	return cell;
}

#pragma mark - taps

- (void)notificationToggled:(UISwitch *)toggle {
	static NSArray *scopes = nil;
	if (!scopes) scopes = @[@"private", @"groups", @"channels"];
	NSString *scope = scopes[toggle.tag];
	self.muted[scope] = @(!toggle.on);
	[[TGClient shared] setScope:scope muted:!toggle.on];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	switch (self.page){
		case TGSettingsPageAppearance: [self tapAppearance:indexPath]; return;
		case TGSettingsPageNotifications: return;   // the switch does the work
		case TGSettingsPagePrivacy:    [self tapPrivacy:indexPath];    return;
		case TGSettingsPageLanguage:   [self tapLanguage:indexPath];   return;
		case TGSettingsPageBlocked:    [self tapBlocked:indexPath];    return;
		case TGSettingsPageData:
			if (indexPath.row == 0){
				TGStorageViewController *storage = [[TGStorageViewController alloc] init];
				[self.navigationController pushViewController:storage animated:YES];
			} else {
				[self confirmClearDatabase];
			}
			return;
		default: break;
	}

	if (indexPath.section == 0){
		UIViewController *profile = [[TGEditProfileViewController alloc] init];
		[self.navigationController pushViewController:profile animated:YES];
		return;
	}

	if (indexPath.section == 1){
		switch (indexPath.row){
			case 0: [self openPage:TGSettingsPageNotifications]; break;
			case 1: [self openPage:TGSettingsPagePrivacy]; break;
			case 2: [self openPage:TGSettingsPageData]; break;
			case 3: [self openPage:TGSettingsPageAppearance]; break;
			case 4: [self showFolders]; break;
			case 5: {
				UIViewController *sessions = [[TGSessionsViewController alloc] init];
				[self.navigationController pushViewController:sessions animated:YES];
				break;
			}
			default: [self openPage:TGSettingsPageLanguage]; break;
		}
		return;
	}

	if (indexPath.section == 2){
		[self openHelp:indexPath.row];
		return;
	}

	[self confirmLogout];
}

- (void)confirmLogout {
	// Logging out drops the session, so make it deliberate.
	UIAlertView *confirm = [[UIAlertView alloc]
			initWithTitle:@"Log out"
				  message:@"Sign out of this account on this device?"
				 delegate:self
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@"Log out", nil];
	confirm.tag = 401;
	[confirm show];
}

- (void)confirmClearDatabase {
	UIAlertView *confirm = [[UIAlertView alloc]
			initWithTitle:@"Clear local database"
				  message:@"Messages and media cached on this device are removed. "
						  @"Nothing is deleted from Telegram itself."
				 delegate:self
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@"Clear", nil];
	confirm.tag = 402;
	[confirm show];
}

/// Folders are a filter over the chat list, so this says where they are rather
/// than building a second copy of the same sheet.
- (void)showFolders {
	NSArray *folders = [TGClient shared].folders;
	NSString *message = folders.count
			? [NSString stringWithFormat:@"%lu folders. Pick one from Folders "
					@"above the chat list.", (unsigned long)folders.count]
			: @"This account has no chat folders. They are set up in Telegram "
			  @"on a desktop or a newer phone, and appear here.";
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Folders"
			message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

- (void)openHelp:(NSInteger)row {
	if (row == 0){
		// Their support is a chat, not a web page.
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] chatWithUsername:@"BotSupport"
								 completion:^(int64_t chatId, NSString *title){
			if (!chatId){
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Support"
						message:@"Support is not reachable from this account right now."
					   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
				[alert show];
				return;
			}
			[weakSelf openSupportChat:chatId title:title];
		}];
		return;
	}
	NSString *url = (row == 1) ? @"https://telegram.org/faq"
							   : @"https://telegram.org/privacy";
	NSURL *target = [NSURL URLWithString:url];
	if (target && [[UIApplication sharedApplication] canOpenURL:target])
		[[UIApplication sharedApplication] openURL:target];
}

- (void)openSupportChat:(int64_t)chatId title:(NSString *)title {
	// Imported lazily to keep the settings screen from knowing about chats in
	// general; it only ever opens this one.
	Class chatClass = NSClassFromString(@"TGChatViewController");
	UIViewController *chat = chatClass ? [[chatClass alloc] init] : nil;
	if (!chat || !self.navigationController){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Support"
				message:@"The support chat could not be opened."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
		return;
	}
	@try {
		[chat setValue:@(chatId) forKey:@"chatId"];
		[chat setValue:(title.length ? title : @"Telegram Support") forKey:@"chatTitle"];
	}
	@catch (NSException *exception) {
		return;
	}
	[self.navigationController pushViewController:chat animated:YES];
}

- (void)tapPrivacy:(NSIndexPath *)indexPath {
	if (indexPath.section == 1){
		[self openPage:TGSettingsPageBlocked];
		return;
	}
	if (indexPath.section == 2){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Delete my account if away for"
														  delegate:self
												 cancelButtonTitle:nil
											destructiveButtonTitle:nil
												 otherButtonTitles:@"1 month", @"3 months",
															   @"6 months", @"12 months", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 90;
		[sheet showInView:self.view];
		return;
	}

	UIActionSheet *sheet = [[UIActionSheet alloc]
			initWithTitle:[TGSettingsViewController privacyTitles][indexPath.row]
				 delegate:self
		cancelButtonTitle:nil
   destructiveButtonTitle:nil
		otherButtonTitles:@"everybody", @"contacts", @"nobody", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 91 + indexPath.row;
	[sheet showInView:self.view];
}

- (void)tapLanguage:(NSIndexPath *)indexPath {
	if ((NSUInteger)indexPath.row >= self.languages.count)
		return;
	NSDictionary *language = self.languages[indexPath.row];
	if (![language[@"id"] isKindOfClass:[NSString class]])
		return;
	[[TGClient shared] setLanguage:language[@"id"]];
	self.currentLanguage = language[@"id"];
	[self.tableView reloadData];
}

- (void)tapBlocked:(NSIndexPath *)indexPath {
	if ((NSUInteger)indexPath.row >= self.blocked.count)
		return;
	NSDictionary *user = self.blocked[indexPath.row];
	if (![user isKindOfClass:[NSDictionary class]])
		return;
	[[TGClient shared] setUser:[user[@"id"] longLongValue] blocked:NO];

	NSMutableArray *rest = [self.blocked mutableCopy];
	[rest removeObjectAtIndex:indexPath.row];
	self.blocked = rest;
	[self.tableView reloadData];
}

- (void)tapAppearance:(NSIndexPath *)indexPath {
	if (indexPath.section == 0){
		[TGTheme shared].style = (TGThemeStyle)indexPath.row;
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
		[self applyTheme];
		[self.tableView reloadData];
		return;
	}

	if (indexPath.section == 1){
		if (indexPath.row == 0) [self chooseWallpaper];
		else                    [self chooseTextSize];
		return;
	}

	NSArray *files = [TGTheme availableThemeFiles];
	if (indexPath.row == 0){
		[[TGTheme shared] clearImportedTheme];
	} else if ((NSUInteger)(indexPath.row - 1) >= files.count){
		[self.tableView reloadData];
		return;
	} else if (![[TGTheme shared] importThemeAtPath:files[indexPath.row - 1]]){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Theme"
				message:@"This file could not be read as a Telegram theme."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self applyTheme];
	[self.tableView reloadData];
}

/// Four sizes is enough on a 3.5-inch screen; a slider would be finer than
/// the difference it makes.
- (void)chooseTextSize {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Message text size"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:@"13 pt", @"15 pt",
														   @"17 pt", @"19 pt", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 88;
	[sheet showInView:self.view];
}

#pragma mark - wallpaper

- (void)chooseWallpaper {
	if ([TGTheme shared].wallpaper){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Chat wallpaper"
														  delegate:self
												 cancelButtonTitle:nil
											destructiveButtonTitle:@"Remove"
												 otherButtonTitles:@"Choose another", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 89;
		[sheet showInView:self.view];
		return;
	}
	[self presentWallpaperPicker];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == 88){
		[TGTheme shared].messageFontSize = 13.0f + index * 2.0f;
		[self.tableView reloadData];
		return;
	}

	if (sheet.tag == 90){
		static const NSInteger months[4] = {1, 3, 6, 12};
		[[TGClient shared] setAccountTtlDays:months[index] * 30];
		self.accountTtl = months[index] * 30;
		[self.tableView reloadData];
		return;
	}

	if (sheet.tag >= 91){
		NSInteger row = sheet.tag - 91;
		NSString *setting = [TGSettingsViewController privacySettings][row];
		NSString *value = @[@"everybody", @"contacts", @"nobody"][index];
		[[TGClient shared] setPrivacyRule:setting to:value];
		self.privacy[setting] = value;
		[self.tableView reloadData];
		return;
	}

	if (index == sheet.destructiveButtonIndex){
		[[TGTheme shared] setWallpaperImage:nil];
		[self.tableView reloadData];
		return;
	}
	[self presentWallpaperPicker];
}

- (void)presentWallpaperPicker {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary]){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Chat wallpaper"
				message:@"There is no photo library on this device."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
		return;
	}
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (image)
		[[TGTheme shared] setWallpaperImage:[self wallpaperSizedImage:image]];
	[self.tableView reloadData];
}

- (UIImage *)wallpaperSizedImage:(UIImage *)image {
	CGSize size = image.size;
	if (size.width < 1 || size.height < 1)
		return image;
	CGFloat limit = 960.0f;
	CGFloat scale = MIN(1.0f, MIN(limit / size.width, limit / size.height));
	if (scale >= 1.0f)
		return image;

	CGSize target = CGSizeMake(floorf(size.width * scale), floorf(size.height * scale));
	UIGraphicsBeginImageContextWithOptions(target, YES, 1.0f);
	[image drawInRect:CGRectMake(0, 0, target.width, target.height)];
	UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return scaled ?: image;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	if (alertView.tag == 401)
		[[TGClient shared] logOut];
	else if (alertView.tag == 402)
		[[TGClient shared] clearLocalDatabase];
}

@end

// vim:ft=objc

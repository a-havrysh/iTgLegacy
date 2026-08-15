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
#import "TGStickersViewController.h"
#import "TGFoldersViewController.h"
#import "TGProxyViewController.h"
#import "TGPremiumViewController.h"
#import "TGStarsViewController.h"
#import "TGSavedMessagesTagsViewController.h"
#import "TGGroupMembersViewController.h"
#import "TGInviteLinksViewController.h"
#import "TGChatEventsViewController.h"
#import "TGClient+ChatList.h"
#import "TGClient+Network.h"
#import "TGClient+Storage.h"
#import "TGClient+Notifications.h"
#import "TGClient+AppSettings.h"
#import "TGCapabilities.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "UIView+SafeTint.h"

// Their profile page: a 175dp coloured block with a 76dp picture on the left,
// the name beside it and the status under that. Scaled to a 320pt screen.
static const CGFloat kHeaderHeight = 86.0f;
static const CGFloat kHeaderAvatar = 70.0f;

enum {
	TGSettingsPageAutoDownload   = 100,
	TGSettingsPageAutosave       = 101,
	TGSettingsPageWallpaper      = 102,
	TGSettingsPageChatListLayout = 103
};

enum {
	TGSettingsRootKindSuggestions = 0,
	TGSettingsRootKindAccount,
	TGSettingsRootKindSettings,
	TGSettingsRootKindStories,
	TGSettingsRootKindTelegram,
	TGSettingsRootKindGroupTools,
	TGSettingsRootKindHelp,
	TGSettingsRootKindLogout
};

static NSString *const TGSettingsPresetDefaultsKey = @"TGAutoDownloadPresetNames";
static NSString *const TGSettingsSavedPresetsKey = @"TGAutoDownloadPresetsBeforeSaver";
static NSString *const TGSettingsLessCallDataKey = @"TGUseLessDataForCalls";
static NSString *const TGSettingsArchiveSuggestionKey = @"TGArchiveSuggestionDismissed";
static NSString *const TGSettingsStoriesEnabledKey = @"TGStoriesEnabled";
static NSString *const TGSettingsChatListLayoutKey = @"TGChatListLayout";

NSString *const TGSettingsStoriesEnabledChangedNotification =
		@"TGStoriesEnabledChanged";
NSString *const TGSettingsChatListLayoutChangedNotification =
		@"TGChatListLayoutChanged";

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
@property (nonatomic, strong) NSMutableDictionary *archive;
@property (nonatomic, strong) NSArray *groupPicks;
@property (nonatomic, assign) BOOL dataSaver;
@property (nonatomic, strong) NSDictionary *presets;
@property (nonatomic, strong) NSMutableDictionary *autosave;
@property (nonatomic, strong) NSArray *backgrounds;
@property (nonatomic, assign) BOOL backgroundsLoaded;
@property (nonatomic, assign) BOOL lessCallData;
@property (nonatomic, strong) NSArray *suggestions;
+ (NSArray *)rootSettingsRows;
+ (NSArray *)telegramRows;
+ (NSArray *)groupToolRows;
+ (NSArray *)helpRows;
+ (NSArray *)privacySettings;
+ (NSArray *)privacyTitles;
- (NSString *)displayName;
- (NSString *)initialsForName:(NSString *)name;
- (void)refreshHeader;
- (void)confirmClearDatabase;
- (UIView *)disclosureAccessory;
- (UIView *)checkAccessory;
- (void)markDisclosure:(UITableViewCell *)cell;
- (void)markChecked:(BOOL)checked on:(UITableViewCell *)cell;
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
	self.archive = [NSMutableDictionary dictionary];
	self.autosave = [NSMutableDictionary dictionary];
	self.suggestions = @[];
	self.dataSaver = [[NSUserDefaults standardUserDefaults] boolForKey:@"TGDataSaver"];
	self.lessCallData = [[NSUserDefaults standardUserDefaults]
			boolForKey:TGSettingsLessCallDataKey];

	if ((NSInteger)self.page == TGSettingsPageAutoDownload)
		self.title = @"Auto-Download Media";
	else if ((NSInteger)self.page == TGSettingsPageAutosave)
		self.title = @"Save to Camera Roll";
	else if ((NSInteger)self.page == TGSettingsPageWallpaper)
		self.title = @"Chat Wallpaper";
	else if ((NSInteger)self.page == TGSettingsPageChatListLayout)
		self.title = @"Chat List";
	else switch (self.page){
		case TGSettingsPageAppearance:    self.title = @"Chat Settings"; break;
		case TGSettingsPageData:          self.title = @"Data and Storage"; break;
		case TGSettingsPageNotifications: self.title = @"Notifications"; break;
		case TGSettingsPagePrivacy:       self.title = @"Privacy and Security"; break;
		case TGSettingsPageLanguage:      self.title = @"Language"; break;
		case TGSettingsPageBlocked:       self.title = @"Blocked Users"; break;
		default:                          self.title = @"Settings"; break;
	}

	if (self.page == TGSettingsPageRoot){
		UIButton *edit = [TGIcons headerButtonWithTitle:@"Edit" bold:NO
												 target:self action:@selector(editProfileTapped)];
		self.navigationItem.rightBarButtonItem =
				[[UIBarButtonItem alloc] initWithCustomView:edit];
		[self buildHeader];
	}
	[self loadForPage];
}

- (void)editProfileTapped {
	UIViewController *profile = [[TGEditProfileViewController alloc] init];
	[self.navigationController pushViewController:profile animated:YES];
}

- (void)applyTheme {
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	if (self.navigationController.navigationBar)
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (UIView *)disclosureAccessory {
	UIImage *art = [[TGTheme shared] isDark]
			? [UIImage imageNamed:@"MenuDisclosureIndicator_Light.png"]
			: [UIImage imageNamed:@"MenuDisclosureIndicator.png"];
	if (!art)
		return nil;
	UIImageView *view = [[UIImageView alloc] initWithImage:art
										 highlightedImage:[UIImage imageNamed:
												 @"MenuDisclosureIndicator_Highlighted.png"]];
	view.frame = CGRectMake(0, 0, art.size.width, art.size.height);
	return view;
}

- (UIView *)checkAccessory {
	UIImage *art = [UIImage imageNamed:@"ListCheck.png"];
	if (!art)
		return nil;
	UIImageView *view = [[UIImageView alloc] initWithImage:art
										 highlightedImage:[UIImage imageNamed:
												 @"ListCheck_Highlighted.png"]];
	view.frame = CGRectMake(0, 0, art.size.width, art.size.height);
	return view;
}

- (void)markDisclosure:(UITableViewCell *)cell {
	UIView *chevron = [self disclosureAccessory];
	if (chevron){
		cell.accessoryView = chevron;
		cell.accessoryType = UITableViewCellAccessoryNone;
	} else {
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
}

- (void)markChecked:(BOOL)checked on:(UITableViewCell *)cell {
	if (!checked){
		cell.accessoryView = nil;
		cell.accessoryType = UITableViewCellAccessoryNone;
		return;
	}
	UIView *check = [self checkAccessory];
	if (check){
		cell.accessoryView = check;
		cell.accessoryType = UITableViewCellAccessoryNone;
	} else {
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	}
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
	if (self.page != TGSettingsPageRoot
			|| [self rootKindForSection:section] != TGSettingsRootKindLogout)
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
	if (self.page == TGSettingsPageRoot
			&& [self rootKindForSection:section] == TGSettingsRootKindLogout)
		return 44;
	return UITableViewAutomaticDimension;
}

#pragma mark - loading

- (void)loadForPage {
	__weak typeof(self) weakSelf = self;

	if ((NSInteger)self.page == TGSettingsPageAutoDownload){
		[[TGClient shared] autoDownloadPresetsWithCompletion:^(NSDictionary *presets){
			if ([presets isKindOfClass:[NSDictionary class]])
				weakSelf.presets = presets;
			[weakSelf.tableView reloadData];
		}];
		return;
	}

	if ((NSInteger)self.page == TGSettingsPageAutosave){
		[[TGClient shared] autosaveSettingsWithCompletion:^(NSDictionary *privateChats,
														   NSDictionary *groups,
														   NSDictionary *channels){
			if ([privateChats isKindOfClass:[NSDictionary class]])
				weakSelf.autosave[@"private"] = privateChats;
			if ([groups isKindOfClass:[NSDictionary class]])
				weakSelf.autosave[@"groups"] = groups;
			if ([channels isKindOfClass:[NSDictionary class]])
				weakSelf.autosave[@"channels"] = channels;
			[weakSelf.tableView reloadData];
		}];
		return;
	}

	if ((NSInteger)self.page == TGSettingsPageWallpaper){
		[[TGClient shared] installedBackgroundsForDarkTheme:[[TGTheme shared] isDark]
												 completion:^(NSArray *backgrounds){
			weakSelf.backgrounds = [backgrounds isKindOfClass:[NSArray class]]
					? backgrounds : @[];
			weakSelf.backgroundsLoaded = YES;
			[weakSelf.tableView reloadData];
		}];
		return;
	}

	if (self.page == TGSettingsPageRoot){
		[self loadSuggestions];
		return;
	}

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

	if (self.page == TGSettingsPageData){
		[[TGClient shared] archiveSettingsWithCompletion:^(NSDictionary *settings){
			if ([settings isKindOfClass:[NSDictionary class]])
				[weakSelf.archive addEntriesFromDictionary:settings];
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

- (void)loadSuggestions {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:TGSettingsArchiveSuggestionKey])
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] archiveChatListSettingsWithCompletion:^(NSDictionary *settings){
		if (![settings isKindOfClass:[NSDictionary class]])
			return;
		if ([settings[@"archiveAndMuteNewChatsFromUnknownUsers"] boolValue])
			return;
		weakSelf.suggestions = @[@{
			@"name"     : @"suggestedActionEnableArchiveAndMuteNewChats",
			@"title"    : @"Archive and mute new chats",
			@"subtitle" : @"Chats from people you do not know go straight to the archive."
		}];
		[weakSelf.tableView reloadData];
	}];
}

- (BOOL)showsSuggestions {
	return self.page == TGSettingsPageRoot && self.suggestions.count > 0;
}

- (NSInteger)rootKindForSection:(NSInteger)section {
	NSInteger kind = section + ([self showsSuggestions] ? 0 : 1);
	return kind;
}

- (NSInteger)rootSectionForKind:(NSInteger)kind {
	return kind - ([self showsSuggestions] ? 0 : 1);
}

- (void)acceptSuggestionAtRow:(NSInteger)row {
	if ((NSUInteger)row >= self.suggestions.count)
		return;
	[[TGClient shared] acceptArchiveAndMuteSuggestion];
	self.archive[@"archiveUnknownSenders"] = @YES;
	[self dismissSuggestionAtRow:row];
}

- (void)dismissSuggestionAtRow:(NSInteger)row {
	if ((NSUInteger)row >= self.suggestions.count)
		return;
	NSDictionary *suggestion = self.suggestions[row];
	if ([suggestion[@"name"] isKindOfClass:[NSString class]])
		[[TGClient shared] hideSuggestedActionNamed:suggestion[@"name"]];
	[[NSUserDefaults standardUserDefaults] setBool:YES
											forKey:TGSettingsArchiveSuggestionKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	NSMutableArray *rest = [self.suggestions mutableCopy];
	[rest removeObjectAtIndex:row];
	self.suggestions = rest;
	[self.tableView reloadData];
}

- (void)suggestionDismissTapped:(UIButton *)button {
	[self dismissSuggestionAtRow:button.tag];
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

#pragma mark - stories and chat list layout

+ (BOOL)storiesEnabled {
	NSNumber *stored = [[NSUserDefaults standardUserDefaults]
			objectForKey:TGSettingsStoriesEnabledKey];
	if (![stored isKindOfClass:[NSNumber class]])
		return YES;
	return [stored boolValue];
}

+ (void)setStoriesEnabled:(BOOL)enabled {
	[[NSUserDefaults standardUserDefaults] setObject:@(enabled)
											  forKey:TGSettingsStoriesEnabledKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGSettingsStoriesEnabledChangedNotification
						  object:nil];
}

+ (NSArray *)chatListLayouts {
	static NSArray *layouts = nil;
	if (!layouts)
		layouts = @[@"a", @"b"];
	return layouts;
}

+ (NSArray *)chatListLayoutTitles {
	static NSArray *titles = nil;
	if (!titles)
		titles = @[@"Chooser in the Title", @"Strip Under the Title"];
	return titles;
}

+ (NSString *)chatListLayout {
	NSString *stored = [[NSUserDefaults standardUserDefaults]
			objectForKey:TGSettingsChatListLayoutKey];
	if ([stored isKindOfClass:[NSString class]]
			&& [[TGSettingsViewController chatListLayouts] containsObject:stored])
		return stored;
	return @"b";
}

+ (NSString *)chatListLayoutTitle {
	NSUInteger index = [[TGSettingsViewController chatListLayouts]
			indexOfObject:[TGSettingsViewController chatListLayout]];
	if (index == NSNotFound)
		index = 1;
	return [TGSettingsViewController chatListLayoutTitles][index];
}

+ (void)setChatListLayout:(NSString *)layout {
	if (![[TGSettingsViewController chatListLayouts] containsObject:layout])
		return;
	[[NSUserDefaults standardUserDefaults] setObject:layout
											  forKey:TGSettingsChatListLayoutKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGSettingsChatListLayoutChangedNotification
						  object:nil];
}

- (void)storiesToggled:(UISwitch *)toggle {
	[TGSettingsViewController setStoriesEnabled:toggle.on];
}

#pragma mark - shape

+ (NSArray *)networkKinds {
	static NSArray *kinds = nil;
	if (!kinds)
		kinds = @[@"wifi", @"mobile", @"roaming"];
	return kinds;
}

+ (NSArray *)networkTitles {
	static NSArray *titles = nil;
	if (!titles)
		titles = @[@"Wi-Fi", @"Mobile data", @"Roaming"];
	return titles;
}

+ (NSArray *)presetNames {
	static NSArray *names = nil;
	if (!names)
		names = @[@"low", @"medium", @"high"];
	return names;
}

+ (NSArray *)autosaveScopes {
	static NSArray *scopes = nil;
	if (!scopes)
		scopes = @[@"private", @"groups", @"channels"];
	return scopes;
}

+ (NSArray *)autosaveTitles {
	static NSArray *titles = nil;
	if (!titles)
		titles = @[@"Private chats", @"Groups", @"Channels"];
	return titles;
}

- (NSString *)presetNameForNetwork:(NSString *)kind {
	NSDictionary *stored = [[NSUserDefaults standardUserDefaults]
			objectForKey:TGSettingsPresetDefaultsKey];
	if ([stored isKindOfClass:[NSDictionary class]]
			&& [stored[kind] isKindOfClass:[NSString class]])
		return stored[kind];
	return nil;
}

- (void)rememberPreset:(NSString *)name forNetwork:(NSString *)kind {
	NSDictionary *stored = [[NSUserDefaults standardUserDefaults]
			objectForKey:TGSettingsPresetDefaultsKey];
	NSMutableDictionary *next = [stored isKindOfClass:[NSDictionary class]]
			? [stored mutableCopy] : [NSMutableDictionary dictionary];
	if (name)
		next[kind] = name;
	else
		[next removeObjectForKey:kind];
	[[NSUserDefaults standardUserDefaults] setObject:next
											  forKey:TGSettingsPresetDefaultsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)detailForNetwork:(NSString *)kind {
	NSString *name = [self presetNameForNetwork:kind];
	NSDictionary *mirror = [[TGClient shared] autoDownloadSettingsForNetworkType:kind];
	if (mirror && ![mirror[@"enabled"] boolValue])
		return @"Off";
	if (!name)
		return mirror ? @"Custom" : @"Not set";
	NSDictionary *preset = [self.presets isKindOfClass:[NSDictionary class]]
			? self.presets[name] : nil;
	long long photo = [preset[@"maxPhotoSize"] longLongValue];
	NSString *label = [name capitalizedString];
	if (photo > 0)
		return [NSString stringWithFormat:@"%@, photos to %lld KB", label, photo / 1024];
	return label;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	if ((NSInteger)self.page == TGSettingsPageAutoDownload)
		return 2;
	if ((NSInteger)self.page == TGSettingsPageAutosave)
		return 4;
	if ((NSInteger)self.page == TGSettingsPageWallpaper)
		return 2;
	if ((NSInteger)self.page == TGSettingsPageChatListLayout)
		return 1;
	if (self.page == TGSettingsPageRoot)
		return [self showsSuggestions] ? 8 : 7;
	switch (self.page){
		case TGSettingsPageAppearance:    return 3;
		case TGSettingsPageData:          return 3;
		case TGSettingsPageNotifications: return 1;
		case TGSettingsPagePrivacy:       return 3;
		case TGSettingsPageLanguage:      return 1;
		case TGSettingsPageBlocked:       return 1;
		default:                          return 6;
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if ((NSInteger)self.page == TGSettingsPageAutoDownload)
		return section == 0 ? (NSInteger)[TGSettingsViewController networkKinds].count : 1;
	if ((NSInteger)self.page == TGSettingsPageAutosave)
		return section == 3 ? 1 : 2;
	if ((NSInteger)self.page == TGSettingsPageWallpaper){
		if (section == 0)
			return [TGTheme shared].wallpaper ? 2 : 1;
		return (NSInteger)MAX((NSUInteger)1, self.backgrounds.count);
	}
	if ((NSInteger)self.page == TGSettingsPageChatListLayout)
		return (NSInteger)[TGSettingsViewController chatListLayouts].count;
	switch (self.page){
		case TGSettingsPageAppearance:
			if (section == 0) return 3;                          // styles
			if (section == 1) return 2;                          // wallpaper, size
			return [TGTheme availableThemeFiles].count + 1;      // + "None"
		case TGSettingsPageData:
			if (section == 0) return 4;
			if (section == 1) return 3;
			return 1;
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

	switch ([self rootKindForSection:section]){
		case TGSettingsRootKindSuggestions: return (NSInteger)self.suggestions.count;
		case TGSettingsRootKindAccount:     return 3;
		case TGSettingsRootKindSettings:
			return (NSInteger)[TGSettingsViewController rootSettingsRows].count;
		case TGSettingsRootKindStories:     return 1;
		case TGSettingsRootKindTelegram:
			return (NSInteger)[TGSettingsViewController telegramRows].count;
		case TGSettingsRootKindGroupTools:
			return (NSInteger)[TGSettingsViewController groupToolRows].count;
		case TGSettingsRootKindHelp:
			return (NSInteger)[TGSettingsViewController helpRows].count;
		default: break;
	}
	return 1;                      // log out
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if ((NSInteger)self.page == TGSettingsPageAutoDownload)
		return section == 0 ? @"Download automatically on" : @"Calls";
	if ((NSInteger)self.page == TGSettingsPageAutosave){
		if (section == 3)
			return nil;
		return [TGSettingsViewController autosaveTitles][section];
	}
	if ((NSInteger)self.page == TGSettingsPageWallpaper)
		return section == 1 ? @"From your account" : nil;
	switch (self.page){
		case TGSettingsPageAppearance:
			if (section == 0) return @"Style";
			if (section == 2) return @"Telegram themes";
			return nil;
		case TGSettingsPagePrivacy:
			return section == 0 ? @"Who can see" : nil;
		case TGSettingsPageNotifications:
			return @"Show notifications for";
		case TGSettingsPageData:
			return section == 1 ? @"Archive" : nil;
		default: break;
	}
	if (self.page != TGSettingsPageRoot)
		return nil;
	switch ([self rootKindForSection:section]){
		case TGSettingsRootKindSuggestions: return @"Suggested";
		case TGSettingsRootKindAccount:     return @"Account";
		case TGSettingsRootKindSettings:    return @"Settings";
		case TGSettingsRootKindStories:     return @"Stories";
		case TGSettingsRootKindTelegram:    return @"Telegram";
		case TGSettingsRootKindGroupTools:  return @"Group tools";
		case TGSettingsRootKindHelp:        return @"Help";
		default: break;
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if ((NSInteger)self.page == TGSettingsPageAutoDownload)
		return section == 0
			? @"Telegram cannot report which settings are in force, so these rows "
			  @"show what this device last applied."
			: @"Voice calls send less audio, which sounds worse and costs less "
			  @"data. It is written onto every network type at once.";
	if ((NSInteger)self.page == TGSettingsPageAutosave && section == 3)
		return @"Media arriving in these chats is copied into the camera roll. "
			   @"Per-chat exceptions are set from the chat itself.";
	if ((NSInteger)self.page == TGSettingsPageWallpaper && section == 1)
		return [TGCapabilities canShowWallpaper]
			? @"Colours and gradients cost nothing to draw. A photograph is held "
			  @"full-screen in memory, so pick a small one."
			: @"This device has too little memory for a photographic wallpaper, "
			  @"so only colours and gradients are offered.";
	if ((NSInteger)self.page == TGSettingsPageChatListLayout)
		return @"The chooser keeps the list as it is: the folder name sits in the "
			   @"title bar and tapping it raises the list of folders. The strip "
			   @"puts the folders under the title bar, where they are always "
			   @"visible and cost one row of chats.";
	if (self.page == TGSettingsPageRoot
			&& [self rootKindForSection:section] == TGSettingsRootKindStories)
		return @"Turn off to hide stories everywhere: no tray over the chat list "
			   @"and no story entries anywhere in the app.";
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
	if (self.page == TGSettingsPageData && section == 0)
		return @"Data Saver applies Telegram's low preset to Wi-Fi, mobile and "
			   @"roaming at once. Turning it off puts back whatever each network "
			   @"had before, and Auto-Download Media tunes them one by one.";
	if (self.page == TGSettingsPageRoot
			&& [self rootKindForSection:section] == TGSettingsRootKindGroupTools)
		return @"Pick a group or channel when you tap one of these.";
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
	if (self.page == TGSettingsPageRoot){
		NSInteger kind = [self rootKindForSection:indexPath.section];
		if (kind == TGSettingsRootKindAccount)
			return [self accountCellInTable:tableView at:indexPath];
		if (kind == TGSettingsRootKindLogout)
			return [self logoutCellInTable:tableView];
		if (kind == TGSettingsRootKindSuggestions)
			return [self suggestionCellInTable:tableView at:indexPath];
	}

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

	if ((NSInteger)self.page == TGSettingsPageAutoDownload)
		return [self fillAutoDownloadCell:cell at:indexPath];
	if ((NSInteger)self.page == TGSettingsPageAutosave)
		return [self fillAutosaveCell:cell at:indexPath];
	if ((NSInteger)self.page == TGSettingsPageWallpaper)
		return [self fillWallpaperCell:cell at:indexPath];
	if ((NSInteger)self.page == TGSettingsPageChatListLayout)
		return [self fillChatListLayoutCell:cell at:indexPath];
	if (self.page == TGSettingsPageRoot
			&& [self rootKindForSection:indexPath.section] == TGSettingsRootKindStories)
		return [self fillStoriesCell:cell];

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
				 @[@"Stickers",                 @"react"],
				 @[@"Folders",                  @"folder"],
				 @[@"Chat List",                @"folder"],
				 @[@"Proxy",                    @"data"],
				 @[@"Devices",                  @"devices"],
				 @[@"Language",                 @"language"]];
	return rows;
}

+ (NSArray *)telegramRows {
	static NSArray *rows = nil;
	if (!rows)
		rows = @[@[@"Telegram Premium", @"more"],
				 @[@"Telegram Stars",   @"react"],
				 @[@"Saved Message Tags", @"pin"]];
	return rows;
}

+ (NSArray *)groupToolRows {
	static NSArray *rows = nil;
	if (!rows)
		rows = @[@[@"Members and Admins", @"devices"],
				 @[@"Invite Links",       @"forward"],
				 @[@"Recent Actions",     @"search"]];
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

	NSInteger kind = [self rootKindForSection:indexPath.section];
	NSArray *table = nil;
	if (kind == TGSettingsRootKindSettings)
		table = [TGSettingsViewController rootSettingsRows];
	else if (kind == TGSettingsRootKindTelegram)
		table = [TGSettingsViewController telegramRows];
	else if (kind == TGSettingsRootKindGroupTools)
		table = [TGSettingsViewController groupToolRows];
	else if (kind == TGSettingsRootKindHelp)
		table = [TGSettingsViewController helpRows];

	if (table && (NSUInteger)indexPath.row < table.count){
		NSArray *row = table[indexPath.row];
		cell.textLabel.text = row[0];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.imageView.image = [TGIcons menuGlyphNamed:row[1]];
		[cell.imageView tg_setTintColor:[theme secondaryTextColour]];
		if (kind == TGSettingsRootKindSettings
				&& [row[0] isEqualToString:@"Chat List"]){
			cell.detailTextLabel.text = [TGSettingsViewController chatListLayoutTitle];
			cell.detailTextLabel.textColor = [theme cellDetailColour];
		}
		[self markDisclosure:cell];
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
		button.adjustsImageWhenHighlighted = NO;
		button.adjustsImageWhenDisabled = NO;
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
					(int)(raw.size.width / 2) topCapHeight:0]
							  forState:UIControlStateNormal];
		if (rawHighlighted)
			[button setBackgroundImage:[rawHighlighted stretchableImageWithLeftCapWidth:
					(int)(rawHighlighted.size.width / 2) topCapHeight:0]
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
	if (self.page == TGSettingsPageRoot){
		NSInteger kind = [self rootKindForSection:indexPath.section];
		if (kind == TGSettingsRootKindLogout)
			return 45;
		if (kind == TGSettingsRootKindSuggestions)
			return 64;
	}
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

- (UITableViewCell *)fillStoriesCell:(UITableViewCell *)cell {
	cell.textLabel.text = @"Show Stories";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = [TGSettingsViewController storiesEnabled];
	[toggle addTarget:self action:@selector(storiesToggled:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)fillChatListLayoutCell:(UITableViewCell *)cell
										 at:(NSIndexPath *)path {
	NSArray *layouts = [TGSettingsViewController chatListLayouts];
	if ((NSUInteger)path.row >= layouts.count)
		return cell;
	cell.textLabel.text = [TGSettingsViewController chatListLayoutTitles][path.row];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	[self markChecked:[layouts[path.row] isEqualToString:
			[TGSettingsViewController chatListLayout]] on:cell];
	return cell;
}

- (UITableViewCell *)fillPrivacyCell:(UITableViewCell *)cell at:(NSIndexPath *)path {
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	[self markDisclosure:cell];

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
	[self markChecked:([language[@"id"] isKindOfClass:[NSString class]]
			&& [language[@"id"] isEqualToString:self.currentLanguage]) on:cell];
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
		[self markChecked:(indexPath.row == [TGTheme shared].style) on:cell];
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
		[self markDisclosure:cell];
		return cell;
	}

	NSArray *files = [TGTheme availableThemeFiles];
	NSString *current = [TGTheme shared].importedName;
	if (indexPath.row == 0){
		cell.textLabel.text = @"None";
		[self markChecked:(current == nil) on:cell];
		return cell;
	}
	if ((NSUInteger)(indexPath.row - 1) >= files.count)
		return cell;
	NSString *path = files[indexPath.row - 1];
	NSString *label = [path.lastPathComponent stringByDeletingPathExtension];
	cell.textLabel.text = label;
	cell.detailTextLabel.text = path.pathExtension;
	[self markChecked:[current isEqualToString:label] on:cell];
	return cell;
}

- (UITableViewCell *)suggestionCellInTable:(UITableView *)tableView
										at:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGSettingsSuggestionCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];
	[[TGTheme shared] styleCell:cell];
	cell.accessoryType = UITableViewCellAccessoryNone;

	NSDictionary *suggestion = self.suggestions[indexPath.row];
	cell.textLabel.text = suggestion[@"title"];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
	cell.detailTextLabel.text = suggestion[@"subtitle"];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.numberOfLines = 2;
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];

	UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
	close.frame = CGRectMake(0, 0, 34, 34);
	close.titleLabel.font = [UIFont boldSystemFontOfSize:17];
	[close setTitle:@"✕" forState:UIControlStateNormal];
	[close setTitleColor:[[TGTheme shared] secondaryTextColour]
				forState:UIControlStateNormal];
	close.tag = indexPath.row;
	[close addTarget:self action:@selector(suggestionDismissTapped:)
	 forControlEvents:UIControlEventTouchUpInside];
	cell.accessoryView = close;
	return cell;
}

- (UITableViewCell *)fillAutoDownloadCell:(UITableViewCell *)cell at:(NSIndexPath *)path {
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];

	if (path.section == 0){
		NSString *kind = [TGSettingsViewController networkKinds][path.row];
		cell.textLabel.text = [TGSettingsViewController networkTitles][path.row];
		cell.detailTextLabel.text = [self detailForNetwork:kind];
		[self markDisclosure:cell];
		return cell;
	}

	cell.textLabel.text = @"Use less data for calls";
	cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = self.lessCallData;
	[toggle addTarget:self action:@selector(lessCallDataToggled:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)fillAutosaveCell:(UITableViewCell *)cell at:(NSIndexPath *)path {
	cell.textLabel.font = [UIFont boldSystemFontOfSize:15];

	if (path.section == 3){
		cell.textLabel.text = @"Clear exceptions";
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1.0f];
		return cell;
	}

	NSString *scope = [TGSettingsViewController autosaveScopes][path.section];
	NSDictionary *settings = self.autosave[scope];
	cell.textLabel.text = path.row == 0 ? @"Photos" : @"Videos";
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = [settings[path.row == 0 ? @"photos" : @"videos"] boolValue];
	toggle.tag = path.section * 10 + path.row;
	[toggle addTarget:self action:@selector(autosaveToggled:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UIImage *)swatchForBackground:(NSDictionary *)background size:(CGSize)size {
	NSNumber *top = background[@"topColor"];
	NSNumber *bottom = background[@"bottomColor"];
	if (![top isKindOfClass:[NSNumber class]])
		return nil;
	UIColor *topColour = TGSettingsRGB((unsigned int)[top unsignedIntValue]);
	UIColor *bottomColour = [bottom isKindOfClass:[NSNumber class]]
			? TGSettingsRGB((unsigned int)[bottom unsignedIntValue]) : topColour;

	UIGraphicsBeginImageContextWithOptions(size, YES, 1.0f);
	CGContextRef context = UIGraphicsGetCurrentContext();
	if (!context){
		UIGraphicsEndImageContext();
		return nil;
	}
	CGFloat locations[2] = {0.0f, 1.0f};
	NSArray *colours = @[(id)topColour.CGColor, (id)bottomColour.CGColor];
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGGradientRef gradient = CGGradientCreateWithColors(space,
			(__bridge CFArrayRef)colours, locations);
	if (gradient){
		CGContextDrawLinearGradient(context, gradient, CGPointZero,
				CGPointMake(0, size.height), 0);
		CGGradientRelease(gradient);
	} else {
		CGContextSetFillColorWithColor(context, topColour.CGColor);
		CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
	}
	CGColorSpaceRelease(space);
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

- (UITableViewCell *)fillWallpaperCell:(UITableViewCell *)cell at:(NSIndexPath *)path {
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];

	if (path.section == 0){
		if (path.row == 0){
			cell.textLabel.text = @"Choose from library";
			cell.detailTextLabel.text = [TGTheme shared].wallpaper ? @"Set" : @"None";
			cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
			[self markDisclosure:cell];
			return cell;
		}
		cell.textLabel.text = @"Remove wallpaper";
		cell.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1.0f];
		return cell;
	}

	if (!self.backgrounds.count){
		cell.textLabel.text = self.backgroundsLoaded ? @"No backgrounds on this account"
													 : @"Loading...";
		cell.textLabel.font = [UIFont systemFontOfSize:15];
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	NSDictionary *background = self.backgrounds[path.row];
	if (![background isKindOfClass:[NSDictionary class]])
		return cell;
	NSString *name = [background[@"name"] isKindOfClass:[NSString class]]
			? background[@"name"] : @"Background";
	NSString *kind = [background[@"kind"] isKindOfClass:[NSString class]]
			? background[@"kind"] : @"wallpaper";
	cell.textLabel.text = name;
	cell.detailTextLabel.text = [background[@"topColor"] isKindOfClass:[NSNumber class]]
			? kind : [NSString stringWithFormat:@"%@, photo", kind];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.imageView.image = [self swatchForBackground:background
											   size:CGSizeMake(30, 30)];
	return cell;
}

+ (NSArray *)archiveKeys {
	static NSArray *keys = nil;
	if (!keys)
		keys = @[@"archiveUnknownSenders", @"keepUnmutedArchived",
				 @"keepFoldersArchived"];
	return keys;
}

+ (NSArray *)archiveTitles {
	static NSArray *titles = nil;
	if (!titles)
		titles = @[@"Archive new unknown chats", @"Keep unmuted chats archived",
				   @"Keep folder chats archived"];
	return titles;
}

- (UITableViewCell *)fillDataCell:(UITableViewCell *)cell at:(NSIndexPath *)indexPath {
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];

	if (indexPath.section == 0){
		if (indexPath.row == 0){
			cell.textLabel.text = @"Storage and cache";
			[self markDisclosure:cell];
			return cell;
		}
		if (indexPath.row == 1){
			cell.textLabel.text = @"Auto-Download Media";
			[self markDisclosure:cell];
			return cell;
		}
		if (indexPath.row == 2){
			cell.textLabel.text = @"Save to Camera Roll";
			[self markDisclosure:cell];
			return cell;
		}
		cell.textLabel.text = @"Data Saver";
		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.on = self.dataSaver;
		[toggle addTarget:self action:@selector(dataSaverToggled:)
		 forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	if (indexPath.section == 1){
		NSString *key = [TGSettingsViewController archiveKeys][indexPath.row];
		cell.textLabel.text = [TGSettingsViewController archiveTitles][indexPath.row];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.on = [self.archive[key] boolValue];
		toggle.tag = indexPath.row;
		[toggle addTarget:self action:@selector(archiveToggled:)
		 forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	cell.textLabel.text = @"Clear local database";
	cell.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1.0f];
	return cell;
}

- (void)dataSaverToggled:(UISwitch *)toggle {
	self.dataSaver = toggle.on;
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:toggle.on forKey:@"TGDataSaver"];

	if (toggle.on){
		NSDictionary *current = [defaults objectForKey:TGSettingsPresetDefaultsKey];
		[defaults setObject:([current isKindOfClass:[NSDictionary class]] ? current : @{})
					 forKey:TGSettingsSavedPresetsKey];
		[defaults synchronize];
		for (NSString *kind in [TGSettingsViewController networkKinds])
			[self rememberPreset:@"low" forNetwork:kind];
		[[TGClient shared] applyAutoDownloadPresetNamed:@"low"
										 toNetworkTypes:[TGSettingsViewController networkKinds]
											 completion:nil];
		return;
	}

	NSDictionary *saved = [defaults objectForKey:TGSettingsSavedPresetsKey];
	[defaults synchronize];
	for (NSString *kind in [TGSettingsViewController networkKinds]){
		NSString *name = ([saved isKindOfClass:[NSDictionary class]]
				&& [saved[kind] isKindOfClass:[NSString class]])
				? saved[kind] : @"high";
		[self rememberPreset:name forNetwork:kind];
		[[TGClient shared] applyAutoDownloadPresetNamed:name
										 toNetworkTypes:@[kind]
											 completion:nil];
	}
}

- (void)archiveToggled:(UISwitch *)toggle {
	static NSDictionary *serverKeys = nil;
	if (!serverKeys)
		serverKeys = @{@"archiveUnknownSenders" : @"archiveAndMuteNewChatsFromUnknownUsers",
					   @"keepUnmutedArchived"   : @"keepUnmutedChatsArchived",
					   @"keepFoldersArchived"   : @"keepChatsFromFoldersArchived"};

	NSString *key = [TGSettingsViewController archiveKeys][toggle.tag];
	BOOL previous = [self.archive[key] boolValue];
	self.archive[key] = @(toggle.on);

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] updateArchiveChatListSettings:@{serverKeys[key] : @(toggle.on)}
										  completion:^(BOOL ok){
		if (ok)
			return;
		weakSelf.archive[key] = @(previous);
		[weakSelf.tableView reloadData];
	}];
}

- (void)lessCallDataToggled:(UISwitch *)toggle {
	self.lessCallData = toggle.on;
	[[NSUserDefaults standardUserDefaults] setBool:toggle.on
											forKey:TGSettingsLessCallDataKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[[TGClient shared] setUseLessDataForCalls:toggle.on completion:nil];
}

- (void)autosaveToggled:(UISwitch *)toggle {
	NSInteger section = toggle.tag / 10;
	NSInteger row = toggle.tag % 10;
	if ((NSUInteger)section >= [TGSettingsViewController autosaveScopes].count)
		return;
	NSString *scope = [TGSettingsViewController autosaveScopes][section];
	NSDictionary *settings = self.autosave[scope];

	BOOL photos = [settings[@"photos"] boolValue];
	BOOL videos = [settings[@"videos"] boolValue];
	long long maxVideo = [settings[@"maxVideoBytes"] longLongValue];
	if (maxVideo <= 0)
		maxVideo = 10 * 1024 * 1024;
	if (row == 0) photos = toggle.on;
	else          videos = toggle.on;

	self.autosave[scope] = @{@"photos"        : @(photos),
							 @"videos"        : @(videos),
							 @"maxVideoBytes" : @(maxVideo)};
	[[TGClient shared] setAutosavePhotos:photos
								  videos:videos
						   maxVideoBytes:maxVideo
								forScope:scope];
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

	if ((NSInteger)self.page == TGSettingsPageAutoDownload){
		[self tapAutoDownload:indexPath];
		return;
	}
	if ((NSInteger)self.page == TGSettingsPageAutosave){
		if (indexPath.section == 3)
			[self confirmClearAutosaveExceptions];
		return;
	}
	if ((NSInteger)self.page == TGSettingsPageWallpaper){
		[self tapWallpaper:indexPath];
		return;
	}
	if ((NSInteger)self.page == TGSettingsPageChatListLayout){
		NSArray *layouts = [TGSettingsViewController chatListLayouts];
		if ((NSUInteger)indexPath.row < layouts.count)
			[TGSettingsViewController setChatListLayout:layouts[indexPath.row]];
		[tableView reloadData];
		return;
	}

	switch (self.page){
		case TGSettingsPageAppearance: [self tapAppearance:indexPath]; return;
		case TGSettingsPageNotifications: return;   // the switch does the work
		case TGSettingsPagePrivacy:    [self tapPrivacy:indexPath];    return;
		case TGSettingsPageLanguage:   [self tapLanguage:indexPath];   return;
		case TGSettingsPageBlocked:    [self tapBlocked:indexPath];    return;
		case TGSettingsPageData:
			if (indexPath.section == 0 && indexPath.row == 0){
				TGStorageViewController *storage = [[TGStorageViewController alloc] init];
				[self.navigationController pushViewController:storage animated:YES];
			} else if (indexPath.section == 0 && indexPath.row == 1){
				[self openPage:(TGSettingsPage)TGSettingsPageAutoDownload];
			} else if (indexPath.section == 0 && indexPath.row == 2){
				[self openPage:(TGSettingsPage)TGSettingsPageAutosave];
			} else if (indexPath.section == 2){
				[self confirmClearDatabase];
			}
			return;
		default: break;
	}

	NSInteger kind = [self rootKindForSection:indexPath.section];

	if (kind == TGSettingsRootKindSuggestions){
		[self acceptSuggestionAtRow:indexPath.row];
		return;
	}

	if (kind == TGSettingsRootKindAccount){
		UIViewController *profile = [[TGEditProfileViewController alloc] init];
		[self.navigationController pushViewController:profile animated:YES];
		return;
	}

	if (kind == TGSettingsRootKindSettings){
		switch (indexPath.row){
			case 0: [self openPage:TGSettingsPageNotifications]; break;
			case 1: [self openPage:TGSettingsPagePrivacy]; break;
			case 2: [self openPage:TGSettingsPageData]; break;
			case 3: [self openPage:TGSettingsPageAppearance]; break;
			case 4: {
				TGStickersViewController *stickers =
						[[TGStickersViewController alloc] init];
				stickers.page = TGStickersPageRoot;
				[self.navigationController pushViewController:stickers animated:YES];
				break;
			}
			case 5: {
				TGFoldersViewController *folders =
						[[TGFoldersViewController alloc] init];
				folders.page = TGFoldersPageList;
				[self.navigationController pushViewController:folders animated:YES];
				break;
			}
			case 6:
				[self openPage:(TGSettingsPage)TGSettingsPageChatListLayout];
				break;
			case 7: {
				TGProxyViewController *proxy = [[TGProxyViewController alloc] init];
				[self.navigationController pushViewController:proxy animated:YES];
				break;
			}
			case 8: {
				UIViewController *sessions = [[TGSessionsViewController alloc] init];
				[self.navigationController pushViewController:sessions animated:YES];
				break;
			}
			default: [self openPage:TGSettingsPageLanguage]; break;
		}
		return;
	}

	if (kind == TGSettingsRootKindStories)
		return;

	if (kind == TGSettingsRootKindTelegram){
		[self tapTelegramRow:indexPath.row];
		return;
	}

	if (kind == TGSettingsRootKindGroupTools){
		[self pickGroupForTool:indexPath.row];
		return;
	}

	if (kind == TGSettingsRootKindHelp){
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

- (void)tapTelegramRow:(NSInteger)row {
	UIViewController *next = nil;
	if (row == 0)
		next = [[TGPremiumViewController alloc] init];
	else if (row == 1)
		next = [[TGStarsViewController alloc] init];
	else
		next = [[TGSavedMessagesTagsViewController alloc] initWithTopicId:0];
	if (next)
		[self.navigationController pushViewController:next animated:YES];
}

/// The three group screens all want a chat, and settings has none, so the row
/// asks for one first. Ten is as many buttons as a 3.5-inch sheet can carry.
- (void)pickGroupForTool:(NSInteger)tool {
	NSMutableArray *groups = [NSMutableArray array];
	for (NSDictionary *chat in [TGClient shared].chats){
		if (![chat isKindOfClass:[NSDictionary class]])
			continue;
		if (![chat[@"isGroup"] boolValue])
			continue;
		[groups addObject:chat];
		if (groups.count >= 10)
			break;
	}
	if (!groups.count){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Group tools"
				message:@"No group or channel is loaded on this device yet."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
		return;
	}
	self.groupPicks = groups;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Choose a chat"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:nil];
	for (NSDictionary *chat in groups){
		NSString *title = [chat[@"title"] isKindOfClass:[NSString class]]
				? chat[@"title"] : @"Chat";
		[sheet addButtonWithTitle:title];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 120 + tool;
	[sheet showInView:self.view];
}

- (void)openGroupTool:(NSInteger)tool forChat:(NSDictionary *)chat {
	int64_t chatId = [chat[@"id"] longLongValue];
	NSString *title = [chat[@"title"] isKindOfClass:[NSString class]]
			? chat[@"title"] : nil;
	if (!chatId)
		return;

	UIViewController *next = nil;
	if (tool == 0){
		TGGroupMembersViewController *members =
				[[TGGroupMembersViewController alloc] init];
		members.chatId = chatId;
		members.initialMode = 0;
		next = members;
	} else if (tool == 1){
		next = [[TGInviteLinksViewController alloc] initWithChatId:chatId];
	} else {
		TGChatEventsViewController *events =
				[[TGChatEventsViewController alloc] initWithChatId:chatId];
		events.chatTitle = title;
		next = events;
	}
	[self.navigationController pushViewController:next animated:YES];
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
		if (indexPath.row == 0) [self openPage:(TGSettingsPage)TGSettingsPageWallpaper];
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

#pragma mark - auto-download

- (void)tapAutoDownload:(NSIndexPath *)indexPath {
	if (indexPath.section != 0)
		return;
	if ((NSUInteger)indexPath.row >= [TGSettingsViewController networkKinds].count)
		return;

	UIActionSheet *sheet = [[UIActionSheet alloc]
			initWithTitle:[TGSettingsViewController networkTitles][indexPath.row]
				 delegate:self
		cancelButtonTitle:nil
   destructiveButtonTitle:nil
		otherButtonTitles:@"Low", @"Medium", @"High", @"Nothing", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 130 + indexPath.row;
	[sheet showInView:self.view];
}

- (void)applyPresetIndex:(NSInteger)index toNetworkRow:(NSInteger)row {
	if ((NSUInteger)row >= [TGSettingsViewController networkKinds].count)
		return;
	NSString *kind = [TGSettingsViewController networkKinds][row];

	if (index >= (NSInteger)[TGSettingsViewController presetNames].count){
		[[TGClient shared] setAutoDownloadSettings:@{@"enabled" : @NO}
									forNetworkType:kind];
		[self rememberPreset:nil forNetwork:kind];
		[self.tableView reloadData];
		return;
	}

	NSString *name = [TGSettingsViewController presetNames][index];
	[self rememberPreset:name forNetwork:kind];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] applyAutoDownloadPresetNamed:name
									 toNetworkTypes:@[kind]
										 completion:^(BOOL ok){
		if (!ok)
			[weakSelf rememberPreset:nil forNetwork:kind];
		[weakSelf.tableView reloadData];
	}];
	[self.tableView reloadData];
}

- (void)confirmClearAutosaveExceptions {
	UIAlertView *confirm = [[UIAlertView alloc]
			initWithTitle:@"Clear exceptions"
				  message:@"Every chat goes back to the setting of its group."
				 delegate:self
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@"Clear", nil];
	confirm.tag = 403;
	[confirm show];
}

#pragma mark - wallpaper

- (void)tapWallpaper:(NSIndexPath *)indexPath {
	if (indexPath.section == 0){
		if (indexPath.row == 0){
			[self presentWallpaperPicker];
			return;
		}
		[[TGTheme shared] setWallpaperImage:nil];
		[[TGClient shared] resetDefaultBackgroundForDarkTheme:[[TGTheme shared] isDark]];
		[self.tableView reloadData];
		return;
	}

	if ((NSUInteger)indexPath.row >= self.backgrounds.count)
		return;
	NSDictionary *background = self.backgrounds[indexPath.row];
	if (![background isKindOfClass:[NSDictionary class]])
		return;
	[self applyBackground:background];
}

- (void)applyBackground:(NSDictionary *)background {
	BOOL isFill = [background[@"topColor"] isKindOfClass:[NSNumber class]]
			&& ![background[@"fileId"] isKindOfClass:[NSNumber class]];
	if (!isFill && ![TGCapabilities canShowWallpaper]){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Chat wallpaper"
				message:@"This device has too little memory to hold a photographic "
						@"wallpaper. Colours and gradients still work."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
		return;
	}
	if (![background[@"id"] isKindOfClass:[NSString class]])
		return;

	BOOL dark = [[TGTheme shared] isDark];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setDefaultBackgroundId:background[@"id"]
									  blurred:NO
									   moving:NO
								 forDarkTheme:dark
								   completion:^(NSDictionary *applied){
		if (!applied){
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Chat wallpaper"
					message:@"Telegram would not apply this background."
				   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
			return;
		}
		[weakSelf adoptBackgroundLocally:applied];
	}];
}

- (void)adoptBackgroundLocally:(NSDictionary *)background {
	NSNumber *fileId = background[@"fileId"];
	if ([fileId isKindOfClass:[NSNumber class]] && [TGCapabilities canShowWallpaper]){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:fileId.integerValue
							 completion:^(NSString *path){
			UIImage *image = path.length ? [UIImage imageWithContentsOfFile:path] : nil;
			if (image)
				[[TGTheme shared] setWallpaperImage:[weakSelf wallpaperSizedImage:image]];
			[weakSelf.tableView reloadData];
		}];
		return;
	}

	CGSize screen = [UIScreen mainScreen].bounds.size;
	UIImage *fill = [self swatchForBackground:background size:screen];
	if (fill)
		[[TGTheme shared] setWallpaperImage:fill];
	[self.tableView reloadData];
}

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

	if (sheet.tag == 89){
		if (index == sheet.destructiveButtonIndex)
			[[TGTheme shared] setWallpaperImage:nil];
		else
			[self presentWallpaperPicker];
		[self.tableView reloadData];
		return;
	}

	if (sheet.tag >= 130 && sheet.tag <= 132){
		[self applyPresetIndex:index toNetworkRow:sheet.tag - 130];
		return;
	}

	if (sheet.tag >= 120 && sheet.tag <= 122){
		if ((NSUInteger)index >= self.groupPicks.count)
			return;
		[self openGroupTool:sheet.tag - 120 forChat:self.groupPicks[index]];
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
	else if (alertView.tag == 403)
		[[TGClient shared] clearAutosaveExceptions];
}

@end

// vim:ft=objc

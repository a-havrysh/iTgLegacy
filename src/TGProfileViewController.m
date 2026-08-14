#import "TGProfileViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGForwardPicker.h"
#import "UIView+SafeTint.h"
#import "TGImageDecode.h"
#import "TGClient+ChatManagement.h"
#import "TGClient+SecretChats.h"
#import "TGClient+Groups.h"
#import "TGGroupMembersViewController.h"
#import "TGInviteLinksViewController.h"
#import "TGChatEventsViewController.h"
#import "TGChatViewController.h"
#import <ImageIO/ImageIO.h>

@interface TGProfilePermissionsController : UITableViewController
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, strong) NSMutableDictionary *permissions;
@end

@interface TGProfileViewController () <UIActionSheetDelegate, UIAlertViewDelegate,
		UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSArray *details;   // label/value pairs
@property (nonatomic, strong) NSArray *photos;    // flattened messages
@property (nonatomic, strong) NSArray *files;
@property (nonatomic, strong) NSArray *members;
@property (nonatomic, strong) NSArray *gifts;
@property (nonatomic, assign) BOOL blocked;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSArray *actionNames;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, strong) NSString *phoneNumber;
@property (nonatomic, strong) UIImage *avatarImage;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, assign) BOOL isContact;
@property (nonatomic, strong) NSString *firstName;
@property (nonatomic, strong) NSString *lastName;
@property (nonatomic, strong) NSArray *manageRows;
@property (nonatomic, strong) NSArray *sectionKinds;
@property (nonatomic, assign) BOOL canEditChat;
@property (nonatomic, assign) BOOL isChatAdmin;
@property (nonatomic, assign) BOOL isChannelChat;
@property (nonatomic, assign) BOOL isSupergroupChat;
@property (nonatomic, assign) NSInteger slowModeDelay;
@end

static const CGFloat kActionButtonHeight = 45.0f;
static const CGFloat kActionButtonGap = 8.0f;
static const CGFloat kTitleContainerHeight = 86.0f;
static const CGFloat kProfileAvatarSide = 70.0f;
static const CGFloat kProfileAvatarRadius = 10.0f;
static const CGFloat kMemberRowHeight = 49.0f;
static const CGFloat kMemberAvatarSide = 36.0f;
static const CGFloat kStripInset = 6.0f;
static const CGFloat kStripThumbSide = 76.0f;

static CGFloat TGProfileRetinaPixel(void) {
	return [UIScreen mainScreen].scale > 1.5f ? 0.5f : 0.0f;
}

static UIColor *TGProfileListBackground(void) {
	TGTheme *theme = [TGTheme shared];
	if (theme.isFlat || theme.isDark || theme.importedName)
		return [theme listBackgroundColour];
	UIImage *pattern = [UIImage imageNamed:@"SettingsBackground.png"];
	if (pattern)
		return [UIColor colorWithPatternImage:pattern];
	return [theme listBackgroundColour];
}

static UIColor *TGProfileColour(int rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:1.0f];
}

static NSString *TGProfileText(id value) {
	if (![value isKindOfClass:[NSString class]])
		return nil;
	NSString *text = [value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return text.length ? text : nil;
}

static NSString *TGProfileNumberText(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [value stringValue];
	return TGProfileText(value);
}

static BOOL TGProfileBool(id value) {
	return [value isKindOfClass:[NSNumber class]] && [value boolValue];
}

static int64_t TGProfileInt64(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [value longLongValue];
	if ([value isKindOfClass:[NSString class]])
		return [value longLongValue];
	return 0;
}

static NSString *TGProfileInitial(NSString *name) {
	NSString *trimmed = TGProfileText(name);
	if (!trimmed.length)
		return @"?";
	NSRange first = [trimmed rangeOfComposedCharacterSequenceAtIndex:0];
	return [[trimmed substringWithRange:first] uppercaseString];
}

@implementation TGProfileViewController

- (instancetype)initWithChatId:(int64_t)chatId userId:(int64_t)userId title:(NSString *)title {
	if ((self = [super initWithStyle:UITableViewStyleGrouped])){
		_chatId = chatId;
		_userId = userId;
		_name = title ?: @"";
		_details = @[];
		_photos = @[];
		_files = @[];
		_manageRows = @[];
		[self rebuildSections];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Info";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = TGProfileListBackground();
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	[self buildHeader];
	[self loadDetails];
	[self loadMedia];
}

/// The profile as the current client draws it: a large picture centred, the
/// name and status under it, and a row of tiles for the things you actually do
/// here. The coloured block this replaced is the old design; everything since
/// puts the actions in reach instead of colouring the top of the screen.
- (void)buildHeader {
	CGFloat width = self.view.bounds.size.width;
	CGFloat side = kProfileAvatarSide;
	TGTheme *theme = [TGTheme shared];
	NSArray *actions = [self actionItems];
	CGFloat height = kTitleContainerHeight +
			actions.count * (kActionButtonHeight + kActionButtonGap);

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	header.backgroundColor = [UIColor clearColor];

	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake(9 + TGProfileRetinaPixel(), 14, side, side)];
	self.avatarView.layer.cornerRadius = kProfileAvatarRadius;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	self.avatarView.image = self.avatarImage
			?: [TGIcons avatarWithInitials:TGProfileInitial(self.name)
									  size:side
								  colourId:self.userId ?: self.chatId];
	[header addSubview:self.avatarView];

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(94, 24, width - 94 - 9, 24)];
	nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	nameLabel.text = TGProfileText(self.name) ?: @"";
	nameLabel.font = [UIFont boldSystemFontOfSize:19];
	nameLabel.backgroundColor = [UIColor clearColor];
	nameLabel.textColor = theme.isDark ? [theme primaryTextColour]
									   : TGProfileColour(0x222932);
	if (!theme.isDark){
		nameLabel.shadowColor = [TGProfileColour(0xedf0f5) colorWithAlphaComponent:0.28f];
		nameLabel.shadowOffset = CGSizeMake(0, 1);
	}
	[header addSubview:nameLabel];
	self.nameLabel = nameLabel;

	self.statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(94, 52, width - 94 - 9, 24)];
	self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.statusLabel.font = [UIFont systemFontOfSize:14];
	self.statusLabel.textColor = theme.isDark ? [theme secondaryTextColour]
											  : TGProfileColour(0x6d7d90);
	if (!theme.isDark){
		self.statusLabel.shadowColor =
				[TGProfileColour(0xedf0f5) colorWithAlphaComponent:0.28f];
		self.statusLabel.shadowOffset = CGSizeMake(0, 1);
	}
	self.statusLabel.backgroundColor = [UIColor clearColor];
	[header addSubview:self.statusLabel];

	[self buildActions:actions in:header atY:kTitleContainerHeight];

	[self refreshStatus];

	self.tableView.tableHeaderView = header;
	self.tableView.backgroundColor = TGProfileListBackground();

	if (self.avatarImage)
		return;
	NSNumber *fileId = self.userId
			? [[TGClient shared] photoFileIdForUserId:self.userId]
			: [[TGClient shared] photoFileIdForChat:self.chatId];
	if (![fileId isKindOfClass:[NSNumber class]])
		return;
	[self loadAvatarFile:fileId.integerValue];
}

- (void)loadAvatarFile:(NSInteger)fileId {
	if (fileId <= 0)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId completion:^(NSString *path){
		if (!path.length)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			UIImage *image = [UIImage imageWithContentsOfFile:path];
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				weakSelf.avatarImage = image;
				weakSelf.avatarView.image = image;
			});
		});
	}];
}

- (void)refreshStatus {
	__weak typeof(self) weakSelf = self;
	if (self.userId){
		[[TGClient shared] statusForUser:self.userId completion:^(NSString *status){
			weakSelf.statusLabel.text = TGProfileText(status) ?: @"";
		}];
		return;
	}
	if (!self.chatId)
		return;
	[[TGClient shared] memberCountForChat:self.chatId completion:^(NSInteger count){
		if (count > 0)
			weakSelf.statusLabel.text = [NSString stringWithFormat:@"%ld member%@",
					(long)count, count == 1 ? @"" : @"s"];
	}];
}

/// The tiles under the name: a glyph over a word, on a soft rounded plate.
/// Only the ones that mean something here - a group has no one to call.
- (NSArray *)actionItems {
	NSMutableArray *items = [NSMutableArray array];
	if (self.userId){
		[items addObject:@[@"Call",       @"call"]];
		[items addObject:@[@"Video Call", @"video"]];
	}
	if (self.chatId)
		[items addObject:(self.muted ? @[@"Unmute", @"unmute"] : @[@"Mute", @"mute"])];
	if (self.onSearchTapped && self.chatId)
		[items addObject:@[@"Search Messages", @"search"]];
	[items addObject:@[@"More", @"more"]];
	return items;
}

- (void)buildActions:(NSArray *)items in:(UIView *)header atY:(CGFloat)y {
	static UIImage *background = nil;
	static UIImage *backgroundPressed = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		UIImage *raw = [UIImage imageNamed:@"GroupedActionButton.png"];
		UIImage *rawPressed = [UIImage imageNamed:@"GroupedActionButton_Highlighted.png"];
		background = [raw stretchableImageWithLeftCapWidth:(int)(raw.size.width / 2)
											  topCapHeight:0];
		backgroundPressed = [rawPressed
				stretchableImageWithLeftCapWidth:(int)(rawPressed.size.width / 2)
									topCapHeight:0];
	});

	CGFloat width = header.bounds.size.width;

	for (NSUInteger i = 0; i < items.count; i++){
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = CGRectMake(9, y + i * (kActionButtonHeight + kActionButtonGap),
								  width - 18, kActionButtonHeight);
		button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		button.exclusiveTouch = YES;
		button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
		button.titleLabel.shadowOffset = CGSizeMake(0, 1);
		[button setBackgroundImage:background forState:UIControlStateNormal];
		[button setBackgroundImage:backgroundPressed forState:UIControlStateHighlighted];
		[button setTitle:items[i][0] forState:UIControlStateNormal];
		[button setTitleColor:TGProfileColour(0x4a6587) forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleShadowColor:[[UIColor whiteColor] colorWithAlphaComponent:0.45f]
						   forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor clearColor] forState:UIControlStateHighlighted];
		button.tag = i;
		[button addTarget:self action:@selector(actionTileTapped:)
		 forControlEvents:UIControlEventTouchUpInside];
		[header addSubview:button];
		if ([items[i][1] hasSuffix:@"mute"])
			self.muteButton = button;
	}
	self.actionNames = items;
}

- (void)actionTileTapped:(UIButton *)tile {
	if (tile.tag >= (NSInteger)self.actionNames.count)
		return;
	NSString *action = self.actionNames[tile.tag][1];

	if ([action isEqualToString:@"call"] || [action isEqualToString:@"video"]){
		if (!self.userId)
			return;
		[TGCallViewController presentForUserId:self.userId
										  name:self.name
									  outgoing:YES];
	} else if ([action hasSuffix:@"mute"]){
		self.muted = !self.muted;
		[[TGClient shared] setChat:self.chatId muted:self.muted];
		[self updateMuteButton];
	} else if ([action isEqualToString:@"search"]){
		if (self.onSearchTapped) self.onSearchTapped();
	} else {
		[self showMoreMenuFrom:tile];
	}
}

- (void)updateMuteButton {
	NSString *title = self.muted ? @"Unmute" : @"Mute";
	NSString *key = self.muted ? @"unmute" : @"mute";
	NSMutableArray *names = [self.actionNames mutableCopy];
	for (NSUInteger i = 0; i < names.count; i++){
		if ([names[i][1] hasSuffix:@"mute"])
			names[i] = @[title, key];
	}
	self.actionNames = names;
	[self.muteButton setTitle:title forState:UIControlStateNormal];
}

/// The "more" menu from the current client, minus what this app cannot do:
/// no secret chats, no gifts.
- (void)showMoreMenuFrom:(UIView *)tile {
	NSMutableArray *items = [NSMutableArray array];
	if (self.userId){
		if (!self.isContact && self.phoneNumber.length)
			[items addObject:@{@"title" : @"Add to contacts", @"icon" : @"edit"}];
		if (self.phoneNumber.length)
			[items addObject:@{@"title" : @"Share contact", @"icon" : @"forward"}];
		if (!self.chatId || ![[TGClient shared] isSecretChat:self.chatId])
			[items addObject:@{@"title" : @"Start secret chat", @"icon" : @"privacy"}];
	}
	if (self.chatId)
		[items addObject:@{@"title" : @"Auto-delete messages", @"icon" : @"delete"}];
	if (self.chatId)
		[items addObject:@{@"title" : @"Clear history", @"icon" : @"delete"}];
	if (!self.userId && self.chatId)
		[items addObject:@{@"title" : @"Leave group", @"icon" : @"delete",
						   @"destructive" : @YES}];
	if (self.userId)
		[items addObject:@{@"title" : (self.blocked ? @"Unblock user" : @"Block user"),
						   @"icon" : @"privacy", @"destructive" : @YES}];
	if (!items.count)
		return;

	CGPoint where = [tile convertPoint:CGPointMake(tile.bounds.size.width / 2,
												   tile.bounds.size.height)
								toView:self.navigationController.view];
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger index, NSString *title){
		[weakSelf runMoreAction:title];
	}];
}

- (void)runMoreAction:(NSString *)title {
	if ([title isEqualToString:@"Add to contacts"]){
		NSString *phone = self.phoneNumber;
		if (!phone.length)
			return;
		NSString *first = self.firstName.length ? self.firstName
											    : (TGProfileText(self.name) ?: phone);
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] addContactWithPhone:phone
									 firstName:first
									  lastName:(self.lastName ?: @"")
									completion:^(BOOL ok){
			if (ok) weakSelf.isContact = YES;
			[weakSelf showToast:(ok ? @"Added to contacts" : @"Could not add contact")];
		}];
		return;
	}

	if ([title isEqualToString:@"Start secret chat"]){
		[self startSecretChat];
		return;
	}

	if ([title isEqualToString:@"Leave group"]){
		UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:@"Leave group"
				message:@"You will stop receiving messages from this group."
			   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Leave", nil];
		confirm.tag = 72;
		[confirm show];
		return;
	}

	if ([title isEqualToString:@"Share contact"]){
		TGForwardPicker *picker = [[TGForwardPicker alloc] init];
		NSString *name = self.name;
		int64_t userId = self.userId;
		__weak typeof(self) weakSelf = self;
		picker.onPicked = ^(int64_t targetChatId){
			NSString *phone = weakSelf.phoneNumber;
			if (!phone.length){
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Share contact"
						message:@"This account does not show its phone number."
					   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
				[alert show];
				return;
			}
			[[TGClient shared] sendContactNamed:name phone:phone toChat:targetChatId];
		};
		(void)userId;
		[self.navigationController pushViewController:picker animated:YES];
		return;
	}

	if ([title isEqualToString:@"Auto-delete messages"]){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Delete messages after"
														  delegate:self
												 cancelButtonTitle:nil
											destructiveButtonTitle:nil
												 otherButtonTitles:@"Off", @"1 day",
															   @"1 week", @"1 month", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 70;
		[sheet showInView:self.view];
		return;
	}

	if ([title isEqualToString:@"Clear history"]){
		UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:@"Clear history"
				message:@"Every message in this chat will be removed for you."
			   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Clear", nil];
		confirm.tag = 71;
		[confirm show];
		return;
	}

	if (!self.userId)
		return;
	BOOL blocked = !self.blocked;
	[[TGClient shared] setUser:self.userId blocked:blocked];
	self.blocked = blocked;
	[self showToast:(blocked ? @"User blocked" : @"User unblocked")];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] isUserBlocked:self.userId completion:^(BOOL actual){
		weakSelf.blocked = actual;
	}];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == 74){
		NSArray *presets = [TGClient slowModePresets];
		if (index < 0 || index >= (NSInteger)presets.count)
			return;
		id preset = presets[index];
		NSInteger seconds = [preset isKindOfClass:[NSNumber class]]
				? [preset integerValue] : 0;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] setSlowModeDelay:seconds forChat:self.chatId
								 completion:^(BOOL ok){
			if (ok){
				weakSelf.slowModeDelay = seconds;
				[weakSelf loadManagement];
			}
			[weakSelf showToast:(ok ? @"Slow mode updated" : @"Could not change slow mode")];
		}];
		return;
	}

	if (sheet.tag != 70)
		return;
	static const NSInteger seconds[4] = {0, 86400, 604800, 2592000};
	if (index < 0 || index > 3)
		return;
	if (!self.chatId)
		return;
	[[TGClient shared] setChat:self.chatId autoDeleteSeconds:seconds[index]];
	[self showToast:(index == 0 ? @"Auto-delete off" : @"Auto-delete on")];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
	if (index == alert.cancelButtonIndex)
		return;
	if (alert.tag == 73 && self.chatId){
		NSString *title = nil;
		if ([alert respondsToSelector:@selector(textFieldAtIndex:)])
			title = TGProfileText([alert textFieldAtIndex:0].text);
		if (!title.length)
			return;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] setTitle:title forChat:self.chatId completion:^(BOOL ok){
			if (ok){
				weakSelf.name = title;
				weakSelf.nameLabel.text = title;
				[weakSelf loadManagement];
			}
			[weakSelf showToast:(ok ? @"Name updated" : @"Could not rename")];
		}];
		return;
	}
	if (alert.tag == 71 && self.chatId){
		[[TGClient shared] clearHistoryInChat:self.chatId];
		self.photos = @[];
		self.files = @[];
		[self.tableView reloadData];
		[self showToast:@"History cleared"];
	} else if (alert.tag == 72 && self.chatId){
		[[TGClient shared] setChat:self.chatId joined:NO];
		[self.navigationController popToRootViewControllerAnimated:YES];
	}
}

- (void)rebuildSections {
	NSMutableArray *kinds = [NSMutableArray arrayWithObject:@"details"];
	if (self.manageRows.count)
		[kinds addObject:@"manage"];
	[kinds addObject:@"members"];
	[kinds addObject:@"photos"];
	[kinds addObject:@"files"];
	self.sectionKinds = kinds;
}

- (NSString *)kindForSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sectionKinds.count)
		return @"files";
	return self.sectionKinds[section];
}

/// The administration rows a group or channel gets: who is in it, the links
/// that let people in, what happened lately, and the things an admin may
/// change about the chat itself. Anything the server says we may not do is
/// simply not offered.
- (void)loadManagement {
	if (self.userId || !self.chatId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] groupInfoForChat:self.chatId completion:^(NSDictionary *info){
		if (![info isKindOfClass:[NSDictionary class]])
			return;
		NSString *status = TGProfileText(info[@"myStatus"]) ?: @"";
		BOOL admin = [status isEqualToString:@"creator"]
				|| [status isEqualToString:@"administrator"];
		weakSelf.isChatAdmin = admin;
		weakSelf.canEditChat = TGProfileBool(info[@"canBeEdited"]) || admin;
		weakSelf.isChannelChat = TGProfileBool(info[@"isChannel"]);
		weakSelf.isSupergroupChat = TGProfileBool(info[@"isSupergroup"]);
		weakSelf.slowModeDelay = [info[@"slowModeDelay"] isKindOfClass:[NSNumber class]]
				? [info[@"slowModeDelay"] integerValue] : 0;

		NSMutableArray *rows = [NSMutableArray array];
		BOOL canListMembers = TGProfileBool(info[@"canGetMembers"]) || admin
				|| !weakSelf.isChannelChat;
		if (canListMembers)
			[rows addObject:@[@"Members", @"members", @""]];
		if (admin){
			[rows addObject:@[@"Administrators", @"admins", @""]];
			[rows addObject:@[@"Invite Links", @"links", @""]];
			[rows addObject:@[@"Recent Actions", @"events", @""]];
		}
		if (weakSelf.canEditChat){
			[rows addObject:@[(weakSelf.isChannelChat ? @"Channel Name" : @"Group Name"),
							  @"title", TGProfileText(info[@"title"]) ?: @""]];
			[rows addObject:@[@"Set Photo", @"photo", @""]];
		}
		if (admin && !weakSelf.isChannelChat){
			[rows addObject:@[@"Permissions", @"permissions", @""]];
			if (weakSelf.isSupergroupChat)
				[rows addObject:@[@"Slow Mode", @"slowmode",
								  [weakSelf slowModeTitle:weakSelf.slowModeDelay]]];
		}
		weakSelf.manageRows = rows;
		[weakSelf rebuildSections];
		[weakSelf.tableView reloadData];
	}];
}

- (NSString *)slowModeTitle:(NSInteger)seconds {
	if (seconds <= 0)
		return @"Off";
	if (seconds < 60)
		return [NSString stringWithFormat:@"%lds", (long)seconds];
	if (seconds < 3600)
		return [NSString stringWithFormat:@"%ldm", (long)(seconds / 60)];
	return [NSString stringWithFormat:@"%ldh", (long)(seconds / 3600)];
}

- (void)openManageRow:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.manageRows.count)
		return;
	NSString *key = self.manageRows[row][1];
	UINavigationController *navigation = self.navigationController;

	if ([key isEqualToString:@"members"] || [key isEqualToString:@"admins"]){
		TGGroupMembersViewController *members =
				[[TGGroupMembersViewController alloc] init];
		members.chatId = self.chatId;
		members.initialMode = [key isEqualToString:@"admins"] ? 1 : 0;
		[navigation pushViewController:members animated:YES];
		return;
	}

	if ([key isEqualToString:@"links"]){
		TGInviteLinksViewController *links =
				[[TGInviteLinksViewController alloc] initWithChatId:self.chatId];
		[navigation pushViewController:links animated:YES];
		return;
	}

	if ([key isEqualToString:@"events"]){
		TGChatEventsViewController *events =
				[[TGChatEventsViewController alloc] initWithChatId:self.chatId];
		events.chatTitle = TGProfileText(self.name);
		[navigation pushViewController:events animated:YES];
		return;
	}

	if ([key isEqualToString:@"title"]){
		UIAlertView *rename = [[UIAlertView alloc] initWithTitle:nil
				message:(self.isChannelChat ? @"Channel name" : @"Group name")
			   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Done", nil];
		rename.tag = 73;
		if ([rename respondsToSelector:@selector(setAlertViewStyle:)]){
			rename.alertViewStyle = UIAlertViewStylePlainTextInput;
			[rename textFieldAtIndex:0].text = TGProfileText(self.name) ?: @"";
		}
		[rename show];
		return;
	}

	if ([key isEqualToString:@"photo"]){
		[self pickChatPhoto];
		return;
	}

	if ([key isEqualToString:@"permissions"]){
		TGProfilePermissionsController *permissions =
				[[TGProfilePermissionsController alloc] initWithStyle:UITableViewStyleGrouped];
		permissions.chatId = self.chatId;
		[navigation pushViewController:permissions animated:YES];
		return;
	}

	if ([key isEqualToString:@"slowmode"]){
		NSArray *presets = [TGClient slowModePresets];
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Slow mode"
				delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
				otherButtonTitles:nil];
		for (id preset in presets){
			NSInteger seconds = [preset isKindOfClass:[NSNumber class]]
					? [preset integerValue] : 0;
			[sheet addButtonWithTitle:(seconds <= 0 ? @"Off"
					: [self slowModeTitle:seconds])];
		}
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 74;
		[sheet showInView:self.view];
	}
}

- (void)pickChatPhoto {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary]){
		[self showToast:@"No photo library"];
		return;
	}
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[self dismissViewControllerAnimated:YES completion:nil];
	UIImage *image = info[UIImagePickerControllerEditedImage]
			?: info[UIImagePickerControllerOriginalImage];
	if (![image isKindOfClass:[UIImage class]] || !self.chatId)
		return;

	CGFloat side = MAX(image.size.width, image.size.height);
	UIImage *scaled = image;
	if (side > 640.0f){
		CGFloat factor = 640.0f / side;
		CGSize target = CGSizeMake(floorf(image.size.width * factor),
								   floorf(image.size.height * factor));
		UIGraphicsBeginImageContextWithOptions(target, YES, 1.0f);
		[image drawInRect:CGRectMake(0, 0, target.width, target.height)];
		scaled = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	}
	NSData *data = UIImageJPEGRepresentation(scaled, 0.87f);
	if (!data.length)
		return;
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"chat-photo.jpg"];
	if (![data writeToFile:path atomically:YES])
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPhotoAtPath:path forChat:self.chatId completion:^(BOOL ok){
		[weakSelf showToast:(ok ? @"Photo updated" : @"Could not set photo")];
		if (ok){
			weakSelf.avatarImage = scaled;
			weakSelf.avatarView.image = scaled;
		}
	}];
}

- (void)startSecretChat {
	if (!self.userId)
		return;
	UINavigationController *navigation = self.navigationController;
	NSString *name = TGProfileText(self.name) ?: @"";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] createSecretChatWithUser:self.userId
									 completion:^(NSDictionary *info){
		int64_t chatId = [info isKindOfClass:[NSDictionary class]]
				? TGProfileInt64(info[@"chatId"]) : 0;
		if (!chatId){
			[weakSelf showToast:@"Could not start secret chat"];
			return;
		}
		TGChatViewController *chat = [[TGChatViewController alloc] init];
		chat.chatId = chatId;
		chat.chatTitle = name;
		[navigation pushViewController:chat animated:YES];
	}];
}

- (void)loadDetails {
	if (self.chatId)
		self.muted = [[TGClient shared] isChatMuted:self.chatId];

	[self loadManagement];

	if (!self.userId && self.chatId){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] membersOfChat:self.chatId completion:^(NSArray *members){
			weakSelf.members = [members isKindOfClass:[NSArray class]] ? members : @[];
			[weakSelf.tableView reloadData];
		}];
		// A group has a description, a size and a link, none of which this
		// screen used to ask for.
		[[TGClient shared] chatProfile:self.chatId completion:^(NSDictionary *info){
			if (![info isKindOfClass:[NSDictionary class]])
				return;
			NSMutableArray *rows = [NSMutableArray array];
			NSString *about = TGProfileText(info[@"description"]);
			if (about)
				[rows addObject:@[@"about", about]];
			NSString *members = TGProfileNumberText(info[@"members"]);
			if (members.integerValue > 0)
				[rows addObject:@[@"members", members]];
			NSString *admins = TGProfileNumberText(info[@"admins"]);
			if (admins.integerValue > 0)
				[rows addObject:@[@"admins", admins]];
			NSString *link = TGProfileText(info[@"inviteLink"]);
			if (link)
				[rows addObject:@[@"invite link", link]];
			weakSelf.details = rows;
			[weakSelf.tableView reloadData];
		}];
		return;
	}

	if (!self.userId)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userInfo:self.userId completion:^(NSDictionary *user){
		if (![user isKindOfClass:[NSDictionary class]]) return;
		NSMutableArray *rows = [NSMutableArray array];
		NSString *phone = TGProfileText(user[@"phone_number"]);
		if (phone){
			[rows addObject:@[@"mobile", [@"+" stringByAppendingString:phone]]];
			weakSelf.phoneNumber = phone;
		}
		weakSelf.firstName = TGProfileText(user[@"first_name"]);
		weakSelf.lastName = TGProfileText(user[@"last_name"]);
		weakSelf.isContact = TGProfileBool(user[@"is_contact"])
				|| TGProfileBool(user[@"is_mutual_contact"]);
		if (!TGProfileText(weakSelf.name)){
			NSMutableArray *parts = [NSMutableArray array];
			if (weakSelf.firstName) [parts addObject:weakSelf.firstName];
			if (weakSelf.lastName) [parts addObject:weakSelf.lastName];
			if (parts.count){
				weakSelf.name = [parts componentsJoinedByString:@" "];
				weakSelf.nameLabel.text = weakSelf.name;
				if (!weakSelf.avatarImage)
					weakSelf.avatarView.image =
							[TGIcons avatarWithInitials:TGProfileInitial(weakSelf.name)
												   size:kProfileAvatarSide
											   colourId:weakSelf.userId];
			}
		}
		NSString *username = nil;
		id usernames = user[@"usernames"];
		if ([usernames isKindOfClass:[NSDictionary class]]){
			id active = usernames[@"active_usernames"];
			if ([active isKindOfClass:[NSArray class]] && [active count])
				username = TGProfileText([active objectAtIndex:0]);
		}
		if (!username)
			username = TGProfileText(user[@"username"]);
		if (username)
			[rows addObject:@[@"username", [@"@" stringByAppendingString:username]]];
		if (TGProfileBool(user[@"is_premium"]))
			[rows addObject:@[@"subscription", @"Telegram Premium"]];
		weakSelf.details = rows;
		[weakSelf.tableView reloadData];

		// The bio, the birthday and how many groups you share live in the full
		// record, which this screen never asked for - so "about" was missing
		// from a profile that has one.
		[[TGClient shared] userProfile:weakSelf.userId completion:^(NSDictionary *info){
			if (![info isKindOfClass:[NSDictionary class]])
				return;
			NSMutableArray *more = [rows mutableCopy];
			NSString *bio = TGProfileText(info[@"bio"]);
			if (bio)
				[more insertObject:@[@"about", bio]
						   atIndex:MIN((NSUInteger)2, more.count)];
			NSString *birthday = TGProfileText(info[@"birthday"]);
			if (birthday)
				[more addObject:@[@"birthday", birthday]];
			NSString *common = TGProfileNumberText(info[@"commonGroups"]);
			if (common.integerValue > 0)
				[more addObject:@[@"groups in common", common]];
			weakSelf.details = more;
			[weakSelf.tableView reloadData];
		}];

		// updateUser does not always carry a photo; getUser does.
		id photo = user[@"profile_photo"];
		id small = [photo isKindOfClass:[NSDictionary class]] ? photo[@"small"] : nil;
		id photoId = [small isKindOfClass:[NSDictionary class]] ? small[@"id"] : nil;
		if ([photoId isKindOfClass:[NSNumber class]] && !weakSelf.avatarImage)
			[weakSelf loadAvatarFile:[photoId integerValue]];
	}];
}

- (void)loadMedia {
	__weak typeof(self) weakSelf = self;
	if (self.userId){
		[[TGClient shared] giftsForUser:self.userId completion:^(NSArray *gifts){
			weakSelf.gifts = [gifts isKindOfClass:[NSArray class]] ? gifts : @[];
			[weakSelf.tableView reloadData];
		}];
		[[TGClient shared] isUserBlocked:self.userId completion:^(BOOL blocked){
			weakSelf.blocked = blocked;
		}];
	}

	if (!self.chatId)
		return;

	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterPhotoAndVideo"
						completion:^(NSArray *messages){
		weakSelf.photos = [messages isKindOfClass:[NSArray class]] ? messages : @[];
		[weakSelf.tableView reloadData];
	}];
	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterDocument"
						completion:^(NSArray *messages){
		weakSelf.files = [messages isKindOfClass:[NSArray class]] ? messages : @[];
		[weakSelf.tableView reloadData];
	}];
}

- (void)showToast:(NSString *)text {
	if (!text.length || !self.isViewLoaded)
		return;
	UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 34)];
	toast.center = CGPointMake(self.view.bounds.size.width / 2,
							   self.view.bounds.size.height - 70);
	toast.text = text;
	toast.textAlignment = NSTextAlignmentCenter;
	toast.font = [UIFont systemFontOfSize:14];
	toast.textColor = [UIColor whiteColor];
	toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75f];
	toast.layer.cornerRadius = 6;
	toast.clipsToBounds = YES;
	[self.view addSubview:toast];
	[UIView animateWithDuration:0.3 delay:1.0 options:0
					 animations:^{ toast.alpha = 0; }
					 completion:^(BOOL done){ [toast removeFromSuperview]; }];
}

/// Settings has its own navigation controller, and nothing was styling
/// its bar - an imported theme stopped at the top of the screen.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.backgroundColor = TGProfileListBackground();
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	if (self.chatId){
		BOOL muted = [[TGClient shared] isChatMuted:self.chatId];
		if (muted != self.muted){
			self.muted = muted;
			[self updateMuteButton];
		}
	}
	[self refreshStatus];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[TGPopupMenu dismiss];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.sectionKinds.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSString *kind = [self kindForSection:section];
	if ([kind isEqualToString:@"details"]) return self.details.count + self.gifts.count;
	if ([kind isEqualToString:@"manage"]) return self.manageRows.count;
	if ([kind isEqualToString:@"members"]) return self.members.count;
	if ([kind isEqualToString:@"photos"]) return self.photos.count ? 1 : 0;
	return self.files.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)inSection {
	NSString *kind = [self kindForSection:inSection];
	NSInteger section = [kind isEqualToString:@"members"] ? 1
			: ([kind isEqualToString:@"photos"] ? 2
			: ([kind isEqualToString:@"files"] ? 3 : 0));
	if ([kind isEqualToString:@"manage"] && self.manageRows.count)
		return self.isChannelChat ? @"Channel" : @"Group";
	if (section == 1 && self.members.count)
		return [NSString stringWithFormat:@"%lu member%@",
				(unsigned long)self.members.count, self.members.count == 1 ? @"" : @"s"];
	if (section == 2 && self.photos.count)
		return [NSString stringWithFormat:@"%lu photo%@ and video%@",
				(unsigned long)self.photos.count,
				self.photos.count == 1 ? @"" : @"s",
				self.photos.count == 1 ? @"" : @"s"];
	if (section == 3 && self.files.count)
		return [NSString stringWithFormat:@"%lu file%@",
				(unsigned long)self.files.count, self.files.count == 1 ? @"" : @"s"];
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (![[self kindForSection:section] isEqualToString:@"files"])
		return nil;
	if (self.details.count || self.gifts.count || self.members.count
			|| self.photos.count || self.files.count)
		return nil;
	return @"Nothing shared here yet.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *kind = [self kindForSection:indexPath.section];
	if ([kind isEqualToString:@"photos"]) return kStripThumbSide + kStripInset * 2;
	if ([kind isEqualToString:@"members"]) return kMemberRowHeight;
	return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *kind = [self kindForSection:indexPath.section];

	if ([kind isEqualToString:@"photos"])
		return [self photoStripCell:tableView];

	if ([kind isEqualToString:@"manage"])
		return [self manageCell:tableView row:indexPath.row];

	if ([kind isEqualToString:@"details"]){
		NSString *label = nil;
		NSString *value = nil;
		if (indexPath.row < (NSInteger)self.details.count){
			NSArray *pair = self.details[indexPath.row];
			label = pair[0];
			value = pair[1];
		} else {
			NSUInteger giftIndex = indexPath.row - self.details.count;
			id gift = giftIndex < self.gifts.count ? self.gifts[giftIndex] : nil;
			label = @"gift";
			NSString *giftTitle = [gift isKindOfClass:[NSDictionary class]]
					? TGProfileText(gift[@"title"]) : nil;
			NSString *stars = [gift isKindOfClass:[NSDictionary class]]
					? TGProfileNumberText(gift[@"starCount"]) : nil;
			if (giftTitle && stars.integerValue > 0)
				value = [NSString stringWithFormat:@"%@ - %@ stars", giftTitle, stars];
			else
				value = giftTitle ?: @"Gift";
		}
		return [self detailCell:tableView label:label value:value];
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.imageView.image = nil;
	[[TGTheme shared] styleCell:cell];
	CGFloat retinaPixel = TGProfileRetinaPixel();
	BOOL isMember = [kind isEqualToString:@"members"];
	if (isMember){
		cell.textLabel.font = [UIFont boldSystemFontOfSize:15 + retinaPixel];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:13 + retinaPixel];
	} else {
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	}
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.textColor = [TGTheme shared].isDark
			? [[TGTheme shared] secondaryTextColour] : TGProfileColour(0x888888);

	if (isMember){
		id member = indexPath.row < (NSInteger)self.members.count
				? self.members[indexPath.row] : nil;
		if (![member isKindOfClass:[NSDictionary class]])
			member = @{};
		int64_t userId = TGProfileInt64(member[@"id"]);
		NSString *name = TGProfileText(member[@"name"])
				?: TGProfileText([[TGClient shared] nameForUserId:userId]);
		cell.selectionStyle = userId ? UITableViewCellSelectionStyleBlue
									 : UITableViewCellSelectionStyleNone;
		cell.textLabel.text = name ?: @"";
		cell.detailTextLabel.text = TGProfileText(member[@"status"]);
		cell.imageView.image = [TGIcons avatarWithInitials:TGProfileInitial(name)
													  size:kMemberAvatarSide
												  colourId:userId];
	} else {
		id m = indexPath.row < (NSInteger)self.files.count
				? self.files[indexPath.row] : nil;
		if (![m isKindOfClass:[NSDictionary class]])
			m = @{};
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		cell.textLabel.text = TGProfileText(m[@"docName"]) ?: @"File";
		cell.detailTextLabel.text = nil;
		cell.imageView.image = [TGIcons document];
	}
	return cell;
}

/// A horizontal strip of thumbnails: a grid would mean a collection view,
/// which iOS 6 has but this screen does not need.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString *kind = [self kindForSection:indexPath.section];

	if ([kind isEqualToString:@"manage"]){
		[self openManageRow:indexPath.row];
		return;
	}

	if ([kind isEqualToString:@"members"]){
		[self openMemberAtRow:indexPath.row];
		return;
	}

	if ([kind isEqualToString:@"files"]){
		[self downloadFileAtRow:indexPath.row];
		return;
	}

	// The actions live in the tiles now; a row of the card copies its value,
	// which is the only thing there is to do with a phone number or a link.
	if (![kind isEqualToString:@"details"] || indexPath.row >= (NSInteger)self.details.count)
		return;
	NSString *value = self.details[indexPath.row][1];
	if (!value.length)
		return;
	[UIPasteboard generalPasteboard].string = value;
	[self showToast:@"Copied"];
}

- (void)openMemberAtRow:(NSInteger)row {
	if (row >= (NSInteger)self.members.count)
		return;
	id member = self.members[row];
	if (![member isKindOfClass:[NSDictionary class]])
		return;
	int64_t userId = TGProfileInt64(member[@"id"]);
	if (!userId || userId == self.userId)
		return;
	NSString *name = TGProfileText(member[@"name"])
			?: TGProfileText([[TGClient shared] nameForUserId:userId]) ?: @"";
	UINavigationController *navigation = self.navigationController;
	if (!navigation)
		return;
	[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
		TGProfileViewController *profile = [[TGProfileViewController alloc]
				initWithChatId:chatId userId:userId title:name];
		[navigation pushViewController:profile animated:YES];
	}];
}

- (void)downloadFileAtRow:(NSInteger)row {
	if (row >= (NSInteger)self.files.count)
		return;
	id m = self.files[row];
	if (![m isKindOfClass:[NSDictionary class]])
		return;
	id fileId = m[@"docId"];
	if (![fileId isKindOfClass:[NSNumber class]])
		fileId = m[@"photoId"];
	if (![fileId isKindOfClass:[NSNumber class]] || [fileId integerValue] <= 0){
		[self showToast:@"File unavailable"];
		return;
	}
	[self showToast:@"Downloading..."];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
		[weakSelf showToast:(path.length ? @"Downloaded" : @"Download failed")];
	}];
}

- (UITableViewCell *)detailCell:(UITableView *)tableView
						  label:(NSString *)label
						  value:(NSString *)value {
	TGTheme *theme = [TGTheme shared];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"detail"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"detail"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		UILabel *labelView = [[UILabel alloc] initWithFrame:CGRectMake(4, 13, 62, 16)];
		labelView.tag = 11;
		labelView.textAlignment = NSTextAlignmentRight;
		labelView.font = [UIFont boldSystemFontOfSize:13];
		labelView.backgroundColor = [UIColor clearColor];
		[cell.contentView addSubview:labelView];

		UILabel *valueView = [[UILabel alloc] initWithFrame:
				CGRectMake(78, 11, cell.contentView.bounds.size.width - 80, 20)];
		valueView.tag = 12;
		valueView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		valueView.font = [UIFont boldSystemFontOfSize:15];
		valueView.backgroundColor = [UIColor clearColor];
		[cell.contentView addSubview:valueView];
	}
	[theme styleCell:cell];

	UILabel *labelView = (UILabel *)[cell.contentView viewWithTag:11];
	UILabel *valueView = (UILabel *)[cell.contentView viewWithTag:12];
	labelView.text = label;
	labelView.textColor = theme.isDark ? [theme secondaryTextColour]
									   : TGProfileColour(0x5d708f);
	valueView.text = value;
	valueView.textColor = theme.isDark ? [theme primaryTextColour] : [UIColor blackColor];
	return cell;
}

- (UITableViewCell *)manageCell:(UITableView *)tableView row:(NSInteger)row {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"manage"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"manage"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.textColor = [TGTheme shared].isDark
			? [[TGTheme shared] secondaryTextColour] : TGProfileColour(0x888888);
	NSArray *item = row < (NSInteger)self.manageRows.count ? self.manageRows[row] : nil;
	cell.textLabel.text = item.count > 0 ? item[0] : @"";
	cell.detailTextLabel.text = item.count > 2 ? item[2] : nil;
	cell.imageView.image = nil;
	return cell;
}

- (UITableViewCell *)photoStripCell:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"strip"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"strip"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		UIScrollView *strip = [[UIScrollView alloc] initWithFrame:
				CGRectMake(0, 0, tableView.bounds.size.width,
						   kStripThumbSide + kStripInset * 2)];
		strip.tag = 99;
		strip.showsHorizontalScrollIndicator = NO;
		[cell.contentView addSubview:strip];
	}

	UIScrollView *strip = (UIScrollView *)[cell.contentView viewWithTag:99];
	for (UIView *v in strip.subviews)
		[v removeFromSuperview];

	CGFloat side = kStripThumbSide, gap = kStripInset, x = gap;
	for (id m in self.photos){
		if (![m isKindOfClass:[NSDictionary class]]) continue;
		id fileId = m[@"photoId"];
		if (![fileId isKindOfClass:[NSNumber class]] || [fileId integerValue] <= 0)
			continue;
		UIImageView *thumb = [[UIImageView alloc] initWithFrame:
				CGRectMake(x, kStripInset, side, side)];
		thumb.backgroundColor = [UIColor colorWithWhite:0.9f alpha:1];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
		thumb.layer.cornerRadius = 4;
		[strip addSubview:thumb];
		x += side + gap;

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			if (!path.length) return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				UIImage *image = TGDecodeSquareThumbnail(path, side);
				dispatch_async(dispatch_get_main_queue(), ^{
					thumb.image = image;
				});
			});
		}];
	}
	strip.contentSize = CGSizeMake(x, kStripThumbSide + kStripInset * 2);
	return cell;
}

@end

@implementation TGProfilePermissionsController

+ (NSString *)titleForKey:(NSString *)key {
	static NSDictionary *titles = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		titles = @{@"sendMessages"    : @"Send Messages",
				   @"sendAudios"      : @"Send Music",
				   @"sendDocuments"   : @"Send Files",
				   @"sendPhotos"      : @"Send Photos",
				   @"sendVideos"      : @"Send Videos",
				   @"sendVideoNotes"  : @"Send Video Notes",
				   @"sendVoiceNotes"  : @"Send Voice Notes",
				   @"sendPolls"       : @"Send Polls",
				   @"sendOther"       : @"Send Stickers & GIFs",
				   @"addLinkPreviews" : @"Embed Links",
				   @"reactToMessages" : @"Add Reactions",
				   @"changeInfo"      : @"Change Chat Info",
				   @"inviteUsers"     : @"Add Users",
				   @"pinMessages"     : @"Pin Messages",
				   @"createTopics"    : @"Create Topics"};
	});
	return titles[key] ?: key;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Permissions";
	self.permissions = [NSMutableDictionary dictionary];
	self.tableView.backgroundColor = TGProfileListBackground();
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	UIButton *done = [TGIcons headerButtonWithTitle:@"Done" bold:YES
											 target:self action:@selector(saveTapped)];
	if (done)
		self.navigationItem.rightBarButtonItem =
				[[UIBarButtonItem alloc] initWithCustomView:done];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] permissionsForChat:self.chatId
							   completion:^(NSDictionary *permissions){
		if ([permissions isKindOfClass:[NSDictionary class]])
			weakSelf.permissions = [permissions mutableCopy];
		[weakSelf.tableView reloadData];
	}];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)saveTapped {
	NSMutableDictionary *full = [NSMutableDictionary dictionary];
	for (NSString *key in [TGClient permissionKeys])
		full[key] = @([self.permissions[key] boolValue]);
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPermissions:full forChat:self.chatId completion:^(BOOL ok){
		if (ok){
			[weakSelf.navigationController popViewControllerAnimated:YES];
			return;
		}
		[[[UIAlertView alloc] initWithTitle:nil
				message:@"These permissions could not be changed."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [[TGClient permissionKeys] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return @"What members may do";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"permission"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"permission"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];

	NSArray *keys = [TGClient permissionKeys];
	NSString *key = indexPath.row < (NSInteger)keys.count ? keys[indexPath.row] : @"";
	cell.textLabel.text = [TGProfilePermissionsController titleForKey:key];

	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = [self.permissions[key] boolValue];
	toggle.tag = indexPath.row;
	[toggle addTarget:self action:@selector(permissionToggled:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	return cell;
}

- (void)permissionToggled:(UISwitch *)toggle {
	NSArray *keys = [TGClient permissionKeys];
	if (toggle.tag >= (NSInteger)keys.count)
		return;
	self.permissions[keys[toggle.tag]] = @(toggle.on);
}

@end

// vim:ft=objc

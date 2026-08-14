#import "TGProfileViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGForwardPicker.h"
#import "UIView+SafeTint.h"
#import "TGImageDecode.h"
#import <ImageIO/ImageIO.h>

@interface TGProfileViewController () <UIActionSheetDelegate, UIAlertViewDelegate>
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
@end

static const CGFloat kActionButtonHeight = 45.0f;
static const CGFloat kActionButtonGap = 8.0f;
static const CGFloat kTitleContainerHeight = 86.0f;

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
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Info";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] bubbleBorderColour];

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
	CGFloat side = 70;
	TGTheme *theme = [TGTheme shared];
	NSArray *actions = [self actionItems];
	CGFloat height = kTitleContainerHeight +
			actions.count * (kActionButtonHeight + kActionButtonGap);

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	header.backgroundColor = [UIColor clearColor];

	self.avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(9, 14, side, side)];
	self.avatarView.layer.cornerRadius = side * 0.12f;
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
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];

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
	if (sheet.tag != 70 || index == sheet.cancelButtonIndex)
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

- (void)loadDetails {
	if (self.chatId)
		self.muted = [[TGClient shared] isChatMuted:self.chatId];

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
												   size:70
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
	return 4;   // details, members, photos, files
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return self.details.count + self.gifts.count;
	if (section == 1) return self.members.count;
	if (section == 2) return self.photos.count ? 1 : 0;   // a strip of thumbnails
	return self.files.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
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
	if (section != 3)
		return nil;
	if (self.details.count || self.gifts.count || self.members.count
			|| self.photos.count || self.files.count)
		return nil;
	return @"Nothing shared here yet.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2) return 84;
	return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2)
		return [self photoStripCell:tableView];

	if (indexPath.section == 0){
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
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];

	if (indexPath.section == 1){
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
													  size:32 colourId:userId];
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

	if (indexPath.section == 1){
		[self openMemberAtRow:indexPath.row];
		return;
	}

	if (indexPath.section == 3){
		[self downloadFileAtRow:indexPath.row];
		return;
	}

	// The actions live in the tiles now; a row of the card copies its value,
	// which is the only thing there is to do with a phone number or a link.
	if (indexPath.section != 0 || indexPath.row >= (NSInteger)self.details.count)
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

- (UITableViewCell *)photoStripCell:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"strip"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"strip"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		UIScrollView *strip = [[UIScrollView alloc] initWithFrame:
				CGRectMake(0, 2, tableView.bounds.size.width, 80)];
		strip.tag = 99;
		strip.showsHorizontalScrollIndicator = NO;
		[cell.contentView addSubview:strip];
	}

	UIScrollView *strip = (UIScrollView *)[cell.contentView viewWithTag:99];
	for (UIView *v in strip.subviews)
		[v removeFromSuperview];

	CGFloat side = 76, gap = 4, x = gap;
	for (id m in self.photos){
		if (![m isKindOfClass:[NSDictionary class]]) continue;
		id fileId = m[@"photoId"];
		if (![fileId isKindOfClass:[NSNumber class]] || [fileId integerValue] <= 0)
			continue;
		UIImageView *thumb = [[UIImageView alloc] initWithFrame:CGRectMake(x, 2, side, side)];
		thumb.backgroundColor = [UIColor colorWithWhite:0.9f alpha:1];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
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
	strip.contentSize = CGSizeMake(x, 80);
	return cell;
}

@end

// vim:ft=objc

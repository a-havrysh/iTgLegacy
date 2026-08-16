#import "TGGroupMembersViewController.h"
#import "TGEmoji.h"
#import "TGClient.h"
#import "TGClient+Groups.h"
#import "TGClient+Contacts.h"
#import "TGClient+Privacy.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import "TGPopupMenu.h"
#import "TGAlertView.h"
#import "TGImageDecode.h"
#import "TGProfileViewController.h"
#import "UIView+SafeTint.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kMemberRowHeight    = 51.0f;
static const CGFloat kMemberAvatar       = 40.0f;
static const CGFloat kMemberAvatarLeft   = 5.0f;
static const CGFloat kMemberAvatarTop    = 5.0f;
static const CGFloat kMemberTextLeft     = 54.0f;
static const CGFloat kSectionHeaderHeight = 25.0f;
static const CGFloat kModeBarHeight      = 44.0f;
static const CGFloat kGroupButtonHeight  = 30.0f;
static const CGFloat kGroupSeparatorWidth = 2.0f;
static const CGFloat kGroupSideInset     = 8.0f;
static const NSInteger kMemberPageSize   = 50;
static const NSInteger kMemberDurationDay   = 86400;
static const NSInteger kMemberDurationWeek  = 604800;
static const NSInteger kMemberDurationMonth = 2592000;

static NSString *TGMembersDurationText(NSInteger untilDate) {
	if (untilDate <= 0)
		return @"Forever";
	return [NSDateFormatter localizedStringFromDate:
			[NSDate dateWithTimeIntervalSince1970:untilDate]
										  dateStyle:NSDateFormatterShortStyle
										  timeStyle:NSDateFormatterShortStyle];
}

static UIImage *TGMembersStretch(NSString *name, int leftCap) {
	UIImage *raw = [UIImage imageNamed:name];
	if (!raw)
		return nil;
	return [raw stretchableImageWithLeftCapWidth:leftCap topCapHeight:0];
}

static NSString *TGMembersString(NSDictionary *m, NSString *key) {
	id value = [m objectForKey:key];
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSInteger TGMembersInteger(NSDictionary *m, NSString *key) {
	id value = [m objectForKey:key];
	if ([value isKindOfClass:NSNumber.class])
		return [value integerValue];
	if ([value isKindOfClass:NSString.class])
		return [value integerValue];
	return 0;
}

static int64_t TGMembersUserId(NSDictionary *m) {
	id value = [m objectForKey:@"id"];
	return [value isKindOfClass:NSNumber.class] ? [value longLongValue] : 0;
}

@interface TGMemberRightsViewController : UIViewController <UITableViewDataSource,
		UITableViewDelegate, UIActionSheetDelegate> {
	int64_t _chatId;
	int64_t _userId;
	BOOL _restricting;
	BOOL _defaults;
}

@property (nonatomic, strong) NSString *memberName;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *keys;
@property (nonatomic, strong) NSMutableDictionary *values;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) NSInteger untilDate;
@property (nonatomic, assign) BOOL editable;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL saving;
@property (nonatomic, assign) BOOL canTransferOwnership;
@property (nonatomic, copy) void (^onSaved)(void);
@property (nonatomic, copy) void (^onTransferOwnership)(void);

- (id)initWithChatId:(int64_t)chatId userId:(int64_t)userId
				name:(NSString *)name restricting:(BOOL)restricting;
- (id)initWithDefaultPermissionsOfChat:(int64_t)chatId;

@end

@interface TGGroupAddMembersViewController : UITableViewController <UISearchBarDelegate> {
	int64_t _chatId;
}

@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *users;
@property (nonatomic, strong) NSMutableArray *picked;
@property (nonatomic, strong) NSMutableDictionary *pickedNames;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) NSInteger generation;
@property (nonatomic, assign) BOOL adding;
@property (nonatomic, copy) void (^onAdded)(void);

- (id)initWithChatId:(int64_t)chatId;

@end

@interface TGGroupPublicLinkViewController : UIViewController <UITableViewDataSource,
		UITableViewDelegate, UITextFieldDelegate> {
	int64_t _chatId;
}

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIView *footerView;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSArray *publicChats;
@property (nonatomic, strong) NSString *existingUsername;
@property (nonatomic, strong) NSString *checkedUsername;
@property (nonatomic, assign) BOOL isChannel;
@property (nonatomic, assign) BOOL checkOk;
@property (nonatomic, assign) BOOL saving;
@property (nonatomic, assign) NSInteger checkGeneration;
@property (nonatomic, copy) void (^onChanged)(void);

- (id)initWithChatId:(int64_t)chatId username:(NSString *)username isChannel:(BOOL)isChannel;

@end

@interface TGGroupMemberCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *titleSecondLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

- (void)setName:(NSString *)name;
@end

@implementation TGGroupMemberCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	BOOL flat = [[TGTheme shared] isFlat];
	if (!flat){
		UIImage *plate = TGMembersStretch(@"Cell102.png", 1);
		UIImage *platePressed = TGMembersStretch(@"CellHighlighted102.png", 1);
		if (plate)
			self.backgroundView = [[UIImageView alloc] initWithImage:plate];
		if (platePressed)
			self.selectedBackgroundView = [[UIImageView alloc] initWithImage:platePressed];
	}
	self.backgroundColor = [[TGTheme shared] listBackgroundColour];

	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake(kMemberAvatarLeft, kMemberAvatarTop, kMemberAvatar, kMemberAvatar)];
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.layer.cornerRadius = 4.0f;
	[self.contentView addSubview:self.avatarView];

	UIColor *titleColour = flat ? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];

	self.titleLabel = [[TGEmojiLabel alloc] initWithFrame:CGRectZero];
	self.titleLabel.backgroundColor = [UIColor clearColor];
	self.titleLabel.font = [UIFont systemFontOfSize:19];
	self.titleLabel.textColor = titleColour;
	self.titleLabel.highlightedTextColor = [UIColor whiteColor];
	self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.titleLabel];

	self.titleSecondLabel = [[TGEmojiLabel alloc] initWithFrame:CGRectZero];
	self.titleSecondLabel.backgroundColor = [UIColor clearColor];
	self.titleSecondLabel.font = [UIFont boldSystemFontOfSize:19];
	self.titleSecondLabel.textColor = titleColour;
	self.titleSecondLabel.highlightedTextColor = [UIColor whiteColor];
	self.titleSecondLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.titleSecondLabel];

	self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.subtitleLabel.backgroundColor = [UIColor clearColor];
	self.subtitleLabel.font = [UIFont systemFontOfSize:13.5f];
	self.subtitleLabel.textColor = [UIColor colorWithRed:0x88 / 255.0f green:0x88 / 255.0f
													blue:0x88 / 255.0f alpha:1.0f];
	self.subtitleLabel.highlightedTextColor = [UIColor whiteColor];
	self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.subtitleLabel];

	return self;
}

- (void)setName:(NSString *)name {
	NSString *first = name ?: @"";
	NSString *second = nil;
	NSRange space = [first rangeOfString:@" "];
	if (space.location != NSNotFound && space.location + 1 < first.length){
		second = [first substringFromIndex:space.location + 1];
		first = [first substringToIndex:space.location];
	}
	self.titleLabel.text = first;
	self.titleSecondLabel.text = second;
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGRect selectedFrame = self.selectedBackgroundView.frame;
	if (selectedFrame.size.width > 0){
		selectedFrame.origin.y = -1;
		selectedFrame.size.height = self.frame.size.height + 1;
		self.selectedBackgroundView.frame = selectedFrame;
	}

	CGSize viewSize = self.contentView.frame.size;
	self.avatarView.frame = CGRectMake(kMemberAvatarLeft, kMemberAvatarTop,
			kMemberAvatar, kMemberAvatar);

	CGFloat width = viewSize.width - kMemberTextLeft - 5;
	if (width < 10)
		width = 10;
	CGFloat titleHeight = self.titleLabel.font.lineHeight;
	CGFloat subtitleHeight = self.subtitleLabel.font.lineHeight;
	BOOL hasSubtitle = self.subtitleLabel.text.length != 0;

	CGFloat titleY = hasSubtitle
			? (CGFloat)(int)((viewSize.height - titleHeight - subtitleHeight - 1) / 2)
			: (CGFloat)(int)((viewSize.height - titleHeight) / 2) - 1;

	CGFloat firstWidth = width;
	if (self.titleSecondLabel.text.length != 0){
		firstWidth = [self.titleLabel.text sizeWithFont:self.titleLabel.font].width;
		if (firstWidth > width - 14)
			firstWidth = width - 14;
		CGFloat secondX = kMemberTextLeft + firstWidth + 4;
		CGFloat secondWidth = viewSize.width - 5 - secondX;
		if (secondWidth < 0)
			secondWidth = 0;
		self.titleSecondLabel.frame = CGRectMake(secondX, titleY, secondWidth, titleHeight);
	} else {
		self.titleSecondLabel.frame = CGRectZero;
	}
	self.titleLabel.frame = CGRectMake(kMemberTextLeft, titleY, firstWidth, titleHeight);

	if (!hasSubtitle){
		self.subtitleLabel.frame = CGRectZero;
		return;
	}
	self.subtitleLabel.frame = CGRectMake(kMemberTextLeft + 1, titleY + titleHeight + 0.5f,
			width, subtitleHeight);
}

@end

@implementation TGMemberRightsViewController

- (id)initWithChatId:(int64_t)chatId userId:(int64_t)userId
				name:(NSString *)name restricting:(BOOL)restricting {
	self = [super init];
	if (!self)
		return nil;
	_chatId = chatId;
	_userId = userId;
	_restricting = restricting;
	self.memberName = name.length ? name : @"this user";
	self.values = [NSMutableDictionary dictionary];
	self.keys = [NSArray array];
	return self;
}

- (id)initWithDefaultPermissionsOfChat:(int64_t)chatId {
	self = [self initWithChatId:chatId userId:0 name:nil restricting:YES];
	if (!self)
		return nil;
	_defaults = YES;
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	if (_defaults)
		self.title = @"Permissions";
	else
		self.title = _restricting ? @"Restrictions" : @"Admin Rights";
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
												  style:UITableViewStyleGrouped];
	self.tableView.autoresizingMask =
			UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 44;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[self.view addSubview:self.tableView];

	self.statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 120, self.view.bounds.size.width, 22)];
	self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.statusLabel.backgroundColor = [UIColor clearColor];
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.font = [UIFont systemFontOfSize:15];
	self.statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.statusLabel.hidden = YES;
	[self.view addSubview:self.statusLabel];

	self.spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	self.spinner.center = CGPointMake(self.view.bounds.size.width / 2, 90);
	self.spinner.autoresizingMask =
			UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	self.spinner.hidesWhenStopped = YES;
	[self.view addSubview:self.spinner];
	[self.spinner startAnimating];
	self.tableView.hidden = YES;

	[self loadCurrentState];
}

- (NSArray *)defaultAdminKeys {
	return [NSArray arrayWithObjects:@"can_manage_chat", @"can_change_info",
			@"can_delete_messages", @"can_invite_users", @"can_restrict_members",
			@"can_pin_messages", @"can_manage_video_chats", nil];
}

- (void)loadCurrentState {
	__weak typeof(self) weakSelf = self;
	if (_defaults){
		self.keys = [[TGClient shared] memberPermissionKeys] ?: [NSArray array];
		[[TGClient shared] defaultPermissionsInGroup:_chatId
										  completion:^(NSDictionary *permissions){
			TGMemberRightsViewController *me = weakSelf;
			if (!me)
				return;
			if (![permissions isKindOfClass:NSDictionary.class]){
				[me showLoadFailure];
				return;
			}
			[me.values removeAllObjects];
			for (NSString *key in me.keys)
				[me.values setObject:[NSNumber numberWithBool:
						[[permissions objectForKey:key] boolValue]] forKey:key];
			me.editable = YES;
			[me finishLoading];
		}];
		return;
	}
	if (_restricting){
		self.keys = [[TGClient shared] memberPermissionKeys] ?: [NSArray array];
		[[TGClient shared] permissionsOfUser:_userId inGroup:_chatId
								  completion:^(NSDictionary *permissions, BOOL isRestricted,
											   NSInteger untilDate){
			TGMemberRightsViewController *me = weakSelf;
			if (!me)
				return;
			if (![permissions isKindOfClass:NSDictionary.class]){
				[me showLoadFailure];
				return;
			}
			me.untilDate = untilDate;
			[me.values removeAllObjects];
			for (NSString *key in me.keys)
				[me.values setObject:[NSNumber numberWithBool:
						[[permissions objectForKey:key] boolValue]] forKey:key];
			me.editable = YES;
			[me finishLoading];
		}];
		return;
	}

	self.keys = [[TGClient shared] administratorRightKeys] ?: [NSArray array];
	[[TGClient shared] administratorRightsOfUser:_userId inGroup:_chatId
									  completion:^(NSDictionary *rights, NSString *status,
												   BOOL canBeEdited){
		TGMemberRightsViewController *me = weakSelf;
		if (!me)
			return;
		if (![rights isKindOfClass:NSDictionary.class]){
			[me showLoadFailure];
			return;
		}
		BOOL alreadyAdmin = [status isEqualToString:@"administrator"]
				|| [status isEqualToString:@"creator"];
		[me.values removeAllObjects];
		for (NSString *key in me.keys){
			BOOL on = [[rights objectForKey:key] boolValue];
			if (!alreadyAdmin)
				on = [[me defaultAdminKeys] containsObject:key];
			[me.values setObject:[NSNumber numberWithBool:on] forKey:key];
		}
		me.editable = canBeEdited || !alreadyAdmin;
		[me finishLoading];
	}];
}

- (void)showLoadFailure {
	[self.spinner stopAnimating];
	self.tableView.hidden = YES;
	self.statusLabel.text = _defaults
			? @"Could not read the group permissions."
			: @"Could not read this member.";
	self.statusLabel.hidden = NO;
}

- (void)finishLoading {
	[self.spinner stopAnimating];
	self.statusLabel.hidden = YES;
	self.loaded = YES;
	self.tableView.hidden = NO;
	[self.tableView reloadData];
	if (self.editable){
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
				initWithTitle:@"Done" style:UIBarButtonItemStyleDone
					   target:self action:@selector(save)];
	}
}

- (BOOL)hasExtraSection {
	if (!self.loaded || !self.editable || _defaults)
		return NO;
	return _restricting || self.canTransferOwnership;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [self hasExtraSection] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 1)
		return 1;
	return self.loaded ? (NSInteger)self.keys.count : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 1)
		return _restricting ? @"How long?" : nil;
	if (_defaults)
		return @"What can members do?";
	return _restricting ? @"What can this member do?" : @"What can this admin do?";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 1){
		if (_restricting)
			return self.untilDate > 0
					? @"The restrictions are lifted automatically when the time is up."
					: @"The restrictions stay until you lift them.";
		return [NSString stringWithFormat:@"%@ becomes the owner and you keep only admin rights.",
				self.memberName];
	}
	if (_defaults)
		return @"Anything turned off here is denied to every member who is not "
				@"an administrator.";
	if (!self.editable)
		return @"You cannot change the rights of this member.";
	if (_restricting)
		return [NSString stringWithFormat:@"Anything turned off here is denied to %@.",
				self.memberName];
	return [NSString stringWithFormat:@"%@ keeps only the rights left on here.",
			self.memberName];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 1){
		static NSString *extraReuse = @"TGMemberExtraCell";
		UITableViewCell *extra = [tableView dequeueReusableCellWithIdentifier:extraReuse];
		if (!extra){
			extra = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
										   reuseIdentifier:extraReuse];
			extra.textLabel.font = [UIFont systemFontOfSize:17];
		}
		if (_restricting){
			extra.textLabel.text = @"Duration";
			extra.textLabel.textColor = [[TGTheme shared] primaryTextColour];
			extra.detailTextLabel.text = TGMembersDurationText(self.untilDate);
			extra.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else {
			extra.textLabel.text = @"Transfer Ownership";
			extra.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1.0f];
			extra.detailTextLabel.text = nil;
			extra.accessoryType = UITableViewCellAccessoryNone;
		}
		return extra;
	}

	static NSString *reuse = @"TGMemberRightCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:reuse];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.textLabel.font = [UIFont systemFontOfSize:17];
	}

	if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.keys.count)
		return cell;
	NSString *key = [self.keys objectAtIndex:(NSUInteger)indexPath.row];
	cell.textLabel.text = _restricting
			? [[TGClient shared] titleForMemberPermissionKey:key]
			: [[TGClient shared] titleForAdministratorRightKey:key];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];

	UISwitch *toggle = [cell.accessoryView isKindOfClass:UISwitch.class]
			? (UISwitch *)cell.accessoryView : nil;
	if (!toggle){
		toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
		[toggle addTarget:self action:@selector(toggleChanged:)
		 forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
	}
	toggle.tag = indexPath.row;
	toggle.on = [[self.values objectForKey:key] boolValue];
	toggle.enabled = self.editable;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1)
		return;
	if (_restricting){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Restrict for"
														   delegate:self
												  cancelButtonTitle:@"Cancel"
											 destructiveButtonTitle:nil
												  otherButtonTitles:@"1 Day", @"1 Week",
								@"1 Month", @"Forever", nil];
		[sheet showInView:self.view];
		return;
	}
	if (self.onTransferOwnership)
		self.onTransferOwnership();
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == actionSheet.cancelButtonIndex)
		return;
	NSInteger now = (NSInteger)[[NSDate date] timeIntervalSince1970];
	switch (buttonIndex){
		case 0: self.untilDate = now + kMemberDurationDay; break;
		case 1: self.untilDate = now + kMemberDurationWeek; break;
		case 2: self.untilDate = now + kMemberDurationMonth; break;
		default: self.untilDate = 0; break;
	}
	[self.tableView reloadData];
}

- (void)toggleChanged:(UISwitch *)sender {
	if (sender.tag < 0 || sender.tag >= (NSInteger)self.keys.count)
		return;
	NSString *key = [self.keys objectAtIndex:(NSUInteger)sender.tag];
	[self.values setObject:[NSNumber numberWithBool:sender.on] forKey:key];
}

- (void)save {
	if (self.saving || !self.editable)
		return;
	self.saving = YES;
	self.navigationItem.rightBarButtonItem.enabled = NO;

	NSMutableDictionary *payload = [NSMutableDictionary dictionary];
	for (NSString *key in self.keys){
		if ([[self.values objectForKey:key] boolValue])
			[payload setObject:[NSNumber numberWithBool:YES] forKey:key];
	}

	__weak typeof(self) weakSelf = self;
	void (^done)(BOOL) = ^(BOOL ok){
		TGMemberRightsViewController *me = weakSelf;
		if (!me)
			return;
		me.saving = NO;
		me.navigationItem.rightBarButtonItem.enabled = YES;
		if (!ok){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not save these changes."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		if (me.onSaved)
			me.onSaved();
		[me.navigationController popViewControllerAnimated:YES];
	};

	if (_defaults){
		[[TGClient shared] setDefaultPermissions:payload
										 inGroup:_chatId
									  completion:done];
		return;
	}
	if (_restricting){
		[[TGClient shared] restrictMember:_userId
								  inGroup:_chatId
							  permissions:payload
								untilDate:self.untilDate
							   completion:done];
		return;
	}
	[[TGClient shared] promoteMember:_userId
							 inGroup:_chatId
							  rights:payload
						 customTitle:nil
						  completion:done];
}

@end

@implementation TGGroupAddMembersViewController

- (id)initWithChatId:(int64_t)chatId {
	self = [super initWithStyle:UITableViewStylePlain];
	if (!self)
		return nil;
	_chatId = chatId;
	self.picked = [NSMutableArray array];
	self.pickedNames = [NSMutableDictionary dictionary];
	self.users = [NSArray array];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Add Members";
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.rowHeight = 44;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	self.searchBar = [[UISearchBar alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, 44)];
	self.searchBar.delegate = self;
	self.searchBar.placeholder = @"Search";
	self.tableView.tableHeaderView = self.searchBar;

	UIView *background = [[UIView alloc] initWithFrame:self.tableView.bounds];
	background.backgroundColor = [[TGTheme shared] listBackgroundColour];
	background.autoresizingMask =
			UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

	self.statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 110, background.bounds.size.width, 22)];
	self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.statusLabel.backgroundColor = [UIColor clearColor];
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.font = [UIFont systemFontOfSize:15];
	self.statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.statusLabel.hidden = YES;
	[background addSubview:self.statusLabel];

	self.spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	self.spinner.center = CGPointMake(background.bounds.size.width / 2, 84);
	self.spinner.autoresizingMask =
			UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	self.spinner.hidesWhenStopped = YES;
	[background addSubview:self.spinner];
	self.tableView.backgroundView = background;

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Add" style:UIBarButtonItemStyleDone
				   target:self action:@selector(addPicked)];
	[self updateDoneButton];
	[self runSearchWithQuery:@""];
}

- (void)updateDoneButton {
	self.navigationItem.rightBarButtonItem.enabled = self.picked.count != 0 && !self.adding;
}

- (void)runSearchWithQuery:(NSString *)query {
	self.generation++;
	NSInteger generation = self.generation;
	[self.spinner startAnimating];
	self.statusLabel.hidden = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchContacts:query ?: @"" limit:kMemberPageSize
						   completion:^(NSArray *users){
		TGGroupAddMembersViewController *me = weakSelf;
		if (!me || me.generation != generation)
			return;
		[me.spinner stopAnimating];
		me.users = [users isKindOfClass:NSArray.class] ? users : [NSArray array];
		[me.tableView reloadData];
		me.statusLabel.text = @"Nobody here to add.";
		me.statusLabel.hidden = me.users.count != 0;
	}];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runDelayedSearch)
											   object:nil];
	[self performSelector:@selector(runDelayedSearch) withObject:nil afterDelay:0.3f];
}

- (void)runDelayedSearch {
	[self runSearchWithQuery:self.searchBar.text ?: @""];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (NSDictionary *)userAtRow:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.users.count)
		return nil;
	NSDictionary *user = [self.users objectAtIndex:(NSUInteger)row];
	return [user isKindOfClass:NSDictionary.class] ? user : nil;
}

- (NSString *)nameOfUser:(NSDictionary *)user {
	NSString *first = TGMembersString(user, @"first_name");
	NSString *last = TGMembersString(user, @"last_name");
	NSString *name = last.length
			? (first.length ? [NSString stringWithFormat:@"%@ %@", first, last] : last)
			: first;
	if (!name.length)
		name = TGMembersString(user, @"username");
	return name.length ? name : @"Unknown";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.users.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGGroupAddMemberCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];
		cell.textLabel.font = [UIFont systemFontOfSize:17];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	}
	NSDictionary *user = [self userAtRow:indexPath.row];
	cell.textLabel.text = user ? [self nameOfUser:user] : @"";
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	NSString *username = user ? TGMembersString(user, @"username") : @"";
	cell.detailTextLabel.text = username.length
			? [NSString stringWithFormat:@"@%@", username] : @"";
	int64_t userId = user ? TGMembersUserId(user) : 0;
	BOOL on = userId != 0
			&& [self.picked containsObject:[NSNumber numberWithLongLong:userId]];
	cell.accessoryType = on ? UITableViewCellAccessoryCheckmark
							: UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *user = [self userAtRow:indexPath.row];
	int64_t userId = user ? TGMembersUserId(user) : 0;
	if (userId == 0)
		return;
	NSNumber *key = [NSNumber numberWithLongLong:userId];
	if ([self.picked containsObject:key]){
		[self.picked removeObject:key];
		[self.pickedNames removeObjectForKey:key];
	} else {
		[self.picked addObject:key];
		[self.pickedNames setObject:[self nameOfUser:user] forKey:key];
	}
	[tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
					 withRowAnimation:UITableViewRowAnimationNone];
	[self updateDoneButton];
}

- (void)addPicked {
	if (self.adding || self.picked.count == 0)
		return;
	self.adding = YES;
	[self updateDoneButton];
	[self.searchBar resignFirstResponder];

	NSArray *ids = [self.picked copy];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] addMembers:ids toGroup:_chatId completion:^(NSArray *failedUserIds){
		TGGroupAddMembersViewController *me = weakSelf;
		if (!me)
			return;
		me.adding = NO;
		[me updateDoneButton];

		NSArray *failed = [failedUserIds isKindOfClass:NSArray.class]
				? failedUserIds : [NSArray array];
		if (failed.count == ids.count){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Nobody could be added. Their privacy "
					@"settings may not allow it."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		if (me.onAdded)
			me.onAdded();
		if (failed.count != 0){
			NSMutableArray *names = [NSMutableArray array];
			for (NSNumber *key in failed){
				NSString *name = [me.pickedNames objectForKey:key];
				[names addObject:name.length ? name : @"someone"];
			}
			[[[UIAlertView alloc] initWithTitle:nil
										message:[NSString stringWithFormat:
					@"%@ could not be added.", [names componentsJoinedByString:@", "]]
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
		}
		[me.navigationController popViewControllerAnimated:YES];
	}];
}

@end

@implementation TGGroupPublicLinkViewController

- (id)initWithChatId:(int64_t)chatId username:(NSString *)username isChannel:(BOOL)isChannel {
	self = [super init];
	if (!self)
		return nil;
	_chatId = chatId;
	self.isChannel = isChannel;
	self.existingUsername = username.length ? username : nil;
	self.publicChats = [NSArray array];
	return self;
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Public Link";
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
												  style:UITableViewStyleGrouped];
	self.tableView.autoresizingMask =
			UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 44;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[self.view addSubview:self.tableView];

	self.footerView = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, 44)];
	self.footerView.backgroundColor = [UIColor clearColor];
	self.footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 6, 280, 30)];
	self.footerLabel.backgroundColor = [UIColor clearColor];
	self.footerLabel.font = [UIFont systemFontOfSize:13];
	self.footerLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.footerLabel.numberOfLines = 0;
	[self.footerView addSubview:self.footerLabel];

	self.field = [[UITextField alloc] initWithFrame:CGRectMake(65, 0, 225, 43)];
	self.field.delegate = self;
	self.field.font = [UIFont systemFontOfSize:17];
	self.field.textColor = [[TGTheme shared] primaryTextColour];
	self.field.placeholder = @"link";
	self.field.text = self.existingUsername ?: @"";
	self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.field.autocorrectionType = UITextAutocorrectionTypeNo;
	self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
	self.field.returnKeyType = UIReturnKeyDone;
	[self.field addTarget:self action:@selector(fieldChanged)
		 forControlEvents:UIControlEventEditingChanged];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Save" style:UIBarButtonItemStyleDone
				   target:self action:@selector(save)];
	self.navigationItem.rightBarButtonItem.enabled = NO;

	[self rebuildSections];
	[self setFooterText:(self.isChannel
			? @"People can share this link and find this channel by searching for it."
			: @"People can share this link and find this group by searching for it.")
					 ok:NO];
	[self.field becomeFirstResponder];
}

- (void)rebuildSections {
	NSMutableArray *sections = [NSMutableArray arrayWithObject:@"link"];
	if (self.existingUsername.length)
		[sections addObject:@"remove"];
	if (self.publicChats.count)
		[sections addObject:@"chats"];
	self.sections = sections;
}

- (NSString *)kindOfSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return @"";
	return [self.sections objectAtIndex:(NSUInteger)section];
}

- (CGFloat)footerHeight {
	CGSize size = [self.footerLabel.text sizeWithFont:self.footerLabel.font
									constrainedToSize:CGSizeMake(280, 400)
										lineBreakMode:NSLineBreakByWordWrapping];
	self.footerLabel.frame = CGRectMake(20, 6, 280, size.height);
	return size.height + 16;
}

- (void)setFooterText:(NSString *)text ok:(BOOL)ok {
	self.footerLabel.text = text ?: @"";
	self.footerLabel.textColor = ok
			? [UIColor colorWithRed:0.16f green:0.55f blue:0.16f alpha:1.0f]
			: [[TGTheme shared] secondaryTextColour];
	[self footerHeight];
	[self.tableView beginUpdates];
	[self.tableView endUpdates];
}

- (NSString *)cleanedText {
	NSMutableString *clean = [NSMutableString string];
	NSString *raw = self.field.text ?: @"";
	for (NSUInteger i = 0; i < raw.length; i++){
		unichar c = [raw characterAtIndex:i];
		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
				|| (c >= '0' && c <= '9') || c == '_')
			[clean appendFormat:@"%C", c];
	}
	return clean;
}

- (void)fieldChanged {
	NSString *clean = [self cleanedText];
	if (![clean isEqualToString:self.field.text ?: @""])
		self.field.text = clean;

	self.checkOk = NO;
	self.checkedUsername = nil;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runCheck)
											   object:nil];

	if (clean.length == 0){
		[self setFooterText:(self.isChannel
				? @"People can share this link and find this channel by searching for it."
				: @"People can share this link and find this group by searching for it.") ok:NO];
		return;
	}
	if (clean.length < 5){
		[self setFooterText:@"A link needs at least five characters." ok:NO];
		return;
	}
	[self setFooterText:@"Checking..." ok:NO];
	[self performSelector:@selector(runCheck) withObject:nil afterDelay:0.4f];
}

- (void)runCheck {
	NSString *name = [self cleanedText];
	if (name.length < 5)
		return;
	self.checkGeneration++;
	NSInteger generation = self.checkGeneration;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] checkGroupUsername:name
								  forChat:_chatId
							   completion:^(NSString *status){
		TGGroupPublicLinkViewController *me = weakSelf;
		if (!me || me.checkGeneration != generation)
			return;
		NSString *value = [status isKindOfClass:NSString.class] ? status : @"error";
		[me handleCheckStatus:value forName:name];
	}];
}

- (void)handleCheckStatus:(NSString *)status forName:(NSString *)name {
	if ([status isEqualToString:@"ok"]){
		self.checkOk = YES;
		self.checkedUsername = name;
		self.navigationItem.rightBarButtonItem.enabled = !self.saving;
		[self setFooterText:[NSString stringWithFormat:@"t.me/%@ is free to take.", name]
						 ok:YES];
		return;
	}
	if ([status isEqualToString:@"too-many"]){
		[self setFooterText:@"This account already holds as many public links as it may. "
				@"Give one of them up first." ok:NO];
		[self loadCreatedPublicChats];
		return;
	}
	NSString *text = @"This link is not available.";
	if ([status isEqualToString:@"occupied"])
		text = @"This link is already taken.";
	else if ([status isEqualToString:@"invalid"])
		text = @"A link may hold only letters, digits and underscores, "
				@"and may not start with a digit.";
	else if ([status isEqualToString:@"error"])
		text = @"Could not check this link. Try again.";
	[self setFooterText:text ok:NO];
}

- (void)loadCreatedPublicChats {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] createdPublicChatsWithCompletion:^(NSArray *chats){
		TGGroupPublicLinkViewController *me = weakSelf;
		if (!me)
			return;
		NSArray *list = [chats isKindOfClass:NSArray.class] ? chats : [NSArray array];
		if (list.count == 0)
			return;
		me.publicChats = list;
		[me rebuildSections];
		[me.field resignFirstResponder];
		[me.tableView reloadData];
	}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if ([[self kindOfSection:section] isEqualToString:@"chats"])
		return (NSInteger)self.publicChats.count;
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	NSString *kind = [self kindOfSection:section];
	if ([kind isEqualToString:@"link"])
		return @"Link";
	if ([kind isEqualToString:@"chats"])
		return @"Your public links";
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if ([[self kindOfSection:section] isEqualToString:@"link"])
		return [self footerHeight];
	return 10;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if ([[self kindOfSection:section] isEqualToString:@"link"])
		return self.footerView;
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *kind = [self kindOfSection:indexPath.section];

	if ([kind isEqualToString:@"link"]){
		static NSString *reuse = @"TGGroupLinkFieldCell";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
		if (!cell){
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:reuse];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.textLabel.font = [UIFont systemFontOfSize:17];
			cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		}
		cell.textLabel.text = @"t.me/";
		if (self.field.superview != cell.contentView)
			[cell.contentView addSubview:self.field];
		self.field.frame = CGRectMake(65, 0,
				cell.contentView.bounds.size.width - 75, 43);
		self.field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		return cell;
	}

	if ([kind isEqualToString:@"remove"]){
		static NSString *removeReuse = @"TGGroupLinkRemoveCell";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:removeReuse];
		if (!cell){
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:removeReuse];
			cell.textLabel.font = [UIFont systemFontOfSize:17];
			cell.textLabel.textAlignment = NSTextAlignmentCenter;
			cell.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1.0f];
		}
		cell.textLabel.text = @"Remove Public Link";
		return cell;
	}

	static NSString *chatReuse = @"TGGroupLinkChatCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:chatReuse];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:chatReuse];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.textLabel.font = [UIFont systemFontOfSize:16];
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	}
	NSDictionary *chat = nil;
	if (indexPath.row >= 0 && indexPath.row < (NSInteger)self.publicChats.count){
		id entry = [self.publicChats objectAtIndex:(NSUInteger)indexPath.row];
		chat = [entry isKindOfClass:NSDictionary.class] ? entry : nil;
	}
	NSString *title = chat ? TGMembersString(chat, @"title") : @"";
	cell.textLabel.text = title.length ? title : @"Untitled";
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (![[self kindOfSection:indexPath.section] isEqualToString:@"remove"])
		return;

	[self.field resignFirstResponder];
	__weak typeof(self) weakSelf = self;
	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:nil
			message:@"Remove the public link? The group becomes private and the old link "
					@"stops working."
								  cancelButtonTitle:@"Cancel"
									  okButtonTitle:@"Remove"
									completionBlock:^(bool okPressed){
		TGGroupPublicLinkViewController *me = weakSelf;
		if (!me)
			return;
		if (okPressed)
			[me applyUsername:@""];
	}];
	[alert show];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return NO;
}

- (void)save {
	if (self.saving || !self.checkOk || !self.checkedUsername.length)
		return;
	[self applyUsername:self.checkedUsername];
}

- (void)applyUsername:(NSString *)username {
	if (self.saving)
		return;
	self.saving = YES;
	self.navigationItem.rightBarButtonItem.enabled = NO;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setGroupChat:_chatId username:username completion:^(BOOL ok){
		TGGroupPublicLinkViewController *me = weakSelf;
		if (!me)
			return;
		me.saving = NO;
		me.navigationItem.rightBarButtonItem.enabled = me.checkOk;
		if (!ok){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not save this link."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		if (me.onChanged)
			me.onChanged();
		[me.navigationController popViewControllerAnimated:YES];
	}];
}

@end

@interface TGGroupMembersViewController () <UITableViewDataSource, UITableViewDelegate,
		UISearchBarDelegate, UIActionSheetDelegate, UIAlertViewDelegate> {
	UIView *_modeBar;
	NSMutableArray *_groupButtons;
	NSMutableArray *_groupSeparators;
	int64_t _pendingUserId;
	NSArray *_manageActions;
}

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *members;
@property (nonatomic, strong) NSArray *searchResults;
@property (nonatomic, strong) NSString *query;
@property (nonatomic, strong) NSMutableDictionary *photos;
@property (nonatomic, strong) NSMutableSet *photosRequested;
@property (nonatomic, strong) NSDictionary *groupInfo;
@property (nonatomic, strong) NSDictionary *myRights;
@property (nonatomic, strong) NSString *myStatus;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *emptyPlaceholder;
@property (nonatomic, strong) UILabel *emptyTitleLabel;
@property (nonatomic, strong) UILabel *emptyHelpLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) NSInteger mode;
@property (nonatomic, assign) NSInteger totalCount;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) NSInteger generation;

@end

@implementation TGGroupMembersViewController

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[TGPopupMenu dismiss];
}

#pragma mark - modes

- (NSArray *)modeTitles {
	return [NSArray arrayWithObjects:@"Members", @"Admins", @"Banned", @"Restricted", nil];
}

- (NSString *)listFilterForMode:(NSInteger)mode {
	switch (mode){
		case 1: return @"administrators";
		case 2: return @"banned";
		case 3: return @"restricted";
		default: return @"recent";
	}
}

- (NSString *)searchFilterForMode:(NSInteger)mode {
	switch (mode){
		case 1: return @"administrators";
		case 2: return @"banned";
		case 3: return @"restricted";
		default: return @"members";
	}
}

- (NSString *)emptyTextForMode:(NSInteger)mode {
	switch (mode){
		case 1: return @"No administrators";
		case 2: return @"No removed users";
		case 3: return @"No restricted users";
		default: return @"No members";
	}
}

- (NSString *)emptyHelpForMode:(NSInteger)mode {
	switch (mode){
		case 1: return @"Nobody here has been promoted yet. Hold a member to give them admin rights.";
		case 2: return @"Nobody has been removed from this group.";
		case 3: return @"Nobody here is restricted. Hold a member to limit what they may do.";
		default: return @"Nobody else is in this group yet.";
	}
}

- (BOOL)hasSearchQuery {
	return [[self.query stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] != 0;
}

- (NSString *)sectionCaptionForMode:(NSInteger)mode {
	if ([self hasSearchQuery])
		return @"SEARCH RESULTS";
	switch (mode){
		case 1: return @"ADMINISTRATORS";
		case 2: return @"REMOVED USERS";
		case 3: return @"RESTRICTED USERS";
		default: return @"MEMBERS";
	}
}

#pragma mark - lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Members";
	NSInteger modeCount = (NSInteger)[self modeTitles].count;
	self.mode = (self.initialMode >= 0 && self.initialMode < modeCount)
			? self.initialMode : 0;
	self.members = [NSArray array];
	self.photos = [NSMutableDictionary dictionary];
	self.photosRequested = [NSMutableSet set];
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	CGRect bounds = self.view.bounds;

	_modeBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, kModeBarHeight)];
	_modeBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	UIImage *plate = TGMembersStretch(@"Footer.png", 1);
	if (plate && ![[TGTheme shared] isFlat])
		_modeBar.backgroundColor = [UIColor colorWithPatternImage:plate];
	else
		_modeBar.backgroundColor = [[TGTheme shared] inputBarColour];
	[self.view addSubview:_modeBar];

	UIView *hairline = [[UIView alloc] initWithFrame:
			CGRectMake(0, kModeBarHeight - 1, bounds.size.width, 1)];
	hairline.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	hairline.backgroundColor = [[TGTheme shared] separatorColour];
	[_modeBar addSubview:hairline];

	[self buildModeButtons];

	self.tableView = [[UITableView alloc] initWithFrame:
			CGRectMake(0, kModeBarHeight, bounds.size.width, bounds.size.height - kModeBarHeight)
													  style:UITableViewStylePlain];
	self.tableView.autoresizingMask =
			UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = kMemberRowHeight;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.separatorStyle = [[TGTheme shared] isFlat]
			? UITableViewCellSeparatorStyleSingleLine
			: UITableViewCellSeparatorStyleNone;
	[self.view addSubview:self.tableView];

	self.searchBar = [[UISearchBar alloc] initWithFrame:
			CGRectMake(0, 0, bounds.size.width, 44)];
	self.searchBar.delegate = self;
	self.searchBar.placeholder = @"Search";
	if ([self.searchBar respondsToSelector:@selector(setBarTintColor:)])
		self.searchBar.barTintColor = [[TGTheme shared] listBackgroundColour];
	else
		[self.searchBar tg_setTintColor:[UIColor colorWithWhite:0.68f alpha:1.0f]];
	self.tableView.tableHeaderView = self.searchBar;

	UIView *background = [[UIView alloc] initWithFrame:self.tableView.bounds];
	background.backgroundColor = [[TGTheme shared] listBackgroundColour];
	background.autoresizingMask =
			UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

	self.statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 110, background.bounds.size.width, 22)];
	self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.statusLabel.backgroundColor = [UIColor clearColor];
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.font = [UIFont systemFontOfSize:15];
	self.statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.statusLabel.hidden = YES;
	[background addSubview:self.statusLabel];

	self.emptyPlaceholder = [[UIView alloc] initWithFrame:
			CGRectMake(0, (CGFloat)(int)((background.bounds.size.height - 70) / 2) - 40,
					background.bounds.size.width, 70)];
	self.emptyPlaceholder.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
	self.emptyPlaceholder.backgroundColor = [UIColor clearColor];
	self.emptyPlaceholder.hidden = YES;

	UIColor *placeholderColour = [UIColor colorWithRed:0x86 / 255.0f green:0x94 / 255.0f
												  blue:0xa4 / 255.0f alpha:1.0f];

	self.emptyTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.emptyTitleLabel.backgroundColor = [UIColor clearColor];
	self.emptyTitleLabel.font = [UIFont boldSystemFontOfSize:14];
	self.emptyTitleLabel.textColor = placeholderColour;
	self.emptyTitleLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.5f];
	self.emptyTitleLabel.shadowOffset = CGSizeMake(0, 1);
	self.emptyTitleLabel.textAlignment = NSTextAlignmentCenter;
	[self.emptyPlaceholder addSubview:self.emptyTitleLabel];

	self.emptyHelpLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.emptyHelpLabel.backgroundColor = [UIColor clearColor];
	self.emptyHelpLabel.font = [UIFont systemFontOfSize:14];
	self.emptyHelpLabel.textColor = placeholderColour;
	self.emptyHelpLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.5f];
	self.emptyHelpLabel.shadowOffset = CGSizeMake(0, 1);
	self.emptyHelpLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyHelpLabel.numberOfLines = 0;
	[self.emptyPlaceholder addSubview:self.emptyHelpLabel];

	[background addSubview:self.emptyPlaceholder];

	self.retryButton = [TGIcons headerButtonWithTitle:@"Try Again" bold:NO
											   target:self action:@selector(reload)];
	self.retryButton.center = CGPointMake(background.bounds.size.width / 2, 150);
	self.retryButton.autoresizingMask =
			UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	self.retryButton.hidden = YES;
	[background addSubview:self.retryButton];

	self.spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	self.spinner.center = CGPointMake(background.bounds.size.width / 2, 84);
	self.spinner.autoresizingMask =
			UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	self.spinner.hidesWhenStopped = YES;
	[background addSubview:self.spinner];

	self.tableView.backgroundView = background;

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(handleLongPress:)];
	hold.minimumPressDuration = 0.4f;
	[self.tableView addGestureRecognizer:hold];

	[self loadGroupInfo];
	[self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[TGPopupMenu dismiss];
}

#pragma mark - mode button group

- (void)buildModeButtons {
	_groupButtons = [[NSMutableArray alloc] init];
	_groupSeparators = [[NSMutableArray alloc] init];

	NSArray *titles = [self modeTitles];
	CGFloat width = self.view.bounds.size.width - kGroupSideInset * 2;
	CGFloat originY = (CGFloat)(int)((kModeBarHeight - kGroupButtonHeight) / 2);

	UIView *group = [[UIView alloc] initWithFrame:
			CGRectMake(kGroupSideInset, originY, width, kGroupButtonHeight)];
	group.autoresizingMask = UIViewAutoresizingFlexibleWidth;

	NSInteger count = (NSInteger)titles.count;
	CGFloat usable = width - kGroupSeparatorWidth * (count - 1);
	CGFloat buttonWidth = (CGFloat)(int)(usable / count);

	UIColor *shadowColour = [UIColor colorWithRed:0x0e / 255.0f green:0x28 / 255.0f
											 blue:0x4d / 255.0f alpha:0.4f];

	CGFloat currentX = 0;
	for (NSInteger i = 0; i < count; i++){
		CGFloat thisWidth = (i == count - 1) ? (width - currentX) : buttonWidth;

		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.exclusiveTouch = YES;
		button.frame = CGRectMake(currentX, 0, thisWidth, kGroupButtonHeight);
		button.tag = i;
		[button setTitle:[titles objectAtIndex:(NSUInteger)i] forState:UIControlStateNormal];
		button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleShadowColor:shadowColour forState:UIControlStateNormal];
		[button setTitleShadowColor:shadowColour forState:UIControlStateHighlighted];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		button.adjustsImageWhenDisabled = NO;
		button.adjustsImageWhenHighlighted = NO;
		[button addTarget:self action:@selector(modeButtonPressed:)
			 forControlEvents:UIControlEventTouchDown];
		[group addSubview:button];
		[_groupButtons addObject:button];

		currentX += thisWidth;

		if (i + 1 < count){
			UIView *separator = [[UIView alloc] initWithFrame:
					CGRectMake(currentX, 0, kGroupSeparatorWidth, kGroupButtonHeight)];
			NSArray *names = [NSArray arrayWithObjects:@"ButtonGroupDivider.png",
					@"ButtonGroupDivider_LeftHighlighted.png",
					@"ButtonGroupDivider_RightHighlighted.png", nil];
			for (NSUInteger j = 0; j < names.count; j++){
				UIImage *art = TGMembersStretch([names objectAtIndex:j], 6);
				UIImageView *layer = [[UIImageView alloc] initWithImage:art];
				layer.tag = (NSInteger)(100 + j);
				layer.frame = separator.bounds;
				layer.alpha = (j == 0) ? 1.0f : 0.0f;
				[separator addSubview:layer];
			}
			[group addSubview:separator];
			[_groupSeparators addObject:separator];
			currentX += kGroupSeparatorWidth;
		}
	}

	[_modeBar addSubview:group];
	[self updateModeButtons];
}

- (void)updateModeButtons {
	NSUInteger count = _groupButtons.count;
	for (NSUInteger i = 0; i < count; i++){
		UIButton *button = [_groupButtons objectAtIndex:i];
		NSString *normalName = @"ButtonGroupCenter.png";
		NSString *highlightedName = @"ButtonGroupCenter_Highlighted.png";
		int leftCap = 1;
		if (i == 0){
			normalName = @"ButtonGroupLeft.png";
			highlightedName = @"ButtonGroupLeft_Highlighted.png";
			leftCap = 8;
		} else if (i == count - 1){
			normalName = @"ButtonGroupRight.png";
			highlightedName = @"ButtonGroupRight_Highlighted.png";
		}

		UIImage *normal = TGMembersStretch(normalName, leftCap);
		UIImage *highlighted = TGMembersStretch(highlightedName, leftCap);
		UIImage *shown = ((NSInteger)i == self.mode) ? highlighted : normal;
		[button setBackgroundImage:shown forState:UIControlStateNormal];
		[button setBackgroundImage:shown forState:UIControlStateHighlighted];
		if (!normal)
			button.backgroundColor = ((NSInteger)i == self.mode)
					? [[TGTheme shared] accentColour]
					: [UIColor colorWithWhite:0.62f alpha:1.0f];
	}

	for (NSUInteger i = 0; i < _groupSeparators.count; i++){
		UIView *separator = [_groupSeparators objectAtIndex:i];
		UIView *normal = [separator viewWithTag:100];
		UIView *leftLit = [separator viewWithTag:101];
		UIView *rightLit = [separator viewWithTag:102];
		UIView *shown = normal;
		if (self.mode == (NSInteger)i)
			shown = leftLit;
		else if (self.mode == (NSInteger)i + 1)
			shown = rightLit;
		shown.alpha = 1.0f;
		[separator bringSubviewToFront:shown];
		if (normal != shown)
			normal.alpha = 0.0f;
		if (leftLit != shown)
			leftLit.alpha = 0.0f;
		if (rightLit != shown)
			rightLit.alpha = 0.0f;
	}
}

- (void)modeButtonPressed:(UIButton *)button {
	if (self.mode == button.tag)
		return;
	self.mode = button.tag;
	[self updateModeButtons];
	[self.tableView setContentOffset:CGPointZero animated:NO];
	[self reload];
}

#pragma mark - loading

- (void)loadGroupInfo {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] groupInfoForChat:self.chatId completion:^(NSDictionary *info){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		if ([info isKindOfClass:NSDictionary.class]){
			me.groupInfo = info;
			[me updateTitle];
			[me updateManageButton];
		}
	}];

	[[TGClient shared] myAdministratorRightsInGroup:self.chatId
										 completion:^(NSDictionary *rights, NSString *status){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		if ([rights isKindOfClass:NSDictionary.class])
			me.myRights = rights;
		if ([status isKindOfClass:NSString.class])
			me.myStatus = status;
		[me updateManageButton];
	}];
}

#pragma mark - manage menu

- (BOOL)isSupergroup {
	return [[self.groupInfo objectForKey:@"isSupergroup"] boolValue];
}

- (NSInteger)pendingJoinRequestCount {
	return TGMembersInteger(self.groupInfo, @"pendingJoinRequests");
}

- (NSArray *)availableManageActions {
	if (![self.groupInfo isKindOfClass:NSDictionary.class])
		return [NSArray array];

	NSMutableArray *actions = [NSMutableArray array];
	if ([self iMay:@"can_invite_users"]){
		[actions addObject:@"addMembers"];
		if ([self pendingJoinRequestCount] > 0){
			[actions addObject:@"approveAllRequests"];
			[actions addObject:@"dismissAllRequests"];
		}
	}
	if ([self isSupergroup] && [self iMay:@"can_restrict_members"])
		[actions addObject:@"defaultPermissions"];
	if ([self isSupergroup] && [self iMay:@"can_change_info"])
		[actions addObject:@"publicLink"];
	if (![self isSupergroup] && [self.myStatus isEqualToString:@"creator"])
		[actions addObject:@"upgrade"];
	return actions;
}

- (NSString *)titleForManageAction:(NSString *)action {
	if ([action isEqualToString:@"addMembers"])
		return @"Add Members";
	if ([action isEqualToString:@"approveAllRequests"])
		return [NSString stringWithFormat:@"Approve All Requests (%d)",
				(int)[self pendingJoinRequestCount]];
	if ([action isEqualToString:@"dismissAllRequests"])
		return @"Dismiss All Requests";
	if ([action isEqualToString:@"defaultPermissions"])
		return @"Default Permissions";
	if ([action isEqualToString:@"publicLink"]){
		NSString *current = TGMembersString(self.groupInfo, @"username");
		return current.length
				? [NSString stringWithFormat:@"Public Link (t.me/%@)", current]
				: @"Public Link";
	}
	return @"Upgrade to Supergroup";
}

- (void)updateManageButton {
	_manageActions = [self availableManageActions];
	if (_manageActions.count == 0){
		self.navigationItem.rightBarButtonItem = nil;
		return;
	}
	if (self.navigationItem.rightBarButtonItem)
		return;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Manage" style:UIBarButtonItemStylePlain
				   target:self action:@selector(showManageMenu)];
}

- (void)showManageMenu {
	NSArray *actions = [self availableManageActions];
	if (actions.count == 0)
		return;
	_manageActions = actions;

	[self.searchBar resignFirstResponder];
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	sheet.tag = 2;
	for (NSString *action in actions)
		[sheet addButtonWithTitle:[self titleForManageAction:action]];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.navigationController.view ?: self.view];
}

- (void)performManageAction:(NSString *)action {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"addMembers"]){
		TGGroupAddMembersViewController *picker =
				[[TGGroupAddMembersViewController alloc] initWithChatId:self.chatId];
		picker.onAdded = ^{
			TGGroupMembersViewController *me = weakSelf;
			if (!me)
				return;
			[me loadGroupInfo];
			[me reload];
		};
		[self.navigationController pushViewController:picker animated:YES];
		return;
	}
	if ([action isEqualToString:@"defaultPermissions"]){
		TGMemberRightsViewController *editor = [[TGMemberRightsViewController alloc]
				initWithDefaultPermissionsOfChat:self.chatId];
		[self.navigationController pushViewController:editor animated:YES];
		return;
	}
	if ([action isEqualToString:@"publicLink"]){
		TGGroupPublicLinkViewController *editor = [[TGGroupPublicLinkViewController alloc]
				initWithChatId:self.chatId
					  username:TGMembersString(self.groupInfo, @"username")
					 isChannel:[[self.groupInfo objectForKey:@"isChannel"] boolValue]];
		editor.onChanged = ^{
			TGGroupMembersViewController *me = weakSelf;
			if (!me)
				return;
			[me loadGroupInfo];
		};
		[self.navigationController pushViewController:editor animated:YES];
		return;
	}
	if ([action isEqualToString:@"upgrade"]){
		[self confirm:@"Upgrade this group to a supergroup? Members can then be "
				@"restricted and banned. This cannot be undone."
				   ok:@"Upgrade" destructive:YES run:^{
			TGGroupMembersViewController *me = weakSelf;
			if (!me)
				return;
			[me upgradeToSupergroupThen:nil];
		}];
		return;
	}
	[self confirmAllJoinRequests:[action isEqualToString:@"approveAllRequests"]];
}

- (void)confirmAllJoinRequests:(BOOL)approve {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] joinRequestsInGroup:self.chatId
									 limit:kMemberPageSize
								completion:^(NSArray *requests, NSInteger totalCount){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		NSArray *list = [requests isKindOfClass:NSArray.class] ? requests : [NSArray array];
		if (list.count == 0 && totalCount == 0){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Nobody is waiting to join this group."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			[me loadGroupInfo];
			return;
		}

		NSMutableArray *names = [NSMutableArray array];
		for (NSDictionary *request in list){
			if (![request isKindOfClass:NSDictionary.class])
				continue;
			NSString *name = TGMembersString(request, @"name");
			if (name.length && names.count < 3)
				[names addObject:name];
		}
		NSInteger count = totalCount > 0 ? totalCount : (NSInteger)list.count;
		NSString *who = names.count
				? [names componentsJoinedByString:@", "] : @"everyone waiting";
		if (count > (NSInteger)names.count && names.count)
			who = [NSString stringWithFormat:@"%@ and %d more", who,
					(int)(count - (NSInteger)names.count)];
		NSString *message = approve
				? [NSString stringWithFormat:@"Let %@ into this group?", who]
				: [NSString stringWithFormat:@"Turn down %@?", who];

		[me confirm:message ok:(approve ? @"Approve" : @"Dismiss")
		destructive:!approve run:^{
			TGGroupMembersViewController *inner = weakSelf;
			if (!inner)
				return;
			[inner runAllJoinRequests:approve];
		}];
	}];
}

- (void)runAllJoinRequests:(BOOL)approve {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] processAllJoinRequestsInGroup:self.chatId
											 approve:approve
										  completion:^(BOOL ok){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not answer these join requests."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		[me loadGroupInfo];
		if (approve)
			[me reload];
	}];
}

- (void)upgradeToSupergroupThen:(void (^)(void))then {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] upgradeBasicGroupToSupergroup:self.chatId
										  completion:^(int64_t newChatId){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		if (newChatId == 0){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not upgrade this group."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		me.chatId = newChatId;
		me.groupInfo = nil;
		[[TGClient shared] groupInfoForChat:newChatId completion:^(NSDictionary *info){
			TGGroupMembersViewController *inner = weakSelf;
			if (!inner)
				return;
			if ([info isKindOfClass:NSDictionary.class]){
				inner.groupInfo = info;
				[inner updateTitle];
			}
			[[TGClient shared] myAdministratorRightsInGroup:newChatId
												 completion:^(NSDictionary *rights,
															  NSString *status){
				TGGroupMembersViewController *last = weakSelf;
				if (!last)
					return;
				if ([rights isKindOfClass:NSDictionary.class])
					last.myRights = rights;
				if ([status isKindOfClass:NSString.class])
					last.myStatus = status;
				[last updateManageButton];
				[last reload];
				if (then)
					then();
			}];
		}];
	}];
}

- (BOOL)iMay:(NSString *)right {
	if ([self.myStatus isEqualToString:@"creator"])
		return YES;
	if (![self.myRights isKindOfClass:NSDictionary.class])
		return YES;
	return [[self.myRights objectForKey:right] boolValue];
}

- (void)updateTitle {
	NSInteger count = TGMembersInteger(self.groupInfo, @"memberCount");
	NSArray *titles = [self modeTitles];
	if (self.mode < 0 || self.mode >= (NSInteger)titles.count)
		self.mode = 0;
	if (self.mode == 0 && count > 0)
		self.title = count == 1 ? @"1 member"
				: [NSString stringWithFormat:@"%d members", (int)count];
	else
		self.title = [titles objectAtIndex:(NSUInteger)self.mode];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	NSMutableSet *live = [NSMutableSet set];
	for (NSDictionary *member in [self rows]){
		if (![member isKindOfClass:NSDictionary.class])
			continue;
		int64_t userId = TGMembersUserId(member);
		if (userId != 0)
			[live addObject:[NSNumber numberWithLongLong:userId]];
	}
	for (NSNumber *key in [self.photos allKeys]){
		if (![live containsObject:key]){
			[self.photos removeObjectForKey:key];
			[self.photosRequested removeObject:key];
		}
	}
}

- (void)reload {
	self.generation++;
	NSInteger generation = self.generation;
	self.loaded = NO;
	self.failed = NO;
	self.loading = YES;
	self.loadingMore = NO;
	self.totalCount = 0;
	self.members = [NSArray array];
	self.searchResults = nil;
	[self.tableView reloadData];
	[self updateStatusView];
	[self updateTitle];

	if ([self hasSearchQuery]){
		[self runSearch];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] membersInGroup:self.chatId
							   filter:[self listFilterForMode:self.mode]
							   offset:0
								limit:kMemberPageSize
						   completion:^(NSArray *members, NSInteger totalCount){
		TGGroupMembersViewController *me = weakSelf;
		if (!me || me.generation != generation)
			return;
		me.loading = NO;
		me.loaded = YES;
		if (![members isKindOfClass:NSArray.class]){
			me.failed = YES;
			[me updateStatusView];
			return;
		}
		me.members = members;
		me.totalCount = totalCount;
		[me.tableView reloadData];
		[me updateStatusView];
		[me fetchPhotosForRows];
	}];
}

- (void)loadMore {
	if (self.loadingMore || self.loading || [self hasSearchQuery])
		return;
	if (self.totalCount <= (NSInteger)self.members.count)
		return;

	self.loadingMore = YES;
	NSInteger generation = self.generation;
	NSInteger offset = (NSInteger)self.members.count;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] membersInGroup:self.chatId
							   filter:[self listFilterForMode:self.mode]
							   offset:offset
								limit:kMemberPageSize
						   completion:^(NSArray *members, NSInteger totalCount){
		TGGroupMembersViewController *me = weakSelf;
		if (!me || me.generation != generation)
			return;
		me.loadingMore = NO;
		if (![members isKindOfClass:NSArray.class] || members.count == 0){
			me.totalCount = (NSInteger)me.members.count;
			[me.tableView reloadData];
			return;
		}
		NSMutableArray *combined = [me.members mutableCopy];
		[combined addObjectsFromArray:members];
		me.members = combined;
		me.totalCount = totalCount;
		[me.tableView reloadData];
		[me fetchPhotosForRows];
	}];
}

- (void)restoreListAfterSearch {
	self.searchResults = nil;
	if (self.loading){
		[self.tableView reloadData];
		[self updateStatusView];
		return;
	}
	if (self.members.count == 0){
		[self reload];
		return;
	}
	[self.tableView reloadData];
	[self updateStatusView];
}

- (void)runSearch {
	NSString *text = [self.query stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length){
		[self restoreListAfterSearch];
		return;
	}

	NSInteger generation = self.generation;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchMembersInGroup:self.chatId
									  query:text
									 filter:[self searchFilterForMode:self.mode]
									  limit:kMemberPageSize
								 completion:^(NSArray *members){
		TGGroupMembersViewController *me = weakSelf;
		if (!me || me.generation != generation)
			return;
		me.loading = NO;
		me.loaded = YES;
		me.searchResults = [members isKindOfClass:NSArray.class] ? members : [NSArray array];
		[me.tableView reloadData];
		[me updateStatusView];
		[me fetchPhotosForRows];
	}];
}

- (void)layoutEmptyPlaceholderWithTitle:(NSString *)title help:(NSString *)help {
	CGFloat width = self.emptyPlaceholder.bounds.size.width;
	self.emptyTitleLabel.text = title;
	CGSize titleSize = [title sizeWithFont:self.emptyTitleLabel.font];
	self.emptyTitleLabel.frame = CGRectMake(0, 0, width, titleSize.height);

	self.emptyHelpLabel.text = help;
	CGSize helpSize = [help sizeWithFont:self.emptyHelpLabel.font
					   constrainedToSize:CGSizeMake(260, 1000)
						   lineBreakMode:NSLineBreakByWordWrapping];
	self.emptyHelpLabel.frame = CGRectMake((CGFloat)(int)((width - 260) / 2), 26,
			260, helpSize.height);

	CGFloat totalHeight = 26 + helpSize.height;
	UIView *host = self.emptyPlaceholder.superview;
	CGFloat hostHeight = host ? host.bounds.size.height : totalHeight;
	CGRect frame = self.emptyPlaceholder.frame;
	frame.size.height = totalHeight;
	frame.origin.y = (CGFloat)(int)((hostHeight - totalHeight) / 2) - 40;
	if (frame.origin.y < 0)
		frame.origin.y = 0;
	self.emptyPlaceholder.frame = frame;
}

- (void)updateStatusView {
	if (self.loading){
		[self.spinner startAnimating];
		self.statusLabel.text = @"Loading...";
		self.statusLabel.hidden = NO;
		self.emptyPlaceholder.hidden = YES;
		self.retryButton.hidden = YES;
		return;
	}
	[self.spinner stopAnimating];

	if (self.failed){
		self.statusLabel.text = @"Could not load the member list.";
		self.statusLabel.hidden = NO;
		self.emptyPlaceholder.hidden = YES;
		self.retryButton.hidden = NO;
		return;
	}
	self.retryButton.hidden = YES;
	self.statusLabel.hidden = YES;

	NSArray *rows = [self rows];
	if (rows.count == 0 && self.loaded){
		if ([self hasSearchQuery])
			[self layoutEmptyPlaceholderWithTitle:@"No results"
											 help:@"Nobody here matches that name."];
		else
			[self layoutEmptyPlaceholderWithTitle:[self emptyTextForMode:self.mode]
											 help:[self emptyHelpForMode:self.mode]];
		self.emptyPlaceholder.hidden = NO;
		return;
	}
	self.emptyPlaceholder.hidden = YES;
}

#pragma mark - photos

- (NSArray *)rows {
	if (self.searchResults)
		return self.searchResults;
	return self.members ?: [NSArray array];
}

- (NSDictionary *)memberAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *rows = [self rows];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count)
		return nil;
	NSDictionary *member = [rows objectAtIndex:(NSUInteger)indexPath.row];
	return [member isKindOfClass:NSDictionary.class] ? member : nil;
}

- (void)fetchPhotosForRows {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *member in [self rows]){
		if (![member isKindOfClass:NSDictionary.class])
			continue;
		int64_t userId = TGMembersUserId(member);
		if (userId == 0)
			continue;
		NSNumber *key = [NSNumber numberWithLongLong:userId];
		if ([self.photos objectForKey:key] || [self.photosRequested containsObject:key])
			continue;
		NSNumber *fileId = [[TGClient shared] photoFileIdForUserId:userId];
		if (![fileId isKindOfClass:NSNumber.class])
			continue;
		[self.photosRequested addObject:key];

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			if (!path.length){
				TGGroupMembersViewController *me = weakSelf;
				if (!me)
					return;
				[me.photosRequested removeObject:key];
				return;
			}
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				UIImage *thumb = TGDecodeSquareThumbnail(path, kMemberAvatar);
				dispatch_async(dispatch_get_main_queue(), ^{
					TGGroupMembersViewController *me = weakSelf;
					if (!me || !thumb)
						return;
					[me.photos setObject:thumb forKey:key];
					[me reloadTableSoon];
				});
			});
		}];
	}
}

- (void)reloadTableSoon {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(reloadTableNow)
											   object:nil];
	[self performSelector:@selector(reloadTableNow) withObject:nil afterDelay:0.15f];
}

- (void)reloadTableNow {
	[self.tableView reloadData];
}

#pragma mark - row text

- (NSString *)statusTextForMember:(NSDictionary *)member {
	NSString *status = TGMembersString(member, @"status");
	NSString *customTitle = TGMembersString(member, @"customTitle");
	if (customTitle.length)
		return customTitle;

	if ([status isEqualToString:@"creator"])
		return @"owner";
	if ([status isEqualToString:@"administrator"])
		return @"admin";
	if ([status isEqualToString:@"banned"]){
		NSInteger until = TGMembersInteger(member, @"untilDate");
		if (until > 0)
			return [NSString stringWithFormat:@"banned until %@",
					[NSDateFormatter localizedStringFromDate:
							[NSDate dateWithTimeIntervalSince1970:until]
											   dateStyle:NSDateFormatterShortStyle
											   timeStyle:NSDateFormatterNoStyle]];
		return @"removed";
	}
	if ([status isEqualToString:@"restricted"]){
		NSInteger until = TGMembersInteger(member, @"untilDate");
		if (until > 0)
			return [NSString stringWithFormat:@"restricted until %@",
					[NSDateFormatter localizedStringFromDate:
							[NSDate dateWithTimeIntervalSince1970:until]
											   dateStyle:NSDateFormatterShortStyle
											   timeStyle:NSDateFormatterNoStyle]];
		return @"restricted";
	}
	if ([status isEqualToString:@"left"])
		return @"left the group";
	return @"member";
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[self rows].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return kMemberRowHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return [self rows].count == 0 ? 0.0f : kSectionHeaderHeight;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if ([self rows].count == 0)
		return nil;

	CGFloat width = tableView.bounds.size.width;
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, kSectionHeaderHeight)];
	container.clipsToBounds = NO;
	container.backgroundColor = [UIColor clearColor];

	UIImage *plate = [UIImage imageNamed:@"CategoryDividerFirst.png"];
	BOOL plated = plate != nil && ![[TGTheme shared] isFlat];
	if (plated){
		UIImageView *plateView = [[UIImageView alloc] initWithImage:plate];
		plateView.frame = CGRectMake(0, -1, width, kSectionHeaderHeight + 1);
		plateView.autoresizingMask =
				UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[container addSubview:plateView];
	} else {
		container.backgroundColor = [[TGTheme shared] inputBarColour];
	}

	UILabel *caption = [[UILabel alloc] initWithFrame:CGRectZero];
	caption.backgroundColor = [UIColor clearColor];
	caption.font = [UIFont boldSystemFontOfSize:15];
	caption.textColor = plated ? [UIColor whiteColor] : [[TGTheme shared] secondaryTextColour];
	if (plated){
		caption.shadowColor = [UIColor colorWithRed:0x88 / 255.0f green:0x92 / 255.0f
											   blue:0x9c / 255.0f alpha:1.0f];
		caption.shadowOffset = CGSizeMake(0, -1);
	}
	caption.text = [self sectionCaptionForMode:self.mode];
	[caption sizeToFit];
	caption.frame = CGRectOffset(caption.frame, 10, 1);
	[container addSubview:caption];

	return container;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGGroupMemberCell";
	TGGroupMemberCell *cell = (TGGroupMemberCell *)
			[tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGGroupMemberCell alloc] initWithStyle:UITableViewCellStyleDefault
										reuseIdentifier:reuse];

	NSDictionary *member = [self memberAtIndexPath:indexPath];
	if (!member){
		[cell setName:@""];
		cell.subtitleLabel.text = @"";
		cell.avatarView.image = nil;
		return cell;
	}

	NSString *name = TGMembersString(member, @"name");
	if (!name.length)
		name = @"Unknown";
	[cell setName:name];
	cell.subtitleLabel.text = [self statusTextForMember:member];

	int64_t userId = TGMembersUserId(member);
	NSNumber *key = [NSNumber numberWithLongLong:userId];
	UIImage *photo = [self.photos objectForKey:key];
	if (!photo)
		photo = [TGIcons avatarWithInitials:[name substringToIndex:1].uppercaseString
									   size:kMemberAvatar
								   colourId:userId];
	cell.avatarView.image = photo;
	[cell setNeedsLayout];

	if (indexPath.row + 5 >= (NSInteger)[self rows].count)
		[self loadMore];

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *member = [self memberAtIndexPath:indexPath];
	if (!member)
		return;
	int64_t userId = TGMembersUserId(member);
	if (userId == 0)
		return;
	NSString *name = TGMembersString(member, @"name");

	[self.searchBar resignFirstResponder];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		TGProfileViewController *vc = [[TGProfileViewController alloc]
				initWithChatId:chatId userId:userId title:name];
		[me.navigationController pushViewController:vc animated:YES];
	}];
}

#pragma mark - long press menu

- (void)handleLongPress:(UILongPressGestureRecognizer *)recogniser {
	if (recogniser.state != UIGestureRecognizerStateBegan)
		return;

	CGPoint point = [recogniser locationInView:self.tableView];
	NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
	if (!indexPath)
		return;
	NSDictionary *member = [self memberAtIndexPath:indexPath];
	if (!member)
		return;

	NSArray *actions = [self actionsForMember:member];
	if (actions.count == 0)
		return;

	[self.searchBar resignFirstResponder];

	NSMutableArray *items = [NSMutableArray array];
	for (NSString *action in actions)
		[items addObject:[self menuItemForAction:action]];

	UIView *host = self.navigationController.view ?: self.view;
	CGPoint hostPoint = [self.tableView convertPoint:point toView:host];
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:hostPoint inView:host
				  onChoice:^(NSInteger index, NSString *title){
		TGGroupMembersViewController *me = weakSelf;
		if (!me || index < 0 || index >= (NSInteger)actions.count)
			return;
		[me performAction:[actions objectAtIndex:(NSUInteger)index] onMember:member];
	}];
}

- (NSDictionary *)menuItemForAction:(NSString *)action {
	if ([action isEqualToString:@"promote"])
		return [NSDictionary dictionaryWithObjectsAndKeys:
				@"Promote to Admin", @"title", @"edit", @"icon", nil];
	if ([action isEqualToString:@"editRights"])
		return [NSDictionary dictionaryWithObjectsAndKeys:
				@"Edit Admin Rights", @"title", @"edit", @"icon", nil];
	if ([action isEqualToString:@"editRestrictions"])
		return [NSDictionary dictionaryWithObjectsAndKeys:
				@"Edit Restrictions", @"title", @"edit", @"icon", nil];
	if ([action isEqualToString:@"dismiss"])
		return [NSDictionary dictionaryWithObjectsAndKeys:
				@"Dismiss Admin", @"title", @"edit", @"icon", nil];
	if ([action isEqualToString:@"transferOwnership"])
		return [NSDictionary dictionaryWithObjectsAndKeys:
				@"Transfer Ownership", @"title", @"edit", @"icon",
				[NSNumber numberWithBool:YES], @"destructive", nil];
	if ([action isEqualToString:@"restrict"])
		return [NSDictionary dictionaryWithObjectsAndKeys:
				@"Restrict", @"title", @"mute", @"icon", nil];
	if ([action isEqualToString:@"unrestrict"])
		return [NSDictionary dictionaryWithObjectsAndKeys:
				@"Lift Restrictions", @"title", @"unmute", @"icon", nil];
	if ([action isEqualToString:@"unban"])
		return [NSDictionary dictionaryWithObjectsAndKeys:
				@"Unban", @"title", @"unmute", @"icon", nil];
	if ([action isEqualToString:@"ban"])
		return [NSDictionary dictionaryWithObjectsAndKeys:
				@"Ban", @"title", @"delete", @"icon",
				[NSNumber numberWithBool:YES], @"destructive", nil];
	if ([action isEqualToString:@"deleteMessages"])
		return [NSDictionary dictionaryWithObjectsAndKeys:
				@"Delete All Messages", @"title", @"delete", @"icon",
				[NSNumber numberWithBool:YES], @"destructive", nil];
	return [NSDictionary dictionaryWithObjectsAndKeys:
			@"Remove from Group", @"title", @"delete", @"icon",
			[NSNumber numberWithBool:YES], @"destructive", nil];
}

- (NSArray *)actionsForMember:(NSDictionary *)member {
	NSString *status = TGMembersString(member, @"status");
	BOOL canEdit = [[member objectForKey:@"canBeEdited"] boolValue];
	BOOL isOwner = [[member objectForKey:@"isOwner"] boolValue];
	int64_t userId = TGMembersUserId(member);

	if (isOwner || [status isEqualToString:@"creator"])
		return [NSArray array];
	if (userId == 0)
		return [NSArray array];

	NSMutableArray *actions = [NSMutableArray array];
	BOOL mayRestrict = [self iMay:@"can_restrict_members"];
	BOOL mayPromote = [self iMay:@"can_promote_members"];
	BOOL mayDelete = [self iMay:@"can_delete_messages"];

	if ([status isEqualToString:@"banned"]){
		if (mayRestrict)
			[actions addObject:@"unban"];
		if (mayDelete)
			[actions addObject:@"deleteMessages"];
		return actions;
	}

	if ([status isEqualToString:@"restricted"]){
		if (mayRestrict){
			[actions addObject:@"editRestrictions"];
			[actions addObject:@"unrestrict"];
			[actions addObject:@"ban"];
		}
		return actions;
	}

	if ([status isEqualToString:@"administrator"]){
		if (canEdit && mayPromote){
			[actions addObject:@"editRights"];
			[actions addObject:@"dismiss"];
		}
		if ([self.myStatus isEqualToString:@"creator"])
			[actions addObject:@"transferOwnership"];
		if (mayRestrict)
			[actions addObject:@"remove"];
		return actions;
	}

	if (mayPromote)
		[actions addObject:@"promote"];
	if (mayRestrict){
		[actions addObject:@"restrict"];
		[actions addObject:@"ban"];
		[actions addObject:@"remove"];
	}
	return actions;
}

- (BOOL)actionNeedsSupergroup:(NSString *)action {
	if (![self.groupInfo isKindOfClass:NSDictionary.class] || [self isSupergroup])
		return NO;
	if (![self.myStatus isEqualToString:@"creator"])
		return NO;
	return [action isEqualToString:@"restrict"]
			|| [action isEqualToString:@"editRestrictions"]
			|| [action isEqualToString:@"ban"]
			|| [action isEqualToString:@"unban"]
			|| [action isEqualToString:@"unrestrict"];
}

- (void)openRightsEditorForUser:(int64_t)userId name:(NSString *)name
					restricting:(BOOL)restricting {
	TGMemberRightsViewController *editor = [[TGMemberRightsViewController alloc]
			initWithChatId:self.chatId userId:userId name:name restricting:restricting];
	__weak typeof(self) weakSelf = self;
	editor.onSaved = ^{
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		[me refreshRowForUser:userId];
		[me loadGroupInfo];
	};
	if (!restricting && [self.myStatus isEqualToString:@"creator"]){
		editor.canTransferOwnership = YES;
		editor.onTransferOwnership = ^{
			TGGroupMembersViewController *me = weakSelf;
			if (!me)
				return;
			[me.navigationController popToViewController:me animated:YES];
			[me beginTransferOwnershipToUser:userId name:name];
		};
	}
	[self.navigationController pushViewController:editor animated:YES];
}

- (void)performAction:(NSString *)action onMember:(NSDictionary *)member {
	int64_t userId = TGMembersUserId(member);
	int64_t chatId = self.chatId;
	NSString *name = TGMembersString(member, @"name");
	if (!name.length)
		name = @"this user";
	__weak typeof(self) weakSelf = self;

	if ([self actionNeedsSupergroup:action]){
		[self confirm:@"Restricting and banning people needs a supergroup. Upgrade "
				@"this group now? This cannot be undone."
				   ok:@"Upgrade" destructive:YES run:^{
			TGGroupMembersViewController *me = weakSelf;
			if (!me)
				return;
			[me upgradeToSupergroupThen:^{
				TGGroupMembersViewController *inner = weakSelf;
				if (!inner)
					return;
				[inner performAction:action onMember:member];
			}];
		}];
		return;
	}

	if ([action isEqualToString:@"promote"] || [action isEqualToString:@"editRights"]){
		[self openRightsEditorForUser:userId name:name restricting:NO];
		return;
	}
	if ([action isEqualToString:@"editRestrictions"]){
		[self openRightsEditorForUser:userId name:name restricting:YES];
		return;
	}
	if ([action isEqualToString:@"dismiss"]){
		[self confirm:[NSString stringWithFormat:@"Dismiss %@ as administrator?", name]
				   ok:@"Dismiss" destructive:NO run:^{
			TGGroupMembersViewController *me = weakSelf;
			if (!me)
				return;
			[me runDismiss:userId];
		}];
		return;
	}
	if ([action isEqualToString:@"restrict"]){
		[self openRightsEditorForUser:userId name:name restricting:YES];
		return;
	}
	if ([action isEqualToString:@"unrestrict"]){
		[self runUnrestrict:userId];
		return;
	}
	if ([action isEqualToString:@"unban"]){
		[self runUnban:userId];
		return;
	}
	if ([action isEqualToString:@"transferOwnership"]){
		[self beginTransferOwnershipToUser:userId name:name];
		return;
	}
	if ([action isEqualToString:@"ban"]){
		_pendingUserId = userId;
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:
				[NSString stringWithFormat:@"Ban %@ from this group?", name]
														   delegate:self
												  cancelButtonTitle:@"Cancel"
											 destructiveButtonTitle:nil
												  otherButtonTitles:@"Ban for 1 Day",
								@"Ban for 1 Week", @"Ban for 1 Month", @"Ban Forever", nil];
		[sheet showInView:self.navigationController.view ?: self.view];
		return;
	}
	if ([action isEqualToString:@"deleteMessages"]){
		[self confirm:[NSString stringWithFormat:@"Delete every message %@ has sent here?", name]
				   ok:@"Delete" destructive:YES run:^{
			[[TGClient shared] deleteAllMessagesFromUser:userId inGroup:chatId];
		}];
		return;
	}

	[self confirm:[NSString stringWithFormat:@"Remove %@ from this group?", name]
			   ok:@"Remove" destructive:YES run:^{
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		[me runRemove:userId];
	}];
}

- (void)confirm:(NSString *)message ok:(NSString *)ok destructive:(BOOL)destructive
			run:(void (^)(void))run {
	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:nil
													message:message
										  cancelButtonTitle:@"Cancel"
											  okButtonTitle:ok
											completionBlock:^(bool okPressed){
		if (okPressed && run)
			run();
	}];
	[alert show];
}

- (void)finishWithSuccess:(BOOL)ok failureText:(NSString *)failureText
				   userId:(int64_t)userId {
	if (!ok){
		[[[UIAlertView alloc] initWithTitle:nil
									message:failureText
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
		return;
	}
	[self loadGroupInfo];
	[self refreshRowForUser:userId];
}

- (NSInteger)rowIndexForUser:(int64_t)userId {
	NSArray *rows = [self rows];
	for (NSUInteger i = 0; i < rows.count; i++){
		NSDictionary *member = [rows objectAtIndex:i];
		if (![member isKindOfClass:NSDictionary.class])
			continue;
		if (TGMembersUserId(member) == userId)
			return (NSInteger)i;
	}
	return -1;
}

- (BOOL)status:(NSString *)status belongsToMode:(NSInteger)mode {
	switch (mode){
		case 1: return [status isEqualToString:@"administrator"]
				|| [status isEqualToString:@"creator"];
		case 2: return [status isEqualToString:@"banned"];
		case 3: return [status isEqualToString:@"restricted"];
		default: return ![status isEqualToString:@"banned"]
				&& ![status isEqualToString:@"left"];
	}
}

- (void)replaceRowAtIndex:(NSInteger)index withMember:(NSDictionary *)member {
	NSMutableArray *rows = [[self rows] mutableCopy];
	if (index < 0 || index >= (NSInteger)rows.count)
		return;
	if (member)
		[rows replaceObjectAtIndex:(NSUInteger)index withObject:member];
	else
		[rows removeObjectAtIndex:(NSUInteger)index];

	if (self.searchResults)
		self.searchResults = rows;
	else {
		self.members = rows;
		if (!member && self.totalCount > 0)
			self.totalCount--;
	}

	NSArray *paths = [NSArray arrayWithObject:
			[NSIndexPath indexPathForRow:index inSection:0]];
	if (!member && rows.count == 0){
		[self.tableView reloadData];
		[self updateStatusView];
		[self updateTitle];
		return;
	}
	if (member)
		[self.tableView reloadRowsAtIndexPaths:paths
							  withRowAnimation:UITableViewRowAnimationNone];
	else
		[self.tableView deleteRowsAtIndexPaths:paths
							  withRowAnimation:UITableViewRowAnimationFade];
	[self updateStatusView];
	[self updateTitle];
}

- (void)refreshRowForUser:(int64_t)userId {
	NSInteger generation = self.generation;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] memberStatusOfUser:userId
								  inGroup:self.chatId
							   completion:^(NSDictionary *member){
		TGGroupMembersViewController *me = weakSelf;
		if (!me || me.generation != generation)
			return;
		NSInteger index = [me rowIndexForUser:userId];
		if (index < 0)
			return;
		if (![member isKindOfClass:NSDictionary.class]){
			[me replaceRowAtIndex:index withMember:nil];
			return;
		}
		NSString *status = TGMembersString(member, @"status");
		if (![me status:status belongsToMode:me.mode]){
			[me replaceRowAtIndex:index withMember:nil];
			return;
		}
		[me replaceRowAtIndex:index withMember:member];
		[me fetchPhotosForRows];
	}];
}

- (void)runDismiss:(int64_t)userId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] dismissAdmin:userId inGroup:self.chatId completion:^(BOOL ok){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		[me finishWithSuccess:ok
				  failureText:@"Could not dismiss this administrator."
					   userId:userId];
	}];
}

- (void)runUnrestrict:(int64_t)userId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] defaultPermissionsInGroup:self.chatId
									  completion:^(NSDictionary *permissions){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		NSDictionary *restore = [permissions isKindOfClass:NSDictionary.class]
				? permissions : [NSDictionary dictionary];
		[[TGClient shared] restrictMember:userId
								  inGroup:me.chatId
							  permissions:restore
								untilDate:0
							   completion:^(BOOL ok){
			TGGroupMembersViewController *inner = weakSelf;
			if (!inner)
				return;
			[inner finishWithSuccess:ok
						 failureText:@"Could not lift the restrictions."
							  userId:userId];
		}];
	}];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (actionSheet.tag == 2){
		if (buttonIndex == actionSheet.cancelButtonIndex)
			return;
		if (buttonIndex < 0 || buttonIndex >= (NSInteger)_manageActions.count)
			return;
		[self performManageAction:[_manageActions objectAtIndex:(NSUInteger)buttonIndex]];
		return;
	}
	if (buttonIndex == actionSheet.cancelButtonIndex || _pendingUserId == 0)
		return;
	NSInteger now = (NSInteger)[[NSDate date] timeIntervalSince1970];
	NSInteger untilDate = 0;
	switch (buttonIndex){
		case 0: untilDate = now + kMemberDurationDay; break;
		case 1: untilDate = now + kMemberDurationWeek; break;
		case 2: untilDate = now + kMemberDurationMonth; break;
		default: untilDate = 0; break;
	}
	[self runBan:_pendingUserId untilDate:untilDate];
	_pendingUserId = 0;
}

- (void)beginTransferOwnershipToUser:(int64_t)userId name:(NSString *)name {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] passwordStateWithCompletion:^(NSDictionary *state){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		BOOL hasPassword = [state isKindOfClass:NSDictionary.class]
				&& [[state objectForKey:@"hasPassword"] boolValue];
		if (!hasPassword){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Turn on Two-Step Verification in Settings, "
					@"Privacy and Security, before you hand this group over."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		[me confirm:[NSString stringWithFormat:
				@"Make %@ the owner of this group? You keep only administrator rights.", name]
				 ok:@"Transfer" destructive:YES run:^{
			TGGroupMembersViewController *inner = weakSelf;
			if (!inner)
				return;
			inner->_pendingUserId = userId;
			UIAlertView *prompt = [[TGAlertView alloc]
					initWithTitle:@"Two-Step Verification"
						  message:@"Enter your password to confirm the transfer."
						 delegate:inner
				cancelButtonTitle:@"Cancel"
				otherButtonTitles:@"Transfer", nil];
			prompt.alertViewStyle = UIAlertViewStyleSecureTextInput;
			[prompt show];
		}];
	}];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex || _pendingUserId == 0)
		return;
	NSString *password = [[alertView textFieldAtIndex:0] text] ?: @"";
	int64_t userId = _pendingUserId;
	_pendingUserId = 0;
	if (!password.length)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] transferOwnershipOfGroup:self.chatId
										 toUser:userId
									   password:password
									 completion:^(BOOL ok){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not transfer this group. Check the "
					@"password and try again."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		me.myStatus = @"administrator";
		[me loadGroupInfo];
		[me reload];
	}];
}

- (void)runBan:(int64_t)userId untilDate:(NSInteger)untilDate {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] banMember:userId
						 inGroup:self.chatId
					   untilDate:untilDate
				  revokeMessages:NO
					  completion:^(BOOL ok){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		[me finishWithSuccess:ok
				  failureText:@"Could not ban this member."
					   userId:userId];
	}];
}

- (void)runUnban:(int64_t)userId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] unbanMember:userId inGroup:self.chatId completion:^(BOOL ok){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		[me finishWithSuccess:ok
				  failureText:@"Could not lift this ban."
					   userId:userId];
	}];
}

- (void)runRemove:(int64_t)userId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] removeMember:userId fromGroup:self.chatId completion:^(BOOL ok){
		TGGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		[me finishWithSuccess:ok
				  failureText:@"Could not remove this member."
					   userId:userId];
	}];
}

#pragma mark - search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
	self.query = text;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runSearch)
											   object:nil];
	if (![self hasSearchQuery]){
		[self restoreListAfterSearch];
		return;
	}
	[self performSelector:@selector(runSearch) withObject:nil afterDelay:0.3f];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	self.query = nil;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runSearch)
											   object:nil];
	[self restoreListAfterSearch];
	[searchBar resignFirstResponder];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	[self.searchBar resignFirstResponder];
	[TGPopupMenu dismiss];
}

@end

// vim:ft=objc

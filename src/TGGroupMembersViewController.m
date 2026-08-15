#import "TGGroupMembersViewController.h"
#import "TGClient.h"
#import "TGClient+Groups.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import "TGPopupMenu.h"
#import "TGAlertView.h"
#import "TGImageDecode.h"
#import "TGProfileViewController.h"
#import "UIView+SafeTint.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kMemberRowHeight    = 49.0f;
static const CGFloat kMemberAvatar       = 40.0f;
static const CGFloat kMemberAvatarLeft   = 5.0f;
static const CGFloat kMemberTextLeft     = 54.0f;
static const CGFloat kModeBarHeight      = 44.0f;
static const CGFloat kGroupButtonHeight  = 30.0f;
static const CGFloat kGroupSeparatorWidth = 2.0f;
static const CGFloat kGroupSideInset     = 8.0f;
static const NSInteger kMemberPageSize   = 50;

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

@interface TGMemberRightsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
	int64_t _chatId;
	int64_t _userId;
	BOOL _restricting;
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
@property (nonatomic, copy) void (^onSaved)(void);

- (id)initWithChatId:(int64_t)chatId userId:(int64_t)userId
				name:(NSString *)name restricting:(BOOL)restricting;

@end

@interface TGGroupMemberCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
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
			CGRectMake(kMemberAvatarLeft, 4, kMemberAvatar, kMemberAvatar)];
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.layer.cornerRadius = 4.0f;
	[self.contentView addSubview:self.avatarView];

	self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.titleLabel.backgroundColor = [UIColor clearColor];
	self.titleLabel.font = [UIFont systemFontOfSize:19];
	self.titleLabel.textColor = flat ? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
	self.titleLabel.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:self.titleLabel];

	self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.subtitleLabel.backgroundColor = [UIColor clearColor];
	self.subtitleLabel.font = [UIFont systemFontOfSize:13.5f];
	self.subtitleLabel.textColor = [UIColor colorWithWhite:0.0f alpha:0.53f];
	self.subtitleLabel.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:self.subtitleLabel];

	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGSize viewSize = self.contentView.frame.size;
	self.avatarView.frame = CGRectMake(kMemberAvatarLeft, 4, kMemberAvatar, kMemberAvatar);

	CGFloat width = viewSize.width - kMemberTextLeft - 5;
	if (width < 10)
		width = 10;
	CGFloat titleHeight = self.titleLabel.font.lineHeight;
	CGFloat subtitleHeight = self.subtitleLabel.font.lineHeight;

	if (self.subtitleLabel.text.length == 0){
		CGFloat titleY = (CGFloat)(int)((viewSize.height - titleHeight) / 2) - 1;
		self.titleLabel.frame = CGRectMake(kMemberTextLeft, titleY, width, titleHeight);
		self.subtitleLabel.frame = CGRectZero;
		return;
	}

	CGFloat titleY = (CGFloat)(int)((viewSize.height - titleHeight - subtitleHeight - 1) / 2);
	self.titleLabel.frame = CGRectMake(kMemberTextLeft, titleY, width, titleHeight);
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

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

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
	self.statusLabel.text = @"Could not read this member.";
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.loaded ? (NSInteger)self.keys.count : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return _restricting ? @"What can this member do?" : @"What can this admin do?";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
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

@interface TGGroupMembersViewController () <UITableViewDataSource, UITableViewDelegate,
		UISearchBarDelegate> {
	UIView *_modeBar;
	NSMutableArray *_groupButtons;
	NSMutableArray *_groupSeparators;
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

#pragma mark - lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Members";
	self.mode = (self.initialMode >= 0 && self.initialMode < 4) ? self.initialMode : 0;
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
	NSInteger count = [[self.groupInfo objectForKey:@"memberCount"] integerValue];
	if (self.mode == 0 && count > 0)
		self.title = [NSString stringWithFormat:@"%d members", (int)count];
	else
		self.title = [[self modeTitles] objectAtIndex:(NSUInteger)self.mode];
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

	if (self.query.length){
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
	if (self.loadingMore || self.loading || self.query.length)
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

- (void)runSearch {
	NSString *text = [self.query stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length){
		self.searchResults = nil;
		[self.tableView reloadData];
		[self updateStatusView];
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

- (void)updateStatusView {
	if (self.loading){
		[self.spinner startAnimating];
		self.statusLabel.text = @"Loading...";
		self.statusLabel.hidden = NO;
		self.retryButton.hidden = YES;
		return;
	}
	[self.spinner stopAnimating];

	if (self.failed){
		self.statusLabel.text = @"Could not load the member list.";
		self.statusLabel.hidden = NO;
		self.retryButton.hidden = NO;
		return;
	}
	self.retryButton.hidden = YES;

	NSArray *rows = [self rows];
	if (rows.count == 0 && self.loaded){
		self.statusLabel.text = self.query.length
				? @"No results" : [self emptyTextForMode:self.mode];
		self.statusLabel.hidden = NO;
		return;
	}
	self.statusLabel.hidden = YES;
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
		int64_t userId = [[member objectForKey:@"id"] longLongValue];
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
		NSInteger until = [[member objectForKey:@"untilDate"] integerValue];
		if (until > 0)
			return [NSString stringWithFormat:@"banned until %@",
					[NSDateFormatter localizedStringFromDate:
							[NSDate dateWithTimeIntervalSince1970:until]
											   dateStyle:NSDateFormatterShortStyle
											   timeStyle:NSDateFormatterNoStyle]];
		return @"removed";
	}
	if ([status isEqualToString:@"restricted"]){
		NSInteger until = [[member objectForKey:@"untilDate"] integerValue];
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
		cell.titleLabel.text = @"";
		cell.subtitleLabel.text = @"";
		cell.avatarView.image = nil;
		return cell;
	}

	NSString *name = TGMembersString(member, @"name");
	if (!name.length)
		name = @"Unknown";
	cell.titleLabel.text = name;
	cell.subtitleLabel.text = [self statusTextForMember:member];

	NSString *status = TGMembersString(member, @"status");
	BOOL emphasised = [status isEqualToString:@"creator"] || [status isEqualToString:@"administrator"];
	cell.subtitleLabel.textColor = emphasised
			? [[TGTheme shared] accentColour]
			: [UIColor colorWithWhite:0.0f alpha:0.53f];

	int64_t userId = [[member objectForKey:@"id"] longLongValue];
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
	int64_t userId = [[member objectForKey:@"id"] longLongValue];
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
	int64_t userId = [[member objectForKey:@"id"] longLongValue];

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

- (void)openRightsEditorForUser:(int64_t)userId name:(NSString *)name
					restricting:(BOOL)restricting {
	TGMemberRightsViewController *editor = [[TGMemberRightsViewController alloc]
			initWithChatId:self.chatId userId:userId name:name restricting:restricting];
	__weak typeof(self) weakSelf = self;
	editor.onSaved = ^{
		TGGroupMembersViewController *me = weakSelf;
		[me refreshRowForUser:userId];
		[me loadGroupInfo];
	};
	[self.navigationController pushViewController:editor animated:YES];
}

- (void)performAction:(NSString *)action onMember:(NSDictionary *)member {
	int64_t userId = [[member objectForKey:@"id"] longLongValue];
	NSString *name = TGMembersString(member, @"name");
	if (!name.length)
		name = @"this user";

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
			[self runDismiss:userId];
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
	if ([action isEqualToString:@"ban"]){
		[self confirm:[NSString stringWithFormat:@"Ban %@ from this group?", name]
				   ok:@"Ban" destructive:YES run:^{
			[self runBan:userId];
		}];
		return;
	}
	if ([action isEqualToString:@"deleteMessages"]){
		[self confirm:[NSString stringWithFormat:@"Delete every message %@ has sent here?", name]
				   ok:@"Delete" destructive:YES run:^{
			[[TGClient shared] deleteAllMessagesFromUser:userId inGroup:self.chatId];
		}];
		return;
	}

	[self confirm:[NSString stringWithFormat:@"Remove %@ from this group?", name]
			   ok:@"Remove" destructive:YES run:^{
		[self runRemove:userId];
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
		if ([[member objectForKey:@"id"] longLongValue] == userId)
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
		[weakSelf finishWithSuccess:ok
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
			[weakSelf finishWithSuccess:ok
							failureText:@"Could not lift the restrictions."
								 userId:userId];
		}];
	}];
}

- (void)runBan:(int64_t)userId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] banMember:userId
						 inGroup:self.chatId
					   untilDate:0
				  revokeMessages:NO
					  completion:^(BOOL ok){
		[weakSelf finishWithSuccess:ok
						failureText:@"Could not ban this member."
							 userId:userId];
	}];
}

- (void)runUnban:(int64_t)userId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] unbanMember:userId inGroup:self.chatId completion:^(BOOL ok){
		[weakSelf finishWithSuccess:ok
						failureText:@"Could not lift this ban."
							 userId:userId];
	}];
}

- (void)runRemove:(int64_t)userId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] removeMember:userId fromGroup:self.chatId completion:^(BOOL ok){
		[weakSelf finishWithSuccess:ok
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
	if (!text.length){
		self.searchResults = nil;
		[self.tableView reloadData];
		[self updateStatusView];
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
	self.searchResults = nil;
	[self.tableView reloadData];
	[self updateStatusView];
	[searchBar resignFirstResponder];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	[self.searchBar resignFirstResponder];
	[TGPopupMenu dismiss];
}

@end

// vim:ft=objc

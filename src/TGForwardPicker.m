#import "TGForwardPicker.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGAlertView.h"
#import "TGImageDecode.h"
#import "UIView+SafeTint.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kChatRowHeight = 73.0f;
static const CGFloat kContactRowHeight = 51.0f;
static const CGFloat kChatAvatar = 56.0f;
static const CGFloat kContactAvatar = 40.0f;
static const CGFloat kToolbarHeight = 44.0f;
static const CGFloat kGroupButtonWidth = 80.0f;
static const CGFloat kGroupSeparatorWidth = 2.0f;
static const CGFloat kGroupButtonHeight = 30.0f;

static UIImage *TGForwardStretchImage(NSString *name, int leftCap) {
	UIImage *raw = [UIImage imageNamed:name];
	return [raw stretchableImageWithLeftCapWidth:leftCap topCapHeight:0];
}

@interface TGForwardPickerCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *preview;
@property (nonatomic, assign) CGFloat avatarSide;
@end

@implementation TGForwardPickerCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	_avatarSide = kChatAvatar;

	_avatar = [[UIImageView alloc] init];
	_avatar.backgroundColor = [UIColor clearColor];
	_avatar.contentMode = UIViewContentModeScaleAspectFill;
	_avatar.clipsToBounds = YES;
	[self.contentView addSubview:_avatar];

	_title = [[UILabel alloc] init];
	_title.backgroundColor = [UIColor clearColor];
	_title.font = [UIFont boldSystemFontOfSize:16];
	_title.textColor = [UIColor colorWithRed:0x11 / 255.0f green:0x11 / 255.0f
										blue:0x11 / 255.0f alpha:1.0f];
	[self.contentView addSubview:_title];

	_preview = [[UILabel alloc] init];
	_preview.backgroundColor = [UIColor clearColor];
	_preview.font = [UIFont systemFontOfSize:14];
	_preview.textColor = [UIColor colorWithRed:0x88 / 255.0f green:0x88 / 255.0f
										  blue:0x88 / 255.0f alpha:1.0f];
	[self.contentView addSubview:_preview];

	UIImage *plate = TGForwardStretchImage(@"DialogListCell.png", 1);
	UIImage *platePressed = TGForwardStretchImage(@"DialogListCellHighlighted.png", 1);
	if (plate)
		self.backgroundView = [[UIImageView alloc] initWithImage:plate];
	if (platePressed)
		self.selectedBackgroundView = [[UIImageView alloc] initWithImage:platePressed];

	self.accessoryType = UITableViewCellAccessoryNone;
	self.selectionStyle = UITableViewCellSelectionStyleBlue;
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGFloat w = self.contentView.bounds.size.width;
	CGFloat h = self.contentView.bounds.size.height;
	CGFloat side = _avatarSide;
	CGFloat top = (CGFloat)(int)((h - side) / 2);
	_avatar.frame = CGRectMake(8, top, side, side);
	_avatar.layer.cornerRadius = side / 2;

	CGFloat left = 8 + side + 9;
	CGFloat right = 16;
	if (_preview.text.length == 0) {
		_title.frame = CGRectMake(left, (CGFloat)(int)((h - 20) / 2), w - left - right, 20);
		_preview.frame = CGRectZero;
	} else {
		_title.frame = CGRectMake(left, 11, w - left - right, 20);
		_preview.frame = CGRectMake(left, 35, w - left - right, 20);
	}
}

@end

@interface TGForwardPicker () <UIAlertViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, strong) NSArray *contacts;
@property (nonatomic, strong) NSArray *visibleRows;
@property (nonatomic, assign) NSInteger mode;
@property (nonatomic, assign) BOOL contactsLoaded;
@property (nonatomic, assign) BOOL picking;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSMutableDictionary *avatars;
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIView *toolbarContainerView;
@property (nonatomic, strong) NSMutableArray *groupButtons;
@property (nonatomic, strong) NSMutableArray *groupSeparators;
@end

@implementation TGForwardPicker

- (void)viewDidLoad {
	[super viewDidLoad];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.title = @"Forward";
	self.chats = [self orderedChats];
	self.contacts = [NSArray array];
	self.visibleRows = self.chats;
	self.mode = 0;
	self.query = @"";
	self.avatars = [[NSMutableDictionary alloc] init];
	self.avatarsRequested = [[NSMutableSet alloc] init];

	self.tableView.rowHeight = kChatRowHeight;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.contentInset = UIEdgeInsetsMake(0, 0, kToolbarHeight, 0);
	self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	UIButton *cancel = [TGIcons headerButtonWithTitle:@"Cancel" bold:NO
												target:self action:@selector(cancel)];
	CGRect cancelFrame = cancel.frame;
	if (cancelFrame.size.width < 59)
		cancelFrame.size.width = 59;
	cancel.frame = cancelFrame;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:cancel];

	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
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
	self.emptyLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 120, background.bounds.size.width, 22)];
	self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.emptyLabel.backgroundColor = [UIColor clearColor];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.emptyLabel.hidden = YES;
	[background addSubview:self.emptyLabel];
	self.tableView.backgroundView = background;

	[self buildToolbar];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] contactsWithCompletion:^(NSArray *users){
		TGForwardPicker *me = weakSelf;
		if (!me)
			return;
		me.contactsLoaded = YES;
		me.contacts = [me sortedContacts:users];
		if (me.mode == 1)
			[me refreshRows];
	}];

	if ([TGClient shared].chats.count == 0)
		[[TGClient shared] loadChats];

	[self refreshRows];
}

- (NSArray *)orderedChats {
	NSArray *source = [TGClient shared].chats;
	if (![source isKindOfClass:NSArray.class])
		return [NSArray array];

	NSMutableArray *result = [NSMutableArray arrayWithCapacity:source.count + 1];
	NSMutableArray *saved = [NSMutableArray array];
	int64_t savedId = [[TGClient shared] savedMessagesChatId];
	for (NSDictionary *chat in source){
		if (![chat isKindOfClass:NSDictionary.class])
			continue;
		if (savedId != 0 && [chat[@"id"] longLongValue] == savedId)
			[saved addObject:chat];
		else
			[result addObject:chat];
	}
	if (saved.count == 0 && savedId != 0)
		[saved addObject:[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithLongLong:savedId], @"id",
				@"Saved Messages", @"title",
				[NSNumber numberWithBool:YES], @"isSaved", nil]];
	[result replaceObjectsInRange:NSMakeRange(0, 0)
			 withObjectsFromArray:saved];
	return result;
}

- (NSArray *)sortedContacts:(NSArray *)users {
	if (![users isKindOfClass:NSArray.class])
		return [NSArray array];

	NSMutableArray *clean = [NSMutableArray arrayWithCapacity:users.count];
	for (NSDictionary *user in users){
		if ([user isKindOfClass:NSDictionary.class] && [user[@"id"] longLongValue] != 0)
			[clean addObject:user];
	}
	[clean sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
		NSString *left = [self titleForContact:a];
		NSString *right = [self titleForContact:b];
		NSComparisonResult order = [left localizedCaseInsensitiveCompare:right];
		if (order != NSOrderedSame)
			return order;
		int64_t leftId = [a[@"id"] longLongValue];
		int64_t rightId = [b[@"id"] longLongValue];
		if (leftId == rightId)
			return NSOrderedSame;
		return (leftId < rightId) ? NSOrderedAscending : NSOrderedDescending;
	}];
	return clean;
}

- (BOOL)row:(NSDictionary *)row matchesQuery:(NSString *)query {
	if (query.length == 0)
		return YES;

	NSMutableArray *fields = [NSMutableArray array];
	[fields addObject:[self titleForRow:row]];
	if (self.mode == 1){
		NSArray *keys = [NSArray arrayWithObjects:@"first_name", @"last_name",
						 @"username", @"phone", nil];
		for (NSString *key in keys){
			id value = row[key];
			if ([value isKindOfClass:NSString.class])
				[fields addObject:value];
		}
	}
	for (id field in fields){
		if (![field isKindOfClass:NSString.class] || [field length] == 0)
			continue;
		if ([field rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound)
			return YES;
	}
	return NO;
}

- (void)refreshRows {
	if (self.mode == 0)
		self.chats = [self orderedChats];

	NSArray *source = (self.mode == 0) ? self.chats : self.contacts;
	NSString *query = [self.query stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (query.length == 0){
		self.visibleRows = source;
	} else {
		NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:source.count];
		for (NSDictionary *row in source){
			if ([self row:row matchesQuery:query])
				[filtered addObject:row];
		}
		self.visibleRows = filtered;
	}

	if (self.visibleRows.count == 0){
		if (query.length > 0)
			self.emptyLabel.text = @"No results";
		else if (self.mode == 1)
			self.emptyLabel.text = self.contactsLoaded ? @"No contacts" : @"Loading...";
		else
			self.emptyLabel.text = @"No chats";
		self.emptyLabel.hidden = NO;
	} else {
		self.emptyLabel.hidden = YES;
	}

	[self.tableView reloadData];
	[self fetchMissingAvatars];
}

- (void)fetchMissingAvatars {
	__weak typeof(self) weakSelf = self;
	CGFloat side = (self.mode == 0) ? kChatAvatar : kContactAvatar;
	for (NSDictionary *row in self.visibleRows){
		NSNumber *fileId = row[@"photoFileId"];
		if (![fileId isKindOfClass:NSNumber.class])
			continue;
		if (self.avatars[fileId] || [self.avatarsRequested containsObject:fileId])
			continue;
		[self.avatarsRequested addObject:fileId];

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			TGForwardPicker *me = weakSelf;
			if (!me)
				return;
			if (!path){
				[me.avatarsRequested removeObject:fileId];
				return;
			}
			UIImage *image = TGDecodeSquareThumbnail(path, side);
			if (!image)
				image = [UIImage imageWithContentsOfFile:path];
			if (!image)
				return;
			me.avatars[fileId] = image;
			[me.tableView reloadData];
		}];
	}
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
	self.query = text ?: @"";
	[self refreshRows];
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
	self.query = @"";
	[searchBar resignFirstResponder];
	[self refreshRows];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	[self.searchBar resignFirstResponder];
}

- (void)buildToolbar {
	CGRect bounds = self.view.bounds;
	_toolbarContainerView = [[UIView alloc] initWithFrame:
			CGRectMake(0, bounds.size.height - kToolbarHeight, bounds.size.width, kToolbarHeight)];
	_toolbarContainerView.autoresizingMask =
			UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

	UIImage *footer = [UIImage imageNamed:@"Footer.png"];
	if (footer)
		_toolbarContainerView.backgroundColor = [UIColor colorWithPatternImage:footer];
	else
		_toolbarContainerView.backgroundColor = [[TGTheme shared] inputBarColour];

	_groupButtons = [[NSMutableArray alloc] init];
	_groupSeparators = [[NSMutableArray alloc] init];

	NSArray *titles = [NSArray arrayWithObjects:@"Chats", @"Contacts", nil];
	CGFloat overallWidth = kGroupButtonWidth * titles.count
			+ kGroupSeparatorWidth * (titles.count - 1);
	CGFloat originX = (CGFloat)(int)((bounds.size.width - overallWidth) / 2);
	CGFloat originY = (CGFloat)(int)((kToolbarHeight - kGroupButtonHeight) / 2);

	UIView *group = [[UIView alloc] initWithFrame:
			CGRectMake(originX, originY, overallWidth, kGroupButtonHeight)];
	group.autoresizingMask =
			UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;

	UIColor *shadowColour = [UIColor colorWithRed:0x0e / 255.0f green:0x28 / 255.0f
											 blue:0x4d / 255.0f alpha:0.4f];

	CGFloat currentX = 0;
	for (NSUInteger i = 0; i < titles.count; i++) {
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.exclusiveTouch = YES;
		button.frame = CGRectMake(currentX, 0, kGroupButtonWidth, kGroupButtonHeight);
		button.tag = (NSInteger)i;
		[button setTitle:[titles objectAtIndex:i] forState:UIControlStateNormal];
		button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
		[button setTitleShadowColor:shadowColour forState:UIControlStateNormal];
		[button setTitleShadowColor:shadowColour forState:UIControlStateHighlighted];
		[button setTitleShadowColor:shadowColour forState:UIControlStateSelected];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		button.adjustsImageWhenDisabled = NO;
		button.adjustsImageWhenHighlighted = NO;
		[button addTarget:self action:@selector(groupButtonPressed:)
			 forControlEvents:UIControlEventTouchDown];
		[group addSubview:button];
		[_groupButtons addObject:button];

		currentX += kGroupButtonWidth;

		if (i + 1 < titles.count) {
			UIImageView *separator = [[UIImageView alloc] initWithImage:
					TGForwardStretchImage(@"ButtonGroupDivider.png", 6)];
			separator.frame = CGRectMake(currentX, 0, kGroupSeparatorWidth, kGroupButtonHeight);
			[group addSubview:separator];
			[_groupSeparators addObject:separator];
			currentX += kGroupSeparatorWidth;
		}
	}

	[_toolbarContainerView addSubview:group];
	[self updateGroupImages];
}

- (void)updateGroupImages {
	NSUInteger count = _groupButtons.count;
	for (NSUInteger i = 0; i < count; i++) {
		UIButton *button = [_groupButtons objectAtIndex:i];
		NSString *normalName = @"ButtonGroupCenter.png";
		NSString *highlightedName = @"ButtonGroupCenter_Highlighted.png";
		int leftCap = 1;
		if (i == 0) {
			normalName = @"ButtonGroupLeft.png";
			highlightedName = @"ButtonGroupLeft_Highlighted.png";
			leftCap = 8;
		} else if (i == count - 1) {
			normalName = @"ButtonGroupRight.png";
			highlightedName = @"ButtonGroupRight_Highlighted.png";
			leftCap = 1;
		}

		UIImage *normal = TGForwardStretchImage(normalName, leftCap);
		UIImage *highlighted = TGForwardStretchImage(highlightedName, leftCap);
		UIImage *shown = ((NSInteger)i == self.mode) ? highlighted : normal;
		[button setBackgroundImage:shown forState:UIControlStateNormal];
		[button setBackgroundImage:shown forState:UIControlStateHighlighted];
	}

	for (NSUInteger i = 0; i < _groupSeparators.count; i++) {
		UIImageView *separator = [_groupSeparators objectAtIndex:i];
		NSString *name = @"ButtonGroupDivider.png";
		if (self.mode == (NSInteger)i)
			name = @"ButtonGroupDivider_LeftHighlighted.png";
		else if (self.mode == (NSInteger)i + 1)
			name = @"ButtonGroupDivider_RightHighlighted.png";
		separator.image = TGForwardStretchImage(name, 6);
	}
}

- (void)groupButtonPressed:(UIButton *)button {
	if (self.mode == button.tag)
		return;
	self.mode = button.tag;
	[self updateGroupImages];
	self.tableView.rowHeight = (self.mode == 0) ? kChatRowHeight : kContactRowHeight;
	[self refreshRows];
	[self.tableView setContentOffset:CGPointZero animated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	UIView *host = self.navigationController.view ?: self.view;
	CGRect frame = _toolbarContainerView.frame;
	frame.origin.y = host.bounds.size.height - kToolbarHeight;
	frame.size.width = host.bounds.size.width;
	_toolbarContainerView.frame = frame;
	[host addSubview:_toolbarContainerView];
	[self refreshRows];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[_toolbarContainerView removeFromSuperview];
}

- (void)cancel {
	[self.searchBar resignFirstResponder];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (NSArray *)rows {
	return self.visibleRows ?: [NSArray array];
}

- (NSDictionary *)rowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *rows = [self rows];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count)
		return nil;
	NSDictionary *row = [rows objectAtIndex:indexPath.row];
	return [row isKindOfClass:NSDictionary.class] ? row : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [self rows].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return (self.mode == 0) ? kChatRowHeight : kContactRowHeight;
}

- (NSString *)titleForRow:(NSDictionary *)row {
	if (self.mode == 0){
		NSString *title = row[@"title"];
		return [title isKindOfClass:NSString.class] && title.length ? title : @"Chat";
	}
	return [self titleForContact:row];
}

- (NSString *)titleForContact:(NSDictionary *)row {
	NSString *first = [row[@"first_name"] isKindOfClass:NSString.class] ? row[@"first_name"] : @"";
	NSString *last = [row[@"last_name"] isKindOfClass:NSString.class] ? row[@"last_name"] : @"";
	if (first.length == 0 && last.length == 0){
		NSString *username = row[@"username"];
		if ([username isKindOfClass:NSString.class] && username.length)
			return [NSString stringWithFormat:@"@%@", username];
		NSString *phone = row[@"phone"];
		if ([phone isKindOfClass:NSString.class] && phone.length)
			return phone;
		return @"Contact";
	}
	if (last.length == 0)
		return first;
	if (first.length == 0)
		return last;
	return [NSString stringWithFormat:@"%@ %@", first, last];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGForwardCell";
	TGForwardPickerCell *cell = (TGForwardPickerCell *)[tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGForwardPickerCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:reuse];

	NSDictionary *row = [self rowAtIndexPath:indexPath];
	NSString *title = row ? [self titleForRow:row] : @"";
	CGFloat side = (self.mode == 0) ? kChatAvatar : kContactAvatar;

	cell.avatarSide = side;
	cell.title.text = title;
	cell.title.textColor = [[TGTheme shared] primaryTextColour];
	cell.preview.textColor = [[TGTheme shared] secondaryTextColour];

	NSString *preview = @"";
	if (self.mode == 0){
		NSString *text = row[@"text"];
		if ([text isKindOfClass:NSString.class])
			preview = text;
	}
	cell.preview.text = preview;

	UIImage *photo = nil;
	NSNumber *fileId = row[@"photoFileId"];
	if ([fileId isKindOfClass:NSNumber.class])
		photo = self.avatars[fileId];
	if (!photo && [row[@"isSaved"] boolValue])
		photo = [TGIcons savedMessagesAvatarOfSide:side];
	if (!photo){
		NSString *initials = title.length ? [title substringToIndex:1] : @"?";
		photo = [TGIcons avatarWithInitials:initials.uppercaseString
									   size:side
								   colourId:[row[@"id"] longLongValue]];
	}
	cell.avatar.image = photo;
	[cell setNeedsLayout];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self.searchBar resignFirstResponder];

	if (self.picking)
		return;

	NSDictionary *row = [self rowAtIndexPath:indexPath];
	if (!row)
		return;

	int64_t rowId = [row[@"id"] longLongValue];
	if (rowId == 0)
		return;

	NSString *title = [self titleForRow:row];
	BOOL quoted = (self.mode == 0) && [row[@"isGroup"] boolValue];
	NSString *message = quoted
			? [NSString stringWithFormat:@"Forward to \"%@\"?", title]
			: [NSString stringWithFormat:@"Forward to %@?", title];

	BOOL isContact = (self.mode == 1);
	__weak typeof(self) weakSelf = self;
	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:nil message:message
										  cancelButtonTitle:@"No" okButtonTitle:@"Yes"
											completionBlock:^(bool okButtonPressed){
		TGForwardPicker *me = weakSelf;
		if (!me || !okButtonPressed)
			return;
		if (isContact)
			[me resolvePrivateChatForUser:rowId];
		else
			[me confirmSendableChat:rowId];
	}];
	[alert show];
}

- (void)resolvePrivateChatForUser:(int64_t)userId {
	self.picking = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		weakSelf.picking = NO;
	});
	[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
		TGForwardPicker *me = weakSelf;
		if (!me)
			return;
		me.picking = NO;
		if (chatId == 0){
			[me showFailure:@"Could not open a chat with this contact."];
			return;
		}
		[me finishWithChat:chatId];
	}];
}

- (void)confirmSendableChat:(int64_t)chatId {
	self.picking = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		weakSelf.picking = NO;
	});
	[[TGClient shared] canSendInChat:chatId completion:^(BOOL canSend, BOOL isChannel){
		TGForwardPicker *me = weakSelf;
		if (!me)
			return;
		me.picking = NO;
		if (!canSend){
			[me showFailure:isChannel
					? @"You can't post in this channel."
					: @"You can't send messages here."];
			return;
		}
		[me finishWithChat:chatId];
	}];
}

- (void)finishWithChat:(int64_t)chatId {
	void (^picked)(int64_t) = self.onPicked;
	self.onPicked = nil;
	if (picked)
		picked(chatId);
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showFailure:(NSString *)message {
	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:nil message:message
										  cancelButtonTitle:@"OK" okButtonTitle:nil
											completionBlock:nil];
	[alert show];
}

@end

// vim:ft=objc

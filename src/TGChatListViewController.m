#import "TGChatListViewController.h"
#import "RootViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGContactsViewController.h"
#import "TGTopicsViewController.h"
#import "TGPopupMenu.h"
#import "TGSnackbar.h"
#import "TGSearchViewController.h"
#import "UIView+SafeTint.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kRowHeight = 73.0f;
static const CGFloat kAvatar = 56.0f;
static const CGFloat kAvatarLeft = 8.0f;
static const CGFloat kTextLeft = 73.0f;

static UIImage *TGDialogListBadgeImage(BOOL highlighted) {
	static UIImage *normal = nil, *bright = nil;
	if (!normal){
		UIImage *raw = [UIImage imageNamed:@"DialogListUnreadBadge.png"];
		normal = [raw stretchableImageWithLeftCapWidth:(int)(raw.size.width / 2)
										  topCapHeight:(int)(raw.size.height / 2)];
		UIImage *rawHigh = [UIImage imageNamed:@"DialogListUnreadBadge_Highlighted.png"];
		bright = [rawHigh stretchableImageWithLeftCapWidth:(int)(rawHigh.size.width / 2)
											  topCapHeight:(int)(rawHigh.size.height / 2)];
	}
	return highlighted ? bright : normal;
}

#pragma mark - cell

@interface TGChatCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *badgeBackground;
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, strong) UIView *onlineDot;
@property (nonatomic, strong) UIImageView *tick;   // your own last message
@property (nonatomic, strong) UIImageView *pin;   // pinned to the top
@property (nonatomic, strong) UIImageView *arrow;
@property (nonatomic, strong) UIImageView *muteIcon;
@property (nonatomic, strong) UIImageView *groupIcon;
@end

@implementation TGChatCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.avatar = [[UIImageView alloc] initWithFrame:CGRectMake(kAvatarLeft, 8, kAvatar, kAvatar)];
	self.avatar.layer.cornerRadius = 5.0f;
	self.avatar.clipsToBounds = YES;
	self.avatar.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
	self.avatar.contentMode = UIViewContentModeScaleAspectFill;
	[self.contentView addSubview:self.avatar];

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.titleLabel.textColor = [UIColor colorWithRed:0x11 / 255.0f green:0x11 / 255.0f blue:0x11 / 255.0f alpha:1.0f];
	// A long name has to stop at the date rather than slide under it.
	self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.titleLabel];

	self.previewLabel = [[UILabel alloc] init];
	self.previewLabel.font = [UIFont systemFontOfSize:14];
	self.previewLabel.textColor = [UIColor colorWithRed:0x88 / 255.0f green:0x88 / 255.0f blue:0x88 / 255.0f alpha:1.0f];
	self.previewLabel.numberOfLines = 2;
	self.previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.previewLabel];

	self.dateLabel = [[UILabel alloc] init];
	self.dateLabel.font = [UIFont systemFontOfSize:13];
	self.dateLabel.textColor = [UIColor colorWithRed:0x33 / 255.0f green:0x7a / 255.0f blue:0xcc / 255.0f alpha:1.0f];
	self.dateLabel.textAlignment = NSTextAlignmentRight;
	self.dateLabel.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:self.dateLabel];

	self.badgeBackground = [[UIImageView alloc] initWithImage:TGDialogListBadgeImage(NO)];
	self.badgeBackground.hidden = YES;
	[self.contentView addSubview:self.badgeBackground];

	self.badge = [[UILabel alloc] init];
	self.badge.font = [UIFont boldSystemFontOfSize:14];
	self.badge.textColor = [UIColor whiteColor];
	self.badge.backgroundColor = [UIColor clearColor];
	self.badge.shadowColor = [UIColor colorWithRed:0x80 / 255.0f green:0x91 / 255.0f blue:0xa6 / 255.0f alpha:1.0f];
	self.badge.shadowOffset = CGSizeMake(0, -1);
	self.badge.textAlignment = NSTextAlignmentCenter;
	self.badge.hidden = YES;
	[self.contentView addSubview:self.badge];

	// The dot sits half off the avatar, so it needs a ring of the row's own
	// colour to stay legible against a photo.
	self.onlineDot = [[UIView alloc] initWithFrame:
			CGRectMake(kAvatarLeft + kAvatar - 14, 8 + kAvatar - 14, 14, 14)];
	self.onlineDot.backgroundColor = [[TGTheme shared] onlineColour];
	self.onlineDot.layer.cornerRadius = 7;
	self.onlineDot.layer.borderWidth = 2;
	self.onlineDot.hidden = YES;
	[self.contentView addSubview:self.onlineDot];

	self.tick = [[UIImageView alloc] init];
	self.tick.hidden = YES;
	[self.contentView addSubview:self.tick];

	// A pinned chat says so where the unread count would be, and gives the
	// place up as soon as there is a count to show.
	self.pin = [[UIImageView alloc] init];
	self.pin.contentMode = UIViewContentModeScaleAspectFit;
	self.pin.hidden = YES;
	[self.contentView addSubview:self.pin];

	self.muteIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"DialogList_Muted.png"]];
	self.muteIcon.hidden = YES;
	[self.contentView addSubview:self.muteIcon];

	self.groupIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"DialogListGroupChatIcon.png"]];
	self.groupIcon.hidden = YES;
	[self.contentView addSubview:self.groupIcon];

	self.arrow = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"DialogListArrow.png"]];
	[self.contentView addSubview:self.arrow];

	UIImage *plate = [[UIImage imageNamed:@"DialogListCell.png"]
			stretchableImageWithLeftCapWidth:1 topCapHeight:0];
	UIImage *platePressed = [[UIImage imageNamed:@"DialogListCellHighlighted.png"]
			stretchableImageWithLeftCapWidth:1 topCapHeight:0];
	self.backgroundView = [[UIImageView alloc] initWithImage:plate];
	self.selectedBackgroundView = [[UIImageView alloc] initWithImage:platePressed];

	self.accessoryType = UITableViewCellAccessoryNone;
	self.selectionStyle = UITableViewCellSelectionStyleBlue;
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.contentView.bounds.size.width;
	CGFloat left = kTextLeft;
	CGFloat retinaPixel = ([UIScreen mainScreen].scale > 1.5f) ? 0.5f : 0.0f;
	CGFloat rightPadding = 16;

	CGFloat countWidth = (int)[self.badge.text sizeWithFont:self.badge.font].width;
	CGFloat badgeWidth = MAX(27, countWidth + 10);
	CGRect badgeFrame = CGRectMake(w - 28 - badgeWidth, 29, badgeWidth, 21);
	self.badgeBackground.frame = badgeFrame;
	self.badge.frame = badgeFrame;
	if (!self.badge.hidden)
		rightPadding += badgeWidth + 7;

	CGFloat dateWidth = (int)[self.dateLabel.text sizeWithFont:self.dateLabel.font].width;
	CGFloat dateX = w - dateWidth - 9;
	self.dateLabel.frame = CGRectMake(dateX - (75 - dateWidth), 9, 75, 15);

	CGFloat titleX = left;
	CGFloat iconWidth = 0;
	if (!self.groupIcon.hidden){
		iconWidth = 21;
		self.groupIcon.frame = CGRectMake(left, 10,
				self.groupIcon.image.size.width, self.groupIcon.image.size.height);
		titleX += iconWidth;
	}

	CGFloat titleWidth = (int)(dateX - 4 - left - 18) - iconWidth;
	if (!self.muteIcon.hidden)
		titleWidth -= 12;
	titleWidth = MIN(titleWidth, [self.titleLabel.text sizeWithFont:self.titleLabel.font].width);
	if (titleWidth < 0)
		titleWidth = 0;
	self.titleLabel.frame = CGRectMake(titleX, 6, titleWidth, 20);

	if (!self.muteIcon.hidden)
		self.muteIcon.frame = CGRectMake(titleX + titleWidth + 3, 12,
				self.muteIcon.image.size.width, self.muteIcon.image.size.height);

	self.previewLabel.frame = CGRectMake(left, 29, w - left - 10 - rightPadding, 40);

	// Your own last message is marked, the way it is in their chat item.
	if (!self.tick.hidden)
		self.tick.frame = CGRectMake(dateX - 15, 11 + retinaPixel, 13, 11);

	if (!self.pin.hidden)
		self.pin.frame = CGRectMake(w - 28 - 16, 32, 16, 16);

	self.arrow.frame = CGRectMake(w - self.arrow.image.size.width - 6, 33,
			self.arrow.image.size.width, self.arrow.image.size.height);
}

@end

#pragma mark - controller

@interface TGChatListViewController () <UISearchBarDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, assign) BOOL showsArchive;      // this IS the archive screen
@property (nonatomic, assign) NSInteger folderId;     // 0 = no folder
@property (nonatomic, strong) NSMutableDictionary *avatars;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *searchResults;   // nil = not searching
@property (nonatomic, strong) NSDictionary *actionChat; // long-pressed row
@property (nonatomic, assign) int64_t chatPendingDeletion;
@property (nonatomic, assign) CGFloat headerHeight;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) id themeObserver;
@end

@implementation TGChatListViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = [self defaultTitle];
	if (!self.showsArchive){
		UIButton *folders = [TGIcons headerButtonWithTitle:@"Folders" bold:NO
													 target:self action:@selector(foldersTapped)];
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:folders];
	}
	self.chats = @[];
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];

	// Without this there is no way to start a conversation at all - you can
	// only reply to chats that already exist.
	UIButton *compose = [UIButton buttonWithType:UIButtonTypeCustom];
	[TGIcons styleHeaderButton:compose];
	[compose setImage:[UIImage imageNamed:@"ComposeMessageIcon"] forState:UIControlStateNormal];
	compose.frame = CGRectMake(0, 0, 30, 30);
	[compose addTarget:self action:@selector(composeTapped) forControlEvents:UIControlEventTouchUpInside];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:compose];

	// Search sits above the list, the way every client puts it - pull down or
	// just start typing.
	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
	self.searchBar.delegate = self;
	self.searchBar.placeholder = @"Search";
	[self styleSearchBar];
	[self rebuildTableHeader];

	// Hold a row for the two things clients put there: pin and mute.
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(rowHeld:)];
	[self.tableView addGestureRecognizer:hold];

	self.tableView.rowHeight = kRowHeight;
	[self applySeparatorStyle];
	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	__weak typeof(self) weakSelf = self;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[[TGTheme shared] styleTabBar:self.tabBarController.tabBar];

	// Restyle in place when the setting changes, rather than needing a restart.
	self.themeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		usingBlock:^(NSNotification *note){
		[TGIcons flush];
		[[TGTheme shared] styleNavigationBar:weakSelf.navigationController.navigationBar];
		weakSelf.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
		weakSelf.tableView.separatorColor = [[TGTheme shared] separatorColour];
		[weakSelf applySeparatorStyle];
		[[TGTheme shared] styleTabBar:weakSelf.tabBarController.tabBar];
		[weakSelf styleSearchBar];
		[weakSelf.tableView reloadData];
	}];

	if ([self.tabBarController isKindOfClass:[RootViewController class]])
		[(RootViewController *)self.tabBarController updateUnreadBadge];

	self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.emptyLabel.backgroundColor = [UIColor clearColor];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.numberOfLines = 2;
	self.emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.emptyLabel.hidden = YES;
	self.emptyLabel.userInteractionEnabled = NO;
	[self.tableView addSubview:self.emptyLabel];

	[self installClientHandlers];
	[self reload];
}

- (void)installClientHandlers {
	__weak typeof(self) weakSelf = self;
	[TGClient shared].onChatsChanged = ^{
		[weakSelf reload];
		TGChatListViewController *me = weakSelf;
		if ([me.tabBarController isKindOfClass:[RootViewController class]])
			[(RootViewController *)me.tabBarController updateUnreadBadge];
	};
	[TGClient shared].onArchiveChanged = ^{
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		if (me.showsArchive)
			[me reload];
		else
			[me rebuildTableHeader];
		[me.tableView reloadData];
	};
	[TGClient shared].onConnectionState = ^(TGConnectionState state, NSString *text){
		// Clients put this in the title bar rather than hiding it in a flag.
		TGChatListViewController *me = weakSelf;
		me.title = text.length ? text : [me defaultTitle];
		[me updateEmptyState];
	};
}

- (NSString *)defaultTitle {
	if (self.showsArchive)
		return @"Archived";
	if (self.folderId != 0){
		for (NSDictionary *f in [TGClient shared].folders)
			if ([f[@"id"] integerValue] == self.folderId)
				return f[@"title"] ?: @"Messages";
	}
	return @"Messages";
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self installClientHandlers];
	NSIndexPath *selected = [self.tableView indexPathForSelectedRow];
	if (selected)
		[self.tableView deselectRowAtIndexPath:selected animated:animated];
	if ([self.tabBarController isKindOfClass:[RootViewController class]])
		[(RootViewController *)self.tabBarController updateUnreadBadge];
	[self reload];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (self.emptyLabel && !self.emptyLabel.hidden)
		[self updateEmptyState];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self updateEmptyState];
}

- (void)updateEmptyState {
	if (!self.emptyLabel)
		return;

	CGRect bounds = self.tableView.bounds;
	self.emptyLabel.frame = CGRectMake(20,
			bounds.origin.y + (int)(bounds.size.height / 2) - 40,
			bounds.size.width - 40, 44);

	NSInteger rows = [self visibleChats].count + [self headerRows].count;
	if (rows > 0){
		self.emptyLabel.hidden = YES;
		return;
	}

	NSString *text;
	if (self.searchResults)
		text = @"No results";
	else if ([TGClient shared].connectionState != TGConnectionStateReady &&
			 [TGClient shared].connectionState != TGConnectionStateUnknown)
		text = @"Connecting…";
	else if (self.showsArchive)
		text = @"No archived chats";
	else if (self.folderId != 0)
		text = @"No chats in this folder";
	else
		text = @"No chats yet.\nTap the pencil to start one.";

	self.emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.emptyLabel.text = text;
	self.emptyLabel.hidden = NO;
	[self.tableView bringSubviewToFront:self.emptyLabel];
}

- (void)dealloc {
	if (self.themeObserver)
		[[NSNotificationCenter defaultCenter] removeObserver:self.themeObserver];
}

- (void)applySeparatorStyle {
	TGTheme *theme = [TGTheme shared];
	BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
	self.tableView.separatorStyle = plainPlate
			? UITableViewCellSeparatorStyleNone
			: UITableViewCellSeparatorStyleSingleLine;
}

/// The search bar and, when there is one, the archive: both above the first
/// chat and both scrolled out of sight to begin with. Pulling the list down is
/// what brings them back, which is how Telegram hides them.
- (void)rebuildTableHeader {
	CGFloat width = self.tableView.bounds.size.width ?: 320;
	BOOL showArchive = !self.showsArchive && self.folderId == 0 &&
					   [TGClient shared].archivedChats.count > 0;
	CGFloat height = 44 + (showArchive ? kRowHeight : 0);

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	self.searchBar.frame = CGRectMake(0, 0, width, 44);
	[header addSubview:self.searchBar];

	if (showArchive){
		TGChatCell *row = [[TGChatCell alloc] initWithStyle:UITableViewCellStyleDefault
											reuseIdentifier:nil];
		row.frame = CGRectMake(0, 44, width, kRowHeight);
		row.titleLabel.text = @"Archived Chats";
		row.titleLabel.textColor = [[TGTheme shared] primaryTextColour];
		row.previewLabel.text = [NSString stringWithFormat:@"%lu chats",
				(unsigned long)[TGClient shared].archivedChats.count];
		row.previewLabel.textColor = [[TGTheme shared] secondaryTextColour];
		row.avatar.image = [TGIcons archiveAvatarOfSide:kAvatar];
		row.avatar.backgroundColor = [UIColor clearColor];
		row.backgroundColor = [[TGTheme shared] listBackgroundColour];
		row.userInteractionEnabled = YES;
		[row addGestureRecognizer:[[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(openArchive)]];
		[row layoutSubviews];
		[header addSubview:row];

		UIView *hair = [[UIView alloc] initWithFrame:
				CGRectMake(0, height - 0.5f, width, 0.5f)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		[header addSubview:hair];
	}

	CGFloat wasHidingHeader = self.headerHeight;
	self.tableView.tableHeaderView = header;
	self.headerHeight = height;
	[self hideHeaderAboveFrom:wasHidingHeader];
}

/// Scroll the header off the top without animating, so the list opens on the
/// first chat. The archive arrives after the first layout, which makes the
/// header taller, so "still at the top" means the old height as well as zero -
/// otherwise the row appears and stays on screen.
- (void)hideHeaderAboveFrom:(CGFloat)previousHeight {
	if (self.tableView.contentSize.height <= self.tableView.bounds.size.height)
		return;
	CGFloat y = self.tableView.contentOffset.y;
	if (y > 0.5f && fabs(y - previousHeight) > 0.5f)
		return;   // the user has scrolled somewhere of their own; leave it
	self.tableView.contentOffset = CGPointMake(0, self.headerHeight);
}

/// The bar in the header is a way in, not a place to type: touching it hands
/// over to the search page, which has room for the results and the keyboard.
- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
	TGSearchViewController *search = [[TGSearchViewController alloc] init];
	[self.navigationController pushViewController:search animated:YES];
	return NO;
}

/// barTintColor paints the bar around the field but leaves the field itself
/// white, which on a dark list is a slab of light at the top. barStyle is what
/// turns the field over too.
- (void)styleSearchBar {
	TGTheme *theme = [TGTheme shared];
	self.searchBar.barStyle = theme.isDark ? UIBarStyleBlack : UIBarStyleDefault;
	if ([self.searchBar respondsToSelector:@selector(setBarTintColor:)]){
		self.searchBar.barTintColor = [theme listBackgroundColour];
		[self.searchBar tg_setTintColor:[theme accentColour]];
	} else {
		[self.searchBar tg_setTintColor:[UIColor colorWithWhite:0.68f alpha:1.0f]];
	}
}

/// Saved Messages is your own chat; it is not always in the list, and every
/// client keeps a way in regardless.
- (void)openSavedMessages {
	int64_t chatId = [[TGClient shared] savedMessagesChatId];
	if (!chatId)
		return;
	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = chatId;
	vc.chatTitle = @"Saved Messages";
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)composeTapped {
	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	contacts.title = @"New Message";
	contacts.isPickerMode = YES;
	[self.navigationController pushViewController:contacts animated:YES];
}

- (void)reload {
	if (self.showsArchive){
		self.chats = [TGClient shared].archivedChats ?: @[];
		[self.tableView reloadData];
		[self fetchMissingAvatars];
		return;
	}

	if (self.folderId != 0){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] chatsInFolder:self.folderId completion:^(NSArray *chats){
			weakSelf.chats = chats ?: @[];
			[weakSelf.tableView reloadData];
			[weakSelf fetchMissingAvatars];
		}];
		return;
	}

	self.chats = [TGClient shared].chats ?: @[];
	[self.tableView reloadData];
	[self rebuildTableHeader];
	[self fetchMissingAvatars];
}

/// Nothing sits above the chats any more. The archive lives in the table's
/// header, hidden above the top of the list until you pull down for it - which
/// is where Telegram keeps it - and Saved Messages is simply a chat, because
/// pinning your own notes to the top of the list is not something it does.
- (NSArray *)headerRows {
	return @[];
}

- (BOOL)hasArchiveRow {
	return NO;
}

- (void)openArchive {
	TGChatListViewController *archive = [[TGChatListViewController alloc] init];
	archive.showsArchive = YES;
	[self.navigationController pushViewController:archive animated:YES];
}

/// Folders are a filter over the same chats, offered as a choice.
- (void)foldersTapped {
	NSArray *folders = [TGClient shared].folders;
	// Tapping and getting nothing back reads as a broken button; an account
	// with no folders has to say so.
	if (!folders.count){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Folders"
				message:@"This account has no chat folders. They are set up in "
						@"Telegram on a desktop or a newer phone, and appear here."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
		return;
	}

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Show"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:@"All chats", nil];
	for (NSDictionary *f in folders)
		[sheet addButtonWithTitle:f[@"title"]];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	UITabBar *tabBar = [self.tabBarController isKindOfClass:UITabBarController.class]
			? self.tabBarController.tabBar : nil;
	if (tabBar)
		[sheet showFromTabBar:tabBar];
	else
		[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	// Saved Messages has its own row now, so this sheet is All chats followed
	// by the folders themselves.
	NSArray *folders = [TGClient shared].folders;
	if (index == 0){
		self.folderId = 0;
	} else if (index - 1 < (NSInteger)folders.count){
		NSDictionary *f = folders[index - 1];
		self.folderId = [f[@"id"] integerValue];
	} else {
		return;
	}
	self.title = [self defaultTitle];
	[self reload];
}

/// Avatars are fetched once each and cached by file id.
- (void)fetchMissingAvatars {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *c in self.chats){
		NSNumber *fileId = c[@"photoFileId"];
		if (!fileId || self.avatars[fileId] || [self.avatarsRequested containsObject:fileId])
			continue;
		[self.avatarsRequested addObject:fileId];

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			TGChatListViewController *me = weakSelf;
			if (!me || !path)
				return;
			UIImage *img = [UIImage imageWithContentsOfFile:path];
			if (!img)
				return;
			me.avatars[fileId] = img;
			[me.tableView reloadData];
		}];
	}
}

/// Today shows the time, this week the weekday, older the date - as clients do.
static NSString *TGChatDate(NSTimeInterval unix) {
	if (unix <= 0)
		return @"";

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:unix];
	NSTimeInterval age = -[date timeIntervalSinceNow];

	static NSDateFormatter *time = nil, *weekday = nil, *full = nil;
	if (!time){
		time = [[NSDateFormatter alloc] init];    [time setDateFormat:@"HH:mm"];
		weekday = [[NSDateFormatter alloc] init]; [weekday setDateFormat:@"EEE"];
		full = [[NSDateFormatter alloc] init];    [full setDateFormat:@"dd.MM.yy"];
	}

	if (age < 24 * 3600)     return [time stringFromDate:date];
	if (age < 7 * 24 * 3600) return [weekday stringFromDate:date];
	return [full stringFromDate:date];
}

#pragma mark - table

static const NSInteger kChatActionsTag = 77;

- (void)rowHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;

	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:[hold locationInView:self.tableView]];
	if (path)
		[self showActionsForRow:path.row];
}

/// Split out from the gesture so itglegacy://holdrow/N can reach it: a long
/// press cannot be delivered through a URL, and this menu needs checking.
- (void)showActionsForRow:(NSInteger)row {
	if (self.searchResults)
		return;

	NSInteger index = row - [self headerRows].count;
	if (index < 0)
		return;

	NSArray *rows = [self visibleChats];
	if (index >= (NSInteger)rows.count)
		return;
	self.actionChat = rows[index];

	BOOL pinned = [self.actionChat[@"isPinned"] boolValue];
	BOOL muted  = [self.actionChat[@"isMuted"] boolValue];
	NSArray *items = @[
		@{@"title" : (pinned ? @"Unpin" : @"Pin"),
		  @"icon"  : (pinned ? @"unpin" : @"pin")},
		@{@"title" : (muted ? @"Unmute" : @"Mute"),
		  @"icon"  : (muted ? @"unmute" : @"mute")},
		@{@"title" : (self.showsArchive ? @"Unarchive" : @"Archive"),
		  @"icon"  : (self.showsArchive ? @"unarchive" : @"archive")},
		@{@"title" : @"Delete and Leave", @"icon" : @"delete", @"destructive" : @YES},
	];

	CGRect rect = [self.tableView rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	CGPoint where = [self.tableView convertPoint:
			CGPointMake(120, CGRectGetMaxY(rect) - 10) toView:self.navigationController.view];

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		[weakSelf runChatAction:choice];
	}];
}

- (void)runChatAction:(NSInteger)choice {
	int64_t chatId = [self.actionChat[@"id"] longLongValue];
	if (choice == 0)
		[[TGClient shared] setChat:chatId pinned:![self.actionChat[@"isPinned"] boolValue]];
	else if (choice == 1)
		[[TGClient shared] setChat:chatId muted:![self.actionChat[@"isMuted"] boolValue]];
	else if (choice == 2)
		[[TGClient shared] setChat:chatId archived:!self.showsArchive];
	else
		[self confirmDeleteChat:chatId];
	self.actionChat = nil;
}

/// Leaving cannot be taken back once it has happened, so it does not happen at
/// once: the row goes, and the count on the plate is the window to change your
/// mind. Their design answers this with a snackbar rather than a dialog.
- (void)confirmDeleteChat:(int64_t)chatId {
	self.chatPendingDeletion = chatId;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[TGSnackbar showInView:self.navigationController.view
					  text:@"Chat deleted"
				   seconds:5
				  onCommit:^{
		[[TGClient shared] deleteChat:chatId];
		TGChatListViewController *me = weakSelf;
		me.chatPendingDeletion = 0;
		[me reload];
	}];

	// UNDO simply never commits; the row has to come back when it does not.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		TGChatListViewController *me = weakSelf;
		if (me.chatPendingDeletion == chatId){
			me.chatPendingDeletion = 0;
			[me.tableView reloadData];
		}
	});
}

#pragma mark - search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
	if (!query.length){
		self.searchResults = nil;
		[self.tableView reloadData];
		return;
	}

	// Chat titles match locally and instantly; messages need the server. Both
	// land in one list, chats first, which is what the query usually means.
	NSMutableArray *results = [NSMutableArray array];
	for (NSDictionary *c in [TGClient shared].chats)
		if ([c[@"title"] rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound)
			[results addObject:c];
	self.searchResults = results;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchMessages:query completion:^(NSArray *messages){
		TGChatListViewController *me = weakSelf;
		// A slower answer to an older query must not replace a newer one.
		if (!me || ![me.searchBar.text isEqualToString:query])
			return;
		NSMutableArray *combined = [results mutableCopy];
		for (NSDictionary *m in messages)
			[combined addObject:@{
				@"id"    : m[@"chatId"] ?: @0,
				@"title" : m[@"chatTitle"] ?: @"",
				@"text"  : m[@"text"] ?: @"",
				@"date"  : m[@"date"] ?: @0,
			}];
		me.searchResults = combined;
		[me.tableView reloadData];
	}];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	self.searchResults = nil;
	[searchBar resignFirstResponder];
	[self.tableView reloadData];
}

/// Saved Messages has a row of its own above the list, so leaving it among the
/// chats as well would show it twice.
- (NSArray *)visibleChats {
	if (self.searchResults)
		return self.searchResults;

	BOOL hideSaved = [[self headerRows] containsObject:@"saved"];
	int64_t saved = hideSaved ? [[TGClient shared] savedMessagesChatId] : 0;
	if (!hideSaved && !self.chatPendingDeletion)
		return self.chats;

	NSMutableArray *rest = [NSMutableArray array];
	for (NSDictionary *c in self.chats){
		int64_t chatId = [c[@"id"] longLongValue];
		// A chat waiting on the undo plate is already off the list; putting it
		// back is what UNDO does.
		if (chatId == saved || chatId == self.chatPendingDeletion)
			continue;
		[rest addObject:c];
	}
	return rest;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	[self updateEmptyState];
	if (self.searchResults)
		return self.searchResults.count;
	return [self visibleChats].count + [self headerRows].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGChatCell";
	TGChatCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	cell.backgroundColor = [theme listBackgroundColour];
	BOOL plainPlate = (!theme.isDark && theme.importedName == nil);
	cell.backgroundView.hidden = !plainPlate;
	cell.titleLabel.textColor = [theme primaryTextColour];
	cell.previewLabel.textColor = [theme secondaryTextColour];
	cell.dateLabel.textColor = [theme accentColour];
	cell.onlineDot.hidden = YES;
	cell.tick.hidden = YES;
	cell.muteIcon.hidden = YES;
	cell.groupIcon.hidden = YES;
	cell.pin.hidden = YES;
	cell.badge.hidden = YES;
	cell.badgeBackground.hidden = YES;
	cell.badge.text = @"";
	cell.dateLabel.text = @"";
	cell.previewLabel.text = @"";
	cell.onlineDot.layer.borderColor = [theme listBackgroundColour].CGColor;

	NSArray *header = [self headerRows];
	NSArray *rows = [self visibleChats];
	if (indexPath.row >= (NSInteger)(header.count + rows.count))
		return cell;
	if (indexPath.row < (NSInteger)header.count){
		BOOL isArchive = [header[indexPath.row] isEqualToString:@"archive"];
		cell.titleLabel.text = isArchive ? @"Archived Chats" : @"Saved Messages";
		cell.previewLabel.text = isArchive
				? [NSString stringWithFormat:@"%lu chats",
						(unsigned long)[TGClient shared].archivedChats.count]
				: @"Your own notes and forwards";
		cell.dateLabel.text = @"";
		cell.badge.hidden = YES;
		cell.badgeBackground.hidden = YES;
		cell.avatar.image = isArchive
				? [TGIcons archiveAvatarOfSide:kAvatar]
				: [TGIcons savedMessagesAvatarOfSide:kAvatar];
		cell.avatar.backgroundColor = [UIColor clearColor];
		[cell setNeedsLayout];
		return cell;
	}

	NSDictionary *c = rows[indexPath.row - header.count];
	cell.titleLabel.text = c[@"title"];
	cell.dateLabel.text = TGChatDate([c[@"date"] doubleValue]);

	// Someone typing takes the preview over for as long as it lasts, in their
	// blurple rather than the grey the preview uses.
	NSString *action = c[@"action"];
	if ([action length]){
		cell.previewLabel.text = action;
		cell.previewLabel.textColor = [theme typingColour];
	} else {
		cell.previewLabel.text = c[@"text"];
	}

	cell.onlineDot.hidden = ![c[@"isOnline"] boolValue];
	cell.tick.hidden = ![c[@"outgoing"] boolValue];
	if (!cell.tick.hidden)
		cell.tick.image = [UIImage imageNamed:@"DialogListSent"];

	cell.muteIcon.hidden = ![c[@"isMuted"] boolValue];
	cell.groupIcon.hidden = ![c[@"isGroup"] boolValue];

	NSInteger unread = [c[@"unread"] integerValue];
	cell.badge.hidden = (unread <= 0);
	cell.badgeBackground.hidden = cell.badge.hidden;
	cell.pin.hidden = !([c[@"isPinned"] boolValue] && unread <= 0);
	if (!cell.pin.hidden){
		cell.pin.image = [TGIcons menuGlyphNamed:@"pin"];
		[cell.pin tg_setTintColor:[theme secondaryTextColour]];
	}
	cell.badge.text = unread > 0
			? (unread < 1000 ? [NSString stringWithFormat:@"%ld", (long)unread]
							 : [NSString stringWithFormat:@"%ldK", (long)(unread / 1000)])
			: @"";

	NSNumber *fileId = c[@"photoFileId"];
	UIImage *photo = fileId ? self.avatars[fileId] : nil;
	if ([c[@"isSaved"] boolValue])
		photo = [TGIcons savedMessagesAvatarOfSide:kAvatar];
	if (!photo){
		NSString *title = c[@"title"] ?: @"";
		NSString *initials = title.length ? [title substringToIndex:1] : @"?";
		photo = [TGIcons avatarWithInitials:initials.uppercaseString
									   size:kAvatar
								   colourId:[c[@"id"] longLongValue]];
	}
	cell.avatar.image = photo;
	cell.avatar.backgroundColor = [UIColor clearColor];

	[cell setNeedsLayout];
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.searchResults)
		return NO;
	NSArray *header = [self headerRows];
	return indexPath.row >= (NSInteger)header.count;
}

- (NSString *)tableView:(UITableView *)tableView
		titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	return @"Delete";
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (style != UITableViewCellEditingStyleDelete)
		return;
	NSArray *header = [self headerRows];
	NSArray *rows = [self visibleChats];
	NSInteger index = indexPath.row - (NSInteger)header.count;
	if (index < 0 || index >= (NSInteger)rows.count)
		return;
	int64_t chatId = [rows[index][@"id"] longLongValue];
	[self confirmDeleteChat:chatId];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSArray *header = [self headerRows];
	NSArray *rows = [self visibleChats];
	if (indexPath.row >= (NSInteger)(header.count + rows.count))
		return;
	if (indexPath.row < (NSInteger)header.count){
		if ([header[indexPath.row] isEqualToString:@"archive"])
			[self openArchive];
		else
			[self openSavedMessages];
		return;
	}

	NSDictionary *c = rows[indexPath.row - header.count];
	int64_t chatId = [c[@"id"] longLongValue];
	if (!chatId)
		return;
	NSLog(@"open chat: group=%@ forum=%@", c[@"isGroup"], c[@"isForum"] ?: @"(absent)");

	if ([c[@"isForum"] boolValue]){
		TGTopicsViewController *topics = [[TGTopicsViewController alloc] init];
		topics.chatId = chatId;
		topics.chatTitle = c[@"title"];
		[self.navigationController pushViewController:topics animated:YES];
		return;
	}

	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = chatId;
	vc.chatTitle = c[@"title"];
	vc.isGroup = [c[@"isGroup"] boolValue];
	[self.navigationController pushViewController:vc animated:YES];
}

@end

// vim:ft=objc

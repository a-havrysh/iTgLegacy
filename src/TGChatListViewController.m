#import "TGChatListViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGContactsViewController.h"
#import "TGTopicsViewController.h"
#import <QuartzCore/QuartzCore.h>

// Their chat item is 80dp on a 360dp screen; on 320pt that is 71, and 72
// is what iOS uses for a two-line row anyway.
static const CGFloat kRowHeight = 72.0f;
// 57dp avatar scaled the same way.
static const CGFloat kAvatar = 50.0f;

#pragma mark - cell

@interface TGChatCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, strong) UIView *onlineDot;
@property (nonatomic, strong) UIImageView *tick;   // your own last message
@end

@implementation TGChatCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.avatar = [[UIImageView alloc] initWithFrame:CGRectMake(10, 8, kAvatar, kAvatar)];
	self.avatar.layer.cornerRadius = kAvatar / 2;
	self.avatar.clipsToBounds = YES;
	self.avatar.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
	self.avatar.contentMode = UIViewContentModeScaleAspectFill;
	[self.contentView addSubview:self.avatar];

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.titleLabel.textColor = [UIColor colorWithWhite:0.1f alpha:1.0f];
	[self.contentView addSubview:self.titleLabel];

	self.previewLabel = [[UILabel alloc] init];
	self.previewLabel.font = [UIFont systemFontOfSize:14];
	self.previewLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
	self.previewLabel.numberOfLines = 2;
	[self.contentView addSubview:self.previewLabel];

	self.dateLabel = [[UILabel alloc] init];
	self.dateLabel.font = [UIFont systemFontOfSize:12];
	self.dateLabel.textColor = [UIColor colorWithWhite:0.55f alpha:1.0f];
	self.dateLabel.textAlignment = NSTextAlignmentRight;
	[self.contentView addSubview:self.dateLabel];

	self.badge = [[UILabel alloc] init];
	self.badge.font = [UIFont boldSystemFontOfSize:13];
	self.badge.textColor = [UIColor whiteColor];
	self.badge.backgroundColor = [[TGTheme shared] badgeColour];
	self.badge.textAlignment = NSTextAlignmentCenter;
	self.badge.layer.cornerRadius = 10;
	self.badge.clipsToBounds = YES;
	self.badge.hidden = YES;
	[self.contentView addSubview:self.badge];

	// The dot sits half off the avatar, so it needs a ring of the row's own
	// colour to stay legible against a photo.
	self.onlineDot = [[UIView alloc] initWithFrame:
			CGRectMake(10 + kAvatar - 14, 8 + kAvatar - 14, 14, 14)];
	self.onlineDot.backgroundColor = [[TGTheme shared] onlineColour];
	self.onlineDot.layer.cornerRadius = 7;
	self.onlineDot.layer.borderWidth = 2;
	self.onlineDot.hidden = YES;
	[self.contentView addSubview:self.onlineDot];

	self.tick = [[UIImageView alloc] init];
	self.tick.hidden = YES;
	[self.contentView addSubview:self.tick];

	self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.contentView.bounds.size.width;
	CGFloat left = kAvatar + 20;
	CGFloat right = 78;   // room for date and the disclosure arrow

	self.dateLabel.frame  = CGRectMake(w - right, 10, right - 8, 16);
	self.titleLabel.frame = CGRectMake(left, 9, w - left - right, 20);
	self.previewLabel.frame = CGRectMake(left, 30, w - left - right + 40, 32);

	// Your own last message is marked, the way it is in their chat item.
	if (!self.tick.hidden){
		CGSize s = [self.dateLabel.text sizeWithFont:self.dateLabel.font];
		self.tick.frame = CGRectMake(w - 8 - s.width - 19, 13, 15, 9);
	}

	if (!self.badge.hidden){
		CGSize s = [self.badge.text sizeWithFont:self.badge.font];
		CGFloat bw = MAX(20, s.width + 12);
		self.badge.frame = CGRectMake(w - right + 30, 36, bw, 20);
	}
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
@end

@implementation TGChatListViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = self.showsArchive ? @"Archived" : @"Chats";
	if (!self.showsArchive)
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
				initWithTitle:@"Folders" style:UIBarButtonItemStylePlain
					   target:self action:@selector(foldersTapped)];
	self.chats = @[];
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];

	// Without this there is no way to start a conversation at all - you can
	// only reply to chats that already exist.
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithImage:[TGIcons compose]
					style:UIBarButtonItemStylePlain
				   target:self
				   action:@selector(composeTapped)];

	// Search sits above the list, the way every client puts it - pull down or
	// just start typing.
	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
	self.searchBar.delegate = self;
	self.searchBar.placeholder = @"Search";
	[self styleSearchBar];
	self.tableView.tableHeaderView = self.searchBar;

	// Hold a row for the two things clients put there: pin and mute.
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(rowHeld:)];
	[self.tableView addGestureRecognizer:hold];

	self.tableView.rowHeight = kRowHeight;
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
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
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		usingBlock:^(NSNotification *note){
		[TGIcons flush];
		[[TGTheme shared] styleNavigationBar:weakSelf.navigationController.navigationBar];
		weakSelf.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
		weakSelf.tableView.separatorColor = [[TGTheme shared] separatorColour];
		[[TGTheme shared] styleTabBar:weakSelf.tabBarController.tabBar];
		[weakSelf styleSearchBar];
		[weakSelf.tableView reloadData];
	}];

	[TGClient shared].onChatsChanged = ^{
		[weakSelf reload];
	};
	[TGClient shared].onArchiveChanged = ^{
		[weakSelf.tableView reloadData];
	};
	[TGClient shared].onConnectionState = ^(TGConnectionState state, NSString *text){
		// Clients put this in the title bar rather than hiding it in a flag.
		weakSelf.title = text ?: @"Chats";
	};
	[self reload];
}

/// barTintColor paints the bar around the field but leaves the field itself
/// white, which on a dark list is a slab of light at the top. barStyle is what
/// turns the field over too.
- (void)styleSearchBar {
	TGTheme *theme = [TGTheme shared];
	self.searchBar.barStyle = theme.isDark ? UIBarStyleBlack : UIBarStyleDefault;
	if ([self.searchBar respondsToSelector:@selector(setBarTintColor:)])
		self.searchBar.barTintColor = [theme listBackgroundColour];
	self.searchBar.tintColor = [theme accentColour];
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
	vc.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)composeTapped {
	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	contacts.title = @"New Message";
	[self.navigationController pushViewController:contacts animated:YES];
}

- (void)reload {
	if (self.showsArchive){
		self.chats = [TGClient shared].archivedChats;
		[self.tableView reloadData];
		[self fetchMissingAvatars];
		return;
	}

	if (self.folderId != 0){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] chatsInFolder:self.folderId completion:^(NSArray *chats){
			weakSelf.chats = chats;
			[weakSelf.tableView reloadData];
			[weakSelf fetchMissingAvatars];
		}];
		return;
	}

	self.chats = [TGClient shared].chats;
	[self.tableView reloadData];
	[self fetchMissingAvatars];
}

/// The archive is one row above the list, as clients place it.
- (BOOL)hasArchiveRow {
	return !self.searchResults && !self.showsArchive && self.folderId == 0 &&
			[TGClient shared].archivedChats.count > 0;
}

- (void)openArchive {
	TGChatListViewController *archive = [[TGChatListViewController alloc] init];
	archive.showsArchive = YES;
	archive.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:archive animated:YES];
}

/// Folders are a filter over the same chats, offered as a choice.
- (void)foldersTapped {
	NSArray *folders = [TGClient shared].folders;
	if (!folders.count)
		return;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Show"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:@"All chats", nil];
	for (NSDictionary *f in folders)
		[sheet addButtonWithTitle:f[@"title"]];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == kChatActionsTag){
		int64_t chatId = [self.actionChat[@"id"] longLongValue];
		if (index == 0)
			[[TGClient shared] setChat:chatId pinned:![self.actionChat[@"isPinned"] boolValue]];
		else if (index == 1)
			[[TGClient shared] setChat:chatId muted:![self.actionChat[@"isMuted"] boolValue]];
		else if (index == sheet.destructiveButtonIndex)
			[self confirmDeleteChat:chatId];
		self.actionChat = nil;
		return;
	}

	NSArray *folders = [TGClient shared].folders;
	if (index == 1){
		[self openSavedMessages];
		return;
	}
	if (index == 0){
		self.folderId = 0;
		self.title = self.showsArchive ? @"Archived" : @"Chats";
	if (!self.showsArchive)
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
				initWithTitle:@"Folders" style:UIBarButtonItemStylePlain
					   target:self action:@selector(foldersTapped)];
	} else if (index - 2 < (NSInteger)folders.count){
		NSDictionary *f = folders[index - 2];
		self.folderId = [f[@"id"] integerValue];
		self.title = f[@"title"];
	}
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
	if (!path || ([self hasArchiveRow] && path.row == 0))
		return;

	NSArray *rows = self.searchResults ?: self.chats;
	NSInteger index = path.row - ([self hasArchiveRow] ? 1 : 0);
	if (index < 0 || index >= (NSInteger)rows.count)
		return;
	self.actionChat = rows[index];

	UIActionSheet *sheet = [[UIActionSheet alloc]
			initWithTitle:self.actionChat[@"title"]
				 delegate:self
		cancelButtonTitle:nil
   destructiveButtonTitle:nil
		otherButtonTitles:([self.actionChat[@"isPinned"] boolValue] ? @"Unpin" : @"Pin"),
						  ([self.actionChat[@"isMuted"] boolValue] ? @"Unmute" : @"Mute"), nil];
	sheet.destructiveButtonIndex = [sheet addButtonWithTitle:@"Delete and Leave"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kChatActionsTag;
	[sheet showInView:self.view];
}

/// Leaving is not undoable, so it asks first.
- (void)confirmDeleteChat:(int64_t)chatId {
	self.chatPendingDeletion = chatId;
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Delete and Leave"
			message:@"This chat will be removed from the list."
		   delegate:self
  cancelButtonTitle:@"Cancel"
  otherButtonTitles:@"Delete", nil];
	[alert show];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
	if (index != alert.cancelButtonIndex && self.chatPendingDeletion)
		[[TGClient shared] deleteChat:self.chatPendingDeletion];
	self.chatPendingDeletion = 0;
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

- (NSArray *)visibleChats {
	return self.searchResults ?: self.chats;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (self.searchResults)
		return self.searchResults.count;
	return self.chats.count + ([self hasArchiveRow] ? 1 : 0);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGChatCell";
	TGChatCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	cell.backgroundColor = [theme listBackgroundColour];
	cell.titleLabel.textColor = [theme primaryTextColour];
	cell.previewLabel.textColor = [theme secondaryTextColour];
	cell.dateLabel.textColor = [theme secondaryTextColour];
	cell.onlineDot.hidden = YES;
	cell.tick.hidden = YES;
	cell.onlineDot.layer.borderColor = [theme listBackgroundColour].CGColor;

	if ([self hasArchiveRow] && indexPath.row == 0){
		cell.titleLabel.text = @"Archived Chats";
		cell.previewLabel.text = [NSString stringWithFormat:@"%lu chats",
				(unsigned long)[TGClient shared].archivedChats.count];
		cell.dateLabel.text = @"";
		cell.badge.hidden = YES;
		cell.avatar.image = [TGIcons avatarWithInitials:@"\u25bc" size:kAvatar colourId:7];
		cell.avatar.backgroundColor = [UIColor clearColor];
		[cell setNeedsLayout];
		return cell;
	}

	NSDictionary *c = self.searchResults
			? self.searchResults[indexPath.row]
			: self.chats[indexPath.row - ([self hasArchiveRow] ? 1 : 0)];
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

	// A muted chat says so in its title; a pinned one keeps a marker where the
	// date sits when it has none.
	cell.titleLabel.text = [c[@"isMuted"] boolValue]
			? [NSString stringWithFormat:@"%@ \U0001F507", c[@"title"] ?: @""]
			: c[@"title"];
	if ([c[@"isPinned"] boolValue] && !cell.dateLabel.text.length)
		cell.dateLabel.text = @"\U0001F4CC";

	NSInteger unread = [c[@"unread"] integerValue];
	cell.badge.hidden = (unread <= 0);
	cell.badge.text = unread > 0 ? [NSString stringWithFormat:@"%ld", (long)unread] : @"";
	// A muted chat still counts, it just stops shouting about it.
	cell.badge.backgroundColor = [c[@"isMuted"] boolValue]
			? [theme mutedBadgeColour] : [theme badgeColour];

	NSNumber *fileId = c[@"photoFileId"];
	UIImage *photo = fileId ? self.avatars[fileId] : nil;
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if ([self hasArchiveRow] && indexPath.row == 0){
		[self openArchive];
		return;
	}

	NSDictionary *c = self.searchResults
			? self.searchResults[indexPath.row]
			: self.chats[indexPath.row - ([self hasArchiveRow] ? 1 : 0)];
	NSLog(@"open chat: group=%@ forum=%@", c[@"isGroup"], c[@"isForum"] ?: @"(absent)");

	if ([c[@"isForum"] boolValue]){
		TGTopicsViewController *topics = [[TGTopicsViewController alloc] init];
		topics.chatId = [c[@"id"] longLongValue];
		topics.chatTitle = c[@"title"];
		topics.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:topics animated:YES];
		return;
	}

	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = [c[@"id"] longLongValue];
	vc.chatTitle = c[@"title"];
	vc.isGroup = [c[@"isGroup"] boolValue];
	vc.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:vc animated:YES];
}

@end

// vim:ft=objc

#import "TGProfileViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGForwardPicker.h"

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
@end

// A tile in the action row: a glyph over a word.
static const CGFloat kActionTile = 52.0f;

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
	CGFloat side = 84;
	CGFloat height = 16 + side + 8 + 26 + 18 + 10 + kActionTile + 12;

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	header.backgroundColor = [[TGTheme shared] listBackgroundColour];

	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake((width - side) / 2, 16, side, side)];
	self.avatarView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
			UIViewAutoresizingFlexibleRightMargin;
	self.avatarView.layer.cornerRadius = side / 2;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	NSString *initials = self.name.length ? [self.name substringToIndex:1] : @"?";
	self.avatarView.image = [TGIcons avatarWithInitials:initials.uppercaseString
												   size:side
											   colourId:self.userId ?: self.chatId];
	[header addSubview:self.avatarView];

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(10, 16 + side + 8, width - 20, 26)];
	nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	nameLabel.text = self.name;
	nameLabel.font = [UIFont boldSystemFontOfSize:21];
	nameLabel.textAlignment = NSTextAlignmentCenter;
	nameLabel.backgroundColor = [UIColor clearColor];
	nameLabel.textColor = [[TGTheme shared] primaryTextColour];
	[header addSubview:nameLabel];

	self.statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(10, 16 + side + 34, width - 20, 18)];
	self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.statusLabel.font = [UIFont systemFontOfSize:14];
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.statusLabel.backgroundColor = [UIColor clearColor];
	[header addSubview:self.statusLabel];

	[self buildActionsIn:header atY:(16 + side + 62)];

	if (self.userId){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] statusForUser:self.userId completion:^(NSString *status){
			weakSelf.statusLabel.text = status;
		}];
	} else {
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] memberCountForChat:self.chatId completion:^(NSInteger count){
			if (count > 0)
				weakSelf.statusLabel.text = [NSString stringWithFormat:@"%ld members",
						(long)count];
		}];
	}

	self.tableView.tableHeaderView = header;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];

	NSNumber *fileId = self.userId
			? [[TGClient shared] photoFileIdForUserId:self.userId]
			: [[TGClient shared] photoFileIdForChat:self.chatId];
	if (!fileId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		UIImage *image = path ? [UIImage imageWithContentsOfFile:path] : nil;
		if (image) weakSelf.avatarView.image = image;
	}];
}

/// The tiles under the name: a glyph over a word, on a soft rounded plate.
/// Only the ones that mean something here - a group has no one to call.
- (void)buildActionsIn:(UIView *)header atY:(CGFloat)y {
	NSMutableArray *tiles = [NSMutableArray array];
	if (self.userId){
		[tiles addObject:@[@"call",  @"call"]];
		[tiles addObject:@[@"video", @"video"]];
	}
	[tiles addObject:@[(self.muted ? @"unmute" : @"mute"),
					   (self.muted ? @"unmute" : @"mute")]];
	if (self.onSearchTapped)
		[tiles addObject:@[@"search", @"search"]];
	[tiles addObject:@[@"more", @"more"]];

	CGFloat width = header.bounds.size.width;
	CGFloat gap = 6, margin = 10;
	CGFloat tileW = (width - 2 * margin - gap * (tiles.count - 1)) / tiles.count;
	TGTheme *theme = [TGTheme shared];

	for (NSUInteger i = 0; i < tiles.count; i++){
		UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
		tile.frame = CGRectMake(margin + i * (tileW + gap), y, tileW, kActionTile);
		tile.backgroundColor = theme.isDark
				? [UIColor colorWithWhite:1.0f alpha:0.08f]
				: [UIColor colorWithWhite:0.0f alpha:0.05f];
		tile.layer.cornerRadius = 8;
		tile.tag = i;
		[tile addTarget:self action:@selector(actionTileTapped:)
	   forControlEvents:UIControlEventTouchUpInside];
		[header addSubview:tile];

		UIImageView *glyph = [[UIImageView alloc] initWithFrame:
				CGRectMake((tileW - 22) / 2, 8, 22, 22)];
		glyph.image = [TGIcons menuGlyphNamed:tiles[i][0]];
		glyph.contentMode = UIViewContentModeScaleAspectFit;
		glyph.tintColor = [theme accentColour];
		[tile addSubview:glyph];

		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(0, kActionTile - 18, tileW, 14)];
		label.text = tiles[i][1];
		label.font = [UIFont systemFontOfSize:10];
		label.textAlignment = NSTextAlignmentCenter;
		label.textColor = [theme accentColour];
		label.backgroundColor = [UIColor clearColor];
		[tile addSubview:label];
	}
	self.actionNames = tiles;
}

- (void)actionTileTapped:(UIButton *)tile {
	NSString *action = self.actionNames[tile.tag][1];

	if ([action isEqualToString:@"call"] || [action isEqualToString:@"video"]){
		[TGCallViewController presentForUserId:self.userId
										  name:self.name
									  outgoing:YES];
	} else if ([action hasSuffix:@"mute"]){
		self.muted = !self.muted;
		[[TGClient shared] setChat:self.chatId muted:self.muted];
		[self buildHeader];              // the tile says the opposite now
	} else if ([action isEqualToString:@"search"]){
		if (self.onSearchTapped) self.onSearchTapped();
	} else {
		[self showMoreMenuFrom:tile];
	}
}

/// The "more" menu from the current client, minus what this app cannot do:
/// no secret chats, no gifts.
- (void)showMoreMenuFrom:(UIView *)tile {
	NSMutableArray *items = [NSMutableArray array];
	if (self.userId)
		[items addObject:@{@"title" : @"Share contact", @"icon" : @"forward"}];
	[items addObject:@{@"title" : @"Auto-delete messages", @"icon" : @"delete"}];
	[items addObject:@{@"title" : @"Clear history", @"icon" : @"delete"}];
	if (self.userId)
		[items addObject:@{@"title" : (self.blocked ? @"Unblock" : @"Block"),
						   @"icon" : @"privacy", @"destructive" : @YES}];

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

	[[TGClient shared] setUser:self.userId blocked:!self.blocked];
	self.blocked = !self.blocked;
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (sheet.tag != 70 || index == sheet.cancelButtonIndex)
		return;
	static const NSInteger seconds[4] = {0, 86400, 604800, 2592000};
	[[TGClient shared] setChat:self.chatId autoDeleteSeconds:seconds[index]];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
	if (alert.tag == 71 && index != alert.cancelButtonIndex)
		[[TGClient shared] clearHistoryInChat:self.chatId];
}

- (void)loadDetails {
	self.muted = [[TGClient shared] isChatMuted:self.chatId];

	if (!self.userId){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] membersOfChat:self.chatId completion:^(NSArray *members){
			weakSelf.members = members;
			[weakSelf.tableView reloadData];
		}];
		// A group has a description, a size and a link, none of which this
		// screen used to ask for.
		[[TGClient shared] chatProfile:self.chatId completion:^(NSDictionary *info){
			NSMutableArray *rows = [NSMutableArray array];
			if ([info[@"description"] length])
				[rows addObject:@[@"about", info[@"description"]]];
			if ([info[@"members"] integerValue] > 0)
				[rows addObject:@[@"members", [info[@"members"] stringValue]]];
			if ([info[@"admins"] integerValue] > 0)
				[rows addObject:@[@"admins", [info[@"admins"] stringValue]]];
			if ([info[@"inviteLink"] length])
				[rows addObject:@[@"invite link", info[@"inviteLink"]]];
			weakSelf.details = rows;
			[weakSelf.tableView reloadData];
		}];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userInfo:self.userId completion:^(NSDictionary *user){
		if (!user) return;
		NSMutableArray *rows = [NSMutableArray array];
		NSString *phone = user[@"phone_number"];
		if (phone.length){
			[rows addObject:@[@"mobile", [@"+" stringByAppendingString:phone]]];
			weakSelf.phoneNumber = phone;
		}
		NSString *username = user[@"usernames"][@"active_usernames"][0];
		if (username.length)
			[rows addObject:@[@"username", [@"@" stringByAppendingString:username]]];
		if ([user[@"is_premium"] boolValue])
			[rows addObject:@[@"subscription", @"Telegram Premium"]];
		weakSelf.details = rows;
		[weakSelf.tableView reloadData];

		// The bio, the birthday and how many groups you share live in the full
		// record, which this screen never asked for - so "about" was missing
		// from a profile that has one.
		[[TGClient shared] userProfile:weakSelf.userId completion:^(NSDictionary *info){
			NSMutableArray *more = [rows mutableCopy];
			if ([info[@"bio"] length])
				[more insertObject:@[@"about", info[@"bio"]]
						   atIndex:MIN((NSUInteger)2, more.count)];
			if ([info[@"birthday"] length])
				[more addObject:@[@"birthday", info[@"birthday"]]];
			if ([info[@"commonGroups"] integerValue] > 0)
				[more addObject:@[@"groups in common",
						[info[@"commonGroups"] stringValue]]];
			weakSelf.details = more;
			[weakSelf.tableView reloadData];
		}];

		// updateUser does not always carry a photo; getUser does.
		NSNumber *photoId = user[@"profile_photo"][@"small"][@"id"];
		if (photoId)
			[[TGClient shared] downloadFile:photoId.integerValue completion:^(NSString *path){
				UIImage *image = path ? [UIImage imageWithContentsOfFile:path] : nil;
				if (image) weakSelf.avatarView.image = image;
			}];
	}];
}

- (void)loadMedia {
	__weak typeof(self) weakSelf = self;
	if (self.userId){
		[[TGClient shared] giftsForUser:self.userId completion:^(NSArray *gifts){
			weakSelf.gifts = gifts;
			[weakSelf.tableView reloadData];
		}];
		[[TGClient shared] isUserBlocked:self.userId completion:^(BOOL blocked){
			weakSelf.blocked = blocked;
			[weakSelf.tableView reloadData];
		}];
	}

	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterPhotoAndVideo"
						completion:^(NSArray *messages){
		weakSelf.photos = messages;
		[weakSelf.tableView reloadData];
	}];
	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterDocument"
						completion:^(NSArray *messages){
		weakSelf.files = messages;
		[weakSelf.tableView reloadData];
	}];
}

/// Settings has its own navigation controller, and nothing was styling
/// its bar - an imported theme stopped at the top of the screen.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
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
		return [NSString stringWithFormat:@"%lu members", (unsigned long)self.members.count];
	if (section == 2 && self.photos.count)
		return [NSString stringWithFormat:@"%lu photos and videos", (unsigned long)self.photos.count];
	if (section == 3 && self.files.count)
		return [NSString stringWithFormat:@"%lu files", (unsigned long)self.files.count];
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2) return 84;
	return indexPath.section == 0 ? 52 : 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2)
		return [self photoStripCell:tableView];

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.imageView.image = nil;
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];

	// The information card: what it is in small grey, the value itself under
	// it in the accent colour. Theirs reads that way round because the number
	// matters and the word "mobile" does not.
	if (indexPath.section == 0){
		if (indexPath.row < (NSInteger)self.details.count){
			NSArray *pair = self.details[indexPath.row];
			cell.textLabel.text = pair[0];
			cell.textLabel.font = [UIFont systemFontOfSize:12];
			cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
			cell.detailTextLabel.text = pair[1];
			cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
			cell.detailTextLabel.textColor = [[TGTheme shared] accentColour];
		} else {
			NSDictionary *gift = self.gifts[indexPath.row - self.details.count];
			cell.textLabel.text = @"gift";
			cell.textLabel.font = [UIFont systemFontOfSize:12];
			cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@ stars",
					gift[@"title"], gift[@"starCount"]];
			cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
			cell.detailTextLabel.textColor = [[TGTheme shared] accentColour];
		}
		return cell;
	}

	if (indexPath.section == 1){
		NSDictionary *member = self.members[indexPath.row];
		int64_t userId = [member[@"id"] longLongValue];
		NSString *name = [member[@"name"] length]
				? member[@"name"] : [[TGClient shared] nameForUserId:userId];
		cell.textLabel.text = name ?: @"";
		cell.detailTextLabel.text = nil;
		cell.imageView.image = [TGIcons avatarWithInitials:
				(name.length ? [name substringToIndex:1].uppercaseString : @"?")
													  size:32 colourId:userId];
	} else {
		NSDictionary *m = self.files[indexPath.row];
		cell.textLabel.text = m[@"docName"] ?: @"File";
		cell.detailTextLabel.text = nil;
		cell.imageView.image = [TGIcons document];
	}
	return cell;
}

/// A horizontal strip of thumbnails: a grid would mean a collection view,
/// which iOS 6 has but this screen does not need.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	// The actions live in the tiles now; a row of the card copies its value,
	// which is the only thing there is to do with a phone number or a link.
	if (indexPath.section != 0 || indexPath.row >= (NSInteger)self.details.count)
		return;
	NSString *value = self.details[indexPath.row][1];
	[UIPasteboard generalPasteboard].string = value;

	UILabel *toast = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 0, 120, 34)];
	toast.center = CGPointMake(self.view.bounds.size.width / 2,
							   self.view.bounds.size.height - 70);
	toast.text = @"Copied";
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
	for (NSDictionary *m in self.photos){
		NSNumber *fileId = m[@"photoId"];
		if (!fileId) continue;
		UIImageView *thumb = [[UIImageView alloc] initWithFrame:CGRectMake(x, 2, side, side)];
		thumb.backgroundColor = [UIColor colorWithWhite:0.9f alpha:1];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
		[strip addSubview:thumb];
		x += side + gap;

		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			if (path) thumb.image = [UIImage imageWithContentsOfFile:path];
		}];
	}
	strip.contentSize = CGSizeMake(x, 80);
	return cell;
}

@end

// vim:ft=objc

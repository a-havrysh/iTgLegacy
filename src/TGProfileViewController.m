#import "TGProfileViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"

@interface TGProfileViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSArray *details;   // label/value pairs
@property (nonatomic, strong) NSArray *photos;    // flattened messages
@property (nonatomic, strong) NSArray *files;
@property (nonatomic, strong) NSArray *members;
@property (nonatomic, strong) UIImageView *avatarView;
@end

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

	[self buildHeader];
	[self loadDetails];
	[self loadMedia];
}

/// Avatar and name above the table, the way every client opens a profile.
- (void)buildHeader {
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 150)];
	header.backgroundColor = [UIColor clearColor];

	CGFloat side = 88;
	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake((header.bounds.size.width - side) / 2, 16, side, side)];
	self.avatarView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
			UIViewAutoresizingFlexibleRightMargin;
	self.avatarView.layer.cornerRadius = side / 2;
	self.avatarView.clipsToBounds = YES;
	NSString *initials = self.name.length ? [self.name substringToIndex:1] : @"?";
	self.avatarView.image = [TGIcons avatarWithInitials:initials.uppercaseString
												   size:side
											   colourId:self.userId ?: self.chatId];
	[header addSubview:self.avatarView];

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(10, 112, header.bounds.size.width - 20, 24)];
	nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	nameLabel.text = self.name;
	nameLabel.font = [UIFont boldSystemFontOfSize:19];
	nameLabel.textAlignment = NSTextAlignmentCenter;
	nameLabel.backgroundColor = [UIColor clearColor];
	nameLabel.textColor = [[TGTheme shared] primaryTextColour];
	[header addSubview:nameLabel];

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

- (void)loadDetails {
	if (!self.userId){
		// A group has no user record; what it does have is a size.
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] membersOfChat:self.chatId completion:^(NSArray *members){
			weakSelf.members = members;
			[weakSelf.tableView reloadData];
		}];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userInfo:self.userId completion:^(NSDictionary *user){
		if (!user) return;
		NSMutableArray *rows = [NSMutableArray array];
		NSString *username = user[@"usernames"][@"active_usernames"][0];
		if (username.length)
			[rows addObject:@[@"username", [@"@" stringByAppendingString:username]]];
		NSString *phone = user[@"phone_number"];
		if (phone.length)
			[rows addObject:@[@"phone", [@"+" stringByAppendingString:phone]]];
		weakSelf.details = rows;
		[weakSelf.tableView reloadData];

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

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 5;   // actions, details, members, photos, files
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return self.onSearchTapped ? 1 : 0;
	if (section == 1) return self.details.count;
	if (section == 2) return self.members.count;
	if (section == 3) return self.photos.count ? 1 : 0;   // a strip of thumbnails
	return self.files.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 2 && self.members.count)
		return [NSString stringWithFormat:@"%lu members", (unsigned long)self.members.count];
	if (section == 3 && self.photos.count)
		return [NSString stringWithFormat:@"%lu photos and videos", (unsigned long)self.photos.count];
	if (section == 4 && self.files.count)
		return [NSString stringWithFormat:@"%lu files", (unsigned long)self.files.count];
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 3 ? 84 : 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 3)
		return [self photoStripCell:tableView];

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	if (indexPath.section == 0){
		cell.textLabel.text = @"Search in chat";
		cell.detailTextLabel.text = nil;
		cell.textLabel.textColor = [[TGTheme shared] accentColour];
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	if (indexPath.section == 1){
		NSArray *pair = self.details[indexPath.row];
		cell.textLabel.text = pair[0];
		cell.detailTextLabel.text = pair[1];
	} else if (indexPath.section == 2){
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
	if (indexPath.section == 0 && self.onSearchTapped)
		self.onSearchTapped();
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

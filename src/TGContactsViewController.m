#import "TGContactsViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>

// Their contact row is a 40dp avatar on a 52dp row; 36 and 56 here.
static const CGFloat kContactAvatar = 36.0f;

@interface TGContactsViewController ()
@property (nonatomic, strong) NSArray *users;
@property (nonatomic, strong) NSMutableDictionary *photos;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *photosRequested;
@end

@implementation TGContactsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Contacts";
	self.users = @[];
	self.photos = [NSMutableDictionary dictionary];
	self.photosRequested = [NSMutableSet set];
	self.tableView.rowHeight = 56;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] contactsWithCompletion:^(NSArray *users){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		// Alphabetical, the way a contact list is expected to read.
		me.users = [users sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
			return [a[@"first_name"] localizedCaseInsensitiveCompare:b[@"first_name"]];
		}];
		[me.tableView reloadData];
		NSLog(@"TDLIB CONTACTS: %lu", (unsigned long)me.users.count);
		[me fetchMissingPhotos];
	}];
}

/// One request per picture, cached by file id: the list scrolls past the same
/// rows repeatedly and re-downloading on every pass would never settle.
- (void)fetchMissingPhotos {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *u in self.users){
		NSNumber *fileId = u[@"photoFileId"];
		if (![fileId isKindOfClass:NSNumber.class])
			continue;
		if (self.photos[fileId] || [self.photosRequested containsObject:fileId])
			continue;
		[self.photosRequested addObject:fileId];

		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			TGContactsViewController *me = weakSelf;
			UIImage *photo = path ? [UIImage imageWithContentsOfFile:path] : nil;
			if (!me || !photo)
				return;
			// A cell's own imageView takes the image's size, so a 160px photo
			// would shove the name off the row. Scale once, on arrival.
			UIGraphicsBeginImageContextWithOptions(
					CGSizeMake(kContactAvatar, kContactAvatar), NO, 0);
			[photo drawInRect:CGRectMake(0, 0, kContactAvatar, kContactAvatar)];
			me.photos[fileId] = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
			[me.tableView reloadData];
		}];
	}
}

static NSString *TGContactName(NSDictionary *u) {
	NSString *first = u[@"first_name"] ?: @"";
	NSString *last  = u[@"last_name"] ?: @"";
	NSString *name  = [[NSString stringWithFormat:@"%@ %@", first, last]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (name.length)
		return name;
	if ([u[@"username"] length])
		return [NSString stringWithFormat:@"@%@", u[@"username"]];
	return u[@"phone"] ?: @"";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.users.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGContactCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	NSDictionary *u = self.users[indexPath.row];
	NSString *name = TGContactName(u);
	cell.textLabel.text = name;
	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.text = [u[@"phone"] length]
		? [NSString stringWithFormat:@"+%@", u[@"phone"]] : @"";
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.backgroundColor = [[TGTheme shared] listBackgroundColour];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	// The real picture when it has arrived, and Telegram's own initials avatar
	// - same palette, same id-to-colour mapping - until then.
	NSNumber *fileId = u[@"photoFileId"];
	UIImage *photo = [fileId isKindOfClass:NSNumber.class] ? self.photos[fileId] : nil;
	if (!photo)
		photo = [TGIcons avatarWithInitials:
					(name.length ? [name substringToIndex:1].uppercaseString : @"?")
									   size:kContactAvatar
								   colourId:[u[@"id"] longLongValue]];
	cell.imageView.image = photo;
	cell.imageView.layer.cornerRadius = kContactAvatar / 2;
	cell.imageView.clipsToBounds = YES;
	cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSDictionary *u = self.users[indexPath.row];
	NSString *name = TGContactName(u);
	__weak typeof(self) weakSelf = self;

	[[TGClient shared] privateChatWithUser:[u[@"id"] longLongValue]
								completion:^(int64_t chatId){
		TGContactsViewController *me = weakSelf;
		if (!me || chatId == 0)
			return;
		TGChatViewController *vc = [[TGChatViewController alloc] init];
		vc.chatId = chatId;
		vc.chatTitle = name;
		vc.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:vc animated:YES];
	}];
}

@end

// vim:ft=objc

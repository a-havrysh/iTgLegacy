#import "TGChatListViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGContactsViewController.h"
#import "TGTopicsViewController.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kRowHeight = 68.0f;
static const CGFloat kAvatar    = 52.0f;

#pragma mark - cell

@interface TGChatCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *badge;
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
	self.dateLabel.font = [UIFont systemFontOfSize:13];
	self.dateLabel.textColor = [UIColor colorWithWhite:0.55f alpha:1.0f];
	self.dateLabel.textAlignment = NSTextAlignmentRight;
	[self.contentView addSubview:self.dateLabel];

	self.badge = [[UILabel alloc] init];
	self.badge.font = [UIFont boldSystemFontOfSize:13];
	self.badge.textColor = [UIColor whiteColor];
	self.badge.backgroundColor = [[TGTheme shared] accentColour];
	self.badge.textAlignment = NSTextAlignmentCenter;
	self.badge.layer.cornerRadius = 10;
	self.badge.clipsToBounds = YES;
	self.badge.hidden = YES;
	[self.contentView addSubview:self.badge];

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

	if (!self.badge.hidden){
		CGSize s = [self.badge.text sizeWithFont:self.badge.font];
		CGFloat bw = MAX(20, s.width + 12);
		self.badge.frame = CGRectMake(w - right + 30, 36, bw, 20);
	}
}

@end

#pragma mark - controller

@interface TGChatListViewController ()
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, strong) NSMutableDictionary *avatars;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@end

@implementation TGChatListViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = @"Chats";
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

	self.tableView.rowHeight = kRowHeight;
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	__weak typeof(self) weakSelf = self;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	// Restyle in place when the setting changes, rather than needing a restart.
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		usingBlock:^(NSNotification *note){
		[TGIcons flush];
		[[TGTheme shared] styleNavigationBar:weakSelf.navigationController.navigationBar];
		[weakSelf.tableView reloadData];
	}];

	[TGClient shared].onChatsChanged = ^{
		[weakSelf reload];
	};
	[TGClient shared].onConnectionState = ^(TGConnectionState state, NSString *text){
		// Clients put this in the title bar rather than hiding it in a flag.
		weakSelf.title = text ?: @"Chats";
	};
	[self reload];
}

- (void)composeTapped {
	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	contacts.title = @"New Message";
	[self.navigationController pushViewController:contacts animated:YES];
}

- (void)reload {
	self.chats = [TGClient shared].chats;
	[self.tableView reloadData];
	[self fetchMissingAvatars];
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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.chats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGChatCell";
	TGChatCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];

	NSDictionary *c = self.chats[indexPath.row];
	cell.titleLabel.text = c[@"title"];
	cell.previewLabel.text = c[@"text"];
	cell.dateLabel.text = TGChatDate([c[@"date"] doubleValue]);

	NSInteger unread = [c[@"unread"] integerValue];
	cell.badge.hidden = (unread <= 0);
	cell.badge.text = unread > 0 ? [NSString stringWithFormat:@"%ld", (long)unread] : @"";

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

	NSDictionary *c = self.chats[indexPath.row];
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

#import "TGStoriesViewController.h"

#import "TGClient.h"
#import "TGClient+Stories.h"
#import "TGClient+Files.h"
#import "TGActionSheet.h"
#import "TGAlertView.h"
#import "TGTheme.h"
#import "TGDateUtils.h"
#import "TGImageDecode.h"
#import "TGReactionPickerView.h"

static const CGFloat TGStoryStripHeight = 3.0f;
static const CGFloat TGStoryStripInset = 4.0f;
static const CGFloat TGStoryStripGap = 2.0f;
static const CGFloat TGStoryStatusBarHeight = 20.0f;
static const CGFloat TGStoryPanelHeight = 45.0f;
static const CGFloat TGStoryPanelButtonSize = 40.0f;
static const CGFloat TGStoryPanelButtonInset = 6.0f;
static const CGFloat TGStoryPanelButtonTop = 2.0f;
static const CGFloat TGStoryPlateHeight = 30.0f;
static const CGFloat TGStoryPlateTop = 7.0f;
static const CGFloat TGStoryPlateLeft = 5.0f;
static const CGFloat TGStoryFooterHeight = 30.0f;
static const CGFloat TGStoryFooterInset = 10.0f;
static const CGFloat TGStoryFooterBottom = 10.0f;
static const CGFloat TGStoryCaptionHeight = 50.0f;
static const NSInteger TGStoryPhotoPixels = 640;
static const CGFloat TGStoryPageGap = 16.0f;
static const CGFloat TGStoryOverscroll = 48.0f;
static const CGFloat TGStoryDismissDistance = 100.0f;
static const CGFloat TGStoryDismissVelocity = 700.0f;
static const NSTimeInterval TGStoryDuration = 5.0;
static const NSTimeInterval TGStoryTick = 0.0667;
static const NSUInteger TGStoryPageQueueLimit = 2;

static UIImage *TGStoryStretch(NSString *name, NSInteger leftCap)
{
	UIImage *image = [UIImage imageNamed:name];
	if (image == nil)
		return nil;
	return [image stretchableImageWithLeftCapWidth:leftCap topCapHeight:0];
}

static NSString *TGStoryAgeText(int date)
{
	if (date <= 0)
		return @"";
	return [TGDateUtils stringForRelativeLastSeen:date];
}

static NSString *TGStoryString(NSDictionary *story, NSString *key)
{
	id value = [story objectForKey:key];
	return [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
}

static NSInteger TGStoryNumber(NSDictionary *story, NSString *key)
{
	id value = [story objectForKey:key];
	return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

static int64_t TGStoryChatId(NSDictionary *story, NSString *key)
{
	id value = [story objectForKey:key];
	return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0;
}

static BOOL TGStoryFlag(NSDictionary *story, NSString *key)
{
	id value = [story objectForKey:key];
	return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

static NSDictionary *TGStoryPosterEntry(int64_t chatId, NSString *title, NSDictionary *active)
{
	NSArray *stories = [active objectForKey:@"stories"];
	if (![stories isKindOfClass:[NSArray class]] || stories.count == 0 ||
		TGStoryFlag(active, @"archived"))
	{
		return nil;
	}

	NSMutableArray *ids = [[NSMutableArray alloc] init];
	for (NSDictionary *story in stories)
	{
		if ([story isKindOfClass:[NSDictionary class]])
			[ids addObject:[NSNumber numberWithInteger:TGStoryNumber(story, @"id")]];
	}
	if (ids.count == 0)
		return nil;

	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithLongLong:chatId], @"chatId",
			title, @"title",
			ids, @"ids",
			([active objectForKey:@"order"] ?: [NSNumber numberWithInt:0]), @"order",
			nil];
}

@interface TGStoryTextViewController : UIViewController
@property (nonatomic, strong) NSString *text;
@end

@implementation TGStoryTextViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];
	UITextView *view = [[UITextView alloc] initWithFrame:self.view.bounds];
	view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	view.editable = NO;
	view.backgroundColor = [UIColor clearColor];
	view.textColor = [[TGTheme shared] primaryTextColour];
	view.font = [UIFont systemFontOfSize:15];
	view.text = self.text ?: @"";
	[self.view addSubview:view];
}

@end

@interface TGStoryContactPicker : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) void (^onPicked)(NSArray *userIds);
@property (nonatomic, copy) NSArray *preselected;
+ (void)presentFrom:(UIViewController *)host
			  title:(NSString *)title
		 preselected:(NSArray *)preselected
			  picked:(void (^)(NSArray *userIds))picked;
@end

@implementation TGStoryContactPicker
{
	UITableView *_tableView;
	NSArray *_contacts;
	NSMutableSet *_selected;
}

+ (void)presentFrom:(UIViewController *)host
			  title:(NSString *)title
		 preselected:(NSArray *)preselected
			  picked:(void (^)(NSArray *userIds))picked
{
	if (host == nil)
		return;
	TGStoryContactPicker *picker = [[TGStoryContactPicker alloc] init];
	picker.title = title.length > 0 ? title : @"Select Contacts";
	picker.preselected = preselected;
	picker.onPicked = picked;
	UINavigationController *navigation =
			[[UINavigationController alloc] initWithRootViewController:picker];
	[host presentViewController:navigation animated:YES completion:nil];
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	_selected = [[NSMutableSet alloc] init];
	for (id value in self.preselected)
	{
		if ([value respondsToSelector:@selector(longLongValue)])
			[_selected addObject:[NSNumber numberWithLongLong:[value longLongValue]]];
	}

	self.navigationItem.leftBarButtonItem =
			[[UIBarButtonItem alloc] initWithTitle:@"Cancel"
											 style:UIBarButtonItemStyleBordered
											target:self
											action:@selector(cancelPressed)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithTitle:@"Done"
											 style:UIBarButtonItemStyleDone
											target:self
											action:@selector(donePressed)];

	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	_tableView.rowHeight = 44.0f;
	_tableView.separatorColor = [[TGTheme shared] separatorColour];
	_tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[self.view addSubview:_tableView];

	__weak TGStoryContactPicker *weakSelf = self;
	[[TGClient shared] contactsWithCompletion:^(NSArray *users)
	{
		TGStoryContactPicker *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_contacts = [users isKindOfClass:[NSArray class]] ? [users copy] : nil;
		[strongSelf->_tableView reloadData];
	}];
}

- (void)cancelPressed
{
	void (^picked)(NSArray *) = self.onPicked;
	self.onPicked = nil;
	[self dismissViewControllerAnimated:YES completion:^
	{
		if (picked != nil)
			picked(nil);
	}];
}

- (void)donePressed
{
	void (^picked)(NSArray *) = self.onPicked;
	self.onPicked = nil;
	NSArray *ids = [_selected allObjects];
	[self dismissViewControllerAnimated:YES completion:^
	{
		if (picked != nil)
			picked(ids);
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	(void)tableView;
	(void)section;
	return (NSInteger)_contacts.count;
}

- (NSString *)nameForContact:(NSDictionary *)contact
{
	NSString *first = TGStoryString(contact, @"first_name");
	NSString *last = TGStoryString(contact, @"last_name");
	if (first.length > 0 && last.length > 0)
		return [NSString stringWithFormat:@"%@ %@", first, last];
	if (first.length > 0)
		return first;
	if (last.length > 0)
		return last;
	NSString *username = TGStoryString(contact, @"username");
	return username.length > 0 ? username : @"Contact";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"contact"];
	if (cell == nil)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"contact"];
	NSDictionary *contact = [_contacts objectAtIndex:(NSUInteger)indexPath.row];
	cell.textLabel.text = [self nameForContact:contact];
	NSNumber *identifier = [NSNumber numberWithLongLong:TGStoryChatId(contact, @"id")];
	cell.accessoryType = [_selected containsObject:identifier]
			? UITableViewCellAccessoryCheckmark
			: UITableViewCellAccessoryNone;
	[[TGTheme shared] styleCell:cell];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)_contacts.count)
		return;
	NSDictionary *contact = [_contacts objectAtIndex:(NSUInteger)indexPath.row];
	NSNumber *identifier = [NSNumber numberWithLongLong:TGStoryChatId(contact, @"id")];
	if ([_selected containsObject:identifier])
		[_selected removeObject:identifier];
	else
		[_selected addObject:identifier];
	[tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
					 withRowAnimation:UITableViewRowAnimationNone];
}

@end

@interface TGStoryViewersViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) NSInteger storyId;
@property (nonatomic, assign) int64_t chatId;
@end

@implementation TGStoryViewersViewController
{
	UITableView *_tableView;
	NSMutableArray *_rows;
	NSString *_nextOffset;
	BOOL _loading;
	BOOL _exhausted;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = @"Viewers";
	_rows = [[NSMutableArray alloc] init];
	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	_tableView.rowHeight = 44.0f;
	_tableView.separatorColor = [[TGTheme shared] separatorColour];
	_tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[self.view addSubview:_tableView];
	[self loadMore];
}

- (void)loadMore
{
	if (_loading || _exhausted)
		return;
	_loading = YES;
	__weak TGStoryViewersViewController *weakSelf = self;
	void (^handler)(NSArray *, NSString *, NSInteger) = ^(NSArray *viewers, NSString *nextOffset, NSInteger total)
	{
		(void)total;
		TGStoryViewersViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_loading = NO;
		if ([viewers isKindOfClass:[NSArray class]])
			[strongSelf->_rows addObjectsFromArray:viewers];
		strongSelf->_nextOffset = nextOffset;
		strongSelf->_exhausted = (nextOffset.length == 0);
		[strongSelf->_tableView reloadData];
	};

	if (_chatId != 0 && [[TGClient shared] me] != nil &&
		_chatId != TGStoryChatId([[TGClient shared] me], @"id"))
	{
		[[TGClient shared] viewersOfStory:_storyId
								   inChat:_chatId
								   offset:_nextOffset
									limit:50
							   completion:handler];
	}
	else
	{
		[[TGClient shared] viewersOfStory:_storyId
								   offset:_nextOffset
									limit:50
							   completion:handler];
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	(void)tableView;
	(void)section;
	return (NSInteger)_rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"viewer"];
	if (cell == nil)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"viewer"];
	NSDictionary *row = [_rows objectAtIndex:(NSUInteger)indexPath.row];
	NSString *name = TGStoryString(row, @"name");
	NSString *emoji = TGStoryString(row, @"emoji");
	cell.textLabel.text = emoji.length > 0
			? [NSString stringWithFormat:@"%@  %@", name, emoji]
			: name;
	cell.detailTextLabel.text = TGStoryAgeText((int)TGStoryNumber(row, @"date"));
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	[[TGTheme shared] styleCell:cell];

	if (indexPath.row + 5 >= (NSInteger)_rows.count)
		[self loadMore];
	return cell;
}

@end

typedef enum
{
	TGStoryListMenu = 0,
	TGStoryListArchive,
	TGStoryListProfile,
	TGStoryListAlbums,
	TGStoryListAlbum,
	TGStoryListForwards,
	TGStoryListTag,
	TGStoryListSettings,
	TGStoryListHidden,
	TGStoryListExceptions
} TGStoryListMode;

@interface TGStoryListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, assign) TGStoryListMode mode;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) NSInteger storyId;
@property (nonatomic, assign) NSInteger albumId;
@property (nonatomic, copy) NSString *tag;

+ (void)pushMode:(TGStoryListMode)mode
		  chatId:(int64_t)chatId
		   title:(NSString *)title
			from:(UIViewController *)host;

@end

@implementation TGStoryListViewController
{
	UITableView *_tableView;
	NSMutableArray *_rows;
	NSMutableArray *_pinned;
	NSString *_nextOffset;
	NSInteger _fromStoryId;
	BOOL _loading;
	BOOL _exhausted;
	NSInteger _archiveTotal;
	NSInteger _profileTotal;
	NSInteger _albumCount;
	NSInteger _closeFriendsCount;
	NSInteger _hiddenCount;
	NSInteger _exceptionCount;
}

+ (void)pushMode:(TGStoryListMode)mode
		  chatId:(int64_t)chatId
		   title:(NSString *)title
			from:(UIViewController *)host
{
	if (host.navigationController == nil)
		return;
	TGStoryListViewController *list = [[TGStoryListViewController alloc] init];
	list.mode = mode;
	list.chatId = chatId;
	list.title = title;
	[host.navigationController pushViewController:list animated:YES];
}

- (BOOL)isGrouped
{
	return self.mode == TGStoryListMenu || self.mode == TGStoryListSettings;
}

- (BOOL)isStoryList
{
	return self.mode == TGStoryListArchive || self.mode == TGStoryListProfile ||
			self.mode == TGStoryListAlbum || self.mode == TGStoryListTag;
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	_rows = [[NSMutableArray alloc] init];
	_pinned = [[NSMutableArray alloc] init];

	UITableViewStyle style = [self isGrouped]
			? UITableViewStyleGrouped
			: UITableViewStylePlain;
	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:style];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	_tableView.rowHeight = 44.0f;
	_tableView.separatorColor = [[TGTheme shared] separatorColour];
	_tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[self.view addSubview:_tableView];

	if ([self isStoryList] || self.mode == TGStoryListAlbums)
	{
		UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
				initWithTarget:self action:@selector(rowHeld:)];
		hold.minimumPressDuration = 0.5;
		[_tableView addGestureRecognizer:hold];
	}

	if (self.mode == TGStoryListAlbums)
	{
		self.navigationItem.rightBarButtonItem =
				[[UIBarButtonItem alloc] initWithTitle:@"New"
												 style:UIBarButtonItemStyleBordered
												target:self
												action:@selector(createAlbumPressed)];
	}

	[self reload];
}

- (void)reload
{
	[_rows removeAllObjects];
	[_pinned removeAllObjects];
	_nextOffset = nil;
	_fromStoryId = 0;
	_loading = NO;
	_exhausted = NO;
	[_tableView reloadData];
	[self loadMore];
}

- (void)showMessage:(NSString *)message
{
	[[[TGAlertView alloc] initWithTitle:nil
								message:message
					  cancelButtonTitle:@"OK"
						  okButtonTitle:nil
						completionBlock:nil] show];
}

#pragma mark - loading

- (void)loadMenuCounts
{
	__weak TGStoryListViewController *weakSelf = self;
	_exhausted = YES;
	_loading = NO;
	int64_t chatId = self.chatId;
	[[TGClient shared] archivedStoriesInChat:chatId
								 fromStoryId:0
									   limit:1
								  completion:^(NSArray *stories, NSInteger total)
	{
		(void)stories;
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_archiveTotal = total;
		[strongSelf->_tableView reloadData];
	}];
	[[TGClient shared] profileStoriesInChat:chatId
								fromStoryId:0
									  limit:1
								 completion:^(NSArray *stories, NSArray *pinnedIds, NSInteger total)
	{
		(void)stories;
		(void)pinnedIds;
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_profileTotal = total;
		[strongSelf->_tableView reloadData];
	}];
	[[TGClient shared] storyAlbumsInChat:chatId completion:^(NSArray *albums)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_albumCount = (NSInteger)albums.count;
		[strongSelf->_tableView reloadData];
	}];
}

- (void)loadSettingsCounts
{
	__weak TGStoryListViewController *weakSelf = self;
	_exhausted = YES;
	_loading = NO;
	[[TGClient shared] closeFriendsWithCompletion:^(NSArray *users)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_closeFriendsCount = (NSInteger)users.count;
		[strongSelf->_tableView reloadData];
	}];
	[[TGClient shared] hiddenStoryPostersWithCompletion:^(NSArray *users)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_hiddenCount = (NSInteger)users.count;
		[strongSelf->_tableView reloadData];
	}];
	[[TGClient shared] storyNotificationExceptionsWithCompletion:^(NSArray *chats)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_exceptionCount = (NSInteger)chats.count;
		[strongSelf->_tableView reloadData];
	}];
}

- (void (^)(NSArray *stories, BOOL more))appendStoriesHandler
{
	__weak TGStoryListViewController *weakSelf = self;
	return ^(NSArray *stories, BOOL more)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_loading = NO;
		if ([stories isKindOfClass:[NSArray class]] && stories.count > 0)
		{
			[strongSelf->_rows addObjectsFromArray:stories];
			NSDictionary *last = [stories objectAtIndex:stories.count - 1];
			strongSelf->_fromStoryId = TGStoryNumber(last, @"id");
		}
		else
		{
			more = NO;
		}
		strongSelf->_exhausted = !more;
		[strongSelf->_tableView reloadData];
	};
}

- (void)loadMore
{
	if (_loading || _exhausted)
		return;
	_loading = YES;

	if (self.mode == TGStoryListMenu)
	{
		[self loadMenuCounts];
		return;
	}

	if (self.mode == TGStoryListSettings)
	{
		[self loadSettingsCounts];
		return;
	}

	void (^appendStories)(NSArray *, BOOL) = [self appendStoriesHandler];

	if (self.mode == TGStoryListArchive)
	{
		[self loadArchivePageAppending:appendStories];
		return;
	}

	if (self.mode == TGStoryListProfile)
	{
		[self loadProfilePageAppending:appendStories];
		return;
	}

	if (self.mode == TGStoryListAlbum)
	{
		[self loadAlbumPageAppending:appendStories];
		return;
	}

	if (self.mode == TGStoryListTag)
	{
		[self loadTagPageAppending:appendStories];
		return;
	}

	if (self.mode == TGStoryListForwards)
	{
		[self loadForwardsPage];
		return;
	}

	if (self.mode == TGStoryListAlbums)
	{
		[self loadAlbumList];
		return;
	}

	if (self.mode == TGStoryListHidden)
	{
		[self loadHiddenPosters];
		return;
	}

	if (self.mode == TGStoryListExceptions)
	{
		[self loadNotificationExceptions];
		return;
	}

	_loading = NO;
	_exhausted = YES;
}

- (void)loadArchivePageAppending:(void (^)(NSArray *stories, BOOL more))appendStories
{
	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] archivedStoriesInChat:self.chatId
								 fromStoryId:_fromStoryId
									   limit:30
								  completion:^(NSArray *stories, NSInteger total)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		BOOL more = strongSelf != nil &&
				((NSInteger)strongSelf->_rows.count + (NSInteger)stories.count) < total;
		appendStories(stories, more);
	}];
}

- (void)loadProfilePageAppending:(void (^)(NSArray *stories, BOOL more))appendStories
{
	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] profileStoriesInChat:self.chatId
								fromStoryId:_fromStoryId
									  limit:30
								 completion:^(NSArray *stories, NSArray *pinnedIds, NSInteger total)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf != nil && [pinnedIds isKindOfClass:[NSArray class]])
		{
			[strongSelf->_pinned removeAllObjects];
			[strongSelf->_pinned addObjectsFromArray:pinnedIds];
		}
		BOOL more = strongSelf != nil &&
				((NSInteger)strongSelf->_rows.count + (NSInteger)stories.count) < total;
		appendStories(stories, more);
	}];
}

- (void)loadAlbumPageAppending:(void (^)(NSArray *stories, BOOL more))appendStories
{
	__weak TGStoryListViewController *weakSelf = self;
	NSInteger offset = (NSInteger)_rows.count;
	[[TGClient shared] storiesInAlbum:self.albumId
							   inChat:self.chatId
							   offset:offset
								limit:30
						   completion:^(NSArray *stories, NSInteger total)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		BOOL more = strongSelf != nil &&
				((NSInteger)strongSelf->_rows.count + (NSInteger)stories.count) < total;
		appendStories(stories, more);
	}];
}

- (void)loadTagPageAppending:(void (^)(NSArray *stories, BOOL more))appendStories
{
	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] searchStoriesWithTag:(self.tag ?: @"")
							   posterChatId:0
									 offset:_nextOffset
									  limit:20
								 completion:^(NSArray *stories, NSString *nextOffset, NSInteger total)
	{
		(void)total;
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_nextOffset = nextOffset;
		appendStories(stories, nextOffset.length > 0);
	}];
}

- (void)loadForwardsPage
{
	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] publicForwardsOfStory:self.storyId
									  inChat:self.chatId
									  offset:_nextOffset
									   limit:20
								  completion:^(NSArray *forwards, NSString *nextOffset)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_loading = NO;
		strongSelf->_nextOffset = nextOffset;
		if ([forwards isKindOfClass:[NSArray class]])
			[strongSelf->_rows addObjectsFromArray:forwards];
		strongSelf->_exhausted = (nextOffset.length == 0 || forwards.count == 0);
		[strongSelf->_tableView reloadData];
	}];
}

- (void)loadAlbumList
{
	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] storyAlbumsInChat:self.chatId completion:^(NSArray *albums)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_loading = NO;
		strongSelf->_exhausted = YES;
		if ([albums isKindOfClass:[NSArray class]])
			[strongSelf->_rows addObjectsFromArray:albums];
		[strongSelf->_tableView reloadData];
	}];
}

- (void)loadHiddenPosters
{
	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] hiddenStoryPostersWithCompletion:^(NSArray *users)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_loading = NO;
		strongSelf->_exhausted = YES;
		if ([users isKindOfClass:[NSArray class]])
			[strongSelf->_rows addObjectsFromArray:users];
		[strongSelf->_tableView reloadData];
	}];
}

- (void)loadNotificationExceptions
{
	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] storyNotificationExceptionsWithCompletion:^(NSArray *chats)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf->_loading = NO;
		strongSelf->_exhausted = YES;
		if ([chats isKindOfClass:[NSArray class]])
			[strongSelf->_rows addObjectsFromArray:chats];
		[strongSelf->_tableView reloadData];
	}];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	(void)tableView;
	if (self.mode == TGStoryListMenu)
		return 2;
	if (self.mode == TGStoryListSettings)
		return 3;
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	(void)tableView;
	if (self.mode == TGStoryListMenu)
		return section == 0 ? 3 : 1;
	if (self.mode == TGStoryListSettings)
		return 2;
	return (NSInteger)_rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	(void)tableView;
	if (self.mode != TGStoryListSettings)
		return nil;
	if (section == 0)
		return @"Story Notifications";
	if (section == 1)
		return @"Preload Stories";
	return @"Privacy";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	(void)tableView;
	if (self.mode == TGStoryListSettings && section == 1)
		return @"Fetching stories ahead of time uses more memory and data.";
	return nil;
}

- (NSString *)reactionSource
{
	NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:@"TGStoryReactionSource"];
	return value.length > 0 ? value : @"all";
}

- (NSString *)reactionSourceTitle
{
	NSString *source = [self reactionSource];
	if ([source isEqualToString:@"contacts"])
		return @"My Contacts";
	if ([source isEqualToString:@"none"])
		return @"Nobody";
	return @"Everybody";
}

- (BOOL)preloadOnNetwork:(NSString *)type
{
	NSString *key = [@"TGStoryPreload_" stringByAppendingString:type];
	return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

- (NSString *)storySummary:(NSDictionary *)story
{
	NSString *caption = TGStoryString(story, @"caption");
	if (caption.length > 0)
		return caption;
	NSString *kind = TGStoryString(story, @"kind");
	if ([kind isEqualToString:@"video"])
		return @"Video";
	if ([kind isEqualToString:@"live"])
		return @"Live";
	return @"Photo";
}

- (UITableViewCell *)menuCellIn:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"menu"];
	if (cell == nil)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"menu"];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.accessoryView = nil;
	cell.detailTextLabel.text = @"";

	if (indexPath.section == 1)
	{
		cell.textLabel.text = @"Story Settings";
		[[TGTheme shared] styleCell:cell];
		return cell;
	}

	if (indexPath.row == 0)
	{
		cell.textLabel.text = @"Archive";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)_archiveTotal];
	}
	else if (indexPath.row == 1)
	{
		cell.textLabel.text = @"On Profile";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)_profileTotal];
	}
	else
	{
		cell.textLabel.text = @"Albums";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)_albumCount];
	}
	[[TGTheme shared] styleCell:cell];
	return cell;
}

- (UITableViewCell *)settingsCellIn:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"setting"];
	if (cell == nil)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"setting"];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.detailTextLabel.text = @"";
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;

	if (indexPath.section == 0)
	{
		if (indexPath.row == 0)
		{
			cell.textLabel.text = @"Reactions";
			cell.detailTextLabel.text = [self reactionSourceTitle];
		}
		else
		{
			cell.textLabel.text = @"Exceptions";
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)_exceptionCount];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
	}
	else if (indexPath.section == 1)
	{
		NSString *type = indexPath.row == 0 ? @"mobile" : @"wifi";
		cell.textLabel.text = indexPath.row == 0 ? @"Mobile Data" : @"Wi-Fi";
		UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
		toggle.tag = indexPath.row == 0 ? 1 : 2;
		toggle.on = [self preloadOnNetwork:type];
		[toggle addTarget:self
				   action:@selector(preloadToggled:)
		 forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	else
	{
		if (indexPath.row == 0)
		{
			cell.textLabel.text = @"Close Friends";
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)_closeFriendsCount];
		}
		else
		{
			cell.textLabel.text = @"Hidden Posters";
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)_hiddenCount];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
	}

	[[TGTheme shared] styleCell:cell];
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (self.mode == TGStoryListMenu)
		return [self menuCellIn:tableView indexPath:indexPath];
	if (self.mode == TGStoryListSettings)
		return [self settingsCellIn:tableView indexPath:indexPath];

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (cell == nil)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	cell.accessoryType = UITableViewCellAccessoryNone;

	if (indexPath.row >= (NSInteger)_rows.count)
		return cell;
	NSDictionary *row = [_rows objectAtIndex:(NSUInteger)indexPath.row];

	if (self.mode == TGStoryListAlbums)
	{
		cell.textLabel.text = TGStoryString(row, @"name");
		cell.detailTextLabel.text = @"";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	else if (self.mode == TGStoryListHidden || self.mode == TGStoryListExceptions)
	{
		NSString *name = TGStoryString(row, @"name");
		if (name.length == 0)
			name = TGStoryString(row, @"title");
		cell.textLabel.text = name;
		cell.detailTextLabel.text = @"";
	}
	else if (self.mode == TGStoryListForwards)
	{
		cell.textLabel.text = TGStoryString(row, @"title");
		cell.detailTextLabel.text = TGStoryAgeText((int)TGStoryNumber(row, @"date"));
		if (TGStoryFlag(row, @"isStory"))
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	else
	{
		cell.textLabel.text = [self storySummary:row];
		NSString *age = TGStoryAgeText((int)TGStoryNumber(row, @"date"));
		BOOL isPinned = [_pinned containsObject:[NSNumber numberWithInteger:TGStoryNumber(row, @"id")]];
		cell.detailTextLabel.text = isPinned
				? [NSString stringWithFormat:@"Pinned · %@", age]
				: age;
	}

	[[TGTheme shared] styleCell:cell];

	if (indexPath.row + 5 >= (NSInteger)_rows.count)
		[self loadMore];
	return cell;
}

#pragma mark - selection

- (void)selectMenuRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.section == 1)
	{
		[TGStoryListViewController pushMode:TGStoryListSettings
									 chatId:self.chatId
									  title:@"Story Settings"
									   from:self];
		return;
	}
	if (indexPath.row == 0)
		[TGStoryListViewController pushMode:TGStoryListArchive
									 chatId:self.chatId
									  title:@"Archive"
									   from:self];
	else if (indexPath.row == 1)
		[TGStoryListViewController pushMode:TGStoryListProfile
									 chatId:self.chatId
									  title:@"On Profile"
									   from:self];
	else
		[TGStoryListViewController pushMode:TGStoryListAlbums
									 chatId:self.chatId
									  title:@"Albums"
									   from:self];
}

- (void)selectSettingsRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.section == 0 && indexPath.row == 0)
	{
		[self askReactionSource];
		return;
	}
	if (indexPath.section == 0 && indexPath.row == 1)
	{
		[TGStoryListViewController pushMode:TGStoryListExceptions
									 chatId:self.chatId
									  title:@"Exceptions"
									   from:self];
		return;
	}
	if (indexPath.section == 2 && indexPath.row == 0)
	{
		[self editCloseFriends];
		return;
	}
	if (indexPath.section == 2 && indexPath.row == 1)
	{
		[TGStoryListViewController pushMode:TGStoryListHidden
									 chatId:self.chatId
									  title:@"Hidden Posters"
									   from:self];
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (self.mode == TGStoryListMenu)
	{
		[self selectMenuRowAtIndexPath:indexPath];
		return;
	}

	if (self.mode == TGStoryListSettings)
	{
		[self selectSettingsRowAtIndexPath:indexPath];
		return;
	}

	if (indexPath.row >= (NSInteger)_rows.count)
		return;
	NSDictionary *row = [_rows objectAtIndex:(NSUInteger)indexPath.row];

	if (self.mode == TGStoryListAlbums)
	{
		TGStoryListViewController *list = [[TGStoryListViewController alloc] init];
		list.mode = TGStoryListAlbum;
		list.chatId = self.chatId;
		list.albumId = TGStoryNumber(row, @"id");
		list.title = TGStoryString(row, @"name");
		[self.navigationController pushViewController:list animated:YES];
		return;
	}

	if (self.mode == TGStoryListHidden)
	{
		[self unhidePoster:row];
		return;
	}

	if (self.mode == TGStoryListExceptions)
	{
		[self askMutingForChat:row];
		return;
	}

	if (self.mode == TGStoryListForwards)
	{
		if (!TGStoryFlag(row, @"isStory"))
			return;
		[self openStory:TGStoryNumber(row, @"storyId")
				 inChat:TGStoryChatId(row, @"chatId")
				   name:TGStoryString(row, @"title")];
		return;
	}

	[self openStory:TGStoryNumber(row, @"id")
			 inChat:(TGStoryChatId(row, @"chatId") != 0 ? TGStoryChatId(row, @"chatId") : self.chatId)
			   name:self.title];
}

- (void)openStory:(NSInteger)storyId inChat:(int64_t)chatId name:(NSString *)name
{
	if (storyId == 0 || chatId == 0)
		return;
	NSArray *ids = [NSArray arrayWithObject:[NSNumber numberWithInteger:storyId]];
	TGStoriesViewController *viewer =
			[[TGStoriesViewController alloc] initWithChatId:chatId storyIds:ids startIndex:0];
	viewer.posterName = name;
	[self.navigationController pushViewController:viewer animated:YES];
}

#pragma mark - settings actions

- (void)preloadToggled:(UISwitch *)toggle
{
	NSString *type = (toggle.tag == 1) ? @"mobile" : @"wifi";
	[[TGClient shared] setStoryPreloading:toggle.on onNetwork:type];
	[[NSUserDefaults standardUserDefaults] setBool:toggle.on
											forKey:[@"TGStoryPreload_" stringByAppendingString:type]];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)askReactionSource
{
	NSArray *titles = [NSArray arrayWithObjects:@"Everybody", @"My Contacts", @"Nobody", nil];
	NSArray *values = [NSArray arrayWithObjects:@"all", @"contacts", @"none", nil];

	NSMutableArray *actions = [[NSMutableArray alloc] init];
	for (NSString *title in titles)
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:title action:title]];

	__weak TGStoryListViewController *weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:@"Reaction notifications from"
													   actions:actions
												   actionBlock:^(id target, NSString *action)
	{
		(void)target;
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		NSUInteger index = [titles indexOfObject:action];
		if (index == NSNotFound)
			return;
		NSString *source = [values objectAtIndex:index];
		[[TGClient shared] setStoryReactionNotificationSource:source];
		[[NSUserDefaults standardUserDefaults] setObject:source forKey:@"TGStoryReactionSource"];
		[[NSUserDefaults standardUserDefaults] synchronize];
		[strongSelf->_tableView reloadData];
	}
														target:self];
	[sheet showInView:self.view];
}

- (void)editCloseFriends
{
	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] closeFriendsWithCompletion:^(NSArray *users)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;

		NSMutableArray *current = [[NSMutableArray alloc] init];
		for (NSDictionary *user in users)
		{
			if ([user isKindOfClass:[NSDictionary class]])
				[current addObject:[NSNumber numberWithLongLong:TGStoryChatId(user, @"id")]];
		}

		[TGStoryContactPicker presentFrom:strongSelf
									title:@"Close Friends"
							  preselected:current
								   picked:^(NSArray *userIds)
		{
			TGStoryListViewController *inner = weakSelf;
			if (inner == nil || userIds == nil)
				return;
			[[TGClient shared] setCloseFriends:userIds];
			inner->_closeFriendsCount = (NSInteger)userIds.count;
			[inner->_tableView reloadData];
		}];
	}];
}

- (void)unhidePoster:(NSDictionary *)user
{
	int64_t userId = TGStoryChatId(user, @"id");
	if (userId == 0)
		return;
	NSString *name = TGStoryString(user, @"name");
	__weak TGStoryListViewController *weakSelf = self;
	[[[TGAlertView alloc] initWithTitle:nil
								message:[NSString stringWithFormat:@"Show stories from %@?", name]
					  cancelButtonTitle:@"Cancel"
						  okButtonTitle:@"Show"
						completionBlock:^(bool okButtonPressed)
	{
		if (!okButtonPressed)
			return;
		[[TGClient shared] setUser:userId storiesHidden:NO];
		[weakSelf reload];
	}] show];
}

- (void)askMutingForChat:(NSDictionary *)chat
{
	int64_t chatId = TGStoryChatId(chat, @"id");
	if (chatId == 0)
		return;

	NSArray *actions = [NSArray arrayWithObjects:
			[[TGActionSheetAction alloc] initWithTitle:@"Mute Stories" action:@"mute"],
			[[TGActionSheetAction alloc] initWithTitle:@"Unmute Stories" action:@"unmute"], nil];

	__weak TGStoryListViewController *weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:TGStoryString(chat, @"title")
													   actions:actions
												   actionBlock:^(id target, NSString *action)
	{
		(void)target;
		[[TGClient shared] setChat:chatId storiesMuted:[action isEqualToString:@"mute"]];
		[weakSelf reload];
	}
														target:self];
	[sheet showInView:self.view];
}

#pragma mark - albums

- (void)createAlbumPressed
{
	__weak TGStoryListViewController *weakSelf = self;
	TGAlertView *alert = nil;
	__block __weak TGAlertView *weakAlert = nil;
	alert = [[TGAlertView alloc] initWithTitle:nil
									   message:@"Album name"
							 cancelButtonTitle:@"Cancel"
								 okButtonTitle:@"Create"
							   completionBlock:^(bool okButtonPressed)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil || !okButtonPressed)
			return;
		NSString *name = nil;
		if ([weakAlert respondsToSelector:@selector(textFieldAtIndex:)])
			name = [weakAlert textFieldAtIndex:0].text;
		if (name.length == 0)
			return;
		[[TGClient shared] createStoryAlbumInChat:strongSelf.chatId
											 name:name
										 storyIds:[NSArray array]
									   completion:^(NSDictionary *album)
		{
			TGStoryListViewController *inner = weakSelf;
			if (inner == nil)
				return;
			if (![album isKindOfClass:[NSDictionary class]])
			{
				[inner showMessage:@"Could not create the album"];
				return;
			}
			[inner reload];
		}];
	}];
	weakAlert = alert;
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	[alert show];
}

- (void)renameAlbum:(NSDictionary *)album
{
	NSInteger albumId = TGStoryNumber(album, @"id");
	__weak TGStoryListViewController *weakSelf = self;
	TGAlertView *alert = nil;
	__block __weak TGAlertView *weakAlert = nil;
	alert = [[TGAlertView alloc] initWithTitle:nil
									   message:@"Album name"
							 cancelButtonTitle:@"Cancel"
								 okButtonTitle:@"Save"
							   completionBlock:^(bool okButtonPressed)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil || !okButtonPressed)
			return;
		NSString *name = nil;
		if ([weakAlert respondsToSelector:@selector(textFieldAtIndex:)])
			name = [weakAlert textFieldAtIndex:0].text;
		if (name.length == 0)
			return;
		[[TGClient shared] renameStoryAlbum:albumId
									 inChat:strongSelf.chatId
									   name:name
								 completion:^(NSDictionary *updated)
		{
			TGStoryListViewController *inner = weakSelf;
			if (inner == nil)
				return;
			if (![updated isKindOfClass:[NSDictionary class]])
			{
				[inner showMessage:@"Could not rename the album"];
				return;
			}
			[inner reload];
		}];
	}];
	weakAlert = alert;
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
	{
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
		[alert textFieldAtIndex:0].text = TGStoryString(album, @"name");
	}
	[alert show];
}

- (void)deleteAlbum:(NSDictionary *)album
{
	NSInteger albumId = TGStoryNumber(album, @"id");
	int64_t chatId = self.chatId;
	__weak TGStoryListViewController *weakSelf = self;
	[[[TGAlertView alloc] initWithTitle:nil
								message:@"Delete this album?"
					  cancelButtonTitle:@"Cancel"
						  okButtonTitle:@"Delete"
						completionBlock:^(bool okButtonPressed)
	{
		if (!okButtonPressed)
			return;
		[[TGClient shared] deleteStoryAlbum:albumId inChat:chatId];
		[weakSelf reload];
	}] show];
}

- (void)moveAlbumUp:(NSUInteger)index
{
	if (index == 0 || index >= _rows.count)
		return;
	NSMutableArray *ordered = [_rows mutableCopy];
	id album = [ordered objectAtIndex:index];
	[ordered removeObjectAtIndex:index];
	[ordered insertObject:album atIndex:index - 1];

	NSMutableArray *ids = [[NSMutableArray alloc] init];
	for (NSDictionary *entry in ordered)
		[ids addObject:[NSNumber numberWithInteger:TGStoryNumber(entry, @"id")]];

	[[TGClient shared] reorderStoryAlbums:ids inChat:self.chatId];
	[_rows removeAllObjects];
	[_rows addObjectsFromArray:ordered];
	[_tableView reloadData];
}

- (void)moveStoryUp:(NSUInteger)index
{
	if (index == 0 || index >= _rows.count)
		return;
	NSMutableArray *ordered = [_rows mutableCopy];
	id story = [ordered objectAtIndex:index];
	[ordered removeObjectAtIndex:index];
	[ordered insertObject:story atIndex:index - 1];

	NSMutableArray *ids = [[NSMutableArray alloc] init];
	for (NSDictionary *entry in ordered)
		[ids addObject:[NSNumber numberWithInteger:TGStoryNumber(entry, @"id")]];

	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] reorderStories:ids
							  inAlbum:self.albumId
							   inChat:self.chatId
						   completion:^(NSDictionary *album)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		if (![album isKindOfClass:[NSDictionary class]])
		{
			[strongSelf showMessage:@"Could not reorder the album"];
			[strongSelf reload];
			return;
		}
		[strongSelf->_rows removeAllObjects];
		[strongSelf->_rows addObjectsFromArray:ordered];
		[strongSelf->_tableView reloadData];
	}];
}

- (void)addStoryToAlbum:(NSInteger)storyId
{
	int64_t chatId = self.chatId;
	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] storyAlbumsInChat:chatId completion:^(NSArray *albums)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		if (![albums isKindOfClass:[NSArray class]] || albums.count == 0)
		{
			[strongSelf showMessage:@"No albums yet"];
			return;
		}

		[strongSelf presentAlbumChooser:albums forStoryId:storyId inChat:chatId];
	}];
}

- (void)presentAlbumChooser:(NSArray *)albums
				 forStoryId:(NSInteger)storyId
					 inChat:(int64_t)chatId
{
	NSMutableArray *actions = [[NSMutableArray alloc] init];
	NSMutableDictionary *byTitle = [[NSMutableDictionary alloc] init];
	for (NSDictionary *album in albums)
	{
		if (![album isKindOfClass:[NSDictionary class]])
			continue;
		NSString *name = TGStoryString(album, @"name");
		if (name.length == 0)
			continue;
		[byTitle setObject:[NSNumber numberWithInteger:TGStoryNumber(album, @"id")] forKey:name];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:name action:name]];
	}
	if (actions.count == 0)
	{
		[self showMessage:@"No albums yet"];
		return;
	}

	__weak TGStoryListViewController *weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:@"Add to album"
													   actions:actions
												   actionBlock:^(id target, NSString *action)
	{
		(void)target;
		TGStoryListViewController *inner = weakSelf;
		if (inner == nil)
			return;
		NSNumber *albumId = [byTitle objectForKey:action];
		if (albumId == nil)
			return;
		[[TGClient shared] addStories:[NSArray arrayWithObject:
										[NSNumber numberWithInteger:storyId]]
							  toAlbum:[albumId integerValue]
							   inChat:chatId
						   completion:^(NSDictionary *album)
		{
			TGStoryListViewController *host = weakSelf;
			if (host == nil)
				return;
			[host showMessage:[album isKindOfClass:[NSDictionary class]]
					? @"Added to the album"
					: @"Could not add to the album"];
		}];
	}
														target:self];
	[sheet showInView:self.view];
}

- (void)removeStoryFromAlbum:(NSInteger)storyId
{
	__weak TGStoryListViewController *weakSelf = self;
	[[TGClient shared] removeStories:[NSArray arrayWithObject:[NSNumber numberWithInteger:storyId]]
						   fromAlbum:self.albumId
							  inChat:self.chatId
						  completion:^(NSDictionary *album)
	{
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		if (![album isKindOfClass:[NSDictionary class]])
		{
			[strongSelf showMessage:@"Could not remove the story"];
			return;
		}
		[strongSelf reload];
	}];
}

- (void)togglePinnedForStory:(NSInteger)storyId
{
	NSNumber *key = [NSNumber numberWithInteger:storyId];
	NSMutableArray *ids = [_pinned mutableCopy];
	if ([ids containsObject:key])
		[ids removeObject:key];
	else
		[ids insertObject:key atIndex:0];

	[[TGClient shared] setPinnedStories:ids inChat:self.chatId];
	[_pinned removeAllObjects];
	[_pinned addObjectsFromArray:ids];
	[_tableView reloadData];
}

#pragma mark - long press

- (NSMutableArray *)heldRowActionsForStoryId:(NSInteger)storyId
{
	NSMutableArray *actions = [[NSMutableArray alloc] init];

	if (self.mode == TGStoryListProfile)
	{
		BOOL isPinned = [_pinned containsObject:[NSNumber numberWithInteger:storyId]];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:(isPinned ? @"Unpin" : @"Pin to Top")
															   action:@"pin"]];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Add to Album"
															   action:@"album"]];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Remove from Profile"
															   action:@"unprofile"
																 type:TGActionSheetActionTypeDestructive]];
	}
	else if (self.mode == TGStoryListArchive)
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Save to Profile"
															   action:@"profile"]];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Add to Album"
															   action:@"album"]];
	}
	else if (self.mode == TGStoryListAlbum)
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Move Up" action:@"up"]];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Remove from Album"
															   action:@"remove"
																 type:TGActionSheetActionTypeDestructive]];
	}
	else if (self.mode == TGStoryListAlbums)
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Rename" action:@"rename"]];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Move Up" action:@"albumup"]];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Delete Album"
															   action:@"deletealbum"
																 type:TGActionSheetActionTypeDestructive]];
	}

	return actions;
}

- (void)rowHeld:(UILongPressGestureRecognizer *)recognizer
{
	if (recognizer.state != UIGestureRecognizerStateBegan)
		return;

	CGPoint point = [recognizer locationInView:_tableView];
	NSIndexPath *indexPath = [_tableView indexPathForRowAtPoint:point];
	if (indexPath == nil || indexPath.row >= (NSInteger)_rows.count)
		return;

	NSUInteger index = (NSUInteger)indexPath.row;
	NSDictionary *row = [_rows objectAtIndex:index];
	NSInteger storyId = TGStoryNumber(row, @"id");

	NSArray *actions = [self heldRowActionsForStoryId:storyId];

	if (actions.count == 0)
		return;

	__weak TGStoryListViewController *weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:nil
													   actions:actions
												   actionBlock:^(id target, NSString *action)
	{
		(void)target;
		TGStoryListViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;

		if ([action isEqualToString:@"pin"])
			[strongSelf togglePinnedForStory:storyId];
		else if ([action isEqualToString:@"album"])
			[strongSelf addStoryToAlbum:storyId];
		else if ([action isEqualToString:@"unprofile"])
		{
			[[TGClient shared] setStory:storyId inChat:strongSelf.chatId onProfile:NO];
			[strongSelf reload];
		}
		else if ([action isEqualToString:@"profile"])
		{
			[[TGClient shared] setStory:storyId inChat:strongSelf.chatId onProfile:YES];
			[strongSelf showMessage:@"Saved to your profile"];
		}
		else if ([action isEqualToString:@"up"])
			[strongSelf moveStoryUp:index];
		else if ([action isEqualToString:@"remove"])
			[strongSelf removeStoryFromAlbum:storyId];
		else if ([action isEqualToString:@"rename"])
			[strongSelf renameAlbum:row];
		else if ([action isEqualToString:@"albumup"])
			[strongSelf moveAlbumUp:index];
		else if ([action isEqualToString:@"deletealbum"])
			[strongSelf deleteAlbum:row];
	}
														target:self];
	[sheet showInView:self.view];
}

@end

@interface TGStoryPage : UIView

@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, strong) NSNumber *itemId;
@property (nonatomic, strong) NSNumber *photoFileId;
@property (nonatomic, readonly) UIImage *image;
@property (nonatomic, assign) CGFloat captionBottomInset;
@property (nonatomic, readonly) BOOL failed;

- (void)setStoryImage:(UIImage *)image animated:(BOOL)animated;
- (void)setCaption:(NSString *)caption;
- (void)setAreas:(NSArray *)areas;
- (NSDictionary *)areaAtPoint:(CGPoint)point;
- (void)prepareForReuse;
- (CGRect)captionFrame;
- (void)beginLoading;
- (void)showFailure;

@end

@implementation TGStoryPage
{
	UIImageView *_imageView;
	UIView *_captionPlate;
	UILabel *_captionLabel;
	UIActivityIndicatorView *_spinner;
	UILabel *_statusLabel;
	NSArray *_areas;
}

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self != nil)
	{
		self.backgroundColor = [UIColor clearColor];

		_imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_imageView.backgroundColor = [UIColor blackColor];
		_imageView.contentMode = UIViewContentModeScaleAspectFit;
		_imageView.userInteractionEnabled = NO;
		[self addSubview:_imageView];

		_captionPlate = [[UIView alloc] initWithFrame:CGRectZero];
		_captionPlate.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.45f];
		_captionPlate.userInteractionEnabled = NO;
		_captionPlate.hidden = YES;
		[self addSubview:_captionPlate];

		_captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_captionLabel.backgroundColor = [UIColor clearColor];
		_captionLabel.textColor = [UIColor whiteColor];
		_captionLabel.font = [UIFont systemFontOfSize:15];
		_captionLabel.numberOfLines = 2;
		_captionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		[_captionPlate addSubview:_captionLabel];

		_spinner = [[UIActivityIndicatorView alloc]
				initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
		_spinner.hidesWhenStopped = YES;
		_spinner.userInteractionEnabled = NO;
		[self addSubview:_spinner];

		_statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_statusLabel.backgroundColor = [UIColor clearColor];
		_statusLabel.textColor = [UIColor whiteColor];
		_statusLabel.font = [UIFont systemFontOfSize:14];
		_statusLabel.textAlignment = NSTextAlignmentCenter;
		_statusLabel.numberOfLines = 2;
		_statusLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
		_statusLabel.shadowOffset = CGSizeMake(0, -1);
		_statusLabel.text = @"Photo unavailable\nTap to reload";
		_statusLabel.hidden = YES;
		_statusLabel.userInteractionEnabled = NO;
		[self addSubview:_statusLabel];
	}
	return self;
}

- (void)beginLoading
{
	_failed = NO;
	_statusLabel.hidden = YES;
	if (_imageView.image == nil)
		[_spinner startAnimating];
	[self setNeedsLayout];
}

- (void)showFailure
{
	[_spinner stopAnimating];
	if (_imageView.image != nil)
		return;
	_failed = YES;
	_statusLabel.hidden = NO;
	[self setNeedsLayout];
}

- (UIImage *)image
{
	return _imageView.image;
}

- (void)setStoryImage:(UIImage *)image animated:(BOOL)animated
{
	if (image != nil)
	{
		_failed = NO;
		_statusLabel.hidden = YES;
		[_spinner stopAnimating];
	}
	if (animated && image != nil)
	{
		UIImageView *view = _imageView;
		[UIView transitionWithView:view
						  duration:0.15
						   options:UIViewAnimationOptionTransitionCrossDissolve
						animations:^{ view.image = image; }
						completion:nil];
	}
	else
	{
		_imageView.image = image;
	}
	[self setNeedsLayout];
}

- (void)setCaption:(NSString *)caption
{
	_captionLabel.text = caption ?: @"";
	_captionPlate.hidden = (caption.length == 0);
	[self setNeedsLayout];
}

- (void)setCaptionBottomInset:(CGFloat)captionBottomInset
{
	if (_captionBottomInset == captionBottomInset)
		return;
	_captionBottomInset = captionBottomInset;
	[self setNeedsLayout];
}

- (void)setAreas:(NSArray *)areas
{
	_areas = [areas isKindOfClass:[NSArray class]] ? [areas copy] : nil;
}

- (NSDictionary *)areaAtPoint:(CGPoint)point
{
	if (_areas.count == 0)
		return nil;

	CGRect frame = _imageView.frame;
	if (frame.size.width < 1.0f || frame.size.height < 1.0f)
		return nil;

	for (NSDictionary *area in _areas)
	{
		if (![area isKindOfClass:[NSDictionary class]])
			continue;
		CGFloat width = frame.size.width * (CGFloat)[[area objectForKey:@"width"] doubleValue] / 100.0f;
		CGFloat height = frame.size.height * (CGFloat)[[area objectForKey:@"height"] doubleValue] / 100.0f;
		if (width < 1.0f || height < 1.0f)
			continue;
		CGFloat centerX = frame.origin.x +
				frame.size.width * (CGFloat)[[area objectForKey:@"x"] doubleValue] / 100.0f;
		CGFloat centerY = frame.origin.y +
				frame.size.height * (CGFloat)[[area objectForKey:@"y"] doubleValue] / 100.0f;
		CGRect box = CGRectMake(centerX - width / 2.0f, centerY - height / 2.0f, width, height);
		if (CGRectContainsPoint(CGRectInset(box, -4.0f, -4.0f), point))
			return area;
	}
	return nil;
}

- (void)prepareForReuse
{
	_imageView.image = nil;
	_captionLabel.text = @"";
	_captionPlate.hidden = YES;
	_areas = nil;
	self.itemId = nil;
}

- (CGRect)captionFrame
{
	if (_captionPlate.hidden)
		return CGRectZero;
	return _captionPlate.frame;
}

- (void)layoutSubviews
{
	[super layoutSubviews];

	CGRect area = self.bounds;
	CGSize size = _imageView.image != nil ? _imageView.image.size : CGSizeMake(9.0f, 16.0f);
	if (size.width <= 0.0f || size.height <= 0.0f)
		size = CGSizeMake(9.0f, 16.0f);

	CGFloat scale = MIN(area.size.width / size.width, area.size.height / size.height);
	CGFloat drawWidth = floorf(size.width * scale);
	CGFloat drawHeight = floorf(size.height * scale);
	CGRect frame = CGRectMake(floorf((area.size.width - drawWidth) / 2.0f),
							  floorf((area.size.height - drawHeight) / 2.0f),
							  drawWidth, drawHeight);
	_imageView.frame = frame;

	CGFloat plateBottom = MIN(CGRectGetMaxY(frame), area.size.height - _captionBottomInset);
	CGFloat available = MAX(0.0f, plateBottom - frame.origin.y);
	CGFloat plateHeight = MIN(TGStoryCaptionHeight, available);
	_captionPlate.frame = CGRectMake(frame.origin.x,
									 plateBottom - plateHeight,
									 frame.size.width, plateHeight);
	_captionLabel.frame = CGRectInset(_captionPlate.bounds, 8.0f, 6.0f);
}

@end

@interface TGStoriesViewController () <UIScrollViewDelegate, UIGestureRecognizerDelegate,
		UIImagePickerControllerDelegate, UINavigationControllerDelegate>
{
	NSArray *_storyIds;
	NSInteger _index;
	NSMutableDictionary *_stories;
	NSMutableSet *_seen;
	NSInteger _openStoryId;

	NSMutableArray *_posterList;
	NSInteger _posterIndex;
	BOOL _postersRequested;
	BOOL _dismissing;

	UIView *_stripView;
	UIScrollView *_pagingView;
	NSMutableArray *_visiblePages;
	NSMutableArray *_pageQueue;
	UIView *_footerView;
	UIButton *_replyButton;
	UIButton *_middleButton;
	UIButton *_shareButton;
	UIImageView *_topPanel;
	UIImageView *_bottomPanel;
	UILabel *_counterLabel;
	UILabel *_authorLabel;
	UILabel *_dateLabel;
	UIButton *_closeButton;
	UIButton *_actionButton;
	UIButton *_deleteButton;
	BOOL _navigationBarWasHidden;
	NSString *_reportOptionId;

	__weak TGReactionPickerView *_reactionPicker;
	NSTimer *_timer;
	NSTimeInterval _elapsed;
	BOOL _holdPaused;
	BOOL _modalPaused;
	BOOL _onScreen;
}
@end

@implementation TGStoriesViewController

@synthesize chatId = _chatId;

- (instancetype)initWithChatId:(int64_t)chatId
					  storyIds:(NSArray *)storyIds
					startIndex:(NSInteger)startIndex
{
	self = [super init];
	if (self != nil)
	{
		_chatId = chatId;
		_storyIds = [storyIds isKindOfClass:[NSArray class]] ? [storyIds copy] : [NSArray array];
		_index = startIndex;
		if (_index < 0 || _index >= (NSInteger)_storyIds.count)
			_index = 0;
		_stories = [[NSMutableDictionary alloc] init];
		_seen = [[NSMutableSet alloc] init];
	}
	return self;
}

+ (void)openStoriesForChat:(int64_t)chatId
					  name:(NSString *)name
					  from:(UIViewController *)controller
{
	if (controller.navigationController == nil)
		return;
	UINavigationController *navigation = controller.navigationController;
	[[TGClient shared] activeStoriesForChat:chatId completion:^(NSDictionary *active)
	{
		NSArray *stories = [active objectForKey:@"stories"];
		if (![stories isKindOfClass:[NSArray class]] || stories.count == 0)
		{
			[[[TGAlertView alloc] initWithTitle:nil
										message:@"No stories"
							  cancelButtonTitle:@"OK"
								  okButtonTitle:nil
								completionBlock:nil] show];
			return;
		}

		NSInteger maxRead = TGStoryNumber(active, @"maxReadStoryId");
		NSMutableArray *ids = [[NSMutableArray alloc] init];
		NSInteger start = 0;
		for (NSDictionary *story in stories)
		{
			if (![story isKindOfClass:[NSDictionary class]])
				continue;
			NSInteger storyId = TGStoryNumber(story, @"id");
			if (storyId <= maxRead)
				start = (NSInteger)ids.count + 1;
			[ids addObject:[NSNumber numberWithInteger:storyId]];
		}
		if (start >= (NSInteger)ids.count)
			start = 0;

		TGStoriesViewController *viewer =
				[[TGStoriesViewController alloc] initWithChatId:chatId
													   storyIds:ids
													 startIndex:start];
		viewer.posterName = name;
		[navigation pushViewController:viewer animated:YES];
	}];
}

- (NSString *)resolvedPosterName
{
	if (self.posterName.length > 0)
		return self.posterName;
	for (NSDictionary *chat in [[TGClient shared] chats])
	{
		if (![chat isKindOfClass:[NSDictionary class]])
			continue;
		if (TGStoryChatId(chat, @"id") == _chatId)
			return TGStoryString(chat, @"title");
	}
	return @"Story";
}

- (BOOL)isOwnStory
{
	NSDictionary *me = [[TGClient shared] me];
	if (me == nil)
		return NO;
	return TGStoryChatId(me, @"id") == _chatId;
}

- (NSDictionary *)currentStory
{
	if (_index < 0 || _index >= (NSInteger)_storyIds.count)
		return nil;
	return [_stories objectForKey:[_storyIds objectAtIndex:(NSUInteger)_index]];
}

- (NSInteger)currentStoryId
{
	if (_index < 0 || _index >= (NSInteger)_storyIds.count)
		return 0;
	return [[_storyIds objectAtIndex:(NSUInteger)_index] integerValue];
}

#pragma mark - chrome

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.view.backgroundColor = [UIColor blackColor];
	self.view.clipsToBounds = YES;
	self.wantsFullScreenLayout = YES;

	_visiblePages = [[NSMutableArray alloc] init];
	_pageQueue = [[NSMutableArray alloc] init];

	_pagingView = [[UIScrollView alloc] initWithFrame:CGRectZero];
	_pagingView.pagingEnabled = YES;
	_pagingView.alwaysBounceHorizontal = YES;
	_pagingView.alwaysBounceVertical = NO;
	_pagingView.directionalLockEnabled = YES;
	_pagingView.scrollsToTop = NO;
	_pagingView.showsHorizontalScrollIndicator = NO;
	_pagingView.showsVerticalScrollIndicator = NO;
	_pagingView.delaysContentTouches = NO;
	_pagingView.backgroundColor = [UIColor clearColor];
	_pagingView.delegate = self;
	[self.view addSubview:_pagingView];

	[self buildTopPanel];

	_stripView = [[UIView alloc] initWithFrame:CGRectZero];
	_stripView.backgroundColor = [UIColor clearColor];
	_stripView.userInteractionEnabled = NO;
	[self.view addSubview:_stripView];

	[self buildBottomPanel];
	[self buildFooter];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(viewTapped:)];
	tap.delegate = self;
	[self.view addGestureRecognizer:tap];

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(viewDragged:)];
	pan.delegate = self;
	pan.maximumNumberOfTouches = 1;
	[self.view addGestureRecognizer:pan];

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(viewHeld:)];
	hold.delegate = self;
	hold.minimumPressDuration = 0.2;
	hold.cancelsTouchesInView = NO;
	[self.view addGestureRecognizer:hold];

	[self updateStrip];
	[self updateChrome];
	[self discoverPosters];
}

- (UILabel *)panelLabelWithFont:(UIFont *)font frame:(CGRect)frame
{
	UILabel *label = [[UILabel alloc] initWithFrame:frame];
	label.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	label.backgroundColor = [UIColor clearColor];
	label.textColor = [UIColor whiteColor];
	label.font = font;
	label.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
	label.shadowOffset = CGSizeMake(0, -1);
	label.textAlignment = NSTextAlignmentCenter;
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	return label;
}

- (UIButton *)platedButtonWithTitle:(NSString *)title
						   minWidth:(CGFloat)minWidth
							 action:(SEL)action
{
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.exclusiveTouch = YES;
	button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	[button setTitle:title forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[button setTitleShadowColor:[UIColor colorWithWhite:0.0f alpha:0.5f]
					   forState:UIControlStateNormal];
	button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	button.adjustsImageWhenHighlighted = NO;

	UIImage *plate = [UIImage imageNamed:@"GalleryDoneButton.png"];
	UIImage *platePressed = [UIImage imageNamed:@"GalleryDoneButton_Highlighted.png"];
	if (plate != nil)
	{
		[button setBackgroundImage:[plate stretchableImageWithLeftCapWidth:11 topCapHeight:0]
						  forState:UIControlStateNormal];
	}
	if (platePressed != nil)
	{
		[button setBackgroundImage:[platePressed stretchableImageWithLeftCapWidth:11
																	 topCapHeight:0]
						  forState:UIControlStateHighlighted];
	}

	CGFloat width = [title sizeWithFont:button.titleLabel.font].width + 14.0f;
	if (width < minWidth)
		width = minWidth;
	button.frame = CGRectMake(0, 0, width, TGStoryPlateHeight);
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (UIButton *)panelButtonWithImageNamed:(NSString *)name
							 fallback:(NSString *)fallback
							   action:(SEL)action
{
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.exclusiveTouch = YES;
	button.showsTouchWhenHighlighted = YES;
	UIImage *icon = [UIImage imageNamed:name];
	if (icon != nil)
	{
		[button setBackgroundImage:icon forState:UIControlStateNormal];
	}
	else
	{
		button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
		[button setTitle:fallback forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithWhite:0.0f alpha:0.5f]
						   forState:UIControlStateNormal];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	}
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (void)buildTopPanel
{
	CGFloat width = self.view.bounds.size.width;

	UIImage *panelImage = [UIImage imageNamed:@"GalleryTopPanel.png"];
	CGFloat panelHeight = panelImage != nil ? panelImage.size.height : TGStoryPanelHeight;
	_topPanel = [[UIImageView alloc] initWithFrame:
			CGRectMake(0, TGStoryStatusBarHeight, width, panelHeight)];
	_topPanel.image = panelImage;
	if (panelImage == nil)
		_topPanel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_topPanel.userInteractionEnabled = YES;
	_topPanel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:_topPanel];

	UIImage *cornersImage = [UIImage imageNamed:@"NavigationBar_Corners.png"];
	if (cornersImage != nil)
	{
		UIImageView *corners = [[UIImageView alloc] initWithImage:
				[cornersImage stretchableImageWithLeftCapWidth:(int)(cornersImage.size.width / 2)
												  topCapHeight:0]];
		corners.frame = CGRectMake(0, -TGStoryStatusBarHeight, width, cornersImage.size.height);
		corners.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[_topPanel addSubview:corners];
	}

	_closeButton = [self platedButtonWithTitle:@"Close"
									  minWidth:55.0f
										action:@selector(closeTapped)];
	_closeButton.frame = CGRectMake(TGStoryPlateLeft, TGStoryPlateTop,
									_closeButton.frame.size.width, TGStoryPlateHeight);
	[_topPanel addSubview:_closeButton];

	_counterLabel = [self panelLabelWithFont:[UIFont boldSystemFontOfSize:20]
									   frame:CGRectMake((CGFloat)(int)((width - 140) / 2),
														11, 140, 20)];
	[_topPanel addSubview:_counterLabel];
}

- (void)buildBottomPanel
{
	CGRect bounds = self.view.bounds;

	UIImage *panelImage = [UIImage imageNamed:@"GalleryBottomPanel.png"];
	CGFloat panelHeight = panelImage != nil ? panelImage.size.height : TGStoryPanelHeight;
	_bottomPanel = [[UIImageView alloc] initWithFrame:
			CGRectMake(0, bounds.size.height - panelHeight, bounds.size.width, panelHeight)];
	if (panelImage != nil)
	{
		_bottomPanel.image = [panelImage
				stretchableImageWithLeftCapWidth:(int)(panelImage.size.width / 2)
									topCapHeight:0];
	}
	else
	{
		_bottomPanel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	}
	_bottomPanel.userInteractionEnabled = YES;
	_bottomPanel.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleTopMargin;
	[self.view addSubview:_bottomPanel];

	_authorLabel = [self panelLabelWithFont:[UIFont boldSystemFontOfSize:14]
									  frame:CGRectMake((CGFloat)(int)((bounds.size.width - 220) / 2),
													   4, 220, 20)];
	[_bottomPanel addSubview:_authorLabel];

	_dateLabel = [self panelLabelWithFont:[UIFont systemFontOfSize:13]
									frame:CGRectMake((CGFloat)(int)((bounds.size.width - 140) / 2),
													 23, 140, 20)];
	[_bottomPanel addSubview:_dateLabel];

	_actionButton = [self panelButtonWithImageNamed:@"GalleryActionIcon.png"
										   fallback:@"More"
											 action:@selector(morePressed)];
	_actionButton.frame = CGRectMake(TGStoryPanelButtonInset, TGStoryPanelButtonTop,
									 TGStoryPanelButtonSize, TGStoryPanelButtonSize);
	_actionButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
	[_bottomPanel addSubview:_actionButton];

	_deleteButton = [self panelButtonWithImageNamed:@"GalleryTrashIcon.png"
										   fallback:@"Delete"
											 action:@selector(deleteTapped)];
	_deleteButton.frame = CGRectMake(bounds.size.width - TGStoryPanelButtonSize
											- TGStoryPanelButtonInset,
									 TGStoryPanelButtonTop,
									 TGStoryPanelButtonSize, TGStoryPanelButtonSize);
	_deleteButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	_deleteButton.hidden = YES;
	[_bottomPanel addSubview:_deleteButton];
}

- (void)closeTapped
{
	[self dismissViewer];
}

- (void)deleteTapped
{
	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;
	[self confirmDeleteStoryId:storyId];
}

- (UIButton *)footerButtonWithTitle:(NSString *)title action:(SEL)action
{
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.exclusiveTouch = YES;
	[button setTitle:title forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
	[button setTitleShadowColor:[UIColor colorWithRed:0.055f green:0.157f blue:0.302f alpha:0.4f]
					   forState:UIControlStateNormal];
	button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	button.adjustsImageWhenHighlighted = NO;
	[button addTarget:self action:action forControlEvents:UIControlEventTouchDown];
	return button;
}

- (void)buildFooter
{
	_footerView = [[UIView alloc] initWithFrame:CGRectZero];
	_footerView.backgroundColor = [UIColor clearColor];
	[self.view addSubview:_footerView];

	_replyButton = [self footerButtonWithTitle:@"Reply" action:@selector(replyPressed)];
	_middleButton = [self footerButtonWithTitle:@"" action:@selector(middlePressed)];
	[_middleButton removeTarget:self
						 action:@selector(middlePressed)
			   forControlEvents:UIControlEventTouchDown];
	[_middleButton addTarget:self
					  action:@selector(middlePressed)
			forControlEvents:UIControlEventTouchUpInside];
	UILongPressGestureRecognizer *reactionHold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(middleHeld:)];
	reactionHold.minimumPressDuration = 0.4;
	[_middleButton addGestureRecognizer:reactionHold];
	_shareButton = [self footerButtonWithTitle:@"Share" action:@selector(sharePressed)];

	UIImage *left = TGStoryStretch(@"ButtonGroupLeft.png", 8);
	UIImage *leftPressed = TGStoryStretch(@"ButtonGroupLeft_Highlighted.png", 8);
	UIImage *center = TGStoryStretch(@"ButtonGroupCenter.png", 1);
	UIImage *centerPressed = TGStoryStretch(@"ButtonGroupCenter_Highlighted.png", 1);
	UIImage *right = TGStoryStretch(@"ButtonGroupRight.png", 1);
	UIImage *rightPressed = TGStoryStretch(@"ButtonGroupRight_Highlighted.png", 1);

	[_replyButton setBackgroundImage:left forState:UIControlStateNormal];
	[_replyButton setBackgroundImage:leftPressed forState:UIControlStateHighlighted];
	[_middleButton setBackgroundImage:center forState:UIControlStateNormal];
	[_middleButton setBackgroundImage:centerPressed forState:UIControlStateHighlighted];
	[_shareButton setBackgroundImage:right forState:UIControlStateNormal];
	[_shareButton setBackgroundImage:rightPressed forState:UIControlStateHighlighted];

	if (left == nil)
	{
		UIColor *plate = [[TGTheme shared] accentColour];
		_replyButton.backgroundColor = plate;
		_middleButton.backgroundColor = plate;
		_shareButton.backgroundColor = plate;
	}

	[_footerView addSubview:_replyButton];
	[_footerView addSubview:_middleButton];
	[_footerView addSubview:_shareButton];

	UIImage *divider = TGStoryStretch(@"ButtonGroupDivider.png", 6);
	for (NSInteger i = 0; i < 2; i++)
	{
		UIImageView *seam = [[UIImageView alloc] initWithImage:divider];
		seam.tag = 900 + i;
		if (divider == nil)
			seam.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.3f];
		[_footerView addSubview:seam];
	}
}

- (void)viewWillLayoutSubviews
{
	[super viewWillLayoutSubviews];

	CGRect bounds = self.view.bounds;
	CGFloat width = bounds.size.width;
	CGFloat height = bounds.size.height;

	CGFloat topPanelHeight = _topPanel.frame.size.height;
	_topPanel.frame = CGRectMake(0, TGStoryStatusBarHeight, width, topPanelHeight);

	CGFloat bottomPanelHeight = _bottomPanel.frame.size.height;
	_bottomPanel.frame = CGRectMake(0, height - bottomPanelHeight, width, bottomPanelHeight);

	CGFloat footerY = height - bottomPanelHeight - TGStoryFooterBottom - TGStoryFooterHeight;
	_footerView.frame = CGRectMake(TGStoryFooterInset, footerY,
								   width - TGStoryFooterInset * 2.0f, TGStoryFooterHeight);
	[self layoutFooter];

	_stripView.frame = CGRectMake(0, TGStoryStatusBarHeight + topPanelHeight,
								  width, TGStoryStripHeight);
	[self layoutStrip];

	CGRect area = CGRectMake(0, 0, width, height);
	if (!CGRectEqualToRect(_pagingView.frame, area))
	{
		_pagingView.frame = area;
		[self resetPagingGeometry];
	}

	CGFloat captionInset = height - footerY + TGStoryFooterBottom;
	for (TGStoryPage *page in _visiblePages)
		page.captionBottomInset = captionInset;
}

- (void)layoutFooter
{
	CGRect bounds = _footerView.bounds;
	CGFloat total = bounds.size.width;
	UIImage *divider = [UIImage imageNamed:@"ButtonGroupDivider.png"];
	CGFloat seam = divider != nil ? divider.size.width : 2.0f;
	CGFloat segment = (CGFloat)(int)((total - seam * 2.0f) / 3.0f);

	CGFloat x = 0.0f;
	_replyButton.frame = CGRectMake(x, 0, segment, TGStoryFooterHeight);
	x += segment;
	UIView *leftSeam = [_footerView viewWithTag:900];
	leftSeam.frame = CGRectMake(x, 0, seam, TGStoryFooterHeight);
	x += seam;
	_middleButton.frame = CGRectMake(x, 0, segment, TGStoryFooterHeight);
	x += segment;
	UIView *rightSeam = [_footerView viewWithTag:901];
	rightSeam.frame = CGRectMake(x, 0, seam, TGStoryFooterHeight);
	x += seam;
	_shareButton.frame = CGRectMake(x, 0, total - x, TGStoryFooterHeight);
}

- (void)layoutStrip
{
	NSInteger count = (NSInteger)_storyIds.count;
	if (count <= 0)
		return;

	CGFloat width = _stripView.bounds.size.width - TGStoryStripInset * 2.0f;
	CGFloat segment = floorf((width - TGStoryStripGap * (count - 1)) / count);
	if (segment < 1.0f)
		segment = 1.0f;

	NSArray *existing = [_stripView.subviews copy];
	if ((NSInteger)existing.count != count)
	{
		for (UIView *view in existing)
			[view removeFromSuperview];
		for (NSInteger i = 0; i < count; i++)
		{
			UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
			bar.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.3f];
			UIView *fill = [[UIView alloc] initWithFrame:CGRectZero];
			fill.tag = 1;
			fill.backgroundColor = [UIColor whiteColor];
			[bar addSubview:fill];
			[_stripView addSubview:bar];
		}
	}

	CGFloat x = TGStoryStripInset;
	NSArray *bars = _stripView.subviews;
	for (NSInteger i = 0; i < count; i++)
	{
		UIView *bar = [bars objectAtIndex:(NSUInteger)i];
		CGFloat thisWidth = (i == count - 1)
				? (_stripView.bounds.size.width - TGStoryStripInset - x)
				: segment;
		bar.frame = CGRectMake(x, 0, thisWidth, TGStoryStripHeight);
		x += thisWidth + TGStoryStripGap;
	}
	[self updateStrip];
}

- (void)updateStrip
{
	NSArray *bars = _stripView.subviews;
	for (NSUInteger i = 0; i < bars.count && i < _storyIds.count; i++)
	{
		UIView *bar = [bars objectAtIndex:i];
		UIView *fill = [bar viewWithTag:1];
		CGFloat portion;
		if ((NSInteger)i < _index)
			portion = 1.0f;
		else if ((NSInteger)i > _index)
			portion = [_seen containsObject:[_storyIds objectAtIndex:i]] ? 1.0f : 0.0f;
		else
			portion = (CGFloat)MIN(1.0, _elapsed / TGStoryDuration);
		fill.frame = CGRectMake(0, 0, floorf(bar.bounds.size.width * portion),
								bar.bounds.size.height);
	}
}

#pragma mark - timeline

- (BOOL)timelineShouldRun
{
	if (!_onScreen || _dismissing || _holdPaused || _modalPaused)
		return NO;
	if ([_pagingView isDragging] || [_pagingView isDecelerating])
		return NO;
	return [self pageForIndex:_index].image != nil;
}

- (void)updateTimeline
{
	BOOL run = [self timelineShouldRun];
	if (run && _timer == nil)
	{
		_timer = [NSTimer scheduledTimerWithTimeInterval:TGStoryTick
												  target:self
												selector:@selector(timelineTick)
												userInfo:nil
												 repeats:YES];
	}
	else if (!run && _timer != nil)
	{
		[_timer invalidate];
		_timer = nil;
	}
}

- (void)resetTimeline
{
	_elapsed = 0.0;
	[self updateStrip];
	[self updateTimeline];
}

- (void)setHoldPaused:(BOOL)paused
{
	if (_holdPaused == paused)
		return;
	_holdPaused = paused;
	[self updateTimeline];
}

- (void)setModalPaused:(BOOL)paused
{
	if (_modalPaused == paused)
		return;
	_modalPaused = paused;
	[self updateTimeline];
}

- (void)timelineTick
{
	if (![self timelineShouldRun])
	{
		[self updateTimeline];
		return;
	}

	_elapsed += TGStoryTick;
	if (_elapsed < TGStoryDuration)
	{
		[self updateStrip];
		return;
	}

	_elapsed = 0.0;
	if (_index + 1 < (NSInteger)_storyIds.count)
		[self showIndex:_index + 1 animated:YES];
	else
		[self movePosterBy:1];
}

#pragma mark - paging

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	_navigationBarWasHidden = self.navigationController.navigationBarHidden;
	[self.navigationController setNavigationBarHidden:YES animated:animated];
	if (_openStoryId == 0)
	{
		NSInteger storyId = [self currentStoryId];
		if (storyId != 0)
		{
			_openStoryId = storyId;
			[[TGClient shared] openStory:storyId inChat:_chatId];
		}
	}
	_onScreen = YES;
	_elapsed = 0.0;
	[self updateTimeline];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	_onScreen = YES;
	[self updateTimeline];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.navigationController setNavigationBarHidden:_navigationBarWasHidden animated:animated];
	_onScreen = NO;
	[self updateTimeline];
	[TGReactionPickerView dismiss];
	[self closeCurrent];
}

- (void)dealloc
{
	[_timer invalidate];
	_timer = nil;
}

- (void)didReceiveMemoryWarning
{
	[super didReceiveMemoryWarning];

	[_pageQueue removeAllObjects];

	for (NSInteger i = (NSInteger)_visiblePages.count - 1;
			i >= 0 && [self pageForIndex:_index] != nil; i--)
	{
		TGStoryPage *page = [_visiblePages objectAtIndex:(NSUInteger)i];
		if (page.pageIndex == _index)
			continue;
		[page prepareForReuse];
		[page removeFromSuperview];
		[_visiblePages removeObjectAtIndex:(NSUInteger)i];
	}

	NSNumber *key = [self currentStoryKey];
	NSDictionary *keep = key != nil ? [_stories objectForKey:key] : nil;
	[_stories removeAllObjects];
	if (keep != nil)
		[_stories setObject:keep forKey:key];
}

- (void)closeCurrent
{
	if (_openStoryId != 0)
	{
		[[TGClient shared] closeStory:_openStoryId inChat:_chatId];
		_openStoryId = 0;
	}
}

- (CGRect)frameForPageIndex:(NSInteger)index
{
	CGRect bounds = _pagingView.bounds;
	return CGRectMake(index * bounds.size.width + TGStoryPageGap / 2.0f, 0,
					  bounds.size.width - TGStoryPageGap, bounds.size.height);
}

- (TGStoryPage *)dequeuePage
{
	if (_pageQueue.count != 0)
	{
		TGStoryPage *page = [_pageQueue objectAtIndex:0];
		[_pageQueue removeObjectAtIndex:0];
		return page;
	}
	return [[TGStoryPage alloc] initWithFrame:_pagingView.bounds];
}

- (void)recycleSparePage:(TGStoryPage *)page
{
	[page prepareForReuse];
	[page removeFromSuperview];
	if (_pageQueue.count < TGStoryPageQueueLimit)
		[_pageQueue addObject:page];
}

- (TGStoryPage *)pageForIndex:(NSInteger)index
{
	for (TGStoryPage *page in _visiblePages)
	{
		if (page.pageIndex == index)
			return page;
	}
	return nil;
}

- (void)resetPagingGeometry
{
	CGFloat width = _pagingView.bounds.size.width;
	if (width < 1.0f)
		return;

	for (TGStoryPage *page in _visiblePages)
		page.frame = [self frameForPageIndex:page.pageIndex];

	_pagingView.contentSize = CGSizeMake(width * (CGFloat)_storyIds.count,
										 _pagingView.bounds.size.height);
	_pagingView.contentOffset = CGPointMake(width * (CGFloat)_index, 0);
	[self layoutPages];
}

- (void)layoutPages
{
	CGRect bounds = _pagingView.bounds;
	CGFloat width = bounds.size.width;
	if (width < 1.0f)
		return;

	CGFloat offset = _pagingView.contentOffset.x;
	CGFloat minX = offset - width;
	CGFloat maxX = offset + width * 2.0f;

	for (NSInteger i = (NSInteger)_visiblePages.count - 1; i >= 0; i--)
	{
		TGStoryPage *page = [_visiblePages objectAtIndex:(NSUInteger)i];
		CGRect frame = page.frame;
		if (CGRectGetMaxX(frame) <= minX || frame.origin.x > maxX)
		{
			[self recycleSparePage:page];
			[_visiblePages removeObjectAtIndex:(NSUInteger)i];
		}
	}

	NSInteger count = (NSInteger)_storyIds.count;
	if (count == 0)
		return;

	NSInteger start = (NSInteger)floorf(offset / width) - 1;
	NSInteger end = start + 2;
	if (start < 0)
		start = 0;
	if (end > count - 1)
		end = count - 1;

	for (NSInteger i = start; i <= end; i++)
	{
		if ([self pageForIndex:i] != nil)
			continue;

		TGStoryPage *page = [self dequeuePage];
		page.pageIndex = i;
		page.captionBottomInset = _footerView.frame.origin.y > 0.0f
				? (bounds.size.height - _footerView.frame.origin.y + TGStoryFooterBottom)
				: 0.0f;
		page.frame = [self frameForPageIndex:i];
		page.itemId = [_storyIds objectAtIndex:(NSUInteger)i];
		[_visiblePages addObject:page];
		[_pagingView addSubview:page];
		[self loadPage:page];
	}

	NSInteger current = (NSInteger)((offset + width / 2.0f) / width);
	if (current > count - 1)
		current = count - 1;
	if (current < 0)
		current = 0;
	[self setCurrentIndex:current];
}

- (void)setCurrentIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)_storyIds.count)
		return;

	NSNumber *key = [_storyIds objectAtIndex:(NSUInteger)index];
	if (index == _index && _openStoryId != 0)
	{
		if (![_seen containsObject:key])
		{
			[_seen addObject:key];
			[self updateStrip];
		}
		return;
	}

	[self closeCurrent];
	_index = index;

	[_seen addObject:key];
	_openStoryId = [key integerValue];
	[[TGClient shared] openStory:_openStoryId inChat:_chatId];

	[self resetTimeline];
	[self updateChrome];
}

- (void)loadPage:(TGStoryPage *)page
{
	NSNumber *key = page.itemId;
	if (key == nil)
		return;

	NSDictionary *known = [_stories objectForKey:key];
	if (known != nil)
	{
		[page setCaption:TGStoryString(known, @"caption")];
		[page setAreas:[known objectForKey:@"areas"]];
		[self loadPhotoForPage:page story:known];
		return;
	}

	int64_t chatId = _chatId;
	__weak TGStoriesViewController *weakSelf = self;
	__weak TGStoryPage *weakPage = page;
	[[TGClient shared] storyWithId:[key integerValue]
							inChat:chatId
						completion:^(NSDictionary *story)
	{
		TGStoriesViewController *strongSelf = weakSelf;
		TGStoryPage *strongPage = weakPage;
		if (strongSelf == nil || strongSelf->_chatId != chatId)
			return;
		if (![story isKindOfClass:[NSDictionary class]])
			return;
		[strongSelf->_stories setObject:story forKey:key];
		if ([key isEqual:[strongSelf currentStoryKey]])
			[strongSelf updateChrome];
		if (strongPage == nil || ![strongPage.itemId isEqual:key])
			return;
		[strongPage setCaption:TGStoryString(story, @"caption")];
		[strongPage setAreas:[story objectForKey:@"areas"]];
		[strongSelf loadPhotoForPage:strongPage story:story];
	}];
}

- (NSNumber *)currentStoryKey
{
	if (_index < 0 || _index >= (NSInteger)_storyIds.count)
		return nil;
	return [_storyIds objectAtIndex:(NSUInteger)_index];
}

- (UIImage *)currentImage
{
	return [self pageForIndex:_index].image;
}

- (void)loadPhotoForPage:(TGStoryPage *)page story:(NSDictionary *)story
{
	NSNumber *photoId = [story objectForKey:@"photoId"];
	if (![photoId isKindOfClass:[NSNumber class]])
	{
		[page setStoryImage:nil animated:NO];
		return;
	}

	NSNumber *key = page.itemId;
	__weak TGStoryPage *weakPage = page;
	__weak TGStoriesViewController *weakSelf = self;
	[[TGClient shared] downloadFile:[photoId integerValue]
							 offset:0
							  limit:0
						 completion:^(NSDictionary *file)
	{
		NSString *path = TGStoryString(file, @"path");
		if (path.length == 0)
			return;
		if (weakPage == nil || ![weakPage.itemId isEqual:key])
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^
		{
			@autoreleasepool
			{
				if (weakPage == nil || ![weakPage.itemId isEqual:key])
					return;
				UIImage *image = TGDecodeThumbnail(path, TGStoryPhotoPixels);
				if (image == nil)
					return;
				dispatch_async(dispatch_get_main_queue(), ^
				{
					TGStoryPage *inner = weakPage;
					if (inner == nil || ![inner.itemId isEqual:key])
						return;
					[inner setStoryImage:image animated:YES];
					[weakSelf updateTimeline];
				});
			}
		});
	}];
}

- (void)showIndex:(NSInteger)index animated:(BOOL)animated
{
	if (index < 0 || index >= (NSInteger)_storyIds.count)
		return;

	CGFloat width = _pagingView.bounds.size.width;
	if (width < 1.0f)
	{
		_index = index;
		return;
	}

	[_pagingView setContentOffset:CGPointMake(width * (CGFloat)index, 0) animated:animated];
	if (!animated)
		[self layoutPages];
}

#pragma mark - scrolling

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
	(void)scrollView;
	[self layoutPages];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
	(void)scrollView;
	_elapsed = 0.0;
	[self updateTimeline];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
	(void)scrollView;
	[self updateTimeline];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
	(void)scrollView;
	[self updateTimeline];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
	(void)decelerate;
	[self updateTimeline];
	CGFloat width = scrollView.bounds.size.width;
	CGFloat maxOffset = MAX(0.0f, scrollView.contentSize.width - width);
	CGFloat offset = scrollView.contentOffset.x;

	if (offset > maxOffset + TGStoryOverscroll)
		[self movePosterBy:1];
	else if (offset < -TGStoryOverscroll)
		[self movePosterBy:-1];
}

#pragma mark - posters

- (NSDictionary *)posterEntryForCurrentChat
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithLongLong:_chatId], @"chatId",
			[self resolvedPosterName], @"title",
			_storyIds, @"ids", nil];
}

- (void)discoverPosters
{
	if (_postersRequested)
		return;
	_postersRequested = YES;

	_posterList = [[NSMutableArray alloc] init];
	[_posterList addObject:[self posterEntryForCurrentChat]];
	_posterIndex = 0;

	NSArray *chats = [[TGClient shared] chats];
	if (![chats isKindOfClass:[NSArray class]] || chats.count == 0)
		return;
	if (chats.count > 25)
		chats = [chats subarrayWithRange:NSMakeRange(0, 25)];

	NSMutableArray *found = [[NSMutableArray alloc] init];
	__block NSInteger pending = 0;
	__weak TGStoriesViewController *weakSelf = self;

	for (NSDictionary *chat in chats)
	{
		if (![chat isKindOfClass:[NSDictionary class]])
			continue;
		int64_t chatId = TGStoryChatId(chat, @"id");
		if (chatId == 0 || chatId == _chatId)
			continue;

		NSString *title = TGStoryString(chat, @"title");
		pending++;
		[[TGClient shared] activeStoriesForChat:chatId completion:^(NSDictionary *active)
		{
			TGStoriesViewController *strongSelf = weakSelf;
			pending--;
			if (strongSelf == nil)
				return;

			NSDictionary *entry = TGStoryPosterEntry(chatId, title, active);
			if (entry != nil)
				[found addObject:entry];

			if (pending > 0)
				return;

			[strongSelf appendDiscoveredPosters:found];
		}];
	}
}

- (void)appendDiscoveredPosters:(NSMutableArray *)found
{
	[found sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b)
	{
		long long left = [[a objectForKey:@"order"] longLongValue];
		long long right = [[b objectForKey:@"order"] longLongValue];
		if (left == right)
			return NSOrderedSame;
		return left > right ? NSOrderedAscending : NSOrderedDescending;
	}];
	[_posterList addObjectsFromArray:found];
}

- (void)movePosterBy:(NSInteger)delta
{
	NSInteger target = _posterIndex + delta;
	if (_posterList == nil || target < 0 || target >= (NSInteger)_posterList.count)
	{
		if (delta > 0)
			[self dismissViewer];
		return;
	}

	NSDictionary *poster = [_posterList objectAtIndex:(NSUInteger)target];
	NSArray *ids = [poster objectForKey:@"ids"];
	if (![ids isKindOfClass:[NSArray class]] || ids.count == 0)
		return;

	[self closeCurrent];

	_posterIndex = target;
	_chatId = TGStoryChatId(poster, @"chatId");
	self.posterName = TGStoryString(poster, @"title");
	_storyIds = [ids copy];
	[_stories removeAllObjects];
	[_seen removeAllObjects];
	_index = (delta > 0) ? 0 : (NSInteger)_storyIds.count - 1;

	for (TGStoryPage *page in _visiblePages)
		[self recycleSparePage:page];
	[_visiblePages removeAllObjects];

	_elapsed = 0.0;
	[self layoutStrip];
	[self updateChrome];
	[self updateTimeline];

	UIScrollView *paging = _pagingView;
	[UIView transitionWithView:paging
					  duration:0.2
					   options:UIViewAnimationOptionTransitionCrossDissolve
					animations:^{ [self resetPagingGeometry]; }
					completion:nil];
}

#pragma mark - dismissal

- (void)dismissViewer
{
	if (_dismissing)
		return;
	_dismissing = YES;

	CGFloat height = self.view.bounds.size.height;
	__weak TGStoriesViewController *weakSelf = self;
	[UIView animateWithDuration:0.2
					 animations:^
	{
		TGStoriesViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf.view.transform = CGAffineTransformMakeTranslation(0, height);
		strongSelf.view.alpha = 0.0f;
	}
					 completion:^(BOOL finished)
	{
		(void)finished;
		TGStoriesViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		strongSelf.view.transform = CGAffineTransformIdentity;
		strongSelf.view.alpha = 1.0f;
		[strongSelf.navigationController popViewControllerAnimated:NO];
	}];
}

- (void)viewDragged:(UIPanGestureRecognizer *)recognizer
{
	if (_dismissing)
		return;

	CGPoint translation = [recognizer translationInView:self.view];
	CGFloat shift = MAX(0.0f, translation.y);

	if (recognizer.state == UIGestureRecognizerStateChanged)
	{
		self.view.transform = CGAffineTransformMakeTranslation(0, shift);
		CGFloat height = MAX(1.0f, self.view.bounds.size.height);
		self.view.alpha = MAX(0.4f, 1.0f - shift / height);
		return;
	}

	if (recognizer.state == UIGestureRecognizerStateEnded ||
		recognizer.state == UIGestureRecognizerStateCancelled ||
		recognizer.state == UIGestureRecognizerStateFailed)
	{
		CGFloat velocity = [recognizer velocityInView:self.view].y;
		BOOL leaving = (recognizer.state == UIGestureRecognizerStateEnded) &&
				(shift > TGStoryDismissDistance || velocity > TGStoryDismissVelocity);
		if (leaving)
		{
			[self dismissViewer];
			return;
		}

		__weak TGStoriesViewController *weakSelf = self;
		[UIView animateWithDuration:0.2
						 animations:^
		{
			TGStoriesViewController *strongSelf = weakSelf;
			if (strongSelf == nil)
				return;
			strongSelf.view.transform = CGAffineTransformIdentity;
			strongSelf.view.alpha = 1.0f;
		}];
	}
}

- (void)viewHeld:(UILongPressGestureRecognizer *)recognizer
{
	if (recognizer.state == UIGestureRecognizerStateBegan)
	{
		CGPoint point = [recognizer locationInView:self.view];
		if ([self pointIsOnChrome:point])
			return;
		[self setHoldPaused:YES];
		return;
	}

	if (recognizer.state == UIGestureRecognizerStateEnded ||
		recognizer.state == UIGestureRecognizerStateCancelled ||
		recognizer.state == UIGestureRecognizerStateFailed)
	{
		[self setHoldPaused:NO];
	}
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer
{
	if (![recognizer isKindOfClass:[UIPanGestureRecognizer class]])
		return YES;

	CGPoint velocity = [(UIPanGestureRecognizer *)recognizer velocityInView:self.view];
	return velocity.y > 0.0f && fabsf((float)velocity.y) > fabsf((float)velocity.x);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
	UIView *hit = touch.view;
	if (hit == nil)
		return YES;

	UIView *picker = _reactionPicker;
	if (picker != nil && picker.superview != nil && hit != picker &&
		[hit isDescendantOfView:picker])
	{
		return NO;
	}

	if ([recognizer isKindOfClass:[UIPanGestureRecognizer class]])
		return YES;

	if (_footerView != nil && [hit isDescendantOfView:_footerView])
		return NO;
	if (_topPanel != nil && [hit isDescendantOfView:_topPanel])
		return NO;
	if (_bottomPanel != nil && [hit isDescendantOfView:_bottomPanel])
		return NO;

	return YES;
}

- (BOOL)pointIsOnChrome:(CGPoint)point
{
	if (_footerView != nil && CGRectContainsPoint(_footerView.frame, point))
		return YES;
	if (_topPanel != nil && CGRectContainsPoint(_topPanel.frame, point))
		return YES;
	if (_bottomPanel != nil && CGRectContainsPoint(_bottomPanel.frame, point))
		return YES;
	return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
		shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other
{
	(void)recognizer;
	(void)other;
	return YES;
}

- (void)updateChrome
{
	NSDictionary *story = [self currentStory];

	_counterLabel.text = [NSString stringWithFormat:@"%d of %d",
			(int)(_index + 1), (int)_storyIds.count];
	_authorLabel.text = [self resolvedPosterName];

	int date = story != nil ? (int)TGStoryNumber(story, @"date") : 0;
	_dateLabel.text = date > 0 ? [TGDateUtils stringForLastSeen:date] : @"";

	_deleteButton.hidden = !(story != nil && TGStoryFlag(story, @"canDelete"));

	if ([self isOwnStory] && (story == nil || TGStoryFlag(story, @"canGetViewers")))
	{
		[_middleButton setTitle:[NSString stringWithFormat:@"%d views",
				(int)TGStoryNumber(story, @"views")] forState:UIControlStateNormal];
	}
	else
	{
		NSString *mine = story != nil ? TGStoryString(story, @"myReaction") : @"";
		[_middleButton setTitle:[NSString stringWithFormat:@"%@ %d",
				(mine.length > 0 ? mine : @"♥"),
				(int)TGStoryNumber(story, @"reactions")] forState:UIControlStateNormal];
	}

	BOOL canReply = story == nil ? YES : TGStoryFlag(story, @"canReply");
	_replyButton.enabled = canReply;
	_replyButton.alpha = canReply ? 1.0f : 0.5f;

	BOOL canForward = story == nil ? YES : TGStoryFlag(story, @"canForward");
	_shareButton.enabled = canForward;
	_shareButton.alpha = canForward ? 1.0f : 0.5f;
}

- (void)viewTapped:(UITapGestureRecognizer *)recognizer
{
	CGPoint point = [recognizer locationInView:self.view];
	if ([self pointIsOnChrome:point])
		return;

	if (_reactionPicker != nil && _reactionPicker.superview != nil)
	{
		[TGReactionPickerView dismiss];
		[self setModalPaused:NO];
		return;
	}

	[self setModalPaused:NO];

	TGStoryPage *page = [self pageForIndex:_index];
	if (page != nil && [self handleAreaTapOnPage:page atPoint:point])
		return;

	CGRect caption = [page captionFrame];
	if (page != nil && !CGRectIsEmpty(caption) &&
		CGRectContainsPoint([self.view convertRect:caption fromView:page], point))
	{
		NSDictionary *story = [self currentStory];
		NSString *text = story != nil ? TGStoryString(story, @"caption") : @"";
		if (text.length > 0)
		{
			TGStoryTextViewController *reader = [[TGStoryTextViewController alloc] init];
			reader.text = text;
			reader.title = [self resolvedPosterName];
			[self.navigationController pushViewController:reader animated:YES];
		}
		return;
	}

	CGFloat width = self.view.bounds.size.width;
	if (point.x < width / 3.0f)
	{
		if (_index > 0)
			[self showIndex:_index - 1 animated:YES];
		else
			[self movePosterBy:-1];
	}
	else if (point.x > width * 2.0f / 3.0f)
	{
		if (_index + 1 < (NSInteger)_storyIds.count)
			[self showIndex:_index + 1 animated:YES];
		else
			[self movePosterBy:1];
	}
}

- (BOOL)handleAreaTapOnPage:(TGStoryPage *)page atPoint:(CGPoint)point
{
	CGPoint local = [self.view convertPoint:point toView:page];
	NSDictionary *area = [page areaAtPoint:local];
	if (area == nil)
		return NO;

	NSString *kind = TGStoryString(area, @"kind");

	if ([kind isEqualToString:@"link"])
	{
		NSString *link = TGStoryString(area, @"url");
		if (link.length == 0)
			return NO;
		[self openLink:link];
		return YES;
	}

	if ([kind isEqualToString:@"reaction"])
	{
		NSString *emoji = TGStoryString(area, @"emoji");
		if (emoji.length == 0)
			return NO;
		[self sendReaction:emoji];
		return YES;
	}

	if ([kind isEqualToString:@"message"])
	{
		return NO;
	}

	return NO;
}

- (void)openLink:(NSString *)link
{
	NSURL *url = [NSURL URLWithString:link];
	if ([link rangeOfString:@"/s/"].location == NSNotFound &&
		[link rangeOfString:@"story"].location == NSNotFound)
	{
		if (url != nil)
			[[UIApplication sharedApplication] openURL:url];
		return;
	}

	__weak TGStoriesViewController *weakSelf = self;
	[[TGClient shared] resolveStoryLink:link completion:^(int64_t chatId, NSInteger storyId)
	{
		TGStoriesViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		if (chatId == 0 || storyId == 0)
		{
			if (url != nil)
				[[UIApplication sharedApplication] openURL:url];
			return;
		}
		TGStoriesViewController *viewer = [[TGStoriesViewController alloc]
				initWithChatId:chatId
					  storyIds:[NSArray arrayWithObject:[NSNumber numberWithInteger:storyId]]
					startIndex:0];
		[strongSelf.navigationController pushViewController:viewer animated:YES];
	}];
}

- (NSString *)hashtagInCaption
{
	NSDictionary *story = [self currentStory];
	NSString *caption = story != nil ? TGStoryString(story, @"caption") : @"";
	NSRange hash = [caption rangeOfString:@"#"];
	if (hash.location == NSNotFound || hash.location + 1 >= caption.length)
		return nil;

	NSCharacterSet *stop = [NSCharacterSet characterSetWithCharactersInString:@" \n\t,.!?;:#"];
	NSRange rest = NSMakeRange(hash.location + 1, caption.length - hash.location - 1);
	NSRange end = [caption rangeOfCharacterFromSet:stop options:0 range:rest];
	NSUInteger length = (end.location == NSNotFound)
			? rest.length
			: end.location - rest.location;
	if (length == 0)
		return nil;
	return [caption substringWithRange:NSMakeRange(rest.location, length)];
}

#pragma mark - actions

- (void)sendReaction:(NSString *)emoji
{
	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;

	NSString *value = emoji ?: @"";
	[[TGClient shared] reactToStory:storyId inChat:_chatId emoji:value];

	NSDictionary *story = [self currentStory];
	if (story == nil)
		return;

	NSString *mine = TGStoryString(story, @"myReaction");
	NSInteger count = TGStoryNumber(story, @"reactions");
	NSInteger delta = 0;
	if (mine.length == 0 && value.length > 0)
		delta = 1;
	else if (mine.length > 0 && value.length == 0)
		delta = -1;

	NSMutableDictionary *patched = [story mutableCopy];
	[patched setObject:value forKey:@"myReaction"];
	[patched setObject:[NSNumber numberWithInteger:MAX(0, count + delta)] forKey:@"reactions"];
	[_stories setObject:patched forKey:[_storyIds objectAtIndex:(NSUInteger)_index]];
	[self updateChrome];
}

- (void)replyPressed
{
	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;

	int64_t chatId = _chatId;
	[self setModalPaused:YES];
	__weak TGStoriesViewController *weakSelf = self;
	TGAlertView *alert = nil;
	__block __weak TGAlertView *weakAlert = nil;
	alert = [[TGAlertView alloc] initWithTitle:nil
									   message:@"Reply"
							 cancelButtonTitle:@"Cancel"
								 okButtonTitle:@"Send"
							   completionBlock:^(bool okButtonPressed)
	{
		[weakSelf setModalPaused:NO];
		if (!okButtonPressed)
			return;
		NSString *text = nil;
		if ([weakAlert respondsToSelector:@selector(textFieldAtIndex:)])
			text = [weakAlert textFieldAtIndex:0].text;
		if (text.length == 0)
			return;
		[[TGClient shared] replyToStory:storyId inChat:chatId text:text];
	}];
	weakAlert = alert;
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	[alert show];
}

- (void)middlePressed
{
	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;

	NSDictionary *story = [self currentStory];
	if ([self isOwnStory] && (story == nil || TGStoryFlag(story, @"canGetViewers")))
	{
		TGStoryViewersViewController *viewers = [[TGStoryViewersViewController alloc] init];
		viewers.storyId = storyId;
		viewers.chatId = _chatId;
		[self.navigationController pushViewController:viewers animated:YES];
		return;
	}

	NSString *mine = story != nil ? TGStoryString(story, @"myReaction") : @"";
	[self sendReaction:(mine.length > 0) ? @"" : @"❤"];
}

- (void)middleHeld:(UILongPressGestureRecognizer *)recognizer
{
	if (recognizer.state != UIGestureRecognizerStateBegan)
		return;
	if ([self currentStoryId] == 0)
		return;

	NSDictionary *story = [self currentStory];
	if ([self isOwnStory] && (story == nil || TGStoryFlag(story, @"canGetViewers")))
		return;
	UIView *host = self.view;
	CGRect anchor = [host convertRect:_middleButton.bounds fromView:_middleButton];
	__weak TGStoriesViewController *weakSelf = self;

	[self setModalPaused:YES];
	[[TGClient shared] storyReactionsWithLimit:12 completion:^(NSArray *emoji)
	{
		TGStoriesViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		if (![emoji isKindOfClass:[NSArray class]] || emoji.count == 0)
		{
			[strongSelf setModalPaused:NO];
			return;
		}

		TGReactionPickerView *picker =
				[TGReactionPickerView showForMessage:0
											  inChat:0
											fromRect:anchor
											  inView:host
											  picked:^(NSString *chosen, BOOL nowChosen)
		{
			(void)nowChosen;
			TGStoriesViewController *inner = weakSelf;
			if (inner == nil)
				return;
			[inner setModalPaused:NO];
			if (chosen.length > 0)
				[inner sendReaction:chosen];
		}];
		if (picker == nil)
		{
			[strongSelf setModalPaused:NO];
			return;
		}
		strongSelf->_reactionPicker = picker;
		[picker setEmoji:emoji reason:nil];
	}];
}

- (void)sharePressed
{
	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;

	NSDictionary *me = [[TGClient shared] me];
	if (me == nil)
		return;
	int64_t myId = TGStoryChatId(me, @"id");
	int64_t chatId = _chatId;

	[self setModalPaused:YES];
	__weak TGStoriesViewController *weakSelf = self;
	[[[TGAlertView alloc] initWithTitle:nil
								message:@"Repost this story to your own?"
					  cancelButtonTitle:@"Cancel"
						  okButtonTitle:@"Repost"
						completionBlock:^(bool okButtonPressed)
	{
		[weakSelf setModalPaused:NO];
		if (!okButtonPressed)
			return;
		[[TGClient shared] repostStory:storyId
							  fromChat:chatId
								asChat:myId
							   caption:@""
							   privacy:@"everyone"
							completion:nil];
	}] show];
}

- (NSMutableArray *)moreActions
{
	NSDictionary *story = [self currentStory];
	NSMutableArray *actions = [[NSMutableArray alloc] init];

	if ([self currentImage] != nil)
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Save to Photos"
															  action:@"save"]];
	}

	if (![self isOwnStory])
		[self appendOtherPosterActionsTo:actions];

	NSString *hashtag = [self hashtagInCaption];
	if (hashtag.length > 0)
	{
		[actions addObject:[[TGActionSheetAction alloc]
				initWithTitle:[NSString stringWithFormat:@"Search #%@", hashtag]
					   action:@"hashtag"]];
	}

	[self appendStoryStateActionsTo:actions story:story];

	return actions;
}

- (void)appendOtherPosterActionsTo:(NSMutableArray *)actions
{
	if ([self unreadStoryIds].count > 0)
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Mark All as Read"
															   action:@"markread"]];
	}
	NSString *hide = [NSString stringWithFormat:@"Hide Stories from %@",
			[self resolvedPosterName]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:hide action:@"hide"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Report" action:@"report"]];
}

- (void)appendStoryStateActionsTo:(NSMutableArray *)actions story:(NSDictionary *)story
{
	if (story != nil && TGStoryNumber(story, @"forwards") > 0)
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Reposts"
															   action:@"forwards"]];
	}

	if (story != nil && TGStoryFlag(story, @"canEdit"))
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Replace Photo"
															   action:@"replace"]];
	}

	if ([[TGClient shared] me] != nil)
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"My Stories"
															   action:@"mystories"]];
	}

	if (story != nil && TGStoryFlag(story, @"canToggleProfile"))
	{
		NSString *title = TGStoryFlag(story, @"onProfile")
				? @"Remove from Profile"
				: @"Save to Profile";
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:title action:@"profile"]];
	}

	if (story != nil && TGStoryFlag(story, @"canSetPrivacy"))
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Who Can See"
															   action:@"privacy"]];
	}

	if (story != nil && TGStoryFlag(story, @"canDelete"))
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Delete"
															  action:@"delete"
																type:TGActionSheetActionTypeDestructive]];
	}
}

- (void)morePressed
{
	NSArray *actions = [self moreActions];

	if (actions.count == 0)
		return;

	[self setModalPaused:YES];
	__weak TGStoriesViewController *weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:nil
													   actions:actions
												   actionBlock:^(id target, NSString *action)
	{
		(void)target;
		[weakSelf performMoreAction:action];
	}
														target:self];
	[sheet showInView:self.view];
}

- (void)askStoryPrivacy
{
	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;

	NSArray *titles = [NSArray arrayWithObjects:
			@"Everyone", @"My Contacts", @"Close Friends", @"Selected Contacts", nil];
	NSArray *values = [NSArray arrayWithObjects:
			@"everyone", @"contacts", @"closeFriends", @"selected", nil];

	NSMutableArray *actions = [[NSMutableArray alloc] init];
	for (NSString *title in titles)
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:title action:title]];

	[self setModalPaused:YES];
	__weak TGStoriesViewController *weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:@"Who can see this story?"
													   actions:actions
												   actionBlock:^(id target, NSString *action)
	{
		(void)target;
		TGStoriesViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		NSUInteger index = [titles indexOfObject:action];
		if (index == NSNotFound)
		{
			[strongSelf setModalPaused:NO];
			return;
		}
		NSString *privacy = [values objectAtIndex:index];
		if (![privacy isEqualToString:@"selected"])
		{
			[strongSelf setModalPaused:NO];
			[[TGClient shared] setStory:storyId privacy:privacy userIds:nil];
			return;
		}

		[TGStoryContactPicker presentFrom:strongSelf
									title:@"Selected Contacts"
							  preselected:nil
								   picked:^(NSArray *userIds)
		{
			TGStoriesViewController *inner = weakSelf;
			if (inner == nil)
				return;
			[inner setModalPaused:NO];
			if (userIds.count == 0)
				return;
			[[TGClient shared] setStory:storyId privacy:@"selected" userIds:userIds];
		}];
	}
														target:self];
	[sheet showInView:self.view];
}

- (void)performMoreAction:(NSString *)action
{
	[self setModalPaused:NO];

	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;

	if ([action isEqualToString:@"save"])
	{
		[self saveCurrentImageToPhotos];
		return;
	}

	if ([action isEqualToString:@"profile"])
	{
		[self toggleOnProfileForStoryId:storyId];
		return;
	}

	if ([action isEqualToString:@"privacy"])
	{
		[self askStoryPrivacy];
		return;
	}

	if ([action isEqualToString:@"hide"])
	{
		[self hideStoriesFromCurrentPoster];
		return;
	}

	if ([action isEqualToString:@"delete"])
	{
		[self confirmDeleteStoryId:storyId];
		return;
	}

	if ([action isEqualToString:@"report"])
	{
		_reportOptionId = nil;
		[self reportWithOptionId:nil text:nil];
		return;
	}

	if ([action isEqualToString:@"markread"])
	{
		[self markRemainingRead];
		return;
	}

	if ([action isEqualToString:@"hashtag"])
	{
		[self openHashtagSearch];
		return;
	}

	if ([action isEqualToString:@"forwards"])
	{
		[self openForwardsListForStoryId:storyId];
		return;
	}

	if ([action isEqualToString:@"replace"])
	{
		[self replacePhoto];
		return;
	}

	if ([action isEqualToString:@"mystories"])
	{
		[self openMyStories];
		return;
	}
}

- (void)saveCurrentImageToPhotos
{
	UIImage *image = [self currentImage];
	if (image != nil)
		UIImageWriteToSavedPhotosAlbum(image, nil, NULL, NULL);
}

- (void)hideStoriesFromCurrentPoster
{
	[[TGClient shared] setUser:_chatId storiesHidden:YES];
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)toggleOnProfileForStoryId:(NSInteger)storyId
{
	NSDictionary *story = [self currentStory];
	BOOL onProfile = !TGStoryFlag(story, @"onProfile");
	[[TGClient shared] setStory:storyId inChat:_chatId onProfile:onProfile];
	if (story != nil)
	{
		NSMutableDictionary *patched = [story mutableCopy];
		[patched setObject:[NSNumber numberWithBool:onProfile] forKey:@"onProfile"];
		[_stories setObject:patched forKey:[_storyIds objectAtIndex:(NSUInteger)_index]];
	}
}

- (void)confirmDeleteStoryId:(NSInteger)storyId
{
	int64_t chatId = _chatId;
	__weak TGStoriesViewController *weakSelf = self;
	[[[TGAlertView alloc] initWithTitle:nil
								message:@"Delete this story?"
					  cancelButtonTitle:@"Cancel"
						  okButtonTitle:@"Delete"
						completionBlock:^(bool okButtonPressed)
	{
		if (!okButtonPressed)
			return;
		[[TGClient shared] deleteStory:storyId inChat:chatId];
		[weakSelf.navigationController popViewControllerAnimated:YES];
	}] show];
}

- (void)openHashtagSearch
{
	NSString *hashtag = [self hashtagInCaption];
	if (hashtag.length == 0 || self.navigationController == nil)
		return;
	TGStoryListViewController *list = [[TGStoryListViewController alloc] init];
	list.mode = TGStoryListTag;
	list.tag = hashtag;
	list.title = [NSString stringWithFormat:@"#%@", hashtag];
	[self.navigationController pushViewController:list animated:YES];
}

- (void)openForwardsListForStoryId:(NSInteger)storyId
{
	if (self.navigationController == nil)
		return;
	TGStoryListViewController *list = [[TGStoryListViewController alloc] init];
	list.mode = TGStoryListForwards;
	list.chatId = _chatId;
	list.storyId = storyId;
	list.title = @"Reposts";
	[self.navigationController pushViewController:list animated:YES];
}

- (void)openMyStories
{
	NSDictionary *me = [[TGClient shared] me];
	if (me == nil)
		return;
	[TGStoryListViewController pushMode:TGStoryListMenu
								 chatId:TGStoryChatId(me, @"id")
								  title:@"My Stories"
								   from:self];
}

- (NSArray *)unreadStoryIds
{
	NSMutableArray *unread = [[NSMutableArray alloc] init];
	for (NSNumber *key in _storyIds)
	{
		if (![_seen containsObject:key])
			[unread addObject:key];
	}
	return unread;
}

- (void)markRemainingRead
{
	NSArray *unread = [self unreadStoryIds];
	for (NSNumber *key in unread)
	{
		[[TGClient shared] markStoryRead:[key integerValue] inChat:_chatId];
		[_seen addObject:key];
	}
	[self updateStrip];
}

- (void)replacePhoto
{
	if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary])
	{
		[[[TGAlertView alloc] initWithTitle:nil
									message:@"No photo library"
						  cancelButtonTitle:@"OK"
							  okButtonTitle:nil
							completionBlock:nil] show];
		return;
	}

	[self setModalPaused:YES];
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.allowsEditing = YES;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
	(void)picker;
	[self dismissViewControllerAnimated:YES completion:nil];
	[self setModalPaused:NO];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info
{
	(void)picker;
	[self dismissViewControllerAnimated:YES completion:nil];
	[self setModalPaused:NO];

	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;

	UIImage *image = [info objectForKey:UIImagePickerControllerEditedImage];
	if (![image isKindOfClass:[UIImage class]])
		image = [info objectForKey:UIImagePickerControllerOriginalImage];
	if (![image isKindOfClass:[UIImage class]])
		return;

	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"storyedit.jpg"];
	BOOL written = NO;

	@autoreleasepool
	{
		CGFloat side = MAX(image.size.width, image.size.height);
		UIImage *scaled = image;
		if (side > 720.0f)
		{
			CGFloat factor = 720.0f / side;
			CGSize target = CGSizeMake(floorf(image.size.width * factor),
									   floorf(image.size.height * factor));
			UIGraphicsBeginImageContextWithOptions(target, YES, 1.0f);
			[image drawInRect:CGRectMake(0, 0, target.width, target.height)];
			scaled = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
		}
		image = nil;

		NSData *data = UIImageJPEGRepresentation(scaled, 0.87f);
		scaled = nil;
		if (data.length != 0)
			written = [data writeToFile:path atomically:YES];
	}

	if (!written)
	{
		[[[TGAlertView alloc] initWithTitle:nil
									message:@"Could not prepare the photo"
						  cancelButtonTitle:@"OK"
							  okButtonTitle:nil
							completionBlock:nil] show];
		return;
	}

	[self applyReplacementPhotoAtPath:path forStoryId:storyId];
}

- (void)applyReplacementPhotoAtPath:(NSString *)path forStoryId:(NSInteger)storyId
{
	NSDictionary *story = [self currentStory];
	NSString *caption = story != nil ? TGStoryString(story, @"caption") : @"";
	[[TGClient shared] editStory:storyId inChat:_chatId photoPath:path caption:caption];

	NSNumber *key = [self currentStoryKey];
	int64_t chatId = _chatId;
	__weak TGStoriesViewController *weakSelf = self;
	[[TGClient shared] storyWithId:storyId inChat:chatId completion:^(NSDictionary *updated)
	{
		TGStoriesViewController *strongSelf = weakSelf;
		if (strongSelf == nil || key == nil || strongSelf->_chatId != chatId)
			return;
		if (![updated isKindOfClass:[NSDictionary class]])
			return;
		[strongSelf->_stories setObject:updated forKey:key];
		TGStoryPage *page = [strongSelf pageForIndex:strongSelf->_index];
		if (page != nil && [page.itemId isEqual:key])
		{
			[page setCaption:TGStoryString(updated, @"caption")];
			[page setAreas:[updated objectForKey:@"areas"]];
			[strongSelf loadPhotoForPage:page story:updated];
		}
		[strongSelf updateChrome];
	}];
}

- (void)reportWithOptionId:(NSString *)optionId text:(NSString *)text
{
	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;

	__weak TGStoriesViewController *weakSelf = self;
	[[TGClient shared] reportStory:storyId
							inChat:_chatId
						  optionId:optionId
							  text:text
						completion:^(NSDictionary *result)
	{
		TGStoriesViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		[strongSelf handleReportResult:result];
	}];
}

- (void)handleReportResult:(NSDictionary *)result
{
	NSString *status = TGStoryString(result, @"status");

	if ([status isEqualToString:@"ok"])
	{
		[[[TGAlertView alloc] initWithTitle:nil
									message:@"Thank you"
						  cancelButtonTitle:@"OK"
							  okButtonTitle:nil
							completionBlock:nil] show];
		return;
	}

	if ([status isEqualToString:@"option"])
	{
		[self presentReportOptions:result];
		return;
	}

	if ([status isEqualToString:@"text"])
	{
		[self askReportComment];
		return;
	}

	[[[TGAlertView alloc] initWithTitle:nil
								message:@"Could not report this story"
					  cancelButtonTitle:@"OK"
						  okButtonTitle:nil
						completionBlock:nil] show];
}

- (void)presentReportOptions:(NSDictionary *)result
{
	NSArray *options = [result objectForKey:@"options"];
	if (![options isKindOfClass:[NSArray class]] || options.count == 0)
		return;

	NSMutableArray *actions = [[NSMutableArray alloc] init];
	NSMutableDictionary *byTitle = [[NSMutableDictionary alloc] init];
	for (NSDictionary *option in options)
	{
		if (![option isKindOfClass:[NSDictionary class]])
			continue;
		NSString *title = TGStoryString(option, @"text");
		NSString *identifier = TGStoryString(option, @"id");
		if (title.length == 0)
			continue;
		[byTitle setObject:identifier forKey:title];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:title action:title]];
	}
	if (actions.count == 0)
		return;

	__weak TGStoriesViewController *weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:TGStoryString(result, @"title")
													   actions:actions
												   actionBlock:^(id target, NSString *action)
	{
		(void)target;
		TGStoriesViewController *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		NSString *identifier = [byTitle objectForKey:action];
		if (identifier == nil)
			return;
		strongSelf->_reportOptionId = identifier;
		[strongSelf reportWithOptionId:identifier text:nil];
	}
														target:self];
	[sheet showInView:self.view];
}

- (void)askReportComment
{
	NSString *optionId = _reportOptionId;
	__weak TGStoriesViewController *weakSelf = self;
	TGAlertView *alert = nil;
	__block __weak TGAlertView *weakAlert = nil;
	alert = [[TGAlertView alloc] initWithTitle:nil
									   message:@"Add a comment"
							 cancelButtonTitle:@"Cancel"
								 okButtonTitle:@"Send"
							   completionBlock:^(bool okButtonPressed)
	{
		if (!okButtonPressed)
			return;
		NSString *text = nil;
		if ([weakAlert respondsToSelector:@selector(textFieldAtIndex:)])
			text = [weakAlert textFieldAtIndex:0].text;
		[weakSelf reportWithOptionId:optionId text:(text ?: @"")];
	}];
	weakAlert = alert;
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	[alert show];
}

@end

@interface TGStoryComposer () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
{
	UIViewController *_host;
	int64_t _asChatId;
	NSString *_path;
	NSString *_caption;
	void (^_completion)(BOOL posted);
}
@end

static NSMutableArray *TGStoryComposersInFlight(void)
{
	static NSMutableArray *composers = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ composers = [[NSMutableArray alloc] init]; });
	return composers;
}

@implementation TGStoryComposer

+ (void)presentFrom:(UIViewController *)controller
		 completion:(void (^)(BOOL posted))completion
{
	if (controller == nil)
		return;
	TGStoryComposer *composer = [[TGStoryComposer alloc] init];
	composer->_host = controller;
	composer->_completion = [completion copy];
	[TGStoryComposersInFlight() addObject:composer];
	[composer chooseChat];
}

- (void)finishPosted:(BOOL)posted
{
	void (^completion)(BOOL) = _completion;
	_completion = nil;
	if (completion != nil)
		completion(posted);
	[TGStoryComposersInFlight() removeObject:self];
}

- (void)chooseChat
{
	__weak TGStoryComposer *weakSelf = self;
	[[TGClient shared] chatsToPostStoriesWithCompletion:^(NSArray *chats)
	{
		TGStoryComposer *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;

		if (![chats isKindOfClass:[NSArray class]] || chats.count == 0)
		{
			[[[TGAlertView alloc] initWithTitle:nil
										message:@"You cannot post a story"
							  cancelButtonTitle:@"OK"
								  okButtonTitle:nil
								completionBlock:nil] show];
			[strongSelf finishPosted:NO];
			return;
		}

		if (chats.count == 1)
		{
			id chat = [chats objectAtIndex:0];
			if (![chat isKindOfClass:[NSDictionary class]])
			{
				[strongSelf finishPosted:NO];
				return;
			}
			[strongSelf checkChat:TGStoryChatId(chat, @"id")];
			return;
		}

		[strongSelf presentChatChooserForChats:chats];
	}];
}

- (void)presentChatChooserForChats:(NSArray *)chats
{
	NSMutableArray *actions = [[NSMutableArray alloc] init];
	NSMutableDictionary *byTitle = [[NSMutableDictionary alloc] init];
	for (NSDictionary *chat in chats)
	{
		if (![chat isKindOfClass:[NSDictionary class]])
			continue;
		NSString *title = TGStoryString(chat, @"title");
		if (title.length == 0)
			continue;
		[byTitle setObject:[chat objectForKey:@"id"] forKey:title];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:title action:title]];
	}

	__weak TGStoryComposer *weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:@"Post story as"
													   actions:actions
												   actionBlock:^(id target, NSString *action)
	{
		(void)target;
		TGStoryComposer *inner = weakSelf;
		if (inner == nil)
			return;
		NSNumber *identifier = [byTitle objectForKey:action];
		if (identifier == nil)
		{
			[inner finishPosted:NO];
			return;
		}
		[inner checkChat:(int64_t)[identifier longLongValue]];
	}
														target:self];
	[sheet showInView:_host.view];
}

- (void)checkChat:(int64_t)chatId
{
	_asChatId = chatId;
	__weak TGStoryComposer *weakSelf = self;
	[[TGClient shared] canPostStoryAsChat:chatId completion:^(BOOL canPost, NSString *reason)
	{
		TGStoryComposer *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		if (!canPost)
		{
			[[[TGAlertView alloc] initWithTitle:nil
										message:(reason.length > 0 ? reason : @"You cannot post a story")
							  cancelButtonTitle:@"OK"
								  okButtonTitle:nil
								completionBlock:nil] show];
			[strongSelf finishPosted:NO];
			return;
		}
		[strongSelf pickPhoto];
	}];
}

- (void)pickPhoto
{
	if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary])
	{
		[self finishPosted:NO];
		return;
	}

	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.allowsEditing = YES;
	picker.delegate = self;
	[_host presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
	(void)picker;
	[_host dismissViewControllerAnimated:YES completion:nil];
	[self finishPosted:NO];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info
{
	(void)picker;
	[_host dismissViewControllerAnimated:YES completion:nil];

	UIImage *image = [info objectForKey:UIImagePickerControllerEditedImage];
	if (![image isKindOfClass:[UIImage class]])
		image = [info objectForKey:UIImagePickerControllerOriginalImage];
	if (![image isKindOfClass:[UIImage class]])
	{
		[self finishPosted:NO];
		return;
	}

	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"story.jpg"];
	BOOL written = NO;

	@autoreleasepool
	{
		CGFloat side = MAX(image.size.width, image.size.height);
		UIImage *scaled = image;
		if (side > 720.0f)
		{
			CGFloat factor = 720.0f / side;
			CGSize target = CGSizeMake(floorf(image.size.width * factor),
									   floorf(image.size.height * factor));
			UIGraphicsBeginImageContextWithOptions(target, YES, 1.0f);
			[image drawInRect:CGRectMake(0, 0, target.width, target.height)];
			scaled = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
		}
		image = nil;

		NSData *data = UIImageJPEGRepresentation(scaled, 0.87f);
		scaled = nil;
		if (data.length != 0)
			written = [data writeToFile:path atomically:YES];
	}

	if (!written)
	{
		[self finishPosted:NO];
		return;
	}
	_path = path;
	[self askCaption];
}

- (void)askCaption
{
	__weak TGStoryComposer *weakSelf = self;
	TGAlertView *alert = nil;
	__block __weak TGAlertView *weakAlert = nil;
	alert = [[TGAlertView alloc] initWithTitle:nil
									   message:@"Caption"
							 cancelButtonTitle:@"Skip"
								 okButtonTitle:@"Next"
							   completionBlock:^(bool okButtonPressed)
	{
		TGStoryComposer *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		NSString *text = nil;
		if (okButtonPressed && [weakAlert respondsToSelector:@selector(textFieldAtIndex:)])
			text = [weakAlert textFieldAtIndex:0].text;
		strongSelf->_caption = text ?: @"";
		[strongSelf askPrivacy];
	}];
	weakAlert = alert;
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	[alert show];
}

- (void)askPrivacy
{
	NSArray *titles = [NSArray arrayWithObjects:
			@"Everyone", @"My Contacts", @"Close Friends", @"Selected Contacts", nil];
	NSArray *values = [NSArray arrayWithObjects:
			@"everyone", @"contacts", @"closeFriends", @"selected", nil];

	NSMutableArray *actions = [[NSMutableArray alloc] init];
	for (NSString *title in titles)
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:title action:title]];

	__weak TGStoryComposer *weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc] initWithTitle:@"Who can see this story?"
													   actions:actions
												   actionBlock:^(id target, NSString *action)
	{
		(void)target;
		TGStoryComposer *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		NSUInteger index = [titles indexOfObject:action];
		if (index == NSNotFound)
		{
			[strongSelf finishPosted:NO];
			return;
		}
		NSString *privacy = [values objectAtIndex:index];
		if (![privacy isEqualToString:@"selected"])
		{
			[strongSelf postWithPrivacy:privacy];
			return;
		}

		[TGStoryContactPicker presentFrom:strongSelf->_host
									title:@"Selected Contacts"
							  preselected:nil
								   picked:^(NSArray *userIds)
		{
			TGStoryComposer *inner = weakSelf;
			if (inner == nil)
				return;
			if (userIds.count == 0)
			{
				[inner finishPosted:NO];
				return;
			}
			[inner postWithPrivacy:@"selected" userIds:userIds];
		}];
	}
														target:self];
	[sheet showInView:_host.view];
}

- (void)postWithPrivacy:(NSString *)privacy
{
	[self postWithPrivacy:privacy userIds:nil];
}

- (void)postWithPrivacy:(NSString *)privacy userIds:(NSArray *)userIds
{
	__weak TGStoryComposer *weakSelf = self;
	[[TGClient shared] postPhotoStoryAtPath:_path
									 asChat:_asChatId
									caption:(_caption ?: @"")
									privacy:privacy
									userIds:userIds
								  toProfile:NO
								 completion:^(NSDictionary *story)
	{
		TGStoryComposer *strongSelf = weakSelf;
		if (strongSelf == nil)
			return;
		BOOL posted = [story isKindOfClass:[NSDictionary class]];
		if (!posted)
		{
			[[[TGAlertView alloc] initWithTitle:nil
										message:@"Could not post the story"
							  cancelButtonTitle:@"OK"
								  okButtonTitle:nil
								completionBlock:nil] show];
		}
		[strongSelf finishPosted:posted];
	}];
}

@end

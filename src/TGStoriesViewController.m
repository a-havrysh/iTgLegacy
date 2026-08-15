#import "TGStoriesViewController.h"

#import "TGClient.h"
#import "TGClient+Stories.h"
#import "TGClient+Files.h"
#import "TGActionSheet.h"
#import "TGAlertView.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGImageDecode.h"

static const CGFloat TGStoryStripHeight = 3.0f;
static const CGFloat TGStoryStripInset = 4.0f;
static const CGFloat TGStoryStripGap = 2.0f;
static const CGFloat TGStoryStripTop = 2.0f;
static const CGFloat TGStoryPhotoTop = 12.0f;
static const CGFloat TGStoryFooterHeight = 30.0f;
static const CGFloat TGStoryFooterInset = 10.0f;
static const CGFloat TGStoryFooterBottom = 10.0f;
static const CGFloat TGStoryCaptionHeight = 50.0f;
static const NSInteger TGStoryPhotoPixels = 640;

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
	NSTimeInterval delta = [[NSDate date] timeIntervalSince1970] - (NSTimeInterval)date;
	if (delta < 60.0)
		return @"just now";
	if (delta < 3600.0)
		return [NSString stringWithFormat:@"%d min ago", (int)(delta / 60.0)];
	if (delta < 86400.0)
		return [NSString stringWithFormat:@"%d h ago", (int)(delta / 3600.0)];
	return [NSString stringWithFormat:@"%d d ago", (int)(delta / 86400.0)];
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

@interface TGStoriesViewController ()
{
	NSArray *_storyIds;
	NSInteger _index;
	NSMutableDictionary *_stories;
	NSMutableSet *_seen;
	NSInteger _openStoryId;
	NSInteger _generation;

	UIView *_stripView;
	UIImageView *_photoView;
	UIView *_captionPlate;
	UILabel *_captionLabel;
	UIView *_footerView;
	UIButton *_replyButton;
	UIButton *_middleButton;
	UIButton *_shareButton;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	NSString *_reportOptionId;
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
	self.wantsFullScreenLayout = NO;

	[self buildTitleView];

	UIButton *more = [TGIcons headerButtonWithTitle:@"More"
											   bold:NO
											 target:self
											 action:@selector(morePressed)];
	if (more != nil)
		self.navigationItem.rightBarButtonItem =
				[[UIBarButtonItem alloc] initWithCustomView:more];

	_stripView = [[UIView alloc] initWithFrame:CGRectZero];
	_stripView.backgroundColor = [UIColor clearColor];
	[self.view addSubview:_stripView];

	_photoView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_photoView.backgroundColor = [UIColor blackColor];
	_photoView.contentMode = UIViewContentModeScaleAspectFit;
	_photoView.userInteractionEnabled = NO;
	[self.view addSubview:_photoView];

	_captionPlate = [[UIView alloc] initWithFrame:CGRectZero];
	_captionPlate.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.45f];
	_captionPlate.hidden = YES;
	[self.view addSubview:_captionPlate];

	_captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_captionLabel.backgroundColor = [UIColor clearColor];
	_captionLabel.textColor = [UIColor whiteColor];
	_captionLabel.font = [UIFont systemFontOfSize:15];
	_captionLabel.numberOfLines = 2;
	_captionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[_captionPlate addSubview:_captionLabel];

	[self buildFooter];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(viewTapped:)];
	[self.view addGestureRecognizer:tap];

	[self showIndex:_index animated:NO];
}

- (void)buildTitleView
{
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 40)];

	_titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, 200, 19)];
	_titleLabel.font = [UIFont boldSystemFontOfSize:16];
	_titleLabel.textColor = [[TGTheme shared] barTitleColour];
	_titleLabel.backgroundColor = [UIColor clearColor];
	_titleLabel.textAlignment = NSTextAlignmentCenter;
	if (![TGTheme shared].isFlat)
	{
		_titleLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.4f];
		_titleLabel.shadowOffset = CGSizeMake(0, -1);
	}
	_titleLabel.text = [self resolvedPosterName];
	[header addSubview:_titleLabel];

	_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 21, 200, 16)];
	_subtitleLabel.font = [UIFont systemFontOfSize:13];
	_subtitleLabel.textColor = [TGTheme shared].isFlat
			? [[TGTheme shared] secondaryTextColour]
			: [UIColor colorWithRed:0.878f green:0.933f blue:0.992f alpha:1.0f];
	_subtitleLabel.backgroundColor = [UIColor clearColor];
	_subtitleLabel.textAlignment = NSTextAlignmentCenter;
	[header addSubview:_subtitleLabel];

	self.navigationItem.titleView = header;
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

	CGFloat footerY = height - TGStoryFooterBottom - TGStoryFooterHeight;
	_footerView.frame = CGRectMake(TGStoryFooterInset, footerY,
								   width - TGStoryFooterInset * 2.0f, TGStoryFooterHeight);
	[self layoutFooter];

	_stripView.frame = CGRectMake(0, TGStoryStripTop, width, TGStoryStripHeight);
	[self layoutStrip];

	CGFloat areaTop = TGStoryPhotoTop;
	CGFloat areaHeight = footerY - 8.0f - areaTop;
	[self layoutPhotoInArea:CGRectMake(0, areaTop, width, areaHeight)];
}

- (void)layoutFooter
{
	CGRect bounds = _footerView.bounds;
	CGFloat total = bounds.size.width;
	CGFloat seam = 2.0f;
	CGFloat first = floorf((total - seam * 2.0f) / 3.0f) + 2.0f;
	CGFloat middle = total - seam * 2.0f - first * 2.0f;

	_replyButton.frame = CGRectMake(0, 0, first, TGStoryFooterHeight);
	UIView *leftSeam = [_footerView viewWithTag:900];
	leftSeam.frame = CGRectMake(first, 0, seam, TGStoryFooterHeight);
	_middleButton.frame = CGRectMake(first + seam, 0, middle, TGStoryFooterHeight);
	UIView *rightSeam = [_footerView viewWithTag:901];
	rightSeam.frame = CGRectMake(first + seam + middle, 0, seam, TGStoryFooterHeight);
	_shareButton.frame = CGRectMake(first + seam * 2.0f + middle, 0, first, TGStoryFooterHeight);
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
			bar.backgroundColor = [UIColor whiteColor];
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
		BOOL seen = [_seen containsObject:[_storyIds objectAtIndex:i]];
		bar.alpha = seen ? 1.0f : 0.3f;
	}
}

- (void)layoutPhotoInArea:(CGRect)area
{
	CGSize size = _photoView.image != nil ? _photoView.image.size : CGSizeMake(9.0f, 16.0f);
	if (size.width <= 0.0f || size.height <= 0.0f)
		size = CGSizeMake(9.0f, 16.0f);

	CGFloat scale = MIN(area.size.width / size.width, area.size.height / size.height);
	CGFloat drawWidth = floorf(size.width * scale);
	CGFloat drawHeight = floorf(size.height * scale);
	CGRect frame = CGRectMake(area.origin.x + floorf((area.size.width - drawWidth) / 2.0f),
							  area.origin.y + floorf((area.size.height - drawHeight) / 2.0f),
							  drawWidth, drawHeight);
	_photoView.frame = frame;

	CGFloat plateHeight = MIN(TGStoryCaptionHeight, drawHeight);
	_captionPlate.frame = CGRectMake(frame.origin.x,
									 CGRectGetMaxY(frame) - plateHeight,
									 frame.size.width, plateHeight);
	_captionLabel.frame = CGRectInset(_captionPlate.bounds, 8.0f, 6.0f);
}

#pragma mark - paging

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	if (_openStoryId == 0)
	{
		NSInteger storyId = [self currentStoryId];
		if (storyId != 0)
		{
			_openStoryId = storyId;
			[[TGClient shared] openStory:storyId inChat:_chatId];
		}
	}
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self closeCurrent];
}

- (void)closeCurrent
{
	if (_openStoryId != 0)
	{
		[[TGClient shared] closeStory:_openStoryId inChat:_chatId];
		_openStoryId = 0;
	}
}

- (void)showIndex:(NSInteger)index animated:(BOOL)animated
{
	if (index < 0 || index >= (NSInteger)_storyIds.count)
		return;

	[self closeCurrent];
	_index = index;
	_generation++;

	NSNumber *key = [_storyIds objectAtIndex:(NSUInteger)_index];
	[_seen addObject:key];
	_openStoryId = [key integerValue];
	[[TGClient shared] openStory:_openStoryId inChat:_chatId];

	[self updateStrip];
	[self updateChrome];

	NSDictionary *known = [self currentStory];
	if (known != nil)
	{
		[self loadPhotoForStory:known animated:animated];
		return;
	}

	NSInteger generation = _generation;
	__weak TGStoriesViewController *weakSelf = self;
	[[TGClient shared] storyWithId:[key integerValue]
							inChat:_chatId
						completion:^(NSDictionary *story)
	{
		TGStoriesViewController *strongSelf = weakSelf;
		if (strongSelf == nil || strongSelf->_generation != generation)
			return;
		if (![story isKindOfClass:[NSDictionary class]])
			return;
		[strongSelf->_stories setObject:story forKey:key];
		[strongSelf updateChrome];
		[strongSelf loadPhotoForStory:story animated:animated];
	}];
}

- (void)updateChrome
{
	NSDictionary *story = [self currentStory];

	_titleLabel.text = [self resolvedPosterName];
	NSString *position = [NSString stringWithFormat:@"%d of %d",
			(int)(_index + 1), (int)_storyIds.count];
	NSString *age = story != nil ? TGStoryAgeText((int)TGStoryNumber(story, @"date")) : @"";
	_subtitleLabel.text = age.length > 0
			? [NSString stringWithFormat:@"%@ · %@", position, age]
			: position;

	NSString *caption = story != nil ? TGStoryString(story, @"caption") : @"";
	_captionLabel.text = caption;
	_captionPlate.hidden = (caption.length == 0);

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

- (void)loadPhotoForStory:(NSDictionary *)story animated:(BOOL)animated
{
	NSNumber *photoId = [story objectForKey:@"photoId"];
	if (![photoId isKindOfClass:[NSNumber class]])
	{
		[self setPhoto:nil animated:animated];
		return;
	}

	NSInteger generation = _generation;
	__weak TGStoriesViewController *weakSelf = self;
	[[TGClient shared] downloadFile:[photoId integerValue]
							 offset:0
							  limit:0
						 completion:^(NSDictionary *file)
	{
		TGStoriesViewController *strongSelf = weakSelf;
		if (strongSelf == nil || strongSelf->_generation != generation)
			return;
		NSString *path = TGStoryString(file, @"path");
		if (path.length == 0)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^
		{
			UIImage *image = TGDecodeThumbnail(path, TGStoryPhotoPixels);
			dispatch_async(dispatch_get_main_queue(), ^
			{
				TGStoriesViewController *inner = weakSelf;
				if (inner == nil || inner->_generation != generation)
					return;
				[inner setPhoto:image animated:YES];
			});
		});
	}];
}

- (void)setPhoto:(UIImage *)image animated:(BOOL)animated
{
	if (animated && image != nil)
	{
		[UIView transitionWithView:_photoView
						  duration:0.15
						   options:UIViewAnimationOptionTransitionCrossDissolve
						animations:^{ _photoView.image = image; }
						completion:nil];
	}
	else
	{
		_photoView.image = image;
	}
	[self.view setNeedsLayout];
}

- (void)viewTapped:(UITapGestureRecognizer *)recognizer
{
	CGPoint point = [recognizer locationInView:self.view];
	if (CGRectContainsPoint(_footerView.frame, point))
		return;

	if (!_captionPlate.hidden && CGRectContainsPoint(_captionPlate.frame, point))
	{
		NSDictionary *story = [self currentStory];
		NSString *caption = story != nil ? TGStoryString(story, @"caption") : @"";
		if (caption.length > 0)
		{
			TGStoryTextViewController *text = [[TGStoryTextViewController alloc] init];
			text.text = caption;
			text.title = [self resolvedPosterName];
			[self.navigationController pushViewController:text animated:YES];
		}
		return;
	}

	CGFloat width = self.view.bounds.size.width;
	if (point.x < width * 0.4f)
	{
		if (_index > 0)
			[self showIndex:_index - 1 animated:YES];
	}
	else if (point.x > width * 0.6f)
	{
		if (_index + 1 < (NSInteger)_storyIds.count)
			[self showIndex:_index + 1 animated:YES];
	}
}

#pragma mark - actions

- (void)replyPressed
{
	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;

	int64_t chatId = _chatId;
	TGAlertView *alert = nil;
	__block __weak TGAlertView *weakAlert = nil;
	alert = [[TGAlertView alloc] initWithTitle:nil
									   message:@"Reply"
							 cancelButtonTitle:@"Cancel"
								 okButtonTitle:@"Send"
							   completionBlock:^(bool okButtonPressed)
	{
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
	NSString *emoji = (mine.length > 0) ? @"" : @"❤";
	[[TGClient shared] reactToStory:storyId inChat:_chatId emoji:emoji];

	if (story != nil)
	{
		NSMutableDictionary *patched = [story mutableCopy];
		NSInteger count = TGStoryNumber(story, @"reactions");
		[patched setObject:[NSString stringWithString:emoji] forKey:@"myReaction"];
		[patched setObject:[NSNumber numberWithInteger:MAX(0, count + (emoji.length > 0 ? 1 : -1))]
					forKey:@"reactions"];
		[_stories setObject:patched forKey:[_storyIds objectAtIndex:(NSUInteger)_index]];
		[self updateChrome];
	}
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

	[[[TGAlertView alloc] initWithTitle:nil
								message:@"Repost this story to your own?"
					  cancelButtonTitle:@"Cancel"
						  okButtonTitle:@"Repost"
						completionBlock:^(bool okButtonPressed)
	{
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

- (void)morePressed
{
	NSDictionary *story = [self currentStory];
	NSMutableArray *actions = [[NSMutableArray alloc] init];

	if (_photoView.image != nil)
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Save to Photos"
															  action:@"save"]];
	}

	if (![self isOwnStory])
	{
		NSString *hide = [NSString stringWithFormat:@"Hide Stories from %@",
				[self resolvedPosterName]];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:hide action:@"hide"]];
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Report" action:@"report"]];
	}

	if (story != nil && TGStoryFlag(story, @"canDelete"))
	{
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Delete"
															  action:@"delete"
																type:TGActionSheetActionTypeDestructive]];
	}

	if (actions.count == 0)
		return;

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

- (void)performMoreAction:(NSString *)action
{
	NSInteger storyId = [self currentStoryId];
	if (storyId == 0)
		return;

	if ([action isEqualToString:@"save"])
	{
		if (_photoView.image != nil)
			UIImageWriteToSavedPhotosAlbum(_photoView.image, nil, NULL, NULL);
		return;
	}

	if ([action isEqualToString:@"hide"])
	{
		[[TGClient shared] setUser:_chatId storiesHidden:YES];
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}

	if ([action isEqualToString:@"delete"])
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
		return;
	}

	if ([action isEqualToString:@"report"])
	{
		_reportOptionId = nil;
		[self reportWithOptionId:nil text:nil];
		return;
	}
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
		return;
	}

	if ([status isEqualToString:@"text"])
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
		return;
	}

	[[[TGAlertView alloc] initWithTitle:nil
								message:@"Could not report this story"
					  cancelButtonTitle:@"OK"
						  okButtonTitle:nil
						completionBlock:nil] show];
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
															target:strongSelf];
		[sheet showInView:strongSelf->_host.view];
	}];
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
		[[[TGAlertView alloc] initWithTitle:nil
									message:@"No photo library"
						  cancelButtonTitle:@"OK"
							  okButtonTitle:nil
							completionBlock:nil] show];
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

	NSData *data = UIImageJPEGRepresentation(scaled, 0.87f);
	if (data.length == 0)
	{
		[self finishPosted:NO];
		return;
	}

	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"story.jpg"];
	if (![data writeToFile:path atomically:YES])
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
	NSArray *titles = [NSArray arrayWithObjects:@"Everyone", @"My Contacts", @"Close Friends", nil];
	NSArray *values = [NSArray arrayWithObjects:@"everyone", @"contacts", @"closeFriends", nil];

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
		[strongSelf postWithPrivacy:[values objectAtIndex:index]];
	}
														target:self];
	[sheet showInView:_host.view];
}

- (void)postWithPrivacy:(NSString *)privacy
{
	__weak TGStoryComposer *weakSelf = self;
	[[TGClient shared] postPhotoStoryAtPath:_path
									 asChat:_asChatId
									caption:(_caption ?: @"")
									privacy:privacy
									userIds:nil
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

#import "TGSearchViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGClient+Search.h"
#import "TGClient+ChatList.h"
#import "TGClient+Groups.h"
#import "TGClient+WebLinks.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "UIView+SafeTint.h"

static const CGFloat kSearchAvatar = 40.0f;
static const CGFloat kSearchRowHeight = 51.0f;
static const CGFloat kSearchAvatarLeft = 5.0f;
static const CGFloat kSearchAvatarTop = 5.0f;
static const CGFloat kSearchTextLeft = 54.0f;
static const CGFloat kSearchTextRight = 5.0f;
static const CGFloat kSearchSectionHeight = 25.0f;
static const CGFloat kSearchMessageRowHeight = 73.0f;
static const CGFloat kSearchMessageAvatar = 56.0f;
static const CGFloat kSearchMessageTextLeft = 73.0f;
static const CGFloat kSearchScopeHeight = 44.0f;
static const CGFloat kSearchScopeButtonTop = 7.0f;
static const CGFloat kSearchScopeButtonHeight = 30.0f;
static const CGFloat kSearchTagStripHeight = 34.0f;

@interface TGSearchCalendarViewController : UITableViewController
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *chatTitle;
@property (nonatomic, copy) NSString *filterName;
@property (nonatomic, copy) void (^onPickDate)(NSInteger date);
@end

@implementation TGSearchCalendarViewController {
	NSArray *_days;
	NSMutableDictionary *_positions;
	NSInteger _sparseTotal;
	UILabel *_status;
	BOOL _calendarLoaded;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Jump to Date";
	_days = @[];
	_positions = [NSMutableDictionary dictionary];
	self.tableView.rowHeight = 44;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.tableFooterView = [[UIView alloc] init];

	_status = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 90, self.view.bounds.size.width, 40)];
	_status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_status.backgroundColor = [UIColor clearColor];
	_status.textAlignment = NSTextAlignmentCenter;
	_status.font = [UIFont systemFontOfSize:15];
	_status.textColor = [[TGTheme shared] secondaryTextColour];
	_status.text = @"Loading...";
	[self.view addSubview:_status];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] messageCalendarForChat:_chatId
									   filter:_filterName
								fromMessageId:0
								   completion:^(NSArray *days, NSInteger totalCount)
	{
		TGSearchCalendarViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *clean = [NSMutableArray array];
		for (NSDictionary *day in days){
			if (![day isKindOfClass:NSDictionary.class])
				continue;
			if ([day[@"date"] integerValue] <= 0)
				continue;
			[clean addObject:day];
		}
		me->_days = clean;
		me->_calendarLoaded = YES;
		[me refresh];
	}];

	[[TGClient shared] sparseMessagePositionsInChat:_chatId
											 filter:_filterName
									  fromMessageId:0
											  limit:100
										 completion:^(NSArray *positions, NSInteger totalCount)
	{
		TGSearchCalendarViewController *me = weakSelf;
		if (!me)
			return;
		me->_sparseTotal = totalCount;
		for (NSDictionary *entry in positions){
			if (![entry isKindOfClass:NSDictionary.class])
				continue;
			NSNumber *messageId = [entry[@"messageId"] isKindOfClass:NSNumber.class]
					? entry[@"messageId"] : nil;
			NSNumber *position = [entry[@"position"] isKindOfClass:NSNumber.class]
					? entry[@"position"] : nil;
			if (!messageId || !position)
				continue;
			me->_positions[messageId] = position;
		}
		[me refresh];
	}];
}

- (void)refresh {
	if (_calendarLoaded && !_days.count){
		_status.text = @"No messages here yet";
		_status.hidden = NO;
	} else {
		_status.hidden = _days.count != 0;
	}
	self.navigationItem.prompt = _sparseTotal > 0
			? [NSString stringWithFormat:@"%d messages in %@", (int)_sparseTotal,
					(_chatTitle.length ? _chatTitle : @"this chat")]
			: nil;
	[self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)_days.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	static NSString *reuse = @"TGSearchCalendarDay";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:reuse];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	}

	NSDictionary *day = _days[indexPath.row];
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateFormat = @"d MMMM yyyy";
	}
	cell.textLabel.text = [formatter stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[day[@"date"] doubleValue]]];

	NSInteger count = [day[@"count"] integerValue];
	NSString *detail = [NSString stringWithFormat:@"%d", (int)count];
	NSNumber *position = [day[@"messageId"] isKindOfClass:NSNumber.class]
			? _positions[day[@"messageId"]] : nil;
	if (position)
		detail = [NSString stringWithFormat:@"%@  #%d", detail, (int)[position integerValue] + 1];
	cell.detailTextLabel.text = detail;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)_days.count)
		return;
	NSInteger date = [((NSDictionary *)_days[indexPath.row])[@"date"] integerValue];
	if (self.onPickDate)
		self.onPickDate(date);
}

@end

@interface TGSearchResultCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *titleLabelSecond;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
- (void)setTitleFirst:(NSString *)first second:(NSString *)second;
@end

@implementation TGSearchResultCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self){
		if (![TGTheme shared].isFlat){
			UIImage *cellImage = [UIImage imageNamed:@"Cell102.png"];
			UIImage *selectedCellImage = [UIImage imageNamed:@"CellHighlighted102.png"];
			if (cellImage)
				self.backgroundView = [[UIImageView alloc] initWithImage:cellImage];
			if (selectedCellImage)
				self.selectedBackgroundView = [[UIImageView alloc] initWithImage:selectedCellImage];
		}

		_titleLabel = [[UILabel alloc] init];
		_titleLabel.backgroundColor = [UIColor clearColor];
		_titleLabel.font = [UIFont systemFontOfSize:19];
		_titleLabel.textColor = [TGTheme shared].isFlat
				? [[TGTheme shared] primaryTextColour]
				: [UIColor colorWithRed:0x11 / 255.0f green:0x11 / 255.0f
								   blue:0x11 / 255.0f alpha:1.0f];
		_titleLabel.highlightedTextColor = [UIColor whiteColor];
		[self.contentView addSubview:_titleLabel];

		_titleLabelSecond = [[UILabel alloc] init];
		_titleLabelSecond.backgroundColor = [UIColor clearColor];
		_titleLabelSecond.font = [UIFont boldSystemFontOfSize:19];
		_titleLabelSecond.textColor = _titleLabel.textColor;
		_titleLabelSecond.highlightedTextColor = [UIColor whiteColor];
		_titleLabelSecond.hidden = YES;
		[self.contentView addSubview:_titleLabelSecond];

		_subtitleLabel = [[UILabel alloc] init];
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		_subtitleLabel.font = [UIFont systemFontOfSize:13];
		_subtitleLabel.textColor = [TGTheme shared].isFlat
				? [[TGTheme shared] secondaryTextColour]
				: [UIColor colorWithRed:0x80 / 255.0f green:0x80 / 255.0f
									blue:0x80 / 255.0f alpha:1.0f];
		_subtitleLabel.highlightedTextColor = [UIColor whiteColor];
		[self.contentView addSubview:_subtitleLabel];

		_dateLabel = [[UILabel alloc] init];
		_dateLabel.backgroundColor = [UIColor clearColor];
		_dateLabel.font = [UIFont systemFontOfSize:13];
		_dateLabel.textAlignment = NSTextAlignmentRight;
		_dateLabel.textColor = [TGTheme shared].isFlat
				? [[TGTheme shared] accentColour]
				: [UIColor colorWithRed:0x33 / 255.0f green:0x7a / 255.0f
									blue:0xcc / 255.0f alpha:1.0f];
		_dateLabel.highlightedTextColor = [UIColor whiteColor];
		[self.contentView addSubview:_dateLabel];

		_avatarView = [[UIImageView alloc] initWithFrame:
				CGRectMake(kSearchAvatarLeft, kSearchAvatarTop, kSearchAvatar, kSearchAvatar)];
		_avatarView.layer.cornerRadius = 4;
		_avatarView.clipsToBounds = YES;
		[self.contentView addSubview:_avatarView];
	}
	return self;
}

- (void)setTitleFirst:(NSString *)first second:(NSString *)second {
	NSString *firstText = first ?: @"";
	NSString *secondText = second ?: @"";

	if (!secondText.length){
		_titleLabel.text = firstText;
		_titleLabel.font = [UIFont boldSystemFontOfSize:19];
		_titleLabelSecond.text = nil;
		_titleLabelSecond.hidden = YES;
		return;
	}

	_titleLabel.text = firstText;
	_titleLabel.font = [UIFont systemFontOfSize:19];
	_titleLabelSecond.text = secondText;
	_titleLabelSecond.font = [UIFont boldSystemFontOfSize:19];
	_titleLabelSecond.hidden = NO;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	if (self.selectedBackgroundView){
		CGRect selectedFrame = self.selectedBackgroundView.frame;
		selectedFrame.origin.y = -1;
		selectedFrame.size.height = self.frame.size.height + 1;
		self.selectedBackgroundView.frame = selectedFrame;
	}

	CGSize viewSize = self.contentView.frame.size;
	_avatarView.frame = CGRectMake(kSearchAvatarLeft, kSearchAvatarTop,
								   kSearchAvatar, kSearchAvatar);

	CGFloat textWidth = viewSize.width - kSearchTextLeft - kSearchTextRight;
	CGFloat dateWidth = 0;
	if (_dateLabel.text.length){
		CGSize dateSize = [_dateLabel.text sizeWithFont:_dateLabel.font];
		dateWidth = (CGFloat)(int)dateSize.width + 4;
		textWidth -= dateWidth + 4;
	}
	_dateLabel.hidden = dateWidth == 0;

	CGFloat titleHeight = (CGFloat)(int)(_titleLabel.font.lineHeight);
	CGFloat subtitleHeight = (CGFloat)(int)(_subtitleLabel.font.lineHeight);
	BOOL hasSubtitle = _subtitleLabel.text.length != 0;

	CGFloat y;
	if (!hasSubtitle){
		y = (CGFloat)(int)((viewSize.height - titleHeight) / 2) - 1;
	} else {
		y = (CGFloat)(int)((viewSize.height - titleHeight - subtitleHeight - 1) / 2);
		_subtitleLabel.frame = CGRectMake(kSearchTextLeft + 1, y + titleHeight,
				viewSize.width - kSearchTextLeft - kSearchTextRight, subtitleHeight);
	}
	_subtitleLabel.hidden = !hasSubtitle;
	if (_titleLabelSecond.hidden){
		_titleLabel.frame = CGRectMake(kSearchTextLeft, y, textWidth, titleHeight);
	} else {
		CGFloat firstWidth = (CGFloat)(int)[_titleLabel.text sizeWithFont:_titleLabel.font].width;
		if (firstWidth > textWidth)
			firstWidth = textWidth;
		_titleLabel.frame = CGRectMake(kSearchTextLeft, y, firstWidth, titleHeight);
		CGFloat secondX = kSearchTextLeft + firstWidth + 5;
		CGFloat secondWidth = kSearchTextLeft + textWidth - secondX;
		if (secondWidth < 0)
			secondWidth = 0;
		_titleLabelSecond.frame = CGRectMake(secondX, y, secondWidth, titleHeight);
	}
	if (dateWidth > 0){
		_dateLabel.frame = CGRectMake(viewSize.width - kSearchTextRight - dateWidth,
									  y + 1, dateWidth, titleHeight);
	}
}

@end

@interface TGSearchMessageCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *textLabel_;
@property (nonatomic, strong) UILabel *dateLabel;
@end

@implementation TGSearchMessageCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self){
		if (![TGTheme shared].isFlat){
			UIImage *plate = [[UIImage imageNamed:@"DialogListCell.png"]
					stretchableImageWithLeftCapWidth:1 topCapHeight:0];
			UIImage *plateHighlighted = [[UIImage imageNamed:@"DialogListCellHighlighted.png"]
					stretchableImageWithLeftCapWidth:1 topCapHeight:0];
			if (plate)
				self.backgroundView = [[UIImageView alloc] initWithImage:plate];
			if (plateHighlighted)
				self.selectedBackgroundView = [[UIImageView alloc] initWithImage:plateHighlighted];
		}

		_titleLabel = [[UILabel alloc] init];
		_titleLabel.backgroundColor = [UIColor clearColor];
		_titleLabel.font = [UIFont boldSystemFontOfSize:16];
		_titleLabel.textColor = [TGTheme shared].isFlat
				? [[TGTheme shared] primaryTextColour]
				: [UIColor colorWithRed:0x11 / 255.0f green:0x11 / 255.0f
									blue:0x11 / 255.0f alpha:1.0f];
		_titleLabel.highlightedTextColor = [UIColor whiteColor];
		[self.contentView addSubview:_titleLabel];

		_authorLabel = [[UILabel alloc] init];
		_authorLabel.backgroundColor = [UIColor clearColor];
		_authorLabel.font = [UIFont boldSystemFontOfSize:14];
		_authorLabel.textColor = [TGTheme shared].isFlat
				? [[TGTheme shared] accentColour]
				: [UIColor colorWithRed:0x34 / 255.0f green:0x5f / 255.0f
									blue:0x8f / 255.0f alpha:1.0f];
		_authorLabel.highlightedTextColor = [UIColor whiteColor];
		_authorLabel.hidden = YES;
		[self.contentView addSubview:_authorLabel];

		_textLabel_ = [[UILabel alloc] init];
		_textLabel_.backgroundColor = [UIColor clearColor];
		_textLabel_.font = [UIFont systemFontOfSize:14];
		_textLabel_.numberOfLines = 2;
		_textLabel_.textColor = [TGTheme shared].isFlat
				? [[TGTheme shared] secondaryTextColour]
				: [UIColor colorWithRed:0x88 / 255.0f green:0x88 / 255.0f
									blue:0x88 / 255.0f alpha:1.0f];
		_textLabel_.highlightedTextColor = [UIColor whiteColor];
		[self.contentView addSubview:_textLabel_];

		_dateLabel = [[UILabel alloc] init];
		_dateLabel.backgroundColor = [UIColor clearColor];
		_dateLabel.font = [UIFont systemFontOfSize:13];
		_dateLabel.textAlignment = NSTextAlignmentRight;
		_dateLabel.textColor = [TGTheme shared].isFlat
				? [[TGTheme shared] accentColour]
				: [UIColor colorWithRed:0x33 / 255.0f green:0x7a / 255.0f
									blue:0xcc / 255.0f alpha:1.0f];
		_dateLabel.highlightedTextColor = [UIColor whiteColor];
		[self.contentView addSubview:_dateLabel];

		_avatarView = [[UIImageView alloc] initWithFrame:
				CGRectMake(8, 8, kSearchMessageAvatar, kSearchMessageAvatar)];
		_avatarView.layer.cornerRadius = 5;
		_avatarView.clipsToBounds = YES;
		[self.contentView addSubview:_avatarView];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	if (self.selectedBackgroundView){
		CGRect selectedFrame = self.selectedBackgroundView.frame;
		selectedFrame.origin.y = -1;
		selectedFrame.size.height = self.frame.size.height + 1;
		self.selectedBackgroundView.frame = selectedFrame;
	}

	CGSize viewSize = self.contentView.frame.size;
	_avatarView.frame = CGRectMake(8, 8, kSearchMessageAvatar, kSearchMessageAvatar);

	CGFloat dateWidth = 0;
	if (_dateLabel.text.length){
		CGSize dateSize = [_dateLabel.text sizeWithFont:_dateLabel.font];
		dateWidth = (CGFloat)(int)dateSize.width;
	}
	_dateLabel.hidden = dateWidth == 0;
	CGFloat dateX = viewSize.width - dateWidth - 9;
	if (dateWidth > 0)
		_dateLabel.frame = CGRectMake(dateX, 9, dateWidth, 15);

	CGFloat titleWidth = viewSize.width - kSearchMessageTextLeft - 10;
	if (dateWidth > 0)
		titleWidth = (CGFloat)(int)(dateX - 4 - kSearchMessageTextLeft - 18);
	if (titleWidth < 0)
		titleWidth = 0;
	_titleLabel.frame = CGRectMake(kSearchMessageTextLeft, 6, titleWidth, 20);

	CGFloat textWidth = viewSize.width - kSearchMessageTextLeft - 10;
	if (textWidth < 0)
		textWidth = 0;
	CGRect messageFrame = CGRectMake(kSearchMessageTextLeft, 29, textWidth, 40);

	BOOL hasAuthor = _authorLabel.text.length != 0;
	_authorLabel.hidden = !hasAuthor;
	if (hasAuthor){
		_authorLabel.frame = CGRectMake(kSearchMessageTextLeft, 29, textWidth, 20);
		messageFrame.origin.y += 9;
		messageFrame.size.height -= 12;
		CGSize fitted = [_textLabel_.text sizeWithFont:_textLabel_.font
									 constrainedToSize:messageFrame.size
										 lineBreakMode:NSLineBreakByTruncatingTail];
		if (fitted.height < 20)
			messageFrame.origin.y += 9;
	}
	_textLabel_.frame = messageFrame;
}

@end

static NSString *const kSearchRecentsKey = @"TGSearchRecentPeers";
static const NSUInteger kSearchRecentsLimit = 12;

@interface TGSearchViewController () <UISearchBarDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UISearchBar *bar;
@property (nonatomic, strong) NSArray *chatHits;
@property (nonatomic, strong) NSArray *contactHits;
@property (nonatomic, strong) NSArray *globalHits;
@property (nonatomic, strong) NSArray *messageHits;
@property (nonatomic, strong) NSArray *recents;
@property (nonatomic, strong) NSArray *contacts;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSMutableDictionary *avatars;
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSArray *hashtagHits;
@property (nonatomic, strong) NSArray *recentTags;
@property (nonatomic, strong) NSArray *remoteRecents;
@property (nonatomic, strong) NSMutableArray *scopeButtons;
@property (nonatomic, strong) NSMutableArray *scopeDividers;
@property (nonatomic, strong) UIView *scopeBar;
@property (nonatomic, strong) UIButton *scopeChatButton;
@property (nonatomic, strong) UIButton *scopeSenderButton;
@property (nonatomic, strong) NSArray *topPeers;
@property (nonatomic, strong) NSArray *tmeLinks;
@property (nonatomic, strong) NSArray *senderCandidates;
@property (nonatomic, strong) UIScrollView *tagStrip;
@property (nonatomic, strong) NSMutableArray *tagButtons;
@property (nonatomic, strong) NSArray *savedTags;
@property (nonatomic, weak) UITextField *searchField;
@property (nonatomic, strong) NSArray *liveLocations;
@property (nonatomic, strong) NSArray *recentMatches;
@end

@implementation TGSearchViewController {
	BOOL _searchFieldStyled;
	NSString *_query;
	NSUInteger _generation;
	NSInteger _pending;
	NSInteger _scope;
	NSString *_messagesOffset;
	int64_t _messagesFromId;
	BOOL _loadingMore;
	int64_t _scopedChatId;
	NSString *_scopedChatTitle;
	int64_t _sheetChatId;
	NSString *_sheetChatTitle;
	BOOL _sheetIsGroup;
	NSInteger _chatTypeIndex;
	NSInteger _periodIndex;
	NSString *_tagEmoji;
	NSInteger _sheetKind;
	BOOL _scopedIsGroup;
	int64_t _senderUserId;
	NSString *_senderName;
	BOOL _onlyMissedCalls;
	BOOL _dateAnchored;
	NSString *_anchorLabel;
}

static const NSInteger kSheetRowActions = 0;
static const NSInteger kSheetFilter = 1;
static const NSInteger kSheetChatType = 2;
static const NSInteger kSheetPeriod = 3;
static const NSInteger kSheetSender = 4;
static const NSInteger kSheetCalls = 5;

static const NSInteger kScopeFiles = 3;
static const NSInteger kScopeCalls = 6;

+ (NSArray *)chatTypeTitles {
	return @[@"All Chats", @"Private Chats", @"Groups", @"Channels"];
}

+ (NSString *)chatTypeForIndex:(NSInteger)index {
	switch (index){
		case 1: return @"private";
		case 2: return @"group";
		case 3: return @"channel";
		default: return nil;
	}
}

+ (NSArray *)scopeTitles {
	return @[@"All", @"Media", @"Links", @"Files", @"Music", @"Voice", @"Calls"];
}

+ (NSString *)filterForScope:(NSInteger)scope {
	switch (scope){
		case 1: return @"searchMessagesFilterPhotoAndVideo";
		case 2: return @"searchMessagesFilterUrl";
		case 3: return @"searchMessagesFilterDocument";
		case 4: return @"searchMessagesFilterAudio";
		case 5: return @"searchMessagesFilterVoiceNote";
		default: return nil;
	}
}

+ (NSArray *)periodTitles {
	return @[@"Any Time", @"Last Week", @"Last Month", @"Last Year"];
}

+ (NSInteger)minDateForPeriod:(NSInteger)index {
	NSTimeInterval span = 0;
	switch (index){
		case 1: span = 7 * 24 * 3600; break;
		case 2: span = 30 * 24 * 3600; break;
		case 3: span = 365 * 24 * 3600; break;
		default: return 0;
	}
	return (NSInteger)([[NSDate date] timeIntervalSince1970] - span);
}

+ (BOOL)isTagQuery:(NSString *)query {
	return query.length > 1 &&
			([query hasPrefix:@"#"] || [query hasPrefix:@"$"]);
}

+ (UIImage *)transparentBarBackground {
	static UIImage *image = nil;
	if (!image){
		UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
		image = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	}
	return image;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.chatHits = @[];
	self.contactHits = @[];
	self.globalHits = @[];
	self.messageHits = @[];
	self.contacts = @[];
	self.sections = @[];
	self.hashtagHits = @[];
	self.recentTags = @[];
	self.remoteRecents = @[];
	self.topPeers = @[];
	self.tmeLinks = @[];
	self.senderCandidates = @[];
	self.liveLocations = @[];
	self.recentMatches = @[];
	_query = @"";
	_scope = 0;
	_messagesOffset = @"";
	_messagesFromId = 0;
	[self loadRecents];
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];
	self.tableView.rowHeight = kSearchRowHeight;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	if (self.tableView.tableFooterView == nil)
		self.tableView.tableFooterView = [[UIView alloc] init];

	if ([self.tableView respondsToSelector:@selector(setKeyboardDismissMode:)])
		self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

	self.bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 240, 44)];
	self.bar.delegate = self;
	self.bar.placeholder = @"Search";
	self.bar.barStyle = [TGTheme shared].isDark ? UIBarStyleBlack : UIBarStyleDefault;
	[self.bar tg_setTintColor:[[TGTheme shared] accentColour]];
	if ([self.bar respondsToSelector:@selector(setBackgroundImage:)])
		[self.bar setBackgroundImage:[[self class] transparentBarBackground]];
	self.navigationItem.titleView = self.bar;
	self.navigationItem.hidesBackButton = YES;
	UIButton *cancel = [TGIcons headerButtonWithTitle:@"Cancel" bold:NO
												target:self action:@selector(cancel)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:cancel];

	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	_statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 40)];
	_statusLabel.backgroundColor = [UIColor clearColor];
	_statusLabel.textAlignment = NSTextAlignmentCenter;
	_statusLabel.font = [UIFont systemFontOfSize:15];
	_statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	_statusLabel.hidden = YES;
	[self.view addSubview:_statusLabel];

	[self buildScopeBar];

	UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(handleLongPress:)];
	press.minimumPressDuration = 0.5;
	[self.tableView addGestureRecognizer:press];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] contactsWithCompletion:^(NSArray *users){
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		me.contacts = users ?: @[];
		[me runLocalSearch];
	}];

	[[TGClient shared] recentlyFoundChatsWithQuery:@"" limit:12 completion:^(NSArray *chats){
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		me.remoteRecents = chats ?: @[];
		if (![me hasActiveQuery])
			[me rebuildSections];
	}];

	[[TGClient shared] topChatsWithCompletion:^(NSArray *chats){
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		me.topPeers = [me peerRowsFromChats:chats];
		if (![me hasActiveQuery])
			[me rebuildSections];
	}];

	[[TGClient shared] recentlyVisitedTMeUrlsWithReferrer:nil completion:^(NSArray *urls){
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		me.tmeLinks = [me linkRowsFromUrls:urls];
		if (![me hasActiveQuery])
			[me rebuildSections];
	}];

	[self reloadRecentTags];

	[self rebuildSections];
	[self.bar becomeFirstResponder];
}

- (void)reloadRecentTags {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchedForTagsWithPrefix:@"" limit:12 completion:^(NSArray *tags){
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		me.recentTags = tags ?: @[];
		if (![me hasActiveQuery])
			[me rebuildSections];
	}];
}

- (BOOL)hasActiveQuery {
	return _query.length != 0 || _tagEmoji.length != 0 || _senderUserId != 0 ||
			_dateAnchored || [self scopeRunsWithoutQuery];
}

- (BOOL)scopeRunsWithoutQuery {
	if (_scopedChatId)
		return NO;
	return _scope == kScopeCalls || _scope == kScopeFiles;
}

- (BOOL)isCallsMode {
	return !_scopedChatId && _scope == kScopeCalls;
}

- (BOOL)isOutgoingDocumentsMode {
	return !_scopedChatId && _scope == kScopeFiles && _query.length == 0;
}

- (NSArray *)peerRowsFromChats:(NSArray *)chats {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *chat in chats){
		if (![chat isKindOfClass:NSDictionary.class])
			continue;
		int64_t chatId = [chat[@"id"] longLongValue];
		NSString *title = [chat[@"title"] isKindOfClass:NSString.class] ? chat[@"title"] : @"";
		if (!chatId || !title.length)
			continue;
		[rows addObject:@{@"title": title,
						  @"chatId": @(chatId),
						  @"isGroup": @([chat[@"isGroup"] boolValue]),
						  @"fileId": ([chat[@"photoFileId"] isKindOfClass:NSNumber.class]
								  ? chat[@"photoFileId"]
								  : ([[TGClient shared] photoFileIdForChat:chatId]
										  ?: [NSNull null]))}];
		if (rows.count >= 10)
			break;
	}
	return rows;
}

- (NSString *)usernameFromTMeUrl:(NSString *)url {
	if (!url.length)
		return nil;
	NSRange marker = [url rangeOfString:@"t.me/" options:NSBackwardsSearch];
	if (marker.location == NSNotFound)
		return nil;
	NSString *tail = [url substringFromIndex:marker.location + marker.length];
	NSRange slash = [tail rangeOfString:@"/"];
	if (slash.location != NSNotFound)
		tail = [tail substringToIndex:slash.location];
	NSRange question = [tail rangeOfString:@"?"];
	if (question.location != NSNotFound)
		tail = [tail substringToIndex:question.location];
	if ([tail hasPrefix:@"+"] || [tail hasPrefix:@"joinchat"])
		return nil;
	return tail.length ? tail : nil;
}

- (NSArray *)linkRowsFromUrls:(NSArray *)urls {
	NSMutableArray *rows = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	for (NSDictionary *entry in urls){
		if (![entry isKindOfClass:NSDictionary.class])
			continue;
		NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
		if (!url.length || [seen containsObject:url])
			continue;
		NSString *kind = [entry[@"kind"] isKindOfClass:NSString.class] ? entry[@"kind"] : @"";
		if ([kind isEqualToString:@"stickerSet"])
			continue;
		NSString *username = [self usernameFromTMeUrl:url];
		NSString *title = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"";
		if (!title.length)
			title = username.length ? [@"@" stringByAppendingString:username] : url;

		NSString *subtitle = @"";
		NSInteger members = [entry[@"memberCount"] integerValue];
		if (members > 0)
			subtitle = [NSString stringWithFormat:@"%d members", (int)members];
		else if (username.length && ![title isEqualToString:
				[@"@" stringByAppendingString:username]])
			subtitle = [@"@" stringByAppendingString:username];

		[seen addObject:url];
		[rows addObject:@{@"title": title,
						  @"subtitle": subtitle,
						  @"tmeUrl": url,
						  @"username": (username ?: @""),
						  @"userId": (entry[@"userId"] ?: @0),
						  @"chatId": @0,
						  @"isGroup": @([kind isEqualToString:@"supergroup"] ||
										[kind isEqualToString:@"chatInvite"]),
						  @"fileId": ([entry[@"photoFileId"] isKindOfClass:NSNumber.class]
								  ? entry[@"photoFileId"] : [NSNull null])}];
		if (rows.count >= 6)
			break;
	}
	return rows;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutScopeBar];
}

#pragma mark - scope bar

- (void)buildScopeBar {
	CGFloat width = self.view.bounds.size.width;
	if (width < 1)
		width = 320;

	_scopeBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, kSearchScopeHeight)];
	_scopeBar.clipsToBounds = YES;
	_scopeBar.backgroundColor = [TGTheme shared].isFlat
			? [[TGTheme shared] listBackgroundColour]
			: [UIColor colorWithRed:0xc3 / 255.0f green:0xcb / 255.0f
								blue:0xd4 / 255.0f alpha:1.0f];

	UIImage *background = [UIImage imageNamed:@"SearchBarScopeBarBackground.png"];
	if (!background)
		background = [UIImage imageNamed:@"SearchBarBackground.png"];
	if (background && ![TGTheme shared].isFlat){
		UIImageView *backgroundView = [[UIImageView alloc] initWithImage:background];
		backgroundView.frame = CGRectMake(0, 0, width, kSearchScopeHeight);
		backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[_scopeBar addSubview:backgroundView];
	}

	_scopeButtons = [NSMutableArray array];
	NSArray *titles = [[self class] scopeTitles];
	for (NSUInteger i = 0; i < titles.count; i++){
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.tag = (NSInteger)i;
		button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
		[button setTitle:titles[i] forState:UIControlStateNormal];
		[self styleScopeButton:button selected:(i == 0)];
		[button addTarget:self action:@selector(scopeTapped:)
			 forControlEvents:UIControlEventTouchDown];
		[_scopeBar addSubview:button];
		[_scopeButtons addObject:button];
	}

	_scopeDividers = [NSMutableArray array];
	UIImage *dividerLeft = [UIImage imageNamed:@"SearchScopeBarScopeDividerLeft.png"];
	UIImage *dividerRight = [UIImage imageNamed:@"SearchScopeBarScopeDividerRight.png"];
	if (dividerLeft && dividerRight && titles.count > 1){
		for (NSUInteger i = 0; i + 1 < titles.count; i++){
			UIImageView *divider = [[UIImageView alloc] initWithImage:dividerLeft];
			divider.hidden = YES;
			[_scopeBar addSubview:divider];
			[_scopeDividers addObject:divider];
		}
	}

	_scopeChatButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_scopeChatButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	_scopeChatButton.hidden = YES;
	[self styleScopeButton:_scopeChatButton selected:YES];
	[_scopeChatButton addTarget:self action:@selector(leaveChatScope)
			   forControlEvents:UIControlEventTouchDown];
	[_scopeBar addSubview:_scopeChatButton];

	_scopeSenderButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_scopeSenderButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	_scopeSenderButton.hidden = YES;
	[_scopeSenderButton setTitle:@"From: Anyone" forState:UIControlStateNormal];
	[self styleScopeButton:_scopeSenderButton selected:NO];
	[_scopeSenderButton addTarget:self action:@selector(showSenderSheet)
				 forControlEvents:UIControlEventTouchDown];
	[_scopeBar addSubview:_scopeSenderButton];

	_tagButtons = [NSMutableArray array];
	_tagStrip = [[UIScrollView alloc] initWithFrame:
			CGRectMake(0, kSearchScopeHeight, width, kSearchTagStripHeight)];
	_tagStrip.backgroundColor = [UIColor clearColor];
	_tagStrip.showsHorizontalScrollIndicator = NO;
	_tagStrip.showsVerticalScrollIndicator = NO;
	_tagStrip.hidden = YES;
	[_scopeBar addSubview:_tagStrip];

	_scopeBar.layer.zPosition = 1;
	[self.tableView addSubview:_scopeBar];
	[self applyScopeInset];
	[self layoutScopeBar];
}

- (CGFloat)scopeBarHeight {
	return kSearchScopeHeight + (_tagStrip.hidden ? 0 : kSearchTagStripHeight);
}

- (void)applyScopeInset {
	CGFloat height = [self scopeBarHeight];
	UIEdgeInsets inset = self.tableView.contentInset;
	if ((int)inset.top == (int)height)
		return;
	BOOL atTop = self.tableView.contentOffset.y <= -inset.top + 1;
	inset.top = height;
	self.tableView.contentInset = inset;
	UIEdgeInsets indicator = self.tableView.scrollIndicatorInsets;
	indicator.top = height;
	self.tableView.scrollIndicatorInsets = indicator;
	if (atTop)
		self.tableView.contentOffset = CGPointMake(0, -height);
}

- (void)positionFloatingViews {
	CGFloat top = self.tableView.contentOffset.y + self.tableView.contentInset.top
			- [self scopeBarHeight];
	CGRect frame = _scopeBar.frame;
	frame.origin.y = top;
	frame.size.height = [self scopeBarHeight];
	_scopeBar.frame = frame;
	if (_scopeBar.superview == self.tableView &&
		[self.tableView.subviews lastObject] != _scopeBar)
		[self.tableView bringSubviewToFront:_scopeBar];

	CGSize size = self.view.bounds.size;
	_statusLabel.frame = CGRectMake(0,
			self.tableView.contentOffset.y + (CGFloat)(int)(size.height / 3), size.width, 40);
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	[self positionFloatingViews];
}

- (void)styleScopeButton:(UIButton *)button selected:(BOOL)selected {
	UIImage *plate = [UIImage imageNamed:selected
			? @"SearchBarScopeButton_Highlighted.png" : @"SearchBarScopeButton.png"];
	if (plate){
		plate = [plate stretchableImageWithLeftCapWidth:(int)(plate.size.width / 2)
										   topCapHeight:0];
		[button setBackgroundImage:plate forState:UIControlStateNormal];
		button.backgroundColor = [UIColor clearColor];
	} else {
		button.backgroundColor = selected
				? [[TGTheme shared] accentColour]
				: [UIColor clearColor];
	}

	if (selected){
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithRed:0x11 / 255.0f green:0x2e / 255.0f
													 blue:0x5c / 255.0f alpha:0.2f]
						   forState:UIControlStateNormal];
	} else {
		[button setTitleColor:([TGTheme shared].isFlat
				? [[TGTheme shared] secondaryTextColour]
				: [UIColor colorWithRed:0x5c / 255.0f green:0x70 / 255.0f
									blue:0x8b / 255.0f alpha:1.0f])
					 forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithWhite:1.0f alpha:0.25f]
						   forState:UIControlStateNormal];
	}
	button.titleLabel.shadowOffset = CGSizeMake(0, -1);
}

- (void)layoutScopeBar {
	if (!_scopeBar)
		return;
	CGFloat width = self.view.bounds.size.width;
	if (width < 1)
		return;

	CGRect barFrame = _scopeBar.frame;
	if ((int)barFrame.size.width != (int)width){
		barFrame.size.width = width;
		_scopeBar.frame = barFrame;
	}
	_tagStrip.frame = CGRectMake(0, kSearchScopeHeight, width, kSearchTagStripHeight);
	[self applyScopeInset];
	[self positionFloatingViews];

	if (_scopedChatId){
		for (UIButton *button in _scopeButtons)
			button.hidden = YES;
		for (UIImageView *divider in _scopeDividers)
			divider.hidden = YES;
		_scopeChatButton.hidden = NO;
		if (_scopedIsGroup){
			CGFloat half = (CGFloat)(int)((width - 18) / 2);
			_scopeChatButton.frame = CGRectMake(6, kSearchScopeButtonTop, half,
					kSearchScopeButtonHeight);
			_scopeSenderButton.hidden = NO;
			_scopeSenderButton.frame = CGRectMake(6 + half + 6, kSearchScopeButtonTop,
					width - 12 - half - 6, kSearchScopeButtonHeight);
		} else {
			_scopeSenderButton.hidden = YES;
			_scopeChatButton.frame = CGRectMake(6, kSearchScopeButtonTop, width - 12,
					kSearchScopeButtonHeight);
		}
		return;
	}

	_scopeChatButton.hidden = YES;
	_scopeSenderButton.hidden = YES;
	NSUInteger count = _scopeButtons.count;
	if (!count)
		return;
	CGFloat available = width - 12;
	CGFloat each = (CGFloat)(int)(available / count);
	for (NSUInteger i = 0; i < count; i++){
		UIButton *button = _scopeButtons[i];
		button.hidden = NO;
		CGFloat buttonWidth = (i == count - 1) ? (available - each * (count - 1)) : each;
		button.frame = CGRectMake(6 + each * i, kSearchScopeButtonTop, buttonWidth,
				kSearchScopeButtonHeight);
	}
	[self updateScopeDividers];
}

- (void)updateScopeDividers {
	if (!_scopeDividers.count)
		return;
	UIImage *dividerLeft = [UIImage imageNamed:@"SearchScopeBarScopeDividerLeft.png"];
	UIImage *dividerRight = [UIImage imageNamed:@"SearchScopeBarScopeDividerRight.png"];
	for (NSUInteger i = 0; i < _scopeDividers.count; i++){
		UIImageView *divider = _scopeDividers[i];
		if (_scopedChatId || i + 1 >= _scopeButtons.count){
			divider.hidden = YES;
			continue;
		}
		UIImage *art = nil;
		if (_scope == (NSInteger)i)
			art = dividerLeft;
		else if (_scope == (NSInteger)(i + 1))
			art = dividerRight;
		if (!art){
			divider.hidden = YES;
			continue;
		}
		UIButton *right = _scopeButtons[i + 1];
		divider.image = art;
		divider.hidden = NO;
		divider.frame = CGRectMake(right.frame.origin.x - (CGFloat)(int)(art.size.width / 2),
				kSearchScopeButtonTop, art.size.width, kSearchScopeButtonHeight);
		[_scopeBar bringSubviewToFront:divider];
	}
}

- (void)scopeTapped:(UIButton *)button {
	if (button.tag == _scope){
		if (_scopedChatId)
			return;
		if (_scope == kScopeCalls)
			[self showCallsSheet];
		else
			[self showFilterSheet];
		return;
	}
	_scope = button.tag;
	for (UIButton *other in _scopeButtons)
		[self styleScopeButton:other selected:(other.tag == _scope)];
	[self updateScopeDividers];
	[self restartSearch];
}

- (UIActionSheet *)sheetWithTitle:(NSString *)title
						  options:(NSArray *)options
							 kind:(NSInteger)kind
{
	_sheetKind = kind;
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	for (NSString *option in options)
		[sheet addButtonWithTitle:option];
	[sheet addButtonWithTitle:@"Cancel"];
	sheet.cancelButtonIndex = (NSInteger)options.count;
	[self.bar resignFirstResponder];
	[sheet showInView:self.view.window ?: self.view];
	return sheet;
}

- (void)showFilterSheet {
	NSString *type = [[self class] chatTypeTitles][_chatTypeIndex];
	NSString *period = [[self class] periodTitles][_periodIndex];
	[self sheetWithTitle:@"Filter Results"
				 options:@[[@"Chats: " stringByAppendingString:type],
						   [@"Date: " stringByAppendingString:period]]
					kind:kSheetFilter];
}

- (void)showCallsSheet {
	[self sheetWithTitle:@"Calls"
				 options:@[@"All Calls", @"Missed Only"]
					kind:kSheetCalls];
}

- (void)showChatTypeSheet {
	[self sheetWithTitle:@"Search In"
				 options:[[self class] chatTypeTitles]
					kind:kSheetChatType];
}

- (void)showPeriodSheet {
	[self sheetWithTitle:@"Search Period"
				 options:[[self class] periodTitles]
					kind:kSheetPeriod];
}

- (void)showSenderSheet {
	if (!_scopedChatId || !_scopedIsGroup)
		return;
	if (self.senderCandidates.count){
		[self presentSenderSheet];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] membersInGroup:_scopedChatId
							   filter:@"recent"
							   offset:0
								limit:20
						   completion:^(NSArray *members, NSInteger totalCount)
	{
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *people = [NSMutableArray array];
		for (NSDictionary *member in members){
			if (![member isKindOfClass:NSDictionary.class])
				continue;
			int64_t userId = [member[@"id"] longLongValue];
			NSString *name = [member[@"name"] isKindOfClass:NSString.class]
					? member[@"name"] : @"";
			if (!userId || !name.length)
				continue;
			[people addObject:@{@"userId": @(userId), @"name": name}];
			if (people.count >= 12)
				break;
		}
		me.senderCandidates = people;
		[me presentSenderSheet];
	}];
}

- (void)presentSenderSheet {
	if (!self.senderCandidates.count)
		return;
	NSMutableArray *options = [NSMutableArray arrayWithObject:@"Anyone"];
	for (NSDictionary *person in self.senderCandidates)
		[options addObject:person[@"name"]];
	[self sheetWithTitle:@"From" options:options kind:kSheetSender];
}

- (void)applySender:(int64_t)userId name:(NSString *)name {
	_senderUserId = userId;
	_senderName = userId ? name : nil;
	[_scopeSenderButton setTitle:(userId
			? [@"From: " stringByAppendingString:(name ?: @"")] : @"From: Anyone")
					   forState:UIControlStateNormal];
	[self styleScopeButton:_scopeSenderButton selected:(userId != 0)];
	[self restartSearch];
}

- (void)updatePlaceholder:(NSString *)placeholder {
	self.bar.placeholder = placeholder;
	[self applyPlaceholderColour];
}

- (void)applyPlaceholderColour {
	UITextField *field = self.searchField;
	if (!field || !field.placeholder.length)
		return;
	if (![field respondsToSelector:@selector(setAttributedPlaceholder:)])
		return;
	UIColor *placeholderColour = [TGTheme shared].isFlat
			? [[TGTheme shared] secondaryTextColour]
			: [UIColor colorWithRed:0x8d / 255.0f green:0x92 / 255.0f
							   blue:0x98 / 255.0f alpha:1.0f];
	field.attributedPlaceholder = [[NSAttributedString alloc]
			initWithString:field.placeholder
				attributes:@{NSForegroundColorAttributeName: placeholderColour}];
}

- (void)enterChatScope:(int64_t)chatId title:(NSString *)title isGroup:(BOOL)isGroup {
	_scopedChatId = chatId;
	_scopedChatTitle = title.length ? title : @"Chat";
	_scopedIsGroup = isGroup;
	_tagEmoji = nil;
	_senderUserId = 0;
	_senderName = nil;
	self.senderCandidates = @[];
	[_scopeSenderButton setTitle:@"From: Anyone" forState:UIControlStateNormal];
	[self styleScopeButton:_scopeSenderButton selected:NO];
	[_scopeChatButton setTitle:[@"In: " stringByAppendingString:_scopedChatTitle]
					  forState:UIControlStateNormal];
	[self updatePlaceholder:[@"Search in " stringByAppendingString:_scopedChatTitle]];
	[self loadSavedTagsIfNeeded];
	[self loadLiveLocations];
	[self layoutScopeBar];
	[self.bar becomeFirstResponder];
	[self restartSearch];
}

- (void)leaveChatScope {
	if (!_scopedChatId)
		return;
	_scopedChatId = 0;
	_scopedChatTitle = nil;
	_scopedIsGroup = NO;
	_tagEmoji = nil;
	_senderUserId = 0;
	_senderName = nil;
	self.senderCandidates = @[];
	self.savedTags = nil;
	self.liveLocations = @[];
	[self rebuildTagStrip];
	[self updatePlaceholder:@"Search"];
	[self layoutScopeBar];
	[self restartSearch];
}

- (void)loadLiveLocations {
	self.liveLocations = @[];
	int64_t chatId = _scopedChatId;
	if (!chatId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] recentLocationMessagesInChat:chatId
											  limit:10
										 completion:^(NSArray *messages)
	{
		TGSearchViewController *me = weakSelf;
		if (!me || me->_scopedChatId != chatId)
			return;
		me.liveLocations = [me rowsForMessages:messages inChat:YES];
		if (![me hasActiveQuery])
			[me rebuildSections];
	}];
}

#pragma mark - jumping to a day

- (void)openCalendarForChat:(int64_t)chatId title:(NSString *)title isGroup:(BOOL)isGroup {
	if (!chatId)
		return;
	TGSearchCalendarViewController *calendar =
			[[TGSearchCalendarViewController alloc] initWithStyle:UITableViewStylePlain];
	calendar.chatId = chatId;
	calendar.chatTitle = title;
	calendar.filterName = (_scopedChatId == chatId)
			? [[self class] filterForScope:_scope] : nil;

	NSString *name = title ?: @"";
	__weak typeof(self) weakSelf = self;
	calendar.onPickDate = ^(NSInteger date){
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		[me jumpToDate:date chat:chatId title:name isGroup:isGroup];
	};
	[self.bar resignFirstResponder];
	[self.navigationController pushViewController:calendar animated:YES];
}

- (void)jumpToDate:(NSInteger)date chat:(int64_t)chatId title:(NSString *)title
		   isGroup:(BOOL)isGroup
{
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] messageInChat:chatId
					   closestToDate:(date + 86399)
						  completion:^(int64_t messageId)
	{
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		[me.navigationController popToViewController:me animated:YES];
		if (!messageId){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Nothing was sent by that day."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		static NSDateFormatter *formatter = nil;
		if (!formatter){
			formatter = [[NSDateFormatter alloc] init];
			formatter.dateFormat = @"d MMM yyyy";
		}
		[me anchorChat:chatId
				 title:title
			   isGroup:isGroup
			   atMessage:messageId
				 label:[formatter stringFromDate:
						 [NSDate dateWithTimeIntervalSince1970:(double)date]]];
	}];
}

- (void)anchorChat:(int64_t)chatId title:(NSString *)title isGroup:(BOOL)isGroup
		 atMessage:(int64_t)messageId label:(NSString *)label
{
	if (_scopedChatId != chatId)
		[self enterChatScope:chatId title:title isGroup:isGroup];

	_generation++;
	_pending = 1;
	_loadingMore = NO;
	_query = @"";
	self.bar.text = @"";
	self.messageHits = @[];
	self.globalHits = @[];
	self.hashtagHits = @[];
	_messagesOffset = @"";
	_messagesFromId = messageId;
	_dateAnchored = YES;
	_anchorLabel = label;
	[self.bar resignFirstResponder];
	[self rebuildSections];
	[self loadChatMessagesPage:@"" generation:_generation];
}

- (void)restartSearch {
	_generation++;
	_pending = 0;
	_loadingMore = NO;
	_dateAnchored = NO;
	_anchorLabel = nil;
	_messagesOffset = @"";
	_messagesFromId = 0;
	self.messageHits = @[];
	self.globalHits = @[];
	self.hashtagHits = @[];
	[self runLocalSearch];
	if (![self hasActiveQuery])
		return;
	[self runServerSearch:_query generation:_generation];
}

#pragma mark - saved messages tags

- (BOOL)scopeIsSavedMessages {
	int64_t saved = [[TGClient shared] savedMessagesChatId];
	return saved != 0 && _scopedChatId == saved;
}

- (void)loadSavedTagsIfNeeded {
	if (![self scopeIsSavedMessages]){
		self.savedTags = nil;
		[self rebuildTagStrip];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] request:@{@"@type": @"getSavedMessagesTags",
								 @"saved_messages_topic_id": @0}
					completion:^(NSDictionary *result)
	{
		TGSearchViewController *me = weakSelf;
		if (!me || ![me scopeIsSavedMessages])
			return;
		NSArray *tags = [result[@"tags"] isKindOfClass:NSArray.class] ? result[@"tags"] : @[];
		NSMutableArray *clean = [NSMutableArray array];
		for (NSDictionary *entry in tags){
			if (![entry isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *tag = [entry[@"tag"] isKindOfClass:NSDictionary.class] ? entry[@"tag"] : nil;
			NSString *emoji = [tag[@"emoji"] isKindOfClass:NSString.class] ? tag[@"emoji"] : nil;
			if (!emoji.length)
				continue;
			NSString *label = [entry[@"label"] isKindOfClass:NSString.class] ? entry[@"label"] : @"";
			NSNumber *count = [entry[@"count"] isKindOfClass:NSNumber.class] ? entry[@"count"] : @0;
			[clean addObject:@{@"emoji": emoji, @"label": label, @"count": count}];
		}
		me.savedTags = clean;
		[me rebuildTagStrip];
		[me layoutScopeBar];
	}];
}

- (void)rebuildTagStrip {
	for (UIButton *button in self.tagButtons)
		[button removeFromSuperview];
	[self.tagButtons removeAllObjects];

	if (!self.savedTags.count){
		_tagStrip.hidden = YES;
		[self applyScopeInset];
		[self positionFloatingViews];
		return;
	}

	_tagStrip.hidden = NO;
	CGFloat x = 6;
	for (NSUInteger i = 0; i < self.savedTags.count; i++){
		NSDictionary *tag = self.savedTags[i];
		NSString *emoji = tag[@"emoji"];
		NSString *label = [tag[@"label"] isKindOfClass:NSString.class] ? tag[@"label"] : @"";
		NSString *title = label.length
				? [NSString stringWithFormat:@"%@ %@", emoji, label]
				: emoji;
		if ([tag[@"count"] integerValue] > 0)
			title = [NSString stringWithFormat:@"%@ %@", title, tag[@"count"]];

		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.tag = (NSInteger)i;
		button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
		[button setTitle:title forState:UIControlStateNormal];
		[self styleScopeButton:button selected:[_tagEmoji isEqualToString:emoji]];
		[button addTarget:self action:@selector(tagTapped:)
			 forControlEvents:UIControlEventTouchUpInside];
		CGSize size = [title sizeWithFont:button.titleLabel.font];
		CGFloat width = (CGFloat)(int)size.width + 22;
		button.frame = CGRectMake(x, 2, width, 28);
		[_tagStrip addSubview:button];
		[self.tagButtons addObject:button];
		x += width + 6;
	}
	_tagStrip.contentSize = CGSizeMake(x, kSearchTagStripHeight);
	[self applyScopeInset];
	[self positionFloatingViews];
}

- (void)tagTapped:(UIButton *)button {
	if (button.tag >= (NSInteger)self.savedTags.count)
		return;
	NSString *emoji = ((NSDictionary *)self.savedTags[button.tag])[@"emoji"];
	_tagEmoji = [_tagEmoji isEqualToString:emoji] ? nil : emoji;
	for (UIButton *other in self.tagButtons){
		NSString *otherEmoji = ((NSDictionary *)self.savedTags[other.tag])[@"emoji"];
		[self styleScopeButton:other selected:[_tagEmoji isEqualToString:otherEmoji]];
	}
	[self restartSearch];
}

- (NSArray *)flattenSavedMessages:(NSArray *)messages {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *m in messages){
		if (![m isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *content = [m[@"content"] isKindOfClass:NSDictionary.class] ? m[@"content"] : nil;
		NSString *text = @"";
		NSDictionary *formatted = nil;
		if ([content[@"text"] isKindOfClass:NSDictionary.class])
			formatted = content[@"text"];
		else if ([content[@"caption"] isKindOfClass:NSDictionary.class])
			formatted = content[@"caption"];
		if ([formatted[@"text"] isKindOfClass:NSString.class])
			text = formatted[@"text"];
		if (!text.length && [content[@"@type"] isKindOfClass:NSString.class])
			text = content[@"@type"];
		int64_t chatId = [m[@"chat_id"] longLongValue];
		if (!chatId)
			chatId = _scopedChatId;
		[rows addObject:@{@"chatId": @(chatId),
						  @"chatTitle": (_scopedChatTitle ?: @""),
						  @"senderName": @"",
						  @"text": text,
						  @"date": (m[@"date"] ?: @0)}];
	}
	return rows;
}

- (void)loadTaggedSavedMessagesPage:(NSString *)query generation:(NSUInteger)generation {
	NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:
			@{@"@type": @"searchSavedMessages",
			  @"saved_messages_topic_id": @0,
			  @"query": (query ?: @""),
			  @"from_message_id": @(_messagesFromId),
			  @"offset": @0,
			  @"limit": @40}];
	if (_tagEmoji.length)
		request[@"tag"] = @{@"@type": @"reactionTypeEmoji", @"emoji": _tagEmoji};

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] request:request completion:^(NSDictionary *result){
		TGSearchViewController *me = weakSelf;
		if (!me || generation != me->_generation)
			return;
		NSArray *messages = [result[@"messages"] isKindOfClass:NSArray.class] ? result[@"messages"] : @[];
		[me appendMessageRows:[me rowsForMessages:[me flattenSavedMessages:messages] inChat:YES]];
		NSDictionary *last = messages.count ? [messages lastObject] : nil;
		me->_messagesFromId = [last isKindOfClass:NSDictionary.class]
				? [last[@"id"] longLongValue] : 0;
		if (messages.count < 40)
			me->_messagesFromId = 0;
		me->_loadingMore = NO;
		if (me->_pending > 0)
			me->_pending--;
		[me rebuildSections];
	}];
}

#pragma mark - recents

- (void)loadRecents {
	NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:kSearchRecentsKey];
	NSMutableArray *clean = [NSMutableArray array];
	for (id entry in stored){
		if (![entry isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *row = entry;
		if (![row[@"chatId"] isKindOfClass:NSNumber.class] || [row[@"chatId"] longLongValue] == 0)
			continue;
		if (![row[@"title"] isKindOfClass:NSString.class])
			continue;
		[clean addObject:row];
	}
	self.recents = clean;
}

- (void)rememberRecent:(NSDictionary *)row {
	if ([row[@"chatId"] longLongValue] == 0)
		return;
	NSMutableArray *updated = [NSMutableArray array];
	[updated addObject:@{@"chatId": row[@"chatId"] ?: @0,
						 @"title": row[@"title"] ?: @"",
						 @"isGroup": @([row[@"isGroup"] boolValue])}];
	for (NSDictionary *old in self.recents){
		if ([old[@"chatId"] longLongValue] == [row[@"chatId"] longLongValue])
			continue;
		if (updated.count >= kSearchRecentsLimit)
			break;
		[updated addObject:old];
	}
	self.recents = updated;
	[[NSUserDefaults standardUserDefaults] setObject:updated forKey:kSearchRecentsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[[TGClient shared] addRecentlyFoundChat:[row[@"chatId"] longLongValue]];
}

- (void)forgetRecentChat:(int64_t)chatId {
	if (!chatId)
		return;
	NSMutableArray *kept = [NSMutableArray array];
	for (NSDictionary *old in self.recents){
		if ([old[@"chatId"] longLongValue] == chatId)
			continue;
		[kept addObject:old];
	}
	self.recents = kept;
	[[NSUserDefaults standardUserDefaults] setObject:kept forKey:kSearchRecentsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];

	NSMutableArray *keptRemote = [NSMutableArray array];
	for (NSDictionary *old in self.remoteRecents){
		if (![old isKindOfClass:NSDictionary.class] || [old[@"id"] longLongValue] == chatId)
			continue;
		[keptRemote addObject:old];
	}
	self.remoteRecents = keptRemote;
	[[TGClient shared] removeRecentlyFoundChat:chatId];
	[self rebuildSections];
}

- (void)clearRecentTags {
	[[TGClient shared] clearSearchedForTagsIncludingCashtags:NO];
	[[TGClient shared] clearSearchedForTagsIncludingCashtags:YES];
	self.recentTags = @[];
	[self rebuildSections];
}

- (void)clearRecents {
	self.recents = @[];
	self.remoteRecents = @[];
	[[TGClient shared] clearRecentlyFoundChats];
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kSearchRecentsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[self rebuildSections];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (!_searchFieldStyled){
		_searchFieldStyled = YES;
		[self.bar layoutIfNeeded];
		[self styleSearchInputField:self.bar];
	}
}

- (void)styleSearchInputField:(UIView *)view {
	if ([view isKindOfClass:[UITextField class]]){
		UITextField *field = (UITextField *)view;
		field.borderStyle = UITextBorderStyleNone;
		field.background = nil;
		field.font = [UIFont systemFontOfSize:14];
		field.clipsToBounds = NO;
		field.textColor = [TGTheme shared].isFlat
				? [[TGTheme shared] primaryTextColour]
				: [UIColor blackColor];

		self.searchField = field;
		[self applyPlaceholderColour];

		UIView *leftView = field.leftView;
		if ([leftView isKindOfClass:[UIImageView class]]){
			UIImage *icon = [UIImage imageNamed:@"SearchBarIcon.png"];
			if (icon){
				((UIImageView *)leftView).image = icon;
				[leftView sizeToFit];
			}
		}

		UIImage *inputImage = [UIImage imageNamed:@"SearchInputField.png"];
		if (inputImage){
			inputImage = [inputImage stretchableImageWithLeftCapWidth:
					(int)(inputImage.size.width / 2) topCapHeight:0];
			UIImageView *inputImageView = [[UIImageView alloc] initWithFrame:
					CGRectMake(0, 0.5f, field.frame.size.width, inputImage.size.height)];
			inputImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
			inputImageView.image = inputImage;
			[field insertSubview:inputImageView atIndex:0];
		}

		SEL clearButtonSelector = NSSelectorFromString([[NSString alloc]
				initWithFormat:@"%sBu%s", "clear", "tton"]);
		if ([field respondsToSelector:clearButtonSelector]){
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
			UIButton *clearButton = [field performSelector:clearButtonSelector];
#pragma clang diagnostic pop
			if ([clearButton isKindOfClass:[UIButton class]]){
				UIImage *clear = [UIImage imageNamed:@"ClearInput.png"];
				UIImage *clearPressed = [UIImage imageNamed:@"ClearInput_Pressed.png"];
				if (clear)
					[clearButton setImage:clear forState:UIControlStateNormal];
				if (clearPressed)
					[clearButton setImage:clearPressed forState:UIControlStateHighlighted];
			}
		}
		return;
	}

	for (UIView *child in view.subviews)
		[self styleSearchInputField:child];
}

- (void)cancel {
	[self.bar resignFirstResponder];
	[self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - searching

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
	NSString *trimmed = [(query ?: @"") stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed isEqualToString:_query])
		return;

	_query = trimmed;
	_generation++;
	_pending = 0;
	_loadingMore = NO;
	_messagesOffset = @"";
	_messagesFromId = 0;
	_dateAnchored = NO;
	_anchorLabel = nil;

	self.messageHits = @[];
	self.globalHits = @[];
	self.hashtagHits = @[];
	self.recentMatches = @[];
	[self runLocalSearch];
	[self matchRecentsForQuery:_query generation:_generation];

	if (![self hasActiveQuery])
		return;

	NSUInteger generation = _generation;
	NSString *query_ = _query;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		[me runServerSearch:query_ generation:generation];
	});
}

- (void)runLocalSearch {
	if (!_query.length || _scope != 0 || _scopedChatId ||
		[[self class] isTagQuery:_query]){
		self.chatHits = @[];
		self.contactHits = @[];
		[self rebuildSections];
		return;
	}

	NSMutableArray *titles = [NSMutableArray array];
	for (NSDictionary *c in [TGClient shared].chats){
		NSString *title = [c[@"title"] isKindOfClass:NSString.class] ? c[@"title"] : nil;
		if (!title.length)
			continue;
		if ([title rangeOfString:_query options:NSCaseInsensitiveSearch].location == NSNotFound)
			continue;
		[titles addObject:@{@"title": title,
							@"subtitle": @"",
							@"chatId": (c[@"id"] ?: @0),
							@"isGroup": @([c[@"isGroup"] boolValue]),
							@"fileId": (c[@"photoFileId"] ?: [NSNull null])}];
	}
	self.chatHits = titles;

	NSMutableArray *people = [NSMutableArray array];
	for (NSDictionary *u in self.contacts){
		if (![u isKindOfClass:NSDictionary.class])
			continue;
		NSString *first = [u[@"first_name"] isKindOfClass:NSString.class] ? u[@"first_name"] : @"";
		NSString *last = [u[@"last_name"] isKindOfClass:NSString.class] ? u[@"last_name"] : @"";
		NSString *username = [u[@"username"] isKindOfClass:NSString.class] ? u[@"username"] : @"";
		NSString *name = [[first stringByAppendingString:
				(last.length ? [@" " stringByAppendingString:last] : @"")]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (!name.length)
			name = username;
		if (!name.length)
			continue;
		BOOL matches = [name rangeOfString:_query
								   options:NSCaseInsensitiveSearch].location != NSNotFound ||
				(username.length && [username rangeOfString:_query
													options:NSCaseInsensitiveSearch].location != NSNotFound);
		if (!matches)
			continue;
		int64_t userId = [u[@"id"] longLongValue];
		if (!userId)
			continue;
		[people addObject:@{@"title": name,
							@"subtitle": @"",
							@"firstName": (first.length ? first : last),
							@"lastName": (first.length ? last : @""),
							@"userId": @(userId),
							@"chatId": @0,
							@"isGroup": @NO,
							@"fileId": ([[TGClient shared] photoFileIdForUserId:userId] ?: [NSNull null])}];
	}
	self.contactHits = people;

	[self rebuildSections];
}

- (NSArray *)recentRows {
	NSMutableArray *rows = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	for (NSDictionary *r in self.recents){
		int64_t chatId = [r[@"chatId"] longLongValue];
		NSString *title = [r[@"title"] isKindOfClass:NSString.class] ? r[@"title"] : @"";
		if (!chatId || !title.length || [seen containsObject:@(chatId)])
			continue;
		[seen addObject:@(chatId)];
		[rows addObject:@{@"title": title,
						  @"subtitle": @"",
						  @"chatId": @(chatId),
						  @"isGroup": @([r[@"isGroup"] boolValue]),
						  @"fileId": ([[TGClient shared] photoFileIdForChat:chatId]
								  ?: [NSNull null])}];
	}
	for (NSDictionary *r in self.remoteRecents){
		if (![r isKindOfClass:NSDictionary.class])
			continue;
		int64_t chatId = [r[@"id"] longLongValue];
		NSString *title = [r[@"title"] isKindOfClass:NSString.class] ? r[@"title"] : @"";
		if (!chatId || !title.length || [seen containsObject:@(chatId)])
			continue;
		[seen addObject:@(chatId)];
		[rows addObject:@{@"title": title,
						  @"subtitle": @"",
						  @"chatId": @(chatId),
						  @"isGroup": @NO,
						  @"unknownType": @YES,
						  @"fileId": ([r[@"photoFileId"] isKindOfClass:NSNumber.class]
								  ? r[@"photoFileId"]
								  : ([[TGClient shared] photoFileIdForChat:chatId]
										  ?: [NSNull null]))}];
	}
	return rows;
}

- (void)matchRecentsForQuery:(NSString *)query generation:(NSUInteger)generation {
	if (!query.length || _scopedChatId || [[self class] isTagQuery:query]){
		self.recentMatches = @[];
		return;
	}
	NSArray *rows = [self recentRows];
	if (!rows.count){
		self.recentMatches = @[];
		return;
	}
	NSMutableArray *titles = [NSMutableArray array];
	for (NSDictionary *row in rows)
		[titles addObject:row[@"title"]];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] indexesOfStrings:titles
						 matchingPrefix:query
								  limit:6
							 completion:^(NSArray *indexes)
	{
		TGSearchViewController *me = weakSelf;
		if (!me || generation != me->_generation)
			return;
		NSMutableArray *matched = [NSMutableArray array];
		for (NSNumber *index in indexes){
			if (![index isKindOfClass:NSNumber.class])
				continue;
			NSInteger i = [index integerValue];
			if (i < 0 || i >= (NSInteger)rows.count)
				continue;
			[matched addObject:rows[i]];
		}
		me.recentMatches = matched;
		[me rebuildSections];
	}];
}

- (NSString *)shortDateFor:(NSNumber *)stamp {
	if (![stamp isKindOfClass:NSNumber.class] || [stamp doubleValue] < 1)
		return @"";
	static NSDateFormatter *timeFormatter = nil;
	static NSDateFormatter *dayFormatter = nil;
	if (!timeFormatter){
		timeFormatter = [[NSDateFormatter alloc] init];
		timeFormatter.dateFormat = @"HH:mm";
		dayFormatter = [[NSDateFormatter alloc] init];
		dayFormatter.dateFormat = @"d MMM";
	}
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:[stamp doubleValue]];
	BOOL today = fabs([date timeIntervalSinceNow]) < 12 * 3600;
	return [(today ? timeFormatter : dayFormatter) stringFromDate:date];
}

- (NSArray *)rowsForMessages:(NSArray *)messages inChat:(BOOL)inChat {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *m in messages){
		if (![m isKindOfClass:NSDictionary.class])
			continue;
		int64_t chatId = [m[@"chatId"] longLongValue];
		if (!chatId)
			continue;
		NSString *chatTitle = [m[@"chatTitle"] isKindOfClass:NSString.class] ? m[@"chatTitle"] : @"";
		NSString *sender = [m[@"senderName"] isKindOfClass:NSString.class] ? m[@"senderName"] : @"";
		NSString *text = [m[@"text"] isKindOfClass:NSString.class] ? m[@"text"] : @"";
		NSString *title = inChat
				? (sender.length ? sender : (chatTitle.length ? chatTitle : @"Message"))
				: (chatTitle.length ? chatTitle : (sender.length ? sender : @"Chat"));
		NSString *author = (!inChat && sender.length && chatTitle.length) ? sender : @"";
		[rows addObject:@{@"title": title,
						  @"subtitle": text,
						  @"author": author,
						  @"date": [self shortDateFor:m[@"date"]],
						  @"chatId": @(chatId),
						  @"isGroup": @([m[@"isGroup"] boolValue]),
						  @"unknownType": @(m[@"isGroup"] == nil),
						  @"fileId": ([[TGClient shared] photoFileIdForChat:chatId] ?: [NSNull null])}];
	}
	return rows;
}

- (void)appendMessageRows:(NSArray *)rows {
	if (!rows.count)
		return;
	NSUInteger start = self.messageHits.count;
	NSMutableArray *all = [NSMutableArray arrayWithArray:self.messageHits];
	[all addObjectsFromArray:rows];
	self.messageHits = all;
	[self centreSnippetsFrom:start generation:_generation];
}

- (void)centreSnippetsFrom:(NSUInteger)start generation:(NSUInteger)generation {
	if (_query.length < 2 || [[self class] isTagQuery:_query])
		return;
	NSUInteger end = start + 6;
	if (end > self.messageHits.count)
		end = self.messageHits.count;

	for (NSUInteger i = start; i < end; i++){
		NSDictionary *row = self.messageHits[i];
		NSString *text = [row[@"subtitle"] isKindOfClass:NSString.class] ? row[@"subtitle"] : @"";
		if (text.length < 80)
			continue;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] positionOfQuote:_query
									inText:text
								completion:^(NSInteger position)
		{
			TGSearchViewController *me = weakSelf;
			if (!me || generation != me->_generation || position < 40)
				return;
			if (i >= me.messageHits.count || me.messageHits[i] != row)
				return;
			NSUInteger from = (NSUInteger)position - 20;
			NSString *tail = [text substringFromIndex:from];
			if (tail.length > 140)
				tail = [tail substringToIndex:140];
			NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:row];
			updated[@"subtitle"] = [@"..." stringByAppendingString:tail];
			NSMutableArray *all = [NSMutableArray arrayWithArray:me.messageHits];
			all[i] = updated;
			me.messageHits = all;
			[me rebuildSections];
		}];
	}
}

- (void)runServerSearch:(NSString *)query generation:(NSUInteger)generation {
	if (generation != _generation)
		return;
	if (![self hasActiveQuery])
		return;

	if ([self isCallsMode]){
		_pending = 1;
		[self rebuildSections];
		[self loadCallsPage:generation];
		return;
	}

	if ([self isOutgoingDocumentsMode]){
		_pending = 1;
		[self rebuildSections];
		[self loadOutgoingDocuments:generation];
		return;
	}

	if (_scopedChatId){
		_pending = 1;
		[self rebuildSections];
		if (_tagEmoji.length && [self scopeIsSavedMessages])
			[self loadTaggedSavedMessagesPage:query generation:generation];
		else
			[self loadChatMessagesPage:query generation:generation];
		return;
	}

	if ([[self class] isTagQuery:query]){
		_pending = 2;
		[self rebuildSections];
		[self loadTagMessagesPage:query generation:generation];
		[self loadHashtagSuggestions:query generation:generation];
		return;
	}

	if (_scope != 0){
		_pending = 1;
		[self rebuildSections];
		[self loadGlobalMessagesPage:query generation:generation];
		return;
	}

	_pending = 2;
	[self rebuildSections];
	[self loadGlobalMessagesPage:query generation:generation];
	[self searchPublicChats:query generation:generation];
}

- (void)loadGlobalMessagesPage:(NSString *)query generation:(NSUInteger)generation {
	NSString *offset = _messagesOffset ?: @"";
	__weak typeof(self) weakSelf = self;
	void (^handler)(NSArray *, NSString *) = ^(NSArray *messages, NSString *nextOffset){
		TGSearchViewController *me = weakSelf;
		if (!me || generation != me->_generation)
			return;
		[me appendMessageRows:[me rowsForMessages:messages inChat:NO]];
		me->_messagesOffset = [nextOffset isKindOfClass:NSString.class] ? nextOffset : @"";
		me->_loadingMore = NO;
		if (me->_pending > 0)
			me->_pending--;
		[me rebuildSections];
	};

	NSString *chatType = [[self class] chatTypeForIndex:_chatTypeIndex];
	NSInteger minDate = [[self class] minDateForPeriod:_periodIndex];
	if (chatType || minDate){
		[[TGClient shared] searchMessagesWithQuery:query
											filter:[[self class] filterForScope:_scope]
										  chatType:chatType
										   minDate:minDate
										   maxDate:0
											offset:offset
											 limit:40
										completion:handler];
		return;
	}
	[[TGClient shared] searchMessagesWithQuery:query
										filter:[[self class] filterForScope:_scope]
										offset:offset
									completion:handler];
}

- (void)loadCallsPage:(NSUInteger)generation {
	NSString *offset = _messagesOffset ?: @"";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchCallMessagesOnlyMissed:_onlyMissedCalls
											 offset:offset
											  limit:40
										 completion:^(NSArray *messages, NSString *nextOffset)
	{
		TGSearchViewController *me = weakSelf;
		if (!me || generation != me->_generation)
			return;
		[me appendMessageRows:[me rowsForMessages:messages inChat:NO]];
		me->_messagesOffset = [nextOffset isKindOfClass:NSString.class] ? nextOffset : @"";
		me->_loadingMore = NO;
		if (me->_pending > 0)
			me->_pending--;
		[me rebuildSections];
	}];
}

- (void)loadOutgoingDocuments:(NSUInteger)generation {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchOutgoingDocumentsWithQuery:@""
												  limit:40
											 completion:^(NSArray *messages)
	{
		TGSearchViewController *me = weakSelf;
		if (!me || generation != me->_generation)
			return;
		[me appendMessageRows:[me rowsForMessages:messages inChat:NO]];
		me->_messagesOffset = @"";
		me->_loadingMore = NO;
		if (me->_pending > 0)
			me->_pending--;
		[me rebuildSections];
	}];
}

- (void)loadChatMessagesPage:(NSString *)query generation:(NSUInteger)generation {
	int64_t chatId = _scopedChatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchMessagesInChat:chatId
									  query:query
							   senderUserId:_senderUserId
									 filter:[[self class] filterForScope:_scope]
							  fromMessageId:_messagesFromId
									  limit:40
								 completion:^(NSArray *messages, int64_t nextFromMessageId,
											  NSInteger totalCount)
	{
		TGSearchViewController *me = weakSelf;
		if (!me || generation != me->_generation)
			return;
		[me appendMessageRows:[me rowsForMessages:messages inChat:YES]];
		me->_messagesFromId = nextFromMessageId;
		me->_loadingMore = NO;
		if (me->_pending > 0)
			me->_pending--;
		[me rebuildSections];
	}];
}

- (void)loadTagMessagesPage:(NSString *)tag generation:(NSUInteger)generation {
	NSString *offset = _messagesOffset ?: @"";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchPublicMessagesWithTag:tag
											offset:offset
											 limit:40
										completion:^(NSArray *messages, NSString *nextOffset)
	{
		TGSearchViewController *me = weakSelf;
		if (!me || generation != me->_generation)
			return;
		[me appendMessageRows:[me rowsForMessages:messages inChat:NO]];
		me->_messagesOffset = [nextOffset isKindOfClass:NSString.class] ? nextOffset : @"";
		me->_loadingMore = NO;
		if (me->_pending > 0)
			me->_pending--;
		[me rebuildSections];
	}];
}

- (void)loadHashtagSuggestions:(NSString *)tag generation:(NSUInteger)generation {
	NSString *prefix = [tag substringFromIndex:1];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchHashtagsWithPrefix:prefix limit:10 completion:^(NSArray *hashtags){
		TGSearchViewController *me = weakSelf;
		if (!me || generation != me->_generation)
			return;
		NSMutableArray *rows = [NSMutableArray array];
		for (id entry in hashtags){
			NSString *entryString = [entry isKindOfClass:NSString.class] ? entry : nil;
			if (!entryString.length)
				continue;
			[rows addObject:@{@"title": [@"#" stringByAppendingString:entryString],
							  @"subtitle": @"",
							  @"hashtag": [@"#" stringByAppendingString:entryString],
							  @"chatId": @0,
							  @"isGroup": @NO,
							  @"fileId": [NSNull null]}];
		}
		me.hashtagHits = rows;
		if (me->_pending > 0)
			me->_pending--;
		[me rebuildSections];
	}];
}

- (void)loadMoreIfPossible {
	if (_loadingMore || _pending > 0 || ![self hasActiveQuery])
		return;
	NSUInteger generation = _generation;
	if (_scopedChatId){
		if (!_messagesFromId)
			return;
		_loadingMore = YES;
		if (_tagEmoji.length && [self scopeIsSavedMessages])
			[self loadTaggedSavedMessagesPage:_query generation:generation];
		else
			[self loadChatMessagesPage:_query generation:generation];
		return;
	}
	if ([self isOutgoingDocumentsMode])
		return;
	if (!_messagesOffset.length)
		return;
	_loadingMore = YES;
	if ([self isCallsMode])
		[self loadCallsPage:generation];
	else if ([[self class] isTagQuery:_query])
		[self loadTagMessagesPage:_query generation:generation];
	else
		[self loadGlobalMessagesPage:_query generation:generation];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
	forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.section >= (NSInteger)self.sections.count)
		return;
	NSDictionary *info = self.sections[indexPath.section];
	if (![info[@"paged"] boolValue])
		return;
	NSArray *rows = info[@"rows"];
	if (indexPath.row >= (NSInteger)rows.count - 3)
		[self loadMoreIfPossible];
}

- (void)searchPublicChats:(NSString *)query generation:(NSUInteger)generation {
	__weak typeof(self) weakSelf = self;
	NSString *type = nil;
	if (_chatTypeIndex == 3)
		type = @"channel";
	[[TGClient shared] searchPublicChatsWithQuery:query
											 type:type
									   completion:^(NSArray *chats)
	{
		TGSearchViewController *me = weakSelf;
		if (!me || generation != me->_generation)
			return;

		NSMutableSet *known = [NSMutableSet set];
		for (NSDictionary *row in me.chatHits)
			[known addObject:@([row[@"chatId"] longLongValue])];

		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *chat in chats){
			if (![chat isKindOfClass:NSDictionary.class])
				continue;
			int64_t chatId = [chat[@"id"] longLongValue];
			NSString *title = [chat[@"title"] isKindOfClass:NSString.class] ? chat[@"title"] : @"";
			if (!chatId || !title.length || [known containsObject:@(chatId)])
				continue;
			if (me->_chatTypeIndex == 1 && ![chat[@"isPrivate"] boolValue])
				continue;
			if (me->_chatTypeIndex == 2 && ![chat[@"isGroup"] boolValue])
				continue;
			if (me->_chatTypeIndex == 3 && ![chat[@"isChannel"] boolValue])
				continue;
			[known addObject:@(chatId)];

			NSString *username = [chat[@"username"] isKindOfClass:NSString.class]
					? chat[@"username"] : @"";
			NSInteger members = [chat[@"memberCount"] integerValue];
			NSString *subtitle = username.length
					? [@"@" stringByAppendingString:username] : @"";
			if (members > 0){
				NSString *count = [NSString stringWithFormat:@"%d %@", (int)members,
						([chat[@"isChannel"] boolValue] ? @"subscribers" : @"members")];
				subtitle = subtitle.length
						? [NSString stringWithFormat:@"%@, %@", subtitle, count] : count;
			}

			[rows addObject:@{@"title": title,
							  @"subtitle": subtitle,
							  @"chatId": @(chatId),
							  @"isGroup": @([chat[@"isGroup"] boolValue] ||
											[chat[@"isChannel"] boolValue]),
							  @"fileId": ([chat[@"photoFileId"] isKindOfClass:NSNumber.class]
									  ? chat[@"photoFileId"]
									  : ([[TGClient shared] photoFileIdForChat:chatId]
											  ?: [NSNull null]))}];
			if (rows.count >= 8)
				break;
		}

		me.globalHits = rows;
		if (me->_pending > 0)
			me->_pending--;
		[me rebuildSections];
	}];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	[self cancel];
}

#pragma mark - table

- (void)rebuildSections {
	NSMutableArray *built = [NSMutableArray array];
	if (_scopedChatId && ![self hasActiveQuery]){
		[built addObject:@{@"title": (_scopedChatTitle ?: @"Chat"),
						   @"rows": @[@{@"title": @"Jump to Date",
										@"subtitle": @"Browse this chat day by day",
										@"action": @"calendar",
										@"chatId": @0,
										@"isGroup": @NO,
										@"fileId": [NSNull null]}]}];
		if (self.liveLocations.count)
			[built addObject:@{@"title": @"Live Locations",
							   @"rows": self.liveLocations,
							   @"messages": @YES}];
		self.sections = built;
		[self.tableView reloadData];
		[self updateStatusLabel];
		return;
	}
	if (![self hasActiveQuery]){
		if (self.topPeers.count)
			[built addObject:@{@"title": @"People", @"rows": self.topPeers}];

		NSMutableArray *rows = [NSMutableArray array];
		NSMutableSet *seen = [NSMutableSet set];
		for (NSDictionary *r in self.recents){
			int64_t chatId = [r[@"chatId"] longLongValue];
			if (!chatId || [seen containsObject:@(chatId)])
				continue;
			[seen addObject:@(chatId)];
			[rows addObject:@{@"title": (r[@"title"] ?: @""),
							  @"subtitle": @"",
							  @"chatId": (r[@"chatId"] ?: @0),
							  @"isGroup": @([r[@"isGroup"] boolValue]),
							  @"fileId": ([[TGClient shared] photoFileIdForChat:chatId]
									  ?: [NSNull null])}];
		}
		for (NSDictionary *r in self.remoteRecents){
			if (![r isKindOfClass:NSDictionary.class])
				continue;
			int64_t chatId = [r[@"id"] longLongValue];
			NSString *title = [r[@"title"] isKindOfClass:NSString.class] ? r[@"title"] : @"";
			if (!chatId || !title.length || [seen containsObject:@(chatId)])
				continue;
			[seen addObject:@(chatId)];
			[rows addObject:@{@"title": title,
							  @"subtitle": @"",
							  @"chatId": @(chatId),
							  @"isGroup": @NO,
							  @"unknownType": @YES,
							  @"fileId": ([r[@"photoFileId"] isKindOfClass:NSNumber.class]
									  ? r[@"photoFileId"]
									  : ([[TGClient shared] photoFileIdForChat:chatId]
											  ?: [NSNull null]))}];
		}
		if (rows.count)
			[built addObject:@{@"title": @"Recent", @"rows": rows, @"recent": @YES}];

		if (self.tmeLinks.count)
			[built addObject:@{@"title": @"Recent Links", @"rows": self.tmeLinks}];

		NSMutableArray *tagRows = [NSMutableArray array];
		for (id entry in self.recentTags){
			NSString *entryString = [entry isKindOfClass:NSString.class] ? entry : nil;
			if (!entryString.length)
				continue;
			NSString *tag = ([entryString hasPrefix:@"#"] || [entryString hasPrefix:@"$"])
					? entryString : [@"#" stringByAppendingString:entryString];
			[tagRows addObject:@{@"title": tag,
								 @"subtitle": @"",
								 @"hashtag": tag,
								 @"chatId": @0,
								 @"isGroup": @NO,
								 @"fileId": [NSNull null]}];
		}
		if (tagRows.count)
			[built addObject:@{@"title": @"Recent Hashtags", @"rows": tagRows, @"tags": @YES}];
	} else {
		NSMutableArray *localHits = [NSMutableArray array];
		[localHits addObjectsFromArray:self.chatHits];
		[localHits addObjectsFromArray:self.contactHits];
		if (localHits.count)
			[built addObject:@{@"title": @"", @"rows": localHits, @"noHeader": @YES}];
		if (self.recentMatches.count)
			[built addObject:@{@"title": @"Recently Opened", @"rows": self.recentMatches}];
		if (self.globalHits.count)
			[built addObject:@{@"title": @"Global Search", @"rows": self.globalHits}];
		if (self.hashtagHits.count)
			[built addObject:@{@"title": @"Hashtags", @"rows": self.hashtagHits}];
		if (self.messageHits.count){
			NSString *title = @"Messages";
			if ([self isCallsMode]){
				title = _onlyMissedCalls ? @"Missed Calls" : @"Recent Calls";
			} else if ([self isOutgoingDocumentsMode]){
				title = @"Files You Sent";
			} else if (_scopedChatId){
				title = [@"In " stringByAppendingString:(_scopedChatTitle ?: @"Chat")];
				if (_dateAnchored && _anchorLabel.length)
					title = [NSString stringWithFormat:@"%@, from %@", title, _anchorLabel];
				if (_tagEmoji.length)
					title = [NSString stringWithFormat:@"%@ %@", title, _tagEmoji];
				if (_senderName.length)
					title = [NSString stringWithFormat:@"%@, from %@", title, _senderName];
			} else if ([[self class] isTagQuery:_query]){
				title = @"Public Posts";
			} else {
				if (_scope != 0)
					title = [[self class] scopeTitles][_scope];
				if (_chatTypeIndex != 0)
					title = [NSString stringWithFormat:@"%@ in %@", title,
							[[self class] chatTypeTitles][_chatTypeIndex]];
				if (_periodIndex != 0)
					title = [NSString stringWithFormat:@"%@, %@", title,
							[[self class] periodTitles][_periodIndex]];
			}
			[built addObject:@{@"title": title, @"rows": self.messageHits,
							   @"paged": @(![self isOutgoingDocumentsMode]),
							   @"messages": @YES}];
		}
	}
	self.sections = built;
	[self.tableView reloadData];
	[self updateStatusLabel];
}

- (void)updateStatusLabel {
	if (self.sections.count){
		_statusLabel.hidden = YES;
		return;
	}
	if (![self hasActiveQuery]){
		_statusLabel.text = _scopedChatId
				? [@"Search in " stringByAppendingString:(_scopedChatTitle ?: @"this chat")]
				: @"Search for messages or users";
		_statusLabel.hidden = NO;
		return;
	}
	_statusLabel.text = _pending > 0 ? @"Searching..." : @"No results";
	_statusLabel.hidden = NO;
}

- (NSDictionary *)rowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.sections.count)
		return nil;
	NSArray *rows = ((NSDictionary *)self.sections[indexPath.section])[@"rows"];
	if (indexPath.row >= (NSInteger)rows.count)
		return nil;
	return rows[indexPath.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section >= (NSInteger)self.sections.count)
		return 0;
	NSArray *rows = ((NSDictionary *)self.sections[section])[@"rows"];
	return (NSInteger)rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section >= (NSInteger)self.sections.count)
		return nil;
	NSDictionary *info = self.sections[section];
	if ([info[@"noHeader"] boolValue])
		return nil;
	return info[@"title"];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (section >= (NSInteger)self.sections.count)
		return nil;

	NSDictionary *info = self.sections[section];
	if ([info[@"noHeader"] boolValue])
		return nil;
	NSString *title = [info[@"title"] isKindOfClass:NSString.class] ? info[@"title"] : @"";
	BOOL isRecent = [info[@"recent"] boolValue];
	BOOL isTags = [info[@"tags"] boolValue];

	CGFloat width = tableView.bounds.size.width;
	UIView *header = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, kSearchSectionHeight)];
	header.clipsToBounds = NO;
	header.backgroundColor = [UIColor clearColor];

	UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont boldSystemFontOfSize:15];
	label.numberOfLines = 1;
	label.text = title;

	UIColor *actionColour;
	if ([TGTheme shared].isFlat){
		header.backgroundColor = [[TGTheme shared] listBackgroundColour];
		label.textColor = [[TGTheme shared] sectionHeaderColour];
		actionColour = [[TGTheme shared] accentColour];
	} else {
		UIImage *background = [UIImage imageNamed:
				section == 0 ? @"CategoryDividerFirst.png" : @"CategoryDivider.png"];
		if (background){
			UIImageView *backgroundView = [[UIImageView alloc] initWithImage:background];
			backgroundView.frame = CGRectMake(0, -1, width, kSearchSectionHeight + 1);
			backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
			[header addSubview:backgroundView];
		} else {
			header.backgroundColor = [UIColor colorWithRed:0xa8 / 255.0f green:0xb0 / 255.0f
													  blue:0xb8 / 255.0f alpha:1.0f];
		}
		label.textColor = [UIColor whiteColor];
		label.shadowColor = [UIColor colorWithRed:0x88 / 255.0f green:0x92 / 255.0f
											 blue:0x9c / 255.0f alpha:1.0f];
		label.shadowOffset = CGSizeMake(0, -1);
		actionColour = [UIColor whiteColor];
	}

	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 10, 1);
	[header addSubview:label];

	if (isRecent || isTags){
		UIButton *clear = [UIButton buttonWithType:UIButtonTypeCustom];
		clear.frame = CGRectMake(width - 90, 0, 80, kSearchSectionHeight);
		clear.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		clear.titleLabel.font = [UIFont boldSystemFontOfSize:13];
		clear.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
		[clear setTitle:@"Clear" forState:UIControlStateNormal];
		[clear setTitleColor:actionColour forState:UIControlStateNormal];
		if (![TGTheme shared].isFlat){
			[clear setTitleShadowColor:[UIColor colorWithRed:0x88 / 255.0f
													   green:0x92 / 255.0f
														blue:0x9c / 255.0f alpha:1.0f]
							  forState:UIControlStateNormal];
			clear.titleLabel.shadowOffset = CGSizeMake(0, -1);
		}
		[clear addTarget:self
				  action:(isTags ? @selector(clearRecentTags) : @selector(clearRecents))
				forControlEvents:UIControlEventTouchUpInside];
		[header addSubview:clear];
	}

	return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if (section >= (NSInteger)self.sections.count)
		return 0;
	if ([((NSDictionary *)self.sections[section])[@"noHeader"] boolValue])
		return 0;
	return kSearchSectionHeight;
}

- (UIImage *)avatarForChat:(int64_t)chatId
					 title:(NSString *)title
					fileId:(NSNumber *)fileId
					  size:(CGFloat)size
{
	NSString *cacheKey = [fileId isKindOfClass:NSNumber.class]
			? [NSString stringWithFormat:@"%@_%d", fileId, (int)size] : nil;
	UIImage *cached = cacheKey ? self.avatars[cacheKey] : nil;
	if (cached)
		return cached;

	if (cacheKey && ![self.avatarsRequested containsObject:cacheKey]){
		[self.avatarsRequested addObject:cacheKey];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			TGSearchViewController *me = weakSelf;
			UIImage *photo = path ? [UIImage imageWithContentsOfFile:path] : nil;
			if (!me || !photo)
				return;
			UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
			[photo drawInRect:CGRectMake(0, 0, size, size)];
			me.avatars[cacheKey] = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
			[me.tableView reloadData];
		}];
	}

	return [TGIcons avatarWithInitials:
				(title.length ? [title substringToIndex:1].uppercaseString : @"?")
								  size:size
							  colourId:chatId];
}

- (BOOL)sectionIsMessages:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return NO;
	return [((NSDictionary *)self.sections[section])[@"messages"] boolValue];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return [self sectionIsMessages:indexPath.section]
			? kSearchMessageRowHeight : kSearchRowHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSDictionary *messageRow = [self rowAtIndexPath:indexPath];
	if ([self sectionIsMessages:indexPath.section]){
		static NSString *messageReuse = @"TGSearchMessageCell";
		TGSearchMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:messageReuse];
		if (!cell)
			cell = [[TGSearchMessageCell alloc] initWithStyle:UITableViewCellStyleDefault
											  reuseIdentifier:messageReuse];

		NSString *messageTitle = [messageRow[@"title"] isKindOfClass:NSString.class]
				? messageRow[@"title"] : @"";
		cell.titleLabel.text = messageTitle;
		cell.authorLabel.text = [messageRow[@"author"] isKindOfClass:NSString.class]
				? messageRow[@"author"] : @"";
		cell.textLabel_.text = [messageRow[@"subtitle"] isKindOfClass:NSString.class]
				? messageRow[@"subtitle"] : @"";
		cell.dateLabel.text = [messageRow[@"date"] isKindOfClass:NSString.class]
				? messageRow[@"date"] : @"";
		cell.avatarView.image = [self avatarForChat:[messageRow[@"chatId"] longLongValue]
											  title:messageTitle
											 fileId:([messageRow[@"fileId"] isKindOfClass:NSNumber.class]
													 ? messageRow[@"fileId"] : nil)
											   size:kSearchMessageAvatar];
		[cell setNeedsLayout];
		return cell;
	}

	static NSString *reuse = @"TGSearchCell";
	TGSearchResultCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGSearchResultCell alloc] initWithStyle:UITableViewCellStyleDefault
										 reuseIdentifier:reuse];

	NSDictionary *row = [self rowAtIndexPath:indexPath];
	NSString *title = [row[@"title"] isKindOfClass:NSString.class] ? row[@"title"] : @"";
	NSString *subtitle = [row[@"subtitle"] isKindOfClass:NSString.class] ? row[@"subtitle"] : @"";
	int64_t colourId = [row[@"chatId"] longLongValue];
	if (!colourId)
		colourId = [row[@"userId"] longLongValue];

	NSString *nameFirst = [row[@"firstName"] isKindOfClass:NSString.class] ? row[@"firstName"] : @"";
	NSString *nameLast = [row[@"lastName"] isKindOfClass:NSString.class] ? row[@"lastName"] : @"";
	if (nameFirst.length || nameLast.length)
		[cell setTitleFirst:(nameFirst.length ? nameFirst : nameLast)
					 second:(nameFirst.length ? nameLast : nil)];
	else
		[cell setTitleFirst:title second:nil];
	cell.subtitleLabel.text = subtitle;
	cell.dateLabel.text = [row[@"date"] isKindOfClass:NSString.class] ? row[@"date"] : @"";

	NSString *hashtagRow = [row[@"hashtag"] isKindOfClass:NSString.class] ? row[@"hashtag"] : nil;
	if (hashtagRow.length){
		cell.avatarView.image = [TGIcons avatarWithInitials:[hashtagRow substringToIndex:1]
													   size:kSearchAvatar
												   colourId:(int64_t)hashtagRow.hash];
		[cell setNeedsLayout];
		return cell;
	}

	cell.avatarView.image = [self avatarForChat:colourId
										  title:title
										 fileId:([row[@"fileId"] isKindOfClass:NSNumber.class]
												 ? row[@"fileId"] : nil)
										   size:kSearchAvatar];

	[cell setNeedsLayout];
	return cell;
}

- (void)openChat:(int64_t)chatId title:(NSString *)title isGroup:(BOOL)isGroup {
	if (!chatId)
		return;
	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = chatId;
	chat.chatTitle = title;
	chat.isGroup = isGroup;
	[self.navigationController pushViewController:chat animated:YES];
}

- (void)openRecentLinkRow:(NSDictionary *)row {
	NSString *title = [row[@"title"] isKindOfClass:NSString.class] ? row[@"title"] : @"";
	BOOL isGroup = [row[@"isGroup"] boolValue];
	int64_t userId = [row[@"userId"] longLongValue];
	__weak typeof(self) weakSelf = self;

	if (userId){
		[[TGClient shared] privateChatWithUser:userId completion:^(int64_t createdChatId){
			TGSearchViewController *me = weakSelf;
			if (!me || !createdChatId)
				return;
			[me rememberRecent:@{@"chatId": @(createdChatId), @"title": title,
								 @"isGroup": @NO}];
			[me openChat:createdChatId title:title isGroup:NO];
		}];
		return;
	}

	NSString *username = [row[@"username"] isKindOfClass:NSString.class] ? row[@"username"] : @"";
	if (!username.length)
		return;
	[[TGClient shared] chatWithUsername:username
							 completion:^(int64_t chatId, NSString *resolvedTitle)
	{
		TGSearchViewController *me = weakSelf;
		if (!me || !chatId)
			return;
		NSString *name = resolvedTitle.length ? resolvedTitle : title;
		[me rememberRecent:@{@"chatId": @(chatId), @"title": name,
							 @"isGroup": @(isGroup)}];
		[me openChat:chatId title:name isGroup:isGroup];
	}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self.bar resignFirstResponder];

	NSDictionary *row = [self rowAtIndexPath:indexPath];
	if (!row)
		return;

	NSString *action = [row[@"action"] isKindOfClass:NSString.class] ? row[@"action"] : nil;
	if ([action isEqualToString:@"calendar"]){
		[self openCalendarForChat:_scopedChatId
							title:(_scopedChatTitle ?: @"")
						  isGroup:_scopedIsGroup];
		return;
	}

	NSString *tmeUrl = [row[@"tmeUrl"] isKindOfClass:NSString.class] ? row[@"tmeUrl"] : nil;
	if (tmeUrl.length){
		[self openRecentLinkRow:row];
		return;
	}

	NSString *hashtag = [row[@"hashtag"] isKindOfClass:NSString.class] ? row[@"hashtag"] : nil;
	if (hashtag.length){
		self.bar.text = hashtag;
		[self searchBar:self.bar textDidChange:hashtag];
		[self.bar becomeFirstResponder];
		return;
	}

	NSString *title = [row[@"title"] isKindOfClass:NSString.class] ? row[@"title"] : @"";
	BOOL isGroup = [row[@"isGroup"] boolValue];
	int64_t chatId = [row[@"chatId"] longLongValue];
	if (chatId){
		[self rememberRecent:row];
		if ([row[@"unknownType"] boolValue]){
			__weak typeof(self) weakSelf = self;
			[[TGClient shared] chatSummaryForChatId:chatId
										 completion:^(NSDictionary *chat)
			{
				TGSearchViewController *me = weakSelf;
				if (!me)
					return;
				BOOL group = [chat[@"isGroup"] boolValue] || [chat[@"isChannel"] boolValue];
				NSString *name = [chat[@"title"] isKindOfClass:NSString.class] &&
						[chat[@"title"] length] ? chat[@"title"] : title;
				[me openChat:chatId title:name isGroup:group];
			}];
			return;
		}
		[self openChat:chatId title:title isGroup:isGroup];
		return;
	}

	int64_t userId = [row[@"userId"] longLongValue];
	if (!userId)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] privateChatWithUser:userId completion:^(int64_t createdChatId){
		TGSearchViewController *me = weakSelf;
		if (!me || !createdChatId)
			return;
		[me rememberRecent:@{@"chatId": @(createdChatId), @"title": title, @"isGroup": @NO}];
		[me openChat:createdChatId title:title isGroup:NO];
	}];
}

#pragma mark - per-row actions

- (void)handleLongPress:(UILongPressGestureRecognizer *)press {
	if (press.state != UIGestureRecognizerStateBegan)
		return;
	NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:
			[press locationInView:self.tableView]];
	if (!indexPath)
		return;
	NSDictionary *row = [self rowAtIndexPath:indexPath];
	int64_t chatId = [row[@"chatId"] longLongValue];
	if (!chatId)
		return;
	[self.tableView deselectRowAtIndexPath:indexPath animated:NO];

	_sheetKind = kSheetRowActions;
	_sheetChatId = chatId;
	_sheetChatTitle = [row[@"title"] isKindOfClass:NSString.class] ? row[@"title"] : @"";
	_sheetIsGroup = [row[@"isGroup"] boolValue];

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:_sheetChatTitle
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"Open Chat"];
	[sheet addButtonWithTitle:@"Search in This Chat"];
	[sheet addButtonWithTitle:@"Jump to Date"];
	[sheet addButtonWithTitle:@"Cancel"];
	sheet.cancelButtonIndex = 3;
	[self.bar resignFirstResponder];
	[sheet showInView:self.view.window ?: self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	NSInteger kind = _sheetKind;
	_sheetKind = kSheetRowActions;

	if (kind == kSheetFilter){
		if (buttonIndex == 0)
			[self showChatTypeSheet];
		else if (buttonIndex == 1)
			[self showPeriodSheet];
		else
			[self.bar becomeFirstResponder];
		return;
	}

	if (kind == kSheetChatType){
		if (buttonIndex >= 0 && buttonIndex < (NSInteger)[[self class] chatTypeTitles].count &&
			buttonIndex != _chatTypeIndex){
			_chatTypeIndex = buttonIndex;
			[self restartSearch];
		}
		[self.bar becomeFirstResponder];
		return;
	}

	if (kind == kSheetPeriod){
		if (buttonIndex >= 0 && buttonIndex < (NSInteger)[[self class] periodTitles].count &&
			buttonIndex != _periodIndex){
			_periodIndex = buttonIndex;
			[self restartSearch];
		}
		[self.bar becomeFirstResponder];
		return;
	}

	if (kind == kSheetCalls){
		if (buttonIndex == 0 || buttonIndex == 1){
			BOOL missed = buttonIndex == 1;
			if (missed != _onlyMissedCalls){
				_onlyMissedCalls = missed;
				[self restartSearch];
			}
		}
		return;
	}

	if (kind == kSheetSender){
		if (buttonIndex == 0){
			if (_senderUserId)
				[self applySender:0 name:nil];
		} else if (buttonIndex > 0 &&
				   buttonIndex <= (NSInteger)self.senderCandidates.count){
			NSDictionary *person = self.senderCandidates[buttonIndex - 1];
			int64_t userId = [person[@"userId"] longLongValue];
			if (userId != _senderUserId)
				[self applySender:userId name:person[@"name"]];
		}
		[self.bar becomeFirstResponder];
		return;
	}

	int64_t chatId = _sheetChatId;
	NSString *title = _sheetChatTitle;
	BOOL isGroup = _sheetIsGroup;
	_sheetChatId = 0;
	if (!chatId)
		return;
	if (buttonIndex == 0){
		[self rememberRecent:@{@"chatId": @(chatId), @"title": (title ?: @""),
							   @"isGroup": @(isGroup)}];
		[self openChat:chatId title:title isGroup:isGroup];
		return;
	}
	if (buttonIndex == 1){
		[self enterChatScope:chatId title:title isGroup:isGroup];
		return;
	}
	if (buttonIndex == 2)
		[self openCalendarForChat:chatId title:title isGroup:isGroup];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.sections.count)
		return NO;
	NSDictionary *info = self.sections[indexPath.section];
	return [info[@"tags"] boolValue] || [info[@"recent"] boolValue];
}

- (NSString *)tableView:(UITableView *)tableView
		titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return @"Remove";
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
		 forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;
	NSDictionary *row = [self rowAtIndexPath:indexPath];
	NSString *tag = [row[@"hashtag"] isKindOfClass:NSString.class] ? row[@"hashtag"] : nil;
	if (!tag.length){
		[self forgetRecentChat:[row[@"chatId"] longLongValue]];
		return;
	}
	[[TGClient shared] removeSearchedForTag:tag];
	NSMutableArray *kept = [NSMutableArray array];
	for (id entry in self.recentTags){
		NSString *entryString = [entry isKindOfClass:NSString.class] ? entry : nil;
		if (!entryString.length)
			continue;
		NSString *candidate = ([entryString hasPrefix:@"#"] || [entryString hasPrefix:@"$"])
				? entryString : [@"#" stringByAppendingString:entryString];
		if ([candidate isEqualToString:tag])
			continue;
		[kept addObject:entry];
	}
	self.recentTags = kept;
	[self rebuildSections];
}

@end

// vim:ft=objc

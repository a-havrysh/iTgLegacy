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

static NSString *TGForwardDateString(NSTimeInterval unix) {
	if (unix <= 0)
		return @"";

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:unix];
	NSTimeInterval age = -[date timeIntervalSinceNow];

	static NSDateFormatter *time = nil, *weekday = nil, *full = nil;
	if (!time){
		NSLocale *fixed = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		time = [[NSDateFormatter alloc] init];
		[time setLocale:fixed];
		[time setDateFormat:@"HH:mm"];
		weekday = [[NSDateFormatter alloc] init];
		[weekday setLocale:fixed];
		[weekday setDateFormat:@"EEE"];
		full = [[NSDateFormatter alloc] init];
		[full setLocale:fixed];
		[full setDateFormat:@"dd.MM.yy"];
	}

	if (age < 24 * 3600)
		return [time stringFromDate:date];
	if (age < 7 * 24 * 3600)
		return [weekday stringFromDate:date];
	return [full stringFromDate:date];
}

static UIImage *TGForwardStretchImage(NSString *name, int leftCap) {
	UIImage *raw = [UIImage imageNamed:name];
	return [raw stretchableImageWithLeftCapWidth:leftCap topCapHeight:0];
}

@interface TGForwardPickerCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *titleSecond;
@property (nonatomic, strong) UILabel *preview;
@property (nonatomic, strong) UILabel *date;
@property (nonatomic, strong) UIImageView *groupIcon;
@property (nonatomic, assign) BOOL compact;
@end

@implementation TGForwardPickerCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	_avatar = [[UIImageView alloc] init];
	_avatar.backgroundColor = [UIColor clearColor];
	_avatar.contentMode = UIViewContentModeScaleAspectFill;
	_avatar.clipsToBounds = YES;
	[self.contentView addSubview:_avatar];

	_title = [[UILabel alloc] init];
	_title.backgroundColor = [UIColor clearColor];
	_title.textColor = [UIColor colorWithRed:0x11 / 255.0f green:0x11 / 255.0f
										blue:0x11 / 255.0f alpha:1.0f];
	_title.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:_title];

	_titleSecond = [[UILabel alloc] init];
	_titleSecond.backgroundColor = [UIColor clearColor];
	_titleSecond.textColor = _title.textColor;
	_titleSecond.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:_titleSecond];

	_groupIcon = [[UIImageView alloc] init];
	_groupIcon.backgroundColor = [UIColor clearColor];
	_groupIcon.hidden = YES;
	[self.contentView addSubview:_groupIcon];

	_preview = [[UILabel alloc] init];
	_preview.backgroundColor = [UIColor clearColor];
	_preview.textColor = [UIColor colorWithRed:0x88 / 255.0f green:0x88 / 255.0f
										  blue:0x88 / 255.0f alpha:1.0f];
	_preview.highlightedTextColor = [UIColor whiteColor];
	_preview.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:_preview];

	_date = [[UILabel alloc] init];
	_date.backgroundColor = [UIColor clearColor];
	_date.font = [UIFont boldSystemFontOfSize:13];
	_date.textAlignment = NSTextAlignmentRight;
	_date.textColor = [UIColor colorWithRed:0x33 / 255.0f green:0x7a / 255.0f
									   blue:0xcc / 255.0f alpha:1.0f];
	_date.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:_date];

	self.backgroundView = [[UIImageView alloc] init];
	self.selectedBackgroundView = [[UIImageView alloc] init];

	self.accessoryType = UITableViewCellAccessoryNone;
	self.selectionStyle = UITableViewCellSelectionStyleBlue;
	[self applyStyle];
	return self;
}

- (void)setCompact:(BOOL)compact {
	if (_compact == compact)
		return;
	_compact = compact;
	[self applyStyle];
}

- (void)applyStyle {
	if (_compact) {
		self.title.font = [UIFont systemFontOfSize:19];
		self.titleSecond.font = [UIFont boldSystemFontOfSize:19];
		self.preview.font = [UIFont systemFontOfSize:13];
		self.preview.numberOfLines = 1;
	} else {
		self.title.font = [UIFont boldSystemFontOfSize:16];
		self.titleSecond.font = self.title.font;
		self.preview.font = [UIFont systemFontOfSize:14];
		self.preview.numberOfLines = 2;
	}
	self.date.hidden = _compact;

	UIImage *plate = TGForwardStretchImage(_compact ? @"Cell102.png" : @"DialogListCell.png", 1);
	UIImage *platePressed = TGForwardStretchImage(
			_compact ? @"CellHighlighted102.png" : @"DialogListCellHighlighted.png", 1);
	if ([self.backgroundView isKindOfClass:UIImageView.class])
		((UIImageView *)self.backgroundView).image = plate;
	if ([self.selectedBackgroundView isKindOfClass:UIImageView.class])
		((UIImageView *)self.selectedBackgroundView).image = platePressed;
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGFloat w = self.contentView.bounds.size.width;
	CGFloat h = self.contentView.bounds.size.height;

	CGRect selected = self.selectedBackgroundView.frame;
	selected.origin.y = -1;
	selected.size.height = self.bounds.size.height + 1;
	self.selectedBackgroundView.frame = selected;

	CGFloat side = _compact ? kContactAvatar : kChatAvatar;
	CGFloat inset = _compact ? 5 : 8;
	_avatar.frame = CGRectMake(inset, inset, side, side);
	_avatar.layer.cornerRadius = _compact ? 4 : 5;

	CGFloat left = _compact ? 54 : 73;
	CGFloat right = _compact ? 5 : 10;
	CGFloat width = w - left - right;
	if (width < 0)
		width = 0;

	if (_compact) {
		_groupIcon.hidden = YES;
		_date.frame = CGRectZero;

		CGFloat titleHeight = _title.font.lineHeight;
		CGFloat subtitleHeight = _preview.font.lineHeight;
		CGFloat titleY;
		if (_preview.text.length == 0) {
			titleY = (CGFloat)(int)((CGFloat)(int)((h - titleHeight) / 2) - 1);
			_preview.frame = CGRectZero;
		} else {
			titleY = (CGFloat)(int)((h - titleHeight - subtitleHeight - 1) / 2);
			_preview.frame = CGRectMake(left + 1, titleY + titleHeight, width, subtitleHeight);
		}

		CGFloat firstWidth = width;
		if (_titleSecond.text.length) {
			CGFloat cap = w - left - 5 - 14;
			if (cap < 0)
				cap = 0;
			firstWidth = [_title.text sizeWithFont:_title.font].width;
			if (firstWidth > cap)
				firstWidth = cap;
			CGFloat secondX = left + firstWidth + 4;
			CGFloat secondWidth = w - secondX - 5;
			if (secondWidth < 0)
				secondWidth = 0;
			_titleSecond.frame = CGRectMake(secondX, titleY, secondWidth, titleHeight);
		} else {
			_titleSecond.frame = CGRectZero;
		}
		_title.frame = CGRectMake(left, titleY, firstWidth, titleHeight);
		return;
	}

	_titleSecond.frame = CGRectZero;

	CGFloat dateWidth = (CGFloat)(int)[_date.text sizeWithFont:_date.font].width;
	CGFloat dateX = w - dateWidth - 9;
	_date.frame = CGRectMake(dateX, 9, dateWidth, 15);

	CGFloat iconWidth = 0;
	if (_groupIcon.image) {
		iconWidth = 21;
		_groupIcon.hidden = NO;
		CGSize iconSize = _groupIcon.image.size;
		_groupIcon.frame = CGRectMake(left, 6 + 4, iconSize.width, iconSize.height);
	} else {
		_groupIcon.hidden = YES;
	}

	CGFloat titleWidth = (CGFloat)(int)(dateX - 4 - 73 - 18) - iconWidth;
	if (titleWidth < 0)
		titleWidth = 0;
	_title.frame = CGRectMake(left + iconWidth, 6, titleWidth, 20);
	_preview.frame = CGRectMake(left, 29, width, 40);
}

@end

@interface TGForwardPicker () <UIAlertViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, strong) NSArray *contacts;
@property (nonatomic, strong) NSArray *visibleRows;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSArray *sectionIndices;
@property (nonatomic, copy) NSString *chatsQuery;
@property (nonatomic, copy) NSString *contactsQuery;
@property (nonatomic, assign) CGFloat chatsOffset;
@property (nonatomic, assign) CGFloat contactsOffset;
@property (nonatomic, assign) NSInteger mode;
@property (nonatomic, assign) BOOL contactsLoaded;
@property (nonatomic, assign) BOOL picking;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSMutableDictionary *avatars;
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@property (nonatomic, strong) UIView *emptyContainer;
@property (nonatomic, strong) UILabel *emptyTitle;
@property (nonatomic, strong) UILabel *emptyText;
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
	self.chatsQuery = @"";
	self.contactsQuery = @"";
	self.sections = [NSArray array];
	self.avatars = [[NSMutableDictionary alloc] init];
	self.avatarsRequested = [[NSMutableSet alloc] init];

	self.tableView.rowHeight = kChatRowHeight;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
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
	UIImage *searchBackground = [UIImage imageNamed:@"SearchBarBackground.png"];
	if (searchBackground && [self.searchBar respondsToSelector:@selector(setBackgroundImage:)])
		[self.searchBar setBackgroundImage:searchBackground];
	else
		[self.searchBar tg_setTintColor:[UIColor colorWithWhite:0.68f alpha:1.0f]];
	self.tableView.tableHeaderView = self.searchBar;

	UIView *background = [[UIView alloc] initWithFrame:self.tableView.bounds];
	background.backgroundColor = [[TGTheme shared] listBackgroundColour];
	background.autoresizingMask =
			UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.backgroundView = background;

	UIView *overscroll = [[UIView alloc] initWithFrame:
			CGRectMake(0, -500, self.tableView.bounds.size.width, 500)];
	overscroll.backgroundColor = [UIColor colorWithRed:0xe4 / 255.0f green:0xe9 / 255.0f
												  blue:0xf0 / 255.0f alpha:1.0f];
	overscroll.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.tableView addSubview:overscroll];

	[self buildEmptyContainer];

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

- (void)buildEmptyContainer {
	UIView *background = self.tableView.backgroundView;
	if (!background)
		return;

	UIColor *grey = [UIColor colorWithRed:0x8b / 255.0f green:0x97 / 255.0f
									 blue:0xa5 / 255.0f alpha:1.0f];

	self.emptyContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 250, 0)];
	self.emptyContainer.backgroundColor = [UIColor clearColor];
	self.emptyContainer.hidden = YES;
	self.emptyContainer.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin
			| UIViewAutoresizingFlexibleBottomMargin;

	self.emptyTitle = [[UILabel alloc] init];
	self.emptyTitle.backgroundColor = [UIColor clearColor];
	self.emptyTitle.textColor = grey;
	self.emptyTitle.font = [UIFont boldSystemFontOfSize:15];
	[self.emptyContainer addSubview:self.emptyTitle];

	self.emptyText = [[UILabel alloc] init];
	self.emptyText.backgroundColor = [UIColor clearColor];
	self.emptyText.textColor = grey;
	self.emptyText.font = [UIFont systemFontOfSize:14];
	self.emptyText.textAlignment = NSTextAlignmentCenter;
	self.emptyText.lineBreakMode = NSLineBreakByWordWrapping;
	self.emptyText.numberOfLines = 0;
	[self.emptyContainer addSubview:self.emptyText];

	[background addSubview:self.emptyContainer];
}

- (void)showEmptyTitle:(NSString *)title text:(NSString *)text {
	if (!self.emptyContainer)
		return;

	self.emptyTitle.text = title;
	[self.emptyTitle sizeToFit];
	CGRect titleFrame = self.emptyTitle.frame;
	titleFrame.origin = CGPointMake((CGFloat)(int)((250 - titleFrame.size.width) / 2), 0);
	self.emptyTitle.frame = titleFrame;

	self.emptyText.text = text ?: @"";
	CGSize textSize = [self.emptyText sizeThatFits:CGSizeMake(232, 1000)];
	self.emptyText.frame = CGRectMake((CGFloat)(int)((250 - textSize.width) / 2),
			titleFrame.origin.y + titleFrame.size.height + (text.length ? 8 : 0),
			textSize.width, text.length ? textSize.height : 0);

	CGFloat height = self.emptyText.frame.origin.y + self.emptyText.frame.size.height;
	CGRect bounds = self.tableView.backgroundView.bounds;
	self.emptyContainer.frame = CGRectMake((CGFloat)(int)((bounds.size.width - 250) / 2),
			(CGFloat)(int)((bounds.size.height - height) / 2), 250, height);
	self.emptyContainer.hidden = NO;
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

	[self rebuildSections];

	if (self.visibleRows.count == 0){
		if (query.length > 0)
			[self showEmptyTitle:@"No results" text:@""];
		else if (self.mode == 1)
			[self showEmptyTitle:self.contactsLoaded ? @"You have no contacts yet" : @"Loading"
							text:self.contactsLoaded
					? @"People from your address book who use Telegram show up here."
					: @""];
		else
			[self showEmptyTitle:@"You have no conversations yet"
							text:@"Start messaging by picking someone from the Contacts section."];
	} else {
		self.emptyContainer.hidden = YES;
	}

	[self.tableView reloadData];
	[self fetchMissingAvatars];
}

- (void)rebuildSections {
	NSArray *rows = self.visibleRows ?: [NSArray array];
	if (self.mode == 0 || rows.count == 0){
		self.sections = rows.count
				? [NSArray arrayWithObject:[NSDictionary dictionaryWithObject:rows forKey:@"rows"]]
				: [NSArray array];
		self.sectionIndices = nil;
		return;
	}

	NSMutableArray *sections = [NSMutableArray array];
	NSMutableArray *indices = [NSMutableArray arrayWithObject:UITableViewIndexSearch];
	NSString *currentLetter = nil;
	NSMutableArray *current = nil;
	for (NSDictionary *row in rows){
		NSString *name = [self titleForRow:row];
		NSString *letter = name.length
				? [[name substringToIndex:1] uppercaseString] : @"#";
		unichar first = [letter characterAtIndex:0];
		if (!((first >= 'A' && first <= 'Z') || (first >= 0x0410 && first <= 0x042f)))
			letter = @"#";
		if (!currentLetter || ![letter isEqualToString:currentLetter]){
			currentLetter = letter;
			current = [NSMutableArray array];
			[sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:
					letter, @"letter", current, @"rows", nil]];
			[indices addObject:letter];
		}
		[current addObject:row];
	}

	self.sections = sections;
	self.sectionIndices = indices;
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
			UIView *separator = [[UIView alloc] initWithFrame:
					CGRectMake(currentX, 0, kGroupSeparatorWidth, kGroupButtonHeight)];
			NSArray *names = [NSArray arrayWithObjects:@"ButtonGroupDivider.png",
					@"ButtonGroupDivider_LeftHighlighted.png",
					@"ButtonGroupDivider_RightHighlighted.png", nil];
			for (NSUInteger j = 0; j < names.count; j++) {
				UIImageView *layer = [[UIImageView alloc] initWithImage:
						TGForwardStretchImage([names objectAtIndex:j], 6)];
				layer.tag = (NSInteger)(100 + j);
				layer.frame = separator.bounds;
				layer.alpha = (j == 0) ? 1.0f : 0.0f;
				layer.autoresizingMask =
						UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
				[separator addSubview:layer];
			}
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
		UIView *separator = [_groupSeparators objectAtIndex:i];
		UIView *normal = [separator viewWithTag:100];
		UIView *leftLit = [separator viewWithTag:101];
		UIView *rightLit = [separator viewWithTag:102];
		UIView *shown = normal;
		if (self.mode == (NSInteger)i)
			shown = leftLit;
		else if (self.mode == (NSInteger)i + 1)
			shown = rightLit;
		shown.alpha = 1.0f;
		[separator bringSubviewToFront:shown];
		if (normal != shown)
			normal.alpha = 0.0f;
		if (leftLit != shown)
			leftLit.alpha = 0.0f;
		if (rightLit != shown)
			rightLit.alpha = 0.0f;
	}
}

- (void)groupButtonPressed:(UIButton *)button {
	if (self.mode == button.tag)
		return;

	if (self.mode == 0){
		self.chatsQuery = self.query;
		self.chatsOffset = self.tableView.contentOffset.y;
	} else {
		self.contactsQuery = self.query;
		self.contactsOffset = self.tableView.contentOffset.y;
	}

	self.mode = button.tag;
	self.query = (self.mode == 0) ? self.chatsQuery : self.contactsQuery;
	self.searchBar.text = self.query;
	[self updateGroupImages];
	self.tableView.rowHeight = (self.mode == 0) ? kChatRowHeight : kContactRowHeight;
	[self refreshRows];
	CGFloat offset = (self.mode == 0) ? self.chatsOffset : self.contactsOffset;
	[self.tableView setContentOffset:CGPointMake(0, offset) animated:NO];
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

- (NSArray *)rowsInSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return [NSArray array];
	NSArray *rows = [[self.sections objectAtIndex:section] objectForKey:@"rows"];
	return [rows isKindOfClass:NSArray.class] ? rows : [NSArray array];
}

- (NSDictionary *)rowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *rows = [self rowsInSection:indexPath.section];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count)
		return nil;
	NSDictionary *row = [rows objectAtIndex:indexPath.row];
	return [row isKindOfClass:NSDictionary.class] ? row : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[self rowsInSection:section].count;
}

- (NSString *)letterForSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return nil;
	NSString *letter = [[self.sections objectAtIndex:section] objectForKey:@"letter"];
	return [letter isKindOfClass:NSString.class] ? letter : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return [self letterForSection:section] ? 25 : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *letter = [self letterForSection:section];
	if (!letter)
		return nil;

	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, 25)];
	container.clipsToBounds = NO;
	container.backgroundColor = [UIColor clearColor];

	UIImageView *plate = [[UIImageView alloc] initWithFrame:
			CGRectMake(0, -1, container.bounds.size.width, 26)];
	plate.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	plate.image = [UIImage imageNamed:
			(section == 0) ? @"CategoryDividerFirst.png" : @"CategoryDivider.png"];
	[container addSubview:plate];

	UILabel *label = [[UILabel alloc] init];
	label.font = [UIFont boldSystemFontOfSize:15];
	label.backgroundColor = [UIColor clearColor];
	label.textColor = [UIColor whiteColor];
	label.shadowColor = [UIColor colorWithRed:0x88 / 255.0f green:0x92 / 255.0f
										 blue:0x9c / 255.0f alpha:1.0f];
	label.shadowOffset = CGSizeMake(0, -1);
	label.numberOfLines = 1;
	label.text = letter;
	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 10, 1);
	[container addSubview:label];

	return container;
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
	return self.sectionIndices.count > 1 ? self.sectionIndices : nil;
}

- (NSInteger)tableView:(UITableView *)tableView
sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
	if (index == 0){
		[tableView setContentOffset:CGPointMake(0, -tableView.contentInset.top) animated:NO];
		return -1;
	}
	NSUInteger found = [self.sectionIndices indexOfObject:title];
	if (found == NSNotFound)
		return -1;
	return (NSInteger)found - 1;
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

	cell.compact = (self.mode == 1);
	cell.title.text = title;
	cell.titleSecond.text = @"";
	cell.date.text = @"";
	cell.groupIcon.image = nil;

	NSString *preview = @"";
	if (self.mode == 0){
		NSString *text = row[@"text"];
		if ([text isKindOfClass:NSString.class])
			preview = text;
		cell.date.text = TGForwardDateString([row[@"date"] doubleValue]);
		if ([row[@"isGroup"] boolValue])
			cell.groupIcon.image = [UIImage imageNamed:@"DialogListGroupChatIcon.png"];
		cell.preview.textColor = [UIColor colorWithRed:0x88 / 255.0f green:0x88 / 255.0f
												  blue:0x88 / 255.0f alpha:1.0f];
	} else {
		NSString *first = [row[@"first_name"] isKindOfClass:NSString.class] ? row[@"first_name"] : @"";
		NSString *last = [row[@"last_name"] isKindOfClass:NSString.class] ? row[@"last_name"] : @"";
		if (first.length && last.length){
			cell.title.text = first;
			cell.titleSecond.text = last;
		}
		NSString *status = row[@"statusText"];
		if ([status isKindOfClass:NSString.class])
			preview = status;
		BOOL online = [row[@"isOnline"] boolValue];
		cell.preview.textColor = online
				? [UIColor colorWithRed:0x07 / 255.0f green:0x79 / 255.0f
									blue:0xd0 / 255.0f alpha:1.0f]
				: [UIColor colorWithWhite:0 alpha:0.53f];
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

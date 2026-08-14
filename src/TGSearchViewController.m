#import "TGSearchViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGClient+Search.h"
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

@interface TGSearchResultCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
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
				viewSize.width - kSearchTextLeft - kSearchTextRight - 1, subtitleHeight);
	}
	_subtitleLabel.hidden = !hasSubtitle;
	_titleLabel.frame = CGRectMake(kSearchTextLeft, y, textWidth, titleHeight);
	if (dateWidth > 0){
		_dateLabel.frame = CGRectMake(viewSize.width - kSearchTextRight - dateWidth,
									  y + 1, dateWidth, titleHeight);
	}
}

@end

static NSString *const kSearchRecentsKey = @"TGSearchRecentPeers";
static const NSUInteger kSearchRecentsLimit = 12;

@interface TGSearchViewController () <UISearchBarDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UISearchBar *bar;
@property (nonatomic, strong) NSArray *chatHits;      // chats whose title matches
@property (nonatomic, strong) NSArray *contactHits;
@property (nonatomic, strong) NSArray *globalHits;
@property (nonatomic, strong) NSArray *messageHits;   // messages from the server
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
@property (nonatomic, strong) UIView *scopeBar;
@property (nonatomic, strong) UIButton *scopeChatButton;
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
}

+ (NSArray *)scopeTitles {
	return @[@"All", @"Media", @"Links", @"Files", @"Voice"];
}

+ (NSString *)filterForScope:(NSInteger)scope {
	switch (scope){
		case 1: return @"searchMessagesFilterPhotoAndVideo";
		case 2: return @"searchMessagesFilterUrl";
		case 3: return @"searchMessagesFilterDocument";
		case 4: return @"searchMessagesFilterVoiceNote";
		default: return nil;
	}
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

	// The one thing the pinned bar could not do: get out of the way. iOS 7 has
	// this, and it is the whole reason search moved to a page.
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
		if (!me->_query.length)
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
		if (!me->_query.length)
			[me rebuildSections];
	}];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGSize size = self.view.bounds.size;
	_statusLabel.frame = CGRectMake(0, (CGFloat)(int)(size.height / 3), size.width, 40);
	[self layoutScopeBar];
}

#pragma mark - scope bar

- (void)buildScopeBar {
	CGFloat width = self.view.bounds.size.width;
	if (width < 1)
		width = 320;

	_scopeBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 36)];
	_scopeBar.backgroundColor = [TGTheme shared].isFlat
			? [[TGTheme shared] listBackgroundColour]
			: [UIColor colorWithRed:0xc3 / 255.0f green:0xcb / 255.0f
								blue:0xd4 / 255.0f alpha:1.0f];

	UIImage *background = [UIImage imageNamed:@"SearchBarBackground.png"];
	if (background && ![TGTheme shared].isFlat){
		UIImageView *backgroundView = [[UIImageView alloc] initWithImage:background];
		backgroundView.frame = CGRectMake(0, 0, width, 36);
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

	_scopeChatButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_scopeChatButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	_scopeChatButton.hidden = YES;
	[self styleScopeButton:_scopeChatButton selected:YES];
	[_scopeChatButton addTarget:self action:@selector(leaveChatScope)
			   forControlEvents:UIControlEventTouchDown];
	[_scopeBar addSubview:_scopeChatButton];

	[self layoutScopeBar];
	self.tableView.tableHeaderView = _scopeBar;
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
		self.tableView.tableHeaderView = _scopeBar;
	}

	if (_scopedChatId){
		for (UIButton *button in _scopeButtons)
			button.hidden = YES;
		_scopeChatButton.hidden = NO;
		_scopeChatButton.frame = CGRectMake(6, 3, width - 12, 30);
		return;
	}

	_scopeChatButton.hidden = YES;
	NSUInteger count = _scopeButtons.count;
	if (!count)
		return;
	CGFloat available = width - 12;
	CGFloat each = (CGFloat)(int)(available / count);
	for (NSUInteger i = 0; i < count; i++){
		UIButton *button = _scopeButtons[i];
		button.hidden = NO;
		CGFloat buttonWidth = (i == count - 1) ? (available - each * (count - 1)) : each;
		button.frame = CGRectMake(6 + each * i, 3, buttonWidth, 30);
	}
}

- (void)scopeTapped:(UIButton *)button {
	if (button.tag == _scope)
		return;
	_scope = button.tag;
	for (UIButton *other in _scopeButtons)
		[self styleScopeButton:other selected:(other.tag == _scope)];
	[self restartSearch];
}

- (void)enterChatScope:(int64_t)chatId title:(NSString *)title {
	_scopedChatId = chatId;
	_scopedChatTitle = title.length ? title : @"Chat";
	[_scopeChatButton setTitle:[@"In: " stringByAppendingString:_scopedChatTitle]
					  forState:UIControlStateNormal];
	self.bar.placeholder = [@"Search in " stringByAppendingString:_scopedChatTitle];
	[self layoutScopeBar];
	[self.bar becomeFirstResponder];
	[self restartSearch];
}

- (void)leaveChatScope {
	if (!_scopedChatId)
		return;
	_scopedChatId = 0;
	_scopedChatTitle = nil;
	self.bar.placeholder = @"Search";
	[self layoutScopeBar];
	[self restartSearch];
}

- (void)restartSearch {
	_generation++;
	_pending = 0;
	_loadingMore = NO;
	_messagesOffset = @"";
	_messagesFromId = 0;
	self.messageHits = @[];
	self.globalHits = @[];
	self.hashtagHits = @[];
	[self runLocalSearch];
	if (!_query.length)
		return;
	[self runServerSearch:_query generation:_generation];
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
}

- (void)clearRecentTags {
	[[TGClient shared] clearSearchedForTagsIncludingCashtags:NO];
	[[TGClient shared] clearSearchedForTagsIncludingCashtags:YES];
	self.recentTags = @[];
	[self rebuildSections];
}

- (void)clearRecents {
	self.recents = @[];
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

		UIColor *placeholderColour = [TGTheme shared].isFlat
				? [[TGTheme shared] secondaryTextColour]
				: [UIColor colorWithRed:0x8d / 255.0f green:0x92 / 255.0f
								   blue:0x98 / 255.0f alpha:1.0f];
		if ([field respondsToSelector:@selector(setAttributedPlaceholder:)] &&
			field.placeholder.length){
			field.attributedPlaceholder = [[NSAttributedString alloc]
					initWithString:field.placeholder
						attributes:@{NSForegroundColorAttributeName: placeholderColour}];
		}

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

	self.messageHits = @[];
	self.globalHits = @[];
	self.hashtagHits = @[];
	[self runLocalSearch];

	if (!_query.length)
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
							@"subtitle": ([c[@"text"] isKindOfClass:NSString.class] ? c[@"text"] : @""),
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
							@"subtitle": (username.length ? [@"@" stringByAppendingString:username] : @""),
							@"userId": @(userId),
							@"chatId": @0,
							@"isGroup": @NO,
							@"fileId": ([[TGClient shared] photoFileIdForUserId:userId] ?: [NSNull null])}];
	}
	self.contactHits = people;

	[self rebuildSections];
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
		NSString *subtitle = text;
		if (!inChat && sender.length && text.length)
			subtitle = [NSString stringWithFormat:@"%@: %@", sender, text];
		[rows addObject:@{@"title": title,
						  @"subtitle": subtitle,
						  @"date": [self shortDateFor:m[@"date"]],
						  @"chatId": @(chatId),
						  @"isGroup": @([m[@"isGroup"] boolValue]),
						  @"fileId": ([[TGClient shared] photoFileIdForChat:chatId] ?: [NSNull null])}];
	}
	return rows;
}

- (void)appendMessageRows:(NSArray *)rows {
	if (!rows.count)
		return;
	NSMutableArray *all = [NSMutableArray arrayWithArray:self.messageHits];
	[all addObjectsFromArray:rows];
	self.messageHits = all;
}

- (void)runServerSearch:(NSString *)query generation:(NSUInteger)generation {
	if (generation != _generation || !query.length)
		return;

	if (_scopedChatId){
		_pending = 1;
		[self rebuildSections];
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
	[[TGClient shared] searchMessagesWithQuery:query
										filter:[[self class] filterForScope:_scope]
										offset:offset
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

- (void)loadChatMessagesPage:(NSString *)query generation:(NSUInteger)generation {
	int64_t chatId = _scopedChatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchMessagesInChat:chatId
									  query:query
							   senderUserId:0
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
	if (_loadingMore || _pending > 0 || !_query.length)
		return;
	NSUInteger generation = _generation;
	if (_scopedChatId){
		if (!_messagesFromId)
			return;
		_loadingMore = YES;
		[self loadChatMessagesPage:_query generation:generation];
		return;
	}
	if (!_messagesOffset.length)
		return;
	_loadingMore = YES;
	if ([[self class] isTagQuery:_query])
		[self loadTagMessagesPage:_query generation:generation];
	else
		[self loadGlobalMessagesPage:_query generation:generation];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
	forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.section != (NSInteger)self.sections.count - 1)
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
	[[TGClient shared] request:@{@"@type": @"searchPublicChats", @"query": query}
					completion:^(NSDictionary *result)
	{
		TGSearchViewController *me = weakSelf;
		if (!me || generation != me->_generation)
			return;

		NSArray *ids = [result[@"chat_ids"] isKindOfClass:NSArray.class] ? result[@"chat_ids"] : @[];
		NSMutableSet *known = [NSMutableSet set];
		for (NSDictionary *row in me.chatHits)
			[known addObject:@([row[@"chatId"] longLongValue])];

		NSMutableArray *wanted = [NSMutableArray array];
		for (id chatId in ids){
			if (![chatId isKindOfClass:NSNumber.class])
				continue;
			if ([known containsObject:@([chatId longLongValue])])
				continue;
			[wanted addObject:chatId];
			if (wanted.count >= 8)
				break;
		}

		if (!wanted.count){
			if (me->_pending > 0)
				me->_pending--;
			[me rebuildSections];
			return;
		}

		__block NSInteger outstanding = (NSInteger)wanted.count;
		NSMutableArray *rows = [NSMutableArray array];
		for (NSNumber *chatId in wanted){
			[[TGClient shared] request:@{@"@type": @"getChat", @"chat_id": chatId}
							completion:^(NSDictionary *chat)
			{
				TGSearchViewController *inner = weakSelf;
				if (!inner || generation != inner->_generation)
					return;
				NSString *title = [chat[@"title"] isKindOfClass:NSString.class] ? chat[@"title"] : nil;
				NSString *type = nil;
				if ([chat[@"type"] isKindOfClass:NSDictionary.class])
					type = chat[@"type"][@"@type"];
				if (title.length)
					[rows addObject:@{@"title": title,
									  @"subtitle": @"",
									  @"chatId": chatId,
									  @"isGroup": @(type != nil && ![type isEqualToString:@"chatTypePrivate"]),
									  @"fileId": ([[TGClient shared] photoFileIdForChat:
											  [chatId longLongValue]] ?: [NSNull null])}];
				if (--outstanding > 0)
					return;
				inner.globalHits = rows;
				if (inner->_pending > 0)
					inner->_pending--;
				[inner rebuildSections];
			}];
		}
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
	if (!_query.length){
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
							  @"fileId": ([r[@"photoFileId"] isKindOfClass:NSNumber.class]
									  ? r[@"photoFileId"]
									  : ([[TGClient shared] photoFileIdForChat:chatId]
											  ?: [NSNull null]))}];
		}
		if (rows.count)
			[built addObject:@{@"title": @"Recent", @"rows": rows, @"recent": @YES}];

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
		if (self.chatHits.count)
			[built addObject:@{@"title": @"Conversations", @"rows": self.chatHits}];
		if (self.contactHits.count)
			[built addObject:@{@"title": @"Contacts", @"rows": self.contactHits}];
		if (self.globalHits.count)
			[built addObject:@{@"title": @"Global Search", @"rows": self.globalHits}];
		if (self.hashtagHits.count)
			[built addObject:@{@"title": @"Hashtags", @"rows": self.hashtagHits}];
		if (self.messageHits.count){
			NSString *title = @"Messages";
			if (_scopedChatId)
				title = [@"In " stringByAppendingString:(_scopedChatTitle ?: @"Chat")];
			else if ([[self class] isTagQuery:_query])
				title = @"Public Posts";
			else if (_scope != 0)
				title = [[self class] scopeTitles][_scope];
			[built addObject:@{@"title": title, @"rows": self.messageHits, @"paged": @YES}];
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
	if (!_query.length){
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
	return ((NSDictionary *)self.sections[section])[@"title"];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (section >= (NSInteger)self.sections.count)
		return nil;

	NSDictionary *info = self.sections[section];
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
	return kSearchSectionHeight;
}

- (UIImage *)avatarForChat:(int64_t)chatId
					 title:(NSString *)title
					fileId:(NSNumber *)fileId
{
	UIImage *cached = [fileId isKindOfClass:NSNumber.class] ? self.avatars[fileId] : nil;
	if (cached)
		return cached;

	if ([fileId isKindOfClass:NSNumber.class] &&
		![self.avatarsRequested containsObject:fileId]){
		[self.avatarsRequested addObject:fileId];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			TGSearchViewController *me = weakSelf;
			UIImage *photo = path ? [UIImage imageWithContentsOfFile:path] : nil;
			if (!me || !photo)
				return;
			UIGraphicsBeginImageContextWithOptions(
					CGSizeMake(kSearchAvatar, kSearchAvatar), NO, 0);
			[photo drawInRect:CGRectMake(0, 0, kSearchAvatar, kSearchAvatar)];
			me.avatars[fileId] = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
			[me.tableView reloadData];
		}];
	}

	return [TGIcons avatarWithInitials:
				(title.length ? [title substringToIndex:1].uppercaseString : @"?")
								  size:kSearchAvatar
							  colourId:chatId];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
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

	cell.titleLabel.text = title;
	cell.subtitleLabel.text = subtitle;
	cell.dateLabel.text = [row[@"date"] isKindOfClass:NSString.class] ? row[@"date"] : @"";

	if ([row[@"hashtag"] isKindOfClass:NSString.class]){
		cell.avatarView.image = nil;
		[cell setNeedsLayout];
		return cell;
	}

	cell.avatarView.image = [self avatarForChat:colourId
										  title:title
										 fileId:[row[@"fileId"] isKindOfClass:NSNumber.class]
												 ? row[@"fileId"] : nil];

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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self.bar resignFirstResponder];

	NSDictionary *row = [self rowAtIndexPath:indexPath];
	if (!row)
		return;

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
	[sheet addButtonWithTitle:@"Cancel"];
	sheet.cancelButtonIndex = 2;
	[self.bar resignFirstResponder];
	[sheet showInView:self.view.window ?: self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
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
	if (buttonIndex == 1)
		[self enterChatScope:chatId title:title];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.sections.count)
		return NO;
	return [((NSDictionary *)self.sections[indexPath.section])[@"tags"] boolValue];
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
	if (!tag.length)
		return;
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

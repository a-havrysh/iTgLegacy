#import "TGSearchViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
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
	CGFloat titleHeight = (CGFloat)(int)(_titleLabel.font.lineHeight);
	CGFloat subtitleHeight = (CGFloat)(int)(_subtitleLabel.font.lineHeight);
	BOOL hasSubtitle = _subtitleLabel.text.length != 0;

	CGFloat y;
	if (!hasSubtitle){
		y = (CGFloat)(int)((viewSize.height - titleHeight) / 2) - 1;
	} else {
		y = (CGFloat)(int)((viewSize.height - titleHeight - subtitleHeight - 1) / 2);
		_subtitleLabel.frame = CGRectMake(kSearchTextLeft + 1, y + titleHeight,
										  textWidth, subtitleHeight);
	}
	_subtitleLabel.hidden = !hasSubtitle;
	_titleLabel.frame = CGRectMake(kSearchTextLeft, y, textWidth, titleHeight);
}

@end

static NSString *const kSearchRecentsKey = @"TGSearchRecentPeers";
static const NSUInteger kSearchRecentsLimit = 12;

@interface TGSearchViewController () <UISearchBarDelegate>
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
@end

@implementation TGSearchViewController {
	BOOL _searchFieldStyled;
	NSString *_query;
	NSUInteger _generation;
	NSInteger _pending;
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
	_query = @"";
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

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] contactsWithCompletion:^(NSArray *users){
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		me.contacts = users ?: @[];
		[me runLocalSearch];
	}];

	[self rebuildSections];
	[self.bar becomeFirstResponder];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGSize size = self.view.bounds.size;
	_statusLabel.frame = CGRectMake(0, (CGFloat)(int)(size.height / 3), size.width, 40);
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

	self.messageHits = @[];
	self.globalHits = @[];
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
	if (!_query.length){
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

- (void)runServerSearch:(NSString *)query generation:(NSUInteger)generation {
	if (generation != _generation || !query.length)
		return;

	_pending = 2;
	[self rebuildSections];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchMessages:query completion:^(NSArray *messages){
		TGSearchViewController *me = weakSelf;
		// A slower answer to an older query must not replace a newer one.
		if (!me || generation != me->_generation)
			return;
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *m in messages){
			if (![m isKindOfClass:NSDictionary.class])
				continue;
			NSString *title = [m[@"chatTitle"] isKindOfClass:NSString.class] ? m[@"chatTitle"] : @"";
			NSString *text = [m[@"text"] isKindOfClass:NSString.class] ? m[@"text"] : @"";
			if ([m[@"chatId"] longLongValue] == 0)
				continue;
			[rows addObject:@{@"title": (title.length ? title : @"Chat"),
							  @"subtitle": text,
							  @"chatId": m[@"chatId"],
							  @"isGroup": @([m[@"isGroup"] boolValue]),
							  @"fileId": [NSNull null]}];
		}
		me.messageHits = rows;
		if (me->_pending > 0)
			me->_pending--;
		[me rebuildSections];
	}];

	[self searchPublicChats:query generation:generation];
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
		if (self.recents.count){
			NSMutableArray *rows = [NSMutableArray array];
			for (NSDictionary *r in self.recents)
				[rows addObject:@{@"title": (r[@"title"] ?: @""),
								  @"subtitle": @"",
								  @"chatId": (r[@"chatId"] ?: @0),
								  @"isGroup": @([r[@"isGroup"] boolValue]),
								  @"fileId": ([[TGClient shared] photoFileIdForChat:
										  [r[@"chatId"] longLongValue]] ?: [NSNull null])}];
			[built addObject:@{@"title": @"Recent", @"rows": rows, @"recent": @YES}];
		}
	} else {
		if (self.chatHits.count)
			[built addObject:@{@"title": @"Conversations", @"rows": self.chatHits}];
		if (self.contactHits.count)
			[built addObject:@{@"title": @"Contacts", @"rows": self.contactHits}];
		if (self.globalHits.count)
			[built addObject:@{@"title": @"Global Search", @"rows": self.globalHits}];
		if (self.messageHits.count)
			[built addObject:@{@"title": @"Messages", @"rows": self.messageHits}];
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
		_statusLabel.text = @"Search for messages or users";
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

	if (isRecent){
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
		[clear addTarget:self action:@selector(clearRecents)
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

@end

// vim:ft=objc

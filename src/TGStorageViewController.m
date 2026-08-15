#import "TGStorageViewController.h"
#import "TGClient.h"
#import "TGClient+Storage.h"
#import "TGTheme.h"

typedef enum {
	TGStorageActionKinds = 0,
	TGStorageActionChat,
	TGStorageActionOptimise
} TGStorageAction;

enum {
	TGStorageSheetConfirm = 3301,
	TGStorageSheetTTL,
	TGStorageSheetSize
};

@interface TGStorageChatViewController : UITableViewController <UIActionSheetDelegate>
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *chatTitle;
@property (nonatomic, assign) long long bytes;
@property (nonatomic, assign) NSInteger files;
@property (nonatomic, copy) void (^didChange)(void);
@end

@interface TGStorageViewController () <UIActionSheetDelegate>
@property (nonatomic, assign) long long bytes;
@property (nonatomic, assign) NSInteger files;
@property (nonatomic, assign) BOOL working;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL refreshing;
@property (nonatomic, assign) BOOL detailLoading;
@property (nonatomic, assign) BOOL detailLoaded;
@property (nonatomic, strong) NSDictionary *overview;
@property (nonatomic, strong) NSArray *typeRows;
@property (nonatomic, strong) NSArray *chatRows;
@property (nonatomic, strong) NSArray *pendingKinds;
@property (nonatomic, assign) int64_t pendingChatId;
@property (nonatomic, assign) TGStorageAction pendingAction;
@property (nonatomic, copy) NSString *pendingTitle;
@end

static UIColor *TGStorageRGB(int rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:1.0f];
}

static NSString *TGStorageKindName(NSString *kind) {
	static NSDictionary *names = nil;
	if (!names)
		names = @{@"fileTypePhoto": @"Photos",
				  @"fileTypeVideo": @"Videos",
				  @"fileTypeVideoNote": @"Video messages",
				  @"fileTypeAnimation": @"GIFs",
				  @"fileTypeDocument": @"Files",
				  @"fileTypeAudio": @"Music",
				  @"fileTypeVoiceNote": @"Voice messages",
				  @"fileTypeSticker": @"Stickers",
				  @"fileTypeProfilePhoto": @"Profile photos",
				  @"fileTypeThumbnail": @"Thumbnails",
				  @"fileTypeWallpaper": @"Wallpapers",
				  @"fileTypeSecret": @"Secret media",
				  @"fileTypeSecretThumbnail": @"Secret thumbnails"};
	NSString *pretty = [names objectForKey:kind];
	if (pretty)
		return pretty;
	if ([kind hasPrefix:@"fileType"])
		return [kind substringFromIndex:8];
	return kind;
}

enum {
	TGStorageSectionSummary = 0,
	TGStorageSectionTypes,
	TGStorageSectionChats,
	TGStorageSectionPolicy,
	TGStorageSectionClear,
	TGStorageSectionEverything,
	TGStorageSectionCount
};

static NSString *TGHumanSize(long long bytes);

static const NSInteger TGStorageTTLValues[4] = {3 * 24 * 60 * 60,
												7 * 24 * 60 * 60,
												30 * 24 * 60 * 60,
												-1};

static const long long TGStorageSizeValues[4] = {5LL * 1024 * 1024 * 1024,
												 16LL * 1024 * 1024 * 1024,
												 32LL * 1024 * 1024 * 1024,
												 -1};

static NSString *TGStorageTTLName(NSInteger ttl) {
	if (ttl <= 0)
		return @"Forever";
	if (ttl <= 3 * 24 * 60 * 60)
		return @"3 days";
	if (ttl <= 7 * 24 * 60 * 60)
		return @"1 week";
	if (ttl <= 30 * 24 * 60 * 60)
		return @"1 month";
	return [NSString stringWithFormat:@"%ld days", (long)(ttl / (24 * 60 * 60))];
}

static NSString *TGStorageSizeName(long long maxBytes) {
	if (maxBytes <= 0)
		return @"No limit";
	return TGHumanSize(maxBytes);
}

@implementation TGStorageViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Storage";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] bubbleBorderColour];
	[self refresh];
	[self refreshDetail];
}

- (void)refresh {
	if (self.refreshing)
		return;
	self.refreshing = YES;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(statsTimedOut)
											   object:nil];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storageStatsWithCompletion:^(long long bytes, NSInteger files){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.refreshing)
			return;
		[NSObject cancelPreviousPerformRequestsWithTarget:strongSelf
												 selector:@selector(statsTimedOut)
												   object:nil];
		strongSelf.refreshing = NO;
		strongSelf.loaded = YES;
		strongSelf.bytes = bytes < 0 ? 0 : bytes;
		strongSelf.files = files < 0 ? 0 : files;
		[strongSelf.tableView reloadData];
	}];

	[[TGClient shared] storageOverviewWithCompletion:^(NSDictionary *overview){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !overview)
			return;
		strongSelf.overview = overview;
		[strongSelf.tableView reloadData];
	}];

	[self performSelector:@selector(statsTimedOut) withObject:nil afterDelay:20.0];
}

- (void)refreshDetail {
	if (self.detailLoading)
		return;
	self.detailLoading = YES;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storageUsageByFileTypeWithCompletion:^(NSDictionary *sizes, long long totalBytes){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.typeRows = [strongSelf sortedTypeRowsFrom:sizes];
		[[TGClient shared] storageUsageByChatWithLimit:24 completion:^(NSArray *chats){
			typeof(self) inner = weakSelf;
			if (!inner)
				return;
			[NSObject cancelPreviousPerformRequestsWithTarget:inner
													 selector:@selector(detailTimedOut)
													   object:nil];
			inner.chatRows = [inner filteredChatRowsFrom:chats];
			inner.detailLoading = NO;
			inner.detailLoaded = YES;
			[inner.tableView reloadData];
		}];
	}];

	[self performSelector:@selector(detailTimedOut) withObject:nil afterDelay:90.0];
}

- (void)detailTimedOut {
	if (!self.detailLoading)
		return;
	self.detailLoading = NO;
	self.detailLoaded = YES;
	[self.tableView reloadData];
}

- (NSArray *)sortedTypeRowsFrom:(NSDictionary *)sizes {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSString *kind in sizes){
		NSDictionary *entry = [sizes objectForKey:kind];
		if (![entry isKindOfClass:[NSDictionary class]])
			continue;
		long long size = [[entry objectForKey:@"size"] longLongValue];
		if (size <= 0)
			continue;
		[rows addObject:@{@"kind": kind,
						  @"title": TGStorageKindName(kind),
						  @"size": [NSNumber numberWithLongLong:size],
						  @"count": [entry objectForKey:@"count"] ?: [NSNumber numberWithInt:0]}];
	}
	[rows sortUsingComparator:^NSComparisonResult(id a, id b){
		long long sa = [[a objectForKey:@"size"] longLongValue];
		long long sb = [[b objectForKey:@"size"] longLongValue];
		if (sa == sb)
			return NSOrderedSame;
		return sa > sb ? NSOrderedAscending : NSOrderedDescending;
	}];
	return rows;
}

- (NSArray *)filteredChatRowsFrom:(NSArray *)chats {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *chat in chats){
		if (![chat isKindOfClass:[NSDictionary class]])
			continue;
		long long size = [[chat objectForKey:@"size"] longLongValue];
		if (size <= 0)
			continue;
		int64_t chatId = (int64_t)[[chat objectForKey:@"chatId"] longLongValue];
		NSString *title = [chat objectForKey:@"title"];
		if (![title isKindOfClass:[NSString class]] || !title.length)
			title = chatId == 0 ? @"Other files" : @"Unknown chat";
		[rows addObject:@{@"chatId": [NSNumber numberWithLongLong:chatId],
						  @"title": title,
						  @"size": [NSNumber numberWithLongLong:size]}];
		if (rows.count >= 24)
			break;
	}
	return rows;
}

- (void)statsTimedOut {
	if (!self.refreshing)
		return;
	self.refreshing = NO;
	self.working = NO;
	[self.tableView reloadData];
}

- (BOOL)cacheIsEmpty {
	return self.loaded && self.bytes <= 0 && self.files <= 0;
}

- (BOOL)canClear {
	return self.loaded && !self.working && ![self cacheIsEmpty];
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

static NSString *TGHumanSize(long long bytes) {
	if (bytes < 1024)
		return [NSString stringWithFormat:@"%lld B", bytes];
	if (bytes < 1024 * 1024)
		return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
	if (bytes < 1024LL * 1024 * 1024)
		return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024)];
	return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024 * 1024)];
}

/// Settings has its own navigation controller, and nothing was styling
/// its bar - an imported theme stopped at the top of the screen.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	if (self.loaded && !self.working)
		[self refresh];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return TGStorageSectionCount;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if (section == TGStorageSectionChats && self.detailLoaded && self.chatRows.count == 0)
		return 1;
	if (section == TGStorageSectionEverything)
		return 12;
	return 46;
}

- (NSString *)titleForSection:(NSInteger)section {
	switch (section){
		case TGStorageSectionSummary: return @"Cache";
		case TGStorageSectionTypes: return @"By media type";
		case TGStorageSectionChats: return @"By chat";
		case TGStorageSectionPolicy: return @"Cache limits";
		case TGStorageSectionClear: return @"Clear";
		default: return @"";
	}
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *title = [self titleForSection:section];
	if (!title.length)
		return nil;
	if (section == TGStorageSectionChats && self.detailLoaded && self.chatRows.count == 0)
		return nil;

	BOOL dark = [[TGTheme shared] isDark];
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, 46)];
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [[UILabel alloc] init];
	label.text = title;
	label.font = [UIFont boldSystemFontOfSize:17];
	label.backgroundColor = [UIColor clearColor];
	label.textColor = dark ? [[TGTheme shared] sectionHeaderColour]
						   : TGStorageRGB(0x697487);
	if (!dark){
		label.shadowColor = TGStorageRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 21, 16);
	[container addSubview:label];
	return container;
}

- (NSString *)footerText {
	return @"Cleared media is downloaded again when you open the message. "
		   @"Nothing is deleted from Telegram.";
}

- (CGFloat)footerHeightForWidth:(CGFloat)width {
	CGSize size = [[self footerText] sizeWithFont:[UIFont systemFontOfSize:14]
								constrainedToSize:CGSizeMake(width - 12 * 2, 1000)
									lineBreakMode:NSLineBreakByWordWrapping];
	return size.height + 7 * 2;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	return section == TGStorageSectionEverything
			? [self footerHeightForWidth:tableView.bounds.size.width] : 1;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (section != TGStorageSectionEverything)
		return nil;
	BOOL dark = [[TGTheme shared] isDark];
	CGFloat width = tableView.bounds.size.width;
	CGFloat height = [self footerHeightForWidth:width];

	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	container.backgroundColor = [UIColor clearColor];
	container.opaque = NO;

	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(1, 7, width - 2, height - 14)];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	label.text = [self footerText];
	label.font = [UIFont systemFontOfSize:14];
	label.contentMode = UIViewContentModeCenter;
	label.textAlignment = NSTextAlignmentCenter;
	label.lineBreakMode = NSLineBreakByWordWrapping;
	label.numberOfLines = 0;
	label.backgroundColor = [UIColor clearColor];
	label.textColor = dark ? [[TGTheme shared] secondaryTextColour]
						   : TGStorageRGB(0x697487);
	if (!dark){
		label.shadowColor = TGStorageRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == TGStorageSectionEverything)
		return 45;
	return 44;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section){
		case TGStorageSectionSummary:
			return self.overview ? 4 : 2;
		case TGStorageSectionTypes:
			if (!self.detailLoaded)
				return 1;
			return self.typeRows.count ? (NSInteger)self.typeRows.count : 1;
		case TGStorageSectionChats:
			if (!self.detailLoaded)
				return 1;
			return (NSInteger)self.chatRows.count;
		case TGStorageSectionPolicy:
			return 2;
		case TGStorageSectionClear:
			return 4;
		default:
			return 1;
	}
}

- (UITableViewCell *)plainCellInTable:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	[[TGTheme shared] styleCell:cell];
	BOOL dark = [[TGTheme shared] isDark];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = dark ? [[TGTheme shared] primaryTextColour]
									: [UIColor blackColor];
	cell.textLabel.highlightedTextColor = [UIColor whiteColor];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.textColor = dark ? [[TGTheme shared] cellDetailColour]
										  : TGStorageRGB(0x356596);
	cell.detailTextLabel.highlightedTextColor = [UIColor whiteColor];
	cell.textLabel.text = @"";
	cell.detailTextLabel.text = @"";
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	return cell;
}

- (NSInteger)policyTTLSeconds {
	NSDictionary *policy = [[TGClient shared] cachePolicy];
	id value = [policy objectForKey:@"ttlSeconds"];
	return value ? [value integerValue] : -1;
}

- (long long)policyMaxBytes {
	NSDictionary *policy = [[TGClient shared] cachePolicy];
	id value = [policy objectForKey:@"maxBytes"];
	return value ? [value longLongValue] : -1;
}

- (NSArray *)policyExcludedChatIds {
	NSDictionary *policy = [[TGClient shared] cachePolicy];
	NSArray *excluded = [policy objectForKey:@"excludedChatIds"];
	return [excluded isKindOfClass:[NSArray class]] ? excluded : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == TGStorageSectionEverything)
		return [self clearEverythingCellInTable:tableView];

	UITableViewCell *cell = [self plainCellInTable:tableView];
	BOOL dark = [[TGTheme shared] isDark];

	if (indexPath.section == TGStorageSectionSummary){
		BOOL busy = self.working || !self.loaded;
		switch (indexPath.row){
			case 0:
				cell.textLabel.text = @"Size on disk";
				if (busy)
					cell.accessoryView = [self spinner];
				else
					cell.detailTextLabel.text = [self cacheIsEmpty] ? @"Empty" : TGHumanSize(self.bytes);
				break;
			case 1:
				cell.textLabel.text = @"Files";
				if (busy)
					cell.accessoryView = [self spinner];
				else
					cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)self.files];
				break;
			case 2:
				cell.textLabel.text = @"Database";
				cell.detailTextLabel.text = TGHumanSize(
						[[self.overview objectForKey:@"database"] longLongValue]);
				break;
			default:
				cell.textLabel.text = @"Total";
				cell.detailTextLabel.text = TGHumanSize(
						[[self.overview objectForKey:@"total"] longLongValue]);
				break;
		}
		return cell;
	}

	if (indexPath.section == TGStorageSectionTypes){
		if (!self.detailLoaded){
			cell.textLabel.text = @"Calculating…";
			cell.textLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
											: TGStorageRGB(0x888888);
			cell.accessoryView = [self spinner];
			return cell;
		}
		if (!self.typeRows.count){
			cell.textLabel.text = @"No cached media";
			cell.textLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
											: TGStorageRGB(0x888888);
			return cell;
		}
		NSDictionary *row = [self.typeRows objectAtIndex:indexPath.row];
		cell.textLabel.text = [row objectForKey:@"title"];
		cell.detailTextLabel.text = TGHumanSize([[row objectForKey:@"size"] longLongValue]);
		if ([self canClear])
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	if (indexPath.section == TGStorageSectionChats){
		if (!self.detailLoaded){
			cell.textLabel.text = @"Calculating…";
			cell.textLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
											: TGStorageRGB(0x888888);
			cell.accessoryView = [self spinner];
			return cell;
		}
		NSDictionary *row = [self.chatRows objectAtIndex:indexPath.row];
		cell.textLabel.text = [row objectForKey:@"title"];
		cell.detailTextLabel.text = TGHumanSize([[row objectForKey:@"size"] longLongValue]);
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	if (indexPath.section == TGStorageSectionPolicy){
		if (indexPath.row == 0){
			cell.textLabel.text = @"Keep media for";
			cell.detailTextLabel.text = TGStorageTTLName([self policyTTLSeconds]);
		} else {
			cell.textLabel.text = @"Maximum cache size";
			cell.detailTextLabel.text = TGStorageSizeName([self policyMaxBytes]);
		}
		if (self.working){
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.textLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
											: TGStorageRGB(0x888888);
		} else {
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		}
		return cell;
	}

	static NSArray *labels = nil;
	if (!labels)
		labels = @[@"Clear photos", @"Clear videos", @"Clear other files", @"Optimise storage"];
	cell.textLabel.text = [labels objectAtIndex:indexPath.row];
	if (indexPath.row == 3){
		NSInteger ttl = [self policyTTLSeconds];
		long long limit = [self policyMaxBytes];
		if (ttl > 0)
			cell.detailTextLabel.text = [NSString stringWithFormat:@"older than %@",
					[TGStorageTTLName(ttl) lowercaseString]];
		else if (limit > 0)
			cell.detailTextLabel.text = [NSString stringWithFormat:@"down to %@",
					TGHumanSize(limit)];
		else
			cell.detailTextLabel.text = @"no limits set";
	}
	if ([self canClear]){
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	} else {
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.textLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
										: TGStorageRGB(0x888888);
		if (self.working)
			cell.accessoryView = [self spinner];
	}
	return cell;
}

- (UIView *)spinner {
	UIActivityIndicatorViewStyle style = [[TGTheme shared] isDark]
			? UIActivityIndicatorViewStyleWhite
			: UIActivityIndicatorViewStyleGray;
	UIActivityIndicatorView *view = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:style];
	[view startAnimating];
	return view;
}

- (UITableViewCell *)clearEverythingCellInTable:(UITableView *)tableView {
	static NSString *reuse = @"TGStorageClearAllCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:reuse];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.backgroundColor = [UIColor clearColor];
		cell.backgroundView = [[UIView alloc] initWithFrame:CGRectZero];
		cell.backgroundView.backgroundColor = [UIColor clearColor];
		cell.contentView.backgroundColor = [UIColor clearColor];
		cell.opaque = NO;

		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.tag = 772;
		button.frame = CGRectMake(9, 0, cell.contentView.bounds.size.width - 18, 45);
		button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		button.adjustsImageWhenDisabled = NO;
		button.exclusiveTouch = YES;
		button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		[button setTitle:@"Clear everything" forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleShadowColor:[UIColor colorWithRed:0xa1 / 255.0f green:0x06 / 255.0f
													 blue:0x03 / 255.0f alpha:0.5f]
						   forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithRed:0xa1 / 255.0f green:0x06 / 255.0f
													 blue:0x03 / 255.0f alpha:0.5f]
						   forState:UIControlStateHighlighted];

		UIImage *raw = [UIImage imageNamed:@"MenuRedButton.png"];
		UIImage *rawHighlighted = [UIImage imageNamed:@"MenuRedButton_Highlighted.png"];
		if (raw)
			[button setBackgroundImage:[raw stretchableImageWithLeftCapWidth:
					(int)(raw.size.width / 2) topCapHeight:(int)(raw.size.height / 2)]
							  forState:UIControlStateNormal];
		if (rawHighlighted)
			[button setBackgroundImage:[rawHighlighted stretchableImageWithLeftCapWidth:
					(int)(rawHighlighted.size.width / 2)
					topCapHeight:(int)(rawHighlighted.size.height / 2)]
							  forState:UIControlStateHighlighted];
		if (!raw)
			button.backgroundColor = TGStorageRGB(0xc4362f);
		[button addTarget:self action:@selector(clearEverythingPressed)
		 forControlEvents:UIControlEventTouchUpInside];
		[cell.contentView addSubview:button];
	}
	UIButton *button = (UIButton *)[cell.contentView viewWithTag:772];
	button.frame = CGRectMake(9, 0, cell.contentView.bounds.size.width - 18, 45);
	button.enabled = [self canClear];
	button.alpha = [self canClear] ? 1.0f : 0.7f;
	return cell;
}

- (void)clearEverythingPressed {
	[self confirmClearKinds:@[] title:@"Clear everything"];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == TGStorageSectionPolicy){
		if (self.working)
			return;
		[self presentPolicySheetForRow:indexPath.row];
		return;
	}

	if (indexPath.section == TGStorageSectionChats){
		if (!self.detailLoaded || indexPath.row >= (NSInteger)self.chatRows.count)
			return;
		[self openChatDetail:[self.chatRows objectAtIndex:indexPath.row]];
		return;
	}

	if (![self canClear])
		return;

	if (indexPath.section == TGStorageSectionTypes){
		if (!self.detailLoaded || !self.typeRows.count)
			return;
		NSDictionary *row = [self.typeRows objectAtIndex:indexPath.row];
		[self confirmClearKinds:@[[row objectForKey:@"kind"]]
						  title:[NSString stringWithFormat:@"Clear %@",
								  [[row objectForKey:@"title"] lowercaseString]]];
		return;
	}

	if (indexPath.section != TGStorageSectionClear)
		return;

	if (indexPath.row == 3){
		self.pendingAction = TGStorageActionOptimise;
		self.pendingKinds = nil;
		[self presentConfirmationWithTitle:@"Optimise"];
		return;
	}

	NSArray *kinds = nil;
	switch (indexPath.row){
		case 0: kinds = @[@"fileTypePhoto", @"fileTypeProfilePhoto", @"fileTypeThumbnail"]; break;
		case 1: kinds = @[@"fileTypeVideo", @"fileTypeVideoNote", @"fileTypeAnimation"]; break;
		case 2: kinds = @[@"fileTypeDocument", @"fileTypeAudio", @"fileTypeVoiceNote"]; break;
		default: kinds = @[]; break;
	}
	[self confirmClearKinds:kinds title:[[tableView cellForRowAtIndexPath:indexPath] textLabel].text];
}

- (void)confirmClearKinds:(NSArray *)kinds title:(NSString *)title {
	if (![self canClear])
		return;
	self.pendingAction = TGStorageActionKinds;
	self.pendingKinds = kinds ? kinds : @[];
	[self presentConfirmationWithTitle:title];
}

- (void)openChatDetail:(NSDictionary *)row {
	TGStorageChatViewController *controller = [[TGStorageChatViewController alloc] init];
	controller.chatId = (int64_t)[[row objectForKey:@"chatId"] longLongValue];
	controller.chatTitle = [row objectForKey:@"title"];
	controller.bytes = [[row objectForKey:@"size"] longLongValue];
	__weak typeof(self) weakSelf = self;
	controller.didChange = ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf refresh];
		[strongSelf refreshDetail];
	};
	[self.navigationController pushViewController:controller animated:YES];
}

- (void)presentPolicySheetForRow:(NSInteger)row {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:
					row == 0 ? @"Keep media for" : @"Maximum cache size"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:nil];
	sheet.tag = row == 0 ? TGStorageSheetTTL : TGStorageSheetSize;
	if (row == 0){
		for (int i = 0; i < 4; i++)
			[sheet addButtonWithTitle:TGStorageTTLName(TGStorageTTLValues[i])];
	} else {
		for (int i = 0; i < 4; i++)
			[sheet addButtonWithTitle:TGStorageSizeName(TGStorageSizeValues[i])];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	if (self.tabBarController.tabBar)
		[sheet showFromTabBar:self.tabBarController.tabBar];
	else
		[sheet showInView:self.view];
}

- (void)applyPolicy {
	if (![self beginWork])
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] applyPersistedCachePolicyWithCompletion:^(long long freed){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.working)
			return;
		[strongSelf finishWorkWithFreed:freed];
	}];
}

- (void)presentConfirmationWithTitle:(NSString *)title {
	self.pendingTitle = title.length ? title : @"Clear";

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:nil];
	sheet.tag = TGStorageSheetConfirm;
	[sheet addButtonWithTitle:self.pendingTitle];
	sheet.destructiveButtonIndex = 0;
	[sheet addButtonWithTitle:@"Cancel"];
	sheet.cancelButtonIndex = 1;
	if (self.tabBarController.tabBar)
		[sheet showFromTabBar:self.tabBarController.tabBar];
	else
		[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet
		clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (actionSheet.tag == TGStorageSheetTTL || actionSheet.tag == TGStorageSheetSize){
		if (buttonIndex < 0 || buttonIndex > 3)
			return;
		NSInteger ttl = [self policyTTLSeconds];
		long long maxBytes = [self policyMaxBytes];
		if (actionSheet.tag == TGStorageSheetTTL)
			ttl = TGStorageTTLValues[buttonIndex];
		else
			maxBytes = TGStorageSizeValues[buttonIndex];
		[[TGClient shared] setCachePolicyMaxBytes:maxBytes
									   ttlSeconds:ttl
								  excludedChatIds:[self policyExcludedChatIds]];
		[self.tableView reloadData];
		if (ttl > 0 || maxBytes > 0)
			[self applyPolicy];
		return;
	}

	if (buttonIndex != actionSheet.destructiveButtonIndex)
		return;
	TGStorageAction action = self.pendingAction;
	NSArray *kinds = self.pendingKinds;
	int64_t chatId = self.pendingChatId;
	self.pendingKinds = nil;
	self.pendingTitle = nil;
	self.pendingChatId = 0;

	if (action == TGStorageActionChat)
		[self clearChat:chatId];
	else if (action == TGStorageActionOptimise)
		[self optimise];
	else
		[self clearKinds:kinds];
}

- (BOOL)beginWork {
	if (self.working)
		return NO;
	self.working = YES;
	[self.tableView reloadData];
	[self performSelector:@selector(clearTimedOut) withObject:nil afterDelay:60.0];
	return YES;
}

- (void)finishWorkWithFreed:(long long)freed {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(clearTimedOut)
											   object:nil];
	self.working = NO;
	[self refresh];
	[self refreshDetail];
	[self.tableView reloadData];

	NSString *message = freed > 0
			? [NSString stringWithFormat:@"Freed %@.", TGHumanSize(freed)]
			: @"There was nothing to clear.";
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Storage"
			message:message
		   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

- (void)clearKinds:(NSArray *)kinds {
	if (!kinds || ![self beginWork])
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] clearCacheOfTypes:kinds completion:^(long long freed){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.working)
			return;
		[strongSelf finishWorkWithFreed:freed];
	}];
}

- (void)clearChat:(int64_t)chatId {
	if (![self beginWork])
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] clearCacheForChat:chatId completion:^(long long freed){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.working)
			return;
		[strongSelf finishWorkWithFreed:freed];
	}];
}

- (void)optimise {
	if (![self beginWork])
		return;

	NSInteger ttl = [self policyTTLSeconds];
	long long maxBytes = [self policyMaxBytes];
	if (ttl <= 0 && maxBytes <= 0)
		ttl = 30 * 24 * 60 * 60;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] optimizeStorageToSize:maxBytes
								  ttlSeconds:ttl
						immunityDelaySeconds:60 * 60
								   fileTypes:nil
							 excludedChatIds:[self policyExcludedChatIds]
								  completion:^(long long freed){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.working)
			return;
		[strongSelf finishWorkWithFreed:freed];
	}];
}

- (void)clearTimedOut {
	if (!self.working)
		return;
	self.working = NO;
	[self.tableView reloadData];
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Storage"
			message:@"Clearing the cache is taking too long. Please try again."
		   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

@end

@interface TGStorageChatViewController ()
@property (nonatomic, assign) BOOL working;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation TGStorageChatViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.chatTitle.length ? self.chatTitle : @"Chat";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] bubbleBorderColour];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storageUsageForChat:self.chatId
								completion:^(long long bytes, NSInteger files){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		strongSelf.bytes = bytes < 0 ? 0 : bytes;
		strongSelf.files = files < 0 ? 0 : files;
		[strongSelf.tableView reloadData];
	}];
}

- (BOOL)canClear {
	return !self.working && self.bytes > 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 2 : 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 44;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return section == 0 ? 46 : 12;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (section != 0)
		return nil;
	BOOL dark = [[TGTheme shared] isDark];
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, 46)];
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [[UILabel alloc] init];
	label.text = @"Cached in this chat";
	label.font = [UIFont boldSystemFontOfSize:17];
	label.backgroundColor = [UIColor clearColor];
	label.textColor = dark ? [[TGTheme shared] sectionHeaderColour]
						   : TGStorageRGB(0x697487);
	if (!dark){
		label.shadowColor = TGStorageRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 21, 16);
	[container addSubview:label];
	return container;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];
	BOOL dark = [[TGTheme shared] isDark];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.textColor = dark ? [[TGTheme shared] primaryTextColour]
									: [UIColor blackColor];
	cell.textLabel.highlightedTextColor = [UIColor whiteColor];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.textColor = dark ? [[TGTheme shared] cellDetailColour]
										  : TGStorageRGB(0x356596);
	cell.detailTextLabel.highlightedTextColor = [UIColor whiteColor];
	cell.detailTextLabel.text = @"";

	if (indexPath.section == 0){
		if (indexPath.row == 0){
			cell.textLabel.text = @"Size on disk";
			cell.detailTextLabel.text = self.bytes > 0 ? TGHumanSize(self.bytes) : @"Empty";
		} else {
			cell.textLabel.text = @"Files";
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)self.files];
		}
		if (!self.loaded){
			cell.detailTextLabel.text = @"";
			UIActivityIndicatorView *view = [[UIActivityIndicatorView alloc]
					initWithActivityIndicatorStyle:dark ? UIActivityIndicatorViewStyleWhite
													   : UIActivityIndicatorViewStyleGray];
			[view startAnimating];
			cell.accessoryView = view;
		}
		return cell;
	}

	cell.textLabel.text = @"Clear cache of this chat";
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	if ([self canClear]){
		cell.textLabel.textColor = TGStorageRGB(0xc4362f);
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	} else {
		cell.textLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
										: TGStorageRGB(0x888888);
		if (self.working){
			UIActivityIndicatorView *view = [[UIActivityIndicatorView alloc]
					initWithActivityIndicatorStyle:dark ? UIActivityIndicatorViewStyleWhite
													   : UIActivityIndicatorViewStyleGray];
			[view startAnimating];
			cell.accessoryView = view;
		}
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1 || ![self canClear])
		return;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"Clear cache"];
	sheet.destructiveButtonIndex = 0;
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet
		clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex != actionSheet.destructiveButtonIndex || ![self canClear])
		return;
	self.working = YES;
	[self.tableView reloadData];
	[self performSelector:@selector(clearTimedOut) withObject:nil afterDelay:60.0];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] clearCacheForChat:self.chatId completion:^(long long freed){
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.working)
			return;
		[NSObject cancelPreviousPerformRequestsWithTarget:strongSelf
												 selector:@selector(clearTimedOut)
												   object:nil];
		strongSelf.working = NO;
		strongSelf.bytes = 0;
		strongSelf.files = 0;
		[strongSelf.tableView reloadData];
		[strongSelf reload];
		if (strongSelf.didChange)
			strongSelf.didChange();

		NSString *message = freed > 0
				? [NSString stringWithFormat:@"Freed %@.", TGHumanSize(freed)]
				: @"There was nothing to clear.";
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Storage"
				message:message
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}];
}

- (void)clearTimedOut {
	if (!self.working)
		return;
	self.working = NO;
	[self.tableView reloadData];
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Storage"
			message:@"Clearing the cache is taking too long. Please try again."
		   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

@end

// vim:ft=objc

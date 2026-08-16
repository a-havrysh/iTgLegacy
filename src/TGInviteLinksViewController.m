#import "TGInviteLinksViewController.h"
#import "TGClient.h"
#import "TGClient+ChatManagement.h"
#import "TGClient+Messages.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGActionSheet.h"
#import "TGAlertView.h"
#import "TGForwardPicker.h"

#define TGInviteRGB(rgb) [UIColor colorWithRed:(((rgb) >> 16) & 0xff) / 255.0f \
										 green:(((rgb) >> 8) & 0xff) / 255.0f \
										  blue:((rgb) & 0xff) / 255.0f alpha:1.0f]

static const NSInteger TGInviteHairlineTag = 7811;

static const NSInteger TGInviteSectionPrimary = 0;
static const NSInteger TGInviteSectionRequests = 1;
static const NSInteger TGInviteSectionLinks = 2;
static const NSInteger TGInviteSectionRevoked = 3;

static const NSInteger TGInviteRequestPageLimit = 50;

static const NSInteger TGInviteRenameAlertTag = 7812;

static CGFloat TGInviteRetinaPixel(void) {
	return [UIScreen mainScreen].scale > 1.0f ? 0.5f : 0.0f;
}

static NSDateFormatter *TGInviteShortDateFormatter(void) {
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterShortStyle;
		formatter.timeStyle = NSDateFormatterNoStyle;
	}
	return formatter;
}

@interface TGInviteLinksViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) NSString *primaryLink;
@property (nonatomic, strong) NSArray *links;
@property (nonatomic, strong) NSArray *revokedLinks;
@property (nonatomic, strong) NSArray *requests;
@property (nonatomic, assign) NSInteger requestTotal;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, strong) NSDictionary *pendingLink;
@property (nonatomic, strong) NSDictionary *pendingRequest;
@property (nonatomic, strong) NSDictionary *editingLink;
@property (nonatomic, assign) NSInteger requestLimit;
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, assign) BOOL loadingMoreRequests;
@property (nonatomic, assign) NSInteger outstanding;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) BOOL busy;
@end

@implementation TGInviteLinksViewController

- (instancetype)init {
	return [self initWithStyle:UITableViewStyleGrouped];
}

- (instancetype)initWithStyle:(__unused UITableViewStyle)style {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self)
		_requestLimit = TGInviteRequestPageLimit;
	return self;
}

- (instancetype)initWithChatId:(int64_t)chatId {
	self = [self init];
	if (self)
		_chatId = chatId;
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Invite Links";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

	[self updateNewButton];
	[self rebuildSections];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.currentActionSheet){
		[self.currentActionSheet dismissWithClickedButtonIndex:
				self.currentActionSheet.cancelButtonIndex animated:NO];
		self.currentActionSheet = nil;
	}
}

#pragma mark - loading

- (void)updateNewButton {
	if (!self.canManage){
		self.navigationItem.rightBarButtonItem = nil;
		return;
	}
	if (self.navigationItem.rightBarButtonItem)
		return;
	UIButton *button = [TGIcons headerButtonWithTitle:@"New" bold:NO
											   target:self action:@selector(createLink)];
	if (button)
		self.navigationItem.rightBarButtonItem =
				[[UIBarButtonItem alloc] initWithCustomView:button];
}

- (void)reload {
	if (self.outstanding > 0)
		return;
	self.outstanding = 5;
	self.failed = NO;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] canManageInviteLinksInChat:self.chatId completion:^(BOOL canManage){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.canManage = canManage;
		[strongSelf updateNewButton];
		[strongSelf stepFinishedWithFailure:NO];
	}];
	[[TGClient shared] primaryInviteLinkForChat:self.chatId completion:^(NSString *link){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.primaryLink = [link isKindOfClass:[NSString class]] ? link : @"";
		[strongSelf stepFinishedWithFailure:NO];
	}];
	[[TGClient shared] inviteLinksForChat:self.chatId revoked:NO completion:^(NSArray *links){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.links = [strongSelf secondaryLinksFrom:links];
		[strongSelf stepFinishedWithFailure:links == nil];
	}];
	[[TGClient shared] inviteLinksForChat:self.chatId revoked:YES completion:^(NSArray *links){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.revokedLinks = links ?: [NSArray array];
		[strongSelf stepFinishedWithFailure:NO];
	}];
	if (self.requestLimit < TGInviteRequestPageLimit)
		self.requestLimit = TGInviteRequestPageLimit;
	[[TGClient shared] joinRequestsForChat:self.chatId inviteLink:nil query:nil
									 limit:self.requestLimit
								completion:^(NSArray *requests, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.requests = requests ?: [NSArray array];
		strongSelf.requestTotal = total;
		[strongSelf stepFinishedWithFailure:NO];
	}];
}

- (BOOL)canLoadMoreRequests {
	return self.loaded && self.requests.count
			&& self.requestTotal > (NSInteger)self.requests.count;
}

- (void)loadMoreRequests {
	if (self.loadingMoreRequests || self.outstanding > 0)
		return;
	self.loadingMoreRequests = YES;
	self.requestLimit += TGInviteRequestPageLimit;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] joinRequestsForChat:self.chatId inviteLink:nil query:nil
									 limit:self.requestLimit
								completion:^(NSArray *requests, NSInteger total){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.loadingMoreRequests = NO;
		if (!requests){
			[strongSelf failedWithMessage:@"More requests could not be loaded."];
			[strongSelf.tableView reloadData];
			return;
		}
		if (requests.count <= strongSelf.requests.count
				&& total > (NSInteger)requests.count)
			strongSelf.requestLimit = (NSInteger)requests.count + TGInviteRequestPageLimit;
		strongSelf.requests = requests;
		strongSelf.requestTotal = total;
		[strongSelf rebuildSections];
		[strongSelf.tableView reloadData];
	}];
}

- (void)stepFinishedWithFailure:(BOOL)failure {
	if (failure)
		self.failed = YES;
	if (self.outstanding > 0)
		self.outstanding -= 1;
	if (self.outstanding > 0)
		return;
	self.loaded = YES;
	[self rebuildSections];
	[self.tableView reloadData];
}

- (NSArray *)secondaryLinksFrom:(NSArray *)links {
	NSMutableArray *result = [NSMutableArray array];
	for (NSDictionary *link in links){
		if (![link isKindOfClass:[NSDictionary class]])
			continue;
		if ([link[@"isPrimary"] boolValue])
			continue;
		[result addObject:link];
	}
	return result;
}

- (void)rebuildSections {
	NSMutableArray *sections = [NSMutableArray array];
	[sections addObject:[NSNumber numberWithInteger:TGInviteSectionPrimary]];
	if (self.requests.count)
		[sections addObject:[NSNumber numberWithInteger:TGInviteSectionRequests]];
	if (self.canManage || self.links.count)
		[sections addObject:[NSNumber numberWithInteger:TGInviteSectionLinks]];
	if (self.revokedLinks.count)
		[sections addObject:[NSNumber numberWithInteger:TGInviteSectionRevoked]];
	self.sections = sections;
}

- (NSInteger)kindOfSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return -1;
	return [self.sections[section] integerValue];
}

#pragma mark - formatting

- (NSString *)shortLink:(NSString *)link {
	if (![link isKindOfClass:[NSString class]] || !link.length)
		return @"";
	NSString *text = link;
	NSRange scheme = [text rangeOfString:@"://"];
	if (scheme.location != NSNotFound)
		text = [text substringFromIndex:scheme.location + scheme.length];
	return text;
}

- (NSString *)titleForLink:(NSDictionary *)link {
	NSString *name = link[@"name"];
	if ([name isKindOfClass:[NSString class]] && name.length)
		return name;
	return [self shortLink:link[@"link"]];
}

- (NSString *)dateText:(long long)stamp {
	if (stamp <= 0)
		return @"";
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)stamp];
	return [TGInviteShortDateFormatter() stringFromDate:date];
}

- (NSString *)subtitleForLink:(NSDictionary *)link revoked:(BOOL)revoked {
	NSMutableArray *parts = [NSMutableArray array];

	NSInteger members = [link[@"memberCount"] integerValue];
	NSInteger limit = [link[@"memberLimit"] integerValue];
	if (limit > 0)
		[parts addObject:[NSString stringWithFormat:@"%d of %d joined",
				(int)members, (int)limit]];
	else if (members == 1)
		[parts addObject:@"1 joined"];
	else
		[parts addObject:[NSString stringWithFormat:@"%d joined", (int)members]];

	NSInteger pending = [link[@"pendingRequests"] integerValue];
	if (pending > 0)
		[parts addObject:[NSString stringWithFormat:@"%d requesting", (int)pending]];

	if (revoked){
		[parts addObject:@"revoked"];
	} else {
		long long expires = [link[@"expirationDate"] longLongValue];
		if (expires > 0){
			NSTimeInterval left = (NSTimeInterval)expires - [[NSDate date] timeIntervalSince1970];
			if (left <= 0)
				[parts addObject:@"expired"];
			else if (left < 60 * 60)
				[parts addObject:[NSString stringWithFormat:@"expires in %d min",
						(int)(left / 60) + 1]];
			else if (left < 60 * 60 * 24)
				[parts addObject:[NSString stringWithFormat:@"expires in %d h",
						(int)(left / 3600) + 1]];
			else
				[parts addObject:[NSString stringWithFormat:@"expires %@",
						[self dateText:expires]]];
		}
	}
	return [parts componentsJoinedByString:@" - "];
}

- (NSString *)subtitleForRequest:(NSDictionary *)request {
	NSString *bio = request[@"bio"];
	if ([bio isKindOfClass:[NSString class]] && bio.length)
		return bio;
	NSString *date = [self dateText:[request[@"date"] longLongValue]];
	if (date.length)
		return [NSString stringWithFormat:@"requested %@", date];
	return @"wants to join";
}

#pragma mark - captions

- (UIColor *)captionColour {
	return [[TGTheme shared] isDark] ? [[TGTheme shared] sectionHeaderColour]
									 : TGInviteRGB(0x697487);
}

- (UILabel *)captionLabel {
	UILabel *label = [[UILabel alloc] init];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont systemFontOfSize:14];
	label.textColor = [self captionColour];
	if (![[TGTheme shared] isFlat] && ![[TGTheme shared] isDark]){
		label.shadowColor = TGInviteRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	return label;
}

- (CGFloat)captionHeightFor:(NSString *)text width:(CGFloat)width {
	CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:14]
				   constrainedToSize:CGSizeMake(width, 1000)
					   lineBreakMode:NSLineBreakByWordWrapping];
	return size.height;
}

- (NSString *)headerTitleForSection:(NSInteger)section {
	NSInteger kind = [self kindOfSection:section];
	if (kind == TGInviteSectionPrimary)
		return @"Invite link";
	if (kind == TGInviteSectionRequests)
		return self.requestTotal > (NSInteger)self.requests.count
				? [NSString stringWithFormat:@"Join requests (%d)", (int)self.requestTotal]
				: @"Join requests";
	if (kind == TGInviteSectionLinks)
		return @"Additional links";
	if (kind == TGInviteSectionRevoked)
		return @"Revoked links";
	return nil;
}

- (NSString *)footerTitleForSection:(NSInteger)section {
	NSInteger kind = [self kindOfSection:section];
	if (kind == TGInviteSectionPrimary){
		if (!self.loaded)
			return @"Loading...";
		if (self.failed)
			return @"The links could not be loaded. Leave this screen and open it again to retry.";
		if (!self.primaryLink.length)
			return @"This chat has no invite link. Only an administrator with the right to invite users can make one.";
		if (!self.canManage)
			return @"Anyone with this link can join. Tap it to copy or share it.";
		return @"Anyone with this link can join. Tap it to copy, share or revoke it.";
	}
	if (kind == TGInviteSectionRequests)
		return self.canManage
				? @"Tap a person to approve or decline the request."
				: @"Only an administrator who may invite users can answer these requests.";
	if (kind == TGInviteSectionLinks){
		if (!self.loaded)
			return nil;
		if (!self.canManage)
			return self.links.count ? @"Tap a link to copy or share it." : nil;
		if (!self.links.count)
			return @"You have no additional links yet. A new link can carry its own expiry and member limit.";
		return @"Tap a link to copy, edit or revoke it, or swipe it away to revoke.";
	}
	if (kind == TGInviteSectionRevoked)
		return @"A revoked link no longer works. Deleting it removes it from this list.";
	return nil;
}

#pragma mark - table structure

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSInteger kind = [self kindOfSection:section];
	if (kind == TGInviteSectionPrimary)
		return self.primaryLink.length ? 1 : 0;
	if (kind == TGInviteSectionRequests)
		return (NSInteger)self.requests.count + ([self canLoadMoreRequests] ? 1 : 0)
				+ ((self.canManage && self.requests.count > 1) ? 1 : 0);
	if (kind == TGInviteSectionLinks)
		return (NSInteger)self.links.count + (self.canManage ? 1 : 0);
	if (kind == TGInviteSectionRevoked)
		return (NSInteger)self.revokedLinks.count + (self.canManage ? 1 : 0);
	return 0;
}

- (NSInteger)moreRequestsRow {
	return [self canLoadMoreRequests] ? (NSInteger)self.requests.count : -1;
}

- (NSInteger)approveAllRow {
	if (!self.canManage || self.requests.count <= 1)
		return -1;
	return (NSInteger)self.requests.count + ([self canLoadMoreRequests] ? 1 : 0);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 44;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return 12;
	return [self captionHeightFor:title width:tableView.bounds.size.width - 42] + 18;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	if (!title)
		return nil;

	CGFloat width = tableView.bounds.size.width - 42;
	CGFloat height = [self captionHeightFor:title width:width];

	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, height + 18)];
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [self captionLabel];
	label.numberOfLines = 0;
	label.text = title;
	label.frame = CGRectMake(21, 6 + TGInviteRetinaPixel(), width, height);
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return 1;
	return [self captionHeightFor:title width:tableView.bounds.size.width - 42] + 14;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	NSString *title = [self footerTitleForSection:section];
	if (!title)
		return nil;

	CGFloat width = tableView.bounds.size.width - 42;
	CGFloat height = [self captionHeightFor:title width:width];

	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, height + 14)];
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [self captionLabel];
	label.numberOfLines = 0;
	label.text = title;
	label.frame = CGRectMake(21, 7 + TGInviteRetinaPixel(), width, height);
	[container addSubview:label];
	return container;
}

#pragma mark - model access

- (NSDictionary *)linkAtIndexPath:(NSIndexPath *)indexPath {
	NSInteger kind = [self kindOfSection:indexPath.section];
	if (kind == TGInviteSectionLinks && indexPath.row < (NSInteger)self.links.count)
		return self.links[indexPath.row];
	if (kind == TGInviteSectionRevoked && indexPath.row < (NSInteger)self.revokedLinks.count)
		return self.revokedLinks[indexPath.row];
	return nil;
}

- (NSDictionary *)requestAtIndexPath:(NSIndexPath *)indexPath {
	if ([self kindOfSection:indexPath.section] != TGInviteSectionRequests)
		return nil;
	if (indexPath.row >= (NSInteger)self.requests.count)
		return nil;
	return self.requests[indexPath.row];
}

- (BOOL)isActionRowAtIndexPath:(NSIndexPath *)indexPath {
	NSInteger kind = [self kindOfSection:indexPath.section];
	if (kind == TGInviteSectionLinks)
		return self.canManage && indexPath.row == (NSInteger)self.links.count;
	if (kind == TGInviteSectionRevoked)
		return self.canManage && indexPath.row == (NSInteger)self.revokedLinks.count;
	if (kind == TGInviteSectionRequests)
		return indexPath.row >= (NSInteger)self.requests.count;
	return NO;
}

#pragma mark - cells

- (UITableViewCell *)actionCellForTable:(UITableView *)tableView
								  title:(NSString *)title
							destructive:(BOOL)destructive {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"action"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = title;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.textColor = destructive ? TGInviteRGB(0xc4362f) : TGInviteRGB(0x0779d0);
	cell.textLabel.highlightedTextColor = [UIColor whiteColor];
	cell.detailTextLabel.text = @"";
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	UIView *hairline = [cell.contentView viewWithTag:TGInviteHairlineTag];
	hairline.hidden = YES;
	return cell;
}

- (UITableViewCell *)actionRowCellForTable:(UITableView *)tableView
									  kind:(NSInteger)kind
								 indexPath:(NSIndexPath *)indexPath {
	if (kind == TGInviteSectionLinks)
		return [self actionCellForTable:tableView title:@"Create a New Link"
							destructive:NO];
	if (kind == TGInviteSectionRevoked)
		return [self actionCellForTable:tableView title:@"Delete All Revoked Links"
							destructive:YES];
	if (indexPath.row == [self moreRequestsRow])
		return [self actionCellForTable:tableView
								  title:self.loadingMoreRequests
										  ? @"Loading..."
										  : [NSString stringWithFormat:@"Show More (%d left)",
												  (int)(self.requestTotal
														  - (NSInteger)self.requests.count)]
							destructive:NO];
	return [self actionCellForTable:tableView title:@"Approve All Requests"
						destructive:NO];
}

- (void)configurePrimaryCell:(UITableViewCell *)cell dark:(BOOL)dark {
	cell.textLabel.text = [self shortLink:self.primaryLink];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	cell.textLabel.textColor = dark ? [[TGTheme shared] primaryTextColour]
									: TGInviteRGB(0x0779d0);
	cell.detailTextLabel.text = @"Tap to copy, share or revoke";
}

- (void)configureRequestCell:(UITableViewCell *)cell
				 atIndexPath:(NSIndexPath *)indexPath
						dark:(BOOL)dark {
	NSDictionary *request = [self requestAtIndexPath:indexPath];
	NSString *name = request[@"name"];
	if (![name isKindOfClass:[NSString class]] || !name.length)
		name = @"Unknown user";
	cell.textLabel.text = name;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = dark ? [[TGTheme shared] primaryTextColour]
									: TGInviteRGB(0x516691);
	cell.detailTextLabel.text = [self subtitleForRequest:request];
	if (!self.canManage)
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.imageView.image = [TGIcons avatarWithInitials:[self initialsForName:name]
												  size:30
											  colourId:[request[@"userId"] longLongValue]];
}

- (void)configureLinkCell:(UITableViewCell *)cell
			  atIndexPath:(NSIndexPath *)indexPath
				  revoked:(BOOL)revoked
					 dark:(BOOL)dark {
	NSDictionary *link = [self linkAtIndexPath:indexPath];
	cell.textLabel.text = [self titleForLink:link];
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = dark ? [[TGTheme shared] primaryTextColour]
									: TGInviteRGB(0x516691);
	cell.detailTextLabel.text = [self subtitleForLink:link revoked:revoked];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSInteger kind = [self kindOfSection:indexPath.section];

	if ([self isActionRowAtIndexPath:indexPath])
		return [self actionRowCellForTable:tableView kind:kind indexPath:indexPath];

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
		UIView *hairline = [[UIView alloc] initWithFrame:CGRectZero];
		hairline.tag = TGInviteHairlineTag;
		hairline.autoresizingMask = UIViewAutoresizingFlexibleWidth
				| UIViewAutoresizingFlexibleTopMargin;
		[cell.contentView addSubview:hairline];
	}

	BOOL dark = [[TGTheme shared] isDark];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.highlightedTextColor = [UIColor whiteColor];
	cell.detailTextLabel.highlightedTextColor = [UIColor whiteColor];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13 + TGInviteRetinaPixel()];
	cell.detailTextLabel.textColor = dark ? [[TGTheme shared] secondaryTextColour]
										  : TGInviteRGB(0x888888);
	cell.imageView.image = nil;

	if (kind == TGInviteSectionPrimary)
		[self configurePrimaryCell:cell dark:dark];
	else if (kind == TGInviteSectionRequests)
		[self configureRequestCell:cell atIndexPath:indexPath dark:dark];
	else
		[self configureLinkCell:cell atIndexPath:indexPath
						revoked:kind == TGInviteSectionRevoked dark:dark];

	UIView *hairline = [cell.contentView viewWithTag:TGInviteHairlineTag];
	NSInteger rows = [self tableView:tableView numberOfRowsInSection:indexPath.section];
	hairline.backgroundColor = [[TGTheme shared] separatorColour];
	hairline.hidden = indexPath.row + 1 >= rows;
	return cell;
}

- (NSString *)initialsForName:(NSString *)name {
	NSArray *parts = [name componentsSeparatedByString:@" "];
	NSMutableString *initials = [NSMutableString string];
	for (NSString *part in parts){
		if (!part.length)
			continue;
		[initials appendString:[[part substringToIndex:1] uppercaseString]];
		if (initials.length >= 2)
			break;
	}
	return initials.length ? initials : @"?";
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	UIView *hairline = [cell.contentView viewWithTag:TGInviteHairlineTag];
	if (!hairline)
		return;
	CGRect bounds = cell.contentView.bounds;
	CGFloat thickness = 1.0f / [UIScreen mainScreen].scale;
	hairline.frame = CGRectMake(10, bounds.size.height - thickness,
			bounds.size.width - 10, thickness);
}

#pragma mark - swipe to revoke

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isActionRowAtIndexPath:indexPath] || !self.canManage)
		return NO;
	NSInteger kind = [self kindOfSection:indexPath.section];
	return kind == TGInviteSectionLinks || kind == TGInviteSectionRevoked;
}

- (NSString *)tableView:(UITableView *)tableView
		titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	return [self kindOfSection:indexPath.section] == TGInviteSectionRevoked
			? @"Delete" : @"Revoke";
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;
	NSDictionary *link = [self linkAtIndexPath:indexPath];
	if (!link)
		return;
	if ([self kindOfSection:indexPath.section] == TGInviteSectionRevoked)
		[self deleteRevokedLink:link];
	else
		[self revokeLink:link];
}

#pragma mark - selection

- (UIView *)sheetHostView {
	if (self.navigationController.view)
		return self.navigationController.view;
	return self.view;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSInteger kind = [self kindOfSection:indexPath.section];

	if ([self isActionRowAtIndexPath:indexPath]){
		if (kind == TGInviteSectionLinks)
			[self createLink];
		else if (kind == TGInviteSectionRevoked)
			[self confirmDeleteAllRevoked];
		else if (indexPath.row == [self moreRequestsRow])
			[self loadMoreRequests];
		else
			[self confirmApproveAll];
		return;
	}

	if (kind == TGInviteSectionPrimary){
		[self showSheetForPrimaryLink];
		return;
	}
	if (kind == TGInviteSectionRequests){
		[self showSheetForRequest:[self requestAtIndexPath:indexPath]];
		return;
	}
	[self showSheetForLink:[self linkAtIndexPath:indexPath]
				   revoked:kind == TGInviteSectionRevoked];
}

#pragma mark - link actions

- (void)copyLink:(NSString *)link {
	if (!link.length)
		return;
	[[UIPasteboard generalPasteboard] setString:link];
}

- (void)shareLink:(NSString *)link {
	if (!link.length)
		return;
	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	__weak typeof(self) weakSelf = self;
	NSString *text = link;
	picker.onPicked = ^(int64_t chatId){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (chatId != 0)
			[[TGClient shared] sendText:text toChat:chatId thread:0 replyTo:0
								options:nil completion:nil];
		[strongSelf dismissViewControllerAnimated:YES completion:nil];
	};
	UINavigationController *navigation =
			[[UINavigationController alloc] initWithRootViewController:picker];
	[self presentViewController:navigation animated:YES completion:nil];
}

- (void)showSheetForPrimaryLink {
	NSString *link = self.primaryLink;
	if (!link.length)
		return;

	NSMutableArray *actions = [NSMutableArray array];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Copy Link" action:@"copy"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Share Link" action:@"share"]];
	if (self.canManage)
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Revoke Link"
															  action:@"revoke"
																type:TGActionSheetActionTypeDestructive]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
															type:TGActionSheetActionTypeCancel]];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:[self shortLink:link]
			actions:actions
			actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				if ([action isEqualToString:@"copy"])
					[strongSelf copyLink:link];
				else if ([action isEqualToString:@"share"])
					[strongSelf shareLink:link];
				else if ([action isEqualToString:@"revoke"])
					[strongSelf replacePrimaryLink];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

- (void)showSheetForLink:(NSDictionary *)link revoked:(BOOL)revoked {
	if (!link)
		return;
	NSString *url = link[@"link"];
	if (![url isKindOfClass:[NSString class]])
		url = @"";
	self.pendingLink = link;

	NSMutableArray *actions = [NSMutableArray array];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Copy Link" action:@"copy"]];
	if (!revoked)
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Share Link"
															  action:@"share"]];
	if (!revoked && self.canManage)
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Edit Link"
															  action:@"edit"]];
	if (self.canManage)
		[actions addObject:[[TGActionSheetAction alloc]
				initWithTitle:revoked ? @"Delete Link" : @"Revoke Link"
					   action:revoked ? @"delete" : @"revoke"
						 type:TGActionSheetActionTypeDestructive]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
															type:TGActionSheetActionTypeCancel]];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:[self shortLink:url]
			actions:actions
			actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				NSDictionary *pending = strongSelf.pendingLink;
				strongSelf.pendingLink = nil;
				if ([action isEqualToString:@"copy"])
					[strongSelf copyLink:url];
				else if ([action isEqualToString:@"share"])
					[strongSelf shareLink:url];
				else if ([action isEqualToString:@"edit"])
					[strongSelf showEditSheetForLink:pending];
				else if ([action isEqualToString:@"revoke"])
					[strongSelf revokeLink:pending];
				else if ([action isEqualToString:@"delete"])
					[strongSelf deleteRevokedLink:pending];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

- (void)failedWithMessage:(NSString *)message {
	[[[TGAlertView alloc] initWithTitle:nil message:message cancelButtonTitle:@"OK"
					   okButtonTitle:nil completionBlock:nil] show];
}

- (void)replacePrimaryLink {
	if (self.busy)
		return;
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] replacePrimaryInviteLinkForChat:self.chatId
										   completion:^(NSDictionary *link){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.busy = NO;
		if (!link){
			[strongSelf failedWithMessage:@"The link could not be revoked."];
			return;
		}
		[strongSelf reload];
	}];
}

- (void)revokeLink:(NSDictionary *)link {
	NSString *url = link[@"link"];
	if (![url isKindOfClass:[NSString class]] || !url.length)
		return;
	if (self.busy)
		return;
	self.busy = YES;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] revokeInviteLink:url inChat:self.chatId completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.busy = NO;
		if (!ok){
			[strongSelf failedWithMessage:@"The link could not be revoked."];
			return;
		}
		[strongSelf reload];
	}];
}

- (void)deleteRevokedLink:(NSDictionary *)link {
	NSString *url = link[@"link"];
	if (![url isKindOfClass:[NSString class]] || !url.length)
		return;
	if (self.busy)
		return;
	self.busy = YES;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] deleteRevokedInviteLink:url inChat:self.chatId completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.busy = NO;
		if (!ok){
			[strongSelf failedWithMessage:@"The link could not be deleted."];
			return;
		}
		[strongSelf reload];
	}];
}

- (void)confirmDeleteAllRevoked {
	if (!self.revokedLinks.count)
		return;

	NSArray *actions = [NSArray arrayWithObjects:
			[[TGActionSheetAction alloc] initWithTitle:@"Delete All Revoked Links"
												 action:@"deleteAll"
												   type:TGActionSheetActionTypeDestructive],
			[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
												  type:TGActionSheetActionTypeCancel],
			nil];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:nil actions:actions
			actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				if (![action isEqualToString:@"deleteAll"])
					return;
				[[TGClient shared] deleteAllRevokedInviteLinksInChat:strongSelf.chatId
														 completion:^(BOOL ok){
					__strong typeof(weakSelf) innerSelf = weakSelf;
					if (!ok){
						[innerSelf failedWithMessage:
								@"The revoked links could not be deleted."];
						return;
					}
					[innerSelf reload];
				}];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

#pragma mark - creating a link

- (void)createLink {
	if (!self.canManage)
		return;
	NSArray *actions = [NSArray arrayWithObjects:
			[[TGActionSheetAction alloc] initWithTitle:@"Permanent Link" action:@"plain"],
			[[TGActionSheetAction alloc] initWithTitle:@"Expires in 1 Hour" action:@"hour"],
			[[TGActionSheetAction alloc] initWithTitle:@"Expires in 1 Day" action:@"day"],
			[[TGActionSheetAction alloc] initWithTitle:@"Expires in 1 Week" action:@"week"],
			[[TGActionSheetAction alloc] initWithTitle:@"Limit: 10 Users" action:@"limit10"],
			[[TGActionSheetAction alloc] initWithTitle:@"Limit: 100 Users" action:@"limit100"],
			[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
												  type:TGActionSheetActionTypeCancel],
			nil];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:nil actions:actions
			actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				if ([action isEqualToString:@"cancel"])
					return;

				NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
				NSInteger expires = 0;
				NSInteger limit = 0;
				if ([action isEqualToString:@"hour"])
					expires = (NSInteger)now + 60 * 60;
				else if ([action isEqualToString:@"day"])
					expires = (NSInteger)now + 60 * 60 * 24;
				else if ([action isEqualToString:@"week"])
					expires = (NSInteger)now + 60 * 60 * 24 * 7;
				else if ([action isEqualToString:@"limit10"])
					limit = 10;
				else if ([action isEqualToString:@"limit100"])
					limit = 100;

				[strongSelf createLinkExpiring:expires limit:limit];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

- (void)createLinkExpiring:(NSInteger)expirationDate limit:(NSInteger)memberLimit {
	if (self.busy)
		return;
	self.busy = YES;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] createInviteLinkForChat:self.chatId
										  name:@""
								expirationDate:expirationDate
								   memberLimit:memberLimit
							  requiresApproval:NO
									completion:^(NSDictionary *link){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.busy = NO;
		if (!link){
			[strongSelf failedWithMessage:@"The link could not be created."];
			return;
		}
		[strongSelf reload];
	}];
}

#pragma mark - editing a link

- (NSArray *)editSheetActions {
	NSMutableArray *actions = [NSMutableArray array];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Change Name"
														  action:@"name"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Expiry: Never"
														  action:@"never"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Expiry: 1 Hour"
														  action:@"hour"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Expiry: 1 Day"
														  action:@"day"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Expiry: 1 Week"
														  action:@"week"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Limit: No Limit"
														  action:@"nolimit"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Limit: 10 Users"
														  action:@"limit10"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Limit: 100 Users"
														  action:@"limit100"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
															type:TGActionSheetActionTypeCancel]];
	return actions;
}

- (void)applyEditAction:(NSString *)action toLink:(NSDictionary *)editing {
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	NSInteger expires = [editing[@"expirationDate"] integerValue];
	NSInteger limit = [editing[@"memberLimit"] integerValue];
	if ([action isEqualToString:@"never"])
		expires = 0;
	else if ([action isEqualToString:@"hour"])
		expires = (NSInteger)now + 60 * 60;
	else if ([action isEqualToString:@"day"])
		expires = (NSInteger)now + 60 * 60 * 24;
	else if ([action isEqualToString:@"week"])
		expires = (NSInteger)now + 60 * 60 * 24 * 7;
	else if ([action isEqualToString:@"nolimit"])
		limit = 0;
	else if ([action isEqualToString:@"limit10"])
		limit = 10;
	else if ([action isEqualToString:@"limit100"])
		limit = 100;

	[self applyEditToLink:editing
					 name:[self nameOfLink:editing]
		   expirationDate:expires
			  memberLimit:limit];
}

- (void)showEditSheetForLink:(NSDictionary *)link {
	NSString *url = link[@"link"];
	if (![url isKindOfClass:[NSString class]] || !url.length)
		return;
	self.editingLink = link;

	__weak typeof(self) weakSelf = self;
	TGActionSheet *sheet = [[TGActionSheet alloc]
			initWithTitle:[self titleForLink:link]
				  actions:[self editSheetActions]
			  actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				NSDictionary *editing = strongSelf.editingLink;
				if (!editing || [action isEqualToString:@"cancel"]){
					strongSelf.editingLink = nil;
					return;
				}
				if ([action isEqualToString:@"name"]){
					[strongSelf askNameForLink:editing];
					return;
				}
				strongSelf.editingLink = nil;
				[strongSelf applyEditAction:action toLink:editing];
			} target:self];

	self.currentActionSheet = sheet;
	UIView *host = [self sheetHostView];
	dispatch_async(dispatch_get_main_queue(), ^{
		[sheet showInView:host];
	});
}

- (NSString *)nameOfLink:(NSDictionary *)link {
	NSString *name = link[@"name"];
	return [name isKindOfClass:[NSString class]] ? name : @"";
}

- (void)askNameForLink:(NSDictionary *)link {
	self.editingLink = link;
	UIAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Link Name"
													message:@"Name this link."
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Save", nil];
	alert.tag = TGInviteRenameAlertTag;
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)]){
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
		[alert textFieldAtIndex:0].text = [self nameOfLink:link];
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[alert show];
	});
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (alertView.tag != TGInviteRenameAlertTag)
		return;
	NSDictionary *link = self.editingLink;
	self.editingLink = nil;
	if (buttonIndex == alertView.cancelButtonIndex || !link)
		return;
	if (![alertView respondsToSelector:@selector(textFieldAtIndex:)])
		return;

	NSString *name = [[alertView textFieldAtIndex:0].text
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!name)
		name = @"";
	if (name.length > 32)
		name = [name substringToIndex:32];
	[self applyEditToLink:link
					 name:name
		   expirationDate:[link[@"expirationDate"] integerValue]
			  memberLimit:[link[@"memberLimit"] integerValue]];
}

- (void)applyEditToLink:(NSDictionary *)link
				   name:(NSString *)name
		 expirationDate:(NSInteger)expirationDate
			memberLimit:(NSInteger)memberLimit {
	NSString *url = link[@"link"];
	if (![url isKindOfClass:[NSString class]] || !url.length)
		return;
	if (self.busy)
		return;
	self.busy = YES;

	BOOL requiresApproval = [link[@"requiresApproval"] boolValue];
	if (requiresApproval)
		memberLimit = 0;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] editInviteLink:url
							   inChat:self.chatId
								 name:name ?: @""
					   expirationDate:expirationDate
						  memberLimit:memberLimit
					 requiresApproval:requiresApproval
						   completion:^(NSDictionary *updated){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		strongSelf.busy = NO;
		if (!updated){
			[strongSelf failedWithMessage:@"The link could not be changed."];
			return;
		}
		[strongSelf reload];
	}];
}

#pragma mark - join requests

- (void)showSheetForRequest:(NSDictionary *)request {
	if (!request || !self.canManage)
		return;
	self.pendingRequest = request;

	NSString *name = request[@"name"];
	if (![name isKindOfClass:[NSString class]])
		name = @"";

	NSArray *actions = [NSArray arrayWithObjects:
			[[TGActionSheetAction alloc] initWithTitle:@"Approve" action:@"approve"],
			[[TGActionSheetAction alloc] initWithTitle:@"Decline" action:@"decline"
												  type:TGActionSheetActionTypeDestructive],
			[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
												  type:TGActionSheetActionTypeCancel],
			nil];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:name.length ? name : nil
			actions:actions
			actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				NSDictionary *pending = strongSelf.pendingRequest;
				strongSelf.pendingRequest = nil;
				if ([action isEqualToString:@"approve"])
					[strongSelf processRequest:pending approve:YES];
				else if ([action isEqualToString:@"decline"])
					[strongSelf processRequest:pending approve:NO];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

- (void)processRequest:(NSDictionary *)request approve:(BOOL)approve {
	int64_t userId = [request[@"userId"] longLongValue];
	if (!userId)
		return;

	NSMutableArray *remaining = [NSMutableArray arrayWithArray:self.requests ?: [NSArray array]];
	[remaining removeObject:request];
	self.requests = remaining;
	if (self.requestTotal > 0)
		self.requestTotal -= 1;
	[self rebuildSections];
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] processJoinRequestFromUser:userId inChat:self.chatId
										  approve:approve completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!ok)
			[strongSelf failedWithMessage:@"The request could not be processed."];
		[strongSelf reload];
	}];
}

- (void)confirmApproveAll {
	if (!self.requests.count)
		return;

	NSArray *actions = [NSArray arrayWithObjects:
			[[TGActionSheetAction alloc] initWithTitle:@"Approve All Requests"
												 action:@"approveAll"],
			[[TGActionSheetAction alloc] initWithTitle:@"Decline All Requests"
												 action:@"declineAll"
												   type:TGActionSheetActionTypeDestructive],
			[[TGActionSheetAction alloc] initWithTitle:@"Cancel" action:@"cancel"
												  type:TGActionSheetActionTypeCancel],
			nil];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:nil actions:actions
			actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				if ([action isEqualToString:@"cancel"])
					return;
				BOOL approve = [action isEqualToString:@"approveAll"];

				strongSelf.requests = [NSArray array];
				strongSelf.requestTotal = 0;
				[strongSelf rebuildSections];
				[strongSelf.tableView reloadData];

				[[TGClient shared] processAllJoinRequestsInChat:strongSelf.chatId
													 inviteLink:nil
														approve:approve
													 completion:^(BOOL ok){
					__strong typeof(weakSelf) innerSelf = weakSelf;
					if (!ok)
						[innerSelf failedWithMessage:
								@"The requests could not be processed."];
					[innerSelf reload];
				}];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

@end

// vim:ft=objc

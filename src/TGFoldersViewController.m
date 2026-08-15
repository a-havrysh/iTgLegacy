#import "TGFoldersViewController.h"
#import "TGClient.h"
#import "TGClient+ChatList.h"
#import "TGClient+Premium.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGAlertView.h"

static const CGFloat kRowHeight = 44.0f;
static const CGFloat kChatRowHeight = 51.0f;
static const CGFloat kCaptionInset = 20.0f;

static inline UIColor *TGFoldersRGB(unsigned int value) {
	return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0f
						   green:((value >> 8) & 0xff) / 255.0f
							blue:(value & 0xff) / 255.0f
						   alpha:1.0f];
}

static const NSInteger kColourSheetTag = 200;
static const NSInteger kLinkSheetTag = 201;
static const NSInteger kRenameLinkAlertTag = 202;

static const unsigned int kFolderTagColours[7] = {
	0xe15052, 0xe0802b, 0xa05ff3, 0x27a910, 0x27acce, 0x3391d4, 0xdd4371
};

@interface TGFoldersViewController () <UITextFieldDelegate, UIAlertViewDelegate,
		UIActionSheetDelegate>

@property (nonatomic, assign) NSInteger mainListPosition;
@property (nonatomic, assign) NSInteger folderLimit;
@property (nonatomic, assign) NSInteger chosenChatLimit;
@property (nonatomic, assign) NSInteger pickerLimit;
@property (nonatomic, strong) NSMutableArray *inviteLinks;
@property (nonatomic, assign) BOOL linksLoaded;
@property (nonatomic, assign) NSInteger activeLinkIndex;

@property (nonatomic, strong) NSMutableArray *folders;
@property (nonatomic, strong) NSMutableDictionary *counts;
@property (nonatomic, strong) NSMutableDictionary *icons;
@property (nonatomic, strong) NSMutableArray *recommended;
@property (nonatomic, assign) BOOL listLoaded;
@property (nonatomic, assign) BOOL orderDirty;
@property (nonatomic, assign) BOOL observingFolders;

@property (nonatomic, strong) NSMutableDictionary *draft;
@property (nonatomic, assign) BOOL draftLoaded;
@property (nonatomic, assign) BOOL draftFailed;
@property (nonatomic, strong) UITextField *nameField;

@property (nonatomic, strong) NSMutableArray *pickerChats;
@property (nonatomic, strong) NSMutableSet *pickerSelection;
@property (nonatomic, assign) BOOL pickerLoaded;
@property (nonatomic, copy) void (^pickerCompletion)(NSArray *chatIds);

@property (nonatomic, strong) NSArray *iconNames;
@property (nonatomic, strong) NSString *currentIcon;
@property (nonatomic, strong) NSString *defaultIconName;
@property (nonatomic, copy) void (^iconCompletion)(NSString *iconName);

@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) NSInteger pendingDeleteIndex;

@end

@implementation TGFoldersViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		_page = TGFoldersPageList;
		_folderId = 0;
		_pendingDeleteIndex = -1;
		_activeLinkIndex = -1;
		_mainListPosition = 0;
	}
	return self;
}

- (id)initWithStyle:(UITableViewStyle)style {
	return [self init];
}

#pragma mark - lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.folders = [NSMutableArray array];
	self.counts = [NSMutableDictionary dictionary];
	self.icons = [NSMutableDictionary dictionary];
	self.recommended = [NSMutableArray array];
	self.pickerChats = [NSMutableArray array];
	self.inviteLinks = [NSMutableArray array];

	[self applyTheme];
	[self buildStatusLabel];

	switch (self.page) {
		case TGFoldersPageEditor:
			self.title = self.folderId ? @"Edit Folder" : @"New Folder";
			[self buildEditorButtons];
			[self loadDraft];
			[self loadChosenChatLimit];
			if (self.folderId)
				[self loadInviteLinks];
			break;
		case TGFoldersPageChatPicker:
			if (!self.title.length)
				self.title = @"Select Chats";
			[self buildPickerButtons];
			[self loadPickerChats];
			break;
		case TGFoldersPageIconPicker:
			self.title = @"Icon";
			self.iconNames = [[TGClient shared] folderIconNames];
			break;
		default:
			self.title = @"Folders";
			[self buildListButtons];
			[self observeFolderChanges];
			[self loadFolderLimit];
			[self loadFolders];
			[self loadRecommended];
			break;
	}
}

- (void)observeFolderChanges {
	if (self.observingFolders)
		return;
	self.observingFolders = YES;
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(foldersDidChange)
												 name:TGChatFoldersDidChangeNotification
											   object:nil];
	[[TGClient shared] beginObservingFolderChanges];
}

- (void)foldersDidChange {
	if (self.page != TGFoldersPageList)
		return;
	if (self.tableView.isEditing)
		return;
	[self.counts removeAllObjects];
	[self loadFolders];
	[self loadRecommended];
}

- (void)dealloc {
	if (self.observingFolders)
		[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.page == TGFoldersPageList)
		[self loadFolders];
	else
		[self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.page == TGFoldersPageList)
		[self commitOrder];
}

- (void)viewWillLayoutSubviews {
	[super viewWillLayoutSubviews];
	[self layoutStatusLabel];
}

- (void)applyTheme {
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	if (self.navigationController.navigationBar)
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - chrome

- (void)buildListButtons {
	UIButton *edit = [TGIcons headerButtonWithTitle:@"Edit" bold:NO
											 target:self action:@selector(toggleEditing)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:edit];
}

- (void)buildEditorButtons {
	UIButton *done = [TGIcons headerButtonWithTitle:@"Done" bold:YES
											 target:self action:@selector(saveDraft)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:done];
}

- (void)buildPickerButtons {
	UIButton *done = [TGIcons headerButtonWithTitle:@"Done" bold:YES
											 target:self action:@selector(finishPicking)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:done];
}

- (void)toggleEditing {
	BOOL editing = !self.tableView.isEditing;
	[self.tableView setEditing:editing animated:YES];
	UIButton *button = [TGIcons headerButtonWithTitle:(editing ? @"Done" : @"Edit")
												 bold:editing
											   target:self action:@selector(toggleEditing)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:button];
	if (!editing)
		[self commitOrder];
}

#pragma mark - status label

- (void)buildStatusLabel {
	self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.statusLabel.backgroundColor = [UIColor clearColor];
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.font = [UIFont systemFontOfSize:15];
	self.statusLabel.numberOfLines = 3;
	self.statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.statusLabel.userInteractionEnabled = NO;
	self.statusLabel.hidden = YES;
	[self.tableView addSubview:self.statusLabel];
}

- (void)layoutStatusLabel {
	if (!self.statusLabel || self.statusLabel.hidden)
		return;
	CGRect bounds = self.tableView.bounds;
	self.statusLabel.frame = CGRectMake(kCaptionInset,
			floorf((bounds.size.height - 60) / 2), bounds.size.width - kCaptionInset * 2, 60);
	[self.tableView bringSubviewToFront:self.statusLabel];
}

- (void)showStatus:(NSString *)text {
	if (!text.length) {
		self.statusLabel.hidden = YES;
		return;
	}
	self.statusLabel.text = text;
	self.statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.statusLabel.hidden = NO;
	[self layoutStatusLabel];
}

#pragma mark - folder list data

- (void)loadFolders {
	NSArray *known = [TGClient shared].folders;
	if (![known isKindOfClass:[NSArray class]])
		known = nil;
	[self.folders removeAllObjects];
	for (NSDictionary *folder in known) {
		if ([folder isKindOfClass:[NSDictionary class]] && folder[@"id"])
			[self.folders addObject:folder];
	}
	self.listLoaded = YES;
	if (self.mainListPosition > (NSInteger)self.folders.count)
		self.mainListPosition = self.folders.count;

	if (![TGClient shared].available && self.folders.count == 0)
		[self showStatus:@"Not connected.\nFolders will appear once the app is online."];
	else if (self.folders.count == 0)
		[self showStatus:@"No folders yet.\nCreate one to group your chats."];
	else
		[self showStatus:nil];

	[self.tableView reloadData];
	[self refreshCounts];
}

- (void)refreshCounts {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *folder in self.folders) {
		NSNumber *identifier = folder[@"id"];
		if (![identifier isKindOfClass:[NSNumber class]])
			continue;
		if (self.counts[identifier])
			continue;
		[[TGClient shared] folderWithId:identifier.integerValue
							 completion:^(NSDictionary *definition) {
			if (![definition isKindOfClass:[NSDictionary class]])
				return;
			NSString *icon = definition[@"icon"];
			if ([icon isKindOfClass:[NSString class]] && icon.length)
				weakSelf.icons[identifier] = icon;
			[[TGClient shared] chatCountForFolder:definition completion:^(NSInteger count) {
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf)
					return;
				strongSelf.counts[identifier] = @(count);
				[strongSelf reloadRowForFolderId:identifier];
			}];
		}];
	}
}

- (void)reloadRowForFolderId:(NSNumber *)identifier {
	NSInteger row = NSNotFound;
	for (NSUInteger index = 0; index < self.folders.count; index++) {
		if ([self.folders[index][@"id"] isEqual:identifier]) {
			row = (NSInteger)index
					+ ((NSInteger)index >= self.mainListPosition ? 1 : 0);
			break;
		}
	}
	if (row == NSNotFound || self.tableView.isEditing) {
		[self.tableView reloadData];
		return;
	}
	[self.tableView reloadRowsAtIndexPaths:
			@[[NSIndexPath indexPathForRow:row inSection:0]]
						  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)loadRecommended {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] recommendedFoldersWithCompletion:^(NSArray *entries) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || strongSelf.page != TGFoldersPageList)
			return;
		NSMutableArray *kept = [NSMutableArray array];
		if ([entries isKindOfClass:[NSArray class]]) {
			for (NSDictionary *entry in entries) {
				if (![entry isKindOfClass:[NSDictionary class]])
					continue;
				if (![entry[@"folder"] isKindOfClass:[NSDictionary class]])
					continue;
				[kept addObject:entry];
			}
		}
		if (kept.count == strongSelf.recommended.count
				&& [kept isEqualToArray:strongSelf.recommended])
			return;
		strongSelf.recommended = kept;
		[strongSelf.tableView reloadData];
	}];
}

- (void)addRecommendedAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.recommended.count)
		return;
	NSDictionary *entry = self.recommended[index];
	NSMutableDictionary *definition = [entry[@"folder"] mutableCopy];
	[definition removeObjectForKey:@"id"];
	NSString *title = entry[@"title"];
	if ([title isKindOfClass:[NSString class]] && title.length)
		definition[@"title"] = title;
	NSString *icon = entry[@"icon"];
	if ([icon isKindOfClass:[NSString class]] && icon.length)
		definition[@"icon"] = icon;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] saveFolder:definition completion:^(NSInteger savedId) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (savedId == 0) {
			TGAlertView *alert = [[TGAlertView alloc]
					initWithTitle:@"Folder Not Added"
						  message:@"Telegram refused this folder. You may already have too many."
				cancelButtonTitle:@"OK" okButtonTitle:nil completionBlock:nil];
			[alert show];
			return;
		}
		[strongSelf loadFolders];
		[strongSelf loadRecommended];
	}];
}

- (void)loadFolderLimit {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] effectivePremiumLimit:@"chatFolderCount"
								  completion:^(NSInteger value) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || value <= 0 || strongSelf.folderLimit == value)
			return;
		strongSelf.folderLimit = value;
		[strongSelf.tableView reloadData];
	}];
}

- (void)loadChosenChatLimit {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] effectivePremiumLimit:@"chatFolderChosenChatCount"
								  completion:^(NSInteger value) {
		if (value > 0)
			weakSelf.chosenChatLimit = value;
	}];
}

- (BOOL)folderLimitReached {
	return self.folderLimit > 0 && (NSInteger)self.folders.count >= self.folderLimit;
}

- (void)showFolderLimitAlert {
	NSString *message = [NSString stringWithFormat:
			@"This account can keep %d folders. Delete one to make room for another.",
			(int)self.folderLimit];
	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Folder Limit"
													message:message
										  cancelButtonTitle:@"OK"
											  okButtonTitle:nil
											completionBlock:nil];
	[alert show];
}

- (NSInteger)listRowCount {
	return (NSInteger)self.folders.count + 1;
}

- (NSInteger)folderIndexForRow:(NSInteger)row {
	if (row == self.mainListPosition)
		return -1;
	return row < self.mainListPosition ? row : row - 1;
}

- (NSMutableArray *)combinedListRows {
	NSMutableArray *combined = [NSMutableArray arrayWithArray:self.folders];
	NSInteger position = MIN(MAX(self.mainListPosition, 0), (NSInteger)self.folders.count);
	[combined insertObject:[NSNull null] atIndex:position];
	return combined;
}

- (void)adoptCombinedListRows:(NSArray *)combined {
	NSMutableArray *ordered = [NSMutableArray array];
	NSInteger position = 0;
	for (NSUInteger index = 0; index < combined.count; index++) {
		id entry = combined[index];
		if (entry == [NSNull null])
			position = (NSInteger)ordered.count;
		else
			[ordered addObject:entry];
	}
	self.folders = ordered;
	self.mainListPosition = position;
}

- (void)commitOrder {
	if (!self.orderDirty || self.folders.count == 0)
		return;
	self.orderDirty = NO;
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *folder in self.folders) {
		NSNumber *identifier = folder[@"id"];
		if ([identifier isKindOfClass:[NSNumber class]])
			[ids addObject:identifier];
	}
	NSInteger position = MIN(MAX(self.mainListPosition, 0), (NSInteger)ids.count);
	[[TGClient shared] reorderFolders:ids mainListPosition:position];
}

- (void)openFolder:(NSInteger)identifier {
	TGFoldersViewController *editor = [[TGFoldersViewController alloc] init];
	editor.page = TGFoldersPageEditor;
	editor.folderId = identifier;
	[self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - editor data

- (void)loadDraft {
	if (!self.folderId) {
		self.draft = [NSMutableDictionary dictionary];
		self.draft[@"title"] = @"";
		self.draft[@"includedChatIds"] = [NSMutableArray array];
		self.draft[@"excludedChatIds"] = [NSMutableArray array];
		self.draftLoaded = YES;
		[self showStatus:nil];
		[self.tableView reloadData];
		[self refreshDefaultIcon];
		return;
	}

	[self showStatus:@"Loading..."];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] folderWithId:self.folderId completion:^(NSDictionary *definition) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (![definition isKindOfClass:[NSDictionary class]] || definition.count == 0) {
			strongSelf.draftFailed = YES;
			[strongSelf showStatus:@"This folder could not be loaded.\nGo back and try again."];
			return;
		}
		strongSelf.draft = [definition mutableCopy];
		strongSelf.draft[@"includedChatIds"] =
				[strongSelf mutableIdsFrom:definition[@"includedChatIds"]];
		strongSelf.draft[@"excludedChatIds"] =
				[strongSelf mutableIdsFrom:definition[@"excludedChatIds"]];
		strongSelf.draftLoaded = YES;
		[strongSelf showStatus:nil];
		[strongSelf.tableView reloadData];
		[strongSelf refreshDefaultIcon];
	}];
}

- (void)refreshDefaultIcon {
	if (self.page != TGFoldersPageEditor || !self.draftLoaded)
		return;
	NSString *icon = self.draft[@"icon"];
	if ([icon isKindOfClass:[NSString class]] && icon.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] defaultIconNameForFolder:self.draft completion:^(NSString *iconName) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || ![iconName isKindOfClass:[NSString class]])
			return;
		if ([strongSelf.defaultIconName isEqualToString:iconName])
			return;
		strongSelf.defaultIconName = iconName;
		if (strongSelf.tableView.numberOfSections > 0)
			[strongSelf.tableView reloadRowsAtIndexPaths:
					@[[NSIndexPath indexPathForRow:1 inSection:0]]
										withRowAnimation:UITableViewRowAnimationNone];
	}];
}

- (NSMutableArray *)mutableIdsFrom:(id)value {
	NSMutableArray *result = [NSMutableArray array];
	if ([value isKindOfClass:[NSArray class]]) {
		for (id entry in value) {
			if ([entry isKindOfClass:[NSNumber class]])
				[result addObject:entry];
		}
	}
	return result;
}

- (void)saveDraft {
	if (!self.draftLoaded)
		return;
	NSString *title = self.nameField.text ?: self.draft[@"title"];
	title = [title stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (title.length == 0) {
		TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Folder Name"
														message:@"Please give this folder a name."
											  cancelButtonTitle:@"OK"
												  okButtonTitle:nil
												completionBlock:nil];
		[alert show];
		return;
	}
	self.draft[@"title"] = title;

	NSMutableDictionary *payload = [self.draft mutableCopy];
	if (self.folderId)
		payload[@"id"] = @(self.folderId);
	else
		[payload removeObjectForKey:@"id"];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] saveFolder:payload completion:^(NSInteger savedId) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (savedId == 0) {
			TGAlertView *alert = [[TGAlertView alloc]
					initWithTitle:@"Folder Not Saved"
						  message:@"Telegram refused this folder. It may be full, or the name may be taken."
				cancelButtonTitle:@"OK" okButtonTitle:nil completionBlock:nil];
			[alert show];
			return;
		}
		[strongSelf.navigationController popViewControllerAnimated:YES];
	}];
}

- (NSArray *)includeKeys {
	return @[@"includeContacts", @"includeNonContacts", @"includeGroups",
			@"includeChannels", @"includeBots"];
}

- (NSArray *)includeTitles {
	return @[@"Contacts", @"Non-Contacts", @"Groups", @"Channels", @"Bots"];
}

- (NSArray *)excludeKeys {
	return @[@"excludeMuted", @"excludeRead", @"excludeArchived"];
}

- (NSArray *)excludeTitles {
	return @[@"Muted", @"Read", @"Archived"];
}

- (void)toggleChanged:(UISwitch *)sender {
	NSArray *keys = [[self includeKeys] arrayByAddingObjectsFromArray:[self excludeKeys]];
	if (sender.tag < 0 || sender.tag >= (NSInteger)keys.count)
		return;
	self.draft[keys[sender.tag]] = @(sender.on);
	[self refreshDefaultIcon];
}

- (void)nameChanged:(UITextField *)field {
	self.draft[@"title"] = field.text ?: @"";
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
	[field resignFirstResponder];
	return NO;
}

- (void)confirmDeleteFolder {
	__weak typeof(self) weakSelf = self;
	TGAlertView *alert = [[TGAlertView alloc]
			initWithTitle:@"Delete Folder"
				  message:@"The chats in this folder will not be deleted."
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@[@"Delete"]
		  completionBlock:^(bool okPressed) {
		typeof(self) strongSelf = weakSelf;
		if (!okPressed || !strongSelf)
			return;
		[strongSelf offerToLeaveChatsThenDelete];
	}];
	[alert show];
}

- (void)offerToLeaveChatsThenDelete {
	NSInteger identifier = self.folderId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatsToLeaveWhenDeletingFolder:identifier
										   completion:^(NSArray *chats) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSMutableArray *chatIds = [NSMutableArray array];
		if ([chats isKindOfClass:[NSArray class]]) {
			for (NSDictionary *row in chats) {
				if (![row isKindOfClass:[NSDictionary class]])
					continue;
				NSNumber *chatId = row[@"id"];
				if ([chatId isKindOfClass:[NSNumber class]])
					[chatIds addObject:chatId];
			}
		}
		if (chatIds.count == 0) {
			[strongSelf finishDeletingFolder:identifier leavingChats:nil];
			return;
		}
		NSString *message = chatIds.count == 1
				? @"One chat is only in this folder. Leave it as well?"
				: [NSString stringWithFormat:
						@"%d chats are only in this folder. Leave them as well?",
						(int)chatIds.count];
		TGAlertView *sheet = [[TGAlertView alloc]
				initWithTitle:@"Leave Chats"
					  message:message
			cancelButtonTitle:@"Keep Chats"
			otherButtonTitles:@[@"Leave Chats"]
			  completionBlock:^(bool leave) {
			[weakSelf finishDeletingFolder:identifier leavingChats:(leave ? chatIds : nil)];
		}];
		[sheet show];
	}];
}

- (void)finishDeletingFolder:(NSInteger)identifier leavingChats:(NSArray *)chatIds {
	[[TGClient shared] deleteFolder:identifier leavingChats:chatIds];
	[self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - chat picker

- (void)pushPickerForKey:(NSString *)key title:(NSString *)title {
	TGFoldersViewController *picker = [[TGFoldersViewController alloc] init];
	picker.page = TGFoldersPageChatPicker;
	picker.title = title;
	NSMutableSet *selection = [NSMutableSet set];
	for (NSNumber *identifier in self.draft[key])
		[selection addObject:identifier];
	picker.pickerSelection = selection;
	picker.pickerLimit = self.chosenChatLimit;
	__weak typeof(self) weakSelf = self;
	picker.pickerCompletion = ^(NSArray *chatIds) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.draft[key] = [chatIds mutableCopy];
		[strongSelf.tableView reloadData];
		[strongSelf refreshDefaultIcon];
	};
	[self.navigationController pushViewController:picker animated:YES];
}

- (void)loadPickerChats {
	if (!self.pickerSelection)
		self.pickerSelection = [NSMutableSet set];
	[self showStatus:@"Loading..."];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatsInList:TGChatListMain limit:200 completion:^(NSArray *chats) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		[strongSelf appendPickerChats:chats];
		[[TGClient shared] chatsInList:TGChatListArchive limit:100
							completion:^(NSArray *archived) {
			[weakSelf appendPickerChats:archived];
			[weakSelf finishPickerLoad];
		}];
	}];
}

- (void)appendPickerChats:(NSArray *)chats {
	if (![chats isKindOfClass:[NSArray class]])
		return;
	NSMutableSet *seen = [NSMutableSet set];
	for (NSDictionary *row in self.pickerChats)
		[seen addObject:row[@"id"]];
	for (NSDictionary *row in chats) {
		if (![row isKindOfClass:[NSDictionary class]])
			continue;
		NSNumber *identifier = row[@"id"];
		if (![identifier isKindOfClass:[NSNumber class]] || [seen containsObject:identifier])
			continue;
		[seen addObject:identifier];
		[self.pickerChats addObject:row];
	}
}

- (void)finishPickerLoad {
	self.pickerLoaded = YES;
	if (self.pickerChats.count == 0)
		[self showStatus:@"No chats to choose from."];
	else
		[self showStatus:nil];
	[self.tableView reloadData];
}

- (void)finishPicking {
	NSMutableArray *ordered = [NSMutableArray array];
	for (NSDictionary *row in self.pickerChats) {
		NSNumber *identifier = row[@"id"];
		if ([self.pickerSelection containsObject:identifier])
			[ordered addObject:identifier];
	}
	for (NSNumber *identifier in self.pickerSelection) {
		if (![ordered containsObject:identifier])
			[ordered addObject:identifier];
	}
	if (self.pickerCompletion)
		self.pickerCompletion(ordered);
	[self.navigationController popViewControllerAnimated:YES];
}

- (NSString *)titleForChatId:(NSNumber *)identifier {
	NSArray *pools = @[[TGClient shared].chats ?: @[], [TGClient shared].archivedChats ?: @[]];
	for (NSArray *pool in pools) {
		if (![pool isKindOfClass:[NSArray class]])
			continue;
		for (NSDictionary *row in pool) {
			if (![row isKindOfClass:[NSDictionary class]])
				continue;
			if ([row[@"id"] isEqual:identifier]) {
				NSString *title = row[@"title"];
				if ([title isKindOfClass:[NSString class]] && title.length)
					return title;
			}
		}
	}
	return @"Chat";
}

- (NSString *)initialsForTitle:(NSString *)title {
	if (!title.length)
		return @"#";
	return [[title substringToIndex:1] uppercaseString];
}

#pragma mark - icon picker

- (void)pushIconPicker {
	TGFoldersViewController *picker = [[TGFoldersViewController alloc] init];
	picker.page = TGFoldersPageIconPicker;
	NSString *icon = self.draft[@"icon"];
	picker.currentIcon = [icon isKindOfClass:[NSString class]] ? icon : @"";
	__weak typeof(self) weakSelf = self;
	picker.iconCompletion = ^(NSString *iconName) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.draft[@"icon"] = iconName ?: @"";
		[strongSelf.tableView reloadData];
	};
	[self.navigationController pushViewController:picker animated:YES];
}

#pragma mark - tag colour

- (NSArray *)colourTitles {
	return @[@"Red", @"Orange", @"Violet", @"Green", @"Cyan", @"Blue", @"Pink"];
}

- (NSInteger)draftColourId {
	NSNumber *value = self.draft[@"colorId"];
	if (![value isKindOfClass:[NSNumber class]])
		return -1;
	NSInteger colourId = value.integerValue;
	return (colourId >= 0 && colourId < 7) ? colourId : -1;
}

- (UIImage *)swatchForColourId:(NSInteger)colourId {
	if (colourId < 0 || colourId >= 7)
		return nil;
	CGSize size = CGSizeMake(22, 22);
	UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(context,
			TGFoldersRGB(kFolderTagColours[colourId]).CGColor);
	CGContextFillEllipseInRect(context, CGRectMake(1, 1, size.width - 2, size.height - 2));
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

- (void)chooseColour {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Folder Colour"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"No Colour"];
	for (NSString *title in [self colourTitles])
		[sheet addButtonWithTitle:title];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kColourSheetTag;
	[sheet showInView:self.view];
}

#pragma mark - invite links

- (void)loadInviteLinks {
	if (!self.folderId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inviteLinksForFolder:self.folderId completion:^(NSArray *links) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSMutableArray *kept = [NSMutableArray array];
		if ([links isKindOfClass:[NSArray class]]) {
			for (NSDictionary *link in links) {
				if ([link isKindOfClass:[NSDictionary class]]
						&& [link[@"link"] isKindOfClass:[NSString class]])
					[kept addObject:link];
			}
		}
		strongSelf.inviteLinks = kept;
		strongSelf.linksLoaded = YES;
		if (strongSelf.draftLoaded)
			[strongSelf.tableView reloadData];
	}];
}

- (void)createInviteLink {
	if (!self.folderId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] shareableChatsInFolder:self.folderId completion:^(NSArray *chats) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSMutableArray *chatIds = [NSMutableArray array];
		if ([chats isKindOfClass:[NSArray class]]) {
			for (NSDictionary *row in chats) {
				if (![row isKindOfClass:[NSDictionary class]])
					continue;
				NSNumber *chatId = row[@"id"];
				if ([chatId isKindOfClass:[NSNumber class]])
					[chatIds addObject:chatId];
			}
		}
		if (chatIds.count == 0) {
			TGAlertView *alert = [[TGAlertView alloc]
					initWithTitle:@"No Chats to Share"
						  message:@"Only groups and channels you can invite people to "
								   "can go into a folder link."
				cancelButtonTitle:@"OK" okButtonTitle:nil completionBlock:nil];
			[alert show];
			return;
		}
		[[TGClient shared] createInviteLinkForFolder:strongSelf.folderId
												name:@""
											 chatIds:chatIds
										  completion:^(NSDictionary *link) {
			if (![link isKindOfClass:[NSDictionary class]]) {
				TGAlertView *alert = [[TGAlertView alloc]
						initWithTitle:@"Link Not Created"
							  message:@"Telegram refused this invite link."
					cancelButtonTitle:@"OK" okButtonTitle:nil completionBlock:nil];
				[alert show];
				return;
			}
			[weakSelf loadInviteLinks];
		}];
	}];
}

- (NSDictionary *)activeLink {
	if (self.activeLinkIndex < 0 || self.activeLinkIndex >= (NSInteger)self.inviteLinks.count)
		return nil;
	return self.inviteLinks[self.activeLinkIndex];
}

- (void)openLinkActionsAtIndex:(NSInteger)index {
	self.activeLinkIndex = index;
	NSDictionary *link = [self activeLink];
	if (!link)
		return;
	UIActionSheet *sheet = [[UIActionSheet alloc]
			initWithTitle:link[@"link"]
				 delegate:self
		cancelButtonTitle:nil
   destructiveButtonTitle:nil
		otherButtonTitles:@"Copy Link", @"Rename Link", nil];
	sheet.destructiveButtonIndex = [sheet addButtonWithTitle:@"Delete Link"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kLinkSheetTag;
	[sheet showInView:self.view];
}

- (void)renameActiveLink {
	NSDictionary *link = [self activeLink];
	if (!link)
		return;
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Link Name"
													message:nil
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Save", nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	alert.tag = kRenameLinkAlertTag;
	NSString *name = link[@"name"];
	if ([name isKindOfClass:[NSString class]])
		[alert textFieldAtIndex:0].text = name;
	[alert show];
}

- (void)deleteLinkAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.inviteLinks.count)
		return;
	NSDictionary *link = self.inviteLinks[index];
	[[TGClient shared] deleteInviteLink:link[@"link"] forFolder:self.folderId];
	[self.inviteLinks removeObjectAtIndex:index];
	self.activeLinkIndex = -1;
	[self.tableView reloadData];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (alertView.tag != kRenameLinkAlertTag || buttonIndex == alertView.cancelButtonIndex)
		return;
	NSDictionary *link = [self activeLink];
	if (!link)
		return;
	NSString *name = [alertView textFieldAtIndex:0].text ?: @"";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] editInviteLink:link[@"link"]
							forFolder:self.folderId
								 name:name
							  chatIds:link[@"chatIds"]
						   completion:^(NSDictionary *updated) {
		[weakSelf loadInviteLinks];
	}];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == kColourSheetTag) {
		self.draft[@"colorId"] = @(index - 1);
		[self.tableView reloadData];
		return;
	}

	if (sheet.tag == kLinkSheetTag) {
		NSDictionary *link = [self activeLink];
		if (!link)
			return;
		if (index == sheet.destructiveButtonIndex) {
			[self deleteLinkAtIndex:self.activeLinkIndex];
			return;
		}
		if (index == 0) {
			[UIPasteboard generalPasteboard].string = link[@"link"];
			return;
		}
		if (index == 1)
			[self renameActiveLink];
	}
}

#pragma mark - table structure

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	switch (self.page) {
		case TGFoldersPageEditor:
			if (!self.draftLoaded)
				return 0;
			return self.folderId ? 5 : 3;
		case TGFoldersPageChatPicker:
		case TGFoldersPageIconPicker:
			return 1;
		default:
			return self.recommended.count ? 3 : 2;
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (self.page == TGFoldersPageChatPicker)
		return self.pickerChats.count;
	if (self.page == TGFoldersPageIconPicker)
		return self.iconNames.count + 1;
	if (self.page == TGFoldersPageEditor) {
		if (section == 0)
			return 3;
		if (section == 1)
			return [self includeKeys].count + [self.draft[@"includedChatIds"] count] + 1;
		if (section == 2)
			return [self excludeKeys].count + [self.draft[@"excludedChatIds"] count] + 1;
		if (section == 3)
			return self.inviteLinks.count + 1;
		return 1;
	}
	if (section == 0)
		return [self listRowCount];
	if (section == 2)
		return self.recommended.count;
	return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.page == TGFoldersPageChatPicker)
		return kChatRowHeight;
	if (self.page == TGFoldersPageEditor && indexPath.section == 3
			&& indexPath.row < (NSInteger)self.inviteLinks.count)
		return kChatRowHeight;
	return kRowHeight;
}

- (NSString *)captionForSection:(NSInteger)section {
	if (self.page == TGFoldersPageList) {
		if (section == 1) {
			NSString *base = @"Folders let you group chats and switch between them "
					"from the chat list. Drag All Chats to change which tab opens first.";
			if (self.folderLimit > 0)
				return [NSString stringWithFormat:@"%@\n\nYou have created %d of %d folders.",
						base, (int)self.folders.count, (int)self.folderLimit];
			return base;
		}
		if (section == 2)
			return @"Recommended folders.";
		return nil;
	}
	if (self.page == TGFoldersPageEditor) {
		if (section == 1)
			return @"Choose chats and types of chats that will appear in this folder.";
		if (section == 2)
			return @"Choose chats and types of chats that will never appear in this folder.";
		if (section == 3)
			return @"Invite links let other people join the groups and channels "
					"of this folder in one step.";
	}
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	NSString *caption = [self captionForSection:section];
	if (!caption)
		return section == 0 ? 12 : 20;
	CGSize limit = CGSizeMake(self.tableView.bounds.size.width - kCaptionInset * 2, 200);
	CGSize measured = [caption sizeWithFont:[UIFont systemFontOfSize:14]
						  constrainedToSize:limit
							  lineBreakMode:NSLineBreakByWordWrapping];
	return measured.height + 18;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *caption = [self captionForSection:section];
	if (!caption)
		return nil;
	CGFloat width = self.tableView.bounds.size.width;
	CGFloat height = [self tableView:tableView heightForHeaderInSection:section];
	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	container.backgroundColor = [UIColor clearColor];
	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(kCaptionInset, 6, width - kCaptionInset * 2, height - 12)];
	label.text = caption;
	label.numberOfLines = 0;
	label.font = [UIFont systemFontOfSize:14];
	label.backgroundColor = [UIColor clearColor];
	label.textColor = [[TGTheme shared] isDark] ? [[TGTheme shared] secondaryTextColour]
												: TGFoldersRGB(0x697487);
	if (![[TGTheme shared] isDark]) {
		label.shadowColor = TGFoldersRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	[container addSubview:label];
	return container;
}

#pragma mark - cells

- (UIView *)disclosureAccessory {
	UIImage *art = [[TGTheme shared] isDark]
			? [UIImage imageNamed:@"MenuDisclosureIndicator_Light.png"]
			: [UIImage imageNamed:@"MenuDisclosureIndicator.png"];
	if (!art)
		return nil;
	UIImageView *view = [[UIImageView alloc] initWithImage:art
										  highlightedImage:[UIImage imageNamed:
												  @"MenuDisclosureIndicator_Highlighted.png"]];
	view.frame = CGRectMake(0, 0, art.size.width, art.size.height);
	return view;
}

- (void)markDisclosure:(UITableViewCell *)cell {
	UIView *chevron = [self disclosureAccessory];
	if (chevron) {
		cell.accessoryView = chevron;
		cell.accessoryType = UITableViewCellAccessoryNone;
	} else {
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
}

- (void)markChecked:(BOOL)checked on:(UITableViewCell *)cell {
	cell.accessoryView = nil;
	if (!checked) {
		cell.accessoryType = UITableViewCellAccessoryNone;
		return;
	}
	UIImage *art = [UIImage imageNamed:@"ListCheck.png"];
	if (art) {
		UIImageView *view = [[UIImageView alloc] initWithImage:art];
		view.frame = CGRectMake(0, 0, art.size.width, art.size.height);
		cell.accessoryView = view;
		cell.accessoryType = UITableViewCellAccessoryNone;
	} else {
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	}
}

- (UITableViewCell *)plainCellFor:(UITableView *)tableView identifier:(NSString *)identifier
							style:(UITableViewCellStyle)style {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.imageView.image = nil;
	cell.detailTextLabel.text = nil;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	[[TGTheme shared] styleCell:cell];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	switch (self.page) {
		case TGFoldersPageEditor:
			return [self editorCellFor:tableView at:indexPath];
		case TGFoldersPageChatPicker:
			return [self pickerCellFor:tableView at:indexPath];
		case TGFoldersPageIconPicker:
			return [self iconCellFor:tableView at:indexPath];
		default:
			return [self listCellFor:tableView at:indexPath];
	}
}

- (NSString *)glyphForIconName:(NSString *)name {
	if (![name isKindOfClass:[NSString class]] || !name.length)
		return nil;
	NSString *symbol = [[TGClient shared] symbolForFolderIconName:name];
	return symbol.length ? symbol : nil;
}

- (UITableViewCell *)listCellFor:(UITableView *)tableView at:(NSIndexPath *)indexPath {
	if (indexPath.section == 2) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderSuggested"
											 style:UITableViewCellStyleValue1];
		NSDictionary *entry = self.recommended[indexPath.row];
		NSString *title = entry[@"title"];
		NSString *glyph = [self glyphForIconName:entry[@"icon"]];
		if (![title isKindOfClass:[NSString class]] || !title.length)
			title = @"Folder";
		cell.textLabel.text = glyph
				? [NSString stringWithFormat:@"%@  %@", glyph, title] : title;
		cell.detailTextLabel.text = @"Add";
		cell.detailTextLabel.textColor = TGFoldersRGB(0x0779d0);
		return cell;
	}

	if (indexPath.section == 1) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderAction"
											 style:UITableViewCellStyleDefault];
		cell.textLabel.text = @"Create New Folder";
		cell.textLabel.textColor = TGFoldersRGB(0x0779d0);
		return cell;
	}

	NSInteger folderIndex = [self folderIndexForRow:indexPath.row];
	if (folderIndex < 0) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderAllChats"
											 style:UITableViewCellStyleValue1];
		cell.textLabel.text = @"All Chats";
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}
	if (folderIndex >= (NSInteger)self.folders.count)
		return [self plainCellFor:tableView identifier:@"TGFolderRow"
							style:UITableViewCellStyleValue1];

	UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderRow"
										 style:UITableViewCellStyleValue1];
	NSDictionary *folder = self.folders[folderIndex];
	NSString *title = folder[@"title"];
	if (![title isKindOfClass:[NSString class]] || !title.length)
		title = @"Folder";
	NSString *glyph = [self glyphForIconName:self.icons[folder[@"id"]]];
	cell.textLabel.text = glyph ? [NSString stringWithFormat:@"%@  %@", glyph, title] : title;
	NSNumber *count = self.counts[folder[@"id"]];
	if (count)
		cell.detailTextLabel.text = count.integerValue == 1
				? @"1 chat" : [NSString stringWithFormat:@"%d chats", (int)count.integerValue];
	[self markDisclosure:cell];
	return cell;
}

- (UITableViewCell *)editorCellFor:(UITableView *)tableView at:(NSIndexPath *)indexPath {
	if (indexPath.section == 0 && indexPath.row == 0) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderName"
											 style:UITableViewCellStyleDefault];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		if (!self.nameField) {
			CGFloat width = tableView.bounds.size.width;
			self.nameField = [[UITextField alloc] initWithFrame:
					CGRectMake(15, 12, width - 30 - 15, 22)];
			self.nameField.placeholder = @"Folder Name";
			self.nameField.font = [UIFont systemFontOfSize:16];
			self.nameField.textColor = [[TGTheme shared] primaryTextColour];
			self.nameField.delegate = self;
			self.nameField.returnKeyType = UIReturnKeyDone;
			self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
			self.nameField.autocorrectionType = UITextAutocorrectionTypeNo;
			self.nameField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
			[self.nameField addTarget:self action:@selector(nameChanged:)
					 forControlEvents:UIControlEventEditingChanged];
			NSString *title = self.draft[@"title"];
			self.nameField.text = [title isKindOfClass:[NSString class]] ? title : @"";
		}
		if (self.nameField.superview != cell.contentView)
			[cell.contentView addSubview:self.nameField];
		return cell;
	}

	if (indexPath.section == 0 && indexPath.row == 2) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderColour"
											 style:UITableViewCellStyleValue1];
		cell.textLabel.text = @"Colour";
		NSInteger colourId = [self draftColourId];
		UIImage *swatch = [self swatchForColourId:colourId];
		if (swatch) {
			UIImageView *view = [[UIImageView alloc] initWithImage:swatch];
			view.frame = CGRectMake(0, 0, swatch.size.width, swatch.size.height);
			cell.accessoryView = view;
			cell.detailTextLabel.text = [self colourTitles][colourId];
		} else {
			cell.detailTextLabel.text = @"None";
			[self markDisclosure:cell];
		}
		return cell;
	}

	if (indexPath.section == 0) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderIcon"
											 style:UITableViewCellStyleValue1];
		cell.textLabel.text = @"Icon";
		NSString *icon = self.draft[@"icon"];
		BOOL explicit = [icon isKindOfClass:[NSString class]] && icon.length;
		NSString *shown = explicit ? icon : self.defaultIconName;
		NSString *glyph = [self glyphForIconName:shown];
		if (!shown.length)
			cell.detailTextLabel.text = @"Default";
		else if (glyph)
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@", glyph, shown];
		else
			cell.detailTextLabel.text = shown;
		[self markDisclosure:cell];
		return cell;
	}

	if (indexPath.section == 3) {
		if (indexPath.row < (NSInteger)self.inviteLinks.count) {
			UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderLink"
												 style:UITableViewCellStyleSubtitle];
			NSDictionary *link = self.inviteLinks[indexPath.row];
			NSString *name = link[@"name"];
			NSString *url = link[@"link"];
			cell.textLabel.font = [UIFont systemFontOfSize:17];
			cell.textLabel.text = ([name isKindOfClass:[NSString class]] && name.length)
					? name : url;
			NSArray *chatIds = link[@"chatIds"];
			NSInteger count = [chatIds isKindOfClass:[NSArray class]]
					? (NSInteger)chatIds.count : 0;
			cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
			cell.detailTextLabel.text = count == 1
					? @"1 chat" : [NSString stringWithFormat:@"%d chats", (int)count];
			[self markDisclosure:cell];
			return cell;
		}
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderAddLink"
											 style:UITableViewCellStyleDefault];
		cell.textLabel.text = @"Create an Invite Link";
		cell.textLabel.textColor = TGFoldersRGB(0x0779d0);
		return cell;
	}

	if (indexPath.section == 4) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderDelete"
											 style:UITableViewCellStyleDefault];
		cell.textLabel.text = @"Delete Folder";
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.textLabel.textColor = TGFoldersRGB(0xcc1e2c);
		return cell;
	}

	BOOL included = (indexPath.section == 1);
	NSArray *keys = included ? [self includeKeys] : [self excludeKeys];
	NSArray *titles = included ? [self includeTitles] : [self excludeTitles];
	NSArray *chatIds = self.draft[included ? @"includedChatIds" : @"excludedChatIds"];

	if (indexPath.row < (NSInteger)keys.count) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderToggle"
											 style:UITableViewCellStyleDefault];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.textLabel.text = titles[indexPath.row];
		UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
		NSInteger flatIndex = included
				? indexPath.row : [self includeKeys].count + indexPath.row;
		toggle.tag = flatIndex;
		toggle.on = [self.draft[keys[indexPath.row]] boolValue];
		[toggle addTarget:self action:@selector(toggleChanged:)
		 forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		return cell;
	}

	NSInteger chatIndex = indexPath.row - keys.count;
	if (chatIndex < (NSInteger)chatIds.count) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderChat"
											 style:UITableViewCellStyleDefault];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.textLabel.font = [UIFont systemFontOfSize:17];
		cell.textLabel.text = [self titleForChatId:chatIds[chatIndex]];
		return cell;
	}

	UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderAddChats"
										 style:UITableViewCellStyleDefault];
	cell.textLabel.text = included ? @"Add Chats" : @"Exclude Chats";
	cell.textLabel.textColor = TGFoldersRGB(0x0779d0);
	return cell;
}

- (UITableViewCell *)pickerCellFor:(UITableView *)tableView at:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderPick"
										 style:UITableViewCellStyleDefault];
	NSDictionary *row = self.pickerChats[indexPath.row];
	NSString *title = row[@"title"];
	if (![title isKindOfClass:[NSString class]] || !title.length)
		title = @"Chat";
	cell.textLabel.text = title;
	cell.textLabel.font = [UIFont systemFontOfSize:19];
	NSNumber *identifier = row[@"id"];
	cell.imageView.image = [TGIcons avatarWithInitials:[self initialsForTitle:title]
												  size:40
											  colourId:[identifier longLongValue]];
	[self markChecked:[self.pickerSelection containsObject:identifier] on:cell];
	return cell;
}

- (UITableViewCell *)iconCellFor:(UITableView *)tableView at:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderIconName"
										 style:UITableViewCellStyleDefault];
	if (indexPath.row == 0) {
		cell.textLabel.text = @"Default";
		cell.textLabel.font = [UIFont systemFontOfSize:17];
		[self markChecked:!(self.currentIcon.length) on:cell];
		return cell;
	}
	NSString *name = self.iconNames[indexPath.row - 1];
	NSString *glyph = [self glyphForIconName:name];
	cell.textLabel.text = glyph ? [NSString stringWithFormat:@"%@  %@", glyph, name] : name;
	cell.textLabel.font = [UIFont systemFontOfSize:17];
	[self markChecked:[name isEqualToString:self.currentIcon ?: @""] on:cell];
	return cell;
}

#pragma mark - selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (self.page == TGFoldersPageList) {
		if (indexPath.section == 2) {
			[self addRecommendedAtIndex:indexPath.row];
			return;
		}
		if (indexPath.section == 1) {
			if ([self folderLimitReached]) {
				[self showFolderLimitAlert];
				return;
			}
			TGFoldersViewController *editor = [[TGFoldersViewController alloc] init];
			editor.page = TGFoldersPageEditor;
			[self.navigationController pushViewController:editor animated:YES];
			return;
		}
		NSInteger folderIndex = [self folderIndexForRow:indexPath.row];
		if (folderIndex >= 0 && folderIndex < (NSInteger)self.folders.count) {
			NSNumber *identifier = self.folders[folderIndex][@"id"];
			[self openFolder:identifier.integerValue];
		}
		return;
	}

	if (self.page == TGFoldersPageChatPicker) {
		NSNumber *identifier = self.pickerChats[indexPath.row][@"id"];
		if (![self.pickerSelection containsObject:identifier] && self.pickerLimit > 0
				&& (NSInteger)self.pickerSelection.count >= self.pickerLimit) {
			TGAlertView *alert = [[TGAlertView alloc]
					initWithTitle:@"Chat Limit"
						  message:[NSString stringWithFormat:
								  @"A folder can name %d chats directly.",
								  (int)self.pickerLimit]
				cancelButtonTitle:@"OK" okButtonTitle:nil completionBlock:nil];
			[alert show];
			return;
		}
		if ([self.pickerSelection containsObject:identifier])
			[self.pickerSelection removeObject:identifier];
		else
			[self.pickerSelection addObject:identifier];
		[tableView reloadRowsAtIndexPaths:@[indexPath]
						 withRowAnimation:UITableViewRowAnimationNone];
		return;
	}

	if (self.page == TGFoldersPageIconPicker) {
		NSString *name = indexPath.row == 0 ? @"" : self.iconNames[indexPath.row - 1];
		self.currentIcon = name;
		if (self.iconCompletion)
			self.iconCompletion(name);
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}

	if (indexPath.section == 0 && indexPath.row == 1) {
		[self.nameField resignFirstResponder];
		[self pushIconPicker];
		return;
	}
	if (indexPath.section == 0 && indexPath.row == 2) {
		[self.nameField resignFirstResponder];
		[self chooseColour];
		return;
	}
	if (indexPath.section == 3) {
		[self.nameField resignFirstResponder];
		if (indexPath.row < (NSInteger)self.inviteLinks.count)
			[self openLinkActionsAtIndex:indexPath.row];
		else
			[self createInviteLink];
		return;
	}
	if (indexPath.section == 4) {
		[self confirmDeleteFolder];
		return;
	}
	if (indexPath.section == 1 || indexPath.section == 2) {
		BOOL included = (indexPath.section == 1);
		NSArray *keys = included ? [self includeKeys] : [self excludeKeys];
		NSArray *chatIds = self.draft[included ? @"includedChatIds" : @"excludedChatIds"];
		if (indexPath.row == (NSInteger)(keys.count + chatIds.count)) {
			[self.nameField resignFirstResponder];
			[self pushPickerForKey:(included ? @"includedChatIds" : @"excludedChatIds")
							 title:(included ? @"Include Chats" : @"Exclude Chats")];
		}
	}
}

#pragma mark - editing

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.page == TGFoldersPageList)
		return indexPath.section == 0 && [self folderIndexForRow:indexPath.row] >= 0;
	if (self.page == TGFoldersPageEditor && indexPath.section == 3)
		return indexPath.row < (NSInteger)self.inviteLinks.count;
	if (self.page == TGFoldersPageEditor
			&& (indexPath.section == 1 || indexPath.section == 2)) {
		BOOL included = (indexPath.section == 1);
		NSArray *keys = included ? [self includeKeys] : [self excludeKeys];
		NSArray *chatIds = self.draft[included ? @"includedChatIds" : @"excludedChatIds"];
		return indexPath.row >= (NSInteger)keys.count
				&& indexPath.row < (NSInteger)(keys.count + chatIds.count);
	}
	return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return self.page == TGFoldersPageList && indexPath.section == 0
			&& indexPath.row < [self listRowCount];
}

- (void)tableView:(UITableView *)tableView
		moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
	if (to.section != 0 || from.row >= [self listRowCount])
		return;
	NSMutableArray *combined = [self combinedListRows];
	id entry = combined[from.row];
	[combined removeObjectAtIndex:from.row];
	NSInteger target = MIN(to.row, (NSInteger)combined.count);
	[combined insertObject:entry atIndex:target];
	[self adoptCombinedListRows:combined];
	self.orderDirty = YES;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from
	   toProposedIndexPath:(NSIndexPath *)proposed {
	if (proposed.section != 0)
		return [NSIndexPath indexPathForRow:[self listRowCount] - 1 inSection:0];
	return proposed;
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)style
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (style != UITableViewCellEditingStyleDelete)
		return;

	if (self.page == TGFoldersPageEditor && indexPath.section == 3) {
		[self deleteLinkAtIndex:indexPath.row];
		return;
	}

	if (self.page == TGFoldersPageEditor) {
		BOOL included = (indexPath.section == 1);
		NSString *key = included ? @"includedChatIds" : @"excludedChatIds";
		NSArray *keys = included ? [self includeKeys] : [self excludeKeys];
		NSMutableArray *chatIds = self.draft[key];
		NSInteger index = indexPath.row - keys.count;
		if (index >= 0 && index < (NSInteger)chatIds.count) {
			[chatIds removeObjectAtIndex:index];
			[tableView deleteRowsAtIndexPaths:@[indexPath]
							 withRowAnimation:UITableViewRowAnimationFade];
		}
		return;
	}

	NSInteger folderIndex = [self folderIndexForRow:indexPath.row];
	if (folderIndex < 0 || folderIndex >= (NSInteger)self.folders.count)
		return;
	self.pendingDeleteIndex = folderIndex;
	NSDictionary *folder = self.folders[folderIndex];
	NSString *title = folder[@"title"];
	__weak typeof(self) weakSelf = self;
	TGAlertView *alert = [[TGAlertView alloc]
			initWithTitle:@"Delete Folder"
				  message:[NSString stringWithFormat:
						  @"Delete \"%@\"? The chats in it will not be deleted.",
						  [title isKindOfClass:[NSString class]] ? title : @"this folder"]
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@[@"Delete"]
		  completionBlock:^(bool okPressed) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSInteger index = strongSelf.pendingDeleteIndex;
		strongSelf.pendingDeleteIndex = -1;
		if (!okPressed || index < 0 || index >= (NSInteger)strongSelf.folders.count)
			return;
		NSNumber *identifier = strongSelf.folders[index][@"id"];
		[[TGClient shared] deleteFolder:identifier.integerValue leavingChats:nil];
		[strongSelf.folders removeObjectAtIndex:index];
		[strongSelf.counts removeObjectForKey:identifier];
		if (strongSelf.mainListPosition > (NSInteger)strongSelf.folders.count)
			strongSelf.mainListPosition = strongSelf.folders.count;
		[strongSelf.tableView reloadData];
		if (strongSelf.folders.count == 0)
			[strongSelf showStatus:@"No folders yet.\nCreate one to group your chats."];
	}];
	[alert show];
}

- (NSString *)tableView:(UITableView *)tableView
titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.page == TGFoldersPageEditor && indexPath.section == 3)
		return @"Delete";
	return self.page == TGFoldersPageEditor ? @"Remove" : @"Delete";
}

@end

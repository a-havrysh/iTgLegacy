#import "TGFoldersViewController.h"
#import "TGClient.h"
#import "TGClient+ChatList.h"
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

@interface TGFoldersViewController () <UITextFieldDelegate, UIAlertViewDelegate>

@property (nonatomic, strong) NSMutableArray *folders;
@property (nonatomic, strong) NSMutableDictionary *counts;
@property (nonatomic, assign) BOOL listLoaded;

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
	self.pickerChats = [NSMutableArray array];

	[self applyTheme];
	[self buildStatusLabel];

	switch (self.page) {
		case TGFoldersPageEditor:
			self.title = self.folderId ? @"Edit Folder" : @"New Folder";
			[self buildEditorButtons];
			[self loadDraft];
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
			[self loadFolders];
			break;
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.page == TGFoldersPageList)
		[self loadFolders];
	else
		[self.tableView reloadData];
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
			[[TGClient shared] chatCountForFolder:definition completion:^(NSInteger count) {
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf)
					return;
				strongSelf.counts[identifier] = @(count);
				[strongSelf.tableView reloadData];
			}];
		}];
	}
}

- (void)reloadFoldersSoon {
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		[weakSelf.counts removeAllObjects];
		[weakSelf loadFolders];
	});
}

- (void)commitOrder {
	if (self.folders.count == 0)
		return;
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *folder in self.folders) {
		NSNumber *identifier = folder[@"id"];
		if ([identifier isKindOfClass:[NSNumber class]])
			[ids addObject:identifier];
	}
	[[TGClient shared] reorderFolders:ids mainListPosition:0];
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
		[[TGClient shared] deleteFolder:strongSelf.folderId leavingChats:nil];
		[strongSelf.navigationController popViewControllerAnimated:YES];
	}];
	[alert show];
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
	__weak typeof(self) weakSelf = self;
	picker.pickerCompletion = ^(NSArray *chatIds) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.draft[key] = [chatIds mutableCopy];
		[strongSelf.tableView reloadData];
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

#pragma mark - table structure

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	switch (self.page) {
		case TGFoldersPageEditor:
			if (!self.draftLoaded)
				return 0;
			return self.folderId ? 4 : 3;
		case TGFoldersPageChatPicker:
		case TGFoldersPageIconPicker:
			return 1;
		default:
			return 2;
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (self.page == TGFoldersPageChatPicker)
		return self.pickerChats.count;
	if (self.page == TGFoldersPageIconPicker)
		return self.iconNames.count;
	if (self.page == TGFoldersPageEditor) {
		if (section == 0)
			return 2;
		if (section == 1)
			return [self includeKeys].count + [self.draft[@"includedChatIds"] count] + 1;
		if (section == 2)
			return [self excludeKeys].count + [self.draft[@"excludedChatIds"] count] + 1;
		return 1;
	}
	return section == 0 ? self.folders.count : 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return self.page == TGFoldersPageChatPicker ? kChatRowHeight : kRowHeight;
}

- (NSString *)captionForSection:(NSInteger)section {
	if (self.page == TGFoldersPageList)
		return section == 1
				? @"Folders let you group chats and switch between them from the chat list."
				: nil;
	if (self.page == TGFoldersPageEditor) {
		if (section == 1)
			return @"Choose chats and types of chats that will appear in this folder.";
		if (section == 2)
			return @"Choose chats and types of chats that will never appear in this folder.";
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

- (UITableViewCell *)listCellFor:(UITableView *)tableView at:(NSIndexPath *)indexPath {
	if (indexPath.section == 1) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderAction"
											 style:UITableViewCellStyleDefault];
		cell.textLabel.text = @"Create New Folder";
		cell.textLabel.textColor = TGFoldersRGB(0x0779d0);
		return cell;
	}

	UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderRow"
										 style:UITableViewCellStyleValue1];
	NSDictionary *folder = self.folders[indexPath.row];
	NSString *title = folder[@"title"];
	cell.textLabel.text = [title isKindOfClass:[NSString class]] && title.length
			? title : @"Folder";
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

	if (indexPath.section == 0) {
		UITableViewCell *cell = [self plainCellFor:tableView identifier:@"TGFolderIcon"
											 style:UITableViewCellStyleValue1];
		cell.textLabel.text = @"Icon";
		NSString *icon = self.draft[@"icon"];
		cell.detailTextLabel.text = [icon isKindOfClass:[NSString class]] && icon.length
				? icon : @"Default";
		[self markDisclosure:cell];
		return cell;
	}

	if (indexPath.section == 3) {
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
	NSString *name = self.iconNames[indexPath.row];
	cell.textLabel.text = name;
	cell.textLabel.font = [UIFont systemFontOfSize:17];
	[self markChecked:[name isEqualToString:self.currentIcon ?: @""] on:cell];
	return cell;
}

#pragma mark - selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (self.page == TGFoldersPageList) {
		if (indexPath.section == 1) {
			TGFoldersViewController *editor = [[TGFoldersViewController alloc] init];
			editor.page = TGFoldersPageEditor;
			[self.navigationController pushViewController:editor animated:YES];
			return;
		}
		if (indexPath.row < (NSInteger)self.folders.count) {
			NSNumber *identifier = self.folders[indexPath.row][@"id"];
			[self openFolder:identifier.integerValue];
		}
		return;
	}

	if (self.page == TGFoldersPageChatPicker) {
		NSNumber *identifier = self.pickerChats[indexPath.row][@"id"];
		if ([self.pickerSelection containsObject:identifier])
			[self.pickerSelection removeObject:identifier];
		else
			[self.pickerSelection addObject:identifier];
		[tableView reloadRowsAtIndexPaths:@[indexPath]
						 withRowAnimation:UITableViewRowAnimationNone];
		return;
	}

	if (self.page == TGFoldersPageIconPicker) {
		NSString *name = self.iconNames[indexPath.row];
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
	if (indexPath.section == 3) {
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
		return indexPath.section == 0 && indexPath.row < (NSInteger)self.folders.count;
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
			&& indexPath.row < (NSInteger)self.folders.count;
}

- (void)tableView:(UITableView *)tableView
		moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
	if (from.row >= (NSInteger)self.folders.count || to.section != 0)
		return;
	NSDictionary *folder = self.folders[from.row];
	[self.folders removeObjectAtIndex:from.row];
	NSInteger target = MIN(to.row, (NSInteger)self.folders.count);
	[self.folders insertObject:folder atIndex:target];
	[self commitOrder];
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from
	   toProposedIndexPath:(NSIndexPath *)proposed {
	if (proposed.section != 0)
		return [NSIndexPath indexPathForRow:self.folders.count - 1 inSection:0];
	return proposed;
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)style
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (style != UITableViewCellEditingStyleDelete)
		return;

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

	if (indexPath.row >= (NSInteger)self.folders.count)
		return;
	self.pendingDeleteIndex = indexPath.row;
	NSDictionary *folder = self.folders[indexPath.row];
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
		[strongSelf.tableView reloadData];
		if (strongSelf.folders.count == 0)
			[strongSelf showStatus:@"No folders yet.\nCreate one to group your chats."];
		[strongSelf reloadFoldersSoon];
	}];
	[alert show];
}

- (NSString *)tableView:(UITableView *)tableView
titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	return self.page == TGFoldersPageEditor ? @"Remove" : @"Delete";
}

@end

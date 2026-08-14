#import "TGProxyViewController.h"
#import "TGClient.h"
#import "TGClient+Network.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGActionSheet.h"
#import "TGAlertView.h"

#define TGProxyRGB(rgb) [UIColor colorWithRed:(((rgb) >> 16) & 0xff) / 255.0f \
									 green:(((rgb) >> 8) & 0xff) / 255.0f \
									  blue:((rgb) & 0xff) / 255.0f alpha:1.0f]

static CGFloat TGProxyRetinaPixel(void) {
	return [UIScreen mainScreen].scale > 1.0f ? 0.5f : 0.0f;
}

static NSString *TGProxyTypeTitle(NSString *type) {
	if ([type isEqualToString:@"mtproto"])
		return @"MTProto";
	if ([type isEqualToString:@"http"])
		return @"HTTP";
	return @"SOCKS5";
}

static NSString *TGProxyServerLine(NSDictionary *proxy) {
	NSString *server = [proxy[@"server"] isKindOfClass:[NSString class]]
			? proxy[@"server"] : @"";
	NSInteger port = [proxy[@"port"] integerValue];
	if (!server.length)
		return @"proxy";
	if (port <= 0)
		return server;
	return [NSString stringWithFormat:@"%@:%d", server, (int)port];
}

#pragma mark - the add / edit form

@interface TGProxyEditViewController : UITableViewController <UITextFieldDelegate>
@property (nonatomic, strong) NSDictionary *existing;
@property (nonatomic, copy) void (^onSaved)(void);
@property (nonatomic, strong) NSString *type;
@property (nonatomic, strong) UITextField *serverField;
@property (nonatomic, strong) UITextField *portField;
@property (nonatomic, strong) UITextField *secretField;
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, assign) BOOL saving;
@end

@implementation TGProxyEditViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self)
		self.type = @"mtproto";
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.existing ? @"Edit Proxy" : @"Add Proxy";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	UIButton *done = [TGIcons headerButtonWithTitle:@"Done" bold:YES
											 target:self action:@selector(save)];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:done];

	self.serverField = [self fieldWithPlaceholder:@"Server" text:self.existing[@"server"]];
	self.serverField.keyboardType = UIKeyboardTypeURL;
	self.serverField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.serverField.autocorrectionType = UITextAutocorrectionTypeNo;

	NSString *port = nil;
	if ([self.existing[@"port"] respondsToSelector:@selector(integerValue)]
			&& [self.existing[@"port"] integerValue] > 0)
		port = [NSString stringWithFormat:@"%d", (int)[self.existing[@"port"] integerValue]];
	self.portField = [self fieldWithPlaceholder:@"Port" text:port];
	self.portField.keyboardType = UIKeyboardTypeNumberPad;

	self.secretField = [self fieldWithPlaceholder:@"Secret" text:self.existing[@"secret"]];
	self.secretField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.secretField.autocorrectionType = UITextAutocorrectionTypeNo;

	self.usernameField = [self fieldWithPlaceholder:@"Username"
											   text:self.existing[@"username"]];
	self.usernameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.usernameField.autocorrectionType = UITextAutocorrectionTypeNo;

	self.passwordField = [self fieldWithPlaceholder:@"Password"
											   text:self.existing[@"password"]];
	self.passwordField.secureTextEntry = YES;

	NSString *existingType = self.existing[@"type"];
	if ([existingType isKindOfClass:[NSString class]] && existingType.length)
		self.type = existingType;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (!self.existing)
		[self.serverField becomeFirstResponder];
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(id)text {
	UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(15, 12, 290, 22)];
	field.placeholder = placeholder;
	field.text = [text isKindOfClass:[NSString class]] ? text : @"";
	field.font = [UIFont boldSystemFontOfSize:16];
	field.backgroundColor = [UIColor clearColor];
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	field.textColor = [[TGTheme shared] primaryTextColour];
	field.returnKeyType = UIReturnKeyDone;
	field.delegate = self;
	return field;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
	[field resignFirstResponder];
	return NO;
}

- (BOOL)isMtproto {
	return [self.type isEqualToString:@"mtproto"];
}

- (NSArray *)fields {
	NSMutableArray *fields = [NSMutableArray array];
	[fields addObject:self.serverField];
	[fields addObject:self.portField];
	if ([self isMtproto]){
		[fields addObject:self.secretField];
	} else {
		[fields addObject:self.usernameField];
		[fields addObject:self.passwordField];
	}
	return fields;
}

#pragma mark - captions

- (UIColor *)captionColour {
	return [[TGTheme shared] isDark] ? [[TGTheme shared] sectionHeaderColour]
									 : TGProxyRGB(0x697487);
}

- (UILabel *)captionLabel {
	UILabel *label = [[UILabel alloc] init];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont systemFontOfSize:14];
	label.numberOfLines = 0;
	label.textColor = [self captionColour];
	if (![[TGTheme shared] isFlat] && ![[TGTheme shared] isDark]){
		label.shadowColor = TGProxyRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	return label;
}

- (CGFloat)captionHeightFor:(NSString *)text width:(CGFloat)width {
	return [text sizeWithFont:[UIFont systemFontOfSize:14]
			constrainedToSize:CGSizeMake(width, 1000)
				lineBreakMode:NSLineBreakByWordWrapping].height;
}

- (NSString *)headerTitleForSection:(NSInteger)section {
	return section == 0 ? @"Proxy type" : @"Connection";
}

- (NSString *)footerTitleForSection:(NSInteger)section {
	if (section != 1)
		return nil;
	if ([self isMtproto])
		return @"An MTProto proxy needs the secret handed out with it. "
				"Paste the server, port and secret exactly as you received them.";
	return @"Leave the username and password empty if the SOCKS5 proxy does not ask for them.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	return [self captionHeightFor:title width:tableView.bounds.size.width - 42] + 18;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *title = [self headerTitleForSection:section];
	CGFloat width = tableView.bounds.size.width - 42;
	CGFloat height = [self captionHeightFor:title width:width];
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, tableView.bounds.size.width, height + 18)];
	container.backgroundColor = [UIColor clearColor];
	UILabel *label = [self captionLabel];
	label.text = title;
	label.frame = CGRectMake(21, 6 + TGProxyRetinaPixel(), width, height);
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
	label.text = title;
	label.frame = CGRectMake(21, 7 + TGProxyRetinaPixel(), width, height);
	[container addSubview:label];
	return container;
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return 2;
	return (NSInteger)[self fields].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 44;
}

- (UIView *)checkAccessory {
	UIImage *art = [UIImage imageNamed:@"ListCheck.png"];
	if (!art)
		return nil;
	UIImageView *view = [[UIImageView alloc] initWithImage:art
										 highlightedImage:
												 [UIImage imageNamed:@"ListCheck_Highlighted.png"]];
	view.frame = CGRectMake(0, 0, art.size.width, art.size.height);
	return view;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"type"];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:@"type"];
		[[TGTheme shared] styleCell:cell];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
		cell.textLabel.text = indexPath.row == 0 ? @"MTProto" : @"SOCKS5";
		BOOL chosen = (indexPath.row == 0) == [self isMtproto];
		UIView *check = chosen ? [self checkAccessory] : nil;
		if (chosen && !check)
			cell.accessoryType = UITableViewCellAccessoryCheckmark;
		else
			cell.accessoryType = UITableViewCellAccessoryNone;
		cell.accessoryView = check;
		return cell;
	}

	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
												  reuseIdentifier:nil];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	UITextField *field = [self fields][indexPath.row];
	field.frame = CGRectMake(15, 11, tableView.bounds.size.width - 50, 22);
	[cell.contentView addSubview:field];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 0)
		return;
	NSString *picked = indexPath.row == 0 ? @"mtproto" : @"socks5";
	if ([picked isEqualToString:self.type])
		return;
	[self.view endEditing:YES];
	self.type = picked;
	[tableView reloadData];
}

#pragma mark - saving

- (NSString *)trimmed:(UITextField *)field {
	return [field.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (void)complain:(NSString *)message field:(UITextField *)field {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Proxy" message:message
												   delegate:nil cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
	[field becomeFirstResponder];
}

- (NSDictionary *)proxyFromForm {
	NSString *server = [self trimmed:self.serverField];
	if (!server.length){
		[self complain:@"Please enter the proxy server." field:self.serverField];
		return nil;
	}
	NSInteger port = [[self trimmed:self.portField] integerValue];
	if (port <= 0 || port > 65535){
		[self complain:@"Please enter a port between 1 and 65535." field:self.portField];
		return nil;
	}

	NSMutableDictionary *proxy = [NSMutableDictionary dictionary];
	proxy[@"server"] = server;
	proxy[@"port"] = [NSNumber numberWithInteger:port];
	proxy[@"type"] = self.type;

	if ([self isMtproto]){
		NSString *secret = [self trimmed:self.secretField];
		if (!secret.length){
			[self complain:@"An MTProto proxy needs a secret." field:self.secretField];
			return nil;
		}
		proxy[@"secret"] = secret;
	} else {
		NSString *username = [self trimmed:self.usernameField];
		NSString *password = self.passwordField.text ?: @"";
		if (username.length)
			proxy[@"username"] = username;
		if (password.length)
			proxy[@"password"] = password;
	}
	return proxy;
}

- (void)save {
	if (self.saving)
		return;
	[self.view endEditing:YES];

	NSDictionary *proxy = [self proxyFromForm];
	if (!proxy)
		return;

	self.saving = YES;
	self.navigationItem.rightBarButtonItem.customView.userInteractionEnabled = NO;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] testProxy:proxy dcId:0 timeout:10 completion:^(BOOL reachable){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (reachable){
			[strongSelf storeProxy:proxy];
			return;
		}
		strongSelf.saving = NO;
		strongSelf.navigationItem.rightBarButtonItem.customView.userInteractionEnabled = YES;
		TGAlertView *alert = [[TGAlertView alloc]
				initWithTitle:@"Proxy"
					  message:@"This proxy did not answer. Save it anyway?"
			cancelButtonTitle:@"Cancel" okButtonTitle:@"Save"
			  completionBlock:^(bool okPressed){
				  __strong typeof(weakSelf) inner = weakSelf;
				  if (inner && okPressed){
					  inner.saving = YES;
					  [inner storeProxy:proxy];
				  }
			  }];
		[alert show];
	}];
}

- (void)storeProxy:(NSDictionary *)proxy {
	__weak typeof(self) weakSelf = self;
	void (^done)(NSDictionary *) = ^(NSDictionary *stored){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.saving = NO;
		strongSelf.navigationItem.rightBarButtonItem.customView.userInteractionEnabled = YES;
		if (!stored){
			UIAlertView *alert = [[UIAlertView alloc]
					initWithTitle:@"Proxy"
						  message:@"Telegram would not accept these settings."
						 delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
			return;
		}
		if (strongSelf.onSaved)
			strongSelf.onSaved();
		[strongSelf.navigationController popViewControllerAnimated:YES];
	};

	NSInteger existingId = [self.existing[@"id"] integerValue];
	if (self.existing && existingId > 0)
		[[TGClient shared] editProxy:existingId to:proxy enable:YES completion:done];
	else
		[[TGClient shared] addProxy:proxy enable:YES completion:done];
}

@end

#pragma mark - the list

@interface TGProxyViewController ()
@property (nonatomic, strong) NSArray *proxies;
@property (nonatomic, strong) NSMutableDictionary *pings;
@property (nonatomic, strong) NSNumber *directPing;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL pinging;
@property (nonatomic, strong) NSTimer *statusTimer;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, assign) NSInteger pendingProxyId;
@end

@implementation TGProxyViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		self.proxies = [NSArray array];
		self.pings = [NSMutableDictionary dictionary];
		self.pendingProxyId = 0;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Proxy";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(handleHold:)];
	hold.minimumPressDuration = 0.5;
	[self.tableView addGestureRecognizer:hold];

	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self.tableView reloadData];
	self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self
				selector:@selector(refreshStatus) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.statusTimer invalidate];
	self.statusTimer = nil;
	if (self.currentActionSheet){
		[self.currentActionSheet dismissWithClickedButtonIndex:
				self.currentActionSheet.cancelButtonIndex animated:NO];
		self.currentActionSheet = nil;
	}
}

- (void)dealloc {
	[_statusTimer invalidate];
}

#pragma mark - data

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] proxiesWithCompletion:^(NSArray *proxies){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.loaded = YES;
		strongSelf.proxies = proxies ?: [NSArray array];
		[strongSelf.tableView reloadData];
		[strongSelf measurePings];
	}];
}

- (void)measurePings {
	if (self.pinging)
		return;
	self.pinging = YES;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] pingProxy:nil completion:^(double seconds){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.directPing = [NSNumber numberWithDouble:seconds];
		[strongSelf.tableView reloadData];
	}];

	if (!self.proxies.count){
		self.pinging = NO;
		return;
	}

	[[TGClient shared] pingAllProxiesWithCompletion:^(NSDictionary *secondsByProxyId){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		strongSelf.pinging = NO;
		if ([secondsByProxyId isKindOfClass:[NSDictionary class]])
			[strongSelf.pings addEntriesFromDictionary:secondsByProxyId];
		[strongSelf.tableView reloadData];
	}];
}

- (NSDictionary *)enabledProxy {
	for (NSDictionary *proxy in self.proxies)
		if ([proxy[@"isEnabled"] boolValue])
			return proxy;
	return nil;
}

- (NSDictionary *)proxyAtRow:(NSInteger)row {
	NSInteger index = row - 1;
	if (index < 0 || index >= (NSInteger)self.proxies.count)
		return nil;
	return self.proxies[index];
}

- (NSString *)pingTextForProxy:(NSDictionary *)proxy {
	id key = proxy[@"id"];
	NSNumber *seconds = proxy ? (key ? self.pings[key] : nil) : self.directPing;
	if (![seconds isKindOfClass:[NSNumber class]])
		seconds = nil;
	if (!seconds)
		return self.pinging ? @"checking..." : nil;
	double value = [seconds doubleValue];
	if (value < 0)
		return @"unavailable";
	return [NSString stringWithFormat:@"%d ms", (int)(value * 1000.0 + 0.5)];
}

- (NSString *)statusText {
	NSString *title = [[TGClient shared] connectionStateTitle];
	if (title.length)
		return title;
	return @"Connected";
}

- (NSString *)statusDetail {
	NSDictionary *enabled = [self enabledProxy];
	if (!enabled)
		return @"Direct";
	return [NSString stringWithFormat:@"%@ - %@",
			TGProxyTypeTitle(enabled[@"type"]), TGProxyServerLine(enabled)];
}

- (void)refreshStatus {
	if (!self.isViewLoaded || !self.view.window)
		return;
	NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
	if (!cell)
		return;
	cell.textLabel.text = [self statusText];
	cell.detailTextLabel.text = [self statusDetail];
	[cell setNeedsLayout];
}

#pragma mark - captions

- (UIColor *)captionColour {
	return [[TGTheme shared] isDark] ? [[TGTheme shared] sectionHeaderColour]
									 : TGProxyRGB(0x697487);
}

- (UILabel *)captionLabel {
	UILabel *label = [[UILabel alloc] init];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont systemFontOfSize:14];
	label.numberOfLines = 0;
	label.textColor = [self captionColour];
	if (![[TGTheme shared] isFlat] && ![[TGTheme shared] isDark]){
		label.shadowColor = TGProxyRGB(0xdae0e8);
		label.shadowOffset = CGSizeMake(0, 1);
	}
	return label;
}

- (CGFloat)captionHeightFor:(NSString *)text width:(CGFloat)width {
	return [text sizeWithFont:[UIFont systemFontOfSize:14]
			constrainedToSize:CGSizeMake(width, 1000)
				lineBreakMode:NSLineBreakByWordWrapping].height;
}

- (NSString *)headerTitleForSection:(NSInteger)section {
	if (section == 0)
		return @"Connection";
	if (section == 1)
		return @"Proxies";
	return nil;
}

- (NSString *)footerTitleForSection:(NSInteger)section {
	if (section != 1)
		return nil;
	if (!self.loaded)
		return @"Loading...";
	if (!self.proxies.count)
		return @"You have no proxies set up. Add one to reach Telegram from a "
				"network that blocks it.";
	return @"Tap a proxy to connect through it. Touch and hold one to edit, share "
			"or delete it.";
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
	label.text = title;
	label.frame = CGRectMake(21, 6 + TGProxyRetinaPixel(), width, height);
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
	label.text = title;
	label.frame = CGRectMake(21, 7 + TGProxyRetinaPixel(), width, height);
	[container addSubview:label];
	return container;
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return 1;
	if (section == 1)
		return 1 + (NSInteger)self.proxies.count;
	return self.proxies.count > 1 ? 2 : 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 1 && indexPath.row > 0 ? 52 : 44;
}

- (UIView *)checkAccessory {
	UIImage *art = [UIImage imageNamed:@"ListCheck.png"];
	if (!art)
		return nil;
	UIImageView *view = [[UIImageView alloc] initWithImage:art
										 highlightedImage:
												 [UIImage imageNamed:@"ListCheck_Highlighted.png"]];
	view.frame = CGRectMake(0, 0, art.size.width, art.size.height);
	return view;
}

- (void)mark:(BOOL)checked on:(UITableViewCell *)cell {
	UIView *check = checked ? [self checkAccessory] : nil;
	if (checked && !check){
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
		cell.accessoryView = nil;
		return;
	}
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = check;
}

- (UITableViewCell *)statusCellForTable:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"status"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"status"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:16];
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	cell.textLabel.text = [self statusText];
	cell.detailTextLabel.text = [self statusDetail];
	return cell;
}

- (UITableViewCell *)actionCellForTable:(UITableView *)tableView title:(NSString *)title {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"action"];
	[[TGTheme shared] styleCell:cell];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] isFlat]
			? [[TGTheme shared] accentColour] : TGProxyRGB(0x0779d0);
	cell.textLabel.text = title;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0)
		return [self statusCellForTable:tableView];

	if (indexPath.section == 2){
		NSString *title = indexPath.row == 0 ? @"Add Proxy" : @"Use Fastest Proxy";
		return [self actionCellForTable:tableView title:title];
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"proxy"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"proxy"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
	cell.detailTextLabel.textColor = [[TGTheme shared] isDark]
			? [[TGTheme shared] secondaryTextColour] : TGProxyRGB(0x888888);

	NSDictionary *proxy = [self proxyAtRow:indexPath.row];
	if (!proxy){
		cell.textLabel.text = @"Without Proxy";
		NSString *ping = [self pingTextForProxy:nil];
		cell.detailTextLabel.text = ping.length
				? [NSString stringWithFormat:@"Direct connection - %@", ping]
				: @"Direct connection";
		[self mark:[self enabledProxy] == nil on:cell];
		return cell;
	}

	cell.textLabel.text = TGProxyServerLine(proxy);
	NSString *ping = [self pingTextForProxy:proxy];
	cell.detailTextLabel.text = ping.length
			? [NSString stringWithFormat:@"%@ - %@", TGProxyTypeTitle(proxy[@"type"]), ping]
			: TGProxyTypeTitle(proxy[@"type"]);
	[self mark:[proxy[@"isEnabled"] boolValue] on:cell];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 2){
		if (indexPath.row == 0)
			[self presentFormForProxy:nil];
		else
			[self useFastest];
		return;
	}
	if (indexPath.section != 1)
		return;

	NSDictionary *proxy = [self proxyAtRow:indexPath.row];
	if (!proxy){
		[self disable];
		return;
	}
	[self enableProxy:proxy];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 1 && [self proxyAtRow:indexPath.row] != nil;
}

- (NSString *)tableView:(UITableView *)tableView
		titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	return @"Delete";
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;
	[self deleteProxy:[self proxyAtRow:indexPath.row]];
}

#pragma mark - actions

- (void)enableProxy:(NSDictionary *)proxy {
	NSInteger proxyId = [proxy[@"id"] integerValue];
	if (proxyId <= 0)
		return;

	NSMutableArray *updated = [NSMutableArray array];
	for (NSDictionary *candidate in self.proxies){
		NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithDictionary:candidate];
		copy[@"isEnabled"] = [NSNumber numberWithBool:
				[candidate[@"id"] integerValue] == proxyId];
		[updated addObject:copy];
	}
	self.proxies = updated;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] enableProxy:proxyId completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (!ok){
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Proxy"
					message:@"Could not switch to that proxy."
					delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
		}
		[strongSelf reload];
	}];
}

- (void)disable {
	NSMutableArray *updated = [NSMutableArray array];
	for (NSDictionary *candidate in self.proxies){
		NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithDictionary:candidate];
		copy[@"isEnabled"] = [NSNumber numberWithBool:NO];
		[updated addObject:copy];
	}
	self.proxies = updated;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] disableProxyWithCompletion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		[strongSelf reload];
	}];
}

- (void)deleteProxy:(NSDictionary *)proxy {
	NSInteger proxyId = [proxy[@"id"] integerValue];
	if (proxyId <= 0)
		return;

	NSMutableArray *remaining = [NSMutableArray arrayWithArray:self.proxies];
	[remaining removeObject:proxy];
	self.proxies = remaining;
	if (proxy[@"id"])
		[self.pings removeObjectForKey:proxy[@"id"]];
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] removeProxy:proxyId completion:^(BOOL ok){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		[strongSelf reload];
	}];
}

- (void)useFastest {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] selectFastestProxyWithCompletion:^(NSDictionary *proxy){
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		if (!proxy){
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Proxy"
					message:@"None of your proxies answered."
					delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
		}
		[strongSelf reload];
	}];
}

- (void)shareLinkForProxy:(NSDictionary *)proxy {
	[[TGClient shared] proxyLinkFor:proxy completion:^(NSString *link){
		if (!link.length){
			UIAlertView *failed = [[UIAlertView alloc] initWithTitle:@"Proxy"
					message:@"Could not build a link for that proxy."
					delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[failed show];
			return;
		}
		[UIPasteboard generalPasteboard].string = link;
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Link copied"
				message:link delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}];
}

- (void)presentFormForProxy:(NSDictionary *)proxy {
	TGProxyEditViewController *form = [[TGProxyEditViewController alloc] init];
	form.existing = proxy;
	__weak typeof(self) weakSelf = self;
	form.onSaved = ^{
		__strong typeof(weakSelf) strongSelf = weakSelf;
		[strongSelf reload];
	};
	[self.navigationController pushViewController:form animated:YES];
}

#pragma mark - the per-proxy sheet

- (UIView *)sheetHostView {
	return self.navigationController.view ?: self.view;
}

- (void)handleHold:(UILongPressGestureRecognizer *)recogniser {
	if (recogniser.state != UIGestureRecognizerStateBegan)
		return;
	CGPoint point = [recogniser locationInView:self.tableView];
	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:point];
	if (!path || path.section != 1)
		return;
	NSDictionary *proxy = [self proxyAtRow:path.row];
	if (proxy)
		[self showSheetForProxy:proxy];
}

- (void)showSheetForProxy:(NSDictionary *)proxy {
	self.pendingProxyId = [proxy[@"id"] integerValue];

	NSMutableArray *actions = [NSMutableArray array];
	if (![proxy[@"isEnabled"] boolValue])
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Use This Proxy"
															   action:@"use"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Edit" action:@"edit"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Copy Link"
														   action:@"link"]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Delete"
														   action:@"delete"
															 type:TGActionSheetActionTypeDestructive]];
	[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Cancel"
														   action:@"cancel"
															 type:TGActionSheetActionTypeCancel]];

	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:TGProxyServerLine(proxy)
			actions:actions
			actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				if (!strongSelf)
					return;
				strongSelf.currentActionSheet = nil;
				NSDictionary *current = [strongSelf proxyWithId:strongSelf.pendingProxyId];
				strongSelf.pendingProxyId = 0;
				if (!current)
					return;
				if ([action isEqualToString:@"use"])
					[strongSelf enableProxy:current];
				else if ([action isEqualToString:@"edit"])
					[strongSelf presentFormForProxy:current];
				else if ([action isEqualToString:@"link"])
					[strongSelf shareLinkForProxy:current];
				else if ([action isEqualToString:@"delete"])
					[strongSelf deleteProxy:current];
			} target:self];
	[self.currentActionSheet showInView:[self sheetHostView]];
}

- (NSDictionary *)proxyWithId:(NSInteger)proxyId {
	if (proxyId <= 0)
		return nil;
	for (NSDictionary *proxy in self.proxies)
		if ([proxy[@"id"] integerValue] == proxyId)
			return proxy;
	return nil;
}

@end

// vim:ft=objc

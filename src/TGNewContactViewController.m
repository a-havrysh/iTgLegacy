#import "TGNewContactViewController.h"
#import "TGQRViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <AddressBook/AddressBook.h>

static UIColor *TGNewContactColour(int rgb, CGFloat alpha) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:alpha];
}

static void TGNewContactApplyMinimumWidth(UIButton *button, CGFloat minimumWidth) {
	if (!button || button.frame.size.width >= minimumWidth)
		return;
	CGRect frame = button.frame;
	frame.size.width = minimumWidth;
	button.frame = frame;
	for (UIView *sub in button.subviews){
		CGRect subFrame = sub.frame;
		subFrame.origin.x = 0;
		subFrame.size.width = minimumWidth;
		sub.frame = subFrame;
	}
}

static UIImage *TGNewContactStretchedImage(NSString *name) {
	UIImage *raw = [UIImage imageNamed:name];
	if (!raw)
		return nil;
	return [raw stretchableImageWithLeftCapWidth:(int)(raw.size.width / 2) topCapHeight:0];
}

@interface TGPhoneLabelCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleView;
@property (nonatomic, strong) UIImageView *checkIndicator;
- (void)setHideCheckIndicator:(BOOL)hide;
@end

@implementation TGPhoneLabelCell

- (id)initWithReuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;
	self.titleView = [[UILabel alloc] initWithFrame:CGRectMake(11, 12, self.contentView.bounds.size.width - 30, 20)];
	self.titleView.contentMode = UIViewContentModeLeft;
	self.titleView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.titleView.font = [UIFont boldSystemFontOfSize:17];
	self.titleView.backgroundColor = [UIColor clearColor];
	self.titleView.textColor = [UIColor blackColor];
	self.titleView.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:self.titleView];
	return self;
}

- (void)setHideCheckIndicator:(BOOL)hide {
	if (hide){
		self.checkIndicator.hidden = YES;
		self.titleView.textColor = [[TGTheme shared] isDarkStyle]
			? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
		return;
	}
	if (!self.checkIndicator){
		UIImage *check = [UIImage imageNamed:@"ListCheck.png"];
		if (check){
			self.checkIndicator = [[UIImageView alloc] initWithImage:check
												   highlightedImage:[UIImage imageNamed:@"ListCheck_Highlighted.png"]];
			self.checkIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
			self.checkIndicator.frame = CGRectMake(self.contentView.bounds.size.width - check.size.width - 9, 14,
												   check.size.width, check.size.height);
			[self.contentView addSubview:self.checkIndicator];
		}
	} else {
		self.checkIndicator.hidden = NO;
	}
	self.titleView.textColor = TGNewContactColour(0x516691, 1.0f);
	if (!self.checkIndicator)
		self.accessoryType = UITableViewCellAccessoryCheckmark;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	self.titleView.frame = CGRectMake(11, 12, self.contentView.bounds.size.width - 30, 20);
	if (self.checkIndicator){
		CGSize size = self.checkIndicator.image.size;
		self.checkIndicator.frame = CGRectMake(self.contentView.bounds.size.width - size.width - 9, 14,
											   size.width, size.height);
	}
}

@end

@interface TGPhoneLabelPickerController : UITableViewController
@property (nonatomic, strong) NSArray *labels;
@property (nonatomic, copy) NSString *selectedLabel;
@property (nonatomic, copy) void (^onPick)(NSString *label);
@property (nonatomic, copy) void (^onCancel)(void);
@end

@implementation TGPhoneLabelPickerController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (!self)
		return nil;
	self.title = @"Label";
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.rowHeight = 44.0f;

	UIButton *cancel = [TGIcons headerButtonWithTitle:@"Cancel" bold:NO
											   target:self action:@selector(cancelPressed)];
	TGNewContactApplyMinimumWidth(cancel, 59.0f);
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:cancel];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	NSUInteger index = self.selectedLabel ? [self.labels indexOfObject:self.selectedLabel] : NSNotFound;
	if (index != NSNotFound){
		[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]
							  atScrollPosition:UITableViewScrollPositionNone animated:NO];
	}
}

- (void)cancelPressed {
	if (self.onCancel)
		self.onCancel();
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.labels.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGPhoneLabelRow";
	TGPhoneLabelCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGPhoneLabelCell alloc] initWithReuseIdentifier:reuse];
	NSString *label = [self.labels objectAtIndex:(NSUInteger)indexPath.row];
	cell.titleView.text = label;
	cell.accessoryType = UITableViewCellAccessoryNone;
	[cell setHideCheckIndicator:![label isEqualToString:self.selectedLabel]];
	cell.backgroundColor = [UIColor clearColor];
	if ([[TGTheme shared] isDarkStyle])
		[[TGTheme shared] styleCell:cell];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString *label = [self.labels objectAtIndex:(NSUInteger)indexPath.row];
	if (self.onPick)
		self.onPick(label);
}

@end

@interface TGNewContactPhoneCell : UITableViewCell
@property (nonatomic, strong) UILabel *labelView;
@property (nonatomic, strong) UIImageView *verticalSeparator;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, assign) BOOL lastInGroup;
@end

@implementation TGNewContactPhoneCell

- (id)initWithReuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.labelView = [[UILabel alloc] initWithFrame:CGRectMake(4, 13, 62, 16)];
	self.labelView.textAlignment = NSTextAlignmentRight;
	self.labelView.font = [UIFont boldSystemFontOfSize:13];
	self.labelView.backgroundColor = [[TGTheme shared] isDarkStyle] ? [UIColor clearColor] : [UIColor whiteColor];
	self.labelView.textColor = TGNewContactColour(0x5d708f, 1.0f);
	self.labelView.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:self.labelView];

	UIImage *line = [UIImage imageNamed:@"GroupedCellVerticalSeparator.png"];
	if (line){
		self.verticalSeparator = [[UIImageView alloc] initWithImage:line
												   highlightedImage:[UIImage imageNamed:@"GroupedCellVerticalSeparator_Highlighted.png"]];
	} else {
		self.verticalSeparator = [[UIImageView alloc] initWithFrame:CGRectZero];
		self.verticalSeparator.backgroundColor = [[TGTheme shared] separatorColour];
	}
	[self.contentView addSubview:self.verticalSeparator];
	return self;
}

- (void)setField:(UITextField *)field {
	if (_field == field)
		return;
	if (_field.superview == self.contentView)
		[_field removeFromSuperview];
	_field = field;
	if (field)
		[self.contentView addSubview:field];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect bounds = self.contentView.bounds;
	self.labelView.frame = CGRectMake(4, 13, 62, 16);
	CGFloat lineHeight = bounds.size.height - (self.lastInGroup ? 1.0f : 0.0f);
	self.verticalSeparator.frame = CGRectMake(72, 0, 1.0f, lineHeight);
	self.field.font = [UIFont boldSystemFontOfSize:15];
	self.field.frame = CGRectMake(78, 11, bounds.size.width - 80, 20);
}

@end

@interface TGNewContactViewController () <UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UITextField *firstNameField;
@property (nonatomic, strong) UITextField *lastNameField;
@property (nonatomic, strong) NSMutableArray *phoneEntries;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, strong) UIButton *addPhotoButton;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIImage *avatarImage;
@property (nonatomic, strong) UIView *editNameContainer;
@property (nonatomic, assign) BOOL saving;
@end

@implementation TGNewContactViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (!self)
		return nil;
	self.phoneEntries = [[NSMutableArray alloc] init];
	return self;
}

- (NSArray *)phoneLabels {
	static NSArray *labels = nil;
	if (!labels){
		NSMutableArray *result = [[NSMutableArray alloc] init];
		CFStringRef raw[] = { kABPersonPhoneMobileLabel, kABHomeLabel, kABWorkLabel,
							  kABPersonPhoneMainLabel, kABPersonPhoneHomeFAXLabel,
							  kABPersonPhoneWorkFAXLabel, kABPersonPhonePagerLabel, kABOtherLabel };
		for (NSUInteger i = 0; i < sizeof(raw) / sizeof(raw[0]); i++){
			NSString *localized = (__bridge_transfer NSString *)ABAddressBookCopyLocalizedLabel(raw[i]);
			if (localized.length && ![result containsObject:localized])
				[result addObject:localized];
		}
		if (!result.count)
			[result addObject:@"mobile"];
		labels = result;
	}
	return labels;
}

- (NSString *)nextUnusedLabel {
	for (NSString *label in [self phoneLabels]){
		BOOL used = NO;
		for (NSMutableDictionary *entry in self.phoneEntries){
			if ([[entry objectForKey:@"label"] isEqualToString:label]){
				used = YES;
				break;
			}
		}
		if (!used)
			return label;
	}
	return @"mobile";
}

- (NSMutableDictionary *)makePhoneEntry {
	UITextField *field = [self makeFieldWithPlaceholder:@"Phone" font:[UIFont boldSystemFontOfSize:15]];
	field.keyboardType = UIKeyboardTypePhonePad;
	NSMutableDictionary *entry = [[NSMutableDictionary alloc] init];
	[entry setObject:[self nextUnusedLabel] forKey:@"label"];
	[entry setObject:field forKey:@"field"];
	return entry;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.title = @"New Contact";
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.rowHeight = 44.0f;
	self.tableView.sectionFooterHeight = 0.0f;
	self.tableView.allowsSelectionDuringEditing = YES;

	UIButton *cancel = [TGIcons headerButtonWithTitle:@"Cancel" bold:NO
												target:self action:@selector(cancelTapped)];
	TGNewContactApplyMinimumWidth(cancel, 59.0f);
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:cancel];

	self.doneButton = [TGIcons headerButtonWithTitle:@"Done" bold:YES
											  target:self action:@selector(doneTapped)];
	TGNewContactApplyMinimumWidth(self.doneButton, 51.0f);
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.doneButton];

	self.firstNameField = [self makeFieldWithPlaceholder:@"First" font:[UIFont boldSystemFontOfSize:16]];
	self.firstNameField.returnKeyType = UIReturnKeyNext;
	self.lastNameField  = [self makeFieldWithPlaceholder:@"Last" font:[UIFont boldSystemFontOfSize:16]];
	self.lastNameField.returnKeyType = UIReturnKeyDefault;

	for (int i = 0; i < 2; i++)
		[self.phoneEntries addObject:[self makePhoneEntry]];

	[self buildTableHeader];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textChanged:)
												 name:UITextFieldTextDidChangeNotification object:nil];
	[self.tableView setEditing:YES animated:NO];
	[self updateDoneEnabled];
}

- (void)buildTableHeader {
	CGFloat width = self.view.bounds.size.width > 0 ? self.view.bounds.size.width : 320.0f;
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 86)];
	header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	header.backgroundColor = [UIColor clearColor];
	header.clipsToBounds = NO;

	self.addPhotoButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.addPhotoButton.frame = CGRectMake(9, 14, 70, 70);
	self.addPhotoButton.exclusiveTouch = YES;
	UIImage *placeholder = TGNewContactStretchedImage(@"ProfilePhotoPlaceholder.png");
	UIImage *placeholderPressed = TGNewContactStretchedImage(@"ProfilePhotoPlaceholder_Highlighted.png");
	if (placeholder){
		[self.addPhotoButton setBackgroundImage:placeholder forState:UIControlStateNormal];
		if (placeholderPressed)
			[self.addPhotoButton setBackgroundImage:placeholderPressed forState:UIControlStateHighlighted];
	} else {
		[self.addPhotoButton setBackgroundImage:[self drawnPlaceholderOfSide:70 colour:TGNewContactColour(0x9aa7b6, 1.0f)]
									   forState:UIControlStateNormal];
		[self.addPhotoButton setBackgroundImage:[self drawnPlaceholderOfSide:70 colour:TGNewContactColour(0x7f8d9d, 1.0f)]
									   forState:UIControlStateHighlighted];
	}
	[self.addPhotoButton addTarget:self action:@selector(addPhotoPressed) forControlEvents:UIControlEventTouchUpInside];
	[header addSubview:self.addPhotoButton];

	CGFloat retinaPixel = ([UIScreen mainScreen].scale > 1.0f) ? 0.5f : 0.0f;
	UILabel *addLabel = [[UILabel alloc] init];
	addLabel.text = @"add";
	addLabel.font = [UIFont boldSystemFontOfSize:14 + retinaPixel];
	addLabel.backgroundColor = [UIColor clearColor];
	addLabel.textColor = [UIColor whiteColor];
	addLabel.shadowColor = TGNewContactColour(0x47586c, 0.5f);
	addLabel.shadowOffset = CGSizeMake(0, -1);
	[addLabel sizeToFit];
	addLabel.frame = CGRectIntegral(CGRectMake((70 - addLabel.frame.size.width) / 2, 16 + retinaPixel,
											   addLabel.frame.size.width, addLabel.frame.size.height));
	[self.addPhotoButton addSubview:addLabel];

	UILabel *photoLabel = [[UILabel alloc] init];
	photoLabel.text = @"photo";
	photoLabel.font = [UIFont boldSystemFontOfSize:14 + retinaPixel];
	photoLabel.backgroundColor = [UIColor clearColor];
	photoLabel.textColor = [UIColor whiteColor];
	photoLabel.shadowColor = TGNewContactColour(0x47586c, 0.5f);
	photoLabel.shadowOffset = CGSizeMake(0, -1);
	[photoLabel sizeToFit];
	photoLabel.frame = CGRectIntegral(CGRectMake((70 - photoLabel.frame.size.width) / 2, 33,
												 photoLabel.frame.size.width, photoLabel.frame.size.height));
	[self.addPhotoButton addSubview:photoLabel];

	self.avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(9, 14, 70, 70)];
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.hidden = YES;
	self.avatarView.userInteractionEnabled = NO;
	[header addSubview:self.avatarView];

	self.editNameContainer = [[UIView alloc] initWithFrame:CGRectMake(90, 14, width - 90 - 9, 88)];
	self.editNameContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.editNameContainer.backgroundColor = [UIColor clearColor];

	UIView *firstBackground = [self groupedNameBackgroundOfWidth:self.editNameContainer.frame.size.width
															 top:YES];
	firstBackground.frame = CGRectMake(0, 0, self.editNameContainer.frame.size.width, 44);
	firstBackground.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	firstBackground.userInteractionEnabled = YES;
	[firstBackground addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
																				  action:@selector(focusOnFirstNameField)]];
	[self.editNameContainer addSubview:firstBackground];

	UIView *lastBackground = [self groupedNameBackgroundOfWidth:self.editNameContainer.frame.size.width
															top:NO];
	lastBackground.frame = CGRectMake(0, 44, self.editNameContainer.frame.size.width, 44);
	lastBackground.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	lastBackground.userInteractionEnabled = YES;
	[lastBackground addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
																				 action:@selector(focusOnLastNameField)]];
	[self.editNameContainer addSubview:lastBackground];

	self.firstNameField.frame = CGRectMake(15, 12, self.editNameContainer.frame.size.width - 20, 22);
	self.firstNameField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.editNameContainer addSubview:self.firstNameField];

	self.lastNameField.frame = CGRectMake(15, 44 + 11, self.editNameContainer.frame.size.width - 20, 22);
	self.lastNameField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.editNameContainer addSubview:self.lastNameField];

	[header addSubview:self.editNameContainer];
	self.tableView.tableHeaderView = header;
}

- (UIImage *)drawnPlaceholderOfSide:(CGFloat)side colour:(UIColor *)colour {
	CGSize size = CGSizeMake(side, side);
	if (UIGraphicsBeginImageContextWithOptions != NULL)
		UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
	else
		UIGraphicsBeginImageContext(size);
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:4.0f];
	[colour setFill];
	[path fill];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

- (UIView *)groupedNameBackgroundOfWidth:(CGFloat)width top:(BOOL)top {
	UIImage *art = [UIImage imageNamed:top ? @"GroupedCellTop.png" : @"GroupedCellBottom.png"];
	if (art){
		UIImageView *view = [[UIImageView alloc] initWithImage:[art stretchableImageWithLeftCapWidth:(int)(art.size.width / 2)
																					   topCapHeight:0]];
		return view;
	}
	UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 44)];
	view.backgroundColor = [UIColor whiteColor];
	UIView *hairline = [[UIView alloc] initWithFrame:CGRectMake(0, top ? 43 : 0, width, 1)];
	hairline.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	hairline.backgroundColor = [[TGTheme shared] separatorColour];
	[view addSubview:hairline];
	return view;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	self.firstNameField.delegate = nil;
	self.lastNameField.delegate = nil;
	for (NSMutableDictionary *entry in self.phoneEntries)
		((UITextField *)[entry objectForKey:@"field"]).delegate = nil;
}

- (void)focusOnFirstNameField {
	[self.firstNameField becomeFirstResponder];
}

- (void)focusOnLastNameField {
	[self.lastNameField becomeFirstResponder];
}

- (NSMutableDictionary *)entryForField:(UITextField *)field {
	for (NSMutableDictionary *entry in self.phoneEntries){
		if ([entry objectForKey:@"field"] == field)
			return entry;
	}
	return nil;
}

- (void)textChanged:(NSNotification *)note {
	id object = note.object;
	if (object == self.firstNameField || object == self.lastNameField){
		[self updateDoneEnabled];
		return;
	}
	if ([self entryForField:object]){
		[self appendEmptyPhoneRowIfNeeded];
		[self updateDoneEnabled];
	}
}

- (void)appendEmptyPhoneRowIfNeeded {
	NSMutableDictionary *last = [self.phoneEntries lastObject];
	UITextField *lastField = [last objectForKey:@"field"];
	if (!lastField.text.length)
		return;
	[self.phoneEntries addObject:[self makePhoneEntry]];
	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)self.phoneEntries.count - 1 inSection:0];
	[self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
						  withRowAnimation:UITableViewRowAnimationFade];
	id previousCell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:indexPath.row - 1 inSection:0]];
	if ([previousCell isKindOfClass:[TGNewContactPhoneCell class]]){
		((TGNewContactPhoneCell *)previousCell).lastInGroup = NO;
		[previousCell setNeedsLayout];
	}
}

- (NSString *)trimmed:(NSString *)text {
	if (!text.length)
		return @"";
	return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSArray *)enteredPhones {
	NSMutableArray *result = [[NSMutableArray alloc] init];
	for (NSMutableDictionary *entry in self.phoneEntries){
		NSString *phone = [self trimmed:((UITextField *)[entry objectForKey:@"field"]).text];
		if (phone.length){
			NSMutableDictionary *item = [[NSMutableDictionary alloc] init];
			[item setObject:phone forKey:@"phone"];
			[item setObject:[entry objectForKey:@"label"] forKey:@"label"];
			[result addObject:item];
		}
	}
	return result;
}

- (BOOL)isFormValid {
	if (![self enteredPhones].count)
		return NO;
	return [self trimmed:self.firstNameField.text].length || [self trimmed:self.lastNameField.text].length;
}

- (void)updateDoneEnabled {
	BOOL enabled = !self.saving && [self isFormValid];
	self.doneButton.enabled = enabled;
	self.doneButton.alpha = 1.0f;
	for (UIView *sub in self.doneButton.subviews){
		if ([sub isKindOfClass:[UILabel class]])
			sub.alpha = enabled ? 1.0f : 0.6f;
	}
}

- (UITextField *)makeFieldWithPlaceholder:(NSString *)placeholder font:(UIFont *)font {
	UITextField *field = [[UITextField alloc] init];
	field.placeholder = placeholder;
	field.font = font;
	if ([field respondsToSelector:@selector(setAttributedPlaceholder:)]){
		UIColor *placeholderColour = TGNewContactColour(0xb3b3b3, 1.0f);
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
									placeholderColour, NSForegroundColorAttributeName,
									font, NSFontAttributeName, nil];
		field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:attributes];
	}
	field.textColor = [[TGTheme shared] isDarkStyle] ? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
	field.backgroundColor = [UIColor clearColor];
	field.contentMode = UIViewContentModeLeft;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.delegate = self;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	return field;
}

- (void)closeSelf {
	[self.view endEditing:YES];
	if (self.navigationController.viewControllers.count > 1)
		[self.navigationController popViewControllerAnimated:YES];
	else
		[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancelTapped {
	[self closeSelf];
}

- (void)doneTapped {
	if (self.saving || ![self isFormValid])
		return;

	NSString *first = [self trimmed:self.firstNameField.text];
	NSString *last  = [self trimmed:self.lastNameField.text];
	NSArray *phones = [self enteredPhones];
	NSString *primaryPhone = [[phones objectAtIndex:0] objectForKey:@"phone"];

	self.saving = YES;
	[self updateDoneEnabled];
	[self.view endEditing:YES];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] addContactWithPhone:primaryPhone firstName:first lastName:last
								 completion:^(BOOL ok){
		dispatch_block_t finish = ^{
		TGNewContactViewController *me = weakSelf;
		if (!me)
			return;
		me.saving = NO;
		[me updateDoneEnabled];
		if (!ok)
			return;
		[me saveToAddressBookFirst:first last:last phones:phones];
		if (me.onDone)
			me.onDone();
		[me closeSelf];
		};
		if ([NSThread isMainThread])
			finish();
		else
			dispatch_async(dispatch_get_main_queue(), finish);
	}];
}

- (void)saveToAddressBookFirst:(NSString *)first last:(NSString *)last phones:(NSArray *)phones {
	ABAddressBookRef book = ABAddressBookCreateWithOptions(NULL, NULL);
	if (!book)
		return;
	UIImage *photo = self.avatarImage;
	ABAddressBookRequestAccessWithCompletion(book, ^(bool granted, CFErrorRef error){
		if (!granted){
			CFRelease(book);
			return;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			ABRecordRef person = ABPersonCreate();
			if (first.length)
				ABRecordSetValue(person, kABPersonFirstNameProperty, (__bridge CFStringRef)first, NULL);
			if (last.length)
				ABRecordSetValue(person, kABPersonLastNameProperty, (__bridge CFStringRef)last, NULL);

			ABMutableMultiValueRef phoneValues = ABMultiValueCreateMutable(kABMultiStringPropertyType);
			for (NSDictionary *item in phones){
				ABMultiValueAddValueAndLabel(phoneValues,
											 (__bridge CFStringRef)[item objectForKey:@"phone"],
											 (__bridge CFStringRef)[item objectForKey:@"label"], NULL);
			}
			ABRecordSetValue(person, kABPersonPhoneProperty, phoneValues, NULL);
			CFRelease(phoneValues);

			if (photo){
				NSData *data = UIImageJPEGRepresentation(photo, 0.9f);
				if (data)
					ABPersonSetImageData(person, (__bridge CFDataRef)data, NULL);
			}

			ABAddressBookAddRecord(book, person, NULL);
			ABAddressBookSave(book, NULL);
			CFRelease(person);
			CFRelease(book);
		});
	});
}

- (void)addPhotoPressed {
	if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary])
		return;
	[self.view endEditing:YES];
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	picker.allowsEditing = YES;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
	UIImage *image = [info objectForKey:UIImagePickerControllerEditedImage];
	if (!image)
		image = [info objectForKey:UIImagePickerControllerOriginalImage];
	if (image){
		self.avatarImage = image;
		self.avatarView.image = image;
		self.avatarView.hidden = NO;
	}
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)presentLabelPickerForRow:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.phoneEntries.count)
		return;
	NSMutableDictionary *entry = [self.phoneEntries objectAtIndex:(NSUInteger)row];
	[self.view endEditing:YES];
	TGPhoneLabelPickerController *picker = [[TGPhoneLabelPickerController alloc] init];
	picker.labels = [self phoneLabels];
	picker.selectedLabel = [entry objectForKey:@"label"];
	__weak typeof(self) weakSelf = self;
	picker.onPick = ^(NSString *label){
		TGNewContactViewController *me = weakSelf;
		if (!me)
			return;
		if (label.length)
			[entry setObject:label forKey:@"label"];
		[me.tableView reloadData];
		[me dismissViewControllerAnimated:YES completion:nil];
	};
	picker.onCancel = ^{
		TGNewContactViewController *me = weakSelf;
		[me dismissViewControllerAnimated:YES completion:nil];
	};
	UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:picker];
	[[TGTheme shared] styleNavigationBar:navigation.navigationBar];
	[self presentViewController:navigation animated:YES completion:nil];
}

- (void)qrTapped {
	[self.view endEditing:YES];
	TGQRViewController *scanner = [[TGQRViewController alloc] init];
	[self.navigationController pushViewController:scanner animated:YES];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		[weakSelf pruneEmptyPhoneRowsAroundField:textField];
	});
}

- (void)pruneEmptyPhoneRowsAroundField:(UITextField *)textField {
	NSMutableDictionary *focused = [self entryForField:textField];
	if (!focused)
		return;
	NSUInteger focusedIndex = [self.phoneEntries indexOfObject:focused];
	NSUInteger lastIndex = self.phoneEntries.count - 1;
	NSMutableArray *removedPaths = [[NSMutableArray alloc] init];
	NSMutableArray *removedEntries = [[NSMutableArray alloc] init];
	for (NSUInteger i = 0; i < self.phoneEntries.count; i++){
		if (i == focusedIndex || i == lastIndex)
			continue;
		NSMutableDictionary *entry = [self.phoneEntries objectAtIndex:i];
		if (!((UITextField *)[entry objectForKey:@"field"]).text.length){
			[removedPaths addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
			[removedEntries addObject:entry];
		}
	}
	if (!removedPaths.count)
		return;
	for (NSMutableDictionary *entry in removedEntries){
		UITextField *field = [entry objectForKey:@"field"];
		field.delegate = nil;
		[field removeFromSuperview];
		[self.phoneEntries removeObject:entry];
	}
	[self.tableView deleteRowsAtIndexPaths:removedPaths withRowAnimation:UITableViewRowAnimationFade];
	[self updateDoneEnabled];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	if (textField == self.firstNameField)
		[self.lastNameField becomeFirstResponder];
	else
		[textField resignFirstResponder];
	return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
	if (![self entryForField:textField] || !string.length)
		return YES;
	for (NSUInteger i = 0; i < string.length; i++){
		unichar c = [string characterAtIndex:i];
		if (!(c >= '0' && c <= '9') && c != '+')
			return NO;
	}
	return YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return (NSInteger)self.phoneEntries.count;
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 0 ? 44.0f : 43.0f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if (section == 0)
		return self.tableView.isEditing ? (18.0f + 12.0f) : 12.0f;
	return 10.0f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if (section == 0)
		return 0.0f;
	return 1.0f + ([UIScreen mainScreen].scale > 1.0f ? 0.5f : 1.0f);
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
	view.backgroundColor = [UIColor clearColor];
	return view;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
	view.backgroundColor = [UIColor clearColor];
	return view;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0){
		static NSString *reuse = @"TGNewContactPhone";
		TGNewContactPhoneCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
		if (!cell)
			cell = [[TGNewContactPhoneCell alloc] initWithReuseIdentifier:reuse];
		NSMutableDictionary *entry = [self.phoneEntries objectAtIndex:(NSUInteger)indexPath.row];
		cell.labelView.text = [entry objectForKey:@"label"];
		cell.field = [entry objectForKey:@"field"];
		cell.lastInGroup = (indexPath.row == (NSInteger)self.phoneEntries.count - 1);
		[[TGTheme shared] styleCell:cell];
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		[cell setNeedsLayout];
		[cell layoutIfNeeded];
		return cell;
	}

	static NSString *reuse = @"TGQRRow";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
		cell.backgroundColor = [UIColor clearColor];
		cell.backgroundView = [[UIView alloc] initWithFrame:CGRectZero];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.tag = 0x51525254;
		UIImage *plate = TGNewContactStretchedImage(@"GroupedActionButton.png");
		UIImage *platePressed = TGNewContactStretchedImage(@"GroupedActionButton_Highlighted.png");
		if (plate)
			[button setBackgroundImage:plate forState:UIControlStateNormal];
		if (platePressed)
			[button setBackgroundImage:platePressed forState:UIControlStateHighlighted];
		button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		button.titleLabel.shadowOffset = CGSizeMake(0, 1);
		[button setTitleColor:TGNewContactColour(0x4a6587, 1.0f) forState:UIControlStateNormal];
		[button setTitleShadowColor:TGNewContactColour(0xffffff, 0.45f) forState:UIControlStateNormal];
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		[button setTitleShadowColor:[UIColor clearColor] forState:UIControlStateHighlighted];
		button.exclusiveTouch = YES;
		[button setTitle:@"Add via QR Code" forState:UIControlStateNormal];
		[button addTarget:self action:@selector(qrTapped) forControlEvents:UIControlEventTouchUpInside];
		[cell.contentView addSubview:button];
	}
	UIButton *button = (UIButton *)[cell.contentView viewWithTag:0x51525254];
	UIImage *plate = [UIImage imageNamed:@"GroupedActionButton.png"];
	CGFloat buttonHeight = plate ? plate.size.height : 43.0f;
	CGFloat width = tableView.bounds.size.width - 18.0f;
	button.frame = CGRectMake(9, 0, width, buttonHeight);
	if (!plate)
		button.backgroundColor = [UIColor whiteColor];
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 0 && self.phoneEntries.count > 1;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0 && self.phoneEntries.count > 1)
		return UITableViewCellEditingStyleDelete;
	return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != 0)
		return;
	NSMutableDictionary *entry = [self.phoneEntries objectAtIndex:(NSUInteger)indexPath.row];
	UITextField *field = [entry objectForKey:@"field"];
	field.delegate = nil;
	[field removeFromSuperview];
	[self.phoneEntries removeObjectAtIndex:(NSUInteger)indexPath.row];
	[tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
					 withRowAnimation:UITableViewRowAnimationFade];
	dispatch_async(dispatch_get_main_queue(), ^{
		[tableView reloadData];
	});
	[self updateDoneEnabled];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 0)
		[self presentLabelPickerForRow:indexPath.row];
}

@end

#import "TGNewContactViewController.h"
#import "TGQRViewController.h"
#import "TGClient.h"
#import "TGClient+Contacts.h"
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
@property (nonatomic, strong) UIButton *removeButton;
@property (nonatomic, strong) UILabel *staticValueLabel;
@property (nonatomic, assign) BOOL lastInGroup;
- (void)setShowsRemoveControl:(BOOL)shows;
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

	self.removeButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.removeButton.frame = CGRectMake(7, 6, 30, 30);
	self.removeButton.exclusiveTouch = YES;
	self.removeButton.adjustsImageWhenHighlighted = NO;
	self.removeButton.hidden = YES;
	UIImage *switchImage = [UIImage imageNamed:@"ListEditingSwitch.png"];
	if (switchImage)
		[self.removeButton setBackgroundImage:switchImage forState:UIControlStateNormal];
	UIView *minus = [[UIView alloc] initWithFrame:CGRectMake(8, 14, 14, 2)];
	minus.backgroundColor = [UIColor whiteColor];
	minus.userInteractionEnabled = NO;
	[self.removeButton addSubview:minus];
	[self addSubview:self.removeButton];
	return self;
}

- (void)setShowsRemoveControl:(BOOL)shows {
	self.removeButton.hidden = !shows;
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
	self.staticValueLabel.frame = CGRectMake(78, 11, bounds.size.width - 80, 20);
	self.removeButton.frame = CGRectMake(7, 6, 30, 30);
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
@property (nonatomic, strong) NSArray *labelDisplayNames;
@property (nonatomic, strong) NSArray *labelIdentifiers;
@property (nonatomic, assign) BOOL saving;
@property (nonatomic, assign) BOOL didFocusNameField;
@property (nonatomic, assign) BOOL syncToPhone;
@property (nonatomic, assign) BOOL sharePhoneNumber;
@property (nonatomic, assign) int64_t resolvedUserId;
@property (nonatomic, assign) BOOL resolving;
@property (nonatomic, assign) BOOL resolveFinished;
@property (nonatomic, copy) NSString *resolvedName;
@property (nonatomic, copy) NSString *resolvedForPhone;
@property (nonatomic, strong) UILabel *phoneFooterLabel;
@property (nonatomic, strong) UIView *phoneFooterView;
@end

@implementation TGNewContactViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (!self)
		return nil;
	self.phoneEntries = [[NSMutableArray alloc] init];
	self.syncToPhone = YES;
	return self;
}

- (BOOL)hasKnownPeer {
	return self.peerUserId != 0;
}

- (BOOL)writesAddressBookRecord {
	return self.syncToPhone && !self.editingExistingContact && ![self hasKnownPeer];
}

- (void)buildPhoneLabels {
	static NSArray *displayLabels = nil;
	static NSArray *identifiers = nil;
	if (!displayLabels){
		NSMutableArray *display = [[NSMutableArray alloc] init];
		NSMutableArray *raw = [[NSMutableArray alloc] init];
		CFStringRef constants[] = { kABPersonPhoneMobileLabel, kABPersonPhoneIPhoneLabel,
									kABHomeLabel, kABWorkLabel, kABPersonPhoneMainLabel,
									kABPersonPhoneHomeFAXLabel, kABPersonPhoneWorkFAXLabel,
									kABPersonPhoneOtherFAXLabel, kABPersonPhonePagerLabel,
									kABOtherLabel };
		for (NSUInteger i = 0; i < sizeof(constants) / sizeof(constants[0]); i++){
			if (constants[i] == NULL)
				continue;
			NSString *identifier = (__bridge NSString *)constants[i];
			NSString *localized = (__bridge_transfer NSString *)ABAddressBookCopyLocalizedLabel(constants[i]);
			if (!localized.length || [display containsObject:localized])
				continue;
			[display addObject:localized];
			[raw addObject:identifier];
		}
		if (!display.count){
			[display addObject:@"mobile"];
			[raw addObject:(__bridge NSString *)kABPersonPhoneMobileLabel];
		}
		displayLabels = display;
		identifiers = raw;
	}
	self.labelDisplayNames = displayLabels;
	self.labelIdentifiers = identifiers;
}

- (NSArray *)phoneLabels {
	if (!self.labelDisplayNames)
		[self buildPhoneLabels];
	return self.labelDisplayNames;
}

- (NSString *)addressBookLabelForDisplayLabel:(NSString *)display {
	if (!self.labelDisplayNames)
		[self buildPhoneLabels];
	NSUInteger index = display ? [self.labelDisplayNames indexOfObject:display] : NSNotFound;
	if (index == NSNotFound)
		return display.length ? display : (__bridge NSString *)kABPersonPhoneMobileLabel;
	return [self.labelIdentifiers objectAtIndex:index];
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
	self.title = self.editingExistingContact ? @"Edit Contact" : @"New Contact";
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
	self.firstNameField.text = self.prefillFirstName ?: @"";
	self.lastNameField  = [self makeFieldWithPlaceholder:@"Last" font:[UIFont boldSystemFontOfSize:16]];
	self.lastNameField.returnKeyType = UIReturnKeyDefault;
	self.lastNameField.text = self.prefillLastName ?: @"";

	if ([self hasKnownPeer]){
		self.resolvedUserId = self.peerUserId;
		self.resolveFinished = YES;
	} else {
		[self.phoneEntries addObject:[self makePhoneEntry]];
		[self.phoneEntries addObject:[self makePhoneEntry]];
		if (self.prefillPhone.length){
			UITextField *first = [[self.phoneEntries objectAtIndex:0] objectForKey:@"field"];
			first.text = [self.prefillPhone hasPrefix:@"+"]
					? self.prefillPhone
					: [@"+" stringByAppendingString:self.prefillPhone];
		}
	}

	[self buildTableHeader];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textChanged:)
												 name:UITextFieldTextDidChangeNotification object:nil];
	[self.tableView setEditing:YES animated:NO];
	[self updateDoneEnabled];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (self.didFocusNameField)
		return;
	self.didFocusNameField = YES;
	[self.firstNameField becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.view endEditing:YES];
}

- (void)buildTableHeader {
	CGFloat width = self.view.bounds.size.width > 0
			? self.view.bounds.size.width
			: [UIScreen mainScreen].bounds.size.width;
	BOOL showsPhoto = !self.editingExistingContact && ![self hasKnownPeer];
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

	self.addPhotoButton.hidden = !showsPhoto;
	CGFloat nameLeft = showsPhoto ? 90.0f : 9.0f;
	self.editNameContainer = [[UIView alloc] initWithFrame:CGRectMake(nameLeft, 14, width - nameLeft - 9, 88)];
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
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
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
	NSMutableDictionary *entry = [self entryForField:object];
	if (entry){
		BOOL hasText = [self fieldHasNumber:object];
		BOOL hadText = [[entry objectForKey:@"hadText"] boolValue];
		[entry setObject:[NSNumber numberWithBool:hasText] forKey:@"hadText"];
		[self appendEmptyPhoneRowIfNeeded];
		NSUInteger row = [self.phoneEntries indexOfObject:entry];
		if (row != NSNotFound){
			id cell = [self.tableView cellForRowAtIndexPath:
					[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
			if ([cell isKindOfClass:[TGNewContactPhoneCell class]])
				[(TGNewContactPhoneCell *)cell setShowsRemoveControl:hasText];
		}
		if (hasText != hadText){
			[self.tableView beginUpdates];
			[self.tableView endUpdates];
		}
		[self updateDoneEnabled];
		[self schedulePhoneLookup];
	}
}

- (void)appendEmptyPhoneRowIfNeeded {
	NSMutableDictionary *last = [self.phoneEntries lastObject];
	if (![self fieldHasNumber:[last objectForKey:@"field"]])
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

- (NSString *)digitsOf:(NSString *)text {
	NSMutableString *digits = [[NSMutableString alloc] init];
	for (NSUInteger i = 0; i < text.length; i++){
		unichar c = [text characterAtIndex:i];
		if (c >= '0' && c <= '9')
			[digits appendString:[NSString stringWithCharacters:&c length:1]];
	}
	return digits;
}

- (NSArray *)enteredPhones {
	NSMutableArray *result = [[NSMutableArray alloc] init];
	for (NSMutableDictionary *entry in self.phoneEntries){
		NSString *phone = [self trimmed:((UITextField *)[entry objectForKey:@"field"]).text];
		if ([self digitsOf:phone].length){
			NSMutableDictionary *item = [[NSMutableDictionary alloc] init];
			NSString *display = [entry objectForKey:@"label"];
			[item setObject:phone forKey:@"phone"];
			[item setObject:display forKey:@"label"];
			[item setObject:[self addressBookLabelForDisplayLabel:display] forKey:@"abLabel"];
			[result addObject:item];
		}
	}
	return result;
}

- (BOOL)isFormValid {
	if (![self trimmed:self.firstNameField.text].length)
		return NO;
	if ([self hasKnownPeer])
		return YES;
	return [self enteredPhones].count > 0;
}

- (void)updateDoneEnabled {
	BOOL enabled = !self.saving && [self isFormValid];
	self.doneButton.enabled = enabled;
	self.doneButton.alpha = enabled ? 1.0f : 0.5f;
}

- (BOOL)fieldHasNumber:(UITextField *)field {
	return [self digitsOf:(field.text ?: @"")].length > 0;
}

- (NSString *)primaryPhone {
	NSArray *phones = [self enteredPhones];
	if (phones.count)
		return [[phones objectAtIndex:0] objectForKey:@"phone"];
	return @"";
}

- (NSString *)phoneStatusText {
	if ([self hasKnownPeer]){
		if (self.prefillPhone.length || self.editingExistingContact)
			return nil;
		return @"This person's phone number will only be shared with you once you become mutual contacts.";
	}
	if (self.resolving)
		return @"Checking this number...";
	if (!self.resolveFinished)
		return nil;
	if (self.resolvedUserId)
		return [NSString stringWithFormat:@"%@ is on Telegram.",
				self.resolvedName.length ? self.resolvedName : @"This number"];
	return @"This number is not on Telegram yet. The contact will be saved anyway.";
}

- (void)resetPhoneLookup {
	self.resolving = NO;
	self.resolveFinished = NO;
	self.resolvedUserId = 0;
	self.resolvedName = nil;
	self.resolvedForPhone = nil;
}

- (void)schedulePhoneLookup {
	if ([self hasKnownPeer])
		return;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runPhoneLookup)
											   object:nil];
	NSString *phone = [self primaryPhone];
	if ([self digitsOf:phone].length < 5){
		if (self.resolveFinished || self.resolving || self.resolvedForPhone){
			[self resetPhoneLookup];
			[self refreshPhoneFooter];
		}
		return;
	}
	if ([phone isEqualToString:self.resolvedForPhone])
		return;
	[self performSelector:@selector(runPhoneLookup) withObject:nil afterDelay:1.0];
}

- (void)runPhoneLookup {
	NSString *phone = [self primaryPhone];
	if ([self digitsOf:phone].length < 5)
		return;
	self.resolving = YES;
	self.resolveFinished = NO;
	self.resolvedUserId = 0;
	self.resolvedName = nil;
	[self refreshPhoneFooter];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userForPhone:phone completion:^(NSDictionary *user){
		TGNewContactViewController *me = weakSelf;
		if (!me)
			return;
		if (![[me primaryPhone] isEqualToString:phone])
			return;
		me.resolving = NO;
		me.resolveFinished = YES;
		me.resolvedForPhone = phone;
		me.resolvedUserId = [user[@"id"] longLongValue];
		NSString *first = user[@"first_name"] ?: @"";
		NSString *last = user[@"last_name"] ?: @"";
		NSString *name = [[NSString stringWithFormat:@"%@ %@", first, last]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		me.resolvedName = name.length ? name : nil;
		[me refreshPhoneFooter];
	}];
}

- (void)refreshPhoneFooter {
	NSString *text = [self phoneStatusText];
	self.phoneFooterLabel.text = text ?: @"";
	[self.tableView beginUpdates];
	[self.tableView endUpdates];
	[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
				  withRowAnimation:UITableViewRowAnimationNone];
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
	if (self.navigationController.viewControllers.count > 1){
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}
	UIViewController *presenting = self.presentingViewController;
	if (!presenting)
		presenting = self.navigationController.presentingViewController;
	if (presenting)
		[presenting dismissViewControllerAnimated:YES completion:nil];
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
	NSString *primaryPhone = phones.count
			? [[phones objectAtIndex:0] objectForKey:@"phone"]
			: (self.prefillPhone ?: @"");

	self.saving = YES;
	[self updateDoneEnabled];
	[self.view endEditing:YES];

	if ([self writesAddressBookRecord])
		[self saveToAddressBookFirst:first last:last phones:phones];

	void (^report)(int64_t) = self.onDone;
	BOOL share = self.sharePhoneNumber;

	if (self.resolvedUserId){
		int64_t userId = self.resolvedUserId;
		[[TGClient shared] addContactWithUserId:userId
										  phone:primaryPhone
									  firstName:first
									   lastName:last
							   sharePhoneNumber:share
									 completion:^(BOOL ok){
			if (report)
				report(ok ? userId : 0);
		}];
	} else {
		[[TGClient shared] importContactWithPhone:primaryPhone
										firstName:first
										 lastName:last
									   completion:^(int64_t userId){
			if (report)
				report(userId);
		}];
	}

	[self closeSelf];
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
											 (__bridge CFStringRef)[item objectForKey:@"abLabel"], NULL);
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
	if ([self entryForField:textField] && !textField.text.length)
		textField.text = @"+";
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
		if (![self fieldHasNumber:[entry objectForKey:@"field"]]){
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

	NSMutableString *accepted = [[NSMutableString alloc] initWithCapacity:string.length];
	for (NSUInteger i = 0; i < string.length; i++){
		unichar c = [string characterAtIndex:i];
		if ((c >= '0' && c <= '9') || (c == '+' && range.location == 0 && accepted.length == 0))
			[accepted appendString:[NSString stringWithCharacters:&c length:1]];
	}
	if ([accepted isEqualToString:string])
		return YES;
	if (!accepted.length)
		return NO;

	NSString *current = textField.text ? textField.text : @"";
	if (range.location + range.length > current.length)
		return NO;
	textField.text = [current stringByReplacingCharactersInRange:range withString:accepted];
	UITextPosition *caret = [textField positionFromPosition:textField.beginningOfDocument
													offset:(NSInteger)(range.location + accepted.length)];
	if (caret)
		textField.selectedTextRange = [textField textRangeFromPosition:caret toPosition:caret];
	[[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:textField];
	return NO;
}

- (NSInteger)numberOfOptionRows {
	NSInteger rows = 0;
	if (![self hasKnownPeer] && !self.editingExistingContact)
		rows++;
	if (self.offersShareException)
		rows++;
	return rows;
}

- (BOOL)showsQRSection {
	return ![self hasKnownPeer] && !self.editingExistingContact && !self.resolvedUserId;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return [self hasKnownPeer] ? 1 : (NSInteger)self.phoneEntries.count;
	if (section == 1)
		return [self numberOfOptionRows];
	return [self showsQRSection] ? 1 : 0;
}

- (CGFloat)phoneFooterHeight {
	NSString *text = [self phoneStatusText];
	if (!text.length)
		return 0.0f;
	CGFloat width = self.tableView.bounds.size.width > 0
			? self.tableView.bounds.size.width : self.view.bounds.size.width;
	CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:14]
				   constrainedToSize:CGSizeMake(MAX(40.0f, width - 40.0f), 1000)
					   lineBreakMode:NSLineBreakByWordWrapping];
	return size.height + 14.0f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 2 ? 43.0f : 44.0f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if ([self tableView:tableView numberOfRowsInSection:section] == 0)
		return 0.0f;
	if (section == 0)
		return self.tableView.isEditing ? (18.0f + 12.0f) : 12.0f;
	return 10.0f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if (section == 0)
		return [self phoneFooterHeight];
	if ([self tableView:tableView numberOfRowsInSection:section] == 0)
		return 0.0f;
	return 1.0f + ([UIScreen mainScreen].scale > 1.0f ? 0.5f : 1.0f);
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
	view.backgroundColor = [UIColor clearColor];
	return view;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (section != 0){
		UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
		view.backgroundColor = [UIColor clearColor];
		return view;
	}
	if (!self.phoneFooterView){
		self.phoneFooterView = [[UIView alloc] initWithFrame:CGRectZero];
		self.phoneFooterView.backgroundColor = [UIColor clearColor];
		self.phoneFooterLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		self.phoneFooterLabel.autoresizingMask =
				UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		self.phoneFooterLabel.backgroundColor = [UIColor clearColor];
		self.phoneFooterLabel.font = [UIFont systemFontOfSize:14];
		self.phoneFooterLabel.numberOfLines = 0;
		self.phoneFooterLabel.lineBreakMode = NSLineBreakByWordWrapping;
		if ([[TGTheme shared] isDarkStyle]){
			self.phoneFooterLabel.textColor = [[TGTheme shared] secondaryTextColour];
		} else {
			self.phoneFooterLabel.textColor = TGNewContactColour(0x697487, 1.0f);
			self.phoneFooterLabel.shadowColor = TGNewContactColour(0xdae0e8, 1.0f);
			self.phoneFooterLabel.shadowOffset = CGSizeMake(0, 1);
		}
		[self.phoneFooterView addSubview:self.phoneFooterLabel];
	}
	self.phoneFooterLabel.text = [self phoneStatusText] ?: @"";
	CGFloat width = tableView.bounds.size.width;
	CGFloat height = [self phoneFooterHeight];
	self.phoneFooterView.frame = CGRectMake(0, 0, width, height);
	self.phoneFooterLabel.frame = CGRectMake(20, 7, MAX(40.0f, width - 40.0f),
											 MAX(0.0f, height - 14.0f));
	return self.phoneFooterView;
}

- (UITableViewCell *)optionCellForRow:(NSInteger)row {
	static NSString *reuse = @"TGNewContactOption";
	UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:reuse];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];

	BOOL syncRow = ![self hasKnownPeer] && !self.editingExistingContact && row == 0;
	UISwitch *toggle = [[UISwitch alloc] init];
	if (syncRow){
		cell.textLabel.text = @"Save to Phone Contacts";
		toggle.on = self.syncToPhone;
		[toggle addTarget:self action:@selector(syncToPhoneToggled:)
		 forControlEvents:UIControlEventValueChanged];
	} else {
		cell.textLabel.text = @"Share My Phone Number";
		toggle.on = self.sharePhoneNumber;
		[toggle addTarget:self action:@selector(sharePhoneToggled:)
		 forControlEvents:UIControlEventValueChanged];
	}
	cell.accessoryView = toggle;
	return cell;
}

- (void)syncToPhoneToggled:(UISwitch *)toggle {
	self.syncToPhone = toggle.on;
}

- (void)sharePhoneToggled:(UISwitch *)toggle {
	self.sharePhoneNumber = toggle.on;
}

- (UITableViewCell *)knownPeerPhoneCell {
	static NSString *reuse = @"TGNewContactKnownPhone";
	TGNewContactPhoneCell *cell = [self.tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGNewContactPhoneCell alloc] initWithReuseIdentifier:reuse];
	cell.labelView.text = @"mobile";
	cell.field = nil;
	cell.lastInGroup = YES;
	[cell setShowsRemoveControl:NO];
	cell.textLabel.text = nil;
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	if (!cell.staticValueLabel){
		cell.staticValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		cell.staticValueLabel.backgroundColor = [UIColor clearColor];
		cell.staticValueLabel.font = [UIFont boldSystemFontOfSize:15];
		cell.staticValueLabel.textColor = [[TGTheme shared] isDarkStyle]
				? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
		cell.staticValueLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[cell.contentView addSubview:cell.staticValueLabel];
	}
	NSString *phone = self.prefillPhone.length
			? ([self.prefillPhone hasPrefix:@"+"] ? self.prefillPhone
					: [@"+" stringByAppendingString:self.prefillPhone])
			: @"hidden";
	cell.staticValueLabel.textColor = self.prefillPhone.length
			? ([[TGTheme shared] isDarkStyle]
					? [[TGTheme shared] primaryTextColour] : [UIColor blackColor])
			: [[TGTheme shared] secondaryTextColour];
	cell.staticValueLabel.text = phone;
	[cell setNeedsLayout];
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 1)
		return [self optionCellForRow:indexPath.row];

	if (indexPath.section == 0 && [self hasKnownPeer])
		return [self knownPeerPhoneCell];

	if (indexPath.section == 0){
		static NSString *reuse = @"TGNewContactPhone";
		TGNewContactPhoneCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
		if (!cell)
			cell = [[TGNewContactPhoneCell alloc] initWithReuseIdentifier:reuse];
		NSMutableDictionary *entry = [self.phoneEntries objectAtIndex:(NSUInteger)indexPath.row];
		cell.labelView.text = [entry objectForKey:@"label"];
		cell.field = [entry objectForKey:@"field"];
		cell.lastInGroup = (indexPath.row == (NSInteger)self.phoneEntries.count - 1);
		[cell setShowsRemoveControl:[self rowCarriesNumber:indexPath]];
		[cell.removeButton removeTarget:self action:NULL
					   forControlEvents:UIControlEventTouchUpInside];
		[cell.removeButton addTarget:self action:@selector(removePhoneRowPressed:)
					forControlEvents:UIControlEventTouchUpInside];
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

- (BOOL)rowCarriesNumber:(NSIndexPath *)indexPath {
	if (indexPath.section != 0 || indexPath.row >= (NSInteger)self.phoneEntries.count)
		return NO;
	NSMutableDictionary *entry = [self.phoneEntries objectAtIndex:(NSUInteger)indexPath.row];
	return [self fieldHasNumber:[entry objectForKey:@"field"]];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return [self rowCarriesNumber:indexPath];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
	return [self rowCarriesNumber:indexPath];
}

- (void)removePhoneRowPressed:(UIButton *)button {
	UIView *view = button;
	while (view && ![view isKindOfClass:[TGNewContactPhoneCell class]])
		view = view.superview;
	if (!view)
		return;
	NSIndexPath *indexPath = [self.tableView indexPathForCell:(UITableViewCell *)view];
	if (!indexPath)
		return;
	[self tableView:self.tableView commitEditingStyle:UITableViewCellEditingStyleDelete
	forRowAtIndexPath:indexPath];
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
	if (!self.phoneEntries.count){
		[self.phoneEntries addObject:[self makePhoneEntry]];
		[tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:0 inSection:0]]
						 withRowAnimation:UITableViewRowAnimationFade];
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[tableView reloadData];
	});
	[self updateDoneEnabled];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 0 && ![self hasKnownPeer])
		[self presentLabelPickerForRow:indexPath.row];
}

@end

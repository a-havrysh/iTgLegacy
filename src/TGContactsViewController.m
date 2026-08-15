#import "TGContactsViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGClient+Contacts.h"
#import "TGClient+UserStatus.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import "TGImageDecode.h"
#import "TGNewContactViewController.h"
#import "UIView+SafeTint.h"
#import <QuartzCore/QuartzCore.h>
#import <AddressBook/AddressBook.h>

static const CGFloat kContactAvatar = 40.0f;
static const CGFloat kContactRowHeight = 51.0f;
static const CGFloat kContactAvatarLeft = 5.0f;
static const CGFloat kContactAvatarTop = 5.0f;
static const CGFloat kContactTextLeft = 54.0f;
static const CGFloat kContactSectionHeight = 25.0f;
static const CGFloat kContactBadgeSide = 14.0f;
static const CGFloat kContactBadgeGap = 3.0f;
static const CGFloat kContactFooterHeight = 58.0f;

static UIColor *TGContactsRGB(int rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:1.0f];
}

static UIImage *TGContactsStretchable(NSString *name) {
	UIImage *image = [UIImage imageNamed:name];
	if (!image)
		return nil;
	if ([image respondsToSelector:@selector(resizableImageWithCapInsets:)])
		return [image resizableImageWithCapInsets:UIEdgeInsetsZero];
	return [image stretchableImageWithLeftCapWidth:1 topCapHeight:0];
}

static UIImage *TGContactsScaledImage(NSString *name, CGFloat side) {
	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [NSMutableDictionary dictionary];
	NSString *key = [NSString stringWithFormat:@"%@-%d", name, (int)side];
	UIImage *cached = cache[key];
	if (cached)
		return cached;
	UIImage *source = [UIImage imageNamed:name];
	if (!source)
		return nil;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0.0f);
	[source drawInRect:CGRectMake(0, 0, side, side)];
	UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (scaled)
		cache[key] = scaled;
	return scaled;
}

@interface TGContactsProgressWindow : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *containerView;
- (void)show;
- (void)dismiss;
@end

@implementation TGContactsProgressWindow

- (void)show {
	if (self.window)
		return;
	CGRect bounds = [[UIScreen mainScreen] bounds];
	self.window = [[UIWindow alloc] initWithFrame:bounds];
	self.window.windowLevel = UIWindowLevelStatusBar + 1.0f;
	self.window.backgroundColor = [UIColor clearColor];
	self.window.userInteractionEnabled = YES;

	UIView *dim = [[UIView alloc] initWithFrame:bounds];
	dim.backgroundColor = [UIColor clearColor];
	[self.window addSubview:dim];

	self.containerView = [[UIView alloc] initWithFrame:CGRectMake(
			(CGFloat)(int)((bounds.size.width - 100) / 2),
			(CGFloat)(int)((bounds.size.height - 100) / 2), 100, 100)];
	self.containerView.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.7f];
	self.containerView.layer.cornerRadius = 16.0f;
	self.containerView.alpha = 0.0f;
	[dim addSubview:self.containerView];

	UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
	spinner.center = CGPointMake(50, 50);
	spinner.frame = CGRectIntegral(spinner.frame);
	[spinner startAnimating];
	[self.containerView addSubview:spinner];

	self.window.hidden = NO;
	[UIView animateWithDuration:0.3f animations:^{
		self.containerView.alpha = 1.0f;
	}];
}

- (void)dismiss {
	if (!self.window)
		return;
	UIWindow *window = self.window;
	UIView *container = self.containerView;
	self.window = nil;
	self.containerView = nil;
	[UIView animateWithDuration:0.3f animations:^{
		container.alpha = 0.0f;
	} completion:^(BOOL finished){
		window.hidden = YES;
	}];
}

@end

@interface TGContactRowCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *premiumView;
@property (nonatomic, strong) UILabel *verifiedLabel;
@property (nonatomic, strong) UILabel *closeFriendLabel;
@end

@implementation TGContactRowCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	BOOL flat = [[TGTheme shared] isFlat];
	if (!flat){
		UIImage *background = TGContactsStretchable(@"Cell102");
		UIImage *highlighted = TGContactsStretchable(@"CellHighlighted102");
		if (background)
			self.backgroundView = [[UIImageView alloc] initWithImage:background];
		if (highlighted)
			self.selectedBackgroundView = [[UIImageView alloc] initWithImage:highlighted];
	}
	self.backgroundColor = [[TGTheme shared] listBackgroundColour];

	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake(kContactAvatarLeft, kContactAvatarTop, kContactAvatar, kContactAvatar)];
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	self.avatarView.clipsToBounds = YES;
	[self.contentView addSubview:self.avatarView];

	self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.titleLabel.backgroundColor = [UIColor clearColor];
	self.titleLabel.font = [UIFont systemFontOfSize:19];
	self.titleLabel.textColor = flat ? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
	self.titleLabel.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:self.titleLabel];

	self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.subtitleLabel.backgroundColor = [UIColor clearColor];
	self.subtitleLabel.font = [UIFont systemFontOfSize:13.5f];
	self.subtitleLabel.textColor = [UIColor colorWithWhite:0.0f alpha:0.53f];
	self.subtitleLabel.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:self.subtitleLabel];

	self.premiumView = [[UIImageView alloc] initWithFrame:CGRectZero];
	self.premiumView.contentMode = UIViewContentModeScaleAspectFit;
	self.premiumView.hidden = YES;
	[self.contentView addSubview:self.premiumView];

	self.verifiedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.verifiedLabel.backgroundColor = [UIColor clearColor];
	self.verifiedLabel.font = [UIFont boldSystemFontOfSize:13];
	self.verifiedLabel.textColor = TGContactsRGB(0x3aa3e3);
	self.verifiedLabel.highlightedTextColor = [UIColor whiteColor];
	self.verifiedLabel.textAlignment = NSTextAlignmentCenter;
	self.verifiedLabel.text = @"✓";
	self.verifiedLabel.hidden = YES;
	[self.contentView addSubview:self.verifiedLabel];

	self.closeFriendLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.closeFriendLabel.backgroundColor = [UIColor clearColor];
	self.closeFriendLabel.font = [UIFont systemFontOfSize:13];
	self.closeFriendLabel.textColor = TGContactsRGB(0x3ac13a);
	self.closeFriendLabel.highlightedTextColor = [UIColor whiteColor];
	self.closeFriendLabel.textAlignment = NSTextAlignmentCenter;
	self.closeFriendLabel.text = @"★";
	self.closeFriendLabel.hidden = YES;
	[self.contentView addSubview:self.closeFriendLabel];

	return self;
}

- (CGFloat)badgeWidth {
	CGFloat width = 0;
	if (!self.closeFriendLabel.hidden)
		width += kContactBadgeSide + kContactBadgeGap;
	if (!self.premiumView.hidden)
		width += kContactBadgeSide + kContactBadgeGap;
	if (!self.verifiedLabel.hidden)
		width += kContactBadgeSide + kContactBadgeGap;
	return width;
}

- (void)layoutBadgesAfterTitleWidth:(CGFloat)titleWidth titleY:(CGFloat)titleY
					   titleHeight:(CGFloat)titleHeight {
	CGSize fit = [self.titleLabel sizeThatFits:CGSizeMake(titleWidth, titleHeight)];
	CGFloat x = kContactTextLeft + MIN(fit.width, titleWidth) + kContactBadgeGap;
	CGFloat y = (CGFloat)(int)(titleY + (titleHeight - kContactBadgeSide) / 2);
	if (!self.closeFriendLabel.hidden){
		self.closeFriendLabel.frame = CGRectMake(x, y, kContactBadgeSide, kContactBadgeSide);
		x += kContactBadgeSide + kContactBadgeGap;
	}
	if (!self.premiumView.hidden){
		self.premiumView.frame = CGRectMake(x, y, kContactBadgeSide, kContactBadgeSide);
		x += kContactBadgeSide + kContactBadgeGap;
	}
	if (!self.verifiedLabel.hidden)
		self.verifiedLabel.frame = CGRectMake(x, y, kContactBadgeSide, kContactBadgeSide);
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGSize viewSize = self.contentView.frame.size;
	self.avatarView.frame = CGRectMake(kContactAvatarLeft, kContactAvatarTop,
			kContactAvatar, kContactAvatar);

	CGFloat width = viewSize.width - kContactTextLeft - 5;
	CGFloat titleHeight = self.titleLabel.font.lineHeight;
	CGFloat subtitleHeight = self.subtitleLabel.font.lineHeight;
	CGFloat titleWidth = MAX(20.0f, width - [self badgeWidth]);

	if (self.subtitleLabel.text.length == 0){
		CGFloat titleY = (CGFloat)(int)((viewSize.height - titleHeight) / 2) - 1;
		self.titleLabel.frame = CGRectMake(kContactTextLeft, titleY, titleWidth, titleHeight);
		self.subtitleLabel.frame = CGRectZero;
		[self layoutBadgesAfterTitleWidth:titleWidth titleY:titleY titleHeight:titleHeight];
		return;
	}

	CGFloat titleY = (CGFloat)(int)((viewSize.height - titleHeight - subtitleHeight - 1) / 2);
	self.titleLabel.frame = CGRectMake(kContactTextLeft, titleY, titleWidth, titleHeight);
	[self layoutBadgesAfterTitleWidth:titleWidth titleY:titleY titleHeight:titleHeight];
	self.subtitleLabel.frame = CGRectMake(kContactTextLeft + 1, titleY + titleHeight + 0.5f,
			width, subtitleHeight);
}

@end

@interface TGContactsViewController () <UISearchBarDelegate, UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *users;
@property (nonatomic, strong) NSArray *filteredUsers;
@property (nonatomic, strong) NSArray *sectionTitles;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSMutableDictionary *photos;
@property (nonatomic, strong) NSMutableSet *photosRequested;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSString *searchQuery;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) BOOL sortByName;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, strong) NSMutableSet *closeFriendIds;
@property (nonatomic, strong) NSMutableDictionary *badges;
@property (nonatomic, strong) NSMutableSet *badgesRequested;
@property (nonatomic, strong) UILabel *importLabel;
@property (nonatomic, assign) NSInteger importedCount;
@property (nonatomic, assign) BOOL importedCountKnown;
@property (nonatomic, strong) NSDictionary *actionUser;
@property (nonatomic, strong) NSString *actionBirthdate;
@property (nonatomic, assign) BOOL actionSheetShown;
@property (nonatomic, strong) NSMutableDictionary *birthdays;
@property (nonatomic, strong) TGContactsProgressWindow *progress;
@property (nonatomic, assign) BOOL importing;
@property (nonatomic, strong) NSDictionary *pendingDeleteUser;
@end

@implementation TGContactsViewController

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

static NSString *TGContactString(NSDictionary *u, NSString *key) {
	id value = u[key];
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *TGContactName(NSDictionary *u) {
	NSString *first = TGContactString(u, @"first_name");
	NSString *last  = TGContactString(u, @"last_name");
	NSString *name  = [[NSString stringWithFormat:@"%@ %@", first, last]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (name.length)
		return name;
	NSString *username = TGContactString(u, @"username");
	if (username.length)
		return [NSString stringWithFormat:@"@%@", username];
	return TGContactString(u, @"phone");
}

- (void)sortUsers {
	self.users = [self.users sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
		if (self.isPickerMode || self.sortByName)
			return [TGContactName(a) localizedCaseInsensitiveCompare:TGContactName(b)];
		int64_t rankA = [a[@"statusRank"] longLongValue];
		int64_t rankB = [b[@"statusRank"] longLongValue];
		if (rankA != rankB)
			return rankA > rankB ? NSOrderedAscending : NSOrderedDescending;
		return [TGContactName(a) localizedCaseInsensitiveCompare:TGContactName(b)];
	}];
}

- (void)sortTapped {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Sort by"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:
			self.sortByName ? @"Last Seen" : @"Last Seen ✓",
			self.sortByName ? @"Name ✓" : @"Name", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 1;
	UITabBar *tabBar = [self.tabBarController isKindOfClass:UITabBarController.class]
			? self.tabBarController.tabBar : nil;
	if (tabBar)
		[sheet showFromTabBar:tabBar];
	else
		[sheet showInView:self.navigationController.view];
}

- (BOOL)isCloseFriend:(NSDictionary *)u {
	NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
	return userId && [self.closeFriendIds containsObject:@(userId.longLongValue)];
}

- (void)reloadCloseFriends {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] contactCloseFriendsWithCompletion:^(NSArray *users){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableSet *ids = [NSMutableSet set];
		if ([users isKindOfClass:NSArray.class]){
			for (NSDictionary *u in users){
				if (![u isKindOfClass:NSDictionary.class])
					continue;
				NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
				if (userId)
					[ids addObject:@(userId.longLongValue)];
			}
		}
		me.closeFriendIds = ids;
		[me reloadTableSoon];
	}];
}

- (void)reloadImportedCount {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] importedContactCountWithCompletion:^(NSInteger count){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		me.importedCount = count;
		me.importedCountKnown = YES;
		[me updateImportFooter];
	}];
}

- (void)updateImportFooter {
	if (!self.importLabel)
		return;
	if (!self.importedCountKnown)
		self.importLabel.text = @"Sync contacts from your address book";
	else if (self.importedCount <= 0)
		self.importLabel.text = @"No address book contacts synced\nTap to sync";
	else if (self.importedCount == 1)
		self.importLabel.text = @"1 contact synced from your address book";
	else
		self.importLabel.text = [NSString stringWithFormat:
				@"%d contacts synced from your address book", (int)self.importedCount];
}

- (void)presentSheet:(UIActionSheet *)sheet {
	UITabBar *tabBar = [self.tabBarController isKindOfClass:UITabBarController.class]
			? self.tabBarController.tabBar : nil;
	if (tabBar)
		[sheet showFromTabBar:tabBar];
	else
		[sheet showInView:self.navigationController.view];
}

- (void)importFooterTapped {
	if (self.importing)
		return;
	NSString *title = (self.importedCountKnown && self.importedCount > 0)
			? @"Imported address book contacts stay on Telegram until you delete them."
			: @"Telegram can look for your address book contacts who already have an account.";
	UIActionSheet *sheet = [[UIActionSheet alloc]
			initWithTitle:title
				 delegate:self
		cancelButtonTitle:nil
   destructiveButtonTitle:nil
		otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"Sync Contacts"];
	if (self.importedCountKnown && self.importedCount > 0)
		sheet.destructiveButtonIndex = [sheet addButtonWithTitle:@"Delete Synced Contacts"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 3;
	[self presentSheet:sheet];
}

- (NSString *)normalisedPhone:(NSString *)phone {
	NSMutableString *digits = [NSMutableString string];
	for (NSUInteger i = 0; i < phone.length; i++){
		unichar c = [phone characterAtIndex:i];
		if (c >= '0' && c <= '9')
			[digits appendFormat:@"%C", c];
	}
	return digits;
}

- (NSArray *)addressBookEntriesFrom:(ABAddressBookRef)book {
	NSMutableArray *entries = [NSMutableArray array];
	CFArrayRef people = ABAddressBookCopyArrayOfAllPeople(book);
	if (!people)
		return entries;
	CFIndex count = CFArrayGetCount(people);
	for (CFIndex i = 0; i < count && entries.count < 1000; i++){
		ABRecordRef person = CFArrayGetValueAtIndex(people, i);
		NSString *first = (__bridge_transfer NSString *)
				ABRecordCopyValue(person, kABPersonFirstNameProperty);
		NSString *last = (__bridge_transfer NSString *)
				ABRecordCopyValue(person, kABPersonLastNameProperty);
		ABMultiValueRef phones = ABRecordCopyValue(person, kABPersonPhoneProperty);
		if (!phones)
			continue;
		CFIndex phoneCount = ABMultiValueGetCount(phones);
		for (CFIndex j = 0; j < phoneCount && entries.count < 1000; j++){
			NSString *raw = (__bridge_transfer NSString *)
					ABMultiValueCopyValueAtIndex(phones, j);
			NSString *phone = [self normalisedPhone:raw ?: @""];
			if (phone.length < 5)
				continue;
			[entries addObject:@{
				@"phone"      : phone,
				@"first_name" : first.length ? first : @"",
				@"last_name"  : last.length ? last : @"",
			}];
		}
		CFRelease(phones);
	}
	CFRelease(people);
	return entries;
}

- (void)finishImportWithResult:(NSArray *)userIds total:(NSInteger)total {
	self.importing = NO;
	[self.progress dismiss];
	self.progress = nil;
	NSInteger found = 0;
	if ([userIds isKindOfClass:NSArray.class]){
		for (NSNumber *userId in userIds)
			if ([userId isKindOfClass:NSNumber.class] && userId.longLongValue != 0)
				found++;
	}
	NSString *message = found
			? [NSString stringWithFormat:@"%d of %d address book contacts are on Telegram.",
					(int)found, (int)total]
			: @"None of your address book contacts are on Telegram yet.";
	[[[UIAlertView alloc] initWithTitle:nil
							   message:message
							  delegate:nil
					 cancelButtonTitle:@"OK"
					 otherButtonTitles:nil] show];
	[self reloadImportedCount];
	[self reloadContacts];
}

- (void)startAddressBookImport {
	if (self.importing)
		return;
	ABAddressBookRef book = ABAddressBookCreateWithOptions(NULL, NULL);
	if (!book){
		[[[UIAlertView alloc] initWithTitle:nil
								   message:@"Telegram could not open your address book."
								  delegate:nil
						 cancelButtonTitle:@"OK"
						 otherButtonTitles:nil] show];
		return;
	}
	self.importing = YES;
	self.progress = [[TGContactsProgressWindow alloc] init];
	[self.progress show];

	__weak typeof(self) weakSelf = self;
	ABAddressBookRequestAccessWithCompletion(book, ^(bool granted, CFErrorRef error){
		dispatch_async(dispatch_get_main_queue(), ^{
			TGContactsViewController *me = weakSelf;
			if (!me){
				CFRelease(book);
				return;
			}
			if (!granted){
				CFRelease(book);
				me.importing = NO;
				[me.progress dismiss];
				me.progress = nil;
				[[[UIAlertView alloc] initWithTitle:nil
										   message:@"Telegram needs access to Contacts in Settings."
										  delegate:nil
								 cancelButtonTitle:@"OK"
								 otherButtonTitles:nil] show];
				return;
			}
			NSArray *entries = [me addressBookEntriesFrom:book];
			CFRelease(book);
			if (!entries.count){
				me.importing = NO;
				[me.progress dismiss];
				me.progress = nil;
				[[[UIAlertView alloc] initWithTitle:nil
										   message:@"Your address book has no phone numbers to sync."
										  delegate:nil
								 cancelButtonTitle:@"OK"
								 otherButtonTitles:nil] show];
				return;
			}
			NSInteger total = (NSInteger)entries.count;
			[[TGClient shared] syncImportedContacts:entries completion:^(NSArray *userIds){
				TGContactsViewController *inner = weakSelf;
				if (!inner)
					return;
				[inner finishImportWithResult:userIds total:total];
			}];
		});
	});
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan || self.isPickerMode)
		return;
	CGPoint point = [gesture locationInView:self.tableView];
	NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
	if (!indexPath || [self isInviteRowAtIndexPath:indexPath])
		return;
	NSDictionary *u = [self userAtIndexPath:indexPath];
	if (!u)
		return;
	self.actionUser = u;
	self.actionBirthdate = nil;
	self.actionSheetShown = NO;

	NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
	id cached = userId ? self.birthdays[userId] : nil;
	if (cached){
		if ([cached isKindOfClass:NSDictionary.class])
			self.actionBirthdate = [self birthdayTextFrom:cached];
		[self showContactActions];
		return;
	}

	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(showContactActions)
											   object:nil];
	[self performSelector:@selector(showContactActions) withObject:nil afterDelay:0.4f];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] birthdateForUser:[u[@"id"] longLongValue]
							 completion:^(NSDictionary *birthdate){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		if (userId)
			me.birthdays[userId] = [birthdate isKindOfClass:NSDictionary.class]
					? birthdate : (id)[NSNull null];
		if (me.actionUser != u)
			return;
		NSString *text = [birthdate isKindOfClass:NSDictionary.class]
				? [me birthdayTextFrom:birthdate] : nil;
		if (text.length)
			me.actionBirthdate = text;
		[me showContactActions];
	}];
}

- (NSString *)birthdayTextFrom:(NSDictionary *)birthdate {
	NSString *text = birthdate[@"text"];
	if (![text isKindOfClass:NSString.class] || !text.length)
		return nil;
	return [self isBirthdayToday:birthdate]
			? [NSString stringWithFormat:@"%@ (today)", text] : text;
}

- (BOOL)isBirthdayToday:(NSDictionary *)birthdate {
	if (![birthdate isKindOfClass:NSDictionary.class])
		return NO;
	NSInteger day = [birthdate[@"day"] integerValue];
	NSInteger month = [birthdate[@"month"] integerValue];
	if (day <= 0 || month <= 0)
		return NO;
	NSDateComponents *now = [[NSCalendar currentCalendar]
			components:(NSDayCalendarUnit | NSMonthCalendarUnit) fromDate:[NSDate date]];
	return now.day == day && now.month == month;
}

- (BOOL)hasBirthdayTodayForUser:(NSDictionary *)u {
	NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
	id cached = userId ? self.birthdays[userId] : nil;
	return [cached isKindOfClass:NSDictionary.class] && [self isBirthdayToday:cached];
}

- (void)showContactActions {
	NSDictionary *u = self.actionUser;
	if (!u || self.actionSheetShown)
		return;
	self.actionSheetShown = YES;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(showContactActions)
											   object:nil];
	BOOL close = [self isCloseFriend:u];
	NSMutableString *title = [NSMutableString stringWithString:TGContactName(u)];
	NSString *username = TGContactString(u, @"username");
	if (username.length)
		[title appendFormat:@"\n@%@", username];
	NSString *phone = TGContactString(u, @"phone");
	if (phone.length)
		[title appendFormat:@"\n+%@", phone];
	if (self.actionBirthdate.length)
		[title appendFormat:@"\nBirthday %@", self.actionBirthdate];

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:
			close ? @"Remove from Close Friends" : @"Add to Close Friends",
			@"Send Message", nil];
	sheet.destructiveButtonIndex = [sheet addButtonWithTitle:@"Delete Contact"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 2;
	[self presentSheet:sheet];
}

- (void)toggleCloseFriendForUser:(NSDictionary *)u {
	NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
	if (!userId)
		return;
	BOOL close = ![self isCloseFriend:u];
	if (close)
		[self.closeFriendIds addObject:@(userId.longLongValue)];
	else
		[self.closeFriendIds removeObject:@(userId.longLongValue)];
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setUser:userId.longLongValue closeFriend:close completion:^(BOOL ok){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[[[UIAlertView alloc] initWithTitle:nil
									   message:@"Could not update Close Friends."
									  delegate:nil
							 cancelButtonTitle:@"OK"
							 otherButtonTitles:nil] show];
		}
		[me reloadCloseFriends];
	}];
}

- (void)openChatWithUser:(NSDictionary *)u {
	NSString *name = TGContactName(u);
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] privateChatWithUser:[u[@"id"] longLongValue]
								completion:^(int64_t chatId){
		TGContactsViewController *me = weakSelf;
		if (!me || chatId == 0)
			return;
		TGChatViewController *vc = [[TGChatViewController alloc] init];
		vc.chatId = chatId;
		vc.chatTitle = name;
		[me.navigationController pushViewController:vc animated:YES];
	}];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;
	if (sheet.tag == 1){
		self.sortByName = (index == 1);
		[self refreshTable];
		return;
	}
	if (sheet.tag == 2){
		NSDictionary *u = self.actionUser;
		self.actionUser = nil;
		if (!u)
			return;
		if (index == 0)
			[self toggleCloseFriendForUser:u];
		else if (index == 1)
			[self openChatWithUser:u];
		else if (index == sheet.destructiveButtonIndex)
			[self confirmDeleteContact:u];
		return;
	}
	if (sheet.tag == 3){
		if (index == sheet.destructiveButtonIndex){
			__weak typeof(self) weakSelf = self;
			[[TGClient shared] clearImportedContactsWithCompletion:^(BOOL ok){
				TGContactsViewController *me = weakSelf;
				if (!me)
					return;
				[me reloadImportedCount];
				if (ok)
					[me reloadContacts];
			}];
			return;
		}
		if ([[sheet buttonTitleAtIndex:index] isEqualToString:@"Sync Contacts"])
			[self startAddressBookImport];
	}
}

- (void)confirmDeleteContact:(NSDictionary *)u {
	self.pendingDeleteUser = u;
	UIAlertView *alert = [[UIAlertView alloc]
			initWithTitle:nil
				  message:[NSString stringWithFormat:@"Delete %@ from your contacts?",
						  TGContactName(u)]
				 delegate:self
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@"Delete", nil];
	[alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
	NSDictionary *u = self.pendingDeleteUser;
	self.pendingDeleteUser = nil;
	if (index == alertView.cancelButtonIndex || !u)
		return;
	[self deleteContact:u];
}

- (void)deleteContact:(NSDictionary *)u {
	NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
	if (!userId)
		return;

	NSArray *previous = self.users;
	NSMutableArray *remaining = [NSMutableArray array];
	for (NSDictionary *other in previous)
		if ([other[@"id"] longLongValue] != userId.longLongValue)
			[remaining addObject:other];
	self.users = remaining;
	[self refreshTable];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] removeContacts:@[userId] completion:^(BOOL ok){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		if (ok){
			[me.closeFriendIds removeObject:@(userId.longLongValue)];
			return;
		}
		me.users = previous;
		[me refreshTable];
		[[[UIAlertView alloc] initWithTitle:nil
								   message:@"Could not delete this contact."
								  delegate:nil
						 cancelButtonTitle:@"OK"
						 otherButtonTitles:nil] show];
	}];
}

- (BOOL)matchesQuery:(NSDictionary *)u query:(NSString *)query {
	if ([TGContactName(u) rangeOfString:query options:NSCaseInsensitiveSearch].length)
		return YES;
	if ([TGContactString(u, @"username") rangeOfString:query
											  options:NSCaseInsensitiveSearch].length)
		return YES;
	if ([TGContactString(u, @"phone") rangeOfString:query
										   options:NSCaseInsensitiveSearch].length)
		return YES;
	return NO;
}

- (void)applyFilter {
	NSString *query = [self.searchQuery
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!query.length){
		self.filteredUsers = nil;
		return;
	}
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *u in self.users)
		if ([self matchesQuery:u query:query])
			[out addObject:u];
	self.filteredUsers = out;
}

- (void)rebuildSections {
	if ((!self.isPickerMode && !self.sortByName) || self.filteredUsers){
		self.sectionTitles = nil;
		self.sections = nil;
		return;
	}
	NSMutableArray *titles = [NSMutableArray array];
	NSMutableArray *groups = [NSMutableArray array];
	for (NSDictionary *u in self.users){
		NSString *name = TGContactName(u);
		NSString *letter = name.length
				? [name substringToIndex:1].uppercaseString : @"#";
		if (![letter rangeOfCharacterFromSet:
				[NSCharacterSet uppercaseLetterCharacterSet]].length)
			letter = @"#";
		if (![titles.lastObject isEqualToString:letter]){
			[titles addObject:letter];
			[groups addObject:[NSMutableArray array]];
		}
		[groups.lastObject addObject:u];
	}
	self.sectionTitles = titles;
	self.sections = groups;
}

- (void)userStatusChanged:(NSNotification *)note {
	int64_t userId = [note.userInfo[@"userId"] longLongValue];
	NSDictionary *status = note.userInfo[@"status"];
	if (![status isKindOfClass:NSDictionary.class])
		return;
	NSMutableArray *updated = [self.users mutableCopy];
	for (NSUInteger i = 0; i < updated.count; i++){
		NSDictionary *u = updated[i];
		if ([u[@"id"] longLongValue] != userId)
			continue;
		NSMutableDictionary *next = [u mutableCopy];
		next[@"isOnline"]   = status[@"isOnline"] ?: @(NO);
		next[@"statusText"] = status[@"text"] ?: @"";
		next[@"statusRank"] = status[@"rank"] ?: @(0);
		updated[i] = next;
		break;
	}
	self.users = updated;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											  selector:@selector(applyPendingStatusChanges)
												object:nil];
	[self performSelector:@selector(applyPendingStatusChanges) withObject:nil afterDelay:0];
}

- (void)applyPendingStatusChanges {
	[self refreshTable];
}

- (void)refreshTable {
	[self sortUsers];
	[self applyFilter];
	[self rebuildSections];
	[self.tableView reloadData];
	[self updateEmptyState];
}

- (void)reloadTableSoon {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(reloadTableNow)
											   object:nil];
	[self performSelector:@selector(reloadTableNow) withObject:nil afterDelay:0.15f];
}

- (void)reloadTableNow {
	[self.tableView reloadData];
}

- (void)updateEmptyState {
	if (!self.emptyLabel)
		return;
	NSString *text = nil;
	if (!self.loaded)
		text = @"Loading...";
	else if (self.filteredUsers && self.filteredUsers.count == 0)
		text = @"No results";
	else if (!self.filteredUsers && self.users.count == 0)
		text = @"You have no contacts yet";
	self.emptyLabel.text = text ?: @"";
	self.emptyLabel.hidden = (text == nil);
}

- (void)reloadContacts {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] contactsWithCompletion:^(NSArray *users){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		me.loaded = YES;
		me.users = [users isKindOfClass:NSArray.class] ? users : @[];
		[me refreshTable];
		[me fetchMissingPhotos];
		if (!me.isPickerMode){
			[me reloadCloseFriends];
			[me reloadImportedCount];
		}
		if ([me respondsToSelector:@selector(refreshControl)])
			[me.refreshControl endRefreshing];
	}];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	if (!self.title.length)
		self.title = @"Contacts";
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.users = @[];
	self.photos = [NSMutableDictionary dictionary];
	self.photosRequested = [NSMutableSet set];
	self.closeFriendIds = [NSMutableSet set];
	self.badges = [NSMutableDictionary dictionary];
	self.badgesRequested = [NSMutableSet set];
	self.birthdays = [NSMutableDictionary dictionary];
	self.tableView.rowHeight = kContactRowHeight;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.separatorStyle = [[TGTheme shared] isFlat]
			? UITableViewCellSeparatorStyleSingleLine
			: UITableViewCellSeparatorStyleNone;

	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
	self.searchBar.delegate = self;
	self.searchBar.placeholder = @"Search";
	if ([self.searchBar respondsToSelector:@selector(setBarTintColor:)])
		self.searchBar.barTintColor = [[TGTheme shared] listBackgroundColour];
	else
		[self.searchBar tg_setTintColor:[UIColor colorWithWhite:0.68f alpha:1.0f]];
	self.tableView.tableHeaderView = self.searchBar;

	UIView *background = [[UIView alloc] initWithFrame:self.tableView.bounds];
	background.backgroundColor = [[TGTheme shared] listBackgroundColour];
	background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.emptyLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 120, background.bounds.size.width, 22)];
	self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.emptyLabel.backgroundColor = [UIColor clearColor];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.emptyLabel.hidden = YES;
	[background addSubview:self.emptyLabel];
	self.tableView.backgroundView = background;

	if (!self.isPickerMode && [self respondsToSelector:@selector(setRefreshControl:)]
			&& NSClassFromString(@"UIRefreshControl")){
		UIRefreshControl *refresh = [[NSClassFromString(@"UIRefreshControl") alloc] init];
		[refresh addTarget:self action:@selector(reloadContacts)
		  forControlEvents:UIControlEventValueChanged];
		self.refreshControl = refresh;
	}

	if (!self.isPickerMode){
		UIButton *add = [UIButton buttonWithType:UIButtonTypeCustom];
		[TGIcons styleHeaderButton:add];
		[add addTarget:self action:@selector(addContactTapped) forControlEvents:UIControlEventTouchUpInside];
		add.frame = CGRectMake(0, 0, 30, 30);
		UILabel *plus = [[UILabel alloc] initWithFrame:CGRectOffset(add.bounds, 0, -2)];
		plus.text = @"+";
		plus.textColor = [UIColor whiteColor];
		plus.textAlignment = NSTextAlignmentCenter;
		plus.backgroundColor = [UIColor clearColor];
		plus.font = [UIFont boldSystemFontOfSize:18];
		plus.userInteractionEnabled = NO;
		[add addSubview:plus];
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:add];

		UIButton *sort = [TGIcons headerButtonWithTitle:@"Sort" bold:NO
												  target:self action:@selector(sortTapped)];
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:sort];
	}

	if (!self.isPickerMode){
		UIView *footer = [[UIView alloc] initWithFrame:
				CGRectMake(0, 0, self.tableView.bounds.size.width, kContactFooterHeight)];
		footer.backgroundColor = [UIColor clearColor];
		footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		self.importLabel = [[UILabel alloc] initWithFrame:
				CGRectMake(10, 14, footer.bounds.size.width - 20, 34)];
		self.importLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		self.importLabel.backgroundColor = [UIColor clearColor];
		self.importLabel.textAlignment = NSTextAlignmentCenter;
		self.importLabel.numberOfLines = 2;
		self.importLabel.font = [UIFont systemFontOfSize:14];
		self.importLabel.textColor = [[TGTheme shared] secondaryTextColour];
		[footer addSubview:self.importLabel];
		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(importFooterTapped)];
		[footer addGestureRecognizer:tap];
		self.tableView.tableFooterView = footer;
		[self updateImportFooter];

		UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
				initWithTarget:self action:@selector(longPressed:)];
		press.minimumPressDuration = 0.5f;
		[self.tableView addGestureRecognizer:press];
	}

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(userStatusChanged:)
				name:TGUserStatusDidChangeNotification
			  object:nil];

	[self updateEmptyState];
	[self reloadContacts];
	if (!self.isPickerMode){
		[self reloadCloseFriends];
		[self reloadImportedCount];
	}
}

- (void)inviteFriendsTapped {
	NSDictionary *me = [TGClient shared].me;
	NSDictionary *usernameBox = [me isKindOfClass:NSDictionary.class] ? me[@"usernames"] : nil;
	NSArray *usernames = [usernameBox isKindOfClass:NSDictionary.class]
			? usernameBox[@"active_usernames"] : nil;
	NSString *username = ([usernames isKindOfClass:NSArray.class] && usernames.count)
			? usernames[0] : nil;
	if (![username isKindOfClass:NSString.class])
		username = nil;
	NSString *link = username.length
			? [NSString stringWithFormat:@"https://t.me/%@", username]
			: @"https://telegram.org";
	NSString *text = [NSString stringWithFormat:
			@"Hey, I'm using Telegram to chat. You can join me here: %@", link];

	UIActivityViewController *sheet = [[UIActivityViewController alloc]
			initWithActivityItems:@[text] applicationActivities:nil];
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)addContactTapped {
	TGNewContactViewController *vc = [[TGNewContactViewController alloc] init];
	__weak typeof(self) weakSelf = self;
	vc.onDone = ^{
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		[me reloadContacts];
	};
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	[self presentModalViewController:nav animated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
	self.searchQuery = query;
	[self applyFilter];
	[self rebuildSections];
	[self.tableView reloadData];
	[self updateEmptyState];
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
	self.searchQuery = nil;
	self.filteredUsers = nil;
	[self rebuildSections];
	[self.tableView reloadData];
	[self updateEmptyState];
	[searchBar resignFirstResponder];
}

- (NSString *)thumbCachePathForKey:(NSString *)key {
	NSString *dir = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, NSUserDomainMask, YES).firstObject
					stringByAppendingPathComponent:@"ContactThumbs"];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir
							 withIntermediateDirectories:YES attributes:nil error:nil];
	return [dir stringByAppendingPathComponent:
			[NSString stringWithFormat:@"%@.png", key]];
}

- (NSString *)thumbCacheKeyForUser:(NSDictionary *)u {
	NSString *uniqueId = u[@"photoUniqueId"];
	if ([uniqueId isKindOfClass:NSString.class] && uniqueId.length)
		return uniqueId;
	NSNumber *fileId = u[@"photoFileId"];
	return [fileId isKindOfClass:NSNumber.class] ? fileId.stringValue : nil;
}

- (void)fetchMissingPhotos {
	__weak typeof(self) weakSelf = self;
	NSMutableSet *liveKeys = [NSMutableSet set];
	for (NSDictionary *u in self.users){
		NSString *key = [self thumbCacheKeyForUser:u];
		if (key)
			[liveKeys addObject:key];
	}
	[self pruneThumbCacheKeeping:liveKeys];

	for (NSDictionary *u in self.users){
		NSNumber *fileId = u[@"photoFileId"];
		NSString *cacheKey = [self thumbCacheKeyForUser:u];
		if (![fileId isKindOfClass:NSNumber.class] || !cacheKey)
			continue;
		if (self.photos[fileId] || [self.photosRequested containsObject:fileId])
			continue;
		[self.photosRequested addObject:fileId];

		NSString *cachePath = [self thumbCachePathForKey:cacheKey];
		if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]){
			UIImage *cached = [UIImage imageWithContentsOfFile:cachePath];
			if (cached && fabs(cached.size.width - kContactAvatar) < 0.5f
					   && fabs(cached.size.height - kContactAvatar) < 0.5f){
				self.photos[fileId] = cached;
				continue;
			}
			[[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
		}

		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			if (!path){
				TGContactsViewController *me = weakSelf;
				[me.photosRequested removeObject:fileId];
				return;
			}
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				UIImage *thumb = TGDecodeSquareThumbnail(path, kContactAvatar);
				if (thumb)
					[UIImagePNGRepresentation(thumb) writeToFile:cachePath atomically:YES];
				dispatch_async(dispatch_get_main_queue(), ^{
					TGContactsViewController *me = weakSelf;
					if (!me || !thumb)
						return;
					me.photos[fileId] = thumb;
					[me reloadTableSoon];
				});
			});
		}];
	}
}

- (void)pruneThumbCacheKeeping:(NSSet *)liveKeys {
	NSString *dir = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, NSUserDomainMask, YES).firstObject
					stringByAppendingPathComponent:@"ContactThumbs"];
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *file in [fm contentsOfDirectoryAtPath:dir error:nil]){
		NSString *stem = [file stringByDeletingPathExtension];
		if (![liveKeys containsObject:stem])
			[fm removeItemAtPath:[dir stringByAppendingPathComponent:file] error:nil];
	}
}

- (NSDictionary *)badgesForUser:(NSDictionary *)u {
	NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
	if (!userId)
		return nil;
	NSDictionary *cached = self.badges[userId];
	if (cached)
		return cached;
	if ([self.badgesRequested containsObject:userId])
		return nil;
	[self.badgesRequested addObject:userId];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] badgesForUser:userId.longLongValue
						  completion:^(NSDictionary *badges){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		me.badges[userId] = [badges isKindOfClass:NSDictionary.class] ? badges : @{};
		[me reloadTableSoon];
	}];
	return nil;
}

- (NSArray *)rowsForSection:(NSInteger)section {
	if (self.sections)
		return (section >= 0 && section < (NSInteger)self.sections.count)
				? self.sections[section] : @[];
	return self.filteredUsers ?: self.users;
}

- (BOOL)isInviteRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 0 && [self showsInviteRow] && indexPath.row == 0;
}

- (NSDictionary *)userAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isInviteRowAtIndexPath:indexPath])
		return nil;
	NSInteger row = indexPath.row
			- ((indexPath.section == 0 && [self showsInviteRow]) ? 1 : 0);
	NSArray *rows = [self rowsForSection:indexPath.section];
	if (row < 0 || row >= (NSInteger)rows.count)
		return nil;
	NSDictionary *u = rows[row];
	return [u isKindOfClass:NSDictionary.class] ? u : nil;
}

- (BOOL)showsInviteRow {
	return !self.isPickerMode && !self.filteredUsers;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.sections ? self.sections.count : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSInteger extra = (section == 0 && [self showsInviteRow]) ? 1 : 0;
	return [self rowsForSection:section].count + extra;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return kContactRowHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return self.sections ? kContactSectionHeight : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (!self.sections || section < 0 || section >= (NSInteger)self.sectionTitles.count)
		return nil;

	CGFloat width = tableView.bounds.size.width;
	UIView *container = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, kContactSectionHeight)];
	container.clipsToBounds = NO;
	container.backgroundColor = [UIColor clearColor];

	UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
	label.backgroundColor = [UIColor clearColor];
	label.font = [UIFont boldSystemFontOfSize:15];
	label.numberOfLines = 1;
	label.text = self.sectionTitles[section];

	if ([[TGTheme shared] isFlat]){
		container.backgroundColor = [[TGTheme shared] listBackgroundColour];
		label.textColor = [[TGTheme shared] sectionHeaderColour];
	} else {
		UIImage *background = TGContactsStretchable(
				section == 0 ? @"CategoryDividerFirst" : @"CategoryDivider");
		if (background){
			UIImageView *backgroundView = [[UIImageView alloc] initWithImage:background];
			backgroundView.frame = CGRectMake(0, -1, width, kContactSectionHeight + 1);
			backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
			[container addSubview:backgroundView];
		} else {
			container.backgroundColor = TGContactsRGB(0xa8b0b8);
		}
		label.textColor = [UIColor whiteColor];
		label.shadowColor = TGContactsRGB(0x88929c);
		label.shadowOffset = CGSizeMake(0, -1);
	}

	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 10, 1);
	[container addSubview:label];
	return container;
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
	return self.sectionTitles;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGContactCell";
	static NSString *inviteReuse = @"TGInviteCell";

	if ([self isInviteRowAtIndexPath:indexPath]){
		TGContactRowCell *cell = (TGContactRowCell *)
				[tableView dequeueReusableCellWithIdentifier:inviteReuse];
		if (!cell)
			cell = [[TGContactRowCell alloc] initWithStyle:UITableViewCellStyleDefault
										   reuseIdentifier:inviteReuse];
		cell.titleLabel.text = @"Invite Friends";
		cell.titleLabel.textColor = [[TGTheme shared] accentColour];
		cell.subtitleLabel.text = @"";
		cell.avatarView.image = [TGIcons inviteFriendsAvatarOfSide:kContactAvatar];
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.premiumView.hidden = YES;
		cell.verifiedLabel.hidden = YES;
		cell.closeFriendLabel.hidden = YES;
		return cell;
	}

	TGContactRowCell *cell = (TGContactRowCell *)[tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGContactRowCell alloc] initWithStyle:UITableViewCellStyleDefault
									   reuseIdentifier:reuse];

	NSDictionary *u = [self userAtIndexPath:indexPath];
	if (!u){
		cell.titleLabel.attributedText = nil;
		cell.titleLabel.text = @"";
		cell.subtitleLabel.text = @"";
		cell.avatarView.image = nil;
		cell.premiumView.hidden = YES;
		cell.verifiedLabel.hidden = YES;
		cell.closeFriendLabel.hidden = YES;
		return cell;
	}
	NSString *first = [u[@"first_name"] isKindOfClass:NSString.class] ? u[@"first_name"] : @"";
	NSString *last  = [u[@"last_name"] isKindOfClass:NSString.class] ? u[@"last_name"] : @"";
	NSString *name = TGContactName(u);
	BOOL online = [u[@"isOnline"] boolValue];

	if (first.length && last.length){
		NSMutableAttributedString *title = [[NSMutableAttributedString alloc]
				initWithString:[NSString stringWithFormat:@"%@ %@", first, last]
					attributes:@{NSFontAttributeName : [UIFont systemFontOfSize:19]}];
		[title addAttribute:NSFontAttributeName
					  value:[UIFont boldSystemFontOfSize:19]
					  range:NSMakeRange(first.length + 1, last.length)];
		cell.titleLabel.attributedText = title;
	} else {
		cell.titleLabel.attributedText = nil;
		cell.titleLabel.text = name;
		cell.titleLabel.font = [UIFont systemFontOfSize:19];
	}

	NSString *phone = TGContactString(u, @"phone");
	cell.subtitleLabel.text = self.isPickerMode
			? (phone.length ? [NSString stringWithFormat:@"+%@", phone] : @"")
			: TGContactString(u, @"statusText");
	cell.subtitleLabel.textColor = (online && !self.isPickerMode)
			? TGContactsRGB(0x0779d0) : [UIColor colorWithWhite:0.0f alpha:0.53f];
	cell.backgroundColor = [[TGTheme shared] listBackgroundColour];
	cell.accessoryType = UITableViewCellAccessoryNone;

	NSDictionary *badges = [self badgesForUser:u];
	BOOL premium = [badges[@"isPremium"] boolValue];
	BOOL verified = [badges[@"isVerified"] boolValue];
	BOOL flagged = [badges[@"isScam"] boolValue] || [badges[@"isFake"] boolValue];
	UIImage *premiumIcon = premium
			? TGContactsScaledImage(@"tgpremiumicon.png", kContactBadgeSide) : nil;
	cell.premiumView.image = premiumIcon;
	cell.premiumView.hidden = (premiumIcon == nil);
	cell.verifiedLabel.hidden = !verified;
	cell.closeFriendLabel.hidden = self.isPickerMode || ![self isCloseFriend:u];
	if (!self.isPickerMode && [self hasBirthdayTodayForUser:u]){
		cell.subtitleLabel.text = cell.subtitleLabel.text.length
				? [NSString stringWithFormat:@"🎂 %@", cell.subtitleLabel.text]
				: @"🎂 Birthday today";
	}
	if (flagged && !self.isPickerMode){
		cell.subtitleLabel.textColor = TGContactsRGB(0xcc3333);
		NSString *mark = [badges[@"isScam"] boolValue] ? @"SCAM" : @"FAKE";
		cell.subtitleLabel.text = cell.subtitleLabel.text.length
				? [NSString stringWithFormat:@"%@ · %@", mark, cell.subtitleLabel.text]
				: mark;
	}
	[cell setNeedsLayout];

	NSNumber *fileId = u[@"photoFileId"];
	UIImage *photo = [fileId isKindOfClass:NSNumber.class] ? self.photos[fileId] : nil;
	if (!photo)
		photo = [TGIcons avatarWithInitials:
					(name.length ? [name substringToIndex:1].uppercaseString : @"?")
									   size:kContactAvatar
								   colourId:[u[@"id"] longLongValue]];
	cell.avatarView.image = photo;
	cell.avatarView.layer.cornerRadius = kContactAvatar * 0.12f;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if ([self isInviteRowAtIndexPath:indexPath]){
		[self inviteFriendsTapped];
		return;
	}
	NSDictionary *u = [self userAtIndexPath:indexPath];
	if (!u)
		return;
	NSString *name = TGContactName(u);
	__weak typeof(self) weakSelf = self;

	[self.searchBar resignFirstResponder];
	[[TGClient shared] privateChatWithUser:[u[@"id"] longLongValue]
								completion:^(int64_t chatId){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		if (chatId == 0){
			[[[UIAlertView alloc] initWithTitle:nil
									   message:@"Could not open this chat."
									  delegate:nil
							 cancelButtonTitle:@"OK"
							 otherButtonTitles:nil] show];
			return;
		}
		TGChatViewController *vc = [[TGChatViewController alloc] init];
		vc.chatId = chatId;
		vc.chatTitle = name;
		[me.navigationController pushViewController:vc animated:YES];
	}];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.isPickerMode)
		return NO;
	return [self userAtIndexPath:indexPath] != nil;
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
	NSDictionary *u = [self userAtIndexPath:indexPath];
	if (u)
		[self deleteContact:u];
}

@end

// vim:ft=objc

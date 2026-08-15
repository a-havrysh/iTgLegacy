#import "TGContactsViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGClient+Contacts.h"
#import "TGClient+SecretChats.h"
#import "TGClient+UserStatus.h"
#import "TGClient+Groups.h"
#import "TGClient+Files.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import "TGImageDecode.h"
#import "TGNewContactViewController.h"
#import "RootViewController.h"
#import "UIView+SafeTint.h"
#import <QuartzCore/QuartzCore.h>
#import <AddressBook/AddressBook.h>
#import <dlfcn.h>

static const CGFloat kContactAvatar = 40.0f;
static const CGFloat kContactRowHeight = 51.0f;
static const CGFloat kContactAvatarLeft = 5.0f;
static const CGFloat kContactAvatarTop = 5.0f;
static const CGFloat kContactTextLeft = 54.0f;
static const CGFloat kContactSectionHeight = 25.0f;
static const CGFloat kContactBadgeSide = 14.0f;
static const CGFloat kContactBadgeGap = 3.0f;
static const CGFloat kContactActionRowHeight = 44.0f;
static const CGFloat kContactAvatarCorner = 4.0f;
static const NSUInteger kContactPhotoCacheCount = 80;
static const NSUInteger kContactPhotoCacheBytes = 2 * 1024 * 1024;

static NSUInteger TGContactPhotoCost(UIImage *image) {
	CGImageRef bitmap = image.CGImage;
	if (!bitmap)
		return (NSUInteger)(image.size.width * image.size.height * 4);
	return (NSUInteger)(CGImageGetWidth(bitmap) * CGImageGetHeight(bitmap) * 4);
}

static NSString *const TGContactActionInvite = @"invite";
static NSString *const TGContactActionNewGroup = @"newGroup";
static NSString *const TGContactActionSync = @"sync";
static NSString *const TGContactActionLink = @"link";

static CGFloat TGContactsRetinaPixel(void) {
	return ([UIScreen mainScreen].scale > 1.5f) ? 0.5f : 0.0f;
}

static UIColor *TGContactsRGB(int rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:1.0f];
}

static BOOL TGContactsTabletLayout(void) {
	return [RootViewController isSplitLayoutActive];
}

static BOOL TGContactsShowInDetailPane(UIViewController *sender,
								   UIViewController *target) {
	(void)sender;
	if (!target || !TGContactsTabletLayout())
		return NO;
	return [RootViewController pushInDetail:target];
}

static CGFloat TGContactsScreenWidth(void) {
	return [UIScreen mainScreen].bounds.size.width;
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

@interface TGFlatActionCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIImageView *disclosureIndicator;
- (void)setIconImage:(UIImage *)image at:(CGPoint)origin;
@end

@implementation TGFlatActionCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	BOOL flat = [[TGTheme shared] isFlat];
	if (!flat){
		UIImage *background = [UIImage imageNamed:@"Cell88"] ?: [UIImage imageNamed:@"Cell102"];
		UIImage *highlighted = [UIImage imageNamed:@"CellHighlighted88"]
				?: [UIImage imageNamed:@"CellHighlighted102"];
		if (background)
			self.backgroundView = [[UIImageView alloc] initWithImage:background];
		if (highlighted)
			self.selectedBackgroundView = [[UIImageView alloc] initWithImage:highlighted];
	}
	self.backgroundColor = [[TGTheme shared] listBackgroundColour];

	self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(53, 12, 200, 20)];
	self.titleLabel.backgroundColor = [UIColor clearColor];
	self.titleLabel.contentMode = UIViewContentModeLeft;
	self.titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.titleLabel.textColor = TGContactsRGB(0x0779d0);
	self.titleLabel.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:self.titleLabel];

	self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
	[self.contentView addSubview:self.iconView];

	self.disclosureIndicator = [[UIImageView alloc] initWithImage:
			[UIImage imageNamed:@"MenuDisclosureIndicator"]
											 highlightedImage:
			[UIImage imageNamed:@"MenuDisclosureIndicator_Highlighted"]];
	self.disclosureIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.contentView addSubview:self.disclosureIndicator];

	return self;
}

- (void)setIconImage:(UIImage *)image at:(CGPoint)origin {
	self.iconView.image = image;
	if (!image){
		self.iconView.frame = CGRectZero;
		return;
	}
	self.iconView.frame = CGRectMake(origin.x, origin.y, image.size.width, image.size.height);
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (self.selectedBackgroundView){
		CGRect selectedFrame = self.selectedBackgroundView.frame;
		selectedFrame.origin.y = -1;
		selectedFrame.size.height = self.frame.size.height + 1;
		self.selectedBackgroundView.frame = selectedFrame;
	}
	CGFloat width = self.contentView.bounds.size.width;
	CGSize arrow = self.disclosureIndicator.image.size;
	if (arrow.width > 0)
		self.disclosureIndicator.frame = CGRectMake(width - arrow.width - 12, 14,
				arrow.width, arrow.height);
	CGFloat right = self.disclosureIndicator.hidden ? 12 : (arrow.width + 18);
	self.titleLabel.frame = CGRectMake(53, 12, MAX(20.0f, width - 53 - right), 20);
}

@end

@interface TGContactRowCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *secondTitleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *premiumView;
@property (nonatomic, strong) UIImageView *verifiedLabel;
@property (nonatomic, strong) UILabel *closeFriendLabel;
- (void)resetForConfiguration;
@end

@implementation TGContactRowCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	BOOL flat = [[TGTheme shared] isFlat];
	if (!flat){
		UIImage *background = [UIImage imageNamed:@"Cell102"];
		UIImage *highlighted = [UIImage imageNamed:@"CellHighlighted102"];
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

	self.secondTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.secondTitleLabel.backgroundColor = [UIColor clearColor];
	self.secondTitleLabel.font = [UIFont boldSystemFontOfSize:19];
	self.secondTitleLabel.textColor = flat ? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
	self.secondTitleLabel.highlightedTextColor = [UIColor whiteColor];
	self.secondTitleLabel.hidden = YES;
	[self.contentView addSubview:self.secondTitleLabel];

	self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.subtitleLabel.backgroundColor = [UIColor clearColor];
	self.subtitleLabel.font = [UIFont systemFontOfSize:13.0f + TGContactsRetinaPixel()];
	self.subtitleLabel.textColor = [UIColor colorWithWhite:0.0f alpha:0.53f];
	self.subtitleLabel.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:self.subtitleLabel];

	[self buildBadgeViews];

	return self;
}

- (void)buildBadgeViews {
	self.premiumView = [[UIImageView alloc] initWithFrame:CGRectZero];
	self.premiumView.contentMode = UIViewContentModeScaleAspectFit;
	self.premiumView.hidden = YES;
	[self.contentView addSubview:self.premiumView];

	self.verifiedLabel = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ListCheck"]
										  highlightedImage:[UIImage imageNamed:@"ListCheck_Highlighted"]];
	self.verifiedLabel.backgroundColor = [UIColor clearColor];
	self.verifiedLabel.contentMode = UIViewContentModeCenter;
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
}

- (void)resetForConfiguration {
	self.avatarView.image = nil;
	self.avatarView.layer.cornerRadius = kContactAvatarCorner;
	self.titleLabel.font = [UIFont systemFontOfSize:19];
	self.titleLabel.text = @"";
	self.secondTitleLabel.font = [UIFont boldSystemFontOfSize:19];
	self.secondTitleLabel.text = @"";
	self.secondTitleLabel.hidden = YES;
	self.subtitleLabel.text = @"";
	self.subtitleLabel.textColor = [UIColor colorWithWhite:0.0f alpha:0.53f];
	self.premiumView.image = nil;
	self.premiumView.hidden = YES;
	self.verifiedLabel.hidden = YES;
	self.closeFriendLabel.hidden = YES;
	self.accessoryType = UITableViewCellAccessoryNone;
	self.backgroundColor = [[TGTheme shared] listBackgroundColour];
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

- (void)layoutBadgesAfterX:(CGFloat)x titleY:(CGFloat)titleY
			   titleHeight:(CGFloat)titleHeight {
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

	if (self.selectedBackgroundView){
		CGRect selectedFrame = self.selectedBackgroundView.frame;
		selectedFrame.origin.y = -1;
		selectedFrame.size.height = self.frame.size.height + 1;
		self.selectedBackgroundView.frame = selectedFrame;
	}

	CGSize viewSize = self.contentView.frame.size;
	self.avatarView.frame = CGRectMake(kContactAvatarLeft, kContactAvatarTop,
			kContactAvatar, kContactAvatar);

	CGFloat width = viewSize.width - kContactTextLeft - 5;
	CGFloat titleHeight = self.titleLabel.font.lineHeight;
	CGFloat subtitleHeight = self.subtitleLabel.font.lineHeight;
	CGFloat titleWidth = MAX(20.0f, width - [self badgeWidth]);

	CGFloat titleY = self.subtitleLabel.text.length == 0
			? (CGFloat)(int)((viewSize.height - titleHeight) / 2) - 1
			: (CGFloat)(int)((viewSize.height - titleHeight - subtitleHeight - 1) / 2);

	CGFloat firstLimit = viewSize.width - kContactTextLeft - 5 - 14;
	CGFloat firstWidth = MIN(titleWidth, firstLimit);
	if (!self.secondTitleLabel.hidden){
		CGSize firstSize = [self.titleLabel.text sizeWithFont:self.titleLabel.font];
		firstWidth = MIN(firstSize.width, firstLimit);
	}
	self.titleLabel.frame = CGRectMake(kContactTextLeft, titleY, firstWidth, titleHeight);

	CGFloat badgeX = kContactTextLeft + firstWidth + kContactBadgeGap;
	if (!self.secondTitleLabel.hidden){
		CGFloat secondX = kContactTextLeft + firstWidth + 4;
		CGFloat secondWidth = MAX(0.0f, viewSize.width - 5 - [self badgeWidth] - secondX);
		self.secondTitleLabel.frame = CGRectMake(secondX, titleY, secondWidth, titleHeight);
		CGSize secondFit = [self.secondTitleLabel.text sizeWithFont:self.secondTitleLabel.font];
		badgeX = secondX + MIN(secondFit.width, secondWidth) + kContactBadgeGap;
	} else {
		CGSize fit = [self.titleLabel sizeThatFits:CGSizeMake(titleWidth, titleHeight)];
		badgeX = kContactTextLeft + MIN(fit.width, titleWidth) + kContactBadgeGap;
		self.secondTitleLabel.frame = CGRectZero;
	}
	[self layoutBadgesAfterX:badgeX titleY:titleY titleHeight:titleHeight];

	if (self.subtitleLabel.text.length == 0){
		self.subtitleLabel.frame = CGRectZero;
		return;
	}
	self.subtitleLabel.frame = CGRectMake(kContactTextLeft + 1,
			titleY + titleHeight + TGContactsRetinaPixel(), width, subtitleHeight);
}

@end

static NSString *TGContactString(NSDictionary *u, NSString *key);
static NSString *TGContactName(NSDictionary *u);

@interface TGMessageComposerShim : UIViewController
+ (BOOL)canSendText;
- (void)setRecipients:(NSArray *)recipients;
- (void)setBody:(NSString *)body;
- (void)setMessageComposeDelegate:(id)delegate;
@end

static Class TGMessageComposerClass(void) {
	Class cls = NSClassFromString(@"MFMessageComposeViewController");
	if (cls)
		return cls;
	dlopen("/System/Library/Frameworks/MessageUI.framework/MessageUI", RTLD_LAZY);
	return NSClassFromString(@"MFMessageComposeViewController");
}

static BOOL TGCanSendSMS(void) {
	Class cls = TGMessageComposerClass();
	if (!cls || ![cls respondsToSelector:@selector(canSendText)])
		return NO;
	NSMethodSignature *signature = [cls methodSignatureForSelector:@selector(canSendText)];
	if (!signature)
		return NO;
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	invocation.selector = @selector(canSendText);
	invocation.target = cls;
	[invocation invoke];
	BOOL result = NO;
	[invocation getReturnValue:&result];
	return result;
}

@interface TGInviteFriendsViewController : UITableViewController
@property (nonatomic, strong) NSArray *entries;
@property (nonatomic, strong) NSMutableSet *selected;
@property (nonatomic, copy) NSString *inviteText;
@property (nonatomic, strong) UIButton *inviteButton;
@property (nonatomic, strong) UILabel *inviteLabel;
@end

@implementation TGInviteFriendsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = @"Invite Friends";
	self.selected = [NSMutableSet set];
	self.tableView.rowHeight = kContactRowHeight;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.inviteButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[TGIcons styleHeaderButton:self.inviteButton];
	[self.inviteButton addTarget:self action:@selector(inviteTapped)
				forControlEvents:UIControlEventTouchUpInside];
	self.inviteLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.inviteLabel.textColor = [UIColor whiteColor];
	self.inviteLabel.textAlignment = NSTextAlignmentCenter;
	self.inviteLabel.backgroundColor = [UIColor clearColor];
	self.inviteLabel.font = [UIFont boldSystemFontOfSize:12];
	self.inviteLabel.userInteractionEnabled = NO;
	[self.inviteButton addSubview:self.inviteLabel];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:self.inviteButton];
	[self updateInviteButton];
}

- (void)updateInviteButton {
	if (!self.inviteButton)
		return;
	NSString *title = self.selected.count
			? [NSString stringWithFormat:@"Invite (%d)", (int)self.selected.count]
			: @"Invite";
	self.inviteLabel.text = title;
	CGSize size = [title sizeWithFont:self.inviteLabel.font];
	self.inviteButton.frame = CGRectMake(0, 0, size.width + 16, 30);
	self.inviteLabel.frame = self.inviteButton.bounds;
	self.inviteButton.enabled = self.selected.count > 0;
	self.inviteButton.alpha = self.selected.count ? 1.0f : 0.5f;
}

- (NSString *)nameForEntry:(NSDictionary *)entry {
	NSString *first = TGContactString(entry, @"first_name");
	NSString *last = TGContactString(entry, @"last_name");
	NSString *name = [[NSString stringWithFormat:@"%@ %@", first, last]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	return name.length ? name : [NSString stringWithFormat:@"+%@", TGContactString(entry, @"phone")];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGInviteEntryCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];
	if (indexPath.row >= (NSInteger)self.entries.count)
		return cell;
	NSDictionary *entry = self.entries[indexPath.row];
	NSString *phone = TGContactString(entry, @"phone");
	cell.textLabel.font = [UIFont systemFontOfSize:19];
	cell.textLabel.text = [self nameForEntry:entry];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13.5f];
	cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.0f alpha:0.53f];
	cell.detailTextLabel.text = phone.length ? [NSString stringWithFormat:@"+%@", phone] : @"";
	cell.backgroundColor = [[TGTheme shared] listBackgroundColour];
	cell.accessoryType = [self.selected containsObject:phone]
			? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.entries.count)
		return;
	NSString *phone = TGContactString(self.entries[indexPath.row], @"phone");
	if (!phone.length)
		return;
	if ([self.selected containsObject:phone])
		[self.selected removeObject:phone];
	else
		[self.selected addObject:phone];
	[tableView reloadRowsAtIndexPaths:@[indexPath]
					 withRowAnimation:UITableViewRowAnimationNone];
	[self updateInviteButton];
}

- (void)shareFallback {
	NSString *text = self.inviteText.length ? self.inviteText : @"";
	if (!text.length)
		return;
	UIActivityViewController *sheet = [[UIActivityViewController alloc]
			initWithActivityItems:@[text] applicationActivities:nil];
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)inviteTapped {
	if (!self.selected.count)
		return;
	NSMutableArray *recipients = [NSMutableArray array];
	for (NSDictionary *entry in self.entries){
		NSString *phone = TGContactString(entry, @"phone");
		if (phone.length && [self.selected containsObject:phone])
			[recipients addObject:[NSString stringWithFormat:@"+%@", phone]];
	}
	if (!recipients.count)
		return;

	Class composerClass = TGCanSendSMS() ? TGMessageComposerClass() : nil;
	if (!composerClass){
		[self shareFallback];
		return;
	}
	TGMessageComposerShim *composer = [[composerClass alloc] init];
	if (!composer){
		[self shareFallback];
		return;
	}
	if ([composer respondsToSelector:@selector(setRecipients:)])
		[composer setRecipients:recipients];
	if (self.inviteText.length && [composer respondsToSelector:@selector(setBody:)])
		[composer setBody:self.inviteText];
	if ([composer respondsToSelector:@selector(setMessageComposeDelegate:)])
		[composer setMessageComposeDelegate:self];
	[self presentModalViewController:composer animated:YES];
}

- (void)messageComposeViewController:(id)controller didFinishWithResult:(int)result {
	[self dismissModalViewControllerAnimated:YES];
	[self.navigationController popViewControllerAnimated:YES];
}

@end

@interface TGNewGroupMembersViewController : UITableViewController <UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *contacts;
@property (nonatomic, strong) NSMutableArray *selected;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UILabel *nextLabel;
@end

@implementation TGNewGroupMembersViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = @"New Group";
	self.selected = [NSMutableArray array];
	self.tableView.rowHeight = kContactRowHeight;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[TGIcons styleHeaderButton:self.nextButton];
	[self.nextButton addTarget:self action:@selector(nextTapped)
			  forControlEvents:UIControlEventTouchUpInside];
	self.nextLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.nextLabel.textColor = [UIColor whiteColor];
	self.nextLabel.textAlignment = NSTextAlignmentCenter;
	self.nextLabel.backgroundColor = [UIColor clearColor];
	self.nextLabel.font = [UIFont boldSystemFontOfSize:12];
	self.nextLabel.userInteractionEnabled = NO;
	[self.nextButton addSubview:self.nextLabel];
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:self.nextButton];
	[self updateNextButton];
}

- (void)updateNextButton {
	NSString *title = self.selected.count
			? [NSString stringWithFormat:@"Next (%d)", (int)self.selected.count] : @"Next";
	self.nextLabel.text = title;
	CGSize size = [title sizeWithFont:self.nextLabel.font];
	self.nextButton.frame = CGRectMake(0, 0, size.width + 16, 30);
	self.nextLabel.frame = self.nextButton.bounds;
	self.nextButton.enabled = self.selected.count > 0;
	self.nextButton.alpha = self.selected.count ? 1.0f : 0.5f;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.contacts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGNewGroupMemberCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:reuse];
	if (indexPath.row >= (NSInteger)self.contacts.count)
		return cell;
	NSDictionary *u = self.contacts[indexPath.row];
	cell.textLabel.font = [UIFont systemFontOfSize:19];
	cell.textLabel.text = TGContactName(u);
	cell.backgroundColor = [[TGTheme shared] listBackgroundColour];
	NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
	cell.accessoryType = (userId && [self.selected containsObject:userId])
			? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.contacts.count)
		return;
	NSDictionary *u = self.contacts[indexPath.row];
	NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
	if (!userId)
		return;
	if ([self.selected containsObject:userId])
		[self.selected removeObject:userId];
	else
		[self.selected addObject:userId];
	[tableView reloadRowsAtIndexPaths:@[indexPath]
					 withRowAnimation:UITableViewRowAnimationNone];
	[self updateNextButton];
}

- (void)nextTapped {
	if (!self.selected.count)
		return;
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New Group"
													message:@"Group name"
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Create", nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	[alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
	if (index == alertView.cancelButtonIndex)
		return;
	NSString *title = [[alertView textFieldAtIndex:0].text
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!title.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] createBasicGroupWithTitle:title
										 userIds:[self.selected copy]
									  completion:^(int64_t chatId, NSArray *failedUserIds){
		TGNewGroupMembersViewController *me = weakSelf;
		if (!me)
			return;
		if (chatId == 0){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not create this group."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		TGChatViewController *vc = [[TGChatViewController alloc] init];
		vc.chatId = chatId;
		vc.chatTitle = title;
		NSMutableArray *stack = [me.navigationController.viewControllers mutableCopy];
		[stack removeObject:me];
		[stack addObject:vc];
		[me.navigationController setViewControllers:stack animated:YES];
	}];
}

@end

static UIImage *TGSecretKeyImage(NSArray *cells) {
	if (![cells isKindOfClass:NSArray.class] || cells.count < 144)
		return nil;
	static const int palette[4] = {0xffffff, 0xd5e6f3, 0x2d5775, 0x2f99c9};
	CGFloat side = 8.0f;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side * 12, side * 12), YES, 0.0f);
	CGContextRef context = UIGraphicsGetCurrentContext();
	for (int i = 0; i < 144; i++){
		id value = cells[(NSUInteger)i];
		int index = [value isKindOfClass:NSNumber.class] ? ([value intValue] & 3) : 0;
		CGContextSetFillColorWithColor(context, TGContactsRGB(palette[index]).CGColor);
		CGContextFillRect(context, CGRectMake((i % 12) * side, (i / 12) * side, side, side));
	}
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

@interface TGSecretChatViewController : UITableViewController <UIActionSheetDelegate>
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, copy) NSString *peerName;
@property (nonatomic, assign) int secretChatId;
@property (nonatomic, copy) NSString *stateText;
@property (nonatomic, copy) NSString *sendText;
@property (nonatomic, assign) NSInteger ttl;
@property (nonatomic, assign) BOOL ttlKnown;
@property (nonatomic, assign) NSInteger defaultTtl;
@property (nonatomic, assign) BOOL defaultTtlKnown;
@property (nonatomic, strong) NSArray *ladder;
@end

@implementation TGSecretChatViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = self.peerName.length ? self.peerName : @"Secret Chat";
	self.stateText = @"Loading…";
	self.sendText = @"";
	self.ladder = [TGClient autoDeleteLadder];
	[self reloadState];
	[self reloadTimers];
	[self reloadKey];
}

- (NSString *)wordingForState:(NSString *)state {
	if ([state isEqualToString:@"ready"])
		return @"Ready";
	if ([state isEqualToString:@"pending"])
		return @"Waiting for the other side";
	if ([state isEqualToString:@"closed"])
		return @"Cancelled";
	return state.length ? state : @"Unknown";
}

- (void)reloadState {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] secretChatInfoForChat:self.chatId completion:^(NSDictionary *info){
		TGSecretChatViewController *me = weakSelf;
		if (!me)
			return;
		if (![info isKindOfClass:NSDictionary.class]){
			me.stateText = @"Unavailable";
			[me.tableView reloadData];
			return;
		}
		NSNumber *secretId = [info[@"secretChatId"] isKindOfClass:NSNumber.class]
				? info[@"secretChatId"] : nil;
		me.secretChatId = secretId ? secretId.intValue : 0;
		NSString *state = [info[@"state"] isKindOfClass:NSString.class] ? info[@"state"] : @"";
		me.stateText = [me wordingForState:state];
		if (!me.peerName.length){
			NSString *name = [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : nil;
			if (name.length){
				me.peerName = name;
				me.title = name;
			}
		}
		[me.tableView reloadData];
	}];
	[[TGClient shared] canSendInSecretChat:self.chatId
								completion:^(BOOL canSend, NSString *state){
		TGSecretChatViewController *me = weakSelf;
		if (!me)
			return;
		me.sendText = canSend ? @"" : @"You cannot send messages yet";
		[me.tableView reloadData];
	}];
}

- (void)reloadTimers {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] autoDeleteTimeForChat:self.chatId completion:^(NSInteger seconds){
		TGSecretChatViewController *me = weakSelf;
		if (!me)
			return;
		me.ttl = seconds;
		me.ttlKnown = YES;
		[me.tableView reloadData];
	}];
	[[TGClient shared] defaultAutoDeleteTimeWithCompletion:^(NSInteger seconds){
		TGSecretChatViewController *me = weakSelf;
		if (!me)
			return;
		me.defaultTtl = seconds;
		me.defaultTtlKnown = YES;
		[me.tableView reloadData];
	}];
}

- (void)reloadKey {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] encryptionKeyGridForChat:self.chatId completion:^(NSArray *cells){
		TGSecretChatViewController *me = weakSelf;
		if (!me)
			return;
		UIImage *image = TGSecretKeyImage(cells);
		if (!image)
			return;
		[[TGClient shared] encryptionKeyHashForChat:me.chatId completion:^(NSString *base64){
			TGSecretChatViewController *inner = weakSelf;
			if (!inner)
				return;
			[inner showKeyImage:image hash:base64];
		}];
	}];
}

- (void)showKeyImage:(UIImage *)image hash:(NSString *)base64 {
	CGFloat width = self.tableView.bounds.size.width;
	UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 210)];
	footer.backgroundColor = [UIColor clearColor];

	UIImageView *grid = [[UIImageView alloc] initWithImage:image];
	grid.frame = CGRectMake((CGFloat)(int)((width - 96) / 2), 14, 96, 96);
	grid.layer.borderColor = [UIColor colorWithWhite:0.0f alpha:0.15f].CGColor;
	grid.layer.borderWidth = 1.0f;
	[footer addSubview:grid];

	UILabel *caption = [[UILabel alloc] initWithFrame:CGRectMake(20, 118, width - 40, 30)];
	caption.backgroundColor = [UIColor clearColor];
	caption.numberOfLines = 2;
	caption.textAlignment = NSTextAlignmentCenter;
	caption.font = [UIFont systemFontOfSize:13];
	caption.textColor = [UIColor colorWithWhite:0.0f alpha:0.55f];
	caption.text = @"If this image looks the same on both devices, this chat is secure.";
	[footer addSubview:caption];

	UILabel *hashLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 152, width - 40, 46)];
	hashLabel.backgroundColor = [UIColor clearColor];
	hashLabel.numberOfLines = 3;
	hashLabel.lineBreakMode = NSLineBreakByCharWrapping;
	hashLabel.textAlignment = NSTextAlignmentCenter;
	hashLabel.font = [UIFont fontWithName:@"Courier" size:11] ?: [UIFont systemFontOfSize:11];
	hashLabel.textColor = [UIColor colorWithWhite:0.0f alpha:0.4f];
	hashLabel.text = [base64 isKindOfClass:NSString.class] ? base64 : @"";
	[footer addSubview:hashLabel];

	self.tableView.tableFooterView = footer;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 2 ? 1 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0)
		return @"Secret Chat";
	if (section == 1)
		return @"Self-Destruct Timer";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0 && self.sendText.length)
		return self.sendText;
	if (section == 1)
		return @"Messages sent to this chat are removed for both sides after the timer runs out.";
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGSecretChatCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:reuse];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.textColor = [UIColor blackColor];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.detailTextLabel.text = @"";
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;

	if (indexPath.section == 0){
		if (indexPath.row == 0){
			cell.textLabel.text = @"Status";
			cell.detailTextLabel.text = self.stateText;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		} else {
			cell.textLabel.text = @"Open Chat";
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
		return cell;
	}
	if (indexPath.section == 1){
		if (indexPath.row == 0){
			cell.textLabel.text = @"Timer";
			cell.detailTextLabel.text = self.ttlKnown
					? [TGClient autoDeleteTitleForSeconds:self.ttl] : @"…";
		} else {
			cell.textLabel.text = @"Default for New Chats";
			cell.detailTextLabel.text = self.defaultTtlKnown
					? [TGClient autoDeleteTitleForSeconds:self.defaultTtl] : @"…";
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	cell.textLabel.text = @"Terminate Secret Chat";
	cell.textLabel.textColor = TGContactsRGB(0xcc3333);
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	return cell;
}

- (void)showLadderWithTag:(NSInteger)tag title:(NSString *)title {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	for (NSDictionary *entry in self.ladder){
		NSString *entryTitle = [entry isKindOfClass:NSDictionary.class] ? entry[@"title"] : nil;
		if ([entryTitle isKindOfClass:NSString.class])
			[sheet addButtonWithTitle:entryTitle];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = tag;
	[sheet showInView:self.navigationController.view];
}

- (void)openChat {
	if (self.chatId != 0){
		TGChatViewController *vc = [[TGChatViewController alloc] init];
		vc.chatId = self.chatId;
		vc.chatTitle = self.peerName.length ? self.peerName : @"Secret Chat";
		[self.navigationController pushViewController:vc animated:YES];
		return;
	}
	if (self.secretChatId == 0){
		[[[UIAlertView alloc] initWithTitle:nil
									message:@"This secret chat is not available."
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] openSecretChatId:self.secretChatId completion:^(int64_t chatId){
		TGSecretChatViewController *me = weakSelf;
		if (!me)
			return;
		if (chatId == 0){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not open this secret chat."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		me.chatId = chatId;
		[me openChat];
	}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 0 && indexPath.row == 1){
		[self openChat];
		return;
	}
	if (indexPath.section == 1){
		if (indexPath.row == 0)
			[self showLadderWithTag:1 title:@"Self-Destruct Timer"];
		else
			[self showLadderWithTag:2 title:@"Default for New Chats"];
		return;
	}
	if (indexPath.section == 2){
		UIActionSheet *sheet = [[UIActionSheet alloc]
				initWithTitle:@"This secret chat will be terminated on both devices."
					 delegate:self
			cancelButtonTitle:nil
	   destructiveButtonTitle:@"Terminate"
			otherButtonTitles:@"Terminate and Delete History", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 3;
		[sheet showInView:self.navigationController.view];
	}
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;
	if (sheet.tag == 3){
		BOOL deleteHistory = (index != sheet.destructiveButtonIndex);
		[[TGClient shared] closeSecretChatForChat:self.chatId deleteHistory:deleteHistory];
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}
	if (index < 0 || index >= (NSInteger)self.ladder.count)
		return;
	NSDictionary *entry = self.ladder[(NSUInteger)index];
	if (![entry isKindOfClass:NSDictionary.class])
		return;
	NSInteger seconds = [entry[@"seconds"] integerValue];
	if (sheet.tag == 1){
		[[TGClient shared] setChat:self.chatId autoDeleteSeconds:seconds];
		self.ttl = seconds;
		self.ttlKnown = YES;
	} else {
		[[TGClient shared] setDefaultAutoDeleteTime:seconds];
		self.defaultTtl = seconds;
		self.defaultTtlKnown = YES;
	}
	[self.tableView reloadData];
	[self reloadTimers];
}

@end

@interface TGContactsViewController () <UISearchBarDelegate, UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *users;
@property (nonatomic, strong) NSArray *filteredUsers;
@property (nonatomic, strong) NSArray *sectionTitles;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSCache *photos;
@property (nonatomic, strong) NSMutableSet *photosRequested;
@property (nonatomic, strong) NSMutableSet *photosFailed;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSString *searchQuery;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, strong) UIView *phonebookAccessOverlay;
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) NSMutableSet *closeFriendIds;
@property (nonatomic, strong) NSMutableDictionary *badges;
@property (nonatomic, strong) NSMutableSet *badgesRequested;
@property (nonatomic, assign) NSInteger importedCount;
@property (nonatomic, assign) BOOL importedCountKnown;
@property (nonatomic, strong) NSDictionary *actionUser;
@property (nonatomic, strong) NSString *actionBirthdate;
@property (nonatomic, assign) BOOL actionSheetShown;
@property (nonatomic, strong) NSMutableDictionary *birthdays;
@property (nonatomic, strong) TGContactsProgressWindow *progress;
@property (nonatomic, assign) BOOL importing;
@property (nonatomic, strong) NSDictionary *pendingDeleteUser;
@property (nonatomic, copy) NSString *contactLink;
@property (nonatomic, assign) NSInteger contactLinkExpiresIn;
@property (nonatomic, strong) NSDate *contactLinkFetchedAt;
@property (nonatomic, assign) BOOL contactLinkRequested;
@property (nonatomic, assign) BOOL buildingInviteList;
@property (nonatomic, strong) NSMutableDictionary *contactFlags;
@property (nonatomic, strong) NSDictionary *actionFlags;
@property (nonatomic, assign) BOOL actionBirthdateReady;
@property (nonatomic, assign) BOOL actionFlagsReady;
@property (nonatomic, strong) NSArray *actionKeys;
@property (nonatomic, assign) BOOL birthdaysHidden;
@property (nonatomic, strong) NSArray *serverUsers;
@property (nonatomic, copy) NSString *serverQuery;
@property (nonatomic, strong) UIDatePicker *birthdayPicker;
@property (nonatomic, strong) UIActionSheet *birthdaySheet;
@property (nonatomic, strong) NSDictionary *birthdayUser;
@property (nonatomic, strong) NSDictionary *phoneShareUser;
@property (nonatomic, strong) NSDictionary *tokenUser;
@property (nonatomic, copy) NSString *myUsernameLink;
@property (nonatomic, strong) NSDictionary *myBirthdate;
@property (nonatomic, assign) BOOL myBirthdateKnown;
@property (nonatomic, assign) BOOL sortByFirstName;
@property (nonatomic, assign) BOOL displayFirstNameFirst;
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

static NSString *TGContactSortKey(NSDictionary *u, BOOL byFirstName) {
	NSString *primary = TGContactString(u, byFirstName ? @"first_name" : @"last_name");
	if (primary.length)
		return primary;
	NSString *secondary = TGContactString(u, byFirstName ? @"last_name" : @"first_name");
	if (secondary.length)
		return secondary;
	return TGContactName(u);
}

- (void)updateContactSortOrder {
	self.sortByFirstName = (ABPersonGetSortOrdering() != kABPersonSortByLastName);
	self.displayFirstNameFirst =
			(ABPersonGetCompositeNameFormat() != kABPersonCompositeNameFormatLastNameFirst);
}

- (void)addressBookOrderMayHaveChanged {
	BOOL sortByFirst = self.sortByFirstName;
	BOOL displayFirst = self.displayFirstNameFirst;
	[self updateContactSortOrder];
	if (sortByFirst == self.sortByFirstName && displayFirst == self.displayFirstNameFirst)
		return;
	[self refreshTable];
}

- (void)sortUsers {
	BOOL byFirstName = self.sortByFirstName;
	self.users = [self.users sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
		NSComparisonResult result = [TGContactSortKey(a, byFirstName)
				localizedCaseInsensitiveCompare:TGContactSortKey(b, byFirstName)];
		if (result != NSOrderedSame)
			return result;
		NSString *otherA = TGContactString(a, byFirstName ? @"last_name" : @"first_name");
		NSString *otherB = TGContactString(b, byFirstName ? @"last_name" : @"first_name");
		if (!otherA.length || !otherB.length)
			return NSOrderedSame;
		return [otherA localizedCaseInsensitiveCompare:otherB];
	}];
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
		[me reloadTableSoon];
	}];
}

- (NSInteger)contactLinkSecondsRemaining {
	if (!self.contactLink.length || !self.contactLinkFetchedAt || self.contactLinkExpiresIn <= 0)
		return 0;
	NSInteger elapsed = (NSInteger)(-[self.contactLinkFetchedAt timeIntervalSinceNow]);
	NSInteger left = self.contactLinkExpiresIn - elapsed;
	return left > 0 ? left : 0;
}

- (NSString *)shareableLink {
	return self.contactLink.length ? self.contactLink : self.myUsernameLink;
}

- (void)reloadMyUsernames {
	if (self.isPickerMode)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] myUsernamesWithCompletion:^(NSDictionary *usernames){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		NSString *pick = nil;
		if ([usernames isKindOfClass:NSDictionary.class]){
			NSArray *active = [usernames[@"active"] isKindOfClass:NSArray.class]
					? usernames[@"active"] : nil;
			for (NSString *one in active){
				if ([one isKindOfClass:NSString.class] && one.length){
					pick = one;
					break;
				}
			}
			if (!pick.length){
				NSString *editable = usernames[@"editable"];
				if ([editable isKindOfClass:NSString.class] && editable.length)
					pick = editable;
			}
		}
		NSString *link = pick.length
				? [NSString stringWithFormat:@"https://t.me/%@", pick] : nil;
		BOOL appears = (link.length && !me.myUsernameLink.length && !me.contactLink.length);
		me.myUsernameLink = link;
		if (appears)
			[me refreshTable];
		else
			[me reloadTableSoon];
	}];
}

- (NSString *)contactLinkSubtitle {
	NSString *display = [self shareableLink];
	for (NSString *prefix in @[@"https://", @"http://"]){
		if ([display hasPrefix:prefix])
			display = [display substringFromIndex:prefix.length];
	}
	NSInteger left = [self contactLinkSecondsRemaining];
	if (left <= 0)
		return display;
	if (left < 60)
		return [NSString stringWithFormat:@"%@ · %ds left", display, (int)left];
	return [NSString stringWithFormat:@"%@ · %d min left", display, (int)(left / 60)];
}

- (void)reloadContactLink {
	if (self.isPickerMode || self.contactLinkRequested)
		return;
	self.contactLinkRequested = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] myContactLinkWithCompletion:^(NSString *url, NSInteger expiresIn){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		me.contactLinkRequested = NO;
		if (![url isKindOfClass:NSString.class] || !url.length)
			return;
		BOOL appeared = (me.contactLink.length == 0);
		me.contactLink = url;
		me.contactLinkExpiresIn = expiresIn;
		me.contactLinkFetchedAt = [NSDate date];
		if (appeared)
			[me refreshTable];
		else
			[me reloadTableSoon];
	}];
}

- (void)contactLinkTapped {
	NSString *link = [self shareableLink];
	if (!link.length)
		return;
	if (self.contactLink.length && [self contactLinkSecondsRemaining] <= 0
			&& self.contactLinkExpiresIn > 0)
		[self reloadContactLink];
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:[self contactLinkSubtitle]
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:@"Copy Link", @"Share Link", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 4;
	[self presentSheet:sheet];
}

- (void)presentSheet:(UIActionSheet *)sheet {
	UITabBar *tabBar = [self.tabBarController isKindOfClass:UITabBarController.class]
			? self.tabBarController.tabBar : nil;
	if (tabBar)
		[sheet showFromTabBar:tabBar];
	else
		[sheet showInView:self.navigationController.view];
}

- (void)reloadMyBirthdate {
	if (self.isPickerMode)
		return;
	int64_t myId = [[TGClient shared].me[@"id"] longLongValue];
	if (myId == 0)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] birthdateForUser:myId completion:^(NSDictionary *birthdate){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		me.myBirthdate = [birthdate isKindOfClass:NSDictionary.class] ? birthdate : nil;
		me.myBirthdateKnown = YES;
	}];
}

- (NSString *)myBirthdateText {
	NSString *text = self.myBirthdate[@"text"];
	return ([text isKindOfClass:NSString.class] && text.length) ? text : nil;
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
	[sheet addButtonWithTitle:@"Add by Link"];
	NSString *mine = [self myBirthdateText];
	[sheet addButtonWithTitle:mine.length
			? [NSString stringWithFormat:@"My Birthday · %@", mine] : @"Set My Birthday"];
	if (mine.length)
		[sheet addButtonWithTitle:@"Remove My Birthday"];
	if (!self.birthdaysHidden && [self hasAnyBirthdayToday])
		[sheet addButtonWithTitle:@"Hide Birthdays Today"];
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
	if (!indexPath || [self actionIdentifierAtIndexPath:indexPath])
		return;
	NSDictionary *u = [self userAtIndexPath:indexPath];
	if (!u)
		return;
	self.actionUser = u;
	self.actionBirthdate = nil;
	self.actionFlags = nil;
	self.actionSheetShown = NO;
	self.actionBirthdateReady = NO;
	self.actionFlagsReady = NO;

	NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
	id cached = userId ? self.birthdays[userId] : nil;
	if (cached){
		if ([cached isKindOfClass:NSDictionary.class])
			self.actionBirthdate = [self birthdayTextFrom:cached];
		self.actionBirthdateReady = YES;
	}
	NSDictionary *cachedFlags = userId ? self.contactFlags[userId] : nil;
	if (cachedFlags){
		self.actionFlags = cachedFlags;
		self.actionFlagsReady = YES;
	}
	if (self.actionBirthdateReady && self.actionFlagsReady){
		[self showContactActions];
		return;
	}

	[self requestActionDetailsForUser:u userId:userId];
}

- (void)requestActionDetailsForUser:(NSDictionary *)u userId:(NSNumber *)userId {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(showContactActions)
											   object:nil];
	[self performSelector:@selector(showContactActions) withObject:nil afterDelay:0.4f];
	__weak typeof(self) weakSelf = self;
	if (!self.actionBirthdateReady){
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
			me.actionBirthdateReady = YES;
			[me showContactActionsWhenReady];
		}];
	}
	if (!self.actionFlagsReady){
		[[TGClient shared] contactFlagsForUser:[u[@"id"] longLongValue]
									completion:^(NSDictionary *flags){
			TGContactsViewController *me = weakSelf;
			if (!me)
				return;
			if (userId)
				me.contactFlags[userId] = [flags isKindOfClass:NSDictionary.class] ? flags : @{};
			if (me.actionUser != u)
				return;
			if ([flags isKindOfClass:NSDictionary.class])
				me.actionFlags = flags;
			me.actionFlagsReady = YES;
			[me showContactActionsWhenReady];
		}];
	}
}

- (void)showContactActionsWhenReady {
	if (self.actionBirthdateReady && self.actionFlagsReady)
		[self showContactActions];
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
	if (self.birthdaysHidden)
		return NO;
	NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
	id cached = userId ? self.birthdays[userId] : nil;
	return [cached isKindOfClass:NSDictionary.class] && [self isBirthdayToday:cached];
}

- (BOOL)hasAnyBirthdayToday {
	for (id cached in self.birthdays.allValues){
		if ([cached isKindOfClass:NSDictionary.class] && [self isBirthdayToday:cached])
			return YES;
	}
	return NO;
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
	BOOL mutual = [self.actionFlags[@"isMutualContact"] boolValue];
	if ([self.actionFlags[@"isSupport"] boolValue])
		[title appendString:@"\nTelegram Support"];
	else if (mutual)
		[title appendString:@"\nMutual contact"];

	NSMutableArray *keys = [NSMutableArray array];
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:nil];
	[sheet addButtonWithTitle:close ? @"Remove from Close Friends" : @"Add to Close Friends"];
	[keys addObject:@"closeFriend"];
	[sheet addButtonWithTitle:@"Send Message"];
	[keys addObject:@"message"];
	[sheet addButtonWithTitle:@"Start Secret Chat"];
	[keys addObject:@"secret"];
	if (!mutual){
		[sheet addButtonWithTitle:@"Share My Phone Number"];
		[keys addObject:@"sharePhone"];
	}
	if (!self.actionBirthdate.length){
		[sheet addButtonWithTitle:@"Suggest Birthday"];
		[keys addObject:@"suggestBirthday"];
	}
	sheet.destructiveButtonIndex = [sheet addButtonWithTitle:@"Delete Contact"];
	[keys addObject:@"delete"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	self.actionKeys = keys;
	sheet.tag = 2;
	[self presentSheet:sheet];
}

- (void)startSecretChatWithUser:(NSDictionary *)u {
	NSString *name = TGContactName(u);
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] createSecretChatWithUser:[u[@"id"] longLongValue]
									 completion:^(NSDictionary *info){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		if (![info isKindOfClass:NSDictionary.class]){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not start a secret chat."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		TGSecretChatViewController *vc = [[TGSecretChatViewController alloc] init];
		vc.chatId = [info[@"chatId"] longLongValue];
		vc.secretChatId = [info[@"secretChatId"] intValue];
		vc.userId = [u[@"id"] longLongValue];
		vc.peerName = name;
		if (vc.chatId == 0 && vc.secretChatId == 0){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not start a secret chat."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		if (vc.chatId == 0){
			[[TGClient shared] openSecretChatId:vc.secretChatId completion:^(int64_t chatId){
				TGContactsViewController *inner = weakSelf;
				if (!inner)
					return;
				if (chatId == 0){
					[[[UIAlertView alloc] initWithTitle:nil
												message:@"Could not open the new secret chat."
											   delegate:nil
									  cancelButtonTitle:@"OK"
									  otherButtonTitles:nil] show];
					return;
				}
				vc.chatId = chatId;
				[inner openTarget:vc];
			}];
			return;
		}
		[me openTarget:vc];
	}];
}

- (void)confirmSharePhoneWithUser:(NSDictionary *)u {
	self.phoneShareUser = u;
	UIAlertView *alert = [[UIAlertView alloc]
			initWithTitle:nil
				  message:[NSString stringWithFormat:@"Let %@ see your phone number?",
						  TGContactName(u)]
				 delegate:self
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@"Share", nil];
	alert.tag = 12;
	[alert show];
}

- (void)showBirthdayPickerForUser:(NSDictionary *)u {
	self.birthdayUser = u;
	[self showBirthdayPickerWithDoneTitle:@"Suggest"
									action:@selector(sendBirthdaySuggestion)
							   initialDate:nil];
}

- (void)showBirthdayPickerForSelf {
	self.birthdayUser = nil;
	NSDate *initial = nil;
	NSInteger day = [self.myBirthdate[@"day"] integerValue];
	NSInteger month = [self.myBirthdate[@"month"] integerValue];
	if (day > 0 && month > 0){
		NSDateComponents *parts = [[NSDateComponents alloc] init];
		parts.day = day;
		parts.month = month;
		NSInteger year = [self.myBirthdate[@"year"] integerValue];
		if (year <= 0){
			NSDateComponents *now = [[NSCalendar currentCalendar]
					components:NSYearCalendarUnit fromDate:[NSDate date]];
			year = now.year;
		}
		parts.year = year;
		initial = [[NSCalendar currentCalendar] dateFromComponents:parts];
	}
	[self showBirthdayPickerWithDoneTitle:@"Save"
									action:@selector(saveMyBirthday)
							   initialDate:initial];
}

- (void)showBirthdayPickerWithDoneTitle:(NSString *)doneTitle
								 action:(SEL)action
							initialDate:(NSDate *)initialDate {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
	sheet.tag = 5;

	CGFloat sheetWidth = self.navigationController.view.bounds.size.width;
	if (sheetWidth < 1.0f)
		sheetWidth = self.view.bounds.size.width;
	if (sheetWidth < 1.0f)
		sheetWidth = TGContactsScreenWidth();
	UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, sheetWidth, 44)];
	bar.barStyle = UIBarStyleBlackTranslucent;
	UIBarButtonItem *cancel = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
								 target:self action:@selector(dismissBirthdaySheet)];
	UIBarButtonItem *space = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
								 target:nil action:nil];
	UIBarButtonItem *done = [[UIBarButtonItem alloc]
			initWithTitle:doneTitle style:UIBarButtonItemStyleDone
				   target:self action:action];
	bar.items = @[cancel, space, done];
	[sheet addSubview:bar];

	UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:
			CGRectMake(0, 44, sheetWidth, 216)];
	picker.datePickerMode = UIDatePickerModeDate;
	picker.maximumDate = [NSDate date];
	if (initialDate)
		picker.date = initialDate;
	[sheet addSubview:picker];
	self.birthdayPicker = picker;
	self.birthdaySheet = sheet;

	[sheet showInView:self.navigationController.view];
	[sheet setBounds:CGRectMake(0, 0, sheetWidth, 320)];
}

- (void)dismissBirthdaySheet {
	[self.birthdaySheet dismissWithClickedButtonIndex:-1 animated:YES];
	self.birthdaySheet = nil;
	self.birthdayPicker = nil;
	self.birthdayUser = nil;
}

- (void)sendBirthdaySuggestion {
	NSDictionary *u = self.birthdayUser;
	NSDate *date = self.birthdayPicker.date;
	[self.birthdaySheet dismissWithClickedButtonIndex:-1 animated:YES];
	self.birthdaySheet = nil;
	self.birthdayPicker = nil;
	self.birthdayUser = nil;
	if (!u || !date)
		return;
	NSDateComponents *parts = [[NSCalendar currentCalendar]
			components:(NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit)
			  fromDate:date];
	[[TGClient shared] suggestBirthdateToUser:[u[@"id"] longLongValue]
										  day:parts.day
										month:parts.month
										 year:parts.year
								   completion:^(BOOL ok){
		[[[UIAlertView alloc] initWithTitle:nil
									message:ok ? @"Birthday suggested."
											   : @"Could not suggest a birthday."
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
	}];
}

- (void)saveMyBirthday {
	NSDate *date = self.birthdayPicker.date;
	[self.birthdaySheet dismissWithClickedButtonIndex:-1 animated:YES];
	self.birthdaySheet = nil;
	self.birthdayPicker = nil;
	self.birthdayUser = nil;
	if (!date)
		return;
	NSDateComponents *parts = [[NSCalendar currentCalendar]
			components:(NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit)
			  fromDate:date];
	if (parts.day <= 0 || parts.month <= 0)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setMyBirthdateDay:parts.day
								   month:parts.month
									year:parts.year
							  completion:^(BOOL ok){
		TGContactsViewController *me = weakSelf;
		[[[UIAlertView alloc] initWithTitle:nil
									message:ok ? @"Your birthday is saved."
											   : @"Could not save your birthday."
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
		if (ok)
			[me reloadMyBirthdate];
	}];
}

- (void)confirmRemoveMyBirthday {
	UIAlertView *alert = [[UIAlertView alloc]
			initWithTitle:nil
				  message:@"Remove your birthday from your profile?"
				 delegate:self
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@"Remove", nil];
	alert.tag = 13;
	[alert show];
}

- (void)removeMyBirthday {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setMyBirthdateDay:0 month:0 year:0 completion:^(BOOL ok){
		TGContactsViewController *me = weakSelf;
		if (!ok){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not remove your birthday."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		me.myBirthdate = nil;
		[me reloadMyBirthdate];
	}];
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
		[me openTarget:vc];
	}];
}

- (void)handleContactSheetAtIndex:(NSInteger)index {
	NSDictionary *u = self.actionUser;
	self.actionUser = nil;
	if (!u || index < 0 || index >= (NSInteger)self.actionKeys.count)
		return;
	NSString *key = self.actionKeys[(NSUInteger)index];
	if ([key isEqualToString:@"closeFriend"])
		[self toggleCloseFriendForUser:u];
	else if ([key isEqualToString:@"message"])
		[self openChatWithUser:u];
	else if ([key isEqualToString:@"secret"])
		[self startSecretChatWithUser:u];
	else if ([key isEqualToString:@"sharePhone"])
		[self confirmSharePhoneWithUser:u];
	else if ([key isEqualToString:@"suggestBirthday"])
		[self showBirthdayPickerForUser:u];
	else if ([key isEqualToString:@"delete"])
		[self confirmDeleteContact:u];
}

- (void)clearImportedContacts {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] clearImportedContactsWithCompletion:^(BOOL ok){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		[me reloadImportedCount];
		if (ok)
			[me reloadContacts];
	}];
}

- (void)handleImportSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	NSString *title = [sheet buttonTitleAtIndex:index];
	if ([title isEqualToString:@"Add by Link"]){
		[self promptForContactToken];
		return;
	}
	if ([title isEqualToString:@"Remove My Birthday"]){
		[self confirmRemoveMyBirthday];
		return;
	}
	if ([title hasPrefix:@"My Birthday"] || [title isEqualToString:@"Set My Birthday"]){
		[self showBirthdayPickerForSelf];
		return;
	}
	if ([title isEqualToString:@"Hide Birthdays Today"]){
		[[TGClient shared] hideContactCloseBirthdays];
		self.birthdaysHidden = YES;
		[self.tableView reloadData];
		return;
	}
	if (index == sheet.destructiveButtonIndex){
		[self clearImportedContacts];
		return;
	}
	if ([[sheet buttonTitleAtIndex:index] isEqualToString:@"Sync Contacts"])
		[self startAddressBookImport];
}

- (void)handleLinkSheetAtIndex:(NSInteger)index {
	NSString *link = [self shareableLink];
	if (!link.length)
		return;
	if (index == 0){
		[UIPasteboard generalPasteboard].string = link;
		return;
	}
	if (index == 1){
		UIActivityViewController *share = [[UIActivityViewController alloc]
				initWithActivityItems:@[link] applicationActivities:nil];
		[self presentViewController:share animated:YES completion:nil];
	}
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;
	if (sheet.tag == 2){
		[self handleContactSheetAtIndex:index];
		return;
	}
	if (sheet.tag == 3){
		[self handleImportSheet:sheet clickedButtonAtIndex:index];
		return;
	}
	if (sheet.tag == 4)
		[self handleLinkSheetAtIndex:index];
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
	alert.tag = 1;
	[alert show];
}

- (void)promptForContactToken {
	UIAlertView *alert = [[UIAlertView alloc]
			initWithTitle:@"Add by Link"
				  message:@"Paste the t.me link someone shared with you."
				 delegate:self
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@"Look Up", nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	alert.tag = 10;
	NSString *pasted = [UIPasteboard generalPasteboard].string;
	if ([pasted isKindOfClass:NSString.class] && [pasted rangeOfString:@"t.me"].length)
		[alert textFieldAtIndex:0].text = pasted;
	[alert show];
}

- (NSString *)tokenFromLink:(NSString *)link {
	NSString *text = [link stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSRange marker = [text rangeOfString:@"contact/"];
	if (marker.length)
		return [text substringFromIndex:marker.location + marker.length];
	NSRange slash = [text rangeOfString:@"/" options:NSBackwardsSearch];
	if (slash.length && slash.location + 1 < text.length)
		return [text substringFromIndex:slash.location + 1];
	return text;
}

- (void)lookUpContactToken:(NSString *)token {
	if (!token.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userForToken:token completion:^(NSDictionary *user){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		if (![user isKindOfClass:NSDictionary.class] || !user[@"id"]){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"This link is not valid any more."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		me.tokenUser = user;
		UIAlertView *confirm = [[UIAlertView alloc]
				initWithTitle:nil
					  message:[NSString stringWithFormat:@"Add %@ to your contacts?",
							  TGContactName(user)]
					 delegate:me
			cancelButtonTitle:@"Cancel"
			otherButtonTitles:@"Add", nil];
		confirm.tag = 11;
		[confirm show];
	}];
}

- (void)addTokenUser:(NSDictionary *)user {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] addContactWithUserId:[user[@"id"] longLongValue]
									  phone:TGContactString(user, @"phone")
								  firstName:TGContactString(user, @"first_name")
								   lastName:TGContactString(user, @"last_name")
						   sharePhoneNumber:NO
								 completion:^(BOOL ok){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[[[UIAlertView alloc] initWithTitle:nil
										message:@"Could not add this contact."
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
			return;
		}
		[me reloadContacts];
	}];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
	if (alertView.tag == 10){
		if (index == alertView.cancelButtonIndex)
			return;
		[self lookUpContactToken:[self tokenFromLink:[alertView textFieldAtIndex:0].text ?: @""]];
		return;
	}
	if (alertView.tag == 11){
		NSDictionary *user = self.tokenUser;
		self.tokenUser = nil;
		if (index == alertView.cancelButtonIndex || !user)
			return;
		[self addTokenUser:user];
		return;
	}
	if (alertView.tag == 13){
		if (index == alertView.cancelButtonIndex)
			return;
		[self removeMyBirthday];
		return;
	}
	if (alertView.tag == 12){
		NSDictionary *u = self.phoneShareUser;
		self.phoneShareUser = nil;
		if (index == alertView.cancelButtonIndex || !u)
			return;
		[[TGClient shared] sharePhoneNumberWithUser:[u[@"id"] longLongValue]];
		NSNumber *userId = [u[@"id"] isKindOfClass:NSNumber.class] ? u[@"id"] : nil;
		if (userId)
			[self.contactFlags removeObjectForKey:userId];
		[[[UIAlertView alloc] initWithTitle:nil
									message:[NSString stringWithFormat:
											@"%@ can now see your phone number.", TGContactName(u)]
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
		return;
	}
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
	NSMutableSet *seen = [NSMutableSet set];
	for (NSDictionary *u in self.users){
		if (![self matchesQuery:u query:query])
			continue;
		[out addObject:u];
		[seen addObject:@([u[@"id"] longLongValue])];
	}
	if ([self.serverQuery isEqualToString:query]){
		for (NSDictionary *u in self.serverUsers){
			if (![u isKindOfClass:NSDictionary.class])
				continue;
			NSNumber *key = @([u[@"id"] longLongValue]);
			if (key.longLongValue == 0 || [seen containsObject:key])
				continue;
			[seen addObject:key];
			[out addObject:u];
		}
	}
	self.filteredUsers = out;
}

- (void)runServerContactSearch {
	NSString *query = [self.searchQuery
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (query.length < 2)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchContacts:query limit:30 completion:^(NSArray *users){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		NSString *current = [me.searchQuery
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (![current isEqualToString:query])
			return;
		me.serverQuery = query;
		me.serverUsers = [users isKindOfClass:NSArray.class] ? users : @[];
		[me applyFilter];
		[me rebuildSections];
		[me.tableView reloadData];
	}];
}

- (NSArray *)actionRowIdentifiers {
	if (self.isPickerMode || self.filteredUsers)
		return nil;
	NSMutableArray *rows = [NSMutableArray arrayWithObjects:
			TGContactActionInvite, TGContactActionNewGroup, TGContactActionSync, nil];
	if ([self shareableLink].length)
		[rows addObject:TGContactActionLink];
	return rows;
}

- (void)rebuildSections {
	if (self.filteredUsers){
		self.sectionTitles = nil;
		self.sections = nil;
		return;
	}
	NSMutableArray *titles = [NSMutableArray array];
	NSMutableArray *groups = [NSMutableArray array];
	for (NSDictionary *u in self.users){
		NSString *key = TGContactSortKey(u, self.sortByFirstName);
		NSString *letter = key.length
				? [key substringToIndex:1].capitalizedString : @"#";
		if (![letter rangeOfCharacterFromSet:
				[NSCharacterSet letterCharacterSet]].length)
			letter = @"#";
		if (![titles.lastObject isEqual:letter]){
			[titles addObject:letter];
			[groups addObject:[NSMutableArray array]];
		}
		[groups.lastObject addObject:u];
	}

	if (!self.isPickerMode){
		NSArray *actions = [self actionRowIdentifiers];
		if (actions.count){
			[titles insertObject:[NSNull null] atIndex:0];
			[groups insertObject:actions atIndex:0];
		}
	}

	self.sectionTitles = titles;
	self.sections = groups;
}

- (NSString *)letterForSection:(NSInteger)section {
	if (!self.sectionTitles || section < 0 || section >= (NSInteger)self.sectionTitles.count)
		return nil;
	id title = self.sectionTitles[section];
	return [title isKindOfClass:NSString.class] ? title : nil;
}

- (NSString *)actionIdentifierAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *rows = [self rowsForSection:indexPath.section];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count)
		return nil;
	id row = rows[indexPath.row];
	return [row isKindOfClass:NSString.class] ? row : nil;
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

- (BOOL)phonebookAccessDenied {
	ABAuthorizationStatus status = ABAddressBookGetAuthorizationStatus();
	return status == kABAuthorizationStatusDenied
			|| status == kABAuthorizationStatusRestricted;
}

- (void)layoutPhonebookAccessOverlay {
	if (!self.phonebookAccessOverlay)
		return;
	UIView *container = [self.phonebookAccessOverlay viewWithTag:100];
	UIImageView *iconView = (UIImageView *)[self.phonebookAccessOverlay viewWithTag:200];
	UILabel *titleLabel = (UILabel *)[self.phonebookAccessOverlay viewWithTag:300];
	UILabel *subtitleLabel = (UILabel *)[self.phonebookAccessOverlay viewWithTag:400];

	CGSize overlaySize = self.phonebookAccessOverlay.bounds.size;
	container.frame = CGRectMake((CGFloat)(int)((overlaySize.width - 40) / 2),
			(CGFloat)(int)((overlaySize.height - 4) / 2), 40, 4);
	CGFloat containerWidth = container.frame.size.width;
	CGFloat additionalOffset = ([UIScreen mainScreen].bounds.size.height > 480.5f) ? -20 : -15;

	CGSize iconSize = iconView.image ? iconView.image.size : CGSizeZero;
	iconView.frame = CGRectMake((CGFloat)(int)((containerWidth - iconSize.width) / 2),
			-113 + additionalOffset, iconSize.width, iconSize.height);

	CGFloat textLimit = MAX(200.0f, overlaySize.width - 55.0f);
	CGSize titleSize = [titleLabel sizeThatFits:CGSizeMake(MIN(420.0f, textLimit), 1000)];
	titleLabel.frame = CGRectMake((CGFloat)(int)((containerWidth - titleSize.width) / 2),
			-10 + additionalOffset, titleSize.width, titleSize.height);

	CGSize subtitleSize = [subtitleLabel sizeThatFits:
			CGSizeMake(MIN(340.0f, textLimit * 210.0f / 265.0f), 1000)];
	subtitleLabel.frame = CGRectMake((CGFloat)(int)((containerWidth - subtitleSize.width) / 2),
			41 + additionalOffset, subtitleSize.width, subtitleSize.height);
}

- (void)updatePhonebookAccess {
	BOOL denied = [self phonebookAccessDenied];
	if (!denied){
		if (self.phonebookAccessOverlay){
			[self.phonebookAccessOverlay removeFromSuperview];
			self.phonebookAccessOverlay = nil;
			self.tableView.scrollEnabled = YES;
			self.addButton.hidden = NO;
		}
		return;
	}
	if (self.phonebookAccessOverlay)
		return;

	UIView *overlay = [self buildPhonebookAccessOverlay];
	[self.view addSubview:overlay];
	self.phonebookAccessOverlay = overlay;
	self.tableView.scrollEnabled = NO;
	self.addButton.hidden = YES;
	[self layoutPhonebookAccessOverlay];
}

- (UILabel *)buildPhonebookAccessSubtitleLabel {
	CGFloat bodySize = ([UIScreen mainScreen].scale > 1.5f) ? 14.5f : 15.0f;
	NSString *body = @"Please go to your iPhone Settings — Privacy — Contacts."
			" Then select ON for Telegram.";
	UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	subtitleLabel.tag = 400;
	subtitleLabel.backgroundColor = [UIColor clearColor];
	subtitleLabel.font = [UIFont boldSystemFontOfSize:bodySize];
	subtitleLabel.textColor = TGContactsRGB(0x697487);
	subtitleLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.3f];
	subtitleLabel.shadowOffset = CGSizeMake(0, 1);
	subtitleLabel.numberOfLines = 0;
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	if ([UILabel instancesRespondToSelector:@selector(setAttributedText:)]){
		NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
				initWithString:body
					attributes:@{NSFontAttributeName : [UIFont systemFontOfSize:bodySize],
								 NSForegroundColorAttributeName : TGContactsRGB(0x697487)}];
		NSRange range = [body rangeOfString:@"ON"];
		if (range.length)
			[text addAttribute:NSFontAttributeName
						 value:[UIFont boldSystemFontOfSize:bodySize]
						 range:range];
		subtitleLabel.attributedText = text;
	} else {
		subtitleLabel.text = body;
	}
	return subtitleLabel;
}

- (UIView *)buildPhonebookAccessOverlay {
	UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
	overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	UIImage *lines = [UIImage imageNamed:@"SettingsBackground"];
	overlay.backgroundColor = lines
			? [UIColor colorWithPatternImage:lines] : TGContactsRGB(0xe4e9f0);

	UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
	container.tag = 100;
	container.backgroundColor = [UIColor clearColor];
	container.clipsToBounds = NO;
	container.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin
			| UIViewAutoresizingFlexibleTopMargin
			| UIViewAutoresizingFlexibleBottomMargin;
	[overlay addSubview:container];

	UIImageView *iconView = [[UIImageView alloc] initWithImage:
			[UIImage imageNamed:@"ContactsIcon"]];
	iconView.tag = 200;
	[container addSubview:iconView];

	UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	titleLabel.tag = 300;
	titleLabel.backgroundColor = [UIColor clearColor];
	titleLabel.font = [UIFont boldSystemFontOfSize:17];
	titleLabel.textColor = TGContactsRGB(0x697487);
	titleLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.3f];
	titleLabel.shadowOffset = CGSizeMake(0, 1);
	titleLabel.numberOfLines = 0;
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.text = @"Telegram does not have access to your contacts";
	[container addSubview:titleLabel];

	[container addSubview:[self buildPhonebookAccessSubtitleLabel]];

	return overlay;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	if (self.phonebookAccessOverlay){
		self.phonebookAccessOverlay.frame = CGRectMake(self.tableView.contentOffset.x,
				self.tableView.contentOffset.y,
				self.tableView.bounds.size.width, self.tableView.bounds.size.height);
		[self layoutPhonebookAccessOverlay];
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self updatePhonebookAccess];
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

- (void)styleSearchField:(UIView *)view {
	if ([view isKindOfClass:UITextField.class]){
		UITextField *field = (UITextField *)view;
		field.background = nil;
		field.clipsToBounds = NO;
		UIImage *inputImage = [UIImage imageNamed:@"SearchInputField"];
		if (inputImage){
			inputImage = [inputImage stretchableImageWithLeftCapWidth:
					(int)(inputImage.size.width / 2) topCapHeight:0];
			UIImageView *inputView = [[UIImageView alloc] initWithFrame:
					CGRectMake(0, ([UIScreen mainScreen].scale > 1.5f) ? 0.5f : 0,
							field.frame.size.width, inputImage.size.height)];
			inputView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
			inputView.image = inputImage;
			[field addSubview:inputView];
			[field sendSubviewToBack:inputView];
		}
		UIImage *icon = [UIImage imageNamed:@"SearchBarIcon"];
		if (icon && [field.leftView isKindOfClass:UIImageView.class]){
			UIImageView *iconView = (UIImageView *)field.leftView;
			iconView.image = icon;
			[iconView sizeToFit];
		}
	}
	for (UIView *child in view.subviews)
		[self styleSearchField:child];
}

- (void)hideStripe:(UIView *)view {
	if ([view isKindOfClass:UIImageView.class] && view.frame.size.height == 1)
		view.hidden = YES;
	for (UIView *child in view.subviews)
		[self hideStripe:child];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	if (!self.title.length)
		self.title = @"Contacts";
	[self updateContactSortOrder];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.users = @[];
	self.photos = [[NSCache alloc] init];
	self.photos.countLimit = kContactPhotoCacheCount;
	self.photos.totalCostLimit = kContactPhotoCacheBytes;
	self.photosRequested = [NSMutableSet set];
	self.photosFailed = [NSMutableSet set];
	self.closeFriendIds = [NSMutableSet set];
	self.badges = [NSMutableDictionary dictionary];
	self.badgesRequested = [NSMutableSet set];
	self.birthdays = [NSMutableDictionary dictionary];
	self.contactFlags = [NSMutableDictionary dictionary];
	self.tableView.rowHeight = kContactRowHeight;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.separatorStyle = [[TGTheme shared] isFlat]
			? UITableViewCellSeparatorStyleSingleLine
			: UITableViewCellSeparatorStyleNone;

	[self buildOverscrollView];
	[self buildSearchBar];
	[self buildTableBackground];

	if (!self.isPickerMode && [self respondsToSelector:@selector(setRefreshControl:)]
			&& NSClassFromString(@"UIRefreshControl")){
		UIRefreshControl *refresh = [[NSClassFromString(@"UIRefreshControl") alloc] init];
		[refresh addTarget:self action:@selector(reloadContacts)
		  forControlEvents:UIControlEventValueChanged];
		self.refreshControl = refresh;
	}

	if (!self.isPickerMode)
		[self buildAddButton];

	self.tableView.tableFooterView = [[UIView alloc] init];

	if (!self.isPickerMode){
		UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
				initWithTarget:self action:@selector(longPressed:)];
		press.minimumPressDuration = 0.5f;
		[self.tableView addGestureRecognizer:press];
	}

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(userStatusChanged:)
				name:TGUserStatusDidChangeNotification
			  object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(addressBookOrderMayHaveChanged)
				name:UIApplicationWillEnterForegroundNotification
			  object:nil];

	[self updatePhonebookAccess];
	[self loadInitialContactData];
}

- (void)loadInitialContactData {
	[self reloadContacts];
	if (!self.isPickerMode){
		[self reloadCloseFriends];
		[self reloadImportedCount];
		[self reloadContactLink];
		[self reloadMyUsernames];
		[self reloadMyBirthdate];
	}
}

- (void)buildOverscrollView {
	UIView *overscroll = [[UIView alloc] initWithFrame:
			CGRectMake(0, -500, self.tableView.bounds.size.width, 500)];
	overscroll.backgroundColor = TGContactsRGB(0xe4e9f0);
	overscroll.opaque = YES;
	overscroll.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.tableView addSubview:overscroll];
}

- (void)buildSearchBar {
	self.searchBar = [[UISearchBar alloc] initWithFrame:
			CGRectMake(0, 0, self.tableView.bounds.size.width, 44)];
	self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.searchBar.delegate = self;
	self.searchBar.placeholder = @"Search";
	UIImage *searchBackground = [UIImage imageNamed:@"SearchBarBackground"];
	if (searchBackground && [self.searchBar respondsToSelector:@selector(setBackgroundImage:)])
		[self.searchBar setBackgroundImage:searchBackground];
	else if (![self.searchBar respondsToSelector:@selector(setBackgroundImage:)])
		[self.searchBar tg_setTintColor:[UIColor colorWithWhite:0.68f alpha:1.0f]];
	self.tableView.tableHeaderView = self.searchBar;
	[self styleSearchField:self.searchBar];
	[self hideStripe:self.searchBar];
}

- (void)buildTableBackground {
	UIView *background = [[UIView alloc] initWithFrame:self.tableView.bounds];
	background.backgroundColor = [[TGTheme shared] listBackgroundColour];
	background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.backgroundView = background;
}

- (void)buildAddButton {
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
	UIImage *addIcon = [UIImage imageNamed:@"AddIcon"];
	if (addIcon){
		plus.hidden = YES;
		[add setImage:addIcon forState:UIControlStateNormal];
		add.frame = CGRectMake(0, 0, MAX(35.0f, addIcon.size.width + 12), 30);
	}
	[add addSubview:plus];
	self.addButton = add;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:add];
}

- (NSString *)inviteMessageText {
	NSString *link = [self shareableLink];
	if (!link.length){
		link = nil;
		NSDictionary *me = [TGClient shared].me;
		NSDictionary *usernameBox = [me isKindOfClass:NSDictionary.class] ? me[@"usernames"] : nil;
		NSArray *usernames = [usernameBox isKindOfClass:NSDictionary.class]
				? usernameBox[@"active_usernames"] : nil;
		NSString *username = ([usernames isKindOfClass:NSArray.class] && usernames.count)
				? usernames[0] : nil;
		if ([username isKindOfClass:NSString.class] && username.length)
			link = [NSString stringWithFormat:@"https://t.me/%@", username];
	}
	if (!link)
		link = @"https://telegram.org";
	return [NSString stringWithFormat:
			@"Hey, I'm using Telegram to chat. You can join me here: %@", link];
}

- (NSArray *)dedupedInviteEntries:(NSArray *)entries {
	NSMutableSet *seen = [NSMutableSet set];
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *entry in entries){
		NSString *first = TGContactString(entry, @"first_name");
		NSString *last = TGContactString(entry, @"last_name");
		NSString *phone = TGContactString(entry, @"phone");
		if (!phone.length)
			continue;
		NSString *key = (first.length || last.length)
				? [[NSString stringWithFormat:@"%@|%@", first, last] lowercaseString]
				: [@"#" stringByAppendingString:phone];
		if ([seen containsObject:key])
			continue;
		[seen addObject:key];
		[out addObject:entry];
	}
	return [out sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
		NSString *nameA = [[NSString stringWithFormat:@"%@ %@",
				TGContactString(a, @"first_name"), TGContactString(a, @"last_name")]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *nameB = [[NSString stringWithFormat:@"%@ %@",
				TGContactString(b, @"first_name"), TGContactString(b, @"last_name")]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (!nameA.length)
			nameA = TGContactString(a, @"phone");
		if (!nameB.length)
			nameB = TGContactString(b, @"phone");
		return [nameA localizedCaseInsensitiveCompare:nameB];
	}];
}

- (void)finishInviteListWithEntries:(NSArray *)entries userIds:(NSArray *)userIds {
	self.buildingInviteList = NO;
	[self.progress dismiss];
	self.progress = nil;

	NSMutableArray *missing = [NSMutableArray array];
	BOOL haveIds = ([userIds isKindOfClass:NSArray.class] && userIds.count == entries.count);
	for (NSUInteger i = 0; i < entries.count; i++){
		if (haveIds){
			NSNumber *userId = userIds[i];
			if ([userId isKindOfClass:NSNumber.class] && userId.longLongValue != 0)
				continue;
		}
		[missing addObject:entries[i]];
	}
	NSArray *list = [self dedupedInviteEntries:missing];
	if (!list.count){
		[[[UIAlertView alloc] initWithTitle:nil
								   message:@"Everyone in your address book is already on Telegram."
								  delegate:nil
						 cancelButtonTitle:@"OK"
						 otherButtonTitles:nil] show];
		return;
	}
	TGInviteFriendsViewController *vc = [[TGInviteFriendsViewController alloc] init];
	vc.entries = list;
	vc.inviteText = [self inviteMessageText];
	[self.navigationController pushViewController:vc animated:YES];
	[self reloadImportedCount];
}

- (void)shareInviteLinkDirectly {
	UIActivityViewController *sheet = [[UIActivityViewController alloc]
			initWithActivityItems:@[[self inviteMessageText]] applicationActivities:nil];
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)inviteFriendsTapped {
	if (self.buildingInviteList || self.importing)
		return;
	ABAddressBookRef book = ABAddressBookCreateWithOptions(NULL, NULL);
	if (!book){
		[self shareInviteLinkDirectly];
		return;
	}
	self.buildingInviteList = YES;
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
				me.buildingInviteList = NO;
				[me.progress dismiss];
				me.progress = nil;
				[me shareInviteLinkDirectly];
				return;
			}
			NSArray *entries = [me addressBookEntriesFrom:book];
			CFRelease(book);
			if (!entries.count){
				me.buildingInviteList = NO;
				[me.progress dismiss];
				me.progress = nil;
				[me shareInviteLinkDirectly];
				return;
			}
			[[TGClient shared] importContacts:entries completion:^(NSArray *userIds){
				TGContactsViewController *inner = weakSelf;
				if (!inner)
					return;
				[inner finishInviteListWithEntries:entries userIds:userIds];
			}];
		});
	});
}

- (void)newGroupTapped {
	TGNewGroupMembersViewController *vc = [[TGNewGroupMembersViewController alloc] init];
	vc.contacts = self.users;
	[self.navigationController pushViewController:vc animated:YES];
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
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(runServerContactSearch)
											   object:nil];
	[self performSelector:@selector(runServerContactSearch) withObject:nil afterDelay:0.35f];
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
	self.serverUsers = nil;
	self.serverQuery = nil;
	[self rebuildSections];
	[self.tableView reloadData];
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

- (UIImage *)diskThumbAtPath:(NSString *)path {
	if (![[NSFileManager defaultManager] fileExistsAtPath:path])
		return nil;
	UIImage *stored = [UIImage imageWithContentsOfFile:path];
	CGFloat scale = [UIScreen mainScreen].scale;
	CGImageRef bitmap = stored.CGImage;
	if (bitmap
			&& fabs((CGFloat)CGImageGetWidth(bitmap) - kContactAvatar * scale) < 0.5f
			&& fabs((CGFloat)CGImageGetHeight(bitmap) - kContactAvatar * scale) < 0.5f)
		return [UIImage imageWithCGImage:bitmap scale:scale
							 orientation:UIImageOrientationUp];
	[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	return nil;
}

- (UIImage *)photoForUser:(NSDictionary *)u {
	NSNumber *fileId = [u[@"photoFileId"] isKindOfClass:NSNumber.class]
			? u[@"photoFileId"] : nil;
	if (!fileId)
		return nil;
	UIImage *photo = [self.photos objectForKey:fileId];
	if (photo)
		return photo;
	NSString *cacheKey = [self thumbCacheKeyForUser:u];
	if (!cacheKey)
		return nil;
	NSString *cachePath = [self thumbCachePathForKey:cacheKey];
	photo = [self diskThumbAtPath:cachePath];
	if (photo){
		[self.photos setObject:photo forKey:fileId cost:TGContactPhotoCost(photo)];
		return photo;
	}
	[self requestPhotoForFileId:fileId cachePath:cachePath];
	return nil;
}

- (void)requestPhotoForFileId:(NSNumber *)fileId cachePath:(NSString *)cachePath {
	if (!fileId || !cachePath.length || [self.photosRequested containsObject:fileId]
			|| [self.photosFailed containsObject:fileId])
		return;
	[self.photosRequested addObject:fileId];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		if (!path){
			TGContactsViewController *me = weakSelf;
			[me.photosRequested removeObject:fileId];
			[me.photosFailed addObject:fileId];
			return;
		}
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			@autoreleasepool {
				UIImage *thumb = TGDecodeSquareThumbnail(path, kContactAvatar);
				if (thumb)
					[UIImagePNGRepresentation(thumb) writeToFile:cachePath
													  atomically:YES];
				dispatch_async(dispatch_get_main_queue(), ^{
					TGContactsViewController *me = weakSelf;
					if (!me)
						return;
					[me.photosRequested removeObject:fileId];
					if (!thumb){
						[me.photosFailed addObject:fileId];
						return;
					}
					[me.photos setObject:thumb forKey:fileId
									cost:TGContactPhotoCost(thumb)];
					[me reloadTableSoon];
				});
			}
		});
	}];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	[self.photos removeAllObjects];
}

- (void)fetchMissingPhotos {
	NSMutableSet *liveKeys = [NSMutableSet set];
	for (NSDictionary *u in self.users){
		NSString *key = [self thumbCacheKeyForUser:u];
		if (key)
			[liveKeys addObject:key];
	}
	[self pruneThumbCacheKeeping:liveKeys];
	[self.photosFailed removeAllObjects];
}

- (BOOL)isPhotoFileVisible:(NSNumber *)fileId {
	for (NSIndexPath *path in [self.tableView indexPathsForVisibleRows]){
		NSDictionary *u = [self userAtIndexPath:path];
		NSNumber *other = [u[@"photoFileId"] isKindOfClass:NSNumber.class]
				? u[@"photoFileId"] : nil;
		if (other && [other isEqualToNumber:fileId])
			return YES;
	}
	return NO;
}

- (void)tableView:(UITableView *)tableView
		didEndDisplayingCell:(UITableViewCell *)cell
		   forRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *u = [self userAtIndexPath:indexPath];
	NSNumber *fileId = [u[@"photoFileId"] isKindOfClass:NSNumber.class]
			? u[@"photoFileId"] : nil;
	if (!fileId || ![self.photosRequested containsObject:fileId])
		return;
	if ([self.photos objectForKey:fileId] || [self isPhotoFileVisible:fileId])
		return;
	[self.photosRequested removeObject:fileId];
	[[TGClient shared] cancelDownloadOfFile:fileId.integerValue onlyIfPending:NO];
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

- (NSDictionary *)userAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *rows = [self rowsForSection:indexPath.section];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count)
		return nil;
	id u = rows[indexPath.row];
	return [u isKindOfClass:NSDictionary.class] ? u : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.sections ? self.sections.count : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [self rowsForSection:section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return [self actionIdentifierAtIndexPath:indexPath]
			? kContactActionRowHeight : kContactRowHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return [self letterForSection:section] ? kContactSectionHeight : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *letter = [self letterForSection:section];
	if (!letter)
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
	label.text = letter;

	if ([[TGTheme shared] isFlat]){
		container.backgroundColor = [[TGTheme shared] listBackgroundColour];
		label.textColor = [[TGTheme shared] sectionHeaderColour];
	} else {
		UIImage *background = [UIImage imageNamed:
				(section == 0 ? @"CategoryDividerFirst" : @"CategoryDivider")];
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
	if (!self.sectionTitles.count || self.filteredUsers)
		return nil;
	NSMutableArray *indices = [NSMutableArray array];
	if (self.searchBar)
		[indices addObject:UITableViewIndexSearch];
	for (id title in self.sectionTitles){
		if ([title isKindOfClass:NSString.class])
			[indices addObject:title];
	}
	return (indices.count > 1) ? indices : nil;
}

- (NSInteger)tableView:(UITableView *)tableView
		sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
	if ([title isEqualToString:UITableViewIndexSearch]){
		[tableView setContentOffset:CGPointMake(0, -tableView.contentInset.top) animated:NO];
		return -1;
	}
	for (NSUInteger section = 0; section < self.sectionTitles.count; section++){
		if ([self.sectionTitles[section] isEqual:title])
			return (NSInteger)section;
	}
	return 0;
}

- (UITableViewCell *)actionCellForTableView:(UITableView *)tableView identifier:(NSString *)action {
	static NSString *actionReuse = @"TGFlatActionCell";
	TGFlatActionCell *cell = (TGFlatActionCell *)
			[tableView dequeueReusableCellWithIdentifier:actionReuse];
	if (!cell)
		cell = [[TGFlatActionCell alloc] initWithStyle:UITableViewCellStyleDefault
									   reuseIdentifier:actionReuse];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.disclosureIndicator.hidden = NO;
	if ([action isEqualToString:TGContactActionInvite]){
		cell.titleLabel.text = @"Invite Friends";
		[cell setIconImage:[UIImage imageNamed:@"ListIconInvite"] at:CGPointMake(13, 12)];
	} else if ([action isEqualToString:TGContactActionNewGroup]){
		cell.titleLabel.text = @"New Group";
		[cell setIconImage:[UIImage imageNamed:@"ListIconFriends"] at:CGPointMake(10, 12)];
	} else if ([action isEqualToString:TGContactActionSync]){
		cell.titleLabel.text = @"Sync Contacts";
		[cell setIconImage:[UIImage imageNamed:@"ListIconFriends"] at:CGPointMake(10, 12)];
		cell.disclosureIndicator.hidden = YES;
	} else {
		cell.titleLabel.text = @"My Invite Link";
		[cell setIconImage:[UIImage imageNamed:@"ListIconInvite"] at:CGPointMake(13, 12)];
		cell.disclosureIndicator.hidden = YES;
	}
	[cell setNeedsLayout];
	return cell;
}

- (void)clearContactCell:(TGContactRowCell *)cell {
	cell.titleLabel.text = @"";
	cell.secondTitleLabel.text = @"";
	cell.secondTitleLabel.hidden = YES;
	cell.subtitleLabel.text = @"";
	cell.avatarView.image = nil;
	cell.premiumView.hidden = YES;
	cell.verifiedLabel.hidden = YES;
	cell.closeFriendLabel.hidden = YES;
}

- (void)applyNameToCell:(TGContactRowCell *)cell user:(NSDictionary *)u {
	NSString *first = [u[@"first_name"] isKindOfClass:NSString.class] ? u[@"first_name"] : @"";
	NSString *last  = [u[@"last_name"] isKindOfClass:NSString.class] ? u[@"last_name"] : @"";
	BOOL online = [u[@"isOnline"] boolValue];

	UIFont *regular = [UIFont systemFontOfSize:19];
	UIFont *bold = [UIFont boldSystemFontOfSize:19];
	NSString *primary = self.displayFirstNameFirst ? first : last;
	NSString *secondary = self.displayFirstNameFirst ? last : first;
	BOOL boldPrimary = (self.displayFirstNameFirst == self.sortByFirstName);

	if (primary.length && secondary.length){
		cell.titleLabel.font = boldPrimary ? bold : regular;
		cell.secondTitleLabel.font = boldPrimary ? regular : bold;
		cell.titleLabel.text = primary;
		cell.secondTitleLabel.text = secondary;
		cell.secondTitleLabel.hidden = NO;
	} else {
		cell.titleLabel.font = bold;
		cell.titleLabel.text = primary.length ? primary
				: (secondary.length ? secondary : TGContactName(u));
		cell.secondTitleLabel.text = @"";
		cell.secondTitleLabel.hidden = YES;
	}

	NSString *phone = TGContactString(u, @"phone");
	cell.subtitleLabel.text = self.isPickerMode
			? (phone.length ? [NSString stringWithFormat:@"+%@", phone] : @"")
			: TGContactString(u, @"statusText");
	cell.subtitleLabel.textColor = (online && !self.isPickerMode)
			? TGContactsRGB(0x0779d0) : [UIColor colorWithWhite:0.0f alpha:0.53f];
	cell.backgroundColor = [[TGTheme shared] listBackgroundColour];
	cell.accessoryType = UITableViewCellAccessoryNone;
}

- (void)applyBadgesToCell:(TGContactRowCell *)cell user:(NSDictionary *)u {
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
				? [NSString stringWithFormat:@"Birthday today · %@", cell.subtitleLabel.text]
				: @"Birthday today";
		cell.subtitleLabel.textColor = TGContactsRGB(0x0779d0);
	}
	if (flagged && !self.isPickerMode){
		cell.subtitleLabel.textColor = TGContactsRGB(0xcc1e2c);
		NSString *mark = [badges[@"isScam"] boolValue] ? @"SCAM" : @"FAKE";
		cell.subtitleLabel.text = cell.subtitleLabel.text.length
				? [NSString stringWithFormat:@"%@ · %@", mark, cell.subtitleLabel.text]
				: mark;
	}
}

- (void)applyAvatarToCell:(TGContactRowCell *)cell user:(NSDictionary *)u {
	NSString *name = TGContactName(u);
	UIImage *photo = [self photoForUser:u];
	if (!photo)
		photo = [TGIcons avatarWithInitials:
					(name.length ? [name substringToIndex:1].uppercaseString : @"?")
									   size:kContactAvatar
								   colourId:[u[@"id"] longLongValue]];
	cell.avatarView.image = photo;
	cell.avatarView.layer.cornerRadius = kContactAvatarCorner;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGContactCell";

	NSString *action = [self actionIdentifierAtIndexPath:indexPath];
	if (action)
		return [self actionCellForTableView:tableView identifier:action];

	TGContactRowCell *cell = (TGContactRowCell *)[tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGContactRowCell alloc] initWithStyle:UITableViewCellStyleDefault
									   reuseIdentifier:reuse];
	[cell resetForConfiguration];

	NSDictionary *u = [self userAtIndexPath:indexPath];
	if (!u){
		[self clearContactCell:cell];
		return cell;
	}
	[self applyNameToCell:cell user:u];
	[self applyBadgesToCell:cell user:u];
	[cell setNeedsLayout];
	[self applyAvatarToCell:cell user:u];
	return cell;
}

- (BOOL)keepsSelectionForDetailPane {
	return !self.isPickerMode && TGContactsTabletLayout();
}

- (void)openTarget:(UIViewController *)target {
	if (!target)
		return;
	if (!self.isPickerMode && TGContactsShowInDetailPane(self, target))
		return;
	[self.navigationController pushViewController:target animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *action = [self actionIdentifierAtIndexPath:indexPath];
	if (action || ![self keepsSelectionForDetailPane])
		[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (action){
		if ([action isEqualToString:TGContactActionInvite])
			[self inviteFriendsTapped];
		else if ([action isEqualToString:TGContactActionNewGroup])
			[self newGroupTapped];
		else if ([action isEqualToString:TGContactActionSync])
			[self importFooterTapped];
		else
			[self contactLinkTapped];
		return;
	}
	NSDictionary *u = [self userAtIndexPath:indexPath];
	if (!u){
		[tableView deselectRowAtIndexPath:indexPath animated:YES];
		return;
	}
	NSString *name = TGContactName(u);
	__weak typeof(self) weakSelf = self;

	[self.searchBar resignFirstResponder];
	[[TGClient shared] privateChatWithUser:[u[@"id"] longLongValue]
								completion:^(int64_t chatId){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		if (chatId == 0){
			[me.tableView deselectRowAtIndexPath:indexPath animated:YES];
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
		[me openTarget:vc];
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

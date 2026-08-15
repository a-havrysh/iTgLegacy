#import "TGProfileViewController.h"
#import "TGClient.h"
#import "TGClient+Files.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGForwardPicker.h"
#import "UIView+SafeTint.h"
#import "TGImageDecode.h"
#import "TGClient+ChatManagement.h"
#import "TGClient+SecretChats.h"
#import "TGClient+Groups.h"
#import "TGClient+Channels.h"
#import "TGClient+Contacts.h"
#import "TGClient+ChatList.h"
#import "TGClient+Forums.h"
#import "TGClient+UserStatus.h"
#import "TGClient+Stories.h"
#import "TGGroupMembersViewController.h"
#import "TGInviteLinksViewController.h"
#import "TGChatEventsViewController.h"
#import "TGChatViewController.h"
#import "TGMediaViewController.h"
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>

@interface TGProfilePermissionsController : UITableViewController
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, strong) NSMutableDictionary *permissions;
@end

@interface TGProfileChartView : UIView
@property (nonatomic, strong) NSArray *points;
@property (nonatomic, strong) NSString *leftDate;
@property (nonatomic, strong) NSString *rightDate;
@end

@interface TGProfileStatisticsController : UIViewController
		<UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, strong) NSArray *values;
@property (nonatomic, strong) NSArray *topSenders;
@property (nonatomic, strong) NSArray *topAdmins;
@property (nonatomic, strong) NSArray *topInviters;
@property (nonatomic, strong) NSArray *graphs;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) NSInteger mode;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) TGProfileChartView *chartView;
@property (nonatomic, strong) NSDictionary *boostStatus;
@property (nonatomic, strong) NSArray *boosters;
@end

@interface TGProfileCommonGroupsController : UITableViewController
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSArray *chats;
@end

@interface TGProfileLinkJoinsController : UITableViewController
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, strong) NSString *link;
@property (nonatomic, strong) NSArray *members;
@property (nonatomic, assign) NSInteger total;
@property (nonatomic, assign) BOOL loaded;
@end

@interface TGProfileBoostsController : UITableViewController
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) BOOL isChannel;
@property (nonatomic, strong) NSDictionary *status;
@property (nonatomic, strong) NSArray *boosters;
@property (nonatomic, strong) NSString *boostLink;
@property (nonatomic, strong) NSDictionary *nextLevelFeatures;
@property (nonatomic, strong) NSArray *featureTable;
@end

@interface TGProfileButtonsCell : UITableViewCell
@property (nonatomic, strong) UIButton *leftButton;
@property (nonatomic, strong) UIButton *rightButton;
@end

@interface TGProfileRedButtonCell : UITableViewCell
@property (nonatomic, strong) UIButton *button;
@end

@interface TGProfileViewController () <UIActionSheetDelegate, UIAlertViewDelegate,
		UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSArray *details;
@property (nonatomic, strong) NSMutableDictionary *measuredRowHeights;
@property (nonatomic, assign) CGFloat groupedInset;
@property (nonatomic, assign) NSInteger photoCount;
@property (nonatomic, assign) NSInteger fileCount;
@property (nonatomic, strong) NSArray *members;
@property (nonatomic, strong) NSArray *gifts;
@property (nonatomic, assign) BOOL blocked;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSArray *actionNames;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, strong) NSString *phoneNumber;
@property (nonatomic, strong) UIImage *avatarImage;
@property (nonatomic, strong) UISwitch *notificationsSwitch;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, assign) BOOL isContact;
@property (nonatomic, strong) NSString *firstName;
@property (nonatomic, strong) NSString *lastName;
@property (nonatomic, strong) NSArray *manageRows;
@property (nonatomic, strong) NSArray *sectionKinds;
@property (nonatomic, assign) BOOL canEditChat;
@property (nonatomic, assign) BOOL isChatAdmin;
@property (nonatomic, assign) BOOL isChannelChat;
@property (nonatomic, assign) BOOL isSupergroupChat;
@property (nonatomic, assign) NSInteger slowModeDelay;
@property (nonatomic, strong) NSString *groupTitle;
@property (nonatomic, assign) BOOL canListMembers;
@property (nonatomic, assign) BOOL managementLoaded;
@property (nonatomic, assign) BOOL signMessages;
@property (nonatomic, assign) BOOL showAuthorProfiles;
@property (nonatomic, assign) BOOL signaturesKnown;
@property (nonatomic, assign) BOOL discussionKnown;
@property (nonatomic, assign) int64_t discussionChatId;
@property (nonatomic, strong) NSString *discussionTitle;
@property (nonatomic, strong) NSArray *discussionCandidates;
@property (nonatomic, assign) BOOL historyAvailable;
@property (nonatomic, assign) BOOL hiddenMembers;
@property (nonatomic, assign) BOOL canHideMembers;
@property (nonatomic, assign) BOOL antiSpam;
@property (nonatomic, assign) BOOL canToggleAntiSpam;
@property (nonatomic, assign) BOOL protectedContent;
@property (nonatomic, assign) BOOL manageFlagsKnown;
@property (nonatomic, assign) NSInteger pendingJoinRequests;
@property (nonatomic, assign) BOOL canGetStatistics;
@property (nonatomic, assign) BOOL boostsKnown;
@property (nonatomic, assign) NSInteger boostLevel;
@property (nonatomic, assign) int64_t personalChatId;
@property (nonatomic, strong) NSString *personalChatTitle;
@property (nonatomic, strong) UIImageView *badgeView;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, assign) BOOL canPostStory;
@property (nonatomic, assign) int64_t storyChatId;
@property (nonatomic, assign) NSInteger pickerMode;
@property (nonatomic, strong) NSString *storyPath;
@property (nonatomic, strong) NSString *storyPrivacy;
@property (nonatomic, strong) NSArray *baseDetailRows;
@property (nonatomic, strong) NSString *profileBio;
@property (nonatomic, strong) NSString *profileBirthdayText;
@property (nonatomic, strong) NSString *birthdayDetail;
@property (nonatomic, strong) NSString *emojiStatusDetail;
@property (nonatomic, assign) NSInteger profileCommonGroupCount;
@property (nonatomic, assign) BOOL fullProfileLoaded;
@property (nonatomic, strong) NSString *profileNote;
@property (nonatomic, assign) BOOL noteLoaded;
@property (nonatomic, strong) NSArray *commonGroups;
@property (nonatomic, assign) BOOL commonGroupsLoaded;
@property (nonatomic, assign) BOOL photosLoaded;
@property (nonatomic, assign) BOOL filesLoaded;
@property (nonatomic, strong) UIView *photoOverlay;
@property (nonatomic, strong) NSDictionary *statusInfo;
@property (nonatomic, assign) BOOL emojiStatusShown;
@property (nonatomic, strong) NSString *chatDescription;
@property (nonatomic, strong) NSString *primaryInviteLink;
@property (nonatomic, assign) NSInteger inviteLinkCount;
@property (nonatomic, assign) NSInteger primaryLinkJoinCount;
@property (nonatomic, assign) NSInteger adminCount;
@property (nonatomic, assign) NSInteger memberCount;
@property (nonatomic, strong) NSString *contactRelation;
@property (nonatomic, strong) NSArray *reportOptions;
@property (nonatomic, strong) NSString *reportOptionId;
@property (nonatomic, assign) BOOL isForumChat;
@property (nonatomic, assign) BOOL forumTopicsKnown;
@property (nonatomic, assign) NSInteger forumTopicCount;
@property (nonatomic, assign) NSInteger avatarFileId;
@property (nonatomic, assign) NSInteger badgeFileId;
@property (nonatomic, assign) NSInteger overlayFileId;
@property (nonatomic, assign) BOOL avatarIsPlaceholder;
@property (nonatomic, assign) BOOL hasAppearedOnce;
@end

static const NSInteger kPickerModeChatPhoto = 0;
static const NSInteger kPickerModeStory = 1;
static const NSInteger kPickerModePersonalPhoto = 2;
static const NSInteger kPickerModeSuggestPhoto = 3;

static const CGFloat kActionButtonHeight = 45.0f;
static const CGFloat kButtonsRowHeight = 43.0f;
static const CGFloat kButtonGutter = 10.0f;
static const CGFloat kGroupedInset = 9.0f;
static const CGFloat kButtonsRowGutter = 10.0f;
static const CGFloat kTitleContainerHeight = 89.0f;
static const CGFloat kProfileAvatarSide = 70.0f;
static const CGFloat kProfileAvatarRadius = 10.0f;
static const CGFloat kMemberRowHeight = 49.0f;
static const CGFloat kMemberAvatarSide = 36.0f;

static CGFloat TGProfileRetinaPixel(void) {
	return [UIScreen mainScreen].scale > 1.5f ? 0.5f : 0.0f;
}

static UIColor *TGProfileListBackground(void) {
	TGTheme *theme = [TGTheme shared];
	if (theme.isFlat || theme.isDark || theme.importedName)
		return [theme listBackgroundColour];
	UIImage *pattern = [UIImage imageNamed:@"SettingsBackground.png"];
	if (pattern)
		return [UIColor colorWithPatternImage:pattern];
	return [theme listBackgroundColour];
}

static UIColor *TGProfileColour(int rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:1.0f];
}

static NSString *TGProfileText(id value) {
	if (![value isKindOfClass:[NSString class]])
		return nil;
	NSString *text = [value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return text.length ? text : nil;
}

static NSString *TGProfileNumberText(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [value stringValue];
	return TGProfileText(value);
}

static BOOL TGProfileBool(id value) {
	return [value isKindOfClass:[NSNumber class]] && [value boolValue];
}

static int64_t TGProfileInt64(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [value longLongValue];
	if ([value isKindOfClass:[NSString class]])
		return [value longLongValue];
	return 0;
}

static NSString *TGProfileInitial(NSString *name) {
	NSString *trimmed = TGProfileText(name);
	if (!trimmed.length)
		return @"?";
	NSRange first = [trimmed rangeOfComposedCharacterSequenceAtIndex:0];
	return [[trimmed substringWithRange:first] uppercaseString];
}

static UIImage *TGProfileStretched(NSString *name) {
	UIImage *raw = [UIImage imageNamed:name];
	if (!raw)
		return nil;
	return [raw stretchableImageWithLeftCapWidth:(int)(raw.size.width / 2) topCapHeight:0];
}

@implementation TGProfileButtonsCell

- (UIButton *)makeButton {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	[button setBackgroundImage:TGProfileStretched(@"GroupedActionButton.png")
					  forState:UIControlStateNormal];
	[button setBackgroundImage:TGProfileStretched(@"GroupedActionButton_Highlighted.png")
					  forState:UIControlStateHighlighted];
	[button setTitleColor:TGProfileColour(0x4a6587) forState:UIControlStateNormal];
	[button setTitleShadowColor:[[UIColor whiteColor] colorWithAlphaComponent:0.45f]
					   forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
	[button setTitleShadowColor:[UIColor clearColor] forState:UIControlStateHighlighted];
	button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
	button.titleLabel.shadowOffset = CGSizeMake(0, 1);
	button.adjustsImageWhenDisabled = NO;
	button.exclusiveTouch = YES;
	return button;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			  reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])){
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.backgroundColor = [UIColor clearColor];
		self.backgroundView = [[UIView alloc] initWithFrame:CGRectZero];
		self.backgroundView.backgroundColor = [UIColor clearColor];
		_leftButton = [self makeButton];
		_rightButton = [self makeButton];
		[self.contentView addSubview:_leftButton];
		[self.contentView addSubview:_rightButton];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat contentWidth = self.contentView.bounds.size.width;
	CGFloat height = kButtonsRowHeight;
	if (!_leftButton.hidden && !_rightButton.hidden){
		CGFloat buttonWidth = floorf((contentWidth - kButtonGutter) / 2);
		_leftButton.frame = CGRectMake(0, 0, buttonWidth, height);
		_rightButton.frame = CGRectMake(contentWidth - buttonWidth, 0,
										buttonWidth, height);
	} else if (!_leftButton.hidden){
		_leftButton.frame = CGRectMake(0, 0, contentWidth, height);
	}
}

@end

@implementation TGProfileRedButtonCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			  reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])){
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.backgroundColor = [UIColor clearColor];
		self.backgroundView = [[UIView alloc] initWithFrame:CGRectZero];
		self.backgroundView.backgroundColor = [UIColor clearColor];
		_button = [UIButton buttonWithType:UIButtonTypeCustom];
		[_button setBackgroundImage:TGProfileStretched(@"MenuRedButton.png")
						   forState:UIControlStateNormal];
		[_button setBackgroundImage:TGProfileStretched(@"MenuRedButton_Highlighted.png")
						   forState:UIControlStateHighlighted];
		[_button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[_button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
		UIColor *shadow = [TGProfileColour(0xa10603) colorWithAlphaComponent:0.5f];
		[_button setTitleShadowColor:shadow forState:UIControlStateNormal];
		[_button setTitleShadowColor:shadow forState:UIControlStateHighlighted];
		_button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
		_button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		_button.adjustsImageWhenDisabled = NO;
		_button.exclusiveTouch = YES;
		[self.contentView addSubview:_button];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	_button.frame = CGRectMake(0, 0, self.contentView.bounds.size.width,
							   kActionButtonHeight);
}

@end

@implementation TGProfileViewController

- (instancetype)initWithChatId:(int64_t)chatId userId:(int64_t)userId title:(NSString *)title {
	if ((self = [super initWithStyle:UITableViewStyleGrouped])){
		_chatId = chatId;
		_userId = userId;
		_name = title ?: @"";
		_details = @[];
		_manageRows = @[];
		[self rebuildSections];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = [self profileTitle];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = TGProfileListBackground();
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	if (self.chatId)
		self.muted = [[TGClient shared] isChatMuted:self.chatId];

	[self buildHeader];
	[self loadDetails];
	[self loadMedia];
	[self loadProfileExtras];
	[self loadStoryPosting];
}

- (NSString *)profileTitle {
	if (self.chatId && [[TGClient shared] isSecretChat:self.chatId])
		return @"   Secret Chat";
	if (!self.userId && self.chatId)
		return @"Group Info";
	return @"Info";
}

- (BOOL)isGroupProfile {
	return self.userId == 0 && self.chatId != 0;
}

- (void)loadStoryPosting {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatsToPostStoriesWithCompletion:^(NSArray *chats){
		if (![chats isKindOfClass:[NSArray class]])
			return;
		int64_t match = 0;
		for (id chat in chats){
			if (![chat isKindOfClass:[NSDictionary class]])
				continue;
			int64_t identifier = TGProfileInt64(chat[@"id"]);
			if (!identifier)
				continue;
			if (identifier == weakSelf.chatId || (weakSelf.userId
					&& identifier == weakSelf.userId)){
				match = identifier;
				break;
			}
		}
		if (!match)
			return;
		weakSelf.storyChatId = match;
		weakSelf.canPostStory = YES;
		[weakSelf rebuildSections];
		[weakSelf.tableView reloadData];
	}];
}

- (void)postStoryTapped {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] canPostStoryAsChat:self.storyChatId
							   completion:^(BOOL canPost, NSString *reason){
		if (!canPost){
			[[[UIAlertView alloc] initWithTitle:nil
					message:(TGProfileText(reason) ?: @"You cannot post a story right now.")
				   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
			return;
		}
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
				delegate:weakSelf cancelButtonTitle:nil destructiveButtonTitle:nil
				otherButtonTitles:@"Take Photo", @"Choose Photo", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 77;
		[sheet showInView:weakSelf.view];
	}];
}

- (void)pickStoryPhotoFromCamera:(BOOL)camera {
	UIImagePickerControllerSourceType source = camera
			? UIImagePickerControllerSourceTypeCamera
			: UIImagePickerControllerSourceTypePhotoLibrary;
	if (![UIImagePickerController isSourceTypeAvailable:source]){
		[self showToast:(camera ? @"No camera" : @"No photo library")];
		return;
	}
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = source;
	picker.allowsEditing = NO;
	picker.delegate = self;
	self.pickerMode = kPickerModeStory;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)askStoryPrivacy {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Who can see this story"
			delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
			otherButtonTitles:@"Everyone", @"My Contacts", @"Close Friends", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 78;
	[sheet showInView:self.view];
}

- (void)askStoryCaption {
	UIAlertView *caption = [[UIAlertView alloc] initWithTitle:nil
			message:@"Caption" delegate:self cancelButtonTitle:@"Cancel"
			otherButtonTitles:@"Post", nil];
	caption.tag = 79;
	if ([caption respondsToSelector:@selector(setAlertViewStyle:)])
		caption.alertViewStyle = UIAlertViewStylePlainTextInput;
	[caption show];
}

- (void)postStoryWithCaption:(NSString *)caption {
	NSString *path = self.storyPath;
	if (!path.length || !self.storyChatId)
		return;
	self.storyPath = nil;
	[self showToast:@"Posting story..."];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] postPhotoStoryAtPath:path
									 asChat:self.storyChatId
									caption:(caption ?: @"")
									privacy:(self.storyPrivacy ?: @"everyone")
									userIds:nil
								  toProfile:NO
								 completion:^(NSDictionary *story){
		[weakSelf showToast:([story isKindOfClass:[NSDictionary class]]
				? @"Story posted" : @"Could not post story")];
	}];
}

- (void)layoutNameBadge {
	NSString *text = self.nameLabel.text ?: @"";
	CGFloat available = self.nameLabel.frame.size.width;
	CGFloat textWidth = available;
	if (text.length && [text respondsToSelector:@selector(sizeWithFont:)]){
		CGSize measured = [text sizeWithFont:self.nameLabel.font];
		textWidth = MIN(measured.width, available);
	}
	CGFloat x = self.nameLabel.frame.origin.x + textWidth + 5;
	CGFloat limit = self.view.bounds.size.width - 30;
	if (x > limit)
		x = limit;
	CGRect labelFrame = self.badgeLabel.frame;
	labelFrame.origin.x = x;
	self.badgeLabel.frame = labelFrame;
	CGRect viewFrame = self.badgeView.frame;
	viewFrame.origin.x = x;
	self.badgeView.frame = viewFrame;
}

- (NSString *)statusRowValueFor:(NSDictionary *)badge emoji:(NSString *)emoji {
	NSString *gift = TGProfileText(badge[@"giftTitle"]);
	NSTimeInterval expires = [badge[@"expires"] isKindOfClass:[NSNumber class]]
			? [badge[@"expires"] doubleValue] : 0;
	NSString *text = gift;
	if (expires > [[NSDate date] timeIntervalSince1970]){
		static NSDateFormatter *formatter = nil;
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			formatter = [[NSDateFormatter alloc] init];
			formatter.dateFormat = @"HH:mm";
		});
		NSString *until = [NSString stringWithFormat:@"until %@",
				[formatter stringFromDate:
						[NSDate dateWithTimeIntervalSince1970:expires]]];
		text = text.length ? [NSString stringWithFormat:@"%@, %@", text, until] : until;
	}
	if (!text.length)
		return emoji ?: @"";
	return [NSString stringWithFormat:@"%@  %@", text, (emoji ?: @"")];
}

- (void)applyEmojiStatus:(NSDictionary *)badge {
	if (![badge isKindOfClass:[NSDictionary class]]){
		self.badgeLabel.hidden = YES;
		self.badgeView.hidden = YES;
		return;
	}
	self.emojiStatusShown = YES;
	NSString *emoji = TGProfileText(badge[@"emoji"]);
	self.badgeLabel.text = emoji ?: @"⭐";
	self.badgeLabel.hidden = NO;
	self.badgeView.hidden = YES;
	[self layoutNameBadge];
	NSString *statusValue = [self statusRowValueFor:badge emoji:self.badgeLabel.text];
	self.emojiStatusDetail = statusValue.length ? statusValue : nil;
	[self setDetail:statusValue forLabel:@"status"];

	NSNumber *thumb = [badge[@"thumbFileId"] isKindOfClass:[NSNumber class]]
			? badge[@"thumbFileId"] : nil;
	if (!thumb)
		thumb = [badge[@"stickerFileId"] isKindOfClass:[NSNumber class]]
				? badge[@"stickerFileId"] : nil;
	NSInteger badgeId = [thumb integerValue];
	if (badgeId <= 0){
		self.badgeFileId = 0;
		return;
	}
	if (self.badgeFileId == badgeId){
		if (self.badgeView.image){
			self.badgeView.hidden = NO;
			self.badgeLabel.hidden = YES;
			[self layoutNameBadge];
		}
		return;
	}
	self.badgeFileId = badgeId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:badgeId completion:^(NSString *path){
		if (!path.length || weakSelf.badgeFileId != badgeId)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			UIImage *image = TGDecodeSquareThumbnail(path, 18.0f);
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				if (weakSelf.badgeFileId != badgeId)
					return;
				weakSelf.badgeView.image = image;
				weakSelf.badgeView.hidden = NO;
				weakSelf.badgeLabel.hidden = YES;
				[weakSelf layoutNameBadge];
			});
		});
	}];
}

- (void)applyAccentColours:(NSDictionary *)colours {
	if (![colours isKindOfClass:[NSDictionary class]])
		return;
	id rgb = colours[@"rgb"];
	if (![rgb isKindOfClass:[NSNumber class]]){
		NSInteger colourId = [colours[@"colorId"] isKindOfClass:[NSNumber class]]
				? [colours[@"colorId"] integerValue] : 0;
		rgb = [TGClient rgbForAccentColorId:colourId];
	}
	if ([rgb isKindOfClass:[NSNumber class]])
		self.nameLabel.textColor = TGProfileColour([rgb intValue]);

	NSInteger profileColourId = [colours[@"profileColorId"] isKindOfClass:[NSNumber class]]
			? [colours[@"profileColorId"] integerValue] : -1;
	[self applyHeaderGradient:[TGClient profileGradientForColorId:profileColourId]];
}

- (void)applyHeaderGradient:(NSArray *)stops {
	UIView *header = self.tableView.tableHeaderView;
	if (!header || stops.count < 2)
		return;
	id top = stops[0];
	id bottom = stops[1];
	if (![top isKindOfClass:[NSNumber class]] || ![bottom isKindOfClass:[NSNumber class]])
		return;
	CGFloat height = header.bounds.size.height;
	if (height < 1)
		return;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, height), NO, 0.0f);
	CGContextRef context = UIGraphicsGetCurrentContext();
	UIImage *image = nil;
	if (context){
		UIColor *topColour = [TGProfileColour([top intValue]) colorWithAlphaComponent:0.20f];
		UIColor *bottomColour =
				[TGProfileColour([bottom intValue]) colorWithAlphaComponent:0.20f];
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		NSArray *colours = @[(id)topColour.CGColor, (id)bottomColour.CGColor];
		CGGradientRef gradient = CGGradientCreateWithColors(space,
				(__bridge CFArrayRef)colours, NULL);
		if (gradient){
			CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0),
					CGPointMake(0, height), 0);
			CGGradientRelease(gradient);
		}
		CGColorSpaceRelease(space);
		image = UIGraphicsGetImageFromCurrentImageContext();
	}
	UIGraphicsEndImageContext();
	if (image)
		header.backgroundColor = [UIColor colorWithPatternImage:image];
}

- (void)loadProfileExtras {
	if (self.userId){
		[self loadUserProfileExtras];
		return;
	}
	if (!self.chatId)
		return;
	[self loadChatProfileExtras];
}

- (void)loadUserProfileExtras {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] emojiStatusForUser:self.userId
							   completion:^(NSDictionary *badge){
		[weakSelf applyEmojiStatus:badge];
	}];
	[[TGClient shared] accentColorsForUser:self.userId
								completion:^(NSDictionary *colours){
		[weakSelf applyAccentColours:colours];
	}];
	[[TGClient shared] birthdateForUser:self.userId
							 completion:^(NSDictionary *birthdate){
		if (![birthdate isKindOfClass:[NSDictionary class]])
			return;
		NSString *text = TGProfileText(birthdate[@"text"]);
		if (!text)
			return;
		weakSelf.birthdayDetail = text;
		[weakSelf setDetail:text forLabel:@"birthday"];
	}];
	[[TGClient shared] personalChatForUser:self.userId
								completion:^(int64_t chatId){
		if (!chatId)
			return;
		weakSelf.personalChatId = chatId;
		weakSelf.personalChatTitle = @"Channel";
		[weakSelf rebuildSections];
		[weakSelf.tableView reloadData];
		[[TGClient shared] titleForChatId:chatId completion:^(NSString *title){
			weakSelf.personalChatTitle = TGProfileText(title) ?: @"Channel";
			[weakSelf.tableView reloadData];
		}];
	}];
}

- (void)loadChatProfileExtras {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] emojiStatusForChat:self.chatId
							   completion:^(NSDictionary *badge){
		[weakSelf applyEmojiStatus:badge];
	}];
	[[TGClient shared] accentColorsForChat:self.chatId
								completion:^(NSDictionary *colours){
		[weakSelf applyAccentColours:colours];
	}];
	[[TGClient shared] badgesForChat:self.chatId completion:^(NSDictionary *badges){
		if (![badges isKindOfClass:[NSDictionary class]] || weakSelf.emojiStatusShown)
			return;
		NSString *mark = nil;
		UIColor *colour = nil;
		if (TGProfileBool(badges[@"isVerified"])){
			mark = @"✓";
			colour = TGProfileColour(0x316ea1);
		} else if (TGProfileBool(badges[@"isScam"]) || TGProfileBool(badges[@"isFake"])){
			mark = @"⚠";
			colour = TGProfileColour(0xc23c2e);
		}
		if (!mark)
			return;
		weakSelf.badgeLabel.text = mark;
		weakSelf.badgeLabel.textColor = colour;
		weakSelf.badgeLabel.hidden = NO;
		weakSelf.badgeView.hidden = YES;
		[weakSelf layoutNameBadge];
	}];
}

- (void)setDetail:(NSString *)value forLabel:(NSString *)label {
	NSMutableArray *rows = [self.details mutableCopy] ?: [NSMutableArray array];
	BOOL replaced = NO;
	for (NSUInteger i = 0; i < rows.count; i++){
		NSArray *pair = rows[i];
		if (pair.count > 0 && [pair[0] isEqualToString:label]){
			rows[i] = @[label, value];
			replaced = YES;
			break;
		}
	}
	if (!replaced)
		[rows addObject:@[label, value]];
	self.details = rows;
	[self.tableView reloadData];
}

- (void)buildHeader {
	CGFloat width = self.view.bounds.size.width;
	CGFloat side = kProfileAvatarSide;
	CGFloat height = kTitleContainerHeight;

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	header.backgroundColor = [UIColor clearColor];

	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake(kGroupedInset, 14, side, side)];
	self.avatarView.layer.cornerRadius = kProfileAvatarRadius;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	self.avatarView.userInteractionEnabled = YES;
	self.avatarView.exclusiveTouch = YES;
	[self.avatarView addGestureRecognizer:
			[[UITapGestureRecognizer alloc] initWithTarget:self
													action:@selector(avatarTapped)]];
	self.avatarView.image = self.avatarImage
			?: [TGIcons avatarWithInitials:TGProfileInitial(self.name)
									  size:side
								  colourId:self.userId ?: self.chatId];
	[header addSubview:self.avatarView];

	[self buildHeaderLabelsInto:header width:width];

	[self refreshStatus];
	[self layoutNameBadge];

	self.tableView.tableHeaderView = header;
	self.tableView.tableFooterView =
			[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 7)];
	self.tableView.backgroundColor = TGProfileListBackground();

	if (self.avatarImage)
		return;
	NSNumber *fileId = self.userId
			? [[TGClient shared] photoFileIdForUserId:self.userId]
			: [[TGClient shared] photoFileIdForChat:self.chatId];
	if (![fileId isKindOfClass:[NSNumber class]])
		return;
	[self loadAvatarFile:fileId.integerValue];
}

- (void)buildHeaderLabelsInto:(UIView *)header width:(CGFloat)width {
	TGTheme *theme = [TGTheme shared];

	CGFloat retinaPixel = TGProfileRetinaPixel();
	CGFloat labelLeft = kProfileAvatarSide + kGroupedInset * 2 + 4;

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(labelLeft, 24, width - labelLeft - kGroupedInset, 24)];
	nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	nameLabel.text = TGProfileText(self.name) ?: @"";
	nameLabel.font = [UIFont boldSystemFontOfSize:19];
	nameLabel.backgroundColor = [UIColor clearColor];
	nameLabel.textColor = theme.isDark ? [theme primaryTextColour]
									   : TGProfileColour(0x222932);
	if (!theme.isDark){
		nameLabel.shadowColor = [TGProfileColour(0xedf0f5) colorWithAlphaComponent:0.28f];
		nameLabel.shadowOffset = CGSizeMake(0, 1);
	}
	[header addSubview:nameLabel];
	self.nameLabel = nameLabel;

	self.badgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelLeft, 24, 20, 24)];
	self.badgeLabel.font = [UIFont systemFontOfSize:17];
	self.badgeLabel.backgroundColor = [UIColor clearColor];
	self.badgeLabel.hidden = YES;
	[header addSubview:self.badgeLabel];

	self.badgeView = [[UIImageView alloc] initWithFrame:CGRectMake(labelLeft, 27, 18, 18)];
	self.badgeView.contentMode = UIViewContentModeScaleAspectFit;
	self.badgeView.hidden = YES;
	[header addSubview:self.badgeView];

	self.statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(labelLeft + 1, 49 + retinaPixel,
					   width - labelLeft - kGroupedInset, 24)];
	self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.statusLabel.font = [UIFont systemFontOfSize:14];
	self.statusLabel.textColor = theme.isDark ? [theme secondaryTextColour]
											  : TGProfileColour(0x6d7d90);
	if (!theme.isDark){
		self.statusLabel.shadowColor =
				[TGProfileColour(0xedf0f5) colorWithAlphaComponent:0.28f];
		self.statusLabel.shadowOffset = CGSizeMake(0, 1);
	}
	self.statusLabel.backgroundColor = [UIColor clearColor];
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:
			[[UITapGestureRecognizer alloc] initWithTarget:self
													action:@selector(statusTapped)]];
	[header addSubview:self.statusLabel];
}

- (void)setAvatarViewImage:(UIImage *)image crossfade:(BOOL)crossfade {
	if (!image)
		return;
	if (crossfade && self.avatarView.image){
		CATransition *fade = [CATransition animation];
		fade.duration = 0.2;
		fade.type = kCATransitionFade;
		[self.avatarView.layer addAnimation:fade forKey:@"avatarFade"];
	}
	self.avatarView.image = image;
}

- (void)showPlaceholderAvatarFromData:(NSData *)data {
	if (!data.length || self.avatarImage)
		return;
	UIImage *tiny = [UIImage imageWithData:data];
	if (!tiny)
		return;
	self.avatarIsPlaceholder = YES;
	[self setAvatarViewImage:tiny crossfade:NO];
}

- (void)cancelAvatarDownload {
	self.avatarFileId = 0;
}

- (void)loadAvatarFile:(NSInteger)fileId {
	if (fileId <= 0)
		return;
	if (self.avatarFileId == fileId)
		return;
	[self cancelAvatarDownload];
	self.avatarFileId = fileId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId completion:^(NSString *path){
		if (!path.length || weakSelf.avatarFileId != fileId)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			UIImage *image = TGDecodeSquareThumbnail(path, kProfileAvatarSide);
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				if (weakSelf.avatarFileId != fileId)
					return;
				weakSelf.avatarImage = image;
				weakSelf.avatarIsPlaceholder = NO;
				[weakSelf setAvatarViewImage:image crossfade:YES];
			});
		});
	}];
}

- (void)dealloc {
	if (_overlayFileId > 0)
		[[TGClient shared] cancelDownloadOfFile:_overlayFileId onlyIfPending:NO];
}

- (void)refreshStatus {
	__weak typeof(self) weakSelf = self;
	if (self.userId){
		[[TGClient shared] statusInfoForUser:self.userId
								  completion:^(NSDictionary *info){
			NSString *text = [info isKindOfClass:[NSDictionary class]]
					? TGProfileText(info[@"text"]) : nil;
			if ([info isKindOfClass:[NSDictionary class]])
				weakSelf.statusInfo = info;
			if (text){
				weakSelf.statusLabel.text = text;
				weakSelf.statusLabel.textColor = TGProfileBool(info[@"isOnline"])
						? TGProfileColour(0x316ea1)
						: ([TGTheme shared].isDark
								? [[TGTheme shared] secondaryTextColour]
								: TGProfileColour(0x6d7d90));
				return;
			}
			[[TGClient shared] statusForUser:weakSelf.userId
								  completion:^(NSString *status){
				weakSelf.statusLabel.text = TGProfileText(status) ?: @"";
			}];
		}];
		return;
	}
	if (!self.chatId)
		return;
	[[TGClient shared] groupOnlineSummaryForChat:self.chatId
									  completion:^(NSString *text, NSInteger members,
												   NSInteger online){
		if (members > 0 && members != weakSelf.memberCount){
			weakSelf.memberCount = members;
			[weakSelf rebuildManageRows];
		}
		NSString *summary = TGProfileText(text);
		if (summary){
			weakSelf.statusLabel.text = summary;
			return;
		}
		[[TGClient shared] memberCountForChat:weakSelf.chatId
								   completion:^(NSInteger count){
			if (count > 0)
				weakSelf.statusLabel.text = [NSString stringWithFormat:@"%ld member%@",
						(long)count, count == 1 ? @"" : @"s"];
		}];
	}];
}

- (void)statusTapped {
	NSString *hint = [TGClient hiddenStatusHintForStatusInfo:self.statusInfo];
	if (!hint.length)
		return;
	[[[UIAlertView alloc] initWithTitle:nil message:hint delegate:nil
					  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (NSArray *)actionItems {
	NSMutableArray *items = [NSMutableArray array];
	if (self.userId){
		[items addObject:@{@"title" : @"Send Message", @"action" : @"message"}];
		if (self.isContact)
			[items addObject:@{@"title" : @"Share Contact", @"action" : @"share"}];
		else
			[items addObject:@{@"title" : @"Add Contact", @"action" : @"add",
							   @"disabled" : @(self.phoneNumber.length == 0)}];
		[items addObject:@{@"title" : @"Call",       @"action" : @"call"}];
		[items addObject:@{@"title" : @"Video Call", @"action" : @"video"}];
	} else if (self.chatId){
		if (self.canListMembers)
			[items addObject:@{@"title" : @"Add Member", @"action" : @"addmember"}];
		[items addObject:@{@"title" : @"Leave Group", @"action" : @"leave"}];
	}
	if (self.onSearchTapped && self.chatId)
		[items addObject:@{@"title" : @"Search Messages", @"action" : @"search"}];
	[items addObject:@{@"title" : @"More", @"action" : @"more"}];
	self.actionNames = items;
	return items;
}

- (NSInteger)actionRowCount {
	NSInteger count = (NSInteger)[self actionItems].count;
	return (count + 1) / 2;
}

- (UITableViewCell *)actionsCell:(UITableView *)tableView row:(NSInteger)row {
	TGProfileButtonsCell *cell = (TGProfileButtonsCell *)
			[tableView dequeueReusableCellWithIdentifier:@"buttons"];
	if (![cell isKindOfClass:[TGProfileButtonsCell class]])
		cell = [[TGProfileButtonsCell alloc] initWithStyle:UITableViewCellStyleDefault
										   reuseIdentifier:@"buttons"];
	NSArray *items = self.actionNames ?: [self actionItems];
	NSInteger first = row * 2;
	UIButton *buttons[2] = {cell.leftButton, cell.rightButton};
	for (NSInteger i = 0; i < 2; i++){
		UIButton *button = buttons[i];
		NSInteger index = first + i;
		[button removeTarget:self action:NULL
			forControlEvents:UIControlEventTouchUpInside];
		if (index >= (NSInteger)items.count){
			button.hidden = YES;
			continue;
		}
		NSDictionary *item = items[index];
		button.hidden = NO;
		BOOL disabled = TGProfileBool(item[@"disabled"]);
		button.alpha = disabled ? 0.7f : 1.0f;
		button.enabled = !disabled;
		[button setTitle:item[@"title"] forState:UIControlStateNormal];
		button.tag = index;
		[button addTarget:self action:@selector(actionTileTapped:)
		 forControlEvents:UIControlEventTouchUpInside];
	}
	[cell setNeedsLayout];
	return cell;
}

- (void)actionTileTapped:(UIButton *)tile {
	if (tile.tag >= (NSInteger)self.actionNames.count)
		return;
	NSString *action = self.actionNames[tile.tag][@"action"];

	if ([action isEqualToString:@"message"]){
		[self openConversation];
		return;
	}
	if ([action isEqualToString:@"add"]){
		[self runMoreAction:@"Add to contacts"];
		return;
	}
	if ([action isEqualToString:@"share"]){
		[self runMoreAction:@"Share contact"];
		return;
	}

	if ([action isEqualToString:@"addmember"]){
		if (self.navigationController)
			[self pushGroupMembersInto:self.navigationController adminsFirst:NO];
		return;
	}
	if ([action isEqualToString:@"leave"]){
		[self confirmLeaveGroup];
		return;
	}

	if ([action isEqualToString:@"call"] || [action isEqualToString:@"video"]){
		if (!self.userId)
			return;
		[TGCallViewController presentForUserId:self.userId
										  name:self.name
									  outgoing:YES];
	} else if ([action isEqualToString:@"search"]){
		if (self.onSearchTapped) self.onSearchTapped();
	} else {
		[self showMoreMenuFrom:tile];
	}
}

- (void)updateMuteButton {
	[self.notificationsSwitch setOn:!self.muted animated:NO];
}

- (void)notificationsToggled:(UISwitch *)toggle {
	if (!self.chatId)
		return;
	self.muted = !toggle.on;
	[[TGClient shared] setChat:self.chatId muted:self.muted];
}

- (void)openConversation {
	UINavigationController *navigation = self.navigationController;
	if (!navigation)
		return;
	NSString *name = TGProfileText(self.name) ?: @"";
	if (self.chatId){
		for (UIViewController *controller in navigation.viewControllers){
			if ([controller isKindOfClass:[TGChatViewController class]]
					&& ((TGChatViewController *)controller).chatId == self.chatId){
				[navigation popToViewController:controller animated:YES];
				return;
			}
		}
		TGChatViewController *chat = [[TGChatViewController alloc] init];
		chat.chatId = self.chatId;
		chat.chatTitle = name;
		[navigation pushViewController:chat animated:YES];
		return;
	}
	if (!self.userId)
		return;
	[[TGClient shared] privateChatWithUser:self.userId completion:^(int64_t chatId){
		if (!chatId)
			return;
		TGChatViewController *chat = [[TGChatViewController alloc] init];
		chat.chatId = chatId;
		chat.chatTitle = name;
		[navigation pushViewController:chat animated:YES];
	}];
}

- (void)avatarTapped {
	if (self.photoOverlay)
		return;
	UIView *host = self.navigationController.view ?: self.view;
	UIImage *image = self.avatarView.image;
	if (!image)
		return;

	UIView *overlay = [[UIView alloc] initWithFrame:host.bounds];
	overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleHeight;
	overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
	UIImageView *big = [[UIImageView alloc] initWithImage:image];
	big.contentMode = UIViewContentModeScaleAspectFit;
	big.clipsToBounds = YES;
	big.frame = [self.avatarView convertRect:self.avatarView.bounds toView:host];
	[overlay addSubview:big];
	[overlay addGestureRecognizer:
			[[UITapGestureRecognizer alloc] initWithTarget:self
													action:@selector(closePhotoOverlay)]];
	[host addSubview:overlay];
	self.photoOverlay = overlay;

	[UIView animateWithDuration:0.3 animations:^{
		overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:1];
		big.frame = overlay.bounds;
	}];

	if (!self.userId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] profilePhotosForUser:self.userId offset:0 limit:1
								 completion:^(NSArray *photos, NSInteger total){
		id photo = [photos isKindOfClass:[NSArray class]] && photos.count
				? photos[0] : nil;
		id fileId = [photo isKindOfClass:[NSDictionary class]] ? photo[@"fileId"] : nil;
		if (![fileId isKindOfClass:[NSNumber class]] || [fileId integerValue] <= 0)
			return;
		if (weakSelf.photoOverlay != overlay)
			return;
		NSInteger fullId = [fileId integerValue];
		weakSelf.overlayFileId = fullId;
		[[TGClient shared] downloadFile:fullId completion:^(NSString *path){
			if (!path.length || weakSelf.photoOverlay != overlay)
				return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				UIImage *full = TGDecodeThumbnail(path, 640.0f);
				if (!full)
					return;
				dispatch_async(dispatch_get_main_queue(), ^{
					if (weakSelf.photoOverlay != overlay)
						return;
					weakSelf.overlayFileId = 0;
					CATransition *fade = [CATransition animation];
					fade.duration = 0.2;
					fade.type = kCATransitionFade;
					[big.layer addAnimation:fade forKey:@"photoFade"];
					big.image = full;
				});
			});
		}];
	}];
}

- (void)closePhotoOverlay {
	UIView *overlay = self.photoOverlay;
	if (!overlay)
		return;
	self.photoOverlay = nil;
	if (self.overlayFileId > 0){
		[[TGClient shared] cancelDownloadOfFile:self.overlayFileId onlyIfPending:NO];
		self.overlayFileId = 0;
	}
	[UIView animateWithDuration:0.2 animations:^{
		overlay.alpha = 0;
	} completion:^(BOOL done){
		[overlay removeFromSuperview];
	}];
}

- (void)showMoreMenuFrom:(UIView *)tile {
	NSMutableArray *items = [NSMutableArray array];
	if (self.userId){
		if (!self.chatId || ![[TGClient shared] isSecretChat:self.chatId])
			[items addObject:@{@"title" : @"Start secret chat", @"icon" : @"privacy"}];
	}
	if (self.userId && self.isContact){
		[items addObject:@{@"title" : @"Set photo for this contact",
						   @"icon" : @"privacy"}];
		[items addObject:@{@"title" : @"Share my phone number", @"icon" : @"privacy"}];
	}
	if (!self.userId && self.chatId)
		[items addObject:@{@"title" : @"Report group", @"icon" : @"privacy"}];
	if (self.chatId)
		[items addObject:@{@"title" : @"Auto-delete messages", @"icon" : @"delete"}];
	if (self.chatId)
		[items addObject:@{@"title" : @"Clear history", @"icon" : @"delete"}];
	if (self.userId)
		[items addObject:@{@"title" : (self.blocked ? @"Unblock user" : @"Block user"),
						   @"icon" : @"privacy", @"destructive" : @YES}];
	if (!items.count)
		return;

	CGPoint where = [tile convertPoint:CGPointMake(tile.bounds.size.width / 2,
												   tile.bounds.size.height)
								toView:self.navigationController.view];
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger index, NSString *title){
		[weakSelf runMoreAction:title];
	}];
}

- (void)runMoreAction:(NSString *)title {
	if ([title isEqualToString:@"Add to contacts"]){
		if (!self.userId)
			return;
		[self promptToAddContact];
		return;
	}

	if ([title isEqualToString:@"Share my phone number"]){
		if (!self.userId)
			return;
		[[TGClient shared] sharePhoneNumberWithUser:self.userId];
		[self showToast:@"Phone number shared"];
		return;
	}

	if ([title isEqualToString:@"Set photo for this contact"]){
		[self showContactPhotoActions];
		return;
	}

	if ([title isEqualToString:@"Report group"]){
		[self reportGroupWithOption:nil text:nil];
		return;
	}

	if ([title isEqualToString:@"Start secret chat"]){
		[self startSecretChat];
		return;
	}

	if ([title isEqualToString:@"Share contact"]){
		[self pushContactForwardPicker];
		return;
	}

	if ([title isEqualToString:@"Auto-delete messages"]){
		[self showAutoDeleteActions];
		return;
	}

	if ([title isEqualToString:@"Clear history"]){
		[self confirmClearHistory];
		return;
	}

	if (!self.userId)
		return;
	[self toggleBlockedState];
}

- (void)promptToAddContact {
	UIAlertView *ask = [[UIAlertView alloc] initWithTitle:@"Add Contact"
			message:@"Share your phone number with them?"
		   delegate:self cancelButtonTitle:@"Don't Share"
		   otherButtonTitles:@"Share", nil];
	ask.tag = 83;
	[ask show];
}

- (void)showContactPhotoActions {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
			delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
			otherButtonTitles:@"Choose Photo", @"Suggest Photo",
							  @"Remove Photo", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 84;
	[sheet showInView:self.view];
}

- (void)confirmLeaveGroup {
	UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:@"Leave Group"
			message:@"You will stop receiving messages from this group."
		   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Leave", nil];
	confirm.tag = 72;
	[confirm show];
}

- (void)pushContactForwardPicker {
	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	NSString *name = self.name;
	__weak typeof(self) weakSelf = self;
	picker.onPicked = ^(int64_t targetChatId){
		NSString *phone = weakSelf.phoneNumber;
		if (!phone.length){
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Share contact"
					message:@"This account does not show its phone number."
				   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
			return;
		}
		[[TGClient shared] sendContactNamed:name phone:phone toChat:targetChatId];
	};
	[self.navigationController pushViewController:picker animated:YES];
}

- (void)showAutoDeleteActions {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Delete messages after"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:@"Off", @"1 day",
														   @"1 week", @"1 month", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 70;
	[sheet showInView:self.view];
}

- (void)confirmClearHistory {
	UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:@"Clear history"
			message:@"Every message in this chat will be removed for you."
		   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Clear", nil];
	confirm.tag = 71;
	[confirm show];
}

- (void)toggleBlockedState {
	BOOL blocked = !self.blocked;
	[[TGClient shared] setUser:self.userId blocked:blocked];
	self.blocked = blocked;
	[self showToast:(blocked ? @"User blocked" : @"User unblocked")];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] isUserBlocked:self.userId completion:^(BOOL actual){
		weakSelf.blocked = actual;
	}];
}

- (void)addContactSharingPhone:(BOOL)share {
	if (!self.userId)
		return;
	NSString *phone = self.phoneNumber ?: @"";
	NSString *first = self.firstName.length ? self.firstName
											: (TGProfileText(self.name) ?: phone);
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] addContactWithUserId:self.userId
									  phone:phone
								  firstName:(first ?: @"")
								   lastName:(self.lastName ?: @"")
						   sharePhoneNumber:share
								 completion:^(BOOL ok){
		if (ok){
			weakSelf.isContact = YES;
			[weakSelf loadContactFlags];
			[weakSelf rebuildDetailRows];
		}
		[weakSelf showToast:(ok ? @"Added to contacts" : @"Could not add contact")];
	}];
}

- (void)loadContactFlags {
	if (!self.userId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] contactFlagsForUser:self.userId
								completion:^(NSDictionary *flags){
		if (![flags isKindOfClass:[NSDictionary class]])
			return;
		BOOL contact = TGProfileBool(flags[@"isContact"])
				|| TGProfileBool(flags[@"isMutualContact"]);
		NSString *note = nil;
		if (TGProfileBool(flags[@"isCloseFriend"]))
			note = @"Close friend";
		else if (TGProfileBool(flags[@"isMutualContact"]))
			note = @"Mutual contact";
		else if (TGProfileBool(flags[@"isSupport"]))
			note = @"Telegram support";
		weakSelf.isContact = contact;
		weakSelf.contactRelation = note;
		[weakSelf rebuildDetailRows];
	}];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == 84){
		[self handleContactPhotoSheetIndex:index];
		return;
	}

	if (sheet.tag == 85){
		[self handleReportOptionSheetIndex:index];
		return;
	}

	if (sheet.tag == 87){
		[self handleChatPhotoSheetIndex:index];
		return;
	}

	if (sheet.tag == 89){
		if (index == 0)
			[self convertToBroadcastGroup];
		return;
	}

	if (sheet.tag == 92){
		[self runInviteLinkAction:[sheet buttonTitleAtIndex:index]];
		return;
	}

	if (sheet.tag == 94){
		if (index == 0)
			[self setForumMode:NO];
		return;
	}

	if (sheet.tag == 77){
		[self pickStoryPhotoFromCamera:(index == 0)];
		return;
	}

	if (sheet.tag == 78){
		[self handleStoryPrivacySheetIndex:index];
		return;
	}

	if (sheet.tag == 79){
		[self handleChatHistorySheetIndex:index];
		return;
	}

	if (sheet.tag == 76){
		[self handleDiscussionSheetIndex:index];
		return;
	}

	if (sheet.tag == 75){
		[self handleDiscussionCandidateSheetIndex:index];
		return;
	}

	if (sheet.tag == 74){
		[self applySlowModePresetAtIndex:index];
		return;
	}

	if (sheet.tag != 70)
		return;
	[self applyAutoDeletePresetAtIndex:index];
}

- (void)handleContactPhotoSheetIndex:(NSInteger)index {
	if (index == 0 || index == 1){
		[self pickPersonalPhotoSuggesting:(index == 1)];
		return;
	}
	if (index == 2)
		[self removePersonalPhoto];
}

- (void)handleReportOptionSheetIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.reportOptions.count)
		return;
	NSDictionary *option = self.reportOptions[index];
	[self reportGroupWithOption:TGProfileText(option[@"id"]) text:nil];
}

- (void)handleChatPhotoSheetIndex:(NSInteger)index {
	if (index == 0)
		[self pickChatPhoto];
	else if (index == 1)
		[self removeChatPhoto];
}

- (void)handleStoryPrivacySheetIndex:(NSInteger)index {
	NSArray *values = @[@"everyone", @"contacts", @"closeFriends"];
	if (index < 0 || index >= (NSInteger)values.count)
		return;
	self.storyPrivacy = values[index];
	[self askStoryCaption];
}

- (void)handleChatHistorySheetIndex:(NSInteger)index {
	if (index != 0 && index != 1)
		return;
	[self setHistoryAvailableTo:(index == 0)];
}

- (void)handleDiscussionSheetIndex:(NSInteger)index {
	if (index == 0){
		[self openChatId:self.discussionChatId title:self.discussionTitle];
		return;
	}
	if (index == 1)
		[self linkDiscussionChat:0];
}

- (void)handleDiscussionCandidateSheetIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.discussionCandidates.count)
		return;
	NSDictionary *chat = self.discussionCandidates[index];
	[self linkDiscussionChat:TGProfileInt64(chat[@"id"])];
}

- (void)applyAutoDeletePresetAtIndex:(NSInteger)index {
	static const NSInteger seconds[4] = {0, 86400, 604800, 2592000};
	if (index < 0 || index > 3)
		return;
	if (!self.chatId)
		return;
	[[TGClient shared] setChat:self.chatId autoDeleteSeconds:seconds[index]];
	[self showToast:(index == 0 ? @"Auto-delete off" : @"Auto-delete on")];
}

- (void)runInviteLinkAction:(NSString *)pressed {
	if ([pressed isEqualToString:@"Copy Link"]){
		[UIPasteboard generalPasteboard].string = self.primaryInviteLink ?: @"";
		[self showToast:@"Invite link copied"];
		return;
	}
	if ([pressed isEqualToString:@"Who Joined"]){
		[self openLinkJoins];
		return;
	}
	if ([pressed isEqualToString:@"Revoke and Create New"] && self.isChatAdmin)
		[self replacePrimaryInviteLink];
}

- (void)applySlowModePresetAtIndex:(NSInteger)index {
	NSArray *presets = [TGClient slowModePresets];
	if (index < 0 || index >= (NSInteger)presets.count)
		return;
	id preset = presets[index];
	NSInteger seconds = [preset isKindOfClass:[NSNumber class]]
			? [preset integerValue] : 0;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setSlowModeDelay:seconds forChat:self.chatId
							 completion:^(BOOL ok){
		if (ok){
			weakSelf.slowModeDelay = seconds;
			[weakSelf loadManagement];
		}
		[weakSelf showToast:(ok ? @"Slow mode updated" : @"Could not change slow mode")];
	}];
}

- (NSString *)textFromAlert:(UIAlertView *)alert {
	if (![alert respondsToSelector:@selector(textFieldAtIndex:)])
		return nil;
	return TGProfileText([alert textFieldAtIndex:0].text);
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
	if (alert.tag == 83){
		[self addContactSharingPhone:(index != alert.cancelButtonIndex)];
		return;
	}
	if (index == alert.cancelButtonIndex)
		return;
	if (alert.tag == 86){
		NSString *text = [self textFromAlert:alert];
		[self reportGroupWithOption:self.reportOptionId text:(text ?: @"")];
		return;
	}
	if (alert.tag == 88){
		[self upgradeToSupergroup];
		return;
	}
	if (alert.tag == 93){
		[self setForumMode:YES];
		return;
	}
	if (alert.tag == 90 && self.chatId){
		[self setStickerSetNamed:[self textFromAlert:alert]];
		return;
	}
	if (alert.tag == 91 && self.chatId){
		NSString *description = [self textFromAlert:alert];
		[self saveChatDescription:(description ?: @"")];
		return;
	}
	if (alert.tag == 79){
		[self postStoryWithCaption:[self textFromAlert:alert]];
		return;
	}
	if (alert.tag == 82){
		[self deleteContactConfirmed];
		return;
	}
	if (alert.tag == 81 && self.userId){
		[self saveContactNote:[self textFromAlert:alert]];
		return;
	}
	if (alert.tag == 73 && self.chatId){
		[self renameChatTo:[self textFromAlert:alert]];
		return;
	}
	if (alert.tag == 71 && self.chatId){
		[self clearHistoryConfirmed];
	} else if (alert.tag == 72 && self.chatId){
		[self leaveGroupConfirmed];
	}
}

- (void)clearHistoryConfirmed {
	[[TGClient shared] clearHistoryInChat:self.chatId];
	self.photoCount = 0;
	self.fileCount = 0;
	[self.tableView reloadData];
	[self showToast:@"History cleared"];
}

- (void)leaveGroupConfirmed {
	[[TGClient shared] setChat:self.chatId joined:NO];
	[self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)saveContactNote:(NSString *)note {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setNote:(note ?: @"") forUser:self.userId
					completion:^(BOOL ok){
		if (ok){
			weakSelf.profileNote = note;
			weakSelf.noteLoaded = YES;
			[weakSelf rebuildDetailRows];
		}
		[weakSelf showToast:(ok ? @"Note saved" : @"Could not save the note")];
	}];
}

- (void)renameChatTo:(NSString *)title {
	if (!title.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setTitle:title forChat:self.chatId completion:^(BOOL ok){
		if (ok){
			weakSelf.name = title;
			weakSelf.nameLabel.text = title;
			[weakSelf layoutNameBadge];
			[weakSelf loadManagement];
		}
		[weakSelf showToast:(ok ? @"Name updated" : @"Could not rename")];
	}];
}

- (void)rebuildSections {
	NSMutableArray *kinds = [NSMutableArray array];
	if (self.canPostStory)
		[kinds addObject:@"story"];
	[kinds addObject:@"details"];
	[kinds addObject:@"actions"];
	if (self.personalChatId)
		[kinds addObject:@"personal"];
	if (self.manageRows.count)
		[kinds addObject:@"manage"];
	if (self.members.count)
		[kinds addObject:@"members"];
	[kinds addObject:@"media"];
	if (self.userId && self.isContact)
		[kinds addObject:@"delete"];
	self.sectionKinds = kinds;
}

- (NSString *)kindForSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sectionKinds.count)
		return @"media";
	return self.sectionKinds[section];
}

- (void)loadManagement {
	if (self.userId || !self.chatId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] groupInfoForChat:self.chatId completion:^(NSDictionary *info){
		if (![info isKindOfClass:[NSDictionary class]]){
			if (!weakSelf.managementLoaded){
				weakSelf.managementLoaded = YES;
				weakSelf.canListMembers = !weakSelf.isChannelChat;
			}
			[weakSelf rebuildManageRows];
			return;
		}
		NSString *status = TGProfileText(info[@"myStatus"]) ?: @"";
		BOOL admin = [status isEqualToString:@"creator"]
				|| [status isEqualToString:@"administrator"];
		weakSelf.isChatAdmin = admin;
		if (!admin){
			weakSelf.adminCount = 0;
			weakSelf.inviteLinkCount = 0;
			weakSelf.pendingJoinRequests = 0;
			weakSelf.manageFlagsKnown = NO;
			weakSelf.signaturesKnown = NO;
			weakSelf.discussionKnown = NO;
			weakSelf.canGetStatistics = NO;
			weakSelf.canHideMembers = NO;
			weakSelf.canToggleAntiSpam = NO;
		}
		weakSelf.canEditChat = TGProfileBool(info[@"canBeEdited"]) || admin;
		weakSelf.isChannelChat = TGProfileBool(info[@"isChannel"]);
		weakSelf.isSupergroupChat = TGProfileBool(info[@"isSupergroup"]);
		weakSelf.isForumChat = TGProfileBool(info[@"isForum"]);
		weakSelf.slowModeDelay = [info[@"slowModeDelay"] isKindOfClass:[NSNumber class]]
				? [info[@"slowModeDelay"] integerValue] : 0;

		weakSelf.historyAvailable = TGProfileBool(info[@"isAllHistoryAvailable"]);
		weakSelf.hiddenMembers = TGProfileBool(info[@"hasHiddenMembers"]);
		weakSelf.canHideMembers = TGProfileBool(info[@"canHideMembers"]);
		weakSelf.antiSpam = TGProfileBool(info[@"hasAggressiveAntiSpam"]);
		weakSelf.canToggleAntiSpam =
				TGProfileBool(info[@"canToggleAggressiveAntiSpam"]);
		weakSelf.pendingJoinRequests =
				[info[@"pendingJoinRequests"] isKindOfClass:[NSNumber class]]
						? [info[@"pendingJoinRequests"] integerValue] : 0;

		weakSelf.groupTitle = TGProfileText(info[@"title"]) ?: @"";
		weakSelf.canListMembers = TGProfileBool(info[@"canGetMembers"]) || admin
				|| !weakSelf.isChannelChat;
		weakSelf.managementLoaded = YES;
		[weakSelf rebuildManageRows];
		[weakSelf loadChannelExtras];
		[weakSelf loadForumTopicCount];
	}];
}

- (void)rebuildManageRows {
	if (!self.managementLoaded)
		return;
	BOOL admin = self.isChatAdmin;
	NSMutableArray *rows = [NSMutableArray array];
	[self appendMembershipManageRowsTo:rows admin:admin];
	[self appendChatEditingManageRowsTo:rows];
	[self appendChannelManageRowsTo:rows admin:admin];
	[self appendGroupManageRowsTo:rows admin:admin];
	[self appendFlagManageRowsTo:rows admin:admin];
	if (self.canGetStatistics)
		[rows addObject:@[@"Statistics", @"stats", @""]];
	if (self.boostsKnown)
		[rows addObject:@[@"Boosts", @"boosts",
						  [NSString stringWithFormat:@"Level %ld", (long)self.boostLevel]]];
	self.manageRows = rows;
	[self rebuildSections];
	[self.tableView reloadData];
}

- (void)appendMembershipManageRowsTo:(NSMutableArray *)rows admin:(BOOL)admin {
	if (self.canListMembers)
		[rows addObject:@[@"Members", @"members",
						  (self.memberCount > 0
								  ? [NSString stringWithFormat:@"%ld",
											  (long)self.memberCount] : @"")]];
	if (admin){
		[rows addObject:@[@"Administrators", @"admins",
						  (self.adminCount > 0
								  ? [NSString stringWithFormat:@"%ld",
											  (long)self.adminCount] : @"")]];
		[rows addObject:@[@"Invite Links", @"links",
						  (self.inviteLinkCount > 0
								  ? [NSString stringWithFormat:@"%ld",
											  (long)self.inviteLinkCount] : @"")]];
		[rows addObject:@[@"Recent Actions", @"events", @""]];
	}
}

- (void)appendChatEditingManageRowsTo:(NSMutableArray *)rows {
	if (!self.canEditChat)
		return;
	[rows addObject:@[(self.isChannelChat ? @"Channel Name" : @"Group Name"),
					  @"title", self.groupTitle ?: @""]];
	[rows addObject:@[@"Description", @"description",
					  (self.chatDescription.length ? self.chatDescription : @"")]];
	[rows addObject:@[@"Set Photo", @"photo", @""]];
}

- (void)appendChannelManageRowsTo:(NSMutableArray *)rows admin:(BOOL)admin {
	if (admin && self.isChannelChat && self.signaturesKnown){
		[rows addObject:@[@"Sign Messages", @"signatures",
						  (self.signMessages ? @"On" : @"Off")]];
		if (self.signMessages)
			[rows addObject:@[@"Show Author Profiles", @"authors",
							  (self.showAuthorProfiles ? @"On" : @"Off")]];
	}
	if (admin && self.isChannelChat && self.discussionKnown)
		[rows addObject:@[@"Discussion Group", @"discussion",
						  (self.discussionChatId ? (self.discussionTitle ?: @"Group")
												 : @"Off")]];
}

- (void)appendGroupManageRowsTo:(NSMutableArray *)rows admin:(BOOL)admin {
	if (!(admin && !self.isChannelChat))
		return;
	[rows addObject:@[@"Permissions", @"permissions", @""]];
	if (self.isSupergroupChat){
		[rows addObject:@[@"Slow Mode", @"slowmode",
						  [self slowModeTitle:self.slowModeDelay]]];
		[rows addObject:@[@"Group Stickers", @"stickers", @""]];
		[rows addObject:@[@"Topics", @"topics", [self forumRowValue]]];
		[rows addObject:@[@"Convert to Broadcast Group", @"broadcast", @""]];
	} else {
		[rows addObject:@[@"Upgrade to Supergroup", @"upgrade", @""]];
	}
}

- (void)appendFlagManageRowsTo:(NSMutableArray *)rows admin:(BOOL)admin {
	if (!(admin && self.manageFlagsKnown))
		return;
	if (self.isSupergroupChat && !self.isChannelChat)
		[rows addObject:@[@"Chat History", @"history",
						  (self.historyAvailable ? @"Visible" : @"Hidden")]];
	if (self.canHideMembers && !self.isChannelChat)
		[rows addObject:@[@"Hide Members", @"hidemembers",
						  (self.hiddenMembers ? @"On" : @"Off")]];
	if (self.canToggleAntiSpam && !self.isChannelChat)
		[rows addObject:@[@"Anti-Spam", @"antispam",
						  (self.antiSpam ? @"On" : @"Off")]];
	[rows addObject:@[@"Restrict Saving Content", @"protected",
					  (self.protectedContent ? @"On" : @"Off")]];
	if (self.pendingJoinRequests > 0)
		[rows addObject:@[@"Join Requests", @"requests",
						  [NSString stringWithFormat:@"%ld",
								  (long)self.pendingJoinRequests]]];
}

- (void)loadChannelExtras {
	if (self.userId || !self.chatId)
		return;
	__weak typeof(self) weakSelf = self;

	[[TGClient shared] groupMemberCount:self.chatId completion:^(NSInteger count){
		if (count <= 0 || count == weakSelf.memberCount)
			return;
		weakSelf.memberCount = count;
		[weakSelf rebuildManageRows];
	}];
	[self loadAdministrationSummary];

	[[TGClient shared] canGetStatisticsForChat:self.chatId completion:^(BOOL canGet){
		if (!canGet)
			return;
		weakSelf.canGetStatistics = YES;
		[weakSelf rebuildManageRows];
	}];

	if (self.isChatAdmin)
		[self loadManagementFlags];

	if (!self.isChannelChat && !self.isSupergroupChat)
		return;

	[self loadBoostSummary];

	if (!self.isChannelChat)
		return;

	[self loadChannelSignatures];
	[self loadDiscussionGroupLink];
}

- (void)loadManagementFlags {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] managementInfoForChat:self.chatId
								  completion:^(NSDictionary *info){
		if (![info isKindOfClass:[NSDictionary class]])
			return;
		weakSelf.protectedContent = TGProfileBool(info[@"hasProtectedContent"]);
		weakSelf.historyAvailable = TGProfileBool(info[@"isAllHistoryAvailable"]);
		weakSelf.hiddenMembers = TGProfileBool(info[@"hasHiddenMembers"]);
		weakSelf.canHideMembers = TGProfileBool(info[@"canHideMembers"]);
		weakSelf.antiSpam = TGProfileBool(info[@"hasAntiSpam"]);
		weakSelf.canToggleAntiSpam = TGProfileBool(info[@"canToggleAntiSpam"]);
		if ([info[@"pendingJoinRequests"] isKindOfClass:[NSNumber class]])
			weakSelf.pendingJoinRequests =
					[info[@"pendingJoinRequests"] integerValue];
		weakSelf.manageFlagsKnown = YES;
		[weakSelf rebuildManageRows];
	}];
}

- (void)loadBoostSummary {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] boostStatusForChat:self.chatId completion:^(NSDictionary *status){
		if (![status isKindOfClass:[NSDictionary class]])
			return;
		weakSelf.boostsKnown = YES;
		weakSelf.boostLevel = [status[@"level"] isKindOfClass:[NSNumber class]]
				? [status[@"level"] integerValue] : 0;
		[weakSelf rebuildManageRows];
	}];
}

- (void)loadChannelSignatures {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] channelSignaturesForChat:self.chatId
									 completion:^(NSDictionary *info){
		if (![info isKindOfClass:[NSDictionary class]])
			return;
		weakSelf.signaturesKnown = YES;
		weakSelf.signMessages = TGProfileBool(info[@"sign_messages"]);
		weakSelf.showAuthorProfiles = TGProfileBool(info[@"show_message_sender"]);
		[weakSelf rebuildManageRows];
	}];
}

- (void)loadDiscussionGroupLink {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] discussionGroupForChannel:self.chatId
									  completion:^(NSNumber *linkedChatId){
		weakSelf.discussionKnown = YES;
		weakSelf.discussionChatId = [linkedChatId isKindOfClass:[NSNumber class]]
				? [linkedChatId longLongValue] : 0;
		[weakSelf rebuildManageRows];
		if (!weakSelf.discussionChatId)
			return;
		[[TGClient shared] titleForChatId:weakSelf.discussionChatId
							   completion:^(NSString *title){
			weakSelf.discussionTitle = TGProfileText(title);
			[weakSelf rebuildManageRows];
		}];
	}];
}

- (void)loadAdministrationSummary {
	if (!self.isChatAdmin || !self.chatId)
		return;
	__weak typeof(self) weakSelf = self;

	[[TGClient shared] administratorsInGroup:self.chatId completion:^(NSArray *admins){
		if (![admins isKindOfClass:[NSArray class]])
			return;
		weakSelf.adminCount = (NSInteger)admins.count;
		[weakSelf rebuildManageRows];
	}];

	[[TGClient shared] inviteLinkCountsInGroup:self.chatId completion:^(NSArray *counts){
		if (![counts isKindOfClass:[NSArray class]])
			return;
		NSInteger total = 0;
		for (id entry in counts){
			if (![entry isKindOfClass:[NSDictionary class]])
				continue;
			id count = [entry objectForKey:@"linkCount"];
			if ([count isKindOfClass:[NSNumber class]])
				total += [count integerValue];
		}
		weakSelf.inviteLinkCount = total;
		[weakSelf rebuildManageRows];
	}];

	[[TGClient shared] pendingJoinRequestCountForChat:self.chatId
										   completion:^(NSInteger count){
		if (count == weakSelf.pendingJoinRequests)
			return;
		weakSelf.pendingJoinRequests = count;
		[weakSelf rebuildManageRows];
	}];

	[[TGClient shared] membersJoinedViaPrimaryInviteLinkInChat:self.chatId
														 limit:1
													completion:^(NSArray *members,
																 NSInteger total){
		weakSelf.primaryLinkJoinCount = total;
	}];

	if (self.primaryInviteLink.length)
		return;
	[[TGClient shared] primaryInviteLinkForGroup:self.chatId
									  completion:^(NSDictionary *link){
		NSString *text = [link isKindOfClass:[NSDictionary class]]
				? TGProfileText(link[@"link"]) : nil;
		if (!text)
			return;
		weakSelf.primaryInviteLink = text;
		[weakSelf setDetail:text forLabel:@"invite link"];
	}];
}

- (void)showInviteLinkActions {
	if (!self.primaryInviteLink.length)
		return;
	NSString *title = self.primaryInviteLink;
	if (self.primaryLinkJoinCount > 0)
		title = [NSString stringWithFormat:@"%@\n%ld joined through this link",
				self.primaryInviteLink, (long)self.primaryLinkJoinCount];
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title
			delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
			otherButtonTitles:@"Copy Link", nil];
	if (self.isChatAdmin && self.primaryLinkJoinCount > 0)
		[sheet addButtonWithTitle:@"Who Joined"];
	if (self.isChatAdmin)
		[sheet addButtonWithTitle:@"Revoke and Create New"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 92;
	[sheet showInView:self.view];
}

- (void)replacePrimaryInviteLink {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] replacePrimaryInviteLinkForGroup:self.chatId
											 completion:^(NSDictionary *link){
		NSString *text = [link isKindOfClass:[NSDictionary class]]
				? TGProfileText(link[@"link"]) : nil;
		if (!text){
			[weakSelf showToast:@"Could not replace the link"];
			return;
		}
		weakSelf.primaryInviteLink = text;
		weakSelf.primaryLinkJoinCount = 0;
		[weakSelf setDetail:text forLabel:@"invite link"];
		[weakSelf showToast:@"New invite link created"];
	}];
}

- (void)toggleSignatures:(BOOL)authorsRow {
	BOOL sign = self.signMessages;
	BOOL authors = self.showAuthorProfiles;
	if (authorsRow)
		authors = !authors;
	else
		sign = !sign;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setChannelSignaturesForChat:self.chatId
									  signMessages:sign
								showAuthorProfiles:authors
										completion:^(BOOL ok){
		if (ok){
			weakSelf.signMessages = sign;
			weakSelf.showAuthorProfiles = authors;
			[weakSelf rebuildManageRows];
		}
		[weakSelf showToast:(ok ? @"Signatures updated"
								: @"Could not change signatures")];
	}];
}

- (void)setHistoryAvailableTo:(BOOL)available {
	if (available == self.historyAvailable)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setChat:self.chatId allHistoryAvailable:available
					completion:^(BOOL ok){
		if (ok){
			weakSelf.historyAvailable = available;
			[weakSelf rebuildManageRows];
			[[TGClient shared] isAllHistoryAvailableForChat:weakSelf.chatId
												 completion:^(BOOL actual){
				if (actual == weakSelf.historyAvailable)
					return;
				weakSelf.historyAvailable = actual;
				[weakSelf rebuildManageRows];
			}];
		}
		[weakSelf showToast:(ok ? (available ? @"History is visible to new members"
											 : @"History is hidden from new members")
								: @"Could not change the history setting")];
	}];
}

- (void)toggleHiddenMembers {
	BOOL hidden = !self.hiddenMembers;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setChat:self.chatId hiddenMembers:hidden
					completion:^(BOOL ok){
		if (ok){
			weakSelf.hiddenMembers = hidden;
			[weakSelf rebuildManageRows];
		}
		[weakSelf showToast:(ok ? (hidden ? @"Member list hidden"
										  : @"Member list visible")
								: @"Could not change the member list")];
	}];
}

- (void)toggleAntiSpam {
	BOOL enabled = !self.antiSpam;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setChat:self.chatId antiSpamEnabled:enabled
					completion:^(BOOL ok){
		if (ok){
			weakSelf.antiSpam = enabled;
			[weakSelf rebuildManageRows];
		}
		[weakSelf showToast:(ok ? (enabled ? @"Anti-spam on" : @"Anti-spam off")
								: @"Could not change anti-spam")];
	}];
}

- (void)toggleProtectedContent {
	BOOL restricted = !self.protectedContent;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setChat:self.chatId protectedContent:restricted
					completion:^(BOOL ok){
		if (ok){
			weakSelf.protectedContent = restricted;
			[weakSelf rebuildManageRows];
		}
		[weakSelf showToast:(ok ? (restricted ? @"Saving content restricted"
											  : @"Saving content allowed")
								: @"Could not change content protection")];
	}];
}

- (NSString *)forumRowValue {
	if (!self.isForumChat)
		return @"Off";
	if (!self.forumTopicsKnown)
		return @"On";
	if (self.forumTopicCount == 1)
		return @"1 topic";
	return [NSString stringWithFormat:@"%ld topics", (long)self.forumTopicCount];
}

- (void)loadForumTopicCount {
	if (!self.chatId || !self.isForumChat)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] forumTopicRowsForChat:self.chatId completion:^(NSArray *topics){
		if (![topics isKindOfClass:[NSArray class]])
			return;
		weakSelf.forumTopicsKnown = YES;
		weakSelf.forumTopicCount = (NSInteger)topics.count;
		[weakSelf rebuildManageRows];
	}];
}

- (void)setForumMode:(BOOL)isForum {
	if (!self.chatId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] managementInfoForChat:self.chatId
								  completion:^(NSDictionary *info){
		int64_t supergroupId = [info isKindOfClass:[NSDictionary class]]
				? TGProfileInt64(info[@"supergroupId"]) : 0;
		if (!supergroupId){
			[weakSelf showToast:@"Only the owner can change topics"];
			return;
		}
		[weakSelf applyForumMode:isForum toSupergroup:supergroupId];
	}];
}

- (void)applyForumMode:(BOOL)isForum toSupergroup:(int64_t)supergroupId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setSupergroup:supergroupId
							 isForum:isForum
							 hasTabs:NO
						  completion:^(BOOL success){
		if (success){
			weakSelf.isForumChat = isForum;
			weakSelf.forumTopicsKnown = NO;
			weakSelf.forumTopicCount = 0;
			[weakSelf rebuildManageRows];
			[weakSelf loadForumTopicCount];
		}
		[weakSelf showToast:(success ? (isForum ? @"Topics turned on"
												: @"Topics turned off")
									 : @"Only the owner can change topics")];
	}];
}

- (void)openLinkJoins {
	if (!self.primaryInviteLink.length || !self.navigationController)
		return;
	TGProfileLinkJoinsController *joins =
			[[TGProfileLinkJoinsController alloc] initWithStyle:UITableViewStylePlain];
	joins.chatId = self.chatId;
	joins.link = self.primaryInviteLink;
	[self.navigationController pushViewController:joins animated:YES];
}

- (void)openDiscussionGroup {
	if (self.discussionChatId){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Discussion group"
				delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
				otherButtonTitles:@"Open", @"Unlink", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 76;
		[sheet showInView:self.view];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] suitableDiscussionChatsWithCompletion:^(NSArray *chats){
		NSMutableArray *usable = [NSMutableArray array];
		if (![chats isKindOfClass:[NSArray class]])
			chats = @[];
		for (id chat in chats){
			if (![chat isKindOfClass:[NSDictionary class]])
				continue;
			if (TGProfileInt64(chat[@"id"]))
				[usable addObject:chat];
		}
		if (!usable.count){
			[weakSelf showToast:@"No group to link"];
			return;
		}
		weakSelf.discussionCandidates = usable;
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Link a group"
				delegate:weakSelf cancelButtonTitle:nil destructiveButtonTitle:nil
				otherButtonTitles:nil];
		for (NSDictionary *chat in usable)
			[sheet addButtonWithTitle:(TGProfileText(chat[@"title"]) ?: @"Group")];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 75;
		[sheet showInView:weakSelf.view];
	}];
}

- (void)linkDiscussionChat:(int64_t)discussionChatId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setDiscussionGroup:discussionChatId
							   forChannel:self.chatId
							   completion:^(BOOL ok){
		if (ok){
			weakSelf.discussionChatId = discussionChatId;
			weakSelf.discussionTitle = nil;
			[weakSelf rebuildManageRows];
			if (discussionChatId)
				[[TGClient shared] titleForChatId:discussionChatId
									   completion:^(NSString *title){
					weakSelf.discussionTitle = TGProfileText(title);
					[weakSelf rebuildManageRows];
				}];
		}
		[weakSelf showToast:(ok ? (discussionChatId ? @"Discussion group linked"
													: @"Discussion group removed")
								: @"Could not change the discussion group")];
	}];
}

- (void)openChatId:(int64_t)chatId title:(NSString *)title {
	if (!chatId)
		return;
	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = chatId;
	chat.chatTitle = title ?: @"";
	[self.navigationController pushViewController:chat animated:YES];
}

- (NSString *)slowModeTitle:(NSInteger)seconds {
	if (seconds <= 0)
		return @"Off";
	if (seconds < 60)
		return [NSString stringWithFormat:@"%lds", (long)seconds];
	if (seconds < 3600)
		return [NSString stringWithFormat:@"%ldm", (long)(seconds / 60)];
	return [NSString stringWithFormat:@"%ldh", (long)(seconds / 3600)];
}

- (void)openManageRow:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.manageRows.count)
		return;
	NSString *key = self.manageRows[row][1];
	UINavigationController *navigation = self.navigationController;

	if ([key isEqualToString:@"members"] || [key isEqualToString:@"admins"]){
		[self pushGroupMembersInto:navigation
					   adminsFirst:[key isEqualToString:@"admins"]];
		return;
	}

	if ([key isEqualToString:@"links"]){
		[self pushInviteLinksInto:navigation];
		return;
	}

	if ([key isEqualToString:@"events"]){
		[self pushChatEventsInto:navigation];
		return;
	}

	if ([key isEqualToString:@"title"]){
		[self promptForChatTitle];
		return;
	}

	if ([key isEqualToString:@"photo"]){
		[self showChatPhotoActions];
		return;
	}

	if ([key isEqualToString:@"description"]){
		[self promptForChatDescription];
		return;
	}

	if ([key isEqualToString:@"stickers"]){
		[self promptForStickerSet];
		return;
	}

	if ([key isEqualToString:@"upgrade"]){
		[self confirmUpgradeToSupergroup];
		return;
	}

	if ([key isEqualToString:@"broadcast"]){
		[self confirmConvertToBroadcast];
		return;
	}

	if ([key isEqualToString:@"topics"]){
		[self confirmForumModeChange];
		return;
	}

	if ([key isEqualToString:@"signatures"] || [key isEqualToString:@"authors"]){
		[self toggleSignatures:[key isEqualToString:@"authors"]];
		return;
	}

	if ([key isEqualToString:@"history"]){
		[self showChatHistoryActions];
		return;
	}

	if ([key isEqualToString:@"hidemembers"]){
		[self toggleHiddenMembers];
		return;
	}

	if ([key isEqualToString:@"antispam"]){
		[self toggleAntiSpam];
		return;
	}

	if ([key isEqualToString:@"protected"]){
		[self toggleProtectedContent];
		return;
	}

	if ([key isEqualToString:@"requests"]){
		[self pushInviteLinksInto:navigation];
		return;
	}

	if ([key isEqualToString:@"discussion"]){
		[self openDiscussionGroup];
		return;
	}

	if ([key isEqualToString:@"stats"]){
		[self pushStatisticsInto:navigation];
		return;
	}

	if ([key isEqualToString:@"boosts"]){
		[self pushBoostsInto:navigation];
		return;
	}

	if ([key isEqualToString:@"permissions"]){
		[self pushPermissionsInto:navigation];
		return;
	}

	if ([key isEqualToString:@"slowmode"])
		[self showSlowModeActions];
}

- (void)pushGroupMembersInto:(UINavigationController *)navigation
				 adminsFirst:(BOOL)adminsFirst {
	TGGroupMembersViewController *members =
			[[TGGroupMembersViewController alloc] init];
	members.chatId = self.chatId;
	members.initialMode = adminsFirst ? 1 : 0;
	[navigation pushViewController:members animated:YES];
}

- (void)pushInviteLinksInto:(UINavigationController *)navigation {
	TGInviteLinksViewController *links =
			[[TGInviteLinksViewController alloc] initWithChatId:self.chatId];
	[navigation pushViewController:links animated:YES];
}

- (void)pushChatEventsInto:(UINavigationController *)navigation {
	TGChatEventsViewController *events =
			[[TGChatEventsViewController alloc] initWithChatId:self.chatId];
	events.chatTitle = TGProfileText(self.name);
	[navigation pushViewController:events animated:YES];
}

- (void)pushStatisticsInto:(UINavigationController *)navigation {
	TGProfileStatisticsController *stats =
			[[TGProfileStatisticsController alloc] init];
	stats.chatId = self.chatId;
	[navigation pushViewController:stats animated:YES];
}

- (void)pushBoostsInto:(UINavigationController *)navigation {
	TGProfileBoostsController *boosts =
			[[TGProfileBoostsController alloc] initWithStyle:UITableViewStyleGrouped];
	boosts.chatId = self.chatId;
	boosts.isChannel = self.isChannelChat;
	[navigation pushViewController:boosts animated:YES];
}

- (void)pushPermissionsInto:(UINavigationController *)navigation {
	TGProfilePermissionsController *permissions =
			[[TGProfilePermissionsController alloc] initWithStyle:UITableViewStyleGrouped];
	permissions.chatId = self.chatId;
	[navigation pushViewController:permissions animated:YES];
}

- (void)promptForChatTitle {
	UIAlertView *rename = [[UIAlertView alloc] initWithTitle:nil
			message:(self.isChannelChat ? @"Channel name" : @"Group name")
		   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Done", nil];
	rename.tag = 73;
	if ([rename respondsToSelector:@selector(setAlertViewStyle:)]){
		rename.alertViewStyle = UIAlertViewStylePlainTextInput;
		[rename textFieldAtIndex:0].text = TGProfileText(self.name) ?: @"";
	}
	[rename show];
}

- (void)showChatPhotoActions {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
			delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
			otherButtonTitles:@"Choose Photo", @"Remove Photo", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 87;
	[sheet showInView:self.view];
}

- (void)promptForChatDescription {
	UIAlertView *editor = [[UIAlertView alloc] initWithTitle:nil
			message:@"Description" delegate:self cancelButtonTitle:@"Cancel"
			otherButtonTitles:@"Done", nil];
	editor.tag = 91;
	if ([editor respondsToSelector:@selector(setAlertViewStyle:)]){
		editor.alertViewStyle = UIAlertViewStylePlainTextInput;
		[editor textFieldAtIndex:0].text = self.chatDescription ?: @"";
	}
	[editor show];
}

- (void)promptForStickerSet {
	UIAlertView *editor = [[UIAlertView alloc] initWithTitle:nil
			message:@"Sticker set name" delegate:self cancelButtonTitle:@"Cancel"
			otherButtonTitles:@"Done", nil];
	editor.tag = 90;
	if ([editor respondsToSelector:@selector(setAlertViewStyle:)])
		editor.alertViewStyle = UIAlertViewStylePlainTextInput;
	[editor show];
}

- (void)confirmUpgradeToSupergroup {
	UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:@"Upgrade to Supergroup"
			message:@"Supergroups keep their history for new members and hold "
					@"many more people. This cannot be undone."
		   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Upgrade", nil];
	confirm.tag = 88;
	[confirm show];
}

- (void)confirmConvertToBroadcast {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:
			@"Only administrators will be able to post. This cannot be undone."
			delegate:self cancelButtonTitle:nil
			destructiveButtonTitle:@"Convert to Broadcast Group"
			otherButtonTitles:nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 89;
	[sheet showInView:self.view];
}

- (void)confirmForumModeChange {
	if (self.isForumChat){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:
				@"Messages will go back to one list and the topics will be lost."
				delegate:self cancelButtonTitle:nil
				destructiveButtonTitle:@"Turn Off Topics"
				otherButtonTitles:nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 94;
		[sheet showInView:self.view];
		return;
	}
	UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:@"Topics"
			message:@"Members will be able to open separate topics instead of "
					@"one message list. Only the owner may change this."
		   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Turn On", nil];
	confirm.tag = 93;
	[confirm show];
}

- (void)showChatHistoryActions {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Chat history for new members"
			delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
			otherButtonTitles:@"Visible", @"Hidden", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 79;
	[sheet showInView:self.view];
}

- (void)showSlowModeActions {
	NSArray *presets = [TGClient slowModePresets];
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Slow mode"
			delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
			otherButtonTitles:nil];
	for (id preset in presets){
		NSInteger seconds = [preset isKindOfClass:[NSNumber class]]
				? [preset integerValue] : 0;
		[sheet addButtonWithTitle:(seconds <= 0 ? @"Off"
				: [self slowModeTitle:seconds])];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 74;
	[sheet showInView:self.view];
}

- (void)pickChatPhoto {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary]){
		[self showToast:@"No photo library"];
		return;
	}
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.allowsEditing = YES;
	picker.delegate = self;
	self.pickerMode = kPickerModeChatPhoto;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)pickPersonalPhotoSuggesting:(BOOL)suggest {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary]){
		[self showToast:@"No photo library"];
		return;
	}
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.allowsEditing = YES;
	picker.delegate = self;
	self.pickerMode = suggest ? kPickerModeSuggestPhoto : kPickerModePersonalPhoto;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)removeChatPhoto {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] removePhotoForChat:self.chatId completion:^(BOOL ok){
		if (ok){
			[weakSelf cancelAvatarDownload];
			weakSelf.avatarImage = nil;
			weakSelf.avatarIsPlaceholder = NO;
			weakSelf.avatarView.image =
					[TGIcons avatarWithInitials:TGProfileInitial(weakSelf.name)
										   size:kProfileAvatarSide
									   colourId:weakSelf.chatId];
		}
		[weakSelf showToast:(ok ? @"Photo removed" : @"Could not remove the photo")];
	}];
}

- (void)removePersonalPhoto {
	if (!self.userId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] removePersonalPhotoForUser:self.userId completion:^(BOOL ok){
		[weakSelf showToast:(ok ? @"Photo removed" : @"Could not remove the photo")];
	}];
}

- (void)upgradeToSupergroup {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] upgradeBasicGroupToSupergroup:self.chatId
										  completion:^(int64_t newChatId){
		if (!newChatId){
			[weakSelf showToast:@"Could not upgrade this group"];
			return;
		}
		weakSelf.chatId = newChatId;
		weakSelf.managementLoaded = NO;
		weakSelf.manageFlagsKnown = NO;
		weakSelf.manageRows = @[];
		[weakSelf rebuildSections];
		[weakSelf.tableView reloadData];
		[weakSelf loadDetails];
		[weakSelf refreshStatus];
		[weakSelf showToast:@"Group upgraded"];
	}];
}

- (void)convertToBroadcastGroup {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] convertGroupToBroadcastGroup:self.chatId completion:^(BOOL ok){
		if (ok)
			[weakSelf loadManagement];
		[weakSelf showToast:(ok ? @"Converted to a broadcast group"
								: @"Could not convert this group")];
	}];
}

- (void)setStickerSetNamed:(NSString *)name {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setGroup:self.chatId
				 stickerSetName:(name.length ? name : nil)
					 completion:^(BOOL ok){
		if (ok){
			[weakSelf showToast:(name.length ? @"Group stickers set"
											 : @"Group stickers removed")];
			return;
		}
		[weakSelf showToast:@"No sticker set with that name"];
	}];
}

- (void)saveChatDescription:(NSString *)description {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setDescription:(description ?: @"")
							  forChat:self.chatId
						   completion:^(BOOL ok){
		if (ok){
			weakSelf.chatDescription = description.length ? description : nil;
			if (description.length){
				[weakSelf setDetail:description forLabel:@"about"];
			} else {
				NSMutableArray *kept = [NSMutableArray array];
				for (NSArray *pair in weakSelf.details){
					if (pair.count > 0 && [pair[0] isEqualToString:@"about"])
						continue;
					[kept addObject:pair];
				}
				weakSelf.details = kept;
				[weakSelf.tableView reloadData];
			}
			[weakSelf rebuildManageRows];
		}
		[weakSelf showToast:(ok ? @"Description saved"
								: @"Could not save the description")];
	}];
}

- (void)reportGroupWithOption:(NSString *)optionId text:(NSString *)text {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] reportGroup:self.chatId optionId:optionId text:text
						completion:^(NSString *status, NSString *title,
									 NSArray *options, BOOL optional){
		if ([status isEqualToString:@"ok"]){
			[weakSelf showToast:@"Report sent"];
			return;
		}
		if ([status isEqualToString:@"options"]){
			[weakSelf showReportOptionsSheet:options title:title];
			return;
		}
		if ([status isEqualToString:@"text"]){
			[weakSelf promptForReportTextWithTitle:title optionId:optionId];
			return;
		}
		[weakSelf showToast:@"Could not send the report"];
	}];
}

- (void)showReportOptionsSheet:(NSArray *)options title:(NSString *)title {
	NSMutableArray *usable = [NSMutableArray array];
	if (![options isKindOfClass:[NSArray class]])
		options = @[];
	for (id option in options){
		if (![option isKindOfClass:[NSDictionary class]])
			continue;
		if (TGProfileText(option[@"id"]) && TGProfileText(option[@"text"]))
			[usable addObject:option];
	}
	if (!usable.count){
		[self showToast:@"Could not send the report"];
		return;
	}
	self.reportOptions = usable;
	UIActionSheet *sheet = [[UIActionSheet alloc]
			initWithTitle:(TGProfileText(title) ?: @"Report")
				 delegate:self cancelButtonTitle:nil
		   destructiveButtonTitle:nil otherButtonTitles:nil];
	for (NSDictionary *option in usable)
		[sheet addButtonWithTitle:TGProfileText(option[@"text"])];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 85;
	[sheet showInView:self.view];
}

- (void)promptForReportTextWithTitle:(NSString *)title optionId:(NSString *)optionId {
	self.reportOptionId = optionId;
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil
			message:(TGProfileText(title) ?: @"Describe the problem")
		   delegate:self cancelButtonTitle:@"Cancel"
		   otherButtonTitles:@"Send", nil];
	alert.tag = 86;
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)])
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	[alert show];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	self.pickerMode = kPickerModeChatPhoto;
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)writeJpegOf:(UIImage *)image maxSide:(CGFloat)maxSide named:(NSString *)name {
	CGFloat side = MAX(image.size.width, image.size.height);
	UIImage *scaled = image;
	if (side > maxSide){
		CGFloat factor = maxSide / side;
		CGSize target = CGSizeMake(floorf(image.size.width * factor),
								   floorf(image.size.height * factor));
		UIGraphicsBeginImageContextWithOptions(target, YES, 1.0f);
		[image drawInRect:CGRectMake(0, 0, target.width, target.height)];
		scaled = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	}
	NSData *data = UIImageJPEGRepresentation(scaled, 0.87f);
	if (!data.length)
		return nil;
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	return [data writeToFile:path atomically:YES] ? path : nil;
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	NSInteger mode = self.pickerMode;
	self.pickerMode = kPickerModeChatPhoto;
	[self dismissViewControllerAnimated:YES completion:nil];
	UIImage *image = info[UIImagePickerControllerEditedImage]
			?: info[UIImagePickerControllerOriginalImage];
	if (![image isKindOfClass:[UIImage class]])
		return;

	if (mode == kPickerModePersonalPhoto || mode == kPickerModeSuggestPhoto){
		[self applyPickedPersonalPhoto:image
							   suggest:(mode == kPickerModeSuggestPhoto)];
		return;
	}

	if (mode == kPickerModeStory){
		[self applyPickedStoryPhoto:image];
		return;
	}

	[self applyPickedChatPhoto:image];
}

- (void)applyPickedPersonalPhoto:(UIImage *)image suggest:(BOOL)suggest {
	if (!self.userId)
		return;
	NSString *personalPath = [self writeJpegOf:image maxSide:640.0f
										 named:@"personal-photo.jpg"];
	if (!personalPath){
		[self showToast:@"Could not prepare the photo"];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPersonalPhotoAtPath:personalPath
									  forUser:self.userId
									  suggest:suggest
								   completion:^(BOOL ok){
		if (ok && !suggest){
			UIImage *preview = TGDecodeSquareThumbnail(personalPath,
													   kProfileAvatarSide);
			if (preview){
				[weakSelf cancelAvatarDownload];
				weakSelf.avatarImage = preview;
				weakSelf.avatarIsPlaceholder = NO;
				[weakSelf setAvatarViewImage:preview crossfade:YES];
			}
		}
		if (ok)
			[weakSelf showToast:(suggest ? @"Photo suggested" : @"Photo set")];
		else
			[weakSelf showToast:@"Could not set the photo"];
	}];
}

- (void)applyPickedStoryPhoto:(UIImage *)image {
	self.storyPath = [self writeJpegOf:image maxSide:720.0f named:@"story.jpg"];
	if (!self.storyPath){
		[self showToast:@"Could not prepare the photo"];
		return;
	}
	[self askStoryPrivacy];
}

- (void)applyPickedChatPhoto:(UIImage *)image {
	if (!self.chatId)
		return;
	NSString *path = [self writeJpegOf:image maxSide:640.0f named:@"chat-photo.jpg"];
	if (!path)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPhotoAtPath:path forChat:self.chatId completion:^(BOOL ok){
		[weakSelf showToast:(ok ? @"Photo updated" : @"Could not set photo")];
		if (!ok)
			return;
		UIImage *preview = TGDecodeSquareThumbnail(path, kProfileAvatarSide);
		if (!preview)
			return;
		[weakSelf cancelAvatarDownload];
		weakSelf.avatarImage = preview;
		weakSelf.avatarIsPlaceholder = NO;
		[weakSelf setAvatarViewImage:preview crossfade:YES];
	}];
}

- (void)startSecretChat {
	if (!self.userId)
		return;
	UINavigationController *navigation = self.navigationController;
	NSString *name = TGProfileText(self.name) ?: @"";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] createSecretChatWithUser:self.userId
									 completion:^(NSDictionary *info){
		int64_t chatId = [info isKindOfClass:[NSDictionary class]]
				? TGProfileInt64(info[@"chatId"]) : 0;
		if (!chatId){
			[weakSelf showToast:@"Could not start secret chat"];
			return;
		}
		TGChatViewController *chat = [[TGChatViewController alloc] init];
		chat.chatId = chatId;
		chat.chatTitle = name;
		[navigation pushViewController:chat animated:YES];
	}];
}

- (void)loadDetails {
	if (self.chatId)
		self.muted = [[TGClient shared] isChatMuted:self.chatId];

	[self loadManagement];

	if (!self.userId && self.chatId){
		[self loadGroupDetailRows];
		return;
	}

	if (!self.userId)
		return;

	[self loadUserDetailRows];
}

- (void)loadGroupDetailRows {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] membersOfChat:self.chatId completion:^(NSArray *members){
		weakSelf.members = [members isKindOfClass:[NSArray class]] ? members : @[];
		[weakSelf rebuildSections];
		[weakSelf.tableView reloadData];
	}];
	[[TGClient shared] chatProfile:self.chatId completion:^(NSDictionary *info){
		if (![info isKindOfClass:[NSDictionary class]])
			return;
		NSMutableArray *rows = [NSMutableArray array];
		NSString *about = TGProfileText(info[@"description"]);
		weakSelf.chatDescription = about;
		if (about)
			[rows addObject:@[@"about", about]];
		NSString *members = TGProfileNumberText(info[@"members"]);
		if (members.integerValue > 0)
			[rows addObject:@[@"members", members]];
		NSString *admins = TGProfileNumberText(info[@"admins"]);
		if (admins.integerValue > 0)
			[rows addObject:@[@"admins", admins]];
		NSString *link = TGProfileText(info[@"inviteLink"]);
		if (link){
			weakSelf.primaryInviteLink = link;
			[rows addObject:@[@"invite link", link]];
		}
		weakSelf.details = rows;
		[weakSelf.tableView reloadData];
		[weakSelf rebuildManageRows];
	}];
}

- (void)loadUserDetailRows {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userInfo:self.userId completion:^(NSDictionary *user){
		if (![user isKindOfClass:[NSDictionary class]]) return;
		NSMutableArray *rows = [NSMutableArray array];
		[weakSelf appendPhoneRowTo:rows fromUser:user];
		weakSelf.firstName = TGProfileText(user[@"first_name"]);
		weakSelf.lastName = TGProfileText(user[@"last_name"]);
		weakSelf.isContact = TGProfileBool(user[@"is_contact"])
				|| TGProfileBool(user[@"is_mutual_contact"]);
		[weakSelf applyFallbackNameFromUser];
		[weakSelf appendUsernameRowTo:rows fromUser:user];
		if (TGProfileBool(user[@"is_premium"]))
			[rows addObject:@[@"subscription", @"Telegram Premium"]];
		weakSelf.baseDetailRows = rows;
		[weakSelf rebuildDetailRows];

		[weakSelf loadFullUserProfile];
		[weakSelf loadNoteAndCommonGroups];
		[weakSelf loadContactFlags];

		[weakSelf loadAvatarFromUserRecord:user];
	}];
}

- (void)appendPhoneRowTo:(NSMutableArray *)rows fromUser:(NSDictionary *)user {
	NSString *phone = TGProfileText(user[@"phone_number"]);
	if (phone){
		[rows addObject:@[@"mobile", [@"+" stringByAppendingString:phone]]];
		self.phoneNumber = phone;
	} else {
		[rows addObject:@[@"mobile", @"Hidden"]];
		self.phoneNumber = nil;
	}
}

- (void)applyFallbackNameFromUser {
	if (TGProfileText(self.name))
		return;
	NSMutableArray *parts = [NSMutableArray array];
	if (self.firstName) [parts addObject:self.firstName];
	if (self.lastName) [parts addObject:self.lastName];
	if (!parts.count)
		return;
	self.name = [parts componentsJoinedByString:@" "];
	self.nameLabel.text = self.name;
	[self layoutNameBadge];
	if (!self.avatarImage && !self.avatarIsPlaceholder)
		self.avatarView.image =
				[TGIcons avatarWithInitials:TGProfileInitial(self.name)
									   size:kProfileAvatarSide
								   colourId:self.userId];
}

- (void)appendUsernameRowTo:(NSMutableArray *)rows fromUser:(NSDictionary *)user {
	NSString *username = nil;
	id usernames = user[@"usernames"];
	if ([usernames isKindOfClass:[NSDictionary class]]){
		id active = usernames[@"active_usernames"];
		if ([active isKindOfClass:[NSArray class]] && [active count])
			username = TGProfileText([active objectAtIndex:0]);
	}
	if (!username)
		username = TGProfileText(user[@"username"]);
	if (username)
		[rows addObject:@[@"username", [@"@" stringByAppendingString:username]]];
}

- (void)loadFullUserProfile {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userProfile:self.userId completion:^(NSDictionary *info){
		if (![info isKindOfClass:[NSDictionary class]])
			return;
		weakSelf.profileBio = TGProfileText(info[@"bio"]);
		weakSelf.profileBirthdayText = TGProfileText(info[@"birthday"]);
		weakSelf.profileCommonGroupCount =
				TGProfileNumberText(info[@"commonGroups"]).integerValue;
		weakSelf.fullProfileLoaded = YES;
		[weakSelf rebuildDetailRows];
	}];
}

- (void)loadAvatarFromUserRecord:(NSDictionary *)user {
	id photo = user[@"profile_photo"];
	id small = [photo isKindOfClass:[NSDictionary class]] ? photo[@"small"] : nil;
	id photoId = [small isKindOfClass:[NSDictionary class]] ? small[@"id"] : nil;
	if (self.avatarImage)
		return;
	if ([photo isKindOfClass:[NSDictionary class]])
		[self showPlaceholderAvatarFromData:
				[[TGClient shared] minithumbnailData:photo[@"minithumbnail"]]];
	if ([photoId isKindOfClass:[NSNumber class]])
		[self loadAvatarFile:[photoId integerValue]];
}

- (void)rebuildDetailRows {
	NSMutableArray *more = [(self.baseDetailRows ?: @[]) mutableCopy];
	NSString *bio = self.profileBio;
	if (bio)
		[more insertObject:@[@"about", bio] atIndex:MIN((NSUInteger)2, more.count)];
	NSString *birthday = self.profileBirthdayText ?: self.birthdayDetail;
	if (birthday)
		[more addObject:@[@"birthday", birthday]];
	if (self.emojiStatusDetail.length)
		[more addObject:@[@"status", self.emojiStatusDetail]];
	if (self.contactRelation.length)
		[more addObject:@[@"contact", self.contactRelation]];
	if (self.noteLoaded && (self.isContact || self.profileNote.length))
		[more addObject:@[@"note", self.profileNote.length ? self.profileNote : @"Add note"]];
	NSInteger common = self.commonGroupsLoaded
			? (NSInteger)self.commonGroups.count
			: (self.fullProfileLoaded ? self.profileCommonGroupCount : 0);
	if (common > 0)
		[more addObject:@[@"groups in common",
						  [NSString stringWithFormat:@"%ld", (long)common]]];
	self.details = more;
	[self actionItems];
	[self rebuildSections];
	[self.tableView reloadData];
}

- (void)loadNoteAndCommonGroups {
	if (!self.userId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] noteForUser:self.userId completion:^(NSString *note){
		weakSelf.noteLoaded = YES;
		weakSelf.profileNote = TGProfileText(note);
		[weakSelf rebuildDetailRows];
	}];
	[[TGClient shared] groupsInCommonWithUser:self.userId completion:^(NSArray *chats){
		weakSelf.commonGroups = [chats isKindOfClass:[NSArray class]] ? chats : @[];
		weakSelf.commonGroupsLoaded = YES;
		[weakSelf rebuildDetailRows];
	}];
}

- (void)editNote {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil
			message:@"Note about this contact"
		   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Done", nil];
	alert.tag = 81;
	if ([alert respondsToSelector:@selector(setAlertViewStyle:)]){
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
		[alert textFieldAtIndex:0].text = self.profileNote ?: @"";
	}
	[alert show];
}

- (void)openCommonGroups {
	if (!self.userId || !self.navigationController)
		return;
	TGProfileCommonGroupsController *list =
			[[TGProfileCommonGroupsController alloc] initWithStyle:UITableViewStylePlain];
	list.userId = self.userId;
	list.chats = self.commonGroups;
	[self.navigationController pushViewController:list animated:YES];
}

- (void)loadMedia {
	__weak typeof(self) weakSelf = self;
	if (self.userId){
		[[TGClient shared] giftsForUser:self.userId completion:^(NSArray *gifts){
			weakSelf.gifts = [gifts isKindOfClass:[NSArray class]] ? gifts : @[];
			[weakSelf.tableView reloadData];
		}];
		[[TGClient shared] isUserBlocked:self.userId completion:^(BOOL blocked){
			weakSelf.blocked = blocked;
		}];
	}

	if (!self.chatId){
		self.photosLoaded = YES;
		self.filesLoaded = YES;
		[self.tableView reloadData];
		return;
	}

	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterPhotoAndVideo"
						completion:^(NSArray *messages){
		weakSelf.photoCount = [messages isKindOfClass:[NSArray class]]
				? (NSInteger)messages.count : 0;
		weakSelf.photosLoaded = YES;
		[weakSelf.tableView reloadData];
	}];
	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterDocument"
						completion:^(NSArray *messages){
		weakSelf.fileCount = [messages isKindOfClass:[NSArray class]]
				? (NSInteger)messages.count : 0;
		weakSelf.filesLoaded = YES;
		[weakSelf.tableView reloadData];
	}];
}

- (void)showToast:(NSString *)text {
	if (!text.length || !self.isViewLoaded)
		return;
	UIView *host = self.navigationController.view ?: self.view;
	UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 34)];
	toast.center = CGPointMake(host.bounds.size.width / 2,
							   host.bounds.size.height - 70);
	toast.autoresizingMask = UIViewAutoresizingFlexibleTopMargin
			| UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	toast.text = text;
	toast.textAlignment = NSTextAlignmentCenter;
	toast.font = [UIFont systemFontOfSize:14];
	toast.textColor = [UIColor whiteColor];
	toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75f];
	toast.layer.cornerRadius = 6;
	toast.clipsToBounds = YES;
	[host addSubview:toast];
	[UIView animateWithDuration:0.3 delay:1.0 options:0
					 animations:^{ toast.alpha = 0; }
					 completion:^(BOOL done){ [toast removeFromSuperview]; }];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.backgroundColor = TGProfileListBackground();
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	if (self.chatId){
		BOOL muted = [[TGClient shared] isChatMuted:self.chatId];
		if (muted != self.muted){
			self.muted = muted;
			[self updateMuteButton];
		}
	}
	if (self.hasAppearedOnce && self.chatId && !self.userId)
		[self loadManagement];
	self.hasAppearedOnce = YES;
	[self refreshStatus];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[TGPopupMenu dismiss];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.sectionKinds.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSString *kind = [self kindForSection:section];
	if ([kind isEqualToString:@"story"]) return 1;
	if ([kind isEqualToString:@"details"]) return self.details.count + self.gifts.count;
	if ([kind isEqualToString:@"personal"]) return self.personalChatId ? 1 : 0;
	if ([kind isEqualToString:@"manage"]) return self.manageRows.count;
	if ([kind isEqualToString:@"members"]) return self.members.count;
	if ([kind isEqualToString:@"actions"]) return [self actionRowCount];
	if ([kind isEqualToString:@"delete"]) return 1;
	if ([kind isEqualToString:@"media"]) return self.chatId ? 2 : 1;
	return 1;
}

- (BOOL)mediaSectionHasNotificationsRow {
	return self.chatId != 0;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *kind = [self kindForSection:indexPath.section];
	if (![kind isEqualToString:@"actions"] && ![kind isEqualToString:@"delete"]
			&& ![kind isEqualToString:@"story"])
		return;
	cell.backgroundColor = [UIColor clearColor];
	cell.backgroundView = [[UIView alloc] initWithFrame:cell.bounds];
	cell.backgroundView.backgroundColor = [UIColor clearColor];
	cell.selectedBackgroundView = nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	NSString *kind = [self kindForSection:section];
	if (section != 0 && [self tableView:tableView numberOfRowsInSection:section] == 0)
		return 0;
	if ([self isGroupProfile])
		return 8;
	if (section == 0)
		return ([kind isEqualToString:@"details"] && !self.details.count) ? 2 : 12;
	if ([kind isEqualToString:@"actions"])
		return 10;
	if ([kind isEqualToString:@"media"])
		return 12;
	return 12;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if ([self tableView:tableView numberOfRowsInSection:section] == 0)
		return 0;
	if ([self isGroupProfile])
		return 1;
	if ([[self kindForSection:section] isEqualToString:@"details"])
		return 0;
	return 1 + ([UIScreen mainScreen].scale > 1.5f ? 0.5f : 1.0f);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *kind = [self kindForSection:indexPath.section];
	if ([kind isEqualToString:@"members"]) return kMemberRowHeight;
	if ([kind isEqualToString:@"story"])
		return kButtonsRowHeight;
	if ([kind isEqualToString:@"actions"]){
		BOOL lastRow = indexPath.row + 1 >= [self actionRowCount];
		return lastRow ? kButtonsRowHeight : kButtonsRowHeight + kButtonsRowGutter;
	}
	if ([kind isEqualToString:@"delete"]) return kActionButtonHeight;
	if ([kind isEqualToString:@"details"] &&
		indexPath.row < (NSInteger)self.details.count){
		NSNumber *measured = self.measuredRowHeights[self.details[indexPath.row][0]];
		if (measured)
			return [measured floatValue];
	}
	return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *kind = [self kindForSection:indexPath.section];

	if ([kind isEqualToString:@"story"])
		return [self storyCell:tableView];

	if ([kind isEqualToString:@"actions"])
		return [self actionsCell:tableView row:indexPath.row];

	if ([kind isEqualToString:@"delete"])
		return [self deleteContactCell:tableView];

	if ([kind isEqualToString:@"media"]){
		if ([self mediaSectionHasNotificationsRow] && indexPath.row == 0)
			return [self notificationsCell:tableView];
		return [self sharedMediaCell:tableView];
	}

	if ([kind isEqualToString:@"manage"])
		return [self manageCell:tableView row:indexPath.row];

	if ([kind isEqualToString:@"personal"])
		return [self personalChatCell:tableView];

	if ([kind isEqualToString:@"details"])
		return [self detailsRowCell:tableView row:indexPath.row];

	return [self plainRowCell:tableView kind:kind row:indexPath.row];
}

- (UITableViewCell *)storyCell:(UITableView *)tableView {
	TGProfileButtonsCell *cell = (TGProfileButtonsCell *)
			[tableView dequeueReusableCellWithIdentifier:@"storybutton"];
	if (![cell isKindOfClass:[TGProfileButtonsCell class]])
		cell = [[TGProfileButtonsCell alloc] initWithStyle:UITableViewCellStyleDefault
										   reuseIdentifier:@"storybutton"];
	cell.rightButton.hidden = YES;
	cell.leftButton.hidden = NO;
	[cell.leftButton setTitle:@"Post a Story" forState:UIControlStateNormal];
	[cell.leftButton removeTarget:self action:NULL
				 forControlEvents:UIControlEventTouchUpInside];
	[cell.leftButton addTarget:self action:@selector(postStoryTapped)
			  forControlEvents:UIControlEventTouchUpInside];
	[cell setNeedsLayout];
	return cell;
}

- (UITableViewCell *)deleteContactCell:(UITableView *)tableView {
	TGProfileRedButtonCell *cell = (TGProfileRedButtonCell *)
			[tableView dequeueReusableCellWithIdentifier:@"delete"];
	if (![cell isKindOfClass:[TGProfileRedButtonCell class]])
		cell = [[TGProfileRedButtonCell alloc]
				initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"delete"];
	[cell.button setTitle:@"Delete Contact" forState:UIControlStateNormal];
	[cell.button removeTarget:self action:NULL
			 forControlEvents:UIControlEventTouchUpInside];
	[cell.button addTarget:self action:@selector(deleteContactTapped)
		  forControlEvents:UIControlEventTouchUpInside];
	return cell;
}

- (UITableViewCell *)personalChatCell:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"manage"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"manage"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.textLabel.text = self.personalChatTitle ?: @"Channel";
	cell.detailTextLabel.text = nil;
	cell.imageView.image = nil;
	return cell;
}

- (void)adoptGroupedInsetFromCell:(UITableViewCell *)cell inTable:(UITableView *)tableView {
	CGFloat content = cell.contentView.bounds.size.width;
	CGFloat width = tableView.bounds.size.width;
	if (content < 1 || width < 1)
		return;
	CGFloat inset = floorf((width - content) / 2);
	if (inset < 0 || fabsf(inset - self.groupedInset) < 0.5f)
		return;
	self.groupedInset = inset;
	[self layoutHeaderForInset:inset];
}

- (void)layoutHeaderForInset:(CGFloat)inset {
	if (!self.avatarView)
		return;
	CGRect avatar = self.avatarView.frame;
	avatar.origin.x = inset;
	self.avatarView.frame = avatar;

	CGFloat width = self.tableView.bounds.size.width;
	CGFloat labelLeft = kProfileAvatarSide + inset * 2 + 4;
	for (UILabel *label in @[self.nameLabel ?: (id)[NSNull null],
							 self.statusLabel ?: (id)[NSNull null]]){
		if (![label isKindOfClass:[UILabel class]])
			continue;
		CGRect frame = label.frame;
		frame.origin.x = labelLeft;
		frame.size.width = MAX(40, width - labelLeft - inset);
		label.frame = frame;
	}
	[self layoutNameBadge];
}

- (void)recordRowHeight:(CGFloat)height forLabel:(NSString *)label inTable:(UITableView *)tableView {
	if (!label)
		return;
	if (!self.measuredRowHeights)
		self.measuredRowHeights = [NSMutableDictionary dictionary];
	NSNumber *known = self.measuredRowHeights[label];
	if (known && fabsf([known floatValue] - height) < 0.5f)
		return;
	self.measuredRowHeights[label] = @(height);
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		[weakSelf.tableView reloadData];
	});
}

- (UITableViewCell *)detailsRowCell:(UITableView *)tableView row:(NSInteger)row {
	NSString *label = nil;
	NSString *value = nil;
	if (row < (NSInteger)self.details.count){
		NSArray *pair = self.details[row];
		label = pair[0];
		value = pair[1];
	} else {
		NSUInteger giftIndex = row - self.details.count;
		id gift = giftIndex < self.gifts.count ? self.gifts[giftIndex] : nil;
		label = @"gift";
		NSString *giftTitle = [gift isKindOfClass:[NSDictionary class]]
				? TGProfileText(gift[@"title"]) : nil;
		NSString *stars = [gift isKindOfClass:[NSDictionary class]]
				? TGProfileNumberText(gift[@"starCount"]) : nil;
		if (giftTitle && stars.integerValue > 0)
			value = [NSString stringWithFormat:@"%@ - %@ stars", giftTitle, stars];
		else
			value = giftTitle ?: @"Gift";
	}
	return [self detailCell:tableView label:label value:value];
}

- (UITableViewCell *)plainRowCell:(UITableView *)tableView
							 kind:(NSString *)kind
							  row:(NSInteger)row {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.imageView.image = nil;
	[[TGTheme shared] styleCell:cell];
	CGFloat retinaPixel = TGProfileRetinaPixel();
	BOOL isMember = [kind isEqualToString:@"members"];
	if (isMember){
		cell.textLabel.font = [UIFont boldSystemFontOfSize:15 + retinaPixel];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:13 + retinaPixel];
	} else {
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	}
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.textColor = [TGTheme shared].isDark
			? [[TGTheme shared] secondaryTextColour] : TGProfileColour(0x888888);

	if (isMember){
		id member = row < (NSInteger)self.members.count
				? self.members[row] : nil;
		if (![member isKindOfClass:[NSDictionary class]])
			member = @{};
		int64_t userId = TGProfileInt64(member[@"id"]);
		NSString *name = TGProfileText(member[@"name"])
				?: TGProfileText([[TGClient shared] nameForUserId:userId]);
		cell.selectionStyle = userId ? UITableViewCellSelectionStyleBlue
									 : UITableViewCellSelectionStyleNone;
		cell.textLabel.text = name ?: @"";
		cell.detailTextLabel.text = TGProfileText(member[@"status"]);
		cell.imageView.image = [TGIcons avatarWithInitials:TGProfileInitial(name)
													  size:kMemberAvatarSide
												  colourId:userId];
	}
	return cell;
}

- (UITableViewCell *)sharedMediaCell:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sharedmedia"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"sharedmedia"];
		UILabel *count = [[UILabel alloc] initWithFrame:
				CGRectMake(cell.contentView.bounds.size.width - 200 - 11 - 14, 11, 200, 21)];
		count.tag = 21;
		count.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		count.textAlignment = NSTextAlignmentRight;
		count.contentMode = UIViewContentModeRight;
		count.font = [UIFont systemFontOfSize:17];
		count.backgroundColor = [UIColor clearColor];
		count.textColor = TGProfileColour(0x415d7f);
		count.highlightedTextColor = [UIColor whiteColor];
		[cell.contentView addSubview:count];

		UILabel *title = [[UILabel alloc] initWithFrame:
				CGRectMake(11, 12, cell.contentView.bounds.size.width - 30, 21)];
		title.tag = 22;
		title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		title.font = [UIFont boldSystemFontOfSize:17];
		title.backgroundColor = [UIColor clearColor];
		title.highlightedTextColor = [UIColor whiteColor];
		title.text = @"Shared Media";
		[cell.contentView addSubview:title];
	}
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.text = nil;
	cell.imageView.image = nil;
	((UILabel *)[cell.contentView viewWithTag:22]).textColor =
			[[TGTheme shared] primaryTextColour];

	UILabel *count = (UILabel *)[cell.contentView viewWithTag:21];
	BOOL loaded = self.photosLoaded && self.filesLoaded;
	if (loaded){
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.accessoryView = nil;
		count.text = [NSString stringWithFormat:@"%lu",
				(unsigned long)(self.photoCount + self.fileCount)];
	} else {
		count.text = @"";
		cell.accessoryType = UITableViewCellAccessoryNone;
		UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
				initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
		[spinner startAnimating];
		cell.accessoryView = spinner;
	}
	return cell;
}

- (UITableViewCell *)notificationsCell:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"notifications"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"notifications"];
		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.tag = 23;
		toggle.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		toggle.frame = CGRectMake(cell.contentView.bounds.size.width
						- toggle.frame.size.width - 9, 8,
				toggle.frame.size.width, toggle.frame.size.height);
		[toggle addTarget:self action:@selector(notificationsToggled:)
		 forControlEvents:UIControlEventValueChanged];
		[cell.contentView addSubview:toggle];

		UILabel *title = [[UILabel alloc] initWithFrame:
				CGRectMake(11, 12, cell.contentView.bounds.size.width - 28
						- toggle.frame.size.width, 20)];
		title.tag = 24;
		title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		title.font = [UIFont boldSystemFontOfSize:17];
		title.backgroundColor = [UIColor clearColor];
		title.highlightedTextColor = [UIColor whiteColor];
		title.text = @"Notifications";
		[cell.contentView addSubview:title];
	}
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.textLabel.text = nil;
	cell.imageView.image = nil;
	((UILabel *)[cell.contentView viewWithTag:24]).textColor =
			[[TGTheme shared] primaryTextColour];
	UISwitch *toggle = (UISwitch *)[cell.contentView viewWithTag:23];
	self.notificationsSwitch = toggle;
	[toggle setOn:!self.muted animated:NO];
	return cell;
}

- (void)openSharedMedia {
	if (!self.chatId || !self.navigationController)
		return;
	TGMediaViewController *media =
			[[TGMediaViewController alloc] initWithChatId:self.chatId];
	media.chatTitle = TGProfileText(self.name) ?: @"";
	[self.navigationController pushViewController:media animated:YES];
}

- (void)deleteContactTapped {
	UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:@"Delete Contact"
			message:@"This person will be removed from your contacts."
		   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Delete", nil];
	confirm.tag = 82;
	[confirm show];
}

- (void)deleteContactConfirmed {
	if (!self.userId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] removeContacts:@[@(self.userId)] completion:^(BOOL ok){
		if (ok){
			weakSelf.isContact = NO;
			[weakSelf rebuildDetailRows];
		}
		[weakSelf showToast:(ok ? @"Contact deleted" : @"Could not delete the contact")];
	}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString *kind = [self kindForSection:indexPath.section];

	if ([kind isEqualToString:@"manage"]){
		[self openManageRow:indexPath.row];
		return;
	}

	if ([kind isEqualToString:@"personal"]){
		[self openChatId:self.personalChatId title:self.personalChatTitle];
		return;
	}

	if ([kind isEqualToString:@"members"]){
		[self openMemberAtRow:indexPath.row];
		return;
	}

	if ([kind isEqualToString:@"media"]){
		if (![self mediaSectionHasNotificationsRow] || indexPath.row == 1)
			[self openSharedMedia];
		return;
	}

	if (![kind isEqualToString:@"details"] || indexPath.row >= (NSInteger)self.details.count)
		return;
	NSString *label = self.details[indexPath.row][0];
	if ([label isEqualToString:@"note"]){
		[self editNote];
		return;
	}
	if ([label isEqualToString:@"groups in common"]){
		[self openCommonGroups];
		return;
	}
	if ([label isEqualToString:@"invite link"]){
		[self showInviteLinkActions];
		return;
	}
	if ([label isEqualToString:@"mobile"])
		[self dialPhoneNumber];
}

- (void)dialPhoneNumber {
	NSString *phone = self.phoneNumber;
	if (!phone.length)
		return;
	NSMutableString *digits = [NSMutableString string];
	for (NSUInteger i = 0; i < phone.length; i++){
		unichar c = [phone characterAtIndex:i];
		if ((c >= '0' && c <= '9') || (c == '+' && digits.length == 0))
			[digits appendFormat:@"%C", c];
	}
	if (!digits.length)
		return;
	UIApplication *application = [UIApplication sharedApplication];
	NSString *scheme = @"tel:";
	if (![application canOpenURL:[NSURL URLWithString:@"tel://"]])
		scheme = @"facetime:";
	NSURL *url = [NSURL URLWithString:[scheme stringByAppendingString:digits]];
	if (url)
		[application openURL:url];
}

- (BOOL)tableView:(UITableView *)tableView
		shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (![[self kindForSection:indexPath.section] isEqualToString:@"details"])
		return NO;
	if (indexPath.row >= (NSInteger)self.details.count)
		return NO;
	NSArray *pair = self.details[indexPath.row];
	return pair.count > 1 && [pair[1] length] > 0;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action
		forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
	return action == @selector(copy:);
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action
		forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
	if (action != @selector(copy:))
		return;
	if (indexPath.row >= (NSInteger)self.details.count)
		return;
	NSArray *pair = self.details[indexPath.row];
	if (pair.count > 1)
		[UIPasteboard generalPasteboard].string = pair[1];
}

- (void)openMemberAtRow:(NSInteger)row {
	if (row >= (NSInteger)self.members.count)
		return;
	id member = self.members[row];
	if (![member isKindOfClass:[NSDictionary class]])
		return;
	int64_t userId = TGProfileInt64(member[@"id"]);
	if (!userId || userId == self.userId)
		return;
	NSString *name = TGProfileText(member[@"name"])
			?: TGProfileText([[TGClient shared] nameForUserId:userId]) ?: @"";
	UINavigationController *navigation = self.navigationController;
	if (!navigation)
		return;
	[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
		TGProfileViewController *profile = [[TGProfileViewController alloc]
				initWithChatId:chatId userId:userId title:name];
		[navigation pushViewController:profile animated:YES];
	}];
}

- (UITableViewCell *)detailCell:(UITableView *)tableView
						  label:(NSString *)label
						  value:(NSString *)value {
	TGTheme *theme = [TGTheme shared];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"detail"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"detail"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		UILabel *labelView = [[UILabel alloc] initWithFrame:CGRectMake(4, 13, 62, 16)];
		labelView.tag = 11;
		labelView.textAlignment = NSTextAlignmentRight;
		labelView.font = [UIFont boldSystemFontOfSize:13];
		labelView.backgroundColor = [UIColor clearColor];
		[cell.contentView addSubview:labelView];

		UILabel *valueView = [[UILabel alloc] initWithFrame:
				CGRectMake(78, 11, cell.contentView.bounds.size.width - 80, 20)];
		valueView.tag = 12;
		valueView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		valueView.font = [UIFont boldSystemFontOfSize:15];
		valueView.numberOfLines = 0;
		valueView.lineBreakMode = NSLineBreakByWordWrapping;
		valueView.backgroundColor = [UIColor clearColor];
		[cell.contentView addSubview:valueView];
	}
	[theme styleCell:cell];

	BOOL opens = [label isEqualToString:@"note"]
			|| [label isEqualToString:@"groups in common"]
			|| [label isEqualToString:@"invite link"];
	BOOL isPhone = [label isEqualToString:@"mobile"];
	BOOL hiddenPhone = isPhone && [value isEqualToString:@"Hidden"];
	cell.selectionStyle = (opens || (isPhone && !hiddenPhone))
			? UITableViewCellSelectionStyleBlue : UITableViewCellSelectionStyleNone;
	cell.accessoryType = opens ? UITableViewCellAccessoryDisclosureIndicator
							   : UITableViewCellAccessoryNone;
	cell.userInteractionEnabled = !hiddenPhone;

	UILabel *labelView = (UILabel *)[cell.contentView viewWithTag:11];
	UILabel *valueView = (UILabel *)[cell.contentView viewWithTag:12];
	labelView.text = label;
	labelView.textColor = theme.isDark ? [theme secondaryTextColour]
									   : TGProfileColour(0x5d708f);
	valueView.text = value;
	CGFloat valueWidth = cell.contentView.bounds.size.width - 78 - 12;
	if (valueWidth < 40)
		valueWidth = 40;
	CGSize valueSize = [(value ?: @"") sizeWithFont:valueView.font
								  constrainedToSize:CGSizeMake(valueWidth, 400)
									  lineBreakMode:NSLineBreakByWordWrapping];
	CGFloat valueHeight = MAX(20, valueSize.height);
	valueView.frame = CGRectMake(78, 11, valueWidth, valueHeight);
	[self recordRowHeight:MAX(44, valueHeight + 22) forLabel:label inTable:tableView];
	[self adoptGroupedInsetFromCell:cell inTable:tableView];
	if (hiddenPhone)
		valueView.textColor = TGProfileColour(0xaaaaaa);
	else if (isPhone)
		valueView.textColor = TGProfileColour(0x347fd4);
	else
		valueView.textColor = theme.isDark ? [theme primaryTextColour]
										   : [UIColor blackColor];
	return cell;
}

- (UITableViewCell *)manageCell:(UITableView *)tableView row:(NSInteger)row {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"manage"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"manage"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.textColor = [TGTheme shared].isDark
			? [[TGTheme shared] secondaryTextColour] : TGProfileColour(0x888888);
	NSArray *item = row < (NSInteger)self.manageRows.count ? self.manageRows[row] : nil;
	cell.textLabel.text = item.count > 0 ? item[0] : @"";
	cell.detailTextLabel.text = item.count > 2 ? item[2] : nil;
	cell.imageView.image = nil;
	return cell;
}

@end

@implementation TGProfilePermissionsController

+ (NSString *)titleForKey:(NSString *)key {
	static NSDictionary *titles = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		titles = @{@"sendMessages"    : @"Send Messages",
				   @"sendAudios"      : @"Send Music",
				   @"sendDocuments"   : @"Send Files",
				   @"sendPhotos"      : @"Send Photos",
				   @"sendVideos"      : @"Send Videos",
				   @"sendVideoNotes"  : @"Send Video Notes",
				   @"sendVoiceNotes"  : @"Send Voice Notes",
				   @"sendPolls"       : @"Send Polls",
				   @"sendOther"       : @"Send Stickers & GIFs",
				   @"addLinkPreviews" : @"Embed Links",
				   @"reactToMessages" : @"Add Reactions",
				   @"changeInfo"      : @"Change Chat Info",
				   @"inviteUsers"     : @"Add Users",
				   @"pinMessages"     : @"Pin Messages",
				   @"createTopics"    : @"Create Topics"};
	});
	return titles[key] ?: key;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Permissions";
	self.permissions = [NSMutableDictionary dictionary];
	self.tableView.backgroundColor = TGProfileListBackground();
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	UIButton *done = [TGIcons headerButtonWithTitle:@"Done" bold:YES
											 target:self action:@selector(saveTapped)];
	if (done)
		self.navigationItem.rightBarButtonItem =
				[[UIBarButtonItem alloc] initWithCustomView:done];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] permissionsForChat:self.chatId
							   completion:^(NSDictionary *permissions){
		if ([permissions isKindOfClass:[NSDictionary class]])
			weakSelf.permissions = [permissions mutableCopy];
		[weakSelf.tableView reloadData];
	}];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)saveTapped {
	NSMutableDictionary *full = [NSMutableDictionary dictionary];
	for (NSString *key in [TGClient permissionKeys])
		full[key] = @([self.permissions[key] boolValue]);
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPermissions:full forChat:self.chatId completion:^(BOOL ok){
		if (ok){
			[weakSelf.navigationController popViewControllerAnimated:YES];
			return;
		}
		[[[UIAlertView alloc] initWithTitle:nil
				message:@"These permissions could not be changed."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [[TGClient permissionKeys] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return @"What members may do";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"permission"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"permission"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];

	NSArray *keys = [TGClient permissionKeys];
	NSString *key = indexPath.row < (NSInteger)keys.count ? keys[indexPath.row] : @"";
	cell.textLabel.text = [TGProfilePermissionsController titleForKey:key];

	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = [self.permissions[key] boolValue];
	toggle.tag = indexPath.row;
	[toggle addTarget:self action:@selector(permissionToggled:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	return cell;
}

- (void)permissionToggled:(UISwitch *)toggle {
	NSArray *keys = [TGClient permissionKeys];
	if (toggle.tag >= (NSInteger)keys.count)
		return;
	self.permissions[keys[toggle.tag]] = @(toggle.on);
}

@end

@implementation TGProfileChartView

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])){
		self.backgroundColor = [UIColor clearColor];
		self.contentMode = UIViewContentModeRedraw;
		self.points = @[];
		for (NSInteger i = 0; i < 4; i++){
			UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
			label.tag = 200 + i;
			label.backgroundColor = [UIColor clearColor];
			label.font = [UIFont systemFontOfSize:10];
			label.textColor = TGProfileColour(0x888888);
			[self addSubview:label];
		}
	}
	return self;
}

- (UILabel *)labelAt:(NSInteger)index {
	return (UILabel *)[self viewWithTag:200 + index];
}

- (void)setPoints:(NSArray *)points {
	_points = points ?: @[];
	[self layoutLabels];
	[self setNeedsDisplay];
}

- (void)setLeftDate:(NSString *)leftDate {
	_leftDate = leftDate;
	[self layoutLabels];
}

- (void)setRightDate:(NSString *)rightDate {
	_rightDate = rightDate;
	[self layoutLabels];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	[self layoutLabels];
}

- (void)layoutLabels {
	CGFloat width = self.bounds.size.width;
	CGFloat height = self.bounds.size.height;
	double maximum = 0, minimum = 0;
	[self scanMaximum:&maximum minimum:&minimum];

	UILabel *top = [self labelAt:0];
	top.frame = CGRectMake(0, 6, 26, 12);
	top.textAlignment = NSTextAlignmentRight;
	top.text = self.points.count ? [self shortNumber:maximum] : @"";

	UILabel *bottom = [self labelAt:1];
	bottom.frame = CGRectMake(0, height - 34, 26, 12);
	bottom.textAlignment = NSTextAlignmentRight;
	bottom.text = self.points.count ? [self shortNumber:minimum] : @"";

	UILabel *left = [self labelAt:2];
	left.frame = CGRectMake(30, height - 18, 100, 12);
	left.textAlignment = NSTextAlignmentLeft;
	left.text = self.leftDate ?: @"";

	UILabel *right = [self labelAt:3];
	right.frame = CGRectMake(width - 110, height - 18, 100, 12);
	right.textAlignment = NSTextAlignmentRight;
	right.text = self.rightDate ?: @"";
}

- (NSString *)shortNumber:(double)value {
	if (fabs(value) >= 1000000)
		return [NSString stringWithFormat:@"%.1fM", value / 1000000.0];
	if (fabs(value) >= 1000)
		return [NSString stringWithFormat:@"%.1fK", value / 1000.0];
	return [NSString stringWithFormat:@"%lld", (long long)value];
}

- (void)scanMaximum:(double *)maximum minimum:(double *)minimum {
	double high = 0, low = 0;
	BOOL first = YES;
	for (id point in self.points){
		if (![point isKindOfClass:[NSNumber class]])
			continue;
		double value = [point doubleValue];
		if (first){
			high = low = value;
			first = NO;
			continue;
		}
		if (value > high) high = value;
		if (value < low) low = value;
	}
	if (maximum) *maximum = high;
	if (minimum) *minimum = low;
}

- (void)drawRect:(CGRect)rect {
	CGContextRef context = UIGraphicsGetCurrentContext();
	if (!context)
		return;
	CGFloat width = self.bounds.size.width;
	CGFloat height = self.bounds.size.height;
	CGFloat leftInset = 30, rightInset = 10, topInset = 12, bottomInset = 26;
	CGFloat plotHeight = height - topInset - bottomInset;
	CGFloat pixel = [UIScreen mainScreen].scale > 1.5f ? 0.5f : 1.0f;

	CGContextSetLineWidth(context, pixel);
	for (NSInteger i = 0; i <= 4; i++){
		CGFloat y = topInset + plotHeight * i / 4.0f;
		UIColor *colour = (i == 0 || i == 4)
				? TGProfileColour(0xd5dee5) : TGProfileColour(0xe5e5e5);
		CGContextSetStrokeColorWithColor(context, colour.CGColor);
		CGContextBeginPath(context);
		CGContextMoveToPoint(context, leftInset, y);
		CGContextAddLineToPoint(context, width - rightInset, y);
		CGContextStrokePath(context);
	}

	NSUInteger count = self.points.count;
	if (count < 2)
		return;

	double maximum = 0, minimum = 0;
	[self scanMaximum:&maximum minimum:&minimum];
	double span = maximum - minimum;
	if (span <= 0)
		span = 1;

	CGFloat plotWidth = width - leftInset - rightInset;
	CGContextSetLineWidth(context, 1.5f);
	CGContextSetLineJoin(context, kCGLineJoinRound);
	CGContextSetStrokeColorWithColor(context, TGProfileColour(0x337acc).CGColor);
	CGContextBeginPath(context);
	for (NSUInteger i = 0; i < count; i++){
		id point = self.points[i];
		double value = [point isKindOfClass:[NSNumber class]] ? [point doubleValue] : 0;
		CGFloat x = leftInset + plotWidth * i / (CGFloat)(count - 1);
		CGFloat y = topInset + plotHeight * (1.0f - (value - minimum) / span);
		if (i == 0)
			CGContextMoveToPoint(context, x, y);
		else
			CGContextAddLineToPoint(context, x, y);
	}
	CGContextStrokePath(context);
}

@end

@implementation TGProfileStatisticsController {
	UIView *_modeBar;
	NSMutableArray *_groupButtons;
	NSMutableArray *_groupSeparators;
	UILabel *_emptyLabel;
}

static const CGFloat kStatsModeBarHeight = 44.0f;
static const CGFloat kStatsGroupHeight = 30.0f;
static const CGFloat kStatsGroupInset = 10.0f;
static const CGFloat kStatsSeparatorWidth = 2.0f;
static const CGFloat kStatsChartHeight = 128.0f;
static const CGFloat kStatsRowHeight = 51.0f;
static const CGFloat kStatsPosterRowHeight = 49.0f;

static UIImage *TGStatsStretch(NSString *name, int leftCap) {
	UIImage *raw = [UIImage imageNamed:name];
	if (!raw)
		return nil;
	return [raw stretchableImageWithLeftCapWidth:leftCap topCapHeight:0];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Statistics";
	self.values = @[];
	self.topSenders = @[];
	self.topAdmins = @[];
	self.topInviters = @[];
	self.graphs = @[];
	self.boosters = @[];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];

	CGRect bounds = self.view.bounds;
	[self buildStatsModeBar:bounds];
	[self buildStatsTable:bounds];
	[self buildStatsEmptyLabel:bounds];
	[self reload];
}

- (void)buildStatsModeBar:(CGRect)bounds {
	_modeBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, bounds.size.width, kStatsModeBarHeight)];
	_modeBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	UIImage *plate = TGStatsStretch(@"Footer.png", 1);
	if (plate && ![[TGTheme shared] isFlat])
		_modeBar.backgroundColor = [UIColor colorWithPatternImage:plate];
	else
		_modeBar.backgroundColor = [[TGTheme shared] inputBarColour];
	[self.view addSubview:_modeBar];

	UIView *hairline = [[UIView alloc] initWithFrame:
			CGRectMake(0, kStatsModeBarHeight - 1, bounds.size.width, 1)];
	hairline.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	hairline.backgroundColor = [[TGTheme shared] separatorColour];
	[_modeBar addSubview:hairline];

	[self buildModeButtons];
}

- (void)buildStatsTable:(CGRect)bounds {
	self.tableView = [[UITableView alloc] initWithFrame:
			CGRectMake(0, kStatsModeBarHeight, bounds.size.width,
					   bounds.size.height - kStatsModeBarHeight)
													  style:UITableViewStylePlain];
	self.tableView.autoresizingMask =
			UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.backgroundColor = TGProfileListBackground();
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[self.view addSubview:self.tableView];

	self.chartView = [[TGProfileChartView alloc] initWithFrame:
			CGRectMake(0, 0, bounds.size.width, kStatsChartHeight)];
	self.chartView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
}

- (void)buildStatsEmptyLabel:(CGRect)bounds {
	_emptyLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 60, bounds.size.width, 22)];
	_emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_emptyLabel.backgroundColor = [UIColor clearColor];
	_emptyLabel.textAlignment = NSTextAlignmentCenter;
	_emptyLabel.font = [UIFont systemFontOfSize:15];
	_emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
	_emptyLabel.text = @"Loading...";
	UIView *background = [[UIView alloc] initWithFrame:self.tableView.bounds];
	background.autoresizingMask =
			UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	background.backgroundColor = [UIColor clearColor];
	[background addSubview:_emptyLabel];
	self.tableView.backgroundView = background;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - mode bar

- (NSArray *)modeTitles {
	return @[@"Growth", @"Members", @"Boosts"];
}

- (void)buildModeButtons {
	_groupButtons = [NSMutableArray array];
	_groupSeparators = [NSMutableArray array];

	NSArray *titles = [self modeTitles];
	CGFloat width = self.view.bounds.size.width - kStatsGroupInset * 2;
	CGFloat originY = (CGFloat)(int)((kStatsModeBarHeight - kStatsGroupHeight) / 2);

	UIView *group = [[UIView alloc] initWithFrame:
			CGRectMake(kStatsGroupInset, originY, width, kStatsGroupHeight)];
	group.autoresizingMask = UIViewAutoresizingFlexibleWidth;

	NSInteger count = (NSInteger)titles.count;
	CGFloat usable = width - kStatsSeparatorWidth * (count - 1);
	CGFloat buttonWidth = (CGFloat)(int)(usable / count);
	UIColor *shadowColour = [TGProfileColour(0x0e284d) colorWithAlphaComponent:0.4f];

	CGFloat currentX = 0;
	for (NSInteger i = 0; i < count; i++){
		CGFloat thisWidth = (i == count - 1) ? (width - currentX) : buttonWidth;

		UIButton *button = [self makeModeButtonWithTitle:titles[(NSUInteger)i]
												   index:i
												   frame:CGRectMake(currentX, 0,
																	thisWidth,
																	kStatsGroupHeight)
											 shadowColour:shadowColour];
		[group addSubview:button];
		[_groupButtons addObject:button];

		currentX += thisWidth;

		if (i + 1 < count){
			UIView *separator = [self makeModeSeparatorAtX:currentX];
			[group addSubview:separator];
			[_groupSeparators addObject:separator];
			currentX += kStatsSeparatorWidth;
		}
	}

	[_modeBar addSubview:group];
	[self updateModeButtons];
}

- (UIButton *)makeModeButtonWithTitle:(NSString *)title
								index:(NSInteger)index
								frame:(CGRect)frame
						 shadowColour:(UIColor *)shadowColour {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.exclusiveTouch = YES;
	button.frame = frame;
	button.tag = index;
	[button setTitle:title forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
	[button setTitleShadowColor:shadowColour forState:UIControlStateNormal];
	[button setTitleShadowColor:shadowColour forState:UIControlStateHighlighted];
	button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	button.adjustsImageWhenDisabled = NO;
	button.adjustsImageWhenHighlighted = NO;
	[button addTarget:self action:@selector(modeButtonPressed:)
	 forControlEvents:UIControlEventTouchDown];
	return button;
}

- (UIView *)makeModeSeparatorAtX:(CGFloat)x {
	UIView *separator = [[UIView alloc] initWithFrame:
			CGRectMake(x, 0, kStatsSeparatorWidth, kStatsGroupHeight)];
	NSArray *names = @[@"ButtonGroupDivider.png",
					   @"ButtonGroupDivider_LeftHighlighted.png",
					   @"ButtonGroupDivider_RightHighlighted.png"];
	for (NSUInteger j = 0; j < names.count; j++){
		UIImage *art = TGStatsStretch(names[j], 6);
		UIImageView *layer = [[UIImageView alloc] initWithImage:art];
		layer.tag = (NSInteger)(100 + j);
		layer.frame = separator.bounds;
		layer.alpha = (j == 0) ? 1.0f : 0.0f;
		[separator addSubview:layer];
	}
	return separator;
}

- (void)updateModeButtons {
	NSUInteger count = _groupButtons.count;
	for (NSUInteger i = 0; i < count; i++){
		UIButton *button = _groupButtons[i];
		NSString *normalName = @"ButtonGroupCenter.png";
		NSString *highlightedName = @"ButtonGroupCenter_Highlighted.png";
		int leftCap = 1;
		if (i == 0){
			normalName = @"ButtonGroupLeft.png";
			highlightedName = @"ButtonGroupLeft_Highlighted.png";
			leftCap = 8;
		} else if (i == count - 1){
			normalName = @"ButtonGroupRight.png";
			highlightedName = @"ButtonGroupRight_Highlighted.png";
		}
		UIImage *normal = TGStatsStretch(normalName, leftCap);
		UIImage *highlighted = TGStatsStretch(highlightedName, leftCap);
		UIImage *shown = ((NSInteger)i == self.mode) ? highlighted : normal;
		[button setBackgroundImage:shown forState:UIControlStateNormal];
		[button setBackgroundImage:shown forState:UIControlStateHighlighted];
		if (!normal)
			button.backgroundColor = ((NSInteger)i == self.mode)
					? [[TGTheme shared] accentColour]
					: [UIColor colorWithWhite:0.62f alpha:1.0f];
	}

	for (NSUInteger i = 0; i < _groupSeparators.count; i++){
		UIView *separator = _groupSeparators[i];
		UIView *normal = [separator viewWithTag:100];
		UIView *leftLit = [separator viewWithTag:101];
		UIView *rightLit = [separator viewWithTag:102];
		UIView *shown = normal;
		if (self.mode == (NSInteger)i)
			shown = leftLit;
		else if (self.mode == (NSInteger)i + 1)
			shown = rightLit;
		shown.alpha = 1.0f;
		[separator bringSubviewToFront:shown];
		if (normal != shown) normal.alpha = 0.0f;
		if (leftLit != shown) leftLit.alpha = 0.0f;
		if (rightLit != shown) rightLit.alpha = 0.0f;
	}
}

- (void)modeButtonPressed:(UIButton *)button {
	if (self.mode == button.tag)
		return;
	self.mode = button.tag;
	[self updateModeButtons];
	[self.tableView setContentOffset:CGPointZero animated:NO];
	[self applyMode];
}

- (void)applyMode {
	self.tableView.tableHeaderView = (self.mode == 0 && self.chartView.points.count > 1)
			? self.chartView : nil;
	[self.tableView reloadData];
	[self updateEmptyLabel];
}

- (void)updateEmptyLabel {
	if (!self.loaded){
		_emptyLabel.text = @"Loading...";
		_emptyLabel.hidden = NO;
		return;
	}
	NSInteger rows = 0;
	for (NSInteger section = 0;
		 section < [self numberOfSectionsInTableView:self.tableView]; section++)
		rows += [self tableView:self.tableView numberOfRowsInSection:section];
	if (rows > 0){
		_emptyLabel.hidden = YES;
		return;
	}
	_emptyLabel.hidden = NO;
	if (self.mode == 1)
		_emptyLabel.text = @"No member statistics yet.";
	else if (self.mode == 2)
		_emptyLabel.text = @"This chat has no boosts.";
	else
		_emptyLabel.text = @"No statistics for this chat yet.";
}

#pragma mark - loading

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] statisticsForChat:self.chatId
								  isDark:[TGTheme shared].isDark
							  completion:^(NSDictionary *stats){
		weakSelf.loaded = YES;
		if ([stats isKindOfClass:[NSDictionary class]]){
			id values = stats[@"values"];
			id senders = stats[@"top_senders"];
			id graphs = stats[@"graphs"];
			weakSelf.values = [values isKindOfClass:[NSArray class]] ? values : @[];
			weakSelf.topSenders = [senders isKindOfClass:[NSArray class]] ? senders : @[];
			weakSelf.graphs = [graphs isKindOfClass:[NSArray class]] ? graphs : @[];
			id admins = stats[@"top_administrators"];
			id inviters = stats[@"top_inviters"];
			weakSelf.topAdmins = [admins isKindOfClass:[NSArray class]] ? admins : @[];
			weakSelf.topInviters = [inviters isKindOfClass:[NSArray class]]
					? inviters : @[];
		}
		[weakSelf loadFirstGraph];
		[weakSelf applyMode];
	}];

	[[TGClient shared] boostStatusForChat:self.chatId completion:^(NSDictionary *status){
		if ([status isKindOfClass:[NSDictionary class]])
			weakSelf.boostStatus = status;
		[weakSelf applyMode];
	}];
	[[TGClient shared] boostsForChat:self.chatId
					   onlyGiftCodes:NO
							  offset:@""
							   limit:20
						  completion:^(NSArray *boosts, NSString *nextOffset,
									   NSInteger totalCount){
		weakSelf.boosters = [boosts isKindOfClass:[NSArray class]] ? boosts : @[];
		[weakSelf applyMode];
	}];
}

- (void)loadFirstGraph {
	NSDictionary *graph = nil;
	for (id entry in self.graphs){
		if ([entry isKindOfClass:[NSDictionary class]]){
			graph = entry;
			break;
		}
	}
	if (!graph)
		return;
	NSString *json = TGProfileText(graph[@"json"]);
	if (json){
		[self applyGraphJson:json];
		return;
	}
	NSString *token = TGProfileText(graph[@"token"]);
	if (!token)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] statisticalGraphForChat:self.chatId
										 token:token
									   zoomAtX:0
									completion:^(NSDictionary *loaded){
		NSString *loadedJson = [loaded isKindOfClass:[NSDictionary class]]
				? TGProfileText(loaded[@"json"]) : nil;
		if (!loadedJson)
			return;
		[weakSelf applyGraphJson:loadedJson];
		[weakSelf applyMode];
	}];
}

- (void)applyGraphJson:(NSString *)json {
	NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
	if (!data.length)
		return;
	id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (![parsed isKindOfClass:[NSDictionary class]])
		return;
	id columns = [(NSDictionary *)parsed objectForKey:@"columns"];
	if (![columns isKindOfClass:[NSArray class]])
		return;

	NSArray *xColumn = nil;
	NSArray *yColumn = nil;
	for (id column in columns){
		if (![column isKindOfClass:[NSArray class]] || [column count] < 2)
			continue;
		NSString *key = [[column objectAtIndex:0] isKindOfClass:[NSString class]]
				? [column objectAtIndex:0] : nil;
		if ([key isEqualToString:@"x"])
			xColumn = column;
		else if (!yColumn)
			yColumn = column;
	}
	if (!yColumn)
		return;

	NSMutableArray *points = [NSMutableArray array];
	for (NSUInteger i = 1; i < yColumn.count; i++){
		id value = yColumn[i];
		if ([value isKindOfClass:[NSNumber class]])
			[points addObject:value];
	}
	if (points.count > 30)
		[points removeObjectsInRange:NSMakeRange(0, points.count - 30)];
	if (points.count < 2)
		return;

	self.chartView.points = points;

	if (xColumn.count >= 2){
		NSUInteger total = xColumn.count - 1;
		NSUInteger firstIndex = total > points.count ? total - points.count + 1 : 1;
		self.chartView.leftDate = [self dayTextFor:xColumn[firstIndex]];
		self.chartView.rightDate = [self dayTextFor:[xColumn lastObject]];
	}
}

- (NSString *)dayTextFor:(id)milliseconds {
	if (![milliseconds isKindOfClass:[NSNumber class]])
		return @"";
	static NSDateFormatter *formatter = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateFormat = @"d MMM";
	});
	NSTimeInterval seconds = [milliseconds doubleValue] / 1000.0;
	return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:seconds]];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	if (self.mode == 2)
		return 2;
	if (self.mode == 1)
		return 3;
	return 1;
}

- (NSArray *)peopleForSection:(NSInteger)section {
	if (section == 1)
		return self.topAdmins ?: @[];
	if (section == 2)
		return self.topInviters ?: @[];
	return self.topSenders ?: @[];
}

- (NSString *)peopleSummaryFor:(NSDictionary *)entry section:(NSInteger)section {
	NSMutableArray *parts = [NSMutableArray array];
	if (section == 1){
		NSArray *keys = @[@"deleted_message_count", @"banned_user_count",
						  @"restricted_user_count"];
		NSArray *words = @[@"deleted", @"banned", @"restricted"];
		for (NSUInteger i = 0; i < keys.count; i++){
			id raw = [entry objectForKey:keys[i]];
			NSInteger value = [raw isKindOfClass:[NSNumber class]]
					? [raw integerValue] : 0;
			if (value > 0)
				[parts addObject:[NSString stringWithFormat:@"%ld %@",
						(long)value, words[i]]];
		}
	} else if (section == 2){
		id raw = [entry objectForKey:@"added_member_count"];
		NSInteger value = [raw isKindOfClass:[NSNumber class]] ? [raw integerValue] : 0;
		if (value > 0)
			[parts addObject:[NSString stringWithFormat:@"%ld invited", (long)value]];
	}
	return parts.count ? [parts componentsJoinedByString:@", "] : nil;
}

- (NSArray *)boostSummaryRows {
	if (![self.boostStatus isKindOfClass:[NSDictionary class]])
		return @[];
	NSMutableArray *rows = [NSMutableArray array];
	NSInteger level = [self.boostStatus[@"level"] isKindOfClass:[NSNumber class]]
			? [self.boostStatus[@"level"] integerValue] : 0;
	NSInteger count = [self.boostStatus[@"boost_count"] isKindOfClass:[NSNumber class]]
			? [self.boostStatus[@"boost_count"] integerValue] : 0;
	NSInteger next = [self.boostStatus[@"next_level_boost_count"]
			isKindOfClass:[NSNumber class]]
			? [self.boostStatus[@"next_level_boost_count"] integerValue] : 0;
	[rows addObject:@[@"Boost level", [NSString stringWithFormat:@"%ld", (long)level]]];
	[rows addObject:@[@"Boosts", [NSString stringWithFormat:@"%ld", (long)count]]];
	if (next > count)
		[rows addObject:@[@"To next level",
						  [NSString stringWithFormat:@"%ld more", (long)(next - count)]]];
	return rows;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (self.mode == 0)
		return self.values.count;
	if (self.mode == 1)
		return [self peopleForSection:section].count;
	return section == 0 ? [self boostSummaryRows].count : self.boosters.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.mode == 1)
		return indexPath.section == 0 ? kStatsPosterRowHeight : kStatsRowHeight;
	return kStatsRowHeight;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (self.mode == 0 && self.values.count)
		return @"Overview";
	if (self.mode == 1 && [self peopleForSection:section].count){
		if (section == 1)
			return @"Top admins";
		if (section == 2)
			return @"Top inviters";
		return @"Top posters";
	}
	if (self.mode == 2 && section == 1 && self.boosters.count)
		return @"Boosted by";
	return nil;
}

- (NSString *)valueTextFor:(NSDictionary *)entry {
	double value = [entry[@"value"] isKindOfClass:[NSNumber class]]
			? [entry[@"value"] doubleValue] : 0;
	return (value == floor(value))
			? [NSString stringWithFormat:@"%lld", (long long)value]
			: [NSString stringWithFormat:@"%.2f", value];
}

- (NSString *)growthTextFor:(NSDictionary *)entry {
	double growth = [entry[@"growth"] isKindOfClass:[NSNumber class]]
			? [entry[@"growth"] doubleValue] : 0;
	if (fabs(growth) < 0.005)
		return nil;
	return [NSString stringWithFormat:@"%@%.2f%%", (growth > 0 ? @"+" : @""), growth];
}

- (NSInteger)largestSenderCount {
	NSInteger largest = 0;
	for (id entry in self.topSenders){
		if (![entry isKindOfClass:[NSDictionary class]])
			continue;
		id count = [entry objectForKey:@"sent_message_count"];
		NSInteger value = [count isKindOfClass:[NSNumber class]]
				? [count integerValue] : 0;
		if (value > largest)
			largest = value;
	}
	return largest;
}

- (UITableViewCell *)makePosterCell:(UITableView *)tableView {
	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"poster"];

	UIImageView *avatar = [[UIImageView alloc] initWithFrame:
			CGRectMake(5, 4, 40, 40)];
	avatar.tag = 21;
	avatar.layer.cornerRadius = 4;
	avatar.clipsToBounds = YES;
	[cell.contentView addSubview:avatar];

	UILabel *name = [[UILabel alloc] initWithFrame:
			CGRectMake(54, 4, tableView.bounds.size.width - 118, 20)];
	name.tag = 22;
	name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	name.backgroundColor = [UIColor clearColor];
	name.font = [UIFont systemFontOfSize:17];
	[cell.contentView addSubview:name];

	UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(54, 25, 0, 4)];
	bar.tag = 23;
	bar.backgroundColor = TGProfileColour(0x337acc);
	[cell.contentView addSubview:bar];

	UILabel *subtitle = [[UILabel alloc] initWithFrame:
			CGRectMake(54, 30, tableView.bounds.size.width - 118, 16)];
	subtitle.tag = 24;
	subtitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	subtitle.backgroundColor = [UIColor clearColor];
	subtitle.font = [UIFont systemFontOfSize:13];
	subtitle.textColor = TGProfileColour(0x888888);
	[cell.contentView addSubview:subtitle];

	UILabel *count = [[UILabel alloc] initWithFrame:
			CGRectMake(tableView.bounds.size.width - 64, 15, 54, 18)];
	count.tag = 25;
	count.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	count.backgroundColor = [UIColor clearColor];
	count.textAlignment = NSTextAlignmentRight;
	count.font = [UIFont boldSystemFontOfSize:13];
	count.textColor = TGProfileColour(0x356596);
	[cell.contentView addSubview:count];
	return cell;
}

- (UITableViewCell *)posterCell:(UITableView *)tableView row:(NSInteger)row {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"poster"];
	if (!cell)
		cell = [self makePosterCell:tableView];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;

	id raw = row < (NSInteger)self.topSenders.count ? self.topSenders[row] : nil;
	NSDictionary *entry = [raw isKindOfClass:[NSDictionary class]] ? raw : @{};
	int64_t userId = TGProfileInt64(entry[@"user_id"]);
	NSString *name = TGProfileText(entry[@"name"])
			?: TGProfileText([[TGClient shared] nameForUserId:userId]) ?: @"";
	NSInteger messages = [entry[@"sent_message_count"] isKindOfClass:[NSNumber class]]
			? [entry[@"sent_message_count"] integerValue] : 0;
	NSInteger characters = [entry[@"average_character_count"]
			isKindOfClass:[NSNumber class]]
			? [entry[@"average_character_count"] integerValue] : 0;

	UILabel *nameLabel = (UILabel *)[cell.contentView viewWithTag:22];
	nameLabel.text = name;
	nameLabel.textColor = [[TGTheme shared] primaryTextColour];

	UILabel *subtitle = (UILabel *)[cell.contentView viewWithTag:24];
	subtitle.text = characters > 0
			? [NSString stringWithFormat:@"~%ld characters per message", (long)characters]
			: nil;

	UILabel *count = (UILabel *)[cell.contentView viewWithTag:25];
	count.text = messages > 0 ? [NSString stringWithFormat:@"%ld", (long)messages] : @"";

	UIImageView *avatar = (UIImageView *)[cell.contentView viewWithTag:21];
	avatar.image = [TGIcons avatarWithInitials:TGProfileInitial(name)
										  size:40
									  colourId:userId];

	NSInteger largest = [self largestSenderCount];
	CGFloat available = cell.contentView.bounds.size.width - 54 - 70;
	CGFloat barWidth = (largest > 0 && messages > 0)
			? floorf(available * messages / (CGFloat)largest) : 0;
	UIView *bar = [cell.contentView viewWithTag:23];
	bar.frame = CGRectMake(54, 25, MAX(barWidth, messages > 0 ? 2 : 0), 4);
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.mode == 1 && indexPath.section == 0)
		return [self posterCell:tableView row:indexPath.row];

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stat"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"stat"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.font = [UIFont systemFontOfSize:17];
	cell.textLabel.textColor = [TGTheme shared].isDark
			? [[TGTheme shared] primaryTextColour] : TGProfileColour(0x516691);
	cell.detailTextLabel.font = [UIFont boldSystemFontOfSize:17];
	cell.detailTextLabel.textColor = [TGTheme shared].isDark
			? [[TGTheme shared] secondaryTextColour] : TGProfileColour(0x356596);

	if (self.mode == 1){
		[self fillPeopleCell:cell atIndexPath:indexPath];
		return cell;
	}

	if (self.mode == 2){
		[self fillBoostCell:cell atIndexPath:indexPath];
		return cell;
	}

	id raw = indexPath.row < (NSInteger)self.values.count
			? self.values[indexPath.row] : nil;
	NSDictionary *entry = [raw isKindOfClass:[NSDictionary class]] ? raw : @{};
	cell.textLabel.text = TGProfileText(entry[@"title"])
			?: (TGProfileText(entry[@"key"]) ?: @"");
	NSString *growth = [self growthTextFor:entry];
	if (growth)
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@",
				[self valueTextFor:entry], growth];
	else
		cell.detailTextLabel.text = [self valueTextFor:entry];
	return cell;
}

- (void)fillPeopleCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
	NSArray *people = [self peopleForSection:indexPath.section];
	id raw = indexPath.row < (NSInteger)people.count ? people[indexPath.row] : nil;
	NSDictionary *entry = [raw isKindOfClass:[NSDictionary class]] ? raw : @{};
	int64_t userId = TGProfileInt64(entry[@"user_id"]);
	NSString *name = TGProfileText(entry[@"name"])
			?: TGProfileText([[TGClient shared] nameForUserId:userId]) ?: @"";
	cell.selectionStyle = userId ? UITableViewCellSelectionStyleBlue
								 : UITableViewCellSelectionStyleNone;
	cell.textLabel.text = name;
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.text = [self peopleSummaryFor:entry
											   section:indexPath.section];
}

- (void)fillBoostCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0){
		NSArray *rows = [self boostSummaryRows];
		NSArray *pair = indexPath.row < (NSInteger)rows.count
				? rows[indexPath.row] : nil;
		cell.textLabel.text = pair.count ? pair[0] : @"";
		cell.detailTextLabel.text = pair.count > 1 ? pair[1] : nil;
		return;
	}
	id raw = indexPath.row < (NSInteger)self.boosters.count
			? self.boosters[indexPath.row] : nil;
	NSDictionary *entry = [raw isKindOfClass:[NSDictionary class]] ? raw : @{};
	NSString *name = TGProfileText(entry[@"name"]);
	if (!name){
		int64_t userId = TGProfileInt64(entry[@"user_id"]);
		name = userId ? TGProfileText([[TGClient shared] nameForUserId:userId]) : nil;
	}
	NSString *source = TGProfileText(entry[@"source"]);
	cell.textLabel.text = name ?: ([source isEqualToString:@"giveaway"]
			? @"Giveaway" : @"Unclaimed");
	NSInteger count = [entry[@"count"] isKindOfClass:[NSNumber class]]
			? [entry[@"count"] integerValue] : 0;
	cell.detailTextLabel.text = count > 1
			? [NSString stringWithFormat:@"%ld", (long)count] : nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.mode != 1)
		return;
	NSArray *people = [self peopleForSection:indexPath.section];
	id raw = indexPath.row < (NSInteger)people.count ? people[indexPath.row] : nil;
	if (![raw isKindOfClass:[NSDictionary class]])
		return;
	int64_t userId = TGProfileInt64([raw objectForKey:@"user_id"]);
	if (!userId)
		return;
	NSString *name = TGProfileText([raw objectForKey:@"name"])
			?: TGProfileText([[TGClient shared] nameForUserId:userId]) ?: @"";
	UINavigationController *navigation = self.navigationController;
	if (!navigation)
		return;
	[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
		TGProfileViewController *profile = [[TGProfileViewController alloc]
				initWithChatId:chatId userId:userId title:name];
		[navigation pushViewController:profile animated:YES];
	}];
}

@end

@implementation TGProfileBoostsController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Boosts";
	self.boosters = @[];
	self.tableView.backgroundColor = TGProfileListBackground();
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] boostStatusForChat:self.chatId completion:^(NSDictionary *status){
		if ([status isKindOfClass:[NSDictionary class]])
			weakSelf.status = status;
		[weakSelf.tableView reloadData];
		[weakSelf loadNextLevelFeatures];
	}];
	[[TGClient shared] boostLevelFeatureTableForChannel:self.isChannel
											 completion:^(NSArray *levels,
														  NSDictionary *minimums){
		weakSelf.featureTable = [levels isKindOfClass:[NSArray class]] ? levels : @[];
		[weakSelf.tableView reloadData];
	}];
	[[TGClient shared] boostLinkForChat:self.chatId
							 completion:^(NSString *link, BOOL isPublic){
		weakSelf.boostLink = TGProfileText(link);
		[weakSelf.tableView reloadData];
	}];
	[[TGClient shared] boostsForChat:self.chatId
					   onlyGiftCodes:NO
							  offset:@""
							   limit:20
						  completion:^(NSArray *boosts, NSString *nextOffset,
									   NSInteger totalCount){
		weakSelf.boosters = [boosts isKindOfClass:[NSArray class]] ? boosts : @[];
		[weakSelf.tableView reloadData];
	}];
}

- (NSInteger)numberForKey:(NSString *)key {
	id value = self.status[key];
	return [value isKindOfClass:[NSNumber class]] ? [value integerValue] : 0;
}

- (void)loadNextLevelFeatures {
	NSInteger next = [self numberForKey:@"level"] + 1;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] boostLevelFeaturesForChannel:self.isChannel
											  level:next
										 completion:^(NSDictionary *features){
		if (![features isKindOfClass:[NSDictionary class]])
			return;
		weakSelf.nextLevelFeatures = features;
		[weakSelf.tableView reloadData];
	}];
}

+ (NSString *)summaryOfFeatures:(NSDictionary *)features {
	if (![features isKindOfClass:[NSDictionary class]])
		return nil;
	NSMutableArray *parts = [NSMutableArray array];
	NSInteger stories = [features[@"story_per_day_count"] isKindOfClass:[NSNumber class]]
			? [features[@"story_per_day_count"] integerValue] : 0;
	if (stories > 0)
		[parts addObject:[NSString stringWithFormat:@"%ld stories a day", (long)stories]];
	NSInteger reactions =
			[features[@"custom_emoji_reaction_count"] isKindOfClass:[NSNumber class]]
					? [features[@"custom_emoji_reaction_count"] integerValue] : 0;
	if (reactions > 0)
		[parts addObject:[NSString stringWithFormat:@"%ld custom reactions",
				(long)reactions]];
	NSInteger colours = [features[@"accent_color_count"] isKindOfClass:[NSNumber class]]
			? [features[@"accent_color_count"] integerValue] : 0;
	if (colours > 0)
		[parts addObject:[NSString stringWithFormat:@"%ld name colours", (long)colours]];
	if (TGProfileBool(features[@"can_set_emoji_status"]))
		[parts addObject:@"emoji status"];
	if (TGProfileBool(features[@"can_set_custom_background"]))
		[parts addObject:@"custom background"];
	if (TGProfileBool(features[@"can_disable_sponsored_messages"]))
		[parts addObject:@"no sponsored messages"];
	if (!parts.count)
		return nil;
	return [parts componentsJoinedByString:@", "];
}

- (void)showBoostsByUser:(int64_t)userId named:(NSString *)name {
	[[TGClient shared] boostsByUser:userId inChat:self.chatId
						 completion:^(NSArray *boosts){
		NSInteger total = 0;
		if ([boosts isKindOfClass:[NSArray class]]){
			for (id entry in boosts){
				if (![entry isKindOfClass:[NSDictionary class]])
					continue;
				id count = [entry objectForKey:@"count"];
				total += [count isKindOfClass:[NSNumber class]]
						? [count integerValue] : 1;
			}
		}
		NSString *message = total > 0
				? [NSString stringWithFormat:@"%@ gave this chat %ld boost%@.",
						(name.length ? name : @"This person"), (long)total,
						total == 1 ? @"" : @"s"]
				: @"No boosts from this person.";
		[[[UIAlertView alloc] initWithTitle:nil message:message delegate:nil
						  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
	}];
}

- (NSArray *)summaryRows {
	if (!self.status)
		return @[];
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:@[@"Level", [NSString stringWithFormat:@"%ld",
								 (long)[self numberForKey:@"level"]]]];
	[rows addObject:@[@"Boosts", [NSString stringWithFormat:@"%ld",
								  (long)[self numberForKey:@"boost_count"]]]];
	NSInteger next = [self numberForKey:@"next_level_boost_count"];
	NSInteger current = [self numberForKey:@"boost_count"];
	if (next > current)
		[rows addObject:@[@"To next level",
						  [NSString stringWithFormat:@"%ld more", (long)(next - current)]]];
	NSInteger premium = [self numberForKey:@"premium_member_count"];
	if (premium > 0)
		[rows addObject:@[@"Premium members",
						  [NSString stringWithFormat:@"%ld (%ld%%)", (long)premium,
						   (long)[self numberForKey:@"premium_member_percentage"]]]];
	return rows;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return [self summaryRows].count;
	if (section == 1) return self.status ? (self.boostLink.length ? 2 : 1) : 0;
	if (section == 2) return self.boosters.count;
	return self.featureTable.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 2 && self.boosters.count) return @"Boosted by";
	if (section == 3 && self.featureTable.count) return @"What each level unlocks";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section != 0)
		return nil;
	if (!self.status)
		return @"Loading...";
	NSString *base = self.isChannel
			? @"Boosts unlock extra features for this channel."
			: @"Boosts unlock extra features for this group.";
	NSString *next = [TGProfileBoostsController
			summaryOfFeatures:self.nextLevelFeatures];
	if (!next.length)
		return base;
	return [NSString stringWithFormat:@"%@\nLevel %ld unlocks %@.", base,
			(long)([self numberForKey:@"level"] + 1), next];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"boost"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"boost"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.textColor = [TGTheme shared].isDark
			? [[TGTheme shared] secondaryTextColour] : TGProfileColour(0x888888);
	cell.detailTextLabel.text = nil;

	if (indexPath.section == 0){
		NSArray *rows = [self summaryRows];
		NSArray *pair = indexPath.row < (NSInteger)rows.count ? rows[indexPath.row] : nil;
		cell.textLabel.text = pair.count ? pair[0] : @"";
		cell.detailTextLabel.text = pair.count > 1 ? pair[1] : nil;
		return cell;
	}

	if (indexPath.section == 1){
		[self fillBoostActionCell:cell atRow:indexPath.row];
		return cell;
	}

	if (indexPath.section == 3){
		[self fillLevelFeatureCell:cell atRow:indexPath.row];
		return cell;
	}

	id raw = indexPath.row < (NSInteger)self.boosters.count
			? self.boosters[indexPath.row] : nil;
	NSDictionary *entry = [raw isKindOfClass:[NSDictionary class]] ? raw : @{};
	NSString *name = TGProfileText(entry[@"name"]);
	if (!name){
		int64_t userId = TGProfileInt64(entry[@"user_id"]);
		name = userId ? TGProfileText([[TGClient shared] nameForUserId:userId]) : nil;
	}
	NSString *source = TGProfileText(entry[@"source"]);
	cell.textLabel.text = name ?: ([source isEqualToString:@"giveaway"]
			? @"Giveaway" : @"Unclaimed");
	NSInteger count = [entry[@"count"] isKindOfClass:[NSNumber class]]
			? [entry[@"count"] integerValue] : 0;
	cell.detailTextLabel.text = count > 1
			? [NSString stringWithFormat:@"%ld boosts", (long)count] : source;
	if (TGProfileInt64(entry[@"user_id"]))
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)fillBoostActionCell:(UITableViewCell *)cell atRow:(NSInteger)row {
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.textLabel.textColor = TGProfileColour(0x316ea1);
	BOOL boosted = TGProfileBool(self.status[@"is_boosted"]);
	if (row == 0)
		cell.textLabel.text = boosted ? @"Boost Again" : @"Boost This Chat";
	else
		cell.textLabel.text = @"Copy Boost Link";
}

- (void)fillLevelFeatureCell:(UITableViewCell *)cell atRow:(NSInteger)row {
	id level = row < (NSInteger)self.featureTable.count
			? self.featureTable[row] : nil;
	NSDictionary *features = [level isKindOfClass:[NSDictionary class]] ? level : @{};
	NSInteger number = [features[@"level"] isKindOfClass:[NSNumber class]]
			? [features[@"level"] integerValue] : (row + 1);
	cell.textLabel.text = [NSString stringWithFormat:@"Level %ld", (long)number];
	cell.detailTextLabel.text =
			[TGProfileBoostsController summaryOfFeatures:features];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 2){
		id raw = indexPath.row < (NSInteger)self.boosters.count
				? self.boosters[indexPath.row] : nil;
		if (![raw isKindOfClass:[NSDictionary class]])
			return;
		int64_t userId = TGProfileInt64([raw objectForKey:@"user_id"]);
		if (!userId)
			return;
		NSString *name = TGProfileText([raw objectForKey:@"name"])
				?: TGProfileText([[TGClient shared] nameForUserId:userId]);
		[self showBoostsByUser:userId named:name];
		return;
	}
	if (indexPath.section != 1)
		return;
	if (indexPath.row == 1){
		if (!self.boostLink.length)
			return;
		[UIPasteboard generalPasteboard].string = self.boostLink;
		[[[UIAlertView alloc] initWithTitle:nil message:@"Boost link copied."
								   delegate:nil cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
		return;
	}
	[self boostNow];
}

- (void)boostNow {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] channelBoostSlotsWithCompletion:^(NSArray *slots){
		NSMutableArray *usable = [NSMutableArray array];
		if (![slots isKindOfClass:[NSArray class]])
			slots = @[];
		for (id slot in slots){
			if (![slot isKindOfClass:[NSDictionary class]])
				continue;
			if (!TGProfileBool(slot[@"is_available"]))
				continue;
			id slotId = slot[@"slot_id"];
			if ([slotId isKindOfClass:[NSNumber class]])
				[usable addObject:slotId];
			if (usable.count)
				break;
		}
		if (!usable.count){
			[[[UIAlertView alloc] initWithTitle:nil
					message:@"You have no boost to give. Boosts come with Telegram Premium."
				   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
			return;
		}
		[[TGClient shared] boostChat:weakSelf.chatId
						 withSlotIds:usable
						  completion:^(NSArray *updated){
			if (![updated isKindOfClass:[NSArray class]]){
				[[[UIAlertView alloc] initWithTitle:nil
						message:@"This chat could not be boosted."
					   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
				return;
			}
			[weakSelf reload];
		}];
	}];
}

@end

@implementation TGProfileCommonGroupsController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Groups in Common";
	self.tableView.backgroundColor = TGProfileListBackground();
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	if (!self.chats.count)
		[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)reload {
	if (!self.userId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] groupsInCommonWithUser:self.userId completion:^(NSArray *chats){
		weakSelf.chats = [chats isKindOfClass:[NSArray class]] ? chats : @[];
		[weakSelf.tableView reloadData];
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.chats.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return kMemberRowHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"common"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"common"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	id raw = indexPath.row < (NSInteger)self.chats.count ? self.chats[indexPath.row] : nil;
	NSDictionary *chat = [raw isKindOfClass:[NSDictionary class]] ? raw : @{};
	NSString *title = TGProfileText(chat[@"title"]) ?: @"";
	cell.textLabel.text = title;
	cell.imageView.image = [TGIcons avatarWithInitials:TGProfileInitial(title)
												  size:kMemberAvatarSide
											  colourId:TGProfileInt64(chat[@"id"])];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	id raw = indexPath.row < (NSInteger)self.chats.count ? self.chats[indexPath.row] : nil;
	if (![raw isKindOfClass:[NSDictionary class]])
		return;
	int64_t chatId = TGProfileInt64([raw objectForKey:@"id"]);
	if (!chatId)
		return;
	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = chatId;
	chat.chatTitle = TGProfileText([raw objectForKey:@"title"]) ?: @"";
	[self.navigationController pushViewController:chat animated:YES];
}

@end

@implementation TGProfileLinkJoinsController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Joined via Link";
	self.tableView.backgroundColor = TGProfileListBackground();
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)reload {
	if (!self.chatId || !self.link.length){
		self.loaded = YES;
		[self.tableView reloadData];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] membersJoinedViaInviteLink:self.link
										   inChat:self.chatId
											limit:100
									   completion:^(NSArray *members, NSInteger total){
		weakSelf.loaded = YES;
		weakSelf.members = [members isKindOfClass:[NSArray class]] ? members : @[];
		weakSelf.total = total;
		[weakSelf.tableView reloadData];
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.members.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return kMemberRowHeight;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (!self.loaded)
		return nil;
	if (!self.members.count)
		return @"Nobody has joined through this link";
	if (self.total > (NSInteger)self.members.count)
		return [NSString stringWithFormat:@"%ld joined, showing the latest %ld",
				(long)self.total, (long)self.members.count];
	return [NSString stringWithFormat:@"%ld joined", (long)self.total];
}

- (NSString *)dateTextFor:(id)value {
	if (![value isKindOfClass:[NSNumber class]])
		return @"";
	NSTimeInterval seconds = [value doubleValue];
	if (seconds <= 0)
		return @"";
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterMediumStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
	}
	return [formatter stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:seconds]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"join"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"join"];
	[[TGTheme shared] styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	id raw = indexPath.row < (NSInteger)self.members.count
			? self.members[indexPath.row] : nil;
	NSDictionary *member = [raw isKindOfClass:[NSDictionary class]] ? raw : @{};
	NSString *name = TGProfileText(member[@"name"]) ?: @"";
	cell.textLabel.text = name;
	cell.detailTextLabel.text = [self dateTextFor:member[@"date"]];
	cell.imageView.image = [TGIcons avatarWithInitials:TGProfileInitial(name)
												  size:kMemberAvatarSide
											  colourId:TGProfileInt64(member[@"userId"])];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	id raw = indexPath.row < (NSInteger)self.members.count
			? self.members[indexPath.row] : nil;
	if (![raw isKindOfClass:[NSDictionary class]])
		return;
	int64_t userId = TGProfileInt64([raw objectForKey:@"userId"]);
	if (!userId)
		return;
	NSString *name = TGProfileText([raw objectForKey:@"name"]) ?: @"";
	UINavigationController *navigation = self.navigationController;
	if (!navigation)
		return;
	[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
		TGProfileViewController *profile =
				[[TGProfileViewController alloc] initWithChatId:chatId
														 userId:userId
														  title:name];
		[navigation pushViewController:profile animated:YES];
	}];
}

@end


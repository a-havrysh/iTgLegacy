#import "TGMessageActionsSheet.h"
#import "TGPopupMenu.h"
#import "TGActionSheet.h"
#import "TGAlertView.h"
#import "TGClient.h"
#import "TGClient+Messages.h"

NSString *const TGMessageActionReply = @"reply";
NSString *const TGMessageActionEdit = @"edit";
NSString *const TGMessageActionCopy = @"copy";
NSString *const TGMessageActionCopyLink = @"copyLink";
NSString *const TGMessageActionForward = @"forward";
NSString *const TGMessageActionPin = @"pin";
NSString *const TGMessageActionUnpin = @"unpin";
NSString *const TGMessageActionTranslate = @"translate";
NSString *const TGMessageActionSelect = @"select";
NSString *const TGMessageActionDeleteForMe = @"deleteForMe";
NSString *const TGMessageActionDeleteForEveryone = @"deleteForEveryone";
NSString *const TGMessageActionReport = @"report";

static NSString *const TGMessageActionDeleteRow = @"deleteRow";

@interface TGMessageActionsSheet ()
@property (nonatomic, strong) NSArray *actionIds;
@property (nonatomic, strong) TGActionSheet *currentActionSheet;
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, copy) void (^completion)(NSString *action);
@property (nonatomic, assign) BOOL presenting;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL canDeleteForMe;
@property (nonatomic, assign) BOOL canDeleteForEveryone;
@property (nonatomic, assign) BOOL confirming;
@property (nonatomic, assign) BOOL resolvedPinned;
@property (nonatomic, weak) UIView *menuView;
@end

@implementation TGMessageActionsSheet

+ (instancetype)sheetForMessage:(int64_t)messageId inChat:(int64_t)chatId {
	TGMessageActionsSheet *sheet = [[TGMessageActionsSheet alloc] init];
	sheet.messageId = messageId;
	sheet.chatId = chatId;
	return sheet;
}

- (instancetype)init {
	self = [super init];
	if (self != nil)
		_allowsSelection = YES;
	return self;
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

#pragma mark - presenting

- (void)presentAtPoint:(CGPoint)point
                inView:(UIView *)host
            completion:(void (^)(NSString *action))completion {
	if (self.presenting || host == nil)
		return;
	if (self.messageId == 0 || self.chatId == 0){
		if (completion)
			completion(nil);
		return;
	}

	self.presenting = YES;
	self.finished = NO;
	self.hostView = host;
	self.completion = completion;
	self.confirming = NO;
	self.resolvedPinned = self.pinned;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] propertiesOfMessage:self.messageId
									inChat:self.chatId
								completion:^(NSDictionary *properties){
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (strongSelf == nil)
				return;
			if ([properties isKindOfClass:NSDictionary.class] &&
				[strongSelf flag:@"canPin" in:properties]){
				[[TGClient shared] isMessagePinned:strongSelf.messageId
											inChat:strongSelf.chatId
										completion:^(BOOL pinned){
					dispatch_async(dispatch_get_main_queue(), ^{
						__strong typeof(weakSelf) innerSelf = weakSelf;
						innerSelf.resolvedPinned = pinned;
						[innerSelf showMenuAtPoint:point properties:properties];
					});
				}];
				return;
			}
			[strongSelf showMenuAtPoint:point properties:properties];
		});
	}];
}

- (void)showMenuAtPoint:(CGPoint)point properties:(NSDictionary *)properties {
	self.presenting = NO;

	UIView *host = self.hostView;
	if (host == nil || host.window == nil){
		[self finishWithAction:nil];
		return;
	}

	if (![properties isKindOfClass:NSDictionary.class] || properties.count == 0){
		[self reportUnavailable];
		return;
	}

	NSMutableArray *items = [[NSMutableArray alloc] init];
	NSMutableArray *ids = [[NSMutableArray alloc] init];
	[self buildItems:items ids:ids fromProperties:properties];

	if (items.count == 0){
		[self reportUnavailable];
		return;
	}

	self.actionIds = ids;

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:point inView:host
				  onChoice:^(NSInteger index, __unused NSString *title){
		[weakSelf menuChoseIndex:index];
	}];

	self.menuView = [self openMenuViewInHost:host];
	if (self.menuView == nil){
		[self finishWithAction:nil];
		return;
	}
	[self scheduleDismissalWatch];
}

- (UIView *)openMenuViewInHost:(UIView *)host {
	Class menuClass = NSClassFromString(@"TGPopupMenu");
	if (menuClass == Nil)
		return nil;
	for (UIView *view in [host.subviews reverseObjectEnumerator]){
		if ([view isKindOfClass:menuClass])
			return view;
	}
	return nil;
}

- (void)scheduleDismissalWatch {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(checkMenuStillOpen)
											   object:nil];
	[self performSelector:@selector(checkMenuStillOpen) withObject:nil afterDelay:0.2];
}

- (void)checkMenuStillOpen {
	if (self.finished || self.confirming)
		return;
	UIView *menu = self.menuView;
	if (menu != nil && menu.superview != nil && menu.window != nil){
		[self scheduleDismissalWatch];
		return;
	}
	self.menuView = nil;
	[self finishWithAction:nil];
}

- (void)stopDismissalWatch {
	self.menuView = nil;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(checkMenuStillOpen)
											   object:nil];
}

- (BOOL)flag:(NSString *)key in:(NSDictionary *)properties {
	id value = properties[key];
	return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

- (void)add:(NSMutableArray *)items
		ids:(NSMutableArray *)ids
	  title:(NSString *)title
	   icon:(NSString *)icon
	 action:(NSString *)action
destructive:(BOOL)destructive {
	NSMutableDictionary *item = [[NSMutableDictionary alloc] init];
	item[@"title"] = title;
	if (icon.length)
		item[@"icon"] = icon;
	if (destructive)
		item[@"destructive"] = @YES;
	[items addObject:item];
	[ids addObject:action];
}

- (void)buildItems:(NSMutableArray *)items
			   ids:(NSMutableArray *)ids
	fromProperties:(NSDictionary *)properties {
	BOOL hasText = self.messageText.length > 0;

	if ([self flag:@"canReply" in:properties])
		[self add:items ids:ids title:@"Reply" icon:@"reply"
			action:TGMessageActionReply destructive:NO];

	if ([self flag:@"canEdit" in:properties] || [self flag:@"canEditMedia" in:properties])
		[self add:items ids:ids title:@"Edit" icon:@"edit"
			action:TGMessageActionEdit destructive:NO];

	if (hasText && [self flag:@"canCopy" in:properties])
		[self add:items ids:ids title:@"Copy" icon:@"copy"
			action:TGMessageActionCopy destructive:NO];

	if ([self flag:@"canGetLink" in:properties])
		[self add:items ids:ids title:@"Copy Link" icon:@"copy"
			action:TGMessageActionCopyLink destructive:NO];

	if ([self flag:@"canForward" in:properties])
		[self add:items ids:ids title:@"Forward" icon:@"forward"
			action:TGMessageActionForward destructive:NO];

	if ([self flag:@"canPin" in:properties]){
		if (self.resolvedPinned)
			[self add:items ids:ids title:@"Unpin" icon:@"unpin"
				action:TGMessageActionUnpin destructive:NO];
		else
			[self add:items ids:ids title:@"Pin" icon:@"pin"
				action:TGMessageActionPin destructive:NO];
	}

	BOOL canTranslate = properties[@"canTranslate"] != nil
			? [self flag:@"canTranslate" in:properties] : hasText;
	if (canTranslate)
		[self add:items ids:ids title:@"Translate" icon:nil
			action:TGMessageActionTranslate destructive:NO];

	BOOL forMe = [self flag:@"canDeleteForMe" in:properties];
	BOOL forEveryone = [self flag:@"canDeleteForEveryone" in:properties];
	if (forEveryone && !forMe)
		[self add:items ids:ids title:@"Delete for Everyone" icon:@"delete"
			action:TGMessageActionDeleteForEveryone destructive:YES];
	else if (forMe && !forEveryone)
		[self add:items ids:ids title:@"Delete" icon:@"delete"
			action:TGMessageActionDeleteForMe destructive:YES];
	else if (forMe && forEveryone)
		[self add:items ids:ids title:@"Delete" icon:@"delete"
			action:TGMessageActionDeleteRow destructive:YES];

	if (self.allowsSelection && (properties[@"canSelect"] == nil ||
								 [self flag:@"canSelect" in:properties]))
		[self add:items ids:ids title:@"Select" icon:nil
			action:TGMessageActionSelect destructive:NO];

	if ([self flag:@"canReport" in:properties])
		[self add:items ids:ids title:@"Report" icon:nil
			action:TGMessageActionReport destructive:NO];

	self.canDeleteForMe = forMe;
	self.canDeleteForEveryone = forEveryone;
}

#pragma mark - choice

- (void)menuChoseIndex:(NSInteger)index {
	[self stopDismissalWatch];

	if (index < 0 || index >= (NSInteger)self.actionIds.count){
		[self finishWithAction:nil];
		return;
	}

	NSString *action = self.actionIds[index];
	if ([action isEqualToString:TGMessageActionDeleteRow]){
		[self confirmDeleteForMe:self.canDeleteForMe forEveryone:self.canDeleteForEveryone];
		return;
	}
	if ([action isEqualToString:TGMessageActionDeleteForMe]){
		[self confirmDeleteForMe:YES forEveryone:NO];
		return;
	}
	if ([action isEqualToString:TGMessageActionDeleteForEveryone]){
		[self confirmDeleteForMe:NO forEveryone:YES];
		return;
	}
	[self finishWithAction:action];
}

- (void)confirmDeleteForMe:(BOOL)forMe forEveryone:(BOOL)forEveryone {
	UIView *host = self.hostView;
	if (host == nil){
		[self finishWithAction:nil];
		return;
	}

	NSMutableArray *actions = [[NSMutableArray alloc] init];
	if (forEveryone)
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:@"Delete for Everyone"
															   action:TGMessageActionDeleteForEveryone
																 type:TGActionSheetActionTypeDestructive]];
	if (forMe)
		[actions addObject:[[TGActionSheetAction alloc] initWithTitle:
								(forEveryone ? @"Delete for Me" : @"Delete")
															   action:TGMessageActionDeleteForMe
																 type:forEveryone ? TGActionSheetActionTypeGeneric : TGActionSheetActionTypeDestructive]];

	if (actions.count == 0){
		[self finishWithAction:nil];
		return;
	}

	self.confirming = YES;
	__weak typeof(self) weakSelf = self;
	self.currentActionSheet = [[TGActionSheet alloc] initWithTitle:nil actions:actions
			actionBlock:^(__unused id target, NSString *action){
				__strong typeof(weakSelf) strongSelf = weakSelf;
				strongSelf.currentActionSheet = nil;
				strongSelf.confirming = NO;
				if ([action isEqualToString:TGMessageActionDeleteForEveryone] ||
					[action isEqualToString:TGMessageActionDeleteForMe])
					[strongSelf finishWithAction:action];
				else
					[strongSelf finishWithAction:nil];
			} target:self];
	[self.currentActionSheet showInView:(host.window != nil ? host.window : host)];
}

#pragma mark - states

- (void)reportUnavailable {
	TGAlertView *alert = [[TGAlertView alloc] initWithTitle:@"Telegram"
													message:@"This message is no longer available."
										  cancelButtonTitle:nil
											  okButtonTitle:@"OK"
											completionBlock:nil];
	[alert show];
	[self finishWithAction:nil];
}

- (void)finishWithAction:(NSString *)action {
	if (self.finished)
		return;
	self.finished = YES;
	[self stopDismissalWatch];

	void (^block)(NSString *) = self.completion;
	self.completion = nil;
	self.actionIds = nil;
	if (block)
		block(action);
}

- (void)dismiss {
	[TGPopupMenu dismiss];
	if (self.currentActionSheet){
		[self.currentActionSheet dismissWithClickedButtonIndex:
				self.currentActionSheet.cancelButtonIndex animated:NO];
		self.currentActionSheet = nil;
	}
	self.confirming = NO;
	self.presenting = NO;
	[self finishWithAction:nil];
}

@end

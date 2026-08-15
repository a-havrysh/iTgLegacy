//
// TGProfileCompanion - owns the data behind one profile screen.
//
// One peer, one companion, one screen. The screen asks the companion for
// finished model objects and is told what changed; it never calls TGClient and
// never sees a TDLib dictionary.
//
// Not a singleton. Create it with the peer, set the delegate, call -reload.
//
#import <Foundation/Foundation.h>

@class TGUserModel;
@class TGChatModel;
@class TGProfileCompanion;

#pragma mark - states

/// Where one area of the profile is in its life. A screen shows a spinner for
/// Loading, a placeholder for Empty and a retry for Failed instead of guessing
/// from an empty array.
typedef enum {
	TGProfileLoadStateIdle = 0,
	TGProfileLoadStateLoading,
	TGProfileLoadStateLoaded,
	TGProfileLoadStateEmpty,
	TGProfileLoadStateFailed
} TGProfileLoadState;

/// The independently-loading areas of a profile. Passed to the delegate so a
/// screen can reload one section rather than the whole table.
typedef enum {
	TGProfileSectionIdentity = 0,
	TGProfileSectionDetails,
	TGProfileSectionMedia,
	TGProfileSectionMembers,
	TGProfileSectionManagement,
	TGProfileSectionCommonGroups
} TGProfileSection;

#pragma mark - delegate

@protocol TGProfileCompanionDelegate <NSObject>
@optional

/// One area finished loading, or its content changed. The screen re-reads that
/// area's properties and reloads only its own rows.
- (void)profileCompanion:(TGProfileCompanion *)companion
	   didUpdateSection:(TGProfileSection)section;

/// The member list changed in place. Both arrays hold NSNumber row indexes into
/// -members as it reads *after* the change for insertions, and as it read
/// *before* for removals. Either may be empty. A screen that implements this
/// should animate rather than reload; if it is not implemented the companion
/// falls back to -profileCompanion:didUpdateSection: with
/// TGProfileSectionMembers.
- (void)profileCompanion:(TGProfileCompanion *)companion
	didInsertMemberRows:(NSArray *)insertedIndexes
		 removeMemberRows:(NSArray *)removedIndexes;

/// A load failed. `section` says which area, `message` is a short user-facing
/// line, and may be nil.
- (void)profileCompanion:(TGProfileCompanion *)companion
		didFailSection:(TGProfileSection)section
			   message:(NSString *)message;

@end

#pragma mark - companion

@interface TGProfileCompanion : NSObject

/// Private-chat profile. `userId` must not be 0. `chatId` may be 0 when the
/// private chat has not been opened yet; pass it when it is known, because the
/// shared-media counts and the mute switch need it.
- (id)initWithUserId:(int64_t)userId chatId:(int64_t)chatId;

/// Group or channel profile. `chatId` must not be 0.
- (id)initWithChatId:(int64_t)chatId;

@property (nonatomic, assign) id<TGProfileCompanionDelegate> delegate;

#pragma mark - peer

@property (nonatomic, readonly) int64_t userId;
@property (nonatomic, readonly) int64_t chatId;
/// YES for a private-chat profile, i.e. userId != 0.
@property (nonatomic, readonly) BOOL isUserProfile;

#pragma mark - lifecycle

/// Start every load this peer needs. Safe to call again: it refreshes.
- (void)reload;

/// Refresh only what the screen returning to the foreground can have missed:
/// the mute flag, the status line, the management flags.
- (void)refreshVolatile;

/// Stop every in-flight callback from reaching the delegate. Call from the
/// screen's -dealloc; the companion also does it itself.
- (void)cancel;

/// Drop everything a screen can rebuild by asking again: members, common
/// groups, gifts. Scalars and the identity survive, so the header does not go
/// blank on a memory warning. Called automatically on
/// UIApplicationDidReceiveMemoryWarningNotification.
- (void)purgeCaches;

#pragma mark - state

/// The state of the profile as a whole: Loaded once the identity is known.
@property (nonatomic, readonly) TGProfileLoadState state;
- (TGProfileLoadState)stateForSection:(TGProfileSection)section;

#pragma mark - identity

/// The peer as a user. Nil for a group profile, and nil until the first load
/// answers.
@property (nonatomic, readonly, strong) TGUserModel *user;

/// Name to show in the header: the user's display name, or the group title.
/// Optional until loaded.
@property (nonatomic, readonly, copy) NSString *displayName;

/// Small profile photo file id to download, or 0 when the peer has none.
@property (nonatomic, readonly) NSInteger photoFileId;

/// Whether the chat is muted. Meaningful only when chatId != 0.
@property (nonatomic, readonly) BOOL muted;

#pragma mark - user detail

/// userFullInfo bio, or nil.
@property (nonatomic, readonly, copy) NSString *bio;
/// Birthday already formatted by TGClient, or nil.
@property (nonatomic, readonly, copy) NSString *birthdayText;
/// The private note about this contact, or nil. -noteLoaded distinguishes
/// "no note" from "not asked yet", which is what decides whether the screen
/// offers an "Add note" row.
@property (nonatomic, readonly, copy) NSString *note;
@property (nonatomic, readonly) BOOL noteLoaded;
/// Digits only, no leading "+". Nil when the number is hidden.
@property (nonatomic, readonly, copy) NSString *phoneNumber;
/// The first active username, without "@". Optional.
@property (nonatomic, readonly, copy) NSString *username;
/// "Close friend", "Mutual contact", "Telegram support", or nil.
@property (nonatomic, readonly, copy) NSString *contactRelation;
@property (nonatomic, readonly) BOOL isContact;
@property (nonatomic, readonly) BOOL isBlocked;
@property (nonatomic, readonly) BOOL blockedKnown;

#pragma mark - common groups

/// TGChatModel objects. Empty until loaded, and again after -purgeCaches.
@property (nonatomic, readonly, strong) NSArray *commonGroups;
/// The count to show. Uses the loaded list when there is one and the number
/// userFullInfo reported before that, so the row does not appear and jump.
@property (nonatomic, readonly) NSInteger commonGroupCount;

#pragma mark - gifts

/// Raw gift entries as TGClient vends them, pending a TGGiftModel. Empty until
/// loaded.
@property (nonatomic, readonly, strong) NSArray *gifts;

#pragma mark - shared media

/// Number of photo/video messages in the chat, and of documents. Valid only
/// once the matching state is Loaded; 0 before that.
@property (nonatomic, readonly) NSInteger photoCount;
@property (nonatomic, readonly) NSInteger fileCount;

#pragma mark - group detail

/// Group or channel title. Optional until loaded.
@property (nonatomic, readonly, copy) NSString *title;
/// The "about" text of a group or channel, or nil.
@property (nonatomic, readonly, copy) NSString *chatDescription;
/// The primary invite link, or nil. `primaryLinkJoinCount` is how many members
/// joined through it.
@property (nonatomic, readonly, copy) NSString *primaryInviteLink;
@property (nonatomic, readonly) NSInteger primaryLinkJoinCount;

/// TGMemberModel objects. Empty until loaded, and again after -purgeCaches.
@property (nonatomic, readonly, strong) NSArray *members;

@property (nonatomic, readonly) NSInteger memberCount;
@property (nonatomic, readonly) NSInteger adminCount;
@property (nonatomic, readonly) NSInteger inviteLinkCount;
@property (nonatomic, readonly) NSInteger pendingJoinRequests;
@property (nonatomic, readonly) NSInteger onlineCount;

#pragma mark - management

/// YES once the management block has an answer, valid or defaulted. Every flag
/// below is meaningless before that.
@property (nonatomic, readonly) BOOL managementLoaded;
/// YES once the second, more detailed management pass answered - the one that
/// carries protected content and anti-spam.
@property (nonatomic, readonly) BOOL managementFlagsLoaded;

@property (nonatomic, readonly) BOOL isChannel;
@property (nonatomic, readonly) BOOL isSupergroup;
@property (nonatomic, readonly) BOOL isForum;
/// This account is creator or administrator.
@property (nonatomic, readonly) BOOL isAdmin;
/// This account may change the title, photo and description.
@property (nonatomic, readonly) BOOL canEditChat;
/// The member list may be shown at all.
@property (nonatomic, readonly) BOOL canListMembers;
@property (nonatomic, readonly) BOOL canGetStatistics;

@property (nonatomic, readonly) NSInteger slowModeDelay;
@property (nonatomic, readonly) BOOL historyAvailable;
@property (nonatomic, readonly) BOOL hiddenMembers;
@property (nonatomic, readonly) BOOL canHideMembers;
@property (nonatomic, readonly) BOOL antiSpam;
@property (nonatomic, readonly) BOOL canToggleAntiSpam;
@property (nonatomic, readonly) BOOL protectedContent;

/// Channel signing. `signaturesLoaded` gates both flags.
@property (nonatomic, readonly) BOOL signaturesLoaded;
@property (nonatomic, readonly) BOOL signMessages;
@property (nonatomic, readonly) BOOL showAuthorProfiles;

/// Linked discussion group of a channel. `discussionLoaded` gates both; a
/// chatId of 0 means there is none.
@property (nonatomic, readonly) BOOL discussionLoaded;
@property (nonatomic, readonly) int64_t discussionChatId;
@property (nonatomic, readonly, copy) NSString *discussionTitle;

/// Boost level of a channel or supergroup. `boostsLoaded` gates it.
@property (nonatomic, readonly) BOOL boostsLoaded;
@property (nonatomic, readonly) NSInteger boostLevel;

#pragma mark - writes

/// The few mutations that belong to the profile itself rather than to a modal
/// the screen pushes. Each one applies locally, tells the server, and notifies
/// the delegate for the affected section.
- (void)setMuted:(BOOL)muted;
- (void)setBlocked:(BOOL)blocked;
- (void)setNoteText:(NSString *)text;

@end

//
// TGMemberModel - one member of a group, as the member screens need them.
//
// Built from the flattened member dictionaries TGClient (Groups) vends:
// -membersInGroup:filter:offset:limit:, -searchMembersInGroup:query:filter:limit:,
// -bannedMembersInGroup:limit:, -memberStatusOfUser:inGroup: and
// -administratorsInGroup: (which carries only id/name/customTitle/isOwner/
// canBeEdited - the rest defaults).
//
// Immutable. A screen reads properties, never subscripts.
//
#import <Foundation/Foundation.h>

#pragma mark - status

/// The member status strings TGClient uses, as a value a switch can take.
typedef enum {
	TGMemberStatusLeft = 0,
	TGMemberStatusMember,
	TGMemberStatusAdministrator,
	TGMemberStatusCreator,
	TGMemberStatusRestricted,
	TGMemberStatusBanned
} TGMemberStatus;

/// "creator", "administrator", "member", "restricted", "banned", "left".
/// Anything unknown maps to TGMemberStatusLeft, which is what TGClient does.
extern TGMemberStatus TGMemberStatusFromString(NSString *string);
/// The string TGClient uses for a status; never nil.
extern NSString *TGMemberStatusToString(TGMemberStatus status);

#pragma mark - rights

/// The chatAdministratorRights booleans of one member, or the chatPermissions
/// booleans of one member, as a small immutable object.
///
/// Both key sets are read the same way: a flag is either present and true, or
/// it is off. Nothing here is optional - a missing key means NO.
@interface TGMemberRightsModel : NSObject {
@private
	NSSet *_grantedKeys;
}

/// Whether one right is granted. `key` is a TDLib key such as
/// "can_delete_messages" or "can_send_photos". An unknown key answers NO, so a
/// switch list may ask for every key it lists without guarding.
- (BOOL)isGranted:(NSString *)key;

/// YES when nothing at all is granted, i.e. the member is not an administrator
/// / carries no individual restrictions.
@property (nonatomic, readonly) BOOL isEmpty;

#pragma mark administrator rights

@property (nonatomic, readonly) BOOL canManageChat;
@property (nonatomic, readonly) BOOL canChangeInfo;
@property (nonatomic, readonly) BOOL canPostMessages;
@property (nonatomic, readonly) BOOL canEditMessages;
@property (nonatomic, readonly) BOOL canDeleteMessages;
@property (nonatomic, readonly) BOOL canInviteUsers;
@property (nonatomic, readonly) BOOL canRestrictMembers;
@property (nonatomic, readonly) BOOL canPinMessages;
@property (nonatomic, readonly) BOOL canManageTopics;
@property (nonatomic, readonly) BOOL canPromoteMembers;
@property (nonatomic, readonly) BOOL canManageVideoChats;
@property (nonatomic, readonly) BOOL isAnonymous;

#pragma mark member permissions

@property (nonatomic, readonly) BOOL canSendBasicMessages;
@property (nonatomic, readonly) BOOL canSendMedia;
@property (nonatomic, readonly) BOOL canSendPolls;
@property (nonatomic, readonly) BOOL canSendOtherMessages;
@property (nonatomic, readonly) BOOL canAddLinkPreviews;

/// Build from a dictionary of NSNumber booleans keyed by TDLib right names -
/// exactly what TGClient puts under "rights" and "permissions". Returns an
/// empty rights object for nil or a non-dictionary, never nil, because "no
/// rights" is the correct reading of "no dictionary".
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// The keys this object holds as granted. Useful when handing the set straight
/// back to -promoteMember:... or -restrictMember:...
- (NSArray *)grantedKeys;

@end

#pragma mark - member

@interface TGMemberModel : NSObject {
@private
	int64_t _userId;
	NSString *_name;
	TGMemberStatus _status;
	NSString *_customTitle;
	BOOL _isOwner;
	BOOL _isAdmin;
	BOOL _canBeEdited;
	NSInteger _untilDate;
	int64_t _inviterUserId;
	NSInteger _joinedDate;
	TGMemberRightsModel *_rights;
	TGMemberRightsModel *_permissions;
}

/// The user id. Never 0 for a model that was built at all.
@property (nonatomic, readonly) int64_t userId;

/// Display name as TGClient resolved it. Optional: nil when the user record
/// was not cached yet, in which case the screen should show its own placeholder
/// rather than an empty row.
@property (nonatomic, readonly, copy) NSString *name;

/// Membership status.
@property (nonatomic, readonly) TGMemberStatus status;

/// The same status as the string TGClient vends, for code that compares text.
@property (nonatomic, readonly, copy) NSString *statusString;

/// The administrator's custom title ("owner", "founder", ...). Optional: nil
/// when there is none, never @"".
@property (nonatomic, readonly, copy) NSString *customTitle;

/// The member created the group.
@property (nonatomic, readonly) BOOL isOwner;

/// Creator or administrator.
@property (nonatomic, readonly) BOOL isAdmin;

/// This account may change this member's status. NO means a read-only editor.
@property (nonatomic, readonly) BOOL canBeEdited;

/// Unix time the ban / restriction / temporary membership lifts. 0 means
/// forever, and also means "not applicable" for an ordinary member.
@property (nonatomic, readonly) NSInteger untilDate;

/// YES when a restriction or ban expires by itself, i.e. untilDate > 0.
@property (nonatomic, readonly) BOOL expires;

/// Who added them. Optional: 0 when the server did not say.
@property (nonatomic, readonly) int64_t inviterUserId;

/// Unix time they joined. Optional: 0 when the server did not say.
@property (nonatomic, readonly) NSInteger joinedDate;

/// Administrator rights. Never nil; empty for a non-administrator.
@property (nonatomic, readonly, strong) TGMemberRightsModel *rights;

/// This member's individual restrictions. Never nil; empty unless the member
/// is individually restricted.
@property (nonatomic, readonly, strong) TGMemberRightsModel *permissions;

/// Build from one entry of TGClient's member arrays. Returns nil for a
/// non-dictionary or an entry without a usable user id.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Map an array of such entries, dropping any that fail to build. Returns an
/// empty array for nil or a non-array, never nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

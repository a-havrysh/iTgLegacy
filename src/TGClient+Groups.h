//
// TGClient+Groups - basic groups, supergroups, members, admins, banned users.
//
// Everything here works on a chat id, never on a raw basic-group or
// supergroup id: the category resolves the underlying group itself, so the UI
// layer only ever holds the chat id it already shows in the list.
//
// Every completion runs on the main queue and may be nil. Failures answer
// nil / NO / an empty array rather than raising.
//
#import "TGClient.h"

@interface TGClient (Groups)

#pragma mark - creating groups

/// Create a basic group with `userIds` and open it. `completion` gets the new
/// chat id (0 on failure) and the user ids that could not be added, which the
/// caller should surface as "X could not be added" rather than treat as an
/// error - the group itself exists either way.
- (void)createBasicGroupWithTitle:(NSString *)title
                          userIds:(NSArray *)userIds
                       completion:(void (^)(int64_t chatId, NSArray *failedUserIds))completion;

/// Create a supergroup or a channel. `description` may be nil.
/// `completion` gets the new chat id, or 0.
- (void)createSupergroupWithTitle:(NSString *)title
                      description:(NSString *)description
                        isChannel:(BOOL)isChannel
                          isForum:(BOOL)isForum
                       completion:(void (^)(int64_t chatId))completion;

/// Convert a basic group into a supergroup. The chat id changes, so an open
/// chat screen must be reopened with the id the completion carries (0 on
/// failure). One-way; there is no downgrade.
- (void)upgradeBasicGroupToSupergroup:(int64_t)chatId
                           completion:(void (^)(int64_t newChatId))completion;

#pragma mark - group info

/// Everything the group info screen needs, flattened from basicGroupFullInfo /
/// supergroupFullInfo plus the chat and the supergroup record. Keys:
/// "id" (chat id), "title", "description", "isSupergroup", "isChannel",
/// "isForum", "isBroadcastGroup", "memberCount", "adminCount",
/// "restrictedCount", "bannedCount", "slowModeDelay", "username" (empty when
/// private), "inviteLink", "linkedChatId", "stickerSetId" (NSNumber, 0 when
/// none), "isAllHistoryAvailable", "hasHiddenMembers", "canHideMembers",
/// "hasAggressiveAntiSpam", "canToggleAggressiveAntiSpam", "canSetStickerSet",
/// "canGetMembers", "pendingJoinRequests", "myStatus" (see -memberStatusOf:),
/// "canBeEdited" (we may change title/photo/description),
/// "upgradedFromBasicGroup". Nil for a chat that is not a group.
- (void)groupInfoForChat:(int64_t)chatId
              completion:(void (^)(NSDictionary *info))completion;

/// Rename a group. `completion` says whether the server accepted it.
- (void)setGroupChat:(int64_t)chatId title:(NSString *)title
          completion:(void (^)(BOOL ok))completion;

/// Set the "about" text of a group or channel.
- (void)setGroupChat:(int64_t)chatId description:(NSString *)description
          completion:(void (^)(BOOL ok))completion;

/// Replace the group photo with a local image file. Pass nil to remove it.
- (void)setGroupChat:(int64_t)chatId photoAtPath:(NSString *)path
          completion:(void (^)(BOOL ok))completion;

#pragma mark - members

/// Members of a group. `filter` is one of "recent", "administrators",
/// "restricted", "banned", "bots", "contacts"; nil means "recent".
/// Basic groups have no server-side paging or filters, so for them the whole
/// member list is returned and only "administrators" and "bots" are honoured.
/// Each entry: "id" (user id), "name", "status" ("creator", "administrator",
/// "member", "restricted", "left", "banned"), "customTitle", "isOwner",
/// "isAdmin", "untilDate" (NSNumber, 0 = forever), "inviterUserId",
/// "joinedDate", "canBeEdited".
- (void)membersInGroup:(int64_t)chatId
                filter:(NSString *)filter
                offset:(NSInteger)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *members, NSInteger totalCount))completion;

/// Search inside a group's member list. Same entry shape as -membersInGroup:.
/// `filter` is one of "members", "administrators", "restricted", "banned",
/// "bots", "contacts", or nil for all members.
- (void)searchMembersInGroup:(int64_t)chatId
                       query:(NSString *)query
                      filter:(NSString *)filter
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *members))completion;

/// One member's record, same shape as an entry of -membersInGroup:, or nil.
- (void)memberStatusOfUser:(int64_t)userId
                   inGroup:(int64_t)chatId
                completion:(void (^)(NSDictionary *member))completion;

/// Number of members in a group; 0 for anything else.
- (void)groupMemberCount:(int64_t)chatId
              completion:(void (^)(NSInteger count))completion;

/// Add users to a group. `completion` gets the user ids that were refused
/// (privacy settings, usually); an empty array means everyone got in.
- (void)addMembers:(NSArray *)userIds
           toGroup:(int64_t)chatId
        completion:(void (^)(NSArray *failedUserIds))completion;

/// Remove a member without banning them: they can rejoin or be re-added.
- (void)removeMember:(int64_t)userId
           fromGroup:(int64_t)chatId
          completion:(void (^)(BOOL ok))completion;

/// Ban a member. `untilDate` is a unix time, 0 for forever. When
/// `revokeMessages` is YES their messages are deleted as well.
- (void)banMember:(int64_t)userId
          inGroup:(int64_t)chatId
        untilDate:(NSInteger)untilDate
   revokeMessages:(BOOL)revokeMessages
       completion:(void (^)(BOOL ok))completion;

/// Lift a ban - the user becomes "left" and may rejoin.
- (void)unbanMember:(int64_t)userId
            inGroup:(int64_t)chatId
         completion:(void (^)(BOOL ok))completion;

/// The "Removed Users" list. Same entry shape as -membersInGroup:.
- (void)bannedMembersInGroup:(int64_t)chatId
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *members))completion;

/// Delete every message a user ever sent in a supergroup.
- (void)deleteAllMessagesFromUser:(int64_t)userId inGroup:(int64_t)chatId;

/// Restrict a member. `permissions` is a dictionary of TDLib chatPermissions
/// booleans ("can_send_basic_messages", "can_send_photos", "can_send_polls",
/// "can_send_other_messages", "can_add_link_previews", "can_change_info",
/// "can_invite_users", "can_pin_messages", ...); anything left out is denied.
/// `untilDate` is a unix time, 0 for forever.
- (void)restrictMember:(int64_t)userId
               inGroup:(int64_t)chatId
           permissions:(NSDictionary *)permissions
             untilDate:(NSInteger)untilDate
            completion:(void (^)(BOOL ok))completion;

#pragma mark - administrators

/// The administrators list, creator first. Each entry: "id", "name",
/// "customTitle", "isOwner", "canBeEdited".
- (void)administratorsInGroup:(int64_t)chatId
                   completion:(void (^)(NSArray *admins))completion;

/// Promote a member. `rights` is a dictionary of TDLib chatAdministratorRights
/// booleans ("can_manage_chat", "can_change_info", "can_delete_messages",
/// "can_invite_users", "can_restrict_members", "can_pin_messages",
/// "can_promote_members", "can_manage_video_chats", "can_manage_topics",
/// "is_anonymous", and for channels "can_post_messages"/"can_edit_messages");
/// omitted rights are withheld. `customTitle` may be nil, and is accepted but
/// not sent: this TDLib schema carries the custom title on chatMember.tag,
/// which setChatMemberStatus does not take, so the field is read-only for us.
- (void)promoteMember:(int64_t)userId
              inGroup:(int64_t)chatId
               rights:(NSDictionary *)rights
          customTitle:(NSString *)customTitle
           completion:(void (^)(BOOL ok))completion;

/// Demote an administrator back to an ordinary member.
- (void)dismissAdmin:(int64_t)userId
             inGroup:(int64_t)chatId
          completion:(void (^)(BOOL ok))completion;

/// Hand the group over. Needs the account's 2FA password; `completion` is NO
/// when the password is wrong or the transfer is refused.
- (void)transferOwnershipOfGroup:(int64_t)chatId
                          toUser:(int64_t)userId
                        password:(NSString *)password
                      completion:(void (^)(BOOL ok))completion;

#pragma mark - default permissions

/// What ordinary members of the group may do: a dictionary of the TDLib
/// chatPermissions boolean fields, as NSNumbers.
- (void)defaultPermissionsInGroup:(int64_t)chatId
                       completion:(void (^)(NSDictionary *permissions))completion;

/// Replace the default permissions. Same key set; missing keys mean "off".
- (void)setDefaultPermissions:(NSDictionary *)permissions
                      inGroup:(int64_t)chatId
                   completion:(void (^)(BOOL ok))completion;

#pragma mark - public groups

/// Ask the server whether a username can be taken for this group.
/// `status` is "ok", "invalid", "occupied", "purchasable", "too-many"
/// (this account already has the maximum number of public chats),
/// "unavailable", or "error".
- (void)checkGroupUsername:(NSString *)username
                   forChat:(int64_t)chatId
                completion:(void (^)(NSString *status))completion;

/// Make a supergroup public under `username`, or pass nil/@"" to make it
/// private again (which also drops the t.me/username link).
- (void)setGroupChat:(int64_t)chatId username:(NSString *)username
          completion:(void (^)(BOOL ok))completion;

/// Turn one of a supergroup's usernames on or off without losing it.
- (void)setGroupChat:(int64_t)chatId username:(NSString *)username
             active:(BOOL)active
          completion:(void (^)(BOOL ok))completion;

/// Public chats this account has created, for the "too many public groups"
/// screen. Each entry: "id", "title".
- (void)createdPublicChatsWithCompletion:(void (^)(NSArray *chats))completion;

#pragma mark - invite links

/// Flattened chatInviteLink keys used below: "link", "name", "creatorUserId",
/// "date", "expirationDate", "memberLimit", "memberCount",
/// "pendingJoinRequestCount", "createsJoinRequest", "isPrimary", "isRevoked".

/// The group's primary t.me invite link, creating it if the group has none.
- (void)primaryInviteLinkForGroup:(int64_t)chatId
                       completion:(void (^)(NSDictionary *link))completion;

/// Revoke the primary link and get the replacement. The old link stops
/// working immediately.
- (void)replacePrimaryInviteLinkForGroup:(int64_t)chatId
                              completion:(void (^)(NSDictionary *link))completion;

/// Create an extra invite link. `name` may be nil, `expirationDate` is a unix
/// time (0 = never), `memberLimit` 0 = unlimited.
- (void)createInviteLinkInGroup:(int64_t)chatId
                           name:(NSString *)name
                 expirationDate:(NSInteger)expirationDate
                    memberLimit:(NSInteger)memberLimit
             createsJoinRequest:(BOOL)createsJoinRequest
                     completion:(void (^)(NSDictionary *link))completion;

/// Change an existing link's settings; the URL itself does not change.
- (void)editInviteLink:(NSString *)inviteLink
               inGroup:(int64_t)chatId
                  name:(NSString *)name
        expirationDate:(NSInteger)expirationDate
           memberLimit:(NSInteger)memberLimit
    createsJoinRequest:(BOOL)createsJoinRequest
            completion:(void (^)(NSDictionary *link))completion;

/// Invite links of this group, either the live ones or the revoked ones.
- (void)inviteLinksInGroup:(int64_t)chatId
                   revoked:(BOOL)revoked
                     limit:(NSInteger)limit
                completion:(void (^)(NSArray *links))completion;

/// Kill one link. `completion` gets the link in its revoked state, or nil.
- (void)revokeInviteLink:(NSString *)inviteLink
                 inGroup:(int64_t)chatId
              completion:(void (^)(NSDictionary *link))completion;

/// Forget a revoked link entirely.
- (void)deleteRevokedInviteLink:(NSString *)inviteLink inGroup:(int64_t)chatId;

/// Who joined through one link. Each entry: "id", "name", "joinedDate",
/// "approverUserId".
- (void)membersJoinedViaInviteLink:(NSString *)inviteLink
                           inGroup:(int64_t)chatId
                             limit:(NSInteger)limit
                        completion:(void (^)(NSArray *members))completion;

/// How many links each administrator of the group has made. Each entry:
/// "id", "name", "linkCount", "revokedLinkCount".
- (void)inviteLinkCountsInGroup:(int64_t)chatId
                     completion:(void (^)(NSArray *counts))completion;

#pragma mark - joining

/// Look at a t.me invite link without joining, for the preview alert.
/// Keys: "chatId" (0 when we are not a member yet), "title", "photoFileId"
/// (NSNumber or nil), "description", "memberCount", "isChannel",
/// "createsJoinRequest", "isPublic". Nil when the link is dead.
- (void)previewGroupInviteLink:(NSString *)inviteLink
                    completion:(void (^)(NSDictionary *info))completion;

/// Join through an invite link. `chatId` is the chat to open, 0 when the
/// group only took a join request - `requestSent` is YES in that case.
- (void)joinGroupByInviteLink:(NSString *)inviteLink
                   completion:(void (^)(int64_t chatId, BOOL requestSent))completion;

/// Pending join requests. Each entry: "id" (user id), "name", "bio", "date".
- (void)joinRequestsInGroup:(int64_t)chatId
                      limit:(NSInteger)limit
                 completion:(void (^)(NSArray *requests, NSInteger totalCount))completion;

/// Approve or dismiss one pending request.
- (void)processJoinRequestFromUser:(int64_t)userId
                           inGroup:(int64_t)chatId
                           approve:(BOOL)approve
                        completion:(void (^)(BOOL ok))completion;

/// Approve or dismiss every pending request at once.
- (void)processAllJoinRequestsInGroup:(int64_t)chatId
                              approve:(BOOL)approve
                           completion:(void (^)(BOOL ok))completion;

#pragma mark - group settings

/// Members may only post once every `seconds`; 0 turns slow mode off.
/// Telegram only accepts 0, 10, 30, 60, 300, 900 and 3600.
- (void)setGroup:(int64_t)chatId slowModeDelay:(NSInteger)seconds
      completion:(void (^)(BOOL ok))completion;

/// Whether people who join later can read the messages sent before they did.
- (void)setGroup:(int64_t)chatId allHistoryAvailable:(BOOL)available
      completion:(void (^)(BOOL ok))completion;

/// Hide the member list from ordinary members. Only allowed when the group
/// info reports "canHideMembers".
- (void)setGroup:(int64_t)chatId hiddenMembers:(BOOL)hidden
      completion:(void (^)(BOOL ok))completion;

/// Server-side spam filtering for large groups.
- (void)setGroup:(int64_t)chatId aggressiveAntiSpam:(BOOL)enabled
      completion:(void (^)(BOOL ok))completion;

/// Report messages to the anti-spam checker as wrongly-classified spam.
- (void)reportSpamMessages:(NSArray *)messageIds inGroup:(int64_t)chatId;

/// Stop members from forwarding or saving what is posted here.
- (void)setGroup:(int64_t)chatId protectedContent:(BOOL)protectedContent;

/// Channels only: append the author's name to each post.
- (void)setGroup:(int64_t)chatId signMessages:(BOOL)sign
      completion:(void (^)(BOOL ok))completion;

/// Require joining before writing, and/or make joining need approval.
- (void)setGroup:(int64_t)chatId joinToSend:(BOOL)joinToSend
     joinByRequest:(BOOL)joinByRequest
      completion:(void (^)(BOOL ok))completion;

/// Turn topic mode on or off for a supergroup.
- (void)setGroup:(int64_t)chatId isForum:(BOOL)isForum
      completion:(void (^)(BOOL ok))completion;

/// Convert a supergroup into a broadcast group. One-way and irreversible.
- (void)convertGroupToBroadcastGroup:(int64_t)chatId
                          completion:(void (^)(BOOL ok))completion;

/// The group's sticker set, by set name (the part after t.me/addstickers/).
/// Pass nil to remove it. `completion` is NO when there is no such set.
- (void)setGroup:(int64_t)chatId stickerSetName:(NSString *)name
      completion:(void (^)(BOOL ok))completion;

/// Groups this account could attach to a channel as its discussion group.
/// Each entry: "id", "title".
- (void)suitableDiscussionGroupsWithCompletion:(void (^)(NSArray *chats))completion;

/// Link a discussion group to a channel; pass 0 to unlink.
- (void)setChannel:(int64_t)channelChatId discussionGroup:(int64_t)groupChatId
        completion:(void (^)(BOOL ok))completion;

#pragma mark - recent actions

/// The admin event log ("Recent Actions"). Each entry: "id" (NSString, the
/// event id, which is an int64 and would not survive as a plain number),
/// "date", "userId", "name", "action" (the TDLib action type with the
/// "chatEvent" prefix stripped, e.g. "MemberPromoted", "TitleChanged") and
/// "raw" (the full action object, for actions the UI wants to detail).
/// `query` may be nil.
- (void)eventLogForGroup:(int64_t)chatId
                   query:(NSString *)query
                   limit:(NSInteger)limit
              completion:(void (^)(NSArray *events))completion;

#pragma mark - reporting

/// Report a group. Telegram drives this as a small wizard: call with a nil
/// `optionId` first, and `completion` answers with what to do next.
/// `status` is "ok" (accepted, done), "options" (show `title` and `options`,
/// each an entry with "id" and "text", then call again with that id),
/// "text" (ask for free text and call again with the same option id, `optional`
/// says whether it may be empty) or "error".
- (void)reportGroup:(int64_t)chatId
           optionId:(NSString *)optionId
               text:(NSString *)text
         completion:(void (^)(NSString *status, NSString *title, NSArray *options, BOOL optional))completion;

@end

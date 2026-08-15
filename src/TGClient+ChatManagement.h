//
// TGClient+ChatManagement - group and channel administration.
//
// Everything a chat's owner or admin can change about the chat itself:
// its title, description and photo, the default member permissions, slow
// mode, the supergroup switches (history visibility, join by request,
// signatures, content protection, anti-spam), invite links, the join
// request inbox and the recent-actions event log.
//
// Every method takes a chat_id, never a supergroup id: the category
// resolves the supergroup behind a chat itself, so the UI never has to.
// Completions run on the main queue and may be nil. Anything that reports
// success answers NO when TDLib refused the call, which for this area
// almost always means the user lacks the right.
//
#import "TGClient.h"

@interface TGClient (ChatManagement)

#pragma mark - title, description, photo

/// Rename a group or channel. `completion` gets YES when accepted.
- (void)setTitle:(NSString *)title forChat:(int64_t)chatId
      completion:(void (^)(BOOL ok))completion;

/// Change the About text of a group or channel. Pass @"" to clear it.
- (void)setDescription:(NSString *)description forChat:(int64_t)chatId
            completion:(void (^)(BOOL ok))completion;

/// Set the chat photo from a local image file (JPEG or PNG on disk).
/// TDLib uploads it; `completion` fires when the call was accepted, not
/// when the upload finished - the new photo arrives as a chat update.
- (void)setPhotoAtPath:(NSString *)path forChat:(int64_t)chatId
            completion:(void (^)(BOOL ok))completion;

/// Reuse a photo the chat had before, by the chatPhoto id TDLib gave it.
- (void)setPreviousPhotoId:(long long)photoId forChat:(int64_t)chatId
                completion:(void (^)(BOOL ok))completion;

/// Remove the chat photo entirely.
- (void)removePhotoForChat:(int64_t)chatId completion:(void (^)(BOOL ok))completion;

#pragma mark - management snapshot

/// Everything the group/channel management screens need, in one call.
/// Keys, all always present:
///   "isChannel", "isSupergroup", "isBasicGroup" (NSNumber BOOL)
///   "supergroupId" (NSNumber, 0 for a basic group)
///   "title", "description" (NSString)
///   "username" (NSString, "" when the chat is private)
///   "inviteLink" (NSString, the primary link, "" when there is none)
///   "members", "admins", "restricted", "banned" (NSNumber)
///   "slowModeDelay" (NSNumber, seconds, 0 = off)
///   "isAllHistoryAvailable", "hasHiddenMembers", "canHideMembers",
///   "hasAntiSpam", "canToggleAntiSpam", "hasProtectedContent",
///   "signMessages", "showMessageSender", "joinByRequest",
///   "joinToSendMessages", "isForum" (NSNumber BOOL)
///   "pendingJoinRequests" (NSNumber)
/// Answers a dictionary of defaults for a private chat rather than nil.
- (void)managementInfoForChat:(int64_t)chatId
                   completion:(void (^)(NSDictionary *info))completion;

#pragma mark - administrators and own rights

/// The administrators of a group or channel, owner first. Each entry:
///   "userId" (NSNumber), "name" (NSString, the display name),
///   "customTitle" (NSString, "" when there is none),
///   "isOwner", "canBeEdited" (NSNumber BOOL).
/// Answers an empty array for a private chat or when the user may not see
/// the list. Useful as the "by admin" narrowing of -eventLogForChat:,
/// whose `userIds` takes the "userId" values straight from here.
- (void)administratorsForChat:(int64_t)chatId
                   completion:(void (^)(NSArray *administrators))completion;

/// The signed-in user's own rights in a chat. Keys, all always present:
///   "isOwner", "isAdministrator", "isMember" (NSNumber BOOL),
///   "customTitle" (NSString),
///   plus one NSNumber BOOL per TDLib chatAdministratorRights field, in
///   the camel-cased spelling: "canManageChat", "canChangeInfo",
///   "canPostMessages", "canEditMessages", "canDeleteMessages",
///   "canInviteUsers", "canRestrictMembers", "canPinMessages",
///   "canManageTopics", "canPromoteMembers", "canManageVideoChats",
///   "canPostStories", "canEditStories", "canDeleteStories",
///   "isAnonymous".
/// An owner answers YES for every right. Never nil: a chat the call fails
/// on answers all NO.
- (void)myRightsInChat:(int64_t)chatId
            completion:(void (^)(NSDictionary *rights))completion;

/// Whether the signed-in user may create, edit and revoke invite links
/// here - owner, or an administrator with can_invite_users. A links screen
/// should hide its actions rather than let TDLib refuse them.
- (void)canManageInviteLinksInChat:(int64_t)chatId
                        completion:(void (^)(BOOL canManage))completion;

#pragma mark - permissions

/// Keys used by both permission methods. Each value is an NSNumber BOOL:
///   "sendMessages", "sendAudios", "sendDocuments", "sendPhotos",
///   "sendVideos", "sendVideoNotes", "sendVoiceNotes", "sendPolls",
///   "sendOther", "addLinkPreviews", "reactToMessages", "changeInfo",
///   "inviteUsers", "pinMessages", "createTopics".
/// The list above, in the order a permissions screen should show it.
+ (NSArray *)permissionKeys;

/// Default permissions of every ordinary member, in the shape above.
/// All keys are present; a chat that has no permissions answers all NO.
- (void)permissionsForChat:(int64_t)chatId
                completion:(void (^)(NSDictionary *permissions))completion;

/// Replace the default member permissions. Keys missing from the
/// dictionary are sent as NO, so pass the full set the switches show.
- (void)setPermissions:(NSDictionary *)permissions forChat:(int64_t)chatId
            completion:(void (^)(BOOL ok))completion;

#pragma mark - slow mode

/// Seconds a member must wait between messages. TDLib only accepts
/// 0, 10, 30, 60, 300, 900 and 3600; anything else is rounded down to
/// the nearest allowed value. 0 turns slow mode off.
- (void)setSlowModeDelay:(NSInteger)seconds forChat:(int64_t)chatId
              completion:(void (^)(BOOL ok))completion;

/// The presets a slow mode picker should offer, as NSNumbers of seconds.
+ (NSArray *)slowModePresets;

#pragma mark - supergroup switches

/// Whether new members can read the messages sent before they joined.
- (void)setChat:(int64_t)chatId allHistoryAvailable:(BOOL)available
     completion:(void (^)(BOOL ok))completion;

/// Whether joining needs an admin's approval. Applies to invite links too.
- (void)setChat:(int64_t)chatId joinByRequest:(BOOL)joinByRequest
     completion:(void (^)(BOOL ok))completion;

/// Whether a user must join the group before they may post in it.
- (void)setChat:(int64_t)chatId joinToSendMessages:(BOOL)joinToSend
     completion:(void (^)(BOOL ok))completion;

/// Channel signatures. `showSender` additionally links the author's profile
/// and is only meaningful while `sign` is YES.
- (void)setChat:(int64_t)chatId signMessages:(BOOL)sign showSender:(BOOL)showSender
     completion:(void (^)(BOOL ok))completion;

/// Forbid members from forwarding, saving or screenshotting content.
- (void)setChat:(int64_t)chatId protectedContent:(BOOL)protectedContent
     completion:(void (^)(BOOL ok))completion;

/// Hide the member list from ordinary members. Only allowed when the
/// management info says "canHideMembers".
- (void)setChat:(int64_t)chatId hiddenMembers:(BOOL)hidden
     completion:(void (^)(BOOL ok))completion;

/// Server-side aggressive spam filtering. Only allowed when the management
/// info says "canToggleAntiSpam".
- (void)setChat:(int64_t)chatId antiSpamEnabled:(BOOL)enabled
     completion:(void (^)(BOOL ok))completion;

/// Tell the server a message the anti-spam filter removed was not spam.
- (void)reportNotSpamMessages:(NSArray *)messageIds inChat:(int64_t)chatId
                   completion:(void (^)(BOOL ok))completion;

/// Report one aggressive-anti-spam deletion as a false positive. Only
/// meaningful for an event log row whose "canReportNotSpam" is YES; pass
/// that row's "messageId". Answers NO for a chat that is not a supergroup.
- (void)reportAntiSpamFalsePositiveForMessage:(int64_t)messageId
                                       inChat:(int64_t)chatId
                                   completion:(void (^)(BOOL ok))completion;

/// Turn a channel's discussion group into a broadcast group. Irreversible;
/// the caller must confirm with the user first.
- (void)convertChatToBroadcastGroup:(int64_t)chatId
                         completion:(void (^)(BOOL ok))completion;

#pragma mark - invite links

/// A flattened chatInviteLink, the shape every invite-link method returns:
///   "link" (NSString, the t.me URL), "name" (NSString),
///   "creatorId" (NSNumber user id), "date", "editDate",
///   "expirationDate" (NSNumber unix time, 0 = never),
///   "memberLimit" (NSNumber, 0 = unlimited), "memberCount",
///   "pendingRequests" (NSNumber),
///   "requiresApproval", "isPrimary", "isRevoked" (NSNumber BOOL).

/// The chat's primary invite link, or @"" when it has none.
- (void)primaryInviteLinkForChat:(int64_t)chatId
                      completion:(void (^)(NSString *link))completion;

/// Revoke the primary link and generate a new one. `completion` gets the
/// new link in the flattened shape above, or nil.
- (void)replacePrimaryInviteLinkForChat:(int64_t)chatId
                             completion:(void (^)(NSDictionary *link))completion;

/// All invite links the signed-in user created for a chat. `revoked` picks
/// the revoked section rather than the active one. `completion` gets an
/// array of flattened links, newest first.
- (void)inviteLinksForChat:(int64_t)chatId revoked:(BOOL)revoked
                completion:(void (^)(NSArray *links))completion;

/// How many links each other administrator made: "userId", "linkCount",
/// "revokedLinkCount".
- (void)inviteLinkCountsForChat:(int64_t)chatId
                     completion:(void (^)(NSArray *counts))completion;

/// Create a new invite link. `name` may be @"", `expirationDate` is a unix
/// time or 0 for never, `memberLimit` 0 for unlimited. A link that requires
/// approval cannot also have a member limit.
- (void)createInviteLinkForChat:(int64_t)chatId
                           name:(NSString *)name
                 expirationDate:(NSInteger)expirationDate
                    memberLimit:(NSInteger)memberLimit
               requiresApproval:(BOOL)requiresApproval
                     completion:(void (^)(NSDictionary *link))completion;

/// Change an existing link's name, expiry, limit or approval flag. Same
/// argument rules as -createInviteLinkForChat:.
- (void)editInviteLink:(NSString *)link
                inChat:(int64_t)chatId
                  name:(NSString *)name
        expirationDate:(NSInteger)expirationDate
           memberLimit:(NSInteger)memberLimit
      requiresApproval:(BOOL)requiresApproval
            completion:(void (^)(NSDictionary *link))completion;

/// One link on its own, in the flattened shape above, or nil when it is
/// gone. Use it to prefill an edit form with the link's current name,
/// expiry, member limit and approval flag.
- (void)inviteLink:(NSString *)link inChat:(int64_t)chatId
        completion:(void (^)(NSDictionary *info))completion;

/// Revoke a link. It stops working and moves to the revoked section.
- (void)revokeInviteLink:(NSString *)link inChat:(int64_t)chatId
              completion:(void (^)(BOOL ok))completion;

/// Delete a single revoked link, or every revoked link the user made.
- (void)deleteRevokedInviteLink:(NSString *)link inChat:(int64_t)chatId
                     completion:(void (^)(BOOL ok))completion;
- (void)deleteAllRevokedInviteLinksInChat:(int64_t)chatId
                               completion:(void (^)(BOOL ok))completion;

/// Who joined through one link: "userId", "name", "date" (NSNumber unix
/// time), "approverId". `total` is the full count, which can exceed the
/// page `limit`.
- (void)membersJoinedViaInviteLink:(NSString *)link
                            inChat:(int64_t)chatId
                             limit:(NSInteger)limit
                        completion:(void (^)(NSArray *members, NSInteger total))completion;

/// The same, for whichever link is the chat's primary one. Answers an
/// empty array when the chat has no primary link.
- (void)membersJoinedViaPrimaryInviteLinkInChat:(int64_t)chatId
                                          limit:(NSInteger)limit
                                     completion:(void (^)(NSArray *members, NSInteger total))completion;

#pragma mark - joining by link

/// Look at a t.me/+hash link without joining. `completion` gets nil for an
/// invalid or expired link, otherwise: "chatId" (NSNumber, 0 when the chat
/// is not known locally yet), "title", "description",
/// "photoFileId" (NSNumber or nil), "memberCount" (NSNumber),
/// "requiresApproval", "isPublic", "isChannel" (NSNumber BOOL).
- (void)previewInviteLink:(NSString *)link
               completion:(void (^)(NSDictionary *info))completion;

/// Join through an invite link. `chatId` is the chat that was joined, or 0
/// when the chat instead queued a join request - in which case
/// `requestSent` is YES. Both are 0/NO when the link was refused.
- (void)joinChatByInviteLink:(NSString *)link
                  completion:(void (^)(int64_t chatId, BOOL requestSent))completion;

#pragma mark - join requests

/// The pending join requests of a chat, oldest first. Each entry:
/// "userId" (NSNumber), "name" (NSString), "bio" (NSString),
/// "date" (NSNumber unix time). `total` is the full count.
/// `query` filters by name and may be nil; `inviteLink` narrows the list
/// to one link and may be nil.
- (void)joinRequestsForChat:(int64_t)chatId
                 inviteLink:(NSString *)inviteLink
                      query:(NSString *)query
                      limit:(NSInteger)limit
                 completion:(void (^)(NSArray *requests, NSInteger total))completion;

/// Approve or decline one pending request.
- (void)processJoinRequestFromUser:(int64_t)userId
                            inChat:(int64_t)chatId
                           approve:(BOOL)approve
                        completion:(void (^)(BOOL ok))completion;

/// Approve or decline every pending request, optionally only those from one
/// invite link (pass nil for all of them).
- (void)processAllJoinRequestsInChat:(int64_t)chatId
                          inviteLink:(NSString *)inviteLink
                             approve:(BOOL)approve
                          completion:(void (^)(BOOL ok))completion;

/// Number of join requests waiting, as the chat record already knows it.
/// Cheap enough for a profile row; -managementInfoForChat: has it too.
- (void)pendingJoinRequestCountForChat:(int64_t)chatId
                            completion:(void (^)(NSInteger count))completion;

#pragma mark - event log

/// Filter names accepted by -eventLogForChat:. Any subset, or nil for all:
/// "messageEdits", "messageDeletions", "messagePins", "memberJoins",
/// "memberLeaves", "memberInvites", "memberPromotions",
/// "memberRestrictions", "infoChanges", "settingChanges",
/// "inviteLinkChanges", "videoChatChanges", "forumChanges".

/// Recent actions of a group or channel, newest first. Each entry:
///   "eventId" (NSNumber, pass the last one back as `fromEventId` to page),
///   "date" (NSNumber unix time),
///   "userId" (NSNumber, 0 when the actor was not a user),
///   "name" (NSString, the actor's display name),
///   "action" (NSString, the TDLib action type without the "chatEvent"
///     prefix, e.g. "MessageDeleted" - a row can switch on this),
///   "text" (NSString, a one-line human summary already built for display),
///   "messageId" (NSNumber, 0 when the action carries no message),
///   "canReportNotSpam" (NSNumber BOOL, only ever YES for a deletion the
///     anti-spam filter made).
/// `query` filters by actor name and may be nil, `fromEventId` 0 starts at
/// the newest, `userIds` narrows to particular admins and may be nil.
- (void)eventLogForChat:(int64_t)chatId
                  query:(NSString *)query
            fromEventId:(int64_t)fromEventId
                  limit:(NSInteger)limit
                filters:(NSArray *)filters
                userIds:(NSArray *)userIds
             completion:(void (^)(NSArray *events))completion;

@end

// vim:ft=objc

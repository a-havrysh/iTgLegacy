//
// TGClient+ChatList - chat lists, folders, pinning, archive, unread counts.
//
// Every method here is safe to call before the chat list has finished loading;
// completions run on the main queue and get nil / empty on failure.
//
#import "TGClient.h"

/// Which chat list a call applies to. The main list and the archive are fixed;
/// any other value is a chat folder id as it appears in TGClient's `folders`
/// (TDLib hands out folder ids starting at 2, so there is no collision).
typedef NSInteger TGChatListId;
enum {
    TGChatListMain    = 0,
    TGChatListArchive = -1
};

@interface TGClient (ChatList)

#pragma mark - lists

/// Chats of any list, in the order TDLib gives them. Each entry is a chat row
/// in the same shape as `chats`: "id", "title", "text", "unread", "date",
/// "isGroup", "isPinned", "isMuted". Rows the client has not cached yet come
/// back with just "id", "title" and "unread".
- (void)chatsInList:(TGChatListId)list
              limit:(NSInteger)limit
         completion:(void (^)(NSArray *chats))completion;

/// Ask TDLib for more chats of a list. Fire and forget: the answer arrives as
/// updates and shows up through `onChatsChanged` / `onArchiveChanged`.
- (void)loadMoreChatsInList:(TGChatListId)list limit:(NSInteger)limit;

/// Mark every chat of a list as read ("Mark all as read").
- (void)markListAsRead:(TGChatListId)list;

/// Unread counters for a list, computed from the rows the client already
/// holds. Keys: "chats", "unmutedChats", "messages", "unmutedMessages" (all
/// NSNumber). Recompute it whenever `onChatsChanged` fires. Folder lists are
/// not cached locally, so this answers for the main list and the archive only;
/// for a folder use -chatsInList:limit:completion: and sum "unread".
- (NSDictionary *)unreadSummaryForList:(TGChatListId)list;

/// The blue-dot "unread" flag a user can set by hand, independent of whether
/// there are actually unread messages.
- (void)setChat:(int64_t)chatId markedAsUnread:(BOOL)marked;

#pragma mark - pinning

/// Pin or unpin a chat in a given list. TGClient's -setChat:pinned: does the
/// same for the main list only.
- (void)setChat:(int64_t)chatId pinned:(BOOL)pinned inList:(TGChatListId)list;

/// Replace the whole pinned set of a list, in the order given. This is what a
/// table view in edit mode should send after a reorder: pass the chat ids of
/// the pinned section, top first, as NSNumbers.
- (void)setPinnedChats:(NSArray *)chatIds inList:(TGChatListId)list;

#pragma mark - membership of lists

/// Add a chat to a list (archive it, or put it in a folder). `completion` may
/// be nil; it gets NO when TDLib refused, e.g. the folder is full.
- (void)addChat:(int64_t)chatId toList:(TGChatListId)list completion:(void (^)(BOOL ok))completion;

/// Lists this chat may still be added to, for an "Add to folder" sheet. Each
/// entry: "list" (NSNumber TGChatListId) and "title".
- (void)listsToAddChat:(int64_t)chatId completion:(void (^)(NSArray *lists))completion;

#pragma mark - folders

/// Full definition of one folder, flattened. Keys: "id" (NSNumber), "title",
/// "icon" (NSString icon name, may be empty), "colorId" (NSNumber, -1 when the
/// folder has no tag colour), "isShareable" (NSNumber BOOL), "pinnedChatIds",
/// "includedChatIds", "excludedChatIds" (NSArrays of NSNumber), and the type
/// toggles "excludeMuted", "excludeRead", "excludeArchived", "includeContacts",
/// "includeNonContacts", "includeBots", "includeGroups", "includeChannels"
/// (NSNumber BOOL). This dictionary is exactly what -saveFolder: takes back.
- (void)folderWithId:(NSInteger)folderId completion:(void (^)(NSDictionary *folder))completion;

/// Create or update a folder from the dictionary shape above. Include "id" to
/// edit an existing folder, leave it out to create a new one. Missing keys
/// default to empty / NO. `completion` gets the folder id, or 0 on failure.
- (void)saveFolder:(NSDictionary *)folder completion:(void (^)(NSInteger folderId))completion;

/// Delete a folder. `chatIds` are chats to leave along with it - pass nil or an
/// empty array to keep them all; -chatsToLeaveWhenDeletingFolder:completion:
/// says which ones are eligible.
- (void)deleteFolder:(NSInteger)folderId leavingChats:(NSArray *)chatIds;

/// Chats that only this folder holds, so a delete sheet can offer to leave
/// them. Completion gets an array of chat rows.
- (void)chatsToLeaveWhenDeletingFolder:(NSInteger)folderId completion:(void (^)(NSArray *chats))completion;

/// How many chats a folder definition would hold, for the live counter in the
/// folder editor. Takes the same dictionary as -saveFolder:.
- (void)chatCountForFolder:(NSDictionary *)folder completion:(void (^)(NSInteger count))completion;

/// The icon TDLib would pick for a folder definition, so the picker can show
/// a sensible default before the user chooses.
- (void)defaultIconNameForFolder:(NSDictionary *)folder completion:(void (^)(NSString *iconName))completion;

/// The icon names a folder may use, for the picker grid.
- (NSArray *)folderIconNames;

/// Reorder folders. `folderIds` are NSNumbers, in the order the tabs should
/// appear; `position` is where the main list sits among them (0 = first).
- (void)reorderFolders:(NSArray *)folderIds mainListPosition:(NSInteger)position;

/// Folders Telegram suggests. Each entry: "title", "icon", "description" and
/// "folder" (the full definition, ready for -saveFolder:).
- (void)recommendedFoldersWithCompletion:(void (^)(NSArray *folders))completion;

#pragma mark - shared folders

/// Invite links of a folder. Each entry: "link", "name", "chatIds".
- (void)inviteLinksForFolder:(NSInteger)folderId completion:(void (^)(NSArray *links))completion;

/// Chats of a folder that may be shared through an invite link, as chat rows.
- (void)shareableChatsInFolder:(NSInteger)folderId completion:(void (^)(NSArray *chats))completion;

/// Create an invite link covering `chatIds`. `completion` gets the same
/// dictionary shape as -inviteLinksForFolder:, or nil.
- (void)createInviteLinkForFolder:(NSInteger)folderId
                             name:(NSString *)name
                          chatIds:(NSArray *)chatIds
                       completion:(void (^)(NSDictionary *link))completion;

/// Change an existing link's name or chat selection.
- (void)editInviteLink:(NSString *)link
             forFolder:(NSInteger)folderId
                  name:(NSString *)name
               chatIds:(NSArray *)chatIds
            completion:(void (^)(NSDictionary *updated))completion;

- (void)deleteInviteLink:(NSString *)link forFolder:(NSInteger)folderId;

/// What a t.me/addlist link would do, without joining. Keys: "title",
/// "folderId" (NSNumber, 0 when the folder is new), "missingChatIds" (chats
/// the user is not in yet - these are what the confirm sheet lists) and
/// "addedChatIds". Nil when the link is invalid or expired.
- (void)checkFolderInviteLink:(NSString *)link completion:(void (^)(NSDictionary *info))completion;

/// Accept an invite link, joining exactly `chatIds` (a subset of
/// "missingChatIds"). `completion` gets NO when TDLib refused.
- (void)joinFolderByInviteLink:(NSString *)link
                       chatIds:(NSArray *)chatIds
                    completion:(void (^)(BOOL ok))completion;

/// Chats added to a shared folder by its owner that the user has not joined,
/// for the "add N chats" banner. Empty when there is nothing to offer.
- (void)newChatsInFolder:(NSInteger)folderId completion:(void (^)(NSArray *chats))completion;

/// Accept some of those new chats; pass nil to dismiss the banner without
/// joining anything.
- (void)addNewChats:(NSArray *)chatIds toFolder:(NSInteger)folderId;

#pragma mark - archive settings

/// Keys: "archiveUnknownSenders", "keepUnmutedArchived", "keepFoldersArchived"
/// (all NSNumber BOOL).
- (void)archiveSettingsWithCompletion:(void (^)(NSDictionary *settings))completion;

/// Same three keys; missing ones are treated as NO.
- (void)setArchiveSettings:(NSDictionary *)settings;

#pragma mark - search and recents

/// Chat-list search. `local` holds chats the user already has, `global` holds
/// public chats found by username. Both are chat rows.
- (void)searchChatList:(NSString *)query
            completion:(void (^)(NSArray *local, NSArray *global))completion;

/// Chats the user talks to most, for the empty search screen.
- (void)topChatsWithCompletion:(void (^)(NSArray *chats))completion;

/// Drop a chat from the top-chats suggestions.
- (void)removeTopChat:(int64_t)chatId;

/// Chats opened lately, newest first.
- (void)recentlyOpenedChatsWithCompletion:(void (^)(NSArray *chats))completion;

/// Remember a chat the user picked out of search results, so it shows up in
/// the "Recent" section next time.
- (void)addRecentlyFoundChat:(int64_t)chatId;
- (void)removeRecentlyFoundChat:(int64_t)chatId;
- (void)clearRecentlyFoundChats;

/// Sponsored chats to show at the bottom of search results. Each entry:
/// "uniqueId" (NSNumber, needed by the calls below), "id" (chat id), "title",
/// "sponsorInfo", "additionalInfo". Empty when there are none.
- (void)sponsoredChatsForQuery:(NSString *)query completion:(void (^)(NSArray *chats))completion;

/// Tell Telegram a sponsored row became visible, and that the user opened it.
- (void)viewSponsoredChat:(long long)uniqueId;
- (void)openSponsoredChat:(long long)uniqueId;

#pragma mark - row rendering

/// Everything the subtitle line of a chat row needs beyond the cached fields.
/// Keys: "draft" (NSString, empty when there is none - render it with the red
/// "Draft:" prefix and let it win over the last message), "markedUnread"
/// (NSNumber BOOL, the blue dot), "unread", "isPinned", "isMuted", and
/// "source" - "" for a normal chat, "psa" for a public service announcement
/// (which also fills "sourceText") or "proxy" for an MTProto proxy sponsor.
/// Rows with a source sit at the top of the list and must not be reordered.
- (void)rowDetailForChat:(int64_t)chatId completion:(void (^)(NSDictionary *detail))completion;

@end

// vim:ft=objc

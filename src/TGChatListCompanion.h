//
// TGChatListCompanion - owns the data behind one chat-list screen.
//
// One instance per TGChatListViewController instance, created and retained by
// that screen. It is the only object in the chat-list area that talks to
// TGClient: it fetches, caches, subscribes to the update callbacks, and hands
// the screen finished TGChatModel / TGFolderModel objects.
//
// The screen never subscripts a TDLib dictionary and never calls TGClient for
// list data again. It sets itself as `delegate`, calls -start, and reads
// -chats / -folders / -state.
//
// Not a singleton. Not thread safe: everything here is main queue, which is
// where TGClient's callbacks already land.
//
#import <Foundation/Foundation.h>
#import "TGClient+ChatList.h"

@class TGChatModel;
@class TGFolderModel;
@class TGChatListCompanion;

/// What the screen should be showing right now, so it never has to guess from
/// an empty array whether it is still loading or genuinely has nothing.
typedef NS_ENUM(NSInteger, TGChatListCompanionState) {
    /// -start has not been called yet.
    TGChatListCompanionStateIdle = 0,
    /// A fetch is in flight and there is nothing to show yet.
    TGChatListCompanionStateLoading,
    /// `chats` holds at least one row.
    TGChatListCompanionStateLoaded,
    /// The fetch finished and the list really is empty.
    TGChatListCompanionStateEmpty,
    /// The fetch came back with nothing usable; see -lastErrorText.
    TGChatListCompanionStateFailed
};

@protocol TGChatListCompanionDelegate <NSObject>

@optional

/// The rows changed. Indexes are into the *new* `chats` for insertions and
/// updates, and into the *old* array for removals - exactly what
/// -deleteRowsAtIndexPaths: / -insertRowsAtIndexPaths: want, applied in that
/// order inside one begin/endUpdates. Any of the three may be empty.
/// Prefer this over reloadData: on this hardware a full reload of a long list
/// is the difference between a smooth push and a visible stall.
- (void)chatListCompanion:(TGChatListCompanion *)companion
     didUpdateChatsInsert:(NSIndexSet *)inserted
                   remove:(NSIndexSet *)removed
                   reload:(NSIndexSet *)reloaded;

/// The rows moved around too much to describe row by row (a folder switch, a
/// first load, a reorder). The screen should reloadData.
- (void)chatListCompanionDidReplaceChats:(TGChatListCompanion *)companion;

/// `state` changed. The screen shows or hides its spinner / empty view here.
- (void)chatListCompanionDidChangeState:(TGChatListCompanion *)companion;

/// The folder list changed: rebuild the folder strip or chooser.
- (void)chatListCompanionDidChangeFolders:(TGChatListCompanion *)companion;

/// An unread total changed. Re-read -unreadCountForList: for the badges, and
/// -archivedChatCount / -archiveUnreadCount for the pull-down archive header.
- (void)chatListCompanionDidChangeUnreadCounts:(TGChatListCompanion *)companion;

@end

@interface TGChatListCompanion : NSObject

/// The screen. Weak by contract - the screen owns the companion.
@property (nonatomic, assign) id<TGChatListCompanionDelegate> delegate;

#pragma mark - what this companion is showing

/// Main list, archive, or a folder id. Defaults to TGChatListMain.
/// Setting it while running refetches and reports a full replace.
@property (nonatomic, assign) TGChatListId listId;

/// Convenience over `listId` for the archive screen.
@property (nonatomic, assign) BOOL showsArchive;

/// Folder id when a folder is being shown, 0 for the main list or the archive.
@property (nonatomic, assign) NSInteger folderId;

/// Title the navigation bar should carry for the current list: "Messages",
/// "Archived", or the folder's name. Never nil.
@property (nonatomic, readonly, copy) NSString *listTitle;

#pragma mark - lifecycle

/// Subscribes to TGClient and performs the first fetch. Idempotent.
/// The screen calls this from -viewDidLoad.
- (void)start;

/// Drops the subscription. The screen calls this from -dealloc; the companion
/// also does it for itself, so forgetting is survivable.
- (void)stop;

/// Refetch the current list now. Reports a diff, not a replace, when it can.
- (void)refresh;

/// Ask for the next page. No-op while one is already in flight or when the
/// list is known to be complete.
- (void)loadMore;

/// YES while a page request is outstanding, for a footer spinner.
@property (nonatomic, readonly) BOOL loadingMore;

/// Free everything that can be rebuilt: cached folder rows and per-folder
/// unread totals. Called for you on UIApplicationDidReceiveMemoryWarning.
- (void)purgeCaches;

#pragma mark - rows

/// Current rows, TGChatModel, in display order. Empty, never nil.
@property (nonatomic, readonly) NSArray *chats;

/// State of the current list. Observe changes through the delegate.
@property (nonatomic, readonly) TGChatListCompanionState state;

/// Short human line for TGChatListCompanionStateFailed, or nil.
@property (nonatomic, readonly, copy) NSString *lastErrorText;

/// Bounds-checked row access. Nil when `index` is out of range.
- (TGChatModel *)chatAtIndex:(NSInteger)index;

/// The row with this id, or nil when it is not in the current list.
- (TGChatModel *)chatWithId:(int64_t)chatId;

/// Index of a chat id in `chats`, or NSNotFound.
- (NSInteger)indexOfChatId:(int64_t)chatId;

#pragma mark - folders

/// The user's folders, TGFolderModel, in the order TDLib gives them. These are
/// summary-only models (id and title); fetch a full definition through the
/// folder editor's own companion. Empty, never nil.
@property (nonatomic, readonly) NSArray *folders;

/// The folder currently being shown, or nil for the main list / archive.
- (TGFolderModel *)currentFolder;

#pragma mark - unread totals

/// Unread messages in a list. Main and archive are answered from TGClient's
/// own summary; folder totals are summed here and refreshed at most every few
/// seconds, so this is cheap to call while building a tab strip.
- (NSInteger)unreadCountForList:(TGChatListId)list;

/// Unread total of the list this companion is showing.
@property (nonatomic, readonly) NSInteger unreadCount;

/// Chats sitting in the archive, for the pull-down archive header.
@property (nonatomic, readonly) NSInteger archivedChatCount;

/// Unread messages in the archive, for that header's badge.
@property (nonatomic, readonly) NSInteger archiveUnreadCount;

/// Mark every chat of the current list as read.
- (void)markCurrentListAsRead;

@end

// vim:ft=objc

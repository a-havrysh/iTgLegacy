//
// TGContactsCompanion - owns the data behind the Contacts screen.
//
// The screen asks this object for rows and never calls TGClient. The companion
// owns the contact list, its sorting into A-Z sections, the local and server
// search, the avatar thumbnails and the online-status subscription. Everything
// it vends is a TGUserModel; no TDLib dictionary crosses this header.
//
// One instance per screen instance, owned by the screen. Not a singleton.
//
#import <UIKit/UIKit.h>

@class TGUserModel;
@class TGContactsCompanion;

/// What the screen has to show right now, so it never infers a state from an
/// empty array.
typedef enum {
	/// Nothing requested yet.
	TGContactsStateIdle = 0,
	/// A first load is in flight and there is nothing to draw.
	TGContactsStateLoading,
	/// There are contacts.
	TGContactsStateLoaded,
	/// The load finished and the account has no contacts.
	TGContactsStateEmpty,
	/// The load finished without an answer. The screen may offer a retry.
	TGContactsStateFailed
} TGContactsState;

@protocol TGContactsCompanionDelegate <NSObject>

@optional

/// -state changed. The screen shows its spinner, its empty view or its table.
- (void)contactsCompanionDidChangeState:(TGContactsCompanion *)companion;

/// The section structure changed and the table has to be reloaded whole:
/// a first load, a search query starting or ending, or a set of changes too
/// tangled to express as rows.
- (void)contactsCompanionDidReloadContacts:(TGContactsCompanion *)companion;

/// Contacts came and went while the section structure stayed the same.
/// Both arrays hold NSIndexPath and may be empty; `removed` is expressed
/// against the old table, `inserted` against the new one, which is the order
/// UITableView wants inside one begin/endUpdates.
- (void)contactsCompanion:(TGContactsCompanion *)companion
	 didInsertRowsAtPaths:(NSArray *)inserted
		removeRowsAtPaths:(NSArray *)removed;

/// Rows whose contents changed in place - an online status arriving, badges
/// resolving, a close-friend star toggling. NSIndexPath array, never empty.
/// Reload just these; the row order is unaffected.
- (void)contactsCompanion:(TGContactsCompanion *)companion
	  didUpdateRowsAtPaths:(NSArray *)paths;

/// An avatar finished downloading. -avatarForUser: will now answer for this
/// user. Sent coalesced, so several avatars may land in one call.
- (void)contactsCompanionDidUpdateAvatars:(TGContactsCompanion *)companion;

@end

@interface TGContactsCompanion : NSObject

/// The screen. Weak - the screen owns the companion.
@property (nonatomic, assign) id<TGContactsCompanionDelegate> delegate;

/// What to draw. Never inferred from the row count.
@property (nonatomic, readonly) TGContactsState state;

/// YES once a load has completed at least once, successfully or not.
@property (nonatomic, readonly) BOOL loaded;

/// In picker mode the companion skips the extras a plain contact list does not
/// need: close friends, the imported-contact count and the server-side search.
/// Set it before -reload.
@property (nonatomic, assign) BOOL pickerMode;

#pragma mark - loading

/// Start, or restart, the contact load. Safe to call again from a
/// pull-to-refresh; a second call while one is in flight is ignored.
- (void)reload;

/// Begin observing status updates and memory warnings. Call from the screen's
/// -viewDidLoad; -reload does not imply it.
- (void)startObserving;

/// Stop observing. Called automatically on -dealloc, so a screen only needs
/// this when it wants to go quiet while off-screen.
- (void)stopObserving;

#pragma mark - rows

/// Sections, already sorted and lettered. 1 while searching.
- (NSInteger)numberOfSections;

- (NSInteger)numberOfRowsInSection:(NSInteger)section;

/// The letter header for a section, or nil when the section takes no header
/// (the first section of an unsearched list, and every search result).
- (NSString *)titleForSection:(NSInteger)section;

/// Letters for the index bar down the right edge, or nil while searching.
- (NSArray *)sectionIndexTitles;

/// The contact at a position, or nil when the position is stale.
- (TGUserModel *)userAtIndexPath:(NSIndexPath *)indexPath;

/// Where a contact currently sits, or nil when it is not on screen. Useful
/// after an action the screen took on one user.
- (NSIndexPath *)indexPathForUserId:(int64_t)userId;

/// Every loaded contact in display order, ignoring any search. For a screen
/// that needs the whole list at once, such as a new-group member picker.
- (NSArray *)allContacts;

#pragma mark - search

/// The current query, or nil. Set through -setSearchQuery:.
@property (nonatomic, readonly, copy) NSString *searchQuery;

/// Filter the list. Pass nil or an empty string to go back to the sectioned
/// contact list. Filtering is immediate and local; a server-side search for
/// people who are not contacts yet follows shortly after, and merges in
/// through -contactsCompanionDidReloadContacts:.
- (void)setSearchQuery:(NSString *)query;

#pragma mark - per-user extras

/// Telegram's close-friend marking. Loaded in one call with the list, so this
/// answers without a round trip.
- (BOOL)isCloseFriendUserId:(int64_t)userId;

/// Badges shown after a name. Each answers NO until the badge set for that
/// user has been fetched, which the first call starts; the delegate learns
/// through -contactsCompanion:didUpdateRowsAtPaths: when the answer changes.
- (BOOL)isVerifiedUserId:(int64_t)userId;
- (BOOL)isPremiumUserId:(int64_t)userId;
- (BOOL)isScamUserId:(int64_t)userId;
- (BOOL)isFakeUserId:(int64_t)userId;

/// How many address-book entries Telegram currently holds, or -1 until the
/// count has arrived. Not fetched in picker mode.
@property (nonatomic, readonly) NSInteger importedContactCount;

#pragma mark - avatars

/// A list-sized avatar for a contact, or nil when there is none yet. The first
/// nil answer starts a download and a disk-cache lookup; when it lands the
/// delegate gets -contactsCompanionDidUpdateAvatars:. Cheap to call from
/// -tableView:cellForRowAtIndexPath:.
- (UIImage *)avatarForUser:(TGUserModel *)user;

/// Drop the in-memory avatar cache. Called for the companion automatically on
/// a system memory warning; exposed for a screen that wants to shed earlier.
- (void)clearAvatarCache;

@end

// vim:ft=objc

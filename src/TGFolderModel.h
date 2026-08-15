//
// TGFolderModel - one chat folder, typed.
//
// Built from the flattened folder dictionary TGClient+ChatList vends:
// -folderWithId:completion:, the entries of -recommendedFoldersWithCompletion:
// (which wrap the definition under "folder"), and the light rows of
// TGClient's `folders` property, which carry only "id" and "title".
//
// A screen reads properties. It never subscripts a folder dictionary again.
//
#import <Foundation/Foundation.h>

@interface TGFolderModel : NSObject

#pragma mark - identity

/// TDLib folder id, usable as a TGChatListId. 0 when this is a folder that has
/// not been created yet - a recommended folder, or an editor draft.
@property (nonatomic, readonly) int64_t folderId;

/// Folder name. Optional: nil when nothing named it (an unnamed draft).
@property (nonatomic, readonly, copy) NSString *title;

/// Icon name, one of -[TGClient folderIconNames]. Optional: nil when the
/// folder has no icon of its own and TDLib's default should be used.
@property (nonatomic, readonly, copy) NSString *iconName;

/// Tag colour index, or -1 when the folder has no tag colour.
@property (nonatomic, readonly) NSInteger colorId;

/// Whether the folder can be shared through an invite link.
@property (nonatomic, readonly) BOOL isShareable;

/// One-line pitch shown next to a recommended folder. Optional: nil for a
/// folder the user already has.
@property (nonatomic, readonly, copy) NSString *folderDescription;

#pragma mark - ordering

/// Position of this folder among the user's folders, as delivered.
/// 0 for a folder that came on its own rather than out of a list.
@property (nonatomic, readonly) NSInteger order;

/// Chat ids pinned to the top of this folder's list, top first.
/// NSNumbers; empty, never nil. Their order is the pin order.
@property (nonatomic, readonly, copy) NSArray *pinnedChatIds;

#pragma mark - include rules

/// Chat ids always in the folder. NSNumbers; empty, never nil.
@property (nonatomic, readonly, copy) NSArray *includedChatIds;

@property (nonatomic, readonly) BOOL includeContacts;
@property (nonatomic, readonly) BOOL includeNonContacts;
@property (nonatomic, readonly) BOOL includeBots;
@property (nonatomic, readonly) BOOL includeGroups;
@property (nonatomic, readonly) BOOL includeChannels;

#pragma mark - exclude rules

/// Chat ids never in the folder. NSNumbers; empty, never nil.
@property (nonatomic, readonly, copy) NSArray *excludedChatIds;

@property (nonatomic, readonly) BOOL excludeMuted;
@property (nonatomic, readonly) BOOL excludeRead;
@property (nonatomic, readonly) BOOL excludeArchived;

#pragma mark - derived

/// YES when no type toggle is on and no chat is listed by hand, i.e. the
/// folder as defined would hold nothing.
@property (nonatomic, readonly) BOOL isEmptyDefinition;

/// YES when the row carries nothing but id and title, as TGClient's `folders`
/// entries do. Such a model has no rules to show; fetch the full definition
/// with -folderWithId:completion: before rendering an editor.
@property (nonatomic, readonly) BOOL isSummaryOnly;

#pragma mark - conversion

/// The only place a folder dictionary is read. Returns nil when `dict` is not
/// a dictionary, or names nothing at all (no id and no title). Accepts both
/// the flattened definition and a recommended-folder entry that wraps it
/// under "folder".
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array of those dictionaries, in order, dropping entries that fail
/// to build. Each model's `order` is its index in the result.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

/// The flattened dictionary shape back again, ready for -saveFolder: and
/// -chatCountForFolder:. "id" is present only when `folderId` is non-zero.
- (NSDictionary *)dictionaryRepresentation;

@end

// vim:ft=objc

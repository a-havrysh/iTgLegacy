#import <Foundation/Foundation.h>

/// One row of the chat list, typed.
///
/// Built from the chat dictionaries TGClient keeps in its chatsById table and
/// vends through -chats / -archivedChats. This is the only place those
/// dictionaries are read: a screen reads properties here and never subscripts.
///
/// Immutable. Nothing is retained from the source dictionary.
@interface TGChatModel : NSObject

/// TDLib chat id. Never 0 for a model that was built successfully.
@property (nonatomic, readonly) int64_t chatId;

/// Chat title. Optional - nil when TDLib has not sent one yet.
@property (nonatomic, readonly, copy) NSString *title;

/// Last-message preview, already prefixed with "Sender: " for groups.
/// Optional - nil when the chat has no last message.
@property (nonatomic, readonly, copy) NSString *previewText;

/// Unsent draft text. Optional - nil when there is no draft.
@property (nonatomic, readonly, copy) NSString *draftText;

/// Current chat action as a finished phrase, e.g. "typing...". Optional -
/// nil when nobody is acting. The list shows it in place of previewText.
@property (nonatomic, readonly, copy) NSString *actionText;

/// Unix time of the last message, in seconds. 0 when unknown.
@property (nonatomic, readonly) int64_t date;

/// Unread message count. 0 when the chat is read.
@property (nonatomic, readonly) NSInteger unreadCount;

/// The user marked the chat unread by hand while unreadCount is 0.
@property (nonatomic, readonly) BOOL markedUnread;

@property (nonatomic, readonly) BOOL pinned;
@property (nonatomic, readonly) BOOL muted;

/// YES for a basic group, a supergroup or a channel; NO for private and secret.
@property (nonatomic, readonly) BOOL group;

/// YES when the chat is a broadcast channel.
@property (nonatomic, readonly) BOOL channel;

/// YES for a one-to-one chat with a user.
@property (nonatomic, readonly) BOOL privateChat;

/// YES when the supergroup behind this chat has topics turned on.
@property (nonatomic, readonly) BOOL forum;

/// YES for the Saved Messages chat, which gets its own icon and title.
@property (nonatomic, readonly) BOOL savedMessages;

/// Supergroup id behind this chat, or 0 when it is not a supergroup.
@property (nonatomic, readonly) int64_t supergroupId;

/// File id of the small avatar, for -downloadFile:. 0 when the chat has none.
@property (nonatomic, readonly) int32_t photoFileId;

/// Sort key inside the main list. 0 means the chat is not in the main list.
@property (nonatomic, readonly) int64_t order;

/// Sort key inside the archive. Non-zero means the chat lives in the archive.
@property (nonatomic, readonly) int64_t archiveOrder;

/// The other party in a private chat is online right now.
@property (nonatomic, readonly) BOOL online;

/// The last message was sent by the current user, so the row shows a tick.
@property (nonatomic, readonly) BOOL outgoing;

/// That outgoing last message has been read by the other side (double tick).
@property (nonatomic, readonly) BOOL outgoingRead;

/// This row is a sponsored placement rather than a real chat.
@property (nonatomic, readonly) BOOL sponsored;

/// Sponsored placement id, passed back on tap. 0 for a normal chat.
@property (nonatomic, readonly) int64_t sponsoredUniqueId;

/// YES when the row should draw an unread badge: a real count or a manual mark.
@property (nonatomic, readonly) BOOL hasUnread;

/// YES when the chat belongs in the archive list rather than the main list.
@property (nonatomic, readonly) BOOL archived;

/// Builds a model from one TGClient chat dictionary.
/// Returns nil when dict is not a dictionary or carries no usable chat id.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array of chat dictionaries, dropping entries that fail to build.
/// Returns an empty array when dicts is not an array.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

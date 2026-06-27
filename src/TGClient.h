//
// TGClient - TDLib client for iOS 7.1.2 / armv7.
//
// TDLib is loaded with dlopen rather than linked: statically linked it pushes
// the app's __TEXT past the 16MB armv7 thumb branch limit, which this linker
// cannot bridge. See scripts/build_tdlib_dylib.sh.
//
// Everything is JSON over td_json_client_*. One background thread owns the
// receive loop; handlers are always delivered on the main queue.
//
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TGAuthState) {
    TGAuthStateUnknown = 0,
    TGAuthStateWaitPhoneNumber,
    TGAuthStateWaitCode,
    TGAuthStateWaitPassword,
    TGAuthStateWaitRegistration,
    TGAuthStateReady,
    TGAuthStateLoggingOut,
    TGAuthStateClosed
};

@interface TGClient : NSObject

+ (instancetype)shared;

/// YES once libtdjson.dylib is loaded and a client exists.
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) TGAuthState authState;

/// Called on the main queue whenever the authorization state changes.
@property (nonatomic, copy) void (^onAuthState)(TGAuthState state);
/// Called on the main queue for TDLib errors that concern the user.
@property (nonatomic, copy) void (^onError)(NSString *message);
/// Connection to Telegram, as TDLib reports it. Replaces the old
/// SCNetworkReachability check: what matters is whether the client is talking
/// to Telegram, not whether the device has a route somewhere.
typedef NS_ENUM(NSInteger, TGConnectionState) {
    TGConnectionStateUnknown = 0,
    TGConnectionStateWaitingForNetwork,
    TGConnectionStateConnecting,
    TGConnectionStateUpdating,
    TGConnectionStateReady
};

@property (nonatomic, readonly) TGConnectionState connectionState;
/// Main queue. `text` is nil when connected, a short status otherwise.
@property (nonatomic, copy) void (^onConnectionState)(TGConnectionState state, NSString *text);

/// Called on the main queue whenever the chat list changed. Read `chats`.
@property (nonatomic, copy) void (^onChatsChanged)(void);

/// Chat list, most recent first. Each entry is a dictionary with keys
/// "id" (NSNumber), "title", "text" (last message preview), "unread"
/// (NSNumber), "date" (NSNumber, unix time). Main queue only.
@property (nonatomic, readonly) NSArray *chats;

/// Ask TDLib to populate the main chat list. Only meaningful once authorized.
- (void)loadChats;

/// The signed-in user: "id", "first_name", "username", "phone". Nil until the
/// session is ready. Main queue only.
@property (nonatomic, readonly) NSDictionary *me;

/// Loads the dylib, creates the client and starts the receive loop.
/// Safe to call more than once. Returns NO if TDLib is unavailable.
- (BOOL)start;

/// Request with a reply. `completion` runs on the main queue with the raw
/// TDLib object, or an object of @type "error".
- (void)request:(NSDictionary *)request completion:(void (^)(NSDictionary *result))completion;

#pragma mark - files

/// Download a file by TDLib id. `completion` gets the local path, or nil.
/// Already-downloaded files complete immediately.
- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *path))completion;

#pragma mark - messages

/// Newest `limit` messages of a chat, oldest first. Each entry has "id",
/// "text", "date", "outgoing" (NSNumber BOOL), "senderId", "photoId"
/// (NSNumber file id or nil).
- (void)historyForChat:(int64_t)chatId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *messages))completion;

/// Fired on the main queue when a message arrives, is edited or deleted in
/// any chat. `message` is the flattened form; nil means it was deleted.
@property (nonatomic, copy) void (^onMessage)(int64_t chatId, NSDictionary *message, int64_t deletedId);

- (void)sendText:(NSString *)text toChat:(int64_t)chatId;
/// Send a local image file. TDLib uploads it and echoes the message back.
- (void)sendPhotoAtPath:(NSString *)path toChat:(int64_t)chatId;
- (void)deleteMessage:(int64_t)messageId inChat:(int64_t)chatId;
- (void)markRead:(NSArray *)messageIds inChat:(int64_t)chatId;

#pragma mark - contacts

/// Telegram contacts as dictionaries with "id", "first_name", "last_name",
/// "phone", "username".
- (void)contactsWithCompletion:(void (^)(NSArray *users))completion;

/// Chat id for a private conversation with a user, creating it if needed.
- (void)privateChatWithUser:(int64_t)userId completion:(void (^)(int64_t chatId))completion;

/// Resolve an address-book phone number to a Telegram user, or nil.
/// Same dictionary shape as -contactsWithCompletion:.
- (void)userForPhone:(NSString *)phone completion:(void (^)(NSDictionary *user))completion;

#pragma mark - maintenance

/// Drop TDLib's local database. The session stays.
- (void)clearLocalDatabase;

- (void)sendPhoneNumber:(NSString *)phoneNumber;
- (void)sendCode:(NSString *)code;
- (void)sendPassword:(NSString *)password;
- (void)logOut;

/// Fire-and-forget request. `request` is a JSON object; @extra is not tracked.
- (void)send:(NSDictionary *)request;

@end

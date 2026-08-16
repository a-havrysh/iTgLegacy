/**
 * TGClient+Private - the state and plumbing TGClient categories need.
 *
 * TGClient.m is a single large file that many feature areas would otherwise
 * have to edit at once. Everything new goes into its own TGClient+<Area>
 * category file instead, and this header is what those categories import to
 * reach the shared state and the request plumbing.
 */
#import "TGClient.h"

typedef void *(*td_create_fn)(void);
typedef void  (*td_send_fn)(void *client, const char *request);
typedef const char *(*td_recv_fn)(void *client, double timeout);
typedef const char *(*td_exec_fn)(void *client, const char *request);

@interface TGClient ()
@property (nonatomic, assign) void *handle;
@property (nonatomic, assign) void *client;
@property (nonatomic, assign) td_send_fn td_send;
@property (nonatomic, assign) td_recv_fn td_recv;
@property (nonatomic, assign) TGAuthState authState;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, copy)   NSString *pendingPhoneNumber;
@property (nonatomic, strong) NSMutableDictionary *chatsById;   // id -> mutable info
@property (nonatomic, strong) NSMutableDictionary *usersById;   // id -> display name
@property (nonatomic, strong) NSMutableDictionary *userPhotosById; // id -> photo file id
/// supergroup id -> is_forum. A chat only carries the supergroup's id; whether
/// it is a forum lives on the supergroup, which arrives in its own update.
@property (nonatomic, strong) NSMutableDictionary *forumSupergroups;
@property (nonatomic, strong) NSArray *archivedChats;
@property (nonatomic, strong) NSArray *folders;
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, strong) NSMutableArray *outbox;   // JSON strings awaiting send
@property (nonatomic, assign) BOOL parametersSent;
@property (nonatomic, strong) NSMutableArray *preInitRequests;
@property (nonatomic, strong) NSLock *outboxLock;
@property (nonatomic, assign) NSUInteger chatsAtLastLoad;
@property (nonatomic, assign) BOOL chatListComplete;
@property (nonatomic, assign) BOOL chatsNotifyScheduled;
@property (nonatomic, assign) BOOL idlePolling;
@property (nonatomic, assign) BOOL cachedChatsLoaded;
@property (nonatomic, assign) NSTimeInterval lastChatSnapshotSave;
@property (nonatomic, strong) NSMutableSet *chatsConfirmedByServer;
@property (nonatomic, assign) NSUInteger loadChatsAttempts;
@property (nonatomic, strong) NSDictionary *me;
@property (nonatomic, assign) TGConnectionState connectionState;
@property (nonatomic, strong) NSMutableDictionary *pendingRequests;  // @extra -> completion
@property (nonatomic, assign) NSUInteger requestSeq;
@property (nonatomic, strong) NSMutableDictionary *fileWaiters;      // fileId -> completions

/// Send a request and get the reply on the main queue. `completion` receives
/// the raw TDLib object, or an "error" object if the call failed.
- (void)request:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion;

- (void)rebuildChats;
- (void)scheduleChatsChanged;
- (void)saveCachedChatsThrottled;
- (void)dropChatsMissingFromServerList;
@end

// vim:ft=objc

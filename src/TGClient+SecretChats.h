//
// TGClient+SecretChats - end-to-end encrypted chats: creating and closing
// them, their handshake state, the encryption key visualization, the
// self-destruct timer (TTL) and self-destructing message content.
//
// Everything returns plain Foundation objects. A "secret chat info"
// dictionary is the shape the UI layer works with everywhere here:
//
//   "secretChatId" NSNumber   the int32 secret chat id
//   "chatId"       NSNumber   the ordinary chat id, or 0 if not resolved
//   "userId"       NSNumber   the peer
//   "name"         NSString   peer display name, "" if unknown
//   "state"        NSString   "pending", "ready" or "closed"
//   "isOutbound"   NSNumber   YES when we started the chat
//   "layer"        NSNumber   the peer's secret-chat protocol layer
//   "keyHash"      NSString   base64 of the 36-byte key hash, "" if absent
//
// Note that TDLib only produces secret chats when it was started with
// use_secret_chats:YES. TGClient currently passes NO, so every call here
// fails until that one parameter is flipped in TGClient.m.
//
#import "TGClient.h"

@interface TGClient (SecretChats)

#pragma mark - lifecycle

/// Start a new secret chat with a user. `completion` receives the secret chat
/// info of the freshly created chat (state is normally "pending" until the
/// peer's device comes online), or nil on failure. "chatId" is filled in and
/// is what you push a TGChatViewController on.
- (void)createSecretChatWithUser:(int64_t)userId
                      completion:(void (^)(NSDictionary *info))completion;

/// Resolve an existing secret chat id (as carried by chatTypeSecret, an
/// update or a deep link) into an ordinary chat. `completion` receives the
/// chat id, or 0 on failure.
- (void)openSecretChatId:(int)secretChatId
              completion:(void (^)(int64_t chatId))completion;

/// Terminate a secret chat. Fire and forget; the chat stays in the list in
/// the "closed" state until it is deleted.
- (void)closeSecretChatId:(int)secretChatId;

/// Terminate the secret chat behind an ordinary chat id and, when
/// `deleteHistory` is YES, wipe its history and remove it from the chat list.
/// This is the destructive row in the secret-chat profile screen.
- (void)closeSecretChatForChat:(int64_t)chatId deleteHistory:(BOOL)deleteHistory;

#pragma mark - state

/// Whether a chat we already know about is a secret chat. Answers from the
/// cached chat list, so it is cheap and safe to call while drawing cells.
- (BOOL)isSecretChat:(int64_t)chatId;

/// The secret chat id behind an ordinary chat id, or 0 if the chat is not
/// secret or is not cached yet.
- (int)secretChatIdForChat:(int64_t)chatId;

/// Secret chat info by secret chat id. `completion` receives nil on failure.
- (void)secretChatInfo:(int)secretChatId
            completion:(void (^)(NSDictionary *info))completion;

/// Secret chat info for an ordinary chat id, with "chatId" and "name" filled
/// in. `completion` receives nil when the chat is not a secret chat or the
/// lookup failed. This is what the chat header and profile screen read.
- (void)secretChatInfoForChat:(int64_t)chatId
                   completion:(void (^)(NSDictionary *info))completion;

/// One-line status for the chat header: nil when the chat is ready and the
/// normal user status should be shown, otherwise text such as
/// "waiting for Alice to come online" or "secret chat cancelled".
- (void)secretChatStatusForChat:(int64_t)chatId
                     completion:(void (^)(NSString *status))completion;

/// Whether the composer may send at all - NO while the handshake is pending
/// and after the chat was closed. `completion` also reports the state string.
- (void)canSendInSecretChat:(int64_t)chatId
                 completion:(void (^)(BOOL canSend, NSString *state))completion;

#pragma mark - encryption key

/// The key hash of a secret chat unpacked for the classic 12x12 identicon:
/// `completion` receives an array of 144 NSNumbers, each 0..3, to be drawn in
/// the four fixed colours, or nil when the key is not available yet (the
/// handshake must be complete). Row-major, 12 per row.
- (void)encryptionKeyGridForChat:(int64_t)chatId
                      completion:(void (^)(NSArray *cells))completion;

/// Raw base64 key hash, for the explanatory text under the grid.
/// `completion` receives "" when no key is available.
- (void)encryptionKeyHashForChat:(int64_t)chatId
                      completion:(void (^)(NSString *base64))completion;

#pragma mark - capability gating

/// Whether the peer's protocol layer supports a feature, so the chat
/// controller can hide affordances the other side cannot understand.
/// `feature` is one of "reply", "entities", "sticker", "video_note",
/// "delete_for_both". `completion` receives NO when unsupported or unknown.
- (void)secretChat:(int64_t)chatId
   supportsFeature:(NSString *)feature
        completion:(void (^)(BOOL supported))completion;

/// Whether a message type may be sent into this chat at all. `kind` is a
/// TDLib InputMessageContent type name, e.g. "inputMessagePoll" or
/// "inputMessageForwarded". Synchronous and cache-only: secret chats reject
/// polls, checklists, forwards, stories and external-message replies, and
/// this is the guard the attachment sheet and forward picker use so TDLib
/// never returns an error the user cannot interpret.
- (BOOL)secretChat:(int64_t)chatId allowsInputMessage:(NSString *)kind;

/// Whether the message context menu may offer Edit / Schedule for this chat.
/// Both are always unavailable in secret chats.
- (BOOL)chatAllowsMessageEditing:(int64_t)chatId;

#pragma mark - self-destruct timer

/// The chat's current self-destruct timer in seconds, 0 when off. Read from
/// the cached chat record where possible, otherwise fetched.
- (void)autoDeleteTimeForChat:(int64_t)chatId
                   completion:(void (^)(NSInteger seconds))completion;

/// The classic timer ladder as the action sheet shows it. Each entry:
/// "seconds" (NSNumber) and "title" (NSString, e.g. "Off", "5 seconds",
/// "1 week").
+ (NSArray *)autoDeleteLadder;

/// Human wording for a timer value, e.g. 300 -> "5 minutes", 0 -> "Off".
+ (NSString *)autoDeleteTitleForSeconds:(NSInteger)seconds;

/// The account-wide default self-destruct timer for new chats, in seconds.
/// `completion` receives 0 when the feature is off.
- (void)defaultAutoDeleteTimeWithCompletion:(void (^)(NSInteger seconds))completion;

/// Set the account-wide default self-destruct timer. Fire and forget.
- (void)setDefaultAutoDeleteTime:(NSInteger)seconds;

#pragma mark - self-destructing content

/// Marking a message's content as opened is what starts the self-destruct
/// countdown, so it must happen the moment a secret photo, voice note or
/// video note is actually shown to the user. Without it the timer never runs
/// and the message never expires. Use -openContentOfMessage:inChat: from
/// TGClient+MessageContent.h, which already wraps openMessageContent.

/// Flatten a raw TDLib message into what a self-destructing bubble needs:
///   "isSecret"    NSNumber BOOL  media that must be hidden until tapped
///   "isExpired"   NSNumber BOOL  content is one of the messageExpired* types
///   "expiredText" NSString       placeholder wording for the expired bubble
///   "ttl"         NSNumber       self-destruct time in seconds, 0 if none
///   "immediate"   NSNumber BOOL  destroys as soon as it is viewed
///   "remaining"   NSNumber       seconds left, 0 when the timer has not
///                                started or the message does not destruct
/// Pure and synchronous - no network. Returns nil for a message that is not
/// self-destructing and not expired.
- (NSDictionary *)selfDestructInfoForMessage:(NSDictionary *)message;

/// Extra key to merge into an inputMessage* dictionary to make the content
/// self-destruct. `seconds` of 0 means "destroy as soon as viewed"
/// (messageSelfDestructTypeImmediately), which is the only mode voice and
/// video notes support. Returns nil when the chat is not secret, so the
/// caller can merge unconditionally.
- (NSDictionary *)selfDestructOptionForChat:(int64_t)chatId seconds:(NSInteger)seconds;

#pragma mark - sessions

/// Allow or forbid one authorized session to accept incoming secret chats.
/// This is the switch row in the session detail view; secret chats can only
/// be accepted by one device at a time.
- (void)setSession:(int64_t)sessionId canAcceptSecretChats:(BOOL)canAccept;

#pragma mark - service messages

/// Wording for the secret-chat service rows, or nil when the message is not
/// one of them. Covers messageChatSetMessageAutoDeleteTime ("Alice set the
/// self-destruct timer to 5 seconds") and messageScreenshotTaken
/// ("Alice took a screenshot!"). `message` is a raw TDLib message.
- (NSString *)secretServiceTextForMessage:(NSDictionary *)message;

/// Notification text for an incoming secret chat request, or nil when the
/// notification is not notificationTypeNewSecretChat. `notification` is a
/// raw TDLib notification object.
- (NSString *)textForSecretChatNotification:(NSDictionary *)notification;

@end

// vim:ft=objc

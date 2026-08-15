//
// TGClient+Messages - sending, editing, deleting, forwarding, replying,
// drafts, scheduling, read state and message links.
//
// Everything here returns plain Foundation objects. Flattened messages use the
// same key names TGClient's own history methods use ("id", "text", "date",
// "outgoing", "senderId", "kind"), so a table cell written against one works
// with the other, but only that common subset is filled in.
//
#import "TGClient.h"

@interface TGClient (Messages)

#pragma mark - sending

/// Send text with the options the long-press-on-Send menu offers.
/// `options` may be nil, or carry any of:
///   "silent"     NSNumber BOOL - deliver without a notification sound
///   "protect"    NSNumber BOOL - recipient cannot forward or save it
///   "sendDate"   NSNumber unix time - schedule the send for that moment
///   "whenOnline" NSNumber BOOL - schedule until the recipient comes online
///   "clearDraft" NSNumber BOOL - drop the chat's stored draft (default YES)
/// `threadId` is a forum topic / comment thread, or 0.
/// `completion` gets the flattened message TDLib accepted, or nil on failure.
- (void)sendText:(NSString *)text
          toChat:(int64_t)chatId
          thread:(int64_t)threadId
         replyTo:(int64_t)replyToId
         options:(NSDictionary *)options
      completion:(void (^)(NSDictionary *message))completion;

/// Reply quoting only part of the original message. `quoteText` is the exact
/// substring the user selected and `quotePosition` its UTF-16 offset inside the
/// original text; TDLib rejects a quote that no longer matches.
- (void)sendText:(NSString *)text
          toChat:(int64_t)chatId
          thread:(int64_t)threadId
         replyTo:(int64_t)replyToId
       quoteText:(NSString *)quoteText
   quotePosition:(NSInteger)quotePosition
      completion:(void (^)(NSDictionary *message))completion;

/// Reply in a different chat than the one the message lives in - the
/// "Reply in another chat" action. `toChat` is where the reply is posted.
- (void)sendText:(NSString *)text
          toChat:(int64_t)chatId
  replyToMessage:(int64_t)messageId
        fromChat:(int64_t)sourceChatId
      completion:(void (^)(NSDictionary *message))completion;

/// Send several photos as one grouped album bubble. `paths` are local files.
/// The caption, if any, is attached to the first item, which is how Telegram
/// shows an album caption. `completion` gets the flattened messages.
- (void)sendPhotoAlbumAtPaths:(NSArray *)paths
                       toChat:(int64_t)chatId
                      caption:(NSString *)caption
                   completion:(void (^)(NSArray *messages))completion;

/// Insert a message into the local history without sending it anywhere. Used
/// for optimistic echo and for local notices. `senderUserId` of 0 means the
/// signed-in user. `completion` gets the flattened local message.
- (void)addLocalTextMessage:(NSString *)text
                     toChat:(int64_t)chatId
               senderUserId:(int64_t)senderUserId
                    replyTo:(int64_t)replyToId
                 completion:(void (^)(NSDictionary *message))completion;

/// Retry messages whose send failed. `completion` gets the flattened messages
/// TDLib re-queued, or an empty array when none could be retried.
- (void)resendMessages:(NSArray *)messageIds
                inChat:(int64_t)chatId
            completion:(void (^)(NSArray *messages))completion;

/// Delivery state of one message: "sent", "pending" or "failed". `canRetry`
/// is only meaningful for "failed", and drives whether the red badge offers
/// Resend or only Delete.
- (void)sendingStateOfMessage:(int64_t)messageId
                       inChat:(int64_t)chatId
                   completion:(void (^)(NSString *state, BOOL canRetry))completion;

#pragma mark - editing

/// Swap the photo of an already-sent media message for a local file, keeping
/// the message in place. Pass nil for `caption` to keep no caption.
- (void)replacePhotoInMessage:(int64_t)messageId
                       inChat:(int64_t)chatId
                         path:(NSString *)path
                      caption:(NSString *)caption
                   completion:(void (^)(BOOL ok))completion;

/// The same for a video file.
- (void)replaceVideoInMessage:(int64_t)messageId
                       inChat:(int64_t)chatId
                         path:(NSString *)path
                      caption:(NSString *)caption
                   completion:(void (^)(BOOL ok))completion;

/// What a message allows, which is what the long-press action sheet must ask
/// before drawing its rows. Keys, all NSNumber BOOL: "canEdit", "canEditMedia",
/// "canDeleteForMe", "canDeleteForEveryone", "canForward", "canCopy",
/// "canPin", "canReply", "canReplyInAnotherChat", "canGetLink",
/// "canGetEmbeddingCode", "canGetViewers", "canGetReadDate", "canGetThread",
/// "canEditSchedulingState", "canReport", "canSave", "canDeleteReactions",
/// "canReportReactions", "canReportSpam", "canRecognizeSpeech",
/// "canGetStatistics", plus two the action sheet needs that TDLib does not
/// carry on messageProperties: "canSelect" (the message can take part in a
/// multi-selection, i.e. it can be copied, forwarded or deleted) and
/// "canTranslate" (the message has text or a caption to translate).
/// Working out "canTranslate" costs a second, local getMessage read.
/// `completion` gets an empty dictionary when the message is gone.
- (void)propertiesOfMessage:(int64_t)messageId
                     inChat:(int64_t)chatId
                 completion:(void (^)(NSDictionary *properties))completion;

#pragma mark - pinning a message

/// Pin a message at the top of a chat. `silently` YES skips the "pinned a
/// message" notification for everyone else; `onlyForMe` YES pins it for this
/// account alone, which is only allowed in private chats. Check "canPin" from
/// -propertiesOfMessage:inChat:completion: before offering the row.
- (void)pinMessage:(int64_t)messageId
            inChat:(int64_t)chatId
          silently:(BOOL)silently
         onlyForMe:(BOOL)onlyForMe
        completion:(void (^)(BOOL ok))completion;

/// Unpin one message.
- (void)unpinMessage:(int64_t)messageId
              inChat:(int64_t)chatId
          completion:(void (^)(BOOL ok))completion;

/// Unpin every pinned message in a chat - the "Unpin all" confirmation.
- (void)unpinAllMessagesInChat:(int64_t)chatId
                    completion:(void (^)(BOOL ok))completion;

/// The id of the chat's currently pinned message, 0 when there is none.
- (void)pinnedMessageIdInChat:(int64_t)chatId
                   completion:(void (^)(int64_t messageId))completion;

/// Whether this message is the chat's pinned one, so the action sheet can draw
/// Pin or Unpin without the caller tracking the state itself.
- (void)isMessagePinned:(int64_t)messageId
                 inChat:(int64_t)chatId
             completion:(void (^)(BOOL pinned))completion;

#pragma mark - deleting

/// Delete messages. `forEveryone` NO removes them only for this account.
- (void)deleteMessages:(NSArray *)messageIds
                inChat:(int64_t)chatId
           forEveryone:(BOOL)forEveryone
            completion:(void (^)(BOOL ok))completion;

/// Delete everything one member ever posted in a group.
- (void)deleteMessagesFromUser:(int64_t)userId
                        inChat:(int64_t)chatId
                    completion:(void (^)(BOOL ok))completion;

/// Delete a chat's messages inside a date range, inclusive. Dates are unix
/// times; the day picker in the UI supplies the start and end of a day.
- (void)deleteMessagesInChat:(int64_t)chatId
                    fromDate:(NSTimeInterval)minDate
                      toDate:(NSTimeInterval)maxDate
                 forEveryone:(BOOL)forEveryone
                  completion:(void (^)(BOOL ok))completion;

#pragma mark - forwarding

/// Forward with the toggles the forward sheet offers. `asCopy` YES hides the
/// original sender, `removeCaptions` drops media captions, `silent` skips the
/// notification sound. `completion` gets the flattened new messages.
- (void)forwardMessages:(NSArray *)messageIds
               fromChat:(int64_t)fromChatId
                 toChat:(int64_t)toChatId
                 thread:(int64_t)threadId
                 asCopy:(BOOL)asCopy
         removeCaptions:(BOOL)removeCaptions
                 silent:(BOOL)silent
             completion:(void (^)(NSArray *messages))completion;

#pragma mark - drafts

/// Store the compose bar's unsent text on the chat, so it survives leaving the
/// screen and shows in the chat list row. Empty or nil `text` clears it.
- (void)setDraftText:(NSString *)text
             replyTo:(int64_t)replyToId
              inChat:(int64_t)chatId
              thread:(int64_t)threadId;

/// Drop a chat's draft.
- (void)clearDraftInChat:(int64_t)chatId thread:(int64_t)threadId;

/// The stored draft of a chat. `text` is empty when there is none, `replyToId`
/// 0 when the draft was not a reply.
- (void)draftForChat:(int64_t)chatId
          completion:(void (^)(NSString *text, int64_t replyToId))completion;

#pragma mark - scheduling

/// Messages waiting to be sent later in this chat, flattened, with an extra
/// "sendDate" (NSNumber unix time, 0 when it waits for the recipient to come
/// online) and "whenOnline" (NSNumber BOOL).
- (void)scheduledMessagesInChat:(int64_t)chatId
                     completion:(void (^)(NSArray *messages))completion;

/// Move a scheduled message to another moment. `sendDate` of 0 together with
/// `whenOnline` YES means "send when the recipient is next online".
- (void)rescheduleMessage:(int64_t)messageId
                   inChat:(int64_t)chatId
                 sendDate:(NSTimeInterval)sendDate
               whenOnline:(BOOL)whenOnline
               completion:(void (^)(BOOL ok))completion;

/// Send a scheduled message right now, by rescheduling it to this second.
- (void)sendScheduledMessageNow:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(BOOL ok))completion;

#pragma mark - read state

/// Mark messages read, telling TDLib where the user was looking. `source` is
/// "history", "thread", "search" or "notification"; nil means the chat history.
- (void)markRead:(NSArray *)messageIds
          inChat:(int64_t)chatId
          source:(NSString *)source;

/// Clear the mention badge of a chat.
- (void)readAllMentionsInChat:(int64_t)chatId;
/// Clear the unread-reaction badge of a chat.
- (void)readAllReactionsInChat:(int64_t)chatId;

/// When the other side read an outgoing message in a private chat. `status` is
/// "read", "unread", "tooOld", "theirPrivacy" or "myPrivacy"; `date` is the
/// unix time and is 0 unless `status` is "read".
- (void)readDateOfMessage:(int64_t)messageId
                   inChat:(int64_t)chatId
               completion:(void (^)(NSString *status, NSTimeInterval date))completion;

/// Who has seen a message in a small group. Each entry: "id" (NSNumber user
/// id), "name" (NSString) and "date" (NSNumber unix time).
- (void)viewersOfMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
              completion:(void (^)(NSArray *viewers))completion;

#pragma mark - typing indicator

/// Tell the other side what the user is doing. `action` is "typing",
/// "recordingVoice", "uploadingVoice", "recordingVideo", "uploadingVideo",
/// "uploadingPhoto", "uploadingDocument", "choosingSticker",
/// "choosingLocation", "choosingContact" or "cancel". Telegram forgets an
/// action after a few seconds, so a typing indicator has to be repeated.
- (void)sendChatAction:(NSString *)action toChat:(int64_t)chatId thread:(int64_t)threadId;

#pragma mark - links

/// A t.me permalink to a message. `link` is nil when the chat is private and
/// has no public link; `isPublic` says whether anyone can open it.
- (void)linkForMessage:(int64_t)messageId
                inChat:(int64_t)chatId
              inThread:(BOOL)inThread
            completion:(void (^)(NSString *link, BOOL isPublic))completion;

/// Resolve a t.me message link the user tapped or pasted, so the app can jump
/// to it. `chatId` and `messageId` are 0 when the link points nowhere we can
/// open; `message` is the flattened target when TDLib already has it.
- (void)messageLinkInfoForUrl:(NSString *)url
                   completion:(void (^)(int64_t chatId, int64_t messageId,
                                        NSDictionary *message))completion;

/// HTML embed code for a message in a public channel, or nil.
- (void)embeddingCodeForMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSString *html))completion;

#pragma mark - threads

/// The comment thread hanging off a channel post. Keys: "chatId" (the
/// discussion group), "threadId", "replies" (NSNumber), "unread" (NSNumber).
/// `completion` gets nil when the post has no thread.
- (void)threadForMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
              completion:(void (^)(NSDictionary *thread))completion;

#pragma mark - translation

/// Translate arbitrary text, for the compose bar rather than a bubble. To
/// translate a bubble use -translateMessage:inChat:toLanguage:completion: from
/// TGClient+MessageContent.
- (void)translateText:(NSString *)text
           toLanguage:(NSString *)languageCode
           completion:(void (^)(NSString *text))completion;

#pragma mark - bot buttons

/// Press an inline keyboard button under a bot message. `data` is the button's
/// base64 payload exactly as it arrived in the reply markup. `completion` gets
/// the bot's answer: `text` to show, `showAlert` whether it wants a modal
/// rather than a toast, and `url` when the button opens a page instead.
- (void)pressInlineButtonWithData:(NSString *)data
                        onMessage:(int64_t)messageId
                           inChat:(int64_t)chatId
                       completion:(void (^)(NSString *text, BOOL showAlert,
                                            NSString *url))completion;

#pragma mark - reporting

/// Report messages. The flow is multi-step: call with a nil `optionId` first,
/// then again with the id of whichever option the user picked, until the
/// result says "ok". `completion` receives:
///   "status"  "ok", "chooseOption", "needText" or "error"
///   "title"   heading for the option list
///   "options" NSArray of {"id", "text"} to draw as rows
///   "optionId" the option a free-text step belongs to
///   "optional" NSNumber BOOL, whether the free text may be left empty
- (void)reportMessages:(NSArray *)messageIds
                inChat:(int64_t)chatId
              optionId:(NSString *)optionId
                  text:(NSString *)text
            completion:(void (^)(NSDictionary *result))completion;

#pragma mark - quick replies

/// Create a quick-reply shortcut, or append a message to an existing one of
/// that name. TDLib only hands the shortcut list back through updates, which
/// this client does not observe, so a shortcut is addressed by name here and
/// by id once one has been seen. `completion` gets NO when the name is refused.
- (void)addQuickReplyShortcutNamed:(NSString *)name
                              text:(NSString *)text
                        completion:(void (^)(BOOL ok))completion;

/// Send every message of a shortcut into a chat.
- (void)sendQuickReplyShortcut:(NSInteger)shortcutId
                        toChat:(int64_t)chatId
                    completion:(void (^)(NSArray *messages))completion;

@end

// vim:ft=objc

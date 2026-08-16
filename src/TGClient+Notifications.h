//
// TGClient+Notifications - notification settings, scopes, per-chat overrides,
// exceptions, sounds and the local-alert helpers.
//
// TDLib keeps notification settings in two layers. Each scope (private chats,
// groups, channels) has a full set of values; each chat has the same values
// again, but every one of them is paired with a use_default_ flag that says
// "take the scope's value instead". A per-chat row is therefore tri-state:
// default / on / off. This category surfaces both layers as flat
// dictionaries, and offers read-modify-write updaters so the UI can flip a
// single switch without having to resend the whole struct itself.
//
// `scope` is the same short string TGClient already uses elsewhere:
// "private", "groups" or "channels".
//
// Every completion runs on the main queue and may be nil. Failures answer
// nil / NO / an empty array rather than raising.
//
#import "TGClient.h"

/// TDLib has no "muted forever" flag; a very large mute_for is how it is
/// expressed. Pass this where a duration in seconds is wanted, and 0 to unmute.
extern const NSInteger TGNotificationMuteForever;

/// Posted on the main queue when the settings of a scope changed on any
/// device. The scope name ("private"/"groups"/"channels") is the object.
/// Only fires if TGClient's update dispatcher forwards it; the settings
/// getters below are always safe to re-read on view appearance regardless.
extern NSString *const TGScopeNotificationSettingsDidChangeNotification;

extern NSString *const TGNotificationUpdateNotification;

@interface TGClient (Notifications)

#pragma mark - scope settings

/// Full notification settings of one scope. `settings` keys, all NSNumber
/// unless noted: "muted" (BOOL, mute_for > 0), "muteFor" (seconds),
/// "showPreview", "soundId" (int64, 0 when sound is off),
/// "disablePinnedMessageNotifications", "disableMentionNotifications".
/// nil on failure.
- (void)notificationSettingsForScope:(NSString *)scope
                          completion:(void (^)(NSDictionary *settings))completion;

/// Change some values of a scope without touching the rest. `changes` uses
/// the same keys as -notificationSettingsForScope:; keys left out keep their
/// current value. This reads the current settings first, so it is what a
/// single switch row should call. `completion` gets YES when the write went out.
- (void)updateScope:(NSString *)scope
             values:(NSDictionary *)changes
         completion:(void (^)(BOOL ok))completion;

/// Mute or unmute a whole scope for a chosen duration.
/// Pass TGNotificationMuteForever to mute, 0 to unmute.
- (void)setScope:(NSString *)scope muteForSeconds:(NSInteger)seconds;

#pragma mark - per-chat settings

/// Notification settings of one chat, including which values follow the scope
/// default. Keys: "muted", "muteFor", "useDefaultMuteFor", "showPreview",
/// "useDefaultShowPreview", "soundId", "useDefaultSound",
/// "disablePinnedMessageNotifications",
/// "useDefaultDisablePinnedMessageNotifications",
/// "disableMentionNotifications", "useDefaultDisableMentionNotifications",
/// and "defaultDisableNotification" (the chat's own send-silently flag).
/// All NSNumber. nil on failure.
- (void)notificationSettingsForChat:(int64_t)chatId
                         completion:(void (^)(NSDictionary *settings))completion;

/// Mute one chat for a chosen duration: 3600, 8 * 3600, 2 * 24 * 3600 or
/// TGNotificationMuteForever, and 0 to unmute. Overrides the scope default.
- (void)setChat:(int64_t)chatId muteForSeconds:(NSInteger)seconds;

/// Change some per-chat values without touching the rest, reading the chat's
/// current settings first. `changes` uses the keys of
/// -notificationSettingsForChat:; setting a "useDefault..." key to @YES hands
/// that one value back to the scope default. `completion` gets YES when the
/// write went out.
- (void)updateChat:(int64_t)chatId
            values:(NSDictionary *)changes
        completion:(void (^)(BOOL ok))completion;

/// Hand every value of this chat back to its scope default, which is what a
/// "Default" reset row does. Also removes the chat from the exceptions list.
- (void)resetNotificationSettingsForChat:(int64_t)chatId;

/// Messages sent to this chat go out without a sound by default. This is a
/// property of the chat, not of a single message.
- (void)setChat:(int64_t)chatId defaultDisableNotification:(BOOL)silent;

#pragma mark - forum topics

/// Mute one forum topic for a duration, independently of its chat.
/// `topicId` is the topic's message_thread_id.
- (void)setChat:(int64_t)chatId
          topic:(int64_t)topicId
 muteForSeconds:(NSInteger)seconds;

/// Hand a forum topic's notification settings back to the chat default.
- (void)resetNotificationSettingsForChat:(int64_t)chatId topic:(int64_t)topicId;

#pragma mark - exceptions

/// Chats whose settings differ from their scope default. Pass nil for `scope`
/// to get the exceptions of every scope at once. Each entry:
/// "id" (NSNumber chat id), "title", "muted" (NSNumber BOOL),
/// "muteFor" (NSNumber seconds), "showPreview" (NSNumber BOOL).
/// `compareSound` makes a chat with only a different sound count as an
/// exception too; pass NO for the usual list.
- (void)notificationExceptionsForScope:(NSString *)scope
                          compareSound:(BOOL)compareSound
                            completion:(void (^)(NSArray *chats))completion;

/// Reset every exception of one scope (or of all scopes when `scope` is nil)
/// back to the default. `completion` gets the number of chats reset.
- (void)clearNotificationExceptionsForScope:(NSString *)scope
                                 completion:(void (^)(NSInteger resetCount))completion;

/// Reset every notification setting of the account: all scopes and every chat
/// go back to the TDLib defaults. Destructive; confirm before calling.
- (void)resetAllNotificationSettingsWithCompletion:(void (^)(BOOL ok))completion;

#pragma mark - reactions

/// Who may trigger a reaction or poll-vote notification. `source` and
/// `pollVoteSource` are "all", "contacts" or "none". `soundId` is 0 for the
/// default sound. There is no TDLib getter for these, so the UI has to keep
/// the picked values itself (NSUserDefaults) and write the whole struct here.
- (void)setReactionNotificationsSource:(NSString *)source
                        pollVoteSource:(NSString *)pollVoteSource
                           showPreview:(BOOL)showPreview
                               soundId:(long long)soundId;

#pragma mark - sounds

/// Notification sounds saved on the account. Each entry: "id" (NSNumber
/// int64, the sound_id to write into settings), "title", "duration"
/// (NSNumber seconds), "date" (NSNumber unix time), "fileId" (NSNumber, pass
/// to -downloadFile:completion: to preview it). Note that the server stores
/// MP3/OGG, which iOS 6 will not play as an alert sound - previewing works
/// in-app, but a UILocalNotification can only use a bundled CAF.
- (void)savedNotificationSoundsWithCompletion:(void (^)(NSArray *sounds))completion;

/// Upload a local audio file as a saved notification sound. `completion` gets
/// the new sound in the same shape as above, or nil.
- (void)addSavedNotificationSoundAtPath:(NSString *)path
                             completion:(void (^)(NSDictionary *sound))completion;

/// Delete a saved sound by its id.
- (void)removeSavedNotificationSound:(long long)soundId;

#pragma mark - archive settings

/// How new chats from unknown users are treated. Keys, all NSNumber BOOL:
/// "archiveAndMuteNewChatsFromUnknownUsers", "keepUnmutedChatsArchived",
/// "keepChatsFromFoldersArchived". nil on failure.
- (void)archiveChatListSettingsWithCompletion:(void (^)(NSDictionary *settings))completion;

/// Write the archive settings back. `changes` uses the keys above; keys left
/// out keep their current value.
- (void)updateArchiveChatListSettings:(NSDictionary *)changes
                           completion:(void (^)(BOOL ok))completion;

#pragma mark - local alerts

/// Tell TDLib a notification the user has seen may be dropped. Call when a
/// chat is opened, so the same alert does not come back after a restart.
- (void)removeNotification:(NSInteger)notificationId inGroup:(NSInteger)groupId;

/// Drop every notification of a group up to and including `maxNotificationId`.
/// Pass NSIntegerMax to clear the whole group.
- (void)removeNotificationGroup:(NSInteger)groupId
              upToNotificationId:(NSInteger)maxNotificationId;

/// One line of preview text for a TDLib PushMessageContent object, e.g.
/// "Photo", "Voice message", or the text of a plain message. Pure function,
/// safe to call on any queue; answers an empty string for anything unknown.
- (NSString *)previewTextForPushContent:(NSDictionary *)content;

- (NSString *)previewTextForMessageContent:(NSDictionary *)content;

- (NSString *)titleForChatId:(int64_t)chatId;

/// Turn a TDLib "notification" object into what a UILocalNotification needs:
/// "title" (chat or sender name, may be empty), "body", and "chatId"
/// (NSNumber, 0 when the notification does not point at a chat).
/// nil when the notification carries nothing worth showing.
- (NSDictionary *)alertForNotification:(NSDictionary *)notification
                              chatName:(NSString *)chatName;

@end

// vim:ft=objc

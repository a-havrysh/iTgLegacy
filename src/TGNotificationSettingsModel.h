#import <Foundation/Foundation.h>

/// TDLib has no "muted forever" flag. Muting without an end is expressed as a
/// very large mute_for, and TGClient+Notifications writes 365 * 24 * 3600
/// (one year in seconds) for it. Anything at or above this value is a
/// permanent mute; anything between 1 and this value is a timed mute that the
/// server counts down; 0 means not muted at all.
///
/// Screens should test -muteForever rather than comparing seconds themselves.
extern const int64_t TGNotificationSettingsMuteForever;

/// Notification settings, typed.
///
/// One class covers the three shapes TGClient+Notifications vends, because
/// they are the same struct seen from three distances:
///
///  - a scope's settings (-notificationSettingsForScope:completion:), which
///    have no per-value defaults and no chat identity;
///  - a chat's settings (-notificationSettingsForChat:completion:), which add
///    a useDefault... flag beside every value plus the chat's own
///    send-silently flag;
///  - a row of the exceptions list
///    (-notificationExceptionsForScope:compareSound:completion:), which
///    carries a chat id and title but only the muted / muteFor / showPreview
///    values.
///
/// Fields the source shape does not carry read as their documented default,
/// so a screen never has to ask which shape it holds. -scopeSettings tells
/// the three apart when a screen really needs to know.
///
/// Immutable. Nothing is retained from the source dictionary.
@interface TGNotificationSettingsModel : NSObject

#pragma mark - identity

/// TDLib chat id these settings belong to. 0 for scope settings, which are
/// not tied to a chat. Always set for an exceptions row.
@property (nonatomic, readonly) int64_t chatId;

/// Chat title. Optional - nil for scope and per-chat settings, which carry no
/// title; set for an exceptions row unless TDLib sent an empty one.
@property (nonatomic, readonly, copy) NSString *title;

/// YES when this came from a scope, so every useDefault... flag below is NO
/// and means nothing: a scope has nothing to fall back to.
@property (nonatomic, readonly) BOOL scopeSettings;

#pragma mark - mute

/// Notifications for this scope or chat are currently off, i.e. muteFor > 0.
@property (nonatomic, readonly) BOOL muted;

/// Remaining mute duration in seconds. 0 when not muted. See
/// TGNotificationSettingsMuteForever for the permanent-mute convention.
@property (nonatomic, readonly) int64_t muteFor;

/// Muted with no end date, i.e. muteFor >= TGNotificationSettingsMuteForever.
/// NO for a timed mute and for an unmuted chat.
@property (nonatomic, readonly) BOOL muteForever;

/// Muted, but only until a moment that will arrive: muteFor is between 1 and
/// TGNotificationSettingsMuteForever. A screen showing a countdown wants this.
@property (nonatomic, readonly) BOOL mutedTemporarily;

/// The mute state follows the scope default rather than being set on the chat.
/// Always NO for scope settings and for an exceptions row.
@property (nonatomic, readonly) BOOL useDefaultMuteFor;

#pragma mark - preview and sound

/// Show the message text in the alert rather than just the sender.
@property (nonatomic, readonly) BOOL showPreview;

/// The preview state follows the scope default. Always NO for scope settings
/// and for an exceptions row.
@property (nonatomic, readonly) BOOL useDefaultShowPreview;

/// Saved notification sound id, matching the "id" of an entry from
/// -savedNotificationSoundsWithCompletion:. 0 means the default sound, or no
/// sound at all when the account has turned sound off.
@property (nonatomic, readonly) int64_t soundId;

/// The sound follows the scope default. Always NO for scope settings and for
/// an exceptions row, which does not carry a sound at all.
@property (nonatomic, readonly) BOOL useDefaultSound;

#pragma mark - message kinds

/// Pinned-message alerts are suppressed. Note the inverted sense: the switch
/// a settings screen draws is on when this is NO.
@property (nonatomic, readonly) BOOL disablePinnedMessageNotifications;

/// The pinned-message rule follows the scope default.
@property (nonatomic, readonly) BOOL useDefaultDisablePinnedMessageNotifications;

/// Mention and reply alerts are suppressed. Inverted in the same way as
/// disablePinnedMessageNotifications.
@property (nonatomic, readonly) BOOL disableMentionNotifications;

/// The mention rule follows the scope default.
@property (nonatomic, readonly) BOOL useDefaultDisableMentionNotifications;

#pragma mark - chat flags

/// Messages this account sends to the chat go out silently by default. This
/// is a property of the chat, not of the notification struct, and is always
/// NO for scope settings and for an exceptions row.
@property (nonatomic, readonly) BOOL defaultDisableNotification;

#pragma mark - derived

/// Every value follows its scope default, so the chat is not an exception.
/// Always NO for scope settings, which have no defaults to follow.
@property (nonatomic, readonly) BOOL followsScopeDefaults;

/// At least one value is set on the chat itself, so it belongs in the
/// exceptions list. The inverse of followsScopeDefaults for chat settings,
/// and always NO for scope settings.
@property (nonatomic, readonly) BOOL exception;

#pragma mark - building

/// Builds a model from one of the dictionaries TGClient+Notifications vends:
/// scope settings, chat settings, or an exceptions row. The shape is detected
/// from the keys present, so the same call handles all three.
///
/// Returns nil when dict is not a dictionary, or when it carries none of the
/// keys that would make it notification settings at all.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array of exception rows (or of any of the shapes above), dropping
/// entries that fail to build. Returns an empty array when dicts is not an
/// array.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

// vim:ft=objc

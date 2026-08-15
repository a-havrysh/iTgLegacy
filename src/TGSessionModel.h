// TGSessionModel - one signed-in session, typed.
//
// Replaces the untyped dictionaries vended by TGClient -sessionsWithCompletion:,
// TGClient+Privacy -activeSessionsWithCompletion: / -unconfirmedSessionsWithCompletion:
// and TGClient+Account -currentSessionWithCompletion: / -sessionInfoForId:completion:.
//
// +fromDictionary: understands both the raw TDLib `session` object (snake_case
// keys) and every flattened shape those four producers emit today, so a screen
// can be migrated before its producer is.

#import <Foundation/Foundation.h>

@interface TGSessionModel : NSObject

/// TDLib session id. Never zero for a model that exists.
@property (nonatomic, readonly) int64_t sessionId;

/// Application that created the session, e.g. "Telegram iOS". Optional: nil when
/// the producer had nothing to report.
@property (nonatomic, readonly, copy) NSString *applicationName;

/// Application version string. Optional.
@property (nonatomic, readonly, copy) NSString *applicationVersion;

/// Hardware, e.g. "iPhone 4S". Optional.
@property (nonatomic, readonly, copy) NSString *deviceModel;

/// TDLib device class with the "sessionDeviceType" prefix stripped, e.g.
/// "iphone", "Android", "Desktop". Optional.
@property (nonatomic, readonly, copy) NSString *deviceType;

/// Operating system name, e.g. "iOS". Optional. Some producers pre-join this
/// with the system version; in that case the joined text lands here and
/// systemVersion is nil.
@property (nonatomic, readonly, copy) NSString *platform;

/// Operating system version, e.g. "6.1.3". Optional.
@property (nonatomic, readonly, copy) NSString *systemVersion;

/// platform and systemVersion joined with a space, whichever of the two exist.
/// Nil when neither exists. Derived, not stored on the wire.
@property (nonatomic, readonly, copy) NSString *systemDescription;

/// Last known IP address. Optional.
@property (nonatomic, readonly, copy) NSString *ipAddress;

/// Human-readable location guessed from the IP, e.g. "Kyiv, Ukraine". Optional.
@property (nonatomic, readonly, copy) NSString *location;

/// Unix time the session was created. 0 when unknown.
@property (nonatomic, readonly) int64_t loginDate;

/// Unix time of the last activity. 0 when unknown; also 0 for the current
/// session on some producers, which report it as live instead.
@property (nonatomic, readonly) int64_t lastActiveDate;

/// api_id the application registered with. 0 when unknown.
@property (nonatomic, readonly) int64_t apiId;

/// YES for the session this device is running in.
@property (nonatomic, readonly) BOOL isCurrent;

/// YES while Telegram has not confirmed this login yet. Drives the chat list
/// "new login" banner.
@property (nonatomic, readonly) BOOL isUnconfirmed;

/// YES for an official Telegram build.
@property (nonatomic, readonly) BOOL isOfficialApplication;

/// YES when the session is waiting on the two-step password.
@property (nonatomic, readonly) BOOL isPasswordPending;

/// Session detail switch: may this session receive calls.
@property (nonatomic, readonly) BOOL canAcceptCalls;

/// Session detail switch: may this session receive secret chats.
@property (nonatomic, readonly) BOOL canAcceptSecretChats;

/// Application name and version joined, falling back to the name alone, then to
/// nil. What a list row shows as its title.
@property (nonatomic, readonly, copy) NSString *applicationDescription;

/// Builds a model from a TDLib session object or from any flattened session
/// dictionary the client vends. Returns nil when `dict` is not a dictionary or
/// carries no session id.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array of dictionaries, silently dropping entries that fail to build.
/// Never returns nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

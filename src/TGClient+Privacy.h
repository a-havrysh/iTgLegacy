//
// TGClient+Privacy - privacy rules, block list, active sessions, connected
// websites, two-step verification and account self-destruct.
//
// The simple three-way privacy rule accessors (-privacyRule:completion: and
// -setPrivacyRule:to:) already live on TGClient itself; this category adds the
// parts that need exception lists or a reply the UI has to react to.
//
// Every completion runs on the main queue and may be nil. Failures answer with
// nil / NO / 0 rather than an error object: TDLib error text is not useful on
// this hardware, and the screens here are all "did it work" screens.
//
#import "TGClient.h"

@interface TGClient (Privacy)

#pragma mark - privacy rules

/// Every privacy setting name this client offers, without the
/// "userPrivacySetting" prefix, in the order the Privacy screen shows them:
/// ShowStatus, ShowProfilePhoto, ShowBio, ShowPhoneNumber,
/// ShowLinkInForwardedMessages, AllowChatInvites, AllowCalls,
/// AllowPeerToPeerCalls, AllowFindingByPhoneNumber.
+ (NSArray *)privacySettingNames;

/// A human title for one of the names above, e.g. "Last Seen".
+ (NSString *)titleForPrivacySetting:(NSString *)setting;

/// Full state of one privacy rule, including the exception lists.
/// `info` has "value" ("everybody" / "contacts" / "nobody"), "allowedUserIds"
/// and "restrictedUserIds" (NSArray of NSNumber, possibly empty), and
/// "allowedChatIds" / "restrictedChatIds" for rules another client set on
/// whole groups. Nil on failure.
- (void)privacyRuleDetailed:(NSString *)setting
                 completion:(void (^)(NSDictionary *info))completion;

/// Set a privacy rule together with its exception lists. `value` is
/// "everybody", "contacts" or "nobody"; `allowedUserIds` and
/// `restrictedUserIds` are NSArrays of NSNumber user ids and may be nil.
/// The exceptions are written ahead of the base rule, which is what makes
/// "Never Allow" win over "Everybody" the way the modern client behaves.
- (void)setPrivacyRule:(NSString *)setting
                    to:(NSString *)value
          allowedUsers:(NSArray *)allowedUserIds
       restrictedUsers:(NSArray *)restrictedUserIds
            completion:(void (^)(BOOL ok))completion;

#pragma mark - block list

/// Block or unblock a user and hear whether it took. The fire-and-forget
/// -setUser:blocked: on TGClient is fine for a profile toggle; use this one
/// when a list row has to be removed only after the server agreed.
- (void)setUser:(int64_t)userId
        blocked:(BOOL)blocked
     completion:(void (^)(BOOL ok))completion;

/// Blocked senders with paging, for a list longer than one screenful.
/// Each entry: "id" (NSNumber, negative for a chat), "name", "isChat"
/// (NSNumber BOOL). `total` is the whole count, not the page.
- (void)blockedSendersFromOffset:(NSInteger)offset
                           limit:(NSInteger)limit
                      completion:(void (^)(NSArray *senders, NSInteger total))completion;

#pragma mark - sessions

/// Every session signed into this account, richer than TGClient's own
/// -sessionsWithCompletion:. Each entry: "id" (NSNumber int64), "appName",
/// "appVersion", "deviceModel", "platform" (platform + system version),
/// "ip", "location", "isCurrent", "isOfficial", "isUnconfirmed",
/// "canAcceptCalls", "canAcceptSecretChats" (all NSNumber BOOL),
/// "loginDate" and "lastActive" (NSNumber, unix time).
/// `inactiveTtlDays` is the auto-terminate period the Sessions screen shows.
- (void)activeSessionsWithCompletion:(void (^)(NSArray *sessions, NSInteger inactiveTtlDays))completion;

/// Sessions Telegram has not confirmed yet, same shape as above. Drives the
/// yellow "new login" banner; empty most of the time.
- (void)unconfirmedSessionsWithCompletion:(void (^)(NSArray *sessions))completion;

/// Kill one session. Fire-and-forget lives on TGClient; this one reports back.
- (void)terminateSession:(long long)sessionId completion:(void (^)(BOOL ok))completion;

/// Kill every session except this device's.
- (void)terminateAllOtherSessionsWithCompletion:(void (^)(BOOL ok))completion;

/// Accept a session the banner is asking about.
- (void)confirmSession:(long long)sessionId completion:(void (^)(BOOL ok))completion;

/// The two switches on a session's detail screen. Pass NSNull-free plain
/// BOOLs; both are written, so read the current values first.
- (void)setSession:(long long)sessionId
    canAcceptCalls:(BOOL)canAcceptCalls
  canAcceptSecrets:(BOOL)canAcceptSecretChats
        completion:(void (^)(BOOL ok))completion;

/// Days of inactivity after which a session terminates itself. Telegram
/// accepts 7, 30, 90 and 180.
- (void)setInactiveSessionTtlDays:(NSInteger)days completion:(void (^)(BOOL ok))completion;

#pragma mark - connected websites

/// Sites signed in with Telegram Login. Each entry: "id" (NSNumber int64),
/// "domain", "botName", "browser", "platform", "ip", "location",
/// "lastActive" (NSNumber, unix time).
- (void)connectedWebsitesWithCompletion:(void (^)(NSArray *websites))completion;

- (void)disconnectWebsite:(long long)websiteId completion:(void (^)(BOOL ok))completion;
- (void)disconnectAllWebsitesWithCompletion:(void (^)(BOOL ok))completion;

#pragma mark - two-step verification

/// State of the 2SV password. `state` has "hasPassword" (NSNumber BOOL),
/// "hint", "hasRecoveryEmail" (NSNumber BOOL), "recoveryEmailPattern"
/// (NSString, empty unless a code is pending), "recoveryCodeLength"
/// (NSNumber), "loginEmailPattern", and "pendingResetDate" (NSNumber, unix
/// time, 0 when no reset is running). Nil on failure.
- (void)passwordStateWithCompletion:(void (^)(NSDictionary *state))completion;

/// Turn 2SV on, or change the password. `oldPassword` is nil the first time.
/// `recoveryEmail` may be nil to skip setting one. `state` is the same shape
/// as -passwordStateWithCompletion:, or nil when the old password was wrong;
/// when it comes back with a non-empty "recoveryEmailPattern" the email needs
/// a code, so push the code screen and finish with
/// -checkRecoveryEmailCode:completion:.
- (void)setPasswordWithOldPassword:(NSString *)oldPassword
                       newPassword:(NSString *)newPassword
                              hint:(NSString *)hint
                     recoveryEmail:(NSString *)recoveryEmail
                        completion:(void (^)(NSDictionary *state))completion;

/// Turn 2SV off. Wrong password answers NO.
- (void)disablePasswordWithOldPassword:(NSString *)oldPassword
                            completion:(void (^)(BOOL ok))completion;

/// The recovery email currently on file; needs the password. Nil on failure.
- (void)recoveryEmailWithPassword:(NSString *)password
                       completion:(void (^)(NSString *email))completion;

/// Point recovery at a new address. The reply carries the pending code info,
/// same shape as -passwordStateWithCompletion:.
- (void)setRecoveryEmail:(NSString *)email
                password:(NSString *)password
              completion:(void (^)(NSDictionary *state))completion;

/// Confirm the code mailed to the recovery address.
- (void)checkRecoveryEmailCode:(NSString *)code
                    completion:(void (^)(NSDictionary *state))completion;

/// Send that code again.
- (void)resendRecoveryEmailCodeWithCompletion:(void (^)(NSDictionary *state))completion;

#pragma mark - forgotten password, at the login screen

/// "Forgot password?" - asks Telegram to mail a recovery code.
/// `emailPattern` is the masked address to show ("a**@g****.com"), nil on
/// failure; `codeLength` is how many digits the entry field wants.
- (void)requestPasswordRecoveryWithCompletion:(void (^)(NSString *emailPattern, NSInteger codeLength))completion;

/// Use the mailed code to set a brand new password. `hint` may be nil.
- (void)recoverPasswordWithCode:(NSString *)code
                    newPassword:(NSString *)newPassword
                           hint:(NSString *)hint
                     completion:(void (^)(BOOL ok))completion;

/// Give up on the password and reset it, which Telegram only allows after a
/// waiting period. `result` is "ok" (the password is gone), "pending" (the
/// wait has started, `date` is when it ends), "declined" (`date` is when it
/// may be asked again) or nil on failure.
- (void)resetPasswordWithCompletion:(void (^)(NSString *result, NSInteger date))completion;

/// Call off a pending reset.
- (void)cancelPasswordResetWithCompletion:(void (^)(BOOL ok))completion;

#pragma mark - account

/// Default self-destruct timer applied to new chats, in seconds; 0 is off.
- (void)defaultAutoDeleteSecondsWithCompletion:(void (^)(NSInteger seconds))completion;
- (void)setDefaultAutoDeleteSeconds:(NSInteger)seconds completion:(void (^)(BOOL ok))completion;

/// Delete this Telegram account for good. `reason` is the free-text the user
/// typed and may be nil; `password` is the 2SV password, needed only when 2SV
/// is on, otherwise nil.
- (void)deleteAccountWithReason:(NSString *)reason
                       password:(NSString *)password
                     completion:(void (^)(BOOL ok))completion;

#pragma mark - reporting

/// Report a chat, or particular messages in it, for abuse. Telegram drives
/// this as a small wizard: call it first with a nil `optionId`, and the reply
/// tells you what it still needs.
/// `result` keys: "status" - "ok" (done), "options" (show the list), "text"
/// (ask for a comment), "messages" (make the user pick messages); "title"
/// and "options" (NSArray of {"id", "text"}) when status is "options";
/// "optionId" and "optional" (NSNumber BOOL) when status is "text".
/// Nil on failure. Feed the chosen option's "id" back in as `optionId`.
- (void)reportChat:(int64_t)chatId
        messageIds:(NSArray *)messageIds
          optionId:(NSString *)optionId
              text:(NSString *)text
        completion:(void (^)(NSDictionary *result))completion;

@end

// vim:ft=objc

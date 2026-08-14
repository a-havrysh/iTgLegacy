//
// TGClient+Account - the login flow beyond the three steps TGClient already
// has, plus everything that edits the signed-in account itself.
//
// TGClient owns the bare state machine (-sendPhoneNumber:, -sendCode:,
// -sendPassword:, -logOut) and TGClient+Privacy owns sessions, two-step
// verification and account deletion. This category fills the gaps: country
// list and phone formatting, code type / timeout / resend, registration,
// QR login in both directions, email as a login factor, changing our own
// phone number, and the editable parts of our own profile.
//
// Every completion runs on the main queue and may be nil. Failures answer
// with nil / NO / 0 rather than an error object, matching the rest of the
// client: TDLib error text is not something these screens can act on.
//
#import "TGClient.h"

@interface TGClient (Account)

#pragma mark - countries and phone numbers

/// Every country Telegram knows, for the country picker. Each entry:
/// "code" (ISO two-letter, e.g. "CH"), "name" (localised), "englishName",
/// "flag" (emoji, useless on this OS but harmless), "callingCodes"
/// (NSArray of NSString without the "+"). Hidden countries are dropped.
/// Empty array on failure.
- (void)countriesWithCompletion:(void (^)(NSArray *countries))completion;

/// ISO country code Telegram guesses for this device from its IP, e.g. "CH".
/// Used to preselect a row in the country picker. Nil on failure.
- (void)guessedCountryCodeWithCompletion:(void (^)(NSString *countryCode))completion;

/// Country and formatting for a phone number or number prefix, as the user
/// types. `info` has "countryCode", "countryName", "callingCode" (without
/// "+") and "formatted" (the number grouped the way that country writes it).
/// Nil when the prefix matches no country yet.
/// TDLib also offers a synchronous variant of this; it needs
/// td_json_client_execute, which this client does not expose, so this one is
/// a normal round trip and must not be called on every keystroke.
- (void)phoneNumberInfo:(NSString *)phoneNumberPrefix
             completion:(void (^)(NSDictionary *info))completion;

/// Language pack id Telegram suggests for a country ("de", "ru", ...), so the
/// login screen can switch localisation after the country is picked.
/// Nil when Telegram has no preference.
- (void)preferredLanguageForCountry:(NSString *)countryCode
                         completion:(void (^)(NSString *languageCode))completion;

#pragma mark - login: phone number and code

/// Hand Telegram the phone number, with the authentication settings this
/// hardware can honour. TGClient's -sendPhoneNumber: is the fire-and-forget
/// version that also survives being called before TDLib is up; use this one
/// when the login screen has to show a spinner and then an error.
/// `isCurrentNumber` is YES only when the number was filled in for the user
/// rather than typed. `ok` NO means the number was rejected.
- (void)startLoginWithPhoneNumber:(NSString *)phoneNumber
                  isCurrentNumber:(BOOL)isCurrentNumber
                       completion:(void (^)(BOOL ok))completion;

/// What the code screen has to say, read back out of the authorization state.
/// `info` has "phone" (the number the code went to), "type" (raw TDLib type
/// name), "description" (ready-to-show text such as "We sent the code to
/// your Telegram app" or "We called +41 79 ..."), "length" (NSNumber, digits
/// expected, 0 when the type has no fixed length), "timeout" (NSNumber,
/// seconds until a resend is allowed, drives the countdown), "nextType"
/// (raw type name, empty when nothing else is available) and
/// "nextDescription" (button title, e.g. "Call me" / "Send code via SMS").
/// Nil when the client is not on the code step.
- (void)authenticationCodeInfoWithCompletion:(void (^)(NSDictionary *info))completion;

/// Ask for the code again, which promotes it to "nextType". Pass
/// `verificationFailedMessage` when resending because the previous code was
/// wrong, otherwise nil. `info` is the fresh code info, same shape as above.
- (void)resendAuthenticationCodeWithFailureMessage:(NSString *)verificationFailedMessage
                                        completion:(void (^)(NSDictionary *info))completion;

/// "The code never arrived" - tells Telegram the SMS did not land.
/// `mobileNetworkCode` is the MNC of the SIM, or nil when unknown.
- (void)reportAuthenticationCodeMissing:(NSString *)mobileNetworkCode
                             completion:(void (^)(BOOL ok))completion;

#pragma mark - login: registration

/// Terms of service the registration step has to show. `terms` has "text"
/// (plain string, entities dropped), "minUserAge" (NSNumber, 0 when none) and
/// "showPopup" (NSNumber BOOL - present it as an alert that must be accepted
/// before the name fields become usable). Nil unless the client is waiting
/// for registration.
- (void)registrationTermsWithCompletion:(void (^)(NSDictionary *terms))completion;

/// Finish signing up a brand new account. `lastName` may be nil.
/// Accepting the terms is implicit in this call.
- (void)registerWithFirstName:(NSString *)firstName
                     lastName:(NSString *)lastName
                   completion:(void (^)(BOOL ok))completion;

/// Accept updated terms of service pushed at us after login. `termsId` comes
/// from an updateTermsOfService update, not from -registrationTermsWithCompletion:.
- (void)acceptTermsOfService:(NSString *)termsId completion:(void (^)(BOOL ok))completion;

#pragma mark - login: QR code

/// Log in on this device by showing a QR code that another, already signed-in
/// device scans. `link` is the "tg://login?token=..." URL to render; nil on
/// failure. The link expires, so re-read it with -qrCodeLoginLinkWithCompletion:
/// and redraw whenever the authorization state changes.
- (void)requestQrCodeLoginWithCompletion:(void (^)(NSString *link))completion;

/// Current QR login link, without asking for a new one. Nil when the client
/// is not on the QR step (which is also how you learn the scan succeeded).
- (void)qrCodeLoginLinkWithCompletion:(void (^)(NSString *link))completion;

/// The other side of the same feature: this device is already signed in and
/// has scanned a QR code shown by a device that wants to log in. `session`
/// describes the device being authorised, so the confirm sheet can name it:
/// "id" (NSNumber int64), "appName", "deviceModel", "platform", "ip",
/// "location". Nil when the link was invalid or expired.
- (void)confirmQrCodeLogin:(NSString *)link
                completion:(void (^)(NSDictionary *session))completion;

#pragma mark - login: email address as second factor

/// Attach an email address during login. `pattern` is the masked address to
/// show above the code field ("a**@g****.com"), `codeLength` how many
/// characters the field wants. `pattern` nil means the address was rejected.
- (void)setAuthenticationEmailAddress:(NSString *)emailAddress
                           completion:(void (^)(NSString *pattern, NSInteger codeLength))completion;

/// Check the code mailed to that address.
- (void)checkAuthenticationEmailCode:(NSString *)code
                          completion:(void (^)(BOOL ok))completion;

/// State of the email step, for the screen that offers "reset email address".
/// `info` has "pattern" and "codeLength" as above plus "resetState"
/// ("available" - the button may be tapped now, "pending" - still waiting,
/// or "" - resetting is not offered), "waitPeriod" (NSNumber seconds the
/// reset will take, when available) and "resetIn" (NSNumber seconds left,
/// when pending). Nil when the client is not on the email code step.
- (void)authenticationEmailStateWithCompletion:(void (^)(NSDictionary *info))completion;

/// Give up on the login email address and fall back to the phone code.
- (void)resetAuthenticationEmailAddressWithCompletion:(void (^)(BOOL ok))completion;

#pragma mark - login: forgotten two-step password

/// "Forgot password?" on the login password screen. Mails a recovery code to
/// the address on file. The equivalent inside Settings lives on
/// TGClient+Privacy; this one only works while signed out.
- (void)requestAuthenticationPasswordRecoveryWithCompletion:(void (^)(BOOL ok))completion;

/// Verify a recovery code before asking for a new password, so the new
/// password screen is never shown for a code that will be refused.
- (void)checkAuthenticationPasswordRecoveryCode:(NSString *)recoveryCode
                                     completion:(void (^)(BOOL ok))completion;

/// Set a new password with a verified recovery code and finish logging in.
/// `newHint` may be nil.
- (void)recoverAuthenticationPasswordWithCode:(NSString *)recoveryCode
                                  newPassword:(NSString *)newPassword
                                      newHint:(NSString *)newHint
                                   completion:(void (^)(BOOL ok))completion;

#pragma mark - changing our own phone number

/// Start "Change Number": sends a code to the new number. `info` is the same
/// shape as -authenticationCodeInfoWithCompletion:, so the login code screen
/// can be reused as is. Nil when the number was refused (already taken,
/// banned, flood wait).
- (void)sendChangePhoneNumberCode:(NSString *)phoneNumber
                       completion:(void (^)(NSDictionary *info))completion;

/// Confirm the change with the code that arrived at the new number.
- (void)checkChangePhoneNumberCode:(NSString *)code
                        completion:(void (^)(BOOL ok))completion;

/// Resend that code. `info` is the refreshed code info, nil on failure.
- (void)resendChangePhoneNumberCodeWithCompletion:(void (^)(NSDictionary *info))completion;

/// Tell Telegram the change-number SMS never arrived.
- (void)reportChangePhoneNumberCodeMissing:(NSString *)mobileNetworkCode
                                completion:(void (^)(BOOL ok))completion;

#pragma mark - login email address, from Settings

/// Set or change the login email of an account that is already signed in.
/// `pattern` and `codeLength` describe the confirmation code, nil pattern on
/// failure. Reading the current address is part of
/// -passwordStateWithCompletion: on TGClient+Privacy ("loginEmailPattern").
- (void)setLoginEmailAddress:(NSString *)emailAddress
                  completion:(void (^)(NSString *pattern, NSInteger codeLength))completion;

- (void)resendLoginEmailAddressCodeWithCompletion:(void (^)(NSString *pattern, NSInteger codeLength))completion;

- (void)checkLoginEmailAddressCode:(NSString *)code completion:(void (^)(BOOL ok))completion;

#pragma mark - generic email verification

/// The plain "prove you own this address" flow, used by support and passport
/// screens. Unrelated to the login email above.
- (void)sendEmailAddressVerificationCode:(NSString *)emailAddress
                              completion:(void (^)(NSString *pattern, NSInteger codeLength))completion;

- (void)resendEmailAddressVerificationCodeWithCompletion:(void (^)(NSString *pattern, NSInteger codeLength))completion;

- (void)checkEmailAddressVerificationCode:(NSString *)code completion:(void (^)(BOOL ok))completion;

#pragma mark - our own profile

/// Usernames on our account. `info` has "editable" (the main one, may be
/// empty), "active" (NSArray of NSString, the ones that resolve, editable
/// one included) and "disabled" (NSArray of NSString). Nil on failure.
/// Setting the editable username is -setUsername:completion: on TGClient.
- (void)usernamesWithCompletion:(void (^)(NSDictionary *info))completion;

/// Per-row switch in the username list.
- (void)setUsername:(NSString *)username
             active:(BOOL)active
         completion:(void (^)(BOOL ok))completion;

/// Persist a drag-reorder of the active usernames. `usernames` must contain
/// exactly the active ones, in the new order.
- (void)reorderActiveUsernames:(NSArray *)usernames completion:(void (^)(BOOL ok))completion;

/// Replace our profile photo with a JPEG already on disk.
- (void)setProfilePhotoAtPath:(NSString *)path completion:(void (^)(BOOL ok))completion;

/// Our profile photos, newest first, for the avatar gallery. Each entry:
/// "id" (NSNumber int64, pass to -deleteProfilePhoto:completion:),
/// "fileId" (NSNumber, the big size, feed to -downloadFile:completion:),
/// "smallFileId" (NSNumber), "date" (NSNumber, unix time).
- (void)profilePhotosWithCompletion:(void (^)(NSArray *photos))completion;

/// Remove one profile photo. Pass 0 to drop the current one.
- (void)deleteProfilePhoto:(long long)photoId completion:(void (^)(BOOL ok))completion;

/// Our public link. `url` is the https://t.me/... form to copy, share or
/// render as a QR code; `expiresIn` is seconds until it stops working
/// (0 means it does not expire, which is the case when we have a username).
- (void)publicLinkWithCompletion:(void (^)(NSString *url, NSInteger expiresIn))completion;

/// Resolve a temporary link token scanned from someone else's profile QR
/// code. `user` has "id" (NSNumber int64), "name" and "username". Nil when
/// the token is unknown or expired.
- (void)searchUserByToken:(NSString *)token
               completion:(void (^)(NSDictionary *user))completion;

/// Birthday shown on our profile. `year` may be 0 to keep it private.
- (void)setBirthdateDay:(NSInteger)day
                  month:(NSInteger)month
                   year:(NSInteger)year
             completion:(void (^)(BOOL ok))completion;

/// Clear the birthday.
- (void)clearBirthdateWithCompletion:(void (^)(BOOL ok))completion;

/// Channel or group featured on our profile. Pass 0 to remove it.
- (void)setPersonalChat:(int64_t)chatId completion:(void (^)(BOOL ok))completion;

@end

// vim:ft=objc

/**
 * TGClient+Contacts - contacts, address-book import, close friends and the
 * profile fields that hang off a user record.
 *
 * Every completion runs on the main queue and may be nil. Users come back
 * flattened the way the rest of TGClient shapes them:
 *   "id", "first_name", "last_name", "phone", "username", "photoFileId"
 *   (NSNumber or NSNull), "isContact", "isMutualContact", "isCloseFriend",
 *   "isPremium" (NSNumber BOOL).
 */
#import "TGClient.h"

/// Posted whenever this client adds, renames or removes a contact, so any list
/// showing contacts can reload itself.
extern NSString *const TGContactsDidChangeNotification;

@interface TGClient (Contacts)

#pragma mark - contact list

/// Search the user's own Telegram contacts by name or username.
/// `completion` gets an array of flattened users, empty when nothing matched.
- (void)searchContacts:(NSString *)query
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *users))completion;

/// Add a user you already know the id of to the contact list, optionally
/// letting them see your phone number. `phone` may be empty when the user was
/// found by username. `completion` gets NO when Telegram refused.
- (void)addContactWithUserId:(int64_t)userId
                       phone:(NSString *)phone
                   firstName:(NSString *)firstName
                    lastName:(NSString *)lastName
            sharePhoneNumber:(BOOL)share
                  completion:(void (^)(BOOL ok))completion;

/// Import one address-book entry that has no known user id yet. `completion`
/// gets the Telegram user id the number resolved to, or 0 when the number has
/// no account (or the request failed).
- (void)importContactWithPhone:(NSString *)phone
                     firstName:(NSString *)firstName
                      lastName:(NSString *)lastName
                    completion:(void (^)(int64_t userId))completion;

/// Drop users from the contact list. `userIds` is an array of NSNumber ids.
- (void)removeContacts:(NSArray *)userIds completion:(void (^)(BOOL ok))completion;

/// Give a user your phone number after they asked for it - the banner shown
/// when userFullInfo said need_phone_number_privacy_exception.
- (void)sharePhoneNumberWithUser:(int64_t)userId;

/// Contact-relationship flags for one user, without the caller having to know
/// the user record: "isContact", "isMutualContact", "isCloseFriend",
/// "isPremium", "isSupport" (all NSNumber BOOL). Nil if the user is unknown.
- (void)contactFlagsForUser:(int64_t)userId
                 completion:(void (^)(NSDictionary *flags))completion;

#pragma mark - address book

/// Push the device address book to Telegram and replace whatever was imported
/// before, which is what a "Sync contacts" switch turning on should do.
/// `contacts` is an array of dictionaries with "phone", "first_name" and
/// "last_name". `completion` gets the ids (NSNumber) of the entries that turned
/// out to be Telegram users; entries with no account come back as 0.
- (void)syncImportedContacts:(NSArray *)contacts
                  completion:(void (^)(NSArray *userIds))completion;

/// Import contacts without discarding the previous import - the one-time
/// prompt on first Contacts tab open. Same result shape as -syncImportedContacts:.
- (void)importContacts:(NSArray *)contacts
            completion:(void (^)(NSArray *userIds))completion;

/// How many address-book entries Telegram is currently holding for this account.
- (void)importedContactCountWithCompletion:(void (^)(NSInteger count))completion;

/// Forget every imported address-book entry - "Delete synced contacts".
- (void)clearImportedContactsWithCompletion:(void (^)(BOOL ok))completion;

#pragma mark - finding people

/// Resolve a t.me temporary contact token (the one behind an add-me QR code)
/// to a user. `completion` gets a flattened user, or nil.
- (void)userForToken:(NSString *)token
          completion:(void (^)(NSDictionary *user))completion;

/// A temporary "add me" link for the signed-in user, for a QR code or a share
/// sheet. `completion` gets the https URL and the seconds until it expires,
/// or nil and 0.
- (void)myContactLinkWithCompletion:(void (^)(NSString *url, NSInteger expiresIn))completion;

#pragma mark - close friends

/// The close-friends subset of the contact list, as flattened users. Named
/// apart from TGClient+Stories' -closeFriendsWithCompletion:, which returns a
/// different user shape and would collide as a second implementation.
- (void)contactCloseFriendsWithCompletion:(void (^)(NSArray *users))completion;

/// Replace the whole close-friends list. `userIds` is an array of NSNumber ids;
/// pass an empty array to clear it.
- (void)setCloseFriends:(NSArray *)userIds completion:(void (^)(BOOL ok))completion;

/// Add or remove one user without the caller rebuilding the list. Reads the
/// current list first, so it costs two round trips.
- (void)setUser:(int64_t)userId closeFriend:(BOOL)closeFriend
     completion:(void (^)(BOOL ok))completion;

#pragma mark - own usernames

/// Usernames of the signed-in account: "active" (NSArray of NSString, in the
/// order they are shown), "disabled" (NSArray), "editable" (NSString, the one
/// the Edit Profile field writes to; empty when none).
- (void)myUsernamesWithCompletion:(void (^)(NSDictionary *usernames))completion;

/// Switch one of the account's usernames on or off.
- (void)toggleUsername:(NSString *)username active:(BOOL)active
            completion:(void (^)(BOOL ok))completion;

/// Whether a username may be taken, before the field is saved. `status` is one
/// of "ok", "invalid", "occupied", "purchasable", "too_many", "unavailable"
/// or "error", ready to pick a message from.
- (void)checkUsernameAvailable:(NSString *)username
                    completion:(void (^)(NSString *status))completion;

#pragma mark - profile photos

/// Set the signed-in user's profile photo from a local file. `isPublic` puts it
/// on the profile everyone sees rather than only contacts.
- (void)setMyProfilePhotoAtPath:(NSString *)path
                       isPublic:(BOOL)isPublic
                     completion:(void (^)(BOOL ok))completion;

/// Remove one of the signed-in user's profile photos, by the id that
/// -profilePhotosForUser:... returned in "photoId".
- (void)deleteMyProfilePhoto:(long long)photoId completion:(void (^)(BOOL ok))completion;

/// A user's profile photo history, newest first, for a paged viewer. Each entry
/// has "photoId" (NSNumber, int64), "date" (NSNumber unix time), "fileId"
/// (NSNumber, the largest size) and "smallFileId" (NSNumber). `completion` also
/// gets the total the server holds.
- (void)profilePhotosForUser:(int64_t)userId
                      offset:(NSInteger)offset
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *photos, NSInteger total))completion;

/// Set a photo that only you see for a contact ("Set Photo for <name>"), or
/// suggest one to them when `suggest` is YES.
- (void)setPersonalPhotoAtPath:(NSString *)path
                       forUser:(int64_t)userId
                       suggest:(BOOL)suggest
                    completion:(void (^)(BOOL ok))completion;

/// Drop the personal photo you had set for a contact.
- (void)removePersonalPhotoForUser:(int64_t)userId completion:(void (^)(BOOL ok))completion;

#pragma mark - birthdays

/// Set the signed-in user's birthdate. Pass 0 for `year` when it is not shared;
/// pass 0 for `day` to clear the birthdate entirely.
- (void)setMyBirthdateDay:(NSInteger)day
                    month:(NSInteger)month
                     year:(NSInteger)year
               completion:(void (^)(BOOL ok))completion;

/// Ask a contact to publish their birthdate, prefilled with what you think it
/// is. Posts a service message with an Accept button in their chat.
- (void)suggestBirthdateToUser:(int64_t)userId
                           day:(NSInteger)day
                         month:(NSInteger)month
                          year:(NSInteger)year
                    completion:(void (^)(BOOL ok))completion;

/// Birthdate of a user as a display dictionary: "day", "month", "year"
/// (NSNumber; year 0 when hidden) and "text" ("14 August"). Nil when unset.
- (void)birthdateForUser:(int64_t)userId
              completion:(void (^)(NSDictionary *birthdate))completion;

/// Dismiss the "birthdays today" section at the top of the Contacts tab. The
/// section's contents arrive in TDLib's updateContactCloseBirthdays, which the
/// update dispatcher in TGClient.m has to surface.
- (void)hideContactCloseBirthdays;

#pragma mark - profile extras

/// Free-form private note kept about a contact, or empty. Only you see it.
- (void)noteForUser:(int64_t)userId completion:(void (^)(NSString *note))completion;
- (void)setNote:(NSString *)note forUser:(int64_t)userId completion:(void (^)(BOOL ok))completion;

/// Groups you and a user are both in. Each entry: "id" (NSNumber chat id) and
/// "title".
- (void)groupsInCommonWithUser:(int64_t)userId
                    completion:(void (^)(NSArray *chats))completion;

/// Channels of yours that may be shown on your profile: "id" and "title".
- (void)suitablePersonalChatsWithCompletion:(void (^)(NSArray *chats))completion;

/// The channel a user shows on their profile, or 0.
- (void)personalChatForUser:(int64_t)userId completion:(void (^)(int64_t chatId))completion;

/// Which tab a profile opens on. `tab` is a bare name: "posts", "gifts",
/// "media", "files", "links", "music", "voice" or "gifs".
- (void)setMainProfileTab:(NSString *)tab completion:(void (^)(BOOL ok))completion;

/// The same name for a user's profile, or nil when they set none.
- (void)mainProfileTabForUser:(int64_t)userId completion:(void (^)(NSString *tab))completion;

#pragma mark - support

/// Telegram's support account, for an "Ask a Question" row: "userId"
/// (NSNumber), "chatId" (NSNumber, ready to open) and "name" (the support
/// person's display name, may be empty). Nil when support is unavailable.
- (void)supportContactWithCompletion:(void (^)(NSDictionary *support))completion;

@end

// vim:ft=objc

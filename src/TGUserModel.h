#import <Foundation/Foundation.h>

/// Which of TDLib's UserStatus variants a user is in. `TGUserStatusUnknown`
/// covers both a missing status and a variant this build does not know.
typedef enum {
	TGUserStatusUnknown = 0,
	TGUserStatusEmpty,
	TGUserStatusOnline,
	TGUserStatusOffline,
	TGUserStatusRecently,
	TGUserStatusLastWeek,
	TGUserStatusLastMonth
} TGUserStatusKind;

/// A Telegram user, converted once from a TDLib dictionary.
///
/// Accepts either shape a screen sees today:
///   - a raw TDLib `user` object, as -userInfo: and getUser return it;
///   - a flattened contact row, as -contactsWithCompletion: builds it
///     ("id", "first_name", "phone", "username", "photoFileId",
///      "statusText", "statusRank", "isOnline").
/// Where both shapes carry a field the raw key wins, and the flattened key is
/// the fallback, so one model serves every producer.
///
/// Immutable. Nothing here fetches, and nothing here knows a screen exists.
@interface TGUserModel : NSObject

#pragma mark - identity

/// Telegram user id. Never 0 for a model that was built.
@property (nonatomic, readonly) int64_t userId;

/// Optional. Nil when the producer sent nothing or an empty string.
@property (nonatomic, readonly, copy) NSString *firstName;
/// Optional.
@property (nonatomic, readonly, copy) NSString *lastName;
/// First and last joined with a space, falling back to the username and then
/// to nil. Optional: a user with no name at all has none.
@property (nonatomic, readonly, copy) NSString *displayName;

/// Optional. Digits only as TDLib sends them, with no leading "+".
@property (nonatomic, readonly, copy) NSString *phoneNumber;

/// Optional. The first active username, or the editable one, or the plain
/// "username" key a flattened row carries. Never has a leading "@".
@property (nonatomic, readonly, copy) NSString *username;

#pragma mark - presence

/// Which status variant TDLib reported.
@property (nonatomic, readonly) TGUserStatusKind statusKind;

/// YES only for `userStatusOnline`.
@property (nonatomic, readonly) BOOL isOnline;

/// The line shown under the name, e.g. "online" or "last seen recently".
///
/// Optional, and deliberately so: for `userStatusOffline` the line needs a
/// formatted date, and formatting is not a model's job. In that case this is
/// nil and the caller uses -wasOnlineDate, UNLESS the source dictionary was a
/// flattened row that already carried "statusText", which is passed through.
@property (nonatomic, readonly, copy) NSString *statusText;

/// Unix time of the last time the user was seen, for `userStatusOffline`.
/// 0 for every other status.
@property (nonatomic, readonly) int64_t wasOnlineDate;

/// Sort key matching the one -contactsWithCompletion: produces: online is
/// highest, then the offline timestamp, then recently/week/month/long-ago as
/// 3/2/1/0. Comparable across users; not meaningful as a date.
@property (nonatomic, readonly) int64_t statusRank;

#pragma mark - photo

/// Small (list-sized) profile photo file id, or nil when the user has none.
/// Optional.
@property (nonatomic, readonly, copy) NSNumber *photoFileId;
/// Big (profile-sized) photo file id, or nil. Optional; a flattened row never
/// carries it.
@property (nonatomic, readonly, copy) NSNumber *bigPhotoFileId;
/// Remote unique id of the small photo, stable across file ids, for cache
/// keys. Optional.
@property (nonatomic, readonly, copy) NSString *photoUniqueId;

#pragma mark - flags

@property (nonatomic, readonly) BOOL isContact;
@property (nonatomic, readonly) BOOL isMutualContact;
/// Telegram's "close friend" marking, used by stories privacy.
@property (nonatomic, readonly) BOOL isCloseFriend;
@property (nonatomic, readonly) BOOL isPremium;
/// From `verification_status.is_verified`, with the older top-level
/// `is_verified` accepted as a fallback.
@property (nonatomic, readonly) BOOL isVerified;
@property (nonatomic, readonly) BOOL isScam;
@property (nonatomic, readonly) BOOL isFake;
@property (nonatomic, readonly) BOOL isSupport;
/// YES for `userTypeBot`.
@property (nonatomic, readonly) BOOL isBot;
/// YES for `userTypeDeleted`.
@property (nonatomic, readonly) BOOL isDeleted;

#pragma mark - modern decoration

/// Custom emoji shown beside the name, or 0 when there is none. Premium only.
@property (nonatomic, readonly) int64_t emojiStatusCustomEmojiId;
/// Unix time the emoji status expires, or 0 when it does not.
@property (nonatomic, readonly) int64_t emojiStatusExpirationDate;

/// TDLib name-colour index, or -1 when the user has not chosen one. Callers
/// treat -1 as "derive a colour from the id", which is the pre-premium rule.
@property (nonatomic, readonly) NSInteger accentColorId;
/// Custom emoji tiled behind the name in the header, or 0 for none.
@property (nonatomic, readonly) int64_t backgroundCustomEmojiId;
/// Profile-page colour index, or -1 when unset.
@property (nonatomic, readonly) NSInteger profileAccentColorId;

#pragma mark - birthday

/// 1-31, or 0 when the user has not shared a birthday. `birthdayMonth` is
/// 1-12 and `birthdayYear` is 0 when the year was withheld, which Telegram
/// allows independently of the day and month.
@property (nonatomic, readonly) NSInteger birthdayDay;
@property (nonatomic, readonly) NSInteger birthdayMonth;
@property (nonatomic, readonly) NSInteger birthdayYear;
/// YES when day and month are both present.
@property (nonatomic, readonly) BOOL hasBirthday;

#pragma mark - conversion

/// The only place a user dictionary is read.
///
/// Returns nil when `dict` is not a dictionary, when it is a TDLib error, or
/// when it carries no usable user id. Never returns a half-built object, and
/// never retains `dict`.
///
/// A `userFullInfo` dictionary may be passed as `full` to fold in the fields
/// that only live there today (the birthday). Pass nil when there is none.
+ (instancetype)fromDictionary:(NSDictionary *)dict;
+ (instancetype)fromDictionary:(NSDictionary *)dict fullInfo:(NSDictionary *)full;

/// Maps an array of dictionaries, dropping any entry that fails to build, so
/// one malformed user cannot empty a contact list. Always returns an array.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

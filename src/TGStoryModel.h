/**
 * TGStoryModel - a typed, immutable story, built once from the flattened
 * dictionary that TGClient (Stories) vends.
 *
 * Every list and single-story call in TGClient+Stories.h hands back the same
 * flat dictionary shape. Feed it to +fromDictionary: and no screen ever needs
 * an isKindOfClass check on story data again.
 *
 * The model is a value object: it converts and nothing else. It does not
 * fetch, does not format for display, and does not retain the dictionary it
 * was built from.
 */
#import <Foundation/Foundation.h>

/// Content kinds a story may carry.
typedef enum {
	TGStoryKindUnsupported = 0,
	TGStoryKindPhoto,
	TGStoryKindVideo,
	TGStoryKindLive
} TGStoryKind;

/// Who may see a story. TGStoryPrivacyUnknown means the server did not tell
/// us, which is normal for stories posted by someone else.
typedef enum {
	TGStoryPrivacyUnknown = 0,
	TGStoryPrivacyEveryone,
	TGStoryPrivacyContacts,
	TGStoryPrivacyCloseFriends,
	TGStoryPrivacySelected
} TGStoryPrivacy;

/// Kinds of interactive area drawn over a story.
typedef enum {
	TGStoryAreaKindUnsupported = 0,
	TGStoryAreaKindLocation,
	TGStoryAreaKindVenue,
	TGStoryAreaKindReaction,
	TGStoryAreaKindMessage,
	TGStoryAreaKindLink,
	TGStoryAreaKindWeather,
	TGStoryAreaKindGift
} TGStoryAreaKind;

/**
 * One interactive area over a story.
 *
 * Geometry is in percentages of the story frame, 0..100, exactly as TDLib
 * gives it, so hit testing is frame.size * value / 100.
 */
@interface TGStoryAreaModel : NSObject

@property (nonatomic, readonly) TGStoryAreaKind kind;
/// The raw kind string ("link", "venue", ...) for logging. Never nil.
@property (nonatomic, readonly, copy) NSString *kindName;

@property (nonatomic, readonly) double x;
@property (nonatomic, readonly) double y;
@property (nonatomic, readonly) double width;
@property (nonatomic, readonly) double height;
/// Clockwise rotation in degrees.
@property (nonatomic, readonly) double rotation;
@property (nonatomic, readonly) double cornerRadius;

/// Optional. Set only for a link area.
@property (nonatomic, readonly, copy) NSString *url;
/// Optional. Set for a reaction area and for a weather area.
@property (nonatomic, readonly, copy) NSString *emoji;
/// Optional. A short human label: venue name, weather temperature, gift name,
/// city for a plain location.
@property (nonatomic, readonly, copy) NSString *title;

/// Meaningful for location and venue areas only; 0 otherwise.
@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;

/// Meaningful for a message area only; 0 otherwise.
@property (nonatomic, readonly) int64_t chatId;
@property (nonatomic, readonly) int64_t messageId;

/// Returns nil unless `dict` is a dictionary describing an area.
+ (instancetype)fromDictionary:(NSDictionary *)dict;
/// Maps an array of area dictionaries, dropping any entry that fails to build.
/// Never returns nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

/**
 * A story: poster, media, caption, privacy, counters, reactions and expiry.
 */
@interface TGStoryModel : NSObject

#pragma mark - identity

/// Story id. Unique only within `chatId`, so always carry the pair.
@property (nonatomic, readonly) int64_t storyId;
/// The chat the story was posted as.
@property (nonatomic, readonly) int64_t chatId;
/// The human poster, or 0 when a channel posted it as itself.
@property (nonatomic, readonly) int64_t senderId;
/// Unix time the story was posted.
@property (nonatomic, readonly) NSTimeInterval date;

#pragma mark - expiry

/// Unix time the story stops being active, or 0 when the producer did not
/// supply one. Optional - see the notes on -isExpiredAt:.
@property (nonatomic, readonly) NSTimeInterval expireDate;
/// YES when `expireDate` is known and already past `now`. Always NO when the
/// expiry is unknown, so a screen never hides a story it cannot date.
- (BOOL)isExpiredAt:(NSTimeInterval)now;
/// Seconds until expiry, clamped at 0. Returns 0 when the expiry is unknown.
- (NSTimeInterval)secondsUntilExpiryAt:(NSTimeInterval)now;

#pragma mark - content

@property (nonatomic, readonly) TGStoryKind kind;
/// The raw kind string ("photo", "video", "live", "unsupported"). Never nil.
@property (nonatomic, readonly, copy) NSString *kindName;

/// Optional. Plain text of the caption; nil when the story has none. It is
/// never an empty string.
@property (nonatomic, readonly, copy) NSString *caption;

/// File id of the still image to show: the photo itself, or a video's
/// thumbnail. 0 when there is none.
@property (nonatomic, readonly) int64_t photoId;
/// File id of the LOW quality alternative video, or 0. The full-quality video
/// is deliberately not exposed by the client layer.
@property (nonatomic, readonly) int64_t videoId;
/// Video stories only; 0 otherwise.
@property (nonatomic, readonly) NSInteger duration;
@property (nonatomic, readonly) NSInteger width;
@property (nonatomic, readonly) NSInteger height;

/// Optional. Name of the original poster when this is a repost; nil otherwise.
@property (nonatomic, readonly, copy) NSString *repostFrom;
/// YES when this story repeats someone else's.
@property (nonatomic, readonly) BOOL isRepost;

#pragma mark - privacy

@property (nonatomic, readonly) TGStoryPrivacy privacy;
/// The raw privacy string ("everyone", "contacts", "closeFriends",
/// "selected"). Optional - nil when the server did not say.
@property (nonatomic, readonly, copy) NSString *privacyName;

#pragma mark - counters and reactions

@property (nonatomic, readonly) NSInteger viewCount;
@property (nonatomic, readonly) NSInteger forwardCount;
@property (nonatomic, readonly) NSInteger reactionCount;
/// Optional. The emoji we reacted with; nil when we have not reacted.
@property (nonatomic, readonly, copy) NSString *myReaction;
/// Convenience for `myReaction != nil`.
@property (nonatomic, readonly) BOOL hasMyReaction;

#pragma mark - state and rights

@property (nonatomic, readonly) BOOL isEdited;
@property (nonatomic, readonly) BOOL isBeingPosted;
@property (nonatomic, readonly) BOOL isBeingEdited;
/// Kept on the poster's profile page after it expires.
@property (nonatomic, readonly) BOOL isOnProfile;

@property (nonatomic, readonly) BOOL canDelete;
@property (nonatomic, readonly) BOOL canEdit;
@property (nonatomic, readonly) BOOL canForward;
@property (nonatomic, readonly) BOOL canReply;
@property (nonatomic, readonly) BOOL canSetPrivacy;
@property (nonatomic, readonly) BOOL canToggleProfile;
/// Whether the viewer list may be fetched for this story.
@property (nonatomic, readonly) BOOL canGetViewers;
/// The detailed viewer list has aged out, only the count remains.
@property (nonatomic, readonly) BOOL hasExpiredViewers;

#pragma mark - grouping

/// NSNumber album ids this story belongs to. Never nil; may be empty.
@property (nonatomic, readonly, copy) NSArray *albumIds;
/// TGStoryAreaModel objects. Never nil; may be empty.
@property (nonatomic, readonly, copy) NSArray *areas;

#pragma mark - construction

/// Builds a story from the flattened dictionary described in
/// TGClient+Stories.h. Returns nil when `dict` is not a dictionary or has no
/// usable story id.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array of story dictionaries, dropping any entry that fails to
/// build so one malformed story cannot empty a list. Never returns nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

// vim:ft=objc

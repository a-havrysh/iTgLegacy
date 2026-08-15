#import <Foundation/Foundation.h>

/// What a message actually contains. Every per-kind property below documents
/// which kinds populate it; on any other kind it holds its empty default.
typedef enum {
	TGMessageContentKindUnknown = 0,
	TGMessageContentKindText,
	TGMessageContentKindPhoto,
	TGMessageContentKindVideo,
	TGMessageContentKindVideoNote,
	TGMessageContentKindAnimation,
	TGMessageContentKindSticker,
	TGMessageContentKindAnimatedEmoji,
	TGMessageContentKindDocument,
	TGMessageContentKindVoiceNote,
	TGMessageContentKindAudio,
	TGMessageContentKindContact,
	TGMessageContentKindLocation,
	TGMessageContentKindLiveLocation,
	TGMessageContentKindVenue,
	TGMessageContentKindPoll,
	TGMessageContentKindChecklist,
	TGMessageContentKindCall,
	TGMessageContentKindDice,
	TGMessageContentKindGame,
	TGMessageContentKindInvoice,
	TGMessageContentKindStory,
	TGMessageContentKindPaidMedia,
	TGMessageContentKindExpiredMedia,
	TGMessageContentKindUnsupported,
	TGMessageContentKindService
} TGMessageContentKind;

/// Only meaningful on an outgoing message; incoming messages are always Sent.
typedef enum {
	TGMessageSendStateSent = 0,
	TGMessageSendStatePending,
	TGMessageSendStateFailed
} TGMessageSendState;

/// Only meaningful on TGMessageContentKindCall.
typedef enum {
	TGMessageCallStateNone = 0,
	TGMessageCallStateMissed,
	TGMessageCallStateAnswered
} TGMessageCallState;

/// One answer of a poll message.
@interface TGMessagePollOption : NSObject

/// The answer as written. Never nil, never empty - an option without text
/// fails to build and is dropped from the list.
@property (nonatomic, readonly, copy) NSString *text;
/// 0-100. TDLib reports 0 for every option until the poll is answered.
@property (nonatomic, readonly) NSInteger votePercentage;
/// YES if this device's user picked this answer.
@property (nonatomic, readonly) BOOL isChosen;

+ (instancetype)fromDictionary:(NSDictionary *)dict;
/// Maps an array of dictionaries, dropping entries that fail to build.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

/// A single message in a conversation, built once from the flattened message
/// dictionary TGClient vends. A screen reads properties here instead of
/// subscripting a dictionary: every isKindOfClass guard lives in
/// +fromDictionary: and nowhere else.
@interface TGMessageModel : NSObject

#pragma mark - identity

/// TDLib message id. Never 0 - a dictionary without one fails to build.
@property (nonatomic, readonly) int64_t messageId;
/// Sender user id, or 0 when the sender is a chat rather than a user
/// (channel posts, anonymous admins).
@property (nonatomic, readonly) int64_t senderId;
/// Set only on search results, which come from more than one chat. 0 otherwise.
@property (nonatomic, readonly) int64_t chatId;
/// Optional. Set only on search results, alongside chatId.
@property (nonatomic, readonly, copy) NSString *chatTitle;
/// Unix seconds. 0 when the producer omitted it.
@property (nonatomic, readonly) NSTimeInterval date;
@property (nonatomic, readonly) BOOL isOutgoing;

#pragma mark - content

@property (nonatomic, readonly) TGMessageContentKind kind;
/// The raw TDLib content type, e.g. "messagePhoto". Kept for the kinds this
/// enum folds together, and for logging. Never nil; empty string if absent.
@property (nonatomic, readonly, copy) NSString *kindTypeName;
/// What the bubble says: the caption if there is one, else the text the
/// content itself carries, else a phrase derived from the content type.
/// Empty string for a bare photo, which speaks for itself. Never nil.
@property (nonatomic, readonly, copy) NSString *text;
/// A grey centred notice rather than a bubble: joins, renames, expired media.
@property (nonatomic, readonly) BOOL isService;
/// Optional. Photos sent together share it; the chat draws them as one block.
/// nil when the message is not part of an album.
@property (nonatomic, readonly, copy) NSString *albumId;

#pragma mark - attachments

/// Image to draw in the bubble: the photo itself, or a thumbnail for video,
/// animation, video note, document and sticker. 0 when there is none.
/// Kinds: Photo, Video, VideoNote, Animation, Sticker, AnimatedEmoji, Document.
@property (nonatomic, readonly) NSInteger photoFileId;
/// File to play or offer for download. 0 when there is none.
/// Kinds: Video, VideoNote, Animation, Document, VoiceNote, Audio, and
/// Sticker when the sticker is a Lottie animation.
@property (nonatomic, readonly) NSInteger documentFileId;
/// Optional. Kinds: Video, Animation, Document, Audio; "tgs" for a Lottie
/// sticker. nil when the producer had no file name.
@property (nonatomic, readonly, copy) NSString *documentName;
@property (nonatomic, readonly) BOOL hasPhoto;
@property (nonatomic, readonly) BOOL hasDocument;
/// Seconds. Kinds: VoiceNote. 0 elsewhere.
@property (nonatomic, readonly) NSInteger duration;
/// Optional. Five bits per sample, drawn as the bars of a voice bubble.
/// Kind: VoiceNote. nil when absent or empty.
@property (nonatomic, readonly, copy) NSData *waveform;

#pragma mark - location

/// Kinds: Location, LiveLocation, Venue. Both are 0 when hasLocation is NO.
@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;
@property (nonatomic, readonly) BOOL hasLocation;

#pragma mark - call

/// Kind: Call. None on every other kind.
@property (nonatomic, readonly) TGMessageCallState callState;

#pragma mark - poll

/// Optional. Kind: Poll. nil on every other kind.
@property (nonatomic, readonly, copy) NSString *pollQuestion;
/// Array of TGMessagePollOption. Empty on every kind but Poll. Never nil.
@property (nonatomic, readonly, copy) NSArray *pollOptions;
@property (nonatomic, readonly) NSInteger pollTotalVoterCount;
@property (nonatomic, readonly) BOOL pollIsClosed;
/// Defaults to YES, which is what TDLib means by an omitted flag.
@property (nonatomic, readonly) BOOL pollIsAnonymous;
@property (nonatomic, readonly) BOOL isPoll;

#pragma mark - reply, forward, edit

/// 0 when this message replies to nothing.
@property (nonatomic, readonly) int64_t replyToMessageId;
/// Optional. The quoted text, when the reply carries it inline. nil means the
/// screen must fetch the original by replyToMessageId to show anything.
@property (nonatomic, readonly, copy) NSString *replyText;
@property (nonatomic, readonly) BOOL isReply;
/// Optional. Who the message came from originally - a user name, a hidden
/// sender's name, a channel signature. nil when the message is not forwarded.
@property (nonatomic, readonly, copy) NSString *forwardFrom;
@property (nonatomic, readonly) BOOL isForwarded;
@property (nonatomic, readonly) BOOL isEdited;

#pragma mark - reactions

/// Optional. One line, "emoji count" per reaction joined by spaces, most used
/// first. nil when nobody has reacted.
@property (nonatomic, readonly, copy) NSString *reactionsSummary;
@property (nonatomic, readonly) BOOL hasReactions;

#pragma mark - send and scheduling state

/// Sent unless the producer supplied a sending state; incoming messages are
/// always Sent.
@property (nonatomic, readonly) TGMessageSendState sendState;
/// YES when the failure is one TDLib says can be retried.
@property (nonatomic, readonly) BOOL canRetry;
/// Unix seconds. Non-zero only on a scheduled message with a fixed send time.
@property (nonatomic, readonly) NSTimeInterval scheduledSendDate;
/// A scheduled message with no fixed time, to go out when the peer is online.
@property (nonatomic, readonly) BOOL sendWhenOnline;
@property (nonatomic, readonly) BOOL isScheduled;

#pragma mark - building

/// Builds from a flattened message dictionary, or from a raw TDLib message
/// that has already been flattened by TGClient. Returns nil if dict is not a
/// dictionary or carries no message id.
+ (instancetype)fromDictionary:(NSDictionary *)dict;
/// Maps an array of dictionaries, dropping entries that fail to build so one
/// malformed message cannot take a whole history down.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

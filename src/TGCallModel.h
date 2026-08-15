#import <Foundation/Foundation.h>

/// Where a call stands right now. Mirrors TDLib's callState* constructors.
typedef NS_ENUM(NSInteger, TGCallModelState) {
	/// No state in the source dictionary - typical for a call-log entry,
	/// which describes a call that is already over.
	TGCallModelStateUnknown = 0,
	TGCallModelStatePending,
	TGCallModelStateExchangingKeys,
	TGCallModelStateReady,
	TGCallModelStateHangingUp,
	TGCallModelStateDiscarded,
	TGCallModelStateError
};

/// Why a call ended. Mirrors TDLib's callDiscardReason* constructors.
typedef NS_ENUM(NSInteger, TGCallModelDiscardReason) {
	/// The source carried no reason, or the call has not ended yet.
	TGCallModelDiscardReasonEmpty = 0,
	TGCallModelDiscardReasonMissed,
	TGCallModelDiscardReasonDeclined,
	TGCallModelDiscardReasonDisconnected,
	TGCallModelDiscardReasonHungUp,
	TGCallModelDiscardReasonUpgradeToGroupCall
};

/// One voice or video call, typed.
///
/// Built from either of the two dictionary shapes the app sees for a call:
///
///  - the `call` object inside an updateCall, which carries `id`, `user_id`,
///    `is_outgoing`, `is_video` and a nested `state`;
///  - a `messageCall` message content from the call log, which carries
///    `discard_reason`, `duration` and `is_video` but no call id, plus the
///    flattened message dictionary TGClient vends for it (`callState`,
///    `duration`, `outgoing`).
///
/// A screen reads properties here and never subscripts a call dictionary.
/// Immutable, and nothing is retained from the source dictionary.
@interface TGCallModel : NSObject

/// TDLib call id. 0 for a call-log entry, which has no id of its own.
@property (nonatomic, readonly) int32_t callId;

/// The other party. 0 when the source did not name one, which is the case
/// for a call-log entry: the peer is the chat the message sits in.
@property (nonatomic, readonly) int64_t peerUserId;

/// YES when this side placed the call.
@property (nonatomic, readonly) BOOL outgoing;

/// YES for a video call. NO when the source did not say.
@property (nonatomic, readonly) BOOL video;

/// Where the call stands. TGCallModelStateUnknown for a call-log entry.
@property (nonatomic, readonly) TGCallModelState state;

/// Why the call ended, as an enum. TGCallModelDiscardReasonEmpty when the
/// call has not ended or the source carried no reason.
@property (nonatomic, readonly) TGCallModelDiscardReason discardReason;

/// The raw TDLib reason constructor, e.g. "callDiscardReasonMissed".
/// Optional - nil when there is no reason. Kept for logging only; screens
/// should branch on discardReason.
@property (nonatomic, readonly, copy) NSString *discardReasonName;

/// How long the call lasted, in whole seconds. 0 when it never connected.
@property (nonatomic, readonly) NSInteger duration;

/// The four-emoji key fingerprint TDLib sends with callStateReady, as an
/// array of NSString. Optional - nil unless the source carried `emojis`.
@property (nonatomic, readonly, copy) NSArray *emojiKey;

/// The message TDLib gave with callStateError. Optional - nil otherwise.
@property (nonatomic, readonly, copy) NSString *errorMessage;

/// YES when the call was never picked up: missed or declined. This is the
/// distinction the chat list and the call bubble draw a red arrow for.
@property (nonatomic, readonly) BOOL missed;

/// YES once the call is over, whichever way it ended.
@property (nonatomic, readonly) BOOL ended;

/// Builds a model from a `call` object, a `messageCall` content, or the
/// flattened call message dictionary TGClient vends.
/// Returns nil when dict is not a dictionary or carries nothing that makes
/// it a call: no call id, no state, no discard reason and no duration.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Maps an array of call dictionaries, dropping entries that fail to build.
/// Returns an empty array when dicts is not an array.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end

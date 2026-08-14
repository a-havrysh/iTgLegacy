//
// TGClient+Calls - the TDLib side of voice calls, the call log and the
// call-related settings.
//
// The media path itself lives in TGCall/libtgvoip, which already issues
// createCall, acceptCall and discardCall. Nothing here duplicates that: this
// category covers everything around a call - rating, debug submission, the
// recent-calls list, per-device and privacy settings, network usage, and the
// read-only handling of group calls (video chats), which this device cannot
// join but must still render and be able to decline.
//
#import "TGClient.h"

@interface TGClient (Calls)

#pragma mark - after a call: rating and debug

/// Rate a finished call. Send this when callStateDiscarded arrived with
/// need_rating set. `rating` is 1..5, `comment` may be nil, `problems` is an
/// array of short names, any of: "echo", "noise", "interruptions",
/// "distortedSpeech", "silentLocal", "silentRemote", "dropped",
/// "distortedVideo", "pixelatedVideo". Unknown names are dropped.
/// `completion` receives YES when TDLib accepted the rating.
- (void)rateCallId:(int32_t)callId
            rating:(NSInteger)rating
           comment:(NSString *)comment
          problems:(NSArray *)problems
        completion:(void (^)(BOOL ok))completion;

/// Same as above for a call we only know as a call message in a chat, which is
/// how a rating submitted late (app relaunched) has to be addressed.
- (void)rateCallInChat:(int64_t)chatId
             messageId:(int64_t)messageId
                rating:(NSInteger)rating
               comment:(NSString *)comment
              problems:(NSArray *)problems
            completion:(void (^)(BOOL ok))completion;

/// Submit the libtgvoip debug string for a finished call. Send when
/// callStateDiscarded arrived with need_debug_information set. Silent, no UI.
- (void)sendDebugInformationForCallId:(int32_t)callId
                          information:(NSString *)information;

/// Upload the libtgvoip log file of a finished call. Send when
/// callStateDiscarded arrived with need_log set. `path` is a local file path;
/// nothing happens if the file does not exist. Silent, no UI.
- (void)sendLogForCallId:(int32_t)callId filePath:(NSString *)path;

#pragma mark - call log

/// Recent calls, newest first, across all chats. `offset` is nil for the first
/// page, otherwise the `nextOffset` handed back by the previous call.
/// `onlyMissed` narrows the list to missed and declined calls.
/// Each entry is a dictionary with:
///   "chatId"    NSNumber int64, the chat holding the call message
///   "messageId" NSNumber int64
///   "userId"    NSNumber int64, the other party (0 if unknown)
///   "name"      NSString, display name of the other party
///   "date"      NSNumber, unix time
///   "outgoing"  NSNumber BOOL
///   "missed"    NSNumber BOOL (missed or declined)
///   "video"     NSNumber BOOL
///   "duration"  NSNumber, seconds, 0 when never connected
///   "text"      NSString, ready-made row subtitle, e.g. "Outgoing, 1:04"
/// `nextOffset` is nil when the list is exhausted.
- (void)callLogWithOffset:(NSString *)offset
               onlyMissed:(BOOL)onlyMissed
                    limit:(NSInteger)limit
               completion:(void (^)(NSArray *calls, NSString *nextOffset))completion;

/// Delete every call message from the log. `revoke` also deletes them for the
/// other party. `completion` receives YES on success.
- (void)clearCallLogRevoke:(BOOL)revoke completion:(void (^)(BOOL ok))completion;

/// The people this user calls most often, for a strip above the call log.
/// Each entry: "chatId", "userId", "name". Never nil, possibly empty.
- (void)frequentlyCalledContactsWithCompletion:(void (^)(NSArray *contacts))completion;

/// Drop one chat from the frequently-called list (long-press "Delete").
- (void)removeFrequentlyCalledChat:(int64_t)chatId;

#pragma mark - settings

/// "Use less data for calls" is NOT declared here: TGClient+Network already
/// owns -setUseLessDataForCalls:completion:, and its auto-download settings
/// dictionary exposes the current value under the "useLessDataForCalls" key.
/// Use those; a second wrapper would be a duplicate category implementation.

/// Whether an authorized session may accept incoming calls. `sessionId` comes
/// from the active-sessions list. `completion` receives YES on success.
- (void)setSessionId:(int64_t)sessionId
      canAcceptCalls:(BOOL)canAccept
          completion:(void (^)(BOOL ok))completion;

/// Network bytes and airtime spent on calls since TDLib last reset its
/// counters. The dictionary has "sent", "received" (NSNumber, bytes),
/// "duration" (NSNumber, seconds) and "sinceDate" (NSNumber, unix time).
/// Never nil; all zeroes when nothing was recorded.
- (void)callNetworkUsageWithCompletion:(void (^)(NSDictionary *usage))completion;

/// Reset all of TDLib's network counters, calls included.
- (void)resetNetworkUsageWithCompletion:(void (^)(BOOL ok))completion;

#pragma mark - group calls (video chats), read-only

/// Human-readable grey service line for a group-call message content
/// dictionary, i.e. one of messageVideoChatScheduled, messageVideoChatStarted,
/// messageVideoChatEnded, messageInviteVideoChatParticipants or
/// messageGroupCall. Returns nil for any other content, so a caller can fall
/// through to its own formatter.
- (NSString *)groupCallServiceTextForContent:(NSDictionary *)content;

/// Politely refuse a group-call invitation that arrived as a message. This
/// device cannot join video chats, and declining is better than ignoring.
- (void)declineGroupCallInvitationInChat:(int64_t)chatId
                               messageId:(int64_t)messageId
                              completion:(void (^)(BOOL ok))completion;

/// Whether a t.me link is a group-call / video-chat link. Tapping one must end
/// in a "not supported on this device" alert rather than a broken join.
/// `completion` receives YES for a group call or video chat link.
- (void)isGroupCallLink:(NSString *)url completion:(void (^)(BOOL isGroupCall))completion;

@end

// vim:ft=objc

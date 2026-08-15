//
// TGClient+Calls - the TDLib side of rating a finished voice call and the
// call-related session settings.
//
// The media path itself lives in TGCall/libtgvoip, which already issues
// createCall, acceptCall and discardCall. Nothing here duplicates that: this
// category covers rating a finished call and the per-session call setting.
//
#import "TGClient.h"

@interface TGClient (Calls)

#pragma mark - after a call: rating

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

@end

// vim:ft=objc

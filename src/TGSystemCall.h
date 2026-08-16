//
// TGSystemCall - puts an incoming call on SpringBoard's own alert machinery.
//
// iOS 6 has no CallKit and, on 10B329, no SBCallAlert either: the real
// incoming-call screen belongs to MobilePhone.app and is built from a CTCall
// that only CommCenter can create. The part of it we can have is SBAlertItem,
// which is what SpringBoard's own call alert (SBCallFailureAlertItem) is - a
// lock-screen slide label and a two-button modal alert.
//
// The SpringBoard half lives outside this binary, in tools/systemcall. This
// side only tells it three things and listens for two:
//
//   -> kuzm.ig.telegram.call.incoming   a call is ringing; the caller's name
//                                       is in Library/Caches/systemcall.plist
//   -> kuzm.ig.telegram.call.ended      it is not ringing any more
//   <- kuzm.ig.telegram.call.answer     the user answered from the alert
//   <- kuzm.ig.telegram.call.decline    the user declined from the alert
//
// Nothing here needs the tweak to be installed. Without it the notifications
// go nowhere and the app behaves exactly as it did before.
//
#import <Foundation/Foundation.h>

@interface TGSystemCall : NSObject

/// Call once at launch. Safe to call more than once.
+ (void)install;

@end

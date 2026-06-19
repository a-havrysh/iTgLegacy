//
// TGClient - TDLib client for iOS 7.1.2 / armv7.
//
// TDLib is loaded with dlopen rather than linked: statically linked it pushes
// the app's __TEXT past the 16MB armv7 thumb branch limit, which this linker
// cannot bridge. See scripts/build_tdlib_dylib.sh.
//
// Everything is JSON over td_json_client_*. One background thread owns the
// receive loop; handlers are always delivered on the main queue.
//
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TGAuthState) {
    TGAuthStateUnknown = 0,
    TGAuthStateWaitPhoneNumber,
    TGAuthStateWaitCode,
    TGAuthStateWaitPassword,
    TGAuthStateWaitRegistration,
    TGAuthStateReady,
    TGAuthStateLoggingOut,
    TGAuthStateClosed
};

@interface TGClient : NSObject

+ (instancetype)shared;

/// YES once libtdjson.dylib is loaded and a client exists.
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) TGAuthState authState;

/// Called on the main queue whenever the authorization state changes.
@property (nonatomic, copy) void (^onAuthState)(TGAuthState state);
/// Called on the main queue for TDLib errors that concern the user.
@property (nonatomic, copy) void (^onError)(NSString *message);

/// Loads the dylib, creates the client and starts the receive loop.
/// Safe to call more than once. Returns NO if TDLib is unavailable.
- (BOOL)start;

- (void)sendPhoneNumber:(NSString *)phoneNumber;
- (void)sendCode:(NSString *)code;
- (void)sendPassword:(NSString *)password;
- (void)logOut;

/// Fire-and-forget request. `request` is a JSON object; @extra is not tracked.
- (void)send:(NSDictionary *)request;

@end

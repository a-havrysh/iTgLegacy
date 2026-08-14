//
// TGClient+Network - proxies, network type reporting, data usage statistics,
// auto-download settings and connection diagnostics.
//
// Everything here is safe to call before authorization: TDLib accepts the
// proxy and network-type calls while the client is still logged out, which is
// exactly when a user behind a blocked network needs them.
//
// Completions run on the main queue and may be nil. Failures answer with nil,
// NO or 0 rather than an error object - the screens in this area are all
// "did it work" screens and TDLib error text is not useful on this hardware.
//
// A proxy is passed around as a plain dictionary so no UI code has to know the
// td_api layout. Keys, all optional on input except "server", "port", "type":
//
//   "id"           NSNumber, server-assigned; present on read, ignored on write
//   "server"       NSString host or IP
//   "port"         NSNumber
//   "type"         NSString - "socks5", "http" or "mtproto"
//   "username"     NSString - socks5 / http only
//   "password"     NSString - socks5 / http only
//   "httpOnly"     NSNumber BOOL - http only, true to forbid CONNECT tunnelling
//   "secret"       NSString - mtproto only
//   "comment"      NSString
//   "isEnabled"    NSNumber BOOL - read only
//   "lastUsedDate" NSNumber unix time - read only
//
#import "TGClient.h"

@interface TGClient (Network)

#pragma mark - proxy list

/// Every proxy configured on this device, newest first as TDLib returns them.
/// Each entry is a proxy dictionary as documented above. Empty array, never
/// nil, when nothing is set up or the call failed.
- (void)proxiesWithCompletion:(void (^)(NSArray *proxies))completion;

/// Add a proxy from a dictionary with at least "server", "port" and "type".
/// `enable` switches to it immediately. `completion` receives the stored proxy
/// including its new "id", or nil if TDLib rejected it (bad secret, bad port).
- (void)addProxy:(NSDictionary *)proxy
          enable:(BOOL)enable
      completion:(void (^)(NSDictionary *added))completion;

/// Overwrite the proxy with `proxyId` with new settings. Same dictionary shape
/// as -addProxy:enable:completion:; `completion` gets the stored proxy or nil.
- (void)editProxy:(NSInteger)proxyId
                 to:(NSDictionary *)proxy
             enable:(BOOL)enable
         completion:(void (^)(NSDictionary *edited))completion;

/// Route all traffic through this proxy. Only one can be enabled at a time,
/// so this implicitly disables whichever one was in use.
- (void)enableProxy:(NSInteger)proxyId completion:(void (^)(BOOL ok))completion;

/// Stop using any proxy and connect directly.
- (void)disableProxyWithCompletion:(void (^)(BOOL ok))completion;

/// Forget a proxy entirely. Removing the enabled one also disables it.
- (void)removeProxy:(NSInteger)proxyId completion:(void (^)(BOOL ok))completion;

#pragma mark - proxy checks

/// Round-trip time to a Telegram server through `proxy`, in seconds.
/// Pass nil to measure the direct connection. `completion` receives a negative
/// value when the proxy is unreachable, so a row can print "unavailable".
- (void)pingProxy:(NSDictionary *)proxy
       completion:(void (^)(double seconds))completion;

/// Ping every configured proxy at once. `completion` receives a dictionary
/// keyed by proxy id (NSNumber) with NSNumber seconds, negative for
/// unreachable. Use it to refresh the whole list when the screen appears.
- (void)pingAllProxiesWithCompletion:(void (^)(NSDictionary *secondsByProxyId))completion;

/// Check that a proxy can actually reach a datacenter before saving it.
/// `dcId` 1..5, or 0 to let this method use datacenter 2, which is what the
/// modern client validates against. `timeout` is in seconds; pass 0 for 10.
- (void)testProxy:(NSDictionary *)proxy
             dcId:(NSInteger)dcId
          timeout:(double)timeout
       completion:(void (^)(BOOL reachable))completion;

/// Ping every proxy and switch to the fastest one that answers. `completion`
/// receives the proxy now in use, or nil if none of them responded (in which
/// case whatever was enabled before is left alone).
- (void)selectFastestProxyWithCompletion:(void (^)(NSDictionary *proxy))completion;

#pragma mark - proxy links

/// A shareable https://t.me/proxy?... link for a proxy dictionary, for the
/// pasteboard or a QR code. Nil on failure.
- (void)proxyLinkFor:(NSDictionary *)proxy
          completion:(void (^)(NSString *link))completion;

/// Parse a tg://proxy or t.me/proxy link (from a URL-scheme open, a tapped
/// message link or a scanned QR code) into a proxy dictionary ready for
/// -addProxy:enable:completion:. Nil when the link is not a proxy link.
- (void)proxyFromLink:(NSString *)link
           completion:(void (^)(NSDictionary *proxy))completion;

#pragma mark - network type

/// Tell TDLib what the device is connected to, so it can size its requests and
/// bill data usage to the right bucket. `kind` is "none", "mobile",
/// "mobileRoaming", "wifi" or "other"; anything else is treated as "other".
/// Push this on every reachability change and when the app foregrounds.
- (void)setNetworkTypeKind:(NSString *)kind;

#pragma mark - data usage

/// Reading the counters lives in TGClient+Files
/// (-networkStatisticsOnlyCurrent:completion:); a second implementation of the
/// same selector in this category would silently override it.
///
/// Zero the counters and set a new "since" date.
- (void)resetNetworkStatisticsWithCompletion:(void (^)(BOOL ok))completion;

/// Fold the traffic of a finished voice call into the statistics. Call it from
/// TGCall when a call ends; TDLib cannot see call traffic on its own.
/// `kind` is a network-type name as in -setNetworkTypeKind:.
- (void)addCallStatisticsSent:(long long)sentBytes
                     received:(long long)receivedBytes
                     duration:(double)seconds
                  networkKind:(NSString *)kind;

#pragma mark - auto-download

/// The server presets are read through TGClient+Files
/// (-autoDownloadPresetsWithCompletion:); this category keeps its own private
/// copy of that call rather than declaring the selector twice.
///
/// Apply one settings dictionary - same keys as a preset, missing keys default
/// to off / zero - to one network type. `kind` is a network-type name as in
/// -setNetworkTypeKind:.
- (void)setAutoDownloadSettings:(NSDictionary *)settings
                    networkKind:(NSString *)kind
                     completion:(void (^)(BOOL ok))completion;

/// The Data Saver master switch: applies the "low" preset to mobile, roaming
/// and Wi-Fi when on, and the "high" preset when off. There is no server-side
/// data-saver flag, so this is exactly what the modern client does.
- (void)setDataSaverEnabled:(BOOL)enabled completion:(void (^)(BOOL ok))completion;

/// "Use less data for calls". TDLib has no way to read back the settings that
/// are in force, so this rewrites the medium preset with the flag flipped onto
/// every network type. Call it from the call settings toggle only.
- (void)setUseLessDataForCalls:(BOOL)useLess completion:(void (^)(BOOL ok))completion;

#pragma mark - diagnostics

/// The server-side application config is read through TGClient+AppSettings
/// (-applicationConfigWithCompletion:).
///
/// Read one TDLib option by name, e.g. "version" or "my_id". `value` is an
/// NSString, NSNumber or nil when the option is unset or the call failed.
- (void)optionNamed:(NSString *)name completion:(void (^)(id value))completion;

/// Write one TDLib option. `value` must be an NSString or NSNumber; pass an
/// NSNumber holding a BOOL for boolean options and use `isBoolean` to say so,
/// because NSNumber cannot tell 1 from YES on this runtime.
- (void)setOptionNamed:(NSString *)name
                 value:(id)value
             isBoolean:(BOOL)isBoolean;

/// Wording for the current connection state, for a navigation-bar title:
/// "Waiting for network", "Connecting...", "Updating..." or nil when the
/// connection is ready and the real title should show instead.
- (NSString *)connectionStateTitle;

@end

// vim:ft=objc

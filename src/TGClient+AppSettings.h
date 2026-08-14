//
// TGClient (AppSettings) - wallpapers, per-chat themes, autosave-to-gallery,
// application config and the suggested-actions banner.
//
// Everything here returns plain Foundation objects. Background ids are int64
// and TDLib sends them as JSON strings, so they travel through this API as
// NSString and must be handed back unchanged.
//
#import "TGClient.h"

@interface TGClient (AppSettings)

#pragma mark - wallpapers

/// Backgrounds installed for this account. `forDarkTheme` picks the dark or
/// light set - they are two independent lists on the server.
/// Each entry: "id" (NSString, int64), "name" (NSString, the t.me/bg slug),
/// "isDark" and "isDefault" (NSNumber BOOL), "kind" (NSString: "wallpaper",
/// "pattern", "fill" or "theme"), "isBlurred" and "isMoving" (NSNumber BOOL),
/// "intensity" (NSNumber, patterns only), "topColor" / "bottomColor"
/// (NSNumber 0xRRGGBB, absent when the background has no fill; a solid fill
/// sets both to the same value), "rotation" (NSNumber degrees),
/// "fileId" (NSNumber TDLib file id of the full image, absent for pure fills)
/// and "thumbFileId" (NSNumber, absent when there is no thumbnail).
/// Never nil; empty on failure.
- (void)installedBackgroundsForDarkTheme:(BOOL)forDarkTheme
							  completion:(void (^)(NSArray *backgrounds))completion;

/// Make an already-installed background the default chat background.
/// `backgroundId` is the "id" string from -installedBackgroundsForDarkTheme:.
/// `blurred` and `moving` only matter for photo wallpapers.
/// `completion` gets the applied background in the same shape as the list, or
/// nil on failure.
- (void)setDefaultBackgroundId:(NSString *)backgroundId
					   blurred:(BOOL)blurred
						moving:(BOOL)moving
				  forDarkTheme:(BOOL)forDarkTheme
					completion:(void (^)(NSDictionary *background))completion;

/// Plain colour wallpaper. `color` is 0xRRGGBB. Nothing is downloaded, which
/// makes this the cheap option on this hardware.
- (void)setDefaultBackgroundColor:(NSInteger)color
					 forDarkTheme:(BOOL)forDarkTheme
					   completion:(void (^)(NSDictionary *background))completion;

/// Two-colour linear gradient wallpaper. `rotation` is in degrees, 0..359,
/// and TDLib only accepts multiples of 45.
- (void)setDefaultBackgroundGradientTop:(NSInteger)topColor
								 bottom:(NSInteger)bottomColor
							   rotation:(NSInteger)rotation
						   forDarkTheme:(BOOL)forDarkTheme
							 completion:(void (^)(NSDictionary *background))completion;

/// Upload a local image file as the wallpaper.
- (void)setDefaultBackgroundAtPath:(NSString *)path
						   blurred:(BOOL)blurred
					  forDarkTheme:(BOOL)forDarkTheme
						completion:(void (^)(NSDictionary *background))completion;

/// Back to the stock wallpaper. Call for both themes to reset appearance
/// completely.
- (void)resetDefaultBackgroundForDarkTheme:(BOOL)forDarkTheme;

/// Look up a background by the slug in a t.me/bg/<name> link, or by a colour
/// spec TDLib understands ("e6ebee", "008000-00ff00" and the like).
/// `completion` gets the same dictionary shape as the list, or nil.
- (void)searchBackgroundNamed:(NSString *)name
				   completion:(void (^)(NSDictionary *background))completion;

/// Shareable https://t.me/bg/... link for a background. `name` and `kind` come
/// from a list entry; `kind` decides which BackgroundType is described.
/// `completion` gets the url, or nil.
- (void)shareUrlForBackgroundNamed:(NSString *)name
							  kind:(NSString *)kind
						completion:(void (^)(NSString *url))completion;

/// Remove one background from the installed list, or empty the list.
- (void)removeInstalledBackgroundId:(NSString *)backgroundId;
- (void)resetInstalledBackgrounds;

#pragma mark - per-chat theme

/// Apply one of Telegram's emoji themes to a chat. `emoji` is the theme name
/// ("🏝", "🌅", ...); pass nil to go back to the default theme.
- (void)setChatThemeEmoji:(NSString *)emoji forChat:(int64_t)chatId;

/// The emoji theme currently applied to a chat, or nil when it uses the
/// default one.
- (void)chatThemeEmojiForChat:(int64_t)chatId
				   completion:(void (^)(NSString *emoji))completion;

#pragma mark - save to camera roll

/// Reading the current autosave settings lives in TGClient+Storage
/// (-autosaveSettingsWithCompletion:, three-dictionary callback).
///
/// Change one scope. `scope` is "private", "groups" or "channels".
/// `maxVideoSize` is in bytes and only limits video autosave.
- (void)setAutosaveScope:(NSString *)scope
				  photos:(BOOL)photos
				  videos:(BOOL)videos
			maxVideoSize:(long long)maxVideoSize;

/// Same, for one specific chat, overriding its scope.
- (void)setAutosaveForChat:(int64_t)chatId
					photos:(BOOL)photos
					videos:(BOOL)videos
			  maxVideoSize:(long long)maxVideoSize;

#pragma mark - application configuration

/// The whole application config is TGClient+Network's
/// -applicationConfigWithCompletion:. Clearing per-chat autosave overrides is
/// TGClient+Storage's -clearAutosaveExceptions.
///
/// One top-level value of the application config, already unwrapped.
/// Handy for a single flag without walking the whole tree.
- (void)applicationConfigValueForKey:(NSString *)key
						  completion:(void (^)(id value))completion;

#pragma mark - suggested actions

/// Dismiss a suggested action the chat-list banner is showing. `name` is the
/// TDLib type name without decoration, e.g. "suggestedActionCheckPassword",
/// "suggestedActionCheckPhoneNumber", "suggestedActionSetPassword" or
/// "suggestedActionEnableArchiveAndMuteNewChats". Actions carrying parameters
/// are dismissed with their defaults, which is what dismissing means anyway.
- (void)hideSuggestedActionNamed:(NSString *)name;

/// Turn on "archive and mute new chats from unknown users" and dismiss the
/// banner that suggested it, which is the whole job behind that one tap.
- (void)acceptArchiveAndMuteSuggestion;

@end

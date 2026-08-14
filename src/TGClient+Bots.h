//
// TGClient (Bots) - bot commands, inline queries, callback buttons, keyboards.
//
// Everything here returns plain Foundation objects. Nothing in this category
// needs the caller to know the TDLib schema: keyboards arrive as arrays of
// arrays of small dictionaries, bots as flat user dictionaries.
//
#import "TGClient.h"

@interface TGClient (Bots)

#pragma mark - keyboards

/// Inline keyboard of a message, as rows of buttons, or nil when the message
/// carries none. Pass the flattened message dictionary the chat list and
/// -historyForChat:... hand out, or a raw TDLib message; both work.
/// Each button is a dictionary with:
///   "text"       NSString, the label
///   "kind"       NSString, one of "url", "callback", "callbackWithPassword",
///                "callbackGame", "switchInline", "user", "copyText", "buy",
///                "loginUrl", "webApp", "unsupported"
///   "url"        NSString, for "url", "loginUrl" and "webApp"
///   "data"       NSString, base64 callback payload, for the callback kinds
///   "query"      NSString, for "switchInline"
///   "target"     NSString, for "switchInline": "current", "chosen" or "link"
///   "userId"     NSNumber, for "user"
///   "copyText"   NSString, for "copyText"
/// A button is always safe to hand straight back to
/// -pressCallbackButton:inChat:message:completion:.
- (NSArray *)inlineKeyboardRowsForMessage:(NSDictionary *)message;

/// Custom reply keyboard attached to a message, or nil when there is none.
/// Keys:
///   "mode"        NSString, "show", "remove" or "forceReply"
///   "rows"        NSArray of NSArray of button dictionaries (see below);
///                 empty for "remove" and "forceReply"
///   "resize"      NSNumber BOOL, shrink the panel to fit its rows
///   "oneTime"     NSNumber BOOL, hide the panel after one press
///   "persistent"  NSNumber BOOL, keep the panel instead of the text keyboard
///   "placeholder" NSString, input-bar placeholder, may be empty
/// Reply-keyboard buttons carry "text" plus "kind", one of "text",
/// "requestPhoneNumber", "requestLocation", "requestPoll", "requestUsers",
/// "requestChat", "webApp", "unsupported". Request buttons also carry
/// "buttonId" (NSNumber) which -shareUsers:... needs, and the request-users
/// ones carry "maxQuantity", "userIsBot", "userIsPremium" (NSNumbers).
- (NSDictionary *)replyKeyboardForMessage:(NSDictionary *)message;

/// Answer a "requestUsers" reply-keyboard button. `messageId` is the message
/// the keyboard came with. Fire and forget; the bot gets a service message.
- (void)shareUsers:(NSArray *)userIds
    withBotButton:(NSInteger)buttonId
           inChat:(int64_t)chatId
          message:(int64_t)messageId;

/// The same for a "requestChat" button.
- (void)shareChat:(int64_t)sharedChatId
    withBotButton:(NSInteger)buttonId
           inChat:(int64_t)chatId
          message:(int64_t)messageId;

#pragma mark - callback buttons

/// Press an inline button that talks back to the bot. `button` is one entry of
/// -inlineKeyboardRowsForMessage:. The completion gets a dictionary with
/// "text" (NSString, may be empty), "showAlert" (NSNumber BOOL - YES means an
/// alert, NO means a toast) and "url" (NSString, non-empty when the client
/// should open it), or nil when the call failed or the button needs a password
/// (see -pressCallbackButton:inChat:message:password:completion:).
- (void)pressCallbackButton:(NSDictionary *)button
                     inChat:(int64_t)chatId
                    message:(int64_t)messageId
                 completion:(void (^)(NSDictionary *answer))completion;

/// Same, for a button of kind "callbackWithPassword": ask the user for their
/// 2FA password first and pass it here. Same answer shape.
- (void)pressCallbackButton:(NSDictionary *)button
                     inChat:(int64_t)chatId
                    message:(int64_t)messageId
                   password:(NSString *)password
                 completion:(void (^)(NSDictionary *answer))completion;

#pragma mark - bot profile and commands

/// Everything a bot chat header and profile needs, or nil when the user is not
/// a bot. Keys: "description", "shortDescription" (NSStrings, may be empty),
/// "commands" (NSArray of dictionaries with "command" - without the slash -
/// and "description"), "menuButtonText" and "menuButtonUrl" (NSStrings, empty
/// when the bot has no menu button).
- (void)botInfoForUser:(int64_t)userId completion:(void (^)(NSDictionary *info))completion;

/// Just the command list of a bot, for the slash-command autocomplete.
/// Same entries as botInfo's "commands"; empty array for a non-bot.
- (void)botCommandsForUser:(int64_t)userId completion:(void (^)(NSArray *commands))completion;

/// Commands filtered by a typed prefix, e.g. "/se" or "se". Convenience over
/// -botCommandsForUser:, ordered as the bot declared them.
- (void)botCommandsForUser:(int64_t)userId
            matchingPrefix:(NSString *)prefix
                completion:(void (^)(NSArray *commands))completion;

/// The bot's menu button, straight from TDLib rather than from bot_info:
/// "text" and "url", both possibly empty.
- (void)menuButtonForBot:(int64_t)userId completion:(void (^)(NSDictionary *button))completion;

#pragma mark - starting a bot

/// Press START in an empty bot chat. `parameter` is the deep-link payload, or
/// nil/empty for a plain start.
- (void)startBot:(int64_t)botUserId inChat:(int64_t)chatId parameter:(NSString *)parameter;

/// Resolve a t.me link that starts a bot. The completion gets nil when the
/// link is not a bot-start link, otherwise a dictionary with "username",
/// "parameter" (NSString, may be empty) and "inGroup" (NSNumber BOOL).
- (void)botStartLinkInfo:(NSString *)link completion:(void (^)(NSDictionary *info))completion;

/// Open a bot-start link end to end: resolves the link, finds or creates the
/// bot's private chat and sends the start message. The completion gets the
/// chat id to push, or 0 when the link could not be used.
- (void)openBotStartLink:(NSString *)link completion:(void (^)(int64_t chatId))completion;

#pragma mark - write access

/// Whether the bot is allowed to message the user without being started.
- (void)canBotSendMessages:(int64_t)botUserId completion:(void (^)(BOOL allowed))completion;
/// Grant that permission, after the user confirmed in an action sheet.
- (void)allowBotToSendMessages:(int64_t)botUserId completion:(void (^)(BOOL ok))completion;

#pragma mark - inline queries

/// Ask an inline bot for results. `query` is the text after the bot username,
/// `offset` is nil for the first page or the "nextOffset" of the previous one.
/// The completion gets a dictionary with:
///   "queryId"     NSNumber, needed to send a result
///   "nextOffset"  NSString, empty when there is no further page
///   "buttonText"  NSString, empty when the bot sent no switch-pm button
///   "buttonParameter" NSString, start parameter for that button
///   "results"     NSArray of dictionaries with "id" (NSString, result id),
///                 "kind" ("article", "photo", "sticker", "animation",
///                 "video", "audio", "voiceNote", "document", "location",
///                 "venue", "contact", "game"), "title", "description",
///                 "url", "thumbId" (NSNumber file id or absent) and
///                 "fileId" (NSNumber file id of the full media, or absent).
/// Nil when the bot answered with an error or is not an inline bot.
- (void)inlineQueryToBot:(int64_t)botUserId
                  inChat:(int64_t)chatId
                   query:(NSString *)query
                  offset:(NSString *)offset
              completion:(void (^)(NSDictionary *results))completion;

/// Send one inline result into a chat. `queryId` and `resultId` come from
/// -inlineQueryToBot:...; `hideVia` drops the "via @bot" attribution.
- (void)sendInlineResult:(NSString *)resultId
                 queryId:(NSNumber *)queryId
                  toChat:(int64_t)chatId
                 replyTo:(int64_t)replyToId
                 hideVia:(BOOL)hideVia;

/// Bots the user has recently used inline, for the bare "@" suggestion list.
/// Each entry: "id", "name", "username".
- (void)recentInlineBotsWithCompletion:(void (^)(NSArray *bots))completion;

#pragma mark - discovery

/// Bots similar to a given bot, for the "Similar bots" profile section.
/// Same entry shape as -recentInlineBotsWithCompletion:. `total` is what the
/// server says exists, which can exceed the number of entries returned.
- (void)similarBotsFor:(int64_t)botUserId
            completion:(void (^)(NSArray *bots, NSInteger total))completion;

#pragma mark - message decoration

/// "via @bot" attribution for a message sent through an inline bot, or nil.
/// The completion runs on the main queue once the bot's username is known.
- (void)viaBotForMessage:(NSDictionary *)message
              completion:(void (^)(NSString *username))completion;

/// Grey service line for the bot-related service messages: write access
/// allowed, users shared, chat shared, web app data sent. Nil for anything
/// else, so the caller can fall through to its own service-text handling.
- (NSString *)botServiceTextForMessage:(NSDictionary *)message;

@end

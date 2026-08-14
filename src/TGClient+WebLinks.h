/**
 * TGClient+WebLinks - web page previews, link previews, t.me resolution and
 * internal link types.
 *
 * Everything here returns plain Foundation objects. No TDLib schema knowledge
 * is needed by the UI layer: dictionaries use camelCase keys and enum-ish
 * strings with the td_api prefix stripped ("publicChat", not
 * "internalLinkTypePublicChat").
 *
 * Deliberately NOT here, because other categories already wrap them:
 *   getMessageLink / getMessageLinkInfo  -> TGClient+Messages, +MessageContent
 *   getLinkPreview (plain text form)     -> TGClient+MessageContent
 *   checkChatInviteLink / joinChatByInviteLink -> TGClient+ChatManagement
 *   searchPublicChat / searchPublicChats -> TGClient.m, TGClient+ChatList
 */
#import "TGClient.h"

@interface TGClient (WebLinks)

#pragma mark - link routing

/**
 * Classify a tapped URL (http, https, t.me or tg://) so the router can decide
 * where to send the user.
 *
 * The completion receives nil when the link is not a Telegram link at all (open
 * it in Safari), otherwise a dictionary:
 *   "kind"        NSString, the td_api InternalLinkType with the
 *                 "internalLinkType" prefix removed and lower-cased first
 *                 letter: "publicChat", "message", "chatInvite", "stickerSet",
 *                 "instantView", "unknownDeepLink", "botStart", "userToken",
 *                 "userPhoneNumber", "videoChat", "webApp", ...
 *   "supported"   NSNumber BOOL, NO for link kinds this client cannot act on
 *                 (mini apps, passport, invoices, premium purchases ...). Show
 *                 a "not supported in this app" alert and offer Safari.
 *   "link"        NSString, the original url that was resolved.
 * plus, when the kind carries them, any of:
 *   "username", "draftText", "openProfile", "phoneNumber", "token",
 *   "inviteLink", "url", "fallbackUrl", "stickerSetName", "expectCustomEmoji",
 *   "botUsername", "startParameter", "autostart", "gameShortName",
 *   "themeName", "languagePackId", "backgroundName", "storyId", "code",
 *   "deepLink", "webAppShortName", "section", "referrer", "inviteHash",
 *   "isLiveStream".
 * Missing keys simply mean the link type does not have that field.
 */
- (void)resolveLink:(NSString *)url
         completion:(void (^)(NSDictionary *link))completion;

/**
 * Build a shareable link for something in the app (public chat, sticker set,
 * bot start link, chat invite...).
 *
 * `type` is a raw td_api InternalLinkType dictionary, e.g.
 *   @{@"@type" : @"internalLinkTypePublicChat", @"chat_username" : @"durov"}
 * Pass isHttp YES for an https://t.me/... link, NO for a tg://... one.
 * The completion receives the url string, or nil on failure.
 */
- (void)linkForInternalType:(NSDictionary *)type
                     isHttp:(BOOL)isHttp
                 completion:(void (^)(NSString *url))completion;

/// t.me link to a public chat / user by username. Nil on failure.
- (void)publicLinkForUsername:(NSString *)username
                   completion:(void (^)(NSString *url))completion;

/// t.me link to a sticker set by its short name. Nil on failure.
- (void)publicLinkForStickerSetName:(NSString *)name
                         completion:(void (^)(NSString *url))completion;

#pragma mark - external links

/**
 * Ask TDLib what should happen before opening a plain http(s) link that came
 * from message text. Use it for the "Open this link?" confirmation.
 *
 * The completion receives:
 *   "url"                  NSString, what to open
 *   "needsConfirmation"    NSNumber BOOL. NO means open "url" straight away.
 *   "domain"               NSString, shown in the confirmation ("example.com")
 *   "botUserId"            NSNumber, the bot that would learn your identity
 *   "requestWriteAccess"   NSNumber BOOL, show an "allow write access" toggle
 * Nil when TDLib refused; in that case just open the original url.
 */
- (void)externalLinkInfoForUrl:(NSString *)url
                    completion:(void (^)(NSDictionary *info))completion;

/**
 * Second half of the external-link flow: called after the user confirmed.
 * Receives the url actually to hand to [UIApplication openURL:], or nil.
 */
- (void)externalLinkForUrl:(NSString *)url
          allowWriteAccess:(BOOL)allowWriteAccess
                completion:(void (^)(NSString *url))completion;

/**
 * Seamless Telegram Login: what to show before following an inline keyboard
 * button of type inlineKeyboardButtonTypeLoginUrl. Completion dictionary has
 * the same keys as -externalLinkInfoForUrl:completion:.
 */
- (void)loginUrlInfoForButton:(int64_t)buttonId
                    inMessage:(int64_t)messageId
                       inChat:(int64_t)chatId
                   completion:(void (^)(NSDictionary *info))completion;

/**
 * Second half of the login-url flow, after the user pressed OK. Receives the
 * http url to open, or nil.
 */
- (void)loginUrlForButton:(int64_t)buttonId
                inMessage:(int64_t)messageId
                   inChat:(int64_t)chatId
         allowWriteAccess:(BOOL)allowWriteAccess
               completion:(void (^)(NSString *url))completion;

/**
 * A tg:// deep link this build does not understand. The server supplies the
 * text to show in an alert. `needsUpdate` YES means the alert should offer an
 * "Update App" button. `text` is nil when TDLib had nothing to say.
 */
- (void)deepLinkInfoForUrl:(NSString *)url
                completion:(void (^)(NSString *text, BOOL needsUpdate))completion;

#pragma mark - link previews

/**
 * Link preview for text the user is typing in the composer, with explicit
 * options. Call it debounced; pass the whole composer text, TDLib finds the
 * url itself.
 *
 * `options` may be nil, or the dictionary from
 * +linkPreviewOptionsDisabled:url:forceSmallMedia:forceLargeMedia:showAboveText:.
 * The completion receives the same flattened shape as +flattenedLinkPreview:,
 * or nil when the text contains no previewable link.
 */
- (void)linkPreviewForText:(NSString *)text
               withOptions:(NSDictionary *)options
                completion:(void (^)(NSDictionary *preview))completion;

/**
 * Build the link_preview_options dictionary to attach to an inputMessageText
 * when sending or editing a message. Pass "" for url to let TDLib pick the
 * link out of the text itself. The result is a raw td_api object, ready to be
 * put under the "link_preview_options" key.
 */
+ (NSDictionary *)linkPreviewOptionsDisabled:(BOOL)disabled
                                         url:(NSString *)url
                             forceSmallMedia:(BOOL)forceSmall
                             forceLargeMedia:(BOOL)forceLarge
                               showAboveText:(BOOL)showAboveText;

/**
 * Flatten the linkPreview object that arrives inline on a messageText content
 * (message["content"]["link_preview"]) into something the bubble can measure.
 *
 * Returns nil when there is no preview, otherwise:
 *   "url", "displayUrl", "siteName", "title", "description", "author"  NSString
 *   "kind"          NSString, LinkPreviewType with the prefix stripped:
 *                   "article", "photo", "video", "user", "chat", "document",
 *                   "audio", "voiceNote", "sticker", "animation",
 *                   "externalVideo", "externalAudio", "embeddedVideoPlayer",
 *                   "unsupported", ...
 *   "mediaKind"     NSString, coarse bucket for picking an existing attachment
 *                   view: "photo", "video", "audio", "voice", "document",
 *                   "sticker", "animation", "external" or "none".
 *   "hasLargeMedia", "showLargeMedia", "showMediaAboveDescription",
 *   "showAboveText", "skipConfirmation"      NSNumber BOOL
 *   "instantViewVersion"                     NSNumber
 *   "hasInstantView"                         NSNumber BOOL, gate the
 *                                            "Instant View" button on this
 *   "photoFileId"   NSNumber, best still image to show, when there is one
 *   "width", "height"                        NSNumber, of that image
 *   "mediaFileId"   NSNumber, the video/audio/document/sticker file itself
 *   "duration"      NSNumber, seconds, for playable types
 *   "mimeType", "externalUrl"                NSString, for external media
 *   "fileName"      NSString, for documents
 */
+ (NSDictionary *)flattenedLinkPreview:(NSDictionary *)preview;

/**
 * Flatten a formattedText into tappable runs for the custom CoreText label.
 *
 * Returns an array of dictionaries, sorted by offset. Offsets and lengths are
 * UTF-16 units, so they index NSString directly:
 *   "offset", "length"   NSNumber
 *   "kind"               NSString, TextEntityType with the prefix stripped:
 *                        "url", "textUrl", "emailAddress", "phoneNumber",
 *                        "mention", "mentionName", "hashtag", "cashtag",
 *                        "bankCardNumber", "bold", "italic", "underline",
 *                        "strikethrough", "code", "pre", "preCode",
 *                        "blockQuote", "spoiler", "customEmoji", ...
 *   "tappable"           NSNumber BOOL, YES for the link-ish kinds
 *   "url"                NSString, for "textUrl"
 *   "userId"             NSNumber, for "mentionName"
 *   "text"               NSString, the substring the entity covers
 * Returns an empty array when there is nothing to mark up.
 */
+ (NSArray *)tappableEntitiesIn:(NSDictionary *)formattedText;

#pragma mark - instant view

/**
 * Load the Instant View article for a url.
 *
 * The completion may be called TWICE: first with the locally cached version
 * (so the reader can paint immediately), then again with the freshly fetched
 * one. Callers must be able to replace their content. When nothing is cached
 * only the network result arrives; on total failure it is called once with
 * nil.
 *
 * The dictionary is:
 *   "blocks"        NSArray of flattened page blocks, see below
 *   "viewCount"     NSNumber
 *   "version"       NSNumber, 1 or 2
 *   "isRtl", "isFull"                        NSNumber BOOL
 *   "feedbackLink" NSString, url for the "Leave a comment" footer row, or absent
 *
 * Each block dictionary has:
 *   "kind"    NSString, PageBlock with the "pageBlock" prefix stripped:
 *             "title", "subtitle", "authorDate", "header", "subheader",
 *             "sectionHeading", "kicker", "paragraph", "preformatted",
 *             "footer", "divider", "anchor", "list", "blockQuote",
 *             "pullQuote", "photo", "animation", "video", "audio",
 *             "voiceNote", "cover", "embedded", "embeddedPost", "collage",
 *             "slideshow", "chatLink", "table", "details", "relatedArticles",
 *             "map", "unsupported".
 *   "text"    NSString, the plain text of the block, when it has any
 *   "runs"    NSArray of style runs over "text", same shape as
 *             +tappableEntitiesIn: ("offset", "length", "kind", "tappable",
 *             "url", "anchor", "email", "phone"), where "kind" is the RichText
 *             type stripped: "bold", "italic", "underline", "strikethrough",
 *             "fixed", "marked", "url", "emailAddress", "phoneNumber",
 *             "anchorLink", "mention", "hashtag".
 *   "captionText", "captionRuns", "creditText"  for media blocks
 * and, per kind:
 *   photo/cover/embedded : "photoFileId", "width", "height", "url"
 *   animation/video      : "fileId", "photoFileId", "width", "height",
 *                          "duration", "autoplay", "looped"
 *   audio/voiceNote      : "fileId", "duration"
 *   list                 : "items", array of {"label", "blocks"}
 *   blockQuote/details/collage/slideshow/embeddedPost : "blocks", nested array
 *   details              : plus "isOpen"
 *   preformatted         : "language"
 *   anchor               : "name"
 *   sectionHeading       : "size"
 *   chatLink             : "title", "username", "photoFileId"
 *   table                : "rows", array of arrays of
 *                          {"text", "runs", "isHeader", "colspan", "rowspan",
 *                           "align", "valign"}, plus "isBordered", "isStriped"
 *   relatedArticles      : "articles", array of {"url", "title",
 *                          "description", "author", "publishDate",
 *                          "photoFileId"}
 *   map                  : "latitude", "longitude", "zoom", "width", "height"
 *
 * Note: "embedded" and "embeddedPost" html cannot be run by the iOS 6
 * UIWebView. Render "photoFileId" as a poster and open "url" in Safari.
 */
- (void)instantViewForUrl:(NSString *)url
               completion:(void (^)(NSDictionary *view))completion;

/// Single-shot form of the above: one network (or one cache) load only.
- (void)instantViewForUrl:(NSString *)url
                onlyLocal:(BOOL)onlyLocal
               completion:(void (^)(NSDictionary *view))completion;

#pragma mark - misc t.me

/**
 * Recently visited t.me urls, for a suggestions section in global search.
 * `referrer` may be nil. Each entry:
 *   "url"        NSString
 *   "kind"       NSString: "user", "supergroup", "chatInvite", "stickerSet"
 *   "userId", "supergroupId", "stickerSetId"   NSNumber, per kind
 *   "title", "memberCount", "photoFileId"      for "chatInvite"
 * The array is empty when there is nothing to suggest.
 */
- (void)recentlyVisitedTMeUrlsWithReferrer:(NSString *)referrer
                                completion:(void (^)(NSArray *urls))completion;

/**
 * HTML embedding code for a message in a public chat, for a "Copy Embed Code"
 * row. Nil when the message cannot be embedded.
 */
- (void)embeddingCodeForMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                       forAlbum:(BOOL)forAlbum
                     completion:(void (^)(NSString *code))completion;

/// Download link for this application, for the invite-friends SMS body.
- (void)applicationDownloadLinkWithCompletion:(void (^)(NSString *url))completion;

@end

// vim:ft=objc

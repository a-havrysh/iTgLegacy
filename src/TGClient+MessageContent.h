//
// TGClient+MessageContent - everything a message can carry: photos, video,
// voice, video notes, documents, GIFs, music, locations, venues, contacts,
// polls, dice, stickers, stories - plus captions, text entities and links.
//
// Sending methods that take a `thread` pass 0 for a normal chat; a non-zero
// value is a forum topic id.
//
#import "TGClient.h"

@interface TGClient (MessageContent)

#pragma mark - text entities

/// Run TDLib's Markdown parser over composer text. `completion` gets the plain
/// text with the markers removed, and the entities as flattened dictionaries
/// (see -entitiesInText:completion: for their shape). On a parse failure it
/// gets the original text and an empty array, never nil.
- (void)parseMarkdown:(NSString *)text
           completion:(void (^)(NSString *plainText, NSArray *entities))completion;

/// Entities TDLib finds in plain text without any markup: urls, mentions,
/// hashtags, bot commands, phone numbers, e-mail addresses. Each entry is
/// "offset" and "length" (NSNumber, UTF-16 units, usable with NSRange),
/// "kind" (NSString, the TextEntityType name without the "textEntityType"
/// prefix, e.g. "Bold", "TextUrl", "Spoiler", "BlockQuote", "MediaTimestamp"),
/// "url" (NSString, empty unless the entity carries one), "userId" (NSNumber,
/// 0 unless a mention of a user without a username), "language" (NSString,
/// the syntax of a PreCode block), "timestamp" (NSNumber, seconds into the
/// referenced media for a MediaTimestamp entity).
- (void)entitiesInText:(NSString *)text
            completion:(void (^)(NSArray *entities))completion;

/// Parse `text` as Markdown and send the result, so bold, italic, code and
/// [links](url) typed in the composer survive. `threadId` and `replyToId` may
/// be 0.
- (void)sendMarkdown:(NSString *)text
              toChat:(int64_t)chatId
              thread:(int64_t)threadId
             replyTo:(int64_t)replyToId;

/// The text or caption of one message together with its entities, which the
/// flattened message form does not carry. `completion` gets the plain text and
/// the same entity dictionaries as above; both are empty when the message has
/// no text.
- (void)formattedTextForMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSString *text, NSArray *entities))completion;

/// Replace the caption of a photo, video, document or audio message already
/// sent. `caption` is parsed as Markdown. `completion` gets YES on success.
- (void)editCaptionOfMessage:(int64_t)messageId
                      inChat:(int64_t)chatId
                     caption:(NSString *)caption
                  completion:(void (^)(BOOL ok))completion;

#pragma mark - inspecting media

/// Everything the UI needs to draw and open a media message, flattened out of
/// whatever content type it turns out to be. `completion` gets nil for a
/// message with no media, otherwise a dictionary with:
///   "kind"        the TDLib content type name, e.g. "messageVideo"
///   "fileId"      NSNumber, the file to download and open (0 when there is none)
///   "thumbId"     NSNumber, a small file to show while waiting (0 when none)
///   "fileName"    NSString, may be empty
///   "mimeType"    NSString, may be empty
///   "size"        NSNumber, bytes of the main file
///   "width"/"height"  NSNumber pixels, 0 when not applicable
///   "duration"    NSNumber seconds, 0 when not applicable
///   "caption"     NSString
///   "title"/"performer"  NSString, audio only
///   "waveform"    NSData, voice notes only, five bits per sample
///   "hasSpoiler"  NSNumber BOOL, media the sender covered up
///   "isSecret"    NSNumber BOOL, self-destructing media
///   "isViewed"    NSNumber BOOL, video/voice notes already played
///   "minithumb"   NSData, a tiny JPEG TDLib ships inline, or empty
- (void)mediaInfoForMessage:(int64_t)messageId
                     inChat:(int64_t)chatId
                 completion:(void (^)(NSDictionary *info))completion;

/// Tell TDLib the user actually opened this message: marks a voice note or
/// video note as listened/viewed and starts the timer of self-destructing
/// media. Call it when playback starts or a viewer is pushed.
- (void)openContentOfMessage:(int64_t)messageId inChat:(int64_t)chatId;

/// The line to show for content this client cannot render - expired photos and
/// videos, expired voice and video notes, unsupported content. Returns nil for
/// a kind that is not one of those, so callers can fall through to their own
/// drawing. `kind` is the "kind" of a flattened message.
- (NSString *)placeholderTextForContentKind:(NSString *)kind;

#pragma mark - sending media

/// Photo send with the parts the plain -sendPhotoAtPath:toChat: leaves out:
/// a Markdown caption, the blurred-cover spoiler flag, and a self-destruct
/// timer in seconds (0 for an ordinary photo).
- (void)sendPhotoAtPath:(NSString *)path
                 toChat:(int64_t)chatId
                 thread:(int64_t)threadId
                caption:(NSString *)caption
                spoiler:(BOOL)spoiler
     selfDestructSeconds:(NSInteger)selfDestructSeconds;

/// The same for video. `duration`, `width` and `height` may be 0 when unknown;
/// giving them lets other clients show the right placeholder before download.
- (void)sendVideoAtPath:(NSString *)path
                 toChat:(int64_t)chatId
                 thread:(int64_t)threadId
                caption:(NSString *)caption
               duration:(NSInteger)duration
                  width:(NSInteger)width
                 height:(NSInteger)height
                spoiler:(BOOL)spoiler
     selfDestructSeconds:(NSInteger)selfDestructSeconds;

/// Send an MP4 as a Telegram GIF, which is what "animation" means here.
- (void)sendAnimationAtPath:(NSString *)path
                     toChat:(int64_t)chatId
                     thread:(int64_t)threadId
                    caption:(NSString *)caption;

/// Send a music file. `title` and `performer` may be nil; `duration` may be 0.
- (void)sendAudioAtPath:(NSString *)path
                 toChat:(int64_t)chatId
                 thread:(int64_t)threadId
                  title:(NSString *)title
              performer:(NSString *)performer
               duration:(NSInteger)duration
                caption:(NSString *)caption;

/// Send any file as a document, without letting the server guess a nicer type
/// for it.
- (void)sendDocumentAtPath:(NSString *)path
                    toChat:(int64_t)chatId
                    thread:(int64_t)threadId
                   caption:(NSString *)caption;

/// Send several photos as one album - they arrive sharing a media_album_id and
/// are drawn as a single block. `caption` goes on the first one, as every
/// Telegram client does it. `completion` gets the number of messages accepted.
- (void)sendPhotoAlbumAtPaths:(NSArray *)paths
                       toChat:(int64_t)chatId
                       thread:(int64_t)threadId
                      caption:(NSString *)caption
                   completion:(void (^)(NSInteger sent))completion;

/// Send a named place rather than a bare point: the bubble shows title and
/// address over the map.
- (void)sendVenueWithTitle:(NSString *)title
                   address:(NSString *)address
                  latitude:(double)latitude
                 longitude:(double)longitude
                    toChat:(int64_t)chatId;

/// Start sharing a moving location for `period` seconds (Telegram accepts
/// 60..86400). `completion` gets the message id to keep updating, or 0.
- (void)sendLiveLocationWithLatitude:(double)latitude
                           longitude:(double)longitude
                              period:(NSInteger)period
                              toChat:(int64_t)chatId
                          completion:(void (^)(int64_t messageId))completion;

/// Move a live location that is already being shared.
- (void)updateLiveLocation:(int64_t)messageId
                    inChat:(int64_t)chatId
                  latitude:(double)latitude
                 longitude:(double)longitude;

/// Stop sharing before the period runs out.
- (void)stopLiveLocation:(int64_t)messageId inChat:(int64_t)chatId;

/// Send a dice or slot machine. `emoji` is the face to roll - the die, the
/// dart, the basketball, the slot machine - or nil for the plain die.
- (void)sendDice:(NSString *)emoji toChat:(int64_t)chatId thread:(int64_t)threadId;

#pragma mark - polls

/// Create a poll. `options` are plain strings. For a quiz pass the index of
/// the right answer in `quizCorrectOption`; pass -1 for a regular poll, where
/// `multipleAnswers` decides whether several options can be picked.
/// `completion` gets the new message id, or 0 when the poll was rejected.
- (void)sendPollWithQuestion:(NSString *)question
                     options:(NSArray *)options
                   anonymous:(BOOL)anonymous
             multipleAnswers:(BOOL)multipleAnswers
           quizCorrectOption:(NSInteger)quizCorrectOption
                      toChat:(int64_t)chatId
                      thread:(int64_t)threadId
                  completion:(void (^)(int64_t messageId))completion;

/// Close a poll so no more votes are taken. Only the sender may do it.
- (void)stopPoll:(int64_t)messageId inChat:(int64_t)chatId;

/// Who voted for one option, newest first. `optionIndex` is the index into the
/// poll's options. Each entry is "id" (NSNumber user id) and "name". Empty for
/// an anonymous poll, which never reveals its voters.
- (void)votersForPollOption:(NSInteger)optionIndex
                  ofMessage:(int64_t)messageId
                     inChat:(int64_t)chatId
                      limit:(NSInteger)limit
                 completion:(void (^)(NSArray *voters, NSInteger total))completion;

#pragma mark - links

/// A t.me link to one message, for the Copy Link action. Pass a non-zero
/// `mediaTimestamp` to link into a point of the audio or video, and YES for
/// `forAlbum` to link the whole album a photo belongs to. `completion` gets
/// nil when the chat has no public link.
- (void)linkForMessage:(int64_t)messageId
                inChat:(int64_t)chatId
        mediaTimestamp:(NSInteger)mediaTimestamp
              forAlbum:(BOOL)forAlbum
            completion:(void (^)(NSString *link))completion;

/// The other direction: what a t.me message link points at. `completion` gets
/// "chatId", "messageId" and "mediaTimestamp" (NSNumbers), or nil.
- (void)resolveMessageLink:(NSString *)url
                completion:(void (^)(NSDictionary *info))completion;

/// The web page Telegram would attach under a message containing this text.
/// `completion` gets nil when there is nothing to preview, otherwise "url",
/// "siteName", "title", "description", "kind" (the LinkPreviewType name) and
/// "photoId" (NSNumber file id, 0 when the preview has no image).
- (void)linkPreviewForText:(NSString *)text
                completion:(void (^)(NSDictionary *preview))completion;

#pragma mark - odds and ends

/// Translate a message's text or caption. `languageCode` is a two-letter code
/// such as "en". `completion` gets the translation, or nil.
- (void)translateMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
              toLanguage:(NSString *)languageCode
              completion:(void (^)(NSString *text))completion;

/// A rendered map tile around a point, as a TDLib file id to hand to
/// -downloadFile:completion:. `zoom` is 13..20, `width`/`height` 16..1024,
/// `scale` 1..3. `completion` gets 0 when the tile is unavailable.
- (void)mapThumbnailForLatitude:(double)latitude
                      longitude:(double)longitude
                           zoom:(NSInteger)zoom
                          width:(NSInteger)width
                         height:(NSInteger)height
                          scale:(NSInteger)scale
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSInteger fileId))completion;

/// Tapping a large animated emoji plays an effect for both sides. `completion`
/// gets the file id of the effect sticker to play, or 0 when there is none.
- (void)clickAnimatedEmojiInMessage:(int64_t)messageId
                             inChat:(int64_t)chatId
                         completion:(void (^)(NSInteger stickerFileId))completion;

/// The story behind a "story shared" bubble. `completion` gets nil when it is
/// gone, otherwise "caption", "date" (NSNumber), "isVideo" (NSNumber BOOL),
/// "fileId" and "thumbId" (NSNumbers).
- (void)storyForMessage:(int64_t)messageId
                 inChat:(int64_t)chatId
             completion:(void (^)(NSDictionary *story))completion;

@end

// vim:ft=objc

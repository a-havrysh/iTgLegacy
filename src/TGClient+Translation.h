//
// TGClient+Translation - message translation, language packs and speech
// recognition.
//
// Naming note for other areas: TGClient+Messages already declares the plain
// -translateMessage:inChat:toLanguage:completion: and
// -translateText:toLanguage:completion:. The methods here are the tone-aware
// and batching supersets, deliberately named differently so both can coexist.
// TGClient.h itself already has -languagesWithCompletion: and -setLanguage:.
//
#import "TGClient.h"

@interface TGClient (Translation)

#pragma mark - translating text

/// Translate one message's text. `tone` is nil for the default, or one of
/// "formal", "neutral", "casual" - it is passed straight through to TDLib.
/// Completion gets the translated plain text, or nil on any failure
/// (unsupported language pair, Premium-gated call, network).
- (void)translateMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
              toLanguage:(NSString *)languageCode
                    tone:(NSString *)tone
              completion:(void (^)(NSString *text))completion;

/// Translate arbitrary text (composer contents, a bio, a caption).
/// Completion gets the translated plain text, or nil on failure.
- (void)translateText:(NSString *)text
           toLanguage:(NSString *)languageCode
                 tone:(NSString *)tone
           completion:(void (^)(NSString *text))completion;

/// Server-side flag behind the per-chat "Translate this chat" bar. TDLib
/// answers with updateChatIsTranslatable; nothing else is needed locally.
- (void)setChat:(int64_t)chatId translatable:(BOOL)translatable;

#pragma mark - language packs

/// Every language pack this account can see, richer than TGClient's
/// -languagesWithCompletion:. Each entry is a dictionary with keys:
/// "id", "name", "nativeName", "pluralCode", "baseId", "official" (NSNumber
/// bool), "rtl", "beta", "installed", "totalStrings", "translatedStrings",
/// "localStrings", "translationUrl". `current` is the language_pack_id in
/// effect. Falls back to the local-only list when the server refuses.
/// Completion gets an empty array (never nil) if there is nothing at all.
- (void)languagePacksWithCompletion:(void (^)(NSArray *packs,
                                              NSString *current))completion;

/// Pull the newest strings of a pack from the server. Fire and forget.
- (void)synchronizeLanguagePack:(NSString *)packId;

/// Strings of a pack, for a TGLang-style lookup layer. Pass nil or an empty
/// `keys` array for the whole pack. Completion gets a dictionary keyed by the
/// string key; an ordinary value maps to an NSString, a pluralised one to a
/// dictionary with the "zero"/"one"/"two"/"few"/"many"/"other" keys that are
/// present. Deleted strings are omitted. Never nil, empty on failure.
- (void)languagePackStrings:(NSString *)packId
                       keys:(NSArray *)keys
                 completion:(void (^)(NSDictionary *strings))completion;

/// Remove a downloaded pack. Fails on the pack currently in use, so switch
/// away first. Completion gets YES when it was actually deleted.
- (void)deleteLanguagePack:(NSString *)packId
                completion:(void (^)(BOOL deleted))completion;

#pragma mark - speech recognition

/// Current transcription state of a message. Completion gets a dictionary:
/// "state" is "pending", "text" or "error"; "text" is the partial or final
/// transcript ("" while nothing is available); "error" is a human-readable
/// message when state is "error". Completion gets nil when the message has no
/// voice or video note, or has never been transcribed - that is the
/// "show the transcribe glyph" case.
- (void)speechTranscriptForMessage:(int64_t)messageId
                            inChat:(int64_t)chatId
                        completion:(void (^)(NSDictionary *transcript))completion;

/// Send the Good / Bad feedback offered under a finished transcript.
- (void)rateSpeechRecognitionForMessage:(int64_t)messageId
                                 inChat:(int64_t)chatId
                                   good:(BOOL)good;

@end

// vim:ft=objc

//
// TGMediaModel - the media payload of a message, typed.
//
// Built from a TDLib message content dictionary (messagePhoto, messageVideo,
// messageDocument, messageAudio, messageVoiceNote, messageVideoNote,
// messageAnimation, messageSticker, messageAnimatedEmoji). One class with a
// `kind` rather than a class family: every one of those payloads is the same
// shape - a main file, optional pixel size, optional duration, an optional
// thumbnail - and the screens already switch on the content type to decide
// what to draw. A subclass family would only make a screen ask
// isKindOfClass again, which is the thing this layer exists to remove.
//
// Immutable. Nothing here retains the source dictionary.
//
#import <Foundation/Foundation.h>

typedef enum {
	TGMediaKindUnknown = 0,
	TGMediaKindPhoto,
	TGMediaKindVideo,
	TGMediaKindAnimation,
	TGMediaKindDocument,
	TGMediaKindAudio,
	TGMediaKindVoiceNote,
	TGMediaKindVideoNote,
	TGMediaKindSticker
} TGMediaKind;

/// One entry of a photo's `sizes` array. A photo arrives as several files at
/// different pixel sizes and the screen picks the one it needs for its width.
@interface TGMediaPhotoSize : NSObject

/// TDLib file id to hand to -downloadFile:completion:. Never 0 on a built object.
@property (nonatomic, readonly) int64_t fileId;
@property (nonatomic, readonly) NSInteger width;
@property (nonatomic, readonly) NSInteger height;
/// Telegram's one-letter size class ("s", "m", "x", "y", "w"). Optional, nil when absent.
@property (nonatomic, readonly, copy) NSString *sizeType;
/// Bytes of this size's file. 0 when TDLib did not say.
@property (nonatomic, readonly) int64_t fileSize;

/// Builds from a TDLib photoSize. Returns nil unless it carries a usable file id.
+ (instancetype)fromDictionary:(NSDictionary *)dict;
/// Maps an array, dropping entries that fail to build. Never returns nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

@end


@interface TGMediaModel : NSObject

#pragma mark - what this is

/// Which payload it turned out to be. Never TGMediaKindUnknown on a built object.
@property (nonatomic, readonly) TGMediaKind kind;
/// The TDLib content type name it came from, e.g. "messageVideoNote". Never nil.
@property (nonatomic, readonly, copy) NSString *rawKind;

#pragma mark - the file

/// The file to download and open: the video, the document, the voice recording,
/// the largest photo size. Never 0 on a built object.
@property (nonatomic, readonly) int64_t fileId;
/// Bytes of that file. Falls back to TDLib's expected_size while it is still
/// being fetched, and is 0 when neither is known.
@property (nonatomic, readonly) int64_t fileSize;
/// Original name. Optional - nil for photos, voice notes, video notes and stickers.
@property (nonatomic, readonly, copy) NSString *fileName;
/// Optional, nil when TDLib sent none.
@property (nonatomic, readonly, copy) NSString *mimeType;
/// Local path when the file is already on disk, otherwise nil. Optional.
@property (nonatomic, readonly, copy) NSString *localPath;
/// YES when the main file is fully downloaded and -localPath is usable.
@property (nonatomic, readonly) BOOL isDownloaded;

#pragma mark - dimensions and duration

/// Pixels. 0 for documents, audio and voice notes. A video note is square, so
/// both carry its `length`.
@property (nonatomic, readonly) NSInteger width;
@property (nonatomic, readonly) NSInteger height;
/// Seconds. 0 for photos, documents and stickers.
@property (nonatomic, readonly) NSInteger duration;

#pragma mark - thumbnail

/// A small file to show while the main one downloads. Optional - 0 when the
/// payload has no thumbnail, or has one this device cannot decode (TDLib may
/// send WEBP or MPEG4 thumbnails; only JPEG and PNG are accepted here).
@property (nonatomic, readonly) int64_t thumbnailFileId;
/// Pixels of that thumbnail, 0 when there is none.
@property (nonatomic, readonly) NSInteger thumbnailWidth;
@property (nonatomic, readonly) NSInteger thumbnailHeight;
/// The tiny inline JPEG TDLib ships with the message, already base64-decoded,
/// good enough to blur behind a loading tile. Optional, nil when absent.
@property (nonatomic, readonly, copy) NSData *minithumbnail;

#pragma mark - per-kind extras

/// Photo only: every size the photo was sent in, smallest first. Empty array
/// for every other kind, never nil.
@property (nonatomic, readonly, copy) NSArray *photoSizes;
/// Voice note only: five bits per sample, decoded from base64, for drawing the
/// bars. Optional, nil for every other kind and for a voice note that carried none.
@property (nonatomic, readonly, copy) NSData *waveform;
/// Audio track title. Optional, nil when absent or not an audio.
@property (nonatomic, readonly, copy) NSString *title;
/// Audio performer. Optional, nil when absent or not an audio.
@property (nonatomic, readonly, copy) NSString *performer;
/// Sticker and animated emoji only: the emoji it stands for. Optional.
@property (nonatomic, readonly, copy) NSString *emoji;
/// Sticker only: the TDLib sticker format name without its prefix - "Webp",
/// "Tgs", "Webm". Optional, nil for other kinds.
@property (nonatomic, readonly, copy) NSString *stickerFormat;

#pragma mark - flags

/// The caption typed under the media. Optional, nil when there is none.
@property (nonatomic, readonly, copy) NSString *caption;
/// The sender covered it up; it must be blurred until tapped.
@property (nonatomic, readonly) BOOL hasSpoiler;
/// Self-destructing media.
@property (nonatomic, readonly) BOOL isSecret;
/// A voice or video note that has already been listened to or watched.
@property (nonatomic, readonly) BOOL isViewed;

#pragma mark - derived

/// Video, animation and video note: something that plays as moving pictures.
@property (nonatomic, readonly) BOOL isVideo;
/// Voice note and audio: something the audio player handles.
@property (nonatomic, readonly) BOOL isAudio;

#pragma mark - building

/// Builds from a TDLib message **content** dictionary (the object whose "@type"
/// is "messagePhoto" and so on). Returns nil when the input is not a
/// dictionary, is a content type that carries no media, or carries no usable
/// file id. Never returns a half-built object.
+ (instancetype)fromDictionary:(NSDictionary *)dict;

/// Convenience for a whole TDLib message: digs out its "content" and builds
/// from that. Returns nil on the same terms.
+ (instancetype)fromMessageDictionary:(NSDictionary *)message;

/// Maps an array of content dictionaries, dropping entries that fail to build,
/// so one malformed element cannot take the list down. Never returns nil.
+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts;

/// Maps an array of whole TDLib messages the same way. Never returns nil.
+ (NSArray *)arrayFromMessageDictionaries:(NSArray *)messages;

@end

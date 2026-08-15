#import "TGMediaModel.h"

static NSDictionary *TGMMDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? (NSDictionary *)value : nil;
}

static NSArray *TGMMArray(id value) {
	return [value isKindOfClass:NSArray.class] ? (NSArray *)value : nil;
}

static NSString *TGMMString(id value) {
	if ([value isKindOfClass:NSString.class])
		return ((NSString *)value).length ? [value copy] : nil;
	return nil;
}

static int64_t TGMMLongLong(id value) {
	if ([value isKindOfClass:NSNumber.class])
		return [(NSNumber *)value longLongValue];
	if ([value isKindOfClass:NSString.class])
		return [(NSString *)value longLongValue];
	return 0;
}

static NSInteger TGMMInteger(id value) {
	int64_t big = TGMMLongLong(value);
	if (big > 2147483647LL)  return 2147483647;
	if (big < -2147483648LL) return -2147483648;
	return (NSInteger)big;
}

static BOOL TGMMBool(id value) {
	return [value isKindOfClass:NSNumber.class] && [(NSNumber *)value boolValue];
}

static NSData *TGMMBase64(id value) {
	NSString *text = TGMMString(value);
	if (!text)
		return nil;

	static signed char table[256];
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		memset(table, -1, sizeof(table));
		const char *alphabet =
			"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		for (int i = 0; i < 64; i++)
			table[(unsigned char)alphabet[i]] = (signed char)i;
		table[(unsigned char)'-'] = 62;
		table[(unsigned char)'_'] = 63;
	});

	NSData *ascii = [text dataUsingEncoding:NSASCIIStringEncoding
					   allowLossyConversion:YES];
	if (!ascii.length)
		return nil;

	const unsigned char *src = (const unsigned char *)ascii.bytes;
	NSUInteger length = ascii.length;
	NSMutableData *out = [NSMutableData dataWithCapacity:length * 3 / 4 + 3];
	unsigned char chunk[192];
	NSUInteger filled = 0;
	unsigned int accumulator = 0;
	int bits = 0;

	for (NSUInteger i = 0; i < length; i++){
		signed char decoded = table[src[i]];
		if (decoded < 0)
			continue;
		accumulator = (accumulator << 6) | (unsigned int)decoded;
		bits += 6;
		if (bits >= 8){
			bits -= 8;
			chunk[filled++] = (unsigned char)((accumulator >> bits) & 0xFF);
			if (filled == sizeof(chunk)){
				[out appendBytes:chunk length:filled];
				filled = 0;
			}
		}
	}
	if (filled)
		[out appendBytes:chunk length:filled];
	return out.length ? [out copy] : nil;
}

static int64_t TGMMFileSize(NSDictionary *file) {
	int64_t size = TGMMLongLong(file[@"size"]);
	if (size <= 0)
		size = TGMMLongLong(file[@"expected_size"]);
	return size > 0 ? size : 0;
}


@interface TGMediaPhotoSize ()
@property (nonatomic, assign) int64_t fileId;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, copy) NSString *sizeType;
@property (nonatomic, assign) int64_t fileSize;
@end

@implementation TGMediaPhotoSize

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	NSDictionary *source = TGMMDict(dict);
	if (!source)
		return nil;

	NSDictionary *file = TGMMDict(source[@"photo"]);
	int64_t fileId = TGMMLongLong(file[@"id"]);
	if (fileId == 0)
		return nil;

	TGMediaPhotoSize *size = [[TGMediaPhotoSize alloc] init];
	size.fileId = fileId;
	size.width = TGMMInteger(source[@"width"]);
	size.height = TGMMInteger(source[@"height"]);
	size.sizeType = TGMMString(source[@"type"]);
	size.fileSize = TGMMFileSize(file);
	return size;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	NSArray *source = TGMMArray(dicts);
	if (!source.count)
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:source.count];
	for (id entry in source){
		TGMediaPhotoSize *size = [TGMediaPhotoSize fromDictionary:entry];
		if (size)
			[out addObject:size];
	}
	return [out copy];
}

@end


@interface TGMediaModel ()
@property (nonatomic, assign) TGMediaKind kind;
@property (nonatomic, copy) NSString *rawKind;
@property (nonatomic, assign) int64_t fileId;
@property (nonatomic, assign) int64_t fileSize;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, copy) NSString *localPath;
@property (nonatomic, assign) BOOL isDownloaded;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, assign) int64_t thumbnailFileId;
@property (nonatomic, assign) NSInteger thumbnailWidth;
@property (nonatomic, assign) NSInteger thumbnailHeight;
@property (nonatomic, copy) NSData *minithumbnail;
@property (nonatomic, copy) NSArray *photoSizes;
@property (nonatomic, copy) NSData *waveform;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *performer;
@property (nonatomic, copy) NSString *emoji;
@property (nonatomic, copy) NSString *stickerFormat;
@property (nonatomic, copy) NSString *caption;
@property (nonatomic, assign) BOOL hasSpoiler;
@property (nonatomic, assign) BOOL isSecret;
@property (nonatomic, assign) BOOL isViewed;
@end

@implementation TGMediaModel

- (void)applyThumbnail:(id)value {
	NSDictionary *thumbnail = TGMMDict(value);
	if (!thumbnail)
		return;

	NSString *format = TGMMString(TGMMDict(thumbnail[@"format"])[@"@type"]);
	if (![format isEqualToString:@"thumbnailFormatJpeg"] &&
		![format isEqualToString:@"thumbnailFormatPng"])
		return;

	NSDictionary *file = TGMMDict(thumbnail[@"file"]);
	int64_t fileId = TGMMLongLong(file[@"id"]);
	if (fileId == 0)
		return;

	self.thumbnailFileId = fileId;
	self.thumbnailWidth = TGMMInteger(thumbnail[@"width"]);
	self.thumbnailHeight = TGMMInteger(thumbnail[@"height"]);
}

- (void)applyMainFile:(NSDictionary *)file {
	self.fileId = TGMMLongLong(file[@"id"]);
	self.fileSize = TGMMFileSize(file);

	NSDictionary *local = TGMMDict(file[@"local"]);
	if (!local)
		return;
	self.isDownloaded = TGMMBool(local[@"is_downloading_completed"]);
	if (self.isDownloaded)
		self.localPath = TGMMString(local[@"path"]);
}

- (void)applyCommonMedia:(NSDictionary *)media {
	if (!media)
		return;
	if (self.width == 0)
		self.width = TGMMInteger(media[@"width"]);
	if (self.height == 0)
		self.height = TGMMInteger(media[@"height"]);
	if (self.duration == 0)
		self.duration = TGMMInteger(media[@"duration"]);
	if (!self.fileName)
		self.fileName = TGMMString(media[@"file_name"]);
	if (!self.mimeType)
		self.mimeType = TGMMString(media[@"mime_type"]);
	if (self.thumbnailFileId == 0)
		[self applyThumbnail:media[@"thumbnail"]];
	if (!self.minithumbnail)
		self.minithumbnail = TGMMBase64(TGMMDict(media[@"minithumbnail"])[@"data"]);
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	NSDictionary *content = TGMMDict(dict);
	if (!content)
		return nil;

	NSString *rawKind = TGMMString(content[@"@type"]);
	if (!rawKind)
		return nil;

	TGMediaModel *model = [[TGMediaModel alloc] init];
	model.rawKind = rawKind;
	model.photoSizes = [NSArray array];
	model.caption = TGMMString(TGMMDict(content[@"caption"])[@"text"]);
	model.hasSpoiler = TGMMBool(content[@"has_spoiler"]);
	model.isSecret = TGMMBool(content[@"is_secret"]);
	model.isViewed = TGMMBool(content[@"is_viewed"]) || TGMMBool(content[@"is_listened"]);

	NSDictionary *media = nil;
	NSDictionary *mainFile = nil;

	if ([rawKind isEqualToString:@"messagePhoto"]){
		media = TGMMDict(content[@"photo"]);
		NSArray *sizes = [TGMediaPhotoSize arrayFromDictionaries:media[@"sizes"]];
		if (!sizes.count)
			return nil;
		model.kind = TGMediaKindPhoto;
		model.photoSizes = sizes;

		TGMediaPhotoSize *largest = [sizes lastObject];
		model.fileId = largest.fileId;
		model.fileSize = largest.fileSize;
		model.width = largest.width;
		model.height = largest.height;

		TGMediaPhotoSize *smallest = [sizes objectAtIndex:0];
		if (smallest != largest){
			model.thumbnailFileId = smallest.fileId;
			model.thumbnailWidth = smallest.width;
			model.thumbnailHeight = smallest.height;
		}
		model.minithumbnail = TGMMBase64(TGMMDict(media[@"minithumbnail"])[@"data"]);
		return model.fileId ? model : nil;

	} else if ([rawKind isEqualToString:@"messageVideo"]){
		model.kind = TGMediaKindVideo;
		media = TGMMDict(content[@"video"]);
		mainFile = TGMMDict(media[@"video"]);

	} else if ([rawKind isEqualToString:@"messageAnimation"]){
		model.kind = TGMediaKindAnimation;
		media = TGMMDict(content[@"animation"]);
		mainFile = TGMMDict(media[@"animation"]);

	} else if ([rawKind isEqualToString:@"messageDocument"]){
		model.kind = TGMediaKindDocument;
		media = TGMMDict(content[@"document"]);
		mainFile = TGMMDict(media[@"document"]);

	} else if ([rawKind isEqualToString:@"messageAudio"]){
		model.kind = TGMediaKindAudio;
		media = TGMMDict(content[@"audio"]);
		mainFile = TGMMDict(media[@"audio"]);
		model.title = TGMMString(media[@"title"]);
		model.performer = TGMMString(media[@"performer"]);
		[model applyThumbnail:TGMMDict(media[@"album_cover_thumbnail"])];

	} else if ([rawKind isEqualToString:@"messageVoiceNote"]){
		model.kind = TGMediaKindVoiceNote;
		media = TGMMDict(content[@"voice_note"]);
		mainFile = TGMMDict(media[@"voice"]);
		model.waveform = TGMMBase64(media[@"waveform"]);

	} else if ([rawKind isEqualToString:@"messageVideoNote"]){
		model.kind = TGMediaKindVideoNote;
		media = TGMMDict(content[@"video_note"]);
		mainFile = TGMMDict(media[@"video"]);
		model.width = TGMMInteger(media[@"length"]);
		model.height = model.width;

	} else if ([rawKind isEqualToString:@"messageSticker"] ||
			   [rawKind isEqualToString:@"messageAnimatedEmoji"]){
		model.kind = TGMediaKindSticker;
		media = [rawKind isEqualToString:@"messageSticker"]
			? TGMMDict(content[@"sticker"])
			: TGMMDict(TGMMDict(content[@"animated_emoji"])[@"sticker"]);
		mainFile = TGMMDict(media[@"sticker"]);
		model.emoji = TGMMString(content[@"emoji"]) ?: TGMMString(media[@"emoji"]);

		NSString *format = TGMMString(TGMMDict(media[@"format"])[@"@type"]);
		if ([format hasPrefix:@"stickerFormat"])
			model.stickerFormat = [format substringFromIndex:13];

	} else {
		return nil;
	}

	if (!media || !mainFile)
		return nil;

	[model applyMainFile:mainFile];
	[model applyCommonMedia:media];

	return model.fileId ? model : nil;
}

+ (instancetype)fromMessageDictionary:(NSDictionary *)message {
	NSDictionary *source = TGMMDict(message);
	return source ? [self fromDictionary:TGMMDict(source[@"content"])] : nil;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	NSArray *source = TGMMArray(dicts);
	if (!source.count)
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:source.count];
	for (id entry in source){
		TGMediaModel *model = [TGMediaModel fromDictionary:entry];
		if (model)
			[out addObject:model];
	}
	return [out copy];
}

+ (NSArray *)arrayFromMessageDictionaries:(NSArray *)messages {
	NSArray *source = TGMMArray(messages);
	if (!source.count)
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:source.count];
	for (id entry in source){
		TGMediaModel *model = [TGMediaModel fromMessageDictionary:entry];
		if (model)
			[out addObject:model];
	}
	return [out copy];
}

- (BOOL)isVideo {
	return _kind == TGMediaKindVideo ||
		   _kind == TGMediaKindAnimation ||
		   _kind == TGMediaKindVideoNote;
}

- (BOOL)isAudio {
	return _kind == TGMediaKindAudio || _kind == TGMediaKindVoiceNote;
}

- (NSString *)description {
	return [NSString stringWithFormat:
			@"<TGMediaModel %@ file=%lld %ldx%ld %lds %lld bytes>",
			_rawKind, _fileId, (long)_width, (long)_height,
			(long)_duration, _fileSize];
}

@end

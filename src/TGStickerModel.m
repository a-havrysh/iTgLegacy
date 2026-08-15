#import "TGStickerModel.h"

static NSDictionary *TGSMDict(id value){
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSArray *TGSMArray(id value){
	return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static NSString *TGSMString(id value){
	if (![value isKindOfClass:[NSString class]])
		return nil;
	return [value length] ? [value copy] : nil;
}

static int64_t TGSMLongLong(id value){
	if ([value isKindOfClass:[NSNumber class]])
		return [value longLongValue];
	if ([value isKindOfClass:[NSString class]])
		return [value longLongValue];
	return 0;
}

static NSInteger TGSMInteger(id value){
	return (NSInteger)TGSMLongLong(value);
}

static CGFloat TGSMFloat(id value){
	return [value isKindOfClass:[NSNumber class]] ? (CGFloat)[value doubleValue] : 0.0f;
}

static BOOL TGSMBool(id value){
	if ([value isKindOfClass:[NSNumber class]])
		return [value boolValue];
	if ([value isKindOfClass:[NSString class]])
		return [value isEqualToString:@"true"] || [value isEqualToString:@"1"];
	return NO;
}

static NSString *TGSMTypeOf(id value){
	return TGSMString(TGSMDict(value)[@"@type"]);
}

static NSInteger TGSMNestedFileId(id container){
	NSDictionary *dict = TGSMDict(container);
	if (!dict)
		return 0;
	NSDictionary *file = TGSMDict(dict[@"file"]);
	if (file)
		return TGSMInteger(file[@"id"]);
	return TGSMInteger(dict[@"id"]);
}

@implementation TGStickerModel

@synthesize fileId = _fileId;
@synthesize setId = _setId;
@synthesize emoji = _emoji;
@synthesize width = _width;
@synthesize height = _height;
@synthesize animated = _animated;
@synthesize video = _video;
@synthesize thumbId = _thumbId;
@synthesize customEmojiId = _customEmojiId;

- (BOOL)customEmoji {
	return _customEmojiId != 0;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;

	NSInteger fileId = TGSMInteger(dict[@"fileId"]);
	if (fileId == 0)
		fileId = TGSMNestedFileId(dict[@"sticker"]);
	if (fileId == 0)
		return nil;

	TGStickerModel *model = [[self alloc] init];
	if (!model)
		return nil;

	model->_fileId = fileId;
	model->_setId = TGSMLongLong(dict[@"setId"] ?: dict[@"set_id"]);
	model->_emoji = TGSMString(dict[@"emoji"]);
	model->_width = TGSMFloat(dict[@"width"]);
	model->_height = TGSMFloat(dict[@"height"]);

	NSInteger thumbId = TGSMInteger(dict[@"thumbId"]);
	if (thumbId == 0)
		thumbId = TGSMNestedFileId(dict[@"thumbnail"]);
	model->_thumbId = thumbId;

	NSString *format = TGSMTypeOf(dict[@"format"]);
	if (format){
		model->_animated = ![format isEqualToString:@"stickerFormatWebp"];
		model->_video = [format isEqualToString:@"stickerFormatWebm"];
	} else {
		model->_animated = TGSMBool(dict[@"isAnimated"]);
		model->_video = TGSMBool(dict[@"isVideo"]);
	}

	int64_t customEmojiId = TGSMLongLong(dict[@"customEmojiId"]);
	if (customEmojiId == 0){
		NSDictionary *fullType = TGSMDict(dict[@"full_type"]);
		NSString *fullTypeName = TGSMString(fullType[@"@type"]);
		if (fullTypeName && [fullTypeName isEqualToString:@"stickerFullTypeCustomEmoji"])
			customEmojiId = TGSMLongLong(fullType[@"custom_emoji_id"]);
	}
	model->_customEmojiId = customEmojiId;

	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	NSArray *source = TGSMArray(dicts);
	if (!source)
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:source.count];
	for (id item in source){
		TGStickerModel *model = [self fromDictionary:item];
		if (model)
			[out addObject:model];
	}
	return out;
}

@end


@implementation TGStickerSetModel

@synthesize setId = _setId;
@synthesize title = _title;
@synthesize name = _name;
@synthesize count = _count;
@synthesize installed = _installed;
@synthesize archived = _archived;
@synthesize official = _official;
@synthesize viewed = _viewed;
@synthesize emojiSet = _emojiSet;
@synthesize thumbId = _thumbId;
@synthesize covers = _covers;
@synthesize stickers = _stickers;

- (TGStickerModel *)firstCover {
	return _covers.count ? [_covers objectAtIndex:0] : nil;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;

	int64_t setId = TGSMLongLong(dict[@"id"]);
	if (setId == 0)
		setId = TGSMLongLong(dict[@"set_id"]);
	if (setId == 0)
		return nil;

	TGStickerSetModel *model = [[self alloc] init];
	if (!model)
		return nil;

	model->_setId = setId;
	model->_title = TGSMString(dict[@"title"]);
	model->_name = TGSMString(dict[@"name"]);

	NSArray *stickers = [TGStickerModel arrayFromDictionaries:dict[@"stickers"]];
	NSArray *covers = [TGStickerModel arrayFromDictionaries:dict[@"covers"]];
	model->_stickers = stickers;
	model->_covers = covers.count ? covers : stickers;

	id count = dict[@"count"] ?: dict[@"size"];
	model->_count = [count isKindOfClass:[NSNumber class]]
		? TGSMInteger(count) : (NSInteger)stickers.count;

	model->_installed = TGSMBool(dict[@"installed"] ?: dict[@"is_installed"]);
	model->_archived = TGSMBool(dict[@"archived"] ?: dict[@"is_archived"]);
	model->_official = TGSMBool(dict[@"official"] ?: dict[@"is_official"]);
	model->_viewed = TGSMBool(dict[@"viewed"] ?: dict[@"is_viewed"]);

	NSString *type = TGSMTypeOf(dict[@"sticker_type"]);
	model->_emojiSet = type ? [type isEqualToString:@"stickerTypeCustomEmoji"]
							: TGSMBool(dict[@"isEmoji"]);

	NSInteger thumbId = TGSMInteger(dict[@"thumbId"]);
	if (thumbId == 0)
		thumbId = TGSMNestedFileId(dict[@"thumbnail"]);
	model->_thumbId = thumbId;

	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	NSArray *source = TGSMArray(dicts);
	if (!source)
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:source.count];
	for (id item in source){
		TGStickerSetModel *model = [self fromDictionary:item];
		if (model)
			[out addObject:model];
	}
	return out;
}

@end

// vim:ft=objc

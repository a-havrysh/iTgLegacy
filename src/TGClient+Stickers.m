#import "TGClient+Private.h"
#import "TGClient+Stickers.h"

static BOOL TGIsError(NSDictionary *result){
	return ![result isKindOfClass:[NSDictionary class]]
		|| [result[@"@type"] isEqualToString:@"error"];
}

static NSArray *TGArray(id value){
	return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static NSDictionary *TGDict(id value){
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSString *TGString(id value){
	return [value isKindOfClass:[NSString class]] ? value : nil;
}

static long long TGInt64(id value){
	if ([value isKindOfClass:[NSNumber class]])
		return [value longLongValue];
	if ([value isKindOfClass:[NSString class]])
		return [value longLongValue];
	return 0;
}

static NSNumber *TGNumber(id value){
	if ([value isKindOfClass:[NSNumber class]])
		return value;
	if ([value isKindOfClass:[NSString class]])
		return [NSNumber numberWithLongLong:[value longLongValue]];
	return @0;
}

static NSNumber *TGDouble(id value){
	return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

static NSDictionary *TGFlattenSticker(id object){
	NSDictionary *sticker = TGDict(object);
	NSNumber *fileId = TGDict(sticker[@"sticker"])[@"id"];
	if (![fileId isKindOfClass:[NSNumber class]])
		return nil;

	NSString *format = TGString(TGDict(sticker[@"format"])[@"@type"]) ?: @"";
	NSDictionary *fullType = TGDict(sticker[@"full_type"]);
	NSNumber *customEmojiId = @0;
	if ([TGString(fullType[@"@type"]) isEqualToString:@"stickerFullTypeCustomEmoji"])
		customEmojiId = TGNumber(fullType[@"custom_emoji_id"]);

	NSNumber *thumbId = TGDict(TGDict(sticker[@"thumbnail"])[@"file"])[@"id"];
	if (![thumbId isKindOfClass:[NSNumber class]])
		thumbId = @0;

	return @{
		@"fileId"        : fileId,
		@"setId"         : TGNumber(sticker[@"set_id"]),
		@"emoji"         : TGString(sticker[@"emoji"]) ?: @"",
		@"width"         : TGDouble(sticker[@"width"]),
		@"height"        : TGDouble(sticker[@"height"]),
		@"isAnimated"    : @(![format isEqualToString:@"stickerFormatWebp"]),
		@"isVideo"       : @([format isEqualToString:@"stickerFormatWebm"]),
		@"thumbId"       : thumbId,
		@"customEmojiId" : customEmojiId,
	};
}

static NSArray *TGFlattenStickers(id list){
	NSMutableArray *out = [NSMutableArray array];
	for (id item in TGArray(list)){
		NSDictionary *sticker = TGFlattenSticker(item);
		if (sticker)
			[out addObject:sticker];
	}
	return out;
}

static NSDictionary *TGFlattenStickerSet(id object){
	NSDictionary *set = TGDict(object);
	if (!set[@"id"])
		return nil;

	NSNumber *thumbId = TGDict(TGDict(set[@"thumbnail"])[@"file"])[@"id"];
	if (![thumbId isKindOfClass:[NSNumber class]])
		thumbId = @0;

	NSArray *stickers = TGFlattenStickers(set[@"stickers"]);
	NSArray *covers   = TGFlattenStickers(set[@"covers"]);
	NSNumber *count   = [set[@"size"] isKindOfClass:[NSNumber class]]
		? set[@"size"] : @(stickers.count);
	NSString *type = TGString(TGDict(set[@"sticker_type"])[@"@type"]) ?: @"";

	return @{
		@"id"        : TGNumber(set[@"id"]),
		@"title"     : TGString(set[@"title"]) ?: @"",
		@"name"      : TGString(set[@"name"]) ?: @"",
		@"count"     : count,
		@"installed" : @([set[@"is_installed"] boolValue]),
		@"archived"  : @([set[@"is_archived"] boolValue]),
		@"official"  : @([set[@"is_official"] boolValue]),
		@"viewed"    : @([set[@"is_viewed"] boolValue]),
		@"isEmoji"   : @([type isEqualToString:@"stickerTypeCustomEmoji"]),
		@"thumbId"   : thumbId,
		@"covers"    : covers.count ? covers : stickers,
		@"stickers"  : stickers,
	};
}

static NSArray *TGFlattenStickerSets(id list){
	NSMutableArray *out = [NSMutableArray array];
	for (id item in TGArray(list)){
		NSDictionary *set = TGFlattenStickerSet(item);
		if (set)
			[out addObject:set];
	}
	return out;
}

static NSDictionary *TGStickerTypeRegular(void){
	return @{@"@type" : @"stickerTypeRegular"};
}

static NSDictionary *TGStickerTypeCustomEmoji(void){
	return @{@"@type" : @"stickerTypeCustomEmoji"};
}

static NSDictionary *TGInputFileWithId(NSInteger fileId){
	return @{@"@type" : @"inputFileId", @"id" : @(fileId)};
}

@implementation TGClient (Stickers)

- (void)stickerSetsOfType:(NSDictionary *)type
               completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getInstalledStickerSets", @"sticker_type" : type}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(nil);
			return;
		}
		completion(TGFlattenStickerSets(result[@"sets"]));
	}];
}

- (void)installedStickerSetsWithCompletion:(void (^)(NSArray *))completion {
	[self stickerSetsOfType:TGStickerTypeRegular() completion:completion];
}

- (void)installedEmojiStickerSetsWithCompletion:(void (^)(NSArray *))completion {
	[self stickerSetsOfType:TGStickerTypeCustomEmoji() completion:completion];
}

- (void)archivedStickerSetsFromSetId:(int64_t)offsetSetId
                               limit:(NSInteger)limit
                          completion:(void (^)(NSArray *, NSInteger))completion {
	if (limit <= 0)
		limit = 100;

	[self request:@{
		@"@type"                 : @"getArchivedStickerSets",
		@"sticker_type"          : TGStickerTypeRegular(),
		@"offset_sticker_set_id" : [NSString stringWithFormat:@"%lld", offsetSetId],
		@"limit"                 : @(limit),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(nil, 0);
			return;
		}
		NSArray *sets = TGFlattenStickerSets(result[@"sets"]);
		completion(sets, (NSInteger)[result[@"total_count"] integerValue]);
	}];
}

- (void)trendingStickerSetsWithOffset:(NSInteger)offset
                                limit:(NSInteger)limit
                           completion:(void (^)(NSArray *, NSInteger))completion {
	if (limit <= 0)
		limit = 20;

	[self request:@{
		@"@type"        : @"getTrendingStickerSets",
		@"sticker_type" : TGStickerTypeRegular(),
		@"offset"       : @(offset),
		@"limit"        : @(limit),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(nil, 0);
			return;
		}
		NSArray *sets = TGFlattenStickerSets(result[@"sets"]);
		completion(sets, (NSInteger)[result[@"total_count"] integerValue]);
	}];
}

- (void)markTrendingStickerSetsViewed:(NSArray *)setIds {
	NSMutableArray *ids = [NSMutableArray array];
	for (id item in TGArray(setIds))
		[ids addObject:[NSString stringWithFormat:@"%lld", TGInt64(item)]];
	if (!ids.count)
		return;

	[self send:@{@"@type" : @"viewTrendingStickerSets", @"sticker_set_ids" : ids}];
}

- (void)stickerSetWithId:(int64_t)setId completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"  : @"getStickerSet",
		@"set_id" : [NSString stringWithFormat:@"%lld", setId],
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? nil : TGFlattenStickerSet(result));
	}];
}

- (void)stickerSetWithName:(NSString *)name completion:(void (^)(NSDictionary *))completion {
	if (!name.length){
		if (completion)
			completion(nil);
		return;
	}

	[self request:@{
		@"@type"        : @"searchStickerSet",
		@"name"         : name,
		@"ignore_cache" : @NO,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? nil : TGFlattenStickerSet(result));
	}];
}

- (void)changeStickerSet:(int64_t)setId
               installed:(BOOL)installed
                archived:(BOOL)archived
              completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"        : @"changeStickerSet",
		@"set_id"       : [NSString stringWithFormat:@"%lld", setId],
		@"is_installed" : @(installed),
		@"is_archived"  : @(archived),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGIsError(result));
	}];
}

- (void)installStickerSet:(int64_t)setId completion:(void (^)(BOOL))completion {
	[self changeStickerSet:setId installed:YES archived:NO completion:completion];
}

- (void)uninstallStickerSet:(int64_t)setId completion:(void (^)(BOOL))completion {
	[self changeStickerSet:setId installed:NO archived:NO completion:completion];
}

- (void)archiveStickerSet:(int64_t)setId completion:(void (^)(BOOL))completion {
	[self changeStickerSet:setId installed:NO archived:YES completion:completion];
}

- (void)reorderInstalledStickerSets:(NSArray *)setIds {
	NSMutableArray *ids = [NSMutableArray array];
	for (id item in TGArray(setIds))
		[ids addObject:[NSString stringWithFormat:@"%lld", TGInt64(item)]];
	if (!ids.count)
		return;

	[self send:@{
		@"@type"           : @"reorderInstalledStickerSets",
		@"sticker_type"    : TGStickerTypeRegular(),
		@"sticker_set_ids" : ids,
	}];
}

- (void)searchInstalledStickerSets:(NSString *)query
                             limit:(NSInteger)limit
                        completion:(void (^)(NSArray *))completion {
	if (limit <= 0)
		limit = 50;

	[self request:@{
		@"@type"        : @"searchInstalledStickerSets",
		@"sticker_type" : TGStickerTypeRegular(),
		@"query"        : query ?: @"",
		@"limit"        : @(limit),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? nil : TGFlattenStickerSets(result[@"sets"]));
	}];
}

- (void)searchStickerSets:(NSString *)query completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"        : @"searchStickerSets",
		@"sticker_type" : TGStickerTypeRegular(),
		@"query"        : query ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? nil : TGFlattenStickerSets(result[@"sets"]));
	}];
}

- (void)favoriteStickersWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getFavoriteStickers"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? nil : TGFlattenStickers(result[@"stickers"]));
	}];
}

- (void)addFavoriteStickerWithFileId:(NSInteger)fileId {
	[self send:@{@"@type" : @"addFavoriteSticker",
				 @"sticker" : TGInputFileWithId(fileId)}];
}

- (void)removeFavoriteStickerWithFileId:(NSInteger)fileId {
	[self send:@{@"@type" : @"removeFavoriteSticker",
				 @"sticker" : TGInputFileWithId(fileId)}];
}

- (void)addRecentStickerWithFileId:(NSInteger)fileId {
	[self send:@{@"@type"       : @"addRecentSticker",
				 @"is_attached" : @NO,
				 @"sticker"     : TGInputFileWithId(fileId)}];
}

- (void)removeRecentStickerWithFileId:(NSInteger)fileId {
	[self send:@{@"@type"       : @"removeRecentSticker",
				 @"is_attached" : @NO,
				 @"sticker"     : TGInputFileWithId(fileId)}];
}

- (void)clearRecentStickers {
	[self send:@{@"@type" : @"clearRecentStickers", @"is_attached" : @NO}];
}

- (void)searchStickersByEmoji:(NSString *)emoji
                        query:(NSString *)query
                        limit:(NSInteger)limit
                   completion:(void (^)(NSArray *))completion {
	if (limit <= 0)
		limit = 50;

	[self request:@{
		@"@type"                : @"searchStickers",
		@"sticker_type"         : TGStickerTypeRegular(),
		@"emojis"               : emoji ?: @"",
		@"query"                : query ?: @"",
		@"input_language_codes" : @[],
		@"offset"               : @0,
		@"limit"                : @(limit),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? nil : TGFlattenStickers(result[@"stickers"]));
	}];
}

- (void)installedStickersMatching:(NSString *)query
                            limit:(NSInteger)limit
                       completion:(void (^)(NSArray *))completion {
	if (limit <= 0)
		limit = 50;

	[self request:@{
		@"@type"        : @"getStickers",
		@"sticker_type" : TGStickerTypeRegular(),
		@"query"        : query ?: @"",
		@"limit"        : @(limit),
		@"chat_id"      : @0,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? nil : TGFlattenStickers(result[@"stickers"]));
	}];
}

- (void)stickerSuggestionEnabledWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"getOption", @"name" : @"is_sticker_suggestion_enabled"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(YES);
			return;
		}
		id value = result[@"value"];
		completion(value ? [value boolValue] : YES);
	}];
}

- (void)allStickerEmojisForQuery:(NSString *)query
                      completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"                  : @"getAllStickerEmojis",
		@"sticker_type"           : TGStickerTypeRegular(),
		@"query"                  : query ?: @"",
		@"chat_id"                : @0,
		@"return_only_main_emoji" : @YES,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(nil);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id emoji in TGArray(result[@"emojis"]))
			if ([emoji isKindOfClass:[NSString class]])
				[out addObject:emoji];
		completion(out);
	}];
}

- (void)emojiSuggestionsForText:(NSString *)text
                     completion:(void (^)(NSArray *))completion {
	if (!text.length){
		if (completion)
			completion(@[]);
		return;
	}

	[self request:@{
		@"@type"                : @"searchEmojis",
		@"text"                 : text,
		@"input_language_codes" : @[],
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(nil);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id item in TGArray(result[@"emoji_keywords"])){
			NSDictionary *entry = TGDict(item);
			NSString *emoji = TGString(entry[@"emoji"]);
			if (!emoji.length)
				continue;
			[out addObject:@{@"emoji"   : emoji,
							 @"keyword" : TGString(entry[@"keyword"]) ?: @""}];
		}
		completion(out);
	}];
}

- (void)keywordEmojisForText:(NSString *)text
                  completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"                : @"getKeywordEmojis",
		@"text"                 : text ?: @"",
		@"input_language_codes" : @[],
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(nil);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id emoji in TGArray(result[@"emojis"]))
			if ([emoji isKindOfClass:[NSString class]])
				[out addObject:emoji];
		completion(out);
	}];
}

- (void)emojiCategoriesForStickers:(BOOL)forStickers
                        completion:(void (^)(NSArray *))completion {
	NSString *type = forStickers ? @"emojiCategoryTypeRegularStickers"
								 : @"emojiCategoryTypeDefault";

	[self request:@{@"@type" : @"getEmojiCategories", @"type" : @{@"@type" : type}}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(nil);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id item in TGArray(result[@"categories"])){
			NSDictionary *category = TGDict(item);
			if (!category)
				continue;
			NSMutableArray *emojis = [NSMutableArray array];
			NSDictionary *source = TGDict(category[@"source"]);
			for (id emoji in TGArray(source[@"emojis"]))
				if ([emoji isKindOfClass:[NSString class]])
					[emojis addObject:emoji];
			NSMutableDictionary *entry = [NSMutableDictionary dictionary];
			[entry setObject:(TGString(category[@"name"]) ?: @"") forKey:@"name"];
			[entry setObject:@([category[@"is_greeting"] boolValue]) forKey:@"isGreeting"];
			[entry setObject:emojis forKey:@"emojis"];
			NSDictionary *icon = TGFlattenSticker(category[@"icon"]);
			if (icon)
				[entry setObject:icon forKey:@"icon"];
			[out addObject:entry];
		}
		completion(out);
	}];
}

- (void)greetingStickersWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getGreetingStickers"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? nil : TGFlattenStickers(result[@"stickers"]));
	}];
}

- (void)customEmojiStickersWithIds:(NSArray *)customEmojiIds
                        completion:(void (^)(NSArray *))completion {
	NSMutableArray *ids = [NSMutableArray array];
	for (id item in TGArray(customEmojiIds))
		[ids addObject:[NSString stringWithFormat:@"%lld", TGInt64(item)]];

	if (!ids.count){
		if (completion)
			completion(@[]);
		return;
	}

	[self request:@{@"@type" : @"getCustomEmojiStickers", @"custom_emoji_ids" : ids}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? nil : TGFlattenStickers(result[@"stickers"]));
	}];
}

- (void)attachedStickerSetsForFileId:(NSInteger)fileId
                          completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getAttachedStickerSets", @"file_id" : @(fileId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? nil : TGFlattenStickerSets(result[@"sets"]));
	}];
}

- (void)setStickerSet:(int64_t)setId
       forSupergroup:(int64_t)supergroupId
          completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"          : @"setSupergroupStickerSet",
		@"supergroup_id"  : @(supergroupId),
		@"sticker_set_id" : [NSString stringWithFormat:@"%lld", setId],
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGIsError(result));
	}];
}

- (void)setCustomEmojiStickerSet:(int64_t)setId
                   forSupergroup:(int64_t)supergroupId
                      completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"                       : @"setSupergroupCustomEmojiStickerSet",
		@"supergroup_id"               : @(supergroupId),
		@"custom_emoji_sticker_set_id" : [NSString stringWithFormat:@"%lld", setId],
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGIsError(result));
	}];
}

- (void)stickerOutlineForFileId:(NSInteger)fileId
                     completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"                              : @"getStickerOutline",
		@"sticker_file_id"                    : @(fileId),
		@"for_animated_emoji"                 : @NO,
		@"for_clicked_animated_emoji_message" : @NO,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(nil);
			return;
		}
		NSMutableArray *paths = [NSMutableArray array];
		for (id item in TGArray(result[@"paths"])){
			NSDictionary *path = TGDict(item);
			NSMutableArray *commands = [NSMutableArray array];
			for (id rawCommand in TGArray(path[@"commands"])){
				NSDictionary *command = TGDict(rawCommand);
				NSDictionary *end = TGDict(command[@"end_point"]);
				if (!end)
					continue;
				NSString *type = TGString(command[@"@type"]) ?: @"";
				if ([type isEqualToString:@"vectorPathCommandCubicBezierCurve"]){
					NSDictionary *c1 = TGDict(command[@"start_control_point"]);
					NSDictionary *c2 = TGDict(command[@"end_control_point"]);
					[commands addObject:@{
						@"type" : @"curve",
						@"x"    : TGDouble(end[@"x"]),
						@"y"    : TGDouble(end[@"y"]),
						@"c1x"  : TGDouble(c1[@"x"]),
						@"c1y"  : TGDouble(c1[@"y"]),
						@"c2x"  : TGDouble(c2[@"x"]),
						@"c2y"  : TGDouble(c2[@"y"]),
					}];
				} else {
					[commands addObject:@{
						@"type" : @"line",
						@"x"    : TGDouble(end[@"x"]),
						@"y"    : TGDouble(end[@"y"]),
					}];
				}
			}
			if (commands.count)
				[paths addObject:commands];
		}
		completion(paths);
	}];
}

@end

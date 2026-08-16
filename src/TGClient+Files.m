#import "TGClient+Private.h"
#import "TGClient+Files.h"

NSString *const TGFileTypePhoto     = @"fileTypePhoto";
NSString *const TGFileTypeVideo     = @"fileTypeVideo";
NSString *const TGFileTypeDocument  = @"fileTypeDocument";
NSString *const TGFileTypeSticker   = @"fileTypeSticker";
NSString *const TGFileTypeAudio     = @"fileTypeAudio";
NSString *const TGFileTypeVoiceNote = @"fileTypeVoiceNote";
NSString *const TGFileTypeAnimation = @"fileTypeAnimation";
NSString *const TGFileTypeThumbnail = @"fileTypeThumbnail";

NSString *const TGNetworkTypeWiFi          = @"networkTypeWiFi";
NSString *const TGNetworkTypeMobile        = @"networkTypeMobile";
NSString *const TGNetworkTypeMobileRoaming = @"networkTypeMobileRoaming";
NSString *const TGNetworkTypeOther         = @"networkTypeOther";
NSString *const TGNetworkTypeNone          = @"networkTypeNone";

static BOOL TGFilesIsError(NSDictionary *result) {
	if (![result isKindOfClass:NSDictionary.class])
		return YES;
	id type = result[@"@type"];
	return [type isKindOfClass:NSString.class] && [type isEqualToString:@"error"];
}

static NSArray *TGFilesArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSDictionary *TGFilesDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSString *TGFilesString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

/// TDLib sends `bytes` fields as base64 text. iOS 6 has neither
/// initWithBase64EncodedString:options: nor a public decoder that is safe to
/// rely on here, so this decodes by hand.
static NSData *TGFilesDataFromBase64(id value) {
	NSString *text = [value isKindOfClass:NSString.class] ? value : nil;
	if (!text.length)
		return nil;

	// Minithumbnails are decoded off the main thread now, and from more than
	// one queue. Filling this table under a plain flag let a second thread
	// read it half-built and turn a picture into nothing.
	static signed char table[256];
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		static const char *alphabet =
				"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		for (int i = 0; i < 256; i++)
			table[i] = -1;
		for (int i = 0; i < 64; i++)
			table[(unsigned char)alphabet[i]] = (signed char)i;
		table[(unsigned char)'-'] = 62;
		table[(unsigned char)'_'] = 63;
	});

	NSMutableData *out = nil;
	@autoreleasepool {
		NSData *ascii = [text dataUsingEncoding:NSASCIIStringEncoding];
		const unsigned char *src = ascii.bytes;
		NSUInteger length = ascii.length;
		out = [[NSMutableData alloc] initWithCapacity:(length / 4) * 3 + 3];

		unsigned char chunk[3072];
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
	}
	return out.length ? out : nil;
}

/// Flattened File object. Nil in, empty-ish dictionary out is never useful, so
/// this returns nil for anything that is not a file.
static NSDictionary *TGFileInfo(NSDictionary *file) {
	if (![file isKindOfClass:NSDictionary.class] || !file[@"id"])
		return nil;
	NSDictionary *local = TGFilesDict(file[@"local"]) ?: @{};
	NSDictionary *remote = TGFilesDict(file[@"remote"]) ?: @{};
	return @{
		@"id"              : file[@"id"] ?: @0,
		@"size"            : file[@"size"] ?: @0,
		@"expectedSize"    : file[@"expected_size"] ?: file[@"size"] ?: @0,
		@"path"            : TGFilesString(local[@"path"]),
		@"downloadedSize"  : local[@"downloaded_size"] ?: @0,
		@"prefixSize"      : local[@"downloaded_prefix_size"] ?: @0,
		@"downloadOffset"  : local[@"download_offset"] ?: @0,
		@"canBeDownloaded" : local[@"can_be_downloaded"] ?: @NO,
		@"canBeDeleted"    : local[@"can_be_deleted"] ?: @NO,
		@"isDownloading"   : local[@"is_downloading_active"] ?: @NO,
		@"isDownloaded"    : local[@"is_downloading_completed"] ?: @NO,
		@"isUploading"     : remote[@"is_uploading_active"] ?: @NO,
		@"isUploaded"      : remote[@"is_uploading_completed"] ?: @NO,
		@"uploadedSize"    : remote[@"uploaded_size"] ?: @0,
		@"remoteId"        : TGFilesString(remote[@"id"]),
		@"uniqueId"        : TGFilesString(remote[@"unique_id"]),
	};
}

/// The file id carried by whichever media a message holds, plus its name.
static NSDictionary *TGFileOfMessageContent(NSDictionary *content) {
	if (![content isKindOfClass:NSDictionary.class])
		return nil;
	NSString *type = content[@"@type"];
	NSDictionary *file = nil;
	NSString *name = @"";
	if ([type isEqualToString:@"messageDocument"]){
		NSDictionary *doc = TGFilesDict(content[@"document"]);
		file = TGFilesDict(doc[@"document"]);
		name = TGFilesString(doc[@"file_name"]);
	} else if ([type isEqualToString:@"messageVideo"]){
		NSDictionary *video = TGFilesDict(content[@"video"]);
		file = TGFilesDict(video[@"video"]);
		name = TGFilesString(video[@"file_name"]);
	} else if ([type isEqualToString:@"messageAudio"]){
		NSDictionary *audio = TGFilesDict(content[@"audio"]);
		file = TGFilesDict(audio[@"audio"]);
		name = TGFilesString(audio[@"file_name"]);
	} else if ([type isEqualToString:@"messageAnimation"]){
		NSDictionary *animation = TGFilesDict(content[@"animation"]);
		file = TGFilesDict(animation[@"animation"]);
		name = TGFilesString(animation[@"file_name"]);
	} else if ([type isEqualToString:@"messageVoiceNote"]){
		file = TGFilesDict(TGFilesDict(content[@"voice_note"])[@"voice"]);
	} else if ([type isEqualToString:@"messageVideoNote"]){
		file = TGFilesDict(TGFilesDict(content[@"video_note"])[@"video"]);
	} else if ([type isEqualToString:@"messagePhoto"]){
		NSArray *sizes = TGFilesArray(TGFilesDict(content[@"photo"])[@"sizes"]);
		file = TGFilesDict([sizes lastObject][@"photo"]);
	}
	if (!file)
		return nil;
	return @{@"file" : file, @"name" : name};
}

@implementation TGClient (Files)

#pragma mark - file state

- (void)fileInfo:(NSInteger)fileId completion:(void (^)(NSDictionary *))completion {
	if (fileId <= 0){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getFile", @"file_id" : @(fileId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGFilesIsError(result) ? nil : TGFileInfo(result));
	}];
}

- (void)resolveRemoteFileId:(NSString *)remoteId
					   type:(NSString *)type
				 completion:(void (^)(NSDictionary *))completion {
	if (!remoteId.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type"          : @"getRemoteFile",
		@"remote_file_id" : remoteId,
		@"file_type"      : @{@"@type" : type.length ? type : TGFileTypeDocument},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGFilesIsError(result) ? nil : TGFileInfo(result));
	}];
}

#pragma mark - downloading

- (void)startDownloadingFile:(NSInteger)fileId
					priority:(NSInteger)priority
				  completion:(void (^)(NSDictionary *))completion {
	if (fileId <= 0){
		if (completion) completion(nil);
		return;
	}
	if (priority < 1) priority = 1;
	if (priority > 32) priority = 32;
	[self request:@{
		@"@type"       : @"downloadFile",
		@"file_id"     : @(fileId),
		@"priority"    : @(priority),
		@"offset"      : @(0),
		@"limit"       : @(0),
		@"synchronous" : @NO,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGFilesIsError(result) ? nil : TGFileInfo(result));
	}];
}

- (void)cancelDownloadOfFile:(NSInteger)fileId onlyIfPending:(BOOL)onlyIfPending {
	if (fileId <= 0)
		return;
	[self send:@{
		@"@type"           : @"cancelDownloadFile",
		@"file_id"         : @(fileId),
		@"only_if_pending" : @(onlyIfPending),
	}];
}

- (void)setDownloadOfFile:(NSInteger)fileId paused:(BOOL)paused {
	if (fileId <= 0)
		return;
	[self send:@{
		@"@type"     : @"toggleDownloadIsPaused",
		@"file_id"   : @(fileId),
		@"is_paused" : @(paused),
	}];
}

- (void)deleteCachedFile:(NSInteger)fileId completion:(void (^)(BOOL))completion {
	if (fileId <= 0){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"deleteFile", @"file_id" : @(fileId)}
	   completion:^(NSDictionary *result){
		if (completion) completion(!TGFilesIsError(result));
	}];
}

- (void)suggestedFileNameForFile:(NSInteger)fileId
					  completion:(void (^)(NSString *))completion {
	if (fileId <= 0){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type"     : @"getSuggestedFileName",
		@"file_id"   : @(fileId),
		@"directory" : @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGFilesIsError(result)){
			completion(nil);
			return;
		}
		NSString *text = TGFilesString(result[@"text"]);
		completion(text.length ? text : nil);
	}];
}

#pragma mark - downloads list

- (void)addFileToDownloads:(NSInteger)fileId
					inChat:(int64_t)chatId
				 messageId:(int64_t)messageId
				  priority:(NSInteger)priority
				completion:(void (^)(NSDictionary *))completion {
	if (fileId <= 0 || messageId == 0){
		if (completion) completion(nil);
		return;
	}
	if (priority < 1) priority = 1;
	if (priority > 32) priority = 32;
	[self request:@{
		@"@type"      : @"addFileToDownloads",
		@"file_id"    : @(fileId),
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"priority"   : @(priority),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGFilesIsError(result) ? nil : TGFileInfo(result));
	}];
}

- (void)searchDownloadsWithQuery:(NSString *)query
					  onlyActive:(BOOL)onlyActive
				   onlyCompleted:(BOOL)onlyCompleted
						  offset:(NSString *)offset
						   limit:(NSInteger)limit
					  completion:(void (^)(NSDictionary *))completion {
	if (limit <= 0)
		limit = 30;
	[self request:@{
		@"@type"          : @"searchFileDownloads",
		@"query"          : query ?: @"",
		@"only_active"    : @(onlyActive),
		@"only_completed" : @(onlyCompleted),
		@"offset"         : offset ?: @"",
		@"limit"          : @(limit),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGFilesIsError(result)){
			completion(nil);
			return;
		}

		NSMutableArray *downloads = [NSMutableArray array];
		for (NSDictionary *entry in TGFilesArray(result[@"files"])){
			if (![entry isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *message = TGFilesDict(entry[@"message"]) ?: @{};
			NSDictionary *media = TGFileOfMessageContent(TGFilesDict(message[@"content"]));
			NSDictionary *file = TGFileInfo(media[@"file"]);
			[downloads addObject:@{
				@"fileId"       : entry[@"file_id"] ?: @0,
				@"chatId"       : message[@"chat_id"] ?: @0,
				@"messageId"    : message[@"id"] ?: @0,
				@"addDate"      : entry[@"add_date"] ?: @0,
				@"completeDate" : entry[@"complete_date"] ?: @0,
				@"isPaused"     : entry[@"is_paused"] ?: @NO,
				@"fileName"     : TGFilesString(media[@"name"]),
				@"file"         : file ?: @{},
			}];
		}

		NSDictionary *counts = TGFilesDict(result[@"total_counts"]) ?: @{};
		completion(@{
			@"downloads"      : downloads,
			@"nextOffset"     : TGFilesString(result[@"next_offset"]),
			@"activeCount"    : counts[@"active_count"] ?: @0,
			@"pausedCount"    : counts[@"paused_count"] ?: @0,
			@"completedCount" : counts[@"completed_count"] ?: @0,
		});
	}];
}

- (void)removeAllDownloadsOnlyActive:(BOOL)onlyActive
					   onlyCompleted:(BOOL)onlyCompleted
					 deleteFromCache:(BOOL)deleteFromCache {
	[self send:@{
		@"@type"             : @"removeAllFilesFromDownloads",
		@"only_active"       : @(onlyActive),
		@"only_completed"    : @(onlyCompleted),
		@"delete_from_cache" : @(deleteFromCache),
	}];
}

#pragma mark - streaming and partial reads

- (void)downloadedPrefixSizeForFile:(NSInteger)fileId
							 offset:(long long)offset
						 completion:(void (^)(long long))completion {
	if (fileId <= 0){
		if (completion) completion(0);
		return;
	}
	[self request:@{
		@"@type"   : @"getFileDownloadedPrefixSize",
		@"file_id" : @(fileId),
		@"offset"  : @(offset),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGFilesIsError(result) ? 0 : [result[@"size"] longLongValue]);
	}];
}

- (void)downloadFile:(NSInteger)fileId
			  offset:(long long)offset
			   limit:(long long)limit
		  completion:(void (^)(NSDictionary *))completion {
	if (fileId <= 0){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type"       : @"downloadFile",
		@"file_id"     : @(fileId),
		@"priority"    : @(32),
		@"offset"      : @(offset < 0 ? 0 : offset),
		@"limit"       : @(limit < 0 ? 0 : limit),
		@"synchronous" : @YES,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGFilesIsError(result) ? nil : TGFileInfo(result));
	}];
}

- (void)readFile:(NSInteger)fileId
		  offset:(long long)offset
		   count:(long long)count
	  completion:(void (^)(NSData *))completion {
	if (fileId <= 0 || count <= 0){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type"   : @"readFilePart",
		@"file_id" : @(fileId),
		@"offset"  : @(offset < 0 ? 0 : offset),
		@"count"   : @(count),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGFilesIsError(result) ? nil : TGFilesDataFromBase64(result[@"data"]));
	}];
}

- (void)streamFile:(NSInteger)fileId
			offset:(long long)offset
			 count:(long long)count
		completion:(void (^)(NSData *))completion {
	if (fileId <= 0 || count <= 0){
		if (completion) completion(nil);
		return;
	}
	if (offset < 0)
		offset = 0;

	__weak typeof(self) weakSelf = self;
	[self downloadedPrefixSizeForFile:fileId offset:offset
						   completion:^(long long ready){
		TGClient *me = weakSelf;
		if (!me){
			if (completion) completion(nil);
			return;
		}
		if (ready >= count){
			[me readFile:fileId offset:offset count:count completion:completion];
			return;
		}
		[me downloadFile:fileId offset:offset limit:count
			  completion:^(NSDictionary *file){
			TGClient *inner = weakSelf;
			if (!file || !inner){
				if (completion) completion(nil);
				return;
			}
			long long available = [file[@"prefixSize"] longLongValue];
			long long wanted = available < count ? available : count;
			if (wanted <= 0){
				if (completion) completion(nil);
				return;
			}
			[inner readFile:fileId offset:offset count:wanted completion:completion];
		}];
	}];
}

#pragma mark - thumbnails

- (NSDictionary *)bestPhotoSizeIn:(NSArray *)sizes
						 forWidth:(CGFloat)width
							scale:(CGFloat)scale {
	NSArray *list = TGFilesArray(sizes);
	if (!list.count)
		return nil;
	if (scale <= 0)
		scale = 1;
	CGFloat wanted = width * scale;

	NSDictionary *best = nil;
	NSInteger bestWidth = 0;
	NSDictionary *largest = nil;
	NSInteger largestWidth = -1;

	for (NSDictionary *size in list){
		if (![size isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *file = TGFilesDict(size[@"photo"]);
		if (!file)
			continue;
		NSInteger sizeWidth = [size[@"width"] integerValue];
		if (sizeWidth > largestWidth){
			largestWidth = sizeWidth;
			largest = size;
		}
		if (sizeWidth >= wanted && (!best || sizeWidth < bestWidth)){
			best = size;
			bestWidth = sizeWidth;
		}
	}

	NSDictionary *chosen = best ?: largest;
	if (!chosen)
		return nil;
	NSDictionary *file = TGFilesDict(chosen[@"photo"]) ?: @{};
	NSDictionary *local = TGFilesDict(file[@"local"]) ?: @{};
	return @{
		@"fileId"       : file[@"id"] ?: @0,
		@"width"        : chosen[@"width"] ?: @0,
		@"height"       : chosen[@"height"] ?: @0,
		@"type"         : TGFilesString(chosen[@"type"]),
		@"path"         : TGFilesString(local[@"path"]),
		@"isDownloaded" : local[@"is_downloading_completed"] ?: @NO,
	};
}

- (NSDictionary *)decodableThumbnail:(NSDictionary *)thumbnail {
	NSDictionary *thumb = TGFilesDict(thumbnail);
	if (!thumb)
		return nil;
	NSString *format = TGFilesDict(thumb[@"format"])[@"@type"];
	if (![format isEqualToString:@"thumbnailFormatJpeg"] &&
		![format isEqualToString:@"thumbnailFormatPng"])
		return nil;

	NSDictionary *file = TGFilesDict(thumb[@"file"]);
	if (!file)
		return nil;
	NSDictionary *local = TGFilesDict(file[@"local"]) ?: @{};
	return @{
		@"fileId"       : file[@"id"] ?: @0,
		@"width"        : thumb[@"width"] ?: @0,
		@"height"       : thumb[@"height"] ?: @0,
		@"type"         : format ?: @"",
		@"path"         : TGFilesString(local[@"path"]),
		@"isDownloaded" : local[@"is_downloading_completed"] ?: @NO,
	};
}

- (void)downloadPhotoSizes:(NSArray *)sizes
				  forWidth:(CGFloat)width
					 scale:(CGFloat)scale
				completion:(void (^)(NSString *, NSDictionary *))completion {
	NSDictionary *size = [self bestPhotoSizeIn:sizes forWidth:width scale:scale];
	if (!size){
		if (completion) completion(nil, nil);
		return;
	}
	NSString *ready = size[@"path"];
	if ([size[@"isDownloaded"] boolValue] && [ready isKindOfClass:NSString.class] &&
		ready.length){
		if (completion) completion(ready, size);
		return;
	}
	[self downloadFile:[size[@"fileId"] integerValue] completion:^(NSString *path){
		if (completion) completion(path, size);
	}];
}

- (NSData *)minithumbnailData:(NSDictionary *)minithumbnail {
	NSDictionary *thumb = TGFilesDict(minithumbnail);
	if (!thumb)
		return nil;
	return TGFilesDataFromBase64(thumb[@"data"]);
}

#pragma mark - uploading

- (void)uploadFileAtPath:(NSString *)path
					type:(NSString *)type
				priority:(NSInteger)priority
			  completion:(void (^)(NSDictionary *))completion {
	if (!path.length){
		if (completion) completion(nil);
		return;
	}
	if (priority < 1) priority = 1;
	if (priority > 32) priority = 32;
	[self request:@{
		@"@type"     : @"preliminaryUploadFile",
		@"file"      : @{@"@type" : @"inputFileLocal", @"path" : path},
		@"file_type" : @{@"@type" : type.length ? type : TGFileTypeDocument},
		@"priority"  : @(priority),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGFilesIsError(result) ? nil : TGFileInfo(result));
	}];
}

- (void)cancelUploadOfFile:(NSInteger)fileId {
	if (fileId <= 0)
		return;
	[self send:@{@"@type" : @"cancelPreliminaryUploadFile", @"file_id" : @(fileId)}];
}

#pragma mark - auto-download settings

- (void)setAutoDownloadSettings:(NSDictionary *)settings
					forNetwork:(NSString *)networkType
					 completion:(void (^)(BOOL))completion {
	NSDictionary *from = TGFilesDict(settings) ?: @{};
	NSDictionary *payload = @{
		@"@type"                   : @"autoDownloadSettings",
		@"is_auto_download_enabled": from[@"enabled"] ?: @NO,
		@"max_photo_file_size"     : from[@"maxPhotoSize"] ?: @(1048576),
		@"max_video_file_size"     : from[@"maxVideoSize"] ?: @(1048576),
		@"max_other_file_size"     : from[@"maxOtherSize"] ?: @(1048576),
		@"video_upload_bitrate"    : from[@"videoUploadBitrate"] ?: @(0),
		@"preload_large_videos"    : from[@"preloadLargeVideos"] ?: @NO,
		@"preload_next_audio"      : from[@"preloadNextAudio"] ?: @NO,
		@"preload_stories"         : from[@"preloadStories"] ?: @NO,
		@"use_less_data_for_calls" : from[@"useLessDataForCalls"] ?:
									 from[@"lessDataForCalls"] ?: @NO,
	};
	[self request:@{
		@"@type"    : @"setAutoDownloadSettings",
		@"settings" : payload,
		@"type"     : @{@"@type" : networkType.length ? networkType : TGNetworkTypeOther},
	} completion:^(NSDictionary *result){
		if (completion) completion(!TGFilesIsError(result));
	}];
}

#pragma mark - statistics

- (void)resetNetworkStatistics {
	[self send:@{@"@type" : @"resetNetworkStatistics"}];
}

- (void)storageStatisticsWithChatLimit:(NSInteger)chatLimit
							completion:(void (^)(NSDictionary *))completion {
	if (chatLimit < 0)
		chatLimit = 0;
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getStorageStatistics", @"chat_limit" : @(chatLimit)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGFilesIsError(result)){
			completion(nil);
			return;
		}
		TGClient *me = weakSelf;

		NSMutableArray *chats = [NSMutableArray array];
		for (NSDictionary *byChat in TGFilesArray(result[@"by_chat"])){
			if (![byChat isKindOfClass:NSDictionary.class])
				continue;
			NSMutableArray *byType = [NSMutableArray array];
			for (NSDictionary *entry in TGFilesArray(byChat[@"by_file_type"])){
				if (![entry isKindOfClass:NSDictionary.class])
					continue;
				[byType addObject:@{
					@"type"  : TGFilesString(TGFilesDict(entry[@"file_type"])[@"@type"]),
					@"size"  : entry[@"size"] ?: @0,
					@"count" : entry[@"count"] ?: @0,
				}];
			}
			int64_t chatId = [byChat[@"chat_id"] longLongValue];
			NSString *title = @"";
			if (chatId != 0 && me){
				NSDictionary *known = me.chatsById[@(chatId)];
				title = TGFilesString(known[@"title"]);
			}
			[chats addObject:@{
				@"chatId" : @(chatId),
				@"title"  : title,
				@"size"   : byChat[@"size"] ?: @0,
				@"count"  : byChat[@"count"] ?: @0,
				@"byType" : byType,
			}];
		}

		[chats sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
			long long left = [a[@"size"] longLongValue];
			long long right = [b[@"size"] longLongValue];
			if (left == right)
				return NSOrderedSame;
			return left > right ? NSOrderedAscending : NSOrderedDescending;
		}];

		completion(@{
			@"size"  : result[@"size"] ?: @0,
			@"count" : result[@"count"] ?: @0,
			@"chats" : chats,
		});
	}];
}

#pragma mark - small helpers

- (void)tg_filesTextCall:(NSString *)method
			 key:(NSString *)key
		   value:(NSString *)value
	  completion:(void (^)(NSString *))completion {
	[self request:@{@"@type" : method, key : value ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGFilesIsError(result)){
			completion(nil);
			return;
		}
		NSString *text = TGFilesString(result[@"text"]);
		completion(text.length ? text : nil);
	}];
}

- (void)fileExtensionForMimeType:(NSString *)mimeType
					  completion:(void (^)(NSString *))completion {
	[self tg_filesTextCall:@"getFileExtension" key:@"mime_type" value:mimeType completion:completion];
}

@end

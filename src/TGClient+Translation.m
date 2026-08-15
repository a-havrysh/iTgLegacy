#import "TGClient+Private.h"
#import "TGClient+Translation.h"

static BOOL TGTrIsError(NSDictionary *result){
	if (![result isKindOfClass:NSDictionary.class])
		return YES;
	id type = [result objectForKey:@"@type"];
	return [type isKindOfClass:NSString.class] &&
	       [type isEqualToString:@"error"];
}

static NSString *TGTrString(id value){
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSNumber *TGTrNumber(id value){
	return [value isKindOfClass:NSNumber.class] ? value : @(0);
}

static NSArray *TGTrArray(id value){
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSDictionary *TGTrDict(id value){
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSDictionary *TGTrFormattedText(NSString *text){
	return @{@"@type"    : @"formattedText",
			 @"text"     : text ?: @"",
			 @"entities" : @[]};
}

static NSDictionary *TGTrPack(id raw){
	NSDictionary *p = TGTrDict(raw);
	if (!TGTrString(p[@"id"]).length)
		return nil;
	NSString *name = TGTrString(p[@"native_name"]);
	if (!name.length)
		name = TGTrString(p[@"name"]);
	if (!name.length)
		name = TGTrString(p[@"id"]);
	return @{
		@"id"                : TGTrString(p[@"id"]),
		@"name"              : name,
		@"nativeName"        : TGTrString(p[@"native_name"]),
		@"baseId"            : TGTrString(p[@"base_language_pack_id"]),
		@"pluralCode"        : TGTrString(p[@"plural_code"]),
		@"official"          : @([p[@"is_official"] boolValue]),
		@"rtl"               : @([p[@"is_rtl"] boolValue]),
		@"beta"              : @([p[@"is_beta"] boolValue]),
		@"installed"         : @([p[@"is_installed"] boolValue]),
		@"totalStrings"      : TGTrNumber(p[@"total_string_count"]),
		@"translatedStrings" : TGTrNumber(p[@"translated_string_count"]),
		@"localStrings"      : TGTrNumber(p[@"local_string_count"]),
		@"translationUrl"    : TGTrString(p[@"translation_url"]),
	};
}

static NSArray *TGTrPacks(NSDictionary *target){
	NSArray *raw = TGTrArray(TGTrDict(target)[@"language_packs"]);
	NSMutableArray *out = [NSMutableArray array];
	for (id item in raw){
		NSDictionary *pack = TGTrPack(item);
		if (pack)
			[out addObject:pack];
	}
	return out;
}

static NSDictionary *TGTrTranscript(id raw){
	NSDictionary *r = TGTrDict(raw);
	NSString *type = TGTrString(r[@"@type"]);
	if ([type isEqualToString:@"speechRecognitionResultText"])
		return @{@"state" : @"text",
				 @"text"  : TGTrString(r[@"text"]),
				 @"error" : @""};
	if ([type isEqualToString:@"speechRecognitionResultPending"])
		return @{@"state" : @"pending",
				 @"text"  : TGTrString(r[@"partial_text"]),
				 @"error" : @""};
	if ([type isEqualToString:@"speechRecognitionResultError"]){
		NSString *message = TGTrString(TGTrDict(r[@"error"])[@"message"]);
		return @{@"state" : @"error",
				 @"text"  : @"",
				 @"error" : message.length ? message : @"Transcription failed"};
	}
	return nil;
}

static NSDictionary *TGTrNoteOfMessage(NSDictionary *message){
	NSDictionary *content = TGTrDict(TGTrDict(message)[@"content"]);
	NSDictionary *note = TGTrDict(content[@"voice_note"]);
	if (!note)
		note = TGTrDict(content[@"video_note"]);
	return note;
}

static id TGTrStringValue(id raw){
	NSDictionary *v = TGTrDict(raw);
	NSString *type = TGTrString(v[@"@type"]);
	if ([type isEqualToString:@"languagePackStringValueOrdinary"])
		return TGTrString(v[@"value"]);
	if (![type isEqualToString:@"languagePackStringValuePluralized"])
		return nil;

	NSArray *forms = @[@"zero", @"one", @"two", @"few", @"many", @"other"];
	NSMutableDictionary *plural = [NSMutableDictionary dictionary];
	for (NSString *form in forms){
		NSString *value = TGTrString(v[[form stringByAppendingString:@"_value"]]);
		if (value.length)
			[plural setObject:value forKey:form];
	}
	return plural.count ? plural : nil;
}

@implementation TGClient (Translation)

#pragma mark - translating text

- (void)translateMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
              toLanguage:(NSString *)languageCode
                    tone:(NSString *)tone
              completion:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"            : @"translateMessageText",
		@"chat_id"          : @(chatId),
		@"message_id"       : @(messageId),
		@"to_language_code" : languageCode.length ? languageCode : @"en",
		@"tone"             : tone ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGTrIsError(result)){
			completion(nil);
			return;
		}
		NSString *text = TGTrString(result[@"text"]);
		completion(text.length ? text : nil);
	}];
}

- (void)translateText:(NSString *)text
           toLanguage:(NSString *)languageCode
                 tone:(NSString *)tone
           completion:(void (^)(NSString *))completion {
	if (!text.length){
		if (completion)
			completion(nil);
		return;
	}

	[self request:@{
		@"@type"            : @"translateText",
		@"text"             : TGTrFormattedText(text),
		@"to_language_code" : languageCode.length ? languageCode : @"en",
		@"tone"             : tone ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGTrIsError(result)){
			completion(nil);
			return;
		}
		NSString *out = TGTrString(result[@"text"]);
		completion(out.length ? out : nil);
	}];
}

- (void)setChat:(int64_t)chatId translatable:(BOOL)translatable {
	[self send:@{
		@"@type"          : @"toggleChatIsTranslatable",
		@"chat_id"        : @(chatId),
		@"is_translatable": @(translatable),
	}];
}

#pragma mark - language packs

- (void)languagePacksWithCompletion:(void (^)(NSArray *, NSString *))completion {
	if (!completion)
		return;

	__weak typeof(self) weakSelf = self;
	void (^answer)(NSArray *) = ^(NSArray *packs){
		[weakSelf request:@{@"@type" : @"getOption",
							@"name"  : @"language_pack_id"}
			   completion:^(NSDictionary *option){
			NSString *current = TGTrString(TGTrDict(option)[@"value"]);
			if (!current.length)
				current = @"en";
			completion(packs ?: [NSArray array], current);
		}];
	};

	[self request:@{@"@type"      : @"getLocalizationTargetInfo",
					@"only_local" : @NO}
	   completion:^(NSDictionary *target){
		NSArray *packs = TGTrPacks(target);
		if (packs.count){
			answer(packs);
			return;
		}
		[weakSelf request:@{@"@type"      : @"getLocalizationTargetInfo",
							@"only_local" : @YES}
			   completion:^(NSDictionary *local){
			answer(TGTrPacks(local));
		}];
	}];
}

- (void)synchronizeLanguagePack:(NSString *)packId {
	if (!packId.length)
		return;
	[self send:@{@"@type"            : @"synchronizeLanguagePack",
				 @"language_pack_id" : packId}];
}

- (void)languagePackStrings:(NSString *)packId
                       keys:(NSArray *)keys
                 completion:(void (^)(NSDictionary *))completion {
	if (!completion)
		return;
	if (!packId.length){
		completion([NSDictionary dictionary]);
		return;
	}

	NSMutableArray *wanted = [NSMutableArray array];
	for (id key in keys){
		if ([key isKindOfClass:NSString.class])
			[wanted addObject:key];
	}

	[self request:@{@"@type"            : @"getLanguagePackStrings",
					@"language_pack_id" : packId,
					@"keys"             : wanted}
	   completion:^(NSDictionary *result){
		NSMutableDictionary *out = [NSMutableDictionary dictionary];
		for (id item in TGTrArray(TGTrDict(result)[@"strings"])){
			NSDictionary *entry = TGTrDict(item);
			NSString *key = TGTrString(entry[@"key"]);
			id value = TGTrStringValue(entry[@"value"]);
			if (key.length && value)
				[out setObject:value forKey:key];
		}
		completion(out);
	}];
}

- (void)deleteLanguagePack:(NSString *)packId
                completion:(void (^)(BOOL))completion {
	if (!packId.length){
		if (completion)
			completion(NO);
		return;
	}

	[self request:@{@"@type"            : @"deleteLanguagePack",
					@"language_pack_id" : packId}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGTrIsError(result));
	}];
}

#pragma mark - speech recognition

- (void)speechTranscriptForMessage:(int64_t)messageId
                            inChat:(int64_t)chatId
                        completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type"      : @"getMessage",
					@"chat_id"    : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *message){
		if (!completion)
			return;
		if (TGTrIsError(message)){
			completion(nil);
			return;
		}
		NSDictionary *note = TGTrNoteOfMessage(message);
		completion(note ? TGTrTranscript(note[@"speech_recognition_result"]) : nil);
	}];
}

- (void)rateSpeechRecognitionForMessage:(int64_t)messageId
                                 inChat:(int64_t)chatId
                                   good:(BOOL)good {
	[self send:@{@"@type"      : @"rateSpeechRecognition",
				 @"chat_id"    : @(chatId),
				 @"message_id" : @(messageId),
				 @"is_good"    : @(good)}];
}

@end

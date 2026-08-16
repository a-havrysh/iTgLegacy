#import "TGClient+AppSettings.h"
#import "TGClient+Private.h"

static BOOL TGASIsError(id result){
	return ![result isKindOfClass:NSDictionary.class] ||
		   [((NSDictionary *)result)[@"@type"] isEqualToString:@"error"];
}

static NSString *TGASIdString(id value){
	if ([value isKindOfClass:NSString.class])
		return value;
	if ([value isKindOfClass:NSNumber.class])
		return [NSString stringWithFormat:@"%lld", [value longLongValue]];
	return nil;
}

static NSDictionary *TGASDict(id value){
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSNumber *TGASFileId(id file){
	NSDictionary *dict = TGASDict(file);
	id fileId = dict[@"id"];
	if ([fileId isKindOfClass:NSNumber.class])
		return fileId;
	return nil;
}

static void TGASApplyFill(NSMutableDictionary *out, NSDictionary *fill){
	if (!fill)
		return;
	NSString *type = fill[@"@type"];
	if ([type isEqualToString:@"backgroundFillSolid"]){
		id color = fill[@"color"];
		if ([color isKindOfClass:NSNumber.class]){
			out[@"topColor"] = color;
			out[@"bottomColor"] = color;
		}
		return;
	}
	if ([type isEqualToString:@"backgroundFillGradient"]){
		if ([fill[@"top_color"] isKindOfClass:NSNumber.class])
			out[@"topColor"] = fill[@"top_color"];
		if ([fill[@"bottom_color"] isKindOfClass:NSNumber.class])
			out[@"bottomColor"] = fill[@"bottom_color"];
		if ([fill[@"rotation_angle"] isKindOfClass:NSNumber.class])
			out[@"rotation"] = fill[@"rotation_angle"];
		return;
	}
	if ([type isEqualToString:@"backgroundFillFreeformGradient"]){
		NSArray *colors = fill[@"colors"];
		if ([colors isKindOfClass:NSArray.class] && colors.count > 0){
			if ([colors[0] isKindOfClass:NSNumber.class])
				out[@"topColor"] = colors[0];
			id last = colors.lastObject;
			if ([last isKindOfClass:NSNumber.class])
				out[@"bottomColor"] = last;
		}
	}
}

static NSDictionary *TGASBackgroundRow(id object){
	NSDictionary *background = TGASDict(object);
	if (!background)
		return nil;
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	NSString *identifier = TGASIdString(background[@"id"]);
	out[@"id"] = identifier ? identifier : @"0";
	NSString *name = background[@"name"];
	out[@"name"] = [name isKindOfClass:NSString.class] ? name : @"";
	out[@"isDark"] = @([background[@"is_dark"] boolValue]);
	out[@"isDefault"] = @([background[@"is_default"] boolValue]);

	NSDictionary *document = TGASDict(background[@"document"]);
	NSNumber *fileId = TGASFileId(document[@"document"]);
	if (fileId)
		out[@"fileId"] = fileId;
	NSDictionary *thumbnail = TGASDict(document[@"thumbnail"]);
	NSNumber *thumbId = TGASFileId(thumbnail[@"file"]);
	if (thumbId)
		out[@"thumbFileId"] = thumbId;

	NSDictionary *type = TGASDict(background[@"type"]);
	NSString *typeName = type[@"@type"];
	NSString *kind = @"wallpaper";
	if ([typeName isEqualToString:@"backgroundTypePattern"])
		kind = @"pattern";
	else if ([typeName isEqualToString:@"backgroundTypeFill"])
		kind = @"fill";
	else if ([typeName isEqualToString:@"backgroundTypeChatTheme"])
		kind = @"theme";
	out[@"kind"] = kind;
	out[@"isBlurred"] = @([type[@"is_blurred"] boolValue]);
	out[@"isMoving"] = @([type[@"is_moving"] boolValue]);
	if ([type[@"intensity"] isKindOfClass:NSNumber.class])
		out[@"intensity"] = type[@"intensity"];
	out[@"isInverted"] = @([type[@"is_inverted"] boolValue]);
	TGASApplyFill(out, TGASDict(type[@"fill"]));
	return out;
}

static NSDictionary *TGASFillFromRow(NSDictionary *row){
	NSNumber *top = row[@"topColor"];
	NSNumber *bottom = row[@"bottomColor"];
	if (![top isKindOfClass:NSNumber.class])
		top = @0;
	if (![bottom isKindOfClass:NSNumber.class])
		bottom = top;
	if ([top intValue] == [bottom intValue])
		return @{ @"@type" : @"backgroundFillSolid",
				  @"color" : @([top intValue]) };
	NSInteger angle = [row[@"rotation"] isKindOfClass:NSNumber.class]
			? [row[@"rotation"] integerValue] : 0;
	angle %= 360;
	if (angle < 0)
		angle += 360;
	angle = (angle / 45) * 45;
	return @{ @"@type"          : @"backgroundFillGradient",
			  @"top_color"      : @([top intValue]),
			  @"bottom_color"   : @([bottom intValue]),
			  @"rotation_angle" : @((int)angle) };
}

static NSDictionary *TGASBackgroundTypeForKind(NSString *kind){
	if ([kind isEqualToString:@"pattern"])
		return @{ @"@type"       : @"backgroundTypePattern",
				  @"fill"        : @{ @"@type" : @"backgroundFillSolid", @"color" : @0 },
				  @"intensity"   : @50,
				  @"is_inverted" : @NO,
				  @"is_moving"   : @NO };
	if ([kind isEqualToString:@"fill"])
		return @{ @"@type" : @"backgroundTypeFill",
				  @"fill"  : @{ @"@type" : @"backgroundFillSolid", @"color" : @0 } };
	return @{ @"@type"      : @"backgroundTypeWallpaper",
			  @"is_blurred" : @NO,
			  @"is_moving"  : @NO };
}

@implementation TGClient (AppSettings)

#pragma mark - wallpapers

- (void)tgas_setDefaultBackground:(NSDictionary *)background
							 type:(NSDictionary *)type
					 forDarkTheme:(BOOL)forDarkTheme
					   completion:(void (^)(NSDictionary *background))completion {
	NSMutableDictionary *request = [NSMutableDictionary dictionary];
	request[@"@type"] = @"setDefaultBackground";
	if (background)
		request[@"background"] = background;
	if (type)
		request[@"type"] = type;
	request[@"for_dark_theme"] = @(forDarkTheme);
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGASIsError(result)){
			completion(nil);
			return;
		}
		completion(TGASBackgroundRow(result));
	}];
}

- (void)installedBackgroundsForDarkTheme:(BOOL)forDarkTheme
							  completion:(void (^)(NSArray *backgrounds))completion {
	[self request:@{ @"@type"          : @"getInstalledBackgrounds",
					 @"for_dark_theme" : @(forDarkTheme) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGASIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		NSArray *backgrounds = result[@"backgrounds"];
		if ([backgrounds isKindOfClass:NSArray.class]){
			for (id item in backgrounds){
				NSDictionary *row = TGASBackgroundRow(item);
				if (row)
					[out addObject:row];
			}
		}
		completion(out);
	}];
}

- (void)setDefaultBackgroundId:(NSString *)backgroundId
					   blurred:(BOOL)blurred
						moving:(BOOL)moving
				  forDarkTheme:(BOOL)forDarkTheme
					completion:(void (^)(NSDictionary *background))completion {
	NSString *identifier = TGASIdString(backgroundId);
	if (identifier.length == 0){
		if (completion)
			completion(nil);
		return;
	}
	[self tgas_setDefaultBackground:@{ @"@type"         : @"inputBackgroundRemote",
									   @"background_id" : identifier }
							   type:@{ @"@type"      : @"backgroundTypeWallpaper",
									   @"is_blurred" : @(blurred),
									   @"is_moving"  : @(moving) }
					   forDarkTheme:forDarkTheme
						 completion:completion];
}

- (void)setDefaultBackgroundRow:(NSDictionary *)row
						blurred:(BOOL)blurred
				   forDarkTheme:(BOOL)forDarkTheme
					 completion:(void (^)(NSDictionary *background))completion {
	if (![row isKindOfClass:NSDictionary.class]){
		if (completion)
			completion(nil);
		return;
	}
	NSString *kind = [row[@"kind"] isKindOfClass:NSString.class] ? row[@"kind"] : @"wallpaper";

	if ([kind isEqualToString:@"fill"]){
		[self tgas_setDefaultBackground:nil
								   type:@{ @"@type" : @"backgroundTypeFill",
										   @"fill"  : TGASFillFromRow(row) }
						   forDarkTheme:forDarkTheme
							 completion:completion];
		return;
	}

	NSString *identifier = TGASIdString(row[@"id"]);
	if (identifier.length == 0 || [identifier isEqualToString:@"0"]){
		if (completion)
			completion(nil);
		return;
	}
	NSDictionary *background = @{ @"@type"         : @"inputBackgroundRemote",
								  @"background_id" : identifier };

	if ([kind isEqualToString:@"pattern"]){
		NSInteger intensity = [row[@"intensity"] isKindOfClass:NSNumber.class]
				? [row[@"intensity"] integerValue] : 50;
		[self tgas_setDefaultBackground:background
								   type:@{ @"@type"       : @"backgroundTypePattern",
										   @"fill"        : TGASFillFromRow(row),
										   @"intensity"   : @((int)intensity),
										   @"is_inverted" : @([row[@"isInverted"] boolValue]),
										   @"is_moving"   : @([row[@"isMoving"] boolValue]) }
						   forDarkTheme:forDarkTheme
							 completion:completion];
		return;
	}

	[self tgas_setDefaultBackground:background
							   type:@{ @"@type"      : @"backgroundTypeWallpaper",
									   @"is_blurred" : @(blurred),
									   @"is_moving"  : @([row[@"isMoving"] boolValue]) }
					   forDarkTheme:forDarkTheme
						 completion:completion];
}

- (void)setDefaultBackgroundColor:(NSInteger)color
					 forDarkTheme:(BOOL)forDarkTheme
					   completion:(void (^)(NSDictionary *background))completion {
	[self tgas_setDefaultBackground:nil
							   type:@{ @"@type" : @"backgroundTypeFill",
									   @"fill"  : @{ @"@type" : @"backgroundFillSolid",
													 @"color" : @((int)color) } }
					   forDarkTheme:forDarkTheme
						 completion:completion];
}

- (void)setDefaultBackgroundGradientTop:(NSInteger)topColor
								 bottom:(NSInteger)bottomColor
							   rotation:(NSInteger)rotation
						   forDarkTheme:(BOOL)forDarkTheme
							 completion:(void (^)(NSDictionary *background))completion {
	NSInteger angle = rotation % 360;
	if (angle < 0)
		angle += 360;
	angle = (angle / 45) * 45;
	[self tgas_setDefaultBackground:nil
							   type:@{ @"@type" : @"backgroundTypeFill",
									   @"fill"  : @{ @"@type"          : @"backgroundFillGradient",
													 @"top_color"      : @((int)topColor),
													 @"bottom_color"   : @((int)bottomColor),
													 @"rotation_angle" : @((int)angle) } }
					   forDarkTheme:forDarkTheme
						 completion:completion];
}

- (void)setDefaultBackgroundAtPath:(NSString *)path
						   blurred:(BOOL)blurred
					  forDarkTheme:(BOOL)forDarkTheme
						completion:(void (^)(NSDictionary *background))completion {
	if (path.length == 0){
		if (completion)
			completion(nil);
		return;
	}
	[self tgas_setDefaultBackground:@{ @"@type"      : @"inputBackgroundLocal",
									   @"background" : @{ @"@type" : @"inputFileLocal",
														  @"path"  : path } }
							   type:@{ @"@type"      : @"backgroundTypeWallpaper",
									   @"is_blurred" : @(blurred),
									   @"is_moving"  : @NO }
					   forDarkTheme:forDarkTheme
						 completion:completion];
}

- (void)resetDefaultBackgroundForDarkTheme:(BOOL)forDarkTheme {
	[self send:@{ @"@type"          : @"deleteDefaultBackground",
				  @"for_dark_theme" : @(forDarkTheme) }];
}

- (void)shareUrlForBackgroundNamed:(NSString *)name
							  kind:(NSString *)kind
						completion:(void (^)(NSString *url))completion {
	if (name.length == 0){
		if (completion)
			completion(nil);
		return;
	}
	[self request:@{ @"@type" : @"getBackgroundUrl",
					 @"name"  : name,
					 @"type"  : TGASBackgroundTypeForKind(kind) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *url = TGASIsError(result) ? nil : result[@"url"];
		completion([url isKindOfClass:NSString.class] ? url : nil);
	}];
}

- (void)removeInstalledBackgroundId:(NSString *)backgroundId {
	NSString *identifier = TGASIdString(backgroundId);
	if (identifier.length == 0)
		return;
	[self send:@{ @"@type"         : @"removeInstalledBackground",
				  @"background_id" : identifier }];
}

- (void)resetInstalledBackgrounds {
	[self send:@{@"@type" : @"resetInstalledBackgrounds"}];
}

#pragma mark - per-chat theme

- (void)chatThemeEmojiForChat:(int64_t)chatId
				   completion:(void (^)(NSString *emoji))completion {
	[self request:@{ @"@type" : @"getChat", @"chat_id" : @(chatId) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGASIsError(result)){
			completion(nil);
			return;
		}
		NSDictionary *theme = TGASDict(result[@"theme"]);
		NSString *name = theme[@"name"];
		if ([theme[@"@type"] isEqualToString:@"chatThemeEmoji"] &&
			[name isKindOfClass:NSString.class] && name.length > 0){
			completion(name);
			return;
		}
		completion(nil);
	}];
}

#pragma mark - suggested actions

- (void)hideSuggestedActionNamed:(NSString *)name {
	if (name.length == 0)
		return;
	NSMutableDictionary *action = [NSMutableDictionary dictionary];
	action[@"@type"] = name;
	if ([name isEqualToString:@"suggestedActionSetPassword"])
		action[@"authorization_delay"] = @0;
	if ([name isEqualToString:@"suggestedActionSetLoginEmailAddress"])
		action[@"can_be_hidden"] = @YES;
	[self send:@{ @"@type" : @"hideSuggestedAction", @"action" : action }];
}

- (void)acceptArchiveAndMuteSuggestion {
	__weak TGClient *weakSelf = self;
	[self request:@{@"@type" : @"getArchiveChatListSettings"} completion:^(NSDictionary *result){
		TGClient *strongSelf = weakSelf;
		if (!strongSelf)
			return;
		BOOL keepUnmuted = NO;
		BOOL keepFolders = NO;
		if (!TGASIsError(result)){
			keepUnmuted = [result[@"keep_unmuted_chats_archived"] boolValue];
			keepFolders = [result[@"keep_chats_from_folders_archived"] boolValue];
		}
		[strongSelf send:@{ @"@type"    : @"setArchiveChatListSettings",
							@"settings" : @{ @"@type" : @"archiveChatListSettings",
											 @"archive_and_mute_new_chats_from_unknown_users" : @YES,
											 @"keep_unmuted_chats_archived"      : @(keepUnmuted),
											 @"keep_chats_from_folders_archived" : @(keepFolders) } }];
		[strongSelf hideSuggestedActionNamed:@"suggestedActionEnableArchiveAndMuteNewChats"];
	}];
}

@end

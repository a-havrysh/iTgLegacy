#import "TGClient+Notifications.h"
#import "TGClient+Private.h"

const NSInteger TGNotificationMuteForever = 365 * 24 * 3600;

NSString *const TGScopeNotificationSettingsDidChangeNotification =
		@"TGScopeNotificationSettingsDidChangeNotification";

NSString *const TGNotificationUpdateNotification =
		@"TGNotificationUpdateNotification";

static NSString *TGNotifScopeType(NSString *scope) {
	if ([scope isEqualToString:@"groups"])   return @"notificationSettingsScopeGroupChats";
	if ([scope isEqualToString:@"channels"]) return @"notificationSettingsScopeChannelChats";
	return @"notificationSettingsScopePrivateChats";
}

static BOOL TGNotifIsError(NSDictionary *result) {
	return ![result isKindOfClass:[NSDictionary class]] ||
			[result[@"@type"] isEqualToString:@"error"];
}

static NSNumber *TGNotifBool(NSDictionary *d, NSString *key) {
	id value = [d isKindOfClass:[NSDictionary class]] ? d[key] : nil;
	return @([value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO);
}

static NSNumber *TGNotifNumber(NSDictionary *d, NSString *key) {
	id value = [d isKindOfClass:[NSDictionary class]] ? d[key] : nil;
	return [value isKindOfClass:[NSNumber class]] ? value : @(0);
}

static NSString *TGNotifString(NSDictionary *d, NSString *key) {
	id value = [d isKindOfClass:[NSDictionary class]] ? d[key] : nil;
	return [value isKindOfClass:[NSString class]] ? value : @"";
}

/// Pick `key` out of the caller's changes, falling back to what is stored now.
static id TGNotifPick(NSDictionary *changes, NSDictionary *current, NSString *key) {
	id value = [changes isKindOfClass:[NSDictionary class]] ? changes[key] : nil;
	if ([value isKindOfClass:[NSNumber class]])
		return value;
	return current[key] ?: @(0);
}

static NSString *TGNotifReactionSource(NSString *name) {
	if ([name isEqualToString:@"all"])      return @"reactionNotificationSourceAll";
	if ([name isEqualToString:@"contacts"]) return @"reactionNotificationSourceContacts";
	return @"reactionNotificationSourceNone";
}

@implementation TGClient (Notifications)

#pragma mark - scope settings

static NSDictionary *TGNotifScopeSettingsFrom(NSDictionary *s) {
	return @{
		@"muted"       : @([TGNotifNumber(s, @"mute_for") integerValue] > 0),
		@"muteFor"     : TGNotifNumber(s, @"mute_for"),
		@"showPreview" : TGNotifBool(s, @"show_preview"),
		@"soundId"     : TGNotifNumber(s, @"sound_id"),
		@"useDefaultMuteStories" : TGNotifBool(s, @"use_default_mute_stories"),
		@"muteStories"           : TGNotifBool(s, @"mute_stories"),
		@"storySoundId"          : TGNotifNumber(s, @"story_sound_id"),
		@"showStoryPoster"       : TGNotifBool(s, @"show_story_poster"),
		@"disablePinnedMessageNotifications" :
				TGNotifBool(s, @"disable_pinned_message_notifications"),
		@"disableMentionNotifications" :
				TGNotifBool(s, @"disable_mention_notifications"),
	};
}

- (void)notificationSettingsForScope:(NSString *)scope
                          completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type" : @"getScopeNotificationSettings",
		@"scope" : @{@"@type" : TGNotifScopeType(scope)},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGNotifIsError(result)){
			completion(nil);
			return;
		}
		completion(TGNotifScopeSettingsFrom(result));
	}];
}

- (void)writeScope:(NSString *)scope settings:(NSDictionary *)settings {
	[self send:@{
		@"@type" : @"setScopeNotificationSettings",
		@"scope" : @{@"@type" : TGNotifScopeType(scope)},
		@"notification_settings" : @{
			@"@type"        : @"scopeNotificationSettings",
			@"mute_for"     : settings[@"muteFor"] ?: @(0),
			@"sound_id"     : settings[@"soundId"] ?: @(0),
			@"show_preview" : settings[@"showPreview"] ?: @YES,
			@"use_default_mute_stories" : settings[@"useDefaultMuteStories"] ?: @YES,
			@"mute_stories"             : settings[@"muteStories"] ?: @NO,
			@"story_sound_id"           : settings[@"storySoundId"] ?: @(0),
			@"show_story_poster"        : settings[@"showStoryPoster"] ?: @NO,
			@"disable_pinned_message_notifications" :
					settings[@"disablePinnedMessageNotifications"] ?: @NO,
			@"disable_mention_notifications" :
					settings[@"disableMentionNotifications"] ?: @NO,
		},
	}];
}

- (void)updateScope:(NSString *)scope
             values:(NSDictionary *)changes
         completion:(void (^)(BOOL))completion {
	__weak typeof(self) weakSelf = self;
	[self notificationSettingsForScope:scope completion:^(NSDictionary *current){
		if (!current){
			if (completion) completion(NO);
			return;
		}
		NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:current];
		for (NSString *key in [merged allKeys])
			merged[key] = TGNotifPick(changes, current, key);
		if ([changes isKindOfClass:[NSDictionary class]] &&
				[changes[@"muted"] isKindOfClass:[NSNumber class]] &&
				![changes[@"muteFor"] isKindOfClass:[NSNumber class]])
			merged[@"muteFor"] = @([changes[@"muted"] boolValue] ? TGNotificationMuteForever : 0);

		[weakSelf writeScope:scope settings:merged];
		if (completion) completion(YES);
	}];
}

- (void)setScope:(NSString *)scope muteForSeconds:(NSInteger)seconds {
	[self updateScope:scope values:@{@"muteFor" : @(seconds)} completion:nil];
}

#pragma mark - per-chat settings

static NSDictionary *TGNotifChatSettingsFrom(NSDictionary *s, BOOL defaultSilent) {
	return @{
		@"muted"             : @([TGNotifNumber(s, @"mute_for") integerValue] > 0),
		@"muteFor"           : TGNotifNumber(s, @"mute_for"),
		@"useDefaultMuteFor" : TGNotifBool(s, @"use_default_mute_for"),
		@"showPreview"       : TGNotifBool(s, @"show_preview"),
		@"useDefaultShowPreview" : TGNotifBool(s, @"use_default_show_preview"),
		@"soundId"           : TGNotifNumber(s, @"sound_id"),
		@"useDefaultSound"   : TGNotifBool(s, @"use_default_sound"),
		@"disablePinnedMessageNotifications" :
				TGNotifBool(s, @"disable_pinned_message_notifications"),
		@"useDefaultDisablePinnedMessageNotifications" :
				TGNotifBool(s, @"use_default_disable_pinned_message_notifications"),
		@"disableMentionNotifications" :
				TGNotifBool(s, @"disable_mention_notifications"),
		@"useDefaultDisableMentionNotifications" :
				TGNotifBool(s, @"use_default_disable_mention_notifications"),
		@"defaultDisableNotification" : @(defaultSilent),
	};
}

- (void)notificationSettingsForChat:(int64_t)chatId
                         completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (!completion)
			return;
		if (TGNotifIsError(chat)){
			completion(nil);
			return;
		}
		NSDictionary *s = chat[@"notification_settings"];
		if (![s isKindOfClass:[NSDictionary class]])
			s = [NSDictionary dictionary];
		completion(TGNotifChatSettingsFrom(s,
				[chat[@"default_disable_notification"] boolValue]));
	}];
}

- (NSDictionary *)chatNotificationPayloadFrom:(NSDictionary *)settings {
	return @{
		@"@type"                : @"chatNotificationSettings",
		@"use_default_mute_for" : settings[@"useDefaultMuteFor"] ?: @NO,
		@"mute_for"             : settings[@"muteFor"] ?: @(0),
		@"use_default_sound"    : settings[@"useDefaultSound"] ?: @YES,
		@"sound_id"             : settings[@"soundId"] ?: @(0),
		@"use_default_show_preview" : settings[@"useDefaultShowPreview"] ?: @YES,
		@"show_preview"             : settings[@"showPreview"] ?: @YES,
		@"use_default_mute_stories" : @YES,
		@"mute_stories"             : @NO,
		@"use_default_story_sound"  : @YES,
		@"story_sound_id"           : @(0),
		@"use_default_show_story_poster" : @YES,
		@"show_story_poster"             : @NO,
		@"use_default_disable_pinned_message_notifications" :
				settings[@"useDefaultDisablePinnedMessageNotifications"] ?: @YES,
		@"disable_pinned_message_notifications" :
				settings[@"disablePinnedMessageNotifications"] ?: @NO,
		@"use_default_disable_mention_notifications" :
				settings[@"useDefaultDisableMentionNotifications"] ?: @YES,
		@"disable_mention_notifications" :
				settings[@"disableMentionNotifications"] ?: @NO,
	};
}

- (void)writeChat:(int64_t)chatId settings:(NSDictionary *)settings {
	[self send:@{
		@"@type"   : @"setChatNotificationSettings",
		@"chat_id" : @(chatId),
		@"notification_settings" : [self chatNotificationPayloadFrom:settings],
	}];
}

- (void)setChat:(int64_t)chatId muteForSeconds:(NSInteger)seconds {
	[self updateChat:chatId
			  values:@{@"muteFor" : @(seconds), @"useDefaultMuteFor" : @NO}
		  completion:nil];
}

- (void)updateChat:(int64_t)chatId
            values:(NSDictionary *)changes
        completion:(void (^)(BOOL))completion {
	__weak typeof(self) weakSelf = self;
	[self notificationSettingsForChat:chatId completion:^(NSDictionary *current){
		if (!current){
			if (completion) completion(NO);
			return;
		}
		NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:current];
		for (NSString *key in [merged allKeys])
			merged[key] = TGNotifPick(changes, current, key);

		if ([changes isKindOfClass:[NSDictionary class]]){
			if ([changes[@"muted"] isKindOfClass:[NSNumber class]] &&
					![changes[@"muteFor"] isKindOfClass:[NSNumber class]]){
				merged[@"muteFor"] = @([changes[@"muted"] boolValue] ? TGNotificationMuteForever : 0);
				merged[@"useDefaultMuteFor"] = @NO;
			}
			if ([changes[@"muteFor"] isKindOfClass:[NSNumber class]] &&
					![changes[@"useDefaultMuteFor"] isKindOfClass:[NSNumber class]])
				merged[@"useDefaultMuteFor"] = @NO;
			if ([changes[@"showPreview"] isKindOfClass:[NSNumber class]] &&
					![changes[@"useDefaultShowPreview"] isKindOfClass:[NSNumber class]])
				merged[@"useDefaultShowPreview"] = @NO;
			if ([changes[@"soundId"] isKindOfClass:[NSNumber class]] &&
					![changes[@"useDefaultSound"] isKindOfClass:[NSNumber class]])
				merged[@"useDefaultSound"] = @NO;
			if ([changes[@"disablePinnedMessageNotifications"] isKindOfClass:[NSNumber class]] &&
					![changes[@"useDefaultDisablePinnedMessageNotifications"] isKindOfClass:[NSNumber class]])
				merged[@"useDefaultDisablePinnedMessageNotifications"] = @NO;
			if ([changes[@"disableMentionNotifications"] isKindOfClass:[NSNumber class]] &&
					![changes[@"useDefaultDisableMentionNotifications"] isKindOfClass:[NSNumber class]])
				merged[@"useDefaultDisableMentionNotifications"] = @NO;
		}

		[weakSelf writeChat:chatId settings:merged];
		if (completion) completion(YES);
	}];
}

- (void)resetNotificationSettingsForChat:(int64_t)chatId {
	[self writeChat:chatId settings:@{
		@"useDefaultMuteFor"     : @YES,
		@"useDefaultSound"       : @YES,
		@"useDefaultShowPreview" : @YES,
		@"useDefaultDisablePinnedMessageNotifications" : @YES,
		@"useDefaultDisableMentionNotifications"       : @YES,
	}];
}

- (void)setChat:(int64_t)chatId defaultDisableNotification:(BOOL)silent {
	[self send:@{
		@"@type"   : @"toggleChatDefaultDisableNotification",
		@"chat_id" : @(chatId),
		@"default_disable_notification" : @(silent),
	}];
}

#pragma mark - forum topics

- (void)setChat:(int64_t)chatId
          topic:(int64_t)topicId
 muteForSeconds:(NSInteger)seconds {
	[self send:@{
		@"@type"          : @"setForumTopicNotificationSettings",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
		@"notification_settings" : [self chatNotificationPayloadFrom:@{
			@"useDefaultMuteFor" : @NO,
			@"muteFor"           : @(seconds),
		}],
	}];
}

- (void)resetNotificationSettingsForChat:(int64_t)chatId topic:(int64_t)topicId {
	[self send:@{
		@"@type"          : @"setForumTopicNotificationSettings",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
		@"notification_settings" : [self chatNotificationPayloadFrom:@{
			@"useDefaultMuteFor" : @YES,
		}],
	}];
}

#pragma mark - exceptions

- (void)exceptionChatIdsForScope:(NSString *)scope
                    compareSound:(BOOL)compareSound
                      completion:(void (^)(NSArray *))completion {
	NSMutableDictionary *query = [NSMutableDictionary dictionaryWithDictionary:@{
		@"@type"         : @"getChatNotificationSettingsExceptions",
		@"compare_sound" : @(compareSound),
	}];
	query[@"scope"] = scope.length ? (id)@{@"@type" : TGNotifScopeType(scope)} : (id)[NSNull null];

	[self request:query completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGNotifIsError(result)){
			completion([NSArray array]);
			return;
		}
		NSArray *ids = result[@"chat_ids"];
		completion([ids isKindOfClass:[NSArray class]] ? ids : [NSArray array]);
	}];
}

- (void)notificationExceptionsForScope:(NSString *)scope
                          compareSound:(BOOL)compareSound
                            completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self exceptionChatIdsForScope:scope compareSound:compareSound
						completion:^(NSArray *chatIds){
		if (!completion)
			return;
		if (!chatIds.count){
			completion([NSArray array]);
			return;
		}

		NSMutableArray *rows = [NSMutableArray array];
		__block NSUInteger pending = chatIds.count;
		for (NSNumber *chatId in chatIds){
			if (![chatId isKindOfClass:[NSNumber class]]){
				if (--pending == 0) completion(rows);
				continue;
			}
			[weakSelf request:@{@"@type" : @"getChat", @"chat_id" : chatId}
				   completion:^(NSDictionary *chat){
				if (!TGNotifIsError(chat)){
					NSDictionary *s = chat[@"notification_settings"];
					if (![s isKindOfClass:[NSDictionary class]])
						s = [NSDictionary dictionary];
					[rows addObject:@{
						@"id"          : chatId,
						@"title"       : TGNotifString(chat, @"title"),
						@"muted"       : @([TGNotifNumber(s, @"mute_for") integerValue] > 0),
						@"muteFor"     : TGNotifNumber(s, @"mute_for"),
						@"showPreview" : TGNotifBool(s, @"show_preview"),
					}];
				}
				if (--pending == 0)
					completion(rows);
			}];
		}
	}];
}

- (void)clearNotificationExceptionsForScope:(NSString *)scope
                                 completion:(void (^)(NSInteger))completion {
	__weak typeof(self) weakSelf = self;
	[self exceptionChatIdsForScope:scope compareSound:YES completion:^(NSArray *chatIds){
		NSInteger reset = 0;
		for (NSNumber *chatId in chatIds){
			if (![chatId isKindOfClass:[NSNumber class]])
				continue;
			[weakSelf resetNotificationSettingsForChat:chatId.longLongValue];
			reset++;
		}
		if (completion) completion(reset);
	}];
}

- (void)resetAllNotificationSettingsWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"resetAllNotificationSettings"}
	   completion:^(NSDictionary *result){
		if (completion) completion(!TGNotifIsError(result));
	}];
}

#pragma mark - reactions

- (void)setReactionNotificationsSource:(NSString *)source
                        pollVoteSource:(NSString *)pollVoteSource
                           showPreview:(BOOL)showPreview
                               soundId:(long long)soundId {
	[self send:@{
		@"@type" : @"setReactionNotificationSettings",
		@"notification_settings" : @{
			@"@type" : @"reactionNotificationSettings",
			@"message_reaction_source" : @{@"@type" : TGNotifReactionSource(source)},
			@"story_reaction_source"   : @{@"@type" : @"reactionNotificationSourceNone"},
			@"poll_vote_source"        : @{@"@type" : TGNotifReactionSource(pollVoteSource)},
			@"sound_id"                : @(soundId),
			@"show_preview"            : @(showPreview),
		},
	}];
}

#pragma mark - sounds

static NSDictionary *TGNotifSoundFrom(NSDictionary *sound) {
	NSDictionary *file = sound[@"sound"];
	NSNumber *fileId = [file isKindOfClass:[NSDictionary class]] ? file[@"id"] : nil;
	return @{
		@"id"       : TGNotifNumber(sound, @"id"),
		@"title"    : TGNotifString(sound, @"title"),
		@"duration" : TGNotifNumber(sound, @"duration"),
		@"date"     : TGNotifNumber(sound, @"date"),
		@"fileId"   : [fileId isKindOfClass:[NSNumber class]] ? fileId : @(0),
	};
}

- (void)savedNotificationSoundsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getSavedNotificationSounds"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSMutableArray *out = [NSMutableArray array];
		NSArray *sounds = result[@"notification_sounds"];
		if ([sounds isKindOfClass:[NSArray class]]){
			for (NSDictionary *sound in sounds)
				if ([sound isKindOfClass:[NSDictionary class]])
					[out addObject:TGNotifSoundFrom(sound)];
		}
		completion(out);
	}];
}

- (void)addSavedNotificationSoundAtPath:(NSString *)path
                             completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type" : @"addSavedNotificationSound",
		@"sound" : @{@"@type" : @"inputFileLocal", @"path" : path ?: @""},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGNotifIsError(result) ? nil : TGNotifSoundFrom(result));
	}];
}

- (void)removeSavedNotificationSound:(long long)soundId {
	[self send:@{
		@"@type" : @"removeSavedNotificationSound",
		@"notification_sound_id" : @(soundId),
	}];
}

#pragma mark - archive settings

- (void)archiveChatListSettingsWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getArchiveChatListSettings"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGNotifIsError(result)){
			completion(nil);
			return;
		}
		completion(@{
			@"archiveAndMuteNewChatsFromUnknownUsers" :
					TGNotifBool(result, @"archive_and_mute_new_chats_from_unknown_users"),
			@"keepUnmutedChatsArchived" :
					TGNotifBool(result, @"keep_unmuted_chats_archived"),
			@"keepChatsFromFoldersArchived" :
					TGNotifBool(result, @"keep_chats_from_folders_archived"),
		});
	}];
}

- (void)updateArchiveChatListSettings:(NSDictionary *)changes
                           completion:(void (^)(BOOL))completion {
	__weak typeof(self) weakSelf = self;
	[self archiveChatListSettingsWithCompletion:^(NSDictionary *current){
		if (!current){
			if (completion) completion(NO);
			return;
		}
		NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:current];
		for (NSString *key in [merged allKeys])
			merged[key] = TGNotifPick(changes, current, key);

		[weakSelf send:@{
			@"@type" : @"setArchiveChatListSettings",
			@"settings" : @{
				@"@type" : @"archiveChatListSettings",
				@"archive_and_mute_new_chats_from_unknown_users" :
						merged[@"archiveAndMuteNewChatsFromUnknownUsers"],
				@"keep_unmuted_chats_archived" :
						merged[@"keepUnmutedChatsArchived"],
				@"keep_chats_from_folders_archived" :
						merged[@"keepChatsFromFoldersArchived"],
			},
		}];
		if (completion) completion(YES);
	}];
}

#pragma mark - local alerts

- (void)removeNotification:(NSInteger)notificationId inGroup:(NSInteger)groupId {
	[self send:@{
		@"@type" : @"removeNotification",
		@"notification_group_id" : @(groupId),
		@"notification_id"       : @(notificationId),
	}];
}

- (void)removeNotificationGroup:(NSInteger)groupId
             upToNotificationId:(NSInteger)maxNotificationId {
	NSInteger max = maxNotificationId;
	if (max > INT32_MAX || max < 0)
		max = INT32_MAX;
	[self send:@{
		@"@type" : @"removeNotificationGroup",
		@"notification_group_id" : @(groupId),
		@"max_notification_id"   : @(max),
	}];
}

- (NSString *)previewTextForPushContent:(NSDictionary *)content {
	if (![content isKindOfClass:[NSDictionary class]])
		return @"";
	NSString *type = content[@"@type"];
	if (![type isKindOfClass:[NSString class]])
		return @"";

	if ([type isEqualToString:@"pushMessageContentText"])
		return TGNotifString(content, @"text");
	if ([type isEqualToString:@"pushMessageContentPhoto"]){
		NSString *caption = TGNotifString(content, @"caption");
		if ([content[@"is_secret"] boolValue])
			return @"Self-destructing photo";
		return caption.length ? caption : @"Photo";
	}
	if ([type isEqualToString:@"pushMessageContentVideo"]){
		NSString *caption = TGNotifString(content, @"caption");
		if ([content[@"is_secret"] boolValue])
			return @"Self-destructing video";
		return caption.length ? caption : @"Video";
	}
	if ([type isEqualToString:@"pushMessageContentAnimation"]){
		NSString *caption = TGNotifString(content, @"caption");
		return caption.length ? caption : @"GIF";
	}
	if ([type isEqualToString:@"pushMessageContentVoiceNote"])
		return @"Voice message";
	if ([type isEqualToString:@"pushMessageContentVideoNote"])
		return @"Video message";
	if ([type isEqualToString:@"pushMessageContentAudio"])
		return @"Audio";
	if ([type isEqualToString:@"pushMessageContentDocument"])
		return @"File";
	if ([type isEqualToString:@"pushMessageContentSticker"]){
		NSString *emoji = TGNotifString(content, @"emoji");
		return emoji.length ? [emoji stringByAppendingString:@" Sticker"] : @"Sticker";
	}
	if ([type isEqualToString:@"pushMessageContentContact"]){
		NSString *name = TGNotifString(content, @"name");
		return name.length ? [@"Contact: " stringByAppendingString:name] : @"Contact";
	}
	if ([type isEqualToString:@"pushMessageContentContactRegistered"])
		return @"joined Telegram";
	if ([type isEqualToString:@"pushMessageContentLocation"])
		return [content[@"is_live"] boolValue] ? @"Live location" : @"Location";
	if ([type isEqualToString:@"pushMessageContentPoll"]){
		NSString *question = TGNotifString(content, @"question");
		NSString *kind = [content[@"is_regular"] boolValue] ? @"Poll" : @"Quiz";
		return question.length ? [NSString stringWithFormat:@"%@: %@", kind, question] : kind;
	}
	if ([type isEqualToString:@"pushMessageContentGame"]){
		NSString *title = TGNotifString(content, @"title");
		return title.length ? [@"Game: " stringByAppendingString:title] : @"Game";
	}
	if ([type isEqualToString:@"pushMessageContentGameScore"])
		return @"scored in a game";
	if ([type isEqualToString:@"pushMessageContentInvoice"]){
		NSString *price = TGNotifString(content, @"price");
		return price.length ? [@"Invoice: " stringByAppendingString:price] : @"Invoice";
	}
	if ([type isEqualToString:@"pushMessageContentScreenshotTaken"])
		return @"took a screenshot";
	if ([type isEqualToString:@"pushMessageContentChatAddMembers"]){
		NSString *name = TGNotifString(content, @"member_name");
		if ([content[@"is_returned"] boolValue])
			return @"joined the group";
		return name.length ? [@"invited " stringByAppendingString:name] : @"invited a member";
	}
	if ([type isEqualToString:@"pushMessageContentChatDeleteMember"]){
		NSString *name = TGNotifString(content, @"member_name");
		if ([content[@"is_left"] boolValue])
			return @"left the group";
		return name.length ? [@"removed " stringByAppendingString:name] : @"removed a member";
	}
	if ([type isEqualToString:@"pushMessageContentChatChangeTitle"]){
		NSString *title = TGNotifString(content, @"title");
		return title.length ? [@"changed the group name to " stringByAppendingString:title]
							: @"changed the group name";
	}
	if ([type isEqualToString:@"pushMessageContentChatChangePhoto"])
		return @"changed the group photo";
	if ([type isEqualToString:@"pushMessageContentChatJoinByLink"])
		return @"joined by invite link";
	if ([type isEqualToString:@"pushMessageContentChatJoinByRequest"])
		return @"was accepted into the group";
	if ([type isEqualToString:@"pushMessageContentBasicGroupChatCreate"])
		return @"created the group";
	if ([type isEqualToString:@"pushMessageContentVideoChatStarted"])
		return @"started a voice chat";
	if ([type isEqualToString:@"pushMessageContentVideoChatEnded"])
		return @"ended the voice chat";
	if ([type isEqualToString:@"pushMessageContentMessageForwards"]){
		NSInteger count = [TGNotifNumber(content, @"total_count") integerValue];
		return [NSString stringWithFormat:@"%d forwarded messages", (int)count];
	}
	if ([type isEqualToString:@"pushMessageContentMediaAlbum"]){
		NSInteger count = [TGNotifNumber(content, @"total_count") integerValue];
		NSString *kind = @"files";
		if ([content[@"has_photos"] boolValue])         kind = @"photos";
		else if ([content[@"has_videos"] boolValue])    kind = @"videos";
		else if ([content[@"has_audios"] boolValue])    kind = @"audio files";
		else if ([content[@"has_documents"] boolValue]) kind = @"files";
		return [NSString stringWithFormat:@"%d %@", (int)count, kind];
	}
	if ([type isEqualToString:@"pushMessageContentHidden"])
		return @"New message";
	return @"New message";
}

- (NSString *)previewTextForMessageContent:(NSDictionary *)content {
	if (![content isKindOfClass:[NSDictionary class]])
		return @"";
	NSString *type = content[@"@type"];
	if (![type isKindOfClass:[NSString class]])
		return @"";

	if ([type isEqualToString:@"messageText"]){
		NSDictionary *text = content[@"text"];
		return [text isKindOfClass:[NSDictionary class]] ? TGNotifString(text, @"text") : @"";
	}

	NSDictionary *caption = content[@"caption"];
	NSString *captionText = [caption isKindOfClass:[NSDictionary class]]
			? TGNotifString(caption, @"text") : @"";
	if (captionText.length)
		return captionText;

	if ([type isEqualToString:@"messagePhoto"])
		return [content[@"is_secret"] boolValue] ? @"Self-destructing photo" : @"Photo";
	if ([type isEqualToString:@"messageVideo"])
		return [content[@"is_secret"] boolValue] ? @"Self-destructing video" : @"Video";
	if ([type isEqualToString:@"messageAnimation"])
		return @"GIF";
	if ([type isEqualToString:@"messageVoiceNote"])
		return @"Voice message";
	if ([type isEqualToString:@"messageVideoNote"])
		return @"Video message";
	if ([type isEqualToString:@"messageSticker"]){
		NSDictionary *sticker = content[@"sticker"];
		NSString *emoji = [sticker isKindOfClass:[NSDictionary class]]
				? TGNotifString(sticker, @"emoji") : @"";
		return emoji.length ? [emoji stringByAppendingString:@" Sticker"] : @"Sticker";
	}
	if ([type isEqualToString:@"messageAnimatedEmoji"]){
		NSString *emoji = TGNotifString(content, @"emoji");
		return emoji.length ? emoji : @"Emoji";
	}
	if ([type isEqualToString:@"messageDocument"]){
		NSDictionary *document = content[@"document"];
		NSString *name = [document isKindOfClass:[NSDictionary class]]
				? TGNotifString(document, @"file_name") : @"";
		return name.length ? name : @"File";
	}
	if ([type isEqualToString:@"messageAudio"]){
		NSDictionary *audio = content[@"audio"];
		NSString *title = [audio isKindOfClass:[NSDictionary class]]
				? TGNotifString(audio, @"title") : @"";
		return title.length ? title : @"Audio";
	}
	if ([type isEqualToString:@"messageContact"])
		return @"Contact";
	if ([type isEqualToString:@"messageVenue"])
		return @"Venue";
	if ([type isEqualToString:@"messageLocation"])
		return [content[@"live_period"] integerValue] > 0 ? @"Live location" : @"Location";
	if ([type isEqualToString:@"messagePoll"]){
		NSDictionary *poll = content[@"poll"];
		NSDictionary *question = [poll isKindOfClass:[NSDictionary class]]
				? poll[@"question"] : nil;
		NSString *text = [question isKindOfClass:[NSDictionary class]]
				? TGNotifString(question, @"text") : @"";
		return text.length ? [@"Poll: " stringByAppendingString:text] : @"Poll";
	}
	if ([type isEqualToString:@"messageGame"])
		return @"Game";
	if ([type isEqualToString:@"messageInvoice"])
		return @"Invoice";
	if ([type isEqualToString:@"messageCall"])
		return @"Call";
	if ([type isEqualToString:@"messageScreenshotTaken"])
		return @"took a screenshot";
	if ([type isEqualToString:@"messageChatAddMembers"])
		return @"added a member";
	if ([type isEqualToString:@"messageChatDeleteMember"])
		return @"left the group";
	if ([type isEqualToString:@"messageChatJoinByLink"] ||
			[type isEqualToString:@"messageChatJoinByRequest"])
		return @"joined the group";
	if ([type isEqualToString:@"messageChatChangeTitle"])
		return @"renamed the group";
	if ([type isEqualToString:@"messageChatChangePhoto"])
		return @"changed the group photo";
	if ([type isEqualToString:@"messagePinMessage"])
		return @"pinned a message";
	return @"New message";
}

- (NSString *)titleForChatId:(int64_t)chatId {
	if (!chatId)
		return nil;
	id title = self.chatsById[@(chatId)][@"title"];
	if ([title isKindOfClass:[NSString class]] && [title length])
		return title;
	return [self nameForUserId:chatId];
}

- (NSDictionary *)alertForNotification:(NSDictionary *)notification
                              chatName:(NSString *)chatName {
	if (![notification isKindOfClass:[NSDictionary class]])
		return nil;
	NSDictionary *type = notification[@"type"];
	if (![type isKindOfClass:[NSDictionary class]])
		return nil;

	NSString *typeName = type[@"@type"];
	NSString *title = chatName.length ? chatName : @"Telegram";
	NSString *body = nil;
	int64_t chatId = 0;

	if ([typeName isEqualToString:@"notificationTypeNewPushMessage"]){
		NSString *sender = TGNotifString(type, @"sender_name");
		if (sender.length && !chatName.length)
			title = sender;
		body = [self previewTextForPushContent:type[@"content"]];
		if (sender.length && chatName.length && ![sender isEqualToString:chatName])
			body = [NSString stringWithFormat:@"%@: %@", sender, body];
	} else if ([typeName isEqualToString:@"notificationTypeNewMessage"]){
		NSDictionary *message = type[@"message"];
		if ([message isKindOfClass:[NSDictionary class]]){
			chatId = [message[@"chat_id"] longLongValue];
			int64_t senderId = 0;
			NSDictionary *sender = message[@"sender_id"];
			if ([sender isKindOfClass:[NSDictionary class]])
				senderId = [sender[@"user_id"] longLongValue];
			NSString *name = senderId ? [self nameForUserId:senderId] : nil;
			if (![type[@"show_preview"] boolValue]){
				title = @"Telegram";
				body = @"New message";
			} else {
				NSString *preview = [self previewTextForMessageContent:message[@"content"]];
				body = preview.length ? preview : @"New message";
				if (name.length && chatName.length && ![name isEqualToString:chatName])
					body = [NSString stringWithFormat:@"%@: %@", name, body];
				else if (name.length && !chatName.length)
					title = name;
			}
		}
	} else if ([typeName isEqualToString:@"notificationTypeNewSecretChat"]){
		body = @"New secret chat";
	} else if ([typeName isEqualToString:@"notificationTypeNewCall"]){
		body = @"Incoming call";
	}

	if (!body.length)
		return nil;
	return @{@"title" : title, @"body" : body, @"chatId" : @(chatId)};
}

@end

// vim:ft=objc

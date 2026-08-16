#import "TGClient+Private.h"
#import "TGClient+Stories.h"
#import "TGClient+Storage.h"

static BOOL TGStoryIsError(NSDictionary *result) {
	if (![result isKindOfClass:NSDictionary.class])
		return YES;
	id type = result[@"@type"];
	return [type isKindOfClass:NSString.class] && [type isEqualToString:@"error"];
}

static NSArray *TGStoryArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSDictionary *TGStoryDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSString *TGStoryString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSNumber *TGStoryNumber(id value) {
	return [value isKindOfClass:NSNumber.class] ? value : nil;
}

static NSArray *TGStoryIdList(NSArray *ids) {
	NSMutableArray *out = [NSMutableArray array];
	for (id one in TGStoryArray(ids)){
		NSNumber *n = TGStoryNumber(one);
		if (n)
			[out addObject:n];
	}
	return out;
}

static int64_t TGStorySenderId(NSDictionary *sender) {
	NSDictionary *s = TGStoryDict(sender);
	if (!s)
		return 0;
	if ([s[@"@type"] isEqualToString:@"messageSenderChat"])
		return [TGStoryNumber(s[@"chat_id"]) longLongValue];
	return [TGStoryNumber(s[@"user_id"]) longLongValue];
}

static NSString *TGStorySenderName(TGClient *client, int64_t senderId) {
	if (!client || senderId == 0)
		return @"";
	if (senderId > 0)
		return [client nameForUserId:senderId] ?: @"";
	NSDictionary *known = TGStoryDict(client.chatsById[@(senderId)]);
	NSString *title = TGStoryString(known[@"title"]);
	if (title.length)
		return title;
	for (NSDictionary *c in client.chats){
		if ([TGStoryDict(c)[@"id"] longLongValue] == senderId)
			return TGStoryString(c[@"title"]);
	}
	for (NSDictionary *c in client.archivedChats){
		if ([TGStoryDict(c)[@"id"] longLongValue] == senderId)
			return TGStoryString(c[@"title"]);
	}
	return @"";
}

static NSDictionary *TGStoryPrivacyRules(NSString *privacy, NSArray *userIds) {
	NSArray *ids = TGStoryIdList(userIds);
	if ([privacy isEqualToString:@"closeFriends"])
		return @{@"@type" : @"storyPrivacySettingsCloseFriends"};
	if ([privacy isEqualToString:@"selected"])
		return @{@"@type" : @"storyPrivacySettingsSelectedUsers", @"user_ids" : ids};
	if ([privacy isEqualToString:@"contacts"])
		return @{@"@type" : @"storyPrivacySettingsContacts", @"except_user_ids" : ids};
	return @{@"@type" : @"storyPrivacySettingsEveryone", @"except_user_ids" : ids};
}

static NSString *TGStoryPrivacyName(NSDictionary *settings) {
	NSString *t = TGStoryDict(settings)[@"@type"];
	if ([t isEqualToString:@"storyPrivacySettingsCloseFriends"])
		return @"closeFriends";
	if ([t isEqualToString:@"storyPrivacySettingsSelectedUsers"])
		return @"selected";
	if ([t isEqualToString:@"storyPrivacySettingsContacts"])
		return @"contacts";
	if ([t isEqualToString:@"storyPrivacySettingsEveryone"])
		return @"everyone";
	return @"";
}

NSString *const TGStoryUpdateNotification = @"TGStoryUpdateNotification";

static NSString *TGStoryLimitReason(NSString *type) {
	if ([type isEqualToString:@"canPostStoryResultPremiumNeeded"])
		return @"Posting more stories requires Telegram Premium.";
	if ([type isEqualToString:@"canPostStoryResultBoostNeeded"])
		return @"This channel needs more boosts before it can post stories.";
	if ([type isEqualToString:@"canPostStoryResultActiveStoryLimitExceeded"])
		return @"Too many active stories. Delete one first.";
	if ([type isEqualToString:@"canPostStoryResultWeeklyLimitExceeded"])
		return @"The weekly story limit has been reached.";
	if ([type isEqualToString:@"canPostStoryResultMonthlyLimitExceeded"])
		return @"The monthly story limit has been reached.";
	if ([type isEqualToString:@"canPostStoryResultLiveStoryIsActive"])
		return @"A live story is still running.";
	return @"Stories cannot be posted right now.";
}

static NSString *TGStoryErrorText(NSDictionary *error) {
	NSDictionary *e = TGStoryDict(error);
	NSString *message = TGStoryString(e[@"message"]);
	if (!message.length)
		return @"The story could not be posted.";

	if ([message hasPrefix:@"FLOOD_WAIT_"]){
		NSInteger seconds = [[message substringFromIndex:11] integerValue];
		if (seconds > 3600)
			return [NSString stringWithFormat:@"Too many attempts. Try again in %ld hours.",
					(long)(seconds / 3600)];
		if (seconds > 60)
			return [NSString stringWithFormat:@"Too many attempts. Try again in %ld minutes.",
					(long)(seconds / 60)];
		return [NSString stringWithFormat:@"Too many attempts. Try again in %ld seconds.",
				(long)seconds];
	}
	if ([message hasPrefix:@"STORY_SEND_FLOOD_WEEKLY_"])
		return @"The weekly story limit has been reached.";
	if ([message hasPrefix:@"STORY_SEND_FLOOD_MONTHLY_"])
		return @"The monthly story limit has been reached.";
	if ([message isEqualToString:@"STORIES_TOO_MUCH"])
		return @"Too many active stories. Delete one first.";
	if ([message isEqualToString:@"PREMIUM_ACCOUNT_REQUIRED"])
		return @"This needs Telegram Premium.";
	if ([message isEqualToString:@"STORY_PERIOD_INVALID"])
		return @"That expiry needs Telegram Premium. Post for 24 hours instead.";
	if ([message isEqualToString:@"BOOSTS_REQUIRED"])
		return @"This channel needs more boosts before it can post stories.";
	if ([message isEqualToString:@"CHAT_ADMIN_REQUIRED"] ||
		[message isEqualToString:@"CHAT_WRITE_FORBIDDEN"])
		return @"You are not allowed to post stories here.";
	if ([message isEqualToString:@"MEDIA_EMPTY"] ||
		[message isEqualToString:@"PHOTO_INVALID_DIMENSIONS"] ||
		[message isEqualToString:@"PHOTO_EXT_INVALID"])
		return @"Telegram rejected that picture.";
	if ([message isEqualToString:@"VIDEO_FILE_INVALID"] ||
		[message hasPrefix:@"VIDEO_"])
		return @"Telegram rejected that video. Stories need a short MP4.";
	if ([message isEqualToString:@"Request timeout"] ||
		[message isEqualToString:@"Request aborted"])
		return @"The connection dropped before the story went out.";
	return message;
}

static NSString *TGStoryReactionEmoji(NSDictionary *type) {
	NSDictionary *t = TGStoryDict(type);
	if (!t)
		return @"";
	return TGStoryString(t[@"emoji"]);
}

static NSNumber *TGStoryLargestPhotoId(NSDictionary *photo) {
	NSArray *sizes = TGStoryArray(TGStoryDict(photo)[@"sizes"]);
	if (!sizes.count)
		return nil;
	NSDictionary *biggest = TGStoryDict([sizes lastObject]);
	return TGStoryNumber(TGStoryDict(biggest[@"photo"])[@"id"]);
}

static NSDictionary *TGStoryAreaFlattened(NSDictionary *raw) {
	NSDictionary *area = TGStoryDict(raw);
	if (!area)
		return nil;
	NSDictionary *position = TGStoryDict(area[@"position"]);
	NSDictionary *type = TGStoryDict(area[@"type"]);
	NSString *rawType = TGStoryString(type[@"@type"]);

	NSString *kind = @"unsupported";
	NSString *url = @"";
	NSString *emoji = @"";
	NSString *title = @"";
	NSNumber *latitude = nil;
	NSNumber *longitude = nil;
	NSNumber *chatId = nil;
	NSNumber *messageId = nil;

	if ([rawType isEqualToString:@"storyAreaTypeLocation"]){
		kind = @"location";
		NSDictionary *location = TGStoryDict(type[@"location"]);
		latitude = TGStoryNumber(location[@"latitude"]);
		longitude = TGStoryNumber(location[@"longitude"]);
		title = TGStoryString(TGStoryDict(type[@"address"])[@"city"]);
	} else if ([rawType isEqualToString:@"storyAreaTypeVenue"]){
		kind = @"venue";
		NSDictionary *venue = TGStoryDict(type[@"venue"]);
		NSDictionary *location = TGStoryDict(venue[@"location"]);
		latitude = TGStoryNumber(location[@"latitude"]);
		longitude = TGStoryNumber(location[@"longitude"]);
		title = TGStoryString(venue[@"title"]);
	} else if ([rawType isEqualToString:@"storyAreaTypeSuggestedReaction"]){
		kind = @"reaction";
		emoji = TGStoryReactionEmoji(type[@"reaction_type"]);
	} else if ([rawType isEqualToString:@"storyAreaTypeMessage"]){
		kind = @"message";
		chatId = TGStoryNumber(type[@"chat_id"]);
		messageId = TGStoryNumber(type[@"message_id"]);
	} else if ([rawType isEqualToString:@"storyAreaTypeLink"]){
		kind = @"link";
		url = TGStoryString(type[@"url"]);
	} else if ([rawType isEqualToString:@"storyAreaTypeWeather"]){
		kind = @"weather";
		emoji = TGStoryString(type[@"emoji"]);
		title = [NSString stringWithFormat:@"%.0f°",
				 [TGStoryNumber(type[@"temperature"]) doubleValue]];
	} else if ([rawType isEqualToString:@"storyAreaTypeUpgradedGift"]){
		kind = @"gift";
		title = TGStoryString(type[@"gift_name"]);
	}

	return @{
		@"kind"         : kind,
		@"x"            : TGStoryNumber(position[@"x_percentage"]) ?: @(0),
		@"y"            : TGStoryNumber(position[@"y_percentage"]) ?: @(0),
		@"width"        : TGStoryNumber(position[@"width_percentage"]) ?: @(0),
		@"height"       : TGStoryNumber(position[@"height_percentage"]) ?: @(0),
		@"rotation"     : TGStoryNumber(position[@"rotation_angle"]) ?: @(0),
		@"cornerRadius" : TGStoryNumber(position[@"corner_radius_percentage"]) ?: @(0),
		@"url"          : url,
		@"emoji"        : emoji,
		@"title"        : title,
		@"latitude"     : latitude ?: @(0),
		@"longitude"    : longitude ?: @(0),
		@"chatId"       : chatId ?: @(0),
		@"messageId"    : messageId ?: @(0),
	};
}

static NSDictionary *TGStoryFlattened(NSDictionary *raw) {
	NSDictionary *story = TGStoryDict(raw);
	if (!story || !TGStoryNumber(story[@"id"]))
		return nil;

	NSDictionary *content = TGStoryDict(story[@"content"]);
	NSString *contentType = TGStoryString(content[@"@type"]);
	NSString *kind = @"unsupported";
	NSNumber *photoId = nil;
	NSNumber *videoId = nil;
	NSNumber *duration = @(0);
	NSNumber *width = @(0);
	NSNumber *height = @(0);

	if ([contentType isEqualToString:@"storyContentPhoto"]){
		kind = @"photo";
		photoId = TGStoryLargestPhotoId(content[@"photo"]);
	} else if ([contentType isEqualToString:@"storyContentVideo"]){
		kind = @"video";
		NSDictionary *video = TGStoryDict(content[@"alternative_video"]) ?:
							  TGStoryDict(content[@"video"]);
		videoId = TGStoryNumber(TGStoryDict(video[@"video"])[@"id"]);
		duration = TGStoryNumber(video[@"duration"]) ?: @(0);
		width = TGStoryNumber(video[@"width"]) ?: @(0);
		height = TGStoryNumber(video[@"height"]) ?: @(0);
		NSDictionary *thumbnail = TGStoryDict(video[@"thumbnail"]);
		photoId = TGStoryNumber(TGStoryDict(thumbnail[@"file"])[@"id"]);
	} else if ([contentType isEqualToString:@"storyContentLive"]){
		kind = @"live";
	}

	NSDictionary *info = TGStoryDict(story[@"interaction_info"]);
	NSDictionary *repost = TGStoryDict(story[@"repost_info"]);
	NSDictionary *origin = TGStoryDict(repost[@"origin"]);
	NSString *repostFrom = @"";
	if ([origin[@"@type"] isEqualToString:@"storyOriginHiddenUser"])
		repostFrom = TGStoryString(origin[@"poster_name"]);

	NSMutableArray *areas = [NSMutableArray array];
	for (NSDictionary *area in TGStoryArray(story[@"areas"])){
		NSDictionary *flat = TGStoryAreaFlattened(area);
		if (flat)
			[areas addObject:flat];
	}

	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	out[@"id"] = TGStoryNumber(story[@"id"]) ?: @(0);
	out[@"chatId"] = TGStoryNumber(story[@"poster_chat_id"]) ?: @(0);
	out[@"senderId"] = @(TGStorySenderId(story[@"poster_id"]));
	out[@"date"] = TGStoryNumber(story[@"date"]) ?: @(0);
	out[@"caption"] = TGStoryString(TGStoryDict(story[@"caption"])[@"text"]);
	out[@"kind"] = kind;
	if (photoId)
		out[@"photoId"] = photoId;
	if (videoId)
		out[@"videoId"] = videoId;
	out[@"duration"] = duration;
	out[@"width"] = width;
	out[@"height"] = height;
	out[@"views"] = TGStoryNumber(info[@"view_count"]) ?: @(0);
	out[@"forwards"] = TGStoryNumber(info[@"forward_count"]) ?: @(0);
	out[@"reactions"] = TGStoryNumber(info[@"reaction_count"]) ?: @(0);
	out[@"myReaction"] = TGStoryReactionEmoji(story[@"chosen_reaction_type"]);
	out[@"privacy"] = TGStoryPrivacyName(story[@"privacy_settings"]);
	out[@"isEdited"] = @([story[@"is_edited"] boolValue]);
	out[@"isBeingPosted"] = @([story[@"is_being_posted"] boolValue]);
	out[@"isBeingEdited"] = @([story[@"is_being_edited"] boolValue]);
	out[@"onProfile"] = @([story[@"is_posted_to_chat_page"] boolValue]);
	out[@"canDelete"] = @([story[@"can_be_deleted"] boolValue]);
	out[@"canEdit"] = @([story[@"can_be_edited"] boolValue]);
	out[@"canForward"] = @([story[@"can_be_forwarded"] boolValue]);
	out[@"canReply"] = @([story[@"can_be_replied"] boolValue]);
	out[@"canSetPrivacy"] = @([story[@"can_set_privacy_settings"] boolValue]);
	out[@"canToggleProfile"] = @([story[@"can_toggle_is_posted_to_chat_page"] boolValue]);
	out[@"canGetViewers"] = @([story[@"can_get_interactions"] boolValue]);
	out[@"expiredViewers"] = @([story[@"has_expired_viewers"] boolValue]);
	out[@"repostFrom"] = repostFrom;
	out[@"albumIds"] = TGStoryIdList(story[@"album_ids"]);
	out[@"areas"] = areas;
	return out;
}

static NSArray *TGStoriesFlattened(NSArray *list) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *one in TGStoryArray(list)){
		@autoreleasepool {
			NSDictionary *flat = TGStoryFlattened(one);
			if (flat)
				[out addObject:flat];
		}
	}
	return out;
}

static NSDictionary *TGStoryAlbumFlattened(NSDictionary *raw) {
	NSDictionary *album = TGStoryDict(raw);
	if (!album || !TGStoryNumber(album[@"id"]))
		return nil;
	return @{
		@"id"   : TGStoryNumber(album[@"id"]),
		@"name" : TGStoryString(album[@"name"]),
	};
}

static NSString *TGStoryNetworkType(NSString *type) {
	NSString *lower = [(type ?: @"") lowercaseString];
	if ([lower isEqualToString:@"wifi"])
		return @"networkTypeWiFi";
	if ([lower isEqualToString:@"roaming"] || [lower isEqualToString:@"mobileroaming"])
		return @"networkTypeMobileRoaming";
	if ([lower isEqualToString:@"other"])
		return @"networkTypeOther";
	if ([lower isEqualToString:@"none"])
		return @"networkTypeNone";
	return @"networkTypeMobile";
}

static NSDictionary *TGStoryAutoDownloadFromMirror(NSDictionary *values) {
	NSDictionary *source = TGStoryDict(values);
	if (!source)
		return nil;
	return @{
		@"@type"                    : @"autoDownloadSettings",
		@"is_auto_download_enabled" : source[@"enabled"] ?: @NO,
		@"max_photo_file_size"      : source[@"maxPhotoSize"] ?: @(1024 * 1024),
		@"max_video_file_size"      : source[@"maxVideoSize"] ?: @(0),
		@"max_other_file_size"      : source[@"maxOtherSize"] ?: @(0),
		@"video_upload_bitrate"     : source[@"videoUploadBitrate"] ?: @(0),
		@"preload_large_videos"     : source[@"preloadLargeVideos"] ?: @NO,
		@"preload_next_audio"       : source[@"preloadNextAudio"] ?: @NO,
		@"preload_stories"          : @NO,
		@"use_less_data_for_calls"  : source[@"useLessDataForCalls"] ?: @YES,
	};
}

@interface TGStoryPostWatcher : NSObject

+ (void)watchChat:(int64_t)chatId
          storyId:(NSInteger)storyId
             path:(NSString *)path
         progress:(void (^)(float fraction))progress
       completion:(void (^)(NSDictionary *story, NSString *error))completion;

@end

static NSMutableArray *TGStoryPostWatchers(void) {
	static NSMutableArray *watchers = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ watchers = [[NSMutableArray alloc] init]; });
	return watchers;
}

@implementation TGStoryPostWatcher {
	int64_t _chatId;
	NSInteger _storyId;
	NSString *_path;
	void (^_progress)(float);
	void (^_completion)(NSDictionary *, NSString *);
	NSTimer *_deadline;
	BOOL _finished;
}

+ (void)watchChat:(int64_t)chatId
          storyId:(NSInteger)storyId
             path:(NSString *)path
         progress:(void (^)(float))progress
       completion:(void (^)(NSDictionary *, NSString *))completion {
	TGStoryPostWatcher *watcher = [[TGStoryPostWatcher alloc] init];
	watcher->_chatId = chatId;
	watcher->_storyId = storyId;
	watcher->_path = [path copy];
	watcher->_progress = [progress copy];
	watcher->_completion = [completion copy];
	[TGStoryPostWatchers() addObject:watcher];
	[[NSNotificationCenter defaultCenter] addObserver:watcher
	                                         selector:@selector(handleStoryUpdate:)
	                                             name:TGStoryUpdateNotification
	                                           object:nil];
	[watcher armDeadline];
}

- (void)dealloc {
	[_deadline invalidate];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)armDeadline {
	[_deadline invalidate];
	_deadline = [NSTimer scheduledTimerWithTimeInterval:180.0
	                                             target:self
	                                           selector:@selector(deadlinePassed)
	                                           userInfo:nil
	                                            repeats:NO];
}

- (void)deadlinePassed {
	_deadline = nil;
	[self finishWithStory:nil
	                error:@"The upload stopped making progress. Check the connection and try again."];
}

- (void)finishWithStory:(NSDictionary *)story error:(NSString *)error {
	if (_finished)
		return;
	_finished = YES;
	[_deadline invalidate];
	_deadline = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	void (^completion)(NSDictionary *, NSString *) = _completion;
	_completion = nil;
	_progress = nil;
	if (completion)
		completion(story, error);
	[TGStoryPostWatchers() removeObject:self];
}

- (void)applyFileUpdate:(NSDictionary *)file {
	if (!_progress || !_path.length)
		return;
	NSString *local = TGStoryString(TGStoryDict(file[@"local"])[@"path"]);
	if (![local isEqualToString:_path] &&
		![local.lastPathComponent isEqualToString:_path.lastPathComponent])
		return;

	NSDictionary *remote = TGStoryDict(file[@"remote"]);
	double total = [TGStoryNumber(file[@"expected_size"]) doubleValue];
	if (total <= 0)
		total = [TGStoryNumber(file[@"size"]) doubleValue];
	double sent = [TGStoryNumber(remote[@"uploaded_size"]) doubleValue];

	float fraction = 0.0f;
	if ([remote[@"is_uploading_completed"] boolValue])
		fraction = 1.0f;
	else if (total > 0)
		fraction = (float)(sent / total);
	if (fraction < 0.0f)
		fraction = 0.0f;
	if (fraction > 1.0f)
		fraction = 1.0f;

	[self armDeadline];
	_progress(fraction);
}

- (void)handleStoryUpdate:(NSNotification *)note {
	NSDictionary *update = TGStoryDict(note.object);
	NSString *type = TGStoryString(update[@"@type"]);

	if ([type isEqualToString:@"updateFile"]){
		[self applyFileUpdate:TGStoryDict(update[@"file"])];
		return;
	}

	if ([type isEqualToString:@"updateStoryPostSucceeded"]){
		if ([TGStoryNumber(update[@"old_story_id"]) integerValue] != _storyId)
			return;
		if (_progress)
			_progress(1.0f);
		[self finishWithStory:TGStoryFlattened(update[@"story"]) error:nil];
		return;
	}

	if ([type isEqualToString:@"updateStoryPostFailed"]){
		NSDictionary *story = TGStoryDict(update[@"story"]);
		if ([TGStoryNumber(story[@"id"]) integerValue] != _storyId)
			return;
		NSString *text = TGStoryErrorText(update[@"error"]);
		NSString *typed = TGStoryString(TGStoryDict(update[@"error_type"])[@"@type"]);
		if (typed.length && ![typed isEqualToString:@"canPostStoryResultOk"])
			text = TGStoryLimitReason(typed);
		[self finishWithStory:nil error:text];
		return;
	}

	if ([type isEqualToString:@"updateStoryDeleted"]){
		if ([TGStoryNumber(update[@"story_id"]) integerValue] != _storyId ||
			[TGStoryNumber(update[@"story_poster_chat_id"]) longLongValue] != _chatId)
			return;
		[self finishWithStory:nil error:@"Posting the story was cancelled."];
		return;
	}

	if ([type isEqualToString:@"updateStory"]){
		NSDictionary *story = TGStoryDict(update[@"story"]);
		if ([TGStoryNumber(story[@"id"]) integerValue] != _storyId ||
			[TGStoryNumber(story[@"poster_chat_id"]) longLongValue] != _chatId)
			return;
		if (![story[@"is_being_posted"] boolValue])
			[self finishWithStory:TGStoryFlattened(story) error:nil];
	}
}

@end

@interface TGClient (StoriesInternal)
- (void)postStoryContent:(NSDictionary *)content
                    path:(NSString *)path
                  asChat:(int64_t)chatId
                 caption:(NSString *)caption
                 privacy:(NSString *)privacy
                 userIds:(NSArray *)userIds
            activePeriod:(NSInteger)activePeriod
               toProfile:(BOOL)toProfile
                progress:(void (^)(float fraction))progress
              completion:(void (^)(NSDictionary *story, NSString *error))completion;
- (NSArray *)flattenedStoryInteractions:(NSArray *)interactions;
- (void)requestStoryAlbum:(NSDictionary *)request
               completion:(void (^)(NSDictionary *album))completion;
- (void)handleFoundStories:(NSDictionary *)result
                completion:(void (^)(NSArray *stories, NSString *nextOffset, NSInteger total))completion;
@end

@implementation TGClient (Stories)

#pragma mark - active stories

- (void)loadActiveStoriesArchived:(BOOL)archived {
	[self send:@{
		@"@type"      : @"loadActiveStories",
		@"story_list" : @{@"@type" : archived ? @"storyListArchive" : @"storyListMain"},
	}];
}

- (void)activeStoriesForChat:(int64_t)chatId
                  completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"   : @"getChatActiveStories",
		@"chat_id" : @(chatId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(nil);
			return;
		}
		NSArray *raw = TGStoryArray(result[@"stories"]);
		if (!raw.count){
			completion(nil);
			return;
		}
		NSInteger maxRead = [TGStoryNumber(result[@"max_read_story_id"]) integerValue];
		BOOL unread = NO;
		NSMutableArray *stories = [NSMutableArray array];
		for (NSDictionary *info in raw){
			NSNumber *storyId = TGStoryNumber(TGStoryDict(info)[@"story_id"]);
			if (!storyId)
				continue;
			if (storyId.integerValue > maxRead)
				unread = YES;
			[stories addObject:@{
				@"id"           : storyId,
				@"date"         : TGStoryNumber(info[@"date"]) ?: @(0),
				@"closeFriends" : @([info[@"is_for_close_friends"] boolValue]),
				@"isLive"       : @([info[@"is_live"] boolValue]),
			}];
		}
		if (!stories.count){
			completion(nil);
			return;
		}
		BOOL archived = [TGStoryDict(result[@"list"])[@"@type"]
						 isEqualToString:@"storyListArchive"];
		completion(@{
			@"chatId"         : TGStoryNumber(result[@"chat_id"]) ?: @(chatId),
			@"order"          : TGStoryNumber(result[@"order"]) ?: @(0),
			@"canBeArchived"  : @([result[@"can_be_archived"] boolValue]),
			@"maxReadStoryId" : @(maxRead),
			@"unread"         : @(unread),
			@"archived"       : @(archived),
			@"stories"        : stories,
		});
	}];
}

- (void)setChat:(int64_t)chatId storiesArchived:(BOOL)archived {
	[self send:@{
		@"@type"      : @"setChatActiveStoriesList",
		@"chat_id"    : @(chatId),
		@"story_list" : @{@"@type" : archived ? @"storyListArchive" : @"storyListMain"},
	}];
}

#pragma mark - viewing

- (void)storyWithId:(NSInteger)storyId
             inChat:(int64_t)chatId
         completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"                : @"getStory",
		@"story_poster_chat_id" : @(chatId),
		@"story_id"             : @(storyId),
		@"only_local"           : @NO,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGStoryIsError(result) ? nil : TGStoryFlattened(result));
	}];
}

- (void)openStory:(NSInteger)storyId inChat:(int64_t)chatId {
	[self send:@{
		@"@type"                : @"openStory",
		@"story_poster_chat_id" : @(chatId),
		@"story_id"             : @(storyId),
	}];
}

- (void)closeStory:(NSInteger)storyId inChat:(int64_t)chatId {
	[self send:@{
		@"@type"                : @"closeStory",
		@"story_poster_chat_id" : @(chatId),
		@"story_id"             : @(storyId),
	}];
}

- (void)markStoryRead:(NSInteger)storyId inChat:(int64_t)chatId {
	[self openStory:storyId inChat:chatId];
	[self closeStory:storyId inChat:chatId];
}

#pragma mark - interactions

- (void)storyReactionsWithLimit:(NSInteger)limit
                     completion:(void (^)(NSArray *))completion {
	NSInteger rowSize = limit > 0 && limit < 8 ? limit : 8;
	[self request:@{
		@"@type"    : @"getStoryAvailableReactions",
		@"row_size" : @(rowSize),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		NSArray *groups = @[TGStoryArray(result[@"top_reactions"]),
							TGStoryArray(result[@"recent_reactions"]),
							TGStoryArray(result[@"popular_reactions"])];
		for (NSArray *group in groups){
			for (NSDictionary *entry in group){
				NSString *emoji = TGStoryReactionEmoji(TGStoryDict(entry)[@"type"]);
				if (!emoji.length || [out containsObject:emoji])
					continue;
				[out addObject:emoji];
				if (limit > 0 && (NSInteger)out.count >= limit){
					completion(out);
					return;
				}
			}
		}
		completion(out);
	}];
}

- (void)reactToStory:(NSInteger)storyId
              inChat:(int64_t)chatId
               emoji:(NSString *)emoji {
	NSMutableDictionary *request = [@{
		@"@type"                    : @"setStoryReaction",
		@"story_poster_chat_id"     : @(chatId),
		@"story_id"                 : @(storyId),
		@"update_recent_reactions"  : @YES,
	} mutableCopy];
	if (emoji.length)
		request[@"reaction_type"] = @{@"@type" : @"reactionTypeEmoji", @"emoji" : emoji};
	[self send:request];
}

- (NSArray *)flattenedStoryInteractions:(NSArray *)interactions {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *raw in TGStoryArray(interactions)){
		NSDictionary *one = TGStoryDict(raw);
		if (!one)
			continue;
		int64_t actorId = TGStorySenderId(one[@"actor_id"]);
		NSDictionary *type = TGStoryDict(one[@"type"]);
		NSString *rawType = TGStoryString(type[@"@type"]);
		NSString *kind = @"view";
		if ([rawType isEqualToString:@"storyInteractionTypeForward"])
			kind = @"forward";
		else if ([rawType isEqualToString:@"storyInteractionTypeRepost"])
			kind = @"repost";
		BOOL blocked = [TGStoryDict(one[@"block_list"])[@"@type"] length] > 0;
		[out addObject:@{
			@"id"      : @(actorId),
			@"name"    : TGStorySenderName(self, actorId),
			@"date"    : TGStoryNumber(one[@"interaction_date"]) ?: @(0),
			@"emoji"   : TGStoryReactionEmoji(type[@"chosen_reaction_type"]),
			@"kind"    : kind,
			@"blocked" : @(blocked),
		}];
	}
	return out;
}

- (void)viewersOfStory:(NSInteger)storyId
                offset:(NSString *)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *, NSString *, NSInteger))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"                : @"getStoryInteractions",
		@"story_id"             : @(storyId),
		@"query"                : @"",
		@"only_contacts"        : @NO,
		@"prefer_forwards"      : @NO,
		@"prefer_with_reaction" : @YES,
		@"offset"               : offset ?: @"",
		@"limit"                : @(limit > 0 ? limit : 20),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[], @"", 0);
			return;
		}
		completion([weakSelf flattenedStoryInteractions:result[@"interactions"]],
				   TGStoryString(result[@"next_offset"]),
				   [TGStoryNumber(result[@"total_count"]) integerValue]);
	}];
}

- (void)viewersOfStory:(NSInteger)storyId
                inChat:(int64_t)chatId
                offset:(NSString *)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *, NSString *, NSInteger))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"                : @"getChatStoryInteractions",
		@"story_poster_chat_id" : @(chatId),
		@"story_id"             : @(storyId),
		@"prefer_forwards"      : @NO,
		@"offset"               : offset ?: @"",
		@"limit"                : @(limit > 0 ? limit : 20),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[], @"", 0);
			return;
		}
		completion([weakSelf flattenedStoryInteractions:result[@"interactions"]],
				   TGStoryString(result[@"next_offset"]),
				   [TGStoryNumber(result[@"total_count"]) integerValue]);
	}];
}

- (void)replyToStory:(NSInteger)storyId
              inChat:(int64_t)chatId
                text:(NSString *)text {
	if (!text.length)
		return;
	[self send:@{
		@"@type"    : @"sendMessage",
		@"chat_id"  : @(chatId),
		@"reply_to" : @{
			@"@type"                : @"inputMessageReplyToStory",
			@"story_poster_chat_id" : @(chatId),
			@"story_id"             : @(storyId),
		},
		@"input_message_content" : @{
			@"@type" : @"inputMessageText",
			@"text"  : @{@"@type" : @"formattedText", @"text" : text},
		},
	}];
}

- (void)publicForwardsOfStory:(NSInteger)storyId
                       inChat:(int64_t)chatId
                       offset:(NSString *)offset
                        limit:(NSInteger)limit
                   completion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{
		@"@type"                : @"getStoryPublicForwards",
		@"story_poster_chat_id" : @(chatId),
		@"story_id"             : @(storyId),
		@"offset"               : offset ?: @"",
		@"limit"                : @(limit > 0 ? limit : 20),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[], @"");
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *raw in TGStoryArray(result[@"forwards"])){
			NSDictionary *one = TGStoryDict(raw);
			if (!one)
				continue;
			if ([one[@"@type"] isEqualToString:@"publicForwardStory"]){
				NSDictionary *story = TGStoryFlattened(one[@"story"]);
				if (!story)
					continue;
				[out addObject:@{
					@"chatId"  : story[@"chatId"],
					@"title"   : @"",
					@"date"    : story[@"date"],
					@"isStory" : @YES,
					@"storyId" : story[@"id"],
				}];
				continue;
			}
			NSDictionary *message = TGStoryDict(one[@"message"]);
			if (!message)
				continue;
			[out addObject:@{
				@"chatId"  : TGStoryNumber(message[@"chat_id"]) ?: @(0),
				@"title"   : @"",
				@"date"    : TGStoryNumber(message[@"date"]) ?: @(0),
				@"isStory" : @NO,
			}];
		}
		completion(out, TGStoryString(result[@"next_offset"]));
	}];
}

#pragma mark - posting

- (void)canPostStoryAsChat:(int64_t)chatId
                completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"   : @"canPostStory",
		@"chat_id" : @(chatId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = TGStoryString(TGStoryDict(result)[@"@type"]);
		if ([type isEqualToString:@"canPostStoryResultOk"]){
			completion(YES, nil);
			return;
		}
		completion(NO, TGStoryLimitReason(type));
	}];
}

- (void)chatsToPostStoriesWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChatsToPostStories"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id one in TGStoryArray(result[@"chat_ids"])){
			NSNumber *chatId = TGStoryNumber(one);
			if (!chatId)
				continue;
			NSString *title = TGStorySenderName(weakSelf, chatId.longLongValue);
			[out addObject:@{@"id" : chatId, @"title" : title}];
		}
		completion(out);
	}];
}

- (void)postStoryContent:(NSDictionary *)content
                    path:(NSString *)path
                  asChat:(int64_t)chatId
                 caption:(NSString *)caption
                 privacy:(NSString *)privacy
                 userIds:(NSArray *)userIds
            activePeriod:(NSInteger)activePeriod
               toProfile:(BOOL)toProfile
                progress:(void (^)(float))progress
              completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!path.length || !content){
		if (completion)
			completion(nil, @"There is nothing to post.");
		return;
	}
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]){
		if (completion)
			completion(nil, @"The picked file went missing before it could be posted.");
		return;
	}

	NSInteger period = activePeriod;
	if (period != TGStoryPeriodSixHours && period != TGStoryPeriodTwelveHours &&
		period != TGStoryPeriodDay && period != TGStoryPeriodTwoDays)
		period = TGStoryPeriodDay;

	if (progress)
		progress(0.0f);

	[self request:@{
		@"@type"   : @"postStory",
		@"chat_id" : @(chatId),
		@"content" : content,
		@"areas"            : @{@"@type" : @"inputStoryAreas", @"areas" : @[]},
		@"caption"          : @{@"@type" : @"formattedText", @"text" : caption ?: @""},
		@"privacy_settings" : TGStoryPrivacyRules(privacy, userIds),
		@"album_ids"        : @[],
		@"active_period"    : @(period),
		@"is_posted_to_chat_page" : @(toProfile),
		@"protect_content"  : @NO,
	} completion:^(NSDictionary *result){
		if (TGStoryIsError(result)){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}

		NSDictionary *temporary = TGStoryDict(result);
		NSNumber *storyId = TGStoryNumber(temporary[@"id"]);
		if (!storyId){
			if (completion)
				completion(nil, @"Telegram did not accept the story.");
			return;
		}
		if (![temporary[@"is_being_posted"] boolValue]){
			if (progress)
				progress(1.0f);
			if (completion)
				completion(TGStoryFlattened(temporary), nil);
			return;
		}
		[TGStoryPostWatcher watchChat:chatId
		                      storyId:[storyId integerValue]
		                         path:path
		                     progress:progress
		                   completion:completion];
	}];
}

- (void)postPhotoStoryAtPath:(NSString *)path
                      asChat:(int64_t)chatId
                     caption:(NSString *)caption
                     privacy:(NSString *)privacy
                     userIds:(NSArray *)userIds
                activePeriod:(NSInteger)activePeriod
                   toProfile:(BOOL)toProfile
                    progress:(void (^)(float))progress
                  completion:(void (^)(NSDictionary *, NSString *))completion {
	[self postStoryContent:@{
		@"@type" : @"inputStoryContentPhoto",
		@"photo" : @{@"@type" : @"inputFileLocal", @"path" : (path ?: @"")},
		@"added_sticker_file_ids" : @[],
	}
	                  path:path
	                asChat:chatId
	               caption:caption
	               privacy:privacy
	               userIds:userIds
	          activePeriod:activePeriod
	             toProfile:toProfile
	              progress:progress
	            completion:completion];
}

- (void)postVideoStoryAtPath:(NSString *)path
                    duration:(double)duration
                      asChat:(int64_t)chatId
                     caption:(NSString *)caption
                     privacy:(NSString *)privacy
                     userIds:(NSArray *)userIds
                activePeriod:(NSInteger)activePeriod
                   toProfile:(BOOL)toProfile
                    progress:(void (^)(float))progress
                  completion:(void (^)(NSDictionary *, NSString *))completion {
	[self postStoryContent:@{
		@"@type" : @"inputStoryContentVideo",
		@"video" : @{@"@type" : @"inputFileLocal", @"path" : (path ?: @"")},
		@"added_sticker_file_ids" : @[],
		@"duration"              : @(duration > 0.0 ? duration : 0.0),
		@"cover_frame_timestamp" : @(0.0),
		@"is_animation"          : @NO,
	}
	                  path:path
	                asChat:chatId
	               caption:caption
	               privacy:privacy
	               userIds:userIds
	          activePeriod:activePeriod
	             toProfile:toProfile
	              progress:progress
	            completion:completion];
}

- (void)postPhotoStoryAtPath:(NSString *)path
                      asChat:(int64_t)chatId
                     caption:(NSString *)caption
                     privacy:(NSString *)privacy
                     userIds:(NSArray *)userIds
                   toProfile:(BOOL)toProfile
                  completion:(void (^)(NSDictionary *))completion {
	[self postPhotoStoryAtPath:path
	                    asChat:chatId
	                   caption:caption
	                   privacy:privacy
	                   userIds:userIds
	              activePeriod:TGStoryPeriodDay
	                 toProfile:toProfile
	                  progress:nil
	                completion:^(NSDictionary *story, NSString *error){
		(void)error;
		if (completion)
			completion(story);
	}];
}

- (void)repostStory:(NSInteger)storyId
           fromChat:(int64_t)fromChatId
             asChat:(int64_t)chatId
            caption:(NSString *)caption
            privacy:(NSString *)privacy
         completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"   : @"postStory",
		@"chat_id" : @(chatId),
		@"areas"            : @{@"@type" : @"inputStoryAreas", @"areas" : @[]},
		@"caption"          : @{@"@type" : @"formattedText", @"text" : caption ?: @""},
		@"privacy_settings" : TGStoryPrivacyRules(privacy, nil),
		@"album_ids"        : @[],
		@"active_period"    : @(86400),
		@"from_story_full_id" : @{
			@"@type"          : @"storyFullId",
			@"poster_chat_id" : @(fromChatId),
			@"story_id"       : @(storyId),
		},
		@"is_posted_to_chat_page" : @NO,
		@"protect_content"        : @NO,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGStoryIsError(result) ? nil : TGStoryFlattened(result));
	}];
}

- (void)editStory:(NSInteger)storyId
           inChat:(int64_t)chatId
          caption:(NSString *)caption {
	[self send:@{
		@"@type"                : @"editStory",
		@"story_poster_chat_id" : @(chatId),
		@"story_id"             : @(storyId),
		@"areas"                : @{@"@type" : @"inputStoryAreas", @"areas" : @[]},
		@"caption"              : @{@"@type" : @"formattedText", @"text" : caption ?: @""},
	}];
}

- (void)editStory:(NSInteger)storyId
           inChat:(int64_t)chatId
        photoPath:(NSString *)path
          caption:(NSString *)caption {
	if (!path.length){
		[self editStory:storyId inChat:chatId caption:caption];
		return;
	}
	[self send:@{
		@"@type"                : @"editStory",
		@"story_poster_chat_id" : @(chatId),
		@"story_id"             : @(storyId),
		@"content" : @{
			@"@type" : @"inputStoryContentPhoto",
			@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path},
			@"added_sticker_file_ids" : @[],
		},
		@"areas"   : @{@"@type" : @"inputStoryAreas", @"areas" : @[]},
		@"caption" : @{@"@type" : @"formattedText", @"text" : caption ?: @""},
	}];
}

- (void)deleteStory:(NSInteger)storyId inChat:(int64_t)chatId {
	[self send:@{
		@"@type"                : @"deleteStory",
		@"story_poster_chat_id" : @(chatId),
		@"story_id"             : @(storyId),
	}];
}

#pragma mark - privacy

- (void)setStory:(NSInteger)storyId
         privacy:(NSString *)privacy
         userIds:(NSArray *)userIds {
	[self send:@{
		@"@type"            : @"setStoryPrivacySettings",
		@"story_id"         : @(storyId),
		@"privacy_settings" : TGStoryPrivacyRules(privacy, userIds),
	}];
}

- (void)closeFriendsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getCloseFriends"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *raw in TGStoryArray(result[@"users"])){
			NSDictionary *user = TGStoryDict(raw);
			NSNumber *userId = TGStoryNumber(user[@"id"]);
			if (!userId)
				continue;
			NSString *first = TGStoryString(user[@"first_name"]);
			NSString *last = TGStoryString(user[@"last_name"]);
			NSString *name = last.length ?
				[NSString stringWithFormat:@"%@ %@", first, last] : first;
			NSArray *usernames = TGStoryArray(TGStoryDict(user[@"usernames"])[@"active_usernames"]);
			[out addObject:@{
				@"id"       : userId,
				@"name"     : name,
				@"username" : usernames.count ? TGStoryString(usernames[0]) : @"",
			}];
		}
		completion(out);
	}];
}

- (void)setCloseFriends:(NSArray *)userIds {
	[self send:@{
		@"@type"    : @"setCloseFriends",
		@"user_ids" : TGStoryIdList(userIds),
	}];
}

- (void)hiddenStoryPostersWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"      : @"getBlockedMessageSenders",
		@"block_list" : @{@"@type" : @"blockListStories"},
		@"offset"     : @(0),
		@"limit"      : @(100),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *sender in TGStoryArray(result[@"senders"])){
			int64_t senderId = TGStorySenderId(sender);
			if (!senderId)
				continue;
			[out addObject:@{
				@"id"   : @(senderId),
				@"name" : TGStorySenderName(weakSelf, senderId),
			}];
		}
		completion(out);
	}];
}

- (void)setUser:(int64_t)userId storiesHidden:(BOOL)hidden {
	NSMutableDictionary *request = [@{
		@"@type"     : @"setMessageSenderBlockList",
		@"sender_id" : @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)},
	} mutableCopy];
	if (hidden)
		request[@"block_list"] = @{@"@type" : @"blockListStories"};
	[self send:request];
}

#pragma mark - archive and profile

- (void)archivedStoriesInChat:(int64_t)chatId
                  fromStoryId:(NSInteger)fromStoryId
                        limit:(NSInteger)limit
                   completion:(void (^)(NSArray *, NSInteger))completion {
	[self request:@{
		@"@type"         : @"getChatArchivedStories",
		@"chat_id"       : @(chatId),
		@"from_story_id" : @(fromStoryId),
		@"limit"         : @(limit > 0 ? limit : 30),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[], 0);
			return;
		}
		completion(TGStoriesFlattened(result[@"stories"]),
				   [TGStoryNumber(result[@"total_count"]) integerValue]);
	}];
}

- (void)profileStoriesInChat:(int64_t)chatId
                 fromStoryId:(NSInteger)fromStoryId
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *, NSArray *, NSInteger))completion {
	[self request:@{
		@"@type"         : @"getChatPostedToChatPageStories",
		@"chat_id"       : @(chatId),
		@"from_story_id" : @(fromStoryId),
		@"limit"         : @(limit > 0 ? limit : 30),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[], @[], 0);
			return;
		}
		completion(TGStoriesFlattened(result[@"stories"]),
				   TGStoryIdList(result[@"pinned_story_ids"]),
				   [TGStoryNumber(result[@"total_count"]) integerValue]);
	}];
}

- (void)setStory:(NSInteger)storyId inChat:(int64_t)chatId onProfile:(BOOL)onProfile {
	[self send:@{
		@"@type"                  : @"toggleStoryIsPostedToChatPage",
		@"story_poster_chat_id"   : @(chatId),
		@"story_id"               : @(storyId),
		@"is_posted_to_chat_page" : @(onProfile),
	}];
}

- (void)setPinnedStories:(NSArray *)storyIds inChat:(int64_t)chatId {
	[self send:@{
		@"@type"     : @"setChatPinnedStories",
		@"chat_id"   : @(chatId),
		@"story_ids" : TGStoryIdList(storyIds),
	}];
}

#pragma mark - albums

- (void)storyAlbumsInChat:(int64_t)chatId completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"   : @"getChatStoryAlbums",
		@"chat_id" : @(chatId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *raw in TGStoryArray(result[@"albums"])){
			NSDictionary *album = TGStoryAlbumFlattened(raw);
			if (album)
				[out addObject:album];
		}
		completion(out);
	}];
}

- (void)requestStoryAlbum:(NSDictionary *)request
               completion:(void (^)(NSDictionary *))completion {
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGStoryIsError(result) ? nil : TGStoryAlbumFlattened(result));
	}];
}

- (void)createStoryAlbumInChat:(int64_t)chatId
                          name:(NSString *)name
                      storyIds:(NSArray *)storyIds
                    completion:(void (^)(NSDictionary *))completion {
	[self requestStoryAlbum:@{
		@"@type"                : @"createStoryAlbum",
		@"story_poster_chat_id" : @(chatId),
		@"name"                 : name ?: @"",
		@"story_ids"            : TGStoryIdList(storyIds),
	} completion:completion];
}

- (void)renameStoryAlbum:(NSInteger)albumId
                  inChat:(int64_t)chatId
                    name:(NSString *)name
              completion:(void (^)(NSDictionary *))completion {
	[self requestStoryAlbum:@{
		@"@type"          : @"setStoryAlbumName",
		@"chat_id"        : @(chatId),
		@"story_album_id" : @(albumId),
		@"name"           : name ?: @"",
	} completion:completion];
}

- (void)deleteStoryAlbum:(NSInteger)albumId inChat:(int64_t)chatId {
	[self send:@{
		@"@type"          : @"deleteStoryAlbum",
		@"chat_id"        : @(chatId),
		@"story_album_id" : @(albumId),
	}];
}

- (void)reorderStoryAlbums:(NSArray *)albumIds inChat:(int64_t)chatId {
	[self send:@{
		@"@type"           : @"reorderStoryAlbums",
		@"chat_id"         : @(chatId),
		@"story_album_ids" : TGStoryIdList(albumIds),
	}];
}

- (void)storiesInAlbum:(NSInteger)albumId
                inChat:(int64_t)chatId
                offset:(NSInteger)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *, NSInteger))completion {
	[self request:@{
		@"@type"          : @"getStoryAlbumStories",
		@"chat_id"        : @(chatId),
		@"story_album_id" : @(albumId),
		@"offset"         : @(offset),
		@"limit"          : @(limit > 0 ? limit : 30),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[], 0);
			return;
		}
		completion(TGStoriesFlattened(result[@"stories"]),
				   [TGStoryNumber(result[@"total_count"]) integerValue]);
	}];
}

- (void)addStories:(NSArray *)storyIds
           toAlbum:(NSInteger)albumId
            inChat:(int64_t)chatId
        completion:(void (^)(NSDictionary *))completion {
	[self requestStoryAlbum:@{
		@"@type"          : @"addStoryAlbumStories",
		@"chat_id"        : @(chatId),
		@"story_album_id" : @(albumId),
		@"story_ids"      : TGStoryIdList(storyIds),
	} completion:completion];
}

- (void)removeStories:(NSArray *)storyIds
            fromAlbum:(NSInteger)albumId
               inChat:(int64_t)chatId
           completion:(void (^)(NSDictionary *))completion {
	[self requestStoryAlbum:@{
		@"@type"          : @"removeStoryAlbumStories",
		@"chat_id"        : @(chatId),
		@"story_album_id" : @(albumId),
		@"story_ids"      : TGStoryIdList(storyIds),
	} completion:completion];
}

- (void)reorderStories:(NSArray *)storyIds
               inAlbum:(NSInteger)albumId
                inChat:(int64_t)chatId
            completion:(void (^)(NSDictionary *))completion {
	[self requestStoryAlbum:@{
		@"@type"          : @"reorderStoryAlbumStories",
		@"chat_id"        : @(chatId),
		@"story_album_id" : @(albumId),
		@"story_ids"      : TGStoryIdList(storyIds),
	} completion:completion];
}

#pragma mark - search and links

- (void)handleFoundStories:(NSDictionary *)result
                completion:(void (^)(NSArray *, NSString *, NSInteger))completion {
	if (!completion)
		return;
	if (TGStoryIsError(result)){
		completion(@[], @"", 0);
		return;
	}
	completion(TGStoriesFlattened(result[@"stories"]),
			   TGStoryString(result[@"next_offset"]),
			   [TGStoryNumber(result[@"total_count"]) integerValue]);
}

- (void)searchStoriesWithTag:(NSString *)tag
                posterChatId:(int64_t)posterChatId
                      offset:(NSString *)offset
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *, NSString *, NSInteger))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"                : @"searchPublicStoriesByTag",
		@"story_poster_chat_id" : @(posterChatId),
		@"tag"                  : tag ?: @"",
		@"offset"               : offset ?: @"",
		@"limit"                : @(limit > 0 ? limit : 20),
	} completion:^(NSDictionary *result){
		[weakSelf handleFoundStories:result completion:completion];
	}];
}

- (void)searchStoriesAtVenueProvider:(NSString *)provider
                             venueId:(NSString *)venueId
                              offset:(NSString *)offset
                               limit:(NSInteger)limit
                          completion:(void (^)(NSArray *, NSString *, NSInteger))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"          : @"searchPublicStoriesByVenue",
		@"venue_provider" : provider ?: @"",
		@"venue_id"       : venueId ?: @"",
		@"offset"         : offset ?: @"",
		@"limit"          : @(limit > 0 ? limit : 20),
	} completion:^(NSDictionary *result){
		[weakSelf handleFoundStories:result completion:completion];
	}];
}

- (void)resolveStoryLink:(NSString *)link
              completion:(void (^)(int64_t, NSInteger))completion {
	if (!link.length){
		if (completion)
			completion(0, 0);
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type" : @"getInternalLinkType",
		@"link"  : link,
	} completion:^(NSDictionary *result){
		NSDictionary *type = TGStoryDict(result);
		if (![type[@"@type"] isEqualToString:@"internalLinkTypeStory"]){
			if (completion)
				completion(0, 0);
			return;
		}
		NSInteger storyId = [TGStoryNumber(type[@"story_id"]) integerValue];
		NSString *username = TGStoryString(type[@"story_poster_username"]);
		[weakSelf request:@{
			@"@type"    : @"searchPublicChat",
			@"username" : username,
		} completion:^(NSDictionary *chat){
			if (!completion)
				return;
			if (TGStoryIsError(chat)){
				completion(0, 0);
				return;
			}
			completion([TGStoryNumber(chat[@"id"]) longLongValue], storyId);
		}];
	}];
}

#pragma mark - reporting and notifications

- (void)reportStory:(NSInteger)storyId
             inChat:(int64_t)chatId
           optionId:(NSString *)optionId
               text:(NSString *)text
         completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"                : @"reportStory",
		@"story_poster_chat_id" : @(chatId),
		@"story_id"             : @(storyId),
		@"option_id"            : optionId ?: @"",
		@"text"                 : text ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = TGStoryString(TGStoryDict(result)[@"@type"]);
		if ([type isEqualToString:@"reportStoryResultOk"]){
			completion(@{@"status" : @"ok"});
			return;
		}
		if ([type isEqualToString:@"reportStoryResultOptionRequired"]){
			NSMutableArray *options = [NSMutableArray array];
			for (NSDictionary *raw in TGStoryArray(result[@"options"])){
				NSDictionary *option = TGStoryDict(raw);
				if (!option)
					continue;
				[options addObject:@{
					@"id"   : TGStoryString(option[@"id"]),
					@"text" : TGStoryString(option[@"text"]),
				}];
			}
			completion(@{
				@"status"  : @"option",
				@"title"   : TGStoryString(result[@"title"]),
				@"options" : options,
			});
			return;
		}
		if ([type isEqualToString:@"reportStoryResultTextRequired"]){
			completion(@{
				@"status"   : @"text",
				@"optionId" : TGStoryString(result[@"option_id"]),
				@"optional" : @([result[@"is_optional"] boolValue]),
			});
			return;
		}
		completion(@{@"status" : @"error"});
	}];
}

- (void)setChat:(int64_t)chatId storiesMuted:(BOOL)muted {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (TGStoryIsError(chat))
			return;
		NSDictionary *current = TGStoryDict(chat[@"notification_settings"]);
		NSMutableDictionary *settings = current ? [current mutableCopy] :
			[@{@"@type" : @"chatNotificationSettings"} mutableCopy];
		settings[@"@type"] = @"chatNotificationSettings";
		settings[@"use_default_mute_stories"] = @NO;
		settings[@"mute_stories"] = @(muted);
		[weakSelf send:@{
			@"@type"                 : @"setChatNotificationSettings",
			@"chat_id"               : @(chatId),
			@"notification_settings" : settings,
		}];
	}];
}

- (void)storyNotificationExceptionsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getStoryNotificationSettingsExceptions"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGStoryIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id one in TGStoryArray(result[@"chat_ids"])){
			NSNumber *chatId = TGStoryNumber(one);
			if (!chatId)
				continue;
			[out addObject:@{
				@"id"    : chatId,
				@"title" : TGStorySenderName(weakSelf, chatId.longLongValue),
			}];
		}
		completion(out);
	}];
}

- (void)setStoryReactionNotificationSource:(NSString *)source {
	NSString *type = @"reactionNotificationSourceContacts";
	if ([source isEqualToString:@"all"])
		type = @"reactionNotificationSourceAll";
	else if ([source isEqualToString:@"none"])
		type = @"reactionNotificationSourceNone";
	[self send:@{
		@"@type" : @"setReactionNotificationSettings",
		@"notification_settings" : @{
			@"@type"                  : @"reactionNotificationSettings",
			@"message_reaction_source": @{@"@type" : @"reactionNotificationSourceContacts"},
			@"story_reaction_source"  : @{@"@type" : type},
			@"poll_vote_source"       : @{@"@type" : @"reactionNotificationSourceContacts"},
			@"sound_id"               : @(0),
			@"show_preview"           : @YES,
		},
	}];
}

- (void)setStoryPreloading:(BOOL)preload onNetwork:(NSString *)type {
	NSDictionary *current =
			TGStoryAutoDownloadFromMirror([self autoDownloadSettingsForNetworkType:type]);
	if (current){
		NSMutableDictionary *settings = [current mutableCopy];
		settings[@"preload_stories"] = @(preload);
		[self send:@{
			@"@type"    : @"setAutoDownloadSettings",
			@"settings" : settings,
			@"type"     : @{@"@type" : TGStoryNetworkType(type)},
		}];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getAutoDownloadSettingsPresets"}
	   completion:^(NSDictionary *presets){
		if (TGStoryIsError(presets))
			return;
		NSDictionary *base = TGStoryDict(presets[@"low"]);
		if (!base)
			return;
		NSMutableDictionary *settings = [base mutableCopy];
		settings[@"@type"] = @"autoDownloadSettings";
		settings[@"preload_stories"] = @(preload);
		[weakSelf send:@{
			@"@type"    : @"setAutoDownloadSettings",
			@"settings" : settings,
			@"type"     : @{@"@type" : TGStoryNetworkType(type)},
		}];
	}];
}

@end

#import "TGClient+Private.h"
#import "TGClient+Channels.h"

static BOOL TGChIsError(NSDictionary *result){
	if (![result isKindOfClass:NSDictionary.class])
		return YES;
	id type = result[@"@type"];
	return [type isKindOfClass:NSString.class] && [type isEqualToString:@"error"];
}

static NSNumber *TGChNumber(id value){
	return [value isKindOfClass:NSNumber.class] ? value : @(0);
}

static NSString *TGChString(id value){
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSArray *TGChArray(id value){
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSDictionary *TGChDict(id value){
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSDictionary *TGChValue(NSString *key, NSString *title, id raw){
	NSDictionary *v = TGChDict(raw);
	if (!v)
		return nil;
	return @{
		@"key"      : key,
		@"title"    : title,
		@"value"    : TGChNumber(v[@"value"]),
		@"previous" : TGChNumber(v[@"previous_value"]),
		@"growth"   : TGChNumber(v[@"growth_rate_percentage"]),
	};
}

static NSDictionary *TGChGraph(NSString *key, NSString *title, id raw){
	NSDictionary *g = TGChDict(raw);
	if (!g)
		return nil;
	NSString *type = TGChString(g[@"@type"]);
	if ([type isEqualToString:@"statisticalGraphData"]){
		return @{
			@"key"        : key,
			@"title"      : title,
			@"json"       : TGChString(g[@"json_data"]),
			@"zoom_token" : TGChString(g[@"zoom_token"]),
		};
	}
	if ([type isEqualToString:@"statisticalGraphAsync"]){
		return @{
			@"key"   : key,
			@"title" : title,
			@"token" : TGChString(g[@"token"]),
		};
	}
	return nil;
}

static void TGChAddGraphs(NSMutableArray *out, NSDictionary *stats, NSArray *pairs){
	for (NSUInteger i = 0; i + 1 < pairs.count; i += 2){
		NSString *key   = pairs[i];
		NSString *title = pairs[i + 1];
		NSDictionary *g = TGChGraph(key, title, stats[key]);
		if (g) [out addObject:g];
	}
}

static void TGChAddValues(NSMutableArray *out, NSDictionary *stats, NSArray *pairs){
	for (NSUInteger i = 0; i + 1 < pairs.count; i += 2){
		NSDictionary *v = TGChValue(pairs[i], pairs[i + 1], stats[pairs[i]]);
		if (v) [out addObject:v];
	}
}

@implementation TGClient (Channels)

#pragma mark - Shared plumbing

- (void)tgch_supergroupIdForChat:(int64_t)chatId
                      completion:(void (^)(NSNumber *supergroupId, BOOL isChannel))completion {
	[self request:@{ @"@type" : @"getChat", @"chat_id" : @(chatId) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSDictionary *type = TGChIsError(result) ? nil : TGChDict(result[@"type"]);
		if (!type || ![TGChString(type[@"@type"]) isEqualToString:@"chatTypeSupergroup"]){
			completion(nil, NO);
			return;
		}
		completion(TGChNumber(type[@"supergroup_id"]),
		           [TGChNumber(type[@"is_channel"]) boolValue]);
	}];
}

- (void)tgch_supergroupFullInfoForChat:(int64_t)chatId
                            completion:(void (^)(NSDictionary *full))completion {
	[self tgch_supergroupIdForChat:chatId completion:^(NSNumber *supergroupId, BOOL isChannel){
		if (!supergroupId){
			if (completion) completion(nil);
			return;
		}
		[self request:@{ @"@type" : @"getSupergroupFullInfo",
		                 @"supergroup_id" : supergroupId }
		   completion:^(NSDictionary *result){
			if (!completion)
				return;
			completion(TGChIsError(result) ? nil : result);
		}];
	}];
}

- (void)tgch_send:(NSDictionary *)request completion:(void (^)(BOOL ok))completion {
	[self request:request completion:^(NSDictionary *result){
		if (completion) completion(!TGChIsError(result));
	}];
}

#pragma mark - Signatures

- (void)channelSignaturesForChat:(int64_t)chatId
                      completion:(void (^)(NSDictionary *info))completion {
	[self tgch_supergroupIdForChat:chatId completion:^(NSNumber *supergroupId, BOOL isChannel){
		if (!supergroupId){
			if (completion) completion(nil);
			return;
		}
		[self request:@{ @"@type" : @"getSupergroup", @"supergroup_id" : supergroupId }
		   completion:^(NSDictionary *result){
			if (!completion)
				return;
			if (TGChIsError(result)){
				completion(nil);
				return;
			}
			completion(@{
				@"supergroup_id"       : supergroupId,
				@"is_channel"          : TGChNumber(result[@"is_channel"]),
				@"sign_messages"       : TGChNumber(result[@"sign_messages"]),
				@"show_message_sender" : TGChNumber(result[@"show_message_sender"]),
				@"has_linked_chat"     : TGChNumber(result[@"has_linked_chat"]),
				@"boost_level"         : TGChNumber(result[@"boost_level"]),
			});
		}];
	}];
}

- (void)setChannelSignaturesForChat:(int64_t)chatId
                       signMessages:(BOOL)sign
                 showAuthorProfiles:(BOOL)showAuthorProfiles
                         completion:(void (^)(BOOL ok))completion {
	[self tgch_supergroupIdForChat:chatId completion:^(NSNumber *supergroupId, BOOL isChannel){
		if (!supergroupId){
			if (completion) completion(NO);
			return;
		}
		[self tgch_send:@{
			@"@type"               : @"toggleSupergroupSignMessages",
			@"supergroup_id"       : supergroupId,
			@"sign_messages"       : @(sign),
			@"show_message_sender" : @(sign && showAuthorProfiles),
		} completion:completion];
	}];
}

#pragma mark - Discussion group

- (void)discussionGroupForChannel:(int64_t)chatId
                       completion:(void (^)(NSNumber *linkedChatId))completion {
	[self tgch_supergroupFullInfoForChat:chatId completion:^(NSDictionary *full){
		if (!completion)
			return;
		NSNumber *linked = full ? TGChNumber(full[@"linked_chat_id"]) : nil;
		completion([linked longLongValue] != 0 ? linked : nil);
	}];
}

- (void)suitableDiscussionChatsWithCompletion:(void (^)(NSArray *chats))completion {
	[self request:@{ @"@type" : @"getSuitableDiscussionChats" }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *ids = TGChIsError(result) ? nil : TGChArray(result[@"chat_ids"]);
		if (!ids){
			completion(nil);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		__block NSUInteger pending = ids.count;
		if (pending == 0){
			completion(out);
			return;
		}
		for (id rawId in ids){
			NSNumber *cid = TGChNumber(rawId);
			[self request:@{ @"@type" : @"getChat", @"chat_id" : cid }
			   completion:^(NSDictionary *chat){
				if (!TGChIsError(chat))
					[out addObject:@{ @"id"    : cid,
					                  @"title" : TGChString(chat[@"title"]) }];
				if (--pending == 0)
					completion(out);
			}];
		}
	}];
}

- (void)setDiscussionGroup:(int64_t)discussionChatId
                forChannel:(int64_t)chatId
                completion:(void (^)(BOOL ok))completion {
	[self tgch_send:@{
		@"@type"             : @"setChatDiscussionGroup",
		@"chat_id"           : @(chatId),
		@"discussion_chat_id": @(discussionChatId),
	} completion:completion];
}

- (void)isAllHistoryAvailableForChat:(int64_t)chatId
                          completion:(void (^)(BOOL available))completion {
	[self tgch_supergroupFullInfoForChat:chatId completion:^(NSDictionary *full){
		if (completion)
			completion(full && [TGChNumber(full[@"is_all_history_available"]) boolValue]);
	}];
}

- (void)setAllHistoryAvailable:(BOOL)available
                       forChat:(int64_t)chatId
                    completion:(void (^)(BOOL ok))completion {
	[self tgch_supergroupIdForChat:chatId completion:^(NSNumber *supergroupId, BOOL isChannel){
		if (!supergroupId){
			if (completion) completion(NO);
			return;
		}
		[self tgch_send:@{
			@"@type"                    : @"toggleSupergroupIsAllHistoryAvailable",
			@"supergroup_id"            : supergroupId,
			@"is_all_history_available" : @(available),
		} completion:completion];
	}];
}

#pragma mark - Statistics

- (void)canGetStatisticsForChat:(int64_t)chatId
                     completion:(void (^)(BOOL canGet))completion {
	[self tgch_supergroupFullInfoForChat:chatId completion:^(NSDictionary *full){
		if (completion)
			completion(full && [TGChNumber(full[@"can_get_statistics"]) boolValue]);
	}];
}

- (void)statisticsForChat:(int64_t)chatId
                   isDark:(BOOL)isDark
               completion:(void (^)(NSDictionary *stats))completion {
	[self request:@{ @"@type" : @"getChatStatistics",
	                 @"chat_id" : @(chatId),
	                 @"is_dark" : @(isDark) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGChIsError(result)){
			completion(nil);
			return;
		}
		NSString *type = TGChString(result[@"@type"]);
		BOOL isChannel = [type isEqualToString:@"chatStatisticsChannel"];
		if (!isChannel && ![type isEqualToString:@"chatStatisticsSupergroup"]){
			completion(nil);
			return;
		}
		NSMutableDictionary *out = [NSMutableDictionary dictionary];
		out[@"kind"] = isChannel ? @"channel" : @"supergroup";

		NSDictionary *period = TGChDict(result[@"period"]);
		if (period)
			out[@"period"] = @{ @"start_date" : TGChNumber(period[@"start_date"]),
			                    @"end_date"   : TGChNumber(period[@"end_date"]) };

		NSMutableArray *values = [NSMutableArray array];
		NSMutableArray *graphs = [NSMutableArray array];
		if (isChannel){
			TGChAddValues(values, result, @[
				@"member_count",              @"Followers",
				@"mean_message_view_count",   @"Mean Views",
				@"mean_message_share_count",  @"Mean Shares",
				@"mean_message_reaction_count", @"Mean Reactions",
				@"mean_story_view_count",     @"Mean Story Views",
				@"mean_story_share_count",    @"Mean Story Shares",
				@"mean_story_reaction_count", @"Mean Story Reactions" ]);
			[values addObject:@{
				@"key"      : @"enabled_notifications_percentage",
				@"title"    : @"Notifications",
				@"value"    : TGChNumber(result[@"enabled_notifications_percentage"]),
				@"previous" : @(0),
				@"growth"   : @(0) }];
			TGChAddGraphs(graphs, result, @[
				@"member_count_graph",             @"Growth",
				@"join_graph",                     @"Followers",
				@"mute_graph",                     @"Notifications",
				@"view_count_by_hour_graph",       @"Views By Hour",
				@"view_count_by_source_graph",     @"Views By Source",
				@"join_by_source_graph",           @"New Followers By Source",
				@"language_graph",                 @"Languages",
				@"message_interaction_graph",      @"Interactions",
				@"message_reaction_graph",         @"Reactions",
				@"story_interaction_graph",        @"Story Interactions",
				@"story_reaction_graph",           @"Story Reactions",
				@"instant_view_interaction_graph", @"Instant View Interactions" ]);

			NSMutableArray *recent = [NSMutableArray array];
			for (id rawInfo in TGChArray(result[@"recent_interactions"]) ?: @[]){
				NSDictionary *info = TGChDict(rawInfo);
				if (!info)
					continue;
				NSDictionary *object = TGChDict(info[@"object_type"]);
				[recent addObject:@{
					@"message_id"     : TGChNumber(object[@"message_id"]),
					@"story_id"       : TGChNumber(object[@"story_id"]),
					@"view_count"     : TGChNumber(info[@"view_count"]),
					@"forward_count"  : TGChNumber(info[@"forward_count"]),
					@"reaction_count" : TGChNumber(info[@"reaction_count"]) }];
			}
			out[@"recent_interactions"] = recent;
		} else {
			TGChAddValues(values, result, @[
				@"member_count",  @"Members",
				@"message_count", @"Messages",
				@"viewer_count",  @"Viewing Members",
				@"sender_count",  @"Posting Members" ]);
			TGChAddGraphs(graphs, result, @[
				@"member_count_graph",     @"Growth",
				@"join_graph",             @"New Members",
				@"join_by_source_graph",   @"New Members By Source",
				@"language_graph",         @"Languages",
				@"message_content_graph",  @"Messages",
				@"action_graph",           @"Actions",
				@"day_graph",              @"Time Of Day",
				@"week_graph",             @"Day Of Week" ]);

			NSMutableArray *senders = [NSMutableArray array];
			for (id raw in TGChArray(result[@"top_senders"]) ?: @[]){
				NSDictionary *info = TGChDict(raw);
				if (!info)
					continue;
				NSNumber *userId = TGChNumber(info[@"user_id"]);
				[senders addObject:@{
					@"user_id"                 : userId,
					@"name"                    : [self nameForUserId:[userId longLongValue]] ?: @"",
					@"sent_message_count"      : TGChNumber(info[@"sent_message_count"]),
					@"average_character_count" : TGChNumber(info[@"average_character_count"]) }];
			}
			out[@"top_senders"] = senders;

			NSMutableArray *admins = [NSMutableArray array];
			for (id raw in TGChArray(result[@"top_administrators"]) ?: @[]){
				NSDictionary *info = TGChDict(raw);
				if (!info)
					continue;
				NSNumber *userId = TGChNumber(info[@"user_id"]);
				[admins addObject:@{
					@"user_id"                : userId,
					@"name"                   : [self nameForUserId:[userId longLongValue]] ?: @"",
					@"deleted_message_count"  : TGChNumber(info[@"deleted_message_count"]),
					@"banned_user_count"      : TGChNumber(info[@"banned_user_count"]),
					@"restricted_user_count"  : TGChNumber(info[@"restricted_user_count"]) }];
			}
			out[@"top_administrators"] = admins;

			NSMutableArray *inviters = [NSMutableArray array];
			for (id raw in TGChArray(result[@"top_inviters"]) ?: @[]){
				NSDictionary *info = TGChDict(raw);
				if (!info)
					continue;
				NSNumber *userId = TGChNumber(info[@"user_id"]);
				[inviters addObject:@{
					@"user_id"            : userId,
					@"name"               : [self nameForUserId:[userId longLongValue]] ?: @"",
					@"added_member_count" : TGChNumber(info[@"added_member_count"]) }];
			}
			out[@"top_inviters"] = inviters;
		}
		out[@"values"] = values;
		out[@"graphs"] = graphs;
		completion(out);
	}];
}

- (void)statisticalGraphForChat:(int64_t)chatId
                          token:(NSString *)token
                        zoomAtX:(int64_t)x
                     completion:(void (^)(NSDictionary *graph))completion {
	if (![token isKindOfClass:NSString.class] || token.length == 0){
		if (completion) completion(nil);
		return;
	}
	[self request:@{ @"@type"   : @"getStatisticalGraph",
	                 @"chat_id" : @(chatId),
	                 @"token"   : token,
	                 @"x"       : @(x) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGChIsError(result)){
			completion(nil);
			return;
		}
		NSDictionary *graph = TGChGraph(@"graph", @"", result);
		completion(graph[@"json"] ? graph : nil);
	}];
}

- (void)statisticsForMessage:(int64_t)messageId
                      inChat:(int64_t)chatId
                      isDark:(BOOL)isDark
                  completion:(void (^)(NSArray *graphs))completion {
	[self request:@{ @"@type"      : @"getMessageStatistics",
	                 @"chat_id"    : @(chatId),
	                 @"message_id" : @(messageId),
	                 @"is_dark"    : @(isDark) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGChIsError(result)){
			completion(nil);
			return;
		}
		NSMutableArray *graphs = [NSMutableArray array];
		TGChAddGraphs(graphs, result, @[
			@"message_interaction_graph", @"Interactions",
			@"message_reaction_graph",    @"Reactions" ]);
		completion(graphs);
	}];
}

- (void)publicForwardsOfMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                         offset:(NSString *)offset
                          limit:(NSInteger)limit
                     completion:(void (^)(NSArray *forwards, NSString *nextOffset, NSInteger totalCount))completion {
	NSString *from = [offset isKindOfClass:NSString.class] ? offset : @"";
	[self request:@{ @"@type"      : @"getMessagePublicForwards",
	                 @"chat_id"    : @(chatId),
	                 @"message_id" : @(messageId),
	                 @"offset"     : from,
	                 @"limit"      : @(limit > 0 ? limit : 50) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGChIsError(result)){
			completion(nil, @"", 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id raw in TGChArray(result[@"forwards"]) ?: @[]){
			NSDictionary *forward = TGChDict(raw);
			if (!forward)
				continue;
			NSString *type = TGChString(forward[@"@type"]);
			if ([type isEqualToString:@"publicForwardMessage"]){
				NSDictionary *message = TGChDict(forward[@"message"]);
				if (!message)
					continue;
				NSNumber *forwardChatId = TGChNumber(message[@"chat_id"]);
				NSDictionary *interaction = TGChDict(message[@"interaction_info"]);
				[out addObject:@{
					@"chat_id"    : forwardChatId,
					@"message_id" : TGChNumber(message[@"id"]),
					@"title"      : [self tgch_titleForChat:[forwardChatId longLongValue]] ?: @"",
					@"view_count" : TGChNumber(interaction[@"view_count"]) }];
			} else if ([type isEqualToString:@"publicForwardStory"]){
				NSDictionary *story = TGChDict(forward[@"story"]);
				if (!story)
					continue;
				NSNumber *senderChatId = TGChNumber(story[@"poster_chat_id"]);
				[out addObject:@{
					@"story_id"       : TGChNumber(story[@"id"]),
					@"sender_chat_id" : senderChatId,
					@"title"          : [self tgch_titleForChat:[senderChatId longLongValue]] ?: @"" }];
			}
		}
		completion(out,
		           TGChString(result[@"next_offset"]),
		           (NSInteger)[TGChNumber(result[@"total_count"]) integerValue]);
	}];
}

- (NSString *)tgch_titleForChat:(int64_t)chatId {
	NSDictionary *chat = TGChDict(self.chatsById[@(chatId)]);
	NSString *title = chat[@"title"];
	return [title isKindOfClass:NSString.class] ? title : nil;
}

#pragma mark - Boosts

- (void)boostStatusForChat:(int64_t)chatId
                completion:(void (^)(NSDictionary *status))completion {
	[self request:@{ @"@type" : @"getChatBoostStatus", @"chat_id" : @(chatId) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGChIsError(result)){
			completion(nil);
			return;
		}
		NSArray *applied = TGChArray(result[@"applied_slot_ids"]) ?: @[];
		completion(@{
			@"boost_url"                 : TGChString(result[@"boost_url"]),
			@"level"                     : TGChNumber(result[@"level"]),
			@"boost_count"               : TGChNumber(result[@"boost_count"]),
			@"gift_code_boost_count"     : TGChNumber(result[@"gift_code_boost_count"]),
			@"current_level_boost_count" : TGChNumber(result[@"current_level_boost_count"]),
			@"next_level_boost_count"    : TGChNumber(result[@"next_level_boost_count"]),
			@"premium_member_count"      : TGChNumber(result[@"premium_member_count"]),
			@"premium_member_percentage" : TGChNumber(result[@"premium_member_percentage"]),
			@"applied_slot_ids"          : applied,
			@"is_boosted"                : @(applied.count > 0),
		});
	}];
}

- (NSArray *)tgch_flattenSlots:(NSDictionary *)result {
	NSArray *slots = TGChArray(result[@"slots"]);
	if (!slots)
		return nil;
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	NSMutableArray *out = [NSMutableArray array];
	for (id raw in slots){
		NSDictionary *slot = TGChDict(raw);
		if (!slot)
			continue;
		NSNumber *cooldown = TGChNumber(slot[@"cooldown_until_date"]);
		[out addObject:@{
			@"slot_id"                   : TGChNumber(slot[@"slot_id"]),
			@"currently_boosted_chat_id" : TGChNumber(slot[@"currently_boosted_chat_id"]),
			@"start_date"                : TGChNumber(slot[@"start_date"]),
			@"expiration_date"           : TGChNumber(slot[@"expiration_date"]),
			@"cooldown_until_date"       : cooldown,
			@"is_available"              : @([cooldown doubleValue] <= now),
		}];
	}
	return out;
}

- (void)channelBoostSlotsWithCompletion:(void (^)(NSArray *slots))completion {
	[self request:@{ @"@type" : @"getAvailableChatBoostSlots" }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGChIsError(result) ? nil : [self tgch_flattenSlots:result]);
	}];
}

- (void)boostChat:(int64_t)chatId
      withSlotIds:(NSArray *)slotIds
       completion:(void (^)(NSArray *slots))completion {
	NSMutableArray *ids = [NSMutableArray array];
	for (id raw in ([slotIds isKindOfClass:NSArray.class] ? slotIds : @[]))
		if ([raw isKindOfClass:NSNumber.class])
			[ids addObject:raw];
	[self request:@{ @"@type"    : @"boostChat",
	                 @"chat_id"  : @(chatId),
	                 @"slot_ids" : ids }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGChIsError(result) ? nil : [self tgch_flattenSlots:result]);
	}];
}

- (void)boostLinkForChat:(int64_t)chatId
              completion:(void (^)(NSString *link, BOOL isPublic))completion {
	[self request:@{ @"@type" : @"getChatBoostLink", @"chat_id" : @(chatId) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGChIsError(result)){
			completion(nil, NO);
			return;
		}
		NSString *link = TGChString(result[@"link"]);
		completion(link.length ? link : nil, [TGChNumber(result[@"is_public"]) boolValue]);
	}];
}

- (void)resolveBoostLink:(NSString *)url
              completion:(void (^)(NSNumber *chatId, BOOL isPublic))completion {
	if (![url isKindOfClass:NSString.class] || url.length == 0){
		if (completion) completion(nil, NO);
		return;
	}
	[self request:@{ @"@type" : @"getChatBoostLinkInfo", @"url" : url }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGChIsError(result)){
			completion(nil, NO);
			return;
		}
		NSNumber *chatId = TGChNumber(result[@"chat_id"]);
		completion([chatId longLongValue] != 0 ? chatId : nil,
		           [TGChNumber(result[@"is_public"]) boolValue]);
	}];
}

- (NSArray *)tgch_flattenBoosts:(NSDictionary *)result {
	NSArray *boosts = TGChArray(result[@"boosts"]);
	if (!boosts)
		return nil;
	NSMutableArray *out = [NSMutableArray array];
	for (id raw in boosts){
		NSDictionary *boost = TGChDict(raw);
		if (!boost)
			continue;
		NSDictionary *source = TGChDict(boost[@"source"]);
		NSString *sourceType = TGChString(source[@"@type"]);
		NSString *kind = @"premium";
		if ([sourceType isEqualToString:@"chatBoostSourceGiftCode"])
			kind = @"gift_code";
		else if ([sourceType isEqualToString:@"chatBoostSourceGiveaway"])
			kind = @"giveaway";
		NSNumber *userId = TGChNumber(source[@"user_id"]);
		[out addObject:@{
			@"id"                  : TGChString(boost[@"id"]),
			@"count"               : TGChNumber(boost[@"count"]),
			@"source"              : kind,
			@"user_id"             : userId,
			@"name"                : [self nameForUserId:[userId longLongValue]] ?: @"",
			@"gift_code"           : TGChString(source[@"gift_code"]),
			@"star_count"          : TGChNumber(source[@"star_count"]),
			@"giveaway_message_id" : TGChNumber(source[@"giveaway_message_id"]),
			@"is_unclaimed"        : TGChNumber(source[@"is_unclaimed"]),
			@"start_date"          : TGChNumber(boost[@"start_date"]),
			@"expiration_date"     : TGChNumber(boost[@"expiration_date"]),
		}];
	}
	return out;
}

- (void)boostsForChat:(int64_t)chatId
        onlyGiftCodes:(BOOL)onlyGiftCodes
               offset:(NSString *)offset
                limit:(NSInteger)limit
           completion:(void (^)(NSArray *boosts, NSString *nextOffset, NSInteger totalCount))completion {
	NSString *from = [offset isKindOfClass:NSString.class] ? offset : @"";
	[self request:@{ @"@type"           : @"getChatBoosts",
	                 @"chat_id"         : @(chatId),
	                 @"only_gift_codes" : @(onlyGiftCodes),
	                 @"offset"          : from,
	                 @"limit"           : @(limit > 0 ? limit : 50) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGChIsError(result)){
			completion(nil, @"", 0);
			return;
		}
		completion([self tgch_flattenBoosts:result],
		           TGChString(result[@"next_offset"]),
		           (NSInteger)[TGChNumber(result[@"total_count"]) integerValue]);
	}];
}

- (void)boostsByUser:(int64_t)userId
              inChat:(int64_t)chatId
          completion:(void (^)(NSArray *boosts))completion {
	[self request:@{ @"@type"   : @"getUserChatBoosts",
	                 @"chat_id" : @(chatId),
	                 @"user_id" : @(userId) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGChIsError(result) ? nil : [self tgch_flattenBoosts:result]);
	}];
}

- (NSDictionary *)tgch_flattenLevelFeatures:(NSDictionary *)level {
	if (![level isKindOfClass:NSDictionary.class])
		return nil;
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	NSArray *keys = @[ @"level", @"story_per_day_count", @"custom_emoji_reaction_count",
	                   @"title_color_count", @"profile_accent_color_count",
	                   @"accent_color_count", @"chat_theme_background_count",
	                   @"can_set_profile_background_custom_emoji",
	                   @"can_set_background_custom_emoji", @"can_set_emoji_status",
	                   @"can_set_custom_background", @"can_set_custom_emoji_sticker_set",
	                   @"can_enable_automatic_translation", @"can_recognize_speech",
	                   @"can_disable_sponsored_messages" ];
	for (NSString *key in keys)
		out[key] = TGChNumber(level[key]);
	return out;
}

- (void)boostLevelFeaturesForChannel:(BOOL)isChannel
                               level:(NSInteger)level
                          completion:(void (^)(NSDictionary *features))completion {
	[self request:@{ @"@type"      : @"getChatBoostLevelFeatures",
	                 @"is_channel" : @(isChannel),
	                 @"level"      : @(level) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGChIsError(result) ? nil : [self tgch_flattenLevelFeatures:result]);
	}];
}

- (void)boostLevelFeatureTableForChannel:(BOOL)isChannel
                              completion:(void (^)(NSArray *levels, NSDictionary *minimums))completion {
	[self request:@{ @"@type" : @"getChatBoostFeatures", @"is_channel" : @(isChannel) }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGChIsError(result)){
			completion(nil, nil);
			return;
		}
		NSMutableArray *levels = [NSMutableArray array];
		for (id raw in TGChArray(result[@"features"]) ?: @[]){
			NSDictionary *flat = [self tgch_flattenLevelFeatures:TGChDict(raw)];
			if (flat) [levels addObject:flat];
		}
		NSMutableDictionary *minimums = [NSMutableDictionary dictionary];
		NSArray *keys = @[ @"min_profile_background_custom_emoji_boost_level",
		                   @"min_background_custom_emoji_boost_level",
		                   @"min_emoji_status_boost_level",
		                   @"min_chat_theme_background_boost_level",
		                   @"min_custom_background_boost_level",
		                   @"min_custom_emoji_sticker_set_boost_level",
		                   @"min_automatic_translation_boost_level",
		                   @"min_speech_recognition_boost_level",
		                   @"min_sponsored_message_disable_boost_level" ];
		for (NSString *key in keys)
			minimums[key] = TGChNumber(result[key]);
		completion(levels, minimums);
	}];
}

@end

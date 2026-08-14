#import "TGClient+Private.h"
#import "TGClient+Groups.h"

static NSDictionary *TGDict(id value) {
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSArray *TGArray(id value) {
	return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static NSString *TGString(id value) {
	return [value isKindOfClass:[NSString class]] ? value : @"";
}

static BOOL TGIsError(NSDictionary *result) {
	return !TGDict(result) || [TGString(result[@"@type"]) isEqualToString:@"error"];
}

static NSDictionary *TGUserSender(int64_t userId) {
	return @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)};
}

static NSArray *TGPermissionKeys(void) {
	static NSArray *keys = nil;
	if (!keys)
		keys = @[@"can_send_basic_messages", @"can_send_audios", @"can_send_documents",
				  @"can_send_photos", @"can_send_videos", @"can_send_video_notes",
				  @"can_send_voice_notes", @"can_send_polls", @"can_send_other_messages",
				  @"can_add_link_previews", @"can_react_to_messages", @"can_edit_tag",
				  @"can_change_info", @"can_invite_users", @"can_pin_messages",
				  @"can_create_topics"];
	return keys;
}

static NSArray *TGAdminRightKeys(void) {
	static NSArray *keys = nil;
	if (!keys)
		keys = @[@"can_manage_chat", @"can_change_info", @"can_post_messages",
				  @"can_edit_messages", @"can_delete_messages", @"can_invite_users",
				  @"can_restrict_members", @"can_pin_messages", @"can_manage_topics",
				  @"can_promote_members", @"can_manage_video_chats", @"can_post_stories",
				  @"can_edit_stories", @"can_delete_stories", @"is_anonymous"];
	return keys;
}

static NSDictionary *TGBuildFlags(NSDictionary *source, NSArray *keys, NSString *type) {
	NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:keys.count + 1];
	out[@"@type"] = type;
	for (NSString *key in keys)
		out[key] = [source[key] boolValue] ? @YES : @NO;
	return out;
}

static NSDictionary *TGReadFlags(NSDictionary *source, NSArray *keys) {
	NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:keys.count];
	for (NSString *key in keys)
		out[key] = [source[key] boolValue] ? @YES : @NO;
	return out;
}

static NSString *TGStatusName(NSString *type) {
	if ([type isEqualToString:@"chatMemberStatusCreator"])       return @"creator";
	if ([type isEqualToString:@"chatMemberStatusAdministrator"]) return @"administrator";
	if ([type isEqualToString:@"chatMemberStatusMember"])        return @"member";
	if ([type isEqualToString:@"chatMemberStatusRestricted"])    return @"restricted";
	if ([type isEqualToString:@"chatMemberStatusBanned"])        return @"banned";
	return @"left";
}

static NSDictionary *TGSupergroupFilter(NSString *filter, NSString *query) {
	NSString *text = query ?: @"";
	if ([filter isEqualToString:@"administrators"])
		return @{@"@type" : @"supergroupMembersFilterAdministrators"};
	if ([filter isEqualToString:@"restricted"])
		return @{@"@type" : @"supergroupMembersFilterRestricted", @"query" : text};
	if ([filter isEqualToString:@"banned"])
		return @{@"@type" : @"supergroupMembersFilterBanned", @"query" : text};
	if ([filter isEqualToString:@"bots"])
		return @{@"@type" : @"supergroupMembersFilterBots"};
	if ([filter isEqualToString:@"contacts"])
		return @{@"@type" : @"supergroupMembersFilterContacts", @"query" : text};
	if (text.length)
		return @{@"@type" : @"supergroupMembersFilterSearch", @"query" : text};
	return @{@"@type" : @"supergroupMembersFilterRecent"};
}

static NSDictionary *TGChatMembersFilter(NSString *filter) {
	if ([filter isEqualToString:@"administrators"])
		return @{@"@type" : @"chatMembersFilterAdministrators"};
	if ([filter isEqualToString:@"restricted"])
		return @{@"@type" : @"chatMembersFilterRestricted"};
	if ([filter isEqualToString:@"banned"])
		return @{@"@type" : @"chatMembersFilterBanned"};
	if ([filter isEqualToString:@"bots"])
		return @{@"@type" : @"chatMembersFilterBots"};
	if ([filter isEqualToString:@"contacts"])
		return @{@"@type" : @"chatMembersFilterContacts"};
	return @{@"@type" : @"chatMembersFilterMembers"};
}

static NSDictionary *TGFlattenInviteLink(NSDictionary *link) {
	if (!TGDict(link) || ![TGString(link[@"@type"]) isEqualToString:@"chatInviteLink"])
		return nil;
	return @{
		@"link"                    : TGString(link[@"invite_link"]),
		@"name"                    : TGString(link[@"name"]),
		@"creatorUserId"           : link[@"creator_user_id"] ?: @(0),
		@"date"                    : link[@"date"] ?: @(0),
		@"expirationDate"          : link[@"expiration_date"] ?: @(0),
		@"memberLimit"             : link[@"member_limit"] ?: @(0),
		@"memberCount"             : link[@"member_count"] ?: @(0),
		@"pendingJoinRequestCount" : link[@"pending_join_request_count"] ?: @(0),
		@"createsJoinRequest"      : @([link[@"creates_join_request"] boolValue]),
		@"isPrimary"               : @([link[@"is_primary"] boolValue]),
		@"isRevoked"               : @([link[@"is_revoked"] boolValue]),
	};
}

@interface TGClient (GroupsPrivate)
- (NSDictionary *)tg_flattenMember:(NSDictionary *)member;
- (NSArray *)tg_flattenMembers:(NSArray *)members;
- (void)tg_group:(int64_t)chatId
      completion:(void (^)(NSString *kind, NSNumber *groupId, NSDictionary *chat))completion;
- (void)tg_send:(NSDictionary *)request completion:(void (^)(BOOL ok))completion;
- (void)tg_supergroupToggle:(NSString *)method
                       chat:(int64_t)chatId
                     fields:(NSDictionary *)fields
                 completion:(void (^)(BOOL ok))completion;
- (void)tg_setStatus:(NSDictionary *)status
              ofUser:(int64_t)userId
             inGroup:(int64_t)chatId
          completion:(void (^)(BOOL ok))completion;
- (void)tg_link:(NSDictionary *)request completion:(void (^)(NSDictionary *link))completion;
@end

@implementation TGClient (Groups)

- (NSDictionary *)tg_flattenMember:(NSDictionary *)member {
	if (!TGDict(member))
		return nil;
	int64_t userId = [TGDict(member[@"member_id"])[@"user_id"] longLongValue];
	NSDictionary *status = TGDict(member[@"status"]) ?: @{};
	NSString *type = TGString(status[@"@type"]);
	NSInteger untilDate = 0;
	if ([type isEqualToString:@"chatMemberStatusRestricted"])
		untilDate = [status[@"restricted_until_date"] integerValue];
	else if ([type isEqualToString:@"chatMemberStatusBanned"])
		untilDate = [status[@"banned_until_date"] integerValue];
	else if ([type isEqualToString:@"chatMemberStatusMember"])
		untilDate = [status[@"member_until_date"] integerValue];

	NSString *name = TGStatusName(type);
	NSDictionary *rights = TGDict(status[@"rights"]);
	return @{
		@"id"            : @(userId),
		@"name"          : [self nameForUserId:userId] ?: @"",
		@"status"        : name,
		@"customTitle"   : TGString(member[@"tag"]),
		@"isOwner"       : @([name isEqualToString:@"creator"]),
		@"isAdmin"       : @([name isEqualToString:@"creator"] ||
							 [name isEqualToString:@"administrator"]),
		@"untilDate"     : @(untilDate),
		@"inviterUserId" : member[@"inviter_user_id"] ?: @(0),
		@"joinedDate"    : member[@"joined_chat_date"] ?: @(0),
		@"canBeEdited"   : @([status[@"can_be_edited"] boolValue]),
		@"rights"        : rights ? TGReadFlags(rights, TGAdminRightKeys()) : @{},
		@"permissions"   : TGDict(status[@"permissions"]) ?
						   TGReadFlags(status[@"permissions"], TGPermissionKeys()) : @{},
	};
}

- (NSArray *)tg_flattenMembers:(NSArray *)members {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *member in TGArray(members)) {
		NSDictionary *flat = [self tg_flattenMember:member];
		if (flat && [flat[@"id"] longLongValue])
			[out addObject:flat];
	}
	return out;
}

/// Resolves a chat id to the group behind it. `kind` is "basic", "super" or
/// nil; `groupId` is the basic-group or supergroup id.
- (void)tg_group:(int64_t)chatId
      completion:(void (^)(NSString *kind, NSNumber *groupId, NSDictionary *chat))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (TGIsError(chat)) {
			completion(nil, nil, nil);
			return;
		}
		NSDictionary *type = TGDict(chat[@"type"]) ?: @{};
		NSString *kind = TGString(type[@"@type"]);
		if ([kind isEqualToString:@"chatTypeSupergroup"])
			completion(@"super", type[@"supergroup_id"], chat);
		else if ([kind isEqualToString:@"chatTypeBasicGroup"])
			completion(@"basic", type[@"basic_group_id"], chat);
		else
			completion(nil, nil, chat);
	}];
}

- (void)tg_send:(NSDictionary *)request completion:(void (^)(BOOL ok))completion {
	[self request:request completion:^(NSDictionary *result){
		if (completion)
			completion(!TGIsError(result));
	}];
}

- (void)tg_supergroupToggle:(NSString *)method
                       chat:(int64_t)chatId
                     fields:(NSDictionary *)fields
                 completion:(void (^)(BOOL ok))completion {
	__weak typeof(self) weakSelf = self;
	[self tg_group:chatId completion:^(NSString *kind, NSNumber *groupId, NSDictionary *chat){
		if (![kind isEqualToString:@"super"]) {
			if (completion) completion(NO);
			return;
		}
		NSMutableDictionary *request = [NSMutableDictionary dictionary];
		request[@"@type"] = method;
		request[@"supergroup_id"] = groupId;
		[request addEntriesFromDictionary:fields ?: @{}];
		[weakSelf tg_send:request completion:completion];
	}];
}

#pragma mark - creating groups

- (void)createBasicGroupWithTitle:(NSString *)title
                          userIds:(NSArray *)userIds
                       completion:(void (^)(int64_t, NSArray *))completion {
	[self request:@{
		@"@type"    : @"createNewBasicGroupChat",
		@"user_ids" : userIds ?: @[],
		@"title"    : title ?: @"",
		@"message_auto_delete_time" : @(0),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)) {
			completion(0, @[]);
			return;
		}
		NSMutableArray *failed = [NSMutableArray array];
		NSDictionary *failure = TGDict(result[@"failed_to_add_members"]);
		for (NSDictionary *entry in TGArray(failure[@"failed_to_add_members"])) {
			if (TGDict(entry) && entry[@"user_id"])
				[failed addObject:entry[@"user_id"]];
		}
		completion([result[@"chat_id"] longLongValue], failed);
	}];
}

- (void)createSupergroupWithTitle:(NSString *)title
                      description:(NSString *)description
                        isChannel:(BOOL)isChannel
                          isForum:(BOOL)isForum
                       completion:(void (^)(int64_t))completion {
	[self request:@{
		@"@type"       : @"createNewSupergroupChat",
		@"title"       : title ?: @"",
		@"is_forum"    : @(isForum),
		@"is_channel"  : @(isChannel),
		@"description" : description ?: @"",
		@"message_auto_delete_time" : @(0),
		@"for_import"  : @NO,
	} completion:^(NSDictionary *chat){
		if (completion)
			completion(TGIsError(chat) ? 0 : [chat[@"id"] longLongValue]);
	}];
}

- (void)upgradeBasicGroupToSupergroup:(int64_t)chatId
                           completion:(void (^)(int64_t))completion {
	[self request:@{@"@type" : @"upgradeBasicGroupChatToSupergroupChat",
					@"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (completion)
			completion(TGIsError(chat) ? 0 : [chat[@"id"] longLongValue]);
	}];
}

#pragma mark - group info

- (void)groupInfoForChat:(int64_t)chatId
              completion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self tg_group:chatId completion:^(NSString *kind, NSNumber *groupId, NSDictionary *chat){
		if (!kind) {
			if (completion) completion(nil);
			return;
		}
		NSString *title = TGString(chat[@"title"]);
		BOOL canBeEdited = [chat[@"can_be_edited"] boolValue];

		if ([kind isEqualToString:@"basic"]) {
			[weakSelf request:@{@"@type" : @"getBasicGroupFullInfo",
								@"basic_group_id" : groupId}
				   completion:^(NSDictionary *full){
				[weakSelf request:@{@"@type" : @"getBasicGroup",
									@"basic_group_id" : groupId}
					   completion:^(NSDictionary *group){
					if (!completion)
						return;
					NSDictionary *link = TGFlattenInviteLink(TGDict(full[@"invite_link"]));
					completion(@{
						@"id"            : @(chatId),
						@"title"         : title,
						@"description"   : TGString(full[@"description"]),
						@"isSupergroup"  : @NO,
						@"isChannel"     : @NO,
						@"isForum"       : @NO,
						@"isBroadcastGroup" : @NO,
						@"memberCount"   : TGIsError(group) ? @(TGArray(full[@"members"]).count)
														   : (group[@"member_count"] ?: @(0)),
						@"adminCount"    : @(0),
						@"restrictedCount" : @(0),
						@"bannedCount"   : @(0),
						@"slowModeDelay" : @(0),
						@"username"      : @"",
						@"inviteLink"    : link[@"link"] ?: @"",
						@"linkedChatId"  : @(0),
						@"stickerSetId"  : @(0),
						@"isAllHistoryAvailable" : @YES,
						@"hasHiddenMembers" : @NO,
						@"canHideMembers"   : @([full[@"can_hide_members"] boolValue]),
						@"hasAggressiveAntiSpam" : @NO,
						@"canToggleAggressiveAntiSpam" :
							@([full[@"can_toggle_aggressive_anti_spam"] boolValue]),
						@"canSetStickerSet" : @NO,
						@"canGetMembers"    : @YES,
						@"pendingJoinRequests" : @(0),
						@"myStatus"      : TGIsError(group) ? @"member"
									: TGStatusName(TGString(TGDict(group[@"status"])[@"@type"])),
						@"canBeEdited"   : @(canBeEdited),
						@"upgradedFromBasicGroup" : @(0),
					});
				}];
			}];
			return;
		}

		[weakSelf request:@{@"@type" : @"getSupergroup", @"supergroup_id" : groupId}
			   completion:^(NSDictionary *group){
			[weakSelf request:@{@"@type" : @"getSupergroupFullInfo",
								@"supergroup_id" : groupId}
				   completion:^(NSDictionary *full){
				if (!completion)
					return;
				NSDictionary *link = TGFlattenInviteLink(TGDict(full[@"invite_link"]));
				NSArray *usernames = TGArray(TGDict(group[@"usernames"])[@"active_usernames"]);
				NSString *username = usernames.count &&
									 [usernames[0] isKindOfClass:[NSString class]]
									 ? usernames[0] : @"";
				completion(@{
					@"id"            : @(chatId),
					@"title"         : title,
					@"description"   : TGString(full[@"description"]),
					@"isSupergroup"  : @YES,
					@"isChannel"     : @([group[@"is_channel"] boolValue]),
					@"isForum"       : @([group[@"is_forum"] boolValue]),
					@"isBroadcastGroup" : @([group[@"is_broadcast_group"] boolValue]),
					@"memberCount"   : full[@"member_count"] ?: (group[@"member_count"] ?: @(0)),
					@"adminCount"    : full[@"administrator_count"] ?: @(0),
					@"restrictedCount" : full[@"restricted_count"] ?: @(0),
					@"bannedCount"   : full[@"banned_count"] ?: @(0),
					@"slowModeDelay" : full[@"slow_mode_delay"] ?: @(0),
					@"username"      : username,
					@"inviteLink"    : link[@"link"] ?: @"",
					@"linkedChatId"  : full[@"linked_chat_id"] ?: @(0),
					@"stickerSetId"  : full[@"sticker_set_id"] ?: @(0),
					@"isAllHistoryAvailable" : @([full[@"is_all_history_available"] boolValue]),
					@"hasHiddenMembers" : @([full[@"has_hidden_members"] boolValue]),
					@"canHideMembers"   : @([full[@"can_hide_members"] boolValue]),
					@"hasAggressiveAntiSpam" :
						@([full[@"has_aggressive_anti_spam_enabled"] boolValue]),
					@"canToggleAggressiveAntiSpam" :
						@([full[@"can_toggle_aggressive_anti_spam"] boolValue]),
					@"canSetStickerSet" : @([full[@"can_set_sticker_set"] boolValue]),
					@"canGetMembers"    : @([full[@"can_get_members"] boolValue]),
					@"pendingJoinRequests" : link[@"pendingJoinRequestCount"] ?: @(0),
					@"myStatus"      : TGStatusName(TGString(TGDict(group[@"status"])[@"@type"])),
					@"canBeEdited"   : @(canBeEdited),
					@"upgradedFromBasicGroup" : full[@"upgraded_from_basic_group_id"] ?: @(0),
				});
			}];
		}];
	}];
}

- (void)setGroupChat:(int64_t)chatId title:(NSString *)title
          completion:(void (^)(BOOL))completion {
	[self tg_send:@{@"@type" : @"setChatTitle",
					@"chat_id" : @(chatId),
					@"title" : title ?: @""}
	   completion:completion];
}

- (void)setGroupChat:(int64_t)chatId description:(NSString *)description
          completion:(void (^)(BOOL))completion {
	[self tg_send:@{@"@type" : @"setChatDescription",
					@"chat_id" : @(chatId),
					@"description" : description ?: @""}
	   completion:completion];
}

- (void)setGroupChat:(int64_t)chatId photoAtPath:(NSString *)path
          completion:(void (^)(BOOL))completion {
	NSMutableDictionary *request = [NSMutableDictionary dictionary];
	request[@"@type"] = @"setChatPhoto";
	request[@"chat_id"] = @(chatId);
	if (path.length)
		request[@"photo"] = @{
			@"@type" : @"inputChatPhotoStatic",
			@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path},
		};
	[self tg_send:request completion:completion];
}

#pragma mark - members

- (void)membersInGroup:(int64_t)chatId
                filter:(NSString *)filter
                offset:(NSInteger)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *, NSInteger))completion {
	__weak typeof(self) weakSelf = self;
	NSInteger wanted = limit > 0 ? limit : 50;
	[self tg_group:chatId completion:^(NSString *kind, NSNumber *groupId, NSDictionary *chat){
		TGClient *me = weakSelf;
		if (!me || !kind) {
			if (completion) completion(@[], 0);
			return;
		}
		if ([kind isEqualToString:@"super"]) {
			[me request:@{
				@"@type"         : @"getSupergroupMembers",
				@"supergroup_id" : groupId,
				@"filter"        : TGSupergroupFilter(filter, nil),
				@"offset"        : @(offset),
				@"limit"         : @(wanted),
			} completion:^(NSDictionary *result){
				if (!completion)
					return;
				if (TGIsError(result)) {
					completion(@[], 0);
					return;
				}
				completion([me tg_flattenMembers:result[@"members"]],
						   [result[@"total_count"] integerValue]);
			}];
			return;
		}
		[me request:@{@"@type" : @"getBasicGroupFullInfo", @"basic_group_id" : groupId}
		 completion:^(NSDictionary *full){
			if (!completion)
				return;
			NSArray *all = [me tg_flattenMembers:TGDict(full) ? full[@"members"] : nil];
			NSMutableArray *filtered = [NSMutableArray array];
			for (NSDictionary *member in all) {
				if ([filter isEqualToString:@"administrators"] &&
					![member[@"isAdmin"] boolValue])
					continue;
				if ([filter isEqualToString:@"banned"] ||
					[filter isEqualToString:@"restricted"])
					continue;
				[filtered addObject:member];
			}
			NSInteger total = (NSInteger)filtered.count;
			if (offset > 0 && offset < (NSInteger)filtered.count)
				filtered = [[filtered subarrayWithRange:
							 NSMakeRange(offset, filtered.count - offset)] mutableCopy];
			else if (offset > 0)
				filtered = [NSMutableArray array];
			if ((NSInteger)filtered.count > wanted)
				filtered = [[filtered subarrayWithRange:NSMakeRange(0, wanted)] mutableCopy];
			completion(filtered, total);
		}];
	}];
}

- (void)searchMembersInGroup:(int64_t)chatId
                       query:(NSString *)query
                      filter:(NSString *)filter
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"   : @"searchChatMembers",
		@"chat_id" : @(chatId),
		@"query"   : query ?: @"",
		@"limit"   : @(limit > 0 ? limit : 50),
		@"filter"  : TGChatMembersFilter(filter),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *me = weakSelf;
		if (!me || TGIsError(result)) {
			completion(@[]);
			return;
		}
		completion([me tg_flattenMembers:result[@"members"]]);
	}];
}

- (void)memberStatusOfUser:(int64_t)userId
                   inGroup:(int64_t)chatId
                completion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChatMember",
					@"chat_id" : @(chatId),
					@"member_id" : TGUserSender(userId)}
	   completion:^(NSDictionary *member){
		if (!completion)
			return;
		TGClient *me = weakSelf;
		completion((me && !TGIsError(member)) ? [me tg_flattenMember:member] : nil);
	}];
}

- (void)groupMemberCount:(int64_t)chatId completion:(void (^)(NSInteger))completion {
	[self groupInfoForChat:chatId completion:^(NSDictionary *info){
		if (completion)
			completion([info[@"memberCount"] integerValue]);
	}];
}

- (void)addMembers:(NSArray *)userIds
           toGroup:(int64_t)chatId
        completion:(void (^)(NSArray *))completion {
	if (userIds.count == 0) {
		if (completion) completion(@[]);
		return;
	}
	NSDictionary *request;
	if (userIds.count == 1)
		request = @{@"@type" : @"addChatMember",
					@"chat_id" : @(chatId),
					@"user_id" : userIds[0],
					@"forward_limit" : @(100)};
	else
		request = @{@"@type" : @"addChatMembers",
					@"chat_id" : @(chatId),
					@"user_ids" : userIds};
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)) {
			completion(userIds);
			return;
		}
		NSMutableArray *failed = [NSMutableArray array];
		for (NSDictionary *entry in TGArray(result[@"failed_to_add_members"])) {
			if (TGDict(entry) && entry[@"user_id"])
				[failed addObject:entry[@"user_id"]];
		}
		completion(failed);
	}];
}

- (void)tg_setStatus:(NSDictionary *)status
             ofUser:(int64_t)userId
            inGroup:(int64_t)chatId
         completion:(void (^)(BOOL ok))completion {
	[self tg_send:@{@"@type" : @"setChatMemberStatus",
					@"chat_id" : @(chatId),
					@"member_id" : TGUserSender(userId),
					@"status" : status}
	   completion:completion];
}

- (void)removeMember:(int64_t)userId
           fromGroup:(int64_t)chatId
          completion:(void (^)(BOOL))completion {
	[self tg_setStatus:@{@"@type" : @"chatMemberStatusLeft"}
				ofUser:userId inGroup:chatId completion:completion];
}

- (void)banMember:(int64_t)userId
          inGroup:(int64_t)chatId
        untilDate:(NSInteger)untilDate
   revokeMessages:(BOOL)revokeMessages
       completion:(void (^)(BOOL))completion {
	[self tg_send:@{
		@"@type"             : @"banChatMember",
		@"chat_id"           : @(chatId),
		@"member_id"         : TGUserSender(userId),
		@"banned_until_date" : @(untilDate),
		@"revoke_messages"   : @(revokeMessages),
	} completion:completion];
}

- (void)unbanMember:(int64_t)userId
            inGroup:(int64_t)chatId
         completion:(void (^)(BOOL))completion {
	[self tg_setStatus:@{@"@type" : @"chatMemberStatusLeft"}
				ofUser:userId inGroup:chatId completion:completion];
}

- (void)bannedMembersInGroup:(int64_t)chatId
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *))completion {
	[self membersInGroup:chatId filter:@"banned" offset:0 limit:limit
			  completion:^(NSArray *members, NSInteger total){
		if (completion)
			completion(members);
	}];
}

- (void)deleteAllMessagesFromUser:(int64_t)userId inGroup:(int64_t)chatId {
	[self send:@{@"@type" : @"deleteChatMessagesBySender",
				 @"chat_id" : @(chatId),
				 @"sender_id" : TGUserSender(userId)}];
}

- (void)restrictMember:(int64_t)userId
               inGroup:(int64_t)chatId
           permissions:(NSDictionary *)permissions
             untilDate:(NSInteger)untilDate
            completion:(void (^)(BOOL))completion {
	[self tg_setStatus:@{
		@"@type"                 : @"chatMemberStatusRestricted",
		@"is_member"             : @YES,
		@"restricted_until_date" : @(untilDate),
		@"permissions"           : TGBuildFlags(permissions ?: @{}, TGPermissionKeys(),
												@"chatPermissions"),
	} ofUser:userId inGroup:chatId completion:completion];
}

#pragma mark - administrators

- (void)administratorsInGroup:(int64_t)chatId
                   completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChatAdministrators", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *me = weakSelf;
		if (!me || TGIsError(result)) {
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *admin in TGArray(result[@"administrators"])) {
			if (!TGDict(admin))
				continue;
			int64_t userId = [admin[@"user_id"] longLongValue];
			NSDictionary *flat = @{
				@"id"          : @(userId),
				@"name"        : [me nameForUserId:userId] ?: @"",
				@"customTitle" : TGString(admin[@"custom_title"]),
				@"isOwner"     : @([admin[@"is_owner"] boolValue]),
				@"canBeEdited" : @([admin[@"can_be_edited"] boolValue]),
			};
			if ([admin[@"is_owner"] boolValue])
				[out insertObject:flat atIndex:0];
			else
				[out addObject:flat];
		}
		completion(out);
	}];
}

- (void)promoteMember:(int64_t)userId
              inGroup:(int64_t)chatId
               rights:(NSDictionary *)rights
          customTitle:(NSString *)customTitle
           completion:(void (^)(BOOL))completion {
	[self tg_setStatus:@{
		@"@type"        : @"chatMemberStatusAdministrator",
		@"can_be_edited": @YES,
		@"rights"       : TGBuildFlags(rights ?: @{}, TGAdminRightKeys(),
									   @"chatAdministratorRights"),
	} ofUser:userId inGroup:chatId completion:completion];
}

- (void)dismissAdmin:(int64_t)userId
             inGroup:(int64_t)chatId
          completion:(void (^)(BOOL))completion {
	[self tg_setStatus:@{@"@type" : @"chatMemberStatusMember",
						 @"member_until_date" : @(0)}
				ofUser:userId inGroup:chatId completion:completion];
}

- (void)transferOwnershipOfGroup:(int64_t)chatId
                          toUser:(int64_t)userId
                        password:(NSString *)password
                      completion:(void (^)(BOOL))completion {
	[self tg_send:@{@"@type" : @"transferChatOwnership",
					@"chat_id" : @(chatId),
					@"user_id" : @(userId),
					@"password" : password ?: @""}
	   completion:completion];
}

#pragma mark - default permissions

- (void)defaultPermissionsInGroup:(int64_t)chatId
                       completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (!completion)
			return;
		if (TGIsError(chat)) {
			completion(nil);
			return;
		}
		completion(TGReadFlags(TGDict(chat[@"permissions"]) ?: @{}, TGPermissionKeys()));
	}];
}

- (void)setDefaultPermissions:(NSDictionary *)permissions
                      inGroup:(int64_t)chatId
                   completion:(void (^)(BOOL))completion {
	[self tg_send:@{@"@type" : @"setChatPermissions",
					@"chat_id" : @(chatId),
					@"permissions" : TGBuildFlags(permissions ?: @{}, TGPermissionKeys(),
												  @"chatPermissions")}
	   completion:completion];
}

#pragma mark - public groups

- (void)checkGroupUsername:(NSString *)username
                   forChat:(int64_t)chatId
                completion:(void (^)(NSString *))completion {
	[self request:@{@"@type" : @"checkChatUsername",
					@"chat_id" : @(chatId),
					@"username" : username ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = TGString(TGDict(result)[@"@type"]);
		if ([type isEqualToString:@"checkChatUsernameResultOk"])
			completion(@"ok");
		else if ([type isEqualToString:@"checkChatUsernameResultUsernameInvalid"])
			completion(@"invalid");
		else if ([type isEqualToString:@"checkChatUsernameResultUsernameOccupied"])
			completion(@"occupied");
		else if ([type isEqualToString:@"checkChatUsernameResultUsernamePurchasable"])
			completion(@"purchasable");
		else if ([type isEqualToString:@"checkChatUsernameResultPublicChatsTooMany"])
			completion(@"too-many");
		else if ([type isEqualToString:@"checkChatUsernameResultPublicGroupsUnavailable"])
			completion(@"unavailable");
		else
			completion(@"error");
	}];
}

- (void)setGroupChat:(int64_t)chatId username:(NSString *)username
          completion:(void (^)(BOOL))completion {
	[self tg_supergroupToggle:@"setSupergroupUsername"
						 chat:chatId
					   fields:@{@"username" : username ?: @""}
				   completion:completion];
}

- (void)setGroupChat:(int64_t)chatId username:(NSString *)username
             active:(BOOL)active
          completion:(void (^)(BOOL))completion {
	[self tg_supergroupToggle:@"toggleSupergroupUsernameIsActive"
						 chat:chatId
					   fields:@{@"username" : username ?: @"", @"is_active" : @(active)}
				   completion:completion];
}

- (void)createdPublicChatsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getCreatedPublicChats",
					@"type" : @{@"@type" : @"publicChatTypeHasUsername"}}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *me = weakSelf;
		if (!me || TGIsError(result)) {
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSNumber *chatId in TGArray(result[@"chat_ids"])) {
			NSDictionary *info = me.chatsById[chatId];
			[out addObject:@{@"id" : chatId,
							 @"title" : TGString(info[@"title"])}];
		}
		completion(out);
	}];
}

#pragma mark - invite links

- (void)tg_link:(NSDictionary *)request completion:(void (^)(NSDictionary *link))completion {
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)) {
			completion(nil);
			return;
		}
		NSDictionary *flat = TGFlattenInviteLink(result);
		if (!flat) {
			NSArray *links = TGArray(result[@"invite_links"]);
			flat = links.count ? TGFlattenInviteLink(links[0]) : nil;
		}
		completion(flat);
	}];
}

- (void)primaryInviteLinkForGroup:(int64_t)chatId
                       completion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self groupInfoForChat:chatId completion:^(NSDictionary *info){
		NSString *existing = TGString(info[@"inviteLink"]);
		if (existing.length) {
			if (completion)
				completion(@{@"link" : existing, @"isPrimary" : @YES});
			return;
		}
		[weakSelf tg_link:@{@"@type" : @"replacePrimaryChatInviteLink",
							@"chat_id" : @(chatId)}
			   completion:completion];
	}];
}

- (void)replacePrimaryInviteLinkForGroup:(int64_t)chatId
                              completion:(void (^)(NSDictionary *))completion {
	[self tg_link:@{@"@type" : @"replacePrimaryChatInviteLink", @"chat_id" : @(chatId)}
	   completion:completion];
}

- (void)createInviteLinkInGroup:(int64_t)chatId
                           name:(NSString *)name
                 expirationDate:(NSInteger)expirationDate
                    memberLimit:(NSInteger)memberLimit
             createsJoinRequest:(BOOL)createsJoinRequest
                     completion:(void (^)(NSDictionary *))completion {
	[self tg_link:@{
		@"@type"                : @"createChatInviteLink",
		@"chat_id"              : @(chatId),
		@"name"                 : name ?: @"",
		@"expiration_date"      : @(expirationDate),
		@"member_limit"         : @(createsJoinRequest ? 0 : memberLimit),
		@"creates_join_request" : @(createsJoinRequest),
	} completion:completion];
}

- (void)editInviteLink:(NSString *)inviteLink
               inGroup:(int64_t)chatId
                  name:(NSString *)name
        expirationDate:(NSInteger)expirationDate
           memberLimit:(NSInteger)memberLimit
    createsJoinRequest:(BOOL)createsJoinRequest
            completion:(void (^)(NSDictionary *))completion {
	[self tg_link:@{
		@"@type"                : @"editChatInviteLink",
		@"chat_id"              : @(chatId),
		@"invite_link"          : inviteLink ?: @"",
		@"name"                 : name ?: @"",
		@"expiration_date"      : @(expirationDate),
		@"member_limit"         : @(createsJoinRequest ? 0 : memberLimit),
		@"creates_join_request" : @(createsJoinRequest),
	} completion:completion];
}

- (void)inviteLinksInGroup:(int64_t)chatId
                   revoked:(BOOL)revoked
                     limit:(NSInteger)limit
                completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"              : @"getChatInviteLinks",
		@"chat_id"            : @(chatId),
		@"creator_user_id"    : @(0),
		@"is_revoked"         : @(revoked),
		@"offset_date"        : @(0),
		@"offset_invite_link" : @"",
		@"limit"              : @(limit > 0 ? limit : 50),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSMutableArray *out = [NSMutableArray array];
		if (!TGIsError(result)) {
			for (NSDictionary *link in TGArray(result[@"invite_links"])) {
				NSDictionary *flat = TGFlattenInviteLink(link);
				if (flat)
					[out addObject:flat];
			}
		}
		completion(out);
	}];
}

- (void)revokeInviteLink:(NSString *)inviteLink
                 inGroup:(int64_t)chatId
              completion:(void (^)(NSDictionary *))completion {
	[self tg_link:@{@"@type" : @"revokeChatInviteLink",
					@"chat_id" : @(chatId),
					@"invite_link" : inviteLink ?: @""}
	   completion:completion];
}

- (void)deleteRevokedInviteLink:(NSString *)inviteLink inGroup:(int64_t)chatId {
	[self send:@{@"@type" : @"deleteRevokedChatInviteLink",
				 @"chat_id" : @(chatId),
				 @"invite_link" : inviteLink ?: @""}];
}

- (void)membersJoinedViaInviteLink:(NSString *)inviteLink
                           inGroup:(int64_t)chatId
                             limit:(NSInteger)limit
                        completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"       : @"getChatInviteLinkMembers",
		@"chat_id"     : @(chatId),
		@"invite_link" : inviteLink ?: @"",
		@"only_with_expired_subscription" : @NO,
		@"limit"       : @(limit > 0 ? limit : 50),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		if (me && !TGIsError(result)) {
			for (NSDictionary *member in TGArray(result[@"members"])) {
				if (!TGDict(member))
					continue;
				int64_t userId = [member[@"user_id"] longLongValue];
				[out addObject:@{
					@"id"             : @(userId),
					@"name"           : [me nameForUserId:userId] ?: @"",
					@"joinedDate"     : member[@"joined_chat_date"] ?: @(0),
					@"approverUserId" : member[@"approver_user_id"] ?: @(0),
				}];
			}
		}
		completion(out);
	}];
}

- (void)inviteLinkCountsInGroup:(int64_t)chatId
                     completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChatInviteLinkCounts", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		if (me && !TGIsError(result)) {
			for (NSDictionary *entry in TGArray(result[@"invite_link_counts"])) {
				if (!TGDict(entry))
					continue;
				int64_t userId = [entry[@"user_id"] longLongValue];
				[out addObject:@{
					@"id"               : @(userId),
					@"name"             : [me nameForUserId:userId] ?: @"",
					@"linkCount"        : entry[@"invite_link_count"] ?: @(0),
					@"revokedLinkCount" : entry[@"revoked_invite_link_count"] ?: @(0),
				}];
			}
		}
		completion(out);
	}];
}

#pragma mark - joining

- (void)previewGroupInviteLink:(NSString *)inviteLink
                    completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"checkChatInviteLink", @"invite_link" : inviteLink ?: @""}
	   completion:^(NSDictionary *info){
		if (!completion)
			return;
		if (TGIsError(info)) {
			completion(nil);
			return;
		}
		NSDictionary *photo = TGDict(info[@"photo"]);
		NSNumber *photoId = TGDict(photo[@"small"])[@"id"];
		NSString *type = TGString(TGDict(info[@"type"])[@"@type"]);
		NSMutableDictionary *out = [NSMutableDictionary dictionary];
		out[@"chatId"]      = info[@"chat_id"] ?: @(0);
		out[@"title"]       = TGString(info[@"title"]);
		out[@"description"] = TGString(info[@"description"]);
		out[@"memberCount"] = info[@"member_count"] ?: @(0);
		out[@"isChannel"]   = @([type isEqualToString:@"inviteLinkChatTypeChannel"]);
		out[@"createsJoinRequest"] = @([info[@"creates_join_request"] boolValue]);
		out[@"isPublic"]    = @([info[@"is_public"] boolValue]);
		if ([photoId isKindOfClass:[NSNumber class]])
			out[@"photoFileId"] = photoId;
		completion(out);
	}];
}

- (void)joinGroupByInviteLink:(NSString *)inviteLink
                   completion:(void (^)(int64_t, BOOL))completion {
	[self request:@{@"@type" : @"joinChatByInviteLink", @"invite_link" : inviteLink ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = TGString(TGDict(result)[@"@type"]);
		if ([type isEqualToString:@"chatJoinResultSuccess"])
			completion([result[@"chat_id"] longLongValue], NO);
		else if ([type isEqualToString:@"chatJoinResultRequestSent"])
			completion(0, YES);
		else if ([type isEqualToString:@"chat"])
			completion([result[@"id"] longLongValue], NO);
		else
			completion(0, NO);
	}];
}

- (void)joinRequestsInGroup:(int64_t)chatId
                      limit:(NSInteger)limit
                 completion:(void (^)(NSArray *, NSInteger))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"       : @"getChatJoinRequests",
		@"chat_id"     : @(chatId),
		@"invite_link" : @"",
		@"query"       : @"",
		@"limit"       : @(limit > 0 ? limit : 50),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *me = weakSelf;
		if (!me || TGIsError(result)) {
			completion(@[], 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *entry in TGArray(result[@"requests"])) {
			if (!TGDict(entry))
				continue;
			int64_t userId = [entry[@"user_id"] longLongValue];
			[out addObject:@{
				@"id"   : @(userId),
				@"name" : [me nameForUserId:userId] ?: @"",
				@"bio"  : TGString(entry[@"bio"]),
				@"date" : entry[@"date"] ?: @(0),
			}];
		}
		completion(out, [result[@"total_count"] integerValue]);
	}];
}

- (void)processJoinRequestFromUser:(int64_t)userId
                           inGroup:(int64_t)chatId
                           approve:(BOOL)approve
                        completion:(void (^)(BOOL))completion {
	[self tg_send:@{@"@type" : @"processChatJoinRequest",
					@"chat_id" : @(chatId),
					@"user_id" : @(userId),
					@"approve" : @(approve)}
	   completion:completion];
}

- (void)processAllJoinRequestsInGroup:(int64_t)chatId
                              approve:(BOOL)approve
                           completion:(void (^)(BOOL))completion {
	[self tg_send:@{@"@type" : @"processChatJoinRequests",
					@"chat_id" : @(chatId),
					@"invite_link" : @"",
					@"approve" : @(approve)}
	   completion:completion];
}

#pragma mark - group settings

- (void)setGroup:(int64_t)chatId slowModeDelay:(NSInteger)seconds
      completion:(void (^)(BOOL))completion {
	[self tg_send:@{@"@type" : @"setChatSlowModeDelay",
					@"chat_id" : @(chatId),
					@"slow_mode_delay" : @(seconds)}
	   completion:completion];
}

- (void)setGroup:(int64_t)chatId allHistoryAvailable:(BOOL)available
      completion:(void (^)(BOOL))completion {
	[self tg_supergroupToggle:@"toggleSupergroupIsAllHistoryAvailable"
						 chat:chatId
					   fields:@{@"is_all_history_available" : @(available)}
				   completion:completion];
}

- (void)setGroup:(int64_t)chatId hiddenMembers:(BOOL)hidden
      completion:(void (^)(BOOL))completion {
	[self tg_supergroupToggle:@"toggleSupergroupHasHiddenMembers"
						 chat:chatId
					   fields:@{@"has_hidden_members" : @(hidden)}
				   completion:completion];
}

- (void)setGroup:(int64_t)chatId aggressiveAntiSpam:(BOOL)enabled
      completion:(void (^)(BOOL))completion {
	[self tg_supergroupToggle:@"toggleSupergroupHasAggressiveAntiSpamEnabled"
						 chat:chatId
					   fields:@{@"has_aggressive_anti_spam_enabled" : @(enabled)}
				   completion:completion];
}

- (void)reportSpamMessages:(NSArray *)messageIds inGroup:(int64_t)chatId {
	if (messageIds.count == 0)
		return;
	__weak typeof(self) weakSelf = self;
	[self tg_group:chatId completion:^(NSString *kind, NSNumber *groupId, NSDictionary *chat){
		if (![kind isEqualToString:@"super"])
			return;
		[weakSelf send:@{@"@type" : @"reportSupergroupSpam",
						 @"supergroup_id" : groupId,
						 @"message_ids" : messageIds}];
	}];
}

- (void)setGroup:(int64_t)chatId protectedContent:(BOOL)protectedContent {
	[self send:@{@"@type" : @"toggleChatHasProtectedContent",
				 @"chat_id" : @(chatId),
				 @"has_protected_content" : @(protectedContent)}];
}

- (void)setGroup:(int64_t)chatId signMessages:(BOOL)sign
      completion:(void (^)(BOOL))completion {
	[self tg_supergroupToggle:@"toggleSupergroupSignMessages"
						 chat:chatId
					   fields:@{@"sign_messages" : @(sign),
								@"show_message_sender" : @(sign)}
				   completion:completion];
}

- (void)setGroup:(int64_t)chatId joinToSend:(BOOL)joinToSend
     joinByRequest:(BOOL)joinByRequest
      completion:(void (^)(BOOL))completion {
	__weak typeof(self) weakSelf = self;
	[self tg_supergroupToggle:@"toggleSupergroupJoinToSendMessages"
						 chat:chatId
					   fields:@{@"join_to_send_messages" : @(joinToSend)}
				   completion:^(BOOL ok){
		[weakSelf tg_supergroupToggle:@"toggleSupergroupJoinByRequest"
								 chat:chatId
							   fields:@{@"join_by_request" : @(joinByRequest),
										@"guard_bot_user_id" : @(0),
										@"apply_to_invite_links" : @NO}
						   completion:^(BOOL second){
			if (completion)
				completion(ok && second);
		}];
	}];
}

- (void)setGroup:(int64_t)chatId isForum:(BOOL)isForum
      completion:(void (^)(BOOL))completion {
	[self tg_supergroupToggle:@"toggleSupergroupIsForum"
						 chat:chatId
					   fields:@{@"is_forum" : @(isForum),
								@"has_forum_tabs" : @(isForum)}
				   completion:completion];
}

- (void)convertGroupToBroadcastGroup:(int64_t)chatId
                          completion:(void (^)(BOOL))completion {
	[self tg_supergroupToggle:@"toggleSupergroupIsBroadcastGroup"
						 chat:chatId
					   fields:nil
				   completion:completion];
}

- (void)setGroup:(int64_t)chatId stickerSetName:(NSString *)name
      completion:(void (^)(BOOL))completion {
	__weak typeof(self) weakSelf = self;
	if (name.length == 0) {
		[self tg_supergroupToggle:@"setSupergroupStickerSet"
							 chat:chatId
						   fields:@{@"sticker_set_id" : @(0)}
					   completion:completion];
		return;
	}
	[self request:@{@"@type" : @"searchStickerSet",
					@"name" : name,
					@"ignore_cache" : @NO}
	   completion:^(NSDictionary *set){
		if (TGIsError(set) || !set[@"id"]) {
			if (completion) completion(NO);
			return;
		}
		[weakSelf tg_supergroupToggle:@"setSupergroupStickerSet"
								 chat:chatId
							   fields:@{@"sticker_set_id" : set[@"id"]}
						   completion:completion];
	}];
}

- (void)suitableDiscussionGroupsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getSuitableDiscussionChats"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *me = weakSelf;
		if (!me || TGIsError(result)) {
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSNumber *chatId in TGArray(result[@"chat_ids"])) {
			NSDictionary *info = me.chatsById[chatId];
			[out addObject:@{@"id" : chatId, @"title" : TGString(info[@"title"])}];
		}
		completion(out);
	}];
}

- (void)setChannel:(int64_t)channelChatId discussionGroup:(int64_t)groupChatId
        completion:(void (^)(BOOL))completion {
	[self tg_send:@{@"@type" : @"setChatDiscussionGroup",
					@"chat_id" : @(channelChatId),
					@"discussion_chat_id" : @(groupChatId)}
	   completion:completion];
}

#pragma mark - recent actions

- (void)eventLogForGroup:(int64_t)chatId
                   query:(NSString *)query
                   limit:(NSInteger)limit
              completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"         : @"getChatEventLog",
		@"chat_id"       : @(chatId),
		@"query"         : query ?: @"",
		@"from_event_id" : @(0),
		@"limit"         : @(limit > 0 ? limit : 50),
		@"user_ids"      : @[],
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *me = weakSelf;
		if (!me || TGIsError(result)) {
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *event in TGArray(result[@"events"])) {
			if (!TGDict(event))
				continue;
			NSDictionary *action = TGDict(event[@"action"]) ?: @{};
			NSString *type = TGString(action[@"@type"]);
			if ([type hasPrefix:@"chatEvent"])
				type = [type substringFromIndex:9];
			int64_t userId = [TGDict(event[@"member_id"])[@"user_id"] longLongValue];
			[out addObject:@{
				@"id"     : [NSString stringWithFormat:@"%@", event[@"id"] ?: @(0)],
				@"date"   : event[@"date"] ?: @(0),
				@"userId" : @(userId),
				@"name"   : [me nameForUserId:userId] ?: @"",
				@"action" : type,
				@"raw"    : action,
			}];
		}
		completion(out);
	}];
}

#pragma mark - reporting

- (void)reportGroup:(int64_t)chatId
           optionId:(NSString *)optionId
               text:(NSString *)text
         completion:(void (^)(NSString *, NSString *, NSArray *, BOOL))completion {
	[self request:@{
		@"@type"       : @"reportChat",
		@"chat_id"     : @(chatId),
		@"option_id"   : optionId ?: @"",
		@"message_ids" : @[],
		@"text"        : text ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = TGString(TGDict(result)[@"@type"]);
		if ([type isEqualToString:@"reportChatResultOk"]) {
			completion(@"ok", nil, @[], NO);
			return;
		}
		if ([type isEqualToString:@"reportChatResultOptionRequired"]) {
			NSMutableArray *options = [NSMutableArray array];
			for (NSDictionary *option in TGArray(result[@"options"])) {
				if (!TGDict(option))
					continue;
				[options addObject:@{@"id" : TGString(option[@"id"]),
									 @"text" : TGString(option[@"text"])}];
			}
			completion(@"options", TGString(result[@"title"]), options, NO);
			return;
		}
		if ([type isEqualToString:@"reportChatResultTextRequired"]) {
			completion(@"text", nil, @[], [result[@"is_optional"] boolValue]);
			return;
		}
		completion(@"error", nil, @[], NO);
	}];
}

@end

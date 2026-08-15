//
// TGClient+ChatManagement - see TGClient+ChatManagement.h.
//
#import "TGClient+ChatManagement.h"
#import "TGClient+Private.h"

static BOOL TGCMFailed(NSDictionary *result) {
	return ![result isKindOfClass:NSDictionary.class] ||
			[result[@"@type"] isEqualToString:@"error"];
}

static NSDictionary *TGCMDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *TGCMArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : [NSArray array];
}

static NSString *TGCMString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSNumber *TGCMNumber(id value) {
	return [value isKindOfClass:NSNumber.class] ? value : [NSNumber numberWithInt:0];
}

// TDLib's chatPermissions field name for each key the header documents.
static NSDictionary *TGCMPermissionFields(void) {
	static NSDictionary *fields = nil;
	if (!fields)
		fields = @{
			@"sendMessages"    : @"can_send_basic_messages",
			@"sendAudios"      : @"can_send_audios",
			@"sendDocuments"   : @"can_send_documents",
			@"sendPhotos"      : @"can_send_photos",
			@"sendVideos"      : @"can_send_videos",
			@"sendVideoNotes"  : @"can_send_video_notes",
			@"sendVoiceNotes"  : @"can_send_voice_notes",
			@"sendPolls"       : @"can_send_polls",
			@"sendOther"       : @"can_send_other_messages",
			@"addLinkPreviews" : @"can_add_link_previews",
			@"reactToMessages" : @"can_react_to_messages",
			@"changeInfo"      : @"can_change_info",
			@"inviteUsers"     : @"can_invite_users",
			@"pinMessages"     : @"can_pin_messages",
			@"createTopics"    : @"can_create_topics",
		};
	return fields;
}

// TDLib's chatAdministratorRights field name for each key the header
// documents, in the order a rights screen should show them.
static NSDictionary *TGCMRightFields(void) {
	static NSDictionary *fields = nil;
	if (!fields)
		fields = @{
			@"canManageChat"       : @"can_manage_chat",
			@"canChangeInfo"       : @"can_change_info",
			@"canPostMessages"     : @"can_post_messages",
			@"canEditMessages"     : @"can_edit_messages",
			@"canDeleteMessages"   : @"can_delete_messages",
			@"canInviteUsers"      : @"can_invite_users",
			@"canRestrictMembers"  : @"can_restrict_members",
			@"canPinMessages"      : @"can_pin_messages",
			@"canManageTopics"     : @"can_manage_topics",
			@"canPromoteMembers"   : @"can_promote_members",
			@"canManageVideoChats" : @"can_manage_video_chats",
			@"canPostStories"      : @"can_post_stories",
			@"canEditStories"      : @"can_edit_stories",
			@"canDeleteStories"    : @"can_delete_stories",
			@"isAnonymous"         : @"is_anonymous",
		};
	return fields;
}

static NSDictionary *TGCMFlatRights(NSDictionary *rights, BOOL isOwner,
									BOOL isAdministrator, NSString *customTitle) {
	NSDictionary *fields = TGCMRightFields();
	NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:fields.count + 4];
	for (NSString *key in fields){
		BOOL value = isOwner;
		if (!isOwner && [rights isKindOfClass:NSDictionary.class])
			value = [TGCMNumber(rights[fields[key]]) boolValue];
		if (isOwner && [key isEqualToString:@"isAnonymous"])
			value = [TGCMNumber(rights[fields[key]]) boolValue];
		out[key] = [NSNumber numberWithBool:value];
	}
	out[@"isOwner"] = [NSNumber numberWithBool:isOwner];
	out[@"isAdministrator"] = [NSNumber numberWithBool:isOwner || isAdministrator];
	out[@"isMember"] = [NSNumber numberWithBool:isOwner || isAdministrator];
	out[@"customTitle"] = [customTitle isKindOfClass:NSString.class] ? customTitle : @"";
	return out;
}

static NSDictionary *TGCMEventFilterFields(void) {
	static NSDictionary *fields = nil;
	if (!fields)
		fields = @{
			@"messageEdits"       : @"message_edits",
			@"messageDeletions"   : @"message_deletions",
			@"messagePins"        : @"message_pins",
			@"memberJoins"        : @"member_joins",
			@"memberLeaves"       : @"member_leaves",
			@"memberInvites"      : @"member_invites",
			@"memberPromotions"   : @"member_promotions",
			@"memberRestrictions" : @"member_restrictions",
			@"infoChanges"        : @"info_changes",
			@"settingChanges"     : @"setting_changes",
			@"inviteLinkChanges"  : @"invite_link_changes",
			@"videoChatChanges"   : @"video_chat_changes",
			@"forumChanges"       : @"forum_changes",
		};
	return fields;
}

@implementation TGClient (ChatManagement)

#pragma mark - shared plumbing

- (void)cm_run:(NSDictionary *)request completion:(void (^)(BOOL ok))completion {
	[self request:request completion:^(NSDictionary *result){
		if (completion)
			completion(!TGCMFailed(result));
	}];
}

/// Resolve the supergroup behind a chat. `supergroupId` is 0 when the chat
/// is a basic group or a private conversation; `chat` is nil on failure.
- (void)cm_supergroupForChat:(int64_t)chatId
                  completion:(void (^)(int64_t supergroupId, NSDictionary *chat))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : [NSNumber numberWithLongLong:chatId]}
	   completion:^(NSDictionary *chat){
		if (TGCMFailed(chat)){
			if (completion)
				completion(0, nil);
			return;
		}
		NSDictionary *type = TGCMDict(chat[@"type"]);
		int64_t supergroupId = 0;
		if ([TGCMString(type[@"@type"]) isEqualToString:@"chatTypeSupergroup"])
			supergroupId = [TGCMNumber(type[@"supergroup_id"]) longLongValue];
		if (completion)
			completion(supergroupId, chat);
	}];
}

- (void)cm_toggleSupergroup:(NSString *)method
                       chat:(int64_t)chatId
                     fields:(NSDictionary *)fields
                 completion:(void (^)(BOOL ok))completion {
	__weak typeof(self) weakSelf = self;
	[self cm_supergroupForChat:chatId completion:^(int64_t supergroupId, NSDictionary *chat){
		if (!supergroupId){
			if (completion)
				completion(NO);
			return;
		}
		NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:fields];
		request[@"@type"] = method;
		request[@"supergroup_id"] = [NSNumber numberWithLongLong:supergroupId];
		[weakSelf cm_run:request completion:completion];
	}];
}

#pragma mark - title, description, photo

- (void)setTitle:(NSString *)title forChat:(int64_t)chatId
      completion:(void (^)(BOOL ok))completion {
	[self cm_run:@{
		@"@type"   : @"setChatTitle",
		@"chat_id" : [NSNumber numberWithLongLong:chatId],
		@"title"   : title ?: @"",
	} completion:completion];
}

- (void)setDescription:(NSString *)description forChat:(int64_t)chatId
            completion:(void (^)(BOOL ok))completion {
	[self cm_run:@{
		@"@type"       : @"setChatDescription",
		@"chat_id"     : [NSNumber numberWithLongLong:chatId],
		@"description" : description ?: @"",
	} completion:completion];
}

- (void)setPhotoAtPath:(NSString *)path forChat:(int64_t)chatId
            completion:(void (^)(BOOL ok))completion {
	if (!path.length){
		if (completion)
			completion(NO);
		return;
	}
	[self cm_run:@{
		@"@type"   : @"setChatPhoto",
		@"chat_id" : [NSNumber numberWithLongLong:chatId],
		@"photo"   : @{
			@"@type" : @"inputChatPhotoStatic",
			@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path},
		},
	} completion:completion];
}

- (void)setPreviousPhotoId:(long long)photoId forChat:(int64_t)chatId
                completion:(void (^)(BOOL ok))completion {
	[self cm_run:@{
		@"@type"   : @"setChatPhoto",
		@"chat_id" : [NSNumber numberWithLongLong:chatId],
		@"photo"   : @{
			@"@type"         : @"inputChatPhotoPrevious",
			@"chat_photo_id" : [NSNumber numberWithLongLong:photoId],
		},
	} completion:completion];
}

- (void)removePhotoForChat:(int64_t)chatId completion:(void (^)(BOOL ok))completion {
	[self cm_run:@{
		@"@type"   : @"setChatPhoto",
		@"chat_id" : [NSNumber numberWithLongLong:chatId],
	} completion:completion];
}

#pragma mark - management snapshot

- (void)managementInfoForChat:(int64_t)chatId
                   completion:(void (^)(NSDictionary *info))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : [NSNumber numberWithLongLong:chatId]}
	   completion:^(NSDictionary *chat){
		if (!completion)
			return;
		NSMutableDictionary *info = [NSMutableDictionary dictionary];
		info[@"isChannel"]             = @NO;
		info[@"isSupergroup"]          = @NO;
		info[@"isBasicGroup"]          = @NO;
		info[@"supergroupId"]          = @0;
		info[@"title"]                 = @"";
		info[@"description"]           = @"";
		info[@"username"]              = @"";
		info[@"inviteLink"]            = @"";
		info[@"members"]               = @0;
		info[@"admins"]                = @0;
		info[@"restricted"]            = @0;
		info[@"banned"]                = @0;
		info[@"slowModeDelay"]         = @0;
		info[@"isAllHistoryAvailable"] = @YES;
		info[@"hasHiddenMembers"]      = @NO;
		info[@"canHideMembers"]        = @NO;
		info[@"hasAntiSpam"]           = @NO;
		info[@"canToggleAntiSpam"]     = @NO;
		info[@"hasProtectedContent"]   = @NO;
		info[@"signMessages"]          = @NO;
		info[@"showMessageSender"]     = @NO;
		info[@"joinByRequest"]         = @NO;
		info[@"joinToSendMessages"]    = @NO;
		info[@"isForum"]               = @NO;
		info[@"pendingJoinRequests"]   = @0;

		if (TGCMFailed(chat)){
			completion(info);
			return;
		}
		info[@"title"] = TGCMString(chat[@"title"]);
		info[@"hasProtectedContent"] = @([TGCMNumber(chat[@"has_protected_content"]) boolValue]);
		NSDictionary *pending = TGCMDict(chat[@"pending_join_requests"]);
		if (pending)
			info[@"pendingJoinRequests"] = TGCMNumber(pending[@"total_count"]);

		NSDictionary *type = TGCMDict(chat[@"type"]);
		NSString *kind = TGCMString(type[@"@type"]);

		if ([kind isEqualToString:@"chatTypeBasicGroup"]){
			info[@"isBasicGroup"] = @YES;
			NSNumber *groupId = TGCMNumber(type[@"basic_group_id"]);
			[weakSelf request:@{@"@type" : @"getBasicGroupFullInfo",
								@"basic_group_id" : groupId}
				   completion:^(NSDictionary *full){
				if (!TGCMFailed(full)){
					info[@"description"] = TGCMString(full[@"description"]);
					info[@"canHideMembers"] = @([TGCMNumber(full[@"can_hide_members"]) boolValue]);
					info[@"canToggleAntiSpam"] =
							@([TGCMNumber(full[@"can_toggle_aggressive_anti_spam"]) boolValue]);
					NSDictionary *link = TGCMDict(full[@"invite_link"]);
					info[@"inviteLink"] = TGCMString(link[@"invite_link"]);
				}
				completion(info);
			}];
			return;
		}

		if (![kind isEqualToString:@"chatTypeSupergroup"]){
			completion(info);
			return;
		}

		info[@"isSupergroup"] = @YES;
		NSNumber *supergroupId = TGCMNumber(type[@"supergroup_id"]);
		info[@"supergroupId"] = supergroupId;
		[weakSelf request:@{@"@type" : @"getSupergroup", @"supergroup_id" : supergroupId}
			   completion:^(NSDictionary *group){
			if (!TGCMFailed(group)){
				info[@"isChannel"]          = @([TGCMNumber(group[@"is_channel"]) boolValue]);
				info[@"isForum"]            = @([TGCMNumber(group[@"is_forum"]) boolValue]);
				info[@"signMessages"]       = @([TGCMNumber(group[@"sign_messages"]) boolValue]);
				info[@"showMessageSender"]  = @([TGCMNumber(group[@"show_message_sender"]) boolValue]);
				info[@"joinByRequest"]      = @([TGCMNumber(group[@"join_by_request"]) boolValue]);
				info[@"joinToSendMessages"] = @([TGCMNumber(group[@"join_to_send_messages"]) boolValue]);
				NSArray *usernames = TGCMArray(TGCMDict(group[@"usernames"])[@"active_usernames"]);
				if (usernames.count && [usernames[0] isKindOfClass:NSString.class])
					info[@"username"] = usernames[0];
			}
			[weakSelf request:@{@"@type" : @"getSupergroupFullInfo",
								@"supergroup_id" : supergroupId}
				   completion:^(NSDictionary *full){
				if (!TGCMFailed(full)){
					info[@"description"]   = TGCMString(full[@"description"]);
					info[@"members"]       = TGCMNumber(full[@"member_count"]);
					info[@"admins"]        = TGCMNumber(full[@"administrator_count"]);
					info[@"restricted"]    = TGCMNumber(full[@"restricted_count"]);
					info[@"banned"]        = TGCMNumber(full[@"banned_count"]);
					info[@"slowModeDelay"] = TGCMNumber(full[@"slow_mode_delay"]);
					info[@"isAllHistoryAvailable"] =
							@([TGCMNumber(full[@"is_all_history_available"]) boolValue]);
					info[@"hasHiddenMembers"] =
							@([TGCMNumber(full[@"has_hidden_members"]) boolValue]);
					info[@"canHideMembers"] =
							@([TGCMNumber(full[@"can_hide_members"]) boolValue]);
					info[@"hasAntiSpam"] =
							@([TGCMNumber(full[@"has_aggressive_anti_spam_enabled"]) boolValue]);
					info[@"canToggleAntiSpam"] =
							@([TGCMNumber(full[@"can_toggle_aggressive_anti_spam"]) boolValue]);
					NSDictionary *link = TGCMDict(full[@"invite_link"]);
					info[@"inviteLink"] = TGCMString(link[@"invite_link"]);
				}
				completion(info);
			}];
		}];
	}];
}

#pragma mark - permissions

+ (NSArray *)permissionKeys {
	return @[@"sendMessages", @"sendAudios", @"sendDocuments", @"sendPhotos",
			 @"sendVideos", @"sendVideoNotes", @"sendVoiceNotes", @"sendPolls",
			 @"sendOther", @"addLinkPreviews", @"reactToMessages", @"changeInfo",
			 @"inviteUsers", @"pinMessages", @"createTopics"];
}

- (void)permissionsForChat:(int64_t)chatId
                completion:(void (^)(NSDictionary *permissions))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : [NSNumber numberWithLongLong:chatId]}
	   completion:^(NSDictionary *chat){
		if (!completion)
			return;
		NSDictionary *raw = TGCMFailed(chat) ? nil : TGCMDict(chat[@"permissions"]);
		NSDictionary *fields = TGCMPermissionFields();
		NSMutableDictionary *out = [NSMutableDictionary dictionary];
		for (NSString *key in fields)
			out[key] = @([TGCMNumber(raw[fields[key]]) boolValue]);
		completion(out);
	}];
}

- (void)setPermissions:(NSDictionary *)permissions forChat:(int64_t)chatId
            completion:(void (^)(BOOL ok))completion {
	NSDictionary *fields = TGCMPermissionFields();
	NSMutableDictionary *value = [NSMutableDictionary dictionary];
	value[@"@type"] = @"chatPermissions";
	for (NSString *key in fields)
		value[fields[key]] = @([TGCMNumber(permissions[key]) boolValue]);

	[self cm_run:@{
		@"@type"       : @"setChatPermissions",
		@"chat_id"     : [NSNumber numberWithLongLong:chatId],
		@"permissions" : value,
	} completion:completion];
}

#pragma mark - slow mode

+ (NSArray *)slowModePresets {
	return @[@0, @10, @30, @60, @300, @900, @3600];
}

- (void)setSlowModeDelay:(NSInteger)seconds forChat:(int64_t)chatId
              completion:(void (^)(BOOL ok))completion {
	NSInteger allowed = 0;
	for (NSNumber *preset in [TGClient slowModePresets]){
		if ([preset integerValue] <= seconds)
			allowed = [preset integerValue];
	}
	[self cm_run:@{
		@"@type"           : @"setChatSlowModeDelay",
		@"chat_id"         : [NSNumber numberWithLongLong:chatId],
		@"slow_mode_delay" : @(allowed),
	} completion:completion];
}

#pragma mark - supergroup switches

- (void)setChat:(int64_t)chatId allHistoryAvailable:(BOOL)available
     completion:(void (^)(BOOL ok))completion {
	[self cm_toggleSupergroup:@"toggleSupergroupIsAllHistoryAvailable"
						 chat:chatId
					   fields:@{@"is_all_history_available" : @(available)}
				   completion:completion];
}

- (void)setChat:(int64_t)chatId joinByRequest:(BOOL)joinByRequest
     completion:(void (^)(BOOL ok))completion {
	[self cm_toggleSupergroup:@"toggleSupergroupJoinByRequest"
						 chat:chatId
					   fields:@{@"join_by_request"        : @(joinByRequest),
								@"apply_to_invite_links"  : @YES}
				   completion:completion];
}

- (void)setChat:(int64_t)chatId joinToSendMessages:(BOOL)joinToSend
     completion:(void (^)(BOOL ok))completion {
	[self cm_toggleSupergroup:@"toggleSupergroupJoinToSendMessages"
						 chat:chatId
					   fields:@{@"join_to_send_messages" : @(joinToSend)}
				   completion:completion];
}

- (void)setChat:(int64_t)chatId signMessages:(BOOL)sign showSender:(BOOL)showSender
     completion:(void (^)(BOOL ok))completion {
	[self cm_toggleSupergroup:@"toggleSupergroupSignMessages"
						 chat:chatId
					   fields:@{@"sign_messages"       : @(sign),
								@"show_message_sender" : @(sign && showSender)}
				   completion:completion];
}

- (void)setChat:(int64_t)chatId protectedContent:(BOOL)protectedContent
     completion:(void (^)(BOOL ok))completion {
	[self cm_run:@{
		@"@type"                 : @"toggleChatHasProtectedContent",
		@"chat_id"               : [NSNumber numberWithLongLong:chatId],
		@"has_protected_content" : @(protectedContent),
	} completion:completion];
}

- (void)setChat:(int64_t)chatId hiddenMembers:(BOOL)hidden
     completion:(void (^)(BOOL ok))completion {
	[self cm_toggleSupergroup:@"toggleSupergroupHasHiddenMembers"
						 chat:chatId
					   fields:@{@"has_hidden_members" : @(hidden)}
				   completion:completion];
}

- (void)setChat:(int64_t)chatId antiSpamEnabled:(BOOL)enabled
     completion:(void (^)(BOOL ok))completion {
	[self cm_toggleSupergroup:@"toggleSupergroupHasAggressiveAntiSpamEnabled"
						 chat:chatId
					   fields:@{@"has_aggressive_anti_spam_enabled" : @(enabled)}
				   completion:completion];
}

- (void)reportNotSpamMessages:(NSArray *)messageIds inChat:(int64_t)chatId
                   completion:(void (^)(BOOL ok))completion {
	[self cm_toggleSupergroup:@"reportSupergroupSpam"
						 chat:chatId
					   fields:@{@"message_ids" : messageIds ?: @[]}
				   completion:completion];
}

- (void)reportAntiSpamFalsePositiveForMessage:(int64_t)messageId
                                       inChat:(int64_t)chatId
                                   completion:(void (^)(BOOL ok))completion {
	[self cm_toggleSupergroup:@"reportSupergroupAntiSpamFalsePositive"
						 chat:chatId
					   fields:@{@"message_id" : [NSNumber numberWithLongLong:messageId]}
				   completion:completion];
}

#pragma mark - administrators and own rights

- (void)administratorsForChat:(int64_t)chatId
                   completion:(void (^)(NSArray *administrators))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChatAdministrators",
					@"chat_id" : [NSNumber numberWithLongLong:chatId]}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCMFailed(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *owners = [NSMutableArray array];
		NSMutableArray *others = [NSMutableArray array];
		for (id raw in TGCMArray(result[@"administrators"])){
			NSDictionary *entry = TGCMDict(raw);
			if (!entry)
				continue;
			NSNumber *userId = TGCMNumber(entry[@"user_id"]);
			BOOL isOwner = [TGCMNumber(entry[@"is_owner"]) boolValue];
			NSDictionary *flat = @{
				@"userId"      : userId,
				@"name"        : [weakSelf nameForUserId:[userId longLongValue]] ?: @"",
				@"customTitle" : TGCMString(entry[@"custom_title"]),
				@"isOwner"     : @(isOwner),
				@"canBeEdited" : @([TGCMNumber(entry[@"can_be_edited"]) boolValue]),
			};
			[(isOwner ? owners : others) addObject:flat];
		}
		[owners addObjectsFromArray:others];
		completion(owners);
	}];
}

- (void)myRightsInChat:(int64_t)chatId
            completion:(void (^)(NSDictionary *rights))completion {
	int64_t myId = [TGCMNumber(self.me[@"id"]) longLongValue];
	if (!myId){
		if (completion)
			completion(TGCMFlatRights(nil, NO, NO, @""));
		return;
	}
	[self request:@{
		@"@type" : @"getChatMember",
		@"chat_id" : [NSNumber numberWithLongLong:chatId],
		@"member_id" : @{@"@type" : @"messageSenderUser",
						 @"user_id" : [NSNumber numberWithLongLong:myId]},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCMFailed(result)){
			completion(TGCMFlatRights(nil, NO, NO, @""));
			return;
		}
		NSDictionary *status = TGCMDict(result[@"status"]);
		NSString *type = TGCMString(status[@"@type"]);
		NSString *title = TGCMString(status[@"custom_title"]);
		if ([type isEqualToString:@"chatMemberStatusCreator"]){
			completion(TGCMFlatRights(status, YES, YES, title));
			return;
		}
		if ([type isEqualToString:@"chatMemberStatusAdministrator"]){
			completion(TGCMFlatRights(TGCMDict(status[@"rights"]), NO, YES, title));
			return;
		}
		BOOL isMember = [type isEqualToString:@"chatMemberStatusMember"] ||
						[type isEqualToString:@"chatMemberStatusRestricted"];
		NSMutableDictionary *out =
			[NSMutableDictionary dictionaryWithDictionary:TGCMFlatRights(nil, NO, NO, title)];
		out[@"isMember"] = @(isMember);
		completion(out);
	}];
}

- (void)canManageInviteLinksInChat:(int64_t)chatId
                        completion:(void (^)(BOOL canManage))completion {
	[self myRightsInChat:chatId completion:^(NSDictionary *rights){
		if (!completion)
			return;
		BOOL owner = [TGCMNumber(rights[@"isOwner"]) boolValue];
		BOOL invite = [TGCMNumber(rights[@"canInviteUsers"]) boolValue];
		completion(owner || invite);
	}];
}

- (void)convertChatToBroadcastGroup:(int64_t)chatId
                         completion:(void (^)(BOOL ok))completion {
	[self cm_toggleSupergroup:@"toggleSupergroupIsBroadcastGroup"
						 chat:chatId
					   fields:@{}
				   completion:completion];
}

#pragma mark - invite links

static NSDictionary *TGCMFlatInviteLink(id value) {
	NSDictionary *link = TGCMDict(value);
	if (!link)
		return nil;
	return @{
		@"link"             : TGCMString(link[@"invite_link"]),
		@"name"             : TGCMString(link[@"name"]),
		@"creatorId"        : TGCMNumber(link[@"creator_user_id"]),
		@"date"             : TGCMNumber(link[@"date"]),
		@"editDate"         : TGCMNumber(link[@"edit_date"]),
		@"expirationDate"   : TGCMNumber(link[@"expiration_date"]),
		@"memberLimit"      : TGCMNumber(link[@"member_limit"]),
		@"memberCount"      : TGCMNumber(link[@"member_count"]),
		@"pendingRequests"  : TGCMNumber(link[@"pending_join_request_count"]),
		@"requiresApproval" : @([TGCMNumber(link[@"creates_join_request"]) boolValue]),
		@"isPrimary"        : @([TGCMNumber(link[@"is_primary"]) boolValue]),
		@"isRevoked"        : @([TGCMNumber(link[@"is_revoked"]) boolValue]),
	};
}

- (void)cm_requestLink:(NSDictionary *)request
            completion:(void (^)(NSDictionary *link))completion {
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCMFailed(result)){
			completion(nil);
			return;
		}
		completion(TGCMFlatInviteLink(result));
	}];
}

- (void)primaryInviteLinkForChat:(int64_t)chatId
                      completion:(void (^)(NSString *link))completion {
	[self managementInfoForChat:chatId completion:^(NSDictionary *info){
		if (completion)
			completion(TGCMString(info[@"inviteLink"]));
	}];
}

- (void)replacePrimaryInviteLinkForChat:(int64_t)chatId
                             completion:(void (^)(NSDictionary *link))completion {
	[self cm_requestLink:@{@"@type" : @"replacePrimaryChatInviteLink",
						   @"chat_id" : [NSNumber numberWithLongLong:chatId]}
			  completion:completion];
}

- (void)inviteLinksForChat:(int64_t)chatId revoked:(BOOL)revoked
                completion:(void (^)(NSArray *links))completion {
	NSNumber *creator = TGCMNumber(self.me[@"id"]);
	[self request:@{
		@"@type"              : @"getChatInviteLinks",
		@"chat_id"            : [NSNumber numberWithLongLong:chatId],
		@"creator_user_id"    : creator,
		@"is_revoked"         : @(revoked),
		@"offset_date"        : @0,
		@"offset_invite_link" : @"",
		@"limit"              : @100,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCMFailed(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id raw in TGCMArray(result[@"invite_links"])){
			NSDictionary *flat = TGCMFlatInviteLink(raw);
			if (flat)
				[out addObject:flat];
		}
		completion(out);
	}];
}

- (void)inviteLinkCountsForChat:(int64_t)chatId
                     completion:(void (^)(NSArray *counts))completion {
	[self request:@{@"@type" : @"getChatInviteLinkCounts",
					@"chat_id" : [NSNumber numberWithLongLong:chatId]}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCMFailed(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id raw in TGCMArray(result[@"invite_link_counts"])){
			NSDictionary *entry = TGCMDict(raw);
			if (!entry)
				continue;
			[out addObject:@{
				@"userId"           : TGCMNumber(entry[@"user_id"]),
				@"linkCount"        : TGCMNumber(entry[@"invite_link_count"]),
				@"revokedLinkCount" : TGCMNumber(entry[@"revoked_invite_link_count"]),
			}];
		}
		completion(out);
	}];
}

- (void)createInviteLinkForChat:(int64_t)chatId
                           name:(NSString *)name
                 expirationDate:(NSInteger)expirationDate
                    memberLimit:(NSInteger)memberLimit
               requiresApproval:(BOOL)requiresApproval
                     completion:(void (^)(NSDictionary *link))completion {
	NSInteger limit = requiresApproval ? 0 : memberLimit;
	[self cm_requestLink:@{
		@"@type"                : @"createChatInviteLink",
		@"chat_id"              : [NSNumber numberWithLongLong:chatId],
		@"name"                 : name ?: @"",
		@"expiration_date"      : @(expirationDate),
		@"member_limit"         : @(limit),
		@"creates_join_request" : @(requiresApproval),
	} completion:completion];
}

- (void)editInviteLink:(NSString *)link
                inChat:(int64_t)chatId
                  name:(NSString *)name
        expirationDate:(NSInteger)expirationDate
           memberLimit:(NSInteger)memberLimit
      requiresApproval:(BOOL)requiresApproval
            completion:(void (^)(NSDictionary *link))completion {
	if (!link.length){
		if (completion)
			completion(nil);
		return;
	}
	NSInteger limit = requiresApproval ? 0 : memberLimit;
	[self cm_requestLink:@{
		@"@type"                : @"editChatInviteLink",
		@"chat_id"              : [NSNumber numberWithLongLong:chatId],
		@"invite_link"          : link,
		@"name"                 : name ?: @"",
		@"expiration_date"      : @(expirationDate),
		@"member_limit"         : @(limit),
		@"creates_join_request" : @(requiresApproval),
	} completion:completion];
}

- (void)inviteLink:(NSString *)link inChat:(int64_t)chatId
        completion:(void (^)(NSDictionary *info))completion {
	if (!link.length){
		if (completion)
			completion(nil);
		return;
	}
	[self cm_requestLink:@{@"@type" : @"getChatInviteLink",
						   @"chat_id" : [NSNumber numberWithLongLong:chatId],
						   @"invite_link" : link}
			  completion:completion];
}

- (void)revokeInviteLink:(NSString *)link inChat:(int64_t)chatId
              completion:(void (^)(BOOL ok))completion {
	if (!link.length){
		if (completion)
			completion(NO);
		return;
	}
	[self cm_run:@{@"@type" : @"revokeChatInviteLink",
				   @"chat_id" : [NSNumber numberWithLongLong:chatId],
				   @"invite_link" : link}
	  completion:completion];
}

- (void)deleteRevokedInviteLink:(NSString *)link inChat:(int64_t)chatId
                     completion:(void (^)(BOOL ok))completion {
	if (!link.length){
		if (completion)
			completion(NO);
		return;
	}
	[self cm_run:@{@"@type" : @"deleteRevokedChatInviteLink",
				   @"chat_id" : [NSNumber numberWithLongLong:chatId],
				   @"invite_link" : link}
	  completion:completion];
}

- (void)deleteAllRevokedInviteLinksInChat:(int64_t)chatId
                               completion:(void (^)(BOOL ok))completion {
	[self cm_run:@{@"@type" : @"deleteAllRevokedChatInviteLinks",
				   @"chat_id" : [NSNumber numberWithLongLong:chatId],
				   @"creator_user_id" : TGCMNumber(self.me[@"id"])}
	  completion:completion];
}

- (void)membersJoinedViaInviteLink:(NSString *)link
                            inChat:(int64_t)chatId
                             limit:(NSInteger)limit
                        completion:(void (^)(NSArray *members, NSInteger total))completion {
	if (!link.length){
		if (completion)
			completion(@[], 0);
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"                          : @"getChatInviteLinkMembers",
		@"chat_id"                        : [NSNumber numberWithLongLong:chatId],
		@"invite_link"                    : link,
		@"only_with_expired_subscription" : @NO,
		@"limit"                          : @(limit > 0 ? limit : 50),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCMFailed(result)){
			completion(@[], 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id raw in TGCMArray(result[@"members"])){
			NSDictionary *entry = TGCMDict(raw);
			if (!entry)
				continue;
			NSNumber *userId = TGCMNumber(entry[@"user_id"]);
			[out addObject:@{
				@"userId"     : userId,
				@"name"       : [weakSelf nameForUserId:[userId longLongValue]] ?: @"",
				@"date"       : TGCMNumber(entry[@"joined_chat_date"]),
				@"approverId" : TGCMNumber(entry[@"approver_user_id"]),
			}];
		}
		completion(out, [TGCMNumber(result[@"total_count"]) integerValue]);
	}];
}

- (void)membersJoinedViaPrimaryInviteLinkInChat:(int64_t)chatId
                                          limit:(NSInteger)limit
                                     completion:(void (^)(NSArray *members, NSInteger total))completion {
	__weak typeof(self) weakSelf = self;
	[self primaryInviteLinkForChat:chatId completion:^(NSString *link){
		if (!link.length){
			if (completion)
				completion(@[], 0);
			return;
		}
		[weakSelf membersJoinedViaInviteLink:link inChat:chatId limit:limit completion:completion];
	}];
}

#pragma mark - joining by link

- (void)previewInviteLink:(NSString *)link
               completion:(void (^)(NSDictionary *info))completion {
	if (!link.length){
		if (completion)
			completion(nil);
		return;
	}
	[self request:@{@"@type" : @"checkChatInviteLink", @"invite_link" : link}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCMFailed(result)){
			completion(nil);
			return;
		}
		NSString *kind = TGCMString(TGCMDict(result[@"type"])[@"@type"]);
		BOOL isChannel = [kind isEqualToString:@"inviteLinkChatTypeChannel"];
		NSMutableDictionary *info = [NSMutableDictionary dictionary];
		info[@"chatId"]           = TGCMNumber(result[@"chat_id"]);
		info[@"title"]            = TGCMString(result[@"title"]);
		info[@"description"]      = TGCMString(result[@"description"]);
		info[@"memberCount"]      = TGCMNumber(result[@"member_count"]);
		info[@"requiresApproval"] = @([TGCMNumber(result[@"creates_join_request"]) boolValue]);
		info[@"isPublic"]         = @([TGCMNumber(result[@"is_public"]) boolValue]);
		info[@"isChannel"]        = @(isChannel);
		NSNumber *photoId = TGCMDict(TGCMDict(result[@"photo"])[@"small"])[@"id"];
		if ([photoId isKindOfClass:NSNumber.class])
			info[@"photoFileId"] = photoId;
		completion(info);
	}];
}

- (void)joinChatByInviteLink:(NSString *)link
                  completion:(void (^)(int64_t chatId, BOOL requestSent))completion {
	if (!link.length){
		if (completion)
			completion(0, NO);
		return;
	}
	[self request:@{@"@type" : @"joinChatByInviteLink", @"invite_link" : link}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCMFailed(result)){
			completion(0, NO);
			return;
		}
		NSString *kind = TGCMString(result[@"@type"]);
		if ([kind isEqualToString:@"chatJoinResultRequestSent"]){
			completion(0, YES);
			return;
		}
		completion([TGCMNumber(result[@"chat_id"]) longLongValue], NO);
	}];
}

#pragma mark - join requests

- (void)joinRequestsForChat:(int64_t)chatId
                 inviteLink:(NSString *)inviteLink
                      query:(NSString *)query
                      limit:(NSInteger)limit
                 completion:(void (^)(NSArray *requests, NSInteger total))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"       : @"getChatJoinRequests",
		@"chat_id"     : [NSNumber numberWithLongLong:chatId],
		@"invite_link" : inviteLink ?: @"",
		@"query"       : query ?: @"",
		@"limit"       : @(limit > 0 ? limit : 50),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCMFailed(result)){
			completion(@[], 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id raw in TGCMArray(result[@"requests"])){
			NSDictionary *entry = TGCMDict(raw);
			if (!entry)
				continue;
			NSNumber *userId = TGCMNumber(entry[@"user_id"]);
			[out addObject:@{
				@"userId" : userId,
				@"name"   : [weakSelf nameForUserId:[userId longLongValue]] ?: @"",
				@"bio"    : TGCMString(entry[@"bio"]),
				@"date"   : TGCMNumber(entry[@"date"]),
			}];
		}
		completion(out, [TGCMNumber(result[@"total_count"]) integerValue]);
	}];
}

- (void)processJoinRequestFromUser:(int64_t)userId
                            inChat:(int64_t)chatId
                           approve:(BOOL)approve
                        completion:(void (^)(BOOL ok))completion {
	[self cm_run:@{
		@"@type"   : @"processChatJoinRequest",
		@"chat_id" : [NSNumber numberWithLongLong:chatId],
		@"user_id" : [NSNumber numberWithLongLong:userId],
		@"approve" : @(approve),
	} completion:completion];
}

- (void)processAllJoinRequestsInChat:(int64_t)chatId
                          inviteLink:(NSString *)inviteLink
                             approve:(BOOL)approve
                          completion:(void (^)(BOOL ok))completion {
	[self cm_run:@{
		@"@type"       : @"processChatJoinRequests",
		@"chat_id"     : [NSNumber numberWithLongLong:chatId],
		@"invite_link" : inviteLink ?: @"",
		@"approve"     : @(approve),
	} completion:completion];
}

- (void)pendingJoinRequestCountForChat:(int64_t)chatId
                            completion:(void (^)(NSInteger count))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : [NSNumber numberWithLongLong:chatId]}
	   completion:^(NSDictionary *chat){
		if (!completion)
			return;
		if (TGCMFailed(chat)){
			completion(0);
			return;
		}
		NSDictionary *pending = TGCMDict(chat[@"pending_join_requests"]);
		completion([TGCMNumber(pending[@"total_count"]) integerValue]);
	}];
}

#pragma mark - event log

/// One line describing what an event did, built from the action object.
/// Anything unrecognised falls back to the action name with the prefix and
/// the camel humps turned into words, which still reads acceptably.
static NSString *TGCMEventText(NSString *action, NSDictionary *body, NSString *who) {
	if ([action isEqualToString:@"MessageEdited"])
		return [NSString stringWithFormat:@"%@ edited a message", who];
	if ([action isEqualToString:@"MessageDeleted"])
		return [NSString stringWithFormat:@"%@ deleted a message", who];
	if ([action isEqualToString:@"MessagePinned"])
		return [NSString stringWithFormat:@"%@ pinned a message", who];
	if ([action isEqualToString:@"MessageUnpinned"])
		return [NSString stringWithFormat:@"%@ unpinned a message", who];
	if ([action isEqualToString:@"PollStopped"])
		return [NSString stringWithFormat:@"%@ stopped a poll", who];
	if ([action isEqualToString:@"MemberJoined"])
		return [NSString stringWithFormat:@"%@ joined", who];
	if ([action isEqualToString:@"MemberJoinedByInviteLink"])
		return [NSString stringWithFormat:@"%@ joined via an invite link", who];
	if ([action isEqualToString:@"MemberJoinedByRequest"])
		return [NSString stringWithFormat:@"%@ joined after approval", who];
	if ([action isEqualToString:@"MemberLeft"])
		return [NSString stringWithFormat:@"%@ left", who];
	if ([action isEqualToString:@"MemberInvited"])
		return [NSString stringWithFormat:@"%@ invited a member", who];
	if ([action isEqualToString:@"MemberPromoted"])
		return [NSString stringWithFormat:@"%@ changed admin rights", who];
	if ([action isEqualToString:@"MemberRestricted"])
		return [NSString stringWithFormat:@"%@ changed member restrictions", who];
	if ([action isEqualToString:@"TitleChanged"])
		return [NSString stringWithFormat:@"%@ changed the title to \"%@\"",
				who, TGCMString(body[@"new_title"])];
	if ([action isEqualToString:@"DescriptionChanged"])
		return [NSString stringWithFormat:@"%@ changed the description", who];
	if ([action isEqualToString:@"PhotoChanged"])
		return [NSString stringWithFormat:@"%@ changed the photo", who];
	if ([action isEqualToString:@"UsernameChanged"] ||
		[action isEqualToString:@"ActiveUsernamesChanged"])
		return [NSString stringWithFormat:@"%@ changed the public link", who];
	if ([action isEqualToString:@"PermissionsChanged"])
		return [NSString stringWithFormat:@"%@ changed the permissions", who];
	if ([action isEqualToString:@"SlowModeDelayChanged"])
		return [NSString stringWithFormat:@"%@ changed slow mode to %@s",
				who, TGCMNumber(body[@"new_slow_mode_delay"])];
	if ([action isEqualToString:@"InvitesToggled"])
		return [NSString stringWithFormat:@"%@ changed who may invite", who];
	if ([action isEqualToString:@"SignMessagesToggled"])
		return [NSString stringWithFormat:@"%@ changed signatures", who];
	if ([action isEqualToString:@"IsAllHistoryAvailableToggled"])
		return [NSString stringWithFormat:@"%@ changed history visibility", who];
	if ([action isEqualToString:@"HasProtectedContentToggled"])
		return [NSString stringWithFormat:@"%@ changed content protection", who];
	if ([action isEqualToString:@"HasAggressiveAntiSpamEnabledToggled"])
		return [NSString stringWithFormat:@"%@ changed anti-spam", who];
	if ([action isEqualToString:@"InviteLinkEdited"])
		return [NSString stringWithFormat:@"%@ edited an invite link", who];
	if ([action isEqualToString:@"InviteLinkRevoked"])
		return [NSString stringWithFormat:@"%@ revoked an invite link", who];
	if ([action isEqualToString:@"InviteLinkDeleted"])
		return [NSString stringWithFormat:@"%@ deleted an invite link", who];
	if ([action isEqualToString:@"LinkedChatChanged"])
		return [NSString stringWithFormat:@"%@ changed the linked chat", who];
	if ([action isEqualToString:@"LocationChanged"])
		return [NSString stringWithFormat:@"%@ changed the location", who];
	if ([action isEqualToString:@"StickerSetChanged"])
		return [NSString stringWithFormat:@"%@ changed the sticker set", who];
	if ([action isEqualToString:@"AvailableReactionsChanged"])
		return [NSString stringWithFormat:@"%@ changed the reactions", who];
	if ([action isEqualToString:@"IsForumToggled"])
		return [NSString stringWithFormat:@"%@ changed topics", who];
	if ([action isEqualToString:@"MessageAutoDeleteTimeChanged"])
		return [NSString stringWithFormat:@"%@ changed the auto-delete timer", who];

	NSMutableString *words = [NSMutableString string];
	for (NSUInteger i = 0; i < action.length; i++){
		unichar c = [action characterAtIndex:i];
		if (i && c >= 'A' && c <= 'Z')
			[words appendString:@" "];
		[words appendFormat:@"%C", c];
	}
	return [NSString stringWithFormat:@"%@: %@", who, [words lowercaseString]];
}

- (void)eventLogForChat:(int64_t)chatId
                  query:(NSString *)query
            fromEventId:(int64_t)fromEventId
                  limit:(NSInteger)limit
                filters:(NSArray *)filters
                userIds:(NSArray *)userIds
             completion:(void (^)(NSArray *events))completion {
	NSDictionary *fields = TGCMEventFilterFields();
	NSMutableDictionary *filter = [NSMutableDictionary dictionary];
	filter[@"@type"] = @"chatEventLogFilters";
	for (NSString *key in fields)
		filter[fields[key]] = @(!filters || [filters containsObject:key]);

	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"         : @"getChatEventLog",
		@"chat_id"       : [NSNumber numberWithLongLong:chatId],
		@"query"         : query ?: @"",
		@"from_event_id" : [NSNumber numberWithLongLong:fromEventId],
		@"limit"         : @(limit > 0 ? limit : 50),
		@"filters"       : filter,
		@"user_ids"      : userIds ?: @[],
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGCMFailed(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id raw in TGCMArray(result[@"events"])){
			NSDictionary *event = TGCMDict(raw);
			if (!event)
				continue;

			NSDictionary *sender = TGCMDict(event[@"member_id"]);
			int64_t userId = 0;
			if ([TGCMString(sender[@"@type"]) isEqualToString:@"messageSenderUser"])
				userId = [TGCMNumber(sender[@"user_id"]) longLongValue];
			NSString *name = userId ? [weakSelf nameForUserId:userId] : nil;
			if (!name.length)
				name = @"Someone";

			NSDictionary *body = TGCMDict(event[@"action"]);
			NSString *action = TGCMString(body[@"@type"]);
			if ([action hasPrefix:@"chatEvent"])
				action = [action substringFromIndex:9];

			NSDictionary *message = TGCMDict(body[@"message"]);
			if (!message)
				message = TGCMDict(body[@"new_message"]);

			[out addObject:@{
				@"eventId"          : TGCMNumber(event[@"id"]),
				@"date"             : TGCMNumber(event[@"date"]),
				@"userId"           : [NSNumber numberWithLongLong:userId],
				@"name"             : name,
				@"action"           : action,
				@"text"             : TGCMEventText(action, body, name),
				@"messageId"        : TGCMNumber(message[@"id"]),
				@"canReportNotSpam" :
					@([TGCMNumber(body[@"can_report_anti_spam_false_positive"]) boolValue]),
			}];
		}
		completion(out);
	}];
}

@end

// vim:ft=objc

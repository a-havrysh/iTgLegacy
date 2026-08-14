#import "TGClient+Private.h"
#import "TGClient+Privacy.h"

static BOOL TGPrivacyIsError(NSDictionary *result) {
	if (![result isKindOfClass:[NSDictionary class]])
		return YES;
	return [result[@"@type"] isEqualToString:@"error"];
}

static NSArray *TGPrivacyArray(id value) {
	if (![value isKindOfClass:[NSArray class]])
		return [NSArray array];
	return value;
}

static NSString *TGPrivacyString(id value) {
	if (![value isKindOfClass:[NSString class]])
		return @"";
	return value;
}

static NSNumber *TGPrivacyBool(id value) {
	if (![value isKindOfClass:[NSNumber class]])
		return @NO;
	return [value boolValue] ? @YES : @NO;
}

static NSNumber *TGPrivacyNumber(id value) {
	if (![value isKindOfClass:[NSNumber class]])
		return @0;
	return value;
}

static NSDictionary *TGPrivacySettingObject(NSString *setting) {
	return @{@"@type" : [@"userPrivacySetting" stringByAppendingString:TGPrivacyString(setting)]};
}

static NSDictionary *TGPrivacySessionDict(NSDictionary *session) {
	if (![session isKindOfClass:[NSDictionary class]])
		return nil;
	return @{
		@"id"                   : TGPrivacyNumber(session[@"id"]),
		@"appName"              : TGPrivacyString(session[@"application_name"]),
		@"appVersion"           : TGPrivacyString(session[@"application_version"]),
		@"deviceModel"          : TGPrivacyString(session[@"device_model"]),
		@"platform"             : [[TGPrivacyString(session[@"platform"])
									stringByAppendingString:@" "]
									stringByAppendingString:TGPrivacyString(session[@"system_version"])],
		@"ip"                   : TGPrivacyString(session[@"ip_address"]),
		@"location"             : TGPrivacyString(session[@"location"]),
		@"isCurrent"            : TGPrivacyBool(session[@"is_current"]),
		@"isOfficial"           : TGPrivacyBool(session[@"is_official_application"]),
		@"isUnconfirmed"        : TGPrivacyBool(session[@"is_unconfirmed"]),
		@"canAcceptCalls"       : TGPrivacyBool(session[@"can_accept_calls"]),
		@"canAcceptSecretChats" : TGPrivacyBool(session[@"can_accept_secret_chats"]),
		@"loginDate"            : TGPrivacyNumber(session[@"log_in_date"]),
		@"lastActive"           : TGPrivacyNumber(session[@"last_active_date"]),
	};
}

static NSDictionary *TGPrivacyPasswordState(NSDictionary *state) {
	if (TGPrivacyIsError(state))
		return nil;
	NSDictionary *codeInfo = state[@"recovery_email_address_code_info"];
	if (![codeInfo isKindOfClass:[NSDictionary class]])
		codeInfo = nil;
	return @{
		@"hasPassword"          : TGPrivacyBool(state[@"has_password"]),
		@"hint"                 : TGPrivacyString(state[@"password_hint"]),
		@"hasRecoveryEmail"     : TGPrivacyBool(state[@"has_recovery_email_address"]),
		@"recoveryEmailPattern" : TGPrivacyString(codeInfo[@"email_address_pattern"]),
		@"recoveryCodeLength"   : TGPrivacyNumber(codeInfo[@"length"]),
		@"loginEmailPattern"    : TGPrivacyString(state[@"login_email_address_pattern"]),
		@"pendingResetDate"     : TGPrivacyNumber(state[@"pending_reset_date"]),
	};
}

@implementation TGClient (Privacy)

+ (NSArray *)privacySettingNames {
	return [NSArray arrayWithObjects:
			@"ShowStatus",
			@"ShowProfilePhoto",
			@"ShowBio",
			@"ShowPhoneNumber",
			@"ShowLinkInForwardedMessages",
			@"AllowChatInvites",
			@"AllowCalls",
			@"AllowPeerToPeerCalls",
			@"AllowFindingByPhoneNumber",
			nil];
}

+ (NSString *)titleForPrivacySetting:(NSString *)setting {
	NSDictionary *titles = @{
		@"ShowStatus"                  : @"Last Seen",
		@"ShowProfilePhoto"            : @"Profile Photo",
		@"ShowBio"                     : @"Bio",
		@"ShowPhoneNumber"             : @"Phone Number",
		@"ShowLinkInForwardedMessages" : @"Forwarded Messages",
		@"AllowChatInvites"            : @"Groups and Channels",
		@"AllowCalls"                  : @"Calls",
		@"AllowPeerToPeerCalls"        : @"Peer-to-Peer Calls",
		@"AllowFindingByPhoneNumber"   : @"Find Me by Phone",
	};
	return titles[TGPrivacyString(setting)] ?: TGPrivacyString(setting);
}

#pragma mark - privacy rules

- (void)privacyRuleDetailed:(NSString *)setting
                 completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"   : @"getUserPrivacySettingRules",
		@"setting" : TGPrivacySettingObject(setting),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPrivacyIsError(result)){
			completion(nil);
			return;
		}

		NSMutableArray *allowedUsers = [NSMutableArray array];
		NSMutableArray *restrictedUsers = [NSMutableArray array];
		NSMutableArray *allowedChats = [NSMutableArray array];
		NSMutableArray *restrictedChats = [NSMutableArray array];
		NSString *value = @"nobody";
		BOOL haveBase = NO;

		for (NSDictionary *rule in TGPrivacyArray(result[@"rules"])){
			if (![rule isKindOfClass:[NSDictionary class]])
				continue;
			NSString *type = TGPrivacyString(rule[@"@type"]);
			if ([type isEqualToString:@"userPrivacySettingRuleAllowUsers"])
				[allowedUsers addObjectsFromArray:TGPrivacyArray(rule[@"user_ids"])];
			else if ([type isEqualToString:@"userPrivacySettingRuleRestrictUsers"])
				[restrictedUsers addObjectsFromArray:TGPrivacyArray(rule[@"user_ids"])];
			else if ([type isEqualToString:@"userPrivacySettingRuleAllowChatMembers"])
				[allowedChats addObjectsFromArray:TGPrivacyArray(rule[@"chat_ids"])];
			else if ([type isEqualToString:@"userPrivacySettingRuleRestrictChatMembers"])
				[restrictedChats addObjectsFromArray:TGPrivacyArray(rule[@"chat_ids"])];
			else if (!haveBase){
				haveBase = YES;
				if ([type isEqualToString:@"userPrivacySettingRuleAllowAll"])
					value = @"everybody";
				else if ([type isEqualToString:@"userPrivacySettingRuleAllowContacts"])
					value = @"contacts";
			}
		}

		completion(@{
			@"value"              : value,
			@"allowedUserIds"     : allowedUsers,
			@"restrictedUserIds"  : restrictedUsers,
			@"allowedChatIds"     : allowedChats,
			@"restrictedChatIds"  : restrictedChats,
		});
	}];
}

- (void)setPrivacyRule:(NSString *)setting
                    to:(NSString *)value
          allowedUsers:(NSArray *)allowedUserIds
       restrictedUsers:(NSArray *)restrictedUserIds
            completion:(void (^)(BOOL))completion {
	NSMutableArray *rules = [NSMutableArray array];

	if ([restrictedUserIds isKindOfClass:[NSArray class]] && [restrictedUserIds count])
		[rules addObject:@{
			@"@type"    : @"userPrivacySettingRuleRestrictUsers",
			@"user_ids" : restrictedUserIds,
		}];
	if ([allowedUserIds isKindOfClass:[NSArray class]] && [allowedUserIds count])
		[rules addObject:@{
			@"@type"    : @"userPrivacySettingRuleAllowUsers",
			@"user_ids" : allowedUserIds,
		}];

	NSString *base = @"userPrivacySettingRuleRestrictAll";
	if ([value isEqualToString:@"everybody"])
		base = @"userPrivacySettingRuleAllowAll";
	else if ([value isEqualToString:@"contacts"])
		base = @"userPrivacySettingRuleAllowContacts";
	[rules addObject:@{@"@type" : base}];

	[self request:@{
		@"@type"   : @"setUserPrivacySettingRules",
		@"setting" : TGPrivacySettingObject(setting),
		@"rules"   : @{@"@type" : @"userPrivacySettingRules", @"rules" : rules},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

#pragma mark - block list

- (void)setUser:(int64_t)userId
        blocked:(BOOL)blocked
     completion:(void (^)(BOOL))completion {
	NSDictionary *request = @{
		@"@type"      : @"setMessageSenderBlockList",
		@"sender_id"  : @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)},
		@"block_list" : blocked ? (id)@{@"@type" : @"blockListMain"} : (id)[NSNull null],
	};
	[self request:request completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

- (void)blockedSendersFromOffset:(NSInteger)offset
                           limit:(NSInteger)limit
                      completion:(void (^)(NSArray *, NSInteger))completion {
	__weak TGClient *weakSelf = self;
	[self request:@{
		@"@type"      : @"getBlockedMessageSenders",
		@"block_list" : @{@"@type" : @"blockListMain"},
		@"offset"     : @(offset),
		@"limit"      : @(limit > 0 ? limit : 100),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPrivacyIsError(result)){
			completion([NSArray array], 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *sender in TGPrivacyArray(result[@"senders"])){
			if (![sender isKindOfClass:[NSDictionary class]])
				continue;
			NSNumber *userId = sender[@"user_id"];
			NSNumber *chatId = sender[@"chat_id"];
			if ([userId isKindOfClass:[NSNumber class]]){
				[out addObject:@{
					@"id"     : userId,
					@"name"   : [weakSelf nameForUserId:[userId longLongValue]] ?: @"",
					@"isChat" : @NO,
				}];
			} else if ([chatId isKindOfClass:[NSNumber class]]){
				[out addObject:@{
					@"id"     : chatId,
					@"name"   : @"",
					@"isChat" : @YES,
				}];
			}
		}
		completion(out, [TGPrivacyNumber(result[@"total_count"]) integerValue]);
	}];
}

#pragma mark - sessions

- (void)activeSessionsWithCompletion:(void (^)(NSArray *, NSInteger))completion {
	[self request:@{@"@type" : @"getActiveSessions"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPrivacyIsError(result)){
			completion([NSArray array], 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *session in TGPrivacyArray(result[@"sessions"])){
			NSDictionary *flat = TGPrivacySessionDict(session);
			if (flat)
				[out addObject:flat];
		}
		completion(out, [TGPrivacyNumber(result[@"inactive_session_ttl_days"]) integerValue]);
	}];
}

- (void)unconfirmedSessionsWithCompletion:(void (^)(NSArray *))completion {
	[self activeSessionsWithCompletion:^(NSArray *sessions, NSInteger ttlDays){
		if (!completion)
			return;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *session in sessions){
			if ([session[@"isUnconfirmed"] boolValue])
				[out addObject:session];
		}
		completion(out);
	}];
}

- (void)terminateSession:(long long)sessionId completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"terminateSession", @"session_id" : @(sessionId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

- (void)terminateAllOtherSessionsWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"terminateAllOtherSessions"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

- (void)confirmSession:(long long)sessionId completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"confirmSession", @"session_id" : @(sessionId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

- (void)setSession:(long long)sessionId
    canAcceptCalls:(BOOL)canAcceptCalls
  canAcceptSecrets:(BOOL)canAcceptSecretChats
        completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"            : @"toggleSessionCanAcceptCalls",
		@"session_id"       : @(sessionId),
		@"can_accept_calls" : canAcceptCalls ? @YES : @NO,
	} completion:^(NSDictionary *callsResult){
		BOOL callsOk = !TGPrivacyIsError(callsResult);
		[self request:@{
			@"@type"                   : @"toggleSessionCanAcceptSecretChats",
			@"session_id"              : @(sessionId),
			@"can_accept_secret_chats" : canAcceptSecretChats ? @YES : @NO,
		} completion:^(NSDictionary *secretsResult){
			if (completion)
				completion(callsOk && !TGPrivacyIsError(secretsResult));
		}];
	}];
}

- (void)setInactiveSessionTtlDays:(NSInteger)days completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"                     : @"setInactiveSessionTtl",
		@"inactive_session_ttl_days" : @(days),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

#pragma mark - connected websites

- (void)connectedWebsitesWithCompletion:(void (^)(NSArray *))completion {
	__weak TGClient *weakSelf = self;
	[self request:@{@"@type" : @"getConnectedWebsites"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPrivacyIsError(result)){
			completion([NSArray array]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *site in TGPrivacyArray(result[@"websites"])){
			if (![site isKindOfClass:[NSDictionary class]])
				continue;
			NSNumber *botId = TGPrivacyNumber(site[@"bot_user_id"]);
			[out addObject:@{
				@"id"         : TGPrivacyNumber(site[@"id"]),
				@"domain"     : TGPrivacyString(site[@"domain_name"]),
				@"botName"    : [weakSelf nameForUserId:[botId longLongValue]] ?: @"",
				@"browser"    : TGPrivacyString(site[@"browser"]),
				@"platform"   : TGPrivacyString(site[@"platform"]),
				@"ip"         : TGPrivacyString(site[@"ip_address"]),
				@"location"   : TGPrivacyString(site[@"location"]),
				@"lastActive" : TGPrivacyNumber(site[@"last_active_date"]),
			}];
		}
		completion(out);
	}];
}

- (void)disconnectWebsite:(long long)websiteId completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"disconnectWebsite", @"website_id" : @(websiteId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

- (void)disconnectAllWebsitesWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"disconnectAllWebsites"} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

#pragma mark - two-step verification

- (void)passwordStateWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getPasswordState"} completion:^(NSDictionary *result){
		if (completion)
			completion(TGPrivacyPasswordState(result));
	}];
}

- (void)setPasswordWithOldPassword:(NSString *)oldPassword
                       newPassword:(NSString *)newPassword
                              hint:(NSString *)hint
                     recoveryEmail:(NSString *)recoveryEmail
                        completion:(void (^)(NSDictionary *))completion {
	BOOL setsEmail = [recoveryEmail isKindOfClass:[NSString class]] && [recoveryEmail length] > 0;
	[self request:@{
		@"@type"                      : @"setPassword",
		@"old_password"               : oldPassword ?: @"",
		@"new_password"               : newPassword ?: @"",
		@"new_hint"                   : hint ?: @"",
		@"set_recovery_email_address" : setsEmail ? @YES : @NO,
		@"new_recovery_email_address" : setsEmail ? recoveryEmail : @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGPrivacyPasswordState(result));
	}];
}

- (void)disablePasswordWithOldPassword:(NSString *)oldPassword
                            completion:(void (^)(BOOL))completion {
	[self setPasswordWithOldPassword:oldPassword
						 newPassword:@""
								hint:@""
					   recoveryEmail:nil
						  completion:^(NSDictionary *state){
		if (completion)
			completion(state != nil && ![state[@"hasPassword"] boolValue]);
	}];
}

- (void)recoveryEmailWithPassword:(NSString *)password
                       completion:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"    : @"getRecoveryEmailAddress",
		@"password" : password ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPrivacyIsError(result)){
			completion(nil);
			return;
		}
		completion(TGPrivacyString(result[@"recovery_email_address"]));
	}];
}

- (void)setRecoveryEmail:(NSString *)email
                password:(NSString *)password
              completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"                      : @"setRecoveryEmailAddress",
		@"password"                   : password ?: @"",
		@"new_recovery_email_address" : email ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGPrivacyPasswordState(result));
	}];
}

- (void)checkRecoveryEmailCode:(NSString *)code
                    completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type" : @"checkRecoveryEmailAddressCode",
		@"code"  : code ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGPrivacyPasswordState(result));
	}];
}

- (void)resendRecoveryEmailCodeWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"resendRecoveryEmailAddressCode"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGPrivacyPasswordState(result));
	}];
}

#pragma mark - forgotten password

- (void)requestPasswordRecoveryWithCompletion:(void (^)(NSString *, NSInteger))completion {
	[self request:@{@"@type" : @"requestPasswordRecovery"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPrivacyIsError(result)){
			completion(nil, 0);
			return;
		}
		completion(TGPrivacyString(result[@"email_address_pattern"]),
				   [TGPrivacyNumber(result[@"length"]) integerValue]);
	}];
}

- (void)recoverPasswordWithCode:(NSString *)code
                    newPassword:(NSString *)newPassword
                           hint:(NSString *)hint
                     completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"         : @"recoverPassword",
		@"recovery_code" : code ?: @"",
		@"new_password"  : newPassword ?: @"",
		@"new_hint"      : hint ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

- (void)resetPasswordWithCompletion:(void (^)(NSString *, NSInteger))completion {
	[self request:@{@"@type" : @"resetPassword"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPrivacyIsError(result)){
			completion(nil, 0);
			return;
		}
		NSString *type = TGPrivacyString(result[@"@type"]);
		if ([type isEqualToString:@"resetPasswordResultPending"]){
			completion(@"pending", [TGPrivacyNumber(result[@"pending_reset_date"]) integerValue]);
			return;
		}
		if ([type isEqualToString:@"resetPasswordResultDeclined"]){
			completion(@"declined", [TGPrivacyNumber(result[@"retry_date"]) integerValue]);
			return;
		}
		completion(@"ok", 0);
	}];
}

- (void)cancelPasswordResetWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"cancelPasswordReset"} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

#pragma mark - account

- (void)defaultAutoDeleteSecondsWithCompletion:(void (^)(NSInteger))completion {
	[self request:@{@"@type" : @"getDefaultMessageAutoDeleteTime"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPrivacyIsError(result)){
			completion(0);
			return;
		}
		completion([TGPrivacyNumber(result[@"time"]) integerValue]);
	}];
}

- (void)setDefaultAutoDeleteSeconds:(NSInteger)seconds completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"                     : @"setDefaultMessageAutoDeleteTime",
		@"message_auto_delete_time"  : @{@"@type" : @"messageAutoDeleteTime",
										 @"time"  : @(seconds)},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

- (void)deleteAccountWithReason:(NSString *)reason
                       password:(NSString *)password
                     completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"    : @"deleteAccount",
		@"reason"   : reason ?: @"",
		@"password" : password ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGPrivacyIsError(result));
	}];
}

#pragma mark - reporting

- (void)reportChat:(int64_t)chatId
        messageIds:(NSArray *)messageIds
          optionId:(NSString *)optionId
              text:(NSString *)text
        completion:(void (^)(NSDictionary *))completion {
	NSArray *ids = [messageIds isKindOfClass:[NSArray class]] ? messageIds : [NSArray array];
	[self request:@{
		@"@type"       : @"reportChat",
		@"chat_id"     : @(chatId),
		@"option_id"   : optionId ?: @"",
		@"message_ids" : ids,
		@"text"        : text ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPrivacyIsError(result)){
			completion(nil);
			return;
		}
		NSString *type = TGPrivacyString(result[@"@type"]);
		if ([type isEqualToString:@"reportChatResultOptionRequired"]){
			NSMutableArray *options = [NSMutableArray array];
			for (NSDictionary *option in TGPrivacyArray(result[@"options"])){
				if (![option isKindOfClass:[NSDictionary class]])
					continue;
				[options addObject:@{
					@"id"   : TGPrivacyString(option[@"id"]),
					@"text" : TGPrivacyString(option[@"text"]),
				}];
			}
			completion(@{
				@"status"  : @"options",
				@"title"   : TGPrivacyString(result[@"title"]),
				@"options" : options,
			});
			return;
		}
		if ([type isEqualToString:@"reportChatResultTextRequired"]){
			completion(@{
				@"status"   : @"text",
				@"optionId" : TGPrivacyString(result[@"option_id"]),
				@"optional" : TGPrivacyBool(result[@"is_optional"]),
			});
			return;
		}
		if ([type isEqualToString:@"reportChatResultMessagesRequired"]){
			completion(@{@"status" : @"messages"});
			return;
		}
		completion(@{@"status" : @"ok"});
	}];
}

@end

// vim:ft=objc

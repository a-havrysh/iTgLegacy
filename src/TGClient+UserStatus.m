#import "TGClient+Private.h"
#import "TGClient+UserStatus.h"

static NSDictionary *TGUSDict(id value){
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *TGUSArray(id value){
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSString *TGUSString(id value){
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static long long TGUSInt64(id value){
	if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class])
		return [value longLongValue];
	return 0;
}

static BOOL TGUSIsError(NSDictionary *result){
	return ![result isKindOfClass:NSDictionary.class] ||
	       [TGUSString(result[@"@type"]) isEqualToString:@"error"];
}

static NSString *TGUSTimeText(NSDate *date){
	static NSDateFormatter *fmt = nil;
	if (!fmt){
		fmt = [[NSDateFormatter alloc] init];
		[fmt setDateFormat:@"HH:mm"];
	}
	return [fmt stringFromDate:date];
}

static NSString *TGUSLastSeenText(long long wasOnline){
	if (wasOnline <= 0)
		return @"last seen a long time ago";

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)wasOnline];
	NSCalendar *cal = [NSCalendar currentCalendar];
	NSUInteger units = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit;
	NSDate *dayOfDate = [cal dateFromComponents:[cal components:units fromDate:date]];
	NSDate *dayOfNow  = [cal dateFromComponents:[cal components:units fromDate:[NSDate date]]];
	NSInteger delta = [cal components:NSDayCalendarUnit
							 fromDate:dayOfDate
							   toDate:dayOfNow
							  options:0].day;
	NSString *time = TGUSTimeText(date);

	if (delta <= 0)
		return [NSString stringWithFormat:@"last seen today at %@", time];
	if (delta == 1)
		return [NSString stringWithFormat:@"last seen yesterday at %@", time];
	if (delta < 7){
		NSDateFormatter *dayFmt = [[NSDateFormatter alloc] init];
		[dayFmt setDateFormat:@"EEEE"];
		return [NSString stringWithFormat:@"last seen on %@ at %@",
				[dayFmt stringFromDate:date], time];
	}
	NSDateFormatter *dateFmt = [[NSDateFormatter alloc] init];
	[dateFmt setDateFormat:@"dd.MM.yyyy"];
	return [NSString stringWithFormat:@"last seen %@ at %@",
			[dateFmt stringFromDate:date], time];
}

static NSDictionary *TGUSFlatEmojiStatusIcon(NSDictionary *sticker,
											 long long customEmojiId,
											 long long expires,
											 BOOL isGift,
											 NSString *giftTitle){
	NSDictionary *s = TGUSDict(sticker);
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	out[@"customEmojiId"] = @(customEmojiId);
	out[@"expires"]       = @(expires);
	out[@"isGift"]        = @(isGift);
	out[@"giftTitle"]     = giftTitle ?: @"";
	out[@"emoji"]         = TGUSString(s[@"emoji"]);

	NSDictionary *thumbFile = TGUSDict(TGUSDict(s[@"thumbnail"])[@"file"]);
	if ([thumbFile[@"id"] isKindOfClass:NSNumber.class])
		out[@"thumbFileId"] = thumbFile[@"id"];

	NSDictionary *file = TGUSDict(s[@"sticker"]);
	if ([file[@"id"] isKindOfClass:NSNumber.class])
		out[@"stickerFileId"] = file[@"id"];

	NSString *format = TGUSString(TGUSDict(s[@"format"])[@"@type"]);
	out[@"isAnimated"] = @([format isEqualToString:@"stickerFormatTgs"] ||
						   [format isEqualToString:@"stickerFormatWebm"]);
	return out;
}

@implementation TGClient (UserStatus)

#pragma mark - chat lifecycle

- (void)openChat:(int64_t)chatId {
	[self send:@{@"@type" : @"openChat", @"chat_id" : @(chatId)}];
}

- (void)closeChat:(int64_t)chatId {
	[self send:@{@"@type" : @"closeChat", @"chat_id" : @(chatId)}];
}

#pragma mark - last seen

+ (NSDictionary *)statusInfoForUserStatus:(NSDictionary *)status {
	NSDictionary *s = TGUSDict(status);
	NSString *type = TGUSString(s[@"@type"]);
	BOOL hidden = [s[@"by_my_privacy_settings"] boolValue];

	if ([type isEqualToString:@"userStatusOnline"])
		return @{@"text" : @"online", @"isOnline" : @YES, @"rank" : @(4000000000LL),
				 @"wasOnline" : @(0), @"isApproximate" : @NO,
				 @"hiddenByMyPrivacy" : @NO};

	if ([type isEqualToString:@"userStatusOffline"]){
		long long was = TGUSInt64(s[@"was_online"]);
		return @{@"text" : TGUSLastSeenText(was), @"isOnline" : @NO, @"rank" : @(was),
				 @"wasOnline" : @(was), @"isApproximate" : @NO,
				 @"hiddenByMyPrivacy" : @NO};
	}
	if ([type isEqualToString:@"userStatusRecently"])
		return @{@"text" : @"last seen recently", @"isOnline" : @NO, @"rank" : @(3),
				 @"wasOnline" : @(0), @"isApproximate" : @YES,
				 @"hiddenByMyPrivacy" : @(hidden)};
	if ([type isEqualToString:@"userStatusLastWeek"])
		return @{@"text" : @"last seen within a week", @"isOnline" : @NO, @"rank" : @(2),
				 @"wasOnline" : @(0), @"isApproximate" : @YES,
				 @"hiddenByMyPrivacy" : @(hidden)};
	if ([type isEqualToString:@"userStatusLastMonth"])
		return @{@"text" : @"last seen within a month", @"isOnline" : @NO, @"rank" : @(1),
				 @"wasOnline" : @(0), @"isApproximate" : @YES,
				 @"hiddenByMyPrivacy" : @(hidden)};

	return @{@"text" : @"last seen a long time ago", @"isOnline" : @NO, @"rank" : @(0),
			 @"wasOnline" : @(0), @"isApproximate" : @YES,
			 @"hiddenByMyPrivacy" : @NO};
}

- (void)statusInfoForUser:(int64_t)userId
               completion:(void (^)(NSDictionary *))completion {
	if (!completion)
		return;
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *user){
		NSDictionary *info;
		if (TGUSIsError(user))
			info = [TGClient statusInfoForUserStatus:nil];
		else
			info = [TGClient statusInfoForUserStatus:TGUSDict(user[@"status"])];

		NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:info];
		out[@"userId"] = @(userId);
		completion(out);
	}];
}

+ (NSString *)hiddenStatusHintForStatusInfo:(NSDictionary *)info {
	NSDictionary *i = TGUSDict(info);
	if (![i[@"isApproximate"] boolValue])
		return nil;
	if ([i[@"hiddenByMyPrivacy"] boolValue])
		return @"You cannot see the exact last seen time because you hide "
			   @"yours. Allow others to see your Last Seen in Privacy "
			   @"settings to see theirs.";
	return @"This user hides the exact time they were last online.";
}

- (void)setSelfOnline:(BOOL)online {
	[self send:@{
		@"@type" : @"setOption",
		@"name"  : @"online",
		@"value" : @{@"@type" : @"optionValueBoolean", @"value" : @(online)},
	}];
}

static const NSUInteger TGUSOnlineProbeLimit = 20;
static const NSTimeInterval TGUSOnlineCacheTtl = 60.0;

static NSMutableDictionary *TGUSOnlineCache(void){
	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [[NSMutableDictionary alloc] init];
	return cache;
}

- (void)countOnlineAmong:(NSArray *)userIds
                   index:(NSUInteger)index
                 running:(NSInteger)running
              completion:(void (^)(NSInteger online))completion {
	if (index >= userIds.count || index >= TGUSOnlineProbeLimit){
		completion(running);
		return;
	}
	int64_t userId = TGUSInt64(userIds[index]);
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *user){
		NSInteger next = running;
		if (!TGUSIsError(user)){
			NSDictionary *info = [TGClient statusInfoForUserStatus:TGUSDict(user[@"status"])];
			if ([info[@"isOnline"] boolValue])
				next++;
		}
		[weakSelf countOnlineAmong:userIds index:index + 1 running:next completion:completion];
	}];
}

- (void)groupOnlineSummaryForChat:(int64_t)chatId
                       completion:(void (^)(NSString *, NSInteger, NSInteger))completion {
	if (!completion)
		return;
	__weak typeof(self) weakSelf = self;

	NSDictionary *cached = TGUSDict(TGUSOnlineCache()[@(chatId)]);
	if (cached &&
		[[NSDate date] timeIntervalSinceReferenceDate] -
		[cached[@"at"] doubleValue] < TGUSOnlineCacheTtl){
		completion(TGUSString(cached[@"text"]),
				   [cached[@"members"] integerValue],
				   [cached[@"online"] integerValue]);
		return;
	}

	void (^answer)(NSInteger, NSArray *) = ^(NSInteger members, NSArray *memberIds){
		[weakSelf countOnlineAmong:(memberIds ?: @[])
							 index:0
						   running:0
						completion:^(NSInteger online){
			NSString *unit = members == 1 ? @"member" : @"members";
			NSString *text = online > 0
				? [NSString stringWithFormat:@"%d %@, %d online", (int)members, unit, (int)online]
				: [NSString stringWithFormat:@"%d %@", (int)members, unit];
			TGUSOnlineCache()[@(chatId)] = @{
				@"text"    : text,
				@"members" : @(members),
				@"online"  : @(online),
				@"at"      : @([[NSDate date] timeIntervalSinceReferenceDate]),
			};
			completion(text, members, online);
		}];
	};

	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (TGUSIsError(chat)){
			completion(@"", 0, 0);
			return;
		}
		NSDictionary *type = TGUSDict(chat[@"type"]);
		NSString *kind = TGUSString(type[@"@type"]);

		if ([kind isEqualToString:@"chatTypeBasicGroup"]){
			[weakSelf request:@{@"@type" : @"getBasicGroupFullInfo",
								@"basic_group_id" : type[@"basic_group_id"] ?: @(0)}
				   completion:^(NSDictionary *full){
				if (TGUSIsError(full)){
					completion(@"", 0, 0);
					return;
				}
				NSArray *members = TGUSArray(TGUSDict(full)[@"members"]);
				NSMutableArray *ids = [NSMutableArray array];
				for (id member in members ?: @[]){
					id memberId = TGUSDict(TGUSDict(member)[@"member_id"])[@"user_id"];
					if (memberId)
						[ids addObject:@(TGUSInt64(memberId))];
				}
				answer((NSInteger)ids.count, ids);
			}];
			return;
		}

		if ([kind isEqualToString:@"chatTypeSupergroup"]){
			id supergroupId = type[@"supergroup_id"] ?: @(0);
			[weakSelf request:@{@"@type" : @"getSupergroupFullInfo",
								@"supergroup_id" : supergroupId}
				   completion:^(NSDictionary *full){
				if (TGUSIsError(full)){
					completion(@"", 0, 0);
					return;
				}
				NSInteger members = [TGUSDict(full)[@"member_count"] integerValue];
				[weakSelf request:@{@"@type" : @"getSupergroupMembers",
									@"supergroup_id" : supergroupId,
									@"filter" : @{@"@type" : @"supergroupMembersFilterRecent"},
									@"offset" : @(0),
									@"limit"  : @(50)}
					   completion:^(NSDictionary *result){
					NSMutableArray *ids = [NSMutableArray array];
					for (id member in TGUSArray(TGUSDict(result)[@"members"]) ?: @[]){
						id memberId = TGUSDict(TGUSDict(member)[@"member_id"])[@"user_id"];
						if (memberId)
							[ids addObject:@(TGUSInt64(memberId))];
					}
					answer(members, ids);
				}];
			}];
			return;
		}
		completion(@"", 0, 0);
	}];
}

#pragma mark - status privacy

- (void)privacyRuleDetail:(NSString *)setting
               completion:(void (^)(NSDictionary *))completion {
	if (!completion)
		return;
	NSString *name = [@"userPrivacySetting" stringByAppendingString:setting ?: @"ShowStatus"];
	[self request:@{@"@type"   : @"getUserPrivacySettingRules",
					@"setting" : @{@"@type" : name}}
	   completion:^(NSDictionary *result){
		if (TGUSIsError(result)){
			completion(nil);
			return;
		}
		NSMutableArray *allowedUsers = [NSMutableArray array];
		NSMutableArray *restrictedUsers = [NSMutableArray array];
		NSMutableArray *allowedChats = [NSMutableArray array];
		NSMutableArray *restrictedChats = [NSMutableArray array];
		NSString *value = @"nobody";
		BOOL haveValue = NO;

		for (id entry in TGUSArray(result[@"rules"]) ?: @[]){
			NSDictionary *rule = TGUSDict(entry);
			NSString *kind = TGUSString(rule[@"@type"]);
			NSArray *userIds = TGUSArray(rule[@"user_ids"]);
			NSArray *chatIds = TGUSArray(rule[@"chat_ids"]);

			if ([kind isEqualToString:@"userPrivacySettingRuleAllowUsers"]){
				for (id uid in userIds ?: @[])
					[allowedUsers addObject:@(TGUSInt64(uid))];
			} else if ([kind isEqualToString:@"userPrivacySettingRuleRestrictUsers"]){
				for (id uid in userIds ?: @[])
					[restrictedUsers addObject:@(TGUSInt64(uid))];
			} else if ([kind isEqualToString:@"userPrivacySettingRuleAllowChatMembers"]){
				for (id cid in chatIds ?: @[])
					[allowedChats addObject:@(TGUSInt64(cid))];
			} else if ([kind isEqualToString:@"userPrivacySettingRuleRestrictChatMembers"]){
				for (id cid in chatIds ?: @[])
					[restrictedChats addObject:@(TGUSInt64(cid))];
			} else if (!haveValue){
				if ([kind isEqualToString:@"userPrivacySettingRuleAllowAll"]){
					value = @"everybody";
					haveValue = YES;
				} else if ([kind isEqualToString:@"userPrivacySettingRuleAllowContacts"]){
					value = @"contacts";
					haveValue = YES;
				} else if ([kind isEqualToString:@"userPrivacySettingRuleRestrictAll"]){
					value = @"nobody";
					haveValue = YES;
				}
			}
		}
		completion(@{
			@"value"             : value,
			@"allowedUserIds"    : allowedUsers,
			@"restrictedUserIds" : restrictedUsers,
			@"allowedChatIds"    : allowedChats,
			@"restrictedChatIds" : restrictedChats,
		});
	}];
}

- (void)setPrivacyRule:(NSString *)setting
                    to:(NSString *)value
            allowUsers:(NSArray *)allowedUserIds
         restrictUsers:(NSArray *)restrictedUserIds
            completion:(void (^)(BOOL))completion {
	NSMutableArray *rules = [NSMutableArray array];
	if (restrictedUserIds.count)
		[rules addObject:@{@"@type" : @"userPrivacySettingRuleRestrictUsers",
						   @"user_ids" : restrictedUserIds}];
	if (allowedUserIds.count)
		[rules addObject:@{@"@type" : @"userPrivacySettingRuleAllowUsers",
						   @"user_ids" : allowedUserIds}];

	NSString *base = @"userPrivacySettingRuleRestrictAll";
	if ([value isEqualToString:@"everybody"])
		base = @"userPrivacySettingRuleAllowAll";
	else if ([value isEqualToString:@"contacts"])
		base = @"userPrivacySettingRuleAllowContacts";
	[rules addObject:@{@"@type" : base}];

	NSString *name = [@"userPrivacySetting" stringByAppendingString:setting ?: @"ShowStatus"];
	[self request:@{@"@type"   : @"setUserPrivacySettingRules",
					@"setting" : @{@"@type" : name},
					@"rules"   : @{@"@type" : @"userPrivacySettingRules",
								   @"rules" : rules}}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGUSIsError(result));
	}];
}

#pragma mark - emoji status

- (void)iconForEmojiStatus:(NSDictionary *)emojiStatus
                completion:(void (^)(NSDictionary *))completion {
	NSDictionary *status = TGUSDict(emojiStatus);
	NSDictionary *type = TGUSDict(status[@"type"]);
	NSString *kind = TGUSString(type[@"@type"]);
	long long expires = TGUSInt64(status[@"expiration_date"]);

	long long customEmojiId = 0;
	BOOL isGift = NO;
	NSString *giftTitle = @"";

	if ([kind isEqualToString:@"emojiStatusTypeCustomEmoji"]){
		customEmojiId = TGUSInt64(type[@"custom_emoji_id"]);
	} else if ([kind isEqualToString:@"emojiStatusTypeUpgradedGift"]){
		customEmojiId = TGUSInt64(type[@"model_custom_emoji_id"]);
		isGift = YES;
		giftTitle = TGUSString(type[@"gift_title"]);
	}
	if (!customEmojiId){
		completion(nil);
		return;
	}

	[self request:@{@"@type" : @"getCustomEmojiStickers",
					@"custom_emoji_ids" : @[[NSString stringWithFormat:@"%lld", customEmojiId]]}
	   completion:^(NSDictionary *result){
		NSArray *stickers = TGUSArray(TGUSDict(result)[@"stickers"]);
		NSDictionary *sticker = stickers.count ? TGUSDict(stickers[0]) : nil;
		completion(TGUSFlatEmojiStatusIcon(sticker, customEmojiId, expires, isGift, giftTitle));
	}];
}

- (void)emojiStatusForUser:(int64_t)userId
                completion:(void (^)(NSDictionary *))completion {
	if (!completion)
		return;
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *user){
		if (TGUSIsError(user)){
			completion(nil);
			return;
		}
		[weakSelf iconForEmojiStatus:TGUSDict(user[@"emoji_status"]) completion:completion];
	}];
}

- (void)emojiStatusForChat:(int64_t)chatId
                completion:(void (^)(NSDictionary *))completion {
	if (!completion)
		return;
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (TGUSIsError(chat)){
			completion(nil);
			return;
		}
		[weakSelf iconForEmojiStatus:TGUSDict(chat[@"emoji_status"]) completion:completion];
	}];
}

- (void)customEmojiIconsForIds:(NSArray *)ids
                    completion:(void (^)(NSDictionary *))completion {
	if (!completion)
		return;
	NSMutableArray *strings = [NSMutableArray array];
	for (id one in TGUSArray(ids) ?: @[]){
		long long value = TGUSInt64(one);
		if (value)
			[strings addObject:[NSString stringWithFormat:@"%lld", value]];
	}
	if (!strings.count){
		completion(@{});
		return;
	}
	[self request:@{@"@type" : @"getCustomEmojiStickers",
					@"custom_emoji_ids" : strings}
	   completion:^(NSDictionary *result){
		NSMutableDictionary *out = [NSMutableDictionary dictionary];
		for (id entry in TGUSArray(TGUSDict(result)[@"stickers"]) ?: @[]){
			NSDictionary *sticker = TGUSDict(entry);
			NSDictionary *fullType = TGUSDict(sticker[@"full_type"]);
			long long emojiId = TGUSInt64(fullType[@"custom_emoji_id"]);
			if (!emojiId)
				continue;
			out[[NSString stringWithFormat:@"%lld", emojiId]] =
				TGUSFlatEmojiStatusIcon(sticker, emojiId, 0, NO, @"");
		}
		completion(out);
	}];
}

#pragma mark - badges

- (void)badgesForUser:(int64_t)userId
           completion:(void (^)(NSDictionary *))completion {
	if (!completion)
		return;
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *user){
		NSDictionary *verification = TGUSDict(TGUSDict(user)[@"verification_status"]);
		NSString *userType = TGUSString(TGUSDict(TGUSDict(user)[@"type"])[@"@type"]);
		completion(@{
			@"isPremium"  : @([TGUSDict(user)[@"is_premium"] boolValue]),
			@"isSupport"  : @([TGUSDict(user)[@"is_support"] boolValue]),
			@"isVerified" : @([verification[@"is_verified"] boolValue]),
			@"isScam"     : @([verification[@"is_scam"] boolValue]),
			@"isFake"     : @([verification[@"is_fake"] boolValue]),
			@"isBot"      : @([userType isEqualToString:@"userTypeBot"]),
		});
	}];
}

- (void)badgesForChat:(int64_t)chatId
           completion:(void (^)(NSDictionary *))completion {
	if (!completion)
		return;
	NSDictionary *empty = @{@"isVerified" : @NO, @"isScam" : @NO, @"isFake" : @NO};
	__weak typeof(self) weakSelf = self;

	void (^answer)(NSDictionary *) = ^(NSDictionary *verification){
		completion(@{
			@"isVerified" : @([TGUSDict(verification)[@"is_verified"] boolValue]),
			@"isScam"     : @([TGUSDict(verification)[@"is_scam"] boolValue]),
			@"isFake"     : @([TGUSDict(verification)[@"is_fake"] boolValue]),
		});
	};

	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (TGUSIsError(chat)){
			completion(empty);
			return;
		}
		NSDictionary *type = TGUSDict(chat[@"type"]);
		NSString *kind = TGUSString(type[@"@type"]);

		if ([kind isEqualToString:@"chatTypeSupergroup"]){
			[weakSelf request:@{@"@type" : @"getSupergroup",
								@"supergroup_id" : type[@"supergroup_id"] ?: @(0)}
				   completion:^(NSDictionary *supergroup){
				answer(TGUSDict(TGUSDict(supergroup)[@"verification_status"]));
			}];
			return;
		}
		if ([kind isEqualToString:@"chatTypePrivate"] ||
			[kind isEqualToString:@"chatTypeSecret"]){
			[weakSelf request:@{@"@type" : @"getUser",
								@"user_id" : type[@"user_id"] ?: @(0)}
				   completion:^(NSDictionary *user){
				answer(TGUSDict(TGUSDict(user)[@"verification_status"]));
			}];
			return;
		}
		completion(empty);
	}];
}

#pragma mark - accent colours

+ (NSNumber *)rgbForAccentColorId:(NSInteger)colorId {
	static const NSInteger builtIn[7] = {
		0xCC5049, 0xD67722, 0x955CDB, 0x40A920, 0x309EBA, 0x368AD1, 0xC7508B
	};
	NSInteger index = colorId < 0 ? 0 : colorId % 7;
	return @(builtIn[index]);
}

+ (NSArray *)profileGradientForColorId:(NSInteger)colorId {
	if (colorId < 0)
		return nil;
	static const NSInteger tops[7] = {
		0xE15052, 0xE0802B, 0xA05FF3, 0x27A910, 0x27ACCE, 0x3391D4, 0xDD4371
	};
	static const NSInteger bottoms[7] = {
		0xF41C2F, 0xFAC534, 0xF48FFF, 0xA7DC57, 0x82E8D6, 0x7DD3F0, 0xF9BFC8
	};
	NSInteger index = colorId % 7;
	return @[@(tops[index]), @(bottoms[index])];
}

- (NSDictionary *)accentInfoFromPeer:(NSDictionary *)peer {
	NSDictionary *p = TGUSDict(peer);
	NSInteger accentId = [p[@"accent_color_id"] integerValue];
	NSInteger profileId = p[@"profile_accent_color_id"]
		? [p[@"profile_accent_color_id"] integerValue] : -1;

	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	out[@"colorId"] = @(accentId);
	out[@"rgb"] = [TGClient rgbForAccentColorId:accentId];
	out[@"profileColorId"] = @(profileId);
	NSArray *gradient = [TGClient profileGradientForColorId:profileId];
	if (gradient)
		out[@"profileColors"] = gradient;
	out[@"backgroundCustomEmojiId"] = @(TGUSInt64(p[@"background_custom_emoji_id"]));
	out[@"profileBackgroundCustomEmojiId"] =
		@(TGUSInt64(p[@"profile_background_custom_emoji_id"]));
	return out;
}

- (void)accentColorsForUser:(int64_t)userId
                 completion:(void (^)(NSDictionary *))completion {
	if (!completion)
		return;
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *user){
		completion([weakSelf accentInfoFromPeer:TGUSIsError(user) ? nil : user]);
	}];
}

- (void)accentColorsForChat:(int64_t)chatId
                 completion:(void (^)(NSDictionary *))completion {
	if (!completion)
		return;
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		completion([weakSelf accentInfoFromPeer:TGUSIsError(chat) ? nil : chat]);
	}];
}

@end

// vim:ft=objc

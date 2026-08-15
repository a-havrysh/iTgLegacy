#import "TGClient+Premium.h"
#import "TGClient+Private.h"

static NSString *TGPremiumHumanize(NSString *tag){
	if (![tag isKindOfClass:[NSString class]] || !tag.length)
		return @"";
	NSMutableString *out = [NSMutableString stringWithCapacity:tag.length + 8];
	NSUInteger i = 0;
	for (i = 0; i < tag.length; i++){
		unichar c = [tag characterAtIndex:i];
		if (c >= 'A' && c <= 'Z'){
			if (out.length)
				[out appendString:@" "];
			[out appendFormat:@"%C", (unichar)(out.length ? c + 32 : c)];
		} else {
			if (!out.length && c >= 'a' && c <= 'z')
				c = (unichar)(c - 32);
			[out appendFormat:@"%C", c];
		}
	}
	return out;
}

static NSString *TGPremiumTag(NSDictionary *object, NSString *prefix){
	if (![object isKindOfClass:[NSDictionary class]])
		return @"";
	NSString *type = object[@"@type"];
	if (![type isKindOfClass:[NSString class]])
		return @"";
	if (prefix.length && type.length > prefix.length && [type hasPrefix:prefix]){
		NSString *rest = [type substringFromIndex:prefix.length];
		if (!rest.length)
			return @"";
		return [[[rest substringToIndex:1] lowercaseString]
				stringByAppendingString:[rest substringFromIndex:1]];
	}
	return type;
}

static NSString *TGPremiumFullType(NSString *tag, NSString *prefix){
	if (![tag isKindOfClass:[NSString class]] || !tag.length)
		return nil;
	if ([tag hasPrefix:prefix])
		return tag;
	return [prefix stringByAppendingString:
			[[[tag substringToIndex:1] uppercaseString]
			 stringByAppendingString:[tag substringFromIndex:1]]];
}

static BOOL TGPremiumIsError(NSDictionary *result){
	return ![result isKindOfClass:[NSDictionary class]] ||
		   [result[@"@type"] isEqualToString:@"error"];
}

static NSString *TGPremiumErrorText(NSDictionary *result){
	if (![result isKindOfClass:[NSDictionary class]])
		return @"No response from Telegram";
	NSString *message = result[@"message"];
	if ([message isKindOfClass:[NSString class]] && message.length)
		return message;
	return @"Request failed";
}

static NSArray *TGPremiumArray(id value){
	return [value isKindOfClass:[NSArray class]] ? value : [NSArray array];
}

static NSDictionary *TGPremiumDict(id value){
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSString *TGPremiumString(id value){
	return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSNumber *TGPremiumNumber(id value){
	return [value isKindOfClass:[NSNumber class]] ? value : [NSNumber numberWithInt:0];
}

static NSNumber *TGPremiumInt64(id value){
	if ([value isKindOfClass:[NSNumber class]])
		return value;
	if ([value isKindOfClass:[NSString class]])
		return [NSNumber numberWithLongLong:[value longLongValue]];
	return [NSNumber numberWithInt:0];
}

static NSString *TGPremiumFeatureSubtitle(NSString *tag){
	static NSDictionary *table = nil;
	if (!table)
		table = [[NSDictionary alloc] initWithObjectsAndKeys:
				 @"Double the limits on folders, pinned chats and more", @"increasedLimits",
				 @"Send files of up to 4 GB", @"increasedUploadFileSize",
				 @"Download media at the fastest possible speed", @"improvedDownloadSpeed",
				 @"Turn voice messages into text", @"voiceRecognition",
				 @"No sponsored messages in public channels", @"disabledAds",
				 @"React with a much larger set of emoji", @"uniqueReactions",
				 @"Unlock exclusive sticker packs", @"uniqueStickers",
				 @"Use custom emoji anywhere in your messages", @"customEmoji",
				 @"Auto-archive and restrict who can message you", @"advancedChatManagement",
				 @"A star badge next to your name everywhere", @"profileBadge",
				 @"Show an emoji next to your name", @"emojiStatus",
				 @"Set a looping video as your profile photo", @"animatedProfilePhoto",
				 @"Use any custom emoji as a topic icon", @"forumTopicIcon",
				 @"Change the app icon on your home screen", @"appIcons",
				 @"Translate whole chats as you read them", @"realTimeChatTranslation",
				 @"Longer stories, more of them, and priority order", @"upgradedStories",
				 @"Boost channels so they can post stories", @"chatBoost",
				 @"Pick your own name and profile colours", @"accentColor",
				 @"Set a wallpaper for both sides of a chat", @"backgroundForBoth",
				 @"Tag your saved messages by topic", @"savedMessagesTags",
				 @"Hide your forwarded-message link and phone number", @"messagePrivacy",
				 @"See when contacts were last online", @"lastSeenTimes",
				 @"Opening hours, away messages and quick replies", @"business",
				 @"Send animated effects with a message", @"messageEffects",
				 @"Send interactive checklists", @"checklists",
				 @"Charge stars for messages sent to you", @"paidMessages",
				 @"Stop others saving media from your private chats", @"protectPrivateChatContent",
				 nil];
	NSString *text = [table objectForKey:tag];
	return text ? text : @"";
}

static BOOL TGPremiumFeatureSupported(NSString *tag){
	static NSSet *unsupported = nil;
	if (!unsupported)
		unsupported = [[NSSet alloc] initWithObjects:
					   @"customEmoji", @"emojiStatus", @"animatedProfilePhoto",
					   @"forumTopicIcon", @"appIcons", @"uniqueStickers",
					   @"uniqueReactions", @"upgradedStories", @"accentColor",
					   @"backgroundForBoth", @"messageEffects", @"checklists",
					   @"realTimeChatTranslation", @"richMessages",
					   @"textComposition", nil];
	return ![unsupported containsObject:tag];
}

static NSString *TGPremiumBusinessSubtitle(NSString *tag){
	static NSDictionary *table = nil;
	if (!table)
		table = [[NSDictionary alloc] initWithObjectsAndKeys:
				 @"Show your address on your profile", @"location",
				 @"Tell customers when you are open", @"openingHours",
				 @"Save and reuse frequent answers", @"quickReplies",
				 @"Greet new customers automatically", @"greetingMessage",
				 @"Reply automatically while you are away", @"awayMessage",
				 @"Link your other accounts from your profile", @"accountLinks",
				 @"A custom intro on your empty chat screen", @"startPage",
				 @"Let a bot answer for you", @"bots",
				 @"Show an emoji next to your name", @"emojiStatus",
				 @"Colour-tag your chat folders", @"chatFolderTags",
				 @"Longer stories and more of them", @"upgradedStories",
				 nil];
	NSString *text = [table objectForKey:tag];
	return text ? text : @"";
}

static NSArray *TGPremiumDisplayLimitTypes(void){
	static NSArray *types = nil;
	if (!types)
		types = [[NSArray alloc] initWithObjects:
				 @"pinnedChatCount", @"chatFolderCount",
				 @"chatFolderChosenChatCount", @"pinnedArchivedChatCount",
				 @"supergroupCount", @"createdPublicChatCount",
				 @"savedAnimationCount", @"favoriteStickerCount",
				 @"messageTextLength", @"captionLength", @"bioLength", nil];
	return types;
}

@implementation TGClient (Premium)

#pragma mark - account state

- (BOOL)isPremiumAccount {
	NSDictionary *me = self.me;
	return [me isKindOfClass:[NSDictionary class]] &&
		   [me[@"is_premium"] boolValue];
}

+ (BOOL)isPremiumUser:(NSDictionary *)user {
	return [user isKindOfClass:[NSDictionary class]] &&
		   [user[@"is_premium"] boolValue];
}

- (void)premiumOptionNamed:(NSString *)name completion:(void (^)(NSNumber *))completion {
	[self request:@{@"@type" : @"getOption", @"name" : name}
	   completion:^(NSDictionary *option){
		if (!completion)
			return;
		if (TGPremiumIsError(option)){
			completion(nil);
			return;
		}
		id value = option[@"value"];
		if ([value isKindOfClass:[NSNumber class]]){
			completion(value);
			return;
		}
		if ([value isKindOfClass:[NSString class]]){
			completion([NSNumber numberWithLongLong:[value longLongValue]]);
			return;
		}
		completion(nil);
	}];
}

- (void)premiumSubscriptionWithCompletion:(void (^)(NSDictionary *))completion {
	BOOL active = [self isPremiumAccount];
	[self request:@{@"@type" : @"getPremiumState"} completion:^(NSDictionary *state){
		if (!completion)
			return;
		if (TGPremiumIsError(state)){
			completion(nil);
			return;
		}
		NSMutableDictionary *out = [NSMutableDictionary dictionary];
		[out setObject:[NSNumber numberWithBool:active] forKey:@"active"];

		NSDictionary *text = TGPremiumDict(state[@"state"]);
		[out setObject:TGPremiumString(text[@"text"]) forKey:@"text"];

		[out setObject:(active ? @"Active" : @"") forKey:@"expiresText"];

		NSMutableArray *options = [NSMutableArray array];
		NSArray *raw = TGPremiumArray(state[@"payment_options"]);
		for (id entry in raw){
			NSDictionary *wrapper = TGPremiumDict(entry);
			if (!wrapper)
				continue;
			NSDictionary *option = TGPremiumDict(wrapper[@"payment_option"]);
			if (!option)
				continue;
			[options addObject:@{
				@"currency"       : TGPremiumString(option[@"currency"]),
				@"amount"         : TGPremiumNumber(option[@"amount"]),
				@"months"         : TGPremiumNumber(option[@"month_count"]),
				@"discount"       : TGPremiumNumber(option[@"discount_percentage"]),
				@"current"        : [NSNumber numberWithBool:[wrapper[@"is_current"] boolValue]],
				@"upgrade"        : [NSNumber numberWithBool:[wrapper[@"is_upgrade"] boolValue]],
				@"storeProductId" : TGPremiumString(option[@"store_product_id"])
			}];
		}
		[out setObject:options forKey:@"options"];
		completion(out);
	}];
}

- (void)premiumOptionsWithCompletion:(void (^)(NSDictionary *))completion {
	NSArray *names = [NSArray arrayWithObjects:
					  @"is_premium", @"is_premium_available",
					  @"premium_upload_speedup", @"premium_download_speedup",
					  @"premium_max_upload_file_size", @"owned_star_count", nil];
	NSArray *keys = [NSArray arrayWithObjects:
					 @"isPremium", @"isPremiumAvailable",
					 @"uploadSpeedup", @"downloadSpeedup",
					 @"maxUploadFileSize", @"starCount", nil];
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	__block NSUInteger pending = names.count;
	NSUInteger i = 0;
	for (i = 0; i < names.count; i++){
		NSString *key = [keys objectAtIndex:i];
		[self premiumOptionNamed:[names objectAtIndex:i] completion:^(NSNumber *value){
			[out setObject:(value ? value : [NSNumber numberWithInt:0]) forKey:key];
			pending--;
			if (pending == 0){
				if (![out objectForKey:@"maxUploadFileSize"] ||
					![[out objectForKey:@"maxUploadFileSize"] longLongValue])
					[out setObject:[NSNumber numberWithLongLong:2000LL * 1024 * 1024]
							forKey:@"maxUploadFileSize"];
				if (completion)
					completion(out);
			}
		}];
	}
}

#pragma mark - limits

- (void)premiumLimit:(NSString *)limitType
          completion:(void (^)(NSDictionary *))completion {
	NSString *type = TGPremiumFullType(limitType, @"premiumLimitType");
	if (!type){
		if (completion)
			completion(nil);
		return;
	}
	[self request:@{@"@type"      : @"getPremiumLimit",
					@"limit_type" : @{@"@type" : type}}
	   completion:^(NSDictionary *limit){
		if (!completion)
			return;
		if (TGPremiumIsError(limit)){
			completion(nil);
			return;
		}
		NSString *tag = TGPremiumTag(TGPremiumDict(limit[@"type"]), @"premiumLimitType");
		if (!tag.length)
			tag = limitType;
		completion(@{
			@"type"    : tag,
			@"title"   : TGPremiumHumanize(tag),
			@"default" : TGPremiumNumber(limit[@"default_value"]),
			@"premium" : TGPremiumNumber(limit[@"premium_value"])
		});
	}];
}

- (void)premiumLimitsWithCompletion:(void (^)(NSArray *))completion {
	NSArray *types = TGPremiumDisplayLimitTypes();
	NSMutableDictionary *byType = [NSMutableDictionary dictionary];
	__block NSUInteger pending = types.count;
	for (NSString *type in types){
		[self premiumLimit:type completion:^(NSDictionary *limit){
			if (limit)
				[byType setObject:limit forKey:type];
			pending--;
			if (pending == 0){
				NSMutableArray *out = [NSMutableArray array];
				for (NSString *ordered in types){
					NSDictionary *limit = [byType objectForKey:ordered];
					if (limit)
						[out addObject:limit];
				}
				if (completion)
					completion(out);
			}
		}];
	}
}

- (void)effectivePremiumLimit:(NSString *)limitType
                   completion:(void (^)(NSInteger))completion {
	BOOL premium = [self isPremiumAccount];
	[self premiumLimit:limitType completion:^(NSDictionary *limit){
		if (!completion)
			return;
		if (!limit){
			completion(0);
			return;
		}
		completion([limit[premium ? @"premium" : @"default"] integerValue]);
	}];
}

#pragma mark - feature catalogue

- (void)premiumFeaturesWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type"  : @"getPremiumFeatures",
					@"source" : @{@"@type" : @"premiumSourceSettings"}}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPremiumIsError(result)){
			completion([NSArray array]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id entry in TGPremiumArray(result[@"features"])){
			NSString *tag = TGPremiumTag(TGPremiumDict(entry), @"premiumFeature");
			if (!tag.length)
				continue;
			[out addObject:@{
				@"type"      : tag,
				@"title"     : TGPremiumHumanize(tag),
				@"subtitle"  : TGPremiumFeatureSubtitle(tag),
				@"supported" : [NSNumber numberWithBool:TGPremiumFeatureSupported(tag)]
			}];
		}
		completion(out);
	}];
}

- (void)businessFeaturesWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getBusinessFeatures"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPremiumIsError(result)){
			completion([NSArray array]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id entry in TGPremiumArray(result[@"features"])){
			NSString *tag = TGPremiumTag(TGPremiumDict(entry), @"businessFeature");
			if (!tag.length)
				continue;
			[out addObject:@{
				@"type"      : tag,
				@"title"     : TGPremiumHumanize(tag),
				@"subtitle"  : TGPremiumBusinessSubtitle(tag),
				@"supported" : [NSNumber numberWithBool:NO]
			}];
		}
		completion(out);
	}];
}

- (void)viewPremiumFeature:(NSString *)featureType {
	NSString *type = TGPremiumFullType(featureType, @"premiumFeature");
	if (!type)
		return;
	[self send:@{@"@type"   : @"viewPremiumFeature",
				 @"feature" : @{@"@type" : type}}];
}

- (void)clickPremiumSubscriptionButton {
	[self send:@{@"@type" : @"clickPremiumSubscriptionButton"}];
}

- (void)premiumInfoStickerForMonths:(NSInteger)monthCount
                         completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type"       : @"getPremiumInfoSticker",
					@"month_count" : [NSNumber numberWithInteger:monthCount]}
	   completion:^(NSDictionary *sticker){
		if (!completion)
			return;
		if (TGPremiumIsError(sticker)){
			completion(nil);
			return;
		}
		NSDictionary *file = TGPremiumDict(sticker[@"sticker"]);
		NSDictionary *thumb = TGPremiumDict(sticker[@"thumbnail"]);
		NSDictionary *thumbFile = TGPremiumDict(thumb[@"file"]);
		completion(@{
			@"fileId"          : TGPremiumNumber(file[@"id"]),
			@"thumbnailFileId" : TGPremiumNumber(thumbFile[@"id"]),
			@"emoji"           : TGPremiumString(sticker[@"emoji"]),
			@"width"           : TGPremiumNumber(sticker[@"width"]),
			@"height"          : TGPremiumNumber(sticker[@"height"])
		});
	}];
}

#pragma mark - gift codes

- (void)checkGiftCode:(NSString *)code
           completion:(void (^)(NSDictionary *))completion {
	if (![code isKindOfClass:[NSString class]] || !code.length){
		if (completion)
			completion(nil);
		return;
	}
	[self request:@{@"@type" : @"checkPremiumGiftCode", @"code" : code}
	   completion:^(NSDictionary *info){
		if (!completion)
			return;
		if (TGPremiumIsError(info)){
			completion(nil);
			return;
		}
		NSDictionary *creator = TGPremiumDict(info[@"creator_id"]);
		BOOL creatorIsChat = [TGPremiumString(creator[@"@type"])
							  isEqualToString:@"messageSenderChat"];
		NSNumber *creatorId = creatorIsChat ? TGPremiumNumber(creator[@"chat_id"])
											: TGPremiumNumber(creator[@"user_id"]);
		long long useDate = [TGPremiumNumber(info[@"use_date"]) longLongValue];
		completion(@{
			@"code"              : code,
			@"creatorId"         : creatorId,
			@"creatorIsChat"     : [NSNumber numberWithBool:creatorIsChat],
			@"creationDate"      : TGPremiumNumber(info[@"creation_date"]),
			@"fromGiveaway"      : [NSNumber numberWithBool:[info[@"is_from_giveaway"] boolValue]],
			@"giveawayMessageId" : TGPremiumNumber(info[@"giveaway_message_id"]),
			@"months"            : TGPremiumNumber(info[@"month_count"]),
			@"days"              : TGPremiumNumber(info[@"day_count"]),
			@"userId"            : TGPremiumNumber(info[@"user_id"]),
			@"useDate"           : TGPremiumNumber(info[@"use_date"]),
			@"used"              : [NSNumber numberWithBool:useDate > 0]
		});
	}];
}

- (void)applyGiftCode:(NSString *)code
           completion:(void (^)(BOOL, NSString *))completion {
	if (![code isKindOfClass:[NSString class]] || !code.length){
		if (completion)
			completion(NO, @"Enter a gift code");
		return;
	}
	[self request:@{@"@type" : @"applyPremiumGiftCode", @"code" : code}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPremiumIsError(result)){
			completion(NO, TGPremiumErrorText(result));
			return;
		}
		completion(YES, nil);
	}];
}

- (void)redeemGiftCode:(NSString *)code
            completion:(void (^)(BOOL, NSDictionary *, NSString *))completion {
	[self checkGiftCode:code completion:^(NSDictionary *info){
		if (!info){
			if (completion)
				completion(NO, nil, @"This gift code is not valid");
			return;
		}
		if ([info[@"used"] boolValue]){
			if (completion)
				completion(NO, info, @"This gift code has already been used");
			return;
		}
		[self applyGiftCode:code completion:^(BOOL ok, NSString *error){
			if (completion)
				completion(ok, info, error);
		}];
	}];
}

#pragma mark - gifting premium

- (void)giftPremiumToUser:(int64_t)userId
                   months:(NSInteger)months
                    stars:(long long)stars
                  message:(NSString *)message
               completion:(void (^)(BOOL, NSString *))completion {
	NSString *text = [message isKindOfClass:[NSString class]] ? message : @"";
	[self request:@{@"@type"       : @"giftPremiumWithStars",
					@"user_id"     : [NSNumber numberWithLongLong:userId],
					@"star_count"  : [NSNumber numberWithLongLong:stars],
					@"month_count" : [NSNumber numberWithInteger:months],
					@"text"        : @{@"@type"    : @"formattedText",
									   @"text"     : text,
									   @"entities" : [NSArray array]}}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPremiumIsError(result)){
			completion(NO, TGPremiumErrorText(result));
			return;
		}
		completion(YES, nil);
	}];
}

#pragma mark - giveaways

- (void)giveawayInfoForMessage:(int64_t)messageId
                        inChat:(int64_t)chatId
                    completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type"      : @"getGiveawayInfo",
					@"chat_id"    : [NSNumber numberWithLongLong:chatId],
					@"message_id" : [NSNumber numberWithLongLong:messageId]}
	   completion:^(NSDictionary *info){
		if (!completion)
			return;
		if (TGPremiumIsError(info)){
			completion(nil);
			return;
		}
		BOOL ongoing = [TGPremiumString(info[@"@type"])
						isEqualToString:@"giveawayInfoOngoing"];
		NSMutableDictionary *out = [NSMutableDictionary dictionary];
		[out setObject:[NSNumber numberWithBool:ongoing] forKey:@"ongoing"];
		[out setObject:TGPremiumNumber(info[@"creation_date"]) forKey:@"creationDate"];

		if (ongoing){
			NSDictionary *status = TGPremiumDict(info[@"status"]);
			NSString *tag = TGPremiumTag(status, @"giveawayParticipantStatus");
			BOOL ended = [info[@"is_ended"] boolValue];
			NSString *statusText = @"You are eligible to take part in this giveaway.";
			if ([tag isEqualToString:@"participating"])
				statusText = @"You are taking part in this giveaway.";
			else if ([tag isEqualToString:@"alreadyWasMember"])
				statusText = @"You joined this channel before the giveaway started, so you cannot take part.";
			else if ([tag isEqualToString:@"administrator"])
				statusText = @"You are an administrator of one of the channels, so you cannot take part.";
			else if ([tag isEqualToString:@"disallowedCountry"])
				statusText = @"Your country is not among the ones this giveaway is open to.";
			if (ended)
				statusText = [statusText stringByAppendingString:
							  @" The winners are being selected."];
			[out setObject:[NSNumber numberWithBool:ended] forKey:@"ended"];
			[out setObject:tag forKey:@"status"];
			[out setObject:statusText forKey:@"statusText"];
			[out setObject:TGPremiumNumber(status[@"joined_chat_date"]) forKey:@"joinedDate"];
			[out setObject:TGPremiumNumber(status[@"chat_id"]) forKey:@"adminChatId"];
			[out setObject:TGPremiumString(status[@"user_country_code"]) forKey:@"countryCode"];
			completion(out);
			return;
		}

		BOOL winner = [info[@"is_winner"] boolValue];
		BOOL refunded = [info[@"was_refunded"] boolValue];
		NSString *giftCode = TGPremiumString(info[@"gift_code"]);
		long long wonStars = [TGPremiumNumber(info[@"won_star_count"]) longLongValue];
		NSString *statusText = @"This giveaway has ended. You were not among the winners.";
		if (refunded)
			statusText = @"This giveaway was cancelled and the payment was refunded.";
		else if (winner && giftCode.length)
			statusText = @"You won this giveaway. Redeem your gift code to activate Premium.";
		else if (winner && wonStars > 0)
			statusText = [NSString stringWithFormat:
						  @"You won this giveaway and received %lld stars.", wonStars];
		else if (winner)
			statusText = @"You won this giveaway.";
		[out setObject:@"" forKey:@"status"];
		[out setObject:[NSNumber numberWithBool:YES] forKey:@"ended"];
		[out setObject:statusText forKey:@"statusText"];
		[out setObject:TGPremiumNumber(info[@"actual_winners_selection_date"])
				forKey:@"winnersDate"];
		[out setObject:TGPremiumNumber(info[@"winner_count"]) forKey:@"winnerCount"];
		[out setObject:TGPremiumNumber(info[@"activation_count"]) forKey:@"activationCount"];
		[out setObject:[NSNumber numberWithBool:winner] forKey:@"winner"];
		[out setObject:[NSNumber numberWithBool:refunded] forKey:@"refunded"];
		[out setObject:giftCode forKey:@"giftCode"];
		[out setObject:[NSNumber numberWithLongLong:wonStars] forKey:@"wonStars"];
		completion(out);
	}];
}

- (void)launchPrepaidGiveaway:(long long)giveawayId
                       inChat:(int64_t)chatId
                  winnerCount:(NSInteger)winnerCount
                 winnersDate:(NSTimeInterval)winnersDate
               onlyNewMembers:(BOOL)onlyNewMembers
             hasPublicWinners:(BOOL)hasPublicWinners
                 countryCodes:(NSArray *)countryCodes
             prizeDescription:(NSString *)prizeDescription
                        stars:(long long)stars
                   completion:(void (^)(BOOL, NSString *))completion {
	NSArray *countries = [countryCodes isKindOfClass:[NSArray class]]
						 ? countryCodes : [NSArray array];
	NSString *description = [prizeDescription isKindOfClass:[NSString class]]
							? prizeDescription : @"";
	NSDictionary *parameters = @{
		@"@type"                   : @"giveawayParameters",
		@"boosted_chat_id"         : [NSNumber numberWithLongLong:chatId],
		@"additional_chat_ids"     : [NSArray array],
		@"winners_selection_date"  : [NSNumber numberWithLongLong:(long long)winnersDate],
		@"only_new_members"        : [NSNumber numberWithBool:onlyNewMembers],
		@"has_public_winners"      : [NSNumber numberWithBool:hasPublicWinners],
		@"country_codes"           : countries,
		@"prize_description"       : description
	};
	[self request:@{@"@type"        : @"launchPrepaidGiveaway",
					@"giveaway_id"  : [NSNumber numberWithLongLong:giveawayId],
					@"parameters"   : parameters,
					@"winner_count" : [NSNumber numberWithInteger:winnerCount],
					@"star_count"   : [NSNumber numberWithLongLong:stars]}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPremiumIsError(result)){
			completion(NO, TGPremiumErrorText(result));
			return;
		}
		completion(YES, nil);
	}];
}

#pragma mark - channel boosts

- (void)chatBoostStatusForChat:(int64_t)chatId
                    completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type"   : @"getChatBoostStatus",
					@"chat_id" : [NSNumber numberWithLongLong:chatId]}
	   completion:^(NSDictionary *status){
		if (!completion)
			return;
		if (TGPremiumIsError(status)){
			completion(nil);
			return;
		}
		NSArray *applied = TGPremiumArray(status[@"applied_slot_ids"]);
		double current = [TGPremiumNumber(status[@"current_level_boost_count"]) doubleValue];
		double next = [TGPremiumNumber(status[@"next_level_boost_count"]) doubleValue];
		double have = [TGPremiumNumber(status[@"boost_count"]) doubleValue];
		double progress = 1.0;
		if (next > current)
			progress = (have - current) / (next - current);
		if (progress < 0.0)
			progress = 0.0;
		if (progress > 1.0)
			progress = 1.0;

		NSMutableArray *prepaid = [NSMutableArray array];
		for (id entry in TGPremiumArray(status[@"prepaid_giveaways"])){
			NSDictionary *giveaway = TGPremiumDict(entry);
			if (!giveaway)
				continue;
			NSDictionary *prize = TGPremiumDict(giveaway[@"prize"]);
			[prepaid addObject:@{
				@"id"          : TGPremiumInt64(giveaway[@"id"]),
				@"winnerCount" : TGPremiumNumber(giveaway[@"winner_count"]),
				@"boostCount"  : TGPremiumNumber(giveaway[@"boost_count"]),
				@"paymentDate" : TGPremiumNumber(giveaway[@"payment_date"]),
				@"prizeMonths" : TGPremiumNumber(prize[@"month_count"]),
				@"prizeStars"  : TGPremiumNumber(prize[@"star_count"])
			}];
		}

		completion(@{
			@"level"                   : TGPremiumNumber(status[@"level"]),
			@"boostCount"              : TGPremiumNumber(status[@"boost_count"]),
			@"giftCodeBoostCount"      : TGPremiumNumber(status[@"gift_code_boost_count"]),
			@"currentLevelBoostCount"  : TGPremiumNumber(status[@"current_level_boost_count"]),
			@"nextLevelBoostCount"     : TGPremiumNumber(status[@"next_level_boost_count"]),
			@"premiumMemberCount"      : TGPremiumNumber(status[@"premium_member_count"]),
			@"premiumMemberPercentage" : TGPremiumNumber(status[@"premium_member_percentage"]),
			@"progress"                : [NSNumber numberWithDouble:progress],
			@"boostUrl"                : TGPremiumString(status[@"boost_url"]),
			@"appliedSlotIds"          : applied,
			@"boosted"                 : [NSNumber numberWithBool:applied.count > 0],
			@"prepaidGiveaways"        : prepaid
		});
	}];
}

- (void)chatBoostLinkForChat:(int64_t)chatId
                  completion:(void (^)(NSString *, BOOL))completion {
	[self request:@{@"@type"   : @"getChatBoostLink",
					@"chat_id" : [NSNumber numberWithLongLong:chatId]}
	   completion:^(NSDictionary *link){
		if (!completion)
			return;
		if (TGPremiumIsError(link)){
			completion(nil, NO);
			return;
		}
		completion(TGPremiumString(link[@"link"]), [link[@"is_public"] boolValue]);
	}];
}

- (void)chatBoostLinkInfo:(NSString *)url
               completion:(void (^)(int64_t, BOOL))completion {
	if (![url isKindOfClass:[NSString class]] || !url.length){
		if (completion)
			completion(0, NO);
		return;
	}
	[self request:@{@"@type" : @"getChatBoostLinkInfo", @"url" : url}
	   completion:^(NSDictionary *info){
		if (!completion)
			return;
		if (TGPremiumIsError(info)){
			completion(0, NO);
			return;
		}
		completion([TGPremiumNumber(info[@"chat_id"]) longLongValue],
				   [info[@"is_public"] boolValue]);
	}];
}

- (NSDictionary *)giftCodeEntryFromMessage:(NSDictionary *)message {
	NSDictionary *content = TGPremiumDict(message[@"content"]);
	NSString *tag = TGPremiumTag(content, @"message");
	if (!([tag isEqualToString:@"premiumGiftCode"] ||
		  [tag isEqualToString:@"giveawayPrizeStars"]))
		return nil;

	NSDictionary *creator = TGPremiumDict(content[@"creator_id"]);
	BOOL creatorIsChat = [TGPremiumString(creator[@"@type"])
						  isEqualToString:@"messageSenderChat"];
	NSNumber *creatorId = creatorIsChat ? TGPremiumNumber(creator[@"chat_id"])
										: TGPremiumNumber(creator[@"user_id"]);
	NSString *creatorName = @"";
	if (creatorIsChat){
		id title = [self.chatsById[creatorId] objectForKey:@"title"];
		if ([title isKindOfClass:[NSString class]])
			creatorName = title;
	} else {
		id name = [self.usersById objectForKey:creatorId];
		if ([name isKindOfClass:[NSString class]])
			creatorName = name;
	}

	NSDictionary *formatted = TGPremiumDict(content[@"text"]);
	NSString *text = TGPremiumString(formatted[@"text"]);

	return @{
		@"code"              : TGPremiumString(content[@"code"]),
		@"months"            : TGPremiumNumber(content[@"month_count"]),
		@"days"              : TGPremiumNumber(content[@"day_count"]),
		@"stars"             : TGPremiumNumber(content[@"star_count"]),
		@"fromGiveaway"      : [NSNumber numberWithBool:
								[content[@"is_from_giveaway"] boolValue] ||
								[tag isEqualToString:@"giveawayPrizeStars"]],
		@"unclaimed"         : [NSNumber numberWithBool:
								[content[@"is_unclaimed"] boolValue]],
		@"creatorId"         : creatorId,
		@"creatorIsChat"     : [NSNumber numberWithBool:creatorIsChat],
		@"creatorName"       : creatorName,
		@"chatId"            : TGPremiumNumber(message[@"chat_id"]),
		@"messageId"         : TGPremiumNumber(message[@"id"]),
		@"boostedChatId"     : TGPremiumNumber(content[@"boosted_chat_id"]),
		@"giveawayMessageId" : TGPremiumNumber(content[@"giveaway_message_id"]),
		@"date"              : TGPremiumNumber(message[@"date"]),
		@"text"              : text
	};
}

- (void)accountGiftCodesWithLimit:(NSInteger)limit
                       completion:(void (^)(NSArray *))completion {
	NSInteger count = limit > 0 ? limit : 100;
	if (count > 100)
		count = 100;
	[self request:@{@"@type"   : @"createPrivateChat",
					@"user_id" : [NSNumber numberWithLongLong:777000LL],
					@"force"   : [NSNumber numberWithBool:NO]}
	   completion:^(NSDictionary *chat){
		if (TGPremiumIsError(chat)){
			if (completion)
				completion([NSArray array]);
			return;
		}
		long long chatId = [TGPremiumNumber(chat[@"id"]) longLongValue];
		if (!chatId)
			chatId = 777000LL;
		NSDictionary *query = @{@"@type"           : @"getChatHistory",
								@"chat_id"         : [NSNumber numberWithLongLong:chatId],
								@"from_message_id" : [NSNumber numberWithInt:0],
								@"offset"          : [NSNumber numberWithInt:0],
								@"limit"           : [NSNumber numberWithInteger:count],
								@"only_local"      : [NSNumber numberWithBool:NO]};
		[self request:query completion:^(NSDictionary *first){
			NSArray *messages = TGPremiumIsError(first) ? [NSArray array]
														: TGPremiumArray(first[@"messages"]);
			if (messages.count){
				if (completion)
					completion([self giftCodeEntriesFromMessages:messages]);
				return;
			}
			[self request:query completion:^(NSDictionary *second){
				if (!completion)
					return;
				if (TGPremiumIsError(second)){
					completion([NSArray array]);
					return;
				}
				completion([self giftCodeEntriesFromMessages:
							TGPremiumArray(second[@"messages"])]);
			}];
		}];
	}];
}

- (NSArray *)giftCodeEntriesFromMessages:(NSArray *)messages {
	NSMutableArray *out = [NSMutableArray array];
	for (id entry in TGPremiumArray(messages)){
		NSDictionary *message = TGPremiumDict(entry);
		if (!message)
			continue;
		NSDictionary *code = [self giftCodeEntryFromMessage:message];
		if (code)
			[out addObject:code];
	}
	return out;
}

- (NSDictionary *)giveawayEntryFromMessage:(NSDictionary *)message {
	NSDictionary *content = TGPremiumDict(message[@"content"]);
	if (![TGPremiumTag(content, @"message") isEqualToString:@"giveaway"])
		return nil;
	NSDictionary *parameters = TGPremiumDict(content[@"parameters"]);
	NSDictionary *prize = TGPremiumDict(content[@"prize"]);
	NSNumber *chatId = TGPremiumNumber(message[@"chat_id"]);
	id title = [self.chatsById[chatId] objectForKey:@"title"];
	return @{
		@"chatId"      : chatId,
		@"chatTitle"   : [title isKindOfClass:[NSString class]] ? title : @"",
		@"messageId"   : TGPremiumNumber(message[@"id"]),
		@"date"        : TGPremiumNumber(message[@"date"]),
		@"winnerCount" : TGPremiumNumber(content[@"winner_count"]),
		@"months"      : TGPremiumNumber(prize[@"month_count"]),
		@"stars"       : TGPremiumNumber(prize[@"star_count"]),
		@"winnersDate" : TGPremiumNumber(parameters[@"winners_selection_date"])
	};
}

- (void)enteredGiveawaysWithLimit:(NSInteger)limit
                       completion:(void (^)(NSArray *))completion {
	NSInteger cap = limit > 0 ? limit : 20;
	[self request:@{@"@type" : @"getAvailableChatBoostSlots"}
	   completion:^(NSDictionary *result){
		NSMutableArray *chatIds = [NSMutableArray array];
		for (id entry in TGPremiumIsError(result) ? [NSArray array]
												  : TGPremiumArray(result[@"slots"])){
			NSDictionary *slot = TGPremiumDict(entry);
			NSNumber *chatId = TGPremiumNumber(slot[@"currently_boosted_chat_id"]);
			if ([chatId longLongValue] && ![chatIds containsObject:chatId])
				[chatIds addObject:chatId];
		}
		if (!chatIds.count){
			if (completion)
				completion([NSArray array]);
			return;
		}
		[self collectGiveawayMessagesFromChats:chatIds
										 index:0
									   results:[NSMutableArray array]
										   cap:cap
									completion:completion];
	}];
}

- (void)collectGiveawayMessagesFromChats:(NSArray *)chatIds
                                   index:(NSUInteger)index
                                 results:(NSMutableArray *)results
                                     cap:(NSInteger)cap
                              completion:(void (^)(NSArray *))completion {
	if (index >= chatIds.count || (NSInteger)results.count >= cap){
		[results sortUsingComparator:^NSComparisonResult(id a, id b){
			long long left = [TGPremiumNumber([a objectForKey:@"date"]) longLongValue];
			long long right = [TGPremiumNumber([b objectForKey:@"date"]) longLongValue];
			if (left == right)
				return NSOrderedSame;
			return left > right ? NSOrderedAscending : NSOrderedDescending;
		}];
		[self attachGiveawayInfoAtIndex:0 entries:results completion:completion];
		return;
	}
	long long chatId = [TGPremiumNumber([chatIds objectAtIndex:index]) longLongValue];
	[self request:@{@"@type"           : @"getChatHistory",
					@"chat_id"         : [NSNumber numberWithLongLong:chatId],
					@"from_message_id" : [NSNumber numberWithInt:0],
					@"offset"          : [NSNumber numberWithInt:0],
					@"limit"           : [NSNumber numberWithInt:40],
					@"only_local"      : [NSNumber numberWithBool:NO]}
	   completion:^(NSDictionary *history){
		if (!TGPremiumIsError(history)){
			for (id entry in TGPremiumArray(history[@"messages"])){
				NSDictionary *message = TGPremiumDict(entry);
				if (!message)
					continue;
				NSDictionary *giveaway = [self giveawayEntryFromMessage:message];
				if (giveaway && (NSInteger)results.count < cap)
					[results addObject:[NSMutableDictionary
										dictionaryWithDictionary:giveaway]];
			}
		}
		[self collectGiveawayMessagesFromChats:chatIds
										 index:index + 1
									   results:results
										   cap:cap
									completion:completion];
	}];
}

- (void)attachGiveawayInfoAtIndex:(NSUInteger)index
                          entries:(NSMutableArray *)entries
                       completion:(void (^)(NSArray *))completion {
	if (index >= entries.count){
		if (completion)
			completion(entries);
		return;
	}
	NSMutableDictionary *entry = [entries objectAtIndex:index];
	long long chatId = [TGPremiumNumber([entry objectForKey:@"chatId"]) longLongValue];
	long long messageId = [TGPremiumNumber([entry objectForKey:@"messageId"]) longLongValue];
	[self giveawayInfoForMessage:messageId
						  inChat:chatId
					  completion:^(NSDictionary *info){
		if ([info isKindOfClass:[NSDictionary class]])
			[entry addEntriesFromDictionary:info];
		[self attachGiveawayInfoAtIndex:index + 1
								entries:entries
							 completion:completion];
	}];
}

- (NSArray *)boostSlotsFromResult:(NSDictionary *)result {
	NSMutableArray *out = [NSMutableArray array];
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	for (id entry in TGPremiumArray(result[@"slots"])){
		NSDictionary *slot = TGPremiumDict(entry);
		if (!slot)
			continue;
		long long chatId = [TGPremiumNumber(slot[@"currently_boosted_chat_id"]) longLongValue];
		long long cooldown = [TGPremiumNumber(slot[@"cooldown_until_date"]) longLongValue];
		[out addObject:@{
			@"slotId"         : TGPremiumNumber(slot[@"slot_id"]),
			@"chatId"         : [NSNumber numberWithLongLong:chatId],
			@"startDate"      : TGPremiumNumber(slot[@"start_date"]),
			@"expirationDate" : TGPremiumNumber(slot[@"expiration_date"]),
			@"cooldownUntil"  : [NSNumber numberWithLongLong:cooldown],
			@"free"           : [NSNumber numberWithBool:chatId == 0],
			@"reassignable"   : [NSNumber numberWithBool:
								 chatId != 0 && (double)cooldown <= now]
		}];
	}
	return out;
}

- (void)availableBoostSlotsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getAvailableChatBoostSlots"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPremiumIsError(result)){
			completion([NSArray array]);
			return;
		}
		completion([self boostSlotsFromResult:result]);
	}];
}

- (void)boostChat:(int64_t)chatId
        withSlots:(NSArray *)slotIds
       completion:(void (^)(BOOL, NSArray *, NSString *))completion {
	NSArray *slots = [slotIds isKindOfClass:[NSArray class]] ? slotIds : [NSArray array];
	if (!slots.count){
		if (completion)
			completion(NO, [NSArray array], @"No boost slot selected");
		return;
	}
	[self request:@{@"@type"    : @"boostChat",
					@"chat_id"  : [NSNumber numberWithLongLong:chatId],
					@"slot_ids" : slots}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPremiumIsError(result)){
			completion(NO, [NSArray array], TGPremiumErrorText(result));
			return;
		}
		completion(YES, [self boostSlotsFromResult:result], nil);
	}];
}

- (void)boostChat:(int64_t)chatId
       completion:(void (^)(BOOL, NSArray *, NSString *))completion {
	[self availableBoostSlotsWithCompletion:^(NSArray *slots){
		NSMutableArray *free = [NSMutableArray array];
		for (NSDictionary *slot in slots){
			if ([slot[@"free"] boolValue])
				[free addObject:slot[@"slotId"]];
		}
		if (!free.count){
			if (completion)
				completion(NO, slots, slots.count
						   ? @"All of your boosts are already in use"
						   : @"Only Telegram Premium subscribers can boost channels");
			return;
		}
		[self boostChat:chatId withSlots:free completion:^(BOOL ok, NSArray *updated, NSString *error){
			if (completion)
				completion(ok, ok ? updated : slots, error);
		}];
	}];
}

- (void)boostersInChat:(int64_t)chatId
        onlyGiftCodes:(BOOL)onlyGiftCodes
                offset:(NSString *)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSDictionary *))completion {
	NSString *from = [offset isKindOfClass:[NSString class]] ? offset : @"";
	NSInteger count = limit > 0 ? limit : 50;
	[self request:@{@"@type"           : @"getChatBoosts",
					@"chat_id"         : [NSNumber numberWithLongLong:chatId],
					@"only_gift_codes" : [NSNumber numberWithBool:onlyGiftCodes],
					@"offset"          : from,
					@"limit"           : [NSNumber numberWithInteger:count]}
	   completion:^(NSDictionary *found){
		if (!completion)
			return;
		if (TGPremiumIsError(found)){
			completion(nil);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id entry in TGPremiumArray(found[@"boosts"])){
			NSDictionary *boost = TGPremiumDict(entry);
			if (!boost)
				continue;
			NSDictionary *source = TGPremiumDict(boost[@"source"]);
			NSString *tag = TGPremiumTag(source, @"chatBoostSource");
			NSNumber *userId = TGPremiumNumber(source[@"user_id"]);
			id name = [self.usersById objectForKey:userId];
			[out addObject:@{
				@"id"                : TGPremiumString(boost[@"id"]),
				@"count"             : TGPremiumNumber(boost[@"count"]),
				@"startDate"         : TGPremiumNumber(boost[@"start_date"]),
				@"expirationDate"    : TGPremiumNumber(boost[@"expiration_date"]),
				@"userId"            : userId,
				@"name"              : [name isKindOfClass:[NSString class]] ? name : @"",
				@"source"            : tag,
				@"giftCode"          : TGPremiumString(source[@"gift_code"]),
				@"giveawayMessageId" : TGPremiumNumber(source[@"giveaway_message_id"]),
				@"unclaimed"         : [NSNumber numberWithBool:
										[source[@"is_unclaimed"] boolValue]]
			}];
		}
		completion(@{
			@"totalCount" : TGPremiumNumber(found[@"total_count"]),
			@"nextOffset" : TGPremiumString(found[@"next_offset"]),
			@"boosts"     : out
		});
	}];
}

- (void)boostFeaturesForChannel:(BOOL)isChannel
                     completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type"      : @"getChatBoostFeatures",
					@"is_channel" : [NSNumber numberWithBool:isChannel]}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPremiumIsError(result)){
			completion([NSArray array]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id entry in TGPremiumArray(result[@"features"])){
			NSDictionary *level = TGPremiumDict(entry);
			if (!level)
				continue;
			NSMutableArray *lines = [NSMutableArray array];
			NSInteger stories = [TGPremiumNumber(level[@"story_per_day_count"]) integerValue];
			if (stories > 0)
				[lines addObject:[NSString stringWithFormat:@"%d stories per day",
								  (int)stories]];
			NSInteger reactions = [TGPremiumNumber(level[@"custom_emoji_reaction_count"]) integerValue];
			if (reactions > 0)
				[lines addObject:[NSString stringWithFormat:@"%d custom reactions",
								  (int)reactions]];
			NSInteger titleColors = [TGPremiumNumber(level[@"title_color_count"]) integerValue];
			if (titleColors > 0)
				[lines addObject:[NSString stringWithFormat:@"%d name colours",
								  (int)titleColors]];
			NSInteger accents = [TGPremiumNumber(level[@"accent_color_count"]) integerValue];
			if (accents > 0)
				[lines addObject:[NSString stringWithFormat:@"%d profile colours",
								  (int)accents]];
			NSInteger backgrounds = [TGPremiumNumber(level[@"chat_theme_background_count"]) integerValue];
			if (backgrounds > 0)
				[lines addObject:[NSString stringWithFormat:@"%d chat themes",
								  (int)backgrounds]];
			if ([level[@"can_set_custom_background"] boolValue])
				[lines addObject:@"Custom chat background"];
			if ([level[@"can_set_emoji_status"] boolValue])
				[lines addObject:@"Emoji status"];
			if ([level[@"can_set_custom_emoji_sticker_set"] boolValue])
				[lines addObject:@"Custom emoji pack"];
			if ([level[@"can_recognize_speech"] boolValue])
				[lines addObject:@"Voice message transcription"];
			if ([level[@"can_enable_automatic_translation"] boolValue])
				[lines addObject:@"Automatic translation"];
			if ([level[@"can_disable_sponsored_messages"] boolValue])
				[lines addObject:@"No sponsored messages"];
			[out addObject:@{
				@"level"    : TGPremiumNumber(level[@"level"]),
				@"features" : lines
			}];
		}
		completion(out);
	}];
}

#pragma mark - stars

- (void)starTransactionsWithOffset:(NSString *)offset
                             limit:(NSInteger)limit
                        completion:(void (^)(NSDictionary *))completion {
	NSDictionary *me = self.me;
	long long myId = [TGPremiumNumber(me[@"id"]) longLongValue];
	NSString *from = [offset isKindOfClass:[NSString class]] ? offset : @"";
	NSInteger count = limit > 0 ? limit : 50;
	[self request:@{@"@type"           : @"getStarTransactions",
					@"owner_id"        : @{@"@type"   : @"messageSenderUser",
										   @"user_id" : [NSNumber numberWithLongLong:myId]},
					@"subscription_id" : @"",
					@"offset"          : from,
					@"limit"           : [NSNumber numberWithInteger:count]}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPremiumIsError(result)){
			completion(nil);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id entry in TGPremiumArray(result[@"transactions"])){
			NSDictionary *transaction = TGPremiumDict(entry);
			if (!transaction)
				continue;
			NSDictionary *amount = TGPremiumDict(transaction[@"star_amount"]);
			NSString *tag = TGPremiumTag(TGPremiumDict(transaction[@"type"]),
										 @"starTransactionType");
			[out addObject:@{
				@"id"     : TGPremiumString(transaction[@"id"]),
				@"stars"  : TGPremiumNumber(amount[@"star_count"]),
				@"refund" : [NSNumber numberWithBool:[transaction[@"is_refund"] boolValue]],
				@"date"   : TGPremiumNumber(transaction[@"date"]),
				@"type"   : tag,
				@"title"  : TGPremiumHumanize(tag)
			}];
		}
		NSDictionary *balance = TGPremiumDict(result[@"star_amount"]);
		completion(@{
			@"balance"      : TGPremiumNumber(balance[@"star_count"]),
			@"nextOffset"   : TGPremiumString(result[@"next_offset"]),
			@"transactions" : out
		});
	}];
}


#pragma mark - voice recognition

- (void)recognizeSpeechInMessage:(int64_t)messageId
                          inChat:(int64_t)chatId
                      completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type"      : @"recognizeSpeech",
					@"chat_id"    : [NSNumber numberWithLongLong:chatId],
					@"message_id" : [NSNumber numberWithLongLong:messageId]}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGPremiumIsError(result)){
			completion(NO, TGPremiumErrorText(result));
			return;
		}
		completion(YES, nil);
	}];
}

+ (NSDictionary *)speechRecognitionFromMessage:(NSDictionary *)message {
	NSDictionary *content = TGPremiumDict(TGPremiumDict(message)[@"content"]);
	NSDictionary *note = TGPremiumDict(content[@"voice_note"]);
	if (!note)
		note = TGPremiumDict(content[@"video_note"]);
	NSDictionary *result = TGPremiumDict(note[@"speech_recognition_result"]);
	if (!result)
		return @{@"state" : @"none", @"text" : @""};
	NSString *type = TGPremiumString(result[@"@type"]);
	if ([type isEqualToString:@"speechRecognitionResultPending"])
		return @{@"state" : @"pending",
				 @"text"  : TGPremiumString(result[@"partial_text"])};
	if ([type isEqualToString:@"speechRecognitionResultText"])
		return @{@"state" : @"text", @"text" : TGPremiumString(result[@"text"])};
	if ([type isEqualToString:@"speechRecognitionResultError"]){
		NSDictionary *error = TGPremiumDict(result[@"error"]);
		return @{@"state" : @"error",
				 @"text"  : TGPremiumString(error[@"message"])};
	}
	return @{@"state" : @"none", @"text" : @""};
}

@end

// vim:ft=objc

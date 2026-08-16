#import "TGClient+Private.h"
#import "TGClient+Contacts.h"

NSString *const TGContactsDidChangeNotification = @"TGContactsDidChangeNotification";

static NSDictionary *TGDict(id value){
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *TGArray(id value){
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSString *TGString(id value){
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static long long TGInt64(id value){
	if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class])
		return [value longLongValue];
	return 0;
}

static BOOL TGIsError(NSDictionary *result){
	return ![result isKindOfClass:NSDictionary.class] ||
	       [result[@"@type"] isEqualToString:@"error"];
}

static NSNumber *TGFileId(NSDictionary *file){
	NSDictionary *f = TGDict(file);
	NSNumber *fid = [f[@"id"] isKindOfClass:NSNumber.class] ? f[@"id"] : nil;
	return fid;
}

static NSString *TGFirstUsername(NSDictionary *user){
	NSDictionary *names = TGDict(user[@"usernames"]);
	NSArray *active = TGArray(names[@"active_usernames"]);
	if (active.count && [active[0] isKindOfClass:NSString.class])
		return active[0];
	return TGString(names[@"editable_username"]);
}

static NSDictionary *TGFlatUser(NSDictionary *u){
	if (![u isKindOfClass:NSDictionary.class] ||
	    ![u[@"@type"] isEqualToString:@"user"])
		return nil;
	NSNumber *photo = TGFileId(TGDict(u[@"profile_photo"])[@"small"]);
	return @{
		@"id"              : u[@"id"] ?: @(0),
		@"first_name"      : TGString(u[@"first_name"]),
		@"last_name"       : TGString(u[@"last_name"]),
		@"phone"           : TGString(u[@"phone_number"]),
		@"username"        : TGFirstUsername(u),
		@"photoFileId"     : photo ?: (id)[NSNull null],
		@"isContact"       : @([u[@"is_contact"] boolValue]),
		@"isMutualContact" : @([u[@"is_mutual_contact"] boolValue]),
		@"isCloseFriend"   : @([u[@"is_close_friend"] boolValue]),
		@"isPremium"       : @([u[@"is_premium"] boolValue]),
	};
}

static NSString *TGProfileTabName(id tab){
	NSString *type = TGString(TGDict(tab)[@"@type"]);
	if (![type hasPrefix:@"profileTab"] || type.length <= 10)
		return nil;
	return [[type substringFromIndex:10] lowercaseString];
}

static NSDictionary *TGBirthdateInfo(id value){
	NSDictionary *b = TGDict(value);
	NSInteger day = [b[@"day"] integerValue];
	NSInteger month = [b[@"month"] integerValue];
	if (day < 1 || month < 1 || month > 12)
		return nil;
	static NSString *const months[12] = {
		@"January", @"February", @"March", @"April", @"May", @"June",
		@"July", @"August", @"September", @"October", @"November", @"December"
	};
	NSInteger year = [b[@"year"] integerValue];
	NSString *text = year > 0
		? [NSString stringWithFormat:@"%d %@ %d", (int)day, months[month - 1], (int)year]
		: [NSString stringWithFormat:@"%d %@", (int)day, months[month - 1]];
	return @{ @"day" : @(day), @"month" : @(month), @"year" : @(year), @"text" : text };
}

@implementation TGClient (Contacts)

#pragma mark - shared plumbing

- (void)tg_fetchUsers:(NSArray *)ids completion:(void (^)(NSArray *))completion {
	NSMutableArray *wanted = [NSMutableArray array];
	for (id uid in TGArray(ids) ?: @[]){
		if ([uid isKindOfClass:NSNumber.class] && [uid longLongValue] != 0)
			[wanted addObject:uid];
	}
	if (!wanted.count){
		if (completion) completion(@[]);
		return;
	}
	NSMutableArray *slots = [NSMutableArray array];
	for (NSUInteger i = 0; i < wanted.count; i++)
		[slots addObject:[NSNull null]];

	__block NSUInteger left = wanted.count;
	for (NSUInteger i = 0; i < wanted.count; i++){
		NSUInteger index = i;
		[self request:@{ @"@type" : @"getUser", @"user_id" : wanted[i] }
		   completion:^(NSDictionary *u){
			NSDictionary *flat = TGFlatUser(u);
			if (flat)
				[slots replaceObjectAtIndex:index withObject:flat];
			if (--left > 0)
				return;
			NSMutableArray *users = [NSMutableArray array];
			for (id slot in slots){
				if ([slot isKindOfClass:NSDictionary.class])
					[users addObject:slot];
			}
			if (completion)
				completion(users);
		}];
	}
}

- (void)tg_fetchChats:(NSArray *)ids completion:(void (^)(NSArray *))completion {
	NSArray *chatIds = TGArray(ids);
	if (!chatIds.count){
		if (completion) completion(@[]);
		return;
	}
	NSMutableArray *slots = [NSMutableArray array];
	for (NSUInteger i = 0; i < chatIds.count; i++)
		[slots addObject:[NSNull null]];

	__block NSUInteger left = chatIds.count;
	for (NSUInteger i = 0; i < chatIds.count; i++){
		NSUInteger index = i;
		[self request:@{ @"@type" : @"getChat", @"chat_id" : chatIds[i] }
		   completion:^(NSDictionary *chat){
			if ([chat[@"@type"] isEqualToString:@"chat"]){
				[slots replaceObjectAtIndex:index withObject:@{
					@"id"    : chat[@"id"] ?: @(0),
					@"title" : TGString(chat[@"title"]),
				}];
			}
			if (--left > 0)
				return;
			NSMutableArray *out = [NSMutableArray array];
			for (id slot in slots){
				if ([slot isKindOfClass:NSDictionary.class])
					[out addObject:slot];
			}
			if (completion)
				completion(out);
		}];
	}
}

- (void)tg_ok:(NSDictionary *)request completion:(void (^)(BOOL))completion {
	[self request:request completion:^(NSDictionary *result){
		if (completion)
			completion(!TGIsError(result));
	}];
}

- (void)tg_userFull:(int64_t)userId completion:(void (^)(NSDictionary *))completion {
	[self request:@{ @"@type" : @"getUserFullInfo", @"user_id" : @(userId) }
	   completion:^(NSDictionary *full){
		if (!completion)
			return;
		completion(TGIsError(full) ? nil : full);
	}];
}

- (NSArray *)tg_importedContacts:(NSArray *)contacts {
	NSMutableArray *out = [NSMutableArray array];
	for (id entry in TGArray(contacts) ?: @[]){
		NSDictionary *c = TGDict(entry);
		if (!c)
			continue;
		NSString *phone = TGString(c[@"phone"]);
		if (!phone.length)
			phone = TGString(c[@"phone_number"]);
		if (!phone.length)
			continue;
		[out addObject:@{
			@"@type"        : @"importedContact",
			@"phone_number" : phone,
			@"first_name"   : TGString(c[@"first_name"]),
			@"last_name"    : TGString(c[@"last_name"]),
		}];
	}
	return out;
}

- (void)tg_import:(NSString *)method contacts:(NSArray *)contacts
	   completion:(void (^)(NSArray *))completion {
	NSArray *payload = [self tg_importedContacts:contacts];
	if (!payload.count){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{ @"@type" : method, @"contacts" : payload }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *ids = TGIsError(result) ? nil : TGArray(result[@"user_ids"]);
		completion(ids ?: @[]);
	}];
}

- (NSDictionary *)tg_inputPhotoAtPath:(NSString *)path {
	return @{
		@"@type" : @"inputChatPhotoStatic",
		@"photo" : @{ @"@type" : @"inputFileLocal", @"path" : path ?: @"" },
	};
}

#pragma mark - contact list

- (void)searchContacts:(NSString *)query limit:(NSInteger)limit
			completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type" : @"searchContacts",
		@"query" : query ?: @"",
		@"limit" : @(limit > 0 ? limit : 50),
	} completion:^(NSDictionary *result){
		if (TGIsError(result)){
			if (completion) completion(@[]);
			return;
		}
		[weakSelf tg_fetchUsers:result[@"user_ids"] completion:completion];
	}];
}

- (void)addContactWithUserId:(int64_t)userId
					   phone:(NSString *)phone
				   firstName:(NSString *)firstName
					lastName:(NSString *)lastName
			sharePhoneNumber:(BOOL)share
				  completion:(void (^)(BOOL))completion {
	[self tg_ok:@{
		@"@type"   : @"addContact",
		@"user_id" : @(userId),
		@"contact" : @{
			@"@type"        : @"importedContact",
			@"phone_number" : phone ?: @"",
			@"first_name"   : firstName ?: @"",
			@"last_name"    : lastName ?: @"",
		},
		@"share_phone_number" : @(share),
	} completion:^(BOOL ok){
		if (ok)
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGContactsDidChangeNotification object:nil];
		if (completion) completion(ok);
	}];
}

- (void)importContactWithPhone:(NSString *)phone
					 firstName:(NSString *)firstName
					  lastName:(NSString *)lastName
					completion:(void (^)(int64_t))completion {
	if (!phone.length){
		if (completion) completion(0);
		return;
	}
	[self importContacts:@[@{
		@"phone"      : phone,
		@"first_name" : firstName ?: @"",
		@"last_name"  : lastName ?: @"",
	}] completion:^(NSArray *userIds){
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGContactsDidChangeNotification object:nil];
		if (!completion)
			return;
		id first = userIds.count ? [userIds objectAtIndex:0] : nil;
		completion([first respondsToSelector:@selector(longLongValue)]
				? [first longLongValue] : 0);
	}];
}

- (void)removeContacts:(NSArray *)userIds completion:(void (^)(BOOL))completion {
	NSArray *ids = TGArray(userIds);
	if (!ids.count){
		if (completion) completion(YES);
		return;
	}
	[self tg_ok:@{ @"@type" : @"removeContacts", @"user_ids" : ids }
	 completion:^(BOOL ok){
		if (ok)
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGContactsDidChangeNotification object:nil];
		if (completion) completion(ok);
	}];
}

- (void)sharePhoneNumberWithUser:(int64_t)userId {
	[self send:@{ @"@type" : @"sharePhoneNumber", @"user_id" : @(userId) }];
}

- (void)contactFlagsForUser:(int64_t)userId
				 completion:(void (^)(NSDictionary *))completion {
	[self request:@{ @"@type" : @"getUser", @"user_id" : @(userId) }
	   completion:^(NSDictionary *u){
		if (!completion)
			return;
		if (![u[@"@type"] isEqualToString:@"user"]){
			completion(nil);
			return;
		}
		completion(@{
			@"isContact"       : @([u[@"is_contact"] boolValue]),
			@"isMutualContact" : @([u[@"is_mutual_contact"] boolValue]),
			@"isCloseFriend"   : @([u[@"is_close_friend"] boolValue]),
			@"isPremium"       : @([u[@"is_premium"] boolValue]),
			@"isSupport"       : @([u[@"is_support"] boolValue]),
		});
	}];
}

#pragma mark - address book

- (void)syncImportedContacts:(NSArray *)contacts
				  completion:(void (^)(NSArray *))completion {
	[self tg_import:@"changeImportedContacts" contacts:contacts completion:completion];
}

- (void)importContacts:(NSArray *)contacts completion:(void (^)(NSArray *))completion {
	[self tg_import:@"importContacts" contacts:contacts completion:completion];
}

- (void)importedContactCountWithCompletion:(void (^)(NSInteger))completion {
	[self request:@{ @"@type" : @"getImportedContactCount" }
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? 0 : [result[@"count"] integerValue]);
	}];
}

- (void)clearImportedContactsWithCompletion:(void (^)(BOOL))completion {
	[self tg_ok:@{ @"@type" : @"clearImportedContacts" } completion:completion];
}

#pragma mark - finding people

- (void)userForToken:(NSString *)token completion:(void (^)(NSDictionary *))completion {
	if (!token.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{ @"@type" : @"searchUserByToken", @"token" : token }
	   completion:^(NSDictionary *u){
		if (completion)
			completion(TGFlatUser(u));
	}];
}

- (void)myContactLinkWithCompletion:(void (^)(NSString *, NSInteger))completion {
	[self request:@{ @"@type" : @"getUserLink" } completion:^(NSDictionary *link){
		if (!completion)
			return;
		if (TGIsError(link)){
			completion(nil, 0);
			return;
		}
		NSString *url = TGString(link[@"url"]);
		completion(url.length ? url : nil, [link[@"expires_in"] integerValue]);
	}];
}

#pragma mark - close friends

- (void)contactCloseFriendsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{ @"@type" : @"getCloseFriends" } completion:^(NSDictionary *result){
		if (TGIsError(result)){
			if (completion) completion(@[]);
			return;
		}
		[weakSelf tg_fetchUsers:result[@"user_ids"] completion:completion];
	}];
}

- (void)setCloseFriends:(NSArray *)userIds completion:(void (^)(BOOL))completion {
	[self tg_ok:@{
		@"@type"    : @"setCloseFriends",
		@"user_ids" : TGArray(userIds) ?: @[],
	} completion:completion];
}

- (void)setUser:(int64_t)userId closeFriend:(BOOL)closeFriend
	 completion:(void (^)(BOOL))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{ @"@type" : @"getCloseFriends" } completion:^(NSDictionary *result){
		if (TGIsError(result)){
			if (completion) completion(NO);
			return;
		}
		NSMutableArray *ids = [NSMutableArray array];
		for (id uid in TGArray(result[@"user_ids"]) ?: @[]){
			if ([uid isKindOfClass:NSNumber.class] && [uid longLongValue] != userId)
				[ids addObject:uid];
		}
		if (closeFriend)
			[ids addObject:@(userId)];
		[weakSelf setCloseFriends:ids completion:completion];
	}];
}

#pragma mark - own usernames

- (void)myUsernamesWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{ @"@type" : @"getMe" } completion:^(NSDictionary *u){
		if (!completion)
			return;
		if (![u[@"@type"] isEqualToString:@"user"]){
			completion(nil);
			return;
		}
		NSDictionary *names = TGDict(u[@"usernames"]);
		completion(@{
			@"active"   : TGArray(names[@"active_usernames"]) ?: @[],
			@"disabled" : TGArray(names[@"disabled_usernames"]) ?: @[],
			@"editable" : TGString(names[@"editable_username"]),
		});
	}];
}

- (void)toggleUsername:(NSString *)username active:(BOOL)active
			completion:(void (^)(BOOL))completion {
	if (!username.length){
		if (completion) completion(NO);
		return;
	}
	[self tg_ok:@{
		@"@type"     : @"toggleUsernameIsActive",
		@"username"  : username,
		@"is_active" : @(active),
	} completion:completion];
}

- (void)checkUsernameAvailable:(NSString *)username
					completion:(void (^)(NSString *))completion {
	if (!username.length){
		if (completion) completion(@"invalid");
		return;
	}
	[self request:@{
		@"@type"    : @"checkChatUsername",
		@"chat_id"  : @([self savedMessagesChatId]),
		@"username" : username,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = TGString(result[@"@type"]);
		if ([type isEqualToString:@"checkChatUsernameResultOk"])
			completion(@"ok");
		else if ([type isEqualToString:@"checkChatUsernameResultUsernameInvalid"])
			completion(@"invalid");
		else if ([type isEqualToString:@"checkChatUsernameResultUsernameOccupied"])
			completion(@"occupied");
		else if ([type isEqualToString:@"checkChatUsernameResultUsernamePurchasable"])
			completion(@"purchasable");
		else if ([type isEqualToString:@"checkChatUsernameResultPublicChatsTooMany"])
			completion(@"too_many");
		else if ([type isEqualToString:@"checkChatUsernameResultPublicGroupsUnavailable"])
			completion(@"unavailable");
		else
			completion(@"error");
	}];
}

#pragma mark - profile photos

- (void)setMyProfilePhotoAtPath:(NSString *)path isPublic:(BOOL)isPublic
					 completion:(void (^)(BOOL))completion {
	if (!path.length){
		if (completion) completion(NO);
		return;
	}
	[self tg_ok:@{
		@"@type"     : @"setProfilePhoto",
		@"photo"     : [self tg_inputPhotoAtPath:path],
		@"is_public" : @(isPublic),
	} completion:completion];
}

- (void)deleteMyProfilePhoto:(long long)photoId completion:(void (^)(BOOL))completion {
	[self tg_ok:@{
		@"@type"            : @"deleteProfilePhoto",
		@"profile_photo_id" : @(photoId),
	} completion:completion];
}

- (void)profilePhotosForUser:(int64_t)userId
					  offset:(NSInteger)offset
					   limit:(NSInteger)limit
				  completion:(void (^)(NSArray *, NSInteger))completion {
	[self request:@{
		@"@type"   : @"getUserProfilePhotos",
		@"user_id" : @(userId),
		@"offset"  : @(offset > 0 ? offset : 0),
		@"limit"   : @(limit > 0 ? limit : 20),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(@[], 0);
			return;
		}
		NSMutableArray *photos = [NSMutableArray array];
		for (id entry in TGArray(result[@"photos"]) ?: @[]){
			NSDictionary *photo = TGDict(entry);
			NSArray *sizes = TGArray(photo[@"sizes"]);
			if (!sizes.count)
				continue;
			NSNumber *small = TGFileId(TGDict(sizes[0])[@"photo"]);
			NSNumber *big = TGFileId(TGDict(sizes.lastObject)[@"photo"]);
			if (!big)
				continue;
			[photos addObject:@{
				@"photoId"     : @(TGInt64(photo[@"id"])),
				@"date"        : photo[@"added_date"] ?: @(0),
				@"fileId"      : big,
				@"smallFileId" : small ?: big,
			}];
		}
		completion(photos, [result[@"total_count"] integerValue]);
	}];
}

- (void)setPersonalPhotoAtPath:(NSString *)path
					   forUser:(int64_t)userId
					   suggest:(BOOL)suggest
					completion:(void (^)(BOOL))completion {
	if (!path.length){
		if (completion) completion(NO);
		return;
	}
	[self tg_ok:@{
		@"@type"   : suggest ? @"suggestUserProfilePhoto" : @"setUserPersonalProfilePhoto",
		@"user_id" : @(userId),
		@"photo"   : [self tg_inputPhotoAtPath:path],
	} completion:completion];
}

- (void)removePersonalPhotoForUser:(int64_t)userId completion:(void (^)(BOOL))completion {
	[self tg_ok:@{
		@"@type"   : @"setUserPersonalProfilePhoto",
		@"user_id" : @(userId),
		@"photo"   : [NSNull null],
	} completion:completion];
}

#pragma mark - birthdays

- (void)setMyBirthdateDay:(NSInteger)day
					month:(NSInteger)month
					 year:(NSInteger)year
			   completion:(void (^)(BOOL))completion {
	NSDictionary *request = day > 0 && month > 0
		? @{ @"@type" : @"setBirthdate",
			 @"birthdate" : @{ @"@type" : @"birthdate",
							   @"day" : @(day), @"month" : @(month), @"year" : @(year) } }
		: @{ @"@type" : @"setBirthdate", @"birthdate" : [NSNull null] };
	[self tg_ok:request completion:completion];
}

- (void)suggestBirthdateToUser:(int64_t)userId
						   day:(NSInteger)day
						 month:(NSInteger)month
						  year:(NSInteger)year
					completion:(void (^)(BOOL))completion {
	if (day < 1 || month < 1){
		if (completion) completion(NO);
		return;
	}
	[self tg_ok:@{
		@"@type"     : @"suggestUserBirthdate",
		@"user_id"   : @(userId),
		@"birthdate" : @{ @"@type" : @"birthdate",
						  @"day" : @(day), @"month" : @(month), @"year" : @(year) },
	} completion:completion];
}

- (void)birthdateForUser:(int64_t)userId
			  completion:(void (^)(NSDictionary *))completion {
	[self tg_userFull:userId completion:^(NSDictionary *full){
		if (completion)
			completion(TGBirthdateInfo(full[@"birthdate"]));
	}];
}

- (void)hideContactCloseBirthdays {
	[self send:@{ @"@type" : @"hideContactCloseBirthdays" }];
}

#pragma mark - profile extras

- (void)noteForUser:(int64_t)userId completion:(void (^)(NSString *))completion {
	[self tg_userFull:userId completion:^(NSDictionary *full){
		if (completion)
			completion(TGString(TGDict(full[@"note"])[@"text"]));
	}];
}

- (void)setNote:(NSString *)note forUser:(int64_t)userId
	 completion:(void (^)(BOOL))completion {
	[self tg_ok:@{
		@"@type"   : @"setUserNote",
		@"user_id" : @(userId),
		@"note"    : @{ @"@type" : @"formattedText",
						@"text" : note ?: @"", @"entities" : @[] },
	} completion:completion];
}

- (void)groupsInCommonWithUser:(int64_t)userId
					completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"          : @"getGroupsInCommon",
		@"user_id"        : @(userId),
		@"offset_chat_id" : @(0),
		@"limit"          : @(100),
	} completion:^(NSDictionary *result){
		if (TGIsError(result)){
			if (completion) completion(@[]);
			return;
		}
		[weakSelf tg_fetchChats:result[@"chat_ids"] completion:completion];
	}];
}

- (void)suitablePersonalChatsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{ @"@type" : @"getSuitablePersonalChats" }
	   completion:^(NSDictionary *result){
		if (TGIsError(result)){
			if (completion) completion(@[]);
			return;
		}
		[weakSelf tg_fetchChats:result[@"chat_ids"] completion:completion];
	}];
}

- (void)personalChatForUser:(int64_t)userId completion:(void (^)(int64_t))completion {
	[self tg_userFull:userId completion:^(NSDictionary *full){
		if (completion)
			completion([full[@"personal_chat_id"] longLongValue]);
	}];
}

- (void)setMainProfileTab:(NSString *)tab completion:(void (^)(BOOL))completion {
	NSArray *known = @[@"posts", @"gifts", @"media", @"files",
					   @"links", @"music", @"voice", @"gifs"];
	NSString *name = [TGString(tab) lowercaseString];
	if (![known containsObject:name]){
		if (completion) completion(NO);
		return;
	}
	NSString *type = [NSString stringWithFormat:@"profileTab%@%@",
					  [[name substringToIndex:1] uppercaseString],
					  [name substringFromIndex:1]];
	[self tg_ok:@{
		@"@type"            : @"setMainProfileTab",
		@"main_profile_tab" : @{ @"@type" : type },
	} completion:completion];
}

- (void)mainProfileTabForUser:(int64_t)userId completion:(void (^)(NSString *))completion {
	[self tg_userFull:userId completion:^(NSDictionary *full){
		if (completion)
			completion(TGProfileTabName(full[@"main_profile_tab"]));
	}];
}

#pragma mark - support

- (void)supportContactWithCompletion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{ @"@type" : @"getSupportUser" } completion:^(NSDictionary *u){
		if (![u[@"@type"] isEqualToString:@"user"]){
			if (completion) completion(nil);
			return;
		}
		int64_t userId = [u[@"id"] longLongValue];
		[weakSelf request:@{ @"@type" : @"getSupportName" }
			   completion:^(NSDictionary *text){
			NSString *name = TGIsError(text) ? @"" : TGString(text[@"text"]);
			[weakSelf request:@{
				@"@type"   : @"createPrivateChat",
				@"user_id" : @(userId),
				@"force"   : @YES,
			} completion:^(NSDictionary *chat){
				if (!completion)
					return;
				completion(@{
					@"userId" : @(userId),
					@"chatId" : @([chat[@"id"] longLongValue]),
					@"name"   : name,
				});
			}];
		}];
	}];
}

@end

// vim:ft=objc

#import "TGUserModel.h"

@interface TGUserModel ()
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, copy) NSString *firstName;
@property (nonatomic, copy) NSString *lastName;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *phoneNumber;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, assign) TGUserStatusKind statusKind;
@property (nonatomic, assign) BOOL isOnline;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, assign) int64_t wasOnlineDate;
@property (nonatomic, assign) int64_t statusRank;
@property (nonatomic, copy) NSNumber *photoFileId;
@property (nonatomic, copy) NSNumber *bigPhotoFileId;
@property (nonatomic, copy) NSString *photoUniqueId;
@property (nonatomic, assign) BOOL isContact;
@property (nonatomic, assign) BOOL isMutualContact;
@property (nonatomic, assign) BOOL isCloseFriend;
@property (nonatomic, assign) BOOL isPremium;
@property (nonatomic, assign) BOOL isVerified;
@property (nonatomic, assign) BOOL isScam;
@property (nonatomic, assign) BOOL isFake;
@property (nonatomic, assign) BOOL isSupport;
@property (nonatomic, assign) BOOL isBot;
@property (nonatomic, assign) BOOL isDeleted;
@property (nonatomic, assign) int64_t emojiStatusCustomEmojiId;
@property (nonatomic, assign) int64_t emojiStatusExpirationDate;
@property (nonatomic, assign) NSInteger accentColorId;
@property (nonatomic, assign) int64_t backgroundCustomEmojiId;
@property (nonatomic, assign) NSInteger profileAccentColorId;
@property (nonatomic, assign) NSInteger birthdayDay;
@property (nonatomic, assign) NSInteger birthdayMonth;
@property (nonatomic, assign) NSInteger birthdayYear;
- (void)tg_applyStatus:(NSDictionary *)d;
@end

static NSDictionary *TGUMDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *TGUMArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSString *TGUMString(id value) {
	if (![value isKindOfClass:NSString.class])
		return nil;
	NSString *s = [value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return s.length ? s : nil;
}

static int64_t TGUMInt64(id value) {
	if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class])
		return [value longLongValue];
	return 0;
}

static NSInteger TGUMInteger(id value, NSInteger fallback) {
	if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class])
		return (NSInteger)[value longLongValue];
	return fallback;
}

static BOOL TGUMBool(id value) {
	if ([value isKindOfClass:NSNumber.class])
		return [value boolValue];
	if ([value isKindOfClass:NSString.class])
		return [value isEqualToString:@"true"] || [value isEqualToString:@"1"];
	return NO;
}

static NSNumber *TGUMFileId(id file) {
	NSDictionary *f = TGUMDict(file);
	id fid = f[@"id"];
	if ([fid isKindOfClass:NSNumber.class])
		return fid;
	if ([fid isKindOfClass:NSString.class])
		return [NSNumber numberWithLongLong:[fid longLongValue]];
	return nil;
}

static NSString *TGUMUsername(NSDictionary *dict) {
	NSDictionary *names = TGUMDict(dict[@"usernames"]);
	NSArray *active = TGUMArray(names[@"active_usernames"]);
	for (id name in active ?: @[]){
		NSString *s = TGUMString(name);
		if (s)
			return s;
	}
	NSString *editable = TGUMString(names[@"editable_username"]);
	if (editable)
		return editable;
	return TGUMString(dict[@"username"]);
}

@implementation TGUserModel

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	return [self fromDictionary:dict fullInfo:nil];
}

+ (instancetype)fromDictionary:(NSDictionary *)dict fullInfo:(NSDictionary *)fullInfo {
	NSDictionary *d = TGUMDict(dict);
	if (!d)
		return nil;

	NSString *type = TGUMString(d[@"@type"]);
	if (type && [type isEqualToString:@"error"])
		return nil;
	if (type && ![type isEqualToString:@"user"])
		return nil;

	int64_t userId = TGUMInt64(d[@"id"]);
	if (userId == 0)
		userId = TGUMInt64(d[@"user_id"]);
	if (userId == 0)
		return nil;

	TGUserModel *m = [[TGUserModel alloc] init];
	m.userId = userId;
	m.firstName = TGUMString(d[@"first_name"]) ?: TGUMString(d[@"firstName"]);
	m.lastName = TGUMString(d[@"last_name"]) ?: TGUMString(d[@"lastName"]);
	m.phoneNumber = TGUMString(d[@"phone_number"]) ?: TGUMString(d[@"phone"]);
	m.username = TGUMUsername(d);

	if (m.firstName && m.lastName)
		m.displayName = [NSString stringWithFormat:@"%@ %@", m.firstName, m.lastName];
	else if (m.firstName)
		m.displayName = m.firstName;
	else if (m.lastName)
		m.displayName = m.lastName;
	else
		m.displayName = m.username;

	NSDictionary *photo = TGUMDict(d[@"profile_photo"]);
	NSDictionary *small = TGUMDict(photo[@"small"]);
	m.photoFileId = TGUMFileId(small);
	m.bigPhotoFileId = TGUMFileId(TGUMDict(photo[@"big"]));
	m.photoUniqueId = TGUMString(TGUMDict(small[@"remote"])[@"unique_id"]);
	if (!m.photoFileId){
		id flat = d[@"photoFileId"];
		if ([flat isKindOfClass:NSNumber.class])
			m.photoFileId = flat;
	}
	if (!m.bigPhotoFileId){
		id flat = d[@"bigFileId"];
		if ([flat isKindOfClass:NSNumber.class] && [flat longLongValue] != 0)
			m.bigPhotoFileId = flat;
	}
	if (!m.photoUniqueId)
		m.photoUniqueId = TGUMString(d[@"photoUniqueId"]);

	m.isContact = TGUMBool(d[@"is_contact"]) || TGUMBool(d[@"isContact"]);
	m.isMutualContact = TGUMBool(d[@"is_mutual_contact"]) || TGUMBool(d[@"isMutualContact"]);
	m.isCloseFriend = TGUMBool(d[@"is_close_friend"]) || TGUMBool(d[@"isCloseFriend"]);
	m.isPremium = TGUMBool(d[@"is_premium"]) || TGUMBool(d[@"isPremium"]);
	m.isSupport = TGUMBool(d[@"is_support"]);

	NSDictionary *verification = TGUMDict(d[@"verification_status"]);
	m.isVerified = verification
			? TGUMBool(verification[@"is_verified"])
			: (TGUMBool(d[@"is_verified"]) || TGUMBool(d[@"isVerified"]));
	m.isScam = verification ? TGUMBool(verification[@"is_scam"]) : TGUMBool(d[@"is_scam"]);
	m.isFake = verification ? TGUMBool(verification[@"is_fake"]) : TGUMBool(d[@"is_fake"]);

	NSString *userType = TGUMString(TGUMDict(d[@"type"])[@"@type"]);
	m.isBot = [userType isEqualToString:@"userTypeBot"];
	m.isDeleted = [userType isEqualToString:@"userTypeDeleted"];

	NSDictionary *emojiStatus = TGUMDict(d[@"emoji_status"]);
	if (emojiStatus){
		NSDictionary *nested = TGUMDict(emojiStatus[@"type"]);
		m.emojiStatusCustomEmojiId = TGUMInt64(emojiStatus[@"custom_emoji_id"]);
		if (m.emojiStatusCustomEmojiId == 0)
			m.emojiStatusCustomEmojiId = TGUMInt64(nested[@"custom_emoji_id"]);
		m.emojiStatusExpirationDate = TGUMInt64(emojiStatus[@"expiration_date"]);
	}

	m.accentColorId = TGUMInteger(d[@"accent_color_id"], -1);
	m.profileAccentColorId = TGUMInteger(d[@"profile_accent_color_id"], -1);
	m.backgroundCustomEmojiId = TGUMInt64(d[@"background_custom_emoji_id"]);

	[m tg_applyStatus:d];

	NSDictionary *full = TGUMDict(fullInfo);
	NSDictionary *birthdate = TGUMDict(full[@"birthdate"]) ?: TGUMDict(d[@"birthdate"]);
	NSInteger day = TGUMInteger(birthdate[@"day"], 0);
	NSInteger month = TGUMInteger(birthdate[@"month"], 0);
	if (day < 1 || day > 31 || month < 1 || month > 12){
		day = 0;
		month = 0;
	}
	m.birthdayDay = day;
	m.birthdayMonth = month;
	m.birthdayYear = (day && month) ? TGUMInteger(birthdate[@"year"], 0) : 0;

	return m;
}

- (void)tg_applyStatus:(NSDictionary *)d {
	NSDictionary *status = TGUMDict(d[@"status"]);
	NSString *kind = TGUMString(status[@"@type"]);
	NSString *carried = TGUMString(d[@"statusText"]);

	if (!kind){
		self.statusKind = TGUserStatusUnknown;
		self.isOnline = TGUMBool(d[@"isOnline"]);
		self.statusText = carried;
		self.statusRank = TGUMInt64(d[@"statusRank"]);
		if (self.isOnline){
			self.statusKind = TGUserStatusOnline;
			if (!self.statusText)
				self.statusText = @"online";
			if (self.statusRank == 0)
				self.statusRank = 4000000000LL;
		}
		return;
	}

	if ([kind isEqualToString:@"userStatusOnline"]){
		self.statusKind = TGUserStatusOnline;
		self.isOnline = YES;
		self.statusText = @"online";
		self.statusRank = 4000000000LL;
	} else if ([kind isEqualToString:@"userStatusOffline"]){
		self.statusKind = TGUserStatusOffline;
		self.wasOnlineDate = TGUMInt64(status[@"was_online"]);
		self.statusText = carried;
		self.statusRank = self.wasOnlineDate;
	} else if ([kind isEqualToString:@"userStatusRecently"]){
		self.statusKind = TGUserStatusRecently;
		self.statusText = @"last seen recently";
		self.statusRank = 3;
	} else if ([kind isEqualToString:@"userStatusLastWeek"]){
		self.statusKind = TGUserStatusLastWeek;
		self.statusText = @"last seen within a week";
		self.statusRank = 2;
	} else if ([kind isEqualToString:@"userStatusLastMonth"]){
		self.statusKind = TGUserStatusLastMonth;
		self.statusText = @"last seen within a month";
		self.statusRank = 1;
	} else if ([kind isEqualToString:@"userStatusEmpty"]){
		self.statusKind = TGUserStatusEmpty;
		self.statusText = @"last seen a long time ago";
		self.statusRank = 0;
	} else {
		self.statusKind = TGUserStatusUnknown;
		self.statusText = carried ?: @"last seen a long time ago";
		self.statusRank = 0;
	}
}

- (BOOL)hasBirthday {
	return self.birthdayDay > 0 && self.birthdayMonth > 0;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	NSArray *list = TGUMArray(dicts);
	if (!list.count)
		return [NSArray array];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:list.count];
	for (id entry in list){
		TGUserModel *m = [self fromDictionary:entry];
		if (m)
			[out addObject:m];
	}
	return out;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"<TGUserModel %lld %@%@>",
			self.userId, self.displayName ?: @"(no name)",
			self.isOnline ? @" online" : @""];
}

@end

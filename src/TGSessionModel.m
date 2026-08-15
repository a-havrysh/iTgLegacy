#import "TGSessionModel.h"

@interface TGSessionModel ()
@property (nonatomic, assign) int64_t sessionId;
@property (nonatomic, copy) NSString *applicationName;
@property (nonatomic, copy) NSString *applicationVersion;
@property (nonatomic, copy) NSString *deviceModel;
@property (nonatomic, copy) NSString *deviceType;
@property (nonatomic, copy) NSString *platform;
@property (nonatomic, copy) NSString *systemVersion;
@property (nonatomic, copy) NSString *ipAddress;
@property (nonatomic, copy) NSString *location;
@property (nonatomic, assign) int64_t loginDate;
@property (nonatomic, assign) int64_t lastActiveDate;
@property (nonatomic, assign) int64_t apiId;
@property (nonatomic, assign) BOOL isCurrent;
@property (nonatomic, assign) BOOL isUnconfirmed;
@property (nonatomic, assign) BOOL isOfficialApplication;
@property (nonatomic, assign) BOOL isPasswordPending;
@property (nonatomic, assign) BOOL canAcceptCalls;
@property (nonatomic, assign) BOOL canAcceptSecretChats;
@end

static NSString *TGSessionModelTrimmedString(id value) {
	if (![value isKindOfClass:[NSString class]])
		return nil;
	NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return trimmed.length ? trimmed : nil;
}

static NSString *TGSessionModelString(NSDictionary *dict, NSString *primary, NSString *fallback) {
	NSString *value = TGSessionModelTrimmedString([dict objectForKey:primary]);
	if (value)
		return value;
	if (fallback)
		return TGSessionModelTrimmedString([dict objectForKey:fallback]);
	return nil;
}

static int64_t TGSessionModelInt64(NSDictionary *dict, NSString *primary, NSString *fallback) {
	id value = [dict objectForKey:primary];
	if (![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSString class]]){
		value = fallback ? [dict objectForKey:fallback] : nil;
		if (![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSString class]])
			return 0;
	}
	return [value longLongValue];
}

static BOOL TGSessionModelBool(NSDictionary *dict, NSString *primary, NSString *fallback) {
	id value = [dict objectForKey:primary];
	if (![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSString class]]){
		value = fallback ? [dict objectForKey:fallback] : nil;
		if (![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSString class]])
			return NO;
	}
	return [value boolValue];
}

static NSString *TGSessionModelDeviceType(NSDictionary *dict) {
	id raw = [dict objectForKey:@"device_type"];
	if ([raw isKindOfClass:[NSDictionary class]]){
		NSString *name = TGSessionModelTrimmedString([(NSDictionary *)raw objectForKey:@"@type"]);
		if ([name hasPrefix:@"sessionDeviceType"]){
			NSString *stripped = [name substringFromIndex:[@"sessionDeviceType" length]];
			return stripped.length ? stripped : nil;
		}
		return name;
	}
	NSString *flat = TGSessionModelTrimmedString([dict objectForKey:@"deviceType"]);
	if ([flat isEqualToString:@"Unknown"])
		return nil;
	return flat;
}

@implementation TGSessionModel

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;

	int64_t sessionId = TGSessionModelInt64(dict, @"id", @"session_id");
	if (sessionId == 0)
		return nil;

	TGSessionModel *model = [[TGSessionModel alloc] init];
	model.sessionId = sessionId;
	model.applicationName = TGSessionModelString(dict, @"application_name", @"appName");
	if (!model.applicationName)
		model.applicationName = TGSessionModelString(dict, @"name", nil);
	model.applicationVersion = TGSessionModelString(dict, @"application_version", @"appVersion");
	model.deviceModel = TGSessionModelString(dict, @"device_model", @"deviceModel");
	model.deviceType = TGSessionModelDeviceType(dict);
	model.platform = TGSessionModelString(dict, @"platform", nil);
	model.systemVersion = TGSessionModelString(dict, @"system_version", @"systemVersion");
	model.ipAddress = TGSessionModelString(dict, @"ip_address", @"ipAddress");
	if (!model.ipAddress)
		model.ipAddress = TGSessionModelString(dict, @"ip", nil);
	model.location = TGSessionModelString(dict, @"location", nil);
	model.loginDate = TGSessionModelInt64(dict, @"log_in_date", @"loginDate");
	model.lastActiveDate = TGSessionModelInt64(dict, @"last_active_date", @"lastActiveDate");
	if (model.lastActiveDate == 0)
		model.lastActiveDate = TGSessionModelInt64(dict, @"lastActive", nil);
	model.apiId = TGSessionModelInt64(dict, @"api_id", @"apiId");
	model.isCurrent = TGSessionModelBool(dict, @"is_current", @"isCurrent");
	model.isUnconfirmed = TGSessionModelBool(dict, @"is_unconfirmed", @"isUnconfirmed");
	model.isOfficialApplication = TGSessionModelBool(dict, @"is_official_application",
			@"isOfficialApplication");
	if (!model.isOfficialApplication)
		model.isOfficialApplication = TGSessionModelBool(dict, @"isOfficial", nil);
	model.isPasswordPending = TGSessionModelBool(dict, @"is_password_pending", @"isPasswordPending");
	model.canAcceptCalls = TGSessionModelBool(dict, @"can_accept_calls", @"canAcceptCalls");
	model.canAcceptSecretChats = TGSessionModelBool(dict, @"can_accept_secret_chats",
			@"canAcceptSecretChats");

	if (model.platform && model.systemVersion
			&& [model.platform rangeOfString:model.systemVersion].location != NSNotFound)
		model.systemVersion = nil;

	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	if (![dicts isKindOfClass:[NSArray class]])
		return [NSArray array];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:dicts.count];
	for (id entry in dicts){
		TGSessionModel *model = [self fromDictionary:entry];
		if (model)
			[out addObject:model];
	}
	return out;
}

- (NSString *)systemDescription {
	if (self.platform && self.systemVersion)
		return [NSString stringWithFormat:@"%@ %@", self.platform, self.systemVersion];
	return self.platform ? self.platform : self.systemVersion;
}

- (NSString *)applicationDescription {
	if (self.applicationName && self.applicationVersion)
		return [NSString stringWithFormat:@"%@ %@", self.applicationName, self.applicationVersion];
	return self.applicationName;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"<TGSessionModel %lld %@ %@%@>",
			self.sessionId,
			self.applicationDescription ? self.applicationDescription : @"?",
			self.deviceModel ? self.deviceModel : @"?",
			self.isCurrent ? @" current" : @""];
}

@end

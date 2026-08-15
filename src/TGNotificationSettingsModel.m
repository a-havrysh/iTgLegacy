#import "TGNotificationSettingsModel.h"

const int64_t TGNotificationSettingsMuteForever = 365 * 24 * 3600;

@interface TGNotificationSettingsModel ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL scopeSettings;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) int64_t muteFor;
@property (nonatomic, assign) BOOL useDefaultMuteFor;
@property (nonatomic, assign) BOOL showPreview;
@property (nonatomic, assign) BOOL useDefaultShowPreview;
@property (nonatomic, assign) int64_t soundId;
@property (nonatomic, assign) BOOL useDefaultSound;
@property (nonatomic, assign) BOOL disablePinnedMessageNotifications;
@property (nonatomic, assign) BOOL useDefaultDisablePinnedMessageNotifications;
@property (nonatomic, assign) BOOL disableMentionNotifications;
@property (nonatomic, assign) BOOL useDefaultDisableMentionNotifications;
@property (nonatomic, assign) BOOL defaultDisableNotification;
@end

static NSString *TGNotificationSettingsString(id value) {
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value length] ? value : nil;
	return nil;
}

static int64_t TGNotificationSettingsInt64(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value longLongValue];
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value longLongValue];
	return 0;
}

static BOOL TGNotificationSettingsBool(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value boolValue];
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value boolValue];
	return NO;
}

static BOOL TGNotificationSettingsHasKey(NSDictionary *dict, NSString *key) {
	return [dict objectForKey:key] != nil;
}

@implementation TGNotificationSettingsModel

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;

	BOOL row = TGNotificationSettingsHasKey(dict, @"id");
	BOOL chat = TGNotificationSettingsHasKey(dict, @"useDefaultMuteFor");
	BOOL known = row || chat ||
			TGNotificationSettingsHasKey(dict, @"muted") ||
			TGNotificationSettingsHasKey(dict, @"muteFor") ||
			TGNotificationSettingsHasKey(dict, @"showPreview") ||
			TGNotificationSettingsHasKey(dict, @"soundId");
	if (!known)
		return nil;

	TGNotificationSettingsModel *model = [[TGNotificationSettingsModel alloc] init];
	model.chatId = TGNotificationSettingsInt64([dict objectForKey:@"id"]);
	model.title = TGNotificationSettingsString([dict objectForKey:@"title"]);
	model.scopeSettings = !row && !chat;

	int64_t muteFor = TGNotificationSettingsInt64([dict objectForKey:@"muteFor"]);
	if (muteFor < 0)
		muteFor = 0;
	model.muteFor = muteFor;
	model.muted = TGNotificationSettingsHasKey(dict, @"muted")
			? TGNotificationSettingsBool([dict objectForKey:@"muted"])
			: (muteFor > 0);

	model.showPreview = TGNotificationSettingsBool([dict objectForKey:@"showPreview"]);
	model.soundId = TGNotificationSettingsInt64([dict objectForKey:@"soundId"]);
	model.disablePinnedMessageNotifications = TGNotificationSettingsBool(
			[dict objectForKey:@"disablePinnedMessageNotifications"]);
	model.disableMentionNotifications = TGNotificationSettingsBool(
			[dict objectForKey:@"disableMentionNotifications"]);
	model.defaultDisableNotification = TGNotificationSettingsBool(
			[dict objectForKey:@"defaultDisableNotification"]);

	if (chat){
		model.useDefaultMuteFor = TGNotificationSettingsBool(
				[dict objectForKey:@"useDefaultMuteFor"]);
		model.useDefaultShowPreview = TGNotificationSettingsBool(
				[dict objectForKey:@"useDefaultShowPreview"]);
		model.useDefaultSound = TGNotificationSettingsBool(
				[dict objectForKey:@"useDefaultSound"]);
		model.useDefaultDisablePinnedMessageNotifications = TGNotificationSettingsBool(
				[dict objectForKey:@"useDefaultDisablePinnedMessageNotifications"]);
		model.useDefaultDisableMentionNotifications = TGNotificationSettingsBool(
				[dict objectForKey:@"useDefaultDisableMentionNotifications"]);
	}

	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	if (![dicts isKindOfClass:[NSArray class]])
		return [NSArray array];

	NSMutableArray *models = [NSMutableArray arrayWithCapacity:dicts.count];
	for (id entry in dicts){
		TGNotificationSettingsModel *model = [self fromDictionary:entry];
		if (model)
			[models addObject:model];
	}
	return models;
}

- (BOOL)muteForever {
	return self.muteFor >= TGNotificationSettingsMuteForever;
}

- (BOOL)mutedTemporarily {
	return self.muteFor > 0 && self.muteFor < TGNotificationSettingsMuteForever;
}

- (BOOL)followsScopeDefaults {
	if (self.scopeSettings)
		return NO;
	return self.useDefaultMuteFor &&
			self.useDefaultShowPreview &&
			self.useDefaultSound &&
			self.useDefaultDisablePinnedMessageNotifications &&
			self.useDefaultDisableMentionNotifications;
}

- (BOOL)exception {
	return !self.scopeSettings && !self.followsScopeDefaults;
}

- (NSString *)description {
	return [NSString stringWithFormat:
			@"<TGNotificationSettingsModel %lld %@ muteFor=%lld preview=%d>",
			self.chatId, self.title ?: @"-", self.muteFor, self.showPreview];
}

@end

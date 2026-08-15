#import "TGMemberModel.h"

TGMemberStatus TGMemberStatusFromString(NSString *string) {
	if (![string isKindOfClass:[NSString class]])
		return TGMemberStatusLeft;
	if ([string isEqualToString:@"creator"])
		return TGMemberStatusCreator;
	if ([string isEqualToString:@"administrator"])
		return TGMemberStatusAdministrator;
	if ([string isEqualToString:@"member"])
		return TGMemberStatusMember;
	if ([string isEqualToString:@"restricted"])
		return TGMemberStatusRestricted;
	if ([string isEqualToString:@"banned"])
		return TGMemberStatusBanned;
	return TGMemberStatusLeft;
}

NSString *TGMemberStatusToString(TGMemberStatus status) {
	switch (status) {
		case TGMemberStatusCreator:       return @"creator";
		case TGMemberStatusAdministrator: return @"administrator";
		case TGMemberStatusMember:        return @"member";
		case TGMemberStatusRestricted:    return @"restricted";
		case TGMemberStatusBanned:        return @"banned";
		default:                          return @"left";
	}
}

static NSString *TGMemberCopyString(NSDictionary *dict, NSString *key) {
	id value = [dict objectForKey:key];
	if (![value isKindOfClass:[NSString class]])
		return nil;
	if ([(NSString *)value length] == 0)
		return nil;
	return [value copy];
}

static NSInteger TGMemberInteger(NSDictionary *dict, NSString *key) {
	id value = [dict objectForKey:key];
	if ([value isKindOfClass:[NSNumber class]])
		return [value integerValue];
	if ([value isKindOfClass:[NSString class]])
		return [value integerValue];
	return 0;
}

static int64_t TGMemberIdentifier(NSDictionary *dict, NSString *key) {
	id value = [dict objectForKey:key];
	if ([value isKindOfClass:[NSNumber class]])
		return [value longLongValue];
	if ([value isKindOfClass:[NSString class]])
		return [value longLongValue];
	return 0;
}

static BOOL TGMemberBool(NSDictionary *dict, NSString *key) {
	id value = [dict objectForKey:key];
	if ([value isKindOfClass:[NSNumber class]])
		return [value boolValue];
	if ([value isKindOfClass:[NSString class]])
		return [value boolValue];
	return NO;
}

@interface TGMemberRightsModel ()
- (id)initWithGrantedKeys:(NSSet *)keys;
@end

@implementation TGMemberRightsModel

- (id)initWithGrantedKeys:(NSSet *)keys {
	self = [super init];
	if (self)
		_grantedKeys = keys;
	return self;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	NSMutableSet *granted = [NSMutableSet set];
	if ([dict isKindOfClass:[NSDictionary class]]) {
		for (id key in dict) {
			if (![key isKindOfClass:[NSString class]])
				continue;
			id value = [dict objectForKey:key];
			BOOL on = NO;
			if ([value isKindOfClass:[NSNumber class]])
				on = [value boolValue];
			else if ([value isKindOfClass:[NSString class]])
				on = [value boolValue];
			if (on)
				[granted addObject:key];
		}
	}
	return [[self alloc] initWithGrantedKeys:[NSSet setWithSet:granted]];
}

- (BOOL)isGranted:(NSString *)key {
	if (![key isKindOfClass:[NSString class]])
		return NO;
	return [_grantedKeys containsObject:key];
}

- (BOOL)isEmpty {
	return [_grantedKeys count] == 0;
}

- (NSArray *)grantedKeys {
	return [_grantedKeys allObjects];
}

- (BOOL)canManageChat        { return [self isGranted:@"can_manage_chat"]; }
- (BOOL)canChangeInfo        { return [self isGranted:@"can_change_info"]; }
- (BOOL)canPostMessages      { return [self isGranted:@"can_post_messages"]; }
- (BOOL)canEditMessages      { return [self isGranted:@"can_edit_messages"]; }
- (BOOL)canDeleteMessages    { return [self isGranted:@"can_delete_messages"]; }
- (BOOL)canInviteUsers       { return [self isGranted:@"can_invite_users"]; }
- (BOOL)canRestrictMembers   { return [self isGranted:@"can_restrict_members"]; }
- (BOOL)canPinMessages       { return [self isGranted:@"can_pin_messages"]; }
- (BOOL)canManageTopics      { return [self isGranted:@"can_manage_topics"]; }
- (BOOL)canPromoteMembers    { return [self isGranted:@"can_promote_members"]; }
- (BOOL)canManageVideoChats  { return [self isGranted:@"can_manage_video_chats"]; }
- (BOOL)isAnonymous          { return [self isGranted:@"is_anonymous"]; }

- (BOOL)canSendBasicMessages { return [self isGranted:@"can_send_basic_messages"]; }
- (BOOL)canSendPolls         { return [self isGranted:@"can_send_polls"]; }
- (BOOL)canSendOtherMessages { return [self isGranted:@"can_send_other_messages"]; }
- (BOOL)canAddLinkPreviews   { return [self isGranted:@"can_add_link_previews"]; }

- (BOOL)canSendMedia {
	return [self isGranted:@"can_send_photos"]
			|| [self isGranted:@"can_send_videos"]
			|| [self isGranted:@"can_send_audios"]
			|| [self isGranted:@"can_send_documents"]
			|| [self isGranted:@"can_send_video_notes"]
			|| [self isGranted:@"can_send_voice_notes"];
}

@end

@interface TGMemberModel ()
- (id)initWithDictionary:(NSDictionary *)dict userId:(int64_t)userId;
@end

@implementation TGMemberModel

@synthesize userId = _userId;
@synthesize name = _name;
@synthesize status = _status;
@synthesize customTitle = _customTitle;
@synthesize isOwner = _isOwner;
@synthesize isAdmin = _isAdmin;
@synthesize canBeEdited = _canBeEdited;
@synthesize untilDate = _untilDate;
@synthesize inviterUserId = _inviterUserId;
@synthesize joinedDate = _joinedDate;
@synthesize rights = _rights;
@synthesize permissions = _permissions;

- (id)initWithDictionary:(NSDictionary *)dict userId:(int64_t)userId {
	self = [super init];
	if (!self)
		return nil;

	_userId = userId;
	_name = TGMemberCopyString(dict, @"name");
	_customTitle = TGMemberCopyString(dict, @"customTitle");

	NSString *statusString = TGMemberCopyString(dict, @"status");
	_status = TGMemberStatusFromString(statusString);

	_isOwner = TGMemberBool(dict, @"isOwner") || _status == TGMemberStatusCreator;
	_isAdmin = TGMemberBool(dict, @"isAdmin") || _isOwner
			|| _status == TGMemberStatusAdministrator;
	_canBeEdited = TGMemberBool(dict, @"canBeEdited");

	NSInteger until = TGMemberInteger(dict, @"untilDate");
	_untilDate = until > 0 ? until : 0;
	_inviterUserId = TGMemberIdentifier(dict, @"inviterUserId");
	NSInteger joined = TGMemberInteger(dict, @"joinedDate");
	_joinedDate = joined > 0 ? joined : 0;

	id rawRights = [dict objectForKey:@"rights"];
	id rawPermissions = [dict objectForKey:@"permissions"];
	_rights = [TGMemberRightsModel fromDictionary:
			[rawRights isKindOfClass:[NSDictionary class]] ? rawRights : nil];
	_permissions = [TGMemberRightsModel fromDictionary:
			[rawPermissions isKindOfClass:[NSDictionary class]] ? rawPermissions : nil];

	return self;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;
	int64_t userId = TGMemberIdentifier(dict, @"id");
	if (userId == 0)
		return nil;
	return [[self alloc] initWithDictionary:dict userId:userId];
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	if (![dicts isKindOfClass:[NSArray class]])
		return [NSArray array];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:[dicts count]];
	for (id entry in dicts) {
		TGMemberModel *model = [self fromDictionary:entry];
		if (model)
			[out addObject:model];
	}
	return out;
}

- (NSString *)statusString {
	return TGMemberStatusToString(_status);
}

- (BOOL)expires {
	return _untilDate > 0;
}

@end

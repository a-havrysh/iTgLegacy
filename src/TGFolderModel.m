#import "TGFolderModel.h"

@interface TGFolderModel ()
@property (nonatomic, assign) int64_t folderId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, assign) NSInteger colorId;
@property (nonatomic, assign) BOOL isShareable;
@property (nonatomic, copy) NSString *folderDescription;
@property (nonatomic, assign) NSInteger order;
@property (nonatomic, copy) NSArray *pinnedChatIds;
@property (nonatomic, copy) NSArray *includedChatIds;
@property (nonatomic, assign) BOOL includeContacts;
@property (nonatomic, assign) BOOL includeNonContacts;
@property (nonatomic, assign) BOOL includeBots;
@property (nonatomic, assign) BOOL includeGroups;
@property (nonatomic, assign) BOOL includeChannels;
@property (nonatomic, copy) NSArray *excludedChatIds;
@property (nonatomic, assign) BOOL excludeMuted;
@property (nonatomic, assign) BOOL excludeRead;
@property (nonatomic, assign) BOOL excludeArchived;
@property (nonatomic, assign) BOOL isSummaryOnly;
@end

static NSString *TGFolderString(id value) {
	if (![value isKindOfClass:[NSString class]])
		return nil;
	NSString *text = (NSString *)value;
	return text.length ? [text copy] : nil;
}

static BOOL TGFolderBool(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value boolValue];
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value boolValue];
	return NO;
}

static int64_t TGFolderId(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value longLongValue];
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value longLongValue];
	return 0;
}

static NSArray *TGFolderIdArray(id value) {
	if (![value isKindOfClass:[NSArray class]])
		return [NSArray array];
	NSMutableArray *out = [NSMutableArray array];
	for (id entry in (NSArray *)value) {
		int64_t chatId = TGFolderId(entry);
		if (chatId != 0)
			[out addObject:[NSNumber numberWithLongLong:chatId]];
	}
	return out;
}

@implementation TGFolderModel

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;

	NSDictionary *outer = dict;
	NSDictionary *definition = dict;
	if ([dict[@"folder"] isKindOfClass:[NSDictionary class]])
		definition = (NSDictionary *)dict[@"folder"];

	int64_t folderId = TGFolderId(definition[@"id"]);
	if (folderId == 0)
		folderId = TGFolderId(outer[@"id"]);

	NSString *title = TGFolderString(definition[@"title"]);
	if (!title)
		title = TGFolderString(outer[@"title"]);

	if (folderId == 0 && !title)
		return nil;

	TGFolderModel *model = [[TGFolderModel alloc] init];
	model.folderId = folderId;
	model.title = title;

	NSString *icon = TGFolderString(definition[@"icon"]);
	if (!icon)
		icon = TGFolderString(outer[@"icon"]);
	model.iconName = icon;

	model.folderDescription = TGFolderString(outer[@"description"]);

	id colorValue = definition[@"colorId"];
	if ([colorValue isKindOfClass:[NSNumber class]])
		model.colorId = (NSInteger)[(NSNumber *)colorValue integerValue];
	else if ([colorValue isKindOfClass:[NSString class]])
		model.colorId = (NSInteger)[(NSString *)colorValue integerValue];
	else
		model.colorId = -1;

	model.isShareable = TGFolderBool(definition[@"isShareable"]);

	model.pinnedChatIds = TGFolderIdArray(definition[@"pinnedChatIds"]);
	model.includedChatIds = TGFolderIdArray(definition[@"includedChatIds"]);
	model.excludedChatIds = TGFolderIdArray(definition[@"excludedChatIds"]);

	model.includeContacts = TGFolderBool(definition[@"includeContacts"]);
	model.includeNonContacts = TGFolderBool(definition[@"includeNonContacts"]);
	model.includeBots = TGFolderBool(definition[@"includeBots"]);
	model.includeGroups = TGFolderBool(definition[@"includeGroups"]);
	model.includeChannels = TGFolderBool(definition[@"includeChannels"]);

	model.excludeMuted = TGFolderBool(definition[@"excludeMuted"]);
	model.excludeRead = TGFolderBool(definition[@"excludeRead"]);
	model.excludeArchived = TGFolderBool(definition[@"excludeArchived"]);

	model.order = 0;
	model.isSummaryOnly = (definition[@"includedChatIds"] == nil &&
						   definition[@"excludedChatIds"] == nil &&
						   definition[@"icon"] == nil &&
						   definition[@"includeContacts"] == nil);
	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	if (![dicts isKindOfClass:[NSArray class]])
		return [NSArray array];
	NSMutableArray *out = [NSMutableArray array];
	for (id entry in dicts) {
		TGFolderModel *model = [self fromDictionary:entry];
		if (!model)
			continue;
		model.order = (NSInteger)out.count;
		[out addObject:model];
	}
	return out;
}

- (BOOL)isEmptyDefinition {
	return self.includedChatIds.count == 0 &&
		   !self.includeContacts && !self.includeNonContacts &&
		   !self.includeBots && !self.includeGroups && !self.includeChannels;
}

- (NSDictionary *)dictionaryRepresentation {
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	if (self.folderId != 0)
		out[@"id"] = [NSNumber numberWithLongLong:self.folderId];
	out[@"title"] = self.title ?: @"";
	out[@"icon"] = self.iconName ?: @"";
	out[@"colorId"] = [NSNumber numberWithInteger:self.colorId];
	out[@"isShareable"] = [NSNumber numberWithBool:self.isShareable];
	out[@"pinnedChatIds"] = self.pinnedChatIds ?: [NSArray array];
	out[@"includedChatIds"] = self.includedChatIds ?: [NSArray array];
	out[@"excludedChatIds"] = self.excludedChatIds ?: [NSArray array];
	out[@"includeContacts"] = [NSNumber numberWithBool:self.includeContacts];
	out[@"includeNonContacts"] = [NSNumber numberWithBool:self.includeNonContacts];
	out[@"includeBots"] = [NSNumber numberWithBool:self.includeBots];
	out[@"includeGroups"] = [NSNumber numberWithBool:self.includeGroups];
	out[@"includeChannels"] = [NSNumber numberWithBool:self.includeChannels];
	out[@"excludeMuted"] = [NSNumber numberWithBool:self.excludeMuted];
	out[@"excludeRead"] = [NSNumber numberWithBool:self.excludeRead];
	out[@"excludeArchived"] = [NSNumber numberWithBool:self.excludeArchived];
	return out;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"<TGFolderModel %lld \"%@\" icon=%@ inc=%lu exc=%lu>",
			self.folderId, self.title ?: @"", self.iconName ?: @"-",
			(unsigned long)self.includedChatIds.count,
			(unsigned long)self.excludedChatIds.count];
}

@end

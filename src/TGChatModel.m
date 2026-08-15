#import "TGChatModel.h"

@interface TGChatModel ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *previewText;
@property (nonatomic, copy) NSString *draftText;
@property (nonatomic, copy) NSString *actionText;
@property (nonatomic, assign) int64_t date;
@property (nonatomic, assign) NSInteger unreadCount;
@property (nonatomic, assign) BOOL markedUnread;
@property (nonatomic, assign) BOOL pinned;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) BOOL group;
@property (nonatomic, assign) BOOL channel;
@property (nonatomic, assign) BOOL privateChat;
@property (nonatomic, assign) BOOL forum;
@property (nonatomic, assign) BOOL savedMessages;
@property (nonatomic, assign) int64_t supergroupId;
@property (nonatomic, assign) int32_t photoFileId;
@property (nonatomic, assign) int64_t order;
@property (nonatomic, assign) int64_t archiveOrder;
@property (nonatomic, assign) BOOL online;
@property (nonatomic, assign) BOOL outgoing;
@property (nonatomic, assign) BOOL outgoingRead;
@property (nonatomic, assign) BOOL sponsored;
@property (nonatomic, assign) int64_t sponsoredUniqueId;
@end

static NSString *TGChatModelString(id value) {
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value length] ? value : nil;
	return nil;
}

static int64_t TGChatModelInt64(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value longLongValue];
	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value longLongValue];
	return 0;
}

static BOOL TGChatModelBool(id value) {
	if ([value isKindOfClass:[NSNumber class]])
		return [(NSNumber *)value boolValue];
	return NO;
}

@implementation TGChatModel

+ (instancetype)fromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;

	int64_t chatId = TGChatModelInt64([dict objectForKey:@"id"]);
	if (chatId == 0)
		return nil;

	TGChatModel *model = [[TGChatModel alloc] init];
	model.chatId = chatId;
	model.title = TGChatModelString([dict objectForKey:@"title"]);
	model.previewText = TGChatModelString([dict objectForKey:@"text"]);
	model.draftText = TGChatModelString([dict objectForKey:@"draft"]);
	model.actionText = TGChatModelString([dict objectForKey:@"action"]);
	model.date = TGChatModelInt64([dict objectForKey:@"date"]);

	int64_t unread = TGChatModelInt64([dict objectForKey:@"unread"]);
	if (unread < 0)
		unread = 0;
	model.unreadCount = (NSInteger)unread;
	model.markedUnread = TGChatModelBool([dict objectForKey:@"markedUnread"]);

	model.pinned = TGChatModelBool([dict objectForKey:@"isPinned"]);
	model.muted = TGChatModelBool([dict objectForKey:@"isMuted"]);
	model.group = TGChatModelBool([dict objectForKey:@"isGroup"]);
	model.channel = TGChatModelBool([dict objectForKey:@"isChannel"]);
	model.privateChat = TGChatModelBool([dict objectForKey:@"isPrivate"]);
	model.forum = TGChatModelBool([dict objectForKey:@"isForum"]);
	model.savedMessages = TGChatModelBool([dict objectForKey:@"isSaved"]);
	model.supergroupId = TGChatModelInt64([dict objectForKey:@"supergroupId"]);
	model.photoFileId = (int32_t)TGChatModelInt64([dict objectForKey:@"photoFileId"]);
	model.order = TGChatModelInt64([dict objectForKey:@"order"]);
	model.archiveOrder = TGChatModelInt64([dict objectForKey:@"archiveOrder"]);
	model.online = TGChatModelBool([dict objectForKey:@"isOnline"]);
	model.outgoing = TGChatModelBool([dict objectForKey:@"outgoing"]);
	model.outgoingRead = TGChatModelBool([dict objectForKey:@"outgoingRead"]);
	model.sponsored = TGChatModelBool([dict objectForKey:@"sponsored"]);
	model.sponsoredUniqueId = TGChatModelInt64([dict objectForKey:@"uniqueId"]);

	return model;
}

+ (NSArray *)arrayFromDictionaries:(NSArray *)dicts {
	if (![dicts isKindOfClass:[NSArray class]])
		return [NSArray array];

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:[dicts count]];
	for (id entry in dicts){
		TGChatModel *model = [self fromDictionary:entry];
		if (model)
			[out addObject:model];
	}
	return out;
}

- (BOOL)hasUnread {
	return self.unreadCount > 0 || self.markedUnread;
}

- (BOOL)archived {
	return self.archiveOrder > 0;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"<TGChatModel %lld %@ unread=%ld>",
			self.chatId, self.title ?: @"(no title)", (long)self.unreadCount];
}

@end

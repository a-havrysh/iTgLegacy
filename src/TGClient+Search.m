#import "TGClient+Search.h"
#import "TGClient+Private.h"

static NSString *TGSearchTextForContent(NSDictionary *content) {
	if (![content isKindOfClass:NSDictionary.class])
		return @"";
	NSString *type = [content[@"@type"] isKindOfClass:NSString.class] ? content[@"@type"] : @"";
	NSDictionary *text = content[@"text"];
	if ([text isKindOfClass:NSDictionary.class] && [text[@"text"] isKindOfClass:NSString.class])
		return text[@"text"];
	NSDictionary *caption = content[@"caption"];
	if ([caption isKindOfClass:NSDictionary.class] &&
		[caption[@"text"] isKindOfClass:NSString.class] &&
		[caption[@"text"] length])
		return caption[@"text"];

	if ([type isEqualToString:@"messagePhoto"])            return @"Photo";
	if ([type isEqualToString:@"messageVideo"])            return @"Video";
	if ([type isEqualToString:@"messageVideoNote"])        return @"Video message";
	if ([type isEqualToString:@"messageVoiceNote"])        return @"Voice message";
	if ([type isEqualToString:@"messageAnimation"])        return @"GIF";
	if ([type isEqualToString:@"messageSticker"])          return @"Sticker";
	if ([type isEqualToString:@"messageLocation"])         return @"Location";
	if ([type isEqualToString:@"messageLiveLocation"])     return @"Live location";
	if ([type isEqualToString:@"messageContact"])          return @"Contact";
	if ([type isEqualToString:@"messagePoll"])             return @"Poll";
	if ([type isEqualToString:@"messageCall"])             return @"Call";
	if ([type isEqualToString:@"messageDocument"]){
		NSDictionary *doc = content[@"document"];
		NSString *name = [doc isKindOfClass:NSDictionary.class] ? doc[@"file_name"] : nil;
		return [name isKindOfClass:NSString.class] && name.length ? name : @"Document";
	}
	if ([type isEqualToString:@"messageAudio"]){
		NSDictionary *audio = content[@"audio"];
		NSString *title = [audio isKindOfClass:NSDictionary.class] ? audio[@"title"] : nil;
		return [title isKindOfClass:NSString.class] && title.length ? title : @"Audio";
	}
	return @"";
}

static NSNumber *TGSearchPhotoIdForContent(NSDictionary *content) {
	if (![content isKindOfClass:NSDictionary.class])
		return nil;
	NSString *type = [content[@"@type"] isKindOfClass:NSString.class] ? content[@"@type"] : @"";
	if ([type isEqualToString:@"messagePhoto"]){
		NSArray *sizes = content[@"photo"][@"sizes"];
		if ([sizes isKindOfClass:NSArray.class] && sizes.count){
			NSDictionary *largest = [sizes lastObject];
			if ([largest isKindOfClass:NSDictionary.class])
				return largest[@"photo"][@"id"];
		}
		return nil;
	}
	NSString *key = nil;
	if ([type isEqualToString:@"messageVideo"])           key = @"video";
	else if ([type isEqualToString:@"messageVideoNote"])  key = @"video_note";
	else if ([type isEqualToString:@"messageAnimation"])  key = @"animation";
	else if ([type isEqualToString:@"messageDocument"])   key = @"document";
	else if ([type isEqualToString:@"messageSticker"])    key = @"sticker";
	if (!key)
		return nil;
	NSDictionary *media = content[key];
	if (![media isKindOfClass:NSDictionary.class])
		return nil;
	NSDictionary *thumb = media[@"thumbnail"];
	if (![thumb isKindOfClass:NSDictionary.class])
		return nil;
	return thumb[@"file"][@"id"];
}

@implementation TGClient (Search)

#pragma mark - shaping

- (NSString *)tgs_titleForChat:(int64_t)chatId {
	NSArray *lists = [NSArray arrayWithObjects:
			self.chats ?: [NSArray array], self.archivedChats ?: [NSArray array], nil];
	for (NSArray *list in lists){
		if (![list isKindOfClass:NSArray.class])
			continue;
		for (NSDictionary *c in list){
			if (![c isKindOfClass:NSDictionary.class])
				continue;
			if ([c[@"id"] longLongValue] == chatId){
				NSString *title = c[@"title"];
				return [title isKindOfClass:NSString.class] ? title : nil;
			}
		}
	}
	return nil;
}

- (NSDictionary *)tgs_rowForMessage:(NSDictionary *)m {
	if (![m isKindOfClass:NSDictionary.class])
		return nil;
	NSDictionary *content = m[@"content"];
	int64_t chatId = [m[@"chat_id"] longLongValue];

	int64_t senderId = 0;
	NSDictionary *sender = m[@"sender_id"];
	if ([sender isKindOfClass:NSDictionary.class] &&
		[sender[@"@type"] isEqualToString:@"messageSenderUser"])
		senderId = [sender[@"user_id"] longLongValue];

	NSString *senderName = senderId ? [self nameForUserId:senderId] : nil;
	NSNumber *photoId = TGSearchPhotoIdForContent(content);
	NSString *kind = [content isKindOfClass:NSDictionary.class] ? content[@"@type"] : nil;

	return [NSDictionary dictionaryWithObjectsAndKeys:
			m[@"id"] ?: [NSNumber numberWithInt:0],     @"id",
			[NSNumber numberWithLongLong:chatId],       @"chatId",
			[self tgs_titleForChat:chatId] ?: @"",      @"chatTitle",
			TGSearchTextForContent(content),            @"text",
			m[@"date"] ?: [NSNumber numberWithInt:0],   @"date",
			m[@"is_outgoing"] ?: [NSNumber numberWithBool:NO], @"outgoing",
			[NSNumber numberWithLongLong:senderId],     @"senderId",
			senderName ?: @"",                          @"senderName",
			photoId ?: [NSNull null],                   @"photoId",
			[kind isKindOfClass:NSString.class] ? kind : @"", @"kind",
			nil];
}

- (NSArray *)tgs_rowsForMessages:(id)messages {
	NSMutableArray *out = [NSMutableArray array];
	if (![messages isKindOfClass:NSArray.class])
		return out;
	for (NSDictionary *m in messages){
		NSDictionary *row = [self tgs_rowForMessage:m];
		if (row)
			[out addObject:row];
	}
	return out;
}

- (NSDictionary *)tgs_filterObject:(NSString *)filter {
	if (![filter isKindOfClass:NSString.class] || !filter.length)
		return [NSDictionary dictionaryWithObject:@"searchMessagesFilterEmpty" forKey:@"@type"];
	return [NSDictionary dictionaryWithObject:filter forKey:@"@type"];
}

- (NSString *)tgs_string:(id)value {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

- (void)tgs_foundMessages:(NSDictionary *)request
               completion:(void (^)(NSArray *, NSString *))completion {
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result isKindOfClass:NSDictionary.class] ||
			[result[@"@type"] isEqualToString:@"error"]){
			completion([NSArray array], @"");
			return;
		}
		NSString *next = result[@"next_offset"];
		completion([self tgs_rowsForMessages:result[@"messages"]],
				   [next isKindOfClass:NSString.class] ? next : @"");
	}];
}

- (void)tgs_foundChatMessages:(NSDictionary *)request
                   completion:(void (^)(NSArray *, int64_t, NSInteger))completion {
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result isKindOfClass:NSDictionary.class] ||
			[result[@"@type"] isEqualToString:@"error"]){
			completion([NSArray array], 0, 0);
			return;
		}
		completion([self tgs_rowsForMessages:result[@"messages"]],
				   [result[@"next_from_message_id"] longLongValue],
				   [result[@"total_count"] integerValue]);
	}];
}

- (void)tgs_hashtags:(NSDictionary *)request completion:(void (^)(NSArray *))completion {
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *tags = [result isKindOfClass:NSDictionary.class] ? result[@"hashtags"] : nil;
		if (![tags isKindOfClass:NSArray.class]){
			completion([NSArray array]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id tag in tags)
			if ([tag isKindOfClass:NSString.class])
				[out addObject:tag];
		completion(out);
	}];
}

#pragma mark - global message search

- (void)searchMessagesWithQuery:(NSString *)query
                         filter:(NSString *)filter
                       chatType:(NSString *)chatType
                        minDate:(NSInteger)minDate
                        maxDate:(NSInteger)maxDate
                         offset:(NSString *)offset
                          limit:(NSInteger)limit
                     completion:(void (^)(NSArray *, NSString *))completion {
	NSMutableDictionary *request = [NSMutableDictionary dictionary];
	[request setObject:@"searchMessages" forKey:@"@type"];
	[request setObject:[self tgs_string:query] forKey:@"query"];
	[request setObject:[self tgs_string:offset] forKey:@"offset"];
	[request setObject:[NSNumber numberWithInteger:limit > 0 ? limit : 50] forKey:@"limit"];
	[request setObject:[self tgs_filterObject:filter] forKey:@"filter"];
	[request setObject:[NSNumber numberWithInteger:minDate > 0 ? minDate : 0] forKey:@"min_date"];
	[request setObject:[NSNumber numberWithInteger:maxDate > 0 ? maxDate : 0] forKey:@"max_date"];

	if ([chatType isKindOfClass:NSString.class] && chatType.length){
		NSString *type = nil;
		if ([chatType isEqualToString:@"private"])
			type = @"searchMessagesChatTypeFilterPrivate";
		else if ([chatType isEqualToString:@"group"])
			type = @"searchMessagesChatTypeFilterGroup";
		else if ([chatType isEqualToString:@"channel"])
			type = @"searchMessagesChatTypeFilterChannel";
		if (type)
			[request setObject:[NSDictionary dictionaryWithObject:type forKey:@"@type"]
						forKey:@"chat_type_filter"];
	}

	[self tgs_foundMessages:request completion:completion];
}

- (void)searchMessagesWithQuery:(NSString *)query
                         filter:(NSString *)filter
                         offset:(NSString *)offset
                     completion:(void (^)(NSArray *, NSString *))completion {
	[self searchMessagesWithQuery:query
						   filter:filter
						 chatType:nil
						  minDate:0
						  maxDate:0
						   offset:offset
							limit:50
					   completion:completion];
}

#pragma mark - in-chat message search

- (void)searchMessagesInChat:(int64_t)chatId
                       query:(NSString *)query
                senderUserId:(int64_t)senderUserId
                      filter:(NSString *)filter
               fromMessageId:(int64_t)fromMessageId
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *, int64_t, NSInteger))completion {
	NSMutableDictionary *request = [NSMutableDictionary dictionary];
	[request setObject:@"searchChatMessages" forKey:@"@type"];
	[request setObject:[NSNumber numberWithLongLong:chatId] forKey:@"chat_id"];
	[request setObject:[self tgs_string:query] forKey:@"query"];
	[request setObject:[NSNumber numberWithLongLong:fromMessageId] forKey:@"from_message_id"];
	[request setObject:[NSNumber numberWithInt:0] forKey:@"offset"];
	[request setObject:[NSNumber numberWithInteger:limit > 0 ? limit : 50] forKey:@"limit"];
	[request setObject:[self tgs_filterObject:filter] forKey:@"filter"];

	if (senderUserId != 0){
		[request setObject:[NSDictionary dictionaryWithObjectsAndKeys:
				@"messageSenderUser", @"@type",
				[NSNumber numberWithLongLong:senderUserId], @"user_id", nil]
					forKey:@"sender_id"];
	}

	[self tgs_foundChatMessages:request completion:completion];
}

- (void)recentLocationMessagesInChat:(int64_t)chatId
                               limit:(NSInteger)limit
                          completion:(void (^)(NSArray *))completion {
	[self request:[NSDictionary dictionaryWithObjectsAndKeys:
			@"searchChatRecentLocationMessages", @"@type",
			[NSNumber numberWithLongLong:chatId], @"chat_id",
			[NSNumber numberWithInteger:limit > 0 ? limit : 20], @"limit", nil]
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion([self tgs_rowsForMessages:
				[result isKindOfClass:NSDictionary.class] ? result[@"messages"] : nil]);
	}];
}

#pragma mark - special message searches

- (void)searchCallMessagesOnlyMissed:(BOOL)onlyMissed
                              offset:(NSString *)offset
                               limit:(NSInteger)limit
                          completion:(void (^)(NSArray *, NSString *))completion {
	[self tgs_foundMessages:[NSDictionary dictionaryWithObjectsAndKeys:
			@"searchCallMessages", @"@type",
			[self tgs_string:offset], @"offset",
			[NSNumber numberWithInteger:limit > 0 ? limit : 50], @"limit",
			[NSNumber numberWithBool:onlyMissed], @"only_missed", nil]
				 completion:completion];
}

- (void)searchOutgoingDocumentsWithQuery:(NSString *)query
                                   limit:(NSInteger)limit
                              completion:(void (^)(NSArray *))completion {
	[self tgs_foundMessages:[NSDictionary dictionaryWithObjectsAndKeys:
			@"searchOutgoingDocumentMessages", @"@type",
			[self tgs_string:query], @"query",
			[NSNumber numberWithInteger:limit > 0 ? limit : 50], @"limit", nil]
				 completion:^(NSArray *messages, NSString *nextOffset){
		if (completion)
			completion(messages);
	}];
}

- (void)searchPublicMessagesWithTag:(NSString *)tag
                             offset:(NSString *)offset
                              limit:(NSInteger)limit
                         completion:(void (^)(NSArray *, NSString *))completion {
	[self tgs_foundMessages:[NSDictionary dictionaryWithObjectsAndKeys:
			@"searchPublicMessagesByTag", @"@type",
			[self tgs_string:tag], @"tag",
			[self tgs_string:offset], @"offset",
			[NSNumber numberWithInteger:limit > 0 ? limit : 50], @"limit", nil]
				 completion:completion];
}

#pragma mark - hashtags

- (void)searchHashtagsWithPrefix:(NSString *)prefix
                           limit:(NSInteger)limit
                      completion:(void (^)(NSArray *))completion {
	[self tgs_hashtags:[NSDictionary dictionaryWithObjectsAndKeys:
			@"searchHashtags", @"@type",
			[self tgs_string:prefix], @"prefix",
			[NSNumber numberWithInteger:limit > 0 ? limit : 20], @"limit", nil]
			completion:completion];
}

- (void)searchedForTagsWithPrefix:(NSString *)prefix
                            limit:(NSInteger)limit
                       completion:(void (^)(NSArray *))completion {
	[self tgs_hashtags:[NSDictionary dictionaryWithObjectsAndKeys:
			@"getSearchedForTags", @"@type",
			[self tgs_string:prefix], @"tag_prefix",
			[NSNumber numberWithInteger:limit > 0 ? limit : 20], @"limit", nil]
			completion:completion];
}

- (void)removeSearchedForTag:(NSString *)tag {
	if (![tag isKindOfClass:NSString.class] || !tag.length)
		return;
	[self send:[NSDictionary dictionaryWithObjectsAndKeys:
			@"removeSearchedForTag", @"@type", tag, @"tag", nil]];
}

- (void)clearSearchedForTagsIncludingCashtags:(BOOL)cashtags {
	[self send:[NSDictionary dictionaryWithObjectsAndKeys:
			@"clearSearchedForTags", @"@type",
			[NSNumber numberWithBool:cashtags], @"clear_cashtags", nil]];
}

#pragma mark - public chats

- (NSMutableDictionary *)tgs_summaryForChat:(NSDictionary *)chat {
	if (![chat isKindOfClass:NSDictionary.class] ||
		![chat[@"@type"] isEqualToString:@"chat"])
		return nil;

	NSDictionary *type = chat[@"type"];
	NSString *typeName = [type isKindOfClass:NSDictionary.class] &&
			[type[@"@type"] isKindOfClass:NSString.class] ? type[@"@type"] : @"";
	BOOL isSupergroup = [typeName isEqualToString:@"chatTypeSupergroup"];
	BOOL isChannel = isSupergroup && [type[@"is_channel"] boolValue];
	BOOL isGroup = [typeName isEqualToString:@"chatTypeBasicGroup"] ||
			(isSupergroup && !isChannel);
	BOOL isPrivate = [typeName isEqualToString:@"chatTypePrivate"];

	NSNumber *photoId = nil;
	NSDictionary *photo = chat[@"photo"];
	if ([photo isKindOfClass:NSDictionary.class]){
		NSDictionary *small = photo[@"small"];
		if ([small isKindOfClass:NSDictionary.class] &&
			[small[@"id"] isKindOfClass:NSNumber.class])
			photoId = small[@"id"];
	}

	NSString *title = [chat[@"title"] isKindOfClass:NSString.class] ? chat[@"title"] : @"";

	NSMutableDictionary *row = [NSMutableDictionary dictionary];
	[row setObject:(chat[@"id"] ?: [NSNumber numberWithInt:0]) forKey:@"id"];
	[row setObject:title forKey:@"title"];
	[row setObject:@"" forKey:@"username"];
	[row setObject:(photoId ?: (id)[NSNull null]) forKey:@"photoFileId"];
	[row setObject:[NSNumber numberWithInt:0] forKey:@"memberCount"];
	[row setObject:[NSNumber numberWithBool:isChannel] forKey:@"isChannel"];
	[row setObject:[NSNumber numberWithBool:isGroup] forKey:@"isGroup"];
	[row setObject:[NSNumber numberWithBool:isPrivate] forKey:@"isPrivate"];
	[row setObject:[NSNumber numberWithBool:NO] forKey:@"isVerified"];
	if (isSupergroup && [type[@"supergroup_id"] isKindOfClass:NSNumber.class])
		[row setObject:type[@"supergroup_id"] forKey:@"tgsSupergroupId"];
	return row;
}

- (void)tgs_fillSupergroupDetails:(NSMutableDictionary *)row
                       completion:(void (^)(NSDictionary *chat))completion {
	NSNumber *supergroupId = [row objectForKey:@"tgsSupergroupId"];
	if (![supergroupId isKindOfClass:NSNumber.class]){
		if (completion)
			completion(row);
		return;
	}
	[row removeObjectForKey:@"tgsSupergroupId"];

	[self request:[NSDictionary dictionaryWithObjectsAndKeys:
			@"getSupergroup", @"@type", supergroupId, @"supergroup_id", nil]
	   completion:^(NSDictionary *group){
		if ([group isKindOfClass:NSDictionary.class] &&
			[group[@"@type"] isEqualToString:@"supergroup"]){
			NSDictionary *usernames = group[@"usernames"];
			if ([usernames isKindOfClass:NSDictionary.class]){
				NSString *editable = usernames[@"editable_username"];
				NSArray *active = usernames[@"active_usernames"];
				NSString *name = nil;
				if ([active isKindOfClass:NSArray.class] && active.count &&
					[[active objectAtIndex:0] isKindOfClass:NSString.class])
					name = [active objectAtIndex:0];
				else if ([editable isKindOfClass:NSString.class] && editable.length)
					name = editable;
				if (name)
					[row setObject:name forKey:@"username"];
			}
			if ([group[@"member_count"] isKindOfClass:NSNumber.class])
				[row setObject:group[@"member_count"] forKey:@"memberCount"];
			NSDictionary *verification = group[@"verification_status"];
			if ([verification isKindOfClass:NSDictionary.class])
				[row setObject:[NSNumber numberWithBool:
						[verification[@"is_verified"] boolValue]] forKey:@"isVerified"];
		}
		if (completion)
			completion(row);
	}];
}

- (void)chatSummaryForChatId:(int64_t)chatId
                  completion:(void (^)(NSDictionary *))completion {
	[self request:[NSDictionary dictionaryWithObjectsAndKeys:
			@"getChat", @"@type",
			[NSNumber numberWithLongLong:chatId], @"chat_id", nil]
	   completion:^(NSDictionary *result){
		NSMutableDictionary *row = [self tgs_summaryForChat:result];
		if (!row){
			if (completion)
				completion(nil);
			return;
		}
		[self tgs_fillSupergroupDetails:row completion:completion];
	}];
}

- (void)publicChatWithUsername:(NSString *)username
                    completion:(void (^)(NSDictionary *))completion {
	NSString *name = [self tgs_string:username];
	while ([name hasPrefix:@"@"])
		name = [name substringFromIndex:1];
	if (!name.length){
		if (completion)
			completion(nil);
		return;
	}

	[self request:[NSDictionary dictionaryWithObjectsAndKeys:
			@"searchPublicChat", @"@type", name, @"username", nil]
	   completion:^(NSDictionary *result){
		NSMutableDictionary *row = [self tgs_summaryForChat:result];
		if (!row){
			if (completion)
				completion(nil);
			return;
		}
		[self tgs_fillSupergroupDetails:row completion:completion];
	}];
}

- (void)searchPublicChatsWithQuery:(NSString *)query
                              type:(NSString *)type
                        completion:(void (^)(NSArray *))completion {
	NSMutableDictionary *request = [NSMutableDictionary dictionary];
	[request setObject:@"searchPublicChats" forKey:@"@type"];
	[request setObject:[self tgs_string:query] forKey:@"query"];

	if ([type isKindOfClass:NSString.class] && type.length){
		NSString *filter = nil;
		if ([type isEqualToString:@"channel"])  filter = @"searchChatTypeFilterChannel";
		else if ([type isEqualToString:@"bot"]) filter = @"searchChatTypeFilterBot";
		if (filter)
			[request setObject:[NSDictionary dictionaryWithObject:filter forKey:@"@type"]
						forKey:@"type_filter"];
	}

	[self request:request completion:^(NSDictionary *result){
		NSArray *ids = [result isKindOfClass:NSDictionary.class] ? result[@"chat_ids"] : nil;
		NSMutableArray *clean = [NSMutableArray array];
		if ([ids isKindOfClass:NSArray.class])
			for (id chatId in ids)
				if ([chatId isKindOfClass:NSNumber.class])
					[clean addObject:chatId];

		if (!clean.count){
			if (completion)
				completion([NSArray array]);
			return;
		}

		NSMutableArray *rows = [NSMutableArray array];
		for (NSUInteger i = 0; i < clean.count; i++)
			[rows addObject:[NSNull null]];

		__block NSInteger pending = (NSInteger)clean.count;
		for (NSUInteger i = 0; i < clean.count; i++){
			NSUInteger slot = i;
			[self chatSummaryForChatId:[[clean objectAtIndex:i] longLongValue]
							completion:^(NSDictionary *chat){
				if (chat)
					[rows replaceObjectAtIndex:slot withObject:chat];
				pending--;
				if (pending > 0 || !completion)
					return;
				NSMutableArray *out = [NSMutableArray array];
				for (id row in rows)
					if ([row isKindOfClass:NSDictionary.class])
						[out addObject:row];
				completion(out);
			}];
		}
	}];
}

- (void)searchPublicChatsWithQuery:(NSString *)query
                        completion:(void (^)(NSArray *))completion {
	[self searchPublicChatsWithQuery:query type:nil completion:completion];
}

#pragma mark - recents

- (void)recentlyFoundChatsWithQuery:(NSString *)query
                              limit:(NSInteger)limit
                         completion:(void (^)(NSArray *))completion {
	[self request:[NSDictionary dictionaryWithObjectsAndKeys:
			@"searchRecentlyFoundChats", @"@type",
			[self tgs_string:query], @"query",
			[NSNumber numberWithInteger:limit > 0 ? limit : 20], @"limit", nil]
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *ids = [result isKindOfClass:NSDictionary.class] ? result[@"chat_ids"] : nil;
		if (![ids isKindOfClass:NSArray.class]){
			completion([NSArray array]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id chatId in ids){
			if (![chatId isKindOfClass:NSNumber.class])
				continue;
			int64_t identifier = [chatId longLongValue];
			NSNumber *photo = [self photoFileIdForChat:identifier];
			[out addObject:[NSDictionary dictionaryWithObjectsAndKeys:
					chatId, @"id",
					[self tgs_titleForChat:identifier] ?: @"", @"title",
					photo ?: [NSNull null], @"photoFileId", nil]];
		}
		completion(out);
	}];
}

#pragma mark - jumping around a history

- (void)messageInChat:(int64_t)chatId
        closestToDate:(NSInteger)date
           completion:(void (^)(int64_t))completion {
	[self request:[NSDictionary dictionaryWithObjectsAndKeys:
			@"getChatMessageByDate", @"@type",
			[NSNumber numberWithLongLong:chatId], @"chat_id",
			[NSNumber numberWithInteger:date], @"date", nil]
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result isKindOfClass:NSDictionary.class] ||
			![result[@"@type"] isEqualToString:@"message"]){
			completion(0);
			return;
		}
		completion([result[@"id"] longLongValue]);
	}];
}

- (void)messageCalendarForChat:(int64_t)chatId
                        filter:(NSString *)filter
                 fromMessageId:(int64_t)fromMessageId
                    completion:(void (^)(NSArray *, NSInteger))completion {
	[self request:[NSDictionary dictionaryWithObjectsAndKeys:
			@"getChatMessageCalendar", @"@type",
			[NSNumber numberWithLongLong:chatId], @"chat_id",
			[self tgs_filterObject:filter], @"filter",
			[NSNumber numberWithLongLong:fromMessageId], @"from_message_id", nil]
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *days = [result isKindOfClass:NSDictionary.class] ? result[@"days"] : nil;
		if (![days isKindOfClass:NSArray.class]){
			completion([NSArray array], 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *day in days){
			if (![day isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *message = day[@"message"];
			if (![message isKindOfClass:NSDictionary.class])
				continue;
			[out addObject:[NSDictionary dictionaryWithObjectsAndKeys:
					message[@"date"] ?: [NSNumber numberWithInt:0], @"date",
					day[@"total_count"] ?: [NSNumber numberWithInt:0], @"count",
					message[@"id"] ?: [NSNumber numberWithInt:0], @"messageId", nil]];
		}
		completion(out, [result[@"total_count"] integerValue]);
	}];
}

- (void)sparseMessagePositionsInChat:(int64_t)chatId
                              filter:(NSString *)filter
                       fromMessageId:(int64_t)fromMessageId
                               limit:(NSInteger)limit
                          completion:(void (^)(NSArray *, NSInteger))completion {
	[self request:[NSDictionary dictionaryWithObjectsAndKeys:
			@"getChatSparseMessagePositions", @"@type",
			[NSNumber numberWithLongLong:chatId], @"chat_id",
			[self tgs_filterObject:filter], @"filter",
			[NSNumber numberWithLongLong:fromMessageId], @"from_message_id",
			[NSNumber numberWithInteger:limit > 0 ? limit : 100], @"limit",
			[NSNumber numberWithInt:0], @"saved_messages_topic_id", nil]
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *positions = [result isKindOfClass:NSDictionary.class]
				? result[@"positions"] : nil;
		if (![positions isKindOfClass:NSArray.class]){
			completion([NSArray array], 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *p in positions){
			if (![p isKindOfClass:NSDictionary.class])
				continue;
			[out addObject:[NSDictionary dictionaryWithObjectsAndKeys:
					p[@"position"] ?: [NSNumber numberWithInt:0], @"position",
					p[@"message_id"] ?: [NSNumber numberWithInt:0], @"messageId",
					p[@"date"] ?: [NSNumber numberWithInt:0], @"date", nil]];
		}
		completion(out, [result[@"total_count"] integerValue]);
	}];
}

#pragma mark - text helpers

- (void)indexesOfStrings:(NSArray *)strings
           matchingPrefix:(NSString *)query
                    limit:(NSInteger)limit
               completion:(void (^)(NSArray *))completion {
	NSMutableArray *safe = [NSMutableArray array];
	if ([strings isKindOfClass:NSArray.class])
		for (id s in strings)
			[safe addObject:[s isKindOfClass:NSString.class] ? s : @""];

	[self request:[NSDictionary dictionaryWithObjectsAndKeys:
			@"searchStringsByPrefix", @"@type",
			safe, @"strings",
			[self tgs_string:query], @"query",
			[NSNumber numberWithInteger:limit > 0 ? limit : (NSInteger)safe.count], @"limit",
			[NSNumber numberWithBool:NO], @"return_none_for_empty_query", nil]
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *positions = [result isKindOfClass:NSDictionary.class]
				? result[@"positions"] : nil;
		if (![positions isKindOfClass:NSArray.class]){
			completion([NSArray array]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id p in positions)
			if ([p isKindOfClass:NSNumber.class])
				[out addObject:p];
		completion(out);
	}];
}

- (void)positionOfQuote:(NSString *)quote
                 inText:(NSString *)text
             completion:(void (^)(NSInteger))completion {
	NSDictionary *textObject = [NSDictionary dictionaryWithObjectsAndKeys:
			@"formattedText", @"@type",
			[self tgs_string:text], @"text",
			[NSArray array], @"entities", nil];
	NSDictionary *quoteObject = [NSDictionary dictionaryWithObjectsAndKeys:
			@"formattedText", @"@type",
			[self tgs_string:quote], @"text",
			[NSArray array], @"entities", nil];

	[self request:[NSDictionary dictionaryWithObjectsAndKeys:
			@"searchQuote", @"@type",
			textObject, @"text",
			quoteObject, @"quote",
			[NSNumber numberWithInt:0], @"quote_position", nil]
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result isKindOfClass:NSDictionary.class] ||
			![result[@"@type"] isEqualToString:@"foundPosition"]){
			completion(-1);
			return;
		}
		completion([result[@"position"] integerValue]);
	}];
}

@end

// vim:ft=objc

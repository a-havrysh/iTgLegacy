#import "TGClient+ChatList.h"
#import "TGClient+Private.h"

static NSDictionary *TGChatListObject(TGChatListId list){
	if (list == TGChatListArchive)
		return @{@"@type" : @"chatListArchive"};
	if (list == TGChatListMain)
		return @{@"@type" : @"chatListMain"};
	return @{@"@type" : @"chatListFolder", @"chat_folder_id" : @((int)list)};
}

static TGChatListId TGChatListIdFromObject(id object){
	if (![object isKindOfClass:NSDictionary.class])
		return TGChatListMain;
	NSString *type = object[@"@type"];
	if ([type isEqualToString:@"chatListArchive"])
		return TGChatListArchive;
	if ([type isEqualToString:@"chatListFolder"])
		return (TGChatListId)[object[@"chat_folder_id"] integerValue];
	return TGChatListMain;
}

static BOOL TGIsError(NSDictionary *result){
	return ![result isKindOfClass:NSDictionary.class] ||
		   [result[@"@type"] isEqualToString:@"error"];
}

static NSArray *TGNumberArray(id value){
	if (![value isKindOfClass:NSArray.class])
		return @[];
	NSMutableArray *out = [NSMutableArray array];
	for (id item in value){
		if ([item isKindOfClass:NSNumber.class])
			[out addObject:item];
	}
	return out;
}

static NSString *TGPlainText(id formatted){
	if ([formatted isKindOfClass:NSString.class])
		return formatted;
	if ([formatted isKindOfClass:NSDictionary.class]){
		id text = formatted[@"text"];
		if ([text isKindOfClass:NSString.class])
			return text;
		if ([text isKindOfClass:NSDictionary.class])
			return TGPlainText(text);
	}
	return @"";
}

@implementation TGClient (ChatList)

#pragma mark - shared helpers

- (NSArray *)tgcl_rowsForChatIds:(NSArray *)chatIds {
	NSMutableArray *out = [NSMutableArray array];
	for (NSNumber *chatId in TGNumberArray(chatIds)){
		NSDictionary *info = self.chatsById[chatId];
		if (info){
			[out addObject:[info copy]];
		} else {
			[out addObject:@{@"id" : chatId, @"title" : @"", @"unread" : @(0)}];
		}
	}
	return out;
}

- (void)tgcl_chatRowsFrom:(NSDictionary *)request completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *client = weakSelf;
		if (!client || TGIsError(result)){
			completion(@[]);
			return;
		}
		completion([client tgcl_rowsForChatIds:result[@"chat_ids"]]);
	}];
}

- (NSDictionary *)tgcl_folderFromTdFolder:(NSDictionary *)folder id:(NSNumber *)folderId {
	if (![folder isKindOfClass:NSDictionary.class])
		return nil;
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	if (folderId)
		out[@"id"] = folderId;
	out[@"title"] = TGPlainText(folder[@"name"]);
	NSString *icon = @"";
	if ([folder[@"icon"] isKindOfClass:NSDictionary.class] &&
		[folder[@"icon"][@"name"] isKindOfClass:NSString.class])
		icon = folder[@"icon"][@"name"];
	out[@"icon"] = icon;
	out[@"colorId"] = folder[@"color_id"] ?: @(-1);
	out[@"isShareable"] = @([folder[@"is_shareable"] boolValue]);
	out[@"pinnedChatIds"] = TGNumberArray(folder[@"pinned_chat_ids"]);
	out[@"includedChatIds"] = TGNumberArray(folder[@"included_chat_ids"]);
	out[@"excludedChatIds"] = TGNumberArray(folder[@"excluded_chat_ids"]);
	out[@"excludeMuted"] = @([folder[@"exclude_muted"] boolValue]);
	out[@"excludeRead"] = @([folder[@"exclude_read"] boolValue]);
	out[@"excludeArchived"] = @([folder[@"exclude_archived"] boolValue]);
	out[@"includeContacts"] = @([folder[@"include_contacts"] boolValue]);
	out[@"includeNonContacts"] = @([folder[@"include_non_contacts"] boolValue]);
	out[@"includeBots"] = @([folder[@"include_bots"] boolValue]);
	out[@"includeGroups"] = @([folder[@"include_groups"] boolValue]);
	out[@"includeChannels"] = @([folder[@"include_channels"] boolValue]);
	return out;
}

- (NSDictionary *)tgcl_tdFolderFrom:(NSDictionary *)folder {
	if (![folder isKindOfClass:NSDictionary.class])
		folder = @{};
	NSString *title = [folder[@"title"] isKindOfClass:NSString.class] ? folder[@"title"] : @"";
	NSString *icon = [folder[@"icon"] isKindOfClass:NSString.class] ? folder[@"icon"] : @"";
	NSNumber *colorId = [folder[@"colorId"] isKindOfClass:NSNumber.class] ? folder[@"colorId"] : @(-1);
	return @{
		@"@type" : @"chatFolder",
		@"name" : @{@"@type" : @"chatFolderName",
					@"text" : @{@"@type" : @"formattedText",
								@"text" : title,
								@"entities" : @[]},
					@"animate_custom_emoji" : @(NO)},
		@"icon" : @{@"@type" : @"chatFolderIcon", @"name" : icon},
		@"color_id" : colorId,
		@"is_shareable" : @([folder[@"isShareable"] boolValue]),
		@"pinned_chat_ids" : TGNumberArray(folder[@"pinnedChatIds"]),
		@"included_chat_ids" : TGNumberArray(folder[@"includedChatIds"]),
		@"excluded_chat_ids" : TGNumberArray(folder[@"excludedChatIds"]),
		@"exclude_muted" : @([folder[@"excludeMuted"] boolValue]),
		@"exclude_read" : @([folder[@"excludeRead"] boolValue]),
		@"exclude_archived" : @([folder[@"excludeArchived"] boolValue]),
		@"include_contacts" : @([folder[@"includeContacts"] boolValue]),
		@"include_non_contacts" : @([folder[@"includeNonContacts"] boolValue]),
		@"include_bots" : @([folder[@"includeBots"] boolValue]),
		@"include_groups" : @([folder[@"includeGroups"] boolValue]),
		@"include_channels" : @([folder[@"includeChannels"] boolValue]),
	};
}

- (NSString *)tgcl_titleForList:(TGChatListId)list {
	if (list == TGChatListMain)
		return @"All Chats";
	if (list == TGChatListArchive)
		return @"Archived";
	for (NSDictionary *folder in self.folders){
		if (![folder isKindOfClass:NSDictionary.class])
			continue;
		if ([folder[@"id"] integerValue] == list)
			return folder[@"title"] ?: @"";
	}
	return @"";
}

#pragma mark - lists

- (void)chatsInList:(TGChatListId)list
			  limit:(NSInteger)limit
		 completion:(void (^)(NSArray *))completion {
	if (limit <= 0)
		limit = 100;
	[self tgcl_chatRowsFrom:@{@"@type" : @"getChats",
							  @"chat_list" : TGChatListObject(list),
							  @"limit" : @((int)limit)}
				 completion:completion];
}

- (void)loadMoreChatsInList:(TGChatListId)list limit:(NSInteger)limit {
	if (limit <= 0)
		limit = 50;
	[self send:@{@"@type" : @"loadChats",
				 @"chat_list" : TGChatListObject(list),
				 @"limit" : @((int)limit)}];
}

- (void)markListAsRead:(TGChatListId)list {
	[self send:@{@"@type" : @"readChatList",
				 @"chat_list" : TGChatListObject(list)}];
}

- (NSDictionary *)unreadSummaryForList:(TGChatListId)list {
	NSArray *rows = (list == TGChatListArchive) ? self.archivedChats : self.chats;
	NSInteger chats = 0, unmutedChats = 0, messages = 0, unmutedMessages = 0;
	for (NSDictionary *row in rows){
		if (![row isKindOfClass:NSDictionary.class])
			continue;
		NSInteger unread = [row[@"unread"] integerValue];
		BOOL marked = [row[@"markedUnread"] boolValue];
		BOOL muted = [row[@"isMuted"] boolValue];
		if (unread <= 0 && !marked)
			continue;
		chats++;
		messages += unread;
		if (!muted){
			unmutedChats++;
			unmutedMessages += unread;
		}
	}
	return @{@"chats" : @(chats),
			 @"unmutedChats" : @(unmutedChats),
			 @"messages" : @(messages),
			 @"unmutedMessages" : @(unmutedMessages)};
}

- (void)setChat:(int64_t)chatId markedAsUnread:(BOOL)marked {
	[self send:@{@"@type" : @"toggleChatIsMarkedAsUnread",
				 @"chat_id" : @(chatId),
				 @"is_marked_as_unread" : @(marked)}];
}

#pragma mark - pinning

- (void)setChat:(int64_t)chatId pinned:(BOOL)pinned inList:(TGChatListId)list {
	[self send:@{@"@type" : @"toggleChatIsPinned",
				 @"chat_list" : TGChatListObject(list),
				 @"chat_id" : @(chatId),
				 @"is_pinned" : @(pinned)}];
}

- (void)setPinnedChats:(NSArray *)chatIds inList:(TGChatListId)list {
	[self send:@{@"@type" : @"setPinnedChats",
				 @"chat_list" : TGChatListObject(list),
				 @"chat_ids" : TGNumberArray(chatIds)}];
}

#pragma mark - membership of lists

- (void)addChat:(int64_t)chatId toList:(TGChatListId)list completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"addChatToList",
					@"chat_id" : @(chatId),
					@"chat_list" : TGChatListObject(list)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGIsError(result));
	}];
}

- (void)listsToAddChat:(int64_t)chatId completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChatListsToAddChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *client = weakSelf;
		if (!client || TGIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		id lists = result[@"chat_lists"];
		if ([lists isKindOfClass:NSArray.class]){
			for (id entry in lists){
				TGChatListId list = TGChatListIdFromObject(entry);
				[out addObject:@{@"list" : @(list),
								 @"title" : [client tgcl_titleForList:list]}];
			}
		}
		completion(out);
	}];
}

#pragma mark - folders

- (void)folderWithId:(NSInteger)folderId completion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChatFolder", @"chat_folder_id" : @((int)folderId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *client = weakSelf;
		if (!client || TGIsError(result)){
			completion(nil);
			return;
		}
		completion([client tgcl_folderFromTdFolder:result id:@(folderId)]);
	}];
}

- (void)saveFolder:(NSDictionary *)folder completion:(void (^)(NSInteger))completion {
	NSDictionary *td = [self tgcl_tdFolderFrom:folder];
	NSNumber *existing = [folder isKindOfClass:NSDictionary.class] ? folder[@"id"] : nil;
	NSDictionary *request;
	if ([existing isKindOfClass:NSNumber.class] && [existing integerValue] != 0){
		request = @{@"@type" : @"editChatFolder",
					@"chat_folder_id" : @([existing intValue]),
					@"folder" : td};
	} else {
		request = @{@"@type" : @"createChatFolder", @"folder" : td};
	}
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(0);
			return;
		}
		completion([result[@"id"] integerValue]);
	}];
}

- (void)deleteFolder:(NSInteger)folderId leavingChats:(NSArray *)chatIds {
	[self send:@{@"@type" : @"deleteChatFolder",
				 @"chat_folder_id" : @((int)folderId),
				 @"leave_chat_ids" : TGNumberArray(chatIds)}];
}

- (void)chatsToLeaveWhenDeletingFolder:(NSInteger)folderId completion:(void (^)(NSArray *))completion {
	[self tgcl_chatRowsFrom:@{@"@type" : @"getChatFolderChatsToLeave",
							  @"chat_folder_id" : @((int)folderId)}
				 completion:completion];
}

- (void)chatCountForFolder:(NSDictionary *)folder completion:(void (^)(NSInteger))completion {
	[self request:@{@"@type" : @"getChatFolderChatCount",
					@"folder" : [self tgcl_tdFolderFrom:folder]}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion(TGIsError(result) ? 0 : [result[@"count"] integerValue]);
	}];
}

- (void)defaultIconNameForFolder:(NSDictionary *)folder completion:(void (^)(NSString *))completion {
	[self request:@{@"@type" : @"getChatFolderDefaultIconName",
					@"folder" : [self tgcl_tdFolderFrom:folder]}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result) || ![result[@"name"] isKindOfClass:NSString.class]){
			completion(nil);
			return;
		}
		completion(result[@"name"]);
	}];
}

- (NSArray *)folderIconNames {
	return @[@"All", @"Unread", @"Unmuted", @"Bots", @"Channels", @"Groups",
			 @"Private", @"Custom", @"Setup", @"Cat", @"Crown", @"Favorite",
			 @"Flower", @"Game", @"Home", @"Love", @"Mask", @"Party",
			 @"Sport", @"Study", @"Trade", @"Travel", @"Work", @"Airplane",
			 @"Book", @"Light", @"Like", @"Money", @"Note", @"Palette"];
}

- (void)reorderFolders:(NSArray *)folderIds mainListPosition:(NSInteger)position {
	NSMutableArray *ids = [NSMutableArray array];
	for (NSNumber *folderId in TGNumberArray(folderIds))
		[ids addObject:@([folderId intValue])];
	[self send:@{@"@type" : @"reorderChatFolders",
				 @"chat_folder_ids" : ids,
				 @"main_chat_list_position" : @((int)position)}];
}

- (void)recommendedFoldersWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getRecommendedChatFolders"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *client = weakSelf;
		if (!client || TGIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		id entries = result[@"chat_folders"];
		if ([entries isKindOfClass:NSArray.class]){
			for (id entry in entries){
				if (![entry isKindOfClass:NSDictionary.class])
					continue;
				NSDictionary *folder = [client tgcl_folderFromTdFolder:entry[@"folder"] id:nil];
				if (!folder)
					continue;
				NSString *text = [entry[@"description"] isKindOfClass:NSString.class] ?
					entry[@"description"] : @"";
				[out addObject:@{@"title" : folder[@"title"] ?: @"",
								 @"icon" : folder[@"icon"] ?: @"",
								 @"description" : text,
								 @"folder" : folder}];
			}
		}
		completion(out);
	}];
}

#pragma mark - shared folders

- (void)inviteLinksForFolder:(NSInteger)folderId completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getChatFolderInviteLinks",
					@"chat_folder_id" : @((int)folderId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		id links = result[@"invite_links"];
		if ([links isKindOfClass:NSArray.class]){
			for (id link in links){
				if (![link isKindOfClass:NSDictionary.class])
					continue;
				[out addObject:@{@"link" : link[@"invite_link"] ?: @"",
								 @"name" : link[@"name"] ?: @"",
								 @"chatIds" : TGNumberArray(link[@"chat_ids"])}];
			}
		}
		completion(out);
	}];
}

- (void)shareableChatsInFolder:(NSInteger)folderId completion:(void (^)(NSArray *))completion {
	[self tgcl_chatRowsFrom:@{@"@type" : @"getChatsForChatFolderInviteLink",
							  @"chat_folder_id" : @((int)folderId)}
				 completion:completion];
}

- (void)tgcl_inviteLinkRequest:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion {
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(nil);
			return;
		}
		completion(@{@"link" : result[@"invite_link"] ?: @"",
					 @"name" : result[@"name"] ?: @"",
					 @"chatIds" : TGNumberArray(result[@"chat_ids"])});
	}];
}

- (void)createInviteLinkForFolder:(NSInteger)folderId
							 name:(NSString *)name
						  chatIds:(NSArray *)chatIds
					   completion:(void (^)(NSDictionary *))completion {
	[self tgcl_inviteLinkRequest:@{@"@type" : @"createChatFolderInviteLink",
								   @"chat_folder_id" : @((int)folderId),
								   @"name" : name ?: @"",
								   @"chat_ids" : TGNumberArray(chatIds)}
					  completion:completion];
}

- (void)editInviteLink:(NSString *)link
			 forFolder:(NSInteger)folderId
				  name:(NSString *)name
			   chatIds:(NSArray *)chatIds
			completion:(void (^)(NSDictionary *))completion {
	if (![link isKindOfClass:NSString.class] || link.length == 0){
		if (completion)
			completion(nil);
		return;
	}
	[self tgcl_inviteLinkRequest:@{@"@type" : @"editChatFolderInviteLink",
								   @"chat_folder_id" : @((int)folderId),
								   @"invite_link" : link,
								   @"name" : name ?: @"",
								   @"chat_ids" : TGNumberArray(chatIds)}
					  completion:completion];
}

- (void)deleteInviteLink:(NSString *)link forFolder:(NSInteger)folderId {
	if (![link isKindOfClass:NSString.class] || link.length == 0)
		return;
	[self send:@{@"@type" : @"deleteChatFolderInviteLink",
				 @"chat_folder_id" : @((int)folderId),
				 @"invite_link" : link}];
}

- (void)checkFolderInviteLink:(NSString *)link completion:(void (^)(NSDictionary *))completion {
	if (![link isKindOfClass:NSString.class] || link.length == 0){
		if (completion)
			completion(nil);
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"checkChatFolderInviteLink", @"invite_link" : link}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *client = weakSelf;
		if (!client || TGIsError(result)){
			completion(nil);
			return;
		}
		NSDictionary *info = result[@"chat_folder_info"];
		NSString *title = @"";
		NSNumber *folderId = @(0);
		if ([info isKindOfClass:NSDictionary.class]){
			title = TGPlainText(info[@"name"]);
			folderId = info[@"id"] ?: @(0);
		}
		completion(@{@"title" : title,
					 @"folderId" : folderId,
					 @"missingChatIds" : TGNumberArray(result[@"missing_chat_ids"]),
					 @"addedChatIds" : TGNumberArray(result[@"added_chat_ids"])});
	}];
}

- (void)joinFolderByInviteLink:(NSString *)link
					   chatIds:(NSArray *)chatIds
					completion:(void (^)(BOOL))completion {
	if (![link isKindOfClass:NSString.class] || link.length == 0){
		if (completion)
			completion(NO);
		return;
	}
	[self request:@{@"@type" : @"addChatFolderByInviteLink",
					@"invite_link" : link,
					@"chat_ids" : TGNumberArray(chatIds)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGIsError(result));
	}];
}

- (void)newChatsInFolder:(NSInteger)folderId completion:(void (^)(NSArray *))completion {
	[self tgcl_chatRowsFrom:@{@"@type" : @"getChatFolderNewChats",
							  @"chat_folder_id" : @((int)folderId)}
				 completion:completion];
}

- (void)addNewChats:(NSArray *)chatIds toFolder:(NSInteger)folderId {
	[self send:@{@"@type" : @"processChatFolderNewChats",
				 @"chat_folder_id" : @((int)folderId),
				 @"added_chat_ids" : TGNumberArray(chatIds)}];
}

#pragma mark - archive settings

- (void)archiveSettingsWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getArchiveChatListSettings"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGIsError(result)){
			completion(nil);
			return;
		}
		completion(@{@"archiveUnknownSenders" :
						 @([result[@"archive_and_mute_new_chats_from_unknown_users"] boolValue]),
					 @"keepUnmutedArchived" :
						 @([result[@"keep_unmuted_chats_archived"] boolValue]),
					 @"keepFoldersArchived" :
						 @([result[@"keep_chats_from_folders_archived"] boolValue])});
	}];
}

- (void)setArchiveSettings:(NSDictionary *)settings {
	if (![settings isKindOfClass:NSDictionary.class])
		settings = @{};
	[self send:@{@"@type" : @"setArchiveChatListSettings",
				 @"settings" : @{
					 @"@type" : @"archiveChatListSettings",
					 @"archive_and_mute_new_chats_from_unknown_users" :
						 @([settings[@"archiveUnknownSenders"] boolValue]),
					 @"keep_unmuted_chats_archived" :
						 @([settings[@"keepUnmutedArchived"] boolValue]),
					 @"keep_chats_from_folders_archived" :
						 @([settings[@"keepFoldersArchived"] boolValue])}}];
}

#pragma mark - search and recents

- (void)searchChatList:(NSString *)query completion:(void (^)(NSArray *, NSArray *))completion {
	if (![query isKindOfClass:NSString.class])
		query = @"";
	__block NSArray *local = nil;
	__block NSArray *global = nil;
	__block NSInteger done = 0;
	void (^finish)(void) = ^{
		done++;
		if (done == 2 && completion)
			completion(local ?: @[], global ?: @[]);
	};
	[self tgcl_chatRowsFrom:@{@"@type" : @"searchChats",
							  @"query" : query,
							  @"limit" : @(50)}
				 completion:^(NSArray *chats){
		local = chats;
		finish();
	}];
	[self tgcl_chatRowsFrom:@{@"@type" : @"searchPublicChats", @"query" : query}
				 completion:^(NSArray *chats){
		global = chats;
		finish();
	}];
}

- (void)topChatsWithCompletion:(void (^)(NSArray *))completion {
	[self tgcl_chatRowsFrom:@{@"@type" : @"getTopChats",
							  @"category" : @{@"@type" : @"topChatCategoryUsers"},
							  @"limit" : @(20)}
				 completion:completion];
}

- (void)removeTopChat:(int64_t)chatId {
	[self send:@{@"@type" : @"removeTopChat",
				 @"category" : @{@"@type" : @"topChatCategoryUsers"},
				 @"chat_id" : @(chatId)}];
}

- (void)recentlyOpenedChatsWithCompletion:(void (^)(NSArray *))completion {
	[self tgcl_chatRowsFrom:@{@"@type" : @"getRecentlyOpenedChats", @"limit" : @(20)}
				 completion:completion];
}

- (void)addRecentlyFoundChat:(int64_t)chatId {
	[self send:@{@"@type" : @"addRecentlyFoundChat", @"chat_id" : @(chatId)}];
}

- (void)removeRecentlyFoundChat:(int64_t)chatId {
	[self send:@{@"@type" : @"removeRecentlyFoundChat", @"chat_id" : @(chatId)}];
}

- (void)clearRecentlyFoundChats {
	[self send:@{@"@type" : @"clearRecentlyFoundChats"}];
}

- (void)sponsoredChatsForQuery:(NSString *)query completion:(void (^)(NSArray *))completion {
	if (![query isKindOfClass:NSString.class])
		query = @"";
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getSearchSponsoredChats", @"query" : query}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		TGClient *client = weakSelf;
		if (!client || TGIsError(result)){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		id chats = result[@"chats"];
		if ([chats isKindOfClass:NSArray.class]){
			for (id chat in chats){
				if (![chat isKindOfClass:NSDictionary.class])
					continue;
				NSNumber *chatId = chat[@"chat_id"];
				NSDictionary *info = chatId ? client.chatsById[chatId] : nil;
				[out addObject:@{@"uniqueId" : chat[@"unique_id"] ?: @(0),
								 @"id" : chatId ?: @(0),
								 @"title" : info[@"title"] ?: @"",
								 @"sponsorInfo" : chat[@"sponsor_info"] ?: @"",
								 @"additionalInfo" : chat[@"additional_info"] ?: @""}];
			}
		}
		completion(out);
	}];
}

- (void)viewSponsoredChat:(long long)uniqueId {
	[self send:@{@"@type" : @"viewSponsoredChat",
				 @"sponsored_chat_unique_id" : @(uniqueId)}];
}

- (void)openSponsoredChat:(long long)uniqueId {
	[self send:@{@"@type" : @"openSponsoredChat",
				 @"sponsored_chat_unique_id" : @(uniqueId)}];
}

#pragma mark - row rendering

- (void)rowDetailForChat:(int64_t)chatId completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (!completion)
			return;
		if (TGIsError(chat)){
			completion(nil);
			return;
		}
		NSString *draft = @"";
		id draftMessage = chat[@"draft_message"];
		if ([draftMessage isKindOfClass:NSDictionary.class]){
			id content = draftMessage[@"content"];
			if ([content isKindOfClass:NSDictionary.class])
				draft = TGPlainText(content[@"text"]);
		}

		NSString *source = @"";
		NSString *sourceText = @"";
		BOOL pinned = NO;
		id positions = chat[@"positions"];
		if ([positions isKindOfClass:NSArray.class]){
			for (id position in positions){
				if (![position isKindOfClass:NSDictionary.class])
					continue;
				if ([position[@"list"] isKindOfClass:NSDictionary.class] &&
					[position[@"list"][@"@type"] isEqualToString:@"chatListMain"])
					pinned = [position[@"is_pinned"] boolValue];
				id origin = position[@"source"];
				if (![origin isKindOfClass:NSDictionary.class])
					continue;
				NSString *type = origin[@"@type"];
				if ([type isEqualToString:@"chatSourcePublicServiceAnnouncement"]){
					source = @"psa";
					if ([origin[@"text"] isKindOfClass:NSString.class])
						sourceText = origin[@"text"];
				} else if ([type isEqualToString:@"chatSourceMtprotoProxy"]){
					source = @"proxy";
				}
			}
		}

		BOOL muted = NO;
		id settings = chat[@"notification_settings"];
		if ([settings isKindOfClass:NSDictionary.class])
			muted = [settings[@"mute_for"] integerValue] > 0;

		completion(@{@"draft" : draft,
					 @"markedUnread" : @([chat[@"is_marked_as_unread"] boolValue]),
					 @"unread" : chat[@"unread_count"] ?: @(0),
					 @"isPinned" : @(pinned),
					 @"isMuted" : @(muted),
					 @"source" : source,
					 @"sourceText" : sourceText});
	}];
}

@end

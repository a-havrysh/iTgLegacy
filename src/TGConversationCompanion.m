#import "TGConversationCompanion.h"

#import "TGClient.h"
#import "TGClient+Messages.h"
#import "TGMessageModel.h"
#import "TGMediaModel.h"

@interface TGConversationCompanion (){
	int64_t _chatId;
	int64_t _threadId;
	NSMutableArray *_messages;
	NSMutableDictionary *_mediaCache;
	TGConversationState _state;
	NSString *_lastErrorText;
	BOOL _canLoadOlder;
	BOOL _isLoadingOlder;
	BOOL _isLoadingInitial;
	BOOL _watching;
	NSInteger _windowLimit;
	void (^_previousMessageHandler)(int64_t, NSDictionary *, int64_t);
	void (^_previousActionHandler)(int64_t, NSString *);
}
@end

@implementation TGConversationCompanion

@synthesize chatId = _chatId;
@synthesize threadId = _threadId;
@synthesize state = _state;
@synthesize lastErrorText = _lastErrorText;
@synthesize canLoadOlder = _canLoadOlder;
@synthesize isLoadingOlder = _isLoadingOlder;

- (id)initWithChatId:(int64_t)chatId {
	return [self initWithChatId:chatId thread:0];
}

- (id)initWithChatId:(int64_t)chatId thread:(int64_t)threadId {
	self = [super init];
	if (!self)
		return nil;
	_chatId = chatId;
	_threadId = threadId;
	_messages = [[NSMutableArray alloc] init];
	_mediaCache = [[NSMutableDictionary alloc] init];
	_state = TGConversationStateIdle;
	_canLoadOlder = YES;
	_pageSize = 60;
	_marksMessagesRead = YES;
	_windowLimit = 0;
	return self;
}

- (void)dealloc {
	[self stopWatching];
}

#pragma mark - state

- (NSArray *)messages {
	return _messages;
}

- (NSInteger)messageCount {
	return (NSInteger)_messages.count;
}

- (void)setState:(TGConversationState)state error:(NSString *)text {
	_lastErrorText = (state == TGConversationStateFailed) ? [text copy] : nil;
	if (_state == state)
		return;
	_state = state;
	if ([_delegate respondsToSelector:@selector(conversationCompanionDidChangeState:)])
		[_delegate conversationCompanionDidChangeState:self];
}

- (void)settleLoadedState {
	[self setState:(_messages.count ? TGConversationStateLoaded : TGConversationStateEmpty)
			 error:nil];
}

- (void)reportFailure:(NSString *)text {
	if ([_delegate respondsToSelector:@selector(conversationCompanion:didFailWithText:)])
		[_delegate conversationCompanion:self didFailWithText:text];
}

#pragma mark - window

- (NSInteger)pageLimit {
	return _pageSize > 0 ? _pageSize : 60;
}

- (NSArray *)modelsFromDictionaries:(NSArray *)dicts {
	return [TGMessageModel arrayFromDictionaries:dicts];
}

- (TGMessageModel *)messageAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_messages.count)
		return nil;
	return [_messages objectAtIndex:(NSUInteger)index];
}

- (NSInteger)indexOfMessageId:(int64_t)messageId {
	if (messageId == 0)
		return NSNotFound;
	NSUInteger count = _messages.count;
	for (NSUInteger i = 0; i < count; i++){
		TGMessageModel *model = [_messages objectAtIndex:i];
		if (model.messageId == messageId)
			return (NSInteger)i;
	}
	return NSNotFound;
}

- (TGMessageModel *)messageWithId:(int64_t)messageId {
	NSInteger index = [self indexOfMessageId:messageId];
	return index == NSNotFound ? nil : [_messages objectAtIndex:(NSUInteger)index];
}

#pragma mark - loading

- (void)loadInitial {
	if (_isLoadingInitial)
		return;
	_isLoadingInitial = YES;
	if (!_messages.count)
		[self setState:TGConversationStateLoading error:nil];

	NSInteger limit = [self pageLimit];
	__weak TGConversationCompanion *weakSelf = self;
	[[TGClient shared] historyForChat:_chatId thread:_threadId limit:limit
						   completion:^(NSArray *history){
		TGConversationCompanion *me = weakSelf;
		if (!me)
			return;
		[me finishInitialLoad:history limit:limit];
	}];
}

- (void)finishInitialLoad:(NSArray *)history limit:(NSInteger)limit {
	_isLoadingInitial = NO;
	if (![history isKindOfClass:[NSArray class]]){
		[self setState:TGConversationStateFailed error:@"Could not load this conversation."];
		[self reportFailure:@"Could not load this conversation."];
		return;
	}
	_windowLimit = limit;
	_canLoadOlder = ((NSInteger)history.count >= limit);
	[_messages setArray:[self modelsFromDictionaries:history]];
	[self settleLoadedState];
	if ([_delegate respondsToSelector:@selector(conversationCompanionDidReloadAll:)])
		[_delegate conversationCompanionDidReloadAll:self];
	if (_marksMessagesRead)
		[self markLoadedMessagesRead];
}

- (void)loadOlder {
	if (!_canLoadOlder || _isLoadingOlder || _isLoadingInitial)
		return;
	_isLoadingOlder = YES;

	NSInteger held = (NSInteger)_messages.count;
	NSInteger limit = held + [self pageLimit];
	__weak TGConversationCompanion *weakSelf = self;
	[[TGClient shared] historyForChat:_chatId thread:_threadId limit:limit
						   completion:^(NSArray *history){
		TGConversationCompanion *me = weakSelf;
		if (!me)
			return;
		[me finishOlderLoad:history limit:limit held:held];
	}];
}

- (void)finishOlderLoad:(NSArray *)history limit:(NSInteger)limit held:(NSInteger)held {
	_isLoadingOlder = NO;
	if (![history isKindOfClass:[NSArray class]]){
		[self reportFailure:@"Could not load earlier messages."];
		return;
	}
	_windowLimit = limit;
	NSArray *models = [self modelsFromDictionaries:history];
	if ((NSInteger)models.count <= held){
		_canLoadOlder = NO;
		return;
	}

	int64_t oldestHeld = held ? [(TGMessageModel *)[_messages objectAtIndex:0] messageId] : 0;
	NSUInteger cut = models.count;
	if (oldestHeld != 0){
		for (NSUInteger i = 0; i < models.count; i++){
			if ([(TGMessageModel *)[models objectAtIndex:i] messageId] == oldestHeld){
				cut = i;
				break;
			}
		}
	} else {
		cut = 0;
	}
	if (cut == models.count || cut == 0){
		if (oldestHeld == 0){
			[_messages setArray:models];
			_canLoadOlder = ((NSInteger)models.count >= limit);
			[self settleLoadedState];
			if ([_delegate respondsToSelector:@selector(conversationCompanionDidReloadAll:)])
				[_delegate conversationCompanionDidReloadAll:self];
			return;
		}
		[self rebuildWindowWithModels:models limit:limit];
		return;
	}

	NSArray *older = [models subarrayWithRange:NSMakeRange(0, cut)];
	[_messages replaceObjectsInRange:NSMakeRange(0, 0)
			   withObjectsFromArray:older];
	_canLoadOlder = ((NSInteger)models.count >= limit);
	[self settleLoadedState];
	if ([_delegate respondsToSelector:@selector(conversationCompanion:didInsertAtIndexes:)]){
		NSIndexSet *inserted = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, older.count)];
		[_delegate conversationCompanion:self didInsertAtIndexes:inserted];
	}
}

- (void)rebuildWindowWithModels:(NSArray *)models limit:(NSInteger)limit {
	[_messages setArray:models];
	_windowLimit = limit;
	_canLoadOlder = ((NSInteger)models.count >= limit);
	[self settleLoadedState];
	if ([_delegate respondsToSelector:@selector(conversationCompanionDidReloadAll:)])
		[_delegate conversationCompanionDidReloadAll:self];
}

- (void)reload {
	NSInteger limit = _windowLimit > 0 ? _windowLimit : [self pageLimit];
	__weak TGConversationCompanion *weakSelf = self;
	[[TGClient shared] historyForChat:_chatId thread:_threadId limit:limit
						   completion:^(NSArray *history){
		TGConversationCompanion *me = weakSelf;
		if (!me)
			return;
		if (![history isKindOfClass:[NSArray class]]){
			[me reportFailure:@"Could not refresh this conversation."];
			return;
		}
		[me rebuildWindowWithModels:[me modelsFromDictionaries:history] limit:limit];
		if (me.marksMessagesRead)
			[me markLoadedMessagesRead];
	}];
}

#pragma mark - updates

- (void)startWatching {
	if (_watching)
		return;
	_watching = YES;

	TGClient *client = [TGClient shared];
	_previousMessageHandler = [client.onMessage copy];
	_previousActionHandler = [client.onChatAction copy];

	__weak TGConversationCompanion *weakSelf = self;
	void (^chainedMessage)(int64_t, NSDictionary *, int64_t) = _previousMessageHandler;
	void (^chainedAction)(int64_t, NSString *) = _previousActionHandler;

	client.onMessage = ^(int64_t updatedChatId, NSDictionary *message, int64_t deletedId){
		if (chainedMessage)
			chainedMessage(updatedChatId, message, deletedId);
		TGConversationCompanion *me = weakSelf;
		if (!me || updatedChatId != me.chatId)
			return;
		[me applyUpdateWithMessage:message deletedId:deletedId];
	};

	client.onChatAction = ^(int64_t updatedChatId, NSString *action){
		if (chainedAction)
			chainedAction(updatedChatId, action);
		TGConversationCompanion *me = weakSelf;
		if (!me || updatedChatId != me.chatId)
			return;
		if ([me.delegate respondsToSelector:@selector(conversationCompanion:didChangeAction:)])
			[me.delegate conversationCompanion:me didChangeAction:action];
	};
}

- (void)stopWatching {
	if (!_watching)
		return;
	_watching = NO;
	TGClient *client = [TGClient shared];
	client.onMessage = _previousMessageHandler;
	client.onChatAction = _previousActionHandler;
	_previousMessageHandler = nil;
	_previousActionHandler = nil;
}

- (void)applyUpdateWithMessage:(NSDictionary *)message deletedId:(int64_t)deletedId {
	if (!message){
		[self removeMessageIds:@[@(deletedId)]];
		return;
	}
	TGMessageModel *model = [TGMessageModel fromDictionary:message];
	if (!model)
		return;
	[self applyMessageModel:model markRead:_marksMessagesRead];
}

- (void)applyMessageModel:(TGMessageModel *)model markRead:(BOOL)markRead {
	NSInteger existing = [self indexOfMessageId:model.messageId];
	if (existing != NSNotFound){
		[_messages replaceObjectAtIndex:(NSUInteger)existing withObject:model];
		[_mediaCache removeObjectForKey:@(model.messageId)];
		if ([_delegate respondsToSelector:@selector(conversationCompanion:didUpdateAtIndexes:)])
			[_delegate conversationCompanion:self
						  didUpdateAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)existing]];
		return;
	}

	[_messages addObject:model];
	[self settleLoadedState];
	if ([_delegate respondsToSelector:@selector(conversationCompanion:didInsertAtIndexes:)])
		[_delegate conversationCompanion:self
					  didInsertAtIndexes:[NSIndexSet indexSetWithIndex:_messages.count - 1]];
	if (markRead && model.messageId != 0)
		[[TGClient shared] markRead:@[@(model.messageId)] inChat:_chatId];
}

- (void)removeMessageIds:(NSArray *)messageIds {
	NSMutableIndexSet *removed = [NSMutableIndexSet indexSet];
	for (id raw in messageIds){
		if (![raw isKindOfClass:[NSNumber class]])
			continue;
		NSInteger index = [self indexOfMessageId:[raw longLongValue]];
		if (index != NSNotFound)
			[removed addIndex:(NSUInteger)index];
		[_mediaCache removeObjectForKey:raw];
	}
	if (!removed.count)
		return;
	[_messages removeObjectsAtIndexes:removed];
	[self settleLoadedState];
	if ([_delegate respondsToSelector:@selector(conversationCompanion:didRemoveAtIndexes:)])
		[_delegate conversationCompanion:self didRemoveAtIndexes:removed];
}

#pragma mark - media

- (void)mediaForMessageId:(int64_t)messageId completion:(void (^)(TGMediaModel *))completion {
	if (!completion)
		return;
	if (messageId == 0){
		completion(nil);
		return;
	}
	NSNumber *key = @(messageId);
	id cached = [_mediaCache objectForKey:key];
	if (cached){
		completion(cached == [NSNull null] ? nil : cached);
		return;
	}

	__weak TGConversationCompanion *weakSelf = self;
	NSDictionary *request = @{@"@type": @"getMessage",
							  @"chat_id": @(_chatId),
							  @"message_id": @(messageId)};
	[[TGClient shared] request:request completion:^(NSDictionary *result){
		TGMediaModel *media = nil;
		if ([result isKindOfClass:[NSDictionary class]])
			media = [TGMediaModel fromMessageDictionary:result];
		TGConversationCompanion *me = weakSelf;
		if (me)
			[me->_mediaCache setObject:(media ? (id)media : (id)[NSNull null]) forKey:key];
		completion(media);
	}];
}

#pragma mark - acting

- (void)sendText:(NSString *)text {
	[self sendText:text replyToMessageId:0];
}

- (void)sendText:(NSString *)text replyToMessageId:(int64_t)replyToMessageId {
	if (![text isKindOfClass:[NSString class]] || !text.length)
		return;
	__weak TGConversationCompanion *weakSelf = self;
	[[TGClient shared] sendText:text
						 toChat:_chatId
						 thread:_threadId
						replyTo:replyToMessageId
						options:nil
					 completion:^(NSDictionary *message){
		TGConversationCompanion *me = weakSelf;
		if (!me)
			return;
		if (!message){
			[me reportFailure:@"Message not sent."];
			return;
		}
		TGMessageModel *model = [TGMessageModel fromDictionary:message];
		if (model)
			[me applyMessageModel:model markRead:NO];
	}];
}

- (void)resendMessageId:(int64_t)messageId {
	if (messageId == 0)
		return;
	__weak TGConversationCompanion *weakSelf = self;
	[[TGClient shared] resendMessages:@[@(messageId)] inChat:_chatId
						   completion:^(NSArray *messages){
		TGConversationCompanion *me = weakSelf;
		if (!me)
			return;
		if (![messages isKindOfClass:[NSArray class]] || !messages.count){
			[me reportFailure:@"Message could not be sent again."];
			return;
		}
		for (NSDictionary *dict in messages){
			TGMessageModel *model = [TGMessageModel fromDictionary:dict];
			if (model)
				[me applyMessageModel:model markRead:NO];
		}
	}];
}

- (void)deleteMessageIds:(NSArray *)messageIds forEveryone:(BOOL)forEveryone {
	if (![messageIds isKindOfClass:[NSArray class]] || !messageIds.count)
		return;
	NSArray *ids = [messageIds copy];
	__weak TGConversationCompanion *weakSelf = self;
	[[TGClient shared] deleteMessages:ids inChat:_chatId forEveryone:forEveryone
						   completion:^(BOOL ok){
		TGConversationCompanion *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[me reportFailure:@"Could not delete."];
			return;
		}
		[me removeMessageIds:ids];
	}];
}

- (void)markLoadedMessagesRead {
	NSMutableArray *ids = [NSMutableArray array];
	for (TGMessageModel *model in _messages)
		if (model.messageId != 0)
			[ids addObject:@(model.messageId)];
	if (ids.count)
		[[TGClient shared] markRead:ids inChat:_chatId];
}

- (void)sendAction:(NSString *)action {
	if (![action isKindOfClass:[NSString class]] || !action.length)
		return;
	[[TGClient shared] sendChatAction:action toChat:_chatId thread:_threadId];
}

#pragma mark - memory

- (void)didReceiveMemoryWarning {
	[_mediaCache removeAllObjects];

	NSInteger keep = [self pageLimit];
	if ((NSInteger)_messages.count <= keep)
		return;
	NSRange tail = NSMakeRange(_messages.count - (NSUInteger)keep, (NSUInteger)keep);
	[_messages setArray:[_messages subarrayWithRange:tail]];
	_windowLimit = keep;
	_canLoadOlder = YES;
	if ([_delegate respondsToSelector:@selector(conversationCompanionDidReloadAll:)])
		[_delegate conversationCompanionDidReloadAll:self];
}

@end

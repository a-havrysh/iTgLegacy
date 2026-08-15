#import "TGStoriesCompanion.h"

#import <UIKit/UIKit.h>

#import "TGClient.h"
#import "TGClient+Stories.h"
#import "TGStoryModel.h"

static const NSInteger TGStoriesPosterScanLimit = 25;

static NSString *TGStoriesStringValue(NSDictionary *dict, NSString *key)
{
	id value = [dict objectForKey:key];
	return [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
}

static NSInteger TGStoriesIntegerValue(NSDictionary *dict, NSString *key)
{
	id value = [dict objectForKey:key];
	return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

static int64_t TGStoriesLongValue(NSDictionary *dict, NSString *key)
{
	id value = [dict objectForKey:key];
	return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0;
}

static BOOL TGStoriesBoolValue(NSDictionary *dict, NSString *key)
{
	id value = [dict objectForKey:key];
	return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

@interface TGStoryPosterModel ()

- (instancetype)initWithChatId:(int64_t)chatId
						 title:(NSString *)title
					  storyIds:(NSArray *)storyIds
						 order:(int64_t)order
				maxReadStoryId:(NSInteger)maxReadStoryId;

@end

@implementation TGStoryPosterModel
{
	int64_t _chatId;
	NSString *_title;
	NSArray *_storyIds;
	int64_t _order;
	NSInteger _maxReadStoryId;
}

- (instancetype)initWithChatId:(int64_t)chatId
						 title:(NSString *)title
					  storyIds:(NSArray *)storyIds
						 order:(int64_t)order
				maxReadStoryId:(NSInteger)maxReadStoryId
{
	self = [super init];
	if (self != nil)
	{
		_chatId = chatId;
		_title = [title length] > 0 ? [title copy] : @"Story";
		_storyIds = [storyIds isKindOfClass:[NSArray class]] ? [storyIds copy] : [NSArray array];
		_order = order;
		_maxReadStoryId = maxReadStoryId;
	}
	return self;
}

- (int64_t)chatId { return _chatId; }
- (NSString *)title { return _title; }
- (NSArray *)storyIds { return _storyIds; }
- (int64_t)order { return _order; }
- (NSInteger)maxReadStoryId { return _maxReadStoryId; }

- (NSInteger)firstUnreadIndex
{
	NSInteger start = 0;
	for (NSUInteger i = 0; i < _storyIds.count; i++)
	{
		NSNumber *key = [_storyIds objectAtIndex:i];
		if ([key integerValue] <= _maxReadStoryId)
			start = (NSInteger)i + 1;
	}
	if (start >= (NSInteger)_storyIds.count)
		start = 0;
	return start;
}

@end

@implementation TGStoriesCompanion
{
	int64_t _chatId;
	NSString *_posterName;
	NSArray *_storyIds;
	NSMutableDictionary *_stories;
	NSMutableSet *_seen;
	NSMutableSet *_pending;

	NSInteger _index;
	NSInteger _openStoryId;

	TGStoriesState _state;
	NSString *_failureMessage;

	NSMutableArray *_posters;
	NSInteger _posterIndex;
	NSInteger _maxReadStoryId;

	BOOL _started;
	BOOL _closed;
	BOOL _postersRequested;
}

@synthesize delegate = _delegate;

- (instancetype)initWithChatId:(int64_t)chatId
					  storyIds:(NSArray *)storyIds
					startIndex:(NSInteger)startIndex
{
	self = [super init];
	if (self != nil)
	{
		_chatId = chatId;
		_storyIds = [storyIds isKindOfClass:[NSArray class]] ? [storyIds copy] : [NSArray array];
		_index = _storyIds.count == 0 ? -1 : startIndex;
		if (_index >= (NSInteger)_storyIds.count || _index < 0)
			_index = _storyIds.count == 0 ? -1 : 0;
		_stories = [[NSMutableDictionary alloc] init];
		_seen = [[NSMutableSet alloc] init];
		_pending = [[NSMutableSet alloc] init];
		_posters = [[NSMutableArray alloc] init];
		_posterIndex = 0;
		_state = TGStoriesStateIdle;

		[[NSNotificationCenter defaultCenter]
				addObserver:self
				   selector:@selector(handleMemoryWarning:)
					   name:UIApplicationDidReceiveMemoryWarningNotification
					 object:nil];
	}
	return self;
}

- (instancetype)initWithChatId:(int64_t)chatId
{
	return [self initWithChatId:chatId storyIds:nil startIndex:0];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self close];
}

#pragma mark - state

- (TGStoriesState)state { return _state; }
- (NSString *)failureMessage { return _failureMessage; }
- (int64_t)chatId { return _chatId; }
- (NSInteger)currentIndex { return _index; }
- (NSInteger)count { return (NSInteger)_storyIds.count; }
- (NSArray *)storyIds { return _storyIds; }
- (NSArray *)posters { return _posters; }
- (NSInteger)posterIndex { return _posterIndex; }

- (NSString *)posterName
{
	if ([_posterName length] > 0)
		return _posterName;

	NSArray *chats = [[TGClient shared] chats];
	if ([chats isKindOfClass:[NSArray class]])
	{
		for (NSDictionary *chat in chats)
		{
			if (![chat isKindOfClass:[NSDictionary class]])
				continue;
			if (TGStoriesLongValue(chat, @"id") != _chatId)
				continue;
			NSString *title = TGStoriesStringValue(chat, @"title");
			if (title.length > 0)
			{
				_posterName = [title copy];
				return _posterName;
			}
		}
	}
	return @"Story";
}

- (BOOL)isOwnStory
{
	NSDictionary *me = [[TGClient shared] me];
	if (![me isKindOfClass:[NSDictionary class]])
		return NO;
	return TGStoriesLongValue(me, @"id") == _chatId;
}

- (void)setState:(TGStoriesState)state message:(NSString *)message
{
	if (_state == state && (message == nil) == (_failureMessage == nil))
		return;
	_state = state;
	_failureMessage = [message copy];
	if ([_delegate respondsToSelector:@selector(storiesCompanion:didChangeState:)])
		[_delegate storiesCompanion:self didChangeState:_state];
}

#pragma mark - lifecycle

- (void)start
{
	if (_started || _closed)
		return;
	_started = YES;

	if (_storyIds.count == 0)
	{
		[self setState:TGStoriesStateLoading message:nil];
		[self loadActiveListThenOpen];
	}
	else
	{
		[self setState:TGStoriesStateLoaded message:nil];
		[self openCurrent];
		[self prefetchAround];
	}

	[self discoverPosters];
}

- (void)close
{
	_closed = YES;
	[self closeOpenStory];
	[_pending removeAllObjects];
}

- (void)closeOpenStory
{
	if (_openStoryId != 0)
	{
		[[TGClient shared] closeStory:_openStoryId inChat:_chatId];
		_openStoryId = 0;
	}
}

- (void)loadActiveListThenOpen
{
	int64_t chatId = _chatId;
	__weak TGStoriesCompanion *weakSelf = self;
	[[TGClient shared] activeStoriesForChat:chatId completion:^(NSDictionary *active)
	{
		TGStoriesCompanion *strongSelf = weakSelf;
		if (strongSelf == nil || strongSelf->_closed || strongSelf->_chatId != chatId)
			return;

		TGStoryPosterModel *poster = [strongSelf posterFromActive:active
														   chatId:chatId
															title:nil
												  allowingArchived:YES];
		if (poster == nil)
		{
			[strongSelf setState:TGStoriesStateEmpty message:nil];
			return;
		}

		[strongSelf adoptPoster:poster atIndex:[poster firstUnreadIndex] reload:YES];
	}];
}

- (TGStoryPosterModel *)posterFromActive:(NSDictionary *)active
								  chatId:(int64_t)chatId
								   title:(NSString *)title
						allowingArchived:(BOOL)allowingArchived
{
	if (![active isKindOfClass:[NSDictionary class]])
		return nil;
	if (!allowingArchived && TGStoriesBoolValue(active, @"archived"))
		return nil;

	NSArray *stories = [active objectForKey:@"stories"];
	if (![stories isKindOfClass:[NSArray class]] || stories.count == 0)
		return nil;

	NSMutableArray *ids = [[NSMutableArray alloc] init];
	for (NSDictionary *story in stories)
	{
		if (![story isKindOfClass:[NSDictionary class]])
			continue;
		NSInteger storyId = TGStoriesIntegerValue(story, @"id");
		if (storyId != 0)
			[ids addObject:[NSNumber numberWithInteger:storyId]];
	}
	if (ids.count == 0)
		return nil;

	return [[TGStoryPosterModel alloc]
			initWithChatId:chatId
					 title:(title.length > 0 ? title : TGStoriesStringValue(active, @"title"))
				  storyIds:ids
					 order:TGStoriesLongValue(active, @"order")
			maxReadStoryId:TGStoriesIntegerValue(active, @"maxReadStoryId")];
}

- (void)adoptPoster:(TGStoryPosterModel *)poster
			atIndex:(NSInteger)index
			 reload:(BOOL)reload
{
	[self closeOpenStory];

	_chatId = poster.chatId;
	_posterName = [poster.title isEqualToString:@"Story"] ? nil : [poster.title copy];
	_storyIds = [poster.storyIds copy];
	_maxReadStoryId = poster.maxReadStoryId;

	[_stories removeAllObjects];
	[_pending removeAllObjects];
	[_seen removeAllObjects];
	for (NSNumber *key in _storyIds)
	{
		if ([key integerValue] <= _maxReadStoryId)
			[_seen addObject:key];
	}

	_index = _storyIds.count == 0 ? -1 : index;
	if (_index >= (NSInteger)_storyIds.count || _index < 0)
		_index = _storyIds.count == 0 ? -1 : 0;

	[self setState:(_storyIds.count == 0 ? TGStoriesStateEmpty : TGStoriesStateLoaded)
		   message:nil];

	if (reload && [_delegate respondsToSelector:@selector(storiesCompanionDidReloadList:)])
		[_delegate storiesCompanionDidReloadList:self];

	[self openCurrent];
	[self prefetchAround];
}

#pragma mark - list access

- (NSInteger)storyIdAtIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)_storyIds.count)
		return 0;
	return [[_storyIds objectAtIndex:(NSUInteger)index] integerValue];
}

- (NSNumber *)keyAtIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)_storyIds.count)
		return nil;
	return [_storyIds objectAtIndex:(NSUInteger)index];
}

- (TGStoryModel *)storyAtIndex:(NSInteger)index
{
	NSNumber *key = [self keyAtIndex:index];
	if (key == nil)
		return nil;
	TGStoryModel *model = [_stories objectForKey:key];
	if (model == nil)
		[self fetchStoryAtIndex:index];
	return model;
}

- (TGStoryModel *)currentStory
{
	return [self storyAtIndex:_index];
}

- (void)prefetchStoryAtIndex:(NSInteger)index
{
	[self fetchStoryAtIndex:index];
}

- (void)prefetchAround
{
	[self fetchStoryAtIndex:_index];
	[self fetchStoryAtIndex:_index + 1];
}

- (void)fetchStoryAtIndex:(NSInteger)index
{
	if (_closed)
		return;
	NSNumber *key = [self keyAtIndex:index];
	if (key == nil)
		return;
	if ([_stories objectForKey:key] != nil || [_pending containsObject:key])
		return;

	[_pending addObject:key];

	int64_t chatId = _chatId;
	__weak TGStoriesCompanion *weakSelf = self;
	[[TGClient shared] storyWithId:[key integerValue]
							inChat:chatId
						completion:^(NSDictionary *story)
	{
		TGStoriesCompanion *strongSelf = weakSelf;
		if (strongSelf == nil || strongSelf->_closed || strongSelf->_chatId != chatId)
			return;
		[strongSelf->_pending removeObject:key];

		TGStoryModel *model = [TGStoryModel fromDictionary:story];
		if (model == nil)
		{
			if (strongSelf->_state == TGStoriesStateLoading)
				[strongSelf setState:TGStoriesStateFailed
							 message:@"This story is no longer available."];
			return;
		}

		[strongSelf->_stories setObject:model forKey:key];
		if (strongSelf->_state != TGStoriesStateLoaded)
			[strongSelf setState:TGStoriesStateLoaded message:nil];

		NSInteger at = (NSInteger)[strongSelf->_storyIds indexOfObject:key];
		if (at == (NSInteger)NSNotFound)
			return;
		if ([strongSelf->_delegate
				respondsToSelector:@selector(storiesCompanion:didLoadStoryAtIndex:)])
		{
			[strongSelf->_delegate storiesCompanion:strongSelf didLoadStoryAtIndex:at];
		}
	}];
}

#pragma mark - position

- (void)openCurrent
{
	NSNumber *key = [self keyAtIndex:_index];
	if (key == nil || _closed)
		return;

	_openStoryId = [key integerValue];
	[[TGClient shared] openStory:_openStoryId inChat:_chatId];
	[self markSeenKeys:[NSArray arrayWithObject:key]];
}

- (void)moveToIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)_storyIds.count)
		return;
	if (index == _index)
	{
		NSNumber *key = [self keyAtIndex:index];
		if (key != nil)
			[self markSeenKeys:[NSArray arrayWithObject:key]];
		return;
	}

	[self closeOpenStory];
	_index = index;

	if ([_delegate respondsToSelector:@selector(storiesCompanion:didMoveToIndex:)])
		[_delegate storiesCompanion:self didMoveToIndex:_index];

	[self openCurrent];
	[self prefetchAround];
}

- (void)advance
{
	if (_index + 1 < (NSInteger)_storyIds.count)
	{
		[self moveToIndex:_index + 1];
		return;
	}
	[self movePosterBy:1];
}

- (void)retreat
{
	if (_index > 0)
	{
		[self moveToIndex:_index - 1];
		return;
	}
	[self movePosterBy:-1];
}

#pragma mark - seen state

- (BOOL)isSeenAtIndex:(NSInteger)index
{
	NSNumber *key = [self keyAtIndex:index];
	return key != nil && [_seen containsObject:key];
}

- (NSArray *)unreadStoryIds
{
	NSMutableArray *unread = [[NSMutableArray alloc] init];
	for (NSNumber *key in _storyIds)
	{
		if (![_seen containsObject:key])
			[unread addObject:key];
	}
	return unread;
}

- (void)markSeenKeys:(NSArray *)keys
{
	NSMutableArray *changed = [[NSMutableArray alloc] init];
	for (NSNumber *key in keys)
	{
		if ([_seen containsObject:key])
			continue;
		[_seen addObject:key];
		NSUInteger at = [_storyIds indexOfObject:key];
		if (at != NSNotFound)
			[changed addObject:[NSNumber numberWithInteger:(NSInteger)at]];
	}
	if (changed.count == 0)
		return;
	if ([_delegate respondsToSelector:@selector(storiesCompanion:didMarkSeenAtIndexes:)])
		[_delegate storiesCompanion:self didMarkSeenAtIndexes:changed];
}

- (void)markRemainingRead
{
	NSArray *unread = [self unreadStoryIds];
	if (unread.count == 0)
		return;
	for (NSNumber *key in unread)
		[[TGClient shared] markStoryRead:[key integerValue] inChat:_chatId];
	[self markSeenKeys:unread];
}

#pragma mark - poster ring

- (void)discoverPosters
{
	if (_postersRequested)
		return;
	_postersRequested = YES;

	[_posters removeObjectsInRange:NSMakeRange(0, _posters.count)];
	[_posters addObject:[[TGStoryPosterModel alloc]
			initWithChatId:_chatId
					 title:[self posterName]
				  storyIds:_storyIds
					 order:0
			maxReadStoryId:_maxReadStoryId]];
	_posterIndex = 0;

	NSArray *chats = [[TGClient shared] chats];
	if (![chats isKindOfClass:[NSArray class]] || chats.count == 0)
		return;
	if ((NSInteger)chats.count > TGStoriesPosterScanLimit)
		chats = [chats subarrayWithRange:NSMakeRange(0, (NSUInteger)TGStoriesPosterScanLimit)];

	NSMutableArray *found = [[NSMutableArray alloc] init];
	__block NSInteger pending = 0;
	__weak TGStoriesCompanion *weakSelf = self;

	for (NSDictionary *chat in chats)
	{
		if (![chat isKindOfClass:[NSDictionary class]])
			continue;
		int64_t chatId = TGStoriesLongValue(chat, @"id");
		if (chatId == 0 || chatId == _chatId)
			continue;

		NSString *title = TGStoriesStringValue(chat, @"title");
		pending++;
		[[TGClient shared] activeStoriesForChat:chatId completion:^(NSDictionary *active)
		{
			TGStoriesCompanion *strongSelf = weakSelf;
			pending--;
			if (strongSelf == nil || strongSelf->_closed)
				return;

			TGStoryPosterModel *poster = [strongSelf posterFromActive:active
															   chatId:chatId
																title:title
													 allowingArchived:NO];
			if (poster != nil)
				[found addObject:poster];

			if (pending > 0)
				return;
			[strongSelf appendDiscoveredPosters:found];
		}];
	}
}

- (void)appendDiscoveredPosters:(NSMutableArray *)found
{
	[found sortUsingComparator:^NSComparisonResult(TGStoryPosterModel *a, TGStoryPosterModel *b)
	{
		if (a.order == b.order)
			return NSOrderedSame;
		return a.order > b.order ? NSOrderedAscending : NSOrderedDescending;
	}];
	[_posters addObjectsFromArray:found];

	if ([_delegate respondsToSelector:@selector(storiesCompanionDidChangePosters:)])
		[_delegate storiesCompanionDidChangePosters:self];
}

- (void)movePosterBy:(NSInteger)delta
{
	NSInteger target = _posterIndex + delta;
	if (target < 0 || target >= (NSInteger)_posters.count)
	{
		if (delta > 0 &&
			[_delegate respondsToSelector:@selector(storiesCompanionWantsDismissal:)])
		{
			[_delegate storiesCompanionWantsDismissal:self];
		}
		return;
	}

	TGStoryPosterModel *poster = [_posters objectAtIndex:(NSUInteger)target];
	if (poster.storyIds.count == 0)
		return;

	_posterIndex = target;
	NSInteger index = (delta > 0) ? 0 : (NSInteger)poster.storyIds.count - 1;
	[self adoptPoster:poster atIndex:index reload:YES];
}

#pragma mark - memory

- (void)handleMemoryWarning:(NSNotification *)notification
{
	[self purgeCache];
}

- (void)purgeCache
{
	NSNumber *key = [self keyAtIndex:_index];
	TGStoryModel *keep = key != nil ? [_stories objectForKey:key] : nil;
	[_stories removeAllObjects];
	if (keep != nil && key != nil)
		[_stories setObject:keep forKey:key];
}

@end

// vim:ft=objc

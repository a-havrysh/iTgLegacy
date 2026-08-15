/**
 * TGStoriesCompanion - owns the data behind the story viewer.
 *
 * The viewer screen (TGStoriesViewController) shows one poster's stories at a
 * time, pages through them, and can step sideways to the next poster whose
 * stories are unread. All three of those are data problems, and they live
 * here: the poster ring, the story list of the current poster, the position
 * inside that list, which stories have been seen, and the open/close pair
 * TDLib needs to keep the unread ring honest.
 *
 * The screen never calls TGClient for any of this and never sees a
 * dictionary. It asks the companion for a TGStoryModel at an index, and the
 * companion tells it - through the delegate - exactly what changed.
 *
 * One instance per viewer instance. Not a singleton. The screen owns it and
 * must call -close before it goes away, so the last open story is closed.
 */
#import <Foundation/Foundation.h>

@class TGStoryModel;
@class TGStoriesCompanion;

/// What the companion currently has for the poster it is showing.
typedef enum {
	/// Nothing asked for yet.
	TGStoriesStateIdle = 0,
	/// A list or a story fetch is in flight and there is nothing to show yet.
	TGStoriesStateLoading,
	/// At least one story is available.
	TGStoriesStateLoaded,
	/// The poster has no active stories. Not an error.
	TGStoriesStateEmpty,
	/// The fetch came back with nothing usable. See -failureMessage.
	TGStoriesStateFailed
} TGStoriesState;

/**
 * One poster in the sideways ring.
 *
 * Immutable, and deliberately tiny: the ring can hold dozens of these and the
 * viewer only ever needs a name to put in the title bar and a count for the
 * strip.
 */
@interface TGStoryPosterModel : NSObject

/// Chat the stories were posted as.
@property (nonatomic, readonly) int64_t chatId;
/// Display name for the title bar. Never nil; "Story" when unknown.
@property (nonatomic, readonly, copy) NSString *title;
/// NSNumber story ids, oldest first - the order the viewer pages through.
@property (nonatomic, readonly, copy) NSArray *storyIds;
/// Tray sort order from TDLib. Higher sorts first.
@property (nonatomic, readonly) int64_t order;
/// Highest story id the server considers read. 0 when none are.
@property (nonatomic, readonly) NSInteger maxReadStoryId;
/// Index the viewer should open on: the first story after `maxReadStoryId`,
/// or 0 when everything has already been read.
@property (nonatomic, readonly) NSInteger firstUnreadIndex;

@end

/**
 * How the companion reports change.
 *
 * Every method is optional and every one is called on the main thread. The
 * companion prefers to say what changed: only -storiesCompanionDidReloadList:
 * asks for a full rebuild, and it is only sent when the poster changes.
 */
@protocol TGStoriesCompanionDelegate <NSObject>

@optional

/// The state moved. Drive the loading spinner, the empty label and the error
/// label from this and nothing else.
- (void)storiesCompanion:(TGStoriesCompanion *)companion
		  didChangeState:(TGStoriesState)state;

/// The whole story list was replaced - the companion switched poster, or the
/// first list arrived. Rebuild pages and read -currentIndex for the position.
- (void)storiesCompanionDidReloadList:(TGStoriesCompanion *)companion;

/// The detail of one story finished loading and -storyAtIndex: now answers
/// with a model where it previously answered nil. Refresh that page only.
- (void)storiesCompanion:(TGStoriesCompanion *)companion
	 didLoadStoryAtIndex:(NSInteger)index;

/// The current position moved within the same list. The strip and the chrome
/// need updating; the pages do not.
- (void)storiesCompanion:(TGStoriesCompanion *)companion
		  didMoveToIndex:(NSInteger)index;

/// The seen set grew. `indexes` is an NSArray of NSNumber indexes into the
/// current list, so the strip can fill just those segments.
- (void)storiesCompanion:(TGStoriesCompanion *)companion
	   didMarkSeenAtIndexes:(NSArray *)indexes;

/// The poster ring finished being discovered, or grew. The screen only needs
/// this to decide whether a sideways swipe is possible.
- (void)storiesCompanionDidChangePosters:(TGStoriesCompanion *)companion;

/// There is no poster after the current one, so a forward swipe should close
/// the viewer instead of moving.
- (void)storiesCompanionWantsDismissal:(TGStoriesCompanion *)companion;

@end

@interface TGStoriesCompanion : NSObject

/// Not retained. Clear it before releasing the screen.
@property (nonatomic, weak) id<TGStoriesCompanionDelegate> delegate;

#pragma mark - lifecycle

/// Starts on a poster whose story ids the caller already has - the tray
/// already fetched them, so do not fetch them twice. `storyIds` is NSNumber
/// ids oldest first; pass nil to have the companion load them itself.
- (instancetype)initWithChatId:(int64_t)chatId
					  storyIds:(NSArray *)storyIds
					startIndex:(NSInteger)startIndex;

/// Starts with only a chat, and loads its active story list. The opening
/// index becomes the first unread story.
- (instancetype)initWithChatId:(int64_t)chatId;

/// Begins work: loads the list if it was not supplied, opens the story at the
/// start index, and starts discovering the poster ring. Safe to call twice.
- (void)start;

/// Closes whatever story is open and stops everything in flight. The screen
/// must call this from -viewWillDisappear: or -dealloc.
- (void)close;

#pragma mark - state

@property (nonatomic, readonly) TGStoriesState state;
/// A ready-to-show sentence when `state` is TGStoriesStateFailed; nil
/// otherwise.
@property (nonatomic, readonly, copy) NSString *failureMessage;

#pragma mark - the current poster

/// Chat the current stories belong to.
@property (nonatomic, readonly) int64_t chatId;
/// Title-bar name for the current poster. Never nil.
@property (nonatomic, readonly, copy) NSString *posterName;
/// YES when the stories on screen are the logged-in user's own, which is what
/// gates the viewer list, delete and edit actions.
@property (nonatomic, readonly) BOOL isOwnStory;

#pragma mark - the list

/// Number of stories in the current poster's list.
@property (nonatomic, readonly) NSInteger count;
/// NSNumber story ids of the current list, oldest first. Never nil.
@property (nonatomic, readonly, copy) NSArray *storyIds;

/// The story id at `index`, or 0 when out of range. Always available, even
/// before the detail has loaded, because the list arrives as ids first.
- (NSInteger)storyIdAtIndex:(NSInteger)index;

/// The loaded story at `index`, or nil when it has not arrived yet. Asking
/// for a nil one schedules its fetch, so a screen may simply ask on layout.
- (TGStoryModel *)storyAtIndex:(NSInteger)index;

/// The story at the current position, or nil.
- (TGStoryModel *)currentStory;

/// Warms the detail of `index` without needing its value, for the page about
/// to scroll in.
- (void)prefetchStoryAtIndex:(NSInteger)index;

#pragma mark - position

/// Index of the story on screen. -1 when the list is empty.
@property (nonatomic, readonly) NSInteger currentIndex;

/// Moves to `index`, closing the previously open story and opening the new
/// one. Out-of-range values are ignored.
- (void)moveToIndex:(NSInteger)index;

/// Steps one story forward. When there is no next story, steps to the next
/// poster, and when there is no next poster either, asks for dismissal.
- (void)advance;

/// Steps one story back. At the start of a list, steps to the previous poster
/// and lands on its last story. At the very start, does nothing.
- (void)retreat;

#pragma mark - seen state

/// YES when the story at `index` has been shown in this session or was
/// already read on the server.
- (BOOL)isSeenAtIndex:(NSInteger)index;

/// Story ids in the current list that are still unread. Never nil.
- (NSArray *)unreadStoryIds;

/// Marks every remaining story of the current poster read without showing
/// them, which is the "mark all read" action.
- (void)markRemainingRead;

#pragma mark - the poster ring

/// TGStoryPosterModel objects, current poster first, then unread posters in
/// tray order. Never nil.
@property (nonatomic, readonly, copy) NSArray *posters;
/// Position of the current poster inside `posters`.
@property (nonatomic, readonly) NSInteger posterIndex;

/// Switches poster by `delta` (+1 next, -1 previous). Sends
/// -storiesCompanionDidReloadList: on success, or
/// -storiesCompanionWantsDismissal: when moving forward past the last poster.
- (void)movePosterBy:(NSInteger)delta;

#pragma mark - memory

/// Drops every loaded story except the one on screen. The companion also does
/// this by itself on a UIApplicationDidReceiveMemoryWarningNotification.
- (void)purgeCache;

@end

// vim:ft=objc

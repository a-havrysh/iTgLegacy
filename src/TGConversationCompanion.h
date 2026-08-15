//
// TGConversationCompanion - owns the data of one conversation screen.
//
// The screen keeps one of these, hands it a chat id, and reads TGMessageModel
// objects out of it. It never calls TGClient for history, sending, updates or
// read state again: everything the conversation needs off the wire happens
// here, once, behind typed accessors.
//
// One instance per screen instance. Not a singleton, not shared between two
// chats: the window it holds belongs to the chat it was created with.
//
#import <Foundation/Foundation.h>

@class TGMessageModel;
@class TGMediaModel;
@class TGConversationCompanion;

/// What the screen must be showing right now. A screen switches on this rather
/// than guessing from an empty array, because "nothing yet" and "nothing at
/// all" want different things on screen.
typedef enum {
	/// Created, nothing asked for yet.
	TGConversationStateIdle = 0,
	/// The first page is in flight; show the spinner, not the empty label.
	TGConversationStateLoading,
	/// There are messages to draw.
	TGConversationStateLoaded,
	/// The load finished and the conversation really is empty.
	TGConversationStateEmpty,
	/// The load failed. -lastErrorText says what to put on screen.
	TGConversationStateFailed
} TGConversationState;

/// How the companion changed its message array. Every callback below is
/// delivered on the main queue, after the array has already changed, so the
/// screen can apply the indexes to its table without re-reading anything.
@protocol TGConversationCompanionDelegate <NSObject>

@optional

/// The whole window was replaced and index-level updates were not possible.
/// The only callback that means reloadData.
- (void)conversationCompanionDidReloadAll:(TGConversationCompanion *)companion;

/// Rows appeared at these indexes: a page of older history at the top, or one
/// arrived message at the bottom.
- (void)conversationCompanion:(TGConversationCompanion *)companion
	   didInsertAtIndexes:(NSIndexSet *)indexes;

/// Rows already on screen changed in place - an edit, a reaction, a send state
/// settling from pending to sent.
- (void)conversationCompanion:(TGConversationCompanion *)companion
	   didUpdateAtIndexes:(NSIndexSet *)indexes;

/// Rows went away. Indexes are into the array as it was before the removal.
- (void)conversationCompanion:(TGConversationCompanion *)companion
	   didRemoveAtIndexes:(NSIndexSet *)indexes;

/// -state changed. Loading spinners and empty labels hang off this.
- (void)conversationCompanionDidChangeState:(TGConversationCompanion *)companion;

/// Somebody in this chat started or stopped doing something. `action` is a
/// short phrase for the subtitle, nil when they stopped.
- (void)conversationCompanion:(TGConversationCompanion *)companion
	     didChangeAction:(NSString *)action;

/// A request the user started failed. `text` is already fit to show.
- (void)conversationCompanion:(TGConversationCompanion *)companion
		didFailWithText:(NSString *)text;

@end


@interface TGConversationCompanion : NSObject

/// The conversation this companion owns. Fixed for its lifetime.
@property (nonatomic, readonly) int64_t chatId;
/// Forum topic or comment thread, 0 for a plain chat.
@property (nonatomic, readonly) int64_t threadId;

/// Not retained. The screen owns the companion, never the other way round.
@property (nonatomic, assign) id<TGConversationCompanionDelegate> delegate;

/// Oldest first, which is the order the table draws top to bottom. Array of
/// TGMessageModel, never nil, never dictionaries.
@property (nonatomic, readonly) NSArray *messages;
@property (nonatomic, readonly) NSInteger messageCount;

@property (nonatomic, readonly) TGConversationState state;
/// Optional. Set only while -state is Failed.
@property (nonatomic, readonly, copy) NSString *lastErrorText;

/// NO once the top of the conversation has been reached, so the screen stops
/// asking when the user drags past the first bubble.
@property (nonatomic, readonly) BOOL canLoadOlder;
/// A page is already in flight; a second -loadOlder is ignored while it is.
@property (nonatomic, readonly) BOOL isLoadingOlder;

/// Messages this companion asks for per page. Defaults to 60, which is what
/// the screen used to hardcode. Set before -loadInitial to change the first
/// page too.
@property (nonatomic, assign) NSInteger pageSize;

/// Mark arrived and loaded messages read as they are handed over. Defaults to
/// YES; a screen showing search results inside the chat turns it off.
@property (nonatomic, assign) BOOL marksMessagesRead;

#pragma mark - lifecycle

- (id)initWithChatId:(int64_t)chatId;
- (id)initWithChatId:(int64_t)chatId thread:(int64_t)threadId;

/// Start listening for new, edited and deleted messages in this chat, and for
/// the typing indicator. Call from -viewWillAppear. Chains onto whatever
/// handler was installed before, and puts it back on -stopWatching.
- (void)startWatching;
/// Stop listening. Call from -viewDidDisappear and before releasing the
/// companion; -dealloc calls it too.
- (void)stopWatching;

#pragma mark - loading

/// Fetch the newest page. Moves state to Loading, then Loaded, Empty or
/// Failed. Safe to call again; a second call while one is in flight is ignored.
- (void)loadInitial;

/// Fetch the page above the oldest message held. Reports its rows through
/// -conversationCompanion:didInsertAtIndexes:, which will be indexes 0..n-1.
/// Does nothing when -canLoadOlder is NO or a page is already in flight.
- (void)loadOlder;

/// Re-read the window from scratch, keeping the same size. Ends in a
/// -conversationCompanionDidReloadAll: unless nothing changed.
- (void)reload;

#pragma mark - reading the window

/// nil when index is out of range, rather than an exception on a stale table.
- (TGMessageModel *)messageAtIndex:(NSInteger)index;
/// NSNotFound when the message is not in the loaded window.
- (NSInteger)indexOfMessageId:(int64_t)messageId;
- (TGMessageModel *)messageWithId:(int64_t)messageId;

/// The typed media payload of a message, fetched once and cached until a
/// memory warning. `completion` gets nil when the message carries no media.
/// Runs on the main queue, immediately when the answer is already cached.
- (void)mediaForMessageId:(int64_t)messageId
	       completion:(void (^)(TGMediaModel *media))completion;

#pragma mark - acting on the conversation

/// Send text into this chat. The companion appends the accepted message
/// itself, so the screen only clears its input field.
- (void)sendText:(NSString *)text;
/// Send as a reply. `replyToMessageId` of 0 is the same as -sendText:.
- (void)sendText:(NSString *)text replyToMessageId:(int64_t)replyToMessageId;

/// Retry a message whose send failed.
- (void)resendMessageId:(int64_t)messageId;

/// Delete messages. `messageIds` are NSNumber int64 values. The rows go away
/// through -conversationCompanion:didRemoveAtIndexes: when TDLib confirms.
- (void)deleteMessageIds:(NSArray *)messageIds forEveryone:(BOOL)forEveryone;

/// Mark everything currently loaded as read, whatever -marksMessagesRead says.
- (void)markLoadedMessagesRead;

/// Tell the other side what the user is doing - "typing", "recordingVoice" and
/// the rest of TGClient's action names. Telegram forgets it after a few
/// seconds, so a live indicator has to repeat the call.
- (void)sendAction:(NSString *)action;

#pragma mark - memory

/// Drop everything derived that can be built again: the media cache, and any
/// history above the newest page. Called for the screen on a system memory
/// warning, and safe to call by hand.
- (void)didReceiveMemoryWarning;

@end

// vim:ft=objc

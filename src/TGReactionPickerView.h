//
// TGReactionPickerView - reactions in the 2013 idiom.
//
// Two views live here, because they are the two halves of one feature:
//
//   TGReactionPickerView  the horizontal strip of emoji that opens after the
//                         "React" row of TGPopupMenu. It is a TGMenuView-shaped
//                         card: 41pt tall, MenuButton plates, an arrow pointing
//                         at the bubble, one emoji per button, scrolling
//                         sideways past six of them.
//
//   TGReactionChipsView   the compact row of chips drawn under a bubble, each
//                         one an emoji, its count, and whether we picked it.
//                         Chip height 20, emoji 13pt, count bold 11pt, filled
//                         with the bubble's own selected-state plate.
//
// Nothing here talks to TDLib directly; everything goes through
// TGClient+Reactions.
//
#import <UIKit/UIKit.h>

/// `nowChosen` is YES when the reaction is now set on the message, NO when the
/// tap removed it (or the call failed).
typedef void (^TGReactionPickedBlock)(NSString *emoji, BOOL nowChosen);

/// `chosen` is the state the chip had *before* the tap, so a caller that wants
/// to act without waiting knows which way the toggle went.
typedef void (^TGReactionChipTappedBlock)(NSString *emoji, BOOL chosen);

#pragma mark - the picker strip

@interface TGReactionPickerView : UIView

/// The message the strip reacts to. Both must be set before -loadReactions.
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;

/// Called on the main queue after the tapped reaction has been toggled. The
/// strip dismisses itself first.
@property (nonatomic, copy) TGReactionPickedBlock onReactionPicked;

/// The whole flow in one call, which is how a chat controller should use it:
/// place the strip over `rect` (the bubble, in `host` coordinates), show a
/// spinner, ask TDLib which reactions the message accepts, then the emoji.
/// Returns the strip, already added to `host`. Only one is ever open; showing a
/// second dismisses the first. Call +dismiss from viewWillDisappear.
+ (instancetype)showForMessage:(int64_t)messageId
                        inChat:(int64_t)chatId
                      fromRect:(CGRect)rect
                        inView:(UIView *)host
                        picked:(TGReactionPickedBlock)picked;

/// Close whatever strip is open, if any.
+ (void)dismiss;

/// Ask TDLib for the emoji this message accepts and rebuild. Called for you by
/// +showForMessage:; call it yourself only if you built the view by hand.
- (void)loadReactions;

/// Fill the strip from a list you already have (array of NSString). Pass a
/// non-empty `reason` instead to draw the "you cannot react here" card.
- (void)setEmoji:(NSArray *)emoji reason:(NSString *)reason;

@end

#pragma mark - the chips under a bubble

@interface TGReactionChipsView : UIView

/// Chips in the shape +[TGClient reactionChipsFromMessage:] hands back:
/// "emoji", "count", "chosen", "custom". Setting this relays out; the view is
/// hidden while the array is empty.
@property (nonatomic, copy) NSArray *chips;

/// Draws the outgoing plate instead of the incoming one. Default NO.
@property (nonatomic, assign) BOOL outgoing;

/// Fired when a chip is tapped, after the toggle has been sent when the view
/// knows its message, or immediately when it does not.
@property (nonatomic, copy) TGReactionChipTappedBlock onChipTapped;

/// Set these and the view toggles the reaction itself on a tap and refreshes
/// its own counts. Leave them 0 to make the view purely presentational.
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;

/// Same as -setChips: with the 0.15s fade the rulebook allows.
- (void)setChips:(NSArray *)chips animated:(BOOL)animated;

/// Fetch the chips for -messageId / -chatId and adopt them.
- (void)reloadChips;

/// How tall a row of these chips is at `width`, so a bubble can size itself
/// before the view exists. 0 when there is nothing to draw.
+ (CGFloat)heightForChips:(NSArray *)chips width:(CGFloat)width;

@end

// vim:ft=objc

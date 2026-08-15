# TGSwitchMenuItemCell — the switch row in a grouped settings menu

## Naming: the class is actually `TGSwitchItemCell`

There is no `TGSwitchMenuItemCell` in the 2014 v1.1 tree. The sibling cells for the same
menu system are named `TGActionMenuItemCell`, `TGVariantMenuItemCell`,
`TGButtonMenuItemCell`, `TGUserMenuItemCell`, `TGWallpapersMenuItemCell` — but the switch
row breaks the pattern and is called **`TGSwitchItemCell`**, backed by a model object
**`TGSwitchItem`** (not `TGSwitchMenuItem`). Everything below is that class.

Files:

- `Telegraph/Telegraph/TGSwitchItemCell.h` (29 lines)
- `Telegraph/Telegraph/TGSwitchItemCell.m` (102 lines)
- model: `Telegraph/Telegraph/TGSwitchItem.h` / `.m`
- superclass: `Telegraph/Telegraph/TGGroupedCell.h` / `.m`
- the switch control itself: `TelegraphKit/TelegraphKit/TGSwitchView.h` / `.m`

All paths are relative to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`.

---

## 1. What it is for

One row of a grouped settings table: a bold black title on the left, a hand-drawn ON/OFF
toggle on the right. It is used by exactly two screens in v1.1:

- `TGNotificationSettingsController.m:448-471` — the user-facing Notifications screen
  (message alerts, previews, group alerts, in-app sounds/vibrate/preview, "people nearby").
- `TGSettingsController.m:278-299` — the internal/debug settings screen ("Debug session",
  "Show message IDs", "Don't read", "Don't jump in dialogs", "Disable background mode";
  `TGSettingsController.m:59-88`).

It is a *menu item* cell, meaning it does not own its state. The `TGSwitchItem` model holds
`isOn` (`TGSwitchItem.h:16`) and the cell reports changes back through the ActionStage
watcher rather than through a target/action or a delegate on the controller.

## 2. Public surface

```objc
@interface TGSwitchItemCell : TGGroupedCell
@property (nonatomic, strong) ASHandle *watcherHandle;   // TGSwitchItemCell.h:17
@property (nonatomic, strong) id itemId;                 // :18  — the TGSwitchItem itself
@property (nonatomic, strong) NSString *title;           // :20
@property (nonatomic) bool isOn;                         // :21
- (void)setCustomBackgroundColor:(UIColor *)color;       // :23
- (void)setIsOn:(bool)isOn animated:(bool)animated;      // :25
- (void)fireChangeEvent;                                 // :27
@end
```

`itemId` is typed `id` but every call site assigns the `TGSwitchItem` object itself
(`TGNotificationSettingsController.m:467`, `TGSettingsController.m:297`), and the receiver
pulls it back out of the notification dictionary and casts it
(`TGNotificationSettingsController.m:713`). It is an object identity token, not an integer id.

`setCustomBackgroundColor:` (`TGSwitchItemCell.m:63-66`) sets only the *title label's*
backgroundColor. **It is never called anywhere in the tree** (grep for
`setCustomBackgroundColor` returns only the declaration and the definition). Dead API; do
not port it.

## 3. Geometry, with citations

Row height is **44 pt**, decided by the controller, not the cell:
`TGNotificationSettingsController.m:347-348` returns 44 for
`TGActionMenuItemType || TGSwitchItemType || TGVariantMenuItemType` (button rows get 45,
comment rows are measured). So the switch row shares its height with the plain action row —
this is a stock 44 pt grouped row, not a custom height.

Everything is laid out once in `initWithStyle:` against the contentView's *initial* width
(320 on the only device that mattered), then maintained by autoresizing masks — there is no
`layoutSubviews` in this class.

**Switch** (`TGSwitchItemCell.m:30-34`):

- `TGSwitchView` default frame is `0,0,77,27` (`TGSwitchView.m:59`).
- placed at `x = contentView.width - 77 - 9 = 234`, `y = 8` → 9 pt right margin,
  8 pt top, so `8 + 27 = 35` against a 44 pt row leaves 9 pt below. Deliberately
  1 pt higher than centred.
- `autoresizingMask = UIViewAutoresizingFlexibleLeftMargin`, so it stays pinned to the right
  on rotation.

**Vertical nudge for grouped ends** (`TGSwitchItemCell.m:49-54`): overriding
`setGroupedCellPosition:` re-frames the switch to `y = 7.5` when the cell is the first or the
last of its section, and `y = 8.0` for middle rows. The reason is that the grouped background
artwork for a top/bottom cell has a rounded cap and the cell's visible content box is shifted
by half a point; the half-point makes the toggle sit optically level with the caps. On a 2x
screen 7.5 is a real pixel boundary, so it is crisp; on 1x it would be blurry (and v1.1 still
ran on non-retina hardware — the original accepted that).

**Title label** (`TGSwitchItemCell.m:36-42`):

- frame `CGRectMake(11, 12, contentView.width - 28 - 77, 20)` → `11, 12, 215, 20` at 320 pt.
  Left inset 11 pt; the right edge lands at 226, i.e. 8 pt of air before the switch at 234.
- `autoresizingMask = UIViewAutoresizingFlexibleWidth`.
- font `[UIFont boldSystemFontOfSize:17]` (`:38`) — **bold**, which is the single most
  characteristic thing about 2013 Telegram settings rows and the easiest detail to get wrong.
- `textColor` black (`:40`), `highlightedTextColor` white (`:41`).
- `backgroundColor` = **opaque `[UIColor whiteColor]`** (`:39`), not clear. This is a 2011-era
  scrolling-performance trick: an opaque label avoids blending. It is only safe because the
  grouped cell artwork behind it is white in the label's rectangle and because the call sites
  set `selectionStyle = UITableViewCellSelectionStyleNone`
  (`TGNotificationSettingsController.m:458`, `TGSettingsController.m:288`), so the white
  highlight background never runs under the label. `highlightedTextColor` is therefore dead
  in practice.
- 20 pt tall label with a 17 pt bold font, top at 12 → text box 12..32 in a 44 pt row, i.e.
  centred to within a point. Baseline sits slightly high, matching the switch's high placement.

## 4. Overflow, empty, missing

- The label is a plain single-line `UILabel` with no `numberOfLines`/`lineBreakMode` set, so
  it uses the iOS default: one line, tail truncation with an ellipsis, clipped at 215 pt.
  Long localizations (German notification strings are the real case) simply get "…". Nothing
  wraps, nothing shrinks, the row never grows — height is hard-coded 44 by the controller
  (`TGNotificationSettingsController.m:348`).
- `setTitle:` (`:56-61`) assigns straight through with no nil guard; `nil` clears the label
  and leaves an empty row with only the toggle. There is no placeholder behaviour.
- The cell has no state to clear on reuse and implements no `prepareForReuse`. Correctness on
  reuse depends entirely on the call sites always setting `title`, `isOn` and `itemId`
  (`TGNotificationSettingsController.m:463-467`) — which they do, unconditionally, outside
  the `if (cell == nil)` block. Only `watcherHandle` is set once at creation time
  (`:468`), which is fine because a controller owns its own table.

## 5. The toggle artwork (`TGSwitchView`)

The 2013 switch is not `UISwitch`; it is nine layered image views, all sized around a
77 × 27 pt control (`TGSwitchView.m:59`, `:70`):

| layer | asset | note |
| --- | --- | --- |
| track | `SwitchBackground.png` | `TGSwitchView.m:70-72`, 77×27 (154×54 @2x) |
| blue fill | `SwitchBlue.png` | in a clipping container whose width follows the handle: `CGRectMake(0, 0, handle.x + 14, 27)` (`:193`) |
| ON caption | `SwitchOnText.png` | 24×14 pt (48×28 @2x), placed at `handleX - width - 9`, y 7 (`:195`) |
| OFF caption | `SwitchOffText.png` | 30×14 pt (60×28 @2x), placed at `handleX + handleWidth + 6`, y 7 (`:196`) |
| transition | `SwitchBlueTransition.png` | 29×29 pt, tracks the handle frame exactly (`:192`) |
| shadow | `SwitchShadow.png` | inner shadow over the whole track (`:98-100`) |
| mask | `SwitchMask.png` | stretched with `leftCapWidth = width/2` (`:102-105`) to round the ends |
| handle | `SwitchBulb.png` + `SwitchBulb_Highlighted.png` | 29×29 pt, drawn at `y = -1` (`:191`); highlighted image swaps in on touch-down (`:165`) |

Handle travel: off position is `x = -1`, on position is `77 - 29 + 2 = 50`
(`TGSwitchView.m:110`, `:136`). Animation is 0.25 s for a programmatic or tap change
(`:124`, `:239`) and 0.10 s for the settle after a drag (`:226`, `:230`). Drag is supported:
a `UIPanGestureRecognizer` moves the handle live, clamped to `[0, onHandlePosition]`
(`:213-216`), and on release the value snaps to whichever half the handle is in —
`handleX > (-1 + onHandlePosition) / 2` (`:225`) — notifying the delegate only if the value
actually changed. The blue fill's visibility is a hard on/off at `handleX > 0`
(`:243-252`), not a fade.

## 6. Behaviour on tap, and the change event

Two independent tap paths exist:

1. `TGSwitchView` has its own tap recognizer that toggles with a 0.25 s animation and
   notifies its delegate (`TGSwitchView.m:117`, `:235-241`).
2. `TGSwitchItemCell` adds a tap recognizer **to the cell itself** (`TGSwitchItemCell.m:44`),
   so tapping anywhere in the 44 pt row flips the switch:
   `[_switchView setOn:!isOn animated:true notifyOnCompletion:true]` (`:98`).

Either way the delegate callback `switchView:didChangeIsOn:` (`:80-83`) calls
`fireChangeEvent`, which posts an ActionStage action rather than calling the controller
directly (`:85-92`):

```objc
[watcher actionStageActionRequested:@"toggleSwitchItem"
    options:@{ @"itemId": _itemId, @"value": @(_switchView.isOn) }];
```

The controller receives it in `actionStageActionRequested:options:`
(`TGNotificationSettingsController.m:707-720`), writes `switchItem.isOn` back into the model,
then dispatches on `switchItem.tag` to fire the actual network actor. Note the ordering: the
notification is sent **on animation completion** (`TGSwitchView.m:151-152`), not at touch-up,
so the network request starts ~0.25 s after the tap. The model is only updated when the
event arrives, i.e. the model lags the visual state for the duration of the animation.

Two things worth knowing before copying this:

- `TGSettingsController.m:375-381` *also* toggles the item from
  `didSelectRowAtIndexPath:` and calls `fireChangeEvent` manually. Since the cell's own tap
  recognizer is still installed and table-view selection is not suppressed by it, a tap on a
  row in that screen looks like it can toggle twice. `TGNotificationSettingsController`
  deliberately does **not** handle `TGSwitchItemType` in `didSelectRowAtIndexPath:`
  (`:566-600` handles only action and variant items), which is the correct pattern and the
  one the user-facing screen uses. I could not settle from source alone whether the debug
  screen actually double-toggles (it depends on recognizer/table-selection interaction and on
  `exclusiveTouch`, `TGSwitchView.m:67`); treat the notifications controller as the reference
  and do not reproduce the debug screen's extra toggle.
- The same ambiguity applies to a tap landing directly on the toggle: both the ancestor (cell)
  and descendant (switch) recognizers are live. If we reimplement this, put the recognizer on
  the cell and *disable* the switch's own tap, or gate the cell recognizer on the touch point
  falling outside the switch's frame. That is a deliberate improvement on an unclear original.

## 7. Grouped background and the superclass

`TGSwitchItemCell` inherits `TGGroupedCell`, whose whole job is the grouped-section artwork
(`TGGroupedCell.m`):

- background is nil and `opaque = false` (`:27-28`) — the images come from the call site.
- the controller assigns `backgroundView`/`selectedBackgroundView` as bare `UIImageView`s at
  creation (`TGNotificationSettingsController.m:453-456`) and then, per row, picks
  `groupedCellSingle` / `groupedCellTop` / `groupedCellBottom` / `groupedCellMiddle` from
  `TGInterfaceAssets` together with the `*Highlighted` variants
  (`TGNotificationSettingsController.m:516-548`), and sets `groupedCellPosition` and
  `extendSelectedBackground` in the same branch (`:519-546`). Single cells get
  `extendSelectedBackground = false`; every other position gets `true`.
- `extendSelectedBackground` grows the selection artwork by 1 pt for middle and first cells
  (`TGGroupedCell.m:3-15`) so the highlight covers the hairline separator, and
  `adjustOrdering` (`:87-112`) re-inserts the highlighted cell above its neighbours so the
  overlap draws on top.

For the switch row specifically, `selectionStyle` is `None` at both call sites, so the
highlight machinery never runs — but `groupedCellPosition` still matters, because the cell
uses it for the 7.5 / 8.0 pt vertical nudge (§3).

---

## 8. Our port: what we have instead

We have **no equivalent class**. Every switch row in `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src` is a stock
`UITableViewCell` with a stock `UISwitch` hung on `accessoryView`, built inline in whichever
controller needs it. Representative sites:

- `src/TGSettingsViewController.m:2652-2657` (Save Incoming Photos),
  `:2893-2899` (`notificationSwitchOn:tag:` factory), `:3072`, `:3259`, `:3360`, `:3489`,
  `:3555`, `:3569`
- `src/TGPrivacyViewController.m:1129-1140`
- `src/TGSessionsViewController.m:924-936`
- `src/TGFoldersViewController.m:1352`
- `src/TGGroupMembersViewController.m:516-519`
- `src/TGChatEventsViewController.m:395`
- `src/TGProfileViewController.m:3254`, `:3598`

Honest verdict: **the visual result is closer to right than it looks**, because the iOS 6.1
system `UISwitch` is itself the 2013 skeuomorphic ON/OFF toggle, and it is 79 × 27 against the
original's 77 × 27 — a 2 pt difference nobody will see. Replacing all of this with a
hand-rolled nine-layer `TGSwitchView` would be a large change for almost no visible gain, and
would cost us the free drag gesture. I do not recommend porting `TGSwitchView`.

What *is* visibly wrong, and is cheap to fix:

1. **Row tap does not toggle.** The original toggles from a tap anywhere in the row
   (`TGSwitchItemCell.m:44`, `:94-100`). Ours only responds to a hit on the switch itself —
   no `didSelectRowAtIndexPath:` handler in any of the sites above flips an accessory switch,
   and the only place that fakes it is the debug touch harness
   (`src/AppDelegate.m:410-416`), which is test scaffolding, not product behaviour. On a
   4S-sized target the toggle is a small target; this is a real usability regression against
   the original. Fix: in each switch-bearing table, handle the row selection by calling
   `[toggle setOn:!toggle.on animated:YES]` + `sendActionsForControlEvents:
   UIControlEventValueChanged`, and deselect.
2. **Title font is right where it is set, missing where it is not.** The original is
   `boldSystemFontOfSize:17` (`TGSwitchItemCell.m:38`). We set that explicitly in
   `src/TGSettingsViewController.m:2650` and `:2903`, but most other switch rows
   (`TGPrivacyViewController.m:1129` region, `TGSessionsViewController.m:924` region,
   `TGFoldersViewController.m:1352`, `TGProfileViewController.m:3254`) leave the stock
   `textLabel` font, which on iOS 6 grouped tables is already bold 17 — so those are
   accidentally correct, but fragile. Worth making explicit so nobody "fixes" it to regular
   later.
3. **Left inset.** The original title starts at **11 pt** from the contentView edge
   (`TGSwitchItemCell.m:36`). Stock `UITableViewCell` in a grouped table on iOS 6 indents the
   text label further. Anywhere we care about matching a period screenshot exactly, this is
   the visible difference. Low severity — but if a row is ever rebuilt with a custom label,
   use 11, not 15 (15 is the *modern* number, see §9).
4. **Right margin.** Original 9 pt (`TGSwitchItemCell.m:33`); `accessoryView` on iOS 6 gives
   about 10 pt. Within noise, leave it.
5. **Vertical placement.** Original pins the toggle to y = 8 (7.5 on section end rows),
   1 pt above centre (`TGSwitchItemCell.m:33`, `:53`). `accessoryView` centres it. This is a
   1 pt difference; not worth chasing unless we build a custom cell for other reasons.
6. **We do not have the original's model/watcher indirection**, and we should not want it.
   Our direct `addTarget:action:UIControlEventValueChanged` is the same thing without
   ActionStage. But note the original notified *after* the animation completed
   (`TGSwitchView.m:151`), whereas ours fires immediately — ours is better, and the modern
   client agrees (see §9).

There is no `SwitchBackground.png` / `SwitchBulb.png` family in `iTgLegacy/images/`
(only `ListEditingSwitch@2x.png`, unrelated), confirming we never attempted the custom
control.

## 9. What became of it

**Twelve** (`/Users/alexanderhavrysh/Git/iOS/twelve`) — same lineage, later. The cell became
`TGSwitchCollectionItem` / `TGSwitchCollectionItemView` in the collection-menu framework:

- `TGSwitchCollectionItemView.m:35` — **`TGSwitchView` was abandoned for stock `UISwitch`.**
  The hand-drawn toggle only survives as `TGIconSwitchView`, and only for permission rows on
  iOS 8+ (`:32-33`). Forced change: iOS 7 flattened the system switch, so keeping a
  skeuomorphic one would have looked broken.
- `:28` — title font became **`TGSystemFontOfSize(17)`, regular, not bold.** That is the iOS 7
  flattening again, and it is precisely the change our 2013 look must not adopt.
- `:104-106` — insets moved to **15 pt** left and right (from 11/9), and the switch is placed
  at y = 6 with a 26 pt title box vertically centred rather than fixed at y = 12.
- The item grew `isEnabled`, `isLocked`, `isPermission`, `fullSeparator`
  (`TGSwitchCollectionItem.h:21-24`) with alpha 0.5 for disabled/locked
  (`TGSwitchCollectionItemView.m:77-88`) — new features (permissions UI, premium locks), not
  taste. The 2013 cell had **no disabled state at all**, which is worth remembering: if we
  need one, we are inventing it.
- ActionStage was replaced by plain blocks (`toggled`, `lockedPressed`,
  `TGSwitchCollectionItem.h:16-17`). Pure simplification.

**Modern Telegram-iOS** —
`submodules/ItemListUI/Sources/Items/ItemListSwitchItem.swift`:

- height still **44** (`:311`, `:316`) — the one number that survived thirteen years intact.
- title font regular at the user's base size (`:289`), left inset **16** (`:333`), switch right
  inset **15** (`:547`), switch vertically centred (`:547`).
- **the whole row toggles** (`:229-231`) — the 2013 behaviour was kept, and everything in
  between (accessory-view-only) was the aberration. This is the strongest argument for fixing
  our defect #1.
- the switch is theme-driven (`frameColor`, `contentColor`, `handleColor`,
  `positiveContentColor`, `negativeContentColor`, `:439-443`) — themes forced a custom
  `SwitchNode` back into existence, which is the same problem the 2013 art solved with PNGs.
- title truncation became explicit and multi-line-capable
  (`maximumNumberOfLines`, truncation `.end`, `:343`) — real-world long localizations forced
  it. The 2013 single-line clip at 215 pt is what we should copy, but it is a known weak spot.

## 10. Rebuild checklist (the numbers, in one place)

Row 44 pt · title bold system 17, black, at x = 11, y = 12, height 20, width
`contentWidth - 28 - switchWidth` · switch 77 × 27 at right margin 9, y = 8 (7.5 when the row
is first or last in its grouped section) · single-line tail truncation · tap anywhere in the
row toggles with a 0.25 s animation · no disabled state · grouped background artwork comes
from the controller, not the cell · `selectionStyle = None`.

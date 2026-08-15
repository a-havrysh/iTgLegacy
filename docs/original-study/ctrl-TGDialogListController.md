# TGDialogListController (original, Telegram for iOS v1.1 / 2013)

Source of truth for everything below:

- `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGDialogListController.h` (40 lines)
- `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGDialogListController.mm` (1703 lines)
- supporting: `TGDialogListCompanion.h`, `TGDialogListCellAssetsSource.h`, `TGDialogListCell.h/.m`,
  `Telegraph/Telegraph/TGInterfaceAssets.mm`, `Telegraph/Telegraph/TGTelegraphDialogListCompanion.mm`,
  `Telegraph/Telegraph/TGForwardTargetController.m`

Our equivalent: `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGChatListViewController.m` (4098 lines; the
cell is an inner class in the same file, not a separate one).

---

## 1. What the class is

`TGDialogListController` is the *chat list screen*, and nothing else. It is deliberately dumb: it owns a
table view, a search bar, two navigation-bar buttons, a title-status view and an empty-state view, and it
knows how to turn an array of `TGConversation` into cells. Every decision that involves the network, the
database or navigation is pushed onto a `TGDialogListCompanion`
(`TGDialogListController.h:21`, `TGDialogListCompanion.h:19-52`).

That split is the reason the same screen serves two products in the original app:

- the main Messages tab, driven by `TGTelegraphDialogListCompanion` with `forwardMode = false`;
- the "forward to…" / "block user…" picker, driven by the same companion with `forwardMode = true`
  (`TGForwardTargetController.m:66-69` and `:88-92`).

`forwardMode` is not cosmetic. It removes the search scope bar (`TGDialogListController.mm:527-528`),
disables per-row editing on every cell (`:1258`), and makes a tap deselect the row instead of leaving it
selected (`:1100-1101`), because you are picking a target, not navigating away.

The controller is also an `ASWatcher` (`TGDialogListController.h:17`): the cells talk *back* to it through
`_actionHandle` rather than through a delegate, which is how a swipe-delete inside a cell reaches the
controller (`:1622-1699`).

## 2. Public surface

```objc
@property (nonatomic, strong, readonly) ASHandle *actionHandle;      // .h:19
@property (nonatomic, strong) TGDialogListCompanion *dialogListCompanion; // .h:21
@property (nonatomic) bool canLoadMore;                              // .h:23
- (id)initWithCompanion:(TGDialogListCompanion *)companion;          // .h:28
- (void)resetState;                                                  // .h:30
- (void)dialogListFullyReloaded:(NSArray *)items;                    // .h:31
- (void)dialogListItemsChanged:...;                                  // .h:32
- (void)searchResultsReloaded:(NSArray *)items searchString:(NSString *)s; // .h:34
- (void)titleStateUpdated:(NSString *)text isLoading:(bool)isLoading; // .h:36
- (void)userTypingInConversationUpdated:(int64_t)cid typingString:(NSString *)s; // .h:38
+ (void)setDebugDoNotJump:(bool)v; + (bool)debugDoNotJump;           // .h:25-26
```

`initWithCompanion:` sets `automaticallyManageScrollViewInsets = true` and
`ignoreKeyboardWhenAdjustingScrollViewInsets = true` (`.mm:222-223`) — the list must *not* shrink when the
search keyboard appears, because the search results live in a separate table on top of it.

The three UIApplication notifications are wired in the initialiser, not in `viewDidLoad`
(`.mm:234-236`): `UIApplicationSignificantTimeChangeNotification`, `…DidEnterBackground`,
`…WillEnterForeground`.

`debugDoNotJump` is a debug switch surfaced in Settings (`Telegraph/Telegraph/TGSettingsController.m:84`
and `:520`) that suppresses the "restore selection of the chat you came back from" behaviour.

## 3. Geometry and colour, with citations

| Thing | Value | Citation |
|---|---|---|
| Conversation row height | **73 pt** | `.mm:1124` |
| Trailing "load more" placeholder row | **50 pt** | `.mm:1125` |
| Search result row, *Conversations* scope | **51 pt** | `.mm:1129` |
| Search result row, *Messages* scope | **73 pt** (a full dialog cell) | `.mm:1129-1130` |
| Search bar | 44 pt tall, full width, is the `tableHeaderView` | `.mm:499`, `.mm:530` |
| Overscroll header above the list | `CGRectMake(0, -480, width, 480)`, colour `0xe4e9f0` | `.mm:492-495`, `TGInterfaceAssets.mm:175-178` |
| View / table background | white | `.mm:482`, `.mm:490` |
| Separators | **none**; drawn by the cell plate art | `.mm:538` |
| Empty-state container width | 250 pt, centred in the view | `.mm:889`, `.mm:919` |
| Empty-state title | bold system 15, `0x8b97a5`, 21 pt below the icon | `.mm:898-902` |
| Empty-state body | system 14, `0x8b97a5`, centred, wraps at **232 pt**, 8 pt below title | `.mm:905-914` |
| Title status label | bold system 15, white, shadow `0x415a7e` offset (0,−1), top-aligned | `.mm:268-272` |
| Title status container | 40 × 30, `clipsToBounds = false` | `.mm:262-263` |
| Edit / Done buttons | `minWidth 51`, padding 10/10 | `.mm:301-306`, `.mm:317-322` |
| Compose button | padding 6/6, `ComposeMessageIcon.png` + `…_Landscape.png` | `.mm:410-415` |
| Scope bar labels | bold system 12; selected white on `0x112e5c @20%` shadow; normal `0x5c708b` on `0xffffff @25%` shadow | `.mm:511-521` |
| Search placeholder colour | `0x8d9298` | `.mm:440` |

**Why 73.** It is not a round number picked for looks — it is the height of the artwork.
`DialogListCell@2x.png` is 4 × 146 px, i.e. 2 × 73 pt, and it is stretched with
`stretchableImageWithLeftCapWidth:1 topCapHeight:0` (`.mm:1137-1138`): horizontally stretchable,
**vertically fixed**. The plate carries the row's top/bottom hairlines, which is why the table itself has
`separatorStyle = None`. Change the row height and the plate stops lining up with the row edges. Inside
that 73 pt the cell puts a 56 × 56 avatar at (8, 8) (`TGDialogListCell.m:406`), text starting at x = 73
(`TGDialogListCell.m:369`, `:1273-1275`, `:1335-1337`), title in bold system 16, preview in system 14,
author name in bold system 14 (`TGDialogListCell.m:371-373`). 8 + 56 + 9 = 73, so the text column starts
exactly 9 pt after the avatar.

**Why 51 for a search row.** A search result in the Conversations scope has no message preview and no
date — one line of name over an avatar — so it uses `TGDialogListSearchCell`, a shorter cell. The Messages
scope reuses the full 73 pt `TGDialogListCell` because it does show a message.

## 4. Structure of the screen

```
self.view (white)
└── TGDialogListTableView (plain style, full bounds, autoresizes)
    ├── headerView   frame (0, -480, w, 480), colour 0xe4e9f0   ← .mm:492-495
    ├── tableHeaderView = TGSearchBar, 44 pt                    ← .mm:530
    ├── rows: TGDialogListCell (73 pt)
    └── optional trailing placeholder row with a grey spinner (50 pt)
emptyListContainer  ← inserted BELOW the table view, .mm:890
```

Two details that are easy to miss:

1. The 480-tall header view is a plain `UIView` added as a **subview of the table**, not a
   `tableHeaderView`. Its only job is to paint the rubber-band area above the search bar in
   `0xe4e9f0` so that pulling the list down shows the pale blue-grey, not white.
2. The empty-state container is inserted *below* the table (`insertSubview:belowSubview:`, `.mm:890`) and
   the table is then hidden outright when the list is empty (`.mm:927`). So when you have no chats you do
   not see an empty table with a stranded search bar — you see the placeholder on white with no search bar
   at all.

## 5. Data flow and states

`dialogListFullyReloaded:` (`.mm:840-883`) is the wholesale path: it clears `_isLoading`, remembers which
`conversationId` was selected, swaps the model, reloads, and then re-selects the row that holds the same
conversation id — index-based restoration would be wrong because the list re-sorts by date.

`reloadData` (`.mm:819-831`) is not a plain `[tableView reloadData]`. Before reloading it walks the visible
cells, harvests their already-decoded avatars into a dictionary, and pushes it into
`[TGRemoteImageView sharedCache] addTemporaryCachedImagesSource:autoremove:`. Without this every full
reload would re-decode every visible avatar from disk on an ARMv7 device. On a 4S this is the difference
between a reload you notice and one you do not.

`dialogListItemsChanged:…` (`.mm:932-975`) is the incremental path:
- removals are applied to the model and then animated out with `UITableViewRowAnimationRight`
  (`.mm:946`) — chats slide out to the right, not fade;
- updates are applied to the model and then pushed into the *existing* cell via `prepareCell:…animated:true`
  rather than reloading the row, so the cell can animate its own internal changes (badge, checkmark);
- insertions are, notably, **not handled here at all** — every parameter is `__unused` and insertion only
  ever arrives through a full reload;
- crossing the empty/non-empty boundary re-runs `updateEmptyListContainer` and, if the list just became
  empty, force-exits editing mode (`.mm:968-974`).

`resetState` (`.mm:833-838`) hides the table and destroys the placeholder — used on logout
(`TGTelegraphDialogListCompanion.mm:122-140`).

**Loading more.** `willDisplayCell:` triggers `[_dialogListCompanion loadMoreItems]` when `canLoadMore`,
not already loading, and the row being displayed is within the last 10 of the list, or the list is shorter
than 10 rows (`.mm:1464-1479`). `_isLoading` is only cleared by the next full reload (`.mm:842`). While
`canLoadMore` is true there is an extra trailing row (`heightForRow` returns 50 when the row index is past
the model, `.mm:1125`) carrying a grey `UIActivityIndicatorView` sized 24 × 24, centred, tag 10000
(`.mm:1269-1295`); when `canLoadMore` goes false the spinner is hidden and stopped but the row remains.

**Typing.** Typing strings live in a C++ `std::map<int64_t, NSString *>` on the controller
(`.mm:161`). `userTypingInConversationUpdated:` mutates the map, and only if the value actually changed
does it scan the visible cells for a matching `conversationId` and call
`setTypingString:animated:true` (`.mm:359-404`). The map is the source of truth, so a cell scrolled back
into view picks up the typing state again in `prepareCell:` (`.mm:1201-1208`). A cell with no entry gets
`setTypingString:nil` explicitly — this is what stops a recycled cell from showing someone else's
"typing…".

**Title status.** `titleStateUpdated:text:isLoading:` (`.mm:338-357`) sets the label, sizes it, and lays
out the small white spinner 5 pt to its left, 3 pt lower. `_showTitleStatus = isLoading`, so
`controllerTitleView:` returns the status view *only while loading* and `nil` otherwise (`.mm:282-290`),
falling back to the plain title `DialogList.Title`. The spinner is `TGActivityIndicatorView` in
`TGActivityIndicatorViewStyleSmallWhite`, which is not a `UIActivityIndicatorView` at all but a 24-frame
image animation over `RProgress1…24@2x.png`, each 30 × 30 px = 15 × 15 pt
(`TGActivityIndicatorView.m:38-63`, `Resources/ProgressIndicatorWhite/RProgress1@2x.png`).

**Empty list.** Built lazily in `updateEmptyListContainer` (`.mm:885-930`) from `NoMessages.png`
(204 × 182 px = 102 × 91 pt), a bold-15 title and a wrapped system-14 body, stacked icon → 21 pt → title →
8 pt → body, and the whole 250-wide stack is vertically centred in the view. It is re-centred on rotation
(`.mm:775-778`). Crucially the container is *hidden* unless
`[_dialogListCompanion shouldDisplayEmptyListPlaceholder]` (`.mm:928-929`), which returns
`clientUserId != 0` (`TGTelegraphDialogListCompanion.mm:182-185`): during the first sync after login you
get a blank white screen, not "You have no conversations yet".

## 6. Behaviour on tap, on return, and in editing mode

**Tap.** `didSelectRowAtIndexPath:` opens with a re-entrancy guard: a `static bool canSelect` that is set
false and restored on the next main-queue turn (`.mm:1049-1059`). Two taps landing in the same runloop
iteration produce one navigation. It then checks `cell.selectionStyle != None` before acting, so the
placeholder row is inert, and hands the conversation to the companion (`.mm:1061-1075`), which either
navigates (`navigateToConversationWithId:`) or, in forward mode, fires a `conversationSelected` action to
the watcher (`TGTelegraphDialogListCompanion.mm:150-158`).

The row **stays selected** while the chat pushes. It is only deselected on return, in `viewWillAppear:`,
and with a delay chosen by the number of CPU cores: immediate on >2 cores, 0.05 s on 2 cores, 0.1 s on 1
core (`.mm:618-640`). The point is that on a slow device the pop animation must be underway before the blue
plate fades, otherwise the fade happens off-screen and the row appears to flash on arrival. The same
three-way delay is repeated for the search results table (`.mm:642-670`). The 4S is dual-core, so the
0.05 s branch is ours.

**Return from a chat.** Before deselecting, `viewWillAppear:` asks
`[TGConversationController lastConversationIdForBackAction]` and, if set, finds that conversation in the
model and *selects* the row, scrolling it into view only if it is off-screen — to the bottom if it is
below `view.height - controllerInset.bottom`, to the top if it is above `controllerInset.top`, otherwise
not at all (`.mm:579-609`). Combined with the delayed deselect above, the effect is that the chat you were
just in is briefly highlighted where it now sits after the list re-sorted.

**Editing.** Edit/Done live in the *left* bar item, not the right (`.mm:292-331`), and only when
`[_dialogListCompanion showListEditingControl]`. Done uses `TGToolbarButtonTypeDone`, a different button
type than Edit's `TGToolbarButtonTypeGeneric` (`.mm:317`). Entering editing fades the compose button out
over 0.3 s (`.mm:1030-1033`), and `updateLeftBarItem:` is bounced through the companion because the button
actually lives on the tab controller's bar
(`TGTelegraphDialogListCompanion.mm:90-93`).

The per-row editing is *not* UIKit's. `editingStyleForRowAtIndexPath:` returns `None` (`.mm:1493-1496`);
the delete control is drawn by the cell itself, a 61 × 31 button at
`(width - 10 - 61, 20)` with a 90 × 71 shadow view (`TGDialogListCell.m:476`, `:489`). The controller
learns about it through ActionStage actions (`.mm:1622-1699`):

- `setFocusCell` — a cell has opened its delete control; the table takes it as `focusCell`, which
  disables scrolling and installs a hit-test that swallows every touch outside that cell's buttons
  (`.mm:73-122`), dismisses the control, and sets `_ignoreTouches` so the touch that closed the control
  does not also select a row (`.mm:105`, `:124-150`). It also flips the controller into editing mode
  without putting the table into `setEditing:` (`.mm:1697-1698`) so the Edit button reads "Done".
- `conversationMenuOpened` — dismiss every other cell's controls and clear selection/highlight.
- `conversationDeleteRequested` — for a **group chat**, show a `UIActionSheet` with
  `DialogList.ClearHistoryConfirmation`, a destructive `DialogList.DeleteConversationConfirmation` and
  `Common.Cancel`, presented in `self.navigationController.view` (`.mm:1678-1683`). For a one-to-one chat
  there is **no confirmation at all** — it deletes immediately (`.mm:1685-1686`).

Scrolling anywhere dismisses all open editing controls (`.mm:1389-1403`).

## 7. Search

Search is a `TGSearchDisplayMixin` over the same controller, not a `UISearchDisplayController`
(`.mm:523-525`, `:1546-1585`). The mixin creates a second table whose delegate and data source are still
this controller, which is why every table callback in the class begins with `if (tableView == _tableView)`.

- Scope bar: `@[@"Conversations", @"Messages"]`, added only when not in forward mode (`.mm:527-528`).
  Note these two strings are **hardcoded English**, unlike everything else on the screen.
- Query changes go straight to `[_dialogListCompanion beginSearch:inMessages:]` (`.mm:1565-1571`); an
  empty query hides the results table rather than showing an empty list (`.mm:1569-1570`,
  and again on the reply path at `.mm:985`).
- Results are heterogeneous: `TGConversation`, `TGUser` or `TGMessage`, dispatched by class both when
  building cells (`.mm:1229-1237`) and when handling taps (`.mm:1082-1097`). A conversation carrying
  `additionalProperties[@"searchMessageId"]` opens the chat *at that message* (`.mm:1085-1086`).
- Activating search hides the navigation bar and freezes the main table's scrolling
  (`.mm:1573-1585`).
- Leaving the screen while search is active and the scope is Conversations closes search silently
  (`.mm:733-734`).
- `searchResultSelectedMessage:` is an empty method in the shipped companion
  (`TGTelegraphDialogListCompanion.mm:174-177`) — tapping a raw message result did nothing in 1.1.

## 8. Lifecycle housekeeping (cheap to skip, visible when you do)

- `viewDidAppear:` calls `[_dialogListCompanion wakeUp]` and restarts every visible cell's animations
  (`.mm:691-710`).
- `viewDidDisappear:` (animated only) dismisses editing controls and **stops** cell animations
  (`.mm:717-738`).
- `UIApplicationSignificantTimeChangeNotification` → `resetView:true` on every visible cell
  (`.mm:781-791`). This is what makes "22:14" become "Yesterday" at midnight without a reload.
- background → `stopAnimations`, foreground → `restartAnimations:true` on visible cells
  (`.mm:793-815`), so typing dots do not burn CPU in the background.
- `scrollToTopRequested` scrolls to `-contentInset.top`, i.e. to the search bar (`.mm:333-336`).
- `shouldAutorotateToInterfaceOrientation:` allows everything except upside-down (`.mm:740-743`).
- The iOS 5 branch in `scrollViewDidEndDragging/DidEndDecelerating` snaps the search bar fully open or
  fully closed at a 15 pt threshold (`.mm:1410-1462`); on iOS 6 (`iosMajorVersion() >= 6`) it is dead code.
  We can ignore it.

## 9. Our port, judged

Ours is `TGChatListViewController`, one 4098-line file that contains the controller, the cell, the swipe
machinery, the story tray, folders and the archive row. Structurally very different (no companion, no
ActionStage; a `TGClient` with block callbacks). That is fine and not worth relitigating. The visible
differences are:

### Defects worth fixing

1. **No overscroll header colour.** The original paints a 480 pt `0xe4e9f0` block above the content
   (`.mm:492-495`, `TGInterfaceAssets.mm:177`). `TGChatListViewController.m` has no such view — grep for
   `e4e9f0` returns nothing. Pull the list down on our build and you get white. Fix: add a
   `UIView` at `(0, -480, w, 480)` with `0xe4e9f0` as `tableView` subview in `styleListTable`
   (near `TGChatListViewController.m:1216`), themed for dark.

2. **Selection is dropped on tap instead of on return.** `TGChatListViewController.m:4054` calls
   `deselectRowAtIndexPath:animated:YES` as the first line of `didSelectRowAtIndexPath:`. The original
   keeps the row selected through the push and deselects in `viewWillAppear:` after a core-count-dependent
   delay (`.mm:618-640`). Result on our build: the blue plate blinks off before the push animation starts.
   Fix: remove the deselect from `didSelectRow`, and in `viewWillAppear:`
   (`TGChatListViewController.m:1456-1458`) deselect after `dispatch_after` 0.05 s (the 4S is dual-core).

3. **No double-tap guard.** The original's `static bool canSelect` (`.mm:1049-1059`) exists precisely
   because a slow push lets a second tap through. Ours has none
   (`TGChatListViewController.m:4053`), so two quick taps push two `TGChatViewController`s.
   Fix: copy the one-per-runloop guard verbatim.

4. **Selected plate is not offset by −1.** The original sets the selected background view to
   `CGRectMake(0, -1, w, h + 1)` on every reset (`TGDialogListCell.m:1264`, and repeatedly at `:551`,
   `:570`, `:579`) so the highlight swallows the hairline above the row, and uses
   `TGHighlightImageView`, not `UIImageView` (`.mm:1260`). Ours does neither
   (`TGChatListViewController.m:384-385`); a pressed row shows a one-pixel seam at its top edge. We already
   have `src/TGHighlightImageView.m` — it is simply not used here.

5. **No "load more" row and a much later trigger.** The original starts loading 10 rows from the end
   (`.mm:1469`) and shows a 50 pt spinner row while `canLoadMore` (`.mm:1125`, `:1277-1294`). Ours triggers
   only when the scroll offset is within two row heights of the bottom
   (`TGChatListViewController.m:2487`) and never shows a spinner — the list just stops at the bottom until
   more arrives. Fix: change the trigger to an index-based one in `willDisplayCell:` and add the trailing
   spinner row.

6. **No significant-time-change observer.** The original re-renders every visible cell on
   `UIApplicationSignificantTimeChangeNotification` (`.mm:781-791`). Ours registers no such observer (grep
   in `TGChatListViewController.m` finds none), so timestamps read "23:58" past midnight until some other
   event forces a reload. Cheap to add next to the theme observer
   (`TGChatListViewController.m:1274`).

7. **Empty state hides nothing.** The original hides the whole table when the list is empty
   (`.mm:927`) and puts the placeholder *behind* it (`.mm:890`), so the search bar disappears too. Ours
   adds the placeholder as a subview of the table (`TGChatListViewController.m:1513`) and leaves the table
   — and therefore the search bar and the story tray — on screen. It also lacks the
   `shouldDisplayEmptyListPlaceholder` gate (`.mm:928-929`,
   `TGTelegraphDialogListCompanion.mm:182-185`): during first sync we show "You have no conversations yet"
   where the original shows white. The layout numbers themselves (250 width, 232 wrap, 21 and 8 gaps,
   `0x8b97a5`, bold-15 / regular-14) are correct — `TGChatListViewController.m:1486-1512` and `:1553-1577`
   match `.mm:889-919` exactly. Good work; only the visibility rules are wrong.

8. **Compose button has no landscape variant and a hardcoded 30 × 30 frame.**
   `TGChatListViewController.m:1266-1271` versus `.mm:410-415`, which sizes to fit and swaps in
   `ComposeMessageIcon_Landscape.png` when the bar shortens. On a 4S in landscape our icon sits in a
   taller-than-bar button.

9. **Compose fade is instant.** `TGChatListViewController.m:1302` sets `alpha` directly; the original
   animates it over 0.3 s when editing toggles (`.mm:1030-1033`).

10. **Done button is bold Edit, not a Done-style button.** `TGChatListViewController.m:1296-1297` renders
    "Done" as the same generic button with `bold:YES`; the original uses `TGToolbarButtonTypeDone`
    (`.mm:317`), which in 2013 was the filled blue plate. Whether we have that artwork is worth checking
    before changing.

11. **Title status container is 200 pt wide, original is 40** (`TGChatListViewController.m:1377` vs
    `.mm:262`), and ours uses a real `UIActivityIndicatorView` with style `White` (20 pt,
    `TGChatListViewController.m:1390-1391`) where the original uses the 15 pt `RProgress` sprite animation
    (`TGActivityIndicatorView.m:38-52`). The label styling is otherwise an exact match — bold 15, white,
    shadow `0x415a7e` at (0,−1), spinner 5 pt left and 3 pt down
    (`TGChatListViewController.m:1381-1404` vs `.mm:265-272`, `:345-346`).

12. **Status is shown whenever `connectionText` is non-empty**
    (`TGChatListViewController.m:1412-1414`), while the original shows it only when `isLoading` is true
    (`.mm:284-289`, `:342`). If our client ever sets a connection string in the connected state we will
    show a spinner forever.

### Where ours is right

Row height 73 (`TGChatListViewController.m:26`), avatar 56 at x = 8 (`:27-28`), text column at 73 (`:29`),
the swipe button 61 × 31 at top 20 (`:31-34`), the plate images stretched leftCap 1 / topCap 0
(`:380-383`), the palette `0x111111` title / `0x888888` preview / `0x536c8c` action / `0x345f8f` author
(`:37-65`) — all match `TGDialogListCell.m:193-196`, `:369-406`, `:476-489`, `:791-793` and
`TGDialogListController.mm:1137-1138`. The unread badge stretchable construction (`:94-104`) matches the
assets-source contract. The empty-state metrics match, as noted above.

### Deliberate divergences, not defects

- Our search bar is a *doorway*: touching it pushes `TGSearchViewController`
  (`TGChatListViewController.m:2358-2362`) instead of activating an in-place mixin with a
  Conversations/Messages scope bar. That is the modern interaction model, which is what this project is
  for. Worth noting only so nobody "fixes" it back.
- Archive row, folders strip, story tray and login banner all live in a composite `tableHeaderView`
  (`TGChatListViewController.m:1601-1645`). The original had none of these. See §10 — twelve solved the
  archive row differently.
- Separators: we re-enable `SingleLine` for dark/imported themes
  (`TGChatListViewController.m:3628-3634` region, `applySeparatorStyle`), because the 2013 plate art is
  light-only. Correct call.

## 10. What became of it

### twelve (`/Users/alexanderhavrysh/Git/iOS/twelve/legacy/TelegraphKit/TGDialogListController.mm`, 4992 lines)

Same class name, same companion split, same ActionStage — and roughly three times the size. What the extra
lines bought:

- **Row height 73 → 76** (`twelve:2423`), and the table gains sections: section 0 is a 45 pt row
  (`:2416-2417`) and an archive header item is 54 pt (`:2419-2421`). The archive lives *in the list* as a
  typed item, not in a header view as in ours.
- The overscroll header survives, renamed `_searchTopBackgroundView`, shrunk from 480 to 320 pt and moved
  to `insertSubview:atIndex:0` with a palette colour instead of a hardcoded one
  (`twelve:1125-1127`) — the same idea, now themeable. That the concept survived to a 2018-era fork is a
  strong argument for fixing our defect 1.
- **The scope bar is gone.** `_searchBar` is created with a style and a pallete
  (`twelve:1120-1121`) and there is no `scopeButtonTitles` anywhere in the file. Search results became
  sectioned (`_searchResultsSections`, `twelve:2429`) with recent-peer rows
  (`TGDialogListRecentPeersCell`) instead of two flat scopes. Forced by features: a two-way segmented
  control cannot carry chats + contacts + messages + recent.
- Search starts hidden: `resetInitialOffset` and an `atTop` check against the header height
  (`twelve:3504`, `:1155`), i.e. pull-to-search. In 2013 the search bar was simply visible at the top.
- Separators come back for iOS 7+ with `separatorInset` 80 pt (`twelve:1141-1146`), because the plate
  artwork was retired for a flat palette.
- The title grew its own view class, `TGDialogListTitleContainer` (`twelve:351`, `:1038`), instead of the
  ad-hoc `UIView` + label + spinner built inline in 2013; and `titleStateUpdated:state:` takes a
  `TGDialogListState` enum instead of a bare `isLoading` bool (`twelve/…/TGDialogListController.h:54`).
  Forced: "Connecting", "Updating", "Waiting for network" and proxy states cannot be encoded in a bool.
- New public surface for features that did not exist: `startSearch`, `isDisplayingSearch`,
  `customSearchPlaceholder`, `presentation`, `selectConversationWithId:`, `updateDatabasePassword`,
  `requestSavedMessagesTooltip` (`twelve/…/TGDialogListController.h:26-59`).

### Telegram-iOS today (`submodules/ChatListUI`)

- **The row height is computed, not declared.** `Node/ChatListItem.swift:4036-4048` builds it from measured
  text layout and `presentationData.fontSize`. Forced by Dynamic Type; a fixed 73 is impossible once the
  user can change the text size. Our fixed 73 is correct *for us* precisely because we do not support that.
- The title-status idea is intact and generalised: `NetworkStatusTitle(text:activity:hasProxy:…)`
  (`ChatListController.swift:7183-7213`), still a text plus a spinner in the navigation bar, still driven
  by connection state. Thirteen years and the design did not move.
- `titleStateUpdated:isLoading:` became a state machine over `State_Connecting`,
  `State_ConnectingToProxy`, `State_WaitingForNetwork`, `State_Updating`
  (`ChatListController.swift:7202-7213`) — the same generalisation twelve made.
- The empty state became its own node with variants (`ChatListEmptyNode.swift`); the 2013 version was a
  single hardcoded icon+two-labels stack.
- Search became a whole subtree (`ChatListSearchContainerNode`, `ChatListSearchPaneContainerNode`,
  pane-per-category) — the scope bar's descendants. Our push-a-search-page approach is closer to this than
  to the 2013 mixin, which is the right call for the interaction half of this project.
- Editing mode with an Edit button in the left bar is gone entirely, replaced by long-press context menus
  (`ChatContextMenus.swift`) and multi-select. This is the biggest behavioural break, and it is a change of
  platform convention (peek/pop, then context menus) rather than a new feature. Our port already carries
  both: swipe actions plus a long-press (`TGChatListViewController.m:1247-1249`).

## 11. Ambiguities I could not resolve from the source

- `TGDialogListMessageSearchCell.m` is 21 lines and appears to be a stub in this build; the Messages scope
  visibly reuses the 73 pt `TGDialogListCell` (`.mm:1356-1381`), so the "message search cell" as a distinct
  visual is not exercised in v1.1.
- The `_preparedCellQueue` warm-cell pool (`.mm:184`, `:1249-1253`, `:1363-1367`) is read but never filled
  anywhere in this source drop. It looks like a dead optimisation hook; do not port it.
- The 480 pt height of the overscroll header is unexplained — it is exactly one 3.5" screen height, so it
  is almost certainly "tall enough that you cannot rubber-band past it", not a measured value. Any height
  greater than the maximum overscroll works.

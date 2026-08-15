# TGSettingsController (original, Telegram for iOS v1.1 build 21024)

**Original files**
- `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGSettingsController.h` (16 lines)
- `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGSettingsController.m` (566 lines)

---

## 0. The most important thing about this class: it is not the Settings screen

The name is a trap, and it is worth stating before any metric.

`TGSettingsController` in the 2013 source is **the internal debug console**. It is not the screen a
user reaches by tapping the third tab. Three independent pieces of evidence:

1. **Every user-visible row inside it is a hard-coded English debug string, never localized.**
   `@"Session: 0x%llx"` (`TGSettingsController.m:55`), `@"Debug session"` (`:59`),
   `@"Show message IDs"` (`:68`), `@"Don't read"` (`:77`), `@"Don't jump in dialogs"` (`:83`),
   `@"Disable background mode"` (`:88`), `@"State update fails: %d"` (`:97`), `@"Salt fails: %d"`
   (`:100`), `@"Clear other sessions"` (`:103`), `@"Clear item uri cache"` (`:113`),
   `@"Clear asset cache"` (`:117`), `@"Clear avatar list cache"` (`:121`), `@"Clear both caches"`
   (`:125`), `@"Clear memory cache"` (`:129`), `@"Clear video cache"` (`:133`), `@"Send logs"`
   (`:138`). Compare with `TGNotificationSettingsController.m:181`, which uses
   `TGLocalized(@"Notifications.ResetAllNotifications")` for a real user-facing row. Only the
   navigation-bar title is localized, `NSLocalizedString(@"Settings.Title", @"")`
   (`TGSettingsController.m:155`), resolving to `"Settings"` (`Telegraph/Telegraph/en.lproj/Localizable.strings:536`).
   That single localized title is what makes the class look user-facing; it is the only such string.

2. **Its only entry point is compiled out of App Store builds.** The one and only construction site
   in the whole tree is `TGNotificationSettingsController.m:960`,
   `[self.navigationController pushViewController:[[TGSettingsController alloc] init] animated:true]`,
   invoked from `- (void)debugButtonPressed` (`TGNotificationSettingsController.m:958`). The row that
   calls it is a plain `TGActionMenuItem` titled `@"Debug"` in a section with **no header title**
   (`TGNotificationSettingsController.m:170-175`), and that whole block sits inside
   `#if defined(DEBUG) || defined(INTERNAL_RELEASE)` … `#endif` (`:169`, `:176`). In a public
   release build the screen is unreachable. `TGProfileController.m:54`,
   `TGChatSettingsController.m:30` and `TGTimelineController.mm:13` `#import` the header but never
   instantiate it (verified by grepping `TGSettingsController alloc` across the tree — the
   `TGNotificationSettingsController.m:960` hit is unique).

3. **Almost all of its own content is additionally `#ifndef EXTERNAL_INTERNAL_RELEASE`-gated**
   (`TGSettingsController.m:49-106` for the Security and Account sections, `:112-136` for six of the
   seven Misc rows). In an "external internal release" build only one section survives — `Misc` with
   a single `Send logs` row.

**The screen a 2013 user called "Settings" is `TGProfileController` initialised with uid 0.**
`TGAppDelegate.mm:293` builds
`_myAccountController = [[TGProfileController alloc] initWithUid:0 preferNativeContactId:0 encryptedConversationId:0]`
and `TGAppDelegate.mm:298` installs it as the third of three tabs
(`[NSArray arrayWithObjects:_contactsController, _dialogListController, _myAccountController, nil]`).
The tab's artwork is `TabIconSettings.png` / `TabIconSettings_Highlighted.png`
(`TGMainTabsController.m:70`). So in 2013 the Settings tab *was* your own profile — exactly the
arrangement the modern client still uses (see §7). Anyone porting "the 2013 Settings screen" must
study `TGProfileController`, not this file.

Our repo names its user-facing screen `TGSettingsViewController`, which collides with this class by
name only. §6 judges that honestly.

---

## 1. What it is for

A single grouped table of developer switches and one-shot maintenance actions, driven by the
generic `TGMenuSection`/`TGMenuItem` model that the whole 2013 settings family shares. It is the
smallest complete example of that model in the codebase — 566 lines, two item types, no server
state, no `ASWatcher` subscriptions except one fire-and-forget actor — which makes it the best
reference for *how the menu framework itself is meant to be used*, even though its content is
throwaway.

## 2. Public surface

```objc
@interface TGSettingsController : TGViewController <ASWatcher>
@property (nonatomic, strong) ASHandle *actionHandle;
@end
```
(`TGSettingsController.h:13-16`)

There is no designated initialiser beyond `-init`; `-init` calls
`[super initWithNibName:nil bundle:nil]` (`TGSettingsController.m:42`). The entire section model is
built eagerly in `-init`, **not** in `-loadView` and **not** in `-viewWillAppear`. Consequence worth
knowing: the values shown in the debug switches and the two failure counters are snapshotted at
construction time and never refreshed. Push the screen twice and you get two different snapshots;
stay on it while `stateConsistencyFails` increments and the row keeps showing the old number. The
one exception is the session-id row, which is patched in place after a toggle (§5).

`actionHandle` is created as `[[ASHandle alloc] initWithDelegate:self releaseOnMainThread:true]`
(`:45`) and exists for exactly one purpose: it is handed to each `TGSwitchItemCell` as its
`watcherHandle` (`:290`) so the cell can call back without a strong reference cycle.

## 3. View, background and chrome

`-loadView` (`:151-168`):

- `self.titleText = NSLocalizedString(@"Settings.Title", @"")` (`:155`). `titleText` is
  `TGViewController`'s own navigation title property (`TGViewController.h:68`), not
  `UIViewController.title`.
- `self.backAction = @selector(performClose)` (`:156`), declared at `TGViewController.h:72`. The
  handler is a plain `popViewControllerAnimated:true` (`:182-185`) — i.e. it reproduces the default
  back behaviour explicitly, so the custom back button gets a target at all.
- `self.view.backgroundColor = [[TGInterfaceAssets instance] linesBackground]` (`:158`). That is
  **not a flat colour**: `-linesBackground` is
  `[UIColor colorWithPatternImage:[UIImage imageNamed:@"SettingsBackground.png"]]`, memoised with
  `dispatch_once` (`TGInterfaceAssets.mm:143-149`). The asset
  `Telegraph/Telegraph/Resources/SettingsBackground@2x.png` is **640 × 70 px @2x = 320 × 35 pt**, a
  horizontally-full-width, vertically-tiling ruled-paper texture. Because it is a pattern colour it
  tiles from the *view's* origin, and because the table view is added at `self.view.bounds` with the
  same origin the ruling lines up with the top of the content area.
- The table is `UITableViewStyleGrouped` (`:161`) with `backgroundColor = [UIColor clearColor]`
  (`:163`) so the pattern shows through. Under iOS 6 a grouped table also has a
  `backgroundView`; the original does not nil it here, and relies on the clear background colour
  plus the fact that on iOS 6 `UITableViewStyleGrouped`'s default background view is the grey
  gradient — this is one of the few genuinely ambiguous points in the file. Sibling screens do the
  same thing (`TGNotificationSettingsController.m` uses the identical pattern), so whatever the
  visual result was, it was consistent across the settings family.
- `autoresizingMask` is `FlexibleWidth | FlexibleHeight` on both view and table (`:159`, `:162`), so
  rotation is handled purely by autoresizing. `-shouldAutorotateToInterfaceOrientation:` returns
  true for everything except upside-down portrait (`:187-190`); `-shouldAutorotate` returns true
  (`:192-195`).
- `-doUnloadView` (`:170-175`) nils delegate and dataSource before dropping the table — the 2013
  codebase's standard defence against a dangling table delegate during teardown. `-dealloc`
  (`:145-149`) resets the handle and removes the watcher from `ActionStageInstance()`.

## 4. Content model and geometry

### Sections (in order, full DEBUG build)

| # | `title` | `tag` | Rows |
|---|---|---|---|
| 1 | `@"Security"` (`:52`) | 1 (`:51`) | `Session: 0x%llx` (action, tag 1), `Debug session` (switch) |
| 2 | `@"Account"` (`:65`) | 0 | `Show message IDs`, [`Don't read`], `Don't jump in dialogs`, `Disable background mode` (switches); `State update fails: %d`, `Salt fails: %d`, `Clear other sessions` (actions) |
| 3 | `@"Misc"` (`:109`) | 0 | six `Clear …` actions, `Send logs` |

`TGMenuSection` is a bare value object: `int tag`, `NSString *title`, `NSMutableArray *items`
(`TGMenuSection.h:19-21`). `TGMenuItem` carries only `int type` and `int tag` (`TGMenuItem.h:13-14`);
the type constants are fourcc-ish magic numbers, e.g.
`#define TGActionMenuItemType ((int)0xD8B4CD4C)` (`TGActionMenuItem.h:11`). `TGActionMenuItem` adds
`NSString *title` and `SEL action` (`TGActionMenuItem.h:15-17`).

Conditional rows:
- `Don't read` is wrapped in `#ifndef DEBUG if (TGTelegraphInstance.clientUserId == 333000)`
  (`:73-81`) — in a release-flavoured internal build it appears only for one specific hard-coded
  account; in a DEBUG build the `if` is compiled away and it always appears.
- A `Logout` action row exists but is commented out (`:93-95`).

Section header titles are returned raw from `-tableView:titleForHeaderInSection:` (`:226-229`), so
they get iOS 6's stock grouped-header treatment (uppercased grey embossed text). Note the third
section header reads `Misc` — the section is never empty, because `Send logs` is outside every
`#ifdef`.

### Row height

`-tableView:heightForRowAtIndexPath:` (`:209-224`) returns **44** for
`TGActionMenuItemType`, `TGPhoneItemType` or `TGSwitchItemType`, and **0** for anything else,
including an out-of-range index path. 44 is not arbitrary: it is the height the grouped-cell artwork
and both cell classes are laid out against. In `TGActionMenuItemCell` the title label is
`CGRectMake(11, 12, width - 30, 20)` (`TGActionMenuItemCell.m:30`) — 12 above + 20 label + 12 below
= 44 exactly — with `[UIFont boldSystemFontOfSize:17]` (`:33`), whose 20 pt line box the 20 pt label
height is sized around. The disclosure arrow (`MenuDisclosureIndicator.png`, **18 × 32 px @2x =
9 × 16 pt**) is pinned at `y = 14` (`TGActionMenuItemCell.m:41`), i.e. (44 − 16) / 2 = 14, and
`x = width − arrowWidth − 11`, mirroring the 11 pt left inset.

Returning 0 rather than a fallback height is deliberate and load-bearing: `cellForRow` has a
matching fallback that produces a bare empty `UITableViewCell` (`:342-346`), so a row of an unknown
type collapses to nothing instead of showing a blank 44 pt band. This screen never exercises that
path, but the pattern is copied verbatim into the other settings controllers.

### Cell construction and the grouped artwork

`-tableView:cellForRowAtIndexPath:` (`:231-347`) is the interesting method. It does three things.

**(a) Dequeue by type.** Two identifiers, `@"AI"` for actions (`:257`) and `@"SI"` for switches
(`:277`). On first creation each cell is given a **fresh empty `UIImageView` as both
`backgroundView` and `selectedBackgroundView`** (`:263-266`, `:283-286`) whose `image` is assigned
later. This is the whole mechanism by which the 2013 app drew its own grouped-cell chrome instead of
UIKit's.

**(b) Configure.** Action cells get only `title` (`:271`). Switch cells get `title`, `isOn`, and
`itemId` set to the model object itself (`:295-298`) — the cell keeps a strong reference to the
`TGSwitchItem` and echoes it back in the change event, which is how the controller identifies which
switch fired without index paths. Switch cells also get
`selectionStyle = UITableViewCellSelectionStyleNone` (`:288`) and `watcherHandle = _actionHandle`
(`:290`), both **inside the `if (cell == nil)` creation block** — correct here because those two
values never vary per row, but a trap for anyone extending the class.

**(c) Position within the group.** `firstInSection` / `lastInSection` are computed at `:244-247` and
drive four branches (`:305-336`):

| Case | `setGroupedCellPosition:` | `setExtendSelectedBackground:` | normal image | highlighted image |
|---|---|---|---|---|
| only row | `First\|Last` | **false** | `groupedCellSingle` | `groupedCellSingleHighlighted` |
| first | `First` | true | `groupedCellTop` | `groupedCellTopHighlighted` |
| last | `Last` | true | `groupedCellBottom` | `groupedCellBottomHighlighted` |
| middle | `0` | true | `groupedCellMiddle` | `groupedCellMiddleHighlighted` |

`TGGroupedCellPositionFirst = 1`, `TGGroupedCellPositionLast = 2` (`TGGroupedCell.h:11-14`).

The artwork (`TGInterfaceAssets.mm:635-737`, assets in `Telegraph/Telegraph/Resources/`):

- `GroupedCellTop.png` / `GroupedCellMiddle.png` / `GroupedCellBottom.png` — **58 × 88 px @2x =
  29 × 44 pt**. The 44 pt height is the same 44 as the row height; the 29 pt width is stretched from
  its centre by `TGStretchableImageInCenterWithName` (`:638`, `:660`, `:684`).
- `GroupedCellSingle.png` — **52 × 88 px @2x = 26 × 44 pt** (`:706`). Narrower than the others
  because a single-row group has two rounded ends and no straight middle to trim.
- The `_Selected` variants are resized with explicit cap insets
  `UIEdgeInsetsMake(5, 13, 6, width - 13 - 1)` under `resizableImageWithCapInsets:resizingMode:`
  (`:648`, `:672`, `:715`) — 5 pt top cap, 13 pt left cap, 6 pt bottom cap, and a right cap that
  leaves exactly a 1 px stretchable column. Note the asymmetric 5/6: the highlight artwork is not
  vertically symmetric.
- `groupedCellBottomHighlighted` is the odd one out: its `resizableImageWithCapInsets:` branch is
  **dead code, guarded by `if (false && …)`** (`:692`), so it always falls through to
  `stretchableImageWithLeftCapWidth:(width/2) topCapHeight:1` (`:695`). Someone found the cap-inset
  version wrong for the bottom cap and disabled it rather than deleting it. Reproduce the
  `topCapHeight:1` behaviour, not the insets, for the bottom-highlighted image.

`extendSelectedBackground` is what makes the highlight cover the hairline *between* cells.
`TGGroupedCell` grows the selected background by 1 pt for a middle cell and for a first cell, and by
nothing for a last cell (`TGGroupedCell.m:3-15`), applied on selection, on highlight, when the flag
changes, and in `layoutSubviews` (`:33-48`, `:50-65`, `:67-85`, `:114-124`). It also calls
`-adjustOrdering` (`:87-112`), which walks the table's subviews and re-inserts the highlighted cell
above every other `UITableViewCell` — otherwise the neighbouring cell's opaque background art would
clip the 1 pt overhang. That is a real behaviour a reimplementation must have: without the
re-ordering the highlight looks 1 pt short at the bottom edge.

The single-row case sets `extendSelectedBackground:false` because there is no neighbour to bleed
into.

## 5. Behaviour

### Tap

`-tableView:didSelectRowAtIndexPath:` (`:349-383`):

- **Action item** → `if ([self respondsToSelector:actionItem.action]) [self performSelector:actionItem.action]`
  (`:369-370`, ARC leak warning suppressed at `:367-371`), then
  `deselectRowAtIndexPath:animated:true` (`:373`). The `respondsToSelector:` guard is why rows with
  no action at all — `Session: 0x…`, `State update fails:`, `Salt fails:` — are safe: their `action`
  is a nil `SEL`, `respondsToSelector:nil` is false, nothing happens, and the row still flashes and
  deselects. So those three rows are read-only labels that nevertheless highlight on touch. That is
  the original behaviour; do not "fix" it into non-selectable rows.
- **Switch item** → the model is toggled first (`:378`), then the cell is told
  `setIsOn:animated:true` (`:379`) and then `fireChangeEvent` (`:380`). Both messages go to
  `[tableView cellForRowAtIndexPath:]`, which returns nil for an off-screen row — harmless here
  since you can only tap a visible row.

The switch cell also handles its own touches: `TGSwitchItemCell` installs a
`UITapGestureRecognizer` on itself (`TGSwitchItemCell.m:44`) that flips the switch with
`setOn:!isOn animated:true notifyOnCompletion:true` (`:98`). Combined with
`UITableViewCellSelectionStyleNone` (`TGSettingsController.m:288`), a tap anywhere on a switch row
animates the switch and never shows a selection highlight. Because the tap recognizer fires *and*
`didSelectRowAtIndexPath:` fires, the row is toggled by two independent paths; the model stays
consistent because `fireChangeEvent` carries the switch view's own resulting `isOn` value
(`TGSwitchItemCell.m:90`), which the controller then writes back into the model rather than
inverting it again.

### The change callback

`-actionStageActionRequested:options:` (`:546-564`) is the single funnel for switch changes. It
matches `@"toggleSwitchItem"`, pulls `itemId` and `value` out of the options dictionary, writes
`switchItem.isOn = [nValue boolValue]`, and then performs `switchItem.action` — again behind a
`respondsToSelector:` guard. Each of the four `-switch…` handlers reads the *global* state and
inverts it independently (`:508-526`), e.g.
`[TGConversationMessageItemView setDisplayMids:![TGConversationMessageItemView displayMids]]`
(`:510`). It does **not** read `switchItem.isOn`. If the model and the global ever disagree, the
global wins and the row goes out of sync until the screen is rebuilt. Real bug in the original;
worth knowing before copying the pattern.

The one handler that does more is `-switchDebugSession` (`:471-506`). It hops to the ActionStage
queue, flips the session by testing whether bits 48–63 of the current generic session id equal
`0xabcd` (`:475`, matching the initial `isOn` computation at `:60`), then hops back to the main queue
and hand-patches the display: it scans `_sectionList` for the section with `tag == 1`, then that
section's item with `tag == 1`, rewrites its `title` to the new `Session: 0x%llx`, and if the cell
is currently on screen calls `setTitle:` on it directly (`:492-496`). No `reloadData`, no
`reloadRowsAtIndexPaths:`. This is the tag-lookup idiom the larger settings screens use everywhere
(`TGNotificationSettingsController.m` has a whole `-findMenuItem:sectionIndex:itemIndex:` helper,
used at `:930`, `:935`, `:948`); here it is inlined.

### Actions

- `revokeButtonPressed` (`:392-395`) → `requestActor:@"/tg/service/revokesessions"`. The completion
  (`:528-544`) only writes to the log — **no alert, no spinner, no confirmation, success and failure
  are visually identical**. `TGLog(@"===== Other sessions revoked")` vs
  `TGLog(@"***** Failed to revoke other sessions")`.
- The five cache-clearing rows are synchronous one-liners with no feedback whatsoever
  (`:397-422`): `clearServerAssetData`, `rm -r Documents/assets`, `clearPeerProfilePhotos`,
  `[[TGRemoteImageView sharedCache] clearCache:TGCacheBoth]`, `…clearCache:TGCacheMemory`.
- `clearVideoCacheButtonPressed` (`:424-436`) is the only one that goes off the main thread:
  `dispatch_async([TGCache diskCacheQueue], …)` and deletes every file under `Documents/video`
  whose name has the prefix `@"remote"`. The prefix filter is the point — locally recorded videos
  survive.
- `sendLogsButtonPressed` (`:438-464`) is the only row with any UI. If
  `[MFMailComposeViewController canSendMail]`, it builds a composer with subject
  `@"Logs from %@ (%@)"` filled with the client user's `displayName` and `[NSDate date]` (`:447`),
  body `@"Application logs"` (`:448`), one `text/plain` attachment per packed log named
  `application-%d.log` starting at 0 (`:450-454`), and recipient `logs@telegram.org` (`:456`).
  Otherwise it shows a `UIAlertView` with **no title**, message
  `@"Please configure at least one email account"`, and cancel button `TGLocalized(@"Common.OK")`
  (`:462`). Note the mismatch: the alert's button is localized, its message is not.
  `-mailComposeController:didFinishWithResult:error:` ignores both result and error and just calls
  `dismissModalViewControllerAnimated:true` (`:466-469`).

### Empty, long and missing content

- **Long titles.** Neither cell wraps or truncates deliberately. `TGActionMenuItemCell`'s label is
  `width - 30` wide with `numberOfLines` left at the default 1, so a long action title tail-truncates
  with an ellipsis at 30 pt short of the cell width. `TGSwitchItemCell`'s label is
  `width - 28 - switchWidth` (`TGSwitchItemCell.m:36`), and the switch is 77 × 27 pt
  (`TGSwitchView.m:59`), so the switch-row title has roughly 105 pt less room than an action-row
  title and truncates much earlier. On a 320 pt screen inside a grouped table that is a title budget
  of about 180 pt at bold 17 — roughly 18 characters. `Disable background mode` (`:88`) is right at
  that limit and is very likely the reason no longer debug label exists in the file.
- **Empty section.** A section with zero items renders as a header with nothing under it; nothing
  guards against it. In practice `#ifdef` combinations can leave the Security and Account sections
  empty — under `EXTERNAL_INTERNAL_RELEASE` they are not even created (`:49`, `:106`), so the case
  does not arise here.
- **Missing values.** `Session: 0x%llx` and the two `%d` counters always format something; there is
  no "unknown" state. `displayName` in the mail subject can be nil, in which case `%@` renders
  `(null)` into the subject line — unhandled.
- **Out-of-range index paths** are handled defensively in all four table methods
  (`:211-214`, `:237-240`, `:353-357`) except `-tableView:titleForHeaderInSection:` (`:226-229`),
  which indexes `_sectionList` unguarded.

## 6. Our port — honest judgement

**There is no port of this class, and that is the right call.** Nothing in
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src` corresponds to the 2013 debug console: grepping
`Debug`, `Send logs` and `logs@telegram` across `TGSettingsViewController.m` and
`TGStorageViewController.m` yields only two unrelated "Clear cache" strings in
`TGStorageViewController.m:1369` and `:1398`. A shipping legacy client does not need Peter
Iakovlev's 2013 session-id inspector.

The name collision is nevertheless worth flagging, because it invites exactly the wrong comparison:

- `src/TGSettingsViewController.m` (5148 lines) is our **user-facing** Settings screen — the modern
  client's Settings, paged through a `TGSettingsPage` enum with Appearance, Data and Storage,
  Notifications, Privacy and Security, Language, Blocked Users and more
  (`TGSettingsViewController.m:1123-1150`). Its correct 2013 counterpart is `TGProfileController`
  (uid 0), per `TGAppDelegate.mm:293`, plus the topic-specific 2013 screens
  `TGChatSettingsController`, `TGNotificationSettingsController` and `TGPrivacySettingsController`.
  Judging it against `TGSettingsController` would be a category error. **Anyone auditing our
  Settings screen must read `ctrl-TGProfileController` / the notification-settings study, not this
  one.**

Two things this study does say about our port, both real and both visible to a user:

1. **We use stock UIKit grouped chrome; the original never did.** Ours is
   `[super initWithStyle:UITableViewStyleGrouped]` (`src/TGSettingsViewController.m:154`, `:1076`)
   with no `GroupedCell*.png` anywhere in the file (grep for `GroupedCell` in
   `src/TGSettingsViewController.m` returns nothing). The original assigned
   `groupedCellTop/Middle/Bottom/Single` plus their highlighted variants as cell
   `backgroundView`/`selectedBackgroundView` images on **every** settings screen
   (`TGSettingsController.m:310-335`; `TGNotificationSettingsController.m` does the same). The
   user-visible consequences are the 1 pt highlight bleed between adjacent rows
   (`TGGroupedCell.m:3-15`) and the `adjustOrdering` z-reordering during highlight
   (`TGGroupedCell.m:87-112`), neither of which stock UIKit reproduces: with stock cells the
   highlight stops one hairline short at each internal boundary. **To fix:** adopt the
   `TGGroupedCell` mechanism — an image-view background/selected-background pair, the four-way
   first/middle/last/single image assignment, `extendSelectedBackground` true except for
   single-row groups, and the `topCapHeight:1` special case for the bottom-highlighted image
   (`TGInterfaceAssets.mm:692-695`).
2. **The `SettingsBackground.png` pattern is right, and applied in the right place.** Ours sets
   `self.tableView.backgroundColor = [UIColor colorWithPatternImage:tile]` for the root page in
   light theme (`src/TGSettingsViewController.m` `applyTheme`, around the `SettingsBackground.png`
   lookup), the original set the same pattern on `self.view` with a clear table
   (`TGSettingsController.m:158`, `:163`). Same 320 × 35 pt tile, same visual result; ours also
   correctly restricts it to the light theme. Fine as is.

Our row heights match: we return 44 as the general case (`src/TGSettingsViewController.m:2890`) and
use `boldSystemFontOfSize:17` for row titles throughout (e.g. `:2503`, `:2605`, `:2903`), which is
the original's cell font (`TGActionMenuItemCell.m:33`, `TGSwitchItemCell.m:38`). Our 45 pt logout
and photo rows and 64 pt suggestion rows (`:2885-2888`) have no 2013 counterpart because those
features did not exist; not a defect.

Separately: our switches are stock `UISwitch` (`src/TGSettingsViewController.m` `notificationSwitchOn:tag:`),
where the original used a fully custom 77 × 27 pt `TGSwitchView` built from `SwitchBackground.png`,
`SwitchBlue.png`, `SwitchOnText.png`, `SwitchOffText.png`, `SwitchBlueTransition.png`,
`SwitchShadow.png`, `SwitchMask.png` and `SwitchBulb.png` (`TelegraphKit/TelegraphKit/TGSwitchView.m:59`,
`:70-107`). On iOS 6 the stock switch is visually close (it also carries ON/OFF text), so this is a
low-severity difference, and it belongs to whoever studies `TGSwitchView` — noted here only because
this controller is the switch's most-cited call site.

## 7. What became of it

**Modern client.** The concept survives intact and even the *content* rhymes; only the way in is
different.

- The screen is `submodules/DebugSettingsUI/Sources/DebugController.swift`, 1804 lines, built as
  `ItemListNodeState(… style: .blocks)` (`DebugController.swift:1723`) — the AsyncDisplayKit
  descendant of exactly the section/item model `TGMenuSection` embodied here. `debugControllerEntries(…)`
  (`:1540`) is the direct descendant of the `-init` body at `TGSettingsController.m:49-141`: an
  eagerly-built array of typed entries rather than a hand-populated `NSMutableArray`.
- **The `#ifdef DEBUG` row was replaced by a gesture.** `TabBarController` counts taps on a tab item
  within 0.4 s windows (`submodules/TabBarUI/Sources/TabBarController.swift:131`, `:164-173`) and at
  **ten** taps fires `tabBarItemDebugTapAction` (`:175-178`). `TelegramRootController.swift:233-237`
  attaches that action to the Settings tab and pushes `debugController(…)`. This is a change forced
  by shipping: a compile-time gate means the debug screen cannot exist in a release build at all, so
  support and QA cannot reach it on a user's device. A ten-tap gesture is present in every build and
  discoverable by nobody. Same intent, better delivery.
- The 2013 Settings-tab-is-your-profile arrangement is unchanged after thirteen years:
  `TelegramRootController.swift:232` builds the Settings tab as
  `PeerInfoScreenImpl(… peerId: self.context.account.peerId, isSettings: true)` — precisely
  `TGProfileController initWithUid:0` (`TGAppDelegate.mm:293`) in Swift. Strong evidence that the
  2013 structure was right and should be preserved in our port.
- The debug screen is also reachable pre-login, from the phone-entry screen
  (`submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift:151`,
  presented modally) — a capability 2013 lacked entirely, since the only door was buried inside
  Notification Settings, which requires an account.

**twelve** (`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGSettingsController.m`, 641 lines).
The fork kept the class verbatim in structure — same `TGMenuSection` model, same two cell classes,
same `return 44` (`twelve/…/TGSettingsController.m:204`), same four-way grouped-artwork assignment
(`:295-320`) — and grew it by accretion:

- New rows appended to the existing sections: `Clear channels` (`:84`), `Clear chat list cache`
  (`:104`), `Send more logs` (`:121`), `Send data` (`:125`). Every one is a new *feature* needing a
  new debug lever (channels, a chat-list cache, richer log export) — forced changes, not taste.
- `Show message IDs` demoted from a `TGSwitchItem` to a `TGActionMenuItem` (`:63-65`) — the
  underlying setting stopped being a simple boolean.
- `Debug session`, the session-id row and its whole `switchDebugSession` tag-patching dance are
  **gone**, as are `Don't read`, the two failure counters and `Clear other sessions`. The network
  stack they inspected was rewritten.
- One change of taste, and it matters for us: `self.view.backgroundColor = [UIColor whiteColor]`
  (`twelve/…/TGSettingsController.m:144`) replaces the original's
  `[[TGInterfaceAssets instance] linesBackground]` pattern (`TGSettingsController.m:158`). The
  ruled-paper texture was abandoned when iOS 7 flattened everything. For our 2013-skinned client the
  original's pattern is the correct choice, not twelve's white.
- The title became `TGLocalized(@"Settings.Title")` (`:146`) and the explicit
  `self.backAction = @selector(performClose)` was dropped — by then the navigation controller
  supplied its own back button.

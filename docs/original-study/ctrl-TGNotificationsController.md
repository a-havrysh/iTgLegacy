# TGNotificationsController — study of the original

## Naming note

There is no class called `TGNotificationsController` in Telegram for iOS v1.1 (build 21024).
The real class is **`TGNotificationSettingsController`**
(`Telegraph/Telegraph/TGNotificationSettingsController.h` / `.m`, 17 + 963 lines). Everything
below is about that class. Its companion, the sound picker it pushes, is
`TGCustomNotificationController` (`Telegraph/Telegraph/TGCustomNotificationController.h` / `.m`,
297 lines) and is documented here too, because the settings screen is not usable without it.

Do not confuse either with `TGNotificationWindow` / `TGMessageNotificationView`
(the in-app banner) — different component, different study.

All paths below are relative to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
unless stated otherwise.

---

## 1. What it is for

A single pushed screen holding the account-wide notification defaults, split into three
concerns that the 2013 app kept deliberately separate:

1. **server-side settings for the "all private chats" pseudo-peer** — peer id `INT_MAX - 1`;
2. **server-side settings for the "all groups" pseudo-peer** — peer id `INT_MAX - 2`;
3. **device-local in-app behaviour** — sound, vibration, banner, stored in `NSUserDefaults`
   through `TGAppDelegateInstance` and never sent to the server.

Plus a destructive "Reset All Notifications" that wipes every per-chat override.

Only one call site exists in the whole app:

```
TGProfileController.m:3420-3423   - (void)notificationsButtonPressed
    [self.navigationController pushViewController:
        [[TGNotificationSettingsController alloc] init] animated:true];
```

So it is reached exactly one way: **Settings (own profile) → Notifications**. It is never
presented modally, never used for a single chat (per-chat settings live in
`TGTelegraphConversationProfileController` / `TGProfileController` and use the same
`/tg/changePeerSettings` actor with a real peer id).

## 2. Public surface

The header is almost empty (`TGNotificationSettingsController.h:13-17`):

```objc
@interface TGNotificationSettingsController : TGViewController <ASWatcher>
@property (nonatomic, strong) ASHandle *actionHandle;
@end
```

`-init` is inherited (`NSObject`'s), overridden in the `.m` at line 80. There is no
configuration: the screen is entirely self-assembling. `actionHandle` is public only because
`ASWatcher` requires it; nobody outside touches it.

## 3. Structure — the model is built once, in `-init`

The screen is **not** a `cellForRow` switch. It builds an `NSArray` of `TGMenuSection`, each
holding `TGMenuItem` subclasses, in `-init` (lines 87-188), and the table view is a thin
renderer over that array. Item identity is carried by an `int tag` from the enum at
lines 34-46 (`TGDialogMessageNotifications = 1` … `TGAlwaysCheckNearbyComment`); `-findMenuItem:
sectionIndex:itemIndex:` (line 863) walks the two-level array to locate an item and its index
path when a value arrives from the network. This is the pattern to copy: **the model owns the
value, the cell is a projection, and updates go model → find → live cell**, never
`reloadData`.

Sections, in order (line numbers are where each item is created):

| # | Section title (`en.lproj/Localizable.strings`) | Items |
|---|---|---|
| 0 | `Notifications.MessageNotifications` = "Message Notifications" (:90, str:548) | Switch "Alert" (:93, tag `TGDialogMessageNotifications`), Switch "Message Preview" (:98, tag `TGDialogMessagePreview`), Variant "Sound" (:103, tag `TGDialogMessageSound`), Comment (:110) |
| 1 | `Notifications.GroupNotifications` = "Group Notifications" (:114, str:554) | Switch "Alert" (:117), Switch "Message Preview" (:122), Variant "Sound" (:127), Comment (:134) |
| 2 | `Notifications.InAppNotifications` = "In-App Notifications" (:138, str:560) | Switch "In-App Sounds" (:141), Switch "In-App Vibrate" (:146), Switch "In-App Preview" (:151) — **no comment row** |
| 3 | *(DEBUG / INTERNAL_RELEASE only)* no title (:173) | Action "Debug" → pushes `TGSettingsController` (:170, :958) |
| 4 | no title (:178) | Red button "Reset All Notifications" (:181), Comment (:185) |

Note the **row order inside section 0/1 in the model is Alert, Preview, Sound**, but the
`updateNotificationSettingsItems` code reads them in the order Alert, Sound, Preview
(:895-924) — that is just traversal order, not display order. Display order is the array
order: Alert, Message Preview, Sound.

A fourth, **commented-out** "Location Services / People Nearby" section survives at
lines 156-167 with its own string keys (str:565-567). It was cut before this build; do not
port it.

Strings, verbatim (`en.lproj/Localizable.strings:547-573`):

- `Notifications.Title` = "Notifications" (nav title, set at :217)
- `Notifications.MessageNotificationsAlert` / `GroupNotificationsAlert` = "Alert"
- `…Preview` = "Message Preview"; `…Sound` = "Sound"
- `Notifications.MessageNotificationsHelp` = "You can set custom notifications for specific users in User Info"
- `Notifications.GroupNotificationsHelp` = "You can set custom notifications for specific groups in Group Info"
- `Notifications.InAppNotificationsSounds` / `Vibrate` / `Preview` = "In-App Sounds" / "In-App Vibrate" / "In-App Preview"
- `Notifications.ResetAllNotifications` = "Reset All Notifications"
- `Notifications.ResetAllNotificationsHelp` = "Undo all custom notification settings for all your contacts and groups"
- `Notifications.Reset` = "Reset"
- `Nofications.CustomSound.Title` = "Sound" (sic — the typo is in the original key)

## 4. View, metrics and colour — every number with a citation

`-loadView` (:211-234):

- `self.view.backgroundColor = [[TGInterfaceAssets instance] linesBackground]` (:215), which is
  `[UIColor colorWithPatternImage:[UIImage imageNamed:@"SettingsBackground.png"]]`
  (`TGInterfaceAssets.mm:143-152`). The screen is a **tiled skeuomorphic backdrop**, not a flat
  colour. Asset present as `Resources/SettingsBackground@2x.png`.
- Table is `TGActionTableView`, `UITableViewStyleGrouped`, full-bounds, flexible W/H,
  `separatorStyle = None`, `backgroundColor = clearColor`, `opaque = false`,
  `backgroundView = nil` (:220-230). Separators are *not* drawn by UIKit — they come baked into
  the grouped-cell artwork.
- `[_tableView enableSwipeToLeftAction]` (:221). In `TGActionTableView.m:129-148` this installs a
  `UISwipeGestureRecognizer` with direction **Right** and calls `performSwipeToLeftAction` on the
  delegate; here (:614-617) that pops the controller. **A right-swipe anywhere on the table goes
  back** — this predates UIKit's interactive pop by a year and is a real, felt behaviour of the
  2013 app.
- `self.backAction = @selector(performClose)` (:218), which pops (:609-612).

Heights and headers:

- Section header height: **46** when the section has a title, **8** when it does not
  (:314-322). The footer height is a constant **1** for every section (:333-336).
- Header view (`-generateSectionHeaders`, :261-290): a bare `UIView` container holding a
  `UILabel` with `boldSystemFontOfSize:17` (:265), `textColor = UIColorRGB(0x697487)` (:277),
  `shadowColor = UIColorRGB(0xdae0e8)` with `shadowOffset = (0, 1)` (:278-279),
  `backgroundColor = clear`. The label is `sizeToFit`-ed and then offset by
  `CGRectOffset(frame, 21, 16)` (:281) — so **x = 21, y = 16** from the header's top-left, and
  the label is *not* uppercased. Sections without a title store `[NSNull null]` and return
  `nil` from `viewForHeaderInSection` (:269-270, :324-331).
  Headers are generated once, lazily from `loadView` (:232-233), and never regenerated — the
  titles are static, so the strings cannot change under them.
- Row heights (:338-357): **44** for action / switch / variant rows, **45** for the button row,
  and for a comment row `[(TGCommentMenuItem *)item heightForWidth:_currentTableWidth]`.
  Anything unrecognised → **0**, which is how the model stays crash-free if a type is added
  without a height.
- `_currentTableWidth` is *not* read from the table. It is set to the screen width for the
  target orientation in `willRotateToInterfaceOrientation:` (:246) and again in
  `viewWillAppear:` (:256), so comment heights are correct **before** the rotation animation
  starts rather than after. Copy this: measuring against `tableView.bounds.size.width` during a
  rotation gives the old width and a visibly clipped comment.

Comment metric (`TGCommentMenuItem.m:37-46`, `TGCommentMenuItemView.m:13-46`):

- height = `sizeWithFont:` of the text at **systemFontOfSize:14**, constrained to
  `width - 12*2`, plus `7*2` of vertical padding. Cached per width (`_cachedHeightWidth`),
  invalidated on `setComment:` (:29-35).
- the label is **centred** (`textAlignment = Center`, `numberOfLines = 0`, word wrap),
  inset (1, 7) with flexible W/H, colour `0x697487`, shadow `0xdae0e8` at offset (0, 1) —
  identical treatment to the section header, one size down and centred.

Reset button row (`TGButtonMenuItemCell.m`):

- it is a real `UIButton` at `CGRectMake(9, 0, width - 18, 45)` (:29) inside a
  transparent cell — hence the 45pt row height — with `boldSystemFontOfSize:17` (:34).
- `TGButtonMenuItemSubtypeRedButton` (:72-81) sets the stretchable artwork
  **`MenuRedButton.png` / `MenuRedButton_Highlighted.png`**
  (`TGInterfaceAssets.mm:835-849`, stretched in the centre), title colour `0xffffff` for both
  normal and highlighted, title shadow `UIColorRGBA(0xa10603, 0.5)`. It is **white bold text on
  a glossy red pill**, not red text on white.
- The button row and comment rows set `clearBackground = true` (:443, :506) and therefore skip
  the grouped-cell artwork entirely.

Grouped-cell artwork (:514-550) — this logic is shared verbatim with
`TGCustomNotificationController.m:169-202` and with the other menu screens:

- `firstInSection && lastInSection` → `groupedCellSingle` / `…SingleHighlighted`,
  `setExtendSelectedBackground:false`;
- `firstInSection` → `groupedCellTop`, extend = true;
- `lastInSection` → `groupedCellBottom`, extend = true;
- otherwise → `groupedCellMiddle`, extend = true.

Assets: `GroupedCellTop@2x.png`, `…Middle@2x.png`, `…Bottom@2x.png`, `…Single@2x.png`, each with
a `_Selected@2x` twin (`Resources/`).

The subtle part is what "first" and "last" mean here (:373-391): **a comment row acts as a
section break.** A row is "first" if it is row 0 *or the previous row is a comment*; "last" if
it is the final row *or the next row is a comment*. That is why "Alert / Preview / Sound" gets a
proper rounded top and bottom even though the section array also contains a trailing comment
item. Any port that computes rounding from `row == 0 / row == count-1` will draw a rounded
corner behind the comment and a square corner above it.

Reuse identifiers are one- or two-letter constants: `@"AI"` action, `@"BI"` button, `@"SI"`
switch, `@"VI"` variant, `@"CI"` comment (:401, :421, :447, :474, :495), plus a `@"NULL"`
fallback plain cell with `selectionStyle = None` returned whenever the index path does not
resolve to an item (:556-564) — the screen never returns nil and never asserts.

On creation each grouped cell gets an empty `UIImageView` as `backgroundView` and another as
`selectedBackgroundView` (:407-410 and friends); only the `image` is swapped afterwards, so no
view churn on scroll. Switch and comment cells additionally get
`selectionStyle = UITableViewCellSelectionStyleNone` (:458, :501).

## 5. States and behaviour

### Initial state and where values come from

The switches are created **optimistically on** (`isOn = true`, :95, :100, :119, :124) and the
sound variants show `alertSoundTitles[2]` = "Tri-tone" (:106, :130) *before* anything is loaded.
There is no spinner and no empty state: the screen is drawn fully populated with plausible
defaults and then corrected in place.

`alertSoundTitles` (`TGAppDelegate.mm:948-970`) is a fixed 10-entry list:

```
0 No Sound   1 Default   2 Tri-tone   3 Tremolo   4 Alert
5 Bell       6 Calypso   7 Chime      8 Glass     9 Telegraph
```

Real values arrive over ActionStage (:190-196): the controller watches
`/tg/peerSettings/(INT_MAX-1)` and `(INT_MAX-2)` and requests the `,cached` actor for each.
`actorCompleted:` (:838-861) and `actionStageResourceDispatched:` (:830-836) both funnel into
the same handler, which stores a mutable copy of the dictionary
(`muteUntil`, `soundId`, `previewText`) and calls `-updateNotificationSettingsItems` **on the
main queue**.

`-updateNotificationSettingsItems` (:890-956) is the only refresh path. For each of the six
server-backed items it: sets the model value, looks up the *currently visible* cell via
`cellForRowAtIndexPath:`, type-checks it with `isKindOfClass:`, and pushes the value in with
`setIsOn:animated:false` / `setVariant:`. If the cell is offscreen, `cellForRowAtIndexPath:`
returns nil, the update is skipped, and the model value is picked up on the next
`cellForRowAtIndexPath:` dequeue. **There is never a `reloadData`** — that is what keeps a
half-thrown switch from snapping back mid-gesture.

Value mapping:

- Alert is on iff `muteUntil == 0` (:898, :929). Off is written as `INT_MAX` (:723, :737).
- Preview is `previewText` as a bool (:920, :951).
- Sound: `soundId`, with the quirk `if (soundId == 1) soundId = 2;` (:908-909, :939-940,
  and again at :626-627, :646-647). Index 1 is "Default", and this screen refuses to display
  "Default" for the global scope — the global scope *is* the default, so it is normalised to
  "Tri-tone". Guarded by a bounds check before indexing (:910, :941), so an out-of-range
  `soundId` from the server leaves the previous variant text untouched instead of crashing.
- If the dictionary key is missing entirely, `[nil intValue]` is 0 / `[nil boolValue]` is false,
  so a missing `muteUntil` reads as unmuted and a missing `previewText` reads as preview **off**.
  This asymmetry is in the original; it is not obviously intentional.

The three in-app switches read `TGAppDelegateInstance.soundEnabled` / `.vibrationEnabled` /
`.bannerEnabled` at construction (:143, :148, :153) and are never refreshed — nothing else can
change them while the screen is up.

### Toggling a switch

Cells do not target the controller. `TGSwitchItemCell.watcherHandle = _actionHandle` (:460) and
the cell posts an ActionStage action `"toggleSwitchItem"` with the `TGSwitchItem` itself as
`itemId` and the new `value`. `-actionStageActionRequested:options:` (:707-771) writes
`switchItem.isOn` first, then branches on `switchItem.tag`:

- private alert / preview → update `_messageNotificationSettings`, fire
  `/tg/changePeerSettings/(INT_MAX-1)/(pc<n>)` with `peerId` + the changed key
  (:721-734); `n` is a monotonically increasing `static int actionId` used purely to make each
  request path unique so ActionStage does not coalesce two rapid toggles.
- group alert / preview → same with `INT_MAX - 2` (:735-748).
- in-app sound / vibrate / banner → set the property on the app delegate and
  `[TGAppDelegateInstance saveSettings]` immediately (:749-763). No network traffic.

There is **no optimistic-rollback**: the UI commits at once and a failed request is simply
never reflected. The next `/tg/peerSettings` dispatch corrects it.

### Choosing a sound

`dialogMessageSoundButtonPressed` / `groupMessageSoundButtonPressed` (:619-659) are reached
through `didSelectRowAtIndexPath:` (:567-605), which performs the item's `action` selector for
action and variant items only — switch and comment rows are inert on tap (switches also have
`selectionStyle = None`).

They build a `TGCustomNotificationController` in `…ModeSettings`, set `watcherHandle`,
`tag` (so the answer can be routed back), `selectedIndex = soundId` (normalising 1 → 2 again),
call `-skipDefault`, wrap it in a `TGNavigationController` with `blackCorners:false` and
**present it modally** (:629-637). Modal, not pushed — because it has Cancel/Done.

`TGCustomNotificationController` (`.m`):

- list = the 10 `alertSoundTitles` (:47-48); `_defaultSoundId = 2` (:50).
- `-skipDefault` (:76-82) removes index 1 ("Default") from the list and decrements
  `_selectedIndex` if it was ≥ 1, so the caller may keep passing absolute sound ids. `Done`
  reverses it: `if (_skipDefaultItem && selectedIndex >= 1) selectedIndex++` (:264-266).
  This is the entire reason `skipDefault` exists — per-chat pickers keep "Default", the global
  one cannot.
- Nav bar: left `TGToolbarButton` type Generic "Cancel", `minWidth = 59`; right type Done
  "Done", `minWidth = 51` (:90-102). Title `Nofications.CustomSound.Title` = "Sound".
- Plain `UITableView`, grouped, `rowHeight = 44`, clear background, `backgroundView = nil`
  (:106-113), over the same `linesBackground` tile (:104). One section.
- Rows are `TGActionMenuItemCell` with `setHideDisclosureIndicator:true` and
  `setHideCheckIndicator:(row != _selectedIndex)` (:164-165) — a checkmark, no chevron.
- Selecting a row moves the check by touching exactly two cells (:210-225), then **plays the
  sound** (:227-244). The play mapping is its own small mess: with `skipDefault` the index is
  shifted back up; ids 1 and 2 both collapse to 2, then 0 → `INT_MAX` (meaning "silent, play
  nothing"), 1 → 0 and 2 → 0. Net effect in the settings mode: "No Sound" plays nothing,
  "Tri-tone" plays sound `0`, and every other row plays its own index.
- **Cancel also reports back** (:249-256): it posts `customSoundSelected` with a `tag` but
  **no `index`**. The parent's handler (:786-827) dismisses the modal and clears the table
  selection unconditionally, then only writes a value if `index` is present (:799-800). So
  "Cancel" and "Done" share one channel and the absence of a key is the cancellation signal.
- On Done, the parent skips the write entirely if the id is unchanged (:803-804, :818-819),
  then updates the model, calls `updateNotificationSettingsItems`, and fires
  `/tg/changePeerSettings/(…)/(pe<n>)` with `soundId` (:806-809, :821-824). Note the different
  prefix `pe` vs `pc` — again just path uniqueness per kind of change.

### Reset

`resetButtonPressed` (:661-671) deselects the current row, then shows a `UIActionSheet`
(:669-670) whose **title is the help text** (`Notifications.ResetAllNotificationsHelp`) with
destructive button `Notifications.Reset` = "Reset" and cancel `Common.Cancel`. Presented with
`showInView:self.view`. The previous sheet's delegate is nil'd first (:666-667) so a
double-tap cannot deliver twice.

On the destructive index (:673-703) it, in order: writes `muteUntil = 0`, `soundId = 1`,
`previewText = true` into **both** local dictionaries; calls `updateNotificationSettingsItems`
(which turns `soundId 1` back into "Tri-tone" on screen); sets all three app-delegate flags to
true and saves; force-sets the three in-app switch cells to on **without animation**
(:694-699); and only then fires `/tg/resetPeerSettings` with `TGTelegraphInstance` as the
watcher — the controller does not wait for or observe the result.

### Teardown

`-dealloc` (:201-209) calls `doUnloadView` (nils the table delegate/dataSource and the sheet
delegate), resets `_actionHandle` and removes itself as an ActionStage watcher.
`viewWillAppear:` deselects the selected row animated (:253-254) — the standard
return-from-push polish.

Rotation: `shouldAutorotate` true, everything except upside-down (:292-300).

## 6. Our port — what we have and what is wrong

We have no dedicated class. The screen is a page of `TGSettingsViewController`
(`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGSettingsViewController.m`), selected by
`self.page == TGSettingsPageNotifications`, with sections enumerated at lines 58-66
(Private, Groups, Channels, Reactions, Stories, Contacts, Sounds, Reset).

What is right: the section titles "Message Notifications" / "Group Notifications" (:1943-1949)
match the original strings; row titles "Alert" and "Message Preview" match (:2993, :2996); the
per-scope model (muted / showPreview) is the right shape; the shared comment metric
`commentHeightForCaption:` (:1436-1442) reproduces the original 14pt / 12pt inset / 7pt padding
formula exactly, and the footer label at :1454-1477 reproduces the centred `0x697487` +
`0xdae0e8` shadow treatment faithfully. Good work — the problem is only *where* it is applied.

Defects, most visible first:

1. **The tiled backdrop is missing on this page.** `applyTheme` (:1174-1183) only installs
   `SettingsBackground.png` as a pattern when `self.page == TGSettingsPageRoot`; every sub-page
   gets `listBackgroundColour`, which is plain `[UIColor whiteColor]` in light mode
   (`TGTheme.m:275-280`). The original sets `linesBackground` on this controller's own view
   (`TGNotificationSettingsController.m:215`). Fix: drop the `page == Root` condition — the
   tile belongs to every settings page.
2. **The original's centred comment footers are switched off here.**
   `viewForFooterInSection:` returns nil immediately for any non-root page
   (`TGSettingsViewController.m:1445-1446`), and `heightForFooterInSection:` returns
   `UITableViewAutomaticDimension` for non-root (:1433). So our notification footers render as
   UIKit's default left-aligned grey caption instead of the original's centred blue-grey text
   with the white-ish shadow. We already have the correct renderer twenty lines above; just
   remove the page gate.
3. **"Reset All Notifications" is red text, not the red pill button.**
   `fillNotificationCell:` (:2934-2937) sets `textLabel.textColor = 0xc4362f`, centred, on a
   normal 44pt row (`heightForRowAtIndexPath:` :2882-2891 returns 44 for every non-root page).
   The original is a `MenuRedButton.png` stretchable button at `(9, 0, w-18, 45)`, white bold
   17 text, shadow `rgba(0xa10603, 0.5)` (`TGButtonMenuItemCell.m:29, 34, 72-81`) on a 45pt row
   with a transparent cell background. We already have exactly this button, built for Log Out
   at `TGSettingsViewController.m:2846-2879` — reuse it for the reset row and return 45 for
   that row's height.
4. **There is no per-scope "Sound" row at all.** `notificationRowsForSection:` (:2015-2021)
   yields `alert / preview / exceptions` (plus `pinned`, `mentions`), never `sound`. The
   original has a `TGVariantMenuItem` "Sound" in both the private and group sections
   (:103-108, :127-132) showing the current tone name and opening a modal picker. Our
   "Notification Sounds" row (:2921) is a different thing — a list of the account's *uploaded*
   sounds (`fillSoundCell:` :3011-3031) with no way to pick the tone for a scope. To match the
   original a "Sound" variant row is needed in each scope section, plus a modal picker over the
   10 `alertSoundTitles` names with a checkmark, Cancel/Done, and preview-on-tap.
5. **The whole "In-App Notifications" section is missing.** A grep for `In-App`, `inAppSound`
   or `vibrate` across `src/*.m` finds only `TGCallViewController`'s ringer. The original's
   third section — In-App Sounds / In-App Vibrate / In-App Preview, all three purely local and
   saved through `saveSettings` (:141-154, :749-763) — has no counterpart. This survived into
   the modern client unchanged (see §7), so it is not a period curiosity that can be dropped.
6. **Reset confirmation uses the wrong control.** `confirmResetAllNotifications`
   (:3806-3815) shows a `UIAlertView` with an invented message. The original shows a
   `UIActionSheet` whose *title* is the exact string
   "Undo all custom notification settings for all your contacts and groups", destructive button
   "Reset", cancel "Cancel" (:669). We already have `TGActionSheet` in the tree; use it, and
   use the original copy.
7. **Section headers are UIKit's, not the original's.** There is no `viewForHeaderInSection:`
   anywhere in the file, and `heightForHeaderInSection:` returns
   `UITableViewAutomaticDimension` for non-root pages (:1420-1424). The original draws its own:
   bold 17, `0x697487`, shadow `0xdae0e8` at (0,1), origin **(21, 16)** inside a **46pt** header
   (:265-281, :319). The iOS 6 default grouped header is visually close (bold 17, blue-grey,
   white shadow), so this is the least urgent item — but the inset and the 46pt height are
   different, and if we ever run under a theme that changes the header, the difference becomes
   obvious. I would fix it after 1-6.
8. **No right-swipe-to-go-back.** The original enables it on this table
   (:221, `TGActionTableView.m:129-148`). Our settings controller uses a plain grouped
   `UITableViewController` (:154) and never touches `TGActionTableView`, whose
   `enableSwipeToLeftAction` exists in our tree
   (`src/TGActionTableView.h:34`) but is unused here.
9. **Cell rounding rule.** Ours relies on UIKit's own grouped rounding, so the "comment row
   breaks the group" rule (:373-391) does not apply and cannot — but since our comments are
   footers rather than rows, the visible result is equivalent. No action needed; noted so the
   next reader does not "fix" it.

Not a defect, but worth stating: our page carries Channels, Reactions, Stories, Contacts and
Exceptions sections that the 2013 screen had no concept of. That is correct for this project —
modern interaction model, 2013 clothes. The clothes are the part that is off.

## 7. What became of it

**Telegram-iOS (modern).**
`submodules/SettingsUI/Sources/Notifications/NotificationsAndSoundsController.swift`. The entry
enum (:136-168) shows how the same screen grew: `accountsHeader / allAccounts / accountsInfo`
(multi-account), `permissionInfo / permissionEnable` (iOS started letting users deny
notifications outright), a `categoriesHeader` group of **`privateChats`, `groupChats`,
`channels`, `stories`, `reactions`** — each now a *disclosure into its own sub-screen*
(`NotificationsPeerCategoryController.swift`) rather than three inline rows —
`displayNamesOnLockscreen`, a `badgeHeader` group, `joinedNotifications`, and finally
`reset` + `resetNotice`.

Two things are striking. First, **`inAppHeader / inAppSounds / inAppVibrate / inAppPreviews`
(:151-154) survived thirteen years verbatim**, same three switches, same order, same meaning —
which is why item 5 above matters. Second, **reset survived too** (:167-168), still last, still
with its explanatory notice underneath. What changed was forced by features, not taste:
per-category screens exist because each category grew a sound *and* an exception list *and*
per-type toggles; the permission rows exist because the OS changed; badge and lockscreen rows
exist because iOS grew those surfaces.

**twelve** (`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGNotificationSettingsController.m`,
613 lines) is the direct descendant on the original's own lineage and is the most useful of the
three for us, because it shows the *minimum* set of additions:

- the item model moved from `TGMenuSection`/`TGMenuItem` + hand-rolled table code to
  `TGCollectionMenuSection` + `TGHeaderCollectionItem` / `TGSwitchCollectionItem` /
  `TGVariantCollectionItem` / `TGCommentCollectionItem` / `TGButtonCollectionItem`
  (:89-180) — the *same* five item kinds, now framework objects. Header and comment became
  items inside the section rather than table header/footer views.
- a new first section `Notifications.BackgroundNotifications` (:89-100), an iOS-6-era
  background-fetch toggle.
- an **Exceptions** variant row per scope (:113, :135), whose variant text is a pluralised count
  or `Notifications.ExceptionsNone` (:235, :238) — pushing
  `TGNotificationExceptionsController` (:444, :462). This is exactly the row our port already
  has, and it confirms the shape: a variant row showing a count, not a separate section.
- the sound picker became `TGAlertSoundController` with a *sound info list* and an explicit
  `defaultId:nil` (:385, :399) instead of an index into a hardcoded name array — forced by
  custom uploaded sounds.
- defaults are now explicit rather than optimistic: both dictionaries start as
  `{muteUntil: 0, soundId: 1, previewText: true}` (:81-82, :323-324), which is also what reset
  writes. Our port should adopt this — it removes the "missing `previewText` reads as off"
  asymmetry noted in §5.
- reset moved from `UIActionSheet` to `TGCustomActionSheet` (:306-308) but kept the same three
  strings and the same destructive/cancel arrangement. So item 6 above should be fixed with our
  `TGActionSheet`, and that is period-correct for the whole lineage.

## 8. Genuinely ambiguous

- Whether a missing `previewText` key reading as **off** (§5) was intended. twelve removes the
  question by pre-seeding the dictionaries; I would follow twelve rather than reproduce the
  original's ambiguity.
- The exact play-index arithmetic in `TGCustomNotificationController.m:227-244` (three
  successive remappings, two of which collapse to the same value) reads like accumulated
  patching rather than a design. Reproduce the observable behaviour — silent for "No Sound",
  otherwise play the tone — not the arithmetic.

# TGSelectContactController (original, Telegram for iOS v1.1 / build 21024)

Source of truth:
`telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGSelectContactController.{h,m}`
(21 + 218 lines). Nearly everything visible is inherited from `TGContactsController`
(`Telegraph/Telegraph/TGContactsController.{h,mm}`, 3226 lines in the .mm); the subclass is a thin
*mode configurator* plus the secret-chat creation flow. Both files are read below in full; every
number here is cited.

---

## 1. What it is

One class serves all three "start something new" screens:

| Screen | Constructed as | Title |
|---|---|---|
| New Message | `initWithCreateGroup:false createEncrypted:false` | `Compose.NewMessage` = "New Message" (`TGSelectContactController.m:98`, `en.lproj/Localizable.strings:242`) |
| New Group (member picking step) | `initWithCreateGroup:true createEncrypted:false` | `Compose.NewGroup` = "New Group" (`.m:82`, strings:243) |
| New Secret Chat | `initWithCreateGroup:false createEncrypted:true` | `Compose.NewEncryptedChat` = "New Secret Chat" (`.m:94`, strings:244) |

It is a `TGContactsController` subclass conforming to `TGNavigationControllerItem`
(`TGSelectContactController.h:13`), with two public members beyond the initialiser:
`shouldBeRemovedFromNavigationAfterHiding` (h:15) and `actionsHandle` (h:17).

### The mode bitmask — the whole design in five lines

```objc
int contactsMode = TGContactsModeRegistered | TGContactsModeHideSelf;
if (createEncrypted)      _createEncrypted = true;
else if (createGroup)     contactsMode |= TGContactsModeCompose;
else                      contactsMode |= TGContactsModeCreateGroupOption;
```
(`TGSelectContactController.m:37-48`)

The enum values matter because several are composites
(`TGContactsController.h:17-30`):
`TGContactsModeCompose = 256|1|4` — i.e. Compose *implies* Registered **and**
`TGContactsModeSearchDisabled(4)`; `TGContactsModeCreateGroupOption = 2048`;
`TGContactsModeHideSelf = 64`; `TGContactsModeRegistered = 1`.

Consequences, all inherited:

- **Registered only, no phonebook.** `TGContactsModePhonebook` is never set, so no
  `/tg/phonebook` watch (`TGContactsController.mm:322-323`) and no grey non-Telegram rows.
- **Self is always removed** — the contact-list builder `continue`s on `uid == clientUserId`
  unconditionally (`TGContactsController.mm:2831-2832`), so `HideSelf` is belt-and-braces here.
- **New Message and New Group get the A–Z section index**, main Contacts does not:
  indices are generated only for `Compose || CreateGroupOption`
  (`TGContactsController.mm:3126`).
- **New Secret Chat sets no extra bits at all**: plain `Registered|HideSelf`. So it is the only
  one of the three with *no* index bar, *no* action rows, and — because SearchDisabled is not set
  and Compose is not set — a plain `UISearchBar` as `tableView.tableHeaderView`
  (`TGContactsController.mm:503`, `585`).

`usersSelectedLimit` is 99 on device, 10 in the simulator (`TGSelectContactController.m:53-57`).

---

## 2. Screen by screen

### 2.1 New Message (`CreateGroupOption`)

Entered from the chat list compose button: `TGTelegraphDialogListCompanion.mm:144-148`
pushes it onto `TGAppDelegateInstance.mainNavigationController`, animated.

Layout: plain-style `TGActionTableView`, `separatorStyle = None`, opaque, white layer background
(`TGContactsController.mm:490-500`). A 500 pt tall filler view of `0xe4e9f0` is parked at
`y = -500` above the table so an over-scroll bounce shows the search-bar blue-grey, not white
(`.mm:503-510`) — this is added because SearchDisabled is off for this mode. Search bar is 44 pt
tall, placeholder `DialogList.SearchLabel`, return key Done (`.mm:513-538`), used as the plain
`tableHeaderView` (`.mm:585`). `tableFooterView` is an empty view so no phantom separators
(`.mm:589`).

**The two action rows.** Because `CreateGroupOption` is set, a synthetic first section is inserted
holding two fake `TGUser`s with `uid = INT_MAX` and `uid = INT_MAX - 1`, and that section's
`letter` is nil so it draws no header (`TGContactsController.mm:3103-3117`). Row height for
section 0 in this mode is **44**, all other user rows are **51**
(`TGContactsController.mm:1350-1357`). Both are rendered by `TGFlatActionCell`:

- `INT_MAX` → `setMode:TGFlatActionCellModeCreateGroup` (`.mm:1559`) → title "New Group", icon
  `ListIconFriends.png` at `(10, 12)`, **disclosure arrow hidden**
  (`TGFlatActionCell.m:66,101-111`).
- `INT_MAX-1` → `TGFlatActionCellModeCreateEncrypted` (`.mm:1572-1573`) → title "New Secret Chat",
  icon `ListIconEncrypted.png` at `(10, 9)` — three points higher than the friends icon —
  disclosure hidden (`TGFlatActionCell.m:113-124`).

`TGFlatActionCell` metrics: background image `Cell88.png`, selected `CellHighlighted88.png`
(`TGFlatActionCell.m:28-37`); title label frame `(53, 12, width-30, 20)`, **bold system 16**,
colour `0x0779d0`, highlighted white, opaque white label background
(`TGFlatActionCell.m:39-46`). The 53 pt left inset is the icon column; the label is not shortened
for the (hidden) disclosure arrow, whose view sits at `contentView.width - w - 12, y 14`
(`TGFlatActionCell.m:51-54`).

Note the row/handler asymmetry that only shows up if you reorder anything: the handlers are
guarded by *both* uid and row index — `INT_MAX` only fires at `indexPath.row == 0` and
`INT_MAX-1` only at `row == 1` (`TGContactsController.mm:1649-1659`). Tapping either does nothing
if the row lands elsewhere.

**Taps.** `actionItemSelected` is overridden to push a new `TGSelectContactController` in group
mode (`TGSelectContactController.m:62-66`); the base class's version would have opened the
invite-friends flow (`TGContactsController.mm:1680-1683`). `encryptionItemSelected` pushes the
encrypted variant (`.m:68-72`); the base class's version pushes group creation and is guarded so
it does nothing when `CreateGroupOption` is set (`.mm:1685-1692`) — the subclass wins, so from New
Message the second row really does open Secret Chat.

Tapping a person calls `singleUserSelected:`, not overridden in this mode, so
`TGContactsController.mm:1694-1700`:
`navigateToConversationWithId:… clearStack:true openKeyboard:(_contactsMode & TGContactsModeCreateGroupOption)`.
Two behaviours worth copying: the compose screen is **removed from the stack** (`clearStack:true`),
so Back from the conversation returns to the chat list, not to the picker; and the keyboard
**opens automatically** because the mask bit is non-zero here (and only here — from main Contacts
the bit is 0 and the keyboard stays down).

Rows are `TGContactCell` with `selectionControls:false` for this mode, since neither Compose nor
Invite is set (`TGContactsController.mm:1585`), and `contactSelected` is forced false
(`.mm:1600-1601`).

Section headers: 25 pt tall, drawn only where `letter != nil`
(`TGContactsController.mm:1264-1275`, `1338-1344`); the first real letter section is drawn in the
"first" variant because search is present (`.mm:1272`). If the whole list collapses to one
section, its letter is cleared (`.mm:3094-3098`), i.e. a single-letter contact list shows no
header at all.

### 2.2 New Group, step 1 (`Compose`)

`Compose` sets SearchDisabled(4) — so the search bar is *not* the table header. Instead a
`TGTokenFieldView` is created at the controller's clean inset, full width, height
`[_tokenFieldView preferredHeight]`, and the table is pushed below it
(`TGContactsController.mm:591-596`, `updateTableFrame:`). A second, always-51-pt-row search table
(`_searchTableView.rowHeight = 51`, `.mm:601`) sits on a white background for token-field search
results. Token field text is system 15, counter label system 15 in `0x8d9298`
(`TGTokenFieldView.m:108,116-120`); placeholder string is `Compose.TokenListPlaceholder` =
"Who would you like to message?" (strings:241).

`_multipleSelectionEnabled` is set at init for Compose (`TGContactsController.mm:328-329`), and
`didSelectRowAtIndexPath:` returns immediately in that state (`.mm:1626-1627`): rows are never
"opened", they are toggled through the cell's own checkbox control, which posts
`/contactlist/toggleItem` through the action handle (`.mm:2529-2551`). `TGContactCell` is built
`selectionControls:true` for Compose (`.mm:1585`).

**Selection limit.** When the user tries to add beyond `usersSelectedLimit` the toggle is simply
refused and the cell's checkbox is snapped back with `updateFlags:selected force:true`
(`.mm:2534-2539`). There is **no alert and no feedback** in v1.1 — worth knowing before inventing
one. (`twelve` later added `usersSelectedLimitAlert` = `CreateGroup.SoftUserLimitAlert`,
`twelve/Telegraph/TGSelectContactController.m:139`.)

Selecting from search also collapses search: `[_searchMixin setIsActive:false animated:true]` and
`[_tokenFieldView clearText]` on add (`.mm:2543-2551`).

**Next button.** `loadView` (after `[super loadView]`) creates a `TGToolbarButton` of type
`TGToolbarButtonTypeDone`, `minWidth = 56`, text `Common.Next` = "Next", `sizeToFit`, wrapped in a
`UIBarButtonItem` as the right item; enabled iff `selectedContactsCount != 0`
(`TGSelectContactController.m:84-90`, strings:44). Button metrics from
`TelegraphKit/TelegraphKit/TGToolbarButton.m`: label bold system **12** (line 281), height **30**
portrait / **25** landscape, horizontal padding 7 + 7, clamped up to `minWidth`
(lines 265-267, 519-540); background `HeaderButton_Blue.png` stretched at its midpoint (lines
69-75); text white with shadow `0x042651 @ 0.3` (lines 173-201). Disabled state is *not* a grey
image — only `_buttonLabelView.alpha = 0.6` (line 599-603).

The button is re-`sizeToFit`ed on every selection change (`TGSelectContactController.m:143-149`,
`172-178`) even though the label text never changes — harmless, but it means the original's Next
title is a bare "Next", **never "Next (3)"**.

**Next pressed** (`.m:107-141`): if nothing is selected it returns silently. Otherwise it
lazily creates one `TGTelegraphConversationProfileController` via `initWithCreateChat`, sets its
`watcher` to `self.actionHandle`, hands it `[self selectedComposeUsers]` (note: read from the
*token field's* ids, resolved from the database — `.mm:2156-2170` — not from `_selectedUsers`),
and pushes it. The controller instance is cached, so going back and pressing Next again reuses
the same profile screen with refreshed participants. There is a commented-out branch
(`.m:112-127`) that used to shortcut a 1-person group straight into a conversation; in v1.1 a
single selected contact still goes to the group-title screen.

### 2.3 New Secret Chat (`createEncrypted`)

No action rows (no `CreateGroupOption`), no index bar, no multi-select; a plain contact list with
a search bar. `singleUserSelected:` is overridden (`.m:151-170`):

1. Deselect the current row animated, if any (`.m:155-156`) — the highlight does not linger while
   the network call runs.
2. Show a full-screen `TGProgressWindow` sized to `[UIScreen mainScreen].bounds`, animated
   (`.m:158-159`).
3. Remember the user in `_currentEncryptedUser`, then request the actor
   `/tg/encrypted/createChat/(profile%d)` with a monotonically increasing static `actionId`, option
   `uid` (`.m:161-164`). The counter guarantees a fresh path per attempt, so repeated taps do not
   collide on one actor.

`actorCompleted:` (`.m:193-216`) dispatches to the main queue, dismisses the progress window, and
then either navigates to `result[@"conversation"].conversationId` via `TGInterfaceManager`
(`.m:204-205`) or shows a plain `UIAlertView` with no title and one OK button. The error text has
two cases: `status == -2` → `Profile.CreateEncryptedChatOutdatedError` formatted **twice** with
`_currentEncryptedUser.displayFirstName` (the string embeds the first name in two places), any
other failure → `Profile.CreateEncryptedChatError` (`.m:209`).

Note that unlike `singleUserSelected:` in the base class, this navigation does **not** pass
`clearStack:true`; the interface manager's default `navigateToConversationWithId:conversation:`
is used both here and in the (dead) single-contact branch.

---

## 3. Cross-cutting behaviour

- **Back.** `loadView` sets `self.backAction = @selector(performBackAction)`
  (`.m:78`, `102-105`), which is just `popViewControllerAnimated:true`. This exists because
  `TGViewController`'s custom back button needs an explicit action; the default in the base class
  is `modalInviteBackButtonPressed` for main-contacts mode (`.mm:483-489`).
- **`shouldBeRemovedFromNavigationAfterHiding`** is set to true when the chat-creation flow reports
  `chatCreated` through the action stage (`.m:182-191`), so after a group is created the picker
  silently deletes itself from the navigation stack rather than animating away.
- **Superclass-respond guards**: both `actionStageActionRequested:` and `actorCompleted:` check
  `[[self superclass] instancesRespondToSelector:]` before calling super (`.m:189-190`,
  `214-215`) — a defensive idiom, not a behaviour.
- **Empty list**: nothing special. With no contacts and `CreateGroupOption`, the table still shows
  the two action rows (the service section is inserted unconditionally, `.mm:3103-3117`); with
  Compose or Encrypted it shows an empty white table. There is no "no contacts" placeholder in
  this controller.
- **Long names**: handled entirely by `TGContactCell` (51 pt row), not here.

---

## 4. Our port — comparison and defects

Our equivalent is not a class. Compose is `TGChatListViewController.composeTapped`
(`src/TGChatListViewController.m:2395-2400`) reusing `TGContactsViewController` with
`isPickerMode = YES` and `title = @"New Message"`; group member picking is the private
`TGNewGroupMembersViewController` inside `src/TGContactsViewController.m:571-700`.

What is right: row height 51 (`src/TGContactsViewController.m:18`), `TGFlatActionCell` title/icon
placement for Invite (13,12) and New Group (10,12) match `TGFlatActionCell.m:96,108`
(`src/TGContactsViewController.m:3088-3093`), and the A–Z index appearing only in picker mode
mirrors the original's `Compose || CreateGroupOption` rule
(`src/TGContactsViewController.m:3055-3063` vs `TGContactsController.mm:3126`).

Visible defects:

1. **New Message has no action rows at all.** `actionRowIdentifiers` returns nil when
   `isPickerMode` (`src/TGContactsViewController.m:2220-2228`), and `rebuildSections` skips the
   action section in picker mode (`:2252-2260`). The original's New Message screen opens with two
   44 pt `TGFlatActionCell` rows above the first letter section: "New Group"
   (`ListIconFriends.png` at 10,12) and "New Secret Chat" (`ListIconEncrypted.png` at 10,9), both
   with the disclosure arrow hidden (`TGContactsController.mm:3103-3117`, `1559`, `1572-1573`;
   `TGFlatActionCell.m:101-124`). This is the single most visible difference on the screen.
   Fix: build those two rows in picker mode, at height 44 while contacts stay at 51
   (`TGContactsController.mm:1350-1357`) — ours uses a uniform `kContactRowHeight` 51.
2. **No "New Secret Chat" entry point from compose.** Ours only offers Start Secret Chat buried in
   a contact long-press action sheet (`src/TGContactsViewController.m:1615`). Original: second row
   of New Message → a dedicated picker titled "New Secret Chat"
   (`TGSelectContactController.m:68-72,94`).
3. **Next button label shows a count.** Ours renders `Next (3)`
   (`src/TGContactsViewController.m:604-612`). The original label is always plain "Next"
   (`TGSelectContactController.m:86`) and only its enabled state changes.
4. **Next button metrics and disabled styling differ.** Ours: bold system 12 white label (right),
   but frame is `size.width + 16` wide × 30 tall with `alpha = 0.5` when disabled
   (`src/TGContactsViewController.m:610-613`). Original: padding 7 + 7 (14 total), **minWidth 56**
   so a short "Next" never shrinks below 56 pt, and disabled dims only the *label* to 0.6, leaving
   the blue capsule at full opacity (`TGToolbarButton.m:266-267,519-540,599-603`;
   `TGSelectContactController.m:85`).
5. **Group member rows are wrong cells.** `TGNewGroupMembersViewController` uses a stock
   `UITableViewCell` with a checkmark accessory and system-19 name
   (`src/TGContactsViewController.m:617-635`). The original keeps `TGContactCell` with the
   checkbox *selection control* on the left and the avatar/status layout intact
   (`TGContactsController.mm:1585`, `adjustCellForSelectionEnabled`), plus a token field at the
   top showing the chosen people as tokens (`TGContactsController.mm:591-596`). No token field
   exists in ours at all; picked contacts are invisible except as checkmarks.
6. **No selection limit.** Ours accepts unbounded selection
   (`src/TGContactsViewController.m:638-655`). Original caps at 99 and silently refuses the toggle
   past the cap (`TGSelectContactController.m:56`, `TGContactsController.mm:2534-2539`).
7. **Group creation asks for the title in a `UIAlertView`**
   (`src/TGContactsViewController.m:657-666`). The original pushes a full screen,
   `TGTelegraphConversationProfileController initWithCreateChat`, where the title *and the group
   photo* are set (`TGSelectContactController.m:130-139`).
8. **Compose does not clear the stack.** Tapping a contact in our picker pushes the chat on top of
   the picker (`src/TGContactsViewController.m:3242-3246`), so Back returns to the contact list.
   Original passes `clearStack:true` and `openKeyboard:` non-zero for `CreateGroupOption`
   (`TGContactsController.mm:1698`): Back goes to the chat list and the keyboard is already up.
9. **Picker mode still shows self?** Ours filters nothing equivalent to
   `uid == clientUserId` in the picker path that I could see in `rebuildSections`; the original
   drops self unconditionally (`TGContactsController.mm:2831-2832`). Worth verifying against
   `[TGClient shared].contacts`, which may already exclude self — flagged, not asserted.

Also missing, and cheap: after a group is created the original removes the picker(s) from the
stack via `shouldBeRemovedFromNavigationAfterHiding` (`.m:186`); ours does the equivalent by hand
with `setViewControllers:` (`src/TGContactsViewController.m:687-692`), which is fine.

---

## 5. What became of it

**`twelve` (`twelve/Telegraph/TGSelectContactController.{h,m}`, 545 lines vs 218).** Same class,
same name, grown by exactly the features that arrived after 2013. The initialiser became
`initWithCreateGroup:createEncrypted:createBroadcast:createChannel:inviteToChannel:showLink:` and
then gained a `call:` variant (h:20,22). New modes appear in the bitmask: `SearchGlobal`,
`CreateGroupLink`, `ManualFirstSection`, `Calls` (m:77-90). Limits multiplied: 199 for broadcast,
`maxChatParticipants - 1` from server config for groups, 0 (unlimited) for channels
(m:103-116), and the silent refusal became a soft alert (m:139). Errors that did not exist in v1.1
are enumerated: `Group.ErrorAddBlocked`, `Channel.ErrorAddTooMuch`,
`Group.ErrorNotMutualContact`, the privacy `InviteToChannelError` family (m:223-244). The chrome
also modernised: `TGToolbarButton` image buttons gave way to plain
`UIBarButtonItem`s with `Common.Next` / `Common.Done` / `Common.Cancel` (m:285-290) — that is iOS 7
flat design, a change of taste, whereas the mode explosion was forced by new features.

**Modern (`Telegram-iOS`).** The one class split into three. `ComposeControllerNode`
(`submodules/TelegramUI/Sources/ComposeControllerNode.swift:44-53`) is now a `ContactListNode`
configured with declarative `ContactListAdditionalOption`s — the direct descendant of the
`INT_MAX` fake-user hack, now a first-class data type. There are **three** options, not two:
"New Group", `NewContact_Title`, "New Channel"; New Secret Chat moved *out* of the compose list
into a separate `ContactSelectionControllerImpl` reached from
`ComposeController.swift:151-153` with title `Compose_NewEncryptedChatTitle`. Group member picking
became `ContactMultiselectionController`, whose title carries a live `count/maxCount` counter
(`ContactMultiselectionController.swift:264-270`) — the modern answer to the original's silent
cap. The secret-chat progress window became `controller.displayNavigationActivity = true` and the
result replaces all but the root controller
(`ComposeController.swift:157-166`), which is the same "do not leave the picker behind" intent as
`shouldBeRemovedFromNavigationAfterHiding` / `clearStack:true`, expressed thirteen years later.

The stable ideas across all three generations: one screen, driven by a mode; a small set of
action rows above the alphabet; single-tap for a chat, checkbox for a group; and the picker never
survives in the back stack once it has done its job.

## 6. Open questions

- `TGProgressWindow` appearance (dimming, spinner size) is not read here; if we mimic the secret
  chat flow we need that component studied separately.
- Whether our contact source already excludes the logged-in user (defect 9) is unverified.
- The original's `disabledUsers` / `_disabledUserIds` path (`TGContactsController.mm:1601`,
  `1662`) is never populated by `TGSelectContactController` in v1.1 — greyed-out rows appear to be
  dead code in these three screens, but I did not exhaustively check every caller of
  `setDisabledUsers:`.

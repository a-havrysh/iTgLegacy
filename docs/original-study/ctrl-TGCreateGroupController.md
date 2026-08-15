# TGCreateGroupController — study of the 2013 group-creation flow

## 0. Naming: the class does not exist in v1.1

There is no `TGCreateGroupController` anywhere in
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
(neither `Telegraph/Telegraph` nor `TelegraphKit/TelegraphKit`). The name first appears in the later
fork, `/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGCreateGroupController.m`, and in the modern
client as `submodules/TelegramUI/Sources/CreateGroupController.swift`.

In v1.1 the same job is done by **two screens**, and this document covers both because neither is
usable alone:

1. **`TGSelectContactController`** (`Telegraph/Telegraph/TGSelectContactController.{h,m}`, 21 + 218
   lines) — a subclass of `TGContactsController` configured for multi-selection. Titled "New Group".
   Right button "Next".
2. **`TGTelegraphConversationProfileController` in `_createChat` mode**
   (`Telegraph/Telegraph/TGTelegraphConversationProfileController.mm`, 3720 lines) — the same class
   that renders Group Info, re-purposed via `-initWithCreateChat` (line 364). Titled "New Group".
   Right button "Create".

Everything below cites those two files unless stated otherwise. Line numbers refer to
`Telegraph/Telegraph/…` under the extracted source root; the localisation file is
`Telegraph/Telegraph/en.lproj/Localizable.strings`.

---

## 1. Entry points and the shape of the flow

Three ways in, all producing a `TGSelectContactController`:

- Compose from the dialog list: `TGTelegraphDialogListCompanion.mm:146` creates
  `initWithCreateGroup:false createEncrypted:false` — i.e. **New Message**, which is *not* group mode
  but carries `TGContactsModeCreateGroupOption`, so its first row is a "New Group" action cell.
- Tapping that action cell: `TGContactsController.mm:1687-1690` (and the identical
  `TGSelectContactController.m:62-66`) pushes `initWithCreateGroup:true createEncrypted:false`.
- The contacts tab shows the same action cell in `TGFlatActionCellModeCreateGroupContacts`
  (`TGContactsController.mm:1572-1575`), whose title is `Compose.NewGroup`
  (`TGFlatActionCell.m:65-66`). The disclosure chevron is hidden only in
  `TGFlatActionCellModeCreateGroup`, shown in the contacts variant (`TGFlatActionCell.m:111`).

So the model is: **pick members first, name the group second.** The name screen is a real pushed
view controller, not a dialog. That ordering is the single most important thing about this component
and it survives unchanged into the modern client.

### Mode bits

`TGSelectContactController.m:37-48`:

```
int contactsMode = TGContactsModeRegistered | TGContactsModeHideSelf;
if (createEncrypted)      _createEncrypted = true;
else if (createGroup)     contactsMode |= TGContactsModeCompose;      // multi-select
else                      contactsMode |= TGContactsModeCreateGroupOption; // single-select + action row
```

`TGContactsModeHideSelf` matters: you never see yourself in the picker, and `createButtonPressed` on
the second screen filters your own uid again (line 2754-2758) as a belt-and-braces measure.

---

## 2. Screen 1 — `TGSelectContactController` (member picker)

### Public surface

```objc
@property (nonatomic) bool shouldBeRemovedFromNavigationAfterHiding;   // .h:15
@property (nonatomic, strong) ASHandle *actionsHandle;                 // .h:17
- (id)initWithCreateGroup:(bool)createGroup createEncrypted:(bool)createEncrypted;  // .h:19
```

### Metrics and chrome

| Thing | Value | Citation |
|---|---|---|
| Title | `Compose.NewGroup` = "New Group" | `.m:82`; `Localizable.strings:243` |
| Right button | `TGToolbarButton` type `Done` (blue), `minWidth = 56`, text `Common.Next` = "Next" | `.m:84-89`; `strings:44` |
| Button enabled | `[self selectedContactsCount] != 0` — set at load and on every (de)selection, each followed by `sizeToFit` | `.m:90`, `.m:152-165` |
| Selection cap | `usersSelectedLimit = 99` on device, `10` in the simulator | `.m:51-55` |
| Contact row height | 51 | `TGContactsController.mm:600` (search table; the main table uses the same cell) |
| Token field | `TGTokenFieldView`, nominal 44 tall, pinned at `tokenFieldOffset`, table inset by its height | `TGContactsController.mm:591-594`, `:767` |
| Checkmark artwork | `Contact_Check.png` (unchecked) / `Contact_Checked.png` (checked) | `TGContactCell.m:32, 40` |
| Back | `backAction = @selector(performBackAction)` → plain pop | `.m:75`, `.m:100-103` |

The token field is what makes compose mode feel different from the plain contacts list: selected
people become tokens in a growing field above the table, and choosing someone clears the typed text
(`TGContactsController.mm:2547-2549`). Its height is dynamic (`preferredHeight`), and it shrinks when
search is active (`:1015-1017`).

### Behaviour at the limit

`TGContactsController.mm:2534-2539`: if the limit is already reached, the tap is swallowed —
`[cell updateFlags:selected force:true]` snaps the checkmark back to its previous state and the
method returns. **No alert, no sound, no explanation.** The cell simply refuses to tick. Worth
copying deliberately or deliberately not; either way it is not an accident.

### Next

`.m:118-149`. Guard: zero selected → return (the button is disabled anyway). Otherwise it lazily
creates one `TGTelegraphConversationProfileController` via `-initWithCreateChat`, sets
`_chatInfoController.watcher = self.actionHandle`, hands it `[self selectedComposeUsers]` and pushes
it. The controller is cached in `_chatInfoController`, so going back and forth preserves the typed
group name.

There is a commented-out branch (`.m:122-135`) for "exactly one contact selected → just open the 1:1
chat". It was disabled: in v1.1 a two-person group is a real group.

### Removal from the stack

When the second screen reports `"chatCreated"` through the watcher, this controller sets
`shouldBeRemovedFromNavigationAfterHiding = true` (`.m:186-193`), so after the animated transition
into the new chat the picker is spliced out of the navigation stack. Back from the new group goes to
the dialog list, not to the picker.

---

## 3. Screen 2 — `TGTelegraphConversationProfileController` in create mode

### Construction

`-initWithCreateChat` (`:364-382`) builds only two sections: a members section tagged
`TGMembersSectionTag` (`#define … 0x4E153930`, line 77) and an **empty** "type" section. It does not
load a conversation, does not subscribe to notification settings, does not touch the media list.

`-shouldBeRemovedFromNavigationAfterHiding` returns `_createChat` (`:396-399`) — same splice-out
behaviour as the picker.

### Header — the part that differs from Group Info

`_headerView` is the table's `tableHeaderView` and is **59 pt tall in create mode**, 89 pt in Group
Info (`:420`). The 30 pt difference is exactly the vertical space the 70×70 avatar needs beyond the
44 pt name field (avatar at y=14 h=70 → 84 + padding vs field at y=14 h=44 → 58 + 1).
`tableFooterView` is a 7 pt spacer (`:426`).

**In create mode there is no avatar and no "add photo" button.** Lines 555-560:

```objc
if (_createChat)
{
    [_avatarView removeFromSuperview];
    [_addPhotoButton removeFromSuperview];
    [_avatarActivityIndicator removeFromSuperview];
    [_avatarActivityOverlay removeFromSuperview];
}
```

All four are constructed first (`:429-514`) and then torn out. `_createChatPhotoData` /
`_createChatPhotoThumbnail` plumbing exists (`:2115-2119`, `:3530-3541`) and would upload the photo
right after creation, but nothing in create mode can reach it because the only triggers are
`_avatarView`'s tap recogniser and `_addPhotoButton`, both detached, and `_avatarView.userInteractionEnabled`
is additionally forced to `false` (`:571-572`). **v1.1 group creation cannot set a photo.** You set it
afterwards from Group Info. If our port offers a photo at creation time it is inventing a feature; if
it does not, it is faithful.

Consequently the name field spans the full width in create mode (`:536`):

```objc
_conversationTitleFieldBackground.frame = _createChat
    ? CGRectMake(9, 14, width - 18, 44)          // create
    : CGRectMake(89, 14, width - 89 - 9, 44);    // group info, right of the avatar
```

Background artwork is `[TGInterfaceAssets groupedCellSingle]` — the single-row grouped-cell capsule,
i.e. the field is drawn as a one-row grouped table cell, not as a text field. It is
`userInteractionEnabled` with a tap recogniser (`focusOnTitleField:`, `:2200-2206`) so the whole
capsule, not just the glyph area, focuses the field.

The `UITextField` itself (`:541-551`):

- frame `CGRectOffset(CGRectInset(background, 12, 10), 0, 1)` → 12 pt horizontal inset, 10 pt
  vertical, nudged 1 pt down: **x=21, y=25, h=24** at 320 wide.
- font `boldSystemFontOfSize:16`.
- `returnKeyType = UIReturnKeyDone`.
- placeholder `ConversationProfile.GroupName` = "Group Name" (`strings:416`), coloured
  `0x8d98a6` through `[TGHacks setTextFieldPlaceholderColor:]` (the OS default grey was too light
  against this capsule).
- created `hidden = true, alpha = 0` and revealed by `updateEditingState:` — see below.

The two static header labels (`_conversationTitleLabel` bold 19 / `0x222932` at (92,24,·,24), shadow
`0xedf0f5` @28% offset (0,1); `_conversationSubtitleLabel` system 14 / `0x6d7d90` at
(93, 49+retinaPixel, ·, 24), same shadow) exist in create mode but are faded to `alpha = 0` and
hidden — lines `:521-534` and `:2311-2337`. `retinaPixel` is `0.5` on retina, `0` otherwise
(`:401`), so on the 4S the subtitle sits at y=49.5 and the "add/photo" labels are 14.5 pt.

Screen background: `[[TGInterfaceAssets instance] linesBackground]` (`:562`).

### Entering the editing state

`loadView` ends with `[self updateEditingState:false explicitState:_createChat]` (`:606`) — create
mode is *born* in the editing state, non-animated. In that branch (`:2296-2308`):

- back action becomes `performClose` (a plain pop, `:632-635`);
- right button is a `TGToolbarButton` type `Done`, text `Compose.Create` = "Create"
  (`strings:245`), `minWidth = 60`;
- `createButton.enabled = ` title with **all spaces stripped** is non-empty. A name of `"   "` does
  not enable Create.

Note the asymmetry: Group Info's editing state also installs a "Cancel" left button
(`minWidth 59`) and a "Done" right button (`minWidth 51`) — create mode installs **neither Cancel nor
Done**, only Create, and keeps the standard back chevron.

Then the field and its capsule are unhidden and, when animated, cross-faded over 0.3 s against the
static labels (`:2311-2337`).

`viewWillAppear` calls `[_conversationTitleField becomeFirstResponder]` unconditionally in create mode
(`:709-712`), so the keyboard is already up when the screen slides in and comes back up every time you
return from a pushed profile.

### Text field rules

`textField:shouldChangeCharactersInRange:` (`:2208-2226`):

- rejects `NSNotFound` ranges;
- hard cap: `range.location + MAX(0, string.length - range.length) > 256` → reject. 256 characters,
  not the 100 of the commented-out older version below it (`:2228-2241`). Paste of a longer string is
  rejected wholesale, not truncated.
- then `dispatch_async` to the main queue to re-evaluate the right button's `enabled` from the
  whitespace-stripped text. The async hop is deliberate: it reads `textField.text` *after* UIKit has
  applied the edit.

`textFieldShouldReturn:` (`:2683-2716`) resigns first responder and then does nothing else in create
mode — the whole body is guarded by `if (!_createChat && …)`. Pressing Done on the keyboard dismisses
it; it does not create the group.

### Members list

`setCreateChatParticipants:` (`:754-773`) wipes the members section and refills it with one
`TGUserMenuItem` per `TGUser`, reloading if the view is loaded.

- Row height for `TGUserMenuItemType` is **49** (`:1202-1229`; other item types there: 44 for
  action/phone/switch/variant, 45 for button, 43 for buttons-row).
- Section header 8 pt, section footer 1 pt (`:1233-1240`).
- Cells are `TGUserMenuItemCell`, reuse id `"UI"`, with `UIImageView` background and
  selectedBackground views installed once (`:1490-1502`); grouped-capsule artwork is chosen per row by
  `updateGroupedCellBackground(cell, firstInSection, lastInSection, animated)` (`:1550-1553`,
  definition at `:1243`).
- `selectionStyle` is forced to `None` when `_createChat` (`:1505`).
- Tapping a member does nothing in create mode: `didSelectRow` guards with
  `if (!_tableView.isEditing && !_createChat)` before navigating to the profile (`:1708-1720`).
- Members **cannot be removed** on this screen: `canEditRowAtIndexPath:` returns
  `indexPath.section == 2` (`:1623-1626`) and create mode only has sections 0 and 1. To drop someone
  you go back to the picker.
- Right-swipe anywhere on the table pops the controller (`:640-647`) — an extra back gesture, since
  iOS 6 has no interactive edge-swipe.
- Subtitle per member is `subtitleTextForUser(user, &active)` (the usual "online" / "last seen …"),
  and the list re-sorts live on `/tg/userdatachanges` and `/tg/userpresencechanges` (`:2790-2850`).

### The dead "Broadcast" switch

`initWithCreateChat` adds an empty second section intended for a group-type switch, and
`updateCreateChatMode` (`:3626-3648`) would retitle the screen to "Broadcast", fade the header out,
apply a `-59` top table inset (exactly the header height) and swap the right button to "Next". It is
**unreachable in v1.1**: the only trigger is a switch item tagged `TGGroupTypeTag`
(`#define … 0x596B9C0A`, line 90) and `grep` finds no code that ever creates one. Do not port it.

### Create

`createButtonPressed` (`:2744-2780`):

1. Collect uids from the members section, skipping `TGTelegraphInstance.clientUserId`.
2. Show a `TGProgressWindow` over `[UIScreen mainScreen].bounds` — a modal window, so the whole UI is
   blocked while the RPC is in flight. No inline spinner, no disabled button.
3. `requestActor:@"/tg/conversation/createChat/(%d)"` with `uids` and `title` — the title is passed
   **verbatim, not trimmed** (`[NSString stringWithString:_conversationTitleField.text]`). Leading and
   trailing spaces reach the server; only the enable-check strips them.

Success (`:3515-3546`): dismiss the progress window, tell the watcher `"chatCreated"` (which is how
the picker learns to remove itself), fire the deferred avatar upload if any (unreachable, see above),
then
`navigateToConversationWithId:… clearStack:true openKeyboard:true animated:true` — the new chat
replaces the whole pushed stack and opens with the keyboard already raised.

Failure (`:3547-3551`): a bare `UIAlertView`, no title, message
`ConversationProfile.ErrorCreatingConversation` = **"An error occurred"** (`strings:407`), single OK
button. No retry, no error-specific text, and the screen stays exactly as it was with the name and
members intact. `ConversationProfile.UsersTooMuchError` ("Sorry, this group is full…", `strings:410`)
exists but is used by the add-member path in Group Info, not here.

---

## 4. What our port does — `TGNewGroupMembersViewController`

Ours is a private class inlined in
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGContactsViewController.m:571-698`, pushed from
`-newGroupTapped` (`:2780-2784`), which hands it `self.users` wholesale. There is no second screen.

The good parts: the flow is entered from a "New Group" action row in the contacts list
(`:38`, `:3091-3092`, `:3215-3216`), row height is 51 (`:18`) which matches the original
(`TGContactsController.mm:600`), the Next button is disabled until something is selected, and the
created chat replaces the picker in the stack (`:686-690`) which reproduces
`shouldBeRemovedFromNavigationAfterHiding`.

### Defects

1. **The naming step is a `UIAlertView`, not a screen.**
   `TGContactsViewController.m:656-666` shows `UIAlertViewStylePlainTextInput` titled "New Group",
   message "Group name", buttons Cancel/Create. The original pushes a full controller with a
   grouped-capsule text field, the member list visible below it, and a "Create" toolbar button
   (`TGSelectContactController.m:136-149`; `TGTelegraphConversationProfileController.mm:364-382`,
   `:536-551`, `:2296-2308`). This is the largest visible difference in the whole flow: the user never
   sees who is in the group while naming it, cannot go back and edit membership, and gets a system
   alert instead of the 2013 chrome. **Fix: build the second controller.** It needs: 59 pt header, name
   capsule at `(9, 14, w-18, 44)` using the single grouped-cell image, field inset (12, 10) offset
   (0, 1) in bold 16, placeholder "Group Name" in `0x8d98a6`, 49 pt member rows with grouped-cell
   backgrounds, 8/1 pt section header/footer, keyboard raised on appear, right button "Create"
   (60 pt min width) enabled on whitespace-stripped non-empty text.

2. **No 256-character cap on the name.** Original: `:2208-2214` rejects any edit that would push the
   length past 256. Ours has no `UITextFieldDelegate` on the alert's field at all.

3. **No selection limit.** Original caps at 99 (`TGSelectContactController.m:51-55`) and silently
   refuses the tap past the cap (`TGContactsController.mm:2534-2539`). Ours lets you select every
   contact you have and only finds out on the server.

4. **No token field.** Compose mode in the original shows selected people as tokens in a 44 pt field
   above the table, with the table inset accordingly (`TGContactsController.mm:591-594`, `:767`).
   Ours shows selection only as a `UITableViewCellAccessoryCheckmark` (`:632-633`) — and that is the
   stock blue system checkmark, not `Contact_Check.png` / `Contact_Checked.png`
   (`TGContactCell.m:32, 40`).

5. **Next button label invents a counter.** Ours renders "Next (3)"
   (`TGContactsViewController.m:604-613`); the original's text is always "Next", with the count
   communicated by the tokens (`TGSelectContactController.m:87`). Also our disabled state is a 0.5
   alpha on a custom button (`:612`) where the original uses `TGToolbarButton`'s own enabled artwork
   with `minWidth = 56`.

6. **Member cells are stock `UITableViewCellStyleDefault` with `systemFontOfSize:19` and no
   subtitle** (`:621-635`). The original's picker uses `TGContactCell`, which carries the avatar,
   name and presence subtitle; the second screen's list uses `TGUserMenuItemCell` at 49 pt with
   avatar + "last seen" subtitle (`:1490-1545`). A user picking from a 300-contact list sees a
   materially poorer row than 2013 did.

7. **No progress window during creation.** The original blocks the UI with `TGProgressWindow`
   (`:2769-2771`) and dismisses it on completion (`:3518-3520`). Ours fires
   `createBasicGroupWithTitle:userIds:completion:` and leaves the alert-dismissed picker fully
   interactive; a second tap on Next during a slow 2G round trip starts a second creation.

8. **`failedUserIds` is silently discarded.** `TGContactsViewController.m:675` receives
   `NSArray *failedUserIds` and never reads it. Even v1.1 had nothing here, but the fork does
   (`twelve/Telegraph/TGCreateGroupController.m:341-350` maps `USERS_TOO_FEW` /
   `USER_PRIVACY_RESTRICTED` to a specific message), and privacy-restricted invites are common on
   today's server. At minimum, report "N people could not be added".

9. **Error text differs.** Ours: "Could not create this group." (`:679-683`). Original:
   `ConversationProfile.ErrorCreatingConversation` = "An error occurred" (`strings:407`) with a nil
   title. Trivial, but it is a visible string.

10. **Title is trimmed before sending** (`:670-671`), where the original sends the raw field text
    (`:2776`). Ours is arguably better behaviour; flagging it only so the divergence is deliberate.

11. **The picker is fed `self.users` directly** (`:2782`) with no `HideSelf` filtering visible at
    this call site, whereas the original masks self out of the list *and* re-filters uids at creation
    (`TGSelectContactController.m:37`; profile `:2754-2758`). Verify our `self.users` already
    excludes the logged-in account; if not, you can add yourself to your own group.

---

## 5. What the concept became

**twelve (`Telegraph/TGCreateGroupController.m`, 530 lines)** — the two-screen structure is kept
exactly (picker → named screen), but the second screen is now a real, dedicated class built on
`TGCollectionMenuController`, and the things v1.1 stubbed out are finished:

- The avatar is live at creation time: a `TGGroupInfoCollectionItem` plus a "Set Group Photo" button
  row in accent colour (`:120-127`), driven by `TGMediaAvatarMenuMixin` (`:440-470`). The photo is
  uploaded as a signal and composed into the create chain, so the group is created *with* its photo
  rather than patched afterwards (`:313-325`). This is the natural completion of the dead
  `_createChatPhotoData` path in v1.1.
- Right-button enablement moved to an action-stage message `"editedTitleChanged"` with the same
  whitespace-trimmed emptiness test (`:428-431`) — same rule, cleaner plumbing.
- Channels arrive and share the class: `initWithCreateChannel:createChannelGroup:` swaps the title to
  "New Channel", the button to "Next", and adds a 200-character About field (`:96-146`). That is the
  empty `typeSection` of 2013 finally getting a purpose, though by a different mechanism.
- Errors are typed: `USERS_TOO_FEW` / `USER_PRIVACY_RESTRICTED` get their own message
  (`:341-350`) instead of one generic alert. **Forced by a feature**: privacy settings did not exist
  in 2013, so "an error occurred" was honest then and is not now.
- `TGProgressWindow` survives unchanged (`:305`), as does "replace the pushed stack with the new
  chat" (`:377-379`).

**Modern client (`submodules/TelegramUI/Sources/CreateGroupController.swift`, 1357 lines)** — same
two-step flow, same "members first, name second", same "Create" in the top-right. The screen grew
into a section enum: `info, username, topics, autoDelete, members, location, venues` (`:56-62`), with
entries for `groupInfo`, `setProfilePhoto`, username availability checking, forum topics, auto-delete
timer, and — for location-based groups — a map and nearby-venue picker (`:79-95`). Error handling is
a typed enum: `.privacy`, `.restricted`, `.tooMuchJoined` (`:889-895`). None of that is a change of
taste; every addition tracks a product feature that did not exist in 2013. What is a change of taste:
the avatar moved from "not offered at all" (v1.1) to a first-class row you are gently pushed toward,
and the name field became a standard inset list item rather than a bespoke capsule floating in a
table header.

The through-line worth keeping: **the group is named on its own screen, with its members listed
underneath, and the keyboard already up.** That has not changed in thirteen years, and it is exactly
what our port dropped.

---

## 6. Genuinely ambiguous / unverified

- I did not open `TGInterfaceAssets` to confirm the pixel geometry of `groupedCellSingle` or the RGB
  of `linesBackground`; both are referenced by name at `:534` and `:562` and would need their own
  study.
- `TGUserMenuItemCell`'s internal layout (avatar size, label baselines) is in
  `TelegraphKit`/`Telegraph` elsewhere and is not covered here — only its 49 pt row height (`:1202-1229`).
- Whether the 2013 server enforced its own participant cap below 99 is not observable from the
  client; 99 is only the client's own `usersSelectedLimit`.

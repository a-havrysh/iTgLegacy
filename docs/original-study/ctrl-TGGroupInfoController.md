# Group Info — original study

**Assigned name:** `TGGroupInfoController`.
**That class does not exist in the 2014 source.** In Telegram for iOS v1.1 (build 21024) the group
info screen is `TGTelegraphConversationProfileController`
(`Telegraph/Telegraph/TGTelegraphConversationProfileController.h` / `.mm`, 32 + 3720 lines). The
screen's navigation title is literally `"Group Info"`
(`en.lproj/Localizable.strings:393`, `"ConversationProfile.Title" = "Group Info";`), and the class
is also the *New Group* creation screen — the same object, two modes.

The name `TGGroupInfoController` appears only later, in the twelve fork
(`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGGroupInfoController.m`, 1839 lines), which is
the direct descendant of this class. Everything below cites the 2014 original unless it says
otherwise. All original-source line numbers refer to
`telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/`.

---

## 1. What it is for

One controller, two lives, selected by which initialiser you use:

| Mode | Initialiser | Title |
|---|---|---|
| Group info (existing chat) | `initWithConversation:` (`.mm:212`) | `ConversationProfile.Title` = "Group Info" (`.mm:407`) |
| New group composition | `initWithCreateChat` (`.mm:364`) | `Compose.NewGroup` (`.mm:407`) |

`_createChat` (`.h:21`) is the flag that forks nearly every layout decision in `loadView`. This
matters: the 2013 "New Group" screen is *the group info screen already in edit mode*, not a separate
design. `shouldBeRemovedFromNavigationAfterHiding` returns `_createChat` (`.mm:396`), so the compose
screen deletes itself from the stack once you leave it, while the info screen stays.

### Public surface (`.h`)

```
@property ASHandle *actionHandle;      // the controller's own ActionStage handle
@property ASHandle *watcher;           // owner (the conversation companion) listens here
@property bool createChat;
@property bool activateCamera;         // open the photo action sheet on viewDidAppear
@property bool activatedCamera;
@property bool activateTitleChange;    // focus the title field on viewWillAppear
- initWithConversation: / initWithCreateChat
- setCreateChatParticipants:
```

`activateCamera` / `activateTitleChange` exist so the *service message* in the chat ("X changed the
group photo") can push straight into the corresponding editing affordance — see the only real call
site, `TGTelegraphConversationCompanion.mm:4474-4482` (`showConversationProfile:activateTitleChange:`,
which also wires `conversationProfileController.watcher = _actionHandle`). The compose call site is
`TGSelectContactController.m:132`, which creates the controller once and re-pushes it with
`setCreateChatParticipants:`.

Leaving the group is **not** done by this controller: the leave action sheet's destructive button
forwards `"deleteConversation"` to `_watcher` (`.mm:1800-1803`), i.e. the conversation companion
performs the deletion and the navigation. The profile screen only asks.

---

## 2. Structure: a grouped table with a custom header

`loadView` (`.mm:401`) builds a `TGActionTableView` in `UITableViewStyleGrouped` with
`separatorStyle = None`, `backgroundView = nil`, `backgroundColor = nil`, `opaque = true`
(`.mm:409-418`). The screen background is `[[TGInterfaceAssets instance] linesBackground]`
(`.mm:563`), which is `[UIColor colorWithPatternImage:[UIImage imageNamed:@"SettingsBackground.png"]]`
(`TGInterfaceAssets.mm:143-151`). **The table draws no chrome of its own** — every row's background is
a nine-slice image the data source assigns (section 4).

Section/row geometry (`.mm:1202-1241`):

| Element | Height | Citation |
|---|---|---|
| `tableHeaderView` | **89** normally, **59** in createChat | `.mm:420` |
| `tableFooterView` | 7 (a bare `UIView` 1×7) | `.mm:425` |
| Section header | 8 | `.mm:1233-1236` |
| Section footer | 1 | `.mm:1238-1241` |
| Action / phone / switch / variant row | 44 | `.mm:1211-1212` |
| Button row (`TGButtonMenuItemType`) | 45 | `.mm:1213-1214` |
| Buttons pair row (`TGButtonsMenuItemType`) | **43** | `.mm:1215-1216` |
| Shared-media row | 44 (145 if the disabled image strip were on) | `.mm:1217-1224` |
| Member row | **49** | `.mm:1225-1226` |

The 89-point header is `14 (top) + 70 (avatar) + 5`; the createChat header is `14 + 44 (title field)
+ 1`. Both numbers are literal in `.mm:420`, `.mm:431`, `.mm:536`.

### Section order — this is the part most ports get wrong

Built in `initWithConversation:` in this order (`.mm:221-266`):

1. **Notifications + Shared Media** (`_mediaSection`, tag `TGMediaSectionTag`) — a switch row
   ("Notifications", `.mm:229-233`) then the Shared Media row (`.mm:235-237`).
2. **Buttons** (`_buttonsSection`, tag `TGButtonsSectionTag`) — one row holding the *pair* of
   buttons "Add Member" / "Leave Group" (`.mm:253-262`).
3. **Members** (tag `TGMembersSectionTag`, `.mm:264-266`).

So on a real 2013 device the order top-to-bottom is: header → Notifications/Shared Media →
Add Member + Leave Group → participant list. `canEditRowAtIndexPath` hard-codes
`indexPath.section == 2` (`.mm:1623-1626`), which only works because that order is fixed.

The createChat mode builds a *different* list: members section, then an empty "type" section
(`.mm:375-380`), and no notifications/buttons at all.

---

## 3. The header

All of it lives in `_headerViewContents`, a plain `UIView` filling `_headerView` (`.mm:427-429`).

### Avatar

`TGRemoteImageView` at `CGRectMake(9, 14, 70, 70)`, `fadeTransition = true` (`.mm:431-433`).
Images go through the registered `"profileAvatar"` processor
(`TGTelegraph.mm:503-504`):

```
TGScaleAndRoundCornersWithOffsetAndFlags(source, {69,69}, offset {0.5, 0},
    canvas {70,70}, radius 10, [TGInterfaceAssets profileAvatarOverlay],
    false, nil, TGScaleImageScaleOverlay)
```

That is: the photo is scaled to **69×69**, drawn half a point in from the left of a 70×70 canvas,
corner radius **10**, and `ProfileAvatarOverlay.png` is composited on top (a bevel/gloss ring). The
half-pixel offset is what makes the overlay's 1px border land on the retina pixel grid — it is not
noise.

Remote loading (`updateTitle`, `.mm:1099-1113`):

- photo present → `loadImage:_conversation.chatPhotoSmall filter:@"profileAvatar"
  placeholder:[TGInterfaceAssets profileGroupAvatarPlaceholder]` (`.mm:1102`), which is
  `ProfilePhotoPlaceholder.png` stretched in the centre (`TGInterfaceAssets.mm:479-485`); the
  "add photo" button is hidden, the edit strip shown, the avatar becomes tappable.
- **photo absent** → `loadImage:nil`, `_addPhotoButton.hidden = false`,
  `_avatarViewEdit.hidden = true`, and `_avatarView.userInteractionEnabled = false` (`.mm:1108-1113`).
  So with no photo you do not see a grey silhouette: you see a *button*.

### The "add photo" button (no-photo state)

A `TGHighlightableButton` occupying exactly the avatar's frame, inserted **below** the avatar view
(`.mm:458-468`). Background `ProfilePhotoPlaceholder.png` / `ProfilePhotoPlaceholder_Highlighted.png`,
both stretched with a left cap of half the image width (`.mm:462-466`). Over it, two separate
centred labels, not one two-line label (`.mm:470-492`):

- "add" (`ConversationProfile.PhotoAdd`) at y = `16 + retinaPixel`
- "photo" (`ConversationProfile.PhotoPhoto`) at y = `33`
- both `boldSystemFontOfSize:14 + retinaPixel`, white, shadow `UIColorRGBA(0x47586c, 0.5)` offset
  `(0, -1)`.

`retinaPixel` is `0.5` on retina, `0` otherwise (`.mm:405`). The half-point font size is deliberate:
at 2× it renders as a crisp 29px.

### The "edit" strip

`SettingsProfileAvatarEditBackground.png`, stretched horizontally (left cap = half width, top cap 0),
pinned to the bottom of the avatar: `x = 1`, `y = avatarHeight - stripHeight - 1`,
`width = avatarWidth - 2` (`.mm:437-441`) — i.e. inset by one point on three sides so the avatar's
rounded corner and overlay border still show. Inside it, a centred "edit" label
(`Common.edit`), `boldSystemFontOfSize:13`, white (`.mm:443-451`). Its `alpha` starts at 0
(`.mm:454`) and is animated to 1 only in editing mode (`.mm:2663-2673`, 0.3 s). Its `hidden` flag is
independently driven by whether a photo exists.

### Upload progress

`AddPhotoMask.png` stretched from its centre, at `avatar.origin + (retinaPixel, 0)`, sized **69×69**
(`.mm:494-499`) — one point smaller than the avatar, again to sit inside the overlay border. A
`TGActivityIndicatorView` (`TGActivityIndicatorViewStyleSmallWhite`) offset to
`avatar.origin + (27 + retinaPixel, 28)` (`.mm:502-507`). `setShowAvatarActivity:animated:`
(`.mm:636-691`) cross-fades both over 0.3 s and hides the edit strip while uploading; on hide it
restores `_avatarViewEdit.hidden = _avatarView.currentUrl != nil` (`.mm:689`) — note the inverted
sense there, which is arguably an original bug (edit strip hidden when a URL *is* present) but is
immediately corrected by the next `updateTitle`.

### Title and subtitle (display state)

```
_conversationTitleLabel   frame (92, 24, width-92-9, 24)
                          bold 19, colour 0x222932, shadow rgba(0xedf0f5, 0.28) offset (0, 1)   .mm:517-524
_conversationSubtitleLabel frame (93, 49 + retinaPixel, width-92-9, 24)
                          system 14, colour 0x6d7d90, same shadow                                .mm:526-533
```

Note the deliberate one-point difference between the title's x (92) and the subtitle's x (93): the
lighter, non-bold subtitle needed a nudge to look optically aligned. Neither label wraps or
truncates specially — they are single-line `UILabel`s at a fixed width, so a long group name is
tail-truncated by UIKit at `width - 101`.

Subtitle text is built unconditionally as `"%d %s"` with `member`/`members`
(`.mm:1115-1116`) — **hardcoded English, not localised**, and with no "N online" part. If
`chatParticipantCount` is 0 it reads "0 members".

### Title field (editing state)

- Background: `[TGInterfaceAssets groupedCellSingle]` (`GroupedCellSingle.png`, centre-stretched,
  `TGInterfaceAssets.mm:703-709`) at `(89, 14, width-89-9, 44)` in info mode, or
  `(9, 14, width-18, 44)` in createChat mode (`.mm:535-537`). Hidden + alpha 0 initially.
- Field: the background rect inset by `(12, 10)` and offset `(0, 1)` (`.mm:544`), bold 16,
  `returnKeyType = Done`, placeholder `ConversationProfile.GroupName` = "Group Name" with
  placeholder colour `0x8d98a6` forced via `TGHacks` (`.mm:546-552`).
- Tapping the *background* focuses the field (`focusOnTitleField:`, `.mm:539`, `.mm:2200-2206`).
- Length cap: the field rejects edits that would push the caret past **256** characters
  (`.mm:2208-2214`).

In createChat mode the avatar, add-photo button and both activity views are removed from the
hierarchy entirely (`.mm:555-561`) — the header is just the full-width name field.

---

## 4. Cell backgrounds: the grouped nine-slice system

There are no separators. Instead `updateGroupedCellBackground()` (`.mm:1243-1293`) assigns each cell
a `backgroundView`/`selectedBackgroundView` image pair by its position in the section:

| Position | Normal | Highlighted |
|---|---|---|
| only row | `groupedCellSingle` | `groupedCellSingleHighlighted` |
| first | `groupedCellTop` | `groupedCellTopHighlighted` |
| last | `groupedCellBottom` | `groupedCellBottomHighlighted` |
| middle | `groupedCellMiddle` | `groupedCellMiddleHighlighted` |

The highlighted variants use `resizableImageWithCapInsets:` with insets
`(5, 13, 6, width-13-1)` when available, falling back to a centre stretch on iOS 5
(`TGInterfaceAssets.mm:711-722`). The normal variants are plain centre stretches
(`TGStretchableImageInCenterWithName`).

`TGGroupedCell` (`TGGroupedCell.h/.m`) exists purely to make the *highlight* look continuous:
when a middle-or-first cell is selected, `extendBackgroundSize()` grows the selected background by
**1 point** (`TGGroupedCell.m:3-15`) so it covers the seam with the next cell, and `adjustOrdering`
(`:87-112`) re-inserts the cell as the topmost cell subview so its overhanging highlight is not
clipped by its neighbour. This is the trick that makes a 2013 grouped list highlight look like a
single painted block rather than a stack of images.

Two cell types opt out and set both images to `nil` (`clearBackground`, `.mm:1364`, `.mm:1389`,
`.mm:1556-1560`): the single-button row and the buttons-pair row, because those draw their own
button artwork.

Row removal animates the seam: after deleting a member row the cell *above* it is re-skinned with
`animated:true`, i.e. a 0.3 s cross-dissolve of its background image (`.mm:3318-3323`,
`.mm:1280-1286`).

---

## 5. The Add Member / Leave Group pair

`TGButtonsMenuItemView` (`TGButtonsMenuItemView.m`), row height 43.

- Artwork: `GroupedActionButton.png` / `GroupedActionButton_Highlighted.png`, stretched with left cap
  = half width, top cap 0 (`:116-120`). The button's height comes from the *image's own height*
  (`:122`), so the 43-point row is sized around the artwork, not the other way round.
- Title: bold 14, colour `0x4a6587`, shadow `rgba(0xffffff, 0.45)` offset `(0, 1)`; when highlighted,
  white text with a clear shadow (`:125-131`).
- A `green` variant exists (`GroupedActionButtonGreen*`, white bold **16**, shadow
  `rgba(0x124606, 0.3)` offset `(0, -1)`, `:86-104`) — unused by this screen, but it is the same
  component used elsewhere for the affirmative button.
- Layout (`:139-153`): two buttons → each `floorf((contentWidth - 10) / 2)` wide, left flush at 0,
  right flush at the right edge, so the gutter absorbs the rounding. One button → full content width.
  There is never a three-button state; `setButtons:` only ever fills `_leftButton` and `_rightButton`
  (`:79`), and extra dictionary entries silently overwrite the right button.
- `disabled: @(true)` sets `alpha = 0.7` and `enabled = NO` (`:82-84`).
- Presses are not target/action to the controller; the cell fires
  `actionStageActionRequested:@"buttonsMenuItemAction"` with the dictionary's `action` string
  (`:155-175`), which the controller maps to `addParticipantButtonPressed` / `leaveConversationButtonPressed`
  (`.mm:2959-2967`).
- `setButtons:` early-outs when titles and disabled flags are unchanged (`:42-70`) — a cheap guard
  against re-creating artwork on every reload.

The content view's inset (the 9-point margin) comes from the grouped table itself, not from this
cell, which lays out at x = 0 within `contentView`.

---

## 6. Member rows (`TGUserMenuItemCell`)

Height 49. Layout in `layoutSubviews` (`TGUserMenuItemCell.m:377-389`), with
`paddingLeft = editing && !alwaysNonEditable ? 37 : 0`:

```
avatar    (paddingLeft + 6, 6, 36, 36)          filter "memberListAvatar" family
title     (paddingLeft + 50, 5, w - 76 - paddingLeft, 22)   bold 15 + retinaPixel
subtitle  (paddingLeft + 50, 24 + retinaPixel, same width, 18)  system 13 + retinaPixel
```

The trailing `26` in the width expression reserves room for the disclosure/edit area.

Colours (`resetView:`, `:278-293`): when the subtitle is "active" (the user is online, or is
yourself) **both** title and subtitle turn `0x0779d0`; otherwise title is black and subtitle
`0x888888`. Highlighted text is white in both cases (`:128`, `:141`).

Subtitle text (`subtitleTextForUser`, `.mm:1573-1597`):

| Condition | Text | Active? |
|---|---|---|
| `presence.online`, or uid == self | `Presence.online` | yes |
| `lastSeen < 0` | `Presence.invisible` | no |
| `lastSeen != 0` | `Time.last_seen` + `[TGDateUtils stringForRelativeLastSeen:]` | no |
| `lastSeen == 0` | `Presence.offline` | no |

Note the deliberate lie: *you* are always shown as online in your own group's member list.
`updateRelativeTimestamps` (`.mm:1599-1619`) re-runs this for visible cells on the
`/as/updateRelativeTimestamps` tick and only touches the cell if the string or the active flag
actually changed.

### Removal affordance

Not UIKit's. `_switchButton` is a 30×30 button at `(16 + retinaPixel, 11)` showing
`ListEditingSwitch.png` with a minus glyph centred at `(15, 14)` (`:106-118`); the actual red button
is `_editingButton`, 61×31 at `y = 9`, right edge inset `TG_DELETE_BUTTON_EDGE_OFFSET = 16`
(`:14`, `:153`), background `ListDeleteButton.png` / `_Highlighted`, with the word
`Common.ListDelete` pre-rendered into an image (bold 13, shadow `rgba(0xa30f0a, 0.2)` offset
`(0,-1)`) and centred with a 7-point top offset (`:91-100`, `:157-159`). It is created collapsed to
2 points wide (`:165`) and expands on swipe. The whole thing is coordinated by `TGActionTableView`,
which tracks a single "action cell" at a time.

### Who may be removed

`updateEditableStates` / the `cellForRow` branch (`.mm:848-907`, `.mm:1513-1533`):

- an action already in flight for that uid → editable (so you can see the spinner state);
- **yourself → never editable**;
- if you are `chatAdminId` → everyone editable;
- otherwise → only users whose `chatInvitedBy` is you.

If *no* member is editable, `_allUsersAreNotEditable` is set and pushed to every visible cell as
`alwaysNonEditable` (`.mm:893-906`), which zeroes the 37-point editing indent — so entering edit mode
in a group you don't administer does not shift the list sideways for nothing.

### In-flight state

`_usersWithActionInProgress` is a `std::set<int>`, rebuilt on init from ActionStage's rejoinable
actions (`.mm:276-306`) so that re-opening the screen mid-request still shows the disabled rows.
`setIsDisabled:animated:` fades a white overlay inset `(12, 6)` over the cell (`:170-175`).
`commitAction:` deliberately sets `isDisabled:false animated:false` then `true animated:true`
(`.mm:1672-1673`) to force the fade to play from a known state.

Tapping a member (`.mm:1708-1724`) navigates to that user's profile — unless it is you, unless the
table is editing, and unless this is createChat. Deselection is animated only when not editing.

---

## 7. Editing mode (`updateEditingState:explicitState:`, `.mm:2269-2682`)

Entered from a nav-bar "Edit" `TGToolbarButton` (`minWidth 51`, `.mm:2477-2484`); leaving restores it.
In editing mode the bar shows Cancel (`TGToolbarButtonTypeGeneric`, `minWidth 59`) on the left and
Done (`TGToolbarButtonTypeDone`, `minWidth 51`) on the right, Done disabled while the title is empty
(`.mm:2275-2293`). In createChat mode instead: back action + a single "Create" Done button,
`minWidth 60`, enabled only when the title has a non-space character (`.mm:2299-2309`).

What changes, all over 0.3 s (`.mm:2315-2340`, `.mm:2489-2516`):

1. Title label + subtitle label fade to 0 and are then hidden; the title field and its
   `GroupedCellSingle` background fade in. Reverse on exit.
2. The avatar "edit" strip fades in/out (`.mm:2663-2673`).
3. **The Shared Media row is replaced by a "Sound" row** — and back again on exit
   (`.mm:2342-2380`, `.mm:2518-2557`). This is the single most characteristic behaviour of the
   screen: notification sound is only reachable while editing. The swap is done without a row
   animation (`UITableViewRowAnimationNone`) but with a hand-rolled cross-fade: the old cell is
   snapshotted with `renderInContext:` into a `UIImageView`, the item is swapped, and the snapshot is
   laid over the new cell and faded to 0. That is why the transition looks like a dissolve rather
   than a UIKit row reload.
4. All visible member cells switch `selectionStyle` between `None` (editing) and `Blue`
   (`.mm:2675-2681`).

The Sound row is a `TGVariantMenuItem` titled `ConversationProfile.Sound`, default variant
`ConversationProfile.DefaultSound` = "Default" (`.mm:239-243`); its variant text comes from
`[TGAppDelegateInstance alertSoundTitles]` indexed by `soundId`, falling back to the literal
`"Sound %d"` when the id is out of range (`.mm:3603-3607`) — that fallback is what you see after a
future server adds a sound this build doesn't know.

Committing the title (`textFieldShouldReturn:`, `.mm:2685-2718`): resign, leave editing, and only if
the trimmed text is non-empty *and different* fire `/tg/conversation/(id)/changeTitle/(Na)`. While
the change is in flight, the field is disabled and greyed to `0x999999` and the display label to
`0x66727f` (`.mm:2705-2709`; the rejoin path at `.mm:349-354` uses `0x888888` for the field — a
genuine inconsistency in the original, two different greys for the same state).

Cancel restores the field and label from `_conversation.chatTitle` (`.mm:2737-2738`).

---

## 8. Other states

**Left / kicked** (`updateTitle`, `.mm:1118-1181`). The right bar button's custom view is set to
`alpha 0`, and a full-bleed `_leftChatContainer` (background `linesBackground`) is added over
everything with a single centred label: bold 15, colour `0x697487`, shadow `rgba(0xffffff, 0.7)`
offset `(0, 1)`, text `ConversationProfile.KickedFromChat` ("You were kicked from the group") or
`ConversationProfile.LeftChat` ("You have left the group") (`.mm:1128-1136`, strings at
`Localizable.strings:402-403`). Returning to the chat fades the container out over 0.3 s
(`.mm:1170-1180`). The label is re-centred with `CGRectIntegral` on every update.

**Avatar tap** (`addPhotoButtonPressed`, `.mm:2163-2188`): ignored entirely while an upload spinner
is visible. With a photo → action sheet Open Photo / Update Photo / **Delete Photo** (destructive,
index 2) / Cancel (index 3). Without → straight to the source sheet: Take Photo / Choose Photo /
Search Web Images / Cancel (`.mm:2066-2072`). Delete asks a second time with
`ConversationProfile.DeleteGroupPhotoConfirmation` = "Delete Photo?" (`.mm:1871`).

**Open photo** (`.mm:1878-1910`) builds a 640×640 `TGImageInfo` from `chatPhotoBig` and animates a
`TGImageViewController` out of the avatar's window-space rect, hiding the avatar during flight.

**Camera / picker result** (`_updateProfileImage:`, `.mm:2102-2138`): JPEG at quality **0.6**, run
through the `profileAvatar` filter for the local preview, then either stashed for createChat or
uploaded via `/tg/conversation/(id)/updateAvatar/(aN)`. `UIImagePickerController` results are
force-squared: the crop rect is expanded on the short axis and the image fixed and cropped to
**600×600** (`.mm:2082-2097`).

**Add member errors** (`.mm:3339-3352`): default `UnknownAddMemberError`; result code `-2` →
`UserLeftChatError` formatted with the display name; `-3` → `UsersTooMuchError` ("Sorry, this group
is full."). Selecting a contact who is already in the chat is caught *before* the request with
`UserAlreadyInChat` (`.mm:2891-2900`), and adding always goes through a confirmation alert
`"Add %@ to the group?"` (`.mm:2907`).

**Member list churn** (`chatInfoChanged:`, `.mm:909-1089`) is throttled: a full members-section
reload is deferred so that two reloads never land within **0.301 s** of each other
(`.mm:1030-1038`). Sorting is a two-stage affair — the database order puts the creator first then
by invite date (`.mm:919-930`), and the display order re-sorts online users first, then invisible,
then by `lastSeen` descending, tie-broken by invite date and finally uid (`.mm:805-846`). Reloads
happen with `[UIView setAnimationsEnabled:false]` around them (`.mm:1019-1022`) — the sort changes
often enough that animating it would look like a twitch.

**Dismiss keyboard**: any table drag calls `[self.view endEditing:true]` (`.mm:2264-2267`). A
right-swipe anywhere on the table pops the controller (`.mm:601-604`, `.mm:627-634`) — the 2013
substitute for the interactive back gesture.

---

## 9. Our port

Our equivalent is **not** a dedicated class: it is `TGProfileViewController`
(`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGProfileViewController.m`, 4986 lines), which serves
both users and groups; `isGroupProfile` is `userId == 0 && chatId != 0` (`:367-369`) and the title
becomes "Group Info" (`:373`). Member removal and admin management were split out into
`TGGroupMembersViewController.m`.

Much of it is right. `TGProfileButtonsCell` (`:245-289`) reproduces `TGButtonsMenuItemView` almost
exactly — same artwork, same `0x4a6587`, same bold 14, same `floorf((w - 10)/2)` split, same
`alpha 0.7` disabled treatment. The header colours (`0x222932`, `0x6d7d90`, shadow
`rgba(0xedf0f5, 0.28)` offset `(0,1)`), the 70-point avatar with radius 10, the 19/14 pt fonts and
the member row's `bold 15 + retinaPixel` / `13 + retinaPixel` fonts are all faithful. Section header
height 8 and footer 1 for group profiles (`:3025-3044`) match `.mm:1233-1241`. Row height 49 for
members, 43 for the button pair, 44 default — all match.

### Defects a user can see

1. **Section order is wrong.** `rebuildSections` (`:1553-1567`) emits
   `details → actions → [manage] → members → media`, putting Notifications and Shared Media *last*.
   The original has Notifications + Shared Media as the **first** section, then the button pair, then
   members (`.mm:221-266`). Fix: for `isGroupProfile`, order the kinds
   `media (notifications + shared media) → actions → members → manage`.

2. **No grouped nine-slice cell artwork.** Our rows go through `[[TGTheme shared] styleCell:]`
   (`TGTheme.m`), i.e. stock UIKit grouped chrome. The original assigns
   `GroupedCellTop/Middle/Bottom/Single` (+ `_Selected`) images per row position
   (`.mm:1243-1293`) and uses `TGGroupedCell`'s 1-point highlight extension and z-reordering
   (`TGGroupedCell.m:3-15`, `:87-112`). This is the largest visual gap on the screen: our selection
   highlight will show a seam between adjacent rows where the original's does not. The assets are
   already in the repo (`TGNewContactViewController.m:429` uses `GroupedCellTop.png`), so this is a
   port of `updateGroupedCellBackground` plus a `TGGroupedCell` base class, not new artwork.

3. **Online members are not tinted blue.** `plainRowCell:` (`:3166-3193`) always paints the title
   `primaryTextColour` and the subtitle `0x888888`. The original turns **both** labels `0x0779d0`
   when the member is online or is you (`TGUserMenuItemCell.m:284-288`, active flag from
   `.mm:1578-1582`). We already have the online flag available for the header status
   (`:824-828` uses `0x316ea1` for user status, itself a different blue from the original's
   `0x0779d0` — worth checking against the profile study).

4. **Header geometry off by a few points.** Ours: header height `kTitleContainerHeight = 86`
   (`:181`), name at x = 94 y = 24, status at x = 94 y = 52 (`:751-796`). Original: header 89
   (`.mm:420`), title at x = **92** y = 24, subtitle at x = **93** y = `49 + retinaPixel`
   (`.mm:517`, `.mm:526`). The subtitle sits three points lower in ours and the block is three points
   shorter overall, so the header reads as vertically cramped against the first section.

5. **No avatar overlay and no 69/70 inset.** We set `cornerRadius = 10` + `clipsToBounds`
   (`:719-721`), which gets the radius right but drops `ProfileAvatarOverlay.png` and the
   `{69,69}` inside `{70,70}` with `(0.5, 0)` offset from the `profileAvatar` processor
   (`TGTelegraph.mm:503`). The 2013 avatar has a visible bevelled border; ours is a bare rounded
   square.

6. **No "add photo" state.** When a group has no photo the original shows the
   `ProfilePhotoPlaceholder.png` button with the two stacked white labels "add" / "photo"
   (`.mm:458-492`) and disables interaction on the avatar view itself (`.mm:1112`). Ours falls back
   to `[TGIcons avatarWithInitials:]` (`:730-733`) — a modern-Telegram initials circle, which is
   exactly the anachronism this project is trying to avoid on this screen.

7. **No inline editing mode.** There is no Edit/Done/Cancel nav pair, no title text field in the
   header, no avatar "edit" strip, and consequently **no Shared Media ↔ Sound row swap**
   (`.mm:2342-2380`). Renaming happens through a `manage` row "Group Name" that opens a
   `UIAlertView` text field (`:1660`, `:1502`, `renameChatTo:` at `:1538`). Sound selection appears
   to be absent from the group screen entirely. Whether to restore inline editing is a product call
   — the modern client also moved to a separate edit mode — but the *Sound-only-while-editing*
   behaviour is the reason a Sound row is missing, and someone should decide consciously rather than
   by omission.

8. **No swipe-to-remove on member rows.** The original allows it on the members section
   (`.mm:1623-1626`) with the custom 61×31 red "Delete" button
   (`TGUserMenuItemCell.m:153-165`) and the admin/inviter rules at `.mm:1513-1533`. Neither
   `canEditRowAtIndexPath` nor `commitEditingStyle` exists in `TGProfileViewController.m`; removal
   lives only in `TGGroupMembersViewController`.

9. **No in-flight member state.** No equivalent of `_usersWithActionInProgress` / the white
   fade overlay (`.mm:1663-1677`, `TGUserMenuItemCell.m:170-175`), so an add or remove shows nothing
   until the list refreshes.

10. **Member subtitle relies on whatever the client returns.** Ours prints `member[@"status"]`
    verbatim (`:3188`). The original derives it locally with the four-way rule in
    `subtitleTextForUser` (`.mm:1573-1597`), including showing *yourself* as online. Worth checking
    that `TGClient` produces the same four strings, otherwise offline members will read differently.

11. **Member count string.** Ours: `"%ld member%@"` (`:857-859`), a close match to the original's
    `"%d %s"` with member/members (`.mm:1116`) — this one is fine, and both are equally
    unlocalised. But ours prefers a `groupOnlineSummaryForChat:` string when available (`:844-853`),
    which will render "12 members, 3 online" — a modern format the original never showed. Acceptable
    as an evolution, but it is a visible difference.

Ambiguities I will not paper over: the original's `_avatarViewEdit.hidden` logic at `.mm:689` is
self-contradictory with `.mm:1104`, and the two greys for an in-flight title (`0x888888` at
`.mm:351` vs `0x999999` at `.mm:2706`) are inconsistent in the source itself. Pick either; nobody
can tell you which was intended.

---

## 10. What became of it

### Modern client (`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS`)

`PeerInfoScreen` (`submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift`,
7554 lines) plus ~50 sibling files. The structural descendants are visible:

- The Add Member / Leave pair became a *row of icon buttons* under the avatar:
  `PeerInfoHeaderButtonKey` (`PeerInfoHeaderButtonNode.swift:11-24`) is
  `message, discussion, call, videoCall, voiceChat, mute, more, addMember, search, leave, stop, addContact`.
  `addMember` and `leave` survived thirteen years, in the same place on the screen, as the same
  concept — but the two wide text buttons became five-or-six narrow icon buttons because the set grew
  past two. That is a change **forced by feature growth**, not taste.
- The editing mode survived as a whole subsystem:
  `PeerInfoHeaderEditingContentNode`, `PeerInfoHeaderSingleLineTextFieldNode`,
  `PeerInfoHeaderMultiLineTextFieldNode`, `PeerInfoEditingAvatarNode`,
  `PeerInfoEditingAvatarOverlayNode`. The 2013 idea — *the header itself becomes editable in place,
  the avatar grows an "edit" affordance* — is still exactly the idea. It just needed five classes
  instead of six ivars.
- Members became a *pane* (`PeerInfoMembers.swift`, `PeerInfoPaneContainerNode.swift`) rather than a
  table section, because a supergroup has 200 000 members and a 2013 `NSMutableArray` of
  `TGUserMenuItem` does not. Forced.
- The Sound-hidden-behind-Edit trick is gone. Notifications got their own sub-screen. That one was
  taste, and the modern answer is better.

### twelve (`/Users/alexanderhavrysh/Git/iOS/twelve`)

Here the class is actually called `TGGroupInfoController` (`Telegraph/TGGroupInfoController.m`), and
it is the same design one generation on, still Objective-C, still item-driven. The interesting part
is what it kept:

- The header became a *collection item*, `TGGroupInfoCollectionItem`
  (`TGGroupInfoController.m:139-151`), with `setUpdatingTitle:` /
  `setUpdatingAvatar:hasUpdatingAvatar:` (`:307-309`) — the same two in-flight states, now
  encapsulated instead of poked at as labels.
- **The Shared Media ↔ Sound swap survived verbatim** (`:444-454` swaps `_sharedMediaItem` for
  `_soundItem` on entering editing; `:479-490` swaps back). Thirteen months later they still thought
  that was the right interaction. Strong evidence it was intentional design, not an accident.
- Sections multiplied rather than reorganised: `_groupInfoSection`, `_notificationsAndMediaSection`,
  `_usersSection`, `_leaveSection` (`:73-110`), plus items appearing and disappearing at runtime
  (`_chatAdminsItem`, `_addParticipantItem`, `_setGroupPhotoItem`, `:345-369`). The leave action moved
  out of the button pair into its own bottom section — the same move the modern client would later
  make for a different reason.
- Member rows are now `TGGroupInfoUserCollectionItem` / `...ItemView`
  (`TGGroupInfoUserCollectionItemView.m`, 474 lines) — a hand-drawn item view rather than a
  `UITableViewCell`, which is how they eventually escaped `TGActionTableView`'s single-action-cell
  limitation.

For our purposes twelve is the better guide to *where to put new features* (a dedicated leave
section, items that appear conditionally) while the 2014 original remains the authority on how any
individual pixel looks.

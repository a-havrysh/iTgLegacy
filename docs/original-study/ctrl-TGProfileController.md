# TGProfileController (original, Telegram for iOS v1.1 build 21024)

Source of truth for everything below:
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGProfileController.h`
(35 lines) and `.../TGProfileController.m` (5393 lines). Line numbers in this document
refer to those two files unless another path is named.

The class exists under exactly that name — no substitution was needed. Its sibling
`TGTelegraphConversationProfileController.mm` handles *group* chats and is a separate,
similarly shaped controller; it is out of scope here except where noted.

---

## 1. What it is

One controller that plays seven different screens. It is simultaneously:

* the **Settings tab** (mode `Self`),
* a **user profile** pushed from a chat or the contact list (mode `TelegraphUser`),
* a **phonebook-only contact** card (mode `PhonebookContact`),
* the **new-contact** form, the **add-number-to-existing-contact** form, and two
  phonebook variants of the same (modes 3–6).

The mode enum is private, at `TGProfileController.m:185-193`:

```
Self = 0, TelegraphUser = 1, PhonebookContact = 2, CreateNewContact = 3,
AddToExistingContact = 4, AddToExistingPhonebookContact = 5, CreateNewPhonebookContact = 6
```

Mode is *not* passed in. It is derived from which initialiser was used
(`:436`, `:465-467`, `:509`, `:552`) and, for `initWithUid:`, from whether the uid equals
`TGTelegraphInstance.clientUserId` (`:1016-1028`, again at `:3884-3886` when the user record
arrives). This matters: the Settings tab is constructed with **uid 0**
(`TGAppDelegate.mm:293`, `_myAccountController = [[TGProfileController alloc] initWithUid:0 …]`)
and only becomes "Self" once the client user id is known.

The screen is a `UITableViewStyleGrouped` table (`TGActionTableView`) with a custom
86pt `tableHeaderView` carrying avatar, name and status. All grouped-cell rounding is
drawn by the app itself with stretched PNGs; the system separators are off.

## 2. Public surface (`TGProfileController.h`)

```objc
@property (nonatomic, strong) ASHandle *actionHandle;
@property (nonatomic, strong) NSString *overrideFirstName;   // :20
@property (nonatomic, strong) NSString *overrideLastName;    // :21

- (id)initWithUid:(int)uid preferNativeContactId:(int)id encryptedConversationId:(int64_t)cid;
- (void)switchToUid:(int)uid;
- (int)uid;
- (id)initWithPhonebookContact:(TGPhonebookContact *)contact;
- (id)initWithCreateNewContact:(TGUser *)user watcherHandle:(ASHandle *)h;
- (id)initWithAddToExistingContact:… ;
- (id)initWithAddToExistingPhonebookContact:… ;
- (void)_updateProfileImage:(UIImage *)image;
```

`overrideFirstName`/`overrideLastName` exist so a caller can show a name the server does
not know yet; `userFirstName`/`userLastName`/`userDisplayName` (`:1139-1171`) prefer the
override pair *as a pair* — if either override is non-nil, both server names are ignored,
so setting only the first name deliberately blanks the last name.

`switchToUid:` (`:978-1040`) lets the Settings tab be re-pointed after login without being
recreated: it tears down all ActionStage watchers, nils `_user`, `_phonebookContact`,
`_userLink`, and re-subscribes. It also force-exits editing mode.

Call sites: `TGInterfaceManager.mm:179` and `:188` (push a user profile),
`TGContactsController.mm:1705` (phonebook contact), `:2345` (new contact),
`TGAppDelegate.mm:293` (Settings tab), and `TGProfileController.m:152/161/3152`
(add-to-existing flows started from inside itself).

## 3. The header ("title container") — every metric

Built in `loadView`, `:704-799`. `retinaPixel = TGIsRetina() ? 0.5f : 0.0f` (`:723`).

| Element | Frame / value | Line |
|---|---|---|
| container `TGView` | `(0, 0, viewWidth, 86)`, `hitTestMatchAll = true`, `backgroundColor = nil`, `clipsToBounds = false` | 704-709 |
| set as `tableView.tableHeaderView` | — | 711 |
| extra table inset | `setExplicitTableInset:UIEdgeInsetsMake(0,0,7,0)` (7pt bottom) | 713 |
| avatar `TGRemoteImageView` | `(9, 14, 70, 70)`, `fadeTransition = true`, `exclusiveTouch` | 715-718 |
| upload-progress mask | `AddPhotoMask.png` stretched from its centre, frame `(9 + retinaPixel, 14, 69, 69)`, starts hidden at alpha 0 | 725-732 |
| upload spinner | `TGActivityIndicatorViewStyleSmallWhite`, origin offset `(36 + retinaPixel, 42)` | 734-739 |
| "Add / Photo" button | same frame as avatar, `TGHighlightableButton`, inserted *below* the avatar | 741-751 |
| name label | `(94, 24, width - 94 - 9, 24)` — **y = 35 instead of 24 when mode is `PhonebookContact`** | 777 |
| name font/colour | `boldSystemFontOfSize:19`, `#222932`, shadow `#edf0f5` at 0.28 alpha, offset `(0, 1)` | 780-783 |
| status `TGDateLabel` | `(94, 52, width - 94 - 9, 24)` | 786 |
| status font/colour | `systemFontOfSize:14`, `#6d7d90`, same shadow as the name | 789-792 |
| status date sub-fonts | `dateFont` = 14, `dateLabelFont` = 12, `amWidth = pmWidth = 20`, `dstOffset = 2 + retinaPixel` | 793-798 |

Why 86: avatar top 14 + 70 = 84, plus 2pt of breathing room; the 7pt explicit bottom inset
at `:713` is what actually separates the header from the first grouped section, not the
header height.

Why the name sits at y = 24 with a 24pt box: 19pt bold caps out around 23pt of line box,
and the status baseline at y = 52 leaves exactly 4pt between the two 24pt boxes. When the
status is structurally absent — the phonebook-contact card, which sets
`_statusLabel.text = nil` (`:1645`) — the name is pushed to y = 35 so it optically centres
against the 70pt avatar. **That single-line variant is a real state, not a rounding
accident.**

Long names: the name label is a plain `UILabel` with default truncation, width
`viewWidth - 103`. On a 320pt screen that is 217pt, so long names tail-truncate with an
ellipsis. There is no shrink-to-fit and no second line.

### Avatar artwork and the `profileAvatar` filter

The avatar is never drawn as "a 70×70 image with corner radius". It is produced by a
registered `TGRemoteImageView` image processor named `profileAvatar`
(`TGTelegraph.mm:501-504`):

```objc
TGScaleAndRoundCornersWithOffsetAndFlags(source,
    CGSizeMake(69, 69),        // the photo is drawn 69×69
    CGPointMake(0.5f, 0),      // offset half a point to the right
    CGSizeMake(70, 70),        // inside a 70×70 canvas
    10,                        // corner radius 10
    [TGInterfaceAssets profileAvatarOverlay],   // ProfileAvatarOverlay.png, drawn on top
    false, nil, TGScaleImageScaleOverlay);
```

`profileAvatarOverlay` is `ProfileAvatarOverlay.png` stretched from its centre
(`TGInterfaceAssets.mm:442-448`). It supplies the inner bevel/edge darkening that makes the
2013 avatar look inset rather than pasted on. The half-point x offset is what keeps the
69pt image visually centred in the 70pt slot on a retina screen.

Placeholders (`TGInterfaceAssets.mm:450-477`):

* `profileAvatarPlaceholder:uid` — uid ≤ 0 → `ProfilePhotoPlaceholderGeneric.png`;
  uid == 333000 (Telegram service account) → `ProfileAvatarSystem.png`; otherwise
  `ProfileAvatar%d.png` with `colorIndexForUid(uid) + 1`, i.e. one of eight coloured
  silhouettes, `ProfileAvatar1…8`.
* `profileAvatarPlaceholderEmpty` — `ProfilePhotoPlaceholder.png`, used as the *transient*
  placeholder while a real photo loads (`:1730`, `:1733`).

### Three avatar states (`updateTitle:`, `:1722-1791`)

The whole block is skipped while an upload overlay is visible
(`_avatarActivityOverlay.alpha < FLT_EPSILON` guard, `:1722`) and only runs when the URL
actually changed.

1. **Photo present** — load `photoUrlSmall` through the `profileAvatar` filter, fade
   duration 0.3 animated / 0.14 not (`:1726`); avatar to alpha 1, the "Add Photo" button
   fades to 0 and is then hidden (`:1737-1754`).
2. **No photo, mode Self** — the reverse: `_addPhotoButton` unhidden and faded in, avatar
   faded out and its image cleared (`:1758-1782`).
3. **No photo, anyone else** — `profileAvatarPlaceholder:_uid` loaded straight into the
   avatar, add-photo button hidden outright (`:1786-1788`). Other people never get an
   "Add Photo" affordance.

The "Add Photo" button is itself two stacked white labels over a stretched
`ProfilePhotoPlaceholder.png` / `_Highlighted.png` background (`:745-775`):
`Profile.PhotoAdd` at y = `16 + retinaPixel` and `Profile.PhotoPhoto` at y = 33, both
`boldSystemFontOfSize:14 + retinaPixel`, white, shadow `#47586c` at 0.5 alpha offset
`(0, -1)`, each horizontally centred by `sizeToFit` then `CGRectIntegral`. Two labels
rather than one two-line label because the word split had to be controlled per-language.

### Upload state

`setShowAvatarActivity:animated:` (`:906-971`) fades the `AddPhotoMask` overlay and the
small white spinner in over 0.3s, and simultaneously disables the "Set Profile Photo"
menu row (`TGSetProfilePhotoTag`) by flipping `photoItem.enabled` and calling
`setEnabled:` on the live cell. On `viewWillAppear`, `rejoinActions` (`:2199-2273`)
re-attaches to any in-flight upload/delete actor and *restores* this state, including
showing the half-uploaded image via `TGTimelineUploadPhotoRequestBuilder.currentPhoto`
(`:2211-2228`). A rename in flight is restored the same way: fields go to alpha 0.5 and
`enabled = false`, and the name label shows the pending name (`:2240-2258`, `:1686-1700`).

## 4. Sections

Composed from scratch in `updateTable` (`:1795-2070`) into `_sectionList`, an array of
`TGMenuSection`. Nothing is built unless `_user != nil` or a phonebook contact exists
(`:1799`) — before that the whole table is simply `hidden = true` (`:1626-1629`).

**Mode Self** (`:1801-1868`), in order:

1. photo section — one grey `TGButtonMenuItem` "Settings.SetProfilePhoto".
2. general — "Notifications and Sounds", "Blocked Users", "Chat Settings"
   (a Privacy row and a Chat Background row exist but are commented out, `:1818-1832`).
3. wallpapers — a single `TGWallpapersMenuItem`, row height **182** (`:2330`).
4. support/autosave — "Support" action, "Save Incoming Photos" switch, and a
   `TGCommentMenuItem` explanatory footnote.
5. logout — a red `TGButtonMenuItem`, **added only while the table is editing**
   (`:1862-1863`, and toggled in `:1488-1518`).

**Everyone else** (`:1869-2060`):

1. phones (`TGPhonesSectionTag`) — from the phonebook contact's numbers, or the single
   server number, or, if the user has no number at all, one *disabled* row whose phone
   string is literally `@"empty"` (`:1917-1923`). `isMainPhone` is highlighted only when
   there is more than one number (`:1894`).
2. actions — a `TGButtonsMenuItem` (one or two side-by-side buttons) plus an optional
   comment row. Suppressed for secret chats (`_encryptedConversationId != 0`, `:1945`).
3. notifications — switch, "New Photos" switch, sound variant row. **Only inserted while
   editing and only when `_uid > 0`** (`:1982-1983`).
4. media — "Shared Media" row; for a secret chat also "Message Lifetime" and
   "Encryption Key" (the latter carrying a 24×24 identicon generated from SHA-1 of the key,
   `:2028-2034`). Hidden while editing and for phonebook-only contacts (`:2041`).
5. delete — red "Delete Contact". Not shown for the create/add modes or a pure phonebook
   contact (`:2059`).

Action-button contents (`updateActions:`, `:1047-1137`):
phonebook contact → a single green "Invite" button, disabled if a request is already
pending; otherwise "Send Message" plus either "Add Contact" (disabled when the user has no
phone number) or "Share Contact" when a phonebook record already exists. The comment row
under them appears only when the user has no phones *and* a contact request was sent
(`:1098`); note the two comment strings at `:1097` are hardcoded English, not `TGLocalized`
— a genuine bug in the original.

### Row and section metrics

`heightForRowAtIndexPath:` (`:2300-2341`):

| Item type | Height |
|---|---|
| action / phone / switch / variant | 44 |
| button (red/grey/green) | 45 — **but 1 for a secret chat when not editing** (`:2318-2320`) |
| buttons pair | 43 |
| contact media | 44 |
| wallpapers | 182 |
| comment | `[item heightForWidth:_currentTableWidth]` |

`heightForHeaderInSection:` (`:2343-2372`): section 0 → 2 if it is an empty phones section,
else 12, or `18 + 12` while editing; then by tag — phones 12 (0 when empty), media
`10` for secret chats else **28**, actions 10, default 12.
`heightForFooterInSection:` (`:2374-2385`): 0 for the phones section, otherwise
`1 + (retina ? 0.5 : 1.0)`.

`_currentTableWidth` is refreshed in `willRotateToInterfaceOrientation:` (`:2142`) and
`viewWillAppear:` (`:2161`) from `screenSizeForInterfaceOrientation:`, so comment-row
heights are correct *before* the rotation animation, not after.

### Grouped-cell backgrounds

`updateGroupedCellBackground()` (`:229-279`) is the whole rounding system: it picks
`groupedCellSingle` / `Top` / `Bottom` / `Middle` (plus `…Highlighted` for the selected
background) and sets `extendSelectedBackground` false only for the single case. Applied
in `cellForRowAtIndexPath:` (`:2650`) for every cell except buttons, button pairs and
comments (`clearBackground`, `:2489`, `:2514`, `:2638`). Phone cells get a
`TGTransitionableImageView` background (`:2573`) precisely so that inserting or deleting a
number can *cross-fade* the corner artwork over 0.3s (`:269`) instead of popping — see
`:1399-1407` and `:1475-1479`.

A subtlety in `cellForRowAtIndexPath:` (`:2401-2419`): a comment row terminates a visual
group. A row is treated as first-in-section if the row *before* it is a comment, and
last-in-section if the row *after* it is a comment. So one `TGMenuSection` can render as
several rounded blocks separated by explanatory text.

## 5. Editing mode

Entered by the "Edit" bar button (`editingEditButtonPressed`, `:4832-4848`), which deep-
copies the phones into `_editingPhonesSection` so a cancel can discard them, then
`setEditing:true animated:true` + `updateEditingState:` + `updateNavigationButtons:`.

`updateEditingState:` (`:1173-1562`) is where the header morphs. The name/status pair
cross-fades over 0.3s against `_editNameContainer` (`:1257-1281`), created lazily at
`:1179-1252`:

* container `(90, 14, containerWidth - 90 - 9, 88)`
* first-name plate `(0, 0, w, 44)` using `groupedCellTop`; last-name plate `(0, 44, w, 44)`
  using `groupedCellBottom` — two 44pt halves of one rounded 88pt block, each with its own
  tap recogniser that focuses the field underneath
* first-name field `(15, 12, w - 20, 22)`, last-name field `(15, 55, w - 20, 22)`,
  both `boldSystemFontOfSize:16`, black, clear-button while editing
* placeholders `Profile.FirstNamePlaceholder` / `Profile.LastNamePlaceholder`; the first
  field's return key is **Next**, the second's is default (`:1204`, `:1217`)

Initial field text depends on mode (`:1224-1250`): Self uses `realFirstName`/`realLastName`
(the server's own record, not any local override); phonebook modes use the phonebook
record; a Telegram user with no name at all gets two empty fields rather than nil.

Sections shuffle while editing (`:1316-1485`): media and actions sections are deleted,
notifications is inserted, the action-buttons cell fades to alpha 0 over 0.2s, and the
phones section grows a fresh empty row (with the first unused label from
`[TGSynchronizeContactsManager phoneLabels]`, defaulting to `Profile.LabelMobile`) whenever
the last row is non-empty. Leaving edit mode removes every empty phone row again
(`:1456-1481`). Newly inserted rows have their editing state kicked
(`setEditing:false` then `setEditing:true animated:true`, `:1412-1420`) because UIKit does
not animate the delete control into a row inserted inside the same `beginUpdates` block.

Navigation buttons (`:4758-4809`): editing shows a `TGToolbarButton` "Cancel"
(`minWidth 59`) on the left and a `TGToolbarButtonTypeDone` "Done" (`minWidth 51`,
tag `0x28DB5B6A`) on the right; non-editing restores the back action and an "Edit" button
(`minWidth 51`, `:625-642`). The Edit button is created hidden unless the mode is Self, or
TelegraphUser with `TGUserLinkMyContact` set (`:632`). Done is enabled only when Self has
both names filled, or, for a contact, when at least one phone is non-empty **and** at least
one of the two names is non-empty (`:4811-4830`).

Because the Settings tab lives inside a tab controller rather than its own navigation bar,
`setLeftBarButtonItem:` / `setRightBarButtonItem:` are overridden (`:591-655`) to stash the
items locally when `self == TGAppDelegateInstance.myAccountController` and let the tabs
controller pull them via `controllerLeftBarButtonItem` / `controllerRightBarButtonItem`.

## 6. Taps and other behaviour

* **Avatar tap** (`:2964-2973`): if no upload overlay, behaves as `addPhotoButtonPressed`;
  if an upload is running, opens the "Stop upload?" action sheet instead.
* **`addPhotoButtonPressed`** (`:3003-3026`): mode Self with no current photo → camera;
  mode Self with a photo, or any other user when not editing → `openAllPhotos`, i.e. the
  profile-photo gallery. Editing suppresses it for other users.
* **Phone row tap** (`:2927-2949`): while editing, pushes the label picker modally;
  otherwise dials `tel:`, falling back to `facetime:` when `tel://` cannot be opened —
  which is the iPod touch / iPad case.
* **Shared media row** (`:2951-2953`): `navigateToMediaListOfConversation:` with the
  encrypted peer id for secret chats, plain uid otherwise.
* **Action / variant rows** dispatch by stored `SEL` via `performSelector` (`:2898-2919`);
  switch rows deliberately do nothing on row tap (`:2920-2926`, the body is commented out)
  so only the switch itself toggles.
* **Right swipe on the table** (`:801-804`, `tableViewSwiped:` `:3408`) is wired as a
  gesture on the table view.
* **Secret-chat title**: `Profile.SecretTitle` prefixed with three spaces and a
  `ProfileLockIcon.png` image view (tag 12345) added into the title label at
  `(0, 6)` portrait / `(0, 4)` landscape (`:671-684`, re-positioned on rotation at
  `:2127-2132`). The three spaces are the layout mechanism for the lock glyph.
* **Empty/unloaded data**: `viewWillAppear:` blocks on an `NSCondition` for **up to 0.3s**
  waiting for the user record (`:2152-2159`) so the push does not animate into a blank
  screen; if it still has not arrived, the table stays hidden (`:1626-1629`) and the header
  shows nothing until `actionStageResourceDispatched:` fills it in.

## 7. Our port — comparison

Our equivalent is `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGProfileViewController.m`
(4986 lines), a `UITableViewController` covering the user *and* group profile; the Settings
tab is a separate `TGSettingsViewController.m` and name editing lives in
`TGEditProfileViewController.m`. Splitting one 5400-line mode-switching controller into
three is a defensible modernisation and matches what the modern client did; it is not a
defect. What follows are the user-visible differences.

**Correct already, no action needed.** Header container 86pt, avatar `(9, 14, 70, 70)`,
name `(94, 24, w-103, 24)` bold 19 `#222932` with `#edf0f5` 0.28 shadow at `(0,1)`, status
`(94, 52, …)` regular 14 `#6d7d90` — all match, `TGProfileViewController.m:181-183, 714-796`
vs original `:704-799`. Grouped section header heights 12 / 10 / 28 / 2, footer
`1 + retinaPixel`, phones footer 0 — match (`ours :3025-3044` vs `:2343-2385`). Row heights
44 / 43 / 45 — match (`ours :177-184, 3046-3053`). Phone/detail row internals `(4,13,62,16)`
bold 13 `#5d708f` label and `(78,11,w-80,20)` bold 15 with `#347fd4` phone / `#aaaaaa`
disabled — an exact match of `TGPhoneItemCell.m:122-145, 274-289` (`ours :3441-3479`).
Action-button pair and the red button reproduce `TGButtonsMenuItemView.m:114-152` and
`TGButtonMenuItemCell.m:29-81` including the 10pt gutter, `#4a6587`, white 0.45 shadow,
`#a10603` 0.5 shadow, and the 9pt inset (`ours :250-333`).

**Defects.**

1. **No avatar overlay artwork, and the wrong geometry.** Ours clips a
   `UIImageView` with `layer.cornerRadius = 10` at a full 70×70
   (`TGProfileViewController.m:717-721`). The original composites a 69×69 image at x-offset
   0.5 inside a 70×70 canvas with `ProfileAvatarOverlay.png` painted on top
   (`TGTelegraph.mm:501-504`, `TGInterfaceAssets.mm:442-448`). `ProfileAvatarOverlay.png` is
   not present in `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/images` at all. The visible
   consequence is a flat, pasted-on avatar with no inset edge — one of the most
   recognisable pieces of the 2013 look. Fix: add the overlay asset and render the avatar
   through a composite (69×69 at +0.5x, radius 10, overlay scaled over it) rather than a
   layer corner radius.
2. **Wrong placeholder family.** With no photo we draw a lettered/initials avatar
   (`ours :727-730`, `TGIcons avatarWithInitials:size:colourId:`). The original had no
   initials avatars anywhere in 2013: it used one of eight coloured silhouettes
   `ProfileAvatar1…8.png`, `ProfileAvatarSystem.png` for uid 333000, and
   `ProfilePhotoPlaceholderGeneric.png` for uid ≤ 0 (`TGInterfaceAssets.mm:450-461`).
   Those PNGs exist in the original's `Resources/Placeholders/` and are absent from our
   `images/`. Initials avatars are a 2015-era idea.
3. **The name never moves to y = 35.** `ours :754-755` hardcodes y = 24. The original
   raises the name to 35 whenever there is no status line (`:777`, the phonebook-contact
   case). Any profile we render with an empty status label will sit visibly high against
   the 70pt avatar.
4. **"Shared Media" shows `0` instead of the no-media string.** `ours :3236-3237` always
   formats the number; the original prints `TGLocalized(@"ConversationProfile.NoMedia")`
   when the count is ≤ 0 (`TGContactMediaItemCell.m:70-77`).
5. **Shared-media title is vertically pinned differently.** Ours places the title at
   `(11, 12, …)` (`:3214-3215`); the original uses
   `(11, contentHeight - 32, …)` with `FlexibleTopMargin` (`TGContactMediaItemCell.m:30-31`).
   At the 44pt height both land at 12, so this is currently invisible — but it will
   diverge the moment the row height changes (the original grew this cell to 206pt when
   the inline media strip was enabled). Low priority; worth a comment-free constant change
   only if that row is ever resized.
6. **The red delete button is not bottom-pinned.** The original's
   `TGButtonMenuItemCell updateFrame` (`TGButtonMenuItemCell.m:157-180`, called from
   `willDisplayCell:` `:2664-2673` and `controllerInsetUpdated:` `:2114-2120`) pushes the
   red and green buttons down to the bottom of the visible scroll area when the content is
   shorter than the screen, so "Delete Contact" hugs the bottom edge on short profiles.
   Ours lays it out at its natural row position (`ours :328-333`). Visible on any
   short profile.
7. **Notifications switch sits in the wrong section.** Ours puts a notifications row as
   row 0 of the media section (`ours :3009, 3067-3070`). In the original the notifications
   switch, the "New Photos" switch and the sound variant form their own section that is
   only present while editing (`:1948-1983`). This is arguably a deliberate modern-
   interaction choice (the modern client does surface notifications directly), but it is a
   difference a user sees, and if we keep it, the section should at least be its own
   group rather than sharing rounding with Shared Media.
8. **No 0.3s data wait before appearing.** The original blocks `viewWillAppear:` on an
   `NSCondition` for up to 300ms (`:2152-2159`) so a pushed profile does not animate in
   empty. We push immediately. Cheap to add and it changes the perceived quality of the
   push noticeably on a 4S.
9. **Cell backgrounds do not cross-fade.** The original gives phone cells a
   `TGTransitionableImageView` background so insert/delete animates the corner artwork over
   0.3s (`:266-272`, `:2573`). Ours uses `[theme styleCell:]`. Only matters once we have an
   editing mode for phone numbers; note it as a dependency of that work.

**Ambiguous / not worth chasing.** The original's action-button comment strings at
`:1097` are hardcoded English and the wording ("To exchange phone numbers you can send a
contact request") never shipped through localisation; do not treat those exact strings as
canonical. The header container's own background is `nil` in both the original (`:707`) and
ours (`:715`), so the `SettingsBackground.png` pattern shows through in both — correct.

## 8. What became of it

**twelve** (`/Users/alexanderhavrysh/Git/iOS/twelve`) shows the immediate next step: the
class was split into `TGUserInfoController` (`Telegraph/TGUserInfoController.h`, 122 lines
of implementation) with subclasses `TGTelegraphUserInfoController`,
`TGPhonebookUserInfoController`, `TGSecretChatUserInfoController`, `TGBotUserInfoController`
and `TGVCardUserInfoController`. The seven-way mode enum became six classes. The header
became a *collection view item*, `TGUserInfoCollectionItemView.m`: avatar
`(15, 16, 66, 66)` circular via `TGLetteredAvatarView`, name at x = 92, plus a 44×44 call
button at `frame.width - 57, 25` (`TGUserInfoCollectionItemView.m:82, 599-601`) and extra
phone/username lines at y = 53 and y = 62 (`:649, :661`). Every one of those changes is
forced: iOS 7 killed the bevelled square avatar and the linen background, and calls and
usernames were new features that needed room in the header. The editing name fields moved
into the same item (`:668-676`) rather than a separate overlay container — the same idea as
the original's `_editNameContainer`, just folded in.

**Modern client** (`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS`,
`submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/`) abandoned the layout entirely:
one `PeerInfoScreen` for users, groups and channels, with a *centred* avatar of 100pt
(200pt when presented modally) at `y = statusBarHeight + 22`, circular
(`avatarCornerRadius = avatarSize / 2`, except forums at `0.25 * size`), a header that
expands to full-bleed when the avatar is tapped, and a paged panel container for media
instead of a single "Shared Media" row (`PeerInfoHeaderNode.swift:534, 644, 1808`). The
left-aligned 70pt avatar with name and status stacked to its right — which is exactly the
row shape of a chat-list cell — was abandoned once the profile stopped being "a contact
card" and became "a peer screen with tabs". For us that direction is irrelevant: we are
rebuilding the 2013 header, and the useful lesson from the modern client is only that
notifications and shared media deserve to be reachable without entering an edit mode,
which is the one place our port's section layout deliberately departs from the original.

# TGContactsController — original study

Sources, all read-only:

- Original: `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGContactsController.h` (71 lines)
  and `.../TGContactsController.mm` (3226 lines). Telegram for iOS v1.1, © Peter Iakovlev 2013.
  There is no copy of this class under `TelegraphKit/`; the whole controller lives in the app target.
- Later ObjC lineage: `twelve/Telegraph/TGContactsController.mm` (3951 lines).
- Modern: `Telegram-iOS/submodules/ContactListUI/Sources/*`.
- Ours: `iTgLegacy/src/TGContactsViewController.m` (3273 lines).

Cell geometry lives in `TGContactCell.m`, which is a separate component; the numbers quoted below
are only the ones the controller depends on.

---

## 1. What it is

One class serves **every** list-of-people screen in the 2013 app. It is not "the Contacts tab"; it
is a contacts *engine* configured by a bitmask, and the Contacts tab is one configuration of it. The
mask is `TGContactsMode` (`TGContactsController.h:17-30`):

| flag | value | meaning |
|---|---|---|
| `Registered` | 1 | include Telegram users from the server contact list |
| `Phonebook` | 2 | include address-book people who are *not* on Telegram |
| `SearchDisabled` | 4 | no search bar, and no `UITableViewIndexSearch` entry in the index |
| `MainContacts` | 8 | this is the tab: adds the two service rows, hides the Cancel button, shows the `+` button |
| `Invite` | 16\|2 | invite-by-SMS list (implies Phonebook) |
| `SelectModal` | 32 | modal picker |
| `HideSelf` | 64 | (declared; the self-skip is unconditional, see §5) |
| `ClearSelectionImmediately` | 128 | deselect the row right after tap |
| `Compose` | 256\|1\|4 | token-field multi-select (implies Registered + SearchDisabled) |
| `ModalInvite` | 512\|16\|2 | invite presented modally, with an Invite done-button |
| `ModalInviteWithBack` | 1024\|512\|16\|2 | same but pushed, so a Back button instead of Cancel |
| `CreateGroupOption` | 2048 | show the two service rows without being the tab |

The composite values matter: `Compose` already contains `Registered|SearchDisabled`, so
`(mode & Compose) == Compose` is the only correct way to test it — a plain `&` is true for any
registered list. The original always writes the `(x & F) == F` form for composite flags, and the
plain form for atomic ones (e.g. `TGContactsController.mm:320-323` vs `:325-329`).

Call sites (`grep TGContactsController` in `Telegraph/Telegraph`):

- `TGAppDelegate.mm:288` — the tab: `MainContacts | Registered | Phonebook | HideSelf`.
- `TGContactsController.mm:2354` and `TGLoginInactiveUserController.m:477` — `Invite | ModalInvite | ModalInviteWithBack`.
- `TGContactsController.mm:2363` — `Invite | ModalInvite` presented modally.
- Subclasses: `TGSelectContactController` (`TGSelectContactController.h:13`),
  `TGForwardContactsController` (`TGForwardTargetController.m:15`),
  `TGSelectSingleContactController` (`TGTelegraphConversationProfileController.mm:98`),
  `TGSelectExistingContactController` (`TGProfileController.m:115`).
  They exist purely to override the five hook methods in the header:
  `contactSelected:`, `contactDeselected:`, `actionItemSelected`, `encryptionItemSelected`,
  `singleUserSelected:` (`TGContactsController.h:61-65`). Subclassing, not delegation, is the
  extension mechanism, and `singleUserSelected:` is the one that decides "open a chat" vs "return a
  value to my owner".

## 2. Data model

Sections are a C++ `std::vector<shared_ptr<TGContactListSection>>` (`.mm:141-201`, member at `:238`),
each holding an `NSString *letter`, a `unichar sortLetter` and a `std::vector<TGUser *>`.
`letter == nil` is a real state and means "this section renders no header at all"
(`heightForHeaderInSection` returns 0 for it, `.mm:1333-1344`).

Section ordering is not plain alphabetical (`TGContactListSectionComparator`, `.mm:215-230`):
digits sort **after** letters, and `#` sorts after everything. Both are explicit special cases, and
`setSortLetter` maps `' '` to `@"#"` (`.mm:177-190`).

Within a section the sort is by last-then-first or first-then-last
(`TGContactListItemSortByLastNameFunction` `.mm:87-112`, `...ByFirstName...` `:114-139`). Both fall
back to the *other* name when their primary is empty, and both use `caseInsensitiveCompare:`. Note
the deliberate quirk: when the primary keys are equal and either secondary name is empty the
comparator returns `false` (`.mm:101-107`), i.e. treats them as not-less — stable enough for
`std::sort` in practice but not a strict weak ordering in the pedantic sense.

Which of the two is used comes from the **system address book**, not from a Telegram setting:
`[[TGSynchronizeContactsManager instance] sortOrder]` (`.mm:2778`) is built from
`ABPersonGetSortOrdering()` and `ABPersonGetCompositeNameFormat()`
(`TGSynchronizeContactsActor.mm:425-434`), re-read on every foreground (`:441-459`). Four bits:
`SortOrderFirst=1`, `Last=2`, `DisplayFirstFirst=4`, `DisplayLastFirst=8`
(`TGSynchronizeContactsActor.h:16-19`). Sorting and display order are therefore independent, which
is why the cell has a `boldMode`: the *sort key* is bolded, wherever it sits in the display order
(`.mm:1429-1464` — `DisplayFirstFirst` + `SortOrderFirst` → `boldMode 1` (first part bold), else
`boldMode 2`). The bits are read as a mask when drawing: bit 1 bolds the first drawn part, bit 2 the
second (`TGContactCellContents.m:67-68`). With the US defaults — sort by last name, display
first-name-first — that gives `boldMode 2`, i.e. "John **Smith**".

Two sentinel users act as the service rows: `uid == INT_MAX` → the invite row,
`uid == INT_MAX - 1` → the create-group row (`.mm:3103-3119`, dispatch at `:1550-1578`, tap at
`:1647-1660`). Phonebook-only people get `uid = -ABS(nativeId)` or `-ABS(phoneId)`
(`.mm:3020`, `:2932`) — a negative uid is the type tag for "not a Telegram user", and it is checked
everywhere (`heightForRow` `:1357`, `hideAvatar` `:1424`, subtitle choice `:1480`, tap `:1665-1668`).

## 3. The surprising part: the tab has almost no letter headers

In `updateContactList` (`.mm:2872-2900`) the loop that files a registered user into a section reads:

```
if (!(_contactsMode & TGContactsModePhonebook)) { if (sortLetter matches) add; }
else { add to the first section, unconditionally; break; }
```

The tab's mode contains `Phonebook`, so **every registered Telegram contact lands in one single
section**, whose letter is then set to `nil` (`.mm:3094-3098`, which also nils it whenever there is
exactly one section). Letter-headed sections in the tab therefore only ever come from the
*phonebook* branch (`.mm:2997-3074`), which is appended after the Telegram block (`.mm:3121`).

So the 2013 Contacts tab is: two service rows (no header) → all Telegram contacts, alphabetical,
**no A/B/C headers** → then A, B, C… sections of address-book people who are not on Telegram.
This is unusual enough that I want to flag it as read-from-code rather than read-from-screenshot:
none of the five images in `iTgLegacy/design-reference/` shows the Contacts tab, so I could not
confirm it visually. The code path is unambiguous, though, and `TGContactsModeCombineSections`
appearing later in `twelve/Telegraph/TGContactsController.h:23` suggests this collapsing behaviour
was eventually made an explicit, opt-in flag rather than a side effect of `Phonebook`.

The section index (right-hand A–Z strip) is likewise **not** shown in the tab: `newIndices` is only
generated for `Compose` or `CreateGroupOption` (`.mm:3126`), and even then only kept if it has more
than 10 entries (`.mm:3148-3151`). Its first element is `UITableViewIndexSearch` unless
`SearchDisabled` (`.mm:2515-2516`), which is why `sectionForSectionIndexTitle:` returns `-1` for
index 0 after scrolling to `-contentInset.top`, and subtracts 1 from the found index otherwise
(`.mm:1388-1408`).

## 4. Metrics and colours (all from the original)

Row heights (`.mm:1346-1360`):

- 44 — service rows, i.e. section 0 in `MainContacts` or `CreateGroupOption`.
- 51 — every row in `Invite` mode, and any user with `uid > 0`.
- 44 — a user with `uid <= 0` (phonebook person) outside Invite mode. Shorter because the avatar is
  hidden (`.mm:1424`) and there is nothing to make it 51 tall for.
- 51 — the search results table, both the mixin's (`.mm:1759`) and the compose one (`.mm:600`).

51 is sized around the avatar: `CGRectMake(5, 5, 40, 40)` (`TGContactCell.m:326`, `:668`) → 5 + 40 + 5
plus a hairline. Text starts at `avatarWidth + 9 = 45 + 9 = 54` (`TGContactCell.m:661`, `:690`),
title `systemFontOfSize:19` / bold 19 (`TGContactCell.m:332-333`), subtitle
`systemFontOfSize:13 + retinaPixel` (`TGContactCell.m:341`). Subtitle colours: `UIColorRGBA(0, 0.53f)`
normal, `UIColorRGB(0x0779d0)` when online (`TGContactCell.m:543-544`).

Section header (`generateSectionHeader:first:`, `.mm:1279-1331`; height 25 at `.mm:1339`):

- Background image `CategoryDividerFirst.png` when it is the first section *and* search is enabled,
  otherwise `CategoryDivider.png` (`.mm:1303`, `:71-77`). The image view is inset `y = -1` and
  `height = 11` with flexible autoresizing, so a 10pt-tall art file stretches over the 25pt header
  and bleeds one point upward under the previous cell (`.mm:1301-1302`).
- Label: `boldSystemFontOfSize:15`, white, shadow `UIColorRGB(0x88929c)` at offset `(0, -1)`,
  `sizeToFit` then offset `(10, 1)` (`.mm:1306-1317`).
- Headers are pooled by hand in two reuse arrays, "first" and "not first" (`.mm:1283-1292`,
  allocated `:312`); a view is considered free when `superview == nil`. UIKit had no header reuse in
  iOS 6, so this pool is the reason scrolling a long list did not allocate.

Overscroll: a 500pt-tall view at `y = -500` coloured `UIColorRGB(0xe4e9f0)` is added as a *subview of
the table* (not the background view) so that rubber-banding above the search bar shows the search
bar's own grey rather than white (`.mm:505-510`). It is only added when there is a search bar.

Search bar: `TGSearchBar` 44pt tall with `SearchBarBackground.png`, placeholder
`DialogList.SearchLabel`, return key forced to Done on whatever subview conforms to
`UITextInputTraits` (`.mm:516-535`). Then two hacks run over its subtree: `clearInputFieldBackground:`
replaces the field background with a stretched `SearchInputField.png`, sets the placeholder colour to
`UIColorRGB(0x8d9298)`, swaps the clear button for `ClearInput.png` / `ClearInput_Pressed.png`, and on
retina nudges the clear button by 0.5pt (`.mm:844-883`); `hideStripe:` hides any `UIImageView` exactly
1pt tall (`.mm:885-891`). The clear-button selector is assembled at runtime from `"clear"` + `"tton"`
to keep the private name out of the binary (`.mm:856`).

Modal-invite header (`.mm:545-569`): a 44pt container coloured `UIColorRGB(0xdfe4eb)` holding the
search background image, the search bar with `searchContentInset = (0, 39, 0, 0)`, and a 28×29
select-all button at `(7, 8)`. When the navigation bar hides during search the button slides out to
`x = -width - 7` and the inset drops to 5 (`.mm:637-657`). The button's three states use
`SelAll_None`, `SelAll_Mid`, `SelAll_All` (+`_Highlighted`) chosen by
`selected == 0 / partial / == contactsCount` (`.mm:1216-1240`).

Phonebook-denied overlay (`.mm:662-759`) — the most metric-dense piece in the file:

- Full-bleed view, background `[[TGInterfaceAssets instance] linesBackground]`.
- A **4pt-tall, 40pt-wide anchor container** centred in the view, tag 100, `clipsToBounds = NO`
  (`.mm:670-674`). Everything else is positioned relative to that anchor with negative offsets, which
  is why the numbers below look strange.
- `additionalOffset` = portrait ? (widescreen ? −20 : −15) : +12 (`.mm:724`).
- Icon `ContactsIcon.png`, centred, `y = (portrait ? −113 : −100) + additionalOffset` (`.mm:726`).
- Title: `boldSystemFontOfSize:17`, `UIColorRGB(0x697487)`, white 30% shadow at `(0, 1)`,
  `numberOfLines = 0`, wrapped at 265pt, `y = −10 + additionalOffset`
  (`.mm:680-690`, `:728-729`).
- Subtitle: font `TGIsRetina() ? 14.5f : 15.0f` — a genuine half-point difference between retina and
  non-retina (`.mm:695`, `:744`). Text is `Contacts.AccessDeniedHelpPortrait` /
  `...Landscape` formatted with the device word ("iPhone"/"iPod"/"iPad", derived from
  `[[UIDevice currentDevice] model]`, `.mm:731-736`), and the word `Contacts.AccessDeniedHelpON`
  inside it is re-attributed bold (`.mm:740-751`). Pre-iOS-6 devices with no `setAttributedText:`
  get the plain string (`.mm:753-754`). Wrapped at 210pt portrait / 480pt landscape,
  `y = 41 + additionalOffset` (`.mm:756-757`).
- While the overlay is up, the `+` button is hidden (`.mm:706-707`, and again at creation time
  `:370-371`). The table is *not* disabled — the overlay simply covers it.

Nav bar buttons are `TGToolbarButton`s, never system items: `+` uses `AddIcon.png` /
`AddIcon_Landscape.png`, `minWidth 35` (`.mm:361-366`); the Invite done-button is
`TGToolbarButtonTypeDone`, `minWidth 60`, padding 10/10 (`.mm:382-387`); Cancel is generic,
`minWidth 60` (`.mm:420-423`).

## 5. Behaviour

**Loading.** Nothing loads in `init`; `viewWillAppear:` does it once, guarded by `_onceLoaded`
(`.mm:909-954`). It first tries the synchronous caches (`synchronousContactList`, `cachedPhonebook`);
only if those miss does it fire the ActionStage actors `/tg/contactlist/(contacts)` and
`/tg/contactlist/(phonebook)`. Both results carry a monotonic `version`, and an update whose version
is `<= ` the current one is dropped outright (`.mm:2705-2706`, `:2729-2730`) — that is the whole
de-duplication strategy. Rebuilds are coalesced by `_updateContactListSheduled` and always run off
the main thread on the global stage queue (`.mm:2711-2720`), with only the final swap and
`reloadData` marshalled back (`.mm:3128-3201`).

**Live updates.** It watches `/tg/contactlist`, `/tg/phonebook`, `/tg/userdatachanges`,
`/tg/userpresencechanges`, `/tg/phonebookAccessStatus` and `/as/updateRelativeTimestamps`
(`.mm:314-323`). Presence and profile changes do **not** reload the table: the changed users are
swapped into `_currentContactList` and into the `_sectionList` vectors in place, and only the
*visible* cells for those uids are re-applied via `adjustCellForUser(..., animated: true, ...)`
(`.mm:2634-2661`). The relative-timestamp tick is even cheaper: it recomputes each visible cell's
subtitle and only calls `resetView:true` when the string or the active flag actually changed
(`.mm:1507-1526`). Row reordering never happens on presence change — a contact that comes online
stays where it is.

**Subtitle text** (`subtitleStringForUser`, `.mm:1475-1505`): online → `Presence.online` and
`subtitleActive = true` (blue); `lastSeen == 0` → `Presence.offline`; `lastSeen < 0` →
`Presence.invisible`; otherwise `"Presence.lastSeen " + [TGDateUtils stringForRelativeLastSeen:]`.
For a phonebook user (`uid <= 0`) the subtitle is `customProperties[@"label"]`, which is set to the
phone label, or to `"label  number"` (two spaces) when the contact has more than one number
(`.mm:2937`, `:1848`). A registered contact whose address-book entry has multiple numbers also gets a
label attached, so the tab can disambiguate "mobile" from "work" (`.mm:2789-2800`, `:2816-2824`).

**Empty / missing content.** There is no empty-state view: a contact list with nothing in it is
simply an empty table over the white background (`.mm:501`). The absent-value rules are all in the
sorters and in `adjustCellForUser`: empty last name → the first name is used as the sort key and as
the *only* title part, with `titleTextSecond = nil` so the cell bolds the single part
(`TGContactCell.m:489-493`). There is a real bug in that path at `.mm:1449-1453`: in the
display-last-first branch with an empty last name, it assigns `titleTextSecond` twice and never sets
`titleTextFirst`, so the previous cell's first-name text survives the reuse. Reproducible on a device
whose address book is set to display "Last, First" with a contact that has no last name. Do not
reproduce this.

**Tap.** `didSelectRowAtIndexPath:` returns immediately in Compose+multi-select — selection there
happens through the cell's own check button, not the row (`.mm:1626-1627`). Otherwise: the two
sentinels dispatch to `actionItemSelected` / `encryptionItemSelected`, and note the extra
`indexPath.row == 0` / `== 1` guards (`.mm:1649`, `:1656`). A disabled user is inert
(`_disabledUserIds`, `.mm:1663`). A real user opens a conversation with `clearStack:true`, and the
keyboard is opened immediately when the mode is `CreateGroupOption` (`.mm:1698`). A phonebook user
opens `TGProfileController` for the address-book record (`.mm:1702-1707`).

**Deselect on return.** `viewWillAppear:` deselects the selected row with a delay that depends on the
CPU: 0 on >2 cores, 0.05s on 2, 0.1s on 1 (`.mm:956-980`, and again for the search table `:982-1011`).
On the 4S (single core) that is the 0.1s branch — the deselect fade starts a tenth of a second after
the push-back animation begins, so the highlight is still visible as the screen slides in. This is
deliberate pacing, not a bug.

**Selection.** `_selectedUsers` is a `std::map<int, TGUser *>` (`.mm:240`).
`setUsersSelected:selected:callback:` is the single mutation point (`.mm:1997-2100`): it diffs, updates
only the *visible* cells via `updateFlags:` rather than reloading, then fires the
`contactSelected:` / `contactDeselected:` hooks, then rebuilds the token field in Compose mode.
`usersSelectedLimit` is enforced at the toggle site by *reverting* the cell's own optimistic flag
(`.mm:2534-2539`). `selectedContactsList` prefers the live `TGUser` from `_sectionList` and only falls
back to the stored pointer (`.mm:2173-2205`), so a user whose data changed while selected is returned
fresh. In Invite mode `_selectAllOnce` selects everything the first time the list is built
(`.mm:325-326`, `:3157-3161`) — you open the invite screen with all your non-Telegram contacts already
ticked.

**Invite button behaviour** (`.mm:2207-2289`): the title becomes `Contacts.InviteTitle` formatted with
the count; on `sizeToFit` during an appear animation the frame is nudged by the width delta so the
button's right edge stays put (`.mm:2214-2217`). Count 0 fades it out over 0.3s and then hides it;
non-zero fades it back in. Sending goes through `MFMessageComposeViewController` with a
Russian/Ukrainian body variant chosen from `[NSLocale preferredLanguages]` (`.mm:2424-2437`), and on
success reports the invites to `/tg/auth/sendinvites/(n)` (`.mm:2467`).

**Search.** Two entirely different mechanisms. Normal modes use `TGSearchDisplayMixin`, and activating
it hides the navigation bar and fades out the private index view (looked up by KVC on the obfuscated
key `TGEncodeText(@"`joefy", -1)` → `"index"`, `.mm:1774`, `:1788`). Compose mode instead uses a
second full table (`_searchTableView`) plus a `TGTokenFieldView` above it (`.mm:591-611`). Queries are
trimmed and whitespace-collapsed by regex before use (`.mm:1811`, `:1870`); an empty query hides the
results table rather than showing everything. Invite mode searches the phonebook locally and filters
out numbers already known as Telegram contacts (`.mm:1822-1852`); other modes fire an actor at
`/tg/contacts/search/(hash)` and the reply is only accepted if its path still matches
`_currentSearchPath` (`.mm:1887`, `:2747-2749`) — the original's answer to out-of-order responses.

**Deletion.** `deleteUserFromList:` removes the row, and removes the whole section if it became empty,
inside one `beginUpdates`/`endUpdates` with `UITableViewRowAnimationFade` (`.mm:1715-1745`).

**Scrolling.** `scrollViewWillBeginDragging:` walks the view tree and resigns the first responder
(`.mm:3204-3223`), so dragging the list dismisses the keyboard.

## 6. Our port, judged

Ours is `iTgLegacy/src/TGContactsViewController.m`, a `UITableViewController` with a
`isPickerMode` boolean instead of the mask, plus three private controllers in the same file
(`TGInviteFriendsViewController:426`, `TGNewGroupMembersViewController:571`,
`TGSecretChatViewController:719`). Given that we have no address book merged into the list, one
boolean is a reasonable simplification and I would not restructure it.

What is already right, briefly: avatar `(5, 5, 40, 40)` and text left 54
(`TGContactsViewController.m:19-22` vs `TGContactCell.m:326`, `:661`); row 51 / action row 44 and
header 25 (`:18`, `:25`, `:22` vs `.mm:1339`, `:1351`, `:1357`); header label bold 15, white,
shadow `0x88929c` at `(0, -1)`, offset `(10, 1)` (`:3028-3072` vs `.mm:1306-1317`); overscroll view
`0xe4e9f0` at `y = -500`, height 500 (`:2590-2597` vs `.mm:505-510`); title 19 / subtitle
`13 + retinaPixel`, subtitle `rgba(0, .53)` → `0x0779d0` online (`:242-260` vs
`TGContactCell.m:332-347`, `:543-544`); the whole denied-access overlay, including the 4pt anchor
container, the −113/−10/41 offsets and the 14.5/15 retina font split (`:2333-2444` vs `.mm:670-757`);
the single-name bold rule (`:3118-3134` vs `TGContactCell.m:489-493`). Good work.

Differences a user can see:

1. **We letter every section; the original did not, in the tab.** Ours builds one section per initial
   and blanks only the first title (`TGContactsViewController.m:2230-2264`); the original collapses
   all registered contacts into one header-less section whenever `Phonebook` is in the mode, which the
   tab always is (`.mm:2872-2900`, `:3094-3098`). Fix: in non-picker mode put every contact into a
   single sectionless group after the action rows. Because §3 could not be confirmed against a
   screenshot, treat this as the one item to sanity-check on device before changing.

2. **Section index strip.** Ours shows it in picker mode (`:3055-3064`), the original showed it in
   Compose and CreateGroup — the same intent, and both gate on `> 10` entries. But ours scrolls to
   `CGPointZero` on the magnifier row (`:3068`) whereas the original scrolls to
   `-contentInset.top` (`.mm:1394`). With a translucent-free iOS 6 bar these coincide, so this is
   only worth fixing if we ever add a content inset. Also, ours returns 0 for an unmatched title
   whereas the original returns −1 — ours will jump to the top instead of doing nothing.

3. **Name order and bolding are hard-coded.** We always sort by last name and always draw
   "first (regular) + last (bold)" (`:1113-1134`, `:3118-3134`). The original reads
   `ABPersonGetSortOrdering()` / `ABPersonGetCompositeNameFormat()` and re-reads them on foreground
   (`TGSynchronizeContactsActor.mm:425-434`, `:441-459`), so a user whose iPhone is set to
   "Last, First" saw a genuinely different list. Our behaviour equals the US default. Fix, if we want
   fidelity: read the two AB functions once in `viewDidLoad`, pick the sort comparator and swap which
   label is bold.

4. **The first-section divider art is dead code in both, but for different reasons.** Ours picks
   `CategoryDividerFirst` when `section == 0` (`:3037-3038`); in ours section 0 is the action section,
   whose title is `NSNull`, so no header is ever drawn there and the "first" art never appears. In the
   original, `first` also required search to be enabled and section 0's letter to be non-nil. Net
   effect matches; no change needed, but do not "fix" ours by removing the branch — it becomes live
   again in picker mode with no action rows.

5. **No phonebook rows at all.** The original's tab listed non-Telegram address-book people inline,
   with a 44pt row, no avatar, and the phone label as subtitle (`.mm:2997-3074`, `:1357`, `:1424`),
   tapping into `TGProfileController`. We replaced that with a "Sync Contacts" action row and an
   import flow (`:2220-2228`, `:1400-1458`). That is a defensible modern-interaction choice, but the
   consequence is that our list never shows a 44pt avatar-less contact row, so if a reader is
   matching screenshots they should not expect one.

6. **Extra rows and badges that never existed.** We add "My Invite Link" (`:2226-2227`), a star for
   close friends, premium/verified/scam badges and a "Birthday today" subtitle prefix
   (`:3145-3169`). These are modern-Telegram concepts. They are consistent with the project's brief
   (modern interaction, 2013 skin), but the badge column shortens the title's available width
   (`:311-320`) in a way the original never did; with a long "First Last" plus two badges on a 320pt
   screen the last name gets clipped where the original would have shown it. Worth a look with a real
   contact list.

7. **Selection/deselect timing.** The original's CPU-dependent deselect delay (0.1s on a single-core
   4S, `.mm:971-979`) is a visible pacing detail on our exact target device. Ours deselects
   immediately with `animated:YES` inside `didSelectRowAtIndexPath:` (`:3209`), which is a different
   moment entirely — the original deselects on *return*, we deselect on *tap*, so during the push
   animation our row is already unhighlighted where the original's stayed blue. Cheap to match: drop
   the deselect from the tap handler and do it in `viewWillAppear:` after 0.1s.

8. **Search results row height.** The original's search tables are pinned to 51 regardless of mode
   (`.mm:1759`, `:600`). Ours reuses the main table, whose `heightForRowAtIndexPath:` returns 51 for
   contacts and 44 for action rows, and `actionRowIdentifiers` returns nil while filtering
   (`:2220-2222`), so we land on 51 too. Correct.

9. **Pull-to-refresh** (`:2551-2557`) has no counterpart in 2013 — `UIRefreshControl` is iOS 6 and the
   original never used one here. It is guarded by a class check, so it is harmless, but it is an
   anachronism in a screenshot.

## 7. What became of it

**twelve** (`twelve/Telegraph/TGContactsController.mm`, `.h`): the same class, same architecture,
same C++ section vectors, thirteen more mode bits (`.h:9-32`). The additions are all "new feature
needed a new list": `Calls`, `Share`, `SearchGlobal`, `IgnoreBots`, `SortByLastSeen`,
`SortByImporters`, `CreateGroupLink`. Two are directly relevant to us: `CombineSections` (4096) turns
the §3 collapsing into an explicit flag instead of a side effect of `Phonebook`, and
`ManualFirstSection` (8192) plus the new hooks `itemHeightForFirstSection` /
`numberOfRowsInFirstSection` / `cellForRowInFirstSection:` (`.h:87-90`) replace the two `INT_MAX`
sentinel users with a real subclass-supplied section. Both changes are the same lesson: the 2013
version encoded structure in magic values (a uid of `INT_MAX`, a mode bit meaning two things), and
the fork had to make them explicit once there were more than two service rows. The visual change is
the row height: 48 (55 on iPad) instead of 51 (`twelve/.../TGContactsController.mm:1430-1436`),
which is the iOS 7 flat redesign, not a change of intent. Also note `TGContactsModeHideSelf` became
`TGContactsModeShowSelf` (`.h:16`) — the default flipped.

**Modern** (`Telegram-iOS/submodules/ContactListUI/`): the controller is now a thin shell over
`ContactListNode`, a diffed list of enum entries. Three things changed in kind, not degree:

- Name sort/display order moved out of the system address book and into Telegram's own
  `PresentationData.nameSortOrder` / `nameDisplayOrder`, threaded into every row
  (`ContactListNode.swift:248`, `:1765-1766`). Forced by cross-platform settings sync — an
  iOS-address-book-derived setting cannot follow an account to Android or desktop.
- The permission state became **list content**, not an overlay: `.permissionInfo`,
  `.permissionEnable`, `.permissionLimited` are entries in the same list as the contacts
  (`ContactListNode.swift:98-100`, `:138-147`), rendered by `LimitedPermissionItem`. Forced by iOS 14
  limited-contacts access, where "denied" is no longer binary and the list can be partially
  populated — a full-screen overlay has nothing sensible to say about that state.
- Invite split off into its own controller (`InviteContactsController.swift`) with its own count
  panel, rather than being the same class in a different mode. The mode bitmask did not survive; the
  five subclass hooks became closures and separate node types.

The alphabetical section headers themselves did survive (`ContactListNameIndexHeader.swift`), which is
worth noting: of everything in this file, the letter header is the piece nobody has felt the need to
change in thirteen years.

## 8. Open questions

- §3's header-less tab is derived from code with no screenshot to confirm it. If a period screenshot
  of the Contacts tab turns up, check it before we change `rebuildSections`.
- `TGContactsModeHideSelf` (64) is declared and passed by `TGAppDelegate.mm:288`, but I could not find
  it tested anywhere in `TGContactsController.mm`; the self-skip at `.mm:2833-2834` is unconditional.
  Either it is vestigial or it is read by a subclass I did not find.
- `TGContactsModeCreateGroupOption` inserts *both* service rows despite the commented-out `if`
  at `.mm:3112`, so the create-group list also shows the invite row. That reads like the comment was
  disabled during a late change; I would not treat the exact row set of that screen as settled.

# TGDialogListSearchCell (original, Telegram for iOS v1.1 / build 21024)

Source of truth for everything below:

- `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGDialogListSearchCell.h` (35 lines)
- `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGDialogListSearchCell.m` (275 lines)
- its only call site, `TelegraphKit/TelegraphKit/TGDialogListController.mm`
- asset provider `Telegraph/Telegraph/TGInterfaceAssets.mm`

The class exists under exactly that name. (There is also a `TGDialogListMessageSearchCell`
in the same folder, but it is a dead stub: an empty `@interface` and a template
`initWithStyle:` with a `// Initialization code` comment — `TGDialogListMessageSearchCell.m:5-12`
— and nothing in the tree references it. Ignore it.)

## 1. What it is for

One row in the *search results* table of the dialog list, and only when the search
scope segment is "chats/contacts" (index 0). It shows a **peer**: either an existing
conversation or a contact that has no conversation yet. It is deliberately *not* the
full `TGDialogListCell` — no date, no message preview, no unread badge, no swipe-to-delete
— because a search hit is an identity, not a conversation state.

Message hits inside search do not use this class at all: when the scope index is not 0,
the controller falls back to the real `TGDialogListCell`
(`TGDialogListController.mm:1418-1442`, the `else if (conversation != nil)` branch),
which is why the row height switches from 51 to 73 in that case.

## 2. Public surface

`TGDialogListSearchCell.h:13-33`

| member | role |
| --- | --- |
| `assetsSource` (`id<TGDialogListCellAssetsSource>`) | every image and placeholder comes from here; never from `imageNamed:` inside the cell except the two background plates |
| `conversationId` (`int64_t`) | used only to pick the *colour* of the placeholder avatar |
| `titleTextFirst`, `titleTextSecond` (`NSString *`) | the two halves of the name (first / last) |
| `subtitleText` (`NSString *`) | supported by the cell, **never set by the app** (see §7) |
| `avatarUrl` (`NSString *`) | remote avatar; nil means "use a coloured placeholder" |
| `isChat`, `isEncrypted`, `encryptedUserId` | pick placeholder family and title colour |
| `- (void)resetView:(bool)animated` | apply model → views; must be called after setting properties |
| `- (void)setBoldMode:(int)index` | which of the two title halves is bold |
| `- (id)initWithStyle:reuseIdentifier:assetsSource:` | designated initialiser |

The cell holds no watcher/handle and posts no notifications — selection is handled
entirely by the controller.

## 3. Geometry

Row height is **51 pt**, decided by the controller, not the cell:
`return _searchBar.selectedScopeButtonIndex == 0 ? 51 : 73;`
(`TGDialogListController.mm:1129`, inside `heightForRowAtIndexPath:`).

Layout, all from `TGDialogListSearchCell.m:170-216`:

- avatar: `CGRectMake(5, 5, 40, 40)` — line 189 (and the same rect at construction, line 85).
  So 5 pt inset on the left, 5 pt top, 6 pt bottom in a 51 pt row: the avatar is *not*
  vertically centred, it sits 1 pt high. That asymmetry is deliberate and matches the
  102 px (= 51 pt) background plate.
- `avatarWidth = 5 + 40 = 45` (line 183) is the local name for "everything left of the text".
- text left edge: `avatarWidth + 9 + leftPadding` = **54 pt** (lines 209/214); `leftPadding` is
  a hard-coded `0` (line 181) — a leftover hook for an inset mode that never shipped.
- text right margin: the title width is `viewSize.width - avatarWidth - 9 - 5 - leftPadding`
  (line 185), i.e. width − 59, so a 5 pt right margin.
- subtitle, when present, is indented **one extra point** (`... + 1`, line 204). Not a typo
  repeated elsewhere in the file, and it is the kind of hand-nudge this codebase is full of.

Vertical placement of the text block:

- no subtitle (the normal case): `titleLabelsY = (int)((int)((h - lineHeight)/2) - 1)`
  (line 198). Double truncation to int, then a **−1 pt** lift. With the 19 pt system font
  (`lineHeight` ≈ 22.6 → 22 after the int cast of the frame height) that puts the title at
  y ≈ 13 in a 51 pt row.
- with subtitle: `titleLabelsY = (int)((h - titleH - subtitleH - 1)/2)` (line 202), subtitle
  immediately below at `titleLabelsY + titleH`.

Heights are taken from `font.lineHeight`, so the 51 pt row is sized around
**19 pt system + 13 pt system** (22 + 16 + 1 = 39, leaving 6 pt above and below): the row
height and the fonts are locked to each other. Change the title font and 51 stops being right.

Two-part titles: the second label's x is computed from the *measured* width of the first
label's text plus a **5 pt gap**:
`avatarWidth + 9 + leftPadding + 5 + (int)([_titleLabelFirst.text sizeWithFont:...].width)`
(line 210). Note the frames are `sizeWithFont:` (UIKit, pre-TextKit) and truncated to int.

## 4. Colours, fonts, artwork

All citations in `TGDialogListSearchCell.m` unless stated.

| element | value | line |
| --- | --- | --- |
| first title label font | `systemFontOfSize:19` | 63 |
| second title label font | `boldSystemFontOfSize:19` | 71 |
| title colour (normal) | `0x111111` | 138, 142-143 |
| title colour (secret chat) | `0x229a0a` (Telegram green) | 139, 142-143 |
| title highlighted colour | `0xffffff` | 65, 73 |
| subtitle font | `systemFontOfSize:13` | 79 |
| subtitle colour | `0x808080` | 80 |
| subtitle highlighted colour | `0xffffff` | 81 |
| label backgrounds | opaque `[UIColor whiteColor]` | 66, 74, 82 |
| normal cell plate | `Cell102.png` as `backgroundView` | 50, 56 |
| pressed cell plate | `CellHighlighted102.png` as `selectedBackgroundView` | 54, 57 |

Note the constructor sets the title colour to `0x000000` (lines 64, 72) and then
`resetView:` overwrites it with `0x111111`/`0x229a0a` every time (lines 142-143). The
0x000000 is dead; 0x111111 is the shipping colour.

Artwork facts:

- `Telegraph/Telegraph/Resources/Cell102@2x.png` is **2 × 102 px** — a 1 × 51 pt vertical
  gradient strip, stretched horizontally by the `UIImageView`. 102 px = 51 pt = exactly the
  row height; the file name *is* the row height.
- `Telegraph/Telegraph/Resources/CellHighlighted102@2x.png` is **2 × 104 px** = 52 pt, one
  point taller. That is why `layoutSubviews`, `setSelected:` and `setHighlighted:` all move
  the selected background to `origin.y = -1` and `height = frame.height + 1`
  (lines 174-177, 224-227, 239-242): the pressed plate has to swallow the hairline separator
  drawn *above* the row as well as the one below. The `true ? -1 : 0` idiom is a debug switch
  the author froze in the on position.
- Only `@2x` files exist for both plates, which is fine for our target (iPhone 4S is retina).

Avatars:

- with a URL: `[_avatarView loadImage:_avatarUrl filter:@"avatar40" placeholder:...]`
  (lines 158, 161). The `avatar40` processor is registered in `Telegraph/Telegraph/TGTelegraph.mm:485-488`
  as `TGScaleAndRoundCorners(source, CGSizeMake(40, 40), CGSizeZero, 4, nil, false, nil)`
  → 40×40 with a **4 pt corner radius**, i.e. a rounded square, not a circle.
- without a URL (line 166): a *colour-indexed* placeholder chosen from the id —
  `smallAvatarPlaceholder:` returns `SmallAvatar%d.png` by `colorIndexForUid`, with
  `SmallAvatarSystem.png` for uid 333000 and a generic for uid ≤ 0
  (`TGInterfaceAssets.mm:314-324`); groups get `DialogListGroupAvatarSmall%d.png`
  (`TGInterfaceAssets.mm:334-339`). Generic fallback is `DialogListAvatarPlaceholderSmall.png`
  (`TGInterfaceAssets.mm:326-332`). For a secret chat the *user* id is used, not the
  conversation id (line 166), so the colour matches the peer, not the secret-chat wrapper.
- fade: `_avatarView.fadeTransition = true` (line 86) and `fadeTransitionDuration` is
  **0.14 s when animated, 0.3 s when not** (line 152). Yes, that is inverted relative to
  what the parameter name suggests; it is what the original does.
- the load is skipped entirely when the URL already matches `_avatarView.currentUrl`
  (line 153) — the reuse guard.

**Dead artwork:** `_groupChatIcon` is created, given `dialogListGroupChatIcon` /
`...Highlighted` from the assets source and added to the content view (lines 89-92), but
`layoutSubviews` never assigns it a frame. It stays at `CGRectZero` and is invisible in the
shipped app. Do not port a group badge into this cell on its authority.

## 5. States and behaviour

- **Bold mode** (lines 97-114): index 0 → first regular, second bold; index 1 → first bold,
  second regular; anything else → both regular. Nothing in this app ever calls it on this
  class (grep over the whole tree: the only `setBoldMode:` callers are `TGContactCell` from
  `TGContactsController.mm:1443/1445/1461/1463` and `TGAddContactsController.mm:477`).
  So the shipped appearance is always the constructor default: **first name regular,
  last name bold**. That reads oddly today but it is genuinely what 1.1 rendered.
- **One-name peers** (lines 118-124): if `titleTextSecond` is empty, `titleLabelFirst` is
  cleared *and hidden*, and the whole name goes into `titleLabelSecond` — the **bold** label.
  A mononym therefore renders bold; "Peter Iakovlev" renders "Peter" regular + "Iakovlev" bold.
- **Subtitle absent** (line 146): hidden, and the title re-centres via the branch at line 198.
- **Selection / highlight** (lines 218-246): both re-apply the −1/+1 plate rect and then call
  `adjustOrdering`.
- **`adjustOrdering`** (lines 248-273): walks the table view's subviews and, if this cell is
  not the last `UITableViewCell` in z-order, re-inserts it at the top. Reason: the taller
  (52 pt) pressed plate would otherwise be clipped by the neighbouring cell drawn above it.
  This is a UITableView z-order workaround, not decoration — a pressed row must paint over
  its neighbours' edges.
- **Reuse**: there is no `prepareForReuse`. The contract is "set properties, call
  `resetView:`", and `resetView:` writes every label and the avatar unconditionally, so
  stale state cannot survive — *except* `isChat`, which the controller only ever sets to
  `true` (never back to `false`) in the conversation branch, relying on the user branch
  setting it explicitly (`TGDialogListController.mm:1382`, versus lines 1319-1322 where it
  is only ever set true). This is safe only because both branches are exhaustive.

## 6. Long / empty / missing content

- **Long name, two parts:** the first label is given the *full* available width
  (line 209) even though the second label starts right after the measured text, so the two
  frames overlap; the first label's own text stops where it stops, so no visual overlap.
  The second label also gets the full `titleSizeGeneric.width` starting at its offset
  x (line 210), so its right edge runs **past** the cell's right margin. `contentView`
  does not clip by default on iOS 6, so a long "first last" pair bleeds toward the screen
  edge and is then cut by the window/table clip, with the UILabel ellipsis appearing only
  at that far-right position. In practice long last names look like they run off the row.
- **Long name, one part:** the single (bold) label gets exactly `width − 59`, so it
  truncates with a normal tail ellipsis at the 5 pt right margin.
- **Empty title:** nothing special; both labels end up nil/empty and the row is a bare avatar.
- **Missing avatar URL:** always a deterministic coloured placeholder, never an empty square.
- **Empty subtitle:** hidden and the title recentres. Since the app never sets a subtitle,
  the single-line branch is the only one that ever runs in production.

## 7. How the controller actually drives it

`TGDialogListController.mm:1299-1412`, reuse identifier `@"UC"`.

- Guard: `if ((conversation != nil || user != nil) && _searchBar.selectedScopeButtonIndex == 0)`
  (line 1298).
- `isEncrypted` / `encryptedUserId` are reset to false/0 first (1308-1309), then filled from
  `conversation.dialogListData[@"isEncrypted"]` / `[@"encryptedUserId"]` (1327-1328).
- Conversation branch (1313-1329): title = `dialogListData[@"title"]`,
  `titleTextSecond = nil`, `subtitleText = nil`, `isChat` from `dialogListData[@"isChat"]`,
  avatar from `dialogListData[@"avatarUrl"]`.
- User branch (1331-1348): if `firstName` is empty the last name goes into `titleTextFirst`
  with `titleTextSecond = nil` (so it renders bold via the §5 rule); otherwise first/last
  split. `subtitleText = nil` again, `conversationId = user.uid`.
- Finally `[cell resetView:false]` (1350) — search rows never animate their avatar in.
- **`subtitleText` is nil at both call sites.** The two-line layout is unreachable in v1.1.
- Tap (`didSelectRowAtIndexPath:`, 1076-1098): the controller dispatches on the *model*
  type, not the cell — `searchResultSelectedConversation:` (with `atMessageId:` if the
  conversation carries `additionalProperties[@"searchMessageId"]`),
  `searchResultSelectedUser:`, or `searchResultSelectedMessage:`. There is also a global
  re-entrancy guard (a static `canSelect` reset on the next runloop hop, 1049-1059) so a
  double tap cannot push two controllers.
- Deselect on return is CPU-count dependent (`viewWillAppear:`, 642-668): immediate on >2
  cores, 0.05 s delayed on 2, 0.1 s on 1 — a 2013 concession to the iPhone 4/4S, which is
  precisely our device. On a 4S (dual core) the search row stays highlighted for 50 ms after
  the chat pops back.

## 8. Our port — `src/TGSearchViewController.m`

Our equivalent is `TGSearchResultCell`, a file-private class in
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGSearchViewController.m:170-315`, used from
`cellForRowAtIndexPath:` at line 2526. Constants at lines 13-18. Both plate PNGs are present
in `iTgLegacy/images/` (`Cell102@2x.png`, `CellHighlighted102@2x.png`).

**What is right** (and I checked the arithmetic, not just the constants): 51 pt row
(`:14` vs original `:1129`); avatar 40×40 at (5,5) with radius 4 (`:232-235` vs `:189` +
the `avatar40` processor); text left 54 = 45 + 9 (`kSearchTextLeft = 54.0f`, `:17`);
text width `width − 54 − 5` = the original's `width − 45 − 9 − 5` (`:274` vs `:185`);
subtitle's extra `+1` indent (`:292` vs `:204`); both vertical-centring formulas including
the `−1` lift (`:289-291` vs `:198/202`); the 5 pt gap between name halves (`:303` vs `:210`);
the −1/+1 pressed-plate correction (`:264-268` vs `:174-177`); fonts 19/19-bold/13 and
colours `0x111111` / `0x808080` (`:195-217`). The mononym-goes-bold rule is reproduced
faithfully at `:245-251`. This is a good port.

**Differences a user can see:**

1. **Blue date column.** We add a fourth label, `_dateLabel`, 13 pt, `0x337acc`, right-aligned
   at the right margin, and we *shrink the title width* to make room
   (`src/TGSearchViewController.m:220-230, 276-281, 309-313`). The original cell has no date
   at all — search rows in v1.1 carry no timestamp (`TGDialogListSearchCell.m` has three
   labels only, lines 13-15). Keep it if it is a deliberate modern-interaction import, but
   know it is ours, not 2013's, and it costs the title `dateWidth + 8` points.
2. **No secret-chat green.** The original paints the title `0x229a0a` when `isEncrypted`
   (`TGDialogListSearchCell.m:139, 142-143`). Our cell has no encrypted flag and always uses
   `0x111111` (`src/TGSearchViewController.m:196-199, 207`). A secret chat in search results
   looks like a normal chat. **Fix:** add an `isEncrypted` property and switch the two title
   labels to `0x229a0a`.
3. **Long two-part names truncate instead of running off.** We clamp `firstWidth` to
   `textWidth` and clamp the second label to the right margin
   (`src/TGSearchViewController.m:299-307`); the original clamps neither (`:209-210`) and lets
   the text bleed to the screen edge. Ours is arguably nicer; it is not the original. If we
   want fidelity, drop the two clamps. I would leave ours, but the difference should be a
   decision, not an accident.
4. **Placeholder avatars.** The original uses a fixed palette of pre-rendered PNGs indexed by
   uid / conversation id (`TGInterfaceAssets.mm:314-339`), including a dedicated
   `SmallAvatarSystem.png` for uid 333000 (Telegram service notifications) and a *generic*
   grey placeholder for uid ≤ 0. We render initials via `[TGIcons avatarWithInitials:...]`
   / `avatarForChat:` (`src/TGSearchViewController.m:2551-2562`). That is a modern-Telegram
   look (lettered avatars arrived later — see §9). Acceptable as a system-wide choice, but it
   must be the *same* choice as our chat-list cell, and the service-account case (333000)
   has no special icon in ours.
5. **No `adjustOrdering`.** We never re-insert the pressed cell above its neighbours
   (absent from `src/TGSearchViewController.m:263-314`). Because our pressed plate is also
   the 52 pt `CellHighlighted102`, its top pixel can be clipped by the cell above on press.
   **Fix:** port the `adjustOrdering` loop (`TGDialogListSearchCell.m:248-273`) and call it
   from `setSelected:animated:` / `setHighlighted:animated:`, which we do not override at all.
6. **No fade-in on the avatar.** The original fades remote avatars in over 0.14/0.3 s
   (`TGDialogListSearchCell.m:86, 152`). Ours assigns `avatarView.image` directly
   (`src/TGSearchViewController.m:2557, 2562`), so avatars pop.
7. **Label backgrounds.** Original labels are opaque white (`:66, 74, 82`) for pre-CoreAnimation
   blending performance; ours are `clearColor` (`:194, 204, 212`). Visually identical
   (UIKit clears subview backgrounds during selection anyway), but on a 4S the opaque path is
   measurably cheaper during scroll. Worth copying if search scrolling ever stutters.
8. **Flat-theme branch.** Ours drops both plates entirely when `[TGTheme shared].isFlat`
   (`src/TGSearchViewController.m:184-192`) and takes colours from the theme. The original has
   one appearance. This is our own theming layer, not a defect — just note that the 51 pt row
   and the −1 lift were tuned for the gradient plate, and in flat mode nothing verifies them.
9. **Whole-screen search instead of an overlay table.** In the original, search results replace
   the dialog list in-place via `_searchMixin` (`TGDialogListController.mm:644, 977-986`). We
   push a dedicated `TGSearchViewController` from `searchBarShouldBeginEditing:`
   (`src/TGChatListViewController.m:2357-2361`). Structural, deliberate, and outside this
   cell's scope — flagging it so nobody "fixes" it later.

## 9. What became of it

**twelve** (`/Users/alexanderhavrysh/Git/iOS/twelve/legacy/TelegraphKit/TGDialogListSearchCell.m`)
keeps the same class, same name, same method skeleton, and shows exactly which pressures
deformed it:

- The gradient plates are gone: `backgroundView = nil`, a `CALayer` hairline separator at
  `x = 65` and `TGSeparatorColor()`, and `selectedBackgroundView` is a plain
  `TGSelectionColor()` view (twelve `TGDialogListSearchCell.m:38-45`). Flat iOS 7 killed
  `Cell102.png`, and with it the reason for the −1/+1 dance (which is nevertheless still
  there, lines 250-251, now vestigial).
- The avatar moved right: `CGRectMake(leftPadding + 14, 5, 40, 40)` and the text inset became
  `avatarWidth + 21` = 66 (twelve lines 279, 273) — the iOS 7 65 pt separator inset. Our
  54 pt is correctly the *2013* number.
- `TGRemoteImageView` → `TGLetteredAvatarView` with `circle:40x40`, and placeholders became
  initials-from-name rather than palette PNGs (twelve lines 67-68, 194, 202-209). Forced by
  a feature: usernames/peers with no photo needed to be distinguishable at a glance.
- Features accreted: unread badge, verified icon, `TGPresentation` theming, `SMetaDisposable`
  for channel loading, `prepareForReuse` (twelve lines 72-86, 91-129, 211-237). The subtitle
  became an `NSAttributedString` and now actually gets used, which forced the title to shrink
  from 19 pt to 17 pt whenever a subtitle is present (twelve line 135) — precisely the
  coupling described in §3, resolved by shrinking the font rather than growing the row.
- `setBoldMode:` finally became meaningful: it stores `_boldMode` and the fonts are applied in
  `resetView:` (twelve lines 132-153), fixing the original's ordering bug where a `setBoldMode:`
  before a font-touching `resetView:` would be discarded.
- Note twelve *also* has `TGChatSearchController.m:370-375` and `TGHashtagSearchController.m:372-375`
  dequeuing under the string `@"TGDialogListSearchCell"` but instantiating `TGDialogListCell` —
  the identifier outlived the class in those screens.

**Modern client** (`Telegram-iOS`): the concept survives as `ContactsPeerItem`
(`submodules/ContactsPeerItem/Sources/ContactsPeerItem.swift`) for peer hits and as the
ordinary `ChatListItem` for conversation hits
(`submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift:1201`). Same skeleton,
thirteen years on: 40 pt avatar, 65 pt left inset, 10 pt right inset
(`ContactsPeerItem.swift:807, 811-812`), title regular + medium pair
(`:794-795`), status 13 pt (`:797-803`). The two changes of substance are (a) every size is
now derived from `presentationData.fontSize.itemListBaseFontSize` — Dynamic Type, a
requirement that did not exist in 2013 — and (b) the split-name bold trick is gone: modern
search bolds the *matched substring*, not the last name. Our 19 pt/bold-last-name split is
period-correct and should stay.

## 10. Ambiguities I am not going to invent an answer for

- Whether the original ever *intended* the group-chat badge to show in this cell. It is wired
  up and never laid out; I cannot tell from the source whether it was cut or forgotten.
- The exact rendered `lineHeight` of 19 pt Helvetica on iOS 6.1.3, which the vertical centring
  depends on. I read the formula, not the metric; if our rows look a point off, that is where
  to measure rather than to hard-code.

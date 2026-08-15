# TGContactCell — original study

Source of truth: `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGContactCell.h`
(46 lines), `TGContactCell.m` (1035 lines), and its private drawing companion
`TGContactCellContents.h` / `TGContactCellContents.m` (97 lines). The class exists under exactly that
name; there is no TelegraphKit variant. TelegraphKit's near relatives are `TGDialogListSearchCell` and
`TGDialogListCell`, which share the avatar filter and the `Cell102` background but not this layout.

Everything below is cited as `file:line` against those files unless stated otherwise.

---

## 1. What it is

One row of a person list. It is used for five different screens, all of which reuse the same class with
different constructor flags:

| Screen | Construction | Flags |
| --- | --- | --- |
| Contacts list / compose / invite picker | `TGContactsController.mm:1585` | `selectionControls:` yes when mode is Compose or Invite, `editingControls:false` |
| Add-contacts (search for people) | `TGAddContactsController.mm:476` | plain `initWithStyle:reuseIdentifier:` → both flags false (`TGContactCell.m:283-286`) |
| Blocked users | `TGBlockedUsersController.mm:332` | `selectionControls:false editingControls:true` (swipe-to-delete) |
| People nearby | `TGPeopleNearbyController.m:15` (import; uses the same 51/44 heights, `TGPeopleNearbyController.m:370-373`) | |

The two flags are decided once, at construction, and are baked into the view tree: a cell built without
`selectionControls` has no check button and no tap recogniser at all (`TGContactCell.m:353-359`,
`314-324`), and one built without `editingControls` has no delete button and no swipe recogniser
(`TGContactCell.m:361-428`). Reuse pools are therefore keyed per screen (`@"CC"`, etc.), never shared
between a picker and a plain list.

## 2. Row height, and why

51 points with an avatar, 44 without:

- `TGContactsController.mm:1350-1357` — section 0 of the main contacts list (the "New Group" style action
  rows) is 44; Invite mode is a flat 51; otherwise `user.uid > 0 ? 51 : 44`. A non-positive uid means a
  synthetic entry (an address-book person who is not on Telegram), which is exactly the case where
  `hideAvatar` is set (`TGContactsController.mm:1423`).
- `TGAddContactsController.mm:395-397` returns 51.
- `TGPeopleNearbyController.m:373` returns 51 when the list has content, 44 when empty.

51 is not arbitrary: the background artwork `Cell102.png` is literally 2×102 pixels
(`Resources/Cell102@2x.png`, measured), i.e. 1×51 points, a one-pixel-wide vertical slice that the cell
stretches horizontally. The row height *is* the artwork height. The avatar is 40pt inset 5pt top and
bottom (`TGContactCell.m:326`, `668`), 40 + 5 + 5 = 50, plus the one-point hairline the artwork carries
at its bottom edge = 51.

## 3. Public surface (`TGContactCell.h`)

```
avatarUrl, hideAvatar, user                       // h:16-18
titleTextFirst, titleTextSecond, subtitleText     // h:20-22
itemId, itemKind, selectionEnabled, contactSelected, actionHandle  // h:24-28
boldMode                                          // h:30
isDisabled                                        // h:32
subtitleActive                                    // h:34
-resetView:                                       // h:39
-updateFlags:(animated:)(force:)                  // h:40-42
-setSelectionEnabled:animated:                    // h:44
```

The critical contract is that **setters are dumb; `resetView:` is what applies them**
(`TGContactCell.m:487-567`). Every call site sets a batch of properties and then calls
`[contactCell resetView:animated]` (`TGContactsController.mm:1471`, `TGAddContactsController.mm:424`,
`TGBlockedUsersController.mm:348`). `setBoldMode:` (`TGContactCell.m:455-471`) only stores the value —
its body is entirely commented-out dead code from the pre-`TGContactCellContents` era. `setIsDisabled:`
(`473-485`) is the one exception: it applies immediately, because it also flips `selectionStyle`.

## 4. View tree and drawing model

This is the part most easily got wrong. The cell has **very few real subviews**:

- `_avatarView` — `TGRemoteImageView`, frame `(5, 5, 40, 40)` (`TGContactCell.m:326`), `fadeTransition`
  on (`:327`).
- `_contactContentsView` — `TGContactCellContents`, a transparent custom-drawn view filling
  `contentView.bounds` with flexible width/height, `userInteractionEnabled = false`
  (`TGContactCell.m:330-335`).
- `_checkButton` (only with selection controls), `_switchButton` + `_editingButton` (only with editing
  controls), `_highlightProxy`.

**The name and the subtitle are not labels.** Both are drawn by `TGContactCellContents -drawRect:`
(`TGContactCellContents.m:54-95`). `_subtitleLabel` is a `TGDateLabel` that is *never added as a
subview*: it is created (`TGContactCell.m:339-349`), handed to the contents view as
`_contactContentsView.dateLabel` (`:351`), and then rendered by the contents view calling
`[_dateLabel drawRect:]` directly into its own CGContext after translating by the label's frame
(`TGContactCellContents.m:88-94`). `_subtitleLabel.frame` is therefore a pure geometry carrier, set in
`layoutSubviews` (`TGContactCell.m:690`) but never affecting a view hierarchy.

Consequence: everything textual is one opaque redraw. `TGContactCellContents -requestRedrawIfNeeded`
(`:27-38`) suppresses redraws unless highlight, width, title offset, bold mode, or either title string
changed — that is the scroll-performance mechanism on a 4S. Note it does **not** watch the subtitle
text, which is why `resetView:` calls `[_contactContentsView setNeedsDisplay]` explicitly at
`TGContactCell.m:547` and `:566`.

`_highlightProxy` is a `TGHighlightTriggerLabel` whose `targetViews` is `[_contactContentsView]`
(`TGContactCell.m:430-432`). Its job is to relay UIKit's cell-highlight state into the custom-drawn
view so the text can repaint white on the blue selection.

## 5. Metrics

All from `-layoutSubviews` (`TGContactCell.m:645-709`) unless noted.

| Quantity | Value | Line |
| --- | --- | --- |
| `retinaPixel` | 0.5 on retina, 0 otherwise | `:649` (also `:293`) |
| Avatar frame | `(leftPadding + 5, 5, 40, 40)` | `:668` |
| `avatarWidth` | `hideAvatar ? 0 : 45` (5 + 40) | `:662` |
| `leftPadding` | 0 normally; when `selectionEnabled`: 40 with avatar, 34 without; `+2` while `editing` | `:658-660` |
| Text left edge | `avatarWidth + 9 + leftPadding` → **54** in the ordinary case | `:708` |
| Subtitle left edge | text left `+ 1` → **55** | `:690` |
| Available text width | `viewSize.width - avatarWidth - 9 - 5 - leftPadding` (5pt right margin) | `:664, :666` |
| Title Y, no subtitle | `(int)((height - titleLineHeight) / 2) - (hideAvatar ? 0 : 1)` | `:683` |
| Title Y, with subtitle | `(int)((height - titleLineHeight - subtitleLineHeight - 1) / 2)` | `:687` |
| Subtitle Y | `titleY + titleLineHeight + retinaPixel` | `:690` |
| Check button frame | `(selectionEnabled ? 7 : -7 - width, 10, 29, 29)` | `:676` |
| Selected background | shifted to `y = -1`, height `+1`, so the highlight covers the separator above | `:651-654`, repeated in `setSelected:` `:718-721` and `setHighlighted:` `:734-737` |

Fonts and colours:

| Element | Value | Line |
| --- | --- | --- |
| Title regular | `systemFontOfSize:19` | `:332` |
| Title bold | `boldSystemFontOfSize:19` | `:333` |
| Title colour | black; **white when highlighted** | `TGContactCellContents.m:82` |
| Title colour, disabled | `0xaeaeae` | `TGContactCellContents.m:76-79` |
| Subtitle font | `systemFontOfSize:(13 + retinaPixel)` → 13.5 on retina | `:341` |
| Subtitle AM/PM font | `systemFontOfSize:11`, am/pm width 19, dst offset 3 | `:343-346` |
| Subtitle colour, normal | `UIColorRGBA(0, 0.53)` — black at 53% alpha, applied in `resetView:` | `:543` |
| Subtitle colour, online | `0x0779d0` | `:544` |
| Subtitle colour, highlighted | white (`0xffffff`) | `:348` |
| Subtitle colour, disabled | `0xaeaeae` | `TGDateLabel.m:109-112` |
| Selection-mode highlight background | `0xe9eff5` with 1pt `0xd5dee5` stripes top and bottom | `:748-758` |

Note the subtitle's grey is set twice with different values: `0x888888` at construction (`:347`) and
`UIColorRGBA(0, 0.53)` in `resetView:` (`:543, :546`). Since `resetView:` always runs before display,
**53%-alpha black is the one that ships**; `0x888888` is vestigial. There is also commented-out code
(`:763-779`) that would have switched the subtitle to `0x778698` on highlight — abandoned.

## 6. The two-part name

The name is two strings, drawn side by side with independent weights, so that the sort key is bold.

`resetView:` (`:489-500`): when `titleTextSecond` is nil or empty, bold mode is forced to 1 and the
second string is cleared, so a one-word name is drawn **bold**. Otherwise `boldMode` passes through.
`boldMode` is a bitmask: bit 1 bolds the first string, bit 2 bolds the second
(`TGContactCellContents.m:67-68`). Default is 2 (`TGContactCell.m:337`).

Who is "first" depends on the display order, and which one is bold depends on the *sort* order, and the
two are independent (`TGContactsController.mm:1428-1463`): with `DisplayFirstFirst`, first = first name,
second = last name, and bold mode is 1 if sorting by first name else 2; with display last-first the
assignment and the bold mode both flip. So in the shipped default (display first-first, sort by last
name) you see *John* **Appleseed** with the surname bold.

Drawing (`TGContactCellContents.m:70-86`):

- The first string is measured, then **clamped** to `width - titleOffset.x - 5 - 14`. The `5` is the
  right margin; the `14` is a reserve so a very long first name still leaves a sliver for the second.
- The first string is drawn with `NSLineBreakByTruncatingTail` — it gets an ellipsis.
- The second string starts at `firstWidth + 4` (a 4pt gap, not a space character) and is given all the
  remaining width, drawn **without** an explicit line-break mode, i.e. `drawInRect:withFont:`'s default
  word wrapping in a single-line-height rect. In practice a too-long surname is **clipped, not
  ellipsised** — an asymmetry the fork later fixed (see §10).
- Both are drawn at `titleFirstSize.height` — the second string's own line height is ignored, so a bold
  second string cannot make the row taller.

Empty/missing cases: a contact with no first name is handled at the call site by promoting the last name
into `titleTextFirst` and nilling the second (`TGContactsController.mm:1430-1434`,
`TGAddContactsController.mm:406-410`), which then triggers the bold-mode-1 path. Note the original bug at
`TGContactsController.mm:1447-1451`: in the display-last-first branch with an empty last name it assigns
`titleTextSecond` twice and never sets `titleTextFirst`, so the previous cell's first name survives reuse.

## 7. Subtitle content and the "active" state

`subtitleStringForUser` (`TGContactsController.mm:1474-1500`): `Presence.online` (and
`subtitleActive = true`) when online; `Presence.offline` when `lastSeen == 0`; `Presence.invisible` when
`lastSeen < 0`; otherwise `"<Presence.lastSeen> <relative date>"`. For synthetic entries (`uid <= 0`) the
subtitle is `user.customProperties[@"label"]`. `subtitleActive` drives only the colour swap at
`TGContactCell.m:546`.

Other screens put other things there: Add-contacts shows `"%d mutual contact(s)"`, or nil when the count
is zero (`TGAddContactsController.mm:417-422`). Blocked users sets no subtitle at all.

When the subtitle is nil or empty, `_subtitleLabel.hidden` is set (`TGContactCell.m:504`) and the title
is vertically centred instead (`:681-683`). The hidden flag is only consulted by `layoutSubviews`;
`TGContactCellContents -drawRect:` draws the date label whenever it is non-nil (`:88`), which is harmless
only because `dateText` is then nil and `drawAtPoint:` on nil is a no-op.

`TGDateLabel` is used rather than `UILabel` because it splits a trailing " AM"/" PM" off the string and
redraws it in an 11pt font right-aligned within a fixed 19pt reserve (`TGDateLabel.m:39-69`, `:76-84`,
`:123-126`) — the same small-caps time treatment as the dialog list. For a presence string with no AM/PM
suffix this degrades to a plain single-font draw.

## 8. Avatar

`resetView:` (`:506-532`):

- `hideAvatar` → the image view is simply hidden (`:508`); the text then starts at `9 + leftPadding`.
- With a URL: loaded through `TGRemoteImageView` with filter `@"avatar40"`, which is
  `TGScaleAndRoundCorners(source, 40×40, corner radius 4)` (`TGTelegraph.mm:486-489`). **Rounded square,
  4pt radius — not a circle.** Cross-fade duration is 0.14s when the update is animated, 0.3s otherwise
  (`:516`); when animated the current image is passed as the placeholder so there is no flash to grey
  (`:521-522`). The load is skipped entirely if the URL already matches `currentUrl` (`:517`).
- With no URL: `[[TGInterfaceAssets instance] smallAvatarPlaceholder:_itemId]`
  (`:530`) — a flat coloured artwork chosen by `colorIndexForUid`, `SmallAvatar1..N.png`, with
  `SmallAvatarSystem.png` for uid 333000 and a generic placeholder for uid ≤ 0
  (`TGInterfaceAssets.mm:314-332`). **The 2013 client has no initials avatars**; those arrive later
  (see §10).

## 9. States and behaviour

**Tap.** With selection controls, a full-bleed transparent `tapAreaView` covers the content view and
carries a tap recogniser with `cancelsTouchesInView = false` (`:316-323`), so the row still highlights
normally while the tap toggles selection. Both the recogniser (`:437-443`) and the check button
(`:357`) funnel into `checkButtonPressed`, which does not mutate state locally — it posts
`/contactlist/toggleItem` through the `ASHandle` with `itemId`, current `selected`, and `self`
(`:445-448`). The controller decides and calls back `[cell updateFlags:selected force:true]`
(`TGContactsController.mm:2536`). This is a strict one-way data flow: the cell never toggles its own
checkmark.

**Check button.** `TGContactCheckButton` (`:130-254`), 29×29, artwork `Contact_Check.png` /
`Contact_Checked.png` (58×58 and 60×60 pixels respectively — the checked art is 1pt larger and relies on
the image view's flexible autoresizing at `:167`). Press feedback is a 0.8 scale applied on highlight and
tracked through `touchesMoved`/`touchesEnded`/`touchesCancelled` so dragging off restores identity
(`:170-215`). Checking animates 0.8 → 1.16 over 0.12s ease-out then → 1.0 over 0.08s ease-in
(`:226-238`); unchecking is a single 0.16s ease-out back to identity (`:242-245`). Entering selection
mode slides/fades the button in over 0.3s and shifts the text right by 40 (`:588-643` together with
`:658`, `:676`).

**Highlight.** In the ordinary case UIKit's `selectedBackgroundView` (`CellHighlighted102.png`) does the
work and the drawn text flips to white. In selection mode the blue selection is suppressed
(`selectionStyle = None`, `TGContactsController.mm:1411`) and a hand-built pale background
`0xe9eff5` with `0xd5dee5` hairlines is inserted at index 0 of the content view instead
(`:746-760`) — created lazily on first highlight and thereafter only hidden/unhidden.

**z-ordering.** `adjustOrdering` (`:787-813`) walks the table view's subviews and re-inserts the cell
above the last cell/search bar when it is selected or highlighted, so the extended (`y = -1`,
`height + 1`) selection art is not clipped by the neighbour drawn on top. With editing controls the
selected background and content view also get explicit `zPosition` 1 and 2 (`:310-311`).

**Editing / swipe to delete** (blocked-users only). A left-or-right swipe on a non-editing cell reveals
the delete button (`:1024-1033`). In editing mode a 30×30 round switch button sits at x = 4
(`:390`, `:830`), and pressing it rotates the minus glyph −90° into a vertical bar and swaps to the
active artwork over 0.25s (`:904-918`). The delete button is a stretchable `ListDeleteButton.png`,
61×31 at `width - 6 - 61`, animated in from a 2pt-wide stub over 0.25s with its label cross-fading
(`:931-948`); the "Delete" label is not a live label but a pre-rendered image drawn once into a bitmap in
`dispatch_once` with a bold 13pt font and a `0xa30f0a` 20%-alpha shadow offset (0, −1) (`:370-388`).
Committing routes through `TGActionTableViewDelegate -commitAction:` (`:883-897`).

**Reuse.** There is no `prepareForReuse`. `resetView:` is the reuse hook and it is responsible for
cancelling editing state: it resets the minus glyph (`:550-556`) and collapses the delete button back to
its 2pt stub (`:558-563`). Anything `resetView:` does not touch — for example a stale `titleTextFirst`
in the buggy branch noted in §6 — survives into the recycled cell.

**Disabled.** `isDisabled` greys both title (`TGContactCellContents.m:74-79`) and subtitle
(`TGDateLabel.m:103-113`) to `0xaeaeae` and forces `selectionStyle = None` (`:481`). Used for contacts
that cannot be added to the current group.

---

## 10. What became of it

**twelve** (`twelve/Telegraph/TGContactCell.m`, 504 lines vs 1035) kept the class and the
`TGContactCellContents` split verbatim but stripped it back and re-skinned it:

- All editing/swipe machinery, the delete button and the minus switch are **gone** — that job moved to
  UITableView's own editing support. That is the bulk of the 531 removed lines.
- `TGPresentation` theming replaces hard-coded colours; the title colour is now
  `_presentation.pallete.textColor` and no longer flips to white on highlight
  (`twelve/Telegraph/TGContactCellContents.m:94` vs original `:82`), because flat-design selection is a
  light grey rather than a blue gradient.
- A `CALayer` separator replaces the `Cell102` background artwork
  (`twelve/Telegraph/TGContactCell.m:54-56`), inset 65pt (98 in selection mode, `:339-341`).
- Title font 19 → **17** (`twelve:82`), the iOS 7 list standard.
- Avatar left inset 5 → **14** (`twelve:365`), and the avatar becomes a `TGLetteredAvatarView` with
  initials — `loadUserPlaceholderWithSize:uid:firstName:lastName:` (`twelve:242`) — and a circular
  filter `circle:40x40`, falling back to the original rounded-square `avatar40` only under
  `[TGPresentation classicIOS6Style]` (`twelve:234-237`). This is the clearest example of the 2013
  artwork surviving as an explicit legacy branch.
- The second-name clipping asymmetry described in §6 **was fixed**: twelve measures the second string and
  clamps it to the remaining width minus 8 (`twelve/Telegraph/TGContactCellContents.m:83-85, 98`).
  This is worth copying — it is a bug fix on the original's own lineage, not a redesign.
- Check button 29×29 with hand-rolled scale animation → shared `TGCheckButtonView` at 32×32, vertically
  centred (`twelve:112`, `:376`).

**Telegram-iOS** (`submodules/ContactsPeerItem/Sources/ContactsPeerItem.swift`) kept the *ideas* and threw
away the implementation. The two-string bold-by-sort-order name survives exactly, now as one
`NSAttributedString` with per-run fonts and a real space between the parts rather than a 4pt gap
(`:962-968`) — which means truncation is uniform across the whole name and the original's clipped-surname
problem cannot occur. Left inset is 65 (`:812`), adjusted by ±13/+38 for selection and other modes
(`:816-827`). Avatar diameter is still 40 but scales with the user's font-size setting
(`:807`), and row height is no longer a constant at all: it is `verticalInset * 2 + titleHeight +
statusHeight` (`:1216`), i.e. derived from the text, because Dynamic Type made a fixed 51 impossible.
The 13pt subtitle became 13 or 15 depending on context (`:798-804`).

The through-line: fixed height derived from artwork → height derived from text; rounded-square avatar →
circle; two separately drawn name halves → one attributed string; ASHandle string-action callbacks → a
typed closure. Only the two-weight name is unchanged in intent after thirteen years.

---

## 11. Our port

Our equivalent is `TGContactRowCell`, a private class inside
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGContactsViewController.m:208-390`, configured by
`-applyNameToCell:user:` (`:3118-3143`), `-applyBadgesToCell:user:` (`:3145-3169`),
`-applyAvatarToCell:user:` (`:3171-3183`) and `-tableView:cellForRowAtIndexPath:` (`:3188-3211`).

It is a labels-based reimplementation rather than a custom-drawn one, which is a legitimate choice, and
most of the geometry is right. Correct already, so briefly: row heights 51/44
(`:18`, `:25`, `:3004-3007`); text left 54 (`:21`); subtitle left 55 (`:385`); avatar 40 at (5,5) with
4pt corner radius (`:17,19,20,26`, `:348`, `:3182`); title 19pt regular/bold; subtitle
`13 + retinaPixel` (`:260`); subtitle grey `white 0.0 alpha 0.53` (`:261`) and online `0x0779d0`
(`:3139-3140`); the two title-Y formulas including the `-1` and the `retinaPixel` subtitle offset
(`:356-358`, `:386`); the first-name clamp `width - 54 - 5 - 14` and the 4pt gap (`:360-372`); the
`y = -1 / height + 1` selected-background stretch (`:340-345`); `Cell102`/`CellHighlighted102`
(`:227-233`, and `images/Cell102@2x.png` is present in the repo).

### Defects a user can see

1. **Bold weight is on the wrong half for the shipped sort order.** `applyNameToCell:` (`:3120-3133`)
   always draws first name regular and last name bold, which matches original `boldMode = 2`. That is
   the correct default (`TGContactCell.m:337`), but we hard-code it: the original picks bold mode from
   the sort order (`TGContactsController.mm:1439-1442`, `1459-1462`). If we ever offer a sort-by-first-name
   option the bold must move to the first name. Today this is latent, not visible — flagging it so the
   coupling is not lost.

2. **A too-long surname gets an ellipsis where the original clips it.** Ours is a `UILabel` whose default
   line-break mode is truncating-tail (`:250-256`, `:372`); the original draws the second string with
   `drawInRect:withFont:` and no break mode (`TGContactCellContents.m:86`). Honest note: twelve
   deliberately fixed this toward clamping-with-measurement
   (`twelve/Telegraph/TGContactCellContents.m:83-85`), and an ellipsis is the better behaviour. I would
   keep ours, but record it as a knowing divergence rather than pretend it matches.

3. **No `hideAvatar` mode.** The original hides the avatar for `uid <= 0` entries — address-book people
   not on Telegram — and pulls the text left to `9 + leftPadding` = 9, and drops the row to 44
   (`TGContactCell.m:506-509`, `:662`, `:708`; `TGContactsController.mm:1357, 1423`). Our layout hard-codes
   `kContactTextLeft = 54` (`:21`) and always shows an avatar. If our contacts list ever shows
   non-Telegram address-book entries, those rows will be wrong. Fix: a `hideAvatar` flag that sets
   `avatarView.hidden`, changes the text origin to 9, and reports 44 from `heightForRowAtIndexPath:`.

4. **No disabled state.** `isDisabled` → `0xaeaeae` title and subtitle plus `selectionStyle = None`
   (`TGContactCell.m:473-485`, `TGContactCellContents.m:74-79`) has no equivalent in ours. Needed the
   moment we show an add-to-group picker where some members are already in the group.

5. **Multi-select uses the system checkmark accessory, not the original check button.** The invite and
   new-group pickers (`TGContactsViewController.m:487-505` and `:620-635`) fall back to a plain
   `UITableViewCell` with `UITableViewCellAccessoryCheckmark`, so they lose the avatar, the two-weight
   name, the 51pt row, and the 29×29 `Contact_Check`/`Contact_Checked` button on the **left** at x = 7
   with the 40pt text shift and the 0.8→1.16→1.0 pop (`TGContactCell.m:676`, `:217-252`, `:658`). This is
   the largest visible divergence in this component. Fix: give `TGContactRowCell` a
   `selectionEnabled`/`contactSelected` pair mirroring `TGContactCell`, reuse it in both pickers, and add
   `Contact_Check@2x.png` / `Contact_Checked@2x.png` to `images/` (neither is currently in the repo; the
   originals are 58×58 and 60×60 pixels).

6. **Selection-mode highlight background is missing.** `0xe9eff5` with `0xd5dee5` 1pt stripes replacing
   the blue selection while in multi-select (`TGContactCell.m:746-760`). Blocked by defect 5; do them
   together.

7. **Avatar placeholder is initials, the original is a flat coloured square.**
   `applyAvatarToCell:` uses `[TGIcons avatarWithInitials:...]` (`:3176-3179`). The 2013 client used
   `SmallAvatar%d.png` picked by uid, with no letters at all
   (`TGInterfaceAssets.mm:314-323`); initials arrived only in the twelve era
   (`twelve/Telegraph/TGContactCell.m:242`). This is a real period inaccuracy, though a defensible one
   given we would otherwise need the `SmallAvatar` artwork. Worth a deliberate decision, not an accident.

8. **Badge column is ours, not theirs.** Premium / verified / close-friend glyphs and the
   `SCAM`/`FAKE`/`Birthday today` subtitle prefixes (`:262-290`, `:3145-3169`) have no original. Fine as
   modern-interaction content, but note that they eat into the title width via `badgeWidth`
   (`:353`, `:361`) while the original reserved a flat 14pt for the second name
   (`TGContactCellContents.m:71-72`). Our `firstLimit` still uses the original's 14 (`:360`) *and*
   subtracts badge width separately, so with three badges a long first name is squeezed harder than the
   original ever squeezed it. Not wrong, just be aware the two reserves stack.

9. **No avatar cross-fade.** The original fades a newly loaded avatar in over 0.14s (animated update) or
   0.3s, keeping the old image as the placeholder so there is no grey flash
   (`TGContactCell.m:516-522`). We assign `avatarView.image` directly (`:3181`). On a 4S scrolling a list
   whose photos decode asynchronously, this is a visible pop.

10. **Subtitle is a plain `UILabel`, so AM/PM shrinking is lost.** We have `TGDateLabel` in the tree
    (`src/TGDateLabel.m`) but the contact cell does not use it (`:258-262`). Only matters if a contact
    subtitle ever ends in " AM"/" PM" — `last seen at 3:40 PM` does, in 12-hour locales
    (`TGContactCell.m:341-346`, `TGDateLabel.m:123-126`). Low priority, but it is the one place our
    subtitle typography can differ from the original by a visible amount (13.5pt vs 11pt for the meridiem).

### Genuinely ambiguous

- The original sets the subtitle colour twice (`0x888888` at `:347`, then `UIColorRGBA(0, 0.53)` at
  `:543`). I read `resetView:` as always winning, so 53% black is what shipped and what we match — but a
  cell displayed before any `resetView:` would show `0x888888`. No call site does that.
- `_subtitleLabel.hidden` never suppresses drawing (§7); whether that is intentional or a latent bug is
  not determinable from the source.

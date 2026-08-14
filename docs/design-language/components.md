# Design language — Chapter: Controls and chrome

Authority: `telegram-original-sources/extracted/telegram_iphone.src` (Telegram for iOS 1.x, 2013).
Every number below is copied from the real `.m` files or measured off the real `@2x.png`. Where a
number is inferred, it says so.

All pixel sizes quoted as `WxH @2x` are the raw retina PNG. Points = half of that. Asset names are
used **without** `@2x` and (for stretchables) **with** the `.png` suffix, exactly as the original
does: `[UIImage imageNamed:@"HeaderButton.png"]`.

## 0. Rules that apply to every control in this chapter

1. **Stretch with `stretchableImageWithLeftCapWidth:topCapHeight:`, never
   `resizableImageWithCapInsets:`.** The latter is not reliable on iOS 6.1.3 hardware. Cap widths
   below are given in **points** and go straight into `leftCapWidth`. `topCapHeight` is `0` for
   every horizontal control (buttons, bars, badges stretched only sideways); it is
   `height/2` only for the two badges that stretch in both directions.
2. **Frame layout only.** No Auto Layout, no `edgesForExtendedLayout`, no `tintColor` on non-bar
   views, no `barTintColor`.
3. **Retina half-pixel rule.** The original defines `float retinaPixel = TGIsRetina() ? 0.5f : 0.0f;`
   and adds it to y-origins and to some font sizes. Keep doing that; do not round it away. On the
   4S `TGIsRetina()` is always true, so `retinaPixel == 0.5`.
4. **Chrome text is always white with a dark 1px upward shadow.** `shadowOffset = CGSizeMake(0, -1)`.
   Shadow colour `rgba(0x0e284d, 0.4)` for grey/back buttons, `rgba(0x042651, 0.3)` for blue
   (Done) buttons. No exceptions, including for new controls you invent.
5. **Nothing in chrome is more than 30pt tall in portrait, 25pt in landscape.** That pair of numbers
   (`30 / 25`) is the single height constant of the whole bar system.

---

## 1. TGToolbarButton — the five bar-button types

Source: `TelegraphKit/TelegraphKit/TGToolbarButton.m` / `.h`.

```
typedef enum {
    TGToolbarButtonTypeGeneric   = 0,
    TGToolbarButtonTypeBack      = 1,
    TGToolbarButtonTypeDone      = 2,
    TGToolbarButtonTypeDoneBlack = 3,
    TGToolbarButtonTypeImage     = 4,
    TGToolbarButtonTypeDelete    = 5,
    TGToolbarButtonTypeCustom    = 6
} TGToolbarButtonType;
```

### Shared metrics (all types)

| Property | Value |
| --- | --- |
| Height | `30` portrait, `25` landscape |
| Y origin in a bar | `7` portrait, `3` landscape (or `0 / 2` plus the bar's `barButtonsOffset` when the superview conforms to `TGBarItemSemantics`) |
| `paddingLeft` / `paddingRight` | `7 / 7` — except Back, which is `15 / 9` |
| `touchInset` | `CGSizeMake(8, 8)`, applied by overriding `hitTest:withEvent:` against `CGRectInset(bounds, -8, -8)` |
| Label font | `[UIFont boldSystemFontOfSize:12]` — **12pt bold, never larger** |
| Label colour | `[UIColor whiteColor]` for every type |
| Label shadow | offset `(0, -1)`; colour per type, see §0.4 |
| Icon/label gap | `4pt` when both present, `0` when only one |
| Disabled | label `alpha = 0.6`; background image unchanged (`adjustsImageWhenDisabled = false`) |
| Width | `paddingLeft + label + (4 + icon) + paddingRight`, floored to `minWidth` (default 0) |
| Subpixel snap | x-origins rounded to `((int)(x * 2.0f)) / 2` on retina |

Never set `adjustsImageWhenHighlighted`; the original explicitly sets both adjust flags to `false`
and swaps the background image instead.

### Per-type backgrounds

| Type | Normal asset | Pressed asset | Left cap | Asset size @2x |
| --- | --- | --- | --- | --- |
| Generic | `HeaderButton.png` | `HeaderButton_Pressed.png` | `6` | 42×60 (21×30 pt) |
| Generic landscape | `HeaderButton_Landscape.png` | `HeaderButton_Landscape_Pressed.png` | `6` | 32×50 |
| Back | `BackButton.png` | `BackButton_Pressed.png` | `15` | 54×60 (27×30 pt) |
| Back landscape | `BackButton_Landscape.png` | `BackButton_Landscape_Pressed.png` | `15` | 60×50 |
| Done (blue) | `HeaderButton_Blue.png` | `HeaderButton_Blue_Pressed.png` | `width/2` = `10` | 42×60 |
| Done landscape | `HeaderButton_Blue_Landscape.png` | `HeaderButton_Blue_Landscape_Pressed.png` | `width/2` = `8` | 32×50 |
| DoneBlack (login) | `HeaderButton_Login_Blue.png` | `HeaderButton_Login_Blue_Pressed.png` | `width/2` | 42×60 |
| DoneBlack landscape | `HeaderButton_Login_Blue_Landscape.png` | `..._Landscape_Pressed.png` | `width/2` | — |
| Image | *none* (`background = nil`) | *none* | — | — |
| Delete | `Header_Button_Delete.png` | *none — no pressed state* | `6` | not in our bundle |
| Custom | supplied by `initWithCustomImages:…` | supplied | caller's | — |

Notes that matter:

- **Done/DoneBlack cap = half the image width**, not 6. A blue button therefore has no flat middle;
  it is two mirrored halves. Reproduce that or the gloss breaks.
- **Type Image** draws no plate at all: the icon is the whole button. Use it for the compose icon
  (`ComposeMessageIcon.png`) and for any new icon-only bar action.
- **Type Delete has no pressed variant** in the original — landscape reuses the portrait asset too.
  A red bar button simply does not light up. Keep that.
- The pressed image is installed for `Highlighted`, `Selected`, and `Highlighted|Selected`.
- Back's background rect is nudged: `origin.x -= 1; size.width += 1;` and, portrait+retina,
  `origin.y += 0.5`. Landscape+retina shifts every type's background down by `0.5`.
- Back's label additionally shifts `-1pt` in x in landscape.

### In our repo

Use `+[TGIcons headerButtonWithTitle:bold:target:action:]` for a Generic text button and
`+[TGIcons styleHeaderButton:]` to plate an existing `UIButton`. They already produce
`HeaderButton` / `HeaderButton_Pressed` at 30pt height with a 12pt centred white label and
`size.width + 16` width (i.e. 8pt padding a side — close enough to the original 7 that you must not
"fix" it per-screen; if it is ever changed, change it there once).
For a blue confirm button follow `TGLoginViewController.m:94` which already loads
`HeaderButton_Login_Blue.png` / `_Pressed` with a half-width cap.
Bundled in `images/`: `HeaderButton`, `HeaderButton_Pressed`, `HeaderButton_Login_Blue`,
`HeaderButton_Login_Blue_Pressed`, `BackButton`, `BackButton_Pressed`. There is **no**
`HeaderButton_Blue`, no landscape variant, and no `Header_Button_Delete` in our bundle — see §9.

---

## 2. The back button

Geometrically a `TGToolbarButton` of type Back, but it is worth its own rules because it is the one
asymmetric control:

- Asset `BackButton.png` (54×60 @2x = 27×30 pt), left cap `15`. The 15pt cap covers the arrow head;
  everything right of it stretches.
- Padding `15` left / `9` right — the text sits off-centre to clear the arrow.
- Label: 12pt bold white, shadow `rgba(0x0e284d,0.4)` at `(0,-1)`.
- Title text is the **previous screen's short title**, truncated to fit; if it will not fit in
  ~90pt, use the literal `Back`. (The original relies on short titles; there is no measured
  truncation constant, so 90pt is our ruling.)
- Never use `UINavigationItem.backBarButtonItem` styling APIs on iOS 6.1.3 beyond
  `setBackgroundImage:forState:barMetrics:` on the appearance proxy — and remember that
  `respondsToSelector:` on an appearance proxy always answers NO, so never gate those calls.

---

## 3. Cell plates

The 2013 list is not a `UITableView` with a separator colour. Every row draws a **plate image**: a
1–2px-wide vertical slice containing the row's gradient plus its bottom hairline, installed as
`backgroundView`, with a second slice as `selectedBackgroundView`.

### 3.1 `Cell102` — the 51pt contact/settings row

| | |
| --- | --- |
| Normal | `Cell102.png`, 2×102 @2x → **51pt row height** |
| Pressed | `CellHighlighted102.png`, 2×104 @2x (one point taller on purpose) |
| Stretch | none horizontally in the original: `[[UIImageView alloc] initWithImage:cellImage]` with autoresizing. If you must stretch, cap `1` / `topCapHeight 0`. |
| Row height | `51` |
| Avatar | `CGRectMake(5, 5, 40, 40)` — 40pt round avatar, 5pt inset |
| Title | `[UIFont systemFontOfSize:19]`, bold variant `boldSystemFontOfSize:19` |
| Subtitle | `[UIFont systemFontOfSize:13 + retinaPixel]` i.e. **13.5pt**, colour `#888888`, highlighted `#ffffff` |
| Small caption font | `[UIFont systemFontOfSize:11]` |

Source: `Telegraph/Telegraph/TGContactCell.m:299` and the initialiser around `:325`.

Companion plates that exist in the original for other heights: `Cell88` (2×88 → 44pt),
`CellHighlighted88`, `Cell96_Light`, `CellHighlighted96`. Only `Cell102` /
`CellHighlighted102` are bundled with us. **A new list row is 44pt or 51pt; do not invent a third
height.**

### 3.2 `DialogListCell` — the 73pt chat-list row

| | |
| --- | --- |
| Normal | `DialogListCell.png`, 4×146 @2x → 2×73 pt, **left cap `1`, top cap `0`** |
| Pressed | `DialogListCellHighlighted.png`, same size and caps |
| Search variant | `DialogListSearchCell.png` / `…Highlighted` (4×102 @2x → 51pt) |
| Row height | **`73`** (`TGDialogListController.mm:1123`); search results `51` when scope 0, `73` otherwise |
| `selectedBackgroundView` frame | `CGRectMake(0, -1, w, h + 1)` — it deliberately overhangs one point upward to swallow the previous row's hairline. Any new plated cell must do the same. |

Content metrics (`TGDialogListCell.m`), all in points from the row's left edge:

| Element | Frame / value |
| --- | --- |
| Avatar | `(8, 8, 56, 56)` |
| Text column origin | `x = 73` |
| Text view | `(73, 6, width − 73, 58)` |
| Title | y `6`, height `20`, `boldSystemFontOfSize:16`, colour `#111111` (`#229a0a` for secret chats) |
| Author name (group) | `(73, 29, width − 73 − 10 − rightPadding, 20)`, `boldSystemFontOfSize:14`, colour `#345f8f` |
| Message preview | `(73, 29, …, 40)`, `systemFontOfSize:14`, colour `#888888`; action/media text `#536c8c` |
| Date | right-aligned, `x = width − dateWidth − 9`, y `9`, height `15`, `systemFontOfSize:13` (bold 13 for the "today" form, 11 for the am/pm suffix), colour `#337acc` |
| Delivered tick | `(dateX − 15, 11 + 0.5, 13, 11)` |
| Read ticks | `(dateX − 20, 11 + 0.5, 18, 11)` |
| Pending clock | `(dateX − 16, 11, 12, 12)` |
| Base right padding | `16`; `+= badgeWidth + 7` when a badge shows; `+= 26 + 7` when the error badge shows |
| Group icon inset | `+21` to the title x; secret-chat lock inset `+15`; mute icon costs `12` |
| Editing shift | date moves `−32` in x while editing |

Unread-count colours: label white, `boldSystemFontOfSize:14`, normal shadow `#8091a6` at `(0,-1)`,
highlighted text `#2371c2` with a clear shadow.

---

## 4. Group button bars (`TGButtonGroupView`)

Source: `TelegraphKit/TelegraphKit/TGButtonGroupView.m`.

| Slot | Asset | Highlighted | Left cap | Size @2x |
| --- | --- | --- | --- | --- |
| Left | `ButtonGroupLeft.png` | `ButtonGroupLeft_Highlighted.png` | `8` | 17×60 |
| Middle | `ButtonGroupCenter.png` | `ButtonGroupCenter_Highlighted.png` | `1` | 10×60 |
| Right | `ButtonGroupRight.png` | `ButtonGroupRight_Highlighted.png` | `1` | 17×60 |
| Divider | `ButtonGroupDivider.png` | `ButtonGroupDivider_LeftHighlighted.png`, `ButtonGroupDivider_RightHighlighted.png` | `6` | 4×60 |

- Height `30` portrait / `25` landscape, same as a toolbar button (asset is 60 @2x = 30 pt).
- Nominal button width `80`; divider width `2` (`separatorWidth` from the asset). Total width for
  *n* buttons = `80n + 2(n − 1)`.
- On layout, each button gets `(frameWidth − 2(n−1)) / n` truncated to int; the last button
  absorbs the remainder so the group always ends flush.
- Text: `boldSystemFontOfSize:12`, white, shadow `rgba(0x0e284d,0.4)` at `(0,-1)`.
- The divider is three stacked image views (normal, left-highlighted, right-highlighted) crossfaded
  by alpha — never swap the image, fade it, so a press lights the correct half of the seam.
- Buttons fire on `UIControlEventTouchDown`, not touch-up. Segmented bars in this idiom respond
  instantly.

---

## 5. Grouped (settings/profile) chrome

- Grouped rows use the plate set `GroupedCellTop / GroupedCellMiddle / GroupedCellBottom /
  GroupedCellSingle` plus a `_Selected` twin each. `GroupedCellBottom` is 58×88 @2x → 29×44 pt, so
  **a grouped settings row is 44pt** and the bottom plate carries the extra rounded skirt.
- Position is declared, not inferred: `TGGroupedCellPositionFirst = 1`, `…Last = 2`, `0` for a
  middle row, `First|Last` for a lone row (`TGGroupedCell.h`).
- `extendSelectedBackground` is `true` for every row **except** a lone `First|Last` row. When true,
  the selected background grows `+1pt` in height for `position == 0` and for `position == First`
  (`extendBackgroundSize()` in `TGGroupedCell.m`), and the cell is raised to the top of the table's
  subview order on highlight so its plate covers its neighbours' edges.
- Vertical split rows (two values side by side) use `GroupedCellVerticalSeparator.png` /
  `GroupedCellVerticalSeparator_Highlighted.png` (`TGPhoneItemCell.m:111`).
- Action rows inside a group use `GroupedActionButton.png` (48×86 @2x → 24×43 pt) with
  `GroupedActionButton_Highlighted.png`; the affirmative/green form is
  `GroupedActionButtonGreen.png` (66×86 @2x → 33×43 pt) with `…Green_Highlighted.png`. Left cap:
  half the width (`24` and `33` respectively — the asset is symmetric, no flat middle). Height
  **43pt**. A green action button may carry a leading glyph, e.g. `GreenButtonLockIcon.png` set as
  the row's `titleIcon` (`TGProfileController.m:2054`).

Profile header metrics for reference (`TGProfileController.m:704`): header container height `86`,
avatar `(9, 14, 70, 70)`, name `(94, 24, w − 94 − 9, 24)` in `boldSystemFontOfSize:19`, status
`(94, 52, …, 24)` in `systemFontOfSize:14`. Edit mode swaps in two 44pt-tall name fields at
`x = 90`, text inset `15`, `boldSystemFontOfSize:16`.

---

## 6. Footers and dividers

| Asset | Size @2x | Points | Use |
| --- | --- | --- | --- |
| `Footer.png` | 2×88 | 1×44 | The plate under the last row of a plain list — a 44pt tall closing slice. Stretch horizontally with cap `1`, top cap `0`. |
| `CategoryDivider.png` | 2×52 | 1×26 | The 26pt section separator between groups of rows in a plain (non-grouped) list. |
| `CategoryDividerFirst.png` | 2×52 | 1×26 | The same divider used **above the first** section, which has a different top edge. Use it for index 0 only. |
| `ShadowDivider.png` | — | — | The soft shadow strip under a bar. |
| `LoginInputDivider.png` | — | — | Hairline between stacked text fields. |

Rules:

- A section header in a plain list is a `26pt` `UIImageView` carrying `CategoryDivider`, with a
  label drawn over it. It is **not** a `UITableView` header title; do not use
  `titleForHeaderInSection:` with default styling.
- A list that ends before the bottom of the screen is closed with a `Footer` image view, not with
  empty space.
- Hairlines are part of the plate PNGs. Never add a `0.5pt` `UIView` separator on top of a plated
  cell — you will get a double line.

---

## 7. Badges

| Badge | Asset | Size @2x | Caps | Metrics |
| --- | --- | --- | --- | --- |
| Chat-list unread | `DialogListUnreadBadge.png` (+`_Highlighted`) | 54×42 → 27×21 pt | **left `width/2` = 13, top `height/2` = 10** (the one badge stretched in both axes) | frame `(rowWidth − 28 − w, 29, w, 21)` where `w = MAX(27, textWidth + 10)`; label bold 14 white, shadow `#8091a6` `(0,-1)`, highlighted text `#2371c2` on a clear shadow |
| Contact-list badge | `ContactListBadge.png` | 52×42 → 26×21 pt | `width/2`, `height/2` | same layout rules |
| Delivery error | `DialogErrorBadge.png` (+`_Highlighted`) | 52×40 → 26×20 pt | **none — drawn unstretched** | fixed frame `(rowWidth − 28 − 26, 29, 26, 20)` |
| Tab-bar unread | `TabBarBadge.png` | 40×40 → 20×20 pt | left cap `10`, top cap `0` | width `MAX(20, textWidth + 12 + 1)`, right-aligned in its container; label `(6.5 + x, 4.5, 28.5, 10)`, `boldSystemFontOfSize:11`, white, no shadow |
| Conversation unread line | `ConversationUnreadBadge.png` | 50×50 → 25×25 pt | `width/2`, `height/2` | in-chat "unread" pill |
| Picker count | `ImagePickerCountBadge.png` | — | `width/2` | selection counter over a thumbnail |

Count text formatting (from `TGMainTabsController.m`): `< 1000` → plain number; `< 1000000` →
`%dK`; otherwise `%dM`. Use exactly this everywhere a count is shown in chrome.

---

## 8. Menus, action bars, and the rest of the chrome family

For completeness, because new features keep needing one of these:

| Control | Assets | Caps | Height |
| --- | --- | --- | --- |
| Action sheet buttons (ours) | `MenuButtonLeft/Center/Right` (+`_Highlighted`) 20/4/20 × 82 @2x | left `10 / 1 / 1` | 41pt |
| Action sheet destructive | `MenuRedButton.png` (+`_Highlighted`) 50×90 @2x | `width/2` = 12 | 45pt |
| Action sheet seam | `MenuButtonSeparator.png` 4×72 @2x | `1` | 36pt |
| Menu callout arrows | `MenuArrowTop/Bottom` (+`_Highlighted`) | none | as-is |
| Original action menu | `ActionMenuButtonLeft/Middle/Right` 46/178/46 × 118 @2x, `ActionMenuDivider` 8×118 | left `11 / 1 / 1`, divider `2` | 59pt |
| Bar background | `NavBarBackground.png` 88×88 @2x | left `1`, top `0` | 44pt |
| Tab bar | `TabBarBackground.png`, selection `TabBarSelected.png` (stretch `width/2`) | — | 49pt |
| List delete button | `ListDeleteButton.png` 36×60 @2x (+`_Highlighted`) | `width/2` = 9 | 30pt; label `boldSystemFontOfSize:13`, white, shadow `rgba(0xa30f0a,0.2)` at `(0,-1)` |
| Swipe-to-delete shadow | `DialogListDeleteShadow.png` | left cap `width − 1` | 71pt tall, 90pt wide, x starts at row width |

Swipe-delete geometry from `TGDialogListCell.m`: the delete button is `61 × 31` at
`(width − 10 − 61, 20)`; the editing minus switch is a `30 × 30` button parked at `x = −35`, its
glyph centred at `(15, 14)`.

---

## 9. Assets we have, assets we lack

Present in `iTgLegacy/images/`: `HeaderButton`, `HeaderButton_Pressed`, `HeaderButton_Login_Blue(+_Pressed)`,
`BackButton(+_Pressed)`, `Cell102`, `CellHighlighted102`, `DialogListCell(+Highlighted)`,
`ButtonGroup*` (all seven), `GroupedActionButton(+_Highlighted)`, `GroupedActionButtonGreen(+_Highlighted)`,
`Footer`, `CategoryDivider`, `CategoryDividerFirst`, `LoginInputDivider`,
`DialogListUnreadBadge(+_Highlighted)`, `TabBarBadge`, `NavBarBackground`, `TabBarBackground`,
`TabBarSelected`, `MenuButton*`, `MenuRedButton`.

**Missing** from our bundle, so do not reference them: `HeaderButton_Blue`, any `_Landscape`
variant, `Header_Button_Delete`, `Cell88`, `Cell96_Light`, `DialogListSearchCell`,
`ContactListCell`, `ContactListBadge`, `DialogErrorBadge`, `ConversationUnreadBadge`,
`GroupedCellTop/Middle/Bottom/Single`, `GroupedCellVerticalSeparator`, `ShadowDivider`,
`ActionMenuButton*`.

Substitution rulings when an asset is missing:

- **Blue Done button** → use `HeaderButton_Login_Blue` with cap `width/2`. It is the same gloss.
- **Landscape** → reuse the portrait asset at height `25`. The 4S at 480×320 is rare enough that a
  slightly tall gloss beats a missing button. Do not draw a substitute gradient.
- **Grouped cell plates** → use `[TGTheme styleCell:]` plus `Cell102`/`CellHighlighted102` clipped
  to a 44pt row. Do not hand-roll rounded rects.
- **Delete bar button** → `TGToolbarButton` Generic plate with red 12pt bold text is *not*
  acceptable; use a `MenuRedButton`-plated button at 30pt height with cap `12`.
- **Error badge** → draw `DialogListUnreadBadge` tinted is *not* acceptable (the shape differs).
  Use a 26×20 red rounded rect drawn in code with the same corner radius as the unread badge
  (10pt) and a white `!` in `boldSystemFontOfSize:14`.

---

## 10. Rendering modern concepts in this idiom

These features did not exist in 2013. The rulings below are law so that a hundred separate screens
converge. Each one reuses an existing asset — **inventing a new PNG is forbidden**; if the idiom
truly has no plate for it, draw it in code following the metrics given.

**Reactions.** A reaction row under a message is a **group button bar**: `ButtonGroupLeft /
Center / Right` at height `30`, one segment per reaction, divider `ButtonGroupDivider` (cap `6`)
between segments. Segment content is the emoji at `16pt` plus the count in
`boldSystemFontOfSize:12` white with the standard `rgba(0x0e284d,0.4)` `(0,-1)` shadow, gap `4`,
padding `7/7`. The reaction *you* picked renders permanently in its `_Highlighted` image. Minimum
segment width `44`. The bar sits `4pt` below the bubble, left-aligned with it. Do not draw pills.

**Reply header inside a bubble.** A `2pt`-wide vertical bar in the bubble's own accent colour, full
height of the quote block, with `6pt` gap to the text. Author line
`boldSystemFontOfSize:14`, quote line `systemFontOfSize:14` at 70% alpha. Block height `34`,
inset `8` from the bubble's content edges. No plate, no rounded corner.

**"Swipe to reply" affordance / message actions.** Reuse the swipe-delete geometry from §8:
a `61 × 31` plated button, `ListDeleteButton` art for destructive actions, `GroupedActionButton`
art (cap `24`, height `43` clipped to `31`) for neutral ones.

**Stickers.** A sticker is a bare transparent image with **no bubble and no plate**, max side
`128pt`, with the time stamp drawn on a `ConversationDateOverlay`-style plate in the bottom-right,
inset `4`. The sticker picker's tab strip is a group button bar (§4) at height `30`; its grid rows
are plain `Cell102` plates cut to `4` columns at `72pt` cells with `CategoryDivider` between packs.

**Premium / verified / scam badges.** These are **badges**, not icons: `DialogListUnreadBadge`
(caps `13/10`, height `21`) carrying the word in `boldSystemFontOfSize:11` white, shadow `#8091a6`
`(0,-1)`. Placed `3pt` after the title, vertically centred to it — the same slot the mute icon uses
(`titleX + titleWidth + 3, titleY + 6`). A verified mark shows `✓`; premium shows `★`. Never a
gradient, never a colour outside the badge asset.

**Folders / chat filters.** The folder switcher is a group button bar (§4) pinned directly under
the navigation bar, height `30`, full screen width, one segment per folder, selected segment held in
its `_Highlighted` image, unread counts appended as `(12)` inside the segment label rather than as a
separate badge. A folder with more than four entries scrolls horizontally inside the same bar art;
it does not become a menu.

**Media grid (shared media, sticker/GIF grids).** No `UICollectionView` — it is unavailable. Build a
`UITableView` of plated rows: each row is a `Cell102`-style plate, height `78` (`72pt` tile + `3`
top + `3` bottom), holding four `72 × 72` tiles at x `2, 78, 154, 230` on a 320pt screen (gap `4`).
Section headers use `CategoryDivider` (`CategoryDividerFirst` for the first) at height `26`.
Selection lights the plate's `_Highlighted` twin, never an overlay tint.

**Video/voice/round-message controls, poll options, QR result actions, and anything else
button-shaped in the content area.** Default to `GroupedActionButton` (neutral, cap `24`,
height `43`) or `GroupedActionButtonGreen` (affirmative, cap `33`, height `43`), text
`boldSystemFontOfSize:14` white with the standard `(0,-1)` shadow. Destructive uses `MenuRedButton`
(cap `12`, height `45`).

**New bar actions of any kind** go through `+[TGIcons headerButtonWithTitle:bold:target:action:]`
for text and through a `TGToolbarButtonTypeImage`-equivalent (bare `UIButton`, no background image,
icon from `TGIcons`) for glyphs. There is exactly one plate for a bar text button and it is
`HeaderButton`.

---

## 11. Where the original genuinely has no answer

- **`Header_Button_Delete.png` is referenced by `TGToolbarButton.m` but is not present in the 2014
  resource dump**, and no pressed/landscape twin ever existed. §9 supplies the substitute.
- `Cell102`, `Cell88`, `Footer`, `CategoryDivider`, `GroupedCell*` and `GroupedActionButton*` are
  bundled by the original project but only `Cell102` and the `GroupedCellVerticalSeparator` are
  loaded from code we can read; the rest were wired through nibs that are not in the dump. Their
  heights above are measured from the PNGs, and the usage rules are our ruling, not a quotation.
- Back-button title truncation width is not a constant anywhere in the original; the 90pt figure
  in §2 is ours.
- Nothing in the original covers reactions, replies-as-quotes, folders, premium marks, or media
  grids. §10 is entirely prescriptive.

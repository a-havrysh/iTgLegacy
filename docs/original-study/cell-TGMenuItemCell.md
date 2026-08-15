# TGMenuItemCell — the 2013 settings-row cell family

## 0. Naming: the class does not exist

There is no class named `TGMenuItemCell` anywhere in the original source. Confirmed by listing
`Telegraph/Telegraph/` and `TelegraphKit/TelegraphKit/` — the files present are
`TGActionMenuItemCell`, `TGVariantMenuItemCell`, `TGButtonMenuItemCell`, `TGUserMenuItemCell`,
`TGWallpapersMenuItemCell`, plus three cells that are named `…View` instead of `…Cell`
(`TGLabelMenuItemView`, `TGCommentMenuItemView`, `TGInputMenuItemView`, `TGButtonsMenuItemView`)
but are all `UITableViewCell` subclasses.

What actually exists is a **family**, and the family is the real component:

- a model layer, `TGMenuItem` (`Telegraph/Telegraph/TGMenuItem.h:11-17`) with subclasses per row kind;
- a shared cell superclass, `TGGroupedCell` (`Telegraph/Telegraph/TGGroupedCell.h:16-20`), which owns
  the rounded-group background behaviour;
- one concrete cell per model type.

This document treats the family as the component, and goes deepest on the two rows that carry the
bulk of the settings UI: `TGActionMenuItemCell` (title + chevron, or title + checkmark) and
`TGVariantMenuItemCell` (title + right-hand value + chevron). Everything a reader needs to rebuild
the settings list correctly is here.

Paths below are relative to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/`
unless stated otherwise.

---

## 1. What the component is for

iOS 6 had no `UITableViewStyleGrouped` look that Telegram was willing to accept, so 2013 Telegram
drew its own. Every settings-like screen (`TGChatSettingsController`, `TGNotificationSettingsController`,
`TGPrivacySettingsController`, `TGProfileController`, `TGSettingsController`, the small picker
controllers `TGTextFontController`, `TGPhoneLabelController`, `TGCustomNotificationController`)
builds an array of `TGMenuSection` objects, each holding an array of `TGMenuItem` subclasses, and a
single `cellForRowAtIndexPath:` switch turns each item type into its cell. The cell is deliberately
dumb: it holds labels and image views and nothing else. All state, all actions and all layout
decisions about *position within the group* live in the controller.

The controllers are, notably, **not** subclasses of `TGListMenuController` — that class exists
(`TGListMenuController.h:13-19`) but its only interesting method returns `nil`
(`TGListMenuController.m:44-47`). It is dead scaffolding. Do not port it.

---

## 2. Model layer

`TGMenuItem` (`TGMenuItem.h:11-17`) is four lines of substance: an `int type` and an `int tag`.
The type is a magic constant defined next to each subclass, e.g.
`TGVariantMenuItemType = 0xF419EA88` (`TGVariantMenuItem.h:11`),
`TGActionMenuItemType = 0xD8B4CD4C` (`TGActionMenuItem.h:11`),
`TGButtonMenuItemType = 0x8D6839FC` (`TGButtonMenuItem.h:11`),
`TGCommentMenuItemType = 0x68CFA5DE` (`TGCommentMenuItem.h:11`),
`TGLabelMenuItemType = 0x1014A51A` (`TGLabelMenuItem.h:11`, duplicated on line 12 — a harmless
copy-paste in the original).

`tag` is the lookup key: controllers find a live row by walking the section list comparing
`item.tag` (`TGChatSettingsController.m` `findMenuItem:sectionIndex:itemIndex:`, the method at the
end of the file, lines ~575-600 of the file). This is how a value gets refreshed after returning
from a sub-screen: update the model, then, *if the cell is currently on screen*, poke the cell
directly — see `TGChatSettingsController.m:166-174`, which sets `variantItem.variant` to the new
`"%dpt"` string and then casts `cellForRowAtIndexPath:` to `TGVariantMenuItemCell` and assigns
`.variant`. Nothing reloads the table. This matters: **the original never calls `reloadData` for a
single value change**, it mutates the model and mutates the visible cell.

The item subclasses:

| Class | Payload | File |
|---|---|---|
| `TGActionMenuItem` | `title`, `SEL action` | `TGActionMenuItem.h:13-19` |
| `TGVariantMenuItem` | `title`, `variant`, `variantImage`, `SEL action` | `TGVariantMenuItem.h:13-19` |
| `TGButtonMenuItem` | `title`, `subtype`, `SEL action`, `enabled`, `titleIcon` | `TGButtonMenuItem.h:19-27` |
| `TGCommentMenuItem` | `comment`, `-heightForWidth:` | `TGCommentMenuItem.h:13-19` |
| `TGLabelMenuItem` | `title`, `label`, `color` | `TGLabelMenuItem.h:14-20` |

`TGMenuSection` (`TGMenuSection.h:17-23`) is a `tag`, a `title` and a mutable `items` array,
allocated in `init` (`TGMenuSection.m:14`).

Actions are plain selectors performed on the controller: the switch-item / button-item path goes
through `ASWatcher` and ends in `[self performSelector:buttonItem.action]`
(`TGChatSettingsController.m`, `actionStageActionRequested:options:`, the `buttonItemPressed`
branch). Row taps for action/variant items are handled in the controller's `didSelectRowAtIndexPath:`.

---

## 3. `TGGroupedCell` — the shared superclass

`TGGroupedCell.h:11-20` declares `TGGroupedCellPositionFirst = 1`, `TGGroupedCellPositionLast = 2`
(a bit mask; a single-row group is `First | Last`, and a middle row is plain `0`), plus
`extendSelectedBackground` and `groupedCellPosition`.

In `init` it sets `self.backgroundColor = nil; self.opaque = false;` (`TGGroupedCell.m:27-28`) —
the artwork behind the row is the `backgroundView` image, and the cell itself must not paint.

The clever part is the selection artwork. `extendBackgroundSize` (`TGGroupedCell.m:3-15`) adds
**1 point** of height to the selected background when the position is `0` (middle) or
`TGGroupedCellPositionFirst`. Reason: the group artwork draws a hairline separator at the bottom of
each non-last row, and without the extra point the highlighted row would show an unhighlighted
1pt gap against the row below. `TGGroupedCellPositionLast` and `First|Last` get no extension because
their artwork ends in the rounded bottom edge.

`setSelected:animated:` and `setHighlighted:animated:` (`TGGroupedCell.m:33-65`) both reset the
selected background to `origin.y = 0`, `height = self.frame.size.height`, apply the extension, and
then call `adjustOrdering`. `layoutSubviews` (`TGGroupedCell.m:114-124`) repeats the frame fix but
*not* the reordering.

`adjustOrdering` (`TGGroupedCell.m:87-112`) is the subtle one: it walks the table view's subviews,
finds the index of the last `UITableViewCell`, and if `self` sits below it, re-inserts `self` at
that index. That is, **the highlighted row is pulled to the front of the z-order**, so its extended
1pt of selection artwork paints over the neighbouring cell instead of under it. Skip this and the
highlight will look clipped on the bottom edge of first/middle rows. This is a real, visible
behaviour, not defensive code.

### The nine background images

Assigned by the controller, never by the cell. From `TGChatSettingsController.m:486-520` (the
`if (!clearBackground)` block):

| Position | normal | highlighted |
|---|---|---|
| `First\|Last` | `[TGInterfaceAssets groupedCellSingle]` | `groupedCellSingleHighlighted` |
| `First` | `groupedCellTop` | `groupedCellTopHighlighted` |
| `Last` | `groupedCellBottom` | `groupedCellBottomHighlighted` |
| middle (`0`) | `groupedCellMiddle` | `groupedCellMiddleHighlighted` |

`extendSelectedBackground` is `false` only for `First|Last`; `true` in the other three cases
(`TGChatSettingsController.m:491, 499, 507, 515`).

Asset resolution (`TGInterfaceAssets.mm:635-723`):

- Normal states use the `TGStretchableImageInCenterWithName` macro on `GroupedCellTop.png`,
  `GroupedCellMiddle.png`, `GroupedCellBottom.png`, `GroupedCellSingle.png` — centre-stretched.
- Highlighted states prefer `resizableImageWithCapInsets:` with insets
  `UIEdgeInsetsMake(5, 13, 6, width - 13 - 1)` when available (iOS 5+), falling back to
  `stretchableImageWithLeftCapWidth:topCapHeight:`. Note the asymmetry: **top cap 5, bottom cap 6,
  left cap 13**, and a right cap that leaves a 1px stretchable column.
  `groupedCellBottomHighlighted` (`TGInterfaceAssets.mm:689-701`) has its modern branch disabled
  with `if (false && …)` and always takes the legacy path with
  `leftCapWidth = width/2, topCapHeight = 1` — a deliberate override, not dead code, and worth
  reproducing if the bottom-row highlight looks wrong.

Artwork ships **@2x only** — `Resources/` contains `GroupedCellTop@2x.png`,
`GroupedCellMiddle@2x.png`, `GroupedCellBottom@2x.png`, `GroupedCellSingle@2x.png`, each with a
`_Selected@2x` companion, plus `GroupedCellVerticalSeparator@2x.png` and its
`_Highlighted@2x`. There is no 1x set; the app was Retina-only in practice.
`GroupedCellSingle@2x.png` measures 52×88 px, i.e. **26×44 pt** — the artwork is authored for the
44pt row and stretches only in the centre.

---

## 4. `TGActionMenuItemCell` — title, chevron, optional checkmark

Header: `TGActionMenuItemCell.h:13-21`. Public surface is `forcePaddings`, `title`,
`-setHideDisclosureIndicator:`, `-setHideCheckIndicator:`.

### Metrics (`TGActionMenuItemCell.m:25-45`)

- Title label frame `(11, 12, contentWidth - 30, 20)`, `UIViewContentModeLeft`,
  `autoresizingMask = FlexibleWidth`.
- Font `boldSystemFontOfSize:17` (line 33). The 20pt label height and the 12pt top origin are sized
  around that font inside a 44pt row: 12 + 20 = 32, leaving 12 below — visually centred.
- `backgroundColor = [UIColor whiteColor]` (line 34). This is **not** a mistake: the label is opaque
  white so the text renders without blending against the group artwork, which is white in the
  middle. It means the label rectangle punches a white box; that is fine because the artwork behind
  it is white there, and it is why the label is only 20pt tall rather than filling the row.
- `textColor` black, `highlightedTextColor` white (lines 35-36) — on highlight the whole row goes
  blue via the `_Selected` artwork and the text inverts.
- Disclosure chevron: `UIImageView` built from
  `[TGInterfaceAssets groupedCellDisclosureArrow]` / `…Highlighted`, i.e.
  `MenuDisclosureIndicator.png` / `MenuDisclosureIndicator_Highlighted.png`
  (`TGInterfaceAssets.mm:725-739`). `MenuDisclosureIndicator@2x.png` is 18×32 px = **9×16 pt**.
  Positioned by offsetting its natural frame to
  `x = contentWidth - imageWidth - 11`, `y = 14` (`TGActionMenuItemCell.m:41`), with
  `autoresizingMask = FlexibleLeftMargin`. So: right margin 11pt, top 14pt — 14 + 16 = 30 in a 44pt
  row, i.e. the chevron sits 1pt above true centre. That 1pt is in the original; keep it.

### Checkmark state (`TGActionMenuItemCell.m:58-79`)

`setHideCheckIndicator:false` lazily builds a `UIImageView` from `ListCheck.png` /
`ListCheck_Highlighted.png` (`ListCheck@2x.png` is 26×28 px = **13×14 pt**), placed at
`x = contentWidth - imageWidth - 9`, `y = 14` — note the right margin here is **9**, not the
chevron's 11 — and, crucially, **recolours the title to `UIColorRGB(0x516691)`** (line 77).
Hiding the check restores black (line 64). Selection in a picker list is therefore signalled twice:
a blue-grey title plus the tick.

The check view is created lazily and only ever hidden, never removed, which is reuse-safe as long as
the controller sets the state on every `cellForRow`. Every picker does exactly that:
`TGTextFontController.m:131-132` calls `setHideDisclosureIndicator:true` then
`setHideCheckIndicator:indexPath.row != _selectedIndex` unconditionally on each pass. Same shape in
`TGPhoneLabelController.m:165-166` and `TGCustomNotificationController.m:164-165`.

> Reuse trap the original avoids by convention, not by code: `TGActionMenuItemCell` has **no
> `prepareForReuse`**. A screen that shows both chevron rows and check rows in the same reuse
> identifier must set *both* flags on every row, or a recycled cell keeps the previous row's
> accessory and, worse, its blue-grey title colour.

### Tap behaviour in pickers (`TGTextFontController.m:177-192`)

`didSelectRowAtIndexPath:` deselects animated, then — if the index actually changed — clears the
check on the old cell, updates `_selectedIndex`, and sets the check on the new cell, both via
`cellForRowAtIndexPath:` (nil-checked, so off-screen rows just pick it up on next dequeue). No
`reloadRowsAtIndexPaths:`, no animation. The tick moves instantly while the blue highlight fades out.

### `forcePaddings` (`TGActionMenuItemCell.m:81-102`)

Only one caller: `TGWallpaperStoreController.m:363`. When set, `layoutSubviews` re-lays the title to
`(11, 14, contentWidth - 30, 20)` (2pt lower), moves the chevron to `y = 16`, and then insets the
content view, `backgroundView` and `selectedBackgroundView` to `origin.x = 9`,
`width = self.frame.size.width - 18`. In other words, in that one screen the table is full-bleed and
the cell manufactures the 9pt side gutter itself. Elsewhere the table view supplies the gutter.

---

## 5. `TGVariantMenuItemCell` — title, right-hand value, chevron

Header: `TGVariantMenuItemCell.h:13-19`: `title`, `variant`, `-setVariantImage:`.

Metrics (`TGVariantMenuItemCell.m:17-48`):

- `retinaPixel = TGIsRetina() ? 0.5f : 0.0f` (line 22) — used only to nudge the variant label down
  half a point on Retina so its 16pt baseline aligns with the 17pt bold title's.
- Title label `(11, 12, contentWidth - 28, 20)`, `boldSystemFontOfSize:17`, opaque white
  background, black text, white highlighted text (lines 24-30). Note the width allowance is
  `- 28` here versus `- 30` in the action cell; a 2pt inconsistency in the original.
- Variant label `(contentWidth - 200 - 11 - 14, 11 + retinaPixel, 200, 20)`,
  `textAlignment = Right`, `font = systemFontOfSize:16`, `backgroundColor = clearColor`,
  `textColor = UIColorRGB(0x356596)`, highlighted white (lines 32-40). So the value column is a
  fixed 200pt wide right-aligned box whose right edge sits 25pt from the content edge
  (11 for the chevron margin + 14 to clear the chevron itself).
- Chevron: same asset and same `contentWidth - width - 11`, `y = 14` placement as the action cell
  (lines 42-45). It is a local variable, never stored — this cell can never hide its chevron.

### The two failure modes with real data

1. **Long title.** The title label is a single line with the default truncation and is
   `contentWidth - 28` wide — it does **not** stop at the variant column. A long title will run
   under and behind the right-aligned value. The value label has a clear background, so on a real
   device you get overlapping text, not a clean truncation. The original simply never shipped a
   title long enough to hit it (the strings are "Message Font Size", "Sound", "Auto-Download Media").
   If our port has longer strings, this is a case the original does not answer and we must decide.
2. **Long variant.** Right-aligned in a fixed 200pt box, so it truncates on the *left*… no: with
   default `UILineBreakModeTailTruncation` it truncates at the tail while remaining right-aligned,
   meaning the ellipsis lands at the right edge next to the chevron. Values in practice are short
   ("14pt", "Default", a language name).
3. **Empty / nil variant.** Nothing special happens — the label simply has no text. The cell still
   shows the chevron. There is no fallback string.

### `setVariantImage:` (`TGVariantMenuItemCell.m:64-82`)

Used to show a colour swatch or flag instead of text. It hides the text label when an image is set
(line 66), lazily creates the image view with `FlexibleLeftMargin`, toggles visibility, and frames
the image at `x = contentWidth - 30 - imageWidth`, vertically centred with `floorf`.
Note **30**, not 25 — the image column is 5pt further from the chevron than the text column.

There is a latent bug worth knowing about before copying: line 66 reads
`_variantLabel.hidden = image != nil;` and executes *before* the nil check, while
`_variantImageView.hidden = image == nil;` is set after creation. Passing `nil` correctly restores
the text label, so the behaviour is right, but the method always allocates the image view even when
called with `nil` on a cell that never shows images.

---

## 6. The other family members, briefly

**`TGCommentMenuItemView`** (`TGCommentMenuItemView.m`) — the grey explanatory paragraph under a
group. Label at `(1, 7, contentWidth - 2, contentHeight - 14)`, flexible width and height,
centre-aligned, `numberOfLines = 0`, word wrap. Font `systemFontOfSize:14` (lines 13-22 — the
ternary on `TGIsRetina()` yields 14 either way). Text `UIColorRGB(0x697487)` with a **shadow**
`UIColorRGB(0xdae0e8)` at offset `(0, 1)` (lines 38-40), the classic engraved-on-linen look; the
same colour pair is used for section header labels (`TGChatSettingsController.m:196-198`).
Cell is transparent (`backgroundColor = nil; opaque = false`).
Height comes from the model: `TGCommentMenuItem.m:42` computes
`sizeWithFont:constrainedToSize:CGSizeMake(width - 12*2, 1000)` **+ 7*2**, cached per width and
invalidated whenever `comment` is set (`TGCommentMenuItem.m:29-35`). So: 12pt horizontal inset for
measurement, 7pt vertical padding top and bottom.

Comment rows also act as **group separators**: in `cellForRowAtIndexPath:` a row is treated as
first-in-section if the previous item is a comment, and last-in-section if the next one is
(`TGChatSettingsController.m:296-310`). A comment in the middle of a section therefore splits the
rounded artwork into two visually distinct groups without needing two sections. That is a genuinely
useful trick and easy to miss.

**`TGLabelMenuItemView`** (`TGLabelMenuItemView.m`) — read-only "Phone: +1 234" rows.
Title `(11, 12, 96, 20)` `boldSystemFontOfSize:16`; value `systemFontOfSize:17`,
`UIColorRGB(0x516691)`. With a title present the value starts at `11 + 96 + 2 = 109` and is
`contentWidth - 24 - 96 - 2` wide; with `title == nil` the title view is hidden and the value takes
the full `(11, 12, contentWidth - 24, 20)` (lines 48-63). `setColor:nil` restores `0x516691`
(line 73). This is the component's documented nil-handling, and it is the only one in the family
that reflows on missing content.

**`TGButtonMenuItemCell`** (`TGButtonMenuItemCell.m`) — full-width capsule buttons ("Log Out",
"Delete Contact"). Not a `TGGroupedCell`; it is a bare `UITableViewCell` with a `UIButton` at
`(9, 0, width - 18, 45)`, `boldSystemFontOfSize:17`, `exclusiveTouch` (lines 29-37). Row height 45
(`TGChatSettingsController.m:268-269`). Three subtypes (`TGButtonMenuItem.h:13-17`):

- Red: `menuButtonBackgroundRed`/`…Highlighted`, white title, shadow `0xa10603` @ 0.5 alpha, offset `(0, -1)`.
- Gray: `menuButtonBackgroundGray`, title `0x4a6587` normal / white highlighted, shadow white @ 0.45, offset `(0, +1)`.
- Green: `GroupedActionButtonGreen.png` stretched at half width, white title, shadow `0x124606` @ 0.3, offset `(0, -1)`.

(`TGButtonMenuItemCell.m:72-121`.) Disabled = `alpha 0.7` (line 127).
`clipsToBounds = false` on both the cell and `contentView.superview` (lines 26-27) plus a custom
`hitTest:` (139-150) exist because `updateFrame` (157-182) can push the button *outside* the cell:
for red and green buttons it pins the button to the bottom of the enclosing scroll view so
"Log Out" hangs at the bottom of the screen rather than after the last row. The screen-height
arithmetic there (`height - 20 - 32` vs `- 20 - 44`) is compensating for the in-call status bar.
If our port does not need a bottom-pinned destructive button, none of this is required.

---

## 7. Row heights, in one place

From `TGChatSettingsController.m:257-276`:

- action, switch, variant → **44**
- button → **45**
- comment → `[(TGCommentMenuItem *)item heightForWidth:_currentTableWidth]`

`_currentTableWidth` is refreshed in `viewWillAppear:` and in
`willRotateToInterfaceOrientation:duration:` from
`[TGViewController screenSizeForInterfaceOrientation:].width`
(`TGChatSettingsController.m:152-164`) — i.e. the comment height is recomputed for the *incoming*
orientation before the rotation animation, so multi-line footers do not jump.

Anything unrecognised returns **0**, not a default height.

---

## 8. Our port, judged

Our equivalent is not a cell class at all. `src/TGSettingsViewController.m` builds stock
`UITableViewCell`s in `tableView:cellForRowAtIndexPath:` (line 2472 onward) with reuse ids
`@"TGSettingsCell"` (`UITableViewCellStyleSubtitle`) and `@"TGSettingsRootRowCell"`
(`UITableViewCellStyleValue1`), then dispatches to a `fill…Cell:at:` method per page
(lines 2486-2534). The table is `UITableViewStyleGrouped`
(`src/TGSettingsViewController.m:154` and `:1076`). Row height 44, with 45 for logout/photo and 64
for suggestions (`src/TGSettingsViewController.m:2882-2891`).

What we got right, briefly: the 44pt row; `boldSystemFontOfSize:17` for the title
(`src/TGSettingsViewController.m:2502`, and `TGTheme.m:413`); the variant colour `0x356596` where
it is used explicitly (`src/TGSettingsViewController.m:2630, 2637, 2643`); a full reset of
accessory/­image/­detail state at the top of every dequeue
(`src/TGSettingsViewController.m:2495-2500`), which is the reuse discipline the original relied on
convention for; and reuse of the genuine `MenuDisclosureIndicator` and `ListCheck` artwork rather
than system chevrons (`src/TGSettingsViewController.m:1190-1236`).

Visible differences, each actionable:

1. **No grouped artwork.** We use `UITableViewStyleGrouped`'s own iOS 6 rounded rects; the original
   painted `GroupedCellTop/Middle/Bottom/Single(.._Selected)` into `backgroundView` /
   `selectedBackgroundView` per row position (`TGChatSettingsController.m:486-520`). We ship
   `GroupedCellTop@2x.png` and `GroupedCellBottom@2x.png` in `iTgLegacy/images/` but never reference
   them — `grep GroupedCell src/` returns nothing. The corner radius, the hairline separator colour
   and above all the *blue highlight* differ from the original as a result. Fix: port
   `TGGroupedCell` verbatim (it is 126 lines) and assign the four image pairs in
   `cellForRowAtIndexPath:`; we are missing `GroupedCellMiddle@2x.png`, `GroupedCellSingle@2x.png`
   and all four `_Selected@2x` files, which must be copied from
   `telegram_iphone.src/Telegraph/Telegraph/Resources/`.
2. **No `extendSelectedBackground` / `adjustOrdering`.** Consequence of (1). Once the artwork is in,
   the +1pt selection extension (`TGGroupedCell.m:3-15`) and the z-order pull
   (`TGGroupedCell.m:87-112`) are required or first/middle rows will show a 1pt unhighlighted seam.
3. **Value font is 15 or 16 depending on path.** `src/TGSettingsViewController.m:2503` sets
   `detailTextLabel.font = systemFontOfSize:15`, while `TGTheme.m:414` sets 16. The original is
   unambiguously **16** (`TGVariantMenuItemCell.m:36`). Remove the 15 at line 2503; whichever runs
   last currently wins by accident.
4. **Value colour is themed, not fixed.** `TGTheme.m:415` assigns `cellDetailColour`, which is
   `TG_SETTINGS_VALUE` or an imported accent (`TGTheme.m:302-305`), and several call sites override
   it to `secondaryTextColour` (`src/TGSettingsViewController.m:3028, 3055, 3144`). The original
   value colour is exactly `UIColorRGB(0x356596)` (`TGVariantMenuItemCell.m:38`) with no variation.
   Unless a row is deliberately non-interactive, it should be `0x356596`.
5. **The half-pixel Retina nudge is absent.** The original offsets the value label by
   `+0.5pt` on Retina (`TGVariantMenuItemCell.m:22, 32`) to align the 16pt regular baseline with the
   17pt bold title. With `UITableViewCellStyleValue1` we get UIKit's centring instead. On a 4S this
   is visible as a half-point baseline mismatch. Only fixable by taking layout into our own hands.
6. **Chevron placement.** `markDisclosure:` (`src/TGSettingsViewController.m:1214-1222`) hands the
   image view to `cell.accessoryView`, so UIKit centres it vertically and applies its own trailing
   margin. The original hard-codes `y = 14` and right margin 11 (`TGActionMenuItemCell.m:41`) —
   1pt above centre in a 44pt row. Small, but this is a systematic offset repeated on every settings
   row in the app.
7. **Checkmark does not recolour the title.** `markChecked:on:`
   (`src/TGSettingsViewController.m:1223-1236`) only swaps the accessory view. The original also
   sets the title to `UIColorRGB(0x516691)` when checked and back to black when unchecked
   (`TGActionMenuItemCell.m:64, 77`). Add that. Also note the original's check margin is **9**, not
   the chevron's 11 (`TGActionMenuItemCell.m:72`) — with `accessoryView` we get neither.
8. **Selection style.** We set `UITableViewCellSelectionStyleBlue`
   (`src/TGSettingsViewController.m:2500`), which is the iOS 6 system gradient. The original's
   highlight is the `_Selected` artwork, a different blue. Falls out of fixing (1).
9. **`highlightedTextColor` is never set.** The original sets it to white on every label
   (`TGActionMenuItemCell.m:36`, `TGVariantMenuItemCell.m:29, 39`). With `styleCell:`
   installing a custom `selectedBackgroundView` in themed mode (`TGTheme.m:424-427`), UIKit's
   automatic white-on-highlight can be lost; set it explicitly.
10. **Footer comments.** I found no equivalent of `TGCommentMenuItemView` in
    `src/TGSettingsViewController.m` — presumably section footers are stock. If so we lose the
    `0x697487` text on `0xdae0e8` shadow at offset `(0,1)` and the 14pt font
    (`TGCommentMenuItemView.m:19, 38-40`), which is a conspicuous part of the 2013 look, and we lose
    the split-a-section-with-a-comment trick from `TGChatSettingsController.m:296-310`.

Ambiguity I will not paper over: the original's title label has an **opaque white** background
(`TGActionMenuItemCell.m:34`, `TGVariantMenuItemCell.m:27`). That is correct against white group
artwork and wrong against any dark theme. Our port has a dark theme (`TGTheme.m:417-427`). The
original gives no guidance because it had no dark mode; if we port the labels literally, dark mode
will show white boxes behind every settings title. Use a clear background in themed mode and accept
the (negligible, on a 4S with our row counts) blending cost.

---

## 9. What became of it

### Telegram-iOS (modern)

The whole family collapsed into `ItemListUI`, one file per row kind:
`submodules/ItemListUI/Sources/Items/ItemListDisclosureItem.swift` is the direct descendant of
`TGActionMenuItemCell` + `TGVariantMenuItemCell` merged into a single item. The mapping is clean:

- The old `int type` magic constants became Swift types conforming to `ListViewItem`; the type-switch
  in each controller became the item's own `asyncLayout()` (line 330).
- `TGGroupedCellPosition` became `ItemListNeighbors`, passed into layout — same idea (a row knows
  whether it is first/last in its group), now computed by the framework rather than by hand in each
  controller's `cellForRow`.
- `variant` became `label` with a `ItemListDisclosureLabelStyle` enum (lines 32-42) covering
  `text`, `detailText`, `coloredText`, `textWithIcon`, `badge`, `color`, `image` — the original had
  exactly two of these (`variant` text and `variantImage`), and the growth is feature-driven:
  badges for unread counts, colour swatches for themes.
- `ItemListDisclosureStyle` (lines 25-29) has `arrow`, `optionArrows`, `none` — the original's
  `setHideDisclosureIndicator:` boolean, generalised.
- The chevron reserves `34.0 + params.rightInset` (line 348) versus the 2013 `11 + 9`; content inset
  is `16.0 + params.leftInset` (line 418) versus 11.
- **Height is computed, not constant.** `verticalInset * 2 + titleHeight (+ label)` (lines 548-556),
  with `verticalInset` selected by font size — 13 or 15 for normal sizes, and **11 in a `.legacy`
  branch** (lines 519-542). The 44pt row is gone because Dynamic Type made it impossible; the
  `.legacy` case is the vestige of the fixed-height world we are rebuilding.
- Titles are `TextNode` with `maximumNumberOfLines: 1, truncationType: .end` and a
  `maxTitleWidth` explicitly derived from the label width (lines 449, 461, 471). This is a direct
  fix for the overlap failure I described in §5 — the modern client subtracts the value's measured
  width from the title's constraint, which 2013 did not do.

Forced by features: Dynamic Type, badges, dark themes, RTL. A matter of taste: the move to
computed insets over hard-coded frames. For our purposes the modern client's only actionable lesson
is the title/label width negotiation.

### twelve (the Objective-C fork)

Both cells survive essentially untouched, which is itself informative. `diff` against the original
shows for `TGVariantMenuItemCell.m` only: an added `LegacyComponents.h` import,
`UITextAlignmentRight → NSTextAlignmentRight`, and `floorf → CGFloor`. For `TGActionMenuItemCell.m`,
a single added line `_titleLabel.textAlignment = NSTextAlignmentLeft;`. No metric, colour or
behaviour changed in the intervening years.

`TGVariantMenuItemCell` in twelve has **no remaining call sites** (grep finds only its own
header/implementation) — it was orphaned as screens migrated to the Swift item list.
`TGActionMenuItemCell` is still used, by `TGSettingsController.m` alone. So the fork's message is:
these cells were correct enough to never need touching, and were retired wholesale rather than
evolved. That supports porting them literally rather than improving them.

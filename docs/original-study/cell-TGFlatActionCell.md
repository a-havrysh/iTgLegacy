# TGFlatActionCell (original, Telegram for iOS v1.1 build 21024)

Paths below are relative to these roots:

- ORIG = `/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
- OURS = `/Users/alexanderhavrysh/Git/iOS/iTgLegacy`
- TWELVE = `/Users/alexanderhavrysh/Git/iOS/twelve`
- MODERN = `/Users/alexanderhavrysh/Git/iOS/Telegram-iOS`

The class exists under its exact name, in the app target only (not TelegraphKit):
`ORIG/Telegraph/Telegraph/TGFlatActionCell.h` (22 lines) and `.m` (195 lines).

## 1. What it is for

It is the blue "verb row" of the contacts list: a 44 pt-tall, icon + blue bold title + optional
chevron row that sits above the alphabetised people. It is not a generic settings row — it has no
`title` setter at all. The only public surface is a mode enum, and the cell owns the copy, the
artwork and the geometry for each mode (`TGFlatActionCell.h:11-21`):

```
TGFlatActionCellModeInvite            = 0
TGFlatActionCellModeCreateGroup       = 1
TGFlatActionCellModeCreateEncrypted   = 2
TGFlatActionCellModeCreateGroupContacts = 3
- (void)setMode:(TGFlatActionCellMode)mode;
```

That is the whole API. Everything else (background, selection artwork, chevron, fonts) is fixed in
`initWithStyle:reuseIdentifier:` (`TGFlatActionCell.m:23-57`).

"Flat" in the name means flat-list (a plain, full-bleed row) as opposed to the grouped/inset menu
cells (`TGVariantMenuItemCell`, `TGActionMenuItemCell`) that share the same disclosure artwork —
see `TGFlatActionCell.m:51` next to `TGVariantMenuItemCell.m:42`.

## 2. Where it is used — the only call site

`ORIG/Telegraph/Telegraph/TGContactsController.mm` is the only file that instantiates it
(`TGContactsController.mm:55, 1553-1576`). The mechanism is worth copying because it explains the
metrics.

The controller does not add a special section object. It injects two **sentinel `TGUser` rows** with
impossible uids at the head of the Telegram section list, only when the list is the main contacts
list or a "create group" picker (`TGContactsController.mm:3103-3118`):

```
serviceUser.uid = INT_MAX;      // row 0 of section 0
serviceUser.uid = INT_MAX - 1;  // row 1 of the same section 0
```

`cellForRowAtIndexPath:` branches on those uids before it ever looks at a real user
(`TGContactsController.mm:1550-1576`), reusing identifier `@"AC"` — separate from the
`@"ContactCell"` pool, so a flat action cell is never recycled into a contact row.

Mode selection is the interesting part (`TGContactsController.mm:1559, 1571-1575`):

| context | row 0 (`INT_MAX`) | row 1 (`INT_MAX - 1`) |
|---|---|---|
| main contacts list | `ModeInvite` → "Invite Friends" | `ModeCreateGroupContacts` → "New Group" |
| compose / create-group picker (`TGContactsModeCreateGroupOption`) | `ModeCreateGroup` → "New Group" | `ModeCreateEncrypted` → "New Secret Chat" |

So `CreateGroup` and `CreateGroupContacts` render identical text and icon and differ *only* in
whether the chevron is drawn (`TGFlatActionCell.m:111`) — the picker's own "New Group" row does not
push anything, it toggles a mode in place, so it earns no chevron; the contacts list's "New Group"
row pushes a controller, so it does.

Row height is decided by the controller, not the cell (`TGContactsController.mm:1346-1360`):
section 0 of a main-contacts/create-group list is **44 pt**; real contact rows are 51 pt; search
results 51 pt. 44 is not arbitrary — it is exactly the height of the background artwork (below).

Tap handling is also the controller's (`TGContactsController.mm:1647-1659`): `INT_MAX` at row 0 →
`actionItemSelected` → `inviteInlineButtonPressed`; `INT_MAX - 1` at row 1 → `encryptionItemSelected`,
which in the non-picker case pushes `TGSelectContactController initWithCreateGroup:true`
(`TGContactsController.mm:1679-1685`). Note the row-index guards: the action only fires if the
sentinel is where it is expected to be. The cell is **not** deselected on tap (no
`deselectRowAtIndexPath:` in either branch, unlike the user branch at `TGContactsController.mm:1670`),
so the row stays blue-highlighted through the push and unhighlights on the pop-back — that is the
period behaviour, and it is deliberate.

## 3. View tree, metrics and colours

All from `TGFlatActionCell.m:23-57` unless noted. Coordinates are inside `contentView`, in a 320×44 pt row.

**Background.** `backgroundView` = `UIImageView` of `Cell88.png`, `selectedBackgroundView` =
`CellHighlighted88.png`, both cached in file-static `UIImage *` (lines 28-37). Measured from
`ORIG/Telegraph/Telegraph/Resources/`:

- `Cell88@2x.png` is 2×88 px = 1×44 pt. Pure white `#FFFFFF` for the first 86 px, bottom 2 px (1 pt)
  `#E0E0E0`. That hairline **is** the row separator; the table itself draws none.
- `CellHighlighted88@2x.png` is 2×88 px, a vertical blue gradient: `#0085E5` at the top edge,
  brightening to about `#26A4F9` at y=2 px, mid `#1D8EE9`, and `#005FBE` at the bottom edge.
- Only `@2x` variants ship — this build is retina-only for these assets, which suits a 4S.

Because the artwork is exactly 44 pt tall and the row is exactly 44 pt, the strip is pixel-exact and
never stretched. If you ever change the row height, the gradient rescales and the separator hairline
becomes non-integral — this coupling is the reason the height is 44 and not 51 like its neighbours.

**Title label** (line 39-46): frame `(53, 12, contentWidth - 30, 20)`, `boldSystemFontOfSize:16`,
colour `UIColorRGB(0x0779d0)`, `highlightedTextColor` white, `backgroundColor` **white** (opaque, a
scroll-performance choice — the cell clears subview backgrounds itself while highlighted, so the
white square is not visible over the blue), `autoresizingMask = FlexibleWidth`,
`contentMode = Left`. Baseline: 12 pt top inset in a 44 pt row with a 20 pt label → 12 pt bottom, so
the label box is vertically centred; a 16 pt bold system line fits inside 20 pt without clipping.

Note the width bug that is really a non-bug: `contentWidth - 30` starting at x=53 runs 23 pt past
the right edge on a 320-wide cell, i.e. the text is allowed to run *under and past* the chevron. In
practice all three English strings are short. With a long localisation the text runs beneath the
chevron and is then clipped by the cell's bounds rather than ellipsised. Reproducing this exactly is
not worth it; matching the visual result for the shipped strings is.

**Icon view** (line 48-49): created empty, positioned per mode with `sizeToFit` + explicit origin, so
the size always comes from the asset:

| mode | asset | pt size (from `@2x`) | origin | occupies y |
|---|---|---|---|---|
| Invite | `ListIconInvite.png` | 25 × 20 | (13, 12) | 12–32 |
| CreateGroup / CreateGroupContacts | `ListIconFriends.png` | 29 × 19 | (10, 12) | 12–31 |
| CreateEncrypted | `ListIconEncrypted.png` | 31 × 27 | (10, 9) | 9–36 |

(`TGFlatActionCell.m:89-124`; pixel sizes measured from `Resources/ListIcon*@2x.png`.) Every icon
also gets a `highlightedImage` — `ListIcon*_Highlighted.png` (lines 81-86) — so the glyph flips to
its white variant while the row is blue. The origins are hand-tuned per glyph, not derived from a
rule: the invite envelope sits 3 pt further right and the padlock 3 pt higher than the others. The
title x stays at 53 for all three regardless of icon width.

**Disclosure chevron** (line 51-54): `[TGInterfaceAssets groupedCellDisclosureArrow]` /
`…Highlighted`, which are `MenuDisclosureIndicator.png` / `MenuDisclosureIndicator_Highlighted.png`
(`ORIG/Telegraph/Telegraph/TGInterfaceAssets.mm:725-739`), 18×32 px = **9×16 pt**. Frame is
`CGRectOffset(imageFrame, contentWidth - 9 - 12, 14)` → origin (299, 14) on a 320 cell, i.e. 12 pt
from the right edge and exactly vertically centred in 44 ((44−16)/2 = 14). `autoresizingMask =
FlexibleLeftMargin`. Visibility per mode: Invite → shown; CreateGroupContacts → shown; CreateGroup →
hidden; CreateEncrypted → hidden (`TGFlatActionCell.m:99, 111, 123`).

## 4. Behaviours worth reproducing

**The −1 pt selection overhang.** In `setSelected:`, `setHighlighted:` and `layoutSubviews`
(`TGFlatActionCell.m:127-155, 185-193`) the same three lines run: `selectedBackgroundView.frame.origin.y
= -1; size.height = self.frame.size.height + 1`. The highlight therefore covers the 1 pt separator
belonging to the row *above*, so a pressed row is a clean unbroken blue block with no grey line
biting into its top edge. The `true ? -1 : 0` in the source is a leftover debug toggle. Reproducing
this is required — without it a tapped action row shows a grey scar along its top.

**`adjustOrdering`** (`TGFlatActionCell.m:157-183`). On highlight, the cell walks its superview's
subviews, finds the highest index occupied by a `UITableViewCell` or `UISearchBar`, and if it is not
already there re-inserts itself at that index. This is a pre-iOS-7 z-order fix: `UITableView` keeps
cells in arbitrary sibling order, and the −1 pt overhang would otherwise be painted *under* the
neighbouring cell, clipping the top pixel row of the highlight. It also keeps the highlight above the
sticky section index/search bar. On iOS 6 this is a real, visible fix, not dead code.

**Reuse.** There is no `prepareForReuse`. `setMode:` is total — it sets text, image, highlighted
image, icon frame and chevron visibility on every path — so reuse is safe *only* because every mode
branch writes every mode-dependent property. Any new mode must do the same or the previous mode's
icon leaks through.

**Missing / unusual content.** There is no empty state and no way to pass content in: an unknown
enum value falls through all branches and leaves the label text and icon from the previous use
(`TGFlatActionCell.m:63-124` — no `else`). Localised strings come from `TGLocalized`; English values
are `"Invite Friends"`, `"New Group"`, `"New Secret Chat"`
(`ORIG/Telegraph/Telegraph/en.lproj/Localizable.strings:263, 243, 244`). Long strings clip rather
than ellipsise, as described above. The cell does not react to editing mode, accessory type or
multiline text.

## 5. Our port — `OURS/src/TGContactsViewController.m`

We have a class with the same name, private to the contacts file:
`TGContactsViewController.m:132-206`, driven by
`-actionCellForTableView:identifier:` (`TGContactsViewController.m:3079-3105`), with action rows built
in `-actionRowIdentifiers` (`TGContactsViewController.m:2220-2228`) and dispatched in
`didSelectRowAtIndexPath:` (`TGContactsViewController.m:3208-3222`). Height 44
(`kContactActionRowHeight`, `TGContactsViewController.m:25`), contact rows 51
(`TGContactsViewController.m:18`) — both correct.

Right already: label frame origin (53, 12), 20 pt tall, `boldSystemFontOfSize:16`, `0x0779d0`,
white highlighted text; icon origins (13,12) for invite and (10,12) for friends; chevron at
`width - w - 12`, y = 14; the −1 pt selection overhang in `layoutSubviews`. Good.

Visible differences, each with what to change:

1. **`CellHighlighted88` is not in our image set.** `OURS/images/` has `Cell88@2x.png` but no
   `CellHighlighted88@2x.png`, so `TGContactsViewController.m:148-149` falls through to
   `CellHighlighted102@2x.png` (2×104 px = 52 pt) which then stretches into a 44 pt row. The gradient
   endpoints happen to match (`#0085E5` → `#005FBE`), so the error is a compressed mid-tone rather
   than a wrong hue — but it is a real difference and trivially fixed by shipping the original
   `Cell88`-sized highlight strip. Original: `TGFlatActionCell.m:34`.
2. **Icons never turn white when pressed.** We never set `iconView.highlightedImage`
   (`TGContactsViewController.m:180-186`), and `ListIconInvite_Highlighted@2x.png` /
   `ListIconFriends_Highlighted@2x.png` are absent from `OURS/images/`. On tap the original swaps to
   white glyphs (`TGFlatActionCell.m:82-84, 92, 104, 116`); ours leaves blue-grey glyphs sitting on a
   blue field. This is the most visible defect in the port. Ship the two `_Highlighted` assets and
   set `highlightedImage` alongside `image` in `setIconImage:at:`.
3. **No secret-chat variant.** The original's fourth mode (`CreateEncrypted`, padlock
   `ListIconEncrypted.png` at (10, 9), no chevron, `TGFlatActionCell.m:113-124`) has no counterpart —
   `ListIconEncrypted@2x.png` is not in `OURS/images/` at all. Where we surface "Start Secret Chat"
   we do it from an action sheet (`TGContactsViewController.m:1615`). That is a product decision, not
   a porting bug, but if a secret-chat row is ever added to the contacts head it must use the padlock
   at (10, 9) with no chevron.
4. **Two extra modes we invented** — `Sync Contacts` and `My Invite Link`
   (`TGContactsViewController.m:3094-3102`). Both reuse `ListIconFriends` / `ListIconInvite`, so the
   head of the contacts list shows the same glyph twice. Not wrong against any original, but a reader
   comparing screenshots will notice the duplication; a distinct glyph for "Sync" would be truer to
   how the original assigned one icon per verb.
5. **`adjustOrdering` is not ported.** We only fix the frame in `layoutSubviews`
   (`TGContactsViewController.m:189-195`), never the sibling z-order
   (`TGFlatActionCell.m:157-183`). On iOS 6 this shows up as the top pixel row of the blue highlight
   being clipped by the neighbouring cell, intermittently, depending on recycling order. Worth
   porting verbatim; it is 25 lines and self-contained.
6. **We deselect on tap** (`TGContactsViewController.m:3209`) where the original leaves the row
   selected through the push (`TGContactsController.mm:1647-1659`). Ours flashes; the original stays
   lit until you come back. Small, but it is exactly the kind of thing the period screenshots show.
7. **Title width.** Ours clamps the label to stop before the chevron
   (`TGContactsViewController.m:203-204`); the original lets it run under it
   (`TGFlatActionCell.m:39`). Ours is better behaved and identical for the shipped English strings —
   leave it.
8. **Flat/dark theme path.** With `[[TGTheme shared] isFlat]` we skip both background images entirely
   (`TGContactsViewController.m:145-153`) and switch the table to `SingleLine` separators
   (`TGContactsViewController.m:2542-2544`), so in flat mode the row loses the Cell88 hairline and
   the blue press state and falls back to UIKit's grey selection. That is our own theming layer, not
   a deviation from the original — but note the original has *no* concept of it: the pressed state is
   always the blue gradient. If the flat theme is meant to still feel like Telegram, give it a
   coloured `selectedBackgroundView` rather than the UIKit default.

Also worth noting: `cell.titleLabel.backgroundColor` is `clear` in ours
(`TGContactsViewController.m:159`) vs opaque white in the original (`TGFlatActionCell.m:43`).
Visually identical; ours costs a blend per row. Irrelevant on anything modern, marginally relevant on
a 4S — if contacts scrolling is ever measured as slow, this is a free win.

## 6. What became of it

**twelve** (`TWELVE/twelve/Telegraph/TGFlatActionCell.{h,m}`) keeps the class, the sentinel-row
pattern, `adjustOrdering` and the −1 pt overhang unchanged, and shows exactly how the component
absorbed five years of features. Modes grew from 4 to 9 — `Channels`, `CreateChannel`,
`CreateChannelGroup`, `AddPhoneNumber`, `ShareApp` (`TGFlatActionCell.h:11-21` there) — and one of
them, `AddPhoneNumber`, finally forced dynamic content into the cell: a `setPhoneNumber:` setter that
formats the number and interpolates it into the title. That is the single API change that new
features actually forced.

Everything else in twelve's diff is taste and OS drift, all of it flat-design conversion:

- Artwork gone. No `Cell88` / `CellHighlighted88`; `selectedBackgroundView` is a plain
  `TGSelectionColor()` view, and the separator is a `CALayer` inset to x=65 (74 on iPad) rather than
  a full-bleed pixel baked into the background image.
- Colours come from a runtime `TGPresentation` palette (`setPresentation:`) instead of literals, and
  icons come from `presentation.images.*` instead of `imageNamed:`.
- `highlightedTextColor` and every `highlightedImage` are **dropped** — with a light-grey selection
  colour there is nothing to invert against. Our port accidentally matches the *later* behaviour here
  while keeping the *earlier* blue highlight, which is why point 2 above looks wrong.
- Font `boldSystemFontOfSize:16` → `TGSystemFontOfSize(17)` (regular, iOS 7 metrics), left inset
  53 → 66, chevron removed entirely.

**Modern** (`MODERN/submodules/ContactListUI/Sources/ContactListActionItem.swift`, and its generic
sibling `MODERN/submodules/ItemListUI/Sources/Items/ItemListActionItem.swift`) completes the
dissolution. There is no cell class and no mode enum: `ContactListActionItem` takes `title`,
`subtitle`, `icon`, `actionStyle` and a closure, and lays out asynchronously — height is computed
from the measured text (`ContactListActionItem.swift:236-252`), not fixed at 44; left inset is
`16 + params.leftInset`, plus 49 when there is an icon (`:209-211`); the title is truncated with a
real `.end` truncation against a measured constraint (`:226`); the separator is a `UIScreenPixel`
stripe inset to the text (`:336`); the highlight node still uses the same one-pixel overhang trick,
now spelled `-UIScreenPixel` on both edges (`:349`). The 2013 idea that survived thirteen years is
precisely that overhang and the icon-plus-accent-title-plus-inset-separator shape. What died was the
enum: the cell no longer knows what "invite friends" means, and every caller passes its own string,
icon and action.

For our purposes this direction is a warning, not a model. The mode enum is the right design for a
2013 pixel-exact reproduction — the per-mode hand-tuned icon origins (13,12)/(10,12)/(10,9) cannot be
derived from a rule, so they have to live in the cell, keyed by mode, exactly as the original did.

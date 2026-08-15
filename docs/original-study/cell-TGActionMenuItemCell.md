# TGActionMenuItemCell — the plain settings row of 2013 Telegram

Source of record: `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGActionMenuItemCell.h`
and `.../TGActionMenuItemCell.m` (105 lines total; the whole class fits on one screen).
The class exists under exactly that name, in `Telegraph/Telegraph` only — there is no
TelegraphKit copy.

## 1. What it is for

This is the workhorse row of every grouped list in the app: a single bold black line of
text on a white rounded-group background, with either a grey chevron on the right (it
pushes another controller), a blue tick on the right (it is the selected member of a
radio group), or nothing at all. Everything else in Settings — the switch row, the
two-line variant row, the user row — is a sibling class; this is the base case.

Two objects are involved, and they are not the same thing:

- `TGActionMenuItem` (`TGActionMenuItem.h:13`) is the *model*: a `TGMenuItem` subclass
  carrying only `title` (`TGActionMenuItem.h:15`) and a `SEL action`
  (`TGActionMenuItem.h:17`), tagged with the type constant
  `TGActionMenuItemType == 0xD8B4CD4C` (`TGActionMenuItem.h:11`). The type constant is
  how the table data sources dispatch: `if (item.type == TGActionMenuItemType)`
  (`TGSettingsController.m:255`).
- `TGActionMenuItemCell` is the *view*. Note that it does not know about
  `TGActionMenuItem` at all — it imports only UIKit and `TGInterfaceAssets`
  (`TGActionMenuItemCell.m:1-3`). The controller copies `actionItem.title` into
  `actionItemCell.title` by hand (`TGSettingsController.m:271`). Half its call sites
  (`TGPhoneLabelController`, `TGTextFontController`, `TGCustomNotificationController`,
  `TGWallpaperStoreController`) use the cell with no model object at all, feeding it a
  raw `NSString` out of an array (`TGPhoneLabelController.m:164`). So the cell is the
  reusable component; the item class is optional baggage.

## 2. Public surface

```objc
@interface TGActionMenuItemCell : TGGroupedCell
@property (nonatomic) bool forcePaddings;
@property (nonatomic, strong) NSString *title;
- (void)setHideDisclosureIndicator:(bool)hide;
- (void)setHideCheckIndicator:(bool)hide;
@end
```
(`TGActionMenuItemCell.h:13-22`)

That is the entire API. There is no colour property, no font property, no subtitle, no
icon, no "destructive" flag. A red "Delete Contact" row is a *different* class
(`TGButtonMenuItemCell`), not a variant of this one — 2013 Telegram preferred a new
cell class over a configuration flag.

Inherited from `TGGroupedCell` (`TGGroupedCell.h:16-21`): `groupedCellPosition`
(bitmask of `TGGroupedCellPositionFirst = 1`, `TGGroupedCellPositionLast = 2`,
`TGGroupedCell.h:11-14`) and `extendSelectedBackground`. Those two are always set by the
controller, never by the cell.

## 3. Geometry, with the reasoning behind each number

All values from `TGActionMenuItemCell.m`.

| Element | Frame | Line |
|---|---|---|
| title label (normal) | `(11, 12, contentView.width - 30, 20)` | 30 |
| title label (`forcePaddings`) | `(11, 14, contentView.width - 30, 20)` | 87 |
| disclosure chevron (normal) | `x = contentView.width - w - 11`, `y = 14` | 41 |
| disclosure chevron (`forcePaddings`) | same x rule, `y = 16` | 88 |
| check mark | `x = contentView.width - w - 9`, `y = 14` | 72 |

The row height is not the cell's business: the controllers declare **44 pt** for
`TGActionMenuItemType` (`TGSettingsController.m:218-219`, and identically
`TGNotificationSettingsController`), which is what makes the default numbers land
centred — label `12 + 20/2 = 22 = 44/2`; chevron, whose art is 9 × 16 pt (see §4),
`14 + 8 = 22`. Both are exactly on the mid-line of a 44 pt row. That is the whole
justification for `12` and `14`: they are derived, not chosen.

`forcePaddings` is the same layout re-derived for a **48 pt** row: label `14 + 10 = 24`,
chevron `16 + 8 = 24`, and `24 = 48/2`. Its single user is the "Choose from Camera Roll"
row above the wallpaper grid, whose height is 48 (`TGWallpaperStoreController.m:319-320`,
flag set at `TGWallpaperStoreController.m:363`). That controller's table is
`UITableViewStylePlain` (`TGWallpaperStoreController.m:136`) with separators off
(`:141`), so `forcePaddings` also does the job UIKit's grouped style would otherwise do:
it insets `contentView`, `backgroundView` and `selectedBackgroundView` to
`origin.x = 9, width = self.frame.size.width - 18`
(`TGActionMenuItemCell.m:90-100`). 9 pt, not the 10 pt of the system grouped style,
because the rounded-corner PNGs are drawn for a 9 pt inset.

The check mark is the one element that is *not* vertically centred: its art is 13 × 14 pt,
so `14 + 7 = 21` against a mid-line of 22 — it sits one point high. This is in the
original and is not compensated anywhere; reproduce it or not, but know it is a real
one-point offset (`TGActionMenuItemCell.m:72`).

Horizontal: text starts at 11 pt from the left edge of `contentView`, which in a grouped
table is already inset, so the visual left margin on a 320 pt screen is about 21 pt.
The label is `contentView.width - 30` wide, i.e. it stops 19 pt from the right edge,
while the chevron starts at `width - 9 - 11 = width - 20`. The label therefore overlaps
the chevron by one point; since the label is single-line with UILabel's default tail
truncation, long titles end in "…" roughly at the chevron and never push it. Nothing
elides or shrinks: no `adjustsFontSizeToFitWidth`, no multi-line, no dynamic height.
**Long text truncates; that is the entire long-text story.** Hiding the chevron does not
widen the label — the label frame is fixed, so a check-only row wastes those 19 pt.

Autoresizing carries width changes (rotation): label `FlexibleWidth`
(`:32`), chevron and check `FlexibleLeftMargin` (`:40`, `:71`). That is why layout is
not recomputed on every `layoutSubviews` except in the `forcePaddings` branch.

## 4. Typography and colour

- Font: `[UIFont boldSystemFontOfSize:17]` (`TGActionMenuItemCell.m:33`). Helvetica-Bold
  17 on iOS 6. Every metric above is sized around a 20 pt line box for this font.
- Normal title colour: pure black `[UIColor blackColor]` (`:35`).
- Highlighted title colour: pure white `[UIColor whiteColor]` (`:36`), used when the row
  is tapped and the blue selection art shows through.
- Checked title colour: `UIColorRGB(0x516691)` (`:77`) — the desaturated slate-blue of
  the era, set by `setHideCheckIndicator:false` and reverted to black by
  `setHideCheckIndicator:true` (`:64`). **The colour change and the tick are one state,
  applied by one method.** A radio row is not just "black text plus a tick": the text
  itself goes blue.
- `titleLabel.backgroundColor = [UIColor whiteColor]` (`:34`). This is an opaque-label
  scrolling optimisation for 2013 hardware, and it is only correct because the cell
  background art is white and because UIKit temporarily clears subview background
  colours while a cell is highlighted. It hard-codes "settings rows are white" into the
  cell; any dark theme breaks it. Ours must not copy this blindly (see §7).

## 5. Artwork

Everything is Retina-only — the resource folder has no `@1x` companions for any of these
(`Telegraph/Telegraph/Resources/`), which matters for us only in that the point sizes
below are the `@2x` pixel dimensions halved.

- Chevron: `MenuDisclosureIndicator.png` / `MenuDisclosureIndicator_Highlighted.png`,
  fetched through `[TGInterfaceAssets groupedCellDisclosureArrow]` /
  `…Highlighted` (`TGInterfaceAssets.mm:725-739`), cached in a static. Asset is
  18 × 32 px = **9 × 16 pt**. It is installed as the image/highlightedImage pair of one
  `UIImageView` (`TGActionMenuItemCell.m:39`), so UIKit swaps to the white variant on
  highlight for free. There is a third file, `MenuDisclosureIndicator_Light.png`, which
  this cell never uses.
- Tick: `ListCheck.png` / `ListCheck_Highlighted.png` loaded directly with
  `imageNamed:` — not through `TGInterfaceAssets` (`TGActionMenuItemCell.m:70`).
  26 × 28 px = **13 × 14 pt**.
- Group background: not the cell's job. The controller assigns `UIImageView`s as
  `backgroundView` / `selectedBackgroundView` at creation
  (`TGSettingsController.m:263-266`) and sets their images per position on every
  `cellForRow`: `groupedCellSingle` / `Top` / `Bottom` / `Middle` and their
  `…Highlighted` twins (`TGSettingsController.m:304-336`, repeated verbatim in
  `TGPhoneLabelController.m:171-203`). Those assets are stretched from the centre by
  `TGStretchableImageInCenterWithName` (`TGInterfaceAssets.mm:14`), except
  `groupedCellSingleHighlighted`, which uses explicit cap insets
  `UIEdgeInsetsMake(5, 13, 6, w - 14)` on iOS ≥ 5 (`TGInterfaceAssets.mm:715-720`).

## 6. States, tap, and reuse

**Highlight.** `TGGroupedCell` intercepts `setHighlighted:` and `setSelected:`
(`TGGroupedCell.m:33-65`) to force `selectedBackgroundView.frame.origin.y = 0` and its
height to the full cell height, then, when `extendSelectedBackground` is set, adds one
extra point of height for middle and first-in-section rows
(`extendBackgroundSize`, `TGGroupedCell.m:3-15`). The reason is the hairline separator
drawn *between* grouped cells: without the extra point, a highlighted middle row shows a
one-pixel white seam under it. A single-cell section passes
`extendSelectedBackground:false` (`TGSettingsController.m:308`) because it has no
neighbour to bleed into.

`adjustOrdering` (`TGGroupedCell.m:87-112`) re-inserts the highlighted cell above all
sibling cells in the table's subview list, so the extended, rounded selection art is not
clipped by the neighbouring cell's opaque background. This is a real visual bug fix, not
decoration: skip it and a highlighted row's bottom edge is overdrawn by the row below.

**Tap.** The cell has no tap handling whatsoever — no target/action, no watcher handle
(contrast `TGButtonMenuItemCell`, which is given `watcherHandle`,
`TGProfileController.m:2462`). Selection is `didSelectRowAtIndexPath` in the controller,
which reads `((TGActionMenuItem *)item).action` and performs it
(`TGSettingsController.m:366`, `TGNotificationSettingsController.m:584`). In the
radio-group controllers the tap handler mutates two cells directly rather than reloading:
old cell `setHideCheckIndicator:true`, new cell `setHideCheckIndicator:false`, then
notify the watcher (`TGPhoneLabelController.m:213-227`; same shape in
`TGTextFontController.m:181-195` and `TGCustomNotificationController.m:214-228`). If the
old cell is off-screen the call is skipped (`cell != nil`) and correctness is restored by
`cellForRow` on the next scroll-in.

**Reuse.** There is no `prepareForReuse`. Consequences the caller must handle:

1. `_checkIndicator` is created lazily on the *first* `setHideCheckIndicator:false`
   (`TGActionMenuItemCell.m:68-74`); afterwards it is only hidden, never removed. So a
   dequeued cell can arrive with a stale tick and a stale blue title. Every radio
   controller therefore calls `setHideCheckIndicator:` unconditionally on every
   `cellForRow` (`TGPhoneLabelController.m:166`). `TGPhoneLabelController.m:161` even
   calls `setHideCheckIndicator:false` inside the `cell == nil` branch purely to force
   the lazy view into existence before the row's real state is applied.
2. The chevron is visible by default; `setHideDisclosureIndicator:true` must be repeated
   on every `cellForRow` in the check-style lists
   (`TGPhoneLabelController.m:165`, `TGTextFontController.m:131`,
   `TGCustomNotificationController.m:164`). `TGSettingsController` never calls it, so its
   rows always show the chevron even for rows that do nothing.
3. `forcePaddings` is set once at creation and never cleared
   (`TGWallpaperStoreController.m:363`), which is safe only because reuse identifiers are
   per-controller.

**Empty / missing content.** `setTitle:` assigns straight through with no nil guard
(`TGActionMenuItemCell.m:47-51`); a nil title yields an empty row of the full 44 pt with
its chevron still drawn. There is no placeholder and no "no value" styling anywhere.
Live title updates are supported by re-calling `setTitle:` on the visible cell rather
than reloading (`TGSettingsController.m:492-496`).

## 7. Our port — verdict

We have **no equivalent class**. The whole pattern is inlined into
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGSettingsViewController.m`, which builds
stock `UITableViewCell`s (`TGSettingsViewController.m:328-336`), styles them via
`[[TGTheme shared] styleCell:]` (`TGTheme.m:411-427`), and attaches the chevron/tick as
`cell.accessoryView` through two helpers, `markDisclosure:` (`:1214-1222`) and
`markChecked:on:` (`:1224-1238`), fed by `disclosureAccessory` (`:1188-1200`) and
`checkAccessory` (`:1202-1212`). The table is `UITableViewStyleGrouped`
(`TGSettingsViewController.m:154`, `:1076`), row height 44 (`:2882-2891`), title font
`boldSystemFontOfSize:17` set in dozens of places and in `TGTheme styleCell:`
(`TGTheme.m:412`). The art files are present in `iTgLegacy/images/`
(`MenuDisclosureIndicator@2x.png`, `ListCheck@2x.png`, `GroupedCellTop@2x.png`, …).

So font, height and artwork are right. The visible differences:

1. **The checked row's title does not turn blue.** Original: `UIColorRGB(0x516691)` on
   check, black off check (`TGActionMenuItemCell.m:64,77`). Ours: `markChecked:on:`
   (`TGSettingsViewController.m:1224-1238`) only swaps `accessoryView` and leaves
   `textLabel.textColor` at whatever `styleCell:` set. Fix: in `markChecked:on:`, set
   `cell.textLabel.textColor` to `#516691` when checked and back to the theme's primary
   colour when not — and set it on *both* branches, because cells are reused.
2. **Accessory positioning is UIKit's, not the original's.** `accessoryView` is laid out
   by UIKit at a fixed right inset and vertically centred; the original placed the
   chevron at `width - 9 - 11` from the *content* edge (`TGActionMenuItemCell.m:41`) and
   the tick at `width - 13 - 9` one point above centre (`:72`). Using `accessoryView`
   also shrinks `textLabel`'s width, which the original never did. The horizontal
   result is close; the tick's one-point rise and the constant text width are lost. This
   is minor and arguably worth accepting — but it should be a decision, not an accident.
3. **Chevron art is theme-switched; the original never did that.** We pick
   `MenuDisclosureIndicator_Light.png` in dark mode
   (`TGSettingsViewController.m:1191-1193`). The original used the plain/highlighted pair
   only (`TGActionMenuItemCell.m:39`, `TGInterfaceAssets.mm:725-739`) and left `_Light`
   for other call sites. Defensible as a dark-theme extension we need, but it is ours,
   not 2013's — do not cite the original for it.
4. **The check accessory has no highlighted-state art path in one case.** We do pass a
   highlighted image for both (`TGSettingsViewController.m:1195-1198`, `:1207-1209`), so
   this is correct; noted only so a future reader does not "fix" it.
5. **We never draw the grouped-cell PNG art or the extended selection.** The assets
   `GroupedCellTop/Middle/Bottom/Single(_Selected)` are shipped in `images/` but no
   source file references them (grep over `iTgLegacy/src` finds
   `MenuDisclosureIndicator` and `ListCheck` only). We rely on UIKit's own grouped
   background plus `TGTheme`'s flat `selectedBackgroundView`
   (`TGTheme.m:421-426`). That means: no 2013 rounded-corner bevel, no one-point
   selection extension, no `adjustOrdering` z-reorder. This is the largest visible gap
   and it belongs to `TGGroupedCell`, not to this cell — but it changes how every
   settings row looks. If we want the period look, the fix is a small `TGGroupedCell`
   port plus per-position image assignment in `cellForRow`, exactly as
   `TGSettingsController.m:304-336` does it.
6. **The opaque white label background is absent from ours** — correctly so. Ours
   supports dark themes (`TGTheme.m:416-422`), where a hard-coded white label box would
   be wrong. Keep it absent.

Ambiguity worth flagging: the original's left text margin is 11 pt *inside a grouped
contentView*, and the effective screen margin depends on UIKit's grouped inset for the
iOS version. Our stock cells use UIKit's default `textLabel` origin instead. I did not
find a place where the original pins an absolute screen-space left margin, so I cannot
state one number as "the" correct left inset; if a pixel-exact match matters, measure
against the 2013 reference screenshots rather than trusting either code path.

## 8. What it became

**twelve** (`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGActionMenuItemCell.m`)
carries the class forward essentially unchanged — same frames, same 0x516691, same lazy
tick. The only diff is one added line, `_titleLabel.textAlignment = NSTextAlignmentLeft;`
(`twelve/Telegraph/TGActionMenuItemCell.m:37`), which is defensive RTL/default hygiene,
not a design change. That is a useful signal: this component was correct enough to
survive its own fork untouched.

**Telegram-iOS today** split the one class in two, along the axis this cell papered over
with `setHideDisclosureIndicator:` / `setHideCheckIndicator:`:

- `submodules/ItemListUI/Sources/Items/ItemListDisclosureItem.swift` — the chevron row.
- `submodules/ItemListUI/Sources/Items/ItemListCheckboxItem.swift` — the tick row, which
  now also owns the tick's *side*: `ItemListCheckboxItemStyle { case left, right }`
  (`ItemListCheckboxItem.swift:8-11`), with `.left` adding a 62 pt leading inset for the
  tick (`:203-205`). 2013 had only the right-hand tick.

Changes that were forced, not aesthetic:

- **Height is computed, not constant.** `contentSize.height = titleLayout.height +
  verticalInset * 2`, with `verticalInset = 11` in the legacy style
  (`ItemListCheckboxItem.swift:246-254`). 11 × 2 + a 22 pt line ≈ our 44, so the classic
  row height survived as an emergent value; it became a formula because Dynamic Type
  (`item.presentationData.fontSize.itemListBaseFontSize`, `:221`) made a hard-coded 44
  untenable.
- **Font weight flipped.** The modern title is `Font.regular(baseFontSize)`
  (`ItemListCheckboxItem.swift:221`), and the disclosure item chooses regular vs medium
  by an explicit `titleFont` enum (`ItemListDisclosureItem.swift:440-446`). The 2013 row
  was unconditionally *bold* 17. This is the single biggest visual difference between
  then and now, and it is a change of taste — it is exactly the sort of thing our port
  must keep at bold, and does (`TGTheme.m:412`).
- **Colour became semantic.** `titleColor` is chosen from
  `theme.list.itemPrimaryTextColor` / `itemAccentColor` / `itemDisabledTextColor`
  (`ItemListCheckboxItem.swift:224-234`), where 2013 hard-coded black, white and
  `0x516691`. Forced by theming, and it is the same move we should make for defect (1):
  the checked-title colour should come from `TGTheme`, seeded with `0x516691` for the
  period skin.
- **A subtitle line and a disabled state appeared** (`:239`, `:232-234`) — new features,
  no 2013 ancestor.
- **Truncation policy is unchanged in spirit**: still one line, still
  `truncationType: .end`, constrained to `width - leftInset - 28`
  (`ItemListCheckboxItem.swift:237`). Thirteen years and the answer to "what if the title
  is long" is still "ellipsis on the right".

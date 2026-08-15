# TGVariantMenuItemCell (original Telegram for iOS 1.1, 2013)

Sources cited below are relative to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
unless stated otherwise. The class exists exactly under this name; there is no
TelegraphKit version — it lives in the app target only
(`Telegraph/Telegraph/TGVariantMenuItemCell.h`, `.m`).

## What it is for

It is the "row with a title on the left, a current value on the right, and a
chevron" row of the 2013 settings/profile menus: *Sound → Bells*, *Text Size →
16pt*, *Message Lifetime → Forever*, *Encryption Key → (identicon)*. Tapping it
pushes a picker or opens a sheet; the cell never edits anything itself. It is the
direct ancestor of today's `ItemListDisclosureItem`.

It is one member of a hand-rolled menu framework: a controller builds
`TGMenuSection`s of `TGMenuItem` subclasses, each with an `int type` constant, and
the table's `cellForRowAtIndexPath:` switches on the type. The model half here is
`TGVariantMenuItem` (`TGVariantMenuItem.h:13-19`): `title`, `variant`,
`variantImage`, and a bare `SEL action` performed on the controller. Its type
constant is `TGVariantMenuItemType == 0xF419EA88` (`TGVariantMenuItem.h:11`).

## Class surface

```objc
@interface TGVariantMenuItemCell : TGGroupedCell     // TGVariantMenuItemCell.h:13
@property (nonatomic, strong) NSString *title;       // :15
@property (nonatomic, strong) NSString *variant;     // :16
- (void)setVariantImage:(UIImage *)image;            // :18
```

Three private views, all built once in `initWithStyle:reuseIdentifier:` and never
re-laid-out in `layoutSubviews` — the cell has no `layoutSubviews` at all. All
adaptation to width is done by autoresizing masks (`TGVariantMenuItemCell.m:7-13,
17-48`).

## Metrics, fonts and colours (every number cited)

| Element | Value | Citation |
|---|---|---|
| Row height | 44 pt (same as action/switch rows) | `TGChatSettingsController.m:266-268`; also `TGNotificationSettingsController.m:347`, `TGTelegraphConversationProfileController.mm:1211` |
| Title frame | `(11, 12, contentView.width - 28, 20)` | `TGVariantMenuItemCell.m:24` |
| Title font | `boldSystemFontOfSize:17` | `.m:26` |
| Title colour | black; highlighted white | `.m:28-29` |
| Title backgroundColor | **opaque white** (not clear) | `.m:27` |
| Variant frame | `(width - 200 - 11 - 14, 11 + retinaPixel, 200, 20)` → x = width−225, right edge at width−25 | `.m:32` |
| `retinaPixel` | `0.5` on retina, `0` otherwise | `.m:22` |
| Variant font | `systemFontOfSize:16` | `.m:36` |
| Variant colour | `UIColorRGB(0x356596)` (the 2013 Telegram link blue); highlighted white | `.m:38-39` |
| Variant alignment | right, `contentMode = UIViewContentModeRight` | `.m:33-34` |
| Variant background | clear | `.m:37` |
| Chevron image | `MenuDisclosureIndicator.png` / `_Highlighted.png` | `TGInterfaceAssets.mm:725-739` |
| Chevron art size | 18×32 px @2x → **9×16 pt** | `Telegraph/Telegraph/Resources/MenuDisclosureIndicator@2x.png` (only an @2x exists) |
| Chevron frame | `x = contentView.width − 9 − 11`, `y = 14` (image's own size) | `.m:44` |
| Variant image frame | `x = width − 30 − image.width`, y centred with `floorf` | `.m:80` |
| `UIColorRGB` macro | `TelegraphKit/TelegraphKit/TGCommon.h:28` | |

Why these numbers hang together: the title is bold 17 and sits at y=12 with a 20 pt
box, so its cap height lands slightly above centre of the 44 pt row; the variant is
system 16, one point *smaller*, so it is placed one point higher (y=11) plus half a
pixel on retina to make the two baselines line up. Do not "fix" that 11 vs 12 to a
shared centre — it is a deliberate baseline match between two different sizes.

The right-hand geometry is a chain: chevron right inset 11, chevron 9 wide, so the
chevron's left edge is at width−20; the variant text's right edge is at width−25,
leaving a 5 pt gap between value and chevron. The `- 200 - 11 - 14` in the source is
literally "200 wide label, 11 outer inset, 14 for the chevron column".

## How it survives rotation without layout code

`_titleLabel` and `_variantLabel` both get `UIViewAutoresizingFlexibleWidth`
(`.m:25, .m:35`) and the chevron gets `UIViewAutoresizingFlexibleLeftMargin`
(`.m:43`). For the right-aligned variant this is a trick, not a mistake: its origin
is pinned and only its width grows with the contentView, so its *right* edge tracks
the cell edge while the text stays right-aligned inside. The variant image view also
uses `FlexibleLeftMargin` (`.m:71`), so it moves with the right edge.

## Background, grouping and the highlight

The cell inherits `TGGroupedCell`, which makes the cell itself transparent
(`TGGroupedCell.m:27-28`) and lets the controller install the nine-part grouped
artwork. The controller — not the cell — supplies plain `UIImageView`s as
`backgroundView` and `selectedBackgroundView` at first dequeue
(`TGChatSettingsController.m:393-400`) and then assigns
`groupedCellSingle/Top/Bottom/Middle` plus the `…Highlighted` variants according to
the row's position in its section (`TGChatSettingsController.m:436-468`). For
non-single positions it also sets `extendSelectedBackground = true`, which grows the
selected artwork by 1 pt so the highlight covers the hairline between rows
(`TGGroupedCell.m:3-15, 33-65`), and `adjustOrdering` re-inserts the highlighted cell
as the topmost cell subview so its extended highlight is not clipped by its neighbour
(`TGGroupedCell.m:87-112`).

Highlight of the text is stock UIKit: both labels declare
`highlightedTextColor = white` (`.m:29, .m:39`) and the chevron was created with
`initWithImage:highlightedImage:` (`.m:42`), so UIKit flips all three together. The
opaque white `titleLabel.backgroundColor` (`.m:27`) is a scrolling optimisation that
only works because UITableViewCell temporarily clears the backgrounds of contentView
subviews while highlighted — worth knowing before copying that line into a cell that
is not inside a table.

Selection style is left at the default (blue) for this cell; note the sibling switch
cell explicitly sets `UITableViewCellSelectionStyleNone`
(`TGChatSettingsController.m:371`) and the variant cell deliberately does not — the
row is tappable and is meant to flash.

## The two content modes: text variant vs image variant

`setVariantImage:` (`.m:64-82`) is the only stateful method. It lazily creates the
image view on first call, hides the text label when an image is given and hides the
image view when `nil` is given. Its frame is computed **at call time** from
`contentView.frame` — there is no layout pass — so it depends on the cell already
having its final width when the controller sets it. The single real user is the
secret-chat encryption key row, which passes a 24×24 identicon
(`TGProfileController.m:2028-2035`: `keyItem.variantImage = TGIdenticonImage(hashData,
CGSizeMake(24, 24))`), applied in `cellForRow` at `TGProfileController.m:2561` and on
later refresh at `:3823-3827`. With a 24 pt image the right inset is 30, i.e. the
image sits 5 pt further left than text would (width−30 vs width−25 right edge), and
it is vertically centred with `floorf` so odd differences bias upward.

Reuse hazard worth reproducing carefully rather than copying: `TGProfileController`
calls `setVariantImage:` unconditionally for every variant row
(`TGProfileController.m:2561`), which is what keeps the identicon from bleeding onto
the *Sound* row through the shared `@"VI"` reuse identifier. `TGChatSettingsController`
and `TGNotificationSettingsController` never call it at all
(`TGChatSettingsController.m:405-407`), which is safe only because their tables never
show an image variant. A port that adds an image variant to any screen must set it on
every row of that screen.

## Behaviour with real data

- **Empty/nil variant.** `setVariant:` just assigns the text (`.m:57-62`). A nil
  variant leaves an empty label; the row still shows title + chevron and is still
  tappable. Callers rely on this: the encryption key item never sets `variant`
  (`TGProfileController.m:2028-2032`).
- **Missing value data.** The original prefers a synthesised string over blank:
  when the sound id is out of range it shows `"Sound %d"`
  (`TGProfileController.m:1965-1970`).
- **Long value.** The variant box is a hard 200 pt. Longer text truncates with the
  UILabel default tail ellipsis; it never pushes the title.
- **Long title.** The title box is `width − 28` — the full row width, running
  *underneath* the variant label and chevron. Because the variant label has a clear
  background and is added after the title, a long localised title visibly overlaps
  the value text before it ellipsises at the far right edge. This is a genuine defect
  of the original, not a design; the modern client fixed it by negotiating widths.
- **Two-line content.** Impossible. Both labels are single-line 20 pt boxes and the
  row is a fixed 44 pt.

## Tap behaviour

The cell has no target/action. `didSelectRowAtIndexPath:` looks up the item, and for
`TGVariantMenuItemType` performs the item's `SEL` on the controller
(`TGChatSettingsController.m:512-521`, same shape in
`TGProfileController.m:2909-2918` and `TGTelegraphConversationProfileController.mm:1736`).
Refresh after the picker returns is manual and always the same three steps: update
the model item, ask the table for the live cell, and if it is still a
`TGVariantMenuItemCell` set `.variant` on it — never `reloadData`
(`TGChatSettingsController.m:169-174`, `TGNotificationSettingsController.m:904-919`,
`TGProfileController.m:4207-4223`). The row is also refreshed in `viewWillAppear:`
after deselecting the pushed row (`TGChatSettingsController.m:160-174`).

## Our port

We have no `TGVariantMenuItemCell` and no menu-item model layer; the pattern is
inlined into each screen as a stock `UITableViewCellStyleValue1`. The main instances
are `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGSettingsViewController.m`
(cell created at `:330`/`:2490`, value rows in `decorateRootCell` `:2626-2646`,
`fillNotificationCell` family `:2905-2995`), plus the same idiom in
`TGPrivacyViewController.m:366`, `TGProfileViewController.m:3119` and others.

Right by construction: 44 pt rows (`TGSettingsViewController.m:2882-2891`), bold
system 17 title (`:2503`), system 16 value (`TGTheme.m:414`), value colour
`0x356596` (`TGTheme.m:205`, `TGSettingsViewController.m:2630`), and the real
`MenuDisclosureIndicator.png` used as an `accessoryView` rather than the iOS chevron
(`TGSettingsViewController.m:1190-1226`). That is the substance of the component and
it is correct.

Visible differences, worst first:

1. **Value colour is inconsistent within one list under a themed build.**
   `styleCell:` returns the imported theme's `accent` for `cellDetailColour`
   (`TGTheme.m:302-305`, `:414`), but `decorateRootCell:` hardcodes
   `TGSettingsRGB(0x356596)` for the *Chat List*, *Telegram Premium* and *Proxy*
   rows (`TGSettingsViewController.m:2629-2645`). With an imported theme those three
   rows differ in colour from every other value row on the same screen. Pick one:
   either drop the hardcodes or make the whole family ignore the theme (the original
   had no theming — `TGVariantMenuItemCell.m:38` is unconditional).
2. **No grouped highlight artwork.** The original swaps to
   `groupedCell*Highlighted` art and whitens both labels
   (`TGChatSettingsController.m:436-468`, `TGVariantMenuItemCell.m:29, 39`). We use
   `UITableViewCellSelectionStyleBlue` (`TGSettingsViewController.m:335`), i.e. the
   iOS 6 blue gradient. Our `images/` only ships `GroupedCellTop/Bottom` and the
   vertical separator, used solely by `TGNewContactViewController.m:189-192, 429` —
   the `Single`/`Middle`/`_Highlighted` set is missing. Until that art is added, the
   tap flash on every settings row is iOS 6's, not Telegram's; this is the single
   most visible remaining gap for this component.
3. **Baseline.** Value1 vertically centres both labels; the original nudges the value
   1 pt (plus half a retina pixel) above the title's box to align baselines
   (`TGVariantMenuItemCell.m:24 vs :32`). Sub-pixel, but it is why the original reads
   as one line of type and ours reads as two boxes.
4. **Right inset.** The original's value ends 25 pt from the content edge with the
   chevron at 11 (`.m:32, :44`). Ours inherits UIKit's `accessoryView` layout, whose
   margins on iOS 6 are close but not these numbers. If a pixel-exact row is wanted,
   this is the argument for writing a real `TGVariantMenuItemCell` instead of Value1.
5. **No image variant.** Nothing in our tree renders an identicon
   (no hits for `dentic` outside unrelated `indexOfObjectIdenticalTo:`), although
   `TGClient+SecretChats.h:83` already exposes the key hash for the classic 12×12
   identicon. When the secret-chat Encryption Key row is built, it needs the
   image-instead-of-text mode and the "set it on every row" reuse discipline above.
6. **Long-title overlap.** Ours cannot reproduce it — Value1 shortens the title
   instead. This is a difference from the original, and ours is the better behaviour;
   do not "restore" it.

## What became of it

**twelve** (`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGVariantMenuItemCell.m`)
kept the class byte-for-byte except two compile fixes: `UITextAlignmentRight` →
`NSTextAlignmentRight` and `floorf` → `CGFloor` from LegacyComponents. Every metric,
colour and the whole `setVariantImage:` contract survive unchanged. So on the
original's own lineage this component was never redesigned — it was simply carried
forward, which is a strong argument for treating the numbers above as canon rather
than as one screen's accident.

**Modern Telegram** replaced it with
`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS/submodules/ItemListUI/Sources/Items/ItemListDisclosureItem.swift`.
The concept is intact — title left, value right, chevron — but three things changed,
and each was forced by a feature rather than by taste:

- **The value became a style enum, not a string.** `ItemListDisclosureLabelStyle`
  has `text`, `detailText`, `multilineDetailText`, `badge`, `semitransparentBadge`,
  `color`, `image`, `textWithIcon` (`:33-36`, dispatched at `:426`, `:476-495`). The
  2013 cell already contained the seed of this in its one hardcoded alternative,
  `setVariantImage:` — the enum is that hack generalised. Badges reserve an extra
  44 pt of right inset (`:426-431`).
- **Height became computed.** `verticalInset * 2 + title + spacing + label`, with a
  floor of `40 + verticalInset * 2` for badge styles (`:548-559`), because
  `detailText` puts the value on a second line and because the app has a user font
  size setting (`itemListBaseFontSize`, `:441-446`; detail font is
  `floor(base * 15/17)`, `:467`). Our 44 pt fixed row is correct for 2013 and should
  stay fixed.
- **Widths are negotiated.** Title and label are laid out against explicit
  constrained sizes with `truncationType: .end` (`:461`, `:499`), which is precisely
  the fix for the overlap bug described above. Left inset is 16 (+43/49 with an icon,
  +46 with a peer avatar) (`:419-423`) — a modern metric; the 2013 inset is 11 and we
  should keep 11.

## Open questions

- Whether the original ever showed a *non-retina* chevron: only
  `MenuDisclosureIndicator@2x.png` ships in `Resources/`, so on a 1× device UIKit
  would have downscaled or found nothing. Irrelevant for an iPhone 4S target, but it
  means the 9×16 pt size is inferred from the @2x file, not stated anywhere in code.
- The exact contentView width at `init` time is 320-ish placeholder, so the frames in
  `initWithStyle:` are only correct because of the autoresizing masks; the effective
  inset from the *cell* edge depends on the grouped table's own 10 pt side inset,
  which the controllers never state explicitly.

# TGLabel (TelegraphKit) — original study

Source of truth: `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGLabel.h` (39 lines)
and `.../TGLabel.m` (144 lines). Telegram for iOS v1.1, header copyright "Peter Iakovlev, 2013" (`TGLabel.h:6`).

## What it is for

`TGLabel` is the project's *only* general-purpose `UILabel` subclass, and it exists to solve four
specific annoyances of `UILabel` on iOS 5/6, nothing more. It carries no drawing of its own beyond
re-routing `drawRect:` into `drawTextInRect:`; every pixel of glyph rendering is still `UILabel`'s.

The four problems it solves:

1. **Vertical placement of text inside a taller box.** `UILabel` centres a single line in its bounds
   and gives you no hook. Telegram's navigation-bar titles need pixel-exact baselines that do not
   move when the font changes at rotation, so `TGLabel` overrides `textRectForBounds:limitedToNumberOfLines:`
   with an explicit top/centre alignment plus a manual nudge (`TGLabel.m:101-119`).
2. **Rotation without relayout.** Portrait and landscape fonts are stored on the label itself
   (`portraitFont`, `landscapeFont`, `TGLabel.h:25-26`) and swapped by a single `setLandscape:` call
   (`TGLabel.m:49-55`). The navigation bar walks its whole view tree and calls that selector on
   anything that responds to it (`TGNavigationBar.m:220-222`), so a label added to a title view gets
   its landscape font for free, with no controller code.
3. **Shadow colour that follows the highlighted state.** `UILabel` swaps `textColor` for
   `highlightedTextColor` when a cell is selected, but leaves `shadowColor` alone, which looks wrong on
   a blue selected row. `TGLabel` adds the missing pair (`TGLabel.m:41-47`).
4. **Staying opaque in a recycled cell.** `persistentBackgroundColor` makes the label refuse any
   attempt to set a different background while it is opaque (`TGLabel.m:57-81`) — a performance guard
   for scrolling table cells, where a non-opaque label forces off-screen blending.

Plus a fifth, effectively dead: `customDrawingOffset` / `customDrawingSize`, a way to draw a label's
text at an offset inside a larger frame. See "Dead surface" below.

## Public surface, verbatim

From `TGLabel.h:11-38`:

```
typedef enum {
    TGLabelVericalAlignmentCenter = 0,   // note the typo: "Verical", not "Vertical"
    TGLabelVericalAlignmentTop = 1
} TGLabelVericalAlignment;

@interface TGLabel : UILabel <TGReusableView>
@property NSString *reuseIdentifier;
@property UIColor  *normalShadowColor, *highlightedShadowColor;
@property UIFont   *portraitFont, *landscapeFont;
@property UIColor  *persistentBackgroundColor;
@property TGLabelVericalAlignment verticalAlignment;   // default 0 == Center
@property float verticalOffset, verticalOffsetMultiplier;
@property CGPoint customDrawingOffset;
@property CGSize  customDrawingSize;
- (void)setLandscape:(bool)landscape;
@end
```

The misspelling `Verical` is in the original and is reproduced in twelve verbatim
(`twelve/submodules/LegacyComponents/LegacyComponents/TGLabel.h`, unchanged by diff) — keep it, it is
the real identifier.

`<TGReusableView>` is TelegraphKit's own three-method recycling protocol —
`reuseIdentifier`, `prepareForReuse`, `prepareForRecycle:` (`TGReusableView.h:13-20`) — driven by
`TGViewRecycler` (`TGViewRecycler.h:13-19`). This is *not* `UITableViewCell` reuse; it is a manual
pool used by the message-bubble layout code.

## Behaviour, precisely

### Vertical alignment (`TGLabel.m:101-119`)

```
if (_customDrawingSize.height != 0) bounds.size = _customDrawingSize;   // line 104: BOTH dimensions
Center: textRect.origin.y = bounds.origin.y + (int)((bounds.size.height - textRect.size.height) / 2);
Top:    textRect.origin.y = bounds.origin.y;
both:   then offset by (int)(verticalOffset + verticalOffsetMultiplier * textRect.size.height)
```

Three details that matter for fidelity:

- The centring is **integer-truncated** (`(int)(...)`, line 108). With an odd leftover the text sits
  the half-point *up*, not down. On the 4S's 2x screen that is a visible half-pixel difference from a
  naive `roundf`.
- The nudge is truncated too (`(int)` on line 109/115), so `verticalOffsetMultiplier` values that
  produce sub-point results collapse to zero rather than blurring the text. This is deliberate: the
  whole point is crisp, non-antialiased text on a navigation bar.
- Since `verticalAlignment` is an enum with only two members and defaults to `Center` (value 0), the
  trailing `else` branch on line 117 is unreachable in practice. Every `TGLabel` in the app is either
  Center or Top.

### Drawing (`TGLabel.m:121-142`)

`drawRect:` ignores the dirty rect entirely and calls `drawTextInRect:self.bounds` (line 141). So the
label always redraws its full bounds; there is no partial invalidation. `drawTextInRect:` then computes
the aligned rect itself and hands the *aligned* rect to `super` (line 135) — which is why the override
of `textRectForBounds:` alone would not have been enough on iOS 6.

There is no early-out for empty text: an empty `TGLabel` still enters `super drawTextInRect:` and
draws nothing.

### Highlight (`TGLabel.m:41-47`)

The shadow swap only happens if **both** `normalShadowColor` and `highlightedShadowColor` are non-nil.
Setting only one is a silent no-op — a real trap, and the reason `TGDialogListCell` sets both plus
`shadowColor` explicitly (`TGDialogListCell.m:418-421`).

### Opaque / background (`TGLabel.m:57-81`)

Once `persistentBackgroundColor` is set and the label is opaque, `setBackgroundColor:` is *ignored*
and the persistent colour is re-applied instead (lines 67-73). If the label is not opaque, the
persistent colour is inert. Order matters: setting `persistentBackgroundColor` while already opaque
applies it immediately (lines 75-81).

### Reuse (`TGLabel.m:31-39`)

Both `prepareForReuse` and `prepareForRecycle:` are **empty**. A recycled `TGLabel` therefore keeps its
old text, font, colours and custom drawing values until the caller overwrites them. That is the
original contract, and the caller is responsible for full reconfiguration.

### Dead surface: customDrawingOffset / customDrawingSize

Grepping the whole v1.1 tree, the *only* place these are assigned is inside a commented-out block in
`Telegraph/Telegraph/TGContactCell.m:694-706` (the `/* ... */` runs from line 693 to 707). The intent
is visible there: draw a bold surname (`_titleLabelSecond`) into the same frame as the regular-weight
first name, shifted right by the measured width of the first name plus 5pt
(`TGContactCell.m:698-699`). By ship time the contact cell had moved to a single custom-drawn
`_contactContentsView` (`TGContactCell.m:709`), so **no live code path in v1.1 exercises this feature.**
Its clamping logic (`TGLabel.m:123-131`) is consequently untested-by-use, and note that with
`customDrawingSize.width == 0` and a non-zero height the original clamps the draw width to 0 and would
render nothing (line 125-126, and line 104 overwriting the whole `bounds.size`). Treat that as a latent
bug in the original, not as intended behaviour.

## How it is actually used (the real spec)

There are five distinct usage shapes across the app.

**1. Plain navigation-bar title** — `TGViewController.mm:443-467`.
Created lazily on `setTitleText:`, `backgroundColor` clear, `verticalAlignment = Top` (line 453),
fonts `boldSystemFontOfSize:20` portrait / `17` landscape (`TGViewController.mm:85, 92`),
colour `#ffffff`, shadow `#3d5c81`, shadow offset `(0, -1)` (`TGViewController.mm:139, 157, 173`).
Sizing ritual, and this is the part usually got wrong: set the frame to `(0,0,480,44)` first, call
`sizeToFit`, then **add 2 to the resulting height** (line 462), horizontally centre with `(int)`
truncation against `self.view.frame.size.width`, and set y to
`(int)(((portrait ? 44 : 32) - height) / 2) + 1` (line 465). The `+2` height and `+1` y together are
what stop the descenders of the bold 20pt title from being clipped by the tight `sizeToFit` box while
keeping the optical centre one point above the geometric one — a bar title looks low if you centre it
honestly. On rotation only `setLandscape:` is called (`TGViewController.mm:639`); the frame is not
recomputed, which is why the 480-wide starting box exists.

**2. Two-line chat title with a typing overlay** — `TGConversationController.mm:762-802`.
Three `TGLabel`s in one container. Title: `titleTitleFontForStyle` = bold 16 portrait / bold 15
landscape (`TGViewController.mm:103, 111`), colour `#ffffff`, shadow `#3d5c81` offset `(0,-1)`,
left-aligned, `NSLineBreakByTruncatingTail`, `verticalAlignment = Center` (lines 764-773).
Two status labels stacked in the same place — the normal one and a `typing` one at `alpha 0`
(line 800) that cross-fades in — both bold system 12, text `#e0eefd`, shadow `#3d5c81`, centred,
`verticalAlignment = Top` (lines 776-801).
Empty-content rule, and it is deliberate: the text is set to `@" "` (a single space) rather than `nil`
or `@""` when the model value is empty (lines 763, 777, 789). A single space preserves the label's
line height so the two-line stack does not jump when a subtitle is briefly unknown. Reproduce this.
The typing indicator's three dots live *inside* the typing label as a subview at `(-24, 5, 21, 10)`
with `clipsToBounds = false` (lines 799, 807-833), so they fade with it as one unit.

**3. Unread badge count** — `TGDialogListCell.m:416-429`.
Frame `(0,0,50,20)`, white text, bold system 14, `normalShadowColor` `#8091a6`, shadow offset
`(0,-1)`, `highlightedShadowColor` clear, `highlightedTextColor` `#2371c2`, clear background. The
badge inverts on row selection: on a blue selected row the white pill's number turns blue and loses
its shadow entirely. That inversion is the whole reason `normalShadowColor`/`highlightedShadowColor`
exist. The pill artwork behind it is a separate `UIImageView` with normal and highlighted images from
the assets source (`TGDialogListCell.m:410`), not drawn by the label.

**4. Table-cell text on an opaque white row** — `TGDialogListSearchCell.m:61-83` and
`TGPhoneItemCell.m:122-137`. Here the labels set `backgroundColor` to solid white (not clear) — the
opaque-row optimisation — with `highlightedTextColor` white for selection. Search cell: first name
system 19 `#000000`, last name bold system 19, subtitle system 13 `#808080`, all with white highlighted
text (`TGDialogListSearchCell.m:63-83`). Phone cell: label bold 13 `#5d708f` right-aligned in
`(4,13,62,16)`, value bold 15 black in `(78,11,width-80,20)` with flexible width and
`userInteractionEnabled = false` so taps fall through to the cell (`TGPhoneItemCell.m:122-137`).

**5. Tab-bar-hosted title** — `TGMainTabsController.m:501-518`, same recipe as (1) but with
`clipsToBounds = false` and a wrapper container, refreshed on rotation at line 544.

## Judging our port

Our file is `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGLabel.m` (101 lines) with
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGLabel.h`. The header is a faithful copy including the
`Verical` typo and the `<TGReusableView>` conformance, and we do ship `TGViewRecycler` /
`TGReusableView`. The implementation is a close and mostly correct port: highlight shadow swap,
`setLandscape:`, the persistent-background triad, the integer-truncated centring and the
`verticalOffset` / `verticalOffsetMultiplier` arithmetic are all byte-for-byte equivalent in effect.

The problems are these.

**a) Nothing uses it.** A grep for `TGLabel alloc` across `iTgLegacy/src` returns zero hits, and no
file outside `TGLabel.h/.m` mentions `verticalAlignment`, `portraitFont`, `landscapeFont`,
`setLandscape:`, `normalShadowColor`, `persistentBackgroundColor` or `customDrawing*`. Every title and
cell label in our port is a bare `UILabel` — e.g. `TGChatViewController.m:2883-2902` builds the chat
header from two plain `UILabel`s, and `TGChatListViewController.m:282-295` does the same for the row.
This is the finding that matters most: the class was ported as a file, not adopted as a component, so
none of the four behaviours it exists for are present anywhere in the running app.

The user-visible consequences, each traceable to a specific original line:

- **No shadow inversion on selected rows.** The unread badge in `TGDialogListCell.m:418-421` loses its
  `#8091a6` shadow and turns `#2371c2` when the row is pressed. Our chat-list cell
  (`TGChatListViewController.m:282-295`) sets only `highlightedTextColor`, so any shadow we apply
  stays on during selection and the highlighted state looks muddy.
- **No landscape font swap.** The original drops the bar title from bold 20 to bold 17 and the chat
  title from bold 16 to bold 15 on rotation (`TGViewController.mm:85/92, 103/111`), automatically, via
  the navigation bar's tree walk (`TGNavigationBar.m:216-222`). We have no equivalent, so a rotated
  4S shows a 20pt title in a 32pt bar.
- **No `+2` height / `+1` y title ritual** (`TGViewController.mm:462-465`). Our chat header hard-codes
  `name` at `y = 1` height 20 and `subtitle` at `y = 21` height 14 in a 40pt container
  (`TGChatViewController.m:2883, 2895`), which is a reasonable approximation but is not the original's
  measured-and-nudged placement and will drift for tall-ascender scripts.
- **Wrong title metrics in the chat header.** We use bold 17 (`TGChatViewController.m:2885`) where the
  original's two-line chat title is bold 16 portrait (`TGViewController.mm:103` via
  `TGConversationController.mm:765`), and system 12 for the subtitle where the original is *bold*
  system 12 (`TGConversationController.mm:779`). Our subtitle colour is `white @ 0.75` alpha
  (`TGChatViewController.m:2900`) where the original is the flat opaque `#e0eefd`
  (`TGConversationController.mm:780`) — a translucent white over the blue bar gradient gives a
  different, slightly greener tint than `#e0eefd` and changes with the gradient behind it.
- **No shadow on the chat subtitle at all.** The original gives it `#3d5c81` at `(0,-1)`
  (`TGConversationController.mm:781-782`); we give the name a generic `black @ 0.4` shadow
  (`TGChatViewController.m:2891`) and the subtitle none.
- **Empty subtitle collapses.** The original sets `@" "` for empty subtitles
  (`TGConversationController.mm:777, 789`) so the header never changes height; ours sets no such
  placeholder, so a chat with an unknown status can shift its title vertically when the status
  arrives.

**b) `prepareForReuse` is not the original's.** Ours clears text, highlight and the custom-drawing
values (`iTgLegacy/src/TGLabel.m:5-10`); the original's is empty (`TGLabel.m:31-34`). Defensible as an
improvement, but it changes the recycler contract: a caller that dequeues a label and only sets the
fields it knows changed will now get a blank label. Since we have no callers yet, decide now — I would
keep the original's empty body and make callers configure fully, because that is what the original's
`TGViewRecycler` users assume.

**c) `textRectForBounds:` diverges when `customDrawingSize.width == 0`.** Original line 104 overwrites
`bounds.size` entirely; ours sets height always and width only when positive
(`iTgLegacy/src/TGLabel.m:60-64`), and `drawTextInRect:` mirrors that with a `maxWidth` fallback
(`iTgLegacy/src/TGLabel.m:81-83`). Ours is the saner behaviour and the original's is arguably a bug —
but it is a deviation, and since the feature is dead in the original there is no screenshot that can
adjudicate it. Keep ours, and keep this note so nobody "fixes" it back.

**d) `drawTextInRect:` early-returns on empty text** (`iTgLegacy/src/TGLabel.m:78-79`), which the
original does not. Harmless in isolation, but it interacts with the `@" "` convention above: a single
space is not empty, so the guard does not fire, and behaviour matches. No change needed.

Fix list, in order: adopt `TGLabel` for the navigation titles and the chat-list badge; correct the
chat-header fonts and colours to bold 16 / bold 12 / `#e0eefd` / shadow `#3d5c81` at `(0,-1)`; add the
`@" "` empty-subtitle placeholder; wire `setLandscape:` from our navigation bar the way
`TGNavigationBar.m:216-222` does; then revisit `prepareForReuse`.

## What it became

**twelve** (`twelve/submodules/LegacyComponents/LegacyComponents/TGLabel.h/.m`): diffed against the
original, the class is *identical* apart from dropping the GPL header comment, dropping the
`<TGReusableView>` conformance from the interface, and deleting the two empty protocol methods. The
`reuseIdentifier` property survives, now orphaned. Nothing about the drawing, alignment, landscape or
shadow logic changed in the years between. That is a strong signal: this component was correct as
written and the pressure that eventually killed it was architectural, not behavioural — TelegraphKit's
hand-rolled `TGViewRecycler` was replaced, so the protocol went, and the label stayed.

**Telegram-iOS** (modern): there is no `UILabel` subclass any more. The same job is done by
`TextNode` / `ImmediateTextNode` in the Display submodule, drawn asynchronously off the main thread.
The concept that survived verbatim is vertical alignment: `ImmediateTextNode.verticalAlignment` is a
first-class `TextVerticalAlignment` passed straight into layout
(`submodules/Display/Source/ImmediateTextNode.swift:19, 101`), which is precisely `TGLabel`'s
`verticalAlignment` thirteen years on. What was abandoned: `portraitFont`/`landscapeFont` (the modern
client re-lays-out on size-class change rather than hot-swapping a font on a fixed frame),
`persistentBackgroundColor` (async-drawn nodes are composited differently and the opaque-row
optimisation is handled by the node system), and `normalShadowColor`/`highlightedShadowColor` (the flat
post-iOS-7 design has no text shadows to invert). Text shadow does still exist as
`textShadowColor` / `textShadowBlur` in the layout arguments (`ImmediateTextNode.swift:101`), but as a
static styling parameter, not a highlight-state pair.

Read that as: the *layout* problem TGLabel solved was real and permanent; the *rendering* problems it
solved were artefacts of skeuomorphic iOS 6 and of `UILabel` being synchronous, and both of those went
away for reasons unrelated to taste.

## Genuinely ambiguous

- Whether `verticalOffset` was ever set by anything. Grepping the tree finds no assignment outside
  `TGLabel.m` itself. It may have been used by code that was refactored away, exactly like
  `customDrawing*`. Our port should keep the property (it is cheap and harmless) but should not invent
  values for it.
- Whether the trailing `else` in `textRectForBounds:` (`TGLabel.m:117-118`) was meant to be a third
  "no alignment" mode. With the enum as declared it cannot be reached; do not try to expose it.

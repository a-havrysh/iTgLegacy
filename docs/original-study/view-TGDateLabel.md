# TGDateLabel — original study

Source of record:
`telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGDateLabel.h`
and `.../TGDateLabel.m` (Telegram for iOS v1.1, build 21024). Referenced below as
`TGDateLabel.h:N` / `TGDateLabel.m:N`.

The class exists under exactly that name; no substitution was needed.

---

## 1. What it is for

`TGDateLabel` is a `UILabel` subclass (`TGDateLabel.h:11`) whose only job is to render a
timestamp string in **two fonts**: the time itself in one size, and the trailing `AM`/`PM`
marker in a smaller size, nudged down by a per-call-site offset. It exists because in 2013 a
`UILabel` could not mix fonts (`NSAttributedString` support arrived in iOS 6, and Telegram
still shipped iOS 4/5), and because the app needed the AM/PM marker to occupy a **fixed-width
column** so that timestamps of different lengths still line up on their right edge.

Everything else it does — the disabled colour, the cached measurement, the manual centring —
exists to serve table-view cells that draw themselves and cannot afford `sizeToFit`.

It is used in seven places:

| Call site | file:line |
|---|---|
| Dialog list cell date (right of row) | `TGDialogListCell.m:387` |
| Message bubble timestamp | `TGConversationMessageItemView.mm:443` |
| Date tooltip (scrub callout) | `TGMessageDateTooltipView.m:44` |
| Image/video viewer caption bar | `TGImageViewControllerInterfaceView.m:113` |
| Contact cell subtitle ("last seen …") | `TGContactCell.m:339` |
| User menu item cell subtitle | `TGUserMenuItemCell.m:132` |
| Profile header status line | `TGProfileController.m:786` |

Note the last three: the class is *not* only a date renderer. Any string that may end in
` AM` / ` PM` — "last seen today at 4:12 PM" — is routed through it, which is why the header
is named after the label rather than after the date.

---

## 2. Public surface (`TGDateLabel.h:13-28`)

```
@property NSString *dateText;      // the string to display; parsed on set
@property NSString *rawDateText;   // the string as it was handed in, before AM/PM was split off
@property UIFont *dateFont;        // font used when there is NO am/pm marker
@property UIFont *dateTextFont;    // font used for the time when there IS a marker
@property UIFont *dateLabelFont;   // font used for the "AM"/"PM" glyphs themselves
@property UIColor *disabledColor;  // nil -> 0xaeaeae
@property float amWidth, pmWidth;  // fixed width reserved for the marker column
@property float dstOffset;         // vertical offset of the marker, in points, from the label top
@property bool isDisabled;
- (CGSize)measureTextSize;
```

`rawDateText` exists so a caller can cheaply test "is this the same string I already set"
without knowing that the setter mutated it; `TGImageViewControllerInterfaceView.m:373` is the
only user of that trick.

The naming is misleading in two places and both matter when porting:

* `dateFont` vs `dateTextFont` — these are *alternatives*, not two parts of one style.
  `dateFont` is used when `formatMode == None`, `dateTextFont` when a marker was found
  (`TGDateLabel.m:76` and `:123`). Only the dialog list actually gives them different values
  (`systemFontOfSize:13` vs `boldSystemFontOfSize:13`, `TGDialogListCell.m:391-392`); every
  other call site assigns the same font to both. The dialog list therefore renders 12-hour
  times *bold* and 24-hour times *regular* — an accident of this API, not a deliberate design,
  and worth knowing before "fixing" it.
* `dstOffset` has nothing to do with daylight saving. It is the y-origin of the AM/PM draw
  rect (`TGDateLabel.m:126`).

---

## 3. Parsing: how the marker is found (`TGDateLabel.m:39-69`)

```
if (dateText != _dateText)          // pointer comparison, not isEqualToString:
    if (TGUse12hDateFormat())
        if ([dateText hasSuffix:@" AM"] || [dateText hasSuffix:@" PM"])
            _dateText = [dateText substringToIndex:length - 3];
            _formatMode = Am | Pm;
```

Consequences, all observable:

* The split is **purely textual** and case-sensitive, keyed on the last three characters
  being exactly `" AM"` or `" PM"`. It is safe only because `TGDateUtils` hard-codes those
  literals rather than using `NSDateFormatter`'s localized `AMSymbol`
  (`TGDateUtils.mm:249-251` for `stringForShortTime:`, `:380-382` for the "today at …" form).
  A localized "a.m." or a Cyrillic marker would fall through to `formatMode = None` and be
  drawn in one font — which is exactly what happens in every non-English 24-hour locale, and
  is fine, because in 24-hour locales there is no marker at all.
* `TGUse12hDateFormat()` (`TGDateUtils.mm:153`, backed by `value_dateHas12hFormat` probed once
  from the locale) gates the split. In a 24-hour locale the label degrades to a plain
  single-font `UILabel` that happens to draw itself by hand.
* The guard is a **pointer** comparison. Handing in an equal-but-distinct `NSString` re-parses
  and re-displays; handing in the identical pointer is a no-op that also skips
  `setNeedsDisplay`. Cells rebuild the string every configure pass, so this never bites in
  practice, but it means the class is not safe as a "set the same value, get a redraw" sink.
* `setText:` is overridden (`TGDateLabel.m:32-37`) and **does not call `super`**. `self.text`
  stays `nil` forever. Consequences: `sizeToFit`, `intrinsicContentSize`, accessibility label
  and any `UILabel` auto-drawing are all dead. Everything must go through `measureTextSize`.
  This is deliberate — `drawRect:` is overridden too (`:129-132`), so `UILabel`'s own text
  drawing is bypassed entirely.
* Empty or `nil` text is never special-cased. It is safe by accident: `[nil sizeWithFont:]`
  returns `CGSizeZero` and `[nil drawAtPoint:withFont:]` is a no-op. Call sites hide the
  empty case themselves — `TGContactCell.m:504` sets `hidden` on the label when the subtitle is empty,
  `TGDialogListCell.m:1308` forces `dateWidth = 0` when `_date == 0`.

---

## 4. Measuring (`TGDateLabel.m:71-85`)

```
textSize = [_dateText sizeWithFont:(marker ? dateTextFont : dateFont)];
if (Am) textSize.width += amWidth;
if (Pm) textSize.width += pmWidth;
```

The measured width is **the time text plus a constant**, never the actual width of the "AM"
glyphs. `amWidth == pmWidth` at every single call site, so the reserved marker column is the
same for both and `9:05 AM` and `9:05 PM` are exactly the same width. That is the whole point
of the design: in the dialog list, the right-hand date column never jitters between morning
and afternoon rows.

The constants, all with the marker font they were sized against:

| Call site | amWidth/pmWidth | dateFont | dateLabelFont (marker) | dstOffset |
|---|---|---|---|---|
| Dialog list | 19 | sys 13 / **bold 13** | sys 11 | 2 |
| Message bubble | 15 | sys 11 | sys 9 | 1 + retinaPixel |
| Date tooltip | 17 | sys 12 | sys 10 | 1.5 |
| Image viewer | 18 | sys 13 | sys 11 | 2 |
| Contact cell | 19 | sys 13+retinaPixel | sys 11 | 3 |
| User menu cell | 19 | sys 13+retinaPixel | sys 11 | 3 |
| Profile status | 20 | sys 14 | sys 12 | 2 + retinaPixel |

Citations in order: `TGDialogListCell.m:388-393`; `TGConversationMessageItemView.mm:446-452`
with the fonts from `TGTelegraphConversationMessageAssetsSource.m:895-909` (`messageDateFont`
= system 11, `messageDateAMPMFont` = system 9); `TGMessageDateTooltipView.m:45-50`;
`TGImageViewControllerInterfaceView.m:116-122`; `TGContactCell.m:341-346`;
`TGUserMenuItemCell.m:134-139`; `TGProfileController.m:792-798`.

The reserved width is consistently a little more than the glyphs need: `"AM"` at system 11
measures roughly 17 pt, and 19 is reserved — the extra ~2 pt is the gap between the time and
the marker. There is no explicit space character anywhere; the gap *is* the slack in the
column. That is the reason a naive port that appends `" AM"` to the string looks tighter than
the original.

`_measuredTextSizeIsValid` caches the result and is invalidated only in `setText:`/
`setDateText:` (`:34`, `:43`). Changing a font after setting text does **not** invalidate it.
All call sites set fonts once at construction, so this is a latent bug, not a live one.

---

## 5. Drawing (`TGDateLabel.m:87-132`)

`drawRect:` simply forwards to `drawTextInRect:self.bounds` (`:129-132`), so the class draws
in *view* coordinates with the text origin at `(0,0)` of the label — the label is not padded
and its height is not used to vertically centre anything. Vertical placement is entirely the
caller's frame.

Order of operations:

1. **Centring** (`:91-98`). Only `UITextAlignmentCenter` is honoured, by translating the CTM
   by `floorf((frame.width - _measuredTextSize.width) / 2)`. Left is the default; **right
   alignment is not implemented** — set it and you get left. The only centred user is the
   image viewer, whose label is a fixed 140×20 box centred in the bar
   (`TGImageViewControllerInterfaceView.m:113`, `:115`).
2. **Shadow** (`:100-101`): `CGContextSetShadowWithColor(context, self.shadowOffset, 0.0f, …)`
   — blur is hard-wired to zero, so this is a 1-pixel hard offset shadow, never a soft one.
   Used by the image viewer (`0x000000` at 50 %, offset `(0,-1)`,
   `TGImageViewControllerInterfaceView.m:124-125`) and by the profile header (`0xedf0f5` at
   28 %, offset `(0,1)`, `TGProfileController.m:790-791`). The bubble sets `shadowOffset
   (0,1)` but `messageDateShadowColor` returns **nil**
   (`TGTelegraphConversationMessageAssetsSource.m:919-922`), so bubble timestamps have no
   shadow — the offset is dead code.
3. **Fill colour** (`:103-121`), in strict priority: `isDisabled` → `disabledColor` else the
   hard-coded `0xaeaeae` (`:111`); otherwise `highlighted ? highlightedTextColor : textColor`.
4. **Time text** (`:123`): `drawAtPoint:(0,0)` — no clipping, no truncation, no line breaking.
   Overlong text runs straight out of the label's bounds and is clipped only by the layer.
5. **Marker** (`:126`):
   `drawInRect:(0, dstOffset, _measuredTextSize.width, bounds.height)` right-aligned with
   `NSLineBreakByClipping`. Note the rect's width is the *measured* width including the
   reserved column, and the marker is pushed to its right edge — which is precisely how the
   fixed column is realised. Note also that this reads `_measuredTextSize` directly rather
   than calling `measureTextSize`: **if the caller never called `measureTextSize`, the width
   is zero and the marker is drawn right-aligned into a zero-width rect at x=0, i.e. it
   collides with the time text.** Every call site therefore calls `measureTextSize`
   explicitly before laying out: `TGDialogListCell.m:1306`, `TGConversationMessageItemView.mm:2188`,
   `TGMessageDateTooltipView.m:78`, `TGImageViewControllerInterfaceView.m:376`,
   `TGContactCell.m:502` and `:689`, `TGUserMenuItemCell.m:282`, `TGProfileController.m:1663`.
   This is the single sharpest edge in the class.

### Colours

| Where | textColor | highlighted | citation |
|---|---|---|---|
| Dialog list | `0x337acc` | white | `TGDialogListCell.m:394`, `:396` |
| Bubble | `0x232d37` | — | `TGTelegraphConversationMessageAssetsSource.m:911-916` |
| Tooltip | white @ 60 % | — | `TGMessageDateTooltipView.m:51` |
| Image viewer | white | — | `TGImageViewControllerInterfaceView.m:123` |
| Contact / user-menu cell | `0x888888` | white | `TGContactCell.m:347-348`, `TGUserMenuItemCell.m:141-142` |
| Profile status | `0x6d7d90` | — | `TGProfileController.m:788` |
| Disabled fallback | `0xaeaeae` | — | `TGDateLabel.m:111` |

No artwork. The class draws text only; every badge or plate behind it belongs to its host
(`_dateBackgroundView` in the bubble, `TGConversationMessageItemView.mm:3079`).

### Opacity, and why white is safe

The dialog list sets `backgroundColor = white`, `opaque = true`
(`TGDialogListCell.m:395-397`) — a deliberate 4S-era scrolling optimisation, since an opaque
layer skips blending. White text on a white background during selection would be invisible,
except that `UITableViewCell` clears its subviews' backgrounds for the duration of a
highlight and sets `highlighted` on contained `UILabel`s, which is what drives
`highlightedTextColor` at `TGDateLabel.m:118`. All other call sites use a clear background
because they sit on artwork.

### States and reuse

* **Highlighted** — inherited from `UILabel`, driven by the enclosing cell. No override.
* **Disabled** — `isDisabled` changes only the fill colour and, notably, does **not** call
  `setNeedsDisplay` (`TGDateLabel.h:26`; there is no custom setter in the `.m`). It works
  because the owner redraws around it: `TGContactCell.m:479` sets it in the same pass that
  sets `_contactContentsView.isDisabled`, and the contents view's `drawRect:` re-invokes the
  label's `drawRect:` manually (`TGContactCellContents.m:86-92` — it translates the CTM to
  the label's frame origin, forwards `highlighted`, and calls `[_dateLabel drawRect:]`
  directly, drawing the label *inside another view's* context). That is why the contact-cell
  variant sets `contentMode = UIViewContentModeLeft` and is never added as a subview.
  The matching disabled grey `0xaeaeae` appears again in `TGContactCellContents.m:77-79`.
* **Editing / swipe** — hosts fade the whole label: `_dateLabel.alpha = 0/1` in
  `TGDialogListCell.m:1531`, `:1555` and `TGConversationMessageItemView.mm:630`, `:657`.
* **Hidden** — bubbles hide the timestamp for service messages and for failed sends
  (`TGConversationMessageItemView.mm:2307-2308`, which also hides the badge behind it).
* **Reuse** — there is no `prepareForReuse` hook of any kind. The cell overwrites `dateText`
  on every configure (`TGDialogListCell.m:1132`), so stale state cannot survive.

### Geometry at the two main call sites

* **Dialog list** (`TGDialogListCell.m:1303-1310`): `dateWidth = (int)measureTextSize.width`,
  forced to 0 if `_date == 0`; frame `CGRectMake(width - dateWidth - 9, 9, 75, 15)` — origin
  computed from the measured width so the *text* ends 9 pt from the right edge, while the
  frame is a fixed 75×15 box that simply extends past it. The title's available width is then
  `dateFrame.origin.x - 4 - 73 - 18` (`:1311`), so a wide date directly shortens the title.
  Text is drawn at the frame origin, so anything wider than 75 pt would be clipped on the
  right; at 13 pt the worst realistic string (`12:05` + 19) is ~58 pt, so the box never fills.
* **Bubble** (`TGConversationMessageItemView.mm:2188-2189`, `:3071-3079`): the frame is set to
  exactly the measured size, then positioned — incoming at `bodyFrame.maxX + 12`, outgoing at
  `bodyFrame.minX - 26 - retinaPixel - width`, with `y = bodyFrame.maxY - 22`. The badge plate
  behind it is `width + 16` (incoming) or `width + 29` (outgoing, leaving room for the
  checkmarks) at height 21, offset `-3 - retinaPixel` vertically.

---

## 6. Our port

`iTgLegacy/src/TGDateLabel.h` / `TGDateLabel.m` is a faithful copy of the class, with three
deliberate and correct improvements:

* `drawTextInRect:` calls `measureTextSize` itself (`src/TGDateLabel.m:108`), closing the
  latent "marker drawn at x=0" trap described in §5.5.
* Font fallbacks when `dateFont`/`dateLabelFont` are unset (`src/TGDateLabel.m:59-73`).
* Zero `amWidth`/`pmWidth` falls back to the measured glyph width
  (`src/TGDateLabel.m:88-94`).

Two small semantic drifts inside the class, neither yet visible:

1. `src/TGDateLabel.m:41` uppercases the suffix before comparing, so a string ending in
   `" pm"` — a plain English sentence, say — would be silently truncated and re-rendered in
   two fonts. The original compares case-sensitively (`TGDateLabel.m:49-50`). Since our
   `TGDateUtils.mm:91-92` emits uppercase literals exactly as the original did, this only
   widens the blast radius; tighten it to match.
2. `src/TGDateLabel.m:29` guards on `isEqualToString:_rawDateText` instead of pointer
   identity. Strictly better, and harmless.

### The real defect is where the class is *not* used

`TGDateLabel` has exactly one consumer in our tree: the topics list
(`src/TGTopicsViewController.m:198-209`), which mirrors the dialog-list constants correctly
(19/19/2, sys 13 / bold 13 / sys 11, `0x337acc`, white highlight) and calls `measureTextSize`
before layout (`src/TGTopicsViewController.m:299`).

The **main chat list**, the screen this component was built for, reimplements the effect with
an attributed string on a plain `UILabel` (`src/TGChatListViewController.m:316-322`, composed
in `applyDateAppearance`, `:602-624`). Visible differences:

* **Marker column is gone.** We append the literal `" AM"` after the time
  (`src/TGChatListViewController.m:2945`) and let the attributed string measure naturally
  (`:624`). The original reserves a constant 19 pt (`TGDialogListCell.m:388-389`). Result:
  our AM and PM rows are not the same width, the right-hand column jitters between rows, and
  the gap before the marker is a single space instead of the original's ~2 pt of column slack.
  Fix: reserve a fixed 19 pt for the marker and right-align it in that column — i.e. use
  `TGDateLabel` here, which already does it.
* **Marker sits at the wrong height.** An attributed run is baseline-aligned, so our 11 pt
  `AM` shares a baseline with the 13 pt time. The original places the marker's *top* at
  `dstOffset = 2` from the label top while the time's top is at 0
  (`TGDateLabel.m:123` vs `:126`), which puts the marker slightly **above** the shared
  baseline. On a 4S at 13/11 pt this is roughly a one-to-two pixel difference and it reads as
  the marker "sitting low" in our build.
* **Clipping direction is inverted.** Ours is `NSTextAlignmentRight` in a 75 pt box
  (`src/TGChatListViewController.m:319`, frame at `:662`); the original is left-drawn in a
  75 pt box whose origin is derived from the measured width (`TGDialogListCell.m:1309`). The
  right edge lands identically at `width - 9`, so normal strings match exactly; only an
  over-75-pt string would clip on the opposite side. Not worth changing on its own.
* Ours is `backgroundColor = clear` in both the chat list (`:320`) and topics (`:208`); the
  original dialog list used opaque white for scroll performance
  (`TGDialogListCell.m:395-397`). On a 4S this is a genuine per-row blend cost in the one
  place where scrolling matters most. Worth restoring — but only together with the plate
  colour behind it, since our chat list now themes its background.

Second gap: **our message bubbles do not use it at all.** No file in `src/` other than
`TGTopicsViewController.m` references `TGDateLabel`, and no bubble code calls
`stringForShortTime:`, so the bubble timestamp's 11 pt / 9 pt split
(`TGConversationMessageItemView.mm:446-452`) is not reproduced anywhere. Whatever draws the
in-bubble timestamp today should be checked against the 15 pt reserved column,
`dstOffset = 1 + retinaPixel`, colour `0x232d37`, and no shadow.

Third gap: `isDisabled` has no consumer in our tree. Our contacts screen has no greyed-out
`0xaeaeae` subtitle for already-added members, which the original showed in the
add-participants flow (`TGContactsController.mm:1471`, `:1974-1987`).

---

## 7. What became of it

**twelve** (`twelve/legacy/TelegraphKit/TGDateLabel.m`) keeps the class essentially verbatim —
same parse, same constants API, same `dstOffset` marker draw — and adds exactly three things:

* an `_attributedDateText` path: `setAttributedText:` (`:74-81`) clears `dateText`, and both
  `measureTextSize` (`:88-94`) and `drawTextInRect:` (`:117-120`) short-circuit to the
  attributed string. This is the seam where the newer feature set (coloured/mixed timestamp
  runs) was bolted on once iOS 6+ made `NSAttributedString` drawing free.
* `setHighlighted:` is overridden to a **no-op** (`:109-111`), and the highlight branch is
  dropped from the fill-colour code (`:149`, versus `TGDateLabel.m:117-120`). Highlight-driven
  recolouring was abandoned.
* `float` → `CGFloat` on the three metric properties (`twelve/.../TGDateLabel.h:22-24`), a
  64-bit port artifact, and `floorf` → `CGFloor` (`:126`).

Both changes were forced, not taste: attributed text by new content types, `CGFloat` by arm64.
The two-font, fixed-column design itself survived untouched.

**Telegram-iOS (modern)** deletes the concept. `stringForShortTimestamp`
(`submodules/TextFormat/Sources/DateFormat.swift:92-124`) builds *one* string with the same
`AM`/`PM` literals and the same `12`-for-`0` hour rule as `TGDateUtils.mm:249-251`, but joins
it with a **non-breaking space** (`\u{00a0}`, `:115`) and renders it in a single font in
`ChatMessageDateAndStatusNode`. The `formatAsPlainText` flag (`:110-116`) exists solely to
swap that NBSP back to a normal space for copy/accessibility. So: the fixed-width column, the
second font, the vertical nudge and the manual `drawRect:` are all gone. Two forces did it —
text layout moved to AsyncDisplayKit where mixed runs are ordinary, and the modern bubble
timestamp is small and low-contrast enough that a distinct marker size no longer reads.

For us the modern behaviour is the wrong target: we are rebuilding the 2013 look, where the
smaller, slightly-raised, column-aligned `AM` is one of the details that makes the dialog
list recognisable.

---

## 8. Genuinely ambiguous

* Whether the dialog list's bold-in-12h/regular-in-24h asymmetry (`dateFont` = system 13 vs
  `dateTextFont` = bold 13, `TGDialogListCell.m:391-392`) was intentional cannot be settled
  from the source. It is the only call site that differs, and it produces a visibly different
  weight depending on the device's locale. Design-reference screenshots in a 12-hour locale
  would settle it; if we cannot settle it, matching the code exactly is the safe choice, and
  our topics cell already does (`src/TGTopicsViewController.m:202-203`).
* `dstOffset = 1.5f` in the tooltip (`TGMessageDateTooltipView.m:50`) is the only non-integer
  and the only value not adjusted by `retinaPixel`; whether that was a considered half-pixel
  or a leftover is not determinable.

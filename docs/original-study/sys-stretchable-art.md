# Stretchable art in Telegram for iOS 1.1 (build 21024)

How the 2014 client made one small PNG cover an arbitrary rectangle: which assets are
resizable, what cap each one gets, why, and where the original itself is inconsistent.

Everything below is cited against
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
(referred to as *original*), and measured with `sips` against the PNGs in
`Telegraph/Telegraph/Resources/`. All sizes are given in **points** (every shipped asset is
`@2x` only — there is no 1x copy of any of them in the tree — so points = pixels / 2).

---

## 1. The two APIs, and why the original uses both

| API | Availability | Stretch region |
| --- | --- | --- |
| `-stretchableImageWithLeftCapWidth:topCapHeight:` | since iOS 2 | **exactly one** row/column, at `x = leftCap`, `y = topCap`. Everything past it is the trailing cap. |
| `-resizableImageWithCapInsets:resizingMode:` | iOS 6.0 | the **whole middle** rectangle between the four insets. |

The original is written for an iOS 4.3–6 range, so every use of the iOS 6 API is guarded and
has a classic fallback:

```objc
if ([rawImage respondsToSelector:@selector(resizableImageWithCapInsets:resizingMode:)])
    image = [rawImage resizableImageWithCapInsets:UIEdgeInsetsMake(15, 23, 15, rawImage.size.width - 23 - 1) resizingMode:UIImageResizingModeStretch];
else
    image = rawImage;   // no stretching at all
```
(original `Telegraph/Telegraph/TGTelegraphConversationMessageAssetsSource.m:662-668`)

Two consequences that matter to us:

* **We ship to iOS 6.1.3, so we are always on the "yes" branch.** Every place where the
  original degrades — bare `image = rawImage`, `contentStretch`, a `backgroundColor` instead
  of a stretched header (`TelegraphKit/TelegraphKit/TGNavigationBar.m:173-183`) — is dead code
  for us. We should implement the iOS 6 branch and drop the fallback, not the reverse.
* The classic API's single stretch line is why almost every stretchable asset in the tree is
  an **odd** number of points wide or tall: the artist drew *cap + 1 + cap*. `Msg_In` is
  40×31; 15 + 1 + 15 = 31 vertically. Break that and the caps no longer add up.

---

## 2. The rule for choosing a cap

There is no constants file. The cap is chosen at the call site, and it always falls into one
of five families. Learn these five and you can predict almost every call in the codebase.

### (a) Centre cap — `width/2`, `height/2`

```objc
#define TGStretchableImageInCenterWithName(s,t) { UIImage *rawImage = [UIImage imageNamed:s]; \
    t = [rawImage stretchableImageWithLeftCapWidth:(int)((rawImage.size.width / 2)) topCapHeight:(int)((rawImage.size.height / 2))]; }
```
(original `Telegraph/Telegraph/TGInterfaceAssets.mm:14`)

Used when the artwork is **symmetric** — a rounded plate, a badge, a shadow ring, a progress
track. Because the classic API stretches one line, `w/2` on an odd-width image lands the
stretch column exactly on the middle pixel; on an even-width image it lands one pixel left of
centre and the right cap is one pixel narrower. The original never worries about this.

This is by far the most common form. Sample sites: unread badge
(`TGInterfaceAssets.mm:237,248`, `DialogListUnreadBadge` 27×21), search cancel button
(`TGInterfaceAssets.mm:199,210`), progress window plate
(`TelegraphKit/TelegraphKit/TGProgressWindow.m:28`), avatar/crop frame
(`TelegraphKit/TelegraphKit/TGImageCropController.m:155`), encryption-key plate
(`Telegraph/Telegraph/TGEncryptionKeyViewController.m:54`).

### (b) Centre cap horizontally, `topCapHeight:0` — the "fixed-height plate"

```objc
image = [rawImage stretchableImageWithLeftCapWidth:(int)(rawImage.size.width / 2) topCapHeight:0];
```

`topCapHeight:0` means *the entire height is the stretch region*, i.e. the vertical profile
is scaled, not preserved. The original uses it for artwork whose height is meant never to
change, and it says so by laying the view out at the art's own height:

```objc
TGHighlightableButton *button = [[TGHighlightableButton alloc] initWithFrame:CGRectMake(0, 0, 100, rawButtonImage.size.height)];
```
(original `Telegraph/Telegraph/TGButtonsMenuItemView.m:119-126`, `GroupedActionButton` 24×43)

**So `topCapHeight:0` is a contract, not a shortcut: the caller promises to lay the view out
at `image.size.height`.** Toolbar buttons (`TelegraphKit/TelegraphKit/TGToolbarButton.m:9-169`),
login plates, timestamp badges, delete buttons and tab-bar badges all obey it.

The one deliberate exception is `DialogListCell.png` (2×73), stretched
`leftCap:1 topCap:0` (`TelegraphKit/TelegraphKit/TGDialogListController.mm:1137`): a 2pt-wide,
row-height-tall vertical gradient stretched *horizontally* across the cell. Here the height is
already right and the width is the free axis.

### (c) Asset-relative cap — `width - N`, or `1`

Used when the interesting art is at **one end** and the other end is a plain edge that may be
repeated.

* `width - 1` — keep everything, stretch the last column. Left half of a segmented pair:
  `MapCalloutLeft` (`TelegraphKit/TelegraphKit/TGCalloutView.m:49`), the map button group
  (`TelegraphKit/TelegraphKit/TGMapViewController.m:306-313`), the dialog-list delete shadow
  (`TelegraphKit/TelegraphKit/TGDialogListCell.m:79`).
* `1` — the mirror image, for the right half of the same pair
  (`TGCalloutView.m:52`, `TGMapViewController.m:311`).
* `width - 16` — the country button on the login screen, which has a 16pt disclosure chevron
  baked into its right edge (`Telegraph/Telegraph/TGLoginPhoneController.m:166-167`).

The rule generalises: **the cap on the decorated side is the width of the decoration; the
other side gets whatever is left.**

### (d) Literal caps for artwork with a corner radius

Hand-tuned to the radius the designer drew, and repeated verbatim at every call site (there
is no shared constant, which is why they drift — see §6):

| Asset | Size (pt) | Cap | Site |
| --- | --- | --- | --- |
| `BackButton` (+`_Pressed`, `_Landscape`, `_Login`…) | 27×30 | `15, 0` | `TGToolbarButton.m:9-33`, `TGLoginPhoneController.m:129-132` |
| `HeaderButton` family | 21×30 | `6, 0` | `TGToolbarButton.m:41-65`, `:161` |
| `HeaderButton_Login` family | 21×30 | `11, 0` | `Telegraph/Telegraph/TGLoginCountriesController.m:184` |
| `ImagePickerGrayButton` / `…BlueButton` | — | `11, 0` | `TelegraphKit/TelegraphKit/TGImagePickerController.mm:524-541` |
| `TabBarBadge` | 20×20 | `10, 0` | `Telegraph/Telegraph/TGMainTabsController.m:164` |
| `DocumentLabelBg` | — | `8, 1` | `TGTelegraphConversationMessageAssetsSource.m:843` |
| `AttachedMessageBackground` (forwarded stripe) | — | `10, 5` | same file `:851` |
| `Call_Button` | — | `16, 15` | `TGInterfaceAssets.mm:390,398` |
| `Actions_Button` | — | `20, 22` | `TGInterfaceAssets.mm:491,499` |
| `DeletePhoto` / `ActionPhoto` | 24.5×43 | `13, 12` / `13, 13` | `TGInterfaceAssets.mm:597,619` |
| `TimelineImagePlaceholder` | 4×4 | `2, 2` | `TGInterfaceAssets.mm:515` |
| `CameraStripeTop` / `Bottom` | 10×68 | `6, 20` / `6, 0` | `Telegraph/Telegraph/TGCameraController.m:209,213` |
| `Cell96_Light` | 1×8 | `0, 1` | `TelegraphKit/TelegraphKit/TGImageSearchQueryCell.m:18` |
| `LoginInputDivider` | 1×41 | `0, 4` | `Telegraph/Telegraph/TGLoginPhoneController.m:188` |

The last two are the "hairline" idiom: `leftCap:0` (stretch freely across) plus a small
`topCapHeight` so the top few pixels and the whole bottom edge stay pixel-exact. Use it for
any 1pt-wide separator plate that must keep a crisp rule at one edge.

### (e) Four-sided insets (iOS 6 only) — grouped cells and the navigation bar

```objc
image = [rawImage resizableImageWithCapInsets:UIEdgeInsetsMake(5, 13, 6, rawImage.size.width - 13 - 1) resizingMode:UIImageResizingModeStretch];
```
(original `TGInterfaceAssets.mm:650`, and identically at `:674` and the disabled `:696`)

Applied to `GroupedCellTop/Middle/Bottom/Single_Selected` (29×44, `Single` 26×44). Note the
right inset `w - left - 1`: the author is emulating the classic API's *one-pixel* stretch
column inside the modern four-inset call. That idiom — `right = width - left - 1` — recurs
everywhere the two APIs coexist, and it is the single most useful thing to recognise when
porting a cap from one API to the other.

The navigation bar is the exception that uses a genuinely wide middle:

```objc
[rawPortrait resizableImageWithCapInsets:UIEdgeInsetsMake(0, 8, 0, 8)]
```
(original `TelegraphKit/TelegraphKit/TGNavigationBar.m:93`, `Header_Corners` 44×44) — 8pt of
corner art at each end, everything between is free, and vertical insets of 0 mean the bar art
scales to whatever height the bar has (44 portrait, 32 landscape).

---

## 3. The message bubble — the one asset with real rules

This is the part that gets mis-copied, so it is worth stating completely.

### The assets

| Asset | Size (pt) | Role |
| --- | --- | --- |
| `Msg_In` | 40×31 | incoming, one line |
| `Msg_Out` | 40×31 | outgoing, one line |
| `Msg_In_High` | 40×48 | incoming, **two lines or more** |
| `Msg_Out_High` | 40×48 | outgoing, two lines or more |
| `Msg_In_Selected`, `Msg_Out_Selected` | 40×31 | highlight overlay, short |
| `Msg_In_High_Selected`, `Msg_Out_High_Selected` | 40×48 | highlight overlay, tall |
| `Msg_In_Selected_Shadow`, `Msg_Out_Selected_Shadow` | 40×31 | shadow drawn *inside* the highlight view |

(measured in `Telegraph/Telegraph/Resources/`)

### The caps

```objc
// short
[[UIImage imageNamed:@"Msg_In.png"]  stretchableImageWithLeftCapWidth:20 topCapHeight:15];   // :652
[[UIImage imageNamed:@"Msg_Out.png"] stretchableImageWithLeftCapWidth:15 topCapHeight:15];   // :721
// tall
[Msg_In_High  resizableImageWithCapInsets:UIEdgeInsetsMake(15, 23, 15, w - 23 - 1) …];       // :664
[Msg_Out_High resizableImageWithCapInsets:UIEdgeInsetsMake(15, 17, 15, w - 17 - 1) …];       // :734
```
(all in original `Telegraph/Telegraph/TGTelegraphConversationMessageAssetsSource.m`)

Read the numbers geometrically:

* **Short, incoming:** left cap 20, stretch column at x=20, right cap 19. The tail hangs off
  the left; 20pt covers tail + left corner.
* **Short, outgoing:** left cap 15, right cap 24 — the tail is on the *right*, so the right
  cap is the fat one. The asymmetry between 20/19 and 15/24 is the whole point: **the cap on
  the tail side must be at least tail width + corner radius.**
* **Vertically both are `15, 15`** on a 31pt image: 15 + 1 + 15. The bubble's vertical
  gradient is preserved top and bottom, and only the middle scanline repeats.
* **Tall variants** move the horizontal cap outward (23 incoming, 17 outgoing) because the
  taller artwork draws a longer tail curve, and keep the same vertical 15/15.

### The switch: 48 points

```objc
if (layout.size.height >= 48) { …Double… } else { …Single… }
```
(original `TelegraphKit/TelegraphKit/TGConversationMessageItemView.mm:2406-2435`, and the same
threshold for the highlight view at `:2376-2398`)

`layout.size.height` is the laid-out bubble height. 48 is exactly the height of the `_High`
artwork, so the rule is really "if the bubble is at least as tall as the tall art, use the
tall art". A one-line bubble is 31pt (which is why `Msg_In` is 31pt tall); two lines cross 48.

`updateBackground:` is also where the *view-side* insets live, duplicated as literals with the
image width hard-coded to 40:

```objc
_messageNormalBackgroundView.stretchInsets = UIEdgeInsetsMake(15, 23, 15, 40 - 23 - 1);   // incoming
_messageNormalBackgroundView.stretchInsets = UIEdgeInsetsMake(15, 17, 15, 40 - 17 - 1);   // outgoing
```
(`TGConversationMessageItemView.mm:2413,2427`)

These are consumed by a private `UIImageView` subclass that only does anything on iOS 5:

```objc
needsStretching = ![UIImage instancesRespondToSelector:@selector(resizableImageWithCapInsets:resizingMode:)];
if (needsStretching && _enableStretching)
    self.contentStretch = CGRectMake(left/w, top/h, 1 - (left+right)/w, 1 - (top+bottom)/h);
```
(`TGConversationMessageItemView.mm:116-147`)

On our target that branch never runs — the cap insets baked into the image do the work. But
the numbers there are the authoritative cross-check that the insets in the assets source are
intentional and not a typo.

### The highlight (selected) bubble

Selection is a **second image view stacked under/over the normal one**, not a tint:
`_messageHighlightedBackgroundView` gets `Msg_*_Selected` (short) or `Msg_*_High_Selected`
(tall, same 23/17 insets), and then a **child** `UIImageView` filling its bounds with
`Msg_*_Selected_Shadow`, added by `-setShadowImage:`
(`TGConversationMessageItemView.mm:150-160`, images at
`TGTelegraphConversationMessageAssetsSource.m:681,692,754,765`). The shadow child is
autoresized to the parent's bounds, so it is stretched by *scaling*, not by cap insets — the
only place in the whole client where a bubble-layer PNG is knowingly distorted.

### Media bubbles do not stretch at all

Photo/video attachments are composited once at their final size using
`AttachmentPhotoBubble` (29×31) as a centre-capped overlay
(`TelegraphKit/TelegraphKit/TGImageUtils.mm:430-436`, and the avatar variant at
`Telegraph/Telegraph/TGTelegraph.mm:514`). The result is a *bitmap*, cached — no resizable
image reaches the view. Anything with a rounded corner over live pixels is baked, not capped.

---

## 4. What the modern client did with the idea

`Telegram-iOS/submodules/TelegramPresentationData/Sources/ChatMessageBubbleImages.swift`
abandoned shipped bubble PNGs entirely. The bubble is drawn with Core Graphics from a fixed
33pt "main diameter" plus a 6pt tail (`:192-193`), and the stretch point is *derived from the
geometry* rather than typed in:

```swift
let outgoingStretchPoint: (x: Int, y: Int) = (Int(additionalInset + strokeInset + round(fixedMainDiameter / 2.0)) - 1, …)
let incomingStretchPoint: (x: Int, y: Int) = (Int(sourceRawSize.width) - outgoingStretchPoint.x + Int(additionalInset), outgoingStretchPoint.y)
…
return drawingContext.generateImage()!.stretchableImage(withLeftCapWidth: incoming ? incomingStretchPoint.x : outgoingStretchPoint.x, topCapHeight: …)
```
(`:198-199`, `:427`)

Three things changed, and each of them tells us why the 2014 approach hurt:

1. **The Single/Double split is gone.** Because the shape is vector, the corner radius is
   constant at any height, so one image serves every bubble. The 2014 `_High` variant exists
   only because a *painted gradient and tail* cannot be stretched from 31pt to 90pt without
   the tail curve visibly flattening.
2. **The cap is computed, never literal.** `round(diameter/2)` and `width - x` mean a theme
   change cannot desynchronise cap from art. The 2014 client had the same number typed in
   four places (`:664`, `:734`, `ItemView:2413`, `:2427`) — see §6.
3. **Tail presence became a per-message decision** (`minRadiusForFullTailCorner`, neighbour
   merging), which is exactly the "message grouping" feature the 2014 asset set could not
   express: there is no tail-less `Msg_In` in the 2014 resources.

`twelve` (`Telegraph/TGTelegraphConversationMessageAssetsSource.m:725-760`) still carries the
2014 code **byte-identical** — same 20/15, same `(15, 23, 15, w-23-1)`, same commented-out
fallback. Where it extended the system it did so with the iOS 6 API only and with symmetric
insets: `resizableImageWithCapInsets:UIEdgeInsetsMake(18, 10, 18, 1)` /
`(18, 1, 18, 10)` / `(18, 2, 18, 2)` for the left/right/middle of the sticker suggestion strip
(`Telegraph/TGStickerAssociatedInputPanel.m:60-62`) — i.e. family (c) restated in four-inset
form, plus runtime tinting (`TGTintedImage(...)` then re-cap, `:107-109`). That is the pattern
to follow when we add a new stretchable component: **tint first, cap after** — a cap applied
before a redraw is lost.

---

## 5. Our port, judged

Scope: `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src` contains 118 calls to
`stretchableImageWithLeftCapWidth:topCapHeight:` and **zero** to
`resizableImageWithCapInsets:`. That single fact is the root of defects 1 and 2.

### D1 — Tall bubbles use the short artwork. *(the big one)*

`src/TGChatViewController.m:7642-7663` (`-applyBubbleArtworkTo:outgoing:`) always loads
`Msg_In`/`Msg_Out` and always applies `leftCap: mine ? 15 : 20, topCap: 15`. There is no
height test and no `_High` path. Every multi-line bubble in the app is a 31pt tail stretched
to 60–200pt, so the tail curve and the top/bottom gradient bands are wrong on every bubble
longer than one line — which is most of them.

Fix, per original `TGTelegraphConversationMessageAssetsSource.m:662-668,732-738` and
`TGConversationMessageItemView.mm:2406-2435`:

```objc
if (bubbleHeight >= 48.0f) {
    UIImage *raw = [UIImage imageNamed:(mine ? @"Msg_Out_High" : @"Msg_In_High")];
    CGFloat left = mine ? 17.0f : 23.0f;
    art = [raw resizableImageWithCapInsets:UIEdgeInsetsMake(15, left, 15, raw.size.width - left - 1)
                              resizingMode:UIImageResizingModeStretch];
} else {
    art = [raw stretchableImageWithLeftCapWidth:(mine ? 15 : 20) topCapHeight:15];
}
```

The threshold is the bubble's laid-out height (`cell.bubble.frame.size.height` before the
`kBubbleMinH` clamp), matching `layout.size.height` in the original.

### D2 — `Msg_In_High@2x.png` is not shipped.

`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/images/` has `Msg_Out_High@2x.png`,
`Msg_In_High_Selected@2x.png` and `Msg_Out_High_Selected@2x.png` but **no
`Msg_In_High@2x.png`** — the incoming tall bubble, i.e. the most common bubble in the app.
Also missing: `Msg_In_Selected_Shadow@2x.png` and `Msg_Out_Selected_Shadow@2x.png`. All five
exist at `telegram_iphone.src/Telegraph/Telegraph/Resources/` and must be copied before D1 can
be fixed. (This is why D1 probably went unnoticed: whoever tried it got `nil` and reverted.)

### D3 — Selection has no shadow layer.

`src/TGChatViewController.m:7647-7651` swaps the *same* image view to `Msg_*_Selected` and
falls back to the unselected art if it is missing. The original keeps a separate highlight
view plus a `Msg_*_Selected_Shadow` child filling its bounds
(`TGConversationMessageItemView.mm:150-160`). Without the shadow child, a selected bubble
reads flat against the wallpaper.

### D4 — `GroupedActionButton` is capped three different ways, one of them broken.

The asset is 24×43pt (`images/GroupedActionButton@2x.png`, 48×86px), and the original always
uses `width/2 = 12`, `topCap 0`, with the button laid out at 43pt tall
(`Telegraph/Telegraph/TGButtonsMenuItemView.m:119-126`). Ours:

* `src/TGStickerPanelView.m:228,230,978,981` — `leftCap: 24`. **24 ≥ image width**, so there
  is no stretchable column at all; UIKit clamps and the plate renders with a squashed or
  duplicated right edge. Change to `(int)(raw.size.width / 2)`.
* `src/TGSettingsViewController.m:2742-2748` and `:2864-2870` — `width/2, 0`. Correct.
* `src/TGChatListViewController.m:248-249` — `width/2, height/2`. Wrong family: this is a
  fixed-height button (family b), not a symmetric plate (family a). With `topCap: 21` a
  button laid out at anything but 43pt stretches the middle of the gradient instead of
  scaling it. Use `topCapHeight:0` and lay the button out at 43pt.

Same asset, same app, three answers. Pick `width/2, 0` and make it one helper.

### D5 — `ButtonGroupDivider` cap exceeds the asset.

`src/TGStickerPanelView.m:1558` uses `leftCap: 6` on `ButtonGroupDivider` (2×30pt). Same
clamping problem as D4, and pointless besides — the view is created 2pt wide two lines above
(`src/TGStickerPanelView.m:1556-1557`). Drop the stretch and assign the raw image.

### D6 — Reaction plates stretch bubble art vertically.

`src/TGReactionPickerView.m:1690-1706` builds a chip from `Msg_*_Selected` /
`Msg_*_High_Selected` with `topCapHeight:0` and a computed `MIN(18, w/2 - 1)` left cap.
`topCap 0` scales the bubble's vertical gradient and its tail to the chip height; the original
never applies a zero vertical cap to bubble artwork — it is always `15` (`…AssetsSource.m:681,
692,754,765`). Use `topCapHeight:15` for the 31pt art, or the `(15, 23/17, 15, w-x-1)` insets
for the 48pt `_High` art, and let the chip height decide which. The generic helper at
`src/TGReactionPickerView.m:115-126` does clamp the cap to `width - 1`, which is the right
defensive move and should be lifted into a shared helper for the whole port.

### D7 — `CategoryDivider` stretched with no caps at all.

`src/TGChatEventsViewController.m:1315` does `stretchableImageWithLeftCapWidth:0 topCapHeight:0`
on `CategoryDivider` (1×26pt) and then sizes the view to `TGEventsHeaderHeight`. Both caps
zero means both axes scale freely, so the plate's top/bottom hairlines blur whenever the
header height differs from 26pt. The original ships this asset but — honestly — never
references it from code (only `Telegraph/Telegraph.xcodeproj/project.pbxproj:1153`), so there
is no authoritative cap. The nearest precedent is `Cell96_Light`, a 1pt-wide plate stretched
`leftCap:0 topCap:1` (`TelegraphKit/TelegraphKit/TGImageSearchQueryCell.m:18`). Adopt that.
`src/TGStickerPanelView.m:927` already uses `leftCap:1 topCap:0` on the same asset — also
undocumented, also inconsistent with D7. Pick one.

### What is right (no action)

* `DialogListCell` at `leftCap:1 topCap:0` — `src/TGChatListViewController.m:381,383,753`,
  `src/TGTopicsViewController.m:82,241-243`, `src/TGSavedMessagesViewController.m:704-706` all
  match original `TelegraphKit/TelegraphKit/TGDialogListController.mm:1137-1138`.
* `HeaderButton_Login` at `11, 0` — `src/TGCountryPickerViewController.m:461-462` matches
  original `Telegraph/Telegraph/TGLoginCountriesController.m:184`.
* Login country button at `width - 16, 0` — `src/TGLoginViewController.m:481-483` matches
  original `Telegraph/Telegraph/TGLoginPhoneController.m:166-167` exactly.
* `LoginInputDivider` at `0, 4` — `src/TGLoginViewController.m:530` matches original
  `TGLoginPhoneController.m:188`.
* Popup/actions menu ends at `width - 1` / `0` — `src/TGPopupMenu.m:274-283`,
  `src/TGActionsMenu.m:348-357` reproduce the family-(c) pairing correctly.
* `CameraStripeTop/Bottom` at `6, 20` / `6, 0` — `src/TGVideoCaptureViewController.m:218,266`
  matches original `Telegraph/Telegraph/TGCameraController.m:209,213`.
* `DialogListUnreadBadge` at `13, 10` — `src/TGSavedMessagesTagsViewController.m:39` equals
  the centre cap of the 27×21 asset, so it is right, but it is *hard-coded* where the original
  computes it (`TGInterfaceAssets.mm:237`). Prefer `w/2, h/2`.

---

## 6. Where the original contradicts itself

Documented rather than smoothed over, because copying either side blindly is how we got here.

1. **Bubble caps are duplicated, not shared.** `23`/`17` appear both in the assets source
   (`…AssetsSource.m:664,734`) and again as literals in the view
   (`TGConversationMessageItemView.mm:2413,2427`), with `40` hard-coded as the image width in
   the second copy. They happen to agree in 1.1; nothing enforces that.
2. **Short vs tall incoming caps disagree.** Short incoming uses `20`; tall incoming uses `23`
   for what is the same tail drawn taller. Either the tail widens in `Msg_In_High` or one of
   the two is off by 3. The assets are 40pt wide in both cases, so a bubble crossing the 48pt
   threshold shifts its stretch column by 3pt mid-animation. Reproduce it — it is what the
   client did — but do not "fix" one to match the other.
3. **Outgoing highlight never got the tall treatment.** `messageBackgroundBubbleOutgoingHighlighted`
   has its `resizableImageWithCapInsets:` line commented out with slightly different numbers
   `(14, 16, 15, w - 16)` (`…AssetsSource.m:751-754`) — note `w - 16`, missing the `- 1` used
   everywhere else. Dead code, but it shows the `-1` idiom was a late correction.
4. **The grouped-cell fallback caps are three different guesses.** For iOS 5 the top and
   middle cells fall back to `topCapHeight: height - 2`, the bottom to `1`, and the single to
   `height/2` (`TGInterfaceAssets.mm:652,676,698,720`). `groupedCellBottomHighlighted` also has
   its modern branch disabled with `if (false && …)` (`:695`). Irrelevant on iOS 6, but a
   warning: do not port an original's fallback branch believing it is the intended geometry.
5. **`Msg_In`/`Msg_Out` are even-width (40pt) with `topCap 15` on 31pt height.** Vertically the
   maths is exact (15+1+15); horizontally `20 + 1 + 19` and `15 + 1 + 24` are not centred and
   were never meant to be. Do not "round" these to `width/2`.

---

## 7. Checklist for adding a stretchable asset to our port

1. Measure the PNG. Points = px/2. If it is meant to stretch on an axis, that axis should be
   *odd* in points (cap + 1 + cap).
2. Classify: symmetric plate → (a) `w/2, h/2`; fixed-height plate → (b) `w/2, 0` **and lay the
   view out at `image.size.height`**; one decorated end → (c) `w - decorationWidth` or `1`;
   corner radius → (d) literal = radius + any baked edge; needs a wide middle or an asymmetric
   pair of caps → (e) `resizableImageWithCapInsets:` with `right = w - left - 1`.
3. Never let a cap reach `width` or `height`; clamp to `size - 1` (the helper at
   `src/TGReactionPickerView.m:115-126` already does this — reuse it).
4. Cap after any tint or redraw, never before (`twelve/Telegraph/TGStickerAssociatedInputPanel.m:107-109`).
5. If the art has a painted tail or a strong vertical gradient and the view height varies by
   more than ~50%, you need a second asset, not a cleverer cap. That is what `Msg_*_High` is,
   and the 48pt threshold is how the original chose between them.

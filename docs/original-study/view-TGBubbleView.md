# TGBubbleView — the message bubble background

## Naming: the class does not exist

There is no `TGBubbleView` anywhere in Telegram for iOS v1.1 (build 21024). Searching the whole
tree for `bubble` returns only two hits outside the Xcode project file and one image utility:
the assets protocol and the message cell.

```
$ grep -ril bubble telegram_iphone.src
Telegraph/Telegraph/TGTelegraphConversationMessageAssetsSource.m
TelegraphKit/TelegraphKit/TGConversationMessageAssetsSource.h
TelegraphKit/TelegraphKit/TGConversationMessageItemView.mm
TelegraphKit/TelegraphKit/TGImageUtils.mm
```

The real class is **`TGConversationMessageItemBackgroundView`**, a 48-line `UIImageView` subclass
declared and implemented privately inside `TGConversationMessageItemView.mm:115-162`. It has no
header, no separate file, and no callers outside that one translation unit. Everything below is
about that class plus the two collaborators that give it meaning: the asset factory
(`TGTelegraphConversationMessageAssetsSource.m`) and the layout/geometry code in the cell
(`TGConversationMessageItemView.mm`).

The important structural fact, and the one our port has partly missed: **the 2013 bubble is not
drawn. It is a nine-part stretchable PNG, tail and border and inner gradient baked in.** There is no
`cornerRadius`, no `borderWidth`, no separately-composited tail image. The bubble view is a dumb
image view whose only job is to pick the right PNG and get the stretch right on iOS 4/5.

---

## 1. The class itself

`TGConversationMessageItemView.mm:115-121`

```objc
@interface TGConversationMessageItemBackgroundView : UIImageView
@property (nonatomic) bool enableStretching;
@property (nonatomic) UIEdgeInsets stretchInsets;
@property (nonatomic, strong) UIImageView *shadowView;
@end
```

Three additions to `UIImageView`, each with a precise reason.

**`setImage:` — the iOS 4/5 fallback** (`:125-148`). It calls super, then checks *once*, cached in a
function-static, whether `UIImage` responds to `resizableImageWithCapInsets:resizingMode:`
(`:134`). That selector is iOS 6+. On an older system, cap insets are unavailable, so the view
falls back to `contentStretch`, converting the pixel insets in `stretchInsets` into the normalised
0..1 rect that `contentStretch` wants (`:145`):

```
contentStretch = (left/w, top/h, 1 - (left+right)/w, 1 - (top+bottom)/h)
```

If the image has zero size it degrades to the full unit rect (`:143`) rather than dividing by zero.
Note that the branch only runs when `_enableStretching` is true (`:139`) — so on iOS 5 a
non-stretching bubble keeps whatever `contentStretch` it had. In practice the view is either always
stretching or always not for a given message state, and `updateBackground:` sets both the flag and
the insets together every time.

**`setShadowImage:`** (`:150-160`). Lazily creates a child `UIImageView` filling the bounds with
`FlexibleWidth|FlexibleHeight`, and sets its image. The shadow is a *sibling image inside the
bubble*, not a `CALayer` shadow — on a 4S, a real `layer.shadowPath` per row would have been
unaffordable. Only the highlighted (context-selected) bubble ever gets a shadow image
(`:2388`, `:2404`); the normal bubble never calls `setShadowImage:`, so `shadowView` stays nil.

The class overrides nothing else. Hit-testing, reuse, and tap handling all live in the cell.

---

## 2. The artwork

Ten PNGs, all `@2x` only in the original resources, all **40 × 31 pt** for the single variants and
**40 × 48 pt** for the "High" (tall) variants (`sips` on
`Telegraph/Telegraph/Resources/Msg_In@2x.png` → 80 × 62 px; `Msg_In_High@2x.png` → 80 × 96 px).

| Asset | Accessor | Caps / insets | Source line |
|---|---|---|---|
| `Msg_In.png` | `messageBackgroundBubbleIncomingSingle` | `stretchableImageWithLeftCapWidth:20 topCapHeight:15` | assets source `:652` |
| `Msg_In_High.png` | `…IncomingDouble` | `capInsets (15, 23, 15, w-23-1)`, `Stretch` | `:664` |
| `Msg_In_Selected.png` | `…IncomingHighlighted` | `leftCap 20, topCap 15` | `:681` |
| `Msg_In_Selected_Shadow.png` | `…IncomingHighlightedShadow` | `leftCap 20, topCap 15` | `:692` |
| `Msg_In_High_Selected.png` | `…IncomingDoubleHighlighted` | `capInsets (15, 23, 15, w-23-1)` | `:705` |
| `Msg_Out.png` | `…OutgoingSingle` | `leftCap 15, topCap 15` | `:721` |
| `Msg_Out_High.png` | `…OutgoingDouble` | `capInsets (15, 17, 15, w-17-1)` | `:734` |
| `Msg_Out_Selected.png` | `…OutgoingHighlighted` | `leftCap 15, topCap 15` | `:754` |
| `Msg_Out_Selected_Shadow.png` | `…OutgoingHighlightedShadow` | `leftCap 15, topCap 15` | `:765` |
| `Msg_Out_High_Selected.png` | `…OutgoingDoubleHighlighted` | `capInsets (15, 17, 15, w-17-1)` | `:778` |

(All line numbers in `Telegraph/Telegraph/TGTelegraphConversationMessageAssetsSource.m`.)

Every accessor is a `static UIImage *image` memoised on first call — one instance per app run, never
per cell. On iOS < 6 the "Double" accessors return the **raw, unstretched** image (`:668`, `:709`,
`:738`, `:782`), because cap insets are unavailable there; that is exactly the case the background
view's `contentStretch` fallback covers, and why the cell must also pass the same numbers again as
`stretchInsets`. The commented-out `//image = [self messageBackgroundBubbleIncomingSingle];` in each
of those branches shows an abandoned earlier fallback.

**Why the cap numbers differ per side.** The incoming left cap is 20 and the outgoing left cap is
15: the tail lives on the left of `Msg_In` and on the right of `Msg_Out`, so the frozen (non-scaled)
region has to cover the tail plus the corner. For the "Double" images, cap insets are specified as
`(top=15, left, bottom=15, right = imageWidth - left - 1)`, i.e. the stretchable strip is exactly
**one pixel wide** — the whole image is frozen except a single column at `x = left`. Since the image
is 40 pt wide, `right` evaluates to `40 - 23 - 1 = 16` incoming and `40 - 17 - 1 = 22` outgoing;
those literal numbers are re-derived at `TGConversationMessageItemView.mm:2379/2395/2413/2427` as
`UIEdgeInsetsMake(15, 23, 15, 40 - 23 - 1)` etc. Vertically, top and bottom caps of 15 leave a
1 pt-tall stretchable row in the 31 pt single image and an 18 pt band in the 48 pt tall image.

---

## 3. State machine: which PNG, when

All of it is `updateBackground:` (`TGConversationMessageItemView.mm:2367-2436`). Two orthogonal
inputs, no others:

1. `_message.outgoing` → In vs Out artwork.
2. `layout.size.height >= 48` → Double ("High") vs Single artwork, **and** `enableStretching`
   on/off (`:2376`, `:2392`, `:2410`, `:2424`).

The 48 is not arbitrary: it is the pixel height of the tall artwork (40 × 48 pt). A bubble shorter
than the tall PNG cannot use it, so anything under 48 pt gets the 31 pt single image, stretched by
plain caps. At 48 pt and above the tall image takes over, because its taller tail region looks right
against several lines of text, where a 31 pt tail stretched to 90 pt would smear.

The highlighted (long-press / context-selected) layer is a *second* instance of the same class,
created lazily the first time the cell is context-selected (`:723-731`), inserted directly above the
normal one, and given the `_Selected` artwork plus a `_Selected_Shadow` child. It goes through the
same >= 48 branch. Selection is a **cross-fade of two full bubbles**, not a tint:
`setIsContextSelected:animated:` (`:717-809`) animates `_messageHighlightedBackgroundView.alpha`
0→1 over **0.3 s** and removes it from the hierarchy on the way back out (`:771-780`). Un-animated
selection just snaps both alphas (`:796-798`). Note `_messageNormalBackgroundView.alpha` is set to
0 while selected (`:796`) — the two bubbles are never both visible; the highlight is a replacement,
not an overlay.

There is no pressed/`highlighted` state driven by touch-down. A message bubble in 2013 does not
flash on tap; only the long-press context selection changes it.

### Media: the bubble disappears entirely

`layout.hideBackground = hasImage` (`:993`), where `hasImage` is true for image, video and location
attachments, and for the `TGMessageActionChatEditPhoto` action (`:953-965`). Then
`_messageNormalBackgroundView.hidden = isAction || layout.hideBackground` (`:2234`). So a photo
message has **no bubble at all** — its rounded corners come from the separate
`messageAttachmentImage{Incoming,Outgoing}{Top,Bottom}Corners` assets in the assets protocol
(`TGConversationMessageAssetsSource.h:111-118`). Selecting such a message instead adds a third view,
`_messageHighlightedForegroundView`, built from `MsgAttachmentHighlightedOverlay.png` stretched from
its own centre (`:737-743`), inset from the body frame by `y+3`, `height-5.5`, `x + 3.5` outgoing /
`+7.5` incoming, `width-11` (`:756-761`, repeated in layout at `:3117-3122`). Those odd
half-pixel numbers are the overlay fitting *inside* the photo's rounded corners.

Service/action messages also hide the bubble (`isAction` in `:2234`) and use
`systemMessageBackground` instead.

---

## 4. Geometry — what the bubble frame actually is

The bubble is never sized directly; it is given the cell's **body frame** verbatim:

```objc
_messageNormalBackgroundView.frame = bodyFrame;                 // :3112
_messageHighlightedBackgroundView.frame = bodyFrame;            // :3114
```

The body frame is built in `layoutContent` (`:3031-3068`) from the cached `TGLayoutModel` size:

- **Margins** `messageBodyMargins = (0, 2, 3, 2)` (assets source `:1225`) — 2 pt at each side,
  3 pt below, nothing above. These are added to the row height in
  `sizeForConversationMessage` (`:106-108`), so the inter-row gap is 3 pt.
- **Paddings**, the content inset *inside* the bubble, asymmetric by direction
  (assets source `:1232-1240`):
  - incoming `(5, 15+1, 5, 9+1)`
  - outgoing `(5, 9+1, 5, 15+1)`

  The wide side is the tail side: 16 pt of lead-in over the tail, 10 pt on the plain side, 5 pt top
  and bottom. The `+1` is written literally in the source, i.e. someone nudged a 15/9 design by a
  point and left the arithmetic visible.
- **Minimum body size** `messageMinimalBodySize = (40, 31)` (assets source `:1229`) — exactly the
  single artwork's dimensions. A one-character message cannot shrink the bubble below the PNG's
  natural size, so the tail never distorts. Enforced at `:988-991`.
- **Maximum width** (`:908-935`): 250 pt portrait, 395 pt landscape; 310/470 for action messages.
  Then `-40` if avatars are shown and the message is incoming (`:922-926`), `-12` if outgoing
  (`:929-933`), and finally `-= bodyPaddings.left + bodyPaddings.right` (`:935`) so the 250 is a
  *bubble* budget and the text gets 250 − 12 − 26 = 212 pt on an outgoing portrait message.
- **Horizontal placement**: incoming sits at `bodyMargins.left`; outgoing is right-aligned,
  `x = selfWidth - width - bodyMargins.right` (`:3047-3048`); action messages are centred (`:3052`).
  With avatars on, the incoming bubble shifts right by `avatarWidth + 4 = 42` and the 38 × 38 avatar
  is placed at `bodyFrame.x + 4`, bottom-aligned to `bodyFrame.bottom - 1` (`:3056-3062`).
- **Padding collapses for media**: when `hasImage`, the layout adds only `+3` to width and
  `top + bottom - 1` to height instead of the full paddings (`:982-986`) — there is no bubble to pad
  against.

Everything else in the row hangs off `bodyFrame`: the timestamp label at `bodyFrame.right + 12`
incoming or `bodyFrame.left - 26 - retinaPixel - width` outgoing, vertically `bottom - 22`
(`:3071-3077`); the upload progress bar (`:3149-3158`); the media action button (`:3130-3137`).
This is why getting the bubble frame wrong shifts six other things.

### Reuse

The bubble view is created once in the cell's initialiser (`:387-388`) and added to `contentView`;
it is never recycled through `TGViewRecycler` and never removed. Reuse means only that
`updateBackground:` reassigns `image`, `enableStretching` and `stretchInsets`, and that `hidden` is
recomputed from the new layout (`:2234`). The *highlighted* view is the one that comes and goes:
created on first selection, removed from the superview on deselect (`:778`, `:804`), kept in the
ivar for the next time. `_messageHighlightedForegroundView` is likewise removed but retained
(`:790`, `:805`).

### Empty / degenerate content

- Empty text: floored at 40 × 31 by the minimal body size, so the bubble is a small pill, never a sliver.
- Extremely long text: the layout wraps at `maxWidth`, the height grows freely, and the tall artwork
  with its 1 pt stretch column carries it — there is no upper height clamp on the bubble. The only
  height-driven behaviour beyond 48 is `:2193`, which disables async background rendering when
  `layoutSize.height > minimalBodySize.height * 12` (i.e. > 372 pt) and falls back to synchronous
  drawing.
- Nil layout: `layoutContent` logs `warning: layout is nil` and returns without touching any frame
  (`:3025-3029`), leaving the previous cell's geometry on screen. A defensive bail-out, not a design.

---

## 5. Our port

Ours has no bubble class either. The equivalent is `TGBubbleCell`'s `bubble` / `bubbleBg` / `tail`
subviews, driven from `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGChatViewController.m`
(`applyBubbleArtworkTo:outgoing:` at `:7646-7674`, cell layout at `:8317-8385`) with colours and
metrics in `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGTheme.m` (`:254-273`, `:402-408`).

What is right: we use the same PNGs with the same caps — `leftCapWidth: mine ? 15 : 20,
topCapHeight: 15` (`TGChatViewController.m:7659`) matches the original's `:652`/`:721` exactly. Our
`kBubbleMinW = 40` / `kBubbleMinH = 31` (`:51-52`) match `messageMinimalBodySize`. Our
`kBubbleOutgoingTrim = 12` and `kBubbleAvatarTrim = 40` (`:53-54`, applied in `maxBubbleWidthFor:`
`:7246-7255`) match `:929-933` and `:922-926`. `kAvatarSide = 38` matches `:3056`. The comment at
`:7642-7645` shows the author understood the model.

### Defects

1. **No tall-bubble variant.** `applyBubbleArtworkTo:` (`:7647`) only ever names `Msg_In` /
   `Msg_Out`. The original switches to `Msg_In_High` / `Msg_Out_High` with a one-pixel stretch column
   whenever `layout.size.height >= 48` (`:2376`, `:2392`, `:2410`, `:2424`). Every multi-line
   message in our client therefore stretches a 31 pt tail across the full bubble height. This is the
   single most visible difference. Fix: at height ≥ 48, use the `_High` asset with
   `resizableImageWithCapInsets:UIEdgeInsetsMake(15, mine?17:23, 15, mine?22:16)
   resizingMode:UIImageResizingModeStretch`.

2. **`Msg_In_High@2x.png` is missing from `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/images`.**
   `Msg_Out_High@2x.png`, `Msg_In_High_Selected@2x.png` and `Msg_Out_High_Selected@2x.png` are all
   there; the incoming tall bubble is not. It must be copied from
   `telegram-original-sources/…/Telegraph/Telegraph/Resources/Msg_In_High@2x.png` before fix (1) can
   land.

3. **Both `Msg_*_Selected_Shadow@2x.png` are missing**, and nothing in our source calls anything
   equivalent to `setShadowImage:`. The original's context-selected bubble is artwork + shadow layer
   (`:2388`, `:2404`); ours would be flatter.

4. **We still draw a CALayer bubble underneath the artwork.** `:8354-8369` sets
   `backgroundColor`, `layer.borderWidth = 1`, `layer.borderColor`, `layer.cornerRadius` (10 or 12
   from `TGTheme.m:402-408`) and composites a hand-drawn 6 × 10 tail from
   `TGIcons.m:957-981`, and only then does `applyBubbleArtworkTo:` clear all of it again
   (`:7669-7672`). The original has no radius, no border, no separate tail — everything is in the
   PNG. The clearing makes it invisible in the normal path, but it is live wherever the artwork
   fails to load (`:7653-7656`) and in the poll / call / card cells (`:7730-7734`, `:7850-7854`,
   `:7897-7901`), which each set radius+border and *then* call `applyBubbleArtworkTo:`. Those three
   paths are two full render passes per cell on a 4S. The drawn fallback is also wrong-looking: 12 pt
   radius and a 1 pt `#012968` @ 20% border have no counterpart in the original.

5. **Symmetric horizontal padding.** We use `kPadH = 10` on both sides (`:56`, used at `:7745`,
   `:8318` and throughout). The original is asymmetric — 16 pt on the tail side, 10 pt on the other
   (`messageBodyPaddings{Incoming,Outgoing}`, assets source `:1234`/`:1239`). Our text sits 6 pt too
   close to the tail on the tail side, which is the exact gap the tail artwork occupies. Fix: pass
   `mine ? UIEdgeInsetsMake(5, 10, 5, 16) : UIEdgeInsetsMake(5, 16, 5, 10)`.

6. **`kBubbleMaxW = 244` vs the original's 250** (`:53` vs `:908`). Six points narrower, so our
   lines wrap earlier than they should. Also, the original's trims are applied to 250 and *then* the
   paddings are subtracted (`:935`); ours subtracts `2 * kPadH` at each call site (`:7427`, `:3504`),
   which with the wrong padding compounds the error. There is no landscape widening in ours; the
   original goes to 395 pt (`:912`).

7. **Selection uses the wrong mechanism.** `self.drawingSelectedRow` swaps in `_Selected` art
   (`:7648-7649`) as a straight image swap. The original keeps two bubble views and cross-fades them
   over 0.3 s (`:771-780`), and it is triggered by *context* selection (long-press), not by row
   selection.

8. **`bodyMargins` are not reproduced.** The original's `(0, 2, 3, 2)` (assets source `:1225`) puts
   the bubble 2 pt from each screen edge and 3 pt of gap below each row. I could not find those
   constants in our chat controller; verify what our row spacing and edge inset actually are before
   changing anything, as they may be encoded in the row-height calculation.

### Ambiguous, not a defect

The original sets `hideBackground = hasImage` unconditionally (`:993`), so *any* photo message loses
its bubble. Ours keeps a bubble unless `bareMedia` — i.e. unless the photo has no caption or other
decoration (`:8371-8372`). But 2013 Telegram had no photo captions, so the original never had to
answer the captioned case. Ours is a reasonable extension, and matches what later clients do; do not
"fix" it to match the original.

---

## 6. What became of it

**twelve** (`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGPresentationImages.m:533-590`) keeps
the same ten PNGs and the same numbers, now behind `TGClassicIOS6StretchableImage(name, left, top)`
and gated as a "classic" theme:

```objc
return TGClassicIOS6StretchableImage(@"Msg_In.png", 20, 15);        // :533
return TGClassicIOS6StretchableImage(@"Msg_In_High.png", 23, 15);   // :549
return TGClassicIOS6StretchableImage(@"Msg_Out.png", 15, 15);       // :565
return TGClassicIOS6StretchableImage(@"Msg_Out_High.png", 17, 15);  // :581
```

Note the tall variants' left caps, 23 and 17, are the same numbers the original passed as
`capInsets.left` — independent confirmation that our reading of those insets is right. twelve's
change is organisational (theming), not aesthetic: the raster bubble was still the raster bubble
years later.

**Telegram-iOS** replaced it with a generated vector in
`submodules/TelegramPresentationData/Sources/ChatMessageBubbleImages.swift`. `messageBubbleImage`
(`:82`) takes `maxCornerRadius`, `minCornerRadius`, `fillColor`, `strokeColor`, a wallpaper, and a
`knockout` flag, and rasterises on demand. Two changes matter:

- **Neighbour awareness.** `MessageBubbleImageNeighbors` (`:6-13`: `none`, `top(side:)`, `bottom`,
  `both`, `side`, `extracted`) selects per-corner radii and whether to draw a tail at all
  (`messageBubbleArguments`, `:86-110`): a bubble in the middle of a run gets `minCornerRadius` on
  its tail-side corners and `drawTail = false`. The 2013 client had no concept of grouped messages —
  every bubble had a tail. This was forced by a feature (message grouping), not taste.
- **User-chosen colours and wallpapers.** A baked PNG cannot be recoloured, and `knockout` mode
  (bubble as a hole in the wallpaper) is impossible with a raster. That killed the PNG.

The one idea that survived unchanged is the geometric one: `minRadiusForFullTailCorner: CGFloat =
14.0` (`:28`) is still a threshold on size deciding whether the tail gets its full form — the same
instinct as the original's `height >= 48`.

For us, the lesson is inverted: we are deliberately in the world where the bubble is one immutable
PNG per direction per height class, and the correct implementation is a `UIImageView` with the right
cap insets and nothing else. Every `CALayer` property we set on `cell.bubble` is a modern habit
leaking into a 2013 design.

# The message bubble as a system (Telegram for iOS 1.1, 2013/2014)

Scope: the bubble artwork and its caps, the body paddings, the width budget, the tail, and how
non-text content sits inside. Everything here is read out of
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
(cited as `Telegraph/...` or `TelegraphKit/...`), plus pixel measurements of the shipped PNGs.

Two files carry almost the whole system:

* `TelegraphKit/TelegraphKit/TGConversationMessageItemView.mm` — 3742 lines: the layout model
  (`+layoutModelForMessage:withMetrics:assetsSource:`, line 943), the recursive content builder
  (`+recursiveCreateLayoutForMessage:...`, line 1001), background selection (`-updateBackground:`,
  line 2367) and `-layoutSubviews` (line 2948).
* `Telegraph/Telegraph/TGTelegraphConversationMessageAssetsSource.m` — every number and asset the
  layout asks for, behind the protocol in `TelegraphKit/TelegraphKit/TGConversationMessageAssetsSource.h`.

Nothing about the bubble is in a constants header. The layout is computed once per message into a
`TGLayoutModel` cached on `TGMessage.cachedLayoutData`, keyed by a `metrics` bitmask
(portrait/landscape/show-avatars, `TGConversationMessageItemView.mm:2986-2994`), and the whole body
is then drawn by one `drawRect:` (`TGConversationItemContentView`, line 174-178). The bubble
background is the only real subview behind it.

---

## 1. The three boxes

The original distinguishes three nested rectangles. Getting these names right makes the rest
readable.

| Box | What it is | Source |
| --- | --- | --- |
| **cell** | the table row; its height is body height + margins | `sizeForConversationMessage`, `TGConversationMessageItemView.mm:90-111` |
| **body** | the bubble: exactly the frame of the background image view | `_messageNormalBackgroundView.frame = bodyFrame`, line 3112 |
| **content** | where text/media actually draw, = body inset by the body paddings | line 3082-3083 |

```
messageBodyMargins        = UIEdgeInsetsMake(0, 2, 3, 2)     TGTelegraphConversationMessageAssetsSource.m:1223-1226
messageMinimalBodySize    = CGSizeMake(40, 31)               ...:1227-1230
messageBodyPaddingsIncoming = UIEdgeInsetsMake(5, 15+1, 5, 9+1)   ...:1232-1235
messageBodyPaddingsOutgoing = UIEdgeInsetsMake(5, 9+1, 5, 15+1)   ...:1237-1240
```

Margins are *not* part of the body: `layout.size` is the body size, and
`sizeForConversationMessage` adds the margins on top to produce the row height
(`TGConversationMessageItemView.mm:106-109`). So consecutive bubbles are separated by **3pt**
(bottom margin) and the outermost bubble edge — tail included — sits **2pt** from the cell edge
(`bodyFrame.origin.x = floorf(bodyMargins.left)` for incoming, line 3043;
`selfWidth - width - bodyMargins.right` for outgoing, line 3047).

The paddings are **asymmetric**: 16pt on the tail side, 10pt on the far side, 5pt top and bottom.
The `15 + 1` / `9 + 1` spelling in the source is the author's own note that the base values are
15/9 and one point of optical slack was added to each. The 6pt difference is exactly the tail
overhang (§3), so text is optically 10pt from the *drawn* body edge on both sides.

`messageMinimalBodySize` (40×31) is not an arbitrary floor: it is the exact point size of
`Msg_In.png` / `Msg_Out.png` (80×62 px @2x). The minimum bubble is one un-stretched copy of the
artwork. It is applied twice — as a floor on the text measuring width
(`minSize.width - paddings.left - paddings.right` = 40 − 26 = 14pt, line 938 and 1049-1050) and as a
floor on the finished body (lines 988-991).

## 2. The artwork and its caps

Ten PNGs, all 40pt wide, all loaded lazily and cached in statics
(`TGTelegraphConversationMessageAssetsSource.m:648-787`):

| Asset | pt size | Used as | Cap treatment |
| --- | --- | --- | --- |
| `Msg_In.png` | 40×31 | incoming, short | `stretchableImageWithLeftCapWidth:20 topCapHeight:15` (line 652) |
| `Msg_In_High.png` | 40×48 | incoming, tall | `resizableImageWithCapInsets:(15, 23, 15, 40-23-1)` stretch mode (line 664) |
| `Msg_Out.png` | 40×31 | outgoing, short | `stretchableImageWithLeftCapWidth:15 topCapHeight:15` (line 721) |
| `Msg_Out_High.png` | 40×48 | outgoing, tall | `resizableImageWithCapInsets:(15, 17, 15, 40-17-1)` (line 734) |
| `Msg_In_Selected.png` | 40×31 | incoming, context-selected | caps 20/15 (line 681) |
| `Msg_In_High_Selected.png` | 40×48 | incoming tall, selected | insets (15, 23, 15, 16) (line 700-710 region) |
| `Msg_Out_Selected.png` / `Msg_Out_High_Selected.png` | 40×31 / 40×48 | ditto outgoing | caps 15/15 and insets (15, 17, 15, 22) |
| `Msg_In_Selected_Shadow.png`, `Msg_Out_Selected_Shadow.png` | 40×31 | shadow layered *inside* the selected background view | `setShadowImage:`, lines 2388 / 2404 |

Both "High" images are stretched through a **single 1pt column** (`right = width - left - 1`) and
an 18pt vertical band (48 − 15 − 15). The plain images stretch through a 1pt column at x=20/15 and
a 1pt row at y=15. On iOS 5 and older the resizable API is missing, so
`TGConversationMessageItemBackgroundView.setImage:` falls back to `contentStretch` computed from
the same insets (lines 125-148). On our target (6.1.3) the modern path is taken.

Measured colours and geometry (pixel-sampled from `Msg_In@2x.png` / `Msg_Out@2x.png`):

* incoming fill `rgb(251,251,251)` with a dark blue-grey 1px border, `Msg_In_High` fill is
  `rgb(254,254,254)` — the two are not the same white, a real inconsistency in the original art;
* outgoing fill `rgb(212,251,178)` with a `rgb(14,173,2)` border;
* the opaque shape starts 2pt below the top of the frame and ends 28.5pt down in a 31pt image; the
  last ~1.5pt is a soft drop shadow baked into the PNG, not a border;
* incoming: body left edge at 7pt, right edge at 39.5pt; the tail hooks out to 0.5pt;
* outgoing: body left edge at 1pt, right edge at 33pt; the tail hooks out to 39.5pt.

So the shadow is part of the artwork; nothing draws a `CALayer` shadow, and the bubble has no
runtime corner radius. The visible corner radius is roughly 9-10pt, entirely inside the 15pt caps.

## 3. The tail — and the rule nobody expects

**The tail is fused into the artwork's bottom corner, and tall bubbles have no tail at all.**

`-updateBackground:` (`TGConversationMessageItemView.mm:2408-2436`) is four lines of logic:

```objc
if (layout.size.height >= 48) { enableStretching = true;  image = ...BubbleOutgoingDouble;  }
else                          { enableStretching = false; image = ...BubbleOutgoingSingle; }
```

`...Double` resolves to `Msg_Out_High.png`, and alpha-mapping that PNG shows a plain rounded
rectangle with a symmetric bottom edge — **no tail**. `Msg_In.png`/`Msg_Out.png` do have one, at
bottom-left and bottom-right respectively. The 2013 screenshot in
`design-reference/telegram-messenger-2013-05.jpg` confirms it on real pixels: the one-line green
bubbles carry tails, the tall white paragraph bubbles are plain rounded rectangles.

The threshold is the **body** height (`layout.size.height`), i.e. content + 10pt of vertical
padding, before the 3pt bottom margin. With the 16pt Helvetica body font a single line yields the
31pt minimum, two lines ≈ 41pt, three ≈ 60pt — so the switch happens somewhere in the third line.
It is deliberately *not* "one line vs many": a two-line bubble still gets a tail.

The naming ("Single"/"Double", "High") suggests the author thought of it as one-line vs
several-line artwork rather than as tail vs no-tail; the tailless shape is a consequence of the
drawing, not of a named flag. The modern client re-reads the same two assets exactly this way — see
§7.

Because the tail is inside the image, the artwork is 6pt wider than the content box on the tail
side and the paddings absorb it (16 vs 10). There is no separate tail view anywhere in the original.

## 4. The width budget

All of this is in `+layoutModelForMessage:` lines 908-936. The number that travels is a **maximum
text width**, not a maximum bubble width:

```
maxWidth = 250                                  // portrait
maxWidth = 395                                  // landscape (metrics & Landscape)
maxWidth = 310 / 470                            // service ("action") messages, portrait/landscape
if (showAvatars && !outgoing)  maxWidth -= 40   // and maxImageWidth -= 40
if (outgoing)                  maxWidth -= 12   // and maxImageWidth -= 12
maxWidth -= bodyPaddings.left + bodyPaddings.right   // −26 for both directions
```

Resulting portrait budgets on a 320pt screen:

| Case | text max | bubble (text+26) | left of the row |
| --- | --- | --- | --- |
| incoming, 1:1 chat | 224 | 250 | 2 + 250 = 252, 68pt free for the timestamp |
| incoming, group (avatars) | 184 | 210 | 2 + 38 + 4 + 210 = 254 |
| outgoing | 212 | 238 | right edge at 320 − 2 |

The avatar reservation is 40pt but the avatar is 38pt at `bodyFrame.origin.x + 4`, and the body then
shifts by `avatarWidth + 4` = 42 (lines 3055-3062). The 40 vs 42 mismatch means an avatar'd bubble
is 2pt narrower than the budget nominally allows — harmless, but it is a real off-by-two in the
original.

The 12pt outgoing trim has no visual element behind it; it simply keeps outgoing bubbles visibly
shorter than incoming ones.

Landscape re-layout is driven purely by the cell width: `metrics` is portrait when
`self.frame.size.width <= 321` and landscape otherwise (lines 2983-2986), and a metrics change
invalidates the cached layout.

## 5. Vertical assembly of the content

`recursiveCreateLayoutForMessage:` walks the message and accumulates `size` top-down. Order and
spacing (all in the file cited, line numbers of the `+recursive...` body):

1. **Author name** — only when `!outgoing && (metrics & ShowAvatars) && text.length != 0`
   (line 1723). Helvetica-Bold 13 (`messageAuthorNameFont`, assets source line 322-328), fixed
   16pt line box, laid at `y + 2`, advances `16 + 1 = 17`. Colour: eight-entry palette
   `0xee4928, 0x41a903, 0xe09602, 0x0f94ed, 0x8f3bf7, 0xfc4380, 0x00a1c4, 0xeb7002`, index =
   `MD5("<uid><currentUserId>")[abs(uid % 16)] % 8`, memoised in a `std::map`
   (`coloredNameForUid`, lines 55-87). A message with media but no text gets **no** author name.
2. **Forwarded header** — "Forwarded message" title then "from " + name, advancing
   `titleHeight + 3` then a fixed `18` (lines 1768-1806). Suppressed entirely when the message
   carries an image/video/contact/location (`forwardIndex = -1`, lines 1751-1760).
3. **Text** — Helvetica at `TGBaseFontSize`, default **16pt**, user-adjustable 16…60
   (`TGTelegraphConversationMessageAssetsSource.m:10`, `TGAppDelegate.mm:902`). Colour
   `rgb(20,22,23)`, shadow explicitly disabled (assets source 173-189). Laid at `bodyPaddings.left`,
   width floored at `minTextWidth`; when the block is taller than the 31pt minimum, **one extra
   point** (two on non-retina) is added to the body height (`textSizeOffsetY`, lines 1015-1020 and
   1836-1837).
4. **Media** — see §6.
5. **Contact** — 30×30 remote avatar at `(paddings.left + 0.5, y + 2.5)` under a 31×32
   `InlineAvatarOverlay.png`, name and phone at `paddings.left + 38`, advancing `32 + 7`
   (lines 2051-2091).
6. Nested/quoted content recurses with `level + 1`, which only adds `level * 9` to the left padding
   and 2 to the right (lines 1027-1033).

Then, back in `layoutModelForMessage:` (lines 977-991):

```objc
if (!hasImage) { size.width += left+right; size.height += top+bottom; }
else           { size.width += 3;          size.height += top+bottom-1; }
size = max(size, minimalBodySize);
```

That is: **a message containing an image does not get horizontal padding at all**, only 3pt of
width, and loses one point of height. This is coherent only because such messages also hide the
bubble.

## 6. Non-text content inside the bubble

### 6.1 Photos, video and location: the bubble disappears

`layout.hideBackground = hasImage` (line 993) where `hasImage` is true for image, video, location
and the "chat photo changed" service action (lines 946-975);
`_messageNormalBackgroundView.hidden = isAction || layout.hideBackground` (line 2234). So a photo
message has **no bubble background at all**. The bubble look is baked into the thumbnail instead:

`TGAttachmentImage` (`TelegraphKit/TelegraphKit/TGImageUtils.mm:429-513`) clips the source to a
rounded rect of **radius 8**, inset `2` left/right, `1.5` top and `2` bottom from the produced
bitmap, fills it with the aspect-filled source, and then draws `AttachmentPhotoBubble.png`
(stretchable from its centre) over the whole thing — that overlay supplies the border and the same
drop shadow the bubble PNGs have. For locations the source is drawn at `(0, 4)` and
`MapThumbnailMarker.png` is stamped at centre − (4, 5) × scale.

Thumbnail sizing (lines 1871-1885):

```
imageSize = closest server size / 2
imageSize = TGFitSize (imageSize, 90×90)     // never larger than 90 in either axis
imageSize = TGFillSize(imageSize, 82×82)     // never smaller than 82 in either axis
imageSize = TGCropSize(imageSize, (maxImageWidth − 60) × 400)
```

`TGFitSize`/`TGFillSize`/`TGCropSize` are at `TGImageUtils.mm:622-672`. In practice every 2013
inline photo lands between **82 and 90 points**. It is a thumbnail, not a poster. The crop bound
only bites in landscape or for extreme aspect ratios (`maxImageWidth − 60` = 164 for a portrait
incoming 1:1 message).

Placement is deliberately negative: `remoteImageItem.frame.origin.x = outgoing ? -9 : -11`
(line 1903) relative to the content origin — the image bleeds back out through the 10/16pt padding
so that its baked border lines up with where the bubble border would have been — and the vertical
paddings around it are `imagePaddingTop = imagePaddingBottom = -4` (lines 1022-1023). The body then
takes `width = max(width, imageWidth + 3)`.

Video adds, on top of the thumbnail: `MessageMediaBar.png` stretched across the bottom inset by
2.5pt, `MessageInlineVideoIcon.png` at +8pt from the left, a right-aligned 30×18 duration label in
bold 10pt white, and a centred progress label sharing the bar (lines 1915-1971).

### 6.2 Selection / long-press highlight

Two mechanisms, chosen by whether the bubble exists:

* **Bubble present**: a second `TGConversationMessageItemBackgroundView` is inserted directly above
  the normal one with the `..._Selected` artwork *and* a `shadowView` holding
  `Msg_In_Selected_Shadow.png` added as its subview with `FlexibleWidth|FlexibleHeight`
  (lines 723-729, 2371-2405). It cross-fades by `alpha` and is removed from the hierarchy when the
  fade completes (lines 765-806). The tall/short choice is made independently for the highlighted
  image, with the same `>= 48` threshold.
* **Bubble hidden (media)**: `MsgAttachmentHighlightedOverlay.png` is placed over the body inset by
  `y + 3`, `height − 5.5`, `x + 3.5` outgoing / `+ 7.5` incoming, `width − 11` (lines 735-762 and
  3115-3122) — i.e. tracking the baked thumbnail border rather than the body box.

### 6.3 Timestamp, ticks and the bubble

The stamp is **not inside the bubble** in 2013. `layoutSubviews` lines 3071-3079:

```objc
dateFrame.origin.x = incoming ? bodyFrame.maxX + 12
                              : bodyFrame.minX - 26 - retinaPixel - dateWidth;
dateFrame.origin.y = bodyFrame.maxY - 22;
dateBackground     = incoming ? (dateX-10, dateY-3-rp, dateW+16, 21)
                              : (dateX-5,  dateY-3-rp, dateW+29, 21);   // +29 leaves room for ticks
```

System font 11, colour `0x232d37` (assets source 895-917); the plate is
`MessageTimestampBackground.png` stretched from its horizontal centre (line 789-797). The label and
plate are siblings of the background view added *after* it, so on a maximum-width bubble the plate
simply overlaps the bubble instead of being pushed — the translucent plate exists precisely for that
case. The original never clamps it to the screen.

### 6.4 Editing mode

When the row is in editing mode and the message is incoming (or a service message), the whole
content view is indented by **35pt** (`indentX`, lines 2962-2968), the round check sits at x=2 in a
35×35 box (line 3110), and the date label and plate fade to alpha 0 (lines 630-631).

### 6.5 Touch slop

`TGConversationItemContentView.pointInside:` grows the hit box by 18pt on both axes (lines 179-193),
so links near the bubble edge stay tappable. Worth keeping; it is invisible but it is why the
original feels forgiving.

---

## 7. What became of this

**Modern client.** The bubble is generated at runtime rather than shipped as PNGs
(`submodules/ChatMessageBackground/Sources/ChatMessageBackground.swift`), and the tail is decided by
**message grouping**, not by height: `ChatMessageBackgroundMergeType` is
`.None / .Side / .Top(side:) / .Bottom / .Both / .Extracted`, built from whether the neighbours above
and below belong to the same author-run (lines 8-30, 145-175). Only the last bubble of a run keeps
the tail. Layout constants moved into one struct: minimum size 40×35, edge inset 3, default spacing
2 + 1px, text bubble insets 11/6 symmetric, image insets 2, image max 300×380 / min 170×74
(`submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageItemCommon.swift:138-143`).
Two changes matter to us: (a) the width budget became proportional — `maximumWidthFill` with
`freeMaximumFillFactor: 0.85` and a 36pt compact inset — instead of the hard 250; (b) the paddings
became symmetric (11/11), because a generated tail no longer eats 6pt out of one side. The 40pt
minimum width survived thirteen years unchanged.

**twelve** (the ObjC fork on this lineage) is the most useful witness, because it maps the old
assets onto the new concepts explicitly
(`Telegraph/TGPresentationImages.m:530-570`):

```objc
- chatBubbleIncomingFullImage    → TGClassicIOS6StretchableImage(@"Msg_In.png", 20, 15)
- chatBubbleIncomingPartialImage → TGClassicIOS6StretchableImage(@"Msg_In_High.png", 23, 15)
- chatBubbleOutgoingFullImage    → TGClassicIOS6StretchableImage(@"Msg_Out.png", 15, 15)
```

"Full" = has tail, "Partial" = no tail — an independent confirmation that `Msg_*_High` is the
tailless artwork, and that the cap widths 20/23/15/17 are exactly the ones to use. twelve keeps the
old caps and only swaps the *trigger* from height to grouping.

---

## 8. Our port, judged

File under review: `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGChatViewController.m`
(bubble constants at 50-59, artwork at 7967-7999, geometry at 8641-8690, stamp at 7887-7928),
plus `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/images/`.

### What is already right

The width budget is right, by a different route. `kBubbleMaxW = 244` is applied to the *content
box*, which is `contentW + 2*kPadH` with `kPadH = 10`, and the artwork is then drawn 6pt wider on
the tail side — so the drawn bubble is 250 incoming, 238 outgoing (`−kBubbleOutgoingTrim = 12`), 210
with an avatar (`−kBubbleAvatarTrim = 40`). Those are the original's three numbers exactly. The
same trick makes the effective paddings 16/10 without ever writing 16 or 10 asymmetrically. The
2pt outer margin, the 3pt row gap (`return h + 3`, line 7846), the 40×31 minimum, the avatar at
`artworkLeft + 4` / `bottom − 39`, the 42pt body shift, the out-of-bubble timestamp with its
`−26 − 0.5 − width` / `+12` offsets and `+16` / `+29` plate widths, the `0x232d37` stamp colour,
the `rgb(20,22,23)` body colour and the eight-colour author palette are all faithful. Say so and
move on.

### Defects

1. **The tailless tall-bubble variant is not implemented, and its asset is missing.**
   `applyBubbleArtworkTo:outgoing:` (`src/TGChatViewController.m:7972-7986`) always loads
   `Msg_In`/`Msg_Out` with `stretchableImageWithLeftCapWidth:(mine ? 15 : 20) topCapHeight:15`.
   Every multi-line bubble in our build therefore wears a tail the original did not draw.
   Fix: when the body height ≥ 48 use `Msg_In_High` / `Msg_Out_High` via
   `resizableImageWithCapInsets:UIEdgeInsetsMake(15, 23, 15, 16)` (incoming) and
   `UIEdgeInsetsMake(15, 17, 15, 22)` (outgoing) with `UIImageResizingModeStretch`.
   Original: `TGConversationMessageItemView.mm:2408-2436`; caps at
   `TGTelegraphConversationMessageAssetsSource.m:656-673` and `726-743`.
   Blocker: `images/Msg_In_High@2x.png` is **absent** from our resources (we ship
   `Msg_Out_High@2x.png`, `Msg_In_High_Selected@2x.png` and `Msg_Out_High_Selected@2x.png` but not
   the incoming one). Copy it from
   `telegram-original-sources/.../Telegraph/Telegraph/Resources/Msg_In_High@2x.png`.

2. **Selection uses the wrong artwork family and drops the shadow layer.**
   Line 7974-7975 appends `_Selected` to the *short* name only, so a selected tall bubble gets the
   tailed short art; and we never load `Msg_In_Selected_Shadow` / `Msg_Out_Selected_Shadow`, which
   the original adds as an autoresizing subview of the highlighted background
   (`TGConversationMessageItemView.mm:2388`, `2404`, and `setShadowImage:` at 150-161). Both shadow
   PNGs are missing from `images/`. The original also cross-fades the highlight by alpha and removes
   the view afterwards (lines 765-806); we swap the image outright.

3. **Media messages keep a bubble the original always removed.**
   Ours clears the bubble only when `stampSitsOnPictureFor: && decorationHeight < 0.5`
   (`src/TGChatViewController.m:8694-8703`). The original sets `hideBackground` for *any*
   image/video/location attachment, unconditionally, and hides the background view
   (`TGConversationMessageItemView.mm:993`, `2234`). A photo with a forwarded header still had no
   bubble in 2013 — and the forwarded header itself was suppressed for media
   (`forwardIndex = -1`, lines 1751-1760), which we also do not do (`layoutForwardIn:` runs for
   every message, line 7429).

4. **The photo "bubble" overlay does not exist in our port.** There is no
   `AttachmentPhotoBubble@2x.png` in `images/` and nothing corresponding to
   `TGAttachmentImage` (`TGImageUtils.mm:429-513`): 8pt corner radius, inset 2/1.5/2/2, plus the
   stretched overlay that supplies the photo's border and shadow. Without it our media messages have
   no border at all, or a `cornerRadius` from the theme, neither of which is the original.
   Same for `MsgAttachmentHighlightedOverlay@2x.png` and the highlight rect
   `(x + 3.5 out / +7.5 in, y + 3, w − 11, h − 5.5)` (`TGConversationMessageItemView.mm:3115-3122`).

5. **Photo size is off by more than 2×.** `kImageMax = 200` (`src/TGChatViewController.m:73`)
   against the original's fit-90 / fill-82 / crop-(maxImageWidth − 60, 400) chain
   (`TGConversationMessageItemView.mm:1883-1885`). Real 2013 inline photos are 82-90pt. Ours also
   gives the picture a `+4` gap (`pic.height + 4`, lines 7843 and 8646) where the original uses
   `−4` top *and* bottom (`imagePaddingTop/Bottom`, lines 1022-1023) and offsets the image
   `x = −11` incoming / `−9` outgoing (line 1903) so it bleeds through the padding.

6. **No landscape metric.** `kBubbleMaxW` is a single constant; the original recomputes at
   `maxWidth = 395` (and 470 for service messages) whenever the cell is wider than 321pt
   (`TGConversationMessageItemView.mm:911-921`, `2983-2986`), and invalidates the cached layout on
   the metrics change. On a rotated 4S our bubbles stay 250pt wide in a 480pt row.

7. **The one-point growth for multi-line text is missing.** The original adds `textSizeOffsetY`
   (1 retina / 2 non-retina) to the body height whenever the text block exceeds the minimum height
   (`TGConversationMessageItemView.mm:1836-1837`). Our height is
   `senderH + 2*kPadV + decoration + body.height` with no such term (line 8645-8647), so every
   multi-line bubble is 1pt shorter than the original's — which, given defect 1, also shifts where
   the 48pt tail threshold would fire.

8. **Minor: avatar trim condition.** Ours triggers the 40pt trim on
   `self.isGroup && nameForUserId != nil` (`maxBubbleWidthFor:`, line 7440); the original triggers
   on the `ShowAvatars` metric and `!outgoing` alone (line 923). A group member whose name has not
   resolved yet gets a 40pt-wider bubble and no avatar in our build.

9. **Minor: author colour index.** Same eight colours, different derivation —
   `llabs(userId) % 8` (`src/TGChatViewController.m:7862-7880`) vs
   `MD5("<uid><currentUserId>")[abs(uid % 16)] % 8` (`TGConversationMessageItemView.mm:76-82`).
   Colours will be right in kind but assigned to different people, and in the original the mapping
   depends on who *you* are.

### Deliberate divergences worth keeping (not defects)

* We clamp the timestamp plate into the row (`over`/`back` at `src/TGChatViewController.m:7908-7911`);
  the original lets it run past the cell edge. The clamp matches what
  `design-reference/telegram-messenger-2013-05.jpg` shows for full-width bubbles, so keep it, but
  know it is ours.
* We draw the plate as a `UIView` with `cornerRadius 10.5` and 55% white
  (`src/TGChatViewController.m:1196-1199`) instead of stretching
  `MessageTimestampBackground.png`. Visually equivalent at 21pt tall; swapping in the real asset
  would be strictly more faithful if we ever ship it.
* `TGIcons bubbleTailForColour:outgoing:` (`src/TGIcons.m:957-981`) draws a 6×10 vector tail. It is
  dead weight for chat rows once the artwork path runs (`cell.tail.hidden = YES`, line 7997) and it
  is *not* the original's shape. Keep it only if some other surface needs it.

## 9. Where the original contradicts itself

* `Msg_In.png` and `Msg_In_High.png` do not share a fill colour (251 vs 254 grey). Nobody noticed
  because they never appear on the same bubble.
* The avatar reserves 40pt from the width budget but consumes 42pt of layout
  (`maxWidth -= 40`, line 924, versus `bodyFrame.origin.x += avatarWidth + 4`, line 3060).
* A message with both text and an image gets its background hidden while the text still lays out
  above the image, which would leave text floating on the wallpaper. Captions did not exist in
  v1.1, so the case never shipped — but if we support captions we must decide it ourselves; the
  original gives no answer.
* `layoutSubviews` carries a `bool singleMessage = false;` that is never assigned (line 3023) with
  three branches behind it (full-width body, zero margins, zero paddings) — dead code for an
  abandoned "one message per screen" mode. Ignore it.
* The `15 + 1` / `9 + 1` padding spelling is the only place in the layout where the author left the
  arithmetic visible; everywhere else the fudge factors (`+3`, `−1`, `+0.5`, `−4`) are bare.

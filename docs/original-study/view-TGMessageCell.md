# TGMessageCell — the conversation message row

**There is no class called `TGMessageCell` in the original.** The message row in Telegram
for iOS v1.1 (build 21024) is `TGConversationMessageItemView`, a `UITableViewCell` subclass:

- `TelegraphKit/TelegraphKit/TGConversationMessageItemView.h` (97 lines)
- `TelegraphKit/TelegraphKit/TGConversationMessageItemView.mm` (3742 lines)

with three collaborators that cannot be understood separately from it:

- `TGConversationItemView.h/.m` — the shared base for all three row kinds (message, date,
  unread) — 41 lines.
- `TGConversationMessageItem.h/.m` — the *model* the cell is bound to (message + author +
  the users referenced by the message) — 101 lines.
- `TGTelegraphConversationMessageAssetsSource.m` (in `Telegraph/Telegraph/`) — the concrete
  implementation of the `TGConversationMessageAssetsSource` protocol; **every** font, colour,
  image and inset in the row comes from here, not from the cell.

All line references below are to those files unless another path is given.

---

## 1. What it is for

One row of the conversation table. It draws *everything*: incoming and outgoing text bubbles,
photos, videos, locations, contacts, documents, forwarded headers, group-chat author names,
service ("X joined the group") messages, the time stamp beside the bubble, the delivery ticks,
the sender avatar, the upload/download progress bar, and the selection checkbox in editing mode.
There is no separate photo cell or service cell — the row type is decided by
`TGConversationItem.type` (`TGConversationItem.h:11-15`) and message rows cover every message.

### 1.1 The two-phase design (important, and unlike ours)

The cell does **not** lay out subviews per content element. It has two phases:

1. **Layout model.** `+layoutModelForMessage:withMetrics:assetsSource:` (`.mm:892`) walks the
   message and produces a `TGLayoutModel`: a flat, ordered list of `TGLayoutItem`s (text, image,
   remote image, button, label) each carrying an absolute `frame` inside the bubble's content
   box, plus the total `size`. It is pure, thread-safe, and cached on the message itself
   (`message.cachedLayoutData`, `.mm:96-104`), keyed by a `metrics` bitmask.
2. **Rendering.** The model is either drawn directly in `-drawRect:` of a single
   `TGConversationItemContentView` (`.mm:174-177`) or, for very tall rows, rendered into a
   `CGImage` on a background `NSOperationQueue` and assigned to `layer.contents`
   (`.mm:233-284`, `.mm:2193-2213`). Only genuinely interactive things (remote images, buttons)
   become real subviews, via `[layout inflateLayoutToView:…]`.

The row height is that cached model's height, so `heightForRowAtIndexPath:` costs nothing after
the first pass (`TGConversationController.mm:3806-3814` → `sizeForConversationMessage`, `.mm:90`).

### 1.2 The table is upside down

`TGConversationItemView` applies `CGAffineTransformMakeRotation(M_PI)` to itself in `init`
(`TGConversationItemView.m:26`) and the table view is rotated the same way. Row 0 is the newest
message. This is why the cell also sets `selectionStyle = None` and `backgroundColor = nil`
there (lines 23, 28-29).

---

## 2. Public surface

```objc
+ (TGLayoutModel *)layoutModelForMessage:withMetrics:assetsSource:   // .h:41
CGSize sizeForConversationMessage(item, metrics, assetsSource);      // .h:34 — height source
+ (void)clearColorMapping;                                           // .h:45 — author colours
+ (void)setDisplayMids:(bool)  / + (bool)displayMids;                // .h:47-48 — debug: show
                                                                     //   message ids instead of time
@property TGMessage *message; TGConversationMessageItem *messageItem;// .h:52-53
@property int messageItemHash;                                       // .h:50 — reuse fast path
@property bool isSelected;        // editing-mode checkbox
@property bool isContextSelected; // long-press "this one" highlight
@property bool showAvatar; NSString *avatarUrl;
@property bool disableBackgroundDrawing;
@property TGViewRecycler *viewRecycler; ASHandle *watcher;
- (void)resetView:(int)metrics;      // full rebind — .h:73
- (void)updateState:(bool)force;     // cheap rebind — .h:76
- (void)setProgress:visible:progress:animated:;
- (void)setMediaNeedsDownload:;
```

### 2.1 The metrics bitmask

`.h:23-29`:

| Flag | Value | Meaning |
|---|---|---|
| `Portrait` | 1 | width ≤ 321 |
| `Landscape` | 2 | width > 321 |
| `SingleMessage` | 4 | (declared; the code path is dead — `singleMessage` is a hard `false` at `.mm:3023`) |
| `HighlightUrls` | 8 | declared, unused in the layout |
| `ShowAvatars` | 16 | group chat, non-secret (`TGConversationController.mm:2139-2140`) |

The mask is recomputed in `layoutSubviews` from `self.frame.size.width <= 321`
(`.mm:2982-2989`), and the cached layout is thrown away whenever it disagrees (`.mm:2994-3021`).
**Rotating the device relays out every visible row from scratch.**

---

## 3. Metrics — every number, with its source

### 3.1 From the assets source (`TGTelegraphConversationMessageAssetsSource.m`)

| Value | Number | Line |
|---|---|---|
| `messageBodyMargins` | `UIEdgeInsetsMake(0, 2, 3, 2)` | 1223-1226 |
| `messageMinimalBodySize` | `CGSizeMake(40, 31)` | 1227-1230 |
| `messageBodyPaddingsIncoming` | `UIEdgeInsetsMake(5, 15+1, 5, 9+1)` | 1232-1235 |
| `messageBodyPaddingsOutgoing` | `UIEdgeInsetsMake(5, 9+1, 5, 15+1)` | 1237-1240 |

The horizontal asymmetry (16 vs 10) is **the tail**: `Msg_In.png` and `Msg_Out.png` carry the
curl inside the bitmap, so the side the tail is on needs 6 more points of padding before the
text can start. Every other geometric quirk in this component follows from that one fact.

`messageBodyMargins` is added on top of the layout size only in `sizeForConversationMessage`
(`.mm:106-108`) — so **the row is exactly `layout.height + 3` tall**, and the bubble sits 2pt
in from the screen edge.

### 3.2 Fonts and colours

| Thing | Value | Line |
|---|---|---|
| Message text | `CTFontCreateWithName("Helvetica", TGBaseFontSize)` | 43-44 |
| `TGBaseFontSize` | `16`, user-settable, clamped `MAX(16, MIN(60, …))` | 10; `TGAppDelegate.mm:902-904` |
| Text colour | `rgb(20, 22, 23)` | 173-179 |
| Text shadow | **nil** (the commented-out white 50% shadow is dead) | 181-189 |
| Author name font | `Helvetica-Bold 13` (CoreText) / `boldSystemFontOfSize:13` (UIKit) | 322-336 |
| Author name colour (1:1) | `0x4d688c` — *unused for group names, see below* | 338-344 |
| Service ("action") title font | `Helvetica-Bold 13` | 49-58 |
| Service text colour | `[UIColor whiteColor]`, shadow nil | 289-300 |
| Date font | `systemFontOfSize:11` | 895-901 |
| Date AM/PM font | `systemFontOfSize:9` | 903-908 |
| Date colour | `0x232d37`, shadow nil | 911-922 |
| Row background, normal | `clearColor` | 879-885 |
| Row background, selected/unread | `rgba(0x003871, 0.07)` | 887-893 |

### 3.3 Group author name colours

`coloredNameForUid` (`.mm:54-88`) — eight colours:

```
0xee4928  0x41a903  0xe09602  0x0f94ed
0x8f3bf7  0xfc4380  0x00a1c4  0xeb7002
```

The index is **not** `uid % 8`. It is
`ABS(MD5("<uid><currentUserId>")[ABS(uid % 16)]) % 8` (`.mm:77-82`), memoised in a
`std::map<int,int>` behind a pthread mutex, cleared by `+clearColorMapping` when the account
changes. So the same person is a different colour in a different account's copy of the same
group — deliberate, and the reason `clearColorMapping` exists at all.

### 3.4 Width budget (`+layoutModelForMessage:`, `.mm:908-935`)

```
maxWidth = 250                       portrait      (.mm:908)
maxWidth = 395                       landscape     (.mm:911-912)
service message: 310 / 470                         (.mm:914-919)
if ShowAvatars && incoming:  maxWidth -= 40        (.mm:922-926)
if outgoing:                 maxWidth -= 12        (.mm:929-933)
maxTextWidth = maxWidth - bodyPaddings.left - .right    (= 26)   (.mm:935)
```

So on a 4S in portrait the text is measured against:

| Case | maxTextWidth |
|---|---|
| 1:1 incoming | 250 − 26 = **224** |
| 1:1 outgoing | 250 − 12 − 26 = **212** |
| Group incoming | 250 − 40 − 26 = **184** |
| Group outgoing | 212 (the avatar trim is incoming-only) |

The 12pt outgoing trim exists so that the outgoing time stamp — which sits to the *left* of the
bubble — has room.

### 3.5 The vertical stack of a plain text message

Walking `+recursiveCreateLayoutForMessage:` (`.mm:1001`) with `level = 0` and no attachments,
the content-box origin is `(0,0)` and:

1. **Group author name** (`.mm:1720-1744`) — only when `!outgoing && (metrics & ShowAvatars)`
   **and `messageText.length != 0`**. Frame `(bodyPaddings.left, size.height + 2, nameWidth + 4, 16)`.
   The height is hardcoded 16 regardless of the measured text (`.mm:1735`); the stack then
   advances by **17** (`size.height += nameSize.height + 1`, `.mm:1742`). One line, no wrap
   (`numberOfLines = 1`, `.mm:1730`).
2. **Message text** (`.mm:1812-1840`) — CoreText, multiline, links highlighted, left-aligned,
   width clamped to at least `minTextWidth = 40 − 26 = 14`. Frame
   `(bodyPaddings.left, size.height + 0, ceil(w), ceil(h))`.
   Then `size.height += textSize.height`, **plus one extra point** (two on non-retina) if
   `textHeight + paddings > minSize.height` (`.mm:1015-1020`, `.mm:1836-1837`) — a descender fudge
   that only kicks in once the bubble has grown past its minimum.
3. **Close out** (`.mm:977-991`): if the message has no image, add
   `paddings.left+right` (26) and `paddings.top+bottom` (10); then clamp to `40 × 31`.

Worked example — a one-line incoming 1:1 message, Helvetica 16 (line height ≈ 19):
content 19 + 10 = 29 → clamped to the **31pt** minimum; row height 31 + 3 = **34pt**.
The 31 is not arbitrary: it is the smallest box the bubble artwork's tail reads correctly in.

### 3.6 Media collapses the bubble

If any attachment is an image, video, location, or a chat-photo action (`.mm:940-975`), then
`layout.hideBackground = true` (`.mm:993`) — **the bubble artwork is not drawn at all** — and the
close-out is different: `width += 3`, `height += paddings.top + bottom − 1` (`.mm:982-986`).
Photos in 2013 were bare rounded rectangles with corner overlays, not bubbles.
Default sizes for those blocks: photo box `90×90`, fill `82×82`, location `200×200` (`.mm:1842-1844`).

### 3.7 Service ("action") messages

Every action branch (`.mm:1057`-≈1700) builds the same shape: centred bold-13 white text on a
stretched `systemMessageBackground`, the plate being `CGRectInset(textFrame, -8, 0)` with
`height += 4`, `+3` more if that exceeds 21, `origin.y -= 1 + retinaPixel`, and a floor of 21pt
(e.g. `.mm:1116-1125`). Stack advance is `textHeight + 16`. A chat-photo change additionally
hangs a 70×70 `profileAvatar`-filtered remote image under it and adds 78 (`.mm:1276-1293`).
Service rows get `bodyPaddings = UIEdgeInsetsZero` in the model (`.mm:903-904`) but
`UIEdgeInsetsMake(5, 0, 4, 0)` in `layoutSubviews` (`.mm:3040-3041`), and are centred:
`bodyFrame.origin.x = (selfWidth − width) / 2` (`.mm:3052`).

### 3.8 Nesting

`recursiveCreateLayoutForMessage:onLevel:` indents by `level * 9` on the left and 2 on the right
(`.mm:1027-1033`); a service message adds a further 8 (`.mm:1041-1044`). In v1.1 the recursion is
only ever entered at level 0 for real messages, but the indent arithmetic is what the forwarded
block reuses.

---

## 4. Artwork

### 4.1 Bubbles — and the "double" variant we are missing

| Selector | File | Caps | Line |
|---|---|---|---|
| incoming, short | `Msg_In.png` | `stretchableImage` left 20, top 15 | 648-654 |
| incoming, tall | `Msg_In_High.png` | `resizableImageWithCapInsets:(15, 23, 15, w−23−1)` stretch | 656-673 |
| incoming, highlighted | `Msg_In_Selected.png` | left 20, top 15 | 675-684 |
| incoming, highlighted shadow | `Msg_In_Selected_Shadow.png` | left 20, top 15 | 686-695 |
| incoming, tall highlighted | `Msg_In_High_Selected.png` | caps `(15,23,15,w−23−1)` | 697-714 |
| outgoing, short | `Msg_Out.png` | left 15, top 15 | 716-724 |
| outgoing, tall | `Msg_Out_High.png` | caps `(15,17,15,w−17−1)` | 726-743 |
| outgoing, highlighted | `Msg_Out_Selected.png` | left 15, top 15 | 745-757 |
| outgoing, highlighted shadow | `Msg_Out_Selected_Shadow.png` | left 15, top 15 | 759-768 |
| outgoing, tall highlighted | `Msg_Out_High_Selected.png` | caps `(15,17,15,w−17−1)` | 770-787 |

All bubble bitmaps are `80×62` px (`@2x` → 40×31 pt) except the `_High` ones, which are
`80×96` px (40×48 pt) — verified with `sips` on
`Telegraph/Telegraph/Resources/Msg_*@2x.png`.

**The switch is at 48 points of layout height** (`-updateBackground:`, `.mm:2367-2436`):

```objc
if (layout.size.height >= 48) → *_High artwork, enableStretching = true,
                                 stretchInsets (15, 23, 15, 40−23−1) incoming
                                             (15, 17, 15, 40−17−1) outgoing
else                          → the plain single artwork, enableStretching = false
```

`enableStretching` / `stretchInsets` exist only for iOS < 5 where
`resizableImageWithCapInsets:resizingMode:` is missing; `TGConversationMessageItemBackgroundView`
converts them into a normalised `contentStretch` rect (`.mm:125-148`). On iOS 6 the cap insets
baked into the image win and this path is inert — but the **image swap at 48pt is not inert**.
A two-line bubble uses a different, taller-drawn tail than a one-line bubble. That is the single
most visible thing our port gets wrong.

### 4.2 Time plate, ticks, misc

| Selector | File | Treatment | Line |
|---|---|---|---|
| `messageDateBadgeOutgoing` | `MessageTimestampBackground.png` | stretchable, left cap = w/2, top 0 | 789-798 |
| `messageDateBadgeIncoming` | `MessageTimestampBackgroundIncoming.png` | same | 800-809 |
| `messageCheckmarkFullIcon` | `MessageCheckFull.png` | as-is (24×20 px = 12×10 pt) | 855-861 |
| `messageCheckmarkHalfIcon` | `MessageCheckHalf.png` | as-is | 863-869 |
| `messageNotSentIcon` | `NotSent.png` | as-is | 871-877 |
| link highlight | `LinkFull.png`, `LinkCorner*` | stretchable, caps = half | 924-931 ff. |

`MessageTimestampBackground@2x.png` is 38×42 px = **19×21 pt** — hence the hardcoded 21 in the
badge frame. There are two distinct plates: the incoming one is narrower in use because the
outgoing plate has to swallow the ticks as well.

---

## 5. Positioning — `layoutSubviews` (`.mm:2948-3144`)

With `bodyMargins = (0,2,3,2)`, `selfWidth` the cell width:

```objc
bodyFrame = (2, 0, layout.width, layout.height)                       // .mm:3043
if (outgoing)  bodyFrame.x = selfWidth − width − 2                    // .mm:3047-3048
if (service)   bodyFrame.x = (selfWidth − width) / 2                  // .mm:3050-3053
```

**Avatar** (group, incoming only — `.mm:3054-3068`): 38×38, at
`(bodyFrame.x + 4, bodyFrame.y + bodyFrame.height − 38 − 1)`, and then
`bodyFrame.x += 42`. So on a 320pt screen the avatar occupies x 6…44 and the bubble starts at 44,
bottom-aligned with the bubble, one point up from its bottom edge.

**Date label** (`.mm:3071-3079`):

```objc
incoming: dateX = bodyFrame.maxX + 12
outgoing: dateX = bodyFrame.x − 26 − retinaPixel − dateWidth
dateY = bodyFrame.maxY − 22
badge  = incoming ? (dateX−10, dateY−3−retinaPixel, dateW+16, 21)
                  : (dateX− 5, dateY−3−retinaPixel, dateW+29, 21)
```

The outgoing badge is 13pt wider because the ticks live inside it. There is **no clamping** to
the screen edge: with the widest bubble the incoming badge can and does run past the right edge.

**Status container** (`.mm:3107`): `(dateX + dateWidth − 30, dateLabel.y − 3, unsentBadge.width, 20)`.
Inside it (`.mm:471-496`): first check at x 35, second at x 31, both `y = 4 + retinaPixel`; the
`TGClockProgressView` for pending at `(31, 2, 15, 15)`; the failed badge at `(0, −retinaPixel)`.
The two checks overlap by 4pt — that is how the double tick is drawn, from two copies of the
same 12×10pt glyph, not from one composed image.

**Editing** (`.mm:2962-2967`, `.mm:3109-3110`): incoming and service rows indent the whole
content view by 35; the checkbox is 35×35 at `x = 2` when editing and `x = −35` when not,
vertically centred and nudged one point up.

**Highlight overlay** (`.mm:3115-3123`): the highlighted foreground is the body frame inset by
`y+3`, `height−5.5`, `x + (outgoing ? 3.5 : 7.5)`, `width−11` — i.e. the bubble interior with the
tail excluded.

---

## 6. States

### 6.1 Delivery (`-updateStatusViews`, `.mm:2247-2309`)

Only outgoing, non-service rows show anything.

| Message state | Shown |
|---|---|
| `unread` + `Delivered` | **one** full check (`Second` only) |
| `unread` + `Failed` | `NotSent` badge; everything else hidden |
| `unread` + anything else (pending) | animated clock, `startAnimating` |
| **not** `unread` (i.e. read) | half check + full check → the double tick |

Note the 2013 semantics: **one tick = delivered, two ticks = read**, and "unread" is a property
of the *outgoing* message. And when delivery failed, `_dateLabel.hidden` and
`_dateBackgroundView.hidden` are both set (`.mm:2307-2308`) — the whole time stamp disappears and
the red badge takes its place.

### 6.2 Selection vs context selection

Two different things:

- `isSelected` (`.mm:2500-2521`) — editing-mode checkbox. Swaps the check image and lazily
  inserts a `_cellBackgroundView` tinted `messageBackgroundColorUnread` = `rgba(0x003871, 0.07)`
  **below** the content view.
- `isContextSelected` (`.h:79`) — the long-press "this is the message the menu is about"
  highlight; drives `_messageHighlightedBackgroundView` (the `_Selected` artwork plus its
  separate shadow image, `.mm:2371-2405`). Reset unconditionally on rebind (`.mm:2132-2133`).

### 6.3 Progress

`setProgress:progress:animated:` (`.mm:2595`) with `layoutProgress` (`.mm:3146-3164`): the bar
lives *outside* the bubble, in the empty gutter on the far side — starting at
`bodyFrame.maxX + 4` for incoming, at `8` for outgoing — with the cancel button pinned to the
outer end. The fill is quantised to half-points and forced to at least 13pt, hidden below that
(`.mm:3160-3163`), so a 1% upload still shows a visible nub rather than a sliver.

---

## 7. Behaviour

### 7.1 Reuse

Two reuse identifiers, `"MS"` (no avatars) and `"MM"` (avatars) —
`TGConversationController.mm:3426-3430` — so an avatar-carrying cell never lands in a 1:1 chat.
There is also a warm pool, `_preparedCellQueue` (`:3433-3441`), filled off the critical path.

Rebinding (`:3478-3487`) has a fast path: if `messageItemView.messageItemHash == (int)messageItem`
— literally the model object's pointer — only `updateState:false` runs; otherwise the full
`resetView:` rebuild. `resetView:` (`.mm:2110-2245`) cancels any in-flight background render,
clears link highlights, resets `isContextSelected`, recomputes or reuses the cached layout,
reloads the avatar, refreshes the date text and plate, re-inflates the layout, resets every
status view's animations and transforms, and re-runs `updateStatusViews`.

Cells are never mutated on scroll beyond that; the cell has no `prepareForReuse`.

### 7.2 Async rendering threshold

`.mm:2193`: `layout.height > messageMinimalBodySize.height * 12` → `31 * 12 = 372pt`. Beyond
that, the content is rasterised on a background queue at priority 0.4 and pushed into
`layer.contents`; below it, plain `drawRect:`. On a 4S this matters — a long message is the one
case where synchronous CoreText drawing visibly stutters the scroll.

### 7.3 Touch

- **Single tap on the bubble**: nothing, unless editing (then it toggles the checkbox via the
  `toggleMessageChecked` action, `.mm:3359-3368`). A single tap that is not on a link fires
  `messageBackgroundTapped` (`.mm:3407-3410`), which the controller uses to dismiss the keyboard.
- **Long press** (`minimumPressDuration = 0.3`, `.mm:405-407`) — link menu if on a link, else the
  message actions menu (`.mm:3385-3394`).
- **Double tap** — same as long press (`.mm:3396-3405`). Both gestures open the same menu; the
  double tap is there because a long press is slow.
- **Link press feedback**: `touchesBegan` highlights the link's glyph run immediately
  (`.mm:3322-3343`) using the `LinkFull`/`LinkCorner*` artwork stitched into up to three regions
  (`-highlightLink:`, `.mm:3423`); `touchesEnded`/`Cancelled` clear it.
- **Media** — `findAndActivateMedia:` hit-tests the layout model and posts `openImage`,
  `openMap` or `openContact` through the `ASHandle` watcher (`.mm:3199-3306`). A video whose file
  is not downloaded starts the download instead of opening (`.mm:3235-3243`).
- **Avatar tap** → `/tg/conversation/avatarTapped` with the uid (`.mm:3188-3197`).
- **Failed badge tap** → `deliveryStatusTapped:` (`.mm:3168`), the resend/delete sheet.
- **Hit slop**: the content view's `pointInside:` shifts the test point by +18,+18 and accepts
  anything within `size + 18` (`.mm:179-193`) — an 18pt grow on every side, because 16pt text in a
  narrow bubble is a small target. And `hitTest:` gives the date badge priority over everything
  below it (`.mm:3316-3317`).

### 7.4 Unusual content

- **Empty text, no attachments** → no layout items at all; the bubble clamps to the 40×31
  minimum and the row is 34pt of empty bubble. The original never guards against it.
- **Very long text** → never truncated, never line-limited; the row simply grows and crosses the
  372pt async-rendering threshold.
- **Missing author** in a group → `messageItem.author.displayName` is nil, the name block is
  skipped silently (`.mm:1726`, `TGReusableLabel` tolerates nil), so the bubble loses its 17pt
  header but the avatar still shows a placeholder keyed by uid (`.mm:2164`).
- **Media with no caption** → the group author name is *not* drawn: the name block is guarded by
  `messageText.length != 0` (`.mm:1720`).
- **Unsupported media** → the text is replaced with `Conversation.UnsupportedMedia` and the last
  26 characters are turned into a link to `http://telegram.org/update` (`.mm:1708-1712`).
- **`nil` message** → `layoutSubviews` and `recursiveCreateLayout` both log and bail
  (`.mm:2952-2956`, `.mm:1003-1007`) rather than crash.

---

## 8. Our port

Ours is `TGBubbleCell` — declared at `src/TGChatViewController.m:1101-1137`, implemented
`:1139-1413` — plus the configuration and geometry which live in `TGChatViewController` itself
(`configureRowChromeIn:` `:8195`, `cellForRowAtIndexPath:` `:8214`, the bubble geometry
`:8300-8500`, `placeDateBesideBubbleFor:` `:7593-7638`, `applyBubbleArtworkTo:` `:7646-7674`,
heights `:7509-7556`).

`src/ChatViewCell.h/.m` is dead — nothing references it, and `ChatViewCell.m:54-67` sends
`self.photoHeight` and `self.text`, which do not exist on the class. It should be deleted, but
that is not this document's call.

### 8.1 What is already right (briefly)

The width budget, the padding asymmetry and the bubble-vs-content offsets are correct, and were
clearly derived from the original rather than guessed:

- `kBubbleMaxW 244` − `kPadH*2 (20)` = 224 = the original's 224 for 1:1 incoming
  (`:53`, `:56`, `:7427` vs `.mm:908/935`); `kBubbleOutgoingTrim 12` and
  `kBubbleAvatarTrim 40` (`:54-55`, `:7246-7254`) match `.mm:922-933` exactly.
- Content box + `kBubbleTailOverhang 6` on the tail side reproduces the 16/10 asymmetric padding
  and puts the artwork's outer edge 2pt from the screen edge, matching `bodyMargins`
  (`:7662-7667`, `:8328` vs `.mm:3043-3048`).
- Avatar: 38pt, `x − 6 + 4` then bubble `+= 42`, bottom-aligned minus 1 (`:8331-8349`) — identical
  to `.mm:3056-3068`.
- Date and badge frames are transcribed exactly, including the `−26 − retinaPixel`, the
  `maxY − 22`, and the two badge insets `(−10, +16)` / `(−5, +29)` and the 21pt height
  (`:7605-7624` vs `.mm:3071-3079`).
- Text colour `rgb(20,22,23)` (`:65-71`), date colour `0x232d37` (`:7560-7567`), date font 11
  (`:1257`), sender font bold 13 (`:1170`), min body `40×31` (`:51-52`), row `+3` (`:7555`),
  day row 27 / unread row 34 (`:73-74` vs `TGConversationController.mm:3817/3821`) — all correct.
- Sender-name palette hexes are the original eight (`:7572-7575`).

### 8.2 Defects, in the order I would fix them

1. **The tall-bubble artwork is never used.** `applyBubbleArtworkTo:` (`:7646-7674`) always loads
   `Msg_In`/`Msg_Out` with caps 20/15 and 15/15. The original swaps to `Msg_In_High` /
   `Msg_Out_High` with cap insets `(15,23,15,w−23−1)` / `(15,17,15,w−17−1)` whenever
   `layout.size.height >= 48` (`.mm:2376-2435`). Every bubble of two lines or more is currently
   drawn with a 31pt-tall bitmap stretched to 50+ points, which distorts the tail and the top
   gradient. Fix: branch on `bubbleH >= 48`, and use
   `resizableImageWithCapInsets:resizingMode:UIImageResizingModeStretch` for the `_High` art.
   *`images/Msg_In_High@2x.png` is missing from our asset folder* (we ship `Msg_Out_High`,
   `Msg_In_High_Selected` and `Msg_Out_High_Selected` but not it) — copy it from
   `telegram-original-sources/.../Resources/Msg_In_High@2x.png` first.
2. **The time plate is a drawn rounded rectangle, not the artwork.** `:1195-1199` builds a
   `UIView` with `whiteAlpha 0.55` and `cornerRadius 10.5`. The original stretches
   `MessageTimestampBackground.png` for outgoing and `MessageTimestampBackgroundIncoming.png` for
   incoming, left cap = half width, top cap 0 (assets source 789-809). These are two different
   images and neither is a flat translucent white pill. Neither file is in `images/`. Copy both,
   make `dateBadge` a `UIImageView`, and pick by direction.
3. **The delivery ticks are the wrong glyph and the wrong semantics.**
   `statusGlyphForMessage:` (`:10071-10078`) returns one composed `ticksWhite:` image
   (`TGIcons.m:983`, which falls back to `DialogListRead` or a hand-drawn green double tick) for
   every non-pending, non-failed state. The original composes the mark from two 12×10pt bitmaps,
   `MessageCheckFull.png` and `MessageCheckHalf.png`, overlapping by 4pt at x 31 and x 35
   (`.mm:471-484`), and it shows **one** tick for delivered-but-unread and **two** for read
   (`.mm:2253-2289`). Ours shows the same double tick either way, so "delivered" and "read" are
   indistinguishable. Add both assets, place two image views 4pt apart, and drive them from the
   read flag.
4. **A failed message keeps its time stamp.** `.mm:2307-2308` hides both `_dateLabel` and
   `_dateBackgroundView` when `deliveryState == Failed` and shows `NotSent.png` in their place.
   Ours draws the badge, the time, and a hand-drawn failure glyph together (`:7620-7630`,
   `:10075-10076`). Hide the badge and the time when the state is `failed`.
5. **No landscape width.** The original doubles the budget to 395 (470 for service messages) when
   the cell is wider than 321pt (`.mm:911-919`, `.mm:2982-2986`). `kBubbleMaxW` is a compile-time
   244 (`:53`). In landscape our bubbles occupy half the screen. Make `maxBubbleWidthFor:`
   take the table width and use 395 above 321.
6. **The group author name is drawn on captionless media.** `:8307-8314` shows it whenever the
   chat is a group and the message is incoming; the original requires `messageText.length != 0`
   (`.mm:1720`). A bare photo in a group should carry the avatar but no name line inside it.
7. **Sender colour mapping differs.** Ours is `llabs(userId) % 8` (`:7586`); the original is
   `MD5("<uid><currentUserId>")[abs(uid % 16)] % 8` (`.mm:77-82`). Same palette, different
   assignment, and ours is not account-relative. Purely cosmetic, but it means screenshots will
   never match the reference ones. If we copy the hash we also need `clearColorMapping` on logout.
8. **No 18pt hit slop, and the date badge is not hit-test-first.** `.mm:179-193` and
   `.mm:3316-3317`. On a 4S this is a real usability difference for short bubbles.
9. **Descender fudge missing.** The original adds 1pt (2 on non-retina) to any bubble taller than
   the minimum (`.mm:1836-1837`). Ours does not (`:7546-7552`), so every multi-line bubble is
   one point shorter than the original's.
10. **Text rendering.** Ours is a `UILabel` with `systemFontOfSize:` (`:1163-1167`); the original
    is CoreText with `Helvetica` at `TGBaseFontSize`. On iOS 6 the system font *is* Helvetica, so
    the glyphs match, but link ranges, the `LinkFull` press highlight, and per-run highlighting
    are all absent from ours. Worth knowing; not worth rewriting as CoreText today.
11. **Structural, not visible:** the original inverts the table and each cell by π
    (`TGConversationItemView.m:26`) and folds date/unread rows into *separate* item types
    (`TGConversationItem.h:11-15`), where we fold them into the message cell as a `headerHeight`
    (`:1352-1357`, `:7500-7507`). Our heights match (27 / 34), so nothing is visibly wrong; but it
    means our day plate scrolls glued to the message beneath it, whereas theirs was its own row.
    Also: we use one reuse identifier (`:8215`) where they use two, so avatar views get carried
    between group and 1:1 chats within one screen — harmless today because we hide them, but it
    is why they split the identifiers.

### 8.3 Genuinely ambiguous

- `TGConversationMessageMetricsSingleMessage` and `HighlightUrls` are declared but never set;
  `singleMessage` is a hard-coded `false` (`.mm:3023`). Whatever the "single message" presentation
  was (probably the forwarding preview), it is not recoverable from this source.
- `messageAuthorNameColor` = `0x4d688c` (assets 338-344) is never consumed by the group-name path,
  which uses the eight-colour palette. I could not find its call site; treat it as dead.

---

## 9. What became of it

### 9.1 Modern client (`Telegram-iOS`)

`submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift`,
7879 lines, with constants in
`submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageItemCommon.swift:137-147`.

The two-phase design *survived and won*: the modern node still computes an immutable layout off
the main thread and then applies it. What changed:

| Then | Now | Why |
|---|---|---|
| One giant `recursiveCreateLayout` switch over attachment types (`.mm:1001`-3000) | A list of content-node classes chosen per message (`contentNodeMessagesAndClassesForItem`, `:117`), each laying itself out | Forced. Every new media type in 2014-2025 (webpage, poll, giveaway, story, invoice…) would have been another 200-line branch in one function. |
| `maxWidth = 250` fixed | `maximumWidthFill(compactInset: 36, freeMaximumFillFactor: 0.85)` (`:138`) — a *fraction* of the screen | Forced by device sizes: a fixed 250 is 78% of a 4S and 41% of an iPhone 16 Pro Max. |
| `minimumSize 40 × 31` | `40 × 35` (`:138`) | Taste — the default text got bigger (17pt) and the bubble corner radius grew. |
| Padding asymmetric 5/16/5/10 | `text.bubbleInsets` symmetric `6+px / 11 / 6−px / 11` (`:139`) | Forced: the tail is no longer inside the bitmap. Modern bubbles are drawn, and merged consecutive bubbles have no tail at all. |
| `bodyMargins` 2pt from the edge | `bubble.edgeInset: 3.0` (`:138`) | Taste. |
| Avatar 38 at `x+4` | `avatarInset: 34 + 4` (`:146`) | Taste; the avatar shrank by 4. |
| Time + ticks **outside** the bubble on a plate | Inside the bubble, on the last text line, with the text wrapped around them | The biggest change of all, and it is a change of taste that then forced work: the layout must now reserve trailing width on the final line for the status. |
| One tick = delivered, two = read | Same semantics, drawn inside | Survived. |
| `hideBackground` for any image | `image.bubbleInsets (2,2,2,2)`, `defaultCornerRadius 15`, `mergedCornerRadius 7` (`:140`) | Forced by grouped albums and captions: a photo *is* a bubble now. |
| Rows are separate item types (message/date/unread) | Still separate (`ListView` items) | Survived. |

### 9.2 `twelve` (the Objective-C fork on this lineage)

The component survives as `TGMessageViewModel` + `TGContentBubbleViewModel` +
`TGTextMessageModernViewModel` (`twelve/Telegraph/`). It is the intermediate step and it is the
most instructive of the three:

- The layout constants became a C struct filled once per idiom
  (`TGMessageViewModel.m:32-113`): phone gets `leftInset/rightInset 4`, `leftImageInset 9`,
  `avatarInset 3`, `textBubblePaddingTop/Bottom 5`, `textBubbleTextOffsetTop 1`; iPad gets
  17 / 23 / 11 / 5 / 6. Our 5pt vertical padding is still there thirteen years later.
- The avatar is still **38×38**, bottom-aligned (`TGMessageViewModel.m:706`) — unchanged from
  `.mm:3056-3061`.
- Font size became a runtime setting with real clamps, `12…24` on phone, `13…26` on pad, default
  17 (`TGMessageViewModel.m:65-68`, `119-134`), where v1.1 had `MAX(16, MIN(60, …))` with default
  16 (`TGAppDelegate.mm:902-904`). Forced: 60pt text broke every fixed metric in the old layout.
- The time stamp moved inside the bubble here, not in the Swift rewrite: the text model takes an
  `additionalTrailingWidth: infoWidth` so the last line wraps short
  (`TGTextMessageModernViewModel.m:929-937`), and `infoWidth` is accumulated from the date, the
  edit marker, the author signature and the view counter
  (`TGContentBubbleViewModel.m:1601-1622`). That accumulation is exactly the feature pressure —
  channels, "edited", view counts — that made an outside-the-bubble plate untenable.
- Headers (reply, forwarded, author name) became first-class submodels of a generic content
  bubble (`TGContentBubbleViewModel.m:1640-1704`) instead of inline arithmetic in one function.

The lesson for us: the 2013 layout is a single function producing a flat item list, and that is
fine as long as we only build the 2013 feature set. The moment a bubble needs a reply header
*and* a webpage footer *and* a trailing status, that function stops scaling — which is precisely
what happened to it in `twelve`.

# New message content kinds

**Area:** `messages-content` · **Question:** video notes, live location, dice, giveaways, invoices and
stories-as-messages did not exist in 2013. How does each render inside the original bubble artwork?

The catalogue entries this covers are *Live location sharing*, *Dice / slot machine messages*,
*Story shared into a chat*, plus the two kinds TDLib gives us that the catalogue folds into
payments and channels (`messageInvoice`, `messagePremiumGiveaway`), and the round `messageVideoNote`
that `TGChatViewController` already draws. Everything below is drawn with the metrics from
`docs/design-language/*.md` and uses only PNGs that are actually in `images/`.

Two facts constrain all three options.

1. **There is no map artwork, and there never can be a cheap one.** `MKMapSnapshotter` is iOS 7.
   `MKMapView` exists on iOS 6, but one live map view per bubble on an A5 with 512 MB is not
   survivable — each instance holds its own tile cache. So a location bubble in *any* option shows a
   code-drawn or server-fetched still, and tapping it pushes **one** shared full-screen `MKMapView`
   controller. That is a hard constraint, not a preference.
2. **`Msg_Out@2x.png` in our bundle is an Apple-crushed (CgBI) PNG.** UIKit reads it fine; some
   tooling does not. Each mockup therefore paints `#EFFEDD` with a black-12 % hairline under the
   outgoing bubble art, which is exactly what the art carries, so the two coincide on device.

---

## Option A — Attachment block (conservative)

`svg/messages-content-a.svg`

Every new kind becomes the **file/attachment block that the chat already draws**: a 37 pt media disc
at the bubble's text origin, a bold-15 title on the first line, a system-13 `#697487` subtitle on the
second, the timestamp in its usual bottom-right slot. Nothing new is invented; the block is the same
one `messageDocument` and the voice player already use, with a different glyph in the disc and
different strings.

Concretely, in a 222 pt-wide incoming bubble at `x = 8` (the 6 pt tail overhang is inside that):

- disc: 37 pt, centre `(45, top + 27.5)`, fill `#7D9AB7` neutral / `#4E8B3C` for anything payable,
  white glyph drawn by `TGIcons`;
- title: `boldSystemFontOfSize:15` `#141617` at `x = 72`, baseline `top + 20`;
- subtitle: `systemFontOfSize:13` `#697487`, baseline `top + 38`;
- timestamp: `systemFontOfSize:11` `#232D37`, right edge at bubble right − 8;
- block height 55 for two lines, 61 when the disc is replaced by a 45 pt thumbnail (radius 4,
  the `avatar40` family) — that is the story case.

Per kind:

| Kind | Disc glyph | Title (bold 15) | Subtitle (13, `#697487`) |
| --- | --- | --- | --- |
| Live location | pin | `Live Location` | `updating · 42 min left`, retimed every 15 s |
| Location (static) | pin | the venue title, or `Location` | reverse-geocoded street line |
| Story | 45 pt thumbnail instead of a disc | `Story from Alina` | `tap to view · 7 h left` |
| Invoice | card | product title | `3 months · @PremiumBot` |
| Giveaway | gift | `Giveaway · 5 Premium subscriptions` | `winners announced 20 Aug` |
| Video note | round 71 pt video already built | — | — |

Two kinds break out of the block:

- **Dice** is bubble-less, exactly like a sticker: a 64 pt die drawn in code (rounded square r 8,
  `#F4F1EA` face, `#B4291F` pips), sitting straight on the wallpaper with the drawn timestamp plate
  at its bottom-right, inset 4. The rulebook's sticker ruling (max side 128, no bubble, no shadow)
  applies unchanged; 64 is the floor it allows.
- **Invoice and giveaway** get one action row under the block: `GroupedActionButtonGreen`
  (cap 16, height 43) for `Pay US$ 11.99`, `GroupedActionButton` (cap 11, height 43) for
  `Learn More`, inset 11 from the bubble's content edges, label `boldSystemFontOfSize:14` white with
  the standard `(0,-1)` shadow. That is the components chapter §10 ruling for anything
  button-shaped in the content area, applied literally.

**Tap.** The disc is not a separate target — the whole block is one hit rect. Live location pushes
the shared map controller; story pushes the full-screen story viewer; invoice pushes the payment
form; giveaway pushes the giveaway info screen; dice replays its animation in place. Long-press is
the existing `TGMessageActionsSheet`, untouched.

**Scroll.** Row height is a pure function of two label heights, so `heightForRowAtIndexPath:`
stays the `sizeWithFont:` arithmetic already in `TGChatViewController`. No image is decoded while
scrolling except the 45 pt story thumb, which is the same size the chat list already decodes.

**Reuses.** `TGBubbleCell.icon` / `.body` / `.subtitle` / `.time` — every view is already allocated
in `-init`. `TGIcons mediaDiscOfSide:playing:`. `GroupedActionButton(Green)`.

**Costs.** Roughly 150 lines in the cell binder, one glyph per kind in `TGIcons`, one countdown
timer shared by every visible live-location cell (a single 15 s `NSTimer` that walks
`visibleCells`, not one per row). Memory delta over a text message: zero for four of the six kinds,
~8 KB for the story thumb.

**Gives up.** The map. A live location that never shows a map is a weaker message than the one
Telegram sends, and a recipient cannot tell at a glance where the sender is — they must tap. Story
previews are postage-stamp sized. Giveaway loses its prize artwork entirely.

---

## Option B — Media tile family

`svg/messages-content-b.svg`

Every new kind that has imagery gets a real **media tile inside the bubble**, clipped to the
existing `kMediaRadius = 6`, with a text strip under it. This is the layout `TGLiveLocationMessageViewModel`
in TWELVE uses, cut down to a 320 pt screen.

- Live location: tile **200 × 100** (the 1280 × 640 aspect TWELVE requests, at our
  `kImageMax = 200`), a 24 × 30 pin centred, a **30 pt countdown ring** at the tile's bottom-right
  inset 8 — 2 pt stroke in `#0779D0` over a 25 % track, minutes remaining in `boldSystemFontOfSize:11`
  at its centre. Under the tile, title `Live Location` bold 15 and subtitle `updated 30 seconds ago`
  system 13 `#697487`. Bubble height 156.
- Story: tile **108 × 144** (a 3:4 crop of the 9:16 story), a 34 pt play disc centred for video
  stories, and a 28 pt `rgba(0,0,0,0.42)` strip along the bottom of the tile carrying
  `Alina · 7h left` in bold 11 white. Bubble height 172, width 132.
- Invoice: tile 200 × 105 of the product photo, price on the drawn timestamp plate at the tile's
  bottom-left, title bold 15 under it, then the 43 pt green `Pay` row.
- Giveaway: tile 200 × 90 drawn in code — the gift glyph on the channel's avatar colour — then
  `5 Premium subscriptions for 5 winners` and the 43 pt `Learn More` row.
- Dice: the 128 pt sticker, animated through `TGLottieView`, which already exists.

**Tap.** Tile and text strip are one target, same destinations as Option A. The countdown ring is
decorative, not tappable — at 30 pt with an 8 pt inset it is inside the tile's own hit rect and
splitting them would produce a target under the 44 pt minimum.

**Scroll.** This is where it costs. A 200 × 100 tile at @2x is 400 × 200 × 4 bytes ≈ **320 KB
decoded**, and a story tile 216 × 288 ≈ 250 KB. Five such rows on screen is 1.5 MB of live bitmaps,
on top of whatever photos the chat already holds. `TGRemoteImageView` must downscale on the decode
thread and the cell must drop its image in `prepareForReuse`, or the chat starts jettisoning.

**Reuses.** `TGBubbleCell.picture` and its 6 pt corner clip; `TGRemoteImageView`; `TGLottieView`;
`GroupedActionButton(Green)`. The countdown ring and the map still are new drawing code
(~120 lines).

**Costs.** ~400 lines, a new `-drawRect:` map placeholder, a per-second ring redraw for visible
live-location rows (cheap: `setNeedsDisplay` on a 30 pt view), and the memory above. A location
still must also be fetched from somewhere — TDLib does not render map images, so this needs a static
map endpoint over the network, which is a real dependency and a real privacy decision.

**Gives up.** Density: **two messages fill the screen.** Scrolling back through a chat that trades
locations and stories becomes a slog, and on a 3.5-inch screen that is felt immediately. It also
gives up honesty about the map — the still is minutes stale while the ring implies live.

---

## Option C — Full-width banner rows

`svg/messages-content-c.svg`

Bubbles stay for things a person said. Everything machine-generated — giveaway, invoice, live
location, story — renders as a **44 pt full-width banner**, the height the rulebook fixes for "any
new top-aligned banner", drawn on `#FFFFFF` with one `#C7CDD3` hairline along the bottom, no rounded
corners, no tail, no direction.

- 30 pt disc or 36 pt thumbnail at `x = 4`, vertically centred;
- text column at **`x = 48`**: title `boldSystemFontOfSize:13` `#141617` baseline `top + 20`,
  subtitle `systemFontOfSize:13` `#697487` baseline `top + 36`;
- right slot at `x = 282..312`: a 28 pt countdown ring for live location, the
  `MenuDisclosureIndicator` chevron for anything that opens a screen, nothing otherwise;
- when the kind has actions, a **`TGButtonGroupView` sits 4 pt under the banner**, 30 pt tall,
  inset 8 either side, one segment per action, `ButtonGroupDivider` (cap 6) between them, labels
  `boldSystemFontOfSize:12` white with the `rgba(0x0e284d,0.4)` `(0,-1)` shadow — the components
  chapter §4 control, unmodified. `Participate | Winners` for a giveaway, a lone `Pay US$ 11.99`
  for an invoice.
- Dice stays a bubble-less sticker, and video notes stay round bubbles. Speech is untouched, which
  the mockup shows with an ordinary outgoing bubble at the bottom.

**Tap.** The banner is one 320 × 44 row — the largest target of the three options. The button group
fires on `UIControlEventTouchDown`, as that control always does.

**Scroll.** Cheapest of the three: fixed 44 (or 76 with the button bar) row height, no measurement
pass, no decode beyond a 36 pt thumb.

**Reuses.** `TGButtonGroupView` art, the banner geometry already used by the translation offer and
the undo bar, `TGIcons` discs, the disclosure indicator.

**Costs.** ~200 lines. Least memory of all three. The only new drawing is the countdown ring.

**Gives up.** Direction and delivery. A banner has no tail and no ticks, so *your own* invoice or
giveaway looks identical to one you received, and you cannot see whether it sent. In a busy channel
the banners stack into what looks like a settings table dropped into the chat, and the 2013 idiom's
strongest signal — the bubble — stops doing its job for a third of the traffic. It is the most
buildable and the least Telegram-like.

---

## Recommendation

**Option A, with one borrowing from B: the live-location bubble alone gets the 200 × 100 map tile
and the 30 pt countdown ring.**

Option A is right because these six kinds are, honestly, *notifications with a payload*, and the
attachment block is the component this app already has for exactly that. It costs nearly nothing,
it cannot regress scrolling, and five of the six kinds lose nothing meaningful by being two lines
of text next to a disc — nobody needs a hero image to understand `Giveaway · 5 Premium
subscriptions`. Option B's tiles buy real comprehension only for location, where "where is she"
is the whole content of the message and a text line genuinely cannot answer it; everywhere else
they buy 300 KB per row and cut the screen down to two messages, which on a 3.5-inch display is
the wrong trade. Option C is the cheapest and I would take it if the device were tighter than it
is, but losing the tail and the ticks on outgoing invoices is a correctness problem, not a taste
one — a user who cannot tell whether their payment request sent will send it twice.

So: build the block for all six, then spend the memory once, on the map.

---

## What genuinely cannot be built on this hardware

- **Slot-machine dice (`diceStickersSlotMachine`).** It is three independently spun TGS reels
  composed over a background and a foreground, five sprites playing in sync. `TGLottieView` on an
  A5 manages one moderate TGS at a reduced frame rate; five is not happening. **Reduced version:**
  the regular die and the slot machine both render as a static final-state image with the value on
  it, and the reels never spin. The number is right; the theatre is gone.
- **A live map.** No `MKMapSnapshotter` (iOS 7), and an `MKMapView` per bubble will not fit in
  512 MB. **Reduced version:** a still fetched once per location message, plus one shared
  full-screen `MKMapView` pushed on tap. The bubble's map is therefore never live even when the
  location is.
- **Background live-location updating.** iOS 6 will keep `CLLocationManager` running in the
  background under the location key, but the app is jettisoned under memory pressure like any
  other, and there is no significant-change plus background-fetch combination that survives it.
  **Reduced version:** live sharing continues while the app is foregrounded or in the location
  background mode, and the bubble states plainly `paused` when we stopped updating, rather than
  pretending.
- **Video stories.** `storyContentVideo` is H.264 in an MP4 that `AVPlayer` on iOS 6 can often
  play, but story video is frequently HEVC now, and there is no decoder. **Reduced version:** the
  story viewer shows the cover frame with a `video unavailable` line. Photo stories work fully.
- **The stories tray at the top of the chat list.** That is a horizontally scrolling ring strip,
  and it is out of scope here anyway; a story only exists in this area as a message.
- **Any blur.** The story viewer's blurred letterbox, and the media-spoiler cover, cannot use
  `UIVisualEffectView`. A pre-blurred small bitmap scaled up is the only affordable substitute,
  and it looks like what it is.

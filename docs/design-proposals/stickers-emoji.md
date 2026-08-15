# Stickers and custom emoji

Three answers to the same question: how do you browse sticker sets and render a line of text with
custom emoji in it when there is no `UICollectionView`, no TextKit and no headroom to animate more
than one thing at a time?

All three obey the same three rulings that come out of the design language, so the difference between
them is genuinely about shape, not about metrics:

- **A grid is a table.** Every sticker grid in all three options is a `UITableView` of `Cell102`
  plates, row height **78** (72 pt tile + 3 top + 3 bottom), four **72 × 72** tiles at x
  `2, 78, 154, 230` on a 320 pt screen. Section headers are `CategoryDivider` (`CategoryDividerFirst`
  for the first) at height **26**, label `boldSystemFontOfSize:12` in `#697487`, left inset 10.
  This is the components chapter §10 media-grid ruling applied verbatim. (The layout chapter's
  64 pt / 4-column figure predates it; where the two disagree, the 72 pt plated row wins because it
  gives exact tile origins and reuses real artwork.) Recycling comes free from `UITableView` —
  no hand-rolled tiling, no `TGViewRecycler` bookkeeping for the grid itself.
- **A sticker in a message is bubble-less**, max side 128, timestamp on a dark plate inset 4 in the
  bottom-right.
- **Animation is a privilege, not a default.** One `TGLottieView` instance exists in the whole
  process. Everything else — every grid tile, every set cover, every sticker scrolled off the
  focus position — is the decoded first frame, cached as a downscaled `UIImage`. Animated tiles carry
  a 14 pt dark play pip in the tile's bottom-right corner so the user knows there is more to see.

---

## Option A — Panel (the conservative one)

**File:** `svg/stickers-emoji-a.svg`

An input-accessory panel 216 pt tall (the iOS 6 portrait keyboard height) that replaces the keyboard
when the smiley button in the composer is tapped. It is the shape the project already half has:
`TGStickerPanelView.m` is 1269 lines of exactly this — sections, tiles, a purge distance, an image
cache limit. This option is mostly "finish what is there and dress it in the plated-row idiom".

- **Structure.** All sections concatenated into one vertically scrolling table: Frequently Used,
  Favourites, then each installed set, then Trending. `CategoryDivider` header at 26 between them.
- **Tab strip.** A group button bar at the bottom of the panel, **30 pt** tall, pinned (not
  scrolling): `ButtonGroupLeft` + `ButtonGroupCenter` × n + `ButtonGroupRight`, `ButtonGroupDivider`
  (cap 6) between segments, six visible segments of ~53 pt on a 320 pt screen, the current section
  held permanently in `ButtonGroupCenter_Highlighted`. Cover glyphs 22 × 22 centred in the segment.
  With more than six sets the bar scrolls horizontally inside its own art — same rule the folders
  bar uses. Trending carries a `DialogListUnreadBadge` (height 21, min width 27) at the segment's
  top-right, `boldSystemFontOfSize:11` white with the `#8091a6` `(0,-1)` shadow.
- **Tapping** a segment sets the table's `contentOffset` to that section header's y with no
  animation (animating a 216 pt jump on an A5 stutters visibly). Tapping a tile sends immediately —
  no confirmation — and pushes the sticker to the front of Frequently Used.
- **Scrolling** drives the tab strip the other way: on `scrollViewDidScroll` the segment whose
  section contains `contentOffset.y + 8` becomes highlighted. Sets scrolled past are marked viewed
  via `viewTrendingStickerSets` on `scrollViewDidEndDecelerating`, never during the scroll.
- **Custom emoji in text** (drawn in the top bubble of the mockup): each `textEntityTypeCustomEmoji`
  entity becomes an **18 × 18** image box inline in the message's own line layout. Since there is no
  TextKit, the bubble's text is measured run by run with `sizeWithFont:` around each entity, the
  glyph box is reserved at the run boundary with a baseline offset of −4, and the image is drawn into
  the bubble's own `drawRect:`, not as a subview. Until the file downloads the box holds the
  entity's fallback plain emoji at 15 pt, so the line never reflows when the image lands.
- **Reuses:** `TGStickerPanelView` and its `TGViewRecycler`, `Cell102`, `CategoryDivider`,
  `ButtonGroup*`, `DialogListUnreadBadge`, `UIImage+WebP`, `TGLottieView`, the existing composer.
- **Costs.** Roughly 400 lines on top of what exists (tab strip, trending section, badge
  bookkeeping) plus ~250 lines of inline-run layout in the bubble drawing, which is the genuinely
  hard part. Memory: 96 decoded 72 pt thumbnails at ~21 KB each ≈ 2 MB steady state, plus one Lottie
  surface.
- **Gives up.** The panel is a long list, so reaching set #9 means a fling or a tab tap; and because
  everything shares one scroll view, a badly behaved set with 200 stickers makes that scroll long.
  Search is not shown in the drawn state — it is a 44 pt bar that appears above the grid when the
  first tab is pulled down, which costs 44 pt of an already short panel.

## Option B — Library (table-only, no in-chat grid)

**File:** `svg/stickers-emoji-b.svg`

Browsing lives entirely in a pushed screen under Settings; the chat gets only the existing recents
strip. This is the most 2013-native answer in the pile: it is a grouped-ish plain table, and nothing
in it is invented.

- **Structure.** 44 pt search bar; a `TRENDING` section header (25, `#88929c`-shadowed white label)
  carrying the unread badge; trending rows at **78**; an `INSTALLED` header; installed set rows at
  **51** — cover 40 × 40 at x 5 y +5 corner radius 4, title `systemFontOfSize:19` at x 49, subtitle
  `systemFontOfSize:13` `#888888` at x 50, `DialogListArrow` at right inset 12.
- **The trending row is the one new cell type.** Title bold 15 at (10, +19), subtitle 13 at (10,
  +33), a cover strip of five 34 pt glyphs at x 10, 58, 106, 154, 202, y +38, and a
  `GroupedActionButtonGreen` **70 × 30** at x 240, y +7 with `ADD` in `boldSystemFontOfSize:14` white
  and the `(0,-1)` shadow. Tapping ADD calls `changeStickerSet` and the button collapses to the
  plain 51 pt installed row with a fade.
- **Tapping** a set row pushes a set-preview screen: the same plated 78 pt grid rows as option A,
  with a full-width `GroupedActionButton` ADD/REMOVE docked at the bottom in a 45 pt `Footer` strip.
  Swipe-to-delete on an installed row uses the standard 61 × 31 delete button. `Edit` in the nav bar
  turns on `setEditing:` for reordering — `reorderInstalledStickerSets` on commit.
- **Reuses:** `TGStickersViewController` (already 1538 lines), `TGSearchViewController` patterns,
  the 51 pt contact-cell geometry, `GroupedActionButton*`, `DialogListArrow`, `Footer`.
- **Costs.** The cheapest by a distance: one new cell class and one preview screen, maybe 300 lines
  total. Memory is a handful of 34 pt covers per visible row — well under 1 MB.
- **Gives up.** Sending. There is no fast in-chat picker beyond the recents strip, so choosing a
  sticker mid-conversation means leaving the chat. For a client whose point is chatting, that is a
  real loss — this option is the *management* half of the feature and should ship alongside A or C,
  not instead of them.

## Option C — Paged decks

**File:** `svg/stickers-emoji-c.svg`

The panel is not a long scroll but a horizontally paged `UIScrollView` with `pagingEnabled`: one
screenful per page, exactly **eight tiles** (two 78 pt plated rows), a set spilling over into as many
pages as it needs.

- **Structure inside the 216 pt panel.** A 30 pt header strip (`#e4e9f0`→`#dfe4eb`, hairline
  `#c2cad4`) with the current set's name centred in bold 13 `#697487` and chevrons at x 8 and 306;
  two `Cell102` rows at y +30 and +108; a 30 pt bottom band holding the page dots centred and two
  `GroupedActionButton` chips 60 × 21 at x 8 (`SETS`, pushes option B) and x 252 (`RECENT`).
- **Why paging.** Memory becomes provably bounded: at most three pages are alive (previous, current,
  next) = 24 thumbnails, and everything else is released on `scrollViewDidEndDecelerating`. On a
  512 MB device with one core, a bounded working set is worth more than smooth infinite scroll, and
  paging gives the scroll view a natural place to stop decoding.
- **Long-press preview** is the demo state drawn: hold a tile for 0.35 s and a 176 × 176 rounded
  white plate (radius 8, 96% opaque) appears centred over the chat area, dimmed `rgba(0,0,0,0.28)`
  behind it, caption bold 13 `#697487` at the bottom. **This is the one place a sticker animates.**
  Dragging the finger across tiles retargets the preview by hit-testing the paged scroll view;
  releasing sends. Lifting outside a tile cancels.
- **Downloading tiles** show a 60 × 60 grey `#cfd6de` rounded rect inset 6 in the 72 pt tile — the
  cheap fallback for the sticker-outline feature, which needs `getStickerOutlineSvgPath` and
  CoreGraphics path drawing to do properly and is not worth it here.
- **Reuses:** the same plated rows and tile class as A, `GroupedActionButton`, and the overlay
  window pattern from `TGPopupMenu`.
- **Costs.** ~500 lines: the pager, the page-index maths that packs a set of n stickers into
  `ceil(n/8)` pages, the long-press tracker. Steady memory ~1 MB.
- **Gives up.** Sets no longer read as one continuous shelf, and a set of 9 stickers wastes most of
  a second page. There is no persistent tab strip, so hopping to a specific set means paging or a
  round trip through the SETS screen — a genuine step backwards for someone with 15 sets installed.

---

## Recommendation

**Ship A, and ship B beside it.** A is the option the codebase is already 70% of the way toward —
`TGStickerPanelView` exists with sections, a recycler, a purge distance and a cache limit, and
re-dressing it as plated `Cell102` rows with a `ButtonGroup` tab strip is finishing work rather than
new work. B is not really a competitor: it is the management surface (install, archive, reorder,
trending) that A has nowhere sensible to put, and it costs almost nothing because it is a table of
51 pt rows with one new 78 pt cell. C's bounded-memory argument is the best technical argument in
this document, but `UITableView`'s own recycling plus the existing purge distance already bound the
working set to roughly the same 2 MB, so C pays a real usability tax — no tab strip, wasted half
pages — for a guarantee we can get without it. Take one thing from C regardless: **the long-press
preview overlay is where the single Lottie instance should live**, because it is the one moment the
user is looking at exactly one sticker and nothing else is scrolling.

## What cannot be built on this hardware

- **Video (WEBM/VP9) stickers.** iOS 6's AVFoundation has no VP9 decoder and the A5 has no hardware
  path for one. These render as their static WEBP/PNG thumbnail, permanently. Not a policy choice —
  there is no code path that could play them.
- **Many animated stickers at once.** A grid of 8 playing Lottie compositions is 8 CPU rasterisers
  on one core; the panel would drop to single-digit frames and the scroll would stick to the finger.
  Hence the one-instance rule and the play pip. Telegram's modern "everything moves" grid is not
  reproducible here and pretending otherwise would produce a screen that cannot be built as drawn.
- **Sending custom emoji, and setting an emoji status.** Both are Premium-gated server-side; without
  a subscription the server rejects the message. Only the read side — rendering custom emoji that
  arrive in someone else's text — is worth building, which is what option A describes.
- **Creating or editing sticker sets.** A dozen TDLib calls and a multi-screen authoring flow with
  image processing, for something every real user does through @stickers bot. Deliberately out of
  scope.
- **Mask stickers.** They need a photo editor with face detection and interactive placement. No such
  editor exists in the client and building one for a 4S is not defensible.
- **Emoji suggestions URL.** The returned page assumes a current JavaScript engine; iOS 6 has only
  the old UIWebView. It cannot be usefully rendered.
- **Gesture-driven interactive dismissal of the preview overlay**, and any view-controller transition
  beyond push and modal. The long-press overlay in C is therefore a plain window fade at 0.15 s, not
  an interactive pull-away.

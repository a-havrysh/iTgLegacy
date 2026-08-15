# Links and previews

Three answers to: how much of the modern link stack — in-bubble previews, Instant View, tap routing
— is worth building on a 4S, and where the honest line is between "render it ourselves" and "hand
the URL to Safari".

All three share one thing that is not optional and is not really a design choice: **tappable text
entities**. Nothing in `src/` renders entities today, and iOS 6 has no link hit-testing in a
`UILabel`. The message body has to become a CoreText-drawn label that keeps a list of run rectangles
per entity so `touchesEnded:` can map a point back to a URL. That is a prerequisite for every option
below, so it is not a differentiator — it just has to be paid once. The run styling is fixed:
tappable runs draw in `#0779D0` (the action/link colour from the palette), no underline, at the same
`[[TGTheme shared] messageFontSize]` as the body; a pressed run gets the existing attachment
highlight wash `rgba(#5E7590, 0.2)` behind its rectangles, no other state.

---

## Option A — Compact preview footer, Safari for everything

`svg/web-and-links-a.svg`

**What it does.** The link preview becomes a block appended inside the existing bubble, below the
message text, exactly the way TWELVE's `TGArticleWebpageFooterModel` does it. Geometry, all of it
derived from metrics already in the rulebook:

- The block starts `9pt` below the last text line, inside the bubble's own content box (bubble text
  origin is `bubble.x + kPadH` = +10, and `kBubbleMaxW` 240 + 2×10 caps the bubble at 260 wide).
- A **2pt vertical accent bar** at the content origin, full block height — the reply-header idiom
  from `layout-metrics.md §7`. Colour follows the forwarded-header rule already in the palette:
  `#0E7ACD` incoming, `#3A8E26` outgoing.
- Text column starts **+10** from the bar (2 + 8 gap, the reply-quote rule).
- Site name: **bold system 14**, accent colour, one line, 17pt.
- Title: **bold system 14**, `#141617`, max two lines at 16pt each.
- Description: **system 14**, `#62768A` (the attachment-subtitle colour), max one line, truncated
  with a tail ellipsis.
- Thumbnail: **52×52, corner radius 4** (`round(52/11) ≈ 5`, snapped to the `avatar40` radius family
  because it sits at the same size class), right-aligned at content-right, top-aligned with the site
  name. Absent thumbnail simply widens the text column; the block never reserves empty space.
- Block height is therefore 17 + (16 or 32) + 17 clamped to a minimum of 52 so the thumbnail always
  fits; measured once in the height pass and cached on the row model, like every other bubble metric
  in `TGChatViewController`.

Non-article preview types (photo, video, document, voice, sticker) drop the whole footer and instead
render the media view the app already has for a real message of that kind, with the site/title lines
above it. That is the "trivial" catalogue row, and it stays trivial only if the container above is
this dumb.

**Tapping.** Anywhere in the preview block, or on a link run in the text, goes through one
`TGLinkRouter`. `getInternalLinkType` decides: a `t.me` username, message, sticker set or invite is
pushed onto our own navigation stack; anything else raises a `TGActionSheet` titled with the bare
host (`theverge.com`), buttons **Open in Safari** / **Copy Link** / **Cancel**, and then
`[UIApplication openURL:]`. `skip_confirmation` from `getExternalLinkInfo` short-circuits the sheet.
A long press on a link run raises the same sheet plus **Copy**. Instant View is not built at all: an
article with `instant_view_version > 0` looks identical to one without.

**Scrolling.** No change in behaviour. The block is subviews of the existing cell, recycled with it.
Thumbnails come from the file cache the app already has; the fetch is issued in
`willDisplayCell:` and cancelled in `didEndDisplaying:`, so a fast flick downloads nothing.

**Reuses.** `TGBubbleCell` (three more `UILabel`s and one `UIImageView`), the existing
`TGActionSheet`, the existing file download/cache path, `TGIcons` for the rounded corner
pre-scaling.

**Costs.** Roughly one measurement function and one layout function on the existing cell, plus the
router. Memory: one extra 52×52 decoded bitmap per visible preview — under 11KB each, negligible
next to the 200pt photos the app already keeps.

**Gives up.** Instant View entirely. Large-media layout: every preview is the small variant, so a
photo-forward article looks the same as a text one. That is the real loss — Telegram's channels lean
hard on `show_large_media`, and posts designed around a hero image read as a grey 52pt square here.

---

## Option B — Native Instant View reader, built from page blocks

`svg/web-and-links-b.svg`

**What it does.** Option A's bubble, plus two things. First, the **large-media variant**: when
`has_large_media && show_large_media`, the thumbnail becomes a full-content-width image above the
text (240 wide, height clamped to `min(natural, 160)`, corners 6 to match `kMediaRadius` already in
the chat controller), and `show_media_above_description` chooses whether the site/title lines sit
above or below it. Second, when `instant_view_version > 0`, a **full-width button strip at the
bottom of the bubble**: 34pt tall, `GroupedActionButton` art stretched with cap 24 (the same
in-bubble action button the rulebook already defines), label **bold system 13** in `#506E8D` with
its `rgba(#FFFFFF,0.7)` shadow at `(0,+1)`, reading `INSTANT VIEW`.

That button pushes the reader in the mockup: a plain `UITableView` on white, one cell class per
block type, no web view anywhere. `getWebPageInstantView` is called with `only_local:true` first so a
cached article paints instantly, then again from the network.

Block metrics, chosen so an agent building it does not have to invent any:

- Text column inset **15** left and right (290 wide), matching nothing in the original because the
  original has no article — so it is a ruling, derived from the 15pt back-button cap and the settings
  10pt inset rounded up for a full-bleed reading surface.
- `pageBlockKicker` / site name: **bold system 12**, `#0E7ACD`, uppercased, 1pt tracking.
- `pageBlockTitle`: **bold system 19** (the largest size in the scale), `#141617`, 21pt lines.
- `pageBlockSubtitle`: system 15, `#62768A`.
- `pageBlockAuthorDate`: system 13, `#999999` (the forwarded-date colour).
- `pageBlockParagraph`: system 15 — derived from `messageFontSize` so the reader honours the
  user's text-size setting — `#141617`, 19pt lines, 11pt gap between paragraphs.
- `pageBlockHeader` bold 17, `pageBlockSubheader` bold 15, `pageBlockSectionHeading` bold 17 with a
  `CategoryDivider` hairline 8pt above it.
- `pageBlockBlockQuote` / `pageBlockPullQuote`: the same **2pt accent bar** in `#0E7ACD`, text
  column +10, italic 15.
- `pageBlockList`: bullet or number in system 15 `#697487` in a 20pt gutter, body at x 35.
- `pageBlockPreformatted`: Courier 13 on a `#EEF1F4` plate, inset 15, horizontally scrollable.
- `pageBlockPhoto` / `Cover`: full-bleed 320 wide, decoded **through
  `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = 640`** so a 2000px
  press photo never lands in RAM whole. Caption below at system 13 `#697487`, inset 15.
- Footer: view count and "Leave a comment" as one 44pt row with a `CategoryDivider` above, and the
  nav bar carries a `HeaderButton` **Share** that raises the existing action sheet.

**Tapping.** Links inside the article reuse the same CoreText run label and the same router, so a
`t.me` link inside an article opens a chat and an external one raises the domain sheet. Anchor links
scroll the table. Blocks that cannot be rendered — embeds, maps, tables — degrade in place to a 66pt
plate with a title and "Tap to open in Safari", carrying the poster image where one exists.

**Scrolling.** Standard `UITableView` reuse with a heights array computed once on load. The whole
article's block heights are measured up front, which on a long piece is maybe 300 measurements of
CoreText framesetters — around 60–120ms on a 4S. Do it off the main thread and show the nav-bar
title only when it lands.

**Reuses.** The CoreText run label from the shared prerequisite, the file cache, `TGActionSheet`,
`TGIcons`, `CategoryDivider`, `GroupedActionButton`, the standard nav bar.

**Costs.** The biggest item in the area: roughly a dozen cell classes, a rich-text-tree to
`NSAttributedString` builder, and a measurement pass. Memory is bounded by the table's own reuse plus
the downscaled images — a 320×200 decoded image is 256KB, so cap the in-memory article image cache at
about six and evict on `didReceiveMemoryWarning`.

**Gives up.** v2 blocks (tables, collapsible details, related articles) in the first pass; embeds and
maps permanently. And it will not match telegram.org's rendering pixel for pixel — this is a 2013
reading surface, not a modern one.

---

## Option C — UIWebView reader over locally generated HTML

`svg/web-and-links-c.svg`

**What it does.** Same bubble as B, same INSTANT VIEW strip, but behind it the reader turns the page
blocks into an HTML string with an inlined stylesheet and hands it to a `UIWebView` via
`loadHTMLString:baseURL:`. No remote content is ever loaded — images are served from the local file
cache through a `file://` base URL — so this is not "just open the page", it is still Instant View,
rendered by WebKit instead of by us. The chrome is ours: nav bar with the host as title and the load
state as the subtitle, a 2pt progress line under the bar, and a 44pt `Footer` toolbar with a
back/forward group-button pair and an **Open in Safari** `GroupedActionButton` at right.

**Tapping.** `shouldStartLoadWithRequest:` intercepts every navigation: `tg://` and `t.me` go to the
router, anything else raises the domain sheet or opens Safari. Internal anchors are allowed through.

**Scrolling.** The web view scrolls itself, which is the visible tell — momentum, rubber-banding and
tap highlight are WebKit's, not `UITableView`'s, and they do not feel like the rest of the app. On a
4S a long article in `UIWebView` also scrolls measurably worse than a table of pre-measured cells,
because tiles are re-rasterised during the flick.

**Reuses.** Almost nothing from our component set beyond the bar chrome — that is the point and the
problem.

**Costs.** Far less code than B: one template, one stylesheet, one delegate. Far more memory:
`UIWebView` on iOS 6 costs 8–15MB resident for a modest article and does not give it back promptly,
against a 512MB device where the app already holds a chat table and an image cache. Two of these on
the navigation stack is a memory warning.

**Gives up.** The typography stops being ours: WebKit's line breaking, its default link colour, its
selection UI. The user's message-text-size setting no longer applies unless we plumb it into the
stylesheet. And the rendering surface is a black box — no way to reuse the tap-run machinery, no way
to hook a block-level long press, no way to lay a 2013 quote bar next to text and be sure it lines
up.

---

## Recommendation

**Ship A first, then B.** A is a week of work on components that already exist, and it delivers the
thing users actually notice a hundred times a day — a link in a chat that looks like a link and shows
what it points at. It is also the piece B depends on: B's bubble *is* A's bubble with a large-media
variant and a button strip.

B is the right reader, and C is not. C looks cheaper only until you weigh it: `UIWebView`'s resident
cost on a 512MB phone is the single most likely cause of a jetsam kill in this whole area, and it
buys rendering we then cannot style, cannot instrument, and cannot make feel like the rest of the
app. TDLib hands us structured blocks precisely so we do not need a browser; declining that gift to
save a fortnight of cell classes is the wrong trade on this hardware. Keep `UIWebView` for exactly
one job it is uniquely good at — nothing here — and otherwise hand the URL to Safari, which has the
whole device's memory to itself.

## What genuinely cannot be built here

- **Telegram Mini Apps / Web Apps.** They need `WKWebView` and a `postMessage` bridge, plus modern
  TLS and ES6 to run `telegram-web-app.js`. iOS 6 has neither the JS engine nor the certificate
  stack. These links must show "not supported in this app" and offer Safari.
- **Instant View embedded blocks (YouTube, tweets, iframes).** The supplied HTML is modern JS against
  hosts that now require TLS 1.2 and SNI behaviour the 4S stack does not do. Render the poster photo
  and open Safari.
- **Instant View map blocks.** `MKMapSnapshotter` is iOS 7+; an offscreen `MKMapView` render on a 4S
  is slow and memory-hungry. Static placeholder that opens Maps.
- **Animated/GIF previews (`linkPreviewTypeAnimation`).** Playing an animation inline in a scrolling
  table costs a decoded frame buffer per visible cell; render the static first frame with a play disc
  and open the full player on tap.
- **v2 tables with colspan/rowspan.** Buildable in principle, but the grid measurer plus its own
  horizontal scroll view is a second project; first pass renders a table as a "Open in Safari" plate.
- **Interactive swipe-back out of the reader.** iOS 6 has no interactive pop transition at all. The
  reader is dismissed by the back button, and that is the whole story.

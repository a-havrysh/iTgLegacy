# TGPhotoGridCell — the shared-media photo row (original study)

Original files (read-only authority):

- `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGPhotoGridCell.h` (29 lines)
- `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGPhotoGridCell.m` (228 lines)
- Its only owner: `.../Telegraph/Telegraph/TGPhotoGridController.mm` (970 lines)

The class exists under exactly that name, only in `Telegraph/Telegraph` (there is no copy in
`TelegraphKit`). Its near-twin in TelegraphKit is `TGImagePickerCell.mm`, which shares the
`mediaGridImage` filter (`TGImagePickerCell.mm:127`) but is a different, camera-roll-oriented cell.

## 1. What it is

This is *not* a grid cell in the modern sense. It is a **UITableViewCell that draws one horizontal
row of a photo grid** (`TGPhotoGridCell.h:13`). The shared-media screen is a plain `UITableView`
with `separatorStyle = None` (`TGPhotoGridController.mm:134`); the grid illusion is produced purely
by each row laying out N square thumbnails side by side. Row count is
`count / imagesPerRow + (count % imagesPerRow ? 1 : 0)` (`TGPhotoGridController.mm:227`).

That choice explains almost every property of the cell: it owns no data model, it holds parallel
arrays that the controller refills on every `cellForRow`, and all of its layout happens in
`layoutSubviews` rather than in a setter.

## 2. Public surface (`TGPhotoGridCell.h`)

| Member | Line | Role |
|---|---|---|
| `int numberOfImagePlaces` | h:15 | how many slots this row is allowed to lay out; drives the horizontal centring |
| `NSMutableArray *imageUrls` | h:16 | thumbnail URLs, one per visible tile |
| `NSMutableArray *imageTags` | h:17 | identity per tile — always an `NSNumber` of `message.mid` (`TGPhotoGridController.mm:257`) |
| `NSMutableArray *imageAttachments` | h:18 | the `TGMediaAttachment`, used only to decide whether the video bar is shown |
| `ASHandle *watcherHandle` | h:20 | the tap goes out through this, not through a delegate |
| `-collectCachedPhotos:` | h:22 | pushes each tile's decoded image into a dictionary so the controller can seed a temporary cache (`TGPhotoGridController.mm:335`) |
| `-rectForImageWithTag:` / `-viewForImageWithTag:` | h:24-25 | look up a tile by message id; used by the zoom-in/zoom-out gallery transition |
| `-reloadImagesWithUrl:` | h:27 | force one URL to re-fetch when a download finishes (`TGPhotoGridController.mm:566`) |

The three arrays are allocated once in `initWithStyle:` (`.m:23-27`) and are **never replaced** — the
controller empties them in place (`TGPhotoGridController.mm:253-255`) and refills them. Index `i`
means the same tile in all four arrays (`imageViews`, `imageUrls`, `imageTags`, `imageAttachments`).

## 3. Metrics, with citations

- Tile side: **75 × 75 pt**, `CGSizeMake(75, 75)` (`.m:96`).
- Horizontal gap between tiles: **4 pt**, `int widthSpacing = 4` (`.m:97`).
- Top inset of the tile inside the cell: **4 pt**, `CGRectMake(currentX, 4, …)` (`.m:129`). There is
  no bottom inset in the cell.
- Row height: **79 pt** for a populated row (`TGPhotoGridController.mm:232-234`) = 4 top + 75 tile.
  The visual 4 pt gap below a row is supplied by the *next* row's own top inset; the gap after the
  last row comes from the table's explicit bottom inset of 4
  (`setExplicitTableInset:UIEdgeInsetsMake(0, 0, 4, 0)`, `TGPhotoGridController.mm:131`).
  This is why 79 and not 83: the spacing is owned by the top edge only, once.
- Tiles per row: `(int)(screenWidth / (75 + 4))` (`TGPhotoGridController.mm:126`, recomputed on
  rotation at `:216`). On a 320 pt iPhone this is `(int)4.05 = 4`; landscape 480 pt gives 6.
- Row content is **centred**: `currentX = (int)((width - (n*75 + (n-1)*4)) / 2)` (`.m:98`), where `n`
  is `numberOfImagePlaces`, not the number of images actually present. On 320 pt: used = 312,
  leading margin = 4. In landscape 480 pt: used = 470, margin = 5. The `(int)` cast pins the origin
  to whole points, so the row is never blurry, and can be one point left of true centre.
- Video bar: **75 × 19 pt**, pinned to the tile's bottom, `CGRectMake(0, 75 - 19, 75, 19)` (`.m:162`).
- Video bar colour: **`UIColorRGBA(0x000000, 0.6)`** (`.m:159`).
- Video play glyph: `MessageInlineVideoIcon.png` (`.m:157`), natural size 32 × 18 px @2x = **16 × 9 pt**
  (measured from `Resources/MessageInlineVideoIcon@2x.png`), placed at offset **(4, 5)** inside the bar
  (`.m:168`) — i.e. optically centred in the 19 pt bar (5 + 9 + 5).
- Duration label: frame `CGRectMake(75 - 56 - 3, 0, 56, 19)` (`.m:171`) — 56 pt wide, right-aligned
  (`.m:176`), 3 pt from the tile's right edge, full bar height, `boldSystemFontOfSize:10` (`.m:158`),
  white on clear (`.m:173-175`).
- Duration text: `"%d:%02d"` from `duration / 60` and `duration % 60` (`.m:186-188`). There is no
  hours form; a 90-minute video renders as `90:00`. The 56 pt box is generous enough that this never
  clips at 10 pt bold.

## 4. Artwork

- **Placeholder**: `[TGInterfaceAssets mediaGridImagePlaceholder]` (`.m:100`) → `FlatImagePlaceholder.png`
  (`TGInterfaceAssets.mm:749-754`), a 16 × 16 px @2x (8 × 8 pt) flat swatch, stretched across the
  tile by `UIViewContentModeScaleAspectFill` (`.m:115`).
- **Shadow / vignette**: `[TGInterfaceAssets mediaGridImageShadow]` (`.m:101`) → `MediaGridImageShadow.png`
  put through `TGStretchableImageInCenterWithName` (`TGInterfaceAssets.mm:757-762`), i.e. caps at half
  the width and half the height (`TGInterfaceAssets.mm:14`). The asset is 150 × 150 px @2x = **75 × 75 pt**,
  exactly the tile, so in practice it is drawn 1:1 and the stretchability never engages. It is a
  `UIImageView` created with `initWithImage:` and **never given a frame** (`.m:121-122`), so it sits at
  (0,0) at its natural 75 × 75 size, filling the tile. It is added as a subview of the tile *before* the
  video bar (`.m:122` vs `.m:179`), so the bar draws over the vignette.
- No corner rounding: the filter passes radius `0` (`TGTelegraph.mm:642` block, `TGScaleAndRoundCorners(source, imageSize, CGSizeMake(75,75), 0, nil, true, nil)`).
  2013 shared media is square-cornered; the only edge treatment is the shadow overlay.

## 5. The image filter

Thumbnails are loaded with `filter:@"mediaGridImage"` (`.m:142`). That processor
(`TGTelegraph.mm:620-642`) scales the source so its **shorter side becomes exactly 75**, then crops to
75 × 75 — an aspect-fill centre crop baked into the cached bitmap, not done by the view. So the
`UIViewContentModeScaleAspectFill` on the view (`.m:115`) is only insurance for the placeholder and
for the pre-filter fade image. Any port that loads a raw thumbnail and lets the view crop will look
right at first glance but will differ in sharpness, because the original rasterises at exactly the
displayed size.

## 6. Behaviour

**Layout / reuse.** Everything is in `layoutSubviews` (`.m:92-197`), triggered by the controller's
explicit `[gridCell setNeedsLayout]` after refilling the arrays (`TGPhotoGridController.mm:260`).
Views are created lazily up to `limit = MAX(numberOfImagePlaces, count)` (`.m:105`) and **never
destroyed** — a cell that once laid out 6 tiles in landscape keeps 6 `TGRemoteImageView`s forever and
simply hides the surplus. Slots beyond `imageUrls.count` get `loadImage:nil` and `hidden = true`
(`.m:132-136`); that is the empty-slot answer for a short final row.

**The URL guard.** A tile only reloads when its URL actually changed:
`if (imageView.currentUrl == nil || ![imageView.currentUrl isEqualToString:…])` (`.m:140`). This is the
cheap reuse trick — scrolling a recycled cell whose slot 2 already holds the right URL costs nothing.
It also carries a real original defect: the **video-bar update lives inside that guard** (`.m:144-193`),
so if a recycled cell ends up with the identical URL in the same slot but a different attachment
kind, a stale duration bar survives. In practice URLs are unique per message, so it does not bite.

**Tap.** Each tile gets its own `UITapGestureRecognizer` at creation (`.m:118-119`); the cell has
`selectionStyle = None` (`TGPhotoGridController.mm:249`), so there is **no highlight of any kind** on
touch — the only feedback is the gallery opening. The handler (`.m:199-226`) bails if
`currentImage == nil`, resolves the tile's index → tag, and fires the ASWatcher action
`@"openImage"` with `image`, `rectInWindowCoords` (`[remoteImageView convertRect:bounds toView:self.window]`)
and `tag` (`.m:222`). Note `currentImage` returns whatever is on the layer, placeholder included
(`TelegraphKit/TGRemoteImageView.m:189-201`), so the real gate on "not loaded yet" is downstream: the
controller only presents if a cached thumbnail exists (`TGPhotoGridController.mm:855`). The
transition is a zoom from that window rect, `animateAppear:anchorForImage:fromRect:fromImage:start:`,
whose `start` block hides the source tile (`TGPhotoGridController.mm:869-872`). `hideImage` /
`closeImage` later toggle the same tile's `hidden` via `viewForImageWithTag:`
(`TGPhotoGridController.mm:918, 953`). **The tile lookup methods exist to serve that animation**, and
that is the whole reason the cell exposes geometry at all.

**Download completion.** `reloadImagesWithUrl:` (`.m:76-90`) re-issues the load with the currently
displayed image as the placeholder and `forceFade:true` when one exists, so a thumbnail that arrives
late cross-fades rather than popping. It also unhides `placeholderOverlay` handling (`.m:86`).

**Missing URL.** The controller skips a message whose `additionalProperties[@"url"]` is nil entirely
(`TGPhotoGridController.mm:254-259`): no tile, no gap — the row just holds fewer items and the
following items do **not** shift up into it, because row membership was computed by index earlier.
So a row can visibly contain 3 tiles in the middle of the list.

**Dead code in the original.** `_imageShadows` is declared and allocated (`.m:12, :24`) and never
used; the `shadowView` local (`.m:109, :121`) is written and dropped. Also `rectForImageWithTag:`
returns `CGRectZero` on miss (`.m:55`) while every caller tests `CGRectIsNull` (e.g.
`TGPhotoGridController.mm:800`), so a miss is silently treated as a valid zero rect.

## 7. Our port

Our equivalent is **inlined into the shared-media screen**, not a standalone class:
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGMediaViewController.m` — `TGMediaTileView`
(line 370) plus `TGMediaGridCell` (line 480). It is largely faithful: 75 pt tile, 4 pt spacing,
79 pt row height, 4 pt bottom content inset, centred row, `black 0.6` bar 19 pt tall, bold 10 pt
right-aligned label 56 pt wide 3 pt from the edge, play glyph at (4,5), `MediaGridImageShadow.png`
and `FlatImagePlaceholder.png` both shipped in `images/` and both used. Constants at lines 17-19,
badge at 417-441, layout at 588-609. Nothing to change there.

Real differences a user can see:

1. **No zoom transition into the gallery.** We call
   `presentViewController:viewer animated:YES` (`TGMediaViewController.m:2930`) — the standard modal
   slide-up — where the original zooms the tapped tile out to full screen from its window rect and
   hides the source tile for the duration (`TGPhotoGridController.mm:869-872`). This is the single
   biggest behavioural gap; our `TGMediaGridCell` already knows each tile's frame
   (`TGMediaViewController.m:604`), so the rect is available.
2. **Shadow is force-stretched.** We re-stretch the 75 pt asset and then set
   `_shadowView.frame = self.bounds` on every layout (`TGMediaViewController.m:399, 409-411`). The
   original never resizes it (`.m:121-122`). Identical at 75 pt, so this is only a latent difference —
   but it means our vignette will silently distort if the tile side is ever changed, where the
   original would have clipped instead. Not user-visible today.
3. **Tap handling is per-row, not per-tile, with 2 pt slop.** `handleTap:` hit-tests
   `CGRectInset(tile.frame, -2, -2)` (`TGMediaViewController.m:618`), so the 4 pt gutters are live and
   a touch in the gap opens a neighbour. The original attaches a recognizer to each tile
   (`.m:118-119`), so gutters are dead. Minor, but it makes edge taps feel less precise than 2013.
4. **Placeholder colour fallback.** If `FlatImagePlaceholder.png` is missing we synthesise
   `#dfe4eb` (`TGMediaViewController.m:28-36, 65-80`) and additionally set it as the tile's
   `backgroundColor` (`:392`). The original has no fallback and no background colour. Harmless, but
   the `#dfe4eb` value is ours, not a cited original colour — do not treat it as period-accurate.
5. **Tiles are created exactly per item**, and surplus tiles are recycled/removed
   (`TGMediaViewController.m:548-558`); the original keeps hidden surplus views forever (`.m:105`).
   Ours is strictly better on a 4S and produces the same picture.
6. **We gate the tap on the placeholder identity** (`TGMediaViewController.m:619-621`) where the
   original gates downstream on the thumbnail cache. Same outcome; ours is clearer.

## 8. What became of it

**twelve** (`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGPhotoGridCell.m`) is the same file,
line for line, with four deliberate edits — and they are the interesting part, because they are the
2013→2015 visual shift applied to this exact component:

- tile side `TGIsRetina() ? 78.5f : 78.0f`, spacing `2`, `currentX` starting at **0** rather than a
  centred inset (`twelve/…/TGPhotoGridCell.m:96-99`), and the last tile of a full row right-aligned
  to `self.frame.size.width - side` (`:126`). That is edge-to-edge four-across with a hairline gutter,
  the modern shared-media look, replacing the inset floating-thumbnails look of 2013.
- top inset drops from 4 to **2** (`:126`).
- the **shadow overlay is deleted** (`:101, :120` removed). Flat design: no vignette.
- `contentHints = TGRemoteImageContentHintBlurRemote` added (`:112`) — blurred low-res preview while
  loading, a capability that did not exist in the original.

**Telegram-iOS today** abandoned UITableView-rows-as-grid entirely. Shared media is
`SparseItemGrid` (`submodules/SparseItemGrid/Sources/SparseItemGrid.swift`) inside
`PeerInfoVisualMediaPaneNode`. The layout ideas that survived and the ones that did not:

- Item spacing is now **1.0 pt** and layout is edge-to-edge, with the last column absorbing the
  rounding remainder (`SparseItemGrid.swift:462, 472, 481-482, 492`) — no centring at all. Confirms
  twelve's direction: the centred 4 pt-inset row is the one thing that reads as unmistakably 2013.
- Tile size is derived from `itemsPerRow` (a pinch-driven zoom level), not fixed at 75
  (`SparseItemGrid.swift:464-472, 1789`). The 75 pt constant died with fixed-width phones.
- The duration bar became a **`DurationLayer` pill** anchored to the bottom-right corner with a soft
  shadow (`PeerInfoVisualMediaPaneNode.swift:260-302, 401-402, 486`), replacing the full-width 19 pt
  black strip. Taste, not necessity.
- The tap-to-zoom-from-rect transition survived thirteen years unchanged in spirit — which is why
  difference (1) above is worth fixing in our port.
- Two things the original had no concept of and which forced structural change: **selection**
  (`GridMessageSelectionLayer`, `:305, 431-453`) and sparse/holey backing data. Neither is a change of
  taste; both are new features.

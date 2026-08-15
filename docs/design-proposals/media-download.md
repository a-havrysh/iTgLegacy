# Media and downloads

*A download manager and a shared-media grid, with no UICollectionView and very little memory for
thumbnails.*

Catalogue entries in scope (area `media-download`, bucket `design`): the downloads list screen
(active/paused/completed, fed by `searchFileDownloads` + the four `updateFileDownload*` updates), the
full-size photo viewer with progressive load, upload progress and cancel on outgoing media, the
minithumbnail blurred placeholder, per-chat storage breakdown, streaming byte-range download, and the
file-generation protocol. Only the first four have a surface on the two screens below; the rest are
plumbing or live on other screens, and are dealt with at the end.

Three constraints shape everything here.

1. **No `UICollectionView`.** iOS 6.1.3. Any grid is either a `UITableView` whose cells each draw a
   row of tiles, or a `UIScrollView` with manually framed subviews that you recycle yourself.
2. **Thumbnail memory.** A 79 pt tile at @2x is 158×158 px; decoded 32-bit that is ~100 KB. Sixteen
   visible tiles is 1.6 MB, which is fine; a naive `NSMutableDictionary` cache of a thousand of them
   is 100 MB, which kills the app on a 512 MB device. Whatever the layout, the thumbnail cache has to
   be an `NSCache` with a hard count limit and every off-screen tile must drop its `UIImage`.
3. **Live progress.** TDLib sends `updateFileDownload` per file, several times a second per active
   download. Redrawing a whole cell on each one is a scroll-killer on an A5. Progress must be a
   1–2 pt bar whose *width* changes, never a re-laid-out cell, and updates must be coalesced on a
   timer.

All three options use the grid geometry the rulebook already fixes
(`layout-metrics.md` §7): tile side `floorf((width - 3) / 4)` = **79 pt**, 1 pt gutter, 4 columns
portrait / 6 landscape, tiles meeting the screen edges, section header 25 pt. The last column takes
the leftover point (80 pt wide) so the grid is flush right.

---

## Option A — Downloads banner over a table-backed grid

**File:** `svg/media-download-a.svg`

**What it does.** One screen, Shared Media, reached from the chat-info screen. The grid is a plain
`UITableView` with `separatorStyle = None`; each cell is 80 pt tall and draws **four** 79×79 tiles
side by side at x = 0, 80, 160, 240. Month sections are real table sections with a 25 pt header
(`#E4E9F0` ground, `boldSystemFontOfSize:15` in `#697487` with the `rgba(#FFFFFF,0.3)` `(0,+1)`
shadow). The download manager is a **44 pt banner** installed as the table's `tableHeaderView` —
exactly the rulebook's "any new top-aligned banner" (`layout-metrics.md` §7): full width, no rounded
corners, one `#D5DEE5` hairline at the bottom. It carries "Downloading 2 files" in bold 15 `#516691`,
a 13 pt `#888888` line with bytes and rate, a 2 pt progress bar from x = 10 to x = 250, the aggregate
percentage in 16 pt `#356596` right-aligned at x = 292, and a disclosure chevron. When nothing is
downloading the banner's height goes to 0 and the table header disappears.

**Tapped.** Tapping a tile pushes the full-screen photo viewer (thumbnail immediately, full JPEG
faded in on `updateFile` completion). Tapping the banner pushes a dedicated Downloads table — the
same 51 pt rows drawn in option B, on their own screen. Tapping "Select" puts the grid into
multi-select: each tile grows a 29×29 check at its top-left corner (the contact cell's selection
geometry, resting scale 0.8, peak 1.16) and a toolbar of `ButtonGroupLeft/Center/Right` appears.
A tile that is still downloading dims to 35 % black and shows a 28 pt progress ring with a stop
square — tapping it cancels rather than opening.

**Scrolled.** `UITableView` cell reuse does the memory work for free: a recycled row-cell drops the
four `UIImage`s it held in `prepareForReuse`, and only rows within the visible rect ever hold decoded
thumbnails. Thumbnail decode happens on a serial background queue keyed by file id; the tile shows
the `minithumbnail` blurred JPEG (a ~40×40 decode, upscaled with `CGContextSetInterpolationQuality
(kCGInterpolationLow)` — that *is* the blur, no CIFilter needed) until the real one arrives.

**Reuses.** `UITableView` + `TGActionTableView` conventions, the 25 pt section header treatment from
the contacts list, `CategoryDivider` artwork for the section rule, the standard nav bar via
`+[TGIcons headerButtonWithTitle:bold:target:action:]`, `Video-play-button` for the video badge, and
the existing 44 pt banner pattern already used elsewhere in `src/`.

**Cost.** The smallest of the three. One `UITableViewCell` subclass holding four `UIImageView`s, one
banner view, one `NSCache` (count limit ~48). No hand-written recycling, no scroll-offset maths.
Peak thumbnail memory ≈ 6 visible rows × 4 tiles × 100 KB ≈ 2.4 MB.

**Gives up.** Sections must be month-aligned to row boundaries, so a month with 6 items still costs
two rows and the last row is ragged — which is correct but means you cannot have a continuous
un-sectioned grid. The banner scrolls away with the content, so once you are 200 pt down the grid
there is no visible download state until you scroll back. Landscape's 6 columns means the cell class
has to re-key its tile count on rotation and reload, which flickers.

---

## Option B — Downloads as a fourth scope of Shared Media

**File:** `svg/media-download-b.svg`

**What it does.** Same screen, but the top of it is a 44 pt scope strip in bar blue holding four
`SearchBarScopeButton` segments — Media, Files, Links, **Downloads** — drawn per the rulebook's
folders ruling (`typography-colour.md` §5): caption `boldSystemFontOfSize:12`, selected white with
`rgba(#112E5C,0.2)` shadow, unselected `#5C708B` with `rgba(#FFFFFF,0.25)`. The mockup shows the
Downloads scope selected, so the download manager gets the *whole* screen rather than a banner.

Rows are the canonical **51 pt** `Cell102` / `CellHighlighted102` plate. Layout per row: file-type
icon 40×40 at (5, 5) using the bundled `filetype_icon_*-island` art keyed off the MIME type; text
column at x = 49 (the contact-cell column); title `boldSystemFontOfSize:15` `#111111` (the
attachment-title size, not 19 — file names are long); subtitle `systemFontOfSize:13` `#888888`
carrying "sender · N MB of M MB · rate"; a 2 pt progress bar from x = 49 to x = 272 at y = row + 40,
track `#D5DEE5`, fill `#0779D0` when active and `#8B97A5` when paused; and a 28 pt pause/resume
control centred at x = 292, drawn as a ring whose stroked arc *is* the per-file progress, so one
control shows state and progress at once. Two sections: DOWNLOADING and COMPLETED, the second with a
"Clear All" affordance in its 25 pt header. Under the table, a comment-view footer in
`systemFontOfSize:14` `#697487` with the `#DAE0E8` `(0,+1)` shadow gives total downloads storage,
which is where `getStorageStatisticsFast` lands.

**Tapped.** Tapping the ring pauses or resumes (`downloadFile` / `cancelDownloadFile` with
`only_if_pending = false`). Tapping an active row does nothing but flash the plate. Tapping a
completed row opens the file — image into the photo viewer, audio into the existing player, anything
else into `UIDocumentInteractionController`. Swipe-left on any row gives the standard 61×31 delete
button at y = 10, right inset per `TG_DELETE_BUTTON_EDGE_OFFSET`, labelled "Remove"; that calls
`removeFileFromDownloads`. Tapping "Clear" in the nav bar clears all completed entries after a
confirm sheet.

**Scrolled.** A normal table with reuse. Pagination is the `searchFileDownloads` offset string:
when the last row becomes visible, fetch the next 40 with the stored `next_offset`. Progress updates
arrive on `updateFileDownload`, are coalesced into a dictionary and flushed by a 0.2 s repeating
timer that only touches the width of the progress bar and the `text` of the subtitle of *visible*
rows — no `reloadData`, no `reloadRowsAtIndexPaths:`.

**Reuses.** `Cell102`/`CellHighlighted102`, `SearchBarScopeButton`, the whole `filetype_icon_*`
family already in `images/`, `MenuDisclosureIndicator` for completed rows, the standard swipe-delete
geometry from `TGDialogListCell`.

**Cost.** One table controller with two sections, one cell subclass, and the paging/coalescing logic.
The download rows themselves hold no bitmaps at all — the file-type icons are shared `UIImage`
instances from the bundle — so this screen's marginal thumbnail memory is essentially zero. The
Media scope of the same controller still needs a grid, so option B is really "option A's grid plus
this"; it does not replace A, it decides *where the manager lives*.

**Gives up.** The scope strip eats 44 pt of a 480 pt screen permanently, which the grid feels. Four
segments at 77 pt each barely fit "Downloads" at bold 12 — it is 62 pt of text in a 77 pt segment,
tight but legal. And a scope strip is a slightly modern gesture; the original only used one inside
search. It also hides the download state entirely while you are on the Media scope, which is worse
than A's banner for the common case of "I tapped download and want to watch it".

---

## Option C — Continuous hand-tiled grid with a docked download tray

**File:** `svg/media-download-c.svg`

**What it does.** The grid is a raw `UIScrollView` with manually framed 79×79 tile views and your own
recycling pool — the literal reading of the rulebook's "lay tiles out yourself inside a
`UIScrollView`". Because layout is free-form, the grid is continuous rather than row-quantised: a
month boundary does not force a new row, and the month label is a **sticky 25 pt strip** pinned to
the top of the scroll area (`#E4E9F0`, bold 15 `#697487`, item count right-aligned in 13 pt),
repositioned in `scrollViewDidScroll:`. The nav bar takes the two-line title treatment
(`boldSystemFontOfSize:16` white + `systemFontOfSize:13` `#C9DCF2` subtitle) to carry the total count.

The download manager is a **44 pt tray docked at the bottom**, always visible, never scrolling away:
a 30 pt file-type glyph at x = 8, "Downloading 3 files" in bold 15 `#516691`, byte/rate line in 13 pt
`#888888`, a 2 pt aggregate progress bar, a `MenuButtonCenter`-plated pause-all button, and a chevron
that pushes the full Downloads list from option B.

**Tapped.** Tile → photo viewer. Tray body → push the Downloads list. Tray pause button → pause every
active download. The tray collapses to zero height with a 0.25 s frame animation when the queue
empties, and slides back in when a download starts, so the grid's `contentInset.bottom` animates with
it.

**Scrolled.** You own everything. On each `scrollViewDidScroll:` you compute the visible row range
from `contentOffset.y / 80`, hand tiles that left the range back to a free pool, and pull tiles for
newly visible rows out of it. The pool is a fixed 32 views; the `NSCache` behind it holds at most 48
decoded thumbnails, and a tile with no cached image shows the `#E4E9F0` placeholder (drawn in the
mockup at row 4, column 2) until its background decode lands. This is exactly the code
`UITableView` writes for you in option A, written again by hand — and it is the part that will have
the bugs.

**Reuses.** Very little beyond the palette, the tile geometry and `MenuButtonCenter`. The sticky
strip borrows the contacts-list sticky header colours; the tray borrows the 44 pt banner rules.

**Cost.** Highest. A recycling pool, a scroll-offset → index mapping, section index maths for the
sticky header, manual rotation relayout, and the tray's inset animation. Realistically 3–4× option
A's code. Memory is *better* controlled than A once it works — you can cap the pool absolutely — but
only if the recycling is right; a leak here is a leak of 100 KB bitmaps.

**Gives up.** Correctness for polish, mostly. It also gives up free `UITableView` behaviours you
would then have to reimplement: scroll-to-top on status-bar tap, the scroll indicator matching content
height, and multi-select highlighting. The permanently docked tray costs 44 pt of grid at all times,
which on a 480 pt screen is a whole tile row.

---

## Recommendation

**Option A for the grid, with option B's table as the screen its banner pushes to.**

A `UITableView` of four-tile rows is the right answer because the memory problem in this theme is
entirely a *recycling* problem, and `UITableView` already solves recycling correctly, on a device
where a hand-rolled pool bug means a 100 KB bitmap leak per scroll. The 1 pt gutter and 79 pt tile
make the row height exactly 80, so the row-quantisation that option A "gives up" costs at most three
blank tiles per month — invisible in practice. The 44 pt banner is the cheapest honest way to show
download state on the media screen, and it is already a sanctioned pattern in the rulebook rather than
an invention.

Option B's 51 pt row design is not really an alternative to A — it is the detailed design of the
downloads screen itself, and it should be built either way. What I would *not* take from B is the
scope strip: four segments across 320 pt is cramped, it permanently costs 44 pt, and it buries
download state behind a tab. Reach the same screen from the banner and from Settings instead, which
is what the catalogue entry already suggests.

Option C is the one to build only if the continuous grid and the always-visible tray turn out to
matter after A ships. They probably will not.

---

## What genuinely cannot be built on this hardware

- **A real blurred minithumbnail.** No `CIFilter` worth using and no `UIVisualEffectView`. The
  reduced version, which is what I drew: decode the tiny JPEG and upscale it with
  `kCGInterpolationLow`, which produces a soft smear that reads as blur at 79 pt. It is not a
  Gaussian and will look like a bad JPEG at full-screen size, so use it only behind tiles and behind
  the photo viewer's initial frame, never as the final image.
- **Interactive, gesture-driven dismissal of the photo viewer** (drag-down-to-close, the tile
  expanding into the full-screen image). iOS 6 has no view-controller transition API beyond push and
  modal and no interactive transitions at all. The reduced version: present the viewer modally with
  `UIModalTransitionStyleCrossDissolve` and close it with a nav-bar Done button plus a single-tap on
  the image. Zoom inside the viewer is fine — that is just a `UIScrollView` with `maximumZoomScale`.
- **A full-resolution photo at original dimensions.** A 4000×3000 JPEG decodes to ~48 MB. The viewer
  must decode with `kCGImageSourceThumbnailMaxPixelSize = 1136` via `CGImageSourceCreateThumbnail
  AtIndex`, never `UIImage imageWithContentsOfFile:`. So pinch-zoom bottoms out at screen resolution;
  you cannot zoom into fine detail of a large photo. That is a hard limit, not a choice.
- **Play-while-downloading video** (the streaming byte-range entry). `AVAssetResourceLoaderDelegate`
  exists on iOS 6, but the A5 decodes 720p H.264 with no headroom to spare and the resource-loader
  path adds a copy per chunk. Reduced version: streaming for **audio only** (MP3/M4A voice and music,
  where the bitrate is trivial), and for video fall back to download-then-play with the progress ring
  on the tile. Do not ship video streaming.
- **Client-side video transcode before upload** (file-generation protocol). `AVAssetExportSession`
  on a 4S runs slower than real time for anything above 640×480 and will be killed in the background.
  Reduced version: use the generation protocol for **photo downscaling only** (a `CGImageSource`
  resize, milliseconds), and upload video as captured.
- **The full `getStorageStatistics` per-chat breakdown as a live screen.** It walks every file in the
  cache directory; on a 4S with a few thousand files that is seconds of I/O. It cannot be called on
  the main thread and cannot be called on `viewWillAppear`. Reduced version: the Settings row shows
  `getStorageStatisticsFast` (already wrapped at `TGClient.m:1533`); the per-chat table is a separate
  push that shows a centred spinner with "Calculating…" in `systemFontOfSize:14` `#8B97A5`, calls the
  slow API once with a `chat_limit` of 32, and caches the result for the session.

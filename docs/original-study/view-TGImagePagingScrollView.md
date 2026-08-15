# TGImagePagingScrollView (original, 2013/2014)

Source of truth:
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGImagePagingScrollView.h` (72 lines)
and `…/TGImagePagingScrollView.mm` (517 lines). The class exists under exactly that name; nothing had to
be substituted. Its page type is `TGImageViewPage` (`TGImageViewPage.h` / `.m`, 1598 lines), and its
per-page zooming scroll view is `TGImageScrollView`.

## What it is for

It is the horizontal pager under the full-screen media viewer: one page per media item, paging enabled,
pages recycled through a queue, and the notion of "which item is on screen" published upward. It is *not*
a generic pager — it also owns the media lifecycle (video player recycling), the "hide the source bubble
image" handshake used by the open/close zoom animation, and the load-more trigger for infinite media
history.

Three screens instantiate it, all with the same geometry:

- `TGImageViewController.mm:149,168-176` — the media viewer proper.
- `TGImagePickerController.mm:1296-1299` — full-screen preview inside the picker.
- `TGImageSearchController.mm:1833-1836` — full-screen preview of web image search results.

## Geometry — the 40pt gap, and why the numbers look odd

`float pageGap = 40;` in all three call sites (`TGImageViewController.mm:149`,
`TGImagePickerController.mm:1296`, `TGImageSearchController.mm:1833`).

The scroll view is deliberately **wider than the screen and shifted left by half the gap**:

```
_pagesScrollView = [[TGImagePagingScrollView alloc] initWithFrame:
    CGRectMake(-pageGap / 2, 0, self.view.bounds.size.width + pageGap, self.view.bounds.size.height)];
```
(`TGImageViewController.mm:168`)

So with `pagingEnabled = true` (`TGImagePagingScrollView.mm:66`) the paging stride equals the scroll
view's own width, i.e. `screenWidth + 40`. Each page is then inset back to screen width:

```
page.frame = CGRectMake(page.pageIndex * bounds.size.width + _pageGap / 2, 0,
                        bounds.size.width - _pageGap, bounds.size.height);
```
(`TGImagePagingScrollView.mm:217`, again at `:323`, `:359`, `:450`)

Net effect: page content is exactly screen-width, with a 40pt black channel between neighbours that is
only ever visible mid-swipe. This is the whole reason for the `-20` origin: at rest, the 20pt half-gaps
sit off both edges of the screen, so the user sees an edge-to-edge photo.

`contentSize = (screenWidth + 40) * pageCount` (`:287`, `:362`); resting `contentOffset.x` for page *i* is
`i * (screenWidth + 40)` (see `resetOffsetForIndex:` at `:337`, where `+ _pageGap/2 - _pageGap/2` cancels —
kept in that written-out form in the original, presumably as a note to self).

No colours and no artwork belong to this class. It is transparent; the black comes from
`_backgroundView.backgroundColor = [UIColor blackColor]` on the controller (`TGImageViewController.mm:157`).

## Scroll view configuration (`commonInit`, `:60-76`)

| property | value | line | why it matters |
|---|---|---|---|
| `pagingEnabled` | true | :66 | stride = view width = screen+40 |
| `alwaysBounceHorizontal` | true | :67 | you get rubber-band even with a single item |
| `alwaysBounceVertical` | false | :68 | vertical is reserved for swipe-to-dismiss |
| `scrollsToTop` | false | :69 | status-bar tap must not hijack the gallery |
| both scroll indicators | false | :70-71 | |
| `delaysContentTouches` | false | :72 | video scrubber must grab the touch instantly |
| `_lastPageIndex` | -1 | :62 | sentinel: "no page yet" |
| `directionalLockEnabled` | true | set by the caller, `TGImageViewController.mm:172` | not set in `commonInit` |

`touchesShouldCancelInContentView:` (`:78-81`) returns false for `UISlider` **and** for any view whose
`tag == 0x6FC81BDB`. That magic tag is how the video scrubber container opts out of scroll cancellation:
once you have your finger on the scrubber, horizontal movement scrubs and never turns into a page swipe.

## Page recycling

`dequeueImageViewPage` (`:83-107`) pops from `_pageViewQueue`, else builds a fresh `TGImageViewPage` at
`self.bounds` and copies down the five configuration properties (`customCache`, `delegate`,
`saveToGallery`, `ignoreSaveToGalleryUid`, `groupIdForDownloadingItems`), calls `createScrollView`, and
assigns `watcherHandle`. Note that these are copied **only on creation** — changing `saveToGallery` after
pages exist does not retro-fit them.

`enqueueImageViewPage:` (`:117-122`) is the reuse hook and it does exactly one thing:
`[page loadItem:nil placeholder:nil willAnimateAppear:false]`, then parks the page. That call is what
cancels the in-flight image download and clears the image. The queue is unbounded — pages accumulate up
to the peak visible count (3) and are never trimmed.

## `layoutSubviews` — the actual windowing algorithm (`:377-475`)

Two different windows, and the difference is the interesting part:

1. **Keep/discard window**: `minX = contentOffset - width`, `maxX = contentOffset + 2*width` (`:387-388`).
   A page is enqueued when it is entirely left of `minX` or starts right of `maxX` (`:399-407`) — so the
   pager holds three pages: previous, current, next.
2. **Zoom-reset window**: `minResetX = contentOffset + 0.5`, `maxResetX = contentOffset + width - 0.5`
   (`:390-391`). Any page not intersecting the *visible rect* (with a half-point tolerance) gets
   `resetScrollView` (`:413-416`). So a page you zoomed into snaps back to fit **as soon as it leaves the
   screen**, while still being kept alive. Swipe away and back: the photo is fitted again, not still zoomed.
   The half-point slack exists so a page resting exactly at the boundary is not reset every frame.

Page index range is derived, not tracked: `startPage = (minX - gap/2)/width + 0.5`,
`endPage = (maxX - gap/2)/width` (`:426-427`), then clamped to `[0, pageCount-1]` (`:429-436`). The
`+ 0.5f` is a round-up on the leading edge so a barely-peeking page is not created twice.

Creation of a missing page (`:441-461`) sets `pageIndex`, frame, `itemId`, calls
`loadItem:placeholder:nil willAnimateAppear:false`, `resetScrollView`, adds it, and *immediately* applies
the current chrome state: `controlsAlphaUpdated:` and `updateControlsOffset:` (`:459-460`). Without those
two lines a newly created neighbour page would show its video controls at full alpha while the chrome is
hidden. Chrome alpha is pulled from the delegate every layout pass (`:439`,
`[delegate controlsAlpha]` → `_interfaceView.controlsAlpha`, `TGImageViewController.mm:860-863`).

Current page is `(contentOffset + width/2) / width`, clamped (`:463-467`), and assigned through the
setter so all the side effects below fire.

Guard against a degenerate size: if `bounds.size.width <= 1` the page range stays `0..0` (`:424`) —
so a zero-width layout pass does not blow up the arithmetic. Same guard in `setFrame:` (`:348`).

## `setCurrentPageIndex:force:` (`:129-178`) — four side effects

1. Notifies `pagingDelegate` `scrollViewCurrentPageChanged:imageItem:` (`:142`), which the controller turns
   into the "3 of 27 / author / date" caption (`TGImageViewController.mm:427-430`).
2. Fires two `hideImage` ActionStage requests: un-hide the previous item's bubble image, hide the new one
   (`:153-164`, keyed by `messageId` plus `imageInfo`). This is what keeps the chat bubble underneath
   blank so the open/close zoom animation appears to be moving the same photo.
3. Calls `resetMedia` on every visible page that is not current (`:168-174`) — leaving a video by swiping
   tears its player down.
4. Rebinds the interface view to the current page's action handle: `[_interfaceHandle requestAction:@"bindPage" …]`
   (`:176`). If no page object exists for the index, `pageForIndex:` returns nil and the bind is a no-op —
   the interface simply keeps the previous binding.

The `force:` variant exists because after a list reload the index may be numerically unchanged while the
underlying item is different (`TGImageViewController.mm:407-408`).

## `setPageList:` (`:180-291`) — identity-preserving reload

This is the most carefully written method in the file, and the reason is realistic data: media history
arrives in pages, and items can be inserted *before* the current one (`reverseOrder`) or deleted.

- Builds `itemId → newIndex` for the incoming list (`:187-196`), but only if pages are on screen.
- Records `offsetFromCurrentPage = page.frame.origin.x - contentOffset.x` for the current page (`:209`) —
  the sub-page scroll position under the user's finger.
- Every visible page whose `itemId` survives is **re-indexed and re-framed in place** (`:216-217`); pages
  whose item vanished are enqueued (`:224-227`).
- Sorts the survivors by index, then checks they form a contiguous run; if not, logs
  `***** Invalid page order` and dumps every page back into the queue (`:236-267`). Note the loop at
  `:255-266` iterates `_visiblePages` while mutating it with `i--`, which is correct here only because the
  intent is to empty it.
- Reapplies `hideImage` for the new current item (`:276-285`), recomputes `contentSize`, and restores
  `contentOffset = currentIndex*width + gap/2 - offsetFromCurrentPage` (`:287-288`).

Result the user sees: new items load, the photo under your finger does not move by a pixel.

Empty list: `contentSize` becomes zero-width and no page is created; the controller separately treats
`items.count == 0` as "close the viewer" (`TGImageViewController.mm:419-420`).

## Load-more (`:471-489`)

Inside `layoutSubviews`: if `_canLoadMore && !_loadingMore` and either `_reverseOrder && currentIndex <= 5`
or `!_reverseOrder && currentIndex >= pageCount - 5`, fire `loadMoreItems` — an ActionStage
`@"loadMoreItems"` request (`:486`). Five pages of runway, direction chosen by `reverseOrder`. The reply
arrives as `itemsChanged:canLoadMore:` (`:491-497`), which clears `_loadingMore` and funnels into
`setPageList:`.

## Video players (`:44-58`, `TGMediaPlayerRecycler`)

Pages hand their `MPMoviePlayerController` to `recycleMediaPlayer:` instead of destroying it inline; the
actual teardown (`removeFromSuperview` + `stop`) happens in `recyclePlayers`, which the controller calls
only on `scrollViewDidEndDecelerating:` and on drag-end-without-deceleration
(`TGImageViewController.mm:734-743`). Tearing down `MPMoviePlayerController` mid-scroll stutters on the
hardware of the era; this defers it to a moment when nothing is animating. `dealloc` also drains it (`:41`).

## Rotation and resize

`setFrame:` (`:341-375`) compares against `_validSize` rather than the current frame. On a real size
change it computes the current page from the **old** width, re-frames every page at the new width, resets
`contentSize`, and jumps `contentOffset` to `currentPage * newWidth` — note this one uses no `+ gap/2`
(`:363`), unlike `resetOffsetForIndex:`. A pure `origin.y` change (chrome sliding) does not re-layout; it
only pushes `updateControlsOffset:` into the pages (`:366-372`), which is how the per-page video controls
and progress bars track the panel offset (`TGImageViewPage.m:1188-1197`:
`controlsContainer.y = statusBarHeight + 44 + 6 - offsetY`, progress bars at
`height - 61 - offsetY` and `height - 17 - offsetY`, inset 8pt each side).

`willAnimateRotation` / `didAnimateRotation` (`:304-318`) just fan out to the pages.

## `setInitialPageState:` (`:320-333`)

The hand-off from the open animation. `TGImageViewController` builds a standalone `_initialPage` outside
the pager (`TGImageViewController.mm:187-196`) so the zoom-in animation can run before any list exists;
when the list arrives, that same view is adopted: `autoresizingMask = 0`, framed at its page index, added
to `_visiblePages`, chrome alpha and offset applied, `resetScrollView`, and `contentOffset` snapped to
`page.frame.origin.x - gap/2`. The page is never re-created, so the animation's final image is the
gallery's first page — no flicker.

## Per-page zoom, for context (`TGImageViewPage.m`)

Our port re-implements this part, so the original numbers matter:

- `resetScrollView` (`:1103-1119`) sets min=max=zoom=1, contentSize to the *image* size, then
  `adjustScrollView` recomputes and finally sets `zoomScale = adjustedZoomScale` and centres the content.
- `adjustScrollView` (`:1404-1445`): `minScale = MIN(w/iw, h/ih)` (fit), `maximumZoomScale = minScale * 2`
  for photos; for video, max is the *fill* scale, collapsed to min when they differ by less than 0.01.
- `adjustedZoomScale` is the "smart fit": if fitting leaves less than 60pt of empty space on the long axis
  (`TG_ZOOM_ADJUSTMENT_THRESHOLD_HORIZONTAL 60.0f`, `TGImageViewPage.m:25-26`), it snaps to fill instead,
  so near-screen-ratio photos go edge-to-edge rather than showing a 20pt black sliver.
- `TGImageScrollView.updateZoomScale` sets `scrollEnabled = zoomScale > adjustedZoomScale + eps`
  (`TGImageScrollView.m:68-71`): an un-zoomed page does not consume horizontal pans at all, so paging is
  never fought over. Double-tap is recognised on the page's own container, with single-tap required to
  fail (`TGImageViewPage.m:73-77`).

---

# Our port

Our equivalent is inlined into `TGMediaViewController.m`: the pager is a plain `UIScrollView`
`_pagingView` built in `-buildPagingView` (`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGMediaViewController.m:768-786`),
the page is `TGMediaPageView` (`:631-700`), windowing is `-updateVisiblePages` (`:1098-1143`), and layout
is `-layoutPagesPreservingIndex:` (`:1065-1088`). There is no separate class.

**What is right.** `TGMediaPageGap = 40.0f` (`:22`), the `-gap/2` origin and `width + gap` frame
(`:772-774`, `:1070-1071`), stride `pageWidth = bounds.width + 40` (`:1061-1063`), page frame
`index*pageWidth + gap/2` at screen width (`:1131-1132`), `contentSize` (`:1072`), and the scroll-view
flags — `pagingEnabled`, `alwaysBounceHorizontal`, `alwaysBounceVertical=NO`, both indicators off,
`scrollsToTop=NO`, `delaysContentTouches=NO` (`:775-781`) — all match the original one for one. The
current-index formula `(offset + width/2)/width` clamped (`:1367-1372`) matches `:463-467`. The ±1 keep
window (`:1101-1106`) matches the original's three-page window. Good work; leave it alone.

**Visible defects.**

1. **Zoom is never reset on an off-screen page.** Original resets any page outside the visible rect every
   layout pass (`TGImagePagingScrollView.mm:390-391,413-416`). Ours calls `resetZoom` only when a page is
   created (`TGMediaViewController.m:1133`); a neighbour stays in `_visiblePages`, so zoom into page 3,
   swipe to 4, swipe back — page 3 is still zoomed, and worse, while it is zoomed its own scroll view
   eats horizontal pans. Fix: in `scrollViewDidScroll:` / `updateVisiblePages`, call `resetZoom` on every
   visible page whose index != `_currentIndex`.
2. **Fixed zoom range 1.0…2.0 on an aspect-fit image view.** `TGMediaPageView` sets
   `minimumZoomScale = 1.0`, `maximumZoomScale = 2.0`, `contentSize = bounds`, and zooms a
   `UIViewContentModeScaleAspectFit` image view (`:653-658`, `:672-681`). The original scales the *image*,
   with min = fit, max = 2× fit, and the 60pt `adjustedZoomScale` snap-to-fill
   (`TGImageViewPage.m:1404-1445`, `:25-26`). Consequences a user sees: (a) a portrait photo on a 4S never
   goes edge-to-edge the way it did in 2013; (b) 2× of a letterboxed fit is much less magnification than
   2× of the original's fit-of-image, so text in a screenshot is unreadable; (c) panning at zoom walks
   over the empty letterbox area because the zoomed content includes the padding.
3. **Chrome does not hide when you start swiping.** Original: `pageWillBeginDragging` and
   `scrollViewDidScroll` both call `[_interfaceView setActive:false duration:0.3]`
   (`TGImageViewController.mm:745-757`). We have no `scrollViewWillBeginDragging:` at all, and our
   `scrollViewDidScroll:` (`TGMediaViewController.m:1359-1376`) only updates the index. Panels stay up
   across the swipe. Fix: hide chrome (`setChromeHidden:YES animated:YES`) on drag begin.
4. **No `touchesShouldCancelInContentView:` override.** Original excludes `UISlider` and tag `0x6FC81BDB`
   (`TGImagePagingScrollView.mm:78-81`). We have no in-page slider today, so nothing is broken *now* —
   but the moment a video scrubber lands in `TGMediaPageView`, dragging it will page the gallery. Worth a
   note next to the page class.
5. **Gestures live on the controller's view, not on the page.** `handleDoubleTap:`/`handleSingleTap:` are
   attached to `self.view` (`TGMediaViewController.m:1006-1015`) and resolve the page by
   `_visiblePages[@(_currentIndex)]` (`:1433`). Original attaches them per page
   (`TGImageViewPage.m:73-77`). Difference the user can hit: double-tapping in the 20pt gap area mid-swipe,
   or double-tapping while the neighbouring page is under the finger, zooms the *other* page.
6. **No identity-preserving reload and no load-more.** Our fullscreen viewer takes a fixed `_items` array
   at init (`TGMediaViewController.m:745`) and keys `_visiblePages` by integer index; there is no
   `itemsChanged:` equivalent, no `canLoadMore`, and no 5-page prefetch trigger
   (original `:471-497`, `:180-291`). If we ever grow the list while the viewer is open — especially with
   items prepended — every visible page will be pointing at the wrong item and the photo under the user's
   finger will jump. The original's `itemId → index` remap plus `offsetFromCurrentPage` restore
   (`:187-196`, `:209`, `:288`) is the pattern to copy.
7. **Cache is dropped with the page.** We evict `_imageCache[key]` when a page leaves the window
   (`:1119`), so scrolling back re-decodes/re-downloads. The original page keeps its `TGRemoteImageView`
   cache (`customCache` passed at `:95`) and re-fetch is a cache hit. On a 4S this is a visible re-blur on
   every back-swipe.
8. **`contentOffset` restore on layout uses only the index** (`:1074-1077`), where the original also
   preserves the sub-page offset. Minor: it only shows if layout runs mid-drag, which we guard against
   anyway (`:1075`).

Ambiguity worth flagging: the original's `setFrame:` jumps to `currentPage * width` with **no** `+ gap/2`
(`:363`) while `resetOffsetForIndex:` and `setPageList:` both land on `index * width + gap/2 - …`
(`:288`, `:337` — where the term cancels). Since a page's own frame starts at `index*width + gap/2`, the
`setFrame:` value is the consistent resting offset and the others agree; there is no inconsistency, but
the code reads as if there is. Do not "fix" one to match the other.

---

# What became of it

**twelve** (`/Users/alexanderhavrysh/Git/iOS/twelve/submodules/LegacyComponents/LegacyComponents/`) replaced
it with `TGModernGalleryView` + `TGModernGalleryScrollView`. The geometry is identical in spirit and the
total gap is unchanged: `#define TGModernGalleryItemPadding 20.0f` (`TGModernGalleryController.m:31`),
scroll view at `CGRectMake(-itemPadding, 0, width + itemPadding*2, height)` (`TGModernGalleryView.m:64`),
item frames `itemWidth*i + padding` wide `itemWidth - padding*2` (`TGModernGalleryController.m:1517,1541`).
So 20+20 replaced one 40, same visual channel. Two real changes: the scroll view drives layout from
`setBounds:` through a `scrollViewBoundsChanged:` delegate rather than from `layoutSubviews`
(`TGModernGalleryScrollView.m:39-59`) — that is what allowed transitions to animate bounds instead of
snapping — and `hitTest:` asks the delegate `scrollViewShouldScrollWithTouchAtPoint:` and toggles
`scrollEnabled` before the touch is delivered (`:25-37`). That is the generalised, declarative replacement
for the original's `touchesShouldCancelInContentView:` slider/magic-tag hack, forced by richer item types
(editable media, stickers, scrubbers) rather than by taste.

**Modern Telegram-iOS**: `GalleryPagerNode` (`submodules/GalleryUI/Sources/GalleryPagerNode.swift`), default
`pageGap: CGFloat = 20.0` (`GalleryControllerNode.swift:63`), scroll view at
`x: -pageGap, width: layout.width + pageGap*2`, items at `i*scrollWidth + pageGap` wide
`scrollWidth - pageGap*2` (`GalleryPagerNode.swift:420-424`). Thirteen years later the exact same
construction is still there. What changed:

- `pageGap` may be zero, and when it is, `alwaysBounceHorizontal` and `bounces` are switched off
  (`:166-167`) — a gapless mode our 2013 pager had no concept of.
- Reload became a proper transaction: `replaceItems(_:centralItemIndex:)` diffs into
  delete/insert/update sets (`:460-488`) instead of the original's `itemId`-map-plus-contiguity-check with
  its `***** Invalid page order` bail-out (`TGImagePagingScrollView.mm:236-267`). Same goal — keep the
  central item pinned — solved with a real diff. Forced by feature growth (editing, live updates), not taste.
- `centralItemIndex` is an optional with an `ignoreCentralItemIndexUpdate` guard (`:101-113`), replacing
  the original's `-1` sentinel and `force:` flag.
- The load-more trigger left the pager entirely; media history paging is a Signal upstream, so nothing
  corresponds to the `currentIndex >= count - 5` test at `:471`.
- `hasActiveEdgeAction` / tap-navigation on the left and right edges (`:218-224`) is new behaviour with no
  1.1 ancestor.

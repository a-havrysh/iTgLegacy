# TGRemoteImageView — original study

Source of truth: `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGRemoteImageView.{h,m}`
(Telegram for iOS v1.1, © Peter Iakovlev 2013 — header banner, `TGRemoteImageView.h:1-7`).
The class exists under the exact requested name; no substitution was necessary.

Throughout, `orig:` means `TelegraphKit/TelegraphKit/TGRemoteImageView.m` unless another path is given.
`ours:` means `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/…`.

---

## 1. What it is for

It is the single image-bearing leaf view of the whole 2013 app. Every avatar, every media-grid
thumbnail, every wallpaper swatch, every photo page is one of these. It is *not* a downloader: it is a
**UIImageView that knows how to name an image, ask ActionStage for it, and cross-fade it in when it
arrives** — and, crucially, how to give that up cleanly the instant its cell is recycled.

Three design decisions define it, and they are the ones worth carrying over:

1. **An image is identified by a string URL plus a named filter.** The pair is flattened into one cache
   key, `{filter:NAME}URL` (`orig:216`, `orig:264`, `orig:451`, `orig:464`), and into one ActionStage
   path, `/img/({filter:NAME}URL)` or `/img/(URL)` (`orig:387-389`). The same two lines of formatting
   appear in five places; that string *is* the identity of a loaded image across the memory cache, the
   disk cache, the download actor and the view.
2. **Geometry is baked into the bitmap, not applied by the layer.** A filter is a registered
   `UIImage *(^)(UIImage *)` block (`TGRemoteImageView.h:28`) that scales, rounds corners and composites
   an overlay *once*, at decode time, off the main thread. Nothing in the scrolling path ever sets
   `cornerRadius` or `masksToBounds`. On a 4S this is the difference between a smooth dialog list and a
   stuttering one.
3. **The placeholder is a real sibling view, not a value of `self.image`.** Fading means fading that
   sibling out over the already-installed real image, so the crossfade never touches the receiver's own
   `contents` and never disturbs subviews.

## 2. Class shape and public surface

Declared as `UIImageView <ASWatcher, TGReusableView>` (`TGRemoteImageView.h:33-39`). There is a
compile-time switch `TGRemoteImageUseContents` (`.h:16`, set `false`) that would have made it a bare
`UIView` driven through `layer.contents`; every assignment site is `#if`-doubled because of it
(`orig:165-169`, `234-238`, `296-300`, `329-333`, `359-363`, `378-382`, `425-429`, `547-551`). In the
shipped configuration all of those reduce to `self.image = …`. Treat the `layer.contents` half as dead
code; do not port it.

`TG_CACHE_INPLACE` (`.h:18`) is likewise `false`, which disables the "cache the image in the view's own
completion handler" branch (`orig:532-538`) — caching is the download actor's job instead.

Public state:

| Property | Declared | Meaning / default |
|---|---|---|
| `cache` / `useCache` | `.h:43-44` | per-view `TGCache` override; `useCache` defaults `true` (`orig:102`) and is passed through to the actor as the `useCache` option (`orig:391`). `nil` cache falls back to `+sharedCache` (`orig:262`). |
| `contentHints` | `.h:45` | bit mask, see §5 |
| `userProperties` | `.h:46` | opaque payload forwarded to the actor when non-nil (`orig:392-393`) |
| `fadeTransition` | `.h:48` | creates/destroys the placeholder sibling view (`orig:120-140`) |
| `fadeTransitionDuration` | `.h:49` | **0.14 s** default, set in `initWithFrame:` (`orig:101`) |
| `allowThumbnailCache` | `.h:50` | on a cache miss, try `[cache cachedThumbnail:]` as the placeholder (`orig:350-355`) |
| `manualParentView` | `.h:55` | for views drawn into a parent's `drawRect:` rather than composited; every image assignment additionally calls `[_manualParentView setNeedsDisplayInRect:self.frame]` (`orig:230`, `292`, `325`, `374`, `420`, `543`) |
| `placeholderOverlay` | `.h:56` | a recyclable view added **as a subview of the placeholder**, not of self (`orig:159`) |
| `currentUrl` / `currentFilter` | `.h:58-59` | last requested pair; cleared on cancel (`orig:439-440`) and on failure (`orig:579-580`) |
| `progressHandler` | `.h:61` | `void(^)(TGRemoteImageView *, float)` |
| `cancelTimeout` | `.h:63` | seconds the actor keeps running after the last watcher leaves; passed as the `cancelTimeout` option (`orig:391`) |

Methods that matter: `-loadImage:` (a plain local image, `orig:223`), the two
`-loadImage:filter:placeholder:[forceFade:]` variants (`orig:250`, `255`), `-loadPlaceholder:`
(`orig:398`), `-cancelLoading` (`orig:404`), and the class helpers `+imageFromCache:filter:cache:`
(`orig:443`) and `+preloadImage:…` (`orig:456`).

## 3. The filter registry — where all the design numbers actually live

`+registerImageProcessor:withName:` and `+registerImageUniversalProcessor:withBaseName:`
(`orig:50-58`) fill two `dispatch_once` dictionaries. Lookup (`orig:60-81`) first tries an exact name;
failing that, it splits on the first `:` and looks the prefix up in the universal table, wrapping it so
the full parameterised name reaches the block. So `scale:90x90` resolves to the `scale` universal
processor, which parses the `WxH` suffix character by character and bails to `nil` on any non-digit
(`TGTelegraph.mm:547-596`).

Every filter in the app is registered in one block in `TGTelegraph.mm:476-725`. The full table, since
these are the numbers the redesign depends on:

| Filter | Output size | Corner radius | Overlay | Line |
|---|---|---|---|---|
| `avatar56` | 56×56 | 5 | — | `TGTelegraph.mm:478` |
| `avatarAuthor` | 30×30 drawn at offset (2,2) into a 32×32 canvas | 5 | — | `:483` |
| `avatar40` | 40×40 | 4 | — | `:488` |
| `avatar27` | 27×27 | 0, `roundCorners=true` flag | — | `:493` |
| `avatar56_half` | 56×56 into a 27×56 canvas (left half only) | 0, rounded | — | `:498` |
| `profileAvatar` | 69×69 at offset (0.5,0) into 70×70 | 10 | `[TGInterfaceAssets profileAvatarOverlay]`, scaled | `:503` |
| `signupProfileAvatar` | 69×69 at (1,0.5) into 71×71 | 9 | `LoginProfilePhotoOverlay.png` | `:508` |
| `inactiveAvatar` | 180×180 at (3.5,3.0) into 187×187 | 8 | `LoginBigPhotoOverlay.png`, stretched from its centre | `:514` |
| `titleAvatar` | 35×35 | 4 | — | `:519` |
| `memberListAvatar` | 40×40 at (2,2) into 44×44 | 4 | `memberListAvatarOverlay` | `:524` |
| `conversationAvatar` | 37×37 at (0.5,0) into 38×38 | **19** (i.e. circular) | `conversationAvatarOverlay` | `:529` |
| `notificationAvatar` | 33×33 at (0.5,0) into 34×34 | 4 | `notificationAvatarOverlay` | `:534` |
| `inlineMessageAvatar` | 30×30 | 3 | — | `:539` |
| `conversationUserPhoto` | 149.5×149 at (0.5,0.5) into 150×150 | 8 | `conversationUserPhotoOverlay`, scaled | `:544` |
| `scale:WxH` | exact `WxH`, identity if already that size | — | — | `:547-596` |
| `mediaListImage` | short side 90, then `TGFitSize` into 200×200 | 0, rounded | — | `:598-618` |
| `mediaGridImage` | short side **75**, cropped to a 75×75 canvas | 0, rounded | — | `:620-642` |
| `mediaGridImageLarge` | short side 100, cropped to 100×100 | 0, rounded | — | `:644-668` |
| `downloadingOverlayImage` | short side 118, cropped to 118×118 | 8, `RoundCornersByOuterBounds` | — | `:670-692` |
| `maybeScale` | `TGFitSize(source, 568×568)` | — | — | `:696` |
| `attachmentImageOutgoing:…` | two sizes parsed from the name → `TGAttachmentImage` | bubble tail baked in | — | `:707-715` |
| `attachmentLocationIncoming` / `Outgoing` | 100×100, incoming/outgoing bubble shape | | | `:719`, `:724` |

Two structural lessons here. First, the *canvas* is often 1–2 px larger than the *image* and the image
is drawn at a sub-pixel offset — that is how the 1-px inner bevel of the 2013 avatar was produced, by
letting an overlay PNG ring sit in the margin. `conversationAvatar` at 37 inside 38 with radius 19 is
the circular chat-title avatar; `avatar56` at 56 with radius 5 and no overlay is the dialog-list one.
Second, the media-grid thumbnail is **crop-to-square, short-side-fit** (`:628-641`), not aspect-fit and
not stretched — the aspect ratio survives, the overflow is cut.

The filter name is part of the cache key, so two call sites asking for different sizes of the same
photo cost two cache entries and two decodes, by design.

## 4. Load path, exactly

`-loadImage:filter:placeholder:forceFade:` (`orig:255-396`):

1. `cancelLoading` first (`orig:257`) — always, even if the same URL is being re-requested.
2. Record `currentUrl` / `currentFilter` (`orig:259-260`).
3. Build `cacheUrl` and ask the memory cache. Disk is consulted synchronously **only** if the
   `LoadFromDiskSynchronously` hint is set (`orig:266`).
4. Fallback for that hint: if the filtered variant is not on disk, load the *raw* image from disk and
   run the processor inline on the calling thread (`orig:268-278`). This is the "I must have this pixel
   data before the next frame" path — used by transitions, not by lists.
5. **Cache hit.** Install the image. If `forceFade`, the placeholder is set to the supplied image,
   shown at alpha 1, and animated to 0 over `fadeTransitionDuration`, hiding on completion
   (`orig:303-318`). If not, the placeholder is snapped to hidden/alpha 0 with `removeAllAnimations`
   first (`orig:336-342`). Then `progressHandler(self, 1.0f)` (`orig:345-346`).
6. **Cache miss.** If `allowThumbnailCache`, a cached blur-thumbnail replaces the caller's placeholder
   (`orig:350-355`). If a placeholder view exists, `self.image` is cleared and the placeholder is shown
   at alpha 1 (`orig:357-368`); if not, the placeholder image is installed directly into `self.image`
   (`orig:369-384`). Then the actor path is built and requested (`orig:386-394`).

`-actorCompleted:` (`orig:516-593`) hops to the main queue, ignores results whose path no longer matches
`self.path` (`orig:520` — this is the whole reuse-safety mechanism), installs the image, and fades the
placeholder out, with an explicit zero-duration shortcut when `fadeTransitionDuration < FLT_EPSILON`
(`orig:557-561`). Note the deliberately commented-out `removeAllAnimations` at `orig:556`: a second
arrival mid-fade is allowed to keep the first fade running rather than restart it.

On failure (`resultCode != ASStatusSuccess`), the image is left as the placeholder and only
`currentUrl`/`currentFilter` are cleared (`orig:577-581`). **There is no error artwork and no retry.**
A permanently failing avatar just stays a placeholder forever. Progress is still reported as 1.0
(`orig:583-584`), i.e. the progress handler means "done", not "succeeded".

Progress arrives by two routes, `actorMessageReceived:` with type `"progress"` (`orig:485-498`) and
`actorReportedProgress:` (`orig:501-514`); both re-check `self.path` before firing.

## 5. Content hints

`TGRemoteImageContentHints` (`.h:20-24`): `LargeFile = 1`, `SaveToGallery = 2`,
`LoadFromDiskSynchronously = 4`. The view itself only acts on the last two — `SaveToGallery` fires a
side request to `/tg/checkImageStored/(hash)` both on a cache hit (`orig:282-285`) and on a completed
download (`orig:524-527`). `LargeFile` is passed through to the actor untouched (`orig:391`).

## 6. Reuse, recycling, and teardown

Two distinct entry points, both of which cancel and clear the image (`orig:162-187`):

- `-prepareForReuse` — UIKit's cell path. Cancel, `self.image = nil`. Note it does **not** touch the
  placeholder view, so a recycled cell shows the last placeholder until the next `loadImage:` sets one.
- `-prepareForRecycle:(TGViewRecycler *)` — the app's own view pool. Additionally detaches
  `placeholderOverlay` and hands it back to the recycler (`orig:171-176`).

`-cancelLoading` (`orig:404-441`) only does the expensive work when `self.path != nil`. Watcher removal
is dispatched onto the ActionStage queue rather than done inline (`orig:410-413`), so cancelling never
blocks the main thread; the actor's own `cancelTimeout` decides whether the in-flight download is
actually abandoned. `dealloc` resets the handle then cancels (`orig:107-111`).

`-addGestureRecognizer:` is overridden to flip `userInteractionEnabled` on (`orig:113-118`), because the
class is normally non-interactive and callers kept forgetting. There is no tap behaviour of its own.

`-tryFillCache:` (`orig:208-221`) writes `key → currentImage` into a caller-supplied dictionary, keyed
exactly as the cache would key it. It is how a controller snapshots the visible images before a
transition so `addTemporaryCachedImagesSource:` (`TGCache.h:40`) can keep them alive across it.

## 7. Cache budget it was tuned against

`TGCache` (`TelegraphKit/TelegraphKit/TGCache.m:117-134`) branches on `deviceMemorySize() > 300` MB.
The 4S has 512 MB, so it takes the upper branch: image memory limit **15 MB** with a 1 MB eviction
interval; thumbnail limit **1.6 MB**; data limit 1 MB; memory-warning baseline 1.5 MB; background
baseline 5.8 MB. Disk is **32 MB** with a 6 MB eviction interval (`:129-130`), shared by all devices.
Those are the numbers our cache should be sized against, not an arbitrary round figure.

## 8. Call-site behaviour worth copying

**Dialog list** (`TelegraphKit/TelegraphKit/TGDialogListCell.m`): the avatar view is created at
`CGRectMake(8, 8, 56, 56)` (`:406`) and `fadeTransition` is enabled **only when `cpuCoreCount() > 1`**
(`:404`) — the 4S is dual-core A5, so on our target the fade is on. Duration is switched per update:
`keepState ? 0.3 : 0.14` (`:1106`). The important trick is at `:1112` — when animating a state change,
the placeholder passed in is **the view's own `currentImage`**, so what crossfades is old-avatar →
new-avatar rather than blank → avatar. When there is no avatar at all, it loads the synthetic URL
`dialogListPlaceholder:<conversationId>` with a `nil` filter (`:1124`), which the download actor
resolves locally into the generated colour-plate avatar (`TGImageDownloadActor.m:337-347`) and then
caches like any other image. Placeholder generation goes through the same pipeline as real photos;
there is no separate placeholder code path in the view.

**Contact cell** (`Telegraph/Telegraph/TGContactCell.m`): avatar at `(5, 5, 40, 40)` (`:326`),
`fadeTransition = true` unconditionally (`:327`), filter `avatar40` (`:522`), and the same
current-image-as-placeholder trick at `:521-522`. Note the duration ternary here is
`animateState ? 0.14 : 0.3` (`:516`) — the *opposite* sense to the dialog cell's `:1106`. One of the two
is a slip in the original; I cannot tell which, so treat 0.14 as the normal value and 0.3 as the
"slower, deliberate" one and do not read intent into the inconsistency.

The actor also understands `asset-original:` / `asset-thumbnail:` (ALAsset library,
`TGImageDownloadActor.m:274-303`), `local://wallpaper…` (bundle resource,
`:308-333`), and a `download:` prefix that is stripped before matching (`:243-245`). Filters whose name
ends in `+bake` cause the *filtered* result rather than the raw image to be written to disk
(`:268`, `:346-352`).

An original bug, for the record: `+preloadImage:` swaps two option keys —
`allowThumbnailCache` is passed under the key `@"forceMemoryCache"` and the constant `TG_CACHE_INPLACE`
under `@"allowThumbnailCache"` (`orig:474`). Do not faithfully reproduce this.

---

## 9. Our port, judged

`ours: TGRemoteImageView.h/.m` (187 lines vs the original's 595). It keeps the name and the two fade
properties and drops essentially everything else. It is used in exactly **one** place —
`TGMediaViewController.m:370` (`TGMediaTileView` subclass) and `:574` — while every avatar in the app is
loaded by hand-rolled code in each screen (`TGChatListViewController.m:2825-2845`,
`TGProfileViewController.m:799-812`, and similar in the other controllers). The class that was the
app's universal image leaf has become a media-grid detail.

### Defects, most serious first

1. **Three declared methods have no implementation.** `-loadImage:filter:placeholder:`,
   `-loadImage:filter:placeholder:forceFade:` (`ours:TGRemoteImageView.h:15-16`) and `-tryFillCache:`
   (`:13`) are in the `@interface` and absent from the `@implementation`. Any caller gets an
   unrecognised-selector crash. Either implement them or delete them from the header. `currentUrl`
   (`:10`) is likewise declared and never assigned by the implementation — it always reads `nil`, so
   the original's "am I already showing this URL?" guard (`TGDialogListCell.m:1117`,
   `TGContactCell.m:517`) cannot be written against it.

2. **No filter registry, therefore no baked corners.** The original never rounds a corner at composite
   time; we do. `ours:TGChatListViewController.m:274-275` sets `layer.cornerRadius = 5.0f` with
   `clipsToBounds = YES` on a 56×56 avatar in a scrolling cell. The original produced that exact 56/5
   geometry inside the `avatar56` processor (`TGTelegraph.mm:478`) so the GPU sees a plain opaque
   bitmap. On a 4S, per-cell offscreen rounding in a fast scroll is the single most expensive thing on
   this screen. Fix: round and composite in `TGAvatarThumbnail` (`ours:TGChatListViewController.m:2758`,
   which currently only scales) and drop the layer rounding. Our radius *values* are right —
   `TGAvatarCornerRadius` in `ours:TGIcons.m:18-24` returns 9/5/4/3 for 70/56/40/30, matching
   `TGTelegraph.mm:503/478/488/539` — they are simply applied in the wrong place.

3. **No 1-px overlay ring.** Every original avatar filter above 40 pt composites an overlay PNG into a
   canvas 1–2 px larger than the image (`TGTelegraph.mm:503`, `:508`, `:524`, `:529`, `:534`, `:544`).
   We have no equivalent anywhere. This is a visible flatness difference against the 2013 reference,
   not a performance point.

4. **The crossfade fades the wrong thing.** `ours:TGRemoteImageView.m:87-89` uses
   `transitionWithView:self options:CrossDissolve`, which snapshots the receiver *and all its
   subviews*. `TGMediaTileView` has four of them — badge bar, badge label, play glyph, shadow
   (`ours:TGMediaViewController.m:372-375`) — so every thumbnail arrival re-dissolves the video badge
   and the gradient shadow along with the photo. The original avoided this precisely by fading a
   dedicated `_placeholderView` sibling out over the already-installed image (`orig:126-130`,
   `orig:564-572`) and never animating the receiver. Fix: adopt the sibling-placeholder structure.

5. **No "previous image as placeholder" behaviour.** The original's most visible avatar polish is
   old→new crossfade on state change (`TGDialogListCell.m:1112`, `TGContactCell.m:521-522`). Our chat
   list calls `[me.tableView reloadData]` on every single avatar arrival
   (`ours:TGChatListViewController.m:2841`), which hard-swaps the image with no transition at all and
   reloads the entire table N times during first paint. Both halves of that line are wrong.

6. **Cache budget is roughly a third of the original's, and volatile.** Ours is one `NSCache` with
   `totalCostLimit = 6 MB` (`ours:TGRemoteImageView.m:16`) against the original's 15 MB image cache plus
   a separate 1.6 MB thumbnail cache on a 512 MB device (`TGCache.m:117`, `:123`). Worse, we
   `removeAllObjects` on `UIApplicationDidEnterBackgroundNotification` (`ours:TGRemoteImageView.m:23-28`)
   — the original *shrinks* to a background baseline of 5.8 MB (`TGCache.m:134`) and additionally has
   `storeMemoryCache` / `restoreMemoryCache` (`TGCache.h:57-58`) so a resume is not a cold start. Ours
   makes every app resume repaint from disk.

7. **Disk cache stores PNG.** `ours:TGRemoteImageView.m:163` re-encodes each thumbnail with
   `UIImagePNGRepresentation` into `Caches/RemoteImageCache`, with no size limit and no eviction. The
   original's disk cache is JPEG-oriented, capped at 32 MB and evicted in 6 MB steps
   (`TGCache.m:129-130`). A media-heavy account will grow our cache without bound.

8. **`cancelLoading` is a one-way latch.** `ours:TGRemoteImageView.m:183-185` sets `cancelled = true`
   and only `loadWithFileId:` clears it (`:98`). After `-loadPlaceholder:` (which cancels, `:176`) the
   view is inert until a full load is requested again. The original's cancel is idempotent and leaves
   the view immediately reusable (`orig:404-441`).

9. **No progress reporting and no content hints.** `progressHandler` (`.h:61`) has no analogue, so we
   cannot draw a download ring over a media tile the way the original could; `contentHints` (`.h:45`),
   including the synchronous-disk-load path that transitions depend on (`orig:266-278`), is absent.

### What is right

The reuse guard is sound and is the part that matters most: `deliver` re-checks `fileId` *and*
`currentCacheKey` before touching the view (`ours:TGRemoteImageView.m:126-127`), which is the same
contract as the original's `[path isEqualToString:self.path]` check (`orig:520`). The 0.14 s default
duration (`ours:56`... `:46`) matches `orig:101` exactly. The memory-cache-hit path assigns without a
fade (`ours:110-113`), matching the original's non-`forceFade` hit branch (`orig:336-342`). Decoding on
a background queue with an `@autoreleasepool` (`ours:131-144`) is right for the 4S. And
`TGDecodeSquareThumbnail` (`ours:TGImageDecode.m:23-41`) implements exactly the crop-to-square,
short-side-fit rule of `mediaGridImage` (`TGTelegraph.mm:628-641`) — that one is a faithful port.

---

## 10. What became of it

**twelve** (`twelve/submodules/LegacyComponents/LegacyComponents/TGRemoteImageView.{h,m}`) keeps the
class almost verbatim — 517 lines against 595, the difference being the removal of the dead
`TGRemoteImageUseContents` branches and of `manualParentView`. Two real changes:

- A fourth content hint, `TGRemoteImageContentHintBlurRemote = 8`
  (`twelve/…/TGRemoteImageView.h:11-12`), forwarded to the actor as a `blurIfRemote` option
  (`twelve/…/TGRemoteImageView.m:340-341`) and threaded through `+preloadImage:` as an explicit
  parameter (`.h:68`). This is feature-forced: spoiler/sensitive media needs a blurred variant, and the
  filter-name mechanism could not express "blur only if this came off the network", because the filter
  name has to be a pure function of the desired output.
- It drops `TGReusableView` conformance and declares `-prepareForRecycle` / `-prepareForReuse` directly
  (`.h:70-71`), decoupling it from the recycler protocol.

The view also gained a subclass, `TGModernRemoteImageView : TGRemoteImageView <TGModernView>`
(`twelve/Telegraph/TGModernRemoteImageView.h:12`), so the same loading machinery could sit inside the
newer flat-view-hierarchy layout system. The interesting point for us: the 2013 loading model survived
a full UI-architecture change intact. Nothing about `/img/(…)` paths or baked filters had to be
rethought.

**Telegram-iOS** replaced it with `TransformImageNode`
(`Telegram-iOS/submodules/Display/Source/TransformImageNode.swift:19`). The concept split cleanly in two:

- The named-filter registry became a *signal* — `setSignal(_:)` takes a stream of
  `(TransformImageArguments) -> DrawingContext?`. The filter is no longer a globally registered string
  key but a closure passed with the request, which removes the parsing hacks the 2013 code needed for
  parameterised filters (`TGTelegraph.mm:552-587` character-by-character `WxH` parsing, and the
  `extractTwoSizes` for `attachmentImageOutgoing:`). This was forced: once bubble geometry became
  data-dependent, encoding it in a filter *name* stopped scaling.
- The placeholder-sibling crossfade became an explicit option set,
  `TransformImageNodeContentAnimations` with `.firstUpdate` / `.subsequentUpdates`
  (`TransformImageNode.swift:15-16`). First update fades alpha 0→1 over **0.15 s**
  (`:104`); a subsequent update snapshots the old contents into a temp layer and fades *that* out over
  0.15 s (`:137`) — which is precisely the 2013 placeholder-sibling trick, generalised, and confirms
  that the original's structure was the right one. The duration moved 0.14 → 0.15, a rounding, not a
  change of taste.

What was abandoned: `manualParentView` (no longer any manual `drawRect:` compositing),
`contentHints`, and the idea that the view owns its cancellation — cancellation is now a `MetaDisposable`
(`TransformImageNode.swift:21`, `:50`). What survived thirteen years: identity-by-key, baked geometry
off the main thread, placeholder-under-image, and re-check-before-apply on reuse. Those four are the
ones to hold onto.

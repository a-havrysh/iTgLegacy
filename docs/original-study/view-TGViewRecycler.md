# TGViewRecycler (2013 original) — study

Sources, all read-only:

- Original: `/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGViewRecycler.{h,m}` and `TGReusableView.{h,m}`
- Ours: `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGViewRecycler.{h,m}`, `TGReusableView.{h,m}`
- Modern: `/Users/alexanderhavrysh/Git/iOS/Telegram-iOS/submodules/Display/Source/ListView.swift`
- Fork: `/Users/alexanderhavrysh/Git/iOS/twelve`

The class exists under exactly this name in the original. It lives in TelegraphKit only; the app
target `Telegraph/Telegraph` never touches the recycler directly — its single reference to the family
is `Telegraph/TGWallpaperPreviewController.m:237`, which allocates a bare `TGReusableView` as a
10×10 placeholder overlay and never pools it.

This is not a visual component: it has no metrics, no colours and no artwork. It is the object-pool
substrate under every hand-rolled scrolling surface in the 2013 client, so the interesting content is
its contract, its lifecycle callbacks, and the exact points where the original chose *not* to be
clever.

## 1. What it is for

`UITableView` gives you cell reuse only if you accept `UITableViewCell` and one view per row. The 2013
conversation is neither: a message row is a hand-laid-out `TGConversationMessageItemView` built from a
variable bag of sub-views (labels, local images, remote images, spinners, buttons), and the whole list
was for a time driven by a custom scroll view, `TGListView`, rather than by `UITableView`. Reuse
therefore had to happen at *sub-view* granularity, keyed by a short string, independent of any list
class. `TGViewRecycler` is that: an identifier→stack-of-views map with two lifecycle hooks.

## 2. Public surface

`TGViewRecycler.h:13-19` — four methods, no properties, no delegate:

```objc
- (UIView<TGReusableView> *)dequeueReusableViewWithIdentifier:(NSString *)reuseIdentifier;
- (void)recycleView:(UIView<TGReusableView> *)view;
- (int)recycledCount:(NSString *)identifier;
- (void)removeAllViews;
```

`TGReusableView.h:13-20` defines the protocol every pooled view must satisfy:

```objc
- (NSString *)reuseIdentifier;
- (void)prepareForReuse;
- (void)prepareForRecycle:(TGViewRecycler *)recycler;
```

and `TGReusableView.h:22-25` a concrete `UIView` subclass with a settable `reuseIdentifier` and empty
hooks (`TGReusableView.m:7-13`) for views that need nothing.

Note the asymmetry, which is the whole design: `prepareForRecycle:` receives the recycler, so a view
being retired can hand *its own* children back to the pool. `prepareForReuse` does not, so it can only
clean itself. See §5.

## 3. Behaviour, line by line

**Construction** (`TGViewRecycler.m:11-24`). Registers for `UIApplicationDidReceiveMemoryWarningNotification`
— but does so inside a `dispatch_async` to the main queue (line 16-19), because recyclers were being
constructed off the main thread and `NSNotificationCenter` registration was not considered safe there.
The observer is torn down in `dealloc` (line 28). Backing store is a plain `NSMutableDictionary` of
`NSMutableArray`s (line 21).

**Memory warning** (`TGViewRecycler.m:31-34`). Drops the entire pool. Nothing is retained by the
recycler after that; live on-screen views are unaffected because they are retained by their superviews.

**Dequeue** (`TGViewRecycler.m:36-49`). Look up the array; if absent return `nil`. Otherwise take
`lastObject` — LIFO, so the most recently retired view is handed back first and stays warm in cache.
`prepareForReuse` is called *by the recycler*, before the caller has set any content (line 46). If the
array exists but is empty, `lastObject` is `nil` and the method returns `nil` having done nothing; the
empty array is left in the dictionary forever. Note also that a `nil` identifier is not guarded: it
would go into `objectForKey:nil` and throw.

**Recycle** (`TGViewRecycler.m:51-73`). Asks the view for its identifier; if `nil`, logs
`"Warning: reuse identifier not specified"` and substitutes `NSStringFromClass([view class])`
(lines 55-59) — so an un-tagged view is still pooled, just under a class-name bucket. Then calls
`prepareForRecycle:self` (line 61). Lines 63-64 are dead code: the `reuseIdentifier == nil` early
return can never fire because line 58 already replaced it. The array is created lazily and the view
appended (lines 66-72).

Three things the original deliberately does *not* do here, all of which are load-bearing for how
callers are written:

- **No cap.** The pool grows without bound; the only shrink paths are a memory warning and
  `removeAllViews`. On a 4S this is a bet that pool size is bounded by working set, and it is: every
  caller recycles roughly as many views as it dequeues.
- **No `removeFromSuperview`.** Every caller must detach the view itself. `TGListView.mm:190-192` and
  `:213-215` remove first then recycle; `TGConversationMessageItemView.mm:538-541` recycles first then
  removes. Both orders occur in the original, so the recycler cannot assume either.
- **No duplicate check.** Recycling the same view twice puts it in the pool twice, and two callers will
  then be handed the same instance. Correctness rests entirely on callers nilling their pointers, which
  they do — see `TGConversationMessageItemView.mm:543-553`, which nils `_uploadProgressContainer` and
  its three sub-references immediately after recycling.

**recycledCount:** (`:75-79`) returns the bucket size (`0` via `nil` array's `count`). Used nowhere in
the shipped code; it is a debugging affordance.

**removeAllViews** (`:81-84`) empties the dictionary.

## 4. Ownership: one shared recycler for the whole conversation

`TGConversationController.mm:77` declares `static TGViewRecycler *sharedViewRecycler`, and
`:942-947` creates it inside a `dispatch_once` during `loadView`, assigning it to the instance's
`_viewRecycler` (`:425` is the property). The consequence matters: the pool **survives leaving a chat**.
Open chat A, scroll, back out, open chat B — B's first screen of rows is furnished from A's retired
labels and image views, so the second chat you open in a session is visibly cheaper to draw than the
first. Any port that gives each conversation controller its own recycler loses that, and the loss shows
up exactly where the 4S can least afford it: the first frame after a push.

`TGListView` is the other owner and it is *not* shared: `TGListView.mm:71` allocates a private recycler
per list, exposed through `dequeueListItemViewWithIdentifier:` (`:119-122`), which is the
`UITableView`-shaped façade over it. Its pool is fed from two places, `discardVisibleItems`
(`:183-192`) on `reloadData`, and the cull loop in `updateVisibleItems` (`:207-215`).

That cull loop also defines the reuse window: `TGListView.mm:194-196` computes
`startOffset = max(0, contentOffset.y - height/2)` and `endOffset = min(contentSize.height, startOffset + height + height/2)`,
i.e. **half a screen of slack above and below the viewport**. A row is only recycled once it is more
than half a screen out of view, which is what keeps a small flick from thrashing the pool.

## 5. The identifier vocabulary

Reuse identifiers in the original are terse constants declared as function-local `static NSString *`,
one per layout item type, in `TGLayoutModel.m -inflateLayoutToView:viewRecycler:actionTarget:`
(`:37-210`):

| id | class | site |
|---|---|---|
| `@"RL"` | `TGReusableLabel` (rich/attributed, CoreText) | `TGLayoutModel.m:49-50` |
| `@"LIV"` | `TGImageView` (local image) | `TGLayoutModel.m:81-82`, reused for overlays at `:118-120` |
| `@"RIV"` | `TGRemoteImageView` | `TGLayoutModel.m:101-102` |
| `@"ACTV"` | `TGReusableActivityIndicatorView` | `TGLayoutModel.m:134-135` |
| `@"SLI"` | `TGSimpleReusableLabel` (plain `UILabel`) | `TGLayoutModel.m:158-159` |
| `@"LBI"` | `TGReusableButton` | `TGLayoutModel.m:182-183` |
| `@"MAB"` | `TGMediaActionButton` | `TGConversationMessageItemView.mm:2723`, `:2737` |
| `@"ImageView"` | `TGImageView` default when constructed directly | `TGImageView.m:12` |
| `@"TGReusableButton"` | `TGReusableButton` fallback getter | `TGReusableButton.m:7-13` |

Two of those deserve comment. `TGImageView.m:12` sets `_reuseIdentifier = @"ImageView"` in
`initWithFrame:`, but `TGLayoutModel.m:86` overwrites it with `@"LIV"` — so a layout-inflated image view
and a directly-constructed one land in *different buckets and never mix*. `TGReusableButton.m:7-13`
overrides the getter to return the class name when unset, so a button always pools even if the caller
forgot.

The inflate path is also where you see the required post-dequeue discipline: a dequeued view is
explicitly un-hidden and re-alpha'd every time (`TGLayoutModel.m:71`, `:87-88`, `:108-109`, `:164-165`,
`:190-191`) because nothing in the pool guarantees those were reset. And for the button,
`TGLayoutModel.m:203` does `removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents`
before re-adding the action — a pooled control carries stale targets otherwise.

## 6. The per-class hooks, and what each actually clears

This is the real specification of the component, because the pool itself is trivial and all the
correctness lives here.

| class | `prepareForReuse` | `prepareForRecycle:` | cite |
|---|---|---|---|
| `TGReusableView` | empty | empty | `TGReusableView.m:7-13` |
| `TGListItemView` | `setNeedsLayout` | empty | `TGListItemView.m:28-36` |
| `TGImageView` | `image = nil` | `image = nil` | `TGImageView.m:17-25` |
| `TGRemoteImageView` | `cancelLoading`; clear contents | `cancelLoading`; clear contents; **detach and recycle `placeholderOverlay`** | `TGRemoteImageView.m:162-186` |
| `TGReusableLabel` | empty | `_precalculatedLayout = nil` | `TGReusableLabel.mm:143-150` |
| `TGSimpleReusableLabel` | empty | empty | `TGSimpleReusableLabel.m:7-13` |
| `TGReusableActivityIndicatorView` | empty | `stopAnimating` if animating | `TGReusableActivityIndicatorView.m:5-13` |
| `TGReusableButton` | empty | empty | `TGReusableButton.m:15-21` |
| `TGLabel` | empty | empty | `TGLabel.m:31-39` |

Read that table as a rule: **`prepareForRecycle:` is where anything expensive or ongoing is stopped**
(network load, spinner animation, a CoreText layout object), **`prepareForReuse` is a cheap belt-and-braces
reset**, and the majority of classes leave one or both empty because the inflate path overwrites every
property anyway.

`TGRemoteImageView.m:162-177` is the only recursive user of the recycler and the reason the protocol
passes it in at all: on retirement it removes its `placeholderOverlay` (itself a
`UIView<TGReusableView>` — either a `TGImageView` or a `TGReusableActivityIndicatorView`, per
`TGLayoutModel.m:118-146`) and hands it back to the same pool, then nils the reference. Without this,
every message with a progress spinner would leak a spinner per scroll pass. Note `setPlaceholderOverlay:`
(`:150-160`) only removes the previous overlay from its superview, it does **not** recycle it — the
recycle happens exclusively on the retirement path.

The spinner is also the clearest state case: `TGLayoutModel.m:145` calls `startAnimating` on dequeue and
`TGReusableActivityIndicatorView.m:9-13` calls `stopAnimating` on recycle, so an off-screen pooled
spinner burns no CPU. That pairing is easy to break and invisible until you profile.

## 7. Edge cases the original accepts

- **`nil` identifier on dequeue** — unguarded, `objectForKey:nil` raises. Callers always pass literals.
- **`nil` view on recycle** — `[view reuseIdentifier]` on `nil` yields `nil`, the warning is logged, and
  `NSStringFromClass(Nil)` is `nil`, so the substituted identifier is *still* `nil` and
  `setObject:forKey:nil` raises. Nothing calls it with `nil`.
- **View still in a superview when recycled** — permitted; it stays in the hierarchy, retained twice,
  and will be handed out again while still parented. All call sites detach.
- **Pool never shrinks except on memory warning** — accepted; no background-entry purge.
- **Not thread-safe** — no locking anywhere; all use is main-thread.

## 8. Our port, judged

`src/TGViewRecycler.h` is byte-for-byte the original's interface (four methods, same signatures), and
`src/TGReusableView.h` matches `TGReusableView.h:13-25` exactly. Good.

`src/TGViewRecycler.m` deviates deliberately in five places. Four are improvements I would keep:

1. `:38-39` guards `nil` identifier on dequeue.
2. `:58-59` guards `nil` view on recycle.
3. `:50-51` deletes the bucket when it empties (original leaks empty arrays).
4. `:74-75` `indexOfObjectIdenticalTo:` rejects a double-recycle — closes the original's worst
   foot-gun.
5. `:21-22` also purges on `UIApplicationDidEnterBackgroundNotification`. Sensible on a 4S; the
   original only purged on memory warning (`TGViewRecycler.m:18`).

`:67-68` moves `removeFromSuperview` inside `recycleView:`. Harmless given both original orderings, but
it means our callers can no longer rely on the view still being parented inside `prepareForRecycle:`.
Nothing in our tree does, so it is fine — just do not "fix" a future caller by re-adding it outside.

### Defects

**D1 — pool caps are set below the working set and will cause visible allocation stalls.**
`src/TGViewRecycler.m:3-4` sets `TGViewRecyclerMaxPoolSize = 12` per identifier and
`TGViewRecyclerMaxTotalPoolSize = 32` overall, enforced at `:77-81`. The original has no cap
(`TGViewRecycler.m:66-72`). The sticker grid in `src/TGStickerPanelView.m:1067` pools every visible tile
under the single identifier `@"stickerTile"`; a grid screenful is on the order of twenty tiles, so
jumping between sticker sections retires ~20 tiles, keeps 12, drops the rest, and immediately allocates
fresh `TGStickerTile`s for the difference — precisely the allocation churn the recycler exists to
prevent, on the device least able to absorb it. Change: raise `TGViewRecyclerMaxPoolSize` to at least
one-and-a-half screenfuls of the largest grid (32 is a safe number) and `TGViewRecyclerMaxTotalPoolSize`
to ~96, or drop the caps entirely and rely on the two purge notifications we already observe.

**D2 — the recycler is per-view everywhere; the conversation's shared pool is gone.**
The original's conversation recycler is a `dispatch_once` process singleton
(`TGConversationController.mm:77`, `:942-947`) shared across every chat opened in the session. Ours
allocates a fresh one per surface: `src/TGStickerPanelView.m:154`, and `src/TGMediaViewController.m:482`
holds a `weak` one per grid cell. Nothing in our tree reproduces the cross-chat warm pool. If the
conversation screen ever adopts the recycler, make it a shared static, not an ivar, and match
`TGConversationController.mm:942`.

**D3 — `TGRemoteImageView` has no `placeholderOverlay`, so the recursive-recycle contract is
unexercised.** The original's `prepareForRecycle:` is the only place the `recycler` argument is used
(`TGRemoteImageView.m:162-177`); ours ignores it (`src/TGRemoteImageView.m:58`, `__unused`). That is
consistent with our `TGRemoteImageView.h`, which has no `placeholderOverlay` property at all — so it is
a missing feature, not a broken port. Flagging it because the moment anyone adds a spinner overlay to a
pooled remote image, they must also add the `[recycler recycleView:_placeholderOverlay]; _placeholderOverlay = nil;`
pair, or spinners will accumulate one per scroll pass.

**D4 — `src/TGRemoteImageView.m:50-61` makes `prepareForReuse` and `prepareForRecycle:` identical.**
Both `cancelLoading`, nil the ids, and set `image = self.placeholderImage`. Setting the placeholder
image on the *recycle* side is wasteful: it retains an image on a view that is about to sit idle in the
pool, and it will be overwritten on dequeue anyway. The original's recycle path clears to nothing
(`TGRemoteImageView.m:165-169`) and lets the caller supply the placeholder. Change the recycle side to
`self.image = nil`.

**D5 — no animating-work stop hook in our pooled classes.** The original pairs
`startAnimating` on dequeue with `stopAnimating` on recycle (`TGLayoutModel.m:145` /
`TGReusableActivityIndicatorView.m:9-13`). We have no `TGReusableActivityIndicatorView` equivalent. Not
a bug today; it is the rule to follow if a pooled view ever gains an animation or a timer.

Everything else in our pooled-view implementations is faithful in spirit: `src/TGStickerPanelView.m:84-98`
correctly splits cheap reset (`prepareForReuse`) from teardown of targets and gesture recognizers
(`prepareForRecycle:`), and `src/TGStickerPanelView.m:1068-1077` correctly re-attaches them after every
dequeue — the same discipline as `TGLayoutModel.m:203-204`. `src/TGMediaViewController.m:511-536`
mirrors the `TGListView` pattern faithfully, including a sane no-recycler fallback.

## 9. What became of it

**Modern client — abandoned entirely, and deliberately.** `Telegram-iOS/submodules/Display/Source/ListView.swift`
contains no occurrence of "reuse" or "recycle" anywhere in the file, and `nodeForItem` (line 1766)
either re-lays-out the *same* `ListViewItemNode` that already represented that item (`previousNode`,
line 1767) or constructs a new one. There is no identifier and no pool. The reason is structural, not
aesthetic: an ASDisplayKit node carries asynchronously-computed layout and can be laid out off the main
thread, so the expensive part of a row is no longer "allocate views" but "measure text" — and measuring
is cached per item, not per view. Identity-preserving updates also give them free animated transitions
between two states of the same row, which a pool cannot express. This is the one place where our port
should *not* follow the modern client: on a 4S, allocation and `-layoutSubviews` genuinely are the cost,
and pooling is the right answer.

**twelve — gone, replaced by a same-named callback on a different hierarchy.** `grep -rn TGViewRecycler`
across `twelve/` returns nothing. What survives is the *name of the hook*, not the pool:
`twelve/Telegraph/TGModernGalleryMessageImageItemView.m:42`, `TGSecretPeerMediaGalleryVideoItemView.m:86`,
`TGExternalGifSearchResultGalleryItemView.m:90`, `TGWebSearchResultsGalleryGifItemView.m:105` and
`TGVTAcceleratedVideoView.m:578` all implement `- (void)prepareForRecycle` — **no recycler argument**.
That dropped argument is the whole story: by the "modern" (TGModern*) generation the gallery managed its
own small fixed set of item views and no longer needed a retiring view to hand children back to a shared
pool, so the hook degenerated into a plain "you are going off-screen, stop what you are doing" callback.
`TGModernRemoteImageView.m:22` and `TGModernLetteredAvatarView.m:30` call it straight out of `init` as a
reset primitive, which is exactly what it had become. This is a change forced by a new architecture
(async layout + fixed-size gallery windows), not a change of taste.

## 10. Open question

Whether the conversation screen in our port should adopt the recycler at all, or keep `UITableView`'s
own cell reuse. The original used both — `UITableView` for the dialog list and the recycler for message
sub-views — and the two are complementary rather than alternatives. We have not made that call yet, and
D2 only becomes urgent once we do.

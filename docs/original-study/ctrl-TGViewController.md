# TGViewController — the original base view controller

Source of truth: `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGViewController.h`
(141 lines) and `TGViewController.mm` (928 lines). There is also a stub
`TGViewControllerAppearance.h` that declares an empty `TGViewControllerAppearance`
protocol and is dead weight (`TGViewControllerAppearance.h:11-13`).

36 classes across `Telegraph/Telegraph` and `TelegraphKit/TelegraphKit` inherit from it
(`grep -rl ": TGViewController"`), so essentially every screen in the 2013 app is one of
these. It is not a visual component; it is the layout contract that every screen shares.
Getting it wrong shows up as content sitting under the navigation bar, tables that jump
when the keyboard appears, and titles that sit one pixel off.

---

## 1. What it is for

Four jobs, in order of how much of the file they occupy:

1. **Compute the content inset for a full-screen-layout controller.** The 2013 app sets
   `self.wantsFullScreenLayout = true` for every screen (`TGViewController.mm:341`), so
   `self.view` starts at y=0 under the status bar and navigation bar. Nothing is laid out
   automatically; `controllerInset` is the number every subclass uses to place its content.
2. **Own the navigation-bar / status-bar appearance contract** through the
   `TGViewControllerNavigationBarAppearance` protocol, which `TGNavigationController` and
   `TGNavigationBar` interrogate.
3. **Provide the title label** — a `TGLabel` in `navigationItem.titleView`, not the system
   title — with the app's fonts, colour and text shadow.
4. **Global autorotation and user-interaction locks**, process-wide, not per instance.

---

## 2. Public surface

### 2.1 Class-level typography and colour (all `+`)

| API | Portrait | Landscape | Citation |
|---|---|---|---|
| `titleFontForStyle:landscape:` | `boldSystemFont` 20 | `boldSystemFont` 17 | `TGViewController.mm:85`, `:92` |
| `titleTitleFontForStyle:landscape:` | `boldSystemFont` 16 | `boldSystemFont` 15 | `:103`, `:110` |
| `titleSubtitleFontForStyle:landscape:` | `systemFont` 13 | `systemFont` 13 | `:121`, `:128` |
| `titleTextColorForStyle:` | `#ffffff` for **both** styles | — | `:139`, `:146` |
| `titleShadowColorForStyle:` | Default `#3d5c81`; Black `#2f3948` | — | `:157`, `:164` |
| `titleShadowOffsetForStyle:` | `(0, -1)` for **both** styles | — | `:173`, `:177` |

Notes that matter when rebuilding:

- The `style` argument is marked `__unused` on all three font getters
  (`:79`, `:97`, `:115`) — style never changed the font, only the shadow colour. The two
  branches of `titleTextColorForStyle:` and `titleShadowOffsetForStyle:` are literally
  identical; `TGViewControllerStyleBlack` differs from Default in exactly one value,
  the shadow colour.
- All of these are `static` one-shot caches, so they are effectively constants.
- **20/17 is the single-line screen title.** 16/15 is the *two-line* title used by the
  conversation screen only: `TGConversationController.mm:765-767` is the sole call site of
  `titleTitleFontForStyle:` in the whole tree.
- **`titleSubtitleFontForStyle:` (13pt regular) is never called anywhere.** The chat
  header's status line is hardcoded `boldSystemFontOfSize:12`, `#e0eefd`, shadow
  `#3d5c81`, offset `(0,-1)`, `TGLabelVericalAlignmentTop`
  (`TGConversationController.mm:780-783`). If you copy 13pt regular from the header, you
  copy something the app never displayed. This is a real trap; the constant exists and
  looks authoritative.
- Shadow offset `(0,-1)` means the shadow is drawn *above* the glyphs. That is the
  1px dark line under the top bevel of the carved 2013 bar; it is not a drop shadow.

### 2.2 Screen geometry

- `screenSize:` / `screenSizeForInterfaceOrientation:` cache
  `[UIScreen mainScreen].bounds.size` once at first call and swap width/height for
  landscape (`:181-215`). They never re-read the screen — deliberate, because in 2013
  `bounds` was orientation-stable anyway.
- `isWidescreen` is true when portrait width > 321 **or** height > 481 (`:227`), i.e. the
  4-inch iPhone 5. On our 4S it is **false**. Nineteen-odd call sites branch on it
  (`TGWallpaperPreviewController.m:121`, `TGLoginInactiveUserController.m:170`,
  `TGCameraController.m:202`, and it even changes network page sizes —
  `TGTelegraphConversationCompanion.mm:745` requests 12 messages instead of 50 on a
  non-widescreen device). For our target the "narrow" branch is always the live one.

### 2.3 Autorotation and interaction locks

Process-global state: `autorotationDisabled` (a bool) plus `std::set<int> autorotationLockIds`
(`:14-19`). `autorotationAllowed` is `!autorotationDisabled && lockIds.empty()` (`:271`).

- `disableAutorotationFor:` installs an `NSTimer` on `NSRunLoopCommonModes` (so it fires
  during scrolling) that re-enables rotation and immediately calls `attemptAutorotation`
  (`:265-266`, `:285-292`). The `reentrant:` variant is a no-op if rotation is already
  disabled (`:251-252`), so a nested caller cannot shorten an outer lock.
- `TGAutorotationLock` is an RAII token: it inserts its id on `init` and erases it on
  `dealloc`, marshalling to the main thread when created off it (`:33-43`, `:52-62`).
  `acquireRotationLock` / `releaseRotationLock` are the instance-level wrappers
  (`:392-401`) — releasing is just dropping the strong reference.
- `shouldAutorotateToInterfaceOrientation:` returns `autorotationAllowed && orientation !=
  PortraitUpsideDown` (`:405`). Upside-down was never supported.
- `shouldAutorotate` (iOS 6) asks the iOS 5 method with a portrait argument (`:410`), so
  under iOS 6 rotation is gated by the global lock alone; the per-orientation filtering
  falls to `supportedInterfaceOrientations` on `TGNavigationController`
  (`TGNavigationController.m` `supportedInterfaceOrientations` → `MaskAllButUpsideDown`).
- `disableUserInteractionFor:` wraps `beginIgnoringInteractionEvents` in the same timer
  pattern and is careful to `end…` before restarting (`:294-317`). Used to swallow taps
  during transitions.

### 2.4 The appearance protocol

```objc
- (UIBarStyle)requiredNavigationBarStyle;      // default UIBarStyleDefault  (:652)
- (bool)navigationBarShouldBeHidden;           // synthesized property       (h:82)
@optional navigationBarHasAction / navigationBarAction / navigationBarSwipeDownAction
@optional statusBarShouldBeHidden;             // default false              (:670)
@optional viewControllerPreferredStatusBarStyle;// default BlackOpaque       (:675)
```

`TGNavigationController setupNavigationBarForController:animated:`
(`TGNavigationController.m:152-180`) reads all five in one pass on every
`viewWillAppear:` and pushes them into `UINavigationBar.barStyle`,
`setStatusBarHidden:`, `setStatusBarStyle:`, each guarded by an equality check so an
unchanged value never animates. `TGViewController` calls it itself from `viewWillAppear:`
(`TGViewController.mm:479-480`) rather than relying on the delegate — meaning a controller
pushed *without* a `TGNavigationController` silently gets no appearance setup.

The three optional action methods are the *bar-as-a-button* behaviour, driven from
`TGNavigationBar.m`. On `touchesBegan` the bar hit-tests; if the touch did not land on a
subview that owns gesture recognizers (`findViewHasActions`, `TGNavigationBar.m:505-512`)
and the top controller answers `navigationBarHasAction` true, an overlay view is shown at
alpha 1 (`:519-530`). On `touchesEnded` the overlay fades out over **0.34 s**
(`hideActionOverlay`, `:544`) and `navigationBarAction` fires (`:567-570`); a cancel fades
it without firing (`:577-583`). A swipe-down recognizer calls `navigationBarSwipeDownAction`
(`:585-594`). Also note `TGNavigationBar hitTest:` retries the hit 16 px to the left and
accepts a `TGToolbarButton` found there (`:534-541`) — the back button's touch target is
widened by 16 px on its left.

### 2.5 Insets — the core of the class

Three insets are published, all read-only:

- `controllerCleanInset` — status bar + nav bar + `parentInsets` + tab bar + keyboard.
- `controllerInset` — clean inset **plus** `explicitTableInset`.
- `controllerScrollInset` — clean inset **plus** `explicitScrollIndicatorInset`.

Computation, `_updateControllerInsetForOrientation:statusBarHeight:keyboardHeight:force:notify:`
(`:717-770`):

1. `navigationBarHeight = navigationBarShouldBeHidden ? 0 : (portrait ? 44 : 32)` (`:721`).
   **32, not 44, in landscape** — that is the iOS 6 short bar; landscape 44 only arrived
   with the iPhone 6 Plus (see §5).
2. `edgeInset = (statusBarHeight + navigationBarHeight, 0, 0, 0)` (`:722`). The status bar
   height comes from the live frame, `MIN(width, height)` of `statusBarFrame` (`:537-541`),
   so it is 20 normally and 40 during an in-call bar.
3. `parentInsets` added on all four sides (`:724-727`).
4. `+49` to the bottom if `parentViewController` is a `UITabBarController` (`:730`).
5. Unless `ignoreKeyboardWhenAdjustingScrollViewInsets`, `bottom = MAX(bottom, keyboardHeight)`
   (`:732-733`) — MAX, not `+`, so a keyboard over a tab bar does not double-count.
6. The scroll-indicator inset forks off *before* `explicitTableInset` is applied (`:739-750`).
   That is why a table can have extra top padding while its scrollbar still starts at the
   bar.
7. The status-bar background view is re-framed to `(0, y<0 ? -statusBarHeight : 0, screenWidth,
   statusBarHeight)` — it preserves its own off-screen state rather than snapping back
   (`:752-754`).
8. Only if something actually changed (or `force`) are the ivars written and
   `controllerInsetUpdated:` sent (`:756-767`); the method returns whether it changed.

`controllerInsetUpdated:` (`:795-820`) applies the result: it walks `self.view.subviews`,
takes the **first** `UIScrollView` and stops (`break`, `:807`), then also applies to every
scroll view in `scrollViewsForAutomaticInsetsAdjustment`. So a screen with two tables must
declare the second one explicitly.

`_autoAdjustInsetsForScrollView:previousInset:` (`:772-793`) is the subtle part:

- sets `contentInset` and `scrollIndicatorInsets`;
- if the previous inset was non-zero, it shifts `contentOffset.y` by
  `previousInset.top - finalInset.top` and clamps to
  `[-finalInset.top, contentSize.height - (frameHeight - finalInset.bottom)]` (`:783-785`).
  This is what keeps the visible row still while the keyboard or in-call bar changes the
  inset;
- if the previous inset was zero (first layout) it only pins to the top when the offset is
  above the inset (`:788-792`), which prevents fighting a controller that restored a
  scroll position.

Triggers for recomputation, all wrapped in animations that match the system's:

| Event | Duration | Citation |
|---|---|---|
| `viewWillAppear:` | none | `:482` |
| `willAnimateRotationToInterfaceOrientation:` | inside the rotation block | `:498-507` |
| `UIApplicationWillChangeStatusBarFrame` | **0.35 s**, `BeginFromCurrentState` | `:552` |
| `UIKeyboardWillChangeFrame` | duration from the notification | `:567-569` |
| `UIKeyboardWillHide` | duration from the notification, keyboard height 0 | `:583-585` |
| `setExplicitTableInset:…` | none | `:693-702` |
| `setNavigationBarHidden:…` | `UINavigationControllerHideShowBarDuration` | `:899-902` |

All three notification handlers are suppressed while
`_viewControllerIsChangingInterfaceOrientation` is true (`:545`, `:561`, `:578`), a flag
set in `willRotate…` and cleared in `didRotate…` (`:492`, `:512`) — otherwise the keyboard's
own rotation notifications would fight the rotation-time inset update.

`_keyboardAdditionalDeltaHeightWhenRotatingFrom:toOrientation:` (`:525-535`) is an empty
shell that always returns 0. It was scaffolding for a fix that was never written; do not
port speculative behaviour into it.

### 2.6 Title label

`setTitleText:` (`:437-466`) lazily builds a `TGLabel`:

- clear background; `portraitFont`/`landscapeFont` from `titleTextFontPortrait/Landscape`
  if the subclass supplied them, else the 20/17 pair (`:446-447`);
- colour, shadow colour and shadow offset from the class getters (`:449-451`);
- `verticalAlignment = TGLabelVericalAlignmentTop` (`:453`);
- installed as `navigationItem.titleView` (`:455`).

Sizing, every time the text is set: frame to `(0,0,480,44)`, `sizeToFit`, then **height +2**
(`:459-462`), x centred against `self.view.frame.size.width` using an `int` cast (integral
pixels), y `= (int)(((portrait ? 44 : 32) - height) / 2) + 1` (`:463-464`). The `+2` on
height plus the `+1` on y are there because the label is top-aligned and the shadow is
drawn one point above the glyphs — without them the shadow clips.

`adjustNavigationItem:` (`:633-646`) re-runs on every orientation change: it hands the label
`setLandscape:` (which swaps to the landscape font), gives it the full screen width and the
44/32 bar height, `sizeToFit`, `+2` again — but note it does **not** recentre x. Centring in
landscape is left to `UINavigationBar`'s own titleView centring, which only works because
the label is resized to its fitted width.

`fadeInTitleText` (`:428-435`): alpha 0 → 1 over **0.3 s**, no delay, default curve. Used
when a title becomes known asynchronously (a name arriving from the server) so the bar does
not pop.

**Empty / long text:** nothing truncates. `sizeToFit` on a `UILabel` with the default one
line and 480 pt of slack produces whatever width the string needs; if that exceeds the space
between the bar buttons, `UINavigationBar` clips it (it does not scale a custom titleView).
The conversation screen worked around that by setting `lineBreakMode =
NSLineBreakByTruncatingTail` on its own label (`TGConversationController.mm:772`), which the
base class does not do. Empty string gives a zero-width label; the conversation screen
substitutes `@" "` for an empty title (`TGConversationController.mm:762`) precisely because a
zero-size `TGLabel` misbehaves.

`subtitleText` is declared and stored but the base class never renders it (`:468-471`).

### 2.7 Back button

`setBackAction:` (`:599-613`) creates a `TGToolbarButton` of type
`TGToolbarButtonTypeBack`, tags it `0x263D9E33` (a magic number used elsewhere to find the
back button in the bar), titles it `NSLocalizedString(@"Common.Back")`, `sizeToFit`s, wires
`UIControlEventTouchUpInside` to the selector, and installs it as
`navigationItem.leftBarButtonItem`. So **the 2013 back button was never the system back
button**; it was a custom control, which is why its artwork and its 16 px hit-test widening
live in `TGNavigationBar`.

The image variant (`:615-631`) additionally sets `backSemantics = true`, `paddingLeft = 15`,
`paddingRight = 9` and takes explicit normal/highlighted images for portrait and landscape
plus text and shadow colours. Login screens use it with white text and shadow
`rgba(0x050608, 0.4)` (`TGLoginPhoneController.m:134`) or `rgba(0x07080a, 0.35)`
(`TGLoginProfileController.m:131`).

Both variants do nothing at all when `backAction` is `nil` — they do not clear an existing
button (`:603`, `:619`). Setting the back action to nil to remove the button silently fails.

### 2.8 Hiding the navigation bar

`setNavigationBarHidden:withAnimation:duration:` (`:832-904`), default duration **0.3 s**
(`:829`). Guard: it runs only if the requested state differs from either the navigation
controller's state or `navigationBarShouldBeHidden` (`:834`) — the double condition
re-syncs a controller whose flag drifted from reality.

- `…AnimationFade`: when showing, unhide instantly at alpha 0 then animate to 1; when
  hiding, animate alpha to 0 then restore alpha 1 and hide for real in the completion
  (`:838-861`). The alpha restore matters — leaving a hidden bar at alpha 0 breaks the next
  non-animated show.
- `…AnimationSlideFar`: manual frame animation between `y = -barHeight` and
  `y = statusBarHeight`, with `barHeight` 44 portrait / 32 landscape (`:867`) and the status
  bar height from `TGHacks` (`:868`). "Far" means it slides fully off-screen above the status
  bar rather than tucking behind it.
- `…AnimationSlide` / `None`: delegated to `UINavigationController` (`:896`).
- In every case the inset is recomputed inside a
  `UINavigationControllerHideShowBarDuration` animation (`:899-902`).

### 2.9 Status-bar background view

Created in `viewDidLoad` **only if** `viewControllerPreferredStatusBarStyle ==
UIStatusBarStyleBlackOpaque` and `autoManageStatusBarBackground` (`:415`): a plain black
`UIView`, 20 pt tall, full width, `userInteractionEnabled = false`,
`layer.zPosition = 1000`, `autoresizingMask = FlexibleWidth` (`:417-422`). Under
`wantsFullScreenLayout` the app's own content would otherwise show through the status bar;
this is the black strip that makes the bar look opaque. `zPosition 1000` keeps it above
everything the subclass adds. `setStatusBarBackgroundAlpha:` lets a screen fade it (the
media viewer does).

### 2.10 Small but load-bearing details

- `navigationController` is overridden to prefer `customParentViewController.navigationController`
  (`:385-390`), so a controller embedded as a child still finds the real nav stack.
- `_commonViewControllerInit` (`:339-376`) turns **off** iOS 7's
  `automaticallyAdjustsScrollViewInsets` via an obfuscated selector
  (`TGEncodeText(@"tfuBvupnbujdbmmzBekvtutTdspmmWjfxJotfut;", -1)` — a Caesar shift by −1 of
  `setAutomaticallyAdjustsScrollViewInsets:`, `:351`), because the class does that job
  itself. Irrelevant on iOS 6 but explains the intent: inset management is exclusive.
- `viewWillAppear:` makes `selectActiveInputView` first responder before anything else
  (`:475-477`), so a screen that returns a text field from that hook opens with the keyboard
  already up and the inset already accounting for it.
- `dealloc` removes exactly the three observers it added (`:378-383`).

---

## 3. Our port

**We do not have this class.** `grep -rl "TGBaseViewController\|controllerInset"` over
`iTgLegacy/src` matches only `TGActionTableView.m`. Every screen subclasses
`UITableViewController` or `UIViewController` directly (36 declarations across
`iTgLegacy/src/*.h`, e.g. `TGChatListViewController.h:10`, `TGChatViewController.h:10`,
`TGSettingsViewController.h:23`). `wantsFullScreenLayout` is set in exactly two places
(`TGVideoCaptureViewController.m:88`, `TGStoriesViewController.m:1970`).

That is a defensible architectural choice — UIKit on iOS 6 with a non-full-screen layout
does the top inset for you — but it has visible consequences, and the numbers we do use are
in places wrong.

### Differences a user can see

1. **No title shadow anywhere.** `TGTheme.m:456` and `:459` set only
   `UITextAttributeTextColor` / `NSForegroundColorAttributeName`. The original always drew
   the title with shadow `#3d5c81` at offset `(0, -1)` for the default (blue) bar and
   `#2f3948` for the black bar (`TGViewController.mm:157`, `:164`, `:173`). On the carved
   2013 bar the missing shadow is the difference between text that sits *in* the bar and
   text that floats on it. Fix: add
   `UITextAttributeTextShadowColor: tgRGB(0x3d5c81)` and
   `UITextAttributeTextShadowOffset: UIOffsetMake(0, -1)` to the non-flat branch of
   `styleNavigationBar:`. Note `UITextAttributeTextShadowOffset` takes a `UIOffset`, and
   the sign convention is the same as `CGSize` here, so `-1`.
   `TGLoginViewController.m:337-339` already does exactly this but with the *wrong* values:
   shadow `#25272b` at offset `(0, +1)`. If the login bar is meant to be the black style,
   the original value is `#2f3948` at `(0, -1)`.
2. **Chat header title is 17 pt; the original is 16 pt.**
   `TGChatViewController.m:2885` uses `boldSystemFontOfSize:17`;
   `TGConversationController.mm:765` uses `titleTitleFontForStyle:` = bold 16
   (`TGViewController.mm:103`). One point, but it changes where the two-line header breaks
   for long group names.
3. **Chat header subtitle: wrong weight and wrong colour.**
   `TGChatViewController.m:2895-2898` uses `systemFontOfSize:12` and either the secondary
   text colour or `white @ 0.75`. The original is `boldSystemFontOfSize:12`, solid
   `#e0eefd`, with its own shadow `#3d5c81` at `(0,-1)`
   (`TGConversationController.mm:780-783`). White-at-75 % over a blue bar is not the same
   colour as `#e0eefd`, and the missing bold reads as a different typeface at 12 pt.
   Interestingly `TGChatListViewController.m:832-834` (the story header) *does* use
   `#E0EEFD` — but at `systemFontOfSize:13`, i.e. it copied the unused
   `titleSubtitleFontForStyle:` constant. Both should be bold 12 / `#e0eefd`.
4. **Chat header title shadow is generic black.** `TGChatViewController.m:2890` uses
   `white 0.0 alpha 0.4`; the original is the opaque blue-grey `#3d5c81`. Against the blue
   bar a translucent black shadow goes muddy where the flat one stays crisp.
5. **No `fadeInTitleText` equivalent.** When a chat title or a contact name arrives
   asynchronously, ours pops. The original faded it in over 0.3 s
   (`TGViewController.mm:431`). Cheap to add wherever we assign a title after a network
   round trip.
6. **No landscape font swap and no 32 pt landscape bar handling.** The original switched
   the title to bold 17 (single-line) / bold 15 (two-line) and re-laid the label against a
   32 pt bar (`TGViewController.mm:640`, `:92`, `:110`). Ours sets one font. Most of our
   screens are portrait-only in practice, but `TGMediaViewController` and
   `TGCallViewController` do rotate (`TGMediaViewController.m:1047`,
   `TGCallViewController.m:201`), and any custom titleView there will be mis-sized in
   landscape.
7. **No navigation-bar tap or swipe-down action.** `navigationBarHasAction` /
   `navigationBarAction` / `navigationBarSwipeDownAction` have no counterpart in our source
   (grep finds nothing). In the original, tapping empty bar space on a screen that opted in
   showed a highlight overlay and fired an action on release, with a 0.34 s fade-out
   (`TGNavigationBar.m:519-570`). Whether we need it depends on which screens opted in;
   worth a separate check before implementing.
8. **No 16 px left widening of the back-button hit test.** `TGNavigationBar.m:534-541`
   retries `hitTest:` at `x - 16` and accepts a `TGToolbarButton`. Ours uses the system back
   button through the appearance proxy (`TGTheme.m:477-503`), which has its own (smaller)
   target. On a 4S this is a felt difference — the original's back button was noticeably
   easier to hit.
9. **Ad-hoc inset arithmetic per screen.** `RootViewController.m:76-77` hardcodes a 49 pt
   bottom inset (the original derived it from `parentViewController` being a
   `UITabBarController`, `TGViewController.mm:730`); `TGForwardPicker.m:301`,
   `TGSettingsViewController.m:1109`, `TGChatViewController.m:4029` and
   `TGSearchViewController.m:887` each patch `contentInset` by hand. None of them do the
   original's offset-preserving clamp (`TGViewController.mm:783-785`), so a table can jump
   when the keyboard or the in-call status bar changes height. If we ever see "the list
   jumps when the green in-call bar appears", that is this.
10. **No rotation lock.** The original could freeze rotation globally for a duration or via
    an RAII token during a transition (`TGViewController.mm:244-272`). Ours has per-screen
    `shouldAutorotate` only. Symptom to watch for: rotating mid-push/mid-dismiss.

### What is right

`TGLabel` is ported faithfully — our `TGLabel.h` is character-for-character the original's
interface including `verticalOffsetMultiplier` and `customDrawingSize`. `TGTheme`'s
`barStyle` / opaque-bar reasoning matches the original's intent, and the carved
`NavBarBackground` + `BackButton` stretchable artwork with a 15 pt left cap
(`TGTheme.m:494-495`) matches the original's `paddingLeft = 15`
(`TGViewController.mm:623`).

### Recommendation

Do not retrofit a `TGViewController` base class into 36 screens now. Do centralise the
*typography* in `TGTheme` — a `barTitleFont` (bold 20 / bold 17), `barTitleShadowColour`
(`#3d5c81` / `#2f3948`), `barTitleShadowOffset` `(0,-1)`, `headerTitleFont` (bold 16 / 15)
and `headerSubtitleFont` (bold 12) with `headerSubtitleColour` `#e0eefd` — and fix the four
call sites above. That captures nearly all of the visible delta for a small change.

---

## 4. What it became: Telegram-iOS (modern)

`Telegram-iOS/submodules/Display/Source/ViewController.swift` (802 lines) is the direct
descendant. The lineage is obvious and the shift is total:

- **Push, not pull.** The 2013 class *computed* an inset and each subclass *read*
  `controllerInset` whenever it laid out. The modern class receives a
  `ContainerViewLayout` and pushes it down: `containerLayoutUpdated(_:transition:)`
  (`ViewController.swift:477`) is the single entry point, and every geometry input — size,
  safe-area insets, status bar height, keyboard height, size classes — arrives inside that
  one struct. There is no ambient "what is the status bar doing right now" query left.
- **Transitions are values.** Every layout call carries a `ContainedViewLayoutTransition`
  instead of the 2013 pattern of wrapping the inset recomputation in a hand-matched
  `UIView animateWithDuration:` whose 0.35 or "duration from the keyboard notification"
  had to be guessed correctly at each of the six call sites listed in §2.5. This was forced
  by interactive (gesture-driven) transitions, where a fixed duration is meaningless.
- **The navigation bar became content.** `navigationLayout(layout:)`
  (`ViewController.swift:263-271`) computes `statusBarHeight + navigationBar.contentHeight`
  rather than the 2013 hardcoded `44/32`, because the bar now hosts search fields and
  variable-height content nodes. The `44/32` constants could not survive.
- **The status bar background became a `StatusBar` object** owned by the controller
  (`:209`, `:505`) framed at a flat 40 pt (`:484`) — the 2013 20 pt black `UIView` at
  `zPosition 1000` generalised into a real component once carriers, calls and recording
  indicators all wanted to tint it.

Nothing in the modern file is copyable for us; its value is the confirmation that the 2013
inset model's weak spot was exactly what we already see in our port — ambient global state
read at unpredictable times, with animation durations duplicated per call site.

## 5. What it became: `twelve` (the Objective-C fork)

`twelve/submodules/LegacyComponents/LegacyComponents/TGViewController.{h,mm}` — the same
class, grown from 928 to 1510 lines. This is the most useful of the three comparisons
because it shows which 2013 constants were *forced* to change and which held.

Held unchanged: `isWidescreen`'s `> 321 || > 481` test (`twelve TGViewController.mm:250-259`),
the whole `TGAutorotationLock` mechanism, the inset composition order
(`:729-748` mirrors the original `:721-750` line for line), the appearance protocol.

Changed, and why:

- **`44/32` became a computed method.** `navigationBarHeightForInterfaceOrientation:`
  (`twelve:1043-1060`) still returns 44 portrait / 32 landscape for every phone *except*
  the 736-point-wide one (iPhone 6 Plus), where landscape is 44. A hardware change forced
  it; on our 4S the original constants are still exactly right.
- **Safe areas.** `safeAreaInsetForOrientation:` (`twelve:1084-1099`) returns
  `(44, 0, 34, 0)` portrait and `(0, 44, 21, 44)` landscape when the screen is 812 points
  tall (iPhone X), zero otherwise. Purely notch-driven; irrelevant to us.
- **Status bar height gained a clamp.** `MAX(prefersStatusBarHidden ? 0 : 20, MIN(w, h))`
  then `MIN(40, height + _additionalStatusBarHeight)` (`twelve:820-822`, `:830-832`). The
  2013 code took the raw `MIN(w, h)` (`original :540`). The floor of 20 and ceiling of 40
  are defensive patches against transient status-bar frames during call/hotspot bars — a
  real bug fix we could adopt cheaply if we ever compute insets ourselves.
- **Screen-size predicates multiplied**: `hasLargeScreen` (≥667), `hasVeryLargeScreen`
  (≥736), `hasTallScreen` (≥812) alongside `isWidescreen` (`twelve:262-300`). Pure device
  proliferation.
- **`titleShadowColorForStyle:` and `titleShadowOffsetForStyle:` were deleted** from the
  header (compare `original TGViewController.h:50-51` with `twelve TGViewController.h:48`,
  which keeps only `titleTextColorForStyle:`). This is the flat-design cut: iOS 7 removed
  the bevelled bar, so the shadow had nothing to sit against. It is a change of taste, and
  for us the *2013* behaviour is the correct one — which is precisely the defect listed in
  §3.1.
- **Bar-button setters moved onto the class** (`setLeftBarButtonItem:animated:`,
  `setRightBarButtonItems:animated:`, `setTitleView:`, `setTargetNavigationItem:titleController:`,
  `twelve TGViewController.h:133-140`) because controllers began being displayed inside
  another controller's navigation item (preview/peek, form sheets). The 2013 class only
  ever touched `self.navigationItem` directly.
- `backAction` / `titleText` / `subtitleText` as *properties* are gone; `setTitleText:` is
  a plain method now (`twelve TGViewController.h:139`) and the `TGToolbarButton` back button
  disappeared entirely with the flat redesign.

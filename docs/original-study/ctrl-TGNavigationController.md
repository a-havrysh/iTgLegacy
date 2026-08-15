# TGNavigationController (original, Telegram for iOS 1.1 / build 21024)

Source of truth, all paths relative to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`:

- `TelegraphKit/TelegraphKit/TGNavigationController.h` (60 lines)
- `TelegraphKit/TelegraphKit/TGNavigationController.m` (584 lines)
- `TelegraphKit/TelegraphKit/TGNavigationBar.h` / `.m` (34 / 616 lines) — inseparable from the controller; the controller is mostly a driver for this bar
- `Telegraph/Telegraph/TGNavigationController.xib` — the nib every instance is loaded from
- `TelegraphKit/TelegraphKit/TGGestureNavigationController.h` / `.m` — a dead alternative superclass, see §1

The class exists under exactly this name. No renaming or "closest match" was needed.

---

## 1. What it is for

`TGNavigationController` is a `UINavigationController` subclass that exists to do four things UIKit
would not do in 2013:

1. Own a `TGNavigationBar` (a fully custom-drawn bar) and keep its style in sync with whatever
   controller is on top, via the `TGViewControllerNavigationBarAppearance` protocol.
2. Choreograph the bar's *contents* during push/pop — the back button and title view slide
   independently of UIKit's own crossfade.
3. Manage the stack destructively: controllers can ask to be dropped from the stack once they are no
   longer visible (`TGNavigationControllerItem`), and controllers get explicit teardown callbacks
   (`TGDestructableViewController`).
4. Paint the chrome UIKit does not paint: a bottom "black corners" strip, an optional black slab
   behind the bar, and an optional full-screen `backgroundView` with a two-layer pattern that slides
   during transitions (used only by the login flow).

There is a declared but **disabled** second personality. `TGNavigationController.h:13` defines
`#define TGUseGestureNavigationController false`, and `TGNavigationController.h:15-20` makes the
superclass conditional — `TGGestureNavigationController` when true, `UINavigationController` when
false. The whole of `TGNavigationController.m:184-582` (every override: rotation, push, pop,
`setNavigationBarHidden:`, delegate methods) is inside `#if !TGUseGestureNavigationController`.
**In the shipped build the flag is false**, so everything documented below is live, and
`TGGestureNavigationController` (435 lines, an aborted hand-written interactive-pop container;
`TGGestureNavigationController.m:38` shows its bar-height rule `width > 320 ? 32 : 44`) is dead code.
Do not port it. Its one useful datum is that bar height in the era was 44 pt portrait, 32 pt landscape.

---

## 2. Public surface

```objc
@property (nonatomic, strong) UIView *cornersImageView;   // .h:22
@property (nonatomic, strong) UIView *backgroundView;     // .h:23
@property (nonatomic)         bool    restrictLandscape;  // .h:25

+ navigationControllerWithControllers:                    // .h:27
+ navigationControllerWithRootController:                 // .h:28
+ navigationControllerWithRootController:blackCorners:    // .h:29
- setupNavigationBarForController:animated:               // .h:31
- updateControllerLayout:                                 // .h:33
- acquireRotationLock / releaseRotationLock               // .h:35-36
```

Plus two protocols declared in the same header:

- `TGNavigationControllerItem` (`.h:40-50`): required `-shouldBeRemovedFromNavigationAfterHiding`,
  optional `-shouldRemoveAllPreviousControllers`.
- `TGBarItemSemantics` (`.h:52-60`): required `-backSemantics`, optional `-barButtonsOffset`.

Notes on the surface itself:

- `updateControllerLayout:` is **entirely commented out** (`.m:124-150`). It is a no-op in the
  shipped build. Anything we port that relies on it is porting a stub.
- `cornersImageView` is declared and read (`TGNavigationBar.m:407, 435, 463` set its alpha per bar
  style) but is **never assigned anywhere in the codebase**. It is a vestige: the alpha writes go to
  `nil`. This is the one genuinely ambiguous piece of the class — the intent was clearly that a
  corner overlay fades out under a translucent bar, but the shipped app has no such overlay.
- `setupNavigationBarForController:animated:` is public so callers can pre-align the bar before a
  controller is actually on top; it duplicates the appearance block that `pushViewController:` runs
  inline (`.m:152-182` vs `.m:251-264`).

---

## 3. Construction: `navigationControllerWithControllers:blackCorners:`

`TGNavigationController.m:34-71`. Every instance in the app goes through here. There is no plain
`alloc/init` call site.

Steps, in order:

1. `.m:37` — `[TGNavigationBar description]` purely to force the class to be realised before the nib
   decodes, because the nib references it by name.
2. `.m:48` — the instance is **loaded from the nib `TGNavigationController.xib`**, not allocated:
   `[[NSBundle mainBundle] loadNibNamed:@"TGNavigationController" owner:UIApplication.delegate ...]
   objectAtIndex:0`. The nib (`Telegraph/Telegraph/TGNavigationController.xib`) contains a single
   `IBUINavigationController` whose class is `TGNavigationController` and whose navigation bar's
   class is `TGNavigationBar` (`xib:110-121` declare both partial class descriptions). The nib is the
   *only* mechanism by which the custom bar class gets installed — pre-iOS-5
   `initWithNavigationBarClass:toolbarClass:` is not used. The nib also sets
   `IBUIClipsSubviews = YES` on the bar (`xib:50`), which the bar immediately undoes in code
   (`TGNavigationBar.m:144` `self.clipsToBounds = false`) so the shadow can hang below it.
3. `.m:51` — `setViewControllers:` with the passed array (no animation).
4. `.m:53` — the bar's back-pointer is wired: `((TGNavigationBar *)navigationBar).navigationController = self`.
   Without this the bar cannot reach `topViewController`, so its tap action, swipe-down action and
   corner-alpha behaviour all silently do nothing. This is the single easiest wiring step to forget.
5. `.m:55-59` — **bottom corners**. `BlackCornersBottom.png`
   (`Telegraph/Telegraph/Resources/BlackCornersBottom@2x.png`, 16×8 px = **8×4 pt**) is stretched with
   `stretchableImageWithLeftCapWidth:(int)(width/2) topCapHeight:0`, i.e. cap 4 pt each side, and
   pinned to the bottom of the controller's view: frame
   `(0, view.height - 4, view.width, 4)`, autoresizing `FlexibleWidth | FlexibleTopMargin`, added as
   the topmost subview of the navigation controller's view. It is applied **unconditionally**,
   including for `blackCorners:false` callers.
6. `.m:61-68` — **the black slab**, only when `blackCorners` is true: a plain `UIView`
   `CGRectMake(0, 0, 320, 50)`, `backgroundColor` black, `autoresizingMask FlexibleWidth`,
   `layer.zPosition = -10`, inserted at index 0. Height 50 pt = 20 pt status bar + 44 pt bar, rounded
   up by 6; its job is to guarantee an opaque black ground behind the status bar and the bar during
   push/pop, when UIKit briefly exposes the window. `zPosition = -10` keeps it behind everything even
   if UIKit reshuffles subviews. Width is hardcoded 320 but flexible-width fixes it on rotation.

`blackCorners` defaults: `true` from `navigationControllerWithRootController:` (`.m:19-22`) and from
`navigationControllerWithControllers:` (`.m:29-32`). In practice **every modal presentation passes
`false`** and only the two root stacks take the default: the login stack
(`TGAppDelegate.mm:109`, explicit `blackCorners:true`) and the main stack
(`TGAppDelegate.mm:303`, default). Modal `false` call sites, all of them:
`TGContactsController.mm:2347, 2367`, `TGNotificationSettingsController.m:635, 656`,
`TGTelegraphImageViewControllerCompanion.mm:381`, `TGLoginPhoneController.m:769`,
`TGProfileController.m:2933, 3048, 3154, 3163, 4570`, `TGTelegraphConversationCompanion.mm:1867`,
`TGBlockedUsersController.mm:454`, `TGTelegraphConversationProfileController.mm:1786`. The rule to
remember: **root stacks get the black slab, modally presented stacks do not** (a modal already sits
over an opaque parent, so the slab would only darken the flip/slide edges).

---

## 4. The bar it drives (`TGNavigationBar`) — metrics, artwork, colours

The controller is unusable without this, so it is documented here rather than elsewhere.

### Background artwork

`TGNavigationBar.m:86-101`, a `dispatch_once` on first bar init:

- If `resizableImageWithCapInsets:` exists (iOS 5+, so always for us):
  `Header_Corners.png` (88×88 px = **44×44 pt**) and `Header_Corners_Landscape.png`
  (64×64 px = **32×32 pt**), each resized with `UIEdgeInsetsMake(0, 8, 0, 8)` — 8 pt caps left and
  right, nothing vertical. The name is literal: the artwork's whole reason to be 44 pt wide with 8 pt
  caps is that its left and right 8 pt carry the rounded top corners of the bar; the middle column
  tiles across. Height matches bar height exactly: 44 pt portrait, 32 pt landscape.
- Otherwise (pre-iOS 5 fallback, dead for us): flat `Header.png` / `Header_Landscape.png` used as
  `colorWithPatternImage:` (`.m:97`, `.m:47-48`).

Black-opaque background: `HeaderBlackOpaque.png` (64×88 px = 32×44 pt) and
`HeaderBlackOpaque_Landscape.png`, always installed as **pattern colours**, never resizable
(`.m:51-55`, `.m:100`). Consequence: the black variant tiles a 32 pt-wide pattern rather than
stretching, so its corners do not behave like the default image's do.

Landscape is decided by a single test, repeated: `self.frame.size.width > 400`
(`TGNavigationBar.m:171`, `.m:235`). Not by orientation, not by 320 — by 400. On a 4S this means
480 > 400 in landscape, 320 in portrait. `layoutSubviews` compares that against the cached
`_currentBackgroundsAreLandscape` and calls `updateBackground` only on change (`.m:237-240`).

### View stack inside the bar (`commonInit`, `.m:77-145`)

- `self.backgroundColor` is force-clamped to `clearColor`: `setBackgroundColor:` ignores its argument
  entirely (`.m:147-153`). `drawRect:` is empty (`.m:485-487`). The bar draws nothing itself.
- `_backgroundContainer`: full-bounds, flexible W+H, `userInteractionEnabled = false`,
  `backgroundColor` **black** (`.m:110`). Sent to back on every `layoutSubviews` (`.m:233`).
- `_defaultView`: `UIImageView` with the portrait image, full bounds, flexible W+H, opaque = false.
- `_blackView`: plain view, `backgroundColor` = the black-opaque pattern, `alpha = 0`.
- `_shadowView`: `HeaderShadow.png` (4×2 px = **2×1 pt**) at frame
  `(0, bar.height, bar.width, 1)` — i.e. **immediately below the bar, outside its bounds**, flexible
  width + flexible top margin (`.m:138-142`). It is visible only because `clipsToBounds = false`
  (`.m:144`) and because `layoutSubviews` re-clears `clipsToBounds` on every subview (`.m:285-288`).
  This 1 pt strip is the hairline under every screen's header; losing it is the classic symptom of a
  bar that "looks flat compared to the screenshots".
- A `UISwipeGestureRecognizer`, direction Down, on the bar itself (`.m:132-134`).

`setShadowMode:true` (`.m:159-167`) swaps the shadow for `HeaderLoginShadow.png` (2×4 px = 1×2 pt,
so **twice as tall**) and re-frames accordingly. Only the login stack calls it
(`TGAppDelegate.mm:117`).

### Bar style

`setBarStyle:animated:` (`.m:301-309`) is deliberately sabotaged: whatever is asked for, it forces
`UIBarStyleBlackTranslucent` before calling super. So the *UIKit* bar style is constant; what varies
is `_defaultView`/`_blackView` alpha, driven by `updateBarStyle:previousBarStyle:animated:duration:`
(`.m:398-483`), which is reached only from `setBarStyle:animated:duration:` (`.m:311-319`) — a method
**no one calls in this codebase**. `resetBarStyle` (`.m:321-333`) is the live path, invoked from
`TGNavigationController.m:244` after every bar hide/show change: `UIBarStyleDefault` → default view
alpha 1 / black 0; `UIBarStyleBlack` → the reverse. Net effect in the shipped app: the bar is
effectively always the default blue header, and the black-opaque machinery is present but inert.
Worth knowing before we spend effort reproducing a style transition users never saw.

### Bar hit testing and touch behaviour

- `hitTest:withEvent:` (`.m:535-542`) first probes at `point.x - 16` and returns that result **only
  if it is a visible `TGToolbarButton`**, otherwise falls back to the true point. This is a 16 pt
  leftward slop that makes the left-hand back button easier to hit near the screen edge without
  enlarging the button's frame or affecting anything else.
- `touchesBegan:` (`.m:514-533`) walks up from the hit view to the bar (`findViewHasActions`,
  `.m:503-512`); if no ancestor has gesture recognizers **and** the top controller answers
  `navigationBarHasAction` with true, it shows `actionOverlayView` at alpha 1 instantly.
  `touchesEnded:` (`.m:558-575`) fades that overlay out over **0.34 s** with
  `UIViewAnimationOptionBeginFromCurrentState` (`hideActionOverlay`, `.m:544-556`) and then calls
  `navigationBarAction`. `touchesCancelled:` fades it out without firing the action.
  The overlay art is `HeaderActionOverlay.png` (32×88 px = 16×44 pt) /
  `HeaderActionOverlay_Landscape.png`, stretched with left cap = width/2, centred horizontally and
  sized to the bar height (`.m:186-205`, `.m:290-293`). This is the "tap the header" affordance.
- The swipe-down recognizer calls `navigationBarSwipeDownAction` on the top controller (`.m:585-595`).

### iOS 7 manual bar-item layout

`TGNavigationBar.m:246-283` runs only when `iosMajorVersion() >= 7` and hand-positions
`leftBarButtonItem.customView` at x = 5 (portrait) / 3 (landscape), `rightBarButtonItem.customView`
right-aligned with the same 5/3 inset, and `titleView` centred, all vertically centred with `floorf`.
**On our 6.1.3 target this block never runs**; UIKit's own layout applies. Do not port it.

`findAndAlignButtons:landscape:` (`.m:211-229`) recurses the whole bar subtree every layout pass and
pushes the landscape flag into every `TGToolbarButton` (or anything responding to `setLandscape:`),
which is how buttons swap to their `_Landscape` artwork.

---

## 5. The appearance protocol

`TelegraphKit/TelegraphKit/TGViewController.h:26-42`:

```objc
@protocol TGViewControllerNavigationBarAppearance <NSObject>
- (UIBarStyle)requiredNavigationBarStyle;        // required
- (bool)navigationBarShouldBeHidden;             // required
@optional
- (bool)navigationBarHasAction;
- (void)navigationBarAction;
- (void)navigationBarSwipeDownAction;
@optional
- (bool)statusBarShouldBeHidden;
- (UIStatusBarStyle)viewControllerPreferredStatusBarStyle;
@end
```

`TGViewController` itself adopts it (`TGViewController.h:44`), so every screen in the app answers.

Defaults applied when a controller does **not** conform (`TGNavigationController.m:154-157`, and the
identical block at `.m:251-254`): bar style `UIBarStyleDefault`, bar not hidden, status bar style
`UIStatusBarStyleBlackOpaque`, status bar not hidden. Note the asymmetry that matters: the
*navigation* default is `Default` (blue header) while the *status bar* default is `BlackOpaque`.
The optional selectors are guarded with `respondsToSelector:` so a conforming controller that omits
them keeps those defaults.

Application order in `setupNavigationBarForController:animated:` (`.m:171-181`): hide/show the bar
first (only if the value differs), then bar style (animated only when
`_wasShowingNavigationBar == !self.navigationBarHidden`, i.e. only when the bar's visibility did not
change across the transition), then status-bar hidden (fade when animated), then status-bar style.
Every one of the four is guarded by a difference check, so redundant sets never animate.

---

## 6. Push

`pushViewController:animated:` (`.m:247-345`).

1. `.m:249` — `_wasShowingNavigationBar = !self.navigationBarHidden`, captured **before** super.
2. `.m:251-264` — read the incoming controller's appearance (same defaults as §5).
3. `.m:266` — remember `currentController = self.topViewController` (the one being covered).
4. `.m:268` — `[super pushViewController:...]`.
5. `.m:270` — the bar-item choreography runs **only if the bar's visibility is unchanged**
   (`_wasShowingNavigationBar == !navigationBarShouldBeHidden`). If the bar is appearing or
   disappearing, UIKit's own animation is left alone.
6. Outgoing back button (`.m:282-296`): if the covered controller's `leftBarButtonItem.customView`
   conforms to `TGBarItemSemantics` **and** `backSemantics` is true, reset its transform then animate
   over **0.4 s** to `CGAffineTransformMakeTranslation(-width * 2, 0)` — it slides off twice its own
   width to the left — and on completion snaps back to identity (UIKit has removed it from the bar by
   then, so the snap is invisible).
7. Incoming back button (`.m:299-311`): the new controller's back custom view starts at
   `translation((int)(screenWidth/2 - titleViewWidth/2 - customView.width/2), 0)` — i.e. positioned
   where the *outgoing screen's title* was — and animates to identity over **0.35 s**.
   `titleViewWidth` is the outgoing controller's `titleView.frame.size.width`, or **0 if it had no
   titleView** (`.m:273-280`), in which case the back button starts from the screen centre.
   `screenWidth` comes from `[TGViewController screenSizeForInterfaceOrientation:self.interfaceOrientation].width`
   (`.m:272`), not from `self.view.bounds`, so it is correct mid-rotation.
   Note the asymmetry: **0.4 s out, 0.35 s in**. That is the original's feel — the old back button
   leaves slightly slower than the new one arrives.
8. `.m:314-319` — bar style, status-bar hidden, status-bar style, each guarded, as in §5.
9. `.m:321-344` — the login-only pattern slide. If `_backgroundView` exists and contains subviews
   tagged `0xF7E5C50E` (pattern) and `0x7A461D42` (transition pattern), the pattern view slides from
   x=0 to x=-width and the transition copy from x=+width to x=0, over **0.35 s**, then both are reset
   and the copy re-hidden. Both tags are set in `TGAppDelegate.mm:129` and `:135`; the two views are
   identical `DarkLinen.png` pattern-colour views (`TGAppDelegate.mm:126`) inside a background that
   also carries a `LoginShadow.png` overlay tagged `0xB72CE77E` (`TGAppDelegate.mm:140-144`). So the
   login screens' linen background scrolls with the push instead of sitting still. That is the whole
   purpose of `backgroundView`; `TGAppDelegate.mm:146` is its only assignment in the app.

`setBackgroundView:` (`.m:107-122`) removes any previous view and inserts the new one at index 0
sized to `self.view.bounds`; `viewDidLoad` (`.m:80-91`) re-inserts it, `viewDidUnload` (`.m:93-101`)
removes it. Note the ordering hazard the original lives with: setting `backgroundView` before the
view is loaded triggers `self.view` and forces a load.

---

## 7. Pop

Two entry points, one shared tail.

`popViewControllerAnimated:` (`.m:445-475`):
1. capture `_wasShowingNavigationBar`;
2. read appearance from `viewControllers[count-2]` (nil if fewer than 2);
3. call `cleanupBeforeDestruction` on the current last object if it conforms to
   `TGDestructableViewController` (`.m:459-465`) — **before** super;
4. super pop;
5. `cleanupAfterDestruction` on the popped controller (`.m:469-470`);
6. `performPopTransition:...` — note it passes `navigationBarShouldBeHidden:self.navigationBarHidden`,
   i.e. the *current* value, not the value it just computed from the destination controller. This
   looks like a bug but is load-bearing: it makes the first branch of `performPopTransition` a no-op
   on a plain pop, so the bar is never re-hidden mid-pop.

`popToViewController:animated:` (`.m:477-513`) is the same shape but calls
`cleanupBeforeDestruction` on every controller above the target, walking
`viewControllers.reverseObjectEnumerator` and breaking at the target (`.m:491-498`), then
`cleanupAfterDestruction` on everything super returned. Here the computed
`navigationBarShouldBeHidden` **is** passed through (`.m:510`).
`popToRootViewControllerAnimated:` (`.m:515-521`) just forwards to `popToViewController:` with
index 0, falling back to super only on an empty stack — so root pops also get the cleanup and the
bar-item animation.

`performPopTransition:...` (`.m:347-443`), animated case only:
- Outgoing (the controller being popped) back button, if `backSemantics`: target x defaults to
  `screenWidth / 4`, but if the destination controller has a `titleView` the target becomes
  `-view.origin.x + titleView.origin.x + (titleView.width - view.width)/2` — that is, it flies to the
  centre of the *destination's title*, the exact inverse of the push. Duration **0.355 s**
  (`.m:376`), reset to identity on completion.
- Destination `titleView` (`.m:389-397`): all layer animations removed, alpha set to 0 and transform
  set to `translation(-screenWidth/2, 0)`, then animated to alpha 1 / identity over **0.355 s**. The
  expression is written `(int)(-currentWidth / 2 - 0 * titleView.frame.size.width / 2)`, with a
  literal `0 *` term — a disabled half-width correction. The effective value is `-screenWidth/2`.
- Destination back button, if `backSemantics` (`.m:399-411`): starts at
  `translation(-width * 2, 0)` and animates to identity over **0.355 s**.
- Both of the above run **only if the destination has a `leftBarButtonItem`** (`.m:387`) — the title
  animation is nested inside that check. A destination with no left item gets no title animation at
  all, which is why the chat-list root does not have its title fly in.
- Then bar style (`.m:416-417`), then the pattern slide in the opposite direction (`.m:419-442`),
  again 0.35 s.

Three near-identical durations coexist deliberately: **0.4** (outgoing back on push),
**0.35** (incoming back on push, pattern slides) and **0.355** (everything on pop). 0.355 is the
odd one; it is 5 ms longer than UIKit's own 0.35 push/pop, which keeps the bar items just behind the
view slide rather than racing it.

The only implementer of `TGBarItemSemantics` in the app is `TGConversationButtonContainer`
(`TGConversationController.mm:209-213`), whose `barButtonsOffset` returns `0` when it is the back
button and `4` otherwise (`.mm:217-220`), and whose `hitTest:` extends the touch area outside its own
bounds (`.mm:222-245`). `backSemantics = true` is set at `TGConversationController.mm:843` and
`TGWebController.m:203`. So in practice the whole choreography above applies to exactly the chat
screen's and web screen's back buttons.

---

## 8. Stack hygiene: `didShowViewController:`

`.m:527-580`, reached because `viewDidLoad` sets `self.delegate = self` (`.m:82`) and `dealloc`
clears it (`.m:75`).

Two independent rules:

1. **Self-removing controllers** (`.m:529-549`): every controller in the stack except
   `topViewController` whose **class** conforms to `TGNavigationControllerItem` is asked
   `shouldBeRemovedFromNavigationAfterHiding`; those answering true are removed with
   `setViewControllers:animated:false`. Note the check is `[[controller class] conformsToProtocol:]`,
   a class-level test, and the loop variable is typed `UINavigationController *` — sloppy but
   harmless. This is how the login chain collapses (`TGLoginWelcomeController.m:635`,
   `TGLoginCodeController.m:95`, `TGLoginProfileController.m:113`), how the forward picker disappears
   (`TGForwardTargetController.m:134`), and how the chat screen removes intermediate screens
   (`TGConversationController.mm:602`). `TGSelectContactController` makes it a settable property
   (`TGSelectContactController.h:15`, set true at `.m:114` and `.m:186`).
2. **Exclusive controllers** (`.m:551-577`): if the newly shown controller answers
   `shouldRemoveAllPreviousControllers` true and the stack is deeper than 2, the stack is rewritten to
   `[first, last]` and every controller in between gets `cleanupBeforeDestruction`, then
   `setViewControllers:animated:false`, then `cleanupAfterDestruction`. Driven by
   `TGInterfaceManager.mm:126`:
   `conversationController.shouldRemoveAllPreviousControllers = TGAppDelegateInstance.exclusiveConversationControllers && clearStack`.
   This is the "opening a chat from a notification should not build an infinite stack" rule.

Both rules fire after the animation has completed, so the user never sees the surgery.

`willShowViewController:` is an empty stub (`.m:523-525`).

---

## 9. Rotation

`.m:186-226`.

- `shouldAutorotateToInterfaceOrientation:` (iOS 5 path): `restrictLandscape` → portrait only;
  otherwise delegate to `topViewController`; with no top controller, allow everything except
  portrait-upside-down.
- `shouldAutorotate` (iOS 6 path): `restrictLandscape` → false; otherwise forward to the top
  controller if it responds; else true.
- `supportedInterfaceOrientations`: `restrictLandscape` → `Portrait`; else `AllButUpsideDown`.
  **Upside-down is never allowed anywhere in this app.**
- `acquireRotationLock` / `releaseRotationLock` (`.m:209-218`) hold a `TGAutorotationLock` object;
  creation is idempotent, release is `nil`-ing the strong reference.

`restrictLandscape = true` is set on the login stack (`TGAppDelegate.mm:110`) and on the three
media-viewer stacks (`TGTelegraphProfileImageViewCompanion.mm:427`, `TGProfileController.m:3220`,
`TGTelegraphConversationProfileController.mm:1987`) — the last three then *acquire* the rotation lock
too (`TGTelegraphProfileImageViewCompanion.mm:404, 453, 461`), i.e. lock first, then unlock into a
free-rotating image viewer.

## 10. Bar hide/show

`setNavigationBarHidden:animated:` (`.m:233-245`): force `navigationBar.alpha = 1` when showing
(UIKit sometimes leaves it faded), tell the bar `setHiddenState:animated:`, call super, and if the
value actually changed call `resetBarStyle`.

`TGNavigationBar setHiddenState:animated:` (`.m:355-396`): when animating a real change, it inserts a
temporary black `_statusBarBackgroundView` of frame `(0, -self.frame.origin.y, width, 20)` —
20 pt, the status bar height, positioned to cover the status bar area regardless of where the bar has
slid to — then animates `_shadowView.alpha` and `_progressView.alpha` to 0/1 over **0.3 s** and
removes the black patch on completion. `setFrame:`/`setCenter:` keep the patch aligned while the bar
moves (`.m:335-353`). Without this patch, sliding the bar away exposes the window behind the status
bar for the duration of the animation.

---

## 11. Behaviour with unusual content

- **No `titleView` on the outgoing controller during push**: `titleViewWidth` stays 0
  (`.m:273-280`), so the incoming back button starts from the exact screen centre instead of from the
  old title. Nothing breaks; the slide is just longer.
- **No `titleView` on the destination during pop**: the outgoing back button falls back to
  `screenWidth / 4` (`.m:366`) instead of a computed title centre.
- **No `leftBarButtonItem` on the destination during pop**: the title animation is skipped entirely
  (`.m:387`).
- **A left item whose custom view does not adopt `TGBarItemSemantics`, or answers `backSemantics`
  false**: no custom animation, UIKit's default crossfade applies. This is the common case — only the
  chat and web screens opt in.
- **Empty stack**: `popToRootViewControllerAnimated:` guards `count != 0` (`.m:517`);
  `popViewControllerAnimated:` computes a nil `previousController` when depth < 2 (`.m:449`) and the
  appearance defaults then apply.
- **`backgroundView` without the two tagged subviews**: the pattern slide is skipped silently
  (`.m:325`, `.m:423`) — the background just sits still.
- **Very long titles**: the controller does nothing about them. Truncation is entirely the
  `titleView`'s problem; the bar only centres it (and only on iOS 7, §4).

---

## 12. Our port — comparison and verdict

**We have no equivalent class.** `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src` contains no
navigation-controller subclass and no navigation-bar subclass; everything is stock
`UINavigationController` plus per-bar styling from `TGTheme`
(`src/TGTheme.h:108-109`, `src/TGTheme.m:442-474`). Instances are created in
`src/RootViewController.m:32-41` (three, one per tab) and `src/AppDelegate.m:214-215` (login).

What we get right:

- **Bar background artwork is a faithful port.** `images/NavBarBackground@2x.png` is 88×88 px, the
  same dimensions as the original `Header_Corners@2x.png`, and
  `src/TGTheme.m:468-474` applies exactly the original's `UIEdgeInsetsMake(0, 8, 0, 8)`
  (matching `TGNavigationBar.m:93`). Correct — leave it alone.
- We do ship `NavigationBar_Corners@2x.png` (24×10 px) and use it in
  `src/TGMediaViewController.m:801` and `src/TGStoriesViewController.m:2112`. That asset exists in
  the original resources too but is referenced nowhere in the original code — our use is an
  invention, not a port. Not wrong, just uncited.

Differences a user can see, most significant first:

1. **Container topology is inverted.** Original: one `TGNavigationController` is the window's root
   and `TGMainTabsController` is its *root view controller* (`TGAppDelegate.mm:295-305`), so pushing
   a chat pushes onto the outer stack and the tabs go away as a whole screen. Ours: a tab bar
   controller owns three separate `UINavigationController`s (`src/RootViewController.m:24-44`) and we
   hide a custom tab bar manually on push (`src/RootViewController.m:86-89`). Visible consequences:
   each tab keeps its own back stack across tab switches (the original had a single stack), and the
   push animation slides the tab bar's contents rather than the whole tabs screen. Changing this is
   surgery; if we keep our topology, that is a deliberate deviation and should be recorded as one,
   not left implicit.
2. **No 1 pt header shadow.** The original hangs `HeaderShadow.png` (2×1 pt) one pixel below the bar
   with `clipsToBounds = false` (`TGNavigationBar.m:138-144`). We ship no `HeaderShadow` asset at all
   (`images/` has only `HeaderLoginShadow@2x.png` and `LoginShadow@2x.png`). Fix: add the 4×2 px
   asset, and since we cannot subclass without one, place a 1 pt image view at
   `(0, 44, width, 1)` in the bar with `bar.clipsToBounds = NO`, autoresizing
   `FlexibleWidth | FlexibleTopMargin`.
3. **No landscape bar background.** `src/TGTheme.m:472-473` sets the background image only for
   `UIBarMetricsDefault`. The original swaps to `Header_Corners_Landscape.png` (32 pt tall) whenever
   `bar.frame.size.width > 400` (`TGNavigationBar.m:171-180`). In landscape our 44 pt-tall artwork is
   squeezed into the 32 pt bar. Fix: also call
   `setBackgroundImage:forBarMetrics:UIBarMetricsLandscapePhone` with a 64×64 px asset carrying the
   same 8 pt caps.
4. **No black slab and no bottom black-corner strip.** `TGNavigationController.m:55-68`. On our root
   stacks the window shows through at the top during transitions, and the 4 pt
   `BlackCornersBottom` footer is entirely absent. Both are cheap to add in
   `src/RootViewController.m` after the nav controllers are built; note the corners strip is added
   unconditionally and the slab only for root (non-modal) stacks.
5. **No bar-item choreography on push/pop.** None of §6/§7 exists in our port; we get UIKit's plain
   crossfade. The most noticeable loss is the chat screen's back button, which in the original flies
   in from where the previous title was over 0.35 s. If we implement anything from this document
   beyond the artwork, implement this: it is the single most recognisable motion of the 2013 client.
6. **No tap-the-header action and no swipe-down on the bar.** `TGNavigationBar.m:514-533, 585-595`
   plus the `HeaderActionOverlay` art. We ship neither the asset nor the behaviour.
7. **No 16 pt left hit-test slop on bar buttons** (`TGNavigationBar.m:535-542`). Our back button is
   measurably harder to hit near the left edge than the original's.
8. **No appearance protocol.** We have no `TGViewControllerNavigationBarAppearance` equivalent: bar
   hiding is done ad hoc from inside screens (`src/TGCountryPickerViewController.m:530, 618`) and the
   status-bar style is never coordinated with the bar. The original centralised all four decisions
   (bar hidden, bar style, status bar hidden, status bar style) in one place per transition
   (`TGNavigationController.m:152-182`). Whether we need this depends on how many screens diverge; at
   two call sites today it is not yet urgent, but it is the correct shape.
9. **No stack hygiene.** Neither `TGNavigationControllerItem` nor `TGDestructableViewController`
   exists in our source (grep for `shouldBeRemovedFromNavigationAfterHiding` and
   `cleanupBeforeDestruction` returns nothing). Concretely: our login flow leaves its intermediate
   screens on the stack, and opening a chat from a notification can grow the stack without bound —
   both of which the original explicitly prevented (§8). This is the highest-value non-visual item
   here.
10. **`restrictLandscape` has no analogue.** The original pinned the login stack and the media-viewer
    stacks to portrait (`TGAppDelegate.mm:110`, `TGProfileController.m:3220` and the other two). Our
    login stack (`src/AppDelegate.m:214`) can rotate.

Do **not** port: `updateControllerLayout:` (dead, §2), `cornersImageView` (never assigned, §2),
`TGGestureNavigationController` (compiled out, §1), the iOS-7-only bar-item layout block
(`TGNavigationBar.m:246-283`, unreachable on 6.1.3), and `setBarStyle:animated:duration:` /
`updateBarStyle:` (unreachable, §4) unless we deliberately want the black-opaque bar the original
built but never used.

---

## 13. What became of it

### twelve (`/Users/alexanderhavrysh/Git/iOS/twelve`)

The class survived, moved to `submodules/LegacyComponents/LegacyComponents/TGNavigationController.{h,m}`,
and grew from 584 to **1034 lines**. The header (`TGNavigationController.h:1-48`) shows what the
extra 450 lines are for:

- `TGNavigationControllerPresentationStyle` (`.h:3-8`: Default / RootInPopover / ChildInPopover /
  InFormSheet) plus `parentPopoverController` and `detachFromPresentingControllerInCompactMode`
  (`.h:20-23`) — **forced by the iPad**, which the 2013 class did not consider at all.
- `displayPlayer` / `minimizePlayer` / `currentAdditionalNavigationBarHeight` /
  `forceAdditionalNavigationBarHeight` (`.h:25-31`) — **forced by a new feature**, the inline music
  player. `TGNavigationController.m:320` and `:345` fix the extra bar height at **37 pt** when the
  player is expanded and **2 pt** when minimised, and every child `TGViewController` is told about it
  (`.m:680-713`). The 2013 class had exactly one bar height and no concept of a bar that grows.
- `showCallStatusBar` (`.h:28`) — same story, the in-call green status bar.
- `shouldPopController` block (`.h:12`, used at `.m:788-789`) — a veto hook for "discard draft?"
  style confirmations, replacing nothing; the 2013 class had no way to refuse a pop.
- `isInPopTransition` / `isInControllerTransition` (`.h:17-18`) and heavy work on
  `interactivePopGestureRecognizer`: the recognizer is `object_setClass`-ed into a custom
  `TGNavigationPanGestureRecognizer` (`.m:139`, `.m:851`) with `delaysTouchesBegan = false`,
  `delaysTouchesEnded = true`, and a wrapped delegate (`.m:140-182`). This is the direct descendant
  of the abandoned `TGGestureNavigationController`: once iOS 7 shipped a real interactive pop, the
  fork stopped writing its own container and started bending UIKit's.
- `navigationBarClass:` parameters on the factory methods (`.h:34-35`) — the 2013 class hardcoded
  the bar class in a nib; the fork needed several bar classes and had to parameterise it.
- `blackCorners:` is **gone** from the header entirely. The black slab and the
  `BlackCornersBottom` strip were skeuomorphic scaffolding for a translucent-black-bar world; iOS 7's
  flat opaque bars made them meaningless.

`TGNavigationControllerItem` survives verbatim (`twelve .h:50-60`, same two selectors) — the
self-removing-controller idea was durable. `TGBarItemSemantics` does **not** survive: once the
back button was UIKit's own again, there was nothing to choreograph.

### Telegram-iOS (`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS`)

`submodules/Display/Source/Navigation/NavigationController.swift`, **2033 lines**, still nominally a
`UINavigationController` subclass (`:148 open class NavigationController: UINavigationController,
ContainableController, UIGestureRecognizerDelegate`) but only to satisfy UIKit; the real work happens
in its own container tree. The concepts that replaced ours:

- `NavigationControllerMode` (`:51-54`: `.single` / `.automaticMasterDetail`) and
  `RootContainer` (`:61-64`: `.flat(NavigationContainer)` / `.split(NavigationSplitContainer)`) —
  the iPad split view that twelve bolted on as a presentation-style enum is now the primary axis of
  the design.
- `NavigationControllerTheme` (`:11`) and `NavigationStatusBarStyle` (`:6`) — the 2013 class read
  appearance off the top controller one property at a time through an Objective-C protocol; the
  modern one passes a theme object down. Same idea, better plumbing.
- Everything is funnelled through `updateContainers(layout:transition:)` (`:492`) with a
  `ContainedViewLayoutTransition`, called from ~20 sites. There is no equivalent of our per-property
  `if (a != b) animate` guards; layout is recomputed wholesale and the transition object decides
  whether it animates. Durations are named and spring-based (`.animated(duration: 0.5, curve:
  .spring)` at `:1704`, `0.4/.spring` at `:1736`, `0.3/.easeInOut` at `:204`) rather than the 2013
  file's literal 0.35/0.355/0.4.
- `MasterDetailLayoutBlackout` (`:56-59`) and a `GlobalOverlayContainerParent` with a custom
  reversed-subnode `hitTest` (`:66-77`) — the modern client's answer to the same class of problem the
  2013 bar solved with its `point.x - 16` hack: hit testing that does not follow the view hierarchy.

Read as a thirteen-year arc: the *style synchronisation* idea (top controller declares, container
applies) survived and got formalised into themes; the *destructive stack management* idea survived
verbatim into twelve and then into the modern router; the *hand-animated bar items* died the moment
UIKit's own transitions became good enough; and the *chrome painting* (black slab, corner strips,
1 pt shadow) died with skeuomorphism. For our purposes only the last group is what we are actually
trying to resurrect, and it is precisely the group the later code deleted — so there is no later
version to crib from. The 2013 file is the only reference for it.

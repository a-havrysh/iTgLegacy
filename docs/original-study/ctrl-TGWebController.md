# TGWebController — the 2013 in-app browser

Source of truth:
- `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGWebController.h` (15 lines)
- `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGWebController.m` (809 lines)

Line references below are into those two files unless another path is named.

---

## 1. What it is for

`TGWebController` is Telegram's own web browser, embedded in the app. In 2013 there was no
`SFSafariViewController` (that arrived with iOS 9), so tapping a link in a chat did not leave
Telegram — it pushed a full-screen `UIWebView` onto the same navigation stack the chat lived on,
with a custom navigation bar that hides on scroll and a custom bottom toolbar of six chrome buttons.
It is a `TGViewController` subclass (`.h:11`) with exactly one public method:

```objc
- (id)initWithUrl:(NSString *)url;   // .h:13
```

That is the entire public surface. Everything else — title, toolbar, activity spinner, action
sheet — is private and driven by the web view's own delegate callbacks.

### Its single call site

`Telegraph/Telegraph/TGApplication.m:34`. `TGApplication` is a `UIApplication` subclass that
overrides `openURL:`; every link tap in the app funnels through it. The routing rules there
(`TGApplication.m:15-40`) are the real contract:

- `tel:` and `facetime:` are handed to `TGAppDelegateInstance performPhoneCall:` (`:18-22`).
- Anything whose absolute string does not begin `http://` or `https://` sets `useNative = true`
  and goes to `[super openURL:]`, i.e. out to the system (`:26-30`).
- Everything else — plain http/https — constructs `TGWebController` and **pushes** it onto
  `TGAppDelegateInstance.mainNavigationController` animated (`:34-36`).
- `openURL:forceNative:` with `forceNative = YES` bypasses the in-app browser entirely; that is
  the escape hatch the browser's own "Open in Safari" uses.

So the design intent is unambiguous: **http/https never leaves the app**, everything else always
does. It is a push, not a modal — the chat's own back-stack semantics apply.

---

## 2. Construction (`.m:62-80`)

```objc
self.automaticallyManageScrollViewInsets = false;   // :67
NSURL *nativeUrl = [[NSURL alloc] initWithString:url];
_url = [NSString stringWithFormat:@"%@:%@", nativeUrl.scheme, nativeUrl.resourceSpecifier]; // :70
_displayUrl = [[_url lowercaseString] hasPrefix:@"http://"]
    ? [nativeUrl.resourceSpecifier substringFromIndex:2]   // :71
    : _url;
```

Two derived strings, and the distinction matters visually:

- `_url` is the URL rebuilt from scheme + resourceSpecifier. This is a normalisation pass — it
  survives round-tripping through `NSURL` and is what actually gets loaded (`:197`).
- `_displayUrl` is the *pre-title* shown in the navigation bar while the page is still loading.
  For `http://` URLs it strips the scheme **and the two slashes** (`substringFromIndex:2` applied
  to the resourceSpecifier `//example.com/x`, giving `example.com/x`). For `https://` it does
  **not** strip anything — the prefix check is only against `http://` — so an https page shows
  the full `https://example.com/x` in the bar until the page title arrives. That asymmetry is in
  the original and looks like an oversight, but it is what shipped.

The initialiser also creates `_customNavigationItem` (`:73`), computes the initial navigation-bar
visibility from the current orientation (`:75`), and hides the real navigation bar (`:77`).

**`automaticallyManageScrollViewInsets = false` is load-bearing.** This controller does all of its
own inset arithmetic in `adjustScrollViewContentInset:` (`:452-472`); if the base class also tried,
the web view would be double-inset.

---

## 3. The two navigation bars

This is the single cleverest and least obvious thing in the class. There are **two** navigation
bars and **two** title labels held in parallel:

| Real (system) | Custom (owned by this controller) |
|---|---|
| `self.navigationController.navigationBar` | `_customNavigationBar` (a `TGNavigationBar`, `.m:154`) |
| `self.navigationItem` | `_customNavigationItem` (`.m:73`) |
| `_genericNavigationView` + `_genericTitleLabel` | `_customNavigationView` + `_customTitleLabel` |

Why: the real navigation bar cannot be moved independently of the push animation, and this screen
wants the bar to slide away under a finger drag (Mobile Safari's behaviour, new and desirable in
2013). So the controller lets the *real* bar carry the title during the push transition, and then
at `viewDidAppear:` swaps to its own free-floating copy:

```objc
- (void)viewDidAppear:(BOOL)animated {
    [self setNavigationBarHidden:true animated:false];   // :347
    [super viewDidAppear:animated];
}
```

The real bar goes away unanimated at the exact instant the push finishes; `_customNavigationBar`
has been sitting underneath it since `loadView`, so the user sees no change. `performBackAction`
(`:476-488`) reverses the trick: if the custom bar is still parked at its home position, the real
bar is un-hidden and the custom one is zeroed to alpha 0 *before* the pop, so the pop transition
again animates a real bar. If the custom bar has been scrolled away, the swap is skipped and the
page pops with no bar — matching what the user was looking at.

Both title labels are created identically by `_createCustomTitleLabel` (`:89-103`) and are kept
byte-identical in text and frame (`:146-147`), which is what makes the handoff invisible.

### Title label metrics (`.m:89-148`)

`TGLabel` with `backgroundColor = clearColor` (`:92`) and, from
`TelegraphKit/TelegraphKit/TGViewController.mm`:

- portrait font: **bold system 20 pt** (`TGViewController.mm:85`)
- landscape font: **bold system 17 pt** (`TGViewController.mm:92`)
- text colour: **`#ffffff`** for `TGViewControllerStyleDefault` (`TGViewController.mm:139`)
- shadow colour: **`#3d5c81`** (`TGViewController.mm:157`)
- shadow offset: **`(0, -1)`** (`TGViewController.mm:173`)

`TGLabel` swaps font itself on rotation because both `portraitFont` and `landscapeFont` are set
(`:94-97`); the initial `font` is picked manually from the current orientation on `:97`.

Layout in `setTitleText:forOrientation:` (`:126-148`):

1. Frame is reset to `CGRectMake(0, 0, 480, 44)` then `sizeToFit` (`:137-138`). The 480 is the
   long side of a 3.5"/4" screen — a "wide enough for anything" sizing box, not a real bound.
2. Width is clamped to `screenSize.width - 72*2` (`:140-141`). **72 pt is the reserved gutter on
   each side** — enough for the "Back" button on the left and the activity spinner on the right.
   On a 320-wide screen that leaves **176 pt** of title. On a 4S in landscape (480 wide) it leaves
   **336 pt**. Longer titles are simply truncated by the label's default `lineBreakMode`; there is
   no marquee and no two-line fallback.
3. `origin.x = floorf((2 - width) / 2)` (`:142`). The container view is only 2×2 points
   (`:120`, `:128`) — a deliberately degenerate `titleView` so UIKit centres *it* and the label
   overhangs symmetrically on both sides. That is the trick that lets the title be wider than a
   `titleView` UIKit would otherwise squeeze.
4. `origin.y = -12` (`:143`). Because the container is 2 pt tall and centred in a 44 pt bar, the
   label has to be pulled up 12 pt to land on the bar's optical baseline.

If a caller sets the title before either label exists, both are lazily created (`:112-116`), so
`setTitleText:` is safe at any point including `loadView` (`:166`).

---

## 4. `loadView` in order (`.m:150-323`)

The subview z-order is the order of `addSubview:` and it matters:

1. `_webView` (`:185`) — bottom.
2. `_overlayBackButton` (`:210`).
3. `_minimizeOverlayButton` (`:223`), alpha 0.
4. `_toolbarView` (`:237`).
5. `_customNavigationBar` (`:322`) — top, so it floats *over* the web content as it slides.

Notable details:

**Custom bar initial frame** `CGRectMake(0, 20 + 44, width, portrait ? 44 : 32)` (`:154`). The
`20 + 44` is status bar plus real navigation bar — it starts parked below the real bar and is
moved to its true position by `controllerInsetUpdated:` (`:443`), which sets it to
`(0, controllerStatusBarHeight, width, 44)`. Note the height there is a flat 44 even in landscape,
contradicting the `: 32` in the initial frame. The landscape 32 never survives the first inset
update, so effectively **the custom bar is always 44 pt tall**.

**Back button** (`:158-164`): a `TGToolbarButton` of type `TGToolbarButtonTypeBack`, text from
`NSLocalizedString(@"Common.Back")`, `sizeToFit`, wrapped in a `UIBarButtonItem` and set as the
custom item's left item. The magic `tag = 0x263D9E33` (`:159`) is how the navigation machinery
recognises "this is the back button" elsewhere.

**Audio session** (`:170-181`): a `dispatch_once` that sets `AVAudioSessionCategoryPlayback`. Set
here, once per app lifetime, so that HTML5 `<video>`/`<audio>` inside the page plays with sound.
Never reverted. This is a real behavioural side effect of ever opening a link: after the first web
page, the app's audio category is Playback for good.

**Web view** (`:183-192`): fills `self.view.bounds`, both autoresizing masks, `scalesPageToFit =
true` (`:190`). The web view's own scroll view delegate is *stolen* — `_webViewScrolDelegate` keeps
the original (`_webView` itself) and the controller becomes the delegate (`:188-189`). Every
zoom-related callback is then manually forwarded back (`:606-638`), because breaking those breaks
pinch-to-zoom. Only `scrollViewDidScroll:` / `WillBeginDragging` / `DidEndDragging` /
`ShouldScrollToTop` are consumed without forwarding.

**`TGHacks setWebScrollViewContentInsetEnabled:`** (`:192`, `:468-471`): a swizzle gate. `TGHacks`
swizzles `UIWebView`'s scroll view's `setContentInset:` and `setScrollIndicatorInsets:`
(`TGHacks.m:336-359`) so that any inset write is *dropped* unless an associated-object flag is set
(`TGHacks.m:712-725`). `UIWebView` resets its own insets constantly during layout; this lets the
controller be the only thing allowed to write them. The pattern is always: enable → set both
insets → disable (`:468-471`).

**Overlay back button** (`:199-210`), the landscape-only floating Back chip:
- `BackButton_Overlay.png` and `BackButton_Overlay_Highlighted.png`, both stretched with
  `stretchableImageWithLeftCapWidth:15 topCapHeight:0` (`:199-200`). Assets are 55×62 @2x, i.e.
  **27.5 × 31 pt** — the 15 pt left cap is the arrow head, everything right of it tiles.
- white text, shadow `UIColorRGBA(0x000000, 0.3f)` (`:202`).
- `backSemantics = true`, `paddingLeft = 15`, `paddingRight = 9` (`:203-205`). The asymmetric
  padding is because the arrow eats space on the left.
- Text is the **hardcoded English `@"Back"`** (`:206`) — unlike the navigation-bar back button on
  `:160` which is localised. That is a genuine bug in the original; port the localised string.
- Positioned by `CGRectOffset(frame, 4, 28)` (`:209`), so x = 4, y = 28. `controllerInsetUpdated:`
  later moves y to **8 when maximised in landscape, 28 otherwise** (`:445`).
- Hidden whenever the orientation is portrait (`:369`) — in portrait the real bar has a Back button
  already.

**Minimize overlay button** (`:212-225`): `BrowserMinimize.png` (60×60 @2x = **30×30 pt**), pinned
to the **bottom-right with a 5 pt margin on both edges** (`:215`), autoresizing
`FlexibleLeftMargin | FlexibleTopMargin`. `adjustsImageWhenDisabled/Highlighted = false` and
`exclusiveTouch = true` (`:217-219`) — the highlight comes from an explicit highlighted asset, not
UIKit's automatic dimming, which is the house style for every button on this screen. Starts at
alpha 0 (`:225`); only visible when maximised in landscape (`:447`).

**Toolbar** (`:227-237`): a plain `UIView`, 44 pt tall, pinned to the bottom.
- `BrowserFooterShadow.png` (8×2 @2x = **4×1 pt**) sits *above* the toolbar at
  `y = -height` (`:229`), full width, `FlexibleWidth`. A 1 pt drop shadow line.
- `_toolbarBackgroundView` fills the toolbar with **`BrowserFooter.png` in portrait,
  `BrowserFooter_Landscape.png` in landscape** (`:235`). The assets are 8×88 @2x and 6×64 @2x —
  4 pt wide, **44 pt** and **32 pt** tall respectively. They are vertical-gradient strips stretched
  horizontally by `FlexibleWidth`, which is why the landscape variant is a separate file: the
  gradient has to be recomputed for the shorter bar, it cannot just be squashed.

**Toolbar buttons** (`:239-311`): six, all built identically from a normal + `_Highlighted` pair,
all `adjustsImageWhenDisabled = false`, `adjustsImageWhenHighlighted = false`,
`exclusiveTouch = true`, sized from the image:

| Property | Asset | Action | Notes |
|---|---|---|---|
| `_backButton` | `BrowserFooterBack.png` | `goBack` (`:704`) | 46×44 @2x = **23×22 pt** |
| `_forwardButton` | `BrowserFooterForward.png` | `goForward` (`:709`) | same size |
| `_reloadButton` | `BrowserFooterRefresh.png` | `reload` (`:719`) | **starts at alpha 0** (`:284`) |
| `_stopButton` | `BrowserFooterStop.png` | `stopLoading` (`:714`) | shares `_reloadButton`'s frame exactly (`:391`) |
| `_actionButton` | `BrowserFooterActions.png` | action sheet (`:722`) | |
| `_maximizeButton` | `BrowserFooterMaximize.png` | `maximizeButtonPressed` (`:735`) | **frame taken from `actionImage.size`, not `maximizeImage.size`** (`:304`) — a copy-paste slip; harmless only because both assets are 46×44 |

Reload and Stop are the same button visually — one crossfades into the other, they never coexist.
Reload starts invisible because the initial load is already in flight.

**Activity indicator** (`:313-320`): `UIActivityIndicatorViewStyleWhite`, alpha 0 and hidden, put
inside a container **4 pt wider than the spinner** (`:316`) so it does not butt against the screen
edge, and installed as the *custom* item's right bar button. It is started immediately (`:320`).

---

## 5. Layout maths

### `updateViewLayout:` (`:367-398`)

```objc
float toolbarHeight = portrait ? 44 : 32;                                    // :371
_toolbarView.frame = CGRectMake(0,
    view.height + ((landscape && _maximizeInLandscape) ? 0 : -toolbarHeight),
    view.width, 44);                                                          // :373
```

Note the frame *height* is a constant 44 while the *offset* uses 32 in landscape. So in landscape
the toolbar is 44 pt tall but hangs 12 pt off the bottom of the screen — only its top 32 pt are
visible. That is intentional: the buttons are laid out against `toolbarHeight` (32), and the
background image is the 32 pt landscape asset stretched over 44, so the extra 12 pt is off-screen
gradient. When maximised in landscape the whole thing is pushed fully off-screen (offset 0).

Button spacing (`:377-397`):

```objc
buttonSize = _backButton.frame.size;            // 23 × 22
padding    = 10;
buttonCount = portrait ? 4 : 5;
spacing = floorf((toolbarWidth - buttonSize.width*buttonCount - padding*2) / (buttonCount - 1));
y = floorf((toolbarHeight - buttonSize.height) / 2 - 1);
```

Read that carefully. In **portrait** `buttonCount = 4` — back, forward, reload/stop, action — and
the maximize button is laid out *anyway*, at a fifth slot which falls off the right edge of the
screen. Maximize is a landscape-only affordance and this is how it is hidden: not by `hidden`, but
by being positioned past the screen. In **landscape** `buttonCount = 5` and all five slots fit.

Concrete portrait numbers on a 320 pt screen: `spacing = floor((320 - 23*4 - 20) / 3) =
floor(208/3) = 69`. Button y = `floor((44 - 22)/2 - 1) = 10`. The `-1` is an optical nudge: the
glyphs sit slightly high in their 22 pt boxes.

### `adjustScrollViewContentInset:` (`:452-472`)

The web view is **not** inset-positioned; instead the frame is grown upward and the top content
inset compensates. That is the only way to get the page to scroll *under* the translucent
navigation bar while still starting below it:

```objc
barHeight = portrait ? 44 : 0;                                                // :458
webViewFrame.origin.y = (landscape && maximized) ? 0
                        : controllerStatusBarHeight + barHeight;               // :460
scrollInset.top       = webViewFrame.origin.y;                                 // :462
webViewFrame.size.height += webViewFrame.origin.y;                             // :463
webViewFrame.origin.y = 0;                                                     // :464
```

So the web view always starts at y = 0 and is full height; the top inset does all the work.
Bottom inset is `44` portrait / `32` landscape, or `0` when maximised, floored by
`self.controllerInset.bottom` (`:454-456`). In landscape the top inset is just the status bar
height, because the custom navigation bar is hidden in landscape.

---

## 6. States

### Loading state

Driven entirely by the three `UIWebViewDelegate` callbacks; all three animate over **0.2 s**.

- `webViewDidStartLoad:` (`:490-503`) — spinner un-hidden and started, then animate
  spinner alpha → 1, stop → 1, reload → 0.
- `webViewDidFinishLoad:` (`:505-528`) — the reverse; on completion the spinner is hidden and
  stopped (only if `finished`, so an interrupted animation leaves it spinning invisibly rather
  than flickering). Then the title is read from JS.
- `webView:didFailLoadWithError:` (`:530-559`) — identical chrome reset, then title recovery, then
  the error alert.

### Title state machine

```objc
NSString *pageTitle = [self.webView stringByEvaluatingJavaScriptFromString:@"document.title"]; // :521
bool fadeIn = self.titleText.length == 0 || [self.titleText isEqualToString:@" "];             // :522
[self setTitleText:pageTitle];
if (fadeIn) [self fadeInTitleText];                                                            // :525
```

**Two original defects worth knowing before you copy this.** `TGWebController` overrides
`setTitleText:` (`:105-108`) *without calling super*, so `TGViewController`'s backing `_titleText`
(`TGViewController.mm:437-440`) is never assigned. Consequences:

1. `self.titleText` is permanently `nil`, so `fadeIn` on `:522` is **always true** — every page
   load fades its title in, even a same-site navigation where the bar already had a title.
2. `fadeInTitleText` (`TGViewController.mm:428-435`) animates `_titleLabel`, the *base class's*
   label — which was never created here, because `setTitleText:forOrientation:` installs its own
   `_genericTitleLabel` into `navigationItem.titleView` instead (`:123`). So the fade is a no-op
   on a nil object. The title snaps in, it does not fade.
3. `updateWebInterface`'s guard `![self.titleText isEqualToString:pageTitle]` (`:575`) compares
   against nil and is therefore always true — the title is re-set on every call.

None of these are visible as breakage, which is presumably why they shipped, but they mean **the
intended behaviour (fade the title in on first load only) never actually happened in the shipping
app**. If you reimplement, decide deliberately which you want. My recommendation: implement the
intent — fade on first title only — because it is clearly what the author meant.

Fallback when a page has no title and fails: `pageTitle` falls back to `_displayUrl` (`:547-548`)
in the failure path only. In the *success* path there is no fallback — a successfully loaded page
with an empty `<title>` sets the bar title to the empty string, and the bar goes blank. Real
behaviour, easy to hit with a bare image URL.

### Error state (`:552-556`)

```objc
if (error.code == -999) return;   // NSURLErrorCancelled — user hit Stop or navigated away
UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:nil
    message:TGLocalized(@"Web.Error")
    delegate:nil cancelButtonTitle:NSLocalizedString(@"Common.OK", nil) otherButtonTitles:nil];
```

Strings (`Telegraph/Telegraph/en.lproj/Localizable.strings:525-527`):

```
"Web.Error"        = "Couldn't load page";
"Web.OpenExternal" = "Open in Safari";
"Web.CopyLink"     = "Copy Link";
```

Title-less alert, one OK button, no retry. The page stays as whatever it was — there is no error
page rendered into the web view.

### Maximize / minimize (`:735-780`)

A landscape-only fullscreen mode, `_maximizeInLandscape`. Both transitions animate over **0.3 s**
and both drive the same two methods (`updateViewLayout:` + `controllerInsetUpdated:`) inside the
animation block, which is what makes the toolbar slide off and the web view grow together. In
addition the status bar is faded and slid:

- maximize: `setApplicationStatusBarAlpha:0`, `statusBarBackgroundView.origin.y = -height`, and
  `animateApplicationStatusBarAppearance:TGStatusBarAppearanceAnimationSlideUp duration:0.3`.
- minimize: alpha 1, y = 0, `…SlideDown`.

The status-bar half only runs if currently landscape (`:744`, `:776`); the flag itself is set
unconditionally, so maximising in portrait (impossible via UI — the button is off-screen) would
still latch the flag for the next rotation.

`viewWillDisappear:` always restores `setApplicationStatusBarAlpha:1`, animated over 0.3 s if the
disappearance is animated (`:352-365`). Without this, leaving a maximised page would leave the
whole app with an invisible status bar.

### Rotation (`:400-418`)

Order matters: `adjustNavigationAppearanceAnimated:` → `updateViewLayout:` →
`controllerInsetUpdated:` → status bar → `setTitleText:forOrientation:` with the *incoming*
orientation, so the title is re-clamped to the new width before the rotation animation runs.

`adjustNavigationAppearanceAnimated:` (`:420-437`) is trivially "portrait shows the bar, landscape
hides it", implemented purely as an alpha change (`:435`) — the bar is never removed, so its frame
maths keeps working. The commented-out line on `:436` shows the author tried a slide animation and
abandoned it.

---

## 7. The scroll-to-hide navigation bar (`:640-698`)

This is the most characteristic behaviour of the screen and the part most worth getting right.

```objc
- (void)scrollViewWillBeginDragging:  // :655-663
    _draggingInProgress   = true;
    _draggingStartPosition = scrollView.contentOffset.y;
    _draggingStartOffset   = _customNavigationBar.frame.origin.y + 44;

- (void)scrollViewDidScroll:          // :640-653
    float scrollOffset = MIN(MAX(-44,
        -contentOffset.y - contentInset.top + _draggingStartPosition + _draggingStartOffset), 0);
    if (_draggingInProgress)
        _customNavigationBar.frame.origin.y = controllerStatusBarHeight + scrollOffset;
```

Read the algebra: the bar tracks the finger 1:1, clamped to the range **[-44, 0]** relative to its
home position at `controllerStatusBarHeight`. `_draggingStartOffset` records where the bar already
was when the drag began (+44 so that the fully-hidden state is 0 and the fully-shown state is 44),
so a drag that starts mid-hide continues from there rather than jumping. The bar only moves while
a finger is down — momentum scrolling does **not** move it, because of the `_draggingInProgress`
guard. That is a deliberate choice and it feels different from later implementations.

On release (`:665-683`) it snaps, over **0.3 s**, to whichever end is nearer, with the threshold at
**-22 pt, i.e. exactly half**:

```objc
if (frame.origin.y - controllerStatusBarHeight > -22)  frame.origin.y = controllerStatusBarHeight;
else                                                   frame.origin.y = controllerStatusBarHeight - 44;
```

`scrollViewShouldScrollToTop:` (`:685-698`) brings the bar back over 0.3 s and returns `true` — the
status-bar tap both scrolls the page up and restores the chrome.

Note the *toolbar* never hides on scroll. Only the top bar does.

---

## 8. Navigation policy (`:580-604`)

```objc
bool loadNative = false;
if (scheme is not "http" and not "https")            loadNative = true;   // :584-587
if (request.URL.host isEqual "itunes.apple.com")     loadNative = true;   // :589-590
if (loadNative && navigationType != UIWebViewNavigationTypeOther) {
    [(id<TGAppManager>)app.delegate openURLNative:request.URL];
    return false;                                                          // :592-597
}
```

Three rules worth transplanting verbatim:

1. Non-http(s) schemes inside a page (`mailto:`, `tel:`, `itms-apps:`, custom app schemes) bounce
   out to the system rather than erroring in the web view.
2. `itunes.apple.com` is special-cased so App Store links open the App Store app, not a web
   redirect chain.
3. The `navigationType != UIWebViewNavigationTypeOther` guard is the important safety valve.
   `UIWebViewNavigationTypeOther` covers sub-resource loads, JS-initiated navigation and iframes;
   without this check a page could fire arbitrary `openURLNative:` calls at the system with no user
   gesture. Only *user-initiated* navigation types are allowed to leave.

Anything else returns `true` and schedules `updateWebInterface` on the next main-queue turn
(`:599-602`) — async because `canGoBack`/`canGoForward` are not yet updated at the time the policy
delegate runs.

`updateWebInterface` (`:561-578`) sets `enabled` on back/forward and, crucially, sets **alpha 1.0
when enabled and 0.4 when disabled** (`:566-567`). Since `adjustsImageWhenDisabled` is off, that
alpha *is* the entire disabled appearance. 0.4 is the number.

---

## 9. Action sheet (`:722-733`, `:782-807`)

Built fresh on every tap, with the previous sheet's delegate nilled first (`:724`) so a stale sheet
cannot call back. No title, no destructive button, two options plus Cancel appended last and
recorded as `cancelButtonIndex` (`:730`). Shown with `showInView:self.view` — over the toolbar, not
from it.

- index 0 → "Open in Safari": takes `_webView.request.URL`, falls back to `_url` if it is nil or
  empty (`:791-793`), and calls `openURLNative:` — the `forceNative` path, so it does not
  re-enter this controller. **It exports the current page, not the page you arrived on.**
- index 1 → "Copy Link": reads `_webView.request.URL` with the same nil fallback (`:799-801`)…
  and then **copies `_url` regardless** (`:805`). The current-URL lookup is computed and thrown
  away. So Copy Link always yields the originally opened URL even after five navigations. That is
  a genuine original bug; the fallback logic on `:799-801` shows the intent was to copy the
  current URL. Fix it in our port.

---

## 10. Teardown (`:325-336`, `:82-87`)

`doUnloadView` nils the web view's delegate first, then the web view and every toolbar reference.
`dealloc` calls it and nils the action sheet's delegate. Not nilled: `_customNavigationBar`,
`_overlayBackButton`, `_minimizeOverlayButton`, `_toolbarBackgroundView`, `_maximizeButton`. Under
iOS 6 `viewDidUnload` semantics this is a partial teardown, but since `doUnloadView` is only
actually reached from `dealloc`, it does not leak in practice.

---

## 11. Our port: `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src`

**We do not have this component at all.** There is no `UIWebView` anywhere in `src/` — the only
files matching "web" are `TGClient+WebLinks.{h,m}`, `TGCapabilities.{h,m}` and `UIImage+WebP.{h,m}`.
Every link tap goes straight out to Safari:

- `src/TGChatViewController.m:5669-5675` (`openExternalLink:`) resolves the URL through
  `TGClient externalLinkForUrl:allowWriteAccess:completion:` and then calls
  `[[UIApplication sharedApplication] openURL:target]`.
- The same pattern appears at `src/TGStoriesViewController.m:3222` and `:3235`,
  `src/TGSettingsViewController.m:4182`, `src/TGQRViewController.m:396`,
  `src/TGMediaViewController.m:2961`, `src/TGProfileViewController.m:3381`,
  `src/TGChatViewController.m:5674` and `:767`.
- We have no `TGApplication` `openURL:` override, so there is no single choke point to add one at.

So the top-line user-visible difference is the largest possible one: **in the original, tapping an
http link kept you inside Telegram; in ours it ejects you to Safari and you have to use the iOS 6
app-switcher to get back.** On a 4S with 512 MB of RAM, coming back to Telegram frequently means a
cold relaunch. This is not a cosmetic gap.

### What we do have, and why it is not the same thing

`TGInstantViewController` — declared at `src/TGChatViewController.m:407` and implemented at
`:411-780`, inlined into the chat file rather than being its own class. It is a `UITableView` that
renders TDLib Instant-View *blocks* (`TGClient instantViewForUrl:completion:`, `:445`). It is the
modern Instant View feature, not a browser: it cannot render an arbitrary page, has no back/forward,
no reload, no address, and tapping any non-text block just calls `openURL:` out to Safari
(`:760-768`). It is only reachable via `openInstantView:` (`:5678-5684`) and only for pages TDLib
has an IV template for.

Its own visuals for reference: white background (`:420`), plain-style table with separators off
(`:434-436`), title = the URL's host or the literal `"Instant View"` (`:429-430`), a centred
`"Loading..."` placeholder at y = 120 in `#999999` (`:440-444`), and `"This article has no Instant
View."` when TDLib returns no blocks (`:456`).

### Differences a user could see, and what to do

Listing these as changes to make, since there is nothing to compare field-by-field:

1. **No in-app browser exists.** Build a `TGWebController` equivalent. `UIWebView` is available and
   correct on iOS 6.1.3; `WKWebView` is not (`src/TGCapabilities.m:24-26` correctly gates it at
   iOS 9). Push it, do not present it.
2. **No single URL choke point.** The original routes everything through one `UIApplication`
   subclass (`TGApplication.m:15-40`). Ours has eight scattered `openURL:` calls. Add the
   equivalent routing helper and funnel all eight through it, or the browser will only ever be
   reachable from chat.
3. **Our link action sheet is half of the original's.** `src/TGChatViewController.m:5655-5665`
   builds a sheet titled with the domain, offering "Open in Safari" / "Copy Link" / "Cancel" —
   the same two verbs as the original's `actionButtonPressed` (`:727-730`), but as a
   *pre*-navigation confirmation rather than as an in-browser action. Those are different sheets
   with different jobs. The original had a confirmation only implicitly (`shouldStartLoadWithRequest`
   gating); ours has a confirmation but no browser. When the browser lands, the confirmation sheet
   should keep its job and the browser gets its own action sheet.
4. **Strings are hardcoded English in ours** — `@"Open in Safari"`, `@"Copy Link"`, `@"Cancel"` at
   `src/TGChatViewController.m:5660-5663`. The original used `TGLocalized(@"Web.OpenExternal")`,
   `TGLocalized(@"Web.CopyLink")` and `NSLocalizedString(@"Common.Cancel")` (`:727-730`). Same
   English text, so no visible difference today, but the same drift as the original's own
   hardcoded `@"Back"` on `:206`.
5. **Artwork is not in our tree.** None of the nineteen `Browser*` / `BackButton_Overlay*` assets
   exist under `iTgLegacy` (the only `browser.h` hits are SDK headers). They are all present in
   `telegram-original-sources/.../Telegraph/Telegraph/Resources/` at @2x only, which is exactly the
   scale a 4S needs. Sizes are listed in §4 above.
6. **`TGHacks` exists in our tree** (`src/TGHacks.h`) but I did not verify it carries
   `setWebScrollViewContentInsetEnabled:`. If it does not, the swizzle from `TGHacks.m:336-359`
   and `:712-725` has to come across too, or `UIWebView` will fight every inset write and the page
   will jitter under the navigation bar.

### Things not to copy verbatim

Reimplement the *intent*, not the code, for four original bugs documented above:
`_displayUrl` not stripping `https://` (`:71`), Copy Link ignoring the current URL (`:805`), the
title fade that never fires (`:522-525`), and the hardcoded `@"Back"` (`:206`).

---

## 12. What became of it

### Modern client (`Telegram-iOS`)

The concept survived and grew enormously. `submodules/BrowserUI/Sources/` now holds 22 files:
`BrowserScreen.swift` is the container, and the single `UIWebView` has fanned out into four content
backends — `BrowserWebContent`, `BrowserInstantPageContent`, `BrowserPdfContent`,
`BrowserDocumentContent` — behind a common `BrowserContent` protocol. The chrome that was five
private properties here is now four components:
`BrowserNavigationBarComponent`, `BrowserToolbarComponent`, `BrowserAddressBarComponent`,
`BrowserTitleBarComponent`. New capabilities that did not exist in 2013 have their own files:
`BrowserBookmarksScreen`, `BrowserRecentlyVisited`, `BrowserAddressListComponent` (an address bar
with history autocomplete — 2013 had no address bar at all, only a read-only title),
`BrowserSearchBarComponent` (in-page find), `BrowserFontSizeContextMenuItem` and
`BrowserReadability` / `BrowserMarkdown` (reader mode),
`BrowserExceptionDomainAlertContentNode` (per-domain security exceptions).

Reading that list against the original tells you which 2013 decisions were *right* and which were
provisional:

- **Survived unchanged in spirit:** a bottom toolbar with back / forward / reload / share, a top
  bar that hides on scroll, links leaving the app only for non-http schemes, share-sheet with
  "Open in Safari" and "Copy Link".
- **Abandoned:** the maximize/minimize landscape mode, and with it `BrowserMinimize` and the
  floating overlay Back chip. Those existed because a 3.5" screen in landscape had almost no
  vertical room once you spent 20 pt on status bar, 44 on navigation and 32 on toolbar. Bigger
  screens killed the problem, so the feature went. This is a **forced** change (hardware), not
  taste — and it means we should *keep* it, because our target device is precisely the one that
  needed it.
- **Forced additions:** the address bar and bookmarks arrived once the in-app browser became
  people's actual browser rather than a link viewer; PDF/document backends arrived with file
  sharing; Instant Page rendering arrived with the IV format in 2016.

### `twelve` (later Obj-C fork)

`TGWebController` **did not survive** into `twelve` — there is no reference to it anywhere in that
tree. It was replaced wholesale by `SFSafariViewController`:

- `twelve/Telegraph/TGApplication.m:704` presents
  `[[SFSafariViewController alloc] initWithURL:url entersReaderIfAvailable:false]` — note
  **present**, not push, which is the opposite of the original's navigation model.
- `twelve/Telegraph/TGSafariViewController.h/.m` is a thin subclass adding
  `externalPreviewActionItems` for 3D-Touch peek, plus a compile-time shim
  (`#if __IPHONE_OS_VERSION_MAX_ALLOWED < 90000`) that fakes `SFSafariViewController` by simply
  calling `nativeOpenURL:` — i.e. on pre-iOS-9 builds, twelve degrades to exactly the behaviour our
  port currently has.
- `twelve/Telegraph/TGNotificationController.m:142` has to know whether an `SFSafariViewController`
  is on screen (`overInAppBrowser:`) to place its notification window — a hint of the integration
  cost of handing the browser to Apple.

That is the clearest signal for us: **Telegram only stopped maintaining its own browser when Apple
shipped one.** We are on iOS 6.1.3, Apple has not shipped one, and `twelve`'s own pre-iOS-9 shim
proves what the fallback looks like — the ejection-to-Safari behaviour we currently have. Building
`TGWebController` is not nostalgia; it is the only correct answer for this platform.

---

## 13. Ambiguities I could not resolve

- The `_maximizeButton` frame is built from `actionImage.size` (`:304`). Both assets are 46×44 @2x,
  so it is invisible — but I cannot tell whether that was known and tolerated or simply never hit.
- `_customNavigationBar`'s init frame says `portrait ? 44 : 32` (`:154`) while
  `controllerInsetUpdated:` unconditionally sets 44 (`:443`). The 32 is dead in every path I can
  trace, but I have not proven `controllerInsetUpdated:` always runs before first display.
- `_toolbarView`'s 44 pt height in landscape against a 32 pt background asset and 32 pt button
  layout: I read this as 12 pt hanging off-screen deliberately, but it could equally be an
  incomplete edit. The visible result is identical either way, so it does not affect the port.

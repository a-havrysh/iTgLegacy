# TGProgressWindow (original, Telegram for iOS v1.1 build 21024)

Sources studied, all read in full:

- `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGProgressWindow.h` (17 lines)
- `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGProgressWindow.m` (122 lines)
- Artwork: `Telegraph/Telegraph/Resources/ProgressWindowBackground@2x.png`, `Telegraph/Telegraph/Resources/ProgressWindowCheck@2x.png`

The class lives in TelegraphKit, not Telegraph. It exists under exactly this name; nothing had to be
substituted.

## What it is for

A blocking, app-modal "please wait" HUD. It is not a view that a controller inserts into its own
hierarchy — it is a whole `UIWindow` that the controller allocates on demand, shows, and drops. That
choice is the design: because it is a window at `UIWindowLevelStatusBar` (`TGProgressWindow.m:19`) it
covers the navigation bar, the status bar and any modally presented controller, and because it is
`userInteractionEnabled = true` while visible (`TGProgressWindow.m:43`) it swallows every touch in the
app for the duration. There is no cancel affordance and no text. The 2013 contract is: an operation
started, the user may not touch anything until it finishes, and when it finishes the HUD either
vanishes silently or flashes a checkmark.

## Public surface

```objc
@interface TGProgressWindow : UIWindow
- (void)show:(bool)animated;
- (void)dismiss:(bool)animated;
- (void)dismissWithSuccess;
@end
```
(`TGProgressWindow.h:11-17`)

There is no designated initializer of its own; callers use `-initWithFrame:` and, without exception,
pass `[[UIScreen mainScreen] bounds]` (e.g. `TGProfileController.m:3109`, `TGChatSettingsController.m:635`,
`TGConversationController.mm:8014`, `TGSelectContactController.m:158`,
`TGTelegraphConversationProfileController.mm:2772`, `TGLoginInactiveUserController.m:469`). Nothing
in the original ever creates one at a different size, so the interior layout was never exercised at
any other frame — see "unusual content" below.

## Construction and metrics

`-initWithFrame:` (`TGProgressWindow.m:14-39`) builds three objects:

1. **The window itself.** `windowLevel = UIWindowLevelStatusBar` (`:19`), `opaque = false` (`:36`).
   Note it never sets `backgroundColor`; a `UIWindow` created this way has a black default background
   in some configurations, but with `opaque = false` and no explicit background the original relies on
   the window being transparent outside the container. There is **no dimming layer** — the rest of the
   screen is not darkened. This is a real visual property, easy to get wrong: only the 100×100 plaque
   is visible, everything behind it stays at full brightness while being untouchable.

2. **`_containerView`**, exactly 100×100 points, centred with
   `floorf(width - 100) / 2` by `floorf(height - 100) / 2` (`:21`). Read the parentheses carefully:
   `floorf` is applied to `(width - 100)`, not to the halved result, so on an odd-width screen the
   origin can land on a half point. On the 4S (320×480, and 320×460 or 320×480 depending on the frame
   passed) both differences are even, so the origin is integral: x = 110, y = 190 for a 320×480 frame.
   Autoresizing is all four flexible margins (`:22`), which keeps it centred on rotation. It starts at
   `alpha = 0.0f` (`:23`) — the plaque is always faded in, never popped in.

3. **`backgroundView`**, a `UIImageView` filling the container's bounds (`:26`), whose image is
   `ProgressWindowBackground.png` turned into a stretchable image with
   `leftCapWidth = (int)(width / 2)`, `topCapHeight = (int)(height / 2)` (`:28`).
   The file on disk is @2x only, 32×32 pixels = **16×16 points**, so the caps are 8 points on each
   side and the stretched middle is a single point row/column. Effectively this is a rounded rectangle
   drawn by nine-part stretching rather than by `layer.cornerRadius`.

4. **`_activityIndicatorView`**, a stock `UIActivityIndicatorView` of style
   `UIActivityIndicatorViewStyleWhiteLarge` (`:31`) — 37×37 points on iOS 6 — offset by
   `(int)((100 - w) / 2)`, `(int)((100 - h) / 2)` (`:32`), i.e. truncated to integers: (31, 31) for a
   37-point indicator. It is started immediately in the initializer (`:34`) and spins for the whole
   lifetime of the window, whether or not the window is visible.

Note `#import "TGActivityIndicatorView.h"` at `TGProgressWindow.m:3` — the custom Telegram indicator
is imported but never used here. The HUD deliberately uses Apple's system spinner. Do not "upgrade"
ours to a custom one on the assumption that the import means something.

## Colours, measured from the artwork

I decoded both PNGs pixel by pixel rather than trusting an eyeball.

- `ProgressWindowBackground@2x.png` is 32×32, RGBA8. Every filled pixel is
  **RGB (0,0,0) with alpha 153/255 = 0.60**. So the plaque is pure black at 60 % opacity — not 70 %,
  not 80 %.
- The corners are anti-aliased quarter-circles. Reading the alpha ramp along the top-left corner, the
  fill reaches full 153 at (x=8,y=8) and the arc crosses the top edge at x≈11 px; the profile fits a
  circle of radius **12 px = 6 points** centred at (12,12) px. So: **6 pt corner radius**, black at
  60 %.
- `ProgressWindowCheck@2x.png` is 78×80 px = **39×40 points**, pure white (255,255,255) glyph on a
  fully transparent background. It is a bare checkmark, not a circled one, and it is not a
  square asset — 39 wide by 40 tall, which is why the centring code uses the image's own size rather
  than a constant.

There is no @1x variant of either file in `Resources/`, which is consistent with the app being
retina-only by then; on our 4S this is fine, but it means `imageNamed:@"ProgressWindowBackground.png"`
resolves through the @2x suffix rule and yields a 16×16-point image.

## Behaviour

### `show:` (`TGProgressWindow.m:41-55`)
Sets `userInteractionEnabled = true`, calls `makeKeyAndVisible`, then either animates
`_containerView.alpha` 0 → 1 over **0.3 s** with the default curve, or sets it directly. The window
becoming key is what steals the keyboard: showing the HUD over a chat resigns first responder from
the input field as a side effect. Several call sites depend on that implicitly.

No scale or spring animation — the 2013 HUD only cross-fades. (twelve later added a 0.6 → 1.0 scale;
see below. That is a later change of taste, and copying it would be wrong for our target look.)

### `dismiss:` (`:57-92`)
Disables interaction immediately (so the app is touchable again the instant dismissal starts, before
the fade completes), fades alpha to 0 over 0.3 s with `UIViewAnimationOptionBeginFromCurrentState` —
so a dismiss racing a still-running show picks up mid-fade instead of snapping. On completion (and
only `if (finished)`), it hides itself and then walks `[[UIApplication sharedApplication] windows]`
**backwards**, calling `makeKeyWindow` on every window that is not itself (`:71-76`). The loop does not
`break`, so the last one it touches is `windows[0]`, the main app window — the effect is "give key
back to the app window", implemented crudely. The non-animated branch (`:80-91`) does the same thing
synchronously.

The `if (finished)` guard is a real behavioural hazard: if the fade is interrupted (another animation
on the same view, app backgrounding), the window is never hidden and never gives up key, and since it
still sits at status-bar level with `userInteractionEnabled = false` it becomes an invisible, inert,
permanently-key window. The original never handles that; callers work around it by dropping their
strong reference (`_progressWindow = nil` right after every `dismiss:` — e.g.
`TGProfileController.m:4056-4057`, `TGSelectContactController.m:199-200`), letting ARC deallocate the
window and take it off screen.

### `dismissWithSuccess` (`:94-120`)
The success flourish. It **removes the spinner from the superview** (`:96`), disables interaction,
adds a `UIImageView` of `ProgressWindowCheck.png` centred with `floorf` on both axes (`:100`) — with a
39×40 image in a 100×100 box that is (30, 30) — and then fades the whole container out over 0.3 s
**after a 0.5 s delay** (`:103`). So the visible sequence is: spinner disappears and the checkmark
appears instantly in the same frame, holds for 0.5 s, then fades over 0.3 s. Total 0.8 s from success
to gone. There is no crossfade between spinner and check, and no animation on the checkmark itself.
Same key-window restoration in the completion block (`:112-117`), same `if (finished)` guard.

There is no `dismissWithFailure`. Failure is expressed by plain `dismiss:true` followed by a
`UIAlertView` — see `TGChatSettingsController.m:656-662`, which is the only call site in the whole app
that uses `dismissWithSuccess` at all (revoking other sessions). Everything else dismisses silently.

### States
Only three, and they are not modelled as an enum: hidden (alpha 0), spinning, and success. There is no
determinate-progress mode despite the name, no label, no cancel button, and no way to change the
content after construction.

### Unusual content, empty, missing
- **No text at all**, so no long-content case exists. The plaque is a fixed 100×100 square forever.
- **Missing artwork**: `imageNamed:` returning nil would make `stretchableImageWithLeftCapWidth:` be
  sent to nil (returns nil), giving an invisible plaque with a bare white spinner floating on the
  screen. Nothing guards this.
- **Double show / double dismiss**: unguarded in the original. `show:` twice restarts the fade;
  `dismiss:` twice runs two overlapping fades, and the second's `finished` may be NO, leaking the
  window as described. `TGConversationController.mm:8010-8022` is the only caller that guards, with a
  nil check on `_progressWindow`; the rest rely on their own state flags.
- **Rotation**: handled purely by the four flexible margins. The container never re-centres on a
  layout pass of its own.

## Call-site pattern (this is part of the component)

Every caller follows the same shape, and our port should too:

```objc
_progressWindow = [[TGProgressWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
[_progressWindow show:true];
... async work ...
[_progressWindow dismiss:true];
_progressWindow = nil;
```

Two variants exist. Controllers that can be asked twice keep it in a strong property and nil it out
(`TGProfileController.m:364, 3109-3110, 4056-4057`; `TGLoginInactiveUserController.m:469-470, 527-528`;
`TGTelegraphConversationProfileController.mm:2772-2773, 3519-3520`). Controllers doing a one-shot job
capture a local in the completion block instead (`TGConversationController.mm:2433-2434 / 2519`, and
`2652-2653 / 2669 / 2720`). The window keeps itself alive while visible only because it is retained by
the caller or the block — a `TGProgressWindow` with no strong reference is deallocated and disappears.

Places it is used: sending picked images, forwarding, deleting/leaving a conversation
(`TGConversationController.mm`), profile actions (`TGProfileController.m`), revoking sessions
(`TGChatSettingsController.m`), contact selection (`TGSelectContactController.m`), login/inactive-user
flows. It is the app's single generic "network round trip you must wait for" HUD.

## Our port: `TGContactsProgressWindow`

We have no `TGProgressWindow`. The only equivalent is a private class buried in one screen:
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGContactsViewController.m:73-129`, used twice, at
`:1413` (address-book import) and `:2742` (building the invite list). Every other screen that waits on
the network in our port has no HUD at all.

Differences a user can see:

1. **Wrong background colour.** Ours is `[UIColor colorWithWhite:0.0f alpha:0.7f]`
   (`TGContactsViewController.m:97`). The original is black at **0.60**, measured from
   `ProgressWindowBackground@2x.png`. Change 0.7 → 0.6.
2. **Wrong corner radius.** Ours sets `layer.cornerRadius = 16.0f` (`:98`). The artwork's radius is
   **6 points** (12 px @2x). 16 pt on a 100 pt square is a visibly different, much softer shape —
   this is the single most noticeable error. Either ship the two PNGs and use the stretchable-image
   path exactly as `TGProgressWindow.m:26-29`, or set `cornerRadius = 6.0f`.
3. **No success state.** We have no `dismissWithSuccess`, and `images/` contains no
   `ProgressWindowCheck@2x.png` (only `ListCheck@2x.png`, a different, smaller glyph). Port the
   39×40 white checkmark and the 0.5 s hold / 0.3 s fade from `TGProgressWindow.m:94-120`.
4. **Wrong window level.** Ours uses `UIWindowLevelStatusBar + 1.0f` (`:88`); the original uses
   `UIWindowLevelStatusBar` exactly (`TGProgressWindow.m:19`). Ours therefore also sits above other
   status-bar-level windows the app may add later; harmless today, but gratuitously different.
5. **Never becomes key, never restores key.** We do `window.hidden = NO` (`:110`) instead of
   `makeKeyAndVisible`, and the dismiss path (`:115-129`) has no key-window restoration loop. The
   visible consequence: showing our HUD does **not** dismiss the keyboard, whereas the original's does.
   If we ever show it over a screen with an active text field, the keyboard stays up behind the plaque.
6. **Dead dimming view.** `:90-92` adds a full-screen `dim` subview with `clearColor` that does
   nothing. Harmless, but it invites someone to "fix" it by darkening the screen — the original
   explicitly does not dim.
7. **Spinner centring differs in kind, not in result.** Ours sets `center = (50,50)` then
   `CGRectIntegral` (`:104-105`); the original truncates the offset with `(int)` (`:32`). For a 37 pt
   indicator both land at origin (31,31)-ish; `CGRectIntegral` rounds the origin down and the size up,
   so it can produce a 38-pt-wide frame and a half-point shift. Prefer the original's arithmetic.
8. **Not reusable.** The original is a TelegraphKit-wide component used by seven controllers. Ours is
   `static`-scope in one file with a contacts-specific name. It should be lifted into its own
   `TGProgressWindow.{h,m}` with the original's three-method surface, and adopted by the other screens
   that currently show nothing while blocking.

What ours gets right: the 100×100 container, the integer-floored centring, `WhiteLarge` system
spinner, the 0.3 s fade in and out, and the "drop the reference on dismiss" ownership model. The
guard against double-show (`if (self.window) return;`, `:81`) is an improvement over the original and
worth keeping.

## What became of it

**twelve** (`submodules/LegacyComponents/LegacyComponents/TGProgressWindow.{h,m}`) kept the class name
and the three-method surface, and even ships the original artwork under
`Telegraph/Resources/ClassicIOS6/ProgressWindowBackground@2x.png`. The changes are instructive:

- The window is now a shell around a `TGProgressWindowController : TGOverlayWindowViewController`
  (`TGProgressWindow.m:263-270` in twelve), because iOS 8+ needs a root view controller for rotation
  and status-bar appearance. Forced by the platform, not taste.
- The plaque became `clipsToBounds` + `layer.cornerRadius = 20.0f` (twelve `:45-46`) with a live blur
  or a flat fill (`UIColorRGBA(0xeaeaea, 0.92f)` light / `0x000000, 0.9f` dark, twelve `:67`), and a
  light/dark switch via `+setDarkStyle:` (twelve `:313-316`). Pure change of taste, tracking iOS 7+
  design. **Do not follow this**: it is exactly the flat-era look our project is trying not to have.
- The system spinner was replaced by `TGProgressSpinnerView`, 48×48 (twelve `:70`), which can
  *morph* into a checkmark (`[_spinner setSucceed]`, twelve `:236`). The 2013 hard-swap of spinner for
  static check became an animated transition, and the success hold grew 0.5 s → **0.55 s** (twelve
  `:177`).
- A 0.6 → 1.0 scale-up was added to `show:` (twelve `:89-95`).
- Two genuinely useful additions driven by real problems: `showWithDelay:` (twelve `:281-288`), so a
  fast request never flashes a HUD, and `_dismissed` / `_appeared` flags plus
  `skipMakeKeyWindowOnDismiss` (twelve `:246-248`, `:296-310`) that fix precisely the double-dismiss
  and key-window-stealing hazards described above. Also `dismissWithSuccess:` can now show the HUD from
  hidden (twelve `:201-237`) — success feedback for an operation that never showed a spinner.

**Telegram-iOS** wrapped the same idea in `OverlayStatusController`
(`submodules/OverlayStatusController/Sources/OverlayStatusController.swift:7-13`). The important
conceptual shift is the type enum: `loading(cancelled:)`, `success`, `shieldSuccess`,
`genericSuccess`, `starSuccess`. Two things the 2013 class lacked became first-class — a **cancel**
callback on the loading state, and **success variants that carry a text message**. That is feature
pressure, not taste: modern flows have long operations users must be able to abort, and successes that
need naming. The blocking-window mechanism itself survives underneath (`ProgressWindowController`,
`ProxyWindowController` are the ObjC descendants of this very file).

For us the lesson is narrow: keep the 2013 visual (60 % black, 6 pt radius, system spinner, static
checkmark, no dimming, no text), but borrow twelve's `_dismissed` flag and `showWithDelay:` because
they fix defects, not looks.

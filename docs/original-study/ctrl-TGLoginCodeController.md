# TGLoginCodeController — the activation-code screen (original, 2013)

Source of truth: `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGLoginCodeController.h`
(23 lines) and `.../TGLoginCodeController.m` (613 lines). Every line number below is in one of these two
files unless another path is named.

## 1. What it is

The second step of sign-in: a black, full-bleed screen with a single 80-point-wide white plate in the
middle of the space left above the keyboard, into which the user types a five-digit SMS code. It owns the
one-minute "Telegram will call you" countdown, the automatic voice-call fallback when that minute runs
out, and the branch into registration when the phone number turns out to be new.

It is a `TGViewController` subclass with `self.style = TGViewControllerStyleBlack` (`.m:75`), an
`ASWatcher` (ActionStage observer) and a `TGNavigationControllerItem` (`.h:15`).

### Public surface (`.h`)

- `@property ASHandle *actionHandle` (`.h:17`) — the ActionStage delegate handle, allocated in
  `init` with `releaseOnMainThread:true` (`.m:70`).
- `- (id)initWithShowKeyboard:(bool)showKeyboard phoneNumber:(NSString *)phoneNumber phoneCodeHash:(NSString *)phoneCodeHash` (`.h:19`).
  Note `showKeyboard` is `__unused` in the implementation (`.m:65`) — the keyboard is raised
  unconditionally in `viewWillAppear` (`.m:233`). The parameter is vestigial.
- `- (void)applyCode:(NSString *)code` (`.h:21`) — fills the field and immediately submits
  (`.m:452-456`). This is the hook for an out-of-band code delivery (push/other session).

The only call site in the whole tree is `TGLoginPhoneController.m:797`, which pushes it after the
`sendCode` request returns a `phoneCodeHash`. Nothing else constructs it, and
`shouldBeRemovedFromNavigationAfterHiding` returns `true` (`.m:95-98`), so it is discarded rather than
kept in the stack once the flow moves on.

## 2. View tree and every metric

Built entirely in `loadView` (`.m:100-200`); there is no nib. `self.view.opaque = false` (`.m:104`) — the
black login background is painted by the navigation container underneath, not by this controller.

### Title

`self.titleText = [TGStringUtils formatPhone:_phoneNumber forceInternational:true]` (`.m:106`). The title
is the phone number the code was sent to, always in international form, never a literal like "Enter code".

### Back button

Custom, not a system item: `BackButton_Login.png` / `_Pressed` / `_Landscape` / `_Landscape_Pressed`,
each `stretchableImageWithLeftCapWidth:15 topCapHeight:0` (`.m:108-111`). The asset is 62×60 px @2x, i.e.
31×30 pt, so the 15-pt left cap is one pixel short of half — the stretched region is the single column at
x=15. Installed through `setBackAction:` with `textColor` white and `shadowColor` `UIColorRGBA(0x050608, 0.4f)`
(`.m:113`). Action is `performClose`, which calls `[TGAppDelegateInstance resetLoginState]` **before**
popping (`.m:202-207`) — going back throws away the saved half-finished login, it is not a cheap
navigation.

### Next button

`TGToolbarButton` of type `TGToolbarButtonTypeDoneBlack`, text `Common.Next`, `minWidth = 52`, then
`sizeToFit` (`.m:115-118`). White title with shadow `UIColorRGBA(0x042651, 0.3f)`
(`TelegraphKit/TelegraphKit/TGToolbarButton.m:187, 195-197`). A
`TGActivityIndicatorView` of style `TGActivityIndicatorViewStyleSmallWhite` is added as a subview of the
button and centred inside it with `floorf((buttonSize - indicatorSize) / 2)` on both axes, hidden at
first (`.m:122-125`).

### Notice label (`_noticeLabel`)

- font `systemFontOfSize:14` (`.m:128`)
- colour `0xc0c5cc`, shadow colour `0x323c4a`, shadow offset `(0, 1)` (`.m:129-131`)
- centred, `numberOfLines = 0`, clear background (`.m:132-136`)
- text `Login.CodeHelp` = "We've sent an SMS with an activation code to your phone. Please enter the code below."
  (`Telegraph/Telegraph/en.lproj/Localizable.strings:177`)

Laid out by measuring `sizeThatFits:CGSizeMake(300, viewSize.height)` — **300 pt is the wrap width** — then
centred horizontally and placed so its bottom edge is 14 pt above the plate
(`.m:325-327`). The two-line English string at 14 pt is what the 14-pt gap and the 300-pt wrap were tuned
around; a longer localisation grows upward.

Overflow rule, and this is the interesting part: if the grown label would start above y=0 the label is not
clipped or shrunk, it is **faded out entirely** — `_noticeLabel.alpha = _noticeLabel.frame.origin.y < 0 ? 0.0f : 1.0f`
(`.m:329`). On a 3.5-inch screen in landscape there is simply no room, and the original chose to drop the
explanatory text rather than crowd the plate.

### Plate and code field

`LoginInput.png` (60×86 px @2x = 30×43 pt) stretched with
`leftCapWidth:(int)(rawInputImage.size.width / 2)` — 15 pt — and `topCapHeight:0` (`.m:139-140`). Because
the cap height is 0 the artwork is **not** vertically stretchable, which is why the frame height is hard-coded
to the artwork's own 43 pt (`.m:323`). Only the width is elastic.

Plate frame (`.m:323`):

```
width  = 80                                   (.m:319)
x      = (viewSize.width - 80) / 2
y      = topOffset + (viewSize.height - 26) / 2 - (isLandscapeWithKeyboard ? 30 : 0)
height = 43
```
wrapped in `CGRectIntegral` and cached in `_baseInputBackgroundViewFrame`.

with (`.m:309-321`):

- `topOffset = MIN(self.controllerInset.top, 70)` — the inset is normally 64 (status bar + bar), so 64.
- `keyboardHeight` is the constant `216` — the number-pad height is assumed, never measured (`.m:311`).
- `viewSize = (screenWidth, screenHeight - 20 - (portrait ? 44 : 32) - 216)` (`.m:315-317`).

The `- 26` in the vertical centring is not the plate height (43); it is a deliberate bias that lifts the
plate a little above the true centre so the plate plus the countdown line below it read as centred.

The field itself is inset inside the plate (`.m:331`): `x + 9`, `y + 10`, `width - 20`, height `22`, also
cached as `_baseCodeFieldFrame`. Note the asymmetry — 9 on the left but 20 taken off the width, so 11 on
the right; with centred text it is invisible, and it is what the original did.

Field styling (`.m:146-155`):

- text font `boldSystemFontOfSize:18`
- placeholder font `systemFontOfSize:18` via `[TGHacks setTextFieldPlaceholderFont:]` (`.m:148`) — i.e. the
  placeholder is deliberately *not* bold while the typed code is
- background `0xf5f5f5` (off-white, matching the plate artwork's interior; the plate image supplies the
  border and the field paints the fill)
- centred text, placeholder `Login.Code` = "Code" (`Localizable.strings:178`)
- `UIKeyboardTypeNumberPad`
- placeholder colour `0xadb0b6` via `[TGHacks setTextFieldPlaceholderColor:]` (`.m:154`)

The plate has `userInteractionEnabled = true` and a tap recogniser that re-focuses the field
(`.m:143-144`, `.m:412-418`) — the 80×43 plate, not the 60×22 field, is the touch target.

### The three countdown lines

`_timeoutLabel`, `_requestingCallLabel`, `_callSentLabel` are three separate labels stacked at the *same*
position and cross-faded, never one relabelled label (`.m:157-196`). All three share:

- font `systemFontOfSize:14`
- colour `0xc4c9d2`, shadow `0x25272b`, offset `(0, 1)` — note this is a *different* pair from the notice
  label above (`0xc0c5cc` / `0x323c4a`). The countdown line is very slightly lighter with a darker shadow.
- centred, `numberOfLines = 0`, clear background, `sizeToFit` at construction

Texts (`Localizable.strings:179-181`):

- `Login.CallRequestState1` = "Telegram will call you in %d:%.2d" — seeded at construction with `1, 0`,
  i.e. "1:00", so `sizeToFit` measures the widest realistic string (`.m:165`)
- `Login.CallRequestState2` = "Requesting a call from Telegram..." — starts at `alpha = 0` (`.m:180`)
- `Login.CallRequestState3` = "Telegram dialed your number" — starts at `alpha = 0` (`.m:194`)

All three are positioned at `plate.y + plate.height + 14`, centred, and each lifted a further 6 pt when
landscape-with-keyboard (`.m:334-336`). They use their `sizeToFit` widths, so the position is stable only
because the format string was pre-measured with a two-digit value.

Line `.m:333` is a commented-out `_codeButton` frame with exactly the same y expression: the original once
had a tappable "send the code again" button in this slot and **removed it**. In v1.1 the only path to a new
code is the automatic call after 60 seconds. There is no user-visible resend control and no "didn't get the
code?" affordance on this screen.

## 3. States and behaviour

### Countdown

Started in `viewWillAppear` if not already running: `_countdownStart = CFAbsoluteTimeGetCurrent()` and a
**non-repeating** `NSTimer` firing in 1.0 s, added to `NSRunLoopCommonModes` so it keeps ticking while the
user drags anything (`.m:235-240`). `updateCountdown` re-arms it each tick (`.m:276-278`) rather than using
a repeating timer — the elapsed time is recomputed from `CFAbsoluteTimeGetCurrent()` every tick
(`.m:251-252`), so drift and background suspension cannot desynchronise the display.

Timeout is `const int timeout = 1 * 60` (`.m:249`), a client-side constant; the server does not supply it in
this version. Remaining time is clamped at 0 (`.m:254-255`) and formatted as `m:ss` (`.m:257`).

The timer is invalidated in `viewWillDisappear` (`.m:289-290`), so pushing the profile or inactive-user
controller stops the clock; coming back re-enters `viewWillAppear`, and because `_countdownTimer` is nil it
**restarts the full minute from now** (`.m:235-237`).

### Reaching zero

At `remainingTime <= 0` (`.m:259-273`): the timeout label fades out over 0.2 s, and 0.1 s into that the
"Requesting a call..." label fades in over 0.2 s — a 0.1 s overlap, not a hard swap. Then a
`/tg/service/auth/sendCode/(call%d)` actor is requested with `requestCall = true` (`.m:272`), with a
monotonically increasing `actionId` so repeats never collide.

On success the same 0.2/0.1/0.2 cross-fade runs from "Requesting a call..." to "Telegram dialed your number"
(`.m:578-589`). On failure an alert is shown — `Login.NetworkError` by default, `Login.InvalidPhoneError`
for `TGSendCodeErrorInvalidPhone`, `Login.CodeFloodError` for flood (`.m:592-602`) — and, notably, the
"Requesting a call..." label is left on screen forever. The screen never returns to a countdown.

### Typing

`textField:shouldChangeCharactersInRange:` (`.m:365-398`) is where the input rules live:

- refuses all edits while `_inProgress` (`.m:367-368`)
- rejects the whole replacement if any character is outside `'0'-'9'` (`.m:377-383`) — so pasting
  "12 34" inserts nothing, it does not filter
- computes the new text, rejects it if longer than 5 (`.m:386-387`) — a paste of 6 digits is dropped whole
- assigns `textField.text` itself and returns `false` (`.m:389, 394`), so the field never performs its own
  edit; a side effect is that undo and the caret's marked-text state are bypassed
- **at exactly 5 characters it auto-submits** (`.m:391-392`). The code length is hardcoded 5.
- `#if TARGET_IPHONE_SIMULATOR return true;` (`.m:372-374`) short-circuits all of it in the simulator

### Submitting

`nextButtonPressed` (`.m:458-477`):

- no-op while `_inProgress`
- if the field is **empty**, shake both the field and the plate (`.m:463-467`). Note it shakes with the
  *cached base* x, `_baseCodeFieldFrame.origin.x` / `_baseInputBackgroundViewFrame.origin.x`, not the
  current frame — so a shake started while another shake is mid-flight still resolves back to the true
  layout position instead of accumulating drift.
- any non-empty text, even one digit, is sent to the server. The client does not pre-validate length; an
  invalid code is the server's answer, not a local shake.

The shake itself (`.m:420-450`): x is set to base, then animate 0.05 s to `+4` with `Autoreverse`, then on
completion animate 0.05 s to `-4` with `Repeat | Autoreverse` and `setAnimationRepeatCount:3`, restoring
the original frame in the completion (or immediately if the first leg was interrupted).

`inProgress` setter (`.m:339-361`): disables the Next button, sets its text to `@""`, unhides and starts the
spinner; on clear it restores `Common.Next`, calls `sizeToFit`, stops and hides the spinner. The button does
not shrink while spinning because `sizeToFit` is only called on the way out.

### Results

`/tg/service/auth/signIn/(%d)` with an incrementing `_currentActionIndex`, so a stale response from an
earlier attempt is ignored by the path comparison (`.m:472-475`, `.m:528`).

Success with `activated` true → `[TGAppDelegateInstance presentMainController]` (`.m:534-535`). Note
`inProgress` is deliberately *not* cleared on success — the spinner keeps running until the whole UI is
replaced.

Failures (`.m:539-570`), all shown as a `UIAlertView` with **nil title** and `Common.OK`:

| result code | behaviour |
| --- | --- |
| `TGSignInResultNotRegistered` | no alert. Saves the login state (date, phone, code, hash) via `saveLoginStateWithDate:` and pushes `TGLoginProfileController`, forwarding `showKeyboard:_codeField.isFirstResponder` (`.m:544-551`) |
| `TGSignInResultTokenExpired` | `Login.CodeExpiredError` = "Code expired. Please try again." and `setDelegate = true`, so tapping OK **pops back to the phone screen** (`.m:552-556`, `.m:608-611`) |
| `TGSignInResultFloodWait` | `Login.CodeFloodError` = "Limit exceeded. Please try again later." (`.m:557-560`) |
| `TGSignInResultInvalidToken` | `Login.InvalidCodeError` = "You have entered an invalid code. Please try again." (`.m:561-564`) |
| anything else | `Login.UnknownError` = "An error occurred. Please try again later" (`.m:541`) |

The expired-code case is the only one that navigates. Every other error leaves the user on the screen with
the typed code still in the field — it is never cleared.

### Ambient watchers

The controller also watches `/tg/activation` and `/tg/contactListSynchronizationState` (`.m:77-78`) and can
be driven to the main UI or to `TGLoginInactiveUserController` by those without any user action
(`.m:481-524`), guarding against pushing a second inactive-user controller by checking the top of the stack
(`.m:493, 515`).

### Rotation

`shouldAutorotateToInterfaceOrientation` allows everything except upside-down (`.m:209-212`). Landscape is a
real supported state: the plate rises 30 pt and the countdown line 6 pt (`.m:323, 334-336`), and the notice
label disappears when it no longer fits (`.m:329`).

## 4. Our port

We have no `TGLoginCodeController`. The whole login flow is one controller,
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGLoginViewController.m` (2292 lines), with the code screen
as `TGLoginStepCode` in a step enum (`:12`). Its plate/field/label objects are shared across all steps and
re-styled per step. That is a defensible choice for a modern flow with eight steps, and much of the visual
port is exact.

Correct and worth not touching: notice colours `0xc0c5cc` / `0x323c4a` (`:460-461`), countdown colours
`0xc4c9d2` / `0x25272b` (`:590-591`, `:395-396`), field bold-18 on `0xf5f5f5` with a non-bold 18 placeholder
in `0xadb0b6` (`:552-553`, `:839`), plate width 80 and height 43 with field at `+9/+10/width-20/22`
(`:816-819`, `:995-1002`), notice wrap 300 with a 14-pt gap and the `origin.y < 0` fade
(`:1007-1012`), the countdown row at `plate bottom + 14` (`:1017`), the shake geometry (4 pt, 0.05 s, repeat
3) (`:1135-1161`), the 0.2 / 0.1 / 0.2 cross-fades (`:2033-2043`, `:2056-2068`), Next `minWidth 52` with a
centred spinner (`:1379-1385`), the `BackButton_Login.png` left cap of 15 (`:1965-1973`), and the five-digit
cap with digit-only replacement (`:2204-2209`).

Differences a user can see:

1. **The shake can permanently displace the row.** Ours reads `view.frame` at the moment the shake starts
   (`TGLoginViewController.m:1139`), where the original always resets to a cached base x
   (`.m:424-427` using `_baseCodeFieldFrame` / `_baseInputBackgroundViewFrame`, set at `.m:323, 331`). Tap
   Next twice quickly on an empty field and our plate ends up 4 pt off-centre until the next layout pass.
   Fix: capture the layout frames in `layoutCentredPlateForViewSize:` and shake from those.

2. **Short codes shake instead of being sent.** `hasSubmittableInput` requires 4 digits for the code step
   (`:1115`), so 1–3 digits shakes the row. The original submitted any non-empty code and let the server
   answer `Login.InvalidCodeError` (`.m:463-475`). Ours never surfaces the server's message for a short
   code. Given the modern protocol reports the real code length, this is arguably an improvement, but it is
   a visible divergence and should be a conscious one.

3. **"Code expired" strands the user.** Our `showLoginAlert:` always passes `delegate:nil` (`:1341-1348`).
   The original set itself as delegate for the expired case only and popped back to the phone screen when
   OK was tapped (`.m:552-556`, `.m:608-611`). Our expired-code path leaves a dead screen with a code that
   can never work. Give the expired case a delegate that returns to the phone step.

4. **Resend button can collide with the call-state text.** Both the three state labels and
   `self.resendButton` are laid out at the same `resendY` (`:1017-1029`). The resend button is hidden only
   while `resendSeconds > 0` (`:1045`), but the call-state labels become visible exactly when
   `resendSeconds <= 0` (`:1033`). Unless `suppressResendButton` happens to be set, "Requesting a call from
   Telegram..." and "Send the code again" overlap. The original avoided this by having no button at all in
   that slot (see the commented-out `_codeButton`, `.m:333`).

5. **Alert titles.** Ours passes `@""` (`:1342`); the original passed `nil` (`.m:568`). On iOS 6 an empty
   string still reserves a title line, so our alerts sit a few points taller with a blank gap.

6. **Landscape.** Our `layoutInterface` reads `[UIScreen mainScreen].bounds.size` unrotated and has no
   equivalent of the original's `isLandscapeWithKeyboard` −30 / −6 adjustments (`:855-857` vs `.m:321-336`).
   If we ever allow rotation on the login screen the plate will sit too low.

7. **Empty-phone title.** We fall back to `@"Enter Code"` when no number is known (`:1375`); the original
   always had one and always showed the formatted international number (`.m:106`). Harmless, but it is our
   invention.

8. **Additions with no original counterpart**, all reasonable given the modern protocol but worth recording
   as ours, not theirs: a server-supplied timeout replacing the hardcoded 60 (`:1447-1452` vs `.m:249`),
   word/phrase code types widening the plate to 240 (`:818`, `:1403-1417`), the "Didn't get the code?" extra
   button at `resendY + 38` (`:1049-1052`, `:1814-1823`), and the 1-second auth-state poll (`:1467-1480`).

One thing I could not settle from reading alone: the original adds `topOffset` (≈64) to the plate's y
because its view is full-screen under its own custom navigation bar, while ours lays out in a
`UINavigationController` content view whose origin is already below the bar (`AppDelegate.m:214`). Under
the standard iOS 6 non-full-screen layout the two land in the same place on screen, and I believe they do,
but this is arithmetic I inferred rather than measured — worth one screenshot comparison before trusting it.

## 5. What became of it

### `twelve` (later Objective-C fork, `/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGLoginCodeController.m`, 1077 lines)

The same class, same ActionStage plumbing, grown to nearly double the size. The initialiser gained
`phoneTimeout:`, `messageSentToTelegram:`, `messageSentViaPhone:` and `termsOfService:`
(`twelve/Telegraph/TGLoginCodeController.h`, the `initWithShowKeyboard:` line). Each of those is a feature
forced on the screen by the protocol, not a matter of taste:

- The countdown text now switches between `Login.CallRequestState*` and `Login.SmsRequestState*` depending
  on whether the code arrived by call (`twelve …CodeController.m:268, 279, 296`), and the fallback actor
  requests SMS rather than a call (`:1069`).
- A "Haven't received the code?" `TGModernButton` appears, but only when the code was delivered inside
  Telegram (`_didNotReceiveCodeButton.hidden = !_messageSentToTelegram`, `:342`), and it is positioned by a
  per-screen-height table of hardcoded offsets (`:548-671`) — the price of dropping the original's purely
  relative layout.
- Terms of service is rendered on this screen (`:1031`).
- Typography moved to the flat era: a 30 pt light title (`:217`), 16 pt notice (`:224`), 24 pt code field
  with a `0xc7c7cd` placeholder (`:243-245`), 17 pt countdown labels (`:263`), and the custom `TGToolbarButton`
  is replaced by a plain system `UIBarButtonItemStyleDone` (`:119`).

What did **not** change: `shouldChangeCharactersInRange:` is character-for-character the original, still
digits-only, still capped at 5, still auto-submitting at exactly 5 (`twelve …:701-730` vs `.m:365-398`). The
five-digit assumption survived the entire redesign.

### Modern (`Telegram-iOS/submodules/AuthorizationUI/`)

The concept survives as `AuthorizationSequenceCodeEntryController` plus its node. The decisive change is
that **code length is data, not a constant**: it is carried on the `SentAuthorizationCodeType` enum and
read per case — `.sms(length:)`, `.call(length:)`, `.otherSession(length:)`, `.missedCall(_, length:)`,
`.fragment(_, length:)`, `.firebase(_, length:)`, `.email(...)`
(`AuthorizationSequenceCodeEntryControllerNode.swift:385-396, 589-610`). Likewise the "what happens next"
line is computed from `(currentType, nextType, timeout)` by a shared
`authorizationNextOptionText` helper rather than hardcoded to call-in-60-seconds
(`…ControllerNode.swift:163`), and `timeout` arrives from the server
(`AuthorizationSequenceCodeEntryController.swift:142-147, 195-206`).

So the arc is: 2013 assumed one delivery channel, one code length and one fallback, and could therefore
hardcode "5" and "60" and cross-fade between three fixed sentences. Every later version replaced each of
those constants with a server-supplied value, and the visual layout became a table of special cases as a
direct consequence. Our port already follows the modern data model on length and timeout while keeping the
2013 look, which is exactly the intended split — the defects listed above are local slips, not a wrong
architecture.

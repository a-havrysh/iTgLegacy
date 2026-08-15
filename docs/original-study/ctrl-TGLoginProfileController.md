# TGLoginProfileController — the "Your Info" sign-up screen (2013 original)

Source of truth for everything below:

- `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGLoginProfileController.h` (19 lines)
- `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGLoginProfileController.m` (754 lines)

Both live in `Telegraph/Telegraph`, not in TelegraphKit — this is an app-level screen, not a reusable
kit component. Nothing in TelegraphKit references it.

---

## 1. What it is for

The last step of registration for a phone number that has no account yet. The user has already passed
the phone step and the SMS-code step; the code controller discovered the number is unregistered and
pushed this screen. Its whole job is to collect **first name**, **last name** and, optionally, an
**avatar photo**, call `auth.signUp`, and then hand control to the main app.

It is a plain `TGViewController` with hand-placed subviews — no table view, no scroll view. Everything
is positioned arithmetically in `updateInterface:` (`.m:276-303`) against a fixed 216pt keyboard that
is *assumed always present*.

## 2. Public surface

```objc
@interface TGLoginProfileController : TGViewController <ASWatcher>
@property (nonatomic, strong) ASHandle *actionHandle;
- (id)initWithShowKeyboard:(bool)showKeyboard phoneNumber:(NSString *)phoneNumber
              phoneCodeHash:(NSString *)phoneCodeHash phoneCode:(NSString *)phoneCode;
@end
```
(`.h:13-19`)

That is the entire surface. There is no delegate and no completion block: the screen finishes by
calling `[TGAppDelegateInstance presentMainController]` itself (`.m:631`, `.m:666`, `.m:686`).

**Note a real dead parameter:** `showKeyboard` is stored into `_showKeyboard` (`.m:89`) and then never
read anywhere in the file. `viewWillAppear:` unconditionally does
`[_firstNameField becomeFirstResponder]` (`.m:264`) regardless of the flag. Do not port the flag; port
the unconditional focus.

### Call sites

1. `TGLoginCodeController.m:550` — on `TGSignInResultNotRegistered`, it first persists the login state
   with nil name/photo (`TGLoginCodeController.m:547`), suppresses the error alert
   (`errorText = nil`, line 546), then pushes
   `[[TGLoginProfileController alloc] initWithShowKeyboard:_codeField.isFirstResponder …]` animated.
2. `TGAppDelegate.mm:584` — cold-start restoration. If a saved login state has both `phoneCode` and
   `phoneCodeHash`, this controller is appended to the login navigation stack
   (`TGAppDelegate.mm:584-586`) and the stack is installed non-animated (`TGAppDelegate.mm:595`).
   So the screen must be able to come up as the initial visible controller, not only via a push.

`shouldBeRemovedFromNavigationAfterHiding` returns `true` (`.m:113-116`), so once it is hidden the
navigation controller drops it — you can never come back to a half-filled Your Info screen by pushing
forward and popping back.

## 3. Chrome: the surrounding login stack (needed to place this screen correctly)

None of the dark look is created by this controller. `self.view.opaque = false` (`.m:122`) and the
controller draws no background at all. The background comes from the shared login navigation
controller in `TGAppDelegate.mm:104-149`:

- `DarkLinen.png` as a `colorWithPatternImage` fill (`TGAppDelegate.mm:126-131`),
- a second identical pattern view used for cross-fades during transitions (`:134-139`),
- `LoginShadow.png` stretched over the whole thing (`:141-144`),
- navigation bar background `LoginHeader.png` portrait / `LoginHeaderLandscape[_Wide].png` landscape,
  with `setShadowMode:true` (`:115-118`),
- `blackCorners:true`, `restrictLandscape = true` (`:109-110`).

`self.style = TGViewControllerStyleBlack` (`.m:94`) only changes the title label: font
`boldSystemFontOfSize:20` portrait / `17` landscape (`TGViewController.mm:79-93`), colour
`0xffffff` (`TGViewController.mm:133-148`), shadow colour `0x2f3948` for the black style versus
`0x3d5c81` for the default blue style (`TGViewController.mm:151-165`).

Title text: `Login.InfoTitle` = **"Your Info"** (`en.lproj/Localizable.strings:198`).

## 4. Navigation bar buttons

**Back button** (`.m:126-131`): a custom back action, not the system one.
`BackButton_Login.png` / `_Pressed` / `_Landscape` / `_Landscape_Pressed`, each stretched with
`stretchableImageWithLeftCapWidth:15 topCapHeight:0`; text white, text shadow
`UIColorRGBA(0x07080a, 0.35f)`. Its action is `performClose` (`.m:232-237`) which calls
`[TGAppDelegateInstance resetLoginState]` **before** popping — i.e. backing out of Your Info throws
away the saved phoneCode/phoneCodeHash, so the cold-start restoration path in section 2 will no
longer resurrect this screen.

**Right button** (`.m:133-138`): a `TGToolbarButton` of type `TGToolbarButtonTypeDoneBlack`, text
`Common.Next`, `minWidth = 51`, then `sizeToFit`. DoneBlack draws `HeaderButton_Login_Blue.png`
stretched at half width (`TGToolbarButton.m:113-119`, selected at `:383-386`), white title
(`TGToolbarButton.m:173-188`) with shadow `UIColorRGBA(0x042651, 0.3f)` (`TGToolbarButton.m:190-201`).

**The label quirk worth knowing:** the button is created saying **"Next"** (`.m:134`), but
`setInProgress:` in its *false* branch sets the text to `Common.Done` and re-`sizeToFit`s
(`.m:357-358`). Since `setInProgress:` only runs when the value actually changes (`.m:343`), the
button reads "Next" until the first submit, and reads "Done" from the first failed submit onward.
This is almost certainly a bug in the original, but it is what the 2013 binary does. Our port picking
one label consistently is defensible; picking "Done" (see section 9) matches the state the user is
most likely to be looking at after any error.

**Spinner in the button** (`.m:140-143`): a `TGActivityIndicatorView` with style
`TGActivityIndicatorViewStyleSmallWhite` (`TGActivityIndicatorView.h:14`) — a frame-animated image
view, not a `UIActivityIndicatorView` (`TGActivityIndicatorView.m:57-66`). It is added *as a subview
of the Next button*, centred in it by `floorf((buttonSize - indicatorSize)/2)` on both axes, and
starts hidden.

Progress state (`.m:341-363`):
- entering progress: button disabled, `text = @""`, indicator unhidden and animating;
- leaving progress: button enabled, text `Common.Done`, `sizeToFit`, indicator stopped and hidden.

There is **no** dimming overlay over the form while the request is in flight; input is blocked purely
by `textField:shouldChangeCharactersInRange:` returning `false` when `_inProgress` (`.m:325-326`) and
by `nextButtonPressed` early-returning (`.m:437-438`).

## 5. Layout arithmetic (`updateInterface:`, `.m:276-303`)

Read this as one block; every number below feeds the next.

```
topOffset  = MIN(self.controllerInset.top, 70)            // 20 + 50            .m:278,282
keyboard   = 216 (hardcoded, always)                                            .m:280
screenSize = [TGViewController screenSizeForInterfaceOrientation:orientation]   .m:284
viewSize   = { 320, screenSize.height - 20 - (portrait ? 44 : 32) - 216 }       .m:285-286
offsetX    = floorf((screenSize.width - 320) / 2)                               .m:288
width      = 288                                                                .m:290
isLandscapeWithKeyboard = landscape && keyboard > 0                             .m:292
```

On a 3.5" iPhone 4S portrait: `viewSize.height = 480 - 20 - 44 - 216 = 200`, `offsetX = 0`.

**Add-photo button / avatar** (`.m:294-295`):

```
x = offsetX + (int)((320 - 288)/2) - 2  = offsetX + 16 - 2 = offsetX + 14
y = topOffset + (int)((viewSize.height - 68)/2) - (landscapeWithKeyboard ? 12 : 0) - 7
size = LoginAddPhoto.png intrinsic size = 71 x 71   (asset is 142x142 @2x)
```

On the 4S portrait with `controllerInset.top == 64`: `topOffset = 64`, `y = 64 + 66 - 7 = 123`.

Note the arithmetic anchor `(viewSize.height - 68)/2`: **68** is the height of the two stacked input
plates (2 × 43 = 86) *minus* nothing obvious — it does not equal any other constant in the file. It is
the tuned centring constant for the pair-of-fields block; the extra `-7` nudges it up. Treat 68 and
the `-7` as opaque tuned values, not derivable ones.

`_avatarView.frame` is `CGRectMake(offsetX + _addPhotoButton.frame.origin.x, …)` (`.m:295`) — and
`_addPhotoButton.frame.origin.x` already contains `offsetX`. On iPhone `offsetX` is 0 so the double
count is invisible; on any width other than 320 the avatar would sit twice as far right as the button
it replaces. Another original bug; do not reproduce it.

**Name plates** (`.m:297-299`):

```
fieldX = addPhotoButton.x + 71 + 14
firstPlate = { fieldX,
               topOffset + (int)((viewSize.height - 68)/2)
                         - (landscapeWithKeyboard ? 12 : 0)
                         - (portrait ? 7 : 0),
               offsetX + 288 - fieldX + 17,
               43 }
lastPlate  = CGRectIntegral({ firstPlate.x, firstPlate.y + 43, firstPlate.width, 43 })
```

On the 4S portrait: `fieldX = 14 + 71 + 14 = 99`; plate width `= 0 + 288 - 99 + 17 = 206`; first plate
at y 123, second at y 166. So the two plates are **206 × 43** each, right of a **71 × 71** photo well,
14pt gutter between them, and the plate block deliberately overhangs the nominal 288 content width by
17pt on the right (the `+17` at `.m:298`) — the plate artwork has transparent shadow padding on its
right edge, which the overhang absorbs.

The plate artwork is `LoginInput_Top.png` and `LoginInput_Bottom.png` (`.m:195-196`), each 58 × 86
pixels @2x = **29 × 43 points**, stretched with
`stretchableImageWithLeftCapWidth:(int)(width/2) topCapHeight:0` — i.e. horizontally stretchable,
vertically fixed at exactly 43pt. That 43 is where the plate height comes from; it is not a free
parameter. Top and bottom are separate assets because the pair forms one rounded card with a shared
divider, not two identical rows.

**Text fields** (`.m:301-302`):

```
firstNameField = { plate.x + 15, plate.y + (retina ? 11.5 : 11.0), plate.width - 20, 22 }
lastNameField  = { plate.x + 15, plate.y + (retina ? 10.5 : 10.0), plate.width - 20, 22 }
```

The half-pixel retina offset (`TGIsRetina()`) and the asymmetry between 11.5 and 10.5 exist to make
the 15pt bold text sit on the same optical baseline inside each half of the card — the top plate's
artwork has a highlight line the bottom one lacks. 22pt is the line box for
`boldSystemFontOfSize:15`. Note width is `plate.width - 20`, not `- 30`: the field is inset 15 on the
left and only 5 on the right, so long text runs almost to the plate's right edge before clipping. There
is no truncation UI; `UITextField` simply scrolls its content.

`updateInterface:` is always called with `UIInterfaceOrientationPortrait` from
`controllerInsetUpdated:` (`.m:273`) and from `loadView` when the inset did not change (`.m:228-229`).
The orientation-aware branches therefore only fire through paths that do not exist in this build — in
practice the screen lays out portrait-style always, even though `shouldAutorotate` is true and
upside-down is the only rejected orientation (`.m:239-247`).

## 6. The photo well

**Empty state** — `_addPhotoButton`, a `TGHighlightableButton` (`.m:145-151`), frame equal to the
intrinsic size of `LoginAddPhoto.png` (71 × 71 pt), `exclusiveTouch = true`, background image
`LoginAddPhoto.png` normal / `LoginAddPhoto_Highlighted.png` highlighted.
`TGHighlightableButton` propagates `highlighted` down to every `UILabel`/`UIImageView` subview
(`TGHighlightableButton.m:8-16`), which is exactly why the two words below are separate `UILabel`s
inside the button rather than a two-line button title.

Two labels inside it (`.m:171-193`):

| | text | key | font | colour | shadow | y |
|---|---|---|---|---|---|---|
| first | "add" | `Login.InfoAvatarAdd` (strings:200) | bold 15 | `0x9fa4ac` | `0x22262c`, offset (0,1) | 16 |
| second | "photo" | `Login.InfoAvatarPhoto` (strings:201) | bold 15 | `0x9fa4ac` | `0x22262c`, offset (0,1) | 32 |

Both are horizontally centred against the button width and their frames are run through
`CGRectIntegral` (`.m:189-190`). The two words are separate strings in the localisation file precisely
so translators can stack them; a translation that does not fit 71pt at bold 15 will simply overflow —
there is no shrink-to-fit.

**Filled state** — `_avatarView`, a plain `UIImageView` fixed at **71 × 71** (`.m:153`), hidden at
start, `userInteractionEnabled = true` with a tap recogniser to `avatarTapped:` (`.m:155-156`).
Inside it, a label tagged **123** (`.m:158-167`): text `Login.InfoAvatarEdit` = **"edit"**
(strings:199), white, clear background, `boldSystemFontOfSize:13`, `sizeToFit`, then centred
horizontally and pinned `avatarHeight - labelHeight - 3` from the top — 3pt above the bottom edge of
the 71pt square. The tag-123 lookup exists only for the custom-camera path (`.m:728`, `.m:746`).

Note the button and the avatar are **not** siblings in a container: they occupy the same rect and are
swapped by `hidden` + `alpha` together (`.m:571-574`, `.m:507-513`). Both are set, always as a pair,
because `alpha` alone would leave the hidden one tappable.

**Avatar image processing** — the picked image is run through the registered processor
`signupProfileAvatar` (`.m:568-569`), defined in `TGTelegraph.mm:507-509`:

```objc
TGScaleAndRoundCornersWithOffset(source, CGSizeMake(69, 69), CGPointMake(1, 0.5f),
                                 CGSizeMake(71, 71), 9,
                                 [UIImage imageNamed:@"LoginProfilePhotoOverlay.png"], false, nil);
```

So: photo scaled to 69 × 69, drawn at offset (1, 0.5) inside a 71 × 71 canvas, **corner radius 9**,
with `LoginProfilePhotoOverlay.png` (142 × 142 px = 71 × 71 pt) composited on top to supply the inner
shadow/bevel that matches the empty well's artwork. This is the only place the overlay asset is used.

Separately, `_imageForPhotoUpload` is produced by the `profileAvatar` processor
(`.m:578`, defined `TGTelegraph.mm:502-504`): 69 × 69 at offset (0.5, 0) in a 70 × 70 canvas, radius
10, overlay `[TGInterfaceAssets profileAvatarOverlay]`. That is the version handed to the upload actor
so the profile screen has something to show immediately; the two differ by one point of canvas and
one of radius because they sit on different backgrounds.

## 7. Behaviour

### Editing
- Both fields: `boldSystemFontOfSize:15`, clear background, `UIKeyboardTypeDefault`, delegate self
  (`.m:208-226`). Placeholders `Login.InfoFirstNamePlaceholder` = "First name" and
  `Login.InfoLastNamePlaceholder` = "Last name" (strings:202-203), placeholder colour forced to
  `0x999da4` via `[TGHacks setTextFieldPlaceholderColor:]` (`.m:215`, `.m:225`).
  No autocorrection or autocapitalisation setting at all — both stay at the UIKit defaults
  (autocorrect on, sentence capitalisation).
- Return keys: first name → `UIReturnKeyNext`, last name → `UIReturnKeyDone` (`.m:213`, `.m:223`).
  `textFieldShouldReturn:` moves focus first→last, and on last name calls `nextButtonPressed`
  (`.m:307-319`); it always returns `false`.
- The plates themselves are tappable: each background image view carries a tap recogniser that focuses
  its own field (`.m:200-206`, handlers `.m:376-390`). This matters because the field is only 22pt tall
  inside a 43pt plate — without this, half of each row would be dead.
- Length cap: **30 characters** per field, enforced on the composed replacement string
  (`.m:328-333`). Note it is `newText.length`, i.e. UTF-16 units, so an emoji costs two.
- While `_inProgress`, all text editing is refused (`.m:325-326`).
- There is a `backgroundTapped:` handler that would dismiss the keyboard, but it begins with a bare
  `return;` (`.m:365-374`) and no view is wired to it — the keyboard is never dismissible on this
  screen. That is deliberate-looking: the whole layout assumes the 216pt keyboard is up.

### Validation and the shake
`nextButtonPressed` (`.m:435-461`):
1. cleanString both fields (`.m:424-433`): collapse runs of spaces to one, collapse runs of newlines
   to two, then trim whitespace and newlines.
2. If the cleaned first name is empty → shake the first-name field **and** its plate.
3. Else if the cleaned last name is empty → shake the last-name field and its plate.
   **Last name is mandatory in 2013.**
4. Else set `inProgress = true` and fire the actor.

`shakeView:originalX:` (`.m:392-422`): the view is first snapped back to `originalX` (taken from the
`_base…Frame` values cached during layout, `.m:298-302`), then a `+4`pt autoreversing 0.05s hop,
followed by a `-4`pt autoreversing 0.05s animation repeated 3 times, ending restored to the original
frame. Total ≈ 0.35s. The cached base frames exist purely so a second shake started mid-animation
cannot drift the view.

### Submit
`ActionStage` actor `"/tg/service/auth/signUp/(%d)"` with a monotonically increasing
`_currentActionIndex`, options `phoneNumber`, `phoneCode`, `phoneCodeHash`, `firstName`, `lastName`
(`.m:457-459`). The index means a stale response from an earlier attempt is ignored by the path
comparison in `actorCompleted:` (`.m:592`).

### Completion (`actorCompleted:`, `.m:590-657`)
On success with a pending photo, the JPEG (quality **0.5**, `.m:564`) is written to
`Documents/upload/<64 hex chars>.bin` using 32 random bytes from `arc4random_buf` as the name
(`.m:598-614`), and an upload actor
`"/tg/timeline/(%d)/uploadPhoto/(%@)"` is fired with `TGTelegraphInstance` as watcher (`.m:619-620`).
The screen does **not** wait for the upload; the photo travels independently of the sign-up.

Then, on the main queue: if success and the result dictionary's `activated` flag is true →
`inProgress = false` and `[TGAppDelegateInstance presentMainController]` (`.m:625-632`). If success but
`activated` is false, nothing at all happens — the spinner keeps spinning until the
`/tg/activation` or `/tg/contactListSynchronizationState` watcher fires (section below).

On failure the spinner stops and a `UIAlertView` with a single `Common.OK` button is shown
(`.m:636-653`), message chosen by result code:

| code | string key |
|---|---|
| `TGSignUpResultInvalidToken` | `Login.InvalidCodeError` |
| `TGSignUpResultNetworkError` | `Login.NetworkError` |
| `TGSignUpResultTokenExpired` | `Login.CodeExpiredError` |
| `TGSignUpResultFloodWait` | `Login.CodeFloodError` |
| `TGSignUpResultInvalidFirstName` | `Login.InvalidFirstNameError` |
| `TGSignUpResultInvalidLastName` | `Login.InvalidLastNameError` |
| anything else | literal `@"Unknown error"` — untranslated (`.m:638`) |

### The two ActionStage watchers
Registered in `init` (`.m:96-97`) and handled in `actionStageResourceDispatched:` (`.m:659-700`):

- `/tg/activation`: true → `presentMainController`; false → push a `TGLoginInactiveUserController`,
  but only if one is not already on top (`.m:661-676`).
- `/tg/contactListSynchronizationState`: when sync finishes (resource false), consult
  `[TGDatabaseInstance() haveRemoteContactUids]`. If any remote contacts exist the account is treated
  as activated → main controller. Otherwise push the inactive-user screen, or, if it is already there,
  just clear `inProgress` (`.m:677-699`).

This is the 2013 invite-gate: a brand new account with zero Telegram contacts got parked on an
"inactive user" screen instead of the chat list.

### Photo acquisition
`addPhotoButtonPressed` (`.m:463-480`) — the custom camera is compiled out
(`TG_USE_CUSTOM_CAMERA false`, `.m:31`), so the shipping path is a `UIActionSheet` tagged
`TGImageSourceActionSheetTag` with `Common.TakePhoto`, `Common.ChoosePhoto`, `Common.Cancel`,
shown `inView:self.view`.

`avatarTapped:` (`.m:482-496`) — a different sheet, tag `TGAvatarActionSheetTag`:
`Login.InfoUpdatePhoto` ("Update Photo", strings:204), then a **destructive**
`Login.InfoDeletePhoto` ("Delete Photo", strings:205), then Cancel.

`actionSheet:clickedButtonAtIndex:` (`.m:498-539`):
- Delete → restore the add-photo button (alpha 1, unhidden), clear the avatar image, alpha 0, hidden,
  drop both `_dataForPhotoUpload` and `_imageForPhotoUpload`. No animation, no confirmation.
- Update → re-enter `addPhotoButtonPressed`.
- Camera chosen but `isSourceTypeAvailable:` false → silently do nothing (`.m:524-525`).
- Otherwise: end editing, tell `TGApplication` to swallow status-bar-hidden requests
  (`setProcessStatusBarHiddenRequests:true`, `.m:529`), present a `UIImagePickerController` with
  `allowsEditing = true`.

`imagePickerController:didFinishPickingMediaWithInfo:` (`.m:541-579`): the crop rect from the picker
is forced square by expanding the shorter side around its centre (`.m:547-560`) — UIKit's editing
rect on iOS 6 is not reliably square. Then
`TGFixOrientationAndCrop(original, cropRect, CGSizeMake(600, 600))`, JPEG at 0.5. If the JPEG comes
back nil the method returns and the UI is left unchanged (`.m:565-566`).

Cancel handler re-sets `setProcessStatusBarHiddenRequests:` to **true** (`.m:585`) whereas the success
handler sets it to **false** (`.m:545`). One of the two is wrong; the finish path (false) is the one
that restores normal behaviour.

## 8. Empty / long / missing content summary

- **No photo**: valid; sign-up proceeds with no upload actor at all (`.m:594` guards on
  `_dataForPhotoUpload != nil`).
- **Empty first name**: shake, no alert, no submit.
- **Empty last name**: shake, no alert, no submit. Mandatory.
- **Whitespace-only name**: `cleanString` trims it to empty → treated as empty → shake.
- **Name > 30 chars**: keystrokes simply refused, no feedback.
- **Long name inside the field**: the 186pt-wide text field scrolls; no ellipsis, no font shrink.
- **Long "add"/"photo" translation**: overflows the 71pt button, unclipped (labels are subviews of the
  button, which does not clip).
- **Server says activated == false**: spinner keeps running, screen stays, resolution comes from the
  ActionStage watchers.

## 9. Our port — `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGLoginViewController.m`

We have no separate controller. Registration is one step inside the 2292-line
`TGLoginViewController`: `TGLoginStepRegistration` (`.m:19`), entered by `showRegistrationStep`
(`.m:1483-1510`), laid out by `layoutRegistrationStepForViewSize:` (`.m:894-932`).

What we got right, briefly: title "Your Info" (`.m:1490`), field font bold 15 (`.m:829`), placeholder
colour `0x999da4` (`.m:836-837`), placeholders "First name"/"Last name", plate height 43 and field
inset `+15 / width-20 / height 22` with the same retina half-pixel and the same 11.0 vs 10.0 baseline
split (`.m:911-923`), the top/bottom plate split (`.m:907-908`), the `(int)((height-68)/2) - 7`
centring constant (`.m:910`), Next-button `minWidth` 51 for this step (`.m:850`), the 30-character cap
(`.m:2199-2202`), the first→last return-key chain (`.m:2263-2266`), and the shake animation reproduced
timing-for-timing (`.m:1138-1161`). The back-button shadow `0x07080a @ 0.35` is also correct
(`.m:1959`).

### Visible defects

**D1 — The avatar well does not exist.** `addPhotoButton` is declared at `TGLoginViewController.m:90`
and never assigned, never added to a view, never referenced again. So we ship no
`LoginAddPhoto`/`_Highlighted` button, no "add / photo" labels, no 71 × 71 avatar view with the "edit"
caption, no `LoginProfilePhotoOverlay` compositing, no photo action sheets, no delete-photo
destructive item. This is the single biggest gap: the original's Your Info screen is visually defined
by that square on the left (`original .m:145-193`, `.m:153-167`).

**D2 — Wrong plate geometry, following from D1.** We lay both plates full width 288 starting at
`(viewSize.width - 288)/2` (`ours .m:909-920`). The original's plates are **206pt wide starting at
x = 99** because the photo well occupies x 14…85 plus a 14pt gutter, and they extend 17pt past the
nominal content edge (`original .m:297-299`). Even after D1 is fixed, the plate frame must be
recomputed as `offsetX + 288 - fieldX + 17`, not 288.

**D3 — Last name is optional for us, mandatory in the original.** `hasSubmittableInput` returns
`text.length > 0` on the first-name field only (`ours .m:1116-1117`), and
`submitRegistrationFirstName:` passes `lastName.length > 0 ? lastName : nil` (`ours .m:1261-1263`).
The original refuses to submit and shakes the last-name row when it is empty
(`original .m:448-452`). Note the modern client agrees with *us*, not with 2013 (section 10) — this
one is worth a deliberate decision rather than a blind fix. If we keep it optional, we should at
least stop shaking the last-name row on a first-name-only error (`ours .m:1169-1172` shakes both
rows unconditionally, which the original never does — it shakes exactly one row).

**D4 — We never shake for a missing name; we alert instead.** Our failure path shows
`showLoginAlert:@"This name was not accepted. Please try again."` (`ours .m:1270`). The original shows
an alert only for a *server* rejection, and even then with the localised
`Login.InvalidFirstNameError` / `Login.InvalidLastNameError` text depending on which field the server
faulted (`original .m:647-650`). We collapse both to one untranslated sentence and lose the
field-specific signal.

**D5 — Notice label.** We pass a notice string
`"Enter your name so your friends know who is writing to them."` into `enterStep:` (`ours .m:1491`)
and then hide it (`ours .m:864`, `.m:925`). Harmless today, but it means a future change to
`enterStep:` could make a 2013-impossible label appear. The original has no notice on this screen at
all — the modern client introduced it (section 10).

**D6 — Busy state differs.** The original blanks the button's title, shows the frame-animated
`TGActivityIndicatorView` small-white inside the button, and dims nothing (`original .m:341-363`).
We keep a `UIActivityIndicatorViewStyleWhite` inside the button (`ours .m:354-359`, positioned
`.m:851-853`) — acceptable substitution — but we additionally unhide a full-screen `shadeView`
(`ours .m:642-646`, `.m:1086`). It is `clearColor` so nothing is visible; it only blocks touches. Not
user-visible today, but if anyone ever gives it a colour it will diverge.

**D7 — Autocapitalisation/autocorrection.** We force
`UITextAutocorrectionTypeNo` + `UITextAutocapitalizationTypeWords` (`ours .m:578-579` for last name,
`.m:1498-1499` for first). The original sets neither, leaving autocorrect **on** and capitalisation at
*sentences* (`original .m:208-226`). Ours is arguably better behaviour for a name field; it is a
visible difference (the keyboard's shift state on the second word) and should be recorded as a
deliberate deviation, not left as an accident.

**D8 — Button label.** We always say "Done" on this step (`ours .m:861`); the original says "Next"
until the first submit completes and "Done" thereafter (`original .m:134` vs `.m:357`). Keeping
"Done" is the right call; flagged only so nobody "fixes" it toward "Next".

**D9 — Back button semantics.** The original's back wipes the saved login state before popping
(`original .m:232-237`). Worth checking that our `installBackButton` path (`ours .m:1957`) clears the
persisted phoneCode/phoneCodeHash equivalent; if it does not, a user who backs out and relaunches can
land back on registration with stale credentials.

**Ambiguity to record:** the original's landscape branches (`original .m:285`, `.m:292`, `.m:298`) are
unreachable in the shipping build because `updateInterface:` is only ever called with
`UIInterfaceOrientationPortrait` (`original .m:229`, `.m:273`), and the login navigation controller
sets `restrictLandscape = true` (`TGAppDelegate.mm:110`). I cannot say from source what the landscape
screen actually looked like; do not treat those constants as verified.

## 10. What became of it

### Telegram-iOS (modern)
`submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpController.swift` +
`…SignUpControllerNode.swift` (303 lines).

- **Both names now optional, with a fallback.** `nextPressed` errors only when *both* are empty; if
  only the first name is empty the last name is promoted into the first-name slot
  (`SignUpController.swift:258-269`). Forced by reality: a large share of users have one name.
- **The shake survived thirteen years**, now paired with haptics:
  `self.hapticFeedback.error(); self.controllerNode.animateError()`
  (`SignUpController.swift:263-264`, `ControllerNode.swift:284`). This is the strongest continuity in
  the whole screen — the 2013 ±4pt shake is still the vocabulary for "this field is empty".
- **The title moved into the content**, big and left-aligned: `Login_InfoTitle` at
  `Font.semibold(28.0)` inside the node (`ControllerNode.swift:92`), not in the navigation bar. Change
  of taste, part of the 2018 flat authorization redesign.
- **A help line was added**: `Login_InfoHelp` at `Font.regular(16.0)`, centred
  (`ControllerNode.swift:98`). Absent in 2013.
- **Terms of Service** became a first-class part of the screen (`SignUpController.swift:183-194`,
  layout item at `ControllerNode.swift:263`). Forced by GDPR-era legal requirements, not by taste.
- **Avatar**: still there, but now backed by the full media editor — `avatarAsset` /
  `avatarAdjustments` including video avatars (`SignUpController.swift:37-38`, `:167-172`), and the
  image is compressed at **quality 0.7** into a temp file (`SignUpController.swift:274-276`) versus
  our 0.5 in-memory JPEG. Forced by new features (animated avatars).
- **The 30-character cap is gone** from the controller; length is a server concern now.
- The invite-gate (`TGLoginInactiveUserController`, contact-count check) is gone entirely. Abandoned
  idea.

### twelve (`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGLoginProfileController.m`, 909 lines)
Same class name and same `initWithShowKeyboard:phoneNumber:phoneCodeHash:phoneCode:` shape plus
`termsOfService:` (`twelve .m:97`). It is the same file evolved, and it shows exactly where the
pressure came from:

- The dark linen is gone: `self.view.backgroundColor = [UIColor whiteColor]` (`twelve .m:139`) with a
  `_grayBackground` and `_separatorView`; the title is an in-content `UILabel` reading
  `Login.InfoTitle` (`twelve .m:155`). The iOS 7 flattening, i.e. taste.
- The Next button is a stock `UIBarButtonItem` with `UIBarButtonItemStyleDone`
  (`twelve .m:111`) — `TGToolbarButton` and all the `HeaderButton_Login_*` artwork dropped.
- The avatar grew to **110 × 110** at `x = 10 + TGRetinaPixel`, `y = separator.y + 11`
  (`twelve .m:184`) from 71 × 71. Bigger screens.
- The plate image views vanished; fields became `TGTextField` with `_firstNameSeparator` /
  `_lastNameSeparator` hairlines (`twelve .m:53-54`, `:74-75`). This is the death of the
  `LoginInput_Top`/`_Bottom` card idiom.
- `_noticeLabel` with `Login.InfoHelp`, system 17, `0x999999`, centred, y 274 widescreen / 218
  otherwise, and alpha conditioned on screen size and whether terms are present
  (`twelve .m:246-257`) — the same help line the modern client has, arriving here first.
- `_termsOfServiceLabel`, tappable, accent-coloured link range, system 16 on large screens / 14
  otherwise, suppressed entirely on 480pt-tall screens (`twelve .m:260-299`). Forced by legal
  requirements; note the explicit "does not fit on a 3.5-inch screen" carve-out at `twelve .m:260` —
  useful precedent for us, since 3.5-inch is our only screen.
- `TGProgressWindow` replaced the in-button `TGActivityIndicatorView` (`twelve .m:91`), and the photo
  flow moved to `TGMediaAvatarMenuMixin` + `TGWebSearchController` (`twelve .m:29-30`).

Net reading: of this screen's 2013 vocabulary, only three things survived to the modern client — the
two-name form, the shake-on-empty, and the tappable avatar well. Everything else (linen background,
plate artwork, custom toolbar button, 30-char cap, mandatory last name, the contacts invite-gate) was
either flattened away by taste or dropped as the product changed.

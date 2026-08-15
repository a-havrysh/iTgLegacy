# TGCameraController — the custom in-app camera (original v1.1, disabled in the shipped build)

Sources studied:

- `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGCameraController.h` (22 lines)
- `.../Telegraph/Telegraph/TGCameraController.m` (1483 lines)
- `.../Telegraph/Telegraph/TGCameraWindow.h` / `.m` (29 / 139 lines) — its only host
- Call sites: `TGProfileController.m`, `TGLoginProfileController.m`
- Artwork: `.../Telegraph/Telegraph/Resources/Camera*.png`, `CameraBtn*.png`, `CameraStripe*.png`, `CameraFocus@2x.png`, `SendPhoto*.png`, `BlackPhotoBtn*.png`

## 0. The single most important fact: it did not ship

The whole class is wrapped in `#if TG_USE_CUSTOM_CAMERA` (`TGCameraController.h:9`, `TGCameraController.m:1`,
`TGCameraWindow.m:1`, closing `#endif` at `TGCameraController.m:1483`). That macro is not a build setting;
it is defined *locally, as false*, in both files that would use it:

- `TGProfileController.m:107` — `#define TG_USE_CUSTOM_CAMERA false`
- `TGLoginProfileController.m:31` — `#define TG_USE_CUSTOM_CAMERA false`

Nothing else in the tree defines it (grep for `TG_USE_CUSTOM_CAMERA` across the src drop returns only
these two defines plus the guarded files themselves, and `TGPasstroughFilter.h:9`). So in the shipped
v1.1 binary, `TGCameraController` compiles to nothing at all.

Two further pieces of evidence that the file is stale, not merely feature-flagged off:

1. `TGCameraController.m:410` calls
   `[_transitionHelper beginTransitionOut:fromView:toView:aboveView:interfaceOrientation:toRectInWindowSpace:toImage:keepAspect:]`,
   but the only `beginTransitionOut:` declared in `TelegraphKit/TelegraphKit/TGImageTransitionHelper.h:17`
   also takes `swipeVelocity:` and `completion:`. The dead branch would not compile against the shipped
   helper.
2. `GPUImage.h`, `GPUImageStillCamera`, `GPUImageRawDataInput`, `GPUImageView` (with Telegram's own
   `ignoreFrames` / `imageScale` / `imageTranslation` / `convertYUV` / `kGPUImageFillModeReal` additions)
   are imported at `TGCameraController.m:7` but GPUImage is not present anywhere in the source drop
   (`find . -iname GPUImageView.h` → nothing). The camera depended on a forked GPUImage that was never
   shipped with the sources.

**What actually ran in 2013 for "take a photo" is a plain `UIImagePickerController`** behind a
`UIActionSheet`. That is the behaviour our port must match, and it does. The custom camera is
interesting as a design document — it is the direct ancestor of the modern camera — but it is not the
2013 look a user saw.

### What the user really saw (the live path)

`TGProfileController.m:3058-3075`, `showCamera`:

```
_currentActionSheet = UIActionSheet, tag TGImageSourceActionSheetTag
  button 0: TGLocalized(@"Common.TakePhoto")          -> "Take Photo"   (Localizable.strings:53)
  button 1: TGLocalized(@"Common.ChoosePhoto")        -> "Choose Photo" (Localizable.strings:54)
  button 2: TGLocalized(@"Conversation.SearchWebImages")
  cancel  : "Common.Cancel"
shown in self.parentViewController.view
```

Button 0 handling, `TGProfileController.m:3181-3196`: bail out silently if
`isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera` is false, `[self.view endEditing:true]`,
then a stock `UIImagePickerController` with `sourceType = Camera` and **`allowsEditing = true`** (the
system square-crop step supplied the avatar crop), presented modally after
`[(TGApplication *)[UIApplication sharedApplication] setProcessStatusBarHiddenRequests:true]`.
Buttons 1 and 2 do *not* use the system picker — they push Telegram's own `TGImagePickerController` /
`TGImageSearchController` with `avatarSelection:true` (`TGProfileController.m:3200-3212`).
`TGLoginProfileController.m:524-532` is the same shape, with the picker source chosen by
`buttonIndex == 0 ? Camera : PhotoLibrary`.

Everything below documents the dead-but-designed custom camera.

## 1. Purpose and shape

A full-screen, portrait-only camera **living in its own `UIWindow`**, not in the navigation stack.
`TGCameraWindow` (`TGCameraWindow.m:30-43`) sets `windowLevel = UIWindowLevelStatusBar + 1`, starts
`backgroundColor = clearColor`, `opaque = false`, and makes the controller its `rootViewController`.
`show` (`:52-68`) does `makeKeyAndVisible`, then fades `alpha` 0 → 1 over **0.3 s**, and only on
completion flips to `blackColor` / `opaque = true` (transparent during the fade so the app shows
through; opaque afterwards for compositing speed).

Public surface of the controller is tiny (`TGCameraController.h:15-21`):

- `@property ASHandle *watcherHandle` — the callback channel.
- `- dismissToRect:fromImage:toImage:toView:aboveView:interfaceOrientation:` — the "fly the photo into
  the avatar" exit animation.

It talks back through `ASWatcher`, never a delegate protocol, with exactly two actions:

- `@"dismissCamera"`, no options (`TGCameraController.m:428-437`, emitted by the top-bar Cancel).
- `@"cameraCompleted"`, options `{@"image": UIImage, @"imageData": NSData}` (`:973`).

`TGCameraWindow` merely relays both to its own `_watcherHandle` (`TGCameraWindow.m:117-135`), so the
window is a pure transport.

Host handling (`TGProfileController.m:4415-4445`): on `dismissCamera`, `[_cameraWindow dismiss]` and nil
the window. On `cameraCompleted`, run the `@"profileAvatar"` image processor over the image to get
`toImage`, then `dismissToRect:` the avatar view's rect converted to window space, hide
`_avatarViewEdit`, and **0.29 s × `TGAnimationSpeedFactor()`** later unhide the avatar and load
`toImage`. That 0.29 is deliberately just under the window's own 0.3 s dismissal.

## 2. States

`TGCameraControllerState` (`:21-25`) has three values and, notably, no value `1`:

```
Empty   = -1   (pre-loadView sentinel)
Camera  =  0
Editing =  2
```

`setState:animated:` (`:1161-1273`) only implements three of the possible transitions:
Empty→Camera, Camera→Editing, Editing→Camera. Anything else is a no-op, and `_state != state` guards
re-entry. `loadView` ends (`:344-346`) by stashing the requested state, forcing `_state = Empty`, and
re-applying — the standard trick to make the first transition run its side effects.

Empty→Camera (`:1170-1191`): scroll view hidden; both editing panels hidden and parked off-screen
(top at `-height`, bottom at `screenHeight + height`); camera panels shown; if a camera exists,
`startCamera` and force the flash icon to "Off", otherwise `updateFlashIcon:false` which hides the flash
button entirely.

Camera→Editing (`:1195-1231`): focus indicator hidden immediately; scroll view unhidden; editing panels
unhidden and slid to top `y = 0` and bottom `y = screenHeight - height` over **0.2 s**; the camera
panels are hidden only in the completion block, so the two chrome sets cross over rather than popping.

Editing→Camera (`:1236-1269`): exact inverse, same 0.2 s, camera panels unhidden *before* the animation
starts and editing panels hidden in the completion.

Note the asymmetry that gives the effect its character: the camera chrome never animates. It is simply
underneath, revealed and covered by the sliding editing chrome.

## 3. Layout and metrics (all portrait, `screenSize` from `[TGViewController screenSizeForInterfaceOrientation:UIInterfaceOrientationPortrait]`)

Root view background `UIColorRGB(0x222222)` (`:173`).

The whole layout is built around a **fixed 320×320 square preview** — the aspect ratio Telegram sent
photos in at the time:

- Top panel (`:202`): `(0, 0, screenWidth, ([TGViewController isWidescreen] ? 44 : 0) + 68)`.
  So **68 pt on a 3.5" screen, 112 pt on a 4" screen**. The extra 44 on the iPhone 5 is spent entirely
  on padding above the controls; the controls themselves keep their 68-pt-relative offsets, because
  every child is positioned from the top with hard-coded y-offsets (17, 21, 23, 25) — which means on the
  4" screen the icons sit 44 pt higher than the panel's visual centre. This is the one place the layout
  is arguably wrong in the original, and it is worth not copying.
- Bottom panel (`:204`): `y = topHeight + 320`, `height = screenHeight - (topHeight + 320)`.
  **92 pt on 3.5" (480 − 68 − 320), 136 pt on 4" (568 − 112 − 320).**
- The preview is the 320-pt band between them; `_gpuImageView` is full-screen and inserted at index 0
  (`:1093`), so the panels mask it.

Panel backgrounds are stretchable strips:

- `CameraStripeTop.png` — `CameraStripeTop@2x.png` is 20×136 px = **10×68 pt**, i.e. exactly the 3.5"
  panel height — stretched with `stretchableImageWithLeftCapWidth:6 topCapHeight:20` (`:209`), so it
  stretches horizontally *and* vertically to cover the 112-pt widescreen panel.
- `CameraStripeBottom.png` — 20×184 px = **10×92 pt**, again exactly the 3.5" bottom-panel height —
  `leftCapWidth:6 topCapHeight:0` (`:213`), horizontal stretch only, so on the 4" screen it is drawn
  into a 136-pt frame from a 92-pt image and the `UIImageView` scales it. Different rule top vs bottom;
  faithfully odd.

### Top panel controls (camera state)

| control | frame | artwork | citation |
|---|---|---|---|
| Reverse | `x = (panelWidth − iconW)/2`, `y = 0`, `w = iconW`, `h = panelH − 8`; icon offset `+0,+17` inside | `Camera_Reverse.png`, 128×70 px = **64×35 pt** | `:218-224` |
| Flash | `(0, 0, 80, 60)`; icon offset `+17,+21`; "On"/"Off" text image offset `+38,+25` | `Camera_Flash.png`, 40×54 px = **20×27 pt** | `:227-243` |
| Cancel | `x = panelW − iconW − textW − 13`, `y = 0`, `w = iconW + textW + 39`, `h = 60`; text offset `+4,+23`, icon offset `+textW+5,+21`; `autoresizingMask = FlexibleLeftMargin` | `Camera_Cancel.png`, 39×54 px = **19.5×27 pt** | `:248-260` |

All three use `showsTouchWhenHighlighted = true` — the UIKit white radial glow, no custom pressed art —
and flash/cancel set `exclusiveTouch = true`.

**The reverse button only exists on Retina devices** (`if (TGIsRetina())`, `:216`). There is no `@1x`
`Camera_Reverse.png` in Resources (only `Camera_Reverse@2x.png`), so on the 3GS the front-camera toggle
simply is not drawn. Same for every other Camera asset: the Resources folder contains **only `@2x`
variants**. Any non-Retina rendering of this screen would have been broken.

The flash button is hidden outright at build time if the last-used camera was the front one
(`:245-246`), and `updateFlashIcon:flashMode:` (`:1021-1039`) hides it whenever `flashAvailable` is
false and otherwise shows exactly one of the two label image views. There is no "Auto" state in the UI —
`startCamera` (`:1064-1065`) actively converts a device default of `AVCaptureFlashModeAuto` into
`FlashModeOn`, so the toggle is strictly binary.

### Text rendered as images: `makeCameraButtonTextImage` (`:27-62`)

Small but the most transferable idea in the file. Button labels in the camera chrome are not `UILabel`s;
they are pre-rendered `UIImage`s, memoised in a `dispatch_once` `NSMutableDictionary` keyed
`@"<text>::<isButtonImage 0|1>"`.

- Font: **`[UIFont boldSystemFontOfSize:14]`** (`:45`).
- Size: `sizeWithFont:`, then `width = (int)width + 2` (`:47`) — one point of slack on each side for the
  shadow.
- Context: `UIGraphicsBeginImageContextWithOptions(size, false, 0.0f)` — non-opaque, device scale.
- Shadow: offset `(0, 1)`, blur **2.0**, colour `UIColorRGBA(0x000000, 0.3)` (`:51`).
- Fill: white at **1.0 alpha for button labels (`isButtonImage == true`), 0.72 for chrome labels**
  (`:52`). So "Library" is solid white; "On", "Off" and "Cancel" in the top bar are 72% white.
- Drawn at `x = 1, y = 0` (`:54`).

Returns `nil` for `nil` text (`:30`), which would leave the `UIImageView` empty rather than crash.

### Bottom panel controls (camera state)

- **Library button** (`:262-270`): `(7, bottomPanelH − 62, 84, 38)`. Background `CameraBtn.png` /
  `CameraBtn_Pressed.png` (168×76 px = **84×38 pt** — the frame is the artwork's natural size).
  Label is `makeCameraButtonTextImage(@"Library", true)`, centred horizontally and **1 pt above centre**
  vertically (`floorf(...) - 1`, `:267`).
- **Shutter** (`:276-284`): only created if the camera source is available (bypassed on the simulator,
  `:272-274`). Frame is `((bottomPanelW − imgW)/2, bottomPanelH − imgH − 20, imgW, imgH)` with
  `Camera_MakePhoto.png` 194×92 px = **97×46 pt**, so a 20 pt gap from the bottom of the panel.
  `autoresizingMask = FlexibleLeftMargin | FlexibleRightMargin` keeps it centred.
  Pressed art `Camera_MakePhoto-Pressed.png`.

Note the two bottom buttons are anchored to *different* references: the library button at
`height − 62` (top of a 38-pt button = 24 pt from the bottom) and the shutter at `height − 46 − 20`
(20 pt from the bottom). Their baselines do not agree; the library button sits 4 pt higher.

### Editing chrome

Both editing panels are created at exactly the camera panels' frames (`:287-290`), and both are filled
with `[UIColor colorWithPatternImage:[UIImage imageNamed:@"Camera_DarkBackground.png"]]` (`:292-293`) —
a 128×128 px = 64×64 pt tile, so the editing bars are a repeating texture rather than a stretched strip.
That is the visible difference between camera chrome and editing chrome.

Each carries a gradient shadow **facing the photo**:

- `Camera_ShadowTop.png` (8×40 px = **4×20 pt**) pinned to the *bottom* edge of the top panel
  (`y = panelH − imgH`, full width, `:295-298`).
- `Camera_ShadowBottom.png` (8×40 px = **4×20 pt**) pinned to the *top* edge of the bottom panel
  (`y = 0`, `:300-303`).

Editing buttons, unlike the camera chrome, use real `UILabel`s:

- **Cancel** (`:308-323`): frame `(10, bottomPanelH − 61, imgW, imgH)`, art `BlackPhotoBtn.png` /
  `BlackPhotoBtn_Pressed.png`, 154×72 px = **77×36 pt**. Label "Cancel" (hard-coded English, *not*
  localized — `:313`), `boldSystemFontOfSize:13`, `textColor 0xffffff`, `shadowColor UIColorRGBA(0x000000, 0.1)`,
  `shadowOffset (0, −1)`, centred and 1 pt above centre.
  Note `BlackPhotoBtn_Active@2x.png` exists in Resources but this screen never uses it.
- **Send** (`:325-342`): frame `((bottomPanelW − imgW)/2, bottomPanelH − 67, imgW, imgH)`, art
  `SendPhoto.png` / `SendPhoto_Pressed.png`, 196×92 px = **98×46 pt**. Label `TGLocalized(@"Camera.Done")`,
  `boldSystemFontOfSize:18`, white, `shadowColor UIColorRGB(0x1662c5)` — an *opaque blue* shadow, the
  darker edge of the blue button, with `shadowOffset (0, −1)`. Centred with `(int)` truncation and
  **−1 pt horizontally** (`:339`).

  **`"Camera.Done"` is absent from `Telegraph/Telegraph/en.lproj/Localizable.strings`** (610 lines; grep
  finds no such key). With a standard `TGLocalized` fallback the button would render the literal string
  `Camera.Done`. Another marker of unfinished code — do not treat this label's text as authoritative.
  Use "Send" or "Done" and say so.

### Focus indicator

`CameraFocus.png` (150×150 px = **75×75 pt**), an `UIImageView` added directly to the root view,
`hidden = true`, `alpha = 0` (`:177-180`). `setFocusIndicatorState:show:` (`:1323-1355`) centres it on
the point (guarding NaN, `:1325`) and fades in over **0.2 s** / out over **0.3 s**, both with
`BeginFromCurrentState`, hiding it again in the fade-out completion. It is forced hidden on
`cameraDidStop`, `cameraDidPause`, and on entering the editing state (`:1197-1198`, `:1295-1305`).

## 4. Behaviour

### Tap to focus (`gpuImageViewTapped:`, `:1417-1479`)

Ignored while the scroll view is visible (i.e. in editing state) or when the front camera is active
(`:1419`). Shows the indicator at the tap point in *view* coordinates immediately, then off the main
queue converts the tap into normalised device coordinates: scale by 2 on Retina, letterbox-correct
against `[_gpuImageView inputImageSize]` scaled up so it covers the screen in both axes
(`:1448-1457` — the same aspect-fill maths as the preview), add the crop offset, divide by the image
size. Then sets `focusPointOfInterest` + `AVCaptureFocusModeAutoFocus`, and if supported also
`exposurePointOfInterest` + `AutoExpose`. All guarded by `focusPointOfInterestSupported`.

`observeValueForKeyPath:` on `adjustingFocus` (`:1357-1415`) does the same conversion **in reverse** to
place the indicator when the *camera* refocuses by itself, and drives show/hide from the KVO boolean.
So the indicator has two independent drivers: your tap, and the hardware.

### Shutter (`shutterButtonPressed`, `:699-953`)

1. Record `_shotTime`, disable `view.userInteractionEnabled`, and **transition to Editing immediately,
   animated** (`:701-705`) — the chrome swaps before the photo exists. The still-live preview is what
   you see behind the editing bars for a moment.
2. `capturePhotoAsSampleBufferWithCompletionHandler:` on the GPUImage still camera. On error: release
   the buffer, log, re-enable interaction, resume capture, return — but note it **does not undo the
   Editing state**, so a capture failure leaves you stuck in editing chrome over a live preview. A real
   bug in the original.
3. YUV downsampling by hand (`:770-826`): `delta = (width*height < 1281*961) ? 1 : 3`, i.e. images
   larger than ~1.23 MP are decimated 3× in both axes by nearest-neighbour, smaller ones kept 1:1.
   The "RGB" buffer it fills is actually packed `(Y, Cb, Cr)` triples uploaded as `GPUPixelFormatRGB`
   and converted on the GPU (`_gpuImageView.convertYUV = true`, `:846`). The `delta == 1` path writes
   rows bottom-up (`height - 1 - y`, `:810`), the `delta == 3` path top-down — a vertical-flip
   discrepancy between the two branches.
4. Rotation `kGPUImageRotateRight` (`:847`), camera stopped 0.2 s later on the GL queue (`:850-853`).
5. Geometry (`:863-890`): halve the size on Retina, swap width/height (portrait), `imageScale =
   scrollViewHeight / imageHeight`, and
   `contentSize = (max(scaledW, svW), max(scaledH + svH − 320, svH))`. The `− 320` is the preview square
   again: the scroll view is full-screen, the photo occupies 320 of it, so the scrollable overflow is
   the photo height minus the square. Initial `contentOffset` is centred, and the scroll view is set to
   `contentOffset.y − 12` while the GPU view gets `contentOffset` — a **constant 12 pt bias** between
   the scroll view and the image, applied again in `scrollViewDidScroll:` (`:1313-1321`,
   `contentOffset.y += 12`). The scroll view is a transparent, invisible driver: it has no subviews and
   no indicators (`:185-186`), it exists purely to give UIKit-quality panning to a GL-rendered image.
6. `fadeInImage` (`:651-666`) cross-fades the frozen snapshot out over **0.2 s**.

`createFadingImage` (`:633-649`) asks the GPU view for a snapshot and shows it in `_fadingImageView`
with `contentMode = ScaleAspectFill`. `_fadingImageView` is created with
`transform = CGAffineTransformMakeScale(1, -1)` (`:193`) — vertically flipped, because GL output is
bottom-up.

`_colorFadingView` (`:196-200`) is a solid rectangle of the root background colour over the whole
screen, used to hide the moment the capture session starts or restarts: `fadeOutCamera` brings it to
alpha 1 over **0.3 s** (`:668-675`), `fadeInCamera` takes it to 0 over **0.18 s** and hides it
(`:677-692`), only if it is currently visible.

### Send (`sendButtonPressed`, `:955-977`)

Snapshot the GPU view, then
`TGScaleAndRoundCornersWithOffsetAndFlags(image, TGFitSize(image.size, screenSize), CGPointMake(0, −topPanelHeight), CGSizeMake(320, 320), 0, nil, true, nil, TGScaleImageFlipVerical)`
— i.e. **crop the 320×320 square starting at the top panel's bottom edge, no rounding, vertical flip**.
JPEG at **quality 0.5** (`:964`). Both the `UIImage` and the `NSData` go to the watcher.
Interaction is disabled for the duration and re-enabled on the main queue.

### Editing Cancel (`editingCancelButtonPressed`, `:979-1003`)

Three behaviours in one button:

1. If we got here from the library picker (`_imagePicker != nil`), Cancel **reopens the library**
   rather than returning to the camera (`:983-987`).
2. A **0.21 s dead time after `_shotTime`** (`:989-990`): taps land silently if you hit Cancel within
   210 ms of the shutter. This exists because `_shotTime` is re-stamped when the capture finishes
   (`:861`), so the guard covers the window where the GL pipeline is still swapping targets.
3. Otherwise disable the bottom panel and flash button, `startCamera`, transition to Camera animated,
   and `fadeOutCamera`. `cameraDidStart` (`:1287-1293`) re-enables them and calls `fadeInCamera`. So the
   chrome is dead until the session is genuinely running.

### Library (`libraryButtonPressed`, `:491-501`)

`stopCamera` (full teardown, not pause), hide the status bar with no animation, present a stock
`UIImagePickerController` with `sourceType = PhotoLibrary`, `allowsEditing` **not** set.

`didFinishPickingMediaWithInfo:` (`:503-590`) is where the sizing policy lives:

- Take `UIImagePickerControllerOriginalImage`, divide by `scale` to get points.
- `TGFitSize(imageSize, CGSizeMake(500, 500))` — the local variable is literally named `screenWidth` and
  set to 500 (`:511`); a cap, not a screen dimension.
- Then **upscale so neither side is below 320** (`:514-523`), height first then width, each with
  `ceilf`. A very wide panorama therefore ends up 320 tall and arbitrarily wide, and the scroll view
  pans across it.
- `TGScaleImage` to that size, set the scroll view's `contentSize`/`contentOffset` with the same
  `+ svH − 320` and `+12` rules as the shutter path.
- Enter Editing **unanimated** (`:533`), show the colour fade at full alpha, dismiss the picker, restore
  the status bar.
- Off the video queue: pause and detach the camera, build a `GPUImagePicture`, `convertYUV = false`,
  `kGPUImageNoRotation`, `fillMode = kGPUImageFillModeReal`, process, then on the main queue hide the
  fading image, insert the GPU view at index 0 if needed, and `fadeInCamera`.

Cancel from the picker (`:592-610`) shows the colour fade, returns to Camera state unanimated, restarts
the camera, dismisses, restores the status bar.

Both paths finish with `restoreWindowLayout` (`:612-631`): a double `dispatch_async` to the main queue
that calls `[TGViewController attemptAutorotation]`, forces the status bar orientation back to the root
controller's, and then **manually re-seats the root navigation bar's `origin.y` to the status bar
height**. This is pure damage repair — `UIImagePickerController` presented from a
`UIWindowLevelStatusBar + 1` window on iOS 5/6 left the app's navigation bar 20 pt out of place.
If we ever present a picker from an overlay window, we inherit this bug and this fix.

### Lifecycle

- `init` (`:144-155`): `wantsFullScreenLayout = true`, registers for
  `UIApplicationDidEnterBackgroundNotification` → `pauseCamera` and
  `UIApplicationWillEnterForegroundNotification` → `resumeCamera` (`:1275-1283`).
- `viewWillAppear` → `resumeCamera`; `viewWillDisappear` → `pauseCamera`; `viewDidDisappear` →
  `stopCamera` **only if `_isDismissed`** (`:364-395`).
- Portrait only: `shouldAutorotate` returns false and
  `shouldAutorotateToInterfaceOrientation:` accepts only portrait (`:354-362`).
- `currentCameraPosition` is a **file-scope static** defaulting to `AVCaptureDevicePositionBack`
  (`:64`), so the front/back choice survives the controller's lifetime for the whole app session.
- `startCamera` (`:1041-1098`) picks the session preset by device memory:
  `deviceMemorySize() > 300 || !TGIsRetina() ? AVCaptureSessionPresetPhoto : AVCaptureSessionPresetiFrame960x540`.
  **On a 256 MB Retina device — the iPhone 4 and the 4S sit either side of this line; the 4S has 512 MB
  so it gets full Photo preset, the iPhone 4 gets 960×540** — the preview and the capture drop to
  960×540 to survive memory pressure. Directly relevant to our target hardware.
- `reverseButtonPressed` (`:439-469`) disables the whole view, flips the static, then on the video
  queue: `ignoreFrames = true`, pause, drop the `adjustingFocus` observer, `rotateCamera`, re-add the
  observer, `ignoreFrames = false`, resume, `updateFlashIcon`, re-enable interaction on the main queue.
  There is no flip animation of any kind — the preview just cuts.
- The commented-out `TGRemoteImageView` memory-cache purge at `:368-369` and `:390` shows the intent:
  drop the image cache while the camera is up, restore it afterwards. Shipped commented out.

### Exit animation (`dismissToRect:...`, `:397-424`)

If `toRectInWindowSpace.size` is zero, **nothing happens** — the window's plain 0.3 s alpha fade
(`TGCameraWindow.m:86-98`) is the whole dismissal. Otherwise:

1. `_fadingImageView` gets `fromImage`, identity transform, frame `(0, topPanelH, 320, 320)` — the
   preview square exactly — alpha 1, unhidden.
2. `TGImageTransitionHelper beginTransitionOut:` flies it to the target rect above `aboveView`,
   `keepAspect:false`.
3. GPU view and both camera panels hidden; root background → `clearColor`.
4. Editing panels fade out over **0.2 s**.
5. The window schedules its own hide at **0.3 s** and then `makeKeyWindow` on the app window
   (`TGCameraWindow.m:102-111`).

So the photo appears to fly out of the camera and land in the avatar circle, while the chrome dissolves
slightly faster than the window.

## 5. Our port

We have **no equivalent of this controller, and correctly so** — we match the shipped behaviour, not the
dead one.

Our camera entry points:

- `iTgLegacy/src/TGChatViewController.m:4757-4760` builds an attach action sheet whose first entry is
  `@"Take Photo"`, gated on `cameraAvailable` (`:4743-4746`). `takePhoto` (`:6345-6353`) presents a stock
  `UIImagePickerController`, `sourceType = Camera`, `mediaTypes = @[kUTTypeImage]`, no `allowsEditing`.
- `iTgLegacy/src/TGProfileViewController.m:420` — action sheet `@"Take Photo"` / `@"Choose Photo"`;
  `:428-437` picks the source and sets `allowsEditing = NO`.
- `iTgLegacy/src/TGSettingsViewController.m:2765-2790` — same pair for the own-profile photo.

Differences a user could see, against the shipped 2013 original:

1. **`allowsEditing`.** The original set `imagePicker.allowsEditing = true` for the *avatar* camera path
   (`TGProfileController.m:3192`) and for the login avatar (`TGLoginProfileController.m:530-533`), which
   gave the user the system square-crop step before the photo became an avatar. Ours sets
   `allowsEditing = NO` in `TGProfileViewController.m:437`, and `TGSettingsViewController.m:2788-2790`
   does not set it at all (defaults to NO). Result: our avatars are cropped by whatever our own code
   does downstream, with no user control and no preview. **Change: set `allowsEditing = YES` on the
   avatar paths only, and read `UIImagePickerControllerEditedImage` first, falling back to
   `OriginalImage`** — our `TGStoriesViewController.m:3804-3806` already does exactly that fallback and
   is the pattern to copy. The chat attach path should stay `NO`; the original's chat send did not crop.
2. **Action sheet contents.** The original avatar sheet had a third option,
   `TGLocalized(@"Conversation.SearchWebImages")` (`TGProfileController.m:3071`), between "Choose Photo"
   and Cancel. Ours (`TGProfileViewController.m:420`) offers only the two. This is a missing feature, not
   a metric bug; worth recording but arguably fine to omit.
3. **Silent no-op on unavailable camera.** The original returned without feedback if the camera source
   was unavailable *after* the user tapped "Take Photo" (`TGProfileController.m:3181-3182`) — it still
   showed the button. Ours hides the button up front (`TGChatViewController.m:4758-4759`,
   `TGProfileViewController.m:431`). Ours is better and I would keep it; note the divergence.
4. **`endEditing` before presenting.** The original did `[self.view endEditing:true]`
   (`TGProfileController.m:3184`) before presenting the picker. Our chat `takePhoto`
   (`TGChatViewController.m:6345`) does not dismiss the keyboard first, so on a 4S the picker animates up
   over a still-shown keyboard and the keyboard reappears on return. **Change: add
   `[self.view endEditing:YES]` at the top of `-takePhoto`.**
5. **JPEG quality.** Ours encodes outgoing photos at **0.85** (`TGChatViewController.m:6360`,
   `stageImageForSending:`). The original's camera path used **0.5** (`TGCameraController.m:964`). Since
   the original's *shipped* path went through a different uploader this is not a strict mismatch, but
   0.85 on a 4S over EDGE is a real user-visible slowness. Worth a deliberate decision rather than an
   accident.

None of the custom-camera chrome (dark tiled bars, 320-square preview, blue Send button, focus reticle)
exists in our port, and it should not, unless we consciously decide to build the 2013 camera that
Telegram itself never shipped.

## 6. What became of it

### Modern client (`Telegram-iOS`)

The idea survived and won. `Telegram-iOS/submodules/Camera/Sources/` is a full Swift camera stack —
`Camera.swift`, `CameraDevice.swift`, `CameraInput.swift`, `CameraOutput.swift`, `CameraPreviewView.swift`,
`PhotoCaptureContext.swift`, `VideoRecorder.swift`, plus `CameraRoundVideoFilter.swift` and
`CameraRoundLegacyVideoFilter.swift` for video messages. Telegram never went back to
`UIImagePickerController`: the 2013 file was the first attempt at a strategy that took a decade to pay
off. The concerns are the same ones this file mixes together — device, input, output, preview, capture —
now separated into one file each. The GPUImage dependency is gone; preview is `AVCaptureVideoPreviewLayer`
plus Metal filters.

### `twelve` (Objective-C fork on the original's lineage)

`twelve/submodules/LegacyComponents/LegacyComponents/TGCameraController.h/.m` (66 / 2465 lines) is the
recognisable descendant: still a `TGCameraControllerWindow` overlay window, still an intent-driven
full-screen camera. What the intervening years added:

- **Intents** instead of one purpose: `Generic`, `Passport`, `PassportId`, `PassportMultiple`, `Avatar`
  (`TGCameraController.h:13-19`). The avatar case that was the *only* case in 2013 is now one enum value.
- **Video, multi-capture, captions, grouping, timers**: `allowCaptions`, `allowGrouping`,
  `inhibitMultipleCapture`, `inhibitMute`, `hasTimer`, and separate `finishedWithPhoto` /
  `finishedWithVideo` / `finishedWithResults` blocks. Feature-forced, all of it.
- **Blocks replaced `ASWatcher`.** The 2013 string-keyed `actionStageActionRequested:@"cameraCompleted"`
  with an `NSDictionary` payload became typed `void(^finishedWithPhoto)(...)`. Change of taste, and the
  right one — our port should prefer typed callbacks over string actions here.
- **Interface split out**: `TGCameraMainPhoneView` / `TGCameraMainTabletView` behind a `TGCameraMainView`
  base (`TGCameraController.m:19, 106, 289-295`), with the shutter, flip and flash as their own classes.
  The 2013 file built every button inline in `loadView`; the fork could not, once there were two form
  factors and rotation (`setInterfaceOrientation:animated:`, `:290`).
- **Capture moved behind `PGCamera`** (`:150`) and preview behind `TGCameraPreviewView` (`:217-221`) —
  the same separation the Swift client later made, arrived at independently.
- `+ (bool)useLegacyCamera` (`TGCameraController.h:64`) — the fork still carried a fallback path, which
  is the honest admission that a custom camera is hard to get right on old hardware. Relevant to us.

The through-line: the 2013 file already contains the whole design (overlay window, fixed-square preview,
two-state camera/editing chrome, tap-to-focus with a reticle, a fly-to-target dismissal). What it lacked
was any separation between the camera, the preview, and the chrome — and that is exactly what both
successors spent their effort on.

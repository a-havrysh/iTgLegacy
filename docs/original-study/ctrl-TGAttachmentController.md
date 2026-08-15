# TGAttachmentController — the attachment menu of Telegram iOS 1.1 (21024)

## 0. The class does not exist

There is no `TGAttachmentController`, and no `TGAttachmentPanel`, `TGAttachmentSheet` or
`TGAttachmentMenu` anywhere in the 2014 tree. A full-tree search for `*Attach*` returns only
model classes (`TGImageMediaAttachment` and friends), image resources, and one controller-level
consumer.

In 1.1 the attachment menu is **not a component at all**. It is roughly forty lines inlined into
`TGConversationController`, and it is a plain `UIActionSheet`. Everything below documents that
code plus the attach button that opens it, which together are the real "attachment controller"
of the original:

- `TelegraphKit/TelegraphKit/TGConversationController.mm:1003-1012` — the attach button
- `TelegraphKit/TelegraphKit/TGConversationController.mm:2197-2216` — `attachButtonPressed:`
- `TelegraphKit/TelegraphKit/TGConversationController.mm:7678-7702` — sheet dismissal routing
- `TelegraphKit/TelegraphKit/TGConversationController.mm:2300-2330, 2798-2842` — the five destinations
- `Telegraph/Telegraph/TGTelegraphConversationCompanion.mm:4596-4638` — the artwork

All line references in this document are relative to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`.

This matters for our port: anyone looking for a designed attachment surface in 1.1 will not find
one, and should not invent one. The 2013 attachment experience *is* the system action sheet.

---

## 1. The attach button

Constructed once in `loadView`, `TGConversationController.mm:1003-1012`:

```
_attachButton = [[UIButton alloc] initWithFrame:CGRectMake(6, 7 + retinaPixel, 29, 30)];
```

- Frame `(6, 7 + retinaPixel, 29, 30)` inside `_inputContainer`. `retinaPixel` is the half-point
  nudge used throughout the input bar; the same `7 + retinaPixel` y-origin is used by the send
  button at `:1014`, so the two buttons share a baseline. The input container's own base height is
  `_baseInputContainerHeight` (`:998`), and the white text field background starts at x=40
  (`:975`), i.e. exactly `6 + 29 + 5` — the button owns the left 35 points of the bar and leaves a
  5-point gutter before the field.
- `exclusiveTouch = true` (`:1004`) — you cannot press attach and send in the same touch sequence.
- `adjustsImageWhenDisabled = false` and `adjustsImageWhenHighlighted = false` (`:1009-1010`).
  The pressed state is a **separate asset**, never a tint or an alpha dim. This is the single
  most commonly mis-ported detail of the 2013 input bar.
- `autoresizingMask = FlexibleRightMargin | FlexibleTopMargin` (`:1007`): the button is pinned to
  the bottom-left of the input container, so when the field grows to multiple lines the button
  stays glued to the bottom rather than centring.
- Target `attachButtonPressed:` on `UIControlEventTouchUpInside` (`:1008`).

### Artwork

`Telegraph/Telegraph/TGTelegraphConversationCompanion.mm:4596-4616`:

- normal: `AttachBtn.png`
- highlighted: `AttachBtn_Pressed.png`

Both ship only as `@2x`: `Resources/AttachBtn@2x.png` and `Resources/AttachBtn_Pressed@2x.png`,
each **56 × 58 px = 28 × 29 pt**. Note the button frame is 29 × 30, i.e. one point larger in each
axis than the artwork; `UIButton` centres the image, so the drawn glyph sits at a half-point
offset which the `retinaPixel` in the y-origin cancels out on a 2x screen.

Both images are fetched through `dispatch_once` statics (`:4598-4604`) — loaded once per process,
never re-decoded per chat. Every one of the `TGConversationControllerCompanion` art hooks returns
`nil` in the base class (`TGConversationControllerCompanion.m:74-91`), so a companion that forgets
to override yields a **blank but still tappable** button. That is the original's degraded state:
invisible control, working hit area.

### The dead arrow

`_attachButtonArrow` (`TGConversationController.mm:393`) and
`setAttachmentArrowState:duration:` (`:4005-4032`) are **vestigial**. The property is never
allocated and never added to a superview — the only other reference is a single call from
`keyboardWillShow` (`:3917`) that transforms a nil view. The two assets it names,
`AttachArrowUp.png` and `AttachArrowDown.png` (`TGTelegraphConversationCompanion.mm:4618-4638`),
**do not exist in `Resources/`** (only `AttachBtn*`, `AttachmentImagePlaceholder`,
`AttachmentMapPlaceholder`, `AttachmentPhotoBubble*` are there).

The same is true of the whole `attachmentPanel*` family in the companion protocol
(`TGConversationControllerCompanion.h:80-90`: background, shadow, divider, camera/gallery/
location/audio images ×2 states). They are implemented in
`TGTelegraphConversationCompanion.mm:4729-4790+` — dark linen background, `LinenShadow.png`,
a horizontally stretchable `ShadowDivider.png` (cap width = half its width), `Camera.png` /
`Camera_Pressed.png`, `Gallery.png` / `Gallery_Pressed.png`, `Audio.png` / `Audio_Pressed.png` —
and the assets all exist, but **nothing in the tree ever calls them**. A grep for
`attachmentCameraImage` / `attachmentPanelBackground` outside the companion pair returns nothing.

Read together: Telegram had built, or was building, an in-app slide-up attachment panel on dark
linen with a rotating chevron on the attach button, and shipped 1.1 with it disabled in favour of
the system action sheet. Our port should treat this as evidence of intent, not as shipped design.
Do not reconstruct the linen panel and call it "the original".

---

## 2. The menu itself

`TGConversationController.mm:2197-2216`, in full behaviour:

1. `_currentActionSheet.delegate = nil` — any previously open sheet is orphaned first, so a
   double-tap cannot deliver a stale callback. The old sheet is not dismissed, only muted.
2. A fresh `UIActionSheet` with **nil title, nil cancel title, nil destructive title**. All buttons
   are added afterwards with `addButtonWithTitle:`, and the returned index is recorded in a
   `NSMutableDictionary` mapping `NSNumber(index) -> action string`. The sheet is therefore driven
   by *names*, not by index arithmetic — the original had already learned that lesson.
3. Five items, in this fixed order (`:2204-2208`), with `en.lproj/Localizable.strings`:
   | key | English | line in strings |
   |---|---|---|
   | `Common.TakePhotoOrVideo` | Take Photo or Video | `:52` |
   | `Common.ChoosePhoto` | Choose Photo | `:54` |
   | `Conversation.SearchWebImages` | Search Web Images | `:432` |
   | `Common.ChooseVideo` | Choose Video | `:55` |
   | `Conversation.Location` | Location | `:322` |
4. `Common.Cancel` ("Cancel", strings `:40`) added last and assigned to `cancelButtonIndex`
   (`:2209`).
5. `tag = TGConversationControllerAttachmentDialogTag` = **10003** (`:307`). Routing at `:7678`
   is by tag, since one delegate serves every sheet in the controller.
6. `showInView:self.view` — presented over the controller's view, not the window, so it sits under
   nothing and respects the controller's own rotation.
7. `_assetsLibraryHolder = [TGImagePickerController preloadLibrary]` (`:2215`). The **moment the
   menu opens**, the ALAssetsLibrary is spun up and held, so that by the time the user picks
   "Choose Photo" the library is already enumerating. On a 4S that is the difference between an
   instant picker and a two-second stall. The holder is released in the dismissal handler at
   `:7701`, whichever branch was taken including cancel.

### What the list is *not*

- No **Contact**, no **File/Document**, no **Music**, no **Poll**. Contacts could be received in
  1.1 (`TGContactMediaAttachment` exists) but there is no way to send one from this menu.
- The list is **static**. There is no capability filtering: "Take Photo or Video" is offered on a
  device with no camera, and `attachCameraPressed` simply returns without feedback
  (`:2300-2302`). On the iPad simulator or an iPod touch the row does nothing at all.
- There is no encrypted-chat variant of the menu. `_conversationCompanion.isEncrypted` gates
  *saving* a received photo to the camera roll (`:2578`), never the menu.

### Destinations

| action | method | behaviour |
|---|---|---|
| `takePhotoOrVideo` | `attachCameraPressed` `:2300` | camera check, `closeKeyboard`, `prepareStatusBarForCamera`, `UIImagePickerController` with `kUTTypeImage` + `kUTTypeMovie`, flash mode restored from the file-static `defaultFlashMode` (default `Auto`, `:2298`) and written back on dismissal (`:2790`) |
| `choosePhoto` | `attachGalleryPressed` `:2317` → `showImageGalleryPicker:false` | in-app `TGImagePickerController` + `TGImageSearchController` stack, not the system picker |
| `searchWeb` | `attachSearchWebPressed` `:2322` → `showImageGalleryPicker:true` | same stack, with `autoActivateSearch = true` so the search field is first responder on appear |
| `chooseVideo` | `attachVideoGalleryPressed` `:2822` | system `UIImagePickerController`, photo library, `kUTTypeMovie` only, `videoQuality = 640x480` |
| `location` | `attachLocationPressed` `:2798` | `TGMapViewController initInPickingMode`, wrapped in a `TGNavigationController`, presented modally, results delivered through `_actionHandle` as a watcher |

Two invariants worth copying:

- **Every** destination calls `[self closeKeyboard]` before presenting
  (`:2303, 2319/2333, 2800, 2810, 2823`). Never present a picker over a live keyboard.
- Photo capture goes through `prepareStatusBarForCamera` / `resetStatusBarAfterCameraCompleted`
  (`:2304`, `:2795`) because iOS 6's camera fights the app's status bar style.
- `attachVideoPressed` (`:2808`) — camera video capture at 640×480 — is written but **unreachable
  from the menu**; nothing dispatches to it. Camera video arrives via the combined
  `takePhotoOrVideo` picker instead.

---

## 3. Our port

Our equivalent is inlined the same way, in `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGChatViewController.m`:

- button: `:3021-3037`
- `attachTapped`: `:4757-4782`
- routing: `:4982-5004`
- second page `showAttachMore`: `:5006-5024`

### What is right

- The button frame `CGRectMake(6, 7 + retinaPixel, 29, 30)` (`:3022`) is byte-for-byte the
  original's `:1003`, including the `retinaPixel`.
- `exclusiveTouch` and `adjustsImageWhenHighlighted = NO` (`:3023, 3030`) match `:1004, 1010`.
- `AttachBtn@2x.png` and `AttachBtn_Pressed@2x.png` in `iTgLegacy/images/` are **md5-identical**
  to the originals (`06113986122e604ab827db17a17539f7`), 56 × 58 px. Nothing to do.
- The vector fallback in `TGIcons.m:320-333` (a stroked plus, width 3, inset 6) only fires when
  `TGArtwork(@"AttachBtn")` is nil, so on a normal build the real artwork wins. Fine.
- `UIActionSheet` with nil title, buttons appended, cancel last, `tag`-based routing, and dispatch
  by button *title* rather than index — structurally the same discipline as the original's
  index→action mapping.

### Defects, in order of visibility

1. **No keyboard dismissal before any picker.** `pickMedia` (`:6471-6482`), `captureVideoRound:`
   (`:4784`), `pickContact`, `pickMusic` all present straight away. The original closes the
   keyboard first at `TGConversationController.mm:2303, 2800, 2810, 2823`. On iOS 6 this produces
   a visible keyboard-under-modal flicker and, on the 4S, a dropped first frame. Add a
   `[self.inputField resignFirstResponder]` (or the existing close-keyboard path) at the top of
   every attach destination.
2. **No asset-library warm-up.** The original preloads at the instant the sheet opens
   (`:2215`) and releases it on dismissal (`:7701`). We do nothing, so the first
   `UIImagePickerController` presentation on a 4S pays the full library spin-up. Even without
   `TGImagePickerController`, touching `ALAssetsLibrary`/`PHPhotoLibrary` when `attachTapped`
   fires and holding it until the sheet resolves would recover most of that.
3. **No status-bar preparation around the camera.** Original `:2304` / `:2795`. Without it the
   status bar style can be left wrong after camera dismissal on 6.1.
4. **No video quality cap.** Original pins `UIImagePickerControllerQualityType640x480` for both
   video paths (`:2818, 2829`). Ours (`pickMedia`, `:6476-6481`) leaves the default, which on a 4S
   library means uploading full 1080p captures. This is user-visible as a long upload, and
   arguably a defect independent of fidelity.
5. **`pickMedia` fails silently when the library is unavailable** (`:6472-6474`) — same silent
   return as the original's camera check, so this one is *consistent* with 1.1 rather than a
   regression; noted so nobody "fixes" it.
6. **Menu length.** Ours offers up to ten items on page one plus a "More" page of five to seven
   (`:4758-4776`, `:5006-5024`). That is a deliberate and correct application of the project's
   rule — modern interaction model, 2013 clothing — but be aware of the physical consequence the
   original avoided: on a 480-point screen in landscape, a `UIActionSheet` with ten buttons plus
   cancel scrolls, and on iOS 6 the scrolling sheet is ugly. Original: five plus cancel, which
   never scrolls in either orientation. If we want to stay honest to the look, the first page
   should be trimmed toward six or seven and the rest pushed to "More". Conditional rows
   ("Take Photo" only when a camera exists, "Paste Photo" only when the pasteboard holds one,
   `:4759, 4766`) already keep the common case shorter, and that conditionality is an improvement
   over the original's dead camera row — keep it.
7. **The stale-sheet guard is missing.** The original nils the previous sheet's delegate first
   (`:2199`). We reuse `self` as delegate for ~35 tagged sheets (`:4696-4735`) and never mute an
   outgoing one; a fast double-tap can deliver a callback from a sheet the user thinks is gone.
   Cheap fix, real bug.
8. Cosmetic: our sheet titles are hard-coded English literals (`:4759-4776`) where the original
   goes through `TGLocalized`. Not visible today, but the original's exact strings are worth
   matching verbatim where the item is the same: "Take Photo or Video" (we say "Take Photo" and
   "Photo or Video" as two rows), "Choose Photo", "Choose Video", "Location", "Cancel".

---

## 4. What this became

### Modern client (`Telegram-iOS/submodules/AttachmentUI`)

The concept was promoted from forty inline lines to its own module:
`AttachmentController.swift`, `AttachmentPanel.swift`, `AttachmentContainer.swift`. Three changes
matter to us conceptually:

- The destinations are a **typed enum**, `AttachmentButtonType` (`AttachmentController.swift:23-38`):
  `gallery, file, location, todo, quickReply, contact, poll, app(AttachMenuBot), gift, sticker,
  emoji, audio, link, richText, standalone`. The list is now data supplied by the caller, not a
  hard-coded sequence — forced by bot mini-apps (`app(AttachMenuBot)`), which can add entries at
  runtime. A fixed list simply could not express that.
- The presentation is a **horizontal row of icon buttons above a sheet that hosts a full
  controller**, not a vertical list of words. Metrics: 30 × 30 pt icons, 69 pt small button width
  (`AttachmentPanel.swift:38-39`), buttons laid out by dividing the available width
  (`:2021-2060`). This is a change of taste enabled by bigger screens; on a 320-pt screen the icon
  row would fit five items at most, which is why 2013 could not have done it.
- The sheet **contains the picker** rather than presenting it modally, so choosing "gallery"
  swaps content in place. That is the real conceptual leap, and the one thing we cannot copy on
  6.1 with `UIActionSheet`.

### twelve (`twelve/Telegraph/TGModernConversationController.mm` + `TGAttachmentSheet*`)

The Objective-C lineage shows the intermediate step, and it is the most instructive of the three.
`TGAttachmentSheetView` / `TGAttachmentSheetWindow` / `TGAttachmentSheetButtonItemView`
(`Telegraph/TGAttachmentSheetView.h`, `TGAttachmentSheetButtonItemView.h`) are a hand-built
action sheet made of composable *item views* — exactly the "linen panel" the 2014 code had stubbed
out and abandoned. It later became `TGMenuSheetController`, which is what the shipped code
actually uses (`TGModernConversationController.mm:9370, 9398, 10002`).

Two consequences the item-view architecture bought:

- **A live media carousel as the first item.** `TGAttachmentCarouselItemView`
  (`TGModernConversationController.mm:7089`) puts recent photos, scrollable and selectable, at the
  top of the menu, capped at `TGAttachmentDisplayedAssetLimit = 500`
  (`LegacyComponents/TGAttachmentCarouselItemView.m:49`). You send a recent photo without ever
  entering a picker. A `UIActionSheet` cannot host a collection view; this feature *forced* the
  rewrite.
- **Sub-menus in place and long-press alternates.** "File" replaces the sheet's contents with
  iCloud Drive / Dropbox / Photo-or-Video rather than pushing a modal
  (`_displayFileMenuWithController:`, `:9969-10070`), gated on `iosMajorVersion() >= 8`; below
  that it falls straight through to the media picker (`:10066-10069`). Long-pressing "Photo or
  Video" opens the web image picker (`:9382-9394`) — the original's dedicated "Search Web Images"
  row, demoted to a gesture once the list got crowded. It also keeps a plain `TGActionSheetAction`
  fallback path (`:9524-9525`) for contexts where the sheet is not available.

So the evolution runs: five words in a system sheet (2014) → composable item views with a carousel
(twelve) → typed button row hosting embedded controllers (modern). The first jump was forced by a
feature (recent-photo carousel, cloud file sources); the second was forced by bots and enabled by
screen size. Our port sits at the first stage and should stay there — but twelve's "long-press for
the rarer variant" and "second page for the rare items" are both cheap on 6.1 and we already use
the second one.

---

## 5. Open questions

- Whether `AttachArrowUp.png` / `AttachArrowDown.png` existed in the shipped 1.1 bundle and were
  merely absent from this source snapshot's `Resources/` folder. The code references them; the
  files are not in the tree. I lean toward "cut before release", since the arrow view is never
  instantiated either, but I cannot prove the bundle contents from source alone.
- Whether the dark-linen attachment panel (`attachmentPanelBackground` = `darkLinenBackground`,
  `TGTelegraphConversationCompanion.mm:4730`) ever shipped in a public build between 1.0 and 1.1.
  Every hook is implemented and every asset is present, which is unusual for pure dead code; it
  may have been live in an earlier version and disabled for 1.1.
- The exact `retinaPixel` value is defined outside the files read here, so the sub-point offsets
  in section 1 are described relative to it rather than absolutely.

# Interaction patterns — 2013 Telegram iOS

Law for every new screen. Values are taken from the 1.1 source
(`telegram_iphone.src`), not from memory. Points, not pixels: the `@2x` assets
are twice the numbers quoted here.

The governing rule of this chapter: **2013 Telegram never invented a container
when the system already had one.** Choices, confirmations and errors go through
`UIActionSheet` and `UIAlertView`. Telegram only drew its own control where the
system had nothing — the long-press bubble menu, the blocking progress window,
the selection checks. Do not add a custom sheet, a custom alert, a bottom sheet,
a card, a toast or a HUD unless this document names one.

**Correction, binding on every agent and superseding any other document in this
repo:** it is false that iOS 6 cannot do gesture-driven interaction, and false
that navigation therefore has to be buttons. iOS 6 has the whole
`UIGestureRecognizer` family and the original 1.1 app used it heavily. See §10.
It is equally false that the A5 cannot encode video: the iPhone 4S records
1080p H.264 at 30 fps in hardware, `AVCaptureSession` /
`AVCaptureMovieFileOutput` / `AVAssetWriter` all exist on iOS 6, and the
original ships `Telegraph/Telegraph/TGCameraController.m`. Recording and sending
video works, and round video notes — short H.264 clips — work. What does not
work is HEVC/H.265, VP9 and AV1, and heavy transcoding of long files is slow
rather than impossible. Never write a design rule, a control, or a line of user
visible copy premised on either of these two false claims.

---

## 1. Presenting a choice — `UIActionSheet`

Every "which one?" is an action sheet built button-by-button, `title:nil`,
delegate `self`, all four other arguments `nil`, then `addButtonWithTitle:` in
order, then Cancel last with its index assigned to `cancelButtonIndex`.
Verbatim shape (`TGProfileController.m:3068`):

```objc
_currentActionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
[_currentActionSheet addButtonWithTitle:TGLocalized(@"Common.TakePhoto")];
[_currentActionSheet addButtonWithTitle:TGLocalized(@"Common.ChoosePhoto")];
_currentActionSheet.cancelButtonIndex = [_currentActionSheet addButtonWithTitle:TGLocalized(@"Common.Cancel")];
[_currentActionSheet showInView:self.parentViewController.view];
```

Rules:

- **Title is `nil`** for a plain choice. A title string appears only when the
  sheet acts on a named object — the link sheet passes the URL itself as the
  title (`TGConversationController.mm:7330`). Never write a sentence as the title.
- **Cancel is always the last button** and always `TGLocalized(@"Common.Cancel")`.
- **Show in the largest containing view**, never in `self.view` when a tab bar or
  navigation bar is present: `showInView:self.parentViewController.view` when the
  parent is a `UITabBarController`, `showInView:self.navigationController.view`
  from a list controller, `self.view` otherwise. Getting this wrong clips the
  sheet behind the tab bar.
- Keep the live sheet in an ivar named `_currentActionSheet` and dismiss it in
  `viewWillDisappear`. Two sheets at once is a bug.
- More than one sheet per controller: set `_currentActionSheet.tag` to a per-screen
  constant (`TGLogoutConfirmationActionSheetTag`, `TGDeleteContactActionSheetTag`)
  and switch on the tag in the delegate. When the button set is dynamic, map index
  → action string in an `NSMutableDictionary` (`actionSheetMapping` in
  `TGProfileController`) instead of comparing indices by hand.

**In our repo use `TGActionSheet`** (`src/TGActionSheet.h`). It is a `UIActionSheet`
subclass that takes `TGActionSheetAction` objects carrying a string action id and
a `TGActionSheetActionType` (`Generic` / `Cancel` / `Destructive`) and calls a
block. It reproduces the ordering rules above; do not hand-roll a sheet.

A choice with more than about six options is not a sheet: it is a pushed grouped
table with a checkmark (see §4).

## 2. Destructive confirm — action sheet with `destructiveButtonIndex`

There is no "are you sure?" alert for destruction in 2013 Telegram. Destruction
is confirmed by a red button in an action sheet. `destructiveButtonIndex` is
assigned the return of `addButtonWithTitle:`, so the red row sits in list order
and Cancel still comes last:

```objc
_currentActionSheet.destructiveButtonIndex = [_currentActionSheet addButtonWithTitle:TGLocalized(@"Profile.DeleteContact")];
_currentActionSheet.cancelButtonIndex = [_currentActionSheet addButtonWithTitle:TGLocalized(@"Common.Cancel")];
```

Rules:

- **Exactly one red button.** If two destructive things are offered together
  (chat list swipe: Clear History + Delete Chat), the *more* destructive one is
  the red one and the milder one is a plain button above it
  (`TGDialogListController.mm:1678` — Clear History plain, Delete Chat red).
- Logout uses the two-argument convenience form
  (`destructiveButtonTitle:TGLocalized(@"Settings.Logout")`) because there is
  nothing else in the sheet.
- The button title **names the act** ("Delete Contact", "Leave Group",
  "Stop Uploading"), never "OK" or "Yes".
- A destructive confirm never carries an explanatory paragraph. If the user needs
  a sentence of warning, it is a `UIAlertView` (§7 shape) with the destructive verb
  as the non-cancel button — but prefer the sheet.
- Reversible destruction may skip confirmation entirely and use
  `TGSnackbar` (`src/TGSnackbar.h`): the act runs when the count expires,
  UNDO cancels. Use snackbar **or** a sheet, never both for one act.

## 3. Multi-select

Three distinct multi-select idioms; pick by surface.

**a. Rows in a list (messages, contacts).** Enter editing mode; a round check
glyph slides in from the left. Metrics from
`TGConversationMessageItemView.mm:3110`: the check view is **35×35**, at
`x = 2` when editing and `x = -35` when not, vertically
`(contentHeight - 35) / 2 - 1`. Images: `MessagesUnchecked.png` /
`MessagesChecked.png` (70×70 @2x → 35pt). Contacts use `Contact_Check.png` (29pt)
and `Contact_Checked.png` (30pt). Content beside it shifts left by 32pt while
editing (`TGDialogListCell.m:1309` moves the date by `-32`).

**b. Thumbnails in a grid (image picker).** A check button sits in the tile
corner, `TGImagePickerCheckButton` with a 49×49 `_checkView`, images
`ImagePickerSelect.png` / `ImagePickerSelect_Checked.png` (98×98 @2x); the small
variant is `ImagePickerThumbnalSelect*.png` (33pt). The tap animation is fixed
and must be reproduced: press → scale 0.8; on check → 0.12 s ease-out to 1.16,
then 0.08 s ease-in to 1.0; on uncheck → 0.16 s ease-out back to identity.

**c. Selection mode chrome.** While a selection is active the screen grows a
bottom action panel of flat text buttons separated by 1pt separator image views
(`TGConversationActionsPanel`), and the navigation bar's right button becomes a
Cancel/Done `TGToolbarButton`. Never a floating action button, never a badge
count bubble. The count goes in the title text of the navigation bar.

## 4. Modal form

A modal form is **a `UINavigationController` presented with
`presentViewController:animated:completion:`**, containing a grouped
`UITableView`. It is never a popover, never a partial-height sheet.

Shape (`TGPhoneLabelController.m`):

- `self.titleText` set to a `TGLocalized` title.
- Left bar item: `TGToolbarButton` of type `TGToolbarButtonTypeGeneric`, text
  `Common.Cancel`, `minWidth = 59`, `sizeToFit`, wrapped in
  `[[UIBarButtonItem alloc] initWithCustomView:button]`.
- Right bar item, when the form commits something: `TGToolbarButtonTypeDone`
  (the blue capsule), text `Common.Done`. A form with nothing to commit has no
  right button — selecting a row dismisses it.
- `self.view.backgroundColor = [[TGInterfaceAssets instance] linesBackground]`;
  table style `UITableViewStyleGrouped`, `rowHeight = 44`,
  `backgroundView = nil`, `backgroundColor = [UIColor clearColor]`.
- Selection is shown by a checkmark image on the right of the row
  (`ListCheck.png`, 13×14pt), not by `UITableViewCellAccessoryCheckmark` styling
  changes and not by a switch.
- Explanatory text under a section is a footer cell in the style of
  `TGCommentMenuItemView`: centered, `systemFontOfSize:14`, colour `0x697487`,
  shadow colour `0xdae0e8` at offset `(0, 1)`, `numberOfLines = 0`, inset 1pt
  horizontally and 7pt vertically.
- A row that performs an action rather than editing a value is a
  `TGFlatActionCell`-style row: `boldSystemFontOfSize:16`, colour **`0x0779d0`**,
  highlighted colour white, title at `x = 53`, `y = 12`, height 20, disclosure
  arrow 12pt from the right edge at `y = 14`. A destructive row of the same kind
  uses the same metrics with red text.

**In our repo**, build the header buttons with
`+[TGIcons headerButtonWithTitle:bold:target:action:]` and style an existing
button with `+[TGIcons styleHeaderButton:]`. Bold = the commit side (Done/Save),
plain = Cancel.

## 5. Progress

Three kinds, chosen by whether the user is blocked.

**a. Blocking, indeterminate → `TGProgressWindow`** (`TGProgressWindow.h`,
`show:`, `dismiss:`, `dismissWithSuccess`). A `UIWindow` at
`UIWindowLevelStatusBar` with a **100×100** centred container: background
`ProgressWindowBackground.png` (32×32 @2x → 16pt) stretched with
`stretchableImageWithLeftCapWidth:(w/2) topCapHeight:(h/2)`, and a
`UIActivityIndicatorViewStyleWhiteLarge` centred with integral offsets. Fade in
and out over **0.3 s** on `containerView.alpha`. Success replaces the spinner
with `ProgressWindowCheck.png` (39×40pt), waits **0.5 s**, then fades out over
0.3 s. Never write a different HUD.

**b. Determinate over media → `TGCircularProgressView`.** Annular by default:
`lineWidth = 4`, radius `(width - 13) / 2`, start angle `-π/2`, clockwise, white
stroke, line cap round until progress reaches 1.0 where it becomes square. The
disc behind it is `CircularProgressBackgroundBig.png` (50pt).

**c. Determinate in a row → `TGLinearProgressView`**, built with
`initWithBackgroundImage:progressImage:` from `LinearProgressBackground.png`
(20×9pt) and `LinearProgressForeground.png` (7×7pt). The fill inset is 1pt on
each side (`width - 2`), and the fill is hidden (alpha 0) while narrower than the
foreground image so a stub never shows. Animate with
`setProgress:animationDuration:` using linear curve.

Rules: an operation that will finish in under ~1 s shows **nothing**. An
operation the user can walk away from (upload, download) shows b or c inline and
never blocks. Only a modal act with no inline place to live (logout, creating a
chat, applying settings) gets `TGProgressWindow`. A cancellable long operation
offers cancellation via a destructive action sheet, not a stop button
(`Profile.StopImageUpload`, `TGProfileController.m:2988`).

## 6. Empty state

Verbatim from `TGDialogListController.mm:885`. Reproduce this layout for every
empty list:

- Container `UIView`, width **250**, inserted **below** the table view; the table
  is then `hidden = true` while the model is empty.
- Icon `UIImageView` at the top, horizontally centred in the 250 container
  (`NoMessages.png`, 102×91pt).
- Title `UILabel`: `boldSystemFontOfSize:15`, colour **`0x8b97a5`**, clear
  background, `sizeToFit`, centred, `y = icon.bottom + 21`.
- Body `UILabel`: `systemFontOfSize:14`, colour **`0x8b97a5`**,
  `UITextAlignmentCenter`, `UILineBreakModeWordWrap`, `numberOfLines = 0`,
  wrapped with `sizeThatFits:CGSizeMake(232, 1000)`, `y = title.bottom + 8`.
- Container height = body bottom; container centred in the view both axes
  (`floorf((viewWidth - 250) / 2)`, `floorf((viewHeight - h) / 2)`), recomputed on
  every layout pass.
- No button in the empty state. No illustration other than one flat icon.
- Use `UITextAlignmentCenter` / `UILineBreakModeWordWrap`, not the
  `NSTextAlignment` spellings — iOS 6.1.3.

## 7. Error — `UIAlertView`

Every error is a one-button alert with **`title:nil`**, the message carrying the
text, `delegate:nil`, and `cancelButtonTitle:TGLocalized(@"Common.OK")`:

```objc
[[[UIAlertView alloc] initWithTitle:nil message:TGLocalized(@"Profile.ImageUploadError") delegate:nil cancelButtonTitle:TGLocalized(@"Common.OK") otherButtonTitles:nil] show];
```

Rules:

- **Never set a title.** Not "Error", not the app name. 30-odd call sites in the
  original, all `title:nil`.
- One button, `Common.OK`. No "Retry" button: a retry is offered by leaving the
  screen in a state the user can tap again.
- Never show a raw server string or a numeric code. Map to a localized key.
- A yes/no question that is not destructive is the two-button alert with
  `cancelButtonTitle:Common.No otherButtonTitles:Common.Yes`
  (`TGForwardTargetController.m:262`) — note **No is the cancel button, Yes is on
  the right**. Where the choice is commit/abandon rather than yes/no, use
  `Common.Cancel` / `Common.OK` in that order (`TGChatSettingsController.m:627`).
- **`UIAlertController` does not exist on iOS 6.1.3.** Use `UIAlertView` only.
- In our repo use `TGAlertView` (`src/TGAlertView.h`), which wraps the above in a
  completion block and keeps itself alive; a plain `UIAlertView` with a block
  captured elsewhere will be deallocated.

## 8. Long-press menu — `TGMenuView`

The bubble menu is Telegram's own control and is the only correct answer for
acting on a message. It is a **single horizontal row of text buttons** with an
arrow pointing at the target — not a vertical list, not an action sheet.

Metrics (`TGMenuView.m`):

- Height **41**. Each button's width is
  `[title sizeWithFont:font].width + 34`; the first and last button get **+1**.
- Title font `boldSystemFontOfSize:14`, white; disabled white at 0.5 alpha;
  title shadow `0x000000` at 0.8 alpha, offset `(0, -1)`; highlighted/selected
  shadow `0x186bcb` at 0.6.
- Backgrounds: `MenuButtonLeft.png` stretched with
  `stretchableImageWithLeftCapWidth:(w - 1) topCapHeight:0`,
  `MenuButtonRight.png` with cap width 0, `MenuButtonCenter.png` with cap width
  `w/2`. Interior buttons use the centre image for all three slices. First button
  gets `titleEdgeInsets.left += 2`, last `+= 2` on the right.
- 1pt `MenuButtonSeparator.png` between buttons; `MenuButtonTopLine.png` /
  `MenuButtonBottomLine.png` hairlines across the top and bottom of each button,
  each with a `_Highlighted` variant switched together with the button.
- Arrow: `MenuArrowTop.png` / `MenuArrowBottom.png` plus `_Highlighted`
  variants; the arrow highlights only when the button it sits under is
  highlighted.
- Placement: centred on the target rect, clamped to **4pt** from either screen
  edge; preferred position is above with `y = rect.origin.y - height - 14`; if
  that is under 2pt it flips below with `y = rect.maxY + 17`; if that also does
  not fit it centres vertically with no arrow flip.
- Presentation animation, exactly: anchor point at the arrow, alpha to 1
  immediately, then **0.142 s** ease-out to scale 1.07, **0.08 s** to 0.967,
  **0.06 s** ease-out to identity. Rasterize the layer at screen scale during the
  animation.
- Re-opening is suppressed within **0.4 s** of the last hide
  (`_lastMenuHideTime + 0.4`).
- The pressed message is put into a context-selected state
  (`setIsContextSelected:true`) so it stays visibly the subject.

Action ordering in the original, and the order new entries must respect:
`Copy` (or `Forward` when there is no text) → `Delete` → `Select`.

**In our repo use `TGPopupMenu`** (`src/TGPopupMenu.h`):
`+showItems:atPoint:inView:onChoice:` with dictionaries carrying `title`, an
optional `icon` name that `+[TGIcons menuGlyphNamed:]` answers to, and optional
`destructive`. `+[TGPopupMenu dismiss]` on screen teardown. Our menu is the
vertical card variant; keep the same placement clamp, the same suppression
window, and the same action ordering.

## 9. Swipe action and inline expansion

**Swipe-to-delete** is not the system red slab. `TGDialogListCell` draws its own
button: `ListDeleteButton.png` (18×30pt, plus `_Highlighted`), frame
`(width - 10 - 61, 20, 61, 31)`, label rendered once into an image using
`boldSystemFontOfSize:13` in white with a shadow of `0xa30f0a` at 0.2 alpha,
offset `(0, -1)`, centred horizontally in the button at `y = 7`. The button grows
from a 2pt-wide stub at the right edge. Driven by `TGSwipeGestureRecognizer` and
`TGActionTableView` (`src/TGActionTableView.h` — `actionCell`,
`enableSwipeToLeftAction`, and the `TGActionTableViewDelegate` methods
`dismissEditingControls` / `commitAction:`). Only one cell may have its controls
open; opening a second closes the first.

**Inline expansion** in 2013 means *rows are inserted into the same table*, with
`beginUpdates` / `insertRowsAtIndexPaths:withRowAnimation:UITableViewRowAnimationFade`
/ `endUpdates` — never an accordion that animates a cell's own height, never a
disclosure that reveals a nested scroll view. The trigger row keeps its
disclosure indicator (`MenuDisclosureIndicator.png`, 9×16pt), which does **not**
rotate. Expanded child rows are ordinary rows of the same section, inset a
further 12pt on the left. If more than about five rows would appear, push a new
controller instead of expanding.

## 10. Gesture-driven interaction

Gestures are available and are the correct answer wherever the original used
one. The following all exist on iOS 6.1.3 and may be used without a guard:

- `UIGestureRecognizer` and subclassing it — iOS 3.2.
- `UITapGestureRecognizer`, `UISwipeGestureRecognizer`, `UIPanGestureRecognizer`,
  `UIPinchGestureRecognizer`, `UILongPressGestureRecognizer`,
  `UIRotationGestureRecognizer` — all iOS 3.2.
- `UIScrollView` with `pagingEnabled` — iOS 2. `UIPageViewController` — iOS 5.
- `UIScrollView` zooming via `viewForZoomingInScrollView:`, `minimumZoomScale`,
  `maximumZoomScale` — iOS 2, no pinch recogniser needed.

The **only** thing iOS 7 added is the convenience transition layer —
`UIViewControllerAnimatedTransitioning`, `UIPercentDrivenInteractiveTransition`.
That layer is sugar for wiring a gesture to a controller transition. Everything
it produces can be written by hand: read the gesture, move a frame or a
transform, and on end animate to the nearer resting place. In 2013 that is
exactly what was done.

**The original proves it.** Fifteen-plus files in `telegram_iphone.src` attach or
subclass gesture recognisers — among them
`TelegraphKit/TelegraphKit/TGConversationController.mm`,
`TGConversationMessageItemView.mm`, `TGDialogListCell.m`, `TGActionTableView.m`,
`TGImageViewController.mm`, `TGImageViewPage.m`, `TGMapViewController.m`,
`TGNavigationBar.m`, `TGImagePickerCell.mm`, `TGSwitchView.m`,
`TGRemoteImageView.m`, `TGImageSearchController.mm`,
`Telegraph/Telegraph/TGProfileController.m`, `TGPhotoGridCell.m`,
`TGMediaListView.m`, `TGTokenFieldView.m`, `TGNotificationWindow.m`,
`TGCameraController.m`. Three custom recognisers ship in TelegraphKit:
`TGSwipeGestureRecognizer` (a `UIGestureRecognizer` subclass),
`TGImagePanGestureRecognizer` (a `UIPanGestureRecognizer` subclass) and
`TGDoubleTapGestureRecognizer`. **Our repo already contains the ported
`TGSwipeGestureRecognizer`** (`src/TGSwipeGestureRecognizer.h`) with
`direction`, `directionLockThreshold`, `horizontalThreshold`,
`verticalThreshold`, `velocityThreshold`, `velocityFailDistance` and
`failGesture`.

**a. Swiping between items is a paging `UIScrollView`.** The authority is
`TelegraphKit/TelegraphKit/TGImagePagingScrollView.mm`, declared
`@interface TGImagePagingScrollView : UIScrollView` and setting
`self.pagingEnabled = true` in its initialiser. It holds page views
(`TGImageViewPage`), recycles them, and reports position back through
`TGImagePagingScrollViewDelegate` — `scrollViewCurrentPageChanged:imageItem:`,
`pageWillBeginDragging:`, `pageDidScroll:`, `pageDidEndDragging:`. Copy that
structure for any swipe-between-items surface (photos, wallpapers, media
previews). Rules: a **page gap** drawn by making each page narrower than the
scroll view by `pageGap` and inset by `pageGap / 2`; `directionalLockEnabled =
true` on the container; only the visible page and its two neighbours may exist,
the rest recycled — a 512 MB device cannot hold more. Do not reach for
`UIPageViewController` when a paging scroll view will do; the original did not.

**b. Drag-to-dismiss is a pan gesture plus a transform.** Verbatim from
`TGImageViewController.mm:180` and `:772` (`scrollViewPanned:`), and this is the
shape to reproduce:

- A `TGImagePanGestureRecognizer` (a `UIPanGestureRecognizer` subclass) is added
  to the *container* of the paging scroll view, `maximumNumberOfTouches = 1`,
  `cancelsTouchesInView = true`, with the controller as `delegate` so it can
  coexist with the scroll view's own pan.
- On `UIGestureRecognizerStateBegan`: dismissal is armed only if the current page
  is **not zoomed**; a zoomed page pans its own content instead.
- On `Changed`: ignore the first **14pt** of travel, then offset the content by
  `translation.y` minus that 14pt dead zone, fade the black backdrop to
  `MAX(0.4, 1 - MIN(1, |translation.y| / 400))`, fade the status bar in over the
  first 200pt, and hide the top and bottom chrome with a 0.3 s `setActive:false`.
- On `Ended`: dismiss when `|translation.y| > 80` **or**
  `|velocity| > 800`; otherwise animate back to the resting frame. Carry the
  release velocity into the dismissal animation rather than starting from zero.

Use a frame offset or a `CGAffineTransform` translation — not a constraint, and
not an interactive-transition object.

**c. Which gesture for which act.** Long-press on a message opens `TGMenuView` /
`TGPopupMenu` (§8) — that is a gesture, and it is the only correct message
menu. Horizontal swipe on a list row opens the cell's own action button (§9)
through `TGSwipeGestureRecognizer` and `TGActionTableView`. Double-tap zooms an
image. Pinch zooms through the scroll view's zoom scale. Vertical pan on a
full-screen media view dismisses it (b). Anything else needs a precedent in the
original before it is added.

**d. What is still refused.** Not because gestures are impossible, but because
2013 Telegram did not do them: an interactive swipe-back on the navigation stack
(the original uses the back button; iOS 7's
`interactivePopGestureRecognizer` does not exist and a hand-rolled one changes
the app's feel), swipe-to-reply on a bubble, a swipeable bottom sheet, a card
stack, and rubber-band spring animations. Gesture work stays inside a screen; it
does not drive controller transitions.

## 11. Tone — the interface never apologises for the operating system

Absolute, and it applies to every string in the app.

- **No banner, label, alert, placeholder, footer, empty state or button title may
  say that iOS 6 cannot do something**, that a feature is unavailable on this
  device, that a device is old or unsupported, or that a thing "requires a newer
  version". Do not mention an operating system version on screen at all. The
  whole app is an iOS 6 app; saying so inside it is noise.
- If something is not supported, there are exactly two allowed outcomes:
  **do not show the control**, or **show the reduced thing working, silently.**
  A missing sticker animation shows the still frame. An unplayable codec shows the
  file row with its download action, not a complaint.
- Never write copy in the shape "Video notes are not supported on this device" —
  besides being apologetic it is also false (see the correction at the top of
  this chapter).
- Errors still follow §7: a localized sentence about *this act*, never about the
  platform, never a raw code.
- Where a limitation genuinely has to be explained, it is explained to a
  developer — in the agent's report, in `docs/`, or in a commit message. Never on
  screen. (And never as a source comment: source files in this repo carry no
  comments.)

---

## How to render a modern concept in this idiom

Rulings. Follow them literally so independent agents converge.

- **Reactions.** A reaction is not a new control. Long-pressing a message adds a
  `React` entry as the **first** item of `TGPopupMenu`, glyph `"react"`. The
  emoji picker that follows is a `TGMenuView`-metric row: height 41, same
  backgrounds and arrow, one emoji per button at 24pt, max 6 buttons then the
  strip scrolls horizontally. The reaction chips shown on a message sit in a row
  beneath the bubble text, chip height **20**, corner radius 10, horizontal
  padding 7, 4pt gap, emoji 13pt, count in `boldSystemFontOfSize:11`; chip fill is
  the bubble's own selected-state fill (`Msg_In_Selected.png` /
  `Msg_Out_Selected.png` stretched), and the chip the user picked is drawn with
  the `_High_Selected` variant. No animation on appearance beyond a 0.15 s fade.
- **Replies.** Reply is the second item of `TGPopupMenu`, glyph `"reply"`. The
  quoted block inside a bubble is not a card: a **2pt** vertical bar in
  `0x0779d0` (outgoing: white at 0.7 alpha) at the bubble's text inset, author in
  `boldSystemFontOfSize:13`, one line of text in `systemFontOfSize:13` truncated
  at the tail, 10pt gap to the message text. The compose-bar reply banner is a
  panel of the `TGConversationActionsPanel` kind, height 44, with a close
  `TGToolbarButton` of `TGToolbarButtonTypeGeneric` on the right.
- **Stickers.** Choosing a sticker is a **modal form** (§4): a presented
  navigation controller, Cancel on the left, grid inside. It is a
  `UIScrollView` of tiles laid out by frame — `UICollectionView` does not exist
  on iOS 6.1.3. Sticker sets are grouped-table rows with a 32pt thumbnail.
  Never a keyboard-height inline panel with a tab strip.
- **Premium / verified badges.** A badge is a glyph beside the title at the
  baseline, 14×14, 4pt after the last text glyph, never a coloured pill and never
  a gradient. Tapping it shows a one-button `UIAlertView` (§7) explaining it.
  Upsell is a grouped-table screen, not a full-screen takeover.
- **Folders / chat filters.** Switching folder is a **choice sheet** (§1) raised
  from the chat-list title, options in folder order with `Common.Cancel` last —
  not a segmented control and not a scrollable tab strip. Editing folders is a
  modal form (§4).
- **Media grids.** Frame-laid `UIScrollView` of square tiles, 3 across in
  portrait, 4pt gutter, tiles rounded 0pt. Multi-select uses idiom 3b
  (`ImagePickerThumbnalSelect*.png` at 33pt in the top-right of the tile, inset
  4pt). Downscale every thumbnail to the tile's pixel size before display; a
  512 MB device cannot hold full-size images.
- **Full-screen media viewer.** A paging `UIScrollView` in the shape of
  `TGImagePagingScrollView` (§10a) with vertical drag-to-dismiss (§10b). Not a
  modal form, not a page-curl, not a custom transition object.
- **Video recording and round video notes.** Supported; build them. Capture with
  `AVCaptureSession` + `AVCaptureMovieFileOutput` (or
  `UIImagePickerController` for the simple path) as
  `Telegraph/Telegraph/TGCameraController.m` does, H.264 only. A round note is a
  short clip drawn in a circular-masked layer — the mask is presentation, the
  file is an ordinary clip. Long-file transcoding is slow, so keep clips short
  and never block the UI on it; if a codec cannot be played, the row still shows
  with its normal action and says nothing about the device (§11).
- **Message forwarding / share sheet.** Not a share sheet. Push or present
  `TGForwardPicker` (`src/TGForwardPicker.h`) — a list with idiom 3a checks and a
  Done `TGToolbarButton` — and confirm with the two-button
  `Common.No` / `Common.Yes` alert of §7.
- **Pull-to-refresh, toasts, snackbars, banners.** Only `TGSnackbar` exists, and
  only for undoable destruction. Anything else that wants to be a toast is an
  alert (§7) if it is an error, and is silent otherwise.
- **Anything needing a bottom sheet, a card stack, a blur, or a spring
  animation.** Refused — because 2013 Telegram had none of these, not because
  the system cannot do them. Use §1 or §4. Gesture-driven behaviour inside a
  screen is not refused; see §10.

## Where the original has no answer

- **Reaction chips, premium badges and folder chrome have no 2013 precedent at
  all.** The rulings above are extrapolations built strictly from existing
  assets and metrics (selected-bubble fills, `TGMenuView` metrics, action-sheet
  choice); they are law here for the sake of convergence, not archaeology.
- **The original has no toast/banner concept and no non-blocking success
  feedback** other than `TGProgressWindow.dismissWithSuccess`. Silence is the
  2013 answer for success; do not invent one.
- **No pull-to-refresh anywhere in the 1.1 source.** Lists refresh from the
  network layer only.
- **No interactive controller transition anywhere in the 1.1 source.** Gestures
  drive views inside a screen (§10); pushes and presents are plain animated
  transitions. This is a taste decision recorded from the original, not a
  platform limit.
- `TGListMenuController` in the original is an empty scaffold — it declares
  `+tableView:cellForMenuItem:` and returns `nil`. It is not a usable pattern;
  build modal forms from §4 instead.

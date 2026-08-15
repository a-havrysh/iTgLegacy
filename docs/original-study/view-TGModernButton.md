# TGModernButton (view) — original study

## Naming: the class does not exist in our authority snapshot

There is no `TGModernButton` anywhere in
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
(Telegram for iOS v1.1, build 21024). A full-tree `find -iname "*ModernButton*"` and a
`grep -r TGModernButton` over both `TelegraphKit/TelegraphKit` and `Telegraph/Telegraph`
return nothing. `TGModernButton` is a *later* class: it exists only in the fork,
`/Users/alexanderhavrysh/Git/iOS/twelve/submodules/LegacyComponents/LegacyComponents/TGModernButton.{h,m}`
(and a separate model-driven `TGModernButtonView`/`TGModernButtonViewModel` pair under
`twelve/Telegraph/`). It belongs to the flat-design era, after the 2013 artwork was thrown away.

The 2013/2014 button family in the original is four classes, in
`.../telegram_iphone.src/TelegraphKit/TelegraphKit/`:

| Class | Lines | Role |
|---|---|---|
| `TGButton` | `TGButton.h:11`–`15`, `TGButton.m:1`–`18` | bare `UIButton` + enlarged hit area. **Dead code**: `grep -rn '"TGButton.h"'` over the whole tree matches only `TGButton.m:1`. |
| `TGHighlightableButton` | `TGHighlightableButton.h:11`–`16`, `.m:1`–`24` | `UIButton` that forwards `highlighted` into its subviews and can flip the title shadow. |
| `TGReusableButton` | `TGReusableButton.h:13`–`17`, `.m:1`–`23` | `UIButton` + `TGReusableView` (recycler identity). |
| `TGToolbarButton` | `TGToolbarButton.h:23`–`49`, `.m:1`–`648` | the real, fully designed, artwork-driven button of the app — the nav-bar/header button. |

**The closest real class to "the app's designed button component" is `TGToolbarButton`**, and that
is what this document treats as the subject; the other three are documented because our port
touches their territory too. Where the fork's `TGModernButton` is relevant it appears in the
"what it became" section.

---

## 1. TGToolbarButton — what it is for

Every button that sits in the blue 2013 navigation bar: Back, Cancel, Done, Edit, Delete, plus the
gallery's custom-image variants. It is a `UIButton` subclass but it does **not** use
`titleLabel`/`imageView`; it builds its own `UILabel` and `UIImageView` and lays them out by hand
(`TGToolbarButton.m:280`–`289`), so all the padding, half-pixel and landscape adjustments are its
own. `UIButton` is still the superclass because the class wants `setBackgroundImage:forState:`
and the touch-tracking state machine.

It declares `<TGBarItemSemantics>` (`TGToolbarButton.h:23`) so a navigation bar can ask it whether
it is a back button and can push a vertical offset into it.

### Public surface (`TGToolbarButton.h`)

- `type` (`:25`) — one of `Generic=0, Back=1, Done=2, DoneBlack=3, Image=4, Delete=5, Custom=6` (`:13`–`21`). Chooses artwork and default paddings.
- `touchInset` (`:27`) — `CGSize`, defaults `(8, 8)` (`.m:263`, `.m:311`).
- `minWidth`, `paddingLeft`, `paddingRight` (`:29`–`31`) — defaults `0, 7, 7` (`.m:265`–`267`).
- `text`, `image`, `imageLandscape`, `imageHighlighted` (`:33`–`36`).
- `buttonLabelView`, `buttonImageView` (`:38`–`39`) — exposed for callers who want to poke at them.
- `isLandscape`, `landscapeOffset` (`:41`–`42`).
- `backSemantics` (`:44`) — read back as `type == Back || _backSemantics` (`.m:354`–`357`).
- `-initWithType:` (`:46`) and `-initWithCustomImages:imageNormalHighlighted:imageLandscape:imageLandscapeHighlighted:textColor:shadowColor:` (`:47`).

### Metrics, every one cited

- **Height: 30 pt portrait, 25 pt landscape.** Set in `sizeToFit` (`.m:521`) and again when the
  orientation flips (`.m:513`).
- **Width** = `paddingLeft + labelWidth + imageWidth + paddingRight`, clamped up to `minWidth`
  (`.m:520`–`540`). Note the spacing between label and image (4 pt, `.m:574`) is **not** added to
  the `sizeToFit` width — a label+image button is 4 pt narrower than its content. That is an
  original bug, faithfully reproducible or not; it only bites the Image type, which in practice is
  used image-only.
- **Padding: 7 / 7 generic; 15 / 9 for `Back`** (`.m:266`–`267`, `.m:271`–`275`). The 15 on the
  left is the width of the chevron in `BackButton.png`.
- **Font: `[UIFont boldSystemFontOfSize:12]`** for the label, both initialisers (`.m:281`, `.m:326`).
  All the 30/25 pt heights and the half-pixel nudges below were tuned around this font.
- **Label vertical position** (`.m:561`):
  `y = (bounds.height - labelHeight)/2 - (isLandscape ? 1 : 0) - retinaPixel + (isLandscape ? 1 : 0) - (type != Back && !isLandscape ? retinaPixel : 0)`
  where `retinaPixel = TGIsRetina() ? 0.5 : 0` (`.m:552`) and `addY = isLandscape ? 1 : 0` (`.m:554`).
  Reduced: on a retina portrait bar a **generic/done** label sits **1.0 pt above centre**, a **Back**
  label **0.5 pt above centre**; on non-retina everything is dead centre. The Back exception exists
  because the back plate's art is itself shifted (see `backgroundRectForBounds` below).
- **Label/image horizontal**: both are centred as a group inside the padded box (`.m:578`–`579`),
  then snapped to a half-pixel grid on retina (`truncate(x*2)/2`, `.m:583`–`584`) or to whole
  points otherwise (`.m:588`–`589`). Back in landscape gets one more point to the left (`.m:592`–`593`).
- **Background rect** (`.m:620`–`636`): shifted down 0.5 pt on retina landscape; for `Back` the
  plate is widened one point to the left (`origin.x -= 1; size.width += 1`) and, on retina portrait,
  pushed down 0.5 pt. This is what makes the back chevron bleed into the bar edge.
- **Frame y when orientation changes** (`.m:496`–`511`): if the superview implements
  `TGBarItemSemantics`, `y = (isLandscape ? 2 : 0) + [superview barButtonsOffset]`; otherwise the
  hardcoded fallback `y = isLandscape ? 3 : 7`.

### Colours

- Title: **always `[UIColor whiteColor]`** — `textColorForButton()` (`.m:173`–`188`) has a switch
  that falls through to white for every type; the `Done`/`DoneBlack` case is empty. So in v1.1 no
  toolbar button ever had a non-white title unless it used the custom-images initialiser.
- Title shadow: `#042651 @ 30%` for `Done` and `DoneBlack`, `#0e284d @ 40%` for everything else
  (`shadowColorForButton`, `.m:190`–`205`). Shadow offset `(0, -1)` in both initialisers
  (`.m:284`, `.m:329`) — the text is engraved into the plate, not raised.

### Artwork and how it stretches

All backgrounds are lazily built once into file-static `UIImage *` (`.m:5`–`171`), so the caps are
fixed for the process lifetime.

| type | normal / pressed | stretch |
|---|---|---|
| `Back` | `BackButton.png` / `BackButton_Pressed.png`, landscape `BackButton_Landscape.png` / `_Pressed` | left cap **15**, top cap 0 (`.m:9`, `:17`, `:25`, `:33`) |
| `Generic` | `HeaderButton.png` / `HeaderButton_Pressed.png`, landscape `HeaderButton_Landscape*` | left cap **6** (`.m:41`, `:49`, `:57`, `:65`) |
| `Done` | `HeaderButton_Blue.png` / `_Pressed`, landscape `HeaderButton_Blue_Landscape*` | left cap = `width/2` (`.m:75`, `:86`, `:97`, `:108`) |
| `DoneBlack` | `HeaderButton_Login_Blue.png` / `_Pressed` (+ landscape) | left cap = `width/2` (`.m:119`, `:130`, `:141`, `:152`) |
| `Delete` | `Header_Button_Delete.png`, **same image in landscape**, no pressed art at all (`.m:157`–`171`, `.m:392`–`395`) | left cap 6 |
| `Image` | no background (`.m:388`–`391`) | — |
| `Custom` | whatever the caller passed | caller's caps |

The 15 pt left cap on Back means the whole chevron is the non-stretching part; the 6 pt cap on
Generic means only a thin bevel edge is preserved; `width/2` on the blue plates means the art is a
symmetric pill stretched from its exact middle.

The pressed image is installed for **three** states, not one:
`Highlighted`, `Highlighted|Selected`, and `Selected` (`.m:396`–`399`). A toolbar button left in
`selected` shows the pressed plate.

### States and behaviour

- **Highlight** is purely the background swap; `setHighlighted:` is an empty override with its body
  commented out (`.m:606`–`611`), same for `setSelected:` (`.m:613`–`618`). There is **no** alpha
  animation, no fade, no cross-dissolve — the 2013 button snaps.
- **Disabled**: `setEnabled:` sets `buttonLabelView.alpha = enabled ? 1.0 : 0.6` (`.m:599`–`604`).
  The plate is not dimmed; only the text goes to 60%. `adjustsImageWhenDisabled` and
  `adjustsImageWhenHighlighted` are both switched off in both initialisers (`.m:295`–`296`,
  `.m:340`–`341`) precisely so UIKit does not add its own dimming on top.
- **`exclusiveTouch = true`** (`.m:269`, `.m:317`) — two nav-bar buttons can never be pressed at once.
- **Hit testing** (`.m:638`–`646`): returns `nil` if hidden or `alpha < FLT_EPSILON`; returns
  `self` if the point is inside `bounds` inset by `-touchInset`; otherwise `nil` — it **never**
  falls through to `super`, so the label and image view can never become the hit view. Compare
  `TGButton.m:7`–`16`, which does the same test but *does* fall through to `super hitTest:`.
- **Empty / nil content**: `setText:nil` blanks and hides the label (`.m:407`–`421`); `setImage:nil`
  blanks and hides the image view (`.m:428`–`442`). Both initialisers deliberately call
  `self.text = @""` and `self.image = nil` (`.m:290`–`291`, `.m:335`–`336`), so a fresh button is a
  bare plate. `layoutSubviews` zeroes the size of whichever is hidden and drops the 4 pt spacing to
  0 when either side is empty (`.m:563`–`576`), so a text-only or image-only button has no phantom gap.
- **Long text**: nothing truncates. `sizeToFit` grows the frame to whatever the label needs; if the
  caller does not call `sizeToFit`, `layoutSubviews` still `sizeToFit`s the label (`.m:559`) and
  centres it, so an overlong title simply overflows the plate on both sides. There is no
  `adjustsFontSizeToFitWidth`, no minimum scale, no ellipsis anywhere in the class. The design
  assumption is short, localised, verb-sized labels ("Done", "Edit", "Cancel").
- **Orientation** is a manual push, not an observer: `setIsLandscape:` is guarded by
  `landscapeInitialized` so the first assignment always runs even if the value matches (`.m:480`–`482`);
  it swaps `image`/`imageLandscape`, re-`sizeToFit`s the image view, re-lays out, re-picks the
  background, and rewrites the frame's `y` and `height`. It does **not** recompute width, so a
  landscape flip keeps the portrait width.

### Real call sites

The clearest one is the image viewer chrome,
`TelegraphKit/TelegraphKit/TGImageViewControllerInterfaceView.m:60`–`79`: two `Custom` buttons built
from `GalleryDoneButton.png` / `GalleryCloseButton.png` with **left cap 11**, white text, shadow
`#000000 @ 50%` for Done and `#16478a @ 50%` for Edit, `minWidth` 55 and 51 respectively,
`touchInset (16, 16)` (double the default, because they float over a photo), then `sizeToFit`
followed by `CGRectOffset(frame, 5, 7)` — 5 pt from the panel edge, 7 pt from its top; the right one
is pinned with `UIViewAutoresizingFlexibleLeftMargin`. `minWidth` exists exactly for this: keeping a
pair of buttons visually equal when their words differ in length.

---

## 2. The three smaller classes

**`TGHighlightableButton`** (`.h:11`–`16`) adds two properties, `reverseTitleShadow` and
`normalTitleShadowOffset`. Its `setHighlighted:` walks `self.subviews` and pushes `highlighted` into
every `UILabel` and `UIImageView` it finds (`.m:10`–`16`) — that is how a caller gets
`highlightedTextColor`/`highlightedImage` to fire on hand-built subviews — and, if
`reverseTitleShadow`, negates the title shadow offset while pressed (`.m:18`–`19`), turning an
engraved label into a raised one on press. It is the button used for the *content-area* buttons:
`TGButtonsMenuItemView.m:114`–`136` (grouped action buttons: `GroupedActionButton.png` stretched
from `width/2`, title `#4a6587`, title shadow `#ffffff @ 45%` offset `(0, 1)`, highlighted title
white with clear shadow, font `boldSystemFontOfSize:14`, frame height taken from the raw image),
the green variant in the same file at `:90`–`103` (white title, shadow `#124606 @ 30%`, font
`boldSystemFontOfSize:16`, offset `(0, -1)`, `reverseTitleShadow = false`),
`TGWallpaperPreviewController.m:145`/`:157` (131 pt wide, x = 17 and `width - 17 - 131`, y = 26,
height from the art), `TGLoginPhoneController.m:164`, `TGLoginProfileController.m:146`,
`TGProfileController.m:742`.

Note the deliberate inversion between the two button worlds: nav-bar buttons are white text with a
dark shadow **above** (`(0, -1)`), content buttons are dark text with a white shadow **below**
(`(0, 1)`). That is the whole skeuomorphic grammar in one line — light comes from the top, so text
punched into a dark plate throws its shadow up, and text raised off a light plate throws it down.

**`TGReusableButton`** only supplies a `reuseIdentifier` defaulting to `@"TGReusableButton"`
(`.m:7`–`13`) and empty `prepareForReuse` / `prepareForRecycle:` (`.m:15`–`21`) — recycling a button
resets *nothing*, the layout model is expected to reconfigure it fully (`TGLayoutModel.m:183`–`186`).
Its one real subclass is **`TGMediaActionButton`**, whose interesting behaviour is a two-string
title: `setTitleText:shortTitleText:` (`TGMediaActionButton.m:28`–`32`) stores both, and
`sizeThatFits:` measures the long one and, if `insets.left + textWidth + insets.right` exceeds the
offered width, silently substitutes the short one (`.m:42`–`55`). Height comes from the normal-state
background image, captured in an overridden `setBackgroundImage:forState:` (`.m:34`–`40`).
**This is the original's entire answer to "what if the text is too long": pick a shorter string.**
No truncation, no scaling.

**`TGButton`** is unused; its only contribution is proving that `touchInset`-style hit expansion was
the house pattern.

---

## 3. Our port, judged

We have **no button class**. The equivalent is a factory pair in
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGIcons.m`: a file-private `TGHeaderButton`
(`TGIcons.m:4`–`13`) overriding `pointInside:withEvent:` with a fixed `CGRectInset(bounds, -8, -8)`,
`+styleHeaderButton:done:` (`TGIcons.m:111`–`131`) and `+headerButtonWithTitle:bold:target:action:`
(`TGIcons.m:133`–`163`), declared in `TGIcons.h:71`–`73`. Ten screens use it
(`TGChatListViewController.m:1267`, `TGPrivacyViewController.m:107` and `:1364`,
`TGTopicsViewController.m:632`, `:1103`, `:1816`, `TGProfileViewController.m:3539`,
`TGInviteLinksViewController.m:116`, `TGEditProfileViewController.m:38`,
`TGGroupMembersViewController.m:1394`).

What is right, briefly: font `boldSystemFontOfSize:12` (`TGIcons.m:150` vs `.m:281`); white title;
shadow offset `(0, -1)`; the two shadow colours `#042651 @ 0.3` / `#0e284d @ 0.4`
(`TGIcons.m:157`–`159` vs `.m:197`, `:204`); `exclusiveTouch`, `adjustsImageWhenDisabled = NO`,
`adjustsImageWhenHighlighted = NO` (`TGIcons.m:136`–`138` vs `.m:295`–`296`); the 6 pt cap on
`HeaderButton` and the `width/2` cap on the blue plate (`TGIcons.m:118`–`125` vs `.m:41`, `.m:119`);
30 pt height and `textWidth + 14` width, which is exactly `paddingLeft 7 + paddingRight 7`
(`TGIcons.m:152` vs `.m:520`); the 8 pt hit expansion (`TGIcons.m:9` vs `.m:263`); and the
`-2 * retinaPixel` label offset on a full-bounds centred label (`TGIcons.m:145`), which puts the
text centre 1.0 pt above the button centre on retina — arithmetically the same result as `.m:561`
for the generic type. Good.

The differences a user can see are listed as defects in the structured report; the substantive ones
are the missing disabled state, the missing `Selected` background, the wrong blue plate, and the
absence of the whole `Back` geometry.

---

## 4. What it became

**In the fork (`twelve`), `TGModernButton`** — the class this study was nominally asked about — is
the direct descendant, and it inverts the design. There is no artwork and no type enum. Highlight is
now `modernHighlight` (`TGModernButton.m:26`, default true), and the pressed look is, in priority
order, a fading `highlightImage` overlay, a fading `highlightBackgroundColor` view, or, failing both,
**fading the whole button to `alpha 0.4`** (`.m:153`–`217`). Disabled is `alpha 0.5`, multiplied into
the same expression (`.m:199`, `.m:244`–`253`, `.m:279`–`282`) rather than the original's
label-only `0.6`. The 0.2 s animation is applied **only on touch-up / move / cancel**, never on
touch-down: `_animateHighlight` is set around those three `touches*` overrides only (`.m:55`–`74`),
so press is instant and release fades. That is a real interaction decision worth copying if we ever
go flat — press must feel immediate, release must feel soft. `touchInset` became a four-sided
`extendedEdgeInsets` (`.m:31`–`45`), and unlike the original it *does* fall through to `super hitTest:`.
`highlitedChanged` (misspelling and all) is a block callback so a container can highlight itself when
its inner button is pressed. Almost all of this was forced by iOS 7 flat design deleting the
plate art; the extended insets and the block callback are genuine functional growth.

**In the modern client**, the concept split in two:
`Telegram-iOS/submodules/Display/Source/HighlightTrackingButton.swift:29` (`HighlightTrackingButtonNode`)
keeps only the *tracking* half — `highligthedChanged: (Bool) -> Void`, still with the same typo
inherited from `TGModernButton.h:14` — driven by `beginTracking`/`endTracking` (`:50`–`59`) rather
than by `setHighlighted:`, while the *appearance* half moved out into the theme system and per-site
nodes. The lesson for us: the 2013 original coupled artwork, geometry, hit area and state into one
class; that coupling is exactly why it was rewritten, and it is also exactly what we want, because
our artwork is fixed and our geometry is one screen size.

## 5. Genuine ambiguity

- Whether a `Delete` toolbar button ever appeared pressed is unclear: `updateBackground` assigns
  `backgroundPressed`, which is left `nil` on that branch (`.m:392`–`399`), so pressing it removes
  the plate entirely. No call site in the snapshot constructs `TGToolbarButtonTypeDelete`, so this
  may simply never have shipped.
- The `sizeToFit` omission of the 4 pt label/image spacing (`.m:520`–`541` vs `.m:574`) is
  indistinguishable from an intentional tightening; there is no label+image call site in the
  snapshot to settle it.

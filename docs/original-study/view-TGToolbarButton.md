# TGToolbarButton — the 2013 navigation-bar button

Source of truth:
`telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGToolbarButton.h`
and `.../TGToolbarButton.m` (Telegram for iOS v1.1, build 21024).
All line numbers below refer to those two files unless another path is given.

## 1. What it is

Every button that appears inside a navigation bar in the 2013 client is a `TGToolbarButton`:
Back, Edit, Done, Cancel, Compose, Clear All, the login Next. It is a `UIButton` subclass
(`.h:23`) but it does **not** use `UIButton`'s own title/image machinery — it owns a private
`UILabel` and a private `UIImageView` that it lays out by hand (`.m:280-289`), and it uses
`UIButton` only for the stretched background plate and the control-state bookkeeping. That is
the single most important structural fact: `setTitle:`/`setImage:` are never called on it;
`self.text` and `self.image` are (`.h:33-34`).

It conforms to `TGBarItemSemantics` (`.h:23`, protocol at
`TelegraphKit/TelegraphKit/TGNavigationController.h:52-59`) so that the navigation bar and the
conversation controller can ask "is this a back button?" and can supply a vertical offset.

Buttons are wrapped in `[[UIBarButtonItem alloc] initWithCustomView:]` at every call site
(e.g. `TelegraphKit/TelegraphKit/TGViewController.mm:610`,
`TelegraphKit/TelegraphKit/TGDialogListController.mm:308`).

## 2. Types

`TGToolbarButtonType` (`.h:13-21`), with the plate each type resolves to in `updateBackground`
(`.m:359-400`):

| Type | Portrait normal | Portrait pressed | Left cap | Used by |
|---|---|---|---|---|
| `Generic` (0) | `HeaderButton.png` | `HeaderButton_Pressed.png` | 6 (`.m:41`) | Edit, Cancel, Compose, Clear All |
| `Back` (1) | `BackButton.png` | `BackButton_Pressed.png` | 15 (`.m:9`) | every back button |
| `Done` (2) | `HeaderButton_Blue.png` | `HeaderButton_Blue_Pressed.png` | width/2 (`.m:75`) | Done inside the app |
| `DoneBlack` (3) | `HeaderButton_Login_Blue.png` | `..._Pressed.png` | width/2 (`.m:119`) | login Next only |
| `Image` (4) | none — `background = nil` (`.m:390`) | — | — | **never used** |
| `Delete` (5) | `Header_Button_Delete.png` (`.m:161`) | none | 6 | **never used** |
| `Custom` (6) | caller-supplied images (`.m:365-366`) | caller-supplied | caller pre-stretches | `TGViewController setBackAction:imageNormal:…` (`TGViewController.mm:621`) |

Two dead ends worth recording, because a port should not spend effort on them: no call site in
the whole tree constructs `TGToolbarButtonTypeImage` or `TGToolbarButtonTypeDelete` (verified by
grepping every `.m`/`.mm` for `TGToolbarButtonType`), and the asset
`Header_Button_Delete.png` does not exist in `Telegraph/Telegraph/Resources` at all — so the
Delete type would have rendered as a bare label on no plate.

Each type has a landscape twin (`HeaderButton_Landscape.png`, `BackButton_Landscape.png`,
`HeaderButton_Blue_Landscape.png`, `HeaderButton_Login_Blue_Landscape.png`, plus `_Pressed`
variants, `.m:21-155`). `TGToolbarButtonTypeDelete`'s "landscape" function returns the same
portrait asset (`.m:169`), another sign it was abandoned.

### Artwork sizes (measured with `sips` on `Telegraph/Telegraph/Resources/*@2x.png`)

| Asset | @2x px | points |
|---|---|---|
| `BackButton@2x.png` | 54×60 | 27×30 |
| `BackButton_Landscape@2x.png` | 60×50 | 30×25 |
| `HeaderButton@2x.png` | 42×60 | 21×30 |
| `HeaderButton_Landscape@2x.png` | 32×50 | 16×25 |
| `HeaderButton_Blue@2x.png` | 42×60 | 21×30 |
| `HeaderButton_Blue_Landscape@2x.png` | 32×50 | 16×25 |
| `HeaderButton_Login_Blue@2x.png` | 42×60 | 21×30 |

So the 30pt portrait / 25pt landscape button heights hard-coded at `.m:513` and `.m:521` are
not arbitrary — they are exactly the plate heights, and the plates are stretched horizontally
only (`topCapHeight:0` everywhere).

Note the cap-width idiom for the blue plates: `stretchableImageWithLeftCapWidth:(int)(w/2)`
where `w` is the *point* width, i.e. cap 10 of a 21pt image (`.m:75`). The grey generic plate
uses a fixed cap of 6 and the back plate 15 (the arrow lives in that left 15pt, which is also
why `paddingLeft` for Back is 15).

## 3. Metrics

Set in `initWithType:` (`.m:256-302`):

- `touchInset = (8, 8)` (`.m:263`) — used only by `hitTest:` (`.m:638-646`), which returns
  `self` for any point inside `CGRectInset(bounds, -8, -8)`. A 30pt-tall button therefore has a
  46pt-tall touch target and 16pt of extra width.
- `minWidth = 0`, `paddingLeft = 7`, `paddingRight = 7` (`.m:265-267`).
- For `Back`: `paddingLeft = 15`, `paddingRight = 9` (`.m:273-274`). The same pair is applied
  by hand to custom-image back buttons (`TGViewController.mm:623-624`).
- `exclusiveTouch = true` (`.m:269`) — two bar buttons can never be pressed at once.
- `adjustsImageWhenDisabled = false`, `adjustsImageWhenHighlighted = false` (`.m:295-296`):
  the pressed look comes only from the pressed plate, never from UIKit's automatic dimming.
- Label font: **bold system 12** (`.m:281`). Every metric below is sized around that font; on
  iOS 6 `[UIFont boldSystemFontOfSize:12]` has a ~14pt line height, which is why a 30pt plate
  leaves ~8pt above and below the glyphs.

Per-call-site widths, which are where the real design lives:

| Call site | text | minWidth | padding L/R |
|---|---|---|---|
| Dialog list Edit (`TGDialogListController.mm:301-306`) | Edit | 51 | 10 / 10 |
| Dialog list Done (`TGDialogListController.mm:317-322`) | Done | 51 | 10 / 10 |
| Dialog list Compose (`TGDialogListController.mm:410-415`) | — (icon) | 0 | 6 / 6 |
| Profile Edit (`TGProfileController.m:629-635`) | Edit | 51 | 7 / 7 |
| Profile Cancel (`TGProfileController.m:4769-4772`) | Cancel | 59 | 7 / 7 |
| Profile Done (`TGProfileController.m:4779-4783`) | Done | 51 | 7 / 7 |
| Login Next (`TGLoginPhoneController.m:136-139`) | Next | 52 | 7 / 7 |
| Conversation Cancel (`TGConversationController.mm:1102-1108`) | Cancel | 51 | 10 / 10 |
| Conversation Clear All (`TGConversationController.mm:1128-1134`) | Clear All | 54 | 8 / 8 |
| Back (`TGViewController.mm:605-608`) | "Common.Back" | 0 | 15 / 9 |

The `minWidth` values are the point of the whole system: "Edit" and "Done" both measure well
under 51pt in bold 12, so both are padded out to exactly 51 and the button does **not** change
width when the list toggles into editing mode. Lose `minWidth` and you get a plate that visibly
jumps between the two states. The compose button, by contrast, has no `minWidth`: its width is
6 + 6 + the icon's own 23pt (`ComposeMessageIcon@2x.png` is 46×40px = 23×20pt) = **35pt**.

## 4. Sizing and layout

`sizeToFit` (`.m:518-541`) is explicit and must be called by the caller after setting text —
it is not automatic:

```
width  = paddingLeft + paddingRight
       + (label visible ? sizeToFit width : 0)
       + (image != nil ? image.size.width : 0)
width  = max(width, minWidth)
height = isLandscape ? 25 : 30
```

Note what is missing: the 4pt label↔image spacing used in `layoutSubviews` is *not* included in
`sizeToFit`. A button carrying both text and an icon is therefore 4pt too narrow for its
content. No shipping call site does both at once, so the bug never showed — but it tells you
the text+icon combination was never a supported case.

`layoutSubviews` (`.m:543-597`):

- Label vertical centre: `(height - labelHeight)/2` minus `retinaPixel` (0.5 on retina, 0 on
  1x, `.m:552`), minus another `retinaPixel` when the type is **not** Back and we are portrait,
  plus `addY = 1` in landscape and minus 1 more in landscape (`.m:561`). Resolving it: portrait
  retina non-Back sits 1.0pt above centre, portrait retina Back sits 0.5pt above centre,
  landscape retina sits 1.0pt above centre. The asymmetry exists because the plates are
  bevelled: the lit top edge eats a half-pixel, and the back plate's bevel differs from the
  generic one.
- Image vertical centre: plain `floorf((height - imageHeight)/2)` (`.m:569`), no nudge.
- Horizontal: label and image are treated as one group, centred inside the box *after* removing
  `paddingLeft`/`paddingRight`, with 4pt between them, and the image placed to the **right** of
  the label (`.m:574-579`). Spacing collapses to 0 when either is empty (`.m:575-576`).
- Rounding: on retina both x origins are snapped to a half-point grid
  (`((int)(x*2.0f))/2`, `.m:583-584`); on 1x they are `floorf`ed. Note the integer division bug
  in `((int)(x * 2.0f)) / 2` — this is integer division, so it actually snaps to whole points on
  retina too. Reproduce the visible result (whole-point x), not the intent.
- One final fudge: Back in landscape shifts its label 1pt left (`.m:592-593`).

`backgroundRectForBounds:` (`.m:620-636`) shifts the plate, not the content:
+0.5pt down on retina landscape; and for Back, 1pt further left and 1pt wider, plus 0.5pt down
in retina portrait. The back plate therefore bleeds one point past the button's own left edge —
that is how the arrow reaches the screen edge while the touch rect stays sane.

## 5. Orientation

`setIsLandscape:` (`.m:478-516`) is the only entry point, and it is driven from the navigation
bar: `TGNavigationBar layoutSubviews` decides `isLandscape = frame.size.width > 400`
(`TelegraphKit/TelegraphKit/TGNavigationBar.m:534`) and then walks the whole view tree calling
`setIsLandscape:` on every `TGToolbarButton` it finds (`TGNavigationBar.m:211-228`). A button
never asks UIKit about orientation itself.

On a change (guarded by `_landscapeInitialized` so the first call always runs, `.m:480`):

1. If both `image` and `imageLandscape` are set, swap the image and `sizeToFit` the image view
   (`.m:485-489`).
2. `layoutSubviews`, `updateBackground`.
3. Reposition `frame.origin.y`: if the superview conforms to `TGBarItemSemantics`, y is
   `2 + offset` landscape / `0 + offset` portrait; otherwise the bare values 3 landscape / 7
   portrait (`.m:496-511`). The only implementer of `barButtonsOffset` in the tree is
   `TGConversationButtonContainer`, which returns `4` for non-back and `0` for back
   (`TGConversationController.mm:215-218`) — i.e. the chat screen's non-back buttons hang 4pt
   lower than a plain bar button.
4. `frame.size.height = isLandscape ? 25 : 30` (`.m:513`). Width is **not** recomputed, so a
   caller that wants a correct landscape width must call `sizeToFit` again; nobody does, which
   means landscape plates keep their portrait width. Faithful behaviour, minor artefact.

## 6. Colours and states

- Text colour is `[UIColor whiteColor]` for every type — `textColorForButton` has a switch that
  falls through and returns white regardless (`.m:173-188`). The switch is vestigial.
- Shadow: offset `(0, -1)` (`.m:284`), i.e. the shadow sits *above* the glyphs — the classic
  engraved look on a dark bar. Colour by type (`.m:190-205`):
  - Done and DoneBlack: `#042651` at **0.3** alpha.
  - everything else: `#0e284d` at **0.4** alpha.
- Custom-image buttons take caller-supplied text and shadow colours and fall back to the
  Generic values when nil (`.m:327-328`).
- Disabled: `setEnabled:` sets the **label's** alpha to 0.6, not the button's (`.m:599-604`), so
  the plate stays fully opaque and only the word dims. There is no disabled plate asset.
- Highlighted/selected: `updateBackground` installs the pressed plate for
  `Highlighted`, `Selected`, and `Highlighted|Selected` (`.m:396-399`) — a selected button looks
  pressed. `setHighlighted:`/`setSelected:` do nothing else; the shadow-recolouring they once
  did is commented out (`.m:606-618`).
- Hiding is done by `alpha`, not `hidden`, at the call sites (compose button:
  `TGDialogListController.mm:422`), and `hitTest:` refuses touches when `alpha < FLT_EPSILON`
  or `hidden` (`.m:640-641`), so an alpha-hidden button is correctly untouchable.

## 7. Content edge cases

- `setText:nil` → label text becomes `@""` **and** the label is hidden (`.m:411-415`); the
  hidden flag is what makes `sizeToFit` and `layoutSubviews` drop it from the width and the
  spacing. `setText:@""` is *not* the same: the label stays visible with zero width, so the 4pt
  spacing still applies if an image is present.
- `setImage:nil` → image view cleared and hidden (`.m:432-436`), same mechanism.
- Long text: nothing truncates. `sizeToFit` grows the plate to whatever the label measures, and
  the stretched plate simply gets wider. Since the buttons are custom views inside
  `UIBarButtonItem`s, an over-long localisation would collide with the title view rather than
  ellipsise. The `minWidth` values are floors, never ceilings.
- No reuse: these are long-lived buttons owned by controllers (usually lazily created and
  cached in an ivar, e.g. `TGDialogListController.mm:299-328`), so there is no prepare-for-reuse
  path to worry about.
- Subviews are added *onto* the button by callers — the login spinner is centred inside the Next
  button (`TGLoginPhoneController.m:143-146`), and the chat back button carries the unread badge
  at `x = width - 13, y = -7` with `FlexibleLeftMargin`
  (`TGConversationController.mm:853-860`). So the button must tolerate arbitrary child views and
  must not clip.

## 8. Bar-level behaviour that belongs to the component

`TGNavigationBar hitTest:` first probes 16pt to the *left* of the real touch point and, if that
lands on a visible `TGToolbarButton`, returns that button
(`TGNavigationBar.m:535-541`). Combined with the button's own 8pt inset, the left-hand back
button is grabbable from well outside its plate. This is a deliberate 2013 affordance for a
27pt-wide target and is easy to miss when porting.

Back semantics: `backSemantics` returns true for type `Back` or when the flag is set explicitly
(`.m:354-357`), which is how custom-image back buttons announce themselves
(`TGViewController.mm:622`). The back button's title is always the localised
`Common.Back` — never the previous screen's title (`TGViewController.mm:606`).

## 9. Our port

We have **no** `TGToolbarButton`. The role is split across three places:

1. `src/TGIcons.m:107-162` — `+styleHeaderButton:done:` and
   `+headerButtonWithTitle:bold:target:action:`, plus a private `TGHeaderButton` whose
   `pointInside:` uses an 8pt inset (`TGIcons.m:8-11`). This is the in-app equivalent and is
   used by ~30 screens.
2. `src/TGLoginViewController.m:44-68, 262-321` — `TGLoginToolbarButton`, a separate and
   noticeably more faithful implementation with `backSemantics`, `backgroundRectForBounds:`
   nudges and a `hitTest:` copy.
3. `src/TGTheme.m:478-509` — the *system* back button, styled through
   `[UIBarButtonItem appearance] setBackButtonBackgroundImage:` with `BackButton` /
   `BackButton_Pressed` stretched at cap 15.

What is right: the 8pt touch inset, `exclusiveTouch`, `adjustsImageWhen…=NO`, bold system 12,
shadow offset `(0,-1)`, both shadow colours `#042651@0.3` / `#0e284d@0.4`, white text, the cap
widths (6 generic, width/2 blue, 15 back), and the 30pt height. Those all match. The login
button's `backgroundRectForBounds:` (`TGLoginViewController.m:50-59`) is a correct transcription
of `.m:620-636`.

Differences a user can see:

1. **The in-app Done plate is the login plate.** `TGIcons.m:121-122` loads
   `HeaderButton_Login_Blue` for every `bold:YES` button. The original uses
   `HeaderButton_Blue.png` for `TGToolbarButtonTypeDone` inside the app (`.m:74`) and reserves
   `HeaderButton_Login_Blue.png` for the login chrome (`.m:118`). Two different plates, two
   different bar backgrounds. Change `TGIcons.m:121-122` to `HeaderButton_Blue` /
   `HeaderButton_Blue_Pressed`; the login screen already loads the Login variants itself
   (`TGLoginViewController.m:343-344`).
2. **No `minWidth`.** `TGIcons.m:145` sizes every button as `textWidth + 14` and stops. So Edit
   (~24pt of text → 38pt) and Done (~31pt → 45pt) are both narrower than the original's 51 and,
   worse, *different from each other* — our Edit/Done toggle in
   `TGChatListViewController.m:1296` and `TGSettingsViewController.m:1155` visibly changes plate
   width where the original never did. Fix: give `headerButtonWithTitle:` a `minWidth` (51 for
   Edit/Done/Cancel-in-list, 59 for Cancel in profile, 52 for login Next) per the table in §3.
3. **Padding is always 7/7.** The original uses 10/10 in the dialog list
   (`TGDialogListController.mm:304-305`) and 8/8 for Clear All
   (`TGConversationController.mm:1131-1132`). With `minWidth` restored this matters less, but
   the parameter should exist.
4. **No landscape support at all.** `TGIcons.m:145` hard-codes height 30 and no code path ever
   swaps in `HeaderButton_Landscape` / `BackButton_Landscape` or drops to 25pt. In landscape on
   the 4S our bar buttons will be full-height portrait plates in a 32pt bar. The original's
   whole `setIsLandscape:` machinery (`.m:478-516`) plus the navigation bar's
   `findAndAlignButtons:` (`TGNavigationBar.m:211-228`) is missing. This is the largest gap.
5. **Disabled state does nothing.** The original dims the label to 0.6 alpha (`.m:601`); we
   never override `setEnabled:`, so a disabled Done looks identical to an enabled one. Screens
   that disable Done (e.g. `TGEditProfileViewController.m:38`'s Save) are affected.
6. **Selected state has no plate.** `TGIcons.m:129-130` sets Normal and Highlighted only; the
   original also sets Selected and Highlighted|Selected (`.m:398-399`).
7. **Compose button is 30×30, should be 35×30.** `TGChatListViewController.m:1266-1270` forces
   `CGRectMake(0,0,30,30)`; the original's compose is padding 6 + 6 + the 23pt icon = 35pt wide
   (`TGDialogListController.mm:411-415`). Ours squeezes the icon.
8. **The label is a full-bounds centred `UILabel` lifted by `-2 * retinaPixel`**
   (`TGIcons.m:146-148`), i.e. 1pt up on retina. That happens to match the original's portrait
   non-Back offset (−1.0pt, `.m:561`), so text position is right for Generic and Done — but the
   Back case (−0.5pt) has no equivalent because our back button is UIKit's.
9. **The back button is UIKit's, so its title is the previous screen's title, not "Back", and
   its font is UIKit's (bold 11 on iOS 6), not bold 12.** The original always wrote the word
   "Back" in bold 12 (`TGViewController.mm:606`, `.m:281`). Our plate art and cap width are
   right (`TGTheme.m:492-495`), the label is not. This is a real visual difference on every
   pushed screen and the most user-visible item after landscape. Note also that
   `UIBarButtonItem`'s back button will not honour the original's asymmetric 15/9 padding or
   the 1pt plate overhang.
10. **No `-16pt` bar-level hit shift.** `TGNavigationBar.m:535-541` gives the leftmost button an
    extra 16pt of grab area toward the screen edge. We have no `UINavigationBar` subclass doing
    this, so back is harder to hit than in the original.

If only two things get fixed: `minWidth` (item 2) and the Done plate (item 1) — both are
one-line changes in `TGIcons.m` and both are visible on the first screen a user sees.

## 10. What became of it

**twelve** (`submodules/LegacyComponents/LegacyComponents/TGToolbarButton.{h,m}`) keeps the class
essentially byte-identical — same types, same 12pt bold, same paddings, same
`backgroundRectForBounds:` nudges. The only substantive addition is a
`TGClassicIOS6Style` `NSUserDefaults` escape hatch: when set, the button builds a plain
`UIButton` of type `RoundedRect` as a child, blanks all four background plates, and forwards
its tap through `nativeClassicButtonPressed` (twelve's `TGToolbarButton.m:358-379, 387-397`,
and the early-outs at `:568-573` and `:602-606`). Highlight there is white at 0.55 alpha instead
of a pressed plate. So in the fork's own lineage the component was not redesigned; it grew a
switch to *stop* drawing itself. That is the clearest evidence available that the plate was the
whole component and the layout logic was considered correct as-is.

**Modern** (`submodules/TelegramUI/Components/NavigationBarImpl/Sources/NavigationButtonNode.swift`)
abandons the plate entirely. `NavigationButtonItemNode` draws text only, system 17pt —
`Font.medium(17.0)` normally, `Font.semibold(17.0)` when bold (`:217`), with `Font.bold(17.0)`
for one case at `:161`. Pressed feedback is `alpha = 0.4` (`:515`), not a second image. The
touch target moved from the button's own `touchInset` to a node-level `hitTestSlop` of
`(-16, -10, -16, -10)` (`:402`), and back buttons get `(0, -20, 0, 0)` (`:660`) — the same
"reach further toward the left edge" idea as the 2013 navigation bar's `-16` probe, now
declared on the node instead of hacked into `hitTest:`. `NavigationBackButtonNode.swift` draws a
chevron image plus a label with `arrowSpacing = 4.0` (`:20`) — the identical 4pt gap the 2013
class used between its label and image (`.m:574`), just mirrored (arrow left of text now,
image right of text then).

Reading the two together: the 12pt font, the two shadow colours, the bevel half-pixel nudges and
the six plate types were all consequences of drawing a raised object on a dark textured bar. Once
iOS 7 removed the bar, every one of them evaporated and what survived is exactly the part that
was about *touch* rather than *paint*: the oversized hit rect, the extra reach on the back
button, and the 4pt gap between glyph and word. For our port that means the plate metrics are
period costume we must copy exactly, while the hit-testing is a genuinely good idea we should
copy for reasons that still apply.

## 11. Ambiguities

- `((int)(labelFrame.origin.x * 2.0f)) / 2` (`.m:583`) is integer division and so rounds to
  whole points; the surrounding `* 2 … / 2` idiom says half-points were intended. I have
  documented the behaviour (whole points), not the intent, but a reader comparing against a
  screenshot should know the author probably wanted half-point snapping.
- `sizeToFit` omitting the 4pt spacing (`.m:518-541`) is almost certainly a bug rather than a
  design; no shipping call site exercises it, so there is no screenshot evidence either way.
- The exact on-screen y of a bar button depends on `barButtonsOffset` from whatever container
  the caller wraps it in, and only the conversation screen supplies one
  (`TGConversationController.mm:215-218`). For a plain `UIBarButtonItem` custom view, UIKit
  positions the view and the `origin.y` written at `.m:496-511` is then partly overridden by the
  bar's own layout. I could not determine from source alone which wins on iOS 6; treat the
  7/3 portrait/landscape numbers as a fallback, not as a measured target.

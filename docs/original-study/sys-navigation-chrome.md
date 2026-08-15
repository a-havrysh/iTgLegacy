# Navigation chrome (2013)

Scope: the navigation bar as a system — its painted background, the shadow under it, the back
button, the title view (single-line and the two-line title-with-status used in a conversation),
the transitions between screens, and what all of it did in landscape.

Sources, abbreviated below:

- `ORIG` = `/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
  (Telegram for iOS v1.1, build 21024). Authority.
- `TWELVE` = `/Users/alexanderhavrysh/Git/iOS/twelve` (later ObjC fork, same lineage).
- `MODERN` = `/Users/alexanderhavrysh/Git/iOS/Telegram-iOS`.
- `OURS` = `/Users/alexanderhavrysh/Git/iOS/iTgLegacy`.

Everything in section 1–6 is the original. Section 7 onwards is comparison and judgement.

---

## 1. The bar object

`TGNavigationBar` is a `UINavigationBar` subclass (`ORIG/TelegraphKit/TelegraphKit/TGNavigationBar.h:13`)
that never lets UIKit paint anything. Three facts drive everything else:

1. `-setBackgroundColor:` is overridden to force `clearColor` no matter what the caller passes
   (`TGNavigationBar.m:151-157`), and `-drawRect:` is empty (`TGNavigationBar.m:492`). UIKit's own
   bar art is therefore completely suppressed; every pixel comes from subviews.
2. `-setBarStyle:` is overridden to coerce *any* style to `UIBarStyleBlackTranslucent`
   (`TGNavigationBar.m:293-301`). That is deliberate: a translucent black bar is the one style where
   UIKit draws nothing of its own and where the status bar sits over the bar rather than above it.
   The *visible* style is then chosen independently by the alpha of two background subviews (§2).
   Note the contradiction: `-resetBarStyle` (`TGNavigationBar.m:311-323`) branches on
   `UIBarStyleDefault` / `UIBarStyleBlack`, values `-setBarStyle:` guarantees can never be stored.
   `resetBarStyle` is therefore dead in practice for the plain setter path and only does anything
   after `-setBarStyle:animated:duration:` (`TGNavigationBar.m:303`), which calls
   `super setBarStyle:` directly and *does* store the real value. This is a genuine inconsistency in
   the original; do not try to make it coherent, just reproduce the effect.
3. `self.clipsToBounds = false` (`TGNavigationBar.m:145`), and `layoutSubviews` re-clears
   `clipsToBounds` on every child on every pass (`TGNavigationBar.m:290-293`). The bar deliberately
   draws outside itself: the drop shadow below it, the unread badge above the back button.

`commonInit` also sets `multipleTouchEnabled = false` and `exclusiveTouch = true`
(`TGNavigationBar.m:83-84`) — no two bar buttons can be pressed at once.

## 2. The background art

The bar background lives in `_backgroundContainer`, a full-bleed autoresizing subview whose own
backgroundColor is **black** (`TGNavigationBar.m:105-113`). That black matters: the bar art has
transparent rounded top corners (see below), so the black shows through them, which is what produced
the 2013 "rounded screen corners" look under the status bar.

Inside the container, stacked:

| layer | what | citation |
| --- | --- | --- |
| `_defaultView` | `UIImageView` with the blue header art | `TGNavigationBar.m:115-122` |
| `_blackView` | plain `UIView`, pattern-colour black art, `alpha 0` | `TGNavigationBar.m:124-130` |
| `_actionOverlayView` | lazily created press highlight | `TGNavigationBar.m:496-506` |

`_backgroundContainer` is sent to the back on every `layoutSubviews` (`TGNavigationBar.m:233`).

### 2.1 Assets and exact colours

Chosen once, in a `dispatch_once`, at `TGNavigationBar.m:87-101`:

- If the OS supports `resizableImageWithCapInsets:` (iOS 5+, so always for us):
  `Header_Corners.png` / `Header_Corners_Landscape.png`, each made resizable with
  `UIEdgeInsetsMake(0, 8, 0, 8)` — 8pt caps left and right, vertically **stretched, not tiled**.
- Otherwise (iOS 4 fallback): `Header.png` / `Header_Landscape.png` as a `colorWithPatternImage:`
  tile. Those two files are not present in the shipped resources folder; the fallback is dead code
  on any device we care about.
- Black opaque variant: `HeaderBlackOpaque.png` / `HeaderBlackOpaque_Landscape.png`, always applied
  as a *pattern colour* (`TGNavigationBar.m:52-56`), never as a resizable image.

Measured pixels (`ORIG/Telegraph/Telegraph/Resources/`, @2x files, so divide by 2 for points):

`Header_Corners@2x.png` — 88×88 px = **44×44 pt**, i.e. exactly the portrait bar height. Vertical
gradient down the middle column:

| y (px) | colour |
| --- | --- |
| 0 | `#769ABB` (118,154,187) |
| 1 | `#6E93B7` |
| 2 | `#6890B5` |
| 22 | `#6187AD` |
| 44 | `#547AA1` (84,122,161) |
| 66 | `#486D95` |
| 86 | `#3D628A` (61,98,138) |
| 87 | `#0D2D53` (13,45,83) |

So: a smooth top-to-bottom blue gradient from `#769ABB` to about `#3D628A`, closed by a **single
device-pixel (0.5 pt) dark line `#0D2D53`** at the very bottom. That hairline is the bar's edge; it
is part of the image, not a separate view.

The top corners are cut out: at y=0 the leftmost 8 px are fully transparent and alpha ramps to 255
by about x=16 px (`alpha 204 at x=8`), and the cut-out ends around y=8 px. That is a **4 pt corner
radius** on the top-left and top-right, which is exactly why the cap inset is 8 pt (16 px) — the cap
must contain the whole arc. Behind it, `_backgroundContainer`'s black shows.

`Header_Corners_Landscape@2x.png` — 64×64 px = **32×32 pt**, the landscape bar height. Same gradient
endpoints (`#769ABB` → `#3D628A`) compressed into 32 pt, same corner treatment, and a bottom line of
`#1F436D` (slightly lighter than portrait's). This is the whole reason a second asset exists: a
gradient stretched from 44 pt to 32 pt would not match one authored at 32 pt, and both are on screen
across a rotation animation.

`HeaderBlackOpaque@2x.png` — 64×88 px, a flat vertical grey ramp `#4E4E4E` at top → `#2D2D2D` at
mid → `#000000` at the bottom rows. Used for media/photo screens.

`HeaderActionOverlay@2x.png` — 32×88 px, a uniform `rgba(32,61,98,0.25)` wash with the top edge
faded at the left/right ends; stretched from its horizontal midpoint
(`TGNavigationBar.m:194-204`).

### 2.2 Portrait vs landscape selection

The test is not the interface orientation. It is literally:

```objc
bool isLandscape = self.frame.size.width > 400;
```

(`TGNavigationBar.m:171` in `updateBackground`, `TGNavigationBar.m:235` in `layoutSubviews`.) On a
320×480 phone, 480 > 400 so landscape is detected; on a 4-inch phone, 568 > 400. The threshold works
because no portrait phone width of the era exceeded 400. `layoutSubviews` compares the computed
value against the cached `_currentBackgroundsAreLandscape` and calls `updateBackground` only on
change (`TGNavigationBar.m:237-240`) — the swap happens during the rotation animation, not after it.

Under stretching support the swap is `((UIImageView *)_defaultView).image = isLandscape ? ... : ...`
(`TGNavigationBar.m:180-183`); the black variant always swaps its *pattern* background colour
(`TGNavigationBar.m:185`).

### 2.3 The style crossfade

`-updateBarStyle:previousBarStyle:animated:duration:` (`TGNavigationBar.m:395-489`) is the only
place the visible style changes, and it works purely by alpha and z-order:

- `UIBarStyleDefault`: bring `_defaultView` to front, animate it to `alpha 1`, and the navigation
  controller's `cornersImageView` to `alpha 1`; on completion set `_blackView.alpha = 0`.
- `UIBarStyleBlackOpaque`: bring `_blackView` to front, `alpha 1`, corners `alpha 1`, then
  `_defaultView.alpha = 0` on completion.
- `UIBarStyleBlackTranslucent`: `_blackView.alpha = 0.5`, `_defaultView.alpha = 0`, and the
  navigation controller's corners fade to **0** — the only style where the corner mask disappears,
  because full-screen media must reach the physical corners.

Setting the target alphas *before* the animation and zeroing the outgoing layer only in the
completion block is what stops a bright flash mid-crossfade. Copy that ordering.

### 2.4 The drop shadow

`_shadowView` is a `UIImageView` positioned at `y = bar height`, i.e. entirely **below** the bar,
with the image's own height and `FlexibleWidth | FlexibleTopMargin`
(`TGNavigationBar.m:138-143`). `HeaderShadow@2x.png` is 4×2 px, uniform `rgba(7,19,31,0.141)` —
a **1 pt tall, 14% dark wash**, not a gradient. It only reads because it is drawn over content, and
it only survives because the bar does not clip (§1.3).

`-setShadowMode:` with `dark = true` swaps in `HeaderLoginShadow.png` (2×4 px = 1×2 pt) and re-frames
the view to its height (`TGNavigationBar.m:159-168`). There is no way back to the light shadow —
the method silently does nothing when passed `false`. Login screens set it once and never unset it.

`setHiddenState:animated:` fades both the shadow and `_progressView` to 0 over 0.3 s and, for the
duration of the animation only, inserts a black 20 pt `_statusBarBackgroundView` at
`y = -self.frame.origin.y` so the status bar does not flash the content behind it while the bar
slides away (`TGNavigationBar.m:355-390`). That view is re-framed from both `-setFrame:` and
`-setCenter:` (`TGNavigationBar.m:325-353`) because UIKit animates bars via `center`, not `frame`.

## 3. Bar buttons

### 3.1 `TGToolbarButton`

All bar buttons are `TGToolbarButton` (`ORIG/TelegraphKit/TelegraphKit/TGToolbarButton.m`), a
`UIButton` subclass placed inside a `UIBarButtonItem` as a `customView`. Types: Back, Generic, Done,
DoneBlack, Image, Delete, Custom.

Geometry, from `initWithType:` and `sizeToFit` (`TGToolbarButton.m:216-259`, `:439-462`):

- Height: **30 pt portrait, 25 pt landscape** (`TGToolbarButton.m:441`, `:434`).
- Padding: `paddingLeft = paddingRight = 7` for everything *except* Back, which uses
  `paddingLeft = 15, paddingRight = 9` (`TGToolbarButton.m:228-234`). The extra 15 on the left is
  the width of the chevron notch baked into the back-button art.
- Width = `paddingLeft + label + (4 pt spacing if both label and image) + image + paddingRight`,
  clamped up to `minWidth` (`TGToolbarButton.m:439-462`, spacing at `:497-499`).
- Label font: **bold system 12** for every button type (`TGToolbarButton.m:236`). White text
  (`textColorForButton`, `TGToolbarButton.m:178-192`), shadow offset `(0,-1)`, shadow colour
  `rgba(0x0E284D, 0.4)` normally and `rgba(0x042651, 0.3)` for Done/DoneBlack
  (`TGToolbarButton.m:194-208`).
- Disabled state dims only the *label* to `alpha 0.6`, never the background art
  (`TGToolbarButton.m:557-562`), and `adjustsImageWhenDisabled/Highlighted` are both off
  (`TGToolbarButton.m:250-252`).
- Touch slop: `hitTest:` accepts anything inside `CGRectInset(bounds, -8, -8)`
  (`TGToolbarButton.m:583-591`, inset from `_touchInset = (8,8)` at `:222`).

Vertical placement is set by the button itself when the orientation flips
(`-setIsLandscape:`, `TGToolbarButton.m:487-517`):

- If the superview conforms to `TGBarItemSemantics`, `origin.y = (landscape ? 2 : 0) + barButtonsOffset`.
- Otherwise `origin.y = landscape ? 3 : 7`.
- `size.height = landscape ? 25 : 30`.

The conversation controller's containers supply `barButtonsOffset = 0` for the back button and `4`
for everything else (`ORIG/TelegraphKit/TelegraphKit/TGConversationController.mm:217-220`).

Sub-pixel fussiness inside `layoutSubviews` (`TGToolbarButton.m:464-534`), all of it load-bearing on
a retina 4S: the label's y is `(height - labelHeight)/2 - (landscape ? 1 : 0) - 0.5 + (landscape ? 1 : 0)`
minus another 0.5 for non-back buttons in portrait; x positions are snapped to half-points on retina
and floored otherwise; a back button in landscape shifts its label 1 pt left (`:531-532`).
`backgroundRectForBounds:` shifts the art down 0.5 pt in retina landscape, and for Back widens it by
1 pt to the left and drops it 0.5 pt in retina portrait (`TGToolbarButton.m:571-586`).

### 3.2 Back button art

Type Back uses `BackButton.png` / `BackButton_Pressed.png` in portrait and
`BackButton_Landscape.png` / `BackButton_Landscape_Pressed.png` in landscape, each
`stretchableImageWithLeftCapWidth:15 topCapHeight:0` (`TGToolbarButton.m:5-33`). The 15 pt left cap
is the arrow head; the right side stretches. `BackButton@2x.png` is 54×60 px = **27×30 pt**, so the
unstretched art is exactly the 30 pt button height; `BackButton_Landscape@2x.png` is 60×50 px =
**30×25 pt**. Interior fill around the vertical middle is `#3F6993` (63,105,147), with a `#194778`
top edge.

Generic buttons use `HeaderButton.png` with a **6 pt** left cap (`TGToolbarButton.m:35-49`);
42×60 px = 21×30 pt. Done buttons (`HeaderButton_Blue*`) stretch from their own horizontal midpoint
(`TGToolbarButton.m:65-107`).

### 3.3 The bar's 16-point left bias

```objc
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *view = [super hitTest:CGPointMake(point.x - 16, point.y) withEvent:event];
    if (view != nil && [view isKindOfClass:[TGToolbarButton class]] && ...)
        return view;
    return [super hitTest:point withEvent:event];
}
```

(`TGNavigationBar.m:535-542`.) Every touch in the bar is first re-tested 16 pt to the **left**; if
that lands on a visible toolbar button, that button wins. Practical effect: the back button gains a
16 pt hit strip to its right, on top of its own 8 pt inset, because in 2013 the back button was the
one control users hit blind. It cannot make a *right*-side button easier to hit — the bias is
one-directional, which is a deliberate asymmetry, not a bug.

### 3.4 Tapping the bar itself, and swiping it

Touching a part of the bar with no gesture recognisers in its view chain, when the top view
controller answers `navigationBarHasAction`, shows `_actionOverlayView` at full alpha immediately
(`TGNavigationBar.m:521-533`); releasing fades it out over 0.34 s with
`UIViewAnimationOptionBeginFromCurrentState` and calls `navigationBarAction`
(`TGNavigationBar.m:544-568`); a cancelled touch fades it without firing (`:570-576`).

A `UISwipeGestureRecognizer` in the **down** direction on the bar calls `navigationBarSwipeDownAction`
(`TGNavigationBar.m:132-134`, `:578-587`).

## 4. Titles

### 4.1 The fonts, in one place

`ORIG/TelegraphKit/TelegraphKit/TGViewController.mm`:

| purpose | portrait | landscape | citation |
| --- | --- | --- | --- |
| plain screen title (`titleFontForStyle:`) | bold 20 | bold 17 | `:79-95` |
| conversation title line (`titleTitleFontForStyle:`) | bold 16 | bold 15 | `:97-113` |
| conversation subtitle (`titleSubtitleFontForStyle:`) | regular 13 | regular 13 | `:115-131` |

Colour is white in every style (`:133-149`). Shadow is `#3D5C81` for the default style and
`#2F3948` otherwise (`:151-167`), offset `(0,-1)` in both (`:169-179`).

Caveat worth recording: `titleSubtitleFontForStyle:` (regular 13) is defined but the conversation
status labels do **not** use it — they hardcode `boldSystemFontOfSize:12`
(`TGConversationController.mm:780`, `:792`). The 13 pt regular subtitle is what plain two-line
screens would have used. Where the two disagree, the conversation is authoritative for chat headers:
**bold 12**.

`TGLabel` carries `portraitFont`/`landscapeFont` and swaps on `-setLandscape:`; `TGNavigationBar`
walks its whole subview tree on every layout and pushes the current orientation into every
`TGToolbarButton` and every object responding to `setLandscape:`
(`TGNavigationBar.m:206-226`, called at `:242`). That recursive walk is the mechanism by which
titles and buttons re-font themselves — nothing observes rotation notifications.

### 4.2 Single-line title

`-setTitleText:` (`TGViewController.mm:429-466`) creates a `TGLabel` with
`verticalAlignment = Top`, installs it as `navigationItem.titleView`, then:

```objc
_titleLabel.frame = CGRectMake(0, 0, 480, 44);   // measuring box
[_titleLabel sizeToFit];
titleLabelFrame.size.height += 2;                 // descender headroom
titleLabelFrame.origin.x = (int)((self.view.frame.size.width - w) / 2);
titleLabelFrame.origin.y = (int)(((portrait ? 44 : 32) - h) / 2) + 1;
```

Two constants to keep: the **+2 pt** added height (a top-aligned label clips descenders otherwise)
and the **+1 pt** downward nudge, which compensates for that same +2. Bar heights are the literals
`44` and `32`.

`-fadeInTitleText` cross-fades a title change over 0.3 s (`TGViewController.mm:419-427`).
`TGMainTabsController` instead uses a 0.1 s `CATransition` with `easeIn` when the tab changes the
title (`ORIG/Telegraph/Telegraph/TGMainTabsController.m:585-591`), and centres the label inside a
`_titleLabelContainer` rather than on the screen (`:551`).

### 4.3 The two-line conversation title

Built in `TGConversationController.mm:756-834`. Structure:

```
_titleContainer                      <- navigationItem.titleView; frame computed per layout
  _titleLabelsContainer              <- flexible W/H; hidden while syncing
    _titleTextLabel                  <- TGLabel, bold 16/15, left-aligned, truncating tail,
                                        vertical align Center
    _titleStatusLabelNormal          <- TGLabel, bold 12, centred, vertical align Top
    _titleStatusLabelTyping          <- same, alpha 0, holds the typing dots subview
  _titleStatusContainer              <- connection-state spinner, replaces the labels
```

Status colours (`TGConversationController.mm:1641-1648`): `#E0EEFD` when the text equals
`Presence.online`, `#C9DCF2` for everything else. Both labels are created with `#E0EEFD` and shadow
`#3D5C81` offset `(0,-1)` (`:781-783`, `:793-795`). Empty text is stored as a single space `@" "`,
never as `nil` or `@""` (`:777`, `:789`, `:1040-1043`) — a zero-height label would collapse the
container arithmetic, so the space guarantees a measurable line box.

#### Width budget (`updateTitle:animated:`, `:1855-2126`)

```objc
leftButtonWidth  = leftBarButtonItem.customView.width  + 13;
rightButtonWidth = rightBarButtonItem.customView.width + 13;
titleMaxWidth    = screenWidth - leftButtonWidth - rightButtonWidth - 8;
subtitleMaxWidth = titleMaxWidth;                      // before adjustments
```

(`:1884-1888`.) `screenWidth` comes from `TGViewController screenSizeForInterfaceOrientation:`
(`TGViewController.mm:199-215`), which swaps the *static* main-screen size — not the current bounds.

Adjustments, all subtractive on the title only:

- Secret chat: `titleMaxWidth -= 10`, and a `HeaderEncryptedChatIcon.png` lock (22×26 px = 11×13 pt)
  is added as a subview of the title label at offset `(-15, +4)` (`:1890-1902`).
- Message self-destruct timer set: `titleMaxWidth -= 40`, and a timer icon + a bold-10 label
  (`#C9DCF2`, shadow `#587DA3`) go in a container appended after the title (`:1904-1941`).
- A visible Done button takes another 30 pt off in portrait (`:1965-1966`).
- Typing status is measured against `subtitleMaxWidth - 26` in portrait, `- 20` in landscape
  (`:1986`, `:2065`) — that is the room the animated dots need.

#### Portrait layout (`:1953-2038`)

- Both labels are measured in a box of height `44`, `sizeToFit`, and every resulting width is
  **rounded up to an even number** (`:1976-1977`, `:1982-1983`, `:1990-1991`, `:2035-2036`). Odd
  widths would put a centred label on a half-point and blur the text on a 2× screen.
- Container width = `MAX(titleWidth, currentStatusWidth)`; height =
  `MIN(titleHeight + statusHeight, 44)` (`:1995`). The typing label, when it is the visible one, is
  inset by 10 pt on each side if it is wider than 22 pt (`:1993`) to reserve the dots' space.
- Container x = `floor((screenWidth - containerWidth)/2)`, then clamped to be at least
  `leftButtonWidth` (`:1999-2001`). **The container is centred on the screen, not in the space
  between the buttons**, and only slides right when it would otherwise underlap the back button.
- Title y = `-2 + titleOffsetY`, where `titleOffsetY` is `2 - 0.5` on iOS 7+ and `0` on iOS 6
  (`:1961`, `:2003`). For us, iOS 6: **title origin.y = -2**, which is correct because the label is
  vertically centred within its own 44 pt-derived height.
- Title x = `floor((containerWidth - titleWidth)/2 - titleOffset)` where `titleOffset` starts at
  `-1`, becomes `-6` for a secret chat and `+3` when a lifetime timer is showing (`:1955-1959`).
  If the title had to be truncated to the full `titleMaxWidth` and no timer is shown, it is shifted
  a further `+12` (`:2005`) — the truncated title leans right to make room for the lock/spacing.
- Status y = `containerHeight - statusHeight - 3 + 0.5(retina) + titleOffsetY` (`:2010`); both status
  labels share that y (`:2011`).
- Status x = `floor((containerWidth - statusWidth)/2 + 1)`; the typing variant is
  `floor((containerWidth - typingWidth - 20)/2 + 1 + 20)` (`:2006-2008`) — shifted right by 20 pt so
  the dots, which live at x = -24 relative to the label, fit inside the container.
- A mute icon, if present, pulls the title 3 pt left and sits 4 pt past its right edge, 6 pt down
  (`:2013-2022`).
- Final frames go through `CGRectIntegral` (`:2024-2026`, `:2033`).

#### Landscape layout (`:2040-2126`)

Landscape is not "the same thing, shorter". The two lines become **one line, side by side**:

- `titleSpacing = 6`; `subtitleMaxWidth = titleMaxWidth * 2/5`, `titleMaxWidth -= subtitleMaxWidth`,
  and each then loses `titleSpacing/2` (`:2044-2049`). The status gets exactly two fifths of the
  available run.
- Container width = `titleWidth + 6 + statusWidth` (`:2073`), height still capped at 32.
- Title at x = 0, y = `(containerHeight - titleHeight)/2 - 1 - 0.5(retina) + titleOffsetY`
  (`:2085-2086`, `titleOffsetY` = 1 on iOS 7+, 0 on iOS 6 at `:2042`).
- Status at x = `titleWidth + 6`, y = `(containerHeight - statusHeight)/2 - 1 + 0.5(retina)`
  (`:2088`, `:2091`). Typing variant starts 20 pt further right (`:2089`).
- Timer present: title -8, both statuses +19 (`:2094-2099`). Mute present: title -5, statuses +5
  (`:2101-2112`).
- The container frame change is animated over 0.3 s, but **only in landscape** — `animated` is
  forced false when `!isLandscape` or during the appearance animation (`:1948-1949`).

#### Typing indicator

`typingDotsContainer` is a 21×10 pt view at `(-24, 5)` **inside the typing status label**
(`:806-807`), backed by `TypingHeader.png` (24×20 px = 12×10 pt) stretched with a 6 pt left cap
(`:808-810`), holding three `TypingHeader_Dot.png` images at x = 4, 8.5, 13 and y = 3 (the 0.5
increments are `retinaPixel`, `:815-822`).

`-setStatusText:typingStatusText:animated:` (`:1633-1731`) is the whole state machine:

- Early-out if neither string changed, but still call `updateTitle:` (`:1635-1640`).
- Typing mode is on when the typing text is non-empty and not `@" "` (`:1675`).
- Crossfade: normal label to `alpha typing ? 0 : 1`, typing label to the inverse, 0.3 s, with
  `BeginFromCurrentState` (`:1677-1690`). Non-animated path sets both directly.
- When animating *out* of typing, the typing label's text is deliberately **not** updated
  (`:1670-1673`) so the outgoing text does not change under the fade.
- Two timers drive the dots: a short one at `TGDotInterval` and a period one at `TGDotPeriod`
  (`:1707-1716`), both added to `NSRunLoopCommonModes` so they keep running while the list scrolls.
  Leaving typing mode invalidates both (`:1693-1705`).
- Side effect that lives here for no good reason: a status text starting with `"you"` is treated as
  "you are blocked/kicked" and disables the input container (`:1650-1665`). Record it, don't imitate
  the string sniffing.

#### Sync state

When `_synchronizationStatus != None`, `_titleLabelsContainer` is hidden entirely and a
`_titleStatusContainer` (40×30 pt, y = 5 portrait / 3 landscape) with a spinner takes over
(`:1857-1869`, created at `:5520-5537`). Connecting/Updating is a *replacement* of the title, not a
subtitle change.

### 4.4 The unread badge on the back button

A 25×6 pt container at `(backButtonWidth - 13, -7)` is added **as a subview of the back button**
with `FlexibleLeftMargin` (`:838-844`), holding a stretchable badge image and a bold-12 white label
at `(9, 7.5)` sized 28.5×10 (`:846-852`). Its y becomes `-5` in landscape (`:1874-1879`). Width is
`MAX(25, textWidth + 18)`, right-aligned inside the container, and the label x follows the badge
(`:1837-1846`). Counts are abbreviated `1234 -> 1K`, `1234567 -> 1M` (`:1826-1833`). It draws above
the bar's top edge, which only works because nothing clips (§1.3).

## 5. Push and pop transitions

`TGNavigationController` (`ORIG/TelegraphKit/TelegraphKit/TGNavigationController.m`) hand-animates
the bar contents because UIKit's own bar transition did not match.

Push (`:247-343`), only when the bar's visibility does not change (`_wasShowingNavigationBar ==
!navigationBarShouldBeHidden`, `:269`):

- The **outgoing** screen's back button (any left item whose custom view conforms to
  `TGBarItemSemantics` and answers `backSemantics`) slides left by twice its own width over
  **0.4 s**, then resets its transform (`:281-297`).
- The **incoming** back button starts at
  `x = screenWidth/2 - incomingTitleWidth/2 - buttonWidth/2` — i.e. it starts where the *previous*
  screen's title was — and animates to identity over **0.35 s** (`:299-311`). That is the signature
  2013 move: the title you tapped becomes the back button you will tap.

Pop (`performPopTransition:...`, `:345-...`):

- The disappearing screen's back button slides to `targetX`, which is the *incoming* title view's
  centre when that screen has a title view, else `screenWidth/4`, over **0.355 s** (`:359-380`).
- The reappearing screen's title view starts at `alpha 0`, translated `-screenWidth/2`, and animates
  to identity over 0.355 s (`:388-397`); its back button starts at `-2 × width` and slides in
  (`:399-411`).

Note the asymmetric durations — 0.4 / 0.35 on push, 0.355 on pop. They are not typos in this study;
they are what the source says.

`TGNavigationController` also owns the screen-corner mask: a `BlackCornersBottom.png` image view,
stretched from its midpoint, pinned to the bottom of the controller's view
(`:52-58`), and optionally a plain black 320×50 view at `zPosition -10` behind everything
(`blackCorners:`, `:60-67`). `cornersImageView` (declared `TGNavigationController.h:22`) is what the
bar's style crossfade fades in and out (§2.3).

`-setNavigationBarHidden:animated:` calls `resetBarStyle` when visibility actually changed
(`:239-245`).

## 6. iOS 7 manual bar-item layout

Under iOS 7+ the bar re-positions its own items in `layoutSubviews` (`TGNavigationBar.m:246-284`),
because iOS 7 stopped honouring custom-view frames:

- left item: `x = 5` portrait, `3` landscape, y vertically centred (`:254-263`);
- right item: `x = width - itemWidth - 5` / `- 3` (`:265-273`);
- title view: centred both ways (`:275-281`).

On iOS 6 this block does not run at all, and the frames set in §3.1/§4.3 are what UIKit uses.
Since we target 6.1.3 this whole path is inert for us — but it tells you what the intended
*resting* geometry was: left inset 5 pt portrait, 3 pt landscape.

---

## 7. What the modern client did with this, and why

`MODERN/submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift`:

- **The art is gone.** No gradient, no corner cut-outs, no shadow image; the bar is a flat
  colour with a hairline, drawn by the theme system. Everything §2 describes was made obsolete by
  iOS 7's flat bars. This is the single largest divergence and it is exactly what we are
  deliberately not following.
- **Fonts drifted up**: title is 17 pt semibold with monospaced numerals, status 13 pt regular
  (`ChatTitleView.swift:26-27`). Ours is a 16/12 world; theirs is a 17/13 world. The monospaced-digit
  trait is a real lesson though — a member count or a "last seen" time that reflows on every digit
  change looks broken, and the original had no answer for it.
- **The width budget survives, restated**: `titleSideInset = 12 + 8` on each side
  (`ChatTitleView.swift:1024`), content x clamped to at least 20 pt (`:1051`), and the title frame
  clamped to `leftIconWidth` (`:1055`) — structurally the same "centre on the bar, then push right
  off the back button" rule as `:1999-2001` in the original.
- **Icons became a list, not a set of special cases.** The original hardcodes lock, timer and mute
  each with its own hand-tuned offsets. The modern one has credibility/verified/status/left-icon
  slots with widths folded into the measurement pass (`:1032-1041`, `:1076-1080`). The original's
  approach is why adding a fourth badge to that title is so painful.
- **Landscape as a distinct layout is gone**; the modern client has one layout and lets the
  container size drive it.

## 8. What `twelve` did when it had to extend this

`TWELVE/Telegraph/TGModernConversationTitleView.m` is the direct descendant of §4.3, and its changes
are the ones we should learn from:

- The title became a **real reusable view class** with its own `layoutSubviews`
  (`:717`) instead of 190 lines inside the conversation controller. Same maths, one owner.
- **Icons became data**: `TGModernConversationTitleIcon` objects with `iconPosition`
  (before/after title), an `imageOffset`, and an `offsetWeight` that decides how much of the icon's
  width shifts the title versus how much just extends it (`:797-805`, `:860-880`). That is precisely
  the generalisation of the original's `titleOffset -= 5` for the lock and `+= 4` for the timer.
- **Orientation is pushed in, not sniffed**: `-setOrientation:` re-fonts the labels and marks the
  view dirty (`:640-668`). Same idea as the original's recursive `setLandscape:` walk, but explicit.
- **Landscape is still one line, side by side**, with `spacing = 6` and `+18` more when typing
  (`:888-891`) — the original's 6 pt spacing survived thirteen years and one rewrite, so treat it as
  settled.
- The status change animation grew a **snapshot cross-fade** with a 0.12 s title slide
  (`:616-637`) instead of the original's plain 0.3 s alpha swap.
- The back-button width is *computed* from its title (`sizeWithFont + 27 + 8`, `:780`) rather than
  read off a custom view, because by then the back button was a system item again.

## 9. Our port: judgement

Files: `OURS/src/TGTheme.m`, `OURS/src/TGIcons.m`, `OURS/src/TGChatViewController.m`,
`OURS/src/TGChatListViewController.m`, `OURS/src/TGLabel.m`, `OURS/images/`.

### What is already right

- `images/NavBarBackground@2x.png` is **byte-identical** to the original `Header_Corners@2x.png`
  (md5 `de4adeeb…` both), and `images/BackButton@2x.png` is byte-identical to the original
  (md5 `aa6a2f53…`). The art is genuine, not re-drawn.
- `TGTheme.m:468-475` applies it with `UIEdgeInsetsMake(0, 8, 0, 8)` — the correct cap insets from
  `TGNavigationBar.m:93`.
- `TGTheme.m:487-501` stretches the back button with `leftCapWidth:15`, matching
  `TGToolbarButton.m:5-12`.
- `TGIcons.m:133-162` (`headerButtonWithTitle:bold:`) reproduces the generic/Done header button
  faithfully: bold 12 label, 30 pt height, `size.width + 14` (= the 7 + 7 padding of
  `TGToolbarButton.m:230-231`), white text, and the exact shadow colours `rgba(0x042651,0.3)` for
  Done and `rgba(0x0E284D,0.4)` otherwise (`TGToolbarButton.m:194-208`). Good.
- `TGLabel.m:21-24` implements `setLandscape:` with the portrait/landscape font pair, mirroring the
  original `TGLabel`. Correct — but nothing calls it (see D6).

### Defects

**D1 — No landscape bar background.** `OURS/images/` contains no `Header_Corners_Landscape`
equivalent (the only "Landscape" files present are iPad launch images), and `TGTheme.m:468-475`
registers a single background for `UIBarMetricsDefault` only. In landscape the 44 pt-authored
gradient is vertically squashed into a 32 pt bar, so the gradient midpoint lands in the wrong place
and the 0.5 pt bottom hairline is resampled. Fix: add the landscape art (44 pt and 32 pt variants
exist for exactly this reason — `TGNavigationBar.m:91-93`, asset heights 88 px and 64 px) and
register it with `setBackgroundImage:forBarMetrics:UIBarMetricsLandscapePhone`.

**D2 — No drop shadow under the bar.** Nothing in our source references `HeaderShadow`, and the
asset is not in `OURS/images/`. The original always has a 1 pt `rgba(7,19,31,0.141)` wash directly
below the bar (`TGNavigationBar.m:138-143`, `HeaderShadow@2x.png` = 4×2 px). Without it the bar sits
flat on the content and the header stops reading as a raised plate. Fix: add the asset and either a
`UIImageView` pinned under the bar (requires `clipsToBounds = NO`, cf. `TGNavigationBar.m:145`) or,
if we keep a stock `UINavigationBar`, bake it into a 45 pt-tall background image — but note that a
baked shadow will be clipped by the bar's own bounds, so the subview is the honest option.

**D3 — Two-line conversation title uses the wrong fonts, colours and geometry.**
`OURS/src/TGChatViewController.m:2889-2915` (`buildTitleView`) uses:
name `boldSystemFontOfSize:17`, subtitle `systemFontOfSize:12` at `white alpha 0.75`, name shadow
`black alpha 0.4`, no subtitle shadow, fixed frames `(0,1,200,20)` and `(0,21,200,14)` in a fixed
200×40 container.

The original (`TGConversationController.mm:764-800`, `TGViewController.mm:97-113`, `:151-167`):
title **bold 16** portrait / **bold 15** landscape, white, shadow `#3D5C81` offset `(0,-1)`;
status **bold 12** (not regular), `#E0EEFD` when online / `#C9DCF2` otherwise
(`TGConversationController.mm:1641-1648`), shadow `#3D5C81` offset `(0,-1)`. Fix all six values.

**D4 — The title container is a fixed 200×40 box.** The original computes it every layout:
width = `MAX(title, status)` rounded up to even, height = `MIN(titleH + statusH, 44)`, x centred on
the *screen* and clamped to `leftButtonWidth`, with a width budget of
`screenWidth - (leftItem + 13) - (rightItem + 13) - 8` (`TGConversationController.mm:1884-1888`,
`:1995-2001`). Consequences of ours, with real data: a short name like "Bob" is padded to 200 pt and
UIKit's own centring then fights the back button; a long group name is truncated at 200 pt even
though a 320 pt bar with a 27 pt back button and a 37 pt avatar leaves roughly 220 pt. Fix: compute
the container as above, including the **even-width rounding** (`:1976-1977`) — without it, centred
bold text lands on a half point and blurs on the 4S.

**D5 — Vertical placement of the two lines is invented.** Ours hardcodes y = 1 and y = 21. The
original places the title at `origin.y = -2` (iOS 6, `:2003` with `titleOffsetY = 0` from `:1961`)
and the status at `containerHeight - statusHeight - 3 + 0.5` (`:2010`). Those come out differently
from 1/21 and are what makes the pair sit optically centred in a 44 pt bar rather than 1 pt low.

**D6 — No landscape behaviour anywhere in the chrome.** In landscape the original (a) swaps to the
32 pt gradient, (b) re-fonts title to bold 15 and buttons to 25 pt height, (c) **re-lays the title
as one line, title and status side by side with 6 pt between them** and the status limited to 2/5 of
the run (`TGConversationController.mm:2040-2126`), (d) moves the unread badge from y −7 to −5. We do
none of it: `TGChatViewController.m` never re-lays the title view, `TGLabel setLandscape:` is dead
code (no caller in `OURS/src`), and there is no equivalent of the bar's recursive orientation walk
(`TGNavigationBar.m:206-226`). If we intend to support landscape at all, the title must be rebuilt
side-by-side; if we do not, we should say so and lock the orientation, not ship a squashed portrait
layout.

**D7 — No typing indicator, only a text swap.**
`TGChatViewController.m:2921-2928` sets `subtitle.text = action ?: restingSubtitle` directly. The
original keeps **two** status labels and crossfades them over 0.3 s with `BeginFromCurrentState`
(`:1677-1690`), deliberately not updating the outgoing label's text mid-fade (`:1670-1673`), and
animates three dots on a `TypingHeader.png` pill at `(-24, 5)` inside the typing label
(`:806-822`) with timers in `NSRunLoopCommonModes` (`:1707-1716`). Ours also loses the 26 pt width
reservation the dots need (`:1986`). This is the most visible missing behaviour in the whole topic.

**D8 — Status colour never varies with presence.** `TGChatViewController.m:2906-2908` uses one
colour for every status. The original swaps `#E0EEFD` (online) against `#C9DCF2` (everything else)
on each update (`:1641-1648`). Online-ness being legible at a glance is the point of the line.

**D9 — Back button is the system one, so its title is the previous screen's title.** There is no
`backBarButtonItem` assignment anywhere in `OURS/src`; `TGTheme.m:477-508` only re-skins whatever
UIKit produces. The original always used a literal `Common.Back` label on a `TGToolbarButton`
(`TGConversationController.mm:836-847`). Ours will render "Chats", "Settings", or a truncated
group name inside 2013 back-button art that was authored around a short word, and a long previous
title will make the button eat the title's width budget. Fix: set an explicit `backBarButtonItem`
with the title "Back" (or a custom-view button) on every pusher.

**D10 — Missing bar affordances.** None of the following exist in our port: the 16 pt left hit-test
bias that widens the back button's target (`TGNavigationBar.m:535-542`), the 8 pt touch inset on bar
buttons (`TGToolbarButton.m:583-591` — our `TGIcons` header button sets no custom `hitTest:`), the
press overlay + `navigationBarAction` on tapping the bar (`TGNavigationBar.m:521-568`), the
swipe-down gesture (`:132-134`, `:578-587`), and the unread badge over the back button
(`TGConversationController.mm:838-852`). The first two are pure ergonomics on a 3.5-inch screen and
are cheap; the badge is a real feature of the 2013 conversation header.

**D11 — Bar style handling is inverted relative to the original.** `TGTheme.m:442-465` sets
`bar.barStyle` from the theme and relies on UIKit. The original forces
`UIBarStyleBlackTranslucent` unconditionally (`TGNavigationBar.m:293-301`) and expresses the visible
style purely as the alpha of two stacked background layers (`:395-489`), which is also what lets the
default→black transition crossfade instead of cutting. We currently cannot crossfade at all. This is
lower priority than D1–D9, but it is the reason a style change in our build snaps.

### Where the original is genuinely ambiguous

- **The 400 pt landscape threshold** (`TGNavigationBar.m:171`) is a width heuristic, not an
  orientation query. On an iPhone it is exact. Keep the heuristic rather than "improving" it to an
  orientation check — the bar is asked to re-lay itself mid-rotation, when the orientation property
  and the frame disagree, and the frame is the one that is right.
- **`resetBarStyle` is unreachable through the plain setter** (§1.2). Either the coercion or the
  reset is a bug; the source does not say which. Reproduce the observable behaviour and do not
  build on `barStyle` as a stored value.
- **Subtitle font, 13 regular vs 12 bold**: `titleSubtitleFontForStyle:` says regular 13
  (`TGViewController.mm:115-131`) but the only two-line title in the app hardcodes bold 12
  (`TGConversationController.mm:780`, `:792`). We follow bold 12 for chat headers and note that a
  non-conversation two-line header, had one existed, would have been 13 regular.
- **The `"you"` prefix check** driving input-bar enablement (`:1650-1665`) is string sniffing on a
  localised status; it cannot have worked outside English. Do not port it.

# The tab bar (2013)

Scope: the whole tab bar as a system — where it lives in the view hierarchy, the three PNGs it is
made of, the selected-indicator stretch arithmetic, the unread badge geometry, the label treatment,
the touch model, and the `UILayoutContainerView` swizzle without which none of it could be
translucent.

Source of truth unless stated otherwise:
`telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGMainTabsController.m`
(hereafter **MTC**). `TGTabBar` is a *private* class declared and implemented at the top of that
file (MTC:24–266); there is no `TGTabBar.h` in the original. Supporting files:
`TelegraphKit/TelegraphKit/TGHacks.m` (hereafter **HACKS**),
`TelegraphKit/TelegraphKit/TGViewController.mm` (**TGVC**), and the PNGs in
`Telegraph/Telegraph/Resources/`.

---

## 1. Where the tab bar lives

The original does **not** use `UITabBar`. `TGMainTabsController` is a `UITabBarController`
subclass that hides the real bar and overlays its own plain `UIView`:

```
_customTabBar = [[TGTabBar alloc] initWithFrame:
    CGRectMake(0, self.view.frame.size.height - 49, self.view.frame.size.width, 49)];
_customTabBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
[self.view insertSubview:_customTabBar aboveSubview:self.tabBar];
self.tabBar.hidden = true;
```
(MTC:359–366)

Consequences that ripple through everything else:

- Height is **49**, hardcoded in three places: the initial frame (MTC:359) and the indicator frame
  in both `setSelectedIndex:` (MTC:132) and `layoutSubviews` (MTC:234). It is never read from
  `self.bounds.size.height`.
- The real `UITabBar` still exists (hidden) purely so `UITabBarController` keeps working as a
  container; `tabBarItem.badgeValue` is still set on the dialog list controller
  (`TGTelegraphDialogListCompanion.mm:954`) even though nobody can see it. Dead weight kept for the
  app-icon/badge plumbing symmetry.
- **Composition**: the tab controller is the *root of a navigation controller*, not the other way
  round — `[TGNavigationController navigationControllerWithRootController:_mainTabsController]`
  (`TGAppDelegate.mm:302`). There is exactly one navigation bar in the app, owned by the tab
  controller, and `TGMainTabsController` retitles it on every tab switch
  (`updateTitleForController:switchingTabs:animateText:`, MTC:483). **Pushing anything pushes the
  whole tab controller away**, so the tab bar never has to hide itself, never has to animate out,
  and `hidesBottomBarWhenPushed` is never used. This single architectural decision removes an entire
  class of problems — see §8, defect D2.
- Order and default: `contacts, dialogList, myAccount(profile)` with `selectedIndex = 1`
  (`TGAppDelegate.mm:297–299`). Messages is the middle tab and the launch tab.

---

## 2. The three PNGs

Only `@2x` variants ship (`Telegraph/Telegraph/Resources/`); there is no 1x art for the bar itself,
which is consistent with the app's iPhone 4/4S-and-later target for this screen.

### TabBarBackground.png — 6×98 px = **3×49 pt**

A pure vertical gradient, uniform across its 3 pt width, with a **constant alpha of 235/255
(0.922)** on every pixel. That alpha is the whole translucency effect; there is no blur, no
`UIVisualEffectView` (iOS 6 has neither), just a 92 %-opaque dark gradient with live content
scrolling behind it.

Sampled down the centre column (px row → RGB, alpha 235 throughout):

| px row (y) | pt | RGB |
|---|---|---|
| 0 | 0.0 | `#1F1F1F` (31,31,31) — a single darker top pixel, the bar's hairline top edge |
| 2 | 1.0 | `#272727` (39,39,39) — brightest point of the gradient |
| 48 | 24.0 | `#1A1A1A` (26,26,26) |
| 97 | 48.5 | `#0C0C0C` (12,12,12) |

The ramp between rows 2 and 97 is smooth and linear-ish (one unit of grey lost roughly every 3 px).
Columns 0 and 5 are one unit darker (30 vs 31) than the interior — a 1 px antialias edge on the
source, not a design element.

It is applied **unstretched**: `initWithImage:` then `frame = self.bounds` (MTC:52–54, and again in
`layoutSubviews` MTC:220). A 3 pt-wide image scaled to 320 pt means the two 1 px edge columns get
smeared across ~53 pt each. Invisible at these greys, but it is a real artifact, and `twelve` later
fixed it deliberately (§7).

### TabBarSelected.png — 6×98 px = **3×49 pt**

This is the surprise. Sampled across a row:

```
x:  0        1        2          3          4        5
    a=0      a=0      #FFF a=13  #FFF a=13  a=0      a=0
```

Identical for **every one of the 98 rows**. So the selected-tab indicator is nothing but **white at
alpha 13/255 ≈ 5.1 %**, occupying the middle 1 pt of a 3 pt image, with a fully transparent 1 pt
column on each side. There is no glow, no gradient, no inner shadow. The visible "selected tab"
effect on screen is: a 5 % white wash over the full 49 pt height of that tab's column, plus the
highlighted icon and white label.

It is turned into a stretchable image:

```
[rawSelectedImage stretchableImageWithLeftCapWidth:(int)(rawSelectedImage.size.width / 2) topCapHeight:0]
```
(MTC:57) → `leftCapWidth = (int)(3/2) = 1`. Under the pre-iOS-5 stretch model that means: 1 pt left
cap (transparent), 1 pt tiled middle (the 5 % white), 1 pt right cap (transparent). **The two
transparent caps are the point of the asset** — they are the 1 pt gutters that separate the wash
from the neighbouring tabs, and they are also why the indicator has to be pushed off-screen at the
outer tabs (§3).

`topCapHeight:0` is harmless here because the image is vertically uniform.

### TabBarBadge.png — 40×40 px = **20×20 pt**

A rounded pill with a white ring, a red vertical gradient fill, and a soft drop shadow below it.
Vertically (centre column, px rows):

| px rows | pt | content |
|---|---|---|
| 0 | 0.0 | antialiased top of the white ring |
| 1–3 | 0.5–1.5 | white ring, opaque |
| 4 | 2.0 | fill starts: `#F66859` (246,104,89) |
| 31 | 15.5 | fill ends: `#D11A0A` (209,26,10) |
| 33–35 | 16.5–17.5 | white ring, bottom |
| 36–39 | 18.0–19.5 | drop shadow, black, peak alpha 120/255 at row 36, fading to 14 |

So the *visible pill* is 18 pt tall inside a 20 pt-tall asset; the bottom 2 pt are shadow only. The
white ring is ~2 px = 1 pt. Horizontally the pill is a symmetric round-rect with ~5 pt corner radii,
stretched with `stretchableImageWithLeftCapWidth:10 topCapHeight:0` (MTC:164) — 10 pt left cap, 1 pt
tiled column, 9 pt right cap.

### The icons

| asset | px | pt |
|---|---|---|
| `TabIconContacts` / `_Highlighted` | 62×58 | 31×29 |
| `TabIconMessages` / `_Highlighted` | 66×58 | 33×29 |
| `TabIconSettings` / `_Highlighted` | 56×56 | 28×28 |

Loaded as `initWithImage:highlightedImage:` pairs (MTC:62–72), so selection is a plain
`highlighted = YES` on the image view — there is no tinting code anywhere. Note the icons are
**different heights** (29, 29, 28) but are all top-aligned at y = 4 (§4), so their baselines do not
line up. That is what the original does; it is not visible because the artwork itself is padded.

---

## 3. The selected indicator: the stretch arithmetic

The same eight lines appear verbatim twice, in `setSelectedIndex:` (MTC:119–132) and in
`layoutSubviews` (MTC:222–234):

```objc
float indicatorWidth = floorf(viewSize.width / 3);
if (((int)indicatorWidth) % 2 != 0)
    indicatorWidth -= 1;

float paddingLeft = floorf((viewSize.width - indicatorWidth * 3) / 2);

float additionalWidth = 0;
float additionalOffset = 0;
if (_selectedIndex == 0 || _selectedIndex == 2)
    additionalWidth += paddingLeft + 1;
if (_selectedIndex == 0)
    additionalOffset += -paddingLeft - 1;

_selectedView.frame = CGRectMake(paddingLeft + indicatorWidth * _selectedIndex + additionalOffset,
                                 0, indicatorWidth + additionalWidth, 49);
```

**Why the parity clamp.** `floorf(width/3)` can be odd; forcing it even guarantees
`width - 3*indicatorWidth` is even whenever `width` is even, so `paddingLeft` is an exact integer and
the left and right gutters are symmetric. Without it you get a half-point asymmetry that shows up as
a 1 px seam on retina.

**Why the additional width/offset.** The indicator asset has a transparent 1 pt cap on each side. For
the middle tab those caps read as intentional gutters between the wash and its neighbours. For the
outer tabs they would read as a 1 pt light-grey seam between the wash and the screen edge. So the
outer tabs are **grown by `paddingLeft + 1` and, for tab 0, shifted left by the same amount** — the
indicator bleeds its transparent cap off the edge of the screen and the wash runs flush to the
bezel.

Worked out for the 320 pt portrait case (`indicatorWidth = 106`, `paddingLeft = 1`):

| selected | frame x | width | covered span |
|---|---|---|---|
| 0 (Contacts) | −1 | 108 | −1 … 107 (left cap off-screen) |
| 1 (Messages) | 107 | 106 | 107 … 213 (1 pt gutter both sides) |
| 2 (Settings) | 213 | 108 | 213 … 321 (right cap off-screen) |

480 pt landscape (`indicatorWidth = 160`, `paddingLeft = 0`): tab 0 → x = −1, w = 161; tab 1 →
x = 160, w = 160; tab 2 → x = 320, w = 161. The formula degrades correctly when the padding is zero
because of the `+ 1`.

**No animation.** The frame is assigned directly, never inside a `UIView` animation block. The wash
teleports to the new tab on touch-down.

---

## 4. Static layout (`layoutSubviews`, MTC:214–264)

Everything is absolute; nothing is centred against the bar's height.

- Background: `(0, 0, width, height)`.
- Icon *i*: `x = paddingLeft + i*indicatorWidth + floor((indicatorWidth - iconWidth)/2)`,
  **`y = 4`**, native size. Top-aligned, not centred.
- Label *i*: same horizontal centring formula against the label's `sizeToFit` width,
  **`y = 35`**, `sizeToFit` size.
- Badge container (only under icon index 1): `x = iconFrame.maxX - 9`, `y = 2` (MTC:250–253).

The label block, all three identical (MTC:76–104):

```objc
label.backgroundColor      = [UIColor clearColor];
label.textColor            = UIColorRGB(0x999999);
label.highlightedTextColor = [UIColor whiteColor];
label.font                 = [UIFont boldSystemFontOfSize:10];
label.text                 = TGLocalized(@"Contacts.TabTitle" / @"DialogList.TabTitle" / @"Settings.TabTitle");
[label sizeToFit];
```

English strings (`en.lproj/Localizable.strings:248, 220, 533`): **"Contacts", "Messages",
"Settings"**. Note the middle tab is *Messages*, not *Chats* — that rename came later.

Bold system 10 (Helvetica Bold on iOS 6) has a ~12 pt `sizeToFit` height, so a label at y = 35 ends
at ~47, leaving 2 pt to the bottom of the bar. The 4 / 35 pair is what the whole vertical rhythm is:
4 pt above a 28–29 pt icon → icon bottom at 32–33 → 2–3 pt gap → 12 pt of label → 2 pt bottom margin.

**Long labels.** There is no truncation, no minimum font scale, no per-tab width clamp. `sizeToFit`
gives the label its natural width and the centring formula centres it within `indicatorWidth`
(106 pt). A localisation whose word exceeds 106 pt simply overlaps the neighbouring tab's label. The
original accepted that; the three shipped English words are 40–55 pt wide, so there was plenty of
headroom.

Note also that labels are laid out **but never re-`sizeToFit`ed** after init, so the layout pass
reuses the width measured at construction time. Fine, because the text never changes.

---

## 5. The unread badge

### Lazy construction (`loadUnreadBadgeView`, MTC:153–176)

Created on first non-zero count and never destroyed:

```objc
_unreadBadgeContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
_unreadBadgeContainer.hidden = true;
_unreadBadgeContainer.userInteractionEnabled = false;
_unreadBadgeContainer.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;

_unreadBadgeBackground = [[UIImageView alloc] initWithImage:
    [[UIImage imageNamed:@"TabBarBadge.png"] stretchableImageWithLeftCapWidth:10 topCapHeight:0]];

float retinaPixel = TGIsRetina() ? 0.5f : 0.0f;
_unreadBadgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(9, 4 + retinaPixel, 28 + retinaPixel, 10)];
_unreadBadgeLabel.textColor = [UIColor whiteColor];
_unreadBadgeLabel.font = [UIFont boldSystemFontOfSize:11];
```

`setUnreadCount:` returns immediately when the count is ≤ 0 *and* the badge has never been built
(MTC:180–181), so an account with no unread messages never allocates the views at all.

### The right-anchored growth trick

The container is a fixed 20×20 box. The *background* inside it is right-aligned and grows leftwards
out of the container's bounds:

```objc
frame.size.width = MAX(20, textWidth + 12 + retinaPixel * 2);
frame.origin.x   = superview.frame.size.width - frame.size.width;   // = 20 - width, i.e. negative
```
(MTC:204–205). The container does not clip (`clipsToBounds` is left at `NO`), so the overflow draws.
The label follows at `x = 6 + 0.5 + backgroundFrame.origin.x` (MTC:209) — i.e. 6.5 pt inside the
pill's left edge, matching the 6.5 pt implied on the right by the `+12 + 1` padding formula.

Net effect: **the badge's right edge is pinned at `iconRight + 11` and the pill grows to the left
over the icon**, which is exactly what you want above a centred icon. The `FlexibleLeftMargin`
autoresizing mask keeps that right edge fixed when the bar's width changes on rotation before the
next `layoutSubviews`.

### Text and the 28.5 pt measuring cap

```objc
if (unreadCount < 1000)          text = @"%d";
else if (unreadCount < 1000000)  text = @"%dK", count/1000;
else                             text = @"%dM", count/1000000;
```
(MTC:190–195)

The measurement is `sizeWithFont:constrainedToSize:_unreadBadgeLabel.bounds.size` — **constrained to
the label's fixed 28.5×10 box** (MTC:203). The label frame's width is never updated, only its origin.
So the abbreviation is not cosmetic: it is what keeps the longest possible string ("999", "999K",
"999M" — four bold-11 glyphs, ≈25 pt) inside the 28.5 pt measuring window. Feed it a raw five-digit
number and the measurement saturates at 28.5, the pill stops growing at ~41 pt, and the label
truncates with an ellipsis. Nothing guards against this except the K/M rule itself.

Minimum pill width is **20 pt** (`MAX(20, …)`), so a single digit sits in a circle.

Vertical: label y = 4.5, height 10, font 11 → the 13 pt line box overflows a 10 pt label, but
`clipsToBounds` is off, so it draws. Against the pill's 18 pt visible height (2 pt of which is the
white ring at each end) the digits land optically centred.

### Feed

Server-driven, from the global unread counter, not from summing chats:
`TGTelegraphDialogListCompanion.mm:946–955` handles `/tg/unreadCount` and calls
`[TGAppDelegateInstance.mainTabsController setUnreadCount:]` on the main queue, alongside
`setApplicationIconBadgeNumber:`. Muted-chat policy is therefore whatever the server counter says.

---

## 6. Touch model, and the swizzle that makes it all translucent

### Touch (MTC:141–151)

```objc
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    int index = MAX(0, MIN((int)_buttonViews.count - 1,
                    (int)([touch locationInView:self].x / (self.frame.size.width / 3))));
    [self setSelectedIndex:index];
    [delegate tabBarSelectedItem:index];
}
```

There is no `touchesEnded:`, no `touchesCancelled:`, no `UIControl`, no gesture recogniser.
Selection commits on **touch-down**; you cannot slide off to cancel. `multipleTouchEnabled = NO` and
`exclusiveTouch = YES` are set in `init` (MTC:49–50) to stop a second finger from switching tabs
mid-gesture.

Division uses `self.frame.size.width / 3`, **not** `indicatorWidth`, so the hit regions are the exact
thirds (106.67 pt) while the indicator is 106 pt — they disagree by up to 2 pt at the boundaries.
Nobody notices, but it is an inconsistency the code contains rather than resolves.

Re-tapping the already-selected tab scrolls that controller to top:

```objc
if ([self.selectedViewController respondsToSelector:@selector(scrollToTopRequested)])
    [self.selectedViewController performSelector:@selector(scrollToTopRequested)];
```
(MTC:431–434)

### The swizzle

A 92 %-opaque bar is only worth having if content passes under it. On iOS 6 `UITabBarController`
sizes its child's view to `height − 49`, so by default there is nothing behind the bar but the
window. The original defeats that by swizzling `UILayoutContainerView`'s `layoutSubviews`:

1. `TGHacks.hackSetAnimationDuration` (called from `TGAppDelegate.mm:274`) swaps
   `-[UILayoutContainerView layoutSubviews]` with `-[TGLayoutContainerView layoutSubviewsTG]`
   (HACKS:400–408). Class names are obfuscated by a Caesar shift, `TGEncodeText(@"VJMbzpvuDpoubjofsWjfx", -1)`
   → `UILayoutContainerView`, purely as App Store review camouflage.
2. `layoutSubviewsTG` looks for an associated object on the view; if none, it calls straight through
   to the saved UIKit implementation, so every other tab/split controller in the app is untouched
   (HACKS:306–330, the `TGFullscreenContainerClass` macro).
3. `TGMainTabsController.loadView` attaches a `TGTabsContainerViewDelegate` to its container
   (MTC:351–352) whose `layoutSubviews:` sets the contained `UITransitionView.frame = view.bounds`
   (MTC:287–297). Child content is now **full-height**, running behind the bar.
4. To compensate, `TGViewController` adds the bar's height back as a scroll inset:
   ```objc
   if ([self.parentViewController isKindOfClass:[UITabBarController class]])
       edgeInset.bottom += 49;
   ```
   (TGVC:729–730), inside `_updateControllerInsetForOrientation:…`, which also folds in the status
   bar, the navigation bar (44 portrait / 32 landscape, TGVC:720) and the keyboard via
   `edgeInset.bottom = MAX(edgeInset.bottom, keyboardHeight)` (TGVC:733). The inset is therefore
   **recomputed on rotation and on every keyboard event**, not set once.

That four-part mechanism is the pre-iOS-7 equivalent of `UITabBar.translucent` + automatic
`contentInset` adjustment. It is worth naming as a unit, because breaking any one part gives a
different bug: skip (1)–(3) and the bar sits on an opaque background; skip (4) and the last row of
every list is unreachable under the bar.

**Contradiction, documented honestly:** MTC:352 installs a second layout delegate on
`self.view.subviews[0]`, which on iOS 6 is a `UITransitionView`. But the `UITransitionView` entry in
the swizzle table is **commented out** (HACKS:402), so nothing ever reads that associated object.
Line 352 is dead code in the shipped build.

---

## 7. What the concept became

### `twelve` (`Telegram-iOS` ObjC lineage, `Telegraph/TGMainTabsController.m`)

`twelve` is the most useful comparison because it re-implements this exact bar as a *theme*
(`[TGPresentation classicIOS6Style]`) inside a modern component, and every place it diverges is a
place where the 2013 design could not survive a new requirement.

- **Structure inverted.** The monolithic `TGTabBar` became `TGTabBarButton` — one view per tab that
  owns its icon, its label and its own selection layer (twelve MTC:164–366). Consequence: the
  stretched single indicator is gone. Selection is a `CAGradientLayer` at index 0 of each button's
  layer, `contents = TabBarSelected` resized, `frame = self.bounds`, `contentsGravity = resize`
  (twelve MTC:228–241, 253–254). Because each button already spans its full column, the
  `additionalWidth` / `additionalOffset` edge-bleed dance disappears entirely — and so do the 1 pt
  gutters between tabs, which is a real (if tiny) visual loss.
- **The background stretch was fixed.** `TGMainTabsClassicIOS6ResizableImage` applies
  `resizableImageWithCapInsets:UIEdgeInsetsMake(0,1,0,1)` (twelve MTC:32–36) so the 1 px antialias
  columns of `TabBarBackground` stay 1 px instead of being smeared over 53 pt.
- **Translucency abandoned.** `self.opaque = true; backgroundColor = UIColorRGB(0x242424)` under the
  image (twelve MTC:412–421), plus a `_classicIOS6BottomSeamView` of the same colour along the last
  screen pixel. The 0.922 alpha is still in the PNG but there is now an opaque plate behind it, so
  nothing shows through. Cost of living on a modern layout stack with safe-area insets — and a
  reminder that the translucency in the original is *only* legible because of the swizzle.
- **A fourth tab.** Calls arrives, hidden by default, with `buttonsCount = _callsHidden ? 3 : 4` and
  an index remap so the delegate still speaks in fixed slot numbers
  (`if (buttonsCount == 3 && index > 0) index += 1;`, twelve MTC:594–596). Under
  `classicIOS6Style` the Calls tab is force-hidden with an explicit comment that the classic layout
  has three tabs (twelve MTC:502–506). This is exactly our extension problem, and the answer they
  reached was: keep the slot indices stable, hide rather than remove.
- **Touch model upgraded.** Two `UILongPressGestureRecognizer`s replace `touchesBegan:` — one with
  `minimumPressDuration = 0.0` for the tap and one at 0.25 s on the chats button for the long-press
  menu, chained with `requireGestureRecognizerToFail:` (twelve MTC:459–471). Same touch-down commit
  semantics, but now cancellable via `allowableMovement = 1.0` and composable with a long press.
- **Badge extracted** into a `TGTabBarBadge` view added as a subview of its *button* rather than the
  bar (twelve MTC:46–162, 637–664), and the classic branch reproduces the 2013 numbers exactly:
  `MAX(20, textWidth + 12 + retinaPixel*2)`, label at `x = frame.origin.x + 6 + retinaPixel`,
  `y = 4 + retinaPixel`, cap inset 10, bold 11, white. The modern branch instead uses a fixed
  20 pt-tall pill, `textWidth + 10`, centred text, system 13. It also learns to *split* counts:
  `[_messagesBadge setCount:MAX(0, _messagesCount - _callsCount)]` (twelve MTC:707).
- **Label offset nudged:** y = `35 - TGScreenPixel` on phone, 36 on iPad (twelve MTC:325–336);
  icon y = 4 on phone, `5 + TGRetinaPixel` on iPad (twelve MTC:310–321). Landscape gets a
  side-by-side icon+label arrangement with the icon scaled to 0.6667 (twelve MTC:274–288) — the 2013
  bar had no landscape variant at all.

### Modern `Telegram-iOS` (`submodules/TabBarUI/Sources/TabBarNode.swift`)

Nothing of the artwork survived.

- **No selection indicator whatsoever.** Selection is a colour swap on a pre-rendered image
  (`tabBarItemImage`, TabBarNode.swift:19–86), which composites icon + title into a single bitmap of
  fixed height 45 (vertical) or 34 (horizontal). The 2013 idea — "mark the selected *column*" — was
  replaced by "tint the selected *item*", which is what iOS 7 standardised.
- **Badge is drawn, not stretched:** height fixed at 18, width
  `hasSingleLetterValue ? 18 : max(18, textWidth + 10 + 1)`, text centred, regular 13
  (TabBarNode.swift:89, 756–774). Compare 2013: 20 pt tall art with a 2 pt shadow, width
  `max(20, textWidth + 12 + 1)`, text left-aligned at a hand-tuned 6.5 pt inset, bold 11. Same
  formula shape, one point tighter, and every pixel now themeable.
- Translucency is a real material again, so no swizzle; layout is inset-driven through
  `ContainerViewLayout`, so no `edgeInset.bottom += 49`.

The honest summary of thirteen years: the *layout constants* (49 pt bar, icon at 4, label at 35,
badge ≈ 20×18 anchored right of the icon and growing left) proved durable and are still recognisable
in `twelve`. The *mechanisms* — stretchable PNGs, a single stretched indicator, a swizzled container
to fake translucency, one shared navigation bar retitled per tab — all died, each replaced by an OS
feature that did not exist in 2013.

---

## 8. Our port, judged

Files: `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGTabBar.m`, `TGTabBar.h`,
`RootViewController.m`, `TGHacks.m`, `TGTabsContainerViewDelegate.m`, and `images/TabBar*.png`,
`images/TabIcon*.png`.

**What is right — and it is most of it.**

- All eight tab assets are **byte-identical** to the originals (verified by md5 against
  `Telegraph/Telegraph/Resources/`): `TabBarBackground@2x`, `TabBarSelected@2x`, `TabBarBadge@2x`,
  and the three icon pairs. Our added 1x downscales are unused on a 4S (scale 2) and harmless.
- `TGTabBar.m:89–103` reproduces the indicator arithmetic exactly, including the parity clamp and the
  edge-bleed, generalised from a hardcoded `3` to `buttonViews.count` — the generalisation is
  correct for the three-tab case and stays correct for four (`_selectedIndex == count - 1`).
- Badge geometry (`TGTabBar.m:155–219`) is a faithful transcription: 20×20 container,
  `FlexibleLeftMargin`, cap inset 10, label `(9, 4.5, 28.5, 10)` bold 11 white, width
  `MAX(20, textWidth + 12 + 1)`, right-anchored growth, `x = 6.5 + bg.origin.x`, and the K/M
  abbreviation with the same thresholds.
- Layout constants (`TGTabBar.m:244, 250, 257`): icon y = 4, badge container y = 2 at
  `iconRight − 9`, label y = 35. Label styling `#999999` / white / bold 10 matches MTC:78–80. The
  hardcoded English strings match `en.lproj/Localizable.strings` exactly ("Contacts", "Messages",
  "Settings").
- `TGHacks.m:6–66` and `TGTabsContainerViewDelegate.m` reproduce the swizzle correctly, including
  the pass-through fallback, and `hackSetAnimationDuration` is called from `AppDelegate.m:45` as in
  `TGAppDelegate.mm:274`. Dropping the `TGEncodeText` obfuscation is right for a sideloaded build.
  Also correct: we install the layout delegate on `self.view` only (`RootViewController.m:25`) and
  omit MTC:352 — that second call is dead code in the original (§6), so this is not a defect.
- `TGTabBar.m:114–115` clamps `selectedIndex` into range, which the original did not
  (MTC:117 assigns unconditionally). A safe improvement; keep it.

**Defects.**

**D1 — Re-tapping the selected tab does nothing; it must scroll to top.**
`RootViewController.m:89–92`:
```objc
- (void)tabBarSelectedItem:(int)index {
    if ((int)self.selectedIndex != index)
        [self setSelectedIndex:index];
}
```
The original's `else` branch is missing (MTC:430–434): on a re-tap it sends `scrollToTopRequested` to
the selected view controller. Fix: add the `else` branch, and implement `scrollToTopRequested` on
`TGChatListViewController` / `TGContactsViewController` / `TGSettingsViewController` as
`[self.tableView setContentOffset:CGPointMake(0, -contentInset.top) animated:YES]`. This is a
behaviour every Telegram user reaches for and it is currently dead.

**D2 — The tab bar snaps out of existence on push, and any tab's push hides it.**
`RootViewController.m:84–87`:
```objc
- (void)navigationController:… willShowViewController:… animated:… {
    self.customTabBar.hidden = viewController != navigationController.viewControllers.firstObject;
}
```
Two problems, both caused by our inverted composition (per-tab `UINavigationController`s inside the
tab controller, `RootViewController.m:31–43`) versus the original's single navigation controller with
the tab controller as its root (`TGAppDelegate.mm:302`):
  1. *No guard on which navigation controller.* All three are assigned `nc.delegate = self`
     (`RootViewController.m:54–55`), so a push inside a **background** tab hides the bar over the
     **foreground** tab. Fix: `if (navigationController != self.selectedViewController) return;`
  2. *No animation.* `hidden` flips instantly at the start of the slide, so the bar pops rather than
     travelling with the outgoing view as it did in 2013 (where the whole tab controller, bar
     included, was pushed off-screen). Fix: animate `alpha`/`transform` alongside the push over the
     same duration, or restructure to the original's composition. The composition change itself is a
     deliberate, defensible modernisation — the pop is not.

**D3 — The 49 pt bottom inset is applied once, only to `UITableViewController` roots, and ignores
the keyboard.** `RootViewController.m:60–76` (`applyTabBarInsetForIndex:`) guards with an
`insetTabs` index set, bails unless the nav root is a `UITableViewController`, and writes
`contentInset.bottom = 49` a single time. The original computed it every time anything moved, inside
`TGViewController._updateControllerInsetForOrientation:statusBarHeight:keyboardHeight:force:notify:`
(TGVC:727–734), where it is combined with the status bar, the navigation bar and
`edgeInset.bottom = MAX(edgeInset.bottom, keyboardHeight)`. Ours therefore breaks the moment a tab
root is not a table view controller (nothing gets the inset, last row unreachable under the bar), or
the moment a controller reassigns its own `contentInset` after our one-shot write. Fix: recompute on
`viewWillLayoutSubviews` / rotation / keyboard notifications rather than guarding with `insetTabs`,
and drop the `UITableViewController` type test in favour of "any `UIScrollView` the child exposes".

**D4 — Badge source differs from the original's semantics.** `RootViewController.m:108–124` sums
`unread` over `TGClient.chats` + `archivedChats`, **skipping muted chats**. The original took the
server's single `/tg/unreadCount` value (`TGTelegraphDialogListCompanion.mm:946–955`). Ours will
under-count relative to 2013 behaviour and will silently miss any chat not currently in the local
list. Not a rendering defect and arguably matches modern Telegram's default, but it should be a
conscious choice, not an accident — if we want the original's number, take TDLib's
`unreadMessageCount` for the main chat list instead of summing.

**Non-defects worth not "fixing".** The label `accessibilityTraits`/`accessibilityValue` additions
(`TGTabBar.m:55–57, 68–81`) have no 2013 counterpart but cost nothing visually: the labels have
`userInteractionEnabled = NO`, so a VoiceOver activation still lands in the bar's `touchesBegan:`.
The extra `[self setNeedsLayout]` in `setSelectedIndex:` (`TGTabBar.m:124`) and clearing
`unreadBadgeLabel.text` when the count hits zero (`TGTabBar.m:190`) are both harmless.

---

## 9. Quick reference

| thing | value | citation |
|---|---|---|
| bar height | 49 pt, hardcoded | MTC:359, 132, 234 |
| bar background | 3×49 pt gradient `#272727` → `#0C0C0C`, alpha 0.922 throughout | `TabBarBackground@2x.png` |
| bar background scaling | stretched from 3 pt to full width, not resizable-image | MTC:52–54, 220 |
| selected indicator | white α 0.051, 3 pt image, `leftCapWidth = 1` | `TabBarSelected@2x.png`, MTC:57 |
| indicator width | `floorf(w/3)`, minus 1 if odd | MTC:119–121 |
| gutter | `paddingLeft = floorf((w − 3·iw)/2)`; 1 pt at 320 | MTC:123 |
| outer-tab bleed | width `+ paddingLeft + 1`; tab 0 also offset `−(paddingLeft + 1)` | MTC:127–130 |
| indicator animation | none | MTC:132 |
| icon y | 4 | MTC:243 |
| icon sizes | contacts 31×29, messages 33×29, settings 28×28 pt | assets |
| icon selection | `highlighted = YES` on `initWithImage:highlightedImage:` pair | MTC:62–72, 136 |
| label font/colour | bold system 10, `#999999`, white when selected | MTC:78–80 |
| label y | 35 | MTC:261 |
| label text | "Contacts" / "Messages" / "Settings" | `en.lproj/Localizable.strings:248, 220, 533` |
| badge art | 20×20 pt; 18 pt pill (`#F66859`→`#D11A0A`, 1 pt white ring) + 2 pt shadow | `TabBarBadge@2x.png` |
| badge cap inset | `leftCapWidth = 10` | MTC:164 |
| badge container | 20×20 at `(iconRight − 9, 2)`, `FlexibleLeftMargin`, non-interactive | MTC:158–161, 250–253 |
| badge width | `MAX(20, textWidth + 12 + 1)`, right-anchored, grows left | MTC:204–205 |
| badge label | `(9, 4.5, 28.5, 10)` bold 11 white; x becomes `6.5 + bg.x` | MTC:169, 209 |
| badge text | `%d` / `%dK` / `%dM` at 1 000 / 1 000 000 | MTC:190–195 |
| badge measuring cap | 28.5 pt (label bounds) — the reason K/M exists | MTC:203 |
| badge lifecycle | lazily built on first non-zero count, then only hidden | MTC:180–186 |
| hit testing | thirds of `frame.width`, clamped; commits on touch-down | MTC:146–147 |
| re-tap | `scrollToTopRequested` on the selected controller | MTC:431–434 |
| translucency | 0.922 PNG alpha + `UILayoutContainerView.layoutSubviews` swizzle + `edgeInset.bottom += 49` | HACKS:400–408, MTC:287–297, TGVC:729–730 |
| default tab | 1 (Messages) | `TGAppDelegate.mm:299` |

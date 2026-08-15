# TGMainTabsController — the 2013 root tab controller

Source of truth for everything below:

- `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGMainTabsController.h` (21 lines)
- `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGMainTabsController.m` (613 lines)

The file contains **three** classes, only one of which is named in the header:

| Class | Lines | Role |
| --- | --- | --- |
| `TGTabBar` (private `UIView`) | `.m:24–266` | the entire visible tab bar; UIKit's `UITabBar` is hidden and never drawn |
| `TGTabsContainerViewDelegate` | `.m:270–322` | a layout hack that forces the child transition view to fill the container |
| `TGMainTabsController : UITabBarController` | `.m:326–613` | the controller: owns the fake tab bar, and owns **the navigation item of the whole app** |

---

## 1. What it is for

The app has exactly one `UINavigationController` for the whole main UI, and
`TGMainTabsController` is its root view controller (`TGAppDelegate.mm:297–303`):

```
_mainTabsController = [[TGMainTabsController alloc] init];
[_mainTabsController setViewControllers:@[_contactsController, _dialogListController, _myAccountController]];
[_mainTabsController setSelectedIndex:1];
_mainNavigationController = [TGNavigationController navigationControllerWithRootController:_mainTabsController];
```

Three tabs, fixed order: **Contacts (0), Messages (1), Settings (2)**, and the app
launches on Messages (`TGAppDelegate.mm:299`). The Settings tab is not a settings
list — it is `TGProfileController` with `uid:0`, i.e. your own profile
(`TGAppDelegate.mm:293`).

This is the structural decision the whole design rests on: **the tabs live *inside*
one navigation stack, not the other way round.** There is exactly one navigation
bar in the app. When you open a chat, the chat is pushed onto that same outer
navigation controller, so the tab bar slides off-screen together with the tab
controller's own view as part of the standard push animation. There is no
"hide the tab bar" code anywhere, because nothing ever needs hiding.

The price of that decision is that the tab controller must impersonate whichever
child is on screen: it proxies the child's title, left button, right button and
"should the bar be hidden" up into its own `navigationItem`. That is what
`TGTabControllerChild` (`Telegraph/Telegraph/TGTabControllerChild.h:11–21`) exists for:

```
- (NSString *)controllerTitle;
- (UIView *)controllerTitleView:(float)titleWidth;
- (UIBarButtonItem *)controllerLeftBarButtonItem;
- (UIBarButtonItem *)controllerRightBarButtonItem;
- (bool)navigationBarShouldBeHidden;
```

All five are `@optional`; a child that implements none of them gets a blank bar.

## 2. Public surface

```objc
@interface TGMainTabsController : UITabBarController <TGViewControllerNavigationBarAppearance>
- (void)setUnreadCount:(int)unreadCount;                                    // .h:15
- (void)updateTitleForController:(UIViewController *)controller
                   switchingTabs:(bool)switchingTabs
                     animateText:(bool)animateText;                         // .h:17
- (void)updateLeftBarButtonForCurrentController:(bool)animated;             // .h:18
- (void)updateRightBarButtonForCurrentController:(bool)animated;            // .h:19
@end
```

Real call sites of the three `update…` methods, all from `TGContactsController.mm`
(lines 2243–2280): when the contacts list enters/leaves edit mode it reaches up
through `self.parentViewController`, checks `isKindOfClass:[TGMainTabsController class]`,
and asks the tab controller to re-pull its bar buttons. So the child never touches
`self.navigationItem`; it mutates its own state and then pokes the parent.
`setUnreadCount:` has exactly one caller,
`TGTelegraphDialogListCompanion.mm:951`, driven off the `/tg/unreadCount` graph path.

---

## 3. `TGTabBar` — geometry

Height is **49** points, hardcoded in three places (`.m:132`, `.m:234`, `.m:359`).
Frame at creation: `CGRectMake(0, view.height - 49, view.width, 49)` with
`FlexibleWidth | FlexibleTopMargin` (`.m:359–360`). It is inserted *above*
`self.tabBar`, and `self.tabBar.hidden = true` (`.m:362, 366`). The real
`UITabBar` still exists and still reserves its 49 points of layout — the fake one
is drawn on top of the hole it leaves.

### Column maths (`.m:119–132`, repeated verbatim in `layoutSubviews` `.m:222–234`)

```
indicatorWidth = floorf(width / 3);
if ((int)indicatorWidth % 2 != 0) indicatorWidth -= 1;   // force even
paddingLeft    = floorf((width - indicatorWidth * 3) / 2);
```

On a 320-point screen: `floor(320/3) = 106`, which is even, so `indicatorWidth = 106`,
`paddingLeft = floor((320 - 318)/2) = 1`. On a 480-point landscape width:
`floor(480/3) = 160`, even, `paddingLeft = 0`.

The even-width rule exists so that a centred icon of even pixel width lands on a
whole point: `floorf((indicatorWidth - iconWidth) / 2)` with both even can never
produce a half-point origin, so nothing blurs on the 4S's 2× screen.

The 1 point of `paddingLeft` on a 320-wide screen is real dead space at the far
left and far right. The selection indicator explicitly reclaims it at the two
outer tabs (`.m:127–132`):

```
if (_selectedIndex == 0 || _selectedIndex == 2) additionalWidth  += paddingLeft + 1;
if (_selectedIndex == 0)                        additionalOffset += -paddingLeft - 1;
```

So on 320 points: selecting Contacts gives the highlight `x = 1 + 0 - 2 = -1`,
`width = 106 + 2 = 108`; selecting Settings gives `x = 1 + 212 = 213`,
`width = 108`, i.e. it runs to `x = 321`. Both outer highlights deliberately bleed
one point past the screen edge, so no sliver of unhighlighted background survives
in the corners. The middle tab is left at its exact 106 points.

### Icons and labels (`layoutSubviews`, `.m:236–263`)

- Icon: `origin.y = 4` (`.m:243`), horizontally centred in its column. The image
  view keeps its intrinsic size from `initWithImage:`.
- Label: `origin.y = 35` (`.m:261`), horizontally centred on the label's own
  `sizeToFit` width (`.m:82, 92, 102`), i.e. centred on the *text*, not on the icon.

Measured artwork sizes (all `@2x` only, no 1× exists in the original):

| Asset | Pixels | Points |
| --- | --- | --- |
| `TabIconContacts[_Highlighted]@2x.png` | 62×58 | 31×29 |
| `TabIconMessages[_Highlighted]@2x.png` | 66×58 | 33×29 |
| `TabIconSettings[_Highlighted]@2x.png` | 56×56 | 28×28 |
| `TabBarBackground@2x.png` | 6×98 | 3×49 |
| `TabBarSelected@2x.png` | 6×98 | 3×49 |
| `TabBarBadge@2x.png` | 40×40 | 20×20 |

So the icon occupies y = 4…33 (Contacts/Messages) or 4…32 (Settings), and the
10-point bold label sits at y = 35 with its own fitted height (~12), ending around
y = 47. The 49-point bar is used essentially edge to edge with 4 points of top
padding and ~2 of bottom. **The three icons are not the same height**, and nothing
compensates: Settings is one point shorter and therefore sits one point higher off
the label than the other two. That asymmetry is in the original.

## 4. `TGTabBar` — colour and artwork

Nothing is drawn in code; everything is a stretched PNG.

- **Background** (`.m:52–54`): plain `UIImageView` with `TabBarBackground.png`,
  frame set to the bar's bounds. Because it is *not* made stretchable, the 3×49
  image is scale-to-fill'd across the full width — legitimate, since the image is
  a pure vertical gradient. Sampled from `TabBarBackground@2x.png`: a top-to-bottom
  ramp from `rgb(31,31,31)` at y=0, peaking at `rgb(39,39,39)` around y=2–4px, down
  to `rgb(12,12,12)` at the bottom, **alpha 235/255 (0.92) everywhere**. The bar is
  translucent by 8%, not opaque, and it has no light hairline on top — the top row
  is already dark (`rgb(30–31)`).
- **Selection** (`.m:56–57`): `TabBarSelected.png` made stretchable with
  `leftCapWidth = (int)(3 / 2) = 1`, `topCapHeight = 0`. Pixel content at 2×: columns
  0–1 fully transparent, columns 2–3 `white @ alpha 13/255 ≈ 5.1%`, columns 4–5
  transparent, uniform down the full 98px. So the highlight is a flat **5% white
  wash** with a **1-point transparent gutter on each side** — the caps are the
  transparent columns and only the white middle point is tiled. That is why the
  outer-tab bleed above is `paddingLeft + 1`: the extra `+1` pays for the gutter.
  There is no gradient, no border, no rounded corner: the whole selected column
  just lifts by 5% white.
- **Labels** (`.m:76–104`): `boldSystemFontOfSize:10`, normal colour
  `UIColorRGB(0x999999)`, `highlightedTextColor = white`, clear background. Text
  from `TGLocalized(@"Contacts.TabTitle")` / `DialogList.TabTitle` /
  `Settings.TabTitle`, which in `Telegraph/Telegraph/en.lproj/Localizable.strings:248, 220, 533`
  are `"Contacts"`, `"Messages"`, `"Settings"`.
- **Icons**: `initWithImage:highlightedImage:` pairs. Selection is expressed purely by
  toggling `.highlighted` on the image view and the label (`.m:113–114, 136–137`) —
  no tinting, no alpha. Two separate PNGs per tab.

## 5. The unread badge

Lazily created; `loadUnreadBadgeView` returns immediately if it already exists
(`.m:153–176`), and `setUnreadCount:` returns immediately when the count is ≤ 0 and
the badge has never been built (`.m:180–181`). So a user with no unread messages
never allocates the badge views at all.

Structure:

- `_unreadBadgeContainer`: `UIView`, frame `(0,0,20,20)`, `hidden = true`,
  `userInteractionEnabled = false` (`.m:158–160`). Positioned in `layoutSubviews`
  only against tab index **1** (Messages): `x = messagesIcon.x + messagesIcon.width - 9`,
  `y = 2` (`.m:246–255`). With a 33-point-wide icon that puts the container's left
  edge 24 points into the icon — the badge overlaps the icon's top-right corner and
  is allowed to overflow to the right by design (`clipsToBounds` is left at `false`).
- `_unreadBadgeBackground`: `TabBarBadge.png` stretched with `leftCapWidth = 10`,
  `topCapHeight = 0` (`.m:164`), natural size 20×20.
- `_unreadBadgeLabel`: frame `(9, 4 + retinaPixel, 28 + retinaPixel, 10)`,
  `boldSystemFontOfSize:11`, white, clear background (`.m:169–172`), where
  `retinaPixel = TGIsRetina() ? 0.5 : 0.0` (`.m:167`) — on the 4S it is 0.5.

Growth (`.m:202–210`):

```
textWidth        = [text sizeWithFont:… constrainedToSize:label.bounds.size …].width;
bg.width         = MAX(20, textWidth + 12 + retinaPixel * 2);   // 4S: +13
bg.origin.x      = 20 - bg.width;                                // right-aligned, grows left
label.origin.x   = 6 + retinaPixel + bg.origin.x;                // 4S: bg.x + 6.5
```

The badge is anchored by its **right** edge and expands leftwards over the icon.
Its minimum width is 20 points (a single digit sits in a circle); the height never
changes from the image's natural 20.

Number formatting (`.m:190–195`) — worth copying exactly, because it is unusual:

- `< 1000` → the number
- `< 1000000` → `"%dK"` with integer division (1999 unread renders as **"1K"**, not "2K" and not "999+")
- otherwise → `"%dM"`

There is no "99+" cap, unlike iOS's own badges. On the empty case
(`unreadCount <= 0` with a badge already built) the container is hidden but the
text is left untouched (`.m:185–186`), so the stale number is still there,
invisible, if the badge is shown again before `setUnreadCount:` writes a new one —
harmless because the next positive call always rewrites `text` first.

Badge artwork, sampled from `TabBarBadge@2x.png` (rows are 2× pixels, 40 tall):

- rows 1–2: pure white — a **1-point white top stroke**
- row 3: `rgb(253,233,231)`, the antialiasing into the fill
- rows 4–31: red vertical gradient, `rgb(249,104,88)` at the top down to
  `rgb(210,27,10)` at the bottom
- rows 33–35: pure white again — a **1-point white bottom stroke**
- rows 36–39: black at alpha 120 → 14 — a **2-point drop shadow below the capsule**

So of the 20 points of artwork only about 17.5 are the badge; the last 2 are
shadow. Since `y = 2` for the container, the visible capsule occupies roughly
y = 2.5…20 of the 49-point bar, and the shadow falls on the icon.

## 6. Interaction

**Selection happens on touch-down, not touch-up** (`.m:141–151`):

```
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    int index = MAX(0, MIN(2, (int)(location.x / (width / 3))));
    [self setSelectedIndex:index];
    [delegate tabBarSelectedItem:index];
}
```

Note that the hit test divides by `width / 3` — the *un-rounded* third — while the
visuals use the floored, forced-even `indicatorWidth`. On 320 points the hit
regions are 106.67 wide against 106-wide visuals offset by `paddingLeft = 1`, so
the boundaries disagree by up to ~1.7 points near the right edge. Nobody notices,
but a faithful port should reproduce the same formula rather than "fixing" it.
`multipleTouchEnabled = false`, `exclusiveTouch = true` (`.m:49–50`); there is no
`touchesCancelled` handling, so a touch that begins on a tab and drags away has
already switched the tab.

**Re-tapping the selected tab** (`.m:430–434`): the controller calls
`scrollToTopRequested` on the selected view controller if it responds. Note the
selector is only ever invoked from here, via `performSelector:`.

**Tab change plumbing** (`.m:413–442`): `tabBarSelectedItem:` calls
`tabBarController:shouldSelectViewController:` *by hand* (UIKit never fires it,
since the real tab bar is hidden), which is where `updateTitleForController:…switchingTabs:true`
runs — so **the navigation bar's title, buttons and hidden state are updated
before the content switches**, not after. `setSelectedIndex:` is overridden to
mirror the index into the custom bar (`.m:437–442`), which is what makes the
programmatic switches in `TGAppDelegate.mm:619, 1184, 1271` (open a chat from a
notification → force the Messages tab) light up the correct tab.

## 7. Title handling

`updateTitleForController:switchingTabs:animateText:` (`.m:483–594`) builds, once,
a `TGLabel` inside a 10×10 `_titleLabelContainer` used as `navigationItem.titleView`
(`.m:499–513, 562`):

- font `[TGViewController titleFontForStyle:… landscape:…]` = **bold system 20** in
  portrait (`TelegraphKit/TelegraphKit/TGViewController.mm:79–87`), with separate
  `portraitFont`/`landscapeFont` so `TGLabel` can swap on rotation
- colour white (`TGViewController.mm:133–140`), shadow `UIColorRGB(0x3d5c81)` with
  offset `(0, -1)` (`TGViewController.mm:151–158, 169–173`) — the classic 2013
  blue-bar letterpress, shadow *above* the glyph
- `verticalAlignment = TGLabelVericalAlignmentTop`, `clipsToBounds = false`

Sizing (`.m:546–554`): the label is reset to `(0,0,480,44)`, `sizeToFit`, then its
height is bumped by 2 (room for the shadow) and it is centred inside its
superview. Because the container is 10×10 and `clipsToBounds` is off, the centring
maths produces a negative origin and the text simply overhangs the container in
both directions — the container is a positioning anchor, not a clip. **Long titles
are therefore never truncated by this code**; the navigation bar's own layout
against the left/right bar button items is what constrains them.

A child may instead return a whole `controllerTitleView:` (given the full view
width), and then the label is bypassed entirely (`.m:526–527, 556–559`).

The `animateText` path (`.m:587–593`) adds a 0.1 s `CATransition` (default fade,
`kCAMediaTimingFunctionEaseIn`) to the label's layer — but the guard is
`![_titleLabel.text isEqualToString:title]` and `_titleLabel.text` was already
assigned the new title at line 546, so **the condition is always false and the
animation never runs**. This is a genuine bug in the original; do not port it as
if it were a feature.

`navigationBarShouldBeHidden` is read from the child and applied with
`animated:(!switchingTabs)` — i.e. switching tabs hides/shows the nav bar
*without* animation, while any other trigger animates (`.m:540–541, 583–584`).
The same block runs twice in the method (once inside the title branch, once again
at the end), which is redundant but harmless.

## 8. Other behaviours

- `requiredNavigationBarStyle` / `navigationBarShouldBeHidden` (`.m:384–402`)
  forward to the selected child if it conforms to
  `TGViewControllerNavigationBarAppearance`, else `UIBarStyleDefault` / `false`.
- Rotation: allowed except upside-down (`.m:374–377`), gated on
  `[TGViewController autorotationAllowed]`. On rotation the title label is
  re-fitted and re-centred (`.m:596–611`); nothing re-lays the tab bar because the
  autoresizing mask and `layoutSubviews` handle it.
- `viewWillAppear:` (`.m:404–411`) updates the title **before** calling `super` and
  forces a synchronous `layoutIfNeeded`, so the bar is correct on the frame the
  view first appears rather than one frame later.
- `TGTabsContainerViewDelegate` (`.m:270–322`): installed on both `self.view` and
  `self.view.subviews[0]` (`.m:351–352`) through
  `TGHacks setLayoutDelegateForContainerView:` (which merely stores it as an
  associated object, `TelegraphKit/TelegraphKit/TGHacks.m:707–710`; the swizzled
  `layoutSubviews` calls back into it). Class names are obfuscated with
  `TGEncodeText(@"VJMbzpvuDpoubjofsWjfx", -1)` = `UILayoutContainerView` and
  `VJUsbotjujpoWjfx` = `UITransitionView` (`.m:283–284`) — a Caesar shift of −1 to
  keep private class names out of the binary's strings for App Review. The effect:
  the child transition view is forced to `view.bounds`, i.e. **the child content
  fills the whole screen and is *not* shortened by the 49-point tab bar**. The
  children are responsible for their own bottom inset.

---

## 9. Our port

Our equivalent is split in two, and the split is faithful:

- `iTgLegacy/src/TGTabBar.h` / `TGTabBar.m` (262 lines) — the extracted `TGTabBar`
- `iTgLegacy/src/TGTabsContainerViewDelegate.m` — the layout hack, an exact
  transcription (the obfuscation is dropped and the class names written plainly,
  which is correct for us)
- `iTgLegacy/src/RootViewController.m` (140 lines) — the controller

**Artwork is byte-identical.** I md5'd all nine PNGs (`TabBarBackground@2x`,
`TabBarSelected@2x`, `TabBarBadge@2x`, and the six icons) against
`telegram_iphone.src/Telegraph/Telegraph/Resources/` — all nine match. Nothing to
do there. (We additionally ship 1× copies of the six icons in `iTgLegacy/images/`,
which the original never had; on a 4S they are never loaded, so this is dead weight
rather than a defect.)

`TGTabBar.m` is a near-line-for-line port: the column maths (`TGTabBar.m:89–100` vs
`.m:119–132`), the icon `y = 4` and label `y = 35` (`TGTabBar.m:244, 257` vs
`.m:243, 261`), the badge geometry, the `%dK`/`%dM` formatting, the `retinaPixel`
half-point, the touch-down selection, the `0x999999` label colour and bold-10 font
— all correct. It even keeps `MAX(20, textWidth + 12 + retinaPixel * 2)` and the
right-anchored badge growth. Good work; I have no complaints about the view.

### Differences a user could see

1. **Re-tapping the selected tab does nothing.** Original: `.m:430–434` calls
   `scrollToTopRequested` on the selected controller. Ours: `RootViewController.m:91–94`
   only acts when the index actually changes. On a long chat list, tapping
   "Messages" while already on Messages should fling the list to the top; today it
   is inert. Fix: in `tabBarSelectedItem:`, when the index is unchanged, walk to the
   visible controller and call `scrollToTopRequested` (or, given our nested nav
   controllers, `setContentOffset:` to the top of its table).

2. **Per-tab navigation controllers instead of one outer stack.**
   `RootViewController.m:31–43` wraps each tab in its own `UINavigationController`.
   The original has none (`TGAppDelegate.mm:297–303`): the tabs controller *is* the
   root of one shared stack. Consequence, and it is visible: when you push a chat,
   the original slides the tab bar off-screen with the rest of the view, whereas we
   set `self.customTabBar.hidden` in `navigationController:willShowViewController:`
   (`RootViewController.m:86–89`), which makes the bar **vanish instantly at the
   start of the push animation** and reappear instantly on the pop, instead of
   travelling with the content. This is the single most visible deviation in the
   component. Given ~100k lines already built on nested nav controllers I am not
   proposing to restructure; the cheap approximation is to animate the bar out
   alongside the push (translate it down/left over the transition duration) rather
   than toggling `hidden`.

3. **No `TGTabControllerChild` title proxying, and therefore no shared title
   styling.** The original centralises the title in a `TGLabel` with bold system 20,
   white, shadow `0x3d5c81` offset `(0,-1)` (`.m:505–517`,
   `TGViewController.mm:79–87, 133–140, 151–173`). Ours leaves each child's
   `navigationItem` to itself and styles the bar globally in `TGTheme.m:456–459`,
   which sets only `NSForegroundColorAttributeName`/`UITextAttributeTextColor` — **no
   shadow colour and no shadow offset**. So our titles are missing the 2013
   letterpress that the original had on every one of the three tab screens.
   Grepping our tree, `0x3d5c81` appears only in `TGTopicsViewController.m:1012, 1023`,
   nowhere in the bar title path. Fix: add
   `UITextAttributeTextShadowColor = UIColorRGB(0x3d5c81)` and
   `UITextAttributeTextShadowOffset = CGSizeMake(0,-1)` (with the
   `NSShadowAttributeName` variant on the iOS 7+ branch) in `TGTheme.m:456–459`.

4. **Tab titles are hardcoded English.** `TGTabBar.m:38` uses the literal array
   `@[@"Contacts", @"Messages", @"Settings"]`; the original goes through
   `TGLocalized(@"Contacts.TabTitle")` etc. (`.m:81, 91, 101`). Same strings in
   English (`en.lproj/Localizable.strings:248, 220, 533`), so nothing is visibly
   wrong today, but the tab bar is the one place in the app that can never be
   translated. Also note ours reuses the same literal as the accessibility label
   (`TGTabBar.m:56`), so localising it fixes both.

5. **The unread count means something different.** Ours sums per-chat unread
   counts and **skips muted chats** (`RootViewController.m:113–124`, the
   `isMuted` continue). The original passes through the server's total unread
   count verbatim from `/tg/unreadCount` (`TGTelegraphDialogListCompanion.mm:941–951`),
   and I found no mute filtering anywhere in the database path that produces it
   (`TGDatabase.mm:4256–4262` just adds deltas). So a user with a noisy muted
   group sees a badge in 1.1 and no badge in ours. This is a *modern* behaviour
   (today's client has an explicit include-muted setting), so it is arguably a
   deliberate improvement rather than a bug — but it is a divergence from the
   original and should be a conscious one, not an accident. Our version also sets
   the app icon badge from the same number (`RootViewController.m:134–135`), which
   matches the original's placement of that call (`…DialogListCompanion.mm:946`).

6. **The layout delegate is installed on one view, not two.**
   `RootViewController.m:25` calls `setLayoutDelegateForContainerView:` on
   `self.view` only; the original also installs it on `self.view.subviews[0]`
   (`.m:351–352`) with a *separate* delegate instance. `self.view` of a
   `UITabBarController` is the `UILayoutContainerView`, and `subviews[0]` is the
   `UITransitionView` whose own subviews need forcing to full bounds. Symptom to
   look for: a child's view coming up 49 points short at the bottom (or a gap
   above the tab bar) on the first appearance of a tab. If our children are already
   correct in practice this may be redundant, but it is a real gap against the
   original and cheap to close.

7. **Tab bar insets are applied by us, not by the children.** `applyTabBarInsetForIndex:`
   (`RootViewController.m:61–78`) pokes a 49-point `contentInset` into the child's
   table view, once per tab, and only if the child is a `UITableViewController`
   whose controller is the nav stack's first. The original does none of this — the
   full-bleed content is the point of `TGTabsContainerViewDelegate` and each child
   sets its own inset. Two consequences: any tab whose root is not a plain
   `UITableViewController` silently gets no bottom inset (its last row hides under
   the bar), and the inset is applied once and never re-applied, so a child that
   later resets `contentInset` itself loses it. Not visibly broken today for the
   three tabs we ship, but it is a fragile mechanism the original deliberately
   avoided.

8. **Minor, non-visible hardening we added and should keep**: index clamping in
   `setSelectedIndex:` (`TGTabBar.m:114–115`), the `count == 0` / zero-width guards
   (`TGTabBar.m:86–87, 228–229`), generalising `_selectedIndex == 2` to
   `count - 1` (`TGTabBar.m:97`), clearing the badge text when the count drops to
   zero (`TGTabBar.m:190`, which fixes the stale-text case noted in §5), and the
   accessibility values (`TGTabBar.m:68–81`). None of these change pixels; all are
   improvements.

I did **not** find any metric, colour or asset error in `TGTabBar.m`. The defects
are all at the controller layer and all stem from the one architectural choice in
item 2.

---

## 10. What became of it

### `twelve` (Objective-C fork, same lineage)

`twelve/Telegraph/TGMainTabsController.m` is 1149 lines against the original's 613,
and the header (`twelve/Telegraph/TGMainTabsController.h:7–29`) has grown
`setMissedCallsCount:`, `setUnreadArrow:`, `setCallsHidden:animated:`,
`localizationUpdated`, `frameForRightmostTab`, `controllerInsetUpdated:` and a
`TGPresentation` theming object. The interesting parts for us:

- **A fourth tab (Calls) was added and made optional**, which broke the hardcoded
  `/ 3`. The buttons became an array `[contacts, calls, chats, settings]` with the
  calls button hidden by default (`twelve/…/TGMainTabsController.m:449–456`), and
  the badge moved from a bar-owned view positioned against index 1 to a
  `TGTabBarBadge` **added as a subview of the button itself** (`:640, 657`) and
  positioned relative to `button.imageView.center` (`:724–732`). That is the right
  refactor and the one we would need if we ever add a tab: our badge is still
  hardcoded to `index == 1` (`TGTabBar.m:247`).
- The badge count is split: `messagesBadge` shows `MAX(0, messages - calls)`
  (`:691`), because missed calls are counted inside the unread total.
- Selection moved from `touchesBegan` to a pair of `UILongPressGestureRecognizer`s
  — one with `minimumPressDuration = 0.0` for the tap, one at 0.25 s on the chats
  button for a long-press menu, with `requireGestureRecognizerToFail:` between them
  (`:459–470`). Forced by the new long-press feature, not taste.
- The PNG background survives only under a `[TGPresentation classicIOS6Style]`
  branch (`:422–430`), where it is drawn over an opaque `UIColorRGB(0x242424)` base
  — note they had to add that opaque base precisely because the original PNG is
  92% opaque, and they also added a `stripeView` of `UIColorRGB(0xa4a8ac)` above
  the bar, which the 2013 original does **not** have. If we ever want to justify a
  hairline, twelve is not evidence for it; the original artwork is.

### `Telegram-iOS` (modern)

The tab bar is now `submodules/TabBarUI` + `submodules/Display/Source/TabBarController.swift`,
built on ASDisplayKit nodes, with `TabBarControllerImpl` a protocol
(`TabBarController.swift:14–27`). Concepts that survived: 49 points as the base
height (`TabBarUI/Sources/TabBarController.swift:190–194`, now `49.0 + bottomInset`
for the home indicator, or 34 in landscape on notched devices), and the
tap-the-selected-tab-to-scroll-to-top gesture, now split into
`scrollToTopWithTabBar` and a separate `longTapWithTabBar` plus explicit
double-tap hooks (`TabBarController.swift:208–232`).

The one change of substance: **the switch no longer happens on touch-down.** The
modern controller subscribes to the target controller's `ready` signal and only
then sets `selectedIndex` (`TabBarController.swift:200–219`) — and it prints a
warning if the controller took more than 0.5 s to become ready. That is a change
forced by content that cannot be built synchronously (async node layout, remote
data), not a change of taste. On a 4S with synchronous UIKit views the 2013
touch-down behaviour is both cheaper and more responsive, so we should keep it.

Selection styling also changed completely: the 5%-white column wash and the
paired normal/highlighted PNGs are gone, replaced by a single template icon
tinted with the palette's accent colour. That *is* taste — the flat-design turn of
iOS 7 — and is exactly the sort of change our project exists to undo.

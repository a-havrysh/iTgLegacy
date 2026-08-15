# TGSearchBar (original, Telegram for iOS v1.1 / build 21024)

Source of truth for everything below:
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
(abbreviated below as `ORIG`). Paths are relative to it.

---

## 1. What it is

`TGSearchBar` is **not** a from-scratch view. It is a thin `UISearchBar` subclass
(`ORIG/TelegraphKit/TelegraphKit/TGSearchBar.h:19`) that keeps UIKit's text field, scope
segmented control and layout, and only overrides four things:

1. the **cancel button** — replaced by a hand-made `UIButton` with artwork, because the
   system one could not be skinned to the 2013 look (`TGSearchBar.m:24-49`);
2. the **height contract** when a scope bar is present — 44 vs 88, announced to a delegate
   (`TGSearchBar.m:129-154`);
3. the **placeholder colour**, via a recursive walk to the private `UITextField` plus a
   swizzled `drawPlaceholderInRect:` (`TGSearchBar.m:176-192`, `TGHacks.m:115-128`);
4. `_setCombinesLandscapeBars:`, reached through an obfuscated selector, so the bar does not
   collapse into the navigation bar in landscape (`TGSearchBar.m:194-211`).

Everything else — the rounded input field, the magnifier icon, the clear button, the
gradient plate — is *not* in this class at all. It is applied from the outside by the two
controllers that use the bar. This is the single most important structural fact about the
component and the thing our port got wrong (§5).

The whole class is 213 lines. Nothing about it is smart; it is a workaround wrapper.

### Public surface (`TGSearchBar.h`)

| Member | Line | Meaning |
|---|---|---|
| `searchContentInset` (`UIEdgeInsets`) | `:21` | Proxied to `UIScrollView.contentInset` on `self` — `UISearchBar` privately *is* laid out through a scroll-view-shaped ivar path; the getter/setter simply casts (`TGSearchBar.m:166-174`). Right inset drives how far the text field stops short of the cancel button; bottom inset drives the scope-bar extension. |
| `searchBarShouldShowScopeControl` (`bool`) | `:23` | Setting it recomputes the required height and notifies the delegate (`:129`). |
| `useDarkStyle` (`bool`) | `:25` | Chooses between `SearchCancelButton*.png` and `SearchDarkCancelButton*.png` only (`:28-29`). It affects nothing else — the dark input field and dark magnifier are set by the caller. Must be set **before** the cancel button is first shown, since the button is built once and cached. |
| `-setSearchPlaceholderColor:` | `:27` | Recursive descent to the `UITextField`. |
| `-setSearchBarCombinesBars:` | `:29` | Private-API bridge. |
| `TGSearchBarDelegate` — `searchBar:willChangeHeight:` | `:15` | The bar does not resize itself; it *asks*. The owner adjusts the table header / container. |

Note the delegate protocol is standalone (`<NSObject>`) and the bar sends
`searchBar:willChangeHeight:` to `self.delegate`, which is typed as `UISearchBarDelegate`.
So the same object plays both roles; `TGSearchDisplayMixin` declares
`<UISearchBarDelegate, TGSearchBarDelegate>` for exactly that reason
(`ORIG/TelegraphKit/TelegraphKit/TGSearchDisplayMixin.m:9`).

---

## 2. The cancel button (the part that is genuinely designed)

`TGSearchBar.m:24-49`. Lazily built, cached forever in `_searchCancelButton`.

- Frame `CGRectMake(0, 7, 59, 30)` (`:31`). 30pt tall inside a 44pt bar with a 7pt top
  offset, leaving 7pt below — vertically centred.
- Background: `SearchCancelButton.png` / `SearchCancelButton_Pressed.png`, or the
  `SearchDark…` pair when `useDarkStyle` (`:28-29`). Stretched with
  `leftCapWidth = width/2, topCapHeight = 0` (`:32-33`) — i.e. horizontally stretchable pill,
  fixed height. Asset is 36×60 px = **18×30 pt** (measured with `sips` on
  `ORIG/Telegraph/Telegraph/Resources/SearchCancelButton@2x.png`), so cap width 9pt each side.
- The artwork is **not** the modern blue: sampled centre pixel is `#7889a2`, top edge
  `#8b9db4`, bottom edge `#506375`, side edge `#56697c` — a desaturated slate-blue pill with a
  vertical gradient and a darker rim. Pressed variant centre is `#6a7c96`, i.e. uniformly
  darkened by roughly 6%.
- Title `Common.Cancel`, white, bold **system 12pt** (`:35-41`). Shadow colour
  `UIColorRGBA(0x112e5c, 0.2)` at offset `(0, -1)` — a dark blue shadow *above* the glyphs,
  which is the 2013 engraved-on-a-gradient convention.
- `autoresizingMask = UIViewAutoresizingFlexibleLeftMargin` (`:43`) so it stays pinned right
  when the bar is resized by rotation.
- Tap → `searchCancelButtonPressed` → forwards `searchBarCancelButtonClicked:` to the
  delegate (`:158-164`). The bar itself performs **no** state change on cancel; clearing the
  text and resigning first responder is the mixin's job
  (`TGSearchDisplayMixin.m:148-150`).

### Show/hide geometry and animation (`TGSearchBar.m:61-120`)

The whole dance is 75 points wide:

- shown: button `origin.x = width - 6 - 59`, i.e. **6pt from the right edge**;
  `searchContentInset.right = 75`.
- hidden: button parked at `width - 6 - 59 + 75` (off to the right, beyond the edge);
  `searchContentInset.right = 5`.
- animated: 0.2s, insets and button frame animated together, `layoutSubviews` called inside
  the animation block so the text field shrinks in step; the button is removed from the
  hierarchy in the completion block only when hiding (`:95-102`).
- non-animated path duplicates all of it (`:104-118`).

75 = 59 (button) + 6 (right gap) + 10 (gap between field and button). The right inset of 5pt
in the resting state is what makes the field stop 5pt short of the bar edge.

Two real bugs in the original worth knowing so we do not faithfully reproduce them:
`buttonFrame.origin.x = buttonFrame.origin.x = …` (double assignment, harmless) at `:93` and
`:113`; and `setShowsCancelButton:` early-returns on an unchanged value, so a re-show after a
layout width change never repositions the button — it relies on the autoresizing mask.

---

## 3. Height, scope bar and the delegate contract

`setSearchBarShouldShowScopeControl:` (`TGSearchBar.m:129-154`):

```
requiredHeight = (shouldShowScope && self.frame.size.width < 400) ? 88 : 44;
```

- **44pt** is the base bar. **88pt** = 44 + 44 when the scope segmented control is stacked
  below rather than beside the field. The `< 400` test is a width test, not a device test:
  iPhone portrait (320) and landscape (480 → not < 400, so combined) — on iPad, and on iPhone
  landscape, the scope control sits inline and the bar stays 44.
- The extra height is expressed as `searchContentInset.bottom = requiredHeight - 44`
  (`:146-148`), not as a frame change. The bar's own frame is changed by whoever owns it,
  after `searchBar:willChangeHeight:` arrives (`:150-152`).
- The guard is `ABS(requiredHeight - height) > FLT_EPSILON` — the delegate is only told on an
  actual change.
- `layoutSubviews` deliberately does **not** re-apply this; the call is commented out at
  `:126`. So a rotation alone will not re-evaluate the 400pt test — the mixin drives it
  instead, from `_updateSearchBarLayout:` (`TGSearchDisplayMixin.m:190-243`), which reads
  `scopeButtonTitles.count > 1`, toggles `showsScopeBar` to match activation, flips
  `setSearchBarCombinesBars:` on the same `< 400` threshold, and then calls `sizeToFit`
  (`:207-221`).
- The scope segmented control is nudged when UIKit inserts it: `didAddSubview:` catches any
  `UISegmentedControl` and applies `contentPositionAdjustment (0, +1)` for all segments
  (`TGSearchBar.m:14-22`) — the 2013 segment artwork sits one point high otherwise.
- When the scope bar is visible, the mixin cross-fades content changes with a 0.2s
  `CATransition` on the bar's layer, scaled by `TGAnimationSpeedFactor()`
  (`TGSearchDisplayMixin.m:280-287`).

---

## 4. The skin, and who applies it

### 4a. Light style — country picker

`ORIG/Telegraph/Telegraph/TGLoginCountriesController.m:280-296` is the canonical light usage:

- created at `CGRectMake(0, 0, tableWidth, 44)` and installed as `tableView.tableHeaderView`
  (`:280`, `:284`);
- `setBackgroundImage:[UIImage imageNamed:@"SearchBarBackground.png"]` guarded by a
  `respondsToSelector:` check (`:281-282`) — that selector is iOS 5+;
- above the table, a 500pt-tall filler view at `y = -500` painted `#e4e9f0`
  (`:273-278`) so overscrolling above the search bar shows the bar's own top colour, not
  white. The colour matches `dialogListHeaderColor` (`TGInterfaceAssets.mm:175-178`);
- `clearInputFieldBackground:andSetIcon:` (`:299-336`) then walks the whole view tree;
- `hideStripe:` (`:338-345`) walks the tree and hides **any `UIImageView` exactly 1pt tall** —
  that is how UIKit's own bottom hairline is killed. Cheap, and it works because nothing else
  in a search bar is a 1pt image view.

`SearchBarBackground@2x.png` is 8×88 px = **4×44 pt**: a vertical gradient sampled
`#e4e9f0` at the top → `#dee4ec` at 10pt → `#d4dbe4` at 22pt → `#c7d0da` at 40pt, with the
last row `#aeb7c2` acting as the separator line. Because it is handed to `setBackgroundImage:`
unstretched, UIKit tiles/stretches it to the bar; at 88pt (scope open) the gradient is
stretched, not repeated — this is why a separate `SearchBarScopeBarBackground@2x.png`
(8×88 px, also 4×44 pt) exists for the scope strip.

`clearInputFieldBackground:andSetIcon:` on the `UITextField` (`:299-336`):

| Step | Line | Detail |
|---|---|---|
| `textField.background = nil` | `:305` | kills UIKit's own capsule |
| `clipsToBounds = false` | `:306` | so the replacement capsule may overhang |
| placeholder colour `#8d9298` | `:308` | via `TGHacks`; drawn in `self.font` with `NSLineBreakByTruncatingTail` and the field's own alignment (`TGHacks.m:115-124`) — an over-long placeholder ellipsises, it does not shrink |
| clear button offset `+0.5` on retina | `:309-310` | via swizzled `clearButtonRectForBounds:` (`TGHacks.m:130-137`) — non-retina gets 0 |
| clear button images | `:312-322` | `ClearInput.png` / `ClearInput_Pressed.png`, reached through the runtime-assembled selector `"clear" + "Bu" + "tton"` to dodge App Store static analysis; 38×38 px = 19×19 pt |
| capsule | `:324-330` | `SearchInputField.png`, stretched `leftCap = w/2, topCap = 0`; an extra `UIImageView` added **as a subview of the text field**, `y = 0.5` on retina else `0`, width = field width, height = image height, `FlexibleWidth` |
| magnifier | `:332-336` | the field's existing `leftView`, if it is a `UIImageView`, gets its image swapped for `SearchBarIcon.png` and `sizeToFit` |

`SearchInputField@2x.png` is 74×64 px = **37×32 pt**, cap 18pt each side. Sampled: top row
`#a9b4c2` (rim), row 1 `#e5e7ea` (inner shade), centre `#ffffff`, left edge `#aeb8c4`, and the
bottom two rows are `#d2d9e1` at alpha 191 then 64 — a soft outer shadow, which is exactly why
`clipsToBounds` must be off and why the view is offset by half a point on retina.

`SearchBarIcon@2x.png` is 30×32 px = **15×16 pt**; `SearchBarDarkIcon@2x.png` is the same
size. The icon is fetched through `[[TGInterfaceAssets instance] dialogListSearchIcon]`
(`TGInterfaceAssets.mm:185-191`), which caches it in a static.

### 4b. Dark style — image search

`ORIG/TelegraphKit/TelegraphKit/TGImageSearchController.mm:326-341`:

- bar at `(0, 0, width, 44)` inside a 45pt `_navigationBarContainer` sitting on a
  `SearchHeaderDark.png` stretchable plate (`:313-325`), with a 10pt pure-black strip behind
  the top corners (`:316-319`);
- `useDarkStyle = true` (`:330`) — this only pre-selects the dark cancel artwork;
- background image is `Transparent.png` (`:332`) so the header plate shows through, rather
  than nil (nil would restore UIKit's own bar);
- placeholder colour `#999999` (`:334`) — note it is *not* the light value `#8d9298`;
- magnifier via the public `setImage:forSearchBarIcon:state:` (`:336`) rather than the
  leftView hack, because there is no need to also replace the capsule background by hand:
- capsule via the public `setSearchFieldBackgroundImage:forState:` with
  `SearchDarkInputField.png` stretched `w/2 / 0` (`:338-339`). 72×60 px = **36×30 pt**.

So the original has **two different techniques** for the same capsule: the private-ish
subview hack in the light path (needed on iOS 5, where `setSearchFieldBackgroundImage:` gives
a worse result with the shadow) and the public API in the dark path. Both ship.

### 4c. Assets belonging to this component

All under `ORIG/Telegraph/Telegraph/Resources/`, sizes measured, points = px/2:

| Asset | px | pt | Used at |
|---|---|---|---|
| `SearchBarBackground@2x.png` | 8×88 | 4×44 | `TGLoginCountriesController.m:282` |
| `SearchBarBackground_Strong@2x.png` | 84×88 | 42×44 | **unreferenced in source** — dead or used only via the xib-less iPad path |
| `SearchInputField@2x.png` | 74×64 | 37×32 | `TGLoginCountriesController.m:324` |
| `SearchDarkInputField@2x.png` | 72×60 | 36×30 | `TGImageSearchController.mm:338` |
| `SearchBarIcon@2x.png` | 30×32 | 15×16 | `TGInterfaceAssets.mm:189` |
| `SearchBarDarkIcon@2x.png` | 30×32 | 15×16 | `TGImageSearchController.mm:336` |
| `SearchCancelButton@2x.png` / `_Pressed` | 36×60 | 18×30 | `TGSearchBar.m:28-29`, also `TGInterfaceAssets.mm:193-211` |
| `SearchDarkCancelButton@2x.png` / `_Pressed` | 36×60 | 18×30 | `TGSearchBar.m:28-29` |
| `ClearInput@2x.png` / `_Pressed` | 38×38 | 19×19 | `TGLoginCountriesController.m:319-320` |
| `SearchBarScopeBarBackground@2x.png` | 8×88 | 4×44 | scope strip; no direct code reference |
| `SearchBarScopeButton@2x.png` / `_Highlighted` | 74×60 | 37×30 | scope segments; applied via `UISegmentedControl` appearance, not in this file |
| `SearchBarShadowTop@2x.png` | 6×12 | 3×6 | no code reference in this build |
| `SearchBarShadowBottom@2x.png` | 6×10 | 3×5 | no code reference in this build |
| `SearchHeaderDark@2x.png` | 48×90 | 24×45 | `TGImageSearchController.mm:321` |

That several of these have no call site is worth stating plainly rather than inventing a use
for them: in v1.1 the shadows and `_Strong` background are shipped but unused.

---

## 5. Our port — judgement

**There is no `TGSearchBar` in `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src`.** The wrapper
was never ported; its skinning code was copy-pasted into at least six controllers:

- `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGTopicsViewController.m:869-961`
  (`buildSearchBar`, `styleSearchBar`, `styleSearchInputField:`)
- `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGChatListViewController.m:2367-2381`
  (`styleSearchBar`)
- `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGSearchViewController.m:609-616`,
  `:1566-1620`
- `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGCountryPickerViewController.m:398`,
  `:541-590`
- `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGContactsViewController.m:2485-2510`,
  `:2605-2611`
- `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGForwardPicker.m:318`, `:375-390`
- plus `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGMediaViewController.m:2371`

These copies have already drifted from one another (`TGContactsViewController.m:2490` looks up
`@"SearchInputField"` without the `.png` extension while everyone else uses `.png`;
`TGForwardPicker.m` has its own `dressSearchField:`), which is precisely the failure mode the
original avoided by keeping one subclass.

### Differences a user can see

1. **The cancel button is the system one.** The original's slate-blue pill
   (`TGSearchBar.m:24-49`) does not exist in our tree: `find` over
   `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/images` shows no `SearchCancelButton*.png` and
   no `SearchDarkCancelButton*.png`. `TGTopicsViewController.m:1122` just calls
   `[searchBar setShowsCancelButton:YES animated:YES]`, so iOS 6 draws its own glass button.
   *Fix:* ship the two (four, with pressed) assets and reproduce `TGSearchBar.m:31-45` —
   frame `(0, 7, 59, 30)`, stretch caps `w/2 / 0`, white bold system 12, shadow
   `#112e5c` at 20% offset `(0, -1)`, right margin 6, content inset right 75/5, 0.2s.

2. **`ClearInput.png` is referenced but not shipped.**
   `TGTopicsViewController.m:947-953` and `TGSearchViewController.m:1601-1613` load
   `ClearInput.png` / `ClearInput_Pressed.png`, and both guard with `if (clear)`, so the code
   silently falls back to the system clear glyph. The assets exist in
   `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/images` — but the built app bundle at
   `build/armv7/app/iTgLegacy.app` contains only `SearchBarBackground@2x.png`,
   `SearchBarIcon@2x.png` and `SearchInputField@2x.png`. Whatever copies resources is not
   copying the rest. *Fix:* audit the resource copy list; this is the reason the search field
   looks half-right on device.

3. **We never offset the clear button by half a point on retina.** Original:
   `TGLoginCountriesController.m:309-310` via `TGHacks setTextFieldClearOffset:0.5`. Ours has
   no equivalent anywhere. On the 4S this is a visible half-pixel misalignment between the
   clear glyph and the capsule.

4. **Capsule z-order differs.** Original does `[textField addSubview:inputImageView]`
   (`TGLoginCountriesController.m:329`); ours does
   `[field insertSubview:inputImageView atIndex:0]`
   (`TGTopicsViewController.m:937`, `TGSearchViewController.m:1596`). On iOS 6 the field's text
   is rendered by internal subviews added later, so both orders happen to work; ours is the
   safer one. **Do not "fix" this to match** — but be aware that ours also means the capsule
   sits behind the UIKit background if `field.background` is ever non-nil. Both set it to nil,
   so this is fine. Flagging it as a deliberate, justified divergence.

5. **The half-point offset is unconditional in ours.** `TGTopicsViewController.m:934` and
   `TGSearchViewController.m:1594` hardcode `y = 0.5f`; the original is
   `TGIsRetina() ? 0.5 : 0` (`TGLoginCountriesController.m:327`). Irrelevant on a 4S. Leave it,
   or gate it if a non-retina target ever appears.

6. **We set the field font explicitly to system 14; the original never sets it.**
   `TGTopicsViewController.m:901-903`, `TGSearchViewController.m:1570-1572`. iOS 6's own
   search field is system 14, so the rendering matches — but the original's placeholder is
   drawn with `self.font` (`TGHacks.m:122`), so if anyone ever changes ours to a non-14 value,
   text and placeholder still track together. No user-visible defect today; note it and move on.

7. **Placeholder colour is right.** `#8d9298` in
   `TGTopicsViewController.m:915` and via `applyPlaceholderColour` in
   `TGSearchViewController.m:1578`, matching `TGLoginCountriesController.m:308`. Ours uses
   `attributedPlaceholder` (iOS 6+) rather than the swizzle, which is the correct modern
   choice — but it silently does nothing when `field.placeholder.length == 0`
   (`TGTopicsViewController.m:914`), so a bar whose placeholder is set *after* styling gets
   the default grey. Set the placeholder before calling the styler.

8. **No dark-style path at all.** The original's dark variant
   (`TGImageSearchController.mm:326-339`: `#999999` placeholder, `SearchDarkInputField`,
   `SearchBarDarkIcon`, transparent bar background over a `SearchHeaderDark` plate) has no
   counterpart. Ours instead flips `barStyle = UIBarStyleBlack` and hands the whole job to
   UIKit (`TGChatListViewController.m:2369`, `TGTopicsViewController.m:887`). That is a
   defensible substitution for themed skins the original never had, but for anything meant to
   look like the 2013 image picker it is wrong.

9. **The scope-bar height contract is reimplemented, not ported.**
   `TGSearchViewController.m:801-840` builds its own `_scopeBar` view at
   `kSearchScopeHeight = 44` (`:23`), with its own buttons at bold system 12 (`:828`) and its
   own `SearchScopeBarScopeDivider{Left,Right}` images. The original let `UISearchBar` own the
   segmented control and only nudged it `(0, +1)` (`TGSearchBar.m:18`) and reported 88pt total
   (`:137`). Ours reaches the same 44 + 44 arithmetic, so the *result* is right. Two things to
   check against the original: our scope buttons fire on `UIControlEventTouchDown`
   (`TGSearchViewController.m:833`) whereas a segmented control commits on touch-up, and we
   have no equivalent of the 0.2s `CATransition` cross-fade the mixin applies whenever the
   scope bar is showing (`TGSearchDisplayMixin.m:280-287`).

10. **The `< 400` width rule is absent.** Nothing in our tree implements
    "scope inline in landscape, stacked in portrait" (`TGSearchBar.m:135`), nor the
    `setSearchBarCombinesBars:` toggle that goes with it
    (`TGSearchDisplayMixin.m:207-221`). On a 4S in landscape (480pt ≥ 400) the original
    switched to a single 44pt combined bar. If we support landscape at all, ours will keep
    the stacked 88pt layout and eat half the screen.

11. **`hideStripe:` is present in the right places** (`TGForwardPicker.m:325`,
    `TGCountryPickerViewController.m`) but is *not* applied in
    `TGTopicsViewController`/`TGChatListViewController`, where the bar sits on a themed list.
    Compare `TGLoginCountriesController.m:293`. If a 1pt UIKit hairline is visible under the
    chat-list search bar, this is why.

12. **The `-500` overscroll filler is missing** in most of our search hosts. Original:
    `TGLoginCountriesController.m:273-278`, a 500pt `#e4e9f0` block above the table so a rubber-band
    pull shows the bar's top gradient colour. Without it the user sees the table background
    (or white) above the search bar when overscrolling — a real, easily-noticed difference on
    the chat list.

---

## 6. What became of it

### `twelve` (`/Users/alexanderhavrysh/Git/iOS/twelve`), same Objective-C lineage

`submodules/LegacyComponents/LegacyComponents/TGSearchBar.h` keeps the *name* and the
`searchBar:willChangeHeight:` delegate method (`:17`) — and throws away the base class:
it is now `@interface TGSearchBar : UIView` (`:44`), 1297 lines, with its own
`customTextField`, `placeholderLabel`, `customSearchIcon`, `customClearButton`,
`customCancelButton` and `customSegmentedControl` (`TGSearchBar.m:98-118`). Every private-API
hack from 2013 is gone because nothing is UIKit's any more.

This is the answer to "how does this component extend when features arrive": it does not.
The wrapper was replaced wholesale the moment more than two skins were needed. The fork
carries seven styles (`TGSearchBarStyle`, `.h:5-13`) plus a full `TGSearchBarPallete` object
of fifteen colours and images (`.h:21-42`) — the exact thing a `UISearchBar` subclass cannot
express.

Metrics moved with it: base height is now `inputHeight + 12` where `inputHeight` is 28
(36 for `LightAlwaysPlain`, 33 for `Keyboard`), pinned back to 44 only while the scope bar
shows (`TGSearchBar.m:121-150`); scope height stayed 44 (`:154-157`); the placeholder/field
font is system 14, or 16 for the always-plain style (`:308`, `:660`).

**Directly useful to us:** twelve ships an iOS 6 nostalgia mode. Behind
`TGSearchBarClassicIOS6Style()` (`TGSearchBar.m:17-20`, a `TGClassicIOS6Style` user default)
it *redraws our exact artwork in Core Graphics*:

- `TGSearchBarClassicFieldImage()` (`:22-64`) — 30×30pt, `cornerRadius 14.5`, white fill under
  a shadow `(0, 1)` blur 1 at `#000000` 32%, then a clipped vertical gradient
  `(0.82, 0.84, 0.86) → white at 18% → (0.95, 0.95, 0.95)`, a 1pt `#8d969f` rim and an inner
  1pt `#ffffff` 72% highlight at radius 13.5; caps 14/14.
- `TGSearchBarClassicBackgroundImage()` (`:66-88`) — 1×44, gradient
  `(0.91, 0.93, 0.95) → (0.72, 0.76, 0.80)`, a `#ffffff` 70% top hairline and a `#77818a`
  bottom hairline at y = 43; caps 0/21.

Those two functions are an independent, later reading of the same design, and they agree with
my pixel samples of the 2013 PNGs to within a couple of levels (`#e8edf2` vs `#e4e9f0` at the
top, `#b8c2cc` vs `#c7d0da`/`#aeb7c2` at the bottom — twelve's gradient is slightly cooler and
its separator darker). Where our port needs a value the PNG cannot give, these are the best
secondary source. Where they disagree with the PNG, **the PNG wins** — it is the shipped asset.

### `Telegram-iOS` (`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS`)

`submodules/SearchBarNode/Sources/SearchBarNode.swift`. An `ASDisplayNode`, themed through
`SearchBarNodeTheme` (`:765-812`) rather than images; the capsule is a plain node with
`cornerRadius = fieldStyle.cornerDiameter / 2` (`:1045`); font is system **17** for the modern
style and 14 for the legacy one (`:842-844`); the placeholder is a real `ImmediateTextNode`
with `maximumNumberOfLines = 1` and `.byTruncatingTail` (`:534-538`) — the same truncation
rule the 2013 swizzle enforced (`TGHacks.m:122`), reached thirteen years later by a completely
different road. New capability that forced most of the rewrite: **tokens** — chips inside the
field for filters/tags, laid out before the placeholder (`:144`, `:684-706`), which is
structurally impossible in a `UITextField`.

Verdict on the evolution: the loss of the artwork is taste (flat design). The loss of
`UISearchBar` is force — skinning, then tokens.

---

## 7. Open questions / genuine ambiguity

- `SearchBarShadowTop/Bottom` and `SearchBarBackground_Strong` have no call site in this
  build. They may be leftovers from 1.0 or consumed by a nib we do not have. I would not
  invent a use.
- The scope segmented control's own artwork (`SearchBarScopeButton*`,
  `SearchScopeBarScopeDivider*`) is never wired up in any `.m` I can find — presumably a
  `UISegmentedControl` `appearance` proxy set somewhere outside the search code, or an
  Interface Builder setting. Our hand-built scope bar in `TGSearchViewController.m` is
  therefore not directly comparable to anything; judge it on the screenshots, not the source.
- Whether the original's light capsule sits above or below the text on iOS 6 depends on
  `UITextField` internals I cannot verify by reading. `addSubview:` at
  `TGLoginCountriesController.m:329` implies it renders above and the text still shows, which
  means iOS 6 draws the text in a subview added later. Our `insertSubview:atIndex:0` is
  robust either way; I am recording this as unresolved rather than claiming the original was
  wrong.

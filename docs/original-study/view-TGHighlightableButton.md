# TGHighlightableButton (original, Telegram for iOS v1.1 build 21024)

Paths below are relative to `/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
unless stated otherwise. Our port lives in `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src`.

## 1. What it is

The class exists exactly as named:

- `TelegraphKit/TelegraphKit/TGHighlightableButton.h` (16 lines)
- `TelegraphKit/TelegraphKit/TGHighlightableButton.m` (24 lines)

It is one of the smallest components in TelegraphKit and it fixes exactly two shortcomings of
`UIButton` in the 2013 skeuomorphic idiom:

1. **UIButton does not propagate its highlight to child views you add yourself.** `UIButton` swaps its
   own `backgroundImage`/`titleColor` per control state, but any `UIImageView` or `UILabel` you
   `addSubview:` on top of it stays in its normal state while the button is pressed. In a design where
   a pressed plate goes from light to dark blue, an unswapped grey chevron sitting on it looks wrong.
2. **UIButton has no per-state title shadow *offset*.** `setTitleShadowColor:forState:` exists;
   `titleLabel.shadowOffset` is a single value. In the 2013 language, a raised button has its title
   shadow *below* the glyphs (`(0, 1)`, light shadow = engraved highlight underneath) and a pressed
   button has it *above* (`(0, -1)`), because the plate is now recessed. This class flips that offset
   on press.

Header, `TGHighlightableButton.h:11-15`:

```objc
@interface TGHighlightableButton : UIButton
@property (nonatomic) bool reverseTitleShadow;
@property (nonatomic) CGSize normalTitleShadowOffset;
@end
```

That is the entire public surface. No initialiser, no drawing, no layout, no artwork of its own.

## 2. The whole implementation

`TGHighlightableButton.m:8-22`:

```objc
- (void)setHighlighted:(BOOL)highlighted
{
    for (UIView *view in self.subviews)
    {
        if ([view isKindOfClass:[UILabel class]])
            [(UILabel *)view setHighlighted:highlighted];
        else if ([view isKindOfClass:[UIImageView class]])
            [(UIImageView *)view setHighlighted:highlighted];
    }

    if (_reverseTitleShadow)
        self.titleLabel.shadowOffset = highlighted ? CGSizeMake(-_normalTitleShadowOffset.width, -_normalTitleShadowOffset.height) : _normalTitleShadowOffset;

    [super setHighlighted:highlighted];
}
```

Points that matter when rebuilding it:

- **The loop is over `self.subviews`, one level deep only** (`.m:10`). Nested image views inside a
  container view are *not* reached. Every call site therefore adds its chevron/label as a direct
  subview of the button.
- **`self.titleLabel` is itself a subview of the button**, so the loop hits it too and sets
  `titleLabel.highlighted = YES`. For a `UIButton` title label that is harmless — `UIButton` drives
  the title colour through `setTitleColor:forState:` on the next `super` call — but it means you
  cannot rely on `UILabel.highlightedTextColor` on the title label; the button's own state colour
  wins because `super setHighlighted:` runs *after* the loop (`.m:21`).
- **Order is deliberate**: subviews and shadow offset are updated *before* `super`, so a single
  redraw pass picks up the new background image and the new child states together. No animation, no
  `UIView` transaction — the swap is instantaneous, which is what the era's PNG-plate look wants.
- **`UIImageView` highlighting requires a `highlightedImage`.** The class only sets the flag; the
  pressed artwork has to be supplied at construction, e.g.
  `[[UIImageView alloc] initWithImage:... highlightedImage:...]` (`Telegraph/Telegraph/TGLoginPhoneController.m:183`).
  If the caller passes only a normal image, `setHighlighted:` is a no-op for that view and the child
  silently does not react — this is the single most likely way to get this component "wrong" and see
  nothing at all.
- **`reverseTitleShadow` defaults to `false`** (ivar zero-init), and `normalTitleShadowOffset`
  defaults to `CGSizeZero`. If you set `reverseTitleShadow = true` and forget
  `normalTitleShadowOffset`, the offset flips between `(0,0)` and `(-0,-0)`, i.e. the shadow silently
  disappears in both states. The two properties are a pair; neither is useful alone.
- **No reuse story.** There is no `prepareForReuse`, no content, no state beyond the two properties.
  It is safe in a cell because the only mutable state is derived from `highlighted` on every
  transition. The one caveat: `TGButtonsMenuItemView` reconfigures its buttons in place on
  `setButtons:` and only re-sets `normalTitleShadowOffset`/`reverseTitleShadow` inside the *green*
  branch (`TGButtonsMenuItemView.m:103-104`) — see §3.1.
- **Behaviour with long / empty / missing titles is plain `UIButton` behaviour**; this class adds
  nothing. Truncation, `titleEdgeInsets`, `contentHorizontalAlignment` are all the caller's problem,
  and the call sites do handle them (§3.2).

## 3. Call sites — what the class is actually for

Seven files import it (`grep -rl TGHighlightableButton`), six use it:

| File | Instance | Uses subview propagation | Uses shadow reversal |
| --- | --- | --- | --- |
| `Telegraph/Telegraph/TGButtonsMenuItemView.m:7-8` | grouped action buttons in a table cell | no | explicitly `false` |
| `Telegraph/Telegraph/TGWallpaperPreviewController.m:145,157` | Cancel / Set panel buttons | no | yes, on Set |
| `Telegraph/Telegraph/TGLoginPhoneController.m:164` | country selector | **yes** (chevron) | no |
| `Telegraph/Telegraph/TGLoginProfileController.m:146` | add-photo tile | no | no |
| `Telegraph/Telegraph/TGProfileController.m:742` | profile add-photo plate | no | no |
| `Telegraph/Telegraph/TGTelegraphConversationProfileController.mm:459` | group add-photo plate | no | no |
| `Telegraph/Telegraph/TGLoginWelcomeController.m:12` | **imports it but never uses it** — the tour's start button is a plain `UIButton` (`TGLoginWelcomeController.m:557`, `:596`) | — | — |

That last row is worth stating plainly: the welcome tour's green button, which visually belongs to the
same family, is a bare `UIButton` because it has no child views and no shadow flip. So the presence of
`TGHighlightableButton` in a screen is a signal, not a rule.

### 3.1 Grouped action buttons — `TGButtonsMenuItemView`

Factory, `TGButtonsMenuItemView.m:114-138`:

- artwork `GroupedActionButton.png` / `GroupedActionButton_Highlighted.png`, both stretched with
  `stretchableImageWithLeftCapWidth:(int)(width / 2) topCapHeight:0` (`:118-121`) — horizontal
  three-slice, no vertical stretch, so the button's height is locked to the PNG's height
  (`:122` uses `rawButtonImage.size.height` as the frame height, initial width a placeholder 100).
- title colour normal `0x4a6587`, highlighted white (`:125,:127`).
- title shadow normal `white @ 0.45`, highlighted `clearColor` (`:126,:128`) — the shadow is deleted
  on press rather than moved, which is why `reverseTitleShadow` stays false here.
- font `boldSystemFontOfSize:14`, `titleLabel.shadowOffset = (0, 1)`,
  `normalTitleShadowOffset = (0, 1)` (`:129-131`). Setting `normalTitleShadowOffset` while
  `reverseTitleShadow` is false is dead weight, kept presumably for symmetry.
- `adjustsImageWhenDisabled = false`, `exclusiveTouch = true` (`:132-133`).

Green variant, `TGButtonsMenuItemView.m:86-105`: `GroupedActionButtonGreen(.png|_Highlighted.png)`,
title white in both states, shadow `0x124606 @ 0.3` in both states, font `boldSystemFontOfSize:16`,
`shadowOffset = (0, -1)` with `normalTitleShadowOffset = (0, -1)` and `reverseTitleShadow = false`
(`:100-104`). Note the green button is a point larger and its shadow points *up* — the green plate is
darker so the title's shadow reads as an emboss above the glyphs.

Disabled state is not a control state here: a disabled entry gets `alpha = 0.7` plus `enabled = NO`
(`TGButtonsMenuItemView.m:83-84`), i.e. the whole plate fades, artwork included.

Layout, `TGButtonsMenuItemView.m:140-153`: two visible buttons split the content width as
`floorf((contentWidth - 10) / 2)`, left flush left, right flush right — so the 10pt gutter absorbs the
rounding and the two buttons are always equal width. One visible button spans the full content width.
Heights come from the PNG and never change. Long titles therefore truncate inside a fixed-width plate;
nothing wraps and nothing grows.

### 3.2 Country selector — the one true subview-propagation case

`TGLoginPhoneController.m:164-186`:

- background `LoginCountry.png` / `LoginCountry_Highlighted.png`, stretched with
  `leftCapWidth = width - 16` (`:166-167`) — i.e. the *right* 16pt is the fixed cap (where the chevron
  sits) and everything left of it stretches. This is the opposite of the usual `width/2` convention
  and is the reason the chevron area never distorts.
- font `boldSystemFontOfSize:` `16.5` on retina, `16` otherwise (`:168`). The half-point is the
  standard 2013 retina-only nudge (`TGIsRetina()`), also seen in the wallpaper panel as
  `16 + retinaPixel` (`TGWallpaperPreviewController.m:143,151`).
- left-aligned title and content (`:169-170`).
- title colour normal `0xf0f0f0`, shadow `0x17191d`; highlighted white with `clearColor` shadow
  (`:171-174`), `shadowOffset = (0, 1)` (`:175`).
- `titleEdgeInsets = UIEdgeInsetsMake(0, 14, 9, 14)` (`:176`) — 14pt side padding, and a 9pt *bottom*
  inset that pushes the baseline up because the PNG has a shadow lip at its bottom edge. Right inset
  14 keeps a long country name off the chevron.
- the chevron, `:183-186`: `TGHighlightImageView`-free plain `UIImageView` created with
  `initWithImage:@"LoginCountryArrow.png" highlightedImage:@"LoginCountryArrow_Highlighted.png"`,
  `autoresizingMask = FlexibleLeftMargin`, positioned at
  `x = buttonWidth - arrowWidth - 15`, `y = 16`, and added as a **direct** subview of the button.

This is the whole justification for the class: pressing the row must swap the chevron to its
highlighted asset in the same frame as the plate. Because the arrow is pinned by a flexible left
margin it survives the button being resized to the screen width later.

`exclusiveTouch = true` (`:165`) — pressing the country row cannot co-fire with the phone field.

### 3.3 Add-photo plates

`TGLoginProfileController.m:146-152`: frame is exactly the PNG size (`LoginAddPhoto.png`), highlighted
`LoginAddPhoto_Highlighted.png`, `exclusiveTouch = true`, no title at all. The labels
("Add", "Photo") are **siblings in the view hierarchy, not subviews of the button**
(`:172-181` build them and they are added to `self.view`), so the propagation loop never touches them —
the label pair does not change appearance on press, only the plate does.

`TGProfileController.m:741-756` and `TGTelegraphConversationProfileController.mm:458-468` are the same
construction with `ProfilePhotoPlaceholder.png` / `ProfilePhotoPlaceholder_Highlighted.png`, stretched
`width/2` horizontally, frame copied from `_avatarView.frame`, and inserted *below* the avatar view so
that once a real avatar exists the plate is hidden behind it rather than removed.

### 3.4 Wallpaper preview panel — the shadow-reversal case

`TGWallpaperPreviewController.m:144-170`. Two 131pt-wide buttons at `y = 26`, insets 17pt from each
panel edge; heights from the PNGs.

- Cancel: `WallpaperBlueButton`-family cancel art stretched `width/2`, highlighted
  `WallpaperGrayButton_Highlighted.png`; white title, black title shadow normal, `0x085cc4` shadow
  highlighted, `shadowOffset = (0, -1)`; **`reverseTitleShadow` left false**.
- Set: `WallpaperGrayButton.png` normal / `WallpaperGrayButton_Highlighted.png` highlighted,
  `reverseTitleShadow = true` and `normalTitleShadowOffset = (0, 1)` (`:159-160`), title black normal /
  white highlighted / `black @ 0.5` disabled (`:165-167`), title shadow `white @ 0.3` normal and
  `0x085cc4` highlighted (`:168-169`).

So: the light grey Set plate has a *white* shadow **under** black text when raised (a bevel), and on
press the plate turns blue, the text turns white, and the now-blue shadow moves **above** the text.
That flip is exactly `reverseTitleShadow`, and Set is the only place in the whole app that uses it.
It also demonstrates the intended pairing: `titleLabel.shadowOffset` and `normalTitleShadowOffset` are
set to the same value (`:160` and `:164`), because the class only takes over the offset once the first
highlight transition happens.

## 4. Our port — findings

We have **no `TGHighlightableButton` equivalent at all**. `grep -rl Highlightable src` returns only
`src/TGHighlightTriggerLabel.{h,m}`, which is a faithful (comment-stripped) copy of the original's
`TelegraphKit/TelegraphKit/TGHighlightTriggerLabel.{h,m}` — a different component (a label that pushes
its highlight *outward* to a list of targets) and, per grep, currently referenced by nothing in our
tree. It is dead code, not a substitute.

### 4.1 Defect: the login country chevron never highlights

`src/TGLoginViewController.m:472-505` reproduces `TGLoginPhoneController.m:164-186` line for line —
same `width - 16` cap (`:483` vs original `:167`), same `0xf0f0f0`/`0x17191d` colours (`:487-490`),
same `titleEdgeInsets (0, 14, 9, 14)` (`:492`), same arrow asset pair with
`initWithImage:highlightedImage:` (`:499`) — **except** the button is created as
`[UIButton buttonWithType:UIButtonTypeCustom]` (`src/TGLoginViewController.m:477`) instead of
`TGHighlightableButton`.

Consequence, visible to a user: press the country row and the plate swaps to
`LoginCountry_Highlighted.png` while `LoginCountryArrow.png` stays in its normal (dark) form.
`LoginCountryArrow_Highlighted.png` is loaded and handed to the image view, then never shown, because
nobody sets `arrowView.highlighted`. This is precisely the bug the class was written to prevent
(`TGHighlightableButton.m:10-16`).

Also, we hardcode the button width as 290 in two places (`:479` and the arrow's `x` at `:501`) where
the original derives the arrow's x from `_countryButton.frame.size.width`
(`TGLoginPhoneController.m:185`). With `autoresizingMask = FlexibleLeftMargin` set (`:500`) the arrow
still floats correctly if the frame changes later, so this is a latent fragility rather than a visible
defect today — but if any layout pass sets a width other than 290 before the mask takes effect, the
chevron starts off misplaced.

**Fix**: add `TGHighlightableButton` (24 lines, copy the semantics of `.m:8-22` exactly, including
running the subview loop *before* `super`), and use it for the country button.

### 4.2 Grouped action buttons — correct in appearance, wrong in class

`src/TGProfileViewController.m:250-267` (`-[TGProfileButtonsCell makeButton]`) matches
`TGButtonsMenuItemView.m:114-133` on every value I checked: `GroupedActionButton.png` /
`GroupedActionButton_Highlighted.png` stretched `width/2` with `topCapHeight:0`
(`src/TGProfileViewController.m:242-246`), title `0x4a6587` normal / white highlighted, title shadow
`white @ 0.45` normal / clear highlighted, `boldSystemFontOfSize:14`, `shadowOffset = (0, 1)`,
`adjustsImageWhenDisabled = NO`, `exclusiveTouch = YES`.

Because this button has no self-added subviews and `reverseTitleShadow` is false in the original, a
plain `UIButton` here is behaviourally identical. It is right; leave it. The only thing we lose is the
class as a shared vocabulary — if anyone later drops a badge image view onto one of these plates it
will silently fail to highlight.

### 4.3 Not applicable in our port

- No wallpaper preview screen exists (`grep -rli "wallpaperpreview\|WallpaperGrayButton" src` is
  empty), so `reverseTitleShadow` has no consumer today. Implement the property anyway when adding the
  class — it is two lines and it is the only correct way to build the Set button later.
- `ProfilePhotoPlaceholder` / `LoginAddPhoto` artwork is not referenced anywhere in `src`, so the
  add-photo plates are either absent or built differently; nothing to compare.
- `src/TGActionsMenu.m:80-85`, `src/TGPopupMenu.m:73+`, `src/TGStickerPanelView.m:79+` each hand-roll a
  `setHighlighted:` override that pushes the flag to their own named nine-slice pieces. That is a
  legitimate different pattern (explicit, typed targets rather than a `subviews` sweep) and is closer
  to the original's `TGHighlightTriggerLabel`/`TGHighlightImageView` pair than to
  `TGHighlightableButton`. No change needed, but note they duplicate three times what one small class
  would cover.

## 5. What became of it

### 5.1 `twelve` (later Objective-C fork, same lineage)

`/Users/alexanderhavrysh/Git/iOS/twelve/legacy/TelegraphKit/TGHighlightableButton.{h,m}` is the same
class with exactly one addition (diff against the original):

```objc
@property (nonatomic, strong) UIColor *normalBackgroundColor;      // .h:16
@property (nonatomic, strong) UIColor *highlightedBackgroundColor; // .h:17
...
if (_normalBackgroundColor != nil && _highlightedBackgroundColor != nil)
    self.backgroundColor = highlighted ? _highlightedBackgroundColor : _normalBackgroundColor;   // .m:18-19
```

That is the flat-design era arriving: a pressed state expressed as a solid colour swap instead of a
second PNG. The guard requires *both* colours to be non-nil, so existing PNG-based call sites are
untouched. New call sites appeared too — `Telegraph/TGContactsController.mm` and
`Telegraph/TGShareTargetController.m` join the original six. The change is feature-forced (new screens
with no bevelled artwork), not taste-driven; the original two behaviours survive unchanged.

Alongside it, `twelve` carries `submodules/LegacyComponents/LegacyComponents/TGModernButton.{h,m}`,
which is the actual successor. It abandons the subview sweep entirely and instead composes a
`_highlightImageView` or `_highlightBackgroundView` inserted into the button
(`TGModernButton.m:74-113`), cross-fading it over **0.2s** on press
(`TGModernButton.m:158-193`), with a default fallback of `alpha = 0.4` when highlighted and `1.0`
otherwise (`TGModernButton.m:196`). It also adds `extendedEdgeInsets` with a custom `hitTest:`
(`TGModernButton.m:30-43`) — the "tap targets are too small" problem — and a
`highlitedChanged` block instead of subclass overrides. It only animates when the transition came from
a real touch (`_animateHighlight` set around `touchesMoved/Ended/Cancelled`,
`TGModernButton.m:52-71`), so programmatic state changes still snap.

### 5.2 Modern Telegram-iOS

`submodules/Display/Source/HighlightableButton.swift:5-27`:

```swift
open class HighlightableButton: HighlightTrackingButton {
    self.adjustsImageWhenHighlighted = false
    self.adjustsImageWhenDisabled = false
    self.internalHighligthedChanged = { highlighted in
        if highlighted { alpha = 0.4 }            // instant on press
        else { alpha = 1.0; animateAlpha(from: 0.4, to: 1.0, duration: 0.2) }
    }
}
```

with `HighlightableButtonNode` (`:87-99`) doing the same for AsyncDisplayKit.

The concept did survive thirteen years, but inverted. In 2013 "highlighted" meant *swap to a second
piece of artwork, instantly, including the artwork your children are drawn from*. Today it means
*fade the whole button to 40% opacity, instantly down and animated back up over 0.2s* — one uniform
gesture, no per-child work needed, because a flat button has nothing whose pressed form differs in
kind. The asymmetric timing (snap in, fade out) is the one piece of craft carried forward from
`TGModernButton`.

What that means for us: **do not import the modern behaviour.** Our design language is the 2013 one,
where the pressed plate is a separate PNG and every glyph on it has a pressed twin. The 0.4-alpha fade
would flatten exactly the detail we are trying to reproduce. Port `TGHighlightableButton` as written in
2013, verbatim.

## 6. Open questions

- Our `src/TGHighlightTriggerLabel.{h,m}` has no callers. Was it ported speculatively, or did a screen
  that used it get rewritten? Worth deciding whether to keep it or delete it.
- The original sets `normalTitleShadowOffset` on the non-green grouped button
  (`TGButtonsMenuItemView.m:131`) while `reverseTitleShadow` is false, so the value is inert. I read
  this as leftover symmetry rather than intent, but I cannot prove it from the source.
- Whether we ever want `twelve`'s `normalBackgroundColor`/`highlightedBackgroundColor` extension
  depends on whether any of our new-feature screens (calls, stickers, QR) end up with colour-only
  buttons. Today they all use PNGs, so I would leave it out.

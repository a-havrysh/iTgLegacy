# TGButtonMenuItemCell

Original: `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGButtonMenuItemCell.h` / `.m`
Model object: `Telegraph/Telegraph/TGButtonMenuItem.h` / `.m`
(Telegram for iOS v1.1, header copyright "Peter Iakovlev, 2013".)

All line citations below are to those files unless another path is named.

---

## 1. What it is for

It is the row that is not a row. Everywhere else in the 2013 settings/profile tables a cell is a
plate with a label on it; `TGButtonMenuItemCell` is a table cell whose only job is to host one
free-standing **rounded push-button** floating on the grouped-table background, with the cell's own
chrome deliberately erased. It is the "Log Out", "Reset All Notifications", "Delete Contact",
"Set Profile Photo" and (dead-coded) "Start Encrypted Chat" control.

It is part of the `TGMenuItem` data-driven table system: a controller builds `TGMenuSection`s of
`TGMenuItem` subclasses, and `cellForRowAtIndexPath:` switches on `item.type`. The button's type
constant is `TGButtonMenuItemType == 0x8D6839FC` (`TGButtonMenuItem.h:11`).

Three visual subtypes exist (`TGButtonMenuItem.h:13-17`):

```
TGButtonMenuItemSubtypeRedButton   = 0   destructive
TGButtonMenuItemSubtypeGrayButton  = 1   neutral / additive
TGButtonMenuItemSubtypeGreenButton = 2   affirmative (secret chat)
```

## 2. Public surface

Cell (`TGButtonMenuItemCell.h:15-28`):

- `watcherHandle` (`ASHandle`) — the ActionStage back-channel to the controller (line 17).
- `itemId` (`id`) — in practice the `TGButtonMenuItem` itself is stored here (line 18; set at
  `TGProfileController.m:2481`, `TGChatSettingsController.m:356`).
- `-setTitle:`, `-setSubtype:`, `-setEnabled:`, `-setTitleIcon:` (lines 20-23).
- `-updateFrame` (line 25) — the sticky-to-bottom repositioning, section 7.
- `-setContentHidden:` (line 27) — hides the button while the cell stays in the table.

Model (`TGButtonMenuItem.h:21-27`): `title`, `subtype`, `action` (a bare `SEL`), `enabled`
(defaults `true`, `TGButtonMenuItem.m:15` and `:27`), `titleIcon`.

Note the header declares `-setTitle:` as a method, not a property, yet every call site writes
`buttonItemCell.title = buttonItem.title;` (`TGProfileController.m:2482`,
`TGNotificationSettingsController.m:438`, `TGChatSettingsController.m:357`). Dot syntax resolves to
the setter, so this compiles and works — but there is no getter. Do not assume the cell can be read
back.

## 3. Geometry

- **Row height: 45 pt.** Stated by each host controller's `heightForRowAtIndexPath:`, not by the
  cell: `TGNotificationSettingsController.m:349-350`, `TGChatSettingsController.m:268-269`,
  `TGProfileController.m:2316-2321`.
- **Button frame: `CGRectMake(9, 0, width - 18, 45)`** (`TGButtonMenuItemCell.m:29`), i.e. a 9 pt
  inset on both sides and the button fills the row's full height with no vertical padding. The
  autoresizing mask is `UIViewAutoresizingFlexibleWidth` (line 31), so rotation and the iPhone
  5 width change are handled without a layout pass.
- The button is added to **`self`, not `self.contentView`** (line 32). That is deliberate: the cell
  turns off clipping on both itself and the contentView's superview (lines 26-27) so `updateFrame`
  can push the button *outside* the 45 pt row and it still draws.
- **Font: `boldSystemFontOfSize:17`** (line 34) — Helvetica Neue Bold 17 on iOS 6. The 45 pt row is
  sized around that: 45 = a 17 pt bold cap line comfortably centred in an artwork plate that is
  itself 45 pt tall (see section 4). All three subtypes share the font; nothing scales it.
- `exclusiveTouch = true` (line 35): two buttons in the same table cannot be pressed at once.

**Long titles.** Nothing clever happens. It is a plain `UIButton` with a single-line `titleLabel`
and no `adjustsFontSizeToFitWidth`, so a title wider than `width - 18` is truncated with a tail
ellipsis and stays centred. The original never mitigated this; the localized strings were simply
kept short. **Empty/nil title**: the plate still draws at full size with no text — the button is not
hidden. `-setTitle:` does no nil check (line 42-45).

## 4. Artwork

| Subtype | Normal | Highlighted | Asset px (@2x) | Resolver |
|---|---|---|---|---|
| Red | `MenuRedButton.png` | `MenuRedButton_Highlighted.png` | 50×90 → **25×45 pt** | `TGInterfaceAssets.mm:835-849` |
| Gray | `MenuGrayButton.png` | `MenuGrayButton_Highlighted.png` | 52×90 → **26×45 pt** | `TGInterfaceAssets.mm:851-865` |
| Green | `GroupedActionButtonGreen.png` | `GroupedActionButtonGreen_Highlighted.png` | 66×86 → **33×43 pt** | inlined, `TGButtonMenuItemCell.m:100-111` |

Red and gray go through the `TGStretchableImageInCenterWithName` macro
(`TGInterfaceAssets.mm:14`), which is

```
stretchableImageWithLeftCapWidth:(int)(w/2) topCapHeight:(int)(h/2)
```

— **centre-stretched in both axes**. Their artwork is 45 pt tall, exactly the button height, so the
vertical stretch is a no-op in practice; the important part is that the caps preserve the rounded
corners and the top-to-bottom gradient if the height ever changes.

Green is different and is worth noting because it is easy to copy wrong: it is stretched with
`topCapHeight:0` (`TGButtonMenuItemCell.m:109-110`), i.e. **horizontally only**, and its source art
is 43 pt tall, so it is *vertically squashed/stretched into 45 pt*. That is the original's own
inconsistency (the green plate is the shared `GroupedActionButton` family used by 43 pt rows
elsewhere), not a nicety. The green images are cached in a `dispatch_once` static
(lines 103-111); red/gray are cached in `TGInterfaceAssets` statics.

Neither `adjustsImageWhenHighlighted` nor a tint is used — highlight is entirely a second
background image. `adjustsImageWhenDisabled = false` (line 30); disabled is expressed by alpha only
(section 6).

## 5. Colours (all with citations)

Red (`TGButtonMenuItemCell.m:72-82`):
- title `#ffffff` normal and highlighted (lines 77-78)
- title shadow `#a10603` at alpha `0.5` (lines 79-80), offset `(0, -1)` — an *inset* shadow,
  reading as engraved text on the red plate (line 81).

Gray (`TGButtonMenuItemCell.m:83-97`):
- title `#4a6587` normal (line 92) — the desaturated Telegram blue-gray of 2013 — and
  `whiteColor` when highlighted (line 93).
- title shadow `#ffffff` at alpha `0.45` normal, `clearColor` highlighted (lines 94-95), offset
  `(0, +1)`: a *raised* letterpress highlight below the glyphs, the standard iOS 6 light-button
  treatment. The highlight shadow is cleared so the pressed (dark) state has flat white text.
- Gray also resets `_button.frame.origin.y = 0` (lines 85-87). Gray buttons never participate in
  the sticky-bottom logic, so this undoes any offset left on a recycled cell that had previously
  been red or green.

Green (`TGButtonMenuItemCell.m:98-121`):
- title `whiteColor` in both states (lines 116-117)
- title shadow `#124606` at alpha `0.3`, offset `(0, -1)` (lines 118-120).

The cell itself: `backgroundColor = nil`, `opaque = false` (lines 23-24). The host controllers
additionally install empty `UIImageView`s as `backgroundView`/`selectedBackgroundView` and set a
local `clearBackground = true` flag (`TGProfileController.m:2456-2460` and `:2489`;
`TGChatSettingsController.m:346-350`; `TGNotificationSettingsController.m:427-431`) so the grouped
table draws no plate and no separator behind the row. `TGProfileController.m:2455` also sets
`selectionStyle = UITableViewCellSelectionStyleNone` — the other two controllers do not, which is
harmless only because the row is never selectable (below).

## 6. States and behaviour

**Tap.** The button's own `UIControlEventTouchUpInside` calls `-buttonPressed`
(`TGButtonMenuItemCell.m:37, 130-137`), which posts through ActionStage:

```
[watcher actionStageActionRequested:@"buttonItemPressed" options:@{@"itemId": _itemId}]
```

The controller receives it, pulls the `TGButtonMenuItem` back out of `itemId`, and
`performSelector:`s the item's `action` on itself (`TGProfileController.m:4263-4276`,
`TGNotificationSettingsController.m:772-785`, `TGChatSettingsController.m:559-572`). Nothing fires
if `itemId` is nil or the watcher does not respond (line 133) — that is the whole "unbound cell"
guard.

**The row is never a table selection.** `TGProfileController.m:2306-2312` returns `false` from
`shouldShowMenuForRowAtIndexPath:`-style handling for `TGButtonMenuItemType`, and no controller
implements a `didSelectRow` branch for it. All interaction is the `UIButton`'s.

**Hit testing.** `-hitTest:withEvent:` (lines 139-150) is overridden so that touches landing inside
the button's frame are routed into the button *in the button's own coordinate space*, before
`super`. This exists because `updateFrame` can move the button outside the cell's bounds, where
UIKit's normal hit test would never reach it. Note the coordinate translation on line 144 subtracts
only the frame origin — correct here because the button has an identity transform and zero bounds
origin.

**Enabled.** `-setEnabled:` (lines 124-128) sets `_button.enabled` and `alpha = enabled ? 1.0 :
0.7`. There is no separate disabled artwork or text colour, which is why
`adjustsImageWhenDisabled` is switched off. Live example: while a profile photo is uploading,
`TGProfileController.m:960-971` flips the item's `enabled` and pushes it into the visible cell
directly, without reloading the row.

**Content hidden.** `-setContentHidden:` (lines 152-155) just hides the button. Used for the
secret-chat row: when an encrypted conversation already exists, the profile keeps the row in the
model but collapses it to **1 pt tall** (`TGProfileController.m:2318-2320`) and hides the button
(`:2477-2478`). So "no button" is expressed as a 1 pt invisible row, not as a removed row.

**Reuse.** The cell is dequeued under the identifier `@"BI"` (all three controllers). `setSubtype:`
is called on every configure pass, so colours/artwork are always rewritten — but note that
`setSubtype:` **only sets what its own branch sets**. A red cell recycled as green keeps nothing
stale because all three branches write both background images, both title colours, both shadow
colours and the shadow offset. The one asymmetry is `_button.frame.origin.y`, which only the gray
branch resets (lines 85-87); red and green rely on `updateFrame` to recompute it. `setTitleIcon:`
hides rather than releases the icon view when passed nil (lines 62-65), so recycling is safe, but
only `TGProfileController.m:2483` ever calls it — the other two controllers leave a recycled cell's
icon in whatever state it was, which is safe only because they never set one.

## 7. `updateFrame` — the sticky-to-bottom trick

This is the part nobody guesses from a screenshot. For **red and green** subtypes only
(`TGButtonMenuItemCell.m:159`), if the cell's superview is a `UIScrollView` (the table), the button
is repositioned to sit at the **bottom of the visible scroll area** rather than at the top of its
own row:

```
buttonFrame.origin.y = MAX(0, visibleHeight - buttonHeight - self.frame.origin.y
                              - contentInset.bottom - contentInset.top)      (line 178)
```

Because clipping is disabled (lines 26-27) and hit testing is overridden (line 139), the button can
render and be tapped far below its 45 pt row. The effect: on a short profile or settings page the
destructive button is pinned to the bottom of the screen; once the content is long enough to fill
the screen, `MAX(0, …)` clamps it back to its natural place in the list.

Lines 166-175 are a correction for the in-call/status-bar-expanded states: it detects a scroll view
whose height matches "screen minus 20 minus 32" (the compact landscape nav bar) or the other
permutations and substitutes the height the view is *about to have*, so the button does not jump
during a rotation or nav-bar height change. This is hard-coded arithmetic against
`[TGViewController screenSizeForInterfaceOrientation:UIInterfaceOrientationPortrait]` — pure 2013
pre-Auto-Layout survival code.

The controllers must drive it. `updateFrame` is called from `willDisplayCell:`
(`TGProfileController.m:3538-3543`), from `controllerInsetUpdated:` for all visible cells
(`:2664-2672`), and after the header expands/collapses, where it also removes any in-flight
`"position"` animation from the cell's layer and presentation layer first so the button does not
lag behind (`:1533-1558`). There is even a `[cell setFrame:cell.frame]` no-op kick after keyboard
dismissal (`:3540` region, `TGProfileController.m:3538-3546`).

## 8. Where it is used

- `TGProfileController.m:1806-1809` — "Set Profile Photo", **gray**, own single-item section at the
  top of the self profile.
- `TGProfileController.m:1865-1867` — "Log Out", **red**, in `_logoutSection`, which is only added
  to the section list while the table is editing (`:1861-1863`).
- `TGProfileController.m:2049-2051` — "Delete Contact", **red**.
- `TGProfileController.m:2053-2056` — "Start Encrypted Chat", **green**, with
  `titleIcon = GreenButtonLockIcon.png` — **and the line adding it to the section is commented out**
  (`:2057`). The green subtype is therefore dead in shipped 1.1; it is reachable only through the
  editing/non-editing swap at `:2470-2479`.
- `TGNotificationSettingsController.m:181-183` — "Reset All Notifications", **red**, followed by a
  `TGCommentMenuItem` explaining it.
- `TGChatSettingsController.m` — same shape via the shared `TGButtonMenuItemType` branch (`:338-362`).

The recurring composition is: **its own single-item section, red button, optional grey caption
comment underneath.** That is the 2013 idiom for a destructive action.

## 9. The title icon

`-setTitleIcon:` (lines 47-66) creates a `UIImageView` and adds it **as a subview of
`_button.titleLabel`**, at `CGRectMake(1, 3, icon.size.width, icon.size.height)`. Because the
titleLabel is centred and sized to the text, the icon rides along with the text and sits just left
of the first glyph, 3 pt down from the label's top. `GreenButtonLockIcon@2x.png` is 20×28 px =
10×14 pt, so it occupies y 3-17 inside a ~21 pt tall 17 pt-bold label.

Room for it is made by **prefixing the title string with four spaces**:
`[NSString stringWithFormat:@"    %@", TGLocalized(@"Profile.StartEncryptedChat")]`
(`TGProfileController.m:2053`). There is no measurement and no layout — four spaces of Helvetica
Neue Bold 17 happen to be about the icon's width. Any port that reflows this must reproduce both
halves or the icon will overlap the text.

---

## 10. Our port

We have **no equivalent class**. The component was dissolved into six independent inlined copies:

| Our site | Subtype | File |
|---|---|---|
| Profile "delete" cell (`TGProfileRedButtonCell`) | red | `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGProfileViewController.m:299-334` |
| Profile two-up buttons (`TGProfileButtonsCell`) | gray-ish | `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGProfileViewController.m:249-297` |
| Settings "Log Out" | red | `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGSettingsViewController.m:2846-2882` |
| Settings "Set Profile Photo" | gray | `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGSettingsViewController.m:2721-2757` |
| Storage "Clear everything" | red | `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGStorageViewController.m:898-940` |
| Sessions / Stickers / Call | red & green | `TGSessionsViewController.m:374-380`, `TGStickersViewController.m:2829-2841`, `TGCallViewController.m:155-165` |

The core numbers are right in most copies: frame `(9, 0, w-18, 45)`, `boldSystemFontOfSize:17`,
`#a10603` at 0.5 with offset `(0,-1)` for red, `#4a6587` + white-at-0.45 with offset `(0,+1)` for
gray, `adjustsImageWhenDisabled = NO`, `exclusiveTouch`, row height 45, cleared cell background.
Whoever ported those read the original closely. The defects are in the places where the copies
disagree with each other.

### Defects

1. **The gray subtype uses the wrong artwork.** The original gray is `MenuGrayButton.png`
   (`TGInterfaceAssets.mm:851-857`), a 26×45 pt centre-stretched plate. We do not ship that asset at
   all (`iTgLegacy/images/` contains only `MenuRedButton*`, `GroupedActionButton*`,
   `GroupedActionButtonGreen*`) and substitute `GroupedActionButton.png` — a 24×43 pt plate from the
   *other* button family — at `TGSettingsViewController.m:2738-2747` and
   `TGProfileViewController.m:253-255`. Fix: add `MenuGrayButton@2x.png` /
   `MenuGrayButton_Highlighted@2x.png` and use them for any full-width 45 pt gray button.

2. **Gray plate is stretched with the wrong caps and into the wrong height.** Ours uses
   `topCapHeight:0` on a 43 pt image inside a 45 pt button
   (`TGSettingsViewController.m:2740-2747`, `TGProfileViewController.m:242-246`), so the corner
   radius and the gradient are vertically smeared by 2 pt. The original's macro is
   `topCapHeight:(int)(h/2)` on a 45 pt image (`TGInterfaceAssets.mm:14`) — no distortion at all.

3. **Red plate stretch is inconsistent across our copies.** `TGStorageViewController.m:919-926` uses
   `topCapHeight:h/2` (matches the original macro). `TGSettingsViewController.m:2862-2870` and
   `TGProfileViewController.m:242-246` use `topCapHeight:0`. Same asset, two behaviours. Standardise
   on `h/2` per `TGInterfaceAssets.mm:14`.

4. **Settings "Log Out" has no highlighted title-shadow colour.** Only the normal state is set
   (`TGSettingsViewController.m:2857-2860`); the original sets both
   (`TGButtonMenuItemCell.m:79-80`). On press the engraved shadow disappears and the label visibly
   "flattens" for the duration of the touch. Storage gets this right
   (`TGStorageViewController.m:909-915`).

5. **No sticky-to-bottom behaviour anywhere.** `updateFrame` (`TGButtonMenuItemCell.m:157-182`) has
   no counterpart in our port; our red buttons always sit at the top of their own 45 pt row. On a
   short Settings or Profile page the original pinned "Log Out" / "Delete Contact" to the bottom of
   the visible area. This is the single largest visible difference, and it also implies the two
   supporting behaviours we lack: `clipsToBounds = false` on the cell and its contentView's
   superview (`:26-27`) and the `hitTest:` override (`:139-150`).

6. **Green subtype and title icon are unimplemented for this component.** We use
   `GroupedActionButtonGreen` in Stickers/Call/VideoCapture but never with the
   `TGButtonMenuItemCell` treatment: no `#124606`@0.3 shadow at offset `(0,-1)`
   (`TGButtonMenuItemCell.m:118-120`), no `GreenButtonLockIcon.png` (asset absent from
   `iTgLegacy/images/`), no four-space title prefix. If a "Start Secret Chat" button is ever added
   to the profile, reproduce all three or it will not match. Caveat: the original itself never
   showed this button (`TGProfileController.m:2057` is commented out), so it is low priority.

7. **`adjustsImageWhenHighlighted = NO` is set in our Settings copies**
   (`TGSettingsViewController.m:2727`, `:2853`) and not in the original. Harmless with a separate
   highlighted image, but it is noise that hides the fact that the two copies were written
   independently.

8. **Structural: there is no shared cell.** Six copies means six chances to drift, and they already
   have (items 2-4 are all drift, not misreading). If a future wave touches button styling, it must
   touch six files. Extracting a `TGButtonMenuItemCell` with `subtype`, `title`, `titleIcon`,
   `enabled` and `updateFrame` would collapse items 1-5 into one fix. This is a recommendation, not
   a visual defect.

Correct as-is and worth stating: the disabled treatment. `TGStorageViewController.m:936-937` does
`enabled` + `alpha 0.7`, exactly `TGButtonMenuItemCell.m:126-127`.

---

## 11. What became of it

### `twelve` (Objective-C fork, same lineage)

`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGButtonMenuItemCell.{h,m}` is **byte-for-byte the
2013 file except for two import paths** (`ASWatcher.h` and the removed `TGViewController.h` are now
reached through `submodules/LegacyComponents/`). No metric, colour, asset or behaviour changed. The
component was simply frozen; the fork even ships `MenuRedButton@2x.png` under
`Telegraph/Resources/ClassicIOS6/`, which tells you the whole look was quarantined as a legacy
theme rather than evolved. Useful conclusion for us: there is no later, better version of this
component in the Objective-C lineage to copy. The 2013 file is the last word.

### Modern Telegram-iOS

The descendant is `submodules/ItemListUI/Sources/Items/ItemListActionItem.swift`. The idea survived;
every part of the *appearance* was abandoned.

- The plate is gone entirely. `ItemListActionItem` is an ordinary list row — background, separators,
  a highlight node — with a coloured label. There is no button, no artwork, no letterpress shadow
  (the whole file contains no shadow or background-image code).
- The three hard-coded subtypes became a semantic enum, `ItemListActionKind` = `.generic /
  .destructive / .neutral / .disabled` (lines 8-13), resolved against the theme:
  `theme.list.itemDestructiveColor`, `itemAccentColor`, `itemPrimaryTextColor`,
  `itemDisabledTextColor` (lines 166-177). That is the forced change — theming (dark mode) makes a
  fixed `#a10603` shadow on a red bitmap impossible.
- Bold 17 became `Font.regular(itemListBaseFontSize)` (line 158) — regular weight, user-scalable.
  Dynamic Type is the second forcing function.
- The 45 pt fixed height became `titleHeight + verticalInset * 2`, with `verticalInset` 11.0 in the
  legacy style and 15.0 in the newer "glass" style (lines 184-192). Height now follows the text
  instead of the artwork.
- Long titles are explicitly handled: one line, `.end` truncation, constrained to
  `width - insets - 20` (line 179). The 2013 version left this to `UIButton`'s default.
- `alignment` (`.natural` / `.center`, lines 15-18, applied at lines 303-305) replaced what was
  implicitly always-centred.
- The sticky-to-bottom `updateFrame` hack has no descendant. Modern controllers put such buttons in
  a real footer or a separate section.

So: the *interaction* model is unchanged (a row that is really a single action, dispatched by a
closure now instead of a `SEL` through ActionStage), while the *visual* model was replaced wholesale
under pressure from theming and Dynamic Type. For our project that means the 2013 file is the design
authority, and the modern file is only useful as a checklist of the cases the original left
unhandled — truncation, alignment, and a real disabled colour rather than 0.7 alpha.

## 12. Genuinely ambiguous / unresolved

- `updateFrame`'s orientation-height fixups (`TGButtonMenuItemCell.m:166-175`) encode nav-bar
  heights of 44/32 and a 49 pt tab bar for a 3.5"/4" device with a 20 pt status bar. They are
  correct for the iPhone 4S in portrait, which is our only target, so a port can implement the
  simple `MAX(0, …)` clamp at line 178 and skip lines 166-175 — but note that doing so is a
  deliberate simplification, not a faithful copy.
- The green subtype's vertical squash (43 pt art into a 45 pt button, line 109 vs line 29) is
  visible in principle but was never shipped, so there is no screenshot to check it against. Treat
  it as "reproduce the code, not the intent".

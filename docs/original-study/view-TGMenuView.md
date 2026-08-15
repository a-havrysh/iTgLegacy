# TGMenuView — the black message context menu

Original: `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGMenuView.h`
(29 lines) and `.../TGMenuView.m` (635 lines). Artwork lives in
`.../Telegraph/Telegraph/Resources/Menu/` (15 PNGs, `@2x` only).
Only call site in the whole app: `TGConversationController.mm` (message long-press).

Our equivalent: `src/TGPopupMenu.{h,m}` (visual clone, extended), driven for messages by
`src/TGMessageActionsSheet.m` and `src/TGChatViewController.m:5905`.

---

## 1. What it is

A single horizontal strip of text buttons on a black glossy pill, with a small arrow tacked to the
top or bottom edge pointing at the thing you long-pressed. It is the 2013 answer to `UIMenuController`
(Copy / Delete / Select over a chat bubble) — the same shape, but drawn from Telegram's own artwork so
it could carry non-system verbs like `Select` and `Forward`.

Two classes ship together and are always used as a pair:

- `TGMenuView` — the pill itself. Knows buttons, arrow, layout, show/hide animation.
- `TGMenuContainerView` — a full-area transparent overlay that owns one `TGMenuView`, swallows the
  outside tap, and removes itself once the menu has faded (`TGMenuView.m:591-633`).

There is no delegate protocol. Actions are reported through the app's `ASWatcher` bus: the caller
hands over an `ASHandle` and gets `menuAction` (options = the action string) or `menuWillHide`
(options = nil) — `TGMenuView.m:559`, `TGMenuView.m:626`.

## 2. Public surface

```objc
- (void)setButtonsAndActions:(NSArray *)buttonsAndActions watcherHandle:(ASHandle *)watcherHandle;
```
`buttonsAndActions` is an array of `NSDictionary` with exactly two keys, `@"title"` and `@"action"`,
both `NSString` (`TGMenuView.m:186`, `TGMenuView.m:558`; built at `TGConversationController.mm:7391-7398`).
There is no icon, no colour, no enabled flag and no destructive style in the data model. Everything the
menu can express is a word.

`sizeToFit` (`TGMenuView.m:340`) must be called by the caller after `setButtonsAndActions:`, then
`-[TGMenuContainerView showMenuFromRect:]` in the container's own coordinates
(`TGConversationController.mm:7399-7401`).

`TGMenuContainerView.isShowingMenu` / `.showingMenuFromRect` exist so the controller can notice that the
anchor moved and kill the menu; see §7.

## 3. Metrics, every number

Row height is **41pt**, hard-coded three times: in the button's `sizeToFit` (`TGMenuView.m:116`), in the
menu's `sizeToFit` (`TGMenuView.m:350`), and as the literal `41 - 4` for the bottom hairline
(`TGMenuView.m:527`). It is not derived from the font; it is the height of the background artwork
(`MenuButtonCenter@2x.png` is 4×82px = 2×41pt).

Button width = `[title sizeWithFont:font].width + 34` (`TGMenuView.m:116`), i.e. 17pt of padding each
side, measured with **bold system 14** (`TGMenuView.m:204`). No maximum, no truncation, no ellipsis —
see §8 for what that means with a long word.

After `sizeToFit`, the first and the last button each get **+1pt** of width (`TGMenuView.m:243-248`),
which covers the 1pt the end-cap artwork loses to the rounded corner. Note the condition is a single
`if (index == 0 || index == count-1)`, so a **one-button menu gains 1pt in total, not 2**.

Menu width = plain sum of button widths (`TGMenuView.m:345-350`); buttons are laid out edge to edge from
x=0 with no gaps (`TGMenuView.m:455-465`).

Placement, in `showInView:fromRect:` (`TGMenuView.m:355-388`), all against the container's frame:

| what | value | line |
|---|---|---|
| horizontal | centred on the anchor rect, then clamped to a **4pt** margin on both sides | 361-365 |
| preferred vertical | `rect.origin.y - height - 14` (14pt above the anchor), arrow points **down** | 367, 381 |
| if that would put it above y=2 | `rect.origin.y + rect.size.height + 17` (17pt below), arrow points **up** | 369-370, 377 |
| if that overflows the bottom (`> height - 14`) | vertically centred in the container, arrow **down** anyway | 371-375 |

The asymmetry (14 above vs 17 below) is not a typo: the bottom arrow art is taller than the top one
(14.5pt vs 12pt, §4), so the tip lands the same distance from the bubble either way.

`_arrowLocation` is the anchor's horizontal centre expressed in menu coordinates
(`TGMenuView.m:384`), and it drives both the arrow's x and the layer anchor point:
`CGPointMake(clamp01(_arrowLocation / width), _arrowOnTop ? -0.2f : 1.2f)` (`TGMenuView.m:386`). That
0.2 overshoot outside the layer is what makes the pop-open animation look like it is growing *out of*
the bubble rather than out of its own edge. Default `_arrowLocation` before any placement is 50
(`TGMenuView.m:170`).

Arrow y: top arrow at **-9**, bottom arrow at **37** (`TGMenuView.m:508-509`) — both deliberately
overhang the 41pt pill. Arrow x is `floor(_arrowLocation - arrowWidth/2)` clamped into the hosting
button, with 10pt kept clear of a rounded end (`TGMenuView.m:502-506`).

Separators sit at `buttonX - 1, y=2, height 36` (`TGMenuView.m:478`) — 2.5pt of pill visible above and
below, so the divider never touches the top/bottom hairlines.

Top/bottom hairlines are inset by **10pt** at the rounded ends (`TGMenuView.m:483-497`) so they stop
before the corner curve.

## 4. Artwork

All fifteen files are `@2x` only — on a non-Retina device the menu would fall back to nothing, which is
fine because the 4S is Retina. Point sizes below are px/2.

| file | px | pt | how used |
|---|---|---|---|
| `MenuButtonLeft.png` | 20×82 | 10×41 | first button's left cap, stretched with `leftCapWidth = width-1` = 9 (`TGMenuView.m:296`) |
| `MenuButtonRight.png` | 20×82 | 10×41 | last button's right cap, `leftCapWidth = 0` (`TGMenuView.m:297`) |
| `MenuButtonCenter.png` | 4×82 | 2×41 | body fill, `leftCapWidth = width/2` = 1 (`TGMenuView.m:299`) |
| `MenuButtonSeparator.png` | 4×72 | 2×36 | vertical divider, drawn at natural size |
| `MenuButtonTopLine.png` | 4×6 | 2×3 | top gloss hairline, stretched horizontally by frame width |
| `MenuButtonBottomLine.png` | 2×8 | 1×4 | bottom hairline |
| `MenuArrowTop.png` | 40×24 | 20×12 | arrow when the menu is *below* the bubble |
| `MenuArrowBottom.png` | 40×29 | 20×14.5 | arrow when the menu is *above* the bubble |
| the six `_Highlighted` variants | — | — | assigned as `highlightedImage`, swapped by UIKit state |

Every button carries three background image views (`leftView`, `centerView`, `rightView`) even when it
is a middle button; in that case all three get the *centre* image (`TGMenuView.m:312-314`), so the
"left cap" of an interior button is just 2pt of fill. This is why highlighting works per-button with no
clipping: the pill is nine image views wide for a three-button menu, not one stretched image.

`MenuRedButton*.png` and `MenuDisclosureIndicator*.png` also exist under `Resources/`, but they belong
to profile/settings buttons, **not** to this menu. There is no destructive red in the 2013 context menu.

## 5. Colour and type

- Title font: `[UIFont boldSystemFontOfSize:14]` (`TGMenuView.m:204`).
- Title normal: pure white (`TGMenuView.m:197`).
- Title disabled: white at 50% (`TGMenuView.m:198`) — never actually reachable, nothing sets `enabled`.
- Title shadow normal: `#000000` at 80%, offset `(0, -1)` (`TGMenuView.m:199`, `:203`).
- Title shadow when highlighted or selected: `#186bcb` at 60% (`TGMenuView.m:200-202`). The blue is the
  pressed-state gloss showing through the letterforms — the only chromatic accent in the whole component.
- Title inset: +2pt on the leading side for the first button, +2pt trailing for the last
  (`TGMenuView.m:326`, `:333`), balancing the wider end caps.

## 6. States and behaviour

**Highlight.** `TGMenuButtonView` overrides both `setHighlighted:` and `setSelected:` and propagates
`highlighted || selected` to all seven image views (`TGMenuView.m:74-112`), then tells the menu via the
`TGMenuButtonViewDelegate` callback. The menu walks the buttons, finds the first highlighted one, and
highlights the arrow **only if that button is the one the arrow is attached to**
(`TGMenuView.m:256-291`). So pressing the button above the arrow lights the arrow too, and the pill
reads as one continuous surface; pressing any other button leaves the arrow dark.

**Hairline splitting around the arrow.** When the arrow is on top, the button that hosts it draws its
top hairline as two segments with a gap the width of the arrow (`TGMenuView.m:519-522`), and mirrored on
the bottom when the arrow is below (`:532-535`). That is the whole reason each button owns *two* top and
*two* bottom line views. When the arrow is on the other edge, the second segment is given zero width
rather than being hidden (`:515`, `:528`).

**Tap.** `buttonPressed:` sets `selected = true` on the tapped button (so it stays lit through the fade),
fires `menuAction` with the action string, and asks the container to hide (`TGMenuView.m:545-567`).

**Outside tap.** `TGMenuContainerView hitTest:` returns nil and hides the menu whenever the hit lands on
the container itself (`TGMenuView.m:591-602`) — no gesture recogniser, no dimming view.

**Show animation** (`TGMenuView.m:394-431`), an overshoot in three legs, with the layer rasterised for
the duration and un-rasterised at the end:
`0.142s ease-out → scale 1.07` → `0.08s → 0.967` → `0.06s ease-out → 1.0`. Alpha is snapped to 1
immediately (`:397`); the 0.04s animation block above it is empty dead code (`:399-402`).

**Hide** (`TGMenuView.m:434-449`): 0.2s alpha to 0, then transform reset to scale 0.1 so the next show
starts small again. The container removes itself in the completion (`:628-631`).

**Reuse.** `setButtonsAndActions:` reuses existing button views by index, creates only the shortfall, and
trims the surplus (`TGMenuView.m:190-220`); separators are grown/shrunk to `count-1` (`:222-235`).
`selected` is explicitly reset to false on every reused button (`:211`) — without that, a menu reopened
after a tap would come up with a stale lit row. Note that the container is created once per controller
and kept (`TGConversationController.mm:7382-7386`), so this reuse path is the normal path.

**Auto-dismiss.** `TGMenuContainerView setFrame:` hides the menu on any size change
(`TGMenuView.m:611-617`) — rotation, keyboard.

## 7. How the conversation controller uses it

Worth reading as part of the component, because half its correctness lives here.

- Menu items are chosen per message (`TGConversationController.mm:7391-7398`): `Copy` if the message has
  text; otherwise `Forward` if it is not a service message and not a secret chat; always `Delete`;
  `Select` unless it is a service message. So it is two or three buttons, never more.
- The anchor is `[messageView contentFrameInView:self.view]` **intersected with the area above the input
  bar** (`:7368-7372`); if the intersection is empty the menu is not shown at all.
- The container's frame excludes the navigation inset and stops at the table's bottom
  (`:7388`), so the pill can never be drawn over the nav bar or the input panel.
- The bubble is marked `setIsContextSelected:true` while the menu is open (`:7376`) and cleared on
  `menuWillHide` (`:7472-7479`).
- On every table update, the controller recomputes the anchor rect and hides the menu if it no longer
  equals `showingMenuFromRect` (`:6606-6635`) — this is what makes the menu disappear when the list
  scrolls or a new message arrives.
- Reopen is suppressed for **0.4s** after a hide (`:7349`), and a background tap is ignored for **0.32s**
  after a hide (`:3844`), so the tap that dismissed the menu does not also do something else.

## 8. Edge cases

- **Long title.** Nothing truncates. A very wide menu is centred, then pushed left until its right edge
  is 4pt from the container edge (`TGMenuView.m:364-365`); if it is wider than the container, `origin.x`
  goes negative and the menu simply hangs off the left. In practice the titles are literals of ≤7
  characters, so this never fired.
- **No room above or below.** The pill is centred vertically and `_arrowOnTop = false`
  (`TGMenuView.m:373-374`), which means the downward arrow is drawn pointing at empty space. The original
  accepts that.
- **Empty array.** `setButtonsAndActions:` with zero entries leaves `index == -1`; the trim loop
  (`:214`) removes every button, `_separatorViews.count > _buttonViews.count - 1` compares against
  `NSUInteger` 0-1 and does not trim, and `sizeToFit` yields a zero-width menu. The caller never does
  this — `Delete` is unconditional (`TGConversationController.mm:7396`).
- **Single button.** Works; it is both first and last, gets both end caps and both title insets, and +1pt
  of width once.
- **Arrow off the end.** Clamped to 10pt from either rounded end (`TGMenuView.m:502-506`), so a menu
  shoved against the screen edge shows the arrow near, but not on, the corner.

---

## 9. Our port, judged

`src/TGPopupMenu.m` is a genuine port, not a lookalike: the artwork, the 41pt height, the +34 padding,
the 34/10/4/14/17 placement numbers, the `#186bcb` 60% pressed shadow, the three-leg overshoot
animation and the `-0.2/1.2` anchor point are all reproduced correctly (`TGPopupMenu.m:4-6`, `:287`,
`:293`, `:356-360`, `:443-465`, `:591-614`). It also fixes one latent bug: the original computed the
bottom hairline split from `_arrowTopView.frame.origin.x` and `bottomLeftView`'s width mixed together
(`TGMenuView.m:534`); ours uses the bottom arrow consistently (`TGPopupMenu.m:568`). Same result, since
both arrows share `arrowX`, but ours is the honest version.

The differences that a user can see:

1. **The anchor is a point, not the bubble.** `TGChatViewController.m:5918-5922` builds a zero-size rect
   60pt in from the bubble's leading/trailing edge and 8pt above the row bottom. The original centred the
   menu on the message's *content* frame (`TGConversationController.mm:7368`), so the pill sat over the
   middle of the bubble; ours sits over an arbitrary interior point and, for a narrow bubble, off to one
   side of it. Fix: pass the bubble's frame in host coordinates and let `positionCardFromRect:` do the
   centring it already implements.

2. **Nothing clips the menu to the message area.** The original's container stopped at the input panel
   and started below the nav bar (`TGConversationController.mm:7388`), and the anchor rect was
   intersected with that band (`:7370-7373`). Ours passes `self.view` whole
   (`TGChatViewController.m:5931`), so a menu opened on the bottom-most message can be laid over the
   input bar, and the "no room" fallback centres it vertically over the entire screen including the nav
   bar. Fix: host in a subview inset by the nav bar and the input container, exactly as the original did.

3. **The message is never marked as the menu's subject.** The original set
   `setIsContextSelected:true` on show and cleared it on `menuWillHide`
   (`TGConversationController.mm:7376`, `:7479`). Nothing in `TGChatViewController.m:5905-5936` or
   `TGMessageActionsSheet.m` does the equivalent, so with several bubbles on screen only the small arrow
   says which one you long-pressed.

4. **The menu does not die when the list moves.** The original re-derived the anchor on every table
   update and hid the menu the moment it moved (`TGConversationController.mm:6606-6635`). Ours only tears
   down on host bounds change, backgrounding and orientation (`TGPopupMenu.m:172-179`, `:224-229`), so an
   incoming message or a scroll leaves the pill floating over an unrelated bubble with its arrow pointing
   at the wrong thing. Fix: have the chat controller call `[TGPopupMenu dismiss]` from
   `scrollViewDidScroll:` and after any table reload while a menu is open.

5. **The header promises styling the view does not implement.** `TGPopupMenu.h:13-15` documents an
   `"icon"` key and a `"destructive"` flag that draws the row red, and `TGMessageActionsSheet.m:182-196`
   dutifully passes both (`icon:@"delete" ... destructive:YES`). `TGPopupMenu.m` reads neither — it only
   reads `title` and `enabled` (`:292`, `:405`). `Delete` therefore renders identically to `Copy`. The
   original had no red and no glyphs either (`TGMenuView.m:197`, and the data model has only
   title/action), so the right fix is to delete the promise from the header and the arguments from the
   callers, not to add red.

6. **A one-item menu is 1pt too wide.** Ours adds +1 for first-in-row and another +1 for last-in-row
   (`TGPopupMenu.m:315-318`); the original's single `if` adds +1 once for a lone button
   (`TGMenuView.m:243-248`). Cosmetic, but it also shifts the arrow's clamp range by half a point.

7. **Cancellation is discovered by polling.** `TGPopupMenu`'s `onChoice` block is simply never called
   when the user taps outside, so `TGMessageActionsSheet` re-schedules `checkMenuStillOpen` every 0.2s
   and infers dismissal from `menu.superview == nil` (`TGMessageActionsSheet.m:151-168`). The original
   had an explicit `menuWillHide` action (`TGMenuView.m:626`). This is a real design defect, not just
   ugliness: up to 200ms of lag before the chat controller learns the menu closed, and a fast
   dismiss-then-reopen can deliver the old sheet's `completion(nil)` after the new one is on screen. Fix:
   give `TGPopupMenu` a `onDismiss` block, called from `teardownAnimated:`.

8. **Reopen suppression is global.** `kMenuReopenSuppression = 0.4` (`TGPopupMenu.m:7`, `:156`) matches
   the original's number (`TGConversationController.mm:7349`), but the original applied it at the
   long-press site in the chat only, whereas ours silently drops *any* `showItems:` from any screen —
   chat list, profile, group members — within 0.4s of the last hide. Since `TGMessageActionsSheet` first
   awaits a TDLib `propertiesOfMessage` round trip before showing (`TGMessageActionsSheet.m:76-98`), the
   suppression window can also swallow a legitimate slow-arriving menu with no feedback at all.

9. **We wrap to multiple rows; the original never had a second row.** Ours splits the buttons across rows
   when they exceed the host width and pads each row to a common width
   (`TGPopupMenu.m:299-354`, `:414`). The original could not: it had at most three short verbs. With our
   message menu offering up to ten entries (Reply, Edit, Copy, Copy Link, Forward, Pin/Unpin, Translate,
   Delete, Select, Report — `TGMessageActionsSheet.m:203-257`), a real long-press produces a black slab
   three or four rows and 123–164pt tall, which is a shape the 2013 design language never contained. This
   is the one place where our port is visually unfaithful *by construction*, and it deserves a design
   decision rather than a patch — see §11.

Everything else — the hitTest dismissal, the button reuse of image views, the highlighted-arrow rule,
the hairline splitting, the separator at `x-1, y+2, h36` — matches. Our images directory carries all
fifteen assets at the original pixel dimensions (`images/Menu*@2x.png`), verified byte-size-wise
identical in geometry to `Resources/Menu/`.

## 10. What became of it

**Telegram-iOS (modern).** The class still exists, verbatim in lineage, as
`submodules/LegacyComponents/Sources/TGMenuView.m` (1014 lines), but it is no longer the message menu:
its only remaining users are the media picker and camera
(`TGMediaPickerGalleryPhotoItemView.m`, `TGMediaPickerGalleryVideoItemView.m`,
`TGMediaAssetsController.m`, `TGMediaPickerGalleryInterfaceView.m`, `TGCameraMainPhoneView.m`), where it
survives as the little black tooltip beside a photo. The message context menu became
`submodules/ContextUI/Sources/ContextController.swift` — a completely different idea: the pressed
message is lifted out of the list into a blurred, dimmed overlay, the actions are a *vertical* list, and
a reaction strip is added above it (`ContextControllerConfiguration.reactionItems`, line 525). That
change is forced, not cosmetic: a horizontal strip cannot hold ten verbs, and reactions need a row of
their own.

**twelve** (`submodules/LegacyComponents/LegacyComponents/TGMenuView.m`, also 1014 lines) shows the
intermediate step, and it is the most instructive of the three because it faced exactly our problem —
too many actions for one strip — and solved it differently. It keeps 41pt rows and all the artwork, and
adds:
- `maxWidth`, default 310pt (`:234`), and `sizeToFitToWidth:` which reserves 20pt (`:503-505`);
- **horizontal pagination** instead of row wrapping: buttons are packed into pages, and 32pt pager
  buttons (`pagerButtonWidth`, `:52`) are added at one or both ends of a page (`:598-606`), so the menu
  stays one row tall and you swipe/tap through it;
- `multiline` (`:317-321`), which lets a title wrap inside `maxWidth - 18` (`:172`) and grows the row
  height above 41 (`:595`);
- `optional` and `trailing` item flags (`:333-334`) — optional buttons are dropped when they do not fit
  and re-added only if the last page has room (`:524`, `:548-560`), trailing ones are forced to the end
  of their page (`:568-575`);
- `forceArrowOnTop`, `forceCenter`, `buttonHighlightDisabled`, an image-only button mode
  (`width = imageWidth + 24`, `:182`), and `showMenuFromRect:animated:`.

## 11. Open decision

Row-wrapping (ours) versus pagination (twelve) versus a vertical list (modern) is the one genuinely open
question here, and it is a design call, not a porting detail. Pagination keeps the 2013 silhouette exact
at the cost of hiding actions behind a chevron; wrapping shows everything but invents a shape that never
existed in 2013. If the answer is "keep the silhouette", twelve's `pagerButtonWidth = 32` layout is the
proven implementation to follow, and `TGPopupMenu.m:299-354` would be replaced rather than tuned.

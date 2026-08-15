# TGButtonsMenuItemView — the paired action-button row

Original: `Telegraph/Telegraph/TGButtonsMenuItemView.{h,m}` in
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`.
Model object: `TGButtonsMenuItem.{h,m}` in the same directory.
The class exists under the exact requested name; nothing had to be substituted. It lives in
`Telegraph/Telegraph`, not in `TelegraphKit` — only its button superclass
(`TelegraphKit/TelegraphKit/TGHighlightableButton.m`) is in the kit.

All line numbers below are 1-based lines of the file named next to them.

---

## 1. What it is for

A single grouped-table row that carries **one or two pill-shaped action buttons side by side**,
edge to edge with the grouped card, with no card chrome of its own. It is the "Send Message /
Add Contact" pair at the top of a user profile, and the "Add Member / Leave Group" pair at the
top of a group profile. It is not a selectable row: it is a row-shaped container for buttons,
and the table treats it as inert (`TGProfileController.m:2786-2790` returns `false` from the
"can perform action" switch for `TGButtonsMenuItemType`).

Its two call sites, and the only two in the app:

- `TGProfileController.m:1937` creates `_actionButtons` (tag `TGActionButtonsTag`) inside
  `_actionsSection`; the contents are rebuilt in `-updateActions:`
  (`TGProfileController.m:1047-1078`).
- `TGTelegraphConversationProfileController.mm:253-262` builds a fixed two-button item in
  `_buttonsSection` at controller-init time.

The model class is deliberately empty: `TGButtonsMenuItem` is a `TGMenuItem` with type constant
`0x415CD6D3` (`TGButtonsMenuItem.h:11`) and a single `buttons` array
(`TGButtonsMenuItem.h:15`); it holds no layout knowledge at all
(`TGButtonsMenuItem.m:7-15`).

## 2. Public surface

```objc
@interface TGButtonsMenuItemView : UITableViewCell
@property (nonatomic, strong) ASHandle *watcherHandle;
@property (nonatomic, strong) NSArray *buttons;
@end
```
(`TGButtonsMenuItemView.h:13-19`)

`buttons` is an array of **plain NSDictionaries**, not objects. The recognised keys, all optional
except `title`:

| key | type | meaning | read at |
|---|---|---|---|
| `title` | NSString | button label | `TGButtonsMenuItemView.m:81` |
| `disabled` | NSNumber(bool) | dim + disable | `.m:82-84` |
| `green` | NSNumber(bool) | switch to the green "call-to-action" skin | `.m:86` |
| `action` | NSString | opaque token echoed back on tap | `.m:160,164` |

Only the **first two** entries are ever reachable: element 0 drives `_leftButton`, element 1
drives `_rightButton`, and any third or later element simply overwrites `_rightButton` again in
the same loop (`.m:74-106`, the `visibleButtons == 1 ? _leftButton : _rightButton` ternary at
`.m:79`). There is no pagination and no wrapping. In practice no call site ever passes more than
two.

`watcherHandle` is the ActionStage callback channel; both controllers set it once at cell-creation
time from their own `_actionHandle` (`TGProfileController.m:2506`,
`TGTelegraphConversationProfileController.mm:1381`).

## 3. Geometry and metrics, with the reasoning behind each number

**Row height: 43 pt.** Hard-coded in both hosts —
`TGProfileController.m:2321-2323` (`case TGButtonsMenuItemType: return 43;`) and
`TGTelegraphConversationProfileController.mm:1215-1216`. This is not an arbitrary number: the
button view is created at exactly the artwork's intrinsic height,
`CGRectMake(0, 0, 100, rawButtonImage.size.height)` (`.m:122`), and
`Telegraph/Telegraph/Resources/GroupedActionButton@2x.png` is 48×86 px = **24×43 pt**. So the
button exactly fills the row, top to bottom, with zero vertical padding. Change the artwork and
the row height must change with it — 43 is the asset, not a design token.

**Horizontal layout** (`.m:139-153`), all relative to `contentView.bounds`, which in an iOS 6
`UITableViewStyleGrouped` table (`TGProfileController.m:690`) is already inset ~10 pt each side,
i.e. 300 pt wide on a 320 pt screen:

- Two buttons visible: `buttonWidth = floorf((contentWidth - 10) / 2)`; left at x = 0, right at
  `contentWidth - buttonWidth`. On a 4S that is 145 pt each with a 10 pt gutter. The `floorf`
  plus right-alignment means the gutter absorbs the odd pixel on odd widths (11 pt gutter), so
  both buttons stay integral and the card edges stay flush.
- One button visible: it takes the full `contentWidth` (`.m:151`).
- **Zero buttons visible: `layoutSubviews` does nothing** — no branch covers it (`.m:143-152`).
  The row is still 43 pt tall and simply renders as empty space, because the height function
  never consults the button count. This is real, observable behaviour, not a hypothetical: in
  `TGProfileController` the phonebook-contact branch adds no buttons at all when the contact has
  no phone numbers (`TGProfileController.m:1053-1058`), yet `_actionsSection` is still in the
  section list, so a 43 pt blank gap appears.

**Widths are never measured against the title.** No `sizeToFit`, no
`adjustsFontSizeToFitWidth`. A long localized title therefore hits `UIButton`'s default
`titleLabel` line-break mode, middle truncation, inside a 145 pt pill. That is the original's
answer to overlong text: truncate in the middle, never shrink, never wrap, never re-balance the
two halves.

## 4. Artwork

Four stretchable PNGs in `Telegraph/Telegraph/Resources/`, **@2x only — there is no 1x variant
in the tree**, so this is retina-only artwork (fine for the 4S, worth knowing if anything ever
runs at 1x):

| asset | px | pt | left cap |
|---|---|---|---|
| `GroupedActionButton@2x.png` | 48×86 | 24×43 | 12 |
| `GroupedActionButton_Highlighted@2x.png` | 48×86 | 24×43 | 12 |
| `GroupedActionButtonGreen@2x.png` | 66×86 | 33×43 | 16 |
| `GroupedActionButtonGreen_Highlighted@2x.png` | 66×86 | 33×43 | 16 |

Stretching is always `stretchableImageWithLeftCapWidth:(int)(width/2) topCapHeight:0`
(`.m:91-92`, `.m:119-120`) — horizontal only, one-pixel stretchable column at the centre, the
vertical gradient preserved intact. `(int)` truncation gives cap 12 of 24 and cap 16 of 33; the
green asset's centre column is therefore 1 pt of a 33 pt image, which is what makes the wider
green artwork stretch without smearing its rounded ends.

## 5. Skins

### Default (grey/blue) — built in `-createButtonWithTitle:` (`.m:114-137`)

- background: `GroupedActionButton` / `_Highlighted` (`.m:123-124`)
- title colour normal `#4A6587` (`.m:125`), highlighted white (`.m:127`)
- title shadow normal `#FFFFFF` at 45 % (`.m:126`), highlighted `clearColor` (`.m:128`)
- font `boldSystemFontOfSize:14` (`.m:129`)
- shadow offset `(0, +1)` — light shadow **below** the glyphs, the classic iOS 6 engraved look on
  a light plate (`.m:130-131`)
- `adjustsImageWhenDisabled = false` (`.m:132`) — the dimming is done by hand via `alpha`, not by
  UIKit
- `exclusiveTouch = true` (`.m:133`) — the two buttons can never both be pressed

### Green — applied in `-setButtons:` when `green` is truthy (`.m:86-105`)

- background swapped to `GroupedActionButtonGreen` / `_Highlighted` (`.m:97-98`)
- title white in both normal and highlighted (`.m:94, 96`)
- title shadow `#124606` at 30 %, both states (`.m:99-100`). Note `.m:95` sets the normal shadow
  to white first and `.m:99` overwrites it four lines later — the white line is dead code.
- font `boldSystemFontOfSize:16` (`.m:101`) — two points larger than the grey skin, because the
  green button is only ever the single full-width "Invite" call to action
- shadow offset `(0, -1)`, i.e. **above** the glyphs — inverted from the grey skin, the correct
  emboss direction on a dark saturated plate (`.m:102-103`)
- `reverseTitleShadow = false` (`.m:104`), so `TGHighlightableButton` does not flip the offset on
  press.

The only green call site is the phonebook-contact "Invite" button
(`TGProfileController.m:1057`).

### Disabled

`buttonView.alpha = 0.7` and `enabled = NO` (`.m:83-84`). Nothing else changes — no separate
artwork, no separate title colour. Two real cases produce it: "Add Contact" when the user has no
phone number (`TGProfileController.m:1069`) and "Invite" when a contact request is already
pending (`TGProfileController.m:1057`).

Note that the green skin is applied but **never un-applied**. Nothing resets font, colours or
background when a subsequent `setButtons:` has no `green` flag, and the reuse identifier is the
same `@"BBI"` for every configuration (`TGProfileController.m:2493`). A cell that has once been
green stays green. That is latent in the original because a given profile controller instance
never changes its own mode in a way that swaps green for grey on the same visible cell — but it
is a genuine fragility of the design, not something to reproduce.

## 6. Cell chrome, background, separators

- `self.backgroundColor = nil; self.opaque = false` in init (`.m:19-20`) — the cell is fully
  transparent, so the grouped table's patterned background shows through the 10 pt gutter and
  around the pills.
- Both hosts set `selectionStyle = UITableViewCellSelectionStyleNone` and replace
  `backgroundView` / `selectedBackgroundView` with **empty `UIImageView`s**
  (`TGProfileController.m:2499-2504`). That is what suppresses iOS 6's grouped white rounded
  plate and its hairline separators for this row: an image view with no image draws nothing.
- Both hosts set `clearBackground = true` for this item type (`TGProfileController.m:2514`), so
  `updateGroupedCellBackground(...)` — the helper that gives every other row its top/middle/bottom
  rounded plate at `TGProfileController.m:2648-2651` — is deliberately skipped.

## 7. Behaviour on tap

`buttonPressed:` (`.m:155-175`) does not call a selector or a delegate directly. It maps the
sender back to index 0 or 1, pulls the `action` string out of that dictionary, and posts it
through ActionStage:

```
[watcher actionStageActionRequested:@"buttonsMenuItemAction"
                            options:@{@"action": action}];
```
(`.m:173`)

If `action` is missing or the array is shorter than the pressed slot, the tap is silently
swallowed (`.m:167-168`). The host controllers demultiplex the token in their
`actionStageActionRequested:options:`:
`sendMessage`, `sendRequest`, `addContact`, `shareContact`, `invite`
(`TGProfileController.m:4504-4530+`) and `addMember`, `leaveGroup`
(`TGTelegraphConversationProfileController.mm:2959-2967`).

The indirection buys one thing: the cell has no knowledge of the controller and can be dequeued,
reconfigured and re-pointed at a different action set without any target/action bookkeeping. The
targets are wired exactly once, in `init` (`.m:23, 26`), and torn down in `dealloc` (`.m:36-37`).

## 8. Reuse and the change-detection short-circuit

`setButtons:` opens with a manual diff (`.m:42-70`): if the new array has the same count and
every entry matches on **`title` and `disabled`**, it returns without touching anything. This
exists because `-updateActions:` is called from network callbacks and would otherwise churn the
buttons on every user-info update.

Two consequences worth writing down:

1. The diff ignores `green` and ignores `action`. Because the early return happens **before**
   `_buttons = buttons` (`.m:72`), an array whose titles and disabled flags are unchanged but
   whose `action` tokens differ leaves the cell holding the *old* array — and `buttonPressed:`
   reads `action` from `_buttons` at tap time. The stale action fires. No call site currently
   triggers this, but it is a trap.
2. There is no `prepareForReuse`. Everything is reset by `setButtons:`, and `setButtons:` is
   called unconditionally in `cellForRowAtIndexPath:` (`TGProfileController.m:2510`), so the
   short-circuit is the only reuse safety net there is. Combined with §5's sticky green, a
   dequeued cell relies entirely on the caller passing a materially different array.

There is also a direct-poke path: `-updateActions:` looks up the live cell by index path and
calls `setButtons:` on it in place rather than reloading the row
(`TGProfileController.m:1086-1090`), which is how the profile avoids an animated row reload when
"Add Contact" flips from disabled to enabled.

---

## 9. Our port

Our equivalent is **`TGProfileButtonsCell`, inlined in
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGProfileViewController.m`**
(interface at :76-79, implementation at :249-296). There is no separate file and no model class;
the button dictionaries are built ad hoc in `-actionItems` (:880-895) and consumed in
`-actionsCell:row:` (:903-931).

**What we got right** — and this is most of it. The grey skin is a faithful transcription: image
names, `stretchableImageWithLeftCapWidth:(int)(w/2) topCapHeight:0` (:240-245), title
`#4A6587` / white-45 % shadow / white highlighted / clear highlighted shadow, `boldSystemFontOfSize:14`,
shadow offset `(0,1)`, `adjustsImageWhenDisabled = NO`, `exclusiveTouch = YES` (:249-265) — every
one matches `.m:114-137`. Row height 43 (`kButtonsRowHeight`, :178, used at :3050) matches
`TGProfileController.m:2322`. The two-up layout formula, `floorf((contentWidth - 10) / 2)` with
the right button right-aligned (:284-295), matches `.m:145-147` exactly, gutter included. The
disabled treatment, `alpha 0.7` + `enabled = NO` (:922-924), matches `.m:83-84`. The four PNGs in
`src/images/` are the same four @2x assets. All of that can stand.

**Differences a user could see:**

1. **Stacked rows have no vertical gutter.** We paginate an arbitrary number of actions into
   `ceil(n/2)` rows of two (`-actionRowCount`, :897-900), and our default set is five entries —
   Send Message / Add / Share / Search Messages / More (:880-893) — so the profile shows three
   button rows. Each button fills its 43 pt row completely (`height = kButtonsRowHeight`, :287),
   so vertically adjacent pills touch with **0 pt** between them while horizontally they are
   10 pt apart. The original never stacked: exactly one row, one or two buttons
   (`.m:79`, `TGProfileController.m:1047-1078`). If we keep the extra actions, the rows need a
   vertical gutter of their own — the cleanest fix matching the original's optics is to keep the
   button at 43 pt and make every row after the first 53 pt tall with the button at y = 10, so
   the vertical rhythm equals the horizontal one.
2. **No green skin.** `TGProfileButtonsCell` has no `green` path at all (:249-265) and
   `-actionItems` never emits one (:880-895), so we have no equivalent of `Invite` —
   `GroupedActionButtonGreen@2x.png` is shipped in `src/images/` but unused by this cell. If we
   ever add the invite-a-phonebook-contact flow, the skin is `.m:86-105`: green artwork, white
   title, `#124606` @ 30 % shadow, **font 16 not 14**, shadow offset `(0,-1)` not `(0,+1)`.
3. **Button height is a constant, not the asset.** We use `kButtonsRowHeight` for the button's own
   height (:287, :291) where the original uses `_leftButton.frame.size.height` seeded from
   `rawButtonImage.size.height` (`.m:122`, `.m:146-147`). Identical today (asset is 86 px). It
   silently diverges the moment a theme swaps in artwork of a different height, which our
   `TGTheme` makes possible in a way the original's fixed bundle did not.
4. **Targets are rewired on every configure.** We `removeTarget:`/`addTarget:` per button per
   `cellForRow` and stash the index in `button.tag` (:909-928) instead of wiring once in `init`
   and resolving the sender by identity (`.m:23-26`, `.m:158-165`). Not visible, but the tag is
   an index into `self.actionNames`, and `-actionTileTapped:` re-reads `self.actionNames`
   (:3092-3095) — if the action list is rebuilt between layout and tap without the table being
   reloaded, the tag points at the wrong entry. The original is immune because the cell owns its
   own array. Low risk, but it is the one place where our simplification is strictly weaker.
5. **`backgroundView` is a clear `UIView`, the original's is an empty `UIImageView`** (:274-275
   vs `TGProfileController.m:2500-2503`), and we never set `selectedBackgroundView`. With
   `selectionStyle = None` (:272) this produces the same pixels; no change needed, noted only so
   nobody "fixes" it in the wrong direction.
6. **Neighbouring inconsistency, adjacent to this component.** `TGProfileRedButtonCell` lays its
   button out against `self.bounds` with a manual `kGroupedInset = 9` (:326-333) while
   `TGProfileButtonsCell` lays out against `contentView.bounds` (:284-295). In an iOS 6 grouped
   table the contentView inset is 10, not 9, so the red Delete Contact button is 1 pt wider on
   each side than the pills above it — a visible 1 pt misalignment of the left and right edges of
   two buttons in the same vertical stack. The original's equivalent (`TGButtonMenuItemCell`,
   row height 45 at `TGProfileController.m:2317-2320`) is a separate study, but the fix here is
   to make the red cell use `contentView` too.
7. **Empty state.** Ours can't reach it — `-actionItems` always appends "More" (:892) so there is
   always at least one button. The original could show a blank 43 pt row (§3). No action needed;
   recorded so the case is known.

## 10. What became of it

**`twelve`** (`/Users/alexanderhavrysh/Git/iOS/twelve`) still carries
`Telegraph/TGButtonsMenuItemView.{h,m}` essentially byte-identical to the original — a `(int)`
cast on `buttons.count` at :46 and `CGFloor` instead of `floorf` at :145 are the only diffs, both
64-bit-cleanliness edits, not design changes. More telling: **nothing imports it any more**. A
grep for `TGButtonsMenuItemView.h` across the whole fork hits only the file itself and
`Telegraph.xcodeproj/project.pbxproj`. The class survived as dead code; the profile screen moved
on without it. So there is no "how the original's authors extended it" lesson to learn here —
they replaced it instead.

**Modern client.** The concept survives, relocated and re-shaped. Paired action buttons are no
longer a table row at all: they are `PeerInfoHeaderButtonNode` /
`PeerInfoHeaderActionButtonNode` inside the profile *header*
(`submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift`,
nodes declared at :153-154). The changes and why they happened:

- **Two slots became N slots, evenly distributed.** `buttonWidth = (width - buttonSideInset * 2 +
  buttonSpacing) / CGFloat(buttonKeys.count) - buttonSpacing` (`PeerInfoHeaderNode.swift:2325`),
  with `buttonSpacing = 8.0` (:2266) and a fixed height of 58 (:2326). This is *forced*, not
  taste: the button set grew to message / call / videoCall / voiceChat / mute / more
  (`PeerInfoHeaderButtonNode.swift:12-33`) and the set is computed per peer
  (`PeerInfoHeaderNode.swift:547-548`), so a hard-coded left/right pair could not survive. Our
  port already made the same move, just by stacking rows instead of shrinking columns — which is
  the right call on a 320 pt screen, where five 58 pt-wide icon buttons would be unreadable.
- **The gutter shrank from 10 to 8** and the metric is now derived from the button count rather
  than from artwork. That follows from the artwork disappearing: the modern buttons are drawn
  vector fills with an icon over a label, not a stretched PNG plate, so nothing pins the height
  to an asset the way our 43 is pinned to an 86 px image.
- **The green skin's job was taken over by a separate node class**
  (`PeerInfoHeaderActionButtonNode`, wired through its own `actionButtonKeys` list and its own
  width formula at :2269). The original expressed "this one button is the primary action" as a
  boolean inside a dictionary; the modern client expresses it as a different type. That is a
  change of taste in service of type safety, and it is the one modern idea worth borrowing in
  spirit: if we ever add the green Invite, make it a distinct configuration path rather than a
  `green` flag on a shared, never-reset cell (§5).
- **The dictionary-of-strings payload is gone**, replaced by a `PeerInfoHeaderButtonKey` enum and
  a `performButtonAction` closure (`PeerInfoHeaderNode.swift:167`). Same architecture as the
  ActionStage token — decouple the cell from the controller — with the stringly-typed part
  removed. Our port already uses closures/selectors on the controller, so we are closer to the
  modern shape than to the original here, and that is fine: the original's ActionStage token was
  an artifact of its global event bus, not a visual decision.

## 11. Genuinely ambiguous / unresolved

- Whether the 10 pt figure in `floorf((width - 10) / 2)` was meant as "gutter" or as "total slack"
  is not stated anywhere; the code produces a 10 pt gutter at even widths and 11 at odd. Either
  reading gives the same pixels on a 4S, so it does not matter for us.
- The original ships no 1x artwork for these plates. Whether 1x versions existed in the shipping
  bundle and were stripped from this source snapshot cannot be determined from the tree.

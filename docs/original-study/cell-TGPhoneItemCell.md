# TGPhoneItemCell — the original 2013 phone row

Source of truth: `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGPhoneItemCell.{h,m}`
(Telegram for iOS v1.1, build 21024). Model object: `TGPhoneItem.{h,m}` in the same directory.
Read-only study; every number below carries a file:line.

---

## 1. What it is

One row of a contact's phone list on the profile screen. It is a *dual-personality* cell: in normal mode
it is a read-only labelled value (`mobile   +7 916 123-45-67`), in table editing mode the very same cell
turns into a phone **text field** with a rotating minus switch on the left and a sliding "Delete" button
on the right. The two personalities share a single frame layout, so nothing moves horizontally when
editing begins — only the switch slides in and the value view is swapped for a field at the identical
rect.

It subclasses `TGGroupedCell` (`TGPhoneItemCell.h:15`), which is the project's grouped-list cell:
it draws its own rounded plate as `backgroundView`/`selectedBackgroundView` images supplied by the
controller (`TGProfileController.m:229-279`, `updateGroupedCellBackground`) and knows a
`groupedCellPosition` bitmask (`TGGroupedCell.h:11-14`, `First = 1`, `Last = 2`).

Two controllers instantiate it, both with reuse identifier `@"PI"`:
`TGProfileController.m:2565-2581` (full behaviour: editing, watcher, main-phone highlight, disabled)
and `TGTelegraphConversationProfileController.mm:1440-1459` (display only — sets `label` and `phone`
and nothing else; no watcher handle, no `resetView`, no `setDisabled:`).

Row height is a hard **44** points, shared with action/switch/variant rows
(`TGProfileController.m:2311-2315`). Every metric below was chosen against that 44 and against the
two fonts named in §3.

---

## 2. Public surface

```objc
@property (nonatomic, strong) ASHandle *watcherHandle;   // TGPhoneItemCell.h:17
@property (nonatomic, strong) NSString *label;           // :19
@property (nonatomic, strong) NSString *phone;           // :20
- (void)setIsMainPhone:(bool)isMainPhone;                // :22
- (void)setDisabled:(bool)disabled;                      // :23
- (void)resetView;                                       // :24
- (bool)hasFocus;                                        // :26
- (void)requestFocus;                                    // :27
- (void)fadeOutEditingControls;                          // :29
```

`phone` is a *formatted* string on the way in — the controller passes `[phoneItem formattedPhone]`
(`TGProfileController.m:2581`), which is `[TGStringUtils formatPhone:_phone forceInternational:false]`
(`TGPhoneItem.m:73`) and is cached until `setPhone:` invalidates it (`TGPhoneItem.m:40-44`).
On the way out (while typing) `self.phone` is set to the field's already-formatted text
(`TGPhoneItemCell.m:702`), and the controller stores it back with `item.formattedPhone = phoneItemCell.phone`
(`TGProfileController.m:4714`), which re-derives the raw digits by stripping everything but a leading
`+` and `0-9` (`TGPhoneItem.m:46-66`). That round trip is the whole reason `TGPhoneItem` has both a raw
and a formatted property.

The cell talks back through `ASWatcher`, not a delegate: two actions,
`"phoneItemReceivedFocus"` (`TGPhoneItemCell.m:608`) and `"phoneItemChanged"`
(`TGPhoneItemCell.m:716`, `:737`), each with `options[@"cell"] = self`. Handled at
`TGProfileController.m:4667-4756`.

---

## 3. Layout, fonts, colours — all with citations

All frames are set once in `initWithStyle:reuseIdentifier:`; there is **no `layoutSubviews`**. Width
adaptation is by autoresizing masks only.

| Element | Frame | Citation |
|---|---|---|
| vertical separator (`_editingLineView`) | `(72, 0, 1, 1)`, `UIViewAutoresizingFlexibleHeight`, hidden, alpha 0 | `TGPhoneItemCell.m:116-119` |
| label (`_labelView`, `TGLabel`) | `(4, 13, 62, 16)`, right-aligned | `:122-123` |
| value (`_phoneView`, `TGLabel`) | `(78, 11, contentWidth - 80, 20)`, `FlexibleWidth` | `:130-131` |
| text field (`_textField`, `TGTextField`) | identical `(78, 11, contentWidth - 80, 20)`, `FlexibleWidth` | `:139-140` |
| minus switch (`_switchButton`) | `(-23, 6, 30, 30)` parked off-screen; slides to `x = 7` when editing | `:185`, `:328` |
| minus glyph (`_switchButtonMinus`) | centre `(15, 14)` inside the 30×30 button | `:196` |
| delete button (`_editingButton`) | height 31, `y = 7 - (retina ? 0.5 : 0)`, collapsed width 2 at `x = width - 16 - 2`, expanded width 61 at `x = width - 16 - 61` | `:207`, `:219`, `:512`; `TG_DELETE_BUTTON_EDGE_OFFSET` = 16 at `:13` |

Note the geometry logic: the label column is `4…66` (62 wide, right-aligned so it hugs the separator),
the separator sits at exactly **72**, the value column starts at **78** — a 6pt gutter on each side of
the 1pt rule. The value's 20pt box at y=11 centres a 15pt bold line in a 44pt row (11 + 20 = 31,
leaving 13 below — one point of optical lift, matching the label's y=13 for a 16pt box). The
`-0.5` retina nudge on the delete button (`:207`) is there because the 31pt button height is odd
against the 44pt row.

**Fonts**

- label: `boldSystemFontOfSize:13` (`:124`)
- value and field and placeholder: `boldSystemFontOfSize:15` (`:132`, `:141`, `:146`)
- "Delete" text baked into the delete button: `boldSystemFontOfSize:13` (`:170`)

**Colours**

- label text `0x5d708f` (`:126`), highlighted white (`:127`)
- value text black (`:134`), highlighted white (`:135`)
- **main phone** value `0x347fd4` (`:274-275`) — applied to both label view and field
- **disabled** value `0xaaaaaa` (`:288-289`)
- placeholder `0xb3b3b3` (`:145`), turning white when highlighted (`:148-149`)
- both `_labelView` and `_phoneView` are given `backgroundColor = whiteColor` (`:125`, `:133`) —
  deliberately **opaque**, because the grouped plate under them is white and opaque labels were the
  cheap way to keep scrolling fast on an A5. This is why the design cannot be recoloured without
  touching these two lines.
- delete-button text shadow: `CGSizeMake(0, -1)`, blur 0, colour `0xa30f0a` at 20 % alpha (`:176`)

**Artwork**

- `GroupedCellVerticalSeparator.png` + `_Highlighted` (`:111-112`) — 2×2 px @2x, i.e. a 1×1 pt tile,
  stretched vertically by the autoresizing mask.
- `ListEditingSwitch.png` (`:168`) as the switch's normal background — 60×60 px @2x = 30×30 pt, exactly
  the button frame.
- `ListEditingSwitchMinus.png` / `ListEditingSwitchMinus_Active.png` (`:20`, `:30`) — 32×32 px @2x = 16×16 pt.
- `ListDeleteButton.png` / `_Highlighted` (`:40`, `:51`), 36×60 px @2x = 18×30 pt, made stretchable with
  `stretchableImageWithLeftCapWidth:(width/2) topCapHeight:0` (`:41`, `:52`) — that is what lets the
  button animate from 2pt wide to 61pt wide without distortion.
- The "Delete" caption is **not** an asset: it is rendered once into a bitmap at `:170-182`, sized
  `ceil(textWidth) + 2` × textHeight, drawn white with the red shadow above. Rendered once in a
  `dispatch_once`, so a language change at runtime would keep the old bitmap — an accepted limitation.

---

## 4. States

1. **Normal** — `_phoneView` visible, `_textField` hidden (`:152`), switch hidden and alpha 0
   (`:187-188`), delete button hidden and alpha 0 (`:208-210`).
2. **Main phone** — only cosmetic: the value turns `0x347fd4`. The controller only sets it when the
   phonebook contact has more than one number: `highlightMainPhone = (phoneNumbers.count != 1)`
   (`TGProfileController.m:1906`) and the cell receives
   `phoneItem.highlightMainPhone && phoneItem.isMainPhone` (`:2583`). A contact with a single number is
   therefore black, never blue. Matching is by `phoneMatchHash` against the Telegram user's own number
   (`:1904`, `:1911`).
3. **Disabled** — used when the peer hides its number. The item is created with `phone = @"empty"`,
   `disabled = true` (`TGProfileController.m:1917-1922`); the cell then paints `0xaaaaaa`, replaces the
   text with `TGLocalized(@"Profile.PhoneHidden")` = "Hidden"
   (`en.lproj/Localizable.strings:451`) and sets `userInteractionEnabled = false`
   (`TGPhoneItemCell.m:286-293`). Two important asymmetries: `setDisabled:false` does **not** restore
   anything (the `if (disabled)` branch is one-way, `:286`), and it does not clear the blue main-phone
   colour by itself — order of `setIsMainPhone:` then `setDisabled:` in the controller (`:2584-2585`)
   is what makes grey win.
4. **Editing (row)** — see §5.
5. **Editing active (delete armed)** — `_editingIsActive`, minus rotated, red Delete extended.

---

## 5. Behaviour

**Entering/leaving editing** (`setEditing:animated:`, `:315-421`). Entering: field unhidden, value
hidden, switch and separator unhidden, then over **0.3 s** the switch slides from `x = -23` to `x = 7`,
the separator fades to alpha 1, and the switch's alpha becomes `text.length == 0 ? 0 : 1` (`:335`) —
the empty trailing row shows no minus, because there is nothing to delete yet. Leaving: resigns first
responder if focused (`:348-352`), animates the switch back out and the separator to 0, and only in the
**completion block** hides the field / unhides the value (`:377-382`), so no flicker mid-animation;
if the animation is interrupted the views stay swapped — a real, reproducible glitch in the original.

**The minus switch** (`switchButtonPressed`, `:467-497`). Toggles `_editingIsActive`. Over **0.25 s**
the glyph swaps image and rotates `-M_PI_2` with its centre moving from `(15, 14)` to `(14.5, 14.5)`
(`:482-484`) — the half-point shift is a hand correction for the rotated bitmap's optical centre.
Simultaneously `animateDeleteButton:` (`:499-534`) expands the red plate from 2pt to 61pt in 0.25 s
with its label cross-fading, and registers the cell as the table's single `actionCell`
(`TGActionTableView`, `:516-517`) so opening another row's Delete closes this one.

**Tap on the red Delete** (`deleteButtonPressed`, `:451-465`): clears `actionCell` and forwards
`commitAction:` to the table's delegate if it conforms to `TGActionTableViewDelegate`. The profile
controller then removes the row, calling `fadeOutEditingControls` first so the minus fades over 0.3 s
while the row collapses (`TGProfileController.m:2733-2745`, cell `:586-592`).

**hitTest override** (`:231-252`). While `self.editing && !_editingIsActive`, any touch left of the
text field's origin returns `super` (so the row's own selection fires — that is how tapping the *label*
opens the label picker), touches inside the field go to the field, and everything else returns `nil`.
The `nil` is what suppresses UITableView's own selection over the empty right-hand area during editing.

**Tap semantics of the row** (`TGProfileController.m:2926-2946`): editing → present
`TGPhoneLabelController` modally to choose the label; not editing → deselect animated, then open
`tel:` (falling back to `facetime:` when `tel://` cannot be opened, `:2944-2946`) using
`[TGStringUtils formatPhoneUrl:]`. Long-press exposes exactly one menu action, **Copy**, and only when
not editing (`:2872-2882` `shouldShowMenu`, `:2844-2870` `canPerformAction`/`copy:`), and it copies the
`formatPhoneUrl` form, not the display form (`:2822-2826`).

**Typing** (`textField:shouldChangeCharactersInRange:`, `:619-726`). This method never returns `true`:
it rewrites the text itself and returns `false` (`:725`). Steps: filter the replacement to `+` and
digits; rebuild the raw digit string from the current text while translating the caret range from
*formatted* coordinates to *raw* coordinates; special-case a backspace that lands on a separator by
stepping one character left (`:661-665`); splice; re-format with `formatPhone`; walk formatted against
raw to translate the caret back; assign, restore `selectedTextRange`, update `self.phone`, update the
switch's visibility, and notify the watcher. The whole body is wrapped in `@try/@catch` (`:671`, `:718`)
because the caret arithmetic was known to be fragile. `textFieldShouldClear:` also returns `false` and
clears manually (`:728-740`).

**Focus** produces the row-pruning behaviour: on `textFieldShouldBeginEditing:` the cell posts
`phoneItemReceivedFocus` **asynchronously** (`:604-609`), and the controller deletes every other empty
phone row except the last one, then re-focuses the cell on the next runloop
(`TGProfileController.m:4667-4702`). On `phoneItemChanged`, if the last row is now non-empty the
controller appends a fresh empty row with the next unused label from `[TGSynchronizeContactsManager phoneLabels]`
(`:4704-4756`), and repaints the previous row's grouped plate via `updateGroupedCellBackground` so the
corner rounding moves down (`:4747`). The label list is the address-book localized labels in order
mobile, iPhone, home, work, main, home fax, work fax, pager, other
(`TGSynchronizeContactsActor.mm:297-310`); default is `Profile.LabelMobile` = "mobile".

**Reuse.** `resetView` (`:423-439`) is called on every `cellForRow` (`TGProfileController.m:2587`) and
undoes exactly two things: an armed minus (rotation, centre, image) and a visible delete button
(alpha 0, hidden, collapsed to 2pt). It deliberately does **not** reset text colour, so a recycled cell
that was blue stays blue unless `setIsMainPhone:`/`setDisabled:` overwrite it — which they always do at
`:2584-2585`. The conversation-profile call site never calls `resetView` at all
(`TGTelegraphConversationProfileController.mm:1440-1459`), which is safe only because that screen never
enters editing.

**Highlight.** `_highlightTrigger` is a zero-frame `TGHighlightTriggerLabel` with `advanced = true` and
`targetViews = @[_textField]` (`:157-160`). UITableViewCell walks its subview tree calling
`setHighlighted:` on labels; this dummy label intercepts that and forwards
`advancedSetHighlighted:` to the text field (`TGHighlightTriggerLabel.m:17-28`) so the field's text and
placeholder flip to white over the blue selection plate. Without it a `UITextField` would stay black on
blue. `_phoneView` and `_labelView` need no such trick — being `TGLabel`s they get
`highlightedTextColor` directly.

**Long / empty / missing content.**
- Long label: `_labelView` is a plain `UILabel` in a fixed 62pt box, right-aligned, so a long localized
  label truncates with a **leading** ellipsis effect at the right? No — default `lineBreakMode` truncates
  the tail, and right alignment means the visible remainder is left-shifted inside the 62pt box. Nothing
  reflows; the separator never moves.
- Long number: single-line, tail-truncated in `contentWidth - 80`. On a 320pt screen that is 240pt,
  which holds roughly 24 characters of bold 15 — enough for any real international number, so the
  original never had to think about it.
- Empty phone in editing: shown as the placeholder "Phone" (`Profile.InputPhonePlaceholder`,
  `Localizable.strings:450`), with the minus switch invisible (`:335`, `:742-748`).
- Absent phone entirely: the disabled "Hidden" row of §4.3.

---

## 6. Our port — judged

We have **no** `TGPhoneItemCell`. The component was split in two, and each half lost different things.

### 6a. Read-only half: `TGProfileViewController.m` `detailCell:label:value:` (`src/TGProfileViewController.m:3431-3483`)

What is right: the frames are exact — label `(4, 13, 62, 16)` right-aligned bold 13
(`:3441-3444` vs original `:122-124`), value `(78, 11, w - 80, 20)` bold 15 with `FlexibleWidth`
(`:3449-3453` vs `:130-132`), label colour `0x5d708f` (`:3473`), hidden-phone grey `0xaaaaaa` (`:3477`).
Good work; those came across intact.

Defects a user can see:

1. **Every phone is blue.** `src/TGProfileViewController.m:3478-3479` paints `0x347fd4` for any row
   whose label is `"mobile"`. The original paints blue *only* for the main phone of a multi-number
   phonebook contact (`TGPhoneItemCell.m:274`, gated by `TGProfileController.m:1906` and `:2583`); a
   single-number contact — which is the overwhelmingly common case in our client, since we only ever
   emit one row (`src/TGProfileViewController.m:2786`) — must be **black**. Fix: default to black; use
   blue only when more than one phone row is present and this one matches the account's number.
2. **The number is never formatted.** We build the value as
   `[@"+" stringByAppendingString:phone]` (`src/TGProfileViewController.m:2786`), i.e. `+79161234567`.
   The original always displays `[TGStringUtils formatPhone:… forceInternational:false]`
   (`TGPhoneItem.m:73`), giving `+7 916 123-45-67`. We already own a formatter —
   `src/TGLoginViewController.m:246 reformatPhoneField` — but it is private to the login screen. Extract
   it and use it here; this is the single most visible difference on the profile screen.
3. **Backgrounds are `clearColor`, not white.** `:3446` and `:3452` vs original `:125` and `:133`.
   Defensible for our dark theme, but it means the labels are non-opaque on every row; if scrolling
   ever needs help this is the first knob.
4. **No highlight colours.** The original sets `highlightedTextColor = white` on both labels
   (`:127`, `:135`) so the row reads correctly under the blue selection plate. We set
   `selectionStyle = Blue` for phone rows (`src/TGProfileViewController.m:3463-3464`) but never set
   `highlightedTextColor`, so on tap the `0x5d708f` label and the blue value sit on a blue plate.
   Add `labelView.highlightedTextColor = valueView.highlightedTextColor = [UIColor whiteColor]`.
5. **Copy copies the wrong string, if at all.** Original: long-press → Copy → `formatPhoneUrl` form
   (`TGProfileController.m:2822-2826`, `:2874-2881`). We do implement a menu
   (`src/TGProfileViewController.m:3385-3399`) — verify it offers Copy on the phone row and that it
   copies the dialable form, not the displayed one.
6. `"Hidden"` is compared as a literal (`src/TGProfileViewController.m:3462`) where the original uses
   `Profile.PhoneHidden`. Harmless today (English-only), worth a note.
7. Tap behaviour matches: `tel:` with `facetime:` fallback and digit filtering
   (`src/TGProfileViewController.m:3363-3380` vs `TGProfileController.m:2941-2946`). Correct.

### 6b. Editing half: `TGNewContactPhoneCell` in `src/TGNewContactViewController.m:167-222`

Right: label `(4, 13, 62, 16)` bold 13 `0x5d708f` with white highlighted colour (`:181-187`),
separator at `x = 72` width 1 using `GroupedCellVerticalSeparator.png` with the highlighted variant
(`:189-197`), field at `(78, 11, w - 80, 20)` bold 15 (`:214-215`), placeholder `0xb3b3b3`
(`src/TGNewContactViewController.m:537`), `UIKeyboardTypePhonePad` (`:281`),
`clearButtonMode = WhileEditing` (`:546`), row height 44 (`:298`), tap on row opens the label picker
(`:857-860` → `:667`), and the empty-row append / prune-on-focus choreography
(`:480-496`, `:707-732`) faithfully reproduces `phoneItemChanged` / `phoneItemReceivedFocus`
(`TGProfileController.m:4667-4756`). That is genuinely close.

Defects:

8. **The minus switch does not exist.** No `ListEditingSwitch.png` button, no rotating
   `ListEditingSwitchMinus` glyph, no 61pt sliding red `ListDeleteButton`. We fall back to the stock
   `UITableViewCellEditingStyleDelete` (`src/TGNewContactViewController.m:855-859`), which draws
   Apple's iOS 6 red circle and the system "Delete" swipe button. Visually this is the biggest gap in
   the whole component: the original's minus is *always* visible in editing mode at `x = 7` (it slides
   in over 0.3 s, `TGPhoneItemCell.m:328-337`), rotates `-90°` in 0.25 s on tap (`:472-486`), and
   expands a custom red plate inset 16pt from the right edge (`:501-513`). Note we already ship
   `images/ListEditingSwitch@2x.png` but never reference it (`grep` over `src/` finds no use), and
   `ListEditingSwitchMinus@2x.png`, `ListEditingSwitchMinus_Active@2x.png`, `ListDeleteButton@2x.png`,
   `ListDeleteButton_Highlighted@2x.png` are **absent from `images/` entirely**. Porting this cell
   properly means copying those four assets from
   `telegram-original-sources/.../Telegraph/Telegraph/Resources/` first.
9. **The switch's visibility rule is missing.** Original hides the minus whenever the field is empty
   (`:335`, `:742-748`), so the trailing blank row never offers a delete. Our stock editing control is
   suppressed only by `phoneEntries.count > 1` (`:852`, `:856`) — a two-row form with one empty row
   still shows a red circle on the empty row.
10. **No live formatting while typing.** Our `shouldChangeCharactersInRange:` only *filters* to digits
    and `+` and returns `YES` (`src/TGNewContactViewController.m:825-834`). The original rewrites the
    text through `formatPhone` on every keystroke and re-places the caret (`TGPhoneItemCell.m:619-726`).
    Consequence: the user sees `+79161234567` while typing where 2013 showed `+7 916 123-45-67`. When
    you fix defect 2 by extracting the formatter, wire it here as well — and port the caret-translation
    loop (`:684-699`), otherwise the caret jumps to the end on every mid-string edit.
11. **No highlight bridging for the field.** We have `TGHighlightTriggerLabel` in the tree
    (`src/TGHighlightTriggerLabel.{h,m}`) but the cell never installs one against its text field
    (compare `TGPhoneItemCell.m:157-160`). With `selectionStyle = Blue` set at
    `src/TGNewContactViewController.m:809`, a highlighted editing row shows black text on blue.
12. **No `hitTest` carve-out.** The original suppresses row selection to the right of the field during
    editing (`:231-252`); we let the whole row open the label picker (`:857-860`). A user tapping empty
    space beside the number gets an unexpected modal.
13. **`lastInGroup` shortens the separator by 1pt** (`src/TGNewContactViewController.m:216`), matching
    `setGroupedCellPosition:`'s `lineEndY -= 1` for the last row (`TGPhoneItemCell.m:304-305`).
    Correct — but we never apply the `First` case, which in the original is a no-op (`:302-303`), so
    this is fine as-is.
14. `commitEditingStyle:` calls a deferred full `reloadData` (`src/TGNewContactViewController.m:875-877`).
    The original animates the row out and repaints only the neighbour's plate
    (`TGProfileController.m:2735-2744`, `:4747`). Ours will visibly flash the section.

---

## 7. What became of it

**`twelve` (ObjC fork, later lineage).** The cell split into two collection items, which is the same
split we made accidentally: `TGUserInfoPhoneCollectionItemView` (display) and
`TGUserInfoEditingPhoneCollectionItemView` (editing). The 2013 single-line "label — separator — value"
became a **two-line stack**: label above at `y = 11`, phone below at `y = 30`, both left-aligned at a
15pt (or 60pt when a checkbox is present) inset, no vertical rule at all
(`twelve/Telegraph/TGUserInfoPhoneCollectionItemView.m:113-117`, `:108`). Label is 14pt system accent,
phone 17pt (`:37`, `:43`) — up from 13/15 bold, and the boldness is gone entirely. A `TGCheckButtonView`
was added for multi-select (`:58-68`), a genuinely new feature. The editing view keeps a vertical
divider but moves it to `x = 109` with the field at `x = 122` and turns the label into a *tappable
button with a disclosure arrow* instead of relying on row selection
(`TGUserInfoEditingPhoneCollectionItemView.m:36`, `:39-47`, `:108`, `:118-120`). Phone formatting was
extracted into a reusable `TGPhoneTextField` (`:52-58`) rather than living in the cell's
`shouldChangeCharacters:` — the right refactor, and the one our port should imitate.

Forced vs. taste: the checkbox and the label-as-button were forced by features (multi-select, and the
fact that hit-testing a label region inside a collection item is worse than an explicit button). The
two-line layout and the loss of bold are taste — iOS 7 flatness.

**Modern Telegram-iOS.** The concept no longer has a cell of its own. A profile phone number is one
`PeerInfoScreenLabeledValueItem` among many, keyed by an enum case
`case phone(String)` in the info-context menu enum
(`submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift:148`,
`PeerInfoScreenOpenPeerInfoContextMenu.swift:109`). Copy became a context-menu action with an undo/toast
overlay rather than a `UIMenuController` item, and it still copies the **formatted** number
(`PeerInfoScreen.swift:2147-2156`). Editing a contact's phone numbers left Telegram's UI entirely and
lives in the device-contact editor (`DeviceContactExtendedData`, `PeerInfoScreen.swift:1892-1900`).
The one idea that survived all thirteen years untouched: the number is always *displayed formatted*
and *copied formatted*, while the raw digits stay internal. That is precisely defect 2 in our port.

---

## 8. Ambiguities

- The delete-button's `y = 7 - 0.5` on retina (`TGPhoneItemCell.m:207`) is uncommented; it is most
  likely optical centring of a 31pt plate in 44pt, but I cannot prove intent from source.
- `resetView`'s refusal to reset text colour may be intentional (callers always set it) or an
  oversight. It is safe in both original call sites, so I would not "fix" it in a port.
- Whether the label truncates head or tail with a very long localized label is default-`UILabel`
  behaviour (tail) and was never exercised — the label set is a fixed nine short address-book strings.

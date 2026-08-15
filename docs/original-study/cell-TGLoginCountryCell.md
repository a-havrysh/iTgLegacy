# TGLoginCountryCell — original study

Source of truth, unless stated otherwise:
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/`
— `TGLoginCountryCell.h` (17 lines), `TGLoginCountryCell.m` (59 lines),
and its only call site `TGLoginCountriesController.m` (554 lines).

The class exists under exactly that name, in `Telegraph/Telegraph` only. There is no copy in
`TelegraphKit/TelegraphKit`: this is a login-flow cell, not a reusable kit component, and that
placement is itself informative — it was never meant to be used anywhere but the country list.

---

## 1. What it is for

One row of the "Select Country" list that opens from the phone-entry screen: a country name on the
left, its dialling code on the right. It is a `UITableViewCell` subclass with two hand-placed
`UILabel`s and no artwork of its own (`TGLoginCountryCell.h:11`). Everything decorative in that
screen — the section header plates, the overscroll colour, the search bar — belongs to the
controller, not to the cell.

It is the entire visual vocabulary of the country picker: 240-odd instances of this one row, plus
25pt letter headers. Nothing else.

## 2. Public surface

```objc
- (void)setTitle:(NSString *)title;   // country name          (.m:43-46)
- (void)setCode:(NSString *)code;     // "+7", "+1", "+6723"   (.m:48-51)
- (void)setUseIndex:(bool)useIndex;   // layout variant        (.m:53-57)
```

Three setters, no getters, no properties in the header (`TGLoginCountryCell.h:13-15`). `setTitle:`
and `setCode:` are pure text assignments with no `setNeedsLayout` and no `sizeToFit`
(`.m:45`, `.m:50`) — the frames are fixed, so content never moves the layout. `setUseIndex:` is not
a stored flag; it *is* the layout pass. Calling it is the only thing that ever positions the labels
(`.m:53-57`), and the initialiser calls it once with `false` (`.m:38`).

## 3. Metrics, with the reasoning behind them

Row height is 44, set on the table view, not the cell (`TGLoginCountriesController.m:269` for the
main table, `:460` for the search-results table). Both labels are 20pt tall at y = 12
(`TGLoginCountryCell.m:55-56`), which centres a 20pt line box in 44pt: 12 + 20 + 12 = 44. The 20pt
height is sized around `boldSystemFontOfSize:17` (`.m:22`, `.m:32`) — 17pt system bold has a line
height of ~20.3pt on iOS 6, so the label is exactly tall enough and the descenders of "gjpqy" in a
country name are not clipped. Change the font size and the y=12/height=20 pair has to move with it.

Horizontal layout has two variants, chosen by `useIndex` (`.m:55-56`). Widths below are the literal
expressions; the resolved numbers assume the 320pt-wide cell that `initWithStyle:` hands out on a
4S, which is the width in force when `setUseIndex:` runs.

| | title x | title width | code x | code width | code right edge |
|---|---|---|---|---|---|
| `useIndex = true` | 9 | `contentView.width - 54 - 5` = 261 | `self.width - 49 - 32` = 239 | 50 | 289 (31pt inset) |
| `useIndex = false` | 9 | `contentView.width - 54 - 15` = 251 | `self.width - 50 - 9` = 261 | 50 | 311 (9pt inset) |

Read the two variants as one idea: the left margin is always 9, the code label is always 50pt wide
and right-aligned (`.m:29`), and the only thing that changes is how far the right edge is pulled in
to clear the A–Z section index bar. With the index present the code sits 31pt from the right edge;
without it, 9pt — symmetric with the 9pt left margin. The title width is derived from the code
column, not from the text: 54 is the code column plus a 4pt breathing gap, then 5 more (index) or 15
more (no index) of separation. The title therefore always stops well short of the code, and the two
can never collide, whatever the country is called.

The 44pt row plus a 9/9 margin pair is the plain iOS-6 grouped-list rhythm of the era; the picker is
deliberately an ordinary system list, styled only at the section headers.

## 4. Colours and fonts

- Title: `boldSystemFontOfSize:17`, `blackColor`, highlighted text `whiteColor`
  (`TGLoginCountryCell.m:22-25`).
- Code: `boldSystemFontOfSize:17`, `UIColorRGB(0x516691)`, highlighted text `whiteColor`
  (`.m:32-35`). `0x516691` is the muted slate-blue the 2013 login flow used for secondary
  values — it reads as "data", not as a tappable link.
- Both labels have `backgroundColor = whiteColor` (`.m:23`, `.m:33`). This is an opacity
  optimisation for a fast-scrolling 240-row list on a 4S, not a design choice; it presumes the cell
  background is white.
- No `selectedBackgroundView` is set, so selection is the stock iOS-6 blue gradient, and the two
  `highlightedTextColor = white` assignments exist precisely to survive it.

Related colours owned by the controller, for context: the overscroll plate above the list is
`0xe4e9f0` (`TGLoginCountriesController.m:275`); section headers are `CategoryDivider.png` /
`CategoryDividerFirst.png` with a 15pt bold white label shadowed `0x88929c` at offset (0,−1), 25pt
tall (`TGLoginCountriesController.m:379` and the header-building loop above it).

## 5. Artwork

None. The cell loads no image. The four `LoginCountry*` PNGs in `Resources/` —
`LoginCountry@2x.png`, `LoginCountry_Highlighted@2x.png`, `LoginCountryArrow@2x.png`,
`LoginCountryArrow_Highlighted@2x.png` — belong to the *button* on the phone-entry screen that opens
this list, not to the cell (`TGLoginPhoneController.m:148-149`, `:166-167`, `:178`). Do not wire
them into the row.

## 6. States and behaviour

**Reuse.** One identifier, `@"CC"` (`TGLoginCountriesController.m:411`). `setUseIndex:` is called
*only inside the `if (cell == nil)` branch* (`:415-417`), so the layout variant is baked in at
creation and never re-evaluated. That is safe only because the main list and the search-results list
are two distinct `UITableView`s with two distinct reuse pools: the main table's cells are created
with `useIndex = true`, the search table's keep the `false` from the initialiser (`.m:38`). Move to a
single table and this becomes a real bug.

**Missing data.** `cellForRowAtIndexPath:` guards with `if (item != nil)` (`:428`) and, when the
item is nil, simply returns the dequeued cell **without clearing the labels** (`:428-431`). A
recycled cell would then show the previous country's name and code. In practice `item` is never nil,
so the bug is latent — but it tells you the original had no empty state at all.

**Reuse hygiene.** There is no `prepareForReuse` override. Nothing to reset, because the only
mutable state is the two strings, both overwritten every time.

**Long text.** Neither label sets `numberOfLines` or `lineBreakMode`, so both take the iOS-6 defaults
of one line and `NSLineBreakModeTailTruncation`. A long name ("Saint Vincent and the Grenadines",
"Bonaire, Sint Eustatius and Saba") truncates with an ellipsis at 261pt; it never wraps, never
shrinks, and never pushes the code. The code label is right-aligned in a fixed 50pt box, so a 4-digit
code (`+6723`, `+5999` — both real, the first two lines of `PhoneCountries.txt`) grows leftward
inside the box. At 17pt bold, "+6723" measures roughly 48pt, so 50 is just enough; a 5-digit code
would clip on the left. The code is built as `[NSString stringWithFormat:@"+%d", …]`
(`TGLoginCountriesController.m:430`), which also means a leading-zero code would lose its zero —
none exist in the data file.

**Tap.** The cell itself has no tap behaviour; it has no target, no delegate, no accessory. Selection
is handled entirely by the controller, which fires the `"countryCodeSelected"` action-stage message
carrying `code` and `name` (`TGLoginCountriesController.m:450`) and, notably, does **not** deselect
the row — the screen closes instead.

**View hierarchy quirk.** The title goes into `self.contentView` (`.m:26`) but the code label is
added to **`self`**, the cell itself (`.m:36`), and its frame is computed from `self.frame.size.width`
rather than the content view's (`.m:56`). In a plain non-editable list the two widths are equal, so
this makes no visible difference in the shipped screen. It is not harmless in principle: iOS clears
the `backgroundColor` of labels inside `contentView` while a row is highlighted, but does not do so
for direct subviews of the cell. That implies the original, at the moment of the tap, drew a white
50×20 plate over the blue selection with white text on it — an invisible code for the duration of the
touch. I have not observed this on device; treat it as a reading of the code, not a measurement. It
is best read as an oversight, and the later fork agreed (see §8).

## 7. Our port — `TGCountryPickerViewController.m`

Our equivalent is `TGCountryPickerRowCell`, a private class inlined at
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGCountryPickerViewController.m:288-339`. It is a
close and mostly correct port: same 17pt bold on both labels (`:310`, `:320`), same `0x516691`
(`:306`), same white label backgrounds (`:304`), same `highlightedTextColor` white (`:313`, `:323`),
same 9 / 12 / 20 / 50 geometry and both `useIndex` variants byte-for-byte (`:333-336`), same 44pt row
(`:380`), same 25pt headers with `CategoryDivider(First).png` and the `0x88929c` shadow (`:783-796`
region), same `0xe4e9f0` overscroll plate (`:388`), same `UITableViewIndexSearch` handling (`:801-815`).
Our country data is literally `PhoneCountries.txt` transcribed into a string array in the same order
(`:34-270`; compare `Resources/PhoneCountries.txt` and the parser at
`TGLoginCountriesController.m:17-70`). This one is in good shape; the list below is small and mostly
about things the original left ragged.

Differences a user could see:

1. **Not a defect — a deliberate improvement, keep it.** We place the code label in `contentView`
   (`:324`) where the original used `self` (`TGLoginCountryCell.m:36`), and we lay out in
   `layoutSubviews` (`:329-337`) where the original laid out once in `setUseIndex:`
   (`TGLoginCountryCell.m:53-57`). Identical at 320pt; ours additionally survives the highlight
   state cleanly (§6). Do not "fix" this back.
2. **Not a defect.** We set `useIndex` per row (`:823`) rather than once at creation
   (`TGLoginCountriesController.m:417`). We must: we have one table that toggles between list and
   filtered mode, not the original's two tables. Setting it at creation here would be a genuine bug.
3. **Not a defect.** We clear the labels to `@""` when the row is missing (`:825-826`) where the
   original left stale text (`TGLoginCountriesController.m:428`).
4. **Theme divergence, needs a decision.** Under `[[TGTheme shared] isFlat]` we swap in
   `clearColor` backgrounds, `primaryTextColour` and `accentColour` (`:303-306`) and call
   `styleCell:` (`:831-832`). The original has no such branch. This is our own layer; it is only a
   defect if the flat theme is ever the shipping look for a 2013 reproduction. Worth confirming with
   whoever owns `TGTheme` that the non-flat path is the default on the 4S.
5. **Live data can break the code column.** We accept `calling_codes` from TDLib `getCountries`
   (`:436-444`), which the original could not do — its data was a frozen bundled file. TDLib returns
   codes up to 5 digits for some entries. The 50pt box (`:335-336`) was sized for at most 4 digits at
   17pt bold. Either widen the code box to ~62pt in both variants and take the same amount off the
   title width, or clamp what we accept. Today a 5-digit code clips on its left.
6. **Cosmetic, low priority.** We set `selectionStyle = UITableViewCellSelectionStyleBlue` explicitly
   (`:830`); that is already the `UITableViewCell` default, so it matches the original's silence. No
   change needed, noted only so nobody "corrects" it.
7. **Behavioural difference on tap.** We deselect with animation before dismissing (`:837`); the
   original left the row selected as the screen went away
   (`TGLoginCountriesController.m:441-452` — no `deselectRowAtIndexPath:`). Ours briefly shows the
   row fading from blue during the pop. If you want the original feel exactly, drop the deselect
   call.
8. **We carry a flag emoji we never draw.** Rows are `@[name, flag, code, iso]` (`:281`) but the cell
   only ever shows `c[0]` and `c[2]` (`:824-826`). That is correct for 2013 — the original had no
   flags anywhere (`TGLoginCountryCell.m` has one title and one code label, full stop) — but the
   unused column is a standing invitation for a future agent to "restore" flags. If we keep it for
   the phone-entry button, say so where it is built.

## 8. What became of it

**`twelve` (`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGLoginCountryCell.m`)** kept the class
name and the whole skeleton, and every edit is legible as a response to a new requirement:

- Title font dropped from `boldSystemFontOfSize:17` to `TGSystemFontOfSize(17)` — regular weight.
  That is the iOS 7 flattening, a change of taste imposed by the platform, not by a feature.
- Code colour went from `0x516691` to plain black, then to `presentation.pallete.textColor` via a
  new `setPresentation:` method. Forced: night mode. Once themes exist, a hardcoded slate-blue
  cannot survive.
- A third label, `_subtitleLabel` at 14pt, appeared, with the layout moving the title from y=12 to
  y=3 and the subtitle to y=22 when it is non-empty. Forced by a feature: showing the country's
  native-language name under its localised one.
- Layout moved out of `setUseIndex:` into a real `layoutSubviews`, with `setUseIndex:`/`setSubtitle:`
  reduced to storing state and calling `setNeedsLayout` — exactly the change we made independently
  (§7.1). It became necessary once the layout depended on content.
- The code box grew from 50 to 70pt (title widths correspondingly `- 74` instead of `- 54`), and the
  code label moved into `contentView`. The 70 is the same pressure our §7.5 describes: wider codes.
- Left margin became `iosMajorVersion() >= 7 ? 15 : 9` — the 9pt margin is genuinely a pre-iOS-7
  number, and the fork encodes that explicitly. For us, on 6.1.3, 9 is right.
- `selectedBackgroundView` with `TGSelectionColor()` replaced the stock blue.

**Modern client**
(`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS/submodules/CountrySelectionUI/Sources/AuthorizationSequenceCountrySelectionControllerNode.swift:435-476`)
abandoned the custom cell entirely. It uses a stock `UITableViewCell` (`.default` or `.subtitle`),
a `Font.regular(17.0)` label in `accessoryView` for the code — sized with `sizeToFit`, so the column
is now content-driven rather than a fixed 50pt box, which is the real answer to §7.5 — the flag
emoji prefixed into `textLabel.text`, the English name as `detailTextLabel`, colours from
`theme.list.*`, a `selectedBackgroundView`, and `accessibilityLabel`/`accessibilityValue` set from
the name and code. The section index no longer carries a leading `UITableViewIndexSearch` entry.

The through-line: the 2013 cell is a fixed-geometry object that assumes one language, one theme, one
screen width and one line of text. Every later change is that assumption failing — themes, subtitles,
longer codes, dynamic type, accessibility. For our target, all of those assumptions hold, which is
why the original is worth copying almost literally, and why the two places our port already deviates
(layout in `layoutSubviews`, code label in `contentView`) are the two that cost nothing and are
strictly better.

## 9. Open questions

- Does the original really flash a white plate behind the dialling code on touch-down (§6)? It
  follows from `[self addSubview:_codeLabel]` plus `highlightedTextColor = white`, but nobody has
  seen it on a device, and the row is dismissed almost immediately after the tap.
- Which theme path is the shipping one for us, flat or non-flat (§7.4)? The cell's colours fork on it
  and the study cannot answer it from this file alone.

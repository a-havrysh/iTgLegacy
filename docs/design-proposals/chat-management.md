# Chat management — fitting dense admin forms into a 320pt grouped table

The question: a permissions matrix (16 booleans in `chatPermissions`), slow mode (a seven-value
enum) and an admin rights editor (~10 booleans plus a custom title string) are all dense forms.
A 320x480 screen shows nine 44pt grouped rows below the bar, and a UISwitch eats 79pt of the
300pt row. Three answers below, drawn as if they were screenshots.

All three share the same skeleton, because the repo already has it: `UITableViewStyleGrouped`
via `TGActionTableView`, rows 44pt, group box inset 10pt each side (content 300pt), title
`boldSystemFontOfSize:17` at x=20, value `systemFontOfSize:16` in `#356596` right-inset 10,
caption text under a group in `systemFontOfSize:14` `#697487` with the `#DAE0E8` `(0,+1)`
raised shadow, ground = the `SettingsBackground.png` pattern. Nothing here invents a row height
or a PNG.

---

## Option A — Switches with drilldown (`chat-management-a.svg`)

**What it does.** The straight grouped table the app already builds everywhere else, with the
16-field permission struct pruned to five visible rows. Three are plain switch rows
(Send Messages, Add Members, Pin Messages, Change Chat Info — four, plus the parent). The nine
media booleans (photos, videos, audio, documents, voice notes, video notes, stickers/GIFs, links,
polls) collapse into one row, **Send Media**, whose value label reads `5 / 9` in `#356596` at
16pt right-inset 10 with a `MenuDisclosureIndicator` beyond it, pushing a second identical
grouped screen of nine switch rows (nine rows x 44 = 396pt, one screen, no scroll on a 4S).
Slow mode is a value+disclosure row reading `30s`, pushing a screen of seven 44pt rows with
`ListCheck` on the current one. Removed Users is a count row. The admin rights editor is the same
screen type again: a 70pt profile-header-style avatar strip at the top (avatar `(9,14,70,70)`,
r10, name at x=94), then a group of ~10 switch rows, then a `GroupedActionButton` row for
"Dismiss Admin" and, for the owner, a `MenuRedButton` row for "Transfer Ownership".

**Tapped and scrolled.** Switch rows do not select — `selectionStyle = None`, the switch fires
`UIControlEventValueChanged` and the write goes out immediately (`setChatPermissions` with the
whole struct, since TDLib takes it whole). Disclosure rows highlight with the `_Selected` plate
and push. Nothing on the screen scrolls in the common case: the top screen is 5+2 rows and ends
at y=446, so the whole form is visible at once, which is the point. When `can_restrict_members`
is false the switches render disabled — `alpha 0.6`, `userInteractionEnabled = NO` — and a
caption says why, matching the `can_be_edited`-aware read-only mode the catalogue asks for.

**Reuses.** `TGActionTableView`, `[TGTheme styleCell:]` with `Cell102` clipped to 44,
`MenuDisclosureIndicator`, `GroupedActionButton`, `MenuRedButton`, `UISwitch` exactly as
`TGSettingsViewController` already uses it. Zero new artwork, zero new cell classes.

**Cost.** One view controller with a page enum (permissions / media / slow-mode / admin rights),
about the size of the existing settings controller's per-page code. Memory is a table of ≤10
reused cells; nothing measurable.

**Gives up.** You cannot see all nine media rights without a push, so "why can't Anna send a
voice note" takes two taps to answer. The `5 / 9` label is the only hint.

---

## Option B — Presets, then the detail (`chat-management-b.svg`)

**What it does.** Puts a four-row preset group at the top — Open group / Text only / Read-only /
Custom — each a 44pt row with `ListCheck` (15x14) right-inset 10 on the selected one. Picking a
preset writes the whole `chatPermissions` struct in one call. The nine-plus-four detail switches
live in a second group directly below, always present, so the screen scrolls: the preset group
ends at y=268, the detail group starts at 314 and runs off the bottom. Touching any detail
switch moves the tick to Custom automatically. Slow mode and the admin rights editor keep
Option A's treatment (they have no natural preset).

**Tapped and scrolled.** Preset rows select-and-tick, no push, no confirmation. The detail group
is one `UITableView` section, so it scrolls under the same nav bar; there is no sticky header
and no expansion animation beyond `reloadSections:withRowAnimation:UITableViewRowAnimationFade`,
which iOS 6 does fine. A variant worth considering: hide the detail group entirely until Custom
is ticked, which makes the common case a four-row screen — but the reload animation of ~13
inserted rows on an A5 stutters visibly, so drawn here is the always-shown version.

**Reuses.** Everything Option A reuses, plus `ListCheck` / `ListCheck_Highlighted`.

**Cost.** Adds a preset table (four structs) and a "does the current struct equal a preset"
comparison — 30 lines. Same memory as A, plus a scrolling table of ~17 rows.

**Gives up.** The presets are our invention, not Telegram's, so their names have to be explained
in the caption and they will drift from what the server considers sensible. And the screen now
scrolls where A did not, so the second half of the matrix is off-screen at rest — the exact
problem the theme is about, traded for a one-tap answer in the 90% case.

---

## Option C — Checklist, no switches (`chat-management-c.svg`)

**What it does.** Drops `UISwitch` entirely and treats the matrix as a multi-select list: a 44pt
row whose title sits at x=20 and whose state is a `ListCheck` tick at x=286. That reclaims the
79pt the switch occupied, so a row can carry both a tick and a value (`Send Media` shows
`5 / 9` at x=272 *and* a tick), and six rights fit above the fold instead of five. Slow mode is
then affordable **inline**: a 43pt grouped row (the profile segmented-strip height) holding a
seven-segment `TGButtonGroupView` at 30pt — `ButtonGroupLeft` / six `ButtonGroupCenter` /
`ButtonGroupRight` with `ButtonGroupDivider` between, segments 40pt wide across the 300pt group
minus 10pt padding, labels `boldSystemFontOfSize:12` white with the standard `(0,-1)` shadow,
selected segment held in its `_Highlighted` image. No push, no picker, seven values visible at
once. The nav bar carries a `Save` HeaderButton because a checklist reads as a form, not as a
set of live toggles.

**Tapped and scrolled.** Tapping anywhere on the row flips the tick — a 300x44 target instead of
a 79x27 one, which matters on a 3.5" screen. `ButtonGroupView` fires on `UIControlEventTouchDown`
per the rulebook, so slow mode changes instantly. The whole permissions form is one non-scrolling
screen ending at y=462. The admin rights editor uses the same checklist, with the custom-title
text field as a 44pt row (field inset 15, `boldSystemFontOfSize:16`) at the top of its own group.

**Reuses.** `ListCheck`, `ButtonGroup*` (all seven assets), `TGActionTableView`. It reuses more
2013 artwork than the other two and less UIKit.

**Cost.** A checkable grouped cell (~40 lines) and wiring `TGButtonGroupView` into a table row
(~30). Batch save means holding a dirty copy of the struct and a Save button state; slightly more
code than A, still trivial memory.

**Gives up.** A tick is a weaker "this is switchable" signal than a switch — a user may read the
list as a set of destinations. It also breaks with the rest of the app, where every boolean in
Settings is a `UISwitch`; that inconsistency is the real price. And Save/discard introduces a
state the other two options do not have (leaving the screen mid-edit needs an action sheet).

---

## Recommendation

**Option A**, with one borrowing from C. A is the conservative answer and it is the correct one:
it is indistinguishable from the settings screens already shipped, it needs no new cell class, and
the whole top-level form fits on one screen without scrolling, which is what the question actually
asked. Its only real weakness is slow mode costing a push for a seven-value enum — so take C's
inline seven-segment `TGButtonGroupView` row for slow mode and leave everything else as switches.
That is a 43pt row the profile controller already has a height for.

Option B is worth keeping in the drawer for channels, where "Read-only" genuinely is the answer
99% of the time; it is not worth the invented vocabulary in a group.

---

## What cannot be built on this hardware

- **Live search or filter over the permission list.** Not a hardware limit but a pointless one at
  16 rows; mentioned because modern clients have it and we will not.
- **Expand/collapse of the media sub-matrix in place**, the way modern Telegram animates it. The
  animation is a ~13-row insert on an A5 with one core; `UITableViewRowAnimationFade` on that many
  plated cells drops frames badly. Hence the push in A and the always-visible group in B.
- **The chat event log rendered as service messages inside a chat view**, which is how modern
  clients show the ~45 `chatEventAction` variants. That means instantiating the conversation
  renderer for a synthetic message list; on 512MB it competes with the real chat controller for
  the image cache. The buildable version is a plain 51pt two-line list (actor name bold 19,
  action text 13.5 `#888888`), which loses the media previews inside events.
- **A wheel/date picker for invite-link expiry.** `UIDatePicker` exists on iOS 6 and works, but it
  is 216pt tall and there is no popover or sheet-with-picker idiom in the 2013 language; it would
  have to be a pushed screen containing the picker. That is buildable but ugly, so the reduced
  version is a checklist of durations (1 hour / 1 day / 1 week / Never), same treatment as slow
  mode.
- **Set chat location.** MapKit runs, but a pin-drop plus reverse geocode plus the group-type
  screen is a lot of surface for a feature nobody uses; recommend dropping it entirely rather than
  shipping a reduced version.
- **Group sticker set preview grid** at any useful size: nine 64pt sticker thumbnails decoded and
  held resident on a 512MB device, on top of the sticker cache the chat already keeps, is the kind
  of thing that gets the app jetsammed. The reduced version is the short-name field plus a single
  row showing the set's title and count.

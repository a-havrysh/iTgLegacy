# Groups and channels: member management, statistics, boosts

The catalogue marks *group statistics*, *group boosts* and *paid messages* as **blocked**, and it is
right to: the MTProto calls behind them (`stats.getMegagroupStats`, `premium.getBoostsStatus`) return
payloads our TDLib bindings can surface but whose modern presentation — zoomable multi-series graphs
with a scrubber, a second detail chart on tap, animated series toggling — is a `UICollectionView`-and-
`CADisplayLink` affair on a device with one A5 core. So the honest question is not "how do we draw
Telegram's charts on a 4S" but "what part of the information survives when the charts do not".

All three options below answer that. Member management (promote, restrict, ban, banned list, admin
list) already exists in `src/TGGroupMembersViewController.m` — a 44pt mode bar carrying a
`TGButtonGroupView` over 49pt `Cell102` member rows — so none of these proposals rebuilds it. They
differ in what the *Statistics* row on group info pushes to, and where boosts live.

A note on artwork: we have no `GroupedCell*` plates in `images/`, so every screen here is a **plain
white list** — `Cell102` / `CellHighlighted102` row plates, `CategoryDivider` / `CategoryDividerFirst`
26pt section headers, `Footer` closing the list — which is exactly what the members screen already
does. Nothing new is added to `images/`.

---

## Option A — Statistics is a list of numbers

**File:** `svg/groups-channels-a.svg`

No graph at all. `Statistics` pushes a plain list of 51pt `Cell102` rows. Each row is
`label / value / delta`: label at x = 10 in `systemFontOfSize:17` `#516691`, value right-aligned at a
10pt inset in `boldSystemFontOfSize:17` `#356596` on the upper line (baseline row + 20), delta on the
lower line (baseline row + 38) in `systemFontOfSize:13`, `#41A903` when positive and `#EE4928` when
negative. Sections are 26pt `CategoryDivider` strips with the caption in `systemFontOfSize:14`
`#697487` with the `rgba(#FFFFFF,0.3)` `(0,+1)` shadow, per the type chapter's ruling for a
grouped-section caption. The list closes with a 44pt `Footer` carrying the "counted since" note in the
comment-view treatment (`#697487` on `#DAE0E8` at `(0,+1)`).

Boosts are two rows in a second section: `Boost level` with a plain numeric value, and `Boosts`
carrying a `DialogListUnreadBadge` — 21pt tall, width `MAX(27, textWidth + 10)`, frame
`(320 − 28 − w, rowY + 15, w, 21)`, label `boldSystemFontOfSize:14` white with the `#8091A6` `(0,−1)`
shadow — plus a 9×16 `MenuDisclosureIndicator` at x = 301. Tapping it pushes the boosters list, which
is the existing 49pt member row verbatim with the badge showing that person's boost count.

**Behaviour.** Tap a stat row: nothing. It is not a control, and per the interaction chapter silence
is the 2013 answer, so the rows are `selectionStyle = None` and do not light their
`CellHighlighted102` plate. The only tappable rows are the two boost rows. Scrolling is an ordinary
`UITableView` with `separatorStyle = None`; the whole screen is about a dozen cells, so it never
recycles anything interesting.

**Reuse.** `TGActionTableView`, `Cell102`, `CategoryDivider`, `Footer`, `DialogListUnreadBadge`,
`MenuDisclosureIndicator`, and the member row class the members screen already owns. No new cell
class beyond a two-label value cell, which is ~80 lines.

**Cost.** Roughly one controller of 300 lines, one cell of 80. Memory: the stats response itself
(a few kB of JSON) and nothing else — no bitmap, no path, no timer.

**Gives up.** All shape. "12 483 members, +214" tells you the direction but not whether the growth is
steady or was one spike on Tuesday. Anyone who wants that reads it in the desktop client.

---

## Option B — One sparkline per number

**File:** `svg/groups-channels-b.svg`

The same list, with a **graph row** inserted after each headline row. The graph row is an ordinary
51pt `Cell102` row whose content is drawn in `drawRect:` — a 1pt `#D5DEE5` baseline at the row's
bottom inset, then a single `CGPath` polyline in `#337ACC` at 1.5pt width across 7 daily points
spanning x = 10 to x = 310, plus a 2.5pt filled dot on the last point and the two end-day labels in
`systemFontOfSize:10` `#888888`. One series, no axes, no legend, no fill under the curve, no
interaction. Seven points, so the path has seven segments and the row draws in microseconds.

Boosts get a **level meter** built out of the group-button bar (chapter 4 of the controls file): five
28pt segments at height 30 on the row's right half, `ButtonGroupLeft_Highlighted` /
`ButtonGroupCenter_Highlighted` for reached levels and the plain `ButtonGroupCenter` /
`ButtonGroupRight` art for the rest, `ButtonGroupDivider` 2pt between them, numerals in
`boldSystemFontOfSize:12` white with the `rgba(#0E284D,0.4)` `(0,−1)` shadow. It is a display, not a
control — but it is made of the app's real button art rather than an invented progress bar, and the
row's left half spells out "14 of 20 boosts to level 4" in `systemFontOfSize:13` `#888888`.

**Behaviour.** Tapping a graph row pushes a plain list of the seven days with their numbers — the
"chart detail" reduced to a table, which is the only honest drill-down here. The graph row lights its
`CellHighlighted102` plate on touch like any other row. Rotating to landscape re-lays the path at the
new width; the row height does not change (layout chapter §6).

**Reuse.** Everything from Option A, plus `TGButtonGroupView` and its seven `ButtonGroup*` assets,
which the members screen already loads.

**Cost.** One extra cell subclass with a `drawRect:` (~120 lines) and a small day-detail controller
(~150). Memory: the cell's backing store is 320×51 at 2× = 130 kB per visible graph row, and at most
three are on screen, so under 400 kB. Redraw only on data arrival and rotation — no `CADisplayLink`,
no animation.

**Gives up.** Absolute scale. A sparkline with no y-axis tells you the shape, and the headline row
above tells you the total, but you cannot read a value off the curve. Multi-series comparisons
(members joined vs. left on the same axes) are not attempted at all.

---

## Option C — A real chart panel with a mode bar

**File:** `svg/groups-channels-c.svg`

The screen becomes a proper stats screen. Under the nav bar sits the members screen's own 44pt mode
bar — a `Footer` plate with a three-segment `TGButtonGroupView` inset 10pt a side, buttons 30pt tall
at y = 71, widths 98/98/100 with 2pt dividers — switching between **Growth**, **Top posters** and
**Boosts**. Below it a **128pt chart panel** (the sticker chapter's 128 maximum, reused so the number
is not invented): four hairline gridlines, `#E5E5E5` inside and `#D5DEE5` for the top and bottom
rules, y-labels right-aligned at x = 26 and x-labels at the ends and midpoint, all
`systemFontOfSize:10` `#888888`, and one `#337ACC` polyline over 30 daily points. Then a 26pt
`CategoryDivider` and the top-poster list.

A top-poster row is the existing **49pt member row** with one addition: a 4pt tall `#337ACC` bar at
`(54, rowY + 25, proportionalWidth, 4)` between the name and the subtitle, width scaled to the top
poster's count. That is the horizontal bar chart, and it costs one `UIView` per row. Count on the
right in `boldSystemFontOfSize:13` `#356596`, name in `systemFontOfSize:17` `#111111`, subtitle in
`systemFontOfSize:13` `#888888`, avatar 40pt at `(5, rowY + 4)` with corner radius 4 from
`+[TGIcons avatarWithInitials:size:colourId:]`.

**Behaviour.** The segments fire on `UIControlEventTouchDown` (controls chapter §4) and swap the
table's data source in place with `reloadData` — no animation, no paging scroll view, since there is
no interactive transition idiom available. Tapping a poster pushes the existing member-rights screen,
which is why member management and statistics end up on one screen rather than two. The chart panel is
a table header view, so it scrolls away with the content; it does not pin. There is **no** scrubber,
no pinch-zoom and no tap-to-inspect on the chart — a 30-point path redrawn per touch move on an A5
under a table view is the one thing this screen must not do.

**Reuse.** The members screen's mode bar wholesale, its member cell wholesale, `Cell102`,
`CategoryDivider`, `Footer`. The chart panel is the only genuinely new view.

**Cost.** A chart view of ~200 lines plus a controller of ~350 that owns three data sets. Memory: the
chart's backing store is 320×128 at 2× ≈ 327 kB, held for the lifetime of the screen; the three
datasets are a few kB. It is the only option that keeps a large bitmap alive while a table scrolls
over it, which on a 512 MB device with a chat open behind it is worth stating plainly.

**Gives up.** Nothing about the chart is inspectable — you get the shape and the axis labels, and that
is the whole contract. It also spends the most screen: after the nav bar, mode bar and chart panel
there are 244pt left, which is three member rows and a footer.

---

## Recommendation

**Option B.** Option A is the safe answer and it is genuinely defensible — it can be built in a day,
it can never be slow, and for a group admin the numbers *are* the point. But it throws away the one
thing a chart is actually for, which is telling a rise from a spike, and it does so to save a
`drawRect:` with seven line segments. That is too much caution.

Option C is the most complete screen and the one that reads as "statistics", but it commits a 327 kB
backing store and a bespoke chart view to a feature the catalogue has already marked blocked, and it
still cannot let you touch the chart, which is where most of the modern screen's value lives. B gets
the shape, keeps every row inside the 51pt idiom the rest of the app already uses, and needs no new
artwork or new layout concept — the graph row is just a cell that draws a line. If the boosts API
lands and the screen needs to grow, B's sections extend downwards without a redesign; C's chart panel
would have to be duplicated or tabbed.

---

## What genuinely cannot be built here

- **Telegram's interactive graphs.** Zoom, pan, the two-handle range scrubber, tap-to-reveal tooltip,
  and the drill-down chart that expands out of the main one. All of them need continuous re-tessellation
  of a multi-hundred-point path during a gesture. iOS 6.1.3 has no `CAShapeLayer` path animation worth
  using here and the A5 has one core shared with the chat list behind. Reduced version: a static
  polyline, and the day-by-day numbers as a pushed table (Option B) or nothing (Option A).
- **Stacked and multi-series charts** (joined vs. left, message types by kind). Two series on one
  320pt-wide axis at 1.5pt stroke are unreadable before they are slow. Reduced version: one series per
  section, one section per metric.
- **The pie / donut charts** the modern client uses for language and source breakdowns. There is no
  circular-chart precedent in the idiom and no asset for one; drawing arcs in code would be the first
  new visual primitive in the app. Reduced version: a list of rows with a percentage in the value slot.
- **Boost gifting, boost purchase, and any Stars or paid-message flow.** These are payment flows
  requiring an in-app-purchase or web-checkout surface; the catalogue marks paid messages blocked and
  that stands. We can *display* boost level and boost count, and list who boosted — nothing more.
- **Live-updating stats.** No pull-to-refresh exists anywhere in the 1.1 source (interaction chapter),
  so the screen loads once on `viewWillAppear:` and shows what it got. There is no toast or banner idiom
  to announce a refresh either.
- **Video chats in groups** (also marked blocked): a multi-party audio session with a participant grid
  is beyond both the codec budget and the missing `UICollectionView`.

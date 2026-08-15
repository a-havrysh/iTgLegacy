# Chat list organisation — folders, swipe actions, unread

Three answers to the same question: the 2013 app has one flat list of 73 pt rows and one swipe
button (Delete). Modern Telegram has folders, an archive, pinning, per-chat mute and a swipe menu.
Where does the folder switcher live on a 320×480 screen that is already spending 20 + 44 + 49 = 113
points on chrome?

Note on the rulebook: the three chapters do not agree here, and that is not an accident — each names
a different container. `layout-metrics.md` §7 says *"No fourth tab and no tab strip. Folders appear
as a chooser reached from the chat list header button"*; `interaction-patterns.md` says *"Switching
folder is a choice sheet raised from the chat-list title"*; `typography-colour.md` §5 says *"Render
the folder strip as a scope bar"* and gives the exact scope-button attributes. Options A, B and C
below are those three rulings drawn out, so the reader picks which chapter wins rather than
arbitrating from prose.

All three share the same swipe and unread treatment, described once at the end.

---

## Option A — Title-tap chooser (`chat-list-a.svg`)

**What it does.** The chat list keeps exactly the geometry it has today. The navigation-bar title
becomes the folder name plus a 10×6 pt white caret 6 pt after the last glyph of the name; the whole
title view is the tappable target (the original's title view is already a `UIView`, so this is a tap
recogniser on it, not new chrome). Tapping raises a `TGActionSheet` listing **All Chats**, **Unread**,
then the user's folders in server order, then `Common.Cancel` last. The current folder's row carries
a white checkmark at the right; folders with unread carry the chat-list badge art
(`DialogListUnreadBadge`, 27×21 pt, right inset 28) inside the sheet button. Choosing a row reloads
the same table with the new folder's chats.

**On tap and on scroll.** No paging, no gesture, no new scroll view: choosing a folder is
`[_model setFolder:]` + `reloadData`, with the table's `contentOffset` reset to 0. Scroll behaviour
is byte-for-byte what ships today. The nav bar never changes height, so nothing below it has to move.

**Reuses.** `TGActionSheet`, `TGDialogListCell` unchanged, `TGIcons headerButtonWithTitle:`,
`TGActionTableView` swipe machinery. The only new view is the caret, which is 8 lines of `drawRect:`.

**Costs.** Roughly 120 lines: a title-tap target, a sheet built from `updateChatFolders`, and one
per-folder `getChats` cursor. Memory cost is one extra array of chat ids per visited folder — a few
kilobytes. No extra image decoding, no second table.

**Gives up.** Folder switching costs two taps and covers the screen while you decide, so you cannot
see the list you are leaving. It scales badly past about six folders (a sheet with nine buttons on a
480 pt screen starts scrolling, which the 2013 sheet does badly). And there is no persistent
reminder of which folder you are in beyond the title word — easy to miss when the folder is called
something short.

---

## Option B — Scope-bar folder strip (`chat-list-b.svg`)

**What it does.** A 36 pt strip sits directly under the navigation bar, on `SearchBarBackground` art
with a 1 px `#D5DEE5` hairline at the bottom. Each folder is a `SearchBarScopeButton` (selected:
`_Highlighted`) 30 pt tall at y = 67, caption `boldSystemFontOfSize:12`, selected white with shadow
`rgba(#112E5C, 0.2)` at (0, −1), unselected `#5C708B` with shadow `rgba(#FFFFFF, 0.25)` at (0, +1) —
the exact `TGDialogListController.mm:511-521` attributes. Button width = caption width + 24, plus 18
pt for a badge when the folder has unread; buttons are laid out left to right at 4 pt gaps inside a
`UIScrollView` that pages horizontally when the folders overflow (the mockup shows the sixth folder
clipped at the right edge, which is the honest steady state for a user with five folders).
Unread counts inside the strip use the chat-list badge asset squeezed to its 27 pt minimum, or
narrower for single digits, with the `#8091A6` shadow.

**On tap and on scroll.** Tap swaps the selected art and reloads the table. The strip is **pinned**,
not part of the table header — it does not scroll away, so the list loses 36 pt permanently: four and
a bit rows visible instead of five. Swiping left/right across the list body can be wired to move one
folder along, but only as a discrete `reloadData` — there is no side-by-side paging, because two live
chat-list tables at once is two sets of decoded 56 pt avatars and the 4S will not hold them.

**Reuses.** The scope-button artwork and the search bar background already in `images/`, the badge
asset, `TGDialogListCell` unchanged.

**Costs.** Around 300 lines: a strip view with manual frame layout and measurement, a horizontal
`UIScrollView`, badge sizing, and selection state persistence. Memory is negligible (one scroll view,
n small buttons). The real cost is 36 pt of screen, permanently, for every user — including the ones
with no folders, unless you hide the strip whenever `updateChatFolders` returns fewer than two, which
is what I would do.

**Gives up.** A row of visible list. Also the strip and the search bar compete: with search revealed,
the top of the screen is 44 + 36 = 80 pt of blue-grey furniture above the first chat, which is a lot
on a 3.5-inch device.

---

## Option C — Folders as a place (`chat-list-c.svg`)

**What it does.** There is no switcher in the chat list at all. The Messages tab's root becomes a
**Folders** screen of 51 pt rows — 40 pt glyph tile at x = 5 (radius 4, drawn by
`+[TGIcons avatarWithInitials:size:colourId:]`-style flat glyphs, not photographs), title
`systemFontOfSize:19` `#111111` at x = 49, subtitle `systemFontOfSize:13` `#888888` beneath it,
unread badge right-inset 28 and a `MenuDisclosureIndicator` at 12 pt from the edge. Rows: All Chats,
Unread, each user folder, Archived; then a `CategoryDivider` and a 44 pt `#0779D0`
"Create New Folder" action row, and a `TGCommentMenuItemView` caption below. Tapping a row pushes the
ordinary chat list, whose back button reads the folder name.

Optionally — and this is the version I would ship if C won — the app remembers the last folder and
pushes straight into it on launch, so the Folders screen is one back-tap away rather than a
mandatory stop.

**On tap and on scroll.** Push and pop, the only transitions iOS 6 gives us. Each folder's chat list
is its own controller instance with its own scroll position, which is the one thing this option gets
for free that the other two have to fake.

**Reuses.** `Cell102` / `CellHighlighted102`, the 51 pt contact-cell geometry, `CategoryDivider`,
`MenuDisclosureIndicator` — literally the existing contacts screen with different content. The chat
list itself is untouched.

**Costs.** About 200 lines for the chooser controller, plus routing changes so the Messages tab has a
two-deep stack. Memory: one extra controller alive per pushed folder — but only one at a time, since
you pop back to switch.

**Gives up.** Switching folders is a pop plus a tap, the slowest of the three. It also puts a screen
between the user and their chats on cold launch unless the last-folder memory above is implemented.
The unread badge on the Messages tab now summarises a screen the user may never look at.

---

## Shared: swipe actions and unread organisation

The same in all three, so it is not a differentiator — but it is half the theme, so here are the
numbers.

**Swipe.** iOS 6 has no `UITableViewRowAction`; the cell draws its own buttons, as
`TGDialogListCell` already does for Delete. Buttons are **61 × 31 at y = 20** inside the 73 pt row,
right inset 10, 6 pt gaps, growing from a 2 pt stub at the right edge under `TGSwipeGestureRecognizer`.
Label `boldSystemFontOfSize:13` white, shadow `rgba(#A30F0A, 0.2)` at (0, −1) for the red one and the
matching dark tint of each other fill. Four buttons is the maximum that fits before the title is
covered, and four is already too many — ship **Mute / Pin / Delete** by default and let Archive
replace Pin on an already-pinned chat (option A's mockup shows all four to demonstrate the limit).
Only one cell's controls open at a time; opening a second closes the first, via
`TGActionTableViewDelegate dismissEditingControls`. Destruction still goes through the existing
route: Delete opens the two-button sheet (Clear History plain, Delete Chat red) per
`interaction-patterns.md` §2, or a `TGSnackbar` undo where the act is reversible.

**Unread.** Unchanged from 2013 and it already works: row background `#EBF0F5`, preview text `#5B646E`
instead of `#888888`, badge `DialogListUnreadBadge` at `CGRectMake(width - 28 - badgeWidth, 29,
badgeWidth, 21)` with a `boldSystemFontOfSize:14` white label and its `#8091A6` (0, −1) shadow. A
**muted** chat keeps its `#111111` title and only the badge greys —
`[[TGTheme shared] mutedBadgeColour]`, drawn in the mockups as `#A8B4C2`. A **pinned** chat draws the
same `#EBF0F5` ground with no extra chrome and no height change.

**Pinned reorder** is edit mode: tap Edit, the 30 × 30 delete-toggle slides in at x = 4 and the date
slides left by 32 (both already in `TGDialogListCell`), and reorder controls appear on pinned rows
only. `setPinnedChats` is committed as a diff on Done, not per drag.

---

## Recommendation

**Option A, with the strip from B as a later addition if folders prove popular.**

A costs nothing — no screen space, no new scroll view, no change to the cell or the table — and it is
the only one of the three that leaves the 2013 screen visually untouched, which matters when the
folder feature is optional and most users will have zero folders. The sheet is also the right
container by the app's own logic: `interaction-patterns.md` opens with "2013 Telegram never invented
a container when the system already had one", and a five-item mutually-exclusive choice is precisely
what `UIActionSheet` is for. B is the better *daily* interaction for a user who lives in three
folders, but it taxes every user 36 pt to serve that minority, and on a 3.5-inch screen a row of list
is expensive. C is the most orthodox port — it is the contacts screen with different rows — but it
makes the common case (open the app, read the top chat) slower than the original, which is the one
thing this project should not do.

If B is chosen, hide the strip entirely when the folder count is under two; that removes the
objection for everyone who does not use folders and makes it strictly better than A for everyone who
does.

## What cannot be built here

- **Swipe-to-page between folders with the lists moving together.** That needs two chat-list tables
  live at once, each holding decoded 56 pt avatars for its visible rows, plus an interactive
  transition. iOS 6 has no interactive view-controller transition, and 512 MB with one A5 core will
  not carry two live lists at 60 fps. Folder changes are discrete `reloadData` calls.
- **The modern folder tab strip with animated selection underline and elastic overscroll.** No
  `UICollectionView`, no spring animations in the idiom, and the rulebook forbids pill tabs outright.
  The scope bar in B is the reduced version: it swaps two PNGs instead of animating.
- **Folder icon picker as a grid.** No `UICollectionView` on iOS 6.1.3. It can be hand-laid tiles in
  a `UIScrollView` (64 pt cells, 4 columns), but the icon set itself does not exist as artwork in
  `images/` — someone must draw 20-odd glyphs at @2x before this feature is possible at all.
- **Shareable folder invite links and "new chats added to a shared folder" banners.** Buildable in
  principle (a modal form plus a 44 pt banner), but each is a nested chat multi-select editor. For a
  port targeting one phone, they are not worth the code; recommend cutting both and leaving folders
  local-to-device in behaviour even though the server syncs them.
- **Sponsored chats in search results** need impression tracking tied to scroll position plus a
  report sheet. Technically possible; recommend not implementing it at all.

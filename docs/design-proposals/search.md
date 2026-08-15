# Search — visual design options

Theme: scoped search, media filters, hashtags and result sectioning, on a 320 pt screen with no
modern segmented control.

Everything below is drawn against what already exists in `src/TGSearchViewController.m`, which
already has: a `UISearchBar` restyled with `SearchInputField.png` / `SearchBarIcon.png`, a 36 pt
floating scope bar (`kSearchScopeHeight`) built from `SearchBarScopeButton.png` /
`_Highlighted.png` with the exact `TGDialogListController.mm:511-521` text attributes, a 34 pt tag
strip (`kSearchTagStripHeight`), 51 pt result rows on `Cell102.png`, 25 pt section headers, and a
chat-type filter (All Chats / Private / Groups / Channels) presented as a `UIActionSheet`. So none
of these options is greenfield; they differ in *where the filter state lives* and *how much
vertical space it eats*.

The catalogue's design-bucket items in this area are: in-chat message search, in-chat search by
sender, date-range search, top/frequently-contacted peers, hashtag prefix autocomplete, Saved
Messages tag chips, jump-to-date calendar, downloaded-files search, media-grid fast scroller,
sticker search, live-location list, quote position. The three options answer the first six; the
rest are covered in the last section.

---

## Option A — One scope bar, everything else in a sheet (conservative)

`svg/search-a.svg`

**What it is.** Exactly the structure already in the repo, finished. A single 36 pt scope bar with
five buttons — All, Media, Links, Files, Voice — sitting directly under the 44 pt search bar,
floating over the table via `contentInset.top = 36` (the code already does this in
`applyScopeInset` / `positionFloatingViews`). Buttons are `SearchBarScopeButton.png` stretched with
`leftCapWidth = width/2, topCapHeight = 0`, 30 pt tall at y = 3 inside the bar, laid out at
6 pt edge padding with a 4 pt gap: widths 58/58/58/58/60, x = 6, 68, 130, 192, 254, the last one
absorbing the 2 pt remainder exactly like `TGButtonGroupView` does. Captions are
`boldSystemFontOfSize:12`, selected white with `rgba(#112E5C, 0.2)` shadow at `(0, -1)`,
unselected `#5C708B` with `rgba(#FFFFFF, 0.25)` at `(0, -1)`.

Everything that is *not* a media type — chat type (private/group/channel), date range, sender,
"only Saved Messages" — lives behind a single `Filter` header button on the right of the nav bar,
which opens a `UIActionSheet` (`TGActionSheet`, already in the repo). When any non-default filter
is on, the `Filter` button's caption becomes `Filter (2)` — the count of active filters — and that
is the only on-screen indication.

Results are sectioned with the existing 26 pt `CategoryDivider` header (`CategoryDividerFirst` for
index 0), label `boldSystemFontOfSize:15` in `#697487`, x = 10. Section order: Recent (empty query
only) → Chats → Contacts → Global search → Messages. Rows are 51 pt on `Cell102`, avatar 40 pt at
(5, 5) radius 4, title `systemFontOfSize:19` `#111111` at x = 54 with the matching substring in
bold 19, subtitle `systemFontOfSize:13` `#888888`, date right-aligned `systemFontOfSize:13`
`#337ACC` at right inset 9.

**Behaviour.** Tapping a scope button fires on `UIControlEventTouchDown` (group-bar rule) and
re-runs `searchMessages` with the filter string; the table is emptied and the 40 pt centred status
label shows "Searching…". Scrolling is plain: the scope bar is a subview of the table view kept
pinned by `scrollViewDidScroll`, so it never scrolls away — no extra work. Hashtags need no chrome
at all: a query starting with `#` or `$` (the existing `+isTagQuery:`) silently switches the
backing call to `searchPublicMessagesByTag`, the section header becomes "Public posts", and the
empty state lists `getSearchedForTags` as ordinary 44 pt text rows with a "Clear" button in the
header — the same treatment the 2013 app gave recent searches.

**Reuses.** The scope bar, tag detection, cell, section header and action sheet all already exist.
Net new code is roughly the sender picker (push the existing `TGGroupMembersViewController` in
selection mode) and a `UIDatePicker` sheet for the date range.

**Costs.** Essentially nothing new in memory: five `UIButton`s and one reused action sheet. Under
the 44 pt search bar, 36 pt of scope bar leaves 400 pt of list — seven full 51 pt rows.

**Gives up.** Active filters are invisible. A user who set "Groups, from Nadia, since 1 Aug" three
minutes ago sees only `Filter (3)` and has to reopen the sheet to remember what is on. That is the
real cost and it is not small.

---

## Option B — Scope bar plus a filter line of removable chips

`svg/search-b.svg`

**What it is.** Option A plus a second 34 pt line under the scope bar — the tag strip that already
exists as `kSearchTagStripHeight`, repurposed to hold active filters. Each chip is a
`SearchBarScopeButton_Highlighted.png` plate, **26 pt tall at y = 146** (4 pt inset in the 34 pt
line), caption `boldSystemFontOfSize:12` white with the `rgba(#112E5C, 0.2)` `(0, -1)` shadow, 10 pt
padding left, and a 13 pt bold `x` glyph 10 pt from the right edge. Chips are laid out left to
right with a 4 pt gap inside a horizontally scrolling `UIScrollView` (plain scroll view, no
collection view). The last chip is a 28 pt wide unselected plate carrying `+`, which opens the same
filter action sheet as Option A. Tapping a chip's `x` removes that filter and re-runs the query;
tapping the chip body reopens the sheet at that filter.

The same strip is what Saved Messages tag chips render into, so the reaction-tag feature and the
filter feature share one control. The scope bar's `scopeBarHeight` already sums both heights and
adjusts `contentInset`, so the strip appearing and disappearing is one existing call.

**Behaviour.** The strip only exists when at least one filter is on; when it does, the list's top
inset grows from 36 to 70 and the table shifts down without animation (the original never animated
a content inset change). Scrolling behaviour is identical to A — both lines are pinned. A hashtag
query adds a chip labelled `#redesign` instead of putting the tag in the field, if the user picked
it from autocomplete; typed tags stay in the field.

**Reuses.** Scope bar, tag strip, chip plate art, cell, section headers, the action sheet. New code:
the chip layout pass (measure caption at bold 12, width = 10 + textWidth + 6 + 10 + 10), plus
hit-testing the `x` region separately from the chip body.

**Costs.** One `UIScrollView` and at most five small buttons — trivial memory. The real cost is
vertical: 70 pt of chrome under the search bar leaves 366 pt of list, i.e. six full rows plus a
sliver, one row fewer than Option A. On a 480 pt screen that is a genuine loss.

**Gives up.** Row count, and a little of the period feel — 2013 Telegram never showed a chip rail.
It is defensible because the chips are the app's own scope-button art at scope-button size, but a
purist will see it as a 2016 idea rendered in 2013 clothes.

---

## Option C — Scope token in the field, filters on a pushed Options screen

`svg/search-c.svg`

**What it is.** No scope bar at all. The single most important scope — *which chat am I searching
in* — becomes a token inside the search field itself: a 22 pt tall
`SearchBarScopeButton_Highlighted.png` plate at x = 36 (right of `SearchBarIcon`), caption bold 12
white, trailing `x`, with the caret and the typed text starting 6 pt after it. Backspace on an
empty query deletes the token, exactly like Mail's address tokens on iOS 6. Everything else — media
type, chat type, date range, sender — lives on a pushed grouped screen behind an `Options` header
button: a `TGActionTableView` of 44 pt rows with `#516691` titles and `#356596` right-hand values
("Type — Any", "In — Groups", "From — Nadia", "Since — 1 Aug"), each pushing or sheeting its own
picker, and a green `GroupedActionButtonGreen` "Search" row at the bottom.

The result list therefore starts at y = 108 and gets the full 372 pt. Paging is a 44 pt closing row
on `Footer.png` reading "Show 42 more results" in `boldSystemFontOfSize:16` `#0779D0`, which is how
the global-search paging feature wants to be expressed anyway.

**Behaviour.** Typing re-queries as before. Tapping `Options`, changing something, and tapping back
re-runs the search and pops. Section headers are unchanged. The empty state has room for the
"Recent" section *and* the top-peers rail: a 74 pt tall horizontally scrolling strip of 56 pt
avatars (radius 5, the chat-list avatar family) with a 12 pt bold name under each, drawn in a plain
`UIScrollView` — it fits here only because nothing else is competing for the top of the screen.

**Reuses.** Search field styling, grouped table chrome, action button art, the 51 pt cell, section
headers. New code: token measurement and drawing inside the search field (the fiddliest part — you
must own the field's `leftView` and shift the text rect), and one small grouped view controller.

**Costs.** Cheap in memory; the pushed screen is created on demand. The token work is the risk:
`UISearchBar`'s internal `UITextField` is not a documented surface on iOS 6, and shifting its text
rect means subclassing or reaching for the subview — the repo already reaches for that subview in
`styleSearchInputField:`, so it is a known-quantity hack, but it is a hack.

**Gives up.** Media filters are now two taps and a screen away, which is the wrong cost for the
filter people use most. Discoverability of "Media/Links/Files" drops to near zero.

---

## In-chat search — shared across all three

The in-chat search chrome is the same in every option because there is only one sane answer on this
screen. Entering search from the conversation's `Search` menu item replaces the 44 pt navigation
title with the search field (the bar keeps its 44 pt height; no new bar), and a **44 pt navigator
bar** appears above the keyboard, matching the search-bar height and the "any new top-aligned
banner" ruling: a `TGButtonGroupView` of two 30 pt buttons at the right (`ButtonGroupLeft` up-arrow,
`ButtonGroupRight` down-arrow, `ButtonGroupDivider` between, 80 pt nominal width each, right inset
5), and at the left, x = 10, a `systemFontOfSize:13` `#697487` label reading "3 of 128" — or
"No results" in the same colour. A `from:` sender chip, when set, sits between them as the same
26 pt chip Option B defines. Tapping an arrow scrolls the conversation to the next matching message
and paints it with the unread wash `rgba(#003871, 0.07)` for one second. Date jumping is a
`UIDatePicker` in an action sheet from a small calendar glyph in the navigator, not a heat-grid
calendar.

---

## Recommendation

**Option B.** Option A is the honest baseline and it is already 80 % built, but its one real defect
— invisible filter state — is exactly the defect that makes people distrust a search screen, and
the fix costs one strip that the code already has a constant and a layout slot for. Option C wins
the most list rows and has the most elegant idea in the token, but it buries the media filters,
which are the filters people actually reach for, behind a push, and it puts the riskiest UIKit hack
in the app on the most-used screen.

Build B as A first: ship the five-button scope bar and the filter sheet, then add the chip line as
a second step, since `scopeBarHeight` already returns the sum and the table inset already follows
it. If the chip line proves to cost too much vertical space in real use, deleting it returns you to
Option A with no other change.

---

## What genuinely cannot be built here

- **Sticker and emoji search** (catalogue: "Sticker / sticker set / emoji search"). A results grid
  of animated stickers needs continuous decode of many TGS/WebP frames at once. There is no
  `UICollectionView` and, more decisively, no headroom: 512 MB total, one A5 core, and the sticker
  panel already competes with the conversation's image cache. A static-thumbnail grid of installed
  sets is buildable; searching the whole public sticker catalogue with previews is not.
- **Media-grid fast-scroll date bubble** (`getChatSparseMessagePositions`). Technically possible,
  but it requires a floating overlay tracking a custom scroll indicator during momentum scrolling;
  on a 320x480 grid the whole scroll range is a few screens, so it buys nothing and costs frame
  time on a device that has none to spare. Recommend dropping it, not designing it.
- **Jump-to-date heat calendar** (`getChatMessageCalendar`). The month grid with per-day message
  density is a hand-drawn view with no analogue in the 2013 language and needs a modal transition
  richer than push-or-modal to feel right. The reduced version — a `UIDatePicker` in an action sheet
  calling `getChatMessageByDate` — is what the in-chat navigator above proposes, and it gives up the
  density shading and the "which days have messages" preview.
- **Downloaded-files search.** Not a hardware limit: there is no download manager in this client, so
  `searchFileDownloads` has nothing to search. It should stay out until that exists.
- **Public post search, sponsored results, story search, nearby chats, secret-chat search.** Blocked
  in the catalogue for non-visual reasons (Stars payments, ad reporting, a story viewer this
  hardware cannot sustain, a discontinued server feature, and absent E2E sessions respectively).
  No mockup can rescue any of them.
- **Interactive swipe-to-dismiss on the search screen.** iOS 6 has no interactive view-controller
  transitions. Search is entered by push and left by the back button or Cancel, full stop.

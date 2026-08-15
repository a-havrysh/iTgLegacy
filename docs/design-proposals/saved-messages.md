# Saved Messages — visual design options

Theme: Saved Messages grew two things the 2013 app has no vocabulary for — **topics** (the saved
stream split by where each message came from) and **tags** (emoji reactions on your own saved
messages, used as folders). The original had neither. It had a self-chat that happened to be named
after you, and that is all.

The catalogue's design-bucket items in this area are: the topics list, topic history, pin/unpin and
reorder topics, tags list and display, tagging a message, filtering by tag / searching within saved,
per-topic drafts, jump-to-date, and pinned messages inside Saved Messages. Custom-emoji tags and the
Premium limit raise are already marked `blocked` and stay blocked — see the last section.

The three options below differ in **what tapping "Saved Messages" opens**, which is the only decision
that really matters. Everything else follows from it.

---

## Option A — It stays a chat; tags are a scope bar (conservative)

`svg/saved-messages-a.svg`

**What it is.** Saved Messages opens the ordinary conversation controller, exactly as it does today —
wallpaper, `Msg_Out` bubbles, 45 pt input panel, the whole 2013 screen unchanged. Two additions:

* A **36 pt tag strip** directly under the nav bar, built out of `SearchBarScopeButton.png` /
  `_Highlighted.png` stretched with `leftCapWidth = width/2, topCapHeight = 0`, buttons 30 pt tall at
  y = 3 inside the strip, 6 pt edge padding, 4 pt gaps. Captions are `boldSystemFontOfSize:12`,
  selected white with `rgba(#112E5C, 0.2)` shadow at `(0, -1)`, unselected `#5C708B` with
  `rgba(#FFFFFF, 0.25)` — the exact `TGDialogListController.mm:511-521` attributes the repo's search
  scope bar already uses. The strip scrolls horizontally in a `UIScrollView` when the tags overflow
  320 pt. Leftmost chip is always "All"; rightmost is a fixed 28 pt "+" chip that opens the tag
  picker. The emoji is drawn at 14 pt, 11 pt left of the caption, inside the chip.
* A **tag chip inside the bubble**, on its own row 4 pt under the last line of body text, timestamp
  pushed to the line below — the reaction-row ruling from the layout chapter, but 20 pt tall rather
  than 22 and using the same `SearchBarScopeButton` art so the chip in the bubble and the chip in the
  strip are visibly the same object. 6 pt inner padding each side, 4 pt between chips.

Topics are **not a screen** here. The nav bar's right button is `From`, and it opens a `UIActionSheet`
listing the top eight origins by saved count ("Alice Kovalenko 7", "Design Team 12", "My Notes 31",
"Hidden Author 3", …) plus "All". Picking one is the same filtered-stream mechanism the tag chips use.

**Behaviour.** Tapping a chip fires on `UIControlEventTouchDown` and switches the message source from
`getChatHistory` to `searchSavedMessages(tag:)`; the bubble list is emptied and reloaded from the
`FoundChatMessages` pager, the input panel stays live (typing in a filtered view sends an untagged
message and drops you back to "All"). Long-pressing a chip is the `setSavedMessagesTagLabel` rename —
a `UIAlertView` with `alertViewStyle = UIAlertViewStylePlainTextInput`, which is what iOS 6 has.
Scrolling is unchanged; the strip is a sibling of the table pinned by frame, not a floating header, so
there is no `contentInset` dance and no scroll-linked layout to get wrong. Long-pressing a bubble adds
"Tag…" to the existing message action sheet, opening a plain 4-column emoji grid (64 pt cells, the
sticker-picker tiling ruling) as a modal.

**Reuses.** The conversation controller in full. `SearchBarScopeButton` art and the scope-bar text
attributes from `TGSearchViewController`. The existing message action sheet. `addMessageReaction` is
already wrapped.

**Cost.** Smallest of the three. One new 36 pt strip view, one new in-bubble chip row in the message
item layout, one filtered loading path in the conversation data source, one emoji grid modal. Memory
cost is a handful of stretched `UIImage`s that UIKit caches anyway; the filtered stream reuses the same
message cell pool, so peak memory is unchanged.

**What it gives up.** Topics as a first-class place. There is no per-topic unread count, no pinning,
no per-topic draft, and no "Saved from" browsing — you get an origin *filter*, not an origin *inbox*.
It also spends 36 pt of the chat's vertical space permanently, which on a 480 pt screen with the
keyboard up is real: bubble area drops to about 155 pt.

---

## Option B — Saved Messages opens a chat list of topics

`svg/saved-messages-b.svg`

**What it is.** Tapping Saved Messages pushes a second chat-list-shaped screen: 44 pt search bar,
26 pt `CategoryDivider` section headers ("Pinned", "Saved from"), and **73 pt rows** with the exact
`TGDialogListCell` geometry — avatar `CGRectMake(8, 8, 56, 56)` radius 5, text column at x = 73, title
`boldSystemFontOfSize:16` `#111111`, two preview lines `systemFontOfSize:14` `#888888` (`#536C8C` for
a media placeholder like "Photo"), date `systemFontOfSize:13` `#337ACC` right-inset 9, and the
`DialogListUnreadBadge` at `CGRectMake(width - 28 - badgeWidth, 29, badgeWidth, 21)` carrying the
message count in that topic rather than an unread count. Pinned rows draw the `#EBF0F5` background,
per the pinned-chat ruling — no extra icon, no extra chrome.

Row identity comes straight from the topic type: `savedMessagesTopicTypeMyNotes` becomes a fixed glyph
avatar ("My Notes", bookmark on `#0F94ED`, produced by `+[TGIcons savedMessagesAvatarOfSide:56]`),
`savedMessagesTopicTypeSavedFromChat` uses that chat's avatar and title,
`savedMessagesTopicTypeAuthorHidden` gets the grey `#8B97A5` placeholder and the literal title
"Hidden Author".

Tapping a row pushes the conversation controller in topic mode — same screen as Option A, including
Option A's tag strip, but paging `getSavedMessagesTopicHistory` instead of `getChatHistory`.

**Behaviour.** Swipe left on a row gives the 61x31 delete button at y 20 the chat list already draws;
long-press opens an action sheet with Pin / Unpin, Clear History, Delete Topic. `Edit` in the nav bar
turns on table edit mode for pin reordering — the only genuinely new plumbing, since the 2013 chat
list has no reorder mode. Updates arrive as `updateSavedMessagesTopic` / `updateSavedMessagesTopicCount`
and are applied as single-row reloads, not full reloads, otherwise the A5 stutters on a busy account.
Scrolling is a plain `UITableView` with the standard cell reuse; 73 pt rows mean about seven visible.

**Reuses.** `TGDialogListCell` almost verbatim — the cell can be subclassed rather than rewritten,
because a topic row is structurally a chat row with a count where the unread badge goes.
`CategoryDivider` headers, the search bar, the swipe-delete art, the pinned background colour.

**Cost.** A new list controller plus a topic model and an incremental-update reducer. Memory: one more
view controller on the stack (the chat list itself stays alive underneath), plus a topic array — a few
hundred small objects at worst. Real but bounded.

**What it gives up.** The 2013 truth that Saved Messages *is* a chat. A user who saves twelve things a
year now has to walk through a list of four rows to reach them, and the compose bar — the thing that
made the self-chat a scratchpad — is one level further away. It also means two loading paths in the
conversation controller forever.

---

## Option C — Tags become the sections of a digest list

`svg/saved-messages-c.svg`

**What it is.** Saved Messages opens a **browsable list of saved messages grouped by tag**. Section
headers are the 26 pt `CategoryDivider` strip with the tag emoji at x = 17 (drawn 14 pt, vertically
centred), the tag label in `boldSystemFontOfSize:15` `#697487` at x = 30, and the count right-aligned
at inset 10 in `systemFontOfSize:13` `#697487`. Rows are 73 pt with the chat-list geometry, but the
avatar and title are the message's **origin** (who you saved it from) and the two preview lines are the
message itself. Untagged saved messages fall into a final "Untagged" section.

The nav bar's right button is `Chat`, which pushes the real self-chat — the 2013 screen, unchanged,
with the compose bar — so nothing is lost, it is just one tap away instead of zero.

**Behaviour.** Tapping a row pushes the self-chat scrolled to that message, using the same
message-anchored open the search results already do. Swipe left on a row offers "Untag". Long-press a
section header offers Rename (the `UIAlertView` text-field prompt) and "Show only this". The search bar
at the top drives `searchSavedMessages` across every tag; typing collapses the sections into one flat
"Results" section. Sections are collapsible by tapping the header — the header keeps its position and
the count stays visible, which is the cheapest way to make twenty tags navigable in 480 pt.

**Reuses.** The chat-list cell and the category divider, same as B. The search field. No new artwork at
all.

**Cost.** Comparable to B, but the data model is flatter: one array of `(tag, messages)` fetched from
`getSavedMessagesTags` plus one `searchSavedMessages` per section as it comes into view. That per-section
paging is the risk — twenty tags means twenty pagers, and on a single-core A5 you must cap it (load the
first eight messages per tag eagerly, page the rest only when the section is expanded).

**What it gives up.** Topics entirely. There is no origin grouping, no per-topic pin, no per-topic draft.
It also inverts the model: in real Telegram, tags filter a *chat*; here they define a *list*, so a
message with two tags appears twice. That is defensible for browsing but it will surprise anyone who
knows the modern app.

---

## Recommendation

**Option A, with Option B added later as a second screen behind the `From` button.**

A is the right first answer because it is the only one that does not contradict the source material.
In 2013 Saved Messages was a chat, and the single most valuable thing about it — type a note, it is
saved — is destroyed the moment you put a list in front of it. A adds the one modern concept that maps
cleanly onto an existing 2013 control (tags → scope bar, which is exactly how the rulebook already says
to render chat folders) and leaves everything else alone. It is also the cheapest by a wide margin and
carries no new loading path in the conversation controller beyond the one that tag filtering needs
anyway.

B is the correct *eventual* shape for a heavy account, and its row art is free because a topic row is a
chat row. But it should be reached from A rather than replacing it: change the `From` action sheet into
a push of the topics list once the list exists, and the two options compose instead of competing. C is
the most interesting reading of the feature and the prettiest screenshot, but the duplicate-message
consequence of tags-as-sections is a real correctness wart, and it throws topics away for good.

---

## What genuinely cannot be built here

* **Custom-emoji tags.** Already `blocked` in the catalogue and it should stay blocked. They need TGS /
  Lottie playback of an animated sticker inside a 20 pt chip; a single-core A5 with 512 MB cannot run
  that on a scrolling list, and there is no static fallback frame available without decoding the
  animation first. Plain unicode emoji tags cover the feature.
* **Premium pinned-topic limit raise and the premium tag features.** Server-side entitlement. The client
  can only show the error, so there is nothing to design.
* **Drag-to-reorder pinned topics with a live floating row.** iOS 6's `UITableView` reordering gives you
  the grab-handle edit mode and nothing else — no lifted, shadowed row following the finger, no
  auto-scroll at the edges worth the name. Option B's reorder is the plain 1980s handle-drag, and the
  proposal should not pretend otherwise.
* **A gesture-driven interactive back swipe** from a topic to the topics list. No interactive
  transitions on iOS 6; it is a push and a Back button.
* **The modern tag-strip-that-floats-over-blurred-content look.** No `UIVisualEffectView`, no vibrancy.
  The strip is opaque `SearchBarBackground.png` art and it occupies its 36 pt honestly.
* **Jump-to-date as a fast scrubber.** `getChatSparseMessagePositions` exists, but a scrubber that
  re-queries as the thumb moves will thrash the A5 and the TDLib socket. The buildable version is a
  "Jump to date…" action-sheet row opening a `UIDatePicker` in date mode — one query, one scroll. The
  continuous scrubber is out.

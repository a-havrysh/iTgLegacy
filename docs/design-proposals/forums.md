# Forum topics

**The question.** A forum is a list of topics that behaves like a chat list but lives *inside* one
chat. iOS 6 gives us push navigation and nothing else — no tab strip of live histories, no
gesture-driven back, no collection view. So the whole design problem is: when the user is looking at
a list of topic rows, how do they know they are one level down inside a group, and how do they get
back out without feeling lost?

All three options answer that with the same navigation spine, and differ only in how loudly the
parent is stated on the child screen:

```
Chats  ──push──▶  Topics of "iOS Developers"  ──push──▶  "Bug Reports" transcript
```

The back button of the topics screen reads **Chats**; the back button of the topic transcript reads
**Topics**. That two-step chain is the hierarchy, and it is free — `TGViewController` already puts
the parent's short title into the `BackButton` art. Everything below is about the first screen.

What is common to all three:

- Rows are pushed with `TGChatViewController` in topic mode (`forumTopicId` set); the transcript's
  navigation title is the topic name, its subtitle line is the group name in `#c9dcf2` at
  `systemFontOfSize:13` — the second half of the breadcrumb.
- Long-press on a row opens a `TGActionSheet` (`title:nil`) carrying Mark as read / Mute / Pin /
  Edit / Close / Copy link, with Delete as the single `destructiveButtonIndex` row and Cancel last.
  That covers eight catalogue entries with no new chrome at all.
- The right bar button is a `HeaderButton` reading **New** (49×30 at x = 266, y = 27, label
  `boldSystemFontOfSize:12` white with the `(0,-1)` shadow), shown only when
  `can_create_topics`. It presents the create form modally per the modal-form rules
  (grouped table, Cancel left, Done right bold): one 44 pt name row and one 44 pt row of six colour
  swatches, 28 pt circles at a `floorf((300 - 6*28)/7)` gutter, the chosen one carrying `ListCheck`.
- Topic icons are drawn in code from `icon.color` — a filled rounded rect with the first letter of
  the name in white bold, no network fetch, no emoji. The catalogue calls for a *circle*; the
  rulebook says avatars in this app are rounded rects, never circles, so I follow the rulebook:
  56 pt slot at radius 5, 40 pt slot at radius 4. General gets a `#` glyph instead of a letter.
- A closed topic pushes normally but the transcript hides the input panel and shows the 44 pt
  banner treatment in its place, reading "This topic is closed".

---

## Option A — The chat list, one level down (`forums-a.svg`)

**What it does.** The topics screen *is* the chat list, verbatim: `DialogListCell` art, 73 pt rows,
56 pt icon at (8, 8) radius 5, title `boldSystemFontOfSize:16` `#111111` at x = 73, two-line preview
with the bold `#345f8f` author prefix and `#888888` body, date `systemFontOfSize:13` `#337acc` at
right inset 9, `DialogListUnreadBadge` at `CGRectMake(width - 28 - badgeWidth, 29, badgeWidth, 21)`
with a `boldSystemFontOfSize:14` count. Pinned topics draw the `#ebf0f5` background exactly as a
pinned chat does and sort above the rest. A muted topic gets the 13 pt `DialogList_Muted` glyph at
`titleRight + 3, titleY + 6`. A closed topic states "Topic closed by Dmitry" in the action colour
`#536c8c` on the preview's first line.

The hierarchy is stated entirely in the navigation bar: title = group name at bold 16, subtitle =
"24 topics" at 13 `#c9dcf2`, back button = **Chats**.

**Tapped and scrolled.** Tap pushes the topic transcript. Long-press opens the action sheet. Swipe
left on a row reuses the chat-list swipe button (61×31 at y 20, right inset 10) — here it reads
Delete and is shown only with `can_delete_messages`. Scrolling to the last row fires the next
`getForumTopics` page using the three offsets; five and a half rows fit on screen, so a 24-topic
forum is five flicks.

**Reuses.** `TGDialogListCell` almost unchanged (the avatar becomes a drawn colour tile, the "Alice:"
prefix stays), `TGTopicsViewController`'s existing table, `TGActionSheet`, `TGIcons` header buttons.

**Cost.** Perhaps 200 lines beyond what `TGTopicsViewController.m` already has, plus the create form.
Memory is the chat list's: one cell per visible row, ~6 live cells, drawn icons cached in a small
`NSMutableDictionary` keyed by `color<<8|firstLetter` so 24 topics share maybe four images.

**Gives up.** It looks *identical* to the chat list, which is the whole point and also the risk: a
user who lands here by a notification tap sees rows that read like separate chats. The nav bar is
doing all the work of saying "you are inside iOS Developers", and the nav bar is small.

---

## Option B — A compact index (`forums-b.svg`)

**What it does.** Deliberately *not* the chat list. Rows shrink to the 51 pt contact-cell geometry:
40 pt icon at (5, 5) radius 4, text column at x = 49, title `systemFontOfSize:19` (`boldSystemFontOfSize:19`
while unread) `#111111`, one-line preview at `systemFontOfSize:13` `#888888`, date 13 `#337acc` at
right inset 9, badge 21 pt tall right-aligned at `width - 28 - badgeWidth`, and a 1 px `#D5DEE5`
hairline from x = 49 to the right edge drawn by the cell. A 44 pt search bar sits above the table and
re-runs `getForumTopics` with a query string. Pinned topics live in their own section under a 26 pt
`CategoryDividerFirst` strip captioned "Pinned"; the rest sit under a `CategoryDivider` captioned
"Topics".

The hierarchy is stated by *shape*: this screen does not look like the chat list, so it cannot be
mistaken for it. Seven and a half rows fit instead of five and a half, which matters because a real
forum has thirty topics, not six.

**Tapped and scrolled.** Identical push and action sheet to A. Typing in the search field filters
server-side; the divider sections collapse into a single unlabelled list while a query is active,
matching how the chat-list search behaves.

**Reuses.** `TGContactCell` metrics and its highlight treatment (`#E9EFF5` background with `#D5DEE5`
hairlines above and below), `CategoryDivider` art, the chat-list badge, `TGSearchBar`.

**Cost.** A new cell class, because the contact cell has no date, no badge and no mute glyph — call it
250–300 lines. Cheaper per row at scroll time than A (no two-line preview layout, no author-prefix
measuring), which on an A5 is a real gain in a long list.

**Gives up.** The two-line preview. You see who spoke and roughly what about, not the message. Also
gives up the emotional cue that a topic is a place where conversation happens — it reads like a
table of contents, which some readers will call correct and others will call cold.

---

## Option C — The parent card (`forums-c.svg`)

**What it does.** Option A's 73 pt rows, but the table gets an 86 pt header cell copied from the
profile header: group avatar 70×70 at (9, 14) radius 10, name at x = 94 in `boldSystemFontOfSize:19`
`#222932` with the `rgba(#EDF0F5,0.28)` `(0,+1)` shadow, status line at x = 94 y = 52 in
`systemFontOfSize:14` `#6D7D90` reading "1 245 members, 24 topics", a `MenuDisclosureIndicator` at
right inset 12, and a `#D5DEE5` hairline at the bottom. Tapping the header pushes the group profile.
The navigation title reduces to the plain word **Topics**.

The hierarchy is stated *on the content surface*, not in the chrome: the group is physically the
first thing in the list, with the topics indented beneath it in meaning if not in pixels. It also
gives the forum a door back into its own group info, which A and B have to hide inside a right bar
button they cannot spare (the right button is already New).

**Tapped and scrolled.** The header scrolls away with the table — it is `tableHeaderView`, not a
pinned bar, because a sticky header on iOS 6 means a second view and manual offset tracking every
frame. Once scrolled off, the screen is Option A and the nav title "Topics" is thin. That is the
honest weakness.

**Reuses.** `TGProfileController`'s header layout code and `TGDialogListCell`; nothing new is drawn.

**Cost.** Between A and B — the header is a static view, ~120 lines. It costs one 70 pt avatar in
memory and four rows of list instead of five and a half on the first screenful.

**Gives up.** Vertical space, on a screen where a forum wants to show as many topics as possible; and
it duplicates the group profile screen's top third, which some will read as redundant.

---

## Recommendation

**Option A, with Option C's header adopted later if the screen tests as confusing.**

The reason is the rulebook's own governing rule: 2013 Telegram never invented a container when one
existed. A forum genuinely *is* a chat list — the same unread counts, the same last-message preview,
the same swipe, the same sort order. Building it as anything else costs a cell class and buys a
distinction the navigation bar already draws. And the "it looks like the chat list" objection is
weaker than it sounds: the back button says Chats, the title says the group name, the subtitle says
"24 topics", and there is no tab bar at the bottom — three simultaneous signals that this is not the
root list. A user is never more than one visible cue away from knowing where they are.

Option B is the right answer only if forums in practice run to fifty or eighty topics, at which point
density beats richness and the search bar stops being decorative. That is a data question we cannot
answer yet, and B can be swapped in later without touching the navigation or the action sheet.

---

## What genuinely cannot be built here

- **The topic tabs strip above the transcript.** The modern client keeps several topic histories
  resident and pages between them horizontally. That needs `UICollectionView` (absent on iOS 6.1) and
  several simultaneously loaded message models on 512 MB with one A5 core. Not feasible; the pushed
  topic list replaces it. The catalogue already marks this one blocked and I agree.
- **Animated (TGS/Lottie) custom-emoji topic icons.** Rendering a Lottie frame per row per frame is
  out of reach. Static WEBP thumbnails of a custom emoji are viable (we ship `UIImage+WebP`) but must
  be decoded once, downscaled to 56 or 40 pt and cached to disk; the animation is dropped to a still
  first frame. Setting one also requires Premium, so the drawn colour tile is the real default.
- **Interactive swipe-from-edge back.** iOS 6 has no interactive pop, so the two-level chain
  Chats → Topics → Topic costs two deliberate button taps to escape. Nothing can fix this; it is why
  all three options spend so much of their design budget on the back button's label.
- **A sticky "you are in iOS Developers" bar that survives scrolling.** Possible in principle as a
  second view with manual `contentOffset` tracking, but it means laying out a view on every scroll
  callback of a fast-flicking list on an A5, and it eats 44 of 416 usable points permanently. Option C
  is the affordable version of that idea: same information, scrolls away.
- **Drag-to-reorder pinned topics.** `UITableView` editing-mode reordering exists on iOS 6 and works,
  but combined with our custom-drawn cells and the swipe-delete button it is a genuine tangle. Pin and
  unpin ship; `setPinnedForumTopics` reordering is a later pass, and the list stays sorted by last
  activity within the pinned section until then.

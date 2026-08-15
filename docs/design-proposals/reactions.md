# Reactions on a message — three ways

The question: a message has eleven reactions spread over four emoji. How does a 2013 bubble show
that, and how does the user add a reaction, given that the bubble metrics are fixed and there is no
context menu in this idiom?

Three answers below. All three assume the same shared machinery, which is described once at the end
(the reactor list, the picker strip, the icon cache), so the options differ only in what happens
inside or beneath the bubble.

A note on the rulebook before anything else, because the two chapters that mention chips disagree
and every agent building this will trip over it:

* `typography-colour.md` §5 says a chip is `MediaActionButton.png` stretched, 22 pt tall, label bold
  13 in `#506E8D`.
* `layout-metrics.md` §7 says the row is 20 pt tall, chips 20 pt, radius 4, emoji 14, count bold 12.
* `interaction-patterns.md` "How to render a modern concept" says chip height 20, radius 10,
  padding 7, gap 4, emoji 13, count bold 11, fill = the bubble's own `_Selected` art.

I have followed the **interaction-patterns** numbers throughout, because that chapter is the one
that also fixes the picker and the menu ordering, so following it keeps chip and picker consistent.
Two further points had to be settled and are settled the same way in all three options:

* `MediaActionButton.png` **does not exist in `images/`**. I checked. Any proposal built on it would
  not compile, so the chip fill is `Msg_In_Selected.png` / `Msg_Out_Selected.png` (measured:
  `#DEF0FF` and `#AEF57C`) as the interaction chapter says.
* The chapter says the chip you picked uses the `_High_Selected` variant. I sampled those files:
  `Msg_In_High_Selected` is `#E3F2FF → #D9EDFF` and `Msg_In_Selected` is a flat `#DEF0FF`. The
  difference is a two-percent gradient — invisible at 20 pt. **Ruling for this area:** the chosen
  chip keeps the same fill and gains a 1 px `#0779D0` border with its count in `#0779D0` bold 11
  instead of `#506E8D`. That is a real, visible chosen state built entirely from colours already in
  the palette.

---

## Option A — Chips inside the bubble (`reactions-a.svg`)

**What it does.** The four reactions become four chips on a row inside the bubble, laid out in the
bubble's own text column, 4 pt under the last line of text, with the timestamp pushed to the line
below. Each chip is 20 pt tall, radius 10, fill `#DEF0FF` (incoming) or `#AEF57C` (outgoing),
7 pt padding either side, 4 pt between chips; the emoji icon is drawn 14×14 and the count is
`boldSystemFontOfSize:11` in `#506E8D`, 3 pt after the icon. Your own reaction — 👍 in the mockup —
carries the `#0779D0` border and blue count. A chip is therefore about 42 pt wide for a single-digit
count, so four chips are 172 pt and fit inside a full-width bubble's 226 pt text column with room to
spare; five or more wrap to a second 20 pt row with a 3 pt gap, and the bubble grows by 23 pt.

**Tapping.** Tap a chip to toggle that reaction (`addMessageReaction` / `removeMessageReaction`),
optimistically bumping the count locally and reconciling on `updateMessageInteractionInfo`. The chip
you added animates in as a 0.15 s fade, nothing else. Tap and hold a chip, or tap the emoji run's
empty tail, to open the reactor list.

**Adding.** Long-press the bubble → `TGPopupMenu` with **React** as its first item (glyph `"react"`,
as the rulebook mandates) → the emoji strip drawn in the mockup: `TGMenuView` metrics exactly,
height 41, 44 pt per button, `MenuButtonLeft/Center/Right` with `MenuButtonSeparator` between,
`MenuArrowBottom` pointing at the message, six emoji visible at 24 pt and the strip scrolls
horizontally past six. Double-tapping a bubble applies the quick reaction directly with `is_big:YES`.

**Reuses.** `TGReactionPickerView` (already in `src/` — it has the 41/44/24 strip, the chip
constants, the icon downscale cache and the reactor list), `TGPopupMenu`, the existing bubble
`_Selected` artwork, `TGClient+Reactions`.

**Costs.** This is the expensive one in the message cell. `ChatViewCell` is frame-based, so chips
inside the bubble mean the bubble's own height calculation takes reactions as an input, and
`heightForRowAtIndexPath:` must reproduce that calculation exactly or the table scrolls wrong. Hit
testing has to resolve a point to a chip index. Memory is small: one 14 pt icon per distinct emoji,
cached globally, roughly 8 KB each at @2x.

**Gives up.** The bubble is no longer "text and a timestamp"; every media bubble, sticker, voice
note and forwarded header now has a reactions case in its layout. Wrapped chips can make a
three-word message twice as tall as its text.

---

## Option B — One summary line and a badge (`reactions-b.svg`)

**What it does.** No chips. Under the last line of text sits a single 20 pt line: the distinct emoji
drawn at 14 pt on a 20 pt pitch, at most five of them, then `+N` in bold 11 `#506E8D` if there are
more, then the **total** — eleven — in a `DialogListUnreadBadge` stretched to fit, 21 pt tall, 27 pt
minimum width, cap insets half the art, label `boldSystemFontOfSize:14` white with the `#8091A6`
shadow at `(0, -1)`. Exactly the chat list's unread badge, doing exactly the job it already does:
"this many". The emoji you chose is drawn first in the run, sitting on a 20×20 `#DEF0FF` rounded
rect at radius 4, which is the only per-emoji decoration on the line.

**Tapping.** The whole line is one target and it opens the reactor list. It never toggles. Removing
your own reaction is done from the picker strip, where your current emoji is drawn pressed.

**Adding.** Identical to A: long-press → `TGPopupMenu`, **React** first, then the strip. The mockup
shows the menu instead of the strip so both halves of the flow are visible across the option set.

**Reuses.** `DialogListUnreadBadge` and its stretch code verbatim, `TGPopupMenu`,
`TGReactionPickerView`'s icon cache. It is the smallest amount of new drawing of the three.

**Costs.** The cheapest by a wide margin. The line is **always exactly 20 pt**, whatever the
reaction count, so the height calculation is `hasReactions ? 24 : 0` — a constant, which a
frame-based cell can absorb without risk. One view, one hit target, no per-chip geometry, no
wrapping. Memory identical to A.

**Gives up.** Per-emoji counts. You can see that eleven people reacted and which four emoji they
used, but not that five of them were 👍 — that costs one tap to the list. You also lose
tap-to-toggle from the bubble, which is the fastest path in every modern client. And the unread
badge is blue; on a message where you did not react, a bright blue badge is a slightly louder
signal than the content deserves.

---

## Option C — Chips in the gutter, bubble untouched (`reactions-c.svg`)

**What it does.** Takes the constraint at its word: the bubble metrics are fixed, so nothing goes in
the bubble. The chips sit in the wallpaper beneath it — same 20 pt chip, radius 10, padding 7, gap
4 — left-aligned to the bubble's left edge for incoming, right-aligned to its right edge for
outgoing, 4 pt below the bubble, and the row's 24 pt is added to the **cell** height, not the
bubble's. Chip fill is the bubble's *normal* fill (`#FBFBFB` / `#D3FBB1`) with the bubble's own
hairline, so the chips read as small satellites of the message rather than as things floating on the
wallpaper. The row ends with a 24 pt wide `+` chip in bold 15 `#506E8D`.

**Tapping.** Chips toggle as in A. The `+` chip opens the emoji strip anchored to itself — **one
tap, no long press**, which is the real reason to choose this option. Tap and hold any chip opens the
reactor list.

**Also drawn.** The floating unread-reactions button from the catalogue: a 30×30 disc at right inset
8, sitting 8 pt above the input panel, bubble-fill with the same hairline, a 16 pt heart glyph and a
`DialogListUnreadBadge` overhanging its top-right corner. Tapping it runs `searchChatMessages` with
`searchMessagesFilterUnreadReaction` and scrolls to the next one; it hides itself at zero and calls
`readAllChatReactions` when the last one is consumed.

**Reuses.** Bubble artwork, `DialogListUnreadBadge`, `TGReactionPickerView`. Notably it does **not**
touch bubble layout at all, which in a frame-laid cell is the single largest source of regressions.

**Costs.** One extra subview per reacted row and 24 pt of cell height. The `+` chip means every
reacted message advertises an affordance, which is more chrome on screen than 2013 would ever have
shown. The floating button is a second new view with its own show/hide logic and paging.

**Gives up.** Contrast. A near-white chip on a light wallpaper is weaker than the same chip on the
bubble's selected fill, and on a user-chosen dark wallpaper the hairline is all that separates them.
It also spends the most vertical space, so a run of reacted messages in a busy group scrolls
noticeably longer. And the `+` chip is an invention with no 2013 precedent at all — the honest cost
of getting single-tap adding.

---

## Recommendation

**Option A**, with one borrowing from C.

A is the rulebook's own answer, it is the one every other agent's chapter cross-references, and most
of it already exists in `TGReactionPickerView` — the constants in that file (`kChipHeight 20`,
`kChipPadding 7`, `kChipGap 4`, `kChipEmojiFontSize 13`, `kChipCountFontSize 11`) are precisely
option A. Building anything else means arguing with code that is already written. It is also the
only option that answers the actual question fully in the bubble: four chips, four counts, one of
them visibly mine, and a toggle under every one of them.

The borrowing: adopt C's floating unread-reactions button as-is. It is independent of the chip
question, it is the only sane home for the jump-to-next-reaction feature on a 320×480 screen, and it
does not compete with anything in A.

If cell-height bugs prove intractable — and in a frame-based `ChatViewCell` that is a real
possibility, not a hedge — **fall back to B**, whose constant 20 pt line makes the height arithmetic
unbreakable. Do not fall back to C: it trades bubble-layout risk for contrast problems on user
wallpapers, which is a worse deal.

### The parts all three share

* **Reactor list** (`getMessageAddedReactions`). A pushed, not modal, `UITableView` titled
  "11 Reactions", `separatorStyle` none, 51 pt rows, 40 pt avatar at `(5, 5)` radius 4, name at
  x = 49 in system 19, the reactor's emoji drawn 20×20 at right inset 9. Filtering by emoji is a
  **choice sheet** raised from a header button (`TGActionSheet`, one button per emoji with its
  count, `Common.Cancel` last) — not a segmented control and not filter tabs, per
  `interaction-patterns.md` §1. Pages 50 at a time on scroll-to-bottom; the loading row is 50 pt.
* **Emoji icons.** `emojiReaction.static_icon` only, downloaded once, decoded on a low-priority
  queue, downscaled to 28 pt and cached in a global dictionary keyed by emoji — the code already in
  `TGReactionPickerView.m`. Never keep the TGS files.
* **Ordering.** Chips and the emoji run follow the server's order in `messageReactions`, which is by
  descending count; do not re-sort locally or chips will reshuffle on every update.

---

## What genuinely cannot be built here

* **Animated reaction effects.** Every appear/select/activate/around asset is TGS, i.e. gzipped
  Lottie. There is no Lottie renderer for iOS 6 and a single-core A5 will not render vector
  animation at frame rate. Static icons only; the 0.15 s fade is the entire animation budget.
* **Custom emoji reactions.** They need Premium to send and their icons are animated custom-emoji
  stickers. Incoming ones can at best be drawn as a generic star chip with the right count.
* **Paid (star) reactions.** Sending requires a Stars balance topped up through in-app purchase,
  which a sideloaded build cannot perform. The top-paid-reactors avatar row is technically drawable
  read-only, but it is a second new avatar row for a feature the user can never participate in — I
  would leave it out.
* **Story reactions and live-story reactions.** There is no story viewer on this client and there
  will not be one on a 4S.
* **Saved Messages reaction tags.** Premium-gated server-side; the strip would always be empty.
* **Reaction statistics graphs.** Modern clients render these in a WebView-backed chart component;
  iOS 6 has only `UIWebView` and hand-drawing the charts is disproportionate.
* **A long-press-free add path in options A and B.** Without a context menu, the only 2013-legal
  entry points are `TGPopupMenu` (long press) and a double-tap quick reaction. Option C's `+` chip
  buys single-tap adding, and it buys it by inventing a control. There is no version of this that is
  both discoverable at one tap and archaeologically honest — pick which one you want.

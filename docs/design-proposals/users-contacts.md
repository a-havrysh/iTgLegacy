# Profiles and identity

How do profile accent colours, emoji status, birthdays and personal channels read on the 2013
profile screen? The honest answer is that three of the four are *values*, and this idiom already
has an excellent way of showing a value: a 44 pt grouped row with a `#516691` bold-17 title on the
left and a `#356596` regular-16 value on the right. The interesting question is only how much
identity is allowed to escape the table and reach the 86 pt header, because the header is the only
place on this screen where a design can say something about a person rather than list a fact.

The three options below answer that at three different volumes. All of them keep the existing
`TGProfileViewController` header geometry from `layout-metrics.md` §4: header container 86 pt,
avatar 70×70 at (9, 14) with corner radius 10, name at x = 94 y = 24, status at x = 94 y = 52,
right inset 9.

Sample data throughout: Anna Petrova, @annapetrova, a Christmas-tree emoji status expiring at
22:00, a birthday on 11 February, and a personal channel called Petrova Photo.

---

## Option A — Everything is a row (`users-contacts-a.svg`)

**What it does.** Identity is expressed entirely through the existing components. The header is
untouched except for one addition: the emoji status glyph is drawn at `systemFontOfSize:15`, 4 pt
after the last glyph of the name, baseline-aligned with it — the exact placement the rulebook gives
the verified badge in `typography-colour.md` §5, only with an emoji instead of a drawn glyph.
The accent colour appears in one place and one place only: it selects which of the eight identity
colours (`#EE4928 #41A903 #E09602 #0F94ED #8F3BF7 #FC4380 #00A1C4 #EB7002`) fills the letter
avatar, replacing the `MD5(uid + selfUid) % 8` result. Here Anna has picked index 3, so her tile is
`#0F94ED` and her in-bubble author name in every group chat becomes `#0F94ED` too, because the
rulebook requires one colour per person everywhere.

Below the header, one grouped section of four 44 pt rows: mobile, username, status, birthday. The
status row's value is `until 22:00` right-aligned at inset 10 with the emoji at 16 pt immediately
to its right, so the emoji is the last thing before the edge and reads as the value's icon. The
birthday row's value is `11 February  (turns 29)`; the age parenthetical is dropped when the year
is not shared. A second single-row group carries the personal channel: a 28×28 r3 channel avatar at
x = 18, title in `#0779D0` bold 17 (the tappable-row colour), the word `channel` in `#888888` 14 at
the right, and `MenuDisclosureIndicator.png` beyond it. A comment view underneath, `systemFontOfSize:14`
`#697487` with the `#DAE0E8` (0, +1) shadow, says whose channel it is.

**Behaviour.** Tapping the status row does nothing on someone else's profile and opens the emoji
picker on your own. Tapping birthday does nothing on someone else's profile; on your own it pushes
a date picker; long-press on someone else's offers "Suggest a birthdate". Tapping the channel row
pushes the channel's chat with a normal `pushViewController:animated:`. Scrolling is one plain
`UITableView`, so it scrolls at 60 fps with the cells the app already recycles.

**Reuses.** `TGActionTableView`, `TGVariantMenuItemCell`, `TGCommentMenuItem`,
`+[TGIcons avatarWithInitials:size:colourId:]`, `GroupedActionButton.png`,
`MenuDisclosureIndicator.png`. Zero new cell classes.

**Cost.** Roughly 60 lines in `TGProfileViewController.m` plus two `TGClient+Contacts` wrappers
(`setPersonalChat`, `getSuitablePersonalChats`). Memory cost is one extra `NSString` per row and
one emoji glyph rendered into the existing name label's superview.

**Gives up.** The accent colour is invisible unless you happen to look at the avatar, and a user
with a photo avatar loses it entirely. The personal channel is a name, not a preview — you cannot
see what the channel is about without opening it. Emoji status is decoration rather than something
you can tap to learn what it means.

---

## Option B — Identity header (`users-contacts-b.svg`)

**What it does.** The header grows from 86 pt to 118 pt and becomes the identity surface. The
accent colour tints the header's vertical gradient (a very light wash — here `#F7F2FE` to `#E6E2F0`
for accent 4, computed as the accent blended 6 % and 14 % into `#FBFCFD`/`#E7EBF0`) and paints a
solid 3 pt rule along the header's bottom edge in the full accent, replacing the usual 1 px
`#A9B0B7` hairline. That rule is the whole accent-colour idea: a coloured edge, not a coloured
surface. The avatar tile takes the same accent.

Under the name and status, at x = 94 and y = 70 inside the header, sits a chip row: 22 pt tall
chips on `GroupedActionButton.png` stretched with `leftCapWidth = width / 2, topCapHeight = 0`,
6 pt padding either side, 4 pt between chips, label `boldSystemFontOfSize:13` in `#506E8D` with a
`rgba(#FFFFFF, 0.7)` (0, +1) shadow — the reaction-chip recipe from `typography-colour.md` §5,
reused verbatim. The first chip is the emoji status and its expiry; the second is the birthday. If
a chip does not apply it is simply absent and the others slide left; if neither applies the header
collapses back to 86 pt. A bio line in `systemFontOfSize:13` `#697487` closes the header. The
premium/verified badge stays a 9×9 pt drawn glyph in `#0E7ACD` after the name, never a pill.

**Behaviour.** Chips are real buttons with an 8 pt touch inset. Tapping the status chip shows a
`TGAlertView` naming the emoji pack and when the status expires; tapping the birthday chip on
someone else's profile offers "Send a gift" if Stars are on, otherwise nothing; on your own profile
both chips push their editors. The header does not scroll away — it is the table header view, so it
scrolls with the content exactly as today.

**Reuses.** The whole existing header, `GroupedActionButton.png`, the reaction-chip drawing code if
it exists by then, the grouped table for everything below.

**Cost.** One new view class of about 120 lines (chip layout is a single left-to-right pass with
`sizeWithFont:`), plus a header-height computation that has to run before the table lays out. About
2 KB of extra live objects. No extra image decodes; the chips are one stretched PNG each.

**Gives up.** 32 pt of vertical space, which on a 480 pt screen is most of a row. The accent wash is
subtle enough that on some accents (the pale ones, `#E09602`, `#00A1C4`) it is barely readable as a
colour at all, and the rulebook forbids the obvious fix of tinting the name. Chips are a slightly
foreign shape for a header — they belong in bubbles — and a reader who knows the original will feel
it.

---

## Option C — Channel preview card (`users-contacts-c.svg`)

**What it does.** Takes the catalogue at its word that "rendering the linked channel's most recent
post inside the profile screen is genuinely new layout", and makes that post the point of the
screen. The header stays at 86 pt and the emoji status stays a 15 pt glyph after the name, as in
Option A. Directly under the header, when today is the person's birthday, a 25 pt strip in `#E4E9F0`
(the sticky section-header colour, with its `#D5DEE5` hairline) runs the full width: a 14 pt cake
emoji at x = 10, `Birthday today — turns 29` in `boldSystemFontOfSize:14` `#697487`, and `Send gift`
in `boldSystemFontOfSize:13` `#0779D0` right-aligned at inset 10. On any other day the strip is not
built at all and the birthday is a plain value row.

The personal channel becomes a full-bleed 73 pt row drawn with `DialogListCell.png`, laid out with
the chat-list cell's exact metrics: 56×56 r5 avatar at (8, 8), text column at x = 73, title
`boldSystemFontOfSize:16` `#111111`, two lines of post preview in `systemFontOfSize:14` `#888888`
with a 10 pt right inset, date `systemFontOfSize:13` `#337ACC` at right inset 9, and
`DialogListArrow.png` at the far right. It is literally a chat-list row parked inside the profile,
which is why it costs almost nothing and why it reads instantly. A `#697487` comment label above it
says `Personal channel`.

**Behaviour.** Tapping the card highlights with `DialogListCellHighlighted.png` and pushes the
channel. Tapping `Send gift` opens the gifts flow. The card's preview text comes from the same
chat-list preview builder, so media posts render as `Photo` in `#536C8C` exactly as they do in the
list. If the channel's latest post has not loaded yet the card shows the title and an empty preview
rather than a spinner.

**Reuses.** `TGDialogListCell` almost unchanged — the biggest single reuse of any option here —
plus the chat-list preview text builder and the highlight artwork.

**Cost.** The lowest of the three for what it delivers, maybe 80 lines, because the cell already
exists. The real cost is one extra `getChatHistory` call with limit 1 per profile open, and holding
one more chat's last message in memory. On a 512 MB device that is nothing, but it is a network
round trip on every profile you open, so it must be cached and must not block the rest of the screen.

**Gives up.** The accent colour, almost entirely — it is only the avatar tile, same as Option A.
The full-bleed white card breaks the grouped-table rhythm; the screen becomes grouped, then plain,
then grouped again, which the original never does on a profile. And the birthday strip only earns
its 25 pt one day a year.

---

## Recommendation

**Option C, with Option A's row treatment for everything it does not cover.** The personal channel
is the only one of these four features that is genuinely a piece of content rather than a value, and
it is the only one that justifies new layout; Option C gets it for near-free by reusing the chat-list
cell, which is also why it will look right the first time it renders on the device. Emoji status and
birthday are values and belong in rows, where Option A already puts them well.

Option B is the one I would build second if the accent colour turns out to matter to people. Its
chip row is defensible and its accent rule is the most honest way to show a colour in an idiom that
has no tint system, but 32 pt of header on a 480 pt screen is a real price and the wash is weak on
half the palette. Option A alone is too quiet: it is correct and it is invisible, and a screen where
four identity features are indistinguishable from a phone number has not really answered the question.

---

## What cannot be built on this hardware

* **Animated emoji status.** A premium status is a video sticker (WEBM/VP9) or a Lottie animation
  looping continuously in the header. There is no VP9 decoder on an A5, and running the existing
  `TGLottieView` in a loop behind a scrolling table burns the single core. The static thumbnail —
  `thumbFileId` on the badge dictionary the profile already fetches — is the only version that
  ships. Tapping it can play one cycle in a modal; it cannot loop in place.
* **Gradient profile accent colours.** Modern accent identities are two- and three-stop gradients
  applied to name text, reply bars and the profile ground. The rulebook forbids tinting the name at
  all, and a per-profile `CAGradientLayer` under a scrolling table view is a per-frame rasterise the
  A5 cannot afford. Every option here reduces the accent to one flat colour drawn from the eight.
* **Profile background patterns / custom wallpapers on the header.** Same reason, plus the memory:
  a full-width patterned header image per profile is a 320×118 pt decode held for the life of the
  screen, on a device that already struggles to keep two chats in memory.
* **The main-profile-tab strip (Posts / Gifts / Media).** Not a hardware limit but a framework one:
  there is no `UICollectionView` on iOS 6 and no gesture-driven paging between view controllers, so
  a swipeable tabbed profile means hand-rolling a paging `UIScrollView` of three tables and paying
  for three of them at once. The reduced version that fits is what the profile already does — a
  disclosure row per section that pushes a normal list.
* **A stretchy, parallax, blur-behind profile header.** No `UIVisualEffectView`, no vibrancy, and
  the original's header is a static table header view. Do not propose it.

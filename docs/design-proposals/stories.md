# Stories on a 320×480 screen

Stories are a full-screen, gesture-driven, video-first format built for a 6-inch phone with a
120 Hz display and interactive view-controller transitions. None of that exists here. iOS 6.1.3 on
an iPhone 4S gives us push and modal transitions only, no interactive dismissal, no blur, one core
and 512 MB of RAM. So the question is not "how do we shrink the story viewer" but "what is left of
stories when you remove the gestures, the transitions and most of the video".

What survives is: a photo, a poster's name, a caption, a position indicator, a way to go forward and
back, and a way to reply or react. That is the payload. Everything else in the modern format is
motion design.

The client layer is already done — `src/TGClient+Stories.h` wraps the whole surface, including the
ruling that only the **low-quality alternative video** file id is ever exposed, so a 4S is never
asked to fetch the main-quality H.264. Every option below assumes that header and adds only UI.

The three options differ on two axes at once: **where the entry point lives**, and **how honest the
viewer is about not being a modern story player**.

---

## Option A — Pushed story viewer with full chrome (`stories-a.svg`)

**What it does.** The viewer is an ordinary pushed `UIViewController` inside the existing navigation
stack. It keeps the blue navigation bar: `BackButton` on the left titled with the previous screen,
a two-line title (poster name in `boldSystemFontOfSize:16` white, `2 of 5 · 3 h ago` in
`systemFontOfSize:13` `#E0EEFD` — the conversation-controller title idiom, verbatim), and a
`HeaderButton` "More" on the right at `x = 320 − 52 − 5`, `y = 27`, 30 pt tall.

Directly under the bar, at `y = 66`, sits the position strip: five 3 pt bars, each 60 pt wide with a
2 pt gap, inset 4 pt from each edge (`x = 4, 66, 128, 190, 252`). Seen stories are solid white, unseen
are white at 0.3 alpha. It is a **position** indicator, not a timer — nothing auto-advances, because
a 5 s per-story timer on a device that may still be decoding the next JPEG produces a viewer that
skips stories the user never saw.

The photo is letterboxed on black: 9:16 fitted into the content area gives `200 × 356` at `x = 60,
y = 76`. The caption sits on a `rgba(0,0,0,0.45)` plate over the bottom 50 pt of the photo, text in
`systemFontOfSize:15` white, two lines maximum, tail-truncated; tapping the plate pushes a plain
scrolling caption screen when the text is longer.

The footer is a `TGButtonGroupView` (§4 of the components chapter): `ButtonGroupLeft` /
`ButtonGroupCenter` / `ButtonGroupRight` with `ButtonGroupDivider` seams, height **30**, at
`y = 440`, `x = 10`, width 300 split 100 / 96 / 100. Labels are `boldSystemFontOfSize:12` white with
the standard `rgba(0x0e284d,0.4)` `(0,−1)` shadow: `Reply`, `♥ 12`, `Share`. For your own stories the
middle segment becomes `👁 1 240` and opens the viewers table.

**Behaviour.** Tap the right 40 % of the photo → next story; left 40 % → previous. Past the last
story of a poster, the next tap moves to the next poster in the tray order, exactly like a page in a
list — no transition, just a content swap with a 0.15 s cross-fade of the image view. Back leaves the
viewer. `openStory:` fires on every page turn and `closeStory:` on the way out, which is what keeps
the read state right. There is no swipe-down-to-dismiss because there is no interactive dismissal on
iOS 6; the Back button is the dismissal. `Reply` presents the modal composer form (§4 of the
interaction chapter) and sends via `-replyToStory:inChat:text:`. `More` raises a `TGActionSheet` with
Save to Photos / Hide Stories from … / Report / (own story) Delete.

Its entry point is the cheapest possible one: **a single 73 pt row pinned at the top of the chat
list**, `DialogListCell` plate, avatar slot carrying the newest poster's avatar, title `Stories` in
bold 16 `#111111`, preview line `Alena, Dmitri and 4 more` in 14 `#536C8C`, and a
`DialogListUnreadBadge` (27 × 21, right-aligned at `width − 28 − badgeWidth`, `y = 29`) with the
count of posters with unread stories. It pushes a 73 pt-row list of posters, and that pushes the
viewer.

**Reuses.** `TGActionSheet`, `TGButtonGroupView` art, `DialogListCell`, `DialogListUnreadBadge`,
`TGRemoteImageView`, `TGImageDecode`, the modal-form composer, `TGProgressWindow`. One new
controller, one new cell type, no new artwork.

**Cost.** Roughly 600 lines: the viewer controller plus the poster list. Memory: one decoded photo at
screen size (~0.6 MB at 640×1136 RGBA after downscale) plus one prefetched neighbour, so budget under
2 MB. Nothing is retained per poster except the flattened dictionaries.

**Gives up.** The immersive full-bleed look: 64 pt of blue chrome sits over every story, and the photo
is letterboxed rather than filling the screen. It also gives up auto-advance, so watching 11 stories
is 11 taps.

---

## Option B — Ring tray above the chat list, black modal viewer (`stories-b.svg`)

**What it does.** This is the option that looks like the feature the reader knows. A **82 pt tray**
sits between the navigation bar and the first chat row, background `#E4E9F0` (the sticky-strip
colour) with a 1 px `#D5DEE5` hairline at the bottom. It is a `UIScrollView` with hand-framed
subviews — no `UICollectionView` exists here — recycled through `TGViewRecycler`.

Each tray cell is 68 pt wide (56 pt avatar + 12 pt gutter), first cell at `x = 8`. The avatar is the
standard 56 pt rounded rect at radius 5 (`avatar56`), and the unread ring is a **2 pt stroked rounded
rect** of `60 × 60` at radius 7 drawn 2 pt outside it — the ring follows the avatar's own corner, it
is not a circle, because nothing in this app is a circle. Unread ring `#0779D0`; already-seen ring
`#C3CBD6`. The name goes under the avatar in `systemFontOfSize:11`, `#111111` unread / `#888888`
seen, centred and truncated. The first cell is always **My Story**: an empty `#DFE4EB` plate with a
`+`, which opens the photo composer.

The viewer this tray opens is a **black full-screen modal** (`presentViewController:animated:`,
`wantsFullScreenLayout`, status bar hidden): timed segmented progress at the top, a 30 pt avatar plus
name plus `3 h ago` overlaid at `y = 8`, a close `×` at the top right, the photo filling the screen,
the caption on a dark plate at the bottom, and a `ConversationInputPanel`-plated reply field with a
heart button pinned above the keyboard.

**Behaviour.** The tray scrolls horizontally; the chat list scrolls under it as normal (the tray is
the table's `tableHeaderView`, so it scrolls away with the content rather than sticking — a pinned
header would need a second scroll view and a second `contentInset` dance). Tapping a poster opens the
modal at that poster's first unread story. Photo stories auto-advance after 5 s; video stories play
the low-quality alternative through `AVPlayer` and advance on end. Tap right / left to page; the
close button dismisses.

**Reuses.** The chat-list controller, `TGViewRecycler`, `TGRemoteImageView`, `TGIcons` avatar
generation, `ConversationInputPanel` art. The ring, the tray layout, the timer and the modal are all
new.

**Cost.** The largest of the three: ~1100 lines and a new asynchronous avatar-loading path for the
tray. Memory is the real cost — the tray holds up to five decoded 56 pt avatars plus the chat list's
own, and the modal keeps a decoded full-screen image plus an `AVPlayerItem`. Expect 6–8 MB resident
while the viewer is open, and expect to tear the tray's images down in
`didReceiveMemoryWarning`. The timer is also a correctness risk: on a cold cache the 5 s tick will
regularly expire before the photo has been fetched, so the timer must start on *decode complete*,
not on page turn.

**Gives up.** Vertical space — 82 pt is more than one chat row, permanently, on a 480 pt screen. And
it gives up the honesty of the other two: the modal promises a modern player and then cannot deliver
swipe-down-to-close, pinch, hold-to-pause done properly, or reliable video.

---

## Option C — Stories as a read-only conversation (`stories-c.svg`) — the conservative one

**What it does.** There is no viewer and no tray. Stories arrive in a **pseudo-chat named "Stories"**
that sits in the chat list like any other row, with the ordinary unread badge. Opening it opens
`TGChatViewController` in a read-only mode against a synthetic message list built from
`-activeStoriesForChat:completion:` across every poster.

Each story is one incoming bubble, laid out exactly like a group-chat message: 30 pt author avatar at
`x = 4` aligned to the bubble's bottom, `Msg_In` bubble stretched (`leftCapWidth:20 topCapHeight:15`)
starting at `x = 38`, author name in `boldSystemFontOfSize:13` `#4D688C`, the story photo as a
thumbnail inside the bubble at up to `120 × 140`, the caption under it in `systemFontOfSize:15`
`#141617`, and the timestamp in `systemFontOfSize:11` `#232D37` at the bubble's bottom right. Video
stories carry the standard duration plate in the thumbnail's top-left, 10 pt bold white. Reactions
appear as the existing chip row. A `Today` service plate separates days.

**Behaviour.** Tapping a thumbnail opens the photo in the media viewer the app already has, which is
where `openStory:` / `closeStory:` fire. Long-pressing a bubble raises `TGPopupMenu` with
`React` → `Reply` → `Hide from …` → `Report`, in the existing order; Reply pushes the poster's real
private chat with the reply-to-story header pre-set. Scrolling is scrolling — a `UITableView` of
bubbles, nothing else. There is no composer at the bottom, which is the visual statement that this
chat is not addressable.

**Reuses.** Almost everything: `TGChatViewController`, `ChatViewCell`, the bubble assets, the media
viewer, `TGPopupMenu`, `TGReactionPickerView`, the chat-list row. The only genuinely new code is the
adapter that turns the active-stories dictionaries into the message model the chat view already
consumes, plus one read-only flag.

**Cost.** By far the smallest: ~250 lines, most of it the adapter. Memory is whatever the chat view
already costs, with thumbnails downscaled to 120 pt before display. No timers, no player, no new
window.

**Gives up.** The format. Nobody will mistake this for stories: it is a digest. There is no unread
ring, no full-screen presentation, no sense of "watching". Chronology across posters is flattened into
one stream, so you cannot watch one person's five stories in a row without scrolling past other
people's. Posting is still available but lives in Settings → My Stories rather than in a `+` avatar
anyone will find.

---

## Recommendation

**Option A**, with the tray from Option B as a later, optional addition.

A is the only one that is both recognisable as stories and honest about the hardware. Keeping the
navigation bar is not a compromise forced on us — it is the correct answer, because dismissal on iOS 6
has to be a button, and the navigation bar is where this app's dismissal button lives. Putting a black
modal on screen and then handing the user a `×` in the corner is strictly worse than a `Back` button
in the place they already look for one. Position bars instead of timer bars is the second honest call:
the moment the network is slow, an auto-advancing viewer starts silently skipping content, and this
device's network is often slow.

The entry point should be A's chat-list row rather than B's tray, at least first. The tray costs 82 pt
of a 480 pt screen and a per-poster avatar decode on every chat-list appearance, and it earns that
cost only if the user actually has stories most days. The row costs 73 pt, appears only when the story
list is non-empty, and is built from a cell that already exists. If the feature proves itself, promote
the row to the tray — the viewer does not change either way, which is the point of separating the two
decisions.

C is worth keeping on the table as a fallback if the viewer turns out to be unaffordable: it delivers
the actual content, reactions, and replies for a quarter of the code. It is the wrong shape but the
right information.

---

## What genuinely cannot be built here

- **Live stories (RTMP / group-call based).** Requires the WebRTC stack and real-time video decode.
  Not achievable on an A5 under iOS 6. The tray must render a live poster as an ordinary unread ring
  and the viewer must show a one-button `UIAlertView` saying the story cannot be played.
- **Posting a video story.** Capture works; trimming and transcoding to the story profile does not.
  There is no usable trimming stack on iOS 6 inside 512 MB, and the upload sizes are impractical over
  the connections this device sees. The composer stays photo-only.
- **Story statistics.** `getStoryStatistics` returns `StatisticalGraph` JSON intended for a charting
  web view. There is no `WKWebView` on iOS 6 and no charting code in this client.
- **Stealth mode and custom expiration.** Both are server-side Premium gates; the calls exist but
  return errors without a subscription. Do not draw the rows.
- **Business-account stories.** Needs a business connection and a connected bot; irrelevant here.
- **Interactive dismissal, hold-to-pause with a rubber-band, pinch-to-zoom the story, the
  scale-from-avatar open transition, and the cube page turn.** iOS 6 has no interactive
  view-controller transitions and no `UIPercentDrivenInteractiveTransition`. Every one of these is
  replaced by a tap or a button, or dropped.
- **Reliable video story playback in general.** It is drawn in the options as a duration-plated
  thumbnail and it should be attempted only against the low-quality alternative file that
  `TGClient+Stories` exposes. Treat a failure to play as normal and fall back to the still cover
  rather than showing an error each time.
- **A story-authoring canvas** (draggable stickers, drawn text, placed location and reaction areas).
  Reading `storyArea` rectangles and hit-testing them is fine — it is percentage arithmetic over the
  photo frame. Authoring them is a drag-and-rotate direct-manipulation editor, which is neither in
  this idiom nor within this CPU budget. Areas are read-only.

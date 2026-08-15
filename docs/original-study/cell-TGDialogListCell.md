# TGDialogListCell — the chat list row

Study of the original component as shipped in Telegram for iOS v1.1 (build 21024).

Sources, all paths relative to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`:

- `TelegraphKit/TelegraphKit/TGDialogListCell.h` (75 lines) — public surface
- `TelegraphKit/TelegraphKit/TGDialogListCell.m` (1607 lines) — the cell and its private
  `TGDialogListTextView`
- `TelegraphKit/TelegraphKit/TGDialogListCellAssetsSource.h` — the theming protocol
- `TelegraphKit/TelegraphKit/TGDialogListController.mm` — the only call site
- `Telegraph/Telegraph/TGInterfaceAssets.mm` — the single concrete assets source
- `Telegraph/Telegraph/Resources/*.png` — artwork

The class exists under exactly that name; no substitution was needed.

---

## 1. What it is

One row of the chat list. A 73-point-tall `UITableViewCell` subclass that shows, in one glance:
avatar, conversation title, last-message preview (or a typing line), the message author when the
conversation is a group, a date, an outgoing delivery mark, an unread-count badge, and a mute icon.
It also owns its own swipe-to-delete affordance and its own editing switch, because in 2013 UIKit
gave you neither in a form the designer wanted.

Two design decisions dominate the whole file and explain most of the odd-looking numbers:

1. **All the text is drawn by hand in one custom view.** `TGDialogListTextView`
   (`TGDialogListCell.m:148-306`) is a single opaque `UIView` whose `drawRect:` paints title,
   preview, author name, typing line and the group/secret glyph. There is no `UILabel` for any of
   them. The cell computes four `CGRect`s in `layoutSubviews` and hands them to the text view as
   `titleFrame` / `textFrame` / `authorNameFrame` / `typingFrame`
   (`TGDialogListCell.m:1375-1376`, `1343`, `1357`). On an A5 this is the difference between a
   scrolling list and a stuttering one: one opaque layer instead of five blended ones.
2. **Everything is recomputed only when the cell's size changes.** `layoutSubviews` guards its
   entire body with `if (!CGSizeEqualToSize(_validSize, size))` (`TGDialogListCell.m:1269`), and
   any content change invalidates it by assigning `_validSize = CGSizeZero`
   (`:1134`, `:630`, `:702`, `:1402`). Get this wrong and the list re-measures strings on every
   frame.

---

## 2. Public surface

From `TGDialogListCell.h`:

| Group | Properties |
| --- | --- |
| identity | `reuseTag`, `conversationId` (`:23-24`) |
| text | `titleText`, `messageText`, `messageAttachments`, `users` (`:26-29`) |
| state | `date`, `outgoing`, `unread`, `deliveryState`, `unreadCount`, `serviceUnreadCount` (`:31-36`) |
| avatar | `avatarUrl`, `isOnline` (`:38-39`) |
| flags | `isMuted` (`:41`), `isGroupChat` + `groupChatAvatarCount` + `groupChatAvatarUrls` (`:43-45`) |
| secret chats | `isEncrypted`, `encryptionStatus`, `encryptedUserId`, `encryptionOutgoing`, `encryptionFirstName` (`:47-51`) |
| group preview | `authorName` (`:53`) |
| live | `typingString` (`:55`) |
| editing | `editingButton`, `enableEditing` (`:57-59`) |
| theming | `assetsSource` (`:19`) |
| callbacks | `watcherHandle` (`:21`) — an `ASHandle`, the project's weak-delegate broadcast object |

Methods: `-initWithStyle:reuseIdentifier:assetsSource:` (`:61`), `-collectCachedPhotos:` (`:63`),
`-setTypingString:animated:` (`:65`), `-restartAnimations:` / `-stopAnimations` (`:66-67`),
`-resetView:` (`:69`), `-dismissEditingControls:` (`:71`), `-showingDeleteConfirmationButton`
(`:73`).

The important thing about this surface is that **setting a property does nothing on its own**. The
setters are plain synthesized ones. The controller fills all of them and then calls `resetView:`
(`TGDialogListController.mm:1215`), which is where the whole cell is derived and
`setNeedsLayout` is finally sent (`TGDialogListCell.m:1226`). `setTypingString:` is the one
exception: it applies itself immediately (`:613-638`), because typing arrives asynchronously and
must not require a full reset.

`resetView:(bool)keepState` — the argument is misleadingly named. It only controls the avatar
cross-fade: `keepState == true` means "this row is being updated in place, cross-fade from the
current image over 0.3s"; false means "this row was just recycled, 0.14s from the placeholder"
(`:1106-1117`).

---

## 3. Geometry

Row height is **73 points**, returned by the controller, not the cell
(`TGDialogListController.mm:1118-1125`: `return 73` for the list, `50` for the trailing loading
row, and `51` or `73` in the search table depending on the scope button). `73` is not a font
metric; it is `8 + 56 + 9` — the avatar box plus its margins — and the avatar size 56 is what
everything else is measured off.

All coordinates below are in cell-content coordinates, taken from `layoutSubviews`
(`TGDialogListCell.m:1258-1380`) unless noted. `size` is the cell's own frame size.

| Element | Frame | Citation |
| --- | --- | --- |
| Avatar | `(8, 8, 56, 56)`, corners rounded 5pt by the image filter | `:406`; filter `avatar56` = `TGScaleAndRoundCorners(source, 56×56, …, 5, …)` in `Telegraph/Telegraph/TGTelegraph.mm:477-479` |
| Text view | `(73, 6, size.width - 73, 58)` | `:1273-1275` (init uses `(73, 2, …, 46)` at `:369`, immediately overwritten on first layout) |
| Title | `(73 + iconWidth, 6, titleWidth, 20)` | `:1335` |
| Date | origin `(size.width - dateWidth - 9, 9)`, box `75 × 15` | `:1309` |
| Preview | `(73, 29, size.width - 73 - 10 - rightPadding, 40)` | `:1337-1338` |
| Author name | `(73, 29, size.width - 73 - 10 - rightPadding, 20)` | `:1357` |
| Unread badge | `(size.width - 28 - badgeWidth, 29, badgeWidth, 21)`, `badgeWidth = MAX(27, textWidth + 10)` | `:1285-1287` |
| Delivery-error badge | `(size.width - 28 - 26, 29, 26, 20)` | `:1298` |
| Sent checkmark | `(dateX - 15, 11 + retinaPixel, 13, 11)` | `:1329` |
| Read checkmark | `(dateX - 20, 11 + retinaPixel, 18, 11)` | `:1330` |
| Pending clock | `(dateX - 16, 11, 12, 12)` | `:1333` |
| Mute icon | `(titleX + titleWidth + 3, titleY + 6)` = y 12 | `:1370-1372` |
| Disclosure arrow | `(size.width - 9 - 6, 33, 9, 13)` | `:431-433`, asset is 18×26 px @2x |

`retinaPixel` is `0.5` on retina and `0` otherwise (`:1280`) — the checkmarks are nudged half a
point down so their 1-pixel stroke lands on the pixel grid.

Both checkmark rects end at `dateX - 2`: the two glyphs are right-aligned to each other, so a row
that flips from sent to read does not shift the mark's right edge.

### Title width

```
titleLabelWidth = (int)(dateX - 4 - 73 - 18)          // :1311
                  - groupChatIconWidth                 // 21 group, 15 secret; :1314-1322
                  - (isMuted ? 12 : 0)                 // :1324-1325
titleLabelWidth = MIN(titleLabelWidth, [title sizeWithFont:bold16].width)   // :1327
```

The `- 18` is dead space reserved so the title never touches the date, and the `MIN` is what makes
the mute icon hug a short title instead of floating out at the truncation point. A title longer
than the budget is truncated with `NSLineBreakByTruncatingTail` (`:256`). If the arithmetic goes
negative on a very narrow cell the original does **not** clamp it — `drawInRect:` with a negative
width simply draws nothing.

### Right padding, and how the preview yields to the badge

`rightPadding` starts at 16 and grows (`:1281`, `:1292-1299`):

- `+ badgeWidth + 7` when the unread badge is visible,
- `+ 26 + 7` when the delivery-error badge is present.

Only the preview and author lines shrink by it; the title is bounded by the date instead. That is
the correct instinct — the badge sits on the second line, so only the second line needs to move.

### The two-line group layout, and its quirk

When there is an author name (`:1355-1366`):

```
authorNameFrame = (73, 29, w - 73 - 10 - rightPadding, 20)
messageRect.origin.y += 9;  messageRect.size.height -= 12;      // → y 38, h 28
if ([message sizeConstrainedTo:messageRect].height < 20)
    messageRect.origin.y += 9;                                   // → y 47
```

So a one-line preview under an author name sits at y 47 (relative y 41 inside the 58-tall text
view; a 14pt line is ~17pt, ending exactly at 58). A preview that wraps to two lines is placed at
y 38 — which overlaps the author name's 20-point box. In practice the author's ink is 14pt bold
occupying roughly y 29–46, so a two-line preview starting at 38 does collide. This looks like a
bug that survived because group previews that wrap are rare at 14pt in ~230 points of width. **Do
not "fix" it silently** — it is the original behaviour, and it is the single place in this file
where the original is genuinely ambiguous about intent.

---

## 4. Colours and fonts

Fonts (`:371-373`, `:391-393`, `:423`, `:450`):

| Role | Font |
| --- | --- |
| Title | `boldSystemFontOfSize:16` |
| Preview / typing | `systemFontOfSize:14` |
| Author name | `boldSystemFontOfSize:14` |
| Date, 24h / weekday / numeric | `systemFontOfSize:13` (`dateFont`) |
| Date, 12h clock part | `boldSystemFontOfSize:13` (`dateTextFont`) |
| Date, "AM"/"PM" | `systemFontOfSize:11` (`dateLabelFont`) |
| Unread count | `boldSystemFontOfSize:14` |
| "Delete" button text | `boldSystemFontOfSize:13` |

Colours:

| Role | Value | Citation |
| --- | --- | --- |
| Title | `#111111` | `:193` |
| Title, secret chat | `#229A0A` | `:194` |
| Title/preview/author when highlighted | white | `:195`, `:250-253` |
| Author name | `#345F8F` | `:196` |
| Preview, plain text | `#888888` (`normalTextColor`) | `:791` |
| Preview, service action | `#536C8C` (`actionTextColor`) | `:792` |
| Preview, media placeholder | `#536C8C` (`mediaTextColor`) | `:793` |
| Typing line | `#536C8C` | `:262` uses `actionTextColor` |
| Date | `#337ACC` | `:394` |
| Date when highlighted | white | `:396` |
| Unread count text | white, shadow `#8091A6` at `(0,-1)` | `:417-420` |
| Unread count when highlighted | `#2371C2`, shadow cleared | `:421-422` |
| Delete-button text shadow | `rgba(#A30F0A, 0.2)` at `(0,-1)` | `:456` |

`normalTextColor` / `actionTextColor` / `mediaTextColor` are file-scope statics initialised lazily
inside `resetView:` (`:789-794`), which is why they are `nil` if you ever draw before the first
reset — the typing dots created in `-typingDotsContainer` (`:656`) read `actionTextColor`
directly and would come out black if a typing string ever arrived before any `resetView:`. In
practice the controller always resets first (`TGDialogListController.mm:1215` precedes
`:1200-1205`).

The unread-count colours are dead-reckoned against the two badge PNGs rather than composed:
`unreadBackground = #EBF0F5` and `unreadMessage = #5B646E` are declared at `:1088-1098` and then
never used — leftovers from an earlier "unread rows get a tinted background" design that did not
ship. Do not port them.

---

## 5. Artwork

The row's background is **not** a `UITableViewCell` separator. The controller sets
`separatorStyle = UITableViewCellSeparatorStyleNone` (`TGDialogListController.mm:538`, `1553`,
`1603`) and gives each cell an image-view background instead
(`TGDialogListController.mm:1259-1260`, `1137-1142`):

- `DialogListCell.png`, stretched `leftCapWidth:1 topCapHeight:0` → `backgroundView`
- `DialogListCellHighlighted.png`, same stretch → `selectedBackgroundView` (a `TGHighlightImageView`)

Both assets are **4 × 146 px @2x, i.e. 2 × 73 points — exactly one row tall, separator included.**
Sampled pixel values:

- Normal: pure white for 71.5 points, then the last **1 point (2 px) is `#E5E5E5`** — that grey line
  at the bottom *is* the separator.
- Highlighted: a vertical gradient — a 1px specular top edge `#0086E5`, a bright band `#26A4F9`
  just below it, decaying to `#1477DA` at the bottom, closed by a 1-point `#005FBE` edge.

Because the plate is a fixed 73 points and stretches only horizontally (`topCapHeight:0` with a
146px-tall source means the vertical axis is scaled, not tiled — at exactly 73 points it is 1:1),
any change to the row height distorts both the gradient and the separator.

Other artwork, all from `Telegraph/Telegraph/Resources`:

| Asset | Points | Used for |
| --- | --- | --- |
| `DialogListSent(_Highlighted).png` | 13 × 11 | single check, delivered but unread (`:501`, `:1169-1172`) |
| `DialogListRead(_Highlighted).png` | 18 × 11 | double check, delivered and read (`:503`, `:1164-1168`) |
| `DialogListPending(_Highlighted).png` | 12 × 12 | clock, created lazily on first pending message (`:1184-1193`) |
| `DialogListGroupChatIcon(_Highlighted).png` | 18 × 12 | group glyph, drawn at `(0, 4)` inside the text view (`:236-247`) |
| `DialogListEncryptedChatIcon(_Highlighted).png` | 10 × 13 | secret-chat lock, drawn at `(0, 3)` (`:215-226`) |
| `DialogList_Muted(_Highlighted).png` | 10 × 10 | mute icon (`:1215`) |
| `DialogListArrow(_Highlighted).png` | 9 × 13 | disclosure chevron (`:129-140`) |
| `DialogListUnreadBadge(_Highlighted).png` | 27 × 21 | unread pill, stretched from its centre (`TGInterfaceAssets.mm:231-251`) |
| `DialogErrorBadge(_Highlighted).png` | 26 × 20 | failed-delivery badge, **not** stretchable (`TGInterfaceAssets.mm:253-271`) |
| `ListEditingSwitch.png` + `ListEditingSwitchMinus(_Active).png` | 30 × 30 / — | the round editing toggle (`:448`, `:36`, `:46`) |
| `ListDeleteButton(_Highlighted).png` | 18 × 30, stretched at mid-width | the red Delete pill (`:56`, `:67`) |
| `DialogListDeleteShadow.png` | 35 × 4, stretched at `width-1` | the shadow the Delete pill casts leftwards (`:78-79`) |

Note the pattern: **every glyph has a `_Highlighted` twin**, because on a blue pressed row a dark
grey icon is illegible. The group and secret glyphs are drawn with `kCGBlendModeCopy` when
highlighted (`:226`, `:247`) so the white artwork replaces rather than blends with the blue plate.

The unread badge's 27-point minimum is not arbitrary: it is the natural width of the PNG, so a
one- or two-digit count shows the pill undistorted and only three digits stretch it.

---

## 6. Deriving the preview text

`resetView:` is where the cell turns a message into a line of text (`:796-1045`). The order matters:

1. **Attachments win over text.** The first attachment in `_messageAttachments` that the switch
   recognises replaces the preview entirely (`:799-1019`). Media types map to localised nouns —
   `Message.Photo`, `Message.Video`, `Message.Location`, `Message.Contact` — each in
   `mediaTextColor` (`:990-1017`).
2. **Service actions** produce a whole sentence built from `_users[@"author"]` — renamed chat,
   changed photo, added/removed member, created chat, joined, and the whole secret-chat
   lifecycle including message-lifetime changes bucketed at 2s / 5s / 1m / 1h / 1d / 1w
   (`:965-976`). All of them are `actionTextColor`.
3. **Service actions also set `_hideAuthorName = true`** (`:815`, `:829`, `:843`, `:861`, `:879`,
   `:892`, `:902`, `:912`, `:922`). "Alice renamed the group" must not be prefixed by "Alice:".
   The secret-chat cases at `:926-985` deliberately do *not* set it — they are not group chats, so
   the author line is already suppressed by `_hideAuthorName = !_isGroupChat` at `:797`.
4. **Empty preview.** If after all that `_messageText.length == 0` and the chat is encrypted, the
   cell substitutes the encryption state — awaiting / processing / rejected / started
   (`:1026-1044`), again in `actionTextColor`. For a non-encrypted empty conversation the preview
   is simply blank; there is no "No messages" string.

The author name shown on the second line is `_hideAuthorName ? nil : _authorName` (`:1100`), and
`_authorName` is supplied by the controller from `dialogListData[@"authorName"]` for both group and
private chats (`TGDialogListController.mm:1176`, `:1181`) — but for private chats
`_hideAuthorName` is already true, so it never shows.

**Unread count formatting** (`:1057-1060`): `unreadCount + serviceUnreadCount`, printed plainly
below 1000 and as `%dK` (integer division, so 1999 → "1K") above it. When `deliveryState` is
`Failed` the badge is suppressed entirely and the error badge takes its place (`:1068-1082`).

**Avatar fallback** (`:1104-1125`): with no `avatarUrl` the cell loads the pseudo-URL
`dialogListPlaceholder:<id>` where the id is `encryptedUserId` for secret chats and
`conversationId` otherwise. `TGImageDownloadActor` resolves it (`Telegraph/Telegraph/TGImageDownloadActor.m:337-341`):
negative ids (groups) get `groupAvatarPlaceholder:`, positive ids get `avatarPlaceholder:`, which
picks one of the `DialogListAvatar%d.png` colour variants by `colorIndexForUid(uid)`, with uid
`333000` (Telegram service) getting `DialogListAvatarSystem.png`
(`Telegraph/Telegraph/TGInterfaceAssets.mm:273-292`). So the 2013 client already had
deterministic per-peer avatar colours — as pre-rendered PNGs, not drawn initials.

---

## 7. Date formatting

`_dateString = _date == 0 ? nil : [TGDateUtils stringForMessageListDate:(int)_date]`
(`:785`) — a zero date yields no string and `dateWidth` collapses to 0 (`:1308`), giving the title
the full width.

`stringForMessageListDate` (`TelegraphKit/TelegraphKit/TGDateUtils.mm:294-346`) works on
**calendar days**, not elapsed seconds:

- different calendar year → `d.m.yy` (or `m/d/yy` where `value_monthFirst`)
- same day (`tm_yday` difference 0) → `HH:mm`, or `h:mm AM`/`h:mm PM` under a 12-hour locale
- 1 to 6 days back → short weekday name
- otherwise → `d.m.yy`

`TGDateLabel` then splits that string (`TGDateLabel.m:39-69`): if it ends in `" AM"`/`" PM"` the
suffix is stripped and remembered as `formatMode`. **The clock part is drawn bold only in the
12-hour case** — `measureTextSize` and `drawTextInRect` both select `dateTextFont` (bold 13) when
`formatMode != None` and `dateFont` (regular 13) otherwise (`TGDateLabel.m:76`, `:123`). Weekdays
and numeric dates are regular. The "AM"/"PM" is drawn separately, right-aligned within the
measured width, in the 11pt font, offset down by `dstOffset = 2` (`TGDateLabel.m:126`, cell sets
`amWidth = pmWidth = 19` and `dstOffset = 2` at `:388-390`) — the 19-point reservation is a fixed
allowance, not a measurement.

---

## 8. States and behaviour

### Highlight

`UITableViewCell` propagates `setHighlighted:` to `UILabel` and `UIImageView` subviews of the
content view, but not to a bare custom `UIView`. The original works around this with
`TGHighlightTriggerLabel` (`:377-381`) — a hidden, zero-sized `UILabel` added to the content view
whose overridden `setHighlighted:` forwards to its `targetViews`, here the text view
(`TelegraphKit/TelegraphKit/TGHighlightTriggerLabel.m:18-29`). The text view's own setter marks
itself dirty (`:175-183`) and `drawRect:` then paints everything white and swaps in the
`_Highlighted` glyphs. Every `UIImageView` in the cell is constructed with
`initWithImage:highlightedImage:` so UIKit's own propagation handles them.

Two subtleties in the pressed state:

- The selected background is grown upward by one point:
  `frame = (0, -1, w, h + 1)` in `setSelected:animated:`, `setHighlighted:animated:`,
  `adjustOrdering` and `layoutSubviews` (`:551`, `:570`, `:579`, `:1264`). That extra point covers
  the `#E5E5E5` separator baked into the *previous* row's plate, so a pressed row is a clean
  unbroken blue block.
- `adjustOrdering` (`:574-606`) walks the table view's subviews and re-inserts the pressed cell at
  the highest cell index. Without it the neighbouring cell, drawn later, would paint over that
  extra point. The search bar is included in the scan so the highlight never jumps above it.

`selectionStyle` is forced to `UITableViewCellSelectionStyleBlue` at the top of every `resetView:`
(`:782-783`).

### Typing

`setTypingString:` (`:613-638`) is diffed against the current value and, when it changes, flips
`showTyping`, invalidates `_validSize`, and starts or stops the dot animation. While typing, the
preview and the author name are not drawn at all — `drawRect:` takes the `_showTyping` branch and
skips both (`:259-285`).

The dots are three `.` labels 4 points apart in a 10×10 container (`:645-667`), positioned at the
measured end of the typing text (`:1345-1353`). The animation is a hand-rolled `NSTimer` chain
(`:731-778`): step 1 reveals nothing after 0.22s, then steps at 0.12s intervals reveal one dot each
(the visibility test is `dotIndex < step - 1`), and after step 3 the cycle restarts after 0.22s.
Timers are scheduled in `NSRunLoopCommonModes` so the dots keep moving while the list scrolls.

`restartAnimations:` / `stopAnimations` (`:669-689`) exist so the controller can stop every visible
cell's timer when the view disappears and restart it on return; `startTypingAnimation:` refuses to
start unless the app is active or `force` is passed and the cell is in a window (`:706-711`).
`prepareForReuse` stops the animation (`:529-534`) — and does nothing else, because all other state
is overwritten by the next `resetView:`.

### Editing and swipe-to-delete

Two separate paths reach the same red Delete pill.

`setEditing:animated:` (`:1384-1480`) slides a 30×30 round switch button in from `x = -35` to
`x = 4`, vertically centred on the 73-point row as `(73 - 30) / 2 = 21`, moves the disclosure
arrow off to the right by `arrowWidth + 12 + 32`, shifts the date left by 32 (`:1309`,
`editing ? -32 : 0`) and fades the unread badge out. Duration 0.3s,
`UIViewAnimationOptionBeginFromCurrentState`. Tapping the switch (`:1482-1511`) rotates the minus
glyph by -90° and swaps it for the active asset over 0.25s, then reveals the Delete pill.

A horizontal swipe reaches the same place through `TGSwipeGestureRecognizer` (`:439-440`,
`:1582-1594`), but only when `enableEditing` is set, and it first cancels the selection so the row
does not stay blue underneath.

`animateDeleteButton:` (`:1513-1573`) is the interesting one. The pill animates from a 2-point-wide
sliver at `x = width - 6 - 2` out to its full 61 × 31 at `x = width - 6 - 61`, top 20, over 0.25s,
while the shadow image slides in behind it and the date and both checkmarks fade to zero. The label
inside the pill is a *pre-rendered image* of the word "Delete" (`:445-463`), drawn once in a
`dispatch_once` into a bitmap with its shadow, because measuring and drawing a string per cell was
too expensive. When the pill appears the cell announces itself through the watcher handle as
`setFocusCell` (`:1541-1545`) so the controller can dismiss the previous row's pill; the tap
broadcasts `conversationDeleteRequested` with the conversation id (`:1596-1605`).

`resetView:` tears all of this down when a cell with a visible pill is recycled (`:1138-1160`).

### `isOnline`

Declared in the header (`:39`) and **never read anywhere in the implementation**. There was no
online dot on a 2013 chat list row.

---

## 9. Our port

Our equivalent is not a separate class; it is `TGChatCell`, declared and implemented inside
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGChatListViewController.m:202-728`, configured by
`-resetCell:plain:` / `-configure…InCell:` / `-tableView:cellForRowAtIndexPath:` at
`:3629-3820`.

**What is already right**, and needs no work: row height 73 (`:26`), avatar 56 at x 8 with 5pt
corners (`:27-28`, `:272-279`), text left edge 73 (`:29`), the three text fonts 16 bold / 14 / 14
bold (`:284`, `:292`, `:301`), title `#111111`, preview `#888888`, action `#536C8C`, author
`#345F8F`, date `#337ACC` (`:37-66`, `:315`), secret-chat title `#229A0A` (`:2870-2876`), the
badge geometry `MAX(27, w+10) × 21` at `(w - 28 - badge, 29)` with the same stretched PNGs
(`:94-104`, `:634-642`), the badge's white-on-`#8091A6`-shadow and `#2371C2`-when-highlighted
treatment (`:330-338`, `:575-580`), the `rightPadding = 16 + badge + 7` rule (`:656-658`), the
title-width formula including the `-18`, the `-12` for mute and the `MIN` against the measured
string (`:673-679`), the checkmark right-edge alignment at `dateX - 2` with the `retinaPixel`
nudge (`:702-705`), the mute icon at `titleX + titleWidth + 3, y 12` (`:681-683`), the arrow at
`(w - 9 - 6, 33)` (`:710-711`), the two `+= 9` author-line offsets reproduced exactly including the
quirk (`:686-697`), and the swipe pill's 61 × 31 at top 20, edge 6, growing from a 2-point sliver
over 0.25s (`:31-35`, `:474-546`).

That is a genuinely faithful port of the layout arithmetic. The defects are all in the states.

### Defects

1. **Icons do not have highlighted artwork, so a pressed row shows dark glyphs on blue.**
   `-buildRowIcons` (`src/TGChatListViewController.m:346-377`) constructs `muteIcon` and
   `groupIcon` with `initWithImage:` only, and `-configureStatusIconsInCell:` (`:3744-3756`) sets
   `tick.image` directly, never `highlightedImage`. The original constructs all three with
   `initWithImage:highlightedImage:` (`TGDialogListCell.m:501`, `:503`, `:1215`) and draws the
   group/secret glyph with the `_Highlighted` asset under `kCGBlendModeCopy`
   (`TGDialogListCell.m:241-247`). Fix: pass the highlighted twins. Two of the four PNGs
   (`DialogList_Muted_Highlighted@2x.png`, `DialogListGroupChatIcon_Highlighted@2x.png`) are
   missing from `iTgLegacy/images/` and must be copied from the original's `Resources` directory;
   `DialogListSent_Highlighted@2x.png` and `DialogListRead_Highlighted@2x.png` are already there,
   so the tick fix is a one-line change to use `initWithImage:highlightedImage:`.

2. **A pressed row shows a pale seam along its top edge.** Our `-buildPlates`
   (`src/TGChatListViewController.m:379-390`) assigns a plain `UIImageView` as
   `selectedBackgroundView` and never offsets it. The original grows it to `(0, -1, w, h + 1)` in
   four places (`TGDialogListCell.m:551`, `:570`, `:579`, `:1264`) precisely because the
   `#E5E5E5` separator is the bottom point of the *previous* row's plate. Fix: override
   `layoutSubviews` / `setHighlighted:animated:` to apply the same -1 offset.

3. **…and even with the offset, the neighbouring cell paints over it.** We have no equivalent of
   `-adjustOrdering` (`TGDialogListCell.m:574-606`), which re-inserts the pressed cell at the top
   of the table view's cell subviews. Both this and defect 2 must land together or neither is
   visible.

4. **The typing line has no animated dots.** `-configurePreviewInCell:chat:plain:`
   (`src/TGChatListViewController.m:3673-3691`) sets the preview text to the action string in
   `TGChatListActionColour()` — right colour, right position — and stops there. The original
   appends three dots at the measured end of the text and cycles them on a 0.22 / 0.12 / 0.12 /
   0.12 timer in `NSRunLoopCommonModes` (`TGDialogListCell.m:645-778`, `:1345-1353`). This is one
   of the most recognisable pieces of motion in the 2013 list.

5. **The date's bold/regular treatment is inverted.** `TGChatDateParts`
   (`src/TGChatListViewController.m:2919-2954`) sets `*bold = YES` for the weekday case and leaves
   the 12-hour clock regular; `-applyDateAppearance` (`:602-628`) honours that. The original is
   the exact opposite: bold 13 is used *only* when an AM/PM marker was split off, and weekdays and
   numeric dates use regular 13 (`TGDateLabel.m:76`, `:123`; fonts assigned at
   `TGDialogListCell.m:391-392`). Fix: set `bold` in the 12-hour branch and clear it in the
   weekday branch.

6. **Date bucketing uses elapsed seconds instead of calendar days.** Ours: `age < 24*3600` → time,
   `age < 7*24*3600` → weekday (`src/TGChatListViewController.m:2941-2952`). The original compares
   `tm_yday` and `tm_year` (`TGDateUtils.mm:305-333`). A message sent yesterday at 23:00 shows a
   clock time in our build and a weekday name in the original, and any message from a previous
   calendar year always falls to the numeric date in the original regardless of age. Ours also
   formats the numeric date as `dd.MM.yy` where the original prints an unpadded day
   (`TGDateUtils.mm:310`).

7. **No failed-delivery state.** The original replaces the unread badge with a 26 × 20
   `DialogErrorBadge` at `(w - 28 - 26, 29)` and reserves `26 + 7` of right padding for it
   (`TGDialogListCell.m:1068-1086`, `:1295-1299`). We have neither the state nor the asset. Same
   for the 12 × 12 pending clock at `dateX - 16` (`TGDialogListCell.m:1180-1197`, `:1333`) — an
   outgoing message that has not left the device shows nothing at all in our build.

8. **No secret-chat lock glyph.** We colour the title green (`:3792-3794`) but never draw
   `DialogListEncryptedChatIcon`, and never reserve its 15 points of title width. The original
   draws it at the text view's `(0, 3)` and subtracts 15 from the title budget
   (`TGDialogListCell.m:207-227`, `:1313-1317`). The asset is not in `iTgLegacy/images/`.

9. **An online dot that the original never had.** `-buildRowIcons`
   (`src/TGChatListViewController.m:347-353`) adds a 14-point dot with a 2-point ring at the
   avatar's bottom-right corner. `TGDialogListCell` declares `isOnline` (`TGDialogListCell.h:39`)
   and never uses it. This is a modern-Telegram affordance, not a 2013 one — a deliberate decision
   to make, not an oversight to leave unexamined.

10. **A "Draft:" label that the original never had.** `src/TGChatListViewController.m:309-317`
    and `:644-650` add a `#C42B1E` "Draft:" prefix. There is no draft concept anywhere in
    `TGDialogListCell`. Same category as 9: defensible as an interaction-model import, but it is
    not the 2013 visual language and it eats preview width.

11. **Author detection by string splitting.** `-configurePreviewInCell:` finds the author by
    searching the preview for `": "` within the first 40 characters
    (`src/TGChatListViewController.m:3703-3711`). The original receives `authorName` as its own
    field and, critically, suppresses it for every service action via `_hideAuthorName`
    (`TGDialogListCell.m:797`, and nine assignments between `:815` and `:922`). Our heuristic will
    split "Alice: hello" correctly but will also split a service line, a URL preview, or a message
    whose text simply contains a colon, producing a spurious blue author line. Fix: carry the
    author separately from the message text and never derive it from the preview.

12. **Performance: the text labels are not opaque.** `titleLabel` and `previewLabel`
    (`src/TGChatListViewController.m:282-298`) never get a `backgroundColor`, so they blend. The
    original draws all four strings into one opaque white view
    (`TGDialogListCell.m:374-375`) specifically to keep the list smooth on this class of hardware.
    Not user-visible as a still frame, very visible as scrolling frame rate on a 4S. If we keep
    `UILabel`s, at minimum give them the plate's white background in the plain theme.

One genuine improvement in ours worth keeping: `-layoutSubviews` recomputes the arrow and date
frames from `contentView.bounds` every pass (`src/TGChatListViewController.m:651-726`) rather than relying on autoresizing masks seeded from a
320-point default frame (`TGDialogListCell.m:432-433`, `:479`, `:483`). That is more robust and
costs nothing.

---

## 10. What became of it

### In `twelve` (`/Users/alexanderhavrysh/Git/iOS/twelve`) — the same lineage, extended

The class survives literally, as `legacy/TelegraphKit/TGDialogListCell.m`, grown from 1607 to 2297
lines. The instructive changes:

- **The row got taller and the type got bigger.** `TGDialogListRowHeight()` returns 80 and
  `TGDialogListAvatarSize()` returns 62 in the modern style
  (`legacy/TelegraphKit/TGDialogListCell.m:27-34`), with the preview and author fonts moved from
  14 to 15 and the title to a medium rather than bold weight (`:360-362`). Forced by iOS 7's
  typography, not by a new feature.
- **A "Classic iOS 6" mode was kept.** The same functions return 72 and 52 when
  `TGDialogListClassicIOS6Style()` is true (`:22-34`), with the avatar inset at 12 rather than 10
  and a 7-point corner radius (`:393-398`), and the original `DialogListCell.png` plates were
  retained under `Telegraph/Resources/ClassicIOS6/`. Someone deliberately preserved the 2013 row
  as a theme — direct evidence that these metrics were understood as a coherent look rather than
  as arbitrary constants.
- **The avatar became generated, not fetched.** `TGRemoteImageView` gave way to
  `TGLetteredAvatarView` with configurable single/double initial font sizes (`:393-394`),
  replacing the fixed `DialogListAvatar%d.png` colour set.
- **Text drawing moved to attributed strings** with cached attribute dictionaries
  (`:79-112`, `:141-166`) — the same one-opaque-view architecture, updated for
  `drawWithRect:options:attributes:`.
- **The one-button delete grew into a whole control strip.**
  `Telegraph/TGDialogListCellEditingControls.{h,m}` (740 lines) replaces the single red pill with
  pin / mute / delete / promote / restrict / group / read / archive, each a block callback
  (`TGDialogListCellEditingControls.h:26-38`). This is the clearest case of a change *forced by
  features*: the 2013 cell hard-coded "the swipe action is Delete" into a pre-rendered bitmap of
  the word.
- A verified badge appeared (`:497`), likewise feature-driven.

Our `TGChatCell`'s swipe implementation — an array of `swipeActions` dictionaries laying out
right-to-left variable-width pills (`src/TGChatListViewController.m:459-546`) — is structurally
the `twelve` design wearing the 2013 pill artwork. That is the correct call for this project and
should not be reverted to a single Delete button.

### In the modern client (`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS`)

`submodules/ChatListUI/Sources/Node/ChatListItem.swift` is the descendant, and the shape of the
change is more interesting than the numbers:

- **Nothing is a constant any more.** The avatar is
  `min(60, floor(baseDisplaySize * 60 / 17))` (`ChatListItem.swift:2025`), collapsing to 40 in
  compact contexts (`:2028`); the title font is `floor(itemListBaseFontSize * 16 / 17)` and the
  text font `* 15 / 17` (`:2294-2295`); the row height is *computed from the measured text*
  (`:4036-4039`). Every metric became a ratio against a user-controlled base size. Our fixed 73 /
  56 / 16 / 14 is the 2013 answer to a question that no longer has one answer — which is exactly
  why our port should keep them fixed and not "modernise" them.
- **The single opaque hand-drawn view was vindicated and then generalised.** The 2013 trick of
  collapsing five views into one drawn layer for scrolling performance is what AsyncDisplayKit
  turned into a framework: `TextNode` layouts computed off the main thread, applied as a closure.
  Same idea, industrialised.
- **The left inset is now composed** from `params.leftInset + avatarLeftEdgeInset + 8 + diameter`
  (`:2564-2589`) rather than the flat `73`, because folders, selection checkboxes and forum topics
  all need to push the content right.
- The separator went back to being a real separator rather than a pixel baked into a background
  PNG — a change of taste made affordable by vector-drawn themes and by no longer paying for an
  extra composited layer.

The through-line: **the 2013 cell's numbers were a fixed composition for one screen size and one
font; the modern one is a layout algorithm.** For a 4S at 320 × 480 with a non-adjustable system
font, the fixed composition is not a limitation to be worked around — it is simply the right
answer, and porting it verbatim is correct.

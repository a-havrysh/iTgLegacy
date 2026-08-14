# Layout Metrics (2013 Telegram iOS)

Every number here is transcribed from the original 2014 Telegraph source. Points, not pixels.
Frame-based layout only — no Auto Layout, ever. Round every computed origin with `floorf()` or
`CGRectIntegral` exactly as the original does; the original tolerates a half-pixel only via the
`retinaPixel` idiom (`TGIsRetina() ? 0.5f : 0.0f`).

## 1. Bars

| Bar | Portrait | Landscape |
| --- | --- | --- |
| Status bar | 20 | 20 |
| Navigation bar | **44** | **32** |
| Tab bar | **49** | **49** |
| Search bar | **44** (+ scope bar extends it; `TGSearchBar` adds the delta as `contentInset.bottom`) | 44 |

Source: `TGViewController.mm:721` — `navigationBarHeight = portrait ? 44 : 32`; `TGMainTabsController.m:359`
— `TGTabBar` frame is `CGRectMake(0, viewHeight - 49, width, 49)`; `TGSearchBar.m:141` — `requiredHeight = 44`.

Nav bar button placement (`TGNavigationBar.m:255-272`), measured from the bar edge, vertically centred
in the bar:

- Left button origin.x = **5** portrait, **3** landscape.
- Right button origin.x = `width - buttonWidth - 5` portrait, `- 3` landscape.
- Title view is centred in a 44-high (portrait) / 32-high (landscape) box; the title label is laid
  out at `CGRectMake(0, 0, maxWidth, portrait ? 44 : 32)`, then `origin.y = (int)((44 or 32 - h)/2) + 1`.

Header buttons are stretchable art, not tinted views:

| Asset | Native size (pt) | Left cap |
| --- | --- | --- |
| `HeaderButton.png` / `_Pressed` | 21 x 30 | 6 |
| `HeaderButton_Landscape.png` / `_Pressed` | 16 x 25 | 6 |
| `BackButton.png` (+ `_Landscape`, `_Pressed`) | — | 15 |
| `HeaderButton_Blue*.png`, `HeaderButton_Login*.png`, `Header_Button_Delete.png` | — | half the raw width (`(int)(w/2)`), except Delete which uses 6 |

So a header button is **30 pt tall portrait, 25 pt tall landscape**, width = text width + caps.
Label font is `boldSystemFontOfSize:12`, shadow offset `(0, -1)`. Touch inset is `CGSizeMake(8, 8)`
(the button accepts touches 8 pt outside its frame on each axis).

Use `stretchableImageWithLeftCapWidth:topCapHeight:` — never `resizableImageWithCapInsets:` unguarded
(the original only used the latter behind an iOS-5+ check).

**In our repo:** build every bar button with `+[TGIcons headerButtonWithTitle:bold:target:action:]`
(or restyle an existing one with `+[TGIcons styleHeaderButton:]`). Do not hand-roll a
`UIBarButtonItem` with a system style.

### Tab bar internals (`TGMainTabsController.m:215-262`)

- Bar height 49, three items.
- `indicatorWidth = floorf(width / 3)`, decremented by 1 if odd.
- `paddingLeft = floorf((width - indicatorWidth * 3) / 2)`.
- Icon: `origin.y = 4`, x centred in its indicator slot.
- Label: `origin.y = 35`, x centred in its slot.
- Selection highlight is a full-height (49) image slid to `paddingLeft + indicatorWidth * index`; the
  first and last slot widen by `paddingLeft + 1` so the highlight reaches the screen edge.
- Unread badge container is 20 x 20, placed at `iconX + iconWidth - 9`, `y = 2`. Badge label frame
  `CGRectMake(9, 4 + retinaPixel, 28 + retinaPixel, 10)`, font bold 14 with shadow `(0, -1)`.

Never add a fourth tab. If a modern feature needs top-level presence, it goes into Settings or the
chat-list header, not a fourth tab — the geometry above is hard-coded to thirds.

## 2. Row heights by list type

| List | Row height | Source |
| --- | --- | --- |
| Chat (dialog) list | **73** | `TGDialogListController.mm:1123` |
| Chat list — loading/placeholder row | 50 | same, fallthrough |
| Chat list search — chats & contacts scope | **51** | `heightForRow`, scope 0 |
| Chat list search — messages scope | **73** | scope 1 |
| Contacts list — normal contact | **51** | `TGContactsController.mm:1359`, `rowHeight = 51` |
| Contacts list — action row ("New Group", non-registered/invite entry with `uid <= 0`) | **44** | `TGContactsController.mm:1351,1359` |
| Contacts search table | **51** | `TGContactsController.mm:600` |
| Settings / profile — plain row, phone row, switch row, disclosure-with-value row | **44** | `TGProfileController.m:2315` |
| Settings / profile — single centred action button row ("Add Contact", "Block") | **45** | `:2320` (1 pt when collapsed) |
| Settings / profile — segmented button strip row | **43** | `:2323` |
| Settings / profile — contact-media row | **44** | `:2326` |
| Settings — wallpaper picker row | **182** | `:2329` |
| Settings — free-text comment row | measured, `heightForWidth:` | `TGCommentMenuItem` |
| Group profile — member row | **49** | `TGTelegraphConversationProfileController.mm:1226` |

Any new list you invent must reuse one of these numbers. 73 for a row with a 56 avatar and two lines
plus a date; 51 for a row with a 40 avatar and two lines; 44 for a text-only settings row.

## 3. Avatars

Avatars are **rounded rectangles, never circles**, produced by pre-scaling the source image
(`TGScaleAndRoundCorners`) — not by `layer.cornerRadius`, which is slow and would clip the stroke art.
Radii are from `TGTelegraph.mm:476-529`:

| Context | Frame | Side | Corner radius | Processor name |
| --- | --- | --- | --- | --- |
| Chat list cell | `CGRectMake(8, 8, 56, 56)` | 56 | **5** | `avatar56` |
| Contacts cell / chat-list search cell | `CGRectMake(leftPadding + 5, 5, 40, 40)` | 40 | **4** | `avatar40` |
| Message author avatar (group chat) | 30 inside a 32 box at offset (2,2) | 30 | **5** | `avatarAuthor` |
| Profile header | `CGRectMake(9, 14, 70, 70)`, image 69 inside 70 at offset (0.5, 0) | 69/70 | **10** | `profileAvatar` |
| Nav-bar title avatar | 35 | 35 | **4** | `titleAvatar` |
| Member list avatar | 40 inside 44 at offset (2,2) | 40 | **4** | `memberListAvatar` |
| Small circular (typing/inline) | 27 | 0, circular flag set | — | `avatar27` |
| Conversation-panel avatar | 37 inside 38 | 37 | **19** (circular) | conversation avatar |

Rule for anything new: **56 → r5, 40 → r4, 70 → r10, 30/35 → r4-5.** Interpolate as
`radius = round(side / 11)` if you must invent a size; do not exceed r10 outside the profile header.

Placeholder assets, at 2x: `DialogListAvatarPlaceholder@2x.png` 112x112 (= 56 pt),
`DialogListAvatarPlaceholderSmall@2x.png` 80x80 (= 40 pt), plus the `...GroupAvatarPlaceholder`
variants. Overlay stroke `DialogListAvatarStroke@2x.png` is 66x66 (= 33 pt) and is drawn over the
author avatar, not the main one. In our repo, generate letter avatars with
`+[TGIcons avatarWithInitials:size:colourId:]` and the fixed glyph avatars with
`+[TGIcons archiveAvatarOfSide:]`, `savedMessagesAvatarOfSide:`, `inviteFriendsAvatarOfSide:` — pass
the side from the table above.

## 4. Text column origins and insets

### Chat list cell (73 pt row, `TGDialogListCell.m`)

- Avatar: x 8, y 8, 56x56. So the **text column starts at x = 73** (8 + 56 + 9).
- Text container view: `CGRectMake(73, 6, width - 73, 58)`.
- Title rect: `CGRectMake(73 + groupChatIconWidth, titleY, titleWidth, 20)`. Title font
  **bold system 16**.
- Message preview rect: `CGRectMake(73 + messageTextOffset, 29, width - 73 - 10, 40)`. Message font
  **system 14**; author-name prefix font **bold system 14**, drawn at
  `CGRectMake(73, 29, width - 73 - 10 - rightPadding, 20)`.
- Right inset for text is **10**.
- Date label: `CGRectMake(width - dateWidth - 9, dateY, 75, 15)` — right inset **9**. Fonts: date
  system 13, bold 13 for the emphasised form, 11 for the small label. In editing mode the date
  slides left by 32.
- Delivery marks sit left of the date: delivered checkmark at `dateX - 15`, y `11 + retinaPixel`,
  13x11; read (double) checkmark at `dateX - 20`, 18x11; pending clock at `dateX - 16`, y 11, 12x12.
- Unread badge: `CGRectMake(width - 28 - badgeWidth, 29, badgeWidth, 21)`; the badge art
  `DialogListUnreadBadge@2x.png` is 54x42 px = **27x21 pt**, so 21 is the fixed badge height and 27 the
  minimum width. Count label font **bold system 14**, shadow `(0, -1)`, label x centred in the badge.
- Error badge replaces it at `CGRectMake(width - 28 - 26, 29, 26, 20)`.
- Mute icon goes at `titleRight + 3`, `titleY + 6`.
- Typing indicator dots: container 10x10, each dot `CGRectMake(4 * i, 0, 4, 10)`.
- Swipe-to-delete: button 61x31 at y 20, right inset 10; `TG_DELETE_BUTTON_WIDTH 80`,
  `TG_DELETE_BUTTON_OFFSET 6`; the delete shadow view is 90x71 at y 1.
- Editing switch button 30x30 at y `(int)((73 - 30) / 2)` = 21, x 4 when open, `-35` when closed.

### Contact / 51 pt cell (`TGContactCell.m`, `TGDialogListSearchCell.m`)

- Avatar: `CGRectMake(leftPadding + 5, 5, 40, 40)`; `leftPadding` is 0 normally, +2 when a selection
  check is shown.
- **Text column starts at x = 40 + 9 + leftPadding = 49** (`avatarWidth + 9 + leftPadding`).
- Title width = `viewWidth - 40 - 9 - 5 - leftPadding`; right inset therefore **5**.
- Subtitle x = title x + 1, y = titleY + titleLineHeight (+ `retinaPixel` in the contact cell).
- Title font **system 19**, the emphasised half **bold system 19** (in a first/last name pair the
  matching half is bold); when both halves are drawn side by side the second starts at
  `firstWidth + 5`. Subtitle font **system 13**.
- Selection check button: 29x29 at `CGRectMake(selectionEnabled ? 7 : -7 - 29, 10, 29, 29)`, resting
  scale `0.8`, peak scale `1.16`.
- Editing delete button 61x31 at y 10, right inset `TG_DELETE_BUTTON_EDGE_OFFSET`.

### Settings / profile rows

Grouped table (`UITableViewStyleGrouped`, `TGActionTableView`). Row 44. Content follows the standard
grouped-cell inset of the era; label origin x = 10 inside the group's rounded box, value/detail
right-aligned with a 10 inset, disclosure arrow beyond that.

### Profile header (`TGProfileController.m:690-790`)

- Header container: `CGRectMake(0, 0, viewWidth, 86)`.
- Avatar 70x70 at (9, 14); the activity overlay is 69x69 at `(9 + retinaPixel, 14)`.
- Name label: `CGRectMake(94, 24, width - 94 - 9, 24)` (y 35 in phonebook-contact mode).
- Status label: `CGRectMake(94, 52, width - 94 - 9, 24)`.
- Edit-name container when editing: `CGRectMake(90, 14, width - 90 - 9, 88)`.
- So the **profile text column is x = 94**, right inset 9, header height 86.

## 5. Section headers

| Table | Header height |
| --- | --- |
| Contacts list, lettered section | **25** (`TGContactsController.mm:1339`); 0 when the section has no letter |
| Settings / profile, first section | **12**, or **30** (18 + 12) while editing |
| Settings / profile, later sections | **12**, or **0** for an empty phones section (**2** if it is section 0 and empty) |
| Profile table default | `sectionHeaderHeight = 0`, heights supplied per section |

A lettered index header is 25 pt with the letter label left-aligned inside it. A grouped-settings
caption block is 12 pt of pure spacing when there is no caption text; when there is caption text,
measure it and add it above the 12.

## 6. Landscape

Landscape is **not** a re-layout; it is a set of substitutions.

1. Nav bar 44 → **32**. Everything anchored to bar height recomputes; `TGViewController` already does
   this in `navigationBarHeight`.
2. Bar background swaps to the `_Landscape` art (`Header_Landscape.png`,
   `Header_Corners_Landscape.png`, `HeaderBlackOpaque_Landscape.png`). `TGNavigationBar` decides
   landscape by `self.frame.size.width > 400` — reuse that test rather than reading the orientation.
3. Every `TGToolbarButton` swaps to its `_Landscape` image pair (30 pt tall → 25 pt tall) via
   `setIsLandscape:`; bar-edge inset 5 → 3.
4. Title fonts swap: `+[TGViewController titleFontForStyle:landscape:]`,
   `titleTitleFontForStyle:landscape:`, `titleSubtitleFontForStyle:landscape:` return smaller faces in
   landscape. Never hard-code a title font; call these.
5. Tab bar stays **49**; only `indicatorWidth` and `paddingLeft` recompute from the new width.
6. Row heights **do not change** in landscape. Only widths and the right-anchored elements move.

## 7. Rendering modern concepts in this idiom

Rulings, so a hundred agents converge. These are not suggestions.

- **Reaction row under a message.** A single left-aligned row **20 pt tall**, top margin 4 from the
  bubble content, laid out inside the bubble's text column. Each reaction pill is 20 pt tall, corner
  radius 4 (the `avatar40` radius family), inner padding 6 left/right, 4 pt gap between pills, emoji
  drawn at 14 pt, count in **bold system 12**. Never a circle, never a floating overlay.
- **Reply header inside a bubble.** Height **34**; a 2 pt vertical accent bar at the bubble text
  column origin, then the quoted text column starts **+8** from that bar. Author line bold system 12,
  quoted line system 12, both single-line truncated.
- **Reply preview above the input bar.** A 44 pt panel above the keyboard bar, matching search bar
  height; 8 pt left inset for the accent bar, close button 30x30 at right inset 5.
- **Forwarded-from header.** Same 34 pt block as a reply header, no accent bar; text column starts at
  the bubble's own text origin.
- **Stickers.** A sticker is a bubble-less image; render at **max 128x128** in a message row of
  height `imageHeight + 6` (matching the chat list's 6 pt content padding). Never below 64.
- **Sticker picker / emoji grid.** No `UICollectionView` on iOS 6.1.3. Use a `UIScrollView` with
  manually framed cells: cell **64x64**, 4 columns portrait at a `floorf((width - 4*64)/5)` gutter,
  header strip 25 pt (the lettered-section height).
- **Media grid (shared media, photo picker).** Same manual `UIScrollView` tiling. Tile side
  `floorf((width - 3) / 4)` with a **1 pt** gutter, 4 columns portrait, **6 columns landscape**;
  grid content inset 0, so tiles meet the screen edges. Section header 25.
- **Chat folders / filters.** No fourth tab and no tab strip. Folders appear as a chooser reached from
  the chat list header button, and the chat list itself keeps its **73** row height unchanged. A
  folder row in the chooser is a **51** row with a 40 avatar-slot glyph at x 5 and text at x 49.
- **Premium / verified / scam badge.** A 16x16 glyph drawn inline after the title, at
  `titleRight + 3`, vertically at `titleY + 6` — exactly the mute icon's slot in the chat list cell,
  and immediately after the name in the profile header. Only one such badge per title; if two apply,
  verified wins.
- **Pinned chat.** No height change and no extra row chrome; the whole 73 pt row simply draws the
  pinned background.
- **Voice / video message row.** Keeps the 73 pt geometry when it appears in a list; inside a chat,
  the waveform strip is **24 pt tall** with a 40 pt play disc at the bubble text origin — use
  `+[TGIcons mediaDiscOfSide:playing:]` and `+[TGIcons waveform:size:...]`.
- **Any new top-aligned banner** (translation offer, undo bar, "join channel"): **44 pt tall**,
  matching the search bar, full width, no rounded corners, one hairline separator at the bottom.

## 8. Non-answers in the original

- The original never lays out a **grid** of anything (no `UICollectionView` in 2013 Telegram; the
  media picker used custom scroll tiling), so the media/sticker grid tile sizes above are derived
  from the 25 pt section header and 1 pt hairline conventions rather than transcribed. Treat them as
  law anyway so agents converge.
- Reaction and reply-quote metrics have **no original source at all**; the numbers above are extended
  from the bubble and pill families that do exist (20/21 pt badge height, radius 4).
- There is no 3.5-inch vs 4-inch distinction in any of the metrics above; the original branches on
  screen size only for asset selection (`screenSize.width > 321 || height > 481`), never for row
  heights.

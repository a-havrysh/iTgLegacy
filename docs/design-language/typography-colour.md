# Design language, chapter: type scale and palette

Authority for every number in this file is the 2014 Telegram iOS source at
`telegram-original-sources/extracted/telegram_iphone.src`. Where a value is quoted, the file and
line are named so you can verify it rather than trust me. Anything not quoted from there is marked
as a **ruling** — a decision made for this project so that a hundred agents converge on one look.

Non-negotiables:

* Only `[UIFont systemFontOfSize:]` and `[UIFont boldSystemFontOfSize:]`. The 2013 app used
  Helvetica (the system face on iOS 6) and never named a font family in UIKit code, with exactly
  one exception (`CTFontCreateWithName(CFSTR("Helvetica-Bold"), 13, NULL)` in
  `TGTelegraphConversationMessageAssetsSource.m:325`, for a CoreText run). Never call
  `fontWithName:`, never use a weight enum, never use Dynamic Type.
* Never `UIColor.tintColor` on a non-bar view, never `barTintColor`, never `setTranslucent:`.
  Colours are set on labels, layers and `backgroundColor` directly.
* Colours in code go through `TGTheme` (`src/TGTheme.h`) wherever an accessor exists, so imported
  themes and the flat/dark styles keep working. The hex values below are the skeuomorphic ground
  truth and the fallback; they are what `TGTheme` must return in the skeuomorphic style.

Helper, in this repo, that you MUST reuse instead of reinventing:
`+[TGIcons headerButtonWithTitle:bold:target:action:]` and `+[TGIcons styleHeaderButton:]`
(`src/TGIcons.h`) for every navigation-bar text button. Do not build a bar button out of a bare
`UIButton` with your own font and shadow.

---

## 1. The type scale

Every size in the original, with its owner. Use the nearest row rather than inventing a size.

| pt | weight | Role | Source |
|---|---|---|---|
| 19 | bold | Contact row name; profile name in the header | `TGContactCell.m:333`, `TGProfileController.m:783` |
| 19 | regular | Contact row name, non-matching half when searching | `TGContactCell.m:332` |
| 17 | bold | Grouped-table row title (settings rows); section header over a contact list | `TGVariantMenuItemCell.m:26`, `TGActionMenuItemCell.m:33`, `TGButtonMenuItemCell.m:34`, `TGContactsController.mm:683`, `TGContactsController.mm:1308` (15 bold for the contacts index header) |
| 17 | regular | Grouped-table row value drawn as a label item | `TGLabelMenuItemView.m:39` |
| 16 | bold | Chat-list row title; profile name-entry fields; a full-width action row ("Block user") | `TGDialogListCell.m:371`, `TGProfileController.m:1201`, `TGBlockActionCell.m:57` |
| 16 | regular | Grouped-table row value; composer placeholder | `TGVariantMenuItemCell.m:36`, `TGConversationController.mm:990` |
| 16 / 15 | bold | Navigation-bar title, portrait / landscape | `TGViewController.mm:103,110` |
| 15 | bold | Message author name in a group bubble; media/file attachment title; empty-list title | `TGTelegraphConversationMessageAssetsSource.m:137`, `TGDialogListController.mm:899` |
| 15 | regular | **Message body text.** Attachment subtitle | `TGTelegraphConversationMessageAssetsSource.m:31` (`messageTextFont`, base size), `:145` |
| 14.5 | bold | Send button | `TGConversationController.mm:1024` |
| 14 | bold | Chat-list preview author prefix ("Alice: "); profile "add photo" caption (14 + retinaPixel); unread-count badge | `TGDialogListCell.m:373,423`, `TGProfileController.m:755` |
| 14 | regular | Chat-list message preview; profile status line; footer/comment text under a grouped section; empty-list body | `TGDialogListCell.m:372`, `TGProfileController.m:792`, `TGCommentMenuItemView.m:19` |
| 13 | bold | Author name inside a bubble (`messageAuthorNameUIFont`); forwarded-from user; "Delete" on a swipe button; in-bubble action button | `TGTelegraphConversationMessageAssetsSource.m:334,160`, `TGDialogListCell.m:450`, `TGConversationMessageItemView.mm:1484` |
| 13 | regular | Chat-list date; contact subtitle (13 + retinaPixel); navigation-bar subtitle line | `TGDialogListCell.m:391`, `TGContactCell.m:341`, `TGViewController.mm:120` |
| 12 | bold | Toolbar / navigation-bar button label; search-scope segment | `TGToolbarButton.m:281,326`, `TGDialogListController.mm:511` |
| 11 | bold | Tab-bar unread badge; delivery-error badge (11 + 0.5 on retina) | `TGMainTabsController.m:172`, `TGTelegraphConversationMessageAssetsSource.m:819` |
| 11 | regular | **Bubble timestamp**; the small "AM/PM"-style suffix label in the chat list | `TGTelegraphConversationMessageAssetsSource.m:899`, `TGDialogListCell.m:393` |
| 10 | bold | Tab-bar item caption; inline video duration | `TGMainTabsController.m:80`, `TGConversationMessageItemView.mm:1925` |
| 10 | regular | Document type label on a file thumbnail; forwarded-from date | `TGTelegraphConversationMessageAssetsSource.m:153,169` |
| 9 | regular | AM/PM suffix beside a bubble timestamp | `TGTelegraphConversationMessageAssetsSource.m:907` |

Two idioms you must copy:

* **`+ retinaPixel`.** The original defines `retinaPixel` as `0.5` on retina and `0` otherwise and
  adds it to a handful of sizes so a half-point lands on a device pixel: `13 + retinaPixel`,
  `14 + retinaPixel`, `15 + retinaPixel`. Use the same trick for any *new* size that would
  otherwise sit at an odd half-point; never for a size already in the table.
* **Message body size is user-settable.** `messageTextFont` is rebuilt whenever `TGBaseFontSize`
  changes. In this repo the equivalent is `[[TGTheme shared] messageFontSize]` (default 15). Any
  new in-bubble text you add must derive from it, not from a literal 15.

---

## 2. The palette

### 2.1 Bars and bar text

| Hex | Role | Source |
|---|---|---|
| `#FFFFFF` | Navigation-bar title colour, both styles | `TGViewController.mm:139` |
| `#3D5C81` | Navigation-bar title shadow, default style | `TGViewController.mm:157` |
| `#2F3948` | Navigation-bar title shadow, dark/alternate style | `TGViewController.mm:165` |
| `#E0EEFD` | Navigation-bar subtitle ("online", "typing…") | `TGConversationController.mm:781,793,1645` |
| `#C9DCF2` | Navigation-bar subtitle, secondary ("last seen …", lifetime) | `TGConversationController.mm:1646,1918` |
| `#587DA3` | Shadow behind that secondary subtitle | `TGConversationController.mm:1919` |
| `#FFFFFF` | Toolbar/bar button label | `TGToolbarButton.m:185` |
| `rgba(#0E284D, 0.4)` | Toolbar button label shadow, generic | `TGToolbarButton.m:204` |
| `rgba(#042651, 0.3)` | Toolbar button label shadow, Done type | `TGToolbarButton.m:197` |
| `rgba(#050608, 0.4)` | Shadow for a modal back button | `TGContactsController.mm:484` |

**Bar title shadow rule.** Every white-on-blue bar label carries a shadow of offset `(0, -1)`,
blur `0`, and one of the colours above. `titleShadowOffsetForStyle:` returns `(0, -1)` for both
styles (`TGViewController.mm:169-179`). No exceptions in new code.

### 2.2 Chat list

| Hex | Role | Source |
|---|---|---|
| `#FFFFFF` | Chat-list background and row background | `TGInterfaceAssets.mm:165-173`, `TGDialogListCell.m:1094` |
| `#EBF0F5` | Row background when the chat is unread | `TGDialogListCell.m:1095` |
| `#111111` | Row title | `TGDialogListCell.m:193` |
| `#229A0A` | Row title for a secret chat | `TGDialogListCell.m:194` |
| `#FFFFFF` | Row title when the row is highlighted | `TGDialogListCell.m:195` |
| `#345F8F` | "Alice: " author prefix in the preview | `TGDialogListCell.m:196` |
| `#888888` | Message preview, read | `TGDialogListCell.m:791,1096` |
| `#5B646E` | Message preview, unread | `TGDialogListCell.m:1097` |
| `#536C8C` | Preview text for an action or a media attachment ("Photo", "joined the group") | `TGDialogListCell.m:792-793` |
| `#337ACC` | Date on the right of the row | `TGDialogListCell.m:394` |
| `#FFFFFF` on `#8091A6` shadow | Unread-count badge label; shadow offset `(0, -1)` | `TGDialogListCell.m:417-421` |
| `#2371C2` | Unread-count label when the row is highlighted (shadow becomes clear) | `TGDialogListCell.m:421-422` |
| `#E4E9F0` | Sticky section/header strip above a list | `TGInterfaceAssets.mm:177`, `TGContactsController.mm:506` |
| `#DFE4EB` | The same strip, inner container | `TGContactsController.mm:549` |
| `#8B97A5` | Empty-list title and body | `TGDialogListController.mm:898,910` |
| `#8D9298` | Search-field placeholder | `TGDialogListController.mm:440` |

Swipe-to-delete label: white `boldSystemFontOfSize:13`, shadow `rgba(#A30F0A, 0.2)` at `(0, -1)`,
blur 0, drawn into the button image (`TGDialogListCell.m:450-459`).

### 2.3 Contacts and grouped tables

| Hex | Role | Source |
|---|---|---|
| `#888888` | Contact subtitle ("last seen…") | `TGContactCell.m:347` |
| `#778698` | Contact subtitle when the contact is online | `TGContactCell.m:765` |
| `#FFFFFF` | Contact title/subtitle when highlighted | `TGContactCell.m:348` |
| `#E9EFF5` | Highlighted row background in a contact list | `TGContactCell.m:750` |
| `#D5DEE5` | The hairline above and below that highlighted row | `TGContactCell.m:753,757` |
| `#E5E5E5` | Hairline above a full-width action row | `TGBlockActionCell.m:84` |
| `#0779D0` | Action/link text ("Block user", a tappable contact row) | `TGBlockActionCell.m:59`, `TGUserMenuItemCell.m:286`, `TGProfileController.m:544` |
| `rgba(#000000, 0.53)` | The same row's text when inactive | `TGProfileController.m:543` |
| `#516691` | Grouped-row title in an action cell, and a row's value label | `TGActionMenuItemCell.m:77`, `TGLabelMenuItemView.m:41,73` |
| `#356596` | Grouped-row value (the blue number/word on the right) | `TGVariantMenuItemCell.m:38` |
| `#697487` | Section footer / comment text under a group of rows | `TGCommentMenuItemView.m:38` |
| `#DAE0E8` | Its shadow, offset `(0, +1)` | `TGCommentMenuItemView.m:39-40` |
| `#FFFFFF` on `#88929C` shadow | Section header label over a contact list, offset `(0, -1)` | `TGContactsController.mm:1310-1312` |
| `#697487` on `rgba(#FFFFFF, 0.3)` shadow | Header title/subtitle inside a list, offset `(0, +1)` | `TGContactsController.mm:684-698` |

Destructive button inside a grouped table (`TGButtonMenuItemCell.m:77-120`): white label, shadow
`rgba(#A10603, 0.5)` at `(0, -1)`. Neutral button: `#4A6587` label, shadow `rgba(#FFFFFF, 0.45)` at
`(0, +1)`. Green/confirm button: shadow `rgba(#124606, 0.3)` at `(0, -1)`.

### 2.4 Profile header

| Hex | Role | Source |
|---|---|---|
| `#222932` | Profile name | `TGProfileController.m:780` |
| `#6D7D90` | Profile status line | `TGProfileController.m:789` |
| `rgba(#EDF0F5, 0.28)` at `(0, +1)` | Shadow under both of the above | `TGProfileController.m:781-782, 790-791` |
| `rgba(#47586C, 0.5)` at `(0, -1)` | Shadow under the "add photo" caption (white text) | `TGProfileController.m:758-768` |

### 2.5 Messages

| Hex | Role | Source |
|---|---|---|
| `#141617` (rgb 20,22,23) | Message body text, both directions | `TGTelegraphConversationMessageAssetsSource.m:175` |
| nil | Message body text shadow — **there is none** | same file, `messageTextShadowColor` |
| `#4D688C` | Author name inside a group bubble (default; per-user colours override, §2.6) | `:342` |
| nil | Author-name shadow | `messageAuthorNameShadowColor` |
| `#232D37` | Timestamp inside a bubble | `:915` |
| nil | Timestamp shadow | `messageDateShadowColor` |
| `#FFFFFF` | Service-message text ("X joined the group") | `:293` |
| nil | Service-message text shadow (the plate carries the contrast) | `:297` |
| `#62768A` | Attachment title on a one-line attachment | `:195` |
| `#72879B` | Attachment subtitle | `:203` |
| `#FFFFFF` on `#111111` shadow | Document type label drawn on a file thumbnail | `:211,219` |
| `#141617` | Forwarded-from user name | `:225` |
| `#999999` | Forwarded-from date | `:235` |
| `#0E7ACD` | "Forwarded from" title and name, incoming | `:243,259` |
| `#3A8E26` / `#169600` | The same, outgoing (title / name) | `:251,267` |
| `#506E8D` | Label on an in-bubble action button ("Download") | `TGConversationMessageItemView.mm:1479` |
| `rgba(#FFFFFF, 0.7)` normal, `rgba(#FFFFFF, 0.5)` pressed, offset `(0, +1)` | That button's label shadow | `:1481-1483` |
| `rgba(#003871, 0.07)` | Wash over the unread block of messages | `TGTelegraphConversationMessageAssetsSource.m:891` |
| `rgba(#5E7590, 0.2)` | Highlight wash over an attachment | `:312` |
| `#CC1E2C` | Shadow under the delivery-error badge text (white), offset `(0, -1)` | `:828` |

Composer: placeholder `#9DA7B3` at `systemFontOfSize:16` (`TGConversationController.mm:990-991`).
Send button: white `boldSystemFontOfSize:14.5`, shadow `rgba(#0CB8E3, 0.3)` at `(0, -1)`, disabled
title `#BBFFB2` (`#CEFFB0` on a 4-inch screen) — `TGConversationController.mm:1020-1025`.

Selection-mode toolbar buttons: white label, shadow `rgba(#9E0A01, 0.3)` for Delete and
`rgba(#3C6696, 0.5)` for Forward; the "N selected" caption is `#576D85`
(`TGConversationController.mm:4961-5034`).

### 2.6 The eight identity colours

Per-user avatar and author-name colour, chosen by `MD5(uid + selfUid) % 8`
(`TGInterfaceAssets.mm:100-116`). Use exactly these, in this order, and use the same index for the
avatar and the in-bubble name so a person is one colour everywhere:

`0 #EE4928`, `1 #41A903`, `2 #E09602`, `3 #0F94ED`, `4 #8F3BF7`, `5 #FC4380`, `6 #00A1C4`,
`7 #EB7002`.

Group avatars use a 4-entry set indexed by `MD5(groupId) % 4` (`TGInterfaceAssets.mm:46-69`); the
original ships them as artwork (`DialogListGroupAvatar1..4.png`), not as constants. In this repo
generate them with `+[TGIcons avatarWithInitials:size:colourId:]` and pass `colourId` so the same
chat always lands on the same hue.

---

## 3. Shadow treatments

There are only four shadow recipes in the whole app. Do not invent a fifth.

1. **Sunken text on a bar or a coloured button** — offset `(0, -1)`, blur `0`, a dark tint of the
   surface at 20–50 % alpha, or a solid dark blue-grey. Every bar title, bar button, badge label,
   tab caption and destructive button uses this.
2. **Raised text on a light grey surface** — offset `(0, +1)`, blur `0`, near-white or a light
   tint: `rgba(#FFFFFF, 0.3)`, `rgba(#FFFFFF, 0.45)`, `#DAE0E8`, `rgba(#EDF0F5, 0.28)`. Section
   footers, list headers, the profile name, in-bubble action buttons.
3. **No shadow at all** — message body, author name, timestamp, service text. All four return nil
   in the original and the code that would have drawn them is commented out. Do not add a shadow to
   in-bubble text under any circumstance.
4. **Drop shadow as artwork** — bubbles, the list-cell edge and the profile header do not use
   `CALayer.shadow*`; they use a PNG (`ListCellShadow.png` 2×2 pt, `Profile_Shadow.png`,
   `Msg_*_Selected_Shadow.png`) stretched under the view. Ruling: keep it that way, or draw the
   gradient yourself. `CALayer` shadows are a per-frame rasterise the A5 cannot afford on a
   scrolling list.

Where the original does light a real blur, it is a 1 pt inner highlight in a drawn control:
`CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 1.0f, rgba(#FFFFFF, 0.3))`
(`TGTelegraphConversationMessageAssetsSource.m:447-448`). Reuse those exact parameters if you draw
a new circular control.

---

## 4. Separators, backgrounds and grouped tables

**Every list in the app sets `separatorStyle = UITableViewCellSeparatorStyleNone`.** This is true of
all 23 table views in the original (`TGDialogListController.mm:538`, `TGContactsController.mm:499`,
`TGProfileController.m:696`, and so on). Separators are drawn by the cell, not by UIKit. New screens
must do the same: set the style to none and draw your own hairline.

Rules for drawing them:

* A plain list hairline is a 1 px (`1.0 / scale`) `UIView` with `backgroundColor` `#D5DEE5` above
  and below the highlighted row (`TGContactCell.m:753,757`); `#E5E5E5` above a full-width action
  row (`TGBlockActionCell.m:84`). Ruling: use `#D5DEE5` inside a white content list and `#E5E5E5`
  where the row sits against a grey surface. In code, call `[[TGTheme shared] separatorColour]` so
  the flat and dark styles get theirs.
* A grouped table is not UIKit's grouped style; it is four stretchable PNGs on a patterned ground:
  `GroupedCellTop.png`, `GroupedCellMiddle.png`, `GroupedCellBottom.png`, `GroupedCellSingle.png`
  plus `_Selected` variants (`TGInterfaceAssets.mm:635-720`). At @2x the first three are 58×88 px
  and the single is 52×88 px, i.e. 29×44 pt and 26×44 pt in points. Cap insets are computed as
  half the width and half the height, except the selected variants: top uses
  `topCapHeight = height - 2`, bottom uses `topCapHeight = 1`. Build them with
  `stretchableImageWithLeftCapWidth:topCapHeight:` — **never** `resizableImageWithCapInsets:`,
  which is not on iOS 6.1.3.
* The ground behind a grouped table is a tiled pattern, not a flat colour:
  `[UIColor colorWithPatternImage:[UIImage imageNamed:@"SettingsBackground.png"]]`
  (`TGInterfaceAssets.mm:141-151`), with `Linen.png` / `DarkLinen.png` / `Footer.png` for the other
  patterned surfaces. Ruling: in the skeuomorphic style use the pattern; in the flat and dark
  styles use `[[TGTheme shared] listBackgroundColour]` and a flat 1 px separator.
* Chat-list and contact-list background is plain `#FFFFFF` (`TGInterfaceAssets.mm:165-173`). A
  sticky section strip over it is `#E4E9F0`; the section divider artwork is `CategoryDivider.png` /
  `CategoryDividerFirst.png`, 2×52 px at @2x — a 1 pt wide, 26 pt tall strip stretched horizontally
  with `stretchableImageWithLeftCapWidth:0 topCapHeight:0` and drawn at `y = -1, height = 11`
  above the section (`TGContactsController.mm:1301-1303`).
* Disclosure arrow: `MenuDisclosureIndicator.png` and `_Highlighted`
  (`TGInterfaceAssets.mm:725-737`). Do not use `UITableViewCellAccessoryDisclosureIndicator`; it
  draws the system chevron, which is the wrong grey and the wrong size.

Tab bar: background `TabBarBackground.png` and selection `TabBarSelected.png`, both 6×98 px at @2x
(3 pt wide, 49 pt tall) stretched horizontally; the bar is 49 pt. Captions are
`boldSystemFontOfSize:10` in `#999999`, white when selected. The badge is `TabBarBadge.png`
(40×40 px @2x = 20×20 pt) with `stretchableImageWithLeftCapWidth:10 topCapHeight:0` and an
`11 pt bold` white label (`TGMainTabsController.m:52-172`).

Chat-list unread badge: `DialogListUnreadBadge.png`, 54×42 px @2x (27×21 pt), cap insets half the
width and half the height; the badge frame is 21 pt tall
(`TGInterfaceAssets.mm:212-224`, `TGDialogListCell.m:1286`).

Bubbles: `Msg_In.png` and `Msg_Out.png` are 80×62 px @2x (40×31 pt). Incoming caps are
`leftCapWidth:20 topCapHeight:15`; outgoing are `leftCapWidth:15 topCapHeight:15`
(`TGTelegraphConversationMessageAssetsSource.m:652,721`). The asymmetry is the tail — do not
copy the incoming caps onto an outgoing bubble.

---

## 5. Rendering modern concepts in this idiom

Nothing below existed in 2013, so nothing below is quoted. These are rulings. Follow them exactly;
they exist so that twenty agents building twenty features produce one app.

* **Reaction row.** A reaction chip is the in-bubble action button:
  `MediaActionButton.png` stretched with `leftCapWidth = width / 2, topCapHeight = 0`, label
  `boldSystemFontOfSize:13` in `#506E8D`, shadow `rgba(#FFFFFF, 0.7)` at `(0, +1)`. The chip is
  22 pt tall, 6 pt of padding either side of `emoji + " " + count`, 4 pt between chips, and the row
  sits 4 pt under the last line of bubble text with the timestamp pushed to the line below. The
  chip the user has picked swaps its background for `MediaActionButton_Highlighted.png` and its
  label to `#FFFFFF` with shadow `rgba(#042651, 0.3)` at `(0, -1)`. Never draw a rounded rect in
  code; never use a pill of the accent colour.
* **Reply header inside a bubble.** Reuse the forwarded-from treatment exactly: name in
  `boldSystemFontOfSize:13` at `#0E7ACD` incoming / `#169600` outgoing, quoted line in
  `systemFontOfSize:13` at `#999999`, one line only with a tail-truncated ellipsis, plus a 2 pt
  vertical bar in the same colour as the name, 4 pt to the left of the text. No shadow.
* **Reply-to bar above the composer.** Background is the input strip
  (`[[TGTheme shared] inputBarColour]`), height 39 pt, a 1 px `#D5DEE5` hairline along the top,
  name at `boldSystemFontOfSize:13` `#4D688C`, preview at `systemFontOfSize:13` `#888888`.
* **Stickers.** A sticker is a transparent image with no bubble, no shadow and no border. Its
  timestamp goes on `MessageTimestampBackground.png` (38×42 px @2x, caps = half width / 0) at the
  bottom-right of the image, label `systemFontOfSize:11` in `#FFFFFF` with shadow
  `rgba(#000000, 0.3)` at `(0, +1)` — the same treatment the original gives a timestamp over a
  photo. Sticker-pack titles in a picker use `boldSystemFontOfSize:13` `#697487`.
* **Media grid (shared media, sticker grid, GIF grid).** No `UICollectionView` — it is unavailable.
  Lay tiles out yourself inside a `UIScrollView` or a table of row-views. Tiles are square, 4 pt
  gutter, placeholder `FlatImagePlaceholder.png`, and every tile carries
  `mediaGridImageShadow` artwork rather than a `CALayer` shadow. Grid background `#FFFFFF`.
* **Premium / verified / scam badge.** A glyph, never a coloured pill and never a gradient. Draw it
  9×9 pt, baseline-aligned with the title, 4 pt after the last glyph of the name, in `#0E7ACD` for
  verified and premium and `#CC1E2C` for scam/fake. Do not tint the name itself.
* **Folders (chat filters).** Render the folder strip as a scope bar, not as modern pill tabs:
  `SearchBarScopeButton.png` / `_Highlighted.png` background, caption `boldSystemFontOfSize:12`,
  selected white with shadow `rgba(#112E5C, 0.2)`, unselected `#5C708B` with shadow
  `rgba(#FFFFFF, 0.25)` — the exact attributes from `TGDialogListController.mm:511-521`. Unread
  counts beside a folder name reuse the chat-list badge asset and its `#8091A6` shadow.
* **Pinned chat.** Row background `#EBF0F5` (the unread background), no extra icon colour change.
* **Muted chat.** Badge tint becomes `[[TGTheme shared] mutedBadgeColour]`; the title stays
  `#111111`. Do not grey the title.
* **Message editing.** The "edited" marker is part of the timestamp run: `systemFontOfSize:11` in
  `#232D37`, no shadow, one space before the time.
* **Any new accent surface** you cannot map to a row above: use `#0779D0` for a tappable word,
  `#516691` for a static grouped-row title, `#888888` for secondary text, `#697487` for a caption
  under a group. Those four cover almost everything.

---

## 6. Where the original genuinely has no answer

* **Dark mode.** The 2013 app has no dark theme. `titleShadowColorForStyle:` has a second branch
  (`#2F3948`) for a darker bar, and there are `DarkLinen.png` and `ProfilePhotoPlaceholder_Mono`
  monochrome assets, but no dark palette. Everything in `TGTheme`'s dark branch is invention;
  treat `TGTheme`'s dark values as authoritative for this repo and do not derive new dark colours
  from the hexes in this chapter.
* **Flat / iOS 7 styling.** Likewise absent. The flat style in `TGTheme` comes from Telegram's
  later design system, not from this source. When a screen must look right in both, set colours via
  `TGTheme` accessors and let the two branches differ; do not hard-code a hex from §2 into a view
  that also renders flat.
* **Group avatar colours as constants.** Only the eight per-user colours exist as hex. The
  four-colour group set exists only as PNGs, so the hexes for it are a project decision, delegated
  to `+[TGIcons avatarWithInitials:size:colourId:]`.
* **A section-header font for a grouped settings table.** The original's settings screens use a
  patterned ground and a comment view, not a UIKit section header, so there is no
  "small grey uppercase caption" anywhere. Ruling: if you need one, use
  `systemFontOfSize:14` in `#697487` with the `#DAE0E8` `(0, +1)` shadow — the comment-view
  treatment — and do not uppercase it.
* **Non-retina sizes.** Several sizes are written as `x + retinaPixel`, so the intended non-retina
  size is the base number. There is no @1x artwork in `Resources/`; everything is `@2x`. Assume
  retina and let UIKit downscale.

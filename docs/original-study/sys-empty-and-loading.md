# Empty, loading and failure states in Telegram for iOS 1.1 (2014)

Scope: what the original put on screen when a list had nothing in it, when a screen was waiting for
the network, when a permission had been refused, and when a request failed. All citations are to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`, paths
relative to that root. Comparisons at the end are to
`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS` (modern), `/Users/alexanderhavrysh/Git/iOS/twelve`
(later ObjC fork) and `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src` (ours).

---

## 0. The system, in one page

The original had **no generic empty-state component and no generic loading component**. Every state
was hand-built at the point of use. But the hand-building followed a very consistent recipe, and
that recipe is the thing worth porting:

1. **An empty list is never an empty table with a label in a cell.** It is a *container view*, sized
   to its own content, positioned by arithmetic against the view's centre, holding an **icon above a
   bold title above a regular-weight wrapped body**. The table view is hidden or faded out behind it.
   (`TGDialogListController.mm:885`, `TGPhotoGridController.mm:700`,
   `TGBlockedUsersController.mm:82`, `TGConversationController.mm:6136`.)
2. **Loading is never a text row saying "Loading…"** except in the loading *footer* of a paged list,
   where it is a spinner with no text at all (`TGPhotoGridController.mm:273-296`,
   `TGConversationController.mm:3582-3617`).
3. **Network state is a navigation-bar title, not a screen.** "Connecting…" / "Updating…" /
   "Waiting for network" replace the title, with a small spinner to the left of it
   (`TGTelegraphDialogListCompanion.mm:686-712`, `TGDialogListController.mm:338`,
   `TGConversationController.mm:5603`).
4. **Blocking work is a 100×100 rounded HUD window above the status bar**, never an inline spinner
   (`TelegraphKit/TelegraphKit/TGProgressWindow.m:20-36`).
5. **Failure is a `UIAlertView` with a specific sentence**, not an inline error state. Every error
   string in `en.lproj/Localizable.strings` is a full sentence ending in a period, and the generic
   one is `"An error occurred. Please try again later"` (line 182). There is no retry button
   anywhere; the alert has OK only.
6. **A refused permission gets the most designed screen of all** — full-bleed overlay, 170×170 pt
   glyph, bold 17 title, and a multi-line body whose "ON"/"Settings" word is bolded inline via
   `NSAttributedString` (`TGContactsController.mm:662-760`, `TGPeopleNearbyController.m:140-232`,
   `TGLoginInactiveUserController.m:256-330`).

The unifying principle: **a state with no data still has a designed weight on screen.** The only
places the original allowed a bare label were the loading *footer* of a paged list (spinner, no
label) and the image-search "nothing found" line.

---

## 1. Empty lists

### 1.1 Chat list — the canonical empty state

`TelegraphKit/TelegraphKit/TGDialogListController.mm:885-929`

| Property | Value | Line |
| --- | --- | --- |
| Container width | fixed 250 pt; height computed from content | 889 |
| Insertion | `insertSubview:belowSubview:_tableView` — behind the table, not in it | 890 |
| Icon | `NoMessages.png` (204×182 px @2x = 102×91 pt), horizontally centred, y = 0 | 891-893 |
| Title | `DialogList.NoMessagesTitle` = "You have no conversations yet" | 899, strings:227 |
| Title font/colour | `boldSystemFontOfSize:15`, `UIColorRGB(0x8b97a5)` | 897-898 |
| Title y | `icon.maxY + 21` | 901 |
| Body | `DialogList.NoMessagesText` = "Start messaging by pressing the pencil button in the top right corner or go to the Contacts section." | 911, strings:228 |
| Body font/colour | `systemFontOfSize:14`, same `0x8b97a5` | 909-910 |
| Body wrap width | `sizeThatFits:CGSizeMake(232, 1000)` — 232, i.e. 250 minus 9 pt each side | 912 |
| Body y | `title.maxY + 8`, centred on the *measured* width, not on 232 | 913 |
| Container y | `floor((view.height - containerHeight) / 2)` — true vertical centre of the whole view, ignoring the navigation bar | 918 |
| Table | `_tableView.hidden = _listModel.count == 0` | 927 |

Notes that only show up with real data:

- The container is **centred on the full view height**, not on the content area. On a 4S in portrait
  under a 44 pt bar plus 20 pt status bar, that pushes the block visibly low. This is what the
  original did; it is not a bug in our port if we reproduce it.
- There is **no fade**. The chat-list placeholder appears and disappears instantly
  (`updateEmptyListContainer` just adds/removes), unlike the media grid and the conversation, which
  both animate. This is the first internal inconsistency (see §6).
- `shouldDisplayEmptyListPlaceholder` (`TGDialogListCompanion.h:49`, default `true` at
  `TGDialogListCompanion.m:84`) gates visibility at line 929. In v1.1 **no companion overrides it**
  — grep finds only the declaration and the default. It exists so a picker/forward-target list can
  suppress the "you have no conversations" wording, which would be wrong in that context. Ours needs
  the same escape hatch for the forward picker.

### 1.2 Shared media grid — icon + single line, faded

`Telegraph/Telegraph/TGPhotoGridController.mm:700-772`

- Condition is **not** "list is empty" but `!_canLoadMore && _presentationListModel.count == 0`
  (line 702). While more pages may still arrive, the screen shows the loading footer instead of the
  placeholder. This is the correct rule and the one most commonly got wrong: **never show an empty
  state while a first page is still in flight.**
- Image `PhotosBlankPlaceholder.png` (530×360 px @2x = 265×180 pt), line 710.
- Label: `ConversationMedia.Empty` = "No Photos in this Conversation" (strings:501),
  `boldSystemFontOfSize:17`, `UIColorRGB(0x808895)`, **opaque white background** (lines 712-716) —
  the label is not transparent, it paints white, because the grid background is white.
- Layout: container width = `MAX(image.width, label.width)`; height =
  `label.height + image.height + 12 + 36` (line 718). The label sits at `image.height + 12`
  (line 728). The trailing **36 is dead space at the bottom of the container**, which, because the
  container is centred, lifts the visible content 18 pt above the true centre. That is deliberate
  optical centring, and it is the only place in the codebase that does it this way.
- Transition: 0.2 s cross-fade, placeholder in / table to `alpha 0` (lines 733-739); reverse on
  non-empty, and on completion the table's background is reset to white (line 762).
- `_appearAnimation` suppresses the fade when the screen is still doing its push animation
  (lines 732, 745) — the same "don't animate during appearance" guard appears in the conversation
  as a 0.15 s window (`TGConversationController.mm:6231`).

### 1.3 Conversation with no messages — a system-message plate

`TelegraphKit/TelegraphKit/TGConversationController.mm:6136-6274`

This is not an "empty state" visually at all; it is styled as a service message bubble.

- Plain chat: container 122×116 pt (line 6141), background is
  `[messageAssetsSource systemMessageBackground]` — the same stretchable art as a "X joined the
  group" bubble (6146).
- Glyph `ConversationIconPlain.png` at x centred, **y = 23** (6207).
- Label: `boldSystemFontOfSize:13`, colour `[messageAssetsSource messageActionTextColor]` (so it
  follows the wallpaper theme, not a hard-coded grey), centred, `numberOfLines = 0`, wrap width
  **110** (6213-6222), positioned at `containerHeight - labelHeight - 8`, i.e. **bottom-anchored**
  8 pt from the plate's bottom edge (6223). With a two-line string the glyph does not move; the text
  grows upward into the gap.
- Text: `Conversation.EmptyPlaceholder` = "No messages here yet..." (strings:333). Special case:
  conversation id `333000` (Telegram support) shows `Conversation.SupportPlaceholder` = "Got a
  question about Telegram?" (6220-6221, strings:332).
- Secret chats get a much larger 229×185 plate with a title, a "description title" and four
  lock-bulleted lines at 22 pt pitch (6141, 6158-6203).
- Positioning (`updateEmptyConversationContainer`, 6268-6274): horizontally centred; vertically
  `viewInsetOffset + floor((viewHeight - h) / 2) + (viewHeight > 140 ? 43 : 0)` where
  `viewInsetOffset` is `controllerInset.top - 64` on tall views and `-14` on short ones. The `+43`
  is a nudge to keep the plate optically above the input panel; the short-view branch exists for the
  landscape keyboard case.
- Fade in/out 0.3 s, but only if more than 0.15 s has passed since `_appearingAnimationStart`
  (6231-6243, 6245-6262); during the push it snaps.

### 1.4 Blocked users — text-only, but still a container

`Telegraph/Telegraph/TGBlockedUsersController.mm:82-107`, `221-260`

The one empty state with no artwork, and it still gets two labels in a sized container:

- Container: full width × **70 pt**, y = `floor((view.height - 70)/2)`, autoresizing to stay centred
  (82-83).
- Line 1: `boldSystemFontOfSize:14`, `UIColorRGB(0x8694a4)`, white 50 % shadow at (0, 1),
  text `BlockedUsers.EmptyListLabel` = "You haven't blocked anyone yet." (86-93, strings:585).
- Line 2: `systemFontOfSize:14`, same colour and shadow, `numberOfLines = 0`, centred, wrap width
  **260**, y = **26** (95-106, strings:586 "You will not see any messages from users you blocked.").
- `updateEmptyState:` (221): sets `_tableView.scrollEnabled = false` while empty — the rubber-band
  bounce is disabled so the placeholder cannot be dragged around — and cross-fades the table's
  background colour to clear over 0.3 s so the `0xe9edf3` view background shows through.

The white 50 % top shadow on `0x8694a4` over `0xe9edf3` is the standard 2013 "engraved grey text on
a light panel" treatment; it appears again in the permission overlays at 30 % (§3).

### 1.5 Image search — "No images found for **query**"

`TelegraphKit/TelegraphKit/TGImageSearchController.mm:299-306, 551-596`

- Label: `systemFontOfSize:15`, `UIColorRGB(0xa8a8a8)`, centred, multi-line.
- Text is composed as prefix + query, with the **query rendered bold at the same point size** via
  `NSAttributedString` when available, plain concatenation on iOS 5 (551-577). Prefix
  `SearchImages.NoImagesFoundForPrefix` = "No images found for " (strings:443) — note the trailing
  space is in the string, not in the format.
- Position: measured against `screenSize.width - 20`, then centred in the **screen**, not the view
  (591-593), so it does not shift when the keyboard is up.
- Cleared to `nil` (and hidden, 584) at the start of every search and whenever the field empties
  (699, 1594-1600) — the failure text never survives into the next query.

---

## 2. Loading

### 2.1 The house spinner: `TGActivityIndicatorView`

`TelegraphKit/TelegraphKit/TGActivityIndicatorView.m`

A `UIImageView` subclass playing a 24-frame sprite sequence, not `UIActivityIndicatorView`.

| Style | Frames | Asset pattern | Size |
| --- | --- | --- | --- |
| `…StyleSmall` | 1…24 | `grayProgress%d.png` (`Resources/ProgressIndicator/`) | 30×30 px @2x = **15×15 pt** |
| `…StyleLarge` | 0…24 (25) | `navbar_big_progress_%d.png` (`Resources/ProgressIndicatorLarge/`) | — |
| `…StyleSmallWhite` | 1…24 | `RProgress%d.png` (`Resources/ProgressIndicatorWhite/`) | 30×30 px @2x = **15×15 pt** |

The frame arrays are built once into file-static arrays (memoised per style, lines 6-56) — on a 4S,
loading 24 PNGs per spinner instance would be visible. `animationDuration` is **never set**, so
UIKit's default of `frameCount / 30` applies: 24 frames → **0.8 s per revolution**, 25 → 0.833 s.
Any port that uses a different duration will look subtly wrong next to period screenshots.

Note the gray/white pair: `Small` is for light backgrounds (grid footers), `SmallWhite` for the blue
navigation bar and for dark system-message plates.

### 2.2 Network state in the navigation title

Producer: `Telegraph/Telegraph/TGTelegraphDialogListCompanion.mm:680-712`. The synchronisation
state is a bitmask on `/tg/service/synchronizationstate`:

```
bit 1 (state & 1)  → Updating
bit 2 (state & 2)  → Connecting
bit 2|4            → WaitingForNetwork
none               → Normal
```

mapping to `State.Updating` = "Updating...", `State.Connecting` = "Connecting...",
`State.WaitingForNetwork` = "Waiting for network" (strings:61-63). Note that only *Connecting* and
*Updating* carry the ellipsis; "Waiting for network" does not — it is a terminal condition, not a
process.

Presentation, chat list (`TGDialogListController.mm:258-279, 338-357`):

- Container 40×30, `clipsToBounds = false` — the 40 is a placeholder width; the label and spinner
  overflow it, which is why clipping must stay off. Returned as the controller's title view only
  while `_showTitleStatus` (282-290); otherwise the plain title is used.
- Label is a `TGLabel` with `verticalAlignment = Top`, `boldSystemFontOfSize:15`, white,
  shadow `UIColorRGB(0x415a7e)` at offset **(0, −1)** (265-272) — the standard upward navigation-bar
  text shadow.
- Layout (345-346): the label is centred *as if* the spinner plus a 5 pt gap were part of it —
  `x = (containerW − labelW + spinnerW + 5) / 2` — and the spinner is then placed at
  `label.x − spinnerW − 5`. So the **pair** is centred, not the label. `y = (containerH − labelH)/2 − 1`
  for the label and `label.y + 3` for the spinner, wrapped in `CGRectIntegral`.
- The spinner starts/stops only on an actual change of `isAnimating` (348-354), so a state refresh
  does not restart the animation mid-revolution.

The conversation screen repeats this verbatim with two deltas
(`TGConversationController.mm:5516-5574`): the container is pre-centred inside `_titleContainer`
(`x = (titleContainerW − 40)/2`) and the label's vertical offset is **−3** rather than −1
(5573), because the conversation title stack is two lines (title + status) instead of one.

### 2.3 Paged lists: a spinner-only footer row

Shared-media grid, `TGPhotoGridController.mm:123, 273-296`: a `UIActivityIndicatorView` of style
**Gray** (this one *is* a UIKit spinner) added once to a reused `"LC"` cell, x-centred,
**y = 14** in the cell's content view, hidden and stopped when `_loadingMore` is false. No text.

Conversation history top, `TGConversationController.mm:3582-3617`: the load-more cell draws the
`systemMessageBackground` art **rotated by π** into a 21 pt-wide strip at y = 3 (plus a half-pixel
height bump on retina, line 3596), with a `SmallWhite` sprite spinner also rotated by π at
`y = 4 + 3 = 7`. Both are hidden together when `_canLoadMoreHistory` is false. The rotation is
because the conversation table is itself flipped upside down.

### 2.4 Blocking work: `TGProgressWindow`

`TelegraphKit/TelegraphKit/TGProgressWindow.m`

- A `UIWindow` at `UIWindowLevelStatusBar` (line 19) — it covers the status bar and swallows all
  touches (`userInteractionEnabled = true` on show, line 41).
- Container **100×100**, centred, all four flexible margins, starts at `alpha 0` (21-24).
- Background: `ProgressWindowBackground.png` (32×32 px @2x = 16×16 pt) made stretchable with caps at
  **half its point size in each axis** (`leftCapWidth: w/2`, `topCapHeight: h/2`, lines 26-28), i.e.
  a 16 pt rounded black square stretched to 100×100.
- Spinner: `UIActivityIndicatorViewStyleWhiteLarge`, integer-centred (30-33). Note: the *only*
  UIKit large spinner in the app; the sprite spinner is not used here.
- Show/dismiss: 0.3 s alpha fade (46-52, 61-64). On dismissal the window is hidden and key status is
  handed back to the topmost other window (68-78) — required, or the app loses first responder.
- `dismissWithSuccess` (91-118): removes the spinner, drops in `ProgressWindowCheck.png`
  (78×80 px @2x = 39×40 pt) centred, **holds for 0.5 s**, then fades out over 0.3 s. This is the
  "saved" confirmation, used after profile photo upload, logout, session termination and similar
  (8 call sites, e.g. `TGProfileController.m:364`, `TGChatSettingsController.m:52`,
  `TGLoginPhoneController.m:41`, `TGSelectContactController.m:27`).

### 2.5 The loupe spinner

`TelegraphKit/TelegraphKit/TGSearchLoupeProgressView.m` — a 33×34 magnifier frame
(`ProgressLoupeFrame.png`) with two clock hands (`ProgressLoupeHour/Minute.png`) both offset to
(10.5, 2.5), each animated by chained π/2 `CGAffineTransformRotate` steps: minute hand 0.3 s per
quarter turn, hour hand 1.8 s (`MINUTE_DURATION * 6`), linear curve, self-rescheduling in the
completion block (31-80). Used only in image search, screen-centred, shown for the duration of the
request (`TGImageSearchController.mm:290-297, 701-702, 1579`).

### 2.6 Progress on media

`TGCircularProgressView` (`TelegraphKit/TelegraphKit/TGCircularProgressView.m`): default 50×50,
annular by default, `lineWidth = 4`, `radius = (width − 13) / 2`, start angle −π/2, clockwise, white.
The cap style switches from **round to square exactly at progress = 1.0** (line 61) so the closed
ring has no overlapping bulge. The non-annular mode is a filled pie with `radius = (width − 4)/2`
(73-82). `setProgress:` early-outs below `FLT_EPSILON` of change, so it is safe to call per packet.

Image loading, `TelegraphKit/TelegraphKit/TGRemoteImageView.m`:

- `_fadeTransitionDuration = 0.14` (line 101) — the app-wide image fade.
- The placeholder view is only created when `setFadeTransition:` is turned on (120-139).
- **Cache hit = no fade at all**: the image is assigned and the placeholder is hard-hidden
  (`alpha 0`, `hidden = true`, image nil, 332-339). Only `forceFade:true` (used for the user's own
  avatar after upload, `TGProfileController.m:1730`) fades a cached image in.
- **Cache miss**: placeholder image shown, and if `_allowThumbnailCache` a cached blur thumbnail
  *replaces* the generic placeholder (348-352) — so the loading state for a photo is the blurred
  thumbnail, not a grey box.

---

## 3. Refused permissions — the most designed state

Three near-identical implementations, which is itself informative: this shape was copy-pasted
rather than factored out.

**Common recipe.** A full-bounds overlay with `linesBackground` (=
`colorWithPatternImage:SettingsBackground.png`, `Telegraph/Telegraph/TGInterfaceAssets.mm:143-151`),
containing a **40×4 pt anchor view** centred in the overlay with all four flexible margins and
`clipsToBounds = false`. Everything is then laid out at *negative and positive offsets from that
4 pt anchor*, so a single centre point drives the whole composition and it stays centred under
rotation for free. Views are addressed by tag: 100 anchor, 200 icon, 300 title, 400 subtitle.

### 3.1 Contacts denied — `TGContactsController.mm:662-760`

| Element | Value |
| --- | --- |
| Icon | `ContactsIcon.png`, 170×170 px @2x = **85×85 pt**, y = `(portrait ? −113 : −100) + additionalOffset` |
| `additionalOffset` | portrait: `isWidescreen ? −20 : −15`; landscape: `+12` |
| Title | `Contacts.AccessDeniedError` = "Telegram does not have access to your contacts", `boldSystemFontOfSize:17`, `UIColorRGB(0x697487)`, white-30 % shadow at (0, 1), centred, wrap width **265**, y = `−10 + additionalOffset` |
| Body | `boldSystemFontOfSize(retina ? 14.5 : 15.0)` on the label, but the attributed run uses `systemFontOfSize` at the same size with only the word "ON" bold; colour `0x697487`, wrap width **210** portrait / **480** landscape, y = `41 + additionalOffset` |
| Body text | `Contacts.AccessDeniedHelpPortrait` / `…Landscape` (strings:258-259), `%@` = "iPhone"/"iPod"/"iPad" sniffed from `[[UIDevice currentDevice] model]` |
| Side effect | the "+" add-contact button is hidden while the overlay is up (line 707) |

The `14.5` on retina is not a typo: the original deliberately used a half-point size where the
retina grid could render it, and rounded up to 15 on 1× devices. The 4S is retina, so **14.5**.

### 3.2 Location denied — `TGPeopleNearbyController.m:140-232`

Same skeleton with `LocationIcon.png` (also 170×170 px = 85×85 pt) at
`y = −110 + additionalOffset`, `additionalOffset = portrait ? (widescreen ? −30 : −26) : −4`, title
at `−7`, subtitle at `+25`, title wrap 265, subtitle wrap **300** portrait / **440** landscape.
Its strings are **hard-coded English in the source**, not localised (lines 164, 209-210) — the only
uncited-by-`Localizable.strings` state in the app. Text is orientation-specific with manual `\n`
line breaks baked into both variants.

### 3.3 Contacts denied on the welcome/inactive screen — `TGLoginInactiveUserController.m:256-330`

Dark variant, since the login background is dark:

- `ContactsDeniedPlaceholder.png`, 230×216 px @2x = **115×108 pt**, bottom edge at `titleY − 29`.
- `titleY = 64 + (isWidescreen ? 205 : 190)`.
- Title `WelcomeScreen.ContactsAccessDisabled` = "Sorry, unable to sync contacts.", bold 17, **white**,
  shadow `UIColorRGB(0x28313d)` at (0, +1).
- Body `WelcomeScreen.ContactsAccessHelp`, `systemFontOfSize:14`, `UIColorRGB(0xc0c5cc)`, shadow
  `0x323c4a` at (0, +1), wrap width **270**, y = `titleY + 34`, with the word "Settings"
  (`WelcomeScreen.ContactsAccessSettings`) bolded inline.

So the same idea has **two palettes**: `0x697487` on the light settings pattern, white + `0xc0c5cc`
on dark. Note the shadow offset flips sign between navigation-bar text (0, −1) and body text on
panels (0, +1).

---

## 4. Failures

There is no inline failure state in v1.1. Every failure is an alert, and the alert text is a
complete sentence. The vocabulary from `Telegraph/Telegraph/en.lproj/Localizable.strings`:

| Key | Text | Line |
| --- | --- | --- |
| `Login.UnknownError` | "An error occurred. Please try again later" | 182 |
| `Login.NetworkError` | "Please check your internet connection and try again." | 184 |
| `Login.CodeFloodError` | "Limit exceeded. Please try again later." | 186 |
| `Contacts.FailedToSendInvitesMessage` | "An error occurred." | 256 |
| `ConversationProfile.UnknownAddMemberError` | "An unexpected error has occurred. Our wizards have been notified and will fix the problem soon. Sorry." | 409 |
| `ConversationProfile.UsersTooMuchError` | "Sorry, this group is full. You cannot add any more members here." | 410 |
| `Profile.ImageUploadError` | "An error occurred. Please try again later." | 470 |
| `Web.Error` | "Couldn't load page" | 525 |
| `Settings.LogoutError` | "An error occurred. Please try again later." | 544 |

Patterns worth copying: the generic message is always "An error occurred." optionally followed by
"Please try again later"; a *known* cause always gets its own specific sentence naming the cause and
the remedy; nothing ever surfaces an error code or a TL error string to the user.

---

## 5. What the concept became

**Modern client.** The hand-built container became two generic mechanisms.
`submodules/TelegramUI/Components/EmptyStateIndicatorComponent/Sources/EmptyStateIndicatorComponent.swift:12-47`
declares an empty state as data — `animationName`, `title`, `text`, `actionTitle`, plus an
*additional* action — so every empty state is one struct literal and gets a Lottie animation and a
call-to-action button for free. Item lists have their own protocol,
`submodules/ItemListUI/Sources/ItemListControllerEmptyStateItem.swift:6-13`, with
`ItemListLoadingIndicatorEmptyStateItem` as a first-class *loading* variant of the same slot — i.e.
modern Telegram treats "loading" and "empty" as the same layout position with different content,
which the original never did.

The bigger change is loading: `submodules/ChatListUI/Sources/ChatListShimmerNode.swift` replaced
the spinner with a **skeleton of fake rows**. The problem that forced it is exactly ours — a spinner
tells the user nothing about what is coming, and on a cold start the chat list is blank for long
enough to look broken. Relevance for us: on a 4S the cold-start gap is *longer* than on modern
hardware, so the original's "blank table, spinner in the title bar" is the weakest inherited
behaviour we have. A period-correct compromise is to keep the title spinner but never show the
"You have no conversations yet" placeholder until the first chat-list page has actually resolved
(the shared-media grid already had this rule, §1.2).

**twelve.** Kept the original's language but factored it: each empty state became its own small
`UIView` subclass with a `layoutItems` method — `TGSharedMediaFilesEmptyView`,
`TGSharedMediaMusicEmptyView`, `TGSharedMediaLinksEmptyView`, `TGAuthSessionsEmptyView`,
`TGChannelMembersControllerEmptyView`, `TGChannelAdminLogEmptyView`,
`TGCloudStorageConversationEmptyView`, `TGSecretConversationEmptyListView` (all under
`twelve/Telegraph/`). The layout formula stabilised into a centre-anchored pair:
`TGSharedMediaFilesEmptyView.m:36-45` puts the icon's bottom at `height/2 + 3 + anchor − 28` and the
text top at `height/2 − 2 + anchor`, where `anchor` is `3 + (portrait ? 0 : 50)`. The typography
drifted from 2013's `0x808895`/bold 17 to `UIColorRGB(0x999999)` at `TGSystemFontOfSize(16)`, i.e.
lighter and regular-weight — a 2015-era flattening we should **not** adopt.
`TGModernConversationEmptyListPlaceholderView` became an empty abstract base with a
`presentation:` (theme) parameter, showing where the fork was heading: theming the states.

---

## 6. Where the original contradicted itself

Document these rather than smoothing them, because a port that "fixes" them stops matching
screenshots.

1. **Fade or no fade.** Chat list: no animation at all (`TGDialogListController.mm:885-929`).
   Media grid: 0.2 s (`TGPhotoGridController.mm:735-747`). Conversation: 0.3 s
   (`TGConversationController.mm:6236`). Blocked users: 0.3 s (`TGBlockedUsersController.mm:230`).
2. **Which spinner.** The house sprite spinner is used in navigation titles and the conversation
   load-more cell; UIKit's `UIActivityIndicatorView` is used in the media-grid footer (Gray) and in
   `TGProgressWindow` (WhiteLarge). There is no rule; it is who wrote the file.
3. **Grey text colour.** Four different greys for the same semantic role: `0x8b97a5` (chat list),
   `0x808895` (media grid), `0x8694a4` (blocked users), `0x697487` (permission overlays),
   `0xa8a8a8` (image search). Do not unify them.
4. **Table hidden vs faded.** Chat list hides the table outright; media grid and blocked users fade
   its background/alpha and, in the blocked-users case, disable scrolling.
5. **Localisation.** Everything is in `Localizable.strings` except the location-permission copy,
   which is inline English.
6. **Dead capability.** `shouldDisplayEmptyListPlaceholder` is declared, defaulted and consulted but
   never overridden in v1.1.

---

## 7. Our port, judged

### Right, leave alone

- **Chat-list empty container** (`src/TGChatListViewController.m:1517-1614`): 250 width, `NoMessages.png`,
  `0x8b97a5`, bold 15 title, system 14 body, 21 and 8 gaps, 232 wrap — all match
  `TGDialogListController.mm:889-918`.
- **Conversation empty plate** (`src/TGChatViewController.m:3735-3775`): 122×116, glyph at y = 23,
  bold 13 white, wrap 110, bottom-anchored at `116 − h − 8`, 0.3 s fade — matches
  `TGConversationController.mm:6141-6243`.
- **Shared-media empty view** (`src/TGMediaViewController.m:2540-2597`): `PhotosBlankPlaceholder.png`,
  bold 17, `0x808895`, 12 pt gap, and the `−18` vertical nudge correctly reproduces the original's
  `+36` container slack (`TGPhotoGridController.mm:718`).
- **Contacts-denied overlay** (`src/TGContactsViewController.m:2334-2450`): anchor 40×4, tags
  100/200/300/400, `−113`, `−10`, `+41`, `additionalOffset −20/−15`, wraps 265/210, `0x697487`,
  white-30 % shadow, `SettingsBackground` pattern — a faithful port of
  `TGContactsController.mm:668-760`, portrait branch only, which is fine for a portrait-locked 4S.

### Defects

1. **No sprite spinner exists in the port at all.** 82 uses of `UIActivityIndicatorView`
   (`grep -rn UIActivityIndicatorView src`), zero of a `TGActivityIndicatorView` equivalent, and the
   `grayProgress*`/`RProgress*`/`navbar_big_progress_*` frame sets from
   `Telegraph/Telegraph/Resources/ProgressIndicator*` are not in `images/`. Every spinner in the app
   is therefore the iOS 6 grey gear instead of Telegram's own 15×15 pt 24-frame wheel at 0.8 s per
   revolution (`TelegraphKit/TelegraphKit/TGActivityIndicatorView.m:6-56`). This is the single
   largest visual miss in this topic. Port the class (memoised static frame arrays; do not set
   `animationDuration`) and copy the three asset folders.
2. **Title-status spinner is the wrong widget and the wrong size.**
   `src/TGChatListViewController.m:1408-1409` uses
   `UIActivityIndicatorViewStyleWhite` (20×20 pt) where the original used
   `TGActivityIndicatorViewStyleSmallWhite` (15×15 pt sprite)
   (`TGDialogListController.mm:275`). The surrounding arithmetic — `(holderW − labelW + spinnerW + 5)/2`,
   `label.y + 3`, shadow `0x415a7e` at (0, −1), bold 15 — is correctly copied
   (`TGDialogListController.mm:345-346`), so swapping the view class fixes it; but note our container
   is 200 wide where the original is 40 (`TGDialogListController.mm:262`), which changes the centring
   result because the label is centred within the container.
3. **`startAnimating` is called unconditionally on every title refresh**
   (`src/TGChatListViewController.m:1422`). The original only touches the animation when
   `isAnimating != isLoading` (`TGDialogListController.mm:348-354`), so the wheel does not jump back
   to frame 0 each time the connection state is re-broadcast. Guard it.
4. **No `TGProgressWindow` equivalent.** Nothing in `src/` implements the 100×100 status-bar-level
   HUD with the 0.5 s check-mark confirmation (`TelegraphKit/TelegraphKit/TGProgressWindow.m:20-118`).
   The closest thing is `src/TGChatViewController.m:4107-4131`, an ad-hoc 110×40 black label showing
   `"0%"` with `cornerRadius 8`. That is not the original's HUD: wrong size (100×100), wrong art
   (stretched `ProgressWindowBackground.png`, not a CALayer corner radius), wrong content (a large
   white UIKit spinner, not a percentage), wrong level (an in-view subview, not a
   `UIWindowLevelStatusBar` window, so it does not block touches or cover the status bar), and no
   success state. Build `TGProgressWindow` and route the blocking operations (photo upload, logout,
   session termination) through it.
5. **"Loading…" as a table cell, everywhere.** ~35 sites, e.g.
   `src/TGSettingsViewController.m:3015, 3042, 3119, 3153, 3314, 3374, 3445`,
   `src/TGPrivacyViewController.m:332, 1505, 1616, 1729, 1917`,
   `src/TGStarsViewController.m:214, 1086, 1102`,
   `src/TGPremiumViewController.m:1172, 1208, 1230, 1270`,
   `src/TGProxyViewController.m:796`, `src/TGSessionsViewController.m:298`,
   `src/TGInviteLinksViewController.m:357, 536`, `src/TGStickersViewController.m:349, 2480`.
   The original never did this. Its two idioms were the spinner-only footer cell
   (`TGPhotoGridController.mm:273-296`: `UIActivityIndicatorViewStyleGray`, x-centred, y = 14, no
   text) for paged content, and the title-bar status for whole-screen waits. Replace the text with
   the footer-cell spinner; where the whole screen is waiting, show nothing and let the title carry
   it.
6. **Empty state shown before first load completes.** `src/TGChatListViewController.m:1547-1553`
   decides purely on `rows > 0`, so a cold start on a slow 4S flashes "You have no conversations
   yet" before the first page arrives. The original's rule for a paged list was
   `!_canLoadMore && count == 0` (`TGPhotoGridController.mm:702`). Add a `loaded` flag and gate on it.
   `src/TGForwardPicker.m:580-583` already does the right thing via `self.contactsLoaded`, so the
   pattern exists in the codebase — apply it to the chat list too. (Also note the picker's fallback
   string is `"Loading"` with no ellipsis, inconsistent with everything else in our port.)
7. **`"No results"` bare, where the original bolded the query.**
   `src/TGChatListViewController.m:1572` and `src/TGSearchViewController.m:2336` show plain
   "No results"; `src/TGGroupMembersViewController.m:2013` the same. The original composed
   `"No images found for " + **query**` with the query bold at the same point size
   (`TGImageSearchController.mm:551-577`) and drew it at `0xa8a8a8`, system 15. Our search status
   label is system 15 (`src/TGSearchViewController.m:627`) but coloured from
   `[[TGTheme shared] secondaryTextColour]` rather than the literal `0xa8a8a8` — the original had
   five distinct greys for these states (§6.3) and none of them were a shared token.
8. **`"Searching..."` has no spinner.** `src/TGSearchViewController.m:2336` swaps the same label to
   "Searching..." while `_pending > 0`. The original showed the animated loupe
   (`TGSearchLoupeProgressView`, 33×34, hour hand 1.8 s / minute hand 0.3 s per quarter turn,
   `TGSearchLoupeProgressView.m:8-80`) screen-centred, and never put the word on screen. If we do
   not port the loupe, the honest substitute is the sprite spinner, not text.
9. **A search failure survives the next query.** The original cleared the nothing-found text at the
   start of every search and on an emptied field (`TGImageSearchController.mm:699, 1594-1600`). Our
   `updateStatusLabel` (`src/TGSearchViewController.m:2324-2338`) only recomputes when sections
   change; verify that a new query resets it before results arrive rather than leaving the previous
   "No results" visible under the spinner.
10. **Statistics screen uses a "Loading..." label as its empty state.**
    `src/TGProfileViewController.m:3931-3943, 4103-4121` uses one `_emptyLabel` at system 15 for
    both "Loading..." and "No member statistics yet." The original always separated the two: a
    loading screen showed no placeholder text (the container was simply absent), and an empty
    screen got icon + bold title + regular body. At minimum this label should be bold for the empty
    case, and blank (with a footer spinner) for the loading case.
11. **Chat-list empty container is a subview of the table view.**
    `src/TGChatListViewController.m:1544` adds it to `self.tableView` and re-centres it against
    `tableView.bounds` each layout pass; the original inserted it into `self.view` *below* the table
    and hid the table entirely (`TGDialogListController.mm:890, 927`). Ours therefore scrolls with
    the table's rubber band and never disables the bounce. Either hide the table (chat-list rule) or
    disable `scrollEnabled` while empty (blocked-users rule, `TGBlockedUsersController.mm:226`).
12. **No location-permission designed state.** `grep` finds no equivalent of
    `TGPeopleNearbyController.m:140-232` in `src/`, and
    `src/TGQRViewController.m:52` handles camera denial with a plain failure string. If those screens
    stay, they should use the §3 recipe (40×4 anchor, 85×85 glyph, bold 17 `0x697487` title, 14.5 pt
    body with the operative word bolded) rather than a sentence.

### Open, genuinely ambiguous

- The original's chat-list placeholder centres on the **full view height**, ignoring the 64 pt bar,
  which reads low. Our port centres on `tableView.bounds`, which is inset and therefore reads
  *higher* than the original. Matching the original exactly means deliberately reproducing an
  off-centre look; I would match it, but it is a judgement call and the design-reference screenshots
  in `design-reference/` should settle it.
- Whether the "Waiting for network" title state should be reachable at all on our transport is a
  networking question this study cannot answer; the string exists (strings:63) and the bitmask that
  produces it is `state & 2 && state & 4` (`TGTelegraphDialogListCompanion.mm:691-697`).

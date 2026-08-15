# TGConversationController — the 2013 conversation screen

Original: `TelegraphKit/TelegraphKit/TGConversationController.h` (104 lines) and
`TGConversationController.mm` (8025 lines), Telegram for iOS v1.1 build 21024.
Paths below are relative to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`.
The class exists under exactly this name; nothing had to be substituted.

Related files read in full or in part, because the controller is meaningless without them:

- `TelegraphKit/TelegraphKit/TGConversationControllerCompanion.h/.m` — the asset and data
  protocol the controller talks to. **The controller owns no artwork of its own.**
- `Telegraph/Telegraph/TGTelegraphConversationCompanion.mm` — the real implementation of that
  protocol; every image name in this document comes from there.
- `TelegraphKit/TelegraphKit/TGConversationActionsPanel.m` — the drop-down that the navigation
  bar opens.
- `TelegraphKit/TelegraphKit/TGViewController.mm` — navigation title fonts and colours.

---

## 1. What it is

A `TGViewController` subclass that is *only* the conversation screen's view layer plus its
gesture and keyboard choreography. It holds no networking and no database access. Everything
that is not a pixel goes through `_conversationCompanion`
(`TGConversationController.h:36`), a `TGConversationControllerCompanion`, and everything that
comes back arrives through the ~30 imperative `- (void)conversationXChanged:` methods declared
in the header (`TGConversationController.h:58-102`). The controller never asks; it is told.

Instantiation is
`initWithConversationControllerCompanion:unreadCount:` (`.mm:567`). The unread count is
constructor state because the badge is drawn on the *back button* and must be right on the
first frame.

Two pieces of controller-wide state worth knowing:

- `+ (CGSize)preferredInlineThumbnailSize` (`.mm:555`) — 220×220 on a widescreen device
  (iPhone 5), 180×180 otherwise. This is what the companion sizes downloaded photo thumbnails to.
- `sharedViewRecycler` (`.mm:77`, assigned `.mm:942`) — one process-wide `TGViewRecycler`
  handed to every message cell (`.mm:3445`). Cells recycle their *subviews*, not just
  themselves. `+clearSharedCache` (`.mm:562`) empties it, and the companion calls it when the
  wallpaper changes (`TGTelegraphConversationCompanion.mm:4506`), because bubble artwork is
  tinted to the wallpaper.

---

## 2. The view stack, bottom to top

Built entirely in `loadView` (`.mm:728-1096`), in this order:

1. `_scrollToTopInterceptor` (`.mm:739`) — a 1-pt-tall invisible `UIScrollView` with
   `scrollsToTop = true`, contentSize 1×2, offset (0,1). This exists because the message table
   is *upside down*, so the system status-bar tap must be intercepted and translated into
   "scroll to the newest message" by hand (`scrollViewShouldScrollToTop:`, `.mm:4391`, which
   scrolls the table to `contentSize.height - 28`).
2. `_backgroundImageView` (`.mm:905`), a `TGConversationBackgroundView` (a bare `UIImageView`
   subclass), only if the companion returns a custom wallpaper. Frame at load:
   `y = superviewOffset - 20`, height `view.height - 43 + 40 - superviewOffset`, where
   `superviewOffset = 20 + (view.height > 400 ? 44 : 32)` — that is, status bar plus a
   navigation bar that is 44 pt in portrait and 32 pt in landscape. Content mode
   `ScaleAspectFill`, clipped.
   If there is no wallpaper the view background is the flat colour
   `[TGInterfaceAssets blueLinenBackground]` (`TGTelegraphConversationCompanion.mm:4491-4493`)
   and a stretched `ConversationBackgroundShadow.png` overlay is laid over the whole bounds
   instead (`.mm:914-921`, art at `TGTelegraphConversationCompanion.mm:4544`).
3. `_tableView` (`.mm:930`) — see §3.
4. `_inputContainer` (`.mm:950`) — see §4.
5. `blackView` (`.mm:1074`) — an opaque black 64-pt-tall view parked at `y = -64`, above the
   top of the screen, so that a rubber-banding navigation transition never reveals white.
6. `_actionsPanel`, `_emptyConversationContainer`, `_overlayDateContainer`, the menu container
   and the scroll-down button are all created lazily.

`_viewPanRecognizer` (`.mm:1070`) is added to the root view with `cancelsTouchesInView = false`
— it drives keyboard dragging (§8) without stealing taps from the cells.

### Background parallax

The wallpaper does not scroll with the table; it *drifts*. In `scrollViewDidScroll:`
(`.mm:4456-4494`, duplicated verbatim in `scrollViewDidEndDecelerating:` at `.mm:4572-4604`):

```
backgroundBaseY = superviewOffset + (keyboard/input raised ? -80 : -20)
overscroll top:    y = base + floor(max(offset, -250) * 0.08 * 2) / 2
overscroll bottom: y = base + floor(min(offset - maxOffset, 250) * 0.08 * 2) / 2
```

So the wallpaper moves at 8 % of finger speed, is clamped at 250 pt of overscroll, and is
rounded to a half-pixel grid (`floor(x*2)/2`) so it never lands on a third of a pixel. The
`-80` vs `-20` base means **the wallpaper shifts 60 pt when the keyboard opens** — this is the
same 60 in `TGConversationInputContainerView.setFrame:` (`.mm:274`), where the offset is
interpolated by `MIN(1, |inputBottom - viewHeight|/fullHeight) * -60`, with `fullHeight` 160 on
a wide screen and 210 otherwise. `_ignoreBackgroundImageViewScroll` (`.mm:3896`, cleared
`.mm:3946`/`:3954`) suppresses the scroll-driven path while the keyboard animation owns it,
so the two never fight.

---

## 3. The message list

`createTableView:` (`.mm:1210-1259`, the `#else` branch; the `TGUseCollectionView` branch at
`.mm:1152` was compiled out in this build).

- A `TGTableView` created `reversed:true` **and** rotated `CGAffineTransformMakeRotation(M_PI)`
  (`.mm:1213`). Row 0 is the newest message and sits at the bottom. Every cell inside is
  counter-rotated. This is why the loading spinner and its plate get their own
  `CGAffineTransformMakeRotation(M_PI)` (`.mm:3597`, `.mm:3605`).
- Initial frame is `(0, 0, 320, portraitScreenHeight)` (`.mm:930`) and is *never* laid out by
  autoresizing; the frame's `origin.y` is negative in steady state and is recomputed from the
  input container every time anything moves:
  `tableFrame.origin.y = inputContainer.origin.y - tableFrame.size.height`
  (`.mm:2878`, `.mm:4074`, `.mm:4174`, `.mm:4227`). The table is taller than the screen and
  hangs off the top; only its bottom edge is meaningful.
- `contentInset = (2, 0, 0, 0)` (`.mm:1223`) — 2 pt of air past the newest message (top in
  rotated space = bottom on screen). `scrollInsets = (0,0,0,9)` (`.mm:1222`) pushes the
  scroll indicator 9 pt in from the rotated edge so it appears on the right, not the left.
- `bottom` inset and indicator inset are always `MAX(0, -tableFrame.origin.y + controllerInset.top)`
  (`.mm:2883`, `.mm:4080`) — i.e. exactly the amount of the table hanging above the navigation
  bar, so content stops under the bar rather than behind it.
- `separatorStyle = None`, `backgroundColor = clear`, `opaque = false`,
  `delaysContentTouches = false` (`.mm:1215-1217`) — the last one is what makes a bubble
  highlight instantly instead of after the 150 ms scroll-detection delay.
- `scrollsToTop = false` (`.mm:1220`); see the interceptor above.

### Sections and rows

Two sections (`.mm:3371`), but section 1 always has 0 rows (`.mm:3384`). Section 0 has
`_listModel.count + 1` rows (`.mm:3380`) — the extra row is the *oldest*-end loading cell, 30 pt
tall (`.mm:3357`), containing a `systemMessageBackground` plate 21 pt wide at y 3 and a small
white `TGActivityIndicatorView` (`.mm:3593-3607`). Both are hidden and the spinner stopped when
`_canLoadMoreHistory` is false (`.mm:3611-3617`) — so an exhausted history shows an empty 30 pt
gap, not a dead spinner.

### Row heights (`heightForConversationItem:metrics:`, `.mm:3806`)

| item type | height |
|---|---|
| message | `sizeForConversationMessage(item, metrics, assetsSource).height` |
| date separator | 27 |
| unread marker | 34 |

`metrics` is the bitfield `_messageMetrics` (`updateMetrics:`, `.mm:2132`): portrait/landscape
plus `TGConversationMessageMetricsShowAvatars`, which is set only for a multichat that is not
encrypted. Avatars in secret group chats were deliberately off.

### Cell reuse (`cellForRowAtIndexPath:`, `.mm:3410`)

- Reuse identifiers are `"MS"` and `"MM"` (`.mm:3426-3429`) — *single* vs *multichat*. The
  avatar gutter changes the whole layout, so the two never share a pool.
- The whole method runs inside `[UIView setAnimationsEnabled:false]` (`.mm:3412`, restored
  `.mm:3619`), because a recycled cell reconfiguring itself inside a table animation block
  would otherwise animate its subviews from their previous message's positions.
- `messageItemView.messageItemHash == (int)messageItem` (`.mm:3478`) is a pointer-identity
  fast path: if the same item object comes back to the same view, only `updateState:false` runs
  instead of the full `resetView:_messageMetrics`.
- `_preparedCellQueue` (`.mm:3433`) is a pre-warmed pool used during the push animation and
  released in `viewDidAppear:` (`.mm:1482`).
- Media state is applied per cell on every configure: upload progress from the shared
  `std::map<int,float>` (`.mm:3494`), download progress from `_mediaDownloadProgress`
  (`.mm:3508`), needs-download flag from `_mediaDownloadedStatuses` (`.mm:3524`), and
  `_hiddenMediaMid` blanks the image and every subview tagged 1/2/3 so a photo can appear to
  fly into the full-screen viewer (`.mm:3530-3547`).

### Paging

`willDisplayCell:` (`.mm:4549`): rows within 5 of index 0 request `loadMoreHistoryDownwards`;
rows within 10 of the end request `loadMoreHistory`. Unloading is the other direction — every
scroll that comes to rest below `contentOffset.y < 100` calls `unloadOldItemsIfNeeded`
(`.mm:4436`, `:4569`, `:4622`, `:4631`), i.e. the moment you are near the newest message the
far end of the history is allowed to be thrown away.

---

## 4. The input container

`_inputContainer` is a `TGConversationInputContainerView` (`.mm:254`), 43 pt tall
(`_baseInputContainerHeight = 43`, `.mm:898`), pinned to the bottom with
`FlexibleWidth | FlexibleTopMargin`, `clipsToBounds = false`, `opaque = false` (`.mm:950-955`).
It is not clipped because the drop shadow and the scroll-down button live *above* its top edge
at negative y.

Its `hitTest:` (`.mm:278`) forwards to `_hitView` — used to make the scroll-down button, which
sits at negative y outside the bounds, still tappable.

Contents, in add order:

| view | frame | art / colour | citation |
|---|---|---|---|
| shadow | `(0, -h, viewWidth, h)`, `h` = image height, above the top edge | `ChatInputContainer_Shadow.png`, or `..._Mono.png` when the wallpaper has a monochrome tint | `.mm:962-969`; art `TGTelegraphConversationCompanion.mm:4550-4571` |
| white plate | `(40, 4 - rp, width - 106, 36)` | flat `whiteColor` | `.mm:975-977` |
| fake text label | `(49, 14 - rp, width - 126, 200)`, system 16, word wrap, unlimited lines | — | `.mm:980-983` |
| placeholder | `(49, 5 - rp, width - 113, 34)`, system 16, `0x9da7b3` | `Conversation.InputTextPlaceholder` | `.mm:986-992` |
| panel frame | full container, stretchable `leftCap 55, topCap 21` | `ConversationInputPanel.png` | `.mm:998-1000`; art `…Companion.mm:4580` |
| attach button | `(6, 7 + rp, 29, 30)` | `AttachBtn.png` / `AttachBtn_Pressed.png` | `.mm:1003-1006`; art `…Companion.mm:4602/4613` |
| send button | `(width - 67, 7 + rp, 62, 29)` | `SendButton.png` stretched at the horizontal midpoint | `.mm:1014-1017`; art `…Companion.mm:4646` |

`rp` is the retina half-pixel, `TGIsRetina() ? 0.5f : 0.0f` (`.mm:817`). It appears in almost
every frame here: the artwork was cut for 2× and the odd-pixel offsets are what keep the 1-px
hairlines in the panel PNG from being resampled.

Send button typography (`.mm:1019-1029`): title `Conversation.Send`, bold system **14.5**,
white, shadow colour `0x0cb8e3` at 30 % with offset `(0,-1)`, title edge insets
`(1.5, 0, 2, 0)`, disabled title colour **`0xceffb0` on a widescreen device and `0xbbffb2`
otherwise** (`.mm:1022`) — the two device generations shipped slightly different green
artwork, and the disabled text was matched to each. `adjustsImageWhenDisabled/Highlighted` are
both off; the button starts `enabled = false`.

### The fake field, and why it exists

At `loadView` time there is no text view at all — only `_fakeInputFieldLabel`, a plain
`UILabel`. The real editor, an `HPGrowingTextView` (`.mm:93`, `#define TGInputFieldClass`), is
created in `createInputField` (`.mm:1428`) either in `viewWillAppear:` when the screen was
asked to open with the keyboard up (`.mm:1332-1342`) or otherwise not until `viewDidAppear:`
(`.mm:1475-1478`). Constructing a `UITextView` cost a visible hitch on a 2013 device, so the
push animation runs against a label and the real control is swapped in afterwards; the label is
removed and nilled at that moment (`.mm:1458`).

The editor frame is derived from the white plate: `x+1`, `width-6`, `height-2` (`.mm:1430-1433`).
`maxNumberOfLines` is **7 on a widescreen portrait, 5 on a 3.5-inch portrait, 3 in landscape**
(`.mm:1443`). Font system 16 (`.mm:1442`), scroll indicator insets `(10,0,10,0)` (`.mm:1438`),
and the vertical indicator is switched off during construction and re-enabled on the next
runloop turn (`.mm:1445`, `.mm:1464`) so it does not flash.

### Growing

`growingTextView:willChangeHeight:animated:` (`.mm:4209`) computes
`newHeight = 43 - 36 + height` — the 36 being the one-line plate height, so the container is
"chrome plus text". It then re-pins `origin.y = superviewHeight - keyboardHeight - newHeight`
and drags the table with it, animated 0.3 s. It returns immediately when the editing container
is visible (`.mm:4211`) so a selection toolbar cannot be pushed around by stale text metrics.

The same maths is applied to the *label* when a draft is restored before the editor exists:
`setMessageText:` (`.mm:5337`) measures the label and calls
`growingTextView:nil willChangeHeight:` with
`MAX(36, MIN(labelHeight + 16, portrait ? (widescreen ? 156 : 116) : 76))` (`.mm:5362`) — those
three caps are the 7/5/3-line limits expressed in points. A draft ending in `\n` gets a trailing
space appended (`.mm:5351`) because `sizeToFit` ignores a final empty line.

### Send

`sendButtonPressed:` (`.mm:2230`). It first resigns and immediately re-takes first responder
with `_isRotating` set true around it (`.mm:2236-2241`) — this commits any in-flight
multi-stage input (Japanese, Chinese) without letting the keyboard-height handlers react. The
text is then passed through `clearTextFromWhitespace:` (`.mm:2219`): runs of spaces collapse to
one, runs of 2+ newlines collapse to exactly two, and the result is trimmed. Empty after that
means nothing is sent.

`growingTextViewDidChange:` (`.mm:4272`) enables the send button only if at least one character
is neither `' '` nor `'\n'` — a whitespace-only draft leaves the button disabled — and fires
`messageTypingActivity` on every change, suppressed while a draft is being installed or during
rotation (`.mm:4290`).

---

## 5. The navigation bar

### Title

`_titleContainer` is a bare `UIView` set as `navigationItem.titleView` (`.mm:834`); inside it
`_titleLabelsContainer` holds three labels. All layout is manual, in
`updateTitle:animated:` (`.mm:1855-2130`), which is the single most metric-dense method in the
class.

| element | font | colour | shadow |
|---|---|---|---|
| title | bold system **16** portrait / **15** landscape (`TGViewController.mm:103,110`) | `0xffffff` (`TGViewController.mm:139`) | `0x3d5c81`, offset `(0,-1)` (`TGViewController.mm:157`, `:171`) |
| status (normal) | bold system **12** (`.mm:780`) | `0xe0eefd` when the text equals `Presence.online`, else `0xc9dcf2` (`.mm:1645-1648`) | `0x3d5c81`, `(0,-1)` (`.mm:782`) |
| status (typing) | bold system 12, same colours, starts `alpha = 0` (`.mm:792-800`) | | |
| message-lifetime label | bold system **10**, `0xc9dcf2`, shadow `0x587da3` `(0,-1)` (`.mm:1916-1920`) | | |
| sync status | bold system **15**, white, shadow `0x415a7e` `(0,-1)` (`.mm:5526-5529`) | | |

Width budget (`.mm:1885-1888`):

```
leftButtonWidth  = leftBarButton.width + 13
rightButtonWidth = rightBarButton.width + 13
titleMaxWidth    = screenWidth - leftButtonWidth - rightButtonWidth - 8
```

then `-10` if the chat is encrypted (room for the lock), `-40` if a message lifetime is set,
and `-30` more if the Cancel button is showing (`.mm:1893`, `:1906`, `:1967`).

Portrait layout (`.mm:1953-2039`): each label is sized to fit, then **every width is rounded up
to an even number** (`.mm:1977`, `:1983`, `:1990`, `:1996`). This is not superstition — the
container is centred with a division by two, and an odd width would put the labels on a half
pixel and blur the text shadow. The container is centred on the *screen*, not on the free space,
and clamped so it never starts left of the back button (`.mm:1999-2001`). Title y is
`-2 + titleOffsetY` where `titleOffsetY` is `2 - rp` on iOS 7+ and 0 before (`.mm:1962`);
subtitle y is `containerHeight - subtitleHeight - 3 + rp + titleOffsetY` (`.mm:2011`). If the
title has been truncated to the full available width and there is no lifetime badge, it is
nudged 12 pt right (`.mm:2005`) to re-centre it against the avatar.

Landscape (`.mm:2041-2123`) is a different design, not a scaled one: title and status sit
**side by side** with 6 pt between them, the status getting 2/5 of the width and the title 3/5
(`.mm:2044-2049`).

### Typing indicator

`_titleStatusLabelTyping` carries a small child container at `(-24, 5, 21, 10)` holding
`TypingHeader.png` stretched with `leftCapWidth 6` and three `TypingHeader_Dot.png` dots at
x = 4, 8.5, 13 (4 + 4 + rp each step) and y = 3 (`.mm:807-825`). The animation:
each dot scales to 1.3 over 0.1 s and back over 0.1 s (`.mm:1734-1746`); dots fire
`TGDotInterval = 0.12` s apart (`.mm:90`), and the whole three-dot run restarts every
`TGDotPeriod = 0.45` s (`.mm:91`, timers at `.mm:1714-1718`). The short timer kills itself after
the third dot (`.mm:1750`) and the period timer restarts it, so there is a real pause between
cycles rather than a continuous ripple.

Switching between the two status labels is a 0.3 s cross-fade of alphas (`.mm:1683-1687`), and
`setStatusText:` is a no-op fast path when neither string changed (`.mm:1635`).

### Right side: avatar

A `TGConversationButtonContainer` 37×38 with a tap recogniser (`.mm:876-879`), containing a
`TGRemoteImageView` with `fadeTransition = true`. Avatar size comes from the companion:
**35×35 portrait, 25×25 landscape** (`TGTelegraphConversationCompanion.mm:4664-4669`). Its
frame is `(3, 1.5)` portrait / `(13, 6.5)` landscape (`.mm:2128`), with a separate overlay
image (the rounded-corner gloss) inset `(-2,-1.5, +4,+4)` portrait and `(-1,-0.5, +2,+2)`
landscape (`.mm:2129`, art `TGInterfaceAssets conversationTitleAvatarOverlay`).
The container is hidden entirely for a broadcast (`.mm:1065`).

Placeholders: a per-id coloured `smallAvatarPlaceholder` / `smallGroupAvatarPlaceholder`
(`…Companion.mm:4672-4681`) when there is no photo URL, and a neutral
`TitleAvatarPlaceholderGeneric.png` (`…Companion.mm:4688`) as the fade-from image while a photo
loads. Fade duration is 0.14 s when the participant object first arrives and 0.3 s for a later
photo change (`.mm:5397`, `.mm:5437`) — a first paint should be quick, a change should be
noticed.

### Left side: back button with unread badge

`TGToolbarButton` of type Back, text `Common.Back` (`.mm:836-839`), wrapped in a
`TGConversationButtonContainer` with `backSemantics = true`, which reports a bar-button offset
of 0 (4 for non-back containers) and extends hit testing outside its own bounds
(`.mm:217-250`).

The badge is a subview of the back button at `(backWidth - 13, -7, 25, 6)` (`.mm:853`), moved to
y `-5` in landscape (`.mm:1877-1880`). Art: `ConversationUnreadBadge.png` stretched with
`leftCapWidth 12` (`…Companion.mm:4703`). Label bold system 12 white at `(9, 7+rp, 28+rp, 10)`
(`.mm:862-865`).
Formatting (`.mm:1827-1833`): `<1000` plain, `<1000000` as `%dK`, else `%dM`.
Badge width is `MAX(25, textWidth + 18)` and it grows **leftwards** — its right edge is pinned
(`.mm:1840-1846`). Zero or negative unread hides the container (`.mm:1823`).

### Sync status

When `_synchronizationStatus != None`, the whole title/subtitle stack is hidden and replaced by
a spinner-plus-label group (`.mm:1859-1870`, built lazily at `.mm:5516`): the label is one of
`State.WaitingForNetwork`, `State.Connecting`, `State.Updating` (`.mm:5564-5569`), and the
`TGActivityIndicatorView` is placed 5 pt to its left (`.mm:5574`). Container y is 5 portrait,
3 landscape (`.mm:1868`).

### Tapping the bar

`navigationBarHasAction` (`.mm:2158`) returns false for broadcasts, when `_disableTitleArrow`
is set, and while the table is in editing mode — that is what makes the disclosure arrow in the
bar appear or not. `navigationBarAction` (`.mm:2168`) toggles the actions panel and dismisses
any open message menu or date tooltip. A swipe down on the bar opens it but never closes it
(`.mm:2189-2195`).

---

## 6. The actions panel

`TGConversationActionsPanel`, a full-screen overlay whose visible content is a 320×59 strip of
three buttons at `y = -26` inside a container anchored at the top
(`TGConversationActionsPanel.m:118-123`) — negative y so it appears to slide out from under the
navigation bar.

Layout (`…Panel.m:layoutSubviews`, `:378-390`): centre button 94 pt wide, side buttons 98 pt,
4 pt gaps filled by separator images, all 59 pt tall. Buttons are bold system 14, white,
disabled white at 50 %, title shadow `0x000000` at 80 % normal and `0x186bcb` at 60 % when
highlighted/selected, offset `(0,-1)` (`…Panel.m:218-226`). Title inset top `8 + rp`, plus 7 pt
left on the first button and 12 pt right on the last (`…Panel.m:228`). The right button carries
an `ActionMenuArrow.png` at `(width - 33, 27 + rp)` (`…Panel.m:231-235`).

Artwork: `ActionMenuButtonLeft/Middle/Right(.._Highlighted).png` — left stretched at
`width - 6`, right at `6`, middle not stretched at all (`…Panel.m:167-183`) — and three
separator states `ActionMenuDivider(.._LeftHighlighted/_RightHighlighted).png` chosen by which
neighbour is pressed (`…Panel.m:updateSeparators`, `:408-424`). This is the detail that makes
the strip read as one carved object: the divider leans toward the pressed side.

Show animation (`…Panel.m:240-283`) is a three-stage overshoot from scale 0.1:
0.142 s to 1.05, 0.08 s to 0.98, 0.06 s to 1.0, with `shouldRasterize` on for the duration.
Hide is a flat 0.2 s alpha fade, then the transform is reset to 0.1 (`…Panel.m:299-322`).
Tapping anywhere outside is caught in `hitTest:` (`…Panel.m:398`) and dismisses.

Contents by chat type (`.mm:1781`, `…Panel.m:126-146`): a user chat gets **Call / Edit /
Info**, where Info becomes **Block** or **Unblock** when the peer is not a contact; a multichat
gets **Mute or Unmute / Edit / Info**. Edit is disabled while the conversation is empty
(`.mm:1802`), Call is disabled when the user has no phone number (`.mm:1791`).

---

## 7. States

### Empty conversation (`updateEmptyState:`, `.mm:6136`)

A plate drawn from `systemMessageBackground` — the same art as an in-line service message —
sized **122×116 for a normal chat and 229×185 for a secret chat** (`.mm:6142`).

Normal chat: `ConversationIconPlain.png` centred at y 23 (`.mm:6207-6209`), then a label in
bold system 13 in `messageActionTextColor`, wrapped at **110 pt** and pinned 8 pt from the
bottom of the plate (`.mm:6211-6224`). Text is `Conversation.EmptyPlaceholder`, or
`Conversation.SupportPlaceholder` when `conversationId == 333000` (`.mm:6219`) — the Telegram
support account has its own empty state.

Secret chat: a two-line bold-13 title at `(20, 12, w-40, 42)` naming the peer, with the first
name **hard-truncated to 16 characters plus an ellipsis** (`.mm:6168-6169`); a bold-13
`Conversation.EncryptedDescriptionTitle` at `(16, 66)`; then four rows of
`SmallLockIcon.png` + system-13 text starting at `(16, 92)` and stepping 22 pt
(`.mm:6186-6203`).

Positioning (`updateEmptyConversationContainer`, `.mm:6268`): horizontally centred; vertically
`viewInsetOffset + (viewHeight - plateHeight)/2 + (viewHeight > 140 ? 43 : 0)`, where
`viewInsetOffset` is `controllerInset.top - 64` on a tall view and `-14` on a short one. The
`+43` is the input container height — the plate is centred in the *messages* area, not the
screen.

It fades in and out over 0.3 s, but only if more than 0.15 s has passed since the screen began
appearing (`.mm:6233`, `.mm:6247`); during the push it just appears, because a fade racing the
navigation transition looks like a glitch.

### Blocked / secret-chat-pending: the editing container

`_editingContainer` (`.mm:4936`) covers the input container and holds two families of controls:

- **Selection mode**: a red Delete and a blue Forward button, each `(screenWidth/2) - 13` wide,
  9 pt from their side, vertically centred in the 43 pt bar plus `1 + rp`
  (`.mm:5090`, `:5106`). Labels bold system 13 white; delete shadow `0x9e0a01` at 30 %, forward
  shadow `0x3c6696` at 50 %, both offset `(0,-1)` (`.mm:4961-4964`, `:4987-4990`). Icon and
  label are laid out as one centred group with 8 pt between them (`.mm:5086`, `:5097-5099`).
  Both are disabled with **icon and label at alpha 0.7** while nothing is selected
  (`.mm:5120-5126`), and their labels gain a `(n)` count once something is (`.mm:5076-5080`) —
  except Forward in a secret chat, which cannot forward and so never shows a count
  (`.mm:5077-5078`).
- **Request/block mode**: pill buttons from `RequestGreenButton.png` / `RequestRedButton.png`,
  stretched at both midpoints (`.mm:5044-5047`), white bold system 14 with shadows `0x479415`
  green / `0xcf2f29` red, darkening to `0x458413` / `0xb91510` when pressed (`.mm:5053-5057`).
  Fixed sizes at y 5, height 35: two 150 pt buttons 6 pt apart, or a single 200 pt (send
  request) or 160 pt (unblock/delete) button centred (`.mm:5128-5131`). Beneath/behind them a
  system-14 `0x576d85` state label spanning the bar (`.mm:5030-5034`, `:5133`).

`setConversationLink:animated:` (`.mm:5665`) is the state machine that chooses between them.
For a secret chat in status 0/1/2/3 or for a blocked peer it shows the request container and
hides Delete/Forward; otherwise it hides the whole editing container again with a 0.25 s
animation and restores the two buttons 0.25 s later (`.mm:5765-5771`). Encryption status 1
renders `Conversation.EncryptionWaiting` with the peer's first name in **bold inside an
otherwise regular attributed string** (`.mm:5635-5651`), computing the bold range from the
position of `%@` in the format string — with a plain-text fallback for OS versions without
`setAttributedText:`.

Entering selection mode (`setEditingMode:animated:`, `.mm:4667`) swaps the bar: Clear All fades
in over 0.3 s while Back fades out on a 0.2 s animation delayed 0.1 s (`.mm:4706-4710`), the
avatar fades out and a Cancel button fades in over the same 0.3 s. The title is cross-dissolved
rather than moved, but **only in portrait and only when the title container is at least 160 pt
wide** (`.mm:4717`) — otherwise the re-layout jump is small enough that a dissolve is worse
than nothing. A 2 pt `messageEditingSeparator` strip is added to the table at y 1
(`.mm:4731-4741`).

The Cancel button is `Common.Cancel`, min width 51, 10 pt padding each side (`.mm:1102-1106`);
Clear All is `Conversation.ClearAll`, min width 54, 8 pt padding (`.mm:1128-1131`).

### Scroll-down button (`displayNewMessagesTooltip`, `.mm:4521`)

A 36×36 button at `(containerWidth - 43, -43)` — i.e. 7 pt in from the right and 7 pt above the
input container's top edge, outside its bounds (`.mm:4528`, `:4541`). Art
`ConversationScrollDown.png` / `..._Highlighted.png`. It fades in over 0.3 s, is registered as
the container's `hitView` so it stays tappable outside the bounds (`.mm:4535`), and fades out
over 0.2 s and removes itself the moment the table reaches the bottom with no more history
below (`.mm:4502-4517`).

### Overlay date bubble — present but dead

`overlayDateView` (`.mm:4301`) builds a `ConversationDateOverlay.png` bubble stretched at its
midpoint, alpha 0.85, with a bold-12 white label inset 12 pt and shadowed black at 30 %.
`updateOverlayDateView:` begins with an unconditional `return;` (`.mm:4332`). **In v1.1 the
floating date bubble was disabled**, and the associated fades in `scrollViewDidEndDragging:`
and `scrollViewDidEndDecelerating:` are commented out (`.mm:4438-4443`, `:4606-4609`). If we
implement one, we are implementing a Telegram feature, not restoring a 2013 one.

---

## 8. Keyboard behaviour

This is the part that made the screen feel expensive in 2013 and it is almost all bespoke.

- `keyboardWillShow:` (`.mm:3892`) converts the keyboard frame into view coordinates, stores
  the height, disables autorotation and user interaction for `duration + 0.05`, then calls
  `changeInputAreaHeight:duration:` — the single funnel that moves the input container and the
  table together (`.mm:4066`). Animation curve is `EaseInOut`, and the table frame is set again
  in the completion block to defeat any interrupted animation (`.mm:4110-4114`).
- The keyboard height is **hard-coded per orientation** when rotating with the keyboard up:
  216→162 and 216+36→162+36 (`.mm:2911-2922`, mirrored in
  `updateKnownKeyboardHeightForOrientation:`, `.mm:3874`). The `+36` is the autocorrect bar.
- **Drag to dismiss.** `tablePanRecognized:` (`.mm:5192`) tracks the finger against the
  table's bottom edge and calls `dragKeyboard:` (`.mm:5236`), which not only shrinks the input
  area but *moves the actual keyboard window* — located by `findKeyboardWindow()` (`.mm:132`),
  which walks `UIApplication.windows` for a view whose description starts with
  `UIPeripheralHostView` containing a `UIKeyboard`. Those two class names are stored
  Caesar-shifted by one (`encodeText`, `.mm:118`, strings at `.mm:139-140`) to keep them out of
  the binary as literals, with a three-level cache of the last window, subview index and
  pointer to keep the lookup off the hot path.
- On release, `maybeHideKeyboard:scrollToBottom:` (`.mm:5275`) decides by *velocity sign*, not
  distance: an upward flick snaps the keyboard back over 0.25 s, a downward one dismisses it.
  Either way, if the drag started within 16 pt of the bottom and the flick was slower than
  260 pt/s, the table animates to the newest message (`.mm:5297-5303`).
- Tapping the background (`touchedTableBackground`, `.mm:3839`) closes the keyboard, clears any
  message selection, and re-enables `handleEditActions` on the text view. It bails out if a
  menu is showing or a menu was hidden less than 0.32 s ago (`.mm:3844`) — the dismissal tap
  must not also dismiss the keyboard.
- Swiping the table left pops the conversation; swiping right opens the peer's profile
  (`tableViewSwiped:`, `.mm:4641`), both rate-limited to one per 0.4 s and both blocked while
  editing or while a `UIMenuController` is up. Thresholds: 36 pt horizontal, 10 pt vertical
  reject, 10 pt direction lock, 200 pt/s velocity (`.mm:1237-1240`).
- Landscape with the keyboard up hides the navigation bar entirely and drops the status-bar
  backdrop alpha to 0 (`.mm:1346-1347`).

---

## 9. Behaviour with awkward content

| situation | what the original does |
|---|---|
| empty or `" "` title/subtitle at load | falls back to `companion.safeConversationTitle` / `safeConversationSubtitle` (`.mm:747-750`); labels are set to a literal `@" "` rather than empty so the layout keeps its height (`.mm:763`, `:777`) |
| title longer than the budget | truncated tail at `titleMaxWidth`; if it fills the budget and there is no lifetime badge it shifts 12 pt right (`.mm:2005`) |
| very long typing subtitle | truncated tail at `subtitleMaxWidth - 26`, the 26 reserving the dot bubble (`.mm:1986-1988`) |
| unread count ≥ 1000 | `12K`, `3M` (`.mm:1828-1833`) |
| secret-chat peer with a long first name | cut to 16 chars + `...` in the empty-state title (`.mm:6168`) |
| whitespace-only draft | send button stays disabled (`.mm:4278-4288`); even if forced, `clearTextFromWhitespace:` yields empty and nothing is sent (`.mm:2252`) |
| history exhausted | the extra 30 pt row stays but its plate and spinner are hidden (`.mm:3611`) |
| no wallpaper set | flat blue-linen colour plus a stretched shadow overlay, and the parallax code simply moves a nil view (`.mm:912-921`) |
| broadcast chat | avatar hidden, navigation-bar action suppressed (`.mm:1065`, `.mm:2160`) |
| screen appears and disappears fast | `_appearingAnimation` / `_appearingAnimationStart` gate almost every animation: anything within 0.25 s of appearing is applied instantly (`.mm:1502`, `:5602`, `:5662`) and empty-state fades within 0.15 s are skipped (`.mm:6233`) |

---

## 10. Our port: `src/TGChatViewController.m`

Ours is one 10457-line controller with the conversation inlined; there is no companion split.
That is a defensible architectural choice for our size and I am not counting it as a defect.
What follows are the differences a user could see.

The input bar is genuinely close — `kInputHeight = 43` (`TGChatViewController.m:45`), the white
plate at `(40, 4 - rp, w - 106, 36)` (`:3005`), the attach button at `(6, 7 + rp, 29, 30)`
(`:3025`), the send button 62×29 at `w - 67` with bold 14.5, shadow offset `(0,-1)`, title
insets `(1.5,0,2,0)` and the `0xceffb0` disabled colour (`:3064-3095`), the panel art stretched
`55/21` (`:3013`) and the shadow above the top edge (`:2988`). Those match the original line for
line. Everything below is where we diverge.

### Defects, most visible first

1. **The message table is not reversed.** Ours is an ordinary top-down `UITableView` with row 0
   as the oldest message (`:2753`, `scrollToBottomAnimated:` at `:3577` scrolls to the last
   row). The original rotates the table by π and treats row 0 as the newest
   (`TGConversationController.mm:1213`). Visible consequences: our newest message is not pinned
   to the bottom when the content is shorter than the screen; loading older history above
   changes the content offset and makes the view jump, which the reversed table gets for free;
   and our `contentInset` has none of the original's `(2,0,0,0)` breathing room or the 9 pt
   scroll-indicator inset (`TGConversationController.mm:1222-1223`). This is the largest single
   behavioural gap and it is worth fixing before anything cosmetic.

2. **Single-line `UITextField` instead of a growing text view.** `:3041` creates a
   `UITextField`; the original uses `HPGrowingTextView` capped at 7 lines on a widescreen
   portrait, 5 on 3.5-inch, 3 in landscape (`TGConversationController.mm:1443`), with the input
   container growing as `43 - 36 + textHeight` (`:4215`) and the table sliding up with it. A
   user typing a paragraph in ours sees one scrolling line. Fix: a growing text view plus
   `growingTextView:willChangeHeight:` wired to move both the container and the table frame.

3. **Title font and shadow are wrong.** Ours: bold system **17** with a black 40 % shadow at
   `(0,-1)` (`:2884-2889`). Original: bold system **16** portrait / 15 landscape
   (`TGViewController.mm:103,110`) with shadow `0x3d5c81` (`TGViewController.mm:157`). The
   blue-grey shadow is what makes the 2013 title sit on the gradient bar; black reads as iOS
   default chrome.

4. **Subtitle font, weight and colour are wrong.** Ours: system 12, white at 75 %
   (`:2896-2899`). Original: **bold** system 12, `0xe0eefd` when the status is exactly
   `Presence.online` and `0xc9dcf2` otherwise (`TGConversationController.mm:780`,
   `:1645-1648`), shadow `0x3d5c81`. We lose the online/offline colour distinction entirely.

5. **No typing dots.** Ours overwrites the subtitle string with the action text (`:2916`). The
   original cross-fades to a second label over 0.3 s and animates three dots in a small
   `TypingHeader.png` bubble at `(-24, 5, 21, 10)`, 0.12 s apart, cycling every 0.45 s
   (`TGConversationController.mm:807-825`, `:1714-1746`). This is one of the most recognisable
   details of the period design and it is missing.

6. **No unread badge on the back button.** The original draws a stretched
   `ConversationUnreadBadge.png` with a bold-12 white count on the back button, right-anchored
   and growing left, `K`/`M`-abbreviated (`TGConversationController.mm:853-866`, `:1821-1848`).
   Grep finds nothing equivalent in ours. It is also how the constructor's `unreadCount`
   argument earns its place.

7. **No actions panel.** Tapping our title pushes the profile directly (`:2905`, `openProfile`
   at `:3822`). The original toggles the three-button Call/Edit/Info drop-down with its
   overshoot animation and lit-separator artwork (`TGConversationController.mm:2168`,
   `TGConversationActionsPanel.m`). Selection mode and Block/Unblock have no other entry point
   in the 2013 design.

8. **Scroll-down button is a drawn circle, not the artwork.** Ours: 34×34, white at 90 %, 1 pt
   border, a `▼` glyph in system 13 (`:3695-3707`), positioned at
   `(width - 44, inputBarTop - 44)`. Original: 36×36 `ConversationScrollDown.png` at
   `(containerWidth - 43, -43)` *inside* the input container with `hitView` forwarding, fading
   in over 0.3 s and out over 0.2 s (`TGConversationController.mm:4528-4546`, `:4504-4516`).
   Ours also just toggles `hidden`, with no fade.

9. **Empty plate is a rounded rectangle, not the service-message artwork.** Ours uses
   `TGSystemPlateColour()` with `cornerRadius = 10` (`:3594-3596`); the original uses the same
   stretchable `systemMessageBackground` art as an in-line service message
   (`TGConversationController.mm:6147`). Size 122×116 and the glyph at y 23 are right
   (`:3593`, `:3605`), but our vertical centring uses `(viewHeight - kInputHeight - 116)/2`
   where the original adds a further `+43` and offsets by `controllerInset.top - 64`
   (`TGConversationController.mm:6273`), so ours sits higher than it should. Our label also has
   no explicit 110 pt wrap width (`TGConversationController.mm:6223`).

10. **No wallpaper parallax.** Our `wallpaperView` is pinned to `self.view.bounds` with
    autoresizing (`:2760-2764`). The original drifts it at 8 % of scroll velocity, clamped at
    250 pt, snapped to half pixels, and shifts it 60 pt when the keyboard opens
    (`TGConversationController.mm:4462-4494`, `:274`).

11. **No drag-to-dismiss keyboard.** We observe `UIKeyboardWillShow/Hide` only (`:2799`,
    `:10400`). The original moves the keyboard window itself under the finger and decides on
    release by velocity sign (`TGConversationController.mm:5192-5318`). The window-moving trick
    is the risky half; the interactive shrink of the input area and table is the part worth
    porting, and it can be done without touching `UIWindow`.

12. **Swipe-left-to-pop and swipe-right-to-profile are absent.** Ours has a reply swipe on the
    table (`:2780`) but not the original's two conversation-level swipes with their 36/10/10/200
    thresholds (`TGConversationController.mm:1235-1251`, `:4641`).

13. **No avatar overlay art and no landscape avatar size.** Ours is a 37 pt circle produced by
    `cornerRadius` (`:3789-3792`). The original is a 35×35 image (25×25 in landscape) inside a
    37×38 container with a separate overlay image drawn 2 pt proud on each side
    (`TGTelegraphConversationCompanion.mm:4664-4669`,
    `TGConversationController.mm:2128-2129`). The comment in our code ("42dp in their header")
    cites a number that does not appear anywhere in the original; the real numbers are 35/25.

### Where ours is right

Input-bar geometry and send-button typography (above). Placeholder colour: ours uses
`(0.616, 0.655, 0.702)` (`:3058`) which is `0x9DA7B3`, exactly the original's `0x9da7b3`
(`TGConversationController.mm:991`). Empty-plate size 122×116 and glyph at y 23. Use of the
original PNG names — `ConversationInputPanel`, `ChatInputContainer_Shadow`, `AttachBtn`,
`SendButton`, `ConversationIconPlain` — with sane fallbacks when the asset is missing.

### Genuinely ambiguous

The original's landscape title layout (title and status side by side, 3/5 vs 2/5 of the width,
`TGConversationController.mm:2044-2049`) is well specified, but the `titleOffsetY` branches on
`iosMajorVersion() >= 7` (`:1962`, `:2042`) — this build was straddling iOS 6 and 7, and on our
iOS 6.1.3 target the iOS 7 branch is dead. Use `titleOffsetY = 0`. I have not tried to guess
which of the two the 2013 screenshots show.

---

## 11. What became of it

### In `twelve` (the Objective-C fork, `Telegraph/TGModernConversationController.mm`, 14929 lines)

The same screen, same lineage, decomposed. The three changes that matter to us:

- **Panels became objects.** Where our original inlines the input field, the editing buttons and
  the request buttons into one controller, twelve has
  `TGModernConversationInputTextPanel`, `TGModernConversationEditingPanel`, a
  `_primaryTitlePanel` in a `_titlePanelWrappingView`, and a `_currentInputPanel` pointer that
  swaps between them (`TGModernConversationController.mm:492-498`, `:1170`, `:1083`). This was
  forced, not aesthetic: reply markup, bot keyboards, broadcast toggles, audio recording and
  channel restrictions each need a different bottom bar, and `setConversationLink:animated:`
  (our original's alpha-juggling state machine at `.mm:5665`) does not scale past two states.
- **The title became a view class.** `TGModernConversationTitleView`
  (`TGModernConversationController.mm:518`, `:702-704`) with `setShowStatus:showArrow:`
  (`:1115`) and its own unread handling (`:1328`), instead of 280 lines of manual frame
  arithmetic inside the controller.
- **The input panel grew to 45 pt** (`TGModernConversationController.mm:1170`) from 43. A
  small number, but it means 43 is specific to the 2013 artwork and not a constant to inherit
  blindly.
- The table became a `UICollectionView` with a custom
  `TGModernConversationViewLayout` (`:448`) — the `TGUseCollectionView` branch that was already
  present but compiled out in our v1.1 source (`TGConversationController.mm:1152`) is the
  ancestor of this. The rotation trick survives conceptually; the reversed-list idea never went
  away.

### In the modern Swift client

- `ChatControllerImpl` (`submodules/TelegramUI/Sources/ChatController.swift`, 11237 lines) plus
  `ChatControllerNode.swift` (5740). The imperative `conversationXChanged:` callbacks are gone,
  replaced by a single immutable `ChatPresentationInterfaceState`
  (`ChatController.swift:286-287`) that the whole screen re-derives itself from. Our original's
  bug class — `setStatusText:` flipping `_userBlocked` as a side effect of a string comparison
  (`TGConversationController.mm:1650-1656`) — is exactly what that redesign was aimed at, and
  it is a real defect in the original: the code infers "blocked" from the subtitle starting
  with `"you"`.
- The title is `ChatTitleView`
  (`submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift`) with a
  `ChatTitleContent` enum and a dedicated `ChatTitleActivityNode` (`:208`, `:261`) — the typing
  dots survived thirteen years as a first-class component.
- `ChatTextInputPanelNode` computes its height from
  `textInputViewInternalInsets.top + .bottom + textFieldMinHeight` (`:2373-2374`) rather than
  from a hard-coded 43/45, and corners are `floor(minimalInputHeight * 0.5)` (`:3151`) — the
  fixed-height, fixed-artwork input bar is the one thing that did *not* survive.

The through-line: the reversed list, the growing input field, the typing indicator and the
two-line title all survived unchanged in concept. What was abandoned is the *mechanism* — one
controller owning every frame, artwork stretched at hand-picked cap widths, and state expressed
as competing view alphas.

# Typography in Telegram for iOS 1.1 (build 21024, 2013)

Scope: every font the original constructs, where it is used, the shadow that travels with it, and
how the type scale drives the row heights it sits in. All citations are to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
unless another root is named. Paths are given relative to that root.

---

## 1. There is no font module

The first thing to know, because it shapes everything else: **the 2013 client has no `TGFont`, no
font constants file, and no semantic font names.** Every single font is constructed literally at its
use site, inside `init`, `loadView` or `layoutSubviews`. There are 243 literal
`systemFontOfSize:` / `boldSystemFontOfSize:` / `fontWithName:` constructions across the tree
(counted over both targets).

The closest thing to a font registry is `TGTelegraphConversationMessageAssetsSource`
(`Telegraph/Telegraph/TGTelegraphConversationMessageAssetsSource.m`), which vends *message-bubble*
fonts only, behind the `TGConversationMessageAssetsSource` protocol
(`TelegraphKit/TelegraphKit/TGConversationMessageAssetsSource.h:95-96`). Chrome, lists, settings and
login each roll their own.

The consequence for us: any "font system" in our port is a reconstruction, not a port. It is a
legitimate improvement — but only if the numbers it centralises are the original's numbers. Where
this document says "the rule is", it means the rule the values imply, not a rule the original wrote
down.

### 1.1 Which family is "system"

Two families ship:

* **The platform system font.** On iOS 6 `[UIFont systemFontOfSize:]` is Helvetica and
  `boldSystemFontOfSize:` is Helvetica-Bold. The original relies on this so completely that the
  message-text font is built by name — `CTFontCreateWithName(CFSTR("Helvetica"), TGBaseFontSize, NULL)`
  (`TGTelegraphConversationMessageAssetsSource.m:44`) — and `Helvetica-Bold` for the bold Core Text
  fonts (`ibid.:57, 96, 122, 326`). System font and Helvetica are used interchangeably in the same
  bubble: body text via Core Text Helvetica, sender name via both
  `CTFontCreateWithName(CFSTR("Helvetica-Bold"), 13, NULL)` (`:322-328`) and
  `[UIFont boldSystemFontOfSize:13]` (`:330-335`) for the two different draw paths. That
  interchange is only safe because they are the same typeface on this OS. **On our target (iOS 6.1.3)
  it is safe; do not "fix" it by switching to a named font.**
* **Myriad Pro**, bundled as `MyriadPro-Regular.otf` and `MyriadPro-Bold.otf`
  (`Telegraph/Telegraph/Resources/Fonts/`, registered in `Telegraph/Telegraph/Telegraph-Info.plist:60-64`).
  It is used in **exactly one screen**, the first-run tour: `TGLoginWelcomeController.m:118-124` —
  regular/bold at 15.5pt retina / 15.0pt non-retina for body, regular/bold 18.0 for the first page's
  title, bold 30.0 for page titles. Nowhere else in the app. If our tour is not Myriad, the tour is
  wrong; if anything else is Myriad, that is wrong too.

`italicSystemFontOfSize:` is **never called** in the original. There is no italic anywhere.

---

## 2. The size ladder

Every literal size in the tree, with the roles it serves. Sizes are grouped because the reuse is the
system: the original has roughly nine sizes doing all the work.

| Size | Weight | Role and citation |
|---|---|---|
| 9 | regular | Bubble timestamp AM/PM suffix — `messageDateAMPMFont`, `TGTelegraphConversationMessageAssetsSource.m:903-908` |
| 10 | regular | Document label on media (`messageDocumentLabelFont`, `:149-154`); forwarded-message date (`messageForwardedDateFont`, `:165-170`) |
| 10 | bold | Tab bar item captions (`Telegraph/Telegraph/TGMainTabsController.m:80, :90, :100`); media-download progress label inside bubbles (`TelegraphKit/TelegraphKit/TGConversationMessageItemView.mm:1925`); secret-chat lifetime badge in the nav title (`TGConversationController.mm`, `_titleLifetimeLabel`) |
| 11 | regular | Bubble timestamp (`messageDateFont`, `:895-901`); the AM/PM half of list dates (`TGDialogListCell.m:393`, `TGContactCell.m:343`, `TGImageViewControllerInterfaceView.m`) |
| 11 | bold | Tab-bar unread badge (`TGMainTabsController.m`); download-centre count (`TGDownloadCenterView.m`) |
| 11 + 0.5 retina | bold | The word "unsent" burned into the error badge image (`TGTelegraphConversationMessageAssetsSource.m:819`) |
| 12 | bold | **Toolbar/navigation buttons** (`TelegraphKit/TelegraphKit/TGToolbarButton.m:281` and `:326`); search-bar Cancel (`TGSearchBar.m`); conversation nav subtitle, normal and typing (`TGConversationController.mm:780, :790`); overlay date bubble while scrolling (`TGConversationController.mm`, `_overlayDateView`); map button group (`TGMapViewController.m`, `TGButtonGroupView.m`); image-picker count |
| 12 | regular | Profile "last seen" line's AM/PM (`TGProfileController.m:790`, `dateLabelFont`) |
| 12.5 / 13 | bold | Picker chrome buttons, retina 12.5 / non-retina 13 (`TGImagePickerController.mm`, `TGImageCropController.m`, `TGImageSearchController.mm`) |
| 13 | regular | Nav-bar **subtitle** for the generic two-line title (`TGViewController.mm:115-131`); bubble action/service text, forward header, forward phone (`TGTelegraphConversationMessageAssetsSource.m:62-121`, all `CTFontCreateWithName(CFSTR("Helvetica"), 13)`); contacts subtitle at 13 + retinaPixel (`TGContactCell.m:341`); chat-list date (`TGDialogListCell.m:391`); nearby/search subtitles |
| 13 | bold | **Sender name in group bubbles** (`messageAuthorNameFont` / `messageAuthorNameUIFont`, `:322-334`); bubble action *title* and forwarded-from name (`:50-58`, `:104-124`); day divider in the conversation (`TGConversationDateItemView.m:36`); the unread-messages divider (`TGConversationUnreadItemView.m:38`); the "Delete" glyph drawn into swipe buttons (`TGDialogListCell.m:450`, `TGContactCell.m:375`); inline media action buttons (`TGConversationMessageItemView.mm:1484, :2746`); profile "edit" caption |
| 14 | regular | Chat-list message preview (`TGDialogListCell.m:372`); conversation editing state label; profile status line (`TGProfileController.m`); notification banner body (`TGMessageNotificationView.mm`); login notices (`TGLoginPhoneController.m`, `TGLoginCodeController.m`) |
| 14 | bold | Chat-list **author prefix** in group rows (`TGDialogListCell.m:373`); chat-list unread badge (`:423`); menu buttons (`TGMenuView.m`); action panel buttons (`TGConversationActionsPanel.m`); notification banner title (`TGMessageNotificationView.mm`) |
| 14 + 0.5 retina | bold | "Add photo" two-line caption on avatars (`TGProfileController.m:723, :758-768`) |
| 14.5 | bold | The **Send** button (`TGConversationController.mm`, `_sendButton.titleLabel.font`) |
| 14.5 / 15 | regular+bold | Search "nothing found" attributed strings, retina 14.5 / non-retina 15 (`TGContactsController.mm:684-698`, `TGPeopleNearbyController.m`) |
| 15 | bold | **List section headers** (`TGContactsController.mm:1311`, `TGAddContactsController.mm`, `TGLoginCountriesController.m:245`); chat-list nav status label (`TGDialogListController.mm`); login profile name fields |
| 15 | regular | Media-attachment subtitle (`:141-146`); token field and token views (`TGTokenFieldView.m`, `TGTokenView.m`) |
| 15 + 0.5 retina | bold | User menu-item cell title (`TGUserMenuItemCell.m:81`) |
| 16 | **regular, default** | **Message body text** — `TGBaseFontSize = 16` (`:10`, `:44`); the composer input field, its placeholder and the fake input field (`TGConversationController.mm`) |
| 16 | bold | Nav-bar **title-with-subtitle** variant, portrait (`TGViewController.mm:97-104`) — this is the conversation header title; flat/block action cells (`TGFlatActionCell.m:42`, `TGBlockActionCell.m:57`); menu item titles (`TGInputMenuItemView.m`, `TGLabelMenuItemView.m`); callout title |
| 16.5 / 16 | bold | Login primary buttons, retina 16.5 / non-retina 16 (`TGLoginWelcomeController.m`, `TGLoginPhoneController.m:175`, `TGLoginInactiveUserController.m`) |
| 17 | bold | **The grouped settings row title** — `TGActionMenuItemCell.m:33`, `TGSwitchItemCell.m:38`, `TGVariantMenuItemCell.m:26`; contacts nav title (`TGContactsController.mm:685`); country picker rows; nearby cells; wallpaper cells |
| 16 (regular) | | The **variant** (right-hand detail) of a settings row: `TGVariantMenuItemCell.m:36` |
| 17 | regular | Gallery counts (`TGImagePickerGalleryCell.m`, `TGContactMediaItemCell.m`) |
| 18 | bold | Phone and code entry fields (`TGLoginPhoneController.m`, `TGLoginCodeController.m`); gallery name in pickers |
| 19 | bold / regular | **Contact row name.** Bold for the surname half, regular for the given-name half, or swapped by sort order: `TGContactCell.m:332-333`, `TGDialogListSearchCell.m:...` |
| 20 | bold | **Nav-bar title, portrait** (`TGViewController.mm:79-95`) |
| 17 | bold | **Nav-bar title, landscape** (same method, the `else` branch) |
| 15 | bold | Nav-bar title-with-subtitle, landscape (`TGViewController.mm:105-112`) |
| 20 | bold | Image-viewer counter (`TGImageViewControllerInterfaceView.m`) |
| 30 | bold Myriad | Tour page titles (`TGLoginWelcomeController.m:124`) |

---

## 3. The half-pixel idiom

Twenty-odd sites compute

```objc
float retinaPixel = TGIsRetina() ? 0.5f : 0.0f;
```

and add it either to a font size or to a Y origin. Two distinct uses, easy to conflate:

* **Size bump**: `[UIFont systemFontOfSize:13 + retinaPixel]` (`TGContactCell.m:341`,
  `TGUserMenuItemCell.m:81` at 15, `TGProfileController.m:723` at 14). On a 2x screen a half point
  is a whole pixel, so the retina build gets a marginally larger face that lands on the pixel grid;
  the 1x build keeps the round number. This is an *optical* correction, not a layout one.
* **Baseline nudge**: `_deliveredCheckmark.frame = CGRectMake(x, 11 + retinaPixel, …)`
  (`TGDialogListCell.m:1329`), `_dateLabel.dstOffset = 1 + retinaPixel`
  (`TGConversationMessageItemView.mm:452`).

Non-retina is the *reference*; retina is the corrected case. On the 4S (retina) we always take the
`+0.5` branch — but keep the expression, because the mixed 12.5/13-style pairs
(`TGIsRetina() ? 12.5f : 13.0f`, `TGImagePickerController.mm`) go the *other* direction, retina
smaller. There is no single rule; each site was tuned by eye.

---

## 4. Shadows: the 2013 signature

Almost every piece of text over a gradient or a bar carries a one-point shadow. The offsets are
consistent in direction if not in colour:

* **Text on a dark bar or over a photo → shadow *up*, `CGSizeMake(0, -1)`, dark colour.**
  * Nav title: colour `0x3d5c81` for `TGViewControllerStyleDefault`, `0x2f3948` otherwise, offset
    `(0, -1)` (`TGViewController.mm:151-179`, applied at `:449-451`).
  * Toolbar buttons: offset `(0, -1)`, colour from `shadowColorForButton(type)` or a caller-supplied
    override — the login screens pass `UIColorRGBA(0x050608, 0.4f)` / `UIColorRGBA(0x07080a, 0.35f)`
    (`TGToolbarButton.m:283-284, :328-329`; `TGLoginPhoneController.m:134`,
    `TGLoginCountriesController.m:184`).
  * List section headers: colour `0x88929c`, offset `(0, -1)` (`TGContactsController.mm:1311-1312`,
    `TGLoginCountriesController.m:245-246`).
* **Dark text on a light panel → shadow *down*, `CGSizeMake(0, 1)`, near-white or pale colour.**
  * Grouped-cell captions: `0xdae0e8` at `(0, 1)` (`TGCommentMenuItemView.m:39-40`,
    `TGNotificationSettingsController.m:278-279`).
  * Profile name and status: `UIColorRGBA(0xedf0f5, 0.28f)` at `(0, 1)`
    (`TGProfileController.m:781-782, :790-791`).
  * Contacts nav title/subtitle over the pale bar: `UIColorRGBA(0xffffff, 0.3f)` at `(0, 1)`
    (`TGContactsController.mm:685-698`).
* **Inside bubbles → no shadow at all, but the offset is still set.** `messageTextShadowColor`,
  `messageAuthorNameShadowColor`, `messageActionShadowColor` and `messageDateShadowColor` all
  `return nil` with the old body commented out
  (`TGTelegraphConversationMessageAssetsSource.m:181-188, :346-354, :297-315, :919-922`). The call
  sites still pass `shadowOffset:CGSizeMake(0, 1)`
  (`TGConversationMessageItemView.mm:1109, :1729, :1825`; `TGConversationDateItemView.m:34`) — a nil
  colour means UIKit draws nothing, so the offset is dead code. **This is the single most useful
  finding for a porter: bubble text in 1.1 is flat.** An earlier build had white 50% shadows under
  message text and they were deliberately switched off. Do not reintroduce them because the offset
  is there.
* One shadow is baked into a generated image rather than a label: the "unsent" badge draws its text
  with `CGContextSetShadowWithColor(context, CGSizeMake(0, -1), 0.0f, UIColorRGB(0xcc1e2c))`
  (`TGTelegraphConversationMessageAssetsSource.m:827`).

---

## 5. How type drives layout

### 5.1 Core Text line metrics — the one real formula

`TGReusableLabel.mm:183-332` is where bubble text is measured, and it defines the app's line box:

```
fontAscent  = CTFontGetAscent(font)
fontDescent = CTFontGetDescent(font)
fontLineHeight  = floorf(fontAscent + fontDescent)     // :201
fontLineSpacing = floorf(fontLineHeight * 1.2f)        // :202
```

* Baselines advance by `fontLineSpacing`, not by the font's own leading (`:317-321`).
* The measured block is `height + fontLineHeight * 0.1f` — a 10% tail so descenders on the last line
  are not clipped (`:332`).
* Kerning is explicitly zeroed: `kCTKernAttributeName = 0.0f` (`:204`).
* Single-line layouts report `fontLineSpacing` as their height and subtract trailing whitespace from
  the width (`:361`).
* Link highlight rectangles are `ceilf(fontLineSpacing)` tall, starting `fontLineHeight * 0.1f`
  above the baseline, inset −3/+6 horizontally (`:462`).

At the default 16pt Helvetica this yields a line height in the 14–15pt range and a spacing near 17;
**derive it, do not hard-code it** — the whole point is that it retracks when `TGBaseFontSize`
changes.

### 5.2 Row heights are font-derived, but only in two places

* **Contacts, 51pt** (`TGContactsController.mm:600, :1759`). `TGContactCell.m:664-690` does not use
  51 anywhere; it computes `titleSizeGeneric.height = _contactContentsView.titleFont.lineHeight`
  (19pt bold) and `subtitleSize.height = _subtitleLabel.font.lineHeight`
  (13 + retinaPixel), then centres the pair with `titleLabelsY = (viewSize.height - title - subtitle - 1) / 2`
  and stacks the subtitle at `titleLabelsY + titleHeight + retinaPixel`. **51 is the number that
  makes 19pt over 13.5pt look centred next to a 40pt avatar inset 5 from the top** (`:668`). If the
  subtitle is hidden the title alone is centred, shifted up 1pt when an avatar is present (`:682`).
* **Chat list, 73pt** (`TGDialogListController.mm:1118-1125`; the loading row is 50, search results
  are 51 for contacts and 73 for chats, `:1129`). Here nothing is font-derived: the text view is a
  fixed `CGRect(73, 6, w−73, 58)` and every Y is a literal — title at y=6 in a 20pt box, date at
  y=9 in a 15pt box, message at y=29 in a 40pt box (`TGDialogListCell.m:1272-1345`). The 73 is
  avatar geometry, not typography.
* Everything else is a flat `rowHeight = 44` (`TGTextFontController.m:77`,
  `TGLoginCountriesController.m:269, :460`, `TGPhoneLabelController.m:85`,
  `TGCustomNotificationController.m:110`) — the platform default, which is why the 17pt bold row
  title reads as standard iOS.

### 5.3 What long text does

* Chat-list title: width is clamped to the text's own width so the mute icon can sit right after it,
  `titleLabelWidth = MIN(available, [_titleText sizeWithFont:titleFont].width)`
  (`TGDialogListCell.m:1327`), then drawn with `NSLineBreakByTruncatingTail` (`:256`).
* Chat-list preview: two lines' worth of box (40pt at y=29), but when an author prefix is present
  the box drops 9pt and loses 12pt of height (`:1358-1361`), and **if the message then measures
  under 20pt tall it drops another 9pt** (`:1365-1366`) — that is the rule that vertically centres a
  one-line preview under a group author name. Get this wrong and every group row looks 9pt high.
* Typing indicator draws with `NSLineBreakByClipping`, never truncated (`:263`), and the animated
  dots are positioned at `typingRect.origin.x + measuredWidth` (`:1347-1355`).
* Nav title: `sizeToFit`, then `height += 2`, centred horizontally, and vertically centred in 44
  (portrait) or 32 (landscape) plus 1 (`TGViewController.mm:458-465`).

### 5.4 The three-font date label

`TGDateLabel` (`TelegraphKit/TelegraphKit/TGDateLabel.m`) is a small piece of typography worth
copying exactly. It holds **three** fonts:

* `dateFont` — used when the locale is 24-hour (`TGUse12hDateFormat()` false).
* `dateTextFont` — used for the numeric part when the locale is 12-hour.
* `dateLabelFont` — used only for the trailing "AM"/"PM", drawn right-aligned as a separate call
  (`:118-122`).

The `" AM"` / `" PM"` suffix is stripped from the incoming string and re-drawn in the smaller face
(`:44-56`); measurement adds a fixed `amWidth` / `pmWidth` rather than measuring the suffix
(`:69-82`). Callers set those:

* Bubble timestamp: `dateFont = dateTextFont = messageDateFont` (11 regular), `dateLabelFont =
  messageDateAMPMFont` (9 regular), `amWidth = pmWidth = 15`, `dstOffset = 1 + retinaPixel`
  (`TGConversationMessageItemView.mm:446-455`). Because the two main fonts are the same, the bubble
  timestamp looks identical in 12h and 24h except for the small suffix.
* Chat list: `dateFont` regular 13, **`dateTextFont` bold 13**, `dateLabelFont` regular 11
  (`TGDialogListCell.m:391-393`). Here the fonts differ: **a 12-hour locale gets a bold time, a
  24-hour locale gets a regular one.** That is not a bug in the port if it looks odd — it is the
  original.
* Contacts: `dateFont = dateTextFont = 13 + retinaPixel`, `dateLabelFont` 11 (`TGContactCell.m:341-343`).
* Profile status: `dateLabelFont` 12 under a 14 regular status (`TGProfileController.m:790`).

---

## 6. `TGBaseFontSize` — the only user-facing type control

* Declared `extern int TGBaseFontSize` (`TGTelegraphConversationMessageAssetsSource.h:13`), defined
  `= 16` (`.m:10`).
* It sizes exactly one thing: `messageTextFont`, rebuilt lazily whenever the value changes, as
  `CTFontCreateWithName(CFSTR("Helvetica"), TGBaseFontSize, NULL)` (`.m:32-46`). The old `CTFontRef`
  is released first. Bubble geometry follows automatically through the §5.1 formula. **Nothing else
  in the app scales** — sender names stay 13, timestamps stay 11, the composer stays 16.
* The picker offers `@[@(16), @(18), @(20), @(24), @(32), @(40)]` in a grouped table with
  `rowHeight = 44`, labelled `"%dpt"`, with a check mark on the current value
  (`TGTextFontController.m:33, :42, :77`). Cancel/Done toolbar buttons with `minWidth` 59/51
  (`:60-70`); the value is only committed on Done (`:202-207`).
* Persistence clamps to `MAX(16, MIN(60, value))` with a fallback of 16
  (`TGAppDelegate.mm:900-905`), stored under `@"baseFontSize"` (`:938`). **16 is the floor** — the
  original never lets message text go below the default.
* The settings row shows `"%dpt"` as its variant (`TGChatSettingsController.m:75, :170`).

---

## 7. What happened next

### twelve (`/Users/alexanderhavrysh/Git/iOS/twelve`)

The fork finally built the module the original lacked:
`submodules/LegacyComponents/LegacyComponents/TGFont.h` declares
`TGSystemFontOfSize`, `TGBoldSystemFontOfSize`, `TGLight/Ultralight/Medium/Semibold/Italic/Fixed`,
plus Core Text twins (`TGCoreTextSystemFontOfSize` etc.) and a `TGFont` class with
`+roundedFontOfSize:`. The implementation (`TGFont.mm:8-100`) is a compatibility shim: below iOS 7
it returns `HelveticaNeue` / `HelveticaNeue-Medium` / `HelveticaNeue-Light` by name, at or above
iOS 7 it defers to the platform. In other words the abstraction was created not to make a type scale
but to **force the iOS 7 look onto iOS 6** — the opposite of our goal. `TGFixedSystemFontOfSize`
is Courier; `roundedFontOfSize:` reaches for `.SFCompactRounded-Semibold`.

Substantively the fork kept the scale: `TGBaseFontSize = 16`
(`Telegraph/TGTelegraphConversationMessageAssetsSource.m:9`), the same
`@[@(16),@(18),@(20),@(24),@(32),@(40)]` ladder with a default of 16
(`Telegraph/TGTextSizeController.m:32, :81`), and `messageTextFont` still rebuilt on change, now via
`TGCreateCTFontFromUIFont` on iOS 7+ and `CTFontCreateWithName(systemFont.fontName, …)` below
(`:44-62`). So: thirteen years of features, same six sizes.

### The modern client (`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS`)

`submodules/Display/Source/Font.swift` turns fonts into a full value type — `Font.Design`
(regular/serif/monospace/round/camera), `Font.Traits` (italic, monospaced numbers), `Font.Width`
(standard/condensed/compressed/expanded), and a weight enum. The type scale became a preference
enum, `PresentationFontSize` with seven cases mapping to base display sizes
14/15/16/17/19/23/26 (`submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift:268-276`,
`submodules/TelegramPresentationData/Sources/ComponentsThemes.swift:21-38`), and it is initialised
from the *system* Dynamic Type size by nearest match (`ComponentsThemes.swift:12-17`).

Two changes matter to us:

1. **The base size now propagates.** `ChatPresentationData` derives an entire family from one number
   — `messageFont`, `messageBoldFont`, `messageItalicFont`, `messageBoldItalicFont`,
   `messageFixedFont`, and `messageBlockQuoteFont = baseFontSize − 1`, with a fixed 53pt emoji font
   (`submodules/TelegramPresentationData/Sources/ChatPresentationData.swift:56-63`). In 1.1 only the
   plain body scaled; the modern client learned that a scale with one scaling member is not a scale.
   The forcing problem was rich text: bold/italic/monospace/quote inside a message did not exist in
   1.1, and each one needs its own derived face.
2. **The floor dropped from 16 to 14, and there is a separate `listsFontSize`.** Accessibility, not
   aesthetics.

Nothing about weights or shadows survived: the modern client has no text shadows at all. The 2013
shadow vocabulary is dead everywhere except in our port, which is exactly why it is worth getting
right here.

---

## 8. Our port, judged

Ours is `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src`. Broad verdict: **the sizes are mostly
right; the chrome shadows and the text-size setting are wrong; and the settings scale drifted.**

What is right, briefly, and needs no work:

* Chat-list cell: bold 16 title / regular 14 preview / bold 14 author / 13 date / 11 suffix /
  bold 14 badge and `kRowHeight = 73`
  (`TGChatListViewController.m:283-332`, `:26`) match `TGDialogListCell.m:371-423` and
  `TGDialogListController.mm:1124` exactly, including the bold-vs-regular date split
  (`TGChatListViewController.m:603`) mirroring `dateTextFont`/`dateFont`.
* Contacts: 19 regular / 19 bold name halves, `13 + TGContactsRetinaPixel()` subtitle,
  `kContactRowHeight = 51` (`TGContactsViewController.m:246-261, :19`) match
  `TGContactCell.m:332-341` and `TGContactsController.mm:1759`.
* Bubbles: body at `TGMessageBaseFontSize()`, sender bold 13, timestamp 11, day divider bold 13,
  unread divider bold 13, composer 16, Send bold 14.5
  (`TGChatViewController.m:1165, 1170, 1257, 1276, 1320, 3048, 3090`) match
  `TGTelegraphConversationMessageAssetsSource.m:10/327/895`, `TGConversationDateItemView.m:36`,
  `TGConversationController.mm` (`_inputField`, `_sendButton`).
* Tab bar bold 10 captions, bold 11 badge (`TGTabBar.m:52, :171`) match `TGMainTabsController.m:80-100, :172`.
* `TGDateLabel.m` reproduces the three-font mechanism faithfully, including the right-aligned suffix
  draw and the fixed am/pm widths.

### Defects

**D1 — The message text-size ladder is wrong, and below the original's floor.**
Ours offers 13/15/17/19 pt from an action sheet and computes `13.0f + index * 2.0f`
(`src/TGSettingsViewController.m:4394-4402`, `:4725`). The original offers **16/18/20/24/32/40** in a
grouped table with 44pt rows and a check mark (`TGTextFontController.m:33, :77`) and clamps to
`MAX(16, MIN(60, …))` (`TGAppDelegate.mm:902`). Ours clamps only the top:
`stored > 0 ? MIN(60.0f, stored) : 16.0f` (`src/TGTheme.m:41-43`), so 13pt message text is
reachable — a size the original could not produce. Fix: replace the four-entry sheet with the
six-entry list, and floor the getter at 16.

**D2 — Nav-bar title shadow is the wrong colour, and there is no landscape face.**
`src/TGChatListViewController.m:1430-1441` uses bold 20 with `colorWithWhite:0 alpha:0.4` at
`(0, -1)`. The original is bold 20 portrait / **bold 17 landscape**
(`TGViewController.mm:79-95`, driven through `TGLabel.portraitFont`/`landscapeFont` at
`:446-448`) with shadow **`UIColorRGB(0x3d5c81)`** (`:151-158`) — a blue-grey that belongs to the
bar gradient, not neutral black. Our `TGLabel` already has the portrait/landscape properties
(`src/TGLabel.h:17-18`) and nobody sets them. Same shadow error in the chat header
(`src/TGChatViewController.m:2900-2902`).

**D3 — The conversation header is a size too large and its subtitle a weight too light.**
Ours: name bold **17**, subtitle regular **12**, subtitle white 75%
(`src/TGChatViewController.m:2900, :2906-2909`). Original: name bold **16** portrait / bold 15
landscape (`TGViewController.mm:97-112`, applied `TGConversationController.mm:765-767`), subtitle
**bold 12** in `UIColorRGB(0xe0eefd)` with shadow `0x3d5c81` at `(0, -1)`
(`TGConversationController.mm:780-783`). Three separate corrections in four lines.

**D4 — Nav-bar and bar-button typography is left to UIKit.**
`src/TGTheme.m:442-509` sets only `titleTextAttributes` colour and back-button images; no font, no
shadow. The original never lets UIKit choose: every bar button is a `TGToolbarButton` with **bold 12**
and a `(0, -1)` shadow (`TGToolbarButton.m:281-284, :326-329`). Our screens that do build custom bar
buttons already use bold 12 (`src/TGChatListViewController.m:880`,
`src/TGProfileViewController.m:4011`, and eight more), so the default path is the odd one out —
which is why system-created back buttons look like iOS 6 and ours look like 2013 on the same screen.
Set the font and `NSShadow`/`UITextAttributeTextShadowColor` on the `UIBarButtonItem` appearance
proxy alongside the colour.

**D5 — Settings row titles oscillate between bold 15 and bold 17.**
`src/TGSettingsViewController.m` uses bold 17 at `:3219` and bold 15 at `:356`, `:2703`, `:3258`,
`:3269`, in rows of the same visual class. The original is uniform: **bold 17 title** for every
grouped row — `TGActionMenuItemCell.m:33`, `TGSwitchItemCell.m:38`, `TGVariantMenuItemCell.m:26` —
with **regular 16** for the right-hand variant text (`TGVariantMenuItemCell.m:36`). Bold 16 is
reserved for the *flat/destructive* action rows (`TGFlatActionCell.m:42`,
`TGBlockActionCell.m:57`); bold 15 is a section-header size (`TGContactsController.mm:1311`), not a
row size. Fix: 17 bold for every settings row title, 16 regular for detail, 16 bold only for
"Delete/Leave"-class rows.

**D6 — Bubble timestamps are hard-wired to 24-hour, so the 9pt AM/PM face never appears.**
`src/TGChatViewController.m:7228-7237` formats with `@"HH:mm"` and measures with a flat
`systemFontOfSize:11` (`:7240`); the bubble's `time` label is a plain `UILabel`
(`:1257`). The original routes the bubble timestamp through `TGDateLabel` with an 11pt body and a
**9pt** AM/PM suffix, `amWidth = pmWidth = 15`, `dstOffset = 1 + retinaPixel`
(`TGConversationMessageItemView.mm:446-455`; `messageDateAMPMFont`,
`TGTelegraphConversationMessageAssetsSource.m:903-908`). We already have `TGDateLabel`; use it in
the bubble, and honour the locale as `TGUse12hDateFormat()` does.

**D7 — Myriad Pro is absent.** No `fontWithName:@"MyriadPro` anywhere in `src`, and the login
flow uses system faces (`src/TGLoginViewController.m`). If the tour is in scope, it needs the two
`.otf` files, a `UIAppFonts` entry, and the 15.5/15.0, 18.0, 30.0 sizes from
`TGLoginWelcomeController.m:118-124`. Everything else in login is correctly system-font, so this is
one screen's worth of work, not a sweep.

**D8 — Sender-name colour aside, no text-shadow policy exists for bubbles, which is accidentally
right.** Our bubble labels set no shadows, matching `messageTextShadowColor == nil` etc. Noting it
so nobody "restores" them.

**D9 — Ours has no italic and no monospace policy, and it uses both.**
`src/TGChatViewController.m:487-489` maps `preformatted` to `[UIFont fontWithName:@"Courier" size:13]`
and `italicSystemFontOfSize:15` for quotes, and `src/TGContactsViewController.m:862` uses Courier 11.
The original has no italic anywhere and no Courier. This is not a defect against the original so
much as a gap in it: rich text did not exist in 1.1, so there is **no authority for these two
faces** — the modern client's answer is `Font.monospace(baseFontSize)` and
`Font.italic(baseFontSize)`, i.e. derived from the message base size, not fixed at 13/15
(`ChatPresentationData.swift:56-61`). Recommend deriving both from `TGMessageBaseFontSize()`.
Flagged honestly as an extrapolation, not a citation.

---

## 9. Where the original contradicts itself

Documented rather than smoothed over, because a porter will hit each of these and assume a mistake:

1. **Two ways to say Helvetica-Bold 13.** The sender name exists as both a `CTFontRef`
   (`messageAuthorNameFont`, `:322-328`) and a `UIFont` (`messageAuthorNameUIFont`, `:330-335`) for
   the Core Text and UIKit draw paths respectively. They must stay in lockstep by hand.
2. **The retina half-point goes both ways.** `13 + retinaPixel` (bigger on retina,
   `TGContactCell.m:341`) versus `TGIsRetina() ? 12.5f : 13.0f` (smaller on retina,
   `TGImagePickerController.mm`) and `TGIsRetina() ? 14.5f : 15.0f`
   (`TGContactsController.mm:684`). There is no rule; copy per site.
3. **Dead shadow offsets.** Every bubble text item passes `shadowOffset:(0, 1)` to a nil shadow
   colour (§4). Harmless, but it makes the code look like it shadows text when it does not.
4. **`messageForwardPhoneColor` is `UIColorRGB(010101)`** —
   `TGTelegraphConversationMessageAssetsSource.m:275`. Not `0x010101`; decimal 10101 = `0x2775`, a
   green-blue. A typo in the original that shipped. Not typography, but it lives in the same
   file and someone will copy it.
5. **`messagerequestActorBoldFont`** (lowercase `r`) — `:89`. The name is a typo; the font is
   Helvetica-Bold 13 like the others.
6. **`titleShadowColorForStyle:` branches on style and returns two different colours; every other
   `…ForStyle:` method marks the parameter `__unused` and returns one value**
   (`TGViewController.mm:79-179`). So the "styles" system is one-third implemented: colours differ,
   fonts never do.
7. **The nav title has two font pairs and no rule for choosing.** `titleFontForStyle:` (20/17) is
   used when a controller sets `titleText`; `titleTitleFontForStyle:` (16/15) plus
   `titleSubtitleFontForStyle:` (13/13) is used when a controller builds a two-line title view. But
   the conversation controller uses the *title* font of the two-line pair (16) with its own bold-12
   subtitle, never the 13 subtitle font — `titleSubtitleFontForStyle:` has no caller in the tree.
   The 13pt nav subtitle is defined and unused.

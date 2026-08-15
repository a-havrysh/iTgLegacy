# The colour system of Telegram for iOS 1.1 (2013–2014)

Study of one cross-cutting aspect of the original. Authority for everything below is
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
(Telegram for iOS v1.1, build 21024). Paths in citations are relative to that root.
Comparisons name `Telegram-iOS` (modern Swift client), `twelve` (later Objective-C fork),
and `iTgLegacy/src` (our port).

---

## 0. How to read this document

Colours in the original arrive by three different routes, and confusing them is the main
source of error when porting:

1. **Hex literals in code**, through two macros defined in
   `TelegraphKit/TelegraphKit/TGCommon.h:28-29`:
   ```objc
   #define UIColorRGB(rgb)     ([[UIColor alloc] initWithRed:(((rgb >> 16) & 0xff) / 255.0f) ... alpha:1.0f])
   #define UIColorRGBA(rgb,a)  ([[UIColor alloc] initWithRed:(((rgb >> 16) & 0xff) / 255.0f) ... alpha:a])
   ```
   There are **364 such call sites** across the tree. They are all text, hairlines, shadows
   and label tints. **No filled surface of any size is a literal.**
2. **PNG assets in `Telegraph/Telegraph/Resources/`** (535 files). Every large surface —
   navigation bar, bubbles, tab bar, badges, buttons, wallpaper — is a bitmap with a
   vertical gradient baked in. Their exact pixel values are given below; they are the part
   most easily lost in a port that substitutes a flat `UIColor`.
3. **One runtime-derived colour**, the wallpaper *monochrome tint*, from which service-message
   plates and upload chrome are generated at run time (§6).

There is no palette object, no theme, and no dark mode. `TGInterfaceAssets` is the closest
thing to a palette and it holds exactly **one** colour array (§5) plus pattern-image getters
(`Telegraph/Telegraph/TGInterfaceAssets.h:19-24`).

---

## 1. The base structure: a blue-grey chrome over white content

The whole app is three surfaces.

| Surface | What it is | Source |
| --- | --- | --- |
| Chrome (nav bar, search bar, tab bar, toolbars) | gradient PNG | `Header_Corners.png`, `TabBarBackground.png` |
| Content (lists, settings, profile) | white, or a linen/lines pattern | `[UIColor whiteColor]`, `Linen.png`, `SettingsBackground.png` |
| Conversation | wallpaper image + bubble PNGs | `wallpaper-original-pattern-default.jpg`, `Msg_In.png`, `Msg_Out.png` |

Text on chrome is always **white with a dark 0/-1 shadow**; text on content is always
**dark on white with no shadow, or dark with a light 0/+1 shadow when it sits on the
linen/lines pattern**. That single rule explains almost every shadow colour in the codebase
and is more portable than the individual values.

---

## 2. Chrome (the blue)

### 2.1 Navigation bar

Not a colour. `TGNavigationBar` installs a resizable image at
`TelegraphKit/TelegraphKit/TGNavigationBar.m:91-93`:

```objc
UIImage *rawPortrait = [UIImage imageNamed:@"Header_Corners.png"];
[TGNavigationBar setDefaultNavigationBarBackground:
    [rawPortrait resizableImageWithCapInsets:UIEdgeInsetsMake(0, 8, 0, 8)] ...];
```

with a pre-iOS-5 fallback to the non-resizable `Header.png` (`TGNavigationBar.m:97`).
Cap insets are horizontal only (8pt left/right), so **the vertical gradient is never
stretched** — the bar is exactly 44pt tall at 88px @2x.

Measured from `Resources/Header_Corners@2x.png` (88×88 px, sampled down the centre column):

| Row (px @2x) | Value |
| --- | --- |
| 0 (top) | `#769abb` |
| 22 | `#6187ad` |
| 44 (midpoint) | `#547aa1` |
| 66 | `#486d95` |
| 85 | `#40658d` |
| 86 | `#3d628a` |
| 87 (bottom hairline) | `#0d2d53` |

So: a linear gradient `#769abb → #40658d` with a **1px `#0d2d53` bottom edge**. A single
flat colour that best represents it is `#547aa1`, the exact midpoint.

The black-opaque variant used over media is `HeaderBlackOpaque.png`
(`TGNavigationBar.m:99`), measured `#404040 → #1a1a1a`.

### 2.2 Text on the bar

| Role | Value | Source |
| --- | --- | --- |
| Title | `#ffffff` | `TelegraphKit/TelegraphKit/TGViewController.mm:139,146` |
| Title shadow (default style) | `#3d5c81`, offset `(0,-1)` | `TGViewController.mm:157` |
| Title shadow (dark/black style) | `#2f3948`, offset `(0,-1)` | `TGViewController.mm:164` |
| Conversation subtitle, online | `#e0eefd` | `TelegraphKit/TelegraphKit/TGConversationController.mm:781,1645` |
| Conversation subtitle, not online | `#c9dcf2` | `TGConversationController.mm:1646` |
| Subtitle shadow | `#3d5c81` | `TGConversationController.mm:782,794` |
| Secret-chat lifetime label | `#c9dcf2`, shadow `#587da3` | `TGConversationController.mm:1918-1919` |
| Dialog-list title status label shadow | `#415a7e` | `TGConversationController.mm:5527`, `TelegraphKit/TelegraphKit/TGDialogListController.mm:269` |

Note the deliberate split: **online is a brighter blue-white (`#e0eefd`) than any other
status (`#c9dcf2`)** — the only presence indicator the 2013 UI had, since there was no
green dot anywhere.

`titleTextColorForStyle:` returns `#ffffff` in **both** branches
(`TGViewController.mm:135-149`) — the style parameter is vestigial for text colour and only
changes the shadow. Do not read meaning into the branch.

### 2.3 Bar buttons

`TGToolbarButton` draws its label white with a translucent dark shadow:
`#042651 @ 0.3` normal, `#0e284d @ 0.4` for the group variant
(`TelegraphKit/TelegraphKit/TGToolbarButton.m:197,204`;
`TelegraphKit/TelegraphKit/TGButtonGroupView.m:176`). Backgrounds are again PNGs
(`HeaderButton*.png`, ten variants covering blue/landscape/pressed/login).

### 2.4 Search bar

`TelegraphKit/TelegraphKit/TGSearchBar.m:38` — cancel-button title `#ffffff` with shadow
`#112e5c @ 0.2`, over `SearchCancelButton.png` (measured `#8b9db4 → #506375`, midpoint
`#788aa2`). `TGDialogListController.mm:514,519-520` repeats the same `#112e5c @ 0.2` and adds
a `#5c708b` label with a `#ffffff @ 0.25` shadow for the "no results" state.

### 2.5 Tab bar

`Telegraph/Telegraph/TGMainTabsController.m:52` uses `TabBarBackground.png`. Measured
(6×98 px @2x): a near-black vertical gradient `#272727 → #0c0c0c`, **alpha 235/255 (0.92)
uniformly** — the tab bar is slightly translucent, which is easy to miss.
`TabBarSelected.png` is not a colour but `#ffffff @ 13/255 (0.05)` flat — the selection is a
5%-white wash, not a tint.

Labels: `#999999` normal, `[UIColor whiteColor]` highlighted, `boldSystemFontOfSize:10`
(`TGMainTabsController.m:78,88,98` — repeated verbatim three times, once per tab).

---

## 3. Content surfaces

| Role | Value | Source |
| --- | --- | --- |
| Dialog list background | `[UIColor whiteColor]` | `Telegraph/Telegraph/TGInterfaceAssets.mm` `dialogListBackgroundColor` |
| Dialog list section header | `#e4e9f0` | `TGInterfaceAssets.mm:177`; same value repeated at `TGContactsController.mm:506`, `TGAddContactsController.mm:226`, `TGLoginCountriesController.mm:275` |
| Section header text | `#8d9298` | `TGContactsController.mm:852`, `TGAddContactsController.mm:138`, `TGLoginCountriesController.mm:307`, `TGDialogListController.mm:440` |
| Index bar / letter text | `#88929c` | `TGContactsController.mm:1311`, `TGAddContactsController.mm:247`, `TGLoginCountriesController.mm:245` |
| Contacts separator | `#dfe4eb` | `TGContactsController.mm:549` |
| Linen (chat/profile pattern) | `Linen.png`, measured `#dde6ef` | `TGInterfaceAssets.mm` `blueLinenBackground` |
| Settings "lines" pattern | `SettingsBackground.png`, measured `#c9d1db` | `TGInterfaceAssets.mm` `linesBackground` |
| Footer pattern | `Footer.png` | `TGInterfaceAssets.mm` `footerBackground` |
| Grouped-cell hairline | `#e5e5e5` | `Telegraph/Telegraph/TGBlockActionCell.m:84`, `TGImageSearchController.mm:265` |

Settings captions above/below a group are `#697487` with a `#dae0e8` light shadow
(offset +1) — this pair appears identically in four controllers:
`TGChatSettingsController.m:196-197`, `TGNotificationSettingsController.m:277-278`,
`TGPrivacySettingsController.m:162-163`, `TGCommentMenuItemView.m:38-39`. It is the single
most reliably repeated pair in the codebase and is effectively "the caption style".

---

## 4. The conversation

### 4.1 Bubbles

Nine-part stretchable PNGs, not drawn shapes
(`Telegraph/Telegraph/TGTelegraphConversationMessageAssetsSource.m:648-787`):

| Method | Asset | Caps |
| --- | --- | --- |
| `messageBackgroundBubbleIncomingSingle` | `Msg_In.png` | left 20, top 15 (`:652`) |
| `messageBackgroundBubbleIncomingDouble` | `Msg_In_High.png` | insets `(15, 23, 15, w-23-1)`, stretch (`:663`) |
| `messageBackgroundBubbleIncomingHighlighted` | `Msg_In_Selected.png` | 20/15 (`:681`) |
| `messageBackgroundBubbleIncomingHighlightedShadow` | `Msg_In_Selected_Shadow.png` | 20/15 (`:692`) |
| `messageBackgroundBubbleOutgoingSingle` | `Msg_Out.png` | left 15, top 15 (`:721`) |
| `messageBackgroundBubbleOutgoingDouble` | `Msg_Out_High.png` | insets `(15, 17, 15, w-17-1)` (`:733`) |
| `messageBackgroundBubbleOutgoingHighlighted` | `Msg_Out_Selected.png` | 15/15 (`:754`) |

"Double" means the tall variant used when a bubble spans two or more lines; the pre-iOS-5
fallback path at `:668` and `:738` simply uses the raw unstretched image, which visibly
clipped long messages. We do not need that path.

Measured fills (centre column of the @2x asset, opaque rows only):

| Bubble | Top | Bottom | Bottom edge |
| --- | --- | --- | --- |
| Incoming `Msg_In` | `#ffffff` | `#f8f8f8` | soft `#002162` shadow at ~5% |
| Incoming selected `Msg_In_Selected` | `#e5f3ff` | `#d7ecff` | — |
| Outgoing `Msg_Out` | `#e8fdcc` (settles to `#e3fcc2` by row 6) | `#c4fa9f` | 1px `#009405 @ 0.85` |
| Outgoing selected `Msg_Out_Selected` | `#c5f79c` | `#99f360` | 1px `#009005 @ 0.9` |

Two things a flat-colour port gets wrong: (a) the incoming bubble **starts at pure white**
and only fades to `#f8f8f8` — using `#fbfbfb` everywhere makes it read grey against a white
attachment; (b) the outgoing bubble has a **saturated green bottom stroke** which is what
makes it look "cut into" the wallpaper, and dropping it flattens the whole chat.

### 4.2 Text inside a bubble

| Role | Value | Source (`TGTelegraphConversationMessageAssetsSource.m`) |
| --- | --- | --- |
| Message body | `rgb(20,22,23)` = `#141617` | `:177` (via `colorWithRed:`, not the macro) |
| Message body shadow | **nil** (commented out; the disabled value was `#ffffff @ 0.5`) | `:182-190` |
| Timestamp | `#232d37` | `:915` |
| Timestamp shadow | nil | `:920` |
| Author name (group chats) | `#4d688c`, `Helvetica-Bold 13` | `:342`, font at `:325` |
| Author name shadow | nil (disabled `#ffffff @ 0.5`) | `:347` |
| Attachment title | `#62768a` | `:195` |
| Attachment subtitle | `#72879b` | `:203` |
| Document label | `#ffffff` on shadow `#111111` | `:211`, `:219` |
| Forwarded-from user | `#141617` | `:227` |
| Forwarded date | `#999999` | `:235` |
| Forward title, incoming | `#0e7acd` | `:243` |
| Forward title, outgoing | `#3a8e26` | `:251` |
| Forward name, incoming | `#0e7acd` | `:259` |
| Forward name, outgoing | `#169600` | `:267` |
| Unread-message row background | `#003871 @ 0.07` | `:891` |
| Normal-message row background | `[UIColor clearColor]` | `:883` |
| "Unsent" badge shadow | `#cc1e2c` under white text | `:828` |

Links inside message text: `#004bad`, defined twice in the same file
(`TelegraphKit/TelegraphKit/TGReusableLabel.mm:225` and `:556`) — one for each of the two
layout paths. Both are the same value, so it reads as duplication rather than intent.

### 4.3 Input panel and its buttons

| Role | Value | Source (`TGConversationController.mm`) |
| --- | --- | --- |
| Placeholder text | `#9da7b3` | `:991` |
| Send-button title | `[UIColor whiteColor]` | `:1021` |
| Send-button title shadow | `#0cb8e3 @ 0.3` | `:1020` |
| Send-button disabled title | `#ceffb0` on 4-inch, `#bbffb2` on 3.5-inch | `:1022` |
| Editing "Delete" title | `#ffffff`, shadow `#9e0a01 @ 0.3` | `:4961-4962` |
| Editing "Forward" title | `#ffffff`, shadow `#3c6696 @ 0.5` | `:4987-4988` |
| Editing state text | `#576d85` | `:5034` |
| Request button, green | title `#ffffff`, shadow `#479415`, pressed `#458413` | `:5053-5055` |
| Request button, red | shadow `#cf2f29`, pressed `#b91510` | `:5054-5055` |

The disabled send-button colour branching on screen size (`[TGViewController isWidescreen]`)
is a genuine oddity — two greens one step apart chosen per device, presumably eyeballed on
the two panels. There is no reason to reproduce it; pick `#ceffb0`.

### 4.4 Unread divider and media buttons

`TelegraphKit/TelegraphKit/TGConversationUnreadItemView.m:35-36` — label `#506e8d`, shadow
`#ffffff @ 0.6`. The same `#506e8d` with `#ffffff @ 0.7` normal / `@ 0.5` highlighted shadow
is the media action button title, defined **twice** in
`TelegraphKit/TelegraphKit/TGConversationMessageItemView.mm:1479-1482` and `:2742-2744`.

---

## 5. Identity colours (avatar placeholders)

The only real "palette" in the app, `Telegraph/Telegraph/TGInterfaceAssets.mm:105-115`:

```
0  #ee4928   red
1  #41a903   green
2  #e09602   amber
3  #0f94ed   blue
4  #8f3bf7   violet
5  #fc4380   pink
6  #00a1c4   cyan
7  #eb7002   orange
```

Assignment is **not** `uid % 8`. From `TGInterfaceAssets.mm:22-45`:

```objc
snprintf(buf, 16, "%lld%d", uid, TGTelegraphInstance.clientUserId);
CC_MD5(buf, strlen(buf), digest);
colorIndex = ABS(digest[ABS(uid % 16)]) % numColors;   // numColors = 8
```

Consequences that matter:
* The **logged-in user's id is mixed into the hash**, so the same contact gets a different
  colour on a different account. This is why `clearColorMapping` exists
  (`TGInterfaceAssets.mm:84-95`) and is called on logout.
* The digest byte index is `uid % 16` — for a 16-byte MD5 that is in range, but `ABS` on an
  `int64_t` remainder is doing nothing useful; negative ids (groups were negative in the
  protocol) would previously have indexed out of range without the `ABS`.
* Group chats use a **separate 4-colour** space (`colorIndexForGroupId`,
  `TGInterfaceAssets.mm:47-69`) hashed on the group id **without** the client id, feeding
  `DialogListGroupAvatar1..4.png`.
* Colour index 0 is also the fallback when the map lookup path is skipped, so uid ≤ 0 falls
  back to `DialogListAvatarPlaceholder.png` rather than a colour
  (`TGInterfaceAssets.mm` `avatarPlaceholder:`), and uid `333000` (Telegram service) gets a
  dedicated `DialogListAvatarSystem.png`.
* The colours are **never used as `UIColor` fills for the placeholder** — `userColor:` is a
  separate accessor and the placeholders are eight prebuilt PNGs named
  `DialogListAvatar1..8.png`. The literal array exists so non-avatar UI can match.

---

## 6. The monochrome tint — the one derived colour

The chat wallpaper carries an integer tint. Default, written on first launch at
`Telegraph/Telegraph/TGAppDelegate.mm:878`:

```objc
int tintColor = 0x0c3259;   // for wallpaper-original-pattern-default.jpg
```

It is persisted as raw bytes in `wallpapers/_custom_mono.dat`
(`TGAppDelegate.mm:890`, re-written by `TGWallpaperStoreController.m:502,626`), read back at
`Telegraph/Telegraph/TGTelegraphConversationCompanion.mm:4527` and pushed into
`[TGTelegraphConversationMessageAssetsSource setMonochromeColor:]` at `:4534`. `-1` means
"no tint" and every consumer checks `_monochromeColor != -1`.

Three pieces of chrome are then generated at run time and cached to disk as PNGs keyed by
the tint (`messageProgressBackground_%x.png`, `messageProgressCancel_%x.png`,
`systemMessageBackground_%x.png` — `TGTelegraphConversationMessageAssetsSource.m:391,516,1126`):

| Generated asset | Geometry | Fill | Source |
| --- | --- | --- | --- |
| Service/system message plate | 21×21, radius 10 | `tint @ 0.29` | `:1155-1215`, alpha at `:1157` |
| Inline upload background | 13×13, radius 6 | `tint @ 0.4`, inner shadow `tint @ 0.45`, outer glow `#ffffff @ 0.3` | `:420-491`, alphas at `:422-423` |
| Inline cancel button | — | same construction, `alphaFactor` 1.0 normal / **1.4 highlighted** | `:542`, called at `:523` and `:629` |

**This is the single most important thing to get right about the 2013 palette:** the service
plate behind "X joined the group" and the date pill are *not* neutral grey or black. With the
shipped wallpaper they are `#0c3259` at 29% — a dark navy that reads blue against the pattern.
Substituting black or a desaturated slate changes the character of the whole conversation view.

---

## 7. The blues — where the original contradicted itself

There is no accent colour. There is a **family of eleven near-identical action blues**,
each introduced by whoever wrote the screen:

| Value | Where | Citation |
| --- | --- | --- |
| `#0779d0` | flat action cell title, "Add contact", contact-cell action, user menu item, notification action | `TGFlatActionCell.m:44`, `TGContactCell.m:544`, `TGUserMenuItemCell.m:286-287`, `TGBlockActionCell.m:59`, `TGMessageNotificationView.mm:228` |
| `#004bad` | link text in messages | `TGReusableLabel.mm:225,556` |
| `#036ceb` | nearby-contacts add button | `TGAddContactsNearbyCell.m:97` |
| `#046dd0` | map controller | `TGMapViewController.m:330` |
| `#0072d0` | image-picker gallery cell | `TGImagePickerGalleryCell.m:79` |
| `#085cc4` | wallpaper preview button | `TGWallpaperPreviewController.m:154,170` |
| `#146ab3` | encryption-key screen | `TGEncryptionKeyViewController.m:82` |
| `#1662c5` | camera controller | `TGCameraController.m:335` |
| `#1a78c8` | token view | `TGTokenView.m:56` |
| `#337acc` | dialog list date | `TGDialogListCell.m:394` |
| `#347fd4` | phone item cell | `TGPhoneItemCell.m:274-275` |
| `#2371c2` | unread badge highlighted text | `TGDialogListCell.m:422` |
| `#356596` | settings value on the right of a row | `TGVariantMenuItemCell.m:38` |
| `#516691` | menu item labels | `TGActionMenuItemCell.m:77`, `TGInputMenuItemView.m:51,86`, `TGLabelMenuItemView.m:41,73`, `TGLoginCountryCell.m:34` |

The same is true of the greys: `#888888` (dialog list preview, contact subtitle,
`TGDialogListCell.m:791`, `TGContactCell.m:347,777`), `#999999` (tab labels, forwarded date,
nearby cell), `#aaaaaa` (`TGPhoneItemCell.m:288`), `#a8a8a8` (image picker),
`#aeaeae` (`TGDateLabel.m:111`, `TGContactCellContents.m:78`), `#b3b3b3`, `#bbbbbb`.
These are not roles; they are seven people typing a grey.

**Recommendation for the port:** collapse the blues to `#0779d0` for tappable text,
`#004bad` for links, `#337acc` for the dialog-list date, `#356596` for settings values, and
`#516691` for menu-item labels. Those five carry real distinctions (three of them appear in
more than one file); the rest are noise and should not be reproduced individually.

### 7.1 Outright bugs in the original

* **`TGTelegraphConversationMessageAssetsSource.m:275`** —
  ```objc
  - (UIColor *)messageForwardPhoneColor { ... color = UIColorRGB(010101); ... }
  ```
  Missing `0x`. `010101` decimal is `0x002775`, a medium blue, not the near-black
  `#010101` that was clearly intended. Whether this was ever visible depends on whether
  forwarded contacts rendered a phone line; the value shipped as a blue.
* **`TGTelegraphConversationMessageAssetsSource.m:1061` and `:1083`** — the *outgoing*
  highlighted attachment corners load `AttachmentCornersIncomingTop_Highlighted.png` and
  `AttachmentCornersIncomingBottom_Highlighted.png`. Copy-paste; outgoing photos got the
  incoming (white) highlight corners.
* **`TelegraphKit/TelegraphKit/TGDialogListCell.m:1088-1097`** — `normalBackground`,
  `unreadBackground` (`#ebf0f5`), `normalMessage` (`#888888`) and `unreadMessage`
  (`#5b646e`) are assigned and **never read anywhere in the file**. The intended
  "unread rows are tinted blue-grey" behaviour was written and abandoned. In shipped v1.1
  **every dialog-list row is white** and the preview text is always `#888888`
  (via `normalTextColor` at `:791`, which is a different static of the same value).
  Do not implement the tint; it never shipped.
* **`TGDialogListCell.m:793`** — `mediaTextColor` is assigned `#536c8c`, identical to
  `actionTextColor` on the previous line, and never used.
* **`TGViewController.mm:135-149`** — `titleTextColorForStyle:` has two branches returning
  the identical `#ffffff` (see §2.2).
* **Disabled shadows.** `messageTextShadowColor` (`:182`), `messageAuthorNameShadowColor`
  (`:347`) and `messageDateShadowColor` (`:920`) all `return nil` with the intended value
  left commented out just below. The 2013 look people remember has **no text shadow inside
  bubbles**; the commented `#ffffff @ 0.5` is a rejected earlier design.

---

## 8. What happened to this concept afterwards

### 8.1 The modern client (Telegram-iOS)

Colours are no longer authored; they are **computed from one accent colour**.
`submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift:58` exposes
`customizeDefaultDayTheme(theme:editing:title:accentColor:outgoingAccentColor:...)`, and
`:78-88` derives the bubble fill from the accent by HSB transform:

```swift
bubbleColors = [accentColor.withMultiplied(hue: 0.966, saturation: 0.61, brightness: 0.98).rgb, accentColor.rgb]
...
UIColor(hue: hsb.0, saturation: (hsb.1 > 0.0 && hsb.2 > 0.0) ? 0.14 : 0.0, brightness: 0.79 + hsb.2 * 0.21, alpha: 1.0)
```

with `#e1ffc7` as the untinted default outgoing bubble (`:96, :646, :662, :689`) and
`#f7f7f7` as the universal light chrome fill (`:420, :426, :543, :914, :999`). The theme is a
value type built once and threaded through every node.

Two ideas from 2013 survived and are worth knowing:
* The **wallpaper-derived service colour** is still there, now named
  `serviceBackgroundColor` and applied with `withAlphaComponent(0.3)`
  (`DefaultDayPresentationTheme.swift:914`) — within a hundredth of the original's `0.29`
  (`TGTelegraphConversationMessageAssetsSource.m:1157`). Thirteen years and the number did
  not move. This is strong evidence that the `0.29` in §6 is a considered value and not an
  accident, and that our port should not round it to `0.4`.
* The **light green outgoing bubble** survived as the default (`#e1ffc7`, a lighter,
  less-saturated cousin of the 2013 gradient's `#e3fcc2 → #c4fa9f`).

What was abandoned: gradients baked into assets, per-screen literals, and text shadows —
all three were casualties of iOS 7's flat language and of needing runtime-recolourable themes.

### 8.2 twelve (the Objective-C fork)

The instructive one, because it faced exactly our problem: extend the 2013 codebase after
new features and dark mode arrived. Its answer was to interpose a palette object.
`Telegraph/TGPresentationPallete.h` declares **175 named colour roles** through a
`#define COLOR @property (nonatomic, readonly) UIColor *` macro, with four concrete
subclasses: `TGDefaultPresentationPallete`, `TGDayPresentationPallete`,
`TGNightPresentationPallete`, `TGNightBluePresentationPallete`. The `UIColorRGB` literals
did not go away — there are still **752** of them — they moved into the palette files
(e.g. `TGDefaultPresentationPallete.m:24` `accentColor = #007ee5`, `:369`
`chatOutgoingBubbleColor = #e1ffc7`, `:64` `barBackgroundColor = #f7f7f7`).

The lesson for us: 175 roles is what it actually takes to name every distinction the
original made implicitly. A palette with fifteen roles will silently collapse distinctions
the original drew (see §9).

---

## 9. Our port, judged

`iTgLegacy/src/TGTheme.m:189-217` defines **26 named constants** and thirty-odd accessors.
The structure is right and the arithmetic is honest: the constants were clearly taken from
the original rather than guessed. Specifically these are **correct and need no change**:

* `TG_BAR_BLUE 0x547AA1` — the exact midpoint of `Header_Corners@2x.png`; a good flat
  fallback. And `images/NavBarBackground@2x.png` is byte-for-byte the original asset
  (verified: top `#769abb`, mid `#547aa1`, bottom `#0d2d53`), applied with the same 8pt
  horizontal cap insets in `TGTheme.m applyCarvedBarBackground:` as
  `TGNavigationBar.m:91-93`. Likewise `images/Linen@2x.png` and
  `images/SettingsBackground@2x.png` are identical to the originals.
* `TG_ACTION_BLUE 0x0779D0` = `TGFlatActionCell.m:44`. Correct, and correctly chosen as the
  representative of the blue family.
* `TG_MESSAGE_DATE 0x232D37` = `TGTelegraphConversationMessageAssetsSource.m:915`.
* `TG_TEXT_PRIMARY 0x111111` = `TGDialogListCell.m:193`;
  `TG_TEXT_SECONDARY 0x888888` = `TGDialogListCell.m:791`.
* `TG_FOOTER_CAPTION 0x697487`, `TG_ACTION_TEXT 0x536C8C`, `TG_ATTACH_TITLE 0x62768A`,
  `TG_ATTACH_META 0x72879B`, `TG_SETTINGS_VALUE 0x356596` — all match §3, §4.2, §7.
* `TG_BADGE_STEEL 0x929FB0` = the measured centre of `DialogListUnreadBadge@2x.png`.
* Message body `rgb(20,22,23)` in `TGChatViewController.m:65-71` matches
  `TGTelegraphConversationMessageAssetsSource.m:177` exactly, including the unusual
  `colorWithRed:` form.
* The unread divider in `TGChatViewController.m:1321-1323` (`#506e8d`, white `@0.6` shadow,
  offset +1) matches `TGConversationUnreadItemView.m:35-36`.
* The dialog-list date `#337acc` and badge shadow `#8091a6` /
  highlighted `#2371c2` in `TGChatListViewController.m:318,335,337` match
  `TGDialogListCell.m:394,418,422`.
* Not tinting unread dialog-list rows is **correct**, matching shipped behaviour (§7.1).

### Defects

**D1 — The service-message plate is the wrong colour and the wrong alpha, and we have two
conflicting versions of it.**
`iTgLegacy/src/TGChatViewController.m:77-84` defines
`TGSystemPlateColour() = rgba(70, 99, 126, 0.4)` = `#46637E @ 0.40`, used for the day
divider (`:1269`), the empty-chat plate (`:3594`) and service messages (`:7703`).
`iTgLegacy/src/TGTheme.m:391-393` **separately** defines
`serviceBubbleColour` as `white 0.29 / black 0.29`. Neither is the original. The original is
the wallpaper monochrome tint at exactly `0.29`, defaulting to `#0c3259`
(`Telegraph/Telegraph/TGAppDelegate.mm:878`;
`Telegraph/Telegraph/TGTelegraphConversationMessageAssetsSource.m:1157`).
Fix: delete `TGSystemPlateColour()` and route all three call sites through
`-[TGTheme serviceBubbleColour]`, and make that return `#0c3259 @ 0.29` for the built-in
skeuomorphic style (ideally the tint of the current wallpaper when one is set, which is what
the original did).

**D2 — Bubbles are flat where the original is a gradient with a stroke.**
`TGTheme.m:192-193` gives `TG_BUBBLE_OUT 0xD3FBB1` and `TG_BUBBLE_IN 0xFBFBFB`, applied as a
plain `backgroundColor` (e.g. `TGChatViewController.m:7730,7850,7897`). The original is
`Msg_Out.png` `#e3fcc2 → #c4fa9f` with a 1px `#009405` bottom stroke, and `Msg_In.png`
`#ffffff → #f8f8f8`. Fix in order of payoff: (a) ship the two PNGs as 9-part stretchables
with the caps from §4.1 — they are 80×62 px @2x and cost nothing; failing that, (b) draw a
`CAGradientLayer` with those endpoints plus the outgoing bottom stroke. `TG_BUBBLE_IN`
should in no case be `#fbfbfb`: the original's top row is pure white.

**D3 — Selected/highlighted bubble colours are absent.**
Nothing in `iTgLegacy/src` corresponds to `Msg_In_Selected` (`#e5f3ff → #d7ecff`) or
`Msg_Out_Selected` (`#c5f79c → #99f360`), cited at
`TGTelegraphConversationMessageAssetsSource.m:675-694` and `:745-757`. Long-press selection
in our chat therefore has no bubble feedback where the original had a distinct blue/green
wash plus a separate `Msg_In_Selected_Shadow.png` layer.

**D4 — Link colour in message text is the system default, not `#004bad`.**
`iTgLegacy/src/ChatViewCell.m:21` sets `self.textView.dataDetectorTypes = UIDataDetectorTypeAll`
and never sets a link colour, so links render in UIKit's blue. The original is `#004bad`
(`TelegraphKit/TelegraphKit/TGReusableLabel.mm:225,556`) — noticeably darker and less
saturated. Fix: set the text view's `linkTextAttributes` / tint to `#004bad`.

**D5 — The avatar colour hash is wrong in a way that shows.**
`iTgLegacy/src/TGChatViewController.m:7573-7574` has the correct eight hex values, but the
original's index is `MD5("<uid><clientUserId>")[uid % 16] % 8`
(`Telegraph/Telegraph/TGInterfaceAssets.mm:22-45`) — the **logged-in user's id is part of the
hash** and group chats use a **separate four-colour** space
(`TGInterfaceAssets.mm:47-69`). Verify our derivation against those two facts; if we use a
plain `uid % 8`, every placeholder colour in the app differs from the original for the same
contact, and groups get eight colours where the original allowed four.

**D6 — The tab bar loses its gradient and its translucency.**
`iTgLegacy/src/TGTabBar.m:50` sets the `#999999` label correctly, but `TGTheme.m styleTabBar:`
returns early for the built-in skeuomorphic style and never installs a background. The
original is `TabBarBackground.png`, `#272727 → #0c0c0c` at a uniform **alpha 0.92**, with a
selection wash of `#ffffff @ 0.05` from `TabBarSelected.png`
(`Telegraph/Telegraph/TGMainTabsController.m:52-58`). A solid black bar reads noticeably
heavier than the original.

**D7 — Systemic: 167 colour literals live outside `TGTheme` across 40 files.**
(`grep -c colorWith` over `iTgLegacy/src/*.m`.) This is the same disease the original had
(§7) and is why we ended up with D1's two conflicting service plates. It is not urgent, but
every new colour should go through `TGTheme`, and the eleven-blue collapse in §7 should be
applied when files are touched. `twelve`'s `TGPresentationPallete` (175 roles) is the proof
that a fifteen-role palette is too small — our `TGTheme` currently exposes about thirty,
which is why screens keep reaching around it.

**D8 — Minor: `onlineColour` is `#778698`, which is not an online colour.**
`TGTheme.m:200` (`TG_PRESENCE_TEXT`) takes the value from
`Telegraph/Telegraph/TGContactCell.m:765`, which is a **commented-out** highlighted-subtitle
colour, not a presence colour. The original's only presence signal is the conversation
subtitle, `#e0eefd` when online versus `#c9dcf2` otherwise
(`TelegraphKit/TelegraphKit/TGConversationController.mm:1645-1646`). If we keep an online dot
(a modern affordance the original lacked), its colour is our invention and should be stated
as such rather than dressed in a miscited original value.

---

## 10. Quick reference

```
CHROME
  nav bar gradient      #769abb → #40658d, 1px bottom #0d2d53   Header_Corners.png
  nav bar flat          #547aa1                                  (midpoint)
  nav black opaque      #404040 → #1a1a1a                        HeaderBlackOpaque.png
  bar title             #ffffff   shadow #3d5c81 (0,-1)          TGViewController.mm:139,157
  subtitle online       #e0eefd                                  TGConversationController.mm:781
  subtitle other        #c9dcf2                                  TGConversationController.mm:1646
  tab bar               #272727 → #0c0c0c @ 0.92                 TabBarBackground.png
  tab label             #999999 / white                          TGMainTabsController.m:78
  bar button shadow     #042651 @ 0.3                            TGToolbarButton.m:197
  search cancel shadow  #112e5c @ 0.2                            TGSearchBar.m:38

CONTENT
  list background       #ffffff
  section header        #e4e9f0   text #8d9298   index #88929c
  linen                 #dde6ef                                  Linen.png
  settings lines        #c9d1db                                  SettingsBackground.png
  hairline              #e5e5e5
  caption               #697487   shadow #dae0e8 (0,+1)          TGChatSettingsController.m:196
  primary text          #111111                                  TGDialogListCell.m:193
  secondary text        #888888                                  TGDialogListCell.m:791
  encrypted title       #229a0a                                  TGDialogListCell.m:194
  author name (list)    #345f8f                                  TGDialogListCell.m:196
  action preview        #536c8c                                  TGDialogListCell.m:792
  date (list)           #337acc                                  TGDialogListCell.m:394
  badge                 #929fb0   shadow #8091a6   hl #2371c2
  cell highlight        #e9eff5   stripes #d5dee5                TGContactCell.m:750-757
  delete-label shadow   #a30f0a @ 0.2                            TGDialogListCell.m:456

CONVERSATION
  bubble in             #ffffff → #f8f8f8                        Msg_In.png    caps 20/15
  bubble in selected    #e5f3ff → #d7ecff                        Msg_In_Selected.png
  bubble out            #e3fcc2 → #c4fa9f, edge #009405          Msg_Out.png   caps 15/15
  bubble out selected   #c5f79c → #99f360, edge #009005          Msg_Out_Selected.png
  body text             #141617   no shadow                      ...AssetsSource.m:177,182
  timestamp             #232d37   no shadow                      ...AssetsSource.m:915,920
  author name           #4d688c   Helvetica-Bold 13              ...AssetsSource.m:342,325
  link                  #004bad                                  TGReusableLabel.mm:225
  attach title/meta     #62768a / #72879b                        ...AssetsSource.m:195,203
  fwd title/name in     #0e7acd / #0e7acd                        ...AssetsSource.m:243,259
  fwd title/name out    #3a8e26 / #169600                        ...AssetsSource.m:251,267
  unread row wash       #003871 @ 0.07                           ...AssetsSource.m:891
  service plate         wallpaper tint @ 0.29, default #0c3259   ...AssetsSource.m:1157, TGAppDelegate.mm:878
  upload chrome         tint @ 0.4, shadow tint @ 0.45           ...AssetsSource.m:422-423
  unread divider text   #506e8d   shadow #ffffff @ 0.6           TGConversationUnreadItemView.m:35
  input placeholder     #9da7b3                                  TGConversationController.mm:991
  send disabled         #ceffb0 (4in) / #bbffb2 (3.5in)          TGConversationController.mm:1022

IDENTITY (avatar placeholders, MD5("<uid><clientId>")[uid%16] % 8)
  #ee4928 #41a903 #e09602 #0f94ed #8f3bf7 #fc4380 #00a1c4 #eb7002   TGInterfaceAssets.mm:107-114
  groups: separate 4-colour space, hashed on group id alone         TGInterfaceAssets.mm:47-69
```

---

## 11. Genuinely open questions

* **Does the wallpaper tint change the bubbles?** It demonstrably drives the service plate
  and upload chrome (§6), and `TGTelegraphConversationCompanion.mm:4552` branches on
  `monochromeColor != -1`, but I did not trace what that branch changes. If it swaps bubble
  assets, our flat colours are wrong in a second way.
* **The per-wallpaper tint table.** Only the default `0x0c3259` is a literal
  (`TGAppDelegate.mm:878`, `TGWallpaperStoreController.m:492,618`). Other wallpapers read
  their tint from a server-supplied `"color"` key (`TGWallpaperStoreController.m:459,584`),
  so the built-in set's tints are not recoverable from source. If we ship more than one
  wallpaper we will have to choose tints ourselves.
* **`#e9eff5` cell highlight scope.** `TGContactCell.m:750` uses it with `#d5dee5` stripes,
  but grouped settings cells use `groupedCell*Highlighted` PNGs instead
  (`TGInterfaceAssets.h:59-66`). Which highlight a given list uses is per-cell-class and I
  did not enumerate all of them.
* **`Footer.png`.** `footerBackground` is exposed (`TGInterfaceAssets.h:22`) but I did not
  find its consumer; its measured colour is not recorded here.

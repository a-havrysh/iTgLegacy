# TGDialogListMessageSearchCell — original study

## 0. The assigned name is a dead file

`TGDialogListMessageSearchCell` exists in the original tree, but it is an empty Xcode template
stub. The whole implementation is:

- `TelegraphKit/TelegraphKit/TGDialogListMessageSearchCell.h:11` — `@interface TGDialogListMessageSearchCell : UITableViewCell` with **no** properties or methods.
- `TelegraphKit/TelegraphKit/TGDialogListMessageSearchCell.m:5-19` — the default `initWithStyle:reuseIdentifier:` and `setSelected:animated:` with `// Initialization code` / `// Configure the view for the selected state` comments left in place.

It is compiled (`TelegraphKit/TelegraphKit.xcodeproj/project.pbxproj:1519`, `:1737`) but is never
instantiated, imported or referenced by any other source file in the snapshot — the only hits for
the name outside its own two files are the four pbxproj lines. It is dead weight left from an
abandoned idea.

**The real class this study documents is `TGDialogListSearchCell`**
(`TelegraphKit/TelegraphKit/TGDialogListSearchCell.h`, `.m`, 275 lines). Where the search results
list needs to show a *message* rather than a peer, the original does not use a dedicated cell at
all: it reuses the normal 73pt dialog-list cell `TGDialogListCell`
(`TGDialogListController.mm:1358-1380`, `[self prepareCell:… isSearch:true]`). That fact is itself
part of the design and is covered in §3.

All paths below are relative to
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
unless stated otherwise.

---

## 1. What the component is for

`TGDialogListSearchCell` is the **compact peer row** of the chat-list search results table. It is
51pt tall against the dialog list's 73pt, holds a 40pt avatar instead of a 56pt one, and it exists
to do one job the tall cell cannot: render a person's name as **two independently-styled runs**,
so the half of the name that the user's sort order keys on is bold and the other half is regular.
No date, no message preview, no unread badge, no swipe-to-delete. It is a picker row, not a
conversation row.

It is used only from `TGDialogListController` and only when the search scope segment is on
"Conversations" (`TGDialogListController.mm:1299`, scope titles at `:528` are
`@[@"Conversations", @"Messages"]`).

---

## 2. Public surface

`TGDialogListSearchCell.h:13-35`:

```
@property (nonatomic, strong) id<TGDialogListCellAssetsSource> assetsSource;   // :15
@property (nonatomic) int64_t conversationId;                                  // :17
@property (nonatomic, strong) NSString *titleTextFirst;                        // :19
@property (nonatomic, strong) NSString *titleTextSecond;                       // :20
@property (nonatomic, strong) NSString *subtitleText;                          // :21
@property (nonatomic, strong) NSString *avatarUrl;                             // :23
@property (nonatomic) bool isChat;                                             // :25
@property (nonatomic) bool isEncrypted;                                        // :26
@property (nonatomic) int encryptedUserId;                                     // :27
- (void)resetView:(bool)animated;                                              // :29
- (void)setBoldMode:(int)index;                                                // :31
- (id)initWithStyle:…reuseIdentifier:…assetsSource:…;                          // :33
```

The setters are plain synthesized ones (`.m:23-41`); **nothing happens until `resetView:` is
called**. The controller sets every property and then calls `[cell resetView:false]`
(`TGDialogListController.mm:1353`). This is the same "dumb properties + one commit method" shape
the whole 2013 codebase uses, and it exists so a cell can be reconfigured many times per scroll
frame with only one layout pass.

`assetsSource` is injected at init (`.m:59`) and comes from
`[_dialogListCompanion dialogListCellAssetsSource]` (`TGDialogListController.mm:1305`), which in
the app is the `TGInterfaceAssets` singleton.

---

## 3. Where it sits in the search table

`- tableView:heightForRowAtIndexPath:` (`TGDialogListController.mm:1118-1131`):

```
1129:  return _searchBar.selectedScopeButtonIndex == 0 ? 51 : 73;
```

So the **whole search table** switches row height with the scope segment: 51 for Conversations,
73 for Messages. There is no mixed-height table and there are no section headers — the search
results are one flat array `_searchResults` (`:1114`) holding `TGConversation`, `TGUser` and
`TGMessage` objects intermixed.

Cell selection (`:1078-1097`) dispatches on the *model* class, not the cell class:
`TGConversation` → `searchResultSelectedConversation:` (or
`searchResultSelectedConversation:atMessageId:` when the conversation carries a
`searchMessageId` in `additionalProperties`, `:1085-1086`), `TGUser` →
`searchResultSelectedUser:`, `TGMessage` → `searchResultSelectedMessage:`. The cell itself has no
tap handling, no `watcherHandle`, and no editing support — unlike `TGDialogListCell`, which gets
`cell.watcherHandle` and `enableEditing` at `:1257-1258`.

In "Messages" scope the controller falls through to `TGDialogListCell` at 73pt
(`:1356-1381`). **There is no message-specific search cell in the original at all.** The tall
dialog cell is simply fed the matched conversation with `isSearch:true`.

---

## 4. Construction — every metric and colour

`initWithStyle:reuseIdentifier:assetsSource:` (`.m:43-95`).

### 4.1 Backgrounds

```
.m:50   cellImage         = [UIImage imageNamed:@"Cell102.png"]
.m:54   selectedCellImage = [UIImage imageNamed:@"CellHighlighted102.png"]
.m:56   self.backgroundView         = [[UIImageView alloc] initWithImage:cellImage]
.m:57   self.selectedBackgroundView = [[UIImageView alloc] initWithImage:selectedCellImage]
```

Both are cached in file-static `UIImage *` on first use (`.m:48-54`) — not `dispatch_once`, just a
nil check, which is fine because cells are only ever created on the main thread.

I decoded both PNGs from `Telegraph/Telegraph/Resources/`:

| asset | pixels | points | content |
|---|---|---|---|
| `Cell102@2x.png` | 2 × 102 | 1 × **51** | rows 0-99 pure `#FFFFFF`; rows 100-101 `#E0E0E0` |
| `CellHighlighted102@2x.png` | 2 × 104 | 1 × **52** | rows 0-1 `#0085E5`; rows 2-101 a vertical gradient `#26A4F9` → `#1477DA`; rows 102-103 `#0060BF` / `#005FBE` |

This is the key to the whole cell and it explains three otherwise-mysterious numbers:

- **51pt row height is the asset height.** The row is 51 because `Cell102` is 51pt tall: 50pt of
  white plus a **1pt `#E0E0E0` separator baked into the bottom of the background image**. The
  table draws no separator of its own; the separator is artwork. Everything vertical in the cell
  is centred in the *full* 51pt, not in the 50pt above the line (see §6).
- **The normal background is 1pt wide** and is stretched horizontally by `UIImageView`'s default
  `UIViewContentModeScaleToFill`. It is a pure vertical strip, so stretching is lossless. It is
  *not* passed through `stretchableImageWithLeftCapWidth:` — compare `TGDialogListCell`'s
  background at `TGDialogListController.mm:1137-1138`, which is.
- **The highlighted background is 1pt taller than the row**, and that extra point is why
  `layoutSubviews` and both `setSelected:`/`setHighlighted:` shove it up by one:

```
.m:174-177 / :224-227 / :239-242
    CGRect frame = self.selectedBackgroundView.frame;
    frame.origin.y = true ? -1 : 0;
    frame.size.height = self.frame.size.height + (true ? 1 : 0);
```

The `true ? … : …` is a debug switch that was left permanently on. The effect: the 52pt blue plate
sits from y = −1 to y = 51. Its top hairline `#0085E5` lands on the *previous* row's baked
separator and its bottom hairline `#0060BF` covers *this* row's baked separator. Selecting a row
therefore replaces both of its separator lines with darker blue rules, which is exactly the 2013
look. Get this wrong by one point and a grey hairline shows through the blue.

### 4.2 `adjustOrdering` — the reason highlighting looks right

`.m:248-273`, called from both `setSelected:` and `setHighlighted:` when the new value is `true`
(`.m:229`, `.m:244`).

The method walks `self.superview.subviews`, finds the index of the last `UITableViewCell`, and if
`self` is below it, does `[self.superview insertSubview:self atIndex:maxCellIndex]`. In plain
terms: **the highlighted cell is raised to be the topmost cell in the table.** Without it, the 1pt
of blue that overhangs above y = 0 would be drawn underneath the cell above and clipped away.
UITableView gives no ordering guarantee among cell subviews, so this is not optional.

### 4.3 Labels

All three are `TGLabel` (a `UILabel` subclass with reuse support and vertical alignment,
`TGLabel.h:19`), all with `contentMode = UIViewContentModeLeft`.

| label | font | colour (init) | highlighted | background | line |
|---|---|---|---|---|---|
| `titleLabelFirst` | `systemFontOfSize:19` | `0x000000` | `0xffffff` | `[UIColor whiteColor]` | `.m:61-67` |
| `titleLabelSecond` | `boldSystemFontOfSize:19` | `0x000000` | `0xffffff` | `[UIColor whiteColor]` | `.m:69-75` |
| `subtitleLabel` | `systemFontOfSize:13` | `0x808080` | `0xffffff` | `[UIColor whiteColor]` | `.m:77-83` |

Two things to note.

1. The `0x000000` title colour set here **never survives**: `resetView:` overwrites it on every
   configure (`.m:142-143`) with `0x111111`, or `0x229a0a` for secret chats. So the shipped title
   colour is `#111111`, and `#000000` is dead.
2. The label backgrounds are **opaque white**, not clear. On a 4S this is deliberate: an opaque
   label is a single blit, a clear one forces blending against the background image for every
   pixel of the row on every scroll frame. It is safe here only because `Cell102` is pure white
   everywhere the labels sit (rows 0-99). The white also does real layout work — see §7.

### 4.4 Avatar

```
.m:85  _avatarView = [[TGRemoteImageView alloc] initWithFrame:CGRectMake(5, 5, 40, 40)];
.m:86  _avatarView.fadeTransition = true;
```

40 × 40 at (5, 5) inside a 51pt row: 5pt above, **6pt below**. The asymmetry is intentional — the
bottom 1pt is the baked separator, so the avatar is centred in the 50pt of white above the line,
not in the 51pt box.

Images are loaded through the registered processor named `avatar40`
(`Telegraph/Telegraph/TGTelegraph.mm:486-489`):

```
return TGScaleAndRoundCorners(source, CGSizeMake(40, 40), CGSizeZero, 4, nil, false, nil);
```

**Corner radius 4, rounded into the bitmap.** There is no `layer.cornerRadius` and no
`clipsToBounds` anywhere in this cell — 2013 avoided both because offscreen-rendered rounded
corners on an iPhone 4S cost roughly a frame per visible cell.

### 4.5 `groupChatIcon` — added, never laid out

```
.m:89-92  _groupChatIcon = [[UIImageView alloc] init];
          _groupChatIcon.image           = [_assetsSource dialogListGroupChatIcon];
          _groupChatIcon.highlightedImage = [_assetsSource dialogListGroupChatIconHighlighted];
          [self.contentView addSubview:_groupChatIcon];
```

The images resolve to `DialogListGroupChatIcon.png` / `DialogListGroupChatIcon_Highlighted.png`
(`Telegraph/Telegraph/TGInterfaceAssets.mm:215-229`), which are 36 × 24 px = 18 × 12 pt.

**But `layoutSubviews` never assigns it a frame** (`.m:170-216` — search for `_groupChatIcon`:
zero hits). `[[UIImageView alloc] init]` gives `CGRectZero`, so the icon is a zero-size view that
draws nothing, forever. This is dead code, and it means **the 2013 search row shows no group
badge next to a group's name.** Do not add one to be helpful; the original did not have one.

---

## 5. `resetView:` — the configure step

`.m:116-168`.

### 5.1 The two-run title, and the empty-second-run rule

```
.m:118-131
if (_titleTextSecond == nil || _titleTextSecond.length == 0) {
    _titleLabelFirst.text = nil;
    _titleLabelFirst.hidden = true;
    _titleLabelSecond.text = _titleTextFirst;      // <- note: FIRST text into SECOND label
} else {
    _titleLabelFirst.text = _titleTextFirst;
    _titleLabelFirst.hidden = false;
    _titleLabelSecond.text = _titleTextSecond;
}
```

This is the single most important behaviour in the cell and it is easy to get backwards. When
there is no second run, the text is put into `titleLabelSecond` — the **bold** label — and the
first label is hidden. So:

- Two-part name (first + last): first name regular 19, last name bold 19.
- One-part name, or a group/channel title: **entirely bold 19**.

A group title, a mononym, and a user with only a last name all render fully bold. There is never a
row whose title is entirely regular weight, under the default bold mode.

### 5.2 Title colour and secret chats

```
.m:138-143  titleColor          = UIColorRGB(0x111111);
            encryptedTitleColor = UIColorRGB(0x229a0a);
            _titleLabelFirst.textColor  = _isEncrypted ? encryptedTitleColor : titleColor;
            _titleLabelSecond.textColor = _isEncrypted ? encryptedTitleColor : titleColor;
```

Secret-chat rows have a **green `#229A0A`** title, both runs. Cached in a `dispatch_once`
(`.m:135`). Highlighted colour stays white in both cases (set once at init, never touched here),
so a selected secret chat is white-on-blue like everything else.

### 5.3 Subtitle

```
.m:145-146  _subtitleLabel.text   = _subtitleText;
            _subtitleLabel.hidden = _subtitleText == nil || _subtitleText.length == 0;
```

**In shipped v1.1 the subtitle is always nil.** Both configure branches in the controller set it
explicitly to nil — `cell.subtitleText = nil` at `TGDialogListController.mm:1326` (conversation)
and `:1348` (user). So the one-line centred layout is the only layout that ever appeared on
screen; the two-line branch of `layoutSubviews` is reachable code that never ran. The obvious
intent was a `@username` second line, and that is exactly what the fork later filled in (§9).

### 5.4 Avatar loading, and the fade durations

```
.m:148  _avatarView.hidden = false;
.m:150-163  if (_avatarUrl != nil) {
                _avatarView.fadeTransitionDuration = animated ? 0.14 : 0.3;
                if (![_avatarUrl isEqualToString:_avatarView.currentUrl]) {
                    if (animated)
                        [_avatarView loadImage:_avatarUrl filter:@"avatar40"
                                   placeholder:(currentImage ?: (_isChat ? smallGroupAvatarPlaceholderGeneric
                                                                         : smallAvatarPlaceholderGeneric))
                                     forceFade:true];
                    else
                        [_avatarView loadImage:_avatarUrl filter:@"avatar40"
                                   placeholder:(_isChat ? … : …)];
                }
            }
```

Three details worth copying:

- **The URL equality guard** (`.m:153`) is what makes reuse cheap: re-configuring a recycled cell
  onto the same peer does not restart the load or re-flash the placeholder.
- **The fade duration is inverted from intuition**: `animated == true` gives the *shorter* 0.14s,
  `false` gives 0.3s (`.m:152`). `animated` here means "this configure is happening inside a
  table animation", where a long crossfade would smear.
- When animating, the **current image** is used as the placeholder if there is one
  (`.m:157-158`), so the avatar crossfades old→new instead of old→grey→new.

Search rows always call `resetView:false` (`TGDialogListController.mm:1353`), so in practice the
0.3s duration is the one users saw.

### 5.5 The no-URL path — coloured placeholder plates

```
.m:166  [_avatarView loadImage:(_isChat ? [_assetsSource smallGroupAvatarPlaceholder:_conversationId]
                                        : [_assetsSource smallAvatarPlaceholder:
                                              _isEncrypted ? _encryptedUserId : (int)_conversationId])];
```

Note the id substitution: a secret chat colours its placeholder by the **peer's user id**, not by
the negative secret-chat conversation id, so the same person gets the same colour in the normal
chat and the secret chat.

`TGInterfaceAssets.mm:314-344`:

- `smallAvatarPlaceholder:uid` — `uid <= 0` → generic; `uid == 333000` (Telegram service account)
  → `SmallAvatarSystem.png`; otherwise `SmallAvatar%d.png` with `colorIndexForUid(uid) + 1`, over
  **8** colours (`:22-24`).
- `smallGroupAvatarPlaceholder:` — `DialogListGroupAvatarSmall%d.png`, **4** colours (`:47-49`).
- `smallAvatarPlaceholderGeneric` — `DialogListAvatarPlaceholderSmall.png` (`:326-332`);
  `smallGroupAvatarPlaceholderGeneric` returns the same generic image (`:341-344`).

The colour index is memoised in a `std::map<int64_t,int>` under a lock (`:28-31`) so a peer's
colour is stable for the process lifetime.

The assets live in `Telegraph/Telegraph/Resources/Placeholders/` (`SmallAvatar1@2x.png` …
`SmallAvatar8@2x.png`, `SmallAvatarSystem@2x.png`, `DialogListGroupAvatarSmall1..4@2x.png`), each
**80 × 80 px = 40 × 40 pt** — exactly the avatar box, pre-rounded, no scaling at draw time.

**These are silhouette-on-colour plates, not lettered monograms.** 2013 Telegram had no initials
avatars anywhere; the letter avatar arrives later (see §9).

---

## 6. `layoutSubviews` — the geometry

`.m:170-216`. `leftPadding` is a hard `0` (`.m:181`), so it drops out of everything below; it is a
leftover hook for an iPad master column.

```
.m:183  int avatarWidth = 5 + 40;                 // = 45, the avatar's right edge
.m:185  titleSize  = (width - 45 - 9 - 5, titleLabelFirst.font.lineHeight)
.m:187  subtitleSize = (width - 45 - 9 - 5, subtitleLabel.font.lineHeight)
.m:189  avatarFrame = (5, 5, 40, 40)              // reassigned only if changed
```

So the **text column starts at x = 45 + 9 = 54** and its right margin is **5**. On a 320pt-wide
table that is a 261pt text column. Both title runs and the subtitle get that same full width as
their frame width — the cell never measures how much it actually needs.

The 9pt gap between the 40pt avatar and the text is worth naming: with the avatar at x = 5, the
text baseline column at 54 lines up with nothing else in the app — the 73pt `TGDialogListCell`
uses a different inset. These are two independently tuned rows, not one system.

Vertical centring:

```
.m:196-205
if (_subtitleLabel.hidden)
    titleLabelsY = (int)((int)((viewSize.height - titleSizeGeneric.height) / 2) - 1);
else {
    titleLabelsY = (int)((viewSize.height - titleSizeGeneric.height - subtitleSize.height - 1) / 2);
    _subtitleLabel.frame = CGRectMake(45 + 9 + 1, titleLabelsY + titleSizeGeneric.height,
                                      subtitleSize.width, subtitleSize.height);
}
```

- One-line case: centred in the contentView height, then nudged **up 1pt**. That −1 is the
  correction for the 1pt separator baked into the bottom of `Cell102`: without it the text sits
  visually low. With a 19pt system font (`lineHeight` ≈ 23 on iOS 6) and a 51pt content height,
  `titleLabelsY = (int)(14 - 1) = 13`.
- Two-line case: title + subtitle + a **1pt gap** as a block, centred, no −1 nudge. The subtitle
  is indented **one extra point** (`45 + 9 + 1 = 55`, `.m:204`) relative to the title's 54 — an
  optical correction for the 13pt regular font's smaller left side bearing.
- Everything is truncated to `int`. Half-point text origins blur on the 4S; the original rounds
  down everywhere.

The horizontal split of the two title runs:

```
.m:207-215
if (!_titleLabelFirst.hidden) {
    _titleLabelFirst.frame  = (54, y, titleSize.width, titleSize.height);
    _titleLabelSecond.frame = (54 + 5 + (int)[_titleLabelFirst.text sizeWithFont:…].width,
                               y, titleSize.width, titleSize.height);
} else {
    _titleLabelSecond.frame = (54, y, titleSize.width, titleSize.height);
}
```

**The gap between the runs is 5pt**, not a space character — the two labels are laid out
independently and the second is positioned by measuring the first with `sizeWithFont:`.

---

## 7. Behaviour with unusual content

This is where the design shows its age, and the details matter because real names hit them.

**Long first name.** Both labels are given the *full* `titleSize.width`, so they overlap. The
first label starts at 54 and can run to the right margin; the second starts at
`54 + width(first) + 5` and also claims the full width, running off the right edge of the cell.
Because both labels have **opaque white backgrounds** (`.m:66`, `.m:74`), the second label — added
to the view hierarchy after the first (`.m:67` then `.m:75`, so drawn on top) — **paints over the
tail of the first**. The opaque background is therefore load-bearing: it is the truncation
mechanism. A long first name is visually cut off by the last name overwriting it, with no ellipsis
and no gap.

**Long last name.** The second label extends past the cell's right edge and is clipped by
`contentView` (UITableViewCell content clips by default). Hard cut, no ellipsis. If the first name
alone fills the column, the last name starts off-screen and is entirely invisible.

**Both names very long.** Same as above: the row shows a truncated first name and nothing else
useful. There is no size-to-fit, no minimum font scale, no `lineBreakMode` set anywhere in the
cell. The 2013 answer to "the name doesn't fit" was "the name doesn't fit".

**Empty `titleTextFirst` with empty `titleTextSecond`.** `titleLabelSecond.text = nil`, first
hidden — the row is a bare avatar with no text. The controller can produce this: the conversation
branch reads `dialogListData[@"title"]` with no fallback (`TGDialogListController.mm:1315`), and
the user branch with both names empty yields `titleTextFirst = user.lastName` = empty
(`:1337-1341`). There is no "Deleted Account" placeholder in 2013.

**Missing avatar URL.** Covered in §5.5 — a deterministic coloured plate, never a blank box.

**A `TGMessage` in the results while scope is 0.** `cellForRow` returns `nil`
(`TGDialogListController.mm:1384`), which crashes UITableView. In practice the search backend
never returns messages in scope 0, so this is latent, not observed.

**Reuse leak — a genuine original bug.** `isChat` is set to `true` in the conversation branch
(`:1318-1321`) but **never set back to `false`** for a non-group conversation; only the user
branch sets `cell.isChat = false` (`:1334`). Compare `isEncrypted`/`encryptedUserId`, which *are*
defensively reset at `:1308-1309`. So a private conversation result that recycles a cell last used
for a group, and that has no avatar URL, gets a **group** colour plate
(`smallGroupAvatarPlaceholder:`, 4 colours) instead of a user one (8 colours). Visible as a
wrong-coloured placeholder that changes when you scroll it off and back. Reproduce it and you will
see it; it is not worth reproducing in our port.

**No `prepareForReuse`.** The cell does not implement it. All resetting is the controller's job
via property assignment + `resetView:`, which is why the `isChat` omission bites.

---

## 8. `setBoldMode:` — designed, never wired

`.m:97-114`:

| index | first label | second label |
|---|---|---|
| 0 | regular 19 | **bold 19** |
| 1 | **bold 19** | regular 19 |
| anything else | regular 19 | regular 19 |

`setBoldMode:` has **no caller anywhere in the snapshot** — the only hits are the declaration
(`.h:31`) and the definition. Mode 0 is the init-time state, so shipped behaviour is always mode 0:
last name bold.

The intent is unmistakable: mode 1 is for the "Last, First" display/sort order, so that whichever
name the list is *sorted by* is the emphasised one. The feature was cut before shipping. The
modern client implements exactly this idea (§9), which is good evidence about what it was for.

---

## 9. What became of it

### 9.1 `twelve` — the same class, extended in place

`/Users/alexanderhavrysh/Git/iOS/twelve/legacy/TelegraphKit/TGDialogListSearchCell.m`, 408 lines
against the original's 275. Same class, same `resetView:`/`setBoldMode:` shape, thirteen years of
accretion:

- Header gains `isSavedMessages`, `isVerified`, `hasExplicitContent`, `unreadCount`,
  `presentation` (theming), `channelDisposable`, and `attributedSubtitleText` replacing the plain
  `NSString *subtitleText` (`twelve/legacy/TelegraphKit/TGDialogListSearchCell.h:24-40`). The
  attributed subtitle is the `@username` line with the matched substring highlighted — the feature
  the original's dead subtitle branch was scaffolding for.
- Preview/peek support: `avatarSnapshotView`, `avatarFrame`, `textContentFrame` (`.h:48-50`),
  used by the 3D-Touch peek path in `TGDialogListController.mm:4175-4187`.
- Geometry moved for the flat era: **avatar x 5 → 14**, text column **54 → 66**
  (`avatarWidth + 21`), and the separator became a real `CALayer` at x = 65 with
  `TGScreenPixel` height instead of being baked into a background PNG
  (`twelve/…SearchCell.m:244-247`, `:271-292`).
- Two-line mode stopped centring: with a subtitle, the title is pinned at `y = 4 + TGScreenPixel`
  and the subtitle at a fixed `y = 26` (`:308`, `:326`).
- `TGRemoteImageView` → `TGLetteredAvatarView`: coloured plates became **initials**.
- The dead `groupChatIcon` is gone, replaced by an unread badge and a verified icon.
- **The 5pt gap between the two title runs survived unchanged** (`:293`, `:313`).

Note also that in `twelve` the *message* search results grew their own controllers
(`Telegraph/TGChatSearchController.m`, `TGHashtagSearchController.m`) — and both still use
`TGDialogListCell` with the reuse identifier string `@"TGDialogListSearchCell"`
(`TGChatSearchController.m:370-375`). The 2013 decision to render message hits with the tall
dialog cell was never reversed.

### 9.2 Telegram-iOS — `ContactsPeerItem`

`submodules/ContactsPeerItem/Sources/ContactsPeerItem.swift`.

What survived:

- **The two-run bold name is still there, thirteen years on.** `:958-969`:
  ```
  string.append(NSAttributedString(string: firstName, font: item.sortOrder == .firstLast ? titleBoldFont : titleFont, …))
  string.append(NSAttributedString(string: " ", font: titleFont, …))
  string.append(NSAttributedString(string: lastName,  font: item.sortOrder == .firstLast ? titleFont : titleBoldFont, …))
  ```
  This is **`setBoldMode:` finally shipped** — the emphasis follows `item.sortOrder`, exactly
  modes 0 and 1. Note the polarity flipped: modern `.firstLast` bolds the *first* name (2013's
  mode 1); 2013's shipped default bolded the last.
- The "one name → bold" rule survived verbatim (`:971-976`): a lone first name, a lone last name,
  a group title, a channel title and the deleted-account string are all `titleBoldFont`.
- The **40pt avatar** survived (`:807`, clamped by the accessibility font scale) and the **13pt
  status font** survived (`:802`).

What changed, and why:

- **Two labels became one attributed string** (`:959-970`, a single `TextNode`). This is the fix
  for §7: with one string, truncation is a single `.end` truncation of the whole name, so a long
  first name gets an ellipsis instead of being painted over by the last name. Forced by the bug,
  not by taste. The **5pt gap became a literal space character** (`:963`).
- Text inset **54 → 65** (`:812`, `leftInset = 65.0 + params.leftInset`), matching `twelve`'s 66.
  The 2013 54 is a pre-flat number.
- The row no longer has a fixed height or a background PNG; height falls out of the text layout
  and theming is a `PresentationTheme`.
- Everything in the accreted middle — verified badge, premium status, selection checkmarks, ad
  icon, thread mode, saved-messages aliasing — is new feature, not new taste.

The honest summary: the *idea* of this cell (compact peer row, 40pt avatar, mixed-weight name,
13pt grey subtitle) is completely intact in 2026. The *implementation* was rewritten because two
overlapping opaque labels cannot truncate.

---

## 10. Our port

Ours is `TGSearchResultCell`, a file-private class inside
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGSearchViewController.m:170-315`, with constants at
`:13-26` and the configure code at `:2525-2564`.

**The good news, briefly:** the port is close and clearly derived from the right original. Row
height 51 (`:14`), avatar 40 at (5, 5) (`:13`, `:15-16`, `:233`), text left 54 (`:17`), right
margin 5 (`:18`), fonts 19 / bold 19 / 13 (`:195`, `:205`, `:213`), title `#111111` (`:198`),
subtitle `#808080` (`:216`), white highlighted text (`:200`, `:207`, `:218`), the same
`Cell102.png` / `CellHighlighted102.png` backgrounds (`:185-190`), the `−1 / +1`
selectedBackgroundView shove (`:263-268`), the `(int)` rounding and the `−1` one-line nudge
(`:289`), the `+1` subtitle indent (`:292`), the 5pt inter-run gap (`:303`), and — importantly —
the correct bold rule: with no second run, `titleLabel` is switched to **bold** (`:247`) rather
than the text being moved into the other label. Same visual result, cleaner. Good work.

Differences a user could see, in rough order of how much they matter:

1. **We never raise the highlighted cell — `adjustOrdering` is missing.**
   Original `.m:229`, `:244`, `:248-273`; ours has no equivalent (grep for `adjustOrdering` in
   `iTgLegacy/src` returns nothing). We do apply the `−1 / +52` frame (`:263-268`), so we pay for
   the overhang without getting it: the 1pt `#0085E5` top hairline of `CellHighlighted102` is
   drawn under whichever sibling cell happens to be above us in the subview list, and the previous
   row's grey `#E0E0E0` separator shows through the top of the blue plate. **Fix:** port
   `adjustOrdering` verbatim and call it from `setSelected:animated:` and
   `setHighlighted:animated:` when the flag is true.

2. **No secret-chat green title.** Original `.m:139`, `:142-143` — `#229A0A` on both runs when
   `isEncrypted`. Our cell has no `isEncrypted` notion at all (`:170-177`), and the configure
   block at `:2531-2546` never reads any secret-chat flag from the row dictionary. Secret chats
   render with the normal `#111111` title. **Fix:** add a `BOOL isEncrypted` to
   `TGSearchResultCell`, set both label colours to `#229A0A` when set, and populate it from the
   row dictionary.

3. **We invented a date label the original does not have.** `:221-230`, `:275-281`, `:309-312`,
   populated at `:2546`. The 51pt peer row in 2013 had **no date and no right-hand column** — the
   only three subviews were avatar, two title labels and a subtitle
   (original `.m:11-17`, `layoutSubviews` `.m:170-216`). Worse, it is not free: when a date is
   present we subtract `dateWidth + 4 + 4` from the text column (`:279`), so the name gets a
   narrower column than the original's flat `width − 59`, and long names truncate earlier. If this
   is a deliberate modern-interaction addition, keep it but say so; if it is drift, delete it and
   restore `textWidth = viewSize.width - 54 - 5`.

4. **Label backgrounds are `clearColor`, the original's are opaque `whiteColor`.**
   Ours `:194`, `:204`, `:212`, `:222`; original `.m:66`, `:74`, `:82`. Two consequences on a 4S.
   (a) Performance: four blended labels per row across ten visible rows, on a device where the
   2013 code went out of its way to keep every label opaque. (b) Behaviour: in the original the
   opaque white of `titleLabelSecond` is what *hides* an over-long first name (§7). We get the
   same visual outcome by a different route — we clamp `firstWidth` to `textWidth` (`:299-301`)
   and give the second run whatever is left, flooring at 0 (`:304-306`) — which is arguably
   better and does not depend on paint order. So the clamp is fine; the clear background is
   still a perf regression worth reversing in the non-flat theme, where the plate is known to be
   `#FFFFFF`. (In flat mode, keep clear.)

5. **Rounded corners are done with `layer.cornerRadius` + `clipsToBounds`, not baked into the
   bitmap.** Ours `:234-235`; the original bakes radius 4 into the image via the `avatar40`
   processor (`Telegraph/Telegraph/TGTelegraph.mm:488`). The radius value (4) is right. The
   mechanism forces an offscreen render pass per avatar per frame on an iPhone 4S — precisely
   what the original's image-processor pipeline exists to avoid. **Fix:** round in
   `avatarForChat:…` / `TGIcons` when the bitmap is produced and cached, and drop
   `cornerRadius`/`clipsToBounds`.

6. **Placeholder avatars are lettered monograms; the original's are silhouette colour plates.**
   Ours `:2479-2482` and `:2550-2552` call `[TGIcons avatarWithInitials:…]`. The original uses
   `SmallAvatar1..8@2x.png` / `DialogListGroupAvatarSmall1..4@2x.png` /
   `DialogListAvatarPlaceholderSmall@2x.png`, all 80 × 80 px, chosen by
   `colorIndexForUid` (8 colours) or `colorIndexForGroupId` (4 colours)
   (`TGInterfaceAssets.mm:314-344`, `:22-24`, `:47-49`). Lettered avatars are a **later** Telegram
   idea — they show up in `twelve` as `TGLetteredAvatarView` and are absent from 2013 entirely.
   Our `images/` directory does not contain the `SmallAvatar*` family at all (only
   `DialogListAvatarPlaceholder@2x.png`, `DialogListAvatarSystem.png`,
   `DialogListAvatarStroke.png`). This is the single most visible period-inaccuracy in the row.
   **Fix, if we want 2013:** copy `Resources/Placeholders/SmallAvatar1..8@2x.png`,
   `SmallAvatarSystem@2x.png` and `DialogListGroupAvatarSmall1..4@2x.png` across, and port
   `colorIndexForUid`. This is a project-wide decision, not a decision for this cell — flag it
   rather than changing it here.

7. **`[TGIcons avatarWithInitials:… colourId:]` is passed `hashtagRow.hash` for hashtag rows**
   (`:2552`) and the chat/user id otherwise (`:2534-2536`, `:2557`). The original's colour key for
   a secret chat is deliberately the **peer user id**, not the conversation id
   (`.m:166`, `_isEncrypted ? _encryptedUserId : (int)_conversationId`), so the same person keeps
   one colour across their normal and secret chats. We do not make that distinction. Minor, but
   it is a visible colour flip on the same face.

8. **The group badge: we correctly have none.** Worth stating explicitly so nobody "fixes" it —
   the original allocates a `groupChatIcon` (`.m:89-92`) but never frames it, so it is invisible.
   Our omission matches shipped 2013 behaviour exactly.

9. **`setNeedsLayout` on every configure** (`:2521`, `:2553`, `:2563`) versus the original's
   `resetView:` which relies on the frame-change-driven layout pass. Harmless — the layout is
   cheap — but note the original's `if (!CGRectEqualToRect(_avatarView.frame, avatarFrame))` guard
   (`.m:190`) which we drop (`:271`). Also harmless; `UIView` compares frames itself.

10. **`reloadData` on every avatar download** (`:2475`). Not a fidelity issue and out of scope for
    this study, but on a 4S mid-scroll it will stutter; the original updates only the one
    `TGRemoteImageView` via its fade transition.

11. **Section headers.** Ours has sections with a 25pt header (`kSearchSectionHeight`, `:19`) and a
    per-section messages flag (`:2485-2493`). The original search table is **flat, one section, no
    headers** (`TGDialogListController.mm:1106-1116`), with the 51/73 height switch driven by the
    scope segment rather than by section (`:1129`). That is a deliberate interaction-model
    upgrade on our side (modern Telegram does group search results), so keep it — but it means our
    row is living in a layout the 51pt cell was not designed for, and the section header's own
    styling is not covered by this cell's original.

---

## 11. Rebuild checklist

If you had to rebuild the 2013 row from scratch, these are the numbers:

- Row height **51**. Background `Cell102.png` (1 × 51pt, white with a 1pt `#E0E0E0` rule baked at
  the bottom), no table separator.
- Selected background `CellHighlighted102.png` (1 × 52pt: 1pt `#0085E5`, 50pt gradient
  `#26A4F9` → `#1477DA`, 1pt `#0060BF`), framed at `y = −1, height = rowHeight + 1`, and the cell
  raised to be the topmost cell subview while highlighted.
- Avatar **40 × 40 at (5, 5)**, corner radius **4 baked into the bitmap**, no layer clipping.
- Text column starts at **54**, right margin **5**.
- Title runs: regular `systemFontOfSize:19` then bold `boldSystemFontOfSize:19`, separated by a
  **5pt gap** measured with `sizeWithFont:`. A single-run title is entirely **bold**.
- Title colour `#111111`; `#229A0A` for secret chats; `#FFFFFF` when highlighted.
- Subtitle `systemFontOfSize:13`, `#808080`, indented **55** (one point more than the title), sat
  directly under the title with a 1pt gap. Never populated in shipped v1.1.
- One-line vertical origin: `(int)((int)((51 − lineHeight) / 2) − 1)`. Two-line: the
  title+1pt+subtitle block centred, no nudge.
- No date, no badge, no group icon, no chevron, no swipe actions.

# TGCommentMenuItemView — the section-comment row (2013)

Original files (read-only authority):
`telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGCommentMenuItemView.{h,m}`
and its model `TGCommentMenuItem.{h,m}` in the same directory.

## What it is for

This is the grey explanatory paragraph under a group of settings rows ("Turn this on to
receive...", "Your phone number will be visible..."). In 2013 Telegram it was not a
UITableView section footer. It was a **row**: a `UITableViewCell` subclass rendered inside
the section, driven by a `TGMenuItem` model like every other row in these hand-rolled
menu tables.

That single decision explains almost everything else about it, including the odd way
grouped-cell corners are computed around it (see "Section geometry" below).

## Public surface

`TGCommentMenuItemView.h:11-17`

- `@interface TGCommentMenuItemView : UITableViewCell` — plain `UITableViewCell`, **not**
  `TGGroupedCell` (contrast `TGLabelMenuItemView.h:13`, which is a `TGGroupedCell`). It has
  no rounded-rect background artwork at all.
- `@property (nonatomic, strong) NSString *label;` — the text. Setting it just assigns
  `_labelView.text` (`TGCommentMenuItemView.m:48-53`). No invalidation, no re-layout, no
  height recompute — the height is the table's problem.
- `+ (UIFont *)defaultFont;` — exposed so the model can measure without instantiating a cell.

Model, `TGCommentMenuItem.h:11-21`:

- type constant `TGCommentMenuItemType == 0x68CFA5DE` (`TGCommentMenuItem.h:11`), inherited
  `type`/`tag` from `TGMenuItem.h:13-14`.
- `initWithComment:`, mutable `comment`, and `- (float)heightForWidth:(float)width`.

## Metrics and colours (every number cited)

Font: `[UIFont systemFontOfSize:14]`, memoised in a `dispatch_once`
(`TGCommentMenuItemView.m:13-22`). Note the tell-tale `TGIsRetina() ? 14.0f : 14.0f` at
line 19 — a retina/non-retina split that was collapsed to the same value and left in. There
is no size difference; do not go hunting for one.

Label frame at init: `CGRectMake(1, 7, contentView.width - 2, contentView.height - 14)`
(`TGCommentMenuItemView.m:32`), autoresizing width+height (`:33`). So:

- vertical padding **7pt top and bottom**;
- horizontal frame inset **1pt each side** — effectively full width.

Text: centred (`textAlignment = UITextAlignmentCenter`, `:35`), `contentMode` center (`:34`),
`numberOfLines = 0` with word wrap (`:41-42`), clear background (`:37`).

Colours (`:38-40`):

- text `UIColorRGB(0x697487)` — the muted blue-grey;
- shadow `UIColorRGB(0xdae0e8)` at offset `(0, 1)` — a **light** shadow one point *below* the
  text, i.e. the classic embossed/letterpress look for text sitting on the light patterned
  settings background.

Those exact two colours plus offset are the same pair used for the section *header* labels in
these screens (`TGPrivacySettingsController.m:160-163`), which is the strongest evidence they
are a single "text on the settings background" style, not two coincidences. The background
they emboss against is `[[TGInterfaceAssets instance] linesBackground]`, a pattern colour from
`SettingsBackground.png` (`TGInterfaceAssets.mm:143-149`), set on the controller's view
(`TGPrivacySettingsController.m:124`), with the table itself fully transparent
(`TGPrivacySettingsController.m:134-137`: no separators, clear background, `backgroundView = nil`).

Cell itself: `backgroundColor = nil`, `opaque = false` (`TGCommentMenuItemView.m:29-30`).

## Height, and the inset that does not match the label

`TGCommentMenuItem.m:37-46`:

```
_cachedHeight = [_comment sizeWithFont:[TGCommentMenuItemView defaultFont]
                     constrainedToSize:CGSizeMake(width - 12 * 2, 1000)
                         lineBreakMode:NSLineBreakByWordWrapping].height + 7 * 2;
```

Three things worth internalising:

1. The measuring inset is **12pt per side**, but the label's own frame inset is **1pt**
   (`TGCommentMenuItemView.m:32`). They disagree, deliberately or not. The consequence is
   benign but visible: text is measured as if it wrapped at `width - 24` and then laid out in
   a box of `width - 2`, so real wrapping happens later than measured. The row is therefore
   never too short — at worst it is one line too tall for a paragraph that just barely fits.
   It also means the paragraph is **not** visually inset by 12pt; it is centred across nearly
   the full table width, and only long text approaches the edges. If you inset the label to 12
   you will get a narrower, more modern-looking paragraph than the original.
2. `+ 7 * 2` reproduces the label's 7pt padding, so the cell height is exactly text + 14.
   Empty string ⇒ height ≈ 0 on iOS 6 (`sizeWithFont:` of `@""` is zero height), so an empty
   comment collapses to a hairline rather than reserving space. `TGProfileController.m:1941`
   really does create one with `@""` and only fills it in later
   (`TGProfileController.m:1099-1101`), relying on this.
3. Caching is per-width, keyed by `_cachedHeightWidth` compared with `FLT_EPSILON`
   (`TGCommentMenuItem.m:39-43`), invalidated whenever `comment` changes
   (`TGCommentMenuItem.m:29-35`). The declared type of `cachedHeightWidth` is
   `UIInterfaceOrientation` (`TGCommentMenuItem.m:8`) — a copy-paste bug; it is assigned a
   float width and compared as a float, so it behaves correctly by accident.

The width passed in is the controller's `_currentTableWidth`, which is the *screen* width for
the target orientation, refreshed in `willRotateToInterfaceOrientation:` and `viewWillAppear:`
(`TGPrivacySettingsController.m:139, 185, 195`) — that is, the height is recomputed ahead of a
rotation, not after it.

## How a controller uses it (the reuse recipe)

Identical in all five call sites; quoting `TGPrivacySettingsController.m:352-370`
(same code at `TGNotificationSettingsController.m:493-511`, `TGChatSettingsController.m:412-430`,
`TGProfileController.m:2625-2643`, `TGPeopleNearbyController.m:516-524`):

- reuse identifier is the two-character `@"CI"`;
- on first creation only: `selectionStyle = UITableViewCellSelectionStyleNone`,
  `backgroundView = [[UIView alloc] init]`, `selectedBackgroundView = [[UIView alloc] init]` —
  empty views, deliberately replacing UIKit's defaults so nothing is drawn behind the text;
- a local `clearBackground = true` flag makes the controller skip the whole grouped-cell
  artwork branch that every other row goes through
  (`TGPrivacySettingsController.m:366` then the `if (!clearBackground)` at `:373`).

So: **no tap, no highlight, no selection, no background image, ever.** There is no
`didSelectRow` handling for this type in any of the five controllers.

Reuse safety: the only mutable state is `label`, always reassigned on every
`cellForRowAtIndexPath:`. There is no `prepareForReuse`, and none is needed.

## Section geometry — the part people get wrong

Because the comment is a row inside the section, the rounded-corner artwork of its
*neighbours* has to be recomputed. Every controller does this
(`TGNotificationSettingsController.m:376-392`, mirrored at `TGPrivacySettingsController.m:282-297`,
`TGChatSettingsController.m:295-310`, `TGProfileController.m:2404-2419`):

- a row is treated as **first in section** if the row before it is a comment item;
- a row is treated as **last in section** if the row after it is a comment item.

In other words a comment splits one logical section into two visually rounded blocks. This is
how the original produced "block / paragraph / block" inside a single `TGMenuSection` —
`TGNotificationSettingsController.m:110, 134, 165, 185` puts four such paragraphs into that
screen.

Row height dispatch, `TGNotificationSettingsController.m:347-352`: action/switch/variant rows
are 44, button rows 45, and the comment asks the model. The comment is the only
variable-height row in these tables.

## States and edge cases

- **Long text**: unlimited lines, word wrap, height grows; nothing is ever truncated
  (`numberOfLines = 0`, `TGCommentMenuItemView.m:42`; constraint height 1000,
  `TGCommentMenuItem.m:42`). A paragraph would have to exceed 1000pt to clip.
- **Empty string**: row collapses to ~0pt as described. `TGProfileController` avoids showing
  a zero-height row by inserting/removing the item entirely, with
  `UITableViewRowAnimationFade` (`TGProfileController.m:1104-1125`).
- **nil comment**: `sizeWithFont:` on nil returns zero size ⇒ height 0; the label text becomes
  nil and nothing is drawn. Not a crash, but no call site does it.
- **Rotation**: handled entirely through `_currentTableWidth` + the per-width cache; the label
  itself just autoresizes.
- **Localisation**: all production strings come from `TGLocalized(...)`, e.g.
  `Notifications.MessageNotificationsHelp` (`TGNotificationSettingsController.m:110`),
  `Privacy.ShowLastSeenHelp` (`TGPrivacySettingsController.m:77`),
  `ChatSettings.ClearOtherSessionsHelp` (`TGChatSettingsController.m:101`),
  `Settings.SaveIncomingPhotosHelp` (`TGProfileController.m:1857`). Two are hardcoded English
  and clearly unfinished: `TGPeopleNearbyController.m:86` and `TGProfileController.m:1096`.
- **No artwork.** This component uses no images at all. Its visual weight comes only from the
  0x697487 / 0xdae0e8 emboss over the patterned settings background.

## Our port

We have no `TGCommentMenuItemView` equivalent class. The comment is inlined, separately, in
about a dozen controllers as a UITableView **section footer view**, and in nine more it is not
implemented at all. The best of our copies is faithful; the worst is a different design.

Faithful (nothing to do): `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGSessionsViewController.m:67-101`
and `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGStorageViewController.m:569-610`. Both
reproduce `width - 12*2` measuring, `+ 7*2` padding, label frame `(1, 7, width - 2, h - 14)`,
14pt system font, centred, `numberOfLines = 0`, 0x697487 text with 0xdae0e8 shadow at (0,1).
That is the original, line for line.

Defects, worst first:

1. **Nine screens fall back to UIKit's default grouped footer.** They implement
   `titleForFooterInSection:` and no `viewForFooterInSection:`:
   `TGPrivacyViewController.m:186, 330, 1112, 1503, 1614, 1726, 1915, 2210`,
   `TGProfileViewController.m:4645`, plus `TGGroupMembersViewController.m`,
   `TGStoriesViewController.m`, `TGChatEventsViewController.m`, `TGStickersViewController.m`,
   `TGNewContactViewController.m`, `TGContactsViewController.m`. iOS 6 draws those
   left-aligned, in its own grey with a *white* bottom shadow — wrong alignment, wrong colour,
   wrong shadow direction against our light patterned background. Privacy is exactly the screen
   the original used this component on most (`TGPrivacySettingsController.m:77, 88, 99`), so
   this is the most visible miss. Fix: route them through the same helper as
   TGSessionsViewController.
2. **`TGProxyViewController.m:274-333` uses the modern style, not the 2013 one.** Its caption
   label is left-aligned at x=21 with width `tableView.width - 42` (`:288-289, 328-330, 344-352`)
   and pads by 14 rather than 14 *inside* a 7/7 box. The 2013 comment is centred at inset 1
   measured at 12. Two paragraph styles now coexist in our settings tree. Fix: centre it and use
   the 1/12/7 geometry, or accept it only if we consciously decided proxy follows the modern
   left-aligned footer (we should not — nothing else in our 2013 skin does).
3. **`TGSettingsViewController.m:1445-1477` insets the label to 12 instead of 1.** Line 1458:
   `CGRectMake(12, 7, width - 24, ...)`. Its height maths (`:1437-1443`) is correct, but the
   layout box now equals the measuring box, so wrapping happens earlier than in the original
   and the paragraph reads narrower. Change x to 1 and width to `width - 2` to match
   `TGCommentMenuItemView.m:32`.
4. **Twelve near-identical copies of a ten-line helper.** `0x697487` appears 27 times and
   `0xdae0e8` 20 times across our sources, each behind a per-file `TG…RGB` macro. The original
   had exactly one implementation. Worth one shared `TGCommentFooterView(text, width)` in a
   common file; every drift above came from copying rather than sharing.
5. **Dark/flat branches are inconsistent.** Sessions suppresses the shadow when
   `isDark || isFlat` (`TGSessionsViewController.m:93-98`), Storage only when `isDark`
   (`TGStorageViewController.m:602-606`), Proxy when `isFlat || isDark`
   (`TGProxyViewController.m:280-283`), and each picks a different substitute colour
   (`secondaryTextColour` vs `sectionHeaderColour`). The original has no theming at all, so
   this is ours to define — but it must be defined once.

Structural note: our footer-view approach is a legitimate modernisation, not a defect. It gets
the same pixels with less code and no neighbour-recomputation. The one behaviour we lose is the
original's ability to place a paragraph *between* two row blocks of one section
(`TGNotificationSettingsController.m:376-392`); with footers we must split into real sections.
Check that Notification Settings, which had four paragraphs in one screen, still reads the
same — that is the screen most likely to expose the difference.

## What it became

**Modern client** — `Telegram-iOS/submodules/ItemListUI/Sources/Items/ItemListTextItem.swift`.
Still a *row* rather than a footer (`isAlwaysPlain = true`, `:59`), still 7pt top and bottom
inset (`:162-163`), still unlimited lines. What changed:

- inset went 12 → **15** per side (`:161`, applied at `:205, 243`), and alignment went centre →
  `.natural`, i.e. left-aligned by default (`ItemListTextItemTextAlignment.natural`, `:31-41`).
  The centred paragraph is gone; centring is now an opt-in case. That is a change of taste that
  arrived with iOS 7 flat design, and it is the single biggest visual difference from 2013.
- the font is theme-scaled (`itemListBaseHeaderFontSize`, `:164`) instead of a hardcoded 14, and
  the colour is `theme.list.freeTextColor` (`:167`) instead of a literal — forced by Dynamic
  Type and dark mode, not taste. The 0xdae0e8 emboss shadow is simply gone; flat design removed
  the reason for it.
- the content gained markdown, inline links with a `linkAction` callback, an inline chevron
  attachment for "learn more >" (`:184-199`), and `.custom` attributed strings with animated
  entities. That is feature pressure: the paragraph became a place to put a tappable link. Our
  2013 cell has no tap handling whatsoever and should not grow one unless a screen genuinely
  needs it.
- variable insets (`additionalInsets` / `additionalOuterInsets`, `:57-58, 209-215`) exist purely
  because one list now hosts many kinds of blocks.

**twelve** — `twelve/Telegraph/TGCommentMenuItemView.{h,m}` and `TGCommentMenuItem.{h,m}` are
the 2013 files essentially unchanged. Diffing against the original yields only: the import
switched to `LegacyComponents.h`; `TGIsRetina() ? 14 : 14` simplified to `14`;
`UITextAlignmentCenter` → `NSTextAlignmentCenter`; `UILineBreakModeWordWrap` →
`NSLineBreakByWordWrapping`; `float` → `CGFloat` on `heightForWidth:`; `@synthesize` removed.
Zero metric or colour changes. A component this small and this correct simply never needed
touching — which is a decent argument for us to extract it as a real class rather than keep
inlining it.

## Genuinely ambiguous

The 1pt-vs-12pt inset mismatch. I cannot tell from the source whether the 12 in
`TGCommentMenuItem.m:42` was intended to be the label inset too and the label frame is the bug,
or whether the loose 1pt box was intentional so short paragraphs stay wide and centred. Both
read plausibly. I documented the original's literal behaviour (1pt box, 12pt measure) because
that is what shipped; if a screenshot comparison ever shows our paragraphs wrapping later than
the reference, this is the line to revisit.

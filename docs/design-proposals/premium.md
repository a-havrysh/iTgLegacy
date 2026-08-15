# Premium — design proposals

**The question.** Modern Telegram sells Premium with a full-screen animated carousel, a gradient
"Subscribe for $4.99" button and per-feature promo videos. None of that is reachable here: we cannot
transact (both purchase paths are `blocked` in the catalogue), we have no Lottie/TGS renderer, no
`UICollectionView`, no blur, and 512 MB of RAM. So the Premium screen in this client is not a store.
It is an **information screen**: what Premium is, what the numbers are, what this account currently
has, and the one action that *is* reachable — redeeming a gift code.

Everything below designs for that honest framing. A screen that shows a big "Subscribe" button which
always fails would be worse than no screen.

The features in scope (catalogue, area `premium`, bucket `design`, plus the `trivial` entries the
same screen has to host):

* Premium feature list / promo screen (the `design` entry that drives this)
* Premium limits inspector — default vs premium values (`getPremiumLimit`)
* Current premium state and subscription info (`getPremiumState`)
* Premium-gated upload size and download speed options (`getOption`)
* Redeem a Premium gift code
* Channel boost slots (entry point only)
* Ad-free claim (we are already ad-free — we never implemented sponsored messages)

There is already a `src/TGPremiumViewController.m` (491 lines) doing a rough version of this with a
plain `UITableViewStyleGrouped` and default UIKit cell styles. All three options below are
re-dressings of that controller, not new plumbing — the data layer (`TGClient+Premium`) stays as is.

---

## Option A — "Premium Settings Group" (the conservative one)

**File:** `svg/premium-a.svg`

**What it does.** A pushed screen off Settings that looks exactly like every other grouped settings
screen in the app: the tiled `SettingsBackground.png` ground, an 86 pt profile-style header, then
grouped 44 pt rows. The header is the profile header geometry verbatim
(`TGProfileController.m:704`): a 70×70 tile at (9, 14) with corner radius 10 — here a `#E09602`
letter tile from `+[TGIcons avatarWithInitials:size:colourId:]` carrying a ★ instead of initials —
name at x 94, y 24, `boldSystemFontOfSize:19` in `#222932` with the `rgba(#EDF0F5, 0.28)` (0, +1)
shadow, status at x 94, y 52 in `systemFontOfSize:14` `#6D7D90`. The status line is the whole answer
to "what is my premium state": *Not active on this account / Cannot be bought here*.

Below it, captions in `systemFontOfSize:14` `#697487` with the `#DAE0E8` (0, +1) comment shadow at
x 20, 12 pt of spacing above each, then a group box inset 10 pt a side. Rows are 44 pt, title at
x 20 in `systemFontOfSize:16` black, value right-aligned at a 10 pt inset in `systemFontOfSize:15`
`#356596`.

The limits rows carry the whole comparison in one value label, coloured in two runs: the current
value in `#888888`, then " → ", then the premium value in `#356596`. `5 → 10`, `10 → 20`,
`200 → 400`. That single-label trick is what lets a 44 pt right-detail row express a two-column
table without inventing a cell.

Sections in scroll order: **This account** (Premium status / Download speed / Max upload size),
**Limits — now / with Premium** (one row per `premiumLimitType` we ask for), **What Premium gives
you** (feature rows, subtitle style, dimmed when this client cannot render the feature), **Gift
codes** (a `GroupedActionButton` row, 43 pt, cap 24, label `boldSystemFontOfSize:14` white with the
(0, −1) shadow: "Redeem a Gift Code…").

**On tap.** Account and limit rows have `selectionStyle = None` — they are readouts, nothing
happens. Feature rows push a small detail screen: a `TGCommentMenuItem` block of explanatory text
plus, where relevant, the numbers again; on the way in it fires `viewPremiumFeature` so the server
sees the impression, exactly as the real client does. The Redeem row opens the existing
`TGAlertView` text-field prompt, then `checkPremiumGiftCode` → a confirm alert naming the giver and
the month count → `applyPremiumGiftCode`. "Boost slots" pushes the channel-boost list.

**On scroll.** Ordinary `UITableView` scrolling; the header scrolls away with the content
(`tableView.tableHeaderView`), so the status is only visible at the top. Grouped plates are stretched
`Cell102`/`CellHighlighted102` clipped to 44 via `[TGTheme styleCell:]`, per the components chapter
§9 substitution ruling (we do not ship `GroupedCellTop/Middle/Bottom/Single`).

**Reuses.** `TGActionTableView`, `[TGTheme styleCell:]`, `TGIcons.headerButtonWithTitle:`,
`TGIcons.avatarWithInitials:size:colourId:`, `GroupedActionButton`, `SettingsBackground`,
`NavBarBackground`, `BackButton`, `HeaderButton`, `TGAlertView`. No new artwork, no new cell class.

**Cost.** Roughly the 491 lines that already exist plus ~120 for the header and the two-run value
label; one 70×70 generated image; five in-flight requests at open. Memory is a normal grouped table:
under a dozen live cells. Nothing per-frame.

**Gives up.** The screen is long — six sections means real scrolling to reach the gift-code action,
and the status header disappears the moment you scroll. It also reads as "yet another settings page":
nothing about it says *this is the premium screen*, which is precisely the point for some readers and
a disappointment for others.

---

## Option B — "The Ledger"

**File:** `svg/premium-b.svg`

**What it does.** Drops the promo framing entirely and presents Premium as a **comparison table**.
Plain white list (`#FFFFFF`, `separatorStyle = None`, hairlines drawn by the cell in `#D5DEE5`),
full-bleed rows with no grouped plates, and three columns per row: the label at x 10 in
`systemFontOfSize:16` `#111111`, the current value right-aligned at x 248 in `systemFontOfSize:15`
`#888888`, the premium value right-aligned at x 310 in `boldSystemFontOfSize:15` `#356596`.

Sections are the plain-list idiom: a 26 pt `CategoryDivider.png` strip (`CategoryDividerFirst.png`
for index 0) with the section name at x 10 in `systemFontOfSize:14` `#697487` on the
`rgba(#FFFFFF, 0.3)` (0, +1) raised shadow, and the two column heads on the right in
`boldSystemFontOfSize:11` `#697487` at the same x anchors as the values — so the columns are labelled
once per section and never repeat.

Status lives in a 44 pt banner pinned under the navigation bar — the ruled "new top-aligned banner"
(layout §7): background `#E4E9F0`, one `#D5DEE5` hairline at the bottom, the premium badge as
`DialogListUnreadBadge.png` (27×21, caps 13/10) at x 10, y 11 carrying "★" in
`boldSystemFontOfSize:11` white with the `#8091A6` (0, −1) shadow, title `boldSystemFontOfSize:14`
`#111111`, subtitle `systemFontOfSize:13` `#536C8C`. The banner does not scroll.

Boolean features get the same two columns with a glyph rather than a number: "—" in `#888888` for
absent and "✓" in `#356596` for present. A feature this client genuinely cannot render (custom emoji,
emoji status, premium sticker effects) shows "—" in both columns in `#B0B0B0`, which is the truth: it
is not there now and Premium would not put it there either.

Redeem moves to the navigation bar as a `HeaderButton`-plated "Redeem" — the only action on the
screen, so it belongs in the chrome. The list closes with a `Footer.png` plate.

**On tap.** Rows do nothing at all: `selectionStyle = None` throughout, no push, no detail screen.
The screen is a readout. "Redeem" in the bar opens the code prompt.

**On scroll.** One `UITableView`, banner outside it. All rows are 44 pt, all cells are one reuse
identifier with three labels — the cheapest scroll in the app.

**Reuses.** `CategoryDivider`, `CategoryDividerFirst`, `Footer`, `DialogListUnreadBadge`,
`NavBarBackground`, `BackButton`, `HeaderButton`, `TGAlertView`. One new cell class with three
labels; no new artwork.

**Cost.** ~200 lines total, replacing most of the existing controller. Smallest of the three in both
code and memory: a single reusable cell type, no generated avatar image, no detail screens.

**Gives up.** Everything explanatory. A limit row says `Pinned chats 5 → 10` and never says why you
would want ten. There is no per-feature copy, so `viewPremiumFeature` is never sent and the subtitle
text `getPremiumFeatures` returns goes unused. On a 320 pt screen the two right columns are tight:
a long label like "Caption length" plus `4096` fits, but a localisation with longer nouns would
truncate — the label must be tail-truncated at x 240 and some strings will lose their tails.

---

## Option C — "Scoped Premium"

**File:** `svg/premium-c.svg`

**What it does.** Keeps all three bodies of content but stops making them one long scroll. A 30 pt
`TGButtonGroupView` (`ButtonGroupLeft` cap 8 / `ButtonGroupCenter` cap 1 / `ButtonGroupRight` cap 1,
`ButtonGroupDivider` cap 6 at 2 pt) is pinned directly under the navigation bar, full width, three
segments of 105/105/106 pt: **Status | Limits | Features**. Labels `boldSystemFontOfSize:12` white
with the `rgba(#0E284D, 0.4)` (0, −1) shadow. The selected segment is held permanently in its
`_Highlighted` art and the adjoining divider crossfades to `ButtonGroupDivider_RightHighlighted`, per
components §4. Segments fire on `UIControlEventTouchDown` — this idiom responds instantly.

The mockup shows the **Features** segment: 51 pt `Cell102`-plated rows with a 40×40 radius-4 glyph
tile at (5, 5) in the identity colours, title at x 49 in `systemFontOfSize:19` `#111111`, subtitle at
x 50 in `systemFontOfSize:13.5` `#888888`, `MenuDisclosureIndicator` at x 305. That is the contact
cell geometry exactly (`TGContactCell.m`), so the rows are visually identical to the Contacts tab —
familiar at a glance, and free to build.

Features this client cannot render keep the row but go grey: tile `#C3C8CE`, title and subtitle
`#B0B0B0`, no disclosure arrow, no selection. "No ads" carries the subtitle *Already true in this
client* and a green tick tile, which is the one honest brag we have.

The **Status** segment is Option A's 86 pt header plus the four `getOption` readouts and the gift-code
action; **Limits** is Option B's two-column table.

**On tap.** Segment switch swaps the table's data source and calls `reloadData` — no animation, no
view controller transition. Feature rows push the same detail screen as Option A. The grey rows are
inert.

**On scroll.** Each segment has its own short list; only Features can overflow the 386 pt of content
area, at seven and a half rows. Scroll offset is remembered per segment in three ivars.

**Reuses.** `TGButtonGroupView`, `Cell102`/`CellHighlighted102`, `MenuDisclosureIndicator`,
`TGIcons.avatarWithInitials:size:colourId:`, `NavBarBackground`, `BackButton`, `HeaderButton`.

**Cost.** The most code of the three: the existing controller plus a segment bar, three data sources
and three scroll positions, roughly +250 lines. Memory cost is one extra 30 pt image view and the
40 pt glyph tiles (seven generated 80×80 px images, ~180 KB total, cached in `TGIcons`).

**Gives up.** Premium **status is invisible on two of the three segments** — you have to go back to
Status to see whether you have it, which is the wrong default for a screen whose first question is
"do I have this?". It also spends 30 pt of a 480 pt screen on chrome permanently, and the 19 pt title
of the contact cell limits feature names to about 22 characters before truncating.

---

## Recommendation

**Option A**, with one borrowing from B.

A is the right answer because Premium here is not a product, it is a property of the account, and an
account property belongs on a settings page that looks like every other settings page. The 86 pt
profile header answers "do I have it?" in the first glance, in geometry the app already uses for
exactly that job on the profile screen, and the two-run `5 → 10` value label gets the limits
comparison into an ordinary right-detail row without a custom cell. It reuses more existing code than
either alternative and adds no artwork at all.

The borrowing: adopt B's honesty about unsupported features — a dimmed row that says *Not available
in this client* rather than omitting the feature. A reader comparing this screen against the real
Telegram should be able to see the complete list and see exactly which parts we could not build.

C is the one to build only if the feature list grows past about a dozen rows, at which point one
scroll really does become unwieldy. B is the one to build if the reader's priority is the numbers
rather than the explanation; it is also by far the cheapest, and if the project ever needs the
premium screen to cost nothing, it is already the answer.

---

## What genuinely cannot be built on this hardware

These are not "hard"; they are impossible on a 4S running iOS 6.1.3, and the design deliberately
contains no affordance for them.

* **The purchase flow, in any form.** Both catalogue paths are `blocked`. App Store purchase needs
  Telegram's own product IDs bound to their bundle ID — our sideloaded bundle cannot fetch those
  `SKProduct`s and TDLib rejects a receipt from a foreign bundle. The web checkout is a modern
  payment form in a browser; `UIWebView` on iOS 6 plus no card-entry UI of our own makes it
  unreachable, and card tokenisation is not something to implement here. **No option draws a
  Subscribe button.** Redeeming a gift code is the only reachable way onto Premium.
* **The animated promo carousel.** Every modern promo surface is an MP4/TGS loop per feature, with a
  page-controlled horizontally paging gradient background. No Lottie renderer, no
  `UICollectionView`, no `UIPageViewController` transitions worth the name, and a per-frame video
  decode on one A5 core while a table scrolls is not affordable. Static rows replace it.
* **The gradient/blur premium identity.** The modern client's whole premium look is a live gradient
  with vibrancy over it. No blur, no vibrancy on iOS 6, and `CALayer` shadows on a scrolling list are
  a per-frame rasterise the A5 cannot afford (typography §3.4). Premium reads as a ★ badge and a
  `#E09602` tile, nothing more.
* **Custom emoji and emoji status.** A status is a document id that must be downloaded and animated
  as a custom emoji. There is no custom-emoji pipeline in this client, so a picker would show empty
  cells. Shown as a permanently dimmed row.
* **Premium stickers, upgraded/unique gifts, gift auctions.** All three are defined by animation —
  premium sticker overlays, per-frame gradient backdrops and rotating symbol patterns, live bid feeds.
  Rendering the static frame communicates nothing, and every action costs Stars we cannot buy.
* **Star revenue graphs.** The statistics payload is a modern chart format with no renderer available
  to us, and withdrawal ends in an external web page behind a 2FA prompt.
* **Interactive dismissal of the screen.** No gesture-driven interactive transitions on iOS 6; the
  screen is a plain push with the standard back button, in all three options.

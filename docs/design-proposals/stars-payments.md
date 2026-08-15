# Stars and payments — three ways to read a balance and pay an invoice

The question: how do balance, transaction history, invoices and gifts read in a 2013 grouped-table
idiom, and what does a payment form look like when there is no modern sheet presentation?

The short answer to the second half is that **there is no sheet**. iOS 6.1.3 gives us exactly three
presentations: a navigation push, a full-screen modal, and the system `UIActionSheet` /
`UIAlertView` that `TGActionSheet` and `TGAlertView` in `src/` already wrap. There is no
`UIPresentationController`, no detent, no interactive dismissal, no blur behind anything. So a
"payment form" is either a pushed table, a full-screen modal table, or a system confirm. Each option
below picks one of those and lives with the consequence.

A useful thing to know before reading: `src/TGStarsViewController.m` already exists. It is a
`UITableViewStyleGrouped` screen with an 86 pt profile-style header (70 pt `★` avatar at `(9, 14)`,
name at x 94 in bold 19, status in system 14), a Transactions section of 51 pt rows, a Gifts section
of 51 pt rows, and a "Show more" paging row. `src/TGClient+Payments.m` (1402 lines) already wraps
`getStarTransactions`, `getReceivedGifts` and friends. Nothing below starts from zero.

All three mockups show the same errand — buying "Cat Stickers Pack" from `@CatStickersBot` for 75
stars with a balance of 214 — so the payment moment is directly comparable. Each drawing also shows
that option's list idiom in the same frame, except A, where the checkout screen *is* the list idiom.

Star colour: there is no star in the 2013 palette, so I am ruling it as `#E09602`, identity colour 2
from `TGInterfaceAssets.mm:100-116`. That keeps it inside the eight colours the app already owns and
avoids inventing a gold. Amount signs use identity `#41A903` (incoming) and `#EE4928` (outgoing) for
the same reason.

---

## Option A — "Checkout is a screen" (the conservative one)

`svg/stars-payments-a.svg` — the pushed Checkout screen.

**What it does.** Everything in the area becomes a grouped table on the `SettingsBackground` pattern,
pushed onto the navigation stack. The Stars hub stays exactly as `TGStarsViewController` already
draws it. A bot invoice bubble's Pay button pushes a **Checkout** controller which is four groups on
the patterned ground:

- Group 1, a **78 pt product header row**: 60 x 60 photo at `(20, 86)` with corner radius 5 (the
  `avatar56` radius family), title in bold system 16 `#111111` at x 90, two description lines in
  system 14 `#888888` at 18 pt line spacing. If `productInfo.photo` is absent the row collapses to
  56 pt and the text column moves to x 20.
- Group 2, one 44 pt row per `labeledPricePart` plus a bold Total row: label in system 17 `#516691`
  at x 20, amount right-aligned at x 300 in system 17 `#356596` with the star glyph 6 pt tall,
  8 pt to its left. Hairline `#D5DEE5` between rows, inset 10 from the group edge.
- A comment block in system 14 `#697487` with the `#DAE0E8` `(0, +1)` shadow, stating the balance and
  the remainder. This is where "insufficient balance" is said, in the same slot, in the same font —
  no red alert, just the sentence changing to "You need 61 more stars." and the Pay button greying
  to `alpha 0.6`.
- Group 3, disclosure rows for the bot and Terms of Service, `MenuDisclosureIndicator` at x 299,
  9 x 16, never `UITableViewCellAccessoryDisclosureIndicator`.
- The confirm is a `GroupedActionButtonGreen` row, 300 x 43 at x 10, label bold system 14 white with
  the `rgba(#124606, 0.3)` `(0, -1)` shadow — the affirmative form the rulebook already assigns to
  content-area buttons.

Card checkout (`paymentFormTypeRegular`) is the same screen with two extra disclosure rows —
Payment Method and Shipping Address — which push further tables. That is Twelve's exact structure
(`TGPaymentCheckoutController`, `TGPaymentCheckoutInfoController`, `TGAddPaymentCardController`),
and it is prior art that shipped.

**Tapped and scrolled.** Cancel pops. Tapping the green row disables it, shows a `UIActivityIndicator`
in its centre, and calls `sendPaymentForm`; on `paymentResult` we pop back to the chat and let the
`messagePaymentSuccessful` service message be the receipt. Tapping that service message later pushes
a Receipt screen — the identical table with the button group replaced by a "Charge ID" row whose tap
copies to the pasteboard via a `TGActionSheet`. The transaction-detail "sheet" from the catalogue
becomes the same pushed table too; there is no modal card.

**Reuses.** `TGActionTableView`, `TGTheme styleCell:`, `TGIcons headerButtonWithTitle:`,
`GroupedActionButtonGreen`, `MenuDisclosureIndicator`, `SettingsBackground`, and the whole existing
`TGStarsViewController`.

**Cost.** One controller of roughly 400 lines for Checkout and 200 for Receipt, both plain grouped
tables. Memory is one 60 pt thumbnail — under 60 KB decoded. Nothing new is allocated per row.

**Gives up.** Two taps and a push animation to spend 75 stars, for a transaction that carries no
information the bubble did not already show. It is the slowest of the three. It is also the only one
that scales to card payments, tips, shipping and receipts without a redesign.

---

## Option B — "Wallet with a direction filter, confirm in place"

`svg/stars-payments-b.svg` — the wallet screen with the confirm sheet up.

**What it does.** The Stars hub stops being a grouped table and becomes a **plain white list**, the
same species as the chat list. Under the navigation bar sits a `TGButtonGroupView` at 30 pt, full
width, three segments at 105 / 105 / 106 pt with 2 pt `ButtonGroupDivider` seams: All / Earned /
Spent, mapping straight onto `transactionDirectionIncoming` and `transactionDirectionOutgoing`.
Selected segment holds its `_Highlighted` image permanently. Segments fire on touch-down, per
`TGButtonGroupView`'s behaviour, so switching direction is instant.

The balance leaves the body entirely and becomes the **navigation bar subtitle**: title "Stars" in
bold 16 white at y 39, and a 13 pt `#E0EEFD` line beneath with the star glyph and "214 balance". That
is the `TGConversationController` two-line title treatment, unmodified — the balance is then visible
from every screen in the stack that keeps the title view.

Rows are 51 pt `Cell102` plates: 40 pt avatar at `(5, 5)` radius 4, title in system 19 at x 49,
subtitle in system 13.5 `#888888`, amount right-aligned at x 311 in bold 17, `#41A903` or `#EE4928`,
with the star glyph 6 pt tall to its left. Months and days are `CategoryDivider` strips at 26 pt
(`CategoryDividerFirst` above the first), label bold 13 `#697487`, not uppercased. The list closes
with `Footer`.

**Payment is a `TGActionSheet`.** No push at all. Tapping Pay on an invoice bubble calls
`getPaymentForm`, and when it returns, an action sheet rises with a two-line title — the product name
in bold 14 white, then "75 stars of your 214 will be spent." in 13 pt — and two buttons, "Pay 75
Stars" and Cancel. The user never leaves the chat. Insufficient balance replaces the whole sheet with
a `TGAlertView` saying so, since there is nowhere to buy more (see the last section).

**Tapped and scrolled.** A row tap pushes a detail table (same as A's receipt). Scrolling past the
last row triggers the next `getStarTransactions` page; the segment filter refetches from offset ""
rather than filtering locally, because a 25-row page of one direction is cheaper than holding both.
Gifts move to their own screen behind a "Gifts" header button, because the segment bar has taken the
place the second section used to occupy.

**Reuses.** `ButtonGroup*` (all seven assets), `Cell102` / `CellHighlighted102`, `CategoryDivider*`,
`Footer`, `TGActionSheet`, the nav-bar subtitle from `TGConversationController`.

**Cost.** The wallet is a rewrite of `TGStarsViewController` into a plain table with a custom 51 pt
cell — maybe 350 lines, of which the cell is 120. The payment path is about 80 lines and no new view
controller at all. Memory: 40 pt letter avatars from `TGIcons avatarWithInitials:size:colourId:`,
cached by the existing avatar cache.

**Gives up.** The product photo — an action sheet title cannot carry an image, so the user confirms
against a name and a number. It also has no room to grow: the moment a card, a tip or a shipping
address enters the picture, this path has to fall back to Option A's screen anyway, so the app ends
up with both idioms. And splitting gifts onto a second screen makes the gifts feature less
discoverable than it is today.

---

## Option C — "The ledger is a chat list"

`svg/stars-payments-c.svg` — the ledger with a system confirm over it.

**What it does.** Transactions are rendered as **73 pt `DialogListCell` rows** — the chat list's own
geometry, unchanged: 56 pt avatar at `(8, 8)` radius 5, title bold 16 `#111111` at x 73, a
`#536C8C` action line at y +44 (the colour the chat list uses for "Photo" and "joined the group"),
a `#888888` detail line at y +60, date right-aligned at x 311 in system 13 `#337ACC`, and the
**amount in a `DialogListUnreadBadge`** at `(320 - 28 - w, +29, w, 21)` where
`w = MAX(27, textWidth + 10)`, label bold 14 white with the `#8091A6` `(0, -1)` shadow. Signs are
carried by the glyph inside the badge, `+200` and `−75`, not by colour, because the badge art is one
colour and tinting it is forbidden.

The balance is a **44 pt banner** directly under the navigation bar — the rulebook's height for any
new top-aligned banner — background `#EBF0F5` (the unread-row colour), an 11 pt star at x 20,
"214 stars" in bold 16 `#111111`, and "7 gifts received" right-aligned in 14 pt `#337ACC` which
pushes the gifts list. One `#D5DEE5` hairline along the bottom. It scrolls with the list rather than
pinning, so a long history gets the full screen.

**Payment is a `TGAlertView`.** The bluntest possible answer: "Confirm Payment / Pay 75 stars to
CatStickersBot for Cat Stickers Pack? / Cancel · Pay". One system alert, two lines of body, no new
view, no photo, no price breakdown. `sendPaymentForm` runs from the alert's completion block and the
result lands as a service message in the chat.

**Tapped and scrolled.** Because a row is a chat-list row, it behaves like one: a tap pushes the
counterparty's chat when the transaction has a peer, and a receipt table when it does not.
Swipe-to-delete is disabled — there is nothing to delete. Paging is the same offset scroll as B.
Gifts are a second screen behind the banner's right-hand link.

**Reuses.** `DialogListCell` / `DialogListCellHighlighted`, `DialogListUnreadBadge`, `Footer`,
`TGAlertView`, and — importantly — the whole `TGDialogListCell` layout code, which can be
subclassed rather than reimplemented.

**Cost.** The smallest of the three: a `TGDialogListCell` subclass that swaps the badge's number for
an amount, plus a data source. Roughly 250 lines total, and the payment path is about 40. Memory is
the highest per row, though: 56 pt avatars are 4x the pixels of 40 pt ones, and at 73 pt a screenful
is only 5 rows, so a 25-row page holds five screens of decoded avatars. Still trivial against 512 MB.

**Gives up.** Precision. A badge with `−75` in it looks like an unread count, and users have twelve
years of muscle memory saying a blue pill on the right of a 73 pt row means "unread messages". That
is a real risk and the honest reason this option is second and not first. It also gives up any
ability to show a price breakdown, a tip, or a shipping address — the alert has room for two lines
and no more — so card payments are simply out of scope in this option.

---

## Recommendation

**Option A, with one borrowing from B.** Build the Checkout table as drawn in A, because it is the
only structure that survives contact with `paymentFormTypeRegular` — price parts, tips, shipping
options and saved cards all need rows, and Twelve shipped precisely this shape, which is the
strongest evidence available that it works in this idiom. The borrowing is B's navigation-bar
balance subtitle: it costs nothing, it uses a treatment the app already owns, and it means the user
sees their balance on the Checkout screen without a dedicated row.

Keep `TGStarsViewController`'s grouped hub as it stands rather than rewriting it into B's plain
list. The segmented direction filter from B can be added later as a `TGButtonGroupView` above the
existing table without disturbing anything, if transaction volume ever makes it worth the extra
fetch. C is the most beautiful of the three and I would build it if the badge did not already mean
"unread"; it does, so it stays a sketch.

One thing worth adopting from C regardless of option: the 44 pt balance banner is a better home for
the balance than the 86 pt profile header currently in `TGStarsViewController`, which spends 86 pt
of a 480 pt screen on one number and an avatar of a star.

---

## What cannot be built on this hardware

These are the honest gaps, in the catalogue's own terms.

- **Buying stars, gifting stars, star giveaways.** All three route through StoreKit with product
  identifiers registered to Telegram's App Store account. A sideloaded build has none, so
  `canPurchaseFromStore` fails and `assignStoreTransaction` never gets a receipt. The alternate
  Fragment top-up needs a modern browser session that iOS 6's `UIWebView` cannot hold. This is why
  every option's insufficient-balance path is a dead end that only says so — there is no "Buy more"
  button to draw, and drawing one would be a lie. Incoming `messageGiftedStars` service messages
  render fine.
- **Apple Pay.** PassKit is iOS 8 and needs a Secure Element the 4S does not have.
- **Star revenue withdrawal.** Requires the 2FA password check plus a Fragment web session; the URL
  from `getStarWithdrawalUrl` cannot be completed in a 2013 `UIWebView`.
- **The unique-gift card and the gift upgrade preview.** The design is a radial-gradient backdrop
  with a tiled pattern of symbols, animating through model / symbol / backdrop variants. A radial
  gradient composited under an animating sticker at 60 fps on an A5 with no Core Animation
  compositing help is not a thing this device does; the reduced version is a static 51 pt row per
  attribute with the rarity percentage as the right-hand value, and the gradient replaced by a flat
  identity colour picked from the backdrop's centre hue.
- **The gift picker grid, the resale marketplace and gift crafting.** No `UICollectionView`. The
  grid is buildable as a `UITableView` of plated rows with four 72 x 72 tiles each, per the
  rulebook's media-grid ruling, but the gifts are animated stickers and holding a screenful of
  animated TGS-equivalents in 512 MB is not realistic. The reduced version is a static first-frame
  thumbnail per tile with the price in bold 12 underneath. The resale marketplace's three attribute
  facet pickers are three more pushed tables; workable, but it is the largest screen stack in the
  area and I would not build it.
- **Gift auctions.** A live countdown driven by server updates, refreshing a bid list. Technically
  buildable — it is a timer and a table reload — but every reload on an A5 is a visible stutter and
  a real-money auction that stutters is worse than no auction. Recommend leaving it out entirely
  rather than shipping a reduced one.
- **A modal transaction-detail card.** The catalogue asks for a "modal detail view over the
  transactions list". iOS 6 has no over-context presentation; a modal covers the whole screen. All
  three options replace it with a push, which is what the era did.

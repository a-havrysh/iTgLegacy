# Bots

The catalogue gives this area four "design" features that actually matter on screen: inline
keyboards under a message, the custom reply keyboard, inline query results, and the bot menu button.
Everything else in the area is either trivial once those exist (callback answers, switch-inline,
recent inline bots, service messages, "via @bot") or is blocked because it ends in a web app.

The central question — what is the reduced version of a web app — has, honestly, only one answer:
**there is no reduced web app, there is a reduced entry point.** iOS 6.1.3 ships UIWebView with a
JavaScriptCore that predates ES6, a TLS stack that modern Telegram Web App hosts refuse, and no
`WKScriptMessageHandler`-class bridge. A 512 MB single-core A5 could not hold a modern SPA even if
the JS parsed. So the three options below differ in *where bot UI lives*, and each one carries the
same web-app answer: show what TDLib already tells us about the app (its title, icon, short
description, URL) as native rows, and hand the URL to Safari. Nothing pretends to run.

---

## Option A — Everything inline, in the chat (`bots-a.svg`)

**What it does.** The bot's UI stays inside the conversation, drawn entirely out of the two button
families the rulebook already owns.

*Inline keyboard* is a **group button bar** per row, exactly as the reactions ruling prescribes
(components §10): `ButtonGroupLeft` / `Center` / `Right` at height **30**, `ButtonGroupDivider`
(cap 6, width 2) on every seam, label `boldSystemFontOfSize:12` white with the standard
`rgba(0x0e284d,0.4)` `(0,-1)` shadow. The bar is left-aligned with the bubble at x = 12, sits **4 pt**
below it, rows are 4 pt apart, and each row's segments split the bubble width as
`(barWidth − 2(n−1)) / n` with the last segment absorbing the remainder — the same arithmetic
`TGButtonGroupView` already does. A URL button gets a `↗` glyph before its label; a pressed button
holds its `_Highlighted` art while `getCallbackQueryAnswer` is in flight, which is also the entire
loading indicator. Answers come back as a one-button alert (`show_alert`) or, for a toast, silence
plus the button returning to normal — the interaction chapter forbids inventing a toast.

*Reply keyboard* takes the keyboard's own 216 pt slot below the input bar: ground `#c3ccd6` with a
1 px `#a3adb8` hairline on top, rows of `GroupedActionButton` plates at height **43**, 8 pt outer
inset, 4 pt gutter between columns, 6 pt between rows, label `boldSystemFontOfSize:14` white.
Special buttons (`requestLocation`, `requestPhoneNumber`, `requestPoll`) use
`GroupedActionButtonGreen` with a 14×14 white glyph 4 pt before the label, and still route through
the existing action-sheet confirm. `resize_keyboard` is honoured by growing the button height into
the free space, capped as TWELVE caps it (`TGCommandKeyboardView.m:193`, `MIN(190, contentSize)`
before insets); more rows than fit simply scroll inside the panel. The emoji slot in the input bar
becomes a 24×24 keyboard-toggle glyph while a reply markup is active, so the user can get the
system keyboard back; `one_time_keyboard` hides the panel after the next send.

*Web apps.* The menu button is a plated button in the input bar; when its payload is a web app it
does not open one — it pushes the screen from option C.

**Reuse.** `TGButtonGroupView` verbatim, `GroupedActionButton(+Green,+_Highlighted)`,
`ConversationInputPanel`, the existing alert and action-sheet paths, the existing poll/contact/
location send calls.

**Cost.** The real work is in `ChatViewCell`: `reply_markup` has to contribute height, the cell has
to own a button-bar subview array and hit-test it, and the height cache has to invalidate when a
message is edited. Roughly one new view class (~200 lines) plus 100 lines of cell metrics for the
inline keyboard; the reply panel is another view class of about the same size plus input-bar mode
switching. Memory is nil-ish: a handful of stretched UIImageViews per visible message, and the art
is already resident.

**Gives up.** Wide keyboards look cramped — a 4-button row on 320 pt gives 78 pt segments, so long
labels truncate; the bar refuses to wrap, it truncates like the original truncates everything.
Scrolling gets slower: a chat where every message carries a two-row keyboard is drawing six extra
image views per cell, and cell height computation is no longer purely text-driven. And the reply
panel steals the keyboard, so typing and pressing a bot button are two separate modes.

## Option B — Modal-first (`bots-b.svg`)

**What it does.** Anything that would be a keyboard-height overlay becomes a **modal form** instead,
which is what `interaction-patterns.md` already rules for stickers ("never a keyboard-height inline
panel with a tab strip"). Typing `@pic ` in the input bar and pausing pushes a presented
`UINavigationController`: Cancel `HeaderButton` on the left, the bot's name as nav title with
`@username` as the 11 pt subtitle, a 44 pt search bar (`SearchBarBackground` +`SearchInputField`
+ `SearchBarIcon` + `ClearInput`) holding the live query, and the results as **51 pt `Cell102`
rows** — 40×40 thumbnail at (5,5) radius 4, title `systemFontOfSize:19` `#111111`, subtitle
`systemFontOfSize:13.5` `#888888`. The switch-pm button is a 44 pt row pinned above the list, blue
`#0779d0` at 16 pt with a grey second line, hairline `#d5dee5` beneath. Paging on `next_offset`
happens when the last row scrolls in, and shows itself as one more 51 pt row with a spinner and
"Loading more…". Tapping a row calls `sendInlineQueryResultMessage` and dismisses; the list is
closed with `Footer` when it ends short.

Media-heavy bots (`@gif`, sticker bots) get the same screen with the rows replaced by the ruled
media grid: frame-laid `UIScrollView`, 72 pt tiles, 4 pt gutter, on `Cell102` plates — no
`UICollectionView`, it does not exist.

The custom reply keyboard in this option is *also* modal: a presented list of the bot's buttons as
44 pt rows. The bot menu button and the command list land in the same place.

**Reuse.** The whole modal-form idiom from §4 of the interaction chapter, `TGForwardPicker`-shaped
list code, `Cell102`, `SearchBar*`, `Footer`, `HeaderButton`.

**Cost.** Cheapest of the three by a wide margin: one table-backed view controller with an image
cache, no changes to `ChatViewCell` at all, no input-bar modes. Memory is bounded because a modal
owns its thumbnails and frees them on dismiss — this matters, an inline results strip that survives
in a chat controller is exactly how a 512 MB device dies.

**Gives up.** Speed and the sense of a live query. Modern inline query results update under your
fingers as you type; here you type, wait for a push, pick, and get dropped back. Inline *keyboards*
cannot be modal at all — they belong to a specific message — so option B still has to borrow A's
button bar for those, or show a bot message's buttons only when you tap the bubble, which is worse.
Be honest that B is a half-answer: it solves inline results and commands beautifully and does not
solve inline keyboards.

## Option C — The Bot page (`bots-c.svg`)

**What it does.** One pushed screen that is the bot's whole non-chat surface, and the designated
landing place for everything web-app-shaped. Profile header metrics verbatim: 86 pt container,
avatar `(9,14,70,70)` radius 10 on the identity colour, name at x = 94 in `boldSystemFontOfSize:19`
`#222932`, `@username · bot` at `systemFontOfSize:14` `#6d7d90`. Under it the bot's short
description as a comment block, `systemFontOfSize:14` `#697487`. Then a **Commands** section of 44 pt
rows — command in `boldSystemFontOfSize:17` `#516691` on the left, its description right-aligned in
`systemFontOfSize:16` `#356596`, 10 pt insets, `#d5dee5` hairlines — where a tap sends the command
and pops back to the chat.

Then the reduced web app. `getMainWebApp` / `searchWebApp` give us a title, an icon and a URL
without ever loading the page, so the mini app renders as a 52 pt row: 36×36 icon at radius 4,
title `boldSystemFontOfSize:16` `#111111`, and the plain second line **"Cannot run on this device"**
in `systemFontOfSize:13` `#888888`. Beneath it two `GroupedActionButton` plates at height 43 —
**Open in Safari** and **Copy link** — 8 pt outer inset, 4 pt between. Safari on iOS 6 will fail on
most modern mini apps too, but that failure belongs to Safari, not to us, and the URL is at least
transportable to another device. A `messageGame` bubble routes to this same screen, showing the
game's photo and its high-score table as 44 pt rows, with Play replaced by Open in Safari.

Attachment-menu bots do not appear anywhere. They are dead buttons, and the catalogue is right to
call them blocked.

**Reuse.** `TGProfileViewController`'s header layout, `Cell102` clipped to 44,
`GroupedActionButton`, `SettingsBackground` ground, the existing push navigation.

**Cost.** Almost nothing new: a list controller with three section types and no image work beyond a
36 pt icon. It is the smallest of the three in both code and memory.

**Gives up.** It is not a web app and it never will be. A user who taps a bot's menu button expecting
a store, a wallet or a form gets a description and a link. It also does nothing for inline keyboards
or the reply keyboard, so it is a *component* of an answer rather than a whole answer.

---

## Recommendation

**Ship A and C together; keep B's modal for inline query results only.**

A is the one that cannot be avoided: inline keyboards are attached to individual messages, they are
the single most visible bot feature, and the group button bar renders them with art we already ship
and metrics the rulebook already ruled on for reactions. Doing them any other way invents a control.
C is nearly free and gives the web-app problem a truthful home instead of a dead button, and it is
where the menu button, the command list and games all land.

B earns its place for inline query results and nothing else. A live results strip pinned above the
input bar would mean holding decoded thumbnails inside a chat controller that already holds a
message list, on a device with 512 MB — that is where this client falls over. A modal that owns its
images and drops them on dismiss is both the safer engineering and the pattern the interaction
chapter already made law for stickers. The cost is one extra tap and no live-as-you-type feel; the
2013 idiom does not have live-as-you-type anywhere anyway.

So: inline keyboards as button bars in the bubble, reply keyboard as a 216 pt panel of
`GroupedActionButton` rows in the keyboard's slot, inline results as a modal picker, everything
web-app-shaped as the Bot page with an Open in Safari button.

---

## What genuinely cannot be built here

- **Telegram Mini Apps (`openWebApp`, `sendWebAppData`, `answerWebAppQuery`).** iOS 6.1.3 has
  UIWebView only. No `WKWebView`, no `WKScriptMessageHandler`, a JavaScriptCore with no ES6, and a
  TLS stack modern hosts reject. Even with a bridge hand-rolled over `webView:shouldStartLoadWith
  Request:` custom URL schemes, a current mini app's JS bundle will not parse, and a 512 MB
  single-core A5 could not hold the DOM if it did. The reduced version is option C's link row.
- **Attachment-menu bots.** Every entry point launches a web app. The icons would be buttons that
  cannot do anything, so they are not drawn.
- **Playing games (`inlineKeyboardButtonTypeCallbackGame`).** Same web runtime problem. The game
  *bubble* (photo, title, description) and `getGameHighScores` as a 44 pt row table are both
  buildable and are in option C; pressing Play is not.
- **Prepared inline messages, `getGrossingWebAppBots`, `getWebAppPlaceholder`, `checkWebApp
  FileDownload`.** All are support calls for a runtime that does not exist here; nothing to draw.
- **Inline message editing (`editInlineMessage*`).** Requires a bot-token session. A user client can
  never call these regardless of hardware.
- **Business connected bots.** Requires an active Business subscription on the account.
- **A live, keyboard-height inline-results strip that updates per keystroke.** Not a hardware
  impossibility so much as a memory one: decoded thumbnails plus a live message list on 512 MB is the
  configuration that gets jetsam-killed. It is refused on purpose, and option B is the substitute.
- **Any of this with an animated transition beyond push/modal.** No view controller transitions, no
  interactive dismissal, no blur behind a panel. The reply-keyboard panel appears with the keyboard's
  own slide or not at all.

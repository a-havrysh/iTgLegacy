# Login and accounts

The original login is three screens on dark linen: phone, code, password. One centred notice label,
one input plate, one blue **Next** in the bar. Nothing else is on screen, and that is the whole
character of it. The features the catalogue asks for — QR login (`requestQrCodeAuthentication`),
login email (`setAuthenticationEmailAddress` / `checkAuthenticationEmailCode`) and multiple accounts —
all want to add a *choice* to a flow whose calm comes from never offering one.

The three options below differ in where that choice is allowed to appear.

Shared facts every option is built on, taken from `src/TGLoginViewController.m` and the rulebook:

- Ground is `DarkLinen.png` with `LoginShadow.png` over the full bounds; bar is `LoginHeader.png`,
  title white bold 16 with a `#25272B` shadow at `(0, +1)`.
- Notice label: `systemFontOfSize:14`, `#C0C5CC`, shadow `#323C4A` at `(0, +1)`, centred, multiline.
- Layout is computed against `viewSize.height = screenHeight − 20 − 44 − 216`, i.e. the number pad is
  assumed permanently up. On a 4S that leaves a content band of **200 pt** between the bar and the
  keyboard. Country button 290×55 at `y = 70` in that band, input plate 290×47 at `y = 133`.
  **There is no free vertical space under the input plate on the phone step** — six points. Any
  option that wants a visible "or log in another way" control under the field is lying about the
  geometry.
- Bar buttons: `HeaderButton_Login_Blue` (cap `width/2`) for Next, `HeaderButton_Login` for the
  neutral one already used by "Send the code again", `BackButton_Login` for back.

---

## Option A — Same wizard, one more menu (`auth-account-a.svg`)

**What it does.** The three screens do not change at all. The empty left bar slot on the phone step
(step 1 has no back button) gains a `HeaderButton_Login`-plated **Options** button, 30 pt tall at
`x = 5`, `y = 27`, label bold 12 white with a `rgba(#07080A, 0.35)` shadow at `(0, −1)` — the exact
button `loginToolbarButtonWithTitle:` already builds for "Send the code again". Tapping it dismisses
the keyboard and raises a `TGActionSheet` with **Log in by QR Code** and **Log in with Email**, plus
Cancel. Sheet geometry is the existing one: 304 pt wide at `x = 8`, buttons 41 pt tall on
`MenuButtonLeft/Center/Right` (caps 10/1/1), a `MenuButtonSeparator` seam between the two options,
an 8 pt gap, then Cancel at `y = 431`, 8 pt from the bottom.

The two destinations are pushed onto the same login navigation controller and reuse the *code step*
layout verbatim — an 80 or 200 pt wide `LoginInput` plate centred in the 200 pt band, one notice
label above, one resend button 14 pt below it. The email screens are literally the code screen with
`keyboardType = UIKeyboardTypeEmailAddress`, a 200 pt plate and a different notice
("We have sent a code to a\*\*\*@gmail.com"). The reset-email countdown from
`emailAddressResetStatePending` becomes the `timeoutLabel` that already exists, with the
`HeaderButton_Login` resend button relabelled **Reset email address**.

Multiple accounts is one row in Settings, `Accounts  ›`, whose detail screen is the plain 44 pt
value-row list; it is not a first-class surface.

**Tapped and scrolled.** Nothing scrolls; every screen still fits above the keyboard. Back is the
existing `BackButton_Login`. The sheet is the same modal the app already uses everywhere else.

**Reuses.** `TGLoginViewController` (two more cases in the `TGLoginStep` enum), `TGActionSheet`,
`loginToolbarButtonWithTitle:`, `layoutInterface`'s non-phone branch, `timeoutLabel`, `resendTimer`.

**Cost.** Roughly 150 lines in `TGLoginViewController.m` plus four TDLib wrappers. No new view class,
no new artwork, no measurable memory.

**Gives up.** QR login is hidden behind a menu, so nobody who does not already know it exists will
find it. The email step cannot show a "Sign in with Apple/Google" alternative — that is blocked
anyway. Multi-account has no visual presence at all.

---

## Option B — The wizard gains a QR front door (`auth-account-b.svg`)

**What it does.** QR becomes a peer of phone entry rather than a hidden option. The login stack opens
on whichever the user used last; from the phone step the *left* bar button reads **QR**, from the QR
screen it reads **Phone**, and the two swap by push/pop.

The QR screen drops the keyboard entirely, so it gets the whole 416 pt below the bar. A white plate
216×216 at `(52, 104)`, radius 5, carries a 25-module code drawn at **8 pt per module** (200 pt of
code, an 8 pt quiet zone), which is the largest whole-point module size that fits a version-2 code on
this screen and still scans from 30 cm. Two lines of notice above it in the standard 14/`#C0C5CC`
treatment; three numbered instruction lines at `y = 351/371/391`, left-aligned at `x = 61` so the
numerals line up; a 13 pt `#8B929C` countdown "Code refreshes in 0:24" at `y = 415`; and a 180×30
`HeaderButton_Login` at the bottom edge, `y = 434`, reading **Log in with phone number** for anyone
who lands here by accident.

When `authorizationStateWaitOtherDeviceConfirmation` delivers a new link, only the module rects
redraw — one `setNeedsDisplay` on a 216 pt view, roughly every 20 s. Email login is where it is in
option A, behind the code step, since it is a second factor and never a starting point.

**Tapped and scrolled.** Nothing scrolls. The countdown is the same `NSTimer` the resend button uses.
Tapping the QR itself does nothing; there is no zoom, no share.

**Reuses.** The login chrome, `HeaderButton_Login`, the notice-label treatment, the resend timer.

**Cost.** The real cost is a **QR encoder**. `src/quirc` is a decoder only; nothing on iOS 6 encodes
(no `CIQRCodeGenerator` until iOS 7). That is a bundled or hand-written Reed–Solomon encoder, about
600–900 lines of C, and it is the reason the catalogue marks this entry `design` rather than
`trivial`. Memory is negligible: a 25×25 bitmap and a `UIView` that fills rects.

**Gives up.** A second screen in a flow that had three, and the encoder maintenance. Also, the code
only ever encodes a `tg://login?token=` URL — there is no camera on this screen, so the *other*
direction (this device scanning someone else's code) stays on the existing `TGQRViewController`.

---

## Option C — Accounts is a place (`auth-account-c.svg`)

**What it does.** Treats "multiple accounts" as the primary problem and the login wizard as something
you enter *from* an account list. Settings gains an **Accounts** row that pushes a plain white list —
not a grouped table, because these are people, and people live in 51 pt rows in this app.

- `CategoryDividerFirst` header at `y = 64`, 26 pt, label bold 15 `#697487` with the white `(0, +1)`
  shadow: "On this iPhone".
- Account rows on `Cell102` clipped to **51 pt**: 40×40 avatar radius 4 at `(5, +5)` in the identity
  colour, name `systemFontOfSize:19` `#111111` at `x = 49`, subtitle `systemFontOfSize:13` `#888888`
  at `x = 50` reading "+44 7700 900112 · signed in".
- The connected account carries `ListCheck` 20×20 at `x = 286`. A signed-out-but-remembered account
  carries a `DialogListUnreadBadge` stretched to its stale count: 21 pt tall, right edge 24 pt from
  the screen edge, label bold 14 white with the `#8091A6` `(0, −1)` shadow.
- `CategoryDivider` at `y = 192`, then two 44 pt action rows in `#0779D0` bold 17 at `x = 10` with
  `MenuDisclosureIndicator` at `x = 300`: **Add Account by Phone Number** and **Add Account by QR
  Code**. Both push the option-B login stack modally.
- A `Footer` plate closes the list, then a four-line comment block in `systemFontOfSize:14`
  `#697487` with the `#DAE0E8` `(0, +1)` shadow, stating the honest limitation below.
- While switching, the tapped row is replaced in place by a 44 pt row with a 16 pt spinner at `x = 14`
  and "Connecting to Work…" in 16 pt `#516691`. Swipe-to-delete on a row signs that account out
  (`logOut`) using the existing 61×31 delete button.

**Tapped and scrolled.** The list scrolls like any 51 pt list; with two or three accounts it never
needs to. Tapping a row tears the TDLib client down and brings it back up on the other account's
database directory — the chat list is rebuilt from scratch, which is why the row shows progress
rather than switching instantly.

**Reuses.** `Cell102`, `CategoryDivider(First)`, `ListCheck`, `DialogListUnreadBadge`, `Footer`, the
comment-row treatment, the swipe-delete machinery, and the whole login stack unchanged.

**Cost.** UI is cheap — one table controller, ~250 lines. The expensive part is underneath: a
per-account TDLib database directory and a clean teardown/restart of `TGClient`. Peak memory during a
switch is one client, not two (see below), but the restart re-downloads the chat list, so a switch is
2–5 s on a 4S.

**Gives up.** Real simultaneous accounts. No background sync for the account you are not on, so its
badge is whatever it was when you left, and push (which we do not have anyway) would not cover it.

---

## Recommendation

**Ship A, then B's QR screen; hold C.**

A is the honest reading of the brief: it adds the two login methods without adding a single pixel to
any of the three screens, because the one place the layout has room is the empty left bar slot. It is
a week of work and it cannot break the flow it extends. B is the right *second* step — QR login is
genuinely the nicest way to sign a second device in, and the screen it needs is calm on its own terms
(one white square, three lines, no keyboard) — but it is gated on writing a QR encoder, and that work
also unblocks the profile-QR entry in the catalogue, so it deserves to be scheduled as its own task
rather than smuggled into the login change. C is the most useful screen of the three for anyone who
actually juggles two numbers, but it promises something the hardware only half-delivers, and a
switch that takes four seconds and shows a stale badge is worse than a Log Out row that is honest
about what it does. Build C when, and only when, per-account database directories exist.

---

## What cannot be built on this hardware

- **Sign in with Apple ID / Google ID** (`emailAddressAuthenticationAppleId`,
  `…GoogleId`). No `AuthenticationServices`, no Google SDK that targets iOS 6. There is no way to
  obtain the token, so the buttons would be decorative. Not drawn.
- **Passkey / WebAuthn and web-token login** (`checkAuthenticationPasskey`,
  `checkAuthenticationWebToken`). Needs `AuthenticationServices` and `WKWebView`; iOS 6 has neither.
- **Firebase SMS device verification** (`sendAuthenticationFirebaseSms`). Requires an APNs push
  receipt for the bundle. This is a sideloaded build with no push registration and no matching
  entitlement, so the receipt cannot exist.
- **Premium-purchase-gated authorization** (`authorizationStateWaitPremiumPurchase`). Needs a live
  StoreKit purchase against the modern Telegram product id.
- **Two accounts connected at once.** Not an API limit — a RAM one. One TDLib client with a warm chat
  list already sits in the tens of megabytes on this device; 512 MB total with iOS 6's watchdog
  killing anything that spikes means a second client is not affordable. Every multi-account design
  here is therefore *serial*: one connected account, the others remembered.
- **Live QR scanning while the login QR is displayed.** One camera, one screen, and no
  `AVCaptureVideoPreviewLayer` running underneath a 216 pt code without stalling the encoder refresh.
  The two QR directions stay on two separate screens.
- **Interactive/gesture dismissal of any of these screens.** iOS 6 has push and modal only; every
  transition above is a push or a full-screen modal, as drawn.

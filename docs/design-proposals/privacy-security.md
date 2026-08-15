# Privacy and security — how multi-step flows fit the grouped-table idiom

The catalogue asks for eight design-bucket features in this area: privacy exception lists,
a session detail screen with two switches, the unconfirmed-session banner, set/change/disable the
two-step password, the recovery e-mail plus its six-digit code, password recovery at login, a local
passcode lock with auto-lock and a keypad overlay, and the server-driven report flow.

Every one of them is the same shape underneath: a sequence of questions with validation between
them, ending in a commit. The 2013 idiom has exactly two containers for that — a pushed grouped
table (`UITableViewStyleGrouped`, rowHeight 44, plates, comment footers) and a modally presented
navigation controller holding the same table (interaction-patterns §4). There is no wizard control,
no page dots, no segmented progress bar, and inventing one is forbidden. So the real question is
not "what widget", it is **where the seams between the steps go**: one screen per question, one
screen for the whole form, or one status screen that owns the state and raises the form.

The three options below answer that differently. All three share the same building blocks: 44 pt
rows, group inset 10 pt with the `GroupedCell*` plate family (substituted with `Cell102` clipped to
44 per components §9), row title `boldSystemFontOfSize:17` `#16181a`, value
`systemFontOfSize:16` `#356596`, footer caption `systemFontOfSize:14` `#697487` with the
`#dae0e8` `(0,+1)` shadow, blue action row `boldSystemFontOfSize:16` `#0779d0`, destructive row the
same metrics in red. The blue bar button is `HeaderButton_Login_Blue` with cap `width/2`; the plain
one is `HeaderButton` via `+[TGIcons headerButtonWithTitle:bold:target:action:]`.

---

## Option A — Pushed chain: one question per screen

`svg/privacy-security-a.svg`

The flow is a stack of pushed controllers, each of which is a grouped table holding exactly one
group of one input row, one comment footer explaining the step, and a blue commit button in the
navigation bar. This is literally the shape of the original login flow (phone → code), extended.

**Layout as drawn.** Status bar 20, nav bar 44. Back button `BackButton` art at x 5, y 27, height
30, label `Two-Step` in `boldSystemFontOfSize:12` white with the `rgba(0x0e284d,0.4)` `(0,-1)`
shadow. Right button `HeaderButton_Login_Blue`, 46 x 30 at x 269, label `Next`. Caption
"Step 2 of 4" sits at x 20, y 82 in the comment style — the only progress affordance, and it is
text, not chrome. The single group is at y 96, 300 x 44, inset 10. Its label `Password` is at x 20;
the `UITextField` occupies `CGRectMake(112, 96 + 12, 178, 20)` with `secureTextEntry = YES`, so the
bullets start at x 120. Footer caption at x 20, y 160, four lines at 16 pt leading. A blue
`Skip this step` line at x 20, y 240 in bold 16 `#0779d0` — a plain flat action row without a plate,
which is how the original draws a secondary escape. Keyboard occupies the bottom 216 pt (y 264 to
480), which is the real constraint: content must fit in the 200 pt between the nav bar and the
keyboard, and one group plus one caption is exactly what fits.

**Behaviour.** The field is first responder on `viewDidAppear`, so the keyboard is up from the
start and never moves; nothing scrolls, because nothing is taller than the visible area. `Next`
validates locally (non-empty; on the re-enter screen, equal to step 1) and pushes the next
controller; a failure is a one-button `UIAlertView` with `title:nil` per interaction §7, and the
field keeps its text. Server work — `setPassword`, `setRecoveryEmailAddress` — happens only on the
last step, wrapped in `TGProgressWindow` with `dismissWithSuccess`, then
`popToViewController:` back to the security list. Back at any point abandons without a
confirmation, because nothing was sent yet. The code-entry screen substitutes a 6-digit numeric
field and adds a second footer line carrying the resend countdown, redrawn once a second by an
`NSTimer` on the label only.

**Screens this produces.** 2SV: Password → Re-enter → Hint → Recovery e-mail → Code (5 pushes,
all the same controller class with a different step descriptor). Passcode: Enter → Re-enter, then
the auto-lock interval is a separate pushed table with `ListCheck.png` marks (13 x 14 pt, right
inset 12). Sessions: list → session detail with two switch rows.

**Reuse.** One `TGSecurityStepViewController` parameterised by a step struct (title, back title,
field kind, footer text, validator, next step). Everything else is `TGSettingsViewController`
machinery that already exists — the header/footer caption views in `TGSessionsViewController.m:271`
are directly reusable, including the 21 pt label inset and the `+18` header height.

**Cost.** One controller class (~350 lines) plus a step table. Memory is one table with at most two
cells alive; the pushed stack holds five controllers of ~40 KB each, which is nothing. No new art.

**What it gives up.** The user cannot see the whole password setup at once, and cannot go back and
edit step 1 without unwinding. Five pushes for one conceptual act feels long on a 3.5-inch screen —
this is the honest cost of the idiom, and it is the cost the original accepted for login.

---

## Option B — One form, one Done

`svg/privacy-security-b.svg`

All four fields of the 2SV flow live in a single group on a single screen, stacked like the
original's profile name editor and login inputs (`LoginInputDivider` hairlines between fields, or
the grouped plate's own hairlines when the fields are grouped rows). One blue `Done` commits
everything; the recovery-code screen is the only push that remains, because the code cannot exist
before the e-mail is sent.

**Layout as drawn.** Nav title `Two-Step`, back `Privacy`, blue `Done` 46 x 30 at x 269. Caption
above the group at x 20, y 82, two lines. The group starts at y 114 and is 4 rows x 44 = 176 tall.
Each row: label at x 20 in bold 17, field origin x 112, width 178, height 20, vertically centred.
Rows 1 and 2 are `secureTextEntry`; row 3 is the hint; row 4 is the e-mail with
`UIKeyboardTypeEmailAddress`. Footer caption at y 306, three lines. A second, single-row group at
y 370 carries `Turn Password Off` in bold 16 `#c1272d` — visible only when a password already
exists — with its own footer at y 426.

**Behaviour.** Tapping a row makes its field first responder; `returnKeyType = UIReturnKeyNext`
moves to the next field, the last one is `Done`. The keyboard is 216 pt tall, so with it up only
the first two rows and part of the third are visible: the table gets
`contentInset.bottom = 216` and scrolls to the active field with `scrollToRowAtIndexPath:`. That
scrolling is the price of this option and it is visible on the device — the caption explaining the
recovery e-mail is under the keyboard exactly when the user is typing the e-mail. `Done` validates
everything at once and reports the first failure as a `title:nil` alert, then focuses the offending
field. On success: `TGProgressWindow`, `setPassword`, then push the code screen if an e-mail was
given, otherwise pop.

**Reuse.** `TGSettingsViewController`'s grouped table and caption views verbatim; a single new cell
class that puts a `UITextField` in a 44 pt grouped row (the profile editor already has one at
`TGEditProfileViewController`, and it should be lifted rather than copied).

**Cost.** One controller (~250 lines), one text-field cell if the profile one cannot be shared. The
smallest of the three. Memory identical to any settings page.

**What it gives up.** Per-step validation. The user can type a mismatched re-entry and only find
out at `Done`. It also puts the destructive `Turn Password Off` on the same screen as the create
form, which the original would not have done — two moods on one screen. And the scroll-under-
keyboard behaviour is the one part of this that will feel less than solid on real hardware.

---

## Option C — A Security hub that owns the state; forms are raised modally

`svg/privacy-security-c.svg`

Split the area in two. `Privacy and Security` keeps the privacy rules it has today; a new
`Security` screen collects passcode, two-step and sessions and shows their **live state** in the
value column, so the multi-step flows never have to be navigated to be understood. Each flow is
then a modal form (interaction §4) — presented navigation controller, `Cancel` left, blue commit
right — internally structured as Option A's chain. Modality is what makes the abandon semantics
honest: a half-finished password setup is thrown away when Cancel is tapped, and the hub row goes
back to reading `Off`.

**Layout as drawn.** Under the 44 pt nav bar sits the unconfirmed-session banner: full width, 44 pt
tall, no rounded corners, one hairline `#c9b96a` along the bottom, per layout-metrics §7's ruling
for any new top-aligned banner. Title `New login: Chrome, Berlin` in bold 14, second line in 13,
both in dark ochre; two plated buttons at the right, `GroupedActionButton` (cap 24) 42 x 28 at
x 228 labelled `Yes` and `MenuRedButton` (cap 12) 38 x 28 at x 274 labelled `No`, both bold 12
white with the `(0,-1)` shadow. Yes calls `confirmSession`, No calls `terminateSession`; either
removes the banner and the table slides up by 44 with `UITableViewRowAnimationFade`.

Group 1 at y 120, three rows: `Passcode Lock` with a `UISwitch` at x 221, y 128 (the switch is
79 x 27, right inset 20); `Auto-Lock` as a value row reading `in 5 minutes` with the
`MenuDisclosureIndicator` art at x 291; `Change Passcode` as a blue action row. Footer at y 274.
Group 2 at y 314: `Two-Step Verification` → `On`, `Recovery E-Mail` → `unconfirmed` in `#c1272d`,
which is the one place a value is allowed to go red. Group 3 at y 418: `Active Sessions` →
`4 devices`.

**Behaviour.** Flipping `Passcode Lock` on raises the keypad modal immediately; flipping it off
raises the keypad in verify mode and only then clears the keychain entry. Auto-Lock is a pushed
checkmark table (Disabled / in 1 minute / in 5 minutes / in 1 hour / in 5 hours) using
`ListCheck.png`. The keypad overlay itself is a `UIWindow` at `UIWindowLevelStatusBar` shown from
`applicationDidEnterBackground` (so the snapshot the OS takes is already covered) with a 4-column
keypad of `GroupedActionButton`-plated 72 x 62 keys and four 12 pt dots above them; a wrong code
shakes the dot row by ±10 pt in 3 steps of 0.05 s, which is a `CGAffineTransform` translate and is
affordable. Rows refresh from `getPasswordState` in `viewWillAppear`, showing `...` in the value
column until the answer arrives — the same placeholder the privacy rows already use
(`TGSettingsViewController.m:1009`).

**Reuse.** `TGSettingsViewController` page machinery (add a `TGSettingsPageSecurity` case),
`TGSessionsViewController` for the sessions list and its detail push, `TGAlertView`,
`TGProgressWindow`. The banner is a plain `UIView` set as the table's `tableHeaderView`, which is
also how it can be dropped into the chat list unchanged.

**Cost.** The hub itself is a new case in an existing controller (~150 lines). The modal wrapper is
a dozen lines. The keypad window is the real work: ~300 lines and one full-screen view held for the
app's lifetime (~1.2 MB backing store at 640 x 960 — release it on unlock and rebuild on lock).
Total the largest of the three, but most of it is the passcode feature, which has to be built
whichever option wins.

**What it gives up.** A second Settings screen to find things in, and one more level of hierarchy
between the user and Blocked Users. It also spends 44 pt of a 480 pt screen on a banner that is
usually absent.

---

## Recommendation

**Option C for the hub, Option A for the flows inside it.** They are not really in conflict: C is a
statement about where state lives, A is a statement about where the seams go, and C explicitly
builds its forms out of A's chain. What C adds over A alone is the thing the catalogue keeps asking
for — a place where "2SV is on but the recovery e-mail is unconfirmed" and "there is a session you
have not confirmed" can be seen without opening anything. Those two facts are the whole point of
the feature set, and a wizard cannot display them.

Option B is the one to reject, and it is worth saying why, because it is the cheapest. Stacking
four fields into one 176 pt group works on paper and fails on the device: with the keyboard up, the
visible window is 200 pt, so the user types the recovery e-mail with the explanation of what a
recovery e-mail is hidden behind the keyboard, and finds out about a mistyped re-entry four fields
later. The original never asked two questions on one screen for exactly this reason. If schedule
forces B, at least split it into two screens of two rows each.

---

## What cannot be built on this hardware

- **A gesture-driven or animated wizard.** No interactive dismissal, no view controller transitions
  beyond push and modal on iOS 6.1.3. Any progress affordance is text in a caption, as in Option A.
- **`UIAlertController`-based prompts with an embedded text field for the passcode.** Not on iOS 6.
  `UIAlertView` has `UIAlertViewStyleSecureTextInput`, but it cannot show a footer explaining the
  rules, so the passcode entry stays a full screen.
- **Biometric unlock.** No Touch ID on a 4S, and no `LocalAuthentication` framework before iOS 8.
  The passcode is the only lock; there is nothing to design around a fingerprint.
- **A blurred or vibrant privacy screen over the app snapshot.** No `UIVisualEffectView`. The lock
  overlay is opaque; the only period-correct alternative is the `Linen.png` / `DarkLinen.png`
  ground already in the bundle.
- **Live session geolocation on a map.** `MKMapView` exists but costs several megabytes of tiles
  and a network round trip per session row; on 512 MB with one core this is not affordable in a
  list. Session detail shows the country and IP as text, which is all TDLib gives us anyway.
- **The full modern report flow as a server-driven tree of arbitrary depth.** `getChatReportOptions`
  can return nested option sets; a table that pushes a fresh copy of itself per level is buildable,
  but the free-text comment step needs a `UITextView` over a 216 pt keyboard on a 480 pt screen,
  which leaves 200 pt. The reduced version is: one level of options, then a single-line reason
  field in a 44 pt grouped row. Deeper trees collapse to their first level and send the parent
  option id.
- **A password strength meter or any live-validating chrome.** No asset for it, and the rulebook
  forbids inventing PNGs. Strength feedback, if wanted at all, is a footer caption sentence that
  changes text — never a coloured bar.

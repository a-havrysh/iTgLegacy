# TGAlertView — original study

## Naming: the class does not exist in the 2013 source

There is no `TGAlertView` anywhere in
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`.
A full-tree grep for the identifier returns only two files, and both are a *different* class:
`TelegraphKit/TelegraphKit/TGAlertDelegateProxy.h` / `.m`.

So this study covers what actually existed in v1.1 (21024):

1. **`TGAlertDelegateProxy`** — the only alert-related type in TelegraphKit
   (`TelegraphKit/TelegraphKit/TGAlertDelegateProxy.h:11`).
2. **The house style for `UIAlertView`** — 23 call sites, which together form a very consistent,
   deliberately narrow convention. This convention is the real "component"; the visual chrome was
   left entirely to iOS 6's system alert.
3. **`TGAlertView` as it later appeared** in the twelve fork
   (`/Users/alexanderhavrysh/Git/iOS/twelve/legacy/TelegraphKit/TGAlertView.h`), which is a
   block-based wrapper around exactly this convention — and which is what our port copied.

If a reader is looking for the 2013 alert *look*, the answer is: it is the stock iOS 6
`UIAlertView` (rounded dark-blue-grey gradient panel, glossy pill buttons, 270 pt wide, drawn by
UIKit). Telegram in 2013 did not draw its own alert. The first Telegram-drawn alert is the modern
`TextAlertController`, discussed at the end.

---

## 1. `TGAlertDelegateProxy`

Header, in full (`TelegraphKit/TelegraphKit/TGAlertDelegateProxy.h:11-15`):

```objc
@interface TGAlertDelegateProxy : NSObject <UIAlertViewDelegate>
- (instancetype)initWithTarget:(id<UIAlertViewDelegate>)target;
@end
```

Implementation: a single `weak` `target` property (`TGAlertDelegateProxy.m:5`), stored in the
initialiser (`:17`), and one forwarded delegate method — `alertView:clickedButtonAtIndex:` —
guarded by `respondsToSelector:` (`:21-26`). Nothing else. It does not forward
`alertViewCancel:`, `willPresentAlertView:`, `didDismissWithButtonIndex:`, or any other
`UIAlertViewDelegate` method; those are silently dropped.

**Why it exists.** `UIAlertView.delegate` is `assign` (unsafe unretained) on iOS 6. If a controller
shows an alert and is then deallocated while the alert is still on screen, the alert messages a
dangling pointer and the app crashes. The proxy holds a `weak` reference, so after the target dies
the forward is a no-op. The proxy itself must be retained by the caller for as long as the alert is
up.

**Its one and only call site** is the paste-images confirmation in the chat:
`TelegraphKit/TelegraphKit/TGConversationController.mm:2390` creates the proxy into the strong
property `_alertProxy` (declared `TGConversationController.mm:525`) and passes it as the alert's
delegate at `:2393`. Every other alert in the app either passes `delegate:nil` (fire-and-forget
"OK" notices) or `delegate:self` and accepts the lifetime risk.

So the proxy is not a general-purpose facility; it is a one-spot patch. Reading it as "the 2013
alert architecture" would be over-reading it.

---

## 2. The 2013 `UIAlertView` house style

23 alerts, all constructed inline in controllers/actors. The rules below are all verifiable by
grep, not inferred.

### 2.1 Title is always `nil`

Every single one of the 23 `[[UIAlertView alloc] initWithTitle:...]` calls in the original passes
`initWithTitle:nil`. A grep for allocations whose title is *not* `nil` returns **zero** matches.
Examples across the whole app:

- `Telegraph/Telegraph/TGProfileController.m:4004` (photo delete error)
- `Telegraph/Telegraph/TGChatSettingsController.m:627` (terminate other sessions)
- `TelegraphKit/TelegraphKit/TGMapViewController.m:467` (location access denied)
- `TelegraphKit/TelegraphKit/TGImageViewController.mm:679` (video not downloaded)

This is the single most characteristic visual property of a 2013 Telegram alert: **a title-less
panel with one centred body paragraph and a button row.** On iOS 6 a `nil` title makes UIKit lay the
message out as the top element, in the bold 17 pt-ish system alert body face, centred, wrapping
freely — the alert grows vertically with the text, and beyond a few lines the message area becomes
its own scroller. No truncation ever happens, so long error strings are safe.

The empty-content case is not defended anywhere: `TGTelegraphConversationProfileController.mm:3447`
and `:3549` pass literal English strings rather than risk a `nil` message, and every server error
path substitutes a fixed fallback (`@"An error occured"`, `TGImageViewController.mm:700`). The
original never showed an alert with both title and message absent.

### 2.2 Two shapes only

**Shape A — notice.** `delegate:nil`, `cancelButtonTitle:` = `Common.OK`, `otherButtonTitles:nil`.
One full-width button. Frequently written as a one-line throwaway, e.g.
`Telegraph/Telegraph/TGProfileController.m:4061`:

```objc
[[[UIAlertView alloc] initWithTitle:nil message:TGLocalized(@"Settings.LogoutError")
    delegate:nil cancelButtonTitle:TGLocalized(@"Common.OK") otherButtonTitles:nil] show];
```

**Shape B — confirmation.** Two buttons; the *negative* one is the cancel button (left slot on iOS
6), the affirmative one is the single `otherButtonTitle` (right slot, rendered bold by UIKit).
Two vocabularies are in use and they are not interchangeable:

- `Common.Cancel` / `Common.OK` — for a settings-style action.
  `TGChatSettingsController.m:627`, `TGTelegraphConversationProfileController.mm:2907`,
  `TGConversationController.mm:2393`.
- `Common.No` / `Common.Yes` — for a question phrased as a question.
  `TGForwardTargetController.m:262`, `:279`, `:306`.

The strings resolve to plain `"OK"`, `"Cancel"`, `"Yes"`, `"No"`
(`Telegraph/Telegraph/en.lproj/Localizable.strings:39,40,49,50`).

The choice tracks the message grammar. Forwarding builds its message as
`"%@%@?"` — a prefix plus a name plus a question mark (`TGForwardTargetController.m:262`), so it
gets Yes/No. A statement-shaped message gets Cancel/OK. Copying one pairing onto the other
sentence shape is exactly the kind of small wrongness that makes a port feel off.

Note also the quoting rule for group targets: users are interpolated bare, chat titles are wrapped
in escaped double quotes — `"%@\"%@\"?"` at `TGForwardTargetController.m:279`.

### 2.3 Destructive actions are not marked

iOS 6 `UIAlertView` has no destructive button style, and the original does not fake one. "Leave
chat" (`TGForwardTargetController.m:279`, via `BlockedUsers.LeavePrefix`) looks identical to any
other confirmation. Do not invent a red button.

### 2.4 Result decoding is always `buttonIndex != cancelButtonIndex`

Never `buttonIndex == 1`. See `TGForwardTargetController.m:315-317`,
`TGConversationController.mm:2263`, `TGTelegraphConversationProfileController.mm:3659`.

This matters because of one inverted case: `Telegraph/Telegraph/TGTimelineController.mm:276` puts
**`Common.Yes` in the cancel slot** and `Common.No` as the other button, so that "yes, interrupt the
upload" is the left/cancel button, and its handler pops the controller when
`buttonIndex == alertView.cancelButtonIndex` (`:288`). Any code that hardcodes index 1 as
"confirmed" breaks here. The idiom is load-bearing.

### 2.5 Disambiguation by `tag`, with a shared handler

Controllers that show more than one alert set an integer `tag` and branch in a single
`alertView:clickedButtonAtIndex:`:

- symbolic constants — `TGConversationController.mm:2246` (`TGMessageWarningAlertTag`), `:2394`
  (`TGPasteImagesAlertTag`), `TGTelegraphConversationProfileController.mm:3659`
  (`TGAddMemberConfirmationAlertTag`);
- and one bare magic number — `TGTimelineController.mm:277` uses `10001`, checked at `:286`.

### 2.6 One alert at a time, enforced by hand

`TGForwardTargetController` keeps `_currentAlert` and, before showing a new one, does
`_currentAlert.delegate = nil;` then replaces it (`:261-263`, `:278-280`, `:305-307`). This both
prevents the stale alert's callback from firing and drops the unsafe-unretained back-pointer. Same
pattern with `_currentAlertView` in `TGChatSettingsController.m:627` and
`TGTelegraphConversationProfileController.mm:2907`. There is no queue: a second alert simply
supersedes the first's delegate while UIKit stacks the windows.

### 2.7 No text-entry alerts

`alertViewStyle` appears **zero** times in the original. Every piece of text input has a real UI:
the group title, for instance, is an inline `_conversationTitleField` in the profile header, which
on commit greys itself to `UIColorRGB(0x999999)` and sets the mirrored label to
`UIColorRGB(0x66727f)` while the change-title actor runs
(`TGTelegraphConversationProfileController.mm:2703-2712`). A rename dialog would have been
off-model in 2013.

### 2.8 Threading and presentation

Alerts are shown from `dispatch_async(dispatch_get_main_queue(), ...)` at the actor boundary — e.g.
`Telegraph/Telegraph/TGSynchronizeContactsActor.mm:87` (built on the main queue inside a
`TGDispatchOnMainThread`-style hop) and `TGCheckUpdatesActor.m:66`, where the delegate is the
long-lived singleton `[TGUpdateInterface instance]` precisely so no controller lifetime is
involved. `UIAlertView` presents into its own `UIWindow`, so alerts are unaffected by which
controller is on screen and survive navigation.

---

## 3. `TGAlertView` in the twelve fork

`/Users/alexanderhavrysh/Git/iOS/twelve/legacy/TelegraphKit/TGAlertView.h` — still carrying the
2013 v1.1 copyright header (`:1-7`), so this is the original's own lineage growing a wrapper. It
is a `UIAlertView` subclass (`:21`) that is its own delegate (`TGAlertView.m:29`) and converts the
delegate callback into a block:

- `initWithTitle:message:cancelButtonTitle:okButtonTitle:completionBlock:` (`.h:23`), plus an
  `otherButtonTitles:(NSArray *)` variant (`.h:24`) which adds buttons one at a time with
  `addButtonWithTitle:` after `super init` (`.m:47-48`).
- The block is `void (^)(bool okButtonPressed)` and is invoked with exactly the 2013 idiom:
  `buttonIndex != alertView.cancelButtonIndex` (`.m:63`).
- `+presentAlertWithTitle:…` (`.h:26`) forks by OS: iOS 8+ builds a real `UIAlertController`
  (`.m:73`), older builds fall back to the `UIAlertView` subclass (`.m:118`).
- Two iOS-8-era workarounds that are pure noise for us: a leading `"\n"` prepended to the message
  when there is no title on 8.0.x (`.m:39,44,57`), and a hunt through
  `UIApplication.sharedApplication.windows` for a `UITextEffec*`/`UIRemoteKe*` window so the alert
  presents above the keyboard (`.m:102-109`).
- On iOS 8+ it restyles the message to `systemFontOfSize:14.0` with `lineSpacing 2.0` when a title
  is present (`.m:76-80`) — an admission that once alerts *had* titles, the system message font was
  too big.

Crucially, twelve's wrapper preserves the 2013 semantics (title optional, cancel = negative,
`okButtonPressed` derived from the cancel index). Everything new in it is OS-compat plumbing, not a
design change.

---

## 4. Our port

Files: `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGAlertView.h` and `.../TGAlertView.m`.

Ours is twelve's class with the iOS 8+ half amputated, which is correct for a 6.1.3 target. The
API is twelve's two initialisers verbatim (`TGAlertView.h:13-14`); `+presentAlertWithTitle:` is
gone, as it should be. It also improves on twelve in two places:

- the block is `copy`d (`TGAlertView.m:56`) rather than assigned from an already-`copy` property —
  harmless, and correct;
- the block is nilled before invocation (`:79-86`) and `alertViewCancel:` is handled (`:93-97`), so
  a system-initiated dismissal (app suspend) still resolves the completion exactly once, with
  `false`. twelve does neither. This is a genuine improvement, keep it.

`-show` hops to the main queue if called off it (`:66-77`) — reasonable given our actors, and it
matches the original's practice of always showing from the main thread.

### 4.1 Defects

**D1 — 126 alerts have titles; the original had none.** Across `src`, 126 of 233 alert
constructions pass a non-`nil` title, e.g. `TGProfileViewController.m:1187` (`@"Leave Group"`),
`:1225` (`@"Clear history"`), `TGLoginViewController.m:1914` (`@"Delete Account"`),
`TGTopicsViewController.m:1795` (`@"Delete Topic"`), `TGChatListViewController.m:1942`
(`@"Add Folder"`). The original is unanimous the other way — zero titled alerts in 23 call sites.
This is the biggest single visible deviation in the whole component and it changes the silhouette
of every confirmation in the app: a titled iOS 6 alert is taller, has a bold heading line, and
reads like an OS dialog rather than like Telegram. Fix: drop the title and fold any information it
carried into the message sentence, exactly as the original does
(`TGProfileController.m:4157`, `TGForwardTargetController.m:262`).

**D2 — `TGAlertView` is bypassed by 172 raw `UIAlertView` allocations** versus 61 uses of our own
wrapper (`TGProfileViewController.m:1187`, `TGLoginViewController.m:1914`,
`TGTopicsViewController.m:554` and so on all go raw, with `delegate:self` and `tag`s 70/71/72/84…).
The raw ones reintroduce precisely the dangling-`assign`-delegate hazard that
`TGAlertDelegateProxy.h:11` existed to kill, and they scatter the confirm/cancel decoding across
dozens of tag-switch handlers. Fix: route them through `TGAlertView`'s completion block; the
`weak self` capture already used at `TGForwardPicker.m:1062` and `TGGroupMembersViewController.m:1134`
is the pattern to follow.

**D3 — 39 text-input alerts (`alertViewStyle = UIAlertViewStylePlainTextInput`)** at
`TGTopicsViewController.m:1963`, `TGProfileViewController.m:458`, `:2301`, `:2322`, `:2334`,
`TGInviteLinksViewController.m:1069`, `TGChatListViewController.m:1942`, and others. The original
has zero. Some of these are for features that did not exist in 2013 (folders, topics, link names)
so an alert is a defensible shortcut, but the ones that *do* have a 2013 counterpart should use the
2013 UI: group rename belongs in an inline profile-header field with the grey pending state at
`TGTelegraphConversationProfileController.mm:2703-2707` (`0x999999` field, `0x66727f` label), not
in a dialog.

**D4 — Yes/No versus Cancel/OK is effectively collapsed.** Our tree has 81 `cancelButtonTitle:@"Cancel"`
and exactly one `cancelButtonTitle:@"No"` (`TGForwardPicker.m:1064`, which is correct — the message
at `:1057-1059` is a question and even reproduces the quoted-group-title rule from
`TGForwardTargetController.m:279`). Everywhere else a question-shaped message gets Cancel/OK. Fix
is per-site: if the message ends in `?`, use No/Yes.

**D5 — dead iOS 8 workaround.** `TGAlertViewNormalizedMessage` (`TGAlertView.m:18-27`) prepends a
newline for `major >= 8 && minor < 1`. It can never fire on 6.1.3, and it drops twelve's `< 9`
upper bound (`twelve/legacy/TelegraphKit/TGAlertView.m:39`), so on a hypothetical iOS 9.0 it would
misfire. Delete the function and the `systemVersion` parsing with it.

**D6 — invented empty-button fallback.** `TGAlertView.m:53-54` adds an `@"OK"` button when no
buttons were supplied. Neither the original nor twelve does this, and the literal is unlocalised
where the original would use `TGLocalized(@"Common.OK")`
(`Localizable.strings:39`). Harmless, but it hides caller bugs; if kept, at least source the string
from the same place as everything else.

**Not a defect:** `initWithTitle:nil` at `TGForwardPicker.m:1063`, `TGGroupMembersViewController.m:1135`,
`TGStoriesViewController.m:497` etc. — 80 sites already follow the original's title-less rule. Those
are right.

---

## 5. What it became

**Modern client.** The alert is now Telegram-drawn:
`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS/submodules/Display/Source/TextAlertController.swift`,
an `AlertController` over ASDisplayKit nodes. The lineage is still visible — panel width is a
hardcoded `270.0` (`:6`), the same width UIKit used in 2013 — but everything else is new:

- Content insets `18 pt` on all four sides (`:359`); action buttons `44 pt` tall (`:372`).
- Title is optional and clamped to 4 lines with tail truncation (`:207-208`); the message node is
  unlimited (`:218`). Same priority order as 2013, now explicit.
- Buttons carry semantic types — `genericAction`, `defaultAction`, `destructiveAction`,
  `defaultDestructiveAction` (`:8-13`) — with the default one drawn semibold (`:113-123`). This is
  the thing iOS 6 could not express and the original therefore left unsaid (§2.3).
- **Automatic horizontal→vertical stacking**: if any button's title lays out taller than
  `44 * 0.6667` at `width/count`, the whole row flips to a vertical stack (`:376-386`, heights at
  `:392-397`). This is the answer to "what happens when the button label is long", a case the 2013
  code simply never hit because it only ever used OK/Cancel/Yes/No.
- `dismissOnOutsideTap` (`:466`) — tap-to-dismiss, which `UIAlertView` never had. twelve was already
  reaching for it: `TGAlertViewController.backgroundTapped` (`twelve/.../TGAlertView.h:17`) digs into
  `UIAlertController`'s private dimming view, matching it by
  `[UIColor colorWithWhite:0.0 alpha:0.4]` (`twelve/.../TGAlertView.m:20-23`).

Which changes were forced and which were taste: theming (day/night, custom fonts,
`theme.baseFontSize`) and destructive styling were **forced** — you cannot theme a system alert, and
Telegram grew a lot of destructive actions. Vertical stacking was forced by longer localised button
labels. Outside-tap dismissal and the switch to a drawn panel are taste, and twelve's private-API
hack shows the desire predated the capability.

**For us:** none of this should be back-ported. On iOS 6 the system alert *is* the period-correct
artwork. What we should back-port is the *discipline* the modern code makes explicit and the 2013
code kept by convention: no titles, negative action in the cancel slot, one alert at a time, decide
by `cancelButtonIndex`.

---

## Rebuild checklist

1. Use the stock `UIAlertView`; draw nothing.
2. `title: nil`, always. Message is one sentence, ending in `?` only if you intend Yes/No.
3. Notice = `delegate:nil`, `cancelButtonTitle:"OK"`, no other buttons.
4. Confirmation = cancel slot holds the negative ("Cancel" or "No"), other button holds the
   affirmative ("OK" or "Yes"); pick the pair to match the sentence grammar.
5. Decide with `buttonIndex != alertView.cancelButtonIndex`, never a literal index — the inverted
   Timeline case (`TGTimelineController.mm:276-289`) is the proof.
6. Never mark a button destructive.
7. Never put a text field in an alert.
8. One alert per controller: keep it in an ivar, `delegate = nil` the old one before showing a new
   one.
9. Show on the main thread; if the delegate can outlive the controller, use a weak proxy
   (`TGAlertDelegateProxy.h:11`) or, better, our block-based `TGAlertView`.

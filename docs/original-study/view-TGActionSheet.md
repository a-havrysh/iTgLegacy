# TGActionSheet — study of the original (and of the fact that it did not exist)

## 0. The headline: there is no `TGActionSheet` in the 2013 source

I searched the whole of `telegram_iphone.src` for the name and for anything sheet-shaped:

```
$ find . -iname "*ActionSheet*"      -> no matches
$ find . -iname "*Sheet*"            -> no matches
```

The v1.1 client has no custom action-sheet class of any kind. What it has, in 17 files, is
**bare `UIActionSheet` from UIKit**, constructed inline at each call site, driven by
`UIActionSheetDelegate` on the presenting controller and disambiguated by an integer `tag`.
There is no subclass, no category, no `UIAppearance` customisation of `UIActionSheet` anywhere
in the tree (`grep -rn "UIActionSheet appearance"` -> nothing). The visual language of the
2013 action sheet is therefore *literally* the iOS 6 system action sheet, pixel for pixel,
and the correct way to be faithful to it is to keep using `UIActionSheet` — which our port does.

The closest thing to a shared abstraction in the original is
`TelegraphKit/TelegraphKit/TGAlertDelegateProxy.h/.m`, and note that it proxies
`UIAlertViewDelegate`, not `UIActionSheetDelegate` — it exists only so a controller can hand an
alert a delegate that holds the real target weakly
(`TGAlertDelegateProxy.m:5-7`, `weak` target; `TGAlertDelegateProxy.m:22-27`). Sheets never got
that treatment; every controller was its own sheet delegate.

The name `TGActionSheet` is real, but it belongs to a **later** Telegram: it appears in
`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGActionSheet.h`. Our
`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGActionSheet.h/.m` is recognisably descended from
that file (same `TGActionSheetAction`, same `initWithTitle:actions:actionBlock:target:`,
same `canBecomeFirstResponder`/`resignFirstResponder` overrides returning `false`). So our class is
an import from the future that wraps the 2013 primitive. That is a defensible choice — it is the
same *rendering*, just a nicer API — and the rest of this document is about the behaviours the
original got out of that primitive that our wrapper does not reproduce.

---

## 1. What the component is for

A modal, bottom-anchored list of one-tap choices, used in the original for exactly four jobs:

1. **Destructive confirmation.** Log out (`Telegraph/Telegraph/TGProfileController.m:3032`),
   leave-and-delete a group (`Telegraph/Telegraph/TGTelegraphConversationProfileController.mm:1773`),
   clear conversation history (`TelegraphKit/TelegraphKit/TGConversationController.mm:7995`),
   reset all notification settings (`Telegraph/Telegraph/TGNotificationSettingsController.m:669`),
   delete group photo (`TGTelegraphConversationProfileController.mm:1871`),
   delete a photo/video from the media viewer (`TelegraphKit/TelegraphKit/TGImageViewController.mm:525-534`).
2. **Source picker.** "Take Photo / Choose Photo / Search Web Images" for avatars
   (`TGProfileController.m:3068-3074`, `TGLoginProfileController.m:473-478`,
   `TGTelegraphConversationProfileController.mm:2066-2072`) and the chat attachment menu
   (`TGConversationController.mm:2201-2214`).
3. **Contextual actions on a tapped object.** Link/phone/email options
   (`TGConversationController.mm:7331-7345`), a contact's several phone numbers
   (`TGConversationController.mm:7523-7534`), media-viewer actions
   (`TGImageViewController.mm:539-560`), a failed message
   (`TGConversationController.mm:6764-6780`).
4. **Enumerated value picker** where a whole pushed screen would be too heavy — self-destruct
   timer, seven values plus Cancel (`TGProfileController.m:5377-5390`).

Everything above is a *choice*; nothing in the original ever put a control (switch, slider,
text field) inside a sheet. That is the boundary the 2013 design keeps and that our port should keep.

---

## 2. Public surface, as the original used it

There is no public surface of our own to document, so this is the *idiom* — and the idiom is
consistent enough across 17 files that it should be treated as the component's contract.

```objc
@property (nonatomic, strong) UIActionSheet *currentActionSheet;   // TGConversationController.mm:492
```

Every controller that shows sheets holds exactly one `currentActionSheet` property
(`TGProfileController.m:357`, `TGDialogListController.mm:195`, `TGMapViewController.m:121`,
`TGImageViewController.mm:62`, `TGWebController.m:50`, `TGChatSettingsController.m:49`,
`TGNotificationSettingsController.m:60`, `TGTelegraphConversationProfileController.mm:194`,
`TGLoginProfileController.m:67`, `TGTelegraphProfileImageViewCompanion.mm:112`).

The construction idiom, verbatim from `TGConversationController.mm:2199-2214`:

```objc
_currentActionSheet.delegate = nil;                                 // 1. orphan the previous one
_currentActionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self
    cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
[_currentActionSheet addButtonWithTitle:...];                       // 2. buttons in visual order
_currentActionSheet.cancelButtonIndex =
    [_currentActionSheet addButtonWithTitle:TGLocalized(@"Common.Cancel")];  // 3. cancel added LAST
_currentActionSheet.tag = TGConversationControllerAttachmentDialogTag;       // 4. identify by tag
[_currentActionSheet showInView:self.view];
```

Four rules fall out of that, and they are all load-bearing:

**(a) `delegate = nil` before replacing.** Repeated in every single call site
(`TGConversationController.mm:2201`, `:6763`, `:7329`, `:7521`, `:7994`;
`TGProfileController.m:3065-3066`, `:5375`; `TGImageViewController.mm:523`, `:544`).
It also happens on `dealloc` — `TGConversationController.mm:671-688` copies the sheet into a local,
nils the ivar, and clears `currentActionSheet.delegate` inside a block dispatched to the main
queue. The reason is that `UIActionSheet` is retained by the window while visible, so it outlives
the controller; without the nil-out, a tap on a sheet belonging to a popped controller messages a
dead delegate. **This is the single most important behaviour in the whole component.**

**(b) Cancel is always the last button added.** Never passed as `cancelButtonTitle:` in the
initialiser except where there is also a `destructiveButtonTitle:` (see (c)). Adding it last is
what makes UIKit draw it detached at the bottom with the dark gradient.

**(c) Two construction shapes, and they order the buttons differently.**
- `initWithTitle:delegate:cancelButtonTitle:nil destructiveButtonTitle:nil` then `addButtonWithTitle:`
  in reading order — the general case, buttons appear in the order added.
- `initWithTitle:... cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Log out"` with no further
  buttons (`TGProfileController.m:3032`; `TGTelegraphConversationProfileController.mm:1773`;
  `TGConversationController.mm:7995`; `TGNotificationSettingsController.m:669`). UIKit puts the
  destructive button **first (top)** and cancel last. This is the standard two-button confirmation
  and the original always builds it this way, never by hand.
- A middle case exists: `TGImageViewController.mm:533-534` and `TGConversationController.mm:6777-6779`
  assign `destructiveButtonIndex` to a button added in the *middle* of the list, so the red
  styling floats to wherever the button sits. UIKit supports exactly one such index.

**(d) Dispatch by `tag`, then by index.** The delegate method is a single
`actionSheet:clickedButtonAtIndex:` with an outer `if (actionSheet.tag == ...)` chain
(`TGConversationController.mm:7597-7700`, `TGImageViewController.mm:577`,
`TGProfileController.m:3078`). Inside, comparison is against
`actionSheet.destructiveButtonIndex` / `actionSheet.cancelButtonIndex` rather than literals
(`TGConversationController.mm:7601`, `:7605`) whenever the button set is variable.
The first line of every such delegate method is again
`_currentActionSheet.delegate = nil; _currentActionSheet = nil;`
(`TGConversationController.mm:7599-7600`, `TGImageViewController.mm:579-580`).

**(e) Where the button set is dynamic, an index→string map is built alongside.**
`TGConversationController.mm:2203-2209` builds an `NSMutableDictionary` keyed by the `NSNumber`
of each returned button index and valued with a stable action name (`@"takePhotoOrVideo"`,
`@"choosePhoto"`, `@"searchWeb"`, `@"chooseVideo"`, `@"location"`), stored in
`_currentActionSheetMapping`, and the handler switches on the string
(`TGConversationController.mm:7663-7690`). `TGImageViewController.mm:551-556` does the same with
`_currentActionSheetButtonMapping`. **This is the ancestor of our `TGActionSheetAction.action`
string.** Our design is the same idea, promoted into a class — good.

---

## 3. Metrics, colours, artwork

There are none of ours. Every pixel is UIKit's iOS 6 `UIActionSheet`: the ~44 pt glossy buttons,
the ~20 pt grey title label, the detached dark cancel button, the dimming of the host view, the
slide-up from the bottom edge. No image in `Telegraph/Telegraph/Resources/` is used by a sheet —
the `ActionMenu*` and `Menu*` PNGs found by an `*Menu*` search
(`Resources/ActionMenuButtonMiddle@2x.png`, `ActionMenuDivider@2x.png`, `ActionMenuArrow@2x.png`,
`MenuRedButton@2x.png`, …) belong to `TelegraphKit/TelegraphKit/TGMenuView.m` (the black
copy/paste bubble over a message) and to the `TGMenuItem*` family (settings rows), not to sheets.
**Do not attach that artwork to a sheet; they are different components.**

The only appearance knob the original ever touches is `actionSheetStyle`, three times:

| Site | Style | Why |
|---|---|---|
| `TGImageViewController.mm:526` and `:546` | `UIActionSheetStyleBlackTranslucent` | the media viewer is a black full-screen surface; a default-style sheet would be a white slab on black |
| `TGConversationController.mm:6765` | `UIActionSheetStyleDefault` | explicit, redundant — defensive because this sheet can appear while other chrome is dark |
| `TGConversationController.mm:7332` | `UIBarStyleDefault` | *a bug in the original.* `UIBarStyleDefault == 0 == UIActionSheetStyleAutomatic`, not `…StyleDefault (1)`. The enums happen to coincide in effect here, so it is invisible; do not copy the line, and do not "faithfully reproduce" it. |

Rule to carry into our port: **any sheet raised from a black full-screen surface (media viewer,
camera preview) is `UIActionSheetStyleBlackTranslucent`; everything else is default.**

---

## 4. Content behaviour — the cases only real data produces

**Long title.** The only place the original defends against it is the link sheet: the title is the
URL, and it is truncated by hand before display —

```objc
if (displayUrl.length > 120)
    displayUrl = [[url substringToIndex:120] stringByAppendingString:@"..."];
```
`TGConversationController.mm:7327-7328`. Note the sloppiness that is nevertheless the real
behaviour: the *test* is on `displayUrl` (scheme already stripped) but the *substring* is taken
from `url` (scheme intact), so a `mailto:` link truncated at the boundary keeps its scheme. 120
characters is the number; it was chosen for a 320 pt sheet where the wrapped title starts eating
the button area. Scheme stripping happens first: `mailto:` -> `substringFromIndex:7`,
`tel:` -> `substringFromIndex:4` (`TGConversationController.mm:7321-7325`).

**Nil title.** The dominant case — most sheets pass `nil` and UIKit simply omits the label.
`TGConversationController.mm:6764` passes a title that is a localised string, so the two shapes
coexist; nothing special is needed.

**Empty button set.** Handled explicitly exactly once, and it is the right precedent:
`TGImageViewController.mm:553-560` builds the media-actions sheet, and if the mapping ended up
empty (no forwarding, no saving permitted) it *throws the sheet away* rather than showing a
lone Cancel:

```objc
if (buttonMapping.count == 0) { _currentActionSheet.delegate = nil; _currentActionSheet = nil; }
else { [_currentActionSheet showInView:self.view]; _currentActionSheetButtonMapping = buttonMapping; }
```

**Conditional buttons shift every index.** The failed-message sheet
(`TGConversationController.mm:6770-6779`) adds "Edit" only when the message has text
(`_messageDialogHasText`) and "Retry all (%d)" only when `undeliveredCount > 1`, so the handler at
`:7607-7645` branches on `_messageDialogHasText` before comparing indices. The count is
interpolated into the localised format string `Conversation.MessageDialogRetryAll`
(`TGConversationController.mm:6774`).

**Longest sheet in the app** is the self-destruct timer: Forever / 2s / 5s / 1m / 1h / 1d / 1w plus
Cancel, eight buttons (`TGProfileController.m:5379-5388`). On a 3.5" screen that is close to the
limit at which iOS 6 turns the sheet into a scrolling list; I did not find any code accommodating
that, so the original either fitted or accepted whatever UIKit did. **Treat "eight buttons fits"
as the observed upper bound, not as a verified safe maximum.**

**Table selection.** A sheet raised from a table row deselects the row *before* presenting —
`TGProfileController.m:5372-5373` (`[_tableView deselectRowAtIndexPath:… animated:true]`). Without
it the row stays blue behind the dimming for the whole life of the sheet.

**The keyboard is not dismissed.** `attachButtonPressed` (`TGConversationController.mm:2197-2216`)
raises the attachment sheet with no `resignFirstResponder` anywhere; on iOS 6 the sheet animates up
over the still-present keyboard. This is a genuine 2013 behaviour and it is one of the things the
later fork deliberately changed (see §7).

**Side effect on show.** `TGConversationController.mm:2216` kicks off
`[TGImagePickerController preloadLibrary]` the moment the attachment sheet appears, holding the
result in `_assetsLibraryHolder`, so that the ALAssetsLibrary permission prompt and enumeration are
already warm by the time the user picks "Choose Photo". On a 4S this is the difference between an
instant picker and a two-second stall. Worth reproducing.

**Media pauses on show.** `TGImageViewController.mm:541-544` pauses every visible page's media
before raising the actions sheet.

---

## 5. Where it is presented — `showInView:` and its argument

`showInView:` is used at every one of the ~20 presentations; `showFromRect:`, `showFromTabBar:`
and `showFromToolbar:` are used **nowhere** (grep confirms zero hits). The interesting part is the
argument, which is not always `self.view`:

- `self.view` — the default (`TGConversationController.mm:2214`, `TGMapViewController.m:785`,
  `TGImageViewController.mm:534`, `TGWebController.m:732`, `TGNotificationSettingsController.m:670`,
  `TGTelegraphConversationProfileController.mm:1775`).
- `self.parentViewController.view` — used by `TGProfileController` when it is a child of the tab
  controller, so that the sheet covers and dims the **tab bar** instead of stopping above it.
  The choice is made per call and is conditional:
  `TGProfileController.m:2993-2996`, `:3034-3037`, `:4543-4546`, `:4627-4630`, `:5149-5152` all read
  `if (<in tabs>) showInView:self.parentViewController.view; else showInView:self.view;`, while
  `:3074` presents unconditionally into the parent. Note the inconsistency inside the same file:
  `:5390` (self-destruct timer) uses plain `self.view`.
- `self.navigationController.view` — `TGDialogListController.mm:1683`.
- Somebody else's view entirely — `TGTelegraphProfileImageViewCompanion.mm:376` presents into
  `imageViewController.view`, the full-screen photo viewer it is driving.

The rule to reconstruct from this: **present into the highest view that should be dimmed.** If a
tab bar or a navigation bar would otherwise sit un-dimmed above the sheet, hand `showInView:` the
ancestor that contains it.

---

## 6. Our port — `src/TGActionSheet.h` / `src/TGActionSheet.m`

Ours is a `UIActionSheet` subclass that is its own delegate, holds an array of
`TGActionSheetAction` (title + action string + type), and fires a block. Structurally it is right,
and it is a better API than the original's tag-and-index chains. Everything below is a difference
that a user could see or a lifetime hazard.

**6.1 A second destructive action is silently demoted — and the caller's object is mutated.**
`src/TGActionSheet.m:72-78`:

```objc
if (action.type == TGActionSheetActionTypeDestructive) {
    if (hasDestructive) action.type = TGActionSheetActionTypeGeneric;   // <- mutates the caller's object
    else hasDestructive = true;
}
```

`UIActionSheet` genuinely supports only one `destructiveButtonIndex`, so *something* has to give;
the original never hit this because no 2013 sheet had two red buttons. But we do:
`src/TGLoginViewController.m:1844-1845` declares both "Reset Password" and "Delete Account" as
destructive, so "Delete Account" renders as an ordinary blue-grey button. Worse, the demotion
writes through to the `TGActionSheetAction` instance the caller created; if any call site ever
hoists its `actions` array into a static or an ivar and presents twice, the red styling is lost
permanently from the second presentation on. Two fixes, both cheap: (i) never mutate the input —
decide the destructive index locally without touching `action.type`; (ii) at the `TGLoginViewController`
call site, pick one red button (the original's precedent is that the *most* destructive action is
the red one and the other is plain), or promote that specific sheet to a custom view.

**6.2 We synthesise a Cancel button the original would not have shown.**
`src/TGActionSheet.m:83-92` appends a Cancel action whenever the caller supplied none. The original
never needed this, and in the one case where the button list can come out empty it *cancels the
presentation entirely* (`TGImageViewController.mm:553-556`). Our version, handed an empty or
fully-filtered action list, shows a sheet whose only button is "Cancel" — a dead-end modal.
Add the original's guard: if no non-cancel action survived filtering, do not present at all.
(This is defensive-only; I found no current call site that hits it.)

**6.3 Hardcoded English Cancel.** `src/TGActionSheet.m:34-40` falls back to the literal `@"Cancel"`.
The original always used `TGLocalized(@"Common.Cancel")` / `NSLocalizedString(@"Common.Cancel", …)`
(`TGConversationController.mm:2211`, `TGImageViewController.mm:534`). Our whole port is
English-only today, so this is a note, not a defect — but the string should be routed through
whatever localisation hook we do have so the key survives.

**6.4 Cancel semantics differ from the original's, in our favour.** `src/TGActionSheet.m:134-138`
implements `actionSheetCancel:` (system-initiated dismissal — incoming call, app suspension) by
replaying the cancel button's action. No original sheet implements `actionSheetCancel:` at all
(grep: zero hits), so in 2013 a system cancel produced *nothing*. Ours will, for example, call
`becomeFirstResponder` back on the login field (`TGLoginViewController.m:1624`) after an interrupted
sheet. That is better behaviour, not a fidelity break — keep it, but be aware that any call site
whose cancel branch has a side effect will now see that side effect in a case the original never
produced.

**6.5 We do not reproduce the `parentViewController.view` presentation rule.** Our call sites are
split between `self.view` (`TGProfileViewController.m:449`, `:1183`, `:2313`, …,
`TGLoginViewController.m:1628`), `self.navigationController.view`
(`TGPrivacyViewController.m:1277`, `TGTopicsViewController.m:2076`,
`TGGroupMembersViewController.m:1659`) and `self.window ?: self`
(`TGStickerPanelView.m:1001`, `:1623`). Any sheet raised from a screen that lives inside the tab
controller and is presented into `self.view` will leave the tab bar bright and untouchable-looking
under the dimming, which the original explicitly avoided (`TGProfileController.m:3034-3037`).
Worth an audit pass over the profile/settings screens specifically.

**6.6 Our teardown is stronger than the original's, and that is fine.**
`src/TGActionSheet.m:140-146` clears `delegate`, both blocks and the target in
`didDismissWithButtonIndex:`, and `target` is `weak` (`:26`), which together make the original's
mandatory `delegate = nil` dance unnecessary. Call sites that additionally do
`self.currentActionSheet = nil` inside the action block (e.g. `TGProxyViewController.m:1209`,
`TGStickerPanelView.m:998`) are belt-and-braces. The `dismissWithClickedButtonIndex:animated:`
teardown used by `TGTopicsViewController.m:993`, `TGSessionsViewController.m:143`,
`TGInviteLinksViewController.m:101` and others is correct: UIKit does not invoke
`actionSheet:clickedButtonAtIndex:` for a programmatic dismissal, so the action does not fire.

**6.7 `dismissBlock` is dead code.** Declared at `src/TGActionSheet.h:30`, consumed at
`src/TGActionSheet.m:127`, assigned by nobody. It has no ancestor in the original *or* in twelve
(twelve's header has no such property). Delete it, or the next reader will assume it is load-bearing.

**6.8 Things we get right, briefly.** Action-string dispatch instead of index arithmetic mirrors
`_currentActionSheetMapping` (`TGConversationController.mm:2203-2209`). Cancel appended last
(`src/TGActionSheet.m:92`) matches the original's ordering rule. `nil`-ing an empty title
(`src/TGActionSheet.m:44`) matches the dominant original shape. Staying on `UIActionSheet` rather
than drawing our own sheet is the correct fidelity call for iOS 6.

**6.9 Not checked against the original because it has no ancestor:**
`src/TGMessageActionsSheet.m` composes `TGPopupMenu` + `TGActionSheet` + `TGAlertView` into a
message context flow. The 2013 equivalent is `TGMenuView` (the black bubble) plus a plain sheet;
whether our composition matches is a separate study.

---

## 7. What became of it

**`twelve` (`Telegraph/TGActionSheet.h/.m`, `Telegraph/TGCustomActionSheet.h/.m`).**
Two things happened on the original's own lineage.

*First*, the inline `UIActionSheet` idiom was factored into exactly the class we imported —
`TGActionSheetAction` with title/action/type, block callback, weak target
(`twelve/Telegraph/TGActionSheet.m:41-64`). Our file is that file plus input validation
(the filtering, the demotion, the synthesised Cancel) and plus the teardown of 6.6. Two things in
twelve's version we did *not* take:
- `showInView:` is overridden to `[view.window endEditing:true]` before presenting
  (`twelve/Telegraph/TGActionSheet.m:88-92`) — the keyboard is now dismissed, reversing the 2013
  attachment-menu behaviour of §4. This is a **change of taste**, made once iOS action sheets
  stopped coexisting gracefully with the keyboard.
- `_replacedIndex` (`twelve/Telegraph/TGActionSheet.m:30, 61, 68-69`) — a hook for rewriting which
  action a tap maps to. Unused in the paths I read; ignore it.
- Header gains `TGActionSheetActionTypeLined` (`twelve/Telegraph/TGActionSheet.h:7`) and
  `disableAutomaticSheetDismiss` (`:15`). Both are meaningless under `UIActionSheet` — they exist
  only for the custom renderer below. That is the tell that the wrapper had outgrown its backing.

*Second*, and this is the real story: `TGCustomActionSheet` keeps the identical initialiser
signature (`twelve/Telegraph/TGCustomActionSheet.m:22`) and throws `UIActionSheet` away entirely,
rendering the same `TGActionSheetAction` array through `TGMenuSheetController` with
`TGMenuSheetTitleItemView` / `TGMenuSheetButtonItemView` and
`TGMenuSheetButtonTypeDefault|Destructive|Cancel` (`:28-66`). Note `dismissesByOutsideTap`,
`hasSwipeGesture`, `permittedArrowDirections` (`:31-33`) — tap-outside and swipe-down to dismiss,
plus iPad popover placement, none of which `UIActionSheet` offered. The forcing function is clear:
Apple deprecated `UIActionSheet` in iOS 8, and Telegram wanted more than one red button, arbitrary
content rows, and a sheet that survives its own theming. `disableAutomaticSheetDismiss` is honoured
here (`:53-54`) and nowhere else.

**Modern `Telegram-iOS`.** `submodules/Display/Source/ActionSheetController.swift` and friends are
the end state: a full component system — `ActionSheetItemGroup` collections separated by
`groupSpacing: CGFloat = 8.0` (`ActionSheetItemGroupsContainerNode.swift:4`), buttons at a fixed
`height: 57.0` (`ActionSheetButtonItem.swift:168`, up from UIKit's ~44 because the whole app grew a
larger type scale), a themable `ActionSheetTheme` carrying `dimColor`, `itemBackgroundColor`,
`itemHighlightedBackgroundColor`, `standardActionTextColor`, `destructiveActionTextColor` and a
user-scalable `baseFontSize` clamped to 26 (`ActionSheetTheme.swift:26-41`), and items that are no
longer only buttons — `ActionSheetSwitchItem`, `ActionSheetCheckboxItem`, `ActionSheetTextItem`.

The abandoned idea is the one that mattered most in 2013: "the sheet is a system object, so it looks
like the OS." Once Telegram had night themes and its own type scale, that stopped being a feature.
The idea that **survived** is the flat one from `_currentActionSheetMapping` — a sheet is a list of
(label, opaque action identifier, kind) triples and a single dispatch point. Our
`TGActionSheetAction` sits exactly on that line, which is why it is the right abstraction for us
even though the class name is an anachronism.

For our target — iPhone 4S on iOS 6.1.3, 2013 visual language — none of the modern evolution
applies except as a warning: the moment we want a sheet with two red buttons (§6.1), a switch in a
row, or tap-outside dismissal, we are on twelve's path and need a `TGMenuSheetController`
equivalent, not a bigger wrapper around `UIActionSheet`.

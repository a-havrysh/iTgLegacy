# TGForwardTargetController (original, 2013/2014)

Source of truth for every citation below, unless another root is named:
`/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`
(Telegram for iOS v1.1, build 21024). Paths are given relative to that root.

Files:
- `Telegraph/Telegraph/TGForwardTargetController.h` (26 lines)
- `Telegraph/Telegraph/TGForwardTargetController.m` (349 lines)

The class exists under the exact requested name, in `Telegraph/Telegraph` (not in TelegraphKit —
it depends on `TGTelegraphDialogListCompanion`, which is app-level, not kit-level).

---

## 1. What it is

It is **not** a list. It is a **shell** — a plain `TGViewController` that owns a 44 pt footer bar with a
two-button segmented group ("Chats" / "Contacts") and swaps two *real* child view controllers in and
out beneath it:

- `TGDialogListController` driven by a `TGTelegraphDialogListCompanion` with `forwardMode = true`
  (`TGForwardTargetController.m:66-70`)
- a private subclass `TGForwardContactsController : TGContactsController` created with
  `TGContactsModeRegistered | TGContactsModeClearSelectionImmediately`
  (`TGForwardTargetController.m:73-75`)

That is the whole design idea, and it is the thing our port loses: the forward screen in 2013 reuses
the *actual* chat list and the *actual* contacts list, with all of their cells, section index, search
bar, avatar loading and empty states, and only re-routes what a tap means. It does not reimplement
either list.

Both children get `customParentViewController = self` (`:70`, `:75`, `:93`, `:98`) — the mechanism by
which a `TGViewController` reports a parent other than the UIKit one, so the children still find the
navigation bar/title of the shell.

The `TGForwardContactsController` subclass overrides exactly one method: `singleUserSelected:` becomes
an ActionStage message `userSelected` with `@"user"` in the options
(`TGForwardTargetController.m:25-28`).

## 2. Public surface

```objc
@property (nonatomic, strong) NSString *controllerTitle;      // .h:17
@property (nonatomic, strong) NSString *confirmationPrefix;   // .h:18
@property (nonatomic, strong) ASHandle *actionHandle;         // .h:20  (internal watcher)
@property (nonatomic, strong) ASHandle *watcherHandle;        // .h:21  (caller's watcher — the result channel)
- (id)initWithMessages:(NSArray *)messages;                   // .h:23
- (id)initWithSelectBlockTarget;                              // .h:24
```

Two modes, one class:

| | `initWithMessages:` | `initWithSelectBlockTarget` |
|---|---|---|
| `_blockMode` | false | true (`:102`) |
| title | `Conversation.ForwardTitle` = "Forward" (`:143`, `en.lproj/Localizable.strings:305`) | `BlockedUsers.BlockTitle` = "Block" (`:101`, strings:591) |
| confirmation prefix | `Conversation.ForwardToPrefix` = "Forward to " (`:64`, strings:304) | `BlockedUsers.BlockPrefix` = "Block " (`:100`, strings:590); for a group chat, `BlockedUsers.LeavePrefix` = "Leave " (`:279`, strings:592) |
| on Yes | navigates into the target conversation carrying the messages (`:335`, `:340`) | fires `blockUser` / `leaveConversation` at `_watcherHandle` (`:322-324`) |

Note the trailing space inside the localized prefixes; the message is built by plain concatenation
(`:262`), so the prefix must keep its space. This is the kind of thing that silently breaks when a
port hardcodes `"Forward to %@?"` — see §7.

## 3. Layout and metrics

`loadView` (`:139-171`):

- **Title**: `_controllerTitle` if set, else `Conversation.ForwardTitle` (`:143`).
- **Left bar button**: a `TGToolbarButton` of type `TGToolbarButtonTypeGeneric`, text `Common.Cancel`,
  `minWidth = 59`, then `sizeToFit` (`:145-152`). 59 pt is the floor, not the width: a longer
  localization grows the button. There is **no right bar button** and **no Back button** — the
  controller is always presented modally (§5), so Cancel is the only way out other than picking.
- **Footer container**: `CGRectMake(0, view.height - 44, view.width, 44)`, autoresizing
  `FlexibleWidth | FlexibleTopMargin` (`:154-155`). Height 44 is hardcoded twice (also in the
  commented-out rotation handler, `:211`).
- **Footer background**: `[[TGInterfaceAssets instance] footerBackground]`
  (`:156`) = `[UIColor colorWithPatternImage:[UIImage imageNamed:@"Footer.png"]]`
  (`Telegraph/Telegraph/TGInterfaceAssets.mm:154-162`). `Footer@2x.png` is 2×88 px = 1×44 pt, i.e. a
  vertical gradient strip exactly as tall as the bar, tiled horizontally. Because it is a pattern
  colour, it is anchored to the *container's* own origin — if the container is not exactly 44 pt tall
  and positioned at its own y=0, the gradient tiles visibly.
- **Button group**: `TGButtonGroupView`, two buttons, `sizeToFit`, then centred in the footer with
  `CGRectIntegral` and autoresizing `FlexibleLeftMargin | FlexibleRightMargin` (`:158-166`).
  `sizeToFit` gives width `80 * n + 2 * (n-1)` = **162** and height **30** in portrait, 25 if
  `_isLandscape` (`TelegraphKit/TelegraphKit/TGButtonGroupView.m:448-457`). `_isLandscape` is never set
  here, so it is 30 always. Centred in 44: y = 7.
- Child controller view: `frame = self.view.bounds`, inserted **at index 0** so the footer stays on top
  (`:200-201`), and `parentInsets = UIEdgeInsetsMake(0, 0, 44, 0)` (`:197`) — that is how the child's
  table gets its bottom content inset. The child view is full-height and *underlaps* the footer; it is
  the inset that keeps the last row reachable.

### TGButtonGroupView, as used here

`TelegraphKit/TelegraphKit/TGButtonGroupView.m`. Defaults from `commonInit` (`:167-178`):
font `boldSystemFontOfSize:12`, text colour white, shadow `UIColorRGBA(0x0e284d, 0.4)` at offset
`(0, -1)`. `_buttonsAreAlwaysDeselected` is left false, which matters: with it false the *selected*
segment keeps the highlighted artwork and a plain touch on the other segment does **not** flash
(`:285-290` — highlighted state is given the *normal* image), and the 0.25 s cross-dissolve at
`:398-421` never runs. So switching tabs in the forward screen is instantaneous, with no animation.

Artwork (all `Telegraph/Telegraph/Resources`, @2x only in this build):

| image | pixels @2x | left cap | line |
|---|---|---|---|
| `ButtonGroupLeft.png` / `_Highlighted` | 17×60 → 8.5×30 pt | 8 | `TGButtonGroupView.m:7`, `:15` |
| `ButtonGroupCenter.png` / `_Highlighted` | 10×60 | 1 | `:23`, `:31` |
| `ButtonGroupRight.png` / `_Highlighted` | 17×60 | 1 | `:39`, `:47` |
| `ButtonGroupDivider.png`, `_LeftHighlighted`, `_RightHighlighted` | 4×60 → 2×30 pt | 6 | `:55`, `:63`, `:71` |

Note the asymmetry that is easy to get wrong: the **right** cap image is stretched from cap width 1,
not 8 — `stretchableImageWithLeftCapWidth:` only ever protects the left edge in this API, and the right
button's rounded right edge survives because the stretch region is a single column at x=1 and the rest
of the 17 px is carried to the right. Copy the cap numbers literally.

The button height used at layout time is `_buttonLeftImage.size.height` = 30 pt
(`TGButtonGroupView.m:474`), and widths are `(width - separators) / count` truncated to int, with the
last button absorbing the rounding remainder (`:476-482`). Separator width comes from the image
(2 pt), not from the constant 2 used in `sizeToFit` — they happen to agree.

The divider is a three-layer stack (tags 100/101/102 = normal, left-lit, right-lit) whose alphas are
switched so the divider adjacent to the lit segment is drawn in its "lit on that side" variant
(`:215-236`, `:345-396`). One divider, three artworks, never a colour.

## 4. Behaviour

**Segment tap** (`:230-242`): index 0 → dialog list, index 1 → contacts; no-op if already current.
Note the buttons fire on `UIControlEventTouchDown` (`TGButtonGroupView.m:185`), not touch-up — the tab
switches the instant your finger lands.

**Child swap** (`setCurrentViewController:`, `:183-205`) is a full UIKit containment cycle
(`willMoveToParentViewController:` / `removeFromParentViewController` / `addChildViewController:`).
The two children are created once in `init` and kept alive across swaps, so **each tab keeps its own
scroll position, its own search text and its own loaded rows**. This is a real, visible behaviour, not
an implementation detail.

**What `forwardMode` changes in the reused dialog list**:
- Tapping a row sends `conversationSelected` to the watcher instead of navigating
  (`Telegraph/Telegraph/TGTelegraphDialogListCompanion.mm:150-156`); same for search results
  (`:347-352`, and `searchResultSelectedUser:` sends `userSelected`).
- `searchResultSelectedConversation:atMessageId:` does nothing in forward mode (`:168-176`) —
  you cannot jump to a message from here.
- The search bar loses its scope bar: `_searchBar.scopeButtonTitles = @[@"Conversations", @"Messages"]`
  is only set when **not** forward mode (`TelegraphKit/TelegraphKit/TGDialogListController.mm:527-528`).
- Cells are created with `enableEditing = ![companion forwardMode]`
  (`TGDialogListController.mm:1258`) — no swipe-to-delete in the picker.
- The selected row is deselected animated after the tap (`TGDialogListController.mm:1100-1101`).
- **Secret chats are filtered out**: every conversation with `conversationId <= INT_MIN` is dropped from
  the loaded list, from search results and from the live update path
  (`TGTelegraphDialogListCompanion.mm:531`, `:591-600`, `:730-740`). You could not forward into a secret
  chat in this build.
- Rows are 73 pt (`TGDialogListController.mm:1124`); contacts rows are 51 pt, and a non-user row
  (uid <= 0, i.e. the "invite"/action rows) is 44 (`Telegraph/Telegraph/TGContactsController.mm:1346-1359`).

**Selection → confirmation** (`actionStageActionRequested:`, `:246-313`). Three paths:

1. `userSelected` (a contact tap, or a user hit in dialog-list search): block mode fires `blockUser`
   immediately, **with no confirmation** (`:255`). Otherwise an alert:
   `"%@%@?"` of prefix + `user.displayName`, no title, buttons `Common.No` / `Common.Yes` (`:262`).
2. `conversationSelected` where the conversation is a group (`isChat && conversationId > INT_MIN`):
   alert message is `"%@\"%@\"?"` — the chat title is **quoted** — with `BlockedUsers.LeavePrefix` in
   block mode, else the forward prefix (`:274-280`). So: `Forward to "Weekend Trip"?` vs
   `Forward to Peter Smith?`.
3. Anything else (a one-to-one conversation, or a group whose title is unavailable): it resolves a
   `uid` — `conversation.conversationId` for a private chat, or the *first* participant uid for a chat
   (`:284-292`) — loads that user from the database, and **if the user is not in the database the tap is
   silently ignored** (`:294-295`, no else branch). The alert then uses `user.displayName`, not the
   conversation title (`:306`). The `_selectedTarget` is still the conversation when it was a chat
   (`:303`).

`_currentAlert.delegate = nil` before each new alert (`:261`, `:278`, `:305`) — tapping two rows fast
orphans the first alert instead of double-firing.

**Confirmation accepted** (`alertView:clickedButtonAtIndex:`, `:315-347`). Non-block mode does two
things, in this order:

1. Sends `willForwardMessages` to `_watcherHandle.delegate` with `@{@"controller": self,
   @"target": _selectedTarget}` (`:328-330`) — this is the *caller's* cue to get out of the way, not a
   result callback. The conversation companion answers it by dismissing the modal
   (`TGTelegraphConversationCompanion.mm:4413-4416`); the image viewer answers it by hiding itself and
   dismissing the whole media chrome (`TGTelegraphImageViewControllerCompanion.mm:684-700`).
2. Calls `[[TGInterfaceManager instance] navigateToConversationWithId:… forwardMessages:_messages
   animated:false]` (`:335`, `:340`), which routes to the full form with `clearStack:true`
   (`TGInterfaceManager.mm:91-94`).

**So the original never sends anything from this screen.** It carries the message array into the target
conversation controller, replaces the navigation stack, and lands the user *inside the destination
chat* with no animation. The forwarded messages are composed there. This is the single most important
behavioural fact about the component and it is the one our port does not implement.

The forward screen itself never calls `dismiss` on success — only `doneButtonPressed`/`dismissSelf`
does, via `self.presentingViewController` (`:220-228`). The success dismissal is the caller's job,
which is why `willForwardMessages` carries `self` under `@"controller"`.

`shouldBeRemovedFromNavigationAfterHiding` returns true (`:134-137`). Navigation-bar style and
hidden-ness are delegated to whichever child is current (`:120-132`), so the bar tracks the child
rather than the shell.

**Teardown**: `dealloc` calls `doUnloadView`, which detaches the current child and nils out both
children's views if loaded (`:173-181`), clears the alert delegate, breaks the `customParentViewController`
back-references and resets the ActionStage handle (`:107-118`).

## 5. Presentation

Always modal, always inside a `TGNavigationController` built with `blackCorners:false`, and there is an
explicit iOS ≤ 5 workaround that hand-animates a 0.45 s slide-up before presenting non-animated
(`TGTelegraphConversationCompanion.mm:1865-1896`; identical block in
`TGBlockedUsersController.mm:450-484`). On iOS 6 the `else` branch runs: plain
`presentViewController:animated:true`. Call sites:

- `TGTelegraphConversationCompanion.mm:1865` — forward from the chat's selection mode; messages are
  sorted by date ascending first (`:1858-1862`).
- `TGProfileController.m:4565`, `TGTelegraphImageViewControllerCompanion.mm:379` — forward a single message.
- `TGBlockedUsersController.mm:452` — `initWithSelectBlockTarget`.

Every call site sets `forwardController.watcherHandle = _actionHandle` immediately after init.

## 6. Edge cases the original actually handles

- **Long chat title / long contact name**: not handled here at all — it is the reused cells'
  problem. In the alert, the concatenated message is whatever `UIAlertView` wraps.
- **Group with no participants loaded**: `uid` stays 0, `loadUser:0` returns nil, tap does nothing (`:288-295`).
- **Secret chats**: filtered out of the list entirely (§4), so they can never be a target.
- **Empty message array**: `initWithMessages:` accepts it; the conversation companion guards with
  `if (messagesToForward.count != 0)` before presenting (`TGTelegraphConversationCompanion.mm:1857`).
- **Dialog list not yet loaded**: `init` kicks off `/tg/dialoglist/(INT_MAX)` with `limit = 25`
  (`:71`), i.e. the picker asks for only the 25 most recent conversations up front and pages from there.
- **Rotation**: the handler that would reposition the footer is commented out (`:207-216`); the footer
  survives rotation on autoresizing masks alone.

## 7. Our port: `src/TGForwardPicker.m`

Ours is a single `UITableViewController` (`/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGForwardPicker.h:6`)
that reimplements both lists inline, 1136 lines. Architecturally that is the opposite choice from the
original, and given that our chat list and contacts list are separate classes that we do not reuse
here, the duplication is where most of the drift below comes from.

**What is right, and worth saying so:** the footer is rebuilt faithfully — 44 pt, `Footer.png` pattern,
80/2/30 geometry, `boldSystemFontOfSize:12`, white text, shadow `0x0e284d @ 0.4` at `(0,-1)`,
touch-down target, three-layer divider with tags 100/101/102, and the exact cap widths 8/1/1/6
(`TGForwardPicker.m:14-17`, `:692-815`). Cancel with a 59 pt floor is there (`:306-312`). The
Chats/Contacts tabs preserve their own scroll offset and query (`:821-836`), which is a deliberate and
correct emulation of the two-live-children behaviour. Row heights 73/51 match
(`:10-11` vs `TGDialogListController.mm:1124`, `TGContactsController.mm:1354`). The confirmation is
title-less with No/Yes and quotes group titles (`:1056-1074`).

### Defects, in severity order

1. **It is pushed, not presented, at four of five call sites — and then it cannot dismiss itself.**
   `TGChatViewController.m:6197`, `:9068`, plus `TGProfileViewController.m` and
   `TGStarsViewController.m`, `TGInviteLinksViewController.m` all do
   `[self.navigationController pushViewController:picker animated:YES]`, while `cancel` (`:855-858`)
   and `finishWithChat:` (`:1119-1125`) both call `dismissViewControllerAnimated:`. On a pushed
   controller that call forwards to the presenting controller, so it either does nothing or tears down
   an unrelated modal. Since `viewDidLoad` also replaces the left bar button with Cancel (`:312`),
   killing the Back chevron, a pushed picker can trap the user. The original is modal at every call
   site (§5). Fix: present it in a `UINavigationController` everywhere, as
   `TGMediaViewController.m:1661-1663` already does, or keep the Back button when pushed.

2. **After picking, we stay where we were; the original goes into the destination chat.** Ours sends
   via `forwardMessages:fromChat:toChat:` and dismisses (`TGChatViewController.m:6188-6195`); the
   original navigates to the target with `forwardMessages:` and `clearStack:true`
   (`TGForwardTargetController.m:335`, `:340`, `TGInterfaceManager.mm:91-94`). This is a visible,
   whole-flow difference. It is defensible — the modern client behaves like ours (§8) — but it should
   be a recorded decision, not an accident.

3. **The toolbar is parented to the navigation controller's view.** `viewWillAppear:` adds
   `_toolbarContainerView` to `self.navigationController.view` and `viewWillDisappear:` removes it
   (`:839-853`). The original keeps it inside its own view with the child inserted at index 0 (`:170`,
   `:201`). Consequences a user can see: the bar does not travel with the push/present animation, it
   remains over any controller pushed on top until `viewWillDisappear` fires, and because the pattern
   colour is anchored to the container it can end up mis-registered if the frame is recomputed
   against a nav view of a different height. Move it into `self.view`.

4. **Secret chats are not excluded.** The original drops every conversation with
   `conversationId <= INT_MIN` from the forward list in three places
   (`TGTelegraphDialogListCompanion.mm:531`, `:591`, `:730`). Ours lists whatever `[TGClient shared].chats`
   returns (`:484-508`). If our client surfaces secret chats, they will appear as forward targets, which
   the original deliberately forbade.

5. **Confirmation text is hardcoded English with no prefix indirection.**
   `"Forward to \"%@\"?"` / `"Forward to %@?"` (`:1057-1059`) versus the original's
   `confirmationPrefix` + name, where the prefix carries its own trailing space and is swappable to
   "Block " / "Leave " (`:262`, `:279`). We have no block-target mode at all — the original's second
   init is a whole second product surface (`TGBlockedUsersController.mm:452`) that our port has not
   ported. Not a bug today; note it before someone builds "Blocked users" and reimplements the picker
   a third time.

6. **Group-quoting rule differs.** The original quotes only when
   `conversation.isChat && conversationId > INT_MIN` (`:274`); ours quotes on `row[@"isGroup"]`
   (`:1056`). Close, but ours will quote a supergroup/channel title where the original's rule was about
   legacy chats. More importantly, for a private conversation the original resolves the user and uses
   `user.displayName` (`:306`), while ours uses the chat-list title (`:1055`); these differ whenever
   the chat title is not the contact's display name.

7. **We invented empty states the original does not have here.** "You have no conversations yet" /
   "Start messaging by picking someone from the Contacts section." / "No results"
   (`:578-590`). Nothing in `TGForwardTargetController.m` or in the forward-mode paths of
   `TGDialogListController.mm` produces such a panel — the picker simply shows the reused list's own
   (empty) table. Either delete these, or accept them as our own addition and record it; do not claim
   period authenticity for the wording.

8. **The Chats tab search behaves differently from the original.** Ours filters the loaded chat array
   locally by title (`:534-556`). The original's forward-mode search is the dialog list's real search
   — server-side conversation search with the scope bar suppressed
   (`TGDialogListController.mm:527-528`), also matching users (`TGTelegraphDialogListCompanion.mm:347-352`).
   Visible difference: typing a contact's name in the Chats tab finds them in the original even without
   an existing conversation, and finds nothing in ours.

9. **Minor: the segment tab switch does not restore selection state on the divider correctly when the
   tab is re-tapped while already selected.** Ours early-returns (`:818-819`), same as the original
   (`:234`, `:239`) — this one is fine. But ours sets the *same* image for normal and highlighted on
   the selected button (`:792-793`), whereas the original leaves the un-selected button showing its
   normal artwork under a finger too (`TGButtonGroupView.m:288`). Equivalent in effect; no change needed.

10. **Minor: avatar refresh reloads the whole table per downloaded file** (`:659`). The original's
    reused cells update themselves. On a 4S with a long chat list this is a visible stutter while
    avatars stream in. Not a fidelity issue, a performance one.

## 8. What became of it

### `twelve` (`/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGForwardTargetController.m`, 900 lines)

Same class, same name, same shell-plus-two-children architecture, grown by roughly 2.5×. The shape of
the growth tells you what the pressure was:

- **The custom `TGButtonGroupView` is gone**, replaced by a `UISegmentedControl` skinned from a
  `presentation.images` theme pack, at `CGRectMake((width - 182)/2, 8, 182, 29)`
  (`twelve/…/TGForwardTargetController.m:438-453`, repositioned on layout at `:483`). 182×29 at y=8 in
  a 44 pt bar versus the original 162×30 at y=7. Titles are now `DialogList.TabTitle` /
  `Contacts.TabTitle`, font `TGSystemFontOfSize(13)` not bold 12, and the shadow is explicitly cleared
  (`:447-448`). That is the iOS 7 flattening arriving, plus a themeing system; it is a change of taste
  and platform, not of function. **We should stay on the original.**
- **Nine initializers instead of two** (`twelve/…/TGForwardTargetController.h:20-31`): select block
  target, select privacy target (with a placeholder and a dialogs flag), select target for broadcast
  lists, select group, send document file(s), select private/group with an excluded-id set. The
  "pick a peer" shell turned out to be the reusable part of the app, and every new feature that needed
  a peer bolted an init onto it. Predictable, and a warning: our `TGForwardPicker` will be asked to do
  the same, so its `onPicked` block API is actually the better shape.
- `skipConfirmation` (`.h:16`, used at `.m:618`, `:665`, `:727`) — the yes/no alert became optional once
  callers existed for which it was noise.
- Multi-select: `multipleUsersSelected` with `_contactsController.selectedComposeUsers` (`.m:544`).
- `forwardMessages` + `sendMessages` + `shareLink` in one init (`.h:20`) — the picker became a share
  sheet.

### Modern Telegram-iOS

The concept split in two, and the 2013 class is the ancestor of both:

- **`PeerSelectionControllerImpl`**
  (`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS/submodules/TelegramUI/Components/PeerSelectionController/Sources/PeerSelectionController.swift:14`)
  is the direct descendant: it still composes a chat list and a contacts list behind a selector, and the
  two booleans `hasChatListSelector` / `hasContactSelector` (`:62-63`, `:104-105`) are literally the two
  buttons of `TGButtonGroupView` turned into parameters. It gained `multipleSelection` and
  `multipleSelectionLimit` (`:71`, `:119`, `:152`, `:197`) and a topic-selection recursion for forums
  (`:320-341`), and the result is a `peerSelected: ((EnginePeer, Int64?) -> Void)` closure (`:22`) —
  the same "hand the caller a target and get out of the way" contract as `willForwardMessages`, minus
  ActionStage.
- **`ShareController`** (`/Users/alexanderhavrysh/Git/iOS/Telegram-iOS/submodules/ShareController/Sources/`)
  is what forwarding itself became: a bottom sheet with a peer grid, multi-select, an inline comment
  field (`ShareInputFieldNode.swift`) and a send action button, whose subtitle enumerates the selected
  peers (`SharePeersContainerNode.swift:692-700`). No confirmation alert, no navigation into the target,
  no full-screen takeover.

Two changes were forced rather than aesthetic, and both are worth understanding even though we do not
copy them:
1. **The yes/no alert per target died** because multi-select made it absurd; the confirmation moved into
   the explicit "Send" button. Our port keeps the alert, which is right for 2013.
2. **"Navigate into the target chat" died** because a share sheet can have several targets and because
   yanking the user out of their current context proved hostile. Our port already behaves the modern
   way (defect 2 above) — the honest position is that this is a deliberate modern-interaction choice,
   consistent with the project's brief, and it should be written down as such rather than left looking
   like a port error.

## 9. Genuinely ambiguous / not determinable from the source

- The exact rendered colours of the button-group artwork: I read pixel dimensions and cap widths from
  the PNGs but did not sample their pixels. Every colour claim above is from code
  (`UIColorRGBA(0x0e284d, 0.4)`, white text), not from the images.
- Whether the footer pattern lines up perfectly under a 44 pt bar was inferred from
  `Footer@2x.png` being 2×88 px; I did not render it.
- The landscape 25 pt button height exists in `TGButtonGroupView` but `_isLandscape` is never set by
  this controller, so I cannot say what the original actually looked like rotated — and the rotation
  handler is commented out (`:207-216`), which suggests it was unfinished rather than deliberate.

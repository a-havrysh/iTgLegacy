# Writing code well, independent of language

This chapter is about craft that would apply in any language: naming, size, boundaries,
dependency direction, error handling, state, duplication, headers, and reviewability.
The Objective-C specifics live in the companion chapter.

## The constraint that shapes every rule here

There is no test target, no simulator, and no debugger on the device. The only verification
is a device build followed by a human tapping through the app on a 4S. That single fact
reweights most of the standard advice:

- A refactor whose correctness argument is "the tests still pass" is unavailable. Every
  change must be **locally verifiable by reading** — the reviewer must be able to hold the
  before and after in their head at once and see that they agree.
- Wide mechanical refactors are more dangerous here than in a tested codebase, and narrow
  ones are cheaper. So the retrofit advice below is deliberately conservative: most rules
  are marked *new code only*, and the handful marked *retrofit* were chosen because either
  the compiler catches a mistake or the change is a pure textual substitution.
- Conversely, rules that make a bug **visible while reading** — a completion block that
  obviously fires on every path, a state machine you can enumerate — pay for themselves more
  here than they would in a project with a test suite. That is why several of them are
  strict.

The codebase is ~108,000 lines of Objective-C across ~100 source files and 31 screens,
written by roughly 400 agents who each saw one file. Its characteristic damage is not bad
code; most individual files are careful. It is *incoherence between files that never met*.
The rules below target that.

Each rule ends with a **Check** (how to tell mechanically whether a file violates it) and a
**Scope** (`new code only`, `retrofit`, or `retrofit on touch` — meaning: fix it in the
region you are already editing, do not go hunting).

---

## 1. Naming

### 1.1 One concept, one name, project-wide

The same helper exists under several names in several files because no agent could see the
others. The clearest instance: five independent byte formatters.

`TGSettingsViewController.m:108` `TGSettingsBytes`, `TGStorageViewController.m:428`
`TGHumanSize`, `TGPremiumViewController.m:1126`, `TGDeviceViewController.m:45`,
`TGMediaViewController.m:44`, plus an inline one at `TGChatViewController.m:1434`. They
disagree: one floors sub-kilobyte values to `"1 KB"`, another prints `"512 B"`, another
starts at MB. The user sees a file reported as `0.5 MB` on one screen and `512 KB` on
another.

**Rule.** Before writing a helper, grep for the concept, not the name you were about to use.
If a helper for that concept exists anywhere in `src/`, call it. If it exists but is `static`
in another `.m`, see rule 5.3.

```objc
// wrong - a sixth formatter, in a seventh file
static NSString *TGStoryBytes(long long bytes) { ... }

// right - the one that already exists, promoted to a shared header (see 5.3)
#import "TGFormat.h"
NSString *text = TGFormatBytes(bytes);
```

**Check.** For any new `static` function, run
`grep -rn --include='*.m' -iE "^static .*(<noun>)" src/` for the noun in the name (`bytes`,
`size`, `date`, `duration`, `avatar`, `initials`, `colour`). More than one hit for the same
concept is a violation.
**Scope.** New code only for the general rule. The specific byte/date/colour families are
listed in §11 as worth retrofitting.

### 1.2 A name may not lie about its contract

Worse than duplication is duplication that disagrees. `TGString(id)` is defined in four
files:

| File | Behaviour on non-string |
| --- | --- |
| `TGClient+Groups.m:12` | returns `@""` |
| `TGClient+Contacts.m:12` | returns `@""` |
| `TGClient+Stickers.m:19` | returns **`nil`** |

An agent who learned `TGString` in one file and wrote `TGString(d[@"title"]).length` in
another gets a silent zero instead of a crash — or the reverse, depending which file they
landed in. This is the single most dangerous naming failure in the codebase, because reading
the call site cannot reveal it.

**Rule.** A given identifier has exactly one behaviour in the whole tree. If two definitions
of a name would differ in *any* observable way — return value on the empty case, whether it
nil-checks, whether it copies — one of them must be renamed or both must be merged.

**Check.**
`grep -rhn --include='*.m' -E "^static [A-Za-z].*\(" src/ | sed 's/^[0-9]*://; s/ *{$//' | sort | uniq -c | sort -rn`
Any count above 1 is a candidate; open each and compare the bodies. Today this reports
`TGIsError` ×4, `TGString` ×3, `TGDict` ×3, `TGArray` ×3, `TGInt64` ×2.
**Scope.** **Retrofit** — this family specifically. It is a small, closed set and the
compiler catches the mechanical half of the change.

### 1.3 Prefix scope tells the reader where a symbol lives

The codebase already does this well and it should be preserved: `TG` for anything visible
across files, a screen-specific infix for file-local statics (`TGTopicDate`, `TGWLAppendRich`,
`TGCMDict`, `TGASApplyFill`, `TGStorageDiskFreeBytes`), and `k` for file-local layout
constants (`kBubbleMaxW`, `kMemberPageSize`).

**Rule.** A `static` symbol carries its file's infix. A symbol in a header carries `TG` and
nothing else. Do not introduce a third convention.

**Check.** In any `.m`, every `static` function name should start with `TG<Infix>` where
`<Infix>` is stable within the file. A bare `TGFoo` on a `static` is a symbol that either
wants to be shared (promote it) or wants an infix.
**Scope.** New code only. Renaming existing statics is churn with no reader benefit.

### 1.4 Names carry units and width

`NSInteger` is 32 bits on armv7. Telegram ids are 64-bit. A name that does not say which it
is invites the wrong type.

**Rule.** Anything holding a chat id, message id, user id, supergroup id or file-size in
bytes is named so the width is obvious (`chatId`, `messageId`, `bytes`, `untilDate`) and is
declared `int64_t`/`long long`, never `NSInteger` or `int`. Durations say their unit
(`seconds`, `ms`, `unix`). Lengths in points say `points` or use a `k…W`/`k…H` layout name.

```objc
// wrong
NSInteger chatId = [dict[@"chat_id"] integerValue];   // truncates on armv7

// right
int64_t chatId = [dict[@"chat_id"] longLongValue];
```

**Check.** `grep -rn --include='*.m' -E "(NSInteger|int) +[a-zA-Z]*(chatId|messageId|userId|Id) *=" src/`
must be empty. Also grep for `integerValue]` applied to a key ending `_id`.
**Scope.** **Retrofit.** It is a correctness bug, the grep is exact, and the fix is
mechanical and compiler-checked.

---

## 2. Size

Size limits are not aesthetics here. A 10,000-line file cannot be held in an agent's context
alongside the files it talks to, which is precisely how the duplication in §1 happened.

### 2.1 A method is at most 60 lines; over 100 is a defect

The median method in `src/` is 11 lines, which is healthy. 186 methods exceed 60 lines and 54
exceed 100. The extremes:

| Lines | Location |
| --- | --- |
| 746 | `TGChatViewController.m:7595` `tableView:cellForRowAtIndexPath:` |
| 504 | `AppDelegate.m:267` `application:handleOpenURL:` |
| 275 | `TGIcons.m:394` `menuGlyphNamed:` |
| 244 | `TGClient.m:236` `handleUpdate:` |

**Rule.** A new method is at most 60 lines between its braces. Above that, split at the
`if`/`switch` arms — one arm, one method, named for the case it handles.

The three shapes that legitimately run long, and what to do instead:

- **A dispatch over a string or enum** (`handleUpdate:`, `menuGlyphNamed:`) — this is a table
  in disguise. It stays one method only if every arm is one or two lines and delegates. An
  arm with a body over five lines becomes `- (void)handleUpdateNewMessage:(NSDictionary *)u`.
- **A cell builder** — split by message kind: `configurePhotoBubble:`, `configureFileBubble:`.
  The 746-line one is the worst reviewability problem in the tree; nobody can diff it.
- **A `loadView` / `setupUI`** — split into `buildHeader`, `buildInputBar`, `buildTable`,
  each returning or wiring one subtree. `TGChatViewController` already does this partially
  (`buildInputBar:` at 193 lines still needs another cut).

**Check.**
```
python3 -c "
import re,glob
for f in glob.glob('src/*.m'):
    L=open(f,errors='ignore').read().split('\n'); s=None
    for i,l in enumerate(L):
        if re.match(r'^[-+]\s*\(',l): s=i
        elif l.startswith('}') and s is not None:
            if i-s>60: print(i-s,f,s+1,L[s].strip()[:60])
            s=None"
```
**Scope.** New code only, plus **retrofit on touch**: if you are editing inside a >100-line
method, extract the part you are changing into a named method first, in a separate commit, so
the behaviour change is reviewable on its own (see §9.1).

### 2.2 A file is at most ~1,500 lines and holds one top-level class

`TGChatViewController.m` is 10,229 lines and defines eight `@implementation`s, including a
full-screen photo browser (`TGPhotoBrowserView`, `TGPhotoPageView`), a web-page reader
(`TGInstantViewController`, 370 lines), a message-info screen
(`TGMessageInfoViewController`), and a reactions list (`TGMessageReactionsViewController`).
None of those are the chat.

**Rule.** A `.m` file holds one public class plus the private views that *only that class
draws*. Anything with its own screen, its own navigation push, or its own network calls gets
its own file pair. A private class over ~250 lines gets its own file pair regardless.

Concretely, the four extractions worth doing from `TGChatViewController.m`, in order of how
cleanly they cut:

1. `TGInstantViewController` (lines 378–751) → `TGInstantViewController.{h,m}`. Self-contained,
   pushes itself, no chat state.
2. `TGMessageReactionsViewController` (1933–2261) → own pair.
3. `TGMessageInfoViewController` (1352–1932) → own pair.
4. `TGPhotoBrowserView` + `TGPhotoPageView` (752–1071) → `TGPhotoBrowser.{h,m}`.

That is roughly 1,700 lines out of the file for four `#import`s in and no behaviour change.

**Rule.** A file over 1,500 lines that is *not* being split still gets `#pragma mark -`
sections every logical group. `TGChatViewController.m` has 42 of them, which is the only
reason it is navigable at all; keep that up in any file you grow.

**Check.** `wc -l src/*.m | sort -rn` and `grep -c '^@implementation' <file>`. More than one
`@implementation` of a class with a `ViewController` suffix in a single file is always a
violation.
**Scope.** **Retrofit, but only the four extractions listed above, one commit each.** A pure
cut-and-paste of a contiguous class into a new file, with no edits to the moved lines, is
verifiable by `diff` and is the rare wide change that is safe without tests. Do not
generalise this into a campaign to split every large file.

### 2.3 Four parameters is the limit

**Rule.** A method taking more than four parameters takes a small object or a dictionary of
named keys instead. Objective-C's interleaved selector keywords make five parameters *look*
readable while still being easy to transpose at the call site — and a transposed `int64_t`
pair compiles silently.

```objc
// wrong
- (void)sendPhoto:(NSData *)data chat:(int64_t)chatId thread:(int64_t)threadId
          replyTo:(int64_t)replyId caption:(NSString *)caption silent:(BOOL)silent
        protected:(BOOL)protectContent;

// right
- (void)sendPhoto:(NSData *)data caption:(NSString *)caption
          options:(TGSendOptions *)options;   // chat, thread, replyTo, silent, protected
```

Exception: two or more parameters of the *same* type in a row is already a violation at three
parameters if they are ids, because transposition is undetectable. `inChat:(int64_t)` and
`replyTo:(int64_t)` adjacent is acceptable only because the keywords differ strongly.

**Check.** Count colons in the selector. More than four, in a method you are adding, is a
violation.
**Scope.** New code only. Existing long selectors work and changing them touches every caller.

---

## 3. Grouping and module boundaries

### 3.1 The existing boundary is correct; use it

The project already has one good large-scale structure and it should be treated as law:

- `TGClient.h` — the public surface: auth state, connection state, `request:completion:`
  callers should not see, chat/user lookup.
- `TGClient+<Area>.{h,m}` — 26 categories (`+Groups`, `+Stories`, `+Payments`, …). Each owns
  one feature area's TDLib traffic and flattens TDLib's JSON into plain
  `NSDictionary`/`NSArray` shapes the UI understands.
- `TGClient+Private.h` — shared mutable state and the `request:completion:` plumbing,
  imported by the 29 files that need it and nothing else.
- View controllers — one per screen, holding *only* view state.

**Rule.** New network or model work goes into an existing `TGClient+<Area>` category, or a new
one. It does not go into `TGClient.m` (2,554 lines, already the shared-edit bottleneck the
`+Private.h` comment warns about), and it does not go into a view controller.

**Check.** A view controller `.m` that contains `@"@type"` string literals for a TDLib request
it builds itself, rather than calling a `TGClient+…` method, is a violation.
**Scope.** New code only.

### 3.2 A category header states its threading and nil contract once, at the top

`TGClient+Groups.h:8` does this in one line: *"Every completion runs on the main queue and may
be nil. Failures answer …"*. That single sentence removes an entire class of question from
every method below it.

**Rule.** Every `TGClient+<Area>.h` opens with a comment block stating: which queue
completions run on, whether completions may be nil, and what a failure looks like (nil? `NO`?
empty array?). Individual methods then only document their own oddities.

**Check.** Open the header. If the first 15 lines do not answer those three questions, it is a
violation.
**Scope.** **Retrofit.** It is comment-only, cannot break a build, and each header takes one
reading to write. Do the categories you touch first.

---

## 4. Direction of dependencies

### 4.1 The client never knows about the UI

This currently holds perfectly: no `TGClient*.m` imports any `ViewController.h`. Preserve it.

**Rule.** Dependencies point one way: `AppDelegate`/`RootViewController` → view controllers →
`TGClient` + categories → `TGClient+Private` → TDLib. Shared leaf utilities (`TGTheme`,
`TGIcons`, `TGDevice`, `TGCapabilities`, `TGDateUtils`) may be imported by anything and import
nothing above themselves.

A `TGClient` category that needs to tell the UI something posts an `NSNotification` (as
`TGUserStatusDidChangeNotification` does) or calls a block the UI installed. It never
`#import`s a screen.

**Check.** `grep -l "ViewController.h" src/TGClient*.m src/TGTheme.m src/TGIcons.m` must be
empty.
**Scope.** **Retrofit** — it is currently clean, so the retrofit cost is zero and the rule is
purely a ratchet.

### 4.2 Screens do not reach through each other

`TGSettingsViewController.m` imports 15 other view controller headers. That is defensible —
it is a menu whose whole job is to push other screens. `TGProfileViewController.m` and
`TGChatListViewController.m` import 7 each, also mostly pushes.

**Rule.** A view controller may import another view controller's header **only to allocate and
push it**. It may not read the other's properties, call its methods, or hold a strong
reference to it after presenting. Communication back comes through a block property the
presenter installs — the pattern `TGProfileViewController.h:14` already uses
(`@property (nonatomic, copy) void (^onSearchTapped)(void);`).

```objc
// wrong
TGChatViewController *chat = [[TGChatViewController alloc] init];
chat.chatId = chatId;
[self.navigationController pushViewController:chat animated:YES];
self.openChat = chat;                       // now two screens share mutable state
...
self.openChat.replyToId = messageId;        // action at a distance, unreviewable

// right
TGChatViewController *chat = [[TGChatViewController alloc] init];
chat.chatId = chatId;
chat.initialReplyToId = messageId;          // configured before push, then forgotten
[self.navigationController pushViewController:chat animated:YES];
```

**Check.** In a view controller `.m`, search for a `@property` whose type is another
`TG…ViewController`. Any such property that outlives the push statement is a violation.
**Scope.** New code only.

### 4.3 Utilities do not import screens or the client

`TGTheme`, `TGIcons`, `TGDevice`, `TGCapabilities`, `TGViewRecycler`, `TGDateUtils`,
`UIImage+WebP` are leaves. They take their inputs as parameters.

**Check.** Each of those `.m` files should import only system frameworks and other leaves.
**Scope.** **Retrofit** (currently clean; ratchet only).

---

## 5. Duplication and abstraction

### 5.1 Rule of three, with a hard exception for divergence-dangerous code

The mainstream position is Sandi Metz's: *duplication is cheaper than the wrong abstraction*,
and you wait for the third occurrence before extracting, because two data points cannot
distinguish a real pattern from coincidence
([Metz](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction),
[Rule of three](https://en.wikipedia.org/wiki/Rule_of_three_(computer_programming))).
That is good advice and it applies here — with one carve-out this codebase earns.

**Rule.** Extract on the third occurrence. Two copies stay two copies.

**Exception — extract at the second occurrence** when a silent divergence between the copies
would be *invisible at the call site*. That covers exactly three kinds of code here:

1. **Formatting the same quantity for the user** — bytes, dates, durations, counts. Two
   copies means two answers on two screens, and no reviewer looking at either screen can see
   the other.
2. **Coercing untyped TDLib JSON** — `TGString`, `TGDict`, `TGArray`, `TGInt64`, `TGIsError`.
   The `nil`-vs-`@""` split described in §1.2 is exactly this failure.
3. **A protocol constant or wire key** — a TDLib `@type` string or a UserDefaults key used in
   two files is one `extern NSString *const`, immediately.

Everything else — layout arithmetic, cell configuration, a two-line `if` ladder — waits for
three, and often should simply stay duplicated. The 41 files that build a `UIColor` from
literal components are *not* a violation; they are local constants that happen to look alike,
and hoisting them into a shared palette would create the wrong abstraction in exactly the way
Metz warns about.

**Check.** For any new helper, ask: if this copy and the other copy disagreed, would a
reviewer reading either call site notice? If no, extract now.
**Scope.** New code only for the rule; §11 lists the specific existing families worth
retrofitting.

### 5.2 If you extract, extract behaviour, not shape

Two blocks that look alike but answer different questions stay separate. The tell that you
extracted wrongly is a boolean or mode parameter added to the shared function to restore a
caller's old behaviour — the classic signal that the abstraction is wrong and the fix is to
inline it back.

```objc
// wrong - one function, two jobs, a flag to pick
static NSString *TGFormatSize(long long bytes, BOOL compact);

// right - two functions, each with one contract
static NSString *TGFormatBytes(long long bytes);        // "1.4 MB"
static NSString *TGFormatBytesShort(long long bytes);   // "1M"
```

**Check.** A shared helper whose signature grew a `BOOL`/mode parameter in the same commit
that added its second caller is a violation.
**Scope.** New code only.

### 5.3 Where a shared helper goes

There is currently no home for small cross-cutting helpers, which is *why* they were rewritten
five times. Create one, and only one:

- `src/TGJSON.h` / `.m` — the TDLib coercion set: `TGString`, `TGDict`, `TGArray`, `TGInt64`,
  `TGIsError`. Non-static, `TG`-prefixed, one documented contract each. Pick the *strictest*
  existing behaviour as the survivor and say so in the header:
  `TGString` returns `@""` (never nil), `TGDict` returns nil, `TGArray` returns `@[]`.
- `src/TGFormat.h` / `.m` — user-facing formatting: `TGFormatBytes`, `TGFormatDuration`,
  and the relative-date functions currently scattered as `TGChatDate`, `TGSavedDate`,
  `TGTopicDate`, `TGForwardDateString`, `TGStoryAgeText`.

Do not create a `TGUtils.h`. A file named for what it is not accumulates everything.

**Check.** A new `static` helper in a screen file that has no screen-specific knowledge in its
body — it reads only its parameters — belongs in one of the two files above.
**Scope.** **Retrofit for `TGJSON` (see §11); new code only for `TGFormat` beyond the byte
formatters.** The date functions genuinely differ (chat list wants `"12:04"` / `"Mon"` /
`"14.02.13"`; stories want `"3h ago"`) and merging them is a design job, not a mechanical one.

---

## 6. Error handling

### 6.1 A completion block is called exactly once on every path

This is the strictest rule in the chapter, because it is the failure a reader can be trained
to catch by eye and no other mechanism here can catch at all. It is also the documented
contract Apple imposes on Objective-C async APIs: the handler "must … be called exactly once
along all execution paths through the implementation"
([SE-0297](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0297-concurrency-objc.md)).

A live example. `TGMessageActionsSheet.m:62`:

```objc
- (void)presentAtPoint:(CGPoint)point
                inView:(UIView *)host
            completion:(void (^)(NSString *action))completion {
	if (self.presenting || host == nil)
		return;                          // <-- completion never fires
	if (self.messageId == 0 || self.chatId == 0){
		if (completion)
			completion(nil);             // <-- this path is correct
		return;
	}
	...
```

The second guard is right and the first is wrong, three lines apart. The caller waiting on
that block waits forever; the visible symptom is a chat that stops responding to long-press
after a fast double-tap, with nothing in the log.

**Rule.** Every path out of a method that takes a completion block either invokes the block or
is a documented, deliberate no-op that says so in a comment on the `return`. The
"deliberate no-op" escape exists only for re-entrancy guards, and even there, calling the
block with a failure value is preferred.

Structure it so the property is visible at a glance — a single guard clause that fires the
block, then the body:

```objc
- (void)presentAtPoint:(CGPoint)point
                inView:(UIView *)host
            completion:(void (^)(NSString *action))completion {
	if (self.presenting || host == nil || self.messageId == 0 || self.chatId == 0){
		if (completion)
			completion(nil);
		return;
	}
	...
```

**Check.** Two greps, both worth running before any commit that touches an async method:

```
# every early return inside a method that takes a completion
python3 - <<'EOF'
import re,glob
for f in sorted(glob.glob('src/*.m')):
    L=open(f,errors='ignore').read().split('\n')
    for i,l in enumerate(L):
        if not re.match(r'^-\s*\(void\)',l): continue
        sig=l; j=i
        while '{' not in sig and j+1<len(L) and j-i<10: j+=1; sig+=' '+L[j].strip()
        if 'completion' not in sig or '^' not in sig: continue
        k=j+1; body=[]
        while k<len(L) and not L[k].startswith('}'): body.append((k+1,L[k])); k+=1
        for idx,(ln,b) in enumerate(body):
            if re.match(r'^\t{1,2}return;\s*$',b):
                if 'completion' not in ' '.join(x[1] for x in body[max(0,idx-5):idx]):
                    print(f,ln,'::',sig.strip()[:70])
EOF
```

Then read each hit. Today it reports two, one of which
(`TGMessageActionsSheet.m:63`) is a real bug and one of which
(`TGClient+SecretChats.m:264`) is a correct tail-call into a nested block. The script cannot
tell them apart; a human reading five lines can.

**Scope.** **Retrofit.** The candidate set is tiny, each fix is three lines, and each is
individually reviewable.

### 6.2 Nil-check the completion, at the boundary, consistently

`TGClient+Groups.m` shows both conventions in one file: `tg_send:completion:` guards with
`if (completion)`, `tg_group:completion:` calls `completion(nil, nil, nil)` unguarded. The
second only survives because every caller happens to pass a block.

**Rule.** Every method whose header advertises `completion` as nillable guards each invocation
with `if (completion)`, or guards once at entry:

```objc
	if (!completion)
		completion = ^(NSDictionary *unused){};
```

File-private `tg_`-prefixed helpers may require a non-nil block, but must say so in a comment
on the declaration in the private `@interface`.

**Check.** `grep -n "completion(" <file>` — every hit is either preceded by `if (completion)`
on the line above, is inside a block whose enclosing method opened with `if (!completion) return;`,
or is a `tg_`-prefixed private helper.
**Scope.** **Retrofit on touch.**

### 6.3 Failure is a value, not an exception, and the value is documented

TDLib answers errors as an object with `"@type": "error"`. The convention already in place —
`TGIsError(result)` at the top of every response block, then a documented failure value — is
the right one.

**Rule.** A completion's failure value is stated in the header and is one of: `nil` for an
object, `@[]` for a list, `NO` for a success flag, `0` for an id. Never a partially-filled
object. Never an `NSError` the caller must inspect — there is no error-presentation UI to feed
it and `TGClient.onError` already handles the user-visible case.

```objc
/// `completion` gets the new chat id, or 0.
- (void)createSupergroupWithTitle:(NSString *)title ... completion:(void (^)(int64_t chatId))completion;
```

**Rule.** Do not `@throw`. Do not use `NSAssert` in shipping paths: on this device an assertion
failure is indistinguishable from the memory killer, so it destroys the only diagnostic signal
you have. Validate and return the documented failure value.

**Check.** `grep -rn "@throw\|NSAssert" src/` should stay empty.
**Scope.** **Retrofit** for the `@throw`/`NSAssert` ban (grep-verifiable, currently clean);
new code only for the documented-failure-value rule.

### 6.4 Every failure path either changes the screen or is silent on purpose

A completion that receives a failure value and does nothing leaves a spinner forever. This is
the second-commonest user-visible defect after 6.1.

**Rule.** In a view controller, every completion handler's failure branch does at least one of:
clears a loading flag, shows a `TGSnackbar`, or restores the previous content. If genuinely
nothing should happen, the branch is written explicitly with a comment, not omitted.

**Check.** In a view controller, for each `self.loading = YES` / `self.working = YES`, count
the assignments back to `NO`. If there are fewer `NO`s than the number of `return` paths in
the corresponding completion, a spinner can stick.
**Scope.** New code only.

---

## 7. Modelling state

### 7.1 Mutually exclusive booleans become an enum

The principle is standard — *n* booleans give 2ⁿ representable states of which only a handful
are legal, and the illegal ones are what you debug at 2am
([DevIQ](https://deviq.com/principles/make-illegal-states-unrepresentable/)). It is also
genuinely contested as a blanket rule: the counter-argument is that over-tight modelling makes
ordinary changes expensive and pushes complexity into conversions
([Goedecke](https://www.seangoedecke.com/invalid-states/)). The version below is scoped to
where the payoff is real here.

`TGChatViewController` has ~180 properties. Two of them describe the compose bar's mode:

```objc
@property (nonatomic, assign) int64_t replyToId;   // composing a reply
@property (nonatomic, assign) int64_t editingId;   // editing instead
```

They are mutually exclusive, and the code proves it by clearing them in pairs at five separate
sites (`:5688`, `:5866`, `:5874`, `:6195`, `:4151`). Miss one pair and the compose bar shows
"Reply to X" while `send` calls `editMessage:`. Nothing catches that.

**Rule.** When two or more properties in the same class must be cleared or set together to stay
consistent, and the number of legal combinations is smaller than the number of representable
ones, replace them with an `NS_ENUM` plus at most one associated id, and one setter.

```objc
// wrong
self.replyToId = messageId;
self.editingId = 0;

// right
typedef NS_ENUM(NSInteger, TGComposeMode) {
	TGComposeModeNew = 0,
	TGComposeModeReply,
	TGComposeModeEdit
};

- (void)setComposeMode:(TGComposeMode)mode message:(int64_t)messageId {
	_composeMode = mode;
	_composeMessageId = (mode == TGComposeModeNew) ? 0 : messageId;
	[self updateComposeBanner];
}
```

The single setter is the point: it makes "banner and behaviour agree" true by construction
rather than by five call sites remembering.

The codebase already contains the pattern done right — `TGLoginStep` at
`TGLoginViewController.m:10` is a nine-state enum covering phone / code / password / email /
QR / registration, replacing what would otherwise be eight flags. `TGAuthState` in
`TGClient.h:15` and `TGThemeStyle` in `TGTheme.h:12` are the same shape. Copy those.

**Check.** Search a class for `@property (nonatomic, assign) BOOL` and for `assign) int64_t
…Id`. Group them by what they describe. If clearing one requires clearing another, and that
pairing appears at three or more call sites, it is a violation. Present candidates:
`TGChatViewController` `replyToId`/`editingId`; `TGMessageActionsSheet.m:28-33`
`presenting`/`finished`/`confirming` (three booleans for one four-state lifecycle);
`TGChatViewController` `scheduledSendDate`/`scheduleWhenOnline`.
**Scope.** New code only, **except** `replyToId`/`editingId` and
`presenting`/`finished`/`confirming`, which are worth doing because each is confined to one
file and each currently has a live inconsistency (§6.1 for the sheet).

### 7.2 Derived state is computed, not stored

`TGChatViewController` stores `cachedUnreadRow`, `unreadOnOpen`, `unreadOnOpenKnown`,
`pinnedBannerInset`, `headerHeight`. Each is a cache of something computable from the message
array, and each is a chance to be stale.

**Rule.** A property that can be computed from other properties is a method, unless you have a
measured reason to cache it. On a 4S you often do have that reason — recomputing a row height
per `cellForRow` is real cost. So the rule is not "never cache"; it is:

**Rule.** A cached value is written in exactly one method, named `recompute…`/`refresh…`, and
every mutation of its inputs ends by calling that method. The cache is never assigned from
anywhere else.

```objc
// wrong - assigned at four call sites that must each remember
self.cachedUnreadRow = index;

// right
- (void)recomputeUnreadRow { ... }   // the only writer of _cachedUnreadRow
```

**Check.** `grep -n "self.cachedFoo =" <file>` — more than one assignment site (outside the
`recompute` method and `init`) is a violation.
**Scope.** New code only; **retrofit on touch** when you are already editing the cache's
inputs.

### 7.3 Sentinels are named

`0` for "no chat", `-1` for "no row", `NSNotFound` for "no index" are all in use. That is fine,
but the meaning must be written down once.

**Rule.** Any sentinel other than `nil`/`NSNotFound` gets a named constant or a comment on the
property declaration. `int64_t chatId` where `0` means "none" is documented on the property,
as `TGChatViewController.m:2516` already does with `// composing a reply`.

**Check.** A property declaration with a magic-value contract and no trailing comment.
**Scope.** New code only.

---

## 8. Headers versus implementations

The codebase is unusually good at this and the rules are mostly ratchets.

### 8.1 A header is the contract, and it is short

`TGChatViewController.h` is 25 lines for a 10,229-line implementation: four properties, one
method, and a comment explaining why the class exists at all. `TGProfileViewController.h` is
20. That is the standard.

**Rule.** A header declares only what another file calls. Everything else — private
properties, private methods, helper classes, constants — lives in the class extension at the
top of the `.m`.

**Check.** For each declaration in a `.h`, grep the tree for a use outside its own `.m`. No
external use means it belongs in the extension.
**Scope.** **Retrofit on touch.** Moving a declaration from `.h` to the `.m`'s extension is
compiler-verified — if you were wrong, the build fails immediately. That makes it one of the
few safe wide changes, but it still has no reader payoff unless the header is genuinely noisy,
so do it opportunistically.

### 8.2 The header carries the *why*; the implementation carries the *how*

Every good header in this tree opens with a paragraph that answers a question the code cannot.
`TGClient.h`: *"TDLib is loaded with dlopen rather than linked: statically linked it pushes the
app's `__TEXT` past the 16MB armv7 thumb branch limit."* `TGCapabilities.h`: *"a feature is not
'impossible' so much as 'not available here'."* `TGChatViewController.h`: why it was not built
on the old `ChatViewController`.

**Rule.** Every header opens with a comment block: what the class is for, and one constraint or
decision a reader would otherwise re-litigate. Individual declarations get a `///` line when
their contract is not obvious from the name — especially the failure value and the queue.

Note this is the one place the project's no-comments rule does not reach: it governs
implementation bodies. Header contracts and the `TGClient+Area.h` preambles are documentation
and are required.

**Check.** Open the header. Line 1 is `//` or `/**`, and the block answers "why does this
exist".
**Scope.** **Retrofit** — comment-only, zero build risk, and it is the highest
information-per-line change available for agents who will only ever see one file.

### 8.3 Cross-file state goes through `+Private.h`, not through a new header

`TGClient+Private.h` exists precisely so 26 categories can share `chatsById`, `pendingRequests`
and `request:completion:` without each redeclaring them.

**Rule.** A category needing shared `TGClient` state imports `TGClient+Private.h`. It does not
redeclare properties in its own file, and it does not add a second private header.

**Check.** A `@interface TGClient ()` block in any file other than `TGClient+Private.h` is a
violation.
**Scope.** **Retrofit** (currently clean; ratchet only).

### 8.4 Constants: `static const` in the `.m`, `extern` in the `.h`, never `#define`

**Rule.** A value used in one file is `static const` at the top of that `.m`
(`static const CGFloat kBubbleMaxW = 240.0f;`). A value used in two files is
`extern NSString *const TGFooNotification;` in a header with the definition in exactly one
`.m` — as `TGUserStatusDidChangeNotification` does. `#define` is reserved for conditional
compilation.

**Check.** `grep -rn "^#define" src/*.m` — every hit should be a compilation guard, not a value.
**Scope.** New code only.

---

## 9. Making a change safe to review

Reviewer attention is the real scarce resource and defect detection is known to fall off past
roughly 400 lines of diff, which is why Google's guidance is to split large changes
([SmartBear/Google, summarised](https://www.awesomecodereviews.com/research/code-review-research-overview/)).
Here the reviewer is often another agent with a one-file window, so the limit is tighter.

### 9.1 One commit does one kind of thing

**Rule.** A commit is either a **move** (cut and paste, byte-identical lines), a **rename**
(mechanical substitution), or a **behaviour change**. Never two at once. The move and rename
kinds are verifiable by inspection in seconds; mixing a behaviour change into one hides it.

The four extractions in §2.2 are move-commits. The `TGJSON` consolidation in §11 is a
rename-commit followed by a delete-commit. The `presentAtPoint:` fix in §6.1 is a
behaviour-change commit of three lines.

**Check.** If a commit's diff contains both a file addition with copied lines and a changed
condition, split it.
**Scope.** Applies to all future work.

### 9.2 A behaviour-change diff is under 200 lines, or it is split

**Rule.** Keep behaviour changes under ~200 changed lines. If a feature cannot be done in that
budget, land the preparatory extraction first (a move-commit), then the feature.

**Check.** `git diff --stat` before committing. Move-commits are exempt from the limit; nothing
else is.
**Scope.** Applies to all future work.

### 9.3 The diff must be verifiable without running the app

Since there is no test to appeal to, the change must carry its own argument.

**Rule.** Every non-trivial change is written so a reader can check it against something they
can see:

- **Prefer local reasoning.** A change confined to one method that reads only its parameters
  and one property is checkable. A change that depends on when three other screens set a
  shared flag is not — restructure until it is.
- **Change the guard, not the caller.** If a nil or a bad index is possible, handle it where
  the value is produced, so one edit fixes every consumer.
- **State the manual verification.** The commit message ends with the exact tap sequence a
  human would use to see the change: *"Settings → Data and Storage → the cache figure now
  matches the Storage screen."* This is the substitute for a test name and it is not optional.

**Check.** Read the commit message. If it does not say how to observe the change on the device,
it is incomplete.
**Scope.** Applies to all future work.

### 9.4 Touch one file per commit where the change allows

Given the one-file agent window, a commit spanning eight files is a commit nobody reviewed as a
whole. The `TGClient+<Area>` structure exists to make one-file changes possible; use it.

**Rule.** If a change must span files, order them: the header contract first, then the
implementation, then the callers — and say in the message which file carries the actual
decision.

**Scope.** Applies to all future work.

### 9.5 Never delete a guard you do not understand

Much of this code contains guards against conditions that only occur on the 4S: memory
pressure, a missing selector, a 32-bit truncation, a slow filesystem. There is no test that
will tell you the guard was load-bearing, and the device will simply be killed.

**Rule.** A guard, `respondsToSelector:` check, `@autoreleasepool`, or capability query is
removed only in a commit that does nothing else and whose message states why the condition can
no longer occur.

**Scope.** Applies to all future work.

---

## 10. What this chapter deliberately excludes

Widely recommended practice that does not apply here, and why:

- **Test-driven development, and "add a regression test" as the close-out of a bug fix.**
  There is no test target and no simulator path. Every rule above that would normally be
  justified by "tests will catch it" has been rewritten to be justified by "a reader will
  catch it" instead. Do not add a test target: it would need a second build configuration for
  a toolchain that barely supports one.
- **Dependency injection and protocol-based seams for testability.** The usual reason to inject
  `TGClient` is to substitute a fake in tests. There are no tests, so the seam buys nothing and
  costs an indirection on every call plus a protocol to keep in sync across 26 categories.
  `[TGClient shared]` stays.
- **"Extract until you drop" / very small functions everywhere.** Each `objc_msgSend` is a real
  cost on a single 800MHz A5 core, and the deep call stacks that style produces are unreadable
  without a debugger — which there isn't. The 60-line ceiling in §2.1 is the compromise:
  short enough to review, long enough to read straight through.
- **Immutability by default / value types everywhere.** With 40–60MB of usable RAM, copying a
  message array on every edit is not affordable. Mutable model dictionaries reused in place
  are the right call here, and rule §7.2 exists to make that safe rather than to forbid it.
- **A shared design-system palette extracted from the 160 `colorWithRed:` sites.** This looks
  like textbook duplication and is not: the sites are local constants, an extraction would need
  a mode parameter for the three themes, and §5.2 says that is the wrong abstraction. `TGTheme`
  already owns the colours that genuinely are shared.
- **Result types / typed error enums / `NSError **` out-parameters.** Nothing in the app can
  present a structured error to the user; `TGClient.onError` shows a string. A typed error
  hierarchy would be write-only code.
- **Nullability annotations, lightweight generics, `NS_DESIGNATED_INITIALIZER`,
  `instancetype`-everywhere modernisation.** The deployment SDK does not understand the first
  two, and mass-annotating is exactly the wide, unverifiable change §9 argues against.
- **A file-size limit applied uniformly.** §2.2 names four specific extractions rather than
  declaring war on every file over 1,500 lines. `TGProfileViewController.m` at 4,649 lines is
  one coherent screen with 40 `#pragma mark` sections; splitting it would create two files that
  both need the same private state, which is worse.
- **Enforcing one class per file retroactively.** Small private views defined above their owner
  (`TGBackspaceTextField` in `TGLoginViewController.m`, `TGLinkPreviewView` in
  `TGChatViewController.m`) are correct as they are — they exist only for that screen.
- **Conventional-commits / changelog tooling.** §9.3's "say how to observe it on the device" is
  worth more here than a machine-readable prefix.

---

## 11. Retrofit list, most valuable first

Everything else in this chapter is new-code-only or retrofit-on-touch. These are the changes
worth spending review budget on, in order. Each is a separate commit.

1. **Fix `TGMessageActionsSheet.m:63`** — the re-entrancy guard that returns without calling
   `completion`. Three lines, one live hang. (§6.1)
2. **Consolidate the JSON coercion helpers into `src/TGJSON.{h,m}`.** Eleven duplicate
   definitions across five files, with `TGString` disagreeing on `nil` vs `@""`. Pick one
   contract, document it, delete the statics. Compiler-verified; the only manual work is
   auditing the three `TGClient+Stickers.m` call sites that relied on `nil`. (§1.2, §5.3)
3. **Fix any `NSInteger`/`int` holding a 64-bit Telegram id.** Grep-exact, silent truncation,
   compiler-checked fix. (§1.4)
4. **Consolidate the six byte formatters into `TGFormatBytes`.** Users currently see the same
   file reported three ways. Behaviour changes on some screens by design — say so in the commit
   message and name the screens to check. (§1.1, §5.3)
5. **Extract the four foreign classes out of `TGChatViewController.m`** (Instant View,
   Reactions, Message Info, Photo Browser), one move-commit each. Removes ~1,700 lines from the
   file most likely to be edited concurrently. (§2.2)
6. **Add the three-question preamble to every `TGClient+<Area>.h`** (queue, nillability, failure
   value), modelled on `TGClient+Groups.h:8`. Comment-only, no build risk, highest value per
   line for single-file agents. (§3.2, §8.2)
7. **Collapse `replyToId`/`editingId` into a `TGComposeMode` enum with one setter**, and
   `presenting`/`finished`/`confirming` in `TGMessageActionsSheet` into a lifecycle enum. Both
   confined to one file; both currently have live inconsistencies. (§7.1)
8. **Audit `if (completion)` guarding across the `TGClient` categories** for the mixed
   convention. Lowest value of the eight — the unguarded calls happen to work today — so do it
   on touch rather than as a campaign. (§6.2)

Sources consulted for current practice: [Sandi Metz, *The Wrong
Abstraction*](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction);
[Rule of three](https://en.wikipedia.org/wiki/Rule_of_three_(computer_programming));
[DevIQ, *Make Illegal States Unrepresentable*](https://deviq.com/principles/make-illegal-states-unrepresentable/)
and the dissent, [Goedecke, *'Make invalid states unrepresentable' considered
harmful*](https://www.seangoedecke.com/invalid-states/);
[SE-0297 on the Objective-C completion-handler contract](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0297-concurrency-objc.md);
[code review research overview on diff size and defect
detection](https://www.awesomecodereviews.com/research/code-review-research-overview/).

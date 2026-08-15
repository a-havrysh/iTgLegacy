# Writing Objective-C for iOS 6 on constrained hardware

This chapter is the one whose violations crash a device we usually cannot test on. Everything here is
about a single machine: an iPhone 4S running iOS 6.1.3. One A5 core at 800 MHz, 512 MB of RAM with
roughly 40–60 MB the process actually gets before jetsam kills it without a log, a 640×960 screen at
scale 2.0, armv7, 32-bit, ARC on, deployment target 6.0. There is no simulator path and no unit test
target. A device build is the only verification, so the compiler and the rules below are the entire
safety net.

Two reference codebases are cited throughout, both real and both on disk:

- **Original** — `/Users/alexanderhavrysh/Git/iOS/telegram-original-sources/extracted/telegram_iphone.src`,
  the Telegram iOS source of this era. It shipped on this hardware. When a question is "how was this
  done at the time", this is the answer.
- **Twelve** — `/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph`, a later Objective-C fork on the same
  lineage that was explicitly back-ported toward iOS 6. It shows the same patterns under a newer SDK.

Each rule is tagged:

- **[RETROFIT]** — worth a sweep across the existing ~100k lines. Earned by crash risk or by being
  mechanically checkable with grep.
- **[NEW CODE]** — apply going forward; leave existing violations alone unless you are already editing
  the surrounding code. Churn on 100k lines is itself a risk.

---

## 1. The API boundary: iOS 6.1 is the floor and the ceiling

### Rule 1.1 — Every symbol you use must exist in the iOS 6.1 SDK, or be guarded. **[RETROFIT]**

The build succeeds against a newer SDK header set. It does not tell you the selector is missing at
runtime. This project has already shipped this bug: `-[NSData initWithBase64EncodedString:options:]`
is iOS 7 and later, it compiled without a warning, and it would have thrown `unrecognized selector` the
first time a voice note arrived.

Two call sites are still live today:

```objc
// WRONG — src/TGClient.m:347 and src/TGClient.m:783, still in the tree
NSData *data = [[NSData alloc] initWithBase64EncodedString:obj[@"data"] options:0];
waveform = [[NSData alloc] initWithBase64EncodedString:
        content[@"voice_note"][@"waveform"] ?: @"" options:0];
```

The right answer already exists in this codebase, three times over — `TGFilesDataFromBase64` in
`src/TGClient+Files.m`, `TGMCBase64` in `src/TGClient+MessageContent.m`, `TGScBase64Decode` in
`src/TGClient+SecretChats.m` — hand-rolled table decoders that run everywhere:

```objc
// RIGHT
waveform = TGMCBase64(content[@"voice_note"][@"waveform"]);
```

**How to check a file:** grep it against the known-absent list below. Anything that matches and is not
inside a `respondsToSelector:` / `NSClassFromString` guard is a defect.

Absent on iOS 6.1, non-exhaustive but these are the ones that get reached for:

| Symbol | Arrived | Use instead |
| --- | --- | --- |
| `UIAlertController` | 8.0 | `UIAlertView` / `UIActionSheet`, or `TGAlertView` / `TGActionSheet` in this tree |
| `UICollectionView` | 6.0 (present) but `UICollectionViewFlowLayout` estimated sizing | 7/8 | fixed layout only |
| Auto Layout on iOS 6 | 6.0 partial, unusable | frame layout, see §4 |
| `NSURLSession` | 7.0 | `NSURLConnection`, or TDLib's own transport |
| `WKWebView` | 8.0 | `UIWebView`; `TGCapabilities.canRunWebApps` already gates this at 9.0 |
| `UIRefreshControl` on plain `UIView` | 6.0 only inside `UITableViewController` | manual header view |
| `UIStackView` | 9.0 | frame layout |
| `-[NSData initWithBase64EncodedString:options:]`, `base64EncodedStringWithOptions:` | 7.0 | the local decoders |
| `NSAttributedString` on `UILabel`/`UITextField` (`attributedText`, `attributedPlaceholder`) | 6.0 for `UILabel`, 6.0 for `UITextField` — but guard anyway, the codebase does | guarded assignment |
| `-[NSString boundingRectWithSize:options:attributes:context:]` | 7.0 | `sizeWithFont:constrainedToSize:lineBreakMode:` |
| `UIRectEdge` / `edgesForExtendedLayout`, `automaticallyAdjustsScrollViewInsets` | 7.0 | guarded, see 1.2 |
| `tintColor` on arbitrary `UIView` | 7.0 | `UIView+SafeTint` in this tree |
| `NSURLQueryItem`, `NSURLComponents` | 7.0 | manual string building |
| Lightweight generics, nullability, `NS_DESIGNATED_INITIALIZER`, `@import` | 8/9 | plain Objective-C |
| KVO block observers, `NSKeyValueObservation` | 11 | `observeValueForKeyPath:` |
| `-[NSOperationQueue addOperationWithBlock:]` waiting conveniences, `qos` | 8 | GCD directly |
| `dispatch_block_t` cancellation, `dispatch_assert_queue` | 8/10 | flags on the object |

### Rule 1.2 — Guard by capability, not by version number, and put the guard at the call site. **[RETROFIT]**

`respondsToSelector:` on the exact receiver is the cheapest and most honest test. This is the dominant
idiom in the tree already (`src/TGChatViewController.m` alone has twenty of them) and it matches the
original:

```objc
// RIGHT — src/TGChatViewController.m:1386
if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
    self.edgesForExtendedLayout = UIRectEdgeNone;

// RIGHT — src/TGChatViewController.m:7372
if ([NSDateFormatter respondsToSelector:@selector(dateFormatFromTemplate:options:locale:)])
    format = [NSDateFormatter dateFormatFromTemplate:@"MMMd" options:0 locale:[NSLocale currentLocale]];
```

For a whole class, `NSClassFromString(@"WKWebView") != nil`. For a C function that may be a weak
symbol, compare the function pointer against `NULL` — the tree does this already:

```objc
// RIGHT — src/TGChatViewController.m:74
if (UIGraphicsBeginImageContextWithOptions != NULL)
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
else
    UIGraphicsBeginImageContext(size);
```

Version numbers are the fallback, not the default, and they belong in `TGCapabilities`, which already
owns `+systemVersion`, `+is64Bit`, `+memoryMB` and the feature answers derived from them. Do not
open-code a version comparison in a view controller. Both references keep version checks behind one
function — the original and Twelve both funnel through `iosMajorVersion()`
(`Telegraph/Telegraph/TGProfileController.m:3227`, `TelegraphKit/TelegraphKit/TGMapView.m:9`,
`twelve/Telegraph/TGEncryptionKeyViewController.m:68`).

**How to check a file:** grep for a floating-point or integer literal compared against a system version
outside `src/TGCapabilities.m`. Today there is exactly one such comparison and it is in the right file.
Keep it that way.

### Rule 1.3 — A behaviour that cannot exist on this hardware is a capability, not an `#ifdef`. **[NEW CODE]**

`TGCapabilities` distinguishes "the API cannot do this at all" (not a capability, do not add a flag)
from "this machine cannot" (a flag with a `requirement` string, so the Device screen can explain
itself). Follow that split. A new expensive feature — anything that decodes video, holds a full-screen
bitmap, or runs a frame loop — gets a capability with an honest reason, in the style of the existing
`canAnimateInline` ("one Lottie frame per message is more than an A5 has to spare").

**How to check:** a new feature that costs frames or megabytes and has no entry in `+[TGCapabilities all]`.

---

## 2. ARC on this toolchain, and what it does not save you from

ARC is on. It handles retain/release on Objective-C object pointers. It handles nothing else.

### Rule 2.1 — Every Core Foundation / Core Graphics / Image I/O object you create is released by hand. **[RETROFIT]**

ARC does not own `CGImageRef`, `CGImageSourceRef`, `CGColorRef`, `CGContextRef` from
`CGBitmapContextCreate`, `CFStringRef`, `CFDictionaryRef`, `ABAddressBookRef`, `SecKeyRef`. Every
`Create`/`Copy` in the name means you own it. On a 4S a leaked `CGImageRef` for a full-screen photo is
1.2 MB you never get back, and forty of them is the process.

`src/TGImageDecode.m` is the model to copy:

```objc
// RIGHT — src/TGImageDecode.m
CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, (CFDictionaryRef)sourceOpts);
if (!src) return nil;
CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, (CFDictionaryRef)opts);
CFRelease(src);
if (!cgImage) return nil;
UIImage *image = [UIImage imageWithCGImage:cgImage];
CGImageRelease(cgImage);
return image;
```

Note the shape: release on every exit path, including the early `return nil` after `CFRelease(src)`.
The common bug is an early return between the create and the release.

**How to check a file:** for each `CGImageSourceCreate`, `CGImageCreate`, `CGBitmapContextCreate`,
`CGColorCreate`, `CGPathCreate`, `CGGradientCreate`, `CGColorSpaceCreate`, `CFStringCreate`,
`ABAddressBookCreate`, count the matching `CFRelease`/`CGxxxRelease` and walk every `return` between
them. Any create with fewer releases than exits is a leak.

### Rule 2.2 — Bridge casts are explicit, and `__bridge` is the default. **[RETROFIT]**

`(__bridge CFTypeRef)obj` for a no-transfer cast, `(__bridge_transfer id)cfObj` when taking ownership of
something you created, `(__bridge_retained CFTypeRef)obj` when handing an object to C that will release
it. `CFBridgingRelease`/`CFBridgingRetain` are the readable spellings and are fine. A plain C-style cast
between an object pointer and a CF type does not compile under ARC, so the compiler catches the
omission; what it does not catch is `__bridge_transfer` on something you did not create, which
over-releases and crashes later, somewhere else.

**How to check:** every `__bridge_transfer` / `CFBridgingRelease` must sit on the result of a
`Create`/`Copy` function on the same or a directly preceding line.

### Rule 2.3 — Any loop that creates temporaries and runs more than a few dozen times gets an `@autoreleasepool`. **[RETROFIT, targeted]**

ARC does not shorten the autorelease pool. A background decode loop, a base64 decode, an NSData round
trip, an image resize — each one produces autoreleased temporaries that live until the pool drains,
which on a background GCD block is when the block ends. On the 4S this is the difference between a 3 MB
peak and a 30 MB peak.

The tree already does this in the right places:

```objc
// RIGHT — src/TGRemoteImageView.m
@autoreleasepool {
    NSData *cachedData = [NSData dataWithContentsOfFile:cachePath
                                                options:NSDataReadingMappedIfSafe error:NULL];
    ...
}
// RIGHT — src/TGClient.m:122, per update on the main queue
dispatch_async(dispatch_get_main_queue(), ^{
    @autoreleasepool { [self handleUpdate:obj]; }
    dispatch_semaphore_signal(slots);
});
```

**How to check:** a `for`/`while` body, or a `dispatch_async` block, that allocates `NSData`, `UIImage`,
`NSString` via `stringWithFormat:`, or any `NSDictionary` per iteration, and has no `@autoreleasepool`.
Retrofit this only where the loop touches images, file data, or TDLib update payloads — not for a loop
over twelve table rows.

### Rule 2.4 — ARC does not break retain cycles. See §3. **[RETROFIT]**

### Rule 2.5 — Do not rely on `dealloc` running at a particular time, and never do UIKit work in it. **[NEW CODE]**

`dealloc` under ARC can run on whatever thread released the last reference — for objects captured in a
background block, that is a background thread. Removing an observer is fine. Touching a view, a timer,
or `UIApplication` is not. Unregister in `viewDidDisappear:` or an explicit `-invalidate`, and keep
`dealloc` to `removeObserver:` and C-level cleanup.

**How to check:** any `dealloc` that calls a UIKit method other than `removeObserver:`,
`[NSNotificationCenter defaultCenter]` removal, or `CFRelease`.

---

## 3. Blocks, retain cycles, and the `__weak` dance this codebase uses

TDLib is callback-driven and every screen is written as `[[TGClient shared] doThing:… completion:^{ … }]`.
A completion block retained by a long-lived client that captures `self` strongly keeps a view controller
and its whole view tree alive after the user has left the screen. On a 4S, two leaked chat controllers
is a jetsam.

### Rule 3.1 — Any block that outlives the statement captures `self` weakly. **[RETROFIT]**

The house idiom, used 2,386 times already, is:

```objc
// RIGHT
__weak typeof(self) weakSelf = self;
[[TGClient shared] editCaptionOfMessage:self.messageId inChat:self.chatId completion:^(BOOL ok){
    TGChatViewController *strong = weakSelf;
    if (!strong)
        return;
    [strong reloadCaption];
}];
```

```objc
// WRONG
[[TGClient shared] editCaptionOfMessage:self.messageId inChat:self.chatId completion:^(BOOL ok){
    [self reloadCaption];          // client holds the block, block holds the controller
}];
```

Exception, and it is a real one: blocks that do not outlive the call — `UIView` animation blocks,
`enumerateObjectsUsingBlock:`, `sortUsingComparator:`, `dispatch_sync` — may capture `self` strongly.
Adding `weakSelf` there is noise.

**How to check a file:** for every block literal passed to a `TGClient` method, a `dispatch_async`, an
`NSTimer`, an `NSNotificationCenter` block observer, or stored in a property, grep the block body for a
bare `self` or an implicit ivar reference (`_foo`). Implicit ivar access inside a block is a strong
`self` capture and is the easiest one to miss.

### Rule 3.2 — Promote the weak reference to a strong local once, at the top, and test it. **[RETROFIT]**

`weakSelf.foo` in a block is legal and reads fine, but each access is a separate load that can go nil
between two of them. There are 373 such accesses in the tree against 1,711 strong promotions; the
promotion is the house style and the correct one.

```objc
// WRONG — two loads, the second can be nil, and the `if` proves nothing about the third line
if (weakSelf.cancelled) return;
[weakSelf.tableView reloadData];

// RIGHT — src/TGRemoteImageView.m
TGRemoteImageView *me = weakSelf;
if (!me || me.cancelled || ![me.fileId isEqual:fileId])
    return;
[me applyImage:image fade:fade];
```

Retrofit this where the block has more than one `weakSelf.` access. A single `weakSelf.someProperty = x`
is harmless; leave it.

### Rule 3.3 — Name the weak variable `weakSelf` and the strong one after the class. **[NEW CODE]**

Twelve idioms for the same thing across 100 files is how nobody can grep for the pattern. Existing code
uses `__weak typeof(self) weakSelf = self;` for the weak side and a class-typed local (`me`, `strong`,
or the class name) for the strong side. Use `__weak typeof(self) weakSelf = self;` and
`TGYourClass *strongSelf = weakSelf;`. Do not retrofit the 22 sites already spelled
`__weak TGLoginViewController *` — they are correct, just differently spelled.

### Rule 3.4 — A block stored on `self` that captures `self` is a cycle even with a weak self inside, if the block also strongly captures a child that points back. **[NEW CODE]**

The subtle version: a cell holds an `onTap` block, the block captures the view controller strongly, the
controller holds the table that holds the cell. `__weak` on the controller side fixes it. Any property
of block type on a view or cell must document, in the header, that its block must not capture the owner
strongly — or, better, must be nil'd out in `prepareForReuse` / `prepareForRecycle:`, which
`TGRemoteImageView` already does for its loading state.

**How to check:** every `@property (nonatomic, copy) void (^…)` — confirm each assignment site uses
`weakSelf`, and that the owner clears it on teardown.

### Rule 3.5 — `__block` on an object variable does not break a cycle. **[RETROFIT]**

Under ARC `__block id x` is retained by the block. Pre-ARC it was not, and the old idiom
`__block id weakSelf = self` is a strong capture today. There are 36 `__block`/`__unsafe_unretained`
sites in the tree; audit each one — `__block` is correct for a mutable counter or a flag the block
writes back, and wrong as a cycle breaker.

**How to check:** grep `__block` and confirm each is either a scalar the block mutates, or an object the
block genuinely needs to reassign. `__block` on a `self`-typed variable is always a bug.

### Rule 3.6 — Cancel, do not just check. **[NEW CODE]**

A weak self that has gone nil stops the UI update but does not stop the work. Anything that costs
bandwidth or CPU — a file download, an image decode, a timer — needs an explicit cancel on teardown.
`TGRemoteImageView` sets `self.cancelled = true` in `-cancelLoading` and every callback re-checks
identity (`![me.fileId isEqual:fileId]`, `![me.currentCacheKey isEqualToString:cacheKey]`). Copy that:
a weak check plus an identity check plus a cancel flag. Two of the three is a stale image in a reused
cell.

---

## 4. Frame-based layout, because Auto Layout is not an option

There are zero `NSLayoutConstraint` references in this codebase and that is correct. Auto Layout exists
on iOS 6 but the solver is slow enough on an A5 to be visible in a scrolling table, and half the API
(`NSLayoutAnchor`, `UIStackView`, `constraintsWithVisualFormat:` niceties) arrived later.

### Rule 4.1 — Layout happens in `layoutSubviews` or in an explicit layout method, never in `cellForRowAtIndexPath:`. **[NEW CODE, retrofit where a table stutters]**

Setting a frame in `cellForRow` means the layout is recomputed on every scroll tick and cannot respond
to a rotation. 24 files already implement `layoutSubviews`; that is the pattern.

```objc
// WRONG
cell.titleLabel.frame = CGRectMake(60, 8, tableView.bounds.size.width - 90, 20);

// RIGHT — in the cell
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    self.titleLabel.frame = CGRectMake(kAvatarSide + 2 * kPadH, kPadV,
                                       b.size.width - kAvatarSide - 4 * kPadH, 20);
}
```

### Rule 4.2 — Frames are whole points, or exact halves on retina. **[RETROFIT, mechanical]**

A non-integral frame origin forces off-pixel compositing and, for text, a blurry label that the A5 pays
antialiasing for on every frame. Round with `floorf(x + 0.5f)` or `CGRectIntegral`. The one legitimate
fraction is a hairline: this tree already names it, `static const CGFloat kRetinaPixel = 0.5f;` in
`src/TGChatViewController.m`.

```objc
// WRONG
label.frame = CGRectMake(10, (rowHeight - textHeight) / 2.0f, w, textHeight);
// RIGHT
label.frame = CGRectMake(10, floorf((rowHeight - textHeight) / 2.0f), w, textHeight);
```

**How to check:** a division by `2.0f`, `3.0f` or a multiplication by a non-integral scale flowing
straight into a `CGRectMake` without a `floorf`/`ceilf`/`roundf`.

### Rule 4.3 — Magic numbers become named constants at file scope. **[NEW CODE]**

`src/TGChatViewController.m` is the reference: `kInputHeight`, `kBubbleTailOverhang`, `kAvatarSide`,
`kPadH`, `kPadV`, each with a comment explaining where the number came from (the 360dp-to-320pt scale,
the artwork's internal padding). A raw `43.0f` in the middle of a method is unmaintainable by the next
agent, who cannot see the other file that also uses 43.

**How to check:** the same float literal appearing three or more times in one file.

### Rule 4.4 — Do not read `[UIScreen mainScreen].bounds` to decide layout; read the view's own bounds. **[NEW CODE]**

The 4S is 320×480 and the 5 is 320×568, and the app also runs on later devices. Screen-size branching
scatters; container bounds do not. Where you genuinely need the screen, go through one accessor.

### Rule 4.5 — Autoresizing masks are allowed and preferred for the simple cases. **[NEW CODE]**

A subview that should track its superview's width sets
`UIViewAutoresizingFlexibleWidth`. That is not Auto Layout, it is cheap, and it removes a
`layoutSubviews` override. Reserve manual layout for anything the mask cannot express.

---

## 5. UITableView reuse, done properly

There are 118 `dequeueReusableCellWithIdentifier:` calls and no `registerClass:` anywhere — correct,
since `registerClass:forCellReuseIdentifier:` on `UITableView` is iOS 6 but the nil-check idiom works
everywhere and is what the original used.

### Rule 5.1 — The dequeue-or-create idiom, with a `static NSString *` identifier. **[RETROFIT, mechanical]**

```objc
// RIGHT — src/TGChatListViewController.m:3356
static NSString *reuse = @"TGChatCell";
TGChatCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
if (!cell)
    cell = [[TGChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
```

```objc
// WRONG — a fresh cell per row, unbounded allocation while scrolling
TGChatCell *cell = [[TGChatCell alloc] initWithStyle:UITableViewCellStyleDefault
                                     reuseIdentifier:nil];
```

**How to check:** any `alloc]/init…WithStyle:` on a cell class that is not inside an `if (!cell)`.

### Rule 5.2 — Subviews are created in the cell's initialiser, never in `cellForRowAtIndexPath:`. **[RETROFIT]**

`[cell.contentView addSubview:…]` in `cellForRow` adds a new label to a recycled cell every time it
scrolls past — the classic overlapping-text bug and an unbounded view leak.

**How to check:** grep every `cellForRowAtIndexPath:` body for `addSubview:` or `alloc] initWith` on a
`UILabel`/`UIImageView`/`UIButton`. There should be none.

### Rule 5.3 — `cellForRowAtIndexPath:` assigns every mutable property on every path. **[RETROFIT]**

A recycled cell carries the previous row's state. `src/TGChatListViewController.m:3364–3381` is the
model: it explicitly sets `hidden` on `authorLabel`, `onlineDot`, `tick`, `muteIcon`, `groupIcon`,
`pin`, `draftLabel`, `badge`, `badgeBackground`, and clears `badge.text`, before deciding which of them
to turn back on. Reset first, then configure.

**How to check:** a property set inside an `if` in `cellForRow` with no matching default assignment
before the `if`.

### Rule 5.4 — Anything asynchronous stored in a cell is keyed and re-checked on delivery. **[RETROFIT]**

The cell that started the download is not the cell that receives the image. `TGRemoteImageView` gets
this right: the completion re-checks `me.fileId` and `me.currentCacheKey` before touching the image
view, and `prepareForReuse` / `prepareForRecycle:` cancel and reset. Any new async property on a cell
copies that structure.

**How to check:** an async completion inside `cellForRow` that assigns to `cell.something` without
first comparing an identity token captured before the call.

### Rule 5.5 — `heightForRowAtIndexPath:` must be O(1) and must not measure text. **[RETROFIT, high value]**

`UITableView` on iOS 6 calls `heightForRowAtIndexPath:` for **every row in the section** when the table
reloads, before it draws anything. In `src/TGChatViewController.m` that path reaches
`-bodySizeFor:` (line 7335), which calls
`sizeWithFont:constrainedToSize:lineBreakMode:` — an uncached Core Text measurement — and
`-[TGClient nameForUserId:]`, for every message in the chat. On a 500-message history that is 500 text
layouts before the first pixel, on one A5 core. This is the single most expensive avoidable thing in
this codebase.

```objc
// WRONG — measured on every call, and heightForRow is called per row per reload
- (CGSize)bodySizeFor:(NSDictionary *)m {
    return [text sizeWithFont:font constrainedToSize:CGSizeMake(maxW, 10000)
                lineBreakMode:NSLineBreakByWordWrapping];
}

// RIGHT — measure once when the message enters the model, store it with the message
NSMutableDictionary *row = [message mutableCopy];
row[@"bodySize"] = [NSValue valueWithCGSize:[self measureBodyFor:message width:maxW]];
// heightForRow then reads row[@"bodySize"], and invalidates only on width change
```

The precomputed-layout model is exactly what the original did: message geometry is computed off the
main thread when the message is added and stored on the model object, so the table's height callback is
a field read.

**How to check:** grep `heightForRowAtIndexPath:` and follow the call graph one level. If it reaches
`sizeWithFont:`, `sizeThatFits:`, a `TGClient` accessor, or a file-system call, it violates this rule.
Retrofit this in the three tables with unbounded row counts — chat, chat list, contacts — and leave the
fixed-height settings tables alone.

### Rule 5.6 — Cell count is bounded by what the model holds; page the model. **[NEW CODE]**

A chat with 20,000 messages must not have 20,000 dictionaries in `self.messages`. Load a window, drop
the far end. This is a design rule more than a code rule, but a new screen that reads an unbounded
TDLib list into an array is a jetsam waiting for a busy chat.

---

## 6. Drawing and image decoding, counted in bytes

The arithmetic that governs everything here: a decoded bitmap costs `width × height × 4` bytes,
in **pixels**, regardless of the file size on disk. A full-screen retina photo on a 4S is
640 × 960 × 4 = 2.4 MB. Twenty of those in a cache is 48 MB and the process is gone.

### Rule 6.1 — Never load a full-size image to display a small one. **[RETROFIT]**

`[UIImage imageWithContentsOfFile:]` on a 2048×1536 photo allocates 12 MB to draw a 38pt avatar. Use
`TGDecodeThumbnail` / `TGDecodeSquareThumbnail` from `src/TGImageDecode.h`, which go through
`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceShouldCache: @NO` and never materialise the
full bitmap.

**How to check:** any `imageWithContentsOfFile:`, `imageWithData:`, or `+[UIImage imageNamed:]` on a
path that came from TDLib (a downloaded file) rather than from the bundle.

### Rule 6.2 — `kCGImageSourceThumbnailMaxPixelSize` is in **pixels**. Points × screen scale. **[RETROFIT]**

This project has already shipped this bug once: a decode size given in points on a 2× screen produced
an image at half the resolution it needed, and every avatar in the app was soft. The unit boundary is
invisible in the type system — both sides are `CGFloat`.

The convention this codebase settled on, and the one to keep:

- `TGDecodeThumbnail(path, maxPixelSize)` takes **pixels**.
- `TGDecodeSquareThumbnail(path, side)` takes **points**, and internally asks for `side * 2` pixels and
  renders into `UIGraphicsBeginImageContextWithOptions(…, 0.0f)` so the result carries the screen scale.

```objc
// WRONG — 38 pixels for a 38pt avatar on a 2x screen: half resolution
UIImage *thumb = TGDecodeThumbnail(path, kContactAvatar);

// RIGHT — points in, the points-taking function
UIImage *thumb = TGDecodeSquareThumbnail(path, kContactAvatar);
// RIGHT — pixels in, the pixels-taking function, named so
UIImage *image = TGDecodeThumbnail(path, TGStoryPhotoPixels);
```

`src/TGStoriesViewController.m:2460` names its constant `TGStoryPhotoPixels`. Do the same: any variable
holding a value destined for `TGDecodeThumbnail` has `Pixel`/`Pixels` in its name.

**How to check:** every `TGDecodeThumbnail(` call site. If the second argument is a point constant
(`kProfileAvatarSide`, `kListAvatarSide`, a frame dimension) and is not multiplied by
`[UIScreen mainScreen].scale` or by a literal `2.0f`, it is wrong.

### Rule 6.3 — `+[UIImage imageWithCGImage:]` produces a scale-1.0 image. **[RETROFIT]**

`TGDecodeThumbnail` returns `[UIImage imageWithCGImage:cgImage]`, whose `scale` is 1.0. Assigned to a
`UIImageView` with `contentMode` scale-to-fill it will render at double the intended point size on a 2×
screen. Either use `imageWithCGImage:scale:orientation:` with the real scale, or size the view in
pixels, or go through `TGDecodeSquareThumbnail`, which fixes the scale by re-rendering. Pick one per
call site and be explicit.

**How to check:** any `imageWithCGImage:` (single-argument) whose result reaches a `UIImageView` sized
in points.

### Rule 6.4 — Image caches are bounded by cost in bytes, and cleared on memory warning and on background. **[RETROFIT]**

`TGRemoteImageMemoryCache()` in `src/TGRemoteImageView.m` is the model: an `NSCache` with
`totalCostLimit = 6 * 1024 * 1024`, a `TGRemoteImageCost()` that computes
`CGImageGetHeight(cg) * CGImageGetBytesPerRow(cg)`, and observers on both
`UIApplicationDidReceiveMemoryWarningNotification` and `UIApplicationDidEnterBackgroundNotification`
that drop everything. An `NSMutableDictionary` of images is not a cache, it is a leak with a nicer name.

```objc
// WRONG
@property (nonatomic, strong) NSMutableDictionary *images;   // grows forever
// RIGHT
cache = [[NSCache alloc] init];
cache.totalCostLimit = 6 * 1024 * 1024;
[cache setObject:image forKey:key cost:TGRemoteImageCost(image)];
```

**How to check:** grep for a dictionary or array property whose values are `UIImage`. Every hit is
either a bounded working set for the visible rows (fine, if it is cleared) or a defect. There are
several today; `src/TGChatViewController.m`'s `self.images` is the one to look at first.

### Rule 6.5 — Decode off the main thread, assign on the main thread. **[RETROFIT]**

Decoding a 640-pixel JPEG on an A5 is tens of milliseconds. Doing it in `cellForRow` drops frames
visibly. The pattern is in `TGRemoteImageView`: `dispatch_async` to a global queue for the file read and
decode, `dispatch_async(dispatch_get_main_queue(), …)` for the assignment, with the identity re-check on
the main side.

**How to check:** a `TGDecodeThumbnail` / `imageWithData:` / `UIImagePNGRepresentation` call reachable
from a table view delegate method without an intervening `dispatch_async` to a non-main queue.

### Rule 6.6 — Prefer a stretchable resource image to a `drawRect:`. **[NEW CODE]**

Only four files implement `drawRect:` (`TGLabel`, `TGLottieView`, `TGDateLabel`,
`TGProfileViewController`) and that is the right number. `drawRect:` allocates a backing store of
`bounds × scale² × 4` bytes per view and re-runs on every bounds change. A one-pixel PNG stretched with
`resizableImageWithCapInsets:` costs nothing per frame. The original drew its bubbles from
`Msg_In.png` / `Msg_Out.png` with the tail baked into the artwork — which is why
`kBubbleTailOverhang` exists in this tree.

**How to check:** a new `drawRect:` that only fills rounded rectangles, gradients, or lines. Ask for a
resource instead.

### Rule 6.7 — Cache generated images in a file-scope static, guarded. **[RETROFIT, cheap]**

`TGUnreadArrowImage()` and `TGSystemPlateColour()` in `src/TGChatViewController.m` show the shape:
build once into a `static`, return it thereafter. Regenerating an 11×8 arrow per cell is silly but
regenerating a 320-wide gradient per cell is a frame.

---

## 7. The main thread budget: one A5 core

At 60 fps you have 16.6 ms per frame; realistically on a 4S, budget 8 ms of your own work per frame
during a scroll. Every one of these costs more than that: a synchronous file read, a JSON parse of a
TDLib update, a text measurement of a long message, a `UIImage` decode, a `NSDateFormatter` allocation.

### Rule 7.1 — No synchronous file I/O on the main thread. **[RETROFIT]**

`[NSData dataWithContentsOfFile:]`, `[NSFileManager attributesOfItemAtPath:]`,
`[NSString stringWithContentsOfFile:]`, `NSUserDefaults` synchronize. Read on a background queue.
`NSDataReadingMappedIfSafe`, which `TGRemoteImageView` uses, avoids the copy but not the page faults.

**How to check:** grep the file for those calls; for each, confirm it is inside a `dispatch_async` to a
non-main queue, or in a startup path that runs once before the first frame.

### Rule 7.2 — `NSDateFormatter` and `NSNumberFormatter` are expensive; allocate once. **[RETROFIT, cheap]**

Creating an `NSDateFormatter` costs on the order of a millisecond on this hardware. One per chat-list
row per reload is a visible stall. Hold a `static` or a property, reconfigure the format only when the
locale changes. `src/TGDateUtils.mm` and `TGDateLabel` exist for this; use them rather than a local
formatter.

**How to check:** `[[NSDateFormatter alloc] init]` inside any method called per row, per message, or per
frame.

### Rule 7.3 — Back-pressure on TDLib updates is not optional. **[NEW CODE, and preserve the existing mechanism]**

`src/TGClient.m` already gates update delivery with a `dispatch_semaphore_t slots` so a burst of updates
from the network thread cannot queue thousands of main-queue blocks and starve the UI. Do not remove it,
and do not add a second, ungated `dispatch_async(dispatch_get_main_queue())` path out of the TDLib
receive loop.

**How to check:** any `dispatch_get_main_queue()` in `TGClient.m` or a `TGClient+*` category on the
receive path that is not inside the semaphore-bounded block.

### Rule 7.4 — Do not call `reloadData` when you changed one row. **[RETROFIT, targeted]**

`reloadData` re-asks `heightForRowAtIndexPath:` for every row (see 5.5). Use
`reloadRowsAtIndexPaths:withRowAnimation:` — `src/TGChatListViewController.m:183` already does. In a
chat, appending a message is `insertRowsAtIndexPaths:`, not a full reload.

**How to check:** a `reloadData` call in a handler whose name mentions a single message, row, chat, or
user.

### Rule 7.5 — Animations: keep them short and do not animate a full-screen blur, shadow, or
`UIViewAnimationOptionTransitionCrossDissolve` over a large view. **[NEW CODE]**

`layer.shadowPath` unset means an off-screen render pass per frame; `layer.cornerRadius` +
`masksToBounds` on a scrolling cell is the same. If a cell needs rounded corners, use a pre-rounded
image mask. The 0.14 s cross-dissolve `TGRemoteImageView` uses on a 38pt avatar is fine; the same on a
320×480 photo is not.

**How to check:** `shadowOpacity` without an adjacent `shadowPath`; `cornerRadius` on a view inside a
`UITableViewCell`.

---

## 8. 32-bit armv7: where 64-bit values get truncated

On armv7 `NSInteger`, `NSUInteger`, `long` and `CFIndex` are **32 bits**. `long long`,
`int64_t` and `NSTimeInterval` are 64. Telegram chat ids, message ids, user ids, supergroup ids and file
sizes are all 64-bit and routinely exceed 2³¹. TDLib hands them over as `NSNumber` inside a parsed JSON
dictionary, where the static type is `id` and the compiler has nothing to check.

### Rule 8.1 — Read every Telegram id with `longLongValue`, never `integerValue` or `intValue`. **[RETROFIT, highest value in this chapter]**

This has bitten already: an id read through `integerValue` truncates on armv7 and the resulting number
silently addresses a different chat, or no chat. It is not a crash. It is a wrong answer, which is
worse, and it only reproduces for accounts whose ids are large.

```objc
// WRONG — truncates to 32 bits on the target device
long long chatId = message[@"chat_id"].integerValue;
[[TGClient shared] openChat:[m[@"senderId"] intValue]];

// RIGHT — src/TGChatListViewController.m:168 and throughout
[[TGClient shared] cachedTitleForChatId:[key longLongValue]];
[[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
```

The codebase is mostly right — 513 `longLongValue` sites — but there are 449 `integerValue` sites, and
each one needs classifying. `integerValue` is legitimate for: array indices, counts, durations,
`unread_count`, reaction counts, `file_id` (TDLib file ids are 32-bit by construction, which is why
`src/TGRemoteImageView.m` can pass `fileId.integerValue` to `downloadFile:`), and enum-ish `@"@type"`
discriminators.

**How to check a file:** grep `integerValue|intValue|unsignedIntegerValue`. For each hit, look at the
key it reads. If the key or the variable name contains `chat`, `message`, `user`, `sender`, `supergroup`,
`basic_group`, `secret_chat`, `id` in an entity sense, `size`, `offset`, or `date` in milliseconds, it
must be `longLongValue`. Fix these across the tree; the sweep is mechanical and the payoff is a whole
class of impossible-to-reproduce wrong-chat bugs.

### Rule 8.2 — 64-bit ids travel as `long long` in every signature, property and format string. **[RETROFIT]**

There are 60 `long long` declarations in the headers today and no `NSInteger`-typed chat or message id,
which is the state to preserve. A method that takes `(NSInteger)chatId` truncates at the call boundary
and no amount of correct `longLongValue` upstream saves it.

```objc
// WRONG
- (void)openChat:(NSInteger)chatId;
// RIGHT
- (void)openChat:(long long)chatId;
```

Format strings follow: `%lld` for `long long`, `%ld` with an `(long)` cast for `NSInteger`, `%zu` for
`NSUInteger` sizes, `%@` for `NSNumber`. `%d` with a `long long` argument reads the wrong half of the
value on a variadic call and prints garbage — and 32 `%lld` sites in the tree say the convention is
already understood.

**How to check:** grep headers for `NSInteger` and `int` in a parameter whose name ends in `Id`.

### Rule 8.3 — Do not store a 64-bit id in a `tag`, an `NSInteger` userInfo, or a `void *`. **[RETROFIT]**

`UIView.tag` is `NSInteger` — 32 bits here. Passing a chat id through `button.tag` truncates. Use a
property on a subclass, an `NSNumber` in a dictionary keyed off the view, or an index into an array.

**How to check:** any `.tag =` whose right-hand side is a chat/message/user id rather than a small
constant.

### Rule 8.4 — Beware `NSUInteger` underflow in reverse loops and length arithmetic. **[RETROFIT, targeted]**

`for (NSUInteger i = count - 1; i >= 0; i--)` never terminates, and `count` of 0 makes `count - 1` a
huge number that indexes off the end. Use `NSInteger` for a countdown, or `while (i-- > 0)`.

**How to check:** `NSUInteger` in a loop with `- 1` or `>= 0`.

### Rule 8.5 — `CGFloat` is `float` on armv7. **[NEW CODE]**

Single precision, ~7 decimal digits. Do not accumulate a Unix timestamp, a byte count, or a message id
into a `CGFloat` — it will round. Use `double` for time arithmetic and `long long` for counts, and cast
to `CGFloat` only at the point of handing a coordinate to UIKit. Equality comparison on `CGFloat` uses
an epsilon; `src/TGRemoteImageView.m` compares against `FLT_EPSILON` and rounds with a `0.5f` bias,
which is the right instinct.

---

## 9. UIAppearance and its proxies

`UIAppearance` exists on iOS 5 and later, and this project uses it in exactly one place —
`-[TGTheme styleBackButton]` — because the navigation controller's back button is created by UIKit and
cannot be reached any other way.

### Rule 9.1 — Never gate an appearance-proxy call with `respondsToSelector:`. **[RETROFIT]**

The proxy returned by `+[UIBarButtonItem appearance]` is an `NSProxy`-like forwarder. It does not
implement the appearance selectors; it captures invocations and replays them on real instances later.
`respondsToSelector:` therefore answers **NO for every selector**, and a guard written in good faith
silently disables all of your theming. This project hit exactly this, and the fix is documented in the
source:

```objc
// src/TGTheme.m:479 — read this comment before touching appearance code
// The appearance proxy forwards selectors instead of implementing them, so
// respondsToSelector: answers NO for every one of them and must not gate
// these calls. They have all existed since iOS 5.
UIBarButtonItem *proxy = [UIBarButtonItem appearance];
[proxy setBackButtonBackgroundImage:nil forState:UIControlStateNormal
                         barMetrics:UIBarMetricsDefault];
```

```objc
// WRONG — the guard is always false, the theme never applies, nothing warns you
UIBarButtonItem *proxy = [UIBarButtonItem appearance];
if ([proxy respondsToSelector:@selector(setBackButtonBackgroundImage:forState:barMetrics:)])
    [proxy setBackButtonBackgroundImage:img forState:UIControlStateNormal
                             barMetrics:UIBarMetricsDefault];
```

The availability question for a proxy call is answered on the **class**, not the proxy:
`[UIBarButtonItem instancesRespondToSelector:@selector(setBackButtonBackgroundImage:forState:barMetrics:)]`.
In practice, every appearance selector this app needs shipped in iOS 5, so no guard is required at all.

**How to check:** grep `appearance]` and confirm no `respondsToSelector:` appears within the same
method on the proxy variable. Also grep for `instancesRespondToSelector:` — if you need a guard, that is
the spelling.

### Rule 9.2 — Appearance is applied once, at launch, from `TGTheme`. **[RETROFIT]**

An appearance proxy set from a view controller affects instances created *after* that point, so the
result depends on navigation order — a bug that reproduces only on the third screen. All appearance
configuration lives in `TGTheme` and runs before the window is keyed, and again as a whole when the
theme changes.

**How to check:** `appearance]` outside `src/TGTheme.m`. Today there are zero. Keep it at zero.

### Rule 9.3 — `appearanceWhenContainedIn:` is the iOS 6 spelling. **[NEW CODE]**

`appearanceWhenContainedInInstancesOfClasses:` is iOS 9. If you need containment scoping, use the
varargs `appearanceWhenContainedIn:` and terminate the list with `nil`.

### Rule 9.4 — Anything appearance cannot reach is set per instance, explicitly. **[NEW CODE]**

Appearance is a fallback for UIKit-created views. For views this code creates, set the property
directly — it is one line, it is greppable, and it does not depend on ordering.

---

## 10. The traps this project has already hit

Collected here so a future agent can check the four in one pass. Each is a real defect from this
project's own history, and each was invisible to the compiler.

1. **An appearance proxy answers NO to `respondsToSelector:` for every selector.** A well-meant
   availability guard turned off the entire back-button theme. §9.1. The comment at
   `src/TGTheme.m:479` is the permanent record.
2. **An id read through `integerValue` truncates on armv7.** Silent wrong answer, not a crash;
   reproduces only for large ids. §8.1. Still the biggest outstanding sweep: 449 `integerValue` sites
   to classify.
3. **A decode size in points where the API wanted pixels halved every avatar.** Both parameters are
   `CGFloat`, so nothing complained. §6.2. The mitigation is naming: pixel-valued variables carry
   `Pixels` in the name, and `TGDecodeSquareThumbnail` (points) is preferred over `TGDecodeThumbnail`
   (pixels) wherever a point-sized view is the destination.
4. **An iOS 7-only base64 initialiser compiled fine and would have thrown on the first voice note.**
   §1.1. Two call sites remain live, at `src/TGClient.m:347` and `src/TGClient.m:783`, and both should
   be routed through the existing hand-rolled decoders. This is the most urgent single fix named in
   this chapter: one of them is on the voice-note path, which any user will hit.

A fifth, structural, which is why this rulebook exists: **400 agents each saw one file.** The same
concept therefore has several spellings — three separate base64 decoders, twelve spellings of the weak
self, two units for a decode size. Where this chapter names a house idiom, the point is that it is
greppable, not that it is prettier.

---

## What this chapter deliberately excludes

Practices that are standard advice in modern Objective-C and that do **not** apply here. Each is
excluded for a reason, not by oversight.

- **Auto Layout, size classes, safe-area insets.** Not available or not usable at this deployment
  target, and the solver is too slow on an A5 for scrolling content. Frame layout is the rule, not a
  compromise. §4.
- **`UICollectionView` for grids.** It exists in iOS 6 but is heavier than a `UITableView` with
  multi-item rows, and every later convenience (self-sizing cells, compositional layout) is absent.
  The sticker and reaction panels in this tree use custom scroll views with `TGViewRecycler`, matching
  `TelegraphKit/TelegraphKit/TGViewRecycler.m` in the original. Do not migrate them.
- **Nullability annotations (`nonnull`/`nullable`) and lightweight generics.** The toolchain targeting
  iOS 6 does not understand them; they would be noise or a build failure. Express nullability in the
  header comment.
- **`NS_DESIGNATED_INITIALIZER`, `instancetype` everywhere, `NS_ENUM` uniformity.** `instancetype` and
  `NS_ENUM` are fine and are used; the designated-initialiser macro is not worth a 100k-line sweep and
  buys nothing without the newer diagnostics.
- **Unit tests, TDD, dependency injection for testability.** There is no test target and no simulator
  path. A rule that says "add a test" is unfollowable here and therefore worse than no rule. Verification
  is a device build plus the checkable conditions written into each rule above; that is why every rule
  has a "how to check a file" clause instead.
- **Swift interop, modules (`@import`), umbrella headers.** Out of scope by hard constraint.
- **`NSURLSession`, `NSURLSessionDownloadTask` for file transfer.** iOS 7. TDLib owns the network
  anyway; do not add a second HTTP stack.
- **Automatic `weakify`/`strongify` macros.** Popular, and they do work under this toolchain, but this
  codebase has 2,386 hand-written `weakSelf` sites and introducing a macro now means either a 2,386-site
  rewrite or two idioms in the tree. Not worth it. §3.3 standardises the hand-written spelling instead.
- **`-Wall -Werror` as a project-wide gate.** Reasonable in general; here the tree was written by
  hundreds of agents against a mixed SDK and turning warnings into errors today would stop the build for
  reasons unrelated to correctness. Fix warnings in files you touch. Note the build already stopped
  suppressing implicit function declarations, which is the one warning class that maps directly to the
  missing-symbol crash of §1.1 — keep that.
- **Instruments-driven optimisation as the first step.** Normally correct advice. Here, Instruments
  against an iOS 6.1.3 device over a jailbreak SSH link is barely workable, so the memory and
  main-thread rules above are stated as budgets and mechanical checks rather than "profile it first".

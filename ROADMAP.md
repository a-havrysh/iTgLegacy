# iTgLegacy Roadmap

A Telegram client for iPhone 3GS/4/4S on iOS 6–7, built on TDLib.

Status legend: **done** · *in progress* · planned · out of scope

---

## Where the project stands

The app was rewritten onto TDLib. libtg — the hand-written MTProto stack it
started with — is gone, along with every screen built on its C structs. What
remains is roughly 2500 lines written for this app plus TDLib itself, loaded at
runtime as `libtdjson.dylib`.

Reference point for "missing": Telegram for iOS, Telegram Desktop and
[Nicegram](https://nicegram.app)-class forks. This list is what those have and
this does not.

---

## 1 · Messaging core

| | Feature | Notes |
|---|---|---|
| **done** | Sign in by phone, code, 2FA password | 1.3 s from launch to authorized on a 4S |
| **done** | Chat list with avatars, previews, unread badges | |
| **done** | Message history, paged | |
| **done** | Send text | |
| **done** | Live updates while a chat is open | `updateNewMessage` |
| **done** | Read receipts sent | `viewMessages` |
| | Reply to a message | quote is currently dropped |
| | Forward a message | source is not shown |
| | Edit a message | no "edited" marker either |
| | Delete a message from the UI | API is wired, no gesture |
| | Draft persistence | typed text is lost on leaving a chat |
| | Typing indicators | |
| | Search in chat and globally | |
| | Pinned message banner | |
| | Message selection and multi-actions | |

## 2 · Media

| | Feature | Notes |
|---|---|---|
| **done** | Photos inline, full-screen viewer | |
| **done** | Video and video notes, played | `MPMoviePlayerViewController` |
| **done** | Voice notes, played | Opus decoded to PCM via libopusfile — iOS 7 cannot decode Opus |
| **done** | WebP stickers | libwebp; the category had to be written, the file in the repo held only a header |
| **done** | Animated `.tgs` stickers | `TGLottieView`, a Lottie subset written for this app |
| **done** | Documents with name and size | |
| **done** | Send a photo from the library | untested — needs a real tap |
| | `.webm` stickers | VP9; no decoder exists on this hardware |
| | Lottie: masks, mattes, trim paths, gradients, repeaters | stickers using them draw approximately |
| | Record and send a voice note | encoder side of Opus |
| | Send video, documents, location, contacts | |
| | Albums (grouped media) | shown as separate messages |
| | Download progress and cancel | |
| | Save to camera roll | |
| | GIF autoplay | plays on tap only |

## 3 · Chats and groups

| | Feature | Notes |
|---|---|---|
| **done** | Basic groups and supergroups | sender names, per-person colours |
| **done** | Service messages | joins, leaves, renames, pins, creation |
| **done** | Forum topics | opens on a topic list |
| **done** | Member count in the header | |
| **done** | Start a new chat from contacts | |
| | Channels | list and read work; posting, comments and reactions do not |
| | Secret chats | disabled at TDLib init |
| | Archive | TDLib reports it; no UI |
| | Chat folders | `updateChatFolders` arrives and is ignored |
| | Mute, pin, leave, delete a chat | |
| | Group member list, admin actions | |
| | Invite links | |

## 4 · Presentation

| | Feature | Notes |
|---|---|---|
| **done** | Skeuomorphic and flat themes, switchable | defaults to what the OS shipped with: skeuomorphic below iOS 7, flat from 7 |
| *in progress* | Skeuomorphic icon set and chrome | app icon, tab bar and buttons still the inherited artwork |
| | Wallpapers | flat colour today |
| | Dark theme | |
| | Font size setting | |
| | Landscape and iPad layouts | portrait iPhone only |
| | 4-inch screen layout check | built for 3.5-inch, never verified on a 5/5c |
| | Localisation | English strings, hardcoded |

## 5 · Platform and delivery

| | Feature | Notes |
|---|---|---|
| **done** | armv7 build that runs on iOS 7.1.2 | `tools/machofix.c` repairs what the linker breaks |
| **done** | TDLib as a dylib | static linking exceeds the 16 MB armv7 branch limit |
| **done** | Unattended device runs | `scripts/devrun.sh`: build, install, launch, log, screenshot |
| *in progress* | iOS 6 support | iOS 7-only calls are guarded; never run on real iOS 6 hardware |
| | Push notifications | needs an `aps-environment` entitlement the build does not have |
| | Background fetch | |
| | arm64 build | Makefile target exists, unexercised since the rewrite |
| | Crash reporting | crash logs are pulled by hand today |

---

## Known constraints

These are not scheduling decisions, they are properties of the target.

**The linker is broken for armv7.** `ld-27036.1` drops the Thumb bit from every
function pointer it writes into data — ObjC method IMPs, C++ vtables, `LC_MAIN`
— and will not emit branch islands past 16 MB. `tools/machofix.c` repairs the
binary after every link. An older Xcode with a working `-ld_classic` would make
it unnecessary.

**No thread-local storage on armv7 Darwin.** clang rejects `__thread` for the
target outright, so TDLib runs single-threaded (`TD_THREAD_UNSUPPORTED`). That
is a performance ceiling on an A5, not a bug to fix.

**Apple's map tiles no longer serve iOS 7.** `MKMapSnapshotter` returns neither
an image nor an error. Locations use a drawn card; a real map needs
self-fetched tiles over plain HTTP, since TLS negotiation with modern servers
mostly fails on this system.

**No VP9 decoder.** `.webm` stickers and videos will stay static thumbnails
unless one is ported.

---

## Next up

1. Reply, forward and edit — the three most-noticed gaps in daily use.
2. Recording voice notes; the decode half is already done.
3. Skeuomorphic icon set, so the theme switch covers chrome and not just colour.
4. Archive and chat folders — TDLib already sends both.
5. Verify on real iOS 6 hardware.

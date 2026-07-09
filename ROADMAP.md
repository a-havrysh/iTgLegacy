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
| **done** | Reply to a message | quoted message shown above the reply |
| **done** | Forward a message | source is named on the message |
| **done** | Edit a message | marked as edited |
| **done** | Delete a message from the UI | long press |
| **done** | Draft persistence | |
| **done** | Typing indicators | takes over the header subtitle |
| **done** | Search in chat and globally | in-chat search lives in the profile |
| **done** | Pinned message banner | |
| **done** | Reactions | shown on messages; can add a thumbs up |
| | Message selection and multi-actions | one message at a time |
| **done** | Jump to the quoted message | scrolls and flashes it |
| | Unread separator and jump-to-unread | history opens at the bottom |
| | Scheduled and silent sending | |
| **done** | Saved Messages | from the Folders menu |

## 2 · Media

| | Feature | Notes |
|---|---|---|
| **done** | Photos inline, full-screen viewer | hold to save |
| **done** | Video and video notes, played | `MPMoviePlayerViewController` |
| **done** | Voice notes, played | Opus decoded to PCM via libopusfile — iOS 7 cannot decode Opus |
| **done** | WebP stickers | libwebp; the category had to be written, the file in the repo held only a header |
| **done** | Animated `.tgs` stickers | `TGLottieView`, a Lottie subset written for this app |
| **done** | Documents with name and size | |
| **done** | Send a photo from the library | untested — needs a real tap |
| | `.webm` stickers | VP9; no decoder exists on this hardware |
| | Lottie: masks, mattes, trim paths, gradients, repeaters | stickers using them draw approximately |
| **done** | Record and send a voice note | libopusenc; hold the microphone |
| **done** | Send video, location, contacts | documents still missing - no file browser on iOS 7 |
| **done** | Albums (grouped media) | one block, one timestamp |
| *in progress* | Download progress and cancel | progress shown; no cancel |
| **done** | Save to camera roll | hold the full-screen picture |
| | GIF autoplay | plays on tap only |
| *in progress* | Send stickers | a strip of recent stickers; animated ones stand in as their emoji |
| | Sticker sets: install, browse, favourites | |
| *in progress* | Photo viewer | zooms; no swipe between photos |
| | Polls and quizzes | not rendered |

## 3 · Chats and groups

| | Feature | Notes |
|---|---|---|
| **done** | Basic groups and supergroups | sender names, per-person colours |
| **done** | Service messages | joins, leaves, renames, pins, creation |
| **done** | Forum topics | opens on a topic list |
| **done** | Member count in the header | |
| **done** | Profile screen | avatar, username, phone, members, shared media |
| **done** | Sender avatars in groups | Telegram's own placeholder palette and mapping |
| **done** | Start a new chat from contacts | |
| *in progress* | Channels | read, join, mute; comments and reactions do not |
| | Secret chats | disabled at TDLib init |
| **done** | Archive | a row above the list |
| **done** | Chat folders | offered from the Folders button |
| **done** | Mute, pin, leave, delete a chat | hold a row in the list |
| *in progress* | Group member list, admin actions | list is in the profile; no admin actions |
| | Invite links | |
| | Create a group or channel | join only |
| | Create and manage forum topics | read only |
| | Block a user, report | |
| **done** | Online status and last seen | in the header of a private chat |

## 4 · Presentation

| | Feature | Notes |
|---|---|---|
| **done** | Skeuomorphic and flat themes, switchable | defaults to what the OS shipped with: skeuomorphic below iOS 7, flat from 7 |
| *in progress* | Skeuomorphic icon set and chrome | app icon, tab bar and buttons still the inherited artwork |
| | Dark theme as a built-in | available today only by importing one |
| | Wallpapers from Telegram's own collection | `getBackgrounds` is not called |
| | Font size setting | |
| | Landscape and iPad layouts | portrait iPhone only |
| | 4-inch screen layout check | built for 3.5-inch, never verified on a 5/5c |
| | Localisation | English strings, hardcoded |
| **done** | Themes from the official clients | `.tgios-theme` JSON and `.attheme`; zipped exports rejected |
| **done** | Chat wallpaper | a picture from the library |

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

## 6 · Not attempted, and why

These are the rest of the difference against Telegram for iOS. They are listed
so the gap is honest, not because each is scheduled.

| Feature | Why it is not here |
|---|---|
| Voice and video calls | needs WebRTC; no build of it exists for armv7 iOS 7, and the A5 could not run video anyway |
| Stories | a large surface built on features above (viewer, reactions, privacy) |
| Premium: emoji status, custom emoji, boosts | custom emoji alone needs an animated-emoji renderer per message |
| Secret chats | disabled at TDLib init; end-to-end key handling on top of everything else |
| Bots: inline mode, keyboards, web apps | inline results and web apps need a browser surface |
| Live locations | a background location task the OS will kill |
| Payments, gifts, Stars | payment sheets and a web view |
| Translation and transcription | server features gated behind Premium |
| Multiple accounts | one TDLib client instance today |
| Chat archive settings, auto-delete timers | small, just not written |
| Privacy and security settings, sessions, blocked users | a settings tree of its own |
| Auto-download and storage settings | TDLib exposes them; no UI |
| Notification settings per chat | mute is all there is |
| Username, bio and profile photo editing | the profile screen is read-only |

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

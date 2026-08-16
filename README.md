# iTgLegacy

Read this in other languages: [Русский](README_RU.md)

A Telegram client for legacy iOS devices, built on TDLib and wearing the visual
language of Telegram for iOS as it was in 2013.

This is a fork of [bla1r1/iTgLegacy](https://github.com/bla1r1/iTgLegacy),
which in turn descends from the work of Igor V. Sementsov
([@igkuzm](https://github.com/igkuzm)). See [Credits](#credits) below.

## What this fork does differently

The upstream project shipped a client that ran on old hardware. This fork keeps
that goal and adds a second one: the interface should be the one those devices
originally had.

- **The 2013 interface, reproduced from the original source.** Layout, metrics,
  artwork and interaction come from the real pre-redesign Telegram for iOS —
  bubble cap insets, the dialog list cell's baked-in separator, the toolbar
  button art, the profile header's avatar bevel. Notes from that
  reverse-engineering live in [`docs/original-study/`](docs/original-study/).
- **Modern functionality underneath.** Everything the current client does that
  TDLib exposes: folders, reactions, stories, saved messages, polls, premium
  surfaces, secret chats, stickers, video messages, calls.
- **Devices without a modern glyph set.** Emoji added to Unicode after iOS 6 are
  drawn from a bundled atlas through CoreText, because the system font on
  6.1.3 stops at Unicode 6.0.
- **iPad.** A split layout on the tablet — chat list on the left, conversation
  on the right — with the phone's tab-bar layout untouched.

## Supported Devices and Architectures

- **armv7 (32-bit)**: iOS 6.0+ — iPhone 3GS, 4, 4S, 5; iPad 2/3/4; iPod Touch 4/5.
- **arm64 (64-bit)**: iOS 7.0 – 12.5.7 — iPhone 5s through X, iPad Air/Pro.
- **Universal**: fat binary containing both slices.

Development is done against a jailbroken iPhone 4S on iOS 6.1.3 and an iPad 2.

## Telegram API Credentials

Before building for real use, configure your own Telegram API credentials:

1. Copy [`include/tg_config.h.example`](include/tg_config.h.example) to `include/tg_config.h`:
   ```bash
   cp include/tg_config.h.example include/tg_config.h
   ```
2. Register your client at https://my.telegram.org (under *API development tools*).
3. Fill in `TG_API_ID` and `TG_API_HASH`:

```c
#define TG_API_ID   YOUR_API_ID
#define TG_API_HASH "YOUR_API_HASH"
```

> `include/tg_config.h` is git-ignored. Keep your own credentials out of commits
> and out of any archive you share — they identify your application to Telegram.

## Repository Layout

```
iTgLegacy/
├── Makefile           # Master build file - there is no Xcode project
├── src/               # Objective-C sources
├── tdlib/             # Telegram Database Library (git submodule)
├── include/           # Third-party C headers and tg_config.h.example
├── images/            # Application assets, including the emoji atlas
├── design-reference/  # Genuine 2013 screenshots the redesign follows
├── docs/              # Design language, original-source study, audits
├── scripts/           # Build and device-deployment automation
├── tools/             # Helper programs (machofix, asset generators)
└── build/             # Build outputs (git-ignored)
```

## Prerequisites

macOS with Xcode and the iOS SDK, plus:

```bash
brew install cmake gperf openssl@1.1 ccache
```

## Building

```bash
git clone --recursive https://github.com/a-havrysh/iTgLegacy.git
cd iTgLegacy
make ipa-armv7
```

### Build Targets

- `make ipa` — all packages (armv7, arm64 and the universal fat IPA).
- `make ipa-armv7` — 32-bit build for iOS 6.0+.
- `make ipa-arm64` — 64-bit build for iOS 7.0 – 12.5.7.
- `make app` — the `.app` bundle.
- `make deps` — extract static third-party libraries into `build/libs`.
- `make tdlib` — compile TDLib for iOS.
- `make clean` — remove intermediate build artifacts.

TDLib is loaded at runtime from `libtdjson.dylib` rather than linked, because a
statically linked copy pushes `__TEXT` past the armv7 branch limit.

## Credits

- **Original author**: Igor V. Sementsov ([@igkuzm](https://github.com/igkuzm))
- **Upstream**: [bla1r1/iTgLegacy](https://github.com/bla1r1/iTgLegacy)
- **This fork**: [a-havrysh/iTgLegacy](https://github.com/a-havrysh/iTgLegacy)

Licensed under GPLv3, as upstream.

## Disclaimer

Provided for legacy hardware preservation and educational purposes. Use at your
own risk.

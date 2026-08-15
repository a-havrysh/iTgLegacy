# TGLoginPhoneController (2013 original)

Sources studied:

- Original: `telegram-original-sources/extracted/telegram_iphone.src/Telegraph/Telegraph/TGLoginPhoneController.h` (19 lines) and `.../TGLoginPhoneController.m` (836 lines). Cited below as `orig .m:N`.
- Strings: `.../Telegraph/Telegraph/en.lproj/Localizable.strings`.
- Artwork: `.../Telegraph/Telegraph/Resources/` (all `@2x` only; the non-retina names the code asks for do not exist in the archive — see "Artwork").
- Our port: `/Users/alexanderhavrysh/Git/iOS/iTgLegacy/src/TGLoginViewController.m` (2292 lines), which folds every login step into one controller.
- Later lineage: `/Users/alexanderhavrysh/Git/iOS/twelve/Telegraph/TGLoginPhoneController.m` (1078 lines).
- Modern: `Telegram-iOS/submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift`, `submodules/PhoneInputNode/Sources/PhoneInputNode.swift`.

---

## 1. What it is

The second screen of the sign-up flow: country picker button on top, a two-cell white input plate below it (dial code | national number), a grey explanatory line above both, and a "Next" done-button in the navigation bar. It runs on the dark ("black") login chrome — `self.style = TGViewControllerStyleBlack` (orig .m:76) — with the back button drawn from custom login artwork rather than a system bar button.

Its single call site is the welcome screen: `TGLoginWelcomeController.m:705-706` allocates it with a bare `init` and pushes it animated. Nothing else in the app instantiates it, and nothing calls the public `setPhoneNumber:` in the shipped 1.1 tree (only its own declaration exists — grep for `setPhoneNumber:` across `Telegraph/Telegraph/*.m` returns just `TGLoginPhoneController.m:93`). It is a hook for restoring a saved, interrupted login: the format it parses is exactly the format the controller itself writes back on success (orig .m:795).

## 2. Public surface

```objc
@interface TGLoginPhoneController : TGViewController <ASWatcher>
@property (nonatomic, strong) ASHandle *actionHandle;
- (void)setPhoneNumber:(NSString *)phoneNumber;
@end
```

`setPhoneNumber:` takes a single string `"<dialcode>|<national>"`, e.g. `"+44|7700 900123"`. Contract details that matter:

- If the string contains no `|`, it returns silently and changes nothing (orig .m:95-96). There is no validation beyond that.
- The country part keeps its leading `+` (it is stored verbatim into `_countryCodeField.text`, orig .m:109), because the writer side formats it as `_countryCodeField.text` which already begins with `+` (orig .m:795).
- If the view is not loaded yet the values are parked in `_presetPhoneCountry` / `_presetPhoneNumber` and applied at the end of `loadView` (orig .m:101-102, .m:253). Applying consumes them — both are nil'd (orig .m:112-113) — so a preset is applied exactly once.
- Applying re-runs the whole derived-state chain: `updatePhoneTextForCountryFieldText:`, `updateCountry`, `updateTitleText` (orig .m:115-117). This is the general rule of the class: every mutation of either field is followed by those three calls in that order.

`actionHandle` is the ActionStage watcher handle; it exists so the modally presented countries controller can call back (`countriesController.watcherHandle = _actionHandle`, orig .m:767).

## 3. Layout — every number and where it comes from

All layout lives in `-updateInterface:` (orig .m:301-324), which is driven by `controllerInsetUpdated:` (orig .m:294-299). Note that it is always called with `UIInterfaceOrientationPortrait` from that path, so the landscape branches only fire through other callers of `updateInterface:` in `TGViewController`.

The layout box is computed, not measured (orig .m:307-311):

```
screenSize = [TGViewController screenSizeForInterfaceOrientation:orientation]
viewSize.height = screenSize.height - 20 (status bar)
                                    - 44 portrait / 32 landscape (nav bar)
                                    - 216 (keyboard, assumed permanently up)
width = 290 portrait, 320 landscape
topOffset = MIN(controllerInset.top, 70)
```

The `216` is hard-coded (orig .m:309): the keyboard is a number pad which is always on screen here (`viewWillAppear` makes the phone field first responder unconditionally, orig .m:289), so the controller never reflows for keyboard show/hide. The `MIN(..., 20 + 50)` cap on `topOffset` (orig .m:305) protects against the in-call status bar doubling the inset.

Positions:

| Element | Frame | Citation |
|---|---|---|
| Country button | x = `(int)((viewSize.width - width) / 2)`, y = `topOffset + (int)((viewSize.height - 68) / 2) + (landscape ? -16 : 4 + (retina ? 0.5 : 0))`, w = 290/320, h = image height (55pt) | orig .m:313 |
| Input plate | x same, y = countryButton.maxY + (landscape ? 0 : retina ? 7.5 : 7), w same, **h = 47** (a literal, not the artwork height), `CGRectIntegral` | orig .m:314 |
| Divider | `CGRectMake(60, 1, 1, plateHeight + 1)`, inside the plate | orig .m:189 |
| Country code field | plate.x + 4, plate.y + 12, 54 × 22 | orig .m:322 |
| Phone field | plate.x + 74, plate.y + 2, plate.width − 74 − 14, 32 | orig .m:323 |
| Notice label | width-fit to max 270pt, centred horizontally, y = countryButton.y − 16 − noticeHeight | orig .m:316-318 |
| Arrow in country button | x = buttonWidth − arrowWidth − 15, y = 16, autoresizes with flexible left margin | orig .m:178-180 |

The `68` in the vertical centring is the design height of the pair (55pt button + 7pt gap + a nudge), used to centre the two-row block inside the space above the keyboard. The half-pixel additions (`retina ? 0.5 : 0`) exist because the plate and the button artwork have a 1-device-pixel top bevel that goes soft when landed on a whole point.

The base frames of the three shakeable views are cached at layout time into `_baseInputBackgroundViewFrame`, `_baseCountryCodeFieldFrame`, `_basePhoneFieldFrame` (orig .m:314, .m:322-323). This is not decoration: the shake animation is fed the cached x, never the live x, so a shake triggered while an earlier shake is mid-flight still restores the correct resting position (orig .m:744-746).

**Overflow behaviour of the notice label**: it is `numberOfLines = 0`, word-wrapping, centred (orig .m:158-161), sized against a 270pt box, and positioned *upwards* from the country button. So a longer translation grows towards the navigation bar and can run off the top. The original's answer is blunt: `_noticeLabel.alpha = _noticeLabel.frame.origin.y < 0 ? 0.0f : 1.0f` (orig .m:320) — if it would clip, it disappears entirely rather than colliding with the title bar. This is the one piece of adaptive behaviour in the whole screen and it is easy to miss.

## 4. Typography and colour

| What | Value | Citation |
|---|---|---|
| Notice label font | `systemFontOfSize:14` | orig .m:152 |
| Notice text colour | `#c0c5cc` | orig .m:153 |
| Notice shadow | `#323c4a`, offset (0, 1) | orig .m:154-155 |
| Country button title font | `boldSystemFontOfSize:` **16.5 on retina, 16 otherwise** | orig .m:168 |
| Country title colour, normal | `#f0f0f0` | orig .m:171 |
| Country title shadow, normal | `#17191d`, offset (0, 1) | orig .m:172, .m:175 |
| Country title, highlighted | pure white, shadow cleared | orig .m:173-174 |
| Country title, no matching country | `#f0f0f0` at **alpha 0.7** | orig .m:676 |
| Country title insets | `UIEdgeInsetsMake(0, 14, 9, 14)` — bottom 9 lifts the text off the plate's lower bevel | orig .m:176 |
| Dial code field font | `boldSystemFontOfSize:18`, centred | orig .m:196, .m:199 |
| Phone field font | `boldSystemFontOfSize:18` | orig .m:206 |
| Phone field **placeholder** font | `systemFontOfSize:17` — regular weight, one point smaller than the text | orig .m:207 |
| Phone field placeholder colour | `#999999` | orig .m:212 |
| Both fields' background | `#f5f5f5` (they are opaque rectangles sitting *on top of* the plate artwork, not transparent) | orig .m:197, .m:208 |
| Back button text/shadow | white on `#050608` at 0.4 alpha | orig .m:134 |
| Next button shadow (from TGToolbarButton) | `#042651` at 0.3 alpha, white text | `TelegraphKit/TGToolbarButton.m:195-196`, :187 |

The placeholder font/colour are set through `TGHacks` (orig .m:207, .m:212) because in iOS 6 `UITextField` gave no public API for either.

## 5. Artwork

| Asset | Use | Stretch | Pixel size (@2x) |
|---|---|---|---|
| `LoginCountry.png` / `_Highlighted` | country button background | `stretchableImageWithLeftCapWidth:(w - 16) topCapHeight:0` — i.e. the *right* 16pt are the fixed cap, everything left of that is the stretch column (orig .m:166-167) | 174 × 110 → 87 × 55 pt |
| `LoginCountryArrow.png` / `_Highlighted` | disclosure chevron, as a `UIImageView` with a highlighted image so it tracks the button (orig .m:178) | none | 18 × 30 → 9 × 15 pt |
| `LoginInput.png` | input plate | left cap = w/2, top cap = h/2, i.e. a nine-part stretch from a 30 × 43 pt tile (orig .m:185) | 60 × 86 |
| `LoginInputDivider.png` | 1pt vertical rule between the two cells | left cap 0, top cap 4 (orig .m:188) | 2 × 82 |
| `BackButton_Login[_Pressed][_Landscape…].png` | four back-button states, all with `leftCapWidth:15` (orig .m:129-132) | | |

Two things to know before copying: the country button's stretch is unusual (cap on the right, not the middle) because the artwork's rounded right end must stay intact while the label side grows; and the plate is 43pt tall in the artwork but is laid out at 47pt (orig .m:314), so the mid-section is always stretched by 4pt — the plate is never drawn at native size.

The archive ships only `@2x` files. The code loads unsuffixed names, so a 1× device would fall back to nothing; either the non-retina set was stripped from this snapshot or the build was retina-only. For a 4S this is moot, but the `TGIsRetina()` branches in the source (orig .m:168, .m:313, .m:314) show the original still cared.

## 6. Behaviour

### Initial country guess (orig .m:218-240)

1. `CTTelephonyNetworkInfo.subscriberCellularProvider.isoCountryCode` — the SIM's country, not the network's.
2. If nil, `NSLocale currentLocale`'s `NSLocaleCountryCode`.
3. `[TGLoginCountriesController countryNameByCountryId:code:]` maps that to a dial code.
4. **If the lookup yields 0, the code falls back to `1`** (orig .m:237-238) — the field is never left as a bare `+`. The returned country *name* is discarded (`__unused`); the button label is recomputed from the code by `updateCountry`.

### Dial code field editing (orig .m:366-415)

Everything is done in `shouldChangeCharactersInRange:` which always returns `false` and assigns `textField.text` itself.

- Non-digits are stripped from the replacement string (orig .m:372-377).
- A deletion that would remove the leading `+` is refused: if `filteredLength == 0 && (range.length == 0 || range.location == 0)` return false (orig .m:379-380); and any edit at location 0 is bumped to location 1 (orig .m:382-383). The `+` is structural and cannot be deleted.
- Maximum is 5 characters total, i.e. `+` plus 4 digits (orig .m:402-403).
- **The spill trick** (orig .m:388-401): when the new text exceeds 5 characters — which in practice happens when a long number is pasted or typed straight into the dial cell — it walks suffix lengths, asking `countryNameByCode:` for each shorter prefix. As soon as a prefix is a real dial code, the trailing digits are prepended to the phone field, the dial field is truncated to the matching prefix, and **first responder moves to the phone field** (orig .m:396-398). Typing `380671234567` into the code cell therefore lands as `+380` / `67 123 45 67` with the caret in the right place.

### Phone field editing (orig .m:416-560)

The live branch is guarded by `if (true)` with a dead `else` below it (orig .m:418, .m:561-588) — leftover from the rewrite; the dead branch is the older, simpler "cap at 19 characters" version and should not be ported.

The live algorithm is a reformat-on-every-keystroke with caret preservation:

1. Strip the replacement to digits (orig .m:420-444, done twice, redundantly).
2. Rebuild a digits-only `rawText` from the current field text, and translate the edit `range` from formatted-string coordinates into raw-digit coordinates by decrementing for every separator character passed (orig .m:446-470).
3. Special case: a backspace whose translated length collapsed to zero (the user deleted a separator such as `)` or a space) is retargeted to delete the digit before it (orig .m:473-477). Without this, backspacing over a bracket would do nothing.
4. Format `countryCode + rawDigits` through `TGStringUtils formatPhone:forceInternational:false`, then strip the country code back off by walking the formatted string until every character of the country code has been consumed, then skip forward to the first `(`, `)` or digit (orig .m:491-518). The formatter only knows how to format whole international numbers, so the national part is obtained by subtraction.
5. Recompute the caret: walk formatted and raw in lockstep, advancing the caret by one for every inserted separator (orig .m:525-540), then set `selectedTextRange`.
6. The whole block is wrapped in `@try/@catch` logging the exception (orig .m:483, .m:554-557) — the author did not trust the index arithmetic. Worth remembering: on a malformed input the original degrades to "text unchanged", never crashes.

`filterPhoneText:` (orig .m:594-607) is the guard against formatter residue: if the resulting string contains no digit at all, it becomes `@""`. That is what stops the field from being left holding a lone `(` or `+` after a delete.

### Backspace at position zero

`TGBackspaceTextField` reports an empty-field backspace and the controller moves focus to the dial code field (orig .m:356-359). This is what makes the two cells feel like one field.

### Tapping the plate (orig .m:694-703)

The plate itself carries a tap recognizer. A tap left of the dial field's right edge focuses the dial field, otherwise the phone field. The threshold is the *field's* right edge (x = plate.x + 4 + 54 = 58 in plate coordinates), not the divider at 60 — a 2pt sliver next to the divider counts as the phone side.

### Title (orig .m:646-662)

The navigation title is live: it shows `Login.PhoneTitle` ("Your Phone") whenever the phone field is empty, the digits are empty, or the dial code is just `+`; otherwise the full number formatted with `forceInternational:true`, i.e. including the `+CC` prefix. Note the asymmetry — the field is formatted nationally, the title internationally, from the same digits.

### Country button (orig .m:664-679, .m:764-779, .m:817-834)

- Title = country name for the current dial code, at full opacity.
- No match: title is `Login.CountryCode` ("Country Code") when the field is just `+`, else `Login.InvalidCountryCode` ("Invalid Country Code"), both at 70% opacity. The button stays tappable in every state.
- Tapping presents `TGLoginCountriesController` **modally**, wrapped in a fresh `TGNavigationController`, and copies the presenting bar's `defaultPortraitImage` / `defaultLandscapeImage` onto the new bar plus `setShadowMode:true` (orig .m:769-776) so the modal keeps the dark login chrome instead of reverting to the default blue.
- The selection comes back through ActionStage as `"countryCodeSelected"` with `name` and `code`. The handler dismisses, sets the button title from `name` directly (not via `updateCountry`, so the picker's spelling wins), writes `+code`, reformats the phone text and the title (orig .m:825-831). If `code` is absent the modal is still dismissed and nothing else changes.

### Next (orig .m:737-762)

Validation is deliberately loose: it fails only if the phone field is empty **or** the dial code is shorter than two characters (orig .m:742). Any non-empty digit string is sent to the server — the server, not the client, decides what a valid number is. On failure: shake the phone field, the plate and the dial field simultaneously (orig .m:744-746) and focus whichever one is at fault, code first (orig .m:748-751).

The shake (orig .m:705-735): +4pt for 0.05s autoreversed, then −4pt for 0.05s autoreversed repeated 3 times, then hard-restore to the cached frame. Total ≈ 0.4s. Both completion paths restore the frame, including the non-`finished` path.

On success: `inProgress = true`, then `ActionStageInstance() requestActor:@"/tg/service/auth/sendCode/(N)"` with a monotonically increasing `N` from a function-static counter (orig .m:757-758) so a stale reply from an earlier attempt is ignored by the path comparison in `actorCompleted:` (orig .m:785).

`_phoneNumber` is assembled as dial-code-minus-`+` concatenated with the *formatted* phone text (orig .m:759) — brackets, spaces and dashes included. The formatting is stripped further down the stack, not here.

### Busy state (orig .m:326-352)

`setInProgress:` is a single toggle guarded by an equality check:

- Next button: disabled, text set to `@""`, and a small white `TGActivityIndicatorView` (created in `loadView` and pre-centred inside the button, orig .m:143-146) is unhidden and started. The button keeps its width because `sizeToFit` is *not* called on the way in — only on the way out (orig .m:345) — so it never shrinks to nothing and then jumps back.
- `_shadeView`, a full-bounds transparent `UIView` added last (orig .m:242-245), is unhidden. It is fully transparent: its only job is to swallow taps on the country button and the plate. Text editing is separately blocked by the early `if (_inProgress) return false;` in the delegate (orig .m:363-364), because a first-responder text field still receives keystrokes through a covering view.

### Results (orig .m:783-815)

Everything is dispatched to the main queue, `inProgress` is cleared first, then:

- Success: `phoneCodeHash` is pulled out of the graph node and the whole login state is persisted via `saveLoginStateWithDate:phoneNumber:...` with the phone stored in the `"+CC|national"` form (orig .m:795) — the exact format `setPhoneNumber:` parses. Then `TGLoginCodeController` is pushed, and it is told whether to show a keyboard based on whether either field is currently first responder (orig .m:797), so focus carries across the push instead of the keyboard dropping and rising again.
- Failure: a plain `UIAlertView` with no title, one OK button, message chosen from `TGSendCodeErrorInvalidPhone` → `Login.InvalidPhoneError`, `…FloodWait` → `Login.CodeFloodError`, `…Network` → `Login.NetworkError`, default `Login.UnknownError` (orig .m:801-811). The fields are not cleared, nothing is shaken, focus is untouched.

### Navigation

`self.navigationItem.hidesBackButton = true` (orig .m:78) and a custom back button is installed via `setBackAction:` (orig .m:134). `performClose` removes the ActionStage watcher and clears `inProgress` before popping (orig .m:256-262), so an in-flight sendCode cannot come back to a popped controller. Rotation: everything except upside-down (orig .m:277-280).

### Strings

```
Login.PhoneTitle          = "Your Phone"
Login.PhonePlaceholder    = "Your phone number"
Login.PhoneAndCountryHelp = "Please confirm your country code and enter your phone number."
Login.CountryCode         = "Country Code"
Login.InvalidCountryCode  = "Invalid Country Code"
Login.InvalidPhoneError   = "Invalid phone number. Please try again."
Login.CodeFloodError      = "Limit exceeded. Please try again later."
```
(`en.lproj/Localizable.strings:176, 186-187, 193-196`)

---

## 7. Our port

Ours is `TGLoginViewController` — one controller for all login steps, with the phone step as `TGLoginStepPhone`. The phone-step visuals were ported carefully and most of them are right: notice label 14pt `#c0c5cc` on `#323c4a` shadow (`TGLoginViewController.m:1197-1200` and :459-462), country button bold 16.5 with `#f0f0f0` / `#17191d` and `UIEdgeInsetsMake(0, 14, 9, 14)` (:484-492), the right-cap-16 stretch (:481), arrow at `width − w − 15, 16` (:500), plate 290 × 47 with divider at x=60 (:980-983), dial field 4/12/54/22 and phone field 74/2/−88/32 (:984-986), disabled-country-title alpha 0.7 with the same two fallback strings (:740-742), the shake geometry (:1135-1162), and the transparent shade view (:642-646). Those need no work.

The differences a user can see:

**1. Placeholder font and colour are wrong.** Original: `systemFontOfSize:17` regular, `#999999` (orig .m:207, .m:212). Ours passes `self.inputField.font` — bold 18 — and `#999da4` (`TGLoginViewController.m:836`). The placeholder therefore reads as bold, one point too large, and slightly blue-grey. Fix: pass `[UIFont systemFontOfSize:17]` and `tgRGB(0x999999)` for the phone step.

**2. Dial-code overflow is dropped instead of spilled.** `countryCodeChanged` truncates to 4 digits and discards the rest (`TGLoginViewController.m:1184-1187`). The original walks prefixes, moves the surplus digits into the phone field and jumps first responder there (orig .m:388-401). Anyone who types or pastes a full international number into the left cell loses everything past the fourth digit in ours; in the original it lands correctly split. This is the biggest functional regression on the screen.

**3. Next is gated at 4 national digits.** `hasSubmittableInput` requires `digitsOnly(text).length >= 4` (`TGLoginViewController.m:1113`); the original requires only non-empty (orig .m:742). Short test numbers and any genuinely short national format are refused client-side with a shake and never reach the server. Change to `> 0` to match.

**4. Shake reads the live frame.** Ours captures `view.frame` at the start (`TGLoginViewController.m:1138`); the original passes the cached base x (orig .m:744-746). Tap Next twice within the ~0.4s animation and ours re-bases on an already-displaced frame, leaving the row permanently offset by up to 4pt. Cache the layout frames in `layoutPhoneRowForViewSize:` and shake against those.

**5. No landscape geometry.** Ours reads `[UIScreen mainScreen].bounds.size` and always subtracts a 44pt bar (`TGLoginViewController.m:857-859`), and the phone row is hard-coded to width 290 (:971). The original uses 320pt wide, a 32pt bar and a −16pt vertical nudge in landscape (orig .m:308, :311, :313). If we allow rotation at all, the landscape layout is wrong; if we do not, this is a non-issue — worth an explicit decision rather than an accident.

**6. Phone formatting covers three cases, not the world.** Ours formats only `+1` (3-3-4 with brackets) and `+7` (3-3-2-2), returning raw digits for everything else (`TGLoginViewController.m:200-229`), and the country→dial map is a hand-written 70-entry dictionary (:150-171). The original goes through `TGStringUtils formatPhone:` and `TGLoginCountriesController`'s full table. A Ukrainian, German or Indian number shows as an unbroken digit run in ours and grouped in the original, and a SIM from any country outside our 70 falls through to no prefill. Also `updateTitleText` in ours emits `"+CC national"` with a plain space (:242), while the original re-runs the formatter with `forceInternational:true` (orig .m:661) — different spacing in the navigation title for the same number.

**7. Divider initial height.** Ours creates the divider at height 48 (`TGLoginViewController.m:528`) and only later sets `plateHeight + 1` = 48 in `layoutPhoneRowForViewSize:` (:983); the original uses `plateHeight + 1` in both places (orig .m:189). Same value today, but ours will silently desync on the steps that use a different plate height. Cosmetic, low priority.

**8. No preset-number restore.** The original persists `"+CC|national"` on success and can be re-seeded from it (orig .m:93-119, :795). Ours stores `savedPhoneNumber` as a flat `+CCnational` string (`TGLoginViewController.m:1235`) and has no path that repopulates the two cells from a previous interrupted session. Not visible on a first run; visible if a user backgrounds the app mid-login.

**9. Country-code guess is asynchronous.** Ours asks the server (`guessedCountryCodeWithCompletion:`, :655) and only prefills if the user has not already typed (:663). The original reads the SIM synchronously in `loadView` and always has a value by the time the screen appears, falling back to `+1` (orig .m:237-238). Ours can show the screen with a default and then change it under the user's finger a moment later. Defensible as an improvement, but it is a behaviour difference, and the `+1` last-resort fallback should be kept either way.

## 8. What became of it

**twelve** (`twelve/Telegraph/TGLoginPhoneController.m`, 1078 lines) keeps the class name and the whole field/formatting machinery but throws away the 2013 skin: white background (`:134`), a large light-weight title *label* inside the content instead of a navigation title — `TGLightSystemFontOfSize(30.0f)`, y = 71 on widescreen else 48 (`:141-146`) — and a stock `UIBarButtonItemStyleDone` bar button instead of `TGToolbarButton` (`:88`). That is the iOS 7 flattening, forced by the platform, not a rethink of the screen. Its genuine additions are feature-driven: a terms-of-service label shown only once a country is resolved (`:810`, laid out from the bottom above the keyboard at `:431-439`), a proxy-setup escape hatch on connection failure (`:995`), and a "contact support by email" path when sign-in is blocked (`:1006-1022`). The shape of the screen — country button, two-cell plate, live title — is unchanged, which is the useful signal: the 2013 interaction model survived the redesign intact.

**Telegram-iOS** splits the component in two. `PhoneInputNode` owns the two text fields and the number logic; `AuthorizationSequencePhoneEntryControllerNode` owns the surrounding screen. Three changes matter to us:

- Formatting became data-driven. Instead of the original's hand-rolled reformat-and-recount-the-caret loop, the modern node applies a per-country *mask* (`formatPhoneNumberToMask(numberText, mask: mask.string)`, `PhoneInputNode.swift:303`) fetched from the server's country list. Our port's hard-coded `+1`/`+7` grouping is the same idea at 3% coverage; if we ever want real formatting, the mask table is the concept to steal, not the code.
- Pasting is a first-class case: `if range.length == 0, string.count > 1 { updateNumber(cleanPhoneNumber(string), tryRestoringInputPosition: false) }` (`PhoneInputNode.swift:252-255`). Thirteen years later the multi-digit paste still needed a special path, which retroactively justifies the original's spill trick.
- The country button gained a flag emoji and truncation (`…Node.swift:160`, `:90-91`), lost the dark plate for a flat row, and the primary action moved from a navigation-bar button to a `SolidRoundedButtonNode` in the body (`:321`). The 2013 grey helper line survived verbatim as `Login_PhoneAndCountryHelp` (`:421`) — same string, now 17pt regular in the list primary colour.

The `checkPhone` closure (`:359`, `PhoneInputNode` `:206`) is the modern equivalent of `nextButtonPressed`, and the `inProgress` flag still disables the country button exactly as `_shadeView` did (`:365`).

## 9. Genuinely ambiguous

- Whether `updateInterface:` was ever reached with a landscape orientation in the shipped app is not determinable from this file: the only in-file caller passes portrait (orig .m:298), and the landscape branches would have to be driven from `TGViewController`, whose implementation I did not read for this study.
- The non-retina artwork is absent from the archive, so I cannot confirm the 1× metrics; the `TGIsRetina()` branches imply a 1× set existed.

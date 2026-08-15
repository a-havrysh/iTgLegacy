# TGMapViewController — the 2013 location screen

Sources studied (all read in full):

- `telegram-original-sources/extracted/telegram_iphone.src/TelegraphKit/TelegraphKit/TGMapViewController.h` (24 lines)
- `.../TGMapViewController.m` (922 lines)
- `.../TGMapView.h` / `.m` (13 / 27 lines)
- `.../TGMapAnnotationView.h` / `.m` (21 / 50 lines)
- `.../TGCalloutView.h` / `.m` (16 / 182 lines) — the callout is inseparable from the controller
- call sites in `.../TGConversationController.mm`

The class exists under exactly that name. Everything below is cited by file and line.

---

## 1. What it is for

One controller serving two unrelated screens, chosen at init time by an enum
(`TGMapViewControllerMode`, `TGMapViewController.m:19-22`):

- **Pick mode** (`TGMapViewControllerModePick = 0`) — the "attach location" sheet. Presented
  *modally* inside a `TGNavigationController` from the chat's attach menu
  (`TGConversationController.mm:2798-2805`, `attachLocationPressed`). Title `Map.ChooseLocationTitle`
  = "Location" (`Localizable.strings:516`), Cancel on the left, Send on the right.
- **Map mode** (`TGMapViewControllerModeMap = 1`) — viewing a location someone sent. *Pushed* on the
  chat's own navigation stack (`TGConversationController.mm:7207-7220`, action `openMap`). Title
  `Map.MapTitle` = "Map" (`Localizable.strings:517`), an actions button on the right.

The mode is not a runtime switch: every branch in `loadView` and in the `MKMapViewDelegate`
callbacks tests `_mode`, and the two paths share only the map, the locate button and the map-type
button group.

## 2. Public surface

```objc
@interface TGMapViewController : TGViewController <ASWatcher>
@property (nonatomic, strong) ASHandle *watcher;        // owner's handle — how results get out
@property (nonatomic, strong) ASHandle *actionHandle;   // self handle, given to the callout
@property (nonatomic, strong) id message;               // TGMessage, map mode only, for Forward
- (id)initInPickingMode;
- (id)initInMapModeWithLatitude:(double)latitude longitude:(double)longitude user:(TGUser *)user;
@end
```
(`TGMapViewController.h:14-24`)

There is no delegate protocol and no completion block. Results leave through ActionStage: the
controller calls `actionStageActionRequested:options:` on `_watcher.delegate`. Three actions exist:

| action | sent from | options | handled at |
|---|---|---|---|
| `mapViewFinished` | Cancel (`:697-704`) and Send (`:706-730`) | none on cancel; `latitude`/`longitude` on send | `TGConversationController.mm:7228-7242` |
| `mapViewForward` | actions sheet item 1 (`:804-813`) | `controller`, `message` | `TGConversationController.mm:7222-7227` |
| `openContact` | callout tap (`:912-920`) | `contactAttachment` (a `TGContactMediaAttachment` with `_user.uid`) | `TGConversationController.mm:7247-7252` |

Note the asymmetry that matters for a port: **the same action name is used for cancel and for send**.
The receiver distinguishes them only by whether `latitude`/`longitude` are present in `options`
(`TGConversationController.mm:7230-7241`), and it dismisses the modal in both cases before looking.

The `user:` argument may be a database miss — the call site passes
`[TGDatabaseInstance() loadUser:...]` unguarded (`TGConversationController.mm:7215`) — so `_user` can
be nil and the callout title then comes out empty (see §7).

## 3. The map view

`TGMapView` is an `MKMapView` subclass whose entire purpose is to nail the Google/Apple attribution
logo to the top-left corner instead of the bottom, where the controller's own buttons sit. On iOS 5
it does this in `layoutSubviews`, finding the first `UIImageView` subview and forcing it to
`(5, 5)` with `autoresizingMask = 0` (`TGMapView.m:9-24`). On iOS 6 the attribution became a
`UILabel`, so the controller does the same walk once in `loadView`, moving the first `UILabel`
subview to `(5, 5)` (`TGMapViewController.m:180-195`). Both are private-view-hierarchy hacks and
both are one-shot `break`s after the first match.

Map configuration (`:169-178`): zoom and scroll enabled, `showsUserLocation = true`, delegate self,
autoresizes in both axes, `mapType = defaultMapMode()`.

**Map type is persisted globally**, not per-screen: `defaultMapMode()` lazily reads
`NSUserDefaults` key `@"TGMapViewController.defaultMapMode"` into a static
(`:35-45`), and `setDefaultMapMode()` writes it back with an immediate `synchronize`
(`:47-55`). Choosing Satellite while sending a location means the next location you *view* opens in
Satellite too.

**Standard region span is 0.008° × 0.008°** — roughly 900 m north–south. This one number appears
three times and is the screen's only zoom level: initial region in pick mode from the cached last
user location (`:223-224`), initial region in map mode around the received point (`:250-251`), and
the first automatic recentre when the user's fix arrives (`:408-409`). Every `setRegion:` call is
wrapped in `@try/@catch` logging the exception (`:226-231`, `:253-260`, `:411-415`) because MapKit
throws on a non-finite region — the original clearly hit this in the field.

**Last user location is a file static**, `lastUserLocation` (`:24`), updated on every
`didUpdateUserLocation` (`:396`) and never cleared. It survives the controller, so the second time
you open the picker in a session it opens already framed on you rather than on the middle of the
ocean, with no wait for a fix.

## 4. Pick mode

Buttons (`:201-214`): a generic `TGToolbarButton` "Common.Cancel" with `minWidth = 59`, and a
`TGToolbarButtonTypeDone` labelled `Map.Send` = "Send" with `minWidth = 52`. Both are `sizeToFit`
after the width floor is set and wrapped in `UIBarButtonItem initWithCustomView:`. Done starts
`enabled = false` (`:214`).

`updateDoneButton` (`:651-657`) enables Send when
`ABS(latitude) > DBL_EPSILON || ABS(longitude) > DBL_EPSILON` — i.e. any pin that is not exactly
(0,0). Null Island is unsendable; that is the whole validity rule. It is called from
`didUpdateUserLocation` (`:445`), from the end of a pin drag (`:453-454`) and after a long press
(`:688`).

**Placing the pin.** A `UILongPressGestureRecognizer` on the map (`:216-217`) drops a pin on
`UIGestureRecognizerStateBegan` only (`:673`): it sets `_modifiedPinLocation = true`, *removes* the
existing annotation entirely, converts the touch point with
`convertPoint:toCoordinateFromView:` and adds a fresh `TGLocationAnnotation` (`:675-688`). It
removes and re-adds rather than moving the coordinate, which is what triggers the drop animation
in §6. In pick mode the annotation view is a stock `MKPinAnnotationView` with `draggable = true`
(`:533`, `:537-538`).

**Automatic follow.** Until the user has touched anything (`!_modifiedPinLocation`), each user-location
update moves the pin to the user (`:418-426`), and the very first update also animates the region to
0.008° around them, guarded by `_modifiedRegion` so it happens once (`:400-416`). Once the user
long-presses or drags, `_modifiedPinLocation` latches true and the pin never follows again.

**Send** (`:706-730`) prefers the pin's coordinate; if there is no pin, or the pin is at (0,0), it
falls back to `_mapView.userLocation.coordinate` (`:717-721`). If both are absent the options
dictionary goes out empty, which the chat reads as a cancel. (There is a vestigial empty
`if (_mapViewFinished)` block at `:723-726`; `_mapViewFinished` is set by
`mapViewWillStartLoadingMap`/`DidFinishLoadingMap` at `:659-667` and used nowhere else.)

## 5. Map mode

Right button (`:239-246`): a generic `TGToolbarButton` with image `HeaderActions.png`,
`minWidth = 37`. `self.backAction = @selector(performCloseMap)` (`:237`), which simply pops
(`:692-695`).

Annotation is created in the initialiser (`:152`), added and *selected* immediately, unanimated,
before the view is even on screen (`:262-263`).

**Actions sheet** (`:770-786`), rebuilt on every press with the previous sheet's delegate nilled first:

1. "Get Directions" — opens `http://maps.google.com/?daddr=lat,lon` on iOS 5 and
   `http://maps.apple.com/?daddr=...` on iOS 6+, appending `&saddr=` with the user's coordinate when
   there is one (`:794-803`). It prefers a private
   `openURL:forceNative:` on `UIApplication` when the host app implements it (protocol declared at
   `:29-33`), falling back to plain `openURL:`.
2. "Forward via Telegram" — fires `mapViewForward` only if `_message != nil` (`:804-813`).
3. "Open in Google Maps" — added only on iOS 6+ *and* only if `comgooglemaps://` can be opened
   (`:778-782`). URL is `comgooglemaps://?center=lat,lon` using the **map centre**, not the pin
   (`:816-818`).
4. Cancel, `TGLocalized(@"Common.Cancel")`, index captured from `addButtonWithTitle:` (`:784`).

Items 1-3 are hardcoded English strings, not localized — a genuine inconsistency in the original,
worth copying only if we are being faithful to a fault.

Because item 3's index is conditional, `clickedButtonAtIndex:` comparing against literal `0/1/2`
(`:794`, `:804`, `:814`) is correct only because Cancel is always last and is filtered first
(`:792`).

## 6. The pin drop animation (pick mode only)

`didAddAnnotationViews:` (`:473-517`) returns immediately unless pick mode, skips the user-location
view, and skips any annotation whose map point is outside `visibleMapRect` (`:483-485`) — no
animation is wasted off-screen. For each remaining view:

1. Frame is moved up by the full view height (`:489`) and animated back to its end frame over
   **0.5 s**, staggered by **0.04 s × index** (`:493-496`).
2. On completion, **0.05 s** squash to `scale(1.0, 0.8)` (`:500-503`).
3. Then `selectAnnotation:animated:true` and a **0.1 s** return to identity (`:505-511`).

Note the selection happens in the *completion of the squash*, i.e. after ~0.55 s, and unconditionally
even if the animation was interrupted (`[mapView selectAnnotation:]` is outside the
`if (finished)` at `:505-506`).

## 7. The callout (`TGCalloutView`, map mode only)

In map mode the annotation view is `TGMapAnnotationView`, an `MKPinAnnotationView` subclass whose
only job is to host a `TGCalloutView` and forward its tap (`TGMapAnnotationView.m:13-24`).
`canShowCallout = false` and `animatesDrop = false` on both modes
(`TGMapViewController.m:535-536`) — MapKit's own callout is never used.

Layout: the callout is centred on the pin **minus 9 pt** horizontally and sits directly above it,
`origin.y = -height` (`TGMapAnnotationView.m:39-42`). The −9 compensates for the pin graphic's own
off-centre point. `hitTest:` forwards to the callout in the callout's coordinate space and returns
nil otherwise (`:26-33`), so the pin body itself is not tappable — only the bubble is.

Artwork, nine-part horizontally (`TGCalloutView.m:41-59`), all `stretchableImageWithLeftCapWidth:`
with `topCapHeight:0`:

| asset | @2x pixels | points | cap |
|---|---|---|---|
| `MapCalloutLeft` | 24 × 124 | 12 × 62 | left cap `width - 1` (stretches its last column) |
| `MapCalloutCenter` | 48 × 124 | 24 × 62 | not stretched, drawn at natural width |
| `MapCalloutRight` | 24 × 124 | 12 × 62 | left cap 1 |
| `MapCalloutArrow` | 18 × 30 | 9 × 15 | not stretched |

Each has a `_Highlighted` twin used as the image view's `highlightedImage`
(`TGCalloutView.m:41-58`). Only @2x files ship in `Telegraph/Telegraph/Resources` — verified: no
1x `Map*` files exist in that directory — so callout height is **62 pt** and every number here is
retina-derived.

Text (`TGCalloutView.m:61-77`):

- title: `boldSystemFontOfSize:16`, white, shadow `#000000 @ 0.5` offset `(0, -1)`, clear background.
- subtitle: `boldSystemFontOfSize:12`, `#ffffff @ 0.7`, same shadow; `highlightedTextColor` white.
- When highlighted, both shadows switch to `#08509c @ 0.5` (`:118-127`) — the blue press state's
  own shadow, so the text stays legible on the pressed bubble.

Sizing (`TGCalloutView.m:80-93`): labels are `sizeToFit`, then
`labelsWidth = max(titleW, subtitleW) + 30 + 13`, and the frame width is
`min(300, max(max(left+right+center, labelsWidth), 194))`. So: **minimum 194 pt, maximum 300 pt**,
height always `leftView.image.size.height` = 62 pt. Long names do not wrap — the width clamps at 300
and the label frame is `width - 30 - 12` wide, so `UILabel` truncates with an ellipsis at one line.

Vertical layout depends on whether there is a subtitle (`TGCalloutView.m:142-153`), and this is the
detail most likely to be lost in a port:

- subtitle empty → title at `y = 13` (vertically centred for a 62 pt bubble), subtitle at `y = 14`
  with `alpha = 0`.
- subtitle present → title at `y = 4`, subtitle at `y = 26`, subtitle `alpha = 1`.

Both labels are always at `x = 13`. The arrow is right-aligned at `width - arrowW - 11`, `y = 16`
(`:140`).

`touchesBegan:` walks up the superview chain on iOS 6+ and disables/re-enables every
two-tap `UITapGestureRecognizer` it finds (`TGCalloutView.m:156-180`) — that is MapKit's
double-tap-to-zoom, cancelled so a tap on the callout does not also zoom the map.

**Callout content** is filled by `updateAnnotationView:` (`TGMapViewController.m:569-639`):

- title = `_user.displayName`. If `_user` is nil this is nil and the bubble shows only the distance.
- subtitle = distance from `_mapLocation` to `_mapView.userLocation.location`, or **nil if there is
  no user fix yet** (`:627-628`) — which is exactly the single-line layout above. The callout
  therefore starts single-line and grows to two lines when the fix lands.
- Units are decided once via `dispatch_once` from `NSLocaleUsesMetricSystem` (`:575-582`).
  Metric: `"%.1fK km away"` above 1 000 km, `"%.1f km away"` above 1 km, else `"%d m away"`
  (`:590-595`). Imperial: converts to feet by `/0.3048`; at or above 5 280 ft prints miles to one
  decimal with a hand-rolled pluralisation that inspects the formatted string for a non-digit
  (`:601-618`), otherwise `"%d feet away"` / `"1 foot away"` (`:621`). All of these strings are
  hardcoded English.
- After setting text it calls `sizeToFit` then `setNeedsLayout`, and **only animates (0.2 s) if the
  callout currently sits above the top of its parent** (`origin.y < 0`, `:632-638`) — which it
  always does, since layout puts it at `-height`. So in practice the resize is always animated.

## 8. The locate button

Geometry (`:268-278`): background `MapSingleButton.png` (39 × 65 px = **19.5 × 32.5 pt**), stretched
with left cap `width / 2`. Frame is `(6, viewHeight - 6 - imageHeight, 40, imageHeight)` —
so **40 pt wide, 32.5 pt tall, 6 pt from the left and 6 pt from the bottom**, pinned by
`UIViewAutoresizingFlexibleTopMargin`. Highlighted state uses `MapSingleButton_Highlighted.png`.

Three icons stacked in a non-interactive `_locationIconsContainer` filling the button (`:280-296`):

| icon | @2x px | pt | offset |
|---|---|---|---|
| `MapLocationIcon` | 37 × 39 | 18.5 × 19.5 | `(9, 7)` |
| `MapLocationIcon_Active` | 37 × 39 | 18.5 × 19.5 | `(9, 7)` |
| `MapLocationIcon_ActiveHeading` | 48 × 52 | 24 × 26 | `(10, 7)` — note `:294` offsets from
  `_locationActiveIcon.frame`, already at (9,7), by a further `(1, 0)` |

Only the normal icon starts visible; the other two are `alpha = 0`.

A `TGActivityIndicatorView` of style `TGActivityIndicatorViewStyleSmall` sits on the *button*, not
the container, centred with a **+0.5 pt retina nudge in both axes** (`retinaPixel`, `:271`, `:300`),
starting at `alpha = 0` and `scale(0.1)`.

**Tracking is a three-state cycle** (`locationButtonPressed`, `:732-761`):
None → Follow → FollowWithHeading → None, animated. It only cycles when there is an actual fix; with
no fix, pressing shows the `Map.AccessDeniedError` alert if services are denied and otherwise just
re-runs `updateLocationAvailability` (`:752-760`).

`updateLocationIcons` (`:830-882`) maps the tracking mode to three alphas and transforms; the
heading icon is scaled `0.1` when hidden and identity when shown, and the other two the reverse.
It animates over **0.2 s** with `BeginFromCurrentState` **only when the heading icon's visibility
actually flips** (`animateTransition`, `:839`); the None↔Follow switch is instant. It is called from
the button (`:739`, `:744`, `:749`), from `didChangeUserTrackingMode:` (`:646-649`) and from
`didUpdateUserLocation` (`:433`).

`updateLocationAvailability` (`:884-908`) cross-fades the icon container against the spinner over
0.2 s, each also scaling between identity and `0.1`. "Available" means a real fix **or** location
services denied — a denial stops the spinner too, rather than spinning forever. It early-returns if
the state has not changed, starts the spinner before fading in, and stops it in the completion.

**Waiting for a fix in the picker.** `didUpdateUserLocation` contains a subtle bit: if the spinner is
still visible when the first fix arrives, the map is put into `MKUserTrackingModeFollow`
(`:430-434`). So a user who opened the picker and pressed nothing gets follow mode for free; a user
who had a cached location does not.

**Denial** (`didFailToLocateUserWithError:`, `:457-471`): only acts on
`kCLAuthorizationStatusDenied`; sets `_locationServicesDisabled`, updates availability, and in
**pick mode only** shows a `UIAlertView` with no title, message `Map.AccessDeniedError`
("To make this feature work, please turn on Location Services for Telegram in your iPhone's
Privacy Settings.", `Localizable.strings:522`) and a single `Common.OK` button. Viewing a location
never nags.

## 9. The map-type button group

`TGButtonGroupView` at `(viewWidth - 219 - 6, viewHeight - imageHeight - 7, 219, imageHeight)`
(`:324`) — **219 pt wide, 6 pt from the right, 7 pt from the bottom** (one point lower than the
locate button's 6, using `MapButtonGroupLeft.png`'s height of 64 px = **32 pt**; the locate button is
32.5 pt, so the two bottom edges land at the same place: `h-6-32.5` vs `h-7-32`). Autoresizing
`FlexibleLeftMargin | FlexibleTopMargin`.

Artwork and caps (`:305-322`), all `topCapHeight:0`:

| asset | @2x px | pt | left cap |
|---|---|---|---|
| `MapButtonGroupLeft` | 22 × 64 | 11 × 32 | `width - 1` |
| `MapButtonGroupCenter` | 8 × 64 | 4 × 32 | `width / 2` |
| `MapButtonGroupRight` | 22 × 64 | 11 × 32 | `1` |
| `MapButtonGroupDivider` | 8 × 64 | 4 × 32 | not stretched |

plus `_Highlighted` variants of the three body pieces and `_LeftHighlighted` / `_RightHighlighted`
variants of the divider, so that pressing a button darkens the divider only on the adjoining side.

Styling (`:327-338`):

- `selectedIndex = MIN(2, MAX(0, mapType))` — clamped, because `MKMapType` gained values later.
- `buttonTopTextInset = 1`, `buttonSideTextInset = 3`.
- text `#595959`, highlighted text `#046dd0`, shadow `#ffffff @ 0.6` offset `(0, 1)` — an *upward*
  white emboss, correct for a light chrome button.
- font `boldSystemFontOfSize:12`.
- `buttonsAreAlwaysDeselected = true`: the group never shows a sticky selection, it only flashes on
  press.
- Buttons: `Map.Map` / `Map.Satellite` / `Map.Hybrid` = "Map" / "Satellite" / "Hybrid"
  (`Localizable.strings:519-521`).

`buttonGroupViewButtonPressed:index:` clamps the index to 0…2, persists it and applies it
(`:763-768`). Because `MKMapTypeStandard/Satellite/Hybrid` are 0/1/2, the index *is* the map type.

## 10. Rotation and lifecycle

`shouldAutorotateToInterfaceOrientation:` allows everything except upside-down, and returns false
outright while a modal is presented (`:359-373`). `willAnimateRotation...` re-sets
`centerCoordinate` to the current region centre unanimated before calling super (`:380-385`) — a
MapKit workaround so the map does not drift during the rotation animation.

`doUnloadView` (`:342-350`) nils the map delegate, the map itself, the button-group delegate and the
action sheet delegate; it is called both from `viewDidUnload` and from `dealloc` (`:157-163`),
alongside `[_actionHandle reset]` and `removeWatcher:`. Any port must nil the action-sheet delegate
on teardown — an in-flight sheet calling back into a dead controller is the classic crash here.

---

## 11. Our port

**We do not have this screen. Neither half of it.**

Grepping `iTgLegacy/src` for `MKMapView` finds a single hit, the `#import <MapKit/MapKit.h>` at
`src/TGChatViewController.m:16`; the framework is imported and never used. There is no map
controller, no annotation view, no callout, no locate button and no map-type switch anywhere in the
tree.

What exists instead:

- **Sending** is a blind action sheet, `showLocationOptions` (`src/TGChatViewController.m:5149-5164`):
  "Send My Location", "Share For 1 Hour" / "Stop Sharing", "Send a Place", Cancel. Choosing one
  starts a raw `CLLocationManager` (`:6485-6492`) and sends whatever fix arrives
  (`:6540-6559`). The user never sees a map, never places a pin, and cannot send a location other
  than the one they are standing on. The original's entire pick-mode interaction — drop pin by long
  press, drag to correct, Send disabled until valid — is absent.
- **Viewing** a location is a hand-drawn `UIImage` card, `mapCardForLatitude:longitude:`
  (`src/TGChatViewController.m:3264-3316`): 220 × 130 pt (`kMapCardW`/`kMapCardH`, `:135-136`),
  a beige field with pseudo-random roads seeded from the coordinates, a green blob, a drawn pin, and
  the coordinates in 12 pt at the bottom-left. It is later replaced by a real TDLib-rendered tile
  (`fetchMapTileFor:key:`, `:3341`). The comment at `:3260-3263` explains why: `MKMapSnapshotter`
  never calls back on this OS because Apple's tile servers no longer answer clients this old.
- **Tapping** a location bubble does nothing. `didSelectRowAtIndexPath:`
  (`src/TGChatViewController.m:6728`ff.) handles calls, polls, media, replies, documents and themes;
  there is no `lat`/`lon` branch, so the map-mode screen has no entry point at all.

### What to change, concretely

The honest constraint first: **`MKMapView` on iOS 6.1.3 is very likely dead the same way
`MKMapSnapshotter` is dead** — same Apple tile servers, same refused clients. Our existing comment
at `TGChatViewController.m:3260` is evidence someone already established this. Nothing in our tree
proves `MKMapView` itself was tested, so I will not claim it works or doesn't; that is the first
thing to establish before any of the below is worth building.

If MapKit tiles are unavailable, the faithful move is to keep the original's *chrome and
interaction* over our own tile source (the TDLib-rendered static map we already fetch), not to
abandon the screen:

1. **Add a location viewer, entered by tapping a location bubble.** Push, don't present. Title "Map",
   back action pops. Right button `HeaderActions.png`, `minWidth 37`, opening a sheet with
   "Get Directions" / "Forward via Telegram" (+ "Open in Google Maps" when `comgooglemaps://`
   resolves) / Cancel, exactly as `TGMapViewController.m:770-786`.
2. **Port `TGCalloutView` verbatim** — it is 182 lines, self-contained, and is the single most
   recognisable piece of 2013 Telegram on this screen. All nine numbers are in §7. Two-line when a
   distance is known, one line with the title at `y = 13` when it is not.
3. **Port the distance string** including its two-decimal-free metric ladder and its imperial
   branch (`:588-623`). Sender name is the callout title; tapping the callout opens that contact.
4. **Port the locate button and the map-type group** (§8, §9) even over a static tile: the type
   group at least changes which tile we request, and the locate button's three-state cycle and
   spinner cross-fade are pure UIKit.
5. **Add pick mode** with long-press-to-drop and Send disabled until the pin is non-(0,0). Even over
   a non-interactive tile, a pannable static map with a draggable pin is closer to the original than
   an action sheet with no map. Persist the chosen map type in `NSUserDefaults` under a key of our
   own; cache the last user location in a file static so the picker opens framed correctly.
6. **Keep the "Send a Place" and live-location items** we already have — those are modern features
   the 2013 controller never had (see §12) and removing them would be a regression in the
   interaction model we are deliberately keeping current.

If MapKit *does* render, all of the above applies unchanged with a real `MKMapView` under it, plus
the two attribution-relocation hacks in §3 (iOS 6 path: first `UILabel` subview to `(5, 5)`), the
`@try/@catch` around every `setRegion:`, and the 0.008° span.

## 12. What became of it

**Telegram-iOS (modern).** One controller became a family: `LocationPickerController`,
`LocationViewController`, `LocationSearchContainerNode`, `LocationDistancePickerScreen`,
`LiveLocationManager` and friends under `submodules/LocationUI/Sources`. The changes that matter:

- The **map is now a header above a list**, not the whole screen. The picker shows nearby venues
  (`LocationInfoListItem.swift`, `LocationSearchContainerNode.swift`) and the viewer shows the
  sender plus live-location participants (`LocationLiveListItem.swift`). This is the real conceptual
  shift: picking a location became *choosing a place from a searchable list*, with the map as
  confirmation, rather than *aiming a pin*. Forced by the arrival of the venue database.
- **Two spans instead of one.** `LocationMapNode.swift:203-205` defines
  `defaultMapSpan = 0.016` (picking), `viewMapSpan = 0.008` (viewing) and `globalMapSpan = 0.1`.
  The original's single 0.008 survives, but only as the *viewing* zoom; picking zooms out because
  you now need to see neighbouring venues.
- **Live location** did not exist in 2013 at all and is the largest single addition.
- The Map/Satellite/Hybrid button group is gone; map type is no longer user-visible. Taste plus
  Apple Maps improving.
- The three-state tracking cycle **survived intact**.

**twelve** (`submodules/LegacyComponents/LegacyComponents`) is the useful middle term, being the same
Objective-C lineage: `TGLocationMapViewController` (654 lines) is now an abstract base with
`TGLocationPickerController` (1 303) and `TGLocationViewController` (1 290) on top — the mode enum
became a class hierarchy, which is what should have happened in 2013. Concretely:

- `const MKCoordinateSpan TGLocationDefaultSpan = { 0.008, 0.008 }`
  (`TGLocationMapViewController.m:25`) — **our number, unchanged, promoted to a named constant.**
- `TGLocationTrackingMode` (`TGLocationTrackingButton.h:5-8`) is `None / Follow / FollowWithHeading`
  with explicit converters to and from `MKUserTrackingMode` (`:20-21`) — the three-state cycle from
  `locationButtonPressed` extracted into its own button class.
- The base class owns the table view, an activity indicator, a message label and a `TGLocationPallete`
  of thirteen colours (`TGLocationMapViewController.h:13-32`) — theming arrived, and the hardcoded
  `#595959` / `#046dd0` / `#08509c` of 2013 became palette entries.
- Callout artwork is gone; the sender is a table row.

So: the pin, the span, and the tracking cycle are the durable ideas. The callout bubble, the map-type
group and the single-controller-two-modes structure are the period pieces — and the callout bubble is
precisely the period piece we want.

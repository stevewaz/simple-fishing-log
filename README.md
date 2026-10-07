# FishLog

**Live web app: https://stevewaz.github.io/simple-fishing-log/** — redeployed automatically on every push to `main`
(`.github/workflows/pages.yml` runs the analyzer and all tests first, so a broken build never reaches the site).
Your catches are stored in *your browser* on that site, not on a server.

A simple, **local-first** fishing journal for **iOS, Android and the web** — a Flutter port of the
original SwiftUI/SwiftData app (`simpleFishLogzOLD`). Everything is stored on the device; there is
no account and no server. Firebase sync is designed for but **not yet wired in** — see
[docs/FIREBASE.md](docs/FIREBASE.md).

## What it does

| Tab | |
|---|---|
| **Home** | Current conditions, moon phase and today's solunar windows, recent catches |
| **Log** | Searchable catch list, sort by newest / nearest, swipe to delete (with Undo), import / export |
| **Map** | Opens on **your position** (blue pin) with every catch as a marker; trophy markers for personal bests; Standard / Hybrid / Satellite / **Water chart** (NOAA depth soundings, contours, buoys, hazards, ramps); date and species filters; trip trails |
| **Trips** | Group catches into sessions; one active at a time |
| **Insights** | Species mix, catches by hour, top waters, moon phase, personal bests (after 20 catches) |

Plus: add/edit form with species and gear pickers (and your own most-used gear as one-tap chips), photo with
**Measure Fish** (reference-object measuring tool + length→weight estimate), live-weather fill, locale-aware number entry
(`2,5` and `2.5` both work), `.fishlog` backup export/import.

## Run it

```sh
flutter pub get
flutter run -d chrome          # web
flutter run -d <ios-device>    # iOS
flutter run -d <android>       # Android
flutter test                   # 440 tests
```

Sample data for development and screenshots (only seeds an *empty* log; compiled out otherwise):

```sh
flutter run -d chrome --dart-define=FISHLOG_DEMO=true
```

## Architecture

Layered, feature-first. Dependencies only point downward.

```
lib/
  app/        providers (Riverpod), router (go_router), app shell
  features/   home · log · detail · edit · map · trips · insights   (screens + their widgets)
  core/       theme, shared widgets, formatting, platform shims
  data/       repositories, document store, blob store, archive, services, sync
  domain/     models, catalogs, astronomy, insights — pure Dart, no Flutter
```

**Local-first storage**

* **Documents** (catches, trips, photo metadata) — [`sembast`](https://pub.dev/packages/sembast): a file on iOS/Android,
  IndexedDB on the web. Pure Dart, no codegen, no native setup, and its JSON documents map 1:1 onto Firestore documents.
* **Photo bytes** — a separate `BlobStore` (files on native, IndexedDB on web). Sembast keeps its whole database in memory, so
  images must not live in it.
* Every record carries sync metadata beside its JSON (`_updatedAt`, `_deletedAt` tombstone, `_syncedAt`); deletes are soft, so
  Undo is free and a remote can later learn about deletions. Domain models never see any of it.

**Adding Firebase later** is an adapter, not a rewrite: implement `SyncGateway` (two methods) and override one provider.
`SyncService` (push-then-pull, last-write-wins) is already built and tested against a fake remote.

**Replacing Apple-only APIs**

| Swift | Flutter |
|---|---|
| SwiftData | sembast + `DocumentStore` / repositories |
| MapKit | `flutter_map` — OpenStreetMap tiles, Esri imagery |
| WeatherKit | Open-Meteo (free, no key) behind a `ConditionsProvider` |
| CLGeocoder / MKLocalSearch | Nominatim + Overpass (OSM), behind a `PlaceService` |
| CoreLocation | `geolocator` |
| PhotosPicker / ImageIO | `image_picker` + `package:image` |
| Swift Charts | small hand-drawn bar widgets (theme-aware, accessible) |
| `.fishlog` directory package | `.fishlog` **zip** (same JSON inside — see below) |

## Water depth

The **Water chart** map style puts NOAA's official nautical chart (ENC Online) over OpenStreetMap, plus the Canadian
Hydrographic Service's chart for Canadian waters: depth soundings and contours, depth shading (darker = shallower), buoys
and lights, channels, rocks and wrecks, marinas and ramps. It is also what the mini-map on a catch's detail screen shows, so
you can look at the bottom around a spot you fished.

* **Free, no key, works in the browser.** Tiles are requested from NOAA's Maritime Chart Server as bounding-box images
  (`NoaaChartTileProvider`); it allows cross-origin requests, so the web build works too. The Canadian layer
  (`chsEndpoint`: the Canadian Hydrographic Service's ENC Maritime Chart Service) is the same request to a different server,
  asked for only at Canadian latitudes. **Not yet confirmed against the live service** — it was added without network access
  to either server, so check the Ontario side of the Great Lakes once deployed.
* **Depths are in meters** (a subscript is tenths: 2₇ = 2.7 m ≈ 8.9 ft). The service has no feet option, so the app has a
  "Depths in meters" help sheet. NOAA's feet-based *raster* chart tiles were unreachable when I tried them.
* **US and Canadian waters only** — coastal waters, both shores of the Great Lakes and some rivers. **Small inland lakes are not charted** by anyone for
  free; there the style is just the standard map. For those you'd need a licensed source (Navionics/Garmin, Mapbox/MapTiler
  bathymetry) or per-state lake surveys. The app already stores the depth *you* record for each catch.
* Shown from zoom 10 (below that the service draws a grid of chart boundaries instead of detail). "Not for navigation."

## `.fishlog` export format

A zip containing `manifest.json`, `catches.json`, `trips.json` and `photos/<catch-id>.jpg`. The JSON keys and
`formatVersion: 1` are identical to the Swift app, so the format is interchangeable; only the container changed (directory
"packages" are an Apple concept — Android and the web have none). To import an old iOS package, zip the folder.
Import validates the manifest, version and size caps first, isolates corrupt records (one bad catch never rejects the
rest), and never uses an archive-supplied filename to build a path.

## How it was verified

* **440 automated tests** (`flutter test`), analyzer clean.
* **Numerical parity with the original Swift.** The old `SolunarCalculator`, `MoonPhase` and `SpeciesCatalog` were compiled
  unchanged with `swiftc` and their output captured over 200 date/location cases (including polar latitudes); the Dart ports
  match to within 5 ms. A mutation check confirmed the parity test fails when a constant is changed. See `tool/swift_golden/`.
* Every test in the Swift suite was ported; plus repository, sync, archive (including hostile-input), service, and
  end-to-end widget tests that drive the real app against an in-memory database.
* Run in a browser: all five tabs, add/edit/save, persistence across reload, real map tiles, the location pin.

## What changed from the Swift app — on purpose

* **Solunar windows are for your local day.** The original computed the *UTC* day, so an evening user in the Americas got
  tomorrow's windows. `SolunarCalculator.calculate(..., dayStart:)` takes a local midnight; the default is unchanged.
* **Dark-mode `currentWater` is lighter.** The original's dark value measured ~1.3 : 1 against its own surface (icons and
  chart bars were effectively invisible); it is now ~7 : 1.
* **Map opens on your position** (blue pin) and asks for permission when you open the tab. "Fit all catches" is its own button.
  The original's map filters vanished if a filter matched nothing; there is now a Clear Filters button.
* **Export is a zip** (above). **Photos are JPEG**, not HEIC (no portable encoder), and metadata (incl. GPS) is stripped.
* **Additions:** Undo after delete; unsaved-changes guard on the form; edit a trip's title/notes (the original could create
  trips but never name them); new catches default to the active trip; "Fill from current weather"; Released / Technique /
  Weather / Pressure rows on the detail screen.
* Home no longer prompts for location on launch — it shows a button; GPS is only requested on a tap (or when opening Map).

## Not done (and why)

* **The iOS home-screen widget** (Solunar). It's a native WidgetKit extension; the Flutter route is the `home_widget` package
  plus a Swift target and an Android `AppWidget`. The math is ported, so this is mostly native plumbing. Left out rather than
  half-done.
* **Opening `.fishlog` files from other apps** (the Swift app registered a document type). Needs per-platform intent/UTType
  config and a plugin; importing from inside the app works.
* **Localization.** English only, as the original. Dates and numbers follow the device locale.
* **Android adaptive icon.** Uses the legacy icon from the original artwork.
* Web fonts are fetched from Google's CDN by Flutter's default font fallback; bundle a font if the web build must work fully offline.

## Before you ship

1. **Map tiles.** `lib/core/widgets/map_widgets.dart` points at the public OpenStreetMap, Esri and NOAA servers (NOAA's is US-government data with no key; the other two forbid heavy or commercial use). Both forbid heavy or
   commercial use. Switch to a provider you have an account with (MapTiler, Stadia, Mapbox…); it is the only place to change.
2. **Weather.** Open-Meteo is free for non-commercial use only; a paid app needs their commercial plan (or another provider
   behind `ConditionsProvider`).
3. **Nominatim / Overpass.** Set a real contact in the `User-Agent` (`OsmPlaceService`) per their usage policies.
4. **Signing & identifiers.** iOS bundle id `com.wasielewski.FishLog`; Android `com.wasielewski.fishlog`. Release builds are
   still signed with the debug key on Android — add your own keystore.
5. **App display name** is `FishLog` (Info.plist / AndroidManifest / web manifest).
6. **Web:** geolocation requires HTTPS (localhost is exempt). The app asks the browser for persistent storage; data lives only
   in the browser until sync exists, so say so in the UI before relying on it.

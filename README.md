# BannerSDK (iOS)

Native Swift port of the imgcode web banner SDK (`backend/apps/api/src/embed/sdk.ts`).
It calls the **same backend embed API** — no server changes — and renders banners with
SwiftUI instead of the DOM.

- Resolve: `GET <baseURL>?site=&placement=` → `EmbedPayload`
- Track: `GET <baseURL>/track?b=&t=impression|click&v=<visitorId>` (fire-and-forget)

Both endpoints are `@AllowAnonymous()` and CORS-open on the backend, so the app needs no auth.

## Requirements

iOS 15+ / macOS 12+ (uses `AsyncImage` and `.task`).

## Install (Swift Package Manager)

```swift
.package(url: "https://github.com/your-org/imgcode-banner-ios.git", from: "0.1.0")
```

or point Xcode at this `ios-sdk/` directory directly.

## Usage

```swift
import BannerSDK
import SwiftUI

struct HomeView: View {
    // baseURL points at the embed root, e.g. https://yourhost/api/embed
    let client = BannerClient(host: "https://yourhost")!

    var body: some View {
        ScrollView {
            BannerView(site: "acme", placement: "home-hero", client: client)
        }
    }
}
```

`BannerView` resolves on appear, tracks an impression for every returned slide, renders
the template, and tracks a click + opens the CTA URL on tap. A failed resolve renders
nothing — the host UI is never disrupted.

### Templates

| Template    | Rendering |
|-------------|-----------|
| `hero`      | Single `AsyncImage`, mobile image preferred |
| `slideshow` | Paged `TabView` carousel with auto-advance (configurable) |
| `grid`      | `LazyVGrid` of `images[]`, `columns` from payload |
| `strip`     | Colored bar with `text`, parsed `bgColor`/`textColor`/`height` |

Multiple resolved banners (or the `slideshow` template) render as a carousel; a single
non-slideshow banner renders statically — matching the web SDK's logic.

### Options

```swift
BannerView(site: "acme", placement: "promo", client: client, autoAdvance: 7) // seconds; nil disables
```

### Lower-level client

```swift
let payload = try await client.resolve(site: "acme", placement: "home-hero")
client.track(bannerId: payload.slides[0].id, event: .click)
```

The per-install visitor id (`client.visitorId`) is a UUID persisted in `UserDefaults`
under `bnr_vid`, mirroring the web SDK's `localStorage` key.

## Notes / parity caveats

- **Shared slide ids**: the backend expands one `slideshow` banner's `images[]` into
  several slides that all carry the same `id`. The SDK renders by index and tracks by
  `id`, so impressions for an expanded slideshow are counted per image (same as web).
- **Mobile-first images**: phones always get `mobileImage ?? desktopImage`; there is no
  desktop/mobile media-query swap like the web CSS.
- **No WKWebView**: the embed API returns structured data + image URLs only, so banners
  render fully native.

## Runnable demo

A macOS demo target (`BannerDemo`) is included so you can see a live banner without
building an iOS app. It points at `https://api-mm.xui.com.au` by default:

```bash
cd ios-sdk
swift run BannerDemo                      # site=demo placement=home-hero
swift run BannerDemo <site> <placement>   # override
```

It opens a window that resolves and renders the banner for the given site/placement.
(The demo is macOS-only because iOS apps can't launch from the CLI — the SDK itself is
meant for iOS.)

## Develop

```bash
cd ios-sdk
swift build
swift test
```

## Publishing (canonical source vs. consumer repo)

This directory (`imgcode/ios-sdk`) is the **canonical source** — edit the SDK here.
Consumers depend on the standalone mirror repo (SwiftPM requires `Package.swift` at a
repo root, which a monorepo subdirectory can't provide):

> https://github.com/trtin/banner-sdk-ios

`publish.sh` mirrors this directory into that repo. Its `main` always reflects
`ios-sdk/` as of the last publish; consumers pin to tags.

```bash
./publish.sh          # build + test, then sync & push main
./publish.sh 0.1.1    # ...and also tag/push release 0.1.1
```

After making changes here, run `./publish.sh <version>` to cut a new release that
consuming apps can bump to.

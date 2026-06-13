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
.package(url: "https://github.com/trtin/banner-sdk-ios.git", from: "0.1.1")
```

Then add the `BannerSDK` product to your target. Or point Xcode at this `ios-sdk/`
directory directly for local development.

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
| `slideshow` | Paged `TabView` carousel with auto-advance + dots/arrows |
| `grid`      | `LazyVGrid` of `images[]`, `columns` from payload; collapses to 1 column on compact width |
| `strip`     | Colored bar with `text`, parsed `bgColor`/`textColor`/`height` |

Multiple resolved banners (or the `slideshow` template) render as a carousel; a single
non-slideshow banner renders statically — matching the web SDK's logic.

## Public API reference

Everything below is `public`. Module: `import BannerSDK`.

### `BannerView` — SwiftUI view (drop-in)

```swift
@available(iOS 15.0, macOS 12.0, *)
public struct BannerView: View {
    public init(
        site: String,            // banner `site` key
        placement: String,       // banner `placement` key
        client: BannerClient,    // shared client (holds baseURL + visitor id)
        autoAdvance: TimeInterval? = 5,  // carousel interval in seconds; nil disables
        showArrows: Bool = false,        // prev/next arrows on carousels (JS `arrows`)
        showDots: Bool = true            // slide-position dots on carousels (JS `dots`)
    )
}
```

Behavior: resolves on appear (and whenever `site`/`placement` change), tracks one
`impression` per returned slide, renders the template, and on tap tracks a `click` +
opens the CTA URL. A failed/empty resolve renders nothing — the host UI is never broken.

```swift
BannerView(site: "acme", placement: "promo",
           client: client, autoAdvance: 7, showArrows: true, showDots: true)
```

### `BannerClient` — networking + tracking

```swift
public final class BannerClient {
    // baseURL must be the embed root, e.g. https://host/api/embed
    public init(baseURL: URL, session: URLSession = .shared)
    // convenience: pass a host like "https://host"; appends "/api/embed"
    public convenience init?(host: String, session: URLSession = .shared)

    public let visitorId: String   // stable per-install UUID (UserDefaults "bnr_vid")

    public func resolve(site: String, placement: String) async throws -> EmbedPayload
    public func track(bannerId: String, event: TrackEvent)   // fire-and-forget
}

public enum TrackEvent: String { case impression, click }
public enum BannerError: Error { case invalidURL, notHTTP, httpStatus(Int) }
```

```swift
let client = BannerClient(host: "https://api-mm.xui.com.au")!
let payload = try await client.resolve(site: "acme", placement: "home-hero")
client.track(bannerId: payload.slides[0].id, event: .click)
```

### Models (`Codable`, mirror the backend `EmbedPayload`)

```swift
public struct EmbedPayload: Codable, Sendable {
    public let template: String     // "hero" | "grid" | "strip" | "slideshow"
    public let columns: Int?        // grid only
    public let slides: [EmbedSlide]
}

public struct EmbedSlide: Codable, Sendable {
    public let id: String           // NOT unique: slideshow expands to repeated ids
    public let desktopImage: String?
    public let mobileImage: String?
    public let ctaUrl: String?
    public let altText: String?
    public let images: [GridImage]? // grid
    public let text: String?        // strip
    public let bgColor: String?     // strip
    public let textColor: String?   // strip
    public let height: String?      // strip (e.g. "48px")
    public var preferredImage: String?  // mobileImage ?? desktopImage
    public var imageURL: URL?
    public var ctaURL: URL?
}

public struct GridImage: Codable, Sendable {
    public let desktop: String
    public let mobile: String?
    public let ctaUrl: String?
    public let altText: String?
    public var preferredImage: String   // mobile ?? desktop
    public var imageURL: URL?
    public var ctaURL: URL?
}

public enum BannerTemplate: String { case hero, grid, strip, slideshow }
```

## Notes / parity with the JS SDK

Covered: all four templates, single-vs-carousel logic, auto-advance + interval,
tappable dots, prev/next arrows, `arrows`/`dots` toggles, grid 1-column collapse on
narrow screens, impression/click tracking, and the persisted visitor id.

Intentional differences:

- **Shared slide ids**: the backend expands one `slideshow` banner's `images[]` into
  several slides that all carry the same `id`. The SDK renders by index and tracks by
  `id`, so impressions for an expanded slideshow are counted per image (same as web).
- **Mobile-first images**: phones always get `mobileImage ?? desktopImage`; there is no
  desktop/mobile media-query swap like the web CSS.
- **Grid collapse** uses the compact horizontal size class as the native equivalent of
  the web's 640px breakpoint.
- **No hover-pause** (touch platform); **no WKWebView** — the embed API returns
  structured data + image URLs only, so banners render fully native.

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

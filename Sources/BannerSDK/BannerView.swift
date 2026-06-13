import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// Drop-in SwiftUI banner. Resolves `site`/`placement` against the backend embed API
/// and renders the returned template natively. Equivalent of the web SDK's
/// `Banner.init({ site, placement, target })`.
///
/// ```swift
/// let client = BannerClient(host: "https://yourhost")!
/// BannerView(site: "acme", placement: "home-hero", client: client)
/// ```
@available(iOS 15.0, macOS 12.0, *)
public struct BannerView: View {
    private let site: String
    private let placement: String
    private let client: BannerClient
    /// Auto-advance interval for carousels, in seconds. `nil` disables auto-advance.
    private let autoAdvance: TimeInterval?
    /// Show prev/next arrows on carousels (JS SDK `arrows`; default off).
    private let showArrows: Bool
    /// Show the slide-position dots on carousels (JS SDK `dots`; default on).
    private let showDots: Bool
    /// Explicit content aspect ratio (width/height). When nil the SDK measures each
    /// image's natural ratio. Used to size the carousel and reserve space before load.
    private let aspectRatio: CGFloat?
    /// Crop grid cells to fill uniform tiles (vs. fit each image with no crop, default).
    private let gridCropsToFill: Bool
    /// Columns to use at compact width (phone portrait). `nil` keeps the payload's
    /// `columns` (no collapse). Default `1` mirrors the web SDK's <640px behavior.
    private let compactGridColumns: Int?

    @State private var payload: EmbedPayload?
    @State private var didTrackImpressions = false
    @State private var selection = 0
    /// Bumped on manual navigation to restart the auto-advance interval.
    @State private var resetEpoch = 0
    /// First slide's measured aspect ratio, used to self-size the carousel.
    @State private var measuredRatio: CGFloat?
    @Environment(\.openURL) private var openURL
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    /// Neutral fallback used to reserve space before an image's true ratio is known.
    private static let fallbackRatio: CGFloat = 16.0 / 9.0

    public init(
        site: String,
        placement: String,
        client: BannerClient,
        autoAdvance: TimeInterval? = 5,
        showArrows: Bool = false,
        showDots: Bool = true,
        aspectRatio: CGFloat? = nil,
        gridCropsToFill: Bool = false,
        compactGridColumns: Int? = 1
    ) {
        self.site = site
        self.placement = placement
        self.client = client
        self.autoAdvance = autoAdvance
        self.showArrows = showArrows
        self.showDots = showDots
        self.aspectRatio = aspectRatio
        self.gridCropsToFill = gridCropsToFill
        self.compactGridColumns = compactGridColumns
    }

    public var body: some View {
        content
            .task(id: "\(site)|\(placement)") { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let payload, !payload.slides.isEmpty {
            let template = BannerTemplate(rawValue: payload.template) ?? .hero
            // Single slide and not an explicit slideshow → static render (mirrors web SDK).
            if payload.slides.count == 1 && template != .slideshow {
                slideView(payload.slides[0], template: template, columns: payload.columns)
            } else {
                carousel(payload, template: template)
            }
        } else {
            // No payload yet, or resolved to zero slides → render nothing (web SDK no-ops too).
            Color.clear.frame(height: 0)
        }
    }

    // MARK: - Carousel

    @ViewBuilder
    private func carousel(_ payload: EmbedPayload, template: BannerTemplate) -> some View {
        let slides = payload.slides
        // A bare TabView has no intrinsic height inside a ScrollView and collapses, so
        // give it a definite height from the (host-supplied or measured) aspect ratio.
        let carouselRatio = aspectRatio ?? measuredRatio ?? Self.fallbackRatio
        ZStack {
            TabView(selection: $selection) {
                ForEach(slides.indices, id: \.self) { index in
                    slideView(
                        slides[index],
                        template: template,
                        columns: payload.columns,
                        onRatio: index == 0 ? { measuredRatio = $0 } : nil
                    )
                    .tag(index)
                }
            }
            // Dots are drawn manually below (tappable, toggleable) — mirror the JS SDK,
            // so the built-in page indicator is disabled.
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .aspectRatio(carouselRatio, contentMode: .fit)

            if showArrows && slides.count > 1 {
                HStack {
                    arrowButton("chevron.left") { go(to: selection - 1, count: slides.count) }
                    Spacer()
                    arrowButton("chevron.right") { go(to: selection + 1, count: slides.count) }
                }
                .padding(.horizontal, 8)
            }

            if showDots && slides.count > 1 {
                VStack {
                    Spacer()
                    dotsBar(count: slides.count)
                }
            }
        }
        // Re-keyed by resetEpoch so manual navigation restarts the full interval,
        // matching the JS SDK's resetTimer() on dot/arrow interaction.
        .task(id: resetEpoch) { await runAutoAdvance(count: slides.count) }
    }

    private func runAutoAdvance(count: Int) async {
        guard let interval = autoAdvance, interval > 0, count > 1 else { return }
        let nanos = UInt64(interval * 1_000_000_000)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { break }
            withAnimation { selection = (selection + 1) % count }
        }
    }

    /// Navigate to `index` with wraparound and restart the auto-advance interval.
    private func go(to index: Int, count: Int) {
        guard count > 0 else { return }
        withAnimation { selection = ((index % count) + count) % count }
        resetEpoch &+= 1
    }

    @ViewBuilder
    private func arrowButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dotsBar(count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == selection ? Color.black.opacity(0.7) : Color.black.opacity(0.25))
                    .frame(width: 8, height: 8)
                    .onTapGesture { go(to: i, count: count) }
            }
        }
        .padding(8)
    }

    // MARK: - Per-template rendering

    @ViewBuilder
    private func slideView(
        _ slide: EmbedSlide,
        template: BannerTemplate,
        columns: Int?,
        onRatio: ((CGFloat) -> Void)? = nil
    ) -> some View {
        switch template {
        case .grid:
            gridSlide(slide, columns: columns ?? 2)
        case .strip:
            stripSlide(slide)
        case .hero, .slideshow:
            heroSlide(slide, onRatio: onRatio)
        }
    }

    @ViewBuilder
    private func heroSlide(_ slide: EmbedSlide, onRatio: ((CGFloat) -> Void)? = nil) -> some View {
        tappable(ctaURL: slide.ctaURL, bannerId: slide.id) {
            RemoteImage(
                url: slide.imageURL,
                accessibilityLabel: slide.altText,
                placeholderRatio: aspectRatio ?? Self.fallbackRatio,
                onRatio: onRatio
            )
        }
    }

    @ViewBuilder
    private func gridSlide(_ slide: EmbedSlide, columns: Int) -> some View {
        let cells = slide.images ?? []
        let layout = Array(repeating: GridItem(.flexible(), spacing: 8), count: max(1, effectiveColumns(columns)))
        // When cropping to uniform tiles we need a fixed box ratio; otherwise fit each
        // image at its natural ratio (the cell still reserves space, so no collapse).
        let fill = gridCropsToFill ? (aspectRatio ?? 1200.0 / 762.0) : nil
        LazyVGrid(columns: layout, spacing: 8) {
            ForEach(cells.indices, id: \.self) { index in
                let cell = cells[index]
                tappable(ctaURL: cell.ctaURL, bannerId: slide.id) {
                    RemoteImage(
                        url: cell.imageURL,
                        accessibilityLabel: cell.altText,
                        fillRatio: fill,
                        placeholderRatio: aspectRatio ?? Self.fallbackRatio
                    )
                }
            }
        }
    }

    /// The web SDK collapses the grid to one column under 640px. On iOS the compact
    /// horizontal size class (phone portrait, slide-over) is the native equivalent;
    /// `compactGridColumns` lets the host override how many columns to keep.
    private func effectiveColumns(_ columns: Int) -> Int {
        #if os(iOS)
        if hSizeClass == .compact { return compactGridColumns ?? columns }
        #endif
        return columns
    }

    @ViewBuilder
    private func stripSlide(_ slide: EmbedSlide) -> some View {
        let bg = Color(hexString: slide.bgColor) ?? Color(red: 0.118, green: 0.161, blue: 0.231)
        let fg = Color(hexString: slide.textColor) ?? .white
        let height = CSSLength.points(slide.height) ?? 48
        tappable(ctaURL: slide.ctaURL, bannerId: slide.id) {
            Text(slide.text ?? "")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(fg)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(bg)
        }
    }

    // MARK: - Tap / tracking helpers

    @ViewBuilder
    private func tappable<Content: View>(
        ctaURL: URL?,
        bannerId: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let ctaURL {
            Button {
                client.track(bannerId: bannerId, event: .click)
                openURL(ctaURL)
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    // MARK: - Load

    private func load() async {
        do {
            let result = try await client.resolve(site: site, placement: placement)
            payload = result
            if !didTrackImpressions {
                didTrackImpressions = true
                for slide in result.slides {
                    client.track(bannerId: slide.id, event: .impression)
                }
            }
        } catch {
            // Resolve failed → leave payload nil so nothing renders. Host app is unaffected.
        }
    }
}

/// Remote image that reserves layout space deterministically so it never collapses
/// inside a `LazyVGrid` or `TabView`.
///
/// Unlike `AsyncImage` (iOS 15), this loads via `URLSession` so it can read the
/// decoded image's true pixel ratio and size the cell with no crop and no reflow.
/// - `fillRatio`: when set, crop-to-fill a fixed-ratio box (uniform tiles).
/// - `placeholderRatio`: ratio used to reserve space before the image loads.
/// - `onRatio`: reports the measured natural ratio once (used to self-size carousels).
@available(iOS 15.0, macOS 12.0, *)
struct RemoteImage: View {
    let url: URL?
    var accessibilityLabel: String?
    var fillRatio: CGFloat?
    var placeholderRatio: CGFloat = 16.0 / 9.0
    var onRatio: ((CGFloat) -> Void)?

    @State private var image: Image?
    @State private var naturalRatio: CGFloat?

    var body: some View {
        Group {
            if let image {
                if let fillRatio {
                    Color.clear
                        .aspectRatio(fillRatio, contentMode: .fit)
                        .overlay(image.resizable().aspectRatio(contentMode: .fill))
                        .clipped()
                        .contentShape(Rectangle())
                } else {
                    image.resizable()
                        .aspectRatio(naturalRatio ?? placeholderRatio, contentMode: .fit)
                }
            } else {
                // Loading or failed: a neutral box that reserves the cell's space so a
                // grid stays even (a 404 cell doesn't silently collapse) and a carousel
                // doesn't shrink to nothing before load.
                Rectangle()
                    .fill(Color.gray.opacity(0.12))
                    .aspectRatio(fillRatio ?? placeholderRatio, contentMode: .fit)
            }
        }
        .accessibilityLabel(accessibilityLabel ?? "")
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        guard let url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let platform = PlatformImage(data: data) else { return }
            let size = platform.size
            if size.width > 0, size.height > 0 {
                let ratio = size.width / size.height
                naturalRatio = ratio
                onRatio?(ratio)
            }
            #if canImport(UIKit)
            image = Image(uiImage: platform)
            #elseif canImport(AppKit)
            image = Image(nsImage: platform)
            #endif
        } catch {
            // Leave `image` nil → the neutral placeholder above keeps layout stable.
        }
    }
}

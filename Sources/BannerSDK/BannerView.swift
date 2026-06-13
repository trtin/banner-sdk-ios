import SwiftUI

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

    @State private var payload: EmbedPayload?
    @State private var didTrackImpressions = false
    @State private var selection = 0
    /// Bumped on manual navigation to restart the auto-advance interval.
    @State private var resetEpoch = 0
    @Environment(\.openURL) private var openURL
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    public init(
        site: String,
        placement: String,
        client: BannerClient,
        autoAdvance: TimeInterval? = 5,
        showArrows: Bool = false,
        showDots: Bool = true
    ) {
        self.site = site
        self.placement = placement
        self.client = client
        self.autoAdvance = autoAdvance
        self.showArrows = showArrows
        self.showDots = showDots
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
        ZStack {
            TabView(selection: $selection) {
                ForEach(slides.indices, id: \.self) { index in
                    slideView(slides[index], template: template, columns: payload.columns)
                        .tag(index)
                }
            }
            // Dots are drawn manually below (tappable, toggleable) — mirror the JS SDK,
            // so the built-in page indicator is disabled.
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

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
    private func slideView(_ slide: EmbedSlide, template: BannerTemplate, columns: Int?) -> some View {
        switch template {
        case .grid:
            gridSlide(slide, columns: columns ?? 2)
        case .strip:
            stripSlide(slide)
        case .hero, .slideshow:
            heroSlide(slide)
        }
    }

    @ViewBuilder
    private func heroSlide(_ slide: EmbedSlide) -> some View {
        tappable(ctaURL: slide.ctaURL, bannerId: slide.id) {
            RemoteImage(url: slide.imageURL, accessibilityLabel: slide.altText)
        }
    }

    @ViewBuilder
    private func gridSlide(_ slide: EmbedSlide, columns: Int) -> some View {
        let cells = slide.images ?? []
        let layout = Array(repeating: GridItem(.flexible(), spacing: 8), count: max(1, effectiveColumns(columns)))
        LazyVGrid(columns: layout, spacing: 8) {
            ForEach(cells.indices, id: \.self) { index in
                let cell = cells[index]
                tappable(ctaURL: cell.ctaURL, bannerId: slide.id) {
                    RemoteImage(url: cell.imageURL, accessibilityLabel: cell.altText)
                }
            }
        }
    }

    /// JS SDK collapses the grid to a single column under 640px. On iOS the compact
    /// horizontal size class (phone portrait, slide-over) is the native equivalent.
    private func effectiveColumns(_ columns: Int) -> Int {
        #if os(iOS)
        if hSizeClass == .compact { return 1 }
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

/// Async image with a neutral placeholder while loading.
@available(iOS 15.0, macOS 12.0, *)
struct RemoteImage: View {
    let url: URL?
    var accessibilityLabel: String?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                Color.clear.frame(height: 0)
            default:
                Rectangle().fill(Color.gray.opacity(0.1))
            }
        }
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}

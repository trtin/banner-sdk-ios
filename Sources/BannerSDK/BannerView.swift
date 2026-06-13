import Combine
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

    @State private var payload: EmbedPayload?
    @State private var didTrackImpressions = false
    @State private var selection = 0
    @Environment(\.openURL) private var openURL

    public init(
        site: String,
        placement: String,
        client: BannerClient,
        autoAdvance: TimeInterval? = 5
    ) {
        self.site = site
        self.placement = placement
        self.client = client
        self.autoAdvance = autoAdvance
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
        TabView(selection: $selection) {
            ForEach(slides.indices, id: \.self) { index in
                slideView(slides[index], template: template, columns: payload.columns)
                    .tag(index)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: slides.count > 1 ? .automatic : .never))
        #endif
        .onReceive(advanceTimer) { _ in
            guard slides.count > 1 else { return }
            withAnimation { selection = (selection + 1) % slides.count }
        }
    }

    private var advanceTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        // Always produce a publisher; when autoAdvance is nil use a far-future interval
        // so it effectively never fires.
        Timer.publish(every: autoAdvance ?? .greatestFiniteMagnitude, on: .main, in: .common)
            .autoconnect()
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
        let layout = Array(repeating: GridItem(.flexible(), spacing: 8), count: max(1, columns))
        LazyVGrid(columns: layout, spacing: 8) {
            ForEach(cells.indices, id: \.self) { index in
                let cell = cells[index]
                tappable(ctaURL: cell.ctaURL, bannerId: slide.id) {
                    RemoteImage(url: cell.imageURL, accessibilityLabel: cell.altText)
                }
            }
        }
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

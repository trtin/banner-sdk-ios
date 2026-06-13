import Foundation

/// Mirrors the backend `EmbedPayload` returned by `GET /api/embed?site=&placement=`.
/// See backend/apps/api/src/embed/embed.service.ts.
public struct EmbedPayload: Codable, Sendable {
    /// One of: "hero", "grid", "strip", "slideshow".
    public let template: String
    /// Only present for the "grid" template.
    public let columns: Int?
    public let slides: [EmbedSlide]

    public init(template: String, columns: Int? = nil, slides: [EmbedSlide]) {
        self.template = template
        self.columns = columns
        self.slides = slides
    }
}

/// A single resolvable slide. Field set varies by template — hero/slideshow use the
/// image fields, grid uses `images`, strip uses `text`/`bgColor`/`textColor`/`height`.
///
/// Note: for the slideshow template the backend expands one banner's `images[]` into
/// multiple slides that all carry the **same** `id`. Do not assume `id` is unique
/// across a payload — render with indices, track with `id`.
public struct EmbedSlide: Codable, Sendable {
    public let id: String

    // Hero / Slideshow
    public let desktopImage: String?
    public let mobileImage: String?
    public let ctaUrl: String?
    public let altText: String?

    // Grid
    public let images: [GridImage]?

    // Strip
    public let text: String?
    public let bgColor: String?
    public let textColor: String?
    public let height: String?

    public init(
        id: String,
        desktopImage: String? = nil,
        mobileImage: String? = nil,
        ctaUrl: String? = nil,
        altText: String? = nil,
        images: [GridImage]? = nil,
        text: String? = nil,
        bgColor: String? = nil,
        textColor: String? = nil,
        height: String? = nil
    ) {
        self.id = id
        self.desktopImage = desktopImage
        self.mobileImage = mobileImage
        self.ctaUrl = ctaUrl
        self.altText = altText
        self.images = images
        self.text = text
        self.bgColor = bgColor
        self.textColor = textColor
        self.height = height
    }

    /// Mobile-first image pick: phones get `mobileImage` when available, else `desktopImage`.
    public var preferredImage: String? { mobileImage ?? desktopImage }

    public var imageURL: URL? { preferredImage.flatMap(URL.init(string:)) }
    public var ctaURL: URL? { ctaUrl.flatMap(URL.init(string:)) }
}

/// One cell inside a "grid" template slide.
public struct GridImage: Codable, Sendable {
    public let desktop: String
    public let mobile: String?
    public let ctaUrl: String?
    public let altText: String?

    public init(desktop: String, mobile: String? = nil, ctaUrl: String? = nil, altText: String? = nil) {
        self.desktop = desktop
        self.mobile = mobile
        self.ctaUrl = ctaUrl
        self.altText = altText
    }

    public var preferredImage: String { mobile ?? desktop }
    public var imageURL: URL? { URL(string: preferredImage) }
    public var ctaURL: URL? { ctaUrl.flatMap(URL.init(string:)) }
}

/// Known template kinds. Unknown values fall back to `.hero` at render time.
public enum BannerTemplate: String, Sendable {
    case hero
    case grid
    case strip
    case slideshow
}

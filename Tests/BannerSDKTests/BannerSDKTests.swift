import XCTest
import SwiftUI
@testable import BannerSDK

final class BannerSDKTests: XCTestCase {
    func testDecodesHeroPayload() throws {
        let json = """
        {"template":"hero","slides":[
          {"id":"abc","desktopImage":"https://x/d.png","mobileImage":"https://x/m.png","ctaUrl":"https://x/go","altText":"hi"}
        ]}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(EmbedPayload.self, from: json)
        XCTAssertEqual(payload.template, "hero")
        XCTAssertEqual(payload.slides.count, 1)
        XCTAssertEqual(payload.slides[0].preferredImage, "https://x/m.png")
        XCTAssertNotNil(payload.slides[0].ctaURL)
    }

    func testDecodesGridPayload() throws {
        let json = """
        {"template":"grid","columns":3,"slides":[
          {"id":"g1","images":[{"desktop":"https://x/1.png"},{"desktop":"https://x/2.png","mobile":"https://x/2m.png"}]}
        ]}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(EmbedPayload.self, from: json)
        XCTAssertEqual(payload.columns, 3)
        XCTAssertEqual(payload.slides[0].images?.count, 2)
        XCTAssertEqual(payload.slides[0].images?[1].preferredImage, "https://x/2m.png")
    }

    func testSlideshowSharedIdsAreAllowed() throws {
        // Backend expands one slideshow doc into multiple slides sharing the same id.
        let json = """
        {"template":"slideshow","slides":[
          {"id":"same","desktopImage":"https://x/1.png"},
          {"id":"same","desktopImage":"https://x/2.png"}
        ]}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(EmbedPayload.self, from: json)
        XCTAssertEqual(payload.slides.count, 2)
        XCTAssertEqual(payload.slides[0].id, payload.slides[1].id)
    }

    func testColorParsing() {
        XCTAssertNotNil(Color(hexString: "#1e293b"))
        XCTAssertNotNil(Color(hexString: "1e293b"))
        XCTAssertNotNil(Color(hexString: "#abc"))
        XCTAssertNil(Color(hexString: "not-a-color"))
        XCTAssertNil(Color(hexString: nil))
    }

    func testCSSLengthParsing() {
        XCTAssertEqual(CSSLength.points("48px"), 48)
        XCTAssertEqual(CSSLength.points("60"), 60)
        XCTAssertNil(CSSLength.points("auto"))
        XCTAssertNil(CSSLength.points(nil))
    }
}

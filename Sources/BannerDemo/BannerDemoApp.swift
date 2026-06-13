import SwiftUI
import BannerSDK

// Runnable demo for BannerSDK against the live backend.
//
//   swift run BannerDemo                       # uses defaults below
//   swift run BannerDemo <site> <placement>    # override site/placement
//
// This is a macOS SwiftUI app target purely so it can be launched from the CLI;
// the SDK itself is platform-neutral and is meant to be consumed on iOS.

private enum Demo {
    static let host = "https://api-mm.xui.com.au"

    static var site: String { CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "demo" }
    static var placement: String { CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "home-hero" }
}

@main
struct BannerDemoApp: App {
    static let client = BannerClient(host: Demo.host)!

    var body: some Scene {
        WindowGroup("BannerSDK Demo") {
            DemoView()
                .frame(minWidth: 420, minHeight: 320)
        }
    }
}

struct DemoView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("BannerSDK Demo")
                .font(.headline)
            Text("\(Demo.host)\nsite=\(Demo.site)  placement=\(Demo.placement)")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Divider()
            ScrollView {
                BannerView(site: Demo.site, placement: Demo.placement, client: BannerDemoApp.client)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }
}

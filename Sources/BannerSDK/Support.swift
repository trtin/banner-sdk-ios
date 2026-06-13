import SwiftUI

extension Color {
    /// Parse a CSS-ish hex color (`#1e293b`, `1e293b`, `#abc`). Returns nil on garbage.
    init?(hexString: String?) {
        guard var hex = hexString?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else {
            return nil
        }
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum CSSLength {
    /// Parse a CSS length like `"48px"` into points. Falls back to nil for `%`, `auto`, etc.
    static func points(_ value: String?) -> CGFloat? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        let numeric = value.replacingOccurrences(of: "px", with: "")
        return Double(numeric).map { CGFloat($0) }
    }
}

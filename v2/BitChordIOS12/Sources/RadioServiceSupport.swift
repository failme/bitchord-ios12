import Foundation

/// The "3:45" / "1:02:03" clock strings the catalogue returns, as seconds.
enum RadioServiceSupport {
    static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total = 0.0
        for part in parts {
            total = total * 60 + part
        }
        return total > 0 ? total : nil
    }
}

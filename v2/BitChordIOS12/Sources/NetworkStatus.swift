import Foundation
import SystemConfiguration

/// The small amount of connection state the player needs.
///
/// iOS 12 has no `NWPathMonitor` equivalent that is available on every target
/// here, so this asks `SCNetworkReachability` for the WWAN flag directly. The
/// answer is only used to choose which of the two quality ceilings applies;
/// when the system cannot answer, Wi-Fi is the safer assumption because it is
/// the less expensive route.
enum NetworkStatus {
    static var isOnWiFi: Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        guard let reach = withUnsafePointer(to: &address, { pointer -> SCNetworkReachability? in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                SCNetworkReachabilityCreateWithAddress(nil, rebound)
            }
        }) else { return true }
        var flags = SCNetworkReachabilityFlags()
        guard SCNetworkReachabilityGetFlags(reach, &flags) else { return true }
        return !flags.contains(.isWWAN)
    }

    /// The bitrate the current connection setting asks JioSaavn for.
    /// `nil` means "let the catalogue serve its best rendition", which is what
    /// upstream's Lossless choice means on a source that tops out at 320 kbps.
    static var playbackKbps: Int? {
        let key = isOnWiFi ? "BitChord.Audio.WifiQuality" : "BitChord.Audio.CellularQuality"
        let fallback = "Lossless"
        switch SettingsStore.shared.string(key, fallback) {
        case "High": return 320
        case "Normal": return 160
        case "Data saver": return 96
        default: return nil
        }
    }
}

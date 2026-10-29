import Foundation
import Photos
import CoreLocation

/// Lightweight, identifiable wrapper around a `PHAsset`.
struct PhotoItem: Identifiable, Hashable {
    let asset: PHAsset

    var id: String { asset.localIdentifier }
    var isVideo: Bool { asset.mediaType == .video }
    var isLivePhoto: Bool { asset.mediaSubtypes.contains(.photoLive) }
    var isFavorite: Bool { asset.isFavorite }
    var creationDate: Date? { asset.creationDate }
    var location: CLLocation? { asset.location }
    var hasLocation: Bool { asset.location != nil }
    var duration: TimeInterval { asset.duration }

    var durationText: String {
        let total = Int(duration.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var accessibilityLabel: String {
        var parts: [String] = [isVideo ? "Video" : "Photo"]
        if let date = creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        parts.append(hasLocation ? "has location" : "no location")
        return parts.joined(separator: ", ")
    }

    static func fallbackName(for asset: PHAsset) -> String {
        let kind = asset.mediaType == .video ? "Video" : "Photo"
        if let date = asset.creationDate {
            return "\(kind) \(date.formatted(date: .numeric, time: .shortened))"
        }
        return kind
    }

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

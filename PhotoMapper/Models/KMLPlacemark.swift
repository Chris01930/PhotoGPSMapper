import Foundation
import Photos
import CoreLocation

struct KMLPlacemark: Identifiable {
    let id: String
    let name: String
    let isVideo: Bool
    let isFavorite: Bool
    let date: Date?
    let duration: TimeInterval
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    let horizontalAccuracy: Double?

    init(asset: PHAsset, location: CLLocation, name: String) {
        id = asset.localIdentifier
        self.name = name
        isVideo = asset.mediaType == .video
        isFavorite = asset.isFavorite
        date = asset.creationDate
        duration = asset.duration
        coordinate = location.coordinate
        altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
        horizontalAccuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
    }
}

import Foundation
import Photos

/// Original file names are only reachable through `PHAssetResource`, which is comparatively
/// slow, so they are looked up lazily and cached for the life of the process.
final class FilenameCache: @unchecked Sendable {
    static let shared = FilenameCache()

    private let lock = NSLock()
    private var cache: [String: String] = [:]

    func cached(for id: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[id]
    }

    func filename(for asset: PHAsset) -> String {
        let id = asset.localIdentifier
        if let hit = cached(for: id) { return hit }

        let resources = PHAssetResource.assetResources(for: asset)
        let primaryTypes: Set<PHAssetResourceType> = [.photo, .video, .audio]
        let primary = resources.first { primaryTypes.contains($0.type) } ?? resources.first
        let name = primary?.originalFilename ?? PhotoItem.fallbackName(for: asset)

        lock.lock(); cache[id] = name; lock.unlock()
        return name
    }
}

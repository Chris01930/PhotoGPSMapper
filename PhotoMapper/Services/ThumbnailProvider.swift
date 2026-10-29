import Foundation
import Photos

/// Wraps a shared `PHCachingImageManager` for grid thumbnails.
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private let manager: PHCachingImageManager = {
        let m = PHCachingImageManager()
        m.allowsCachingHighQualityImages = false
        return m
    }()

    @discardableResult
    func request(_ asset: PHAsset, pixelSize: CGFloat,
                 completion: @escaping (PlatformImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let target = CGSize(width: pixelSize, height: pixelSize)
        return manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { image, info in
            if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled { return }
            if Thread.isMainThread {
                completion(image)
            } else {
                DispatchQueue.main.async { completion(image) }
            }
        }
    }

    func cancel(_ id: PHImageRequestID) {
        manager.cancelImageRequest(id)
    }
}

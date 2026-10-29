import Foundation
import Photos

/// Thread-safe flag used to abandon an in-flight query when a newer one supersedes it.
final class QueryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

enum LibraryQuery {
    enum GPSRequirement: String, CaseIterable, Identifiable, Equatable {
        case any = "Any"
        case required = "Required"
        case missing = "Missing"

        var id: String { rawValue }
    }

    struct GeographicFilter: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        let radiusMeters: Double
    }

    struct Request {
        let collection: PHAssetCollection?
        let filter: AssetFilter
        let searchText: String
        let restrictToIDs: Set<String>?
        var gpsRequirement: GPSRequirement = .any
        var geographicFilter: GeographicFilter? = nil
    }

    struct Result {
        let items: [PhotoItem]
        let withLocationCount: Int
        static let empty = Result(items: [], withLocationCount: 0)
    }

    /// Runs on a background thread. PhotoKit does the heavy lifting via predicates; location,
    /// selection and text search are applied while enumerating.
    static func run(_ request: Request, cancellation: QueryCancellation) -> Result {
        let options = PHFetchOptions()
        options.predicate = request.filter.predicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: !request.filter.newestFirst)]
        options.includeHiddenAssets = false

        let fetch: PHFetchResult<PHAsset>
        if let collection = request.collection {
            fetch = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            fetch = PHAsset.fetchAssets(with: options)
        }

        let matcher = SearchMatcher(text: request.searchText)
        var items: [PhotoItem] = []
        items.reserveCapacity(fetch.count)
        var withLocation = 0

        fetch.enumerateObjects { asset, index, stop in
            if index & 127 == 0, cancellation.isCancelled {
                stop.pointee = true
                return
            }
            if let ids = request.restrictToIDs, !ids.contains(asset.localIdentifier) { return }
            let hasLocation = asset.location != nil
            if request.filter.locationOnly && !hasLocation { return }
            switch request.gpsRequirement {
            case .any:
                break
            case .required where !hasLocation:
                return
            case .missing where hasLocation:
                return
            default:
                break
            }
            if let geographicFilter = request.geographicFilter {
                guard let location = asset.location else { return }
                let center = CLLocation(latitude: geographicFilter.latitude,
                                        longitude: geographicFilter.longitude)
                guard location.distance(from: center) <= geographicFilter.radiusMeters else { return }
            }
            if let matcher, !matcher.matches(asset) { return }
            if hasLocation { withLocation += 1 }
            items.append(PhotoItem(asset: asset))
        }

        if cancellation.isCancelled { return .empty }
        return Result(items: items, withLocationCount: withLocation)
    }
}

/// Matches an asset against free text: album titles it belongs to, its creation date
/// (month names, weekday, year), and its original file name.
struct SearchMatcher {
    let text: String
    private let albumMemberIDs: Set<String>
    private let dateFormatter: DateFormatter

    init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.text = trimmed

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        dateFormatter = formatter

        var ids = Set<String>()
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        for result in [userAlbums, smartAlbums] {
            result.enumerateObjects { collection, _, _ in
                guard collection.assetCollectionSubtype != .smartAlbumAllHidden,
                      let title = collection.localizedTitle,
                      title.localizedCaseInsensitiveContains(trimmed) else { return }
                PHAsset.fetchAssets(in: collection, options: nil).enumerateObjects { asset, _, _ in
                    ids.insert(asset.localIdentifier)
                }
            }
        }
        albumMemberIDs = ids
    }

    func matches(_ asset: PHAsset) -> Bool {
        if albumMemberIDs.contains(asset.localIdentifier) { return true }
        if let date = asset.creationDate,
           dateFormatter.string(from: date).localizedCaseInsensitiveContains(text) {
            return true
        }
        return FilenameCache.shared.filename(for: asset).localizedCaseInsensitiveContains(text)
    }
}

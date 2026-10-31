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
/// (month names, weekday, year, or numeric like 10/18/2026), and its original file name.
struct SearchMatcher {
    let text: String
    private let albumMemberIDs: Set<String>
    private let dateTokens: [String]
    private let dateFormatters: [DateFormatter]

    init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.text = trimmed

        // Each word must appear somewhere in the date text, so "July 2024" matches
        // "Thursday, July 18, 2024". Commas are dropped so "October 18, 2026" works too.
        dateTokens = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        dateFormatters = Self.dateFormatters(numeric: trimmed.contains(where: \.isNumber))

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
        if let date = asset.creationDate, matchesDate(date) { return true }
        return FilenameCache.shared.filename(for: asset).localizedCaseInsensitiveContains(text)
    }

    func matchesDate(_ date: Date) -> Bool {
        let dateText = dateFormatters.map { $0.string(from: date) }.joined(separator: " ")
        return dateTokens.allSatisfy { dateText.localizedCaseInsensitiveContains($0) }
    }

    /// Long form ("Sunday, October 18, 2026") plus, when the query has digits, numeric forms in
    /// the user's locale order with and without zero padding (10/18/2026, 10/18/26) and ISO.
    private static func dateFormatters(numeric: Bool) -> [DateFormatter] {
        var formatters = [DateFormatter(format: "EEEE, MMMM d, yyyy")]
        if numeric {
            formatters += ["Mdyyyy", "MMddyyyy", "Mdyy"].map { DateFormatter(template: $0) }
            formatters.append(DateFormatter(format: "yyyy-MM-dd", locale: Locale(identifier: "en_US_POSIX")))
        }
        return formatters
    }
}

private extension DateFormatter {
    convenience init(format: String, locale: Locale = .current) {
        self.init()
        self.locale = locale
        dateFormat = format
    }

    convenience init(template: String) {
        self.init()
        setLocalizedDateFormatFromTemplate(template)
    }
}

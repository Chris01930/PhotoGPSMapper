import Foundation
import Photos

struct AssetFilter: Equatable {
    enum MediaKind: String, CaseIterable, Identifiable {
        case all = "All", photos = "Photos", videos = "Videos"
        var id: String { rawValue }
    }

    var mediaKind: MediaKind = .all
    var favoritesOnly = false
    var locationOnly = false
    var showSelectedOnly = false
    var useDateRange = false
    var startDate: Date = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    var endDate: Date = Date()
    var newestFirst = true

    /// Number of non-default filter settings, shown as a badge on the Filters button.
    var activeCount: Int {
        var n = 0
        if mediaKind != .all { n += 1 }
        if favoritesOnly { n += 1 }
        if locationOnly { n += 1 }
        if showSelectedOnly { n += 1 }
        if useDateRange { n += 1 }
        return n
    }

    /// Everything PhotoKit can evaluate itself. Location is not a supported predicate key,
    /// so it (and search text) is applied in memory afterwards.
    var predicate: NSPredicate? {
        var predicates: [NSPredicate] = []
        switch mediaKind {
        case .all:
            predicates.append(NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                          PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue))
        case .photos:
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
        case .videos:
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
        }
        if favoritesOnly {
            predicates.append(NSPredicate(format: "isFavorite == YES"))
        }
        if useDateRange {
            let cal = Calendar.current
            let start = cal.startOfDay(for: min(startDate, endDate))
            let endDay = cal.startOfDay(for: max(startDate, endDate))
            let end = cal.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            predicates.append(NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}

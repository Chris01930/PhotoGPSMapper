import Foundation
import Photos
#if os(iOS)
import PhotosUI
#endif
import Observation
import SwiftUI

@MainActor
@Observable
final class LibraryModel: NSObject {

    // MARK: Authorization
    var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var hasAccess: Bool { authorizationStatus == .authorized || authorizationStatus == .limited }

    // MARK: Albums
    private(set) var albums: [AlbumItem] = []
    var selectedAlbumID: String? = AlbumItem.allPhotosID {
        didSet { if selectedAlbumID != oldValue { scheduleReload() } }
    }
    var currentAlbum: AlbumItem? { albums.first { $0.id == selectedAlbumID } }
    var currentAlbumTitle: String { currentAlbum?.title ?? "All Photos" }

    // MARK: Query
    var filter = AssetFilter() {
        didSet { if filter != oldValue { scheduleReload() } }
    }
    var searchText = "" {
        didSet { if searchText != oldValue { scheduleReload(debounce: 0.35) } }
    }
    private(set) var items: [PhotoItem] = []
    private(set) var itemsWithLocationCount = 0
    private(set) var isLoading = false

    // MARK: Selection
    private(set) var selected: [String: PHAsset] = [:]
    private(set) var selectedWithLocationCount = 0
    var selectedCount: Int { selected.count }

    // MARK: UI state
    var thumbnailSize: Double = 132
    var isExportPresented = false

    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var activeQuery: QueryCancellation?
    @ObservationIgnored private var isObserving = false

    // MARK: - Lifecycle

    func start() async {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if hasAccess {
            await activate()
        } else if authorizationStatus == .notDetermined,
                  CommandLine.arguments.contains("--auto-request-photos") {
            // Skips the explainer screen; handy for automated/simulator runs.
            await requestAccess()
        }
    }

    func requestAccess() async {
        authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if hasAccess { await activate() }
    }

    private func activate() async {
        if !isObserving {
            PHPhotoLibrary.shared().register(self)
            isObserving = true
        }
        await loadAlbums()
        scheduleReload()

        if CommandLine.arguments.contains("--open-export") {
            // Debug/automation hook: select everything visible and open the export sheet.
            await reloadTask?.value
            selectAllVisible()
            isExportPresented = true
        }
    }

    func loadAlbums() async {
        let list = await Task.detached(priority: .userInitiated) { AlbumLoader.loadAll() }.value
        albums = list
        if let id = selectedAlbumID, !list.contains(where: { $0.id == id }) {
            selectedAlbumID = AlbumItem.allPhotosID
        }
    }

    // MARK: - Querying

    func scheduleReload(debounce: Double = 0) {
        guard hasAccess else { return }
        reloadTask?.cancel()
        activeQuery?.cancel()

        let cancellation = QueryCancellation()
        activeQuery = cancellation
        let request = LibraryQuery.Request(
            collection: currentAlbum?.collection,
            filter: filter,
            searchText: searchText,
            restrictToIDs: filter.showSelectedOnly ? Set(selected.keys) : nil)

        reloadTask = Task { [weak self] in
            if debounce > 0 {
                try? await Task.sleep(for: .seconds(debounce))
                if Task.isCancelled { return }
            }
            self?.isLoading = true
            let result = await Task.detached(priority: .userInitiated) {
                LibraryQuery.run(request, cancellation: cancellation)
            }.value
            guard let self, !Task.isCancelled, !cancellation.isCancelled else { return }
            self.items = result.items
            self.itemsWithLocationCount = result.withLocationCount
            self.isLoading = false
        }
    }

    func resetFilters() {
        filter = AssetFilter()
    }

    // MARK: - Selection

    func isSelected(_ id: String) -> Bool { selected[id] != nil }

    func toggle(_ item: PhotoItem) {
        if selected[item.id] != nil {
            selected.removeValue(forKey: item.id)
            if item.hasLocation { selectedWithLocationCount -= 1 }
            if filter.showSelectedOnly { scheduleReload() }
        } else {
            selected[item.id] = item.asset
            if item.hasLocation { selectedWithLocationCount += 1 }
        }
    }

    func selectAllVisible() {
        for item in items { selected[item.id] = item.asset }
        recountSelection()
    }

    func selectVisibleWithLocation() {
        for item in items where item.hasLocation { selected[item.id] = item.asset }
        recountSelection()
    }

    func deselectVisible() {
        for item in items { selected.removeValue(forKey: item.id) }
        recountSelection()
        if filter.showSelectedOnly { scheduleReload() }
    }

    func deselectAll() {
        selected = [:]
        selectedWithLocationCount = 0
        if filter.showSelectedOnly { scheduleReload() }
    }

    private func recountSelection() {
        selectedWithLocationCount = selected.values.reduce(0) { $0 + ($1.location != nil ? 1 : 0) }
    }

    // MARK: - Export

    struct ExportPreparation {
        let placemarks: [KMLPlacemark]
        let skippedWithoutLocation: Int
        let matchingCount: Int
    }

    /// Fetches every asset matching the wizard criteria, then resolves names for located assets.
    func prepareExport(filter: AssetFilter, albumID: String, searchText: String,
                       gpsRequirement: LibraryQuery.GPSRequirement,
                       geographicFilter: LibraryQuery.GeographicFilter?) async -> ExportPreparation {
        let collection = albums.first(where: { $0.id == albumID })?.collection
        let request = LibraryQuery.Request(
            collection: collection,
            filter: filter,
            searchText: searchText,
            restrictToIDs: filter.showSelectedOnly ? Set(selected.keys) : nil,
            gpsRequirement: gpsRequirement,
            geographicFilter: geographicFilter)
        return await Task.detached(priority: .userInitiated) {
            let result = LibraryQuery.run(request, cancellation: QueryCancellation())
            var marks: [KMLPlacemark] = []
            var skipped = 0
            for item in result.items {
                let asset = item.asset
                guard let location = asset.location else { skipped += 1; continue }
                marks.append(KMLPlacemark(asset: asset, location: location,
                                          name: FilenameCache.shared.filename(for: asset)))
            }
            marks.sort { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            return ExportPreparation(placemarks: marks, skippedWithoutLocation: skipped,
                                     matchingCount: result.items.count)
        }.value
    }

    // MARK: - Limited library (iOS)

    #if os(iOS)
    func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
    #endif
}

extension LibraryModel: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            await self.loadAlbums()
            self.scheduleReload()
        }
    }
}

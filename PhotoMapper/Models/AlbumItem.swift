import Foundation
import Photos

struct AlbumItem: Identifiable, Hashable {
    enum Kind { case allPhotos, smart, user }

    static let allPhotosID = "all-photos"

    let id: String
    let title: String
    let kind: Kind
    let systemImage: String
    let collection: PHAssetCollection?
    let count: Int?

    static let allPhotos = AlbumItem(
        id: allPhotosID, title: "All Photos", kind: .allPhotos,
        systemImage: "photo.on.rectangle.angled", collection: nil, count: nil)

    static func == (lhs: AlbumItem, rhs: AlbumItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum AlbumLoader {
    private static let smartAlbums: [(PHAssetCollectionSubtype, String)] = [
        (.smartAlbumFavorites, "heart"),
        (.smartAlbumVideos, "video"),
        (.smartAlbumLivePhotos, "livephoto"),
        (.smartAlbumSelfPortraits, "person.crop.square"),
        (.smartAlbumPanoramas, "pano"),
        (.smartAlbumTimelapses, "timelapse"),
        (.smartAlbumSlomoVideos, "slowmo"),
        (.smartAlbumBursts, "square.stack.3d.down.right"),
        (.smartAlbumScreenshots, "camera.viewfinder"),
        (.smartAlbumDepthEffect, "person.and.background.dotted"),
        (.smartAlbumCinematic, "film"),
        (.smartAlbumRAW, "r.square"),
    ]

    /// Builds the sidebar list: All Photos, non-empty smart albums, then user albums.
    static func loadAll() -> [AlbumItem] {
        var items: [AlbumItem] = []

        let allCount = PHAsset.fetchAssets(with: nil).count
        items.append(AlbumItem(id: AlbumItem.allPhotosID, title: "All Photos", kind: .allPhotos,
                               systemImage: "photo.on.rectangle.angled", collection: nil, count: allCount))

        for (subtype, icon) in smartAlbums {
            let result = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            result.enumerateObjects { collection, _, _ in
                let count = PHAsset.fetchAssets(in: collection, options: nil).count
                guard count > 0 else { return }
                items.append(AlbumItem(id: collection.localIdentifier,
                                       title: collection.localizedTitle ?? "Album",
                                       kind: .smart, systemImage: icon,
                                       collection: collection, count: count))
            }
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            let icon = collection.assetCollectionSubtype == .albumCloudShared ? "rectangle.stack.badge.person.crop" : "rectangle.stack"
            items.append(AlbumItem(id: collection.localIdentifier,
                                   title: collection.localizedTitle ?? "Untitled Album",
                                   kind: .user, systemImage: icon,
                                   collection: collection, count: count))
        }
        return items
    }
}

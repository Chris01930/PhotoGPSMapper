import SwiftUI
import Photos

struct AssetGridView: View {
    @Environment(LibraryModel.self) private var library

    private var cellSize: CGFloat { CGFloat(library.thumbnailSize) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize, maximum: cellSize * 1.5), spacing: 3)],
                      spacing: 3) {
                ForEach(library.items) { item in
                    AssetCell(item: item,
                              isSelected: library.isSelected(item.id),
                              size: cellSize) {
                        library.toggle(item)
                    }
                    .contextMenu {
                        Button(library.isSelected(item.id) ? "Deselect" : "Select") { library.toggle(item) }
                        if item.hasLocation, let loc = item.location {
                            Button("Copy Coordinates") {
                                Pasteboard.copy(String(format: "%.6f, %.6f", loc.coordinate.latitude, loc.coordinate.longitude))
                            }
                        }
                    }
                }
            }
            .padding(3)
        }
        .overlay {
            if library.items.isEmpty {
                if library.isLoading {
                    ProgressView("Loading…")
                } else if !library.searchText.isEmpty {
                    ContentUnavailableView.search(text: library.searchText)
                } else {
                    ContentUnavailableView("No Items",
                                           systemImage: "photo.on.rectangle.angled",
                                           description: Text("Nothing in this album matches the current filters."))
                }
            }
        }
    }
}

struct AssetCell: View {
    let item: PhotoItem
    let isSelected: Bool
    let size: CGFloat
    let onTap: () -> Void

    @State private var image: PlatformImage?
    @State private var requestID: PHImageRequestID?
    @State private var loadedPixelSize: CGFloat = 0

    /// Requests are made in 128px buckets so dragging the size slider doesn't refetch every step.
    private var pixelSize: CGFloat {
        max(128, (size * 2 / 128).rounded(.up) * 128)
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) { bottomBadges }
            .overlay(alignment: .topTrailing) { selectionBadge }
            .overlay {
                if isSelected {
                    Rectangle().stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .opacity(isSelected ? 0.85 : 1)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .onAppear(perform: load)
            .onDisappear(perform: cancel)
            .onChange(of: pixelSize) { _, _ in load() }
    }

    private var bottomBadges: some View {
        HStack(spacing: 4) {
            Image(systemName: item.hasLocation ? "mappin.circle.fill" : "mappin.slash.circle.fill")
                .foregroundStyle(item.hasLocation ? Color.green : Color.white.opacity(0.7))
            if item.isVideo {
                Label(item.durationText, systemImage: "video.fill")
                    .labelStyle(.titleAndIcon)
            } else if item.isLivePhoto {
                Image(systemName: "livephoto")
            }
            if item.isFavorite {
                Image(systemName: "heart.fill")
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(4)
    }

    private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .font(.title3)
            .shadow(radius: 2)
            .padding(5)
            .opacity(isSelected ? 1 : 0.7)
    }

    private func load() {
        guard loadedPixelSize != pixelSize else { return }
        cancel()
        let target = pixelSize
        requestID = ThumbnailProvider.shared.request(item.asset, pixelSize: target) { result, isDegraded in
            guard let result else { return }
            image = result
            // Only the final image counts; otherwise a request cancelled after the placeholder
            // arrived would leave the cell blurry for good.
            if !isDegraded { loadedPixelSize = target }
        }
    }

    private func cancel() {
        if let requestID {
            ThumbnailProvider.shared.cancel(requestID)
            self.requestID = nil
        }
    }
}

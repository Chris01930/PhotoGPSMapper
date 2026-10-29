import SwiftUI

struct SidebarView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        @Bindable var library = library
        List(selection: $library.selectedAlbumID) {
            Section("Library") {
                ForEach(library.albums.filter { $0.kind != .user }) { album in
                    row(album)
                }
            }
            let userAlbums = library.albums.filter { $0.kind == .user }
            if !userAlbums.isEmpty {
                Section("Albums") {
                    ForEach(userAlbums) { album in
                        row(album)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("PhotoMapper")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        #endif
        .overlay {
            if library.albums.isEmpty {
                ProgressView("Loading albums…")
            }
        }
    }

    private func row(_ album: AlbumItem) -> some View {
        Label(album.title, systemImage: album.systemImage)
            .badge(album.count ?? 0)
            .tag(album.id)
    }
}

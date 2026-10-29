import SwiftUI

struct ContentView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Group {
            if library.hasAccess {
                mainView
            } else {
                AuthorizationView()
            }
        }
        .task { await library.start() }
    }

    @ViewBuilder
    private var mainView: some View {
        @Bindable var library = library
        NavigationSplitView {
            SidebarView()
        } detail: {
            AssetGridView()
                .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
                .navigationTitle(library.currentAlbumTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { DetailToolbar() }
                .searchable(text: $library.searchText, prompt: "File names, albums, dates")
        }
        .sheet(isPresented: $library.isExportPresented) {
            ExportSheet()
                .environment(library)
        }
    }
}

/// Filters popover, selection menu and the export button.
struct DetailToolbar: ToolbarContent {
    @Environment(LibraryModel.self) private var library
    @State private var isFilterPresented = false

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                isFilterPresented.toggle()
            } label: {
                Label("Filters", systemImage: library.filter.activeCount > 0
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
            .help("Filter by media type, favorites, location and date")
            .popover(isPresented: $isFilterPresented) {
                FilterView()
                    .environment(library)
            }

            Menu {
                Button("Select All Visible", systemImage: "checkmark.circle") { library.selectAllVisible() }
                Button("Select Visible With Location", systemImage: "mappin.circle") { library.selectVisibleWithLocation() }
                Divider()
                Button("Deselect Visible", systemImage: "circle") { library.deselectVisible() }
                Button("Deselect All", systemImage: "xmark.circle") { library.deselectAll() }
                    .disabled(library.selectedCount == 0)
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
            .help("Selection")

            Button {
                library.isExportPresented = true
            } label: {
                Label("Export KML", systemImage: "square.and.arrow.up")
            }
            .help("Find photos by album, filters, date, and location, then export them as KML")
        }
    }
}

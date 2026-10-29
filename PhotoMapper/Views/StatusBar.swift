import SwiftUI

struct StatusBar: View {
    @Environment(LibraryModel.self) private var library
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        @Bindable var library = library
        HStack(spacing: 12) {
            if library.isLoading {
                ProgressView().controlSize(.small)
            }
            if isCompact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(itemsText).lineLimit(1)
                    Text(selectionText)
                        .lineLimit(1)
                        .foregroundStyle(library.selectedCount > 0 ? .primary : .secondary)
                }
                .font(.caption)
            } else {
                Text(itemsText).lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
                Text(selectionText)
                    .lineLimit(1)
                    .foregroundStyle(library.selectedCount > 0 ? .primary : .secondary)
            }

            #if os(iOS)
            if library.authorizationStatus == .limited {
                Button("Manage…") { library.presentLimitedLibraryPicker() }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            #endif

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3").imageScale(.small)
                Slider(value: $library.thumbnailSize, in: 72...320)
                    .frame(width: isCompact ? 90 : 110)
                Image(systemName: "square").imageScale(.medium)
            }
            .foregroundStyle(.secondary)
            .help("Thumbnail size")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var itemsText: String {
        let n = library.items.count
        let loc = library.itemsWithLocationCount
        return "\(n.formatted()) item\(n == 1 ? "" : "s") · \(loc.formatted()) with location"
    }

    private var selectionText: String {
        let n = library.selectedCount
        if n == 0 { return "Nothing selected" }
        return "\(n.formatted()) selected · \(library.selectedWithLocationCount.formatted()) with location"
    }
}

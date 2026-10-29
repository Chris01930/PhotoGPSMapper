import SwiftUI

@main
struct PhotoMapperApp: App {
    @State private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                #if os(macOS)
                .frame(minWidth: 860, minHeight: 540)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 740)
        #endif
        .commands {
            CommandMenu("Selection") {
                Button("Select All Visible") { library.selectAllVisible() }
                    .keyboardShortcut("a", modifiers: [.command])
                Button("Select Visible Items With Location") { library.selectVisibleWithLocation() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Deselect All") { library.deselectAll() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Export KML…") { library.isExportPresented = true }
                    .keyboardShortcut("e", modifiers: [.command])
            }
        }
    }
}

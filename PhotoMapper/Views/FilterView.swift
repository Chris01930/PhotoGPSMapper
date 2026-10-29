import SwiftUI

struct FilterView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        form
            .formStyle(.grouped)
            .frame(width: 360, height: 430)
        #else
        NavigationStack {
            form
                .navigationTitle("Filters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        #endif
    }

    private var form: some View {
        @Bindable var library = library
        return Form {
            Section("Media") {
                Picker("Type", selection: $library.filter.mediaKind) {
                    ForEach(AssetFilter.MediaKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Favorites only", isOn: $library.filter.favoritesOnly)
                Toggle("Only items with a location", isOn: $library.filter.locationOnly)
                Toggle("Only selected items", isOn: $library.filter.showSelectedOnly)
            }
            Section("Date") {
                Toggle("Limit to date range", isOn: $library.filter.useDateRange)
                if library.filter.useDateRange {
                    DatePicker("From", selection: $library.filter.startDate, displayedComponents: .date)
                    DatePicker("To", selection: $library.filter.endDate, displayedComponents: .date)
                }
                Picker("Sort", selection: $library.filter.newestFirst) {
                    Text("Newest first").tag(true)
                    Text("Oldest first").tag(false)
                }
            }
            Section {
                Button("Reset Filters", role: .destructive) { library.resetFilters() }
                    .disabled(library.filter == AssetFilter())
            }
        }
    }
}

import SwiftUI
import MapKit
import UniformTypeIdentifiers

private struct ResolvedExportLocation: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
}

private struct ExportCriteria: Equatable {
    let filter: AssetFilter
    let albumID: String
    let searchText: String
    let gpsRequirement: LibraryQuery.GPSRequirement
    let geographicFilter: LibraryQuery.GeographicFilter?
}

struct ExportSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var title = KMLBuilder.defaultTitle()
    @State private var exportFilter = AssetFilter()
    @State private var albumID = AlbumItem.allPhotosID
    @State private var searchText = ""
    @State private var gpsRequirement = LibraryQuery.GPSRequirement.any
    @State private var locationQuery = ""
    @State private var resolvedLocation: ResolvedExportLocation?
    @State private var radiusMeters = 10_000.0
    @State private var includeRoute = false
    @State private var includeDescriptions = true
    @State private var placemarks: [KMLPlacemark] = []
    @State private var matchingCount = 0
    @State private var skipped = 0
    @State private var isPreparing = false
    @State private var isFindingLocation = false
    @State private var preparedCriteria: ExportCriteria?
    @State private var isExporterPresented = false
    @State private var statusMessage: String?

    private static let mapMarkerLimit = 300

    private var geographicFilter: LibraryQuery.GeographicFilter? {
        guard let resolvedLocation else { return nil }
        return LibraryQuery.GeographicFilter(latitude: resolvedLocation.latitude,
                                             longitude: resolvedLocation.longitude,
                                             radiusMeters: radiusMeters)
    }

    private var criteria: ExportCriteria {
        ExportCriteria(filter: exportFilter, albumID: albumID,
                       searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                       gpsRequirement: gpsRequirement, geographicFilter: geographicFilter)
    }

    private var hasCurrentResults: Bool { preparedCriteria == criteria }
    private var kmlText: String {
        KMLBuilder.build(title: title, placemarks: placemarks,
                         includeRoute: includeRoute, includeDescriptions: includeDescriptions)
    }
    private var fileName: String { KMLBuilder.fileName(for: title) }
    private var canExport: Bool { hasCurrentResults && !isPreparing && !placemarks.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                criteriaSection

                if preparedCriteria != nil {
                    resultsSection
                    documentSection
                    importSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export KML")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        }
        #if os(macOS)
        .frame(width: 560, height: 760)
        #endif
        .fileExporter(isPresented: $isExporterPresented,
                      document: KMLDocument(text: kmlText),
                      contentType: .kml,
                      defaultFilename: fileName) { result in
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                statusMessage = error.localizedDescription
            }
        }
    }

    private var criteriaSection: some View {
        Section("1. Choose what to export") {
            Picker("Album", selection: $albumID) {
                ForEach(library.albums) { album in
                    Text(album.title).tag(album.id)
                }
            }

            Picker("Media type", selection: $exportFilter.mediaKind) {
                ForEach(AssetFilter.MediaKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Favorites only", isOn: $exportFilter.favoritesOnly)
            Toggle("Only currently selected items", isOn: $exportFilter.showSelectedOnly)

            Toggle("Limit by date range", isOn: $exportFilter.useDateRange)
            if exportFilter.useDateRange {
                DatePicker("From", selection: $exportFilter.startDate, displayedComponents: .date)
                DatePicker("To", selection: $exportFilter.endDate, displayedComponents: .date)
            }

            TextField("Match file name, album, or date", text: $searchText)

            Picker("GPS data", selection: $gpsRequirement) {
                ForEach(LibraryQuery.GPSRequirement.allCases) { requirement in
                    Text(requirement.rawValue).tag(requirement)
                }
            }

            locationControls

            Button {
                Task { await runExportQuery() }
            } label: {
                if isPreparing {
                    ProgressView("Finding matching photos…")
                        .frame(maxWidth: .infinity)
                } else {
                    Label(hasCurrentResults ? "Refresh Matches" : "Find Matching Photos",
                          systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isPreparing || isFindingLocation)
        }
    }

    @ViewBuilder
    private var locationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Place or address (optional)", text: $locationQuery)
                    .onChange(of: locationQuery) { _, _ in
                        resolvedLocation = nil
                    }
                Button {
                    Task { await findLocation() }
                } label: {
                    if isFindingLocation {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Find")
                    }
                }
                .disabled(locationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || isFindingLocation)
            }

            if let resolvedLocation {
                HStack {
                    Label(resolvedLocation.name, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                    Spacer()
                    Button("Clear") {
                        self.resolvedLocation = nil
                        locationQuery = ""
                    }
                    .font(.caption)
                }

                Picker("Within", selection: $radiusMeters) {
                    Text("1 km").tag(1_000.0)
                    Text("5 km").tag(5_000.0)
                    Text("10 km").tag(10_000.0)
                    Text("25 km").tag(25_000.0)
                    Text("50 km").tag(50_000.0)
                    Text("100 km").tag(100_000.0)
                }
            } else {
                Text("Optionally search around a place. Photos without GPS are excluded when a place is set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        Section("2. Review matches") {
            if isPreparing {
                ProgressView("Preparing KML…")
            } else {
                if !hasCurrentResults {
                    Label("Criteria changed. Find matching photos again before exporting.",
                          systemImage: "arrow.clockwise")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                LabeledContent("Photos matching filters", value: matchingCount.formatted())
                LabeledContent("KML locations", value: placemarks.count.formatted())
                if skipped > 0 {
                    Label("\(skipped.formatted()) matching item\(skipped == 1 ? " has" : "s have") no GPS data and will be skipped.",
                          systemImage: "mappin.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if placemarks.count > 2000 {
                    Label("Google My Maps imports at most 2,000 placemarks per layer. Consider exporting in batches.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                mapPreview
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    private var documentSection: some View {
        Section("3. KML document") {
            TextField("Title", text: $title)
            Toggle("Include chronological route line", isOn: $includeRoute)
            Toggle("Include date, type and coordinates in descriptions", isOn: $includeDescriptions)
        }
    }

    private var importSection: some View {
        Section("Import into Google Maps") {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open google.com/mymaps and create a new map.")
                Text("2. In the layer panel choose Import, then pick the .kml file.")
                Text("3. Each photo or video appears as a pin with its date and details.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mapPreview: some View {
        if placemarks.isEmpty {
            ContentUnavailableView("No Locations",
                                   systemImage: "mappin.slash",
                                   description: Text("No matching items have GPS coordinates."))
        } else {
            Map(initialPosition: .automatic) {
                ForEach(placemarks.prefix(Self.mapMarkerLimit)) { mark in
                    Marker(mark.name,
                           systemImage: mark.isVideo ? "video.fill" : "camera.fill",
                           coordinate: mark.coordinate)
                    .tint(mark.isVideo ? .orange : .blue)
                }
                if includeRoute, placemarks.count > 1 {
                    MapPolyline(coordinates: placemarks.map(\.coordinate))
                        .stroke(.orange, lineWidth: 3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if placemarks.count > Self.mapMarkerLimit {
                    Text("Preview shows first \(Self.mapMarkerLimit) of \(placemarks.count.formatted())")
                        .font(.caption2)
                        .padding(4)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button {
                    Pasteboard.copy(kmlText)
                    statusMessage = "KML copied to the clipboard."
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(!canExport)

                Spacer()

                ShareLink(item: KMLFile(text: kmlText, fileName: fileName),
                          preview: SharePreview(fileName, image: Image(systemName: "map"))) {
                    Label("Share / AirDrop", systemImage: "square.and.arrow.up")
                }
                .disabled(!canExport)

                Button {
                    isExporterPresented = true
                } label: {
                    Label("Save KML…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canExport)
            }
        }
        .padding(12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @MainActor
    private func findLocation() async {
        let query = locationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isFindingLocation = true
        statusMessage = nil
        defer { isFindingLocation = false }

        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let response = try await MKLocalSearch(request: request).start()
            guard let match = response.mapItems.first else {
                statusMessage = "No matching place was found."
                return
            }
            let coordinate = match.placemark.coordinate
            resolvedLocation = ResolvedExportLocation(
                name: match.name ?? query,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude)
        } catch {
            statusMessage = "Could not find that place: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func runExportQuery() async {
        let requestedCriteria = criteria
        isPreparing = true
        statusMessage = nil
        defer { isPreparing = false }

        let result = await library.prepareExport(
            filter: requestedCriteria.filter,
            albumID: requestedCriteria.albumID,
            searchText: requestedCriteria.searchText,
            gpsRequirement: requestedCriteria.gpsRequirement,
            geographicFilter: requestedCriteria.geographicFilter)
        placemarks = result.placemarks
        skipped = result.skippedWithoutLocation
        matchingCount = result.matchingCount
        preparedCriteria = requestedCriteria
    }
}

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
    let geographicFilter: LibraryQuery.GeographicFilter?
}

/// Inputs that change the size of the generated KML; the size plan is recomputed when they change.
private struct SizePlanKey: Hashable {
    let generation: Int
    let includeRoute: Bool
    let includeDescriptions: Bool
}

struct ExportSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var title = KMLBuilder.defaultTitle()
    @State private var exportFilter = AssetFilter()
    @State private var albumID = AlbumItem.allPhotosID
    @State private var searchText = ""
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
    @State private var didApplyDefaults = false
    /// Bumped after each query so the map preview re-frames itself around the new results.
    @State private var mapGeneration = 0
    @State private var sizePlan: KMLSizePlan?
    @State private var splitForMyMaps = true

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
                       geographicFilter: geographicFilter)
    }

    private var hasCurrentResults: Bool { preparedCriteria == criteria }
    private var exceedsPlacemarkLimit: Bool { placemarks.count > KMLBuilder.myMapsPlacemarkLimit }
    private var exceedsByteLimit: Bool { (sizePlan?.estimatedBytes ?? 0) > KMLBuilder.myMapsByteLimit }
    private var exceedsMyMapsLimits: Bool { exceedsPlacemarkLimit || exceedsByteLimit }

    /// One part normally; several when the export is too big for My Maps and splitting is on.
    private var kmlParts: [KMLContent] {
        guard splitForMyMaps, exceedsMyMapsLimits, let ranges = sizePlan?.myMapsParts, ranges.count > 1 else {
            return [KMLContent(title: title, placemarks: placemarks[...],
                               includeRoute: includeRoute, includeDescriptions: includeDescriptions)]
        }
        return ranges.enumerated().map { index, range in
            KMLContent(title: "\(title) (Part \(index + 1) of \(ranges.count))", placemarks: placemarks[range],
                       includeRoute: includeRoute, includeDescriptions: includeDescriptions)
        }
    }
    private var kmlDocument: KMLDocument { KMLDocument(parts: kmlParts) }
    private var defaultFilename: String {
        kmlDocument.parts.count > 1 ? KMLBuilder.baseName(for: title) : kmlDocument.parts[0].fileName
    }
    private var canExport: Bool {
        hasCurrentResults && !isPreparing && !placemarks.isEmpty && sizePlan != nil
    }

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
        .onAppear(perform: applyDefaults)
        .task(id: SizePlanKey(generation: mapGeneration, includeRoute: includeRoute,
                              includeDescriptions: includeDescriptions)) {
            await updateSizePlan()
        }
        .fileExporter(isPresented: $isExporterPresented,
                      document: kmlDocument,
                      contentType: kmlDocument.contentType,
                      defaultFilename: defaultFilename) { result in
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
                myMapsLimitRows

                mapPreview
                    .id(mapGeneration)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    /// File size, the My Maps placemark and size warnings, and the option to split.
    @ViewBuilder
    private var myMapsLimitRows: some View {
        if !placemarks.isEmpty {
            LabeledContent("Estimated file size") {
                if let sizePlan {
                    Text(sizePlan.estimatedBytes.formatted(.byteCount(style: .file)))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        if exceedsPlacemarkLimit {
            Label("Google My Maps imports at most \(KMLBuilder.myMapsPlacemarkLimit.formatted()) places per file.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
        if exceedsByteLimit {
            Label("Google My Maps imports files up to \(KMLBuilder.myMapsByteLimit.formatted(.byteCount(style: .file))). Turning off descriptions makes the file smaller.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
        if exceedsMyMapsLimits, let sizePlan {
            Toggle("Split into files Google My Maps can import", isOn: $splitForMyMaps)
            Text(splitForMyMaps
                 ? "Creates \(sizePlan.myMapsParts.count) files with up to \(KMLBuilder.myMapsPlacemarkLimit.formatted()) places and \(KMLBuilder.myMapsByteLimit.formatted(.byteCount(style: .file))) each, saved together in a folder. Import each file as its own layer."
                 : "Exports a single file. Google Earth can open it, but Google My Maps will reject it.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                if kmlParts.count > 1 {
                    Text("2. In the layer panel choose Import and pick the first .kml file. Use Add layer, then Import, for each of the other files.")
                } else {
                    Text("2. In the layer panel choose Import, then pick the .kml file.")
                }
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
                    Pasteboard.copy(kmlParts[0].build())
                    statusMessage = "KML copied to the clipboard."
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(!canExport || kmlParts.count > 1)
                .help(kmlParts.count > 1 ? "Copy is only available for a single file" : "Copy the KML text")

                Spacer()

                ShareLink(items: kmlParts.map(KMLFile.init),
                          preview: { SharePreview($0.content.fileName, image: Image(systemName: "map")) }) {
                    Label("Share / AirDrop", systemImage: "square.and.arrow.up")
                }
                .disabled(!canExport)

                Button {
                    isExporterPresented = true
                } label: {
                    Label(kmlParts.count > 1 ? "Save \(kmlParts.count) KML Files…" : "Save KML…",
                          systemImage: "square.and.arrow.down")
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
            geographicFilter: requestedCriteria.geographicFilter)
        placemarks = result.placemarks
        skipped = result.skippedWithoutLocation
        matchingCount = result.matchingCount
        preparedCriteria = requestedCriteria
        mapGeneration += 1
    }

    private func updateSizePlan() async {
        sizePlan = nil
        let marks = placemarks, route = includeRoute, descriptions = includeDescriptions
        let plan = await Task.detached(priority: .userInitiated) {
            KMLBuilder.sizePlan(placemarks: marks, includeRoute: route, includeDescriptions: descriptions)
        }.value
        if !Task.isCancelled { sizePlan = plan }
    }

    /// Start from what the user is looking at: their selection if they have one (across all
    /// albums, since selection survives album changes), otherwise the album currently open.
    private func applyDefaults() {
        guard !didApplyDefaults else { return }
        didApplyDefaults = true
        if library.selectedCount > 0 {
            albumID = AlbumItem.allPhotosID
            exportFilter.showSelectedOnly = true
        } else {
            albumID = library.selectedAlbumID ?? AlbumItem.allPhotosID
        }
    }
}

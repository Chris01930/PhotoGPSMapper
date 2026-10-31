import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist as an imported type so Save panels and Share sheets label it correctly.
    static let kml = UTType(importedAs: "com.google.earth.kml", conformingTo: .xml)
}

/// Everything needed to generate a KML file. Views pass this around instead of the text so the
/// (potentially large) document is only built when it is actually saved, shared or copied.
struct KMLContent {
    let title: String
    let placemarks: ArraySlice<KMLPlacemark>
    let includeRoute: Bool
    let includeDescriptions: Bool

    var fileName: String { KMLBuilder.baseName(for: title) + ".kml" }

    func build() -> String {
        KMLBuilder.build(title: title, placemarks: placemarks,
                         includeRoute: includeRoute, includeDescriptions: includeDescriptions)
    }
}

/// Used by `.fileExporter` (Save panel on macOS, document picker on iOS). Export only.
/// One part is saved as a .kml file; several are saved as a folder of .kml files.
struct KMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.kml, .xml] }
    static var writableContentTypes: [UTType] { [.kml, .folder] }

    let parts: [KMLContent]

    var contentType: UTType { parts.count > 1 ? .folder : .kml }

    init(parts: [KMLContent]) { self.parts = parts }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard parts.count > 1 else {
            return FileWrapper(regularFileWithContents: Data((parts.first?.build() ?? "").utf8))
        }
        var files: [String: FileWrapper] = [:]
        for part in parts {
            let file = FileWrapper(regularFileWithContents: Data(part.build().utf8))
            file.preferredFilename = part.fileName
            files[part.fileName] = file
        }
        return FileWrapper(directoryWithFileWrappers: files)
    }
}

/// Used by `ShareLink`; writes a real file so the receiving app sees a proper .kml name.
struct KMLFile: Transferable {
    let content: KMLContent

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .kml) { file in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoMapper", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(file.content.fileName)
            try file.content.build().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

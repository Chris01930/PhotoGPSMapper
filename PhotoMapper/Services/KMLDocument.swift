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
    let placemarks: [KMLPlacemark]
    let includeRoute: Bool
    let includeDescriptions: Bool

    var fileName: String { KMLBuilder.fileName(for: title) }

    func build() -> String {
        KMLBuilder.build(title: title, placemarks: placemarks,
                         includeRoute: includeRoute, includeDescriptions: includeDescriptions)
    }
}

/// Used by `.fileExporter` (Save panel on macOS, document picker on iOS). Export only.
struct KMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.kml, .xml] }
    static var writableContentTypes: [UTType] { [.kml] }

    let content: KMLContent

    init(content: KMLContent) { self.content = content }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.build().utf8))
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

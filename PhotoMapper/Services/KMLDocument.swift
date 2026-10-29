import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist as an imported type so Save panels and Share sheets label it correctly.
    static let kml = UTType(importedAs: "com.google.earth.kml", conformingTo: .xml)
}

/// Used by `.fileExporter` (Save panel on macOS, document picker on iOS).
struct KMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.kml, .xml] }
    static var writableContentTypes: [UTType] { [.kml] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Used by `ShareLink`; writes a real file so the receiving app sees a proper .kml name.
struct KMLFile: Transferable {
    let text: String
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .kml) { file in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoMapper", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(file.fileName)
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

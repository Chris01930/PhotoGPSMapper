import Foundation

enum KMLBuilder {
    static let photoIcon = "http://maps.google.com/mapfiles/kml/shapes/camera.png"
    static let videoIcon = "http://maps.google.com/mapfiles/kml/shapes/movies.png"

    static func build(title: String, placemarks: [KMLPlacemark],
                      includeRoute: Bool, includeDescriptions: Bool) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        // KML colors are aabbggrr, not RGB.
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
        <Document>
          <name>\(escape(title))</name>
          <description>\(escape("Exported by PhotoMapper on \(Date().formatted(date: .long, time: .shortened)). \(placemarks.count) items."))</description>
          <Style id="photo">
            <IconStyle><color>ffffa03b</color><scale>1.1</scale><Icon><href>\(photoIcon)</href></Icon></IconStyle>
          </Style>
          <Style id="video">
            <IconStyle><color>ff3b7aff</color><scale>1.1</scale><Icon><href>\(videoIcon)</href></Icon></IconStyle>
          </Style>
          <Style id="route">
            <LineStyle><color>b31e8cff</color><width>3</width></LineStyle>
          </Style>

        """

        for mark in placemarks {
            out += "  <Placemark>\n"
            out += "    <name>\(escape(mark.name))</name>\n"
            if includeDescriptions {
                out += "    <description><![CDATA[\(descriptionHTML(for: mark))]]></description>\n"
            }
            out += "    <styleUrl>#\(mark.isVideo ? "video" : "photo")</styleUrl>\n"
            if let date = mark.date {
                out += "    <TimeStamp><when>\(iso.string(from: date))</when></TimeStamp>\n"
            }
            out += "    <ExtendedData>\n"
            out += "      <Data name=\"Type\"><value>\(mark.isVideo ? "Video" : "Photo")</value></Data>\n"
            if let date = mark.date {
                out += "      <Data name=\"Date\"><value>\(escape(date.formatted(date: .long, time: .shortened)))</value></Data>\n"
            }
            if mark.isVideo {
                out += "      <Data name=\"Duration\"><value>\(escape(durationText(mark.duration)))</value></Data>\n"
            }
            out += "    </ExtendedData>\n"
            out += "    <Point>\n"
            out += "      <coordinates>\(coordinateString(mark))</coordinates>\n"
            out += "    </Point>\n"
            out += "  </Placemark>\n"
        }

        if includeRoute, placemarks.count > 1 {
            let coords = placemarks.map(coordinateString).joined(separator: "\n        ")
            out += """
              <Placemark>
                <name>Route (chronological)</name>
                <styleUrl>#route</styleUrl>
                <LineString>
                  <tessellate>1</tessellate>
                  <coordinates>
                    \(coords)
                  </coordinates>
                </LineString>
              </Placemark>

            """
        }

        out += "</Document>\n</kml>\n"
        return out
    }

    static func fileName(for title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines)
        var base = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "PhotoMapper" }
        return base + ".kml"
    }

    static func defaultTitle() -> String {
        "PhotoMapper \(Date().formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Helpers

    private static func coordinateString(_ mark: KMLPlacemark) -> String {
        let lon = String(format: "%.6f", mark.coordinate.longitude)
        let lat = String(format: "%.6f", mark.coordinate.latitude)
        let alt = String(format: "%.1f", mark.altitude ?? 0)
        return "\(lon),\(lat),\(alt)"
    }

    private static func descriptionHTML(for mark: KMLPlacemark) -> String {
        var rows: [String] = []
        rows.append("<b>Type:</b> \(mark.isVideo ? "Video" : "Photo")\(mark.isFavorite ? " ♥" : "")")
        if let date = mark.date {
            rows.append("<b>Date:</b> \(escapeHTML(date.formatted(date: .long, time: .shortened)))")
        }
        if mark.isVideo {
            rows.append("<b>Duration:</b> \(durationText(mark.duration))")
        }
        rows.append(String(format: "<b>Coordinates:</b> %.6f, %.6f", mark.coordinate.latitude, mark.coordinate.longitude))
        if let alt = mark.altitude {
            rows.append(String(format: "<b>Altitude:</b> %.0f m", alt))
        }
        return rows.joined(separator: "<br/>")
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

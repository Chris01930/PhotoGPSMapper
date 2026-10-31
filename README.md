# PhotoMapper

A native SwiftUI app for **macOS 14+** and **iOS 17+** (single multiplatform target) that connects to
the Photos library, lets you search and filter photos and videos with thumbnails, select the ones
you want, and export their GPS locations as a **KML** file for Google Maps / Google Earth.

## Features

- **Photos integration** via PhotoKit: All Photos, smart albums (Favorites, Videos, Live Photos,
  Panoramas, Screenshots, …) and your own albums in a sidebar.
- **Search** across original file names, album titles and creation dates (e.g. `IMG_12`, `Iceland`,
  `July 2024`).
- **Filters**: photos / videos, favorites only, only items with a location, only selected items,
  date range, newest/oldest first.
- **Thumbnail grid** with badges for location, video duration, Live Photo and favorite; adjustable
  thumbnail size; tap to select. Selection is kept while you change albums, search or filters.
- **Export wizard** searches all photos in an album using media type, favorites, selected-item,
  filename/album/date text, date range, and optional distance-from-place filters. It starts from
  your current selection if you have one, otherwise from the album you are viewing.
  Review matching items on a map, then create a KML file with an optional chronological route:
  - **Save KML…** (Save panel on macOS, Files picker on iOS)
  - **Share / AirDrop** (system share sheet: AirDrop, Mail, Google Drive, …)
  - **Copy** the KML text to the clipboard
- Photo filtering and KML generation run on-device; photo data is not uploaded. Place-name lookup
  uses Apple Maps to resolve the requested search text to a coordinate.

## KML output

One `<Placemark>` per matching item that has GPS coordinates: name (original file name), styled
camera/movie icon, `<TimeStamp>`, description (date, type, duration, coordinates, altitude) and
`<ExtendedData>`. Items without a location are skipped and reported in the export summary.

## Importing into Google Maps

1. Go to [google.com/mymaps](https://www.google.com/mymaps) and create a new map.
2. In the layer panel click **Import** and choose the exported `.kml` file.
3. Each photo/video appears as a pin with its date and details.

Google My Maps imports at most 2,000 placemarks and 5 MB per file. The export sheet shows the
estimated file size, warns when either limit is exceeded, and can split the export into a folder of
numbered files (`Title (Part 1 of 3).kml`, …) that each fit; import each one as its own layer.
The file also opens directly in Google Earth.

## Building

Open `PhotoMapper.xcodeproj` in Xcode 16 or newer, pick the **My Mac** or an iPhone/iPad
destination, and run. Set your team under *Signing & Capabilities* if Xcode asks for one.

Command line:

```sh
xcodebuild -scheme PhotoMapper -destination 'platform=macOS' build
xcodebuild -scheme PhotoMapper -destination 'generic/platform=iOS Simulator' build
```

Note: this folder lives on an iCloud-synced Desktop. If you point `-derivedDataPath` inside it,
ad-hoc code signing can fail with "resource fork, Finder information, or similar detritus not
allowed" because macOS re-adds extended attributes to synced files. Xcode's default DerivedData
location (in `~/Library`) is unaffected.

## TestFlight

The project is configured for team `Z4K4WDMMZ6` with automatic (cloud-managed) signing. The bundle
ID `com.christophernewell.PhotoMapper` is registered and App Store provisioning profiles exist for
both iOS and macOS.

One-time setup: create the app record at [App Store Connect](https://appstoreconnect.apple.com)
→ My Apps → **+** → New App. Select both **iOS** and **macOS**, pick the bundle ID above, choose a
name and SKU. (App names are unique store-wide; if "PhotoMapper" is taken, any other name works and
does not affect the bundle ID.)

Then upload both platforms with:

```sh
Scripts/upload-testflight.sh        # or: ios | mac
```

Builds show up under the TestFlight tab after processing. `ITSAppUsesNonExemptEncryption` is set to
`NO` in Info.plist, so no export-compliance prompt blocks the build.

## Launch arguments (for automation / simulator testing)

- `--auto-request-photos` — skip the explainer screen and request Photos access immediately.
- `--open-export` — after loading, select everything visible and open the Export sheet.

## Project layout

```
PhotoMapper/
  PhotoMapperApp.swift        App entry, Selection menu commands (⌘A, ⇧⌘L, ⇧⌘D, ⌘E)
  Info.plist                  Photos usage description, KML UTType declaration
  PhotoMapper.entitlements    App Sandbox + Photos + network (place search, map tiles) + user-selected files (macOS)
  Models/                     PhotoItem, AlbumItem, AssetFilter, KMLPlacemark
  Services/
    LibraryModel.swift        @Observable app state: auth, albums, query, selection, export prep
    LibraryQuery.swift        Background PhotoKit fetch + in-memory location/search filtering
    FilenameCache.swift       Lazy original-file-name lookup via PHAssetResource
    ThumbnailProvider.swift   PHCachingImageManager wrapper
    KMLBuilder.swift          KML generation
    KMLDocument.swift         FileDocument + Transferable for save/share
  Views/                      ContentView, SidebarView, AssetGridView, FilterView,
                              StatusBar, ExportSheet, AuthorizationView
```

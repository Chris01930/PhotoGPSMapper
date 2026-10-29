import SwiftUI
import Photos

struct AuthorizationView: View {
    @Environment(LibraryModel.self) private var library
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("PhotoMapper needs access to your Photos")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("The app lists your photos and videos, lets you search and filter them, and exports the GPS locations of the items you pick as a KML file you can import into Google Maps.\n\nNothing is uploaded; everything stays on this device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            switch library.authorizationStatus {
            case .notDetermined:
                Button {
                    isRequesting = true
                    Task {
                        await library.requestAccess()
                        isRequesting = false
                    }
                } label: {
                    Label("Allow Access to Photos", systemImage: "photo.on.rectangle")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)
            case .denied, .restricted:
                Text("Access is currently turned off. Enable it in Settings and come back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    openPrivacySettings()
                } label: {
                    Label("Open Privacy Settings", systemImage: "gear")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            default:
                ProgressView()
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPrivacySettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

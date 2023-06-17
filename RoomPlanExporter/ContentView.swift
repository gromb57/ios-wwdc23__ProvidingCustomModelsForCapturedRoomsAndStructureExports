/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The sample app's primary view.
*/

import SwiftUI
import RoomPlan

/// A model-provider extension that adds catalog-related functions.
extension CapturedRoom.ModelProvider {
    
    /// An error subclass for model catalogs.
    enum CatalogError: LocalizedError {
        
        /// An error that indicates when the system fails to find a catalog by the given name on disk.
        case cannotFindCatalog
        
        /// A human-readable description for the error.
        var errorDescription: String? {
            switch self {
            case .cannotFindCatalog:
                return "Cannot Find Catalog"
            }
        }
    }
    
    /// Validates that a catalog exists with the given filename and loads the catalog.
    static func load() throws -> CapturedRoom.ModelProvider {
        guard let catalogURL = Bundle.main.url(forResource: "RoomPlanCatalog", withExtension: "bundle") else {
            throw CatalogError.cannotFindCatalog
        }
        return try RoomPlanCatalog.load(at: catalogURL)
    }
}

/// A view that defines the app's user interface.
struct ContentView: View {
    
    /// A state for actions that operate on a model catalog.
    enum ExportState {
        case selectCapturedRoom
        case exportCapturedRoom(url: URL)
        case shareCapturedRoom(url: URL)
        case exportError(description: String)
    }
    
    /// The app's current export state.
    @State private var exportState: ExportState = .selectCapturedRoom
    
    /// A state that indicates the app loads a captured room from disk.
    @State private var isSelectingCapturedRoom: Bool = false
    
    /// A view that contains a menu of export formats.
    var body: some View {
        
        switch exportState {
        case .selectCapturedRoom:
            captureRoomSelectionButton
        case .exportCapturedRoom(let url):
            Menu("Export \(url.lastPathComponent)") {
                Button("All") { exportState = export(url: url, exportOptions: [.parametric, .mesh, .model]) }
                Button("Parametric") { exportState = export(url: url, exportOptions: .parametric) }
                Button("Mesh") { exportState = export(url: url, exportOptions: .mesh) }
                Button("Model") { exportState = export(url: url, exportOptions: .model) }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        case .shareCapturedRoom(let url):
            VStack {
                ShareLink("Share \(url.lastPathComponent)", item: url)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                captureRoomSelectionButton
            }
        case .exportError(let description):
            Text("")
                .alert(description, isPresented: .constant(true)) {
                    Button("OK") {
                        exportState = .selectCapturedRoom
                    }
                }
        }
        
    }
    
    /// A button that presents an Open File dialog for a captured room on disk.
    var captureRoomSelectionButton: some View {
        Button(action: {
            isSelectingCapturedRoom = true
        }, label: {
            Text("Open a CapturedRoom...")
        })
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .fileImporter(isPresented: $isSelectingCapturedRoom,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            do {
                guard let capturedRoomURL = try result.get().first else { return }
                exportState = .exportCapturedRoom(url: capturedRoomURL)
            } catch {
                exportState = .exportError(description: "Cannot read CapturedRoom file")
            }
        }
    }
    
    /// Outputs a USDZ file for the selected captured room with its bounding boxes replaced by detailed 3D models.
    func export(url: URL, exportOptions: CapturedRoom.USDExportOptions) -> ExportState {
        let tmpFolderURL = URL(filePath: NSTemporaryDirectory())
        let exportFolderURL = tmpFolderURL.appending(path: "Export")
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        if url.startAccessingSecurityScopedResource() {
            do {
                if FileManager.default.fileExists(atPath: exportFolderURL.path()) {
                    try FileManager.default.removeItem(at: exportFolderURL)
                }
                let data = try Data(contentsOf: url)
                let capturedRoom = try JSONDecoder().decode(CapturedRoom.self, from: data)
                try FileManager.default.createDirectory(at: exportFolderURL, withIntermediateDirectories: true)
                let capturedRoomURL = exportFolderURL.appending(path: "Room.json")
                try FileManager.default.copyItem(at: url, to: capturedRoomURL)
                let usdzURL = exportFolderURL.appending(path: "Room.usdz")
                let metadataURL = exportFolderURL.appending(path: "Room.plist")
                let modelProvider: CapturedRoom.ModelProvider? = exportOptions.contains(.model) ? try CapturedRoom.ModelProvider.load() : nil
                try capturedRoom.export(to: usdzURL, metadataURL: metadataURL, modelProvider: modelProvider,
                                        exportOptions: exportOptions)
                return .shareCapturedRoom(url: exportFolderURL)
            } catch {
                return .exportError(description: "CapturedRoom export failed: \(error.localizedDescription)")
            }
        } else {
            return .exportError(description: "Cannot access \(url.lastPathComponent)")
        }
    }
}

/// A structure that enables previewing during development.
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

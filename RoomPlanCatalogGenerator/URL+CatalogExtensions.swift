/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
URL utilities that support model catalogs.
*/

import Foundation

/// An extension that defines URL utilities to support model catalogs.
extension URL {
    
    /// A file extension for catalog models.
    static let generatedModelExtension = "usdc"
    
    /// A subextension for catalog models.
    static private let generatedModelSubExtension = "rooms"
    
    /// Creates a URL by expanding a tilde in the file path.
    init(expandingTildeInFilePath filePath: String) {
        self.init(filePath: NSString(string: filePath).expandingTildeInPath)
    }
    
    /// Checks whether the URL's file path is of the model-catalog format.
    var isAGeneratedModel: Bool {
        let urlExtension = self.pathExtension
        let urlSubExtension = self.deletingPathExtension().pathExtension
        return (urlExtension.uppercased() == Self.generatedModelExtension.uppercased() &&
                urlSubExtension.uppercased() == Self.generatedModelSubExtension.uppercased())
    }
    
    /// Creates a new URL by removing the extension and subextension from the file path.
    func replaceExtensionByGeneratedModelExtension() -> URL {
        return self.deletingPathExtension()
            .appendingPathExtension(Self.generatedModelSubExtension)
            .appendingPathExtension(Self.generatedModelExtension)
    }
}

/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A structure that manages a catalog index.
*/

import Foundation
import RoomPlan
import simd
import os

/// A structure that manages a catalog index. You can create your own model catalog or use the sample project's prepopulated catalog.
struct RoomPlanCatalog: Codable {
    
    /// The name of the catalog file on disk.
    static let catalogIndexFilename = "catalog.plist"
    
    /// A name for an empty file.
    static let emptyFilename = ".empty"
    
    /// An array of categories and attributes that the catalog supports.
    let categoryAttributes: [RoomPlanCatalogCategoryAttribute]
    
    /// Creates a catalog with the given app-supported attributes.
    init(categoryAttributes: [RoomPlanCatalogCategoryAttribute]) {
        self.categoryAttributes = categoryAttributes
    }
    
    /// Creates a catalog.
    init() {
        var categoryAttributes = [RoomPlanCatalogCategoryAttribute]()
        // Iterate through all categories that RoomPlan supports.
        for category in CapturedRoom.Object.Category.allCases {
            let attributeTypes = category.supportedAttributeTypes
            
            // Check whether this category has attributes.
            // This isn't mandatory, and you can comment if you want
            // to replace a category without attributes by a model.
            guard !attributeTypes.isEmpty else { continue }
            
            categoryAttributes.append(.init(category: category, attributes: []))
            for attributes in category.supportedCombinations {
                categoryAttributes.append(
                    RoomPlanCatalogCategoryAttribute(category: category, attributes: attributes))
            }
        }
        self.init(categoryAttributes: categoryAttributes)
    }
    
    /// Loads a catalog with the given URL.
    static func load(at url: URL) throws -> CapturedRoom.ModelProvider {
        let catalogPListURL = url.appending(path: RoomPlanCatalog.catalogIndexFilename)
        let data = try Data(contentsOf: catalogPListURL)
        let propertyListDecoder = PropertyListDecoder()
        let catalog = try propertyListDecoder.decode(RoomPlanCatalog.self, from: data)
        
        var modelProvider = CapturedRoom.ModelProvider()
        // Iterate through categories/attributes in the catalog.
        for categoryAttribute in catalog.categoryAttributes {
            guard let modelFilename = categoryAttribute.modelFilename else { continue }
            let folderRelativePath = categoryAttribute.folderRelativePath
            let modelURL = url.appending(path: folderRelativePath).appending(path: modelFilename)
            if categoryAttribute.attributes.isEmpty {
                do {
                    try modelProvider.setModelFileURL(modelURL, for: categoryAttribute.category)
                } catch {
                    Logger().warning("Can't add \(modelURL.lastPathComponent) to ModelProvider: \(error.localizedDescription)")
                }
            } else {
                do {
                    try modelProvider.setModelFileURL(modelURL, for: categoryAttribute.attributes)
                } catch {
                    Logger().warning("Can't add \(modelURL.lastPathComponent) to ModelProvider: \(error.localizedDescription)")
                }
            }
        }
        
        return modelProvider
    }
}

/// A structure that holds attributes that the app supports.
struct RoomPlanCatalogCategoryAttribute: Codable {
    enum CodingKeys: String, CodingKey {
        case folderRelativePath
        case category
        case attributes
        case modelFilename
    }
    
    /// A relative path of the folder that contains a 3D model.
    let folderRelativePath: String
    
    /// An object category for a 3D model.
    let category: CapturedRoom.Object.Category

    /// An array of object attributes.
    let attributes: [any CapturedRoomAttribute]
    
    /// A filename for the 3D model.
    private(set) var modelFilename: String? = nil
    
    /// The resources file path component.
    static let resourcesFolderName = "Resources"
    
    /// The default category file path component.
    private static let defaultCategoryAttributeFolderName = "Default"
    
    /// Creates a catalog attributes instance with the given object category and attributes array.
    init(category: CapturedRoom.Object.Category, attributes: [any CapturedRoomAttribute]) {
        self.category = category
        self.attributes = attributes
        self.folderRelativePath = Self.generateFolderRelativePath(category: category, attributes: attributes)
    }
    
    /// Creates a catalog attributes instance by deserializing the given decoder.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderRelativePath = try container.decode(String.self, forKey: .folderRelativePath)
        category = try container.decode(CapturedRoom.Object.Category.self, forKey: .category)
        let attributesCodableRepresentation = try container.decode(
            CapturedRoom.AttributesCodableRepresentation.self, forKey: .attributes)
        attributes = attributesCodableRepresentation.attributes
        modelFilename = try? container.decode(String.self, forKey: .modelFilename)
    }

    /// Serializes a catalog attributes instance to the given encoder.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.folderRelativePath, forKey: .folderRelativePath)
        try container.encode(self.category, forKey: .category)
        let attributesCodableRepresentation = CapturedRoom.AttributesCodableRepresentation(
            attributes: attributes)
        try container.encode(attributesCodableRepresentation, forKey: .attributes)
        try container.encode(self.modelFilename, forKey: .modelFilename)
    }
    
    /// Sets the 3D model filename.
    mutating func addModelFilename(_ modelFilename: String) {
        self.modelFilename = modelFilename
    }
    
    /// Returns a complete file path on disk for the given category and attributes array.
    private static func generateFolderRelativePath(category: CapturedRoom.Object.Category,
                                                   attributes: [any CapturedRoomAttribute]) -> String {
        let path = "\(resourcesFolderName)/\(String(describing: category).capitalized)"
        if attributes.isEmpty {
            return "\(path)/\(defaultCategoryAttributeFolderName)"
        }
        var attributesPaths = [String]()
        for attribute in attributes {
            attributesPaths.append(attribute.shortIdentifier)
        }
        var attributePath = attributesPaths.joined(separator: "_")
        attributePath = attributePath.prefix(1).capitalized + attributePath.dropFirst(1)
        return "\(path)/\(attributePath)"
    }
}

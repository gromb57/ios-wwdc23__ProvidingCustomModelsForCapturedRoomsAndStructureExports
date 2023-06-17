/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The sample app's main commands.
*/

import Foundation
import ArgumentParser
import ModelIO
import RoomPlan
import os
/// A structure that creates and manages a folder hierarchy of 3D models on disk.
@main
struct RoomPlanCatalogGenerator: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "RoomPlanCatalogGenerator",
                                                        abstract: "RoomPlan Catalog Generator",
                                                    subcommands: [CreateFolderHierarchy.self,
                                                                  GenerateCatalog.self,
                                                                  ConvertRoom.self])
}

/// An extension that defines the catalog generation command.
extension RoomPlanCatalogGenerator {
    
    /// Errors that can occur during catalog generation.
    enum GeneratorError: LocalizedError {
        case nonExistingPath(type: String, url: URL)
        case notADirectory(type: String, url: URL)
        case wrongExtension(url: URL, supportedExtensions: [String])
        case cannotCreateCatalog(underlyingError: Error)
        case cannotCreateHierarchy(underlyingError: Error)
        case cannotParseHierarchy(url: URL, underlyingError: Error)
        case folderHierarchyNotCreated(url: URL)
        case folderHierarchyCompromised(url: URL)
        case cannotRemoveModelFile(url: URL, underlyingError: Error)
        case cannotConvertRoom(url: URL, underlyingError: Error)
        
        /// A human-readable description for the error.
        var errorDescription: String? {
            switch self {
            case .nonExistingPath(let type, let url):
                return "\(type.capitalized) path \(url.path()) doesn't exist"
            case .notADirectory(let type, let url):
                return "\(type.capitalized) path \(url.path()) isn't a directory"
            case .wrongExtension(let url, let supportedExtensions):
                let supportedExtStr = supportedExtensions.map { ".\($0)" }.joined(separator: " or ")
                return "Unsupported path extension for \(url.path()): this tool only supports \(supportedExtStr) extension"
            case .cannotCreateCatalog(let underlyingError):
                return "Can't create catalog bundle: \(underlyingError.localizedDescription)"
            case .cannotCreateHierarchy(let underlyingError):
                return "Can't create catalog folder hierarchy: \(underlyingError.localizedDescription)"
            case .cannotParseHierarchy(let url, let underlyingError):
                return "Can't parse \(url.path()): \(underlyingError.localizedDescription)"
            case .folderHierarchyNotCreated(let url):
                return "Folder hierarchy not created at \(url.path). Run RoomPlanCatalogGenerator create-folders first"
            case .folderHierarchyCompromised(let url):
                return "Folder hierarchy at \(url.path) contains files that aren't part of the catalog. You need to remove them."
            case .cannotRemoveModelFile(let url, let underlyingError):
                return "Can't remove model file at \(url.path()): \(underlyingError.localizedDescription)"
            case .cannotConvertRoom(let url, let underlyingError):
                return "Can't convert Room at \(url.path()): \(underlyingError.localizedDescription)"
            }
        }
    }
    
    /// A structure that configures a command-line command to generate a catalog's folder hierarchy.
    struct CreateFolderHierarchy: ParsableCommand {
        
        /// A command-line command definition for creating the folder hierarchy.
        static let configuration = CommandConfiguration(
            commandName: "create-folders",
            abstract: "Creates Catalog Folder Hierarchy")
        
        /// Arguments for the command.
        struct Options: ParsableArguments {
            @Option(name: .shortAndLong, help: "Path of the catalog folder. By default, it's the current folder")
            var inputPath: String = FileManager.default.currentDirectoryPath
        }
        @OptionGroup var options: Options
        
        /// Generates the folder hierarchy when a shell receives the command by name.
        mutating func run() throws {
            do {
                let inputURL = URL(expandingTildeInFilePath: options.inputPath)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: inputURL.path(), isDirectory: &isDirectory),
                   !isDirectory.boolValue {
                    throw GeneratorError.notADirectory(type: "input", url: inputURL)
                }
                let catalog = RoomPlanCatalog()
                
                Logger().info("Number of attribute combinations: \(catalog.categoryAttributes.count)")
                for categoryAttribute in catalog.categoryAttributes {
                    let categoryFolderURL = inputURL.appending(path: categoryAttribute.folderRelativePath)
                    if !FileManager.default.fileExists(atPath: categoryFolderURL.path) {
                        // Create a folder for each category/attribute combination.
                        try FileManager.default.createDirectory(at: categoryFolderURL,
                                                                withIntermediateDirectories: true)
                    }
                }
            } catch {
                throw GeneratorError.cannotCreateHierarchy(underlyingError: error)
            }
        }
    }
}

/// A catalog generator extension that fills a folder hierarchy with supplied 3D models.
extension RoomPlanCatalogGenerator {
    
    /// A structure that configures a command-line command that fills a catalog's folder hierarchy with 3D models.
    struct GenerateCatalog: ParsableCommand {
        
        /// A command-line command definition for filling the folder hierarchy with 3D models.
        static let configuration = CommandConfiguration(
            commandName: "generate",
            abstract: "Parses folder hierarchy and generates a RoomPlan catalog out of it.")
        
        /// Arguments for the command.
        struct Options: ParsableArguments {
            @Option(name: .shortAndLong, help: "Path of the catalog folder. By default, it's the current folder.")
            var inputPath: String = FileManager.default.currentDirectoryPath
            @Option(name: .shortAndLong, help: "Path of the generated catalog bundle.")
            var outputPath: String = "\(FileManager.default.currentDirectoryPath)/RoomPlanCatalog.bundle"
        }
        @OptionGroup var options: Options
        
        /// Fills the catalog when a shell receives the command by name.
        mutating func run() throws {
            let inputURL = URL(expandingTildeInFilePath: options.inputPath)
            
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) {
                throw GeneratorError.nonExistingPath(type: "input", url: inputURL)
            } else if !isDirectory.boolValue {
                throw GeneratorError.notADirectory(type: "input", url: inputURL)
            }
            let outputURL = URL(expandingTildeInFilePath: options.outputPath)
            let catalogURL = inputURL.appendingPathComponent(RoomPlanCatalog.catalogIndexFilename)
            
            if outputURL.pathExtension.compare("bundle", options: .caseInsensitive) != .orderedSame {
                throw GeneratorError.wrongExtension(url: outputURL, supportedExtensions: ["bundle"])
            }
            let catalog = RoomPlanCatalog()
            try chechInputURL(inputURL)
            
            var enhancedCatagoryAttributes = [RoomPlanCatalogCategoryAttribute]()
            for categoryAttribute in catalog.categoryAttributes {
                var enhancedCategoryAttribute = categoryAttribute
                let attributeFolderURL = inputURL.appending(path: categoryAttribute.folderRelativePath)
                guard FileManager.default.fileExists(atPath: attributeFolderURL.path()) else { continue }
                let emptyFileURL = attributeFolderURL.appending(path: RoomPlanCatalog.emptyFilename)
                if let modelFilename = try createModel(
                    at: attributeFolderURL, categoryAttribute: categoryAttribute) {
                    enhancedCategoryAttribute.addModelFilename(modelFilename)
                    try? FileManager.default.removeItem(at: emptyFileURL)
                } else {
                    FileManager.default.createFile(atPath: emptyFileURL.path(), contents: nil)
                }
                enhancedCatagoryAttributes.append(enhancedCategoryAttribute)
            }
            
            // Write the catalog index.
            let enhancedCatalog = RoomPlanCatalog(categoryAttributes: enhancedCatagoryAttributes)
            try writeCatalog(enhancedCatalog, to: catalogURL)
            do {
                // Write the catalog bundle.
                let fileWrapper = try FileWrapper(url: inputURL)
                try fileWrapper.write(to: outputURL, options: [.atomic, .withNameUpdating],
                                      originalContentsURL: nil)
            } catch {
                throw GeneratorError.cannotCreateCatalog(underlyingError: error)
            }
            let missingCount = enhancedCatalog.categoryAttributes.filter { $0.modelFilename == nil }.count
            if missingCount > 0 {
                print("\(missingCount) missing models")
            }
            print("Catalog bundle created at \(outputURL.path())")
            try cleanCatalogPackage(at: outputURL)
        }
        
        /// Validates a file path URL in the folder hierarchy.
        private func chechInputURL(_ inputURL: URL) throws {
            let inputContents: [URL]
            do {
                inputContents = try FileManager.default.contentsOfDirectory(
                    at: inputURL, includingPropertiesForKeys: [.isDirectoryKey])
                
            } catch {
                throw GeneratorError.folderHierarchyNotCreated(url: inputURL)
            }
            if inputContents.isEmpty {
                throw GeneratorError.folderHierarchyNotCreated(url: inputURL)
            } else {
                for inputElement in inputContents {
                    let elementName = inputElement.lastPathComponent
                    if !((try? inputElement.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) {
                        if elementName != RoomPlanCatalog.catalogIndexFilename, elementName.prefix(1) != "." {
                            throw GeneratorError.folderHierarchyCompromised(url: inputURL)
                        }
                    } else {
                        if elementName != RoomPlanCatalogCategoryAttribute.resourcesFolderName {
                            throw GeneratorError.folderHierarchyCompromised(url: inputURL)
                        }
                    }
                }
            }
        }
        
        /// Outputs a complete catalog to the given file URL.
        private func writeCatalog(_ catalog: RoomPlanCatalog, to folderURL: URL) throws {
            let plistEncoder = PropertyListEncoder()
            let data = try plistEncoder.encode(catalog)
            try data.write(to: folderURL)
        }
        
        /// Validates a 3D model at the given file URL.
        private func createModel(at folderURL: URL,
                                 categoryAttribute: RoomPlanCatalogCategoryAttribute) throws -> String? {
            let contents = try FileManager.default.contentsOfDirectory(at: folderURL,
                                                                       includingPropertiesForKeys: [])
            var generatedModelURL: URL? = nil
                
            for childURL in contents {
                guard MDLAsset.canImportFileExtension(childURL.pathExtension) else { continue }
                if childURL.isAGeneratedModel {
                    generatedModelURL = childURL
                    continue
                }
                generatedModelURL = try createUSDC(inputURL: childURL)
                break
            }
            return generatedModelURL?.lastPathComponent
        }
        
        /// Creates a 3D model URL for the given input URL.
        private func createUSDC(inputURL: URL) throws -> URL {
            let outputURL = inputURL.replaceExtensionByGeneratedModelExtension()
            if inputURL.pathExtension.caseInsensitiveCompare(URL.generatedModelExtension) == .orderedSame {
                if FileManager.default.fileExists(atPath: outputURL.path()) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.copyItem(at: inputURL, to: outputURL)
            } else {
                let modelAsset = MDLAsset(url: inputURL)
                try modelAsset.export(to: outputURL)
            }
            return outputURL
        }
        
        /// Removes any superfluous paths from the folder hierarchy.
        private func cleanCatalogPackage(at url: URL) throws {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path(), isDirectory: &isDirectory),
               isDirectory.boolValue {
                let urlContents: [URL]
                do {
                    urlContents = try FileManager.default.contentsOfDirectory(
                        at: url, includingPropertiesForKeys: nil)
                } catch {
                    throw GeneratorError.cannotParseHierarchy(url: url, underlyingError: error)
                }
                for childURL in urlContents {
                    try cleanCatalogPackage(at: childURL)
                }
            } else if !url.isAGeneratedModel, url.lastPathComponent != RoomPlanCatalog.catalogIndexFilename,
                      url.lastPathComponent != RoomPlanCatalog.emptyFilename {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    throw GeneratorError.cannotRemoveModelFile(url: url, underlyingError: error)
                }
            }
        }
    }
}

/// A catalog generator extension generates a 3D model from a serialized scan and replaces the bounding boxes with detailed models.
extension RoomPlanCatalogGenerator {
    
    /// A structure that configures a command-line command to generate a 3D model that replaces the bounding boxes with detailed models.
    struct ConvertRoom: ParsableCommand {
        
        /// Arguments for the command.
        struct Options: ParsableArguments {
            @Option(name: .shortAndLong, help: "Path of the RoomPlan scan file (in plist or json format)")
            var inputPath: String
            @Option(name: .shortAndLong, help: "Path of catalog bundle")
            var catalogPath: String
            @Option(name: .shortAndLong, help: "Path of the output usdz file")
            var outputPath: String
        }
        
        @OptionGroup var options: Options
    
        /// A command-line command definition for generating the 3D model.
        static let configuration = CommandConfiguration(
            commandName: "convert",
            abstract: "Converts a RoomPlan scan in JSON or .plist format to a USDZ using the models in the catalog.")
        
        /// Generates the 3D model when a shell receives the command by name.
        mutating func run() throws {
            let inputURL = URL(expandingTildeInFilePath: options.inputPath)
            let catalogURL = URL(expandingTildeInFilePath: options.catalogPath)
            let outputURL = URL(expandingTildeInFilePath: options.outputPath)
            if !FileManager.default.fileExists(atPath: inputURL.path) {
                throw GeneratorError.nonExistingPath(type: "input", url: inputURL)
            }
            if !FileManager.default.fileExists(atPath: catalogURL.path) {
                throw GeneratorError.nonExistingPath(type: "catalog", url: catalogURL)
            }
            
            let capturedRoom: CapturedRoom?
            do {
                let data = try Data(contentsOf: inputURL)
                if inputURL.pathExtension.compare("json", options: .caseInsensitive) == .orderedSame {
                    capturedRoom = try JSONDecoder().decode(CapturedRoom.self, from: data)
                } else if inputURL.pathExtension.compare("plist", options: .caseInsensitive) == .orderedSame {
                    capturedRoom = try PropertyListDecoder().decode(CapturedRoom.self, from: data)
                } else {
                    capturedRoom = nil
                }
            } catch {
                throw GeneratorError.cannotConvertRoom(url: inputURL, underlyingError: error)
            }
            
            guard let capturedRoom else {
                throw GeneratorError.wrongExtension(url: inputURL, supportedExtensions: ["json", "plist"])
            }
            let modelProvider = try RoomPlanCatalog.load(at: catalogURL)
            try capturedRoom.export(to: outputURL, modelProvider: modelProvider, exportOptions: .model)
            
            print("USDZ created at \(outputURL.path())")
        }
    }
}

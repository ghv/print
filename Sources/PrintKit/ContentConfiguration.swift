// This source file is part of the Print open source project
//
// Copyright 2021 Gustavo Verdun and the ghv/print project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt file for license information
//

import Foundation

public struct ContentConfiguration: Decodable {

    public static func load(root: String, file: String = PrintKitConstants.configFile) -> ContentConfiguration? {
        let isLatest = file == PrintKitConstants.configFile
        let configFileURL = URL(fileURLWithPath: "\(root)/\(file)")
        if let data = try? Data(contentsOf: configFileURL) {
            do {
                var config: ContentConfiguration = try data.decoded()
                config.expandVariables()
                config.isLatestConfig = isLatest
                return config
            } catch let error {
                print("Error: Could not decode \(configFileURL.absoluteString) - \(error)")
            }
        } else {
            if isLatest {
                print("Error: Could not read \(configFileURL.absoluteString)")
            }
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case keychainItem
        case region
        case bucket
        case cloudFront
        case originPathFolder
        case contents
    }

    struct ContentFolder: Decodable {
        enum CodingKeys: String, CodingKey {
            case compactInvalidation
            case prune
            case folder
            case files
        }

        struct File: Decodable {
            var value: [String]

            struct InvalidFileError: Error {
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let file = try? container.decode(String.self) {
                    value = [file, file]
                } else if let file = try? container.decode([String].self) {
                    value = file
                } else {
                    throw InvalidFileError()
                }
            }
        }

        /// Invalidate files using "\(folder)/*" rather than individual files under this path.
        var compactInvalidation: Bool

        /// If true, all target keys that are in the contents.old.json will be deleted if they do not exist in contents.json
        var prune: Bool

        /// The folder or path that will contiain the files specified (key path prefix in S3)
        var folder: String

        /// The list of local relative paths to be served in the above S3 folder
        var files: [[String]]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            folder = try container.decode(String.self, forKey: .folder)
            compactInvalidation = try container.decodeIfPresent(Bool.self, forKey: .compactInvalidation) ?? false
            prune = try container.decodeIfPresent(Bool.self, forKey: .prune) ?? false
            let anyFiles = try container.decode([File].self, forKey: .files)
            files = anyFiles.map { $0.value }
        }
    }

    // The keychain Item name. "AWS" if ommitted
    public var keychainItem: String?

    /// The S3 Bucket Region
    var region: String

    /// The S3 Bucket name
    var bucket: String

    /// The CloudFront Distribution ID
    var cloudFront: String

    /// The Origin Path (prefix added by CloudFront into the Bucket.) The folders in the contents list will be prefixed by this
    var originPathFolder: String

    /// The list of folders and files to serve in the bucket
    var contents: [ContentFolder]

    /// Internal variable to track if this is an old or new config file
    var isLatestConfig = false

    mutating func expandVariables(using internalValues: [String:String]? = nil) {
        let variableKeyPaths: [WritableKeyPath<ContentConfiguration, String>] = [\.region, \.bucket, \.cloudFront, \.originPathFolder]
        for path in variableKeyPaths {
            if self[keyPath: path].hasPrefix("$") {
                let variable = String(self[keyPath: path].dropFirst())
                if let value = internalValues?[variable] ?? ProcessInfo.processInfo.environment[variable] {
                    self[keyPath: path] = value
                }
            }
        }
    }

    // Compacts the paths using wildcards if there is more than one change in or under a compactable folder
    func compactChangedKeysToWildcards(_ changedKeys: [String]) -> [String] {
        var remainingChangedKeys = changedKeys
        let wildcardFolders = contents.compactMap {
            if $0.compactInvalidation {
                return $0.folder
            } else {
                return nil
            }
        }.sorted{ $0 > $1 }

        var wildcards: [String] = []
        for folder in wildcardFolders {
            let keysInFolder = remainingChangedKeys.filter { $0.starts(with: folder) }
            if keysInFolder.count > 1 {
                wildcards.append("\(folder)/*")
            } else {
                wildcards.append(contentsOf: keysInFolder)
            }
            remainingChangedKeys = remainingChangedKeys.filter { !$0.starts(with: folder) }
        }

        // Handle the case where there are nested wildcard levels like "/foo/*" and "/foo/bar/*" to
        // invalidate at the lowest level but combine higher levels to reduce this to one global.
        var result: [String] = []
        for folder in wildcardFolders.reversed() {
            let keysInFolder = wildcards.filter { $0.starts(with: folder) }
            if keysInFolder.count > 1 {
                result.append("/\(folder)/*")
            } else {
                result.append(contentsOf: keysInFolder.map  { "/\($0)" })
            }
            wildcards = wildcards.filter { !$0.starts(with: folder) }
        }
        result.append(contentsOf: remainingChangedKeys.map { "/\($0)" })
        return result
    }

    func buildCloudFrontKeys() -> [String] {
        var keys = [String]()
        for folder in contents {
            if isLatestConfig || folder.prune {
                for localRemoteFile in folder.files {
                    let remote = localRemoteFile[1]
                    let cloudFrontPath = folder.folder.appendPath(component: remote.lastComponent)
                    keys.append("/\(cloudFrontPath)")
                }
            }
        }
        return keys
    }

}

typealias UploadedContents = [String:Double]

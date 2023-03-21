// This source file is part of the Print open source project
//
// Copyright 2021 Gustavo Verdun and the ghv/print project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt file for license information
//

import Foundation

public struct ContentConfiguration: Decodable {

    public static func load(root: String) -> ContentConfiguration? {
        let configFileURL = URL(fileURLWithPath: "\(root)/\(PrintKitConstants.configFile)")
        if let data = try? Data(contentsOf: configFileURL) {
            do {
                var config: ContentConfiguration = try data.decoded()
                config.expandVariables()
                return config
            } catch let error {
                print("Error: Could not decode \(configFileURL.absoluteString) - \(error)")
            }
        } else {
            print("Error: Could not read \(configFileURL.absoluteString)")
        }
        return nil
    }

    struct ContentFolder: Decodable {
        enum CodingKeys: String, CodingKey {
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

        /// The folder or path that will contiain the files specified (key path prefix in S3)
        var folder: String

        /// The list of local relative paths to be served in the above S3 folder
        var files: [[String]]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            folder = try container.decode(String.self, forKey: .folder)
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
}

typealias UploadedContents = [String:Double]

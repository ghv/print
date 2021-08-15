// This source file is part of the Print open source project
//
// Copyright 2021 Gustavo Verdun and the ghv/print project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt file for license information
//

import ArgumentParser
import Files
import Foundation
import PrintKit
import SotoCore

struct Print: ParsableCommand {
    static var configuration = CommandConfiguration(
           abstract: "A utility for deploying static content on S3 and CloudFront.",
           subcommands: [It.self, Keychain.self],
           defaultSubcommand: It.self)
}

extension Print {
    struct Keychain: ParsableCommand {
        static var configuration = CommandConfiguration(abstract: "Stores your AWS API keys in Keychain")

        @Argument(help: "AWS Access Key ID")
        var accessKeyId: String

        func prompt(message: String) -> String {
            print(message)
            if let line = readLine(strippingNewline: true) {
                return line
            } else {
                return ""
            }
        }

        mutating func run() throws {
            let accessSecret = prompt(message: "Enter AWS Access Secret:")
            let aws = AWSCredentials(keyId: accessKeyId, secret: accessSecret)
            try KeychainAccess.write(item: "AWS", value: try aws.endcoded())
        }
    }
}

// TODO: Add flag to define variable values
// TODO: Add flag to define root folder (besides environment variable)
extension Print {
    struct It: ParsableCommand {
        static var configuration = CommandConfiguration(abstract: "Upload touched files")

        func getAWSCredentials() -> AWSCredentials? {
            guard let awsData = (try? KeychainAccess.read(item: "AWS")) else {
                print("Error: Could not read AWS credentials")
                return nil
            }

            guard let awsCredentials: AWSCredentials = try? awsData.decoded() else {
                print("Error: Could not decode AWS credentials")
                return nil
            }
            return awsCredentials
        }

        func getRootFolder() -> Folder? {
            let configFile = PrintKitConstants.configFile
            let rootFolderEnvironmentVariable = PrintKitConstants.rootFolderEnvironmentVariable

            var root: Folder = Folder.current
            if let value = ProcessInfo.processInfo.environment[rootFolderEnvironmentVariable], let valueAsFolder = try? Folder(path: value) {
                root = valueAsFolder
                do {
                    try _ = root.file(named: configFile)
                } catch {
                    print("Error: Could not find '\(value)/\(configFile)' as specified in '\(rootFolderEnvironmentVariable)' environment variable.")
                    return nil
                }
            } else {
                do {
                    try _ = Folder.current.file(named: configFile)
                } catch {
                    print("Error: Could not find '\(configFile)' in current folder")
                    return nil
                }
            }
            return root
        }

        mutating func run() {

            guard let awsCredentials = getAWSCredentials(), let root = getRootFolder() else {
                return
            }

            let client = AWSClient(credentialProvider: awsCredentials.provider,
                                   httpClientProvider: .createNew)

            if let deployer = S3CloudFrontDeployer(client: client, inFolder: root.path) {
                let future = deployer.run()
                do {
                    _ = try future.wait()
                } catch let error {
                    print("Error: Deployment failed with \(error)")
                }
            } else {
                print("Error: Could not create S3 & CloudFront Deployer")
            }

            do {
                try client.syncShutdown()
            } catch let error {
                print("Error: AWS client shutdown failed with \(error)")
            }
          }
      }
}

Print.main()

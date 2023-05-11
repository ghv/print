// This source file is part of the Print open source project
//
// Copyright 2021 Gustavo Verdun and the ghv/print project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt file for license information
//

import Foundation
import SotoS3
import SotoCloudFront

extension AWSCredentials {
    public var provider: CredentialProviderFactory {
        .static(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
    }
}

public class S3CloudFrontDeployer {
    var s3: S3
    var cloudFront: CloudFront

    var root: String
    var config: ContentConfiguration
    var lastUploadTimeStamps: UploadedContents
    var timeStampsFileURL: URL

    public init?(client: AWSClient, inFolder rootFolder: String) {
        cloudFront = CloudFront(client: client)
        root = rootFolder
        config = ContentConfiguration.load(root: rootFolder)!

        timeStampsFileURL = URL(fileURLWithPath: "\(root)/\(PrintKitConstants.timeStampsFile)")
        if let data = try? Data(contentsOf: timeStampsFileURL), let decoded: UploadedContents = try? data.decoded() {
            lastUploadTimeStamps = decoded
        } else {
            lastUploadTimeStamps = [:]
        }

        if let region = Region(awsRegionName: config.region) {
            s3 = S3(client: client, region: region)
        } else {
            print("Error: \(config.region) is not a valid AWS region name")
            return nil
        }
    }

    // [(fullLocalPath, cloudFrontFileName, localRelativePath)]
    private func buildTouchedFilesList() -> [(String, String, String)] {
        var uploadList = [(String, String, String)]()
        for target in config.contents {
            for relativeLocalFilePath in target.files {
                let local = relativeLocalFilePath[0]
                let remote = relativeLocalFilePath[1]
                let tskey = local == remote ? local : "\(local) as \(remote)"
                let fullPath = root.appendPath(component: local)
                let fileModTime = fullPath.fileModificationTime
                let cloudFrontPath = target.folder.appendPath(component: remote.lastComponent)
                if let ts = lastUploadTimeStamps[tskey] {
                    if fileModTime > ts {
                        uploadList.append((fullPath, cloudFrontPath, local))
                        lastUploadTimeStamps[tskey] = fileModTime
                    }
                } else {
                    uploadList.append((fullPath, cloudFrontPath, local))
                    lastUploadTimeStamps[tskey] = fileModTime
                }
            }
        }
        return uploadList
    }

    private func buildOldCloudFrontKeys() -> [String] {
        if let oldConfig = ContentConfiguration.load(root: root, file: PrintKitConstants.oldConfigFile) {
            return oldConfig.buildCloudFrontKeys()
        } else {
            return []
        }
    }

    private func buildPurgeList() -> [String] {
        let old = buildOldCloudFrontKeys()
        let current = Set(config.buildCloudFrontKeys())
        print("old:")
        for key in old {
            print("  \(key)")
        }
        print("current:")
        for key in current {
            print("  \(key)")
        }

        var purge = [String]()
        for key in old {
            if !current.contains(key) {
                print("\(key) is not in current keys, adding to purge list")
                purge.append(key)
            } else {
                print("\(key) is in current keys, not adding to purge list")
            }
        }
        return purge
    }

    private func createHeadBucketFuture() -> EventLoopFuture<Void> {
        s3.headBucket(S3.HeadBucketRequest(bucket: config.bucket))
    }

    private func createJoinedUploadFuture(with changes: [(String, String, String)]) -> EventLoopFuture<[S3.PutObjectOutput]> {
        if changes.count > 0 {
            var futures = [EventLoopFuture<S3.PutObjectOutput>]()
            for (absoluteFilePath, cloudFrontPath, relativeLocalFilePath) in changes {
                let fileExtension = NSString(string: absoluteFilePath).pathExtension
                let contentType = PrintKitConstants.fileExtensionMapping[fileExtension]
                let keyPath = config.originPathFolder.appendPath(component: cloudFrontPath)
                if let body = try? Data(contentsOf: URL(fileURLWithPath: absoluteFilePath)) {
                    let request = S3.PutObjectRequest(body: AWSPayload.data(body),
                                                      bucket: config.bucket, contentType: contentType, key: keyPath)
                    futures.append(s3.putObject(request))
                    print("Uploading file \(relativeLocalFilePath)...")
                }
            }
            return EventLoopFuture.whenAllSucceed(futures, on: s3.eventLoopGroup.next())
        } else {
            let eventLoop =  s3.eventLoopGroup.next()
            return eventLoop.makeSucceededFuture([S3.PutObjectOutput]())
        }
    }

    private func deleteOldConfigFile() {
        let oldConfigFile = root.appendPath(component: PrintKitConstants.oldConfigFile)
        if FileManager.default.fileExists(atPath: oldConfigFile) {
            do {
                try FileManager.default.removeItem(atPath: oldConfigFile)
            } catch {
                print("Failed to delete old config file: \(error)")
            }
        }
    }

    private func createJoinedDeleteFuture() -> EventLoopFuture<Int> {
        let purgeKeys = buildPurgeList()
        let eventLoop =  s3.eventLoopGroup.next()
        if purgeKeys.count > 0 {
            print("Keys to purge:")
            for key in purgeKeys {
                print("   \(key)")
            }
            var futures = [EventLoopFuture<S3.DeleteObjectOutput>]()
            for key in purgeKeys {
                let cloudFrontPath = config.originPathFolder.appendPath(component: key)
                let request = S3.DeleteObjectRequest(bucket: config.bucket, key: cloudFrontPath)
                futures.append(s3.deleteObject(request))
                print("Deleting file \(cloudFrontPath)...")
            }
            return EventLoopFuture.whenAllSucceed(futures, on: eventLoop).map { _ in
                self.deleteOldConfigFile()
                return purgeKeys.count
            }
        } else {
            print("No keys to purge")
            deleteOldConfigFile()
            return eventLoop.makeSucceededFuture(0)
        }
    }

    private struct InvalidationResult {
        let count: Int
        let id: String?
    }

    private func createInvalidationFuture(with changes: [(String, String, String)]) -> EventLoopFuture<InvalidationResult> {
        let allChangedKeys = changes.map{ $0.1 }
        if !allChangedKeys.isEmpty {
            print("All Changed Keys:")
            for key in allChangedKeys {
                print("   \(key)")
            }
        }
        let reducedChangedKeys = config.compactChangedKeysToWildcards(allChangedKeys)
        let eventLoop =  s3.eventLoopGroup.next()
        if reducedChangedKeys.isEmpty {
            return eventLoop.makeSucceededFuture(InvalidationResult(count: 0, id: nil))
        } else {
            print("Invalidated Keys:")
            for key in reducedChangedKeys {
                print("   \(key)")
            }
            let paths = CloudFront.Paths(items: reducedChangedKeys, quantity: reducedChangedKeys.count)
            let batch = CloudFront.InvalidationBatch(callerReference: Date().timeStampID, paths: paths)
            let request = CloudFront.CreateInvalidationRequest(distributionId: config.cloudFront, invalidationBatch: batch)
            return cloudFront.createInvalidation(request).flatMap { result -> EventLoopFuture<InvalidationResult> in
                return eventLoop.makeSucceededFuture(InvalidationResult(count: reducedChangedKeys.count, id: result.invalidation?.id))
            }
        }
    }

    public struct DeploymentResult {
        let uploaded: Int
        let invalidated: Int
        let purged: Int
    }

    private func createUploadAndInvalidationFuture() -> EventLoopFuture<DeploymentResult> {
        let changedFiles = self.buildTouchedFilesList()
        return self.createJoinedUploadFuture(with: changedFiles).flatMap { _ -> EventLoopFuture<DeploymentResult> in
            // changedFiles.count are the number of files to delete (same as the array of results count passed into this.
            return self.createJoinedDeleteFuture().flatMap { purgeCount -> EventLoopFuture<DeploymentResult> in
                return self.createInvalidationFuture(with: changedFiles).map { invalidationResult -> DeploymentResult in
                    if let id = invalidationResult.id  {
                        print("Created invalidation request: \(id)")
                    }
                    return DeploymentResult(uploaded: changedFiles.count, invalidated: invalidationResult.count, purged: purgeCount)
                }
            }
        }
    }

    private func buildKnownTimeStampKeys() -> Set<String> {
        var knownKeys = Set<String>()
        for target in config.contents {
            for relativeLocalFilePath in target.files {
                let local = relativeLocalFilePath[0]
                let remote = relativeLocalFilePath[1]
                let tskey = local == remote ? local : "\(local) as \(remote)"
                knownKeys.insert(tskey)
            }
        }
        return knownKeys
    }

    private func cleanupTimeStamps() -> Bool {
        var result = false
        let knownKeys = buildKnownTimeStampKeys()
        var existingKeys = Set(lastUploadTimeStamps.keys)
        for key in knownKeys {
            existingKeys.remove(key)
        }
        for key in existingKeys {
            result = true
            print("Removing time stamp for \(key)")
            lastUploadTimeStamps.removeValue(forKey: key)
        }
        return result
    }

    private func saveTimeStamps() {
        if let data = try? lastUploadTimeStamps.endcoded() {
            do {
                try data.write(to: timeStampsFileURL)
            } catch let error {
                print("Error: Could not write time stamps to \(timeStampsFileURL.absoluteString) \(error)")
            }
        }
    }

    public func run() -> EventLoopFuture<DeploymentResult> {
        let future = createHeadBucketFuture().flatMap {
            self.createUploadAndInvalidationFuture()
        }

        future.whenSuccess { results in
            var saveTimeStampsNeeded = false

            if results.uploaded == 0 && results.purged == 0 && results.invalidated == 0 {
                print("Nothing to update")
            } else {
                if results.uploaded > 0 {
                    print("Uploaded \(results.uploaded) \(results.uploaded.plural("file"))")
                    saveTimeStampsNeeded = true
                }
                if results.purged > 0 {
                    print("Purged \(results.purged) \(results.purged.plural("key"))")
                    saveTimeStampsNeeded = self.cleanupTimeStamps() || saveTimeStampsNeeded
                }
                if results.invalidated > 0 {
                    print("Invalidated \(results.invalidated) \(results.invalidated.plural("path"))")
                }
                if saveTimeStampsNeeded {
                    self.saveTimeStamps()
                }
            }
        }

        future.whenFailure { error in
            print("Error: \(error)")
        }

        return future
    }

}

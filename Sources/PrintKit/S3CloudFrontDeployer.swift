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

    func createHeadBucketFuture() -> EventLoopFuture<Void> {
        s3.headBucket(S3.HeadBucketRequest(bucket: config.bucket))
    }

    // [(fullLocalPath, cloudFrontFileName, localRelativePath)]
    func buildTouchedFilesList() -> [(String, String, String)] {
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

    func createJoinedUploadFuture(with changes: [(String, String, String)]) -> EventLoopFuture<[S3.PutObjectOutput]> {
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

    func createInvalidationFuture(with changes: [(String, String, String)]) -> EventLoopFuture<CloudFront.CreateInvalidationResult> {
        let allChangedKeys = changes.map{ $0.1 }
        print("All Changed Keys:")
        for key in allChangedKeys {
            print("   \(key)")
        }
        let reducedChangedKeys = config.compactChangedKeysToWildcards(allChangedKeys)
        if reducedChangedKeys.count > 0 {
            print("Invalidated Keys:")
            for key in reducedChangedKeys {
                print("   \(key)")
            }
            let paths = CloudFront.Paths(items: reducedChangedKeys, quantity: reducedChangedKeys.count)
            let batch = CloudFront.InvalidationBatch(callerReference: Date().timeStampID, paths: paths)
            let request = CloudFront.CreateInvalidationRequest(distributionId: config.cloudFront, invalidationBatch: batch)
            return cloudFront.createInvalidation(request)
        } else {
            let eventLoop =  cloudFront.eventLoopGroup.next()
            return eventLoop.makeSucceededFuture(CloudFront.CreateInvalidationResult(invalidation: nil, location: nil))
        }
    }

    func createUploadAndInvalidationFuture() -> EventLoopFuture<Int> {
        let changedFiles = self.buildTouchedFilesList()
        return self.createJoinedUploadFuture(with: changedFiles).flatMap { _ -> EventLoopFuture<Int> in
            return self.createInvalidationFuture(with: changedFiles).map { response -> Int in
                if let id = response.invalidation?.id  {
                    print("Created invalidation request: \(id)")
                }
                return changedFiles.count
            }
        }
    }

    func updateTimeStamps() {
        if let data = try? lastUploadTimeStamps.endcoded() {
            do {
                try data.write(to: timeStampsFileURL)
            } catch let error {
                print("Error: Could not write time stamps to \(timeStampsFileURL.absoluteString) \(error)")
            }
        }
    }

    public func run() -> EventLoopFuture<Int> {
        let future = createHeadBucketFuture().flatMap {
            self.createUploadAndInvalidationFuture()
        }

        future.whenSuccess { count in
            if count == 0 {
                print("Nothing to update")
            } else {
                print("Uploaded \(count) file\(count > 1 ? "s": "")")
                self.updateTimeStamps()
            }
        }

        future.whenFailure { error in
            print("Error: \(error)")
        }

        return future
    }

}

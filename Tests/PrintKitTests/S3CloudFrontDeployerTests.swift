// This source file is part of the Print open source project
//
// Copyright 2021 Gustavo Verdun and the ghv/print project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt file for license information
//

import Files
import Foundation
import SotoS3
import XCTest

@testable import PrintKit

final class DeployerTests: XCTestCase {
    var client: AWSClient!

    override func setUp() {
        let credentials: AWSCredentials
        if let data = try? KeychainAccess.read(item: "AWS"), let decdoded: AWSCredentials = try? data.decoded() {
            credentials = decdoded
        } else {
            print("Error: Could not read AWS credentials")
            credentials = AWSCredentials(keyId: "", secret: "")
        }
        client = AWSClient(
            credentialProvider: credentials.provider,
            httpClientProvider: .createNew)
    }

    override func tearDown() {
        try? client.syncShutdown()
    }

    func testPublisher() {
        print(Folder.current)
        let env = ProcessInfo.processInfo.environment
        for (key, value) in env {
            print("\(key) - \(value)")
        }
        print("==============================================")

        if let root = Bundle.module.path(forResource: "TestSite", ofType: nil) {
            if let publisher = S3CloudFrontDeployer(client: client, inFolder: root ) {
                let future = publisher.run()
                do {
                    let result = try future.wait()
                    XCTAssertGreaterThanOrEqual(result, 0)
                } catch let error {
                    dump(error)
                    print("threw error \"\(error)\"")
                    XCTFail("threw error \"\(error)\"")
                }

            } else {
                XCTFail("Could not create publisher")
            }
        } else {
            XCTFail("Could not get bundle resource path to TestSite")
        }
    }
}

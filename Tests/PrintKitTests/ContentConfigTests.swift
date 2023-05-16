// This source file is part of the Print open source project
//
// Copyright 2021 Gustavo Verdun and the ghv/print project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt file for license information
//

import Foundation
import XCTest

@testable import PrintKit

final class ContentConfigTests: XCTestCase {


    func testKeyChainItem() throws {
        let data = Data("""
            {
              "keychainItem": "someKeychainItem",
              "region": "someRegion",
              "bucket": "someBucket",
              "cloudFront": "someCloudFront",
              "originPathFolder": "someOriginPathFolder",
              "contents": [
              ]
            }
            """.utf8)
        let config: ContentConfiguration = try data.decoded()
        XCTAssertEqual(config.keychainItem, "someKeychainItem")
        XCTAssertEqual(config.region, "someRegion")
        XCTAssertEqual(config.bucket, "someBucket")
        XCTAssertEqual(config.cloudFront, "someCloudFront")
        XCTAssertEqual(config.originPathFolder, "someOriginPathFolder")
        XCTAssertEqual(config.contents.count, 0)
    }

    func testDecoder() throws {
        let data = Data("""
            {
              "region": "someRegion",
              "bucket": "someBucket",
              "cloudFront": "someCloudFront",
              "originPathFolder": "someOriginPathFolder",
              "contents": [
                {
                    "folder": "someFolder",
                    "files": [
                        "someFile",
                        ["anotherFile", "alias"]
                    ]
                }
              ]
            }
            """.utf8)
        let config: ContentConfiguration = try data.decoded()
        XCTAssertNil(config.keychainItem)
        XCTAssertEqual(config.region, "someRegion")
        XCTAssertEqual(config.bucket, "someBucket")
        XCTAssertEqual(config.cloudFront, "someCloudFront")
        XCTAssertEqual(config.originPathFolder, "someOriginPathFolder")
        XCTAssertEqual(config.contents.count, 1)
        XCTAssertEqual(config.contents[0].folder, "someFolder")
        XCTAssertEqual(config.contents[0].compactInvalidation, false)
        XCTAssertEqual(config.contents[0].files.count, 2)
        XCTAssertEqual(config.contents[0].files[0].count, 2)
        XCTAssertEqual(config.contents[0].files[0][0], "someFile")
        XCTAssertEqual(config.contents[0].files[0][1], "someFile")
        XCTAssertEqual(config.contents[0].files[1].count, 2)
        XCTAssertEqual(config.contents[0].files[1][0], "anotherFile")
        XCTAssertEqual(config.contents[0].files[1][1], "alias")
    }

    func testReduceChangedKeys() throws {
        let data = Data("""
            {
              "region": "someRegion",
              "bucket": "someBucket",
              "cloudFront": "someCloudFront",
              "originPathFolder": "someOriginPathFolder",
              "contents": [
                {
                    "folder": "someFolderOne",
                    "compactInvalidation": true,
                    "files": [
                    ]
                },
                {
                    "folder": "someFolderTwo",
                    "files": [
                    ]
                },
                {
                    "folder": "someFolderThree",
                    "compactInvalidation": true,
                    "files": [
                    ]
                },
                {
                    "folder": "someFolderFour",
                    "compactInvalidation": true,
                    "files": [
                    ]
                },
                {
                    "folder": "someFolderFour/Five",
                    "compactInvalidation": true,
                    "files": [
                    ]
                }
              ]
            }
            """.utf8)
        let config: ContentConfiguration = try data.decoded()

        let changedKeys = [
            "someFolderOne/Foo",
            "someFolderTwo/Foo",
            "someFolderThree/Foo",
            "someFolderThree/Bar",
            "someFolderFour/Foo",
            "someFolderFour/Five/Bar",
            "someFolderFour/Five/Baz",
        ].shuffled()

        let expectedKeys = [
            "/someFolderFour/*",
            "/someFolderOne/Foo",
            "/someFolderThree/*",
            "/someFolderTwo/Foo",
        ]

        let resultKeys = config.compactChangedKeysToWildcards(changedKeys)

        XCTAssertEqual(resultKeys, expectedKeys)
    }

    func testBuildCloudFrontKeys() throws {
        let data = Data("""
            {
              "region": "someRegion",
              "bucket": "someBucket",
              "cloudFront": "someCloudFront",
              "originPathFolder": "someOriginPathFolder",
              "contents": [
                {
                    "folder": "someFolderOne/",
                    "prune": true,
                    "files": [
                        "foo",
                        "bar"
                    ]
                },
                {
                    "folder": "someFolderTwo/with/a/path",
                    "files": [
                        "file1",
                    ]
                }
              ]
            }
            """.utf8)
        var config: ContentConfiguration = try data.decoded()
        config.isLatestConfig = false

        let expectedPruneKeys = [
            "/someFolderOne/foo",
            "/someFolderOne/bar"
        ]

        let expectedAllKeys = [
            "/someFolderOne/foo",
            "/someFolderOne/bar",
            "/someFolderTwo/with/a/path/file1"
        ]

        let resultPruneKeys = config.buildCloudFrontKeys()
        XCTAssertEqual(resultPruneKeys, expectedPruneKeys)

        config.isLatestConfig = true
        let resultAllKeys = config.buildCloudFrontKeys()
        XCTAssertEqual(resultAllKeys, expectedAllKeys)
    }

    func testVariableExpanded() throws {
        let someBAR = "BAR"
        let someFOO = "FOO"
        let someBAZ = "BAZ"
        let someBAT = "BAT"
        let environment = [someFOO: someBAR, someBAR: someFOO, someBAZ: someBAT, someBAT: someBAZ]
        let data = Data("""
            {
              "region": "$BAT",
              "bucket": "$FOO",
              "cloudFront": "$BAR",
              "originPathFolder": "$BAZ",
              "contents": [
              ]
            }
            """.utf8)
        var config: ContentConfiguration = try data.decoded()
        config.expandVariables(using: environment)
        XCTAssertEqual(config.region, someBAZ)
        XCTAssertEqual(config.bucket, someBAR)
        XCTAssertEqual(config.cloudFront, someFOO)
        XCTAssertEqual(config.originPathFolder, someBAT)
        XCTAssertEqual(config.contents.count, 0)
    }

    func testVariableNotExpanded() throws {
        let data = Data("""
            {
              "region": "$BAT",
              "bucket": "$FOO",
              "cloudFront": "$BAR",
              "originPathFolder": "$BAZ",
              "contents": [
              ]
            }
            """.utf8)
        var config: ContentConfiguration = try data.decoded()
        config.expandVariables()
        XCTAssertEqual(config.region, "$BAT")
        XCTAssertEqual(config.bucket, "$FOO")
        XCTAssertEqual(config.cloudFront, "$BAR")
        XCTAssertEqual(config.originPathFolder, "$BAZ")
    }

    func testUploadedContents() throws {
        let someKey = "somePath/withSomeFile"
        let someValue: Double = 1.2
        let data = Data("""
            {
              "somePath/withSomeFile": 1.2,
            }
            """.utf8)
        let uploaded: UploadedContents = try data.decoded()
        XCTAssertEqual(uploaded.count, 1)
        XCTAssertTrue(uploaded.keys.contains(someKey))
        XCTAssertEqual(uploaded[someKey], someValue)
    }
}

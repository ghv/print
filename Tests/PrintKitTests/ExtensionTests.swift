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

final class ExtensionTests: XCTestCase {
    func testDateTimeStampID() throws {
        let someDateComponents = DateComponents(
            year: 1971, month: 6, day: 28, hour: 0, minute: 0)
        let someDate = try XCTUnwrap(Calendar.current.date(from: someDateComponents))
        XCTAssertEqual(someDate.timeStampID.count, 15)
        XCTAssertTrue(someDate.timeStampID.hasPrefix("19710628T"))
    }

    func testLastComponent() throws {
        let somePath = "/some/path/to/file.ext"
        XCTAssertEqual(somePath.lastComponent, "file.ext")
    }

    func testFileModificationTime() throws {
        let somePath = "/Applications/Safari.app"
        XCTAssertTrue(somePath.fileModificationTime > 0.0)

        let someNonExistingPath = "/Applications/Safari.app/this/does/not/exist"
        XCTAssertEqual(someNonExistingPath.fileModificationTime, 0.0)
    }

    func testSHA256() {
        let someFixedContent = "test content"
        XCTAssertEqual(someFixedContent.sha256, "6ae8a75555209fd6c44157c0aed8016e763ff435a19cf186f76863140143ff72")
    }
}

// This source file is part of the Print open source project
//
// Copyright 2021 Gustavo Verdun and the ghv/print project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt file for license information
//

import CommonCrypto
import Foundation

extension Encodable {
    public func endcoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(self)
    }
}

extension Data {
    public func decoded<T: Decodable>() throws -> T {
        try JSONDecoder().decode(T.self, from: self)
    }
}

extension Date {
    var timeStampID: String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [
            .withYear,
            .withMonth,
            .withDay,
            .withTime,
        ]
        return dateFormatter.string(from: self)
    }
}

extension String {
    var sha256: String {
        let context = UnsafeMutablePointer<CC_SHA256_CTX>.allocate(capacity: 1)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Init(context)
        CC_SHA256_Update(context, self, CC_LONG(self.lengthOfBytes(using: String.Encoding.utf8)))
        CC_SHA256_Final(&digest, context)
        context.deallocate()
        return digest.map({ String(format: "%02x", $0) }).joined()
    }

    var fileModificationTime: Double {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: self) {
            if let date = attrs[.modificationDate] as? Date {
                return date.timeIntervalSince1970
            }
        }
        return 0.0
    }

    var lastComponent: String {
      return NSString(string: self).lastPathComponent
    }

    func appendPath(component: String) -> String {
        var path = self
        if path.count > 0 && !path.hasSuffix("/") {
            path.append("/\(component)")
        } else {
            path.append(component)
        }
        return path
    }
}

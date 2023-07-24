// This source file is part of the Print open source project
//
// Copyright 2021 Gustavo Verdun and the ghv/print project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt file for license information
//

public enum PrintKitConstants {
    public static let version = "0.0.5"
    public static let configFile = "contents.json"
    public static let oldConfigFile = "contents.old.json"
    public static let timeStampsFile = ".contents-ts.json"
    public static let rootFolderEnvironmentVariable = "PRINTROOT"

    public static let fileExtensionMapping = [
        "css":    "text/css",
        "gif":    "image/gif",
        "html":   "text/html",
        "ico":    "image/vnd.microsoft.icon",
        "jpeg":   "image/jpeg",
        "jpg":    "image/jpeg",
        "js":     "application/javascript",
        "json":   "application/json",
        "mpeg":   "video/mpeg",
        "otf":    "font/otf",
        "png":    "image/png",
        "pdf":    "application/pdf",
        "svg":    "image/svg+xml",
        "tif":    "image/tiff",
        "tiff":   "image/tiff",
        "ts":     "video/mp2t",
        "ttf":    "font/ttf",
        "txt":    "text/plain",
        "weba":   "audio/webm",
        "webm":   "video/webm",
        "webp":   "image/webp",
        "woff":   "font/woff",
        "woff2":  "font/woff2",
        "xhtml":  "application/xhtml+xml",
        "xml":    "application/xml",
    ]
}

// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "Print",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(
            name: "printer",
            targets: ["PrintMain"]),
        .library(
            name: "PrintKit",
            type: .static,
            targets: ["PrintKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"),
        .package(url: "https://github.com/JohnSundell/Files", from: "4.0.0"),
        .package(url: "https://github.com/soto-project/soto.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "PrintKit",
            dependencies: [
                "Files",
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoCloudFront", package: "soto")
            ]
        ),
        .executableTarget(
            name: "PrintMain",
            dependencies: [
                "PrintKit",
                "Files",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
        name: "PrintKitTests",
            dependencies: [
                "PrintKit",
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoCloudFront", package: "soto")
            ],
            resources: [
                .copy("TestSite")
            ]
        )
    ],
    swiftLanguageVersions: [.v5],
    cLanguageStandard: .c11, // gnu11, iso9899_2011
    cxxLanguageStandard: .cxx14 // cxx11, gnucxx11, cxx14, gnucxx14, cxx1z, gnucxx1z
)

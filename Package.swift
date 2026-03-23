// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "idx0",
    targets: [
        .target(
            name: "IPCShared",
            path: "Sources/IPCShared"
        ),
        .executableTarget(
            name: "idx0",
            dependencies: ["IPCShared"]
        ),
    ]
)

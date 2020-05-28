// swift-tools-version:5.2

// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import PackageDescription

let package = Package(
    name: "swiftpm-on-llbuild2",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "0.0.1"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.0.1"),
        .package(name: "llbuild2", url: "https://github.com/apple/swift-llbuild2.git", .branch("master")),
    ],
    targets: [
        .target(
            name: "LLBSwiftBuild",
            dependencies: [
                "llbuild2",
            ]
        ),

        .target(
            name: "spmllb2",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "LLBSwiftBuild",
            ]
        ),

        .testTarget(
            name: "LLBSwiftBuildTests",
            dependencies: ["LLBSwiftBuild"]
        ),
    ]
)

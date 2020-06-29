// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Foundation
import LLBBuildSystem
import LLBBuildSystemUtil
import NIO
import PackageLoading
import PackageModel
import TSCBasic
import llbuild2

struct ManifestLoaderRequest: Codable, LLBBuildKey, Hashable {
    var manifestDataID: LLBDataID
    var packageIdentity: String
}

struct ManifestLoaderResult: LLBBuildValue, Codable {
    var manifest: Manifest
}

class ManifestLoaderFunction: LLBBuildFunction<ManifestLoaderRequest, ManifestLoaderResult> {
    override func evaluate(
        key: ManifestLoaderRequest,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) -> LLBFuture<ManifestLoaderResult> {
        let manifestDataID = key.manifestDataID
        let client = LLBCASFSClient(ctx.db)

        let manifest = client.load(manifestDataID, ctx).flatMapThrowing { node -> LLBCASBlob in
            if let blob = node.blob {
                return blob
            }
            throw StringError("Could not load manifest blob for \(key)")
        }.flatMap {
            $0.read(ctx)
        }.flatMapThrowing {
            try self.loadManifest(
                contents: ByteString($0),
                subpath: key.packageIdentity
            )
        }

        return manifest.map {
            ManifestLoaderResult(manifest: $0)
        }
    }

    private func loadManifest(
        contents: ByteString,
        subpath: String
    ) throws -> Manifest {
        let packagePath = AbsolutePath("/" + Manifest.filename)
        let inMemFS = InMemoryFileSystem()
        try inMemFS.writeFileContents(packagePath, bytes: contents)

        let resources = try UserManifestResources(
            swiftCompiler: Self.swiftCompiler
        )
        let loader = ManifestLoader(manifestResources: resources)
        let toolsVersion = try ToolsVersionLoader().load(
            at: .root, fileSystem: inMemFS
        )

        return try loader.load(
            package: .root,
            baseURL: "/\(subpath)",
            toolsVersion: toolsVersion,
            packageKind: .root,
            fileSystem: inMemFS
        )
    }

    static let swiftCompiler: AbsolutePath = {
        let path = try! Process.checkNonZeroExit(
            args: "xcrun", "--sdk", "macosx", "-f", "swiftc"
        ).spm_chomp()
        return AbsolutePath(path)
    }()
}

struct ManifestLookupRequest: Codable, LLBBuildKey, Hashable {
    var packageID: LLBDataID
}

struct ManifestLookupResult: LLBBuildValue, Codable {
    var manifestID: LLBDataID
}

class ManifestLookupFunction: LLBBuildFunction<ManifestLookupRequest, ManifestLookupResult> {
    override func evaluate(
        key: ManifestLookupRequest,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) -> LLBFuture<ManifestLookupResult> {
        let client = LLBCASFSClient(ctx.db)

        let packageTree = client.load(key.packageID, ctx).flatMapThrowing { node -> LLBCASFileTree in
            if let tree = node.tree {
                return tree
            }
            throw StringError("could not find package source tree for \(key)")
        }

        let packageManifestID = packageTree.flatMapThrowing { tree -> LLBDataID in
            if let id = tree.lookup(Manifest.filename)?.id {
                return id
            }
            throw StringError("could not find \(Manifest.filename) for \(key)")
        }

        return packageManifestID.map {
            ManifestLookupResult(manifestID: $0)
        }
    }
}

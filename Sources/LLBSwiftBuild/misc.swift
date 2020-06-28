// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import NIO
import llbuild2
import LLBBuildSystem
import PackageModel
import TSCBasic

public struct BaseTarget: Codable {
    var name: String
    var c99name: String
    var sources: [LLBArtifact]
    var dependencies: [LLBLabel]
}

public struct DefaultProvider: LLBProvider, Codable {
    public var targetName: String
    public var runnable: LLBArtifact?
    public var inputs: [LLBArtifact]
    public var outputs: [LLBArtifact]
}

extension LLBBuildFunctionInterface {
    func requestManifestLookup(_ packageID: LLBDataID, _ ctx: Context) -> LLBFuture<LLBDataID> {
        let req = ManifestLookupRequest(packageID: packageID)
        return request(req, as: ManifestLookupResult.self, ctx).map { $0.manifestID }
    }

    func requestManifest(
        _ manifestID: LLBDataID,
        packageIdentity: String,
        _ ctx: Context
    ) -> LLBFuture<Manifest> {
        let req = ManifestLoaderRequest(manifestDataID: manifestID, packageIdentity: packageIdentity)
        return request(req, as: ManifestLoaderResult.self, ctx).map { $0.manifest }
    }

    func request(_ key: ManifestLoaderRequest, _ ctx: Context) -> LLBFuture<ManifestLoaderResult> {
        request(key, as: ManifestLoaderResult.self, ctx)
    }
}

extension EventLoopFuture {
    func unwrapOptional<T>(orError error: Swift.Error) -> EventLoopFuture<T> where Value == T? {
        self.flatMapThrowing { value in
            guard let value = value else {
                throw error
            }
            return value
        }
    }

    func unwrapOptional<T>(orStringError error: String) -> EventLoopFuture<T> where Value == T? {
        unwrapOptional(orError: StringError(error))
    }
}

func darwinSDKPath() throws -> AbsolutePath? {
    let result = try Process.checkNonZeroExit(
        args: "xcrun", "-sdk", "macosx", "--show-sdk-path"
    ).spm_chomp()
    return AbsolutePath(result)
}

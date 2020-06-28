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

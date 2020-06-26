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

extension LLBBuildFunction {
    var db: LLBCASDatabase { engineContext.db }
}

extension LLBBuildFunctionInterface {
    func requestManifestLookup(_ packageID: LLBDataID) -> LLBFuture<LLBDataID> {
        let req = ManifestLookupRequest(packageID: packageID)
        return request(req, as: ManifestLookupResult.self).map { $0.manifestID }
    }

    func request(_ key: ManifestLoaderRequest) -> LLBFuture<ManifestLoaderResult> {
        request(key, as: ManifestLoaderResult.self)
    }
}

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

struct PackageLoaderRequest: Codable, LLBBuildKey, Hashable {
    var manifestDataID: LLBDataID
    var packageIdentity: String

    // FIXME: Need to switch this to be the structure of the package direcotry
    // instead of the contents as we'll be invalidating the entire package loading
    // operation on each edit right now.
    var packageDataID: LLBDataID
}

struct PackageLoaderResult: LLBBuildValue, Codable {
    var package: PackageModel.Package
}

class PackageLoaderFunction: LLBBuildFunction<PackageLoaderRequest, PackageLoaderResult> {
    override func evaluate(
        key: PackageLoaderRequest,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) -> LLBFuture<PackageLoaderResult> {
        let manifest = fi.requestManifest(
            key.manifestDataID,
            packageIdentity: key.packageIdentity, ctx
        )

        let db = ctx.db
        let client = LLBCASFSClient(db)

        let casFS = client.load(key.packageDataID, ctx).flatMapThrowing { node -> LLBCASFileTree in
            guard let tree = node.tree else {
                throw StringError("unable to find a cas tree for \(key)")
            }
            return tree
        }.map {
            TSCCASFileSystem(db: db, rootTree: $0, ctx)
        }

        // Create a promise and async out of the event loop as TSCCASFileSystem is not async.
        let packagePromise = db.group.next().makePromise(of: Package.self)
        DispatchQueue.global().async {
            do {
                let manifest = try manifest.wait()
                let fs = try casFS.wait()
                let diags = DiagnosticsEngine()
                let builder = PackageBuilder(
                    manifest: manifest,
                    productFilter: .everything,
                    path: .root,
                    xcTestMinimumDeploymentTargets: [:],
                    fileSystem: fs,
                    diagnostics: diags
                )
                let pkg = try builder.construct()

                if diags.hasErrors {
                    // FIXME: Surface errors properly from here.
                    packagePromise.fail(StringError("have error diagnostics when loading \(key)"))
                    return
                }

                packagePromise.succeed(pkg)
            } catch {
                packagePromise.fail(error)
            }
        }

        return packagePromise.futureResult.map {
            PackageLoaderResult(package: $0)
        }
    }
}

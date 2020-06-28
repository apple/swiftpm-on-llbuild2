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
import LLBBuildSystemUtil
import Foundation
import TSCBasic

public struct SwiftBuildSystemDelegate {
    let rules: [String: LLBRule] = [
        SwiftExecutableTarget.identifier: SwiftExecutableRule(),
    ]

    let functions: [LLBBuildKeyIdentifier: LLBFunction]

    public init() {
        self.functions = [
            BuildRequest.identifier : BuildFunction(),
            ManifestLookupRequest.identifier: ManifestLookupFunction(),
            ManifestLoaderRequest.identifier: ManifestLoaderFunction(),
            PackageLoaderRequest.identifier: PackageLoaderFunction(),
        ]
    }
}

extension SwiftBuildSystemDelegate: LLBRuleLookupDelegate {
    public func rule(for configuredTargetType: LLBConfiguredTarget.Type) -> LLBRule? {
        rules[configuredTargetType.identifier]
    }
}

extension SwiftBuildSystemDelegate: LLBBuildFunctionLookupDelegate {
    public func lookupBuildFunction(for identifier: LLBBuildKeyIdentifier) -> LLBFunction? {
        functions[identifier]
    }
}

extension SwiftBuildSystemDelegate: LLBSerializableRegistrationDelegate {
    public func registerTypes(registry: LLBSerializableRegistry) {
        registry.register(type: SwiftExecutableTarget.self)
    }
}

extension SwiftBuildSystemDelegate: LLBConfiguredTargetDelegate {
    public func configuredTarget(
        for key: LLBConfiguredTargetKey,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) throws -> LLBFuture<LLBConfiguredTarget> {
        let label = key.label
        let packageName = label.logicalPathComponents[0]
        let targetName = label.targetName

        let client = LLBCASFSClient(ctx.db)
        let srcTree = client.load(key.rootID, ctx)
            .map{ $0.tree }
            .unwrapOptional(orStringError: "the package root \(key.rootID) is not a directory")

        let manifestID = fi.requestManifestLookup(key.rootID, ctx)

        let package = manifestID.map {
            PackageLoaderRequest(
                manifestDataID: $0, packageIdentity: packageName, packageDataID: key.rootID)
        }.flatMap {
            fi.request($0, as: PackageLoaderResult.self, ctx)
        }.map {
            $0.package
        }

        let target = package.map { package in
            package.targets.first { $0.name == targetName }
        }
        .unwrapOptional(orStringError: "unable to find target named \(targetName)")

        let srcArtifacts: LLBFuture<[LLBArtifact]> = target.map { target in
            target.sources.paths
        }.and(srcTree).flatMap { (paths, srcTree) in
            var futures: [LLBFuture<LLBArtifact>] = []
            for path in paths {
                let future = srcTree.lookup(path: path, in: ctx.db, ctx)
                    .unwrapOptional(orStringError: "unable to find \(path)").map {
                    LLBArtifact.source(
                        shortPath: path.basename,
                        roots: [label.asRoot, "src"],
                        dataID: $0.id
                    )
                }
                futures.append(future)
            }
            return LLBFuture.whenAllSucceed(futures, on: ctx.group.next())
        }

        return srcArtifacts.map { files in
            return SwiftExecutableTarget(
                name: targetName,
                sources: files,
                dependencies: []
            )
        }
    }
}

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
        SPMTarget.identifier: SPMRule(),
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
        let srcTree: LLBFuture<LLBCASFileTree> = client.load(key.rootID, ctx).flatMapThrowing { node in
            guard let tree = node.tree else {
                throw StringError("the package root \(key.rootID) is not a directory")
            }
            return tree
        }

        let manifestID = fi.requestManifestLookup(key.rootID, ctx)
        let manifest = manifestID.flatMap {
            fi.requestManifest($0, packageIdentity: packageName, ctx)
        }

        let package = manifestID.map {
            PackageLoaderRequest(
                manifestDataID: $0, packageIdentity: packageName, packageDataID: key.rootID)
        }.flatMap {
            fi.request($0, as: PackageLoaderResult.self, ctx)
        }.map {
            $0.package
        }

        let sourceFile = srcTree.flatMap { tree in
            tree.lookup(path: AbsolutePath("/Sources/foo/main.swift"), in: ctx.db, ctx)
        }.map { result -> LLBDataID in
            guard let result = result?.id else {
                fatalError("unable to find main.swift")
            }
            return result
        }.map {
            LLBArtifact.source(
                shortPath: "main.swift",
                roots: [label.asRoot, "src"],
                dataID: $0
            )
        }

        return package.and(sourceFile).map { (m, file) in
            print(m)
            return SPMTarget(
                packageName: packageName,
                name: targetName,
                sources: [file],
                dependencies: []
            )
        }
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
        registry.register(type: SPMTarget.self)
    }
}

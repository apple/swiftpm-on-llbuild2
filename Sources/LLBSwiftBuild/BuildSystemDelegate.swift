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

    let engineContext: LLBBuildEngineContext
    var db: LLBCASDatabase { engineContext.db }
    var group: LLBFuturesDispatchGroup { engineContext.group }

    public init(engineContext: LLBBuildEngineContext) {
        self.engineContext = engineContext
        self.functions = [
            BuildRequest.identifier : BuildFunction(engineContext: engineContext),
            ManifestLookupRequest.identifier: ManifestLookupFunction(engineContext: engineContext),
            ManifestLoaderRequest.identifier: ManifestLoaderFunction(engineContext: engineContext),
        ]
    }
}

extension SwiftBuildSystemDelegate: LLBConfiguredTargetDelegate {
    public func configuredTarget(
        for key: LLBConfiguredTargetKey,
        _ fi: LLBBuildFunctionInterface
    ) throws -> LLBFuture<LLBConfiguredTarget> {
        let label = key.label
        let packageName = label.logicalPathComponents[0]
        let targetName = label.targetName

        let client = LLBCASFSClient(db)

        let srcTree: LLBFuture<LLBCASFileTree> = client.load(key.rootID).flatMapThrowing { node in
            guard let tree = node.tree else {
                throw StringError("the package root \(key.rootID) is not a directory")
            }
            return tree
        }

        let manifestID = fi.requestManifestLookup(key.rootID)
        let manifest = manifestID.map { manifestID in
            ManifestLoaderRequest(manifestDataID: manifestID, packageIdentity: "foo")
        }.flatMap {
            fi.request($0)
        }.map {
            $0.manifest
        }

        let sourceFile = srcTree.flatMap { tree in
            tree.lookup(path: AbsolutePath("/Sources/foo/main.swift"), in: db)
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

        return manifest.and(sourceFile).map { (m, file) in
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

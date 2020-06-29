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
        SwiftLibraryTarget.identifier: SwiftLibraryRule(),
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
        registry.register(type: SwiftLibraryTarget.self)
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

        let manifest = manifestID.flatMap {
            fi.requestManifest(
                $0,
                packageIdentity: packageName,
                ctx
            )
        }

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

        return manifest.and(target).and(srcArtifacts).flatMapThrowing { (manifestAndTarget, files) in
            let manifest = manifestAndTarget.0
            let manifestTarget = manifest.targetMap[targetName]!
            let target = manifestAndTarget.1

            var dependencies: [LLBLabel] = []
            for dependency in manifestTarget.dependencies {
                switch dependency {
                case .target(let name, _):
                    dependencies += [try LLBLabel("//\(packageName):\(name)")]

                case .byName(let name, _):
                    if manifest.targetMap.keys.contains(name) {
                        dependencies += [try LLBLabel("//\(packageName):\(name)")]
                    }
                    // FIXME: handle dependencies outside of this package.

                case .product:
                    // FIXME: handle products dependencies.
                    break
                }
            }

            switch target.type {
            case .executable:
                return SwiftExecutableTarget(
                    name: targetName,
                    sources: files,
                    dependencies: dependencies
                )
            case .library:
                return SwiftLibraryTarget(
                    name: targetName,
                    sources: files,
                    dependencies: dependencies
                )
            case .systemModule, .test, .binary:
                throw StringError("unsupported target \(target) \(target.type)")
            }
        }
    }
}

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
import PackageModel
import TSCBasic
import llbuild2

public struct SwiftBuildSystemDelegate {
    let rules: [String: LLBRule] = [
        SwiftExecutableTarget.identifier: SwiftExecutableRule(),
        SwiftLibraryTarget.identifier: SwiftLibraryRule(),
        CLibraryTarget.identifier: CLibraryRule(),
    ]

    let functions: [LLBBuildKeyIdentifier: LLBFunction]

    public init() {
        self.functions = [
            BuildRequest.identifier: BuildFunction(),
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
        registry.register(type: CLibraryTarget.self)
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
            .map { $0.tree }
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

        let includeDir = self.includeDir(target: target, srcTree: srcTree, ctx)
        let headers = self.headers(label: label, target: target, srcTree: srcTree, ctx)

        let cTargetInfo = includeDir.and(headers).map { includeDir, headers in
            CTargetInfo(label: label, includeDir: includeDir, headers: headers)
        }

        return manifest.and(target).and(srcArtifacts).and(cTargetInfo).flatMapThrowing {
            (manifestAndTargetAndSrcs, cTargetInfo) in
            let manifest = manifestAndTargetAndSrcs.0.0
            let target = manifestAndTargetAndSrcs.0.1
            let files = manifestAndTargetAndSrcs.1
            let manifestTarget = manifest.targetMap[targetName]!

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
                    c99name: target.c99name,
                    sources: files,
                    dependencies: dependencies
                )
            case .library:
                if let cTarget = target as? ClangTarget {
                    return CLibraryTarget(
                        name: cTarget.name,
                        c99name: target.c99name,
                        sources: files,
                        headers: cTargetInfo.headers,
                        dependencies: dependencies,
                        includeDir: cTargetInfo.includeDirArtifact,
                        moduleMap: nil,
                        cTarget: cTarget
                    )
                }

                return SwiftLibraryTarget(
                    name: targetName,
                    c99name: target.c99name,
                    sources: files,
                    dependencies: dependencies
                )
            case .systemModule, .test, .binary:
                throw StringError("unsupported target \(target) \(target.type)")
            }
        }
    }

    func headers(
        label: LLBLabel,
        target: EventLoopFuture<Target>,
        srcTree: LLBFuture<LLBCASFileTree>,
        _ ctx: Context
    ) -> EventLoopFuture<[LLBArtifact]> {
        let headers = target.map { target -> ClangTarget? in
            target as? ClangTarget
        }.and(srcTree).flatMap { (target, srcTree) -> LLBFuture<[LLBArtifact]> in
            guard var headers = target?.headers else {
                return ctx.group.next().makeSucceededFuture([])
            }

            if let includeDir = target?.includeDir {
                headers = headers.filter { !$0.contains(includeDir) }
            }

            var futures: [LLBFuture<LLBArtifact>] = []
            for path in headers {
                let future = srcTree.lookup(path: path, in: ctx.db, ctx)
                    .unwrapOptional(orStringError: "unable to find \(path)").map { $0.id }
                    .map {
                        LLBArtifact.source(
                            shortPath: path.basename,
                            roots: [label.asRoot, "src"],
                            dataID: $0
                        )
                    }
                futures.append(future)
            }
            return LLBFuture.whenAllSucceed(futures, on: ctx.group.next())
        }
        return headers
    }

    func includeDir(
        target: EventLoopFuture<Target>,
        srcTree: LLBFuture<LLBCASFileTree>,
        _ ctx: Context
    ) -> EventLoopFuture<LLBDataID?> {
        let includeDir = target.map { target -> ClangTarget? in
            target as? ClangTarget
        }.and(srcTree).flatMap { (target, srcTree) -> LLBFuture<LLBDataID?> in
            guard let includeDir = target?.includeDir else {
                return ctx.group.next().makeSucceededFuture(nil)
            }
            return srcTree.lookup(path: includeDir, in: ctx.db, ctx).map {
                $0?.id
            }
        }
        return includeDir
    }
}

struct CTargetInfo {
    var label: LLBLabel
    var includeDir: LLBDataID?
    var headers: [LLBArtifact]

    var includeDirArtifact: LLBArtifact? {
        includeDir.map {
            LLBArtifact.sourceDirectory(
                shortPath: "include",
                roots: [label.asRoot, "src"],
                dataID: $0
            )
        }
    }
}

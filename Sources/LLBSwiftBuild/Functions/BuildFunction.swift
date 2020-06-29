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
import TSCBasic
import llbuild2

public struct BuildRequest: Codable, LLBBuildKey, Hashable {
    public var targets: [LLBLabel]
    public var rootID: LLBDataID

    public init(rootID: LLBDataID, targets: [LLBLabel]) {
        self.rootID = rootID
        self.targets = targets
    }
}

public struct BuildResult: LLBBuildValue, Codable {
    public var runnable: LLBDataID?

    public init(runnable: LLBDataID?) {
        self.runnable = runnable
    }
}

class BuildFunction: LLBBuildFunction<BuildRequest, BuildResult> {

    func detectTargets(
        key: BuildRequest,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) -> LLBFuture<[LLBLabel]> {
        let rootPackage = key.rootID
        let packageIdentity = "foo"

        let manifestID = fi.requestManifestLookup(rootPackage, ctx)
        let manifest = manifestID.flatMap {
            fi.requestManifest($0, packageIdentity: packageIdentity, ctx)
        }

        return manifest.flatMapThrowing { manifest in
            let mainTargets = manifest.targets.filter { $0.type == .regular }.map { $0.name }
            return try mainTargets.map { try LLBLabel("//\(packageIdentity):\($0)") }
        }
    }

    override func evaluate(
        key: BuildRequest,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) -> LLBFuture<BuildResult> {
        let targets: LLBFuture<[LLBLabel]>
        if key.targets.isEmpty {
            targets = detectTargets(key: key, fi, ctx)
        } else {
            targets = ctx.group.next().makeSucceededFuture(key.targets)
        }

        let configuredTargetKeys = targets.map { targets in
            targets.map {
                LLBConfiguredTargetKey(
                    rootID: key.rootID,
                    label: $0
                )
            }
        }

        let providerMaps: LLBFuture<[LLBProviderMap]> = configuredTargetKeys.flatMap { keys in
            let deps = keys.map { fi.requestDependency($0, ctx) }
            return LLBFuture.whenAllSucceed(deps, on: ctx.group.next())
        }
        let allArtifacts = artifacts(for: providerMaps, fi, ctx)
        let firstRunnable = runnable(for: providerMaps, fi, ctx)

        return allArtifacts.and(firstRunnable).map { (_, runnable) in
            BuildResult(runnable: runnable?.dataID)
        }
    }

    func artifacts(
        for providerMaps: LLBFuture<[LLBProviderMap]>,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) -> LLBFuture<[LLBArtifactValue]> {
        let artifacts = providerMaps.flatMapThrowing {
            try $0.flatMap { try $0.get(DefaultProvider.self).outputs }
        }

        return artifacts.flatMap { outputs in
            let futures = outputs.map { fi.requestArtifact($0, ctx) }
            return LLBFuture.whenAllSucceed(futures, on: ctx.group.next())
        }
    }

    func runnable(
        for providerMaps: LLBFuture<[LLBProviderMap]>,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) -> LLBFuture<LLBArtifactValue?> {
        let artifacts = providerMaps.flatMapThrowing {
            try $0.compactMap { try $0.get(DefaultProvider.self).runnable }
        }

        return artifacts.flatMap { runnables in
            if let runnable = runnables.first {
                return fi.requestArtifact(runnable, ctx).map { $0 as LLBArtifactValue? }
            } else {
                return ctx.group.next().makeSucceededFuture(nil)
            }
        }
    }
}

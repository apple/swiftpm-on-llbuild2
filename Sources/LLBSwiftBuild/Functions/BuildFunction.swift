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
    override func evaluate(
        key: BuildRequest,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) -> LLBFuture<BuildResult> {

        let configuredTargetKeys = key.targets.map {
            LLBConfiguredTargetKey(
                rootID: key.rootID,
                label: $0
            )
        }

        let providerMaps = configuredTargetKeys.map{ fi.requestDependency($0, ctx) }
        let allArtifactsFuture = providerMaps.map {
            artifacts(for: $0, fi, ctx)
        }
        let allArtifacts = LLBFuture.whenAllSucceed(allArtifactsFuture, on: ctx.group.next())
            .map{ $0.flatMap{ $0 } }

        let allRunnablesFuture = providerMaps.map {
            runnable(for: $0, fi, ctx)
        }
        let allRunnables = LLBFuture.whenAllSucceed(allRunnablesFuture, on: ctx.group.next())
            .map{ $0.compactMap{ $0 } }

        return allArtifacts.and(allRunnables).map { (_, runnables) in
            BuildResult(runnable: runnables.first?.dataID)
        }
    }

    func runnable(
        for providerMap: LLBFuture<LLBProviderMap>,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) -> LLBFuture<LLBArtifactValue?> {
        providerMap.flatMapThrowing {
            try $0.get(DefaultProvider.self).runnable
        }.flatMap { runnable in
            if let runnable = runnable {
                return fi.requestArtifact(runnable, ctx).map { $0 as LLBArtifactValue? }
            } else {
                return ctx.group.next().makeSucceededFuture(nil)
            }
        }
    }

    func artifacts(
        for providerMap: LLBFuture<LLBProviderMap>,
        _ fi: LLBBuildFunctionInterface,
        _ ctx: Context
    ) -> LLBFuture<[LLBArtifactValue]> {
        providerMap.flatMapThrowing {
            try $0.get(DefaultProvider.self).outputs
        }.flatMap { outputs in
            let futures = outputs.map { fi.requestArtifact($0, ctx) }
            return LLBFuture.whenAllSucceed(futures, on: ctx.group.next())
        }
    }
}


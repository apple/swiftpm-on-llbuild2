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
        let configuredTargetKey = LLBConfiguredTargetKey(
            rootID: key.rootID,
            label: key.targets[0]
        )

        let providerMap = fi.requestDependency(configuredTargetKey, ctx)

        let allOutputs: LLBFuture<[LLBArtifactValue]> = providerMap.flatMapThrowing {
            try $0.get(DefaultProvider.self).outputs
        }.flatMap { outputs in
            let futures = outputs.map { fi.requestArtifact($0, ctx) }
            return LLBFuture.whenAllSucceed(futures, on: ctx.group.next())
        }

        let runnable: LLBFuture<LLBArtifactValue?> = providerMap.flatMapThrowing {
            try $0.get(DefaultProvider.self).runnable
        }.flatMap { runnable in
            if let runnable = runnable {
                return fi.requestArtifact(runnable, ctx).map { $0 as LLBArtifactValue? }
            } else {
                return ctx.group.next().makeSucceededFuture(nil)
            }
        }

        return allOutputs.and(runnable).map { (_, runnable) in
            BuildResult(runnable: runnable?.dataID)
        }
    }
}


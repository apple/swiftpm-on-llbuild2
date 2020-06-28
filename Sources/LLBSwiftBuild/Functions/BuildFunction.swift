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
            label: try! LLBLabel("//foo:foo")
        )

        let providerMap = fi.requestDependency(configuredTargetKey, ctx)

        let runnable = providerMap.flatMapThrowing {
            try $0.get(DefaultProvider.self).runnable
        }.flatMapThrowing { runnable -> LLBArtifact in
            guard let run = runnable else {
                throw StringError("only executable targets can be built right now")
            }
            return run
        }.flatMap {
            fi.requestArtifact($0, ctx)
        }

        return runnable.map {
            BuildResult(runnable: $0.dataID)
        }
    }
}


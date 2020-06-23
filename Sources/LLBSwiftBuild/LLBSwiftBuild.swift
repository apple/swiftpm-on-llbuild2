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
    public let stdout: LLBDataID

    public init(stdout: LLBDataID) {
        self.stdout = stdout
    }
}

public struct SPMTarget: LLBConfiguredTarget, Codable {
    var packageName: String
    var name: String
    var sources: [String]
    var dependencies: [LLBProviderMap]
}

class BuildFunction: LLBBuildFunction<BuildRequest, BuildResult> {
    override func evaluate(
        key: BuildRequest,
        _ fi: LLBBuildFunctionInterface
    ) -> LLBFuture<BuildResult> {
        let configuredTargetKey = LLBConfiguredTargetKey(
            rootID: key.rootID,
            label: try! LLBLabel("//foo:foo")
        )

        let providerMap = fi.requestDependency(configuredTargetKey)

        let artifactValue = providerMap.flatMapThrowing {
            try $0.get(SPMProvider.self).stdout
        }.flatMap { artifact in
            fi.requestArtifact(artifact)
        }

        return artifactValue.map {
            BuildResult(stdout: $0.dataID)
        }
    }
}

public struct SPMProvider: LLBProvider, Codable {
    public var targetName: String
    public var stdout: LLBArtifact
}

public class SPMRule: LLBBuildRule<SPMTarget> {
    public override func evaluate(
        configuredTarget: SPMTarget,
        _ ruleContext: LLBRuleContext
    ) throws -> LLBFuture<[LLBProvider]> {
        let stdoutArtifact = try ruleContext.declareArtifact("stdout.txt")

        try ruleContext.registerAction(
            arguments: [
                "/bin/bash", "-c", "echo \(configuredTarget.sources) > \(stdoutArtifact.path)"
            ],
            inputs: [],
            outputs: [stdoutArtifact]
        )

        let provider = SPMProvider(
            targetName: configuredTarget.name,
            stdout: stdoutArtifact
        )

        return ruleContext.group.next().makeSucceededFuture([provider])
    }
}

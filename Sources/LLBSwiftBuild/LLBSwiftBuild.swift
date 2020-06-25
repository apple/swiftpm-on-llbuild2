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
    public let executable: LLBDataID

    public init(executable: LLBDataID) {
        self.executable = executable
    }
}

public struct SPMTarget: LLBConfiguredTarget, Codable {
    public var targetDependencies: [String: LLBTargetDependency] {
        ["dependencies": .list(dependencies)]
    }

    var packageName: String
    var name: String
    var sources: [LLBArtifact]
    var dependencies: [LLBLabel]
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
            try $0.get(SPMProvider.self).executable
        }.flatMap { artifact in
            fi.requestArtifact(artifact)
        }

        return artifactValue.map {
            BuildResult(executable: $0.dataID)
        }
    }
}

public struct SPMProvider: LLBProvider, Codable {
    public var targetName: String
    public var executable: LLBArtifact
}

public class SPMRule: LLBBuildRule<SPMTarget> {
    public override func evaluate(
        configuredTarget: SPMTarget,
        _ ruleContext: LLBRuleContext
    ) throws -> LLBFuture<[LLBProvider]> {
        let buildDir = try ruleContext.declareDirectoryArtifact("build")
        let executable = try ruleContext.declareArtifact("build/\(configuredTarget.name)")

        let mainFile = configuredTarget.sources[0]

        try ruleContext.registerAction(
            arguments: [
                "swiftc",
                mainFile.path,
                "-o",
                executable.path,
            ],
            inputs: [mainFile],
            outputs: [executable, buildDir]
        )

        let provider = SPMProvider(
            targetName: configuredTarget.name,
            // FIXME: Seems like local executor doesn't import file outputs using CASTree.
            executable: buildDir
        )

        return ruleContext.group.next().makeSucceededFuture([provider])
    }
}

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

public struct SwiftExecutableTarget: LLBConfiguredTarget, Codable {
    public var targetDependencies: [String: LLBTargetDependency] {
        ["dependencies": .list(dependencies)]
    }

    var base: BaseTarget
    var name: String { base.name }
    var sources: [LLBArtifact] { base.sources }
    var dependencies: [LLBLabel] { base.dependencies }

    init(
        name: String,
        sources: [LLBArtifact],
        dependencies: [LLBLabel]
    ) {
        self.base = BaseTarget(
            name: name,
            c99name: name,
            sources: sources,
            dependencies: dependencies
        )
    }
}

public class SwiftExecutableRule: LLBBuildRule<SwiftExecutableTarget> {
    public override func evaluate(
        configuredTarget: SwiftExecutableTarget,
        _ ruleContext: LLBRuleContext
    ) throws -> LLBFuture<[LLBProvider]> {
        let buildDir = try ruleContext.declareDirectoryArtifact("build")
        let executable = try ruleContext.declareArtifact("build/\(configuredTarget.name)")
        let sources = configuredTarget.sources

        var commandLine: [String] = []
        commandLine += ["swiftc"]
        commandLine += sources.map{ $0.path }
        commandLine += ["-o", executable.path]

        try ruleContext.registerAction(
            arguments: commandLine,
            inputs: sources,
            outputs: [executable, buildDir]
        )

        let provider = DefaultProvider(
            targetName: configuredTarget.name,
            runnable: executable,
            inputs: sources,
            outputs: [executable]
        )

        return ruleContext.group.next().makeSucceededFuture([provider])
    }
}

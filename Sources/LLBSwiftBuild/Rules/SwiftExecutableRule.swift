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
import SwiftDriver

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
        let dependencies: [DefaultProvider] = try ruleContext.providers(for: "dependencies")

        let tmpDir = try ruleContext.declareDirectoryArtifact("tmp")
        let executable = try ruleContext.declareArtifact("build/\(configuredTarget.name)")
        let sources = configuredTarget.sources

        var commandLine: [String] = []
        commandLine += ["swiftc"]
        commandLine += ["-target", "x86_64-apple-macosx10.15"]
        commandLine += ["-sdk", try darwinSDKPath()!.pathString]
        commandLine += sources.map{ $0.path }
        commandLine += ["-o", executable.path]

        var driver = try Driver(args: commandLine)
        let jobs = try driver.planBuild()
        let resolver = try ArgsResolver(
            fileSystem: localFileSystem,
            temporaryDirectory: .relative(RelativePath(tmpDir.path))
        )

        // FIXME: Can we avoid this?
        try ruleContext.registerAction(
            arguments: ["mkdir", "-p", tmpDir.path],
            inputs: [],
            outputs: [tmpDir]
        )

        let existingArtifacts = sources + [executable]

        func toLLBArtifact(_ paths: [TypedVirtualPath]) throws -> [LLBArtifact] {
            return try paths.map{
                try $0.toLLBArtifact(
                    ruleContext: ruleContext,
                    tmpDir: tmpDir,
                    existingArtifacts: existingArtifacts
                )
            }
        }

        let globalDependencies = dependencies.flatMap{ $0.outputs } + dependencies.compactMap{ $0.swiftmodule }

        for job in jobs {
            let tool = try resolver.resolve(.path(job.tool))
            let args = try job.commandLine.map{ try resolver.resolve($0) }

            let inputs = try toLLBArtifact(job.inputs)
            let outputs = try toLLBArtifact(job.outputs)

            try ruleContext.registerAction(
                arguments: [tool] + args,
                inputs: inputs + globalDependencies,
                outputs: outputs
            )
        }

        let provider = DefaultProvider(
            targetName: configuredTarget.name,
            runnable: executable,
            swiftmodule: nil,
            outputs: [executable]
        )

        return ruleContext.group.next().makeSucceededFuture([provider])
    }
}

extension TypedVirtualPath {
    func toLLBArtifact(
        ruleContext: LLBRuleContext,
        tmpDir: LLBArtifact,
        existingArtifacts: [LLBArtifact]
    ) throws -> LLBArtifact {
        let artifact: LLBArtifact
        if let existingArtifact = existingArtifacts.first(where: { $0.path == file.name }) {
            artifact = existingArtifact
        } else if file.isTemporary {
            artifact = try ruleContext.declareArtifact(tmpDir.shortPath + "/" + file.name)
        } else {
            artifact = try ruleContext.declareArtifact(file.name)
            print("declared \(self.file) \(artifact.path)")
        }
        return artifact
    }
}

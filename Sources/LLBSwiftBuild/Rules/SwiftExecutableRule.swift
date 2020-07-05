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
import SwiftDriver
import TSCBasic
import llbuild2

public struct SwiftExecutableTarget: LLBConfiguredTarget, Codable {
    public var targetDependencies: [String: LLBTargetDependency] {
        ["dependencies": .list(dependencies)]
    }

    var base: BaseTarget
    var name: String { base.name }
    var c99name: String { base.c99name }
    var sources: [LLBArtifact] { base.sources }
    var dependencies: [LLBLabel] { base.dependencies }

    init(
        name: String,
        c99name: String,
        sources: [LLBArtifact],
        dependencies: [LLBLabel]
    ) {
        self.base = BaseTarget(
            name: name,
            c99name: c99name,
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
        let cImportPaths = dependencies.flatMap { $0.cImportPaths }
        let swiftmoduleDeps = dependencies.compactMap { $0.swiftmodule }
        let dependencyObjects = dependencies.flatMap { $0.objects }
        // FIXME: We can do a little better and avoid adding dependency objects in the global dependencies because that will block the non-linking jobs from starting.
        let globalDependencies =
            dependencies.flatMap { $0.outputs } + swiftmoduleDeps + dependencyObjects + cImportPaths

        let tmpDir = try ruleContext.declareDirectoryArtifact("tmp")
        let executable = try ruleContext.declareArtifact("build/\(configuredTarget.name)")
        let sources = configuredTarget.sources

        var commandLine: [String] = []
        commandLine += ["swiftc"]
        commandLine += ["-target", "x86_64-apple-macosx10.15"]
        commandLine += ["-sdk", try darwinSDKPath()!.pathString]
        commandLine += ["-DSWIFT_PACKAGE"]
        // FIXME: RelativePath needs parentDirectory.
        commandLine += swiftmoduleDeps.flatMap { ["-I", RelativePath($0.path).dirname] }
        commandLine += cImportPaths.flatMap { ["-I", $0.path] }
        commandLine += ["-module-name", configuredTarget.c99name]
        if let moduleCachePath = ruleContext.ctx.moduleCache?.path.pathString {
            commandLine += ["-module-cache-path", moduleCachePath]
        }
        commandLine += sources.map { $0.path }
        commandLine += dependencyObjects.map { $0.path }
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

        func toLLBArtifact(_ paths: [TypedVirtualPath]) throws -> [LLBArtifact] {
            return try paths.map {
                try $0.toLLBArtifact(
                    ruleContext: ruleContext,
                    tmpDir: tmpDir,
                    inputArtifacts: sources + globalDependencies
                )
            }
        }

        for job in jobs {
            let tool = try resolver.resolve(.path(job.tool))
            let args = try job.commandLine.map { try resolver.resolve($0) }

            let inputs = try toLLBArtifact(job.inputs)
            let outputs = try toLLBArtifact(job.outputs)

            try ruleContext.registerAction(
                arguments: [tool] + args,
                inputs: inputs + globalDependencies,
                outputs: outputs,
                mnemonic: job.description
            )
        }

        let provider = DefaultProvider(
            targetName: configuredTarget.name,
            runnable: executable,
            swiftmodule: nil,
            cImportPaths: [],
            objects: [],
            outputs: [executable]
        )

        return ruleContext.group.next().makeSucceededFuture([provider])
    }
}

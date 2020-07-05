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

public struct SwiftLibraryTarget: LLBConfiguredTarget, Codable {
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

public class SwiftLibraryRule: LLBBuildRule<SwiftLibraryTarget> {
    public override func evaluate(
        configuredTarget: SwiftLibraryTarget,
        _ ruleContext: LLBRuleContext
    ) throws -> LLBFuture<[LLBProvider]> {
        let dependencies: [DefaultProvider] = try ruleContext.providers(for: "dependencies")
        let swiftmoduleDeps = dependencies.compactMap { $0.swiftmodule }

        let cImportPaths = dependencies.flatMap { $0.cImportPaths }
        let tmpDir = try ruleContext.declareDirectoryArtifact("tmp")
        let swiftmodule = try ruleContext.declareArtifact("build/\(configuredTarget.name).swiftmodule")
        let swiftdoc = try ruleContext.declareArtifact("build/\(configuredTarget.name).swiftdoc")
        let objectFile = try ruleContext.declareArtifact("build/\(configuredTarget.name).o")
        let sources = configuredTarget.sources

        var outputFileMap = OutputFileMap()
        var objects: [LLBArtifact] = []
        for source in sources {
            let object = try ruleContext.declareArtifact("build/objects/\(source.shortPath).o")
            objects.append(object)
            var entry: [FileType: VirtualPath] = [:]
            entry[.object] = .relative(RelativePath(object.path))
            outputFileMap.entries[.relative(RelativePath(source.path))] = entry
        }

        let _tmpDir = try withTemporaryDirectory(removeTreeOnDeinit: false) { $0 }
        defer {
            try? localFileSystem.removeFileTree(_tmpDir)
        }
        let outputFileMapPath = _tmpDir.appending(components: "output-file-map.json")
        try outputFileMap.store(
            fileSystem: localFileSystem,
            file: outputFileMapPath,
            diagnosticEngine: DiagnosticsEngine()
        )

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

        commandLine += ["-emit-module", "-emit-module-path", swiftmodule.path]
        commandLine += ["-emit-module-doc-path", swiftdoc.path]
        commandLine += ["-output-file-map", outputFileMapPath.pathString]
        commandLine += ["-parse-as-library", "-c"]
        commandLine += sources.map { $0.path }

        if let sdkPaths = sdkPlatformFrameworkPaths() {
            commandLine += ["-F", sdkPaths.fwk.pathString]
            commandLine += ["-I", sdkPaths.lib.pathString]
            commandLine += ["-L", sdkPaths.lib.pathString]
        }

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

        let globalDependencies = dependencies.flatMap { $0.outputs } + swiftmoduleDeps + cImportPaths
        let allInputArtifacts = sources + globalDependencies

        func toLLBArtifact(_ paths: [TypedVirtualPath]) throws -> [LLBArtifact] {
            return try paths.map {
                try $0.toLLBArtifact(
                    ruleContext: ruleContext,
                    tmpDir: tmpDir,
                    inputArtifacts: allInputArtifacts
                )
            }
        }

        var allObjectFiles: [LLBArtifact] = []
        for job in jobs {
            let tool = try resolver.resolve(.path(job.tool))
            let args = try job.commandLine.map { try resolver.resolve($0) }

            let inputs = try toLLBArtifact(job.inputs)
            let outputs = try toLLBArtifact(job.outputs)

            let objects = try job.outputs
                .filter { $0.type == .object }
                .map {
                    try $0.toLLBArtifact(
                        ruleContext: ruleContext,
                        tmpDir: tmpDir,
                        inputArtifacts: allInputArtifacts
                    )
                }
            allObjectFiles += objects

            try ruleContext.registerAction(
                arguments: [tool] + args,
                inputs: inputs + globalDependencies,
                outputs: outputs,
                mnemonic: job.description
            )
        }

        var linkCommandLine = ["ld", "-r"]
        linkCommandLine += allObjectFiles.map { $0.path }
        linkCommandLine += ["-o", objectFile.path]
        try ruleContext.registerAction(
            arguments: linkCommandLine,
            inputs: allObjectFiles,
            outputs: [objectFile],
            mnemonic: "Linking \(objectFile.pathRel.basename)"
        )

        let allObjects = dependencies.flatMap { $0.objects }
        let provider = DefaultProvider(
            targetName: configuredTarget.name,
            runnable: nil,
            swiftmodule: swiftmodule,
            cImportPaths: cImportPaths,
            objects: allObjects + [objectFile],
            outputs: allObjects + [objectFile]
        )

        return ruleContext.group.next().makeSucceededFuture([provider])
    }
}

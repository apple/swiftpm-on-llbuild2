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
import PackageModel
import TSCBasic
import llbuild2

public struct CLibraryTarget: LLBConfiguredTarget, Codable {
    public var targetDependencies: [String: LLBTargetDependency] {
        ["dependencies": .list(dependencies)]
    }

    var base: BaseTarget
    var name: String { base.name }
    var c99name: String { base.c99name }
    var sources: [LLBArtifact] { base.sources }
    let headers: [LLBArtifact]
    var dependencies: [LLBLabel] { base.dependencies }
    var includeDir: LLBArtifact?
    var moduleMap: LLBArtifact?

    init(
        name: String,
        c99name: String,
        sources: [LLBArtifact],
        headers: [LLBArtifact],
        dependencies: [LLBLabel],
        includeDir: LLBArtifact?,
        moduleMap: LLBArtifact?,
        cTarget: ClangTarget
    ) {
        self.base = BaseTarget(
            name: name,
            c99name: c99name,
            sources: sources,
            dependencies: dependencies
        )
        self.headers = headers
        self.includeDir = includeDir
        self.moduleMap = moduleMap
    }
}

public class CLibraryRule: LLBBuildRule<CLibraryTarget> {
    public override func evaluate(
        configuredTarget: CLibraryTarget,
        _ ruleContext: LLBRuleContext
    ) throws -> LLBFuture<[LLBProvider]> {
        // let dependencies: [DefaultProvider] = try ruleContext.providers(for: "dependencies")
        let objectFile = try ruleContext.declareArtifact("build/\(configuredTarget.name).o")
        let sources = configuredTarget.sources

        var inputs: [LLBArtifact] = sources + configuredTarget.headers
        var cImportPaths: [LLBArtifact] = []

        if let includeDir = configuredTarget.includeDir {
            inputs += [includeDir]
            cImportPaths += [includeDir]
        }

        var objects: [LLBArtifact] = []
        for source in sources {
            let object = try ruleContext.declareArtifact("build/objects/\(source.shortPath).o")
            objects.append(object)

            var commandLine: [String] = []
            commandLine += ["clang"]
            commandLine += ["-fobjc-arc", "-target", "x86_64-apple-macosx10.15"]
            commandLine += ["-isysroot", try darwinSDKPath()!.pathString]
            commandLine += ["-DSWIFT_PACKAGE=1", "-fblocks"]
            commandLine += ["-fmodules", "-fmodule-name=\(configuredTarget.c99name)"]
            if let moduleCachePath = ruleContext.ctx.moduleCache?.path.pathString {
                commandLine += ["-fmodules-cache-path=\(moduleCachePath)"]
            }
            commandLine += cImportPaths.flatMap { ["-I", $0.path] }

            commandLine += ["-c", source.path]
            commandLine += ["-o", object.path]

            try ruleContext.registerAction(
                arguments: commandLine,
                inputs: inputs,
                outputs: [object],
                mnemonic: "Compiling \(configuredTarget.name) \(source.pathRel.basename)"
            )
        }

        var allObjectFiles: [LLBArtifact] = []
        allObjectFiles += objects

        var linkCommandLine = ["ld", "-r"]
        linkCommandLine += allObjectFiles.map { $0.path }
        linkCommandLine += ["-o", objectFile.path]
        try ruleContext.registerAction(
            arguments: linkCommandLine,
            inputs: allObjectFiles,
            outputs: [objectFile],
            mnemonic: "Linking \(objectFile.pathRel.basename)"
        )

        let provider = DefaultProvider(
            targetName: configuredTarget.name,
            runnable: nil,
            swiftmodule: nil,
            cImportPaths: cImportPaths,
            objects: [objectFile],
            outputs: [objectFile]
        )

        return ruleContext.group.next().makeSucceededFuture([provider])
    }
}

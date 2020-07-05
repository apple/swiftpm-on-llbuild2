// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import ArgumentParser
import Foundation
import LLBBuildSystem
import LLBBuildSystemUtil
import LLBSwiftBuild
import NIO
import TSCBasic
import TSCLibc
import TSCUtility
import TSFCASFileTree
import llbuild2

struct SPMLLBTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [
            CASImport.self,
            SQL.self,
        ]
    )

    @OptionGroup()
    var options: Options

    @Option(name: .customLong("target"))
    var targets: [String] = []

    @Option()
    var rootID: String?

    @Flag()
    var disableFnCache: Bool = false

    func run() throws {
        let rootID: LLBDataID

        var ctx = Context()
        ctx.buildEventDelegate = self
        ctx.moduleCache = SharedModuleCache(options.sharedModuleCache)

        let packagePath = try options.getPackagePath()
        if let rootID_ = self.rootID.flatMap({ LLBDataID(string: $0) }) {
            rootID = rootID_
        } else {
            rootID = try importDir(path: packagePath, ctx)
        }
        print("root id:", rootID)

        let buildDir = try options.buildDir()
        let engine = try setupBuildEngine(buildDir: buildDir)

        let request = BuildRequest(
            rootID: rootID,
            targets: try self.targets.map { try LLBLabel($0) }
        )

        let startTime = Date()
        let result = try engine.build(request, as: BuildResult.self, ctx).wait()
        let endTime = Date().timeIntervalSince(startTime)
        print("Build duration: \(String(format: "%.2f", endTime))s")

        guard let executable = result.runnable else {
            throw StringError("expected runnable output from the target")
        }

        let resultsDir = buildDir.appending(component: "results")
        try? localFileSystem.removeFileTree(resultsDir)
        try localFileSystem.createDirectory(resultsDir, recursive: true)

        let exec = resultsDir.appending(component: "a.out")
        let db = try options.db()
        try LLBCASFileTree.export(
            executable,
            from: db,
            to: exec,
            ctx
        ).wait()
        print(try Process.checkNonZeroExit(arguments: [exec.pathString]))
    }

    func importDir(path: AbsolutePath, _ ctx: Context) throws -> LLBDataID {
        let db = try options.db()

        var opts = LLBCASFileTree.ImportOptions()
        opts.pathFilter = {
            if $0.hasPrefix("/.") {
                return false
            }
            return true
        }
        let progress = LLBCASFileTree.ImportProgressStats()

        return try LLBCASFileTree.import(
            path: path,
            to: db,
            options: opts,
            stats: progress,
            ctx
        ).wait()
    }

    func setupBuildEngine(buildDir: AbsolutePath) throws -> LLBBuildEngine {
        let group = options.group
        let db = try options.db()

        let fnCache = LLBFileBackedFunctionCache(
            group: group,
            path: buildDir.appending(component: "cache")
        )

        let executorDir = buildDir.appending(component: "local_exector")

        // Avoid re-using base output since the local executor currently
        // doesn't handle incremental source/input exports very well.
        let executionNum: Int
        let existingExecutionNum =
            (try? localFileSystem.getDirectoryContents(executorDir))?.compactMap { Int($0) }.sorted().last ?? -1
        executionNum = existingExecutionNum + 1

        let executor = LLBLocalExecutor(
            outputBase: buildDir.appending(components: "local_exector", "\(executionNum)"),
            delegate: self
        )

        let buildSystemDelegate = SwiftBuildSystemDelegate()

        return LLBBuildEngine(
            group: group,
            db: db,
            buildFunctionLookupDelegate: buildSystemDelegate,
            configuredTargetDelegate: buildSystemDelegate,
            ruleLookupDelegate: buildSystemDelegate,
            registrationDelegate: buildSystemDelegate,
            executor: executor,
            functionCache: disableFnCache ? nil : fnCache
        )
    }
}

extension SPMLLBTool: LLBLocalExecutorDelegate {
    func launchingProcess(
        arguments: [String],
        workingDir: AbsolutePath,
        environment: [String: String]
    ) {
    }

    func finishedProcess(with result: ProcessResult) {
        if result.exitStatus == .terminated(code: 0) { return }

        print("failed:", result.arguments.joined(separator: " "))
        let output = try? (result.utf8Output() + result.utf8stderrOutput())
        print(output ?? "", terminator: "")
    }
}

extension SPMLLBTool: LLBBuildEventDelegate {
    func targetEvaluationRequested(label: LLBLabel) {
        print("Evaluating \(label.targetName)")
    }

    func targetEvaluationCompleted(label: LLBLabel) {
    }

    func actionRequested(actionKey: LLBActionExecutionKey) {
        print(actionKey.command.mnemonic)
    }

    func actionCompleted(actionKey: LLBActionExecutionKey, result: LLBActionResult) {
    }
}

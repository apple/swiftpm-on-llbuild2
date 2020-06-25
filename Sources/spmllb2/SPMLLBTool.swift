// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import ArgumentParser
import NIO
import llbuild2
import LLBBuildSystem
import LLBBuildSystemUtil
import Foundation
import TSCBasic
import LLBSwiftBuild
import TSCLibc
import LLBCASFileTree

struct SPMLLBTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [
        ]
    )

    @OptionGroup()
    var options: Options

    @Option()
    var targets: [String] = []

    @Option()
    var rootID: String?

    @Flag()
    var disableFnCache: Bool = false

    func run() throws {
        let rootID: LLBDataID

        let packagePath = try options.getPackagePath()
        if let rootID_ = self.rootID.flatMap({ LLBDataID(string: $0) }) {
            rootID = rootID_
        } else {
            rootID = try importDir(path: packagePath)
        }
        print("root id:", rootID)

        let buildDir = try options.buildDir()
        let engine = try setupBuildEngine(buildDir: buildDir)

        let request = BuildRequest(
            rootID: rootID,
            targets: try self.targets.map{ try LLBLabel($0) }
        )

        let result = try engine.build(request, as: BuildResult.self).wait()
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
            to: exec
        ).wait()
        print(try Process.checkNonZeroExit(arguments: [exec.pathString]))
    }

    func importDir(path: AbsolutePath) throws -> LLBDataID {
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
            stats: progress
        ).wait()
    }

    func setupBuildEngine(buildDir: AbsolutePath) throws -> LLBBuildEngine {
        let group = options.group
        let db = try options.db()

        let fnCache = LLBFileBackedFunctionCache(
            group: group,
            path: buildDir.appending(component: "cache")
        )

        let executor = LLBLocalExecutor(
            outputBase: buildDir.appending(component: "outputs")
        )

        let engineContext = LLBBasicBuildEngineContext(
            group: group,
            db: db,
            executor: executor
        )
        let buildSystemDelegate = SwiftBuildSystemDelegate(
            engineContext: engineContext
        )

        return LLBBuildEngine(
            engineContext: engineContext,
            buildFunctionLookupDelegate: buildSystemDelegate,
            configuredTargetDelegate: buildSystemDelegate,
            ruleLookupDelegate: buildSystemDelegate,
            registrationDelegate: buildSystemDelegate,
            executor: executor,
            functionCache: disableFnCache ? nil : fnCache
        )
    }
}

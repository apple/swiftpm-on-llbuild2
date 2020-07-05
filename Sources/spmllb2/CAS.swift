// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import ArgumentParser
import TSCBasic
import TSCUtility
import TSFCAS
import TSFCASFileTree

struct CASImport: ParsableCommand {

    @OptionGroup()
    var options: Options

    func run() throws {
        let packagePath = try options.getPackagePath()
        let ctx = Context()

        let casDir = options.llbspm2Cache.appending(component: "cas")
        let db = LLBFileBackedCASDatabase(
            group: options.group,
            path: casDir.appending(component: "file-cas")
        )

        var opts = LLBCASFileTree.ImportOptions()
        opts.pathFilter = {
            if $0.hasPrefix("/.") {
                return false
            }
            return true
        }
        let progress = LLBCASFileTree.ImportProgressStats()

        let dataID = try LLBCASFileTree.import(
            path: packagePath,
            to: db,
            options: opts,
            stats: progress,
            ctx
        ).wait()
        print("imported \(dataID)")
    }
}

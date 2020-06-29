// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import ArgumentParser
import Foundation
import TSCBasic
import TSCUtility
import Workflow

struct DumpWorkflows: ParsableCommand {

    @Option()
    var moduleName: String = "ExampleWorkflows"

    @Option()
    var moduleDir: String?

    func run() throws {
        let fs = localFileSystem
        let cwd = fs.currentWorkingDirectory!

        let moduleDir = cwd.appending(components: ".build", "debug")

        let tool = SymbolGraphExtractTool()
        let graph = try tool.dumpSymbolGraph(
            moduleName: moduleName,
            moduleDirectory: moduleDir
        )

        let workflowConformers = graph.relationships.filter {
            $0.kind == "conformsTo" && $0.target == "s:8WorkflowAAP"
        }.map { $0.source }

        let workflows = graph.symbols.filter {
            // We only support structs.
            $0.kind.identifier == "swift.struct"
        }.filter {
            workflowConformers.contains($0.identifier.precise)
        }

        for workflow in workflows {
            let mangledName = String(workflow.identifier.precise.dropFirst(2))
            guard let workflowType = _typeByName(mangledName) as? WorkflowInstance.Type else {
                print("no workflow found for the mangled name")
                return
            }
            let data = workflowType.init()._data

            print(workflow.names.title, data)
        }
    }
}

struct SymbolGraph: Codable {
    struct Symbol: Codable {
        struct Kind: Codable {
            var identifier: String
        }

        struct Identifier: Codable {
            var precise: String
        }

        struct Names: Codable {
            var title: String
        }

        var kind: Kind
        var identifier: Identifier
        var names: Names
    }

    struct Relationship: Codable {
        var kind: String
        var source: String
        var target: String
    }

    var symbols: [Symbol]
    var relationships: [Relationship]
}

class SymbolGraphExtractTool {
    public func dumpSymbolGraph(
        moduleName: String,
        moduleDirectory: AbsolutePath
    ) throws -> SymbolGraph {
        var args = [String]()
        args += ["-module-name", moduleName]
        args += ["-target", "x86_64-apple-macosx10.15"]
        args += ["-I", moduleDirectory.pathString]
        args += ["-sdk", sdkRoot.pathString]
        args += ["--pretty-print"]
        args += ["--minimum-access-level=internal"]

        return try withTemporaryDirectory { tmpDir in
            args += ["--output-dir", tmpDir.pathString]
            try runTool(args)

            let symbolsFile = tmpDir.appending(component: "\(moduleName).symbols.json")
            let contents = try localFileSystem.readFileContents(symbolsFile)
            return try JSONDecoder().decode(SymbolGraph.self, from: Data(contents.contents))
        }
    }

    func runTool(_ args: [String]) throws {
        let arguments = ["swift", "symbolgraph-extract"] + args
        let process = Process(
            arguments: arguments,
            verbose: verbosity != .concise
        )
        try process.launch()
        try process.waitUntilExit()
    }
}

let swiftCompiler: AbsolutePath = {
    let string = try! Process.checkNonZeroExit(
        args: "xcrun", "--sdk", "macosx", "-f", "swiftc"
    ).spm_chomp()
    return AbsolutePath(string)
}()

let sdkRoot: AbsolutePath = {
    let string = try! Process.checkNonZeroExit(
        arguments: [
            "xcrun", "--sdk", "macosx", "--show-sdk-path",
        ]
    ).spm_chomp()
    return AbsolutePath(string)
}()

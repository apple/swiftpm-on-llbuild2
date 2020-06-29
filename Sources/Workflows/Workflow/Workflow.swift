// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

public protocol Workflow: WorkflowInstance {
    associatedtype Body: Workflow

    var body: Body { get }
}

extension Workflow {
    public var _data: [String: String] { body._data }
}

public protocol WorkflowInstance {
    init()
    var _data: [String: String] { get }
}

public struct ModifiedWorkflow<W: Workflow>: Workflow, PrimitiveWorkflow {
    public var body: W.Body { workflow.body }

    public init() {
        self.init(workflow: W(), key: "", value: "")
    }

    public var workflow: W

    public var _data: [String: String] = [:]

    public init(workflow: W, key: String, value: String) {
        self.workflow = workflow

        if let modifiedW = workflow as? ModifiedWorkflow {
            var data = modifiedW._data
            data[key] = value
            self._data = data
        } else {
            self._data = [key: value]
        }
    }
}

public struct WorkflowGroup {
    public var workflows: [String]

    public init() {
        workflows = []
    }
}

@_functionBuilder
public struct ArgumentBuilder {
    public static func buildBlock(_ arguments: String...) -> [String] {
        return arguments
    }
}

public struct Execute: Workflow, PrimitiveWorkflow {
    public init() {
        fatalError()
    }

    let outputs: [String]
    let args: [String]

    public init(
        outputs: [String] = [],
        @ArgumentBuilder argBuilder: () -> [String]
    ) {
        self.outputs = outputs
        self.args = argBuilder()
    }

    public var _data: [String: String] {
        [
            "output": outputs.joined(separator: " "),
            "args": args.joined(separator: " "),
        ]
    }
}

public struct Build: Workflow, PrimitiveWorkflow {
    public init() {
        self.init(labels: ["//..."])
    }

    public var labels: [String]

    public init(labels: [String]) {
        self.labels = labels
    }
}

extension Build {
    public enum Configuration {
        case debug
        case release
    }

    public func enableASAN(_ enable: Bool = true) -> Self {
        return self
    }

    public func enableMainThreadChecker(_ enable: Bool = true) -> Self {
        return self
    }

    public func config(_ config: Configuration) -> Self {
        return self
    }
}

public struct Test: Workflow, PrimitiveWorkflow {
    public init() {
        self.init(labels: ["//..."])
    }

    public var labels: [String]

    public init(labels: [String]) {
        self.labels = labels
    }
}

extension Test {
    public func skip(_ testSpecifier: String) -> Self {
        return self
    }
}

public struct Sandbox {
    public var path: String

    public init() {
        self.path = ""
    }
}

@propertyWrapper
public struct Input<InputType> {
    public var input: InputType

    public init(wrappedValue input: InputType) {
        self.input = input
    }

    public var wrappedValue: InputType {
        input
    }
}

public struct OutputArtifact {
    public var basename: String
    public var path: String

    public init<W: Workflow>(_ workflow: W.Type) {
        let path = "\(workflow)".lowercased()
        if path.hasPrefix("buildrelease") {
            self.path = "BestExec"
        } else if path.hasPrefix("build") {
            self.path = String(path.dropFirst(5))
        } else if path == "createtarball" {
            self.path = "BestExec.tar.gz"
        } else {
            self.path = path
        }
        basename = "BestExec"
    }
}

public protocol PrimitiveWorkflow: Workflow {}

extension PrimitiveWorkflow {
    public var body: Never { bodyError() }
    public var _data: [String: String] { [:] }
}

extension Never: Workflow {
    public init() {
        fatalError()
    }
    public var body: Never {
        fatalError()
    }

    public typealias Body = Never
}

extension PrimitiveWorkflow {
    func bodyError() -> Never {
        fatalError("body() should not be called on \(Self.self).")
    }
}

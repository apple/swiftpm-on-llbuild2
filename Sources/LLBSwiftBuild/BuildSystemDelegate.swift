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

public struct SwiftBuildSystemDelegate {
    let rules: [String: LLBRule] = [
        SPMTarget.identifier: SPMRule(),
    ]

    let functions: [LLBBuildKeyIdentifier: LLBFunction]

    public init(engineContext: LLBBuildEngineContext) {
        self.functions = [
            BuildRequest.identifier : BuildFunction(engineContext: engineContext)
        ]
    }
}

extension SwiftBuildSystemDelegate: LLBConfiguredTargetDelegate {
    public func configuredTarget(
        for key: LLBConfiguredTargetKey,
        _ fi: LLBBuildFunctionInterface
    ) throws -> LLBFuture<LLBConfiguredTarget> {
        let target = SPMTarget(
            packageName: "foo",
            name: key.label.targetName,
            sources: ["main.swift", "foo.swift"],
            dependencies: []
        )

        return fi.group.next().makeSucceededFuture(target)
    }
}

extension SwiftBuildSystemDelegate: LLBRuleLookupDelegate {
    public func rule(for configuredTargetType: LLBConfiguredTarget.Type) -> LLBRule? {
        rules[configuredTargetType.identifier]
    }
}

extension SwiftBuildSystemDelegate: LLBBuildFunctionLookupDelegate {
    public func lookupBuildFunction(for identifier: LLBBuildKeyIdentifier) -> LLBFunction? {
        functions[identifier]
    }
}

extension SwiftBuildSystemDelegate: LLBSerializableRegistrationDelegate {
    public func registerTypes(registry: LLBSerializableRegistry) {
        registry.register(type: SPMTarget.self)
    }
}

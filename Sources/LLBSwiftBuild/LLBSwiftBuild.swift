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

public struct BuildRequest: Codable, LLBBuildKey, Hashable {
    public var target: LLBLabel
    public var rootID: LLBDataID

    public init(rootID: LLBDataID, target: LLBLabel) {
        self.rootID = rootID
        self.target = target
    }
}

public struct BuildResult: LLBBuildValue, Codable {
    public let stdout: LLBDataID

    public init(stdout: LLBDataID) {
        self.stdout = stdout
    }
}

class BuildFunction: LLBBuildFunction<BuildRequest, BuildResult> {
    override func evaluate(
        key: BuildRequest,
        _ fi: LLBBuildFunctionInterface
    ) -> LLBFuture<BuildResult> {
        let configuredTargetKey = LLBConfiguredTargetKey(
            rootID: key.rootID,
            label: key.target
        )

        return fi.group.next().makeFailedFuture(StringError("unimplemented \(configuredTargetKey)"))
    }
}

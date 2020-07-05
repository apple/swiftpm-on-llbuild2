// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import ArgumentParser
import SQLite3
import TSCBasic
import TSCUtility
import TSFCAS
import TSFCASFileTree

struct SQL: ParsableCommand {
    func run() throws {

    }
}

public final class SQLite {

    public init() {

    }
}

public final class SQLiteCAS: LLBCASDatabase {
    public let group: LLBFuturesDispatchGroup
    let sqlite: SQLite

    public init(
        group: LLBFuturesDispatchGroup,
        sqlite: SQLite
    ) {
        self.group = group
        self.sqlite = sqlite
    }

    public func supportedFeatures() -> LLBFuture<LLBCASFeatures> {
        group.next().makeSucceededFuture(LLBCASFeatures(preservesIDs: true))
    }

    public func contains(
        _ id: LLBDataID,
        _ ctx: Context
    ) -> LLBFuture<Bool> {
        fatalError()
    }

    public func get(
        _ id: LLBDataID,
        _ ctx: Context
    ) -> LLBFuture<LLBCASObject?> {
        fatalError()
    }

    public func identify(
        refs: [LLBDataID],
        data: LLBByteBuffer,
        _ ctx: Context
    ) -> LLBFuture<LLBDataID> {
        fatalError()
    }

    public func put(
        knownID id: LLBDataID,
        refs: [LLBDataID],
        data: LLBByteBuffer,
        _ ctx: Context
    ) -> LLBFuture<LLBDataID> {
        fatalError()
    }

    public func put(
        refs: [LLBDataID],
        data: LLBByteBuffer,
        _ ctx: Context
    ) -> LLBFuture<LLBDataID> {
        let knownID = LLBDataID(blake3hash: data, refs: refs)
        return put(
            knownID: knownID,
            refs: refs,
            data: data,
            ctx
        )
    }
}

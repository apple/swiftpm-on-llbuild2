// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import LLBBuildSystem
import NIO
import PackageModel
import SwiftDriver
import TSCBasic
import llbuild2

public struct BaseTarget: Codable {
    var name: String
    var c99name: String
    var sources: [LLBArtifact]
    var dependencies: [LLBLabel]
}

public struct DefaultProvider: LLBProvider, Codable {
    public var targetName: String
    public var runnable: LLBArtifact?
    public var swiftmodule: LLBArtifact?
    public var cImportPaths: [LLBArtifact]
    public var objects: [LLBArtifact]
    public var outputs: [LLBArtifact]
}

extension LLBBuildFunctionInterface {
    func requestManifestLookup(_ packageID: LLBDataID, _ ctx: Context) -> LLBFuture<LLBDataID> {
        let req = ManifestLookupRequest(packageID: packageID)
        return request(req, as: ManifestLookupResult.self, ctx).map { $0.manifestID }
    }

    func requestManifest(
        _ manifestID: LLBDataID,
        packageIdentity: String,
        _ ctx: Context
    ) -> LLBFuture<Manifest> {
        let req = ManifestLoaderRequest(manifestDataID: manifestID, packageIdentity: packageIdentity)
        return request(req, as: ManifestLoaderResult.self, ctx).map { $0.manifest }
    }

    func request(_ key: ManifestLoaderRequest, _ ctx: Context) -> LLBFuture<ManifestLoaderResult> {
        request(key, as: ManifestLoaderResult.self, ctx)
    }
}

extension EventLoopFuture {
    func unwrapOptional<T>(orError error: Swift.Error) -> EventLoopFuture<T> where Value == T? {
        self.flatMapThrowing { value in
            guard let value = value else {
                throw error
            }
            return value
        }
    }

    func unwrapOptional<T>(orStringError error: String) -> EventLoopFuture<T> where Value == T? {
        unwrapOptional(orError: StringError(error))
    }
}

func darwinSDKPath() throws -> AbsolutePath? {
    let result = try Process.checkNonZeroExit(
        args: "xcrun", "-sdk", "macosx", "--show-sdk-path"
    ).spm_chomp()
    return AbsolutePath(result)
}

func sdkPlatformFrameworkPaths(
    environment: [String: String] = ProcessEnv.vars
) -> (fwk: AbsolutePath, lib: AbsolutePath)? {
    if let path = _sdkPlatformFrameworkPath {
        return path
    }
    let platformPath = try? Process.checkNonZeroExit(
        arguments: ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-platform-path"],
        environment: environment
    ).spm_chomp()

    if let platformPath = platformPath, !platformPath.isEmpty {
        // For XCTest framework.
        let fwk = AbsolutePath(platformPath).appending(
            components: "Developer", "Library", "Frameworks")

        // For XCTest Swift library.
        let lib = AbsolutePath(platformPath).appending(
            components: "Developer", "usr", "lib")

        _sdkPlatformFrameworkPath = (fwk, lib)
    }
    return _sdkPlatformFrameworkPath
}
fileprivate var _sdkPlatformFrameworkPath: (fwk: AbsolutePath, lib: AbsolutePath)? = nil

extension LLBArtifact {
    var pathRel: RelativePath {
        RelativePath(path)
    }

    var shortPathRel: RelativePath {
        RelativePath(shortPath)
    }
}

extension Array where Element == LLBArtifact {
    func first(_ virtualPath: VirtualPath) -> LLBArtifact? {
        self.first(where: { $0.path == virtualPath.name })
    }
}

extension TypedVirtualPath {
    func toLLBArtifact(
        ruleContext: LLBRuleContext,
        tmpDir: LLBArtifact,
        inputArtifacts: [LLBArtifact]
    ) throws -> LLBArtifact {
        if let inputArtifact = inputArtifacts.first(file) {
            return inputArtifact
        }

        let artifactPrefix = ruleContext.outputsDirectory

        switch file {
        case .relative(let file):
            var filePathString = file.pathString
            // The paths created by driver will already have the artifact roots applied so remove them.
            if file.pathString.hasPrefix(artifactPrefix) {
                filePathString.removeFirst(artifactPrefix.count + 1)
            }

            return try ruleContext.declareArtifact(filePathString)

        case .temporary(let file):
            return try ruleContext.declareArtifact(tmpDir.shortPathRel.appending(file).pathString)

        case .absolute:
            throw StringError("unexpected virtual file with absolute path \(self)")
        case .standardInput, .standardOutput:
            fatalError("unexpected stdin/stdout virtual file \(self)")
        }
    }
}

public struct SharedModuleCache {
    public var path: AbsolutePath

    public init(_ path: AbsolutePath) {
        self.path = path
    }
}

extension Context {
    public var moduleCache: SharedModuleCache? {
        get {
            self.getOptional(Optional<SharedModuleCache>.self).flatMap { $0 }
        }
        set {
            self.set(newValue)
        }
    }
}

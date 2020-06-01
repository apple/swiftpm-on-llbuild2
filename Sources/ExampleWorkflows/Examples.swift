// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Workflow

struct SwiftBuild: Workflow {
    var body: some Workflow {
        Build()
            .enableMainThreadChecker()
    }
}

struct SwiftTest: Workflow {
    var body: some Workflow {
        Test()
            .skip("SomeTest")
            .skip("SomeOtherTest")
    }
}

struct BuildASAN: Workflow {
    var body: some Workflow {
        Build()
            .enableASAN()
    }
}

struct BuildRelease: Workflow {
    var body: some Workflow {
        Build()
            .enableMainThreadChecker()
            .config(.release)
    }
}

struct CreateTarball: Workflow {
    @Input var bestApp: OutputArtifact = .init(BuildRelease.self)

    @Input var sandbox: Sandbox = .init()

    var tarballPath: String {
        sandbox.path + "/" + bestApp.basename + ".tar.gz"
    }

    var body: some Workflow {
        Execute(outputs: [tarballPath]) {
            "tar"
            "zcvf"
            tarballPath
            bestApp.path
        }
    }
}

struct BuildPublishTool: Workflow {
    var body: some Workflow {
        Build(labels: ["some-tool"])
    }
}

struct Publish: Workflow {
    @Input var publishTool: OutputArtifact = .init(BuildPublishTool.self)
    @Input var tarball: OutputArtifact = .init(CreateTarball.self)

    var body: some Workflow {
        Execute {
            publishTool.path
            "bestapp"
            "--path"
            tarball.path
            "--version"
            "next"
        }
    }
}

# Workflow

SwiftPM Workflow is a feature for writing composable ad-hoc project-specific
actions. The idea is to provide a framework for configuring how a build is
produced and transforming the build outputs using custom operations.

Note that this concept is orthogonal to [extensible build
tools](https://github.com/aciidb0mb3r/swift-evolution/blob/extensible-tool/proposals/NNNN-package-manager-extensible-tools.md)
which aims to support user-defined build tools that are executed during the
build itself.

## Prototype

This package contains a barebones prototype of this concept. Install a recent
Swift.org trunk snapshot and run `swift run spm-workflow dump-workflows` to see
it in action.

## Examples

Workflows are written using existing built-in workflows provided by the `Workflow`
module. In this world, `swift build` and `swift test` are implicit workflows
that can be customized by if desired:

```swift
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
```

One might want to write additional workflows to build in a particular
configuration:

```swift
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
```

Workflows can act as input to other workflows. For example, it's quite common to
create a tarball for release:

```swift
struct CreateTarball: Workflow {
    /// We're going to use the BuildRelease workflow as the input to the tarball workflow.
    @Input var bestApp: OutputArtifact = .init(BuildRelease.self)

    /// We also request a sandbox directory where we can stage intermediate files.
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
```

Imagine there's a tool in the package that can be used to deploy the tarball to
some server. We can express that we want to build the tool and publish the
previously declared tarball using the tool:

```swift
struct BuildPublishTool: Workflow {
    var body: some Workflow {
        Build(target: ["some-publish-tool"])
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
```

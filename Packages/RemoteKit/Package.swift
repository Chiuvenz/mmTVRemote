// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RemoteKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RemoteCore", targets: ["RemoteCore"]),
        .library(name: "RemoteRuntime", targets: ["RemoteRuntime"]),
    ],
    targets: [
        .target(name: "RemoteCore"),
        .target(name: "RemoteRuntime", dependencies: ["RemoteCore"]),
        .testTarget(name: "RemoteCoreTests", dependencies: ["RemoteCore"]),
        .testTarget(name: "RemoteRuntimeTests", dependencies: ["RemoteCore", "RemoteRuntime"]),
    ]
)

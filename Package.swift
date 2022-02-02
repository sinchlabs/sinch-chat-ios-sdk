// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SinchChatSDK",
    defaultLocalization: "en",
    platforms: [.iOS(.v11)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SinchChatSDK",
            targets: ["SinchChatSDK"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(name: "Connectivity", url: "https://github.com/rwbutler/connectivity", from: "5.0.0"),
        .package(name: "grpc-swift", url: "https://github.com/grpc/grpc-swift.git", from: "1.6.1"),
        .package(name: "Kingfisher", url: "https://github.com/onevcat/Kingfisher.git", branch: "version6-xcode13")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "SinchChatSDK",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "Connectivity", package: "Connectivity")
            ]),
        .testTarget(
            name: "SinchChatSDKTests",
            dependencies: ["SinchChatSDK"])
    ],
    swiftLanguageVersions: [.v5]
)

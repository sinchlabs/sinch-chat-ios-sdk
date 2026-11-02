// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package.init(
    name: "SinchChatSDK",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v13)],
    products: [
        .library(name: "SinchChatSDK", targets: ["SinchChatSDK"]),
        // For a Notification Service Extension target only: no UIKit, no third-party dependencies.
        .library(name: "SinchChatSDKNotificationExtension", targets: ["SinchChatSDKNotificationExtension"])
    ],
    dependencies: [
        // Local during development.
        .package(url: "https://github.com/sinchlabs/sinch-push-ios-sdk.git", from: "1.1.0"),
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.4.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.9.0")
    ],
    targets: [
        // Kept for source compatibility: it only re-exports the push extension.
        .target(
            name: "SinchChatSDKNotificationExtension",
            dependencies: [.product(name: "SinchPushSDKNotificationExtension", package: "sinch-push-ios-sdk")]
        ),
        .target(
                        name: "SinchChatSDK",
                        dependencies: [
                            "SinchChatSDKNotificationExtension",
                            .product(name: "SinchPushSDK", package: "sinch-push-ios-sdk"),
                            .product(name: "GRPCCore", package: "grpc-swift-2"),
                            .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                            .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
                            .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                            .product(name: "Kingfisher", package: "Kingfisher")
                        ],
                        resources: [
                            .process("record.wav")]
                    ),
        .testTarget(
            name: "SinchChatSDKTests",
            dependencies: ["SinchChatSDK"],
            path: "Tests/SinchChatSDKTests"
        )
    ],
    swiftLanguageModes: [.v6]
)

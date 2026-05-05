// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
//  Generated file. Do not edit.
//

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])
    ],
    dependencies: [
        .package(name: "url_launcher_macos", path: "../.packages/url_launcher_macos"),
        .package(name: "sqflite_darwin", path: "../.packages/sqflite_darwin"),
        .package(name: "shared_preferences_foundation", path: "../.packages/shared_preferences_foundation"),
        .package(name: "path_provider_foundation", path: "../.packages/path_provider_foundation"),
        .package(name: "file_selector_macos", path: "../.packages/file_selector_macos"),
        .package(name: "geolocator_apple", path: "../.packages/geolocator_apple")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "url-launcher-macos", package: "url_launcher_macos"),
                .product(name: "sqflite-darwin", package: "sqflite_darwin"),
                .product(name: "shared-preferences-foundation", package: "shared_preferences_foundation"),
                .product(name: "path-provider-foundation", package: "path_provider_foundation"),
                .product(name: "file-selector-macos", package: "file_selector_macos"),
                .product(name: "geolocator-apple", package: "geolocator_apple")
            ]
        )
    ]
)

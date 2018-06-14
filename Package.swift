// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "Growth",
    products: [
        .library(name: "Growth", targets: ["Growth"]),
        .executable(name: "GrowthExample", targets: ["GrowthExample"])
    ],
    dependencies: [],
    targets: [
        .target(name: "Growth", dependencies: [], path: "./Sources"),
        .target(name: "GrowthExample", dependencies: ["Growth"], path: "./GrowthExample")
    ]
)

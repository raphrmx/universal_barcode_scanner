// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to
// build this package.

import Foundation
import PackageDescription

// Flutter 3.44 and later vend the Flutter framework as a package of its own,
// next to this one among the app's packages, and ask plugins to depend on it.
// Earlier versions have no such package, and a dependency on it would stop
// them resolving the app's packages at all: it is declared only where it is.
let hasFlutterFramework = FileManager.default.fileExists(
  atPath: URL(fileURLWithPath: Context.packageDirectory)
    .deletingLastPathComponent()
    .appendingPathComponent("FlutterFramework")
    .path
)

let flutterFrameworkPackage: [Package.Dependency] =
  hasFlutterFramework
  ? [.package(name: "FlutterFramework", path: "../FlutterFramework")]
  : []

let flutterFrameworkProduct: [Target.Dependency] =
  hasFlutterFramework
  ? [.product(name: "FlutterFramework", package: "FlutterFramework")]
  : []

let package = Package(
  name: "universal_barcode_scanner",
  platforms: [
    .iOS("12.0")
  ],
  products: [
    .library(
      name: "universal-barcode-scanner",
      targets: ["universal_barcode_scanner"]
    )
  ],
  dependencies: flutterFrameworkPackage,
  targets: [
    .target(
      name: "universal_barcode_scanner",
      dependencies: flutterFrameworkProduct
    )
  ]
)

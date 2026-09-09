// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to
// build this package.

import PackageDescription

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
  dependencies: [],
  targets: [
    .target(
      name: "universal_barcode_scanner",
      dependencies: [],
      resources: [
        // The flash and camera icons. Under Swift Package Manager they land in
        // Bundle.module, which is why the code asks for the bundle rather than
        // naming one.
        .process("Resources")
      ]
    )
  ]
)

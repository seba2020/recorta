// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Recorta", platforms: [.macOS(.v14)], products: [.executable(name: "Recorta", targets: ["Recorta"])], targets: [.executableTarget(name: "Recorta")])

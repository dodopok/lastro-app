// swift-tools-version: 6.2
// Domínio do Lastro: modelos, dinheiro, contas do mês, cores. Sem UIKit/SwiftUI,
// para rodar os testes rápido (e no Linux, se precisar).
import PackageDescription

let package = Package(
    name: "LastroKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LastroKit", targets: ["LastroKit"]),
    ],
    targets: [
        .target(name: "LastroKit"),
        .testTarget(name: "LastroKitTests", dependencies: ["LastroKit"]),
    ]
)

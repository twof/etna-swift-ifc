// swift-tools-version: 6.2
import PackageDescription

// PropertyTestingKit requires the patched Swift toolchain (parameter packs) and
// macOS 26. Build via ./scripts/swift-toolchain.sh, not system `swift`.
//
// `-sanitize-coverage=edge,pc-table` instruments the code under test so PTK's
// SanCovHooks can observe edge coverage; `-sanitize=undefined` matches PTK's own
// build. Any product linking the instrumented `IFC` module must also link PTK
// (which provides the SanitizerCoverage callbacks).
let sanitize: [SwiftSetting] = [
    .unsafeFlags(["-sanitize=undefined", "-sanitize-coverage=edge,pc-table"])
]

let package = Package(
    name: "etna-swift-ifc",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ifc", targets: ["Solve"]),
        .executable(name: "ifc-sampler", targets: ["ifc-sampler"]),
        .executable(name: "ifc-oracle", targets: ["ifc-oracle"]),
    ],
    dependencies: [
        .package(path: "../PropertyTestingKit"),
    ],
    targets: [
        // System under test: the IFC abstract machine (labels, rules, exec),
        // indistinguishability, the table mutator, the SSNI spec, and the wire
        // (de)serializer. Instrumented for coverage.
        .target(
            name: "IFC",
            swiftSettings: sanitize
        ),
        // PTK-backed bespoke variation generator + coverage-guided strategy.
        .target(
            name: "IFCGen",
            dependencies: [
                "IFC",
                .product(name: "PropertyTestingKit", package: "PropertyTestingKit"),
            ],
            swiftSettings: sanitize
        ),
        // The `ifc` solve binary (ETNA `solve`). Dir is `Solve` to avoid a
        // case-insensitive filesystem clash with the `IFC` library.
        .executableTarget(
            name: "Solve",
            dependencies: ["IFCGen"],
            swiftSettings: sanitize
        ),
        .executableTarget(
            name: "ifc-sampler",
            dependencies: ["IFCGen"],
            swiftSettings: sanitize
        ),
        // Differential-oracle helper: emits a variation corpus + SSNI verdicts
        // (clean + every mutant table) for cross-checking against the Coq
        // reference.
        .executableTarget(
            name: "ifc-oracle",
            dependencies: [
                "IFCGen",
                .product(name: "PropertyTestingKit", package: "PropertyTestingKit"),
            ],
            swiftSettings: sanitize
        ),
        .testTarget(
            name: "IFCTests",
            dependencies: [
                "IFC",
                "IFCGen",
                .product(name: "PropertyTestingKit", package: "PropertyTestingKit"),
            ],
            swiftSettings: sanitize
        ),
    ]
)

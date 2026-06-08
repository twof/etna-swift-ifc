import Foundation
import IFCGen

// ETNA `sample` entry point: print `count` generated variations (wire form),
// one per line, prefixed with generation time in ns.
let args = CommandLine.arguments
let count = args.count >= 2 ? (Int(args[1]) ?? 100) : 100
for (ns, wire) in sample(count: count) {
    print("\(ns)\t\(wire)")
}

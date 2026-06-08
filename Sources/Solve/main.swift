import Foundation
import IFC
import IFCGen

// ETNA `solve` entry point.
//   ifc <strategy> <property> [duration_seconds] [mutant_index]
// strategy is "ptk"; property is "SSNI"; mutant_index selects a table from
// mutateTable (omitted/"clean" -> the clean default table). Prints result JSON.
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: ifc <strategy> <property> [seconds] [mutant]\n".utf8))
    exit(2)
}
let property = args[2]
let seconds = args.count >= 4 ? (Double(args[3]) ?? 10) : 10
let mutant: Int? = args.count >= 5 ? Int(args[4]) : nil

do {
    let outcome = try await solve(
        property: property,
        mutant: mutant,
        duration: .nanoseconds(Int(seconds * 1_000_000_000)))
    print(outcome.json)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

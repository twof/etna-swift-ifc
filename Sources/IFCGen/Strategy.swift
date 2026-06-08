import IFC
import PropertyTestingKit
import Foundation
import os

/// Thrown by the fuzz closure when SSNI fails; carries the failing variation in
/// wire form so `solve` can report it as the counterexample.
struct PropertyViolation: Error { let wire: String }

/// Outcome of one solve run, shaped for ETNA's result JSON.
public struct SolveOutcome: Sendable {
    public let status: String          // "passed" | "failed" | "aborted"
    public let tests: Int
    public let discards: Int
    public let counterexample: String?
    public let error: String?
    public let timeNs: UInt64

    public init(status: String, tests: Int, discards: Int, counterexample: String?, error: String?, timeNs: UInt64) {
        self.status = status
        self.tests = tests
        self.discards = discards
        self.counterexample = counterexample
        self.error = error
        self.timeNs = timeNs
    }
}

private func jsonEscape(_ s: String) -> String {
    var out = ""
    for c in s {
        switch c {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case "\r": out += "\\r"
        default: out.append(c)
        }
    }
    return out
}

extension SolveOutcome {
    public var json: String {
        let cex = counterexample.map { "\"\(jsonEscape($0))\"" } ?? "null"
        let err = error.map { "\"\(jsonEscape($0))\"" } ?? "null"
        return """
        {"status":"\(status)","tests":\(tests),"discards":\(discards),"counterexample":\(cex),"error":\(err),"time":"\(timeNs)ns","execution_time":null,"generation_time":null,"shrinking_time":null}
        """
    }
}

/// Parallel fuzz engines (default: core count). The stop-at-first-counterexample
/// plugin halts the finding engine and PTK cancels its siblings, so `solve` still
/// returns at the first counterexample with time-to-find. Override with
/// `IFC_PARALLELISM`.
let enginesParallelism: Int = {
    if let v = ProcessInfo.processInfo.environment["IFC_PARALLELISM"], let n = Int(v), n > 0 { return n }
    return ProcessInfo.processInfo.processorCount
}()

private func runFuzz(
    duration: Duration,
    check: @escaping @Sendable (Variation) -> Bool?
) async -> SolveOutcome {
    let discards = OSAllocatedUnfairLock(initialState: 0)
    let start = DispatchTime.now()
    func elapsed() -> UInt64 { DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds }

    do {
        let result = try await fuzz(
            duration: duration,
            persistence: .ephemeral,
            parallelism: enginesParallelism,
            plugins: { [.corpusMutation(), .stopOnFirstFailure(reason: .custom("counterexample_found"))] }
        ) { (input: Variation) in
            switch check(input) {
            case .some(false): throw PropertyViolation(wire: wireVariation(input))
            case .none: discards.withLock { $0 += 1 }
            case .some(true): break
            }
        }
        return SolveOutcome(status: "passed", tests: result.stats.totalInputs,
                            discards: discards.withLock { $0 }, counterexample: nil, error: nil, timeNs: elapsed())
    } catch let e as FuzzError {
        guard case let .testFailed(_, underlying, _, stats) = e else {
            return SolveOutcome(status: "aborted", tests: 0, discards: discards.withLock { $0 },
                                counterexample: nil, error: "\(e)", timeNs: elapsed())
        }
        return SolveOutcome(status: "failed", tests: stats.totalInputs,
                            discards: discards.withLock { $0 },
                            counterexample: (underlying as? PropertyViolation)?.wire, error: nil, timeNs: elapsed())
    } catch {
        return SolveOutcome(status: "aborted", tests: 0, discards: discards.withLock { $0 },
                            counterexample: nil, error: "\(error)", timeNs: elapsed())
    }
}

public enum SolveError: Error { case unknownProperty(String), badMutant(Int) }

/// Coverage-guided solve: search for a variation that breaks `property` under the
/// given table. `mutant` selects a table from `mutateTable` (nil → clean).
public func solve(property: String, mutant: Int?, duration: Duration) async throws -> SolveOutcome {
    guard property == "SSNI" else { throw SolveError.unknownProperty(property) }
    let table: Table
    if let m = mutant {
        guard m >= 0 && m < ifcMutants.count else { throw SolveError.badMutant(m) }
        table = ifcMutants[m]
    } else {
        table = defaultTable
    }
    return await runFuzz(duration: duration, check: { propSSNI(table, $0) })
}

// MARK: - Sampling (cross-language `sample` capability)

public func sample(count: Int) -> [(timeNs: UInt64, wire: String)] {
    var rng = FastRNG()
    var out: [(UInt64, String)] = []
    out.reserveCapacity(count)
    for _ in 0..<count {
        let start = DispatchTime.now()
        let w = wireVariation(genVariation(&rng))
        let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        out.append((ns, w))
    }
    return out
}

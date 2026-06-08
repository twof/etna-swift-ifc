// Port of the QuickChick `ifc-basic` reference's SSNI property (`Driver.v`).
//
// A Variation is a pair of machine states that agree on low-labelled data. SSNI
// ("single-step non-interference") says: stepping both states under table `t`
// preserves indistinguishability at the attacker's level. A mutant that leaks
// information yields a variation whose successors disagree on low data.

public struct Variation: Sendable, Equatable, Hashable, Codable {
    public var st1: State
    public var st2: State
    public init(_ st1: State, _ st2: State) {
        self.st1 = st1
        self.st2 = st2
    }
}

// SSNI as a partial predicate: `nil` means the variation is rejected/discarded
// (not indistinguishable to begin with, no instruction, or a required step
// faulted); `true`/`false` is the indistinguishability verdict after stepping.
public func propSSNI(_ t: Table, _ v: Variation) -> Bool? {
    let st1 = v.st1, st2 = v.st2
    let l1 = st1.pc.label, l2 = st2.pc.label

    guard lookupInstr(st1) != nil else { return nil }
    guard indistState(st1, st2) else { return nil }

    switch (l1, l2) {
    case (.L, .L):
        guard let st1p = exec(t, st1), let st2p = exec(t, st2) else { return nil }
        return indistState(st1p, st2p)

    case (.H, .H):
        guard let st1p = exec(t, st1), let st2p = exec(t, st2) else { return nil }
        if isAtomLow(st1p.pc) && isAtomLow(st2p.pc) {
            return indistState(st1p, st2p)
        } else if isAtomLow(st1p.pc) {
            return indistState(st2, st2p)
        } else {
            return indistState(st1, st1p)
        }

    case (.H, _):   // (H, L)
        guard let st1p = exec(t, st1) else { return nil }
        return indistState(st1, st1p)

    case (_, .H):   // (L, H)
        guard let st2p = exec(t, st2) else { return nil }
        return indistState(st2, st2p)
    }
}

// The full 20-element mutant table list for the standard machine.
public let ifcMutants: [Table] = mutateTable(defaultTable)

public let ifcProperties = ["SSNI"]

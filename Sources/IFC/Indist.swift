// Port of the QuickChick `ifc-basic` reference's `Indist.v` (the boolean
// `indist` instances). Two states are indistinguishable at the attacker level
// when they agree on all low-labelled data; high-labelled data may differ.

@usableFromInline
func indistAtom(_ a1: Atom, _ a2: Atom) -> Bool {
    switch (a1.label, a2.label) {
    case (.L, .L): return a1.value == a2.value
    case (.H, .H): return true
    default: return false
    }
}

@usableFromInline
func indistMem(_ m1: [Atom], _ m2: [Atom]) -> Bool {
    guard m1.count == m2.count else { return false }
    for (x, y) in zip(m1, m2) where !indistAtom(x, y) { return false }
    return true
}

// Drop everything above (and including) the first low return-frame marker.
@usableFromInline
func cropTop(_ s: Stack) -> Stack {
    switch s {
    case .mty: return .mty
    case .cons(_, let s2): return cropTop(s2)
    case .retCons(let a, let s2):
        switch a.label {
        case .H: return cropTop(s2)
        case .L: return s
        }
    }
}

// Assumes stacks have been cropTopped.
@usableFromInline
func indistStack(_ s1: Stack, _ s2: Stack) -> Bool {
    switch (s1, s2) {
    case (.cons(let a1, let r1), .cons(let a2, let r2)):
        return indistAtom(a1, a2) && indistStack(r1, r2)
    case (.retCons(let a1, let r1), .retCons(let a2, let r2)):
        return indistAtom(a1, a2) && indistStack(r1, r2)
    case (.mty, .mty): return true
    default: return false
    }
}

public func indistState(_ st1: State, _ st2: State) -> Bool {
    guard indistMem(st1.mem, st2.mem) else { return false }
    guard indistAtom(st1.pc, st2.pc) else { return false }
    let (s1, s2): (Stack, Stack)
    switch st1.pc.label {
    case .H: (s1, s2) = (cropTop(st1.stack), cropTop(st2.stack))
    case .L: (s1, s2) = (st1.stack, st2.stack)
    }
    return indistStack(s1, s2)
}

@inlinable
public func isAtomLow(_ a: Atom) -> Bool { a.label == .L }

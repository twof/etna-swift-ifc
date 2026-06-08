import IFC
import PropertyTestingKit

// Port of the QuickChick `ifc-basic` reference's `Generation.v`: the bespoke
// generator that builds a Variation (a pair of low-equivalent machine states)
// by generating one state and then "varying" its high-labelled data. This is
// the analogue of the type-directed generators in the STLC / Fsub workloads:
// it produces inputs that pass SSNI's indistinguishability precondition by
// construction, so almost nothing is discarded.

// freq_: weighted choice. Returns the index of the chosen branch (or -1 when all
// weights are 0). Returns an index rather than calling a closure so generators
// keep `inout rng` out of escaping closures.
@usableFromInline
func freqIndex(_ weights: [Int], using rng: inout FastRNG) -> Int {
    let total = weights.reduce(0) { $0 + max(0, $1) }
    if total <= 0 { return -1 }
    var pick = Int.random(in: 0..<total, using: &rng)
    for (i, w) in weights.enumerated() where w > 0 {
        pick -= w
        if pick < 0 { return i }
    }
    return -1
}

@usableFromInline
func genZ(_ rng: inout FastRNG) -> Int { Int.random(in: 0...1, using: &rng) }

@usableFromInline
func genLabel(_ rng: inout FastRNG) -> Label { Bool.random(using: &rng) ? .L : .H }

@usableFromInline
func genAtom(_ rng: inout FastRNG) -> Atom { Atom(genZ(&rng), genLabel(&rng)) }

@usableFromInline
func genMemory(_ rng: inout FastRNG) -> [Atom] { (0..<2).map { _ in genAtom(&rng) } }

func stackLength(_ s: Stack) -> Int {
    switch s {
    case .cons(_, let s2): return 1 + stackLength(s2)
    default: return 0
    }
}

func containsRet(_ s: Stack) -> Bool {
    switch s {
    case .retCons: return true
    case .cons(_, let s2): return containsRet(s2)
    default: return false
    }
}

// ainstr: generate one instruction, weighted as in Generation.v (Store is
// heavily favoured; BCall/BRet are gated on stack shape).
func ainstr(_ st: State, _ rng: inout FastRNG) -> Instruction {
    let sl = stackLength(st.stack)
    let hasRet = containsRet(st.stack)
    let weights = [1, 10, 10, hasRet ? 10 : 0, 10, 10, 100]
    switch freqIndex(weights, using: &rng) {
    case 1: return .push(genZ(&rng))
    case 2: return sl == 0 ? .bcall(0) : .bcall(Int.random(in: 0...(sl - 1), using: &rng))
    case 3: return .bret
    case 4: return .add
    case 5: return .load
    case 6: return .store
    default: return .nop
    }
}

func genStack(_ n: Int, _ onlyLow: Bool, _ rng: inout FastRNG) -> Stack {
    if n == 0 { return .mty }
    switch freqIndex([10, 4], using: &rng) {
    case 0:
        return .cons(genAtom(&rng), genStack(n - 1, onlyLow, &rng))
    case 1:
        let pc = genAtom(&rng)
        return .retCons(pc, genStack(n - 1, isAtomLow(pc), &rng))
    default:
        return .mty
    }
}

public func genState(_ rng: inout FastRNG) -> State {
    let imem0: [Instruction] = [.nop, .nop]
    let pc = genAtom(&rng)
    let mem = genMemory(&rng)
    let stk = genStack(4, isAtomLow(pc), &rng)
    let i = ainstr(State(imem: imem0, mem: mem, stack: stk, pc: pc), &rng)
    return State(imem: [i, i], mem: mem, stack: stk, pc: pc)
}

// ---- Varying: produce a low-equivalent partner state ----

func varyAtom(_ a: Atom, _ rng: inout FastRNG) -> Atom {
    switch a.label {
    case .L: return a
    case .H: return Atom(genZ(&rng), .H)
    }
}

func varyMem(_ m: [Atom], _ rng: inout FastRNG) -> [Atom] {
    m.map { varyAtom($0, &rng) }
}

func varyStack(_ s: Stack, _ isLow: Bool, _ rng: inout FastRNG) -> Stack {
    switch s {
    case .cons(let a, let s2):
        if isLow {
            return .cons(varyAtom(a, &rng), varyStack(s2, isLow, &rng))
        } else {
            return .cons(genAtom(&rng), varyStack(s2, isLow, &rng))
        }
    case .retCons(let a, let s2):
        switch a.label {
        case .L: return .retCons(a, varyStack(s2, true, &rng))
        case .H: return .retCons(varyAtom(a, &rng), varyStack(s2, false, &rng))
        }
    case .mty:
        return .mty
    }
}

public func varyState(_ st: State, _ rng: inout FastRNG) -> State {
    let mem2 = varyMem(st.mem, &rng)
    let pc2 = varyAtom(st.pc, &rng)
    let isLow = st.pc.label == .L
    if isLow {
        let stk2 = varyStack(st.stack, true, &rng)
        return State(imem: st.imem, mem: mem2, stack: stk2, pc: pc2)
    } else {
        let stk2 = varyStack(st.stack, false, &rng)
        let extra = genAtom(&rng)
        return State(imem: st.imem, mem: mem2, stack: .cons(extra, stk2), pc: pc2)
    }
}

public func genVariation(_ rng: inout FastRNG) -> Variation {
    let st = genState(&rng)
    let st2 = varyState(st, &rng)
    return Variation(st, st2)
}

// ---- Deterministic vary, for `mutate` (which gets no RNG) ----
//
// A genuine SSNI witness needs st1 and st2 to *differ* on high data (if they were
// identical, both steps would coincide and SSNI could never fail). `varyDet`
// builds a low-equivalent partner that flips every high atom's value, so a
// mutated `st1` always yields a non-trivial, indistinguishable variation.

private func flipH(_ a: Atom) -> Atom { a.label == .H ? Atom(1 - a.value, .H) : a }

private func varyStackDet(_ s: Stack) -> Stack {
    switch s {
    case .mty: return .mty
    case .cons(let a, let s2): return .cons(flipH(a), varyStackDet(s2))
    case .retCons(let a, let s2): return .retCons(flipH(a), varyStackDet(s2))
    }
}

func varyDet(_ st: State) -> State {
    let mem2 = st.mem.map(flipH)
    let pc2 = flipH(st.pc)
    let stk2 = varyStackDet(st.stack)
    if st.pc.label == .H {
        return State(imem: st.imem, mem: mem2, stack: .cons(Atom(0, .L), stk2), pc: pc2)
    } else {
        return State(imem: st.imem, mem: mem2, stack: stk2, pc: pc2)
    }
}

// Structural neighbours of a variation: swap the executed instruction, flip a
// label, or tweak a value — each re-paired with `varyDet` to stay a valid
// low-equivalent variation.
func mutateVariation(_ v: Variation) -> [Variation] {
    let s = v.st1
    var states: [State] = []

    let instrs: [Instruction] = [.nop, .push(0), .push(1), .add, .load, .store, .bret, .bcall(0)]
    for i in instrs {
        states.append(State(imem: [i, i], mem: s.mem, stack: s.stack, pc: s.pc))
    }
    // PC label flip.
    states.append(State(imem: s.imem, mem: s.mem, stack: s.stack,
                        pc: Atom(s.pc.value, s.pc.label == .L ? .H : .L)))
    // Memory tweaks: flip each cell's label, and flip its value.
    for idx in s.mem.indices {
        var m1 = s.mem; m1[idx] = Atom(m1[idx].value, m1[idx].label == .L ? .H : .L)
        states.append(State(imem: s.imem, mem: m1, stack: s.stack, pc: s.pc))
        var m2 = s.mem; m2[idx] = Atom(1 - m2[idx].value, m2[idx].label)
        states.append(State(imem: s.imem, mem: m2, stack: s.stack, pc: s.pc))
    }
    // Top-of-stack tweaks.
    if case .cons(let a, let rest) = s.stack {
        states.append(State(imem: s.imem, mem: s.mem,
                            stack: .cons(Atom(a.value, a.label == .L ? .H : .L), rest), pc: s.pc))
        states.append(State(imem: s.imem, mem: s.mem,
                            stack: .cons(Atom(1 - a.value, a.label), rest), pc: s.pc))
    }
    return states.map { Variation($0, varyDet($0)) }
}

// MARK: - MutatorProviding conformance + seeds

extension Variation: MutatorProviding {
    public static var defaultMutator: Mutator<Variation> {
        Mutator(
            seeds: ifcSeeds,
            mutate: { mutateVariation($0) },
            generate: { genVariation(&$0) }
        )
    }
}

// A small set of indistinguishable starting variations (low-equal pair differing
// only on a high stack cell) over each executable instruction. The documented
// store example from the reference's `Driver.v` is the first.
public let ifcSeeds: [Variation] = {
    func pair(_ i: Instruction) -> Variation {
        let mem: [Atom] = [Atom(0, .L), Atom(0, .L)]
        let pc = Atom(0, .L)
        let stk1: Stack = .cons(Atom(0, .L), .cons(Atom(0, .H), .mty))
        let stk2: Stack = .cons(Atom(0, .L), .cons(Atom(1, .H), .mty))
        return Variation(
            State(imem: [i, i], mem: mem, stack: stk1, pc: pc),
            State(imem: [i, i], mem: mem, stack: stk2, pc: pc))
    }
    return [.store, .load, .add, .push(0), .bcall(0), .nop, .bret].map(pair)
}()

// Port of the QuickChick `ifc-basic` reference's `Machine.v` + `Instructions.v`.
//
// A tiny stack machine whose values carry two-point labels. `exec` is a single
// step; a rule `table` decides, per opcode, whether the step is allowed and how
// labels propagate. `defaultTable` is the noninterference-correct table; the
// mutants in `Mutate.swift` are systematically-weakened variants of it.

public enum Instruction: Sendable, Equatable, Hashable, Codable {
    case nop
    case push(Int)
    case bcall(Int)   // how many things to pass as arguments
    case bret
    case add
    case load
    case store
}

public enum OpCode: Sendable, Equatable, Hashable, Codable, CaseIterable {
    // Order matches `opCodes` in Instructions.v — mutateTable iterates it.
    case opBCall
    case opBRet
    case opNop
    case opPush
    case opAdd
    case opLoad
    case opStore
}

@inlinable
public func opcodeOf(_ i: Instruction) -> OpCode {
    switch i {
    case .bcall: return .opBCall
    case .bret: return .opBRet
    case .push: return .opPush
    case .nop: return .opNop
    case .add: return .opAdd
    case .load: return .opLoad
    case .store: return .opStore
    }
}

@inlinable
public func labelCount(_ c: OpCode) -> Int {
    switch c {
    case .opBCall: return 1
    case .opBRet: return 2
    case .opNop: return 0
    case .opPush: return 0
    case .opAdd: return 2
    case .opLoad: return 2
    case .opStore: return 3
    }
}

public struct Atom: Sendable, Equatable, Hashable, Codable {
    public var value: Int
    public var label: Label
    public init(_ value: Int, _ label: Label) {
        self.value = value
        self.label = label
    }
}

@inlinable
public func pcLab(_ pc: Atom) -> Label { pc.label }

public indirect enum Stack: Sendable, Equatable, Hashable, Codable {
    case mty                    // empty stack
    case cons(Atom, Stack)      // operand
    case retCons(Atom, Stack)   // return-frame marker
}

public struct State: Sendable, Equatable, Hashable, Codable {
    public var imem: [Instruction]  // instruction memory
    public var mem: [Atom]          // data memory
    public var stack: Stack         // operand stack
    public var pc: Atom             // program counter
    public init(imem: [Instruction], mem: [Atom], stack: Stack, pc: Atom) {
        self.imem = imem
        self.mem = mem
        self.stack = stack
        self.pc = pc
    }
}

// A rule table: one rule per opcode. Held as a dictionary so tables are
// Equatable/Hashable and a mutant can replace exactly one opcode's rule.
public struct Table: Sendable, Equatable, Hashable, Codable {
    public var rules: [OpCode: AllowModify]
    public init(rules: [OpCode: AllowModify]) { self.rules = rules }
    public subscript(_ op: OpCode) -> AllowModify { rules[op]! } // total: built for all 7
    public func with(_ op: OpCode, _ r: AllowModify) -> Table {
        var copy = rules; copy[op] = r; return Table(rules: copy)
    }
}

// Convenience builders mirroring the Coq notations (Lab1/Lab2/Lab3/LabPC/...).
private let labPC: RuleExpr = .varr(.labpc)
private let lab1: RuleExpr = .varr(.lab1)
private let lab2: RuleExpr = .varr(.lab2)
private let lab3: RuleExpr = .varr(.lab3)
private func join(_ a: RuleExpr, _ b: RuleExpr) -> RuleExpr { .join(a, b) }

public let defaultTable = Table(rules: [
    // ≪ TRUE , LabPC , JOIN Lab1 LabPC ≫
    .opBCall: AllowModify(allow: .aTrue, labRes: labPC, labResPC: join(lab1, labPC)),
    // ≪ TRUE , JOIN Lab2 LabPC , Lab1 ≫
    .opBRet: AllowModify(allow: .aTrue, labRes: join(lab2, labPC), labResPC: lab1),
    // ≪ TRUE , __ , LabPC ≫
    .opNop: AllowModify(allow: .aTrue, labRes: nil, labResPC: labPC),
    // ≪ TRUE , BOT , LabPC ≫
    .opPush: AllowModify(allow: .aTrue, labRes: .bot, labResPC: labPC),
    // ≪ TRUE , JOIN Lab1 Lab2, LabPC ≫
    .opAdd: AllowModify(allow: .aTrue, labRes: join(lab1, lab2), labResPC: labPC),
    // ≪ TRUE , JOIN Lab1 Lab2 , LabPC ≫
    .opLoad: AllowModify(allow: .aTrue, labRes: join(lab1, lab2), labResPC: labPC),
    // ≪ LE (JOIN Lab1 LabPC) Lab3, JOIN LabPC (JOIN Lab1 Lab2) , LabPC ≫
    .opStore: AllowModify(
        allow: .le(join(lab1, labPC), lab3),
        labRes: join(labPC, join(lab1, lab2)),
        labResPC: labPC),
])

@usableFromInline
func runTMR(_ t: Table, _ op: OpCode, _ labs: [Label], _ pc: Label) -> (Label?, Label)? {
    applyRule(t[op], labs, pc)
}

// ---- List helpers (faithful to Machine.v, including the Z<0 → None checks) ----

@usableFromInline
func nth<A>(_ l: [A], _ n: Int) -> A? {
    if n < 0 { return nil }
    return n < l.count ? l[n] : nil
}

@usableFromInline
func upd(_ l: [Atom], _ n: Int, _ a: Atom) -> [Atom]? {
    if n < 0 || n >= l.count { return nil }
    var copy = l; copy[n] = a; return copy
}

// insert_nat: drop `a` as a RetCons marker `n` operand-slots deep.
@usableFromInline
func insertStack(_ s: Stack, _ n: Int, _ a: Atom) -> Stack? {
    if n < 0 { return nil }
    func go(_ s: Stack, _ n: Int) -> Stack? {
        if n == 0 { return .retCons(a, s) }
        switch s {
        case .cons(let x, let xs):
            guard let s2 = go(xs, n - 1) else { return nil }
            return .cons(x, s2)
        default:
            return nil
        }
    }
    return go(s, n)
}

@usableFromInline
func findRet(_ s: Stack) -> (Atom, Stack)? {
    switch s {
    case .retCons(let x, let s2): return (x, s2)
    case .cons(_, let s2): return findRet(s2)
    case .mty: return nil
    }
}

@usableFromInline
func lookupInstr(_ st: State) -> Instruction? {
    nth(st.imem, st.pc.value)
}

// A single machine step under table `t`. Returns nil on fault (bad opcode,
// stack underflow, denied side condition, out-of-bounds access).
public func exec(_ t: Table, _ st: State) -> State? {
    guard let instr = lookupInstr(st) else { return nil }
    let xpc = st.pc.value, lpc = st.pc.label
    let m = st.mem, μ = st.imem

    switch (instr, st.stack) {
    case (.bcall(let n), .cons(let arg, let σ)):
        guard case let (rl?, rpcl)? = runTMR(t, .opBCall, [arg.label], lpc) else { return nil }
        let pc2 = Atom(arg.value, rpcl)
        let retPC = Atom(xpc + 1, rl)
        guard let σ2 = insertStack(σ, n, retPC) else { return nil }
        return State(imem: μ, mem: m, stack: σ2, pc: pc2)

    case (.bret, .cons(let a, let σ)):
        guard let (frame, σ2) = findRet(σ) else { return nil }
        let lrpc = frame.label, xrpc = frame.value
        guard case let (rl?, rpcl)? = runTMR(t, .opBRet, [lrpc, a.label], lpc) else { return nil }
        let pc2 = Atom(xrpc, rpcl)
        return State(imem: μ, mem: m, stack: .cons(Atom(a.value, rl), σ2), pc: pc2)

    case (.load, .cons(let x, let σ)):
        guard let a = nth(m, x.value) else { return nil }
        guard case let (rl?, rpcl)? = runTMR(t, .opLoad, [a.label, x.label], lpc) else { return nil }
        return State(imem: μ, mem: m, stack: .cons(Atom(a.value, rl), σ), pc: Atom(xpc + 1, rpcl))

    case (.store, .cons(let x, .cons(let a, let σ))):
        guard let inMem = nth(m, x.value) else { return nil }
        guard case let (rl?, rpcl)? = runTMR(t, .opStore, [x.label, a.label, inMem.label], lpc) else { return nil }
        guard let m2 = upd(m, x.value, Atom(a.value, rl)) else { return nil }
        return State(imem: μ, mem: m2, stack: σ, pc: Atom(xpc + 1, rpcl))

    case (.push(let r), let σ):
        guard case let (rl?, rpcl)? = runTMR(t, .opPush, [], lpc) else { return nil }
        return State(imem: μ, mem: m, stack: .cons(Atom(r, rl), σ), pc: Atom(xpc + 1, rpcl))

    case (.nop, let σ):
        guard case let (_, rpcl)? = runTMR(t, .opNop, [], lpc) else { return nil }
        return State(imem: μ, mem: m, stack: σ, pc: Atom(xpc + 1, rpcl))

    case (.add, .cons(let x, .cons(let y, let σ))):
        guard case let (rl?, rpcl)? = runTMR(t, .opAdd, [x.label, y.label], lpc) else { return nil }
        return State(imem: μ, mem: m, stack: .cons(Atom(x.value + y.value, rl), σ), pc: Atom(xpc + 1, rpcl))

    default:
        return nil
    }
}

public func execN(_ t: Table, _ n: Int, _ s: State) -> [State] {
    var out = [s]
    var cur = s
    var k = n
    while k > 0 {
        guard let s2 = exec(t, cur) else { break }
        out.append(s2)
        cur = s2
        k -= 1
    }
    return out
}

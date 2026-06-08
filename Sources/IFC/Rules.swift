// Port of the QuickChick `ifc-basic` reference's `Rules.v`.
//
// A rule (`AllowModify`) constrains an instruction's effect: when it fires
// (`allow`), the label on its result value (`labRes`, optional), and the label
// of the new PC (`labResPC`). Labels are the two-point lattice L ⊑ H.
//
// In Coq the label *variables* `LAB n` are dependently typed (each carries a
// proof that its index is in range for the opcode's arity `n`). We drop the
// dependent typing: `LAB` is a plain enum, and range-correctness is an invariant
// of `defaultTable` that `mutateTable` preserves (it only ever *drops* disjuncts,
// never introduces a new variable). `evalVar` reads the argument-label vector
// positionally — lab1→vs[0], lab2→vs[1], lab3→vs[2] — exactly as Coq's
// `nth_order` does for the proofs `1<=n`, `2<=n`, `3<=n`.

public enum Label: Sendable, Equatable, Hashable, Codable {
    case L
    case H
}

@inlinable
public func labelEq(_ l1: Label, _ l2: Label) -> Bool { l1 == l2 }

@inlinable
public func labelJoin(_ l1: Label, _ l2: Label) -> Label {
    switch (l1, l2) {
    case (_, .H): return .H
    case (.H, _): return .H
    default: return .L
    }
}

// flows_to: L ≼ anything, anything ≼ H, H ⋠ L.
@inlinable
public func flowsTo(_ l1: Label, _ l2: Label) -> Bool {
    switch (l1, l2) {
    case (.L, _): return true
    case (_, .H): return true
    default: return false
    }
}

// Label variables referenced by a rule expression.
public enum LAB: Sendable, Equatable, Hashable, Codable {
    case lab1
    case lab2
    case lab3
    case labpc
}

public indirect enum RuleExpr: Sendable, Equatable, Hashable, Codable {
    case bot                      // L_Bot — the bottom label, L
    case varr(LAB)                // L_Var
    case join(RuleExpr, RuleExpr) // L_Join
}

public indirect enum RuleScond: Sendable, Equatable, Hashable, Codable {
    case aTrue                       // A_True
    case le(RuleExpr, RuleExpr)      // A_LE — flows_to on label expressions
    case and(RuleScond, RuleScond)   // A_And
    case or(RuleScond, RuleScond)    // A_Or
}

public struct AllowModify: Sendable, Equatable, Hashable, Codable {
    public var allow: RuleScond
    public var labRes: RuleExpr?    // None for ops that return no value (Nop)
    public var labResPC: RuleExpr

    public init(allow: RuleScond, labRes: RuleExpr?, labResPC: RuleExpr) {
        self.allow = allow
        self.labRes = labRes
        self.labResPC = labResPC
    }
}

// mk_eval_var: resolve a label variable against the argument-label vector + pc.
@usableFromInline
func evalVar(_ vs: [Label], _ pc: Label, _ lv: LAB) -> Label {
    switch lv {
    case .lab1: return vs[0]
    case .lab2: return vs[1]
    case .lab3: return vs[2]
    case .labpc: return pc
    }
}

@usableFromInline
func evalExpr(_ vs: [Label], _ pc: Label, _ e: RuleExpr) -> Label {
    switch e {
    case .bot: return .L
    case .varr(let v): return evalVar(vs, pc, v)
    case .join(let e1, let e2):
        return labelJoin(evalExpr(vs, pc, e1), evalExpr(vs, pc, e2))
    }
}

@usableFromInline
func evalCond(_ vs: [Label], _ pc: Label, _ c: RuleScond) -> Bool {
    switch c {
    case .aTrue: return true
    case .and(let c1, let c2): return evalCond(vs, pc, c1) && evalCond(vs, pc, c2)
    case .or(let c1, let c2): return evalCond(vs, pc, c1) || evalCond(vs, pc, c2)
    case .le(let e1, let e2): return flowsTo(evalExpr(vs, pc, e1), evalExpr(vs, pc, e2))
    }
}

// apply_rule: returns (optional result-value label, result-PC label), or nil
// when the side condition fails.
@usableFromInline
func applyRule(_ r: AllowModify, _ vlabs: [Label], _ pclab: Label) -> (Label?, Label)? {
    guard evalCond(vlabs, pclab, r.allow) else { return nil }
    let rpc = evalExpr(vlabs, pclab, r.labResPC)
    let rres: Label? = r.labRes.map { evalExpr(vlabs, pclab, $0) }
    return (rres, rpc)
}

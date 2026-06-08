// Port of the QuickChick `ifc-basic` reference's `Mutate.v`.
//
// Mutants are *generated*, not hand-edited: each mutant is `defaultTable` with
// exactly one opcode's rule weakened — one dropped side-condition conjunct, or
// one dropped disjunct from a result/PC label join. `mutateTable` enumerates the
// full cross-product (opcode × rule field × droppable disjunct), in the same
// order as the Coq reference, yielding exactly 20 mutants for `defaultTable`.

func breakExpr(_ e: RuleExpr) -> [RuleExpr] {
    switch e {
    case .bot: return []
    case .varr(let m): return [.varr(m)]
    case .join(let e1, let e2): return breakExpr(e1) + breakExpr(e2)
    }
}

func joinExprs(_ es: [RuleExpr]) -> RuleExpr {
    switch es.count {
    case 0: return .bot
    case 1: return es[0]
    default: return .join(es[0], joinExprs(Array(es.dropFirst())))
    }
}

func breakScond(_ c: RuleScond) -> [RuleScond] {
    switch c {
    case .aTrue: return []
    case .le(let e1, let e2): return breakExpr(e1).map { .le($0, e2) }
    case .and(let c1, let c2): return breakScond(c1) + breakScond(c2)
    case .or: return [c]
    }
}

func andSconds(_ cs: [RuleScond]) -> RuleScond {
    switch cs.count {
    case 0: return .aTrue
    case 1: return cs[0]
    default: return .and(cs[0], andSconds(Array(cs.dropFirst())))
    }
}

// drop_each [1;2;3;4] = [[2;3;4];[1;3;4];[1;2;4];[1;2;3]]
func dropEach<X>(_ xs: [X]) -> [[X]] {
    guard let head = xs.first else { return [] }
    let tail = Array(xs.dropFirst())
    return [tail] + dropEach(tail).map { [head] + $0 }
}

func mutateExpr(_ e: RuleExpr) -> [RuleExpr] {
    let es = breakExpr(e)
    return es.isEmpty ? [] : dropEach(es).map(joinExprs)
}

func mutateScond(_ c: RuleScond) -> [RuleScond] {
    let cs = breakScond(c)
    return cs.isEmpty ? [] : dropEach(cs).map(andSconds)
}

func mutateRule(_ r: AllowModify) -> [AllowModify] {
    let scondMuts = mutateScond(r.allow).map {
        AllowModify(allow: $0, labRes: r.labRes, labResPC: r.labResPC)
    }
    let resMuts: [AllowModify]
    if let lres = r.labRes {
        resMuts = mutateExpr(lres).map {
            AllowModify(allow: r.allow, labRes: $0, labResPC: r.labResPC)
        }
    } else {
        resMuts = []
    }
    let pcMuts = mutateExpr(r.labResPC).map {
        AllowModify(allow: r.allow, labRes: r.labRes, labResPC: $0)
    }
    return scondMuts + resMuts + pcMuts
}

// Each mutant = `t` with one opcode's rule replaced. Order matches Coq's
// `mutate_table'`: fold over opCodes, then over that opcode's rule mutants.
public func mutateTable(_ t: Table) -> [Table] {
    var out: [Table] = []
    for op in OpCode.allCases {
        for mr in mutateRule(t[op]) {
            out.append(t.with(op, mr))
        }
    }
    return out
}

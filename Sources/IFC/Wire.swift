// Serialization for a Variation:
//  - `wireVariation` — a compact one-line form used to report counterexamples.
//  - `coqVariation`  — the same term rendered as Coq `ifc-basic` syntax, so the
//    differential oracle can emit a Coq program over exactly the inputs Swift
//    tested (validating exec + indist + SSNI + the 20 mutant tables at once).

// Use explicit constructors (Atm / Cons / RetCons), not the `@` / `::` / `:::`
// notations — the latter collide with `ListNotations`' list cons when emitted.
private func coqAtom(_ a: Atom) -> String {
    "(Atm \(a.value) \(a.label == .L ? "L" : "H"))"
}

private func coqStack(_ s: Stack) -> String {
    switch s {
    case .mty: return "Mty"
    case .cons(let a, let s2): return "(Cons \(coqAtom(a)) \(coqStack(s2)))"
    case .retCons(let a, let s2): return "(RetCons \(coqAtom(a)) \(coqStack(s2)))"
    }
}

private func coqInstr(_ i: Instruction) -> String {
    switch i {
    case .nop: return "Nop"
    case .push(let n): return "Push \(n)"
    case .bcall(let n): return "BCall \(n)"
    case .bret: return "BRet"
    case .add: return "Add"
    case .load: return "Load"
    case .store: return "Store"
    }
}

private func coqList(_ xs: [String]) -> String {
    "[" + xs.joined(separator: "; ") + "]"
}

private func coqState(_ st: State) -> String {
    let imem = coqList(st.imem.map(coqInstr))
    let mem = coqList(st.mem.map(coqAtom))
    return "St \(imem) \(mem) (\(coqStack(st.stack))) \(coqAtom(st.pc))"
}

public func coqVariation(_ v: Variation) -> String {
    "V (\(coqState(v.st1))) (\(coqState(v.st2)))"
}

// ---- Compact wire form (counterexample reporting) ----

private func wAtom(_ a: Atom) -> String { "\(a.value)\(a.label == .L ? "L" : "H")" }

private func wStack(_ s: Stack) -> String {
    switch s {
    case .mty: return "."
    case .cons(let a, let s2): return "c\(wAtom(a)) \(wStack(s2))"
    case .retCons(let a, let s2): return "r\(wAtom(a)) \(wStack(s2))"
    }
}

private func wInstr(_ i: Instruction) -> String {
    switch i {
    case .nop: return "N"
    case .push(let n): return "P\(n)"
    case .bcall(let n): return "C\(n)"
    case .bret: return "R"
    case .add: return "A"
    case .load: return "L"
    case .store: return "S"
    }
}

private func wState(_ st: State) -> String {
    let imem = st.imem.map(wInstr).joined(separator: ",")
    let mem = st.mem.map(wAtom).joined(separator: ",")
    return "[\(imem)|\(mem)|\(wStack(st.stack))|\(wAtom(st.pc))]"
}

public func wireVariation(_ v: Variation) -> String {
    "\(wState(v.st1)) / \(wState(v.st2))"
}

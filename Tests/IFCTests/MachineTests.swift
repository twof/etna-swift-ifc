import Testing
import IFC
import IFCGen
import PropertyTestingKit

@Suite struct MachineTests {

    // The table mutator must enumerate exactly the reference's 20 mutants.
    @Test func mutate_table_yields_twenty_mutants() {
        #expect(ifcMutants.count == 20)
    }

    // Every generated mutant is a distinct, strict weakening of defaultTable.
    @Test func every_mutant_differs_from_default_in_one_opcode() {
        for m in ifcMutants {
            let changed = OpCode.allCases.filter { m[$0] != defaultTable[$0] }
            #expect(changed.count == 1)
        }
    }

    // SSNI holds on the clean table: a generated variation never yields `false`.
    @Test func clean_table_satisfies_ssni() {
        var rng = FastRNG()
        for _ in 0..<20000 {
            let v = genVariation(&rng)
            #expect(propSSNI(defaultTable, v) != false)
        }
    }

    // The bespoke `vary` keeps most pairs indistinguishable, so SSNI accepts the
    // majority rather than discarding. (Not 100%: as in the reference, varying
    // the operand stack below a high return-frame can desynchronise low data,
    // which SSNI then discards — that is the reference's high discard rate.)
    @Test func generated_variations_are_mostly_indistinguishable() {
        var rng = FastRNG()
        var indist = 0
        for _ in 0..<10000 {
            let v = genVariation(&rng)
            if indistState(v.st1, v.st2) { indist += 1 }
        }
        #expect(indist > 8000, "too few indistinguishable variations: \(indist)/10000")
    }

    // Fidelity: like the QuickChick reference, the bespoke generator kills all
    // 20 mutants — each has at least one variation that breaks SSNI.
    @Test func all_mutants_are_killed_by_the_generator() {
        var rng = FastRNG()
        var killed = Set<Int>()
        for _ in 0..<200000 where killed.count < 20 {
            let v = genVariation(&rng)
            for (idx, m) in ifcMutants.enumerated() where !killed.contains(idx) {
                if propSSNI(m, v) == false { killed.insert(idx) }
            }
        }
        let survivors = (0..<20).filter { !killed.contains($0) }
        #expect(survivors.isEmpty, "mutants not killed: \(survivors)")
    }
}

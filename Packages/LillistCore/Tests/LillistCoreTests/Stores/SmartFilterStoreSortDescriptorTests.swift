import Testing
import Foundation
@testable import LillistCore

@Suite("SmartFilterStore.sortDescriptors")
struct SmartFilterStoreSortDescriptorTests {

    @Test("manualPosition primary key is 'position', not 'deadline'")
    func manualPositionPrimaryKeyIsPosition() {
        let descs = SmartFilterStore.sortDescriptors(field: .manualPosition, ascending: true)
        #expect(descs.first?.key == "position",
                "Expected primary key 'position' for .manualPosition but got '\(descs.first?.key ?? "nil")'")
    }

    @Test("deadline primary key is 'deadline'")
    func deadlinePrimaryKeyIsDeadline() {
        let descs = SmartFilterStore.sortDescriptors(field: .deadline, ascending: true)
        #expect(descs.first?.key == "deadline")
    }

    @Test("All SortField cases map to distinct primary keys (no accidental aliasing)")
    func noDuplicatePrimaryKeyAliases() {
        // manualPosition and deadline must NOT share the same primary key.
        let manualDescs = SmartFilterStore.sortDescriptors(field: .manualPosition, ascending: true)
        let deadlineDescs = SmartFilterStore.sortDescriptors(field: .deadline, ascending: true)
        #expect(manualDescs.first?.key != deadlineDescs.first?.key,
                ".manualPosition and .deadline must map to different primary keys")
    }
}

import Testing
@testable import LillistCore

@Suite("Status")
struct StatusTests {
    @Test("Raw values are stable for persistence")
    func rawValuesStable() {
        #expect(Status.todo.rawValue == 0)
        #expect(Status.started.rawValue == 1)
        #expect(Status.blocked.rawValue == 2)
        #expect(Status.closed.rawValue == 3)
    }

    @Test("All cases enumerable")
    func allCases() {
        #expect(Status.allCases.count == 4)
        #expect(Status.allCases.contains(.todo))
        #expect(Status.allCases.contains(.started))
        #expect(Status.allCases.contains(.blocked))
        #expect(Status.allCases.contains(.closed))
    }

    @Test("isClosed convenience")
    func isClosed() {
        #expect(Status.closed.isClosed == true)
        #expect(Status.todo.isClosed == false)
        #expect(Status.started.isClosed == false)
        #expect(Status.blocked.isClosed == false)
    }

    @Test("Round-trip through Int16 (Core Data backing type)")
    func int16RoundTrip() {
        for status in Status.allCases {
            let int16 = Int16(status.rawValue)
            #expect(Status(rawValue: Int(int16)) == status)
        }
    }
}

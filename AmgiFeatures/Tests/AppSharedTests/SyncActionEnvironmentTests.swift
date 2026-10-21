import SwiftUI
import Testing
@testable import AppShared

@MainActor
@Suite struct SyncActionEnvironmentTests {
    @Test func defaultActionIsUninstalledAndDoesNothing() {
        let action = EnvironmentValues().startSync

        #expect(!action.isInstalled)
        action()
    }

    @Test func installedActionExecutesEveryRequestAndHasStableIdentity() {
        final class Token {}
        let token = Token()
        var requestCount = 0
        let first = SyncAction(identity: token) { requestCount += 1 }
        let second = SyncAction(identity: token) { requestCount += 100 }

        #expect(first.isInstalled)
        #expect(first == second)
        first()
        first()
        #expect(requestCount == 2)
        #expect(first != SyncAction(identity: Token()) {})
    }
}

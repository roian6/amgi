package import SwiftUI

/// A package-wide request to start the app's existing sync flow.
///
/// The default value is deliberately uninstalled so feature previews and test
/// hosts do not accidentally create a second sync implementation. `SyncFlow`
/// installs the real closure and keeps ownership of its coordinator and UI.
package struct SyncAction: Equatable {
    private let identity: AnyObject?
    private let action: (@MainActor () -> Void)?

    package init() {
        identity = nil
        action = nil
    }

    package init(
        identity: AnyObject,
        action: @escaping @MainActor () -> Void
    ) {
        self.identity = identity
        self.action = action
    }

    package var isInstalled: Bool { action != nil }

    @MainActor
    package func callAsFunction() {
        action?()
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity === rhs.identity
    }
}

extension EnvironmentValues {
    @Entry package var startSync = SyncAction()
}

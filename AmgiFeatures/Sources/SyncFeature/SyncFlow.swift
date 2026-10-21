//
//  SyncFlow.swift
//  SyncFeature
//
//  Created by Vladimir Gusev on 29.08.2026.
//

package import SwiftUI
import AppShared
import Dependencies

/// The whole sync flow behind one modifier: the trigger (published as
/// `EnvironmentValues.startSync` so any toolbar below can fire it), the
/// progress/success toast, the sync sheet, and the collection invalidation
/// each of them implies.
///
/// It lives here rather than in the app root so `SyncCoordinator.state`,
/// `SyncSheet` and the toast controller can stay internal to this module —
/// the root used to drive all three by hand, which is what forced them
/// public.
private struct SyncFlowModifier: ViewModifier {
    let onFinished: () -> Void
    let presentsFeedback: Bool

    @Dependency(\.syncCoordinator) private var coordinator
    @Dependency(\.collectionStore) private var store

    @State private var toast = SyncToastController()
    @State private var showSheet = false

    func body(content: Content) -> some View {
        content
            .environment(
                \.startSync,
                SyncAction(identity: toast) {
                    toast.presentSyncing()
                    Task { await coordinator.startSync() }
                }
            )
            .sheet(isPresented: $showSheet) {
                store.invalidateAll()
                onFinished()
            } content: {
                SyncSheet(isPresented: $showSheet)
                    .presentationDetents([.fraction(0.7), .large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: SyncToastController.needsAttention(coordinator.state)) { _, needs in
                if presentsFeedback && needs { showSheet = true }
            }
            .onChange(of: coordinator.state) { _, newState in
                if presentsFeedback { toast.handle(newState) }
                if case .success = newState { store.invalidateAll() }
            }
            .onChange(of: presentsFeedback, initial: true) { _, enabled in
                guard !enabled else { return }
                showSheet = false
                toast.dismiss()
            }
            .syncToastOverlay(presentsFeedback ? toast.toast : nil, onDismiss: { toast.dismiss() })
    }
}

extension View {
    /// Attach the sync flow. `onFinished` fires after the sheet is dismissed
    /// so the host can refresh anything not backed by `CollectionStore`.
    package func syncFlow(
        presentsFeedback: Bool = true,
        onFinished: @escaping () -> Void
    ) -> some View {
        modifier(SyncFlowModifier(
            onFinished: onFinished,
            presentsFeedback: presentsFeedback
        ))
    }
}

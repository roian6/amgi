//
//  WatchLoginView.swift
//  WatchFeature
//
//  Created by Leaf Eriksen on 17.07.2026.
//

import AnkiClients
import AnkiKit
import AnkiSync
import Dependencies
import os
public import SwiftUI

private let logger = Logger(subsystem: "com.amgiapp.AmgiApp", category: "WatchLogin")

public struct WatchLoginView: View {
    @Dependency(\.syncClient) private var syncClient
    @State private var username = ""
    @State private var password = ""
    @State private var endpoint = SyncEndpoint.official
    /// Form submission state. `showLoginFields` used to sit here too and was
    /// never read.
    enum SubmissionState {
        case idle
        case submitting
        case failed(String)
    }

    @State private var submission: SubmissionState = .idle
    var onLoginSuccess: () -> Void

    public init(onLoginSuccess: @escaping () -> Void) {
        self.onLoginSuccess = onLoginSuccess
    }

    private var isSubmitting: Bool {
        if case .submitting = submission { return true }
        return false
    }
    public var body: some View {
        ScrollView {
            loginFieldsView
        }
        .onAppear {
            if let saved = KeychainHelper.loadEndpoint() {
                endpoint = saved
            }
        }
    }
    private var loginFieldsView: some View {
        VStack {
            TextField("Server URL", text: $endpoint)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("Username", text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            SecureField("Password", text: $password)
                .textContentType(.password)
            if case .failed(let error) = submission {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await login() }
            } label: {
                if isSubmitting {
                    ProgressView()
                } else {
                    Text("Sign In")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || password.isEmpty || isSubmitting)
        }
    }
    private func login() async {
        submission = .submitting
        do {
            let normalizedEndpoint = try SyncEndpoint.normalized(endpoint)
            try KeychainHelper.saveEndpoint(normalizedEndpoint)
            _ = try await SyncClient.login(username: username, password: password)
            _ = try await syncClient.sync()
            submission = .idle
            onLoginSuccess()
        } catch {
            logger.error("Login failed: \(error)")
            submission = .failed(error.localizedDescription)
        }
    }
}

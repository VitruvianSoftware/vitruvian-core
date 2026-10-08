// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Combine
import Foundation
import VitruvianCore

/// A central service managing GitHub status synchronization for watched repositories.
/// Uses direct REST polling with ETags so it works out-of-the-box with zero relays or servers.
@MainActor
package final class GitHubService: ObservableObject {
    package static let shared = GitHubService()

    @Published package private(set) var summary: GitHubSummary
    @Published package private(set) var states: [RepoKey: RepoState] = [:]
    @Published package private(set) var isRefreshing: Bool = false
    @Published package private(set) var lastRefreshedAt: Date? = nil
    @Published package private(set) var lastError: String? = nil

    private let auth: any GitHubTokenProviding
    private let api: GitHubAPIClient
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var pollTask: Task<Void, Never>?
    private var identity: GitHubIdentity?

    package init(auth: any GitHubTokenProviding = GitHubAuthService.shared,
                 api: GitHubAPIClient = GitHubAPIClient(),
                 defaults: UserDefaults = .standard) {
        self.auth = auth
        self.api = api
        self.defaults = defaults
        self.summary = GitHubSummary(states: [:], watched: [])

        auth.signedInChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signedIn in
                self?.handleSignInStateChange(signedIn: signedIn)
            }
            .store(in: &cancellables)
    }

    package var watchedRepositories: [RepoKey] {
        let raw = defaults[Preferences.githubWatchedRepositories]
        let repos = GitHubWatchlist.decode(raw)
        return repos.isEmpty ? GitHubWatchlist.defaultRepositories : repos
    }

    package func refresh() {
        guard let token = auth.currentToken() else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.performPoll(token: token)
            self?.scheduleNextPoll()
        }
    }

    private func handleSignInStateChange(signedIn: Bool) {
        if signedIn {
            refresh()
        } else {
            pollTask?.cancel()
            pollTask = nil
            states = [:]
            summary = GitHubSummary(states: [:], watched: watchedRepositories)
            identity = nil
            lastRefreshedAt = nil
            GitHubPeripheralSink.shared.restore()
        }
    }

    private func performPoll(token: String) async {
        guard !Task.isCancelled else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // 1. Fetch user identity if missing
        if identity == nil {
            if let user = try? await api.fetchIdentity(token: token) {
                identity = user
            }
        }

        let watched = watchedRepositories
        var newStates = states

        // 2. Fetch snapshot for each watched repo
        for repo in watched {
            guard !Task.isCancelled else { return }
            do {
                if let updated = try await api.fetchSnapshot(repo: repo, token: token, knownState: states[repo]) {
                    newStates[repo] = updated
                }
            } catch {
                lastError = error.localizedDescription
                if (error as? GitHubAuthError) == .gitHubRefused(status: 401) {
                    auth.handleUnauthorized()
                    return
                }
            }
        }

        states = newStates
        summary = GitHubSummary(states: newStates, watched: watched)
        // The first snapshot since launch or sign-in, read before it is stamped.
        let firstSnapshot = lastRefreshedAt == nil
        lastRefreshedAt = Date()

        // 3. Update peripheral LED if mouse indicator is enabled. The mouse
        // keeps its LED across app restarts, so the first snapshot always writes.
        if defaults[Preferences.githubMouseIndicator] {
            GitHubPeripheralSink.shared.update(verdict: summary.aggregate, force: firstSnapshot)
        }
    }

    private func scheduleNextPoll() {
        guard auth.currentToken() != nil else { return }
        pollTask?.cancel()

        // Configurable interval: active when runs in progress, standard otherwise
        let hasActiveRuns = summary.repositories.contains { $0.running > 0 }
        let configured = hasActiveRuns
            ? defaults[Preferences.githubPollActiveInterval]
            : defaults[Preferences.githubPollInterval]
        let interval: TimeInterval = max(5, TimeInterval(configured))

        pollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let token = self?.auth.currentToken() else { return }
            await self?.performPoll(token: token)
            self?.scheduleNextPoll()
        }
    }
}

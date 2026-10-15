// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


import Foundation
import ServiceManagement

// The flags that must run as HomeSpeaker.app itself: its keychain-held
// sign-in, its TCC Automation grant, its login item. Parsing and the work
// behind each flag live here, against protocols, so tests drive them without
// a network, a keychain or System Settings; Entry only wires the real parts.

/// One of the app-identity commands, parsed.
public enum AppCommand: Equatable, Sendable {
    /// `--sign-out [--chat]`: every Google login, or only Google Chat's.
    case signOut(chatOnly: Bool)
    /// `--discover [--save] [--home <id>]`
    case discover(save: Bool, home: String?)
    /// `--login-item [status|enable|disable]`
    case loginItem(LoginItemAction)
    /// `--test-media-pause`
    case testMediaPause
}

public enum LoginItemAction: String, CaseIterable, Sendable {
    case status, enable, disable
}

public struct UsageError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public enum AppCommandParser {
    /// Bad flags or arguments: the caller's mistake, as with most CLIs.
    public static let usageExitCode: Int32 = 2
    /// The command ran and failed.
    public static let failureExitCode: Int32 = 1

    public static let signOutFlag = "--sign-out"
    public static let discoverFlag = "--discover"
    public static let loginItemFlag = "--login-item"
    public static let testMediaPauseFlag = "--test-media-pause"
    public static let commandFlags = [signOutFlag, discoverFlag, loginItemFlag, testMediaPauseFlag]

    public static let usageLines = """
      --sign-out [--chat]  sign out of every Google login (or only Google Chat)
      --discover [--save] [--home <id>]
                           list homes and broadcast targets; --save keeps them
                           as the speaker list (the home given, else the
                           current one, else the first)
      --login-item [status|enable|disable]
                           show or change Open at Login
      --test-media-pause   pause what this Mac plays for 3 s, then resume
    """

    /// Nil when the arguments hold none of these commands, so the caller
    /// carries on with its other flags. A command flag must come first:
    /// `--say` text is free-form and may contain anything.
    public static func parse(_ arguments: [String]) -> Result<AppCommand, UsageError>? {
        guard let first = arguments.first else { return nil }
        guard commandFlags.contains(first) else {
            if first == "--say" || first == ClaudeStopHook.announceArgument { return nil }
            if let misplaced = arguments.first(where: commandFlags.contains) {
                return .failure(UsageError("\(misplaced) must be the first argument"))
            }
            return nil
        }
        let rest = Array(arguments.dropFirst())
        if let second = rest.first(where: commandFlags.contains) {
            return .failure(UsageError("\(first) and \(second) cannot be combined; run one at a time"))
        }
        switch first {
        case signOutFlag:
            var chatOnly = false
            for arg in rest {
                guard arg == "--chat", !chatOnly else { return .failure(unexpected(arg, after: first)) }
                chatOnly = true
            }
            return .success(.signOut(chatOnly: chatOnly))
        case discoverFlag:
            var save = false
            var home: String?
            var i = 0
            while i < rest.count {
                switch rest[i] {
                case "--save" where !save:
                    save = true
                case "--home" where home == nil:
                    guard i + 1 < rest.count else { return .failure(UsageError("--home needs a home id (see HomeSpeaker --discover)")) }
                    let id = rest[i + 1].trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty, !id.hasPrefix("-") else {
                        return .failure(UsageError("--home needs a home id (see HomeSpeaker --discover), not \"\(rest[i + 1])\""))
                    }
                    home = id
                    i += 1
                default:
                    return .failure(unexpected(rest[i], after: first))
                }
                i += 1
            }
            return .success(.discover(save: save, home: home))
        case loginItemFlag:
            guard rest.count <= 1 else { return .failure(unexpected(rest[1], after: first)) }
            guard let word = rest.first else { return .success(.loginItem(.status)) }
            guard let action = LoginItemAction(rawValue: word) else {
                let valid = LoginItemAction.allCases.map(\.rawValue).joined(separator: ", ")
                return .failure(UsageError("--login-item takes one of \(valid), not \"\(word)\""))
            }
            return .success(.loginItem(action))
        default: // testMediaPauseFlag
            if let extra = rest.first { return .failure(unexpected(extra, after: first)) }
            return .success(.testMediaPause)
        }
    }

    /// The arguments that `parse` reads back as `command`: how the
    /// Vitruvian tool asks HomeSpeaker's program to run one.
    public static func arguments(for command: AppCommand) -> [String] {
        switch command {
        case .signOut(let chatOnly):
            return [signOutFlag] + (chatOnly ? ["--chat"] : [])
        case .discover(let save, let home):
            var arguments = [discoverFlag]
            if save { arguments.append("--save") }
            if let home { arguments += ["--home", home] }
            return arguments
        case .loginItem(let action):
            return [loginItemFlag, action.rawValue]
        case .testMediaPause:
            return [testMediaPauseFlag]
        }
    }

    private static func unexpected(_ arg: String, after flag: String) -> UsageError {
        UsageError("unexpected argument \"\(arg)\" for \(flag)")
    }
}

/// What a command printed and how it ended.
public struct CLIOutput: Equatable, Sendable {
    public var stdout: [String] = []
    public var stderr: [String] = []
    public var exitCode: Int32 = 0

    public init(stdout: [String] = [], stderr: [String] = [], exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }

    static func failure(_ message: String) -> CLIOutput {
        CLIOutput(stderr: ["error: \(message)"], exitCode: AppCommandParser.failureExitCode)
    }
}

// MARK: - The parts each command drives

public protocol GoogleSigningOut: Sendable {
    func signOut(purpose: GoogleAuth.Purpose?, revoke: Bool) async
}

extension GoogleAuth: GoogleSigningOut {}

public protocol HomeDiscovering: Sendable {
    func listHomes() async throws -> [HomeStructure]
    func discoverBroadcastTargets(structureId: String) async throws -> [String: SpeakerDevice]
}

extension GoogleHomeClient: HomeDiscovering {}

public enum LoginItemState: String, Equatable, Sendable {
    case enabled
    case notRegistered = "disabled"
    case requiresApproval = "requires approval"
    case notFound = "not found"
}

public protocol LoginItemControlling {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
}

/// The app's own login item, through the system API. Only a real .app can
/// register; a bare `.build` binary reads as "not found".
public struct SystemLoginItem: LoginItemControlling {
    public init() {}

    public var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        default: return .notRegistered
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
}

// MARK: - Running them

public enum AppCommandRunner {
    /// Signs out, then checks the stored login is really gone. On success
    /// `notify` tells a running app (Entry passes `SignOutNotice.post`; the
    /// default does nothing, so tests never reach a real running app).
    public static func signOut(
        chatOnly: Bool, auth: GoogleSigningOut, signedIn: @Sendable () -> Set<GoogleAuth.Purpose>,
        notify: @Sendable (_ chatOnly: Bool) -> Void = { _ in }
    ) async -> CLIOutput {
        let purposes: Set<GoogleAuth.Purpose> = chatOnly ? [.chat] : Set(GoogleAuth.Purpose.allCases)
        await auth.signOut(purpose: chatOnly ? .chat : nil, revoke: true)
        let left = signedIn().intersection(purposes)
        guard left.isEmpty else {
            return .failure("still signed in for \(left.map(\.rawValue).sorted().joined(separator: " and ")); the sign-in store could not be updated")
        }
        notify(chatOnly)
        return CLIOutput(stdout: [chatOnly ? "signed out of Google Chat" : "signed out of Google (Home and Chat)"])
    }

    /// Lists homes and their broadcast targets; with `save`, makes the
    /// chosen home's targets the speaker list through `apply`.
    public static func discover(
        save: Bool, home wanted: String?, client: HomeDiscovering, currentStructureId: String,
        apply: @MainActor @Sendable (HomeStructure, [String: SpeakerDevice]) throws -> Void
    ) async -> CLIOutput {
        var out = CLIOutput()
        do {
            let homes = try await client.listHomes()
            guard !homes.isEmpty else {
                return .failure("no homes visible to this account (the Home API needs a Google Home Premium Advanced plan)")
            }
            let shown: [HomeStructure]
            if let wanted {
                guard let match = homes.first(where: { $0.id == wanted }) else {
                    return .failure("no home with id \(wanted); this account sees: " + homes.map { "\($0.name) (\($0.id))" }.joined(separator: ", "))
                }
                shown = [match]
            } else if save {
                shown = [homes.first(where: { $0.id == currentStructureId }) ?? homes[0]]
            } else {
                shown = homes
            }
            var lastTargets: [String: SpeakerDevice] = [:]
            for home in shown {
                out.stdout.append("home: \(home.name) (\(home.id))")
                lastTargets = try await client.discoverBroadcastTargets(structureId: home.id)
                for (alias, d) in lastTargets.sorted(by: { $0.key < $1.key }) {
                    out.stdout.append("  \(alias)\t\(d.type)\t\(d.displayLine)\t\(d.id)")
                }
            }
            guard save, let home = shown.first else { return out }
            guard !lastTargets.isEmpty else {
                out.stderr.append("error: no speakers or displays found in \(home.name); the saved speaker list is unchanged")
                out.exitCode = AppCommandParser.failureExitCode
                return out
            }
            try await apply(home, lastTargets)
            out.stdout.append("saved \(lastTargets.count) target(s) from \(home.name)")
            return out
        } catch {
            out.stderr.append("error: \(error.localizedDescription)")
            out.exitCode = AppCommandParser.failureExitCode
            return out
        }
    }

    public static func loginItem(_ action: LoginItemAction, control: LoginItemControlling) -> CLIOutput {
        do {
            switch action {
            case .status:
                break
            case .enable:
                if control.state != .enabled { try control.register() }
            case .disable:
                if control.state == .enabled || control.state == .requiresApproval { try control.unregister() }
            }
        } catch {
            return .failure("could not \(action.rawValue) the login item: \(error.localizedDescription)")
        }
        let state = control.state
        var out = CLIOutput(stdout: ["login item: \(state.rawValue)"])
        switch (action, state) {
        case (.enable, .requiresApproval):
            out.stdout.append("approve HomeSpeaker under System Settings > General > Login Items")
        case (.enable, .enabled), (.disable, .notRegistered), (.disable, .notFound), (.status, _):
            break
        case (.enable, _), (.disable, _):
            out.stderr.append("error: the login item is \(state.rawValue) after \(action.rawValue)"
                              + (state == .notFound ? "; run HomeSpeaker from its .app bundle" : ""))
            out.exitCode = AppCommandParser.failureExitCode
        }
        return out
    }

    /// Pauses what is playing for `hold` seconds, as an announcement would,
    /// then resumes it. Exit 1 when a player could not be paused.
    @MainActor
    public static func testMediaPause(
        coordinator: MediaPauseCoordinator, hold: Double = 3,
        wait: @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) async -> CLIOutput {
        await coordinator.pause(for: hold)
        let report = coordinator.lastReport
        let failed = coordinator.lastPauseHadProblems
        if coordinator.isHolding {
            await wait(hold)
            await coordinator.resumeNow()
        }
        if failed {
            return CLIOutput(stdout: report.map { [$0] } ?? [], exitCode: AppCommandParser.failureExitCode)
        }
        guard let report else { return CLIOutput(stdout: ["nothing was playing that HomeSpeaker can pause"]) }
        return CLIOutput(stdout: [report, "resumed"])
    }
}

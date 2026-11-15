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
@testable import VitruvianCodeCore
import XCTest

final class ACPClientPolicyTests: XCTestCase {
    private static let allToolKinds = [
        "read",
        "edit",
        "delete",
        "move",
        "search",
        "execute",
        "think",
        "fetch",
        "other",
    ]

    /// Exhaustive table of `VitruvianCodeApprovalMode` (5) × `planSwitch` (2) × `toolKind` (9) = 90 cases.
    /// Expected decisions come directly from T3 Code's `clientPolicy.ts`:
    /// - `isAcpReadKind` (`clientPolicy.ts:82-84`, `148-150`): `read`, `search`, `think` always auto-allow;
    /// - `approval-required` (`clientPolicy.ts:166-168`): all non-read kinds ask (including when `planSwitch` is on,
    ///   and for `.standard`, `.plan`, and `.auto` per `AntigravityProvider.ts:188-189`);
    /// - `auto-accept-edits` (`clientPolicy.ts:175-190`): `isAcpMutationKind` (`edit`, `delete`, `move`) auto-allows,
    ///   while `execute`, `fetch`, `other` ask;
    /// - `full-access` (`clientPolicy.ts:162-164`): all kinds auto-allow unless `planSwitch` overrides to `approval-required`.
    func testDecisionTableAcrossEveryModePlanSwitchAndToolKind() {
        let policy = ACPClientPolicy.none
        let allow: ACPClientPolicy.Decision = .allow(.allowOnce)
        let ask: ACPClientPolicy.Decision = .ask

        let table: [(
            mode: VitruvianCodeApprovalMode,
            planSwitch: Bool,
            expectedByKind: [String: ACPClientPolicy.Decision]
        )] = [
            (
                .yolo,
                false,
                [
                    "read": allow,
                    "edit": allow,
                    "delete": allow,
                    "move": allow,
                    "search": allow,
                    "execute": allow,
                    "think": allow,
                    "fetch": allow,
                    "other": allow,
                ]
            ),
            (
                .yolo,
                true,
                [
                    "read": allow,
                    "edit": ask,
                    "delete": ask,
                    "move": ask,
                    "search": allow,
                    "execute": ask,
                    "think": allow,
                    "fetch": ask,
                    "other": ask,
                ]
            ),
            (
                .acceptEdits,
                false,
                [
                    "read": allow,
                    "edit": allow,
                    "delete": allow,
                    "move": allow,
                    "search": allow,
                    "execute": ask,
                    "think": allow,
                    "fetch": ask,
                    "other": ask,
                ]
            ),
            (
                .acceptEdits,
                true,
                [
                    "read": allow,
                    "edit": ask,
                    "delete": ask,
                    "move": ask,
                    "search": allow,
                    "execute": ask,
                    "think": allow,
                    "fetch": ask,
                    "other": ask,
                ]
            ),
            (
                .standard,
                false,
                [
                    "read": allow,
                    "edit": ask,
                    "delete": ask,
                    "move": ask,
                    "search": allow,
                    "execute": ask,
                    "think": allow,
                    "fetch": ask,
                    "other": ask,
                ]
            ),
            (
                .standard,
                true,
                [
                    "read": allow,
                    "edit": ask,
                    "delete": ask,
                    "move": ask,
                    "search": allow,
                    "execute": ask,
                    "think": allow,
                    "fetch": ask,
                    "other": ask,
                ]
            ),
            (
                .plan,
                false,
                [
                    "read": allow,
                    "edit": ask,
                    "delete": ask,
                    "move": ask,
                    "search": allow,
                    "execute": ask,
                    "think": allow,
                    "fetch": ask,
                    "other": ask,
                ]
            ),
            (
                .plan,
                true,
                [
                    "read": allow,
                    "edit": ask,
                    "delete": ask,
                    "move": ask,
                    "search": allow,
                    "execute": ask,
                    "think": allow,
                    "fetch": ask,
                    "other": ask,
                ]
            ),
            (
                .auto,
                false,
                [
                    "read": allow,
                    "edit": ask,
                    "delete": ask,
                    "move": ask,
                    "search": allow,
                    "execute": ask,
                    "think": allow,
                    "fetch": ask,
                    "other": ask,
                ]
            ),
            (
                .auto,
                true,
                [
                    "read": allow,
                    "edit": ask,
                    "delete": ask,
                    "move": ask,
                    "search": allow,
                    "execute": ask,
                    "think": allow,
                    "fetch": ask,
                    "other": ask,
                ]
            ),
        ]

        XCTAssertEqual(table.count, VitruvianCodeApprovalMode.allCases.count * 2)

        var checkedCells = 0
        for row in table {
            XCTAssertEqual(Set(row.expectedByKind.keys), Set(Self.allToolKinds))
            for kind in Self.allToolKinds {
                let expected = row.expectedByKind[kind]!
                let actual = policy.decide(mode: row.mode, planSwitch: row.planSwitch, toolKind: kind)
                XCTAssertEqual(
                    actual,
                    expected,
                    "mode=\(row.mode.rawValue) planSwitch=\(row.planSwitch) toolKind=\(kind)"
                )
                checkedCells += 1
            }
        }
        XCTAssertEqual(checkedCells, 90)
    }

    func testAllowDecisionPrefersAllowOnceFallsBackToAllowAlwaysAndAsksWhenMissing() {
        let policy = ACPClientPolicy.none
        let allowAlways = AgentPermissionOption(id: "always", name: "Always", kind: .allowAlways)
        let allowOnce = AgentPermissionOption(id: "once", name: "Once", kind: .allowOnce)
        let rejectOnce = AgentPermissionOption(id: "no", name: "No", kind: .rejectOnce)

        let pickedOnce = policy.selectPermissionOption(
            mode: .yolo,
            planSwitch: false,
            toolKind: "execute",
            options: [allowAlways, allowOnce, rejectOnce]
        )
        XCTAssertEqual(pickedOnce, allowOnce)

        let pickedAlways = policy.selectPermissionOption(
            mode: .yolo,
            planSwitch: false,
            toolKind: "execute",
            options: [rejectOnce, allowAlways]
        )
        XCTAssertEqual(pickedAlways, allowAlways)

        let noAllowOption = policy.decide(
            mode: .yolo,
            planSwitch: false,
            toolKind: "execute",
            options: [rejectOnce]
        )
        XCTAssertEqual(noAllowOption, .ask)
        XCTAssertNil(
            policy.selectPermissionOption(
                mode: .yolo,
                planSwitch: false,
                toolKind: "execute",
                options: [rejectOnce]
            )
        )
    }

    func testAntigravityPresetForQualifiedAndUnqualifiedVersionsAndNonePreset() {
        // `AntigravityAcpSupport.ts:84-86`: qualified release is `"1.4.5"`.
        XCTAssertEqual(ACPClientPolicy.qualifiedAntigravityReleaseVersion, "1.4.5")
        XCTAssertEqual(
            ACPClientPolicy.none,
            ACPClientPolicy(readTextFile: false, writeTextFile: false, terminal: false, elicitation: false)
        )

        let qualified = ACPClientPolicy.antigravity(version: "1.4.5")
        XCTAssertEqual(
            qualified,
            ACPClientPolicy(readTextFile: false, writeTextFile: false, terminal: false, elicitation: false)
        )
        XCTAssertEqual(ACPClientPolicy.antigravity(version: "  1.4.5 \n"), qualified)

        for unqualifiedVersion in ["1.4.4", "1.4.6", "2.0.0", "", nil] as [String?] {
            let preset = ACPClientPolicy.antigravity(version: unqualifiedVersion)
            XCTAssertNil(preset.sandbox)
            XCTAssertEqual(
                preset,
                ACPClientPolicy(readTextFile: true, writeTextFile: false, terminal: false, elicitation: false),
                "version=\(String(describing: unqualifiedVersion))"
            )
        }
        XCTAssertNil(qualified.sandbox)
    }

    /// Covers every sandbox branch in `clientPolicy.ts`:
    /// - `acpReadDisposition` (`clientPolicy.ts:87-98`): `undefined` (`nil`), `readOnly`, `workspaceWrite`,
    ///   `dangerFullAccess`, `externalSandbox` allow `read`/`search`/`think`; unknown sandbox denies;
    /// - `acpPolicyRequiresApproval` (`clientPolicy.ts:76-80, 151-153`): `approval-required` asks for every
    ///   non-read kind unless `approvalPolicy == .never`, while `approvalPolicy == .onRequest`/`.untrusted` asks;
    /// - `case "readOnly"` (`clientPolicy.ts:157-158`): non-read kinds return `.deny` in `acceptEdits`/`yolo`;
    /// - `case "workspaceWrite"` (`clientPolicy.ts:100-141, 159-169`): mutation kinds (`edit`, `delete`, `move`)
    ///   allow only when `locations` is non-empty and every location resolves (symlink-aware) inside `cwd` or
    ///   `writableRoots`; missing/outside/symlink-escaping locations and all non-mutation kinds return `.deny`;
    /// - `case "dangerFullAccess"` / `case "externalSandbox"` (`clientPolicy.ts:170-172`): allow all non-read kinds;
    /// - `case undefined` (`clientPolicy.ts:173-182`): `approval-required` with `approvalPolicy == .never` denies,
    ///   `auto-accept-edits` allows mutations and asks non-mutations, `full-access` allows all;
    /// - `default` (`clientPolicy.ts:183-185`): unknown sandbox denies.
    func testSandboxDecisionTableAndWorkspaceWriteContainment() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-policy-\(UUID().uuidString)", isDirectory: true)
        let cwdDir = tempRoot.appendingPathComponent("cwd", isDirectory: true)
        let writableDir = tempRoot.appendingPathComponent("writable", isDirectory: true)
        let outsideDir = tempRoot.appendingPathComponent("outside", isDirectory: true)
        for dir in [cwdDir, writableDir, outsideDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let escapeLink = cwdDir.appendingPathComponent("escape-link")
        try FileManager.default.createSymbolicLink(at: escapeLink, withDestinationURL: outsideDir)

        let insideCwdLoc = [ACPToolCallLocation(path: "src/NewFile.swift")]
        let insideWritableLoc = [ACPToolCallLocation(path: writableDir.appendingPathComponent("gen.txt").path)]
        let outsideLoc = [ACPToolCallLocation(path: outsideDir.appendingPathComponent("secret.txt").path)]
        let symlinkEscapeLoc = [ACPToolCallLocation(path: escapeLink.appendingPathComponent("pwn.txt").path)]

        let policy = ACPClientPolicy.none
        let allow: ACPClientPolicy.Decision = .allow(.allowOnce)
        let ask: ACPClientPolicy.Decision = .ask
        let deny: ACPClientPolicy.Decision = .deny

        struct SandboxCase {
            let label: String
            let mode: VitruvianCodeApprovalMode
            let planSwitch: Bool
            let sandbox: ACPClientPolicy.Sandbox?
            let locations: [ACPToolCallLocation]?
            let approvalPolicy: ACPClientPolicy.ApprovalPolicy?
            let expectedByKind: [String: ACPClientPolicy.Decision]
        }

        let allAllowKinds = Dictionary(uniqueKeysWithValues: Self.allToolKinds.map { ($0, allow) })
        let readsAllowRestDeny = Dictionary(uniqueKeysWithValues: Self.allToolKinds.map { kind in
            (kind, ACPClientPolicy.isReadKind(kind) ? allow : deny)
        })
        let readsAllowRestAsk = Dictionary(uniqueKeysWithValues: Self.allToolKinds.map { kind in
            (kind, ACPClientPolicy.isReadKind(kind) ? allow : ask)
        })
        let readsAndMutationsAllowRestDeny = Dictionary(uniqueKeysWithValues: Self.allToolKinds.map { kind in
            let ok = ACPClientPolicy.isReadKind(kind) || ACPClientPolicy.isMutationKind(kind)
            return (kind, ok ? allow : deny)
        })
        let readsAndMutationsAllowRestAsk = Dictionary(uniqueKeysWithValues: Self.allToolKinds.map { kind in
            if ACPClientPolicy.isReadKind(kind) || ACPClientPolicy.isMutationKind(kind) {
                return (kind, allow)
            }
            return (kind, ask)
        })
        let allDenyKinds = Dictionary(uniqueKeysWithValues: Self.allToolKinds.map { ($0, deny) })

        let cases: [SandboxCase] = [
            // `sandbox: nil` (`clientPolicy.ts:89, 173-182`)
            SandboxCase(
                label: "nil-acceptEdits",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: nil,
                locations: outsideLoc,
                approvalPolicy: nil,
                expectedByKind: readsAndMutationsAllowRestAsk
            ),
            SandboxCase(
                label: "nil-approvalRequired-never",
                mode: .standard,
                planSwitch: false,
                sandbox: nil,
                locations: insideCwdLoc,
                approvalPolicy: .never,
                expectedByKind: readsAllowRestDeny
            ),
            SandboxCase(
                label: "nil-acceptEdits-never",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: nil,
                locations: nil,
                approvalPolicy: .never,
                expectedByKind: allAllowKinds
            ),
            // `sandbox: .readOnly` (`clientPolicy.ts:90, 157-158`)
            SandboxCase(
                label: "readOnly-acceptEdits",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: .readOnly,
                locations: insideCwdLoc,
                approvalPolicy: nil,
                expectedByKind: readsAllowRestDeny
            ),
            SandboxCase(
                label: "readOnly-yolo",
                mode: .yolo,
                planSwitch: false,
                sandbox: .readOnly,
                locations: insideCwdLoc,
                approvalPolicy: nil,
                expectedByKind: readsAllowRestDeny
            ),
            SandboxCase(
                label: "readOnly-standard-asks-before-sandbox",
                mode: .standard,
                planSwitch: false,
                sandbox: .readOnly,
                locations: insideCwdLoc,
                approvalPolicy: nil,
                expectedByKind: readsAllowRestAsk
            ),
            // `sandbox: .workspaceWrite` (`clientPolicy.ts:91, 100-141, 159-169`)
            SandboxCase(
                label: "workspaceWrite-inside-cwd",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: .workspaceWrite(writableRoots: [writableDir.path]),
                locations: insideCwdLoc,
                approvalPolicy: nil,
                expectedByKind: readsAndMutationsAllowRestDeny
            ),
            SandboxCase(
                label: "workspaceWrite-inside-writableRoot",
                mode: .yolo,
                planSwitch: false,
                sandbox: .workspaceWrite(writableRoots: [writableDir.path]),
                locations: insideWritableLoc,
                approvalPolicy: nil,
                expectedByKind: readsAndMutationsAllowRestDeny
            ),
            SandboxCase(
                label: "workspaceWrite-both-inside-cwd-and-writableRoot",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: .workspaceWrite(writableRoots: [writableDir.path]),
                locations: insideCwdLoc + insideWritableLoc,
                approvalPolicy: nil,
                expectedByKind: readsAndMutationsAllowRestDeny
            ),
            SandboxCase(
                label: "workspaceWrite-mixed-inside-and-outside",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: .workspaceWrite(writableRoots: [writableDir.path]),
                locations: insideCwdLoc + outsideLoc,
                approvalPolicy: nil,
                expectedByKind: readsAllowRestDeny
            ),
            SandboxCase(
                label: "workspaceWrite-symlink-escape",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: .workspaceWrite(writableRoots: [writableDir.path]),
                locations: symlinkEscapeLoc,
                approvalPolicy: nil,
                expectedByKind: readsAllowRestDeny
            ),
            SandboxCase(
                label: "workspaceWrite-empty-locations",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: .workspaceWrite(writableRoots: [writableDir.path]),
                locations: [],
                approvalPolicy: nil,
                expectedByKind: readsAllowRestDeny
            ),
            SandboxCase(
                label: "workspaceWrite-nil-locations",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: .workspaceWrite(writableRoots: [writableDir.path]),
                locations: nil,
                approvalPolicy: nil,
                expectedByKind: readsAllowRestDeny
            ),
            // `sandbox: .dangerFullAccess` & `.externalSandbox` (`clientPolicy.ts:92-93, 170-172`)
            SandboxCase(
                label: "dangerFullAccess-acceptEdits",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: .dangerFullAccess,
                locations: outsideLoc,
                approvalPolicy: nil,
                expectedByKind: allAllowKinds
            ),
            SandboxCase(
                label: "externalSandbox-acceptEdits",
                mode: .acceptEdits,
                planSwitch: false,
                sandbox: .externalSandbox,
                locations: outsideLoc,
                approvalPolicy: nil,
                expectedByKind: allAllowKinds
            ),
            // `sandbox: .unknown` (`clientPolicy.ts:95-97, 183-185`)
            SandboxCase(
                label: "unknown-yolo",
                mode: .yolo,
                planSwitch: false,
                sandbox: .unknown("custom-sandbox"),
                locations: insideCwdLoc,
                approvalPolicy: nil,
                expectedByKind: allDenyKinds
            ),
        ]

        for row in cases {
            for kind in Self.allToolKinds {
                let actual = policy.decide(
                    mode: row.mode,
                    planSwitch: row.planSwitch,
                    toolKind: kind,
                    sandbox: row.sandbox,
                    locations: row.locations,
                    cwd: cwdDir.path,
                    approvalPolicy: row.approvalPolicy
                )
                XCTAssertEqual(
                    actual,
                    row.expectedByKind[kind],
                    "case=\(row.label) kind=\(kind)"
                )
            }
        }

        // Deny outcome selection: `reject_once` preferred, else `reject_always`, else `.cancelled`.
        let allowOnce = AgentPermissionOption(id: "allow-1", name: "Allow", kind: .allowOnce)
        let rejectAlways = AgentPermissionOption(id: "reject-always", name: "Never", kind: .rejectAlways)
        let rejectOnce = AgentPermissionOption(id: "reject-once", name: "Deny", kind: .rejectOnce)

        XCTAssertEqual(
            policy.resolvePermissionOutcome(
                mode: .acceptEdits,
                planSwitch: false,
                toolKind: "execute",
                sandbox: .readOnly,
                options: [allowOnce, rejectAlways, rejectOnce]
            ),
            .selected(optionId: "reject-once")
        )
        XCTAssertEqual(
            policy.resolvePermissionOutcome(
                mode: .acceptEdits,
                planSwitch: false,
                toolKind: "execute",
                sandbox: .readOnly,
                options: [allowOnce, rejectAlways]
            ),
            .selected(optionId: "reject-always")
        )
        XCTAssertEqual(
            policy.resolvePermissionOutcome(
                mode: .acceptEdits,
                planSwitch: false,
                toolKind: "execute",
                sandbox: .readOnly,
                options: [allowOnce]
            ),
            .cancelled
        )
    }
}

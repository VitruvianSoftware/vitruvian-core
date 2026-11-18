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

import AppKit
import SwiftUI
import VitruvianCodeCore
@testable import VitruvianCodeUI
import XCTest

/// Snapshot tests for agent approval option cards and question form cards in light and dark mode.
final class AgentCardSnapshotTests: XCTestCase {
    /// Bazel's undeclared outputs folder when there is one (the PNGs land in
    /// the test's `test.outputs`), else a folder in the temporary directory.
    private static var snapshotFolderPath: String {
        ProcessInfo.processInfo.environment["TEST_UNDECLARED_OUTPUTS_DIR"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("vitruvian-code-snapshots")
    }

    @MainActor
    func testRendersApprovalOptionsAndQuestionFormCardsLightAndDark() throws {
        let approvalOptions: [AgentPermissionOption] = [
            AgentPermissionOption(id: "allow-once", name: "Allow once", kind: .allowOnce),
            AgentPermissionOption(id: "allow-always", name: "Always allow Bash", kind: .allowAlways),
            AgentPermissionOption(id: "reject-once", name: "Reject", kind: .rejectOnce),
            AgentPermissionOption(id: "reject-always", name: "Never allow", kind: .rejectAlways),
        ]

        let pendingApproval = VitruvianCodeChatMessage(
            role: .agent,
            text: "",
            approvalRequest: VitruvianCodeApprovalRequest(
                id: "app-pending",
                toolName: "Bash",
                commandOrPath: "rm -rf build/cache",
                status: .pending,
                requestID: "req-1",
                options: approvalOptions
            )
        )
        let decidedApproval = VitruvianCodeChatMessage(
            role: .agent,
            text: "",
            approvalRequest: VitruvianCodeApprovalRequest(
                id: "app-decided",
                toolName: "Bash",
                commandOrPath: "git status",
                status: .sessionAllowed,
                requestID: "req-2",
                options: approvalOptions,
                chosenOptionID: "allow-always"
            )
        )

        let formQuestion = AgentQuestion(
            requestID: "q-form",
            title: "Deployment Options",
            message: "Choose target environment and add release notes.",
            fields: [
                AgentQuestion.Field(
                    id: "env",
                    type: .choice,
                    label: "Environment",
                    required: true,
                    options: [
                        AgentQuestion.Option(value: "staging", label: "Staging", description: "Deploy to staging cluster"),
                        AgentQuestion.Option(value: "prod", label: "Production", description: "Deploy to live traffic"),
                    ]
                ),
                AgentQuestion.Field(id: "notes", type: .text, label: "Release Notes", required: false),
            ]
        )
        let pendingFormMsg = VitruvianCodeChatMessage(
            role: .agent,
            text: "",
            question: formQuestion,
            questionStatus: .pending
        )
        let answeredFormMsg = VitruvianCodeChatMessage(
            role: .agent,
            text: "",
            question: formQuestion,
            questionStatus: .answered(["env": "prod", "notes": "v2.4.0 rollout"])
        )
        let urlQuestionMsg = VitruvianCodeChatMessage(
            role: .agent,
            text: "",
            question: AgentQuestion(
                requestID: "q-url",
                title: "Sign in",
                message: "Open the sign-in page to continue.",
                url: "https://auth.example.com/oauth/start?client_id=vitruvian&redirect_uri=http://localhost:8080/cb"
            ),
            questionStatus: .pending
        )

        let shots: [(name: String, message: VitruvianCodeChatMessage)] = [
            ("approval-options-pending", pendingApproval),
            ("approval-options-decided", decidedApproval),
            ("form-card-pending", pendingFormMsg),
            ("form-card-answered", answeredFormMsg),
            ("form-card-url", urlQuestionMsg),
        ]

        _ = NSApplication.shared
        let folderURL = URL(fileURLWithPath: Self.snapshotFolderPath, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        for shot in shots {
            for (schemeName, scheme, appearanceName) in [
                ("light", ColorScheme.light, NSAppearance.Name.aqua),
                ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua),
            ] {
                let view = VitruvianCodeMessageBubble(
                    message: shot.message,
                    strings: VitruvianCodeChatStrings(),
                    errorScheme: "x-test"
                )
                .frame(width: 560)
                .padding(16)
                .fixedSize(horizontal: false, vertical: true)
                .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
                .environment(\.colorScheme, scheme)

                let bitmap = try Self.renderViewToBitmap(view, width: 592, appearanceName: appearanceName)
                let yellowShare = Self.placeholderYellowShare(in: bitmap)
                XCTAssertLessThan(
                    yellowShare,
                    0.01,
                    "\(shot.name)-\(schemeName) contains placeholder yellow (\(String(format: "%.2f", yellowShare * 100))%)"
                )

                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let fileName = "\(shot.name)-\(schemeName).png"
                let destination = folderURL.appendingPathComponent(fileName)
                try data.write(to: destination)
                print("agent card snapshot: \(destination.path)")
                XCTAssertGreaterThan(bitmap.pixelsWide, 100)
                XCTAssertGreaterThan(bitmap.pixelsHigh, 80)
            }
        }
    }

    func testReturnToSendSubmitsValidFormAndSendsNothingWhenInvalid() {
        let question = AgentQuestion(
            requestID: "q-ret",
            title: "Deploy",
            message: "Choose target and count",
            fields: [
                AgentQuestion.Field(
                    id: "env",
                    type: .choice,
                    label: "Environment",
                    required: true,
                    options: [AgentQuestion.Option(value: "prod", label: "Production")]
                ),
                AgentQuestion.Field(id: "replicas", type: .integer, label: "Replicas", required: true),
            ]
        )

        var form = AgentQuestionForm(question: question)
        XCTAssertNil(form.submitOnReturn(status: .pending), "incomplete form must send nothing on Return")

        form.selectChoice(fieldID: "env", value: "prod")
        form.setText(fieldID: "replicas", value: "not-an-int")
        XCTAssertNil(form.submitOnReturn(status: .pending), "invalid form must send nothing on Return")

        form.setText(fieldID: "replicas", value: "3")
        XCTAssertEqual(
            form.submitOnReturn(status: .pending),
            ["env": "prod", "replicas": "3"],
            "valid form must submit answers on Return"
        )
        XCTAssertNil(form.submitOnReturn(status: .expired), "non-pending card must send nothing on Return")
        XCTAssertNil(form.submitOnReturn(status: .skipped))
    }

    @MainActor
    private static func renderViewToBitmap<V: View>(
        _ view: V,
        width: CGFloat,
        appearanceName: NSAppearance.Name
    ) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearanceName)
        let initialFitting = host.fittingSize
        let initialSize = NSSize(width: max(initialFitting.width, width), height: max(initialFitting.height, 1))
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearanceName)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: initialSize)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        for _ in 0 ..< 25 {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
            host.layoutSubtreeIfNeeded()
        }
        let finalSize = NSSize(width: max(host.fittingSize.width, width), height: max(host.fittingSize.height, 1))
        if finalSize != window.frame.size {
            window.setContentSize(finalSize)
            host.frame = NSRect(origin: .zero, size: finalSize)
            host.layoutSubtreeIfNeeded()
        }
        window.displayIfNeeded()
        defer {
            window.contentView = nil
            window.close()
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "AgentCardSnapshotTests", code: 1)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private static func placeholderYellowShare(in bitmap: NSBitmapImageRep) -> Double {
        guard let cgImage = bitmap.cgImage else { return 1.0 }
        let width = cgImage.width
        let height = cgImage.height
        let total = width * height
        guard total > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let data = ctx.data else {
            return 1.0
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let ptr = data.bindMemory(to: UInt8.self, capacity: total * 4)
        var yellowCount = 0
        for i in 0 ..< total {
            let offset = i * 4
            let r = Int(ptr[offset])
            let g = Int(ptr[offset + 1])
            let b = Int(ptr[offset + 2])
            if abs(r - 255) <= 25 && abs(g - 204) <= 25 && b <= 40 {
                yellowCount += 1
            }
        }
        return Double(yellowCount) / Double(total)
    }
}

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
                url: "https://auth.example.com/oauth/start"
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

        let folder = ProcessInfo.processInfo.environment["TEST_UNDECLARED_OUTPUTS_DIR"] ?? NSTemporaryDirectory()
        for shot in shots {
            for (schemeName, scheme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
                let view = VitruvianCodeMessageBubble(
                    message: shot.message,
                    strings: VitruvianCodeChatStrings(),
                    errorScheme: "x-test"
                )
                .frame(width: 560)
                .padding(16)
                .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
                .environment(\.colorScheme, scheme)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.cgImage else {
                    throw XCTSkip("ImageRenderer drew nothing here")
                }
                let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                let url = URL(fileURLWithPath: folder).appendingPathComponent("\(shot.name)-\(schemeName).png")
                try data.write(to: url)
                XCTAssertGreaterThan(image.width, 100)
                XCTAssertGreaterThan(image.height, 80)
            }
        }
    }
}

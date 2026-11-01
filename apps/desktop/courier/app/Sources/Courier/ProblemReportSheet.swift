// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UniformTypeIdentifiers

/// Local-only **Report a Problem** sheet (`⌘⇧P`, `Help ▸ Report a Problem…`).
///
/// Builds a scrubbed diagnostic bundle (`report.json`, `bridges.json`, `stderr-scrubbed.log`, and optional
/// user-attached screenshots/videos) and saves it to a local path chosen in `NSSavePanel`. Nothing is ever
/// uploaded over the network.
public struct ProblemReportSheet: View {
    @ObservedObject var model: ProblemReportModel
    var pasteboard: TextPasteboard = SystemPasteboard()
    public var reportUploader: any ReportUploader = UnavailableReportUploader()
    var onDismiss: () -> Void = {}
    @State private var uploadStubNotice: String?

    public init(
        model: ProblemReportModel,
        pasteboard: TextPasteboard = SystemPasteboard(),
        reportUploader: any ReportUploader = UnavailableReportUploader(),
        onDismiss: @escaping () -> Void = {}
    ) {
        self.model = model
        self.pasteboard = pasteboard
        self.reportUploader = reportUploader
        self.onDismiss = onDismiss
    }

    private var includeDetailsTitle: String {
        if model.contextEventID != nil {
            return String(localized: "Include Message Details")
        }
        return String(localized: "Include Latest Message Details")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Report a Problem"))
                        .font(.headline)
                    Text(String(localized: "Saves a scrubbed diagnostic bundle on this Mac. Nothing is sent over the network."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "What happened?"))
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $model.descriptionText)
                    .font(.body)
                    .frame(height: 84)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if model.descriptionText.isEmpty {
                            Text(String(localized: "Describe the issue..."))
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 13)
                                .allowsHitTesting(false)
                        }
                    }
            }

            HStack(spacing: 10) {
                Button(String(localized: "Attach screenshot or video…")) {
                    chooseAttachments()
                }
                .controlSize(.small)

                if !model.attachedFileURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(model.attachedFileURLs, id: \.self) { url in
                                HStack(spacing: 4) {
                                    Image(systemName: "paperclip")
                                        .font(.caption2)
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Button {
                                        model.attachedFileURLs.removeAll { $0 == url }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.12))
                                )
                            }
                        }
                    }
                }
                Spacer()
            }

            Toggle(isOn: Binding(
                get: { model.includeMessageDetails },
                set: { newValue in
                    model.includeMessageDetails = newValue
                    Task { await model.loadDiagnostics() }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(includeDetailsTitle)
                        .font(.subheadline)
                    Text(String(localized: "Includes scrubbed room and event IDs, network, timestamp, and delivery status. Message text and names are never included."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Scrubbed Diagnostic Preview"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(String(localized: "Copy Diagnostic Data")) {
                        let combined = model.previewStderrText.isEmpty
                            ? model.previewJSONText
                            : model.previewJSONText + "\n\n--- stderr-scrubbed.log ---\n" + model.previewStderrText
                        pasteboard.setString(combined)
                    }
                    .controlSize(.small)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.previewJSONText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        if !model.previewStderrText.isEmpty {
                            Divider()
                            Text("stderr-scrubbed.log")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(model.previewStderrText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 150)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            }

            if let errorText = model.errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let savedURL = model.savedBundleURL {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(localized: "Saved to \(savedURL.lastPathComponent)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let uploadStubNotice {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(uploadStubNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(String(localized: "Cancel")) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(String(localized: "Upload Report (Not available yet)")) {
                    uploadStubNotice = reportUploader.unavailableReason
                }
                .help(reportUploader.unavailableReason)

                Button(String(localized: "Save Problem Report…")) {
                    chooseSaveDestination()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            await model.loadDiagnostics()
        }
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .movie]
        panel.prompt = String(localized: "Attach")
        if panel.runModal() == .OK {
            for url in panel.urls where !model.attachedFileURLs.contains(url) {
                model.attachedFileURLs.append(url)
            }
        }
    }

    private func chooseSaveDestination() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ProblemReportModel.defaultArchiveFileName()
        panel.allowedContentTypes = [.zip]
        panel.prompt = String(localized: "Save")
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await model.saveBundle(to: url)
            }
        }
    }
}

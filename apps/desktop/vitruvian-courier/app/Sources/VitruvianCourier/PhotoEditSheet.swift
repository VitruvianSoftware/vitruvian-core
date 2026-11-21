// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import ImageIO
import UniformTypeIdentifiers
import VitruvianCourierCore
import SwiftUI

/// "Edit with AI…": the photo, what to change, then the original and the result side by side. From there the person
/// can try again, save the result to the Mac, or put it in the chat's message box as a draft. **Nothing here sends.**
struct PhotoEditSheet: View {
    @ObservedObject var model: PhotoEditModel
    var onClose: () -> Void
    /// Says something short in the chat's toast, after Add to Message.
    var onToast: (String) -> Void = { _ in }

    @State private var original: CGImage?
    @State private var edited: CGImage?
    @Environment(\.redactNamesAndPictures) private var isRedacted

    static let instructionPrompt = String(localized: "Describe the change — e.g. brighten it, remove the person on the left")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Edit with AI"))
                .font(.headline)

            switch model.phase {
            case let .unavailable(resolution):
                unavailableContent(resolution)
            case let .confirming(service):
                photoRow
                consentContent(service)
            default:
                photoRow
                instructionRow
                statusAndButtons
            }

            if let notice = model.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 640)
        .task(id: model.source.path) {
            guard !isRedacted else { return }
            original = await ThumbnailLoader.shared.thumbnail(atPath: model.source.path)?.image
        }
        .task(id: model.outcome?.image.data.count) {
            guard !isRedacted else { return }
            edited = model.outcome.flatMap { Self.previewImage($0.image.data) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // A key added in Settings turns "can't edit photos" into "ready".
            model.recheck()
        }
    }

    // MARK: - Pieces

    private var photoRow: some View {
        HStack(alignment: .top, spacing: 16) {
            photoColumn(
                title: model.outcome == nil ? nil : String(localized: "Original"),
                image: original,
                caption: nil
            )
            if let outcome = model.outcome {
                photoColumn(title: String(localized: "Edited"), image: edited, caption: outcome.caption)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func photoColumn(title: String?, image: CGImage?, caption: String?) -> some View {
        VStack(spacing: 6) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var instructionRow: some View {
        TextField(Self.instructionPrompt, text: $model.instruction, axis: .vertical)
            .lineLimit(1 ... 3)
            .textFieldStyle(.roundedBorder)
            .disabled(isWorking)
            .onSubmit { model.submit() }
            .accessibilityLabel(String(localized: "What to change"))
    }

    private var isWorking: Bool {
        if case .working = model.phase { return true }
        return false
    }

    @ViewBuilder
    private var statusAndButtons: some View {
        switch model.phase {
        case let .working(service):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Editing with \(service.label)…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(String(localized: "Stop")) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        case let .failed(failure, service):
            VStack(alignment: .leading, spacing: 10) {
                Text(failure.message(service: service))
                    .font(.callout)
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if failure.needsSettings {
                        Button(String(localized: "Open AI Settings")) { model.openSettings() }
                    }
                    Spacer(minLength: 0)
                    Button(String(localized: "Close"), action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Button(String(localized: "Try Again")) { model.submit() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canSubmit)
                }
            }
        case .done:
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Nothing is sent. Add to Message puts the edited photo in your message box so you can look at it and press Send yourself."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(String(localized: "Try Again")) { model.submit() }
                        .disabled(!model.canSubmit)
                    Button(String(localized: "Save to Mac…")) { save() }
                    Spacer(minLength: 0)
                    Button(String(localized: "Done"), action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Button(String(localized: "Add to Message")) {
                        if model.addToMessage() {
                            onClose()
                            onToast(String(localized: "Added to your message. Nothing is sent until you press Send."))
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        default:
            HStack {
                Text(String(localized: "The photo goes to the AI service you chose in Settings ▸ AI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(String(localized: "Cancel"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Edit")) { model.submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSubmit)
            }
        }
    }

    private func consentContent(_ service: AIProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PhotoEditConsentStore.question(for: service))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button(String(localized: "Cancel")) { model.declineConsent() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Continue")) { model.confirmConsent() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func unavailableContent(_ resolution: PhotoEditingResolution) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            photoRow
            if let message = resolution.unavailableMessage {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote = resolution.unavailableFootnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if resolution.keyToAdd != nil {
                    Button(String(localized: "Open AI Settings")) { model.openSettings() }
                        .keyboardShortcut(.defaultAction)
                    if let url = resolution.keyToAdd?.keyPortalURL {
                        Link(String(localized: "Get a Google AI Studio key"), destination: url)
                            .font(.callout)
                    }
                }
                Spacer(minLength: 0)
                Button(String(localized: "Close"), action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        guard let outcome = model.outcome else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.suggestedFileName
        panel.allowedContentTypes = [UTType(mimeType: outcome.image.mimeType) ?? .png]
        panel.canCreateDirectories = true
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                model.saveToMac(at: url)
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            model.saveToMac(at: url)
        }
    }

    /// The result at a size the sheet shows, decoded off the file's full size.
    static func previewImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

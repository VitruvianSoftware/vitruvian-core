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
import NexusAgentCore
import SwiftUI
import WebKit

// MARK: - Annotated Diff Review View

/// Displays parsed `NexusAgentDiffFile`s with inline line-anchored markdown annotations
/// and a one-click "Send Review Batch to Agent" action.
@MainActor
public struct NexusAgentAnnotatedDiffView: View {
    @ObservedObject private var reviewSession: NexusAgentDiffReviewSession
    private let onSendBatch: (String) -> Void

    @State private var activeDraftLineID: String?
    @State private var activeDraftFilePath: String = ""
    @State private var activeDraftLineNumber: Int = 1
    @State private var activeDraftSnippet: String = ""
    @State private var draftCommentText: String = ""
    @State private var collapsedFileIDs: Set<String> = []

    public init(
        reviewSession: NexusAgentDiffReviewSession,
        onSendBatch: @escaping (String) -> Void
    ) {
        self.reviewSession = reviewSession
        self.onSendBatch = onSendBatch
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().opacity(0.3)

            if reviewSession.files.isEmpty {
                emptyDiffPlaceholder
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(reviewSession.files) { file in
                            fileCard(file)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NexusAgentTheme.warmCoral)

            Text("Diff Review")
                .font(.system(size: 13, weight: .semibold))

            Text("\(reviewSession.files.count) files")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            let unresolvedCount = reviewSession.unresolvedAnnotations.count
            if unresolvedCount > 0 {
                Text("\(unresolvedCount) unresolved")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NexusAgentTheme.warmCoral)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(NexusAgentTheme.warmCoral.opacity(0.14))
                    )
            }

            Spacer()

            Button {
                if let prompt = reviewSession.composeReviewBatchPrompt() {
                    onSendBatch(prompt)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Send Review Batch to Agent")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(reviewSession.unresolvedAnnotations.isEmpty ? Color.gray.opacity(0.4) : NexusAgentTheme.warmCoral)
                )
            }
            .buttonStyle(.plain)
            .disabled(reviewSession.unresolvedAnnotations.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }

    private var emptyDiffPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No diff loaded")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func fileCard(_ file: NexusAgentDiffFile) -> some View {
        let isCollapsed = collapsedFileIDs.contains(file.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isCollapsed {
                    collapsedFileIDs.remove(file.id)
                } else {
                    collapsedFileIDs.insert(file.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(file.displayPath)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("+\(file.addedCount)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green)

                    Text("-\(file.removedCount)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05))
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                Divider().opacity(0.25)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(file.hunks) { hunk in
                        ForEach(hunk.lines) { line in
                            diffLineView(file: file, line: line)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func diffLineView(file: NexusAgentDiffFile, line: NexusAgentDiffLine) -> some View {
        let lineNumber = line.anchorLineNumber
        let matchingAnnotations = reviewSession.annotations.filter {
            $0.filePath == file.displayPath && lineNumber != nil && $0.endLine == lineNumber
        }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if line.kind != .header, let anchor = lineNumber {
                    Button {
                        activeDraftLineID = line.id
                        activeDraftFilePath = file.displayPath
                        activeDraftLineNumber = anchor
                        activeDraftSnippet = line.content
                        draftCommentText = ""
                    } label: {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 11))
                            .foregroundStyle(NexusAgentTheme.warmCoral)
                    }
                    .buttonStyle(.plain)
                    .help("Annotate line \(anchor)")
                } else {
                    Spacer().frame(width: 14)
                }

                Text(line.oldLineNumber.map(String.init) ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)

                Text(line.newLineNumber.map(String.init) ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)

                Text(prefixSymbol(for: line.kind))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(prefixColor(for: line.kind))
                    .frame(width: 12, alignment: .center)

                Text(line.content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.kind == .header ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(rowBackground(for: line.kind))

            if activeDraftLineID == line.id {
                draftComposerView
            }

            ForEach(matchingAnnotations) { annotation in
                annotationCard(annotation)
            }
        }
    }

    private var draftComposerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Add markdown review note for line \(activeDraftLineNumber)…", text: $draftCommentText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .lineLimit(2...5)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    activeDraftLineID = nil
                    draftCommentText = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Button {
                    let trimmed = draftCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    reviewSession.addAnnotation(
                        filePath: activeDraftFilePath,
                        startLine: activeDraftLineNumber,
                        endLine: activeDraftLineNumber,
                        lineSnippet: activeDraftSnippet,
                        commentMarkdown: trimmed
                    )
                    activeDraftLineID = nil
                    draftCommentText = ""
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 10))
                        Text("Save Note")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(NexusAgentTheme.warmCoral)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.06))
    }

    private func annotationCard(_ annotation: NexusAgentDiffAnnotation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: annotation.isResolved ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(annotation.isResolved ? Color.green : NexusAgentTheme.warmCoral)

            VStack(alignment: .leading, spacing: 3) {
                Text("Line \(annotation.startLine)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(annotation.commentMarkdown)
                    .font(.system(size: 12))
                    .strikethrough(annotation.isResolved)
                    .foregroundStyle(annotation.isResolved ? .secondary : .primary)
            }

            Spacer()

            Button {
                reviewSession.toggleResolved(id: annotation.id)
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(annotation.isResolved ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(annotation.isResolved ? "Unresolve comment" : "Resolve comment")

            Button {
                reviewSession.removeAnnotation(id: annotation.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete comment")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(NexusAgentTheme.warmCoral.opacity(annotation.isResolved ? 0.04 : 0.10))
    }

    private func prefixSymbol(for kind: NexusAgentDiffLine.Kind) -> String {
        switch kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        case .header: return "@"
        }
    }

    private func prefixColor(for kind: NexusAgentDiffLine.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .context, .header: return .secondary
        }
    }

    private func rowBackground(for kind: NexusAgentDiffLine.Kind) -> Color {
        switch kind {
        case .addition: return Color.green.opacity(0.10)
        case .deletion: return Color.red.opacity(0.10)
        case .header: return Color.primary.opacity(0.05)
        case .context: return Color.clear
        }
    }
}

// MARK: - Design Mode Browser View

/// Native `WKWebView` wrapper with URL bar, Design Mode DOM inspector toggle,
/// captured element tray, and one-click "Send Elements to Agent".
@MainActor
public struct NexusAgentDesignModeBrowserView: View {
    @State private var urlString: String
    @State private var committedURLString: String
    @State private var isDesignModeEnabled: Bool = false
    @State private var reloadTrigger: Int = 0
    @State private var captures: [NexusAgentDesignElementCapture] = []

    private let onSendCaptures: (String) -> Void

    public init(
        initialURL: String = "http://localhost:3000",
        onSendCaptures: @escaping (String) -> Void
    ) {
        self._urlString = State(initialValue: initialURL)
        self._committedURLString = State(initialValue: initialURL)
        self.onSendCaptures = onSendCaptures
    }

    public var body: some View {
        VStack(spacing: 0) {
            browserToolbar
            Divider().opacity(0.3)

            NexusAgentInspectableWebView(
                urlString: committedURLString,
                isDesignModeEnabled: isDesignModeEnabled,
                reloadTrigger: reloadTrigger,
                onElementCaptured: { capture in
                    captures.append(capture)
                }
            )
            .frame(minHeight: 240, maxHeight: .infinity)

            if !captures.isEmpty {
                Divider().opacity(0.3)
                captureTray
            }
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("http://localhost:3000", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit {
                    committedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                }

            Button {
                committedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                reloadTrigger += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Reload page")

            Button {
                isDesignModeEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Design Mode")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(isDesignModeEnabled ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isDesignModeEnabled ? NexusAgentTheme.warmCoral : Color.primary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .help("Toggle point-and-click DOM inspection")

            if !captures.isEmpty {
                Button {
                    let attachment = NexusAgentDesignModeScript.formatPromptAttachment(for: captures)
                    if !attachment.isEmpty {
                        onSendCaptures(attachment)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Send Elements to Agent")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(NexusAgentTheme.warmCoral)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
    }

    private var captureTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Captured Elements (\(captures.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    captures.removeAll()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Clear")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach($captures) { $capture in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("<\(capture.tagName)>")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NexusAgentTheme.warmCoral)
                                Text(capture.cssSelector)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    captures.removeAll { $0.id == capture.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            TextField("Describe change for this element…", text: $capture.userIntentNote)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                        }
                        .padding(8)
                        .frame(width: 240)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
    }
}

@MainActor
struct NexusAgentInspectableWebView: NSViewRepresentable {
    let urlString: String
    let isDesignModeEnabled: Bool
    let reloadTrigger: Int
    let onElementCaptured: @MainActor (NexusAgentDesignElementCapture) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onElementCaptured: onElementCaptured)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(
            context.coordinator,
            name: NexusAgentDesignModeScript.messageHandlerName
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.loadIfNeeded(
            urlString: urlString,
            reloadTrigger: reloadTrigger,
            isDesignModeEnabled: isDesignModeEnabled,
            in: webView
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onElementCaptured = onElementCaptured
        context.coordinator.loadIfNeeded(
            urlString: urlString,
            reloadTrigger: reloadTrigger,
            isDesignModeEnabled: isDesignModeEnabled,
            in: webView
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onElementCaptured: @MainActor (NexusAgentDesignElementCapture) -> Void
        private var lastLoadedURL: String?
        private var lastReloadTrigger: Int = -1
        private var lastDesignModeState: Bool = false

        init(onElementCaptured: @escaping @MainActor (NexusAgentDesignElementCapture) -> Void) {
            self.onElementCaptured = onElementCaptured
        }

        func loadIfNeeded(
            urlString: String,
            reloadTrigger: Int,
            isDesignModeEnabled: Bool,
            in webView: WKWebView
        ) {
            let designChanged = lastDesignModeState != isDesignModeEnabled
            lastDesignModeState = isDesignModeEnabled

            if lastLoadedURL != urlString {
                lastLoadedURL = urlString
                lastReloadTrigger = reloadTrigger
                if let url = URL(string: urlString) {
                    webView.load(URLRequest(url: url))
                }
            } else if lastReloadTrigger != reloadTrigger {
                lastReloadTrigger = reloadTrigger
                webView.reload()
            } else if designChanged {
                applyDesignModeScript(in: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyDesignModeScript(in: webView)
        }

        private func applyDesignModeScript(in webView: WKWebView) {
            let script = lastDesignModeState
                ? NexusAgentDesignModeScript.inspectorJavaScript
                : NexusAgentDesignModeScript.disableInspectorJavaScript
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == NexusAgentDesignModeScript.messageHandlerName,
                  let body = message.body as? String else {
                return
            }
            let pageURL = lastLoadedURL ?? ""
            if let capture = NexusAgentDesignModeScript.parseCapture(fromJSON: body, pageURL: pageURL) {
                onElementCaptured(capture)
            }
        }
    }
}

// MARK: - Workspace Notes View

/// Editor and preview for the worktree's `PLAN.md` scratchpad with one-click "Insert into Prompt".
@MainActor
public struct NexusAgentWorkspaceNotesView: View {
    @ObservedObject private var noteStore: NexusAgentWorkspaceNoteStore
    private let onInsertIntoPrompt: (String) -> Void

    public init(
        noteStore: NexusAgentWorkspaceNoteStore,
        onInsertIntoPrompt: @escaping (String) -> Void
    ) {
        self.noteStore = noteStore
        self.onInsertIntoPrompt = onInsertIntoPrompt
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NexusAgentTheme.warmCoral)

                Text("Workspace Notes (PLAN.md)")
                    .font(.system(size: 12, weight: .semibold))

                if noteStore.isDirty {
                    Text("Edited")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    noteStore.save()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 11))
                        Text("Save")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)

                Button {
                    if let excerpt = noteStore.formattedPromptExcerpt() {
                        onInsertIntoPrompt(excerpt)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Insert into Prompt")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(NexusAgentTheme.warmCoral)
                    )
                }
                .buttonStyle(.plain)
                .disabled(noteStore.noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))

            Divider().opacity(0.3)

            TextEditor(
                text: Binding(
                    get: { noteStore.noteContent },
                    set: { noteStore.updateContent($0) }
                )
            )
            .font(.system(size: 12, design: .monospaced))
            .padding(8)
        }
    }
}

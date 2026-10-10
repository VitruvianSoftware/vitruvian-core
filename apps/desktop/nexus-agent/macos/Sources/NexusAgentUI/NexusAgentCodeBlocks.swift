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
//
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).

import AppKit
import SwiftUI
import WebKit

/// An interactive card rendering a Mermaid diagram with Diagram and Source toggle modes.
struct NexusAgentMermaidCard: View {
    let source: String
    let strings: NexusAgentChatStrings
    let errorScheme: String
    @State private var mode: DiagramViewMode = .diagram
    @State private var copied = false
    @State private var renderFailed = false
    @Environment(\.colorScheme) private var colorScheme

    private enum DiagramViewMode: String, CaseIterable, Identifiable {
        case diagram = "Diagram"
        case source = "Source"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NexusAgentTheme.warmCoral)
                Text(strings.diagram)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(DiagramViewMode.allCases) { item in
                        Text(item == .diagram ? strings.diagram : strings.diagramSource).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 140)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(source, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(strings.copySource)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))

            Divider().opacity(0.3)

            if mode == .diagram && !renderFailed {
                NexusAgentMermaidWebView(source: source, isDark: colorScheme == .dark, errorScheme: errorScheme, onRenderError: {
                    renderFailed = true
                })
                .frame(minHeight: 180, idealHeight: 240, maxHeight: 420)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if renderFailed {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Text(strings.diagramRenderFailed)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(source)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                    }
                }
                .background(Color.black.opacity(0.25))
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A WKWebView rendering a Mermaid diagram with the copy of Mermaid the app
/// ships (`NexusAgentMermaidPage`). Nothing is fetched from the network.
struct NexusAgentMermaidWebView: NSViewRepresentable {
    let source: String
    let isDark: Bool
    /// The URL scheme the page goes to when the diagram cannot be drawn.
    let errorScheme: String
    let onRenderError: @MainActor () -> Void

    func makeCoordinator() -> NexusAgentMermaidNavigationDelegate {
        NexusAgentMermaidNavigationDelegate(errorScheme: errorScheme, onRenderError: onRenderError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = NexusAgentMermaidPage.makeWebView(script: NexusAgentMermaidPage.bundledScript)
        webView.navigationDelegate = context.coordinator
        loadDiagram(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.errorScheme = errorScheme
        context.coordinator.onRenderError = onRenderError
        loadDiagram(in: nsView)
    }

    private func loadDiagram(in webView: WKWebView) {
        NexusAgentMermaidPage.load(source: source, isDark: isDark, errorScheme: errorScheme, in: webView)
    }
}

/// A styled monospaced code container with language badge, line numbers, and copy button.
struct NexusAgentCodeBlockView: View {
    let language: String?
    let bodyText: String
    let strings: NexusAgentChatStrings
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language = language, !language.isEmpty {
                    Text(language.lowercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
                } else {
                    Text(strings.codeLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bodyText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? strings.copiedCode : strings.copy)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))

            Divider().opacity(0.3)

            let lines = bodyText.components(separatedBy: "\n")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(0..<lines.count, id: \.self) { idx in
                            Text("\(idx + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<lines.count, id: \.self) { idx in
                            Text(lines[idx].isEmpty ? " " : lines[idx])
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.primary)
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

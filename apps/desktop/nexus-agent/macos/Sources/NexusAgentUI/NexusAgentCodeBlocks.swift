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

/// A WKWebView rendering a Mermaid diagram via self-contained HTML.
struct NexusAgentMermaidWebView: NSViewRepresentable {
    let source: String
    let isDark: Bool
    /// The URL scheme the page goes to when the diagram cannot be drawn.
    let errorScheme: String
    let onRenderError: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(errorScheme: errorScheme, onRenderError: onRenderError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
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
        let escapedSource = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let theme = isDark ? "dark" : "default"
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          * { box-sizing: border-box; }
          body {
            margin: 0;
            padding: 16px;
            background: transparent;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            overflow: auto;
          }
          .mermaid {
            width: 100%;
            display: flex;
            justify-content: center;
          }
          svg {
            max-width: 100%;
            height: auto;
          }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <script>
          try {
            mermaid.initialize({
              startOnLoad: true,
              theme: '\(theme)',
              securityLevel: 'loose'
            });
          } catch(e) {
            window.location.href = "\(errorScheme)://error";
          }
        </script>
        </head>
        <body>
        <div class="mermaid">
        \(escapedSource)
        </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var errorScheme: String
        var onRenderError: @MainActor () -> Void

        init(errorScheme: String, onRenderError: @escaping @MainActor () -> Void) {
            self.errorScheme = errorScheme
            self.onRenderError = onRenderError
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onRenderError()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onRenderError()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == errorScheme {
                decisionHandler(.cancel)
                onRenderError()
                return
            }
            decisionHandler(.allow)
        }
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

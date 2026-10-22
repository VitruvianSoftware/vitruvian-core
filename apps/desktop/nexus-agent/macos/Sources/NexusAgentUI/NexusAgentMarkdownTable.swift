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


import NexusAgentCore
import SwiftUI

/// A GitHub-style table in a reply: a semibold header row, banded rows and
/// hairline rules. A table wider than the bubble scrolls sideways.
struct NexusAgentMarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    /// Each cell's text, as the bubble renders inline Markdown.
    let render: (String) -> AttributedString
    var isError = false

    private static let rule = Color.primary.opacity(0.1)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            table
            ScrollView(.horizontal, showsIndicators: true) {
                table.fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    cell(header, weight: .semibold, fill: Color.primary.opacity(0.06))
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        cell(value, weight: .regular, fill: index % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Self.rule, lineWidth: 0.5)
        )
    }

    private func cell(_ text: String, weight: Font.Weight, fill: Color) -> some View {
        Text(render(text))
            .font(.system(size: 12, weight: weight))
            .foregroundStyle(isError ? NexusAgentTheme.warmCoral : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(fill)
            .overlay(alignment: .trailing) { Rectangle().fill(Self.rule).frame(width: 0.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(Self.rule).frame(height: 0.5) }
    }
}

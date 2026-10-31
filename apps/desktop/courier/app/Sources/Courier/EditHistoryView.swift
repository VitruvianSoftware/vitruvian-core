// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// A message's earlier versions, below its bubble (01 §5's MessageEditHistory): each with when it was written, the
/// first as sent and the newest last. Nil while they are read.
struct EditHistoryView: View {
    let versions: [Version]?
    let mine: Bool
    var timeFormat: TimeFormatPreference = .system
    @State private var revealed = true

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            if let versions {
                ForEach(Array(versions.enumerated()), id: \.offset) { index, version in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(index, of: versions.count, at: version.ts))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        RichTextView(rich: version.rich, onBubble: false, revealed: $revealed, detectDates: false)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Edit history"))
    }

    private func label(_ index: Int, of count: Int, at ts: Int64) -> String {
        let time = timeFormat.formatDateTime(Date(timeIntervalSince1970: Double(ts) / 1000), dateStyle: .medium)
        if index == 0 { return String(localized: "Original, \(time)") }
        if index == count - 1 { return String(localized: "Current, \(time)") }
        return String(localized: "Edited \(time)")
    }
}

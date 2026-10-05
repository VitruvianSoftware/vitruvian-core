// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Saving keeps the picture visible: a scrim over the whole editor says
/// "this is hard for me", and it is not.
/// In a narrow window the band squeezes this chip; the bar gives way
/// first, so the words never wrap letter by letter.
package struct RecorderExportProgressChip: View {
    /// An upload has no fraction to show, only that it is under way.
    let uploading: Bool
    let progress: Double
    let label: String
    let cancelTitle: String
    let cancel: () -> Void

    package init(uploading: Bool, progress: Double, label: String, cancelTitle: String,
                 cancel: @escaping () -> Void) {
        self.uploading = uploading
        self.progress = progress
        self.label = label
        self.cancelTitle = cancelTitle
        self.cancel = cancel
    }

    package var body: some View {
        HStack(spacing: 8) {
            if uploading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20)
            } else {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(minWidth: 24, idealWidth: 110, maxWidth: 110)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.8))
                .fixedSize()
            Button(cancelTitle) { cancel() }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .transition(.opacity)
    }
}

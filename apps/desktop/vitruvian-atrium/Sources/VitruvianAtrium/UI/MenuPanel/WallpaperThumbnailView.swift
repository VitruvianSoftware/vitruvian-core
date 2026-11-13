// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

package struct WallpaperThumbnailView: View {
    package let image: NSImage?
    package var height: CGFloat = 54

    // Spelled out because a memberwise initializer never leaves its module.
    package init(image: NSImage?, height: CGFloat = 54) {
        self.image = image
        self.height = height
    }

    package var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // The cell owns its size; an aspect-fill image must not widen it.
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UniformTypeIdentifiers

/// `AppIconPrefsSubView.tsx` — grid of Courier's 8 clean-room vector app icons plus custom PNG/JPG/ICNS upload.
public struct AppIconPickerView: View {
    @ObservedObject public var appearance: AppearancePreferences
    @State private var errorMessage: String?

    public init(appearance: AppearancePreferences) {
        self.appearance = appearance
    }

    private let columns = [
        GridItem(.adaptive(minimum: 112, maximum: 140), spacing: 12),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CourierAppIconVariant.allCases) { variant in
                    iconTile(for: variant)
                }
            }

            HStack(spacing: 10) {
                Button(String(localized: "Choose Custom Icon…")) {
                    chooseCustomIcon()
                }
                .controlSize(.small)

                if appearance.selectedAppIcon != .classicTeal || appearance.customAppIconPath != nil {
                    Button(String(localized: "Reset to Default Icon")) {
                        errorMessage = nil
                        appearance.selectedAppIcon = .classicTeal
                    }
                    .controlSize(.small)
                }

                if let customPath = appearance.customAppIconPath, !customPath.isEmpty {
                    Text(URL(fileURLWithPath: customPath).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func iconTile(for variant: CourierAppIconVariant) -> some View {
        let isSelected = appearance.customAppIconPath == nil && appearance.selectedAppIcon == variant
        let nsImage = AppIconRenderer.renderIcon(variant: variant, size: 128)
        return Button {
            errorMessage = nil
            appearance.selectedAppIcon = variant
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .shadow(color: .black.opacity(0.14), radius: 3, y: 1)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 4, y: -4)
                    }
                }
                .padding(.top, 4)

                Text(variant.title)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(variant.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(variant.subtitle)
        .accessibilityLabel("\(variant.title), \(variant.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func chooseCustomIcon() {
        guard let urls = AppLockGate.shared.runOpenPanel(action: .settingsChange, configure: { panel in
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.png, .jpeg, .icns]
            panel.message = String(localized: "Choose a PNG, JPG, or ICNS image for Courier’s Dock icon")
            panel.prompt = String(localized: "Use Icon")
        }), let url = urls.first else {
            return
        }
        let previous = appearance.customAppIconPath
        appearance.customAppIconPath = url.path
        if appearance.customAppIconPath == previous && previous != url.path {
            errorMessage = AppIconApplyError.invalidImageFile(path: url.lastPathComponent).errorDescription
        } else {
            errorMessage = nil
        }
    }
}

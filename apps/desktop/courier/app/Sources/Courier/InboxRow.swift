// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// One chat in the inbox: avatar with its network badge, name, time, a preview and the unread count.
struct InboxRowView: View {
    let row: InboxRow
    let networkName: String

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(path: row.avatarPath, initials: row.initials, seed: row.name)
                .frame(width: 40, height: 40)
                .overlay(alignment: .bottomTrailing) {
                    NetworkBadge(network: row.network, name: networkName, size: 15)
                        .background(Circle().fill(.background))
                        .offset(x: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(RelativeTime.text(forMillis: row.lastTS))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 6) {
                    preview
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if row.muted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(String(localized: "Muted"))
                            .accessibilityLabel(String(localized: "Muted"))
                    }
                    if let badge = row.unreadBadge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(row.muted ? Color.gray.opacity(0.55) : Color.accentColor))
                            .accessibilityLabel(String(localized: "\(row.unread) unread"))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "You: " when the newest message is mine, then the kind's label if it is not text, then the text.
    private var preview: Text {
        var text = Text(verbatim: "")
        if row.previewMine { text = text + Text(String(localized: "You: ")) }
        if let label = row.previewLabel { text = text + Text(label.title).italic() }
        if !row.preview.isEmpty {
            text = text + Text(verbatim: row.previewLabel == nil ? row.preview : " " + row.preview)
        }
        return text
    }
}

extension PreviewLabel {
    var title: String {
        switch self {
        case .image: String(localized: "Image")
        case .video: String(localized: "Video")
        case .voiceNote: String(localized: "Voice note")
        case .file: String(localized: "File")
        case .sticker: String(localized: "Sticker")
        }
    }
}

/// A network's mark: an SF Symbol in the network's tint, named by its tooltip and accessibility label.
struct NetworkBadge: View {
    let network: String
    let name: String
    let size: CGFloat

    var body: some View {
        let look = NetworkAppearance.of(network)
        Image(systemName: look.symbol)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Color(red: look.red, green: look.green, blue: look.blue))
            .help(name)
            .accessibilityLabel(name)
    }
}

/// A chat's picture, or its initials on a colour taken from its name.
struct AvatarView: View {
    let path: String
    let initials: String
    let seed: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Self.color(for: seed))
                Text(initials)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: path) { image = await AvatarCache.shared.image(atPath: path) }
    }

    /// A colour that is the same for a name in every run (a Swift hash is not).
    static func color(for seed: String) -> Color {
        var hash: UInt32 = 5381
        for byte in seed.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.45, brightness: 0.62)
    }
}

/// Pictures already read from disk, so scrolling back does not read them again.
final class AvatarCache: @unchecked Sendable {
    static let shared = AvatarCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 400 }

    func image(atPath path: String) async -> NSImage? {
        guard !path.isEmpty else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let image = await Task.detached(priority: .utility) { NSImage(contentsOfFile: path) }.value
        if let image { cache.setObject(image, forKey: path as NSString) }
        return image
    }
}

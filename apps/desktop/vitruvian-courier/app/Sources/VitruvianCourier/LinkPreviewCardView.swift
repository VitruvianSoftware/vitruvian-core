// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import WebKit

/// Inline link preview card (`LinkPreviewItem`) rendered solely from bridge-supplied metadata and local media store files.
///
/// Never fetches the target URL or any remote image. Clicking the card opens the `http(s)` URL in the default browser.
public struct LinkPreviewCardView: View {
    public let preview: LinkPreviewItem
    public var onBubble: Bool
    public var onOpenURL: (URL) -> Void

    @State private var loadedCGImage: CGImage?

    public static let userVisibleStrings: [String] = [
        String(localized: "Link Preview"),
        String(localized: "Open Link"),
    ]

    public init(
        preview: LinkPreviewItem,
        onBubble: Bool = false,
        onOpenURL: @escaping (URL) -> Void = { url in
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
            _ = NSWorkspace.shared.open(url)
        }
    ) {
        self.preview = preview
        self.onBubble = onBubble
        self.onOpenURL = onOpenURL
    }

    private var targetURL: URL? {
        let raw = (preview.url?.isEmpty == false ? preview.url : preview.matchedURL) ?? ""
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }

    private var domainHeader: String {
        if let siteName = preview.siteName?.trimmingCharacters(in: .whitespacesAndNewlines), !siteName.isEmpty {
            return siteName
        }
        if let host = targetURL?.host?.lowercased(), !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return String(localized: "Link Preview")
    }

    private var displayTitle: String {
        if let title = preview.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return targetURL?.absoluteString ?? domainHeader
    }

    private var displayDescription: String? {
        guard let desc = preview.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty else {
            return nil
        }
        return desc
    }

    private var localThumbnailPath: String? {
        guard let path = preview.imagePath, isLocalMediaStorePath(path) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        return path
    }

    private var synchronousLocalThumbnail: NSImage? {
        guard let path = localThumbnailPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    public var body: some View {
        Button {
            if let url = targetURL {
                onOpenURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let cgImage = loadedCGImage {
                    Image(decorative: cgImage, scale: 2)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 320, minHeight: 120, maxHeight: 148)
                        .clipped()
                } else if let nsImage = synchronousLocalThumbnail {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 320, minHeight: 120, maxHeight: 148)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(onBubble ? Color.white.opacity(0.78) : Color.secondary)
                        Text(domainHeader)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(onBubble ? Color.white.opacity(0.78) : Color.secondary)
                            .lineLimit(1)
                    }

                    Text(displayTitle)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(onBubble ? Color.white : Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let description = displayDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(onBubble ? Color.white.opacity(0.85) : Color.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 320, alignment: .leading)
            }
            .frame(maxWidth: 320, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(onBubble ? Color.black.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(onBubble ? Color.white.opacity(0.22) : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .task(id: preview.imagePath) {
            loadedCGImage = nil
            guard let path = localThumbnailPath else { return }
            if let thumbnail = await ThumbnailLoader.shared.thumbnail(atPath: path) {
                loadedCGImage = thumbnail.image
            }
        }
        .help(targetURL?.absoluteString ?? String(localized: "Open Link"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(domainHeader): \(displayTitle)")
    }
}

/// Identifies an external media embed (YouTube, Vimeo, Spotify, or Loom) and its canonical embed URL.
public struct ExternalEmbedDescriptor: Equatable, Sendable {
    public let host: String
    public let originalURL: URL
    public let embedURL: URL

    public init(host: String, originalURL: URL, embedURL: URL) {
        self.host = host
        self.originalURL = originalURL
        self.embedURL = embedURL
    }

    /// Returns a descriptor when `urlString` matches an embeddable YouTube, Vimeo, Spotify, or Loom link.
    public static func match(urlString: String) -> ExternalEmbedDescriptor? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let rawHost = url.host?.lowercased()
        else {
            return nil
        }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let pathParts = url.pathComponents.filter { $0 != "/" }

        // YouTube: youtube.com/watch?v=<id>, youtube.com/embed/<id>, youtube.com/shorts/<id>, youtu.be/<id>
        if host == "youtube.com" || host == "m.youtube.com" || host == "youtube-nocookie.com" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let videoID = comps?.queryItems?.first(where: { $0.name == "v" })?.value,
               Self.isSafeEmbedToken(videoID),
               let embed = URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)") {
                return ExternalEmbedDescriptor(host: "youtube.com", originalURL: url, embedURL: embed)
            }
            if pathParts.count >= 2, (pathParts[0] == "embed" || pathParts[0] == "shorts"),
               Self.isSafeEmbedToken(pathParts[1]),
               let embed = URL(string: "https://www.youtube-nocookie.com/embed/\(pathParts[1])") {
                return ExternalEmbedDescriptor(host: "youtube.com", originalURL: url, embedURL: embed)
            }
        } else if host == "youtu.be", let videoID = pathParts.first,
                  Self.isSafeEmbedToken(videoID),
                  let embed = URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)") {
            return ExternalEmbedDescriptor(host: "youtube.com", originalURL: url, embedURL: embed)
        }

        // Vimeo: vimeo.com/<id> or player.vimeo.com/video/<id>
        if host == "vimeo.com", let videoID = pathParts.first,
           videoID.allSatisfy(\.isNumber),
           let embed = URL(string: "https://player.vimeo.com/video/\(videoID)") {
            return ExternalEmbedDescriptor(host: "vimeo.com", originalURL: url, embedURL: embed)
        } else if host == "player.vimeo.com", pathParts.count >= 2, pathParts[0] == "video",
                  Self.isSafeEmbedToken(pathParts[1]),
                  let embed = URL(string: "https://player.vimeo.com/video/\(pathParts[1])") {
            return ExternalEmbedDescriptor(host: "vimeo.com", originalURL: url, embedURL: embed)
        }

        // Spotify: open.spotify.com/{track,album,playlist,episode,show}/<id>
        if host == "open.spotify.com" || host == "spotify.com" {
            if pathParts.count >= 2,
               ["track", "album", "playlist", "episode", "show"].contains(pathParts[0]),
               Self.isSafeEmbedToken(pathParts[1]),
               let embed = URL(string: "https://open.spotify.com/embed/\(pathParts[0])/\(pathParts[1])") {
                return ExternalEmbedDescriptor(host: "open.spotify.com", originalURL: url, embedURL: embed)
            }
        }

        // Loom: loom.com/share/<id> or loom.com/embed/<id>
        if host == "loom.com", pathParts.count >= 2,
           (pathParts[0] == "share" || pathParts[0] == "embed"),
           Self.isSafeEmbedToken(pathParts[1]),
           let embed = URL(string: "https://www.loom.com/embed/\(pathParts[1])") {
            return ExternalEmbedDescriptor(host: "loom.com", originalURL: url, embedURL: embed)
        }

        return nil
    }

    /// Finds the first embeddable media link in a timeline message's link previews or rich text entities.
    public static func first(in message: TimelineMessage) -> ExternalEmbedDescriptor? {
        for preview in message.linkPreviews {
            if let url = preview.url, let matched = match(urlString: url) {
                return matched
            }
            if let matched = match(urlString: preview.matchedURL) {
                return matched
            }
        }
        for entity in message.rich.entities where entity.kind == .link {
            if let url = entity.url, let matched = match(urlString: url) {
                return matched
            }
        }
        return nil
    }

    private static func isSafeEmbedToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.count <= 64 else { return false }
        return token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

/// Privacy-gated external embed placeholder and sandboxed loader (`MessageIFrame.tsx`).
///
/// Until the person clicks **Load Embed** (when `loadExternalEmbedsAutomatically == false`), no `WKWebView` is
/// instantiated at all. Once loaded, the `WKWebView` runs with a non-persistent `WKWebsiteDataStore` and blocks
/// navigation away from the embed URL.
public struct EmbedConsentCard: View {
    public let messageID: String
    public let descriptor: ExternalEmbedDescriptor
    public let isLoaded: Bool
    public var onBubble: Bool
    public let onLoadEmbed: () -> Void
    public var onOpenURL: (URL) -> Void

    public static let userVisibleStrings: [String] = [
        String(localized: "Load embed from youtube.com"),
        String(localized: "External embed from youtube.com is blocked to protect your IP address"),
        String(localized: "Load Embed"),
        String(localized: "Open in Browser"),
    ]

    public init(
        messageID: String,
        descriptor: ExternalEmbedDescriptor,
        isLoaded: Bool,
        onBubble: Bool = false,
        onLoadEmbed: @escaping () -> Void,
        onOpenURL: @escaping (URL) -> Void = { url in
            _ = NSWorkspace.shared.open(url)
        }
    ) {
        self.messageID = messageID
        self.descriptor = descriptor
        self.isLoaded = isLoaded
        self.onBubble = onBubble
        self.onLoadEmbed = onLoadEmbed
        self.onOpenURL = onOpenURL
    }

    public var body: some View {
        if isLoaded {
            VStack(alignment: .leading, spacing: 6) {
                SandboxedEmbedWebView(embedURL: descriptor.embedURL)
                    .frame(width: 300, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 6) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.caption2)
                        .foregroundStyle(onBubble ? Color.white.opacity(0.8) : Color.secondary)
                    Text(descriptor.host)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(onBubble ? Color.white.opacity(0.8) : Color.secondary)
                    Spacer(minLength: 4)
                    Button(String(localized: "Open in Browser")) {
                        onOpenURL(descriptor.originalURL)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
            .padding(4)
            .frame(maxWidth: 320, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(onBubble ? Color.black.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(onBubble ? Color.white.opacity(0.22) : Color.primary.opacity(0.12), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(onBubble ? 0.28 : 0.14))
                            .frame(width: 30, height: 30)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(onBubble ? Color.white : Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Load embed from \(descriptor.host)"))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(onBubble ? Color.white : Color.primary)
                        Text(String(localized: "External embed from \(descriptor.host) is blocked to protect your IP address"))
                            .font(.caption)
                            .foregroundStyle(onBubble ? Color.white.opacity(0.82) : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    Button(action: onLoadEmbed) {
                        Label(String(localized: "Load Embed"), systemImage: "play.rectangle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        onOpenURL(descriptor.originalURL)
                    } label: {
                        Label(String(localized: "Open in Browser"), systemImage: "safari")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .frame(maxWidth: 320, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(onBubble ? Color.black.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(onBubble ? Color.white.opacity(0.22) : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Load embed from \(descriptor.host)"))
        }
    }

    /// Recursively checks whether `view` or any of its descendants is a `WKWebView`.
    @MainActor
    public static func containsWebView(in view: NSView) -> Bool {
        if view is WKWebView {
            return true
        }
        for child in view.subviews where containsWebView(in: child) {
            return true
        }
        return false
    }
}

/// Ephemeral, navigation-locked `WKWebView` created only after explicit user consent.
public struct SandboxedEmbedWebView: NSViewRepresentable {
    public let embedURL: URL

    public init(embedURL: URL) {
        self.embedURL = embedURL
    }

    /// Builds a `WKWebViewConfiguration` using a non-persistent data store (no cookies or cache persisted).
    @MainActor
    public static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        return config
    }

    /// Returns true only when `targetURL` stays on the allowed `embedURL` host and path prefix.
    public static func shouldAllowNavigation(targetURL: URL?, embedURL: URL) -> Bool {
        guard let targetURL else { return false }
        if targetURL.absoluteString == "about:blank" {
            return true
        }
        guard let scheme = targetURL.scheme?.lowercased(),
              scheme == "https",
              let targetHost = targetURL.host?.lowercased(),
              let allowedHost = embedURL.host?.lowercased()
        else {
            return false
        }
        return targetHost == allowedHost
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(embedURL: embedURL)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: embedURL))
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.embedURL != embedURL {
            context.coordinator.embedURL = embedURL
            nsView.load(URLRequest(url: embedURL))
        }
    }

    public final class Coordinator: NSObject, WKNavigationDelegate {
        var embedURL: URL

        init(embedURL: URL) {
            self.embedURL = embedURL
        }

        public func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if SandboxedEmbedWebView.shouldAllowNavigation(
                targetURL: navigationAction.request.url,
                embedURL: embedURL
            ) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

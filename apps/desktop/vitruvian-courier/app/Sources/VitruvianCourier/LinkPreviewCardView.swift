// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import WebKit

/// Inline link preview card (`LinkPreviewItem`) rendered solely from bridge-supplied metadata and local media store files.
///
/// Never fetches the target URL or any remote image. Clicking the card opens the `http(s)` URL in the default browser.
public struct LinkPreviewCardView: View {
    private struct LoadedThumbnail {
        let path: String
        let image: CGImage
    }

    public let preview: LinkPreviewItem
    public var onBubble: Bool
    public var onOpenURL: (URL) -> Void

    /// Read in `body`, so the card draws again when the table learns something about its files.
    @Environment(\.timelineContentRevision) private var contentRevision
    @State private var loaded: LoadedThumbnail?
    /// Counts the file facts learned for the picture, so its load starts when the file is known to be there.
    @State private var factTick = 0

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

    /// The picture's path once it is known to be on disk. Asked of memory (`LocalFileFacts`), never of the disk, so
    /// laying out or measuring the card does not wait on a file; the answer arrives with `didLearnSizeNotification`.
    private var localThumbnailPath: String? {
        guard let path = preview.imagePath, isLocalMediaStorePath(path),
              LocalFileFacts.exists(path) == true else { return nil }
        return path
    }

    private var currentCGImage: CGImage? {
        guard let path = localThumbnailPath else { return nil }
        if loaded?.path == path, let img = loaded?.image { return img }
        return ThumbnailLoader.shared.cachedThumbnail(atPath: path)?.image
    }

    /// The picture's height: it fills the card's width, so it follows the picture's own proportions within 120–148 pt.
    /// The size is asked of memory (`ImagePixelSizeReader.cachedSize`, warmed with the page) or the wire's; a picture of
    /// no known size is the tallest. The same loaded or not, so the card does not change height when it arrives.
    private var thumbnailHeight: CGFloat {
        let size: CGSize? = preview.imagePath.flatMap { ImagePixelSizeReader.cachedSize(ofFirstReadable: [$0]) }
            ?? {
                guard let w = preview.imageWidth, let h = preview.imageHeight, w > 0, h > 0 else { return nil }
                return CGSize(width: w, height: h)
            }()
        guard let size, size.width > 0, size.height > 0 else { return 148 }
        return min(148, max(120, 320 * size.height / size.width))
    }

    public var body: some View {
        let _ = contentRevision
        Button {
            if let url = targetURL {
                onOpenURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if localThumbnailPath != nil {
                    if let cgImage = currentCGImage {
                        Image(decorative: cgImage, scale: 2)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 320)
                            .frame(height: thumbnailHeight)
                            .clipped()
                    } else {
                        Color.clear
                            .frame(maxWidth: 320)
                            .frame(height: thumbnailHeight)
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: ImagePixelSizeReader.didLearnSizeNotification)) { note in
            if let path = note.userInfo?[ImagePixelSizeReader.pathUserInfoKey] as? String, path == preview.imagePath {
                factTick += 1
            }
        }
        .task(id: "\(preview.imagePath ?? "")#\(factTick)") {
            guard let path = localThumbnailPath else { return }
            // Its size sizes the card; reading it announces it, and a table timeline re-measures the row.
            _ = await ImagePixelSizeReader.shared.size(ofFirstReadable: [path])
            if let cached = ThumbnailLoader.shared.cachedThumbnail(atPath: path)?.image {
                loaded = LoadedThumbnail(path: path, image: cached)
            } else if let thumbnail = await ThumbnailLoader.shared.thumbnail(atPath: path) {
                loaded = LoadedThumbnail(path: path, image: thumbnail.image)
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

    /// The YouTube video's ID, read from the embed address; nil for every other site.
    public var youTubeVideoID: String? {
        guard host == "youtube.com", embedURL.pathComponents.count >= 3, embedURL.pathComponents[1] == "embed" else { return nil }
        return embedURL.pathComponents[2]
    }

    /// The video's still picture on YouTube, when this is a YouTube link.
    public var remoteThumbnailURL: URL? { youTubeVideoID.flatMap(EmbedThumbnail.youTubeURL(videoID:)) }

    /// The picture the message's own preview for this link carries, when it has been saved on this Mac.
    public static func previewImagePath(in message: TimelineMessage) -> String? {
        guard let path = message.linkPreviews.first(where: isEmbedPreview)?.imagePath, !path.isEmpty,
              isLocalMediaStorePath(path) else { return nil }
        return path
    }

    public init(host: String, originalURL: URL, embedURL: URL) {
        self.host = host
        self.originalURL = originalURL
        self.embedURL = embedURL
    }

    /// The site as people say it ("YouTube"), for the card's second line.
    public var siteName: String {
        switch host {
        case "youtube.com": "YouTube"
        case "vimeo.com": "Vimeo"
        case "open.spotify.com": "Spotify"
        case "loom.com": "Loom"
        default: host
        }
    }

    /// What the card says when nothing better is known about the link: what it is, on which site.
    public var fallbackTitle: String {
        host == "open.spotify.com"
            ? String(localized: "Listen on \(siteName)")
            : String(localized: "Watch on \(siteName)")
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

    /// Finds the first embeddable media link in a timeline message's link previews, rich text entities, or plain text.
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
        let nsText = message.rich.text as NSString
        if nsText.length > 0 {
            let range = NSRange(location: 0, length: nsText.length)
            for matchResult in SharedLinkDetector.matches(in: message.rich.text, options: [], range: range) {
                if let url = matchResult.url, let matched = match(urlString: url.absoluteString) {
                    return matched
                }
            }
        }
        return nil
    }

    /// Whether a network-supplied preview is for an embeddable link: the embed card stands for it.
    public static func isEmbedPreview(_ preview: LinkPreviewItem) -> Bool {
        match(urlString: preview.url ?? "") != nil || match(urlString: preview.matchedURL) != nil
    }

    /// The previews a message draws as link cards. A link with an embed card (YouTube and the like) gets that one
    /// card, not a second for the same link: its preview is left out here and its title goes on the embed card.
    public static func cardPreviews(in message: TimelineMessage) -> [LinkPreviewItem] {
        guard first(in: message) != nil else { return message.linkPreviews }
        return message.linkPreviews.filter { !isEmbedPreview($0) }
    }

    /// The title the network's preview gives the embedded link, for the embed card to carry.
    public static func embedTitle(in message: TimelineMessage) -> String? {
        message.linkPreviews.first(where: isEmbedPreview)?.title
    }

    private static func isSafeEmbedToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.count <= 64 else { return false }
        return token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

/// Privacy-gated external embed placeholder and sandboxed loader (`MessageIFrame.tsx`).
///
/// Until the person clicks the card (when `loadExternalEmbedsAutomatically == false`), no `WKWebView` is
/// instantiated at all. The card is a compact preview (a play glyph, a title, the site); its tooltip says the embed
/// is held back to protect the person's IP address, and clicking it loads the embed. Once loaded, the `WKWebView`
/// runs with a non-persistent `WKWebsiteDataStore` and blocks navigation away from the embed URL.
public struct EmbedConsentCard: View {
    /// The theme's accent, never the system one (which can be red).
    @Environment(\.themeAccentColor) private var themeAccent
    public let messageID: String
    public let descriptor: ExternalEmbedDescriptor
    public let isLoaded: Bool
    /// The link's title when the message already carries one (a preview its network sent); else the card names the site.
    public var title: String?
    /// A picture the link's preview already saved on this Mac; drawn without any request.
    public var previewImagePath: String?
    /// Whether the video's picture and title may be fetched from YouTube (that tells YouTube this Mac's address). The
    /// message row passes "Show link previews"; "Load external embeds automatically" only decides whether the player
    /// itself loads (`LinkPreviewPolicy`).
    /// Off (the default here), the card uses the picture and title the network's own preview saved on this Mac, else
    /// the tinted placeholder and the stand-in title, and asks for nothing.
    public var allowsRemoteThumbnail: Bool
    /// Where a fetched picture comes from (the shared session unless a test supplies its own).
    public var session: URLSession
    /// Gets a video's picture; the default asks YouTube through `session`. A test supplies its own.
    public var fetchPicture: (@Sendable (String) async -> CGImage?)?
    /// Gets a video's title and channel; the default asks YouTube oEmbed through `session`. A test supplies its own.
    public var fetchMetadata: (@Sendable (String) async -> YouTubeMetadata?)?
    public var onBubble: Bool
    /// The last picture loaded, tagged with the source it was loaded for. It is drawn only while that source is
    /// still the card's current one, so a late answer for an earlier video can never show.
    @State private var loaded: (source: String, image: CGImage)?
    @State private var loadedMetadata: (source: String, metadata: YouTubeMetadata)?
    private var thumbnail: CGImage? {
        if let hit = Self.visibleThumbnail(loaded, currentSource: thumbnailSource) { return hit }
        if allowsRemoteThumbnail, previewImagePath == nil, let id = descriptor.youTubeVideoID {
            return EmbedThumbnail.cachedThumbnail(videoID: id)
        }
        return nil
    }

    /// The picture to draw: only one loaded for the card's current source.
    static func visibleThumbnail(_ loaded: (source: String, image: CGImage)?, currentSource: String) -> CGImage? {
        guard let loaded, !loaded.source.isEmpty, loaded.source == currentSource else { return nil }
        return loaded.image
    }
    public let onLoadEmbed: () -> Void
    public var onOpenURL: (URL) -> Void

    public static let userVisibleStrings: [String] = [
        String(localized: "Watch on YouTube"),
        String(localized: "Listen on Spotify"),
        String(localized: "External embed from youtube.com is blocked to protect your IP address. Click to load it."),
        String(localized: "Open in Browser"),
    ]

    public init(
        messageID: String,
        descriptor: ExternalEmbedDescriptor,
        isLoaded: Bool,
        title: String? = nil,
        previewImagePath: String? = nil,
        allowsRemoteThumbnail: Bool = false,
        session: URLSession = .shared,
        fetchPicture: (@Sendable (String) async -> CGImage?)? = nil,
        fetchMetadata: (@Sendable (String) async -> YouTubeMetadata?)? = nil,
        onBubble: Bool = false,
        onLoadEmbed: @escaping () -> Void,
        onOpenURL: @escaping (URL) -> Void = { url in
            _ = NSWorkspace.shared.open(url)
        }
    ) {
        self.messageID = messageID
        self.descriptor = descriptor
        self.isLoaded = isLoaded
        self.title = title
        self.previewImagePath = previewImagePath
        self.allowsRemoteThumbnail = allowsRemoteThumbnail
        self.session = session
        self.fetchPicture = fetchPicture
        self.fetchMetadata = fetchMetadata
        self.onBubble = onBubble
        self.onLoadEmbed = onLoadEmbed
        self.onOpenURL = onOpenURL
    }

    private var trimmedBridgeTitle: String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title
    }

    private var currentMetadata: YouTubeMetadata? {
        let source = metadataSource
        guard allowsRemoteThumbnail, !source.isEmpty else { return nil }
        if let loadedMetadata, loadedMetadata.source == source {
            return loadedMetadata.metadata
        }
        if let id = descriptor.youTubeVideoID {
            return EmbedThumbnail.cachedMetadata(videoID: id)
        }
        return nil
    }

    private var displayTitle: String {
        if let bridgeTitle = trimmedBridgeTitle { return bridgeTitle }
        if let oembedTitle = currentMetadata?.title { return oembedTitle }
        return descriptor.fallbackTitle
    }

    private var displaySubtitle: String {
        if let channel = currentMetadata?.authorName, !channel.isEmpty {
            return "\(channel) · \(descriptor.siteName)"
        }
        return displayTitle == descriptor.fallbackTitle ? descriptor.host : descriptor.siteName
    }

    /// What picture the card would draw, so the load restarts when it changes (empty: none).
    private var thumbnailSource: String {
        if let path = previewImagePath, isLocalMediaStorePath(path) { return path }
        if allowsRemoteThumbnail, let id = descriptor.youTubeVideoID, EmbedThumbnail.youTubeURL(videoID: id) != nil {
            return "youtube:\(id)"
        }
        return ""
    }

    /// What metadata the card needs to fetch via YouTube oEmbed when the bridge gave no title (empty: none).
    private var metadataSource: String {
        guard trimmedBridgeTitle == nil,
              allowsRemoteThumbnail,
              let id = descriptor.youTubeVideoID,
              EmbedThumbnail.youTubeOEmbedURL(videoID: id) != nil
        else { return "" }
        return "youtube-oembed:\(id)"
    }

    /// Reads a saved preview picture (through the shared small-picture cache) or, when allowed, fetches the video's.
    /// A result that arrives after the card moved on to another picture, or was left, is dropped.
    @MainActor
    private func loadThumbnail() async {
        let source = thumbnailSource
        guard !source.isEmpty else { return }
        var image: CGImage?
        if let path = previewImagePath, isLocalMediaStorePath(path) {
            image = await ThumbnailLoader.shared.thumbnail(atPath: path)?.image
        }
        if image == nil, allowsRemoteThumbnail, let id = descriptor.youTubeVideoID, !Task.isCancelled {
            if let fetchPicture {
                image = await fetchPicture(id)
            } else {
                image = await EmbedThumbnail.fetch(videoID: id, showLinkPreviews: allowsRemoteThumbnail, session: session)
            }
        }
        guard !Task.isCancelled, let image else { return }
        loaded = (source, image)
    }

    /// Fetches the video's title and channel (YouTube oEmbed) when the network's preview gave no title. Like the
    /// picture, an answer for an earlier video is tagged with its own source, so it is never drawn on another card.
    @MainActor
    private func loadMetadata() async {
        let source = metadataSource
        guard !source.isEmpty, let id = descriptor.youTubeVideoID else { return }
        let metadata: YouTubeMetadata?
        if let fetchMetadata {
            metadata = await fetchMetadata(id)
        } else {
            metadata = await EmbedThumbnail.fetchMetadata(videoID: id, showLinkPreviews: allowsRemoteThumbnail, session: session)
        }
        guard !Task.isCancelled, let metadata else { return }
        loadedMetadata = (source, metadata)
    }

    /// The widest the card is, and so the widest a bubble holding it is.
    public static let maxWidth: CGFloat = 480

    /// The video's still, 16:9 across the full width of the card, with the play glyph over it. While the picture
    /// loads, or if it never comes, a calm tinted box of the same shape stands in, so the card does not jump.
    private var picture: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle().fill(themeAccent.opacity(onBubble ? 0.30 : 0.16))
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                    Image(systemName: "play.fill")
                        .font(.system(size: thumbnail == nil ? 22 : 20, weight: .semibold))
                        .foregroundStyle(thumbnail == nil && !onBubble ? themeAccent : Color.white)
                        .shadow(color: .black.opacity(thumbnail == nil ? 0 : 0.6), radius: 3)
                }
            }
            .clipped()
    }

    private var tooltip: String {
        String(localized: "External embed from \(descriptor.host) is blocked to protect your IP address. Click to load it.")
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
            Button(action: onLoadEmbed) {
                VStack(alignment: .leading, spacing: 0) {
                    picture
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(onBubble ? Color.white : Color.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        // The site's name (with channel when oEmbed provided it) under a real title; under the stand-in title, the address.
                        Text(displaySubtitle)
                            .font(.caption)
                            .foregroundStyle(onBubble ? Color.white.opacity(0.78) : Color.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(minWidth: 0, idealWidth: Self.maxWidth, maxWidth: Self.maxWidth, alignment: .leading)
                .background(onBubble ? Color.black.opacity(0.18) : Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(onBubble ? Color.white.opacity(0.22) : Color.primary.opacity(0.12), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .task(id: thumbnailSource) { await loadThumbnail() }
            .task(id: metadataSource) { await loadMetadata() }
            .help(tooltip)
            .contextMenu {
                Button(String(localized: "Open in Browser")) { onOpenURL(descriptor.originalURL) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(descriptor.siteName): \(displayTitle)")
            .accessibilityHint(tooltip)
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

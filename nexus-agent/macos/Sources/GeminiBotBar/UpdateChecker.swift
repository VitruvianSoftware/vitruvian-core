import Foundation
import AppKit

/// Checks GitHub Releases for newer versions and handles download-and-replace updates.
@MainActor
class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion = ""
    @Published var releaseURL: URL?
    @Published var releaseNotes = ""
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    @Published var isInstalling = false
    @Published var errorMessage: String?
    @Published var dismissed = false

    private var downloadAssetURL: URL?

    func checkForUpdates() async {
        let urlString = "https://api.github.com/repos/\(appRepoOwner)/\(appRepoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }
            
            if httpResponse.statusCode != 200 {
                // If it's a 404, the repo might be private or there are no releases yet.
                throw URLError(.badServerResponse)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            // Extract just the semantic version from tags like "gemini-telegram-bot-v1.4.0"
            let remoteVersion = extractVersion(from: tagName)

            if isNewerVersion(remote: remoteVersion, current: appVersion) {
                latestVersion = remoteVersion
                releaseURL = URL(string: htmlURL)
                releaseNotes = (json["body"] as? String) ?? ""
                dismissed = false

                // Find the universal ZIP asset for auto-update
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.contains("universal") && name.hasSuffix(".zip"),
                           let downloadURL = asset["browser_download_url"] as? String {
                            downloadAssetURL = URL(string: downloadURL)
                            break
                        }
                    }
                }

                updateAvailable = true
            } else {
                updateAvailable = false
            }
        } catch {
            errorMessage = "Update check failed: \(error.localizedDescription)"
        }
    }
    
    private func extractVersion(from tag: String) -> String {
        // Find the first occurrence of a digit followed by dots (e.g. "1.4.0")
        if let range = tag.range(of: "\\d+\\.\\d+\\.\\d+", options: .regularExpression) {
            return String(tag[range])
        }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Download the latest release and replace the current app bundle.
    func downloadAndInstall() async {
        // If assets were still uploading during the initial check, try to fetch them again now
        if downloadAssetURL == nil {
            isDownloading = true
            errorMessage = "Fetching release assets…"
            await checkForUpdates() // Re-runs the API check
            
            // Wait up to 5 seconds for asset processing just in case we need a tiny breather
            if downloadAssetURL == nil {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await checkForUpdates()
            }
        }
        
        guard let assetURL = downloadAssetURL else {
            // Fallback: open browser to release page if STILL no assets
            errorMessage = nil
            isDownloading = false
            if let url = releaseURL {
                NSWorkspace.shared.open(url)
            }
            return
        }

        isDownloading = true
        errorMessage = nil
        downloadProgress = 0

        do {
            // Download to temp
            let (tempURL, _) = try await downloadWithProgress(url: assetURL)

            isDownloading = false
            isInstalling = true

            // Unzip
            let extractDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("GeminiBotBar-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", tempURL.path, "-d", extractDir.path]
            unzipProcess.standardOutput = FileHandle.nullDevice
            unzipProcess.standardError = FileHandle.nullDevice
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                throw UpdateError.extractionFailed
            }

            // Find the .app in extracted contents
            let newAppURL = extractDir.appendingPathComponent("GeminiBotBar.app")
            guard FileManager.default.fileExists(atPath: newAppURL.path) else {
                throw UpdateError.appNotFound
            }

            // Determine where the current app is running from
            let currentBundle = Bundle.main.bundleURL
            // Strategy: replace the app bundle, then relaunch
            let targetURL: URL
            if currentBundle.pathExtension == "app" {
                // Running from a .app bundle — replace in-place
                targetURL = currentBundle
            } else {
                // Running from swift build — install to /Applications
                targetURL = URL(fileURLWithPath: "/Applications/GeminiBotBar.app")
            }

            // Backup current if it exists
            let backupURL = targetURL.deletingLastPathComponent()
                .appendingPathComponent("GeminiBotBar.app.bak")
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
            }
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.moveItem(at: targetURL, to: backupURL)
            }

            // Move new app into place
            try FileManager.default.moveItem(at: newAppURL, to: targetURL)

            // Clean up backup
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: extractDir)

            isInstalling = false

            // Relaunch from the new location
            relaunch(at: targetURL)

        } catch {
            isDownloading = false
            isInstalling = false
            errorMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    private func downloadWithProgress(url: URL) async throws -> (URL, URLResponse) {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        let totalBytes = response.expectedContentLength
        var data = Data()
        data.reserveCapacity(totalBytes > 0 ? Int(totalBytes) : 10_000_000)

        var bytesReceived: Int64 = 0
        for try await byte in asyncBytes {
            data.append(byte)
            bytesReceived += 1
            if totalBytes > 0, bytesReceived % 65536 == 0 {
                downloadProgress = Double(bytesReceived) / Double(totalBytes)
            }
        }
        downloadProgress = 1.0

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeminiBotBar-\(latestVersion).zip")
        try data.write(to: tempFile)
        return (tempFile, response)
    }

    private func relaunch(at appURL: URL) {
        // Use a shell script to wait for us to exit, then open the new app
        let script = """
        sleep 1
        open "\(appURL.path)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()

        // Terminate current app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    /// Semantic version comparison (supports major.minor.patch)
    private func isNewerVersion(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, currentParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}

enum UpdateError: LocalizedError {
    case extractionFailed
    case appNotFound

    var errorDescription: String? {
        switch self {
        case .extractionFailed: return "Failed to extract update archive"
        case .appNotFound: return "Could not find app in update archive"
        }
    }
}

import AppKit
import Foundation

/// Looks up the latest GitHub release and replaces this app with the disk image.
@MainActor
enum AppUpdateChecker {
    private static let owner = "wolfromkev"
    private static let repo = "umbrella-helper"
    private static let assetName = "Umbrella-Helper.dmg"
    private static var isBusy = false

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func prompt() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                guard let release = try await fetchNewerRelease() else {
                    inform(
                        "You’re up to date",
                        "Umbrella Helper \(currentVersion) is the latest release."
                    )
                    return
                }
                guard confirmInstall(of: release.version) else { return }
                try await downloadAndInstall(release)
            } catch {
                inform("Couldn’t update", error.localizedDescription)
            }
        }
    }

    private static func fetchNewerRelease() async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("UmbrellaHelper", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.badResponse
        }
        if http.statusCode == 404 {
            throw UpdateError.noRelease
        }
        guard (200...299).contains(http.statusCode) else {
            throw UpdateError.badResponse
        }

        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = payload.assets.first(where: { $0.name == assetName }) else {
            throw UpdateError.noRelease
        }
        guard isTrustedDownload(asset.browserDownloadURL) else {
            throw UpdateError.untrustedURL
        }

        let remote = normalizedVersion(payload.tagName)
        guard isNewer(remote, than: normalizedVersion(currentVersion)) else {
            return nil
        }
        return Release(version: remote, downloadURL: asset.browserDownloadURL)
    }

    private static func downloadAndInstall(_ release: Release) async throws {
        let downloaded = try await download(release.downloadURL)
        let mount = FileManager.default.temporaryDirectory
            .appendingPathComponent("umbrella-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)

        do {
            try mountImage(downloaded, at: mount)
        } catch {
            try? FileManager.default.removeItem(at: mount)
            throw error
        }

        let source = mount.appendingPathComponent("Umbrella Helper.app")
        guard FileManager.default.fileExists(atPath: source.path),
              bundleIdentifier(of: source) == "com.kevinwolfrom.umbrella" else {
            eject(mount)
            throw UpdateError.appMissing
        }

        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            eject(mount)
            throw UpdateError.notWritable
        }

        scheduleReplace(source: source, destination: destination, mount: mount)
        NSApp.terminate(nil)
    }

    private static func download(_ url: URL) async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Umbrella-Helper-update.dmg")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    private static func mountImage(_ image: URL, at mount: URL) throws {
        let diskutil = Process()
        diskutil.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        diskutil.arguments = [
            "image", "attach",
            "--readOnly",
            "--nobrowse",
            "--mountPoint", mount.path,
            image.path,
        ]
        let pipe = Pipe()
        diskutil.standardError = pipe
        try diskutil.run()
        diskutil.waitUntilExit()
        guard diskutil.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError.mountFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func scheduleReplace(source: URL, destination: URL, mount: URL) {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("umbrella-update-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        set -euo pipefail
        SOURCE=\(shellQuote(source.path))
        DEST=\(shellQuote(destination.path))
        MOUNT=\(shellQuote(mount.path))
        PID=\(ProcessInfo.processInfo.processIdentifier)
        while kill -0 "$PID" 2>/dev/null; do
          sleep 0.2
        done
        sleep 0.4
        rm -rf "$DEST"
        ditto "$SOURCE" "$DEST"
        xattr -cr "$DEST"
        diskutil eject "$MOUNT" >/dev/null 2>&1 || true
        open "$DEST"
        rm -f "$0"
        """
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [
            "-c",
            "nohup /bin/bash \(shellQuote(scriptURL.path)) >/tmp/umbrella-update.log 2>&1 &",
        ]
        try? task.run()
        task.waitUntilExit()
    }

    private static func eject(_ mount: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["eject", mount.path]
        try? task.run()
        task.waitUntilExit()
    }

    private static func bundleIdentifier(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) else { return nil }
        return info["CFBundleIdentifier"] as? String
    }

    private static func isTrustedDownload(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "github.com" else { return false }
        let prefix = "/\(owner)/\(repo)/releases/download/"
        return url.path.hasPrefix(prefix) && url.path.hasSuffix("/\(assetName)")
    }

    private static func normalizedVersion(_ raw: String) -> String {
        var version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.lowercased().hasPrefix("v") {
            version.removeFirst()
        }
        return version
    }

    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = versionParts(remote)
        let localParts = versionParts(local)
        let count = max(remoteParts.count, localParts.count)
        for index in 0..<count {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let localValue = index < localParts.count ? localParts[index] : 0
            if remoteValue != localValue {
                return remoteValue > localValue
            }
        }
        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    private static func confirmInstall(of version: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Update available"
        alert.informativeText = "Umbrella Helper \(version) is available. The app will quit, install it, and reopen. Screen Recording may need to be allowed again."
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func inform(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private struct Release {
        let version: String
        let downloadURL: URL
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }
}

private enum UpdateError: LocalizedError {
    case noRelease
    case badResponse
    case untrustedURL
    case downloadFailed
    case mountFailed(String)
    case appMissing
    case notWritable

    var errorDescription: String? {
        switch self {
        case .noRelease:
            return "No Umbrella Helper release with a disk image was found on GitHub."
        case .badResponse:
            return "GitHub didn’t return the latest release."
        case .untrustedURL:
            return "The release download wasn’t the expected GitHub disk image."
        case .downloadFailed:
            return "The disk image didn’t download."
        case .mountFailed(let detail):
            return detail.isEmpty ? "The disk image couldn’t be opened." : detail
        case .appMissing:
            return "The disk image didn’t contain Umbrella Helper."
        case .notWritable:
            return "Umbrella Helper can’t replace itself in this folder. Move it to Applications and try again."
        }
    }
}

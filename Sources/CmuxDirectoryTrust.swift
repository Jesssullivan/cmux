import Foundation

/// Manages trusted directories for cmux.json command execution.
/// When a directory (or its git repo root) is trusted, project actions from
/// that directory's cmux.json skip the confirmation dialog.
/// Global config (~/.config/cmux/cmux.json) is always trusted.
final class CmuxDirectoryTrust {
    static let shared = CmuxDirectoryTrust()
    static let didChangeNotification = Notification.Name("cmux.directoryTrustDidChange")

    private let storePath: String
    private var trustedPaths: Set<String>

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("cmux")
        storePath = appSupport.appendingPathComponent("trusted-directories.json").path

        let fm = FileManager.default
        if !fm.fileExists(atPath: appSupport.path) {
            try? fm.createDirectory(atPath: appSupport.path, withIntermediateDirectories: true)
        }

        if let data = fm.contents(atPath: storePath),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            trustedPaths = Set(paths.map(Self.canonicalPath))
        } else {
            trustedPaths = []
        }
    }

    /// Check if a cmux.json path is trusted.
    /// Global config is always trusted. For local configs, check the git repo root
    /// or the cmux.json parent directory when not in a git repo.
    func isTrusted(configPath: String, globalConfigPath: String) -> Bool {
        if Self.canonicalPath(configPath) == Self.canonicalPath(globalConfigPath) {
            return true
        }
        return trustedPaths.contains(Self.trustKey(for: configPath))
    }

    /// Trust the directory containing a cmux.json. If the cmux.json is inside a git
    /// repo, trust the repo root so subdirectories are covered too.
    func trust(configPath: String) {
        trustedPaths.insert(Self.trustKey(for: configPath))
        save()
    }

    /// Remove trust for a directory.
    func revokeTrust(configPath: String) {
        trustedPaths.remove(Self.trustKey(for: configPath))
        save()
    }

    /// Remove trust by the path directly as stored/displayed in settings.
    func revokeTrustByPath(_ path: String) {
        trustedPaths.remove(Self.canonicalPath(path))
        save()
    }

    var allTrustedPaths: [String] {
        trustedPaths.sorted()
    }

    func replaceAll(with paths: [String]) {
        trustedPaths = Set(paths.map(Self.canonicalPath).filter { !$0.isEmpty })
        save()
    }

    func clearAll() {
        trustedPaths.removeAll()
        save()
    }

    private static func trustKey(for configPath: String) -> String {
        let configDir = (canonicalPath(configPath) as NSString).deletingLastPathComponent
        if let gitRoot = findGitRoot(from: configDir) {
            return canonicalPath(gitRoot)
        }
        return canonicalPath(configDir)
    }

    private static func findGitRoot(from directory: String) -> String? {
        let fm = FileManager.default
        var current = directory
        while true {
            let gitPath = (current as NSString).appendingPathComponent(".git")
            if fm.fileExists(atPath: gitPath) {
                return current
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return nil
    }

    private static func canonicalPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { return "" }
        return URL(fileURLWithPath: expanded).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(trustedPaths.sorted()) else { return }
        FileManager.default.createFile(atPath: storePath, contents: data)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}

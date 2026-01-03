import Foundation

struct DerivedDataLogFinder {
    struct BuildLog: Sendable {
        let url: URL
        let modifiedAt: Date
    }

    func defaultDerivedDataRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
    }

    func findLatestLog(derivedDataPath: URL?, since: Date?) -> BuildLog? {
        if let derivedDataPath {
            return findLatestLogInDerivedData(derivedDataPath, since: since)
        }

        let root = defaultDerivedDataRoot()
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return nil }

        guard let children = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var best: BuildLog?
        for projectRoot in children where isDirectory(projectRoot) {
            if let candidate = findLatestLogInDerivedData(projectRoot, since: since) {
                if best == nil || candidate.modifiedAt > best!.modifiedAt { best = candidate }
            }
        }
        return best
    }

    private func findLatestLogInDerivedData(_ derivedData: URL, since: Date?) -> BuildLog? {
        let buildDir = derivedData.appendingPathComponent("Logs/Build", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: buildDir.path) else { return nil }

        guard let files = try? fm.contentsOfDirectory(
            at: buildDir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var bestURL: URL?
        var bestDate: Date = .distantPast

        for logURL in files where logURL.pathExtension == "xcactivitylog" {
            guard let values = try? logURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true
            else { continue }

            let mtime = values.contentModificationDate ?? .distantPast
            if let since, mtime < since { continue }

            if mtime > bestDate {
                bestDate = mtime
                bestURL = logURL
            }
        }

        guard let bestURL else { return nil }
        return BuildLog(url: bestURL, modifiedAt: bestDate)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}


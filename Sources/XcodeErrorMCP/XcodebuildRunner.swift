import Foundation

struct XcodebuildRunner {
    struct Result: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let durationSeconds: Double
    }

    func run(arguments: [String], workingDirectory: URL?) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let start = Date()
        try process.run()
        process.waitUntilExit()
        let end = Date()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return Result(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            durationSeconds: end.timeIntervalSince(start)
        )
    }
}


import Foundation

@main
enum XcodeErrorMCPMain {
    static func main() throws {
        let debug = ProcessInfo.processInfo.environment["XCODE_ERROR_MCP_DEBUG"] == "1"
        let server = StdioJSONRPCServer(debug: debug)
        let handler = XcodeErrorMCPHandler(debug: debug)
        try server.run { method, paramsData in
            handler.handle(method: method, paramsData: paramsData)
        }
    }
}

final class XcodeErrorMCPHandler {
    private let debug: Bool

    init(debug: Bool) {
        self.debug = debug
    }

    func handle(method: String, paramsData: Data?) -> (result: Encodable?, error: JSONRPCError?) {
        switch method {
        case "initialize":
            return (InitializeResult.make(), nil)
        case "tools/list":
            return (MCP.ToolsListResult(tools: ToolCatalog.tools), nil)
        case "tools/call":
            return handleToolsCall(paramsData: paramsData)
        case "ping":
            return (["ok": true], nil)
        default:
            return (nil, JSONRPCError(code: -32601, message: "Method not found", data: .string(method)))
        }
    }

    private func handleToolsCall(paramsData: Data?) -> (result: Encodable?, error: JSONRPCError?) {
        guard let paramsData else {
            return (nil, JSONRPCError(code: -32602, message: "Missing params", data: nil))
        }

        let decoder = JSONDecoder()
        guard let params = try? decoder.decode(MCP.ToolCallParams.self, from: paramsData) else {
            return (nil, JSONRPCError(code: -32602, message: "Invalid params", data: nil))
        }

        switch params.name {
        case "xcode_build_errors":
            return runBuildAndExtractErrors(arguments: params.arguments)
        case "xcode_last_errors":
            return readLastErrors(arguments: params.arguments)
        default:
            return (nil, JSONRPCError(code: -32602, message: "Unknown tool", data: .string(params.name)))
        }
    }

    private func runBuildAndExtractErrors(arguments: [String: JSONValue]?) -> (result: Encodable?, error: JSONRPCError?) {
        let env = ProcessInfo.processInfo.environment

        let workspace = arguments?["workspace"]?.stringValue
            ?? env["XCODE_WORKSPACE"]
        let project = arguments?["project"]?.stringValue
            ?? env["XCODE_PROJECT"]
        let scheme = arguments?["scheme"]?.stringValue
            ?? env["XCODE_SCHEME"]

        guard let scheme, !scheme.isEmpty else {
            return toolError("Missing `scheme` (arg or env XCODE_SCHEME)")
        }

        let configuration = arguments?["configuration"]?.stringValue
            ?? env["XCODE_CONFIGURATION"]
            ?? "Debug"
        let destination = arguments?["destination"]?.stringValue
            ?? env["XCODE_DESTINATION"]
        let sdk = arguments?["sdk"]?.stringValue
            ?? env["XCODE_SDK"]
        let derivedDataPathString = arguments?["derivedDataPath"]?.stringValue
            ?? env["XCODE_DERIVED_DATA_PATH"]
        let clonedSourcePackagesDirPath = arguments?["clonedSourcePackagesDirPath"]?.stringValue
            ?? env["XCODE_CLONED_SOURCE_PACKAGES_DIR_PATH"]
        let resultBundlePath = arguments?["resultBundlePath"]?.stringValue
            ?? env["XCODE_RESULT_BUNDLE_PATH"]
        let workingDirectoryString = arguments?["workingDirectory"]?.stringValue
            ?? env["XCODE_WORKING_DIRECTORY"]

        let codeSigningAllowed = arguments?["codeSigningAllowed"]?.boolValue
            ?? parseBool(env["XCODE_CODE_SIGNING_ALLOWED"], default: false)

        let extraArgs = (arguments?["extraArgs"]?.arrayValue ?? [])
            .compactMap(\.stringValue)

        var xcodebuildArgs: [String] = []

        if let workspace, !workspace.isEmpty {
            xcodebuildArgs += ["-workspace", workspace]
        } else if let project, !project.isEmpty {
            xcodebuildArgs += ["-project", project]
        } else {
            if let auto = autodiscoverWorkspaceOrProject() {
                switch auto {
                case let .workspace(path): xcodebuildArgs += ["-workspace", path]
                case let .project(path): xcodebuildArgs += ["-project", path]
                }
            } else {
                return toolError("Missing `workspace`/`project` (or set env XCODE_WORKSPACE/XCODE_PROJECT)")
            }
        }

        xcodebuildArgs += ["-scheme", scheme]
        xcodebuildArgs += ["-configuration", configuration]

        if let destination, !destination.isEmpty {
            xcodebuildArgs += ["-destination", destination]
        }
        if let sdk, !sdk.isEmpty {
            xcodebuildArgs += ["-sdk", sdk]
        }
        if let derivedDataPathString, !derivedDataPathString.isEmpty {
            xcodebuildArgs += ["-derivedDataPath", derivedDataPathString]
        }
        if let clonedSourcePackagesDirPath, !clonedSourcePackagesDirPath.isEmpty {
            xcodebuildArgs += ["-clonedSourcePackagesDirPath", clonedSourcePackagesDirPath]
        }
        if let resultBundlePath, !resultBundlePath.isEmpty {
            xcodebuildArgs += ["-resultBundlePath", resultBundlePath]
        }

        xcodebuildArgs += ["CODE_SIGNING_ALLOWED=\(codeSigningAllowed ? "YES" : "NO")"]
        xcodebuildArgs += extraArgs
        xcodebuildArgs.append("build")

        let workingDirectory = workingDirectoryString.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }

        let buildStart = Date()
        let runner = XcodebuildRunner()
        let finder = DerivedDataLogFinder()
        let extractor = XCActivityLogErrorExtractor()

        do {
            let buildResult = try runner.run(arguments: xcodebuildArgs, workingDirectory: workingDirectory)

            let derivedDataURL = derivedDataPathString.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            let log = finder.findLatestLog(derivedDataPath: derivedDataURL, since: buildStart.addingTimeInterval(-2))

            var errors: [String] = []
            if let log {
                errors = (try? extractor.extractErrors(from: log.url)) ?? []
            }

            if errors.isEmpty {
                errors = extractErrorsFromXcodebuildOutput(buildResult.stdout + "\n" + buildResult.stderr)
            }

            let text = formatOutput(
                title: "Xcode build errors",
                errors: errors,
                metadata: [
                    "exitCode": "\(buildResult.exitCode)",
                    "durationSeconds": String(format: "%.2f", buildResult.durationSeconds),
                    "log": log?.url.path ?? "—",
                ]
            )

            return toolText(text, isError: !errors.isEmpty || buildResult.exitCode != 0)
        } catch {
            return toolError("Failed running xcodebuild: \(error.localizedDescription)")
        }
    }

    private func readLastErrors(arguments: [String: JSONValue]?) -> (result: Encodable?, error: JSONRPCError?) {
        let env = ProcessInfo.processInfo.environment
        let derivedDataPathString = arguments?["derivedDataPath"]?.stringValue
            ?? env["XCODE_DERIVED_DATA_PATH"]
        let sinceSeconds = arguments?["sinceSeconds"].flatMap { value -> Double? in
            if let n = value.numberValue { return n }
            if let s = value.stringValue { return Double(s) }
            return nil
        }

        let since = sinceSeconds.map { Date().addingTimeInterval(-$0) }

        let finder = DerivedDataLogFinder()
        let extractor = XCActivityLogErrorExtractor()
        let derivedDataURL = derivedDataPathString.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }

        guard let log = finder.findLatestLog(derivedDataPath: derivedDataURL, since: since) else {
            return toolText("No .xcactivitylog found.", isError: false)
        }

        do {
            let errors = try extractor.extractErrors(from: log.url)
            let text = formatOutput(
                title: "Xcode last build errors",
                errors: errors,
                metadata: [
                    "log": log.url.path,
                    "modifiedAt": ISO8601DateFormatter().string(from: log.modifiedAt),
                ]
            )
            return toolText(text, isError: !errors.isEmpty)
        } catch {
            return toolError("Failed extracting errors: \(error.localizedDescription)")
        }
    }

    private func toolText(_ text: String, isError: Bool) -> (result: Encodable?, error: JSONRPCError?) {
        (
            MCP.ToolCallResult(
                content: [.init(type: "text", text: text)],
                isError: isError ? true : nil
            ),
            nil
        )
    }

    private func toolError(_ message: String) -> (result: Encodable?, error: JSONRPCError?) {
        (
            MCP.ToolCallResult(
                content: [.init(type: "text", text: message)],
                isError: true
            ),
            nil
        )
    }

    private func formatOutput(title: String, errors: [String], metadata: [String: String]) -> String {
        var lines: [String] = []
        lines.append("\(title) (\(errors.count))")
        if !metadata.isEmpty {
            for (k, v) in metadata.sorted(by: { $0.key < $1.key }) {
                lines.append("\(k): \(v)")
            }
        }
        if errors.isEmpty {
            lines.append("")
            lines.append("No errors found.")
            return lines.joined(separator: "\n")
        }
        lines.append("")
        lines.append(contentsOf: errors)
        return lines.joined(separator: "\n")
    }

    private enum AutoProject {
        case workspace(String)
        case project(String)
    }

    private func autodiscoverWorkspaceOrProject() -> AutoProject? {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        guard let items = try? fm.contentsOfDirectory(at: cwd, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return nil
        }

        let workspaces = items.filter { $0.pathExtension == "xcworkspace" }.map(\.path)
        if workspaces.count == 1, let one = workspaces.first { return .workspace(one) }

        let projects = items.filter { $0.pathExtension == "xcodeproj" }.map(\.path)
        if projects.count == 1, let one = projects.first { return .project(one) }

        return nil
    }

    private func parseBool(_ string: String?, default defaultValue: Bool) -> Bool {
        guard let string else { return defaultValue }
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on": return true
        case "0", "false", "no", "n", "off": return false
        default: return defaultValue
        }
    }

    private func extractErrorsFromXcodebuildOutput(_ output: String) -> [String] {
        var out: [String] = []
        out.reserveCapacity(64)
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if lower.contains(": warning:") || lower.hasPrefix("warning:") { continue }
            if lower.contains(": error:") ||
                lower.hasPrefix("error:") ||
                lower.hasPrefix("fatal error:") ||
                lower.hasPrefix("ld: error:") ||
                lower.contains("command compileswift failed") ||
                lower.contains("command ld failed") ||
                lower.contains("compile") && lower.contains("failed")
            {
                out.append(line)
            }
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}

private struct InitializeResult: Encodable {
    struct Capabilities: Encodable {
        struct Tools: Encodable {
            let listChanged: Bool
        }

        let tools: Tools
    }

    let protocolVersion: String
    let capabilities: Capabilities
    let serverInfo: MCP.ServerInfo

    static func make() -> InitializeResult {
        InitializeResult(
            protocolVersion: "2024-11-05",
            capabilities: Capabilities(tools: .init(listChanged: false)),
            serverInfo: MCP.ServerInfo(name: "xcode-error-mcp", version: "0.1.0")
        )
    }
}

private enum ToolCatalog {
    static let tools: [MCP.Tool] = [
        MCP.Tool(
            name: "xcode_build_errors",
            description: "Run xcodebuild and return only build errors (no warnings).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "workspace": .object([
                        "type": .string("string"),
                        "description": .string("Path to a .xcworkspace"),
                    ]),
                    "project": .object([
                        "type": .string("string"),
                        "description": .string("Path to a .xcodeproj"),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string("Scheme to build"),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string("Build configuration (e.g. Debug/Release)"),
                    ]),
                    "destination": .object([
                        "type": .string("string"),
                        "description": .string("xcodebuild -destination value"),
                    ]),
                    "sdk": .object([
                        "type": .string("string"),
                        "description": .string("xcodebuild -sdk value"),
                    ]),
                    "derivedDataPath": .object([
                        "type": .string("string"),
                        "description": .string("xcodebuild -derivedDataPath value"),
                    ]),
                    "clonedSourcePackagesDirPath": .object([
                        "type": .string("string"),
                        "description": .string("xcodebuild -clonedSourcePackagesDirPath value"),
                    ]),
                    "resultBundlePath": .object([
                        "type": .string("string"),
                        "description": .string("xcodebuild -resultBundlePath value"),
                    ]),
                    "extraArgs": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Extra xcodebuild arguments appended before the build action"),
                    ]),
                    "workingDirectory": .object([
                        "type": .string("string"),
                        "description": .string("Working directory for xcodebuild"),
                    ]),
                    "codeSigningAllowed": .object([
                        "type": .string("boolean"),
                        "description": .string("Sets CODE_SIGNING_ALLOWED=YES/NO"),
                    ]),
                ]),
            ])
        ),
        MCP.Tool(
            name: "xcode_last_errors",
            description: "Extract errors (no warnings) from the most recent .xcactivitylog in DerivedData.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "derivedDataPath": .object([
                        "type": .string("string"),
                        "description": .string("DerivedData path (if you used -derivedDataPath)"),
                    ]),
                    "sinceSeconds": .object([
                        "type": .string("number"),
                        "description": .string("Only consider logs modified in the last N seconds"),
                    ]),
                ]),
            ])
        ),
    ]
}

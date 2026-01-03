import Foundation
import zlib

struct XCActivityLogErrorExtractor {
    enum ExtractError: Error { case decompressionFailed }

    private static let errorFileDiagnosticRegex: NSRegularExpression? = {
        let exts = "(swift|m|mm|c|cc|cpp|h|hpp|metal|storyboard|xib|plist|intentdefinition)"
        let sev = "(fatal error|error)"
        let pattern = "/[^\\n\\r\"]+?\\.\(exts):\\d+:\\d+:\\s*\(sev):\\s*[^\\n\\r]+"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    func extractErrors(from logURL: URL) throws -> [String] {
        let rawText = try decompressToText(logURL: logURL)
        let lines = rawText.components(separatedBy: .newlines)

        var results: [String] = []
        results.append(contentsOf: extractFileDiagnostics(from: rawText, regex: Self.errorFileDiagnosticRegex))

        let filtered = filterErrorLines(lines).map { trimToFirstDiagnosticIfPresent($0, regex: Self.errorFileDiagnosticRegex) }
        results.append(contentsOf: filtered)

        let normalized = normalize(results)
        if !normalized.isEmpty { return normalized }

        let fused = fuseFileAndErrorLines(lines).map { trimToFirstDiagnosticIfPresent($0, regex: Self.errorFileDiagnosticRegex) }
        return normalize(fused)
    }

    private func decompressToText(logURL: URL) throws -> String {
        let data = try Data(contentsOf: logURL)

        if let inflated = inflateIfNeeded(data), let text = decodeTextData(inflated), !text.isEmpty {
            return text
        }

        if let text = decodeTextData(data), !text.isEmpty {
            return text
        }

        throw ExtractError.decompressionFailed
    }

    private func decodeTextData(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty { return utf8 }
        let utf8Lossy = String(decoding: data, as: UTF8.self)
        if !utf8Lossy.isEmpty { return utf8Lossy }
        if let utf16 = String(data: data, encoding: .utf16LittleEndian), !utf16.isEmpty { return utf16 }
        if let utf16BE = String(data: data, encoding: .utf16BigEndian), !utf16BE.isEmpty { return utf16BE }
        if let ascii = String(data: data, encoding: .ascii), !ascii.isEmpty { return ascii }
        return nativeStrings(from: data)
    }

    private func extractFileDiagnostics(from text: String, regex: NSRegularExpression?) -> [String] {
        guard let regex, !text.isEmpty else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var out: [String] = []
        out.reserveCapacity(min(64, matches.count))
        for m in matches {
            let s = ns.substring(with: m.range(at: 0)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(s) }
        }
        return out
    }

    private func trimToFirstDiagnosticIfPresent(_ line: String, regex: NSRegularExpression?) -> String {
        guard let regex, !line.isEmpty else { return line }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
        return ns.substring(with: m.range(at: 0)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inflateIfNeeded(_ data: Data) -> Data? {
        guard data.count >= 2 else { return nil }
        let b0 = data[data.startIndex]
        let b1 = data[data.index(after: data.startIndex)]
        let looksCompressed = (b0 == 0x1f && b1 == 0x8b) || b0 == 0x78
        guard looksCompressed else { return nil }
        return inflateZlibOrGzip(data)
    }

    private func inflateZlibOrGzip(_ data: Data) -> Data? {
        var stream = z_stream()
        var status = inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        let chunkSize = 64 * 1024
        var output = Data()
        output.reserveCapacity(min(4_000_000, max(chunkSize, data.count * 2)))
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        return data.withUnsafeBytes { inputRaw -> Data? in
            guard let base = inputRaw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: base)
            stream.avail_in = uInt(inputRaw.count)

            while true {
                buffer.withUnsafeMutableBytes { outRaw in
                    stream.next_out = outRaw.bindMemory(to: UInt8.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    buffer.withUnsafeBytes { outRaw in
                        output.append(outRaw.bindMemory(to: UInt8.self).baseAddress!, count: produced)
                    }
                }

                if status == Z_STREAM_END { break }
                if status != Z_OK { return nil }
                if produced == 0 && stream.avail_in == 0 { break }
            }

            return output.isEmpty ? nil : output
        }
    }

    private func nativeStrings(from data: Data) -> String? {
        var out = String()
        out.reserveCapacity(min(1_000_000, data.count / 2))
        var run: [UInt8] = []
        run.reserveCapacity(256)

        func flushRun() {
            if run.count >= 4 {
                out.append(String(bytes: run, encoding: .ascii) ?? "")
                out.append("\n")
            }
            run.removeAll(keepingCapacity: true)
        }

        for b in data {
            if (32...126).contains(b) || b == 9 {
                run.append(b)
            } else if b == 10 || b == 13 {
                flushRun()
            } else {
                flushRun()
            }
            if out.count > 4_000_000 { break }
        }
        flushRun()
        return out.isEmpty ? nil : out
    }

    private func filterErrorLines(_ lines: [String]) -> [String] {
        var results: [String] = []
        results.reserveCapacity(32)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.contains(" warning:") { continue }
            if trimmed.contains(": error:") ||
                trimmed.hasPrefix("error:") ||
                trimmed.hasPrefix("fatal error:") ||
                trimmed.hasPrefix("ld: error:") ||
                trimmed.contains("CompileSwiftSources normal") && trimmed.contains("failed") ||
                trimmed.contains("Command CompileSwift failed") ||
                trimmed.contains("Command Ld failed")
            {
                results.append(trimmed)
            }
        }
        return results
    }

    private func fuseFileAndErrorLines(_ lines: [String]) -> [String] {
        let pattern = "^(.+\\.(swift|m|mm|c|cc|cpp|h|hpp)):(\\d+):(\\d+):\\s*$"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        var fused: [String] = []
        var lastFileLine: String?

        func push(_ combined: String) {
            fused.append(combined.trimmingCharacters(in: .whitespaces))
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let re = regex,
               re.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) != nil
            {
                lastFileLine = line
                continue
            }

            let lower = line.lowercased()
            if lower.hasPrefix("error:") || lower.hasPrefix("fatal error:") {
                if let file = lastFileLine {
                    if let colonIndex = line.firstIndex(of: ":") {
                        let after = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                        push("\(file) error: \(after)")
                    } else {
                        push("\(file) error: \(line)")
                    }
                } else {
                    push(line)
                }
                lastFileLine = nil
                continue
            }

            if let file = lastFileLine, line.contains("expected") || line.contains("use of unresolved identifier") {
                push("\(file) error: \(line)")
                lastFileLine = nil
            }
        }
        return fused
    }

    private func normalize(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(lines.count)
        for l in lines where !l.isEmpty {
            if !seen.contains(l) {
                seen.insert(l)
                out.append(l)
            }
        }
        return out
    }
}


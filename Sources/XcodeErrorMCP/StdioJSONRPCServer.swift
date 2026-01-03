import Foundation

final class StdioJSONRPCServer {
    private let debug: Bool
    private let stdin = FileHandle.standardInput
    private let stdout = FileHandle.standardOutput
    private let stderr = FileHandle.standardError

    private var buffer = Data()

    init(debug: Bool) {
        self.debug = debug
    }

    func run(handler: @escaping (_ method: String, _ params: Data?) -> (result: Encodable?, error: JSONRPCError?)) throws {
        while true {
            if let message = try readNextMessage() {
                try handleMessage(message, handler: handler)
                continue
            }

            let chunk = stdin.availableData
            guard !chunk.isEmpty else {
                return
            }
            buffer.append(chunk)
        }
    }

    private func handleMessage(
        _ messageData: Data,
        handler: @escaping (_ method: String, _ params: Data?) -> (result: Encodable?, error: JSONRPCError?)
    ) throws {
        guard let json = try JSONSerialization.jsonObject(with: messageData) as? [String: Any] else {
            return
        }

        let method = json["method"] as? String ?? ""
        let id = json["id"]
        let paramsData: Data?

        if let params = json["params"] {
            paramsData = try? JSONSerialization.data(withJSONObject: params)
        } else {
            paramsData = nil
        }

        if debug {
            log("[in] \(method) id=\(id.map(String.init(describing:)) ?? "nil")")
        }

        let isNotification = (id == nil)
        let (result, error) = handler(method, paramsData)
        if isNotification { return }

        if let error {
            try sendResponse(JSONRPCResponse(id: id, result: nil, error: error))
            return
        }

        if let result {
            try sendResponse(JSONRPCResponse(id: id, result: AnyEncodable(result), error: nil))
        } else {
            try sendResponse(JSONRPCResponse(id: id, result: AnyEncodable(JSONNull()), error: nil))
        }
    }

    private func readNextMessage() throws -> Data? {
        let headerDelimiterCRLF = Data("\r\n\r\n".utf8)
        let headerDelimiterLF = Data("\n\n".utf8)
        guard let headerRange = buffer.range(of: headerDelimiterCRLF) ?? buffer.range(of: headerDelimiterLF) else { return nil }

        let headerData = buffer.subdata(in: 0 ..< headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        var contentLength: Int?
        for lineSub in headerString.split(whereSeparator: \.isNewline) {
            let line = String(lineSub)
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if key == "content-length" {
                contentLength = Int(value)
                break
            }
        }

        guard let contentLength, contentLength >= 0 else { return nil }

        let bodyStart = headerRange.upperBound
        let bodyEnd = bodyStart + contentLength
        guard buffer.count >= bodyEnd else { return nil }

        let body = buffer.subdata(in: bodyStart ..< bodyEnd)
        buffer.removeSubrange(0 ..< bodyEnd)
        return body
    }

    private func sendResponse(_ response: JSONRPCResponse) throws {
        let data = try JSONEncoder().encode(response)
        let header = "Content-Length: \(data.count)\r\n\r\n"
        if debug {
            log("[out] id=\(response.id.map(String.init(describing:)) ?? "nil") bytes=\(data.count)")
        }
        stdout.write(Data(header.utf8))
        stdout.write(data)
    }

    private func log(_ message: String) {
        stderr.write(Data((message + "\n").utf8))
    }
}

struct JSONRPCError: Encodable {
    let code: Int
    let message: String
    let data: JSONValue?
}

private struct JSONRPCResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: AnyCodable?
    let result: AnyEncodable?
    let error: JSONRPCError?

    init(id: Any?, result: AnyEncodable?, error: JSONRPCError?) {
        self.id = AnyCodable(id)
        self.result = result
        self.error = error
    }
}

private struct AnyCodable: Encodable {
    private let value: Any?

    init(_ value: Any?) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case nil:
            try container.encodeNil()
        case let v as NSNumber:
            if CFNumberIsFloatType(v) {
                try container.encode(v.doubleValue)
            } else {
                try container.encode(v.int64Value)
            }
        case let v as Int:
            try container.encode(v)
        case let v as Int64:
            try container.encode(v)
        case let v as Double:
            try container.encode(v)
        case let v as String:
            try container.encode(v)
        case let v as Bool:
            try container.encode(v)
        default:
            try container.encode(String(describing: value))
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeFunc = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}

private struct JSONNull: Encodable {}

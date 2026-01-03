import Foundation

enum MCP {
    struct ServerInfo: Encodable {
        let name: String
        let version: String
    }

    struct Tool: Encodable {
        let name: String
        let description: String
        let inputSchema: JSONValue
    }

    struct ToolsListResult: Encodable {
        let tools: [Tool]
    }

    struct ToolCallParams: Decodable {
        let name: String
        let arguments: [String: JSONValue]?
    }

    struct ToolCallResult: Encodable {
        struct ContentItem: Encodable {
            let type: String
            let text: String
        }

        let content: [ContentItem]
        let isError: Bool?
    }
}

enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let n = try? container.decode(Double.self) { self = .number(n); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? container.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(v): try container.encode(v)
        case let .number(v): try container.encode(v)
        case let .string(v): try container.encode(v)
        case let .array(v): try container.encode(v)
        case let .object(v): try container.encode(v)
        }
    }

    var stringValue: String? {
        if case let .string(v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(v) = self { return v }
        return nil
    }

    var numberValue: Double? {
        if case let .number(v) = self { return v }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(v) = self { return v }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(v) = self { return v }
        return nil
    }
}

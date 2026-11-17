import Foundation

/// A JSON tree. Used to decode documents and themes tolerantly: the stored JSON is laid over the JSON of the
/// current defaults, so a key missing from an older file takes its default and unknown keys are ignored.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// The JSON of any `Encodable` value.
    public init(encoding value: some Encodable) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// Decodes this tree as `T`.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    /// `self` (stored) laid over `defaults`: objects merge key by key, anything else is taken from `self`.
    ///
    /// Single-key objects whose key differs are treated as different enum cases (`{"solid":…}` vs
    /// `{"gradient":…}`), so the stored case replaces the default instead of being merged into it.
    public func merged(over defaults: JSONValue) -> JSONValue {
        guard case .object(let stored) = self, case .object(let base) = defaults else { return self }
        if base.count == 1, let defaultKey = base.keys.first, stored[defaultKey] == nil, !stored.isEmpty {
            return self
        }
        var result = base
        for (key, value) in stored {
            result[key] = base[key].map { value.merged(over: $0) } ?? value
        }
        return .object(result)
    }

    /// Decodes `self` as `T`, filling every missing key from `defaults` (see `merged(over:)`).
    public func decodeTolerantly<T: Codable>(_ type: T.Type, defaults: T) throws -> T {
        try merged(over: JSONValue(encoding: defaults)).decode(type)
    }
}

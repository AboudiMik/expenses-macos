import Foundation

/// One block of a Messages API message, for requests and responses.
nonisolated enum ContentBlock: Codable {
    case text(String)
    case image(mediaType: String, base64: String)
    case document(mediaType: String, base64: String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String, content: String, isError: Bool)
    case other(type: String)

    private enum Keys: String, CodingKey {
        case type, text, source, id, name, input, content
        case toolUseId = "tool_use_id", isError = "is_error"
    }
    private enum SourceKeys: String, CodingKey { case type, mediaType = "media_type", data }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "tool_use":
            self = .toolUse(id: try c.decode(String.self, forKey: .id),
                            name: try c.decode(String.self, forKey: .name),
                            input: try c.decode(JSONValue.self, forKey: .input))
        default:
            self = .other(type: type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        case .image(let mediaType, let base64), .document(let mediaType, let base64):
            if case .image = self { try c.encode("image", forKey: .type) }
            else { try c.encode("document", forKey: .type) }
            var s = c.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try s.encode("base64", forKey: .type)
            try s.encode(mediaType, forKey: .mediaType)
            try s.encode(base64, forKey: .data)
        case .toolUse(let id, let name, let input):
            try c.encode("tool_use", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try c.encode("tool_result", forKey: .type)
            try c.encode(toolUseId, forKey: .toolUseId)
            try c.encode(content, forKey: .content)
            if isError { try c.encode(true, forKey: .isError) }
        case .other(let type):
            try c.encode(type, forKey: .type)
        }
    }
}

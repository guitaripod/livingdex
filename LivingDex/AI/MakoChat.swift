import Foundation

/// Parsing helpers for mako's `chat.completion` responses, which proxy an
/// OpenAI-shaped body (`choices[].message.content`). Models occasionally wrap
/// JSON in prose or code fences, so we isolate the first balanced object.
enum MakoChat {
    private struct ChatCompletion: Decodable {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        let choices: [Choice]
    }

    /// Extracts the assistant message text from a raw completion body.
    static func messageContent(_ data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(ChatCompletion.self, from: data) {
            return decoded.choices.first?.message.content
        }
        guard let envelope = firstBalancedObject(in: String(decoding: data, as: UTF8.self)),
              let decoded = try? JSONDecoder().decode(ChatCompletion.self, from: Data(envelope.utf8))
        else { return nil }
        return decoded.choices.first?.message.content
    }

    /// Isolates the first balanced top-level `{...}`, tolerating markdown fences
    /// and surrounding prose.
    static func firstBalancedObject(in text: String) -> String? {
        let stripped = stripCodeFences(text)
        return firstBalanced(in: stripped, open: "{", close: "}")
    }

    private static func stripCodeFences(_ text: String) -> Substring {
        guard let fenceStart = text.range(of: "```") else { return text[...] }
        let afterOpen = text[fenceStart.upperBound...]
        // Drop an optional language tag ("```json\n") only when a newline follows
        // the opener. A single-line fence ("```{...}```") has no newline, so the
        // body must be kept as-is rather than dropped wholesale.
        let body: Substring
        if afterOpen.first == "\n" {
            body = afterOpen.dropFirst()
        } else if let newline = afterOpen.firstIndex(of: "\n") {
            body = afterOpen[afterOpen.index(after: newline)...]
        } else {
            body = afterOpen
        }
        guard let fenceEnd = body.range(of: "```") else { return body }
        return body[..<fenceEnd.lowerBound]
    }

    private static func firstBalanced(in text: Substring, open: Character, close: Character) -> String? {
        guard let start = text.firstIndex(of: open) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == open {
                    depth += 1
                } else if character == close {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

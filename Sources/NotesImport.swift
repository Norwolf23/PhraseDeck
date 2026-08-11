import AppKit

enum NotesImport {
    struct ScriptError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func run(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            let detail = error?[NSAppleScript.errorMessage] as? String ?? "unknown error"
            throw ScriptError(message: "Couldn't talk to Notes (check Automation permission in System Settings > Privacy & Security): \(detail)")
        }
        return result
    }

    private static func strings(_ d: NSAppleEventDescriptor) -> [String] {
        if d.numberOfItems > 0 { return (1...d.numberOfItems).compactMap { d.atIndex($0)?.stringValue } }
        return d.stringValue.map { [$0] } ?? []
    }

    static func listFolders() throws -> [String] {
        strings(try run(#"tell application "Notes" to get name of folders"#))
    }

    static func fetchCards(folders: [String]) throws -> [Card] {
        var out: [Card] = []
        for folder in folders {
            let escaped = folder
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let d = try run("tell application \"Notes\" to get plaintext of every note of folder \"\(escaped)\"")
            for body in strings(d) {
                for line in body.split(whereSeparator: \.isNewline) {
                    if let card = parseLine(String(line), language: folder) { out.append(card) }
                }
            }
        }
        return out
    }

    /// Splits on the first occurrence of a separator, spaced forms first;
    /// bare "-" only when spaced so hyphenated words survive.
    static func parseLine(_ line: String, language: String) -> Card? {
        let t = line.trimmingCharacters(in: .whitespaces)
        for sep in [" – ", " — ", " - ", " : ", "–", "—"] {
            guard let r = t.range(of: sep) else { continue }
            let phrase = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let translation = t[r.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !phrase.isEmpty, !translation.isEmpty else { return nil }
            return Card(language: language, phrase: phrase, translation: translation)
        }
        return nil
    }
}

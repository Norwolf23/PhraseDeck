import Foundation

// Build: swiftc -parse-as-library Sources/Models.swift Sources/NotesImport.swift test_parser.swift -o /tmp/pdtest && /tmp/pdtest

@main
struct TestParser {
    static func main() {
        func check(_ ok: Bool, _ name: String) {
            if !ok { print("FAIL: \(name)"); exit(1) }
        }

        let a = NotesImport.parseLine("hola – hello", language: "Spanish")
        check(a?.phrase == "hola" && a?.translation == "hello" && a?.confidence == .unrated, "en dash split")

        let b = NotesImport.parseLine("buenos días - good morning", language: "Spanish")
        check(b?.phrase == "buenos días" && b?.translation == "good morning", "spaced hyphen split")

        let c = NotesImport.parseLine("well-being : bienestar", language: "Spanish")
        check(c?.phrase == "well-being" && c?.translation == "bienestar", "hyphenated word survives")

        check(NotesImport.parseLine("just a sentence line", language: "Spanish") == nil, "plain line rejected")

        let d = NotesImport.parseLine("Cute = süßi", language: "Südtirolerisch")
        check(d?.phrase == "Cute" && d?.translation == "süßi", "equals split")

        let e1 = Card(language: "it", phrase: "Are you", translation: "Stai", confidence: .unrated)
        let e2 = Card(language: "it", phrase: "Are you", translation: "Sei", confidence: .unrated)
        check(e1.id != e2.id, "same phrase, different translation = distinct cards")

        let low = Card(language: "es", phrase: "l", translation: "x", confidence: .low)
        let high = Card(language: "es", phrase: "h", translation: "x", confidence: .high)
        var lowCount = 0
        for _ in 0..<2000 {
            if Store.weightedPick(from: [low, high], count: 1).first?.confidence == .low { lowCount += 1 }
        }
        check(lowCount > 2000 - lowCount, "low picked more than high (\(lowCount)/2000)")

        print("OK")
    }
}

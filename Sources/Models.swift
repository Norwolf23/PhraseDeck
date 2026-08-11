import Combine
import Foundation

enum Confidence: String, Codable, CaseIterable { case unrated, low, medium, high }

struct Card: Codable, Identifiable, Hashable {
    var language: String
    var phrase: String
    var translation: String
    var confidence: Confidence = .unrated
    var id: String { language + "|" + phrase }
}

final class Store: ObservableObject {
    static let shared = Store()

    @Published var cards: [Card] = []
    @Published var selectedLanguage: String?
    @Published var deckFolders: [String] = []

    private struct State: Codable {
        var cards: [Card]
        var selectedLanguage: String?
        var deckFolders: [String]
    }

    private static let url = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PhraseDeck/store.json")

    init() {
        if let data = try? Data(contentsOf: Self.url),
           let s = try? JSONDecoder().decode(State.self, from: data) {
            cards = s.cards
            selectedLanguage = s.selectedLanguage
            deckFolders = s.deckFolders
        }
    }

    private func save() {
        let s = State(cards: cards, selectedLanguage: selectedLanguage, deckFolders: deckFolders)
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? JSONEncoder().encode(s).write(to: Self.url)
    }

    var languages: [String] { Array(Set(cards.map(\.language))).sorted() }

    func cards(language: String, confidence: Confidence) -> [Card] {
        cards.filter { $0.language == language && $0.confidence == confidence }
    }

    /// Weighted random without replacement: low ×4, medium ×2, unrated ×2, high ×1.
    static func weightedPick(from cards: [Card], count: Int) -> [Card] {
        let weight: [Confidence: Int] = [.low: 4, .medium: 2, .unrated: 2, .high: 1]
        var pool = cards
        var picked: [Card] = []
        while picked.count < count, !pool.isEmpty {
            var r = Int.random(in: 0..<pool.reduce(0) { $0 + weight[$1.confidence]! })
            let i = pool.firstIndex { r -= weight[$0.confidence]!; return r < 0 }!
            picked.append(pool.remove(at: i))
        }
        return picked
    }

    func pickSession(count: Int) -> [Card] {
        var pool = cards
        if let l = selectedLanguage {
            let filtered = cards.filter { $0.language == l }
            if !filtered.isEmpty { pool = filtered }
        }
        return Self.weightedPick(from: pool, count: count)
    }

    func rate(_ card: Card, _ c: Confidence) {
        guard let i = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[i].confidence = c
        save()
    }

    func setDeckFolders(_ folders: [String]) {
        deckFolders = folders
        save()
    }

    func setSelectedLanguage(_ l: String?) {
        selectedLanguage = l
        save()
    }

    /// Identity = language|phrase. Existing ratings kept, new cards unrated,
    /// cards absent from `imported` are removed.
    func merge(imported: [Card]) {
        let existing = Dictionary(cards.map { ($0.id, $0.confidence) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        cards = imported.compactMap {
            guard seen.insert($0.id).inserted else { return nil }
            var c = $0
            c.confidence = existing[c.id] ?? .unrated
            return c
        }
        save()
    }
}

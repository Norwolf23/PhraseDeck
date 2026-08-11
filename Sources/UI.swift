import SwiftUI

// MARK: - Pastel palette (stable per phrase — djb2, not Swift's seeded hashValue)

private let pastels: [Color] = [
    Color(red: 1.00, green: 0.80, blue: 0.82), // pink
    Color(red: 1.00, green: 0.87, blue: 0.72), // peach
    Color(red: 1.00, green: 0.96, blue: 0.70), // butter
    Color(red: 0.78, green: 0.93, blue: 0.79), // mint
    Color(red: 0.74, green: 0.91, blue: 0.90), // seafoam
    Color(red: 0.76, green: 0.87, blue: 1.00), // sky
    Color(red: 0.85, green: 0.81, blue: 0.98), // lavender
    Color(red: 0.96, green: 0.80, blue: 0.95), // lilac
]

private func pastel(for phrase: String) -> Color {
    var h: UInt64 = 5381
    for u in phrase.unicodeScalars { h = h &* 33 &+ UInt64(u.value) }
    return pastels[Int(h % UInt64(pastels.count))]
}

// MARK: - CardView (3D flip, text kept unmirrored via pre-rotated back face)

struct CardView: View {
    let card: Card
    let frontIsPhrase: Bool
    @Binding var flipped: Bool

    private func face(_ text: String) -> some View {
        Text(text)
            .font(.title2.weight(.medium))
            .foregroundStyle(.black.opacity(0.8))
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(width: 420, height: 260)
            .background(pastel(for: card.phrase), in: RoundedRectangle(cornerRadius: 20))
    }

    var body: some View {
        ZStack {
            face(frontIsPhrase ? card.phrase : card.translation)
                .opacity(flipped ? 0 : 1)
            face(frontIsPhrase ? card.translation : card.phrase)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .onTapGesture { withAnimation(.easeInOut(duration: 0.35)) { flipped.toggle() } }
    }
}

// MARK: - SessionView

struct SessionView: View {
    let cards: [Card]
    let onDone: () -> Void
    @State private var index = 0
    @State private var flipped = false
    @State private var fronts: [Bool]

    init(cards: [Card], onDone: @escaping () -> Void) {
        self.cards = cards
        self.onDone = onDone
        _fronts = State(initialValue: cards.map { _ in Bool.random() })
    }

    private func rate(_ c: Confidence) {
        Store.shared.rate(cards[index], c)
        if index + 1 < cards.count {
            flipped = false
            withAnimation(.easeInOut(duration: 0.3)) { index += 1 }
        } else {
            onDone()
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(min(index + 1, cards.count)) / \(cards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDone) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            if cards.indices.contains(index) {
                CardView(card: cards[index], frontIsPhrase: fronts[index], flipped: $flipped)
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
                RatingBar(onRate: rate)
            } else {
                Text("No cards to review").foregroundStyle(.secondary).padding(40)
            }
        }
        .padding(20)
    }
}

// MARK: - RatingBar

struct RatingBar: View {
    let onRate: (Confidence) -> Void

    private func button(_ title: String, _ c: Confidence, _ tint: Color) -> some View {
        Button(title) { onRate(c) }
            .buttonStyle(.borderedProminent)
            .tint(tint)
    }

    var body: some View {
        HStack(spacing: 12) {
            button("Not confident", .low, Color(red: 0.91, green: 0.42, blue: 0.42))
            button("So-so", .medium, Color(red: 0.93, green: 0.76, blue: 0.30))
            button("Confident", .high, Color(red: 0.36, green: 0.72, blue: 0.44))
        }
    }
}

private func pool(_ language: String?) -> [Card] {
    guard let language else { return Store.shared.cards }
    return Store.shared.cards.filter { $0.language == language }
}

// MARK: - SessionLauncherView (choose a language, then 5 cards)

struct SessionLauncherView: View {
    let onDone: () -> Void
    @State private var cards: [Card]?

    var body: some View {
        if let cards {
            SessionView(cards: cards, onDone: onDone)
        } else {
            VStack(spacing: 10) {
                Text("Which language?").font(.headline).padding(.bottom, 4)
                ForEach(Store.shared.languages, id: \.self) { lang in
                    Button { start(lang) } label: { Text(lang).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
                Button { start(nil) } label: { Text("Mix them all").frame(maxWidth: .infinity) }
                Button("Not now", action: onDone)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(width: 260)
            .onAppear { if Store.shared.languages.count < 2 { start(nil) } }
        }
    }

    private func start(_ lang: String?) {
        cards = Store.weightedPick(from: pool(lang), count: 5)
    }
}

// MARK: - EndlessView (keeps drawing weighted cards until closed)

struct EndlessView: View {
    let language: String?
    let onDone: () -> Void
    @State private var card: Card?
    @State private var frontIsPhrase = false
    @State private var flipped = false
    @State private var seen = 0

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(seen) reviewed").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: onDone) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            if let card {
                CardView(card: card, frontIsPhrase: frontIsPhrase, flipped: $flipped)
                    .id("\(seen)|\(card.id)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
                RatingBar { c in
                    Store.shared.rate(card, c)
                    seen += 1
                    withAnimation(.easeInOut(duration: 0.3)) { draw() }
                }
            } else {
                Text("No cards here yet").foregroundStyle(.secondary).padding(40)
            }
        }
        .padding(20)
        .onAppear { draw() }
    }

    /// Weighted single draw; never shows the same card twice in a row.
    private func draw() {
        var p = pool(language)
        if p.count > 1, let cur = card { p.removeAll { $0.id == cur.id } }
        flipped = false
        frontIsPhrase = Bool.random()
        card = Store.weightedPick(from: p, count: 1).first
    }
}

// MARK: - HomeView (piles per language + review buttons)

struct HomeView: View {
    let onSync: () -> Void
    @ObservedObject private var store = Store.shared

    private enum Mode { case browse, cards([Card]), endless(String?) }
    @State private var mode: Mode = .browse

    private static let piles: [(String, Confidence, Color)] = [
        ("High", .high, .green), ("Medium", .medium, .yellow),
        ("Low", .low, .red), ("New", .unrated, .gray),
    ]

    private func chip(_ lang: String, _ label: String, _ c: Confidence, _ tint: Color) -> some View {
        let pile = store.cards(language: lang, confidence: c)
        return Button { mode = .cards(pile.shuffled()) } label: {
            VStack(spacing: 2) {
                Text("\(pile.count)").font(.title3.bold())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(pile.isEmpty ? 0.08 : 0.2), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(pile.isEmpty)
    }

    private func section(_ lang: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(lang, systemImage: "globe").font(.headline)
                Spacer()
                Button("5 cards") { mode = .cards(Store.weightedPick(from: pool(lang), count: 5)) }
                Button { mode = .endless(lang) } label: { Label("Endless", systemImage: "infinity") }
            }
            HStack(spacing: 8) {
                ForEach(Self.piles, id: \.0) { p in chip(lang, p.0, p.1, p.2) }
            }
        }
    }

    var body: some View {
        Group {
            switch mode {
            case .cards(let cards):
                SessionView(cards: cards) { mode = .browse }
            case .endless(let lang):
                EndlessView(language: lang) { mode = .browse }
            case .browse:
                if store.cards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No cards yet").font(.headline)
                        Button("Sync from Notes…", action: onSync).buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                ForEach(store.languages, id: \.self) { lang in section(lang) }
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        HStack {
                            Button("Sync from Notes…", action: onSync)
                            Spacer()
                            Text("\(store.cards.count) cards").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(12)
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}

// MARK: - FolderPickerView

struct FolderPickerView: View {
    let allFolders: [String]
    let onConfirm: ([String]) -> Void
    @State private var selected = Set(Store.shared.deckFolders)

    var body: some View {
        VStack(spacing: 12) {
            Label("Choose deck folders", systemImage: "folder.badge.gearshape")
                .font(.headline)
            Text("Each note inside becomes a language deck (note title = language).")
                .font(.caption)
                .foregroundStyle(.secondary)
            List(allFolders, id: \.self) { f in
                Toggle(f, isOn: Binding(
                    get: { selected.contains(f) },
                    set: { if $0 { selected.insert(f) } else { selected.remove(f) } }))
            }
            HStack {
                Button("Cancel") { onConfirm(Store.shared.deckFolders) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use these folders") { onConfirm(allFolders.filter(selected.contains)) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340, height: 400)
    }
}

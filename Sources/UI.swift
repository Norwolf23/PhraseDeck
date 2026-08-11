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

    private func rateButton(_ title: String, _ c: Confidence, _ tint: Color) -> some View {
        Button(title) { rate(c) }
            .buttonStyle(.borderedProminent)
            .tint(tint)
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
                HStack(spacing: 12) {
                    rateButton("Not confident", .low, Color(red: 0.91, green: 0.42, blue: 0.42))
                    rateButton("So-so", .medium, Color(red: 0.93, green: 0.76, blue: 0.30))
                    rateButton("Confident", .high, Color(red: 0.36, green: 0.72, blue: 0.44))
                }
            } else {
                Text("No cards to review").foregroundStyle(.secondary).padding(40)
            }
        }
        .padding(20)
    }
}

// MARK: - PilesView

struct PilesView: View {
    @ObservedObject private var store = Store.shared
    @State private var reviewing: [Card]?

    private static let piles: [(String, Confidence, Color)] = [
        ("High", .high, .green), ("Medium", .medium, .yellow),
        ("Low", .low, .red), ("New", .unrated, .gray),
    ]

    private func chip(_ lang: String, _ label: String, _ c: Confidence, _ tint: Color) -> some View {
        let pile = store.cards(language: lang, confidence: c)
        return Button { reviewing = pile } label: {
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

    var body: some View {
        Group {
            if let cards = reviewing {
                SessionView(cards: cards) { reviewing = nil }
            } else if store.cards.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Sync from Notes to get started")
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(store.languages, id: \.self) { lang in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(lang, systemImage: "globe").font(.headline)
                                HStack(spacing: 8) {
                                    ForEach(Self.piles, id: \.0) { p in
                                        chip(lang, p.0, p.1, p.2)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: 480, height: 560)
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
            Text("Each folder becomes a language deck.")
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

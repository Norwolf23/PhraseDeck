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
    /// true for the automatic wake/unlock popup — honors the wake language
    /// setting; manual "Review 5 Now" always asks.
    var auto: Bool = false
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
            .onAppear {
                if auto, let wl = Store.shared.wakeLanguage {
                    start(wl.isEmpty ? nil : wl)
                } else if Store.shared.languages.count < 2 {
                    start(nil)
                }
            }
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
    @ObservedObject private var pomo = Pomodoro.shared

    private enum Mode { case browse, cards([Card]), endless(String?) }
    @State private var mode: Mode = .browse

    private static let piles: [(String, Confidence, Color)] = [
        ("High", .high, Color(red: 0.36, green: 0.72, blue: 0.44)),
        ("Medium", .medium, Color(red: 0.93, green: 0.76, blue: 0.30)),
        ("Low", .low, Color(red: 0.91, green: 0.42, blue: 0.42)),
        ("New", .unrated, Color(red: 0.55, green: 0.62, blue: 0.72)),
    ]

    private func chip(_ lang: String, _ label: String, _ c: Confidence, _ tint: Color) -> some View {
        let pile = store.cards(language: lang, confidence: c)
        return Button { mode = .cards(pile.shuffled()) } label: {
            VStack(spacing: 3) {
                Text("\(pile.count)")
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundStyle(pile.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                    .contentTransition(.numericText())
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(pile.isEmpty ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(pile.isEmpty)
    }

    /// Thin segmented bar showing the confidence mix of a deck.
    private func progressBar(_ lang: String) -> some View {
        let counts = Self.piles.map { (store.cards(language: lang, confidence: $0.1).count, $0.2) }
        let total = max(counts.reduce(0) { $0 + $1.0 }, 1)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, seg in
                    if seg.0 > 0 {
                        seg.1.frame(width: max(geo.size.width * CGFloat(seg.0) / CGFloat(total) - 2, 3))
                    }
                }
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
    }

    private func section(_ lang: String) -> some View {
        let deck = pool(lang)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(lang).font(.title3.bold())
                Text("\(deck.count) cards").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    mode = .cards(Store.weightedPick(from: deck, count: 5))
                } label: {
                    Label("Review 5", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button { mode = .endless(lang) } label: { Label("Endless", systemImage: "infinity") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            progressBar(lang)
            HStack(spacing: 8) {
                ForEach(Self.piles, id: \.0) { p in chip(lang, p.0, p.1, p.2) }
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(colors: [Color(red: 0.45, green: 0.55, blue: 0.95),
                                            Color(red: 0.65, green: 0.45, blue: 0.90)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text("PhraseDeck").font(.title3.bold())
                Text("\(store.cards.count) cards · \(store.languages.count) languages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onSync()
            } label: {
                Label("Sync from Notes", systemImage: "arrow.triangle.2.circlepath")
            }
            .controlSize(.regular)
            Menu {
                Picker("Wake language", selection: Binding(
                    get: { store.wakeLanguage },
                    set: { store.setWakeLanguage($0) }
                )) {
                    Text("Ask each time").tag(String?.none)
                    Text("Mix all languages").tag(String?.some(""))
                    Divider()
                    ForEach(store.languages, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("Work length", selection: Binding(
                    get: { store.workMinutes },
                    set: { store.setWorkMinutes($0) }
                )) {
                    ForEach([15, 25, 30, 45, 50, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Break length", selection: Binding(
                    get: { store.breakMinutes },
                    set: { store.setBreakMinutes($0) }
                )) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
                Toggle("Open 5 new cards at break", isOn: Binding(
                    get: { store.openCardsOnBreak },
                    set: { store.setOpenCardsOnBreak($0) }
                ))
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Wake-up popup and pomodoro settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var pomodoroBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .foregroundStyle(pomo.phase == .rest ? .green : .orange)
            if pomo.isRunning {
                Text(pomo.phase == .work ? "Working" : "Break")
                    .font(.callout.weight(.semibold))
                Text(pomo.clock)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(pomo.paused ? "Resume" : "Pause") { pomo.togglePause() }
                    .controlSize(.small)
                Button(pomo.phase == .work ? "Skip to Break" : "Skip to Work") { pomo.skip() }
                    .controlSize(.small)
                Button("Stop") { pomo.stop() }
                    .controlSize(.small)
            } else {
                Text("Pomodoro · \(store.workMinutes) min work / \(store.breakMinutes) min break")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Start") { pomo.start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.25))
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
                    VStack(spacing: 14) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("No cards yet").font(.title3.bold())
                        Text("Make a checklist of phrase pairs in Apple Notes,\nthen sync it here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Sync from Notes…", action: onSync)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.top, 6)
                    }
                } else {
                    VStack(spacing: 0) {
                        header
                        pomodoroBar
                        Divider()
                        ScrollView {
                            VStack(spacing: 14) {
                                ForEach(store.languages, id: \.self) { lang in section(lang) }
                            }
                            .padding(20)
                        }
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

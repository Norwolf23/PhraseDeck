# PhraseDeck — design spec (2026-08-10)

Native SwiftUI menu-bar Mac app. Pops a floating 5-card flashcard window on every wake/unlock, cards come from phrase-pair lines in Apple Notes folders (one folder per language), user rates confidence, low-confidence cards appear more often. Manual sync.

## Data

- `Card { language, phrase, translation, confidence }`, identity = `language|phrase`.
- `Confidence: unrated | low | medium | high` (low = "not confident", medium = "so-so", high = "confident").
- Persistence: single JSON file at `~/Library/Application Support/PhraseDeck/store.json` holding cards, selected language, chosen Notes folder names.
- Import is **manual**: "Sync from Notes" menu action. AppleScript (via `NSAppleScript`/`osascript`) lists Notes folders; user ticks which folders are decks (folder name = language). Sync fetches all notes' plaintext in those folders.
- Parser: a line makes a card if it splits on the first ` – `, ` — `, ` - `, or ` : ` (separator surrounded by spaces; en/em dash also accepted without spaces). Everything else ignored. Whitespace trimmed.
- Merge on sync: match by `language|phrase`; existing ratings preserved, new lines arrive as `unrated`, lines no longer in Notes are removed.

## Review session

- Trigger: `NSWorkspace.didWakeNotification` + `com.apple.screenIsUnlocked` (distributed). Debounce 60 s so wake+unlock doesn't double-fire. Also "Review 5 Now" menu item.
- Floating window (`.floating` level, centered) with 5 cards from the selected language, weighted random without replacement: low ×4, medium ×2, unrated ×2, high ×1.
- Card face shown first is chosen at random per card (phrase side or translation side). Click card to flip.
- Card background: pleasant pastel from a fixed ~8-color palette, picked by hash of the phrase (stable per card, no meaning).
- Buttons under card: **Not confident / So-so / Confident** → saves rating, advances. After card 5 the window closes. Esc/✕ dismisses anytime.

## Piles

- Window from menu bar: one section per language, four piles — **High / Medium / Low / New** — each showing a count. Click a pile → flip through those cards with the same card UI, rating as you go.

## Menu bar

Icon menu: Review 5 Now · language picker · Piles… · Sync from Notes… · Launch at Login toggle (`SMAppService.mainApp`) · Quit. App is `LSUIElement` (no Dock icon).

## Build & files

StayAwake pattern: plain `swiftc` + hand-rolled `.app` bundle, no Xcode project, no dependencies.

- `Sources/Models.swift` — Card, Confidence, Store (load/save/merge/weighted pick/rate)
- `Sources/NotesImport.swift` — AppleScript folder list + note fetch + line parser
- `Sources/UI.swift` — CardView, SessionView, PilesView, folder-picker sheet
- `Sources/App.swift` — @main MenuBarExtra, wake observers, window management
- `build.sh` — compiles, writes Info.plist (incl. `NSAppleEventsUsageDescription`, `LSUIElement`), codesigns ad-hoc
- `test_parser.swift` — runnable assert check for the line parser + weighted pick

## Skipped on purpose

Spaced repetition, iCloud sync, in-app card editing, stats/streaks, per-note granularity. All addable later without rework.

# PhraseDeck

Menu-bar Mac flashcard app. Every time your Mac wakes or unlocks, it pops a floating window with 5 phrase cards pulled from Apple Notes. Rate each card (Not confident / So-so / Confident) — shaky cards come back more often. macOS 14+, no dependencies.

## Build & install

```sh
./build.sh
cp -R build/PhraseDeck.app /Applications/
open /Applications/PhraseDeck.app
```

First sync will ask permission to control Notes — allow it (fixable later under System Settings → Privacy & Security → Automation).

## How phrases must look in Notes

One Apple Notes **folder per language** (the folder name becomes the language). Inside, any note with one phrase pair per line:

```
buenos días – good morning
la cuenta, por favor - the check, please
gracias : thank you
```

Only **checklist or bullet lines** (the little circle/dot items) become cards — plain text lines are ignored, so you can keep staging words in the same note. A line becomes a card when it splits on the first ` – `, ` — `, ` - `, ` : `, or `=` (en/em dashes also work without surrounding spaces).

Sync is manual: menu bar icon → **Sync from Notes…**, tick the folders that are decks.

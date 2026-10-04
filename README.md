# PerkPilot

Your credit cards are quietly handing you hundreds of dollars in credits every
month — and most of them expire if you don't use them. PerkPilot is a simple,
private iPhone app that tracks every recurring benefit across your wallet and
turns "use it or lose it" into a monthly checklist.

## Features (Phase 1)

- **Today checklist** — every monthly, quarterly, semi-annual, and annual
  credit for the current period, grouped by cadence, with one-tap checkmarks
  and a progress ring.
- **Wallet** — your 12 cards with fees and benefit counts; archive a card
  (tasks stop, history kept) or restore it anytime.
- **Benefits library** — all 238 benefits, searchable and filterable by card,
  cadence, lesser-known tricks, and muted status. Every benefit links its
  sources.
- **Lesser-known tips** — community-discovered tricks live *inside* their
  benefit (never as duplicate checklist rows).
- **Mute a reward** — hide anything with no monetary value, no interest, or
  no value to you, with a reason. Muted rewards stay in the library and can
  be unmuted anytime.
- **Monthly reminder** — one quiet local notification on the 28th of each
  month. No account, no server, no tracking.
- **Statement Intelligence** — import CSV (first-class) or PDF (best-effort)
  statements per card per month. Spend auto-categorizes by keyword with
  per-merchant learning when you recategorize; search every transaction by
  merchant, amount, card, category, or date; and the **rewards check** shows
  whether each monthly credit was *likely received* by heuristically matching
  statement charges — always labeled as heuristic, never bank-verified, with
  one-tap confirm feeding the checklist.
- **News tab** — reserved for the Phase 2 discovery feed (currently a
  placeholder explaining what's coming).

## Roadmap

- **Phase 2 — Discovery engine.** A server-side worker scans Reddit, issuer
  pages, and points press every 72 hours for new hidden benefits, credit
  changes, and enrollment updates. Findings land in the News tab for your
  review; nothing is ever added to your benefits automatically. API keys stay
  on the server, never in the app.
- **Phase 3 — Sync & polish.** Optional iCloud sync across devices, widgets,
  TestFlight distribution.

See `docs/` (coming) and the architecture plan for the full blueprint.

## Seed data

The app ships with a researched, versioned catalog: **12 cards, 238 benefits**,
each with amount, how-to-use instructions, enrollment flags, and 2–4 source
URLs. Research was compiled October 2026 from issuer pages, Doctor of Credit,
The Points Guy, Frequent Miler, NerdWallet, and community forums; lesser-known
entries were cross-checked against r/CreditCards, r/chase, r/amex, and related
communities.

- Raw research: `research/` (not in this repo — see NOTES)
- Normalizer: `tools/normalize_seed.py`
- Bundled seed: `PerkPilot/PerkPilot/Resources/SeedData.json`
  (`catalogVersion: 2026.10.03`)

## Setup

Requires a Mac with Xcode 15+ (Swift 5.9, iOS 17 SDK).

```bash
git clone <this-repo>
cd perkpilot
open PerkPilot/PerkPilot.xcodeproj
```

1. In Xcode, select the **PerkPilot** target → **Signing & Capabilities** →
   choose your Team (free Apple ID works for running on your own device).
2. The bundle ID is `com.sannat.perkpilot` — change it if you like, but keep
   it consistent with the test target (`com.sannat.perkpilot.tests`).
3. Pick your iPhone (or a simulator) and press **Run** (⌘R).
4. Run the tests with **Product → Test** (⌘U).

To regenerate the Xcode project after adding/removing files:

```bash
python3 tools/generate_project.py
```

To rebuild the seed bundle from research JSONs:

```bash
python3 tools/normalize_seed.py
```

## Service seams (for future features)

Statement Intelligence is built as four clean, UI-independent services so
later features can reuse them without touching views:

| Service | File | Owns | Future use |
|---|---|---|---|
| `StatementParser` | `Services/StatementParser.swift` | CSV parsing: issuer-profile auto-detect, manual `ColumnMapping` fallback, sign normalization, row-level warnings. Never invents rows. | Reused by any bulk import |
| `PDFStatementParser` | `Services/PDFStatementParser.swift` | PDFKit text extraction + line-item heuristics with confidence scores | Swap in a better engine later |
| `CategoryEngine` | `Services/CategoryEngine.swift` | Pure keyword categorizer + merchant normalization + override precedence. No SwiftData. | **"Best card for this purchase" advisor**: categorize the purchase, then rank cards by category earn rate |
| `RewardMatcher` | `Services/RewardMatcher.swift` | Heuristic benefit↔transaction matching (merchant keywords + expected-amount patterns), honest confidence levels | **Annual fee justification report**: sum detected credits per card vs. its annual fee |
| `TransactionStore` | `Services/TransactionStore.swift` | The only doorway to statement data: import, search, aggregates, recategorize-with-learning, deletion | Everything above |

## Privacy

Everything lives on-device in SwiftData. No card numbers, no bank logins, no
analytics, no network calls in Phase 1. The discovery pipeline (Phase 2) is
deliberately server-side so provider API secrets never ship in the app.

**Statement data is extra-sensitive and treated that way:** imported
statements are parsed on-device and the raw files are never persisted or
uploaded — only parsed transaction rows are stored, in the same on-device
SwiftData store. Statements are explicitly excluded from any future sync
design. The app's import screens and Settings say this in plain language.

## License

Private project — all rights reserved for now.

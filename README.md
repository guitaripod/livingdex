# Living Dex

**Point your iPhone at anything alive and add it to the only Pokédex where the creatures are real.**

A camera-first "real-life Pokédex" collection game for iOS 26 — discover, identify, and collect every life form on Earth, gamified. UIKit + GRDB, Liquid Glass, on-device identification with a Claude cloud layer through the shared [mako](https://github.com/guitaripod/mako) backend.

## Status

Early MVP. The capture loop is real and working: **spot → identify → collect → learn**.

- **Camera-first Field view** (Liquid Glass HUD) → capture → confidence-signalled, rarity-dramatised **card mint** → reactive **Dex** grid → **Profile** with collection progress.
- **On-device identification** behind a `SpeciesIdentifier` protocol (`CoreMLSpeciesIdentifier` Vision harness + geo-prior rerank); ships with a labelled stub until the BioCLIP→Core ML model + `taxa.json` are bundled.
- **AI narration** via mako `chat.completion` → Claude (grounded "Pokédex entry"); on-device Apple Foundation Models planned as the free/offline default.
- **GRDB** for offline-first persistence; **AICredits** for identity/credits/RevenueCat (mako tenant `livingdex`).
- Agent-native file logger (`Library/Logs/livingdex.log`), haptics, accessibility (VoiceOver + Dynamic Type + Reduce Motion), first-run onboarding.

## Build

```sh
brew install xcodegen        # if needed
cp LivingDex/Secrets.example.swift LivingDex/Secrets.swift   # fill in the RevenueCat key
xcodegen generate
open LivingDex.xcodeproj
```

Requires Xcode 26 / iOS 26 SDK. `Secrets.swift` is gitignored.

## Architecture

| Area | Where |
|---|---|
| App shell | `LivingDex/App/` (AppDelegate, SceneDelegate, RootViewController, AppLogger, Haptics, DesignSystem) |
| Capture | `LivingDex/Capture/` (CameraController, ImageStore, LocationProvider) |
| Identification | `LivingDex/Identify/` (SpeciesIdentifier, CoreMLSpeciesIdentifier, TaxonCatalog, GeoPrior) |
| AI narration | `LivingDex/AI/` (SpeciesNarrator, MakoChat) |
| Persistence | `LivingDex/Database/` (DatabaseManager, Records, CollectionStore) |
| Features | `LivingDex/Features/` (Field, Card, Dex, Profile, Onboarding) |

Backend is [`guitaripod/mako`](https://github.com/guitaripod/mako) (shared AI-credits Worker); this app is one of its tenants.

## Roadmap

Bundle a real BioCLIP→Core ML model + taxon catalog + geo-prior · the Living-Dex domain Worker (fact-sheet/geo-prior/EXIF strip) · Game Center (leaderboards, challenges, bioblitz) · RevenueCat `livingdex` project + Pro paywall · ethics guardrails (sensitive-species obscuring).

# Living Dex

**Point your iPhone at anything alive and add it to the only Pokédex where the creatures are real.**

A camera-first "real-life Pokédex" collection game for iOS 26 — discover, identify, and collect every life form on Earth, gamified. UIKit + GRDB, Liquid Glass, on-device identification with a Claude cloud layer through the shared [mako](https://github.com/guitaripod/mako) backend.

## What it does

**Spot → identify → collect → learn.** Point the camera (or pick a photo, or try a bundled sample) at anything alive and get a rarity-graded card for your Dex.

- **Field**: camera-first view with a Liquid Glass HUD, a credits meter, and a photo menu (library or sample).
- **Identification**: cloud vision through the shared [mako](https://github.com/guitaripod/mako) backend (Gemini), then the name is verified against GBIF through the domain Worker (`services/living-dex` at the repo root); an unconfirmed species is never minted. A consent sheet precedes the first photo that leaves the device. No on-device species model ships yet (`CoreMLSpeciesIdentifier` is wired and takes over once `SpeciesClassifier.mlmodelc` + `taxa.json` are bundled).
- **Dex**: Nearby (regional species as locked slots) and Caught (searchable, sortable); card detail with a field entry (Apple Foundation Models, else the sourced Wikipedia summary; Pro gets cloud entries) and a playable call.
- **Progression**: XP, levels, streaks, Game Center leaderboard and eight achievements (`scripts/asc-gamecenter.py`).
- **Money**: 30 free identifications per device; Living Dex Pro (monthly, annual with trial) is unlimited; consumable credit packs. Everything runs through AICredits + RevenueCat.
- **Privacy**: anonymous identity, privacy manifest, revocable cloud consent, in-app Delete Account & Data (`DELETE /v1/identity`, then local wipe).
- Agent-native file logger (`Library/Logs/livingdex.log`), haptics, VoiceOver, Dynamic Type, Reduce Motion.

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
| Features | `LivingDex/Features/` (Field, Card, Dex, Profile, Guide, Paywall, Consent, Onboarding) |

Backend is [`guitaripod/mako`](https://github.com/guitaripod/mako) (shared AI-credits Worker); this app is one of its tenants.

## Demo and store assets

DEBUG builds read `LIVINGDEX_DEMO=<route>` (`field`, `reveal`, `caught`, `nearby`, `card`, `profile`, `guide`, `guide-realms`, `onboarding` with `LIVINGDEX_DEMO_STEP`, `sample`, `sharecards`) and `LIVINGDEX_DEMO_PHOTOS=<folder>` to seed a populated collection. `scripts/capture-demo-screens.sh` captures the routes from a simulator (`route[@step][=name]`; the photos folder is `marketing/demo-photos`, not committed) and `marketing/compose_screenshots.py` frames them with the `frames` CLI into the App Store set; `marketing/appstore/metadata.json` is the en-US listing.

## Roadmap

Bundle a real BioCLIP→Core ML model + taxon catalog so identification works offline · the "ask the creature" Q&A · sensitive-species obscuring · localisation.

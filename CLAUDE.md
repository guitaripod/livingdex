# Living Dex: agent guide

A camera-first "real-life Pokedex" for iOS 26: point the camera at anything alive, get a rarity-graded card for the Dex. UIKit, GRDB (`LivingDex/Database`), Swift 6 with complete strict concurrency. `README.md` describes the features and the demo and store-asset tooling; this file is the working guide.

## Build and test

```sh
cp LivingDex/Secrets.example.swift LivingDex/Secrets.swift   # RevenueCat key only, gitignored
xcodegen generate
xcodebuild test -project LivingDex.xcodeproj -scheme LivingDex -destination 'platform=iOS Simulator,id=<udid>'
```

Run from the monorepo as `apps/living-dex`; the mirror is `guitaripod/livingdex` (`midgar sync living-dex`). Bundle id `com.guitaripod.livingdex`, registry slug `living-dex`.

## Midgar platform

- **Packages.** MidgarKit comes from the monorepo's `packages/MidgarKit` by path and AICredits from `packages/AICredits` by path, both in `project.yml` (decision D15). Commerce stays on AICredits and RevenueCat until wallet linking; do not move purchases.
- **Composition root.** `LivingDexMidgar` (`LivingDex/App`) builds the Midgar ID (`MidgarIdentity`, no App Attest entitlement), the gateway addresses, the portal configuration and the log file. The keychain groups are the app's own first, then `$(AppIdentifierPrefix)cc.midgarcorp.shared`.
- **Gateway.** mako is `https://api.midgarcorp.cc/v1/intelligence` (`LivingDexMidgar.intelligenceURL`, AICredits' base URL) and AICredits sends the Midgar token through `additionalHeaders` (`midgarTokenHeaders()`, never waited on). The worker is `https://api.midgarcorp.cc/v1/livingdex/...` through `LivingDexGateway`, each call once with the timeout it always had (3.5 s enrichment, 8 s Regional Dex and call lookup). The worker is keyless and the gateway forwards no `Authorization` to it, so worker calls carry none. The tenant id is `livingdex` (mako and the worker know the app by it); the Midgar ID, signals and the portal use the registry slug `living-dex`.
- **Species verification.** The worker answers 404 with a plain `{"error": ...}` for a name GBIF rejects, which `SpeciesEnricher` reads as "unresolved" and never mints; a 404 with an error code is the gateway's own and only makes the result unavailable.
- **Logging.** `MidgarLog` writes `Library/Logs/livingdex.log` (the name `ios-device-logs` pulls). Categories are in `LivingDex/Logging`. Never log photos, prompts, model output, coordinates or tokens.
- **Settings.** `SettingsViewController` hosts MidgarUI's `MidgarSettingsViewController` with the portal card (`LivingDexMidgar.portalConfig`) in `MidgarTheme.livingDex`.
- **Reviews.** `ReviewPrompt` reports a saved new Dex entry to `MidgarReviewPolicy` and asks StoreKit only when it allows.
- **Legal.** Policy and terms live at `https://midgarcorp.cc/legal/living-dex/{privacy,terms}/` (`LegalLinks`); the source is `web/midgarcorp/src/content/legal/living-dex/`. Keep `LivingDex/PrivacyInfo.xcprivacy`, `store/privacy-label.md` and the policy in step.
- **Worker** (`backend/`, `livingdex-worker`): GBIF rarity, Regional Dex and species call. Deploy it and the gateway before an app release that depends on a route.

## Rules

No inline comments (a `///` on a well-named method instead), no file headers, no file over 1,000 lines, `midgar arch check --app living-dex` with 0 errors.

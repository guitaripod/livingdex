# Living Dex App Privacy label

Answers for App Store Connect, App Privacy section. Apple does not expose this section through the API, so the founder enters it by hand. It matches `LivingDex/PrivacyInfo.xcprivacy` and the policy at https://midgarcorp.cc/legal/living-dex/privacy/ (source: `web/midgarcorp/src/content/legal/living-dex/privacy.html`, last updated 23 October 2026). The Privacy Policy URL on the app info (`store/metadata/ios/app-info/en-US.json`) and the policy and terms links in the description (`store/metadata/ios/version/1.0/en-US.json`) move from the `mako.midgarcorp.cc` addresses to the midgarcorp.cc ones with this release; `midgar listing` pushes them and, under the `metadata_edit` policy, only with the founder at a terminal. The old addresses redirect to the new ones, because mako answers them with a 301. The support URL stays on mako, because the Midgar site has no support page for the app.

## Top-level answers

- Do you or your third-party partners collect data from this app: Yes.
- Data used to track you: none. No data type is used for tracking. The app asks for no tracking permission and `NSPrivacyTracking` is false with no tracking domains.
- Privacy policy URL: https://midgarcorp.cc/legal/living-dex/privacy/

## Data types collected

| Data type (Apple) | Linked to the user | Used to track | Purpose | What it is in Living Dex |
| --- | --- | --- | --- | --- |
| Photos or Videos | Yes | No | App Functionality | The photo of a capture, shrunk to 1,536 pixels, sent to mako and on to Google (Gemini) to name the organism after the person allows cloud identification. mako keeps no copy; it is declared as linked because it travels with the anonymous account key. |
| Location, Coarse Location | No | No | App Functionality | The sighting's coordinates rounded to about 11 km, and the centre of a 55 km grid cell for the Nearby list, sent to the Living Dex worker, which stores nothing. No account key or Midgar ID goes with them. |
| Contact Info, Email Address | Yes | No | App Functionality | Only when the person links Sign in with Apple: the address Apple provides, possibly a private relay. |
| Identifiers, User ID | Yes | No | App Functionality | The anonymous account key mako issues for the credit balance and Pro status, and the random Midgar ID, kept in iCloud Keychain and shared with Midgar's other apps on the person's devices. The Midgar ID goes to `api.midgarcorp.cc` (the identity service), rides on mako calls so mako can link it to the account, and authorizes the portal's "Your Midgar" panel. RevenueCat also holds its own anonymous app user id. (New with this release.) |
| Identifiers, Device ID | Yes | No | App Functionality | The app reads no advertising identifier and no vendor identifier. The first mako account is created with a DeviceCheck token that mako checks with Apple, which answers only yes or no; the app also keeps a random per-install id in the Keychain. MidgarKit's App Attest key id, per app and per device, stored with the Midgar ID when the ID is created or joined. App Store and TestFlight builds use App Attest's production environment whether or not the app has the App Attest entitlement (Apple, App Attest Environment entitlement), so released builds create it. |
| Purchases, Purchase History | Yes | No | App Functionality | The App Store transactions of Living Dex Pro and credit packs, verified by RevenueCat and recorded by mako, and the credit ledger of identifications and field entries. |
| Usage Data, Product Interaction | No | No | Analytics | The anonymous More Apps card events (opened, shown, tapped) that the portal sends to `api.midgarcorp.cc/v1/signals` through MidgarKit's anonymous signals client, with no Midgar ID, device identifier or `Authorization` header. Reading "Your Midgar" sends no event. (New with this release.) |

Everything else is "Data Not Collected".

## Data types answered "not collected", and why

- Contacts, Browsing History, Search History, Sensitive Info, Health & Fitness, Financial Info: none.
- Precise Location: the app reads it on the device to tag a sighting, but only coordinates rounded to 11 km leave the device.
- Gameplay Content and Game Center data: reported to Apple's Game Center under Apple's policy, not collected by us.
- Diagnostics: the log (`Library/Logs/livingdex.log`) stays on the device and is never uploaded unless the person exports it. MetricKit is not collected.
- Other Data: none.

## Check before the label is entered

- Every call to mako and to the Living Dex worker now goes through `api.midgarcorp.cc`; the legacy `mako.midgarcorp.cc` and `livingdex-worker.guitaripod.workers.dev` addresses are no longer used by this build, so the data collected is unchanged apart from the Midgar ID and the portal counts.
- The gateway forwards no credential to the worker: the worker is keyless and the calls carry only `X-App-ID` `livingdex`.
- Delete Account in the app deletes the mako account (`DELETE /v1/intelligence/v1/identity`) and then the local data. It does not erase the Midgar ID, which Midgar's other apps share; the policy gives the support address for that.
- The Midgar ID is not sent to RevenueCat and Living Dex's purchases still go through AICredits and RevenueCat only, so Purchase History is unchanged.

## Third-party SDK notes

- RevenueCat: processes purchase data on our behalf (Purchase History, User ID above).
- MidgarKit 4.3.1: `MidgarPortal` ships a manifest that declares Product Interaction for Analytics, not linked, matching the row above. `MidgarCore` (identity, HTTP, logging, signals) ships none and uses no required-reason API beyond the ones listed below. Anonymous signals send nothing else: MetricKit collection is not started.
- Cloudflare: hosts the gateway (`api.midgarcorp.cc`) and the services behind it, mako and the Living Dex worker, and may keep standard request logs (IP address) for a limited time; IP address is not a data type in the label.

## Required-reason APIs (in the manifest, not in the label)

- App: UserDefaults `CA92.1` (own settings), file timestamp `C617.1` (documents the person opens or exports).

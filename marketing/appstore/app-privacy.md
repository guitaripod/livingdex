# App Privacy answers (App Store Connect > App Privacy)

Matches `Resources/PrivacyInfo.xcprivacy` and the live privacy policy. Nothing is used to track, so
"Data Used to Track You" is empty. Publish after saving.

| Data type | Purpose | Linked to the user | Why |
|---|---|---|---|
| Photos or Videos | App Functionality | Yes | The photo sent for cloud identification (not stored by us) |
| Coarse Location | App Functionality | No | Sighting coordinates rounded to 0.1 degrees go to the Worker for rarity; the Nearby list uses a 0.5 degree cell centre |
| Email Address | App Functionality | Yes | Only if the player links Sign in with Apple (may be Apple's private relay) |
| User ID | App Functionality | Yes | The anonymous account id |
| Device ID | App Functionality | Yes | Keychain device id + DeviceCheck for one free allowance per device |
| Purchase History | App Functionality | Yes | Apple purchase records for Pro and credit packs, verified by mako |

Tracking: No. Third-party advertising: No.

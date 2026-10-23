import Foundation

/// Where the published policies live: the Midgar site, which is also what the store listing links to. The old mako
/// addresses redirect here. There is no support page on the Midgar site, so support is the address in Settings.
enum LegalLinks {
    static let privacy = URL(string: "https://midgarcorp.cc/legal/living-dex/privacy/")!
    static let terms = URL(string: "https://midgarcorp.cc/legal/living-dex/terms/")!
    static let appStore = URL(string: "https://apps.apple.com/app/id6787688416")!
}

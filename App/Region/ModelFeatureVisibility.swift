import Foundation
import MidgarCore

/// What the model-feature surfaces show for one answer of Midgar's region gateway. Cloud identification, the credit
/// packs, Pro and the cloud narration all need a model that Midgar's servers only run where the model providers serve
/// the device, so while the answer is no, none of their entry points is offered and the neutral line stands in for them.
struct ModelFeatureVisibility: Equatable {
    let modelsAvailable: Bool

    /// The visibility for the answer the device holds now.
    static var current: ModelFeatureVisibility {
        ModelFeatureVisibility(modelsAvailable: MidgarModelRegion.shared.modelsAvailable)
    }

    /// The capture control of the Field, which identifies what the camera points at in the cloud.
    var showsCloudIdentification: Bool { modelsAvailable }

    /// The photo library in the photo menu and the camera gate. A bundled sample runs on the device and stays either way.
    var showsLibraryIdentification: Bool { modelsAvailable }

    /// The credits meter, and the Profile row that counts identifications and sells credits.
    var showsCredits: Bool { modelsAvailable }

    /// Whether any paywall may be presented. Living Dex Pro and the credit packs sell model features, so they are not
    /// presented where the models do not work.
    var presentsPaywall: Bool { modelsAvailable }

    /// The Settings switch that sends photos to a cloud service.
    var showsCloudConsentSetting: Bool { modelsAvailable }

    /// The line the Field shows while it waits: the prompt to point at something, or the neutral line where the models
    /// do not work.
    var idleStatus: String {
        modelsAvailable ? String(localized: "Point at anything alive") : MidgarModelRegion.unavailableMessage
    }
}

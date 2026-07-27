import Foundation
import FoundationModels

enum IntelligenceAvailabilityState: String, CaseIterable, Sendable {
    case checking
    case available
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case unknown

    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available:
            self = .available
        case .unavailable(.appleIntelligenceNotEnabled):
            self = .appleIntelligenceNotEnabled
        case .unavailable(.deviceNotEligible):
            self = .deviceNotEligible
        case .unavailable(.modelNotReady):
            self = .modelNotReady
        @unknown default:
            self = .unknown
        }
    }

    var isReady: Bool { self == .available }

    var title: String {
        switch self {
        case .checking: "Checking Apple Intelligence…"
        case .available: "Apple Intelligence ready"
        case .appleIntelligenceNotEnabled: "Apple Intelligence is off"
        case .deviceNotEligible: "This Mac is not eligible"
        case .modelNotReady: "The on-device model is not ready"
        case .unknown: "Apple Intelligence is unavailable"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            "FileMorrow is checking the on-device Foundation Model."
        case .available:
            "Smart Content can use the on-device Foundation Model. File evidence stays on this Mac."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in System Settings, or keep using reliable Format mode."
        case .deviceNotEligible:
            "Smart Content requires macOS 26 and an Apple Intelligence-eligible Mac. Format mode remains fully available."
        case .modelNotReady:
            "The model may still be downloading or temporarily unavailable. Format mode remains fully available."
        case .unknown:
            "FileMorrow could not confirm model availability. Format mode remains fully available."
        }
    }
}

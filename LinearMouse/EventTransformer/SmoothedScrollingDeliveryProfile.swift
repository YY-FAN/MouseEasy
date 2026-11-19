// SPDX-License-Identifier: MIT
// Copyright (c) 2026 MouseWorkbench contributors

import Foundation

/// Delivery policy is separate from the user's scroll curve and gain.
/// The mirror transport receives a single, phase-complete wheel stream.
enum SmoothedScrollingDeliveryProfile: Equatable {
    case standard
    case mirror30Hz
    case iPhoneMirroring

    var timerInterval: TimeInterval {
        switch self {
        case .standard: return 1.0 / 120.0
        case .iPhoneMirroring: return 1.0 / 60.0
        case .mirror30Hz: return 1.0 / 30.0
        }
    }

    var preservesScrollPhases: Bool { self != .standard }
    var emitsGestureCompanions: Bool { self == .standard }
    var accumulatesMomentumSubpixels: Bool { self != .standard }

}

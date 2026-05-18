import Foundation

// MARK: - Shot Context

/// Carries metadata about where a shot originated, enabling downstream views
/// (ShotResultView, ShotTrackingReviewView) to adapt their presentation.
struct ShotContext {
    enum SourceMode {
        case range
        case sim
        case course
    }

    var sourceMode: SourceMode     = .range
    var courseRoundId: UUID?       = nil
    var holeNumber: Int?           = nil
    var holePar: Int?              = nil
    var holeYardage: Int?          = nil
    var courseName: String?        = nil
    var holeHandicap: Int?         = nil

    var shotMode: ShotMode {
        switch sourceMode {
        case .range:  return .range
        case .sim:    return .sim
        case .course: return .course
        }
    }
}

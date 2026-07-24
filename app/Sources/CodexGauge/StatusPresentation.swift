import Foundation

enum StatusTone: Equatable {
    case normal
    case informational
    case warning
    case critical
    case muted
}

struct StatusPresentation: Equatable {
    let title: String
    let tone: StatusTone
}

struct StatusPresentationCache {
    private var current: StatusPresentation?

    mutating func shouldApply(_ presentation: StatusPresentation) -> Bool {
        guard current != presentation else { return false }
        current = presentation
        return true
    }
}

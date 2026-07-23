import SwiftUI

// Smartisan OS palette — color encodes status only, everything else warm grays.
enum Theme {
    static let bg        = Color(hex: 0xeef0f2)
    static let panel     = Color(hex: 0xffffff)
    static let panelSoft = Color(hex: 0xfafbfc)
    static let fg        = Color(hex: 0x181a1c)
    static let fg2       = Color(hex: 0x5f6670)
    static let fg3       = Color(hex: 0x9aa3ad)
    static let track     = Color(hex: 0xe6e9ed)
    static let border    = Color(hex: 0x141e32, alpha: 0.08)
    static let good      = Color(hex: 0x0e8a4f)
    static let info      = Color(hex: 0x2563eb)
    static let warn      = Color(hex: 0xc98a14)
    static let caution   = Color(hex: 0xb7791f)
    static let bad       = Color(hex: 0xe0411b)
    static let muted     = Color(hex: 0x7b8490)

    static func status(_ remaining: Double) -> Color {
        if remaining < 10 { return bad }
        if remaining < 30 { return warn }
        return good
    }

    static func pace(_ status: UsagePaceStatus) -> Color {
        switch status {
        case .balanced: good
        case .useMore: info
        case .wasteRisk: warn
        case .aheadOfPace: caution
        case .quotaTight: bad
        case .unknown, .expired: muted
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

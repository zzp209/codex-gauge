import Foundation

// Tiny code-based localization. Chinese is the default; English and system are options.
// Views read @AppStorage("language") so they re-render when the user switches.
struct Strings {
    let zh: Bool
    init(_ raw: String) {
        switch raw {
        case "en": zh = false
        case "zh": zh = true
        default:  zh = (Locale.current.language.languageCode?.identifier == "zh")  // system
        }
    }
    // Usage: t("Refresh", "刷新")
    func callAsFunction(_ en: String, _ zh: String) -> String { self.zh ? zh : en }
}

let LanguageKey = "language"

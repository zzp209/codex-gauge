import AppKit
import Foundation

enum UsageDestination: Equatable {
    case application(URL)
    case web(URL)
}

enum UsageDestinationResolver {
    static let cockpitToolsBundleIdentifier = "com.jlcodes.cockpit-tools"
    static let officialUsageURL = URL(
        string: "https://chatgpt.com/codex/settings/usage"
    )!

    static func preferred(
        cockpitApplicationURL: URL?
    ) -> UsageDestination {
        if let cockpitApplicationURL {
            return .application(cockpitApplicationURL)
        }
        return .web(officialUsageURL)
    }
}

@MainActor
enum UsageDestinationLauncher {
    static var isCockpitToolsInstalled: Bool {
        cockpitToolsURL != nil
    }

    @discardableResult
    static func openPreferred() -> Bool {
        let destination = UsageDestinationResolver.preferred(
            cockpitApplicationURL: cockpitToolsURL
        )
        switch destination {
        case let .application(url):
            if NSWorkspace.shared.open(url) {
                return true
            }
            return NSWorkspace.shared.open(
                UsageDestinationResolver.officialUsageURL
            )
        case let .web(url):
            return NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    static func openOfficialUsagePage() -> Bool {
        NSWorkspace.shared.open(UsageDestinationResolver.officialUsageURL)
    }

    private static var cockpitToolsURL: URL? {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier:
                UsageDestinationResolver.cockpitToolsBundleIdentifier
        )
    }
}

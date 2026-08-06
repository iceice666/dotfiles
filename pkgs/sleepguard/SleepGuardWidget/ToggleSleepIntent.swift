import AppIntents
import WidgetKit
import AppKit

struct ToggleSleepPreventionIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Sleep Prevention"
    static var description = IntentDescription("Prevents or allows your Mac to sleep.")

    func perform() async throws -> some IntentResult {
        SleepGuardShared.isEnabled.toggle()

        let extensionURL = Bundle.main.bundleURL
        let appURL = extensionURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // SleepGuard.app

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: config)

        SleepGuardShared.postToggleNotification()
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}

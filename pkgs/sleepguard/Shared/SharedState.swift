import Foundation

enum SleepGuardShared {
    static let appGroupID = "VWZB7NR2YV.group.com.iceice666.sleepguard"
    static let enabledKey = "sleepPreventionEnabled"
    static let toggleDarwinNotification = "com.iceice666.sleepguard.toggle" as CFString

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    static func postToggleNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(toggleDarwinNotification),
            nil, nil, true
        )
    }
}

import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.iceice666.sleepguard", category: "pmset")
    private let queue = DispatchQueue(label: "com.iceice666.sleepguard.pmset")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
                me.applySleepState()
            },
            SleepGuardShared.toggleDarwinNotification,
            nil,
            .deliverImmediately
        )

        applySleepState()
    }

    // Mirrors the widget state into `pmset -a disablesleep`. Requires the
    // NOPASSWD sudoers rule declared in hosts/m5pro/configuration.
    private func applySleepState() {
        let disable = SleepGuardShared.isEnabled
        queue.async { [logger] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", disable ? "1" : "0"]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    logger.info("disablesleep set to \(disable ? 1 : 0)")
                } else {
                    logger.error("pmset via sudo exited with \(process.terminationStatus)")
                }
            } catch {
                logger.error("failed to run sudo pmset: \(error.localizedDescription)")
            }
        }
    }
}

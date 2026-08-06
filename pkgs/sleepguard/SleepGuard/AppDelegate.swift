import AppKit
import IOKit.pwr_mgt

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var assertionID: IOPMAssertionID = 0
    private var isAsserting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
                me.syncAssertionState()
            },
            SleepGuardShared.toggleDarwinNotification,
            nil,
            .deliverImmediately
        )

        syncAssertionState()
    }

    private func syncAssertionState() {
        let shouldAssert = SleepGuardShared.isEnabled
        guard shouldAssert != isAsserting else { return }

        if shouldAssert {
            let reason = "SleepGuard enabled by user" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            isAsserting = (result == kIOReturnSuccess)
        } else {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isAsserting = false
        }
    }
}

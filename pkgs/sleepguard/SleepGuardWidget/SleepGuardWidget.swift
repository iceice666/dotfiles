import WidgetKit
import SwiftUI

struct SleepGuardEntry: TimelineEntry {
    let date: Date
    let isEnabled: Bool
}

struct SleepGuardProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepGuardEntry {
        SleepGuardEntry(date: Date(), isEnabled: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepGuardEntry) -> Void) {
        completion(SleepGuardEntry(date: Date(), isEnabled: SleepGuardShared.isEnabled))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepGuardEntry>) -> Void) {
        let entry = SleepGuardEntry(date: Date(), isEnabled: SleepGuardShared.isEnabled)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct SleepGuardWidgetEntryView: View {
    let entry: SleepGuardEntry

    var body: some View {
        Button(intent: ToggleSleepPreventionIntent()) {
            VStack(spacing: 8) {
                Image(systemName: entry.isEnabled ? "eye.fill" : "moon.zzz.fill")
                    .font(.system(size: 28))
                Text(entry.isEnabled ? "Sleep Prevented" : "Sleep Allowed")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) {
            if entry.isEnabled {
                Color.green.opacity(0.25)
            } else {
                Color.clear
            }
        }
    }
}

struct SleepGuardWidget: Widget {
    let kind = "SleepGuardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepGuardProvider()) { entry in
            SleepGuardWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sleep Guard")
        .description("Tap to toggle whether your Mac is allowed to sleep.")
        .supportedFamilies([.systemSmall])
    }
}

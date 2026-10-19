import HouseCatCore
import HouseCatStore
import HouseCatUI
import SwiftUI
import UserNotifications
#if canImport(UIKit)
    import UIKit
#endif

/// Reminders, the widget and the weather's source, from the cat's profile (SPEC "Notifications": local only,
/// at the player's own times; WeatherKit's attribution goes wherever its weather is credited).
struct SettingsView: View {
    let catName: String
    var store: (any EntitlementService)?
    let close: () -> Void
    @State private var settings = Reminders.settings
    @State private var status: UNAuthorizationStatus?
    @State private var attribution = RealWeather.attribution
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    PaintedIcon("bell_for_notifications", size: 36)
                    Text("Settings").font(Theme.title(28))
                }
                reminders
                MusicCard()
                if HealthLayer.isAvailable {
                    HealthSettingsCard()
                }
                if Analytics.isAvailable {
                    AnalyticsCard()
                }
                // Co-owning needs the app's iCloud container (HouseholdSync.isEnabled); until it is on, the card is
                // not shown at all rather than promising something that cannot work (App Review 2.1).
                if HouseholdSync.isEnabled {
                    CoOwnCard(catName: catName)
                }
                PurchasesCard(store: store)
                YourDataCard(catName: catName, deleted: close)
                WidgetGuide(catName: catName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
                weather
            }
            .padding(24)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .overlay(alignment: .topTrailing) { CloseButton(action: close).padding(16) }
        .task {
            status = await Reminders.status()
            await RealWeather.loadAttribution()
            attribution = RealWeather.attribution
        }
        .onChange(of: settings) { _, settings in
            Reminders.settings = settings
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(catName) can remind you. Only at these times, and only from this device.")
                .font(.subheadline).foregroundStyle(Theme.inkSoft)
            if status == .notDetermined || status == .denied {
                HStack {
                    Text("Notifications are off for HouseCat.").font(.subheadline.weight(.semibold))
                    Spacer()
                    // Never asked: iOS asks now. Turned down: only Settings can turn them on.
                    HUDButton(status == .denied ? "Open Settings" : "Allow", symbol: "bell") {
                        if status == .denied {
                            #if canImport(UIKit)
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    openURL(url)
                                }
                            #endif
                        } else {
                            Task {
                                await Reminders.ask()
                                status = await Reminders.status()
                            }
                        }
                    }
                }
            }
            row("Breakfast", detail: "When the bowl is still empty", on: $settings.breakfast, minutes: $settings.breakfastMinutes)
            row("Presents", detail: "When \(catName) brings you something", on: $settings.gifts, minutes: nil)
            row("Evening", detail: "If you haven't visited yet", on: $settings.evening, minutes: $settings.eveningMinutes)
        }
        .padding(16)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func row(_ title: String, detail: String, on: Binding<Bool>, minutes: Binding<Int>?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if let minutes, on.wrappedValue {
                DatePicker("", selection: time(minutes), displayedComponents: .hourAndMinute).labelsHidden()
            }
            Toggle("", isOn: on).labelsHidden().tint(Theme.accent)
        }
    }

    /// Minutes after midnight as a time of day for the picker.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(
                bySettingHour: minutes.wrappedValue / 60,
                minute: minutes.wrappedValue % 60,
                second: 0,
                of: Date()
            ) ?? Date() },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    /// WeatherKit's attribution: Apple's mark and the legal page.
    private var weather: some View {
        HStack(spacing: 10) {
            Text("The weather outside comes from").font(.caption).foregroundStyle(Theme.inkSoft)
            if let attribution {
                AsyncImage(url: attribution.mark) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text("\u{F8FF} Weather").font(.caption.weight(.semibold))
                }
                .frame(height: 14)
                Link("Sources", destination: attribution.legal).font(.caption.weight(.semibold)).tint(Theme.accent)
            } else {
                Text("\u{F8FF} Weather").font(.caption.weight(.semibold))
                Link("Sources", destination: Tuning.Store.weatherLegalURL).font(.caption.weight(.semibold)).tint(Theme.accent)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// How to put the cat on the Home Screen (SPEC: the widget guide in onboarding and at the day-3 moment).
struct WidgetGuide: View {
    let catName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Put \(catName) on your Home Screen").font(.headline)
            step(1, "Touch and hold an empty part of your Home Screen.")
            step(2, "Tap Edit, then Add Widget.")
            step(3, "Find HouseCat and choose a size. The medium one has Feed and Pet.")
            Text("Feeding or petting from the widget counts as your visit for the day.")
                .font(.caption).foregroundStyle(Theme.inkSoft)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)").font(.system(size: 13, weight: .heavy, design: .rounded))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent.opacity(0.18)))
            Text(text).font(.subheadline)
        }
    }
}

/// After the first feed: may the cat send reminders? (Josh, 18 Oct: permission priming in the cat's voice.) It
/// shows a reminder as it would arrive, with a real line from the cat, before iOS asks; Not now asks nothing.
struct RemindersCard: View {
    let catName: String
    let done: () -> Void
    @State private var sample: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PaintedIcon("bell_for_notifications", size: 34)
                Text("Shall \(catName) remind you?").font(Theme.title(22))
            }
            NotificationPreview(title: catName, message: sample ?? "Breakfast? The bowl is looking very empty from here.")
            Text(
                "Like this: at breakfast if the bowl is empty, and when there's a present waiting. Only at the times you pick; change them any time from \(catName)'s profile."
            )
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer()
                HUDButton("Not now", action: done)
                HUDButton("Remind me", icon: "bell_for_notifications", prominent: true) {
                    Task {
                        await Reminders.ask()
                        done()
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 480)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            Reminders.asked = true
            let session = GameSession.shared
            sample = session.reminderLine("feed.nag_morning", id: "preview", at: session.now())
        }
    }
}

/// A notification as iOS shows it on the Lock Screen: the app's picture, its name and the time, the cat's name
/// and its line.
struct NotificationPreview: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PaintedIcon("cat_face", size: 30)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.cream))
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("now").font(.caption).foregroundStyle(.secondary)
                }
                Text(message).font(.subheadline).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A sample reminder from \(title): \(message)")
    }
}

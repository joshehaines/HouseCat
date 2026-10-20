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
            // Named for VoiceOver (it read an empty switch), the name hidden on screen beside its own words.
            Toggle(title, isOn: on).labelsHidden().tint(Theme.accent)
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

/// How to put the cat on the Home Screen (SPEC: the widget guide in onboarding and at the day-3 moment): Show me
/// how plays the steps on a little Home Screen, as the add-widget card does (`WidgetHowTo`); once the widget is
/// there it says so.
struct WidgetGuide: View {
    let catName: String
    @State private var showing = false
    @State private var installed = false
    @State private var entry: WidgetEntry?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(installed ? "\(catName) is on your Home Screen" : "Put \(catName) on your Home Screen").font(.headline)
                Spacer()
                if installed {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                } else if !showing {
                    HUDButton("Show me how", icon: "house") {
                        withAnimation(.spring(duration: 0.35)) { showing = true }
                    }
                }
            }
            if showing, !installed {
                WidgetHowTo(entry: entry)
                    .transition(.opacity)
                    .task { entry = await WidgetPrompt.previewEntry() }
            }
            Text("The medium widget has Feed and Pet. Feeding or petting from the widget counts as your visit for the day.")
                .font(.caption).foregroundStyle(Theme.inkSoft)
        }
        .task(id: phase) {
            if phase == .active {
                installed = await WidgetPrompt.installed()
            }
        }
    }
}

/// After the first feed: may the cat send reminders? (Josh, 18 Oct: permission priming in the cat's voice.) It
/// shows a reminder as it would arrive, with a real line from the cat, before iOS asks; Not now asks nothing.
/// Redrawn as a card that stands out from the room (Josh, 19 Oct: it faded into the light floor and looked plain):
/// a warm header with the bell, the sample reminder on a dusk-blue "Lock Screen", what it is for in three lines,
/// and one big button.
struct RemindersCard: View {
    let catName: String
    let done: () -> Void
    @State private var sample: String?
    @State private var ringing = false
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 14) {
                NotificationPreview(
                    title: catName,
                    message: sample ?? "Breakfast? The bowl is looking very empty from here."
                )
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.25, green: 0.33, blue: 0.5), Color(red: 0.45, green: 0.36, blue: 0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
                VStack(alignment: .leading, spacing: 8) {
                    reason("feed_bowl", "At breakfast, if the bowl is still empty")
                    reason("gift_box_with_a_ribbon", "When \(catName) has a present waiting for you")
                    reason("clock", "Only at the times you pick, never more")
                }
                HStack(spacing: 12) {
                    Button("Not now") {
                        feedback.tap()
                        done()
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 12)
                    Spacer(minLength: 0)
                    ChunkyButton("Remind me") {
                        Task {
                            await Reminders.ask()
                            done()
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(maxWidth: 500)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.cream))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom), lineWidth: 4)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .onAppear {
            Reminders.asked = true
            let session = GameSession.shared
            sample = session.reminderLine("feed.nag_morning", id: "preview", at: session.now())
            withAnimation(.easeInOut(duration: 0.12).repeatCount(5, autoreverses: true).delay(0.4)) { ringing = true }
        }
    }

    /// The bell, swinging as the card arrives, and the question, on a warm band.
    private var header: some View {
        HStack(spacing: 14) {
            PaintedIcon("bell_for_notifications", size: 56)
                .rotationEffect(.degrees(ringing ? 14 : -10), anchor: .top)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shall \(catName) remind you?")
                    .font(Theme.title(26))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A nudge now and then, in \(catName)'s own words.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.accent, GameHUD.deepGold], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func reason(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            PaintedIcon(icon, size: 26)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
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

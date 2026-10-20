import HouseCatCore
import HouseCatUI
import SwiftUI
import WidgetKit
#if canImport(UIKit)
    import UIKit
#endif

/// Whether the add-widget card has asked, a device preference (each phone has its own Home Screen).
@MainActor
enum WidgetPrompt {
    private static let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard

    static var asked: Set<String> {
        get { Set(defaults.stringArray(forKey: "widget.prompt.asked") ?? []) }
        set { defaults.set(Array(newValue), forKey: "widget.prompt.asked") }
    }

    /// Whether a HouseCat widget is on this phone already.
    static func installed() async -> Bool {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                let found = (try? result.get())?.contains { $0.kind == "HouseCatWidget" } ?? false
                continuation.resume(returning: found)
            }
        }
    }

    /// The ask due now, marked as asked, or nil.
    static func take(_ state: HouseholdState) async -> WidgetPromptRules.Ask? {
        var due = WidgetPromptRules.due(state, asked: asked, installed: await installed())
        #if DEBUG
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "addwidget" {
                due = .firstFeed
            }
        #endif
        if let due {
            asked.insert(due.rawValue)
            var stage = WidgetPromptCard.Stage.ask
            #if DEBUG
                // HOUSECAT_SCREEN=addwidget with HOUSECAT_WIDGET_STAGE=guide|added: the card at that stage.
                switch ProcessInfo.processInfo.environment["HOUSECAT_WIDGET_STAGE"] {
                case "guide": stage = .guide
                case "added": stage = .added
                default: break
                }
            #endif
            WidgetPromptFlow.shared.stage = stage
        }
        return due
    }

    /// The player's own small widget as the widget draws it, from what the app left for it in the App Group (made
    /// in the background for this cat and home: waits for it a little).
    static func previewEntry() async -> WidgetEntry? {
        WidgetBridge.publish()
        for _ in 0 ..< 20 {
            if let world = WidgetWorld.load(), world.kit != nil, let scene = world.scenes(from: .now).first {
                return WidgetEntry(date: scene.state.date, scene: scene, catName: world.catName, caption: world.caption(scene), kit: world.kit)
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
        return nil
    }
}

/// Where the add-widget card is (asking, the steps, or added), kept outside the card: the room shows a card both as
/// it is and in a scroll view (`ViewThatFits`), two copies, and swaps to the other when the card grows (the steps on
/// a phone), so a step kept in the card went back to the question.
@MainActor
@Observable
final class WidgetPromptFlow {
    static let shared = WidgetPromptFlow()
    var stage = WidgetPromptCard.Stage.ask
}

/// Putting the cat on the Home Screen (Josh, 18 Oct; Liven's add-widget prompt): the player's own cat in their
/// own window, drawn by the widget's views from what the app left for it.
///
/// Josh, 20 Oct: "When asking about a widget, make it an option to do right away like the notifications - add to
/// Home Screen". iOS lets no app put a widget on the Home Screen itself (WidgetKit can only read and reload the
/// widgets a person has added; there is no system add-widget sheet, unlike notifications' permission prompt), so Add
/// to Home Screen goes straight into the steps, played on a little Home Screen (`WidgetHowTo`), and when the player
/// comes back with the widget there, the card says so.
struct WidgetPromptCard: View {
    let catName: String
    let close: () -> Void
    @State private var entry: WidgetEntry?
    @Environment(\.scenePhase) private var phase
    @Environment(\.controlFeedback) private var feedback

    enum Stage {
        case ask, guide, added
    }

    private var flow: WidgetPromptFlow {
        WidgetPromptFlow.shared
    }

    private var stage: Stage {
        flow.stage
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch stage {
                case .ask: ask
                case .guide: guide
                case .added: added
                }
            }
            .padding(18)
            .transition(.opacity)
        }
        .frame(maxWidth: 640)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.cream))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom), lineWidth: 4)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .animation(.spring(duration: 0.35), value: stage)
        .task {
            entry = await WidgetPrompt.previewEntry()
        }
        .onChange(of: phase) { _, phase in
            // Back from the Home Screen: if the widget is there now, say so.
            guard phase == .active, stage == .guide else { return }
            Task {
                if await WidgetPrompt.installed() {
                    flow.stage = .added
                }
            }
        }
    }

    /// The question, on a warm band, as the reminders card asks it.
    private var header: some View {
        HStack(spacing: 14) {
            PaintedIcon(stage == .added ? "trust_heart_with_a_paw_print" : "house", size: 50)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.title(24))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.accent, GameHUD.deepGold], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var title: String {
        switch stage {
        case .ask: "Keep \(catName) on your Home Screen"
        case .guide: "Add \(catName) in four taps"
        case .added: "\(catName) is on your Home Screen"
        }
    }

    private var subtitle: String {
        switch stage {
        case .ask: "Your window, your weather, and \(catName) waiting for you."
        case .guide: "Go to your Home Screen and do as the finger does."
        case .added: "Feed and stroke from there whenever you like."
        }
    }

    private var ask: some View {
        HStack(alignment: .center, spacing: 18) {
            preview
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    reason("house", "\(catName) in your own window, with your real weather")
                    reason("feed_bowl", "Feed and stroke without opening the app")
                    reason("streak_paw_print_with_a_small_flame", "Your streak, always in sight")
                }
                HStack(spacing: 10) {
                    Button("Not now") {
                        feedback.tap()
                        close()
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 6)
                    .accessibilityIdentifier("widgetNotNow")
                    Spacer(minLength: 0)
                    ChunkyButton("Add to Home Screen") { flow.stage = .guide }
                }
            }
        }
    }

    private var guide: some View {
        WidgetHowTo(entry: entry, footer: AnyView(VStack(alignment: .leading, spacing: 8) {
            Text("Swipe up to your Home Screen to start. \(catName) will be here when you come back.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Not now") {
                    feedback.tap()
                    close()
                }
                .font(.headline)
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 6)
                ChunkyButton("Got it", action: close)
            }
        }))
    }

    private var added: some View {
        HStack(alignment: .center, spacing: 18) {
            preview
            VStack(alignment: .leading, spacing: 14) {
                Text("A stroke or a meal from the widget counts as your visit for the day, so your streak keeps going.")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer(minLength: 0)
                    ChunkyButton("Lovely", action: close)
                }
            }
        }
    }

    /// The player's own small widget on a bit of wallpaper.
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: WidgetHowTo.wallpaper, startPoint: .top, endPoint: .bottom))
            if let entry {
                HouseCatWidgetView(entry: entry, family: .systemSmall)
                    .frame(width: 150, height: 150)
                    .background(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(width: 186, height: 186)
        .animation(.spring(duration: 0.45), value: entry != nil)
        .accessibilityLabel("How the widget looks with \(catName)")
    }

    private func reason(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            PaintedIcon(icon, size: 26)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How to add the widget, played on a little Home Screen beside the four steps, the step being shown lit: a finger
/// holds an empty spot until the icons jiggle, taps Edit and Add Widget, searches for HouseCat, picks it and taps Add
/// Widget, and the player's own widget drops into place. It goes round every `loop` seconds. The steps are iOS 26's
/// (an iPad's Home Screen is drawn on an iPad). Reduce Motion keeps the icons still.
struct WidgetHowTo: View {
    let entry: WidgetEntry?
    /// Under the steps, beside the film (the card's buttons).
    var footer: AnyView?
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let wallpaper = [Color(red: 0.42, green: 0.56, blue: 0.7), Color(red: 0.62, green: 0.5, blue: 0.66)]
    static let steps = [
        "Touch and hold an empty spot on your Home Screen until the apps jiggle.",
        "Tap Edit at the top, then Add Widget.",
        "Search for HouseCat and tap it.",
        "Pick a size, then tap Add Widget.",
    ]
    /// When each step starts and when the loop ends (seconds).
    private static let stepStarts: [Double] = [0, 2.3, 4.2, 7.1]
    private static let loop = 14.0

    private var pad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            TimelineView(.animation) { context in
                HomeScreenFilm(t: time(context.date), entry: entry, pad: pad, still: reduceMotion)
            }
            .frame(width: pad ? 300 : 104, height: pad ? 218 : 212)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                TimelineView(.periodic(from: start, by: 0.2)) { context in
                    let t = time(context.date)
                    let current = Self.stepStarts.lastIndex { t >= $0 } ?? 0
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Self.steps.indices, id: \.self) { index in
                            step(index, lit: index == current && t < 10.6, done: index < current || t >= 10.6)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.steps.enumerated().map { "Step \($0.offset + 1): \($0.element)" }.joined(separator: " "))
                .accessibilityIdentifier("widgetHowTo")
                if let footer {
                    footer.padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Seconds into the film's loop.
    private func time(_ date: Date) -> Double {
        date.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.loop)
    }

    private func step(_ index: Int, lit: Bool, done: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ZStack {
                Circle().fill(lit ? Theme.accent : done ? Theme.accent.opacity(0.35) : Theme.ink.opacity(0.12))
                if done, !lit {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                } else {
                    Text("\(index + 1)").font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(lit ? .white : Theme.ink)
                }
            }
            .frame(width: 22, height: 22)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(Self.steps[index])
                .font(.subheadline.weight(lit ? .bold : .medium))
                .foregroundStyle(lit ? Theme.ink : Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? Theme.accent.opacity(0.13) : .clear))
        .animation(.easeOut(duration: 0.2), value: lit)
    }
}

/// One frame of the little Home Screen at `t` seconds into the guide (see `WidgetHowTo`).
private struct HomeScreenFilm: View {
    let t: Double
    let entry: WidgetEntry?
    let pad: Bool
    let still: Bool

    // Moments in the film (seconds).
    private let holdAt = 0.9, jiggleAt = 2.0, editAt = 2.9, menuAt = 3.1, addAt = 4.0, sheetAt = 4.2, searchAt = 4.9,
                typeFrom = 5.1, typeTo = 6.2, rowAt = 6.3, pickAt = 7.0, pageAt = 7.2, addWidgetAt = 9.1, dropAt = 9.3,
                doneAt = 10.4, fadeAt = 13.2

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let corner = size.width * (pad ? 0.06 : 0.16)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: WidgetHowTo.wallpaper, startPoint: .top, endPoint: .bottom)
                icons(size)
                widgetSlot(size)
                editBar(size)
                menu(size)
                sheet(size)
                finger(size)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Theme.ink.opacity(0.85), lineWidth: pad ? 5 : 4))
            .opacity(t > fadeAt ? max(0, 1 - (t - fadeAt) / 0.5) : 1)
        }
    }

    // MARK: Where things are, as fractions of the screen

    private var columns: Int {
        pad ? 6 : 4
    }

    private var rows: Int {
        pad ? 3 : 5
    }

    private func iconSize(_ size: CGSize) -> CGFloat {
        size.width * (pad ? 0.085 : 0.16)
    }

    private func cell(_ column: Int, _ row: Int, _ size: CGSize) -> CGPoint {
        if pad {
            return CGPoint(x: size.width * (0.14 + Double(column) * 0.145), y: size.height * (0.2 + Double(row) * 0.22))
        }
        return CGPoint(x: size.width * (0.16 + Double(column) * 0.227), y: size.height * (0.13 + Double(row) * 0.118))
    }

    /// The widget's place: the top-left two by two, left empty for it.
    private func slot(_ size: CGSize) -> CGRect {
        let a = cell(0, 0, size), b = cell(1, 1, size), half = iconSize(size) / 2
        return CGRect(x: a.x - half, y: a.y - half, width: b.x - a.x + 2 * half, height: b.y - a.y + 2 * half)
    }

    private var editing: Bool {
        t >= jiggleAt && t < doneAt
    }

    private static let colours: [Color] = [
        Color(red: 0.98, green: 0.62, blue: 0.4), Color(red: 0.45, green: 0.75, blue: 0.7), Color(red: 0.95, green: 0.55, blue: 0.62),
        Color(red: 0.5, green: 0.55, blue: 0.85), Color(red: 0.55, green: 0.78, blue: 0.45), Color(red: 0.98, green: 0.82, blue: 0.4),
        Color(red: 0.62, green: 0.82, blue: 0.95), Color(red: 0.75, green: 0.55, blue: 0.85),
    ]

    private struct Spot: Identifiable {
        var column: Int
        var row: Int
        var id: Int
    }

    private func icons(_ size: CGSize) -> some View {
        let side = iconSize(size)
        var spots: [Spot] = []
        for row in 0 ..< rows {
            for column in 0 ..< columns where !(row < 2 && column < 2) {
                spots.append(Spot(column: column, row: row, id: spots.count))
            }
        }
        let houseCat = pad ? 7 : 4
        return ZStack(alignment: .topLeading) {
            ForEach(spots) { spot in
                appIcon(spot.id == houseCat ? nil : Self.colours[spot.id % Self.colours.count], side: side)
                    .rotationEffect(.degrees(wiggle(spot.id)))
                    .position(cell(spot.column, spot.row, size))
            }
            // The dock.
            let dockY = size.height * (pad ? 0.9 : 0.915)
            RoundedRectangle(cornerRadius: side * 0.45, style: .continuous)
                .fill(.white.opacity(0.28))
                .frame(width: size.width * (pad ? 0.5 : 0.88), height: side * 1.4)
                .position(x: size.width / 2, y: dockY)
            ForEach(0 ..< 4, id: \.self) { index in
                let span = size.width * (pad ? 0.11 : 0.205)
                appIcon(Self.colours[(index + 3) % Self.colours.count], side: side)
                    .rotationEffect(.degrees(wiggle(index + 20)))
                    .position(x: size.width / 2 + (Double(index) - 1.5) * span, y: dockY)
            }
        }
    }

    /// An app's icon; nil is HouseCat's own (the cat's face on cream).
    private func appIcon(_ colour: Color?, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
            .fill(colour.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Theme.cream))
            .frame(width: side, height: side)
            .overlay {
                if colour == nil {
                    PaintedIcon("cat_face", size: side * 0.8)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
    }

    private func wiggle(_ index: Int) -> Double {
        guard editing, !still else { return 0 }
        return sin(t * 22 + Double(index) * 1.7) * 2.6
    }

    /// The player's widget, dropping into its place once added.
    @ViewBuilder
    private func widgetSlot(_ size: CGSize) -> some View {
        if t >= dropAt {
            let rect = slot(size)
            let pop = min(1, (t - dropAt) / 0.35)
            widget(side: rect.width)
                .scaleEffect(0.6 + 0.4 * ease(pop) + (pop < 1 ? 0.06 * sin(pop * .pi) : 0))
                .rotationEffect(.degrees(t < doneAt ? wiggle(99) : 0))
                .opacity(pop)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    private func widget(side: CGFloat) -> some View {
        Group {
            if let entry {
                HouseCatWidgetView(entry: entry, family: .systemSmall)
                    .frame(width: 150, height: 150)
                    .background(Theme.paper)
                    .scaleEffect(side / 150)
                    .frame(width: side, height: side)
            } else {
                Theme.paper.overlay { PaintedIcon("cat_face", size: side * 0.5) }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.16, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }

    /// Edit and Done along the top while the apps jiggle.
    @ViewBuilder
    private func editBar(_ size: CGSize) -> some View {
        if editing {
            let font = size.width * (pad ? 0.03 : 0.075)
            pill("Edit", font: font, lit: t >= editAt - 0.6 && t < menuAt)
                .position(editPoint(size))
            pill("Done", font: font, lit: t >= doneAt - 0.6)
                .position(donePoint(size))
        }
    }

    private func editPoint(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (pad ? 0.07 : 0.15), y: size.height * (pad ? 0.06 : 0.045))
    }

    private func donePoint(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (pad ? 0.93 : 0.85), y: size.height * (pad ? 0.06 : 0.045))
    }

    private func pill(_ text: String, font: CGFloat, lit: Bool) -> some View {
        Text(text)
            .font(.system(size: font, weight: .semibold))
            .foregroundStyle(lit ? Theme.ink : .white)
            .padding(.horizontal, font * 0.7)
            .padding(.vertical, font * 0.25)
            .background(Capsule().fill(.white.opacity(lit ? 0.95 : 0.35)))
    }

    /// Edit's menu: Add Widget first.
    @ViewBuilder
    private func menu(_ size: CGSize) -> some View {
        if t >= menuAt, t < sheetAt + 0.2 {
            let font = size.width * (pad ? 0.026 : 0.068)
            VStack(alignment: .leading, spacing: font * 0.55) {
                menuRow("plus.square", "Add Widget", font: font, lit: t >= addAt - 0.5)
                menuRow("paintbrush", "Customise", font: font, lit: false)
                menuRow("square.grid.3x3", "Edit Pages", font: font, lit: false)
            }
            .padding(font * 0.6)
            .background(RoundedRectangle(cornerRadius: font, style: .continuous).fill(.white.opacity(0.95)))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .fixedSize()
            .scaleEffect(min(1, (t - menuAt) / 0.2), anchor: .topLeading)
            .position(menuPoint(size))
        }
    }

    private func menuPoint(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (pad ? 0.16 : 0.42), y: size.height * (pad ? 0.24 : 0.16))
    }

    private func addRowPoint(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (pad ? 0.12 : 0.3), y: size.height * (pad ? 0.135 : 0.105))
    }

    private func menuRow(_ symbol: String, _ title: String, font: CGFloat, lit: Bool) -> some View {
        HStack(spacing: font * 0.4) {
            Image(systemName: symbol).font(.system(size: font, weight: .semibold))
            Text(title).font(.system(size: font, weight: lit ? .bold : .regular))
        }
        .foregroundStyle(lit ? Theme.accent : Theme.ink.opacity(0.75))
    }

    /// The widget gallery: up from the bottom on a phone, in the middle of an iPad.
    @ViewBuilder
    private func sheet(_ size: CGSize) -> some View {
        if t >= sheetAt, t < dropAt {
            let rect = sheetRect(size)
            let rise = t < pageAt ? ease(min(1, (t - sheetAt) / 0.35)) : 1
            let fall = t >= addWidgetAt ? ease(min(1, (t - addWidgetAt) / 0.2)) : 0
            let offset = (1 - rise + fall) * (size.height - rect.minY)
            let font = size.width * (pad ? 0.028 : 0.07)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: font * 1.2, style: .continuous).fill(Color(white: 0.96))
                if t < pageAt {
                    gallery(rect.size, font: font)
                } else {
                    sizes(rect.size, font: font)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .shadow(color: .black.opacity(0.25), radius: 4, y: -1)
            .position(x: rect.midX, y: rect.midY + offset)
        }
    }

    private func sheetRect(_ size: CGSize) -> CGRect {
        if pad {
            return CGRect(x: size.width * 0.25, y: size.height * 0.1, width: size.width * 0.5, height: size.height * 0.84)
        }
        return CGRect(x: 0, y: size.height * 0.17, width: size.width, height: size.height * 0.83)
    }

    /// The search field typing HouseCat, then HouseCat's row.
    private func gallery(_ size: CGSize, font: CGFloat) -> some View {
        let typed = String("HouseCat".prefix(Int(((t - typeFrom) / (typeTo - typeFrom) * 8).rounded(.down)).clamped(0, 8)))
        return VStack(alignment: .leading, spacing: font * 0.8) {
            Capsule().fill(Theme.ink.opacity(0.2)).frame(width: font * 2.2, height: font * 0.25).frame(maxWidth: .infinity)
            HStack(spacing: font * 0.3) {
                Image(systemName: "magnifyingglass")
                Text(typed.isEmpty ? "Search Widgets" : typed)
                    .foregroundStyle(typed.isEmpty ? Theme.ink.opacity(0.4) : Theme.ink)
                Spacer(minLength: 0)
            }
            .font(.system(size: font))
            .padding(.horizontal, font * 0.5)
            .frame(height: font * 1.8)
            .background(RoundedRectangle(cornerRadius: font * 0.5, style: .continuous).fill(Theme.ink.opacity(0.08)))
            if t >= rowAt {
                HStack(spacing: font * 0.5) {
                    appIcon(nil, side: font * 2.2)
                    Text("HouseCat").font(.system(size: font * 1.05, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: font * 0.8, weight: .bold)).foregroundStyle(Theme.ink.opacity(0.35))
                }
                .padding(font * 0.35)
                .background(RoundedRectangle(cornerRadius: font * 0.6, style: .continuous).fill(t >= pickAt - 0.15 ? Theme.accent.opacity(0.18) : .clear))
                .transition(.opacity)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(font * 0.7)
    }

    /// HouseCat's sizes: the small one, the page dots and Add Widget.
    private func sizes(_ size: CGSize, font: CGFloat) -> some View {
        VStack(spacing: font * 0.7) {
            Capsule().fill(Theme.ink.opacity(0.2)).frame(width: font * 2.2, height: font * 0.25)
            Text("HouseCat").font(.system(size: font * 1.1, weight: .bold))
            widget(side: min(size.width * 0.52, size.height * 0.42))
            HStack(spacing: font * 0.35) {
                ForEach(0 ..< 3, id: \.self) { dot in
                    Circle().fill(Theme.ink.opacity(dot == 0 ? 0.7 : 0.2)).frame(width: font * 0.4, height: font * 0.4)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: font * 0.3) {
                Image(systemName: "plus.circle.fill")
                Text("Add Widget")
            }
            .font(.system(size: font, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size.width * 0.72, height: font * 2)
            .background(Capsule().fill(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(t >= addWidgetAt - 0.15 ? 0.75 : 1)))
            .padding(.bottom, font * 1.2)
        }
        .foregroundStyle(Theme.ink)
        .padding(.top, font * 0.7)
    }

    private func addWidgetPoint(_ size: CGSize) -> CGPoint {
        let rect = sheetRect(size)
        let font = size.width * (pad ? 0.028 : 0.07)
        return CGPoint(x: rect.midX, y: rect.maxY - font * 2.2)
    }

    // MARK: The finger

    /// Where the finger is at `t`, whether it is pressing, and whether it shows.
    private func fingerState(_ size: CGSize) -> (point: CGPoint, pressing: Bool, shown: Bool) {
        let empty = CGPoint(x: slot(size).midX, y: slot(size).midY)
        let rect = sheetRect(size)
        let font = size.width * (pad ? 0.028 : 0.07)
        let search = CGPoint(x: rect.midX, y: rect.minY + font * 2.6)
        let row = CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + font * 5.3)
        // (time it arrives, place, pressed from arrival until)
        let path: [(Double, CGPoint, Double)] = [
            (holdAt, empty, jiggleAt + 0.1),
            (editAt, editPoint(size), editAt + 0.15),
            (addAt, addRowPoint(size), addAt + 0.15),
            (searchAt, search, searchAt + 0.15),
            (pickAt, row, pickAt + 0.15),
            (addWidgetAt, addWidgetPoint(size), addWidgetAt + 0.15),
            (doneAt, donePoint(size), doneAt + 0.15),
        ]
        guard t >= holdAt - 0.4, t < doneAt + 0.6 else { return (empty, false, false) }
        var from = CGPoint(x: empty.x + size.width * 0.15, y: empty.y + size.height * 0.2)
        var leave = holdAt - 0.4
        for (arrive, point, until) in path {
            if t < arrive {
                let travel = ease(min(1, max(0, (t - leave) / max(0.01, arrive - leave))))
                return (CGPoint(x: from.x + (point.x - from.x) * travel, y: from.y + (point.y - from.y) * travel), false, true)
            }
            if t < until {
                return (point, true, true)
            }
            from = point
            // Stays a moment, then sets off for the next place.
            leave = until + 0.15
        }
        return (from, false, t < doneAt + 0.5)
    }

    @ViewBuilder
    private func finger(_ size: CGSize) -> some View {
        let state = fingerState(size)
        if state.shown {
            let side = size.width * (pad ? 0.05 : 0.13)
            let holding = t >= holdAt && t < jiggleAt + 0.1
            ZStack {
                if holding {
                    // The hold: a ring grows until the apps jiggle.
                    Circle()
                        .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                        .frame(width: side * (1 + 1.2 * (t - holdAt) / (jiggleAt - holdAt)), height: side * (1 + 1.2 * (t - holdAt) / (jiggleAt - holdAt)))
                }
                Circle()
                    .fill(.white.opacity(0.75))
                    .overlay(Circle().strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1))
                    .frame(width: side, height: side)
                    .scaleEffect(state.pressing ? 0.82 : 1)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            }
            .position(state.point)
        }
    }

    private func ease(_ x: Double) -> Double {
        x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }
}

private extension Int {
    func clamped(_ low: Int, _ high: Int) -> Int {
        Swift.min(high, Swift.max(low, self))
    }
}

import HouseCatCore
import HouseCatUI
import SpriteKit
import SwiftUI

/// The Mac menu-bar cat (SPEC "Mac menu-bar cat"): the cat in its room in the menu bar, Feed and Stroke (each
/// counts as the day's visit), what the cat says back, the streak and whether it is fed, About and Quit.
@main
struct HouseCatMacApp: App {
    var body: some Scene {
        MenuBarExtra("HouseCat", systemImage: "cat.fill") {
            MenuBarCat()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarCat: View {
    @State private var line: String?
    @State private var status = MenuBarCat.status()
    @State private var scene = MenuBarCat.room()

    /// The room as the save has it now (a fed bowl shows full).
    static func room() -> SKScene {
        GameWorld.roomScene(size: CGSize(width: 420, height: 315), state: GameSession.shared.state(at: Date()), arrival: nil)
    }

    /// The streak and today's care, from the save.
    static func status() -> (name: String, streak: Int, fed: Bool, hasCat: Bool) {
        let session = GameSession.shared
        let state = session.state(at: session.now())
        let cat = state.cats.first
        return (cat?.name ?? "Your cat", state.streak.current, cat.map { state.isFedToday($0.id) } ?? false, cat != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            RoomView(scene: scene)
                .frame(width: 420, height: 315)
                .overlay(alignment: .bottom) {
                    if let line {
                        Text(line)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.cream))
                            .padding(10)
                            .transition(.opacity)
                    }
                }
            Divider()
            if status.hasCat {
                HStack(spacing: 10) {
                    Label(status.streak == 1 ? "1 day" : "\(status.streak) days", systemImage: "pawprint.fill")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button(status.fed ? "Fed" : "Feed") { feed() }
                        .disabled(status.fed)
                    Button("Stroke") { stroke() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else {
                Text("Meet your cat in HouseCat on your iPhone or iPad first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
            Divider()
            HStack {
                Button("About HouseCat") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                    NSApplication.shared.activate()
                }
                Spacer()
                Button("Quit HouseCat") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(10)
        }
        .frame(width: 420)
        .animation(.easeOut(duration: 0.25), value: line)
        .onAppear {
            status = Self.status()
            scene = Self.room()
        }
    }

    private func feed() {
        say(GameSession.shared.feed())
        scene = Self.room()
        Sound.play("ui_bean_chime", volume: Tuning.Sound.place)
    }

    private func stroke() {
        say(GameSession.shared.pet(taps: 1).line)
        Sound.play("cat_purr_loop", volume: Tuning.Sound.meow)
    }

    private func say(_ text: String?) {
        status = Self.status()
        line = text
        let shown = text
        Task {
            try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds))
            if line == shown {
                line = nil
            }
        }
    }
}

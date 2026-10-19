import HouseCatUI
import SwiftUI

/// In Settings: the background music on or off, and how loud (Shared/Sources/Music.swift), kept on this device.
struct MusicCard: View {
    @AppStorage(Music.onKey) private var on = true
    @AppStorage(Music.volumeKey) private var volume = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $on) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Music").font(.headline)
                    Text("Quiet music in the home. It stays silent while your own music plays.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
            .tint(Theme.accent)
            if on {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.caption).foregroundStyle(Theme.inkSoft)
                    Slider(value: $volume, in: 0.1 ... 1).tint(Theme.accent)
                        .accessibilityLabel("Music volume")
                    Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(16)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: on) { Music.refresh() }
        .onChange(of: volume) { Music.refresh(fade: 0.1) }
    }
}

import HouseCatCore
import HouseCatUI
import SwiftUI

/// Apple Weather's mark and the link to its data-sources page, wherever WeatherKit's weather is on screen (Apple's
/// attribution rule for WeatherKit; `HomeNow.weatherIsReal` says when the weather shown is Apple's rather than the
/// game's own): a small cream capsule, the combined mark WeatherKit hands out (" Weather" until it has loaded, or
/// offline), opening the legal page. The room shows it at the bottom, the house from outside under its town, the
/// world map on the home's card; Settings and Licences have it too, and the widget its text form.
struct WeatherMark: View {
    @Environment(\.hudScale) private var scale
    /// Words before the mark ("Raining · 9°").
    var caption: String?
    @State private var attribution = RealWeather.attribution

    var body: some View {
        Link(destination: attribution?.legal ?? Tuning.Store.weatherLegalURL) {
            HStack(spacing: 6 * scale) {
                if let caption {
                    Text(caption)
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                mark
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8 * scale, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.leading, 10 * scale)
            .padding(.trailing, 8 * scale)
            .padding(.vertical, 5 * scale)
            .paper(Capsule())
        }
        .accessibilityLabel((caption.map { "\($0). " } ?? "") + "Weather from Apple Weather. Opens Apple's weather data sources page.")
        .accessibilityIdentifier("weatherMark")
        .task {
            await RealWeather.loadAttribution()
            attribution = RealWeather.attribution
        }
    }

    /// The mark as WeatherKit gives it, else its words.
    private var mark: some View {
        Group {
            if let attribution {
                AsyncImage(url: attribution.mark) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    words
                }
            } else {
                words
            }
        }
        .frame(height: 12 * scale)
    }

    private var words: some View {
        Text("\u{F8FF} Weather")
            .font(.system(size: 11 * scale, weight: .semibold))
            .foregroundStyle(Theme.ink)
    }

    /// The home's weather now in a word, with the temperature when it is Apple's ("Raining · 9°").
    @MainActor
    static func caption(_ now: HomeNow, at date: Date) -> String {
        let name = PlaceLabels.weatherName(now.weather, sky: now.sky)
        guard now.weatherIsReal, let hour = RealWeather.report?.hour(at: date) else { return name }
        return "\(name) · \(Int(hour.temperatureC.rounded()))°"
    }
}

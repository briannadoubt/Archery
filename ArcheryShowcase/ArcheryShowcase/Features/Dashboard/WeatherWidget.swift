import SwiftUI
import Archery

// MARK: - Weather Widget

/// A compact weather widget demonstrating @APIClient usage.
/// Uses WeatherAPI (with @APIClient macro) for data fetching.
struct WeatherWidget: View {
    @State private var weather: WeatherData?
    @State private var isLoading = false
    @State private var error: Error?

    /// Location to show weather for
    let location: String

    /// Weather API client - uses the generated protocol for DI
    private let api: WeatherAPIProtocol

    init(location: String = "San Francisco", api: WeatherAPIProtocol? = nil) {
        self.location = location
        self.api = api ?? WeatherAPILive(
            retryPolicy: APIRetryPolicy(maxRetries: 2, baseDelay: .seconds(1)),
            cachePolicy: APICachePolicy(enabled: true, ttl: .seconds(300))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Weather", systemImage: "cloud.sun")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if let weather {
                HStack(spacing: 16) {
                    // Weather icon
                    Image(systemName: weather.condition.systemImage)
                        .font(.system(size: 40))
                        .symbolRenderingMode(.multicolor)

                    VStack(alignment: .leading, spacing: 4) {
                        // Temperature
                        Text("\(weather.temperature)°F")
                            .font(.title)
                            .fontWeight(.semibold)

                        // Condition
                        Text(weather.condition.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        // Location
                        Text(weather.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Details
                        HStack(spacing: 8) {
                            Label("\(weather.humidity)%", systemImage: "humidity")
                            Label("\(weather.windSpeed)mph", systemImage: "wind")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
            } else if error != nil {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Unable to load weather")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Retry") {
                        Task { await loadWeather() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack {
                    ProgressView()
                    Text("Loading weather...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await loadWeather()
        }
    }

    private func loadWeather() async {
        isLoading = true
        error = nil

        do {
            weather = try await api.currentWeather(for: location)
        } catch {
            self.error = error
        }

        isLoading = false
    }
}

// MARK: - Preview

#Preview("Weather Widget") {
    VStack(spacing: 16) {
        WeatherWidget(location: "San Francisco")
        WeatherWidget(location: "New York")
    }
    .padding()
}

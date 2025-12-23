import Archery
import Foundation

// MARK: - Weather Models

struct WeatherData: Codable, Sendable {
    let location: String
    let temperature: Int
    let condition: WeatherCondition
    let humidity: Int
    let windSpeed: Int
    let lastUpdated: Date
}

enum WeatherCondition: String, Codable, Sendable {
    case sunny
    case cloudy
    case partlyCloudy
    case rainy
    case stormy
    case snowy
    case foggy

    var systemImage: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .rainy: return "cloud.rain.fill"
        case .stormy: return "cloud.bolt.rain.fill"
        case .snowy: return "cloud.snow.fill"
        case .foggy: return "cloud.fog.fill"
        }
    }

    var description: String {
        switch self {
        case .sunny: return "Sunny"
        case .cloudy: return "Cloudy"
        case .partlyCloudy: return "Partly Cloudy"
        case .rainy: return "Rainy"
        case .stormy: return "Stormy"
        case .snowy: return "Snowy"
        case .foggy: return "Foggy"
        }
    }
}

// MARK: - Weather API

/// Demonstrates @APIClient macro for network requests.
/// The macro generates:
/// - `WeatherAPIProtocol` - Protocol for dependency injection
/// - `WeatherAPILive` - Production implementation with retry/caching
/// - `MockWeatherAPI` - Mock for testing
@APIClient
class WeatherAPI {
    /// Simulated weather data (in a real app, this would be an HTTP call)
    private static let weatherConditions: [WeatherCondition] = [
        .sunny, .partlyCloudy, .cloudy, .rainy
    ]

    func currentWeather(for location: String) async throws -> WeatherData {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)

        // Generate realistic-looking weather data
        let condition = Self.weatherConditions.randomElement() ?? .sunny
        let baseTemp: Int
        switch condition {
        case .sunny: baseTemp = 72
        case .partlyCloudy: baseTemp = 68
        case .cloudy: baseTemp = 62
        case .rainy: baseTemp = 58
        case .stormy: baseTemp = 55
        case .snowy: baseTemp = 28
        case .foggy: baseTemp = 50
        }

        return WeatherData(
            location: location,
            temperature: baseTemp + Int.random(in: -5...5),
            condition: condition,
            humidity: Int.random(in: 40...80),
            windSpeed: Int.random(in: 5...20),
            lastUpdated: Date()
        )
    }

    func forecast(for location: String, days: Int) async throws -> [WeatherData] {
        try await Task.sleep(nanoseconds: 300_000_000)

        return (0..<days).map { dayOffset in
            let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            let condition = Self.weatherConditions.randomElement() ?? .sunny
            let baseTemp: Int
            switch condition {
            case .sunny: baseTemp = 72
            case .partlyCloudy: baseTemp = 68
            case .cloudy: baseTemp = 62
            case .rainy: baseTemp = 58
            case .stormy: baseTemp = 55
            case .snowy: baseTemp = 28
            case .foggy: baseTemp = 50
            }

            return WeatherData(
                location: location,
                temperature: baseTemp + Int.random(in: -5...5),
                condition: condition,
                humidity: Int.random(in: 40...80),
                windSpeed: Int.random(in: 5...20),
                lastUpdated: date
            )
        }
    }
}

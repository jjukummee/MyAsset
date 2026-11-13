import SwiftUI
import Foundation

// MARK: - 모델

struct WeatherDay: Codable, Identifiable {
    var date: String        // "2026-06-22"
    var dayLabel: String    // "오늘", "내일", "월", "화" …
    var condition: String   // "맑음", "흐림", "비" 등
    var tempHigh: Int
    var tempLow: Int

    var id: String { date }
    var sfSymbol: String { WeatherIcon.symbol(for: condition) }
    var color: Color { WeatherIcon.color(for: condition) }
}

struct WeatherToday: Codable {
    var date: String
    var condition: String
    var tempCurrent: Int?   // 현재 기온 (선택 — 없으면 최고 기온 표시)
    var tempHigh: Int
    var tempLow: Int
    var humidity: Int?      // %
    var windSpeed: Double?  // m/s
    var uvIndex: Int?
    var description: String?

    var sfSymbol: String { WeatherIcon.symbol(for: condition) }
    var color: Color { WeatherIcon.color(for: condition) }
    var displayTemp: Int { tempCurrent ?? tempHigh }
}

struct WeatherHour: Codable, Identifiable {
    var time: String            // "01:00", "06:00", …
    var condition: String
    var temp: Int               // °C
    var precipProbability: Int  // 강수확률 %
    var humidity: Int           // 습도 %

    var id: String { time }
    var sfSymbol: String { WeatherIcon.symbol(for: condition) }
    var color: Color { WeatherIcon.color(for: condition) }
}

struct WeatherData: Codable {
    var updatedAt: String   // ISO8601 — 예: "2026-06-22T09:00:00+09:00"
    var location: String
    var today: WeatherToday
    var hourly: [WeatherHour]   // 시간별 예보 (당일 기준)
    var weekly: [WeatherDay]
}

// MARK: - 날씨 아이콘 / 색상 매핑

enum WeatherIcon {
    static func symbol(for condition: String) -> String {
        switch condition.trimmingCharacters(in: .whitespaces) {
        case "맑음":      return "sun.max.fill"
        case "구름조금":   return "cloud.sun.fill"
        case "흐림":      return "cloud.fill"
        case "비":        return "cloud.rain.fill"
        case "소나기":     return "cloud.bolt.rain.fill"
        case "눈":        return "cloud.snow.fill"
        case "안개":      return "cloud.fog.fill"
        case "천둥번개":   return "cloud.bolt.fill"
        case "황사":      return "sun.haze.fill"
        default:          return "cloud.sun.fill"
        }
    }

    static func color(for condition: String) -> Color {
        switch condition.trimmingCharacters(in: .whitespaces) {
        case "맑음":           return Theme.yellow
        case "구름조금":        return Theme.teal
        case "흐림", "안개":   return Color.gray
        case "비", "소나기":   return Theme.accent
        case "눈":             return Color.cyan
        case "천둥번개":        return Theme.purple
        case "황사":            return Theme.orange
        default:               return Theme.teal
        }
    }
}

// MARK: - 날씨 스토어

@MainActor
final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    /// 집 날씨 (weather.json)
    @Published private(set) var homeWeather:    WeatherData?
    /// 현재 위치 날씨 (weather_current.json). 없으면 homeWeather로 대체.
    @Published private(set) var currentWeather: WeatherData?
    @Published private(set) var loadError:      String?

    /// 하위 호환 — 기존 코드에서 .weather로 접근하는 경우를 위해 유지
    var weather: WeatherData? { homeWeather }

    // MARK: 파일 경로

    static var dataURL: URL {
        MyAssetFiles.directory.appendingPathComponent("weather.json")
    }

    static var currentDataURL: URL {
        MyAssetFiles.directory.appendingPathComponent("weather_current.json")
    }

    private init() { load() }

    func refresh() {
        load()
    }

    private func load() {
        loadError = nil
        homeWeather    = decode(from: Self.dataURL)
        let cur        = decode(from: Self.currentDataURL)
        // weather_current.json이 없으면 집 날씨로 대체
        currentWeather = cur ?? homeWeather
    }

    private func decode(from url: URL) -> WeatherData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(WeatherData.self, from: Data(contentsOf: url))
        } catch {
            loadError = "읽기 실패: \(error.localizedDescription)"
            return nil
        }
    }
}

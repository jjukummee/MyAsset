import SwiftUI

// MARK: - 색상

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init?(hexString: String) {
        var raw = hexString.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt(raw, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

enum Theme {
    static let accent = Color(hex: 0x007AFF)
    static let green = Color(hex: 0x34C759)
    static let red = Color(hex: 0xFF3B30)
    static let orange = Color(hex: 0xFF9500)
    static let purple = Color(hex: 0x5856D6)
    static let teal = Color(hex: 0x30B0C7)
    static let pink = Color(hex: 0xFF2D55)
    static let yellow = Color(hex: 0xFFCC00)
    static let indigo = Color(hex: 0x5E5CE6)

    static let accountPalette: [String] = [
        "#007AFF", "#34C759", "#FF9500", "#FF3B30",
        "#5856D6", "#AF52DE", "#FF2D55", "#5AC8FA",
        "#FFCC00", "#8E8E93",
    ]
}

// MARK: - 금액 포맷

func formatKRW(_ amount: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    let str = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    return str + "원"
}

func formatKRWCompact(_ amount: Int) -> String {
    let absAmount = abs(amount)
    if absAmount >= 100_000_000 {
        let v = Double(amount) / 100_000_000
        return (v == v.rounded() ? String(format: "%.0f억원", v) : String(format: "%.1f억원", v))
    }
    if absAmount >= 10_000 {
        return formatNumber(amount / 10_000) + "만원"
    }
    return formatKRW(amount)
}

func formatNumber(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
}

// MARK: - 날짜 포맷

enum DateFormat {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let monthKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    static let monthLabel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월"
        return f
    }()

    static let dayLabel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f
    }()

    static let fullDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f
    }()
}
